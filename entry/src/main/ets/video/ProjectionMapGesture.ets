import { CarPlayTouchContact } from '../airplay/CarPlayTouchReport';

export interface ProjectionMapBounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface ProjectionMapMovement {
  scrollX: number;
  scrollY: number;
  zoom: number;
  focusX: number;
  focusY: number;
}

export class ProjectionMapGesture {
  private previous: CarPlayTouchContact[] = [];
  private blocked: boolean = false;
  private dragging: boolean = false;

  reset(): void {
    this.previous = [];
    this.blocked = false;
    this.dragging = false;
  }

  update(contacts: CarPlayTouchContact[], bounds: ProjectionMapBounds,
    dragSlop: number = 8): ProjectionMapMovement | undefined {
    const pressed = contacts.filter((contact: CarPlayTouchContact): boolean => contact.down);
    if (pressed.length === 0) {
      this.reset();
      return undefined;
    }
    if (this.blocked) {
      return undefined;
    }
    for (const contact of pressed) {
      if (!this.previous.some((previous: CarPlayTouchContact): boolean => previous.id === contact.id) &&
        (contact.x < bounds.left || contact.x >= bounds.right ||
          contact.y < bounds.top || contact.y >= bounds.bottom)) {
        this.previous = [];
        this.blocked = true;
        return undefined;
      }
    }
    const previous = this.previous;
    if (previous.length !== pressed.length ||
      pressed.some((contact: CarPlayTouchContact, index: number): boolean => contact.id !== previous[index].id)) {
      this.previous = pressed;
      this.dragging = false;
      return undefined;
    }
    if (pressed.length === 1 && !this.dragging) {
      if (Math.hypot(pressed[0].x - previous[0].x, pressed[0].y - previous[0].y) <= dragSlop) {
        return undefined;
      }
      this.dragging = true;
    }
    this.previous = pressed;
    const oldX = previous.reduce((sum: number, contact: CarPlayTouchContact): number => sum + contact.x, 0) /
      previous.length;
    const oldY = previous.reduce((sum: number, contact: CarPlayTouchContact): number => sum + contact.y, 0) /
      previous.length;
    const newX = pressed.reduce((sum: number, contact: CarPlayTouchContact): number => sum + contact.x, 0) /
      pressed.length;
    const newY = pressed.reduce((sum: number, contact: CarPlayTouchContact): number => sum + contact.y, 0) /
      pressed.length;
    let zoom = 0;
    if (pressed.length === 2) {
      const oldDistance = Math.hypot(previous[0].x - previous[1].x, previous[0].y - previous[1].y);
      const newDistance = Math.hypot(pressed[0].x - pressed[1].x, pressed[0].y - pressed[1].y);
      if (oldDistance >= 10 && newDistance >= 10) {
        zoom = Math.max(-1, Math.min(1, Math.log2(newDistance / oldDistance)));
      }
    }
    return {
      scrollX: oldX - newX,
      scrollY: oldY - newY,
      zoom,
      focusX: newX - bounds.left,
      focusY: newY - bounds.top
    };
  }
}