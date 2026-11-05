import util from '@ohos.util';
import nativeIap2Codec from 'libiap2codec.so';
import { formatRawByteBlock } from './RawByteFormatter';

export interface NativeIap2Codec {
  encodeLink(control: number, sequence: number, acknowledgement: number, session: number,
    payload: Uint8Array): Uint8Array;
  scanLink(bytes: Uint8Array): number[];
  encodeControl(messageId: number, body: Uint8Array): Uint8Array;
  encodeParameter(id: number, value: Uint8Array): Uint8Array;
  scanControl(bytes: Uint8Array): number[];
  parseParameters(bytes: Uint8Array): number[];
  encodeTlv8(types: Uint8Array, values: Uint8Array[]): Uint8Array;
  decodeTlv8(bytes: Uint8Array): NativeTlv8DecodeResult;
}

export interface NativeTlv8DecodeResult {
  ranges: Uint32Array;
  values: Uint8Array;
}

let nativeCodec = nativeIap2Codec as NativeIap2Codec;

// Host unit tests cannot load an OpenHarmony shared library; device builds use the native codec.
export function setIap2CodecForHostTests(codec: NativeIap2Codec): void {
  nativeCodec = codec;
}

export interface Iap2ControlFrame {
  messageId: number;
  body: Uint8Array;
}

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

const MAX_DIAGNOSTIC_BYTES: number = 2048;
const MAX_RAW_FRAME_DIAGNOSTIC_BYTES: number = 16 * 1024;

export function formatIap2MessageDiagnostic(direction: string, messageId: number, body: Uint8Array): string {
  const prefix = `iAP2 ${direction} CSM id=0x${messageId.toString(16).padStart(4, '0')} body=${body.length}B`;
  if (messageId >= 0xaa00 && messageId <= 0xaa06) {
    let parameters = 'unparsed';
    try {
      parameters = decodeIap2Parameters(body)
        .map((parameter: Iap2Parameter): string => `${parameter.id}:${parameter.value.length}B`)
        .join(',') || 'none';
    } catch (_error) {
      parameters = 'malformed';
    }
    return `${prefix} params=[${parameters}] data=[REDACTED:MFi]`;
  }
  if (messageId === 0x5703) {
    try {
      const parameters = decodeIap2Parameters(body).map((parameter: Iap2Parameter): string => {
        if (parameter.id === 2) {
          return `p${parameter.id}:${parameter.value.length}B=[REDACTED:Wi-Fi password]`;
        }
        return `p${parameter.id}:${parameter.value.length}B=${formatDiagnosticHex(parameter.value)}`;
      });
      return `${prefix} params=[${parameters.join('; ')}]`;
    } catch (_error) {
      return `${prefix} params=[malformed; contents redacted]`;
    }
  }
  if (messageId === 0x4301) {
    try {
      const parameters = decodeIap2Parameters(body).map((parameter: Iap2Parameter): string => {
        if (parameter.id !== 1) {
          return `p${parameter.id}:${parameter.value.length}B=${formatDiagnosticHex(parameter.value)}`;
        }
        try {
          const children = decodeIap2Parameters(parameter.value).map((child: Iap2Parameter): string => {
            if (child.id === 1) {
              return `p${child.id}:${child.value.length}B=[REDACTED:Wi-Fi passphrase]`;
            }
            return `p${child.id}:${child.value.length}B=${formatDiagnosticHex(child.value)}`;
          });
          return `group${parameter.id}=[${children.join('; ')}]`;
        } catch (_error) {
          return `group${parameter.id}:${parameter.value.length}B=[REDACTED:malformed]`;
        }
      });
      return `${prefix} params=[${parameters.join('; ')}]`;
    } catch (_error) {
      return `${prefix} params=[malformed; contents redacted]`;
    }
  }
  return `${prefix} hex=${formatDiagnosticHex(body)}`;
}

export function formatIap2LinkPayloadDiagnostic(direction: string, payload: Uint8Array): string {
  if (payload.length === 0) {
    return 'empty';
  }
  if (payload[0] !== 0x40 || payload[1] !== 0x40) {
    return formatDiagnosticHex(payload);
  }
  const messages: string[] = [];
  let offset = 0;
  while (offset < payload.length) {
    if (offset + 6 > payload.length || payload[offset] !== 0x40 || payload[offset + 1] !== 0x40) {
      return `malformed CSM payload; remainingBytes=${payload.length - offset}; contents redacted`;
    }
    const length = readU16(payload, offset + 2);
    if (length < 6 || offset + length > payload.length) {
      return `incomplete CSM payload; remainingBytes=${payload.length - offset}; contents redacted`;
    }
    const messageId = readU16(payload, offset + 4);
    messages.push(formatIap2MessageDiagnostic(direction, messageId, payload.slice(offset + 6, offset + length)));
    offset += length;
  }
  return messages.join(' | ');
}

export function formatIap2RawFrameDiagnostic(
  direction: string,
  frame: Iap2LinkFrame,
  includeMarker: boolean = false
): string {
  const encoded = frame.raw?.slice() ?? encodeIap2LinkFrame(frame);
  const raw = includeMarker
    ? concatBytes(new Uint8Array([0xff, 0x55, 0x02, 0x00, 0xee, 0x10]), encoded)
    : encoded;
  const payloadStart = Math.max(0, raw.length - frame.payload.length - (frame.payload.length > 0 ? 1 : 0));
  const masked = new Set<number>();
  if ((frame.control & 0x80) === 0 && (frame.control & 0x20) === 0 && frame.payload.length > 0 &&
    (frame.payload[0] !== 0x40 || frame.payload[1] !== 0x40)) {
    for (let index = 0; index < frame.payload.length; index++) masked.add(payloadStart + index);
  }
  let offset = 0;
  while (offset < frame.payload.length && frame.payload[offset] === 0x40 && frame.payload[offset + 1] === 0x40) {
    if (offset + 6 > frame.payload.length) {
      for (let index = offset; index < frame.payload.length; index++) masked.add(payloadStart + index);
      break;
    }
    const messageLength = readU16(frame.payload, offset + 2);
    if (messageLength < 6) {
      for (let index = offset + 4; index < frame.payload.length; index++) masked.add(payloadStart + index);
      break;
    }
    const messageId = readU16(frame.payload, offset + 4);
    const bodyStart = offset + 6;
    const bodyEnd = offset + messageLength;
    if (bodyEnd > frame.payload.length) {
      for (let index = bodyStart; index < frame.payload.length; index++) masked.add(payloadStart + index);
      break;
    }
    if (messageId >= 0xaa00 && messageId <= 0xaa06) {
      for (let index = bodyStart; index < bodyEnd; index++) {
        masked.add(payloadStart + index);
      }
    } else if (messageId === 0x5703 || messageId === 0x4301) {
      try {
        addSensitiveParameterRanges(frame.payload, bodyStart, bodyEnd, messageId, payloadStart, masked);
      } catch (_error) {
        for (let index = bodyStart; index < bodyEnd; index++) {
          masked.add(payloadStart + index);
        }
      }
    }
    offset += messageLength;
  }
  const maskedBytes = new Uint8Array(raw.length);
  for (const index of masked) {
    if (index >= 0 && index < maskedBytes.length) {
      maskedBytes[index] = 1;
    }
  }
  return formatRawByteBlock(direction, 'iAP2', raw, MAX_RAW_FRAME_DIAGNOSTIC_BYTES, maskedBytes);
}

function addSensitiveParameterRanges(
  bytes: Uint8Array,
  start: number,
  end: number,
  messageId: number,
  payloadStart: number,
  masked: Set<number>
): void {
  let offset = start;
  while (offset + 4 <= end) {
    const length = readU16(bytes, offset);
    if (length < 4 || offset + length > end) {
      throw new Error('Malformed iAP2 parameter length');
    }
    const parameterId = readU16(bytes, offset + 2);
    const valueStart = offset + 4;
    const valueEnd = offset + length;
    if (messageId === 0x5703 && parameterId === 2) {
      for (let index = valueStart; index < valueEnd; index++) {
        masked.add(payloadStart + index);
      }
    } else if (messageId === 0x4301 && parameterId === 1) {
      let childOffset = valueStart;
      while (childOffset + 4 <= valueEnd) {
        const childLength = readU16(bytes, childOffset);
        if (childLength < 4 || childOffset + childLength > valueEnd) {
          throw new Error('Malformed iAP2 wireless-group parameter length');
        }
        if (readU16(bytes, childOffset + 2) === 1) {
          for (let index = childOffset + 4; index < childOffset + childLength; index++) {
            masked.add(payloadStart + index);
          }
        }
        childOffset += childLength;
      }
    }
    offset += length;
  }
  if (offset !== end) {
    throw new Error('Trailing bytes in iAP2 parameter body');
  }
}

function formatDiagnosticHex(bytes: Uint8Array): string {
  const displayedLength = Math.min(bytes.length, MAX_DIAGNOSTIC_BYTES);
  let value = '';
  for (let index = 0; index < displayedLength; index++) {
    if (index > 0) {
      value += ' ';
    }
    value += (bytes[index] ?? 0).toString(16).padStart(2, '0');
  }
  if (displayedLength < bytes.length) {
    value += ` ... (${bytes.length - displayedLength} bytes omitted)`;
  }
  return value || 'empty';
}

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

export function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const result = new Uint8Array(bytes.length);
  result.set(bytes);
  return result.buffer;
}

export function encodeUtf8(value: string): Uint8Array {
  return util.TextEncoder.create('utf-8').encodeInto(value);
}

export function decodeUtf8(value: Uint8Array): string {
  return util.TextDecoder.create('utf-8').decodeToString(value);
}

export function readU16(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] << 8) | bytes[offset + 1];
}

function writeU16(bytes: Uint8Array, offset: number, value: number): void {
  bytes[offset] = (value >>> 8) & 0xff;
  bytes[offset + 1] = value & 0xff;
}

export function encodeIap2Control(messageId: number, body: Uint8Array = new Uint8Array(0)): Uint8Array {
  if (messageId < 0 || messageId > 0xffff || body.length + 6 > 0xffff) {
    throw new Error('iAP2 control frame is too large or has an invalid message ID');
  }
  return nativeCodec.encodeControl(messageId & 0xffff, body);
}

export function encodeIap2Parameter(id: number, value: Uint8Array): Uint8Array {
  if (id < 0 || id > 0xffff || value.length + 4 > 0xffff) {
    throw new Error('iAP2 parameter is too large or has an invalid ID');
  }
  return nativeCodec.encodeParameter(id & 0xffff, value);
}

export function encodeTlv8Native(types: Uint8Array, values: Uint8Array[]): Uint8Array {
  return nativeCodec.encodeTlv8(types, values);
}

export function decodeTlv8Native(bytes: Uint8Array): NativeTlv8DecodeResult {
  return nativeCodec.decodeTlv8(bytes);
}

export function stringParameter(id: number, value: string): Uint8Array {
  if (value.indexOf('\0') >= 0) {
    throw new Error('iAP2 strings cannot contain a NUL character');
  }
  return encodeIap2Parameter(id, concatBytes(encodeUtf8(value), new Uint8Array([0])));
}

export function numberParameter(id: number, value: number, width: 1 | 2 | 4): Uint8Array {
  const bytes = new Uint8Array(width);
  for (let index = width - 1; index >= 0; index--) {
    bytes[index] = value & 0xff;
    value = Math.floor(value / 256);
  }
  return encodeIap2Parameter(id, bytes);
}

export function groupedParameter(id: number, children: Uint8Array[]): Uint8Array {
  return encodeIap2Parameter(id, concatBytes(...children));
}

export function decodeIap2Parameters(bytes: Uint8Array): Iap2Parameter[] {
  const parameters: Iap2Parameter[] = [];
  const entries = nativeCodec.parseParameters(bytes);
  for (let index = 0; index < entries.length; index += 3) {
    const offset = entries[index + 1];
    const length = entries[index + 2];
    const parameter: Iap2Parameter = {
      id: entries[index],
      value: bytes.slice(offset, offset + length)
    };
    parameters.push(parameter);
  }
  return parameters;
}

export function decodeIap2String(value: Uint8Array): string {
  let end = value.indexOf(0);
  if (end < 0) {
    end = value.length;
  }
  return decodeUtf8(value.slice(0, end));
}

export function encodeIap2LinkFrame(frame: Iap2LinkFrame): Uint8Array {
  return nativeCodec.encodeLink(frame.control & 0xff, frame.sequence & 0xff,
    frame.acknowledgement & 0xff, frame.sessionId & 0xff, frame.payload);
}

export class Iap2LinkDecoder {
  private buffer: Uint8Array = new Uint8Array(0);

  push(chunk: Uint8Array, onEvent?: (frame: Iap2LinkFrame | undefined) => void): Iap2LinkFrame[] {
    if (chunk.length + this.buffer.length > 1024 * 1024) {
      this.buffer = new Uint8Array(0);
      throw new Error('iAP2 link input exceeded the 1 MiB safety limit');
    }
    this.buffer = concatBytes(this.buffer, chunk);
    const frames: Iap2LinkFrame[] = [];
    const marker = new Uint8Array([0xff, 0x55, 0x02, 0x00, 0xee, 0x10]);
    while (true) {
      if (this.buffer.length === 0) {
        break;
      }
      const prefixLength = Math.min(this.buffer.length, marker.length);
      if (marker.slice(0, prefixLength).every((value: number, index: number): boolean =>
        value === this.buffer[index])) {
        if (this.buffer.length < marker.length) {
          break;
        }
        this.buffer = this.buffer.slice(marker.length);
        onEvent?.(undefined);
        continue;
      }
      const scan = nativeCodec.scanLink(this.buffer);
      const consumed = scan[0];
      const start = scan[1];
      const length = scan[2];
      if (start > 0 || (length === 0 && consumed > 0)) {
        const skipLength = length === 0 ? consumed : start;
        let nextMarker = skipLength;
        for (let index = 1; index < skipLength; index++) {
          if (this.buffer[index] === 0xff && this.buffer[index + 1] === 0x55) {
            nextMarker = index;
            break;
          }
        }
        this.buffer = this.buffer.slice(nextMarker);
        continue;
      }
      if (length === 0) {
        this.buffer = this.buffer.slice(consumed);
        break;
      }
      const raw = this.buffer.slice(start, start + length);
      const frame: Iap2LinkFrame = {
        control: raw[4],
        sequence: raw[5],
        acknowledgement: raw[6],
        sessionId: raw[7],
        payload: raw.slice(9, length - 1),
        raw
      };
      frames.push(frame);
      this.buffer = this.buffer.slice(consumed);
      onEvent?.(frame);
    }
    return frames;
  }
}

export function encodeIap2SyncPayload(controlSessionId: number = 10): Uint8Array {
  const sessions = new Uint8Array([
    controlSessionId & 0xff, 0x00, 0x02,
    (controlSessionId + 1) & 0xff, 0x02, 0x01,
    (controlSessionId + 2) & 0xff, 0x01, 0x02
  ]);
  const header = new Uint8Array(10);
  header[0] = 1;
  header[1] = 4;
  writeU16(header, 2, 1024);
  writeU16(header, 4, 4000);
  writeU16(header, 6, 4000);
  header[8] = 4;
  header[9] = 4;
  return concatBytes(header, sessions);
}

export class Iap2ControlDecoder {
  private buffer: Uint8Array = new Uint8Array(0);

  push(chunk: Uint8Array): Iap2ControlFrame[] {
    if (chunk.length + this.buffer.length > 1024 * 1024) {
      this.buffer = new Uint8Array(0);
      throw new Error('iAP2 control input exceeded the 1 MiB safety limit');
    }
    this.buffer = concatBytes(this.buffer, chunk);
    const frames: Iap2ControlFrame[] = [];
    while (true) {
      const scan = nativeCodec.scanControl(this.buffer);
      const consumed = scan[0];
      const start = scan[1];
      const length = scan[2];
      if (length === 0) {
        this.buffer = this.buffer.slice(consumed);
        break;
      }
      const frame: Iap2ControlFrame = {
        messageId: readU16(this.buffer, start + 4),
        body: this.buffer.slice(start + 6, start + length)
      };
      frames.push(frame);
      this.buffer = this.buffer.slice(consumed);
    }
    return frames;
  }
}
