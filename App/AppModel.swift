import Foundation
import Observation
import UIKit
import HeadLinkCore

@MainActor @Observable final class AppModel {
    let camera=PocketCamera()
    var controller=TrackingController()
    var probe=MotionProbe()
    var commissioning=CommissioningSession()
    var motionLabel="未准备好"
    var notice:String?
    var callbackHz=0.0
    var sendHz=0.0
    var now=ProcessInfo.processInfo.systemUptime
    var diagnostics:[DiagnosticRow]=[]
    var exportURL:URL?
    var showingCalibration=false
    var showingCommissioning=false
    var calibrationStarted:Double?
    var manualFirmware="" { didSet { if oldValue != manualFirmware { confirmedModel=false; revokeExperiment() } } }
    var confirmedModel=false { didSet { if oldValue != confirmedModel { revokeExperiment() } } }
    var fixedBaseConfirmed=false { didSet { if oldValue != fixedBaseConfirmed { revokeExperiment() } } }
    var followModeConfirmed=false { didSet { if oldValue != followModeConfirmed { revokeExperiment() } } }
    var experimentAccepted=false
    var axes:ControlAxes = .both { didSet { pause(); controller.axes=axes; UserDefaults.standard.set(axes.rawValue,forKey:"axes") } }
    var response:ResponseMode = .immediate { didSet { pause(); controller.response=response; UserDefaults.standard.set(response.rawValue,forKey:"response") } }
    @ObservationIgnored let motion=HeadphoneMotion()
    @ObservationIgnored private var loop:Task<Void,Never>?
    @ObservationIgnored private var connectedBefore=false
    @ObservationIgnored private var lastSensor:Double?
    @ObservationIgnored private var rateAt=0.0
    @ObservationIgnored private var diagnosticAt=0.0
    @ObservationIgnored private var controlInfoAt=0.0
    @ObservationIgnored private var writesBefore=0
    @ObservationIgnored private var errorSince:Double?
    @ObservationIgnored private var verifiedProfiles:[VerifiedLimits]=[]
    var headAge:Double? { controller.sample.map { max(0,now-$0.receivedAt) } }
    var profileReady:Bool { controller.limits?.valid == true }
    var isFollowing:Bool { controller.state == .following }
    var canCalibrate:Bool { !commissioning.running && commissioning.state != .awaitingConfirmation && camera.freshPose != nil && (headAge.map{$0 < 0.2} ?? false) }
    var currentIdentity:CommissioningIdentity {
        .init(model:camera.selected?.model.name ?? "",firmware:camera.status.firmware ?? manualFirmware,
              firmwareSource:camera.status.firmware == nil ? (confirmedModel ? "operator-confirmed" : "operator-entered-unconfirmed") : "camera-report")
    }
    var blockers:[String] {
        var result:[String]=[]
        if !camera.connected { result.append("相机未连接") }
        if !camera.transportHealthy { result.append("相机传输未就绪") }
        if !(headAge.map{$0 <= controller.freshnessThreshold} ?? false) { result.append("未收到新鲜耳机姿态（需小于200ms）") }
        if !probe.movementObserved { result.append("尚未观察到左右和上下各至少3°的真实头部变化") }
        if camera.freshPose == nil { result.append("镜头姿态缺失或超过300ms") }
        if let reason=camera.followModeBlock { result.append(reason) }
        if !profileReady { result.append("未启用匹配的配置；请完成本次小角度实验") }
        if !controller.hasCalibration { result.append("尚未校准头部与镜头方向") }
        if commissioning.running || commissioning.state == .awaitingConfirmation { result.append("云台实验仍在进行或等待确认") }
        return result
    }
    var canStart:Bool { blockers.isEmpty }
    init() {
        axes=ControlAxes(rawValue:UserDefaults.standard.string(forKey:"axes") ?? "") ?? .both
        response=ResponseMode(rawValue:UserDefaults.standard.string(forKey:"response") ?? "") ?? .immediate
        controller.axes=axes; controller.response=response
        if let url=Bundle.main.url(forResource:"VerifiedProfiles",withExtension:"json"),let data=try? Data(contentsOf:url),
           let profiles=try? JSONDecoder().decode([VerifiedLimits].self,from:data) { verifiedProfiles=profiles.filter(\.valid) }
        camera.onDisconnected={ [weak self] in
            guard let self else { return }
            controller.connectionChanged(false); connectedBefore=false; revokeExperiment()
            confirmedModel=false; fixedBaseConfirmed=false; followModeConfirmed=false; manualFirmware=""
        }
    }
    func activate() {
        guard loop == nil else { return }
        motion.start()
        loop=Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }; step()
                do { try await Task.sleep(for:.milliseconds(25)) } catch { return }
            }
        }
    }
    func suspendControl() {
        camera.stopTargets(); controller.pause(invalidateCalibration:true); motion.stop(); lastSensor=nil; probe.reset()
        revokeExperiment(); loop?.cancel(); loop=nil; UIApplication.shared.isIdleTimerDisabled=false
    }
    func deactivate() {
        suspendControl()
        // Preserve the working manual Settings handoff and existing transport/video implementation.
        if camera.wifiRequest == nil { camera.disconnect() }
    }
    private func synchronizeLimits() {
        let identity=currentIdentity
        if let bound=commissioning.identity,(bound.model != identity.model || bound.firmware != identity.firmware) {
            revokeExperiment(); notice="机型或固件信息变化，本次实验配置已清除"
        }
        let verified=verifiedProfiles.first { $0.model == identity.model && $0.firmware == identity.firmware }
        controller.limits=verified ?? (experimentAccepted && commissioning.readyForFollow ? commissioning.experimentalLimits : nil)
    }
    private func step() {
        now=ProcessInfo.processInfo.systemUptime; camera.checkHealth()
        let read=motion.read(); callbackHz=read.1
        if read.2 { camera.stopTargets(); controller.motionUnavailable(); probe.reset(); motionLabel="运动数据中断，请重新连接" }
        if camera.connected != connectedBefore { controller.connectionChanged(camera.connected); connectedBefore=camera.connected }
        if let s=read.0,s.sensorTime != lastSensor { controller.ingest(s); probe.ingest(s); lastSensor=s.sensorTime }
        if let p=camera.pose { controller.ingest(p) }
        if motion.authorization == .denied || motion.authorization == .restricted { motionLabel="运动权限未允许" }
        else if !motion.available { motionLabel="请在系统中连接支持运动数据的耳机" }
        else if probe.referenceChanged { motionLabel="姿态参考中断或跳变，请重设观察零点并重新校准" }
        else { motionLabel=(headAge.map{$0 <= 0.2} ?? false) ? "数据正常" : "等待新的运动数据" }
        synchronizeLimits()
        if let reason=camera.followModeBlock,(commissioning.state != .inactive || isFollowing) {
            revokeExperiment(); notice=reason
        }
        if camera.connected,showingCommissioning || isFollowing || commissioning.running,now-controlInfoAt >= 2 {
            camera.refreshControlInfo(); controlInfoAt=now
        }
        if controller.state == .calibrating {
            if let started=calibrationStarted,now-started > 12 { controller.pause(invalidateCalibration:true); notice="校准未完成，请保持头部和机身静止后重试" }
            else {
                do { if try controller.collectCalibration(at:now) { showingCalibration=false; notice="已校准，请明确点击开始跟随"; haptic() } }
                catch { notice="校准中断：请检查耳机和镜头数据" }
            }
        }
        if commissioning.running {
            if let command=commissioning.tick(at:now,pose:camera.freshPose) {
                if camera.submit(angles:command.angles,nativePitch:command.nativePitch) { commissioning.noteSubmitted() }
                else { commissioning.abort(.transport) }
            }
            if commissioning.state != .moving { camera.stopTargets() }
            if commissioning.state == .failed { notice=commissioningFailure(commissioning.failure) }
        } else if isFollowing {
            if let output=controller.tick(at:now) {
                if !camera.submit(output) { controller.pause(invalidateCalibration:true); camera.stopTargets(); notice=camera.lastCommandIssue }
                // Arrival-time feedback is not time-aligned precision measurement. Only a persistent
                // large settled discrepancy is used as a conservative interlock.
                if let pose=camera.freshPose,!output.transitioning,CommissioningSession.distance(pose.angles,output.limited) > 2.5 {
                    if errorSince == nil { errorSince=now }
                    if now-(errorSince ?? now) > 1 { pause(); notice="目标与最新镜头回报持续相差较大，已暂停；请检查方向和机身是否移动" }
                } else { errorSince=nil }
            } else { camera.stopTargets(); notice="数据失效或姿态跳变，已暂停；请重新校准" }
        } else { camera.stopTargets() }
        if now-rateAt >= 1 {
            let count=camera.nativeWrites
            sendHz=rateAt > 0 && count >= writesBefore ? Double(count-writesBefore)/(now-rateAt) : 0
            writesBefore=count; rateAt=now
        }
        if (UserDefaults.standard.bool(forKey:"recordDiagnostics") || commissioning.state != .inactive),now-diagnosticAt >= 0.1 {
            diagnosticAt=now
            diagnostics.append(.init(uptime:now,state:controller.state.rawValue,headAge:headAge,
                head:controller.head,probe:probe.look,raw:controller.rawTarget,command:camera.lastSubmittedAngles,
                actual:camera.freshPose?.angles,nativePitch:camera.freshPose?.nativePitch,callbackHz:callbackHz,sendHz:sendHz,
                testState:commissioning.state.rawValue,commandIssue:camera.lastCommandIssue))
            if diagnostics.count > 6000 { diagnostics.removeFirst(diagnostics.count-6000) }
        }
    }
    func resetProbe() { probe.reset(); notice="头部观察零点已重设；请分别左右转头、抬头低头，仅用于检查数据，不会转动云台" }
    func retryMotion() { motion.stop(); lastSensor=nil; controller.motionUnavailable(); probe.reset(); camera.stopTargets(); motion.start() }
    func revokeExperiment() {
        camera.stopTargets(); controller.pause(invalidateCalibration:true); controller.limits=nil
        commissioning = .init(); experimentAccepted=false; errorSince=nil
    }
    func beginExperiment() {
        guard camera.transportHealthy,let pose=camera.freshPose,confirmedModel,fixedBaseConfirmed,followModeConfirmed,
              currentIdentity.valid,camera.followModeBlock == nil else {
            notice="请核对真实Pocket 4机型与固件、固定机身和跟随模式，并等待新鲜镜头姿态"; return
        }
        revokeExperiment(); camera.refreshControlInfo()
        // These are upstream encoder/path bounds, never claimed as this device's mechanical range.
        let candidate=VerifiedLimits(model:currentIdentity.model,firmware:currentIdentity.firmware,evidence:"upstream command envelope only",
            yawMin:OpenCineBounds.panMin,yawMax:OpenCineBounds.panMax,pitchMin:OpenCineBounds.tiltMin,pitchMax:OpenCineBounds.tiltMax)
        do { try commissioning.begin(identity:currentIdentity,pose:pose,candidate:candidate,at:now); notice="实验已准备，尚未发运动命令。请选择一个约5°测试，活动方向需无遮挡。" }
        catch { notice="当前姿态超出上游已核实命令范围，不能开始实验；请查看诊断" }
    }
    func runTest(_ direction:TestDirection) {
        guard !isFollowing,camera.transportHealthy,camera.followModeBlock == nil,let pose=camera.freshPose else { notice="无法测试：需要已连接且新鲜的镜头姿态及跟随模式"; return }
        controller.pause(invalidateCalibration:true); experimentAccepted=false; controller.limits=nil
        do {
            try commissioning.startMove(direction,pose:pose,at:now)
            guard camera.startTargets() else { throw CommissioningError.transport }
            notice="小角度实验中，请保持机身固定，随时可点击停止"
        } catch {
            camera.stopTargets()
            if commissioning.running { commissioning.abort(.transport) }
            notice="当前测试不可开始：请先确认上一项，并沿已测路径返回起点；超出候选范围的方向不可用"
        }
    }
    func confirmTest() {
        guard let pose=camera.freshPose,let receipt=commissioning.pendingReceipt,
              CommissioningSession.distance(pose.angles,receipt.target) <= 0.8,
              camera.followModeBlock == nil else { stopTest(); return }
        do { try commissioning.confirmPhysicalObservation(); notice=commissioning.needsReturn ? "已记录，请明确点击沿已测路径返回起点，再确认返回与停止。" : "已记录。完成左右、上下端点及返回后，可启用本次实验跟随。" }
        catch { notice="尚无可确认的到位与停止记录" }
    }
    func stopTest() { camera.stopTargets(); commissioning.abort(.canceled); experimentAccepted=false; controller.limits=nil; notice="实验已停止，已尝试发停止命令；请观察镜头，网络中断时无法确认送达" }
    func acceptExperimentalFollow() {
        guard commissioning.readyForFollow,probe.movementObserved,canCalibrate,camera.followModeBlock == nil else { notice="请完成四个方向及返回确认，并确认耳机左右/上下姿态真实变化"; return }
        experimentAccepted=true; synchronizeLimits(); controller.pause(invalidateCalibration:true)
        notice="已启用本次连接的局部实验范围；请校准后明确点击开始。超出已测范围会限位，不会缩放头部角度。"
    }
    func calibrate() {
        camera.stopTargets()
        do { try controller.beginCalibration(at:now); calibrationStarted=now; showingCalibration=true; notice=nil }
        catch { notice="需要新鲜的耳机姿态和镜头反馈才能校准" }
    }
    func start() {
        guard canStart else { notice=blockers.joined(separator:"；"); return }
        do {
            try controller.start(at:now)
            guard camera.startTargets() else { throw TrackingError.unavailable }
            notice="固定基座1∶1跟随中；仅在已测局部范围内运行，起步与恢复受限速保护"; haptic()
        } catch { controller.pause(); camera.stopTargets(); notice="启动被拒绝：校准时镜头可能不在已测范围，或数据已过期" }
    }
    func pause() {
        camera.stopTargets(); controller.pause(); errorSince=nil
        if commissioning.running { commissioning.abort(.canceled); experimentAccepted=false; controller.limits=nil }
        notice="跟随已暂停；已尝试发送停止，未收到停止ACK。机身移动时不保证锁定世界方向。"
    }
    func clearCalibration() { camera.stopTargets(); controller.pause(invalidateCalibration:true) }
    func haptic() { if UserDefaults.standard.bool(forKey:"haptics") { UIImpactFeedbackGenerator(style:.light).impactOccurred() } }
    func exportDiagnostics() {
        do {
            let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            let url=FileManager.default.temporaryDirectory.appendingPathComponent("HeadLink-diagnostics.json")
            let context=DiagnosticContext(iOS:UIDevice.current.systemVersion,model:camera.selected?.model.name,
                modelID:camera.selected?.modelId,reportedFirmware:camera.status.firmware,operatorFirmware:manualFirmware,
                firmwareSource:currentIdentity.firmwareSource,mode:camera.modeSummary,attitudeLength:camera.lastAttitudeLength,
                attitudeFrames:camera.attitudeFrames,poseFrames:camera.poseFrames,probeMovementObserved:probe.movementObserved,
                motionAvailable:motion.available,motionAuthorization:Int(motion.authorization.rawValue),
                controllerState:controller.state.rawValue,trackingFailure:controller.failure.map{String(describing:$0)},
                blockers:blockers,receipts:commissioning.receipts,pendingReceipt:commissioning.pendingReceipt,
                limits:controller.limits,stopAttemptAt:camera.lastStopAttemptAt,
                targetSubmissions:camera.targetSubmissions,nativeWrites:camera.nativeWrites,
                lastSubmittedAngles:camera.lastSubmittedAngles,lastSubmittedNativePitch:camera.lastSubmittedNativePitch,
                lastCommandIssue:camera.lastCommandIssue)
            try encoder.encode(DiagnosticExport(schema:2,generatedAt:Date(),context:context,rows:diagnostics)).write(to:url,options:.atomic)
            exportURL=url
        } catch { notice="诊断导出失败，请重试" }
    }
}
// Read directly from the pinned DJI encoder limits; this is not a hardware capability declaration.
import OpenCineDJI
private enum OpenCineBounds {
    static let panMin=GimbalReach.panMinDeg, panMax=GimbalReach.panMaxDeg
    static let tiltMin=GimbalReach.tiltMinDeg, tiltMax=GimbalReach.tiltMaxDeg
}
struct DiagnosticRow:Codable {
    let uptime:Double; let state:String; let headAge:Double?
    let head:Angles?; let probe:Angles?; let raw:Angles?; let command:Angles?; let actual:Angles?; let nativePitch:Double?
    let callbackHz:Double; let sendHz:Double; let testState:String; let commandIssue:String?
}
struct DiagnosticContext:Codable {
    let iOS:String; let model:String?; let modelID:Int?; let reportedFirmware:String?; let operatorFirmware:String
    let firmwareSource:String; let mode:String; let attitudeLength:Int?; let attitudeFrames:Int; let poseFrames:Int
    let probeMovementObserved:Bool; let motionAvailable:Bool; let motionAuthorization:Int; let controllerState:String; let trackingFailure:String?
    let blockers:[String]; let receipts:[MovementReceipt]; let pendingReceipt:MovementReceipt?
    let limits:VerifiedLimits?; let stopAttemptAt:Double?
    let targetSubmissions:Int; let nativeWrites:Int; let lastSubmittedAngles:Angles?; let lastSubmittedNativePitch:Double?; let lastCommandIssue:String?
}
struct DiagnosticExport:Codable { let schema:Int; let generatedAt:Date; let context:DiagnosticContext; let rows:[DiagnosticRow] }
func commissioningFailure(_ reason:CommissioningError?) -> String {
    switch reason {
    case .stale:return "实验暂停：镜头姿态缺失或超过300ms"
    case .schedulerGap:return "实验暂停：控制节拍超过200ms"
    case .wrongDirection:return "实验停止：实际回报方向与目标相反，请导出诊断"
    case .crossAxisMovement:return "实验停止：另一轴出现明显运动，请检查机身固定和云台模式"
    case .range:return "实验停止：回报超出本次目标或上游命令范围"
    case .timeout:return "实验停止：未能及时到位或收到足够停稳回报，请导出诊断"
    case .didNotHold:return "停止后回报仍有明显移动，实验未通过"
    case .transport:return "实验停止：目标队列或相机传输拒绝，详见命令链路状态"
    case .modeChanged:return "实验停止：云台模式发生变化"
    case .canceled:return "用户停止实验；该项未通过"
    default:return "实验条件不满足，请检查设备信息、数据时效和确认步骤"
    }
}
