# 上游和环境核实

核实日期：2026-10-16。调查与实现分别保存，以下“上游事实”不等于 HeadLink 的硬件测试结果。

## 环境

- 空工作目录，祖先目录未发现适用 AGENTS.md，没有用户待保留的已有 Git 修改。
- macOS 26.1，Apple Silicon，Swift 6.2；仅 CommandLineTools。`xcodebuild -version` 报需要完整 Xcode。
- 没有安装 Xcode、iOS SDK 或模拟器。Swift Testing 框架已存在于 CommandLineTools，通过显式 framework 搜索路径使用。
- GitHub connector 能读已登录账户和公开源码；仓库列表为空，用户尚未提供项目仓库。允许网络访问后 CLI 登录有效，具有 repo/read:org/gist，尚无 workflow scope。
- 网络沙箱内 git DNS 不可用；经授权的公开 codeload 下载成功。源码没有上传到外部账户。

## 路线选择

修改完整 OpenPocketCine 可以沿用全套已集成的 UI，但会带入监视器功能、多机位、Watch、Sentry、Frame.io、自动 Wi-Fi capability 和庞大的 host 模型。

选择独立 SwiftUI 壳，复用 OpenCine 原生 DJI / 视频模块。上游已完成模块分离，维护代价较低；保留真实 transport / parser，而 HeadLink 负责校准、1∶1 映射与产品状态。七个模块约数 MB，以固定源码子集随工程保存，云端无需解析漂移的远程包。

## 精确版本与许可证

- OpenPocketCine：[`5e57d277cb301a846de9f0a2c0e97b217f6acffc`](https://github.com/erik-sutton95/OpenPocketCine/tree/5e57d277cb301a846de9f0a2c0e97b217f6acffc)，Apache-2.0，仅作为调用与集成参考。
- 其 `opencine-pins.txt` 指向 OpenCine：[`acc38b57d43d4308c79ad5ce951bcb6f44d14d68`](https://github.com/erik-sutton95/OpenCine/tree/acc38b57d43d4308c79ad5ce951bcb6f44d14d68)，Apache-2.0。
- 地址来自 `scripts/checkout-opencine.sh`，不是猜测。读取了两个仓库的 Package.swift 和许可/NOTICE；OpenCine 原始 Swift package 无外部包依赖。
- 分发 Core、Media、Motion、CameraVocabulary、DJI、DJIApple、Apple 七个 target。原始 NOTICE 保留；未分发 UI、字体、图标库、KCP、Nikon、Insta360 模块。
- 本地修改：裁剪 package manifest；DJIApple 的动态 OSLog 字段设 private；增加累计网络写入计数供诊断。未更改 wire 协议。

## 具体代码证据

所有路径以下面的固定 OpenCine revision 为准：

| 能力 | 源码路径 | 结论与边界 |
| --- | --- | --- |
| 耳机姿态 | `Sources/OpenCineAppKitApple/HeadphoneMotionBridge.swift`和 `Sources/OpenCineMotion/HeadTrack.swift` | 使用 CMHeadphoneMotionManager；+X 右、+Y 鼻尖、+Z 上；校准逆四元数乘当前四元数。HeadLink 自行加入归一化、稳定采样与跳变处理 |
| BLE | `Sources/OpenCineDJIApple/DjiAppleBluetoothLink.swift`、`OpenCineDJI/CameraModel+DJIWire.swift` | CoreBluetooth 扫描、真实 GATT 通知；直接使用上游常量，不另写 UUID |
| 配对 | `OpenCineDJIApple/DjiAppleConnectionRun.swift` | session wake、配对 PIN、相机确认、Wi-Fi 凭据、握手/注册；HeadLink 仅替换系统 Wi-Fi join 回调 |
| 型号与端口 | `OpenCineDJI/CameraModel+DJIProfile.swift`、`CameraModel+DJIWire.swift`、`CameraSoftAP.swift` | 从真实广播分类选择上游端口/配对参数；不把 Pocket 3 参数冒充 Pocket 4 |
| 直接目标角度 | `OpenCineDJI/Commands.swift` 的 `gimbalTimedTarget` | `0x04/0x14`，角度 i16 little-endian、0.1°，绝对模式 `0x05`，roll ignored，时间 0.1 秒单位 |
| 停止 | 同文件 `gimbalTimedStop` | 相对模式零 yaw/pitch，100 ms 替换当前 timed move；notify 无停止回包保证 |
| 反馈 | `OpenCineDJI/CameraControl+DJIWire.swift` | 只解析长度 50 的 `0x04/0x05` 姿态；yaw @4，native pitch @0，显示 tilt 为 @20 负值，单位 0.1° |
| native pitch 转换 | `OpenCineMotion/HeadTrackNative.swift` | `nativeOrigin - (displayTarget - displayOrigin)`；不能直接把显示俯仰塞进命令 |
| 队列与限流 | `OpenCineDJI/GimbalNativeTargetStream.swift`、`OpenCineDJIApple/DjiAppleDatalink.swift` | 容量一个、token fence、200 ms 过期、停止同步清空；streamInterval=0.04s，即最多约 25 Hz，实际发送另测 |
| 视频 | `OpenCineDJIApple/SoftAPVideoAssembler.swift`、`DjiAppleDatalink.swift`、`OpenCineApple/MonitorLiveVideoRuntime.swift` | 上游 UDP/DUML 视频组帧，HEVC/AVC 解码与有界呈现；initial enable-once；失效画面标记最后一帧 |
| 录像 | `OpenCineDJI/Commands.swift`、`CameraStatus+DJIWire.swift` | recordStart/Stop；`0x02/0x80` recording bit 与 elapsed seconds。HeadLink 等状态推送，不采用按钮乐观翻转 |

参考 URL：[固定源树](https://github.com/erik-sutton95/OpenCine/tree/acc38b57d43d4308c79ad5ce951bcb6f44d14d68/Sources)、[iOS 集成参考](https://github.com/erik-sutton95/OpenPocketCine/tree/5e57d277cb301a846de9f0a2c0e97b217f6acffc/ios/OpenPocketCine)。上游 README 的兼容勾选项不列入本项目验证记录。

## 权限与签名

Apple 要求运动访问声明 [NSMotionUsageDescription](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager?language=objc)，蓝牙声明 [NSBluetoothAlwaysUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription)，本地连接声明 [NSLocalNetworkUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription)。应用不使用 Bonjour，不声明 Bonjour service。

不启用 Hotspot Configuration / Access Wi-Fi Information / App Group 等 entitlement。Wi-Fi 凭据仅保留在内存中，用户在系统设置加入；本地路径存在后仍必须完成 datalink 握手，才显示相机已连接。移除 entitlement 的免费签名可运行性仍需实际安装测试。

## 构建版本

[GitHub macos-15 runner 软件清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md) 当前列有 Xcode 26.1.1 与 iOS 26.1 SDK。工程显式选择该路径，不依赖默认 Xcode 16.4。runner 镜像本身是滚动更新的，版本移除时构建会失败，不静默降级。最低 iOS 17.0 来源于固定依赖 manifest；用户实际系统尚未提供。

工程生成器 [XcodeGen 2.44.1](https://github.com/yonaskolb/XcodeGen/releases/tag/2.44.1) 固定下载并校验 SHA-256。本机实际成功生成工程，但没有 iPhone SDK，最小真机构建只能在云端执行。
