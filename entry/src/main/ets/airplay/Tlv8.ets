import { decodeTlv8Native, encodeTlv8Native } from '../protocol/Iap2Codec';

export interface Tlv8Item {
  type: number;
  value: Uint8Array;
}

export function encodeTlv8(items: Tlv8Item[]): Uint8Array {
  const types = new Uint8Array(items.length);
  const values: Uint8Array[] = [];
  for (const item of items) {
    if (!Number.isInteger(item.type) || item.type < 0 || item.type >= 0xff) {
      throw new Error(`Invalid TLV8 type ${item.type}`);
    }
    types[values.length] = item.type;
    values.push(item.value);
  }
  return encodeTlv8Native(types, values);
}

export function decodeTlv8(bytes: Uint8Array): Map<number, Uint8Array> {
  const values: Map<number, Uint8Array> = new Map<number, Uint8Array>();
  const decoded = decodeTlv8Native(bytes);
  const entries = decoded.ranges;
  for (let index = 0; index < entries.length; index += 3) {
    const type = entries[index];
    const valueOffset = entries[index + 1];
    const length = entries[index + 2];
    if (type === undefined || valueOffset === undefined || length === undefined) {
      throw new Error('Native TLV8 decoder returned an incomplete item');
    }
    values.set(type, decoded.values.slice(valueOffset, valueOffset + length));
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
