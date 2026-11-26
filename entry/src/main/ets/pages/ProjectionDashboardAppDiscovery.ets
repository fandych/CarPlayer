import bundleManager from '@ohos.bundle.bundleManager';
import { ProjectionApp, resolveProjectionApps } from './ProjectionAppCatalog';

let projectionAppDiscovery: Promise<ProjectionApp[]> | undefined = undefined;

export const HOME_APP: ProjectionApp = {
  appId: 'shell-home',
  uri: 'carplay-client://v1/shell/home',
  launchState: 'VERIFIED',
  label: '首页',
  mark: 'C',
  color: '#0A84FF',
  category: 'home'
};

export function discoverProjectionApps(refresh: boolean = false): Promise<ProjectionApp[]> {
  if (projectionAppDiscovery && !refresh) {
    return projectionAppDiscovery;
  }
  projectionAppDiscovery = resolveProjectionApps(
    (uri: string): boolean => bundleManager.canOpenLink(uri)
  ).catch((error: Error): never => {
    projectionAppDiscovery = undefined;
    throw error;
  });
  return projectionAppDiscovery;
}
