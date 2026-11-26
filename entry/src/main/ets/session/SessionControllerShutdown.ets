import { advanceSessionGeneration } from './NativeSessionLifecycle';
import { SessionControllerBluetoothLifecycle } from './SessionControllerBluetoothLifecycle';

export abstract class SessionControllerShutdown extends SessionControllerBluetoothLifecycle {
  async stop(): Promise<void> {
    advanceSessionGeneration();
    this.running = false;
    this.bluetoothOutboundGeneration++;
    this.clearBluetoothOutboundTimer();
    this.bluetoothOutboundConnecting = false;
    this.airPlayGeneration++;
    this.wifiJoinGeneration++;
    this.clearAirPlayTimers();
    this.clearWifiReconnectTimer();
    this.pendingAirPlayDisconnect = '';
    this.airPlayConnectAttempted = false;
    this.airPlayPairingDeadline = -1;
    this.wifiJoinInProgress = false;
    this.vehicleWifiConnected = false;
    this.clearPendingStartSessionTimer();
    const failures: string[] = [];
    try {
      await this.wifi.cancelPendingJoin();
    } catch (error) {
      failures.push(`取消 Wi-Fi 加入失败：${error instanceof Error ? error.message : String(error)}`);
    }
    try {
      await this.stopProjection();
    } catch (error) {
      failures.push(`投屏资源清理失败：${error instanceof Error ? error.message : String(error)}`);
    }
    try {
      this.discovery?.stop();
    } catch (error) {
      failures.push(`mDNS 停止失败：${error instanceof Error ? error.message : String(error)}`);
    }
    this.discovery = undefined;
    try {
      await this.stopAirPlayRawMonitor();
    } catch (error) {
      failures.push(`mDNS RAW 监听停止失败：${error instanceof Error ? error.message : String(error)}`);
    }
    if (this.ctrlAdvertiser) {
      try {
        await this.ctrlAdvertiser.stop();
      } catch (error) {
        failures.push(`控制广播停止失败：${error instanceof Error ? error.message : String(error)}`);
      }
      this.ctrlAdvertiser = undefined;
    }
    this.iap2?.cancel();
    const pairing = this.activePairing;
    this.activePairing = undefined;
    if (pairing) {
      try {
        await pairing.close();
      } catch (error) {
        failures.push(`AirPlay 会话清理失败：${error instanceof Error ? error.message : String(error)}`);
      }
    }
    try {
      await this.wifiNetworkLease.release();
    } catch (error) {
      failures.push(`指定 Wi-Fi 网络监听清理失败：${error instanceof Error ? error.message : String(error)}`);
    }
    try {
      this.bluetooth.stop();
    } catch (error) {
      failures.push(`蓝牙监听停止失败：${error instanceof Error ? error.message : String(error)}`);
    }
    this.iap2 = undefined;
    this.adapterMode = false;
    this.credentials = undefined;
    this.discoveredAirPlay = undefined;
    this.mdnsAirPlayService = undefined;
    this.iap2AirPlayEndpoint = undefined;
    this.airPlayIdentityConflict = false;
    this.inviteReceived = false;
    this.airPlayStartSessionReceived = false;
    this.airPlayInviteWaitElapsed = false;
    this.airPlayEndpointResolveElapsed = false;
    try {
      await this.setKeepScreenOn(false);
    } catch (error) {
      failures.push(`恢复屏幕常亮设置失败：${error instanceof Error ? error.message : String(error)}`);
    }
    try {
      await this.releaseBackgroundTask();
    } catch (error) {
      failures.push(`后台长时任务清理失败：${error instanceof Error ? error.message : String(error)}`);
    }
    this.events.onStatus(failures.length > 0 ? '已停止，但部分资源清理失败' : '已停止');
    this.events.onLog(failures.length > 0 ? `会话停止时出现错误：${failures.join('；')}` : '会话已停止');
    if (failures.length > 0) {
      throw new Error(failures.join('；'));
    }
  }
  async disconnectAirPlay(): Promise<void> {
    this.airPlayGeneration++;
    this.clearAirPlayTimers();
    this.pendingAirPlayDisconnect = '';
    this.airPlayConnectAttempted = false;
    this.airPlayConnectInProgress = false;
    this.inviteReceived = false;
    this.airPlayStartSessionReceived = false;
    this.airPlayInviteWaitElapsed = false;
    this.airPlayEndpointResolveElapsed = false;
    this.airPlayPairingDeadline = -1;
    this.clearAirPlayWaitTimers();
    const pairing = this.activePairing;
    this.activePairing = undefined;
    const failures: string[] = [];
    try {
      await this.stopProjection();
    } catch (error) {
      failures.push(`投屏资源清理失败：${error instanceof Error ? error.message : String(error)}`);
    }
    if (pairing) {
      try {
        await pairing.close();
      } catch (error) {
        failures.push(`AirPlay 会话断开失败：${error instanceof Error ? error.message : String(error)}`);
      }
    }
    const result = failures.length > 0
      ? `AirPlay 已断开，但清理不完整：${failures.join('；')}`
      : 'AirPlay 已断开，iAP2 监听继续运行';
    this.events.onStatus(result);
    this.events.onLog(result);
    if (failures.length > 0) {
      throw new Error(failures.join('；'));
    }
  }
}
