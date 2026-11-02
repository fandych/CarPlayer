import emitter from '@ohos.events.emitter';
import { CarPlayTouchContact, parseCarPlayTouchReport } from '../airplay/CarPlayTouchReport';

export const CARPLAY_TOUCH_TAP_EVENT: string = 'carplayer.projection.touch.tap';
export const CARPLAY_TOUCH_REPORT_EVENT: string = 'carplayer.projection.touch.report';
export const CARPLAY_RECEIVER_HOME_EVENT: string = 'carplayer.projection.receiver.home';

export interface CarPlayTouchReport {
  displayId: number;
  contacts: CarPlayTouchContact[];
}

export interface CarPlayTouchTap {
  displayId: number;
  startX: number;
  startY: number;
  endX: number;
  endY: number;
  maxDistance: number;
  durationMs?: number;
}

export class CarPlayTouchInput {
  private readonly onTap: (tap: CarPlayTouchTap) => void;
  private readonly onReport: (report: CarPlayTouchReport) => void;
  private displayId: number = -1;
  private width: number = 0;
  private height: number = 0;
  private activeId: number = -1;
  private startX: number = 0;
  private startY: number = 0;
  private lastX: number = 0;
  private lastY: number = 0;
  private startedAt: number = 0;
  private maxDistance: number = 0;
  private suppressUntilReleased: boolean = false;
  private suppressReportsUntilReleased: boolean = false;

  constructor(onTap: (tap: CarPlayTouchTap) => void = (tap: CarPlayTouchTap): void => {
    emitter.emit<CarPlayTouchTap>(CARPLAY_TOUCH_TAP_EVENT, { data: tap });
  }, onReport: (report: CarPlayTouchReport) => void = (report: CarPlayTouchReport): void => {
    emitter.emit<CarPlayTouchReport>(CARPLAY_TOUCH_REPORT_EVENT, { data: report });
  }) {
    this.onTap = onTap;
    this.onReport = onReport;
  }

  start(displayId: number, width: number, height: number): void {
    this.displayId = displayId;
    this.width = width;
    this.height = height;
    this.activeId = -1;
    this.suppressUntilReleased = false;
    this.suppressReportsUntilReleased = false;
  }

  handleReport(report: Uint8Array): void {
    const contacts = parseCarPlayTouchReport(report);
    if (this.displayId < 0 || !contacts) {
      return;
    }
    const pressed = contacts.filter((contact) => contact.down);
    if (this.suppressReportsUntilReleased) {
      if (pressed.length === 0) {
        this.suppressReportsUntilReleased = false;
        this.suppressUntilReleased = false;
        this.onReport({ displayId: this.displayId, contacts: [] });
      }
      return;
    }
    if (contacts.some((contact: CarPlayTouchContact): boolean =>
      contact.down && (contact.x >= this.width || contact.y >= this.height))) {
      this.onReport({ displayId: this.displayId, contacts: [] });
      this.activeId = -1;
      this.suppressUntilReleased = true;
      this.suppressReportsUntilReleased = true;
      return;
    }
    this.onReport({ displayId: this.displayId, contacts });
    if (pressed.length > 1) {
      this.activeId = -1;
      this.suppressUntilReleased = true;
      return;
    }
    if (this.suppressUntilReleased) {
      if (pressed.length === 0) {
        this.suppressUntilReleased = false;
      }
      return;
    }
    if (pressed.length === 1) {
      const contact = pressed[0];
      if (this.activeId < 0) {
        this.activeId = contact.id;
        this.startX = contact.x;
        this.startY = contact.y;
        this.startedAt = Date.now();
        this.maxDistance = 0;
      } else if (this.activeId !== contact.id) {
        this.activeId = -1;
        this.suppressUntilReleased = true;
        return;
      }
      this.lastX = contact.x;
      this.lastY = contact.y;
      this.maxDistance = Math.max(this.maxDistance, Math.hypot(contact.x - this.startX, contact.y - this.startY));
      return;
    }
    if (this.activeId >= 0) {
      const released = contacts.find((contact: CarPlayTouchContact): boolean => contact.id === this.activeId);
      if (!released) {
        this.activeId = -1;
        return;
      }
      const hasReleasePosition = released.x !== 0 || released.y !== 0;
      const endX = hasReleasePosition ? released.x : this.lastX;
      const endY = hasReleasePosition ? released.y : this.lastY;
      const tap: CarPlayTouchTap = {
        displayId: this.displayId,
        startX: this.startX,
        startY: this.startY,
        endX,
        endY,
        maxDistance: Math.max(this.maxDistance, Math.hypot(endX - this.startX, endY - this.startY)),
        durationMs: Math.max(0, Date.now() - this.startedAt)
      };
      this.activeId = -1;
      if (tap.maxDistance <= this.width * 0.04 && (tap.durationMs ?? 0) <= 10000 &&
        tap.endX < this.width && tap.endY < this.height) {
        this.onTap(tap);
      }
    }
  }

  stop(): void {
    if (this.displayId >= 0) {
      this.onReport({ displayId: this.displayId, contacts: [] });
    }
    this.displayId = -1;
    this.activeId = -1;
    this.suppressUntilReleased = false;
    this.suppressReportsUntilReleased = false;
  }
}