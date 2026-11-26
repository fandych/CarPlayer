import connection from '@ohos.net.connection';
import { isIpv6LinkLocal } from './WifiNetworkAddress';

export interface LocalNetworkAddresses {
  ipv4?: string;
  ipv4PrefixLength?: number;
  ipv6?: string;
  ipv6PrefixLength?: number;
  gatewayIpv4?: string;
  gatewayIpv6?: string;
  interfaceName?: string;
}

export async function getMatchingWifiNetworkAddresses(
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
