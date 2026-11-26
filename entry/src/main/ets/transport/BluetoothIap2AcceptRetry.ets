export class BluetoothIap2AcceptRetry {
  private delayMs: number = 500;
  private timer: number = -1;
  private lastFailure: string = '';
  private readonly setTimer: (handler: () => void, delayMs: number) => number;
  private readonly clearTimer: (timerId: number) => void;

  constructor(
    setTimer: (handler: () => void, delayMs: number) => number = setTimeout,
    clearTimer: (timerId: number) => void = clearTimeout
  ) {
    this.setTimer = setTimer;
    this.clearTimer = clearTimer;
  }

  schedule(isListening: () => boolean, acceptNext: () => void): void {
    if (!isListening() || this.timer >= 0) {
      return;
    }
    const delay = this.delayMs;
    this.delayMs = Math.min(delay * 2, 5000);
    this.timer = this.setTimer((): void => {
      this.timer = -1;
      if (isListening()) {
        acceptNext();
      }
    }, delay);
  }

  markAccepted(): void {
    this.delayMs = 500;
    this.lastFailure = '';
  }

  report(message: string, onFailure?: (message: string) => void): void {
    if (message === this.lastFailure) {
      return;
    }
    this.lastFailure = message;
    onFailure?.(message);
  }

  cancel(): void {
    if (this.timer >= 0) {
      this.clearTimer(this.timer);
      this.timer = -1;
    }
    this.delayMs = 500;
    this.lastFailure = '';
  }
}
