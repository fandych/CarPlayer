# CarPlayer

CarPlayer 是一个面向 HarmonyOS 手机的无线 CarPlay 发送端项目。应用通过蓝牙 iAP2 与车机协商连接信息，再通过车机 Wi-Fi 和 AirPlay 建立媒体会话，并将手机侧的投影视图输出到车机。实际连接与投影能力取决于 HarmonyOS 设备、车机实现和目标应用的兼容性；构建成功不代表已通过车机实测。

## 技术结构

```text
手机 UI / SessionController
  ├─ Bluetooth RFCOMM / iAP2 ── 协商连接与 Wi-Fi 参数
  ├─ Wi-Fi / AirPlay ────────── 发现、配对、RTSP 与媒体会话
  └─ 虚拟显示 / 音视频 / 触控 ─ 投影到车机并传回交互
```

- 主应用入口是 `EntryAbility` 和 `pages/Index`；独立的 `ProjectionHomeAbility` 加载投影界面。
- `SessionController` 协调连接生命周期。蓝牙、Wi-Fi、iAP2、AirPlay、音频、视频和显示逻辑分别位于 `entry/src/main/ets` 下的对应模块。
- `entry/src/main/cpp` 提供协议、媒体字节处理和会话生命周期的 C 核心，以及 HarmonyOS N-API 适配层。ArkTS 负责系统 API、异步会话和界面。

## 投影应用与诊断

- 第三方投影入口仅保留导航和音乐应用，应用列表仍提供内置车机主页、设置、主题与分屏功能。图标使用静态资源引用；加载失败时记录错误并显示类别图标。
- 导航预览、全屏地图及分屏地图使用横向内容区域。车机提供竖向有效区域时，地图在其中居中留白，不拉伸画面；音乐区域维持原尺寸。内容区域横向不等于第三方应用进入横屏导航：高德的里程/时间面板布局取决于高德自身的窗口方向处理，当前公开 API 无法替其它应用调用 `setPreferredOrientation`，仍需单独验证。
- 第三方应用画面目前不能通过车机触摸、拖动、多点手势或按键直接操作。项目能处理 CarPlayer 自身 Dashboard 控件的触摸，但 HarmonyOS Phone 没有本项目可用的公开通用接口，将原始输入注入到另一应用的虚拟屏窗口；不会退回注入手机主屏。
- 虚拟屏按创建时的宽高形成横竖几何形态，但 `Display.orientation` 可能为未知值 4，不能通过给该属性赋值强制方向。`startAbility` 的 `displayId` 只指定目标屏幕，不保证第三方应用窗口采用横屏、显示成功或迁移已有任务。完整限制及与 Android CarDeck 的平台差异见 [HarmonyOS CarPlay 客户端实现方案](docs/HarmonyOS_CarPlay客户端实现方案.md)。
- 当前应用使用可观察状态传递到主页、地图表面和 Dock；左侧与底部 Dock 的列表 key 均包含选中状态，切换应用时会更新高亮。首页预览仍高亮 Home，展开地图后高亮地图。
- 控制广播在蓝牙启动前发布，并在加入车机 WLAN 后复用，不重复注销、注册。广播不可用时记录明确警告，继续通过 mDNS/iAP2 端点完成连接。
- 手机菜单进入“日志”后，点击日志标题栏的“⋯”可导出本次运行日志或清空日志；导出保存、写入及关闭失败会报告错误。

## 开发环境与构建

- 使用 DevEco Studio 和项目所需的 HarmonyOS SDK。
- 在 DevEco Studio 打开项目，选择 `default` product 和 `entry` module，然后执行 **Build > Build Hap(s)/APP(s)**。仓库没有签入 Hvigor wrapper 或 npm build script。
- Node 主机测试从项目根目录运行；若 DevEco SDK 不在默认位置，先设置 `DEVECO_SDK_HOME`。

## 测试与静态检查

在 Windows PowerShell 的项目根目录运行：

```powershell
# Node 主机行为测试
node --test entry\src\test\ProjectionBehavior.test.cjs

# 只运行一个 Node 测试（按名称或正则表达式匹配）
node --test --test-name-pattern="irregular-display calibration preserves aspect ratio" entry\src\test\ProjectionBehavior.test.cjs

# 纯 C 原生核心测试
.\entry\src\test\native\run-tests.ps1
```

`run-tests.ps1` 使用 DevEco SDK 自带的 LLVM 工具；SDK 安装位置非默认时设置 `DEVECO_SDK_HOME`。Hypium 测试通过 DevEco Studio 的测试运行器执行；`entry/src/ohosTest` 中的 N-API 测试需要 HarmonyOS 设备。主机 Hypium 测试会注入 ArkTS 替身，不验证原生库运行时行为。`code-linter.json5` 定义 ArkTS lint 规则和排除范围，仓库未提供独立 lint 命令。

## 相关文档

- [原生模块说明与测试边界](entry/src/main/cpp/README.md)
- [HarmonyOS CarPlay 客户端实现方案（设计背景）](docs/HarmonyOS_CarPlay客户端实现方案.md)
- [CarPlay iAP2 控制码字典](docs/CarPlay-iAP2控制码字典.md)
- [CarPlay 功能与通道分析](docs/CarPlay功能与通道分析.md)
- [CarPlay 协议依据与核查记录](docs/CarPlay协议依据与核查记录.md)
- [CarPlay 发送端与 USB 无线协议分析](docs/CarPlay发送端与USB无线协议深度分析.md)
- [CarPlay 完整协议说明](docs/CarPlay完整协议最终版.md)
- [CarPlay 控制码认证与媒体格式详解](docs/CarPlay控制码认证与媒体格式详解.md)
- [手机端 HTML 原型](docs/carplay-phone.html)
- [车机端 HTML 原型](docs/carplay.html)

实现状态和实际支持范围以源码、模块配置及设备测试为准；方案和协议分析文档用于补充背景。
