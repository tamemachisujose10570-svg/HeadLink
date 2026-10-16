# 首版为什么不跟随，以及本次验证入口

检查基线：首次成功安装构建 c47dc56b46e8e3016cb124618514d697b79b19e7。用户已报告连接和图传正常；尚无本机姿态/角度命令诊断。

| 条件 | 源码位置 | 结论 |
| --- | --- | --- |
| 正式机型/固件限位配置 | App/VerifiedProfiles.json:1 为 []；首版 App/AppModel.swift:68、70–72 逐项精确匹配型号和firmware | **确定的硬阻塞**：limits一直nil；首版32行canStart=false |
| 实际启动检查 | Sources/HeadLinkCore/TrackingController.swift:108–114 | 即使绕过按钮，start仍要求limits.valid、已校准和新鲜姿态 |
| 固件读取 | Vendor/OpenCine/Sources/OpenCineDJI/CameraStatus+DJIWire.swift:123、255 | 有回包解析器，不等于已获得本机固件；首版没有人工核对入口，缺失固件不能匹配正式配置 |
| 未校准 | 首版App/AppModel.swift:32；TrackingController.swift:77 | 是独立启动条件；不知道用户当时是否完成，不能从连接正常推断 |
| 耳机真实回调 | App/HeadphoneMotion.swift:19–29；TrackingController.swift:45–73 | 真正使用CMHeadphoneMotionManager。连接正常不能证明回调、新鲜度或yaw/pitch变化，需新版观测 |
| 相机反馈 | App/PocketCamera.swift:137–153 | 仅支持已核实50字节姿态格式；视频成功不能证明此反馈可用 |
| 当前云台模式 | App/PocketCamera.swift:181–187 | 新版读取真实family/俯仰锁定参数，明确不兼容就拒绝；本机模式需新版运行记录，不能推测 |
| 角度命令 | App/PocketCamera.swift:157–174；Vendor/OpenCine/Sources/OpenCineDJI/Commands.swift:549 | 链路已存在，首版被启动门槛挡住；没有本机运动成功证据，不能宣称相机已接受 |

首版位置可在[已安装构建源码](https://github.com/wch33e/HeadLink/blob/c47dc56b46e8e3016cb124618514d697b79b19e7/App/AppModel.swift#L68)复核。

新版AppModel.swift:46明确列出逐项阻塞；Commissioning.swift:103的begin只准备，不发运动。首次实验以真实型号/人工核对固件、固定机身及模式确认启动，逐项点击运动；四向及返回/停止/物理观察全部确认后才生成本次局部配置。正式VerifiedProfiles仍为空，不会伪造兼容认证。

真实运动结果需要用户用新版界面及JSON确认。不能把合成协议测试、设备目录型号或上游软件范围当成本机机械行程和控制验收。
