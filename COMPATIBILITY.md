# 兼容性

## HeadLink 已验证真机组合

**无。** 不能把上游 README 的支持声明或本机核心测试列入这里。

| 项目 | 目标/现状 | 验证状态 |
| --- | --- | --- |
| 手机 | 用户自己的 iPhone，型号待确认 | 未安装 |
| iOS | 用户版本待确认，工程最低 17.0 | 未真机编译/安装验证 |
| 耳机 | AirPods Pro 3，运行时检查运动能力和真实回调 | 未验证 |
| 相机 | DJI Pocket 4，实物型号及固件待确认 | 未连接验证 |
| 固定支架 | 机身不动的第一阶段基线 | 未验证 |
| 移动基座 | 手持/胸前/肩带 | 当前不支持 |
| 自动加入相机 Wi-Fi | 无 Hotspot entitlement | 当前不提供；手动加入路径待真机验证 |
| Sideloadly 免费签名 | 已生成未签名 device IPA 供本地重签 | 未安装验证 |

## 工具链

- 本机 macOS 26.1 / arm64，Swift 6.2，CommandLineTools：15 个核心/协议测试通过。
- XcodeGen 2.44.1：本机成功生成工程。
- 云端 macos-15 / Xcode 26.1.1 / iOS 26.1 SDK：Actions run #1 已通过最小与完整 iPhoneOS arm64 Release 编译及IPA打包。
- OpenCine 固定 `acc38b57d43d4308c79ad5ce951bcb6f44d14d68`。上游声明支持 Pocket 4/4 Pro/3；HeadLink 没有继承其验证结论。

## 限位的三个层次

1. **上游命令编码范围**：其 `GimbalReach` 声明 pan -48…225°，display tilt -44…70°；原生 pitch 编码 -180…180°。这是上游软件与其观察，不能当成你的 Pocket 4 机械规格。
2. **具体相机机械范围**：尚未测量，不填写数字。
3. **HeadLink 当前验证范围**：空；`VerifiedProfiles.json` 无条目，所以跟随禁用。

新增 profile 前必须记录真实型号、固件、固定基座、控制模式、方向符号、原生/显示俯仰关系、小角度可达范围与证据；限制在已核实命令范围内。不要为了让按钮变亮填写未经测试的范围，也不要把固件字符串设通配符。profile 需随新构建交付。

固件或 iOS 更新后重新执行关键用例；不自动迁移未经验证的 profile。
