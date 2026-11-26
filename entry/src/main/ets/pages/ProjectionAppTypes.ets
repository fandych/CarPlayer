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
