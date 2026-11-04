import i18n from '@ohos.i18n';
import {
  concatBytes,
  decodeIap2Parameters,
  decodeIap2String,
  formatIap2LinkPayloadDiagnostic,
  groupedParameter,
  Iap2LinkFrame,
  numberParameter,
  stringParameter
} from '../../protocol/Iap2Codec';
import { formatProtocolEvent } from '../ProtocolLogger';
export const LINK_MARKER: Uint8Array = new Uint8Array([0xff, 0x55, 0x02, 0x00, 0xee, 0x10]);

export function formatIap2FrameInterpretation(direction: string, frame: Iap2LinkFrame): string {
  const isSync = (frame.control & 0x80) !== 0;
  const isReset = (frame.control & 0x10) !== 0;
  const payloadSummary = frame.payload.length === 0
    ? 'empty'
    : frame.payload[0] === 0x40 && frame.payload[1] === 0x40
      ? formatIap2LinkPayloadDiagnostic(direction, frame.payload)
      : `non-CSM payload omitted (${frame.payload.length}B)`;
  const meaning = isReset
    ? '链路复位帧，当前 iAP2 会话将终止'
    : isSync
      ? '链路同步帧，声明会话和传输参数'
      : frame.payload.length === 0
        ? '链路控制/确认帧，不包含控制消息'
        : '链路承载控制消息或分片';
  return formatProtocolEvent(`iap2.link.${direction.toLowerCase()}`,
    'control', `0x${frame.control.toString(16).padStart(2, '0')}`,
    'sequence', frame.sequence,
    'acknowledgement', frame.acknowledgement,
    'sessionId', frame.sessionId,
    'payloadBytes', frame.payload.length,
    'payloadSummary', payloadSummary,
    'meaning', meaning
  );
}

export interface Iap2MessageIds {
  IDENTIFICATION_START: number;
  IDENTIFICATION_INFORMATION: number;
  IDENTIFICATION_ACCEPTED: number;
  WIFI_REQUEST: number;
  WIFI_CONFIGURATION: number;
  MFI_CERTIFICATE_REQUEST: number;
  MFI_CERTIFICATE: number;
  MFI_CHALLENGE: number;
  MFI_RESPONSE: number;
  MFI_AUTHENTICATION_FAILED: number;
  MFI_AUTHENTICATION_SUCCEEDED: number;
  MFI_CERTIFICATE_SERIAL: number;
  CARPLAY_AVAILABILITY: number;
  CARPLAY_START_SESSION: number;
  WIRELESS_UPDATE: number;
  TRANSPORT_IDENTIFIER: number;
  START_HID: number;
  DEVICE_INFORMATION_UPDATE: number;
  DEVICE_LANGUAGE_UPDATE: number;
  DEVICE_TIME_UPDATE: number;
  DEVICE_UUID_UPDATE: number;
  DEVICE_HID_REPORT: number;
  AUX_STATUS_NOTIFICATION: number;
  EA_OPEN_SESSION: number;
  EA_SESSION_STATUS: number;
  MIB3_START_CALL_STATE_UPDATES: number;
  MIB3_CALL_STATE_UPDATE: number;
  MIB3_START_COMMUNICATIONS_UPDATES: number;
  MIB3_COMMUNICATIONS_UPDATE: number;
  MIB3_START_LIST_UPDATES: number;
  MIB3_LIST_UPDATE: number;
  MIB3_START_NOW_PLAYING_UPDATES: number;
  MIB3_NOW_PLAYING_UPDATE: number;
}

export const MESSAGE: Iap2MessageIds = {
  IDENTIFICATION_START: 0x1d00,
  IDENTIFICATION_INFORMATION: 0x1d01,
  IDENTIFICATION_ACCEPTED: 0x1d02,
  WIFI_REQUEST: 0x5702,
  WIFI_CONFIGURATION: 0x5703,
  MFI_CERTIFICATE_REQUEST: 0xaa00,
  MFI_CERTIFICATE: 0xaa01,
  MFI_CHALLENGE: 0xaa02,
  MFI_RESPONSE: 0xaa03,
  MFI_AUTHENTICATION_FAILED: 0xaa04,
  MFI_AUTHENTICATION_SUCCEEDED: 0xaa05,
  MFI_CERTIFICATE_SERIAL: 0xaa06,
  CARPLAY_AVAILABILITY: 0x4300,
  CARPLAY_START_SESSION: 0x4301,
  WIRELESS_UPDATE: 0x4e0d,
  TRANSPORT_IDENTIFIER: 0x4e0e,
  START_HID: 0x6800,
  DEVICE_INFORMATION_UPDATE: 0x4e09,
  DEVICE_LANGUAGE_UPDATE: 0x4e0a,
  DEVICE_TIME_UPDATE: 0x4e0b,
  DEVICE_UUID_UPDATE: 0x4e0c,
  DEVICE_HID_REPORT: 0x6801,
  AUX_STATUS_NOTIFICATION: 0xa100,
  EA_OPEN_SESSION: 0xea00,
  EA_SESSION_STATUS: 0xea03,
  MIB3_START_CALL_STATE_UPDATES: 0x4154,
  MIB3_CALL_STATE_UPDATE: 0x4155,
  MIB3_START_COMMUNICATIONS_UPDATES: 0x4157,
  MIB3_COMMUNICATIONS_UPDATE: 0x4158,
  MIB3_START_LIST_UPDATES: 0x4170,
  MIB3_LIST_UPDATE: 0x4171,
  MIB3_START_NOW_PLAYING_UPDATES: 0x5000,
  MIB3_NOW_PLAYING_UPDATE: 0x5001
};

export const MIB3_COMMUNICATIONS_IDLE_BODY: Uint8Array = new Uint8Array([
  0x00, 0x05, 0x00, 0x00, 0x01,
  0x00, 0x05, 0x00, 0x01, 0x06,
  0x00, 0x05, 0x00, 0x02, 0x00, 0x00,
  0x0e, 0x00, 0x04, 0xe6, 0x97, 0xa0, 0x53, 0x49, 0x4d, 0xe5, 0x8d, 0xa1, 0x00, 0x00,
  0x05, 0x00, 0x05, 0x01, 0x00,
  0x05, 0x00, 0x06, 0x01, 0x00,
  0x05, 0x00, 0x07, 0x00, 0x00,
  0x05, 0x00, 0x08, 0x00, 0x00,
  0x05, 0x00, 0x09, 0x00, 0x00,
  0x05, 0x00, 0x0a, 0x00, 0x00,
  0x05, 0x00, 0x0b, 0x00, 0x00,
  0x05, 0x00, 0x0c, 0x01, 0x00,
  0x05, 0x00, 0x0d, 0x00, 0x00,
  0x05, 0x00, 0x0e, 0x00, 0x00,
  0x05, 0x00, 0x0f, 0x00, 0x00,
  0x05, 0x00, 0x10, 0x00, 0x00,
  0x05, 0x00, 0x11, 0x00
]);
export const MIB3_NOW_PLAYING_IDLE_BODY: Uint8Array = new Uint8Array([
  0x00, 0x2a, 0x00, 0x00,
  0x00, 0x05, 0x00, 0x01, 0x00, 0x00,
  0x08, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x05, 0x00, 0x06, 0x00, 0x00,
  0x05, 0x00, 0x0c, 0x00, 0x00,
  0x05, 0x00, 0x10, 0x00, 0x00,
  0x05, 0x00, 0x12, 0x00, 0x00,
  0x05, 0x00, 0x1a, 0x80,
  0x00, 0x25, 0x00, 0x01, 0x00,
  0x05, 0x00, 0x00, 0x00, 0x00,
  0x08, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x05, 0x00, 0x05, 0x00, 0x00,
  0x05, 0x00, 0x06, 0x00, 0x00,
  0x05, 0x00, 0x07, 0x00, 0x00,
  0x05, 0x00, 0x10, 0x00
]);

export const WIFI_CONFIGURATION_WINDOW_MS: number = 60_000;

export interface EaProtocol {
  protocolId: number;
  name: string;
}

export function readEaProtocols(body: Uint8Array): EaProtocol[] {
  const parameters = decodeIap2Parameters(body);
  const protocols: EaProtocol[] = [];
  for (const groupId of [10, 11, 12]) {
    const group = parameters.find((parameter) => parameter.id === groupId);
    if (!group) {
      continue;
    }
    const children = decodeIap2Parameters(group.value);
    const protocolId = children.find((parameter) => parameter.id === 0)?.value[0];
    if (protocolId === undefined) {
      continue;
    }
    const name = decodeIap2String(
      children.find((parameter) => parameter.id === 1)?.value ?? new Uint8Array(0)
    );
    protocols.push({ protocolId, name });
  }
  return protocols;
}

export function currentDeviceLanguage(): string {
  try {
    return i18n.System.getSystemLanguage() || 'zh-Hans';
  } catch (_error) {
    return 'zh-Hans';
  }
}

export function readMessageIds(value: Uint8Array | undefined): number[] | undefined {
  if (!value || value.length % 2 !== 0) {
    return undefined;
  }
  const messageIds: number[] = [];
  for (let offset = 0; offset < value.length; offset += 2) {
    messageIds.push((value[offset] << 8) | value[offset + 1]);
  }
  return messageIds;
}

export function shouldProbeLegacyWifi(accessorySends?: number[], accessoryReceives?: number[]): boolean {
  const declaresLegacyWifi = accessoryReceives?.includes(MESSAGE.WIFI_REQUEST) === true ||
    accessorySends?.includes(MESSAGE.WIFI_CONFIGURATION) === true;
  const capabilityCount = (accessorySends?.length ?? 0) + (accessoryReceives?.length ?? 0);
  return declaresLegacyWifi || capabilityCount < 10;
}

export function isBuickB233Identity(identity: string): boolean {
  const normalized = identity.toLowerCase().replace(/\s+/g, ' ');
  return normalized.includes('buick') && normalized.includes('b233') &&
    normalized.includes('saic general motors');
}

export function isClassicMib3Profile(
  identity: string,
  accessorySends?: number[],
  accessoryReceives?: number[]
): boolean {
  if (accessorySends === undefined || accessoryReceives === undefined) {
    return false;
  }
  const normalized = identity.toLowerCase().replace(/\s+/g, ' ');
  const capabilityCount = accessorySends.length + accessoryReceives.length;
  return normalized.includes('delphi') && normalized.includes('audi') &&
    capabilityCount >= 1 && capabilityCount <= 9;
}

export function normalizeAccessoryIdentity(identity: string): string {
  return identity.toLowerCase().replace(/\s+/g, ' ').trim();
}

export function readAccessoryIdentity(body: Uint8Array): string {
  return decodeIap2Parameters(body)
    .filter((parameter) => parameter.id <= 2)
    .map((parameter) => decodeIap2String(parameter.value))
    .join(' ')
    .trim();
}

export function encodeBuickB233AvailabilityBody(deviceIdentifier: string, bluetoothAddress: string): Uint8Array {
  if (!/^[0-9A-F]{24}$/.test(deviceIdentifier)) {
    throw new Error('Buick B233 CarPlay device identifier must be 24 uppercase hex characters');
  }
  if (!/^(?!02:00:00:00:00:00$)(?!00:00:00:00:00:00$)([0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(bluetoothAddress)) {
    throw new Error('Buick B233 CarPlay availability requires a real Bluetooth MAC');
  }
  return concatBytes(
    groupedParameter(0, [numberParameter(0, 1, 1), stringParameter(1, deviceIdentifier)]),
    groupedParameter(1, [numberParameter(0, 1, 1), stringParameter(1, bluetoothAddress)])
  );
}

export function parseMfiCertificatePayload(body: Uint8Array): Uint8Array {
  const parameters = decodeIap2Parameters(body);
  const certificate = parameters.find((parameter) => parameter.id === 0)?.value;
  const baaMarker = parameters.find((parameter) => parameter.id === 1)?.value;
  const intermediate = parameters.find((parameter) => parameter.id === 2)?.value;
  if (!certificate || certificate.length === 0) {
    throw new Error('AA01 is missing certificate parameter 0');
  }
  if (baaMarker) {
    if (baaMarker.length !== 1 || baaMarker[0] !== 1 || !intermediate || intermediate.length === 0) {
      throw new Error('AA01 BAA certificate package has an invalid marker or intermediate certificate');
    }
    return concatBytes(certificate, intermediate);
  }
  if (intermediate) {
    throw new Error('AA01 has an intermediate certificate without the supported BAA marker');
  }
  return certificate;
}

