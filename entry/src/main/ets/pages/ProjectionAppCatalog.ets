export type ProjectionAppCategory = 'map' | 'music' | 'video' | 'finance' | 'home' | 'vehicle';
export type ProjectionLaunchState = 'VERIFIED' | 'UNVERIFIED';

export interface ProjectionApp {
  appId: string;
  uri: string;
  bundleName?: string;
  abilityName?: string;
  launchTarget?: ProjectionLaunchTarget;
  launchState: ProjectionLaunchState;
  unavailableReason?: string;
  icon?: string;
  symbol?: string;
  view?: string;
  label: string;
  mark: string;
  color: string;
  category: ProjectionAppCategory;
}

export interface ProjectionLaunchTarget {
  kind: 'ability' | 'appLink';
  bundleName?: string;
  abilityName?: string;
  uri?: string;
  probeUri?: string;
}

export const PROJECTION_MAP_URI: string = 'carplay-client://v1/apps/amap/launch';
const AMAP_LAUNCH_URI: string = 'amapuri://com.amap.hmapp/open';

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
      kind: 'ability', bundleName: 'com.amap.hmapp', abilityName: 'EntryAbility', probeUri: AMAP_LAUNCH_URI
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
    appId: 'petal-maps', uri: 'carplay-client://v1/apps/petal-maps/launch', launchState: 'UNVERIFIED',
    unavailableReason: '旧源码没有可复用的公开启动入口',
    label: 'Petal 地图', mark: 'P', color: '#5186B7', category: 'map', icon: 'app.media.ic_navigation'
  },
  {
    appId: 'tencent-map', uri: 'carplay-client://v1/apps/tencent-map/launch', launchState: 'UNVERIFIED',
    launchTarget: { kind: 'appLink', uri: 'qqmap://map/routeplan' },
    unavailableReason: '当前设备未解析到旧源码中的 qqmap://map/routeplan 入口',
    label: '腾讯地图', mark: '腾', color: '#3977A5', category: 'map', icon: 'app.media.app_tencent_map'
  },
  {
    appId: 'huawei-music', uri: 'carplay-client://v1/apps/huawei-music/launch',
    bundleName: 'com.huawei.hmsapp.music', abilityName: 'MainAbility', launchState: 'UNVERIFIED',
    launchTarget: {
      kind: 'ability', bundleName: 'com.huawei.hmsapp.music', abilityName: 'MainAbility', probeUri: 'hwmusic://'
    },
    unavailableReason: '当前设备尚未核验华为音乐的 bundle/Ability 入口',
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
    launchTarget: { kind: 'appLink', uri: 'kugou://' },
    unavailableReason: '当前设备未解析到旧源码中的 kugou:// 入口',
    label: '酷狗音乐', mark: 'K', color: '#D5A837', category: 'music', icon: 'app.media.app_kugou'
  },
  {
    appId: 'tangshui-music', uri: 'carplay-client://v1/apps/tangshui-music/launch', launchState: 'UNVERIFIED',
    unavailableReason: '旧源码没有可复用的公开启动入口',
    label: '糖水音乐', mark: '糖', color: '#A875B5', category: 'music', icon: 'app.media.ic_music'
  },
  {
    appId: 'douyin', uri: 'carplay-client://v1/apps/douyin/launch',
    bundleName: 'com.ss.hm.ugc.aweme', abilityName: 'MainAbility', launchState: 'UNVERIFIED',
    launchTarget: {
      kind: 'ability', bundleName: 'com.ss.hm.ugc.aweme', abilityName: 'MainAbility', probeUri: 'snssdk1128://'
    },
    unavailableReason: '当前设备尚未核验抖音的 bundle/Ability 入口',
    label: '抖音', mark: 'D', color: '#313941', category: 'video', icon: 'app.media.app_douyin'
  },
  {
    appId: 'kuaishou', uri: 'carplay-client://v1/apps/kuaishou/launch',
    bundleName: 'com.kuaishou.hmapp', abilityName: 'EntryAbility', launchState: 'UNVERIFIED',
    launchTarget: {
      kind: 'ability', bundleName: 'com.kuaishou.hmapp', abilityName: 'EntryAbility', probeUri: 'kwai://'
    },
    unavailableReason: '当前设备尚未核验快手的 bundle/Ability 入口',
    label: '快手', mark: 'K', color: '#DC7136', category: 'video', icon: 'app.media.app_kuaishou'
  },
  {
    appId: 'eastmoney', uri: 'carplay-client://v1/apps/eastmoney/launch',
    bundleName: 'com.eastmoney.hmn.berlin', abilityName: 'EntryAbility', launchState: 'UNVERIFIED',
    launchTarget: {
      kind: 'ability', bundleName: 'com.eastmoney.hmn.berlin', abilityName: 'EntryAbility', probeUri: 'emoh://'
    },
    unavailableReason: '当前设备尚未核验东方财富的 bundle/Ability 入口',
    label: '东方财富', mark: '财', color: '#C84D44', category: 'finance', icon: 'app.media.app_eastmoney'
  },
  {
    appId: 'tencent-video', uri: 'carplay-client://v1/apps/tencent-video/launch',
    bundleName: 'com.tencent.videohm', abilityName: 'AppAbility', launchState: 'UNVERIFIED',
    launchTarget: {
      kind: 'ability', bundleName: 'com.tencent.videohm', abilityName: 'AppAbility', probeUri: 'tenvideo2://'
    },
    unavailableReason: '当前设备尚未核验腾讯视频的 bundle/Ability 入口',
    label: '腾讯视频', mark: '▶', color: '#327A99', category: 'video', icon: 'app.media.app_tencent_video'
  }
];

function copyProjectionApp(source: ProjectionApp): ProjectionApp {
  const copy: ProjectionApp = {
    appId: source.appId,
    uri: source.uri,
    launchState: source.launchState,
    label: source.label,
    mark: source.mark,
    color: source.color,
    category: source.category
  };
  if (source.bundleName !== undefined) {
    copy.bundleName = source.bundleName;
  }
  if (source.abilityName !== undefined) {
    copy.abilityName = source.abilityName;
  }
  if (source.launchTarget !== undefined) {
    copy.launchTarget = source.launchTarget;
  }
  if (source.unavailableReason !== undefined) {
    copy.unavailableReason = source.unavailableReason;
  }
  if (source.icon !== undefined) {
    copy.icon = source.icon;
  }
  if (source.symbol !== undefined) {
    copy.symbol = source.symbol;
  }
  if (source.view !== undefined) {
    copy.view = source.view;
  }
  return copy;
}

export async function resolveProjectionApps(
  canOpenLink: (uri: string) => boolean
): Promise<ProjectionApp[]> {
  return Promise.all(PROJECTION_APP_CANDIDATES.map(async (candidate: ProjectionApp): Promise<ProjectionApp> => {
    const target = candidate.launchTarget;
    if (!target) {
      return candidate;
    }
    try {
      const probeUri = target.kind === 'ability' ? target.probeUri : target.uri;
      const available = probeUri !== undefined && canOpenLink(probeUri);
      const resolved = copyProjectionApp(candidate);
      resolved.launchState = available ? 'VERIFIED' : 'UNVERIFIED';
      if (available) {
        resolved.unavailableReason = undefined;
      }
      return resolved;
    } catch (error) {
      const unresolved = copyProjectionApp(candidate);
      unresolved.launchState = 'UNVERIFIED';
      unresolved.unavailableReason =
        `检查启动入口失败：${error instanceof Error ? error.message : String(error)}`;
      return unresolved;
    }
  }));
}

export function projectionAppCatalog(available: ProjectionApp[]): ProjectionApp[] {
  return PROJECTION_APP_CANDIDATES.map((candidate: ProjectionApp): ProjectionApp =>
    available.find((app: ProjectionApp): boolean => app.appId === candidate.appId) ?? candidate);
}

export function isProjectionAppLaunchable(app: ProjectionApp): boolean {
  return app.launchState === 'VERIFIED' && app.launchTarget !== undefined;
}

export function includeMediaSessionApp(
  apps: ProjectionApp[], bundleName?: string, abilityName?: string
): ProjectionApp[] {
  if (!bundleName || !abilityName) {
    return apps;
  }
  const knownApp = apps.find((candidate: ProjectionApp): boolean =>
    candidate.bundleName === bundleName &&
    (candidate.abilityName === undefined || candidate.abilityName === abilityName));
  if (knownApp) {
    return apps;
  }
  const appId = `active-media-${encodeURIComponent(bundleName)}`;
  const app: ProjectionApp = {
    appId,
    uri: `carplay-client://v1/apps/${appId}/launch`,
    bundleName,
    abilityName,
    launchState: 'UNVERIFIED',
    unavailableReason: '媒体会话可用不代表旧源码中存在已核验的打开入口',
    icon: 'app.media.ic_music',
    label: '当前播放器',
    mark: '音',
    color: '#8A9B63',
    category: 'music'
  };
  return [...apps, app];
}
