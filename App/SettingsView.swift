import SwiftUI
import HeadLinkCore
struct SettingsView:View {
    @Bindable var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("crosshair") private var crosshair=true
    @AppStorage("leftHanded") private var leftHanded=false
    @AppStorage("keepAwake") private var keepAwake=false
    @AppStorage("haptics") private var haptics=false
    @AppStorage("recordDiagnostics") private var recordDiagnostics=false
    var body:some View {
        NavigationStack {
            Form {
                Section("跟随") {
                    Picker("控制轴",selection:$model.axes) {
                        Text("左右＋上下").tag(ControlAxes.both); Text("仅左右").tag(ControlAxes.yaw); Text("仅上下").tag(ControlAxes.pitch)
                    }
                    LabeledContent("倍率",value:"1.00")
                    Picker("响应",selection:$model.response) { Text("低延迟").tag(ResponseMode.immediate); Text("轻度平滑").tag(ResponseMode.smooth) }
                    Text("平滑只改变过渡，停稳后收敛到原始目标。更改控制设置会暂停跟随。").font(.footnote)
                    Picker("安装方式",selection:$model.mountMode) {
                        ForEach(MountMode.allCases,id:\.self) { Text(LocalizedStringKey($0.title)).tag($0) }
                    }
                    Text("移动机身补偿未验证；当前没有独立机身姿态输入，移动模式不允许启动，避免身体和云台重复转动。").font(.footnote)
                    Button("清除校准") { model.clearCalibration() }
                }
                Section("显示与反馈") {
                    Toggle("十字线",isOn:$crosshair); Toggle("左手布局",isOn:$leftHanded)
                    Toggle("拍摄页保持常亮",isOn:$keepAwake); Toggle("操作震动",isOn:$haptics)
                }
                Section("本地诊断") {
                    Toggle("记录诊断",isOn:$recordDiagnostics)
                    Text("最多保留最近约10分钟的角度、状态和频率；正式跟随配置就绪后自动记录。无视频、设备标识或网络密码；退出应用后不保留记录。").font(.footnote)
                    Button("生成脱敏诊断文件") { model.exportDiagnostics() }
                    if let url=model.exportURL { ShareLink("分享 JSON",item:url) }
                    Button("清除记录",role:.destructive) {
                        model.diagnostics=[]
                        if let url=model.exportURL { try? FileManager.default.removeItem(at:url) }
                        model.exportURL=nil
                    }
                }
                Section("关于 HeadLink") {
                    LabeledContent("版本",value:(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "开发构建"))
                    Text("原生 iPhone 工具，数据在本地处理。无需账号，无广告，不上传运动数据或相机画面。")
                    Text("用户已确认原局部范围内头部联动通过。1.2.0移除实验窗口，正式连接、校准、开始；大角度响应、复合转头及连续稳定性仍需本版真机核对。").foregroundStyle(.orange)
                    NavigationLink("开源许可与署名") { ScrollView { Text(licenseText).font(.footnote).textSelection(.enabled).padding() }.navigationTitle("开源许可") }
                    Text("使用 OpenCine / OpenPocketCine 的 Apache-2.0 开源实现。与 Apple、DJI 无官方关联。")
                }
            }.navigationTitle("设置").toolbar { Button("完成") { dismiss() } }
        }
    }
    private var licenseText:String {
        ["NOTICE","LICENSE"].compactMap { name in
            Bundle.main.url(forResource:name,withExtension:"txt").flatMap{try? String(contentsOf:$0,encoding:.utf8)}
        }.joined(separator:"\n\n")
    }
}
