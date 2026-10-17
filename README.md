# HeadLink · 头部联动拍摄

原生 Swift / SwiftUI iPhone 工程。目标组合是 iPhone + AirPods Pro 3 + DJI Pocket 4，先以固定支架、相机机身不动为基线。当前为 **1.1.2 开发构建，云端真机编译和未签名 IPA 打包已通过，首版连接/图传用户已报告正常，真实跟随待实验**。

## 当前状态（2026-10-16）

| 层次 | 结果 |
| --- | --- |
| 代码已写 | 耳机运动读取、配对与手动 Wi-Fi 适配、真实遥测解析、绝对角度命令、预览接入、录像请求/确认、中文界面、诊断导出 |
| 核心编译和测试 | macOS / Swift 6.2，稳定性修复45项本地通过，云端编译结果见最新记录，新增实验和贯通跟随测试，见测试记录；工程生成、Swift 语法检查、plist 校验通过 |
| iOS App 编译 | **云端成功**：Actions run #6，Xcode 26.1.1，iPhoneOS arm64 Release |
| IPA / 安装 | **已生成未签名 device IPA**，供 Sideloadly 本地重签；首版已安装，新版待覆盖更新 |
| 硬件运行 | 用户已反馈首版安装、耳机连接、Pocket配对/连接和图传正常；诊断确认iOS27.0、人工固件01.03.14.04、真实头部回调和四向小角度控制；校准后1∶1仍待用户实测 |

`App/VerifiedProfiles.json` 现保存用户实机确认的Pocket 4 / 01.03.14.04局部窗口（yaw -4.5…5.1°，pitch -5.4…4.6°），不是机械全行程认证。证据与复用步骤见 [DEVICE_EVIDENCE.md](docs/DEVICE_EVIDENCE.md)。1.1.1可在现场核对后主动使用，随后校准并开始，无需重复首次实验。1.1.0 新增独立的“首次5°实验”：实时显示未校准头部角度、真实机型/固件/姿态/模式与具体启动阻塞；用户主动测试单轴端点、停止保持和返回，并确认物理观察后，可启用仅本次连接的局部实验包络。完整流程见 [FIRST_FOLLOW_TEST.md](docs/FIRST_FOLLOW_TEST.md)。不会删除正式验证条件，也不把实验包络冒充机械全行程。

## 已实现的控制行为

- 通过四元数相对旋转得到校准后的视线 yaw / pitch，增益固定 1.00；roll 不跟随。
- 0.7 秒稳定采样校准；连续 yaw 展开，q 与 -q 等价；接近竖直、姿态参考跳变、数据过期时停止并要求重校准。
- 原始目标、限位目标、命令目标分别保存；低延迟/轻度平滑不改变静态增益。
- 起步和恢复采用速率/加速度限制；暂停后可继续原关系或保留构图重新对齐。
- 上游原生 UDP 队列保留一个最新角度目标，停止操作清空待发目标并发送上游停止命令。没有停止确认时不会显示“已确认停稳”。
- 录像状态来自实际状态推送，命令或 ACK 不被当成 REC。
- 不请求手机相机、麦克风、定位、照片库权限；无后台音频、自动 Wi-Fi entitlement、App Extension、账户和上传后端。

## 开始使用代码

1. 阅读 [上游调查](docs/UPSTREAM_FINDINGS.md)、[云端仓库设置](GITHUB_SETUP.md)。
2. 本机可运行 `bash scripts/test-core.sh`，只需要现有 Swift 命令行工具。受限执行环境必要时附加 `--disable-sandbox`，不需要安装 Xcode。
3. 将工程放进自己的私有 GitHub 仓库；先确认 Actions 额度及禁止超额付费的设置。
4. 手动运行 `iPhone unsigned build`。它先生成工程、验证最小真机 SDK 链路、运行核心测试，再编译 iOS 真机目标并封装 IPA。
5. 仅在工作流成功且产物检查通过后，按 [免费安装说明](INSTALL_FREE.md) 使用 Sideloadly 本地签名安装。
6. 按 [真机测试清单](HARDWARE_TESTS.md) 逐步验证；不能把本页“代码已写”改成“硬件正常”。

原生工程配置是 `project.yml`；XcodeGen 2.44.1 会生成 `HeadLink.xcodeproj`。iOS 最低版本暂定 17.0，源于上游要求；必须再用用户的实际 iOS 验证。云端选择 `macos-15` + `/Applications/Xcode_26.1.1.app`，不跟随 runner 默认 Xcode。

## 目录

- `Sources/HeadLinkCore`：不依赖 iOS 的坐标、稳定校准、状态机、限位和平滑。
- `App`：真实设备适配器、SwiftUI、生命周期、资源与许可。
- `Vendor/OpenCine`：固定版本的七个所需模块；Apache-2.0。没有 Sentry、Frame.io、Watch、共享 UI 字体或第三方 SDK。
- `Tests`：数学、状态机及真实上游协议编码/解析测试；fixture 是脱敏的合成帧。
- `scripts` / `.github/workflows`：核心测试、固定工程生成器、真机打包和供应链校验。
- [架构](ARCHITECTURE.md) · [兼容性](COMPATIBILITY.md) · [故障排除](TROUBLESHOOTING.md) · [测试记录](docs/TEST_RESULTS.md) · [尚未完成项](docs/REMAINING_WORK.md)

## 费用与维护

本地算法、界面和协议无收费服务。私有仓库的 GitHub macOS 构建和产物存储会使用账户额度，超额可能收费；首次云构建已在账户 Actions $0 付费预算限制下完成，没有调整计费设置或购买服务。免费签名通常需每 7 天刷新，Sideloadly 刷新需要符合工具要求的电脑和设备连接。参见安装文档，不承诺永久免费或永久免维护。

## 许可

HeadLink 新增代码采用 Apache-2.0，见 `LICENSE`。固定依赖版本、文件哈希和本地修改见 `Vendor/manifest.json`、`Vendor/OpenCine/HEADLINK_MODIFICATIONS.md`。本项目与 Apple / DJI 无官方关联；不修改相机固件，不使用官方 DJI SDK。

## 首次云端构建

- 代码提交：`c47dc56b46e8e3016cb124618514d697b79b19e7`。
- [Actions run #1](https://github.com/wch33e/HeadLink/actions/runs/38896370871)：success，job 用时 2分8秒。
- [未签名 IPA 产物](https://github.com/wch33e/HeadLink/actions/runs/38896370871/artifacts/12044256826)：`HeadLink-unsigned-1`，保留3天，下载需仓库权限。
- 已通过最小真机SDK编译、15项核心/协议测试、完整App真机编译和打包检查；未进行安装或硬件验收。

## 1.1.0 首次联动

新增独立头部观察、固件来源区分、模式只读查询、小角度实验和当前启动阻塞列表。保持bundle ID `org.headlink.personal`，配对、Wi-Fi交接、预览绑定与首版逐字相同。新版构建结果以PROGRESS.md为准，首版IPA仍可用于回退。

## 稳定性修复

1.1.2优先修复校准—开始循环、按钮高频刷新和视频停滞恢复。控制/视频分别记录，必要检查保留，无新增拍摄功能。依据见 [STABILITY_FIX.md](docs/STABILITY_FIX.md)，至少5分钟真机流程见 [STABILITY_TEST_PLAN.md](docs/STABILITY_TEST_PLAN.md)。硬件结果待用户提供。
