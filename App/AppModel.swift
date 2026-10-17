import Foundation
import Observation
import UIKit
import HeadLinkCore

@MainActor @Observable final class AppModel {
    let camera=PocketCamera()
    let instanceID=UUID().uuidString
    @ObservationIgnored private var loggedInvalidation:UInt64=0
    @ObservationIgnored var controller=TrackingController()
    @ObservationIgnored var probe=MotionProbe()
    @ObservationIgnored var commissioning=CommissioningSession()
    var motionLabel="未准备好"
    var notice:String?
    @ObservationIgnored var callbackHz=0.0
    @ObservationIgnored var sendHz=0.0
    @ObservationIgnored var now=ProcessInfo.processInfo.systemUptime
    @ObservationIgnored var diagnostics:[DiagnosticRow]=[]
    var exportURL:URL?
    var showingCalibration=false
    var showingCommissioning=false
    @ObservationIgnored var calibrationStarted:Double?
    var manualFirmware="" { didSet { if oldValue != manualFirmware { confirmedModel=false; revokeExperiment() } } }
    var confirmedModel=false { didSet { if oldValue != confirmedModel { revokeExperiment() } } }
    var fixedBaseConfirmed=false { didSet { if oldValue != fixedBaseConfirmed { revokeExperiment() } } }
    var followModeConfirmed=false { didSet { if oldValue != followModeConfirmed { revokeExperiment() } } }
    var experimentAccepted=false
    var savedProfileAccepted=false
    var controlRevision=0
    var telemetryRevision=0
    @ObservationIgnored private var presentationGate=PresentationGate<ControlPresentation>()
    @ObservationIgnored private var lastStepAt:Double?
    @ObservationIgnored private var loopGap=0.0
    @ObservationIgnored private var events:[ControlEvent]=[]
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
    var savedProfile:VerifiedLimits? { verifiedProfiles.first { $0.matches(currentIdentity) } }
    var canUseSavedProfile:Bool {
        guard let limits=savedProfile,let pose=camera.freshPose else { return false }
        return camera.transportHealthy && confirmedModel && fixedBaseConfirmed && followModeConfirmed &&
            camera.followModeBlock == nil && probe.movementObserved && canCalibrate && limits.clamp(pose.angles) == pose.angles
    }
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
        if !profileReady { result.append("未启用匹配的配置；请在跟随准备中选择已测配置或完成实验") }
        if savedProfileAccepted && savedProfile == nil { result.append("保存的局部配置与当前真实型号或固件不匹配") }
        if let limits=controller.limits,let pose=camera.freshPose,limits.clamp(pose.angles) != pose.angles {
            result.append("镜头当前角度超出已测局部范围，请用机身摇杆调整回范围内")
        }
        if !controller.hasCalibration { result.append("尚未校准头部与镜头方向") }
        if commissioning.running || commissioning.state == .awaitingConfirmation { result.append("云台实验仍在进行或等待确认") }
        if let rejection=controller.startBlocker(at:now),!result.contains(rejection.message) { result.append(rejection.message) }
        if !controller.hasCalibration,let invalidation=controller.invalidation,invalidation.calibrationID > 0 { result.append("上次校准失效原因："+invalidation.reason.message) }
        return result
    }
    var canStart:Bool { blockers.isEmpty }
    init() {
        axes=ControlAxes(rawValue:UserDefaults.standard.string(forKey:"axes") ?? "") ?? .both
        response=ResponseMode(rawValue:UserDefaults.standard.string(forKey:"response") ?? "") ?? .immediate
        controller.axes=axes; controller.response=response
        if let url=Bundle.main.url(forResource:"VerifiedProfiles",withExtension:"json"),let data=try? Data(contentsOf:url),
           let profiles=try? JSONDecoder().decode([VerifiedLimits].self,from:data) { verifiedProfiles=profiles.filter(\.valid) }
        camera.onVideoEvent={ [weak self] kind,detail in
            guard let self else { return }
            recordEvent(kind,detail:detail)
            if kind == "video_repair_start",isFollowing {
                camera.stopTargets(); controller.pause()
                notice="图传恢复开始，已暂停跟随；恢复后不会自动启动，控制状态与视频分别显示"
            }
            publishPresentation()
        }
        camera.onControlTransportReset={ [weak self] in
            guard let self else { return }
            camera.stopTargets(); controller.connectionChanged(false)
            revokeExperiment(reason:.connectionChanged)
            controller.connectionChanged(true); connectedBefore=true
            recordEvent("control_transport_reset",detail:"视频收流/组帧修复升级到共享UDP重建，校准已失效")
        }
        camera.onDisconnected={ [weak self] in
            guard let self else { return }
            if camera.lastDisconnect?.wasConnected == true { recordEvent("camera_disconnect",detail:camera.lastDisconnect?.reason ?? "unknown") }
            controller.connectionChanged(false); connectedBefore=false; revokeExperiment()
            if camera.lastDisconnect?.wasConnected == true { notice="相机连接中断："+(camera.lastDisconnect?.reason ?? "unknown") }
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
    func pauseForInactiveScene() {
        recordEvent("scene_inactive",detail:"停止运动但不重建会话；有效校准保留，绝不自动恢复")
        let wasFollowing=isFollowing
        camera.stopTargets()
        controller.pause(invalidateCalibration:controller.state == .calibrating,reason:.sceneInactive)
        if commissioning.running { commissioning.abort(.canceled); experimentAccepted=false; controller.limits=nil }
        if wasFollowing { notice="应用暂时失去活动状态，已暂停跟随；请回到前台后明确恢复" }
        publishPresentation()
    }
    func suspendControl() {
        recordEvent("scene_background",detail:"应用进入后台，停止控制并清除本次校准")
        camera.stopTargets(); controller.pause(invalidateCalibration:true,reason:.sceneBackground); motion.stop(); lastSensor=nil; probe.reset()
        revokeExperiment(reason:.sceneBackground); loop?.cancel(); loop=nil; UIApplication.shared.isIdleTimerDisabled=false
        publishPresentation()
    }
    func deactivate() {
        suspendControl()
        // Preserve the working manual Settings handoff and existing transport/video implementation.
        if camera.wifiRequest == nil { camera.disconnect(reason:"app_background") }
    }
    private func synchronizeLimits() {
        let identity=currentIdentity
        if let bound=commissioning.identity,(bound.model != identity.model || bound.firmware != identity.firmware) {
            revokeExperiment(); notice="机型或固件信息变化，本次实验配置已清除"
        }
        let verified=savedProfileAccepted ? savedProfile : nil
        if savedProfileAccepted && verified == nil {
            savedProfileAccepted=false; camera.stopTargets(); controller.pause(invalidateCalibration:true,reason:.configurationChanged)
            notice="真实型号或固件不再匹配，已撤销本次配置启用"
        }
        controller.limits=verified ?? (experimentAccepted && commissioning.readyForFollow ? commissioning.experimentalLimits : nil)
    }
    private func captureInputs() {
        let frame=ControlInputFrame.capture(readMotion:{
            let value=motion.read()
            return .init(sample:value.0,callbackHz:value.1,failed:value.2)
        },readCamera:{camera.pose},clock:{ProcessInfo.processInfo.systemUptime})
        now=frame.evaluatedAt; callbackHz=frame.motion.callbackHz
        let wasFollowing=isFollowing
        if frame.motion.failed { camera.stopTargets(); controller.motionUnavailable(); probe.reset() }
        if camera.connected != connectedBefore { controller.connectionChanged(camera.connected); connectedBefore=camera.connected }
        if let s=frame.motion.sample,s.sensorTime != lastSensor { controller.ingest(s); probe.ingest(s); lastSensor=s.sensorTime }
        if let p=frame.camera { controller.ingest(p) }
        let label:String
        if frame.motion.failed { label="耳机运动回调报告错误，请重新检查运动服务" }
        else if motion.authorization == .denied || motion.authorization == .restricted { label="运动权限未允许" }
        else if !motion.available { label="请在系统中连接支持运动数据的耳机" }
        else if probe.referenceChanged { label="姿态参考中断或跳变，请重设观察零点并重新校准" }
        else { label=(headAge.map{$0 <= 0.2} ?? false) ? "数据正常" : "等待新的运动数据" }
        if motionLabel != label { motionLabel=label }
        if wasFollowing && !isFollowing { stopAfterInputFailure() }
    }
    private func step() {
        camera.checkHealth(); camera.checkVideoHealth(); captureInputs()
        loopGap=lastStepAt.map{now-$0} ?? 0; lastStepAt=now
        defer { publishPresentation() }
        synchronizeLimits()
        if let reason=camera.followModeBlock,(commissioning.state != .inactive || isFollowing || savedProfileAccepted) {
            revokeExperiment(reason:.modeChanged); notice=reason
        }
        if camera.connected,showingCommissioning || isFollowing || commissioning.running || savedProfileAccepted,now-controlInfoAt >= 2 {
            camera.refreshControlInfo(); controlInfoAt=now
        }
        if controller.state == .calibrating {
            if let started=calibrationStarted,now-started > 12 { controller.pause(invalidateCalibration:true,reason:.calibrationTimeout); notice="校准未完成，请保持头部和机身静止后重试" }
            else {
                do { if try controller.collectCalibration(at:now) { showingCalibration=false; notice="已校准，请明确点击开始跟随"; haptic() } }
                catch { recordEvent("calibration_interrupted",detail:inputFailureDescription()); notice="校准暂停："+inputFailureDescription() }
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
                if !camera.submit(output) {
                    // A command rejection stops motion, but is not proof that the head reference changed.
                    // Genuine stale/jumped input independently invalidates calibration in the controller.
                    controller.pause(); camera.stopTargets()
                    recordEvent("target_rejected",detail:camera.lastCommandIssue ?? "unknown")
                    notice="跟随已暂停："+(camera.lastCommandIssue ?? "目标命令被拒绝")+"；未判定相机断连，请查看诊断"
                }
                // Arrival-time feedback is not time-aligned precision measurement. Only a persistent
                // large settled discrepancy is used as a conservative interlock.
                if let pose=camera.freshPose,!output.transitioning,CommissioningSession.distance(pose.angles,output.limited) > 2.5 {
                    if errorSince == nil { errorSince=now }
                    if now-(errorSince ?? now) > 1 { pause(); notice="目标与最新镜头回报持续相差较大，已暂停；请检查方向和机身是否移动" }
                } else { errorSince=nil }
            } else { stopAfterInputFailure() }
        } else { camera.stopTargets() }
        if now-rateAt >= 1 {
            let count=camera.nativeWrites
            sendHz=rateAt > 0 && count >= writesBefore ? Double(count-writesBefore)/(now-rateAt) : 0
            writesBefore=count; rateAt=now
        }
        if (UserDefaults.standard.bool(forKey:"recordDiagnostics") || commissioning.state != .inactive || savedProfileAccepted),now-diagnosticAt >= 0.1 {
            diagnosticAt=now
            diagnostics.append(.init(uptime:now,state:controller.state.rawValue,headAge:headAge,
                head:controller.head,probe:probe.look,raw:controller.rawTarget,command:camera.lastSubmittedAngles,
                actual:camera.freshPose?.angles,nativePitch:camera.freshPose?.nativePitch,callbackHz:callbackHz,sendHz:sendHz,
                testState:commissioning.state.rawValue,commandIssue:camera.lastCommandIssue))
            if diagnostics.count > 6000 { diagnostics.removeFirst(diagnostics.count-6000) }
        }
    }
    private func publishPresentation() {
        if let invalidation=controller.invalidation,invalidation.sequence != loggedInvalidation {
            loggedInvalidation=invalidation.sequence
            recordEvent("calibration_invalidated",detail:invalidation.reason.rawValue)
        }
        let state=ControlPresentation(state:controller.state,canStart:isFollowing ? false : canStart,
            canCalibrate:canCalibrate,profileReady:profileReady,hasCalibration:controller.hasCalibration,
            cameraFresh:camera.freshPose != nil,controlFresh:camera.controlReceiveFresh,previewLive:camera.previewLive,
            pictureAspect:Double(camera.decoder.pictureAspect),firmware:camera.status.firmware,recording:camera.actualRecording,
            recordingSeconds:camera.actualRecording == true ? camera.status.recordElapsedSec : 0,
            testState:commissioning.state,receiptCount:commissioning.receipts.count,
            probeReady:probe.movementObserved)
        let update=presentationGate.updates(control:state,at:ProcessInfo.processInfo.systemUptime)
        if update.controls { controlRevision &+= 1 }
        if update.telemetry { telemetryRevision &+= 1 }
    }
    private func recordEvent(_ kind:String,detail:String) {
        let time=ProcessInfo.processInfo.systemUptime
        events.append(.init(uptime:time,kind:kind,detail:detail,state:controller.state.rawValue,
            hasCalibration:controller.hasCalibration,cameraConnected:camera.connected,
            transportHealthy:camera.transportHealthy,headAge:controller.sample.map{time-$0.receivedAt},
            cameraAge:camera.pose.map{time-$0.receivedAt},loopGap:loopGap,nativeWrites:camera.nativeWrites,connectionEpoch:camera.connectionEpoch,calibrationID:controller.calibrationID,
            mode:camera.modeSummary,firmware:currentIdentity.firmware,cameraAngles:camera.pose?.angles))
        if events.count > 100 { events.removeFirst(events.count-100) }
    }
    private func inputFailureDescription() -> String {
        guard camera.connected else { return "相机已断连，请查看断连原因" }
        guard let sample=controller.sample else { return "耳机未提供有效姿态" }
        let age=now-sample.receivedAt
        if age < 0 { return "控制时钟早于耳机样本，已停止（时序错误）" }
        if age > controller.freshnessThreshold { return String(format:"耳机姿态已过期（%.0f ms）",age*1000) }
        guard let pose=controller.pose else { return "未收到有效镜头姿态" }
        if !pose.fresh(at:now) { return String(format:"镜头姿态已失效（%.0f ms）",(now-pose.receivedAt)*1000) }
        switch controller.failure {
        case .referenceJump:return "耳机姿态参考跳变或回调间隔超过200ms"
        case .vertical:return "头部接近竖直，方向解算不可用"
        case .invalidQuaternion:return "耳机姿态数值无效"
        case .unavailable:return "当前控制配置不可用"
        case .stale:return String(format:"控制节拍失效（本轮间隔%.0f ms）",loopGap*1000)
        default:return "控制状态失效：\(controller.failure.map{String(describing:$0)} ?? controller.state.rawValue)"
        }
    }
    private func stopAfterInputFailure() {
        camera.stopTargets()
        let reason=inputFailureDescription()
        recordEvent("input_paused",detail:reason)
        notice="跟随已暂停："+reason+"；需要重新校准。这不等同于相机断连。"
    }
    func resetProbe() { defer { publishPresentation() }; probe.reset(); notice="头部观察零点已重设；请分别左右转头、抬头低头，仅用于检查数据，不会转动云台" }
    func retryMotion() { defer { publishPresentation() }; motion.stop(); lastSensor=nil; controller.motionUnavailable(); probe.reset(); camera.stopTargets(); motion.start() }
    func revokeExperiment(reason:CalibrationInvalidationReason = .configurationChanged) { defer { publishPresentation() };
        camera.stopTargets(); controller.pause(invalidateCalibration:true,reason:reason); controller.limits=nil
        commissioning = .init(); experimentAccepted=false; savedProfileAccepted=false; errorSince=nil
    }
    func useSavedProfile() { defer { publishPresentation() };
        guard canUseSavedProfile else { notice="请核对真实型号、固件、固定机身和跟随模式，确认数据新鲜且镜头处于已测范围"; return }
        revokeExperiment(); savedProfileAccepted=true; synchronizeLimits()
        notice="已启用保存的局部配置，尚不运动。点击校准，并在弹窗点击开始校准；成功后点击开始／恢复跟随。"
    }
    func beginExperiment() { defer { publishPresentation() };
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
    func runTest(_ direction:TestDirection) { defer { publishPresentation() };
        guard !isFollowing,camera.transportHealthy,camera.followModeBlock == nil,let pose=camera.freshPose else { notice="无法测试：需要已连接且新鲜的镜头姿态及跟随模式"; return }
        controller.pause(invalidateCalibration:true,reason:.experimentStarted); experimentAccepted=false; controller.limits=nil
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
    func confirmTest() { defer { publishPresentation() };
        guard let pose=camera.freshPose,let receipt=commissioning.pendingReceipt,
              CommissioningSession.distance(pose.angles,receipt.target) <= 0.8,
              camera.followModeBlock == nil else { stopTest(); return }
        do { try commissioning.confirmPhysicalObservation(); notice=commissioning.needsReturn ? "已记录，请明确点击沿已测路径返回起点，再确认返回与停止。" : "已记录。完成左右、上下端点及返回后，可启用本次实验跟随。" }
        catch { notice="尚无可确认的到位与停止记录" }
    }
    func stopTest() { defer { publishPresentation() }; camera.stopTargets(); commissioning.abort(.canceled); experimentAccepted=false; controller.limits=nil; notice="实验已停止，已尝试发停止命令；请观察镜头，网络中断时无法确认送达" }
    func acceptExperimentalFollow() { defer { publishPresentation() };
        guard commissioning.readyForFollow,probe.movementObserved,canCalibrate,camera.followModeBlock == nil else { notice="请完成四个方向及返回确认，并确认耳机左右/上下姿态真实变化"; return }
        experimentAccepted=true; synchronizeLimits(); controller.pause(invalidateCalibration:true,reason:.experimentAccepted)
        notice="已启用本次连接的局部实验范围；请校准后明确点击开始。超出已测范围会限位，不会缩放头部角度。"
    }
    func calibrate() {
        defer { publishPresentation() }
        camera.checkHealth(); captureInputs()
        camera.stopTargets()
        do { try controller.beginCalibration(at:now); calibrationStarted=now; showingCalibration=true; notice=nil; recordEvent("calibration_started",detail:"user_action") }
        catch { notice="需要新鲜的耳机姿态和镜头反馈才能校准" }
    }
    func start() {
        defer { publishPresentation() }
        camera.checkHealth(); captureInputs(); synchronizeLimits()
        recordEvent("start_requested",detail:"user_action")
        guard canStart else { notice=blockers.joined(separator:"；"); recordEvent("start_blocked",detail:notice ?? "unknown"); return }
        do {
            guard camera.startTargets() else {
                recordEvent("start_rejected_native",detail:camera.lastCommandIssue ?? "native_queue_unavailable")
                notice="跟随未启动："+(camera.lastCommandIssue ?? "目标队列不可用")+"；校准是否有效见当前状态"
                return
            }
            // Queue ownership is established without sending a target. Re-snapshot after
            // the synchronous UDP handoff, then establish the control-loop time origin.
            captureInputs(); try controller.start(at:now)
            recordEvent("following_started",detail:"native_queue_armed")
            notice="固定基座1∶1跟随中；仅在已测局部范围内运行，起步与恢复受限速保护"; haptic()
        } catch {
            controller.pause(); camera.stopTargets()
            recordEvent("start_rejected",detail:String(describing:error))
            notice="跟随未启动："+(controller.lastStartRejection?.message ?? String(describing:error))
        }
    }
    func pause() { defer { publishPresentation() };
        recordEvent("user_paused",detail:"user_action")
        camera.stopTargets(); controller.pause(); errorSince=nil
        if commissioning.running { commissioning.abort(.canceled); experimentAccepted=false; controller.limits=nil }
        notice="跟随已暂停；已尝试发送停止，未收到停止ACK。机身移动时不保证锁定世界方向。"
    }
    func clearCalibration() { defer { publishPresentation() }; camera.stopTargets(); controller.pause(invalidateCalibration:true,reason:.userCleared) }
    func haptic() { if UserDefaults.standard.bool(forKey:"haptics") { UIImpactFeedbackGenerator(style:.light).impactOccurred() } }
    func exportDiagnostics() {
        camera.captureVideoDiagnostic()
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
                lastCommandIssue:camera.lastCommandIssue,calibrationComplete:controller.hasCalibration,
                configurationSource:savedProfileAccepted ? "saved-local-envelope" : (experimentAccepted ? "session-experiment" : "none"),
                events:events,lastDisconnect:camera.lastDisconnect,
                appVersion:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String,
                buildNumber:Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String,
                appInstanceID:instanceID,connectionEpoch:camera.connectionEpoch,calibrationID:controller.calibrationID,
                lastStartRejection:controller.lastStartRejection,currentStartBlocker:controller.startBlocker(at:now),calibrationInvalidation:controller.invalidation,
                video:camera.videoDiagnostic,videoHistory:camera.videoHistory)
            try encoder.encode(DiagnosticExport(schema:3,generatedAt:Date(),context:context,rows:diagnostics)).write(to:url,options:.atomic)
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
    let calibrationComplete:Bool; let configurationSource:String
    let events:[ControlEvent]; let lastDisconnect:CameraDisconnect?
    let appVersion:String?; let buildNumber:String?; let appInstanceID:String; let connectionEpoch:UInt64; let calibrationID:UInt64
    let lastStartRejection:TrackingStartRejection?; let currentStartBlocker:TrackingStartRejection?; let calibrationInvalidation:CalibrationInvalidation?
    let video:VideoDiagnostic?; let videoHistory:[VideoDiagnostic]
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

private struct ControlPresentation:Equatable {
    let state:TrackingState; let canStart:Bool; let canCalibrate:Bool; let profileReady:Bool; let hasCalibration:Bool
    let cameraFresh:Bool; let controlFresh:Bool; let previewLive:Bool; let pictureAspect:Double; let firmware:String?; let recording:Bool?; let recordingSeconds:Int
    let testState:CommissioningState; let receiptCount:Int; let probeReady:Bool
}
struct ControlEvent:Codable {
    let uptime:Double; let kind:String; let detail:String; let state:String; let hasCalibration:Bool
    let cameraConnected:Bool; let transportHealthy:Bool; let headAge:Double?; let cameraAge:Double?
    let loopGap:Double; let nativeWrites:Int; let connectionEpoch:UInt64; let calibrationID:UInt64
    let mode:String; let firmware:String; let cameraAngles:Angles?
}
