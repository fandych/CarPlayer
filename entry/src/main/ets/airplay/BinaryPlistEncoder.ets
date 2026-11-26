import { concatBytes, encodeUtf8 } from '../protocol/Iap2Codec';
import { PlistNode } from './PlistNode';

export class BinaryPlistEncoder {
  static encode(root: PlistNode): Uint8Array {
      const objects: Uint8Array[] = [];
      const rootIndex = BinaryPlistEncoder.encodeObject(root, objects);
      if (rootIndex !== 0) {
        throw new Error('Internal bplist00 root reference error');
      }
      const referenceSize: number = 4;
      const offsets: number[] = [];
      let objectBytes = 8;
      for (let index = 0; index < objects.length; index++) {
        offsets.push(objectBytes);
        objectBytes += objects[index].length;
      }
      const offsetSize = widthForUnsigned(BigInt(objectBytes));
      const offsetTableOffset = objectBytes;
      const totalLength = offsetTableOffset + objects.length * offsetSize + 32;
      const output = new Uint8Array(totalLength);
      output.set(encodeUtf8('bplist00'), 0);
      let cursor = 8;
      for (const object of objects) {
        output.set(object, cursor);
        cursor += object.length;
      }
      for (let index = 0; index < offsets.length; index++) {
        writeUnsigned(output, offsetTableOffset + index * offsetSize, offsetSize, BigInt(offsets[index]));
      }
      const trailer = totalLength - 32;
      output[trailer + 6] = offsetSize;
      output[trailer + 7] = referenceSize;
      writeUnsigned(output, trailer + 8, 8, BigInt(objects.length));
      writeUnsigned(output, trailer + 16, 8, BigInt(rootIndex));
      writeUnsigned(output, trailer + 24, 8, BigInt(offsetTableOffset));
      return output;
    }

  private static encodeObject(value: PlistNode, objects: Uint8Array[]): number {
      const index = objects.length;
      objects.push(new Uint8Array(0));
      if (value.kind === 'dictionary') {
        const keys: string[] = [];
        const values: PlistNode[] = [];
        value.dictionaryValue.forEach((item: PlistNode, key: string): void => {
          keys.push(key);
          values.push(item);
        });
        const keyRefs: number[] = [];
        const valueRefs: number[] = [];
        for (const key of keys) {
          keyRefs.push(BinaryPlistEncoder.encodeObject(PlistNode.string(key), objects));
        }
        for (const item of values) {
          valueRefs.push(BinaryPlistEncoder.encodeObject(item, objects));
        }
        objects[index] = encodeCollection(0xd0, keyRefs.concat(valueRefs), keys.length);
        return index;
      }
      if (value.kind === 'array') {
        const refs: number[] = [];
        for (const item of value.arrayValue) {
          refs.push(BinaryPlistEncoder.encodeObject(item, objects));
        }
        objects[index] = encodeCollection(0xa0, refs, refs.length);
        return index;
      }
      objects[index] = encodeScalar(value);
      return index;
    }
}

function encodeScalar(value: PlistNode): Uint8Array {
  if (value.kind === 'null') {
    return new Uint8Array([0x00]);
  }
  if (value.kind === 'boolean') {
    return new Uint8Array([value.boolValue ? 0x09 : 0x08]);
  }
  if (value.kind === 'integer') {
    return encodeInteger(value.integerValue);
  }
  if (value.kind === 'real') {
    const bytes = new Uint8Array(9);
    bytes[0] = 0x23;
    new DataView(bytes.buffer).setFloat64(1, value.realValue, false);
    return bytes;
  }
  if (value.kind === 'data') {
    return concatBytes(encodeLengthPrefix(0x40, value.dataValue.length), value.dataValue);
  }
  if (value.kind === 'string') {
    const isAscii = isAsciiString(value.stringValue);
    if (isAscii) {
      const data = encodeUtf8(value.stringValue);
      return concatBytes(encodeLengthPrefix(0x50, data.length), data);
    }
    const data = encodeUtf16Be(value.stringValue);
    return concatBytes(encodeLengthPrefix(0x60, value.stringValue.length), data);
  }
  throw new Error(`Unsupported bplist00 scalar kind ${value.kind}`);
}

function encodeCollection(marker: number, refs: number[], count: number): Uint8Array {
  const referenceSize: number = 4;
  const bytes: Uint8Array[] = [encodeLengthPrefix(marker, count)];
  for (const reference of refs) {
    bytes.push(encodeUnsigned(BigInt(reference), referenceSize));
  }
  return concatBytes(...bytes);
}

function encodeInteger(value: bigint): Uint8Array {
  const signed64Max = (BigInt(1) << BigInt(63)) - BigInt(1);
  const signed64Min = -(BigInt(1) << BigInt(63));
  if (value < signed64Min || value > signed64Max) {
    throw new Error('bplist00 integer exceeds the signed 64-bit encoder range');
  }
  const width = value < BigInt(0) ? 8 : widthForUnsigned(value);
  const unsigned = value < BigInt(0) ? (BigInt(1) << BigInt(width * 8)) + value : value;
  const header: Uint8Array = new Uint8Array([0x10 | log2(width)]);
  return concatBytes(header, encodeUnsigned(unsigned, width));
}

function encodeLengthPrefix(marker: number, count: number): Uint8Array {
  if (count < 15) {
    return new Uint8Array([marker | count]);
  }
  const lengthInteger = encodeInteger(BigInt(count));
  return concatBytes(new Uint8Array([marker | 0x0f]), lengthInteger);
}

function widthForUnsigned(value: bigint): number {
  if (value <= BigInt(0xff)) return 1;
  if (value <= BigInt(0xffff)) return 2;
  if (value <= BigInt(0xffffffff)) return 4;
  return 8;
}

function encodeUnsigned(value: bigint, width: number): Uint8Array {
  const bytes = new Uint8Array(width);
  let remaining = value;
  for (let index = width - 1; index >= 0; index--) {
    bytes[index] = Number(remaining & BigInt(0xff));
    remaining >>= BigInt(8);
  }
  return bytes;
}

function writeUnsigned(target: Uint8Array, offset: number, width: number, value: bigint): void {
  target.set(encodeUnsigned(value, width), offset);
}

function log2(width: number): number {
  if (width === 1) return 0;
  if (width === 2) return 1;
  if (width === 4) return 2;
  if (width === 8) return 3;
  throw new Error(`Unsupported bplist00 integer width ${width}`);
}

function isAsciiString(value: string): boolean {
  for (let index = 0; index < value.length; index++) {
    if (value.charCodeAt(index) > 0x7f) return false;
  }
  return true;
}

function encodeUtf16Be(value: string): Uint8Array {
  const bytes = new Uint8Array(value.length * 2);
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    bytes[index * 2] = (code >>> 8) & 0xff;
    bytes[index * 2 + 1] = code & 0xff;
  }
  return bytes;
}
