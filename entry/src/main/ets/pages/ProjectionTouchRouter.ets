import { CarPlayTouchReport, CarPlayTouchTap } from '../video/CarPlayTouchInput';

export interface ProjectionBounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface ProjectionPoint {
  x: number;
  y: number;
}

interface ProjectionTouchScrollState {
  displayId: number;
  contactId: number;
  startX: number;
  startY: number;
  lastX: number;
  lastY: number;
  scroller?: Scroller;
  drag?: (pointX: number) => void;
}

export interface ProjectionTouchArea extends ProjectionBounds {
  group: string;
  action: () => void;
  longPress?: () => void;
  drag?: (pointX: number) => void;
}

export class ProjectionTouchRouter {
  touchAreas: Map<string, ProjectionTouchArea> = new Map();
  touchBounds: Map<string, ProjectionBounds> = new Map();
  private touchScrollState?: ProjectionTouchScrollState;

  updateTouchArea(
    group: string,
    key: string,
    area: Area,
    action: () => void,
    longPress?: () => void,
    drag?: (pointX: number) => void
  ): void {
    const left = Number.parseFloat(`${area.globalPosition.x}`);
    const top = Number.parseFloat(`${area.globalPosition.y}`);
    this.touchAreas.set(`${group}:${key}`, {
      group,
      action,
      longPress,
      drag,
      left,
      top,
      right: left + Number.parseFloat(`${area.width}`),
      bottom: top + Number.parseFloat(`${area.height}`)
    });
  }

  clear(): void {
    this.touchAreas.clear();
    this.touchBounds.clear();
    this.touchScrollState = undefined;
  }

  resetScrollState(): void {
    this.touchScrollState = undefined;
  }

  contains(bounds: ProjectionBounds, x: number, y: number): boolean {
    return x >= bounds.left && x < bounds.right && y >= bounds.top && y < bounds.bottom;
  }

  handleTap(
    tap: CarPlayTouchTap | undefined,
    projectionActive: boolean,
    projectionDisplayId: number,
    dashboardView: string,
    activeAppLabel: string,
    navigationPreview: boolean,
    canvasPixelToContentPoint: (x: number, y: number) => ProjectionPoint
  ): void {
    if (!tap || !projectionActive || projectionDisplayId !== tap.displayId) {
      return;
    }
    const start = canvasPixelToContentPoint(tap.startX, tap.startY);
    const end = canvasPixelToContentPoint(tap.endX, tap.endY);
    if (Math.hypot(end.x - start.x, end.y - start.y) > 20) {
      return;
    }
    const pointX = (start.x + end.x) / 2;
    const pointY = (start.y + end.y) / 2;
    const dock = this.touchBounds.get('dock');
    if (dock && (this.contains(dock, start.x, start.y) || this.contains(dock, end.x, end.y))) {
      if (this.contains(dock, pointX, pointY)) {
        for (const area of this.touchAreas.values()) {
          if (area.group === 'dock' && this.contains(area, pointX, pointY)) {
            if ((tap.durationMs ?? 0) >= 550) {
              area.longPress?.();
            } else if (area.drag) {
              area.drag(pointX);
            } else {
              area.action();
            }
            return;
          }
        }
      }
      return;
    }
    for (const area of this.touchAreas.values()) {
      if (area.group === 'dock' ||
        ((area.group === 'media' || area.group === 'map') &&
          (dashboardView !== 'home' || (activeAppLabel.length > 0 && !navigationPreview))) ||
        (area.group === 'grid' && dashboardView !== 'apps') ||
        (area.group === 'preview' && (dashboardView !== 'home' || !navigationPreview)) ||
        (area.group === 'maps' && dashboardView !== 'maps') ||
        (area.group === 'music' && dashboardView !== 'music') ||
        (area.group === 'settings' && dashboardView !== 'settings') ||
        (area.group === 'themes' && dashboardView !== 'themes')) {
        continue;
      }
      const bounds = this.touchBounds.get(area.group);
      if (bounds && this.contains(area, pointX, pointY) && this.contains(bounds, pointX, pointY)) {
        if (area.drag) {
          area.drag(pointX);
        } else {
          area.action();
        }
        return;
      }
    }
  }

  handleReport(
    report: CarPlayTouchReport | undefined,
    projectionActive: boolean,
    projectionDisplayId: number,
    dashboardView: string,
    canvasPixelToContentPoint: (x: number, y: number) => ProjectionPoint,
    scrollControllerAt: (x: number, y: number) => Scroller | undefined
  ): void {
    if (!report || !projectionActive || projectionDisplayId !== report.displayId) {
      this.resetScrollState();
      return;
    }
    const pressed = report.contacts.filter((contact): boolean => contact.down);
    if (pressed.length !== 1) {
      this.resetScrollState();
      return;
    }
    const contact = pressed[0];
    const point = canvasPixelToContentPoint(contact.x, contact.y);
    const previous = this.touchScrollState;
    if (!previous || previous.displayId !== report.displayId || previous.contactId !== contact.id) {
      const bounds = this.touchBounds.get('settings');
      const dragArea = dashboardView === 'settings'
        ? Array.from(this.touchAreas.values()).find((area: ProjectionTouchArea): boolean =>
          area.group === 'settings' && area.drag !== undefined &&
          this.contains(area, point.x, point.y) && (!bounds || this.contains(bounds, point.x, point.y)))
        : undefined;
      this.touchScrollState = {
        displayId: report.displayId,
        contactId: contact.id,
        startX: point.x,
        startY: point.y,
        lastX: point.x,
        lastY: point.y,
        scroller: dragArea ? undefined : scrollControllerAt(point.x, point.y),
        drag: dragArea?.drag
      };
      dragArea?.drag?.(point.x);
      return;
    }
    const deltaX = previous.lastX - point.x;
    const deltaY = previous.lastY - point.y;
    previous.lastX = point.x;
    previous.lastY = point.y;
    if (previous.drag) {
      previous.drag(point.x);
      return;
    }
    if (Math.hypot(point.x - previous.startX, point.y - previous.startY) >= 8) {
      previous.scroller?.scrollBy(deltaX, deltaY);
    }
  }

}
