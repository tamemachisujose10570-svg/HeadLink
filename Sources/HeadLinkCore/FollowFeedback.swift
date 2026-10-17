import Foundation

public enum FollowFeedbackState:String,Codable,Sendable { case unavailable, settling, withinTolerance, mismatch, diverged }
public struct FollowFeedbackReading:Codable,Sendable {
    public let at:Double; public let state:FollowFeedbackState
    public let target:Angles; public let actual:Angles?
    public let yawError:Double?; public let pitchError:Double?; public let nativePitchError:Double?
    public let poseAge:Double?
}
/// Only compare settled commands with fresh handle-frame reports. These are camera
/// telemetry residuals, not externally measured optical pointing accuracy or latency.
public struct FollowFeedbackMonitor:Sendable {
    private var anchor:Angles?
    private var stableSince:Double?
    private var mismatchSince:Double?
    public private(set) var reading:FollowFeedbackReading?
    public init() {}
    public mutating func update(command:Angles,nativePitch:Double,transitioning:Bool,pose:CameraPose?,at now:Double) -> FollowFeedbackReading {
        if anchor.map({max(abs($0.yaw-command.yaw),abs($0.pitch-command.pitch)) > 0.5}) ?? true {
            anchor=command; stableSince=now; mismatchSince=nil
        }
        let actual=pose.flatMap{$0.fresh(at:now) ? $0 : nil}
        let yaw=actual.map{$0.angles.yaw-command.yaw},pitch=actual.map{$0.angles.pitch-command.pitch}
        let native=actual.map{Orientation.wrap($0.nativePitch-nativePitch)}
        let state:FollowFeedbackState
        if actual == nil { state = .unavailable; mismatchSince=nil }
        else if transitioning || now-(stableSince ?? now) < 0.35 { state = .settling; mismatchSince=nil }
        else if abs(yaw ?? .infinity) <= 2.5 && abs(pitch ?? .infinity) <= 2.5 && abs(native ?? .infinity) <= 2.5 {
            state = .withinTolerance; mismatchSince=nil
        } else {
            if mismatchSince == nil { mismatchSince=now }
            state=now-(mismatchSince ?? now) >= 1 ? .diverged : .mismatch
        }
        let result=FollowFeedbackReading(at:now,state:state,target:command,actual:actual?.angles,
            yawError:yaw,pitchError:pitch,nativePitchError:native,poseAge:pose.map{now-$0.receivedAt})
        reading=result; return result
    }
}
