export interface Tlv8Item {
  type: number;
  value: Uint8Array;
}

const TLV8_SEPARATOR: number = 0xff;
const MAX_TLV8_FRAGMENT: number = 0xff;
const MAX_TLV8_BYTES: number = 1024 * 1024;

export function encodeTlv8(items: Tlv8Item[]): Uint8Array {
  let encodedLength = 0;
  for (let index = 0; index < items.length; index++) {
    const item = items[index];
    if (!Number.isInteger(item.type) || item.type < 0 || item.type >= 0xff) {
      throw new Error(`Invalid TLV8 type ${item.type}`);
    }
    if (item.value.length > MAX_TLV8_BYTES) {
      throw new Error('TLV8 value exceeds the 1 MiB size limit');
    }
    if (index > 0 && item.type === items[index - 1].type) {
      encodedLength += 2;
    }
    encodedLength += Math.max(1, Math.ceil(item.value.length / MAX_TLV8_FRAGMENT)) * 2 + item.value.length;
    if (encodedLength > MAX_TLV8_BYTES) {
      throw new Error('TLV8 message exceeds the 1 MiB size limit');
    }
  }
  const encoded = new Uint8Array(encodedLength);
  let offset = 0;
  for (let index = 0; index < items.length; index++) {
    const item = items[index];
    if (index > 0 && item.type === items[index - 1].type) {
      encoded[offset++] = TLV8_SEPARATOR;
      encoded[offset++] = 0;
    }
    if (item.value.length === 0) {
      encoded[offset++] = item.type;
      encoded[offset++] = 0;
      continue;
    }
    let valueOffset = 0;
    while (valueOffset < item.value.length) {
      const length = Math.min(MAX_TLV8_FRAGMENT, item.value.length - valueOffset);
      encoded[offset++] = item.type;
      encoded[offset++] = length;
      encoded.set(item.value.subarray(valueOffset, valueOffset + length), offset);
      offset += length;
      valueOffset += length;
    }
  }
  return encoded;
}

export function decodeTlv8(bytes: Uint8Array): Map<number, Uint8Array> {
  if (bytes.length > MAX_TLV8_BYTES) {
    throw new Error('TLV8 message exceeds the 1 MiB size limit');
  }
  const values: Map<number, Uint8Array> = new Map<number, Uint8Array>();
  let offset = 0;
  let previousType = -1;
  let previousLength = 0;
  let separatorSeen = false;
  while (offset < bytes.length) {
    if (bytes.length - offset < 2) {
      throw new Error('Malformed TLV8 item header');
    }
    const type = bytes[offset];
    const length = bytes[offset + 1];
    const valueOffset = offset + 2;
    if (length > bytes.length - valueOffset || (type === TLV8_SEPARATOR && length !== 0)) {
      throw new Error('Malformed TLV8 item length');
    }
    if (type === TLV8_SEPARATOR) {
      previousType = -1;
      previousLength = 0;
      separatorSeen = true;
      offset = valueOffset;
      continue;
    }
    const continuation = previousType === type && previousLength === MAX_TLV8_FRAGMENT && !separatorSeen;
    if (continuation) {
      const previous = values.get(type);
      if (previous === undefined) {
        throw new Error('Malformed TLV8 continuation');
      }
      const combined = new Uint8Array(previous.length + length);
      combined.set(previous);
      combined.set(bytes.subarray(valueOffset, valueOffset + length), previous.length);
      values.set(type, combined);
    } else {
      values.set(type, bytes.slice(valueOffset, valueOffset + length));
    }
    previousType = type;
    previousLength = length;
    separatorSeen = false;
    offset = valueOffset + length;
  }
  return values;
}

export interface Tlv8TypeIds {
  METHOD: number;
  IDENTIFIER: number;
  SALT: number;
  PUBLIC_KEY: number;
  PROOF: number;
  ENCRYPTED_DATA: number;
  STATE: number;
  ERROR: number;
  SIGNATURE: number;
}

export const Tlv8Type: Tlv8TypeIds = {
  METHOD: 0x00,
  IDENTIFIER: 0x01,
  SALT: 0x02,
  PUBLIC_KEY: 0x03,
  PROOF: 0x04,
  ENCRYPTED_DATA: 0x05,
  STATE: 0x06,
  ERROR: 0x07,
  SIGNATURE: 0x0a
};
