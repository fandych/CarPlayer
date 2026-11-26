import util from '@ohos.util';
import {
  concatBytes,
  encodeIap2Parameter,
  Iap2LinkFrame,
  readU16,
  scanIap2Control,
  scanIap2Link
} from './Iap2FrameCodec';

export {
  concatBytes,
  decodeIap2Parameters,
  encodeIap2Control,
  encodeIap2LinkFrame,
  encodeIap2Parameter,
  Iap2LinkFrame,
  Iap2Parameter,
  readU16
} from './Iap2FrameCodec';
export {
  formatIap2LinkPayloadDiagnostic,
  formatIap2MessageDiagnostic,
  formatIap2RawFrameDiagnostic
} from './Iap2Diagnostics';

export interface Iap2ControlFrame {
  messageId: number;
  body: Uint8Array;
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

function writeU16(bytes: Uint8Array, offset: number, value: number): void {
  bytes[offset] = (value >>> 8) & 0xff;
  bytes[offset + 1] = value & 0xff;
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
    while (this.buffer.length > 0) {
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
      const scan = scanIap2Link(this.buffer);
      if (scan.frameOffset > 0 || (scan.frameLength === 0 && scan.consumed > 0)) {
        const skipLength = scan.frameLength === 0 ? scan.consumed : scan.frameOffset;
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
      if (scan.frameLength === 0) {
        this.buffer = this.buffer.slice(scan.consumed);
        break;
      }
      const raw = this.buffer.slice(scan.frameOffset, scan.frameOffset + scan.frameLength);
      const frame: Iap2LinkFrame = {
        control: raw[4],
        sequence: raw[5],
        acknowledgement: raw[6],
        sessionId: raw[7],
        payload: raw.slice(9, scan.frameLength - 1),
        raw
      };
      frames.push(frame);
      this.buffer = this.buffer.slice(scan.consumed);
      onEvent?.(frame);
    }
    return frames;
  }
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
      const scan = scanIap2Control(this.buffer);
      if (scan.frameLength === 0) {
        this.buffer = this.buffer.slice(scan.consumed);
        break;
      }
      frames.push({
        messageId: readU16(this.buffer, scan.frameOffset + 4),
        body: this.buffer.slice(scan.frameOffset + 6, scan.frameOffset + scan.frameLength)
      });
      this.buffer = this.buffer.slice(scan.consumed);
    }
    return frames;
  }
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

export function decodeIap2String(value: Uint8Array): string {
  let end = value.indexOf(0);
  if (end < 0) {
    end = value.length;
  }
  return decodeUtf8(value.slice(0, end));
}
