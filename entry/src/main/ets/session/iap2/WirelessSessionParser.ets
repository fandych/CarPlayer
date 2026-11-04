import { decodeIap2Parameters, decodeIap2String } from '../../protocol/Iap2Codec';

export interface WifiCredentials {
  ssid: string;
  password: string;
  securityType: number;
  channel: number;
}

export interface WirelessAirPlayEndpoint {
  addresses: string[];
  port: number;
  deviceIdentifier: string;
  publicKey: string;
  unrecognizedIdentity?: string;
  sourceVersion: string;
}

export function parseWirelessSessionEndpoint(body: Uint8Array): WirelessAirPlayEndpoint | undefined {
  const parameters = decodeIap2Parameters(body);
  const values = new Map<number, Uint8Array>();
  for (const parameter of parameters) {
    values.set(parameter.id, parameter.value);
  }
  const wirelessGroup = values.get(1);
  const portBytes = values.get(2);
  const deviceIdentifier = decodeIap2String(values.get(3) ?? new Uint8Array(0));
  const identity = decodeIap2String(values.get(4) ?? new Uint8Array(0));
  const publicKey = /^(?:0x)?[0-9a-fA-F]{64}$/.test(identity) ? identity : '';
  const sourceVersion = decodeIap2String(values.get(5) ?? new Uint8Array(0));
  if (!wirelessGroup || !portBytes || portBytes.length !== 4 || !deviceIdentifier || !sourceVersion) {
    return undefined;
  }
  const port = (((portBytes[0] * 256 + portBytes[1]) * 256 + portBytes[2]) * 256) + portBytes[3];
  if (port < 1 || port > 65535) {
    return undefined;
  }
  const addresses = decodeIap2Parameters(wirelessGroup)
    .filter((parameter) => parameter.id === 3)
    .map((parameter) => decodeIap2String(parameter.value).trim())
    .filter((address) => address.length > 0);
  if (addresses.length === 0) {
    return undefined;
  }
  const result: WirelessAirPlayEndpoint = {
    addresses,
    port,
    deviceIdentifier,
    publicKey,
    unrecognizedIdentity: publicKey ? undefined : identity,
    sourceVersion
  };
  return result;
}

export function parseWirelessSessionCredentials(body: Uint8Array): WifiCredentials | undefined {
  const wirelessGroup = decodeIap2Parameters(body).find((parameter) => parameter.id === 1);
  if (!wirelessGroup) {
    return undefined;
  }
  const values = new Map<number, Uint8Array>();
  for (const parameter of decodeIap2Parameters(wirelessGroup.value)) {
    values.set(parameter.id, parameter.value);
  }
  const ssid = decodeIap2String(values.get(0) ?? new Uint8Array(0));
  if (!ssid) {
    return undefined;
  }
  return {
    ssid,
    password: decodeIap2String(values.get(1) ?? new Uint8Array(0)),
    channel: values.get(2)?.[0] ?? 0,
    securityType: values.get(4)?.[0] ?? 0
  };
}
