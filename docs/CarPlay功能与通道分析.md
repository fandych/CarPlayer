# CarPlay 功能、显示区域与通信通道分析

进一步阅读：[CarPlay 发送端与 USB / 无线协议深度分析](CarPlay发送端与USB无线协议深度分析.md)、[控制码/认证/媒体格式详解](CarPlay控制码认证与媒体格式详解.md)、[iAP2 endpoint 全量字典](CarPlay-iAP2控制码字典.md)（[CSV](CarPlay-iAP2-endpoints.csv)）。包括 CarDeck、发送端候选、握手交互、控制码命名空间、认证算法、媒体 wire format 和源码证据边界。

> 分析日期：2026-10-31。依据本地 DiPlay、xcertplay、WirelessCarPlay 源码和项目文档，以及 Apple 官方公开资料。项目实现中的编号、协议、端口和测试结果不等于 Apple 对所有 CarPlay 版本的公开规范。本分析未做实车、抓包或构建验证。

## 1. 结论摘要

CarPlay 不仅是一条投屏视频。一个会话可能同时包含：连接发现和认证、主屏视频、可选仪表视频、多用途双向音频、触摸及按键输入、会话控制、时间同步、结构化导航、车辆状态、定位及媒体元数据等。具体能力依赖手机、车机、系统版本、应用和协商结果。

容易混淆的三种内容：

1. **主屏 Dashboard、Dock、地图及应用**：在 DiPlay/xcertplay 的实现中表现为主屏画面内的内容，并不各自对应一条视频流。
2. **仪表地图和转向卡片**：可通过与主屏分开的仪表视频流提供；是否有这条流取决于能力声明及协商。
3. **HUD 箭头、剩余距离、道路名称等**：可以通过结构化导航消息提供，再由车机厂商接口呈现；不能仅凭 HUD 有显示就认定存在独立 HUD 视频流。

普通 CarPlay 的兼容车辆也可在仪表或 HUD 显示导航；CarPlay Ultra 则进一步涉及多个屏幕及车厂系统集成，两者不是同义词。参考 [Apple CarPlay 开发者页面](https://developer.apple.com/carplay/) 和 [Apple CarPlay Ultra 发布说明](https://www.apple.com/newsroom/2025/05/carplay-ultra-the-next-generation-of-carplay-begins-rolling-out-today/)。

## 2. Apple 配件设计指南的范围

已下载：[Accessory-Design-Guidelines.pdf](Apple-Documentation/Accessory-Design-Guidelines.pdf)。文件为 Release R32，日期 2026-10-23，共 397 页。以下页码为 PDF 页码。

在该 PDF 可提取文本中未找到 CarPlay、video stream、H.264 或 H.265 的专项说明。**因此该文件不能证明 CarPlay 视频流数量、类型编号、编解码方式或专用端口。** 文档第 18、22 页说明某些配件接口细节需要另行查阅 MFi 的 Accessory Interface Specification。

| 指南内容 | 页码 | 适用范围 |
|---|---:|---|
| USB NCM 以太网 | 256 | 一般配件网络接入，不能直接当作 CarPlay 专项规定 |
| External Accessory 字节流 | 257 | 一般配件与应用通信，不等同于 CarPlay 特殊通道 |
| GNSS 与传感器信息 | 262 | 一般配件可提供的定位信息 |
| Siri Eyes Free | 292–298 | 车载蓝牙语音体验，不等同于 CarPlay |
| Wi-Fi 信息共享 | 304 | 一般配件功能，依用户授权 |
| 蓝牙 A2DP 音频 | 312–316 | 蓝牙音频场景，不能用来推断 CarPlay 音频格式 |
| iAP2 概述 | 319 | 描述一般配件的高级功能，详细协议需另查 |
| HID | 320–321 | 一般 USB/蓝牙 HID 指南 |

文档的 shall/required、should/recommended、may/optional 具有不同约束强度（第 19 页）；不可把一般配件建议误写为 CarPlay 强制要求。

## 3. 分层架构：以 DiPlay/xcertplay 为例

```text
                             iPhone
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
    发现、配对、认证         控制与协商             媒体和数据
          │                    │                    │
无线：蓝牙/iAP2 → Wi-Fi    AirPlay/RTSP      ├─ 主屏视频 → 显示
有线：USB/iAP2 + NCM        /info、SETUP      ├─ 可选仪表视频 → 显示
                           动态端口、事件     ├─ 多用途音频 ↔ 麦克风
                                              ├─ HID 触摸、旋钮、按键
                                              └─ iAP2 导航、定位、车辆等
```

该图是项目实现的概括，不是 Apple 公布的完整协议拓扑。无线实现中蓝牙主要参与启动与交接，媒体经 Wi-Fi；有线实现中 USB NCM 被桥接为网络，再承载 AirPlay 连接。代码涉及 Android VPN 桥接：[CarPlayVpnService.kt](DiPlay/shared/src/main/java/com/shilapi/xcertplay/network/CarPlayVpnService.kt)。具体连接和网络模式参见 [DiPlay EXISTING_WIFI.md](DiPlay/docs/EXISTING_WIFI.md)。

## 4. 显示与视频相关通道

### 4.1 主屏视频

在 DiPlay 中，iPhone 通过会话协商请求主屏流，车机创建屏幕 TCP listener 并返回系统分配的数据端口。实现读取帧头、处理视频配置和视频帧、解密并转换视频数据，最终交由 Android 解码和显示。项目支持 H.264/H.265；具体格式由能力与会话协商决定。[ScreenStream.kt](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/ScreenStream.kt)

主屏可能出现 Home 应用列表、Dock、Dashboard、多卡片、导航、媒体、Siri 和系统提示，但当前代码没有为每个区域建立单独的视频流。DiPlay 可通过 viewAreas 请求 Dock 在底部或驾驶员侧，iPhone 仍发整帧：[VIEW_AREAS.md](DiPlay/docs/VIEW_AREAS.md)。

### 4.2 可选仪表视频

DiPlay/xcertplay 使用单独的仪表屏类型，请求另一个显示目标及对应视频流；其画面可包含仪表地图、转向卡等，由 iPhone 提供。能否获得该流，以及实际显示内容，都依赖协商、地图应用和车机适配。[BYD_NAVIGATION.md](DiPlay/docs/BYD_NAVIGATION.md)

DiPlay 对部分车机提供仪表显示、地图浮窗及 Launcher 集成；浮窗使用同一仪表流的额外解码路径，不代表完整主屏画中画或任意数量的独立视频流。[LAUNCHER_INTEGRATION.md](DiPlay/docs/LAUNCHER_INTEGRATION.md)

xcertplay 的网页主屏与仪表显示是额外的局域网展示路径，不是证明 iPhone 原生传输了浏览器协议：[xcertplay README](xcertplay/README.zh-CN.md)。

### 4.3 停车视频播放不是普通主屏投屏

DiPlay 另有可选的停车视频播放功能：协商后由 iPhone 提供媒体 URL 和播放/暂停/跳转命令，车机播放器加载媒体；实现还涉及单独的数据和遥控会话。这与主屏 type 110 投屏视频不同。项目要求确认 P 挡，读不到挡位也不允许；服务、版权保护及车型兼容性有限。请勿绕过这些行车安全限制。[BYD_NAVIGATION.md](DiPlay/docs/BYD_NAVIGATION.md)

## 5. 项目中出现的流类型

以下编号是**所查看 DiPlay 实现**的类型值，不是 Apple 在本 PDF 公开的完整标准；不保证其他版本或设备相同。实际端口、格式和是否建立以 SETUP 协商为准。

| Type | 代码中的用途 | 方向及说明 |
|---:|---|---|
| 110 | 主屏 | iPhone → 车机，屏幕视频 |
| 111 | 仪表/副屏 | iPhone → 车机，可选独立屏幕视频 |
| 100 | 主实时音频 | 用 audioType 进一步区分媒体、提示、电话等；可能有上行 |
| 101 | 另一实时音频类型 | 配合 audioType 标明用途 |
| 102 | 高质量主音频 | 项目能力声明包含 AAC-LC 媒体 |
| 103 | 缓冲音频 | 项目可选的 AAC-LC 缓冲音乐流 |
| 130 | 数据类型 | 可用于 iAP2 tunnel，也存在其他用途；不能将所有 130 流一律视为同一业务 |

流类型、`audioType` 和 Android 本地音频 stream type 是不同编号体系。[AirPlaySession.kt](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt)、[AirPlayInfoPlist.kt](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlayInfoPlist.kt)。

仓库中的 [xcertplay 双屏握手测试记录](xcertplay/common/src/test/resources/handshake-wireless-cluster.txt) 展示过一次主屏、仪表与数据流分别协商，以及双屏首帧；这只是一次记录，不代表所有手机会提供仪表视频。

## 6. 音频、麦克风与时钟

| 功能 | 典型方向 | 实现侧重点 |
|---|---|---|
| 音乐/媒体 | iPhone → 车机 | 实时或缓冲音频，由车机输出 |
| 导航提示、系统提示 | iPhone → 车机 | 可按用途映射车机音频路由及焦点 |
| Siri/语音识别 | 双向 | 提示音下行，麦克风可上行 |
| 电话 | 双向 | 电话语音下行及麦克风上行 |
| 时钟和同步 | 双向/会话相关 | 用于协调媒体时间，不是额外画面 |

DiPlay 可按 `(type, audioType)` 区分并存的音频用途；实时音频代码创建 UDP 数据与控制 socket。能力声明包含 PCM、Opus 和 AAC-LC 等，但**最终格式取决于具体 SETUP**，不是每一通道固定使用同一编码。Android 路由还受 ROM 和车机音频焦点影响。[CarPlayMediaEngine.kt](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/CarPlayMediaEngine.kt)、[AudioStream.kt](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AudioStream.kt)、[AudioChannelMapping.kt](DiPlay/shared/src/main/java/com/shilapi/xcertplay/media/AudioChannelMapping.kt)。

公开的 CatPlay 实现也分别有 [UDP/RTP 音频接收](https://github.com/catplay-labs/catplay/blob/master/carplay/catplay_carplay/src/rtp/play/rtp_session.rs) 和 [麦克风发送](https://github.com/catplay-labs/catplay/blob/master/carplay/catplay_carplay/src/rtp/record/rtp_session_tx.rs) 路径；这些属于其具体实现，不应推广为所有 CarPlay 版本必须如此。

## 7. 输入与控制通道

触摸、旋钮、电话键和媒体键是输入事件，不是视频的反向传输。DiPlay 将触摸坐标和按键编码为 HID 报告，通过控制消息传递；其代码中也存在 iAP2 HID 消息，因此 HID 不应被简单等同于物理 USB HID 设备。[AirPlaySession.kt](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt)、[CarPlayTouchMapper.kt](DiPlay/shared/src/main/java/com/shilapi/xcertplay/media/CarPlayTouchMapper.kt)。

画面缩放、黑边、旋转及安全区会影响触摸坐标映射。车机原生侧栏属于宿主自己的 Android 界面，其触摸不应作为 CarPlay 画面触摸发送：[SIDE_PANEL.md](DiPlay/docs/SIDE_PANEL.md)。

AirPlay 会话还处理能力交换、SETUP、事件、显示控制和流关闭等。DiPlay 默认控制端口为 7000，但端口被占用时可选择其他可用端口；媒体端口也可能由系统动态分配，不能假设永远是固定端口。[AirPlayPortSelector.kt](DiPlay/shared/src/main/java/com/shilapi/xcertplay/network/AirPlayPortSelector.kt)

## 8. 结构化导航、车辆状态与其他数据

| 功能 | 方向 | DiPlay 示例 | 是否视频 |
|---|---|---|---|
| 路线引导 | iPhone → 车机 | iAP2 `0x5201` 路线更新、`0x5202` 转向更新；包含距离及动作等 | 否 |
| HUD/车机导航提示 | 车机内部输出 | 将结构化导航转换为厂商接口，部分车型可到 HUD | 不必是视频 |
| 车辆状态 | 车机 → iPhone | 例如 `0xA100` 请求，`0xA101` 状态更新，可含电量/续航 | 否 |
| 定位信息 | 车机 → iPhone | iAP2 `0xFFFB` 中承载 NMEA 等信息 | 否 |
| 媒体元数据 | iPhone → 车机 | 标题、艺术家、播放状态等可有独立消息 | 否 |

上述编号和字段属于具体项目代码，不代表每辆车、每个 App 或全部 CarPlay 版本均有对应内容。仪表视频存在也不保证路线结构化消息存在；收到路线消息也不保证厂商 HUD 接口可用。DiPlay 文档的特定固件测试和未验证范围见 [BYD_NAVIGATION.md](DiPlay/docs/BYD_NAVIGATION.md)。

其他公开实现的结构化数据参考：[LIVI 路线引导定义](https://github.com/f-io/LIVI/blob/main/native/crates/iap2-csm/src/messages/route_guidance.rs)、[车辆状态定义](https://github.com/f-io/LIVI/blob/main/native/crates/iap2-csm/src/messages/vehicle_status.rs)、[媒体元数据定义](https://github.com/f-io/LIVI/blob/main/native/crates/iap2-csm/src/messages/now_playing.rs)。

## 9. 新下载项目的交叉验证：type 130 与 Ultra

本地 LIVI 和 CatPlay 源码进一步说明：**流类型相同不代表业务相同**。LIVI 对 `type=130` 根据 `clientTypeUUID` 分支，例如：

| LIVI 中的用途 | 代码中的识别方式 | 说明 |
|---|---|---|
| iAP tunnel | `E9459FD0-BCAD-4C45-820F-1E72447EF2F2` | 承载 iAP 通信的数据路径 |
| 车辆状态 | 普通及高优先级两种 UUID | 分别有处理路径；车辆消息不等于屏幕视频 |
| uiSync | 单独 UUID | 按手机能力及显示配置有条件启用 |
| 视频播放 | 单独 UUID | 遥控/会话路径，不等同于屏幕视频 |
| 视频设置、overlay | 各有 UUID | 独立的数据处理路径 |

查看 [LIVI data_streams.rs](GitHub-CarPlay-Projects/LIVI/native/crates/livi-cp/src/stack/data_streams.rs)、[LIVI video_playback.rs](GitHub-CarPlay-Projects/LIVI/native/crates/livi-cp/src/video_playback.rs)。UUID 也只是该实现中的标识；LIVI 与 DiPlay 对部分视频相关 UUID 的处理不完全相同，不能认为存在统一且公开完整的通道说明。

LIVI 代码分别建立 110/111 屏幕接收器，并有主题化 panel、uiSync 及车辆状态相关代码；这**不证明完整 Ultra 功能或任何实车的兼容性**。CatPlay 当前所查代码有主屏流处理，但 `111` 在枚举中被列为注释项，不能仅凭显示 UUID 推断其已实现仪表视频。参考 [LIVI setup.rs](GitHub-CarPlay-Projects/LIVI/native/crates/livi-cp/src/stack/setup.rs)、[CatPlay streams.rs](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/msg/streams.rs)。

排查时应同时记录协议上下文、stream type、UUID、stream ID、connection ID、方向和实际端口。同一个数字在不同协议或消息空间中可能含义不同；例如不能把 iAP2 消息 ID、RTSP 类型和 MFi 会话中的同值常量混为一谈。

## 10. 认证、安全与能力限制

MFi 身份认证、配对和加密与显示流是不同环节。xcertplay 文档列出芯片、远程服务及本地认证材料等方式；能否实际运行取决于合法有效身份、硬件和项目配置。不要将证书、私钥、配对记录或抓包中的敏感材料提交到代码仓库或分享给他人。

停车视频与常规主屏投影不同：主屏画面使用视频编码传输，并不代表可在行驶时观看影片。视频应用及 AirPlay 视频功能需要兼容车辆和停车条件：[Apple CarPlay 开发者页面](https://developer.apple.com/carplay/)。

## 11. 建议的排查顺序

1. **发现和认证**：设备是否发现、完成配对、认证及网络切换。
2. **能力声明和协商**：主屏/仪表、音频用途、安全区和流是否被请求。
3. **监听和首包**：实际协商的端口是否连通；每条流是否有数据或首帧。
4. **解码和输出**：主屏、仪表、音频设备各自是否建立并正确路由。
5. **输入映射**：触摸、旋钮、按键是否送入正确会话；黑边及缩放是否正确。
6. **结构化数据**：导航、车辆和定位消息是否实际出现，再单独检查车厂接口/HUD。
7. **生命周期**：重连、切屏、音频焦点变化及断连时各流是否恢复或清理。

主屏有画面只说明主屏链路可用，不代表仪表、麦克风、HUD 或车辆数据链路也可用。

## 12. 下载清单与完整性

Apple 指南保存为 [Accessory-Design-Guidelines.pdf](Apple-Documentation/Accessory-Design-Guidelines.pdf)。公开仓库保存到 `GitHub-CarPlay-Projects`，采用浅克隆，未下载子模块、未运行项目脚本。以下是检出版本（HEAD 简写）：

| 仓库 | 本地目录 | HEAD | 状态 |
|---|---|---|---|
| f-io/LIVI | `LIVI` | `e7b20b8` | 已检出 |
| catplay-labs/catplay | `catplay` | `fc52bac` | 已检出 |
| youcci/playport | `playport` | `9a0882d` | 已检出 |
| fython/wheelplay | `wheelplay` | `7a82bcb` | 已检出 |
| luka-dev/mib2q-carplay-rgi | `mib2q-carplay-rgi` | `df73e06` | 已检出 |
| wiboma/hudiy | `hudiy` | `1c5a690` | 已检出；仓库以文档、配置和示例为主 |
| rhysmorgan134/react-carplay | `react-carplay` | `090b43d` | 已检出 |
| niellun/FastCarPlay | `FastCarPlay` | `f483456` | 已检出 |
| electric-monk/pycarplay | `pycarplay` | `8d9a313` | 已检出 |
| ludwig-v/wireless-carplay-dongle-reverse-engineering | `wireless-carplay-dongle-reverse-engineering-source` | `b437135` | 部分检出，见下 |
| birkir/react-native-carplay | `react-native-carplay` | `829c8a2` | 已检出 |

盒子逆向仓库采用部分检出：已下载 3,383 个源码、补丁、配置及文档等文件；未检出 7,671 个文件，仓库文件大小合计约 4.53 GB，主要位于固件和提取文件目录，包含镜像、二进制及无扩展名文件。无扩展名文件未逐一鉴定，因此不能保证所有源码都已下载。完整遗漏清单：[wireless-carplay-omitted-files.csv](GitHub-CarPlay-Projects/wireless-carplay-omitted-files.csv)，分类汇总：[wireless-carplay-omitted-summary.csv](GitHub-CarPlay-Projects/wireless-carplay-omitted-summary.csv)。
