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
- [CarPlay 客户端实现方案（设计背景）](HarmonyOS_CarPlay客户端实现方案.md)
- [CarPlay 功能与通道分析](CarPlay功能与通道分析.md)
- [协议依据与核查记录](CarPlay协议依据与核查记录.md)

实现状态和实际支持范围以源码、模块配置及设备测试为准；方案和协议分析文档用于补充背景。
