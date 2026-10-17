# HeadLink 进度检查点

- 项目：wch33e/HeadLink（私有）。
- 本地代码：当前工程目录，project.yml 可重建。
- 当前：1.1.1（6）；28项本地及云端测试通过，用户诊断证实真实姿态和四向小角度运动，保存个人局部范围；1∶1仍待校准后实测。
- 2026-10-16：工作流和完整工程已提交。构建源commit：c47dc56b46e8e3016cb124618514d697b79b19e7。
- 构建命令：GitHub 手动 iPhone unsigned build；Xcode 26.1.1 / macos-15；内部 bash scripts/build-unsigned.sh。
- 权限：Contents/Workflows 写入已实际证实，Actions 已启用；CLI 不需新增 workflow scope。
- 费用检查：账户预算页面已显示 Actions 为 $0，并阻止超额；未改变预算或支付设置。免费余额 API 不可读，首次运行若无可用额度应停止，不启用付费。
- iOS云端编译和IPA打包：成功，run #1，job用时2分8秒。
- Actions：https://github.com/wch33e/HeadLink/actions/runs/38896370871
- 产物：https://github.com/wch33e/HeadLink/actions/runs/38896370871/artifacts/12044256826 （HeadLink-unsigned-1，保留3天）。
- 已通过：最小真机SDK编译、15项核心/协议测试、完整iPhoneOS arm64 Release编译、device IPA检查。
- 首版已由用户通过Sideloadly安装，AirPods/Pocket连接与实时图传报告正常；实际跟随仍待新版实验验收。
- Git智能HTTP传输在本机失败；本次通过connector写workflow、gh REST Git Data API上传源码，无需扩大CLI权限。
- 真机目标：iPhone + AirPods Pro 3 + Pocket 4；实际型号/固件/iOS待确认。正式VerifiedProfiles为空；1.1.0提供明确点击的首次实验流程，完成后启用本次局部范围。

- 已下载并复核：HeadLink-unsigned.ipa，SHA256 c9e3abf6b1dbafddb53eb5f08e964d402a56af4db50652ce436c2de04b1db442；iPhoneOS arm64，最低iOS17.0，无开发者签名和provisioning profile。

## 1.1.0 首次联动实验

- 用户已反馈：首版安装、AirPods连接、Pocket配对/连接、实时图传正常；头转不带动云台。未收到准确iOS/机型/固件。
- 确定原因：正式profile为空，且精确firmware匹配，没有首次验证入口，故canStart恒假；旧版未校准前也没有可观察的头部角度。不能据连接成功断言姿态回调或角度指令已实测。
- 已实现：未校准头部观察、具体阻塞列表、只读模式/真实姿态诊断、人工固件来源、session-only明确点击的5°实验、停止后保持和物理确认、返回确认、逐次扩展5°包络、完成后校准再1∶1跟随。
- 已保留：首版连接与预览关键函数逐字不变；bundle ID不变。没有改变上游wire或软件限位。
- 核心跟随代码已通过run #3云端iOS编译和25项测试。按用户追加要求，Wi-Fi密码增加复制按钮及选中复制；最终run #4也已成功：https://github.com/wch33e/HeadLink/actions/runs/38905644553 。安装/跟随验收由用户执行docs/FIRST_FOLLOW_TEST.md。

## 中间构建run #4（不交付）

- 源码：dbcb050166ee85c89f5d100281f100be51c1629b。
- 云构建：https://github.com/wch33e/HeadLink/actions/runs/38905644553 ，完整iPhoneOS编译、25项测试、IPA打包通过；job 3分4秒。
- 产物：https://github.com/wch33e/HeadLink/actions/runs/38905644553/artifacts/12048451898 。
- bundle ID：org.headlink.personal，与首版相同。
- Wi-Fi密码：显式点击复制按钮，也可显示后选中复制；仅写本机剪贴板，不写诊断/日志。
- 真实yaw/pitch回调、型号/固件/模式、5°动作与停止、1∶1跟随仍需用户在固定机身基线下验收。

- 下载核对发现XcodeGen默认Info.plist仍写1.0（1）；已将版本字段绑定MARKETING_VERSION/CURRENT_PROJECT_VERSION，正式版本改为1.1.0以高于首版1.0。打包新增校验构建号等于workflow run，并实际验证旧包会被拒绝。最终使用修复后的run #5。

## 1.1.0（5）最终交付

- 源码：ed94612f7944a2a6fb10d5a78ec9f9f3123eda38。
- 云构建：https://github.com/wch33e/HeadLink/actions/runs/38906748373 ，job 2分23秒，25项测试、完整iPhoneOS编译、构建号校验和IPA打包通过。
- 产物：https://github.com/wch33e/HeadLink/actions/runs/38906748373/artifacts/12048202912 。
- 当前功能含明确点击5°实验、实验后校准1∶1跟随，以及Wi-Fi密码复制；关键连接/图传路径未改。
- 新包保持org.headlink.personal，用首次相同Sideloadly签名账户/设置覆盖安装；本次未启用付费服务。

- 已下载直接复核IPA：CFBundleShortVersionString=1.1.0、CFBundleVersion=5、bundle ID=org.headlink.personal、最低iOS17.0、iPhoneOS arm64、未签名，无内嵌provisioning profile。
- SHA256：83af04c07372541565e9b65bf1c707680722c527b6f0c9ffaa4841ba08bf684a；与云端metadata一致。真实运动验收仍待用户。

## 1.1.1：根据用户实机证据保存局部配置

- 用户诊断确认真实耳机约50Hz回调、Osmo Pocket 4、人工固件01.03.14.04、iOS27.0、跟随/俯仰未锁定、4端点+4返回与停止保持均人工确认。
- 导出时唯一blocker是未校准；1591行均userPaused，1∶1尚无运行证据。
- 保存保守局部窗口：yaw -4.5…5.1，display pitch -5.4…4.6；不叫机械极限，不扩大。证据docs/DEVICE_EVIDENCE.md及摘要。
- 复用仍需精确身份来源、3项现场确认、新鲜数据、头部实际变化和当前角度在范围内，明确点击启用后再校准、开始。连接/断连/校准不会自动运动；配置跨连接保存，启用资格不保存。
- 本地28项测试通过（包括真实起点native pitch±180的映射回归），App语法及236个Vendor哈希通过。CLI Testing缺Foundation overlay的模块接口，本地测试脚本CLT分支自动追加-disable-cross-import-overlays并通过默认命令；云端full Xcode仍运行标准测试。run #6已通过28项测试及设备编译，产物下载核验中。

- 1.1.1（6）云端成功：https://github.com/wch33e/HeadLink/actions/runs/38919199454 ，源码107834d9e6d9b874bd49281fab72d630860554a6，28项测试/4组、完整iPhoneOS arm64 Release编译与打包通过，job2分21秒。
- 产物：https://github.com/wch33e/HeadLink/actions/runs/38919199454/artifacts/12053409458 。本次未启用付费服务。
- 已下载核对：版本1.1.1（6）、org.headlink.personal、iPhoneOS arm64、最低iOS17.0、未签名。包内VerifiedProfiles.json与本地已测配置逐字相等。SHA256 82477b322e879863774193f2fb9638cc27455661d819361e0babd69c1622d70a 与云端一致。

## 2026-10-17 稳定性修复1.1.2

- 保存基线标签baseline-1.1.1-build-6，旧IPA未覆盖。暂停功能扩展；详见docs/STABILITY_FIX.md。
- 修复可复现的输入时间竞态，UI/start共用拒绝检查、校准失效记录、同会话幂等、短暂inactive仅暂停而非清除有效参考。真实后台/断连/姿态过期等继续使校准失效。
- 控制40Hz保持，UI离散状态与最多10Hz遥测分离，预览层禁隐式布局动画。
- 补视频分层有界恢复、3次预算/动作间隔、最多一次共享UDP重建/10秒上限。视频停滞不等于相机断连，不自动完整配对或自动跟随。
- schema3实际构建号、实例/连接/校准ID、失效/拒绝事件、视频各层时间/缓冲/错误与恢复记录。压缩显示路径解码完成不可观测时如实nil。
- 本地45项/7组通过（含模拟5分钟健康视频、竞态复现、正常更新保校准、故障分层恢复）；不是5分钟硬件验证。Vendor236文件不变。云端编译待完成。
