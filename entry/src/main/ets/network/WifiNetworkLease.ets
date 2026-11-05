import connection from '@ohos.net.connection';

const WIFI_NETWORK_BIND_WAIT_MS: number = 15_000;
const WIFI_NETWORK_BIND_WARNING_MS: number = 5000;

interface LocalNetworkAddresses {
  ipv4?: string;
  ipv6?: string;
  gatewayIpv4?: string;
  gatewayIpv6?: string;
  interfaceName?: string;
}

interface NetworkErrorWithCode extends Error {
  code?: number | string;
}

interface NetworkErrorDescription {
  code?: number | string;
  message?: string;
}

export class WifiNetworkLease {
  private netConnection?: connection.NetConnection;
  private netHandle?: connection.NetHandle;
  private registered: boolean = false;
  private availableHandler?: (handle: connection.NetHandle) => void;
  private lostHandler?: (handle: connection.NetHandle) => void;
  private unavailableHandler?: () => void;
  private availabilityTimer?: number;
  private availabilityWarningTimer?: number;
  private cancelAcquire?: () => void;
  private generation: number = 0;
  private localAddresses?: LocalNetworkAddresses;
  private log: (message: string) => void = (_message: string): void => {};

  get defaultGatewayAddress(): string | undefined {
    return this.localAddresses?.gatewayIpv4 ?? this.localAddresses?.gatewayIpv6;
  }

  async acquire(
    ssid: string,
    onLost: (message: string) => void,
    log: (message: string) => void,
    localAddress: string
  ): Promise<connection.NetHandle> {
    await this.release();
    const generation = this.generation;
    this.log = log;
    if (!localAddress || localAddress === '0.0.0.0') {
      throw new Error('车机 Wi-Fi 尚未分配可匹配的本机地址');
    }
    let connectedHandle: connection.NetHandle | undefined;
    let connectedLocalAddresses: LocalNetworkAddresses | undefined;
    for (const handle of await connection.getAllNets()) {
      try {
        const localAddresses = await this.getMatchingLocalAddresses(handle, localAddress);
        if (localAddresses) {
          connectedHandle = handle;
          connectedLocalAddresses = localAddresses;
          break;
        }
      } catch (error) {
        log(`跳过不可读取的网络 netId=${handle.netId}：${error instanceof Error ? error.message : String(error)}`);
      }
    }
    if (generation !== this.generation) {
      throw new Error('车机 Wi-Fi 网络选择已取消');
    }
    const netConnection = connection.createNetConnection({
      netCapabilities: {
        bearerTypes: [connection.NetBearType.BEARER_WIFI]
      }
    }, WIFI_NETWORK_BIND_WAIT_MS);
    this.netConnection = netConnection;
    this.netHandle = connectedHandle;
    this.localAddresses = connectedLocalAddresses;

    let resolveAvailable: (handle: connection.NetHandle) => void = () => {};
    let rejectAvailable: (error: Error) => void = () => {};
    const available = new Promise<connection.NetHandle>((resolve, reject) => {
      resolveAvailable = resolve;
      rejectAvailable = reject;
    });
    void available.catch((): void => {});
    this.cancelAcquire = (): void => rejectAvailable(new Error('车机 Wi-Fi 网络选择已取消'));
    this.availabilityTimer = setTimeout((): void => {
      rejectAvailable(new Error(`15 秒内未找到匹配本机地址的车机 WLAN：${ssid}`));
    }, WIFI_NETWORK_BIND_WAIT_MS);
    this.availabilityWarningTimer = setTimeout((): void => {
      if (this.netConnection === netConnection && generation === this.generation) {
        log(`匹配车机 WLAN 已等待 ${WIFI_NETWORK_BIND_WARNING_MS / 1000} 秒；仍等待 netAvailable，暂不使用默认路由`);
      }
    }, WIFI_NETWORK_BIND_WARNING_MS);
    this.availableHandler = (handle: connection.NetHandle): void => {
      void this.getMatchingLocalAddresses(handle, localAddress).then((addresses: LocalNetworkAddresses | undefined): void => {
        if (!addresses || this.netConnection !== netConnection || generation !== this.generation ||
          (this.netHandle && this.netHandle.netId !== handle.netId)) {
          return;
        }
        this.netHandle = handle;
        this.localAddresses = addresses;
        resolveAvailable(handle);
      }).catch((error: Error): void => {
        log(`车机 WLAN 候选校验失败：${error.message}`);
      });
    };
    this.lostHandler = (handle: connection.NetHandle): void => {
      if (this.netConnection === netConnection && this.netHandle?.netId === handle.netId) {
        this.netHandle = undefined;
        rejectAvailable(new Error('车机 WLAN 在网络选择期间丢失'));
        onLost(`指定车机 Wi-Fi 网络已丢失（netId=${handle.netId}）`);
      }
    };
    this.unavailableHandler = (): void => {
      rejectAvailable(new Error(`系统未提供指定车机 Wi-Fi 网络：${ssid}`));
    };
    netConnection.on('netAvailable', this.availableHandler);
    netConnection.on('netLost', this.lostHandler);
    netConnection.on('netUnavailable', this.unavailableHandler);

    try {
      await new Promise<void>((resolve, reject) => {
        netConnection.register((error) => {
          if (error) {
            reject(error);
          } else {
            resolve();
          }
        });
      });
      if (generation !== this.generation) {
        await new Promise<void>((resolve, reject) => {
          netConnection.unregister((error) => error ? reject(error) : resolve());
        });
        throw new Error('车机 Wi-Fi 网络选择已取消');
      }
      this.registered = true;
      if (this.netHandle) {
        resolveAvailable(this.netHandle);
      }
      const handle = await available;
      if (this.availabilityTimer !== undefined) {
        clearTimeout(this.availabilityTimer);
        this.availabilityTimer = undefined;
      }
      if (this.availabilityWarningTimer !== undefined) {
        clearTimeout(this.availabilityWarningTimer);
        this.availabilityWarningTimer = undefined;
      }
      this.cancelAcquire = undefined;
      log(`已匹配车机 WLAN：netId=${handle.netId}，localIp=${localAddress}`);
      return handle;
    } catch (error) {
      if (generation === this.generation) {
        await this.release();
      }
      throw error instanceof Error ? error : new Error(String(error));
    }
  }

  private async getMatchingLocalAddresses(
    handle: connection.NetHandle,
    selectedLocalAddress: string
  ): Promise<LocalNetworkAddresses | undefined> {
    const capabilities = await connection.getNetCapabilities(handle);
    if (!capabilities.bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) {
      return undefined;
    }
    const properties = await connection.getConnectionProperties(handle);
    const localAddresses: LocalNetworkAddresses = { interfaceName: properties.interfaceName };
    for (const link of properties.linkAddresses ?? []) {
      const address = link.address.address;
      if (address.includes(':')) {
        localAddresses.ipv6 = address;
      } else if (address === selectedLocalAddress) {
        localAddresses.ipv4 = address;
      }
    }
    for (const route of properties.routes ?? []) {
      if (!route.isDefaultRoute || !route.hasGateway) {
        continue;
      }
      const gateway = route.gateway.address;
      if (gateway.includes(':')) {
        const isLinkLocal = /^fe[89ab][0-9a-f]:/i.test(gateway);
        localAddresses.gatewayIpv6 = isLinkLocal && !gateway.includes('%') && properties.interfaceName
          ? `${gateway}%${properties.interfaceName}`
          : gateway;
      } else {
        localAddresses.gatewayIpv4 = gateway;
      }
    }
    return localAddresses.ipv4 ? localAddresses : undefined;
  }

  async bindSocket(
    socket: connection.TCPSocket | connection.UDPSocket,
    purpose: string,
    requestedFamily: number = 1,
    localPort: number = 0
  ): Promise<boolean> {
    const handle = this.netHandle;
    if (!handle) {
      throw new Error('没有已确认的车机 WLAN，拒绝使用默认路由');
    }
    const addressFamily = requestedFamily === 2 ? 2 : 1;
    const localAddress = addressFamily === 2 ? this.localAddresses?.ipv6 : this.localAddresses?.ipv4;
    if (!localAddress) {
      throw new Error(`指定车机 WLAN 没有可用于 IPv${addressFamily} socket 的本机地址，拒绝使用默认路由`);
    }
    let stage: string = 'local-socket-bind';
    try {
      const bindAddress: connection.NetAddress = {
        address: localAddress,
        family: addressFamily,
        port: localPort
      };
      await socket.bind(bindAddress);
      stage = 'network-bind';
      await handle.bindSocket(socket);
      this.log(`指定车机 Wi-Fi socket 已绑定：purpose=${purpose}, netId=${handle.netId}, family=IPv${addressFamily}`);
      return true;
    } catch (error) {
      const detail = formatNetworkError(error);
      this.log(`指定车机 Wi-Fi socket 绑定失败：stage=${stage}, purpose=${purpose}, netId=${handle.netId}, family=IPv${addressFamily}, error=${detail}`);
      throw new Error(`车机 Wi-Fi socket 绑定失败（${stage}，${detail}），拒绝使用默认路由`);
    }
  }

  async release(): Promise<void> {
    this.generation++;
    this.cancelAcquire?.();
    this.cancelAcquire = undefined;
    if (this.availabilityTimer !== undefined) {
      clearTimeout(this.availabilityTimer);
      this.availabilityTimer = undefined;
    }
    if (this.availabilityWarningTimer !== undefined) {
      clearTimeout(this.availabilityWarningTimer);
      this.availabilityWarningTimer = undefined;
    }
    const netConnection = this.netConnection;
    this.netConnection = undefined;
    this.netHandle = undefined;
    this.localAddresses = undefined;
    if (!netConnection) {
      this.log = (_message: string): void => {};
      return;
    }
    let unregisterError: Error | undefined;
    if (this.registered) {
      try {
        await new Promise<void>((resolve, reject) => {
          netConnection.unregister((error) => {
            if (error) {
              reject(error);
            } else {
              resolve();
            }
          });
        });
      } catch (error) {
        unregisterError = error instanceof Error ? error : new Error(String(error));
      }
    }
    this.registered = false;
    this.availableHandler = undefined;
    this.lostHandler = undefined;
    this.unavailableHandler = undefined;
    this.log = (_message: string): void => {};
    if (unregisterError) {
      throw unregisterError;
    }
  }
}

export function getSocketAddressFamily(address: string): number {
  return address.includes(':') ? 2 : 1;
}

export function formatNetworkError(error: Error | Object): string {
  if (error instanceof Error) {
    const details = error as NetworkErrorWithCode;
    return details.code === undefined ? details.message : `${details.message} (code=${details.code})`;
  }
  const details = error as NetworkErrorDescription;
  const parts: string[] = [];
  if (details.code !== undefined) {
    parts.push(`code=${details.code}`);
  }
  if (details.message) {
    parts.push(details.message);
  }
  if (parts.length > 0) {
    return parts.join(': ');
  }
  try {
    return JSON.stringify(error) || String(error);
  } catch (_serializationError) {
    return String(error);
  }
}