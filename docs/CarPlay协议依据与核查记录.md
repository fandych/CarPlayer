# CarPlay 协议依据与核查记录

整理日期：2026-10-31。

本文件独立保存协议正文的依据范围、实现观察、核查状态、运行记录、代码定位与参考资料。协议正文只描述交互和数据格式；资料迁出不表示某个实现行为已成为所有设备的通用要求，也不表示完成实车互通或 MFi 合规验证。

下列原章节编号保留用于追溯整理前的记录，不是协议正文的新章节编号。

## 一、资料范围与证据等级

### 整理前主文档说明

> 版本：2026-10-31 · 结构复核与文档差异代码核验版  
> 范围：CarPlay 会话建立、USB/无线承载、iAP2 控制、AirPlay/RTSP 风格协商、认证、媒体和输入/车辆数据。本文为独立技术参考，不是 Apple/MFi 的规范文本。由于部分接口和认证细节受 MFi 规范限制，公开资料不能证明完整、唯一且跨版本的线上协议；凡无法由公开权威文件确认的细节，均标为实现观察或未知，不把单次记录提升为普遍要求。


> 确认状态：已完成本次文档结构与选定静态证据复核；没有新增实车互通、音视频质量或 MFi 合规测试。未公开/待实测内容仍保留，不将“最终版”解释为“全协议已验证”。

### 原第 1 章：阅读约定、证据等级与结论边界

#### 1.1 证据标签

- **[公开资料]**：Apple 面向公众的配件指南或公开标准明确写出的内容。引用范围仅限该资料实际覆盖的内容。
- **[多实现静态观察]**：多个公开实现的代码交叉检查结果。可证明所检查代码路径如此，不等同于 Apple 对所有设备的要求。
- **[单实现静态观察]**：只核对一个实现的具体代码路径；不能推断其它实现、设备或版本。
- **[实现注释]**：源码中的兼容性说明或测试描述，未在本次复核中重现；其证据强度低于实际报文记录。
- **[单次记录]**：既有的一次握手/测试记录中观察到的现象；不能推广到其它手机、车机、系统版本或连接方式。
- **[待实测/未公开]**：公开证据不足，需 MFi 资料、获授权抓包或真实设备互通测试才能确认。

“实现支持”不等于“协商成功”，“能力声明”不等于“建立了通道”，“收到成功状态”不等于“身份已经通过密码学验证”。

#### 1.2 能确认与不能确认的范围

可以说明协议分层、所检查实现中的 iAP2 消息/能力交换作用、AirPlay/RTSP 会话模式及其具体字段、实现所见的媒体流和数据格式，以及这些层之间不可混用的边界。这里的“公开实现可见”不表示相应 iAP2 消息 schema 已由 Apple 完整公开。

不能据此宣称：存在唯一 CarPlay 协议版本号；所有车辆采用完全相同的无线拓扑或握手顺序；公开资料完整定义了全部 CarPlay endpoint、命令、密钥派生与流格式；某个开源实现已经通过 MFi 或量产认证；静态分析等同于实车互操作验证。

## 二、运行记录与诊断建议

#### 3.5 一条已观察到的运行顺序（不是规范顺序）

既有的一次握手记录体现了几个关键事实：身份/无线配置、AirPlay 配对、初始控制 SETUP、媒体流建立之间有清晰阶段，但运行期 iAP2 认证与首帧交错；`RECORD` 也可早于显示流 SETUP。流程摘要如下：

| 阶段 | 本次记录中观察到的交互 | 结果/限制 |
|---|---|---|
| iAP2 建链与识别 | Link 同步；`0x1D00 → 0x1D01 → 0x1D02` | 完成该次身份/能力接受；不证明每台设备都用完全相同顺序 |
| 配件认证 | `0xAA00…0xAA05` 相关证书、challenge/response阶段 | 属于记录中的认证交互；状态消息不能替代验证签名/证书 |
| 无线配置/启动 | `0x5702 → 0x5703`、传输状态通知、`0x4300 → 0x4301` | 随后具备无线接入所需信息；该交换本身不等于媒体连接 |
| AirPlay身份 | 三次 `/pair-setup` 请求、两次 `/pair-verify` 请求，随后出现 `/auth-setup` | 仅说明该次连接走过这些请求；`/auth-setup` 不是统一必经步骤 |
| 控制与能力 | 初始 `SETUP → /info`，建立 timing/event 等会话参数 | 取得可选显示、音频和输入能力；能力声明仍需后续 SETUP 确认 |
| 会话推进与数据通道 | `RECORD`；之后 type 130 SETUP、模式状态更新 | 本次 `RECORD` 先于显示 SETUP；不推广为固定时序 |
| 显示输出 | 先 type 111，再 type 110；分别分配端口并发 codec config/首帧 | 证明显示目标分开协商；不证明每台车都有副屏，也不证明必先仪表 |
| 并行认证/运行 | type 110 首帧期间，type 130 tunnel 上仍出现 iAP2 认证交互 | 会话过程可并行/交错；不能把所有控制交换假设为首帧之前完成 |

#### 3.7 将流程落到实现日志

建议每个会话用单调时钟记录：阶段名、传输层、发起角色、消息命名空间/ID 或 RTSP method、CSeq、stream type/UUID、方向、协商端口、返回状态、socket连接、首个有效包/首帧及清理原因。对密钥、凭据、认证 payload、SSID 密码和可重放密文做脱敏；仅记录“认证验证成功/失败”的结果及失败阶段。通过这种状态轨迹，可以区分“没发现”“没建网”“控制连接失败”“SETUP未协商”“端口连不上”“媒体未解密/解码”与“输入已收但未执行”，避免用一个“CarPlay连接失败”掩盖不同故障。

## 三、实现对比与代码定位

对一套发送端实现与一套接收端实现进行静态比较，可归纳为以下限定结论：

1. **已对齐的常见路径**：配对完成后的主屏帧结构、屏幕加密方式、主要音频 RTP 路径及部分 event key/framing，在两端所检查分支中大体对应。这只能说明代码层相互接近，不能代替真实运行。
2. **未配对/弱安全路径存在条件性不兼容**：一个发送端分支在缺少持久共享 pairing key 时仍使用 AES-CTR 或明文 event 路径；另一个接收端分支仅接受已配对后的 ChaCha 加密事件路径。两端若走不同安全状态，不能假定可互通。
3. **认证验收强度不同**：发送端一侧对配件身份/签名的验证存在省略或宽松处理；这会造成安全保证不一致，即使消息往返成功也不能视为双向身份认证成立。
4. **辅助音频同步差异**：接收端当前某控制 socket 的处理路径会忽略其不支持的 UDP timing/sync 包；不能据此推出音频 RTP 主数据必然失败，但时间同步/音频质量需单独验证。
5. **尚未建立实测结论**：以上是静态代码差异，不代表固定的 Apple 设备行为、每次运行结果或已通过实车验证。需要有授权的双端测试、完整非敏感日志、音视频同步指标和安全负面用例才能确认影响。

#### 14.1 两份文档差异的代码核验结果

本次核验使用三个匿名快照标签：**R-A** 为另一文档所在目录的接收代码，**R-B** 为当前目录的主接收代码，**S** 为当前目录所查发送代码。标签不代表官方版本、认证状态或所有同类实现；文件名/行号用于定位本次代码事实，不能替代运行测试。

| 项目 | 代码确认结果 | 差异性质 | 关键定位（本次快照） |
|---|---|---|---|
| NAL 长度 | R-A 从 codec config 取长度宽度；R-B 固定四字节；S 写四字节配置和长度 | 真正的实现差异；S 与 R-B 在此参数上对齐 | R-A `ScreenStream.kt:137–153`；R-B `ScreenStream.kt:176–195`；S `VideoSender.kt:318,369–372` |
| iAP2 tunnel 方向 | R-A/R-B TCP 接收手机字节，Event 回传；S 的实际出站优先写 tunnel TCP | 所查分支对齐；此前仅凭读线程推断反向过强 | R-A `AirPlayIapTunnelStream.kt:15–75`；R-B `IapTunnel.kt:143–166`；S `VirtualIap2Link.kt:341–362` |
| 请求头 | S 配对请求实际加 HKP/PD；R-A/R-B 配对路由不显式强制检查这些头 | 构造事实与接收强制条件不同；403 仍属注释 | S `AirPlayClient.kt:2402–2418`；R-A `AirPlaySession.kt:346–353`；R-B `AirPlaySession.kt:572–579` |
| iAP2 线编码 | Link 9 字节、CSM 6 字节、参数 4 字节、完整检测标记与负和校验可核查 | 线格式对齐；不是完整官方 schema | R-A `Iap2LinkEngine.kt:270–275,643–685`；`Iap2Wire.kt:34,99–109` |
| session 描述 | 接收实现实际通告/分派 10/11/12，未显示任意 descriptor 动态重映射 | 协议处理原则与当前实现能力有差距 | R-A `Iap2LinkEngine.kt:441–443,590–594`；R-B `Iap2LinkChannel.kt:234–237` |
| 字段与宽度 | Identification 6/7 为配件发送/接收列表；group24 与 4301 group1 分开；4301 端口为 u32BE | 已核查字段对齐，另一文档细节可按此补入 | R-A `Iap2Messages.kt:73–101`；S `Iap2SenderSession.kt:950` |
| 反向控制标识 | R-A 把十六进制设备标识转十进制；R-B 只去冒号 | 真正的文本编码差异，不是等价转换 | R-A `CarPlayBonjour.kt:77–98`；R-B `CarPlayBonjour.kt:113–128` |
| 夜间模式 | R-A/R-B 有业务发送路径；S 无对应主题分派，只记录未知命令 | 接收实现有功能路径；所查发送实现未接入 UI 处理 | R-A `CarPlayHostActivity.kt:2200–2212`；R-B 同名文件 `5741–5788`；S `SessionController.kt:2489–2634` |
| 主题资产可用性 | 4300 group2 有布尔 decoder/消费，不是资产内容传输 | 可用性解码存在；不能推出皮肤或 RGB 同步 | R-A `Iap2Messages.kt:124–140`；R-B `Iap2WirelessControlClient.kt:251` |
| 封面文件 | 两边都有接收/回复/完成路径，顺序检查、容量和失败策略不同 | 实现差异；文件完成不等于最终 UI 输出 | R-A `Iap2FileTransferReceiver.kt:24–145,213–233`；R-B 同名文件 `35–127` |
| 控制/配对加密 | Pair-Verify 的密钥标签、nonce/AAD 和 M4 后切换在接收代码可核查；控制发送分片上限不同 | 基本线格式对齐；分片参数不同，安全验收另查 | R-A `AirPlaySession.kt:314–319`；R-B 同名文件 `519–524`；各 `ControlCipher.kt` |
| 音频与 Timing | PCM/AAC-LC/Opus 基础映射和音频 AAD 对齐；R-A 另有 AAC-ELD 映射；Timing 实际处理 210/211，音频 control 不做完整重传 | 部分对齐、部分实现差异；声明不等于 decoder/重传支持 | R-A `AudioStream.kt:106–114,155–160,199–261`；R-B 同名文件 `131–139,181–188,223–268`；两边 `NtpClock.kt` |

#### 14.2 认证算法对齐不代表验证强度对齐

两套接收的 `/auth-setup` 摘要/AES 分支与 Pair-Verify 响应处理可核查。所查发送的 Pair-Verify 在提供静态公钥时计算验签结果，但仅记录结果；未提供公钥时跳过该校验，未显示因 `valid=false` 终止的路径。Pair-Setup 的某身份验签也仅记录结果。接收 Pair-Verify 则在配对公钥缺失或签名不匹配时返回错误。

因此“算法、标签和往返消息对齐”只能说明所查数据计算/封装接近，不能写成双方身份已严格验证。所有这里的结论均是静态代码事实；本次没有新增设备运行或密码学负面用例测试。

## 四、验证状态与验收记录

#### 16.1 可复现的静态核验

- 交叉检查了多种公开协议实现的 framing、字段定义、状态机、流 handler 与消息方向；所有不具备 Apple 公共规范支撑的线格式均保留“实现观察”限定。
- 本地 Apple《Accessory Design Guidelines》PDF 元数据显示标题为 *Accessory Design Guidelines for Apple Devices*、Release R32，日期 2026-10-23，共 397 页。指南包含一般 USB NCM、iAP2 与 HID 配件主题，但不构成完整 CarPlay 视频/控制线协议规范。
- 既有报告中的静态引用校验检查了旧分析材料的链接与行号；该结果不代表此最终文档每个技术事实经过设备验证，也不覆盖本文件内容。

#### 16.2 尚未完成的验证

本报告没有执行 CarPlay 实车连接、USB/蓝牙/Wi-Fi 空口抓包、互操作构建测试、音频/视频质量测试或 MFi 合规验证。敏感认证交换不应在未授权设备上捕获或传播。因此“真实可靠”的范围严格限定为公开文档元数据/内容核对、公开实现静态交叉检查及既有测试记录观察；任何需要设备运行才能确认的结论都明确列为未实测。

#### 16.3 建议的互通验收矩阵

| 阶段 | 验收证据 | 失败定位 |
|---|---|---|
| USB/蓝牙连接 | 设备角色、接口/服务、可靠字节流 | USB role、描述符、权限、配对/RFCOMM |
| iAP2 Link/CSM | 同步完成、校验/序号正常、身份能力消息完成 | marker、checksum、分片、方向/endpoint schema |
| 网络及发现 | Wi-Fi 地址/路由、服务发现、邀请成功 | P2P/AP/已有网络状态、mDNS、IPv6/路由/端口 |
| 配对认证 | proof、签名、证书链及 AEAD 验证成功 | TLV state/error、身份绑定、方向 key/counter |
| RTSP 协商 | `/info` 能力与初始/流 SETUP 响应一致 | plist/header/CSeq/Content-Length/端口绑定 |
| 媒体 | 视频有效 config/帧、音频有效 RTP/codec、同步数据 | codec、AAD/nonce、丢包、timestamp、实际路由 |
| 输入/事件 | descriptor/report、命令 params 与动作一致 | 坐标映射、report ID、命名空间、模式状态 |
| 生命周期 | 暂停、切屏、断连/重连、TEARDOWN 清理正确 | 资源状态、线程/socket/key/订阅泄漏 |

#### 16.4 本次最终复核的确认范围

复核日期：2026-10-31。这里的“最终确认”指文档结构、已有静态证据与关键表达边界的复核，不是 Apple/MFi 认证或新增实车测试。

| 复核项 | 本次动作 | 确认状态与限制 |
|---|---|---|
| 文档组织 | 六个部分、连续章节/子节点、目录与内部锚点检查 | 文档结构确认；不构成协议一致性测试 |
| iAP2 配件认证方向 | 对照请求/响应 handler，修正时序图中证书、challenge、签名与结果的方向 | 代码路径确认；未执行证书链/实车验收 |
| Event/Timing | 对照 TCP listener 与 UDP socket 的分工，将时序图拆开表示 | 当前实现传输类型确认；不推广为全部 profile |
| 请求头 | 保留通用构造器与配对/信息/命令专用路径的差异；将注释中的 403 记录单独标注 | 静态构造与证据等级确认；未重现实车 403 |
| 既有分析证据 | 重新执行引用/行号及已有握手记录校验，无错误 | 覆盖旧分析材料的 794 个本地链接、748 个行号范围和选定记录断言；不是本文件所有事实的验证 |
| 公开指南元数据 | 重新读取本地 PDF 标题、Release R32、397 页及 2026-10-23 元数据日期 | 本地文件元数据确认；不是网站最新版本的在线确认 |
| 真实设备与质量 | 没有新增实车连接、空口抓包或音视频质量实验 | 待实测；不可标注“全协议验证通过” |

##### 16.4.1 待确认事项不得隐藏

- 不同手机/iOS/车机 profile 的精确握手顺序、认证分支与回退策略。
- 每个 endpoint 的完整 payload schema、枚举、错误码、扩展兼容和授权要求。
- 当前设备实际支持的 codec、拓扑、可选流和密钥切换点。
- 输入执行效果、音视频同步、丢包/重连行为与量产/MFi 合规性。

#### 16.5 本次两文档差异核验的边界

本次沿实际编码/解码与调用链核查了 NAL 宽度、type 130 iAP2 收发、请求头、iAP2 线格式与部分参数、反向探测、夜间模式/主题可用性、封面接收、配对加密以及音频/Timing。第 14.1 节给出逐项结果与关键代码位置，相关确认细节已补入第 5–11 章。

- **已确认**：所查代码路径是否存在、参数如何构造/读取、哪些分支仅记录或缺少处理，以及几项明确的实现差异。
- **已修正**：不能仅凭 tunnel 读取线程判定反向 TCP 业务；不能把 session 动态协商原则写成当前实现已支持任意 ID；不能把夜间模式回应写成 UI 已应用。
- **未确认**：这些分支在所有真实手机/车机上的可达性、实际互通、音视频/主题/封面最终呈现及完整官方 schema。本次未修改协议实现，也未新增实车测试。

## 五、参考资料

1. Apple, [Accessory Design Guidelines for Apple Devices (PDF)](https://developer.apple.com/accessories/Accessory-Design-Guidelines.pdf)。用于一般配件工程和接口范围；不能替代受限 MFi Accessory Interface Specification，也不能作为完整 CarPlay wire protocol。
2. Apple, [CarPlay developer information](https://developer.apple.com/carplay/)。用于公开 CarPlay 产品/开发范围，不公开完整连接协议。
3. Apple, [CarPlay Ultra announcement](https://www.apple.com/newsroom/2025/05/carplay-ultra-the-next-generation-of-carplay-begins-rolling-out-today/)。用于区分多屏与车厂系统集成的产品能力范围，不定义这里讨论的底层包格式。
4. RFC 9293, [Transmission Control Protocol (TCP)](https://www.rfc-editor.org/rfc/rfc9293)。仅用于 TCP 通用语义。
5. RFC 6762, [Multicast DNS](https://www.rfc-editor.org/rfc/rfc6762)。仅用于 mDNS 通用发现语义。
6. RFC 5054, [Using the Secure Remote Password (SRP) Protocol for TLS Authentication](https://www.rfc-editor.org/rfc/rfc5054)。用于识别 SRP 相关通用算法/参数；不证明某 CarPlay profile 必须使用该变体。
7. RFC 5869, [HMAC-based Extract-and-Expand Key Derivation Function (HKDF)](https://www.rfc-editor.org/rfc/rfc5869)。仅作 HKDF 通用定义。
8. RFC 7748, [Elliptic Curves for Security](https://www.rfc-editor.org/rfc/rfc7748)。仅作 X25519 通用定义。
9. RFC 8032, [Edwards-Curve Digital Signature Algorithm (EdDSA)](https://www.rfc-editor.org/rfc/rfc8032)。仅作 Ed25519 通用定义。
10. RFC 8439, [ChaCha20 and Poly1305 for IETF Protocols](https://www.rfc-editor.org/rfc/rfc8439)。仅作 ChaCha20-Poly1305 通用定义。
11. Apple MFi 的 Accessory Interface Specification 及认证要求：受限资料。本报告没有将未获授权/未公开内容伪装成公开规范。

## 六、原正文中的实现限定与兼容性备注

以下保留整理前包含实现来源、局限或兼容观察的段落；其中的字段与数值须结合原分支解释。

### 原第 4 章相关备注

1. **枚举与接口发现**：USB host 读取设备/配置/接口/端点描述符并选择可用配置。VID/PID、配置编号、endpoint 地址等可能随设备和系统改变，不应将单个实现观察写成固定值。
2. **可选模式切换/重新枚举**：某些实现可能发送设备特定控制请求后重新枚举；不是已证明的所有设备必经步骤。底层 USB token、握手、调度由 USB host controller/操作系统处理，应用层代码通常看不到完整总线事务。
3. **USBMUX 服务字节流**：在 USB 上通过 USBMUX 版本交换、逻辑连接等方式访问 Lockdown 服务端口。某一接收实现使用 USBMUX version 2 和端口 62078；这些是实现/设备路径观察，不应硬编码为所有连接的唯一值。
4. **Lockdown pairing/session**：如尚无有效配对，需走配对/信任流程；再启动 Lockdown session。若服务要求 SSL，则在该逻辑服务流执行 TLS。随后请求 CarKit 服务并使用返回的实际端口；某些会话可在服务通道再次启用 TLS。
5. **iAP2**：CarKit 字节流上启动 iAP2 Link，同步成功后在控制会话承载 CSM 识别、能力、认证及控制消息。
6. **CDC NCM 网络**：USB NCM NTB 承载 Ethernet datagram；网络层可能承载 IPv6/TCP/UDP。RTSP 风格控制和媒体/IP 数据走该网络，不是将 H.264 帧直接写入 iAP2 endpoint。
7. **AirPlay/RTSP 会话**：在网络地址上发现/邀请接收端，协商会话与动态媒体端口，再单独启动显示、音频和数据流。

### 原第 5 章相关备注

多实现中可见经典蓝牙/BR-EDR、RFCOMM 承载早期 iAP2 控制，后续交换 Wi-Fi 配置/启动信息；显示与多数实时媒体随后走 Wi-Fi 上的 IP/TCP/UDP。不能将此描述成“视频经 BLE GATT 传输”。BLE、经典蓝牙、RFCOMM 与 Wi-Fi 的选择以实际设备和 profile 为准。

在公开实现/端点目录中观察到的常见 Wi-Fi 配置相关 ID：

方向/字段来自实现中的 iAP2 endpoint 声明和 handler [多实现静态观察]，不是这里可引用的完整 MFi 定义。无线建立可能与 iAP2 消息、Bonjour/mDNS、接收端邀请、网络关联和 IP 配置并行或交错；必须以真实状态与报文确认，不可假设唯一固定的先后顺序。

所查接收代码实际发布 `_airplay._tcp`；TXT 生成路径包含 `deviceid`、`features`、`flags`、`model`、`srcvers`、`protovers`、`pi` 和 `pk`，SRV 提供目标和端口。它们是发现提示，不能替代会话能力、身份验证或流 SETUP。

所查接收代码会发现手机的 `_carplay-ctrl._tcp` 并发送 **`GET /ctrl-int/1/connect HTTP/1.1`**，携带 `AirPlay-Receiver-Device-ID`。这是车机 → 手机控制服务的反向探测，不是主 AirPlay 控制连接，也不是 `/command`。

两套接收代码的 Header 值构造不相同：一套把 12 位十六进制设备标识解析为数值，再输出十进制字符串；另一套仅移除冒号，保留标识文本。所查设备控制接口也存在六字节标识转数值、再以无符号十进制输出的路径。**去冒号文本与十进制数值字符串不是等价编码**，应按当前接收服务约定确认，不能混用。

所查发送端接受该 GET、读取 Header 并返回空体 `200`；这一路径未显示对设备标识进行身份匹配拒绝的处理。因此探测响应仅能证明该请求被接收，不能证明车机身份已验证或媒体连接已完成。

### 原第 6 章相关备注

- **Link 同步**：marker/detection、SYN 参数协商、ACK 确认进入可传输状态；Link 还有序号、确认号、会话和校验等可靠传输信息。它不是 TCP SYN/ACK。
- **Link frame**：多个实现观察到固定字段结构，包含 marker、长度、flags、sequence/ack、session ID、header checksum；有 payload 时还存在 payload checksum。特定实现使用 9-byte header。字段宽度、checksum 覆盖范围和协商值应依对应协议实现/schema 解码，不得凭一次采样改写成所有版本固定约束。
- **CSM**：在协商的控制 session 上承载消息。所检查实现的 framing 使用 `0x4040` 标记、消息总长度、16-bit message ID、参数列表。参数项按长度、参数 ID、value 编码；参数 ID 可重复，也可嵌套分组，不能无损地直接压成键值 map。
- 一次 socket read/USB transfer/RFCOMM read 不必等于一个 Link frame 或 CSM。实现必须缓冲、按长度重组、处理分片、校验和重传状态。
- control session ID、传输 session 数值与 Link 版本须通过实际协商取得，不可跨设备硬编码。

##### 6.1.1 已核查的线格式与校验

以下为两套接收代码中的实际编码/解码路径 [多实现静态观察]，不是跨版本的完整官方定义：

协议处理应依据当前 session 描述与能力；但所查接收代码通告并分派固定的控制/扩展/文件 session `10/11/12`，没有证据表明已按任意对端 session descriptor 动态重映射。因此“session 需协商”是处理原则，不能写成这些实现已经支持任意 session ID。文件通道使用 12 的结论也只限于这些代码路径。

| ID 范围/示例 | 功能族 | 典型功能，不代表每台车必需 |
|---|---|---|
| `0x4300`–`0x4301` | CarPlay availability/start session | 手机声明可用；配件请求/启动会话并提供所需连接信息 |
| `0x5000`–`0x5003` | Now Playing | 订阅/停止更新、媒体信息更新 |
| `0x5200`–`0x5204` | Route Guidance | 路线/转向/车道信息订阅与更新，可用于结构化仪表/HUD输出 |
| `0x4154`–`0x4161` | Communications/Call state | 通话状态、接听/结束/切换/DTMF 等，取决于双方支持 |
| `0x4C00`–`0x4C09` | Media Library | 媒体库信息订阅、选择与播放控制 |
| `0x4E09`–`0x4E0E` | Device notifications | 设备/语言/时间/传输状态更新 |
| `0x6800`–`0x6803` | HID/USB-host related | 按 endpoint 定义传 HID 报告或控制 HID 生命周期 |
| `0xAE00`–`0xAE02` | Power | 电源更新订阅/通知 |
| `0xA100`–`0xA101` 等 | Vehicle status（实现观察） | 车辆状态请求/更新；不是所有 CarPlay 连接都有此数据 |
| `0xFFFB`（实现观察） | Location/NMEA 类数据 | 某些实现中的定位载荷路径，需按实际 endpoint/schema 确认 |

端点 ID 不是全协议全局通用“控制码”。每个方向的消息列表、已注册 handler、schema、required 字段和实际支持情况需分别核实。endpoint 声明目录本身不是 Apple 授权的完整码表；本文列举的是与本文功能相关、在公开实现中可交叉检查的族。

#### 6.5 已核查的字段宽度与参数作用域

以下是所查编码器/解码器的实现事实，不代表完整 endpoint schema：

| 消息/参数路径 | 实际编码或解释 | 不能混用的边界 |
|---|---|---|
| `0x1D01` 顶层参数 6 / 7 | 分别为**配件发送 / 配件接收**的消息列表，成员为 u16BE | 方向以配件为参照，不是当前 socket 的读/写方向 |
| `0x1D01` group 24 | Wireless CarPlay transport 描述 | 不是 `0x4301` 的 wireless group 编号 |
| `0x1D01` Bluetooth group 17 子参数 3 | 原始 6 字节 MAC | 不带冒号或 NUL；不能按字符串解码 |
| `0x4301` group 0 / 1 | 分别是 wired / wireless 参数分支 | 有线与无线不能套用同一子参数 schema |
| `0x4301` 顶层参数 2 | 端口以 u32BE 编码；所查发送端按 `asU32()` 解码 | 端口值较小也不能擅自改为 u16 |
| `0x4301` 顶层参数 3 / 4 / 5 | 设备标识 / 公钥文本 / 版本文本 | 设备标识、公钥和协议/软件版本各自解释 |
| iAP2 字符串 | 所查字符串 codec 使用 UTF-8 与末尾 NUL | NUL 计入参数长度；原始 Data 不自动按字符串解码 |
| transport identifier 中的 MAC | 对应通知路径可使用末尾 NUL 的文本 | 与 Identification 中原始 MAC 的封装不同 |

两套接收代码均有实际文件接收、分块重组和回复处理，不是仅有常量或消息目录。Now Playing 属性 26 读取为 1 字节 transfer ID，关联文件通道上的图像内容；这些代码通告并使用 file session 12。

所查包以 `transferID:u8 | control:u8 | data` 起始；Setup 的元数据包含文件长度 u64BE 与文件类型 u16BE，图像路径使用类型 2。数据控制值中可见 `0x80/0x00/0x40/0xC0` 对应首块/中间块/末块/单包首末，必须结合 transfer ID 与接收状态解析，不能映射成 CSM 成功码。

两套接收状态机并不相同：一套显式检查 First/Last 顺序，包含完成/失败回复、30 秒超时和 16 MiB 上限；另一套按 opcode/Last 标志处理，使用 2 MiB 上限及不同取消/失败策略。以上限制是实现常量，不是统一协议上限。收到完整文件、通知 listener 或更新媒体桥接，不等于最终车机界面已成功显示封面。

### 原第 7 章相关备注

| 机制 | 所在层 | 主要用途 | 不等于 |
|---|---|---|---|
| USB Lockdown pairing/session/TLS | USBMUX 服务流 | 设备信任、启动受限服务、保护服务连接 | iAP2 MFi 或 AirPlay 配对 |
| iAP2 MFi accessory authentication | iAP2 endpoint | 配件证书与 challenge-response 身份验证 | Lockdown 配对或 AirPlay pair-verify |
| AirPlay `pair-setup` | RTSP 控制 + TLV8 | 建立并保存双方长期配对身份 | 单次媒体流 SETUP |
| AirPlay `pair-verify` | RTSP 控制 + TLV8 | 使用既有配对身份证明双方并派生控制密钥 | MFi accessory authentication |
| `/auth-setup` | RTSP 控制的特定认证分支 | 某些实现中的 MFiSAP/配件身份认证 | pair-setup/verify 的替代名 |

TLV8 基本元素为 `type (1 byte) | length (1 byte) | value (length bytes)`，可重复分片/拼接的类型需按 TLV 规则处理。**Type 与 value 是不同含义**：例如 pair-setup/pair-verify 实现中 `0x06` 是 State 的 TLV type；其 value 才是 M1、M2 等状态值。`0x07` 是 Error 的 TLV type；error value 才是具体错误。`0x00` 在某实现中用作 Method 的 TLV type，它不是全局成功码。

所检查 pairing 分支可见以下流程 [单实现静态观察；算法参数并非 Apple 公共配件指南定义]：

| 状态 | 方向 | 作用（实现观察） |
|---|---|---|
| Pair-Setup M1 | 手机 → 配件 | 提交 state=1/方法 |
| M2 | 配件 → 手机 | state=2，SRP salt 与服务端公开参数 |
| M3 | 手机 → 配件 | state=3，客户端公开参数与 proof |
| M4 | 配件 → 手机 | 校验 proof 后 state=4/server proof；失败应带错误 |
| M5 | 手机 → 配件 | state=5，加密的长期身份、公钥、签名 |
| M6 | 配件 → 手机 | state=6，加密的配件身份、公钥、签名，保存配对关系 |

一份实现使用 SRP-6a、RFC 5054 3072-bit group、SHA-512；身份部分使用 Ed25519 与 HKDF-SHA512、ChaCha20-Poly1305。Pair-Verify 的一份实现使用临时 X25519、Ed25519 签名、HKDF-SHA512，并按读/写方向派生 control key。以上算法/参数是实现分支事实，不应表述为每个 CarPlay 设备必然采用的标准 suite。任何 proof、签名、证书链或 AEAD tag 验证失败都必须终止/拒绝该认证阶段，而非设置已验证状态。

M1–M4 指所检查实现中的 TLV state，不表示四次客户端请求。下表区分实际交换的材料与应完成的验证动作；部分发送端代码并未严格拒绝验签失败，不能将表中的验证要求误写为该实现已通过验证，差异见第 14 章：

#### 7.3 `/auth-setup` 实现观察

两套所查接收实现均检查请求为 `version=0x01` 加 32-byte X25519 公钥，并基于共享密钥生成签名加密材料。普通 MFi 分支的响应为临时公钥、u32BE 证书长度及证书、u32BE 签名密文长度及签名密文；BAA 分支另有证书/中间证书封装，不应套用单证书布局。

以上请求长度、摘要选择、字节序和响应布局是代码分支事实，不是 Apple 公开 PDF 定义的通用规范。验证方仍须检查身份、证书与签名；正确响应长度或成功状态不是密码学验证结果。

- 控制连接、屏幕、音频和 data stream 可能具有不同的派生标签、key、nonce/counter 和生命周期。不能复用某个流的密钥或计数器到另一个流。
- 加密方向分别维护读/写 key 与 nonce/counter；发送端和接收端对方向的命名取决于各自角色。
- 多实现中可见 Pair-Verify 后控制帧采用长度前缀 + AEAD ciphertext/tag；具体长度字节序、AAD、nonce 与切换点必须从当前 profile/实现和会话协商中确认。
- TLS record、AirPlay 控制加密帧、视频 AEAD、音频 RTP 密文不是同一种加密封装。
- 不记录或外传配对私钥、session secret、密码、MFi 私有材料、真实 Wi-Fi 凭据或可重放认证 payload。

##### 7.4.1 所查控制/Event AEAD 的具体封装

读写 key/counter 独立；解密成功后按完整 AEAD frame 推进读 counter，而不是按 TCP read 或 CSeq 推进。所查接收控制循环先写出 Pair-Verify M4 响应，再启用控制 cipher；不能把 M4 提前按尚未切换的密钥状态加密。

两套接收控制 cipher 的发送分片上限为 `0x4000` 字节，所查发送端为 `1422` 字节；这是实现参数差异，不是由 TCP/以太网 MTU 自动得出的统一协议限制。两类实现的基本 AEAD 帧布局相同，分片上限不同也不能单独证明不能互通。

所查配对后的屏幕/音频路径以共享密钥为输入，salt 为 `DataStream-Salt` 与 connection ID 的十进制文本拼接，输出方向使用 `DataStream-Output-Encryption-Key`；iAP2 tunnel 使用自己的 seed 构造 salt。**connection ID 与 seed 不能互换。**具体麦克风方向还需核查对应输入流的调用，不能从主音频方向直接倒推出所有实现均支持。

### 原第 8 章相关备注

在不同实现中可见 `deviceID`、`model`、`sourceVersion`、`sessionUUID`、`timingPort`、`features`、低功耗保活参数等。字段缺省、类型和编码需按 plist schema 解码。`protocolVersion` 若在某实现的 `/info` schema 中出现，只能解释为该 schema 的字段；`sourceVersion` 通常是发送端软件/SDK 信息。二者都不等于一个已证实的全局 CarPlay 版本协商号。

| `type` 字符串 | 常见方向/动作（实现观察） | 处理边界 |
|---|---|---|
| `changeModes` | 配件请求 app/resource mode 变化 | 更新资源仲裁，不等于媒体流已建立 |
| `modesChanged` | 发送端通知资源/app state 快照变化 | 只按模式状态处理；不要自动重连全部流 |
| `hidSendReport` | 发送 HID report | 依 HID UUID/descriptor/report ID 解码 |
| `hidSetInputMode` | 更新 HID 输入模式 | 枚举只在该字段空间有效 |
| `requestSiri` | 请求 Siri 预热、按下或释放动作 | Siri 控制信号与麦克风音频分开处理 |
| `setNightMode` | 配件通知夜间模式，`params.nightMode` 为 Boolean | 所查发送端没有专用 UI 处理分支；响应不等于主题已应用 |
| `requestUI` | 请求显示某 UI/URL（实现中可选） | 校验 profile/显示目标，不推断独立流 |
| `forceKeyFrame` | 请求关键帧 | 不代表 codec 切换 |
| `mediaControl` 等 | 媒体控制动作 | 依 plist params 和会话能力，不与 iAP2 ID 混用 |

下表的请求构造属于 **[单实现静态观察]**，兼容性描述属于 **[实现注释]**；不是 Apple 对所有设备的通用强制头清单。尤其 `X-Apple-HKP` 与 `X-Apple-PD` 的要求来自特定配对实现及其对特定车机的兼容描述，不能泛化成所有 RTSP 请求都要加。

| 请求 | `Content-Type` / body | 额外 Header | 发送端观察到的处理要点 |
|---|---|---|---|
| `POST /pair-setup` | `application/pairing+tlv8`；body 为 TLV8 | `X-Apple-HKP: 2` | 该发送端代码明确添加；实现注释记录：特定车机曾对使用默认 `application/octet-stream` 且缺少配对专用头的请求返回 `403`；该观察不能单独归因于某一个头 |
| `POST /pair-verify` | `application/pairing+tlv8`；body 为 TLV8 | `X-Apple-HKP: 2`、`X-Apple-PD: 1` | `X-Apple-PD: 1` 只在 pair-verify 分支添加；不能挪到 pair-setup 或全部 RTSP 请求 |
| `GET /info`（控制连接） | `application/x-apple-binary-plist`；body 是编码后的空 plist dictionary，不是零字节 | 无专用头 | 该实现注释记录：特定旧固件对空 body 或错误 Content-Type 可返回 400/455 |
| 独立短连接 `GET /info` 探测 | `application/x-apple-binary-plist`；空 plist dictionary | 使用该短连接自己的 `CSeq: 1`；同时有 `User-Agent` | 该路径不共享已建立控制连接的 CSeq；探测结果不取代会话内协商 |
| 初始 `SETUP /setup`、媒体/数据 `SETUP /`、`RECORD /` | `application/x-apple-binary-plist`；body 为 binary plist | 无额外认证头 | path 与 body schema 都应按对应方法/设备 profile；不能因都叫 SETUP 就复用同一 body |
| 控制连接 `POST /command`（例如 `modesChanged`；特定会话路径也可能用其承载 `iAPSendMessage`） | `application/x-apple-binary-plist`；body 为 binary plist | 无专用头 | 使用通用构造器；命令内容在 plist `type`/`params`，不是自定义 RTSP header |
| `POST /feedback` | 此发送端当前通过通用默认值发送 `application/octet-stream`，body 长度 `0` | 无专用头 | 这是具体实现写法，不足以证明所有接收端都要求此 Content-Type |
| `GET_PARAMETER` / `SET_PARAMETER` 音量 | `text/parameters`；body 如 `volume` 或 `volume: <dB>` | 无专用头 | 参数文本 body 与 plist、TLV8 不同 |
| 独立 Event socket 上 `POST /command` | `application/x-apple-binary-plist`；body 为 binary plist | 手工构造 `CSeq`、`Content-Length`；此发送路径未写 `User-Agent` | 它绕过控制连接通用请求方法；勿把某一路径的完整头集合误当全局强制模板 |

所查两套接收配对路由根据路径进入 handler，直接将请求 body 交给 TLV 处理；这些路由没有显式检查 `X-Apple-HKP` 或 `X-Apple-PD`。因此发送端确实添加这两个 Header，不等于这些接收 handler 把它们作为强制条件，更不等于全部真实车机具有同一要求。特定车机 `403` 的描述仍归为实现注释，未在本次重现。

### 原第 9 章相关备注

**结论 [多实现静态观察]：** 在所检查的实现中，主屏与副屏显示流是独立协商对象；Dock、Dashboard 等 UI 区域没有各自对应的必需视频流。Apple 公开配件设计指南不提供完整显示流目录。

#### 9.2 流类型索引（实现观察，不是完整官方码表）

| Stream type | 多实现中常见含义 | 必须同时检查 |
|---:|---|---|
| 96 | 兼容/旧式音频 | legacy audio 描述、格式及方向 |
| 100 | 主实时音频 | `audioType`、`audioFormat`、`input`、数据/控制端口 |
| 101 | 另一音频用途/资源 | 实际协商的方向与音频类型 |
| 102 | 高质量主音频 | 实际 codec 与采样参数，不只看编号 |
| 103 | 可选缓冲音频 | 是否声明/启用 buffered-audio 控制能力 |
| 104–109 | 较新/可选音频及冗余变体 | profile 与能力交集；仅看数值不足以解释方向 |
| 110 | 主屏显示 | display UUID、连接 ID、codec config、动态 dataPort |
| 111 | 可选第二显示/仪表类显示 | 独立显示 UUID、SETUP、dataPort 与显示能力 |
| 130 | 数据流 | `clientTypeUUID`、profile、stream ID 与专用端口/密钥 |

表中数值及业务来自多个实现中的类型声明/handler [多实现静态观察]，不构成 Apple 完整公开定义。尤其 `type=130` 不是单一业务：iAP2 中继、车辆数据、UI 同步、视频控制等路径可能依 `clientTypeUUID` 或 profile 区分。

### 原第 10 章相关备注

#### 10.1 屏幕视频（实现观察）

所查接收实现采用 **128-byte header**：offset 0 的 `u32 LE` body 长度、offset 4 的 opcode、后续字段含时间信息；opcode 0 表示视频帧，opcode 1 表示 codec config。所查已配对分支对视频帧使用 ChaCha20-Poly1305，header 作为 AAD，按连接维护 frame counter；配置帧可包含 `avcC`（H.264）或 `hvcC`（H.265）记录。

**NAL 长度宽度存在已确认的实现差异：**一套接收代码从 `avcC[4]` 或 `hvcC[21]` 的低两位计算 `lengthSizeMinusOne + 1`，支持该路径的 1/2/4 字节长度并拒绝保留值 3；另一套接收转换函数固定按 4-byte big-endian 读取。所查发送端写入 `avcC` 的长度宽度为 4，并实际写出四字节 NAL 长度。因此该发送路径与固定四字节接收路径在长度宽度上对齐，但不能推广为所有视频配置都固定四字节，也不能仅凭这点宣称完整视频互通已验证。

**边界：**128-byte header/opcode/AEAD 细节是代码实现观察，不是 Apple 公开配件指南中的通用规范；没有证据支持把所有 CarPlay 视频都描述成 RTP。视频 TCP socket、RTSP control socket 与 type 130 socket是不同连接。

- `type` 是流用途编号；`audioType` 表示具体音频业务/用途；`audioFormat` 通常是位掩码或 profile 值。三者不能互换。
- 公开实现中的格式能力可含 PCM 多采样率/位深、AAC-LC、AAC-ELD、Opus、ALAC 等；枚举中出现某 codec 不代表当前实现能编码/解码它，也不代表对端接受。
- 实际使用格式需结合 `/info` 能力、SETUP 中的 `audioFormat`、采样参数、通道数、输入标志及最终响应。不能将 CarPlay 说成固定 AAC 或所有音频流一种格式。
- 实时音频常见 UDP/RTP 承载；实现可另开 control/timing socket。RTP sequence/timestamp、RTSP CSeq、iAP2 sequence 互不相同。
- 音乐/导航/提示音/电话下行一般是手机 → 车机；麦克风上行是车机 → 手机。Siri 的按钮/动作命令与麦克风音频数据需分离处理。
- buffered audio 与低延时 RTP audio 是不同用途；`SET...`/anchor/flush 等控制方法仅在对应能力启用时处理。

##### 10.2.1 已核查的音频格式位

两套接收格式映射中，下列 PCM/AAC-LC/Opus 值对齐 [多实现静态观察]；这些是所查映射，不是完整官方格式表或对所有 decoder 的能力保证。

| 格式位 | 所查映射 |
|---|---|
| `0x4 / 0x8` | PCM 8 kHz，mono / stereo |
| `0x10 / 0x20` | PCM 16 kHz，mono / stereo |
| `0x40 / 0x80` | PCM 24 kHz，mono / stereo |
| `0x100 / 0x200` | PCM 32 kHz，mono / stereo |
| `0x400 / 0x800` | PCM 44.1 kHz，mono / stereo |
| `0x4000 / 0x8000` | PCM 48 kHz，mono / stereo |
| `0x400000 / 0x800000` | AAC-LC 44.1 / 48 kHz，stereo |
| `0x10000000 / 0x20000000 / 0x40000000` | Opus 16 / 24 / 48 kHz 的格式/时钟档位；所查解码映射可使用 48 kHz 输出 |

能力集合可使用位 OR；选定流的格式仍应结合 SETUP 与具体 schema 判断。一套接收映射额外包含 AAC-ELD 分支，另一套没有该分支；遇到未知格式时，两者还存在回退到 PCM 44.1 kHz stereo 的代码。这种默认映射不是未知 codec 被支持的证据，不能据此声称所有广告格式均能实际播放。

##### 10.2.2 所查实时音频 AEAD 与控制处理

两套接收路径均按 `RTP header[12] | ciphertext | tag[16] | nonceSuffix[8]` 拆包；AEAD 的 AAD 是 RTP header 的字节 **4–11（timestamp + SSRC）**，nonce 是四字节零与尾部八字节 suffix 拼接。所查发送端也使用这一 AAD/布局；因此此前对 AAD 的笼统描述可在这些路径中具体化，但不能推广到其它兼容分支。

两套接收音频 `controlPort` 循环仅接收并丢弃数据，未显示解析/处理完整重传控制的路径；不能因端口存在就认定 `0xD5/0xD6` 重传已经实现。Timing 的专用请求/响应在另一 UDP handler 中处理。

Timing port 用于会话媒体时钟同步，不等同于媒体 RTP 负载或互联网 UDP/123 公共 NTP 服务。所查两套 Timing handler 实际处理类型字节 `210/211`（`0xD2/0xD3`）的 32 字节请求/响应：offset 8/16/24 是 NTP 风格 originate/receive/transmit 时间字段，响应回显请求的 transmit 值作为 originate，并据此估算时钟偏移与 RTT。

这不是通用 48 字节 NTP 报文；RTP 音频 timestamp 使用采样时钟域，也不能直接当墙钟毫秒。`212–214` 的完整 time-announce/重传行为不能从该 Timing handler 推导，所查音频 control 循环也没有实现完整对应处理。应按当前端口、profile 与已实现 handler 解码。

对 tunnel 还要区分外层 TCP、加密长度帧、内部 package header、iAP2 Link 与 CSM。所查 iAP2 tunnel 为 `length:u16LE | AEAD ciphertext/tag`，内层有 32 字节 package header，offset 0 为 u32BE 总长，offset 16 的 `comm` 表示该 iAP2 载荷分支。一次 TCP read 不能直接当作一条 CSM。

两套所查接收 adapter 的实际分工是：**手机 → 车机的 iAP2 link bytes 从 type 130 TCP 读取；车机 → 手机的 bytes 经 Event `/command` 的 `iAPSendMessage` 发送。**这是该 iAP2 tunnel 分支的代码路径，不代表全部 type 130 业务都采用这一方向。

所查发送端虽然创建了 tunnel 读取线程，但它同时实现 TCP 写入；虚拟链路在 tunnel 可用时，优先调用该写入方法。若无 tunnel，另按状态经主控制 `/command` 或 Event 发送。因此不能只凭 `startReading()` 推断“此发送端必须反向使用 type 130”；仅有读取线程也不能证明车机实际通过该 TCP 回传。

此前比较中对“type 130 反向方向”的推断需据此收紧：已确认的是实际出站 TCP 与对端入站 TCP 对齐，以及 Event 回传路径存在；反向 TCP 是否有真实对端数据仍待记录/运行验证。

### 原第 11 章相关备注

所查接收端有实际业务调用：车机主题状态变化/会话同步时发送 `setNightMode`，其 `params.nightMode` 为 Boolean。该命令表达夜间模式，不传 RGB、色板或完整皮肤。iAP2 `0x4300` 的 group 2 子参数 0 则是**手机 → 车机**的 `themeAssetsAvailable` 布尔可用性字段，已存在实际 decoder/消费路径，不是仅有目录声明；它不承载主题资产本体。

所查发送端 Event `/command` 入口先回应 `200`，再分派命令；其业务分派没有 `setNightMode` 分支，进入默认日志路径，没有读取 `params.nightMode` 并切换 UI 的专用处理。因此该接收/发送组合中的“协议请求已回应”不能写成“手机主题已应用”。两端源码路径已确认，实车 UI 效果仍未验证。

### 原第 12 章相关备注

| 数值例子 | 所属命名空间 | 实现中的含义示例 | 正确处理 |
|---|---|---|---|
| `0x00` | Pair-Setup TLV type | Method 字段类型 | 读取 length/value；不是成功码 |
| `0x06` | Pairing TLV type | State 字段类型 | 解出 value 再判断状态 |
| `0x07` | Pairing TLV type | Error 字段类型 | 解释错误 value；不是 HTTP status |
| `0` | 视频帧 header opcode | 某实现的 VideoFrame | 只在该帧格式/版本上下文解释 |
| `1` | 同一帧 header opcode | 某实现的 VideoConfig | 解码器配置数据，不是“成功” |
| `0` | HID `hidInputMode` enum | 某实现的 Default | 仅按该字段 enum 解码 |
| `0` | ChangeModes Entity/AppState/SpeechMode enum | 某些类型中的 None/Invalid | 每个字段单独按 enum 解释 |
| `0` | 某 response 的 status 字段 | 某实现注释中的 no-error | 只对这一字段/消息有效 |
| `0` | StreamType | 某些实现的 Invalid | 不能映射到视频 opcode 0 |
| `0x4301` | iAP2 message ID | CarPlayStartSession | CSM ID，不是 AirPlay Stream type |
| `110` | RTSP stream type | 多实现中的 Screen | 不是 iAP2 endpoint 或 RTP payload type |
| RTP sequence | RTP header 字段 | 包序号 | 与 CSeq、iAP2 sequence、frame counter 分开 |

## 七、分离记录

- 整理前正文 SHA-256：`9414fb976768c074d0546c5584ce6285956baa77e0c334e6d01ca93e85cba319`。
- 第 1 章改为协议范围与术语约定；运行记录、代码对比、验收记录和参考资料移至本文件。
- 正文保留消息方向、字段宽度、请求头、认证状态、媒体 framing、适用 profile 与能力协商条件。
- 主文档不再包含资料引用、核查结论、代码文件/行号、匿名代码快照或具体实现的缺失功能记录。
- 实现特有的分片/容量/超时参数留在本文件，不提升为通用协议常量。
