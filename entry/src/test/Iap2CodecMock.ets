import { NativeIap2Codec, NativeTlv8DecodeResult } from '../main/ets/protocol/Iap2Codec';

// Host-only stand-in. Native behavior is tested separately in C and on device.
function encodeLink(control: number, sequence: number, acknowledgement: number, session: number,
  payload: Uint8Array): Uint8Array {
  const length = 9 + payload.length + (payload.length > 0 ? 1 : 0);
  if (length > 65535) throw new Error('iAP2 link frame is too large');
  const result = new Uint8Array(length);
  result.set([0xff, 0x5a, length >> 8, length & 255, control, sequence, acknowledgement, session], 0);
  let sum = 0;
  for (let index = 0; index < 8; index++) sum += result[index];
  result[8] = -sum & 255;
  if (payload.length > 0) {
    result.set(payload, 9);
    sum = 0;
    for (const byte of payload) sum += byte;
    result[length - 1] = -sum & 255;
  }
  return result;
}

function scanLink(bytes: Uint8Array): number[] {
  for (let start = 0; start + 1 < bytes.length; start++) {
    if (bytes[start] !== 0xff || bytes[start + 1] !== 0x5a) continue;
    if (bytes.length - start < 9) return [start, 0, 0];
    const length = (bytes[start + 2] << 8) | bytes[start + 3];
    let sum = 0;
    for (let index = 0; index < 9; index++) sum += bytes[start + index];
    if (length < 9 || (sum & 255) !== 0) continue;
    if (bytes.length - start < length) return [start, 0, 0];
    sum = 0;
    for (let index = 9; index < length; index++) sum += bytes[start + index];
    if ((sum & 255) !== 0) continue;
    return [start + length, start, length];
  }
  return [Math.max(0, bytes.length - 1), 0, 0];
}

function encodeControl(id: number, body: Uint8Array): Uint8Array {
  const length = body.length + 6;
  if (length > 65535) throw new Error('iAP2 control frame is too large');
  const result = new Uint8Array(length);
  result.set([0x40, 0x40, length >> 8, length & 255, id >> 8, id & 255], 0);
  result.set(body, 6);
  return result;
}

function encodeParameter(id: number, value: Uint8Array): Uint8Array {
  const length = value.length + 4;
  if (length > 65535) throw new Error('iAP2 parameter is too large');
  const result = new Uint8Array(length);
  result.set([length >> 8, length & 255, id >> 8, id & 255], 0);
  result.set(value, 4);
  return result;
}

function scanControl(bytes: Uint8Array): number[] {
  for (let start = 0; start + 1 < bytes.length; start++) {
    if (bytes[start] !== 0x40 || bytes[start + 1] !== 0x40) continue;
    if (bytes.length - start < 6) return [start, 0, 0];
    const length = (bytes[start + 2] << 8) | bytes[start + 3];
    if (length < 6) continue;
    if (bytes.length - start < length) return [start, 0, 0];
    return [start + length, start, length];
  }
  return [Math.max(0, bytes.length - 1), 0, 0];
}

function parseParameters(bytes: Uint8Array): number[] {
  const entries: number[] = [];
  let offset = 0;
  while (offset < bytes.length) {
    if (bytes.length - offset < 4) throw new Error('Malformed iAP2 parameter');
    const length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 4 || length > bytes.length - offset) throw new Error('Malformed iAP2 parameter');
    entries.push((bytes[offset + 2] << 8) | bytes[offset + 3], offset + 4, length - 4);
    offset += length;
  }
  return entries;
}

function encodeTlv8(types: Uint8Array, values: Uint8Array[]): Uint8Array {
  const parts: Uint8Array[] = [];
  for (let index = 0; index < types.length; index++) {
    const type = types[index];
    const value = values[index];
    if (type === undefined || type >= 0xff || !value) throw new Error('Invalid TLV8 item');
    if (index > 0 && type === types[index - 1]) parts.push(new Uint8Array([0xff, 0]));
    if (value.length === 0) {
      parts.push(new Uint8Array([type, 0]));
      continue;
    }
    for (let offset = 0; offset < value.length; offset += 255) {
      const fragment = value.subarray(offset, Math.min(offset + 255, value.length));
      parts.push(new Uint8Array([type, fragment.length]), fragment);
    }
  }
  const length = parts.reduce((total, part) => total + part.length, 0);
  const result = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

function decodeTlv8(bytes: Uint8Array): NativeTlv8DecodeResult {
  const decoded = new Map<number, Uint8Array>();
  let offset = 0;
  let previousType = -1;
  let previousLength = 0;
  let separatorSeen = false;
  while (offset < bytes.length) {
    if (bytes.length - offset < 2) throw new Error('Truncated TLV8 header');
    const type = bytes[offset];
    const length = bytes[offset + 1];
    if (type === undefined || length === undefined || offset + 2 + length > bytes.length ||
      (type === 0xff && length !== 0)) throw new Error('Malformed TLV8 item');
    const value = bytes.slice(offset + 2, offset + 2 + length);
    if (type === 0xff) {
      previousType = -1;
      previousLength = 0;
      separatorSeen = true;
      offset += 2 + length;
      continue;
    }
    if (previousType === type && previousLength === 255 && !separatorSeen) {
      const prior = decoded.get(type) ?? new Uint8Array(0);
      const combined = new Uint8Array(prior.length + value.length);
      combined.set(prior);
      combined.set(value, prior.length);
      decoded.set(type, combined);
    } else {
      decoded.set(type, value);
    }
    previousType = type;
    previousLength = length;
    separatorSeen = false;
    offset += 2 + length;
  }
  const ranges: number[] = [];
  const values: number[] = [];
  decoded.forEach((value: Uint8Array, type: number): void => {
    ranges.push(type, values.length, value.length);
    for (const byte of value) values.push(byte);
  });
  const result: NativeTlv8DecodeResult = {
    ranges: Uint32Array.from(ranges),
    values: Uint8Array.from(values)
  };
  return result;
}

class MockCodec implements NativeIap2Codec {
  encodeLink(control: number, sequence: number, acknowledgement: number, session: number,
    payload: Uint8Array): Uint8Array { return encodeLink(control, sequence, acknowledgement, session, payload); }
  scanLink(bytes: Uint8Array): number[] { return scanLink(bytes); }
  encodeControl(id: number, body: Uint8Array): Uint8Array { return encodeControl(id, body); }
  encodeParameter(id: number, value: Uint8Array): Uint8Array { return encodeParameter(id, value); }
  scanControl(bytes: Uint8Array): number[] { return scanControl(bytes); }
  parseParameters(bytes: Uint8Array): number[] { return parseParameters(bytes); }
  encodeTlv8(types: Uint8Array, values: Uint8Array[]): Uint8Array { return encodeTlv8(types, values); }
  decodeTlv8(bytes: Uint8Array): NativeTlv8DecodeResult { return decodeTlv8(bytes); }
}

const mockCodec: MockCodec = new MockCodec();
export default mockCodec;