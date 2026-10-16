import Foundation
import Observation
import OpenCineDJI
import OpenCineDJIApple
import OpenCineMotion
import OpenCineApple
import HeadLinkCore

/// Production adapter. Wire values and connection sequencing come only from pinned OpenCine.
@MainActor @Observable final class PocketCamera {
    var sightings: [DjiAppleSighting] = []
    var message = "未连接"
    var connected = false
    var selected: DjiAppleSighting?
    var pose: CameraPose?
    var lastAttitudeLength:Int?
    var attitudeFrames=0
    var poseFrames=0
    var parameterAt:Double?
    var lastSubmittedAngles:Angles?
    var lastSubmittedNativePitch:Double?
    var targetSubmissions=0
    var lastCommandIssue:String?
    var lastStopAttemptAt:Double?

    var status = CameraStatus()
    var statusAt: Double?
    var recordingAt: Double?
    var recordPending: Bool?
    var recordDeadline: Double?
    var recordError: String?
    var wifiRequest: DjiAppleConnectionTransport.AccessPointJoin?
    var decoder = MonitorLiveVideoRuntime()
    var lastPresentedAt: Double?
    var onDisconnected: (() -> Void)?
    @ObservationIgnored private var link: DjiAppleDatalink?
    @ObservationIgnored private var scanTask: Task<Void,Never>?
    @ObservationIgnored private var wifiContinue = false
    @ObservationIgnored private var targetToken: UInt64?
    @ObservationIgnored private var tokenCounter: UInt64 = 0
    @ObservationIgnored private var connectRun: DjiAppleConnectionRun?
    @ObservationIgnored private lazy var bluetooth = DjiAppleBluetoothLink(host: .init(
        logSubsystem:"org.headlink.app", bluetoothDenied:"请在设置中允许蓝牙权限",bluetoothOff:"请开启蓝牙",bluetoothNotReady:"蓝牙尚未就绪"))
    @ObservationIgnored private lazy var exchange = DjiAppleControlExchange(
        endpoint:.init(writeBLE:{ [weak self] in self?.bluetooth.send($0) },writeDatalink:{ [weak self] frame in
            guard let link=self?.link else { return .skipped }; return .queued(link.send(frame))
        }),context:{ [weak self] in .init(canTransmit:self?.connected == true,reported:self?.status) })
    @ObservationIgnored private lazy var heartbeat = DjiAppleSessionHeartbeat(
        endpoint:.init(writeBLE:{ [weak self] in self?.bluetooth.send($0) },registerDatalink:{ [weak self] in self?.link?.reRegister() },transport:{ .init() }),
        context:{ [weak self] in .init(live:self?.connected == true,ownedConnection:true,
            pathReady:DjiAppleWiFiJoiner.isCameraPathReady(),sceneActive:true,holdsMonitor:true) },event:{ [weak self] event in
            if event == .cameraPathLost { self?.disconnect() }
        })
    var now: Double { ProcessInfo.processInfo.systemUptime }
    var freshPose: CameraPose? { guard let pose,pose.fresh(at:now) else { return nil }; return pose }
    var actualRecording: Bool? {
        guard connected,status.recordingReported,let t=recordingAt,now-t <= 2 else { return nil }
        return status.isRecording
    }
    var previewLive: Bool { guard let t=lastPresentedAt else { return false }; return connected && now-t < 0.7 }
    var transportHealthy: Bool { connected && link?.isFlowHealthy == true }
    // Counts actual UDP writes, not UI timer ticks or accepted mailbox submissions.
    var nativeWrites: Int { link?.headLinkNativeWriteCount ?? 0 }

    func scan() {
        disconnect(); sightings=[]; message="搜索相机…"
        scanTask=Task { [weak self] in
            guard let self else { return }
            guard await bluetooth.waitUntilPoweredOn() else { message=bluetooth.unavailableReason; return }
            for await sighting in bluetooth.scan() {
                guard !Task.isCancelled else { break }
                if sighting.model.hasGimbal, !sightings.contains(where:{$0.id == sighting.id}) { sightings.append(sighting) }
            }
        }
    }
    func connect(_ sighting: DjiAppleSighting) {
        disconnect(); selected=sighting; message="连接中…"
        decoder=MonitorLiveVideoRuntime(); decoder.onPresentedFrame={ [weak self] in self?.lastPresentedAt=self?.now }
        var transport=DjiAppleConnectionTransport(bluetooth:bluetooth)
        // Replace only the OS Wi-Fi action; retain upstream pairing, identity verification and registration.
        transport.network.joinAccessPoint={ [weak self] request in
            guard let self else { throw CancellationError() }
            wifiRequest=request; wifiContinue=false; message="请手动加入相机 Wi-Fi"
            defer { wifiRequest=nil }
            let deadline=ContinuousClock.now.advanced(by:.seconds(180))
            while !wifiContinue {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else { throw DjiAppleConnectionRun.Failure.timeout }
                try await Task.sleep(for:.milliseconds(150))
            }
            guard DjiAppleWiFiJoiner.isCameraPathReady() else { throw DjiAppleConnectionRun.Failure.hostWiFi("manual path unavailable") }
        }
        transport.network.currentSSID={ nil }
        transport.network.leave={ _ in }
        connectRun=DjiAppleConnectionRun(transport:transport,exchange:exchange,heartbeat:heartbeat,
            credentials:.init(savedPath:{ _,_ in .init() },resolveWiFi:{ _ in .init() },joinPolicy:{ _,_,_ in .init() },
                validateSSID:{ _,_,_ in },persist:{ _,_,_ in },rejectCached:{ _,_ in }),
            native:.init(observe:{ [weak self] in .init(ownsConnection:true,endpoint:self?.link) },prepare:{ _,_,_ in },
                attach:{ [weak self] endpoint,_,_ in
                    self?.link?.close(); self?.link=endpoint as? DjiAppleDatalink
                    self?.bindLink()
                },registered:{ [weak self] _,_,_ in
                    self?.connected=true; self?.message="已连接（兼容性待真机验证）"
                    self?.link?.startLiveView()
                }), event:{ [weak self] event in
                    guard let self else { return }
                    switch event {
                    case .stage(let stage,_): message=Self.stageLabel(stage)
                    case .finished(.failure(_),_):
                        disconnect(); message="连接失败：请检查相机确认、Wi-Fi 和本地网络权限后重试"
                    default: break
                    }
                })
        connectRun?.replace(target:.init(id:sighting.id.uuidString,name:sighting.name,model:sighting.model,modelId:sighting.modelId),route:.cameraAccessPoint)
    }
    private static func stageLabel(_ stage: DJIConnectionStage) -> String {
        // Descriptions are intentionally independent of the protocol's internal progress text.
        switch stage {
        case .connectingBluetooth: return "正在连接蓝牙"
        case .pairing, .awaitingApproval: return "请在相机上确认配对"
        case .readingWiFi: return "正在读取相机连接信息"
        case .joiningWiFi: return "等待手动加入 Wi-Fi"
        case .openingDatalink: return "正在验证相机通信"
        default: return "正在建立连接"
        }
    }
    private func bindLink() {
        guard let link else { return }
        link.onStatusFrame={ [weak self] frame in self?.receive(frame) }
        let source=decoder.sourceToken
        link.onAccessUnit={ [weak self] bytes in
            guard let self,self.connected else { return }
            _=decoder.decode(accessUnit:bytes,source:source)
        }
        link.onVideoDiscontinuity={ [weak self] in self?.decoder.noteCompressedDiscontinuity() }
    }
    private func receive(_ frame: Duml.Frame) {
        exchange.receive(frame)
        if frame.cmdSet == 4,frame.cmdId == 5 { lastAttitudeLength=frame.payload.count; attitudeFrames += 1 }
        if CameraStatusDecoder.apply(frame,to:&status,model:selected?.model) {
            statusAt=now
            if frame.cmdSet == 4,frame.cmdId == 0x50 { parameterAt=now }
        }
        if frame.cmdSet == 2,frame.cmdId == 0x80,frame.payload.count >= 13 {
            recordingAt=now
            if recordPending == status.isRecording { recordPending=nil; recordDeadline=nil }
        }
        if frame.cmdSet == 4,frame.cmdId == 5,
           let yaw=GimbalStick.yawTenthDeg(frame.payload),let pitch=GimbalStick.pitchTenthDeg(frame.payload),
           let native=GimbalStick.nativePitchTenthDeg(frame.payload) {
            poseFrames += 1
            let unwrapped=GimbalWaypoint.unwrapYaw(Double(yaw)/10)
            pose = .init(angles:.init(yaw:unwrapped,pitch:Double(pitch)/10),nativePitch:Double(native)/10,receivedAt:now)
        }
    }
    func confirmWiFi() { wifiContinue=true }
    func startTargets() -> Bool {
        guard transportHealthy,freshPose != nil else { return false }
        stopTargets(); tokenCounter &+= 1; targetToken=tokenCounter; link?.beginNativeTargets(token:tokenCounter); return true
    }
    func submit(_ output: TrackingOutput) -> Bool {
        submit(angles:output.command,nativePitch:output.nativePitch)
    }
    func submit(angles:Angles,nativePitch:Double) -> Bool {
        guard transportHealthy else { lastCommandIssue="相机传输不可用"; return false }
        guard freshPose != nil else { lastCommandIssue="镜头姿态已过期或布局不受支持"; return false }
        guard let token=targetToken else { lastCommandIssue="目标流未启动或已经暂停"; return false }
        guard let frame=Commands.gimbalTimedTarget(yawDeg:angles.yaw,nativePitchDeg:nativePitch,duration:0.1) else {
            lastCommandIssue="角度被已核实命令编码器拒绝"; return false
        }
        guard link?.noteNativeTarget(frame,token:token) == true else {
            lastCommandIssue="目标队列拒绝：可能被底层新鲜度或可达路径检查停止"; return false
        }
        lastSubmittedAngles=angles; lastSubmittedNativePitch=nativePitch; targetSubmissions += 1; lastCommandIssue=nil
        return true
    }
    func refreshControlInfo() {
        guard connected else { return }
        _=link?.sendUntracked(Commands.gimbalParamsGet())
    }
    var followModeBlock:String? {
        if let family=status.gimbalModeFamily, family != .follow { return "机身当前不是跟随模式，请在相机下拉菜单选择跟随" }
        if let parameterAt,now-parameterAt < 3,status.gimbalParams?.tiltLock == .locked {
            return "相机报告俯仰已锁定，请在机身改为跟随模式"
        }
        return nil
    }
    var modeSummary:String {
        guard let family=status.gimbalModeFamily,let pose,pose.fresh(at:now) else { return "不可用；请在机身下拉菜单核对" }
        switch family {
        case .directionLock:return "方向锁定（姿态推送）"
        case .fpv:return "FPV（姿态推送）"
        case .follow:
            guard let parameterAt,now-parameterAt < 3,let params=status.gimbalParams else { return "跟随族；俯仰锁定参数未收到" }
            return params.tiltLock == .unlocked ? "跟随／俯仰未锁定（真实回报）" : "俯仰锁定（真实回报）"
        }
    }
    func stopTargets() {
        guard let token=targetToken else { return }; targetToken=nil
        lastStopAttemptAt=now
        link?.endNativeTargets(token:token)
        // This command is notify-only; no claim that a stopped pose was confirmed.
    }
    func toggleRecording() {
        guard connected,recordPending == nil,let current=actualRecording else { return }
        recordError=nil; recordPending = !current; recordDeadline=now+4
        _=link?.send(current ? Commands.recordStop() : Commands.recordStart())
    }
    func checkHealth() {
        if let deadline=recordDeadline,now >= deadline { recordPending=nil; recordDeadline=nil; recordError="录像请求未确认，请检查相机" }
        if connected, !transportHealthy || (statusAt.map { now-$0 > 3 } ?? false) {
            disconnect(); message="连接中断，停止未确认"
        }
    }
    func disconnect() {
        stopTargets(); scanTask?.cancel(); scanTask=nil; bluetooth.stopScan()
        connectRun?.retire(); connectRun=nil; heartbeat.stop(); exchange.stopBLEDrain(); exchange.retire(DjiAppleControlExchange.Error.disconnected)
        link?.close(); link=nil; bluetooth.disconnect(); decoder.close(); lastPresentedAt=nil
        lastAttitudeLength=nil; attitudeFrames=0; poseFrames=0; parameterAt=nil
        lastSubmittedAngles=nil; lastSubmittedNativePitch=nil; targetSubmissions=0; lastCommandIssue=nil; lastStopAttemptAt=nil
        connected=false; pose=nil; status = .init(); statusAt=nil; recordingAt=nil
        recordPending=nil; recordDeadline=nil; wifiRequest=nil; message="未连接"; onDisconnected?()
    }
}
