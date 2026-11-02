export class ProjectionShakeDetector {
  private previousX: number = 0;
  private previousY: number = 0;
  private previousZ: number = 0;
  private initialized: boolean = false;
  private lastPulse: number = -1000;
  private pulseCount: number = 0;
  private cooldownUntil: number = 0;

  update(x: number, y: number, z: number, now: number): boolean {
    if (![x, y, z, now].every((value: number): boolean => Number.isFinite(value))) {
      return false;
    }
    const delta = Math.hypot(x - this.previousX, y - this.previousY, z - this.previousZ);
    const wasInitialized = this.initialized;
    this.previousX = x;
    this.previousY = y;
    this.previousZ = z;
    this.initialized = true;
    if (!wasInitialized || now < this.cooldownUntil || delta < 18 || now - this.lastPulse < 100) {
      return false;
    }
    this.pulseCount = now - this.lastPulse <= 600 ? this.pulseCount + 1 : 1;
    this.lastPulse = now;
    if (this.pulseCount < 3) {
      return false;
    }
    this.pulseCount = 0;
    this.cooldownUntil = now + 2500;
    return true;
  }
}