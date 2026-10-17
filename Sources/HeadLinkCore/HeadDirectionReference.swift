import Foundation

public struct DirectionVector:Codable,Equatable,Sendable {
    public let x:Double; public let y:Double; public let z:Double
    public init(x:Double,y:Double,z:Double) { self.x=x; self.y=y; self.z=z }
    public func dot(_ b:Self) -> Double { x*b.x+y*b.y+z*b.z }
    public func cross(_ b:Self) -> Self { .init(x:y*b.z-z*b.y,y:z*b.x-x*b.z,z:x*b.y-y*b.x) }
    public func scaled(_ s:Double) -> Self { .init(x:x*s,y:y*s,z:z*s) }
    public static func - (a:Self,b:Self) -> Self { .init(x:a.x-b.x,y:a.y-b.y,z:a.z-b.z) }
    public func unit() throws -> Self {
        let n=sqrt(dot(self)); guard n.isFinite,n > 1e-6 else { throw TrackingError.gravityUnavailable }
        return scaled(1/n)
    }
}
extension Quaternion {
    public func rotate(_ v:DirectionVector) throws -> DirectionVector {
        let q=try normalized(),r=q*Quaternion(w:0,x:v.x,y:v.y,z:v.z)*q.inverse
        return .init(x:r.x,y:r.y,z:r.z)
    }
}

/// Gravity-level azimuth/elevation, measured in the motion manager's reference frame.
/// Calibration captures heading and elevation separately; initial head roll/pitch cannot
/// tilt the yaw plane. This describes a fixed camera body, not world tracking of a moving body.
public struct HeadDirectionReference:Codable,Sendable {
    public let up:DirectionVector
    public let forward:DirectionVector
    public let right:DirectionVector
    public let elevation:Double
    public init(origin:Quaternion,gravity:DirectionVector) throws {
        let g2=gravity.dot(gravity)
        guard g2.isFinite,(0.25...2.25).contains(g2) else { throw TrackingError.gravityUnavailable }
        try self.init(origin:origin,upInReference:origin.rotate(gravity.scaled(-1)))
    }
    public init(origin:Quaternion,upInReference:DirectionVector) throws {
        let up=try upInReference.unit()
        let nose=try origin.rotate(.init(x:0,y:1,z:0))
        let horizontal=nose-up.scaled(nose.dot(up))
        guard sqrt(horizontal.dot(horizontal)) > sin(3 * .pi/180) else { throw TrackingError.vertical }
        self.up=up; forward=try horizontal.unit(); right=try forward.cross(up).unit()
        elevation=atan2(nose.dot(up),sqrt(horizontal.dot(horizontal)))*180 / .pi
    }
    public func look(_ current:Quaternion,previousYaw:Double) throws -> Angles {
        let nose=try current.rotate(.init(x:0,y:1,z:0))
        let x=nose.dot(right),y=nose.dot(forward),z=nose.dot(up)
        guard hypot(x,y) > sin(3 * .pi/180) else { throw TrackingError.vertical }
        return .init(yaw:Orientation.unwrap(atan2(x,y)*180 / .pi,near:previousYaw),
            pitch:atan2(z,hypot(x,y))*180 / .pi-elevation)
    }
}
