# HeadLink 进度检查点

- 项目：wch33e/HeadLink（私有）。
- 本地代码：当前工程目录，project.yml 可重建。
- 已验证：15 项 macOS 核心/协议测试、XcodeGen 生成、App Swift 语法、耳机 Core Motion macOS 类型检查；未进行真机硬件验证。
- 2026-10-16：connector 实际写入工作流成功；准备首次完整源码提交。
- 构建命令：GitHub 手动 iPhone unsigned build；Xcode 26.1.1 / macos-15；内部 bash scripts/build-unsigned.sh。
- 权限：Contents/Workflows 写入已实际证实，Actions 已启用；CLI 不需新增 workflow scope。
- 费用检查：账户预算页面已显示 Actions 为 $0，并阻止超额；未改变预算或支付设置。免费余额 API 不可读，首次运行若无可用额度应停止，不启用付费。
- 当前 iOS 编译、IPA、安装和硬件状态：均未验证。后续以实际 Actions 结果更新。
- 真机目标：iPhone + AirPods Pro 3 + Pocket 4；实际型号/固件/iOS待确认。VerifiedProfiles为空，跟随未开放。
