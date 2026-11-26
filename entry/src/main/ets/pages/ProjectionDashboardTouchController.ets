import { CarPlayTouchReport } from '../video/CarPlayTouchInput';
import { ProjectionBounds, ProjectionPoint } from './ProjectionTouchRouter';
import { ProjectionMapSurface } from './ProjectionSurface';
import { ProjectionDashboardState } from './ProjectionDashboardState';
import { ProjectionDashboardSettingsController } from './ProjectionDashboardSettingsController';

export class ProjectionDashboardTouchController {
  private emptyBounds(): ProjectionBounds {
    return { left: 0, top: 0, right: 0, bottom: 0 };
  }

  scrollControllerAt(state: ProjectionDashboardState, x: number, y: number): Scroller | undefined {
    const emptyBounds = this.emptyBounds();
    if (state.touchRouter.contains(state.touchRouter.touchBounds.get('dock') ?? emptyBounds, x, y)) {
      return state.dockScroller;
    }
    if (state.dashboardView === 'apps' &&
      state.touchRouter.contains(state.touchRouter.touchBounds.get('grid') ?? emptyBounds, x, y)) {
      return state.appsScroller;
    }
    if ((state.dashboardView === 'maps' || state.dashboardView === 'music') &&
      state.touchRouter.contains(state.touchRouter.touchBounds.get(state.dashboardView) ?? emptyBounds, x, y)) {
      return state.dockMenuScroller;
    }
    if (state.dashboardView === 'settings' &&
      state.touchRouter.contains(state.touchRouter.touchBounds.get('settingsContent') ?? emptyBounds, x, y)) {
      return state.settingsScroller;
    }
    if (state.dashboardView === 'themes' &&
      state.touchRouter.contains(state.touchRouter.touchBounds.get('themes') ?? emptyBounds, x, y)) {
      return state.themesScroller;
    }
    if (state.navigationPreview &&
      state.touchRouter.contains(state.touchRouter.touchBounds.get('media') ?? emptyBounds, x, y)) {
      return state.sidebarMediaScroller;
    }
    return undefined;
  }

  handleTouchReport(state: ProjectionDashboardState, report: CarPlayTouchReport | undefined): void {
    state.touchRouter.handleReport(
      report,
      state.getStorage<boolean>('carplayProjectionHomeActive') === true,
      state.getStorage<number>('carplayProjectionDisplayId') ?? -1,
      state.dashboardView,
      (x: number, y: number): ProjectionPoint => state.canvasPixelToContentPoint(x, y),
      (x: number, y: number): Scroller | undefined => this.scrollControllerAt(state, x, y)
    );
  }

  handleAppSurfaceChange(
    state: ProjectionDashboardState, surfaceId: string, area: Area | undefined, attached: boolean
  ): void {
    if (!attached) {
      state.appSurfaceId = '';
      state.appSurfaceArea = undefined;
      state.onAppSurfaceChange(undefined);
      return;
    }
    state.appSurfaceId = surfaceId;
    state.appSurfaceArea = area;
    const ui = state.getUIContext();
    if (!area || !surfaceId) {
      return;
    }
    const surface: ProjectionMapSurface = {
      surfaceId,
      left: Math.round(ui.vp2px(Number.parseFloat(`${area.globalPosition.x}`))),
      top: Math.round(ui.vp2px(Number.parseFloat(`${area.globalPosition.y}`))),
      width: Math.round(ui.vp2px(Number.parseFloat(`${area.width}`))),
      height: Math.round(ui.vp2px(Number.parseFloat(`${area.height}`)))
    };
    if (surface.width > 0 && surface.height > 0) {
      state.onAppSurfaceChange(surface);
    }
  }

  handleMapSurfaceChange(
    state: ProjectionDashboardState, surfaceId: string, area: Area | undefined, attached: boolean
  ): void {
    if (!attached) {
      state.mapSurfaceLoaded = false;
      state.mapSurfaceId = '';
      state.mapSurfaceArea = undefined;
      state.lastMapSurface = undefined;
      state.onMapSurfaceChange(undefined);
      return;
    }
    state.mapSurfaceLoaded = true;
    state.mapSurfaceId = surfaceId;
    state.mapSurfaceArea = area;
    const ui = state.getUIContext();
    if (!surfaceId || !area ||
      Number.parseFloat(`${area.width}`) <= 0 || Number.parseFloat(`${area.height}`) <= 0) {
      return;
    }
    const surface: ProjectionMapSurface = {
      surfaceId,
      left: Math.round(ui.vp2px(Number.parseFloat(`${area.globalPosition.x}`))),
      top: Math.round(ui.vp2px(Number.parseFloat(`${area.globalPosition.y}`))),
      width: Math.round(ui.vp2px(Number.parseFloat(`${area.width}`))),
      height: Math.round(ui.vp2px(Number.parseFloat(`${area.height}`)))
    };
    if (surface.width <= 0 || surface.height <= 0) {
      return;
    }
    const previous = state.lastMapSurface;
    if (previous && previous.surfaceId === surface.surfaceId && previous.left === surface.left &&
      previous.top === surface.top && previous.width === surface.width && previous.height === surface.height) {
      return;
    }
    state.lastMapSurface = surface;
    state.onMapSurfaceChange(surface);
  }

  areaBounds(area: Area): ProjectionBounds {
    const left = Number.parseFloat(`${area.globalPosition.x}`);
    const top = Number.parseFloat(`${area.globalPosition.y}`);
    return {
      left,
      top,
      right: left + Number.parseFloat(`${area.width}`),
      bottom: top + Number.parseFloat(`${area.height}`)
    };
  }

  updateTouchArea(state: ProjectionDashboardState, group: string, key: string, area: Area, action: () => void,
    longPress?: () => void, drag?: (pointX: number) => void): void {
    state.touchRouter.updateTouchArea(group, key, area, action, longPress, drag);
  }

  setDisplayBrightnessFromTouch(
    state: ProjectionDashboardState,
    settingsController: ProjectionDashboardSettingsController,
    pointX: number,
    bounds: ProjectionBounds
  ): void {
    const width = bounds.right - bounds.left;
    if (width <= 0) {
      return;
    }
    const position = Math.max(0, Math.min(1, (pointX - bounds.left) / width));
    settingsController.updateDisplayBrightness(state, 20 + position * 80);
  }

  screenToContentPoint(state: ProjectionDashboardState, x: number, y: number): ProjectionPoint {
    const scale = state.contentScalePercent / 100;
    if (scale <= 0 || state.projectionViewportWidth <= 0 || state.projectionViewportHeight <= 0) {
      return { x, y };
    }
    const centerX = state.projectionViewportWidth / 2;
    const centerY = state.projectionViewportHeight / 2;
    const offsetX = state.projectionViewportWidth * state.contentOffsetXPercent / 100;
    const offsetY = state.projectionViewportHeight * state.contentOffsetYPercent / 100;
    return {
      x: (x - centerX - offsetX) / scale + centerX,
      y: (y - centerY - offsetY) / scale + centerY
    };
  }

  canvasPixelToContentPoint(state: ProjectionDashboardState, x: number, y: number): ProjectionPoint {
    const ui = state.getUIContext();
    const originX = ui.px2vp(state.viewAreaOriginX);
    const originY = ui.px2vp(state.viewAreaOriginY);
    const content = this.screenToContentPoint(state, ui.px2vp(x) - originX, ui.px2vp(y) - originY);
    return { x: content.x + originX, y: content.y + originY };
  }
}
