# 验证记录

日期：2026-10-16（Asia/Shanghai）。执行环境：macOS 26.1 / Apple Silicon / Swift 6.2 / CommandLineTools。**没有本地 Xcode、iOS SDK 或模拟器测试。**

| 检查 | 结果 | 能证明什么 |
| --- | --- | --- |
| Swift package core + 实际 vendored DJI 编译 | 通过 | 可移植代码在当前 macOS 工具链编译 |
| Swift Testing 15 项 | 全部通过 | 数学、状态机、队列及协议 fixture 行为 |
| XcodeGen 2.44.1 generate | 通过 | project.yml 可生成 Xcode 工程 |
| App Swift `-frontend -parse` | 通过 | 语法解析；不是 iOS SDK 类型检查/链接 |
| 耳机适配器 Core Motion API 类型检查 | macOS SDK 通过 | 真实 Core Motion API 调用可类型检查；不替代 iOS 构建 |
| 打包脚本模拟器反例 | 拒绝通过 | 带 iPhoneSimulator 标识的假 .app 不会封成 IPA |
| Info.plist `plutil -lint` | 通过 | plist 格式正确 |
| shell `bash -n` / Python 编译 | 通过 | 脚本语法；不是已实际打出 IPA |
| Vendor manifest SHA-256 | 通过 | 当前固定依赖及已记录修改与文件哈希一致 |
| iOS smoke / full device build | 未运行 | 缺少已指定云端仓库及本次构建权限/费用确认 |
| App 安装、UI、AirPods、Pocket | 未运行 | 无本项目硬件证据 |

## 测试内容

- 恒等、单轴 ±30° / ±45°、非零校准原点、复合旋转与回到原基准。
- 归一化、四元数符号等价、±180 连续展开、近竖直拒绝。
- 稳定采样、不稳定时不锁定随机样本。
- 显式启动、用户暂停、重连不自动运动；运动权限/数据失效使校准失效。
- 新鲜头部但相机反馈陈旧时暂停；时间戳重置暂停。
- 暂停中持续转头经过 180° 仍保持连续 yaw。
- 无已验证范围时不允许开始；原始目标与裁剪目标独立；平滑最终无静态偏差。
- 上游最新目标替换旧目标，旧 token 被拒绝，停止清空 pending，过期命令不发送。
- 实际上游绝对角度/停止帧编码；截断/分片、错误 CRC、未知 opcode、有界 notification 缓冲。
- 录像命令和 ACK 不生成假 recordingReported；未知姿态长度不能产生角度反馈。

fixture 为本项目合成的合法脱敏数据，没有私人设备信息。测试命令与结果见 `core-tests.log`。SwiftPM 在沙箱内提示用户缓存不可写，已使用工作目录缓存；Testing framework 最低 macOS 版本警告不影响本机 26.1 的实际测试结果，不代表支持旧 macOS。

## 可重复执行

在工程根目录执行 `bash scripts/test-core.sh`。受限工具环境可追加 `--disable-sandbox`。云端 full Xcode 使用同一测试文件，不需要本机安装 Xcode。

不要将“15 项通过”解读为物理精度证明，或把测试耗时解读为控制延迟。
