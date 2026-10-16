import Testing
@testable import HeadLinkCore
import OpenCineDJI

struct TrackingTests {
    let limits=VerifiedLimits(model:"TEST ONLY",firmware:"fixture",evidence:"synthetic",yawMin:-48,yawMax:100,pitchMin:-40,pitchMax:40)
    @Test func testIdentityAndSingleAxisGain() throws {
        for d in [-45.0,-30,0,30,45] {
            let yaw=try Orientation.look(current:.axis(0,0,1,degrees:-d),origin:.identity)
            let pitch=try Orientation.look(current:.axis(1,0,0,degrees:d),origin:.identity)
            expectEqual(yaw.yaw,d,accuracy:1e-9); expectEqual(pitch.pitch,d,accuracy:1e-9)
        }
    }
    @Test func testCompoundRotationAndNonIdentityCalibration() throws {
        let origin=Quaternion.axis(0,0,1,degrees:65)*Quaternion.axis(1,0,0,degrees:20)
        let relative=Quaternion.axis(0,0,1,degrees:-45)*Quaternion.axis(1,0,0,degrees:30)
        let look=try Orientation.look(current:origin*relative,origin:origin)
        expectEqual(look.yaw,45,accuracy:1e-9); expectEqual(look.pitch,30,accuracy:1e-9)
        let back=try Orientation.look(current:origin,origin:origin)
        expectEqual(back.yaw,0,accuracy:1e-9); expectEqual(back.pitch,0,accuracy:1e-9)
    }
    @Test func testSignScaleBoundaryAndVertical() throws {
        let q=Quaternion.axis(0,0,1,degrees:-179)
        let neg=Quaternion(w:-q.w*4,x:-q.x*4,y:-q.y*4,z:-q.z*4)
        expectEqual(try Orientation.look(current:q,origin:.identity).yaw,
                       try Orientation.look(current:neg,origin:.identity).yaw,accuracy:1e-9)
        expectEqual(Orientation.unwrap(-179,near:179),181)
        expectEqual(Orientation.unwrap(179,near:-179),-181)
        expectThrows(try Orientation.look(current:.axis(1,0,0,degrees:89),origin:.identity))
        expectThrows(try Quaternion(w:0,x:0,y:0,z:0).normalized())
    }
    func calibrated() throws -> TrackingController {
        var c=TrackingController(); c.limits=limits; c.connectionChanged(true)
        feed(&c,at:1); try c.beginCalibration(at:1)
        for i in 1...35 { let t=1+Double(i)*0.025; feed(&c,at:t); if c.state == .calibrating { _=try c.collectCalibration(at:t) } }
        expectEqual(c.state,.calibrated); return c
    }
    func feed(_ c:inout TrackingController,at t:Double,q:Quaternion = .identity) {
        c.ingest(.init(attitude:q,receivedAt:t,sensorTime:t,rotationRate:0))
        c.ingest(CameraPose(angles:.zero,nativePitch:0,receivedAt:t))
    }
    @Test func testExplicitStartPauseAndReconnect() throws {
        var c=try calibrated(); expectNil(c.tick(at:1.9))
        try c.start(at:1.875); feed(&c,at:1.9); expectNotNil(c.tick(at:1.9))
        c.pause(); feed(&c,at:1.925); expectNil(c.tick(at:1.925))
        c.connectionChanged(false); c.connectionChanged(true); feed(&c,at:1.95)
        expectFalse(c.hasCalibration); expectThrows(try c.start(at:1.95))
    }
    @Test func testStaleAndTimestampResetInvalidateCalibration() throws {
        var c=try calibrated(); try c.start(at:1.875)
        expectNil(c.tick(at:2.2)); expectEqual(c.state,.stalePaused); expectFalse(c.hasCalibration)
        c=try calibrated(); c.ingest(.init(attitude:.identity,receivedAt:1.9,sensorTime:0,rotationRate:0))
        expectFalse(c.hasCalibration); expectEqual(c.state,.fault)
    }
    @Test func testUnverifiedLimitsCannotMove() throws {
        var c=try calibrated(); c.limits=nil; expectThrows(try c.start(at:1.875))
    }
    @Test func testRawTargetLimitAndSmoothConvergence() throws {
        var c=try calibrated(); c.response = .smooth; try c.start(at:1.875)
        // Slowly approach so this is not classified as an attitude-reference jump.
        var last:TrackingOutput?
        for i in 1...400 {
            let t=1.875+Double(i)*0.025, pitch=min(50,Double(i)*0.5)
            feed(&c,at:t,q:.axis(1,0,0,degrees:pitch)); last=c.tick(at:t)
        }
        expectEqual(try unwrap(last).raw.pitch,50,accuracy:1e-8)
        expectEqual(last!.limited.pitch,40); expectTrue(last!.limitedByRange)
        expectEqual(last!.command.pitch,40,accuracy:0.01)
        expectEqual(last!.nativePitch,-40,accuracy:0.01)
        for i in 401...800 {
            let t=1.875+Double(i)*0.025, pitch=max(0,50-Double(i-400)*0.5)
            feed(&c,at:t,q:.axis(1,0,0,degrees:pitch)); last=c.tick(at:t)
        }
        expectEqual(try unwrap(last).command.pitch,0,accuracy:0.01)
    }
    @Test func testUnstableCalibrationDoesNotFinish() throws {
        var c=TrackingController(); c.connectionChanged(true); feed(&c,at:1); try c.beginCalibration(at:1)
        for i in 1...60 {
            let t=1+Double(i)*0.025
            c.ingest(.init(attitude:.identity,receivedAt:t,sensorTime:t,rotationRate:1))
            c.ingest(CameraPose(angles:.zero,nativePitch:0,receivedAt:t))
            expectFalse(try c.collectCalibration(at:t))
        }
        expectFalse(c.hasCalibration)
    }
    @Test func testPausedYawRemainsContinuousAndMotionLossRequiresCalibration() throws {
        var c=try calibrated(); c.pause()
        for i in 1...200 { feed(&c,at:1.875+Double(i)*0.025,q:.axis(0,0,1,degrees:-Double(i))) }
        expectEqual(try unwrap(c.head).yaw,200,accuracy:1e-8)
        expectEqual(c.state,.userPaused)
        c.motionUnavailable(); expectFalse(c.hasCalibration); expectNil(c.head)
    }
    @Test func testStaleCameraStopsEvenWithFreshHead() throws {
        var c=try calibrated(); try c.start(at:1.875)
        for i in 1...15 {
            let t=1.875+Double(i)*0.025
            c.ingest(.init(attitude:.identity,receivedAt:t,sensorTime:t,rotationRate:0)); _=c.tick(at:t)
        }
        expectEqual(c.state,.stalePaused); expectNil(c.output)
    }
    @Test func testNativeLatestWinsAndPauseFence() throws {
        var stream=GimbalNativeTargetStream(); stream.begin(token:1)
        let a=try unwrap(Commands.gimbalTimedTarget(yawDeg:10,nativePitchDeg:0,duration:0.1))
        let b=try unwrap(Commands.gimbalTimedTarget(yawDeg:20,nativePitchDeg:0,duration:0.1))
        expectTrue(stream.submit(a,token:1,now:1)); expectTrue(stream.submit(b,token:1,now:1.01))
        expectEqual(stream.next(now:1.02)?.payload,b.payload); expectNil(stream.next(now:1.1))
        _=stream.submit(a,token:1,now:1.12); expectTrue(stream.cancel(token:1))
        expectFalse(stream.submit(b,token:1,now:1.13)); expectNil(stream.next(now:1.14))
        stream.begin(token:2); _=stream.submit(a,token:2,now:2); expectNil(stream.next(now:2.3))
        expectFalse(stream.cancel(token:1))
    }
    @Test func testNativeAngleEncodingAndStop() throws {
        let f=try unwrap(Commands.gimbalTimedTarget(yawDeg:30,nativePitchDeg:-10,duration:0.1))
        expectEqual(f.payload,[0x2c,0x01,0,0,0x9c,0xff,0x05,1])
        expectEqual(Commands.gimbalTimedStop().payload,[0,0,0,0,0,0,4,1])
        expectNil(Commands.gimbalTimedTarget(yawDeg:.nan,nativePitchDeg:0,duration:0.1))
    }
}

private func expectEqual<T:Equatable>(_ a:T,_ b:T,sourceLocation:SourceLocation = #_sourceLocation) { #expect(a == b,sourceLocation:sourceLocation) }
private func expectEqual(_ a:Double,_ b:Double,accuracy:Double,sourceLocation:SourceLocation = #_sourceLocation) { #expect(abs(a-b) <= accuracy,sourceLocation:sourceLocation) }
private func expectTrue(_ v:Bool,sourceLocation:SourceLocation = #_sourceLocation) { #expect(v,sourceLocation:sourceLocation) }
private func expectFalse(_ v:Bool,sourceLocation:SourceLocation = #_sourceLocation) { #expect(!v,sourceLocation:sourceLocation) }
private func expectNil<T>(_ v:T?,sourceLocation:SourceLocation = #_sourceLocation) { #expect(v == nil,sourceLocation:sourceLocation) }
private func expectNotNil<T>(_ v:T?,sourceLocation:SourceLocation = #_sourceLocation) { #expect(v != nil,sourceLocation:sourceLocation) }
private func unwrap<T>(_ v:T?,sourceLocation:SourceLocation = #_sourceLocation) throws -> T { try #require(v,sourceLocation:sourceLocation) }
private func expectThrows<T>(_ expression:@autoclosure () throws -> T,sourceLocation:SourceLocation = #_sourceLocation) {
    do { _=try expression(); Issue.record("Expected an error",sourceLocation:sourceLocation) } catch {}
}
