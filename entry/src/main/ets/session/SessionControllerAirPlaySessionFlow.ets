import { AirPlayPairingClient, AirPlayPairingResult, AirPlayRtspStatusError, supportsAirPlayPairingAndEncryption } from '../airplay/AirPlayPairingClient';
import { AirPlayMediaSessionInfo, AirPlayMediaSessionStatusError } from '../airplay/AirPlayMediaSession';
import { Iap2SenderSession } from './Iap2SenderSession';
import { isAirPlayStartReady } from './airplay/AirPlayEndpointFactory';
import { SessionControllerAirPlayPrerequisiteFlow } from './SessionControllerAirPlayPrerequisiteFlow';

const AIRPLAY_PAIRING_WINDOW_MS: number = 120000;

export abstract class SessionControllerAirPlaySessionFlow extends SessionControllerAirPlayPrerequisiteFlow {
  protected async connectAirPlay(): Promise<void> {
    const service = this.discoveredAirPlay;
    if (this.airPlayIdentityConflict) {
      this.events.onLog('AirPlay mDNS 与 iAP2 endpoint 身份冲突；拒绝连接');
      return;
    }
    if (!this.running || !service || !isAirPlayStartReady(
      this.vehicleWifiConnected,
      this.inviteReceived || this.airPlayInviteWaitElapsed,
      this.hasSelfContainedAirPlayEndpoint(),
      this.mdnsAirPlayService !== undefined,
      this.airPlayEndpointResolveElapsed
    ) || this.airPlayConnectInProgress ||
      this.airPlayConnectAttempted) {
      return;
    }
    const pairingRequired = supportsAirPlayPairingAndEncryption(service.txt['features']) !== false;
    if (pairingRequired && !/^(?:0x)?[0-9a-fA-F]{64}$/.test(service.txt['pk'] ?? '')) {
      this.events.onLog('AirPlay endpoint 未预广播公钥；Pair-Setup 将验证协商出的接收端身份');
    }
    this.clearAirPlayWaitTimers();
    if (this.airPlayPairingDeadline < 0) {
      this.airPlayPairingDeadline = Date.now() + AIRPLAY_PAIRING_WINDOW_MS;
    }
    this.airPlayConnectInProgress = true;
    this.airPlayConnectAttempted = true;
    this.pendingAirPlayDisconnect = '';
    this.clearAirPlayCtrlReannounceTimer();
    const generation = ++this.airPlayGeneration;
    this.scheduleAirPlayControlReannounce(generation);
    const mib3VirtualLink = this.iap2?.isClassicMib3Receiver === true;
    const pairing = new AirPlayPairingClient(
      (message: string): void => this.events.onLog(message),
      (message: string): void => this.handleAirPlayTransportDisconnect(generation, message),
      this.wifiNetworkLease
    );
    const virtualIap2 = mib3VirtualLink ? new Iap2SenderSession(
      (bytes: Uint8Array): Promise<void> => pairing.sendVirtualIap2Message(bytes),
      (message: string): void => this.events.onLog(message),
      (): void => {},
      (): void => {},
      this.deviceAddress,
      this.deviceName,
      this.deviceUuid,
      this.allowMfiIntermediateDownload,
      this.trustedMfiFingerprints,
      this.events.requestMfiTrust,
      this.events.persistMfiFingerprint,
      this.skipMfiChallengeVerification,
      this.context,
      (): void => {},
      true
    ) : undefined;
    this.activePairing = pairing;
    try {
      let result: AirPlayPairingResult;
      if (pairingRequired) {
        this.events.onStatus('车机邀请和 AirPlay 服务已就绪，正在安全配对');
        this.events.onLog(`开始 AirPlay Pair-Setup/Verify：${service.host}:${service.port}`);
        try {
          result = await pairing.pair(this.context, service);
        } catch (error) {
          if (!(error instanceof AirPlayRtspStatusError) ||
            ![404, 405, 455, 501].includes(error.statusCode)) {
            throw error instanceof Error ? error : new Error(String(error));
          }
          await pairing.close();
          result = await pairing.connectUnpaired(service);
          this.events.onLog(
            `AirPlay pairing 接口返回 ${error.statusCode}，按 CardDeck et=NONE 兼容路径重试`
          );
        }
      } else {
        this.events.onStatus('接收端未声明 AirPlay 配对加密，正在建立 et=NONE 会话');
        result = await pairing.connectUnpaired(service);
      }
      if (!this.running || generation !== this.airPlayGeneration) {
        await pairing.close();
        return;
      }
      if (result.encryptedControl) {
        this.events.onLog(`AirPlay 配对验证通过：${result.receiverId} · ${result.model}`);
        this.events.onStatus('AirPlay 配对通过，正在建立 RTSP 会话');
      }
      let media: AirPlayMediaSessionInfo;
      try {
        media = await pairing.startCarPlaySession(this.deviceAddress, mib3VirtualLink, virtualIap2);
      } catch (error) {
        if (pairingRequired || result.encryptedControl || !(error instanceof AirPlayMediaSessionStatusError) ||
          error.stage !== 'initial session SETUP') {
          throw error instanceof Error ? error : new Error(String(error));
        }
        await pairing.close();
        this.events.onLog('et=NONE 初始 SETUP 被拒绝；尝试 Pair-Setup/Pair-Verify 加密升级');
        result = await pairing.pair(this.context, service);
        media = await pairing.startCarPlaySession(this.deviceAddress, mib3VirtualLink, virtualIap2);
      }
      if (!this.running || generation !== this.airPlayGeneration) {
        await pairing.close();
        return;
      }
      this.events.onAirPlayMediaSession(media);
      this.events.onLog(
        `AirPlay RTSP RECORD 已完成：screen=${media.videoDataPort}, audio=${media.audioSession?.dataPort ?? 0}`
      );
      try {
        await this.startProjection(media, pairing, generation);
        if (!this.running || generation !== this.airPlayGeneration) {
          return;
        }
        this.events.onStatus(`CarPlay 实时投屏已启动：${media.displayWidth}x${media.displayHeight}`);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        this.events.onStatus(`AirPlay 控制已连接；投屏不可用：${message}`);
        this.events.onLog(`CarPlay 视频源未能启动：${message}`);
      }
      if (this.pendingAirPlayDisconnect) {
        return;
      }
      await this.startAudio(media, generation);
      this.airPlayPairingDeadline = -1;
      this.clearAirPlayCtrlReannounceTimer();
      this.scheduleAirPlayStableReset(generation);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (!this.running || generation !== this.airPlayGeneration) {
        try {
          await pairing.close();
        } catch (cleanupError) {
          this.events.onLog(`停止期间清理 AirPlay 会话失败：${cleanupError instanceof Error ?
            cleanupError.message : String(cleanupError)}`);
        }
        return;
      }
      this.events.onStatus(`AirPlay 连接失败：${message}`);
      this.events.onLog(`AirPlay 自动连接失败：${message}`);
      try {
        await pairing.close();
      } catch (cleanupError) {
        this.events.onLog(`AirPlay 失败清理异常：${cleanupError instanceof Error ?
          cleanupError.message : String(cleanupError)}`);
      }
      this.activePairing = undefined;
      if (error instanceof AirPlayRtspStatusError &&
        [404, 405, 455, 501].includes(error.statusCode)) {
        this.airPlayPairingDeadline = -1;
        this.events.onStatus('AirPlay 接收端不支持当前配对接口；未降级到明文会话');
        this.events.onLog(`AirPlay Pair-Setup 返回 ${error.statusCode}；保留认证要求，停止自动重试`);
      } else {
        this.scheduleAirPlayReconnect(`连接失败：${message}`, this.airPlayRetryDelayMs(error));
      }
    } finally {
      if (generation === this.airPlayGeneration) {
        this.airPlayConnectInProgress = false;
        const disconnect = this.pendingAirPlayDisconnect;
        this.pendingAirPlayDisconnect = '';
        if (disconnect) {
          this.handleAirPlayTransportDisconnect(generation, disconnect);
        }
      }
    }
  }
}
