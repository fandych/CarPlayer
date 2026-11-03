# Agent instructions

本文件适用于在此仓库中工作的编码代理。项目概览见 [README.md](README.md)；Copilot 的补充说明见 [.github/copilot-instructions.md](.github/copilot-instructions.md)。

## 项目结构与职责

- 这是由 Hvigor 构建的 HarmonyOS 应用，主业务模块为 `entry`。
- `entry/src/main/ets/entryability` 定义手机与投影窗口的 Ability；`pages` 保存 ArkUI 页面。`Index` 管理手机侧 UI，`ProjectionHome` 管理投影界面。
- `session/SessionController` 是连接生命周期的协调层，组合 `transport`、`network`、`iap2`、`airplay`、`audio` 和 `video` 模块。保持 UI、协议、传输和系统 API 的边界，不要把连接流程分散到页面组件中。
- `entry/src/main/cpp` 的协议、媒体和会话核心尽量保持为可独立测试的 C 代码；HarmonyOS N-API 和系统媒体接口留在对应适配层。新增或修改导出接口时，同步维护 `cpp/types/lib*/` 声明。

## 实现约定

- 用 `SessionController` 现有的会话 generation 生命周期机制防止停止或重连后的迟到异步回调继续改变状态；资源所属类应负责清理自己的 socket、监听器、显示和捕获资源。
- 多 Ability 共享的投影状态通过现有 `AppStorage` key 传递；修改 key 时同步更新发布方和读取方。
- 协议诊断沿用 `ProtocolLogger` / `formatProtocolEvent`，事件名保持点分隔格式。
- 连接配置由现有 settings/store 模块负责；不要从页面或协议代码绕过存储层读写配置。
- 不要将签名材料或机器相关路径从 `build-profile.json5`、`certs/` 复制到源代码、文档或日志。

## 文档位置

- CarPlay 协议、实现方案和分析资料统一放在 `docs/`，不要再从仓库根目录引用这些文档。
- 实现方案：[HarmonyOS CarPlay 客户端实现方案](docs/HarmonyOS_CarPlay客户端实现方案.md)。
- 协议资料：[iAP2 控制码字典](docs/CarPlay-iAP2控制码字典.md)、[功能与通道分析](docs/CarPlay功能与通道分析.md)、[协议依据与核查记录](docs/CarPlay协议依据与核查记录.md)、[发送端与 USB 无线协议分析](docs/CarPlay发送端与USB无线协议深度分析.md)、[完整协议说明](docs/CarPlay完整协议最终版.md)、[控制码认证与媒体格式](docs/CarPlay控制码认证与媒体格式详解.md)。
- 手机端和车机端 HTML 原型位于 `docs/carplay-phone.html` 与 `docs/carplay.html`。

## 构建与验证

- 在 DevEco Studio 中构建 `entry` module 的 `default` product（Build > Build Hap(s)/APP(s)）；仓库没有签入 Hvigor wrapper 或 npm build script。
- Node 主机行为测试：`node --test entry\src\test\ProjectionBehavior.test.cjs`。
- 单个 Node 测试：`node --test --test-name-pattern="<test title or regex>" entry\src\test\ProjectionBehavior.test.cjs`。测试从 DevEco SDK 加载 TypeScript；SDK 不在默认位置时设置 `DEVECO_SDK_HOME`。
- 纯 C 测试：在 Windows PowerShell 项目根目录运行 `.\entry\src\test\native\run-tests.ps1`；SDK 不在默认位置时设置 `DEVECO_SDK_HOME`。
- Hypium 测试通过 DevEco Studio 测试运行器执行；`entry/src/ohosTest` 的 N-API 覆盖需要 HarmonyOS 设备。主机替身测试不代表原生库已在设备上验证。
- ArkTS lint 配置位于 `code-linter.json5`；仓库没有独立 lint 命令。

协议实现和系统能力的实际兼容性需要结合设备验证；构建或主机测试通过不能替代车机实测。
