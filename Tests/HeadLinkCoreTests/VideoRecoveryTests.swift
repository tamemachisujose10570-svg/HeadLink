import Testing
@testable import HeadLinkCore

struct VideoRecoveryTests {
    func sample(_ now:Double,packet:Double? = 0,au:Double? = 0,presented:Double? = 0,
                connected:Bool = true,failed:Bool = false,keyframe:Bool = false) -> VideoPipelineSample {
        .init(now:now,startedAt:0,connected:connected,transportReady:true,packetAt:packet,accessUnitAt:au,
            presentedAt:presented,decoderFailed:failed,awaitingKeyframe:keyframe)
    }
    @Test func healthyVideoDoesNotRepairForFiveMinutes() {
        var p=VideoRecoveryPolicy()
        for i in 0...12000 {
            let t=Double(i)*0.025
            #expect(p.tick(sample(t,packet:t,au:t,presented:t)) == nil)
        }
        #expect(p.attempts == 0 && p.state == .healthy)
    }
    @Test func waitingForKeyframeRequestsDecoderRepairAndNewStream() {
        var p=VideoRecoveryPolicy()
        #expect(p.tick(sample(4,packet:4,au:4,presented:0,keyframe:true)) == .repairDecoderAndEnable)
        #expect(!sample(4,packet:4,au:4,presented:0,keyframe:true).live)
        #expect(p.tick(sample(4.1,packet:4.1,au:4.1,presented:4.1)) == nil)
        #expect(p.state == .healthy)
    }
    @Test func freshDecoderOutputWithFrozenPresentationRepairsOnlyPresentationFirst() {
        var p=VideoRecoveryPolicy()
        let frame=VideoPipelineSample(now:4,startedAt:0,connected:true,transportReady:true,packetAt:4,
            accessUnitAt:4,decoderOutputAt:4,presentedAt:0)
        #expect(p.tick(frame) == .repairPresentation)
        #expect(p.attempts == 1)
    }
    @Test func staleVideoDoesNotMeanDisconnectedAndRepairIsBounded() {
        var p=VideoRecoveryPolicy()
        #expect(p.tick(sample(4)) == .registerAndEnable)
        #expect(p.tick(sample(5)) == nil)
        #expect(p.tick(sample(8)) == .registerAndEnable)
        #expect(p.tick(sample(12)) == .rebuildSharedTransport)
        for i in 16...300 { #expect(p.tick(sample(Double(i))) == nil) }
        #expect(p.attempts == 3 && p.state == .failed)
    }
    @Test func freshCompleteFramesNeverRebuildControlTransport() {
        var p=VideoRecoveryPolicy()
        #expect(p.tick(sample(4,packet:4,au:4)) == .repairDecoderAndEnable)
        #expect(p.tick(sample(8,packet:8,au:8)) == .repairDecoderAndEnable)
        for i in 12...30 { #expect(p.tick(sample(Double(i),packet:Double(i),au:Double(i))) == nil) }
        #expect(p.state == .failed && p.attempts == 2)
    }
    @Test func recoveryNeedsNewPicturesNotOldRetainedFrame() {
        var p=VideoRecoveryPolicy()
        _=p.tick(sample(4))
        #expect(!sample(5,packet:5,au:5,presented:0).live)
        #expect(p.tick(sample(5,packet:5,au:5,presented:5)) == nil)
        #expect(p.state == .healthy && p.attempts == 1)
        #expect(p.tick(sample(15.1,packet:15.1,au:15.1,presented:15.1)) == nil)
        #expect(p.attempts == 0)
    }
    @Test func aDisconnectedSessionAndBusyRecoveryDoNotOverlapRepairs() {
        var p=VideoRecoveryPolicy()
        #expect(p.tick(sample(8,connected:false)) == nil)
        #expect(p.tick(sample(8),busy:true) == nil)
        #expect(p.attempts == 0)
    }
}
