import { ProjectionApp } from './ProjectionAppTypes';

export const PROJECTION_MAP_URI: string = 'carplay-client://v1/apps/amap/launch';
const AMAP_LAUNCH_URI: string = 'amapuri://';
const HUAWEI_MUSIC_LAUNCH_URI: string = 'hwmusic://com.huawei.hmsapp.music';

export const PROJECTION_VEHICLE_APPS: ProjectionApp[] = [
  { appId: 'shell-home', uri: 'carplay-client://v1/shell/home', launchState: 'VERIFIED',
    label: '车机主页', mark: '', color: '#F5F5F7', category: 'vehicle',
    icon: 'app.media.ic_car_front', view: 'receiver' },
  { appId: 'shell-settings', uri: 'carplay-client://v1/shell/settings', launchState: 'VERIFIED',
    label: '设置', mark: '', color: '#61B9E8', category: 'vehicle',
    icon: 'app.media.ic_settings', view: 'settings' },
  { appId: 'shell-themes', uri: 'carplay-client://v1/shell/themes', launchState: 'VERIFIED',
    label: '主题', mark: '', color: '#41C99A', category: 'vehicle',
    icon: 'app.media.ic_palette', view: 'themes' },
  { appId: 'shell-split', uri: 'carplay-client://v1/shell/split', launchState: 'VERIFIED',
    label: '导航 + 音乐', mark: '', color: '#61B9E8', category: 'vehicle',
    icon: 'app.media.ic_layout_grid', view: 'split' }
];

export const PROJECTION_APP_CANDIDATES: ProjectionApp[] = [
  {
    appId: 'amap', uri: PROJECTION_MAP_URI, bundleName: 'com.amap.hmapp', abilityName: 'EntryAbility',
    launchState: 'UNVERIFIED',
    launchTarget: {
      kind: 'ability', bundleName: 'com.amap.hmapp', abilityName: 'EntryAbility',
      isSingleton: true, probeUri: AMAP_LAUNCH_URI
    },
    unavailableReason: '当前设备尚未核验高德地图的 bundle/Ability 入口',
    label: '高德地图', mark: '高', color: '#308A6E', category: 'map', icon: 'app.media.app_amap'
  },
  {
    appId: 'baidu-map', uri: 'carplay-client://v1/apps/baidu-map/launch', launchState: 'UNVERIFIED',
    launchTarget: { kind: 'appLink', uri: 'baidumap://map' },
    unavailableReason: '当前设备未解析到旧源码中的 baidumap://map 入口',
    label: '百度地图', mark: '百', color: '#4774A1', category: 'map', icon: 'app.media.app_baidu'
  },
  {
    appId: 'petal-maps', uri: 'carplay-client://v1/apps/petal-maps/launch',
    bundleName: 'com.huawei.hmos.maps.app', abilityName: 'EntryAbility', launchState: 'UNVERIFIED',
    launchTarget: { kind: 'appLink', uri: 'petalmaps://' },
    unavailableReason: '当前设备未解析到地图应用的 petalmaps:// 入口',
    label: '地图', mark: '图', color: '#5186B7', category: 'map', icon: 'app.media.ic_navigation'
  },
  {
    appId: 'tencent-map', uri: 'carplay-client://v1/apps/tencent-map/launch', launchState: 'UNVERIFIED',
    launchTarget: { kind: 'appLink', uri: 'qqmap://' },
    unavailableReason: '当前设备未解析到 qqmap:// 入口',
    label: '腾讯地图', mark: '腾', color: '#3977A5', category: 'map', icon: 'app.media.app_tencent_map'
  },
  {
    appId: 'huawei-music', uri: 'carplay-client://v1/apps/huawei-music/launch',
    bundleName: 'com.huawei.hmsapp.music', abilityName: 'MainAbility', launchState: 'UNVERIFIED',
    launchTarget: { kind: 'appLink', uri: HUAWEI_MUSIC_LAUNCH_URI },
    unavailableReason: '当前设备尚未核验华为音乐的 hwmusic URI 入口',
    label: '华为音乐', mark: '音', color: '#C56648', category: 'music', icon: 'app.media.app_huawei_music'
  },
  {
    appId: 'qq-music', uri: 'carplay-client://v1/apps/qq-music/launch', launchState: 'UNVERIFIED',
    launchTarget: { kind: 'appLink', uri: 'qqmusic://' },
    unavailableReason: '当前设备未解析到旧源码中的 qqmusic:// 入口',
    label: 'QQ 音乐', mark: 'Q', color: '#8A9B63', category: 'music', icon: 'app.media.app_qqmusic'
  },
  {
    appId: 'netease-music', uri: 'carplay-client://v1/apps/netease-music/launch', launchState: 'UNVERIFIED',
    launchTarget: { kind: 'appLink', uri: 'orpheus://' },
    unavailableReason: '当前设备未解析到旧源码中的 orpheus:// 入口',
    label: '网易云音乐', mark: 'N', color: '#B94442', category: 'music', icon: 'app.media.app_netease'
  },
  {
    appId: 'kugou-music', uri: 'carplay-client://v1/apps/kugou-music/launch', launchState: 'UNVERIFIED',
    launchTarget: { kind: 'appLink', uri: 'kugou://m.kugou.com' },
    unavailableReason: '当前设备未解析到 kugou://m.kugou.com 入口',
    label: '酷狗音乐', mark: '酷', color: '#D5A837', category: 'music', icon: 'app.media.app_kugou'
  },
  {
    appId: 'tangshui-music', uri: 'carplay-client://v1/apps/tangshui-music/launch',
    bundleName: 'com.salmon.sweetmusic', abilityName: 'EntryAbility', launchState: 'UNVERIFIED',
    launchTarget: { kind: 'appLink', uri: 'sweetmusic://' },
    unavailableReason: '当前设备未解析到溏心音乐的 sweetmusic:// 入口',
    label: '溏心音乐', mark: '溏', color: '#A875B5', category: 'music', icon: 'app.media.ic_music'
  },
  {
    appId: 'kuwo-music', uri: 'carplay-client://v1/apps/kuwo-music/launch',
    bundleName: 'com.hmkuwo.cn', abilityName: 'KuWoAbility', launchState: 'UNVERIFIED',
    launchTarget: { kind: 'appLink', uri: 'kwapp://' },
    unavailableReason: '当前设备未解析到酷我音乐的 kwapp:// 入口',
    label: '酷我音乐', mark: '酷', color: '#6E8FB4', category: 'music', icon: 'app.media.ic_music'
  }
];
