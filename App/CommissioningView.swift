import SwiftUI
import HeadLinkCore

struct CommissioningView:View {
    @Bindable var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var observed=false
    @State private var requestedDirection:TestDirection?
    var body:some View {
        NavigationStack {
            Form {
                Section("1 · 真实耳机姿态") {
                    LabeledContent("数据状态",value:model.motionLabel)
                    LabeledContent("观察 yaw / pitch",value:angles(freshProbe))
                    LabeledContent("回调频率",value:String(format:"%.1f Hz",model.callbackHz))
                    LabeledContent("数据时效",value:model.headAge.map{String(format:"%.0f ms",$0*1000)} ?? "未收到")
                    LabeledContent("实际变化范围",value:String(format:"左右 %.1f° · 上下 %.1f°",model.probe.yawSpan,model.probe.pitchSpan))
                    Label(model.probe.movementObserved ? "已观察到两个方向真实变化" : "请分别左右转头和抬头低头，各变化至少3°",
                          systemImage:model.probe.movementObserved ? "checkmark.circle" : "arrow.left.and.right")
                    Button("重设观察零点（不转动云台）") { model.resetProbe() }
                    Button("重新检查耳机运动服务") { model.retryMotion() }.disabled(model.isFollowing || model.commissioning.running)
                    Text("这里的观察零点只用于确认传感器数据，不等于跟随校准；侧歪头不控制roll。")
                }
                Section("2 · 相机与控制模式") {
                    LabeledContent("识别型号",value:model.camera.selected?.model.name ?? "未识别")
                    LabeledContent("广播型号编号",value:model.camera.selected?.modelId.map{String(format:"0x%04X",$0)} ?? "未上报")
                    LabeledContent("相机回报固件",value:model.camera.status.firmware ?? "未收到，不填写推测值")
                    if model.camera.status.firmware == nil {
                        TextField("人工核对的完整固件版本",text:$model.manualFirmware).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("若未收到固件，请在机身设置或DJI Mimo设备信息核对后填写。此值始终标注“人工确认”，不会冒充相机回报。")
                    }
                    LabeledContent("姿态 yaw / pitch",value:angles(model.camera.freshPose?.angles))
                    LabeledContent("原生俯仰回报",value:model.camera.freshPose.map{String(format:"%.1f°",$0.nativePitch)} ?? "不可用")
                    LabeledContent("姿态时效",value:model.camera.pose.map{String(format:"%.0f ms",max(0,model.now-$0.receivedAt)*1000)} ?? "未收到")
                    LabeledContent("当前模式",value:model.camera.modeSummary)
                    LabeledContent("姿态帧长度 / 有效数",value:"\(model.camera.lastAttitudeLength.map(String.init) ?? "未收到") / \(model.camera.poseFrames)")
                    Button("读取云台参数（不发运动命令）") { model.camera.refreshControlInfo() }
                    Text("相机从屏幕顶部下滑，选择跟随模式，并关闭ActiveTrack和智能云台。未收到模式参数时需人工核对；收到不兼容模式时会阻止运动。")
                }
                Section("3 · 固定基座跟随准备") {
                    Toggle("已核对机身为识别出的Pocket 4及固件",isOn:$model.confirmedModel)
                    Toggle("机身已固定，所测方向活动范围无遮挡",isOn:$model.fixedBaseConfirmed)
                    Toggle("已选跟随模式，已关闭跟踪和智能云台",isOn:$model.followModeConfirmed)
                    if let limits=model.savedProfile {
                        Text(String(format:"已保存局部配置：yaw %.1f°…%.1f°；pitch %.1f°…%.1f°",limits.yawMin,limits.yawMax,limits.pitchMin,limits.pitchMax)).monospacedDigit()
                        Text("型号和固件已精确匹配，可复用已测范围，无需重复5°实验。需重新核对现场条件、校准并点击开始；不会连接后自动运动。")
                        if let pose=model.camera.freshPose,limits.clamp(pose.angles) != pose.angles {
                            Text("当前镜头超出已测范围，请用机身摇杆调整回上方范围内。App不会自动回中。").foregroundStyle(.orange)
                        }
                        Button("使用已测配置，返回拍摄页校准") {
                            model.useSavedProfile()
                            if model.savedProfileAccepted { dismiss() }
                        }.disabled(!model.canUseSavedProfile)
                    }
                    Button("准备本次实验（尚不运动）") { observed=false; model.beginExperiment() }
                        .disabled(!model.camera.connected || model.commissioning.running || !model.currentIdentity.valid ||
                                  !model.confirmedModel || !model.fixedBaseConfirmed || !model.followModeConfirmed || model.camera.freshPose == nil)
                    Text("不是机械全行程验证。只有你主动点击下一节的测试并确认后，才累积本次局部可用范围；退出前台、断连、改机型/固件/模式会清除实验资格。")
                }
                Section("4 · 点击才会运动") {
                    LabeledContent("实验状态",value:testState)
                    if model.commissioning.state == .failed { Text(commissioningFailure(model.commissioning.failure)).foregroundStyle(.orange) }
                    if model.commissioning.state == .ready {
                        if model.commissioning.needsReturn {
                            testButton(.origin)
                            Text("必须先沿本次已测方向返回起点并确认，才可测试另一方向。")
                        } else {
                            ForEach([TestDirection.right,.left,.up,.down],id:\.self) { testButton($0) }
                        }
                    }
                    if model.commissioning.running {
                        ProgressView()
                        LabeledContent("本次目标",value:angles(model.commissioning.target))
                    }
                    if let receipt=model.commissioning.pendingReceipt {
                        LabeledContent("目标 / 最终回报",value:"\(angles(receipt.target)) / \(angles(receipt.final))")
                        LabeledContent("停止后最大回报变化",value:String(format:"%.2f°",receipt.maximumPostStopMovement))
                        Text("已尝试发送停止，并收到一段稳定的姿态回报；这不是设备停止ACK，也不是独立物理量角证明。")
                        Toggle(receipt.direction == .origin ? "我看到镜头沿原路返回起点并停稳" : "我看到方向正确、约定角度正确且停止后保持",isOn:$observed)
                        Button("确认本项物理观察") { model.confirmTest(); observed=false }
                            .disabled(!observed || model.camera.freshPose == nil)
                        Button("未通过，停止并保存诊断",role:.destructive) { model.stopTest(); model.exportDiagnostics() }
                    }
                    Button("立即停止实验／跟随",role:.destructive) {
                        if model.commissioning.running || model.commissioning.state == .awaitingConfirmation { model.stopTest() } else { model.pause() }
                    }.frame(minHeight:44)
                    LabeledContent("已确认运动记录",value:"\(model.commissioning.receipts.count)")
                }
                Section("5 · 局部1∶1跟随") {
                    if let limits=model.commissioning.experimentalLimits {
                        Text(String(format:"本次已测包络：yaw %.1f°…%.1f°；pitch %.1f°…%.1f°",limits.yawMin,limits.yawMax,limits.pitchMin,limits.pitchMax)).monospacedDigit()
                        Text("这些是相机机身参考角，只有单轴端点和返回经本次观察。组合运动仍属实验，异常差值会暂停。增益固定1.00，超出包络明确限位。")
                    } else { Text("先完成向右、向左、向上、向下各约5°及每次返回。确认后才开放本次实验跟随。") }
                    Button("启用本次实验跟随，返回拍摄页校准") {
                        model.acceptExperimentalFollow()
                        if model.experimentAccepted { dismiss() }
                    }.disabled(!model.commissioning.readyForFollow || !model.probe.movementObserved || !model.canCalibrate)
                    Text("启用不等于开始运动。返回拍摄页后仍需校准，再明确点击开始跟随。需要扩大范围时，可回到这里逐侧新增5°测试；不自动扫行程。")
                }
                Section("命令链路与诊断") {
                    LabeledContent("提交目标数",value:"\(model.camera.targetSubmissions)")
                    LabeledContent("实际网络写入数",value:"\(model.camera.nativeWrites)")
                    LabeledContent("最近提交目标",value:angles(model.camera.lastSubmittedAngles))
                    if let reason=model.camera.lastCommandIssue { Text(LocalizedStringKey(reason)).foregroundStyle(.orange) }
                    if !model.blockers.isEmpty { ForEach(model.blockers,id:\.self) { Text(LocalizedStringKey($0)).font(.footnote) } }
                    Button("生成本次诊断（含型号、模式和实验记录）") { model.exportDiagnostics() }
                    if let url=model.exportURL { ShareLink("分享诊断JSON",item:url) }
                    Text("不包含相机密码、完整设备标识或视频。固件来源、姿态帧长度、目标/反馈、停止观察与未通过原因会保留。")
                    if let notice=model.notice { Text(LocalizedStringKey(notice)).foregroundStyle(.secondary) }
                }
            }.navigationTitle("跟随准备与实验")
                .toolbar { Button("完成") { if model.commissioning.running { model.stopTest() }; dismiss() } }
                .confirmationDialog("确认机身已固定且目标方向无遮挡",isPresented:Binding(get:{requestedDirection != nil},set:{if !$0 { requestedDirection=nil }}),titleVisibility:.visible) {
                    if let direction=requestedDirection {
                        Button(testLabel(direction)) { model.runTest(direction); requestedDirection=nil; observed=false }
                    }
                    Button("取消",role:.cancel) { requestedDirection=nil }
                } message: { Text("只执行这一次缓慢的目标角度测试，未确认结果不会开放跟随。可随时点击停止。") }
                .onDisappear { if model.commissioning.running { model.stopTest() } }
        }
    }
    private var freshProbe:Angles? { (model.headAge.map{$0 <= 0.2} ?? false) ? model.probe.look : nil }
    private func angles(_ a:Angles?) -> String { a.map{String(format:"%.1f° / %.1f°",$0.yaw,$0.pitch)} ?? "不可用" }
    private func testButton(_ direction:TestDirection) -> some View {
        Button(testLabel(direction)) { requestedDirection=direction }
            .disabled(model.commissioning.plannedTarget(direction) == nil || model.camera.freshPose == nil || model.camera.followModeBlock != nil)
            .frame(minHeight:44)
    }
    private func testLabel(_ direction:TestDirection) -> String {
        guard let target=model.commissioning.plannedTarget(direction),let anchor=model.commissioning.anchor else { return "此方向超出候选范围" }
        switch direction {
        case .right:return String(format:"向右测试到 +%.0f°（新增5°）",target.yaw-anchor.angles.yaw)
        case .left:return String(format:"向左测试到 −%.0f°（新增5°）",anchor.angles.yaw-target.yaw)
        case .up:return String(format:"向上测试到 +%.0f°（新增5°）",target.pitch-anchor.angles.pitch)
        case .down:return String(format:"向下测试到 −%.0f°（新增5°）",anchor.angles.pitch-target.pitch)
        case .origin:return "沿已测路径返回实验起点"
        }
    }
    private var testState:String {
        switch model.commissioning.state {
        case .inactive:return "尚未准备，不发运动命令"
        case .ready:return model.commissioning.needsReturn ? "等待明确点击返回起点" : "就绪，等待你点击测试"
        case .moving:return "正在缓慢发送绝对角度目标"
        case .stopping:return "已尝试发送停止，观察真实回报是否保持"
        case .awaitingConfirmation:return "回报已到位并保持，等待你的物理观察确认"
        case .failed:return "实验未通过，已停止待发目标"
        }
    }
}
