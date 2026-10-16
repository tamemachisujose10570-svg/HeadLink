# HeadLink 进度检查点

- 项目：wch33e/HeadLink（私有）。
- 本地代码：当前工程目录，project.yml 可重建。
- 已验证：15 项 macOS 核心/协议测试、XcodeGen 生成、App Swift 语法、耳机 Core Motion macOS 类型检查；未进行真机硬件验证。
- 2026-10-16：工作流和完整工程已提交。构建源commit：c47dc56b46e8e3016cb124618514d697b79b19e7。
- 构建命令：GitHub 手动 iPhone unsigned build；Xcode 26.1.1 / macos-15；内部 bash scripts/build-unsigned.sh。
- 权限：Contents/Workflows 写入已实际证实，Actions 已启用；CLI 不需新增 workflow scope。
- 费用检查：账户预算页面已显示 Actions 为 $0，并阻止超额；未改变预算或支付设置。免费余额 API 不可读，首次运行若无可用额度应停止，不启用付费。
- iOS云端编译和IPA打包：成功，run #1，job用时2分8秒。
- Actions：https://github.com/wch33e/HeadLink/actions/runs/38896370871
- 产物：https://github.com/wch33e/HeadLink/actions/runs/38896370871/artifacts/12044256826 （HeadLink-unsigned-1，保留3天）。
- 已通过：最小真机SDK编译、15项核心/协议测试、完整iPhoneOS arm64 Release编译、device IPA检查。
- 安装和硬件状态：尚未安装、未验证。下一步用Sideloadly签名安装，先验证真实数据和连接。
- Git智能HTTP传输在本机失败；本次通过connector写workflow、gh REST Git Data API上传源码，无需扩大CLI权限。
- 真机目标：iPhone + AirPods Pro 3 + Pocket 4；实际型号/固件/iOS待确认。VerifiedProfiles为空，跟随未开放。

- 已下载并复核：HeadLink-unsigned.ipa，SHA256 c9e3abf6b1dbafddb53eb5f08e964d402a56af4db50652ce436c2de04b1db442；iPhoneOS arm64，最低iOS17.0，无开发者签名和provisioning profile。

## 0.2.0 进行中

- 用户已反馈：首版安装、AirPods连接、Pocket配对/连接、实时图传正常；头转不带动云台。未收到准确iOS/机型/固件。
- 确定原因：正式profile为空，且精确firmware匹配，没有首次验证入口，故canStart恒假；旧版未校准前也没有可观察的头部角度。不能据连接成功断言姿态回调或角度指令已实测。
- 已实现：未校准头部观察、具体阻塞列表、只读模式/真实姿态诊断、人工固件来源、session-only明确点击的5°实验、停止后保持和物理确认、返回确认、逐次扩展5°包络、完成后校准再1∶1跟随。
- 已保留：首版连接与预览关键函数逐字不变；bundle ID不变。没有改变上游wire或软件限位。
- 新版尚未云端编译；完成测试后提交并手动构建。安装/跟随验收要由用户执行docs/FIRST_FOLLOW_TEST.md。
