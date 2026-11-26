import bluetoothConnection from '@ohos.bluetooth.connection';
import window from '@ohos.window';
import { isCarPlayAdapterName } from '../transport/BluetoothIap2Server';
import { advanceSessionGeneration, isCurrentSessionGeneration } from './NativeSessionLifecycle';
import { CarPlayBackgroundTask } from './CarPlayBackgroundTask';
import { SessionControllerAirPlayReconnectFlow } from './SessionControllerAirPlayReconnectFlow';

export abstract class SessionControllerBluetoothLifecycle extends SessionControllerAirPlayReconnectFlow {
  protected backgroundTask?: CarPlayBackgroundTask;
  protected bluetoothOutboundTimer: number = -1;
  protected bluetoothOutboundGeneration: number = 0;
  protected bluetoothOutboundDeviceIndex: number = 0;
  protected bluetoothOutboundConnecting: boolean = false;
  private lastBluetoothOutboundLog: string = '';

  async start(): Promise<void> {
    if (this.running) {
      return;
    }
    const generation = advanceSessionGeneration();
    await this.requestPermissions(['ohos.permission.ACCESS_BLUETOOTH']);
    if (!isCurrentSessionGeneration(generation)) {
      this.events.onLog('CarPlayer 已在权限请求期间停止；取消迟到的监听启动');
      return;
    }
    this.running = true;
    this.bluetoothOutboundGeneration++;
    this.bluetoothOutboundDeviceIndex = 0;
    this.bluetoothOutboundConnecting = false;
    this.inviteReceived = false;
    this.wifiJoinInProgress = false;
    this.wifiJoinGeneration++;
    this.airPlayConnectInProgress = false;
    this.airPlayConnectAttempted = false;
    this.airPlayStartSessionReceived = false;
    this.airPlayInviteWaitElapsed = false;
    this.airPlayEndpointResolveElapsed = false;
    this.airPlayPairingDeadline = -1;
    this.vehicleWifiConnected = false;
    this.wifiReconnectAttempts = 0;
    this.clearWifiReconnectTimer();
    this.discoveredAirPlay = undefined;
    this.mdnsAirPlayService = undefined;
    this.iap2AirPlayEndpoint = undefined;
    this.airPlayIdentityConflict = false;
    this.clearAirPlayWaitTimers();
    this.clearPendingStartSessionTimer();
    try {
      const backgroundTask = new CarPlayBackgroundTask(this.context);
      this.backgroundTask = backgroundTask;
      await backgroundTask.start((reason: string): void => {
        if (!this.running) {
          return;
        }
        this.events.onLog(`系统取消了 CarPlay 后台长时任务：reason=${reason}`);
        this.events.onStatus('后台连接任务已被系统取消，正在停止 CarPlay');
        void this.stop().catch((error: Error): void => this.reportError(error));
      });
      if (!this.running || !isCurrentSessionGeneration(generation)) {
        await this.releaseBackgroundTask();
        return;
      }
      if (this.hasValidDeviceAddress()) {
        try {
          await this.startControlAdvertisement();
        } catch (error) {
          this.events.onLog(
            `蓝牙启动前控制广播未能发布；入网后将重试：${error instanceof Error ? error.message : String(error)}`
          );
        }
      } else {
        this.events.onLog('真实蓝牙 MAC 未配置；暂不发布 CarPlay 控制广播');
      }
      this.adapterMode = this.detectAdapterMode();
      this.events.onLog(
        this.adapterMode
          ? '检测到已配对 CarPlay 无线适配器；启用 Wireless iAP SDP 和交接重拨处理'
          : '未检测到已配对 CarPlay 无线适配器；使用标准 iAP2 SDP'
      );
      await this.bluetooth.start(
        () => this.handleBluetoothConnected(),
        (bytes: Uint8Array) => this.handleBluetoothData(bytes),
        (message: string) => this.reportError(message),
        this.adapterMode,
        (): void => this.handleBluetoothDisconnected()
      );
      if (!this.running || !isCurrentSessionGeneration(generation)) {
        this.bluetooth.stop();
        this.events.onLog('RFCOMM 启动完成时会话已停止；已立即关闭监听');
        return;
      }
      await this.setKeepScreenOn(true);
      this.events.onStatus('等待车机 iAP2 握手');
      this.events.onLog('CarPlay 已开启：等待蓝牙 RFCOMM / iAP2 连接');
      this.scheduleBluetoothOutboundAttempt(0);
    } catch (error) {
      if (!isCurrentSessionGeneration(generation)) {
        this.running = false;
        this.bluetooth.stop();
        try {
          await this.releaseBackgroundTask();
        } catch (cleanupError) {
          this.events.onLog(
            `过期启动清理后台长时任务失败：${cleanupError instanceof Error ? cleanupError.message : String(cleanupError)}`
          );
        }
        return;
      }
      this.running = false;
      this.adapterMode = false;
      this.bluetooth.stop();
      const advertiser = this.ctrlAdvertiser;
      this.ctrlAdvertiser = undefined;
      if (advertiser) {
        try {
          await advertiser.stop();
        } catch (cleanupError) {
          this.events.onLog(
            `蓝牙启动失败后的控制广播清理失败：${cleanupError instanceof Error ? cleanupError.message : String(cleanupError)}`
          );
        }
      }
      try {
        await this.releaseBackgroundTask();
      } catch (cleanupError) {
        this.events.onLog(
          `启动失败后的后台长时任务清理失败：${cleanupError instanceof Error ? cleanupError.message : String(cleanupError)}`
        );
      }
      throw error instanceof Error ? error : new Error(String(error));
    }
  }
  protected async releaseBackgroundTask(): Promise<void> {
    const task = this.backgroundTask;
    if (task) {
      await task.stop();
      if (this.backgroundTask === task) {
        this.backgroundTask = undefined;
      }
    }
  }
  protected clearBluetoothOutboundTimer(): void {
    if (this.bluetoothOutboundTimer >= 0) {
      clearTimeout(this.bluetoothOutboundTimer);
      this.bluetoothOutboundTimer = -1;
    }
  }
  private scheduleBluetoothOutboundAttempt(delayMs: number): void {
    if (!this.running || this.bluetooth.isClientConnected || this.bluetoothOutboundConnecting ||
      this.bluetoothOutboundTimer >= 0) {
      return;
    }
    const generation = this.bluetoothOutboundGeneration;
    this.bluetoothOutboundTimer = setTimeout((): void => {
      this.bluetoothOutboundTimer = -1;
      void this.tryBluetoothOutboundConnection(generation);
    }, delayMs);
  }
  private async tryBluetoothOutboundConnection(generation: number): Promise<void> {
    if (!this.running || generation !== this.bluetoothOutboundGeneration ||
      this.bluetooth.isClientConnected || this.bluetoothOutboundConnecting) {
      return;
    }
    let deviceIds: string[];
    try {
      deviceIds = bluetoothConnection.getPairedDevices();
    } catch (error) {
      const signature = `list:${error instanceof Error ? error.message : String(error)}`;
      if (signature !== this.lastBluetoothOutboundLog) {
        this.lastBluetoothOutboundLog = signature;
        this.events.onLog(`无法读取已配对蓝牙设备，暂不主动连接：${signature.slice(5)}`);
      }
      this.scheduleBluetoothOutboundAttempt(5000);
      return;
    }
    const candidates: string[] = [];
    for (const deviceId of deviceIds) {
      try {
        const name = bluetoothConnection.getRemoteDeviceName(deviceId);
        if (!isCarPlayAdapterName(name)) {
          candidates.push(deviceId);
        }
      } catch (_error) {
        candidates.push(deviceId);
      }
    }
    if (candidates.length === 0) {
      const signature = deviceIds.length === 0 ? '没有已配对设备' : '未发现适合主动 iAP2 的已配对设备';
      if (signature !== this.lastBluetoothOutboundLog) {
        this.lastBluetoothOutboundLog = signature;
        this.events.onLog(`主动 RFCOMM 连接待命：${signature}；继续保持 iAP2 监听`);
      }
      this.scheduleBluetoothOutboundAttempt(8000);
      return;
    }
    this.lastBluetoothOutboundLog = '';
    const index = this.bluetoothOutboundDeviceIndex % candidates.length;
    const deviceId = candidates[index];
    this.bluetoothOutboundDeviceIndex++;
    this.bluetoothOutboundConnecting = true;
    this.events.onLog(`尝试主动连接已配对设备 ${deviceId} 的无线 iAP2 RFCOMM 服务`);
    let connected = false;
    try {
      connected = await this.bluetooth.connectToDevice(deviceId,
        (message: string): void => this.events.onLog(`主动 RFCOMM 连接探测未成功：${message}`));
    } catch (error) {
      this.events.onLog(`主动 RFCOMM 连接失败：${error instanceof Error ? error.message : String(error)}`);
    } finally {
      this.bluetoothOutboundConnecting = false;
    }
    if (!this.running || generation !== this.bluetoothOutboundGeneration || connected ||
      this.bluetooth.isClientConnected) {
      return;
    }
    this.scheduleBluetoothOutboundAttempt(3000);
  }
  private handleBluetoothDisconnected(): void {
    const session = this.iap2;
    this.iap2 = undefined;
    session?.cancel();
    this.clearPendingStartSessionTimer();
    if (!this.running) {
      return;
    }
    this.events.onLog('RFCOMM 链路已断开；保留监听并恢复主动 iAP2 连接轮询');
    this.scheduleBluetoothOutboundAttempt(3000);
  }

  protected clearWifiReconnectTimer(): void {
    if (this.wifiReconnectTimer >= 0) {
      clearTimeout(this.wifiReconnectTimer);
      this.wifiReconnectTimer = -1;
    }
  }

  protected reportError(error: Error | string): void {
    const message = error instanceof Error ? error.message : error;
    const stack = error instanceof Error && error.stack && error.stack !== message
      ? `\n${error.stack}`
      : '';
    this.events.onStatus(`错误：${message}`);
    this.events.onLog(`错误：${message}${stack}`);
  }
  protected async setKeepScreenOn(keepScreenOn: boolean): Promise<void> {
    if (!this.keepScreenOn) {
      return;
    }
    try {
      const appWindow = await window.getLastWindow(this.context);
      await appWindow.setWindowKeepScreenOn(keepScreenOn);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.events.onLog(`常亮设置失败：${message}`);
    }
  }
}
