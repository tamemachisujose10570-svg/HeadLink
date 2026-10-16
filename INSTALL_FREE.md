# 不安装 Xcode 的安装、更新和刷新

**首次云端 IPA 已生成。** [下载 run #1 产物](https://github.com/wch33e/HeadLink/actions/runs/38896370871/artifacts/12044256826)，解压得到 `HeadLink-unsigned.ipa`。这是 iPhoneOS arm64 Release 包，需要 Sideloadly 本地签名；用户已报告首版安装、连接和图传正常，真实跟随尚待实验。未签名 IPA 不能直接点开安装。

**当前新版1.1.0（5）：** [下载run #5产物](https://github.com/wch33e/HeadLink/actions/runs/38906748373/artifacts/12048202912)。保留 org.headlink.personal 和首次相同签名设置覆盖更新；包含首次5°实验、局部1∶1跟随与Wi-Fi密码复制。测试步骤见 [FIRST_FOLLOW_TEST.md](docs/FIRST_FOLLOW_TEST.md)。

## 1. 云端获得正确产物

先按 [GITHUB_SETUP.md](GITHUB_SETUP.md) 设置私有仓库、权限和费用限制。手动运行 Actions，成功后打开该次运行的 Artifacts，下载 `HeadLink-unsigned-构建编号`，在 Mac 解压。

你应看到 `HeadLink-unsigned.ipa`、`build-metadata.json`、`SHA256SUMS` 与日志。打开 metadata，确认 `signature` 是 `UNSIGNED; local signing required`，架构为 arm64、`minimumOS` 不高于你的 iOS。失败运行可能只上传日志，不会产生可用 IPA。

在该目录运行 `shasum -a 256 -c SHA256SUMS` 检查文件完整性。工作流已检查 device platform、Info.plist、内嵌 framework 和非模拟器 Mach-O；但这不替代签名安装测试。

## 2. 安装 Sideloadly

只从 [Sideloadly 官方网站](https://sideloadly.io/) 获取适合 Mac 的版本。不要安装来源不明的企业证书。第一次优先 USB，减少无线发现/刷新问题。

将 iPhone 连接 Mac，解锁，并在系统提示时选择信任此电脑。工具需要的设备组件或邮件插件等行为随版本变化，以官方当前安装提示为准，不额外安装完整 Xcode。

## 3. 本地签名

在 Sideloadly 主窗口选择连接的 iPhone，把 `HeadLink-unsigned.ipa` 拖到 IPA 区域，使用自己的 Apple Account 在工具里完成登录，再选择 Start 进行签名安装。Apple 密码和验证码只交给本地工具/官方登录流程，不发给开发助手。

保持 App bundle ID `org.headlink.personal` 和同一个签名账户，避免更新时变成另一个 App。暂不改高级 entitlement、注入 dylib 或启用额外插件。若工具自动调整 bundle ID，以首次成功安装后的值作为后续更新基线。

iPhone 提示开发者不受信任时，按系统“设置 → 通用 → VPN 与设备管理”中的对应开发者记录处理；开启开发者模式若系统要求，见 [Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。通常在“隐私与安全性 → 开发者模式”中开启并按提示重启。不要为了找不到开关而抹除手机。

## 4. 首次使用

1. 先在 iPhone 系统连接 AirPods，戴好后进入 HeadLink，允许运动权限，检查是否有持续新鲜数据。
2. 搜索你自己的 Pocket，选择实际相机，按相机屏幕确认配对；不要仅凭目标名称认定型号。
3. App 读取相机网络信息后，去系统设置手动加入显示的相机 Wi-Fi，返回点击“已加入 Wi-Fi，验证连接”。密码只在需要时显示；截图前隐藏。
4. 允许本地网络权限，等真正的相机握手成功。仅加入 Wi-Fi 不等于相机通信成功。
5. 进入拍摄查看真实预览/反馈。1.1.0请进入“真实数据检查／首次5°实验”，按 docs/FIRST_FOLLOW_TEST.md 检查头部回调、真实型号/固件/模式，再由本人点击各5°运动和返回测试。
6. 校准不会机械回中，也不会自动开始运动。只有有效正式配置或本次四向及返回确认生成的局部实验范围、校准及新鲜数据全部满足后，明确点击开始才发送角度命令。

## 5. 免费签名维护

[Apple 的 Personal Team 说明](https://developer.apple.com/help/account/basics/about-your-developer-account) 列明 provisioning profile 7 天到期，免费 App/设备还有数量限制。Sideloadly 官方也说明免费账户需要周期刷新。请在到期前用同一个 Mac、账户和 App 身份刷新。USB 最直接；无线/自动刷新需要工具后台运行、合适的网络和设备可达，不能当成无需电脑的永久授权。

刷新是重新签名/安装，不必每周重新编译源码。源码更新才需要新的云端 IPA。同一 App 更新优先覆盖安装，不要先卸载，以免丢失设置。签名失效时重新签名安装；先核对账户、bundle ID 和额度。

## 6. 常见问题

- **没有 IPA**：工作流尚未成功或仅有日志；不要把源码 ZIP 当 IPA。
- **系统不兼容**：当前最低 iOS 17.0，真实设备版本待确认；不能靠改 Info.plist 绕过 SDK/API 要求。
- **免费 App/身份额度已满**：检查自己已签名的 App 和 Apple 的当前限制，不删除未知应用。
- **内嵌框架签名失败**：保留完整构建/签名错误，确认使用 device IPA 和 Sideloadly 当前版本；不能通过删除所需框架修复。
- **权限没有弹出**：在设置查看 HeadLink 的运动、蓝牙、本地网络权限；必要时从应用设置页打开系统入口。这个 App 不应该要求手机相机、麦克风、定位或照片库。
- **加入 Wi-Fi 后失败**：回到 App 手动验证，关闭 Mimo，确认相机没有被其他控制端占用；不要公开网络密码。
- **刷新覆盖后设置没保留**：确认签名账户和 bundle ID 与首次安装一致。

[AltStore Classic](https://faq.altstore.io/altstore-classic/your-altstore) 是备选，仍需要对应的电脑服务和周期刷新；本项目尚未用它安装测试。

## 可选付费路线

Apple Developer Program 的 [官方注册说明](https://developer.apple.com/programs/enroll/) 通常列年费 USD 99 或地区等值价格，实际结算以当地官方页面为准。本项目未购买。设备签名需匹配有效证书/profile，不能把会员年限当作任意安装包永不过期；应记录具体签名材料的到期日期。

[TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) 构建通常可测试 90 天，外部测试可能需要 Beta App Review。它需要开发者计划及 App Store Connect 配置，云端构建仍可能消耗 GitHub 额度。免费路线没有走通前不自动升级或购买。
