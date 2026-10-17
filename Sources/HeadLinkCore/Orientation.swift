import Foundation

public enum TrackingError: Error, Equatable { case invalidQuaternion, vertical, stale, unstable, uncalibrated, unavailable, referenceJump, gravityUnavailable }

/// Right-handed active rotation, Hamilton product; +X right, +Y nose, +Z up.
/// q maps head-local vectors into the motion reference. Angles exposed in degrees.
public struct Quaternion: Equatable, Sendable, Codable {
    public var w: Double; public var x: Double; public var y: Double; public var z: Double
    public init(w: Double, x: Double, y: Double, z: Double) { self.w=w; self.x=x; self.y=y; self.z=z }
    public static let identity = Self(w: 1, x: 0, y: 0, z: 0)
    public func normalized() throws -> Self {
        let n = sqrt(w*w+x*x+y*y+z*z)
        guard n.isFinite, n > 1e-9 else { throw TrackingError.invalidQuaternion }
        return .init(w:w/n,x:x/n,y:y/n,z:z/n)
    }
    public var inverse: Self { .init(w:w,x:-x,y:-y,z:-z) }
    public static func * (a: Self, b: Self) -> Self {
        .init(w:a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z,
              x:a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,
              y:a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,
              z:a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w)
    }
    public static func axis(_ x: Double, _ y: Double, _ z: Double, degrees: Double) -> Self {
        let n=sqrt(x*x+y*y+z*z), h=degrees * .pi/360
        guard n > 0 else { return .identity }
        return .init(w:cos(h),x:x/n*sin(h),y:y/n*sin(h),z:z/n*sin(h))
    }
    public func distance(to other: Self) throws -> Double {
        let a=try normalized(), b=try other.normalized()
        let dot=abs(a.w*b.w+a.x*b.x+a.y*b.y+a.z*b.z)
        return 2*acos(min(1,dot))*180 / .pi
    }
}

public struct Angles: Equatable, Sendable, Codable {
    public var yaw: Double; public var pitch: Double
    public init(yaw: Double, pitch: Double) { self.yaw=yaw; self.pitch=pitch }
    public static let zero = Self(yaw:0,pitch:0)
    public var finite: Bool { yaw.isFinite && pitch.isFinite }
}

public enum Orientation {
    public static func wrap(_ value: Double) -> Double {
        var d=value.truncatingRemainder(dividingBy:360)
        if d > 180 { d-=360 }; if d <= -180 { d+=360 }; return d
    }
    public static func unwrap(_ value: Double, near previous: Double) -> Double { previous+wrap(value-previous) }
    /// B = inverse(q0) * q: current head → calibrated head axes. Extract nose, not Euler differences.
    /// Camera origin is a two-axis offset. This is a calibrated azimuth/elevation mapping,
    /// not an arbitrary three-axis pose reproduction, nor world stabilization of a moving base.
    public static func look(current: Quaternion, origin: Quaternion, previousYaw: Double = 0) throws -> Angles {
        let relative = try origin.normalized().inverse * current.normalized()
        let v=relative * Quaternion(w:0,x:0,y:1,z:0) * relative.inverse
        guard hypot(v.x,v.y) > sin(3 * .pi/180) else { throw TrackingError.vertical }
        return .init(yaw:unwrap(atan2(v.x,v.y)*180 / .pi,near:previousYaw),
                     pitch:atan2(v.z,hypot(v.x,v.y))*180 / .pi)
    }
}

public struct MotionSample: Sendable {
    public let attitude: Quaternion
    public let receivedAt: Double
    public let sensorTime: Double
    public let rotationRate: Double
    public let gravity:DirectionVector?
    public init(attitude: Quaternion, receivedAt: Double, sensorTime: Double, rotationRate: Double,gravity:DirectionVector? = nil) {
        self.attitude=attitude; self.receivedAt=receivedAt; self.sensorTime=sensorTime; self.rotationRate=rotationRate
        self.gravity=gravity
    }
    public func fresh(at now: Double, threshold: Double) -> Bool {
        receivedAt.isFinite && now.isFinite && now >= receivedAt && now-receivedAt <= threshold
    }
}

public struct CameraPose: Sendable {
    public let angles: Angles; public let nativePitch: Double; public let receivedAt: Double
    public init(angles: Angles, nativePitch: Double, receivedAt: Double) { self.angles=angles; self.nativePitch=nativePitch; self.receivedAt=receivedAt }
    public func fresh(at now: Double) -> Bool {
        angles.finite && nativePitch.isFinite && now >= receivedAt && now-receivedAt <= 0.3
    }
}

/// Configured coordinate reach. Evidence distinguishes personal measurements from pinned protocol limits.
public struct VerifiedLimits: Sendable, Codable {
    public let model: String; public let firmware: String; public let evidence: String
    public let yawMin: Double; public let yawMax: Double; public let pitchMin: Double; public let pitchMax: Double
    public init(model:String,firmware:String,evidence:String,yawMin:Double,yawMax:Double,pitchMin:Double,pitchMax:Double) {
        self.model=model; self.firmware=firmware; self.evidence=evidence
        self.yawMin=yawMin; self.yawMax=yawMax; self.pitchMin=pitchMin; self.pitchMax=pitchMax
    }
    public var valid: Bool {
        !model.isEmpty && !firmware.isEmpty && !evidence.isEmpty &&
        [yawMin,yawMax,pitchMin,pitchMax].allSatisfy(\.isFinite) && yawMin < yawMax && pitchMin < pitchMax
    }
    public func clamp(_ a: Angles) -> Angles {
        .init(yaw:min(yawMax,max(yawMin,a.yaw)),pitch:min(pitchMax,max(pitchMin,a.pitch)))
    }
}
