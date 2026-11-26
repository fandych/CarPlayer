import { SessionControllerWifiFlow } from './SessionControllerWifiFlow';

export abstract class SessionControllerAirPlayControl extends SessionControllerWifiFlow {
  async retryAirPlay(): Promise<void> {
    if (!this.running) {
      throw new Error('CarPlayer 已关闭，不能重试 AirPlay');
    }
    if (this.airPlayConnectInProgress) {
      this.events.onLog('AirPlay 配对或会话建立仍在进行，忽略重复重试');
      return;
    }
    this.clearAirPlayTimers();
    this.pendingAirPlayDisconnect = '';
    this.airPlayReconnectAttempts = 0;
    this.airPlayPairingDeadline = -1;
    const stalePairing = this.activePairing;
    try {
      await this.stopProjection();
    } catch (error) {
      this.events.onLog(`重试前清理本地投屏资源失败：${error instanceof Error ? error.message : String(error)}`);
    }
    this.activePairing = undefined;
    if (stalePairing) {
      try {
        await stalePairing.close();
      } catch (error) {
        this.events.onLog(`重试前关闭旧 AirPlay 会话失败：${error instanceof Error ? error.message : String(error)}`);
      }
    }
    this.airPlayConnectAttempted = false;
    if (!this.vehicleWifiConnected || !this.discoveredAirPlay) {
      this.events.onLog(
        `AirPlay 重试暂不可执行：车机 Wi-Fi${this.vehicleWifiConnected ? '已连接' : '未连接'}，` +
          `mDNS 服务${this.discoveredAirPlay ? '已发现' : '未发现'}`
      );
      return;
    }
    this.airPlayEndpointResolveElapsed = true;
    this.events.onStatus('正在重试 AirPlay 配对和 RTSP 会话');
    await this.connectAirPlay();
  }
}
