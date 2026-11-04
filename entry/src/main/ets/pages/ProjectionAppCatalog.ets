export type ProjectionAppCategory = 'map' | 'music' | 'home' | 'vehicle';
export type ProjectionLaunchState = 'VERIFIED' | 'UNVERIFIED';

export interface ProjectionApp {
  appId: string;
  uri: string;
  bundleName?: string;
  moduleName?: string;
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
  moduleName?: string;
  abilityName?: string;
  isSingleton?: boolean;
  uri?: string;
  probeUri?: string;
}

export interface ProjectionInstalledAbility {
  moduleName: string;
  abilityName: string;
  isMainElement: boolean;
  enabled: boolean;
  exported: boolean;
  isSingleton: boolean;
}

export type ProjectionAbilityLookup =
  (bundleName: string) => Promise<ProjectionInstalledAbility[]>;

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
    label: '酷狗音乐', mark: 'K', color: '#D5A837', category: 'music', icon: 'app.media.app_kugou'
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
  if (source.moduleName !== undefined) {
    copy.moduleName = source.moduleName;
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
  canOpenLink: (uri: string) => boolean,
  lookupInstalledAbilities?: ProjectionAbilityLookup
): Promise<ProjectionApp[]> {
  return Promise.all(PROJECTION_APP_CANDIDATES.map(async (candidate: ProjectionApp): Promise<ProjectionApp> => {
    const target = candidate.launchTarget;
    if (!target) {
      return candidate;
    }
    const resolved = copyProjectionApp(candidate);
    let abilityLookupSucceeded = false;
    let abilityLookupError = '';
    if (target.kind === 'ability' && target.bundleName && lookupInstalledAbilities) {
      try {
        const abilities = await lookupInstalledAbilities(target.bundleName);
        abilityLookupSucceeded = true;
        const isLaunchable = (ability: ProjectionInstalledAbility): boolean =>
          ability.enabled && ability.exported && ability.moduleName.length > 0 && ability.abilityName.length > 0;
        const expectedAbility = abilities.find((item: ProjectionInstalledAbility): boolean =>
          isLaunchable(item) && item.abilityName === target.abilityName);
        const ability = candidate.appId === 'amap'
          ? expectedAbility
          : expectedAbility ??
            abilities.find((item: ProjectionInstalledAbility): boolean => isLaunchable(item) && item.isMainElement) ??
            abilities.find((item: ProjectionInstalledAbility): boolean => isLaunchable(item));
        if (ability) {
          resolved.moduleName = ability.moduleName;
          resolved.abilityName = ability.abilityName;
          resolved.launchTarget = {
            kind: 'ability',
            bundleName: target.bundleName,
            moduleName: ability.moduleName,
            abilityName: ability.abilityName,
            isSingleton: ability.isSingleton,
            probeUri: target.probeUri
          };
          resolved.launchState = 'VERIFIED';
          resolved.unavailableReason = undefined;
          return resolved;
        }
      } catch (error) {
        abilityLookupError = error instanceof Error ? error.message : String(error);
      }
    }
    try {
      const probeUri = target.kind === 'ability' ? target.probeUri : target.uri;
      const available = probeUri !== undefined && canOpenLink(probeUri);
      resolved.launchState = available ? 'VERIFIED' : 'UNVERIFIED';
      if (available) {
        resolved.unavailableReason = undefined;
        if (target.kind === 'ability' && probeUri !== undefined && candidate.appId !== 'amap') {
          resolved.launchTarget = { kind: 'appLink', uri: probeUri };
        }
      } else if (abilityLookupError.length > 0) {
        resolved.unavailableReason = `检查已安装应用的启动 Ability 失败：${abilityLookupError}`;
      } else if (abilityLookupSucceeded) {
        resolved.unavailableReason = `${candidate.label} 已安装，但没有可外部启动的 Ability 或可用链接`;
      }
      return resolved;
    } catch (error) {
      resolved.launchState = 'UNVERIFIED';
      resolved.unavailableReason =
        `检查启动入口失败：${error instanceof Error ? error.message : String(error)}`;
      return resolved;
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

export function isProjectionAppInstanceMigratable(app: ProjectionApp): boolean {
  const target = app.launchTarget;
  return app.appId === 'amap' && target?.kind === 'ability' && target.isSingleton === true;
}

export function projectionAppLaunchTarget(
  app: ProjectionApp, preserveExistingInstance: boolean = false
): ProjectionLaunchTarget | undefined {
  const target = app.launchTarget;
  if (!isProjectionAppLaunchable(app) || !target) {
    return undefined;
  }
  if (preserveExistingInstance) {
    return isProjectionAppInstanceMigratable(app) ? target : undefined;
  }
  if (app.appId === 'amap' && target.kind === 'ability') {
    return target.probeUri ? { kind: 'appLink', uri: target.probeUri } : undefined;
  }
  return target;
}

export function findLaunchableProjectionApp(
  apps: ProjectionApp[],
  category: ProjectionAppCategory,
  preferredUri?: string,
  preferredBundleName?: string
): ProjectionApp | undefined {
  if (preferredUri !== undefined) {
    const preferred = apps.find((app: ProjectionApp): boolean =>
      app.category === category && app.uri === preferredUri);
    if (preferred) {
      return isProjectionAppLaunchable(preferred) ? preferred : undefined;
    }
  }
  if (preferredBundleName !== undefined) {
    const preferred = apps.find((app: ProjectionApp): boolean =>
      app.category === category && app.bundleName === preferredBundleName);
    if (preferred) {
      return isProjectionAppLaunchable(preferred) ? preferred : undefined;
    }
  }
  return apps.find((app: ProjectionApp): boolean =>
    app.category === category && isProjectionAppLaunchable(app));
}

export function activeProjectionMusicApp(
  apps: ProjectionApp[], activeAppUri: string
): ProjectionApp | undefined {
  const app = apps.find((candidate: ProjectionApp): boolean => candidate.uri === activeAppUri);
  return app && app.category === 'music' && isProjectionAppLaunchable(app) ? app : undefined;
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
