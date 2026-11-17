# HarmonyOS 公开 API 限制与能力边界

更新日期：2026-11-17

本文面向本项目的 HarmonyOS Phone 普通应用实现，记录已核对的华为公开 API 边界。这里的“不可完成”仅用于文档明确不支持或缺少普通应用可用控制接口的情形；受限权限审批、用户授权、目标应用行为及设备实测不通过，分别标记为条件限制，不混为一谈。

## 已确认的硬边界

| 能力 | 结论 | 依据与对项目的影响 |
|---|---|---|
| 转发其他应用音频，同时只静音手机本机 | 目前不能仅靠本应用的公开 Audio Kit API 保证实现。系统内录把允许捕获的 PCM 交给采集应用处理，不等于接管源播放器的输出路由；本应用也没有其他播放器的 `AudioRenderer` 可调用 `setVolume(0)`。系统输出路由只选择系统识别的音频设备，不能把 CarPlayer 的 Wi-Fi RTP socket 注册成系统音频设备。项目当前还把手机媒体音量映射为 CarPlay RTP 增益，因此将手机媒体音量调到零也会把转发 PCM 缩放到零；这项增益耦合是项目实现选择，不是系统强制行为。可行替代是使用系统路由的蓝牙 A2DP，或由源播放器自身提供独立输出/静音控制。 | [华为系统音频录制](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/implement-system-audio-recording.md)、[音频输出设备管理](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/audio-output-device-management.md)、[CarAudioOutput](entry/src/main/ets/audio/CarAudioOutput.ets)、[PlaybackAudioCapture](entry/src/main/ets/audio/PlaybackAudioCapture.ets) |
| 强制第三方应用在虚拟屏横屏 | 本应用可用虚拟屏的宽高形成横/竖几何区域，但没有公开接口替另一个应用设置窗口方向。`setPreferredOrientation` 控制的是调用者自己的窗口；`startAbility` 的 `displayId` 指定启动目标屏幕，不代表目标应用必须按横屏布局。第三方应用是否适配屏幕尺寸由其自身决定。 | [Display API](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/js-apis-display.md)、[窗口方向 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-window-e#orientation9)、[StartOptions](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/js-apis-app-ability-startoptions.md)；项目现状另见 [README](README.md) |
| 向 Phone 上的第三方虚拟屏窗口注入触摸 | 通用触控模拟 API `createTouchController` 的设备范围是 PC/2in1，在其他设备上不支持（返回 801）。输入拦截/监听权限不是输入注入能力，不能据此绕过限制。项目可以处理车机触摸并操作自己的投影 UI，但不能承诺把触摸注入任意第三方应用。 | [InputEventClient API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-inputeventclient)、[Input C API](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/capi-oh-input-manager-h.md)、[CarPlayTouchInput](entry/src/main/ets/video/CarPlayTouchInput.ets) |

## 其他已发现的系统限制

| 能力 | 类别与边界 | 依据与对项目的影响 |
|---|---|---|
| 枚举设备上所有已安装应用 | **公开查询能力受限。**华为说明普通三方应用通常只能查询自身包信息；查询其他应用信息需要特权权限，并且目前不允许查询设备应用列表、不能申请相应权限。因此不能做通用的“扫描所有已安装应用并自动生成投影目录”。 | [华为应用包信息 FAQ](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-ability-162)；项目采用静态候选应用和已声明的 URI scheme，见 [ProjectionAppCatalog](entry/src/main/ets/pages/ProjectionAppCatalog.ets) |
| 启动任意第三方 Ability、把已有应用无损迁移到虚拟屏 | **目标应用与系统启动规则依赖。**目标组件必须允许跨应用启动（例如 `exported`），启动还受组件启动规则约束。指定 `displayId` 只是启动请求参数，不保证目标窗口实际渲染、获得预期焦点、改变方向或保留原有导航状态；URI/App Link 入口也不等于任意 Ability 入口。 | [组件启动规则](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V13/component-startup-rules-V13)、[ProjectionAppLauncher](entry/src/main/ets/pages/ProjectionAppLauncher.ets)、[ProjectionHome](entry/src/main/ets/pages/ProjectionHome.ets) |
| 创建和管理虚拟屏 | **受限权限审批依赖。**`ohos.permission.ACCESS_VIRTUAL_SCREEN` 属于受限开放能力，文档列出的车机导航/视频场景可以申请，但必须按流程提交并获批；代码声明权限、运行时检查或本机调试通过都不代表上架审批必然通过。 | [华为受限开放权限](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/restricted-permissions.md)、[module.json5](entry/src/main/module.json5)、[SettingsPage](entry/src/main/ets/pages/SettingsPage.ets) |
| 跨应用媒体会话控制 | **受限权限与播放器实现依赖。**控制方能力需要申请 `ohos.permission.MANAGE_MEDIA_RESOURCES_FOR_PUBLIC`；即便授权成功，也只能读取目标应用实际发布的 AVSession 信息和有效命令，不能保证每个播放器提供曲目、队列或播放控制。 | [媒体会话控制方](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/using-avsession-controller.md)、[ProjectionMediaCoordinator](entry/src/main/ets/pages/ProjectionMediaCoordinator.ets)、[HelpPage](entry/src/main/ets/pages/HelpPage.ets) |
| 捕获系统播放音频 | **系统授权与隐私过滤依赖。**API 26 起支持系统音频内录；启动授权异步返回。被源应用标记为隐私保护的音频流会被系统过滤，不能保证捕获所有应用或所有声音。 | [华为系统音频录制](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/implement-system-audio-recording.md)、[PlaybackAudioCapture](entry/src/main/ets/audio/PlaybackAudioCapture.ets) |
| 后台维持连接/投影 | **长时任务不是永久保活。**`MULTI_DEVICE_CONNECTION` 可用于合规的多设备连接业务，但后台运行需要按任务类型申请；通知被用户移除或系统判定任务不符合申请类型时，任务可能被停止。应用必须处理取消并释放/恢复连接，不能承诺无限期后台运行。 | [长时任务开发指导](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V13/continuous-task-V13)、[CarPlayBackgroundTask](entry/src/main/ets/session/CarPlayBackgroundTask.ets) |
| 录屏连续性 | **系统事件可中断。**华为 AVScreenCapture 文档说明，录制期间来电/通话及系统用户切换可能导致录制自动停止；需要把停止状态当作真实会话中断处理，不能假设视频采集始终连续。 | [AVScreenCapture 录制指导](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/using-avscreencapture-for-file-0000002239112476)、[projection_napi.cpp](entry/src/main/cpp/projection_napi.cpp) |

## 项目自身限制（不是华为 API 限制）

- 当前 N-API 适配层主动拒绝第二个并发 `AVScreenCapture` 实例，错误信息为 `Only one active AVScreenCapture instance is supported`。这是项目当前实现上限，不应描述为 HarmonyOS API 只能创建一个采集器；如需多路独立采集，应先验证目标 SDK/设备的并发能力、资源占用和合成方案，再调整该门禁。见 [projection_napi.cpp](entry/src/main/cpp/projection_napi.cpp)。
- 手机媒体音量同步到车机 RTP 增益也是项目当前策略。即使以后解耦增益，也只能解决“车机音量跟随手机音量”的问题，不能因此获得静音第三方源播放器本机输出的系统权限。

## 结论

当前明确的普通 Phone API 硬边界是：不能控制第三方源播放器的本机输出、不能替第三方应用设置虚拟屏方向、不能通过 Phone 上不支持的通用触控模拟接口注入第三方窗口。另有应用枚举、虚拟屏权限、媒体控制、音频捕获、第三方 Ability 启动和后台连续运行等条件限制，必须以权限审批、目标应用公开能力及目标设备实测结果逐项判定。

官方接口和权限策略可能随 API 版本、设备类型与审批结果变化；新设备/API 版本应重新核对，不把“尚未验证”或“申请未获批”写成永久不支持。
