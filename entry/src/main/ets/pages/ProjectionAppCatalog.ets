import {
  ProjectionAbilityLookup,
  ProjectionApp,
  ProjectionAppCategory,
  ProjectionInstalledAbility,
  ProjectionLaunchState,
  ProjectionLaunchTarget
} from './ProjectionAppTypes';
export {
  ProjectionAbilityLookup,
  ProjectionApp,
  ProjectionAppCategory,
  ProjectionInstalledAbility,
  ProjectionLaunchState,
  ProjectionLaunchTarget
} from './ProjectionAppTypes';

import {
  PROJECTION_APP_CANDIDATES,
  PROJECTION_MAP_URI,
  PROJECTION_VEHICLE_APPS
} from './ProjectionAppCatalogData';
export { PROJECTION_APP_CANDIDATES, PROJECTION_MAP_URI, PROJECTION_VEHICLE_APPS } from './ProjectionAppCatalogData';

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
