import Testing
import OpenCineDJI

struct ProtocolTests {
    @Test func splitNotificationsCorruptionAndUnknownOpcode() {
        // Synthetic packet using the real upstream encoder: no private camera capture.
        let frame=Duml.Frame(sender:1,receiver:2,seq:42,flags:0xc0,cmdSet:0xee,cmdId:0xef,payload:[0,1,2,3])
        let bytes=Duml.encode(frame)
        for split in 0...bytes.count {
            var assembler=DumlNotificationAssembler()
            let result=assembler.append(Array(bytes.prefix(split)))+assembler.append(Array(bytes.dropFirst(split)))
            #expect(result == [frame])
        }
        var bad=bytes; bad[12] ^= 0xff
        var assembler=DumlNotificationAssembler()
        #expect(assembler.append(bad).isEmpty)
        #expect(assembler.append(bytes) == [frame])
        var badHeader=bytes;badHeader[3] ^= 1
        var other=DumlNotificationAssembler()
        #expect(other.append(badHeader).isEmpty)
        #expect(other.append(bytes) == [frame])
    }
    @Test func telemetryIsNotDerivedFromCommandOrAck() {
        var status=CameraStatus()
        #expect(!status.recordingReported)
        _=CameraStatusDecoder.apply(Commands.recordStart(),to:&status)
        #expect(!status.recordingReported)
        let ack=Duml.Frame(sender:1,receiver:2,seq:0,flags:0xc0,cmdSet:2,cmdId:2,payload:[0])
        _=CameraStatusDecoder.apply(ack,to:&status)
        #expect(!status.recordingReported)
        #expect(GimbalStick.yawTenthDeg([0,0]) == nil)
        #expect(GimbalStick.pitchTenthDeg(Array(repeating:0,count:49)) == nil)
        #expect(GimbalStick.nativePitchTenthDeg(Array(repeating:0,count:51)) == nil)
    }
    @Test func assemblerBoundsAndTruncation() {
        var assembler=DumlNotificationAssembler()
        #expect(assembler.append(Array(repeating:0x55,count:5000)).isEmpty)
        let f=Commands.recordStop(seq:77);let bytes=Duml.encode(f)
        #expect(assembler.append(Array(bytes.dropLast())).isEmpty)
        #expect(assembler.append([bytes.last!]) == [f])
    }
}
