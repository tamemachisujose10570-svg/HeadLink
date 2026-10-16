import Testing
@testable import HeadLinkCore

struct CommissioningTests {
    let identity=CommissioningIdentity(model:"Osmo Pocket 4",firmware:"01.02.0300",firmwareSource:"operator-confirmed")
    let candidate=VerifiedLimits(model:"Osmo Pocket 4",firmware:"01.02.0300",evidence:"synthetic encoder envelope",yawMin:-48,yawMax:225,pitchMin:-44,pitchMax:70)
    func pose(_ angles:Angles = .zero,at time:Double) -> CameraPose { .init(angles:angles,nativePitch:-angles.pitch,receivedAt:time) }
    func session() throws -> CommissioningSession {
        var session=CommissioningSession()
        try session.begin(identity:identity,pose:pose(at:1),candidate:candidate,at:1)
        return session
    }
    @Test func preparingAndConnectionNeverCommandMotion() throws {
        var s=try session()
        #expect(s.state == .ready); #expect(s.tick(at:1.025,pose:pose(at:1.025)) == nil)
        #expect(!s.readyForFollow); #expect(s.experimentalLimits == nil)
    }
    @Test func unknownIdentityAndStalePoseCannotArm() {
        for id in [CommissioningIdentity(model:"Osmo Pocket 3",firmware:"01.00",firmwareSource:"operator-confirmed"),
                   CommissioningIdentity(model:"Osmo Pocket 4",firmware:"",firmwareSource:"camera-report"),
                   CommissioningIdentity(model:"Osmo Pocket 4",firmware:"unknown",firmwareSource:"operator-confirmed")] {
            var s=CommissioningSession()
            #expect(throws:CommissioningError.identity) { try s.begin(identity:id,pose:pose(at:1),candidate:candidate,at:1) }
        }
        var s=CommissioningSession()
        #expect(throws:CommissioningError.stale) { try s.begin(identity:identity,pose:pose(at:1),candidate:candidate,at:2) }
    }
    @Test func candidateRangeDoesNotBecomeVerifiedRange() throws {
        var s=CommissioningSession()
        try s.begin(identity:identity,pose:pose(.init(yaw:-47,pitch:0),at:1),candidate:candidate,at:1)
        #expect(s.plannedTarget(.left) == nil); #expect(s.plannedTarget(.right)?.yaw == -42)
        #expect(throws:CommissioningError.range) { try s.startMove(.left,pose:pose(.init(yaw:-47,pitch:0),at:1),at:1) }
        #expect(s.experimentalLimits == nil)
    }
    /// Deterministic semantic camera: follows the preceding target, without claiming any physical proof.
    func complete(_ s:inout CommissioningSession,_ direction:TestDirection,time:inout Double,actual:inout Angles) throws -> MovementReceipt {
        try s.startMove(direction,pose:pose(actual,at:time),at:time)
        var lastCommand:Angles?
        for _ in 0..<1400 {
            time += 0.025
            if let lastCommand { actual=lastCommand }
            if let command=s.tick(at:time,pose:pose(actual,at:time)) {
                #expect(command.angles.finite)
                #expect(abs(command.nativePitch+command.angles.pitch) < 1e-8)
                lastCommand=command.angles; s.noteSubmitted()
            }
            if s.state == .awaitingConfirmation { break }
            #expect(s.state != .failed)
        }
        #expect(s.state == .awaitingConfirmation)
        let receipt=try #require(s.pendingReceipt)
        #expect(receipt.submittedTargets > 0)
        #expect(receipt.heldAt-receipt.stopRequestedAt >= 0.8)
        #expect(!receipt.operatorConfirmed)
        #expect(!s.readyForFollow)
        try s.confirmPhysicalObservation()
        return receipt
    }
    @Test func allAxesNeedExplicitPhysicalAndReturnConfirmation() throws {
        var s=try session(),time=1.0,actual=Angles.zero
        for direction in [TestDirection.right,.left,.up,.down] {
            let endpoint=try complete(&s,direction,time:&time,actual:&actual)
            #expect(CommissioningSession.distance(endpoint.target,.zero) == 5)
            #expect(s.needsReturn); #expect(!s.readyForFollow)
            #expect(throws:CommissioningError.returnFirst) { try s.startMove(.up,pose:pose(actual,at:time),at:time) }
            _=try complete(&s,.origin,time:&time,actual:&actual)
        }
        #expect(s.receipts.count == 8); #expect(s.readyForFollow)
        let limits=try #require(s.experimentalLimits)
        #expect(limits.yawMin == -5 && limits.yawMax == 5)
        #expect(limits.pitchMin == -5 && limits.pitchMax == 5)
        #expect(limits.clamp(.init(yaw:30,pitch:30)) == .init(yaw:5,pitch:5))
        #expect(s.plannedTarget(.right)?.yaw == 10)
        _=try complete(&s,.right,time:&time,actual:&actual)
        #expect(!s.readyForFollow)
        _=try complete(&s,.origin,time:&time,actual:&actual)
        #expect(s.experimentalLimits?.yawMax == 10)
    }
    @Test func commissionedRangeFeedsOneToOneTrackingWithoutAutomaticStart() throws {
        var session=try self.session(), time=1.0, actual=Angles.zero
        for d in [TestDirection.right,.left,.up,.down] {
            _=try complete(&session,d,time:&time,actual:&actual)
            _=try complete(&session,.origin,time:&time,actual:&actual)
        }
        var c=TrackingController(); c.connectionChanged(true); c.limits=try #require(session.experimentalLimits)
        func feed(_ q:Quaternion) {
            time += 0.025
            c.ingest(.init(attitude:q,receivedAt:time,sensorTime:time,rotationRate:0))
            c.ingest(pose(actual,at:time))
        }
        feed(.identity); try c.beginCalibration(at:time)
        for _ in 0..<35 { feed(.identity); if c.state == .calibrating { _=try c.collectCalibration(at:time) } }
        #expect(c.state == .calibrated); #expect(c.tick(at:time+0.001) == nil)
        try c.start(at:time)
        var output:TrackingOutput?
        for i in 1...140 {
            let yaw=min(3,Double(i)*0.1),pitch=min(2,Double(i)*0.1)
            feed(.axis(0,0,1,degrees:-yaw)*Quaternion.axis(1,0,0,degrees:pitch))
            output=c.tick(at:time); if let output { actual=output.command }
        }
        #expect(abs((output?.raw.yaw ?? -999)-3) < 1e-8)
        #expect(abs((output?.raw.pitch ?? -999)-2) < 1e-8)
        #expect(abs((output?.command.yaw ?? -999)-3) < 0.01)
        #expect(abs((output?.command.pitch ?? -999)-2) < 0.01)
        for i in 1...140 {
            feed(.axis(0,0,1,degrees:-max(0,3-Double(i)*0.1))*Quaternion.axis(1,0,0,degrees:max(0,2-Double(i)*0.1)))
            output=c.tick(at:time); if let output { actual=output.command }
        }
        #expect(CommissioningSession.distance(try #require(output).command,.zero) < 0.01)
        c.pause(); feed(.axis(0,0,1,degrees:-3)); #expect(c.tick(at:time) == nil)
    }
    @Test func returnRefusesUncommandedRepositioning() throws {
        var s=try session(),time=1.0,actual=Angles.zero
        _=try complete(&s,.right,time:&time,actual:&actual)
        #expect(throws:CommissioningError.returnFirst) {
            try s.startMove(.origin,pose:pose(.init(yaw:50,pitch:0),at:time),at:time)
        }
    }
    @Test func lossAndPauseCannotEmitHistoricalTargets() throws {
        var s=try session(); try s.startMove(.right,pose:pose(at:1),at:1)
        #expect(s.tick(at:1.025,pose:nil) == nil); #expect(s.state == .failed)
        #expect(s.tick(at:1.05,pose:pose(at:1.05)) == nil)
        s=try session(); try s.startMove(.right,pose:pose(at:1),at:1)
        s.abort(.canceled)
        #expect(s.tick(at:1.025,pose:pose(at:1.025)) == nil)
        #expect(s.experimentalLimits == nil)
        s=try session(); try s.startMove(.right,pose:pose(at:1),at:1)
        #expect(s.tick(at:1.4,pose:pose(at:1.4)) == nil)
        #expect(s.failure == .schedulerGap)
    }
    @Test func wrongAxisDirectionAndNoMotionFail() throws {
        var s=try session(); try s.startMove(.right,pose:pose(at:1),at:1)
        #expect(s.tick(at:1.025,pose:pose(.init(yaw:-2,pitch:0),at:1.025)) == nil)
        #expect(s.failure == .wrongDirection)
        s=try session(); try s.startMove(.right,pose:pose(at:1),at:1)
        #expect(s.tick(at:1.025,pose:pose(.init(yaw:0,pitch:2),at:1.025)) == nil)
        #expect(s.failure == .crossAxisMovement)
        s=try session(); try s.startMove(.right,pose:pose(at:1),at:1)
        for i in 1...220 { let t=1+Double(i)*0.025; if s.tick(at:t,pose:pose(at:t)) != nil { s.noteSubmitted() } }
        #expect(s.failure == .timeout); #expect(!s.readyForFollow)
    }
    @Test func stopMustBeObservedAndCannotBeConfirmedEarly() throws {
        var s=try session(); var actual=Angles.zero,time=1.0
        #expect(throws:CommissioningError.unconfirmed) { try s.confirmPhysicalObservation() }
        try s.startMove(.right,pose:pose(at:time),at:time)
        for _ in 0..<200 {
            time += 0.025
            if let c=s.tick(at:time,pose:pose(actual,at:time)) { actual=c.angles; s.noteSubmitted() }
            if s.state == .stopping { break }
        }
        #expect(s.state == .stopping)
        #expect(throws:CommissioningError.unconfirmed) { try s.confirmPhysicalObservation() }
        time += 0.025
        #expect(s.tick(at:time,pose:pose(.init(yaw:actual.yaw+1.2,pitch:0),at:time)) == nil)
        #expect(s.failure == .didNotHold)
    }
    @Test func observerWorksBeforeCameraCalibrationAndRejectsReferenceJump() {
        var probe=MotionProbe()
        for i in 0..<80 {
            let d=Double(i)*0.1,t=1+Double(i)*0.025
            let q=Quaternion.axis(0,0,1,degrees:-d)*Quaternion.axis(1,0,0,degrees:d)
            probe.ingest(.init(attitude:q,receivedAt:t,sensorTime:t,rotationRate:0.1))
        }
        #expect(probe.movementObserved); #expect((probe.look?.yaw ?? 0) > 7)
        #expect((probe.look?.pitch ?? 0) > 7)
        probe.ingest(.init(attitude:.identity,receivedAt:10,sensorTime:0,rotationRate:0))
        #expect(probe.referenceChanged); #expect(!probe.movementObserved)
        probe.reset()
        for i in 0..<80 { let t=11+Double(i)*0.025
            probe.ingest(.init(attitude:.axis(0,1,0,degrees:Double(i)),receivedAt:t,sensorTime:t,rotationRate:0.1))
        }
        #expect(!probe.movementObserved) // Pure roll about the nose must not masquerade as pan/tilt.
    }
}
