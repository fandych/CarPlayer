export interface Iap2LinkFrame {
  control: number;
  sequence: number;
  acknowledgement: number;
  sessionId: number;
  payload: Uint8Array;
  raw?: Uint8Array;
}

export interface Iap2Parameter {
  id: number;
  value: Uint8Array;
}

export interface Iap2ScanResult {
  consumed: number;
  frameOffset: number;
  frameLength: number;
}

const LINK_HEADER_LENGTH: number = 9;
const CONTROL_HEADER_LENGTH: number = 6;
const PARAMETER_HEADER_LENGTH: number = 4;
const MAX_FRAME_LENGTH: number = 0xffff;

export function concatBytes(...parts: Uint8Array[]): Uint8Array {
  let length = 0;
  for (const part of parts) {
    length += part.length;
  }
  const result = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

export function readU16(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] << 8) | bytes[offset + 1];
}

function writeU16(bytes: Uint8Array, offset: number, value: number): void {
  bytes[offset] = (value >>> 8) & 0xff;
  bytes[offset + 1] = value & 0xff;
}

function checksum(bytes: Uint8Array, offset: number, length: number): number {
  let sum = 0;
  for (let index = 0; index < length; index++) {
    sum = (sum + bytes[offset + index]) & 0xff;
  }
  return (-sum) & 0xff;
}

export function encodeIap2LinkFrame(frame: Iap2LinkFrame): Uint8Array {
  const payload = frame.payload;
  if (payload.length > MAX_FRAME_LENGTH - LINK_HEADER_LENGTH - 1) {
    throw new Error('iAP2 link frame is too large');
  }
  const length = LINK_HEADER_LENGTH + payload.length + (payload.length > 0 ? 1 : 0);
  const output = new Uint8Array(length);
  output[0] = 0xff;
  output[1] = 0x5a;
  writeU16(output, 2, length);
  output[4] = frame.control & 0xff;
  output[5] = frame.sequence & 0xff;
  output[6] = frame.acknowledgement & 0xff;
  output[7] = frame.sessionId & 0xff;
  output[8] = checksum(output, 0, 8);
  if (payload.length > 0) {
    output.set(payload, LINK_HEADER_LENGTH);
    output[length - 1] = checksum(payload, 0, payload.length);
  }
  return output;
}

export function scanIap2Link(bytes: Uint8Array): Iap2ScanResult {
  let offset = 0;
  while (offset + 1 < bytes.length) {
    if (bytes[offset] !== 0xff || bytes[offset + 1] !== 0x5a) {
      offset++;
      continue;
    }
    if (bytes.length - offset < LINK_HEADER_LENGTH) {
      return { consumed: offset, frameOffset: 0, frameLength: 0 };
    }
    const frameLength = readU16(bytes, offset + 2);
    if (frameLength < LINK_HEADER_LENGTH || frameLength === LINK_HEADER_LENGTH + 1 ||
      checksum(bytes, offset, LINK_HEADER_LENGTH) !== 0) {
      offset++;
      continue;
    }
    if (bytes.length - offset < frameLength) {
      return { consumed: offset, frameOffset: 0, frameLength: 0 };
    }
    if (checksum(bytes, offset + LINK_HEADER_LENGTH, frameLength - LINK_HEADER_LENGTH) !== 0) {
      offset++;
      continue;
    }
    return { consumed: offset + frameLength, frameOffset: offset, frameLength };
  }
  return { consumed: Math.max(0, bytes.length - 1), frameOffset: 0, frameLength: 0 };
}

export function encodeIap2Control(messageId: number, body: Uint8Array = new Uint8Array(0)): Uint8Array {
  if (!Number.isInteger(messageId) || messageId < 0 || messageId > 0xffff ||
    body.length + CONTROL_HEADER_LENGTH > MAX_FRAME_LENGTH) {
    throw new Error('iAP2 control frame is too large or has an invalid message ID');
  }
  const output = new Uint8Array(CONTROL_HEADER_LENGTH + body.length);
  output[0] = 0x40;
  output[1] = 0x40;
  writeU16(output, 2, output.length);
  writeU16(output, 4, messageId);
  output.set(body, CONTROL_HEADER_LENGTH);
  return output;
}

export function encodeIap2Parameter(id: number, value: Uint8Array): Uint8Array {
  if (!Number.isInteger(id) || id < 0 || id > 0xffff ||
    value.length + PARAMETER_HEADER_LENGTH > MAX_FRAME_LENGTH) {
    throw new Error('iAP2 parameter is too large or has an invalid ID');
  }
  const output = new Uint8Array(PARAMETER_HEADER_LENGTH + value.length);
  writeU16(output, 0, output.length);
  writeU16(output, 2, id);
  output.set(value, PARAMETER_HEADER_LENGTH);
  return output;
}

export function scanIap2Control(bytes: Uint8Array): Iap2ScanResult {
  let offset = 0;
  while (offset + 1 < bytes.length) {
    if (bytes[offset] !== 0x40 || bytes[offset + 1] !== 0x40) {
      offset++;
      continue;
    }
    if (bytes.length - offset < CONTROL_HEADER_LENGTH) {
      return { consumed: offset, frameOffset: 0, frameLength: 0 };
    }
    const frameLength = readU16(bytes, offset + 2);
    if (frameLength < CONTROL_HEADER_LENGTH) {
      offset++;
      continue;
    }
    if (bytes.length - offset < frameLength) {
      return { consumed: offset, frameOffset: 0, frameLength: 0 };
    }
    return { consumed: offset + frameLength, frameOffset: offset, frameLength };
  }
  return { consumed: Math.max(0, bytes.length - 1), frameOffset: 0, frameLength: 0 };
}

export function decodeIap2Parameters(bytes: Uint8Array): Iap2Parameter[] {
  const parameters: Iap2Parameter[] = [];
  let offset = 0;
  while (offset < bytes.length) {
    if (bytes.length - offset < PARAMETER_HEADER_LENGTH) {
      throw new Error('Truncated iAP2 parameter header');
    }
    const length = readU16(bytes, offset);
    if (length < PARAMETER_HEADER_LENGTH || length > bytes.length - offset) {
      throw new Error('Invalid iAP2 parameter length');
    }
    parameters.push({
      id: readU16(bytes, offset + 2),
      value: bytes.slice(offset + PARAMETER_HEADER_LENGTH, offset + length)
    });
    offset += length;
  }
  return parameters;
}
