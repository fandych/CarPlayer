import { IndexHost } from './IndexHost';
import { AirPlayMediaSessionInfo } from '../airplay/AirPlayMediaSession';
import { MfiTrustPromptInfo } from '../iap2/MfiVerifier';
import { AirPlayService } from '../network/AirPlayMdnsDiscovery';
import { SessionController, SessionEvents } from '../session/SessionController';
import { WifiCredentials } from '../session/Iap2SenderSession';

export function syncConnectionDuration(host: IndexHost): void {
    if (host.status === 'connected') {
      if (host.connectionTimer >= 0) {
        return;
      }
      host.connectionStartedAt = Date.now();
      host.connectionDuration = '00:00';
      host.connectionTimer = setInterval((): void => {
        const elapsed = Math.max(0, Math.floor((Date.now() - host.connectionStartedAt) / 1000));
        const minutes = `${Math.floor(elapsed / 60)}`.padStart(2, '0');
        const seconds = `${elapsed % 60}`.padStart(2, '0');
        host.connectionDuration = `${minutes}:${seconds}`;
      }, 1000);
      return;
    }
    if (host.connectionTimer >= 0) {
      clearInterval(host.connectionTimer);
      host.connectionTimer = -1;
    }
    host.connectionStartedAt = 0;
    host.connectionDuration = '00:00';
}

export async function startSession(host: IndexHost): Promise<void> {
    if (host.isStarting || host.isSessionActive) {
      host.logProtocol('session', '忽略重复启动请求', 'WARN');
      return;
    }
    const address = host.bluetoothAddress.trim().toUpperCase();
    host.logSessionId = host.createLogSessionId();
    host.connectionAttempt = 0;
    host.lastConnectionSummary = '';
    host.protocolLogger?.setContext({ sessionId: host.logSessionId, attempt: host.connectionAttempt });
    host.isStarting = true;
    host.isSessionActive = true;
    host.status = 'connecting';
    host.syncConnectionDuration();
    host.statusMessage = '正在请求蓝牙权限并启动 RFCOMM 监听';
    host.logProtocol(
      'bluetooth',
      `启动 RFCOMM/iAP2 监听，发送端 MAC ${address.length > 0 ? '已配置' : '未配置（可稍后补充）'}`
    );
    host.logProtocol('session', '日志会话开始，等待车机连接');
    try {
      await host.ensureController().start();
    } catch (error) {
      host.isSessionActive = false;
      host.status = 'closed';
      host.syncConnectionDuration();
      host.showError(error);
    } finally {
      host.isStarting = false;
    }
}

export function ensureController(host: IndexHost): SessionController {
    if (host.controller) {
      return host.controller;
    }
    const events: SessionEvents = {
      onStatus: (status: string): void => host.applyProtocolStatus(status),
      onLog: (message: string): void => host.logProtocol(host.protocolStage(message), message),
      onWifiCredentials: (credentials: WifiCredentials): void => {
        host.logProtocol(
          'wifi',
          `收到车机热点配置：SSID=${credentials.ssid}，安全类型=${credentials.securityType}，密码已隐藏`
        );
        void host.joinVehicleWifi();
      },
      onAirPlayService: (service: AirPlayService): void => {
        host.logProtocol('mdns', `解析 AirPlay 服务：${service.name} ${service.host}:${service.port}`);
      },
      onAirPlayMediaSession: (info: AirPlayMediaSessionInfo): void => {
        host.applyProtocolStatus('AirPlay RTSP RECORD 已完成');
        host.logProtocol(
          'airplay',
          `RTSP RECORD 完成：videoPort=${info.videoDataPort}, audioPort=${info.audioSession?.dataPort ?? 0}`
        );
      },
      onProjectionReady: async (displayId: number, width: number, height: number): Promise<void> => {
        host.projectionDisplayId = displayId;
        host.logProtocol('projection', `虚拟屏已建立：id=${displayId}, size=${width}x${height}`);
        try {
          host.logProtocol(
            'projection',
            `请求启动投影页：bundle=com.fandy.carplayer, ability=ProjectionHomeAbility, displayId=${displayId}`
          );
          await host.startProjectionAbility(displayId);
          host.logProtocol('projection', `startAbility 返回成功：ProjectionHomeAbility, displayId=${displayId}`);
        } catch (error) {
          const message = host.errorMessage(error);
          host.logProtocol('projection', `投影首页启动失败：${message}`, 'ERROR');
          throw new Error(`CarPlay 虚拟屏已创建，但投影首页启动失败：${message}`);
        }
      },
      onProjectionStopping: (): Promise<void> => host.pauseActiveMediaOnProjectionStop(),
      onProjectionStopped: (): void => {
        host.projectionDisplayId = -1;
        AppStorage.setOrCreate('carplayProjectionActiveModeId', '');
      },
      requestMfiTrust: (info: MfiTrustPromptInfo): Promise<boolean> => host.confirmMfiTrust(info),
      persistMfiFingerprint: (fingerprint: string): Promise<void> => host.persistMfiFingerprint(fingerprint)
    };
    host.controller = new SessionController(
      host.getAppContext(),
      events,
      host.bluetoothAddress.trim().toUpperCase(),
      host.deviceName.trim() || 'Harmony CarPlayer',
      host.deviceUuid,
      false,
      false,
      host.trustedMfiFingerprints,
      host.skipMfiChallengeVerification
    );
    return host.controller;
}

export async function disconnectAirPlay(host: IndexHost): Promise<void> {
    try {
      await host.controller?.disconnectAirPlay();
      host.status = host.isSessionActive ? 'waiting' : 'closed';
      host.syncConnectionDuration();
      host.logProtocol('airplay', '用户请求断开 AirPlay；iAP2 监听保持活动');
    } catch (error) {
      host.showError(error);
    }
}

export async function retryAirPlay(host: IndexHost): Promise<void> {
    try {
      host.status = 'connecting';
      host.syncConnectionDuration();
      host.statusMessage = '正在重试 AirPlay';
      await host.controller?.retryAirPlay();
    } catch (error) {
      host.showError(error);
    }
}

export async function joinVehicleWifi(host: IndexHost): Promise<void> {
    if (host.wifiJoinInProgress) {
      return;
    }
    host.wifiJoinInProgress = true;
    host.status = 'connecting';
    host.syncConnectionDuration();
    host.statusMessage = '正在自动连接车机 Wi-Fi';
    try {
      await host.controller?.joinVehicleWifi();
    } catch (error) {
      host.showError(error);
    } finally {
      host.wifiJoinInProgress = false;
    }
}

export async function stopSession(host: IndexHost): Promise<void> {
    if (host.isStopping) {
      return;
    }
    host.isStopping = true;
    host.isSessionActive = false;
    host.logProtocol('session', '用户请求停止 CarPlayer，会清理全部连接资源', 'WARN');
    try {
      await host.controller?.stop();
      host.status = 'closed';
      host.syncConnectionDuration();
      host.statusMessage = '监听已关闭';
    } catch (error) {
      host.showError(error);
    } finally {
      host.controller = undefined;
      host.wifiJoinInProgress = false;
      host.projectionDisplayId = -1;
      host.isStopping = false;
    }
}
