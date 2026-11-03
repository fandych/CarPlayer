# 投影应用 URI Schema 与启动参数

## 查询范围与结论边界

本记录基于 2026-11-03 通过 HDC 查询的当前连接 HarmonyOS 设备，应用范围取自 [ProjectionAppCatalog.ets](../entry/src/main/ets/pages/ProjectionAppCatalog.ets) 中的 14 个第三方应用候选。设备序列号不记录在文档中。14 个候选包在本次查询时均已安装；版本、模块和 Ability 名称只代表本次设备快照。

`bm dump` 中的 `hapModuleInfos[].abilityInfos[].skills[].uris[]` 描述 Ability 注册的 URI 匹配规则（scheme、host、path 等），不是完整的业务深链协议。它不会说明应用期望的 query 参数、Want parameters 或参数值含义。下表中的“用途”仅按已登记的 action、host 和 path 名称归类；未执行 `aa start`，不代表这些入口已实测成功，也不保证启动后显示在投影屏。

## HDC 查询和启动参数

```powershell
hdc list targets
hdc -t <target> shell bm dump -a
hdc -t <target> shell bm dump -n <bundle-name>
hdc -t <target> shell aa start
```

- `bm dump -a` 列出设备 bundle；`bm dump -n` 查询单个 bundle。重点查看版本、`hapModuleInfos[].moduleName`、`mainElementName`、`abilityInfos[].name` 和 `skills`。
- `skills` 中的 `actions`、`entities` 与 `uris` 共同描述 Want 匹配条件。URI 项可包含 `scheme`、`host`、`path`、`pathStartWith`、`pathRegex`；`domainVerify=true` 表示该项是域名验证的 Web Link 声明，不表示其应用内路由参数已经验证。
- 显式启动指定 Ability 的命令模板：

  ```powershell
  hdc -t <target> shell aa start -b <bundle-name> -m <module-name> -a <ability-name>
  ```

- 按 URI 隐式解析的命令模板：

  ```powershell
  hdc -t <target> shell aa start -A ohos.want.action.viewData -U '<registered-uri>'
  ```

- `aa start` 常用参数：`-b` bundle、`-m` module、`-a` Ability、`-U` URI、`-A` action、`-e` entity、`-t` MIME type。`--ps`、`--pi`、`--pb`、`--psn` 分别用于传入字符串、整数、布尔和 null 字符串类型的 Want 参数；它们是通用参数载体，不代表应用接受某个特定 key。
- 如果 URI 对应的 Skill 要求特定 entity，应按该 Skill 增加 `-e <entity>`；不要假定所有应用都使用相同 entity。
- 本次 `aa start` 帮助没有列出投影 `displayId` 参数。`-d` 是设备参数，不应当作显示屏 ID；这里的命令用于查询/验证启动入口，不等价于 CarPlayer 通过 API 指定目标屏。
- CarPlayer 的 `querySchemes` 是本应用查询其它应用链接时的可见性声明，并非第三方应用的 schema；见 [module.json5](../entry/src/main/module.json5)。

## 每个候选应用

“显式启动”列给出本次 HDC 查询到的 module/Ability 参数。URI 是应用注册或 CarPlayer 候选中已有的入口；除明确标注的 path/host 外，不推测额外参数。

| 应用 | 设备 bundle / 版本 | 显式启动参数 | 已登记的应用 URI / 含义 |
|---|---|---|---|
| 高德地图 | `com.amap.hmapp` / `17.02.0.2016` | `-m entry -a EntryAbility` | CarPlayer 候选 `amapuri://`；另登记 `systemnav://navigation`、`systemnav://routeplan`、`systemnav://poisearch`，分别是导航、路线规划、POI 搜索入口。还有 `https://m.amap.com` 的 `applink/` 路径前缀，以及 `qqopenapi://100571486`（auth/share）、`taobaooauth21792629://`、`ut.34657035://ut.open.realtime` 等集成 URI；它们不是已知导航参数。 |
| 百度地图 | `com.baidu.hmmap` / `1.21.0` | `-m entry -a EntryAbility` | 候选 `baidumap://map` 已登记；另有 `baidumap://hicarmap`、`baidumap://cuid`。HDC schema 不揭示导航目的地参数；官方 HarmonyOS 指南使用 `@bdmap/util` 的类型化 SDK API，见下节。 |
| Petal 地图 | `com.huawei.hmos.maps.app` / `6.3.3.306` | `-m entry -a EntryAbility` | 候选 `petalmaps://` 已登记；还登记 `maps://routes`、`maps://navigation`、`maps://locationInfo`、`maps://textSearch`、`maps://dataManagement`、`maps://offlineMap`，以及 `petalmaps://textSearch`、`loadweb`、`poidetail`、`findcar`、`themeMap`、`aiTravel`、`explore` 等路径前缀；另有 `geo://`。`maps://`/`petalmaps://` 覆盖不同地图功能入口，具体参数仍需应用协议文档或实测。 |
| 腾讯地图 | `com.tencent.mapohos` / `11.7.1` | `-m entry -a EntryAbility` | 候选 `qqmap://` 已登记；另有 `qqmap://navigation`、`qqmap://routePlan`、`qqmap://search`。设备还登记 `https://5gimg.map.qq.com` 下的 `map/routeplan` 路径、`qqopenapi://100379435`（auth/share）和 `midaspay://`（支付 action）。 |
| 华为音乐 | `com.huawei.hmsapp.music` / `1.9.4.300` | `-m phone -a MainAbility` | 候选 `hwmusic://com.huawei.hmsapp.music` 已登记；同一 scheme 还有 `clearcache` 路径前缀。另有 `hwmediacenter://com.android.mediacenter`（媒体中心交互入口）和华为音乐 Web 域名。 |
| QQ 音乐 | `com.tencent.hm.qqmusic` / `3.5.0.4` | `-m entry -a EntryAbility` | 候选 `qqmusic://` 已登记；另有 `https://music.qq.com`、`https://uni.y.qq.com` 和 `qqopenapi://100497308`（OpenAPI 授权/分享类匹配）。 |
| 网易云音乐 | `com.netease.cloudmusic.hm` / `9.6.27` | `-m entry -a EntryAbility` | 候选 `orpheus://` 已登记；另有 `orpheus-cortana://`、`cmapi://`、`https://m.music.163.com` 和 `qqopenapi://100495085`（授权/分享类匹配）。 |
| 酷狗音乐 | `com.kugou.hmmusic` / `20.4.5.0` | `-m entry -a MainAbility` | 候选 `kugou://m.kugou.com` 已登记；还登记 `kugou://start.nfc`、`start.weixin`、`start.quicklogin`、`start.alipay`，`kugouurl://start.weixin`、`start.fanxing`，以及 `qqopenapi://205141` 的授权/分享路径。`start.*` 是对应集成/快捷入口，不应当当作通用播放参数。 |
| 溏心音乐 | `com.salmon.sweetmusic` / `7.0.1` | `-m entry -a EntryAbility` | 候选 `sweetmusic://` 已登记；另有 `https://www.biandangroup.com` 下的 `sweetmusic` 路径前缀。 |
| 酷我音乐 | `com.hmkuwo.cn` / `1.2.4.0` | `-m entry -a KuWoAbility` | 候选 `kwapp://` 已登记；另有 `kwunionlogin://`（名称指向联合登录）、`qqopenapi://100243533`（授权/分享类匹配）和 `https://oia.kuwo.cn`。 |
| 抖音 | `com.ss.hm.ugc.aweme` / `40.9.0` | `-m entry -a MainAbility` | 候选 `snssdk1128://` 已登记；另有 `sslocal://`、`douyinopensdk://openplatform`、`share_v1`、`share_v2`、`auth_v1`、`douyinUPPay1128Share://`、`ttcjpay://`、`dypay1128://`、`cjsign://` 和 `accountsdk1128://`。SDK、授权、支付和签名入口不是普通“打开首页”的替代参数。 |
| 快手 | `com.kuaishou.hmapp` / `14.9.20` | `-m kwai -a EntryAbility` | 候选 `kwai://` 已登记；另有 `kwai://settingstoragePage`（设置存储页）、`https://k.ksurl.cn` 和 `qqopenapi://100228415`（授权/分享类匹配）。设备的主 module 名是 `kwai`，显式 Want 应带该 module。 |
| 东方财富 | `com.eastmoney.hmn.berlin` / `1.24.2` | `-m entry -a EntryAbility` | 候选 `emoh://eastmoney.com` 已登记，对应 action 包含 `ohos.want.action.viewData`；另有 `com.eastmoney.action` 自定义 action、`mlink.eastmoney.com` Web Link 和 `qqopenapi://100507134`（授权/分享类匹配）。 |
| 腾讯视频 | `com.tencent.videohm` / `9.04.71.13000` | `-m app -a AppAbility` | 候选 `tenvideo2://` 已登记；另有 `txvideo://`，并登记 `HomeActivity`、`VideoDetailActivity`、`SearchPagerActivity`、`PlayHistroryActivity` 等路径/host 项。另有 `qqopenapi://101795054`（授权/分享类匹配）。具体页面参数不在 dump 的 schema 中。独立的 `SchemeRouterAbility` 调试 URI 不作为通用启动入口。 |

## 官方文档补充：地图路径规划与导航

### 高德地图手机版 HarmonyOS NEXT

官方的路径规划入口是 `amapuri://route/plan/`，不是只有 scheme 的 `amapuri://`。高德文档示例通过 `UIAbilityContext.startAbility({ uri })` 启动，核心 URI 形式为：

```text
amapuri://route/plan/?slon=<起点经度>&slat=<起点纬度>&sname=<起点名称>&dlon=<终点经度>&dlat=<终点纬度>&dname=<终点名称>&t=<出行方式>&sourceApplication=<调用方名称>
```

| 参数 | 要求 | 官方说明 |
|---|---|---|
| `slon`、`slat`、`sname` | 必填 | 起点经度、纬度和名称 |
| `dlon`、`dlat`、`dname` | 必填 | 终点经度、纬度和名称 |
| `t` | 必填 | 出行类型：驾车 `0`、公交地铁 `1`、步行 `2`、骑行 `3`、货车 `7`、摩托车 `11`、新能源 `12` |
| `sourceApplication` | 必填 | 调用方应用名称 |
| `sid`、`did` | 可选 | 起点、终点 POI ID |
| `vialons`、`vialats`、`vianames`、`viaids` | 可选 | 途经点的经度、纬度、名称和 ID；多个值用 `|` 分隔 |

官方示例还带有 `m`、`dev`、`vian`、`userRelationToken` 等字段，但该页参数表未说明它们的含义或必填性；不要仅凭示例猜测并填入。设备 `bm dump` 只显示 `amapuri` scheme，不会列出 `route/plan` 的 query 参数。  
来源：[高德地图手机版：路径规划（HarmonyOS NEXT）](https://lbs.amap.com/api/amap-mobile/guide/harmony-os/route-next)

### 腾讯地图 HarmonyOS NEXT

官方路线规划 URI 是 `qqmap://map/routeplan`。当前设备的 `bm dump` 确认注册了 `qqmap` scheme，但没有证明下面这条完整路径及其 query 参数已在 CarPlayer 中实测：

```text
qqmap://map/routeplan?type=<drive|bus|walk>&fromcoord=<纬度>,<经度>&tocoord=<纬度>,<经度>&referer=<开发者Key>
```

| 参数 | 要求 | 官方说明 |
|---|---|---|
| `type` | 必填 | `bus` 公交、`drive` 驾车、`walk` 步行；文档注明 HarmonyOS 暂不支持 `bike` 骑行 |
| `fromcoord` | 必填 | 起点坐标，格式为“纬度,经度”；`CurrentLocation` 表示当前位置 |
| `tocoord` | 必填 | 终点坐标，格式为“纬度,经度” |
| `referer` | 必填 | 腾讯位置服务开发者 Key |
| `from`、`to` | 可选 | 起点、终点名称 |
| `touid` | 可选 | 终点 POI ID；官方提醒它应与 `tocoord` 接近 |
| `passes` | 可选 | 最多 15 个途经点，格式为 `name:<名称>;coord:<纬度>,<经度>|...` |

不要把当前目录里的通用 `qqmap://` 当成已填好的路线规划 URI；需要规划路线时，应使用官方路径和必填参数，并通过设备实测确认解析结果。  
来源：[腾讯位置服务：导航和路线规划 URI](https://lbs.qq.com/webApi/uriV1/uriGuide/uriMobileRoute)

### 百度地图 HarmonyOS SDK

给出的百度官方指南使用 HarmonyOS SDK `@bdmap/util` 调起地图客户端，而不是定义一条通用的路线规划 URI。文档列出的能力包括主图、标注、反 GEO、POI 检索、路线页、步行/骑行路线规划、导航和货车导航。路线规划示例通过 `DirectionPageParamModel` 构造 Want 参数：

```typescript
const routeParam = new DirectionPageParamModel()
  .setPageflag('4')
  .setPopRoot(IsTrueEnum.NO)
  .setSrc(SrcTypeEnum.DUHELPER)
  .setOrigin('<起点>')
  .setOriginName('<起点名称>')
  .setDestination('<终点>')
  .setDestName('<终点名称>')
  .setMode(TravelMethodEnum.WALKING)
  .setCoord_type(CoordTypeEnum.BD09LL);

BaiduMapRoutePlan.openBaiduMapDirectionPage(routeParam, context);
```

官方导航示例使用 `NaviPageParamModel.setLocation('<纬度>,<经度>')`、`setUid('<POI UID>')` 和 `setCoord_type(CoordTypeEnum.BD09LL)`，再调用 `BaiduMapNavigation.openBaiduMapNavi(...)`。路线页、导航页、两框页各有不同参数模型；不要将这些 SDK 参数臆造为 `baidumap://map?...` query。  
来源：[百度地图开放平台：调起百度地图功能（HarmonyOS）](https://lbsyun.baidu.com/docs/harmony?title=harmonynextsdk/guide/tool/baiduapi)

## 解读与限制

1. 表中的显式 `aa start` 形式由本次设备的 bundle/module/Ability 元数据拼出；本记录没有执行它们，也没有改变应用状态。代码启动前还应确认 Ability 可由调用方访问，以及目标 OS/应用版本支持该入口。
2. URI 能匹配不等于 URI 参数已知。上面高德、腾讯的路线参数来自各自官方文档；其它导航目的地、搜索关键词、播放内容等参数，仍不能仅凭 `bm dump` 推导。
3. 不把通用 `file://`、`content://`、普通网页打开规则和支付/登录/分享 SDK callback 当作第三方 APP 的常规启动 schema。上表保留与应用启动或应用功能入口相关的注册项。
4. `aa start` 命令成功只证明系统接受启动请求；目标虚拟屏呈现、应用是否保留任务以及触摸/返回键能否工作，仍需单独在设备上验收。

## Android 手机 ADB 对照快照

本节是 2026-11-03 在当前 Android 手机上的新增只读快照（Android 12 / API 31）。使用 `pm list packages`、`dumpsys package` 和 Package Manager 的 resolve/query 命令；**没有执行 `am start`，未启动任何应用**。包版本、入口和 URI 规则仅代表本次安装状态。

本次查询方式：

```powershell
adb shell pm list packages
adb shell dumpsys package <package-name>
adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER <package-name>
adb shell cmd package query-activities --brief -a android.intent.action.VIEW -d '<uri>'
```

`query-activities` 只问系统“哪一个 Activity 能处理这个 Intent”，不会启动 Activity。下面的 URI 解析记录也只证明该设备当前的 Intent-filter 能匹配，不证明业务页面或目标屏效果。

| 候选应用 | Android 包 / 版本 / 主入口 | Android 侧观察到的 schema 与变化 |
|---|---|---|
| 高德地图 | `com.autonavi.minimap` / `17.02.0.2010` / `com.autonavi.map.activity.SplashActivity` | `amapuri` 仍在；官方路线 URI `amapuri://route/plan/?...` 已由 `VIEW` 查询解析到 `SchemeHandleActivity`。Android 还注册 `geo`、`navi`、`pois`、`wechatnav`、`androidamap`、`amapuriucar`、`amapuricruise`、`amapurihicar`、`amapquickuri` 等。与鸿蒙快照的 `systemnav://...` 不同，Android 侧使用 `navi` / `pois` 等 scheme。 |
| 百度地图 | `com.baidu.BaiduMap` / `22.1.20` / `com.baidu.baidumaps.WelcomeScreen.Alias0` | 注册 `baidumap`、`bdmap`、`bdapp`、`geo`、`baidumapmecp`、`mapbainuo`、`openapp` 等。`baidumap://map` 可解析到主界面 Alias；`bdmap://bdmap` 可解析到 `TalosSchemeProxyActivity`，但 `bdmap://map` 不匹配（filter 要求 authority 为 `bdmap`）。鸿蒙候选的 `baidumap://map` 在该 Android 设备上仍能匹配，但这不代表鸿蒙 SDK 的类型化参数协议与 Android URI 协议相同。 |
| 抖音 | `com.ss.android.ugc.aweme` / `40.9.0` / `.splash.SplashActivity` | `snssdk1128` 可解析到 `DeepLinkHandlerActivity`；另有 `snssdk0`、`trans1128`、`splash1128`、`douyinopenplatform`、`dygame` 及支付/授权相关 scheme。鸿蒙快照使用的 `sslocal`、`douyinopensdk` 没有出现在 Android 的主 scheme 列表中。 |
| 快手 | `com.smile.gifmaker` / `14.9.30.50933` / `com.yxcorp.gifshow.HomeActivity` | 注册 `kwai`、`ks`、`ksminiapp`、`ksnebula`、`kwailive`、`kwainative`、`kwaiopensdk`、`kwaipaysdk` 等。裸 `kwai://` 无匹配；`kwai://home` 解析到 `UriRouterActivity`，但这里只验证了路由分发，未验证其最终页面语义。 |
| 腾讯视频（华为包变体） | `com.tencent.qqlivehuawei` / `1.0.0.305` / 没有解析到 `MAIN/LAUNCHER` Activity | 未发现 `tenvideo2` handler；dump 仅见一个不透明 scheme `zas123sed1f31as654f621` 指向 `.MainActivity`。不要把它当作腾讯视频公开启动 schema。此前鸿蒙快照的 `com.tencent.videohm` 不在本机匹配结果中。 |
| 华为音乐 / 媒体中心 | `com.android.mediacenter` / `12.11.46.300` / `.PageActivity`；`com.huawei.music.local` / `1.0.0.304` / `.main.MainActivity` | Android 上没有找到鸿蒙包 `com.huawei.hmsapp.music`。媒体中心注册 `hwmediacenter://`，但需要具体路径：`.../showrunplaylist` 和 `.../searchSongsAndPlay` 都可解析到 `LauncherActivity`；`showrunplaylist` 的 filter 还带 action `com.huawei.mediacenter.START_RUNLIST`。本地音乐包另有 `huaweimusiclocal://com.huawei.music.local/shortcutconfirm`，指向快捷方式确认页。鸿蒙候选 `hwmusic://com.huawei.hmsapp.music` 在此设备无匹配。 |
| Petal 地图 | 未找到匹配的已安装包 | 本次包列表未发现对应地图客户端，无法检查 Android schema。 |
| 腾讯地图 | 未找到匹配的已安装包 | 未发现 `com.tencent.map` 等匹配包，无法检查 `qqmap` 路由。 |
| QQ 音乐 | 未找到匹配的已安装包 | 无法检查 Android URI schema。 |
| 网易云音乐 | 未找到匹配的已安装包 | 无法检查 Android URI schema。 |
| 酷狗音乐 | 未找到匹配的已安装包 | 无法检查 Android URI schema。 |
| 溏心音乐 | 未找到匹配的已安装包 | 无法检查 Android URI schema。 |
| 酷我音乐 | 未找到匹配的已安装包 | 无法检查 Android URI schema。 |
| 东方财富 | 未找到匹配的已安装包 | 无法检查 Android URI schema。 |

### 本次对比结论

- **Amap**：相同 `amapuri` 入口在 Android 版指向 Android Activity；官方路线格式可由系统解析。HDC 的 HarmonyOS `skills.uris` 不包含 Android 的 Activity 名称，不能用 Android Component 替代 Harmony Want。
- **Baidu**：Android 当前包注册 `baidumap` / `bdmap` / `bdapp` 等多套 scheme；鸿蒙版文档所述 `@bdmap/util` 模型不是这些 Android URI 的同义写法。
- **抖音、快手**：两端有相同主 scheme 名（`snssdk1128`、`kwai`），但 handler、模块和路由分发表不同；仅有同名 scheme 不能证明路径和参数可跨平台复用。
- **其它候选**：本机未装大多数候选，且音乐、腾讯视频存在平台/渠道包差异；“未找到匹配包”不能推断该应用没有 Android 版 schema。
- URI schema 属于应用版本和平台的实现细节。没有厂商公开协议或实测前，不把支付、登录、分享、推送、内部 router 等 filter 当作通用启动入口。
