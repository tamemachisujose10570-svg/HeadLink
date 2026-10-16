import SwiftUI
import UIKit
import AVFoundation
import HeadLinkCore
import OpenCineApple

private let accent=Color(red:0.388,green:0.851,blue:0.929)
private let panel=Color(red:0.09,green:0.106,blue:0.129)
private let backdrop=Color(red:0.043,green:0.051,blue:0.063)

struct RootView: View {
    @Bindable var model: AppModel
    @State private var shooting=false
    @State private var settings=false
    @State private var resume=false
    @AppStorage("onboarded") private var onboarded=false
    @AppStorage("crosshair") private var crosshair=true
    @AppStorage("leftHanded") private var leftHanded=false
    @AppStorage("keepAwake") private var keepAwake=false
    @State private var diagnostics=false
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing:18) {
                        if !onboarded {
                            VStack(alignment:.leading,spacing:12) {
                                Text("让镜头跟随你的头部方向").font(.title2.bold())
                                Text("① 连接耳机与相机\n② 看向正前方并校准\n③ 点击开始，随时暂停")
                                Button("知道了") { onboarded=true }.buttonStyle(.bordered)
                            }.frame(maxWidth:.infinity,alignment:.leading).padding().background(panel,in:RoundedRectangle(cornerRadius:16))
                        }
                        if shooting {
                            statusBar
                            if geo.size.width > geo.size.height {
                                HStack(spacing:16) {
                                    if leftHanded { controls.frame(width:200) }
                                    preview.frame(minHeight:220)
                                    if !leftHanded { controls.frame(width:200) }
                                }
                            } else { preview.frame(minHeight:250); controls }
                            DisclosureGroup("精度与诊断",isExpanded:$diagnostics) { diagnosticsPanel }
                        } else { connection }
                        if let notice=model.notice { Label(LocalizedStringKey(notice),systemImage:"info.circle").font(.footnote).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading) }
                        Text("固定支架 · 移动基座补偿尚未支持").font(.caption).foregroundStyle(.secondary)
                    }.padding(16)
                }.background(backdrop)
            }
            .navigationTitle("HeadLink")
            .toolbar {
                ToolbarItem(placement:.topBarLeading) { if shooting { Button("设备") { shooting=false } } }
                ToolbarItem(placement:.topBarTrailing) { Button("设置",systemImage:"gearshape") { settings=true } }
                ToolbarItem(placement:.bottomBar) {
                    if model.isFollowing { Button("暂停跟随",systemImage:"pause.fill") { model.pause() }.buttonStyle(.borderedProminent).tint(accent).accessibilityIdentifier("alwaysPause") }
                }
            }
            .sheet(isPresented:$settings) { SettingsView(model:model) }
            .sheet(isPresented:$model.showingCommissioning) { CommissioningView(model:model) }
            .sheet(isPresented:$model.showingCalibration,onDismiss:{
                if model.controller.state == .calibrating { model.clearCalibration() }
            }) {
                VStack(spacing:24) {
                    Image(systemName:"viewfinder").font(.system(size:56)).foregroundStyle(accent).accessibilityHidden(true)
                    Text("看向你想设定的正前方，并让镜头对准同一方向。").font(.title2).multilineTextAlignment(.center)
                    Text(model.controller.state == .calibrating ? "正在检查稳定性，请保持头部和机身静止" : "准备好后，建立新的方向对应关系")
                    Text("此操作不会发送机械回中指令").font(.footnote).foregroundStyle(.secondary)
                    if model.controller.state == .calibrating { ProgressView() }
                    else { Button("校准") { model.calibrate() }.buttonStyle(.borderedProminent).disabled(!model.canCalibrate) }
                    Button("取消") { model.clearCalibration(); model.showingCalibration=false }
                }.padding(28).presentationDetents([.medium,.large])
            }
            .confirmationDialog("恢复跟随",isPresented:$resume,titleVisibility:.visible) {
                Button("继续原对应关系") { model.start() }
                Button("以当前姿势重新对齐") { model.pause(); model.showingCalibration=true }
                Button("取消",role:.cancel) {}
            } message: { Text("继续原关系会以受限速度过渡到当前目标；重新对齐会保留当前构图。") }
            .onChange(of:shooting) { _,value in UIApplication.shared.isIdleTimerDisabled=value && keepAwake }
            .onChange(of:keepAwake) { _,value in UIApplication.shared.isIdleTimerDisabled=value && shooting }
            .tint(accent)
        }
    }
    private var connection: some View {
        VStack(spacing:18) {
            Text("头部联动拍摄").font(.title3).foregroundStyle(.secondary)
            card("耳机运动数据",icon:"airpodspro") {
                Text(LocalizedStringKey(model.motionLabel))
                Text("观察 yaw / pitch：\(format((model.headAge.map{$0 <= 0.2} ?? false) ? model.probe.look : nil))").monospacedDigit()
                Text(String(format:"实际回调 %.1f Hz",model.callbackHz)).font(.caption)
                Button("检查真实数据与首次5°实验") { model.pause(); model.showingCommissioning=true }.buttonStyle(.bordered)
                Text("先在 iPhone 系统中连接 AirPods。只有收到新鲜姿态，才表示运动数据可用。").font(.footnote).foregroundStyle(.secondary)
                Button("检查运动数据") { model.retryMotion() }.buttonStyle(.bordered)
                if model.motion.authorization == .denied { settingsLink }
            }
            card("Pocket 相机",icon:"camera") {
                Text(LocalizedStringKey(model.camera.message))
                if let camera=model.camera.selected { Text(camera.model.name).font(.headline) }
                if let fw=model.camera.status.firmware { Text("固件：\(fw)").font(.caption) }
                ForEach(model.camera.sightings) { sighting in
                    Button(sighting.name) { model.controller.connecting(); model.camera.connect(sighting) }.buttonStyle(.bordered)
                }
                if let request=model.camera.wifiRequest {
                    Text("打开系统“设置 → Wi-Fi”，加入下方网络，然后返回此处验证连接。").font(.footnote)
                    Text(request.ssid).font(.body.monospaced()).privacySensitive()
                    // Credentials enter the clipboard only after an explicit user copy action.
                    SecureCredential(password:request.password)
                    Button("已加入 Wi-Fi，验证连接") { model.camera.confirmWiFi() }.buttonStyle(.borderedProminent)
                } else {
                    HStack {
                        Button("搜索相机") { model.camera.scan() }.buttonStyle(.bordered)
                        Button("断开") { model.camera.disconnect() }.buttonStyle(.bordered)
                    }
                }
                Text("配对时请在相机屏幕确认。关闭 DJI Mimo，避免占用连接。").font(.footnote).foregroundStyle(.secondary)
            }
            Button("进入拍摄",systemImage:"viewfinder") { shooting=true }.frame(maxWidth:.infinity,minHeight:44).buttonStyle(.borderedProminent)
            Text("首次使用请进入“首次5°实验”。真实姿态、单轴运动及返回确认通过后，可启用本次固定基座实验跟随。").font(.footnote).foregroundStyle(.orange)
        }
    }
    private var statusBar: some View {
        VStack(alignment:.leading,spacing:6) {
            HStack { Label(LocalizedStringKey(model.motionLabel),systemImage:"airpodspro"); Spacer(); Label(model.camera.connected ? "相机已连接" : "相机未连接",systemImage:"camera") }.font(.caption)
            Text(LocalizedStringKey(stateLabel(model.controller.state))).font(.headline).foregroundStyle(model.isFollowing ? accent : .primary)
        }
    }
    private var preview: some View {
        ZStack {
            Color.black
            if model.camera.connected { PreviewSurface(runtime:model.camera.decoder).aspectRatio(model.camera.decoder.pictureAspect,contentMode:.fit) }
            if !model.camera.previewLive {
                VStack(spacing:12) {
                    Image(systemName:"video.slash").font(.largeTitle)
                    Text(model.camera.lastPresentedAt == nil ? "等待真实相机预览" : "画面已暂停 · 最后一帧")
                }.padding().background(.black.opacity(0.75),in:RoundedRectangle(cornerRadius:12))
            }
            if crosshair { Image(systemName:"plus").font(.body.weight(.ultraLight)).foregroundStyle(.white.opacity(0.6)).accessibilityHidden(true) }
            VStack {
                HStack {
                    if model.camera.actualRecording == true { Label("REC \(model.camera.status.recordElapsedSec)s",systemImage:"record.circle.fill").foregroundStyle(.red).monospacedDigit() }
                    else if model.camera.recordPending != nil { Text("等待录像确认…").foregroundStyle(.orange) }
                    Spacer()
                    if model.controller.output?.limitedByRange == true { Label("目标超出可达范围",systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }.font(.caption.bold()).padding(12).background(.black.opacity(0.5))
                Spacer()
            }
        }.clipShape(RoundedRectangle(cornerRadius:14))
    }
    private var controls: some View {
        VStack(spacing:14) {
            Text(model.axes == .both ? "左右＋上下 1∶1" : model.axes == .yaw ? "仅左右 1∶1" : "仅上下 1∶1").font(.headline)
            Button("真实数据检查／首次5°实验",systemImage:"testtube.2") { model.pause(); model.showingCommissioning=true }.buttonStyle(.bordered)
            if !model.profileReady { Text("先完成本次小角度实验，再启用局部1∶1跟随").font(.footnote).foregroundStyle(.orange) }
            if model.experimentAccepted,let limits=model.controller.limits {
                Text(String(format:"实验包络 yaw %.1f…%.1f° / pitch %.1f…%.1f°",limits.yawMin,limits.yawMax,limits.pitchMin,limits.pitchMax)).font(.caption).monospacedDigit()
            }
            if model.controller.output?.transitioning == true { Text("正在过渡到目标方向").font(.caption).foregroundStyle(accent) }
            Button(model.isFollowing ? "暂停跟随" : "开始／恢复跟随",systemImage:model.isFollowing ? "pause.fill" : "play.fill") {
                if model.isFollowing { model.pause() }
                else if model.controller.state == .userPaused { resume=true }
                else { model.start() }
            }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth:.infinity,minHeight:52)
                .disabled(!model.isFollowing && !model.canStart).accessibilityIdentifier("followToggle")
            HStack {
                Button("校准",systemImage:"scope") { model.pause(); model.showingCalibration=true }.disabled(!model.canCalibrate)
                Spacer()
                Button(model.camera.actualRecording == true ? "停止录像" : "录像",systemImage:"record.circle") { model.camera.toggleRecording() }
                    .tint(.red).disabled(model.camera.actualRecording == nil || model.camera.recordPending != nil)
            }.buttonStyle(.bordered).frame(minHeight:44)
            if let error=model.camera.recordError { Text(LocalizedStringKey(error)).font(.footnote).foregroundStyle(.orange) }
        }
    }
    private var diagnosticsPanel: some View {
        VStack(spacing:10) {
            metric("观察头部方向（未校准也可看）",format((model.headAge.map{$0 <= 0.2} ?? false) ? model.probe.look : nil))
            metric("校准后头部方向",format(model.controller.head))
            metric("未裁剪目标",format(model.controller.rawTarget))
            metric("命令目标（已提交）",format(model.controller.output?.command))
            metric("镜头反馈（机身参考）",format(model.camera.freshPose?.angles))
            metric("角度误差","不可用：参考与时间对齐待验证")
            metric("运动数据时效",model.headAge.map{String(format:"%.0f ms",$0*1000)} ?? "不可用")
            metric("实际回调频率",String(format:"%.1f Hz",model.callbackHz))
            metric("实际网络写入频率",String(format:"%.1f Hz",model.sendHz))
            metric("完整端到端延迟","不可用：需要外部同步测量")
            if !model.blockers.isEmpty { ForEach(model.blockers,id:\.self) { Text(LocalizedStringKey($0)).foregroundStyle(.orange) } }
            Text("命令提交或网络写入不等于镜头已到位。暂停命令尚无停止确认。").font(.caption).foregroundStyle(.secondary)
        }.padding(.top,12).font(.footnote).monospacedDigit()
    }
    private func card<Content:View>(_ title:String,icon:String,@ViewBuilder content:()->Content) -> some View {
        VStack(alignment:.leading,spacing:12) { Label(LocalizedStringKey(title),systemImage:icon).font(.headline); content() }
            .frame(maxWidth:.infinity,alignment:.leading).padding(18).background(panel,in:RoundedRectangle(cornerRadius:16))
    }
    private func metric(_ name:String,_ value:String) -> some View {
        HStack(alignment:.top) { Text(LocalizedStringKey(name)).foregroundStyle(.secondary); Spacer(); Text(LocalizedStringKey(value)).multilineTextAlignment(.trailing) }
    }
    private func format(_ a:Angles?) -> String { a.map{String(format:"%.1f° / %.1f°",$0.yaw,$0.pitch)} ?? "不可用" }
    private var settingsLink: some View { Button("打开应用设置") { if let url=URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
}
private struct SecureCredential: View {
    let password:String
    @State private var reveal=false
    @State private var copied=false
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Button(reveal ? "隐藏 Wi-Fi 密码" : "显示 Wi-Fi 密码") { reveal.toggle() }
                Spacer()
                Button {
                    UIPasteboard.general.setItems([["public.utf8-plain-text":password]],options:[.localOnly:true])
                    copied=true
                } label: {
                    Label(copied ? "密码已复制" : "复制密码",systemImage:copied ? "checkmark" : "doc.on.doc")
                }.buttonStyle(.bordered).disabled(password.isEmpty)
            }
            if reveal { Text(password).font(.body.monospaced()).textSelection(.enabled).privacySensitive() }
        }.onChange(of:password) { _,_ in copied=false; reveal=false }
    }
}
struct PreviewSurface: UIViewRepresentable {
    let runtime:MonitorLiveVideoRuntime
    func makeUIView(context:Context) -> VideoContainer { let v=VideoContainer(); v.display=runtime.displayLayer; v.layer.addSublayer(runtime.displayLayer); return v }
    func updateUIView(_ view:VideoContainer,context:Context) {
        if view.display !== runtime.displayLayer { view.display?.removeFromSuperlayer(); view.display=runtime.displayLayer; view.layer.addSublayer(runtime.displayLayer) }
        view.setNeedsLayout(); runtime.noteDisplayReady()
    }
}
final class VideoContainer: UIView {
    var display:AVSampleBufferDisplayLayer?
    override func layoutSubviews() { super.layoutSubviews(); display?.frame=bounds; display?.videoGravity = .resizeAspect }
}
func stateLabel(_ state:TrackingState) -> String {
    switch state {
    case .disconnected:return "未连接"
    case .connecting:return "连接中"
    case .waitingMotion:return "已连接，等待运动数据"
    case .ready:return "就绪，尚未校准"
    case .calibrating:return "校准中"
    case .calibrated:return "已校准，等待开始"
    case .following:return "跟随中"
    case .userPaused:return "用户暂停"
    case .stalePaused:return "数据失效，已暂停"
    case .deviceDisconnected:return "设备断连"
    case .fault:return "姿态异常，请重新校准"
    }
}
