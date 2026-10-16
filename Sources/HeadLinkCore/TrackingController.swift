import Foundation

public enum TrackingState: String, Sendable, Codable {
    case disconnected, connecting, waitingMotion, ready, calibrating, calibrated, following
    case userPaused, stalePaused, deviceDisconnected, fault
}
public enum ControlAxes: String, CaseIterable, Sendable { case both, yaw, pitch }
public enum ResponseMode: String, CaseIterable, Sendable { case immediate, smooth }

public struct TrackingOutput: Sendable {
    public let head: Angles; public let raw: Angles; public let limited: Angles; public let command: Angles
    public let nativePitch: Double; public let limitedByRange: Bool; public let transitioning: Bool
}

/// Pure state machine. Owner calls tick at 40 Hz, sensors publish newest values independently.
/// No motion may start from connection, calibration, foregrounding or reconnection alone.
public struct TrackingController: Sendable {
    public private(set) var state: TrackingState = .disconnected
    public private(set) var sample: MotionSample?
    public private(set) var pose: CameraPose?
    public private(set) var output: TrackingOutput?
    public private(set) var head: Angles?
    public var rawTarget: Angles? {
        guard let head,let base=cameraOrigin else { return nil }
        return .init(yaw:base.angles.yaw+(axes == .pitch ? 0 : head.yaw),pitch:base.angles.pitch+(axes == .yaw ? 0 : head.pitch))
    }
    public private(set) var failure: TrackingError?
    public var freshnessThreshold = 0.2
    public var axes: ControlAxes = .both
    public var response: ResponseMode = .immediate
    public var limits: VerifiedLimits?
    private var connected=false
    private var origin: Quaternion?
    private var cameraOrigin: CameraPose?
    private var calibrationSamples: [MotionSample]=[]
    private var calibrationPoses: [CameraPose]=[]
    private var previousYaw=0.0
    private var lastTick: Double?
    private var lastCommand=Angles.zero
    private var filtered=Angles.zero
    private var velocity=Angles.zero
    public init() {}
    public var hasCalibration: Bool { origin != nil }
    public mutating func connecting() { invalidate(); connected=false; state = .connecting }
    public mutating func connectionChanged(_ value: Bool) {
        invalidate(); connected=value; pose=nil; state=value ? .waitingMotion : .deviceDisconnected
    }
    public mutating func invalidate() {
        origin=nil; cameraOrigin=nil; output=nil; head=nil; lastTick=nil; velocity = .zero
        calibrationSamples=[]; calibrationPoses=[]; previousYaw=0
    }
    public mutating func motionUnavailable() { invalidate(); sample=nil; state = connected ? .waitingMotion : .disconnected }
    public mutating func ingest(_ next: MotionSample) {
        guard next.sensorTime.isFinite, next.rotationRate.isFinite, next.rotationRate >= 0,
              (try? next.attitude.normalized()) != nil else {
            invalidate(); failure = .invalidQuaternion; state = .fault; return
        }
        if let old=sample {
            let dt=next.receivedAt-old.receivedAt
            guard dt > 0, next.sensorTime > old.sensorTime else {
                invalidate(); failure = .referenceJump; state = .fault; sample=next; return
            }
            if dt > freshnessThreshold || ((try? next.attitude.distance(to:old.attitude)) ?? 180) > max(20,dt*900) {
                invalidate(); failure = .referenceJump; state = .stalePaused
            }
        }
        sample=next
        if let origin {
            do {
                let look=try Orientation.look(current:next.attitude,origin:origin,previousYaw:previousYaw)
                head=look; previousYaw=look.yaw
            } catch { invalidate(); failure = .vertical; state = .fault }
        }
        if connected && state == .waitingMotion { state = .ready }
    }
    public mutating func ingest(_ next: CameraPose) { pose=next }
    public mutating func beginCalibration(at now: Double) throws {
        guard connected, let s=sample, s.fresh(at:now,threshold:freshnessThreshold),
              let p=pose, p.fresh(at:now) else { throw TrackingError.stale }
        invalidate(); state = .calibrating; failure=nil
    }
    /// 0.7 seconds of stable samples; camera and head must both remain stable.
    public mutating func collectCalibration(at now: Double) throws -> Bool {
        guard state == .calibrating else { throw TrackingError.uncalibrated }
        guard let s=sample, s.fresh(at:now,threshold:freshnessThreshold), let p=pose, p.fresh(at:now) else {
            invalidate(); state = .stalePaused; throw TrackingError.stale
        }
        if calibrationSamples.last?.sensorTime == s.sensorTime { return false }
        if s.rotationRate > 0.08 ||
            (calibrationSamples.first.map { (try? s.attitude.distance(to:$0.attitude)) ?? 180 } ?? 0) > 1 ||
            (calibrationPoses.first.map { abs(p.angles.yaw-$0.angles.yaw)+abs(p.angles.pitch-$0.angles.pitch) } ?? 0) > 1 {
            calibrationSamples=[]; calibrationPoses=[]; failure = .unstable; return false
        }
        calibrationSamples.append(s); calibrationPoses.append(p)
        guard let first=calibrationSamples.first, s.receivedAt-first.receivedAt >= 0.7,
              calibrationSamples.count >= 15 else { return false }
        // Sign-aligned normalized quaternion mean, avoiding cancellation of q and -q.
        let ref=try first.attitude.normalized()
        var sum=Quaternion(w:0,x:0,y:0,z:0)
        for item in calibrationSamples {
            let q=try item.attitude.normalized()
            let sign = ref.w*q.w+ref.x*q.x+ref.y*q.y+ref.z*q.z < 0 ? -1.0 : 1.0
            sum.w+=sign*q.w; sum.x+=sign*q.x; sum.y+=sign*q.y; sum.z+=sign*q.z
        }
        origin=try sum.normalized(); cameraOrigin=p; previousYaw=0; head = .zero
        state = .calibrated; failure=nil; calibrationSamples=[]; calibrationPoses=[]; return true
    }
    public mutating func start(at now: Double) throws {
        guard connected, origin != nil, cameraOrigin != nil else { throw TrackingError.uncalibrated }
        guard limits?.valid == true else { throw TrackingError.unavailable }
        guard let s=sample, s.fresh(at:now,threshold:freshnessThreshold), let p=pose, p.fresh(at:now),
              limits?.clamp(p.angles) == p.angles else { throw TrackingError.stale }
        lastCommand=p.angles; filtered=p.angles; velocity = .zero; lastTick=now
        state = .following; failure=nil
    }
    public mutating func pause(invalidateCalibration: Bool = false) {
        if invalidateCalibration { invalidate() }
        output=nil; state = .userPaused; lastTick=nil; velocity = .zero
    }
    public mutating func tick(at now: Double) -> TrackingOutput? {
        guard state == .following else { return nil }
        guard connected, let s=sample, s.fresh(at:now,threshold:freshnessThreshold), let p=pose, p.fresh(at:now) else {
            invalidate(); failure = .stale; state = .stalePaused; return nil
        }
        guard let origin, let base=cameraOrigin, let limits, limits.valid else {
            invalidate(); failure = .unavailable; state = .fault; return nil
        }
        do {
            let head=try Orientation.look(current:s.attitude,origin:origin,previousYaw:previousYaw)
            previousYaw=head.yaw
            let raw=Angles(yaw:base.angles.yaw+(axes == .pitch ? 0 : head.yaw),
                           pitch:base.angles.pitch+(axes == .yaw ? 0 : head.pitch))
            let limited=limits.clamp(raw)
            let dt=now-(lastTick ?? now)
            guard dt > 0, dt <= freshnessThreshold else { throw TrackingError.stale }
            lastTick=now
            let alpha=response == .smooth ? 1-exp(-dt/0.08) : 1
            filtered = .init(yaw:filtered.yaw+alpha*(limited.yaw-filtered.yaw),pitch:filtered.pitch+alpha*(limited.pitch-filtered.pitch))
            // Discrete acceleration-limited approach. On target crossing snap only when
            // braking can finish in this step; otherwise decelerate, never reset velocity.
            func advance(_ current:Double,_ target:Double,_ v:inout Double) -> Double {
                let error=target-current, a=120.0, vmax=30.0
                let desired=(error < 0 ? -1.0 : 1.0)*min(vmax,sqrt(2*a*abs(error)))
                v += min(a*dt,max(-a*dt,desired-v))
                let step=v*dt
                if abs(error) < 0.001 && abs(v) <= a*dt { v=0; return target }
                if step*error >= 0 && abs(step) >= abs(error) && abs(v) <= a*dt { v=0; return target }
                return current+step
            }
            let next=Angles(yaw:advance(lastCommand.yaw,filtered.yaw,&velocity.yaw),pitch:advance(lastCommand.pitch,filtered.pitch,&velocity.pitch))
            let command=limits.clamp(next)
            if command != next { velocity = .zero }
            lastCommand=command
            let value=TrackingOutput(head:head,raw:raw,limited:limited,command:command,
                nativePitch:Orientation.wrap(base.nativePitch-(command.pitch-base.angles.pitch)),
                limitedByRange:raw != limited,
                transitioning:abs(command.yaw-limited.yaw)+abs(command.pitch-limited.pitch)>0.1)
            output=value; return value
        } catch {
            invalidate(); failure=(error as? TrackingError) ?? .unavailable; state = .fault; return nil
        }
    }
}
