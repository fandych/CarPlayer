import { AirPlayService } from '../../network/AirPlayMdnsDiscovery';
import { WirelessAirPlayEndpoint } from '../Iap2SenderSession';

export function isAirPlayStartReady(
  networkReady: boolean,
  invited: boolean,
  hasCompleteEndpoint: boolean,
  hasMdnsService: boolean = false,
  endpointResolutionComplete: boolean = false
): boolean {
  return networkReady && (
    hasCompleteEndpoint ||
    hasMdnsService ||
    (invited && endpointResolutionComplete)
  );
}

export function makeAirPlayServiceFromEndpoint(endpoint: WirelessAirPlayEndpoint): AirPlayService {
  const addresses = endpoint.addresses.slice();
  const host = addresses.find((address: string): boolean => address.includes('.') && !address.includes(':')) ??
    addresses[0] ?? '';
  const txt: Record<string, string> = {};
  txt['deviceid'] = endpoint.deviceIdentifier;
  if (endpoint.publicKey) {
    txt['pk'] = endpoint.publicKey;
  }
  txt['srcvers'] = endpoint.sourceVersion;
  const service: AirPlayService = {
    name: `iAP2 ${endpoint.deviceIdentifier}`,
    host,
    addresses,
    port: endpoint.port,
    txt
  };
  return service;
}

export function normalizeDeviceIdentifier(value: string): string {
  return value.trim().replace(/[:-]/g, '').toLowerCase();
}
