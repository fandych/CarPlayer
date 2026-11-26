import { formatRawByteBlock } from './RawByteFormatter';
import {
  concatBytes,
  decodeIap2Parameters,
  encodeIap2LinkFrame,
  Iap2LinkFrame,
  Iap2Parameter,
  readU16
} from './Iap2FrameCodec';

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
        return parameter.id === 2
          ? `p${parameter.id}:${parameter.value.length}B=[REDACTED:Wi-Fi password]`
          : `p${parameter.id}:${parameter.value.length}B=${formatDiagnosticHex(parameter.value)}`;
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
            return child.id === 1
              ? `p${child.id}:${child.value.length}B=[REDACTED:Wi-Fi passphrase]`
              : `p${child.id}:${child.value.length}B=${formatDiagnosticHex(child.value)}`;
          });
          return `group${parameter.id}=[${children.join('; ')}]`;
        } catch (_error) {
          return `group${parameter.id}:${parameter.value.length}B=[REDACTED]`;
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
    messages.push(formatIap2MessageDiagnostic(
      direction, readU16(payload, offset + 4), payload.slice(offset + 6, offset + length)
    ));
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
  const addRange = (start: number, end: number): void => {
    for (let index = start; index < end; index++) {
      masked.add(payloadStart + index);
    }
  };
  if ((frame.control & 0x80) === 0 && (frame.control & 0x20) === 0 && frame.payload.length > 0 &&
    (frame.payload[0] !== 0x40 || frame.payload[1] !== 0x40)) {
    addRange(0, frame.payload.length);
  }
  let offset = 0;
  while (offset < frame.payload.length && frame.payload[offset] === 0x40 && frame.payload[offset + 1] === 0x40) {
    if (offset + 6 > frame.payload.length) {
      addRange(offset, frame.payload.length);
      break;
    }
    const messageLength = readU16(frame.payload, offset + 2);
    if (messageLength < 6) {
      addRange(offset + 4, frame.payload.length);
      break;
    }
    const messageId = readU16(frame.payload, offset + 4);
    const bodyStart = offset + 6;
    const bodyEnd = offset + messageLength;
    if (bodyEnd > frame.payload.length) {
      addRange(bodyStart, frame.payload.length);
      break;
    }
    if (messageId >= 0xaa00 && messageId <= 0xaa06) {
      addRange(bodyStart, bodyEnd);
    } else if (messageId === 0x5703 || messageId === 0x4301) {
      try {
        addSensitiveParameterRanges(frame.payload, bodyStart, bodyEnd, messageId, payloadStart, masked);
      } catch (_error) {
        addRange(bodyStart, bodyEnd);
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
      if (childOffset !== valueEnd) {
        throw new Error('Trailing bytes in iAP2 wireless-group parameter body');
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
  const parts: string[] = [];
  for (let index = 0; index < displayedLength; index++) {
    parts.push((bytes[index] ?? 0).toString(16).padStart(2, '0'));
  }
  if (displayedLength < bytes.length) {
    parts.push(`... (${bytes.length - displayedLength} bytes omitted)`);
  }
  return parts.join(' ') || 'empty';
}
