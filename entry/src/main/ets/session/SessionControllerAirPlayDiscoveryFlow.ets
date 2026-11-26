import { AirPlayMdnsDiscovery, AirPlayService } from '../network/AirPlayMdnsDiscovery';
import { AirPlayMdnsRawMonitor } from '../network/AirPlayMdnsRawMonitor';
import { correlateAirPlayIdentity } from '../network/AirPlayIdentityCorrelation';
import { CarPlayCtrlAdvertiser } from '../network/CarPlayCtrlAdvertiser';
import { makeAirPlayServiceFromEndpoint, normalizeDeviceIdentifier } from './airplay/AirPlayEndpointFactory';
import { WirelessAirPlayEndpoint } from './Iap2SenderSession';
import { SessionControllerIap2Flow } from './SessionControllerIap2Flow';

export abstract class SessionControllerAirPlayDiscoveryFlow extends SessionControllerIap2Flow {
  protected abstract clearAirPlayInviteWaitTimer(): void;

  protected startAirPlayDiscovery(): void {
    if (this.discovery) {
      this.discovery.stop();
    }
    this.discovery = new AirPlayMdnsDiscovery(
      this.context,
      (service: AirPlayService): void => {
        this.handleDiscoveredAirPlayService(service);
      },
      (message: string): void => this.events.onLog(message)
    );
    this.discovery.start();
    if (!this.mdnsRawMonitor) {
      const rawMonitor = new AirPlayMdnsRawMonitor(
        this.wifiNetworkLease,
        (message: string): void => this.events.onLog(message)
      );
      this.mdnsRawMonitor = rawMonitor;
      void rawMonitor.start().catch((error: Error): void => {
        if (this.mdnsRawMonitor === rawMonitor) {
          this.mdnsRawMonitor = undefined;
        }
        this.events.onLog(`WARN: ${error.message}`);
      });
    }
    this.events.onLog('正在发现 _airplay._tcp 服务');
  }
  protected handleDiscoveredAirPlayService(service: AirPlayService): void {
    if (!this.wifiNetworkLease.isAirPlayAddressOnSelectedNetwork(service.host)) {
      this.events.onLog(`忽略不属于车机 WLAN 网段的 AirPlay mDNS 地址：${service.host}`);
      return;
    }
    this.mdnsAirPlayService = service;
    this.refreshDiscoveredAirPlay();
    this.events.onAirPlayService(service);
    this.events.onLog(`发现 AirPlay ${service.name} · ${service.host}:${service.port}`);
    if (this.inviteReceived || this.airPlayInviteWaitElapsed || this.hasSelfContainedAirPlayEndpoint()) {
      this.clearAirPlayWaitTimers();
    }
    void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
  }
  protected async stopAirPlayRawMonitor(): Promise<void> {
    const monitor = this.mdnsRawMonitor;
    this.mdnsRawMonitor = undefined;
    if (monitor) {
      await monitor.stop();
    }
  }
  protected handleIap2AirPlayEndpoint(endpoint: WirelessAirPlayEndpoint | undefined): void {
    if (!this.running || this.airPlayIdentityConflict) {
      return;
    }
    this.airPlayStartSessionReceived = true;
    this.clearPendingStartSessionTimer();
    if (endpoint) {
      this.iap2AirPlayEndpoint = endpoint;
      this.events.onLog(
        `已从 iAP2 0x4301 获得 AirPlay 地址候选：${endpoint.addresses.length} 个地址，port=${endpoint.port}`
      );
      if (!endpoint.publicKey) {
        this.events.onLog('0x4301 未携带可识别的公钥；仅保留地址候选，身份仍须通过配对验证');
      }
    } else {
      this.events.onLog('已收到 0x4301 启动请求，等待 mDNS 提供 AirPlay endpoint');
    }
    this.refreshDiscoveredAirPlay();
    if (this.discoveredAirPlay) {
      this.events.onAirPlayService(this.discoveredAirPlay);
    }
    this.startAirPlayPrerequisiteWait();
    void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
  }
  protected refreshDiscoveredAirPlay(): void {
    if (this.airPlayIdentityConflict) {
      this.discoveredAirPlay = undefined;
      return;
    }
    const endpoint = this.iap2AirPlayEndpoint;
    const mdnsService = this.mdnsAirPlayService;
    if (!endpoint) {
      this.discoveredAirPlay = mdnsService ?? this.makeAirPlayGatewayFallback();
      return;
    }

    const endpointService = endpoint.port > 0 &&
      endpoint.addresses.some((address: string): boolean => address.trim().length > 0)
      ? makeAirPlayServiceFromEndpoint(endpoint)
      : undefined;
    if (!mdnsService) {
      this.discoveredAirPlay = endpointService ?? this.makeAirPlayGatewayFallback(endpoint);
      return;
    }

    const identityRelation = correlateAirPlayIdentity(
      mdnsService.txt['deviceid'] ?? '',
      mdnsService.txt['pk'] ?? '',
      endpoint.deviceIdentifier,
      endpoint.publicKey
    );
    if (identityRelation === 'conflict') {
      this.rejectAirPlayIdentityConflict(
        '同一 AirPlay deviceIdentifier 的 mDNS pk 与 iAP2 0x4301 publicKey 不一致'
      );
      return;
    }
    if (identityRelation === 'different-device') {
      this.events.onLog('忽略与当前 0x4301 endpoint 身份不匹配的 mDNS AirPlay 服务');
      this.discoveredAirPlay = endpointService;
      return;
    }
    if (identityRelation === 'unlinked') {
      this.events.onLog('mDNS AirPlay 服务无法与 iAP2 endpoint 建立身份关联；使用 0x4301 地址');
      this.discoveredAirPlay = endpointService;
      return;
    }
    if (!endpoint.publicKey && !/^(?:0x)?[0-9a-fA-F]{64}$/.test(mdnsService.txt['pk'] ?? '')) {
      this.events.onLog('AirPlay endpoint 未预广播公钥；将通过 Pair-Setup 建立并验证接收端身份');
    }
    if (identityRelation === 'public-key-match' &&
      normalizeDeviceIdentifier(mdnsService.txt['deviceid'] ?? '') !==
        normalizeDeviceIdentifier(endpoint.deviceIdentifier)) {
      this.events.onLog(
        'mDNS deviceid 与 iAP2 deviceIdentifier 不同，但 publicKey 一致；按公钥确认 AirPlay 接收端'
      );
    }

    const addresses = mdnsService.port === endpoint.port
      ? [mdnsService.host].concat(endpoint.addresses)
      : [mdnsService.host];
    const uniqueAddresses: string[] = [];
    for (const address of addresses) {
      if (uniqueAddresses.indexOf(address) < 0) {
        uniqueAddresses.push(address);
      }
    }
    const txt: Record<string, string> = {};
    for (const key of Object.keys(mdnsService.txt)) {
      const value = mdnsService.txt[key];
      if (value !== undefined) {
        txt[key] = value;
      }
    }
    if (!txt['deviceid']) {
      txt['deviceid'] = endpoint.deviceIdentifier;
    }
    if (!txt['pk'] && endpoint.publicKey) {
      txt['pk'] = endpoint.publicKey;
    }
    this.discoveredAirPlay = {
      name: mdnsService.name,
      host: mdnsService.host,
      addresses: uniqueAddresses,
      port: mdnsService.port,
      txt
    };
  }
  protected makeAirPlayGatewayFallback(endpoint?: WirelessAirPlayEndpoint): AirPlayService | undefined {
    const gateway = this.wifiNetworkLease.defaultGatewayAddress;
    if (!gateway) {
      return undefined;
    }
    const port = endpoint?.port || 7000;
    if (port < 1 || port > 65535) {
      return undefined;
    }
    const txt: Record<string, string> = {};
    if (endpoint?.deviceIdentifier) {
      txt['deviceid'] = endpoint.deviceIdentifier;
    }
    if (endpoint?.publicKey && /^(?:0x)?[0-9a-fA-F]{64}$/.test(endpoint.publicKey)) {
      txt['pk'] = endpoint.publicKey;
    }
    const signature = `${gateway}:${port}:${txt['deviceid'] ?? ''}:${txt['pk'] ?? ''}`;
    if (signature !== this.lastGatewayFallbackSignature) {
      this.lastGatewayFallbackSignature = signature;
      this.events.onLog(
        `mDNS AirPlay 服务尚未出现；尝试已选车机 WLAN gateway ${gateway}:${port}，` +
          `receiver 公钥${txt['pk'] ? '已知' : '未知，不伪造'}`
      );
    }
    return { name: 'CarPlay gateway fallback', host: gateway, addresses: [gateway], port, txt };
  }
  protected rejectAirPlayIdentityConflict(reason: string): void {
    this.airPlayIdentityConflict = true;
    this.discoveredAirPlay = undefined;
    this.inviteReceived = false;
    this.airPlayStartSessionReceived = false;
    this.airPlayInviteWaitElapsed = false;
    this.airPlayEndpointResolveElapsed = false;
    this.airPlayPairingDeadline = -1;
    this.airPlayConnectAttempted = true;
    this.airPlayConnectInProgress = false;
    this.airPlayGeneration++;
    this.clearAirPlayTimers();
    const pairing = this.activePairing;
    this.activePairing = undefined;
    void this.stopProjection().catch((error: Error): void => {
      this.events.onLog(`身份冲突后清理 AirPlay 媒体资源失败：${error.message}`);
    });
    if (pairing) {
      void pairing.close().catch((error: Error): void => {
        this.events.onLog(`身份冲突后关闭 AirPlay 会话失败：${error.message}`);
      });
    }
    this.events.onStatus('AirPlay 身份信息冲突，已拒绝配对');
    this.events.onLog(`ERROR: ${reason}；已拒绝继续 Pair-Setup/Pair-Verify`);
  }
  protected async startControlAdvertisement(reannounce: boolean = false): Promise<void> {
    if (!this.hasValidDeviceAddress()) {
      this.events.onLog('真实蓝牙 MAC 未配置；跳过 CarPlay 控制广播');
      return;
    }
    const advertiser = this.ctrlAdvertiser ?? new CarPlayCtrlAdvertiser(
      this.context,
      this.deviceAddress,
      (): void => {
        if (!this.running || this.ctrlAdvertiser !== advertiser) {
          return;
        }
        this.inviteReceived = true;
        this.clearAirPlayInviteWaitTimer();
        this.events.onStatus('收到车机邀请，等待 AirPlay 接收端');
        this.startAirPlayEndpointResolutionWait();
        if (this.discoveredAirPlay) {
          void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
        }
      },
      (message: string): void => this.events.onLog(message)
    );
    this.ctrlAdvertiser = advertiser;
    try {
      if (reannounce) {
        await advertiser.reannounce();
      } else {
        await advertiser.start();
      }
    } catch (error) {
      if (this.ctrlAdvertiser === advertiser) {
        this.ctrlAdvertiser = undefined;
      }
      throw error instanceof Error ? error : new Error(String(error));
    }
    if (!this.running || this.ctrlAdvertiser !== advertiser) {
      await advertiser.stop();
      return;
    }
    this.startAirPlayPrerequisiteWait();
    if (this.inviteReceived && this.discoveredAirPlay) {
      void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
    }
  }
}
