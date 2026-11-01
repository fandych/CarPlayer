# CarPlay 发送端与 USB / 无线协议深度分析

> 日期：2026-10-31。范围：已下载的公开源码及仓库握手记录。本文以 CatPlay 发送侧/双角色适配器为分析主线，DiPlay、CarDeck 和握手记录用作对照；本文是源码导读与协议交互重建，**不是 Apple 完整、正式或跨版本通用的 CarPlay 协议规范**。未进行实车连接、网络抓包、固件刷写或 Android/Rust 工程构建。不得据此声称已通过 MFi 认证或量产兼容验证。
>
> 配套阅读：[CarPlay 功能与通道分析](CarPlay功能与通道分析.md)、[控制码/认证/媒体格式详解](CarPlay控制码认证与媒体格式详解.md)、[iAP2 endpoint 全量字典](CarPlay-iAP2控制码字典.md)（[CSV](CarPlay-iAP2-endpoints.csv)）。Apple 公共配件指南不包含完整 CarPlay 协议；MFi 受限规范、Apple iOS 原生源码及未捕获的分支，不在本次可证实范围内。

## 1. 成功条件与证据等级

**本文阅读标记：**【CatPlay源码事实】仅表示检出版本中的实现；【与其他公开实现的差异】表示相对 DiPlay、CarDeck 或仓库握手记录观察到的路径/能力差异；【协议规范未证实】表示没有足够的 Apple 公开规范证据判定为标准差异。本文所说“CatPlay 差异”不等同于“CatPlay 违反 CarPlay 协议”。

本次工作按以下条件验收：

1. 下载并记录真正的发送端候选，区分发送端、接收端、盒子客户端和 CarLife。
2. 给出 USB 与无线建立过程、请求方向、协议层、关键字段及源码入口。
3. 把媒体协商、控制、视频、音频、麦克风和 iAP 数据从基础链路中拆开。
4. 每个关键结论能定位到源码或仓库记录；文档引用文件存在，行号不超出检出文件。
5. 用现有双屏握手记录检查实际交互顺序，尤其避免把 RECORD、仪表首帧和第二轮认证写成一个固定串行流程。

证据分三级：**S=源码直接证据；F=仓库提供的握手/测试记录；D=作者文档声明**。三者均不等于本次已实车复现。本文伪代码是对逻辑的原创概括，不是复制 Apple SDK 源码。

## 2. 发送端究竟是谁？

### 2.1 角色与方向

```text
普通接收器：
  iPhone（Apple 原生发送端，源码未公开）
      ⇄ USB 或无线网络
  DiPlay / xcertplay / LIVI（车机接收端）

Android 实验发送器：
  CarDeck / carlife-to-carplay（模拟手机角色）
      ⇄ 蓝牙引导 + Wi-Fi
  原车 CarPlay 接收器

无线转有线适配器：
  iPhone ⇄ Wi-Fi ⇄ CatPlay 接收侧
                        │ 桥接、转码/封装、控制代理
                    CatPlay 发送侧 ⇄ USB ⇄ 原车接收器
```

**socket client/server 与 CarPlay transmitter/receiver 不是同一个概念。** 手机角色也会监听邀请或蓝牙回连；车机角色也会主动发 RFCOMM 连接、输入和启动消息。iAP2 中名为 `Client` 的类不一定是手机发送端。接收器发出触摸、车辆数据，也不意味着其整体角色变成视频发送端。

### 2.2 本次新增下载及核验

都保存于 `GitHub-CarPlay-Projects`，浅克隆，不运行仓库脚本、不初始化子模块。

| 项目 | 检出 HEAD | 真实定位与边界 |
|---|---|---|
| [CarDeck](https://github.com/shaonialife/cardeck) | `503ed3730d5a9365272294b79306cea5fcce115b` | Android 无线 CarPlay 发送实验；有编码、网络、输入处理；无 USB/NCM 发送路径，认证验收存在明确省略 |
| [carlife-to-carplay](https://github.com/LSJKC/carlife-to-carplay) | `462907843a9fc071f9ba9b42a85ca3eee646e37f` | Android 手机角色发送候选；源码有 PhoneBluetooth 和 AirPlaySender，须区分 CarLife 输入适配与真正 CarPlay 输出 |
| [carlife-unified](https://github.com/My-Dev-sketch/carlife-unified) | `882c569b17c644ad4150f82efb0eb6e1013ca8ca` | 主要是 Baidu CarLife 协议及 CarPlay 风格界面；**不是证明 Apple CarPlay 发送协议的依据** |
| [CatPlay](https://github.com/catplay-labs/catplay)（此前已下载） | `fc52bac7910a07ff3b6d94712175db6013528aa9` | 有 transmitter/receiver 双角色，适配器面向车机的一侧可用于研究 USB 发送与媒体代理；不等同于 iOS 原生源码 |

没有找到可据以声称“Apple iPhone 完整原生 CarPlay 发送栈已开源”的材料。新增检索匹配以源码核验为准，不以仓库简介中的 complete、100% 或 CarPlay-style 判断互通能力。

## 3. 协议栈：不要把各层混为一谈

| 层级 | USB 分支 | 无线分支 | 功能 |
|---|---|---|---|
| 接口与网络建立 | USB 枚举、配置、bulk；CDC NCM | 蓝牙 BR/EDR RFCOMM；Wi-Fi AP / P2P 创建网络 | 获得可用字节流或 IP 连接 |
| 设备控制引导 | 项目中的 USBMUX、Lockdown、CarKit；随后 iAP2 | RFCOMM 内 iAP2 | 识别、认证、交换会话参数 |
| 数据网络 | NCM NTB → Ethernet → IPv6/TCP/UDP | Wi-Fi 接口上的 IP/TCP/UDP | 承载控制及媒体 |
| 发现与邀请 | 可有 Bonjour 和 ctrl 邀请；CatPlay 发送侧可走这一支 | Bonjour/mDNS、ctrl 邀请，或已交付端点 | 确认接收端和启动时机 |
| 会话 | HTTP/RTSP 风格请求；plist、TLV8 | 同类控制协议 | 配对、/info、SETUP、RECORD、资源控制 |
| 媒体 | 视频 TCP、实时音频 UDP 等项目路径 | 同上，但受无线网络状态影响 | 视频、音频、麦克风 |
| 运行期控制/数据 | 既有 iAP2 或具体实现的其他路径 | 可选 Wi-Fi iAP tunnel/命令携带 | HID、导航、位置、车辆数据 |

这是一组项目支持的路径，不是要求所有车都使用每一层。**P2P 是网络创建方式，iAP2 是配件协议，AirPlay 是会话/媒体体系**，三者可以串联但不是互斥的同一层协议。

### 3.1 CatPlay 实现与通用 CarPlay 说法的差异边界

Apple 的完整 CarPlay 线协议规范未公开在本次证据范围内，因此下表将“源码明确的 CatPlay 行为”与“是否偏离 Apple 规范”分开：

| 项目 | CatPlay 检出源码中的行为 | 应如何理解，而不要误写成 |
|---|---|---|
| USB 设备角色 | 使用 Linux 定制 PhoneGadget/UDC 与 role-switch 驱动，模拟手机角色接原车；这不同于 DiPlay 的 USB host 接真实 iPhone。 | 这是设备/驱动实现差异，不足以证明 iAP2 或 AirPlay 线上协议不同；也不能假设普通 Android USB API 可替代。见 §4.6。 |
| iAP2 MFi 认证验收 | phone-role CSM 收证书后发固定 20 字节测试 challenge；收到 AuthenticationResponse 后直接发 AuthenticationSucceeded，未见这里验证证书、challenge 签名或绑定身份。 | 明确是 CatPlay 当前代码的测试/不完整验收行为，不代表 Apple 手机的真实认证算法或 CarPlay 的认证规则。源码：[CatPlay phone-role CSM](GitHub-CarPlay-Projects/catplay/catplay_carplay_tx_gadget/src/carplay_client_session.rs#L719-L739)。 |
| AirPlay 配对顺序 | 当前 `Connected` 事件先启动初始 SETUP；SETUP 失败时才触发配对升级；`/auth-setup` 与直接启动配对的调用在该分支被注释。 | 与 DiPlay、握手记录等其他路径存在启动顺序差异；这是当前 CatPlay 兼容策略，不代表所有 CarPlay 设备都按此顺序或允许未加密 SETUP。见 §7.4。 |
| `/info` 版本字段 | CatPlay schema 有可选 `protocolVersion`（源码注释为 `1.0`），另有 `sourceVersion`（SDK version）及 `OSInfo`。 | 这是 CatPlay `/info` schema 的字段，不等于 CarPlay 全局协商版本号；`RTSP/1.0` 也只是控制报文语法标记。源码：[InfoMessageResponse](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/msg/info.rs#L65-L73)。 |
| 流类型/能力 | CatPlay 活跃枚举含 96、100–102、110；103、111、部分辅助/冗余流在“Modern CarPlay”注释块中未启用。 | 表示所查版本实现/声明的能力子集，不证明这些流类型不属于 CarPlay 体系，也不证明 CatPlay 完成副屏、缓冲音频或现代扩展。源码：[StreamType](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/msg/streams.rs#L3-L25)。 |
| event 命令集合 | CatPlay `CommandType` 当前只解析列出的命令；未知名字返回 `UnknownCommand`，event server 对其回 `501 Not Implemented`。 | 是命令覆盖度差异，不是另一套通用命令码表；不能把未实现的命令解读为车机不会发送。源码：[命令枚举/解析](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/msg/commands/command_types.rs#L10-L35)、[未知命令响应](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/events/events_server.rs#L72-L78)。 |
| 屏幕帧格式 | CatPlay 与 DiPlay 所查实现都使用 128-byte `ScreenFrameHeader`，小端 body length 和 opcode。 | 此处没有观察到两者格式差异；但“两个开源项目一致”仍不等于 Apple 规范已完整确认。源码：[CatPlay ScreenFrameHeader](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/screen/screen_frame.rs#L98-L149)。 |
| 双角色适配 | CatPlay 适配器把接收侧内容转成内部 ScreenChannel/Modes/Command/SetupAudio，再面向另一端重新 SETUP、代理媒体。 | 是代理/转换后的两段会话，不是手机与车机间对每个字节、端口、密钥和资源状态都透明的直通链路。见 §10。 |

**结论用语：**能由源码确认的是“CatPlay 当前实现与某个公开实现/抓包记录不同”或“CatPlay 当前能力有限”；没有 Apple 规范或足够互操作证据时，不写成“CatPlay 协议与 CarPlay 不兼容/违反标准”。

## 4. USB：从插线到会话启动（CatPlay 发送侧为主，DiPlay 作反向对照）

**阅读顺序提示：**本章主角是 CatPlay 的手机角色 USB gadget；其端到端状态流见 §4.6。§4.1–4.5 展示的是 DiPlay 作为 USB host 连接真实 iPhone 的反向接收流程，只用于对照层次与报文，不是 CatPlay 的实际启动顺序，不能把两条流程拼成一套。

主入口：[CarPlayController.runStack，2244–2478 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/orchestration/CarPlayController.kt#L2244-L2478)。这是 DiPlay 作为 USB host 与 iPhone 交互的路径；不能照抄为 CarDeck 的 USB 实现，因为后者没有该路径。

### 4.1 USB 发现、模式切换及接口认领

| 步骤 | 发起方 → 对端 | 协议/动作 | 结果及下一步 |
|---|---|---|---|
| U1 | 系统 → DiPlay | USB attach；筛选配置允许的 Apple VID/PID；申请 Android USB 权限 | 权限拒绝或设备不存在则不能进入协议 |
| U2 | DiPlay → iPhone | 项目使用 vendor IN 请求：`bmRequestType=0xC0`、`bRequest=0x52`、value 0、index 4 | 可能触发重新枚举；不是所有设备都必须再次执行 |
| U3 | iPhone → 系统 | USB detach/attach 或返回新配置 | 必须重新打开新设备对象，旧连接不能继续用 |
| U4 | DiPlay → iPhone | 找到 CarPlay/USBMUX 配置，setConfiguration，claim interface，选择 bulk 端点 | 按实际描述符发现；历史值配置 6、bulk 0x04/0x85 不应硬当所有手机标准 |
| U5 | DiPlay → iPhone | 发现并打开 CDC NCM 控制/数据接口 | 创建独立网络通道，不是把显示帧直接写进任意 USB 端点 |

证据：[IphoneUsbHost，169–285 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/IphoneUsbHost.kt#L169-L285)，[请求常量，408–414 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/IphoneUsbHost.kt#L408-L414)，[NcmUsbBridge.open，444–505 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/NcmUsbBridge.kt#L444-L505)。USB 的总线枚举和底层 token/handshake 由操作系统 USB host controller 完成，Java 源码并不逐包实现这些硬件事务。

### 4.2 USBMUX：先建立服务字节通道

DiPlay 的 USBMUX host 先发送版本消息，等待版本响应，再以复用的 TCP 风格包建立逻辑连接。源码中 `USBMUX_VERSION=2`，Lockdown 端口为 62078。

```text
DiPlay                                  iPhone
   ─── USBMUX version request ───────────►
   ◄── USBMUX version response ───────────
   ─── logical TCP SYN (dst 62078) ──────►
   ◄── SYN+ACK ───────────────────────────
   ─── ACK ─────────────────────────────►
   ⇄   Lockdown plist messages
```

这里的 TCP 风格流封装在 USBMUX 中，**不等同于 NCM 网卡上的普通 IP/TCP 连接**。版本交换、连接和读线程证据：[Iap2UsbMuxHost，38–148 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2UsbMuxHost.kt#L38-L148)，[SYN/ACK 状态，430–520 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2UsbMuxHost.kt#L430-L520)。

### 4.3 Lockdown 配对、TLS、CarKit 服务

1. 有保存配对记录则尝试复用；没有则新建。
2. `LockdownPairingClient` 读取设备信息/公钥等，生成配对记录并发 `Pair`；等待用户信任或处理错误。源码也有可选 `SetValue` 设置，不应写成每次必须发生的固定包。
3. 连接 Lockdown，发 `StartSession`，携带 `HostID`、`SystemBUID` 等。
4. 响应要求 `EnableSessionSSL=true`，然后在该逻辑服务流内进行 TLS 握手。
5. 在加密的 Lockdown 流内发 `StartService(Service=com.apple.carkit.service)`。
6. 响应提供实际 `Port` 和可选 `EnableServiceSSL`；重新通过 USBMUX 连接该端口，必要时再次 TLS。
7. 保持创建服务的 Lockdown 会话存活，交给 iAP2 链路处理。
8. 若旧配对记录被明确拒绝，清除并重新配对，而不是继续用失效凭据。

证据：[LockdownPairingClient，27–180 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/LockdownPairingClient.kt#L27-L180)，[LockdownCarKitClient，24–108 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/LockdownCarKitClient.kt#L24-L108)。用户信任配对、MFi 配件认证和 AirPlay 长期身份配对是**三个不同层次的状态**。

### 4.4 iAP2 链路与配件控制

CarKit 提供字节流之后，再启动 iAP2 detection/SYN/ACK、CSM 识别及认证。接收侧等待手机 `StartIdentification`，交互见第 6 节。

`Iap2WiredControlClient.run` 的顺序是：

```text
identify()
  → mfi.run()
  → powerSourceUpdate()
  → update subscriptions
  → 等待 0x4300 CarPlayAvailability
  → 发送 0x4301 CarPlayStartSession
  → 持续接收导航/位置/车辆状态请求
```

`0x4301` 携带有线 IPv6 地址、AirPlay 接收端实际端口、身份公钥、版本等；它**并不自己打开媒体 socket**。网络 listener 要先可用，手机收到端点后才能主动建立 AirPlay 控制连接。证据：[Iap2WiredControlClient，23–130 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2WiredControlClient.kt#L23-L130)，[构建端点消息，173–185 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2WiredControlClient.kt#L173-L185)。

### 4.5 NCM 如何承载媒体

```text
AirPlay/RTSP TCP 或音频 UDP
     ↕ IPv6 packet
Android VPN/TUN（项目适配，不是 CarPlay 必须要求 VPN）
     ↕ Ethernet II frame
CDC NCM NTB / Datagram
     ↕ USB bulk
iPhone 网络接口
```

`NcmUsbBridge` 负责 NTB 数据块的读写、分段/聚合及 bulk 收发；`Ipv6NcmBridge` 去除/恢复 Ethernet 头，把 IPv6 包接到 TUN，处理邻居链路层地址相关适配。不能把 NCM NTB、iAP2 CSM 和 H.264 NAL 当成同一种帧。

证据：[NcmUsbBridge](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/NcmUsbBridge.kt#L59-L90)，[Ipv6NcmBridge，16–132 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/network/Ipv6NcmBridge.kt#L16-L132)。网络桥接和服务线程可能并行启动；`runStack` 的函数顺序不能证明线路上每个包严格串行。

### 4.6 真正的 USB 发送侧：CatPlay 的不同分支

**【CatPlay 实现差异：设备角色/驱动】**前面的 DiPlay 是 USB host 接收器连接真实 iPhone 的流程。CatPlay 面向原车的发送侧不能简单倒转前面的箭头：它使用定制 Linux 手机 gadget/UDC 驱动，并处理 USB role switch。这是硬件/驱动栈与运行角色差异；公开证据不足以据此断言其 iAP2/AirPlay wire format 与 Apple 不同。

源码状态流程：

```text
创建 PhoneGadget、绑定 UDC
  → GadgetStarted / ReceivedEnable
  → 收到 RoleSwitch（或测试用 pinned 分支）
  → WaitingForAccessory / DetectedAccessory
  → 建立 iAP2 CSM 与手机角色会话
  → ConfiguringNcm：配置手机侧 IPv6 link-local
  → WaitingForStableMulticast：确认 mDNS IPv6 可用
  → CarPlaySession：接口和地址就绪
  → 发布 ctrl → 收邀请 → AirPlayTransmitterBootstrap
  → SETUP / 视频与音频发送
```

其 `PhoneGadgetDriver` 通过 `/sys/class/iphone`、UDC 状态及 iAP2 设备节点控制定制内核接口；不是普通 Android `UsbManager` 可以直接替代。所查源码显示 `ReceivedRoleSwitch` 等驱动状态与后续 NCM 配置，但本报告没有取得所有内核 EP0 请求的完整线上逐包证据，因此**不伪造 role-switch 控制包字节或断言所有车机都用这套顺序**。固定测试角色 pinned 也不是量产手机的普遍流程。

证据：[CarPlayPhoneGadget 状态](GitHub-CarPlay-Projects/catplay/usb/catplay_iap2_usb_host/src/carplay_phone_gadget.rs#L68-L89)，[role-switch 到 NCM](GitHub-CarPlay-Projects/catplay/usb/catplay_iap2_usb_host/src/carplay_phone_gadget.rs#L299-L437)，[定制驱动接口](GitHub-CarPlay-Projects/catplay/usb/catplay_iap2_usb_host/src/phone_gadget_driver.rs#L72-L193)，[发送侧入口](GitHub-CarPlay-Projects/catplay/catplay_carplay_tx_gadget/src/client.rs#L26-L95)。

这也解释了为什么 Android sender APK 有 Wi-Fi 视频发送代码，并不意味着插 USB 线就能成为原车认可的手机设备。USB 主从角色、UDC 驱动、角色切换、服务握手和网络承载都是额外前提。

## 5. 无线：蓝牙引导、入网、邀请及运行期切换

### 5.1 准备网络，不等于已经连接 iPhone

DiPlay 有四种网络后端：Wi-Fi P2P、LocalOnlyHotspot、车机热点、现有 Wi-Fi/同局域网。选择一个可用后端并取得实际 SSID、信道、地址和接口，先建立 AirPlay listener 和 Bonjour 服务，随后进行 RFCOMM iAP2 控制。

**不能推断 iPhone 必然参与 Wi-Fi Direct 的 P2P discovery/GO negotiation。** 源码证明的是 Android 用 `WifiP2pManager.createGroup()` 创建 Group Owner 网络，检查 `isGroupOwner`、读取口令和接口。手机收到 Wi-Fi 参数后如何完成 802.11 关联、认证、IP 获取，属于系统 Wi-Fi 栈；此项目没有逐包实现完整 iPhone P2P 栈。DHCP、IPv6 邻居发现等实际过程需要抓包确认，不可一律假设仅 IPv4/DHCP。

证据：[WirelessHotspotBackend](DiPlay/shared/src/main/java/com/shilapi/xcertplay/network/WirelessHotspotManager.kt#L7-L37)，[P2P createGroup](DiPlay/shared/src/main/java/com/shilapi/xcertplay/network/WifiP2pGroupManager.kt#L210-L252)，[读取 GO 配置](DiPlay/shared/src/main/java/com/shilapi/xcertplay/network/WifiP2pGroupManager.kt#L524-L580)，[无线总管](DiPlay/shared/src/main/java/com/shilapi/xcertplay/orchestration/CarPlayController.kt#L1304-L1557)。

### 5.2 蓝牙配对与 RFCOMM

- 首次蓝牙配对、系统提示和用户授权属于前提；DiPlay 从已配对设备选择目标，不证明每次会自动完成首次配对。
- 当前 DiPlay 连接手机的 iAP2 RFCOMM 服务，UUID 为 `00000000-deca-fade-deca-deafdecacafe`。
- 获取可靠的 input/output stream 后，由读线程驱动字节流；`socket.isConnected=true` 不是 iAP2 同步成功。
- CarDeck 支持出站连接配件服务，也支持监听手机服务让车机回连；**TCP/蓝牙监听方向不会改变它的手机协议角色**。
- 这里是经典蓝牙 RFCOMM 路径，不能写成“CarPlay 的视频经 BLE GATT 传输”。

证据：[BluetoothRfcommDuplexStream，26–99 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/BluetoothRfcommDuplexStream.kt#L26-L99)，[无线 RFCOMM 连接](DiPlay/shared/src/main/java/com/shilapi/xcertplay/orchestration/CarPlayController.kt#L1509-L1557)。

### 5.3 iAP2 无线启动消息

下表是接收器与手机角色之间的交互，不是强制唯一顺序。

| 消息/事件 | 方向 | 参数及作用 |
|---|---|---|
| 识别和 MFi | 手机 ⇄ 接收器 | 第 6 节：配件身份与能力 |
| 订阅状态 | 接收器 → 手机 | 订阅设备及无线可用信息 |
| `0x5702` RequestAccessoryWiFiConfiguration | 手机 → 接收器 | 请求 Wi-Fi 信息 |
| `0x5703` AccessoryWiFiConfiguration | 接收器 → 手机 | SSID、口令、安全类型、信道，可选 AP BSSID |
| `0x4E0D` WirelessCarPlayUpdate | 手机 → 接收器 | 无线可用状态 |
| `0x4E0E` DeviceTransportIdentifier | 手机 → 接收器 | 传输身份；DiPlay 可据此再发一次 Wi-Fi 配置 |
| `0x4300` CarPlayAvailability | 手机 → 接收器 | 有线/无线可用信息 |
| `0x4301` CarPlayStartSession | 接收器 → 手机 | 无线参数及 AirPlay 地址、端口、身份 |
| Wi-Fi 入网、IP 可达 | 系统网络栈 | 与服务启动并发，不能仅以 AP 创建回调认定已关联 |
| Bonjour 或 ctrl 邀请 | 双方具体路径相关 | 发现服务、触发发送侧连接 |
| AirPlay TCP 建立 | 发送侧 → 接收侧 | 进入第 7 节 |

证据：[Iap2WirelessControlClient，119–238 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2WirelessControlClient.kt#L119-L238)，[Wi-Fi 和会话端点构建](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2WirelessControlClient.kt#L251-L285)。配置重复请求有限额、阶段和超时策略；不能把重发写成一个无限循环，或误认为第二个 5703 是另一条媒体流。

### 5.4 Bonjour 与控制邀请

DiPlay 发布/处理 `_airplay._tcp` 和 `_carplay-ctrl._tcp`，在选定 Wi-Fi 接口和地址族上做服务发现。这里使用的 DNS-SD/mDNS 是网络发现层；不是屏幕帧协议。

另一常见分支：**发送端也发布 ctrl 服务**，接收器向它请求 `GET /ctrl-int/1/connect`，发送端据邀请和已发现的接收器信息主动连接 AirPlay 端点。CarDeck 和 CatPlay 均有此类路径。不要把“手机监听邀请”误写成“车机向手机推视频”。

证据：[CarPlayBonjour，293–306 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/network/CarPlayBonjour.kt#L293-L306)，[服务类型常量](DiPlay/shared/src/main/java/com/shilapi/xcertplay/network/CarPlayBonjour.kt#L666-L667)，[CatPlay 邀请状态机](GitHub-CarPlay-Projects/catplay/catplay_carplay_tx_gadget/src/client.rs#L300-L346)，[CarDeck 邀请处理](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/net/CarPlayCtrlAdvertiser.kt#L260-L281)。

### 5.5 蓝牙 → Wi-Fi iAP 交接

1. AirPlay `SETUP` 可申请 `type=130` 的 iAP 数据流。
2. 接收侧检查 `clientTypeUUID`、`seed`，建立实际数据通道。
3. 数据包中取出 iAP 字节，再跑该运行期控制会话；可能再次识别和认证。
4. 手机发 `disableBluetooth` 等控制命令。
5. DiPlay 需同时看到“手机请求交接”和“无线 tunnel ready”才完成交接；收到命令就立即断蓝牙可能造成启动失败。
6. tunnel 未就绪时有看门狗/回退，不能把所有车都强制套成只剩 Wi-Fi 的状态。

证据：[建立 tunnel](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/CarPlayMediaEngine.kt#L379-L427)，[交接条件与生命周期](DiPlay/shared/src/main/java/com/shilapi/xcertplay/orchestration/CarPlayController.kt#L1812-L1897)。

## 6. iAP2：链路握手、CSM 与 MFi 每次交互

### 6.1 Link 层和 CSM 层不同

DiPlay 实现的 detection marker 是 `FF 55 02 00 EE 10`。进入同步后，用 `FF 5A` 开头的链路包交换同步参数和 ACK。SYN 的载荷含版本、窗口、最大包长、重传/ACK 定时及可用 session 表。

```text
字节流接通
  → marker 交换（发起/响应方式因角色与 profile 不同）
  → 本端 SYN、接收对端 SYN 参数
  → ACK 确认及 NORMAL/writable
  → 在协商的 control session 中承载 CSM
  → 后续 ACK、重传、窗口管理持续运行
```

不能将 iAP2 SYN/ACK 当成 TCP SYN/ACK。DiPlay Link 包有 9 字节 header：marker 两字节、u16 长度、flags、sequence、ack、session、header checksum；有载荷时再有 payload checksum。CSM 则是大端 `40 40 | u16 总长 | u16 messageId | body`，**没有自己的 checksum**，body 参数为 `u16 长度 | u16 parameterId | value`，参数 ID 可以重复，不能随意转换为 map。

DiPlay 的当前 link control session 为 10；其他发送器可按协商采用不同 session，不应硬编码为所有设备相同。链路可分片，transport 一次 read 不等于一条 CSM。

证据：[Link 启动与解析](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2LinkEngine.kt#L169-L200)，[同步和 ACK](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2LinkEngine.kt#L264-L370)，[常量与 header](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2LinkEngine.kt#L644-L679)，[CSM framer](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/wire/Iap2CsmFramer.kt#L1-L51)，[参数集合](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/wire/Iap2Wire.kt#L5-L115)。

### 6.2 识别与认证消息方向

| 次序 | 发送方 → 接收方 | ID | 接收器动作 / 内容 |
|---:|---|---:|---|
| I1 | 手机角色 → 配件 | `0x1D00` | StartIdentification |
| I2 | 配件 → 手机角色 | `0x1D01` | 配件名称、型号、能力、发送/接收消息清单、传输信息 |
| I3 | 手机角色 → 配件 | `0x1D02` / `0x1D03` | 接受或拒绝；拒绝可能导致可选能力裁减重试 |
| I4 | 手机角色 → 配件 | `0xAA00` | 请求认证证书 |
| I5 | 配件 → 手机角色 | `0xAA01` | 证书/认证类型对应的载荷 |
| I6 | 手机角色 → 配件 | `0xAA02` | challenge 参数 |
| I7 | 配件 → 手机角色 | `0xAA03` | 芯片、有效身份或认证服务签名响应 |
| I8 | 手机角色 → 配件 | `0xAA05` / `0xAA04` | 认证成功或失败 |
| I9 | 双方按能力 | 状态/订阅等 | 电源、媒体、无线可用、后续会话启动 |

DiPlay 接收侧证据：[Identification.exchange](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L197-L235)，[MFi exchange](DiPlay/shared/src/main/java/com/shilapi/xcertplay/mfi/Iap2MfiAuthenticationClient.kt#L19-L76)。

**【CatPlay/CarDeck 的认证实现限制】**CarDeck 明确跳过配件证书及挑战签名校验，甚至挑战超时后也可能继续报告成功；这只能证明消息流实现，不证明配件身份经过正确验收。CatPlay 的所查 phone-role CSM 分支也在收证书后发送固定测试 challenge，收到响应后直接发成功；不能把它写成 Apple iPhone 的真实密码学校验实现，也不能把这项测试行为当作 CarPlay 协议的认证定义。

证据：[CarDeck 发送角色认证处理](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2SenderSession.kt#L199-L235)，[挑战回退](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2SenderSession.kt#L598-L681)，[CatPlay phone-role CSM](GitHub-CarPlay-Projects/catplay/catplay_carplay_tx_gadget/src/carplay_client_session.rs#L685-L738)。本文不提供绕过真实 Apple 验证或认证材料的操作方案。

### 6.3 外部 iAP2 项目交叉核对

对照用户提供的 [wiomoc/iap2](https://github.com/wiomoc/iap2) 与 [HaToan/carplay-wifi-extractor](https://github.com/HaToan/carplay-wifi-extractor)：**两者的 iAP2 核心结构与本文第 5–6 节大体一致；它们不是完整 CarPlay AirPlay/媒体发送栈。** extractor 包含与 wiomoc 项目相同的 CSM/Wi-Fi 模块代码，同时增加 phone-role client；因此二者不是完全独立的两份协议证据。

| 检查点 | 源码核对结果 | 与本文关系/注意事项 |
|---|---|---|
| Link 层 | 两份 Python 实现都有 `FF 55 02 00 EE 10` detection marker、`FF 5A` Link frame、序号/ACK、校验和及 SYN 参数协商。 | 与 §6.1 的分层描述吻合。但 extractor README 把 `FF 55...` 标成 SYN/SYN-ACK，并省略真实 `FF 5A` header 中的 control/session 字段；实际源码将 marker 检测与后续 Link SYN 分开，应以代码而非 README 图为准。[wiomoc link layer](https://github.com/wiomoc/iap2/blob/master/iap2/link_layer.py)、[extractor client link layer](https://github.com/HaToan/carplay-wifi-extractor/blob/main/example/iap2/link_layer_client.py)、[extractor README](https://github.com/HaToan/carplay-wifi-extractor/blob/main/README.md)。 |
| CSM 格式 | `0x4040`、总长、message ID；参数头按 `length`、`parameterId`、value 编码。 | 与本文 §6.1 的 CSM 格式一致。README 的 TLV 图将 Tag 放在 Length 前，与它自己的 serializer/parser（先读写 length，再 parameter ID）不一致。[wiomoc CSM codec](https://github.com/wiomoc/iap2/blob/master/iap2/control_session_message/__init__.py)。 |
| 无线 Wi-Fi 配置 | `0x5702` 请求、`0x5703` 响应；字段含 SSID、passphrase、security type、channel。 | 与本文 §5.3 一致。源码按 CSM 参数序列编码，应用层没有额外加密层；这不等于可断言 Bluetooth 空口必然明文，因为链路加密取决于蓝牙连接状态。[Wi-Fi CSM](https://github.com/wiomoc/iap2/blob/master/iap2/control_session_message/wifi.py)、[extractor Wi-Fi CSM](https://github.com/HaToan/carplay-wifi-extractor/blob/main/example/iap2/control_session_message/wifi.py)。只应在获授权的测试设备上处理配件凭据，不要传播抓取日志中的真实网络信息。 |
| 交互方向与认证 | extractor client 源码发送 `StartIdentification`，读取配件 `IdentificationInformation`，再发送 `IdentificationAccepted`；认证响应未被校验就发送 `AuthenticationSucceeded`，之后才请求 Wi-Fi 配置。 | 主流程与 §6.2 的消息方向及“不能把成功消息当作已验证身份”吻合；但其 README 的 client 时序图把 Identification 方向画反，且 README 内部不同示意不完全一致。[extractor client flow](https://github.com/HaToan/carplay-wifi-extractor/blob/main/example/iap2/client/__main__.py)。 |
| session 参数 | wiomoc server 示例使用 control/EA session 10/11、version 1；extractor phone-role client 配置 1/2、version 2。 | 是实现/对端协商配置差异，不足以单独判为协议错误；支持本文“session ID 不可跨实现硬编码”的提醒。不能把任一仓库的数值泛化到所有车机。 |
| 协议覆盖 | 仓库重点是 RFCOMM/USB 上的 iAP2 Link、CSM、认证消息及 Wi-Fi 参数交换。 | 不能用它们验证 RTSP `/info`、pair-setup/verify、SETUP/RECORD、HID event、视频/音频帧格式；这些内容仍需看 CatPlay/DiPlay/CarDeck 对应代码或实测记录。 |

**结论：**协议核心（iAP2 Link/CSM、身份认证消息 ID、Wi-Fi 配置消息）与本文相符；不相符处主要是 extractor README 的示意/字段次序错误、不同实现的 session 配置，以及认证验收未完成。它们既不能推翻本文的 CarPlay 通用流程，也不能证明完整 CarPlay 互通。

## 7. AirPlay / RTSP：配对到会话建立
### 7.1 三种认证不能混写

- **Lockdown pairing**：USB 服务和用户信任状态。
- **iAP2 MFi exchange**：配件证书及 challenge/response。
- **AirPlay pair-setup / pair-verify / auth-setup**：AirPlay 层的长期身份、临时共享密钥及具体认证路径。

是否都出现、先后如何，依设备代际和实现分支变化；不能把某次完整记录写成所有设备必发的“标准包序列”。

### 7.2 pair-setup：M1 到 M6

DiPlay 响应方和 CarDeck 发起方可对照：

| 消息 | 发送端 → 接收端 / 返回 | 核心内容 |
|---|---|---|
| M1 | 发送端 POST `/pair-setup` | TLV8 state=1，方法 |
| M2 | 接收端响应 | state=2、SRP salt、服务端公开参数 |
| M3 | 发送端再次 POST | state=3、客户端公开参数、SRP proof |
| M4 | 接收端响应 | state=4、server proof；错误不应当成功 |
| M5 | 发送端再次 POST | state=5、加密长期身份、公钥及签名 |
| M6 | 接收端响应 | state=6、加密接收端身份、公钥及签名；持久化配对 |

DiPlay 使用 SRP-6a、HKDF-SHA512、Ed25519、ChaCha20-Poly1305；上述名称来自项目实现，不是从公共 PDF 推导。[PairSetup](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/PairSetup.kt#L1-L115)，[CarDeck 配对发起方](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/PairingClients.kt#L31-L115)。

### 7.3 pair-verify：M1 到 M4

1. M1：发送端交临时 X25519 公钥。
2. M2：接收端回临时公钥及加密的身份/Ed25519 签名。
3. 发送端由临时密钥生成 shared secret，验证接收端身份，再交 M3 的加密身份/签名。
4. 接收端检查保存的发送端长期公钥，验签后回 M4；按读/写方向派生控制密钥。
5. 响应发送后，后续控制数据升级为加密帧；方向和计数不能交换。

证据：[DiPlay PairVerify](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/PairVerify.kt#L30-L117)。CarDeck 中接收端签名结果被记录但不总是强制拒绝失败，因此不能以“有 Ed25519 代码”证明其严格验收身份：[CarDeck PairVerify 实现](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/PairingClients.kt#L166-L241)。

### 7.4 auth-setup 和兼容分支

DiPlay 有 `/auth-setup` 处理；一次仓库会话在 pair-verify 后发送它。**【与其他公开实现/握手记录的路径差异】**CatPlay 的发送启动器当前先试初始 SETUP，失败时才尝试配对升级；代码中有 auth-setup 路径但 Connected 默认调用处未启用。**这只是 CatPlay 对其目标 USB 车机的兼容策略，不是建议关闭安全机制，也不是所有 CarPlay 接收器允许明文。**
证据：[DiPlay 请求分派](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L538-L625)，[CatPlay SETUP 失败升级](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/carplay_tx/transmitter.rs#L306-L342)，[Connected 选择](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/carplay_tx/transmitter.rs#L526-L552)。

#### auth-setup 的二进制交互（DiPlay 所实现分支）

- 请求：1 字节 version=1，加 32 字节发送侧临时 X25519 公钥；不是 TLV8 的 pair-setup 消息。
- 接收侧：生成临时密钥，计算 shared secret；按具体认证类型签名两端公开参数或其摘要。
- MFi 响应：接收侧 32 字节临时公钥、4 字节证书长度、证书、4 字节签名长度、AES-128-CTR 密封的签名。
- BAA 分支另带中间证书数据；不能把不同证书类型压成相同响应布局。
- 发送侧还需校验身份与签名，不能仅因响应长度正确或 HTTP 200 就报告认证合格。

证据：[MfiSapAuthSetup，24–111 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/MfiSapAuthSetup.kt#L24-L111)。这与后续媒体的 ChaCha framing 不同；不同会话是否选用该分支要以实际请求和认证状态为准。

### 7.5 初始 SETUP、/info、event、RECORD

**初始 SETUP** 与 **带 streams 的 SETUP** 不同：

```text
发送端                          接收端
  SETUP（设备、时钟、feature） ──►
       ◄── timingPort、eventPort、keepAlivePort、enabledFeatures
  /info ─────────────────────────►
       ◄── displays、HID、audioFormats、尺寸/安全区等
  TCP connect(eventPort) ────────►   后续双向事件/命令
  modesChanged / 资源交互 ⇄          屏幕和音频资源归属
  SETUP(streams=[...]) ──────────►
       ◄── 各流实际端口和流 ID
  TCP 视频 / UDP 音频 ⇄
  RECORD ───────────────────────►   激活会话/资源，确切时机因实现而异
```

不能把示意图当严格唯一顺序：**有记录先 RECORD 后申请视频流；CarDeck 则先连接视频 dataPort 再 RECORD，音频随后建立。**

初始 SETUP 常见字段：`deviceID`、`model`、`sourceVersion`、`sessionUUID`、`timingPort`、`features`、`keepAliveLowPower`。接收端只启用提议与支持的交集。端口由 socket 实际绑定产生，不应假设全是 7000。

带 streams 的 SETUP 中，视频常有 `type`、`uuid`、`streamConnectionID`、`latencyMs`；音频再有 `audioType`、`audioFormat`、输入/端口字段；data 流再按 UUID 分业务。

证据：[DiPlay 初始及 streams SETUP](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L655-L757)，[CatPlay 初始 SETUP 与 info/event](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/carplay_tx/transmitter.rs#L352-L482)，[CarDeck 总管实际顺序](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L2639-L2824)。

## 8. 数据发送：视频、音频、麦克风、type 130

### 8.1 主屏 110 和仪表 111

发送侧：读 `/info` 显示 UUID 和尺寸 → 创建每条流的 connection ID → SETUP → 读取 dataPort → 连接该 TCP socket → 先交 codec config → 发送编码帧 → 保活、关键帧恢复、资源归还。

接收侧：监听协商端口 → 校验来源 → 累积完整帧头和载荷 → 解密 → 解析配置和 NAL → 解码到相应屏幕。

DiPlay 的屏幕帧头为 **128 字节**；offset 0 是小端 body 长度，offset 4 opcode，offset 8..15 是项目解释的时间值；opcode 1 配置、0 视频帧。帧数据通过 ChaCha 验证解密，header 用作 AAD，nonce 使用每流计数；NAL 的四字节大端长度前缀转换为 Annex B。**这一 TCP 包格式不是把视频一律放进 RTP。**

**【CatPlay 对照：此处没有观察到帧头长度差异】**CatPlay 自身的 `ScreenFrameHeader` 同样定义为 128 字节，并用相同的 body-size/opcode 起始布局。这里可以说两个检出实现一致，不能反推 Apple 规范已经完整公开；具体加密模式、flag 与统计字段仍要分别看 codec/session 配置。[CatPlay frame header](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/screen/screen_frame.rs#L98-L149)，[CatPlay codec](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/screen/screen_frame_codec.rs#L150-L175)。

证据：[DiPlay ScreenStream/ScreenCodec](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/ScreenStream.kt#L45-L205)，[CatPlay 发送视频 SETUP](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/carplay_tx/transmitter_impl.rs#L279-L357)，[CatPlay ScreenTransmitSession](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/screen/tx/screen_tx_session.rs)。

CarDeck 使用 MediaCodec H.264 编码、Surface 输入、codec config 和帧发送、关键帧请求；视频来自隐藏/虚拟显示，依赖已授权的 Shizuku shell 服务，不是普通 APK 随意抓取所有显示与注入输入。它当前没有证明原生 CarPlay 仪表 111 已实现。

证据：[CarDeck VideoSender](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/video/VideoSender.kt#L93-L162)，[编码取帧与发送](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/video/VideoSender.kt#L218-L430)，[隐藏显示源](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/capture/HiddenDisplaySource.kt#L27-L80)。

### 8.2 实时音频与输入麦克风

| 类型（所查实现） | 用途 | 不能误解为 |
|---:|---|---|
| 100 | main audio；按 audioType 区分媒体/电话/Siri 等 | 所有类型 100 都是同一首音乐 |
| 101 | alt audio | 仪表视频 |
| 102 | main high audio | 固定所有设备 AAC 的强制标准 |
| 103 | 可选缓冲音频 | 缓冲视频或另一屏幕 |

一个音频 type 可有多个用途，必须同时看 `audioType`、`audioFormat`、方向、输入标志和实际端口。PCM、AAC-LC、Opus 等是各项目能力与格式处理，最终以协商结果为准。

DiPlay 实时接收代码创建 data/control 两个 UDP socket。所查加密音频包为：12 字节 RTP header + 密封 payload/tag + 末尾 8 字节 nonce；AAD 使用 RTP header 的部分字段。RTP sequence 和 sample timestamp 用于接收统计及播放，不是视频帧序号。control socket 的当前代码主要接收包；不能因此声称该类已经完整实现每一种 RTCP 重传功能。

证据：[AudioStream，60–195 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AudioStream.kt#L60-L195)。

麦克风是**车机 → 手机角色**的音频，需单独采集、按协商编码与 input key 发送；不是把音频下行数据反过来写。DiPlay 用 audioType 和输入字段判断是否开启。CarDeck 音频 SETUP `input=false`，未实现通话/Siri 麦克风回传；RECORD_AUDIO 权限不等于该功能已完成。

证据：[DiPlay 麦克风判断](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/CarPlayMediaEngine.kt#L645-L706)，[CarDeck 下行音频协商](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/AirPlayClient.kt#L1635-L1770)。

### 8.3 加密与方向

控制帧和 data tunnel 使用小端长度前缀、认证密文和 tag；读写方向各有自己的 key/counter。DiPlay `ControlCipher` 并不是 TLS record：TLS 属于前面的 Lockdown 服务分支，不能与 AirPlay ChaCha framing 混称。

流 key 根据共享 secret、`DataStream-Salt` 加连接 ID 或 seed，以及 Input/Output label 经 HKDF-SHA512 派生。**屏幕、音频、iAP tunnel 的 key/nonce 状态不得混用**；发送/接收方向 label 的含义需按所在端解释，而不是机械把 Output 当本机发送。

证据：[ControlCipher](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/ControlCipher.kt#L1-L55)，[流密钥派生](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/CarPlayMediaEngine.kt#L665-L706)。本文不记录真实密钥、证书、口令或配对私钥。

#### 媒体时钟不是通用 UDP/123 NTP 服务

DiPlay 的 `NtpClock` 使用协商的 timingPort 收发项目格式的 32 字节 UDP 包；包含 originate、receive、transmit 时间字段，以请求发送和响应接收时刻估计偏移与往返延迟。不能仅因类名 NtpClock 就写成手机连接公共 NTP 服务器，或把时钟请求当音频采样数据。音频 RTP 时间戳还需按音频采样时钟解释，不是墙钟毫秒。

证据：[NtpClock 请求和响应](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/NtpClock.kt#L87-L155)，[字段偏移](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/NtpClock.kt#L187-L190)。

### 8.4 type 130 不等于单一 iAP 通道

先检查 `clientTypeUUID`、seed、controlType、stream ID、是否有 dataPort、是否要求 dedicated socket，再决定业务。

- iAP tunnel：承载 iAP 字节并进入运行期会话。
- LIVI 中普通/高优先级 vehicle state：车辆 accessory/characteristic 数据，不等于 iAP2 的电量消息。
- uiSync：显示与仪表选择同步，不是又一条地图视频。
- 视频设置、播放控制、overlay：视频播放业务；某些路径有 socket，某些只回 stream ID。
- 对未知 UUID 应按项目支持范围处理，不能假装已建立所有可能通道。

DiPlay iAP tunnel 在认证帧内再解析 32 字节 package header 的 `comm` 包，提取 iAP 载荷；发送回程也有命令桥接，不能从 TCP 上的一次 read 直接当作完整 CSM。

证据：[IapTunnel，170–222 行](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/IapTunnel.kt#L170-L222)，[LIVI UUID 分派](GitHub-CarPlay-Projects/LIVI/native/crates/livi-cp/src/stack/data_streams.rs#L8-L40)，[DiPlay type130 处理](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/CarPlayMediaEngine.kt#L379-L427)。

## 9. 输入、资源归属和结构化数据

### 9.1 输入和模式不是媒体帧

- `hidSendReport`：车机 → 发送端；传触摸坐标、按键、旋钮等报告。
- `hidSetInputMode`：输入模式设置；描述符/设备 ID 需匹配。
- `modesChanged/changeModes`：资源拥有者、临时借用、音频/屏幕占用状态；不是通知收到视频帧。
- `showUI`、viewArea 更新：请求界面/布局切换。
- `/feedback`、event、keepAlive、timing：健康状态、双向命令、保活和媒体时钟。

**【CatPlay实现范围】**CatPlay 的 `CarManager.flush_modes()` 明确将模式状态与 screen SETUP/TEARDOWN 对齐；其事件命令类型只覆盖源码枚举中的子集，未知命令会回 501，而不是自动忽略或通用转发。该边界描述的是 CatPlay 当前支持度，不代表 CarPlay 端没有其他命令。CarDeck 接收 HID 后，经描述符、TouchRouter/HidNavigation 和已授权 Shizuku 输入服务操作 Android 虚拟显示；接收一个 HID report 不代表 Android 已成功执行输入。

证据：[CatPlay 资源队列](GitHub-CarPlay-Projects/catplay/c2a/catplay_c2a/src/proxy_rpc/car_manager.rs#L266-L326)，[CarDeck 输入分派](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L2494-L2606)，[DiPlay HID 命令](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L348-L448)。

### 9.2 导航、车辆与 HUD

- iAP2 `0x5201` 路线、`0x5202` maneuver、`0x5204` 车道等是结构化导航，可与仪表 111 视频并存。
- `0xA100/0xA101` 等车辆更新属于项目支持的特定消息；真实数据依权限和车厂属性。
- 定位消息可承载 NMEA，车速/挡位是否发出取决于手机请求及项目能力。
- HUD 输出需车厂导航接口，不一定有 CarPlay HUD 视频；导航数据、仪表帧、厂商 HUD 接口是三项独立验收。
- 发送器只实现视频和触摸，不意味着已实现导航元数据、通话、EV 路线或 Ultra。

参见 [前篇车辆与导航分析](CarPlay功能与通道分析.md)，[DiPlay 车厂功能与验证边界](DiPlay/docs/BYD_NAVIGATION.md)，[LIVI 路线结构](GitHub-CarPlay-Projects/LIVI/native/crates/iap2-csm/src/messages/route_guidance.rs)。

## 10. CatPlay 双角色如何代理数据

**【CatPlay特有的适配器架构，不等于 Apple 原生 iPhone 栈】**CatPlay 的发送器不是只用来“把 Android 画面发过去”。其生产适配器可以接 iPhone，代理到已有车机：

```text
iPhone 视频/控制
  → CatPlay RX 解密、会话回调
  → ScreenChannel / Modes / Command / SetupAudio 等内部消息
  → CarManager / Overlay / AudioProxy
  → CatPlay TX 对车机重新 SETUP、按车机端口发送
```

`dispatch_tx_op()` 接收 `ScreenChannel`、`Modes`、`Command`、`SetupAudio`；`AudioProxyUtil` 按方向和 codec 配置建立音频发送/录音代理。不能描述为完全透明的原始 TCP 转发，也不能假设两边共享端口、密钥或同一资源状态。

证据：[内部代理操作](GitHub-CarPlay-Projects/catplay/c2a/catplay_c2a/src/proxy_rpc/car_manager.rs#L336-L375)，[音频代理](GitHub-CarPlay-Projects/catplay/c2a/catplay_c2a/src/audiov2/audio_proxy.rs#L16-L70)。

重要边界：CatPlay phone-role CSM 的某些现代启动分支仍有 TODO，实际 sender gadget 还有 Bonjour 邀请触发路径；不能因为能发视频就写成所有现代无线/仪表/Ultra 协议都完成。当前所查 CatPlay 枚举 111/103 有注释项，也不证明已启用副屏/缓冲流。

## 11. 用现有握手记录纠正“理想顺序”

证据来自 [xcertplay handshake-wireless-cluster.txt](xcertplay/common/src/test/resources/handshake-wireless-cluster.txt)。这是仓库记录而非本机抓包；以下只列协议名称和行号，不复制敏感认证材料。

| 记录中的顺序 | 行号 | 说明 |
|---|---:|---|
| RFCOMM 识别 1D00 → 1D01 → 1D02 | 29–31 | 手机请求配件身份 |
| AA00 → AA01 → AA02 → AA03 → AA05 | 34–43 | 蓝牙阶段 MFi 消息 |
| 5702 → 5703，4E0D，4E0E，再发 5703 | 53–62 | Wi-Fi 配置和传输状态 |
| 4300 → 4301 | 63–66 | 启动端点交付 |
| 三次 `/pair-setup` | 75、86、88 | M1/M3/M5 请求 |
| 两次 `/pair-verify` | 93、95 | M1/M3 请求 |
| `/auth-setup` | 98 | 本次记录出现，不代表所有实现必发 |
| 初始 SETUP → /info | 100–110 | 能力和 event/timing 等 |
| RECORD | 112 | **发生在屏幕流 SETUP 之前** |
| type130 iAP SETUP | 115–121 | 独立运行期数据通道 |
| modesChanged | 125–130 | 资源交互 |
| 仪表 111 SETUP | 131–135 | 本次先建立仪表流 |
| showUI、disableBluetooth | 137–139 | 仪表 UI 与交接请求 |
| 主屏 110 SETUP | 141–146 | 不可把此顺序推广为“总是主屏先” |
| 双屏 codec config / 首帧 | 149–153 | 显示流开始送数据 |
| tunnel 再次识别与 AA00..AA05 | 151–167 | **与首帧交错发生，不是所有认证结束才开始全部视频** |

从记录能证实同一次运行出现多阶段/并行交互，却不能证实当前 HEAD 在所有设备的互通，更不能由两条首帧推断音频和 HUD 正常。

## 12. 发送端代码阅读顺序与原创伪代码

### 12.1 CarDeck

```text
SessionController
  选择车机 profile、取得授权
  建立 RFCOMM / 接受回连
  Iap2LinkEngine 协商
  Iap2SenderSession：识别、认证消息、无线信息交换
  加入车机 Wi-Fi，并绑定正确 Network
  发布 ctrl / 处理邀请 / 确定 AirPlay 地址
  AirPlayClient.pair / 初始 SETUP / info
  打开 event，处理 HID 和资源状态
  主屏 SETUP → 连接 video dataPort → RECORD
  VideoSender：MediaCodec config、关键帧、后续帧
  可选 AudioSender：协商、捕获、编码、UDP
  保活、feedback、恢复、关闭
```

重点入口：[Iap2SenderSession](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2SenderSession.kt#L199-L330)，[AirPlayClient 主屏 SETUP/RECORD](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/AirPlayClient.kt#L1973-L2081)。与作者旧注释冲突时，以当前调用顺序为准。作者曾记录特定车型成功，但部分后续文档还有断链、黑屏和音频捕获问题；没有以本次静态阅读替代实车验收。

### 12.2 CatPlay

**【本节边界】**这里的“CatPlay 发送端”指适配器面向原车的一端，不是把 CatPlay 等同于 Apple iPhone 的原生 CarPlay transmitter。流程和前述通用层次的差别已在 §3.1 汇总：认证验收为测试实现、配对启动顺序是 CatPlay 特定兼容分支、现代流与事件命令只覆盖部分能力。以下仅描述当前代码路径，不构成 Apple 协议符合性结论。

```text
CarPlayUsbClientGadget
  有 USB 网络及服务状态
  发布 ctrl、收邀请、发现目标
  AirPlayTransmitterBootstrapSession.connect
    建控制 TCP
    初始 SETUP；兼容错误分支可能进入配对升级
    info → timing/event/keepAlive
  CarManager 对齐资源状态
  AirPlayTransmitterImpl.do_setup_video
    descriptor → SETUP → dataPort → ScreenTransmitSession
  audio SETUP → RtpReceiver.finish_tx（类名仍需看 TX 方法）
  命令代理、媒体代理、feedback
  TEARDOWN → 按所有权释放资源
```

证据：[CatPlay video/audio transmitter](GitHub-CarPlay-Projects/catplay/carplay/catplay_carplay/src/carplay_tx/transmitter_impl.rs#L173-L357)。不要仅因类叫 `RtpReceiver` 就忽略其 `new_tx/finish_tx` 发送路径。

### 12.3 carlife-to-carplay：可用于对照的另一发送器

它不是只显示 CarPlay 风格 UI：实际 `AirPlaySender.start()` 连接车机、执行配对、初始 SETUP、/info、type110 SETUP、连接 video dataPort 并发送 RECORD。应用的 `AirPlayLink` 在该版本接入 `/auth-setup` 回调；该次序与前面 xcertplay 记录中的 pair-verify 后 auth-setup 不同，不应强行写成统一顺序。

```text
PhoneBootstrap.begin → 1D00 / 1D01 / 1D02
  → 收配件证书、验证/绑定身份
  → AA02 challenge / AA03 response / 验证 / AA05
  → 取得无线端点
AirPlayLink → AirPlaySender
  → /auth-setup 回调、PhonePairing、控制密钥
  → 初始 SETUP、/info、音频/显示选择
  → type110 SETUP、video TCP、RECORD
  → iAP 控制承载协商、媒体输出与资源状态
```

它的控制承载选择不是无条件 fallback：`SenderNegotiation` 分 dedicated Wi-Fi socket、命令承载与已验证蓝牙；不能把返回 200 或缺失 130 当作自动认证成功。`PhoneBootstrap` 同时保留多轮历史注释和 profile 分支，以当前 `begin()` 调用为准。所查代码也有认证验收与绑定蓝牙身份的机制，但这仍不等于 Apple 认证或所有车机支持。

证据：[AirPlaySender.start](GitHub-CarPlay-Projects/carlife-to-carplay/core-airplay/src/main/java/com/carplay/sender/AirPlaySender.kt#L444-L484)，[视频 SETUP 与连接](GitHub-CarPlay-Projects/carlife-to-carplay/core-airplay/src/main/java/com/carplay/sender/AirPlaySender.kt#L913-L964)，[应用 auth-setup 接入](GitHub-CarPlay-Projects/carlife-to-carplay/app/src/main/java/com/carlink/cast/AirPlayLink.kt#L199-L213)，[PhoneBootstrap](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/controller/PhoneBootstrap.kt#L296-L440)，[控制承载选择](GitHub-CarPlay-Projects/carlife-to-carplay/core-airplay/src/main/java/com/carplay/sender/SenderNegotiation.kt#L60-L78)。

边界：仓库已有 USB host/真实 iPhone 控制组件，但不能作为 Android USB phone-role/gadget 发送已完成的证据。音频有真实协商和包发送；作者最新变更记录仍涉及断链、CSM=0、音频资源丢失，长期稳定参考不能当作当前应用实车验证通过。参见 [README](GitHub-CarPlay-Projects/carlife-to-carplay/README.md#L77-L117)、[CHANGELOG](GitHub-CarPlay-Projects/carlife-to-carplay/CHANGELOG.md#L8-L65)。

### 12.4 排除误匹配：carlife-unified

该仓库有手机/车机端 TCP 和媒体代码，但输出主要为 **Baidu CarLife** 六通道，不是 Apple iAP2/AirPlay；CarPlay-style Dashboard 仅指界面风格。其 localhost 测试中双方都是自有 Dart 类，也不是 iPhone 对原厂车机实测。下载保留以供协议区分，不用它证明 CarPlay sender 兼容。

证据：[仓库定位](GitHub-CarPlay-Projects/carlife-unified/README.md#L1-L6)，[CarLife TCP 承载](GitHub-CarPlay-Projects/carlife-unified/packages/carlife_protocol/lib/src/carlife_link.dart#L28-L68)，[localhost 测试](GitHub-CarPlay-Projects/carlife-unified/packages/carlife_protocol/test/carlife_protocol_test.dart#L76-L151)。

### 12.5 CarDeck 发送端 ↔ DiPlay/xcertplay 接收端：逐层互通差异

本节只比较所查源码中的 CarDeck 手机/发送端与 DiPlay/xcertplay 接收端实现；它不是 Apple 规范的完整定义，也没有本轮真实 iPhone/车机互通测试。结论按“线格式不兼容”“条件分支不兼容”“功能未覆盖”和“安全验收差异”区分，避免把安全弱点误称为协议字段不同。

| 层/功能 | 核对结果 | 判断及影响 |
|---|---|---|
| iAP2 Link/CSM 与无线配置 | 双方都实现 Identification、`0xAA00..05` MFi 消息及 Wi-Fi 配置应答相关消息；源码所查的 `0x5702→0x5703`、`0x4300→0x4301` 方向和基本往返对应。CarDeck 处理能力清单、可选 EA/HID 和 `0x4E0D/0x4E0E` 无线状态；DiPlay 有其接收处理。 | **目前没有确认到这些共同消息的线格式冲突。** 两边能力子集、状态机先决条件并不相同；不能据此声称所有 CSM 能力都互通。证据：[CarDeck IAP2 sender](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2SenderSession.kt#L199-L235)，[DiPlay wireless control](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2WirelessControlClient.kt#L1-L220)。 |
| iAP2 MFi 认证验收 | 消息 ID/顺序可对应：接收端交证书、响应 challenge，发送端最终给 `0xAA05/0xAA04`。CarDeck 会跳过证书/响应签名的严格验收，某些失败/超时分支仍继续；DiPlay 提供真实 MFi responder 接口并等待手机侧认证结果。 | **不是 CSM 编码差异，而是安全验收不等价。** 与 CarDeck 对接成功不代表对端身份已被 CarDeck 密码学验证；也不能将 CarDeck 的成功状态当作真实 Apple 验证通过。[CarDeck MFi 分支](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2SenderSession.kt#L598-L681)，[DiPlay MFi responder](DiPlay/shared/src/main/java/com/shilapi/xcertplay/mfi/Iap2MfiAuthenticationClient.kt#L19-L76)。 |
| Pair-Setup / Pair-Verify | TLV 状态序列及 SRP、X25519、Ed25519、HKDF、ChaCha 构造整体对应；配对后双方控制密钥按 Read/Write 方向派生。 | **已配对主路径未见确定的 wire-format 冲突。** 但 CarDeck 对接收端签名失败主要记录而非一律拒绝；DiPlay 对其配对身份执行验签/状态校验。这是认证强度差异，不是密码算法名称或 TLV 字段差异。未经可信身份绑定仍可能被中间人或错误身份接受。[CarDeck pairing](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/PairingClients.kt#L31-L241)，[DiPlay PairSetup](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/PairSetup.kt#L1-L115)，[DiPlay PairVerify](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/PairVerify.kt#L30-L117)。 |
| 加密 RTSP 控制帧 | 两边都是 `[u16LE 长度作 AAD][密文][16B tag]`、ChaCha20-Poly1305、按方向独立递增 nonce。CarDeck 每片明文上限 1422B，DiPlay 当前 encrypt 上限为 `0x4000`；双方解码器按帧长重组，CarDeck 解码端没有 1422B 上限。 | **分片大小策略不同，但不构成已确认的互通失败。** 一方拆成较小帧、另一方仍逐帧解析；未发现接收端要求发送端必须使用同一固定片长。[CarDeck ControlCipher](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/ControlCipher.kt#L1-L72)，[DiPlay ControlCipher](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/ControlCipher.kt#L1-L55)。 |
| RTSP `/info`、初始/媒体 SETUP、RECORD | CarDeck 通过 `/info` 读取能力，发送初始 SETUP 和 type 110 主屏 SETUP；DiPlay 对应路由 `/info`、SETUP、RECORD，并按 stream plist 配置资源。音频 type/format、显示 UUID、事件端口等依赖协商参数。 | **现有源码没有显示固定的路径/头部线格式冲突。** 必须使用对端实际声明的 feature、display UUID、音频 format/latency；能力不相交或字段缺失时会拒绝/不开流，是协商结果而非必然协议不兼容。[CarDeck SETUP](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/AirPlayClient.kt#L645-L810)，[CarDeck stream SETUP](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/AirPlayClient.kt#L1625-L1755)，[DiPlay RTSP 路由](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L538-L625)，[DiPlay SETUP/媒体分派](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L650-L740)。 |
| 配对后主屏视频 | 两边对 128B 头、u32LE body 长度、opcode 0 视频帧/opcode 1 配置、ChaCha20-Poly1305、完整头作 AAD、逐帧 nonce 计数的处理相符；key 都依赖配对共享秘密和 DataStream 输出密钥派生。 | **配对有效且 streamConnectionID/密钥参数一致时，源码格式兼容。** 这是静态源码对照，不等于实际视频已验证。[CarDeck 视频发送](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/video/VideoSender.kt#L1-L180)，[CarDeck DataStream key](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/AirPlayClient.kt#L1970-L2055)，[DiPlay ScreenStream](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/ScreenStream.kt#L1-L135)，[DiPlay output key](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/CarPlayMediaEngine.kt#L620-L672)。 |
| 未配对视频/事件兼容路径 | CarDeck 明确有 `et=NONE` 未配对会话：视频发送端可走 AES-CTR、无 ChaCha tag；事件 TCP 通道也可退回明文。DiPlay 屏幕流只接受 ChaCha 帧，输出 key 在缺少 `sharedSecret` 时为 null；事件 accept 在 Pair-Verify shared secret 缺失时关闭 socket，并会关闭会话。 | **确定的条件性不兼容（高置信度）：CarDeck 未配对 fallback ≠ DiPlay 接收能力。** 若 CarDeck 选择 `sessionKey=null`，主屏 AES-CTR 帧无法由 DiPlay `ScreenStream` 解密；事件明文也不会被 DiPlay 接受。要走当前 DiPlay 路径，需先成功配对/Pair-Verify，再使用双方 ChaCha 密钥；这不是建议绕过认证的理由。[CarDeck AES/ChaCha 分支](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/video/VideoSender.kt#L1-L180)，[CarDeck 未配对事件逻辑](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/AirPlayClient.kt#L2084-L2125)，[DiPlay 必须有共享密钥的事件处理](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L880-L930)，[DiPlay 的输出 key 缺省行为](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/CarPlayMediaEngine.kt#L620-L672)。 |
| 配对后音频 RTP | 两端都采用 12B RTP header、timestamp+SSRC 作为 AAD、ChaCha20-Poly1305 密文/tag、尾部 8B nonce；CarDeck 针对 LPCM 转成大端 s16、AAC 保持字节流，DiPlay 收到后还原为 RTP 交给解码/播放管线。两端都由协商的 type、audioFormat、audioType 决定 codec。 | **RTP 加密封装源码对得上；codec 互通只对双方协商交集成立。** 当前不能把 CarDeck 可选 AAC/PCM 全部概括成 DiPlay 所有设备配置均支持，需按 `/info` 的 `audioFormats` 和实际 SETUP 响应选共同格式。[CarDeck audio RTP](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/audio/AudioSender.kt#L553-L600)，[DiPlay AudioStream](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AudioStream.kt#L1-L160)，[DiPlay codec parsing](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AudioStream.kt#L222-L262)，[CarDeck audio negotiation](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/AirPlayClient.kt#L1821-L1935)。 |
| 音频同步/控制 UDP | CarDeck 若收到非零 `controlPort`，会周期发送 `AudioSyncPacket` 建立 RTP↔NTP 时间锚点。DiPlay `AudioStream.runControl()` 只从控制 socket 读取并丢弃数据，没有解析该同步包。 | **功能未覆盖，非基础 RTP 密文格式冲突。** DiPlay 当前播放路径可能依靠到包时间及其他 timing/feedback 机制继续播放；CarDeck 发出的该同步语义不会在此类中生效，长时间同步/漂移效果需实测，不能仅凭源码断言必然无声。[CarDeck AudioSync 发送](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/audio/AudioSender.kt#L34-L62)，[CarDeck controlPort 定时发送](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/audio/AudioSender.kt#L360-L404)，[DiPlay control datagram handling](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AudioStream.kt#L55-L165)。 |
| HID/触摸等事件通道 | 配对后双方 Events HKDF 方向标签相反使用、实际读写方向对应；DiPlay 接收加密 RTSP 事件并回 200，CarDeck 能连接 eventPort、解密并把车机命令交给回调。 | **配对后 framing/key 方向表面相符。** 命令 plist 类型、HID UUID/报告格式、具体命令覆盖范围仍需逐命令核对；源码支持事件 TCP 不代表所有触摸/旋钮/语音事件均已实现。[CarDeck event channel](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/AirPlayClient.kt#L2084-L2160)，[DiPlay event accept/read](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L849-L963)，[DiPlay command APIs](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L302-L430)。 |
| `/auth-setup` | DiPlay 有 MFi-SAP `/auth-setup` responder；本次查到的 CarDeck RTSP 请求路径没有对应客户端调用。 | **本轮没有相同交易可比较，不判定为冲突。** 若目标接收端明确要求该交换，而 CarDeck 未发起，则该特定配置可能无法完成；是否必需取决于设备/配对路径。[DiPlay auth-setup 路由](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlaySession.kt#L576-L585)，[DiPlay MFi-SAP handler](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/MfiSapAuthSetup.kt#L1-L150)。 |

**关键结论：**在已配对分支，主屏帧、加密控制帧、音频 RTP 与事件密钥的线格式总体对得上；目前最明确的线级差异发生在 CarDeck 允许的“未配对 AES-CTR/明文事件”分支，DiPlay 只接收配对加密格式，因此不能互通。另有两个非线格式问题：CarDeck 的身份验收弱于应有的安全校验；CarDeck 音频同步 UDP 包在 DiPlay 的当前 AudioStream 控制 socket 中被丢弃。以上均为源码静态对照，尚未做两仓库联机测试。

## 13. 尚不能声称完成的协议覆盖

1. Apple iOS 的完整原生发送代码、全部受限 MFi/CarPlay 消息和所有参数含义。
2. iPhone Wi-Fi 驱动层/P2P 关联和 USB host controller 逐事务行为。
3. 所有车机代际的固定包顺序、所有流编号、所有 cipher 与 DRM。
4. CarDeck 的 USB、仪表 111、麦克风/通话完整能力；其身份验收省略不能当作官方实现。
5. Ultra 完整车辆安全控制、多屏能力和真实执行器集成。
6. 停车视频的受保护内容和 FairPlay 授权，以及任何绕过行车限制的方案。
7. 未随仓库下载的原始真车日志、未运行的测试，不能作为“本次验证通过”。

## 14. 工程验证建议与本次验证记录

每条会话日志至少记录：角色、transport、阶段、RTSP CSeq、stream type、UUID、stream/connection ID、方向、实际端口、首包/首帧、错误类型。日志不记录密钥、口令、认证载荷和个人身份。

**验收点分别设置：**

- USB：权限、重新枚举、USBMUX 版本、Lockdown 服务、NCM 双向包、AirPlay TCP。
- 无线：蓝牙真实字节、iAP2 writable、认证消息、SSID 交付、Wi-Fi IP 可达、邀请、首个 TCP。
- 会话：pairing 结果、初始 SETUP、能力交集、event/timing、资源拥有者。
- 视频：每条流 SETUP、端口连接、codec config、关键帧、解码/呈现。
- 音频：用途与格式、UDP 首包、解密、播放路由、输入回程。
- 运行期：iAP tunnel 真正可用、交接条件、结构化导航、车厂接口独立验证。
- 关闭：局部 TEARDOWN 与完整会话关闭不同；释放 listener、队列、counter、媒体设备和本轮持有资源。

本次验证采用源码引用校验和仓库记录顺序检查；当前所选验证环境只有已确认的 Java 工具，未配置用于本次工程构建的 Android SDK/Kotlin/Rust，因此**不报告任何 Android/Rust 单测、编译、实车或密码学互通测试通过**。

静态核验结果：

- 90 个本地文件引用存在；84 处源码行号范围有效，无缺失文件或越界行号。
- 4 个重点发送端/双角色仓库的 HEAD 与本文记录一致。
- 现有 fixture 的三次 pair-setup、两次 pair-verify 请求数量核对通过。
- fixture 中 RECORD 在主屏/仪表 SETUP 之前，且仪表 SETUP 在主屏之前。
- fixture 的双屏首帧（152、153 行）早于 tunnel 的认证完成（166 行），支持并发/交错结论。
- 130、111、110 的 SETUP 响应均分别出现 dataPort。
- 核对源码中的 iAP2 link 标记/flags、128 字节视频头与 opcode、RTSP 方法以及 CatPlay USB role-switch 状态名称。

核验脚本和结构化结果保存在会话附件目录中的 `validate_protocol_report.py`、`protocol_validation.json`。这只证明文档引用和已有记录一致，**不是重新播放协议、执行项目单元测试或验证车机互通**。

可复核的现有项目测试入口（本次未执行）：`carlife-to-carplay` 的 `PhoneBluetoothHandshakeTest`、`AirPlaySenderFlowTest`、`SenderProtocolTest`；依赖及 SDK 完备后可分别运行 `:core-iap2:testDebugUnitTest` 和 `:core-airplay:testDebugUnitTest` 的对应 test selectors。测试中的本地模拟车机与真实原车不等价。
