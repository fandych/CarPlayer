import { hilog } from '@kit.PerformanceAnalysisKit';
import { ProjectionApp, activeProjectionMusicApp, findLaunchableProjectionApp, isProjectionAppLaunchable,
  PROJECTION_MAP_URI, PROJECTION_VEHICLE_APPS, projectionAppCatalog } from './ProjectionAppCatalog';
import { ProjectionDockItem } from './ProjectionDock';
import { ProjectionDashboardState } from './ProjectionDashboardState';
import { discoverProjectionApps, HOME_APP } from './ProjectionDashboardAppDiscovery';

const DOMAIN: number = 0xCA22;

export class ProjectionDashboardAppController {
  selectApp(state: ProjectionDashboardState, app: ProjectionApp): void {
    if (app.category === 'vehicle') {
      if (app.view === 'receiver') {
        state.receiverHomeMessage = '正在请求车机主页';
        state.onReceiverHomeClick();
        return;
      }
      this.showDashboardView(state, app.view ?? 'settings');
      return;
    }
    const keepSplitLayout = state.dashboardView === 'split' && app.category === 'music';
    if (app.category !== 'home' && !isProjectionAppLaunchable(app)) {
      state.appDiscoveryMessage = app.unavailableReason ?? `${app.label} 的启动入口尚未验证`;
      state.mediaActionMessage = state.appDiscoveryMessage;
      this.showDockActionMessage(state, state.appDiscoveryMessage);
      return;
    }
    state.dockActionMessage = '';
    state.preserveSplitSurfaceForOverlays = false;
    if (app.category === 'map') {
      state.selectedMapUri = app.uri;
      state.setStorage('carplaySelectedMapAppId', app.appId);
    } else if (app.category === 'music') {
      state.selectedMusicUri = app.uri;
    }
    state.dashboardView = keepSplitLayout ? 'split' : 'home';
    state.setStorage('carplayDashboardView', state.dashboardView);
    if (app.uri === HOME_APP.uri) {
      this.showHome(state);
    } else {
      this.setNavigationPreview(state, false);
      state.onAppClick(app);
    }
  }

  showHome(state: ProjectionDashboardState): void {
    this.setNavigationPreview(state, true);
    const mapUri = state.selectedMapUri || PROJECTION_MAP_URI;
    if (state.activeAppUri === mapUri && state.activeAppLabel.length > 0) {
      return;
    }
    const map = state.apps.find((app: ProjectionApp): boolean => app.uri === mapUri);
    if (map && isProjectionAppLaunchable(map)) {
      state.onAppClick(map);
    } else {
      if (map) {
        state.appDiscoveryMessage = map.unavailableReason ?? `${map.label} 的启动入口尚未验证`;
      }
      state.onHomeClick();
    }
  }

  setNavigationPreview(state: ProjectionDashboardState, preview: boolean): void {
    state.navigationPreview = preview;
    state.setStorage('carplayNavigationPreview', preview);
  }

  showDashboardView(state: ProjectionDashboardState, view: string): void {
    if (view === 'split' && !this.activeMusicApp(state)) {
      const message = state.appOnPhone
        ? '请先将音乐 app 切回车机屏幕，再进入分屏'
        : '请先从音乐 Dock 打开音乐 app，再进入分屏';
      state.mediaActionMessage = message;
      this.showDockActionMessage(state, message);
      return;
    }
    state.dockActionMessage = '';
    if (view === 'split' || view === 'home') {
      state.preserveSplitSurfaceForOverlays = false;
    } else if (state.dashboardView === 'split' &&
      (state.getStorage<number>('carplayEmbeddedMapDisplayId') ?? -1) > 0) {
      state.preserveSplitSurfaceForOverlays = true;
    }
    state.touchRouter.touchBounds.delete('grid');
    state.touchRouter.touchBounds.delete('media');
    state.dashboardView = view;
    state.setStorage('carplayDashboardView', view);
    if (view === 'split') {
      this.setNavigationPreview(state, false);
    }
  }

  async discoverApps(state: ProjectionDashboardState, refresh: boolean = true): Promise<void> {
    const installed = await discoverProjectionApps(refresh);
    state.apps = projectionAppCatalog(installed);
    const savedMapId = state.getStorage<string>('carplaySelectedMapAppId');
    const selectedMap = state.apps.find((app: ProjectionApp): boolean =>
      app.appId === savedMapId && app.category === 'map');
    state.selectedMapUri = selectedMap?.uri ?? PROJECTION_MAP_URI;
    if (!savedMapId) {
      state.setStorage('carplaySelectedMapAppId', 'amap');
    }
    const launchableCount = installed.filter((app: ProjectionApp): boolean =>
      isProjectionAppLaunchable(app)).length;
    state.appDiscoveryMessage = launchableCount > 0
      ? `${launchableCount} 个入口通过本机能力核验；目标屏实际显示仍需车机验证`
      : '未核验到可用入口；检查应用安装、querySchemes 与旧源码 URI 入口';
    if (state.activeAppLabel.length === 0) {
      this.showHome(state);
    }
  }

  openMediaApp(state: ProjectionDashboardState): void {
    const bundleName = state.mediaState.bundleName;
    const activeMediaApp = bundleName
      ? findLaunchableProjectionApp(state.apps, 'music', undefined, bundleName)
      : undefined;
    const app = activeMediaApp ?? this.launchableCategoryApp(state, 'music');
    if (app) {
      this.selectApp(state, app);
    } else {
      this.showDashboardView(state, 'music');
      this.showDockActionMessage(state, '当前音乐应用没有已验证的启动入口；请选择可用音乐 app');
    }
  }

  openMapApp(state: ProjectionDashboardState): void {
    const app = this.launchableCategoryApp(state, 'map');
    if (app) {
      this.selectApp(state, app);
    } else {
      this.showDashboardView(state, 'maps');
      this.showDockActionMessage(state, '所选导航 app 没有可用启动入口；请选择已验证的地图 app');
    }
  }

  isDashboardHome(state: ProjectionDashboardState): boolean {
    return state.dashboardView === 'home' && (state.navigationPreview || state.activeAppLabel.length === 0);
  }

  activeAppHasCategory(state: ProjectionDashboardState, category: 'map' | 'music'): boolean {
    return state.dashboardView === 'home' && !state.navigationPreview && state.activeAppUri.length > 0 &&
      state.apps.some((app: ProjectionApp): boolean =>
        app.uri === state.activeAppUri && app.category === category);
  }

  isDockItemSelected(state: ProjectionDashboardState, id: string): boolean {
    if (id === 'home') {
      return this.isDashboardHome(state);
    }
    if (id === 'apps' || id === 'split' || id === 'settings') {
      return state.dashboardView === id;
    }
    if (id === 'map') {
      return state.dashboardView === 'maps' || this.activeAppHasCategory(state, 'map');
    }
    if (id === 'music') {
      return state.dashboardView === 'music' || this.activeAppHasCategory(state, 'music');
    }
    return false;
  }

  dockItems(state: ProjectionDashboardState): ProjectionDockItem[] {
    return [
      { id: 'home', label: '首页', icon: 'app.media.ic_house', selected: this.isDockItemSelected(state, 'home') },
      { id: 'apps', label: '应用', icon: 'app.media.ic_layout_grid', selected: this.isDockItemSelected(state, 'apps') },
      { id: 'map', label: '地图', icon: 'app.media.ic_navigation', selected: this.isDockItemSelected(state, 'map') },
      { id: 'music', label: '音乐', icon: 'app.media.ic_music', selected: this.isDockItemSelected(state, 'music') },
      { id: 'split', label: '分屏', icon: 'app.media.ic_split', selected: this.isDockItemSelected(state, 'split') },
      { id: 'settings', label: '设置', icon: 'app.media.ic_settings', selected: this.isDockItemSelected(state, 'settings') }
    ];
  }

  toggleDockPosition(state: ProjectionDashboardState): void {
    state.dockPosition = state.dockPosition === 'bottom' ? 'left' : 'bottom';
  }

  categoryApp(state: ProjectionDashboardState, category: string): ProjectionApp | undefined {
    const selected = category === 'map' ? state.selectedMapUri : state.selectedMusicUri;
    return state.apps.find((app: ProjectionApp): boolean => app.category === category && app.uri === selected) ??
      state.apps.find((app: ProjectionApp): boolean => app.category === category &&
        (category === 'map' ? app.uri === PROJECTION_MAP_URI : app.bundleName === state.mediaState.bundleName)) ??
      state.apps.find((app: ProjectionApp): boolean => app.category === category);
  }

  launchableCategoryApp(state: ProjectionDashboardState, category: string): ProjectionApp | undefined {
    const selectedUri = category === 'map' ? state.selectedMapUri : state.selectedMusicUri;
    const selected = state.apps.find((app: ProjectionApp): boolean =>
      app.category === category && app.uri === selectedUri);
    if (selected) {
      return isProjectionAppLaunchable(selected) ? selected : undefined;
    }
    if (category === 'music' && state.mediaState.bundleName) {
      const mediaApp = state.apps.find((app: ProjectionApp): boolean =>
        app.category === category && app.bundleName === state.mediaState.bundleName);
      if (mediaApp) {
        return isProjectionAppLaunchable(mediaApp) ? mediaApp : undefined;
      }
    }
    return findLaunchableProjectionApp(state.apps, category === 'map' ? 'map' : 'music');
  }

  activeMusicApp(state: ProjectionDashboardState): ProjectionApp | undefined {
    return state.appOnPhone ? undefined : activeProjectionMusicApp(state.apps, state.activeAppUri);
  }

  visibleApps(state: ProjectionDashboardState): ProjectionApp[] {
    const visible: ProjectionApp[] = [...PROJECTION_VEHICLE_APPS];
    for (const app of state.apps) {
      if (isProjectionAppLaunchable(app)) {
        visible.push(app);
      }
    }
    return visible;
  }

  updateAppsGridColumns(state: ProjectionDashboardState, width: number): void {
    const columns = width < 360 ? 3 : width < 480 ? 4 : width < 640 ? 5 : 6;
    if (columns !== state.appsGridColumns) {
      state.appsGridColumns = columns;
    }
  }

  appsGridTemplate(state: ProjectionDashboardState): string {
    if (state.appsGridColumns === 3) {
      return '1fr 1fr 1fr';
    }
    if (state.appsGridColumns === 5) {
      return '1fr 1fr 1fr 1fr 1fr';
    }
    if (state.appsGridColumns === 6) {
      return '1fr 1fr 1fr 1fr 1fr 1fr';
    }
    return '1fr 1fr 1fr 1fr';
  }

  activateDock(state: ProjectionDashboardState, id: string, longPress: boolean = false): void {
    if (id === 'home') {
      this.selectApp(state, HOME_APP);
    } else if (id === 'apps') {
      this.showDashboardView(state, 'apps');
    } else if (id === 'settings') {
      this.showDashboardView(state, 'settings');
    } else if (id === 'split') {
      this.showDashboardView(state, 'split');
    } else if (id === 'map' || id === 'music') {
      const app = this.launchableCategoryApp(state, id);
      if (longPress || !app) {
        this.showDashboardView(state, id === 'map' ? 'maps' : 'music');
        if (!longPress && !app) {
          this.showDockActionMessage(state, id === 'map'
            ? '没有已验证的地图启动入口，请从导航列表中选择'
            : '没有已验证的音乐启动入口，请从音乐列表中选择');
        }
      } else {
        this.selectApp(state, app);
      }
    }
  }

  showDockActionMessage(state: ProjectionDashboardState, message: string): void {
    state.dockActionMessage = message;
    try {
      promptAction.showToast({ message });
    } catch (error) {
      hilog.warn(DOMAIN, 'CarPlayerProjection', '提示显示失败：%{public}s',
        error instanceof Error ? error.message : String(error));
    }
  }
}
