import Testing
@testable import HeadLinkCore
import OpenCineDJI

struct FormalFollowTests {
    func required<T>(_ value:T?,sourceLocation:SourceLocation = #_sourceLocation) throws -> T { try #require(value,sourceLocation:sourceLocation) }
    func q(_ yaw:Double,_ pitch:Double,_ roll:Double = 0) -> Quaternion {
        .axis(0,0,1,degrees:-yaw) * Quaternion.axis(1,0,0,degrees:pitch) * Quaternion.axis(0,1,0,degrees:roll)
    }
    func gravity(_ value:Quaternion) throws -> DirectionVector { try value.inverse.rotate(.init(x:0,y:0,z:-1)) }
    @Test func declaredReachReplacesFiveDegreeEnvelopeAndMatchesPinnedWire() throws {
        let p=try #require(FormalFollowProfile.limits(model:"Osmo Pocket 4",reportedFirmware:nil))
        #expect(p.yawMin == GimbalReach.panMinDeg && p.yawMax == GimbalReach.panMaxDeg)
        #expect(p.pitchMin == GimbalReach.tiltMinDeg && p.pitchMax == GimbalReach.tiltMaxDeg)
        #expect(p.clamp(.init(yaw:-30,pitch:30)) == .init(yaw:-30,pitch:30))
        #expect(p.firmware == "not-reported")
        #expect(FormalFollowProfile.limits(model:"Osmo Pocket 3",reportedFirmware:nil) == nil)
        #expect(FormalFollowProfile.limits(model:"Osmo Pocket 4 Pro",reportedFirmware:nil) == nil)
        #expect(FormalFollowProfile.limits(model:nil,reportedFirmware:nil) == nil)
        #expect(p.clamp(.init(yaw:-90,pitch:80)) == .init(yaw:-48,pitch:70))
    }
    @Test func levelReferencePreservesCompoundThirtyDegreesFromTiltedRolledCalibration() throws {
        let origin=q(65,20,35),reference=try HeadDirectionReference(origin:origin,gravity:gravity(origin))
        for roll in [-60.0,0,45,90] {
            let result=try reference.look(q(95,50,roll),previousYaw:0)
            #expect(abs(result.yaw-30) < 1e-9 && abs(result.pitch-30) < 1e-9)
        }
        let old=try Orientation.look(current:q(95,50),origin:origin)
        #expect(abs(old.yaw-30)+abs(old.pitch-30) > 1)
        let back=try reference.look(origin,previousYaw:30)
        #expect(abs(back.yaw)+abs(back.pitch) < 1e-9)
    }
    @Test func levelReferenceIsIndependentOfMotionReferenceFrameAndWrapsContinuously() throws {
        let rotation=Quaternion.axis(1,2,3,degrees:63),origin=q(170,-10,20)
        let reference=try HeadDirectionReference(origin:rotation*origin,gravity:gravity(origin))
        let result=try reference.look(rotation*q(205,20,-40),previousYaw:0)
        #expect(abs(result.yaw-35)+abs(result.pitch-30) < 1e-9)
        var previous=0.0
        for yaw in stride(from:175.0,through:375,by:5) {
            let r=try reference.look(rotation*q(yaw,-10),previousYaw:previous)
            #expect(abs(r.yaw-(yaw-170)) < 1e-8); previous=r.yaw
        }
    }
    @Test func missingGravityAndVerticalCalibrationAreRejected() throws {
        #expect(throws:TrackingError.gravityUnavailable) {
            try HeadDirectionReference(origin:.identity,gravity:.init(x:0,y:0,z:0))
        }
        let tilted=q(0,89)
        #expect(throws:TrackingError.vertical) { try HeadDirectionReference(origin:tilted,gravity:gravity(tilted)) }
        var c=try TrackingTests().calibrated(); c.requiresGravityReference=true
        #expect(throws:TrackingError.gravityUnavailable) { try c.beginCalibration(at:1.875) }
    }
    @Test func officialRouteCalibratesWithoutExperimentThenTracksHoldReturnAndNativePitch() throws {
        var c=TrackingController(); c.requiresGravityReference=true
        c.limits=FormalFollowProfile.limits(model:"Osmo Pocket 4",reportedFirmware:nil); c.connectionChanged(true)
        var time=1.0,actual=Angles(yaw:15,pitch:10)
        let origin=q(65,20,35)
        func feed(_ orientation:Quaternion) throws {
            time += 0.025
            c.ingest(.init(attitude:orientation,receivedAt:time,sensorTime:time,rotationRate:0,gravity:try gravity(orientation)))
            c.ingest(.init(angles:actual,nativePitch:Orientation.wrap(170-(actual.pitch-10)),receivedAt:time))
        }
        try feed(origin); try c.beginCalibration(at:time)
        for _ in 0..<35 { try feed(origin); if c.state == .calibrating { _=try c.collectCalibration(at:time) } }
        let id=c.calibrationID
        #expect(c.startBlocker(at:time) == nil); try c.start(at:time)
        try feed(origin); actual=try required(c.tick(at:time)).command
        var monitor=FollowFeedbackMonitor()
        for target in [Angles(yaw:30,pitch:30),Angles(yaw:-30,pitch:-30),.zero] {
            // Head moves gradually; camera feedback is simulated, not physical evidence.
            let previous=c.head ?? .zero
            for i in 1...30 {
                let f=Double(i)/30,delta=Angles(yaw:previous.yaw+(target.yaw-previous.yaw)*f,pitch:previous.pitch+(target.pitch-previous.pitch)*f)
                try feed(q(65+delta.yaw,20+delta.pitch,35))
                let output=try required(c.tick(at:time)); actual=output.command
                #expect(abs(output.raw.yaw-(15+delta.yaw))+abs(output.raw.pitch-(10+delta.pitch)) < 1e-8)
                // After start alignment, immediate control has no added client-side trailing filter.
                #expect(abs(output.command.yaw-output.limited.yaw)+abs(output.command.pitch-output.limited.pitch) < 1e-8)
            }
            for _ in 0..<80 {
                try feed(q(65+target.yaw,20+target.pitch,35))
                let output=try required(c.tick(at:time)); actual=output.command
                let check=monitor.update(command:output.command,nativePitch:output.nativePitch,transitioning:output.transitioning,pose:c.pose,at:time)
                #expect(check.state != .diverged)
            }
            #expect(monitor.reading?.state == .withinTolerance)
            #expect(abs(actual.yaw-(15+target.yaw))+abs(actual.pitch-(10+target.pitch)) < 1e-8)
            #expect(c.hasCalibration && c.calibrationID == id)
        }
        c.pause(); try feed(origin); #expect(c.tick(at:time) == nil)
        try c.start(at:time); try feed(origin); #expect(c.tick(at:time) != nil)
        c.connectionChanged(false); c.connectionChanged(true); #expect(!c.hasCalibration)
    }
    @Test func resumeTransitionIsBoundedThenImmediateGainRemainsOne() throws {
        var c=try TrackingTests().calibrated(); c.pause()
        for i in 1...10 { TrackingTests().feed(&c,at:1.875+Double(i)*0.025,q:q(Double(i)*3,0)) }
        try c.start(at:2.125)
        TrackingTests().feed(&c,at:2.15,q:q(30,0))
        let first=try required(c.tick(at:2.15))
        #expect(first.command.yaw < 1 && first.transitioning)
        for i in 2...80 { TrackingTests().feed(&c,at:2.125+Double(i)*0.025,q:q(30,0)); _=c.tick(at:2.125+Double(i)*0.025) }
        #expect(abs(try #require(c.output).command.yaw-30) < 0.01)
        #expect(c.output?.limitedByRange == false)
    }
    @Test func outsideReachIsClampedWithoutGainCompressionOrOriginChange() throws {
        var c=try TrackingTests().calibrated()
        c.limits=FormalFollowProfile.limits(model:"Osmo Pocket 4",reportedFirmware:nil)
        try c.start(at:1.875)
        for i in 1...100 {
            let t=1.875+Double(i)*0.025
            TrackingTests().feed(&c,at:t,q:q(-min(90,Double(i)*2),min(80,Double(i)*2))); _=c.tick(at:t)
        }
        let value=try #require(c.output)
        #expect(abs(value.raw.yaw+90)+abs(value.raw.pitch-80) < 1e-8)
        #expect(value.limited == .init(yaw:-48,pitch:70) && value.limitedByRange)
        #expect(c.hasCalibration)
    }
    @Test func settledFeedbackDetectsWrongAxisUnitsAndNativeReference() {
        var m=FollowFeedbackMonitor()
        var r:FollowFeedbackReading?
        for i in 0...80 {
            let t=Double(i)*0.025
            r=m.update(command:.init(yaw:30,pitch:30),nativePitch:150,transitioning:false,
                pose:.init(angles:.init(yaw:-30,pitch:30),nativePitch:150,receivedAt:t),at:t)
        }
        #expect(r?.state == .diverged && r?.yawError == -60)
        m = .init()
        for i in 0...80 {
            let t=Double(i)*0.025
            r=m.update(command:.init(yaw:30,pitch:30),nativePitch:150,transitioning:false,
                pose:.init(angles:.init(yaw:30,pitch:30),nativePitch:30,receivedAt:t),at:t)
        }
        #expect(r?.state == .diverged && r?.nativePitchError == -120)
    }
    @Test func movingTargetOrStaleFeedbackCannotClaimVerifiedSettledResponse() {
        var m=FollowFeedbackMonitor()
        for i in 0...100 {
            let t=Double(i)*0.025
            let r=m.update(command:.init(yaw:Double(i),pitch:0),nativePitch:180,transitioning:false,
                pose:.init(angles:.zero,nativePitch:180,receivedAt:t),at:t)
            #expect(r.state == .settling)
        }
        let stale=m.update(command:.zero,nativePitch:180,transitioning:false,pose:.init(angles:.zero,nativePitch:180,receivedAt:0),at:4)
        #expect(stale.state == .unavailable)
    }
    @Test func smallHoldJitterCannotHideAnUnresponsiveCamera() {
        var m=FollowFeedbackMonitor()
        for i in 0...100 {
            let t=Double(i)*0.025,jitter=i%2 == 0 ? 0.1 : -0.1
            _=m.update(command:.init(yaw:30+jitter,pitch:30+jitter),nativePitch:150-jitter,transitioning:false,
                pose:.init(angles:.zero,nativePitch:180,receivedAt:t),at:t)
        }
        #expect(m.reading?.state == .diverged)
    }
}
