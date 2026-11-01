# CarPlay iAP2 控制码字典（所选源码 catalog）

> 来自 DiPlay 的 151 个端点声明：61 个具名、90 个内联。它包括一般 iAP2 能力，不代表全部都是 CarPlay 必选功能或均有 handler。方向和 confidence 是本地 catalog metadata，不是 Apple 官方授权说明。

配套：[控制码、认证及媒体格式详解](CarPlay控制码认证与媒体格式详解.md)；[CSV](CarPlay-iAP2-endpoints.csv)。

## 阅读和双端处理规则

- IPHONE_TO_ACCESSORY：手机角色生成/发送，配件接收；ACCESSORY_TO_IPHONE：配件生成/发送，手机接收；BIDIRECTIONAL：依业务和会话状态处理。socket 的 client/server 身份不改变这一方向。
- 有字段 schema 时按所列类型、required、repeatable 及分组路径解析；没有 schema 只说明本地没有完整 typed 定义，不能认定 body 为空。
- 字段 0x0000 在每条消息/嵌套分组中独立命名；不是全协议通用成功码。
- 源码引用采用词法扫描，可能是常量、构造器、能力声明或日志；**不能自动认定该代码就是完整 handler**。真正执行过程见配套详解的核心流程与处理矩阵。
- 未定位的方向/行为不猜测；未知/未实现请求不得伪造成功或认证通过，应用需保留边界和必要的错误/超时路径。

## 全部端点索引

| ID | 名称 | 功能组 | 方向 | Schema 顶层字段数 | 声明位置 |
|---|---|---|---|---:|---|
| 0x0000 | pingHandler | Test | 配件 → 手机 | 0 | [L553](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L553-L553) |
| 0x0001 | userNotificationHandler | Test | 配件 → 手机 | 0 | [L554](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L554-L554) |
| 0x0004 | sendPingAccHandler | Test | 配件 → 手机 | 0 | [L555](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L555-L555) |
| 0x0005 | pingAccHandler | Test | 配件 → 手机 | 0 | [L556](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L556-L556) |
| 0x00B0 | oobBtPairing_startPairing | Other endpoints | 手机 → 配件 | 0 | [L861](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L861-L861) |
| 0x00B1 | oobBtPairing_accessoryInfoHandler | Other endpoints | 配件 → 手机 | 0 | [L862](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L862-L862) |
| 0x00B2 | oobBtPairing_pairingLinkKeyInfo | Other endpoints | 手机 → 配件 | 0 | [L868](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L868-L868) |
| 0x00B3 | oobBtPairing_completionInfoHandler | Other endpoints | 配件 → 手机 | 0 | [L874](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L874-L874) |
| 0x00B4 | oobBtPairing_stopPairing | Other endpoints | 手机 → 配件 | 0 | [L880](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L880-L880) |
| 0x0B00 | oobBtPairing2_startPairing | BLE and OOB pairing | 手机 → 配件 | 0 | [L828](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L828-L828) |
| 0x0B01 | oobBtPairing2_accessoryInfoHandler | BLE and OOB pairing | 配件 → 手机 | 0 | [L829](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L829-L829) |
| 0x0B02 | oobBtPairing2_statusHandler | BLE and OOB pairing | 配件 → 手机 | 0 | [L835](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L835-L835) |
| 0x0B03 | oobBtPairing2_stopPairing | BLE and OOB pairing | 手机 → 配件 | 0 | [L836](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L836-L836) |
| 0x0D00 | StartRoadObjectDetection | Other endpoints | 手机 → 配件 | 0 | [L881](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L881-L881) |
| 0x0D01 | RoadObjectDetectionUpdate | Other endpoints | 手机 → 配件 | 0 | [L882](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L882-L882) |
| 0x0D02 | StopRoadObjectDetection | Other endpoints | 手机 → 配件 | 0 | [L883](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L883-L883) |
| 0x10DA | destinationSharing_StartDestinationInformation | Destination sharing | 配件 → 手机 | 0 | [L837](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L837-L837) |
| 0x10DB | DestinationInformationUpdate | Destination sharing | 手机 → 配件 | 0 | [L843](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L843-L843) |
| 0x10DC | destinationSharing_StopDestinationInformation | Destination sharing | 配件 → 手机 | 0 | [L849](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L849-L849) |
| 0x10DD | destinationSharing_DestinationInformationStatus | Destination sharing | 配件 → 手机 | 0 | [L855](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L855-L855) |
| 0x1D00 | StartIdentification | Identification | 手机 → 配件 | 0 | [L70](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L70-L70) |
| 0x1D01 | IdentificationInformation | Identification | 配件 → 手机 | 20 | [L76](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L76-L76) |
| 0x1D02 | IdentificationAccepted | Identification | 手机 → 配件 | 0 | [L154](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L154-L154) |
| 0x1D03 | IdentificationRejected | Identification | 双向 | 0 | [L160](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L160-L160) |
| 0x1D05 | CancelIdentification | Identification | 配件 → 手机 | 0 | [L166](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L166-L166) |
| 0x1D06 | IdentificationInformationUpdate | Identification | 配件 → 手机 | 0 | [L172](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L172-L172) |
| 0x4154 | startCallStateUpdatesHandler | Communications | 配件 → 手机 | 0 | [L465](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L465-L465) |
| 0x4155 | CallStateUpdate | Communications | 手机 → 配件 | 0 | [L646](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L646-L646) |
| 0x4156 | stopCallStateUpdatesHandler | Communications | 配件 → 手机 | 0 | [L477](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L477-L477) |
| 0x4157 | startCommunicationsUpdatesHandler | Communications | 配件 → 手机 | 0 | [L459](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L459-L459) |
| 0x4158 | CommunicationsUpdate | Communications | 手机 → 配件 | 0 | [L647](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L647-L647) |
| 0x4159 | stopCommunicationsUpdatesHandler | Communications | 配件 → 手机 | 0 | [L471](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L471-L471) |
| 0x415A | initiateCallHandler | Communications | 配件 → 手机 | 0 | [L648](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L648-L648) |
| 0x415B | acceptCallHandler | Communications | 配件 → 手机 | 0 | [L649](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L649-L649) |
| 0x415C | endCallHandler | Communications | 配件 → 手机 | 0 | [L650](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L650-L650) |
| 0x415D | swapCallHandler | Communications | 配件 → 手机 | 0 | [L651](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L651-L651) |
| 0x415E | mergeCallHandler | Communications | 配件 → 手机 | 0 | [L652](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L652-L652) |
| 0x415F | holdStatusUpdateHandler | Communications | 配件 → 手机 | 0 | [L653](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L653-L653) |
| 0x4160 | muteStatusUpdateHandler | Communications | 配件 → 手机 | 0 | [L654](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L654-L654) |
| 0x4161 | sendDTMFHandler | Communications | 配件 → 手机 | 0 | [L655](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L655-L655) |
| 0x4170 | startListUpdatesHandler | Communications | 配件 → 手机 | 0 | [L656](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L656-L656) |
| 0x4171 | ListUpdate | Communications | 手机 → 配件 | 0 | [L657](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L657-L657) |
| 0x4172 | stopListUpdatesHandler | Communications | 配件 → 手机 | 0 | [L658](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L658-L658) |
| 0x4300 | CarPlayAvailability | CarPlayConnectionRequest | 手机 → 配件 | 3 | [L262](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L262-L262) |
| 0x4301 | CarPlayStartSession | CarPlayConnectionRequest | 配件 → 手机 | 9 | [L294](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L294-L294) |
| 0x4302 | AvailableDigitalCarKeys | DigitalCarKey_Matching | 配件 → 手机 | 0 | [L338](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L338-L338) |
| 0x4303 | MatchedDigitalCarKeys | DigitalCarKey_Matching | 手机 → 配件 | 0 | [L344](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L344-L344) |
| 0x4C00 | StartMediaLibraryInformation | Media Library | 配件 → 手机 | 0 | [L633](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L633-L633) |
| 0x4C01 | MediaLibraryInformation | Media Library | 手机 → 配件 | 0 | [L634](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L634-L634) |
| 0x4C02 | StopMediaLibraryInformation | Media Library | 配件 → 手机 | 0 | [L635](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L635-L635) |
| 0x4C03 | StartMediaLibraryUpdates | Media Library | 配件 → 手机 | 0 | [L636](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L636-L636) |
| 0x4C04 | MediaLibraryUpdate | Media Library | 手机 → 配件 | 0 | [L637](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L637-L637) |
| 0x4C05 | StopMediaLibraryUpdates | Media Library | 配件 → 手机 | 0 | [L638](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L638-L638) |
| 0x4C06 | PlayMediaLibraryCurrentSelection | Media Library | 配件 → 手机 | 0 | [L639](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L639-L639) |
| 0x4C07 | PlayMediaLibraryItems | Media Library | 配件 → 手机 | 0 | [L640](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L640-L640) |
| 0x4C08 | PlayMediaLibraryCollection | Media Library | 配件 → 手机 | 0 | [L641](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L641-L641) |
| 0x4C09 | PlayMediaLibrarySpecial | Media Library | 配件 → 手机 | 0 | [L642](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L642-L642) |
| 0x4E01 | BluetoothComponentInfo | Bluetooth connection status | 配件 → 手机 | 0 | [L659](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L659-L659) |
| 0x4E03 | StartBluetoothConnectionUpdates | Bluetooth connection status | 配件 → 手机 | 0 | [L665](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L665-L665) |
| 0x4E04 | BluetoothConnectionUpdate | Bluetooth connection status | 手机 → 配件 | 0 | [L671](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L671-L671) |
| 0x4E05 | StopBluetoothConnectionUpdates | Bluetooth connection status | 配件 → 手机 | 0 | [L677](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L677-L677) |
| 0x4E09 | DeviceInformationUpdate | DeviceNotifications | 手机 → 配件 | 1 | [L484](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L484-L484) |
| 0x4E0A | DeviceLanguageUpdate | DeviceNotifications | 手机 → 配件 | 1 | [L491](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L491-L491) |
| 0x4E0B | DeviceTimeUpdate | DeviceNotifications | 手机 → 配件 | 3 | [L498](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L498-L498) |
| 0x4E0C | DeviceUuidUpdate | DeviceNotifications | 手机 → 配件 | 1 | [L509](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L509-L509) |
| 0x4E0D | WirelessCarPlayUpdate | DeviceNotifications | 手机 → 配件 | 1 | [L516](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L516-L516) |
| 0x4E0E | DeviceTransportIdentifierNotification | DeviceNotifications | 手机 → 配件 | 2 | [L523](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L523-L523) |
| 0x5000 | StartNowPlayingUpdates | Now Playing | 配件 → 手机 | 0 | [L447](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L447-L447) |
| 0x5001 | NowPlayingUpdate | Now Playing | 手机 → 配件 | 0 | [L631](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L631-L631) |
| 0x5002 | StopNowPlayingUpdates | Now Playing | 配件 → 手机 | 0 | [L453](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L453-L453) |
| 0x5003 | SetNowPlayingInfo | Now Playing | 配件 → 手机 | 0 | [L632](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L632-L632) |
| 0x5200 | StartRouteGuidanceUpdates | Navigation | 配件 → 手机 | 0 | [L435](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L435-L435) |
| 0x5201 | RouteGuidanceUpdate | Navigation | 手机 → 配件 | 0 | [L643](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L643-L643) |
| 0x5202 | RouteGuidanceManeuverUpdate | Navigation | 手机 → 配件 | 0 | [L644](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L644-L644) |
| 0x5203 | StopRouteGuidanceUpdates | Navigation | 配件 → 手机 | 0 | [L441](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L441-L441) |
| 0x5204 | LaneGuidanceInfoUpdate | Navigation | 手机 → 配件 | 0 | [L645](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L645-L645) |
| 0x5400 | assistiveTouch_startAssistiveTouchHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L713](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L713-L713) |
| 0x5401 | assistiveTouch_stopAssistiveTouchHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L719](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L719-L719) |
| 0x5402 | assistiveTouch_startAssistiveTouchUpdateHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L725](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L725-L725) |
| 0x5403 | NotifyStatusUpdate | VoiceOver and AssistiveTouch | 手机 → 配件 | 0 | [L731](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L731-L731) |
| 0x5404 | assistiveTouch_stopAssistiveTouchUpdateHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L732](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L732-L732) |
| 0x5601 | voiceOver_moveCursorHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L738](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L738-L738) |
| 0x5602 | voiceOver_selectCursorHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L744](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L744-L744) |
| 0x5603 | voiceOver_scrollPageHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L750](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L750-L750) |
| 0x5606 | voiceOver_speakTextHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L756](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L756-L756) |
| 0x5608 | voiceOver_pauseSpeakingHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L762](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L762-L762) |
| 0x5609 | voiceOver_resumeSpeakingHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L768](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L768-L768) |
| 0x560B | voiceOver_startInformationHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L774](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L774-L774) |
| 0x560C | VoiceOverInformation | VoiceOver and AssistiveTouch | 手机 → 配件 | 0 | [L780](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L780-L780) |
| 0x560D | voiceOver_stopInformationHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L786](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L786-L786) |
| 0x560E | voiceOver_updateInformationHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L792](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L792-L792) |
| 0x560F | voiceOver_startCursorInformationHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L798](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L798-L798) |
| 0x5610 | VoiceOverCursorInformation | VoiceOver and AssistiveTouch | 手机 → 配件 | 0 | [L804](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L804-L804) |
| 0x5611 | voiceOver_stopCursorInformationHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L810](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L810-L810) |
| 0x5612 | VoiceOver_startVoiceOverHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L816](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L816-L816) |
| 0x5613 | VoiceOver_stopVoiceOverHandler | VoiceOver and AssistiveTouch | 配件 → 手机 | 0 | [L822](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L822-L822) |
| 0x5700 | RequestWiFiInformation | WiFiSharing | 配件 → 手机 | 0 | [L351](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L351-L351) |
| 0x5701 | WiFiInformation | WiFiSharing | 手机 → 配件 | 4 | [L357](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L357-L357) |
| 0x5702 | RequestAccessoryWiFiConfigurationInformation | WiFiSharing | 手机 → 配件 | 0 | [L369](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L369-L369) |
| 0x5703 | AccessoryWiFiConfigurationInformation | WiFiSharing | 配件 → 手机 | 5 | [L375](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L375-L375) |
| 0x6800 | hid_StartHIDMsgHandler | HID and USB host | 配件 → 手机 | 0 | [L689](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L689-L689) |
| 0x6801 | hid_OutReport | HID and USB host | 手机 → 配件 | 0 | [L690](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L690-L690) |
| 0x6802 | hid_AccessoryHIDReportHandler | HID and USB host | 配件 → 手机 | 0 | [L691](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L691-L691) |
| 0x6803 | hid_StopHIDMsgHandler | HID and USB host | 配件 → 手机 | 0 | [L692](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L692-L692) |
| 0x6804 | hid_GetReport | HID and USB host | 手机 → 配件 | 0 | [L693](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L693-L693) |
| 0x6805 | hid_AccessoryHIDGetReportResponseHandler | HID and USB host | 配件 → 手机 | 0 | [L694](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L694-L694) |
| 0x6807 | hid_ComponentUpdate | HID and USB host | 手机 → 配件 | 0 | [L700](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L700-L700) |
| 0x7E00 | usbHostMode_StartUSBHostModeHandler | HID and USB host | 配件 → 手机 | 0 | [L701](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L701-L701) |
| 0x7E02 | usbHostMode_StopUSBHostModeHandler | HID and USB host | 配件 → 手机 | 0 | [L707](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L707-L707) |
| 0xA100 | StartVehicleStatusUpdates | Vehicle | 手机 → 配件 | 0 | [L628](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L628-L628) |
| 0xA101 | VehicleStatusUpdate | Vehicle | 配件 → 手机 | 0 | [L629](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L629-L629) |
| 0xA102 | StopVehicleStatusUpdates | Vehicle | 手机 → 配件 | 0 | [L630](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L630-L630) |
| 0xAA00 | RequestAuthenticationCertificate | AccAuthentication | 手机 → 配件 | 0 | [L179](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L179-L179) |
| 0xAA01 | AuthenticationCertificate | AccAuthentication | 配件 → 手机 | 1 | [L185](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L185-L185) |
| 0xAA02 | RequestAuthenticationChallengeResponse | AccAuthentication | 手机 → 配件 | 1 | [L192](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L192-L192) |
| 0xAA03 | AuthenticationResponse | AccAuthentication | 配件 → 手机 | 1 | [L199](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L199-L199) |
| 0xAA04 | AuthenticationFailed | AccAuthentication | 手机 → 配件 | 0 | [L206](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L206-L206) |
| 0xAA05 | AuthenticationSucceeded | AccAuthentication | 手机 → 配件 | 0 | [L212](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L212-L212) |
| 0xAA06 | AuthenticationCertificateSerial | AccAuthentication | 配件 → 手机 | 0 | [L218](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L218-L218) |
| 0xAA10 | RequestDeviceCertificate | DeviceAuthentication | 配件 → 手机 | 0 | [L225](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L225-L225) |
| 0xAA11 | AuthenticationCertificate | DeviceAuthentication | 手机 → 配件 | 0 | [L231](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L231-L231) |
| 0xAA12 | RequestDeviceChallengeResponse | DeviceAuthentication | 配件 → 手机 | 0 | [L237](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L237-L237) |
| 0xAA13 | AuthenticationResponse | DeviceAuthentication | 手机 → 配件 | 0 | [L243](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L243-L243) |
| 0xAA14 | DeviceAuthenticationFailed | DeviceAuthentication | 配件 → 手机 | 0 | [L249](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L249-L249) |
| 0xAA15 | DeviceAuthenticationSucceeded | DeviceAuthentication | 配件 → 手机 | 0 | [L255](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L255-L255) |
| 0xAD00 | appLinks_start | App links and launch | 配件 → 手机 | 0 | [L683](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L683-L683) |
| 0xAD01 | AppLinksUpdate | App links and launch | 手机 → 配件 | 0 | [L684](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L684-L684) |
| 0xAD02 | appLinks_stop | App links and launch | 配件 → 手机 | 0 | [L685](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L685-L685) |
| 0xAD03 | appLinks_requestAppIcons | App links and launch | 配件 → 手机 | 0 | [L686](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L686-L686) |
| 0xAD04 | AppIconResponse | App links and launch | 手机 → 配件 | 0 | [L687](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L687-L687) |
| 0xAE00 | StartPowerUpdates | Power | 配件 → 手机 | 0 | [L415](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L415-L415) |
| 0xAE01 | PowerUpdate | Power | 手机 → 配件 | 0 | [L416](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L416-L416) |
| 0xAE02 | StopPowerUpdates | Power | 配件 → 手机 | 0 | [L417](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L417-L417) |
| 0xAE03 | PowerSourceUpdate | Power | 配件 → 手机 | 5 | [L418](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L418-L418) |
| 0xAE05 | AccessoryPowerUpdate | Power | 配件 → 手机 | 0 | [L431](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L431-L431) |
| 0xAE06 | AccessoryResetBaseCurrent | Power | 配件 → 手机 | 0 | [L432](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L432-L432) |
| 0xB102 | blePairing_accessoryStateUpdateHandler | Other endpoints | 配件 → 手机 | 0 | [L884](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L884-L884) |
| 0xB103 | blePairing_accessoryPairingInfoHandler | Other endpoints | 配件 → 手机 | 0 | [L890](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L890-L890) |
| 0xB105 | blePairing_accessoryPairingDataHandler | Other endpoints | 配件 → 手机 | 0 | [L896](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L896-L896) |
| 0xB107 | blePairing_stopBLEUpdates | Other endpoints | 手机 → 配件 | 0 | [L902](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L902-L902) |
| 0xDA00 | digitalAudio_start | DigitalAudio | 配件 → 手机 | 0 | [L557](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L557-L557) |
| 0xDA01 | DigitalAudioInformationUpdate | DigitalAudio | 手机 → 配件 | 0 | [L558](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L558-L558) |
| 0xDA02 | digitalAudio_stop | DigitalAudio | 配件 → 手机 | 0 | [L560](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L560-L560) |
| 0xEA00 | externalAccessory_openEASession | ExternalAccessory | 手机 → 配件 | 0 | [L534](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L534-L534) |
| 0xEA01 | externalAccessory_closeEASession | ExternalAccessory | 手机 → 配件 | 0 | [L540](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L540-L540) |
| 0xEA02 | requestAppLaunchHandler | External Accessory | 配件 → 手机 | 0 | [L688](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L688-L688) |
| 0xEA03 | externalaccessory_statusEASessionHandler | ExternalAccessory | 配件 → 手机 | 0 | [L546](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L546-L546) |
| 0xFFF0 | GPRMCDataStatusValues | Location | 手机 → 配件 | 0 | [L389](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L389-L389) |
| 0xFFFA | StartLocationInformation | Location | 手机 → 配件 | 0 | [L395](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L395-L395) |
| 0xFFFB | LocationInformation | Location | 配件 → 手机 | 1 | [L401](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L401-L401) |
| 0xFFFC | StopLocationInformation | Location | 手机 → 配件 | 0 | [L408](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/catalog/Iap2Endpoint.kt#L408-L408) |

## 逐条 schema 与双端证据

### 0x0000 — pingHandler

- 功能组：Test；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[BplistCodec.kt:L148](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/BplistCodec.kt#L148-L148)；[BplistCodec.kt:L152](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/BplistCodec.kt#L152-L152)；[BydCallPopupGuard.kt:L103](DiPlay/shared/src/main/java/com/shilapi/xcertplay/hud/BydCallPopupGuard.kt#L103-L103)。
- 手机/发送侧词法证据（不等于已验证 handler）：[BinaryPlist.kt:L333](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/BinaryPlist.kt#L333-L333)；[ConsumerKeys.kt:L107](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/input/ConsumerKeys.kt#L107-L107)；[ConsumerKeys.kt:L114](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/input/ConsumerKeys.kt#L114-L114)。

### 0x0001 — userNotificationHandler

- 功能组：Test；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[BplistCodec.kt:L154](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/BplistCodec.kt#L154-L154)；[NtpClock.kt:L197](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/NtpClock.kt#L197-L197)；[AmbientMusicEnvelope.kt:L24](DiPlay/shared/src/main/java/com/shilapi/xcertplay/media/AmbientMusicEnvelope.kt#L24-L24)。
- 手机/发送侧词法证据（不等于已验证 handler）：[BinaryPlist.kt:L345](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/BinaryPlist.kt#L345-L345)；[BinaryPlist.kt:L425](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/BinaryPlist.kt#L425-L425)；[Iap2Endpoint.kt:L550](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L550-L550)。

### 0x0004 — sendPingAccHandler

- 功能组：Test；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[AudioStream.kt:L249](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AudioStream.kt#L249-L249)；[BplistCodec.kt:L69](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/BplistCodec.kt#L69-L69)；[BplistCodec.kt:L171](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/BplistCodec.kt#L171-L171)。
- 手机/发送侧词法证据（不等于已验证 handler）：[BinaryPlist.kt:L357](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/BinaryPlist.kt#L357-L357)；[Iap2Endpoint.kt:L551](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L551-L551)；[Iap2Endpoint.kt:L619](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L619-L619)。

### 0x0005 — pingAccHandler

- 功能组：Test；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[BplistCodec.kt:L181](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/BplistCodec.kt#L181-L181)；[BplistCodec.kt:L223](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/BplistCodec.kt#L223-L223)。
- 手机/发送侧词法证据（不等于已验证 handler）：[BinaryPlist.kt:L362](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/BinaryPlist.kt#L362-L362)；[Iap2Endpoint.kt:L552](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L552-L552)；[Iap2Endpoint.kt:L620](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L620-L620)。

### 0x00B0 — oobBtPairing_startPairing

- 功能组：Other endpoints；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[AirPlayHid.kt:L120](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlayHid.kt#L120-L120)；[AirPlayHid.kt:L129](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlayHid.kt#L129-L129)。
- 手机/发送侧词法证据（不等于已验证 handler）：[ConsumerKeys.kt:L13](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/input/ConsumerKeys.kt#L13-L13)；[ConsumerKeys.kt:L54](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/input/ConsumerKeys.kt#L54-L54)；[ConsumerKeys.kt:L140](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/input/ConsumerKeys.kt#L140-L140)。

### 0x00B1 — oobBtPairing_accessoryInfoHandler

- 功能组：Other endpoints；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[AirPlayHid.kt:L120](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlayHid.kt#L120-L120)；[AirPlayHid.kt:L129](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlayHid.kt#L129-L129)。
- 手机/发送侧词法证据（不等于已验证 handler）：[ConsumerKeys.kt:L13](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/input/ConsumerKeys.kt#L13-L13)；[ConsumerKeys.kt:L54](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/input/ConsumerKeys.kt#L54-L54)；[ConsumerKeys.kt:L141](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/input/ConsumerKeys.kt#L141-L141)。

### 0x00B2 — oobBtPairing_pairingLinkKeyInfo

- 功能组：Other endpoints；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[AirPlayHid.kt:L129](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlayHid.kt#L129-L129)。
- 手机/发送侧词法证据：本次词法扫描未定位，不据此断言功能不存在。

### 0x00B3 — oobBtPairing_completionInfoHandler

- 功能组：Other endpoints；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[AirPlayHid.kt:L129](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlayHid.kt#L129-L129)。
- 手机/发送侧词法证据（不等于已验证 handler）：[SessionController.kt:L2499](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L2499-L2499)；[ConsumerKeys.kt:L13](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/input/ConsumerKeys.kt#L13-L13)；[ConsumerKeys.kt:L142](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/input/ConsumerKeys.kt#L142-L142)。

### 0x00B4 — oobBtPairing_stopPairing

- 功能组：Other endpoints；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[AirPlayHid.kt:L129](DiPlay/shared/src/main/java/com/shilapi/xcertplay/airplay/AirPlayHid.kt#L129-L129)。
- 手机/发送侧词法证据（不等于已验证 handler）：[ConsumerKeys.kt:L13](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/input/ConsumerKeys.kt#L13-L13)；[ConsumerKeys.kt:L143](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/input/ConsumerKeys.kt#L143-L143)；[ConsumerKeys.kt:L156](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/input/ConsumerKeys.kt#L156-L156)。

### 0x0B00 — oobBtPairing2_startPairing

- 功能组：BLE and OOB pairing；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据：本次词法扫描未定位，不据此断言功能不存在。

### 0x0B01 — oobBtPairing2_accessoryInfoHandler

- 功能组：BLE and OOB pairing；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据：本次词法扫描未定位，不据此断言功能不存在。

### 0x0B02 — oobBtPairing2_statusHandler

- 功能组：BLE and OOB pairing；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据：本次词法扫描未定位，不据此断言功能不存在。

### 0x0B03 — oobBtPairing2_stopPairing

- 功能组：BLE and OOB pairing；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据：本次词法扫描未定位，不据此断言功能不存在。

### 0x0D00 — StartRoadObjectDetection

- 功能组：Other endpoints；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据：本次词法扫描未定位，不据此断言功能不存在。

### 0x0D01 — RoadObjectDetectionUpdate

- 功能组：Other endpoints；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据：本次词法扫描未定位，不据此断言功能不存在。

### 0x0D02 — StopRoadObjectDetection

- 功能组：Other endpoints；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据：本次词法扫描未定位，不据此断言功能不存在。

### 0x10DA — destinationSharing_StartDestinationInformation

- 功能组：Destination sharing；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L834](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L834-L834)。

### 0x10DB — DestinationInformationUpdate

- 功能组：Destination sharing；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L840](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L840-L840)。

### 0x10DC — destinationSharing_StopDestinationInformation

- 功能组：Destination sharing；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L846](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L846-L846)。

### 0x10DD — destinationSharing_DestinationInformationStatus

- 功能组：Destination sharing；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L852](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L852-L852)。

### 0x1D00 — StartIdentification

- 功能组：Identification；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L218](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L218-L218)；[Iap2IdentificationClient.kt:L232](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L232-L232)。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L23](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L23-L23)；[VirtualIap2Link.kt:L60](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L60-L60)；[VirtualIap2Link.kt:L480](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L480-L480)。

### 0x1D01 — IdentificationInformation

- 功能组：Identification；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：
  - `0x0000 name: STRING required`
  - `0x0001 modelIdentifier: STRING required`
  - `0x0002 manufacturer: STRING required`
  - `0x0003 serialNumber: STRING required`
  - `0x0004 firmwareVersion: STRING required`
  - `0x0005 hardwareVersion: STRING required`
  - `0x0006 MessagesSentByAccessory: U16_LIST required`
  - `0x0007 MessagesReceivedFromDevice: U16_LIST required`
  - `0x0008 powerProvidingCapability: U8 optional`
  - `0x0009 maximumCurrentDrawnFromDevice: U16 optional`
  - `0x000A externalAccessoryProtocols: GROUP optional`
  - `0x000C currentLanguage: STRING required`
  - `0x000D supportedLanguages: STRING_LIST required`
  - `0x0010 USBHostTransport: GROUP optional`
  - `0x0010/0x0000 componentID: U16 optional`
  - `0x0010/0x0001 name: STRING optional`
  - `0x0010/0x0002 isSupported: VOID optional`
  - `0x0010/0x0003 interfaceNumber: U8 optional`
  - `0x0010/0x0004 isAvailable: VOID optional`
  - `0x0011 BluetoothTransport: GROUP optional`
  - `0x0011/0x0000 componentID: U16 optional`
  - `0x0011/0x0001 name: STRING optional`
  - `0x0011/0x0002 isSupported: VOID optional`
  - `0x0011/0x0003 bluetoothMAC: BYTES optional`
  - `0x0011/0x0004 transportName: STRING optional`
  - `0x0011/0x0005 isAvailable: VOID optional`
  - `0x0014 VehicleInformation: GROUP optional`
  - `0x0015 VehicleStatus: GROUP optional`
  - `0x0016 LocationInformation: GROUP optional`
  - `0x0018 WirelessCarPlayTransport: GROUP optional`
  - `0x0018/0x0000 componentID: U16 optional`
  - `0x0018/0x0001 SSID: STRING optional`
  - `0x0018/0x0002 isSupported: VOID optional`
  - `0x0018/0x0003 transportIdentifier: U16 optional`
  - `0x0018/0x0004 isAvailable: VOID optional`
  - `0x0018/0x0005 isEnabled: VOID optional`
  - `0x001E RouteGuidanceDisplayComponent: GROUP optional`
  - `0x001E/0x0000 Identifier: U16 required`
  - `0x001E/0x0001 Name: STRING required`
  - `0x001E/0x0002 MaxCurrentRoadNameLength: U16 optional`
  - `0x001E/0x0004 MaxAfterManeuverRoadNameLength: U16 optional`
  - `0x001E/0x0006 MaxGuidanceManeuverStorageCapacity: U16 optional`
  - `0x001E/0x0007 MaxLaneGuidanceDescriptionLength: U16 optional`
  - `0x001E/0x0008 MaxLaneGuidanceStorageCapacity: U16 optional`
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L233](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L233-L233)；[Iap2IdentificationClient.kt:L321](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L321-L321)。
- 手机/发送侧词法证据（不等于已验证 handler）：[SessionController.kt:L383](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L383-L383)；[SessionController.kt:L390](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L390-L390)；[SessionController.kt:L2318](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L2318-L2318)。

### 0x1D02 — IdentificationAccepted

- 功能组：Identification；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L219](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L219-L219)；[Iap2IdentificationClient.kt:L234](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L234-L234)。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L24](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L24-L24)；[VirtualIap2Link.kt:L528](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L528-L528)；[VirtualIap2Link.kt:L577](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L577-L577)。

### 0x1D03 — IdentificationRejected

- 功能组：Identification；catalog confidence：HIGH。
- 双端角色：双方依具体业务方向及状态处理；不能用这条元数据推断所有发起条件。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L220](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L220-L220)；[Iap2IdentificationClient.kt:L235](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L235-L235)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2MessageIds.kt:L28](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L28-L28)；[Iap2MessageIds.kt:L77](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L77-L77)；[Iap2Endpoint.kt:L156](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L156-L156)。

### 0x1D05 — CancelIdentification

- 功能组：Identification；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L162](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L162-L162)；[Iap2Endpoint.kt:L163](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L163-L163)；[Iap2Endpoint.kt:L567](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L567-L567)。

### 0x1D06 — IdentificationInformationUpdate

- 功能组：Identification；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L168](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L168-L168)；[Iap2Endpoint.kt:L169](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L169-L169)；[Iap2Endpoint.kt:L568](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L568-L568)。

### 0x4154 — startCallStateUpdatesHandler

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L423](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L423-L423)；[Iap2Messages.kt:L305](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/message/Iap2Messages.kt#L305-L305)。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L530](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L530-L530)；[VirtualIap2Link.kt:L632](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L632-L632)；[VirtualIap2Link.kt:L638](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L638-L638)。

### 0x4155 — CallStateUpdate

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[BydCarPlayCall.kt:L22](DiPlay/shared/src/main/java/com/shilapi/xcertplay/hud/BydCarPlayCall.kt#L22-L22)；[BydCarPlayCall.kt:L77](DiPlay/shared/src/main/java/com/shilapi/xcertplay/hud/BydCarPlayCall.kt#L77-L77)；[Iap2IdentificationClient.kt:L441](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L441-L441)。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L530](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L530-L530)；[VirtualIap2Link.kt:L638](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L638-L638)；[VirtualIap2Link.kt:L935](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L935-L935)。

### 0x4156 — stopCallStateUpdatesHandler

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L424](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L424-L424)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L473](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L473-L473)；[Iap2Endpoint.kt:L474](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L474-L474)；[Iap2Endpoint.kt:L607](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L607-L607)。

### 0x4157 — startCommunicationsUpdatesHandler

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L421](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L421-L421)；[Iap2Messages.kt:L300](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/message/Iap2Messages.kt#L300-L300)。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L530](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L530-L530)；[VirtualIap2Link.kt:L626](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L626-L626)；[VirtualIap2Link.kt:L629](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L629-L629)。

### 0x4158 — CommunicationsUpdate

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L440](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L440-L440)。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L517](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L517-L517)；[VirtualIap2Link.kt:L530](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L530-L530)；[VirtualIap2Link.kt:L629](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L629-L629)。

### 0x4159 — stopCommunicationsUpdatesHandler

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L422](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L422-L422)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L467](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L467-L467)；[Iap2Endpoint.kt:L468](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L468-L468)；[Iap2Endpoint.kt:L606](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L606-L606)。

### 0x415A — initiateCallHandler

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L644](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L644-L644)。

### 0x415B — acceptCallHandler

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L645](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L645-L645)。

### 0x415C — endCallHandler

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L646](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L646-L646)。

### 0x415D — swapCallHandler

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L647](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L647-L647)。

### 0x415E — mergeCallHandler

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L648](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L648-L648)。

### 0x415F — holdStatusUpdateHandler

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L649](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L649-L649)。

### 0x4160 — muteStatusUpdateHandler

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L650](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L650-L650)。

### 0x4161 — sendDTMFHandler

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L651](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L651-L651)。

### 0x4170 — startListUpdatesHandler

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L530](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L530-L530)；[VirtualIap2Link.kt:L650](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L650-L650)；[VirtualIap2Link.kt:L937](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L937-L937)。

### 0x4171 — ListUpdate

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L530](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L530-L530)；[VirtualIap2Link.kt:L650](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L650-L650)；[VirtualIap2Link.kt:L938](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L938-L938)。

### 0x4172 — stopListUpdatesHandler

- 功能组：Communications；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L654](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L654-L654)。

### 0x4300 — CarPlayAvailability

- 功能组：CarPlayConnectionRequest；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：
  - `0x0000 wired: GROUP optional`
  - `0x0000/0x0000 wiredAvailable: U8 optional`
  - `0x0000/0x0001 usbIdentifier: STRING optional`
  - `0x0001 wireless: GROUP optional`
  - `0x0001/0x0000 wirelessAvailable: U8 optional`
  - `0x0001/0x0001 bluetoothIdentifier: STRING optional`
  - `0x0002 themeAssets: GROUP optional`
  - `0x0002/0x0000 themeAssetsAvailable: U8 optional`
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L185](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L185-L185)；[Iap2IdentificationClient.kt:L442](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L442-L442)；[Iap2IdentificationClient.kt:L447](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L447-L447)。
- 手机/发送侧词法证据（不等于已验证 handler）：[SessionController.kt:L792](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L792-L792)；[AirPlayClient.kt:L2748](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/AirPlayClient.kt#L2748-L2748)；[BtSession.kt:L50](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/bt/BtSession.kt#L50-L50)。

### 0x4301 — CarPlayStartSession

- 功能组：CarPlayConnectionRequest；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：
  - `0x0000 wired: GROUP optional`
  - `0x0000/0x0000 wiredIP: STRING optional repeatable`
  - `0x0000/0x0001 reserved: U32 optional`
  - `0x0001 wireless: GROUP optional`
  - `0x0001/0x0000 SSID: STRING optional`
  - `0x0001/0x0001 passphrase: STRING optional`
  - `0x0001/0x0002 channel: U8 optional`
  - `0x0001/0x0003 wirelessIP: STRING optional repeatable`
  - `0x0001/0x0004 securityType: U8 optional`
  - `0x0002 airPlayPort: U32 optional`
  - `0x0003 deviceIdentifier: STRING optional`
  - `0x0004 publicKey: STRING optional`
  - `0x0005 sourceVersion: STRING optional`
  - `0x0006 SDKVersion: STRING optional`
  - `0x0007 clusterAsset: GROUP optional`
  - `0x0007/0x0000 assetID: STRING optional`
  - `0x0007/0x0001 assetVersion: U32 optional`
  - `0x0008 mutualAuth: U8 optional`
- 配件/接收侧词法证据（不等于已验证 handler）：[WirelessStartupDiagnostics.kt:L41](DiPlay/shared/src/main/java/com/shilapi/xcertplay/network/WirelessStartupDiagnostics.kt#L41-L41)；[CarPlayController.kt:L3260](DiPlay/shared/src/main/java/com/shilapi/xcertplay/orchestration/CarPlayController.kt#L3260-L3260)；[Iap2IdentificationClient.kt:L185](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L185-L185)。
- 手机/发送侧词法证据（不等于已验证 handler）：[SessionController.kt:L87](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L87-L87)；[SessionController.kt:L88](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L88-L88)；[SessionController.kt:L165](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L165-L165)。

### 0x4302 — AvailableDigitalCarKeys

- 功能组：DigitalCarKey_Matching；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L334](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L334-L334)；[Iap2Endpoint.kt:L335](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L335-L335)；[Iap2Endpoint.kt:L584](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L584-L584)。

### 0x4303 — MatchedDigitalCarKeys

- 功能组：DigitalCarKey_Matching；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L340](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L340-L340)；[Iap2Endpoint.kt:L341](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L341-L341)；[Iap2Endpoint.kt:L585](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L585-L585)。

### 0x4C00 — StartMediaLibraryInformation

- 功能组：Media Library；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L629](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L629-L629)。

### 0x4C01 — MediaLibraryInformation

- 功能组：Media Library；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L630](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L630-L630)。

### 0x4C02 — StopMediaLibraryInformation

- 功能组：Media Library；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L631](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L631-L631)。

### 0x4C03 — StartMediaLibraryUpdates

- 功能组：Media Library；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L632](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L632-L632)。

### 0x4C04 — MediaLibraryUpdate

- 功能组：Media Library；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L633](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L633-L633)。

### 0x4C05 — StopMediaLibraryUpdates

- 功能组：Media Library；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L634](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L634-L634)。

### 0x4C06 — PlayMediaLibraryCurrentSelection

- 功能组：Media Library；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L635](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L635-L635)。

### 0x4C07 — PlayMediaLibraryItems

- 功能组：Media Library；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L636](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L636-L636)。

### 0x4C08 — PlayMediaLibraryCollection

- 功能组：Media Library；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L637](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L637-L637)。

### 0x4C09 — PlayMediaLibrarySpecial

- 功能组：Media Library；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L638](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L638-L638)。

### 0x4E01 — BluetoothComponentInfo

- 功能组：Bluetooth connection status；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L656](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L656-L656)。

### 0x4E03 — StartBluetoothConnectionUpdates

- 功能组：Bluetooth connection status；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L662](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L662-L662)。

### 0x4E04 — BluetoothConnectionUpdate

- 功能组：Bluetooth connection status；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L668](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L668-L668)。

### 0x4E05 — StopBluetoothConnectionUpdates

- 功能组：Bluetooth connection status；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L674](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L674-L674)。

### 0x4E09 — DeviceInformationUpdate

- 功能组：DeviceNotifications；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：
  - `0x0000 deviceName: STRING optional`
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L790](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L790-L790)；[VirtualIap2Link.kt:L932](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L932-L932)；[Iap2MessageIds.kt:L37](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L37-L37)。

### 0x4E0A — DeviceLanguageUpdate

- 功能组：DeviceNotifications；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：
  - `0x0000 language: STRING optional`
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L931](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L931-L931)；[Iap2MessageIds.kt:L38](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L38-L38)；[Iap2SenderSession.kt:L350](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2SenderSession.kt#L350-L350)。

### 0x4E0B — DeviceTimeUpdate

- 功能组：DeviceNotifications；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：
  - `0x0000 secondsSinceReferenceDate: U64 optional`
  - `0x0001 timeZoneOffsetMinutes: I16 optional`
  - `0x0002 daylightSavingsOffsetMinutes: I8 optional`
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L802](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L802-L802)；[VirtualIap2Link.kt:L930](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L930-L930)；[Iap2MessageIds.kt:L39](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L39-L39)。

### 0x4E0C — DeviceUuidUpdate

- 功能组：DeviceNotifications；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：
  - `0x0000 deviceUUID: STRING optional`
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L929](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L929-L929)；[Iap2MessageIds.kt:L40](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L40-L40)；[Iap2SenderSession.kt:L687](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2SenderSession.kt#L687-L687)。

### 0x4E0D — WirelessCarPlayUpdate

- 功能组：DeviceNotifications；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：
  - `0x0000 availability: U8 required`
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L453](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L453-L453)；[Iap2WirelessControlClient.kt:L14](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2WirelessControlClient.kt#L14-L14)；[Iap2WirelessControlClient.kt:L174](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2WirelessControlClient.kt#L174-L174)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2MessageIds.kt:L20](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L20-L20)；[Iap2MessageIds.kt:L33](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L33-L33)；[Iap2MessageIds.kt:L80](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L80-L80)。

### 0x4E0E — DeviceTransportIdentifierNotification

- 功能组：DeviceNotifications；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：
  - `0x0000 bluetoothMAC: STRING optional`
  - `0x0001 usbTransportIdentifier: STRING optional`
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L453](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L453-L453)；[Iap2WirelessControlClient.kt:L14](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2WirelessControlClient.kt#L14-L14)；[Iap2WirelessControlClient.kt:L185](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2WirelessControlClient.kt#L185-L185)。
- 手机/发送侧词法证据（不等于已验证 handler）：[AirPlayClient.kt:L2748](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/AirPlayClient.kt#L2748-L2748)；[BtSession.kt:L50](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/bt/BtSession.kt#L50-L50)；[BtSession.kt:L71](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/bt/BtSession.kt#L71-L71)。

### 0x5000 — StartNowPlayingUpdates

- 功能组：Now Playing；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L415](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L415-L415)；[Iap2Messages.kt:L279](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/message/Iap2Messages.kt#L279-L279)。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L101](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L101-L101)；[VirtualIap2Link.kt:L530](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L530-L530)；[VirtualIap2Link.kt:L653](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L653-L653)。

### 0x5001 — NowPlayingUpdate

- 功能组：Now Playing；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[CarPlayGlance.kt:L11](DiPlay/shared/src/main/java/com/shilapi/xcertplay/glance/CarPlayGlance.kt#L11-L11)；[BydClusterSong.kt:L21](DiPlay/shared/src/main/java/com/shilapi/xcertplay/hud/BydClusterSong.kt#L21-L21)；[BydClusterSong.kt:L66](DiPlay/shared/src/main/java/com/shilapi/xcertplay/hud/BydClusterSong.kt#L66-L66)。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L530](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L530-L530)；[VirtualIap2Link.kt:L656](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L656-L656)；[VirtualIap2Link.kt:L658](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L658-L658)。

### 0x5002 — StopNowPlayingUpdates

- 功能组：Now Playing；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L416](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L416-L416)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L449](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L449-L449)；[Iap2Endpoint.kt:L450](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L450-L450)；[Iap2Endpoint.kt:L603](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L603-L603)。

### 0x5003 — SetNowPlayingInfo

- 功能组：Now Playing；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L628](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L628-L628)。

### 0x5200 — StartRouteGuidanceUpdates

- 功能组：Navigation；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L417](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L417-L417)；[Iap2Messages.kt:L290](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/message/Iap2Messages.kt#L290-L290)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2MessageIds.kt:L62](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L62-L62)；[Iap2MessageIds.kt:L92](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L92-L92)；[Iap2Endpoint.kt:L431](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L431-L431)。

### 0x5201 — RouteGuidanceUpdate

- 功能组：Navigation；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[CarPlayGlance.kt:L11](DiPlay/shared/src/main/java/com/shilapi/xcertplay/glance/CarPlayGlance.kt#L11-L11)；[BydHudRouteState.kt:L246](DiPlay/shared/src/main/java/com/shilapi/xcertplay/hud/BydHudRouteState.kt#L246-L246)；[FceClusterOutput.kt:L125](DiPlay/shared/src/main/java/com/shilapi/xcertplay/hud/FceClusterOutput.kt#L125-L125)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L639](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L639-L639)；[Iap2IdentificationClient.kt:L286](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/transport/Iap2IdentificationClient.kt#L286-L286)；[Iap2IdentificationClient.kt:L325](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/transport/Iap2IdentificationClient.kt#L325-L325)。

### 0x5202 — RouteGuidanceManeuverUpdate

- 功能组：Navigation；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[CarPlayGlance.kt:L11](DiPlay/shared/src/main/java/com/shilapi/xcertplay/glance/CarPlayGlance.kt#L11-L11)；[BydHudRouteState.kt:L174](DiPlay/shared/src/main/java/com/shilapi/xcertplay/hud/BydHudRouteState.kt#L174-L174)；[BydHudRouteState.kt:L247](DiPlay/shared/src/main/java/com/shilapi/xcertplay/hud/BydHudRouteState.kt#L247-L247)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L640](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L640-L640)；[Iap2IdentificationClient.kt:L286](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/transport/Iap2IdentificationClient.kt#L286-L286)；[Iap2IdentificationClient.kt:L326](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/transport/Iap2IdentificationClient.kt#L326-L326)。

### 0x5203 — StopRouteGuidanceUpdates

- 功能组：Navigation；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L418](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L418-L418)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L437](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L437-L437)；[Iap2Endpoint.kt:L438](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L438-L438)；[Iap2Endpoint.kt:L601](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L601-L601)。

### 0x5204 — LaneGuidanceInfoUpdate

- 功能组：Navigation；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[CarPlayGlance.kt:L29](DiPlay/shared/src/main/java/com/shilapi/xcertplay/glance/CarPlayGlance.kt#L29-L29)；[CarPlayGlance.kt:L40](DiPlay/shared/src/main/java/com/shilapi/xcertplay/glance/CarPlayGlance.kt#L40-L40)；[CarPlayGlance.kt:L60](DiPlay/shared/src/main/java/com/shilapi/xcertplay/glance/CarPlayGlance.kt#L60-L60)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L641](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L641-L641)。

### 0x5400 — assistiveTouch_startAssistiveTouchHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L710](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L710-L710)。

### 0x5401 — assistiveTouch_stopAssistiveTouchHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L716](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L716-L716)。

### 0x5402 — assistiveTouch_startAssistiveTouchUpdateHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L722](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L722-L722)。

### 0x5403 — NotifyStatusUpdate

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L727](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L727-L727)。

### 0x5404 — assistiveTouch_stopAssistiveTouchUpdateHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L729](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L729-L729)。

### 0x5601 — voiceOver_moveCursorHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L735](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L735-L735)。

### 0x5602 — voiceOver_selectCursorHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L741](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L741-L741)。

### 0x5603 — voiceOver_scrollPageHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L747](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L747-L747)。

### 0x5606 — voiceOver_speakTextHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L753](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L753-L753)。

### 0x5608 — voiceOver_pauseSpeakingHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L759](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L759-L759)。

### 0x5609 — voiceOver_resumeSpeakingHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L765](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L765-L765)。

### 0x560B — voiceOver_startInformationHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L771](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L771-L771)。

### 0x560C — VoiceOverInformation

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L777](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L777-L777)。

### 0x560D — voiceOver_stopInformationHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L783](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L783-L783)。

### 0x560E — voiceOver_updateInformationHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L789](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L789-L789)。

### 0x560F — voiceOver_startCursorInformationHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L795](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L795-L795)。

### 0x5610 — VoiceOverCursorInformation

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L801](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L801-L801)。

### 0x5611 — voiceOver_stopCursorInformationHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L807](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L807-L807)。

### 0x5612 — VoiceOver_startVoiceOverHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L813](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L813-L813)。

### 0x5613 — VoiceOver_stopVoiceOverHandler

- 功能组：VoiceOver and AssistiveTouch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L819](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L819-L819)。

### 0x5700 — RequestWiFiInformation

- 功能组：WiFiSharing；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L347](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L347-L347)；[Iap2Endpoint.kt:L348](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L348-L348)；[Iap2Endpoint.kt:L586](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L586-L586)。

### 0x5701 — WiFiInformation

- 功能组：WiFiSharing；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：
  - `0x0000 status: U8 required`
  - `0x0001 securityType: U8 optional`
  - `0x0002 SSID: STRING optional`
  - `0x0003 passphrase: STRING optional`
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2Messages.kt:L170](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/message/Iap2Messages.kt#L170-L170)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L353](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L353-L353)；[Iap2Endpoint.kt:L354](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L354-L354)；[Iap2Endpoint.kt:L587](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L587-L587)。

### 0x5702 — RequestAccessoryWiFiConfigurationInformation

- 功能组：WiFiSharing；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L453](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L453-L453)；[Iap2WirelessControlClient.kt:L127](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2WirelessControlClient.kt#L127-L127)；[Iap2WirelessControlClient.kt:L128](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2WirelessControlClient.kt#L128-L128)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2MessageIds.kt:L15](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L15-L15)；[Iap2MessageIds.kt:L43](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L43-L43)；[Iap2MessageIds.kt:L82](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L82-L82)。

### 0x5703 — AccessoryWiFiConfigurationInformation

- 功能组：WiFiSharing；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：
  - `0x0000 BSSID: BYTES optional`
  - `0x0001 SSID: STRING optional`
  - `0x0002 passphrase: STRING optional`
  - `0x0003 securityType: U8 optional`
  - `0x0004 channel: U8 optional`
- 配件/接收侧词法证据（不等于已验证 handler）：[WirelessHotspotManager.kt:L28](DiPlay/shared/src/main/java/com/shilapi/xcertplay/network/WirelessHotspotManager.kt#L28-L28)；[WirelessHotspotManager.kt:L102](DiPlay/shared/src/main/java/com/shilapi/xcertplay/network/WirelessHotspotManager.kt#L102-L102)；[WirelessStartupDiagnostics.kt:L39](DiPlay/shared/src/main/java/com/shilapi/xcertplay/network/WirelessStartupDiagnostics.kt#L39-L39)。
- 手机/发送侧词法证据（不等于已验证 handler）：[MainActivity.kt:L842](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/MainActivity.kt#L842-L842)；[SessionController.kt:L377](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L377-L377)；[SessionController.kt:L398](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L398-L398)。

### 0x6800 — hid_StartHIDMsgHandler

- 功能组：HID and USB host；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L101](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L101-L101)；[VirtualIap2Link.kt:L423](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L423-L423)；[VirtualIap2Link.kt:L555](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L555-L555)。

### 0x6801 — hid_OutReport

- 功能组：HID and USB host；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2MessageIds.kt:L48](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L48-L48)；[Iap2SenderSession.kt:L14](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2SenderSession.kt#L14-L14)；[Iap2SenderSession.kt:L269](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2SenderSession.kt#L269-L269)。

### 0x6802 — hid_AccessoryHIDReportHandler

- 功能组：HID and USB host；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[SessionController.kt:L2341](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L2341-L2341)；[SessionController.kt:L2345](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L2345-L2345)；[SessionController.kt:L2347](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L2347-L2347)。

### 0x6803 — hid_StopHIDMsgHandler

- 功能组：HID and USB host；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2MessageIds.kt:L50](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L50-L50)；[Iap2Endpoint.kt:L688](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L688-L688)。

### 0x6804 — hid_GetReport

- 功能组：HID and USB host；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L689](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L689-L689)。

### 0x6805 — hid_AccessoryHIDGetReportResponseHandler

- 功能组：HID and USB host；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L691](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L691-L691)。

### 0x6807 — hid_ComponentUpdate

- 功能组：HID and USB host；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L696](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L696-L696)。

### 0x7E00 — usbHostMode_StartUSBHostModeHandler

- 功能组：HID and USB host；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L698](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L698-L698)。

### 0x7E02 — usbHostMode_StopUSBHostModeHandler

- 功能组：HID and USB host；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L704](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L704-L704)。

### 0xA100 — StartVehicleStatusUpdates

- 功能组：Vehicle；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2VehicleStatus.kt:L43](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2VehicleStatus.kt#L43-L43)；[Iap2VehicleStatus.kt:L47](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2VehicleStatus.kt#L47-L47)；[Iap2VehicleStatus.kt:L100](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2VehicleStatus.kt#L100-L100)。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L933](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L933-L933)；[Iap2Endpoint.kt:L624](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L624-L624)；[Iap2VehicleStatus.kt:L43](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/transport/Iap2VehicleStatus.kt#L43-L43)。

### 0xA101 — VehicleStatusUpdate

- 功能组：Vehicle；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2VehicleStatus.kt:L43](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2VehicleStatus.kt#L43-L43)；[Iap2VehicleStatus.kt:L48](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2VehicleStatus.kt#L48-L48)；[Iap2VehicleStatus.kt:L128](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2VehicleStatus.kt#L128-L128)。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L531](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L531-L531)；[Iap2Endpoint.kt:L625](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L625-L625)；[Iap2VehicleStatus.kt:L43](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/transport/Iap2VehicleStatus.kt#L43-L43)。

### 0xA102 — StopVehicleStatusUpdates

- 功能组：Vehicle；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2VehicleStatus.kt:L49](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2VehicleStatus.kt#L49-L49)；[Iap2VehicleStatus.kt:L100](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2VehicleStatus.kt#L100-L100)；[Iap2VehicleStatus.kt:L110](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2VehicleStatus.kt#L110-L110)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L626](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L626-L626)；[Iap2VehicleStatus.kt:L49](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/transport/Iap2VehicleStatus.kt#L49-L49)；[Iap2VehicleStatus.kt:L100](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/transport/Iap2VehicleStatus.kt#L100-L100)。

### 0xAA00 — RequestAuthenticationCertificate

- 功能组：AccAuthentication；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2MfiAuthenticationClient.kt:L46](DiPlay/shared/src/main/java/com/shilapi/xcertplay/mfi/Iap2MfiAuthenticationClient.kt#L46-L46)；[Iap2MfiAuthenticationClient.kt:L104](DiPlay/shared/src/main/java/com/shilapi/xcertplay/mfi/Iap2MfiAuthenticationClient.kt#L104-L104)；[Iap2IdentificationClient.kt:L429](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L429-L429)。
- 手机/发送侧词法证据（不等于已验证 handler）：[SessionController.kt:L1840](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L1840-L1840)；[VirtualIap2Link.kt:L24](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L24-L24)；[VirtualIap2Link.kt:L235](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L235-L235)。

### 0xAA01 — AuthenticationCertificate

- 功能组：AccAuthentication；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：
  - `0x0000 certificate: BYTES required`
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2MfiAuthenticationClient.kt:L48](DiPlay/shared/src/main/java/com/shilapi/xcertplay/mfi/Iap2MfiAuthenticationClient.kt#L48-L48)；[Iap2MfiAuthenticationClient.kt:L105](DiPlay/shared/src/main/java/com/shilapi/xcertplay/mfi/Iap2MfiAuthenticationClient.kt#L105-L105)；[Iap2IdentificationClient.kt:L413](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L413-L413)。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L529](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L529-L529)；[Iap2MessageIds.kt:L54](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L54-L54)；[Iap2SenderSession.kt:L13](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2SenderSession.kt#L13-L13)。

### 0xAA02 — RequestAuthenticationChallengeResponse

- 功能组：AccAuthentication；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：
  - `0x0000 challenge: BYTES required`
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2MfiAuthenticationClient.kt:L55](DiPlay/shared/src/main/java/com/shilapi/xcertplay/mfi/Iap2MfiAuthenticationClient.kt#L55-L55)；[Iap2MfiAuthenticationClient.kt:L106](DiPlay/shared/src/main/java/com/shilapi/xcertplay/mfi/Iap2MfiAuthenticationClient.kt#L106-L106)；[Iap2IdentificationClient.kt:L430](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L430-L430)。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L24](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L24-L24)；[VirtualIap2Link.kt:L475](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L475-L475)；[VirtualIap2Link.kt:L529](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L529-L529)。

### 0xAA03 — AuthenticationResponse

- 功能组：AccAuthentication；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：
  - `0x0000 signatureResponse: BYTES required`
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2MfiAuthenticationClient.kt:L58](DiPlay/shared/src/main/java/com/shilapi/xcertplay/mfi/Iap2MfiAuthenticationClient.kt#L58-L58)；[Iap2MfiAuthenticationClient.kt:L107](DiPlay/shared/src/main/java/com/shilapi/xcertplay/mfi/Iap2MfiAuthenticationClient.kt#L107-L107)；[Iap2IdentificationClient.kt:L414](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L414-L414)。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L24](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L24-L24)；[VirtualIap2Link.kt:L529](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L529-L529)；[VirtualIap2Link.kt:L613](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L613-L613)。

### 0xAA04 — AuthenticationFailed

- 功能组：AccAuthentication；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2MfiAuthenticationClient.kt:L64](DiPlay/shared/src/main/java/com/shilapi/xcertplay/mfi/Iap2MfiAuthenticationClient.kt#L64-L64)；[Iap2MfiAuthenticationClient.kt:L108](DiPlay/shared/src/main/java/com/shilapi/xcertplay/mfi/Iap2MfiAuthenticationClient.kt#L108-L108)；[Iap2IdentificationClient.kt:L431](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L431-L431)。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L592](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L592-L592)；[Iap2MessageIds.kt:L57](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L57-L57)；[Iap2SenderSession.kt:L584](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2SenderSession.kt#L584-L584)。

### 0xAA05 — AuthenticationSucceeded

- 功能组：AccAuthentication；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2MfiAuthenticationClient.kt:L60](DiPlay/shared/src/main/java/com/shilapi/xcertplay/mfi/Iap2MfiAuthenticationClient.kt#L60-L60)；[Iap2MfiAuthenticationClient.kt:L61](DiPlay/shared/src/main/java/com/shilapi/xcertplay/mfi/Iap2MfiAuthenticationClient.kt#L61-L61)；[Iap2MfiAuthenticationClient.kt:L109](DiPlay/shared/src/main/java/com/shilapi/xcertplay/mfi/Iap2MfiAuthenticationClient.kt#L109-L109)。
- 手机/发送侧词法证据（不等于已验证 handler）：[SessionController.kt:L1840](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/SessionController.kt#L1840-L1840)；[VirtualIap2Link.kt:L24](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L24-L24)；[VirtualIap2Link.kt:L235](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L235-L235)。

### 0xAA06 — AuthenticationCertificateSerial

- 功能组：AccAuthentication；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L24](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L24-L24)；[VirtualIap2Link.kt:L528](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L528-L528)；[VirtualIap2Link.kt:L586](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L586-L586)。

### 0xAA10 — RequestDeviceCertificate

- 功能组：DeviceAuthentication；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L221](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L221-L221)；[Iap2Endpoint.kt:L222](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L222-L222)；[Iap2Endpoint.kt:L576](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L576-L576)。

### 0xAA11 — AuthenticationCertificate

- 功能组：DeviceAuthentication；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L227](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L227-L227)；[Iap2Endpoint.kt:L228](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L228-L228)；[Iap2Endpoint.kt:L577](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L577-L577)。

### 0xAA12 — RequestDeviceChallengeResponse

- 功能组：DeviceAuthentication；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L233](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L233-L233)；[Iap2Endpoint.kt:L234](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L234-L234)；[Iap2Endpoint.kt:L578](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L578-L578)。

### 0xAA13 — AuthenticationResponse

- 功能组：DeviceAuthentication；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L239](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L239-L239)；[Iap2Endpoint.kt:L240](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L240-L240)；[Iap2Endpoint.kt:L579](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L579-L579)。

### 0xAA14 — DeviceAuthenticationFailed

- 功能组：DeviceAuthentication；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L245](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L245-L245)；[Iap2Endpoint.kt:L246](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L246-L246)；[Iap2Endpoint.kt:L580](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L580-L580)。

### 0xAA15 — DeviceAuthenticationSucceeded

- 功能组：DeviceAuthentication；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L251](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L251-L251)；[Iap2Endpoint.kt:L252](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L252-L252)；[Iap2Endpoint.kt:L581](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L581-L581)。

### 0xAD00 — appLinks_start

- 功能组：App links and launch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L720](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L720-L720)；[Iap2Endpoint.kt:L679](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L679-L679)。

### 0xAD01 — AppLinksUpdate

- 功能组：App links and launch；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L680](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L680-L680)。

### 0xAD02 — appLinks_stop

- 功能组：App links and launch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L720](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L720-L720)；[Iap2Endpoint.kt:L681](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L681-L681)。

### 0xAD03 — appLinks_requestAppIcons

- 功能组：App links and launch；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L720](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L720-L720)；[Iap2Endpoint.kt:L682](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L682-L682)。

### 0xAD04 — AppIconResponse

- 功能组：App links and launch；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L683](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L683-L683)。

### 0xAE00 — StartPowerUpdates

- 功能组：Power；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L419](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L419-L419)；[Iap2Messages.kt:L295](DiPlay/shared/src/main/java/com/shilapi/xcertplay/iap2/message/Iap2Messages.kt#L295-L295)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2MessageIds.kt:L63](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L63-L63)；[Iap2MessageIds.kt:L93](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L93-L93)；[Iap2Endpoint.kt:L411](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L411-L411)。

### 0xAE01 — PowerUpdate

- 功能组：Power；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L439](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L439-L439)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L412](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L412-L412)；[Iap2Endpoint.kt:L595](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L595-L595)；[Iap2IdentificationClient.kt:L327](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/transport/Iap2IdentificationClient.kt#L327-L327)。

### 0xAE02 — StopPowerUpdates

- 功能组：Power；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L420](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L420-L420)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L413](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L413-L413)；[Iap2Endpoint.kt:L596](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L596-L596)；[Iap2IdentificationClient.kt:L309](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/transport/Iap2IdentificationClient.kt#L309-L309)。

### 0xAE03 — PowerSourceUpdate

- 功能组：Power；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：
  - `0x0000 AvailableCurrentForDevice: U16 optional`
  - `0x0001 IsDeviceBatteryCharging: U8 optional`
  - `0x0003 AvailableSiphoningCurrent: U16 optional`
  - `0x0004 ReserveCurrent: U16 optional`
  - `0x0005 MaxNonSiphoningCurrentExceeded: VOID optional`
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L333](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L333-L333)；[Iap2IdentificationClient.kt:L425](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L425-L425)；[Iap2IdentificationClient.kt:L446](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L446-L446)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L414](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L414-L414)；[Iap2Endpoint.kt:L415](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L415-L415)；[Iap2Endpoint.kt:L597](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L597-L597)。

### 0xAE05 — AccessoryPowerUpdate

- 功能组：Power；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L427](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L427-L427)；[Iap2Endpoint.kt:L598](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L598-L598)。

### 0xAE06 — AccessoryResetBaseCurrent

- 功能组：Power；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L428](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L428-L428)；[Iap2Endpoint.kt:L429](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L429-L429)；[Iap2Endpoint.kt:L599](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L599-L599)。

### 0xB102 — blePairing_accessoryStateUpdateHandler

- 功能组：Other endpoints；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L881](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L881-L881)。

### 0xB103 — blePairing_accessoryPairingInfoHandler

- 功能组：Other endpoints；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L887](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L887-L887)。

### 0xB105 — blePairing_accessoryPairingDataHandler

- 功能组：Other endpoints；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L893](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L893-L893)。

### 0xB107 — blePairing_stopBLEUpdates

- 功能组：Other endpoints；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L898](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L898-L898)。

### 0xDA00 — digitalAudio_start

- 功能组：DigitalAudio；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L553](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L553-L553)；[Iap2Endpoint.kt:L621](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L621-L621)。

### 0xDA01 — DigitalAudioInformationUpdate

- 功能组：DigitalAudio；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L554](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L554-L554)；[Iap2Endpoint.kt:L555](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L555-L555)；[Iap2Endpoint.kt:L622](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L622-L622)。

### 0xDA02 — digitalAudio_stop

- 功能组：DigitalAudio；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L556](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L556-L556)；[Iap2Endpoint.kt:L623](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L623-L623)。

### 0xEA00 — externalAccessory_openEASession

- 功能组：ExternalAccessory；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L433](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L433-L433)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2MessageIds.kt:L68](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L68-L68)；[Iap2SenderSession.kt:L214](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2SenderSession.kt#L214-L214)；[Iap2SenderSession.kt:L249](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2SenderSession.kt#L249-L249)。

### 0xEA01 — externalAccessory_closeEASession

- 功能组：ExternalAccessory；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L434](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L434-L434)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2MessageIds.kt:L69](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L69-L69)；[Iap2Endpoint.kt:L536](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L536-L536)；[Iap2Endpoint.kt:L537](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L537-L537)。

### 0xEA02 — requestAppLaunchHandler

- 功能组：External Accessory；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L531](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L531-L531)；[Iap2Endpoint.kt:L684](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L684-L684)。

### 0xEA03 — externalaccessory_statusEASessionHandler

- 功能组：ExternalAccessory；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2MessageIds.kt:L70](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2MessageIds.kt#L70-L70)；[Iap2SenderSession.kt:L115](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2SenderSession.kt#L115-L115)；[Iap2SenderSession.kt:L246](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/iap2/Iap2SenderSession.kt#L246-L246)。

### 0xFFF0 — GPRMCDataStatusValues

- 功能组：Location；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据：本次词法扫描未定位，不据此断言功能不存在。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L517](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L517-L517)；[VirtualIap2Link.kt:L771](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L771-L771)；[VirtualIap2Link.kt:L950](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L950-L950)。

### 0xFFFA — StartLocationInformation

- 功能组：Location；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L310](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L310-L310)；[Iap2IdentificationClient.kt:L451](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L451-L451)；[Iap2LocationClient.kt:L36](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2LocationClient.kt#L36-L36)。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L517](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L517-L517)；[VirtualIap2Link.kt:L771](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L771-L771)；[VirtualIap2Link.kt:L943](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L943-L943)。

### 0xFFFB — LocationInformation

- 功能组：Location；catalog confidence：HIGH。
- 双端角色：配件发送该消息，手机接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：
  - `0x0000 NMEA: STRING optional`
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L305](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L305-L305)；[Iap2IdentificationClient.kt:L450](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L450-L450)；[Iap2LocationClient.kt:L51](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2LocationClient.kt#L51-L51)。
- 手机/发送侧词法证据（不等于已验证 handler）：[VirtualIap2Link.kt:L531](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L531-L531)；[VirtualIap2Link.kt:L532](GitHub-CarPlay-Projects/cardeck/app/src/main/java/io/github/shaonialife/cardeck/airplay/VirtualIap2Link.kt#L532-L532)；[Iap2Endpoint.kt:L397](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L397-L397)。

### 0xFFFC — StopLocationInformation

- 功能组：Location；catalog confidence：HIGH。
- 双端角色：手机发送该消息，配件接收并按该业务解析。
- 声明级别：只确认端点注册；运行期实现与执行结果需看对应 handler。
- 参数：本地 schema 未细化或有意保留 opaque，不能当作无参数。
- 配件/接收侧词法证据（不等于已验证 handler）：[Iap2IdentificationClient.kt:L310](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L310-L310)；[Iap2IdentificationClient.kt:L452](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2IdentificationClient.kt#L452-L452)；[Iap2LocationClient.kt:L147](DiPlay/shared/src/main/java/com/shilapi/xcertplay/transport/Iap2LocationClient.kt#L147-L147)。
- 手机/发送侧词法证据（不等于已验证 handler）：[Iap2Endpoint.kt:L404](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L404-L404)；[Iap2Endpoint.kt:L405](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L405-L405)；[Iap2Endpoint.kt:L593](GitHub-CarPlay-Projects/carlife-to-carplay/core-iap2/src/main/java/com/carplay/iap2/catalog/Iap2Endpoint.kt#L593-L593)。

## 提取校验

- 已逐项解析 ALL 注册表，集合等于 61 个具名声明加 90 个内联声明。
- 总数 151，唯一 ID 151，无重复 ID；具名声明全部进入 ALL。
- 保留嵌套字段、必选/可选、重复字段和本地 confidence；不执行任何下载仓库脚本。
- 此校验不是消息互通、认证、编码或实车测试。
