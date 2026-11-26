import { AirPlayPairingClient, AirPlayRtspStatusError } from '../airplay/AirPlayPairingClient';
import { SessionControllerAirPlaySessionFlow } from './SessionControllerAirPlaySessionFlow';

const AIRPLAY_PAIRING_WINDOW_MS: number = 120000;
const AIRPLAY_RECONNECT_DELAY_MS: number = 2000;
const AIRPLAY_FORBIDDEN_RETRY_DELAY_MS: number = 5000;
const AIRPLAY_CTRL_REANNOUNCE_INTERVAL_MS: number = 10000;

export abstract class SessionControllerAirPlayReconnectFlow extends SessionControllerAirPlaySessionFlow {
  protected handleAirPlayTransportDisconnect(generation: number, message: string): void {
    if (!this.running || generation !== this.airPlayGeneration) {
      return;
    }
    if (this.airPlayConnectInProgress) {
      this.pendingAirPlayDisconnect = message;
      void this.playbackAudioCapture?.stop().catch((error: Error): void => {
        this.events.onLog(`断连时取消音频授权失败：${error.message}`);
      });
      return;
    }
    const pairing = this.activePairing;
    if (!pairing) {
      return;
    }
    this.clearAirPlayStableTimer();
    const recoveryGeneration = ++this.airPlayGeneration;
    this.airPlayConnectInProgress = true;
    this.airPlayConnectAttempted = false;
    this.events.onStatus('AirPlay 连接中断，正在清理并准备重连');
    this.events.onLog(`检测到 AirPlay RTSP 断连：${message}`);
    void (async (): Promise<void> => {
      try {
        await pairing.stopMediaSession(true);
      } catch (error) {
        this.events.onLog(`断连后停止 AirPlay 媒体会话失败：${error instanceof Error ? error.message : String(error)}`);
      }
      try {
        await this.stopProjection();
      } catch (error) {
        this.events.onLog(`断连后清理投屏资源失败：${error instanceof Error ? error.message : String(error)}`);
      }
      if (this.activePairing === pairing) {
        this.activePairing = undefined;
      }
      try {
        await pairing.close();
      } catch (error) {
        this.events.onLog(`断连后关闭旧 AirPlay 会话失败：${error instanceof Error ? error.message : String(error)}`);
      }
      if (!this.running || recoveryGeneration !== this.airPlayGeneration) {
        return;
      }
      this.pendingAirPlayDisconnect = '';
      this.airPlayConnectInProgress = false;
      this.scheduleAirPlayReconnect('RTSP 会话意外关闭');
    })();
  }
  protected airPlayRetryDelayMs(error: Error): number {
    return error instanceof AirPlayRtspStatusError && error.statusCode === 403
      ? AIRPLAY_FORBIDDEN_RETRY_DELAY_MS
      : AIRPLAY_RECONNECT_DELAY_MS;
  }
  protected scheduleAirPlayReconnect(reason: string, retryDelayMs: number = AIRPLAY_RECONNECT_DELAY_MS): void {
    if (!this.running || !this.hasAirPlayStartSignal() || !this.discoveredAirPlay ||
      this.airPlayReconnectTimer >= 0) {
      return;
    }
    if (this.airPlayPairingDeadline < 0) {
      this.airPlayPairingDeadline = Date.now() + AIRPLAY_PAIRING_WINDOW_MS;
    }
    const remainingMs = this.airPlayPairingDeadline - Date.now();
    if (remainingMs <= 0) {
      this.events.onStatus('AirPlay 自动重连已暂停，请手动重试');
      this.events.onLog(`AirPlay 配对重试窗口已到 120 秒；最近原因：${reason}`);
      return;
    }
    const attempt = this.airPlayReconnectAttempts + 1;
    const delayMs = Math.min(retryDelayMs, remainingMs);
    this.airPlayReconnectAttempts = attempt;
    this.events.onLog(`AirPlay ${reason}；${delayMs / 1000} 秒后自动重连 (${attempt}，剩余 ${Math.ceil(remainingMs / 1000)} 秒)`);
    this.airPlayReconnectTimer = setTimeout((): void => {
      this.airPlayReconnectTimer = -1;
      if (!this.running || !this.hasAirPlayStartSignal() || !this.discoveredAirPlay ||
        this.airPlayConnectInProgress) {
        return;
      }
      this.airPlayConnectAttempted = false;
      void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
    }, delayMs);
  }
  protected scheduleAirPlayStableReset(generation: number): void {
    this.clearAirPlayStableTimer();
    this.airPlayStableTimer = setTimeout((): void => {
      this.airPlayStableTimer = -1;
      if (this.running && generation === this.airPlayGeneration) {
        this.airPlayReconnectAttempts = 0;
        this.airPlayPairingDeadline = -1;
      }
    }, 60000);
  }
  protected scheduleAirPlayControlReannounce(generation: number): void {
    if (!this.running || !this.vehicleWifiConnected || generation !== this.airPlayGeneration ||
      this.airPlayPairingDeadline <= Date.now() || this.airPlayCtrlReannounceTimer >= 0) {
      return;
    }
    const remainingMs = this.airPlayPairingDeadline - Date.now();
    this.airPlayCtrlReannounceTimer = setTimeout((): void => {
      this.airPlayCtrlReannounceTimer = -1;
      void this.reannounceAirPlayControl(generation);
    }, Math.min(AIRPLAY_CTRL_REANNOUNCE_INTERVAL_MS, remainingMs));
  }
  protected async reannounceAirPlayControl(generation: number): Promise<void> {
    if (!this.running || !this.vehicleWifiConnected || generation !== this.airPlayGeneration ||
      this.airPlayPairingDeadline <= Date.now()) {
      return;
    }
    try {
      if (this.ctrlAdvertiser) {
        await this.ctrlAdvertiser.reannounce();
      } else {
        await this.startControlAdvertisement();
      }
      this.events.onLog('AirPlay 配对重试期间已重新公告 CarPlay ctrl 服务');
    } catch (error) {
      this.events.onLog(`WARN: 配对重试期间重新公告 CarPlay ctrl 服务失败：${error instanceof Error ? error.message : String(error)}`);
    }
    this.scheduleAirPlayControlReannounce(generation);
  }
  protected clearAirPlayCtrlReannounceTimer(): void {
    if (this.airPlayCtrlReannounceTimer >= 0) {
      clearTimeout(this.airPlayCtrlReannounceTimer);
      this.airPlayCtrlReannounceTimer = -1;
    }
  }
  protected clearAirPlayStableTimer(): void {
    if (this.airPlayStableTimer >= 0) {
      clearTimeout(this.airPlayStableTimer);
      this.airPlayStableTimer = -1;
    }
  }
  protected clearAirPlayTimers(): void {
    if (this.airPlayReconnectTimer >= 0) {
      clearTimeout(this.airPlayReconnectTimer);
      this.airPlayReconnectTimer = -1;
    }
    this.clearAirPlayCtrlReannounceTimer();
    this.clearAirPlayStableTimer();
    this.clearAirPlayWaitTimers();
  }
  protected isCurrentAirPlaySession(pairing: AirPlayPairingClient, generation: number): boolean {
    return this.running && generation === this.airPlayGeneration && this.activePairing === pairing;
  }
}
