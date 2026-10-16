import Foundation

/// Display-only observer. Its origin never calibrates the camera or starts motion.
public struct MotionProbe: Sendable {
    public private(set) var origin: Quaternion?
    public private(set) var look: Angles?
    public private(set) var samples = 0
    public private(set) var yawSpan = 0.0
    public private(set) var pitchSpan = 0.0
    public private(set) var referenceChanged = false
    private var previous: MotionSample?
    private var yawMin = 0.0, yawMax = 0.0, pitchMin = 0.0, pitchMax = 0.0
    public init() {}
    public var movementObserved: Bool { samples >= 20 && yawSpan >= 3 && pitchSpan >= 3 && !referenceChanged }
    public mutating func reset() { self = .init() }
    public mutating func ingest(_ sample: MotionSample) {
        if let old = previous {
            let dt = sample.receivedAt-old.receivedAt
            if dt <= 0 || dt > 0.2 || sample.sensorTime <= old.sensorTime ||
                ((try? sample.attitude.distance(to:old.attitude)) ?? 180) > max(20,dt*900) {
                reset(); referenceChanged = true
            }
        }
        previous = sample
        guard !referenceChanged else { look = nil; return }
        if origin == nil { origin = try? sample.attitude.normalized() }
        guard let origin, let value = try? Orientation.look(current:sample.attitude,origin:origin,previousYaw:look?.yaw ?? 0) else {
            look = nil; return
        }
        look = value; samples += 1
        yawMin = min(yawMin,value.yaw); yawMax = max(yawMax,value.yaw)
        pitchMin = min(pitchMin,value.pitch); pitchMax = max(pitchMax,value.pitch)
        yawSpan = yawMax-yawMin; pitchSpan = pitchMax-pitchMin
    }
}

public struct CommissioningIdentity: Sendable, Codable, Equatable {
    public let model: String
    public let firmware: String
    public let firmwareSource: String
    public init(model:String,firmware:String,firmwareSource:String) {
        self.model=model; self.firmware=firmware.trimmingCharacters(in:.whitespacesAndNewlines); self.firmwareSource=firmwareSource
    }
    public var valid:Bool {
        model == "Osmo Pocket 4" && firmware.count >= 3 && firmware.count <= 64 &&
        firmware.contains(where: { $0.isNumber }) &&
        firmware.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) } &&
        ["camera-report","operator-confirmed"].contains(firmwareSource)
    }
}

public enum TestDirection:String,CaseIterable,Sendable,Codable {
    case right, left, up, down, origin
    public var axisYaw:Bool { self == .right || self == .left }
}
public enum CommissioningState:String,Sendable,Codable { case inactive, ready, moving, stopping, awaitingConfirmation, failed }
public enum CommissioningError:String,Error,Sendable,Codable {
    case identity, stale, range, returnFirst, unconfirmed, schedulerGap, wrongDirection, crossAxisMovement, timeout, didNotHold, transport, modeChanged, canceled
}
public struct TestCommand:Sendable {
    public let angles:Angles
    public let nativePitch:Double
}
public struct MovementReceipt:Sendable,Codable {
    public let direction:TestDirection
    public let start:Angles
    public let target:Angles
    public let final:Angles
    public let nativePitchStart:Double
    public let startedAt:Double
    public let stopRequestedAt:Double
    public let heldAt:Double
    public let submittedTargets:Int
    public let maximumPostStopMovement:Double
    public var operatorConfirmed:Bool
}

/// Explicit, session-scoped commissioning. Candidate encoder bounds are never called mechanical limits.
/// Endpoints enter the experimental envelope only after fresh telemetry, a post-stop hold,
/// a successful return to the anchor, and an explicit operator confirmation of physical direction.
public struct CommissioningSession:Sendable {
    public private(set) var state:CommissioningState = .inactive
    public private(set) var identity:CommissioningIdentity?
    public private(set) var anchor:CameraPose?
    public private(set) var receipts:[MovementReceipt] = []
    public private(set) var pendingReceipt:MovementReceipt?
    public private(set) var failure:CommissioningError?
    public private(set) var direction:TestDirection?
    public private(set) var target:Angles?
    public private(set) var experimentalLimits:VerifiedLimits?
    private var candidate:VerifiedLimits?
    private var start:CameraPose?
    private var startedAt=0.0, previousTick=0.0, duration=2.0
    private var stableSince:Double?, lastPoseTime:Double?, stopAt:Double?
    private var stopPose:Angles?, lastPose:Angles?
    private var postStopMaximum=0.0, submitted=0, stableReports=0
    private var pendingEndpoint:TestDirection?
    private var qualified:[TestDirection:Double] = [:]
    public init() {}
    public var running:Bool { state == .moving || state == .stopping }
    public var readyForFollow:Bool { experimentalLimits != nil && state == .ready && pendingEndpoint == nil }
    public var needsReturn:Bool { pendingEndpoint != nil }
    public mutating func begin(identity:CommissioningIdentity,pose:CameraPose,candidate:VerifiedLimits,at now:Double) throws {
        guard identity.valid else { throw CommissioningError.identity }
        guard pose.fresh(at:now) else { throw CommissioningError.stale }
        guard candidate.valid,candidate.model == identity.model,candidate.firmware == identity.firmware, candidate.clamp(pose.angles) == pose.angles else { throw CommissioningError.range }
        self = .init(); self.identity=identity; self.anchor=pose; self.candidate=candidate; state = .ready
    }
    public func plannedTarget(_ direction:TestDirection) -> Angles? {
        guard let anchor,let candidate else { return nil }
        var result=anchor.angles
        let extent=(qualified[direction] ?? 0)+5
        switch direction {
        case .right: guard extent <= 45 else { return nil }; result.yaw += extent
        case .left: guard extent <= 45 else { return nil }; result.yaw -= extent
        case .up: guard extent <= 30 else { return nil }; result.pitch += extent
        case .down: guard extent <= 30 else { return nil }; result.pitch -= extent
        case .origin: break
        }
        guard candidate.clamp(result) == result else { return nil }
        return result
    }
    public mutating func startMove(_ direction:TestDirection,pose:CameraPose,at now:Double) throws {
        guard state == .ready, let anchor else { throw CommissioningError.unconfirmed }
        guard pose.fresh(at:now) else { throw CommissioningError.stale }
        if direction == .origin {
            guard let pendingEndpoint,let last=receipts.last,last.direction == pendingEndpoint,
                  Self.distance(pose.angles,last.target) <= 0.7 else { throw CommissioningError.returnFirst }
        }
        else {
            guard pendingEndpoint == nil, Self.distance(pose.angles,anchor.angles) <= 0.7 else { throw CommissioningError.returnFirst }
        }
        guard let target=plannedTarget(direction),let candidate,candidate.clamp(pose.angles) == pose.angles else { throw CommissioningError.range }
        self.direction=direction; self.target=target; start=pose; startedAt=now; previousTick=now
        duration=max(2,Self.distance(target,pose.angles)/3)
        stableSince=nil; lastPoseTime=nil; stopAt=nil; stopPose=nil; lastPose=nil
        postStopMaximum=0; submitted=0; stableReports=0; pendingReceipt=nil; failure=nil; state = .moving
    }
    public mutating func noteSubmitted() { if state == .moving { submitted += 1 } }
    public mutating func abort(_ reason:CommissioningError) {
        state = .failed; failure=reason; experimentalLimits=nil; pendingReceipt=nil
    }
    /// Owner must immediately end the native target stream when state leaves `moving`.
    public mutating func tick(at now:Double,pose:CameraPose?) -> TestCommand? {
        guard running,let start,let target,let direction else { return nil }
        guard let pose,pose.fresh(at:now) else { abort(.stale); return nil }
        let dt=now-previousTick; previousTick=now
        guard dt > 0,dt <= 0.2 else { abort(.schedulerGap); return nil }
        let newReport=lastPoseTime != pose.receivedAt
        if newReport { lastPoseTime=pose.receivedAt }
        if state == .moving {
            let elapsed=now-startedAt
            let yawAxis=abs(target.yaw-start.angles.yaw) > abs(target.pitch-start.angles.pitch)
            let actualDelta=yawAxis ? pose.angles.yaw-start.angles.yaw : pose.angles.pitch-start.angles.pitch
            let desiredDelta=yawAxis ? target.yaw-start.angles.yaw : target.pitch-start.angles.pitch
            if actualDelta*desiredDelta < 0 && abs(actualDelta) > 1 { abort(.wrongDirection); return nil }
            let cross=yawAxis ? abs(pose.angles.pitch-start.angles.pitch) : abs(pose.angles.yaw-start.angles.yaw)
            if cross > 1.5 { abort(.crossAxisMovement); return nil }
            if abs(actualDelta) > abs(desiredDelta)+1 { abort(.range); return nil }
            let f=min(1,max(0,elapsed/duration)); let s=f*f*f*(10+f*(-15+6*f))
            let command=Angles(yaw:start.angles.yaw+s*(target.yaw-start.angles.yaw),pitch:start.angles.pitch+s*(target.pitch-start.angles.pitch))
            if elapsed >= duration && Self.distance(pose.angles,target) <= 0.6 && newReport && submitted > 0 {
                if stableSince == nil { stableSince=now; stableReports=0 }
                stableReports += 1
                if now-(stableSince ?? now) >= 0.3 && stableReports >= 4 {
                    stopAt=now; stopPose=pose.angles; lastPose=pose.angles; stableSince=nil; stableReports=0; state = .stopping
                    return nil
                }
            } else if newReport { stableSince=nil; stableReports=0 }
            if elapsed > duration+3 { abort(.timeout); return nil }
            return .init(angles:command,nativePitch:Orientation.wrap(start.nativePitch-(command.pitch-start.angles.pitch)))
        }
        guard let stopped=stopAt,let stopPose else { abort(.didNotHold); return nil }
        postStopMaximum=max(postStopMaximum,Self.distance(pose.angles,stopPose))
        if postStopMaximum > 0.8 || Self.distance(pose.angles,target) > 0.8 { abort(.didNotHold); return nil }
        if newReport {
            if let lastPose,Self.distance(lastPose,pose.angles) <= 0.2 {
                if stableSince == nil { stableSince=now }; stableReports += 1
            } else { stableSince=now; stableReports=0 }
            lastPose=pose.angles
            if now-stopped >= 0.8, now-(stableSince ?? now) >= 0.5,stableReports >= 5 {
                pendingReceipt = .init(direction:direction,start:start.angles,target:target,final:pose.angles,
                    nativePitchStart:start.nativePitch,startedAt:startedAt,stopRequestedAt:stopped,heldAt:now,
                    submittedTargets:submitted,maximumPostStopMovement:postStopMaximum,operatorConfirmed:false)
                state = .awaitingConfirmation
            }
        }
        if now-stopped > 3 && state == .stopping { abort(.timeout) }
        return nil
    }
    public mutating func confirmPhysicalObservation() throws {
        guard state == .awaitingConfirmation,var receipt=pendingReceipt,let anchor else { throw CommissioningError.unconfirmed }
        receipt.operatorConfirmed=true; receipts.append(receipt); pendingReceipt=nil
        if receipt.direction == .origin {
            guard let pendingEndpoint, let endpointReceipt=receipts.dropLast().last,
                  endpointReceipt.direction == pendingEndpoint else { abort(.unconfirmed); throw CommissioningError.unconfirmed }
            let extent=pendingEndpoint.axisYaw ? abs(endpointReceipt.target.yaw-anchor.angles.yaw) : abs(endpointReceipt.target.pitch-anchor.angles.pitch)
            qualified[pendingEndpoint]=extent; self.pendingEndpoint=nil
        } else { pendingEndpoint=receipt.direction }
        state = .ready; rebuildLimits()
    }
    private mutating func rebuildLimits() {
        guard pendingEndpoint == nil,let anchor,let identity,
              let right=qualified[.right],let left=qualified[.left],let up=qualified[.up],let down=qualified[.down] else { return }
        experimentalLimits = .init(model:identity.model,firmware:identity.firmware,
            evidence:"session-only; operator-observed single-axis endpoints + return/hold; not mechanical specifications",
            yawMin:anchor.angles.yaw-left,yawMax:anchor.angles.yaw+right,
            pitchMin:anchor.angles.pitch-down,pitchMax:anchor.angles.pitch+up)
    }
    public static func distance(_ a:Angles,_ b:Angles) -> Double { max(abs(a.yaw-b.yaw),abs(a.pitch-b.pitch)) }
}
