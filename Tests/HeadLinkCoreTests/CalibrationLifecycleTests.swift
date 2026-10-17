import Testing
@testable import HeadLinkCore

struct CalibrationLifecycleTests {
    @Test func oneCalibrationSurvivesNormalUpdatesAndStartsWithoutReinitialization() throws {
        var c=try TrackingTests().calibrated()
        let id=c.calibrationID
        #expect(c.startBlocker(at:1.875) == nil)
        try c.start(at:1.875)
        for i in 1...1200 {
            let t=1.875+Double(i)*0.025
            // Ordinary same-session reports, matching configuration and new camera/head data.
            c.connectionChanged(true); c.limits=TrackingTests().limits
            TrackingTests().feed(&c,at:t,q:.axis(0,0,1,degrees:Double(i%20)*0.05))
            #expect(c.tick(at:t) != nil)
            #expect(c.hasCalibration && c.calibrationID == id)
            #expect(c.invalidation == nil)
        }
    }
    @Test func UIAdmissionAndStartUseTheSameRejection() throws {
        var c=try TrackingTests().calibrated()
        c.ingest(.init(angles:.init(yaw:150,pitch:0),nativePitch:180,receivedAt:1.875))
        #expect(c.startBlocker(at:1.875) == .outsideLimits)
        #expect(throws:TrackingError.stale) { try c.start(at:1.875) }
        #expect(c.lastStartRejection == .outsideLimits)
        #expect(c.hasCalibration) // reposition camera, do not demand a spurious new head origin
        c.ingest(.init(angles:.zero,nativePitch:180,receivedAt:1.875))
        #expect(c.startBlocker(at:1.875) == nil)
        try c.start(at:1.875)
    }
    @Test func actualSessionReplacementInvalidatesWithReasonAndID() throws {
        var c=try TrackingTests().calibrated(); let id=c.calibrationID
        c.connectionChanged(false)
        #expect(!c.hasCalibration)
        #expect(c.invalidation?.reason == .connectionChanged)
        #expect(c.invalidation?.calibrationID == id)
        let sequence=c.invalidation?.sequence
        c.connectionChanged(false)
        #expect(c.invalidation?.sequence == sequence)
        c.connectionChanged(true)
        #expect(c.startBlocker(at:1.875) == .uncalibrated)
    }
    @Test func temporaryPausePreservesCalibrationButRealStaleInputDoesNot() throws {
        var c=try TrackingTests().calibrated(); try c.start(at:1.875)
        c.pause()
        for i in 1...40 { TrackingTests().feed(&c,at:1.875+Double(i)*0.025) }
        #expect(c.hasCalibration && c.tick(at:2.875) == nil)
        try c.start(at:2.875)
        #expect(c.tick(at:3.2) == nil)
        #expect(!c.hasCalibration && c.invalidation?.reason == .inputStale)
    }
    @Test func explicitInvalidationRecordsSpecificReasonAndTime() throws {
        var c=try TrackingTests().calibrated()
        c.invalidate(reason:.modeChanged,at:25)
        #expect(c.invalidation?.at == 25)
        #expect(c.invalidation?.reason == .modeChanged)
        #expect(c.invalidation?.calibrationID == 1)
    }
}
