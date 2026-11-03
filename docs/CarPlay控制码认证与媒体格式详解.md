# CarPlay 控制码、认证与媒体格式详解

> 范围：以 DiPlay/xcertplay、CatPlay、CarDeck 和 LIVI 等本地公开代码为证据，补充主报告中容易被简写成“0x00”“认证版本”“音频格式”的部分。它是源码级互操作分析，不是 Apple 的完整规范；各实现、iOS 版本与链路模式可能不同。除非另有说明，结论是静态代码分析，不代表本次执行或实车验证。
>
> 关联资料：[USB/无线协议主报告](CarPlay发送端与USB无线协议深度分析.md)、[iAP2 151 项 endpoint 字典](CarPlay-iAP2控制码字典.md)（配套 [CSV](CarPlay-iAP2-endpoints.csv)）。字典提供声明/方向/schema，不声称每一项都有工作 handler。

## 1. 首要原则：编号必须带命名空间

`0x00`、`0` 或 `1` 都不是跨协议的通用“成功”“开始”码。解码时至少需要知道承载协议、字段名、消息方向及当前状态。

| 数值 | 所属字段/空间 | 源码中含义 | 接收端/对端的处理边界 |
|---|---|---|---|
| `0x00` | Pair-Setup TLV 的 **Type** | `TYPE_METHOD` 的 TLV 类型编号；不是 method 的取值，也不是认证成功码 | 先按 TLV8 的 `[type,length,value]` 解包，再按当前 Pair-Setup 状态解析 value；不能把类型号当状态 |
| `0x06` | Pair-Setup / Pair-Verify TLV **Type** | State 字段类型；value 才是 M1/M2…状态号 | 先检查 TLV 边界，再依 state 分派；未知/缺失状态应报错或关闭，不进入后续密钥状态 |
| `0x07` | Pair-Setup / Pair-Verify TLV **Type** | Error 字段类型；其 value 是错误枚举 | 是失败响应字段，不是 iAP2 endpoint，也不等于 HTTP 状态码 |
| `0` | 视频流 TCP 128-byte header 的 opcode | DiPlay `OP_VIDEO_FRAME`：后接加密视频帧 | 按帧计数器解密、验证 AEAD tag，再交 H.264/H.265 解码器；不能将其解释为“空帧” |
| `1` | 同一视频 header 的 opcode | `OP_VIDEO_CONFIG`：codec config body，在该实现里明文 | 提取 `avcC`/`hvcC`，初始化对应解码器；不按视频帧 nonce 解密 |
| `0` | HID `hidInputMode` 枚举 | `Default` 输入模式 | HID 解释依据枚举字段；并非控制消息成功状态 |
| `0` | ChangeModes 的 Entity / AppState / SpeechMode | 分别为 `None`、`Invalid`、`Invalid` | 各自表示未指定/无效语义；不要互换，也不要认为是默认资源所有者 |
| `0` | ChangeModesResponse 的 `status` | CatPlay 结构注释称 0 表示无错误 | 仅在该 response 字段中表示成功；返回的 `params` 是模式快照 |
| `0` | StreamType | CatPlay 定义 `Invalid=0` | 非有效的流业务类型；不能映射成视频 opcode 0 |

证据：[PairSetup 常量与状态分派](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/PairSetup.kt#L15-L129)、[PairVerify](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/PairVerify.kt#L24-L120)、[ScreenStream opcode/header](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/ScreenStream.kt#L15-L145)、[HID 命令字段](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/msg/commands/command_structs.rs#L39-L62)、[ChangeModes 数值枚举及 response](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/modes/change_modes.rs#L10-L38)、[Entity/AppState/资源枚举](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/modes/change_modes.rs#L150-L232)、[StreamType/AudioFormat](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/msg/streams.rs#L1-L60)。

## 2. 双端行为速查：从 transport 到处理器

### 2.1 iAP2 endpoint 与 CarPlay `POST /command` 不是同一码表

| 通道 | 外层格式 | 内层标识 | 通常应做的处理 |
|---|---|---|---|
| iAP2（USB/蓝牙/130 tunnel 中继） | iAP2 packet/frame；130 tunnel 还包在 AirPlay DataStream 加密帧及 APTransportPackage 中 | 16-bit endpoint ID，例如 `0x4301`、`0x5702`；其方向依 endpoint 声明 | 依 endpoint registry 查 schema、长度/分组与方向，再交对应 handler。未知 endpoint 保留原始信息/返回适当协议错误，不能猜用途或静默冒充成功 |
| CarPlay control RTSP `/command` | RTSP/1.0 text headers + binary plist body | plist 字典的字符串 `type` 和 `params`，例如 `changeModes`、`hidSendReport`、`requestUI` | 先解析 plist 与 type；依命令方向和参数 schema 执行资源状态/HID/UI/媒体动作。CatPlay 命令枚举只是它支持的子集 |
| Remote-control/data stream | `/command` 可带 `X-Apple-StreamID`，body 内还有 `params.data` plist | stream ID + 内嵌消息字典；不是普通 command enum，也不是 iAP2 endpoint | 外层 header、内层 plist 分层解析；仅按对应 stream/profile 交给数据通道 handler |
| Stream SETUP | binary plist 的 `streams[]` | `type`（流用途）、`uuid`、`streamConnectionID` 等 | 做支持能力交集；开实际 TCP/UDP listener 后才答 `dataPort`；未成功绑定或认证不能虚报端口 |

DiPlay 在 type 130 tunnel 中先按 2-byte length + ChaCha20-Poly1305 解密，再解析 APTransportPackage；`messageType=comm` 的 payload 才作为 iAP 字节上送。见 [IapTunnel](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/IapTunnel.kt#L15-L23) 与 [DataStream package parse](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/IapTunnel.kt#L151-L190)。因此 tunnel 的外层 TCP、加密 frame、APTransportPackage、iAP2 endpoint 是四层，不应将其长度/类型字段混为一谈。

### 2.2 部分命令方向与参数

以下是 CatPlay `CommandType` 实际列出的方向/字段；不代表 Apple 全量命令表。`FromAccessory`/`FromDevice` 为该 crate 的角色命名，请结合具体 sender/receiver 配置，不直接等同于 IP socket 的 client/server。

| 字符串 type | CatPlay 方向 | 可见参数/动作 | 实现提示 |
|---|---|---|---|
| `changeModes` | accessory → device | `appStates[]`, `resources[]`, `reasonStr`, `initialPermanentEntity[]` | 资源取用/借用/归还及 app state 独立处理；响应 `status` 和更新后 `params`，不要把“请求成功”误认为某路媒体已开始 |
| `modesChanged` | device → accessory | 更新后的模式快照 | 车机更新本地资源仲裁状态，不应把每次变化当作 SETUP 或媒体重连 |
| `hidSendReport` | accessory → device | 二进制 `hidReport`、可选同步时间戳、HID UUID | 报告格式需匹配 HID descriptor；虚构/错序报告不等于触摸成功 |
| `hidSetInputMode` | device → accessory | `hidInputMode`, HID UUID | 按该 HID 的 mode 解读输入 |
| `requestSiri` | accessory → device | `siriAction`: Prewarm=1, ButtonDown=2, ButtonUp=3 | 依次控制预热/按下/释放；不等于把麦克风音频包发送成功 |
| `requestUI` | accessory → device | 可选 URL | URL/UUID 与已协商显示有关；不要把 dashboard 内容硬编码为独立 stream |
| `forceKeyFrame` | accessory → device | 空对象 | 请求关键帧，不是 codec 切换 |
| `duckAudio` / `unduckAudio` | device → accessory | `durationMs`, `volume` | 控制音量淡入/淡出；当前 DiPlay 也将其映射到音频 duck 回调 |
| `setNightMode` / `setLimitedUI` | accessory → device | boolean (`nightMode`, `limitedUI`) | UI 状态命令；是否响应由对应会话能力决定 |
| `iAPSendMessage` | 双向 | plist binary `data` | 传递 iAP message 数据；外层 command 不是 endpoint ID |

证据：[type 名称/方向](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/msg/commands/command_types.rs#L1-L105)、[命令 plist schema](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/msg/commands/command_structs.rs#L1-L121)、[DiPlay 对 `/command` 的解析和回调](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L748-L783)。`setVideoPlaybackAllowed`、`showUI`、`stopUI` 等 DiPlay 代码可见字符串不一定都在 CatPlay 当前 CommandType enum 内；不要因 crate enum 不包含而断言 Apple 不支持。

### 2.3 如何从车机回传内容识别“事件”

不要先按“点击/切歌/夜间模式”猜 payload；先识别承载通道和外层封装，再解析内层命名空间：

1. **iAP2 控制链路**：按 iAP2 frame 解出 `messageId`（如 `0x4300`），再按 endpoint 参数 schema 解析。`0x4300` 是有线/无线可用性声明，不是运行期 UI 事件。
2. **AirPlay RTSP control socket**：解析 RTSP method/path、`CSeq` 和 binary plist body。常见 `/command` 的内层 `type` 是字符串，不是 iAP2 endpoint number。
3. **AirPlay event socket**：`SETUP` 初始响应带 `eventPort`；连接需来自同一控制 peer，建立 Pair-Verify 派生的 event 读/写密钥后，才可解密 RTSP 风格 event frame。CatPlay 的 `EventsServer` 对 `/command` body 做 binary-plist `Command` 反序列化并调用 handler。
4. **HID 命令**：从 command 的 `uuid` 找到 `/info` 声明的 HID descriptor，再以 descriptor 的 report layout/usage 解码 `hidReport`。点击、滑动通常不是 `click`/`swipe` 字符串，而是触点状态、坐标及按下/抬起等报告。
5. **音频与 iAP 数据**：语音音频、媒体 RTP、iAP tunneled frame 是数据面；不要把它们当作 `/command` plist。查看已协商 stream type、格式和实际数据方向。

| 现象/业务 | 可观察标记与方向（以 CatPlay 命令模型为参照） | 正确判读 | 易混淆项 |
|---|---|---|---|
| 屏幕点击、滑动、多点触控 | `hidSendReport`，`uuid` 指向触摸 HID，`hidReport` 是 bytes；Accessory → Device | 按该 UUID 的 HID descriptor 解出触点 slot、接触状态、X/Y、报告时间；由连续报告还原手势 | 没有通用的“tap opcode”。像素坐标范围取决于 descriptor/display；短按需看到 down/up 两阶段 |
| 旋钮、方向键、媒体键 | 同样是 `hidSendReport`，但 UUID/descriptor 与触摸设备不同 | 先区分 knob、media、telephony HID，再依据 usage 和 report ID 解码。相同 byte 值在不同 HID descriptor 下可有不同含义 | 不可拿触摸 report 的解码逻辑解析媒体键；CarPlay 标准也不保证所有 accessory 使用同一私有 UUID |
| 播放/暂停、上一首/下一首 | 可走 media HID report；媒体库控制另有 iAP2 `0x4C06`–`0x4C09` 声明 | 媒体键是用户输入；`PlayMediaLibrary*` 是媒体库选择/播放请求，不等于上一首等按键。依 endpoint schema、HID usage 和会话日志分别处理 | 不能把 `duckAudio` 当作暂停；它是音频 ducking。iAP2 catalog 声明也不证明某个项目实现了 handler |
| 夜间/白天模式 | CatPlay `setNightMode` (`params.nightMode: bool`) 方向为 Accessory → Device | 车机告知手机当前明暗状态；应把 `true/false` 更新为 UI 环境状态 | 这是车机发给手机，不是手机回传给车机的事件。RTSP `modesChanged` 是资源/模式快照，也不等价于夜间模式 |
| 资源/界面模式变化 | `modesChanged` (Device → Accessory)，`changeModes` (Accessory → Device) | 作为状态通知/资源协调解析 `params`，按 entity/appState/resources 字段更新状态 | 不是触摸事件、不是版本号，也不必然意味着音视频流已重建 |
| Siri/语音键 | `requestSiri` + `params.siriAction`（Prewarm=1、ButtonDown=2、ButtonUp=3），Accessory → Device | 它是 Siri 交互控制信号；根据 down/up 生命周期启停 UI/捕获，不把信号本身当作语音内容 | 实际语音采样/编码在协商的音频 uplink stream，不在此 plist 命令里；需结合 `/info` audioFormats 和 SETUP/RTP |
| 音频闪避 | `duckAudio` / `unduckAudio` (Device → Accessory)，参数含 `durationMs`、`volume` | 对本地播放音量做淡入/淡出；分别跟踪当前 duck 状态 | 不等于播放/暂停或曲目切换 |
| 媒体库标题/列表更新 | iAP2 `0x4C00`–`0x4C05` 的 start/stop/update 声明，方向包含手机 → 配件更新 | 区分查询/订阅与手机回送的 library/update 数据；需按具体 endpoint schema 解码 | 这类元数据不是音乐流，也不代表用户刚按了“下一首” |

**当前 DiPlay 的重要实现边界：**该实现用 `eventPort` 建立并解密 event socket，发送 `setNightMode`、HID 等事件；但其 event 读取循环仅解析 RTSP framing、跳过响应行并记录收到的 method/path/header/body，然后回 200，并没有像 CatPlay `EventsServer` 那样将 event body 反序列化为 command 并调用业务 handler。因此不能据 DiPlay 的当前 event reader 声称它已完整处理车机回传的 event command。DiPlay 普通 control socket 的 `/command` handler 确实会解 plist、读 `type`/`params`，但目前只内置处理少数类型，其余交给 listener callback。**这说明同一协议概念在项目中的接收能力不同，不代表 event-port 上永远不会有命令。**

证据：[CatPlay 命令方向](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/msg/commands/command_types.rs#L95-L111)、[Siri 与夜间模式字段](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/msg/commands/command_structs.rs#L74-L102)、[CatPlay event `/command` 解码/handler](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/events/events_server.rs#L72-L82)、[DiPlay 在 SETUP 响应 eventPort](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L673-L690)、[DiPlay control `/command` 解析](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L759-L781)、[DiPlay event channel 密钥和收包循环](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L900-L954)、[DiPlay HID UUID/report descriptor](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlayHid.kt#L21-L128)、[iAP2 媒体库 endpoints](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L633-L642)。

### 2.4 如何判断协议版本/能力

**本地源码没有证明存在一个可从单字段读出的全局 CarPlay 协议版本协商号。**CatPlay `/info` schema 有可选 `protocolVersion`（源码注释为 `1.0`）、`sourceVersion`（SDK 版本）与 `OSInfo`；DiPlay `/info` 输出 `sourceVersion`、`features`、`extendedFeatures`、`displays`、`audioFormats`、`modes`、`hidDevices` 等能力，但该 response builder 没有 `protocolVersion` 字段。`RTSP/1.0` 只是报文语法标记，不等于 CarPlay feature/protocol release；`sourceVersion`、iOS `OSInfo`、`X-Apple-HKP` 也不能独立证明所选协议分支。

实际互通判断按层留存证据：记录 `/info` 的能力字段和 bitmask；两端提出/接受的 SETUP stream type/UUID/format；认证方法与状态；命令 type、方向、参数；实际建立的 TCP/UDP/event socket 及运行时行为。能力声明只能表示“宣称支持”，以 SETUP response 接受、端口可连通、数据可解码及命令有 handler 为准。版本不明或字段缺省应标“未声明/未观察”，不要自行映射到一个猜测的 CarPlay 代际。

证据：[CatPlay `/info` version/OS/features schema](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/msg/info.rs#L28-L73)、[DiPlay `/info` 能力字段](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlayInfoPlist.kt#L28-L60)、[DiPlay SETUP 取 feature 交集并返回 enabledFeatures](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L673-L698)。

### 2.5 如何判断 Wi-Fi P2P 还是普通热点

iAP2 无线流程可见的 `0x4300` 是有线/无线 CarPlay availability；`0x5702` 请求 Wi-Fi 配置、`0x5703` 携带 SSID、passphrase、security type、channel 和可选 BSSID。这些字段可说明无线能力和接入参数交换，但当前检查的 schema 没有一个明确的 `P2P=true` / `SoftAP=false` 拓扑标志。SSID、BSSID、信道、密码、甚至“手机连到一个像 AP 的网络”都不足以单独判别：Wi-Fi Direct Group Owner 也能表现成可供 legacy client 加入的 AP。

要给具体连接分类，应在建立连接的操作系统/端侧读取权威状态：

- Android Wi-Fi Direct：查询当前 `WifiP2pGroup`、`isGroupOwner`、group network name/owner 与 P2P 接口；DiPlay 的 `WirelessHotspotBackend.WIFI_P2P` 是项目创建路径证据。
- LocalOnlyHotspot/普通 SoftAP：查看 Android hotspot backend/系统 SoftAP 配置和接口，而不是仅看 SSID。DiPlay 把 `LOCAL_ONLY_HOTSPOT` 与 `WIFI_P2P` 明确作为不同 backend。
- 已有 WLAN/同网段：查看关联网络、接口及路由；代码里的 `EXISTING_WIFI` 也与前两者区分。
- 对未知原车：采集连接双方 OS Wi-Fi Direct group/supplicant/NL80211 状态、P2P negotiation/association 日志；必要时做 monitor-mode 抓包并核对 P2P IE/协商过程。仅有 iAP2 `0x5703` 配置或被动 SSID scan 时，结论应是“拓扑未确认”。

证据：[iAP2 0x4300 可用性字段](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/message/Iap2Messages.kt#L102-L150)、[0x5703 配置 schema](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/message/Iap2Messages.kt#L152-L165)、[无线协商状态处理](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2WirelessControlClient.kt#L128-L177)、[DiPlay 无线 backend 枚举](DiPlay/shared/src/main/java/com/shilapi/xcertplay/network/WirelessHotspotManager.kt#L7-L20)、[Wi-Fi Direct group owner/group fields](DiPlay/shared/src/main/java/com/shilapi/xcertplay/network/WifiP2pGroupManager.kt#L652-L690)。

完整的 iAP2 endpoint 方向、功能组、confidence、typed fields/未细化 schema 及本地词法引用见 [端点字典](CarPlay-iAP2控制码字典.md)。其 151 个声明由 DiPlay catalog 提取（61 个具名、90 个内联、151 个唯一 ID）；endpoint declaration 不等于 handler/Apple 规范。

## 3. Pairing/auth：算法、选择依据与失败处理

### 3.1 不能混为一个“认证版本”

| 层 | 所在链路 | 目标 | 本地代码能证明什么 | 不能从它推断什么 |
|---|---|---|---|---|
| USB Lockdown pairing / TLS | USBMUX 服务字节流 | 与手机建立信任配对并访问服务 | 具体实现可读到服务启动、配对记录及连接逻辑 | 不等于 iAP2 MFi 认证，也不等于 AirPlay pair-setup 成功 |
| iAP2 MFi authentication | iAP2 authentication endpoint | 验证配件/MFi 证书和 challenge signature | iAP2 catalog 和 MFi provider 代码可见请求、证书、challenge 路径 | 生成签名不证明手机验证通过，或证书链合法 |
| AirPlay `pair-setup` | RTSP control + TLV8 | 建立长期 controller/accessory pairing，交换 Ed25519 身份材料 | DiPlay responder 使用 SRP-6a (RFC 5054 3072-bit group, SHA-512) | 不是所有 iOS/CarPlay profile 一律使用该分支 |
| AirPlay `pair-verify` | RTSP control + TLV8 | 验证已存 controller 身份并生成 control-channel keys | DiPlay 使用临时 X25519、Ed25519 签名与 HKDF-SHA512 | 不能代替 MFi 配件认证 |
| `/auth-setup` MFiSAP | RTSP control，DiPlay 注释说明在已加密控制连接上处理 | 向手机证明 MFi 配件身份 | DiPlay 的 MFI 分支按 `protocolMajor()` 选择摘要 | `X-Apple-HKP: 2`/`3` 不是 SRP、MFi 或 HKDF 的总版本号，也不能当作算法协商结果 |

重要：已有 sender/receiver 代码对请求头与认证分支并不完全一致。应当以本次连接实际的 method/path/body、证书和协商结果选择 handler；不能只看一个头字段就决定全部密码算法。源码是项目分支实现，不是 Apple 全局规则。

### 3.2 DiPlay Pair-Setup：SRP 参数和 M1–M6 状态

DiPlay 的 accessory-side responder 对 TLV 中的 `state` value 分派 1/3/5；server 分别返回 2/4/6。处理流程如下：

1. **M1 请求**：TLV state=1。生成 16-byte salt、随机 32-byte private exponent，按固定 username/password 计算 SRP verifier，回 M2：state=2、server public B（384-byte big-endian padded）、salt。
2. **M3 请求**：state=3，要求 A (`public key`, TLV type 3) 和 client proof (`proof`, TLV type 4)。缺任一字段、会话无 SRP 状态、`A mod N == 0` 或 proof 不符：回 error TLV（state 与 error type 7，项目 error value=2）。
3. **M4 响应**：校验成功后回 state=4 和 server proof。
4. **M5 请求**：state=5，encrypted data TLV type 5；使用 `HKDF-SHA512(K, Pair-Setup-Encrypt-Salt, Pair-Setup-Encrypt-Info)` 派生 key，ChaCha20-Poly1305 nonce label `PS-Msg05` 解密 inner TLV，要求 identifier、Ed25519 public key、signature，验证 controller 长期公钥绑定的签名。
5. **M6 响应**：保存已验证 controller pairing key；用独立 HKDF `Pair-Setup-Accessory-Sign-*` 生成 accessory signature，ChaCha seal `PS-Msg06`，回 state=6 + encrypted data。
6. 未知 state 或捕获到异常：当前实现回 error TLV；不能将失败吞掉后再把配对标为 complete。

SRP 源码常量/公式摘要：`N` 为 RFC 5054 3072-bit prime（384 bytes），`g=5`，hash 为 SHA-512；`k=H(N || PAD(g))`，`x=H(salt || H(username || ':' || password))`，`u=H(PAD(A) || PAD(B))`，server secret `S=(A * v^u mod N)^b mod N`，session key `K=H(S)`。proof 检查包含 `(H(N) XOR H(g)) || H(I) || salt || PAD(A) || PAD(B) || K`；server proof 为 `H(PAD(A) || clientProof || K)`。大整数正数按 big-endian 解释，A/B 按 384-byte 左侧零填充。代码只实现这一份变体的序列化与哈希公式，不能仅因名字 SRP-6a 就假定跟其他库逐字节互通。

证据：[PairSetup state/加密身份交换](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/PairSetup.kt#L15-L129)、[SRP 参数与 PAD](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/Srp6a.kt#L10-L67)、[SRP proof 计算](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/Srp6a.kt#L95-L110)。PairSetup 源码在此项目中确实使用固定测试 setup code；不能将此固定值视为量产密码策略或 Apple 要求。

### 3.3 Pair-Verify：临时密钥、签名、control keys

Pair-Verify state=1 请求应有 client ephemeral X25519 public key；响应 state=2、公钥和密封数据。Responder 算 X25519 shared secret；HKDF-SHA512（`Pair-Verify-Encrypt-*`）派生临时加密 key；在 `PV-Msg02` nonce 下封装 accessory identifier 与 Ed25519 签名。state=3 请求包含以 `PV-Msg03` 解封的 identifier/signature；用此前 Pair-Setup 保存的 controller long-term public key 验签。controller 未找到、字段缺失、tag/signature 失败均回 error，不设置 verified。成功后按 `Control-Salt` 与 `Control-Read-Encryption-Key`/`Control-Write-Encryption-Key` 分别派生双向 control key。

随后 control frame 为 `[u16 LE 密文长度][ciphertext][16-byte Poly1305 tag]`；长度 2 bytes 是 AEAD AAD，两个方向各自维护 key 与 nonce counter，DiPlay 每 frame counter +1，最大 plaintext chunk 0x4000。Pair-Verify 切换后首次控制写入会启用 cipher；不可在双方未同步 counter/key 的情况下重用 frame 或混合明文/密文。

证据：[PairVerify M2/M4](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/PairVerify.kt#L24-L120)、[控制帧加密](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/ControlCipher.kt#L1-L55)、[Crypto primitives/HKDF](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlayCrypto.kt#L42-L160)。

### 3.4 `/auth-setup` MFiSAP：请求/响应布局与摘要分支

DiPlay 所实现 MFI 请求严格检查 `[version=0x01][32-byte controller X25519 public key]`，长度不是 33 或 version 不匹配则拒绝。双方算 X25519 shared secret；全零 shared secret 拒绝。`SHA1("AES-KEY" || shared)` 取前 16 bytes 作 AES key，`SHA1("AES-IV" || shared)` 取 16 bytes 作 IV，使用 AES-128-CTR 加密 coprocessor challenge signature。MFI certificate 分支 response 为：`[32-byte accessory ephemeral public key][u32 length][certificate][u32 length][encrypted signature]`（该实现的 u32 写入格式见 helper）。

MFI 分支的签名摘要根据 `MfiAuthenticator.protocolMajor()`：2 → SHA-1(`accessory public || controller public`)，否则 SHA-256(相同拼接)。这属于 DiPlay 此 provider 的条件选择；不是 `X-Apple-HKP` 头自动协商。BAA 分支的 response 另含 leaf certificate、签名和 OPACK `baIC` 中间证书 blob，不能套用 MFI 两长度字段格式。畸形请求返回 null，由 session 返回 400；provider 的签名和证书仍须由手机端真正验证。

证据：[版本、X25519、摘要选择和 response 布局](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/MfiSapAuthSetup.kt#L16-L109)、[RTSP handler/content type](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L568-L584)。

### 3.5 认证失败处理检查清单

| 检查点 | Accessory/server 接收手机请求 | Sender/phone 接收 server 响应 |
|---|---|---|
| TLV / binary framing | 检查长度、必需字段、state 是否可在当前会话出现；拒绝重复/超长值按 parser 策略处理 | 检查响应 Content-Type、状态、TLV state、error、字段长度 |
| 密码学 | 验 `A` 非零 mod N、SRP proof；验证 Ed25519；拒绝 AEAD tag/证书失败 | 验 server proof、controller/accessory 身份链、签名和 MFi 证书 |
| 状态绑定 | session key、临时 X25519、stream、身份材料仅限当前 control session | response 不能脱离发起请求/会话复用；控制密钥不能跨方向/会话混用 |
| 结果 | 错误 state/error 或 4xx/关闭；不返回认证成功、不开放受限后续通道 | 停止后续 SETUP/RECORD 或仅按明确 profile 回退；记录非敏感诊断 |
| 日志 | 不写 password、私钥、session secret、完整认证 payload | 不写配对密钥、MFi 私有材料或可重放响应体 |

## 4. RTSP 请求行、header 与 body 对照

### 4.1 通用 framing

DiPlay parser 把请求行拆为 `method path protocol`，header 名称 lowercase，`Content-Length` 决定 body byte 数，未提供长度则视为 0；设置了 16 KiB header、1 MiB body 上限。响应拷贝请求协议和 `CSeq`，始终写 `Content-Length`。这属于所读实现行为，不保证所有发送端对空 body、版本文本或响应 header 处理相同。

| 请求/路径 | body / Content-Type | 主要 headers | DiPlay 服务端动作 | 客户端要核对 |
|---|---|---|---|---|
| `POST /pair-setup` | TLV8；响应 `application/pairing+tlv8` | `CSeq`；实现可能不要求 `X-Apple-HKP` | PairSetup 状态机、SRP、持久化 pairing key | HTTP/RTSP status、TLV state/error、SRP proof；不能把 `X-Apple-HKP` 当算法版本 |
| `POST /pair-verify` | TLV8；响应 pairing+tlv8 | `CSeq`；配置/版本分支可能不同 | 已保存 pairing key 验签，创建控制加密 keys | Pair-Verify 成功后才切换密文，双方按准确方向同步 counter |
| `POST /auth-setup` | binary；响应 `application/octet-stream` | `CSeq` 和当前加密状态 | MFiSAP 或配置认证 provider；格式错误 400 | 检查 response 结构、证书链和 challenge 签名 |
| `GET/POST /info` | GET 可无 body；POST 常见 bplist request；响应 binary plist | `CSeq` | 返回 features/displays/audio formats/latencies 等本端声明 | 取能力交集；feature 宣告不是运行时 stream 已建立 |
| `SETUP` 初始 | bplist device metadata/timingPort/features | `CSeq`、body 长度 | 返回 event/timing/可选 keepAlive ports | 实际绑定地址/端口、event socket 是否连通 |
| `SETUP` streams | bplist `streams[]`；响应每条已接受流的 dataPort/type/IDs | `CSeq`、body 长度 | 为每个受支持流实际创建 TCP/UDP endpoint | 每条流响应、dataPort、codec/UUID/connection ID 与数据面必须一致 |
| `RECORD` | 通常空 body | `CSeq` | DiPlay 标记 session active | 不等于每路视频/音频都成功收到数据；在项目中先后顺序可不同 |
| `TEARDOWN` | 可带 stream 类型 plist | `CSeq` | 释放局部 stream 或全部 session | 部分 teardown 不应无条件关闭其余并行流 |
| `POST /command` | binary plist `{type, params}`；可能有 `X-Apple-StreamID` | `CSeq`、可选 `X-Apple-StreamID` | 派发字符串命令/remote-control body | 解析 `type` 字符串与 params，而非将其强转 iAP2 ID |
| `POST /feedback` | binary plist 可选 | `CSeq` | 返回媒体 feedback 或空 200 | 应依 stream state/feedback 信息处置 |
| buffered audio (`SETRATE`, `SETRATEANCHORTIME`, `GETANCHOR`, `FLUSHBUFFERED`) | 二进制 plist 或特定 GETANCHOR 空请求 | `CSeq` | 只有配置启用才交 buffered handler | 不能把 type 103 当普通视频 URL 或任意 audio RTP |

`Content-Type` 在所读 DiPlay 代码里分别定义为 binary plist `application/x-apple-binary-plist`、pairing `application/pairing+tlv8` 和 binary `application/octet-stream`。CatPlay/CarDeck/carlife sender 对 `Content-Length`、空 body 和首个 CSeq 的实现并不完全一致；主报告已举例说明。RTSP 风格控制请求不要不加区分地叫作 HTTP/1.1。

证据：[RTSP parser/response framing](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/RtspMessage.kt#L18-L106)、[路由和 Content-Type](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L535-L623)、[SETUP 初始与 streams](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L648-L715)、[X-Apple-StreamID](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L748-L777)。

### 4.2 Header 注意事项

- `CSeq` 是 RTSP 请求/响应匹配序列，不是 stream ID、iAP2 packet 序号或音频 RTP sequence。响应应 echo 本次请求的值。
- `Content-Length` 是 body 的字节长度，不含 request line/headers，也不是 plist 对象个数。以字节而非字符计算。
- `Content-Type` 随 body 编码变化；TLV8、binary plist、raw binary 不能用同一个 decoder。
- `X-Apple-HKP: 2` / `3`（在一些项目请求 builder 里出现）只记录某个实现放出的 header 值。它不等于 `SRP-6a` 版本、MFi protocol major、iOS version 或完整密码 suite 选择；不能据它单独切算法。
- `X-Apple-StreamID` 是 `/command` 上用于远程控制消息的 stream 标识，在 DiPlay handler 中与 `params.data` 同时出现才进入 remote control 分支；不是 `streamConnectionID`，也不是 130 tunnel 的 port。
- 一些 sender 空 body 请求省略 Content-Length，另一些明确带 `Content-Length: 0`；接收 parser 应按 body 长度稳健处理，不能假定所有实现完全统一。

## 5. 视频/音频/数据流：编号、SETUP 参数与 wire 格式

### 5.1 Stream type 与用途

| Stream type | 项目中的通常用途 | 相关参数/承载 | 不要误解为 |
|---:|---|---|---|
| 96 | GeneralAudio（旧式/兼容音频） | legacy audio description 可能有 `ct`, `spf`, `latency_min/max`, `sr`, `control_port`, `audio_format` | 96 是 codec ID |
| 100 | MainAudio，含媒体、电话、语音识别等用途 | `audioType` 区分 default/alert/media/telephony/speechRecognition/compatibility；UDP data/control ports | 只有音乐播放 |
| 101 | AltAudio | 独立的音频资源/流用途 | alternate screen |
| 102 | MainHighAudio | 高规格/特定 profile 音频 | 一定在所有设备出现 |
| 103 | BufferedAudio（可选） | buffered control verbs + 专用 SETUP/控制 handler | video stream 或普通 RTP 即时流 |
| 104/105 | Main/Alt Audio with redundancy（目录/较新能力声明） | 需对应 profile 和冗余能力 | CatPlay 注释掉的定义等于已经支持 |
| 106–109 | AuxOut/AuxIn audio 及 redundancy 变体 | 具体方向与 codec profile 要由协商决定 | 仅凭编号就可以推定输入输出方向 |
| 110 | Screen / 主 CarPlay 显示 | TCP dataPort，video header + codec config/frame；常带 display UUID 和 streamConnectionID | Dock 或 Dashboard 各自一条流 |
| 111 | AltScreen / 第二显示（常为仪表/cluster） | 独立 UUID、SETUP 和 TCP dataPort；其 UI 内容可经 showUI URL 变更 | 每次地图/转向卡变更都新建流 |
| 130 | Data stream（iAP relay、video settings 等取决于 UUID/profile） | TCP dataPort，独立连接 ID/UUID 和 DataStream key | 所有 CarPlay 控制都走同一个无区别 tunnel |

CatPlay 当前 `StreamType` 可见 Invalid=0、96、100–102、110；代码把 103/104–109/111 的声明保留为注释，因此只能说明源码注释有这些符号，不可声称该 crate 已支持。DiPlay handler 中可以看到 100/110/111/130 的分派；type 103 需另按 buffered 功能配置。`type`、`audioType`、`audioFormat` 是三个不同字段。

### 5.2 SETUP 请求与响应字段

**Screen description**：`type`, `streamConnectionID`，通常 `uuid`、`latencyMs`；响应中 `dataPort`, `type`, `streamConnectionID`，可能包含 timestamp/sample time。主/副屏必须按不同 UUID 与业务流处理。

**Audio description**：至少核验 `type`, `streamConnectionID`, `audioFormat` (bitmask), `audioType`, `audioLatencyMs`；可选 `audioLoopback`, `dataPort`, `controlPort`, `input`, `spf`, `vocoderInfo`，较新能力可能带 `supportsRTPPacketRedundancy`、`supportsHighAccuracyTimestamps`。响应包含已绑定 `dataPort`, `type`, connection ID 和有的 profile 的 controlPort/时间戳能力。不要把请求端希望的 remote port 与服务端本地 bind 的 port 混淆。

CatPlay schema 直接保留上述 modern fields，并有 Legacy audio 描述映射。其 legacy adaptor 会把最小 latency clamp 到 250 ms；这是该实现兼容策略，不是 Apple 对每条 CarPlay 流的固定值。

证据：[CatPlay Audio/Screen SETUP schema](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/msg/stream_desc.rs#L1-L128)、[响应及构造器](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/msg/stream_desc.rs#L130-L215)、[CatPlay stream type 与 audio format](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/msg/streams.rs#L1-L150)。

### 5.3 AudioFormat 位掩码与真实支持差异

CatPlay 定义的 `AudioFormat` 为 `u128` bitflags（第 n 位是 `1 << n`），不是 codec 数字枚举。源码可见：bit 2–17 为不同 PCM rate/bit-depth/channel；18–21 为 ALAC 44.1/48 kHz 16/24 bit stereo；22–23 为 AAC-LC 44.1/48 kHz stereo；24–27 与 31–32、43 等为 AAC-ELD 多采样/声道选项；28–30 为 Opus 16/24/48 kHz mono；其后还有多声道 PCM、AAC、DDPLUS、QAAC/QAACHE、QLAC、QC3、APAC 等名目及 reserved/unknown bit。完整名称和 bit index 直接见 [`streams.rs`](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/msg/streams.rs#L25-L190)，不要把实现声称能 encode/decode 的 codec 范围扩大到 enum 列举范围。

DiPlay 实际 `AudioStreamCodec` 映射仅处理部分 PCM bits、AAC-LC stereo 44.1/48 kHz、Opus mono bits；未识别值回退到 LPCM 44.1 kHz stereo。此 fallback 是代码行为，不代表该格式与对端兼容。`audioType` 再区分用途；DiPlay 里 `telephony` 与 `speechrecognition` 可触发 mic path，但 codec/端口/`input` 仍要同时满足。

媒体 UDP data packet（DiPlay 实现）：`12-byte clear RTP header || ciphertext || 16-byte AEAD tag || 8-byte LE nonce counter`。解密 AAD 为 RTP header bytes 4..11（timestamp + SSRC），RTP header 中 sequence/timestamp 仍能被观测。每一条流的 key、sequence、timestamp、nonce 都应独立维护。DiPlay control UDP socket 当前主要收包；不得用这一实现推断所有 RTCP feedback/retransmission 已完整覆盖。

### 5.4 视频 TCP：header、opcode 与帧体

DiPlay 屏幕实现读取固定 128-byte header，之后读取 header offset 0 的 `u32 LE body size` 个字节。opcode 位于 header offset 4；发送端时间字段位于 bytes 8..15（该实现按 little-endian NTP 32.32 转换）。header 总长 128 bytes 全部作为每帧 ChaCha20-Poly1305 AEAD associated data。

| Opcode | 作用 | 处理 |
|---:|---|---|
| `0` | VideoFrame | frame body = 密文 + 16-byte tag；nonce 为 `[00000000 || u64 LE frame counter]`，按会话/视频连接 counter 解密。明文 NALU 为 4-byte big-endian length-prefixed；校验所有 NALU 长度后转 Annex-B start code，交解码器 |
| `1` | VideoConfig | config body 在此实现中明文，提取 `avcC` → H.264 或 `hvcC` → H.265 初始化 decoder；不增加 frame counter |

配置帧缺少有效 record 时此源码有 fallback 判断，但不能据此假设所有未知 codec 都能解码。接收器限制 body 最大 8 MiB 并校验来源 peer。屏幕 stream 的主屏与副屏要分别处理；媒体帧不经过 RTSP `/command` plist 解码。

证据：[TCP packet reader、长度及 opcode dispatch](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/ScreenStream.kt#L15-L145)、[NTP 32.32 和 config/AVCC/Annex-B](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/ScreenStream.kt#L148-L220)、[ChaCha/HKDF primitives](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlayCrypto.kt#L140-L220)。

### 5.5 麦克风上行（accessory → phone）与音频下行不可混淆

语音识别/电话麦克风是从车机侧送回手机侧的数据路径。DiPlay 从 audio SETUP 判断 `audioType`、`input`/输入端口、`dataPort`、stream connection ID；mic key 用 `DataStream-Input-Encryption-Key` label 派生，与音频下行 `DataStream-Output-Encryption-Key` 不同。该实现的 PCM packetizer 输出 12-byte RTP header、加密 payload/tag、8-byte LE nonce；AAD 是 RTP header bytes 4..11，sequence/timestamp/nonce 独立递增。Android 捕获的 PCM little-endian 样本转成该 wire path 使用的 big-endian 顺序。

Opus 输入采集/编码率和 RTP timestamp clock 并非必然相同：DiPlay 按协商 bit 选择 16/24/48 kHz RTP clock；配置了 packet frames 时依样本率推导周期，无值则根据 MTU 选可装入数据报的 PCM packet 时长。车机必须同时拥有麦克风采集权限、codec、目的地址/port、正确 Input key 和有效 RTP 计数器。只看到 `RECORD_AUDIO` 权限、audio `input=true` 或成功 SETUP，不足以证明麦克风上行可用。

证据：[麦克风选择及 Input key](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/CarPlayMediaEngine.kt#L620-L719)、[mic RTP packetizer](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/MicrophonePacketizer.kt#L10-L126)、[Opus clock/frame 配置](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/MicrophonePacketizer.kt#L12-L91)。

## 6. 130 数据流与“视频通道”辨析

`type=130` 是 DataStream stream type，业务由 UUID / streamConnectionID /配置决定。两个 DiPlay 分支展示不同用途：

- iAP tunnel：TCP listener → DataStream output-key 解密 frame → APTransportPackage；只把 `messageType=comm` 的 iAP payload relay 出去。本类为 receive-only；不证明所有 iAP endpoint 双向透传都完成。
- Video Settings App channel：同为 130，但使用 VideoInCar settings UUID；加密载荷是 32-byte package header + command/body。项目见到 `sync` 时用 `rply` 空 reply 保持 channel；其 body 不是视频帧。
- 视频播放 URL / remote-control message 与 130 settings data stream 亦非同一对象。播放策略、车辆行驶限制、DRM/FairPlay 不在公开源码观察范围内，不推导绕过行为。

证据：[DataStream receive/tunnel](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/IapTunnel.kt#L1-L24)、[APTransportPackage parsing](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/IapTunnel.kt#L145-L210)、[Video Settings channel framing](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/VideoSettingsChannel.kt#L1-L105)。

## 7. 整体接收端执行顺序（参考实现，不是强制时序）

1. 初始化 USB NCM 或 Wi-Fi/P2P/Bonjour 网络；建立 iAP2/Lockdown 与 AirPlay 服务端点；确认真实 bind/peer 身份。
2. RTSP 连接收到 pair-setup / pair-verify / auth-setup 时，按 path、Content-Type、请求 body 与状态机分别处理；不要把三种认证压成一个 flag。
3. 认证完成后按各方向独立初始化 control cipher；处理 `/info` 能力 request/response，能力宣告中仅保留可实现的交集。
4. 初始 SETUP 建立 timing/event/keepalive；每一条 `streams[]` 另行验证并绑定实际 data socket，再回应实际 dataPort。
5. RECORD、音视频 `SETUP` 和数据 socket 建立顺序可能交错或因发送端 profile 不同而不同；用本会话状态关联 stream ID/UUID，不编码单一固定序列。
6. 数据面分别执行视频 TCP、音频 RTP/RTCP UDP、麦克风上行、130 DataStream 解密与子协议 parsing；Control `/command`、event/HID、resource modes 分流处理。
7. TEARDOWN 按指定 stream scope 释放资源；完整关闭时清理 event、timing、keepalive、cipher counter、socket、媒体和 iAP tunnel，避免因单流停止误断其它流。

这是一套从本地代码归纳的稳健处理策略，不是完整 Apple 规范。遇到未知 type、codec、endpoint、状态或数据格式，服务端应拒绝/保留兼容边界，手机/发送端应停止依赖该通道并报告明确错误；不应回假端口、伪造成功状态、忽略 AEAD 错误后继续解码。

## 8. 覆盖边界与核验记录

- iAP2 catalog 有 151 个 endpoint 声明；字典提取校验：61 个具名、90 个内联、151 个唯一 ID、59 个顶层 typed fields、97 个递归 field path。空 schema 表示 catalog 未细化，不代表 wire body 一定为空。
- 已将编号、请求头、配对算法、stream schema 与实际数据 framing 分开；摘要、bitmask 与 handler 仍需依具体源码版本核查。
- 没有将 Apple 原生 iOS sender 源码、MFi 受限规范或真实抓包当作已得证据；未执行 Android/Rust build、密码学互通测试、单测或实车连接。
- 当前静态校验覆盖主报告、本文、endpoint 字典和概览文档的本地链接/行号，并检查握手 fixture 的既有请求顺序与仓库 HEAD 记录；endpoint CSV 行数为 151。它们只证明检出代码/文本记录的内部一致性，不是运行时协议或互通测试。
