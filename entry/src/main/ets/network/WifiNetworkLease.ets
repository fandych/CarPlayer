import connection from '@ohos.net.connection';

const WIFI_NETWORK_BIND_WAIT_MS: number = 15_000;
const WIFI_NETWORK_BIND_WARNING_MS: number = 5000;

interface LocalNetworkAddresses {
  ipv4?: string;
  ipv4PrefixLength?: number;
  ipv6?: string;
  ipv6PrefixLength?: number;
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

  isAirPlayAddressOnSelectedNetwork(address: string): boolean {
    const candidate = stripIpv6ScopeId(address.replace(/^\[|\]$/g, ''));
    if (isIpv4Address(candidate)) {
      const localAddress = this.localAddresses?.ipv4;
      const prefixLength = this.localAddresses?.ipv4PrefixLength;
      return localAddress !== undefined && prefixLength !== undefined &&
        ipv4AddressesSharePrefix(candidate, localAddress, prefixLength);
    }
    if (!candidate.includes(':')) {
      return false;
    }
    if (isIpv6LinkLocal(candidate)) {
      return this.localAddresses?.interfaceName !== undefined;
    }
    const localAddress = this.localAddresses?.ipv6;
    const prefixLength = this.localAddresses?.ipv6PrefixLength;
    return localAddress !== undefined && prefixLength !== undefined &&
      ipv6AddressesSharePrefix(candidate, localAddress, prefixLength);
  }

  scopeLinkLocalAddress(address: string): string {
    const normalizedAddress = address.replace(/^\[|\]$/g, '');
    if (!isUnscopedIpv6LinkLocal(normalizedAddress)) {
      return address;
    }
    const interfaceName = this.localAddresses?.interfaceName;
    if (!interfaceName) {
      throw new Error('车机 Wi-Fi interfaceName is unavailable for IPv6 link-local address');
    }
    return `${normalizedAddress}%${interfaceName}`;
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
        if (!localAddresses.ipv6 || !isIpv6LinkLocal(address)) {
          localAddresses.ipv6 = address;
          localAddresses.ipv6PrefixLength = link.prefixLength;
        }
      } else if (address === selectedLocalAddress) {
        localAddresses.ipv4 = address;
        localAddresses.ipv4PrefixLength = link.prefixLength;
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
    const selectedLocalAddress = addressFamily === 2 ? this.localAddresses?.ipv6 : this.localAddresses?.ipv4;
    if (!selectedLocalAddress && addressFamily === 1) {
      throw new Error(`指定车机 WLAN 没有可用于 IPv${addressFamily} socket 的本机地址，拒绝使用默认路由`);
    }
    let stage: string = 'local-socket-bind';
    try {
      if (!selectedLocalAddress) {
        this.log(`车机 WLAN 未列出 IPv6 本机地址；使用 IPv6 通配绑定，由 netId=${handle.netId} 限定网络`);
      }
      const bindAddress: connection.NetAddress = {
        address: selectedLocalAddress
          ? (addressFamily === 2 ? this.scopeLinkLocalAddress(selectedLocalAddress) : selectedLocalAddress)
          : '::',
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

function isUnscopedIpv6LinkLocal(address: string): boolean {
  return !address.includes('%') && isIpv6LinkLocal(address);
}

function isIpv6LinkLocal(address: string): boolean {
  return /^fe[89ab][0-9a-f]:/i.test(address);
}

function ipv4AddressesSharePrefix(left: string, right: string, prefixLength: number): boolean {
  if (!Number.isInteger(prefixLength) || prefixLength < 0 || prefixLength > 32 ||
    !isIpv4Address(left) || !isIpv4Address(right)) {
    return false;
  }
  if (prefixLength === 0) {
    return true;
  }
  const blockSize = 2 ** (32 - prefixLength);
  return Math.floor(ipv4AddressNumber(left) / blockSize) === Math.floor(ipv4AddressNumber(right) / blockSize);
}

function ipv4AddressNumber(address: string): number {
  return address.split('.').reduce((value: number, octet: string): number => value * 256 + Number(octet), 0);
}

function ipv6AddressesSharePrefix(left: string, right: string, prefixLength: number): boolean {
  if (!Number.isInteger(prefixLength) || prefixLength < 0 || prefixLength > 128) {
    return false;
  }
  const leftBytes = parseIpv6Address(left);
  const rightBytes = parseIpv6Address(right);
  if (!leftBytes || !rightBytes) {
    return false;
  }
  const fullBytes = Math.floor(prefixLength / 8);
  for (let index = 0; index < fullBytes; index++) {
    if (leftBytes[index] !== rightBytes[index]) {
      return false;
    }
  }
  const remainingBits = prefixLength % 8;
  if (remainingBits === 0) {
    return true;
  }
  const mask = (0xff << (8 - remainingBits)) & 0xff;
  return (leftBytes[fullBytes] & mask) === (rightBytes[fullBytes] & mask);
}

function parseIpv6Address(address: string): number[] | undefined {
  const normalized = stripIpv6ScopeId(address.toLowerCase());
  if (!normalized.includes(':')) {
    return undefined;
  }
  const compressionIndex = normalized.indexOf('::');
  let groups: string[];
  if (compressionIndex >= 0) {
    if (normalized.indexOf('::', compressionIndex + 2) >= 0) {
      return undefined;
    }
    const left = normalized.slice(0, compressionIndex).split(':').filter(Boolean);
    const right = normalized.slice(compressionIndex + 2).split(':').filter(Boolean);
    const zeroCount = 8 - left.length - right.length;
    if (zeroCount < 1) {
      return undefined;
    }
    groups = left.concat(new Array<string>(zeroCount).fill('0'), right);
  } else {
    groups = normalized.split(':');
  }
  if (groups.length !== 8 || groups.some((group: string): boolean => !/^[0-9a-f]{1,4}$/.test(group))) {
    return undefined;
  }
  const bytes: number[] = [];
  for (const group of groups) {
    const value = Number.parseInt(group, 16);
    bytes.push((value >> 8) & 0xff, value & 0xff);
  }
  return bytes;
}

export function getSocketAddressFamily(address: string): number {
  return address.includes(':') ? 2 : 1;
}

export function stripIpv6ScopeId(address: string): string {
  const scopeSeparator = address.indexOf('%');
  return scopeSeparator === -1 ? address : address.slice(0, scopeSeparator);
}

export function orderAirPlayAddresses(addresses: string[]): string[] {
  const ipv4: string[] = [];
  const ipv6: string[] = [];
  const linkLocalIpv6: string[] = [];
  const other: string[] = [];
  const seen: Set<string> = new Set<string>();
  for (const address of addresses) {
    const candidate = address.trim().replace(/^\[|\]$/g, '');
    const unscopedAddress = stripIpv6ScopeId(candidate);
    if (!unscopedAddress || seen.has(unscopedAddress.toLowerCase())) {
      continue;
    }
    seen.add(unscopedAddress.toLowerCase());
    if (isIpv4Address(unscopedAddress)) {
      ipv4.push(candidate);
    } else if (unscopedAddress.includes(':') && /^fe[89ab][0-9a-f]:/i.test(unscopedAddress)) {
      linkLocalIpv6.push(candidate);
    } else if (unscopedAddress.includes(':')) {
      ipv6.push(candidate);
    } else {
      other.push(candidate);
    }
  }
  return ipv4.concat(ipv6, linkLocalIpv6, other);
}

function isIpv4Address(address: string): boolean {
  const octets = address.split('.');
  return octets.length === 4 && octets.every((octet: string): boolean =>
    /^\d{1,3}$/.test(octet) && Number(octet) <= 255
  );
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