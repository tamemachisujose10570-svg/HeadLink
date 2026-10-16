import Foundation
import Observation
import UIKit
import HeadLinkCore

@MainActor @Observable final class AppModel {
    let camera=PocketCamera()
    var controller=TrackingController()
    var motionLabel="未准备好"
    var notice: String?
    var callbackHz=0.0
    var sendHz=0.0
    var now=ProcessInfo.processInfo.systemUptime
    var diagnostics: [DiagnosticRow]=[]
    var exportURL: URL?
    var showingCalibration=false
    var calibrationStarted: Double?
    var axes: ControlAxes = .both { didSet { pause(); controller.axes=axes; UserDefaults.standard.set(axes.rawValue,forKey:"axes") } }
    var response: ResponseMode = .immediate { didSet { pause(); controller.response=response; UserDefaults.standard.set(response.rawValue,forKey:"response") } }
    @ObservationIgnored let motion=HeadphoneMotion()
    @ObservationIgnored private var loop: Task<Void,Never>?
    @ObservationIgnored private var connectedBefore=false
    @ObservationIgnored private var lastSensor: Double?
    @ObservationIgnored private var rateAt=0.0
    @ObservationIgnored private var writesBefore=0
    @ObservationIgnored private var diagnosticAt=0.0
    @ObservationIgnored private var verifiedProfiles: [VerifiedLimits]=[]
    var profileReady: Bool { controller.limits != nil }
    var headAge: Double? { controller.sample.map { max(0,now-$0.receivedAt) } }
    var isFollowing: Bool { controller.state == .following }
    var canCalibrate: Bool { camera.freshPose != nil && (headAge.map{$0 < 0.2} ?? false) }
    var canStart: Bool { profileReady && controller.hasCalibration && canCalibrate }
    init() {
        axes=ControlAxes(rawValue:UserDefaults.standard.string(forKey:"axes") ?? "") ?? .both
        response=ResponseMode(rawValue:UserDefaults.standard.string(forKey:"response") ?? "") ?? .immediate
        controller.axes=axes; controller.response=response
        if let url=Bundle.main.url(forResource:"VerifiedProfiles",withExtension:"json"),
           let data=try? Data(contentsOf:url),let profiles=try? JSONDecoder().decode([VerifiedLimits].self,from:data) { verifiedProfiles=profiles.filter(\.valid) }
        camera.onDisconnected={ [weak self] in
            self?.controller.connectionChanged(false); self?.connectedBefore=false
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
        camera.stopTargets(); controller.pause(invalidateCalibration:true); motion.stop(); lastSensor=nil
        loop?.cancel(); loop=nil; UIApplication.shared.isIdleTimerDisabled=false
    }
    func deactivate() {
        suspendControl()
        // The manual Settings handoff must keep its finite connection attempt alive.
        if camera.wifiRequest == nil { camera.disconnect() }
    }
    private func step() {
        now=ProcessInfo.processInfo.systemUptime; camera.checkHealth()
        let read=motion.read(); callbackHz=read.1
        if read.2 { camera.stopTargets(); controller.motionUnavailable(); motionLabel="运动数据中断，请重新连接" }
        if camera.connected != connectedBefore {
            controller.connectionChanged(camera.connected); connectedBefore=camera.connected
            controller.limits=verifiedProfiles.first { $0.model == camera.selected?.model.name && $0.firmware == camera.status.firmware }
        }
        if camera.connected,controller.limits == nil {
            controller.limits=verifiedProfiles.first { $0.model == camera.selected?.model.name && $0.firmware == camera.status.firmware }
        }
        if let s=read.0,s.sensorTime != lastSensor { controller.ingest(s); lastSensor=s.sensorTime }
        if let p=camera.pose { controller.ingest(p) }
        if motion.authorization == .denied || motion.authorization == .restricted { motionLabel="运动权限未允许" }
        else if !motion.available { motionLabel="请在系统中连接支持运动数据的耳机" }
        else { motionLabel=(headAge.map{$0 <= 0.2} ?? false) ? "数据正常" : "等待新的运动数据" }
        if controller.state == .calibrating {
            if let started=calibrationStarted,now-started > 12 { controller.pause(invalidateCalibration:true); notice="校准未完成，请保持头部和机身静止后重试" }
            else {
                do {
                    if try controller.collectCalibration(at:now) { showingCalibration=false; notice="已校准，请点击开始跟随"; haptic() }
                } catch { notice="校准中断：请检查耳机和镜头数据" }
            }
        }
        if isFollowing {
            if let output=controller.tick(at:now) {
                if !camera.submit(output) { controller.pause(invalidateCalibration:true); camera.stopTargets(); notice="目标命令未被发送，请重新检查连接并校准" }
            } else { camera.stopTargets(); notice="数据失效或姿态跳变，已暂停；请重新校准" }
        } else { camera.stopTargets() }
        if now-rateAt >= 1 {
            let count=camera.nativeWrites
            sendHz=rateAt > 0 && count >= writesBefore ? Double(count-writesBefore)/(now-rateAt) : 0
            writesBefore=count; rateAt=now
        }
        if UserDefaults.standard.bool(forKey:"recordDiagnostics"),now-diagnosticAt >= 0.1 {
            diagnosticAt=now
            diagnostics.append(.init(uptime:now,state:controller.state.rawValue,headAge:headAge,
                head:controller.head,raw:controller.rawTarget,command:controller.output?.command,
                actual:camera.freshPose?.angles,callbackHz:callbackHz,sendHz:sendHz))
            if diagnostics.count > 6000 { diagnostics.removeFirst(diagnostics.count-6000) }
        }
    }
    func retryMotion() { motion.stop(); lastSensor=nil; controller.motionUnavailable(); camera.stopTargets(); motion.start() }
    func calibrate() {
        camera.stopTargets()
        do { try controller.beginCalibration(at:now); calibrationStarted=now; showingCalibration=true; notice=nil }
        catch { notice="需要新鲜的耳机姿态和镜头反馈才能校准" }
    }
    func start() {
        do {
            try controller.start(at:now)
            guard camera.startTargets() else { throw TrackingError.unavailable }
            notice="固定基座跟随中；起步与恢复采用受限速度过渡"; haptic()
        } catch { controller.pause(); camera.stopTargets(); notice="尚不能开始：请检查校准、数据及机型验证配置" }
    }
    func pause() { camera.stopTargets(); controller.pause(); notice="跟随已暂停；已尝试发送停止，未确认镜头静止。移动机身时不保证锁定世界方向。" }
    func clearCalibration() { camera.stopTargets(); controller.pause(invalidateCalibration:true) }
    func haptic() { if UserDefaults.standard.bool(forKey:"haptics") { UIImpactFeedbackGenerator(style:.light).impactOccurred() } }
    func exportDiagnostics() {
        do {
            let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            let url=FileManager.default.temporaryDirectory.appendingPathComponent("HeadLink-diagnostics.json")
            try encoder.encode(DiagnosticExport(schema:1,generatedAt:Date(),rows:diagnostics)).write(to:url,options:.atomic)
            exportURL=url
        } catch { notice="诊断导出失败，请重试" }
    }
}
struct DiagnosticRow: Codable {
    let uptime:Double; let state:String; let headAge:Double?
    let head:Angles?; let raw:Angles?; let command:Angles?; let actual:Angles?
    let callbackHz:Double; let sendHz:Double
}
struct DiagnosticExport: Codable { let schema:Int; let generatedAt:Date; let rows:[DiagnosticRow] }
