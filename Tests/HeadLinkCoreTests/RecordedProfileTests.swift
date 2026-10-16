import Foundation
import Testing
@testable import HeadLinkCore

struct RecordedProfileTests {
    func profile() throws -> VerifiedLimits {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data=try Data(contentsOf:root.appendingPathComponent("App/VerifiedProfiles.json"))
        let profiles=try JSONDecoder().decode([VerifiedLimits].self,from:data)
        #expect(profiles.count == 1)
        return try #require(profiles.first)
    }
    @Test func packagedEnvelopeUsesOnlyObservedLocalEndpoints() throws {
        let p=try profile()
        #expect(p.valid)
        #expect(p.model == "Osmo Pocket 4" && p.firmware == "01.03.14.04")
        #expect(p.yawMin == -4.5 && p.yawMax == 5.1)
        #expect(p.pitchMin == -5.4 && p.pitchMax == 4.6)
        #expect(p.evidence.contains("operator-confirmed"))
        #expect(p.evidence.contains("167e16e6ec363a0fd8cd8e347fb03eb2ae813872b46f5e40963ddb0cd48b76a3"))
        #expect(p.clamp(.init(yaw:30,pitch:-30)) == .init(yaw:5.1,pitch:-5.4))
    }
    @Test func exactConfirmedIdentityRequiredForReuse() throws {
        let p=try profile()
        for source in ["camera-report","operator-confirmed"] {
            #expect(p.matches(.init(model:p.model,firmware:p.firmware,firmwareSource:source)))
        }
        for id in [CommissioningIdentity(model:p.model,firmware:p.firmware,firmwareSource:"operator-entered-unconfirmed"),
                   .init(model:p.model,firmware:"01.03.14.05",firmwareSource:"camera-report"),
                   .init(model:"Osmo Pocket 4 Pro",firmware:p.firmware,firmwareSource:"camera-report")] {
            #expect(!p.matches(id))
        }
    }
    @Test func recordedOriginRequiresCalibrationThenPreservesGainAndNativeWrap() throws {
        let p=try profile(); let base=Angles(yaw:0.3,pitch:-0.4)
        var c=TrackingController(),time=1.0,actual=base
        c.connectionChanged(true); c.limits=p
        func feed(_ q:Quaternion) {
            time += 0.025
            c.ingest(.init(attitude:q,receivedAt:time,sensorTime:time,rotationRate:0))
            c.ingest(.init(angles:actual,nativePitch:Orientation.wrap(180-(actual.pitch-base.pitch)),receivedAt:time))
        }
        feed(.identity)
        #expect(c.tick(at:time+0.001) == nil)
        #expect(throws:TrackingError.uncalibrated) { try c.start(at:time) }
        try c.beginCalibration(at:time)
        for _ in 0..<35 { feed(.identity); if c.state == .calibrating { _=try c.collectCalibration(at:time) } }
        #expect(c.state == .calibrated)
        #expect(c.tick(at:time+0.001) == nil)
        try c.start(at:time)
        for delta in [Angles(yaw:3,pitch:2),Angles(yaw:-3,pitch:-2),.zero] {
            var output:TrackingOutput?
            for _ in 0..<200 {
                feed(.axis(0,0,1,degrees:-delta.yaw)*Quaternion.axis(1,0,0,degrees:delta.pitch))
                output=c.tick(at:time); if let output { actual=output.command }
            }
            let result=try #require(output)
            #expect(abs(result.raw.yaw-(base.yaw+delta.yaw)) < 1e-8)
            #expect(abs(result.raw.pitch-(base.pitch+delta.pitch)) < 1e-8)
            #expect(CommissioningSession.distance(result.command,result.raw) < 0.01)
            #expect(abs(result.nativePitch-Orientation.wrap(180-delta.pitch)) < 0.01)
        }
        c.pause(); feed(.identity); #expect(c.tick(at:time) == nil)
        c.connectionChanged(false); c.connectionChanged(true); c.limits=p; feed(.identity)
        #expect(c.tick(at:time+0.001) == nil)
        #expect(throws:TrackingError.uncalibrated) { try c.start(at:time) }
    }
}
