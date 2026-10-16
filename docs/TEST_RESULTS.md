# 验证记录

日期：2026-10-16（Asia/Shanghai）。执行环境：macOS 26.1 / Apple Silicon / Swift 6.2 / CommandLineTools。**没有安装本地 Xcode 或模拟器；首次云端 iOS device 编译现已成功。**

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
| iOS smoke / full device build | 云端通过 | run #1，Xcode 26.1.1，iPhoneOS arm64 Release |
| 云端核心/协议测试 | 15项通过 | 与本机相同测试文件 |
| device IPA 打包检查 | 云端通过 | arm64、iPhoneOS、权限说明、内嵌依赖、无Hotspot entitlement |
| 首版安装、AirPods连接、Pocket配对/连接、实时图传 | 用户报告通过 | 不能证明头部姿态回调或角度命令已经正常 |

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

首次云构建：https://github.com/wch33e/HeadLink/actions/runs/38896370871 ，源码 c47dc56b46e8e3016cb124618514d697b79b19e7。上传产物包含device-build.xcresult与原始日志。job 2026-10-16 19:50:01–19:52:09（Asia/Shanghai）。

## 1.1.0 首次跟随实验

本地 Swift Testing **25项、3组全部通过**，新增10项实验与集成测试。App语法解析通过；固定依赖236个文件哈希通过。原连接、Wi-Fi交接、图传关键函数与首版逐字一致。

新增覆盖：独立头部观察、参考跳变/纯roll、真实身份来源与新鲜度、准备时零命令、5°逐项测试、反向/串轴/超时拒绝、停止后稳定反馈、人工确认、沿已测路径返回、四向完整确认后才产生局部范围、每次显式扩展5°，以及该范围接入校准后1∶1目标、保持、回基准与暂停的集成流程。确认时还需新鲜姿态保持在本次目标附近。

本地日志：`commissioning-tests.log`。其中相机反馈由测试合成；**不构成真实Pocket 4运动、方向、停止或机械限位证据**。真实验收步骤见 `FIRST_FOLLOW_TEST.md`。跟随代码已通过云端run #3完整iOS编译和IPA打包（34dbce88f1287f507145d8a1209a42abf24e0544）；随后按用户要求加入密码复制，最终构建结果另记。

中间构建run #4（不交付）：[https://github.com/wch33e/HeadLink/actions/runs/38905644553](https://github.com/wch33e/HeadLink/actions/runs/38905644553)，源码dbcb050166ee85c89f5d100281f100be51c1629b。25项测试、完整iPhoneOS arm64 Release编译与打包全部通过，包含追加的Wi-Fi密码复制功能。密码复制代码通过App语法和云端SDK编译检查。

下载后直接检查真实IPA发现版本仍为1.0（1），已修正XcodeGen info.properties，使版本/构建号继承build settings。本地重新生成工程并校验引用通过；打包反例使用run #4真实Info.plist，在run=5时被明确拒绝，避免旧构建号再通过。最终交付需由run #5真实IPA复核。

最终云构建run #5：[https://github.com/wch33e/HeadLink/actions/runs/38906748373](https://github.com/wch33e/HeadLink/actions/runs/38906748373)，源码ed94612f7944a2a6fb10d5a78ec9f9f3123eda38。25项测试与完整设备编译、递增构建号检查、打包通过。

下载真实run #5 IPA并独立读取plist与Mach-O通过：版本1.1.0（5）、org.headlink.personal、最低iOS17.0、iPhoneOS arm64。codesign确认未签名、无profile，需Sideloadly签名。SHA256 83af04c07372541565e9b65bf1c707680722c527b6f0c9ffaa4841ba08bf684a 与云端metadata相等。记录随产物保存在inspection.json。

## 1.1.1 实机已测配置

本地28项/4组测试通过。新增：打包配置从真实端点生成、精确型号/固件/来源匹配拒绝错误身份、真实起点native pitch约180°时1∶1/保持/回基准/跨±180映射及重连必须重校准。CLI-only Testing Foundation交叉overlay缺模块接口，本地追加 `-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays`，未改变App编译或云端标准测试。App语法和236个依赖哈希通过。用户实机证据与不能证明的内容见DEVICE_EVIDENCE.md。
