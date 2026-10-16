# HeadLink 进度检查点

- 项目：wch33e/HeadLink（私有）。
- 本地代码：当前工程目录，project.yml 可重建。
- 已验证：25 项核心/协议/实验测试，iOS device云编译；用户报告首版安装、连接及图传正常，真实跟随尚待实验。
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
- 真机目标：iPhone + AirPods Pro 3 + Pocket 4；实际型号/固件/iOS待确认。正式VerifiedProfiles为空；0.2.0提供明确点击的首次实验流程，完成后启用本次局部范围。

- 已下载并复核：HeadLink-unsigned.ipa，SHA256 c9e3abf6b1dbafddb53eb5f08e964d402a56af4db50652ce436c2de04b1db442；iPhoneOS arm64，最低iOS17.0，无开发者签名和provisioning profile。

## 0.2.0 首次联动实验

- 用户已反馈：首版安装、AirPods连接、Pocket配对/连接、实时图传正常；头转不带动云台。未收到准确iOS/机型/固件。
- 确定原因：正式profile为空，且精确firmware匹配，没有首次验证入口，故canStart恒假；旧版未校准前也没有可观察的头部角度。不能据连接成功断言姿态回调或角度指令已实测。
- 已实现：未校准头部观察、具体阻塞列表、只读模式/真实姿态诊断、人工固件来源、session-only明确点击的5°实验、停止后保持和物理确认、返回确认、逐次扩展5°包络、完成后校准再1∶1跟随。
- 已保留：首版连接与预览关键函数逐字不变；bundle ID不变。没有改变上游wire或软件限位。
- 核心跟随代码已通过run #3云端iOS编译和25项测试。按用户追加要求，Wi-Fi密码增加复制按钮及选中复制；最终run #4也已成功：https://github.com/wch33e/HeadLink/actions/runs/38905644553 。安装/跟随验收由用户执行docs/FIRST_FOLLOW_TEST.md。

## 0.2.0（4）最终交付

- 源码：dbcb050166ee85c89f5d100281f100be51c1629b。
- 云构建：https://github.com/wch33e/HeadLink/actions/runs/38905644553 ，完整iPhoneOS编译、25项测试、IPA打包通过；job 3分4秒。
- 产物：https://github.com/wch33e/HeadLink/actions/runs/38905644553/artifacts/12048451898 。
- bundle ID：org.headlink.personal，与首版相同。
- Wi-Fi密码：显式点击复制按钮，也可显示后选中复制；仅写本机剪贴板，不写诊断/日志。
- 真实yaw/pitch回调、型号/固件/模式、5°动作与停止、1∶1跟随仍需用户在固定机身基线下验收。
