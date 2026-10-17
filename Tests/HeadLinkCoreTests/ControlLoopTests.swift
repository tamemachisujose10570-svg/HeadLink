import Testing
@testable import HeadLinkCore

struct ControlLoopTests {
    @Test func arrivalBetweenClockAndReadPreviouslyInvalidatedCalibration() throws {
        var old=try TrackingTests().calibrated()
        try old.start(at:1.875)
        let loopEntry=1.9,arrival=loopEntry+0.0001
        let sample=MotionSample(attitude:.identity,receivedAt:arrival,sensorTime:arrival,rotationRate:0)
        old.ingest(sample); old.ingest(.init(angles:.zero,nativePitch:180,receivedAt:1.9))
        #expect(old.tick(at:loopEntry) == nil)
        #expect(!old.hasCalibration)

        var c=try TrackingTests().calibrated(); try c.start(at:1.875)
        var clock=loopEntry
        let frame=ControlInputFrame.capture(readMotion:{
            clock=arrival
            return .init(sample:sample,callbackHz:50,failed:false)
        },readCamera:{ .init(angles:.zero,nativePitch:180,receivedAt:loopEntry) },clock:{clock+0.0001})
        c.ingest(try #require(frame.motion.sample)); c.ingest(try #require(frame.camera))
        #expect(c.tick(at:frame.evaluatedAt) != nil)
        #expect(c.state == .following && c.hasCalibration)
    }
    @Test func buttonActionsUseFreshSnapshotRatherThanCachedLoopClock() throws {
        var c=try TrackingTests().calibrated()
        let fresh=MotionSample(attitude:.identity,receivedAt:1.9,sensorTime:1.9,rotationRate:0)
        c.ingest(fresh); c.ingest(.init(angles:.zero,nativePitch:180,receivedAt:1.9))
        #expect(throws:TrackingError.stale) { try c.start(at:1.875) }
        let frame=ControlInputFrame.capture(readMotion:{.init(sample:fresh,callbackHz:50,failed:false)},
            readCamera:{c.pose},clock:{1.901})
        try c.start(at:frame.evaluatedAt)
        #expect(c.state == .following)
    }
    @Test func captureDoesNotWeakenStaleOrFutureTimestampGuards() throws {
        let old=MotionSample(attitude:.identity,receivedAt:1,sensorTime:1,rotationRate:0)
        let stale=ControlInputFrame.capture(readMotion:{.init(sample:old,callbackHz:0,failed:false)},
            readCamera:{.init(angles:.zero,nativePitch:180,receivedAt:1)},clock:{2})
        #expect(stale.motion.sample?.fresh(at:stale.evaluatedAt,threshold:0.2) == false)
        #expect(stale.camera?.fresh(at:stale.evaluatedAt) == false)
        #expect(!old.fresh(at:0.9,threshold:0.2))
        var c=try TrackingTests().calibrated(); try c.start(at:1.875)
        #expect(c.tick(at:2.2) == nil)
        #expect(!c.hasCalibration)
    }
    @Test func repeatedConcurrentArrivalsKeepFollowingAcrossManyTicks() throws {
        var c=try TrackingTests().calibrated(); try c.start(at:1.875)
        for i in 1...400 {
            let entry=1.875+Double(i)*0.025
            let arrival=entry+0.0001
            let frame=ControlInputFrame.capture(readMotion:{
                .init(sample:.init(attitude:.identity,receivedAt:arrival,sensorTime:arrival,rotationRate:0),callbackHz:50,failed:false)
            },readCamera:{.init(angles:.zero,nativePitch:180,receivedAt:entry)},clock:{arrival+0.0001})
            c.ingest(try #require(frame.motion.sample)); c.ingest(try #require(frame.camera))
            #expect(c.tick(at:frame.evaluatedAt) != nil)
            #expect(c.state == .following && c.hasCalibration)
        }
    }
    @Test func stableButtonsDoNotRepublishAtMotorCadence() {
        var gate=PresentationGate<String>(),buttons=0,telemetry=0
        for i in 0..<400 {
            let update=gate.updates(control:"following",at:Double(i)*0.025)
            if update.controls { buttons += 1 }; if update.telemetry { telemetry += 1 }
        }
        #expect(buttons == 1)
        #expect(telemetry >= 80 && telemetry <= 100)
        // A pause/disconnect is immediately visible even within the telemetry interval.
        #expect(gate.updates(control:"disconnected",at:9.976).controls)
        #expect(!gate.updates(control:"disconnected",at:9.977).controls)
    }
}
