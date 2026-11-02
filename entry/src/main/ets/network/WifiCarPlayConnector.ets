import wifiManager from '@ohos.wifiManager';
import { WifiCredentials } from '../session/Iap2SenderSession';
import { formatProtocolEvent } from '../session/ProtocolLogger';

export interface WifiConnectionResult {
  ssid: string;
  ipAddress: string;
}

interface WifiApiErrorDetails {
  code?: number;
  message?: string;
}

export class WifiCarPlayConnector {
  private pendingNetworkId: number = -1;
  private requestGeneration: number = 0;
  private logCallback: (message: string) => void = (_message: string): void => {};

  async connect(
    credentials: WifiCredentials,
    log: (message: string) => void = (_message: string): void => {}
  ): Promise<WifiConnectionResult> {
    const startedAt = Date.now();
    this.logCallback = log;
    if (credentials.ssid.length === 0 || credentials.ssid.length > 32) {
      throw new Error('车机 Wi-Fi 名称无效');
    }
    if (!wifiManager.isWifiActive()) {
      throw new Error('请先开启手机 Wi-Fi，再连接车机热点');
    }
    if (this.pendingNetworkId >= 0) {
      const previousNetworkId = this.pendingNetworkId;
      if (!await this.removeCandidate(previousNetworkId, log, 'before-next-join')) {
        throw new Error('上次车机 Wi-Fi 候选配置清理失败，请重试');
      }
      this.pendingNetworkId = -1;
    }
    const currentLink = await wifiManager.getLinkedInfo();
    if (currentLink.ssid === credentials.ssid && currentLink.ipAddress !== 0) {
      const result: WifiConnectionResult = {
        ssid: credentials.ssid,
        ipAddress: this.formatIpAddress(currentLink.ipAddress)
      };
      log(formatProtocolEvent('wifi.link.already_connected',
        'ssid', result.ssid,
        'localIp', result.ipAddress,
        'elapsedMs', Date.now() - startedAt
      ));
      return result;
    }
    const securityType = this.mapSecurityType(credentials.securityType);
    await this.removeExistingCandidates(log, 'before-next-candidate', credentials.ssid);
    const config: wifiManager.WifiDeviceConfig = {
      ssid: credentials.ssid,
      preSharedKey: credentials.password,
      securityType,
      showNoInternetDialog: false
    };
    let networkId: number;
    try {
      networkId = await this.addCandidateConfig(config, credentials.ssid, log);
    } catch (error) {
      const message = formatWifiApiError(error);
      log(formatProtocolEvent('wifi.candidate.add_failed',
        'ssid', credentials.ssid,
        'elapsedMs', Date.now() - startedAt,
        'error', message
      ));
      throw new Error(`添加车机 Wi-Fi 候选配置失败：${message}`);
    }
    if (networkId < 0) {
      throw new Error('系统没有接受车机 Wi-Fi 配置');
    }
    log(formatProtocolEvent('wifi.candidate.added',
      'ssid', credentials.ssid,
      'securityType', credentials.securityType,
      'channel', credentials.channel,
      'networkId', networkId
    ));
    const generation = ++this.requestGeneration;
    this.pendingNetworkId = networkId;
    try {
      await wifiManager.connectToCandidateConfig({
        networkId,
        withUserAction: false,
        addNetworkToSystem: false
      });
      log(formatProtocolEvent('wifi.candidate.connect.requested',
        'ssid', credentials.ssid,
        'networkId', networkId,
        'withUserAction', false,
        'addNetworkToSystem', false
      ));
      if (generation !== this.requestGeneration) {
        throw new Error('CarPlay 连接已取消');
      }
      const deadline = Date.now() + 20000;
      let pollCount = 0;
      while (Date.now() < deadline) {
        if (generation !== this.requestGeneration) {
          throw new Error('CarPlay 连接已取消');
        }
        const linked = await wifiManager.getLinkedInfo();
        pollCount++;
        if (pollCount === 1 || pollCount % 5 === 0) {
          log(formatProtocolEvent('wifi.link.poll',
            'elapsedMs', Date.now() - startedAt,
            'requestedSsid', credentials.ssid,
            'currentSsid', linked.ssid || null,
            'ssidMatched', linked.ssid === credentials.ssid,
            'hasIpAddress', linked.ipAddress !== 0
          ));
        }
        if (generation !== this.requestGeneration) {
          throw new Error('CarPlay 连接已取消');
        }
        if (linked.ssid === credentials.ssid && linked.ipAddress !== 0) {
          const result: WifiConnectionResult = {
            ssid: credentials.ssid,
            ipAddress: this.formatIpAddress(linked.ipAddress)
          };
          log(formatProtocolEvent('wifi.link.connected',
            'ssid', result.ssid,
            'localIp', result.ipAddress,
            'networkId', networkId,
            'elapsedMs', Date.now() - startedAt
          ));
          if (this.pendingNetworkId === networkId && generation === this.requestGeneration) {
            this.pendingNetworkId = -1;
            log(formatProtocolEvent('wifi.candidate.retained',
              'networkId', networkId,
              'reason', 'allow-auto-reconnect'
            ));
          }
          return result;
        }
        await new Promise<void>((resolve: () => void): void => {
          setTimeout(resolve, 1000);
        });
      }
      const linked = await wifiManager.getLinkedInfo();
      const actualSsid = linked.ssid.length > 0 ? linked.ssid : '未知网络';
      log(formatProtocolEvent('wifi.link.timeout',
        'requestedSsid', credentials.ssid,
        'currentSsid', actualSsid,
        'timeoutMs', 20000,
        'elapsedMs', Date.now() - startedAt
      ));
      throw new Error(`20 秒内未确认加入车机热点；当前网络为 ${actualSsid}`);
    } catch (error) {
      const message = formatWifiApiError(error);
      log(formatProtocolEvent('wifi.join.failed',
        'ssid', credentials.ssid,
        'networkId', networkId,
        'elapsedMs', Date.now() - startedAt,
        'error', message
      ));
      if (this.pendingNetworkId === networkId && generation === this.requestGeneration) {
        if (await this.removeCandidate(networkId, log, 'join-failed')) {
          this.pendingNetworkId = -1;
        }
      }
      throw new Error(message);
    }
  }

  async cancelPendingJoin(): Promise<void> {
    this.requestGeneration++;
    const networkId = this.pendingNetworkId;
    if (networkId < 0) {
      return;
    }
    const removed = await this.removeCandidate(
      networkId,
      this.logCallback,
      'cancelled'
    );
    if (!removed) {
      throw new Error('取消车机 Wi-Fi 加入失败：候选配置未能清理');
    }
    if (this.pendingNetworkId === networkId) {
      this.pendingNetworkId = -1;
    }
  }

  private async addCandidateConfig(
    config: wifiManager.WifiDeviceConfig,
    ssid: string,
    log: (message: string) => void
  ): Promise<number> {
    try {
      return await wifiManager.addCandidateConfig(config);
    } catch (error) {
      const originalMessage = formatWifiApiError(error);
      let message = originalMessage;
      let removedCount = 0;
      if (/config(?:uration)? count.*exceed.*limit/i.test(originalMessage)) {
        removedCount = await this.removeExistingCandidates(log, 'limit-recovery');
        if (removedCount > 0) {
          try {
            const networkId = await wifiManager.addCandidateConfig(config);
            log(formatProtocolEvent('wifi.candidate.add_retry',
              'ssid', ssid,
              'removedStaleCandidates', removedCount,
              'networkId', networkId
            ));
            return networkId;
          } catch (retryError) {
            message = formatWifiApiError(retryError);
          }
        }
      }
      throw new Error(message);
    }
  }

  private async removeExistingCandidates(
    log: (message: string) => void,
    reason: string,
    ssid?: string
  ): Promise<number> {
    let removedCount = 0;
    let candidates: wifiManager.WifiDeviceConfig[];
    try {
      candidates = wifiManager.getCandidateConfigs();
    } catch (error) {
      log(formatProtocolEvent('wifi.candidate.list_failed',
        'reason', reason,
        'error', formatWifiApiError(error)
      ));
      return removedCount;
    }
    for (const candidate of candidates) {
      if (ssid !== undefined && candidate.ssid !== ssid) {
        continue;
      }
      const networkId = candidate.netId;
      if (networkId !== undefined && networkId >= 0 && await this.removeCandidate(networkId, log, reason)) {
        removedCount++;
      }
    }
    return removedCount;
  }

  private async removeCandidate(
    networkId: number,
    log: (message: string) => void,
    reason: string
  ): Promise<boolean> {
    try {
      await wifiManager.removeCandidateConfig(networkId);
      log(formatProtocolEvent('wifi.candidate.removed',
        'networkId', networkId,
        'reason', reason
      ));
      return true;
    } catch (error) {
      log(formatProtocolEvent('wifi.candidate.remove_failed',
        'networkId', networkId,
        'reason', reason,
        'error', formatWifiApiError(error)
      ));
      return false;
    }
  }

  private mapSecurityType(type: number): wifiManager.WifiSecurityType {
    switch (type) {
      case 0:
        return wifiManager.WifiSecurityType.WIFI_SEC_TYPE_OPEN;
      case 1:
        throw new Error('HarmonyOS 候选网络 API 不支持 WEP 车机热点');
      case 2:
      case 3:
        return wifiManager.WifiSecurityType.WIFI_SEC_TYPE_PSK;
      case 4:
        return wifiManager.WifiSecurityType.WIFI_SEC_TYPE_SAE;
      default:
        throw new Error(`暂不支持车机 Wi-Fi 安全类型 ${type}`);
    }
  }

  private formatIpAddress(ipAddress: number): string {
    return formatWifiIpv4Address(ipAddress);
  }
}

// WifiLinkedInfo.ipAddress holds the first octet in the most significant byte.
export function formatWifiIpv4Address(ipAddress: number): string {
  return [
    (ipAddress >>> 24) & 0xff,
    (ipAddress >>> 16) & 0xff,
    (ipAddress >>> 8) & 0xff,
    ipAddress & 0xff
  ].join('.');
}

function formatWifiApiError(error: Error | Object): string {
  if (error instanceof Error) {
    return error.message;
  }
  const details = error as WifiApiErrorDetails;
  const parts: string[] = [];
  if (details.code !== undefined) {
    parts.push(`code=${details.code}`);
  }
  if (details.message) {
    parts.push(details.message);
  }
  return parts.length > 0 ? parts.join(': ') : JSON.stringify(error) || String(error);
}
