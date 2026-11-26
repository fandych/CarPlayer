import util from '@ohos.util';
import { encodeUtf8 } from '../protocol/Iap2Codec';
import { PlistNode } from './PlistNode';

interface DecodedLength {
  length: number;
  cursor: number;
}

export class BinaryPlistDecoder {
  static decode(bytes: Uint8Array): PlistNode {
      if (bytes.length < 40 || !BinaryPlistDecoder.hasHeader(bytes)) {
        throw new Error('Invalid or truncated bplist00 data');
      }
      const trailer = bytes.length - 32;
      const offsetSize = bytes[trailer + 6];
      const referenceSize = bytes[trailer + 7];
      const objectCount = toSafeNumber(readUnsigned(bytes, trailer + 8, 8), 'object count');
      const topObject = toSafeNumber(readUnsigned(bytes, trailer + 16, 8), 'root object');
      const offsetTable = toSafeNumber(readUnsigned(bytes, trailer + 24, 8), 'offset table');
      if (offsetSize < 1 || offsetSize > 8 || referenceSize < 1 || referenceSize > 8 ||
        objectCount < 1 || objectCount > 100000 || topObject >= objectCount ||
        offsetTable < 8 || offsetTable + objectCount * offsetSize > trailer) {
        throw new Error('Invalid bplist00 trailer');
      }
  
      const offsets: number[] = [];
      for (let index = 0; index < objectCount; index++) {
        const offset = toSafeNumber(readUnsigned(bytes, offsetTable + index * offsetSize, offsetSize), 'object offset');
        if (offset < 8 || offset >= offsetTable) {
          throw new Error(`Invalid bplist00 object offset ${offset}`);
        }
        offsets.push(offset);
      }
      const cache: Map<number, PlistNode> = new Map<number, PlistNode>();
      return BinaryPlistDecoder.decodeObject(bytes, offsets, referenceSize, objectCount, topObject, offsetTable, cache, 0);
    }

  private static hasHeader(bytes: Uint8Array): boolean {
      const header = encodeUtf8('bplist00');
      for (let index = 0; index < header.length; index++) {
        if (bytes[index] !== header[index]) {
          return false;
        }
      }
      return true;
    }

  private static decodeObject(
      bytes: Uint8Array,
      offsets: number[],
      referenceSize: number,
      objectCount: number,
      reference: number,
      objectLimit: number,
      cache: Map<number, PlistNode>,
      depth: number
    ): PlistNode {
      if (reference < 0 || reference >= objectCount || depth > 100) {
        throw new Error('Invalid or excessively nested bplist00 object reference');
      }
      const cached = cache.get(reference);
      if (cached) {
        return cached;
      }
      let cursor = offsets[reference];
      const marker = bytes[cursor];
      cursor++;
      const type = marker >>> 4;
      const info = marker & 0x0f;
      if (type === 0) {
        if (info === 0x00) {
          return PlistNode.nullValue();
        }
        if (info === 0x08) {
          return PlistNode.boolean(false);
        }
        if (info === 0x09) {
          return PlistNode.boolean(true);
        }
        throw new Error(`Unsupported bplist00 simple marker 0x${marker.toString(16)}`);
      }
      if (type === 1) {
        const size = 1 << info;
        if (cursor + size > objectLimit) {
          throw new Error('Truncated bplist00 integer');
        }
        const value = size < 8 ? readUnsigned(bytes, cursor, size) : readSigned(bytes, cursor, size);
        return PlistNode.integer(value);
      }
      if (type === 2) {
        const size = 1 << info;
        if (size !== 4 && size !== 8) {
          throw new Error(`Unsupported bplist00 real width ${size}`);
        }
        if (cursor + size > objectLimit) {
          throw new Error('Truncated bplist00 real');
        }
        const view = new DataView(bytes.buffer, bytes.byteOffset + cursor, size);
        return PlistNode.real(size === 4 ? view.getFloat32(0, false) : view.getFloat64(0, false));
      }
      if (type === 3) {
        if (info !== 3 || cursor + 8 > objectLimit) {
          throw new Error('Invalid bplist00 date');
        }
        const view = new DataView(bytes.buffer, bytes.byteOffset + cursor, 8);
        return PlistNode.real(view.getFloat64(0, false));
      }
      if (type === 4 || type === 5 || type === 6 || type === 7 || type === 8) {
        const lengthInfo = BinaryPlistDecoder.decodeLength(bytes, cursor, info, objectLimit);
        cursor = lengthInfo.cursor;
        const length = lengthInfo.length;
        if (type === 8) {
          if (length < 1 || length > 8) {
            throw new Error('Unsupported bplist00 UID width');
          }
          return PlistNode.integer(readUnsigned(bytes, cursor, length));
        }
        const byteLength = type === 6 ? length * 2 : length;
        if (cursor + byteLength > objectLimit) {
          throw new Error('Truncated bplist00 scalar object');
        }
        const value = bytes.slice(cursor, cursor + byteLength);
        if (type === 4) {
          return PlistNode.data(value);
        }
        if (type === 5) {
          return PlistNode.string(util.TextDecoder.create('utf-8').decodeToString(value));
        }
        if (type === 7) {
          return PlistNode.string(util.TextDecoder.create('utf-8').decodeToString(value));
        }
        return PlistNode.string(decodeUtf16Be(value));
      }
      if (type === 0x0a || type === 0x0c || type === 0x0d) {
        const lengthInfo = BinaryPlistDecoder.decodeLength(bytes, cursor, info, objectLimit);
        cursor = lengthInfo.cursor;
        const count = lengthInfo.length;
        const referenceCount = type === 0x0d ? count * 2 : count;
        if (cursor + referenceCount * referenceSize > objectLimit) {
          throw new Error('Truncated bplist00 collection');
        }
        if (type === 0x0d) {
          const dictionary = PlistNode.dictionary(new Map<string, PlistNode>());
          cache.set(reference, dictionary);
          const keyRefs: number[] = [];
          const valueRefs: number[] = [];
          for (let index = 0; index < count; index++) {
            keyRefs.push(toSafeNumber(readUnsigned(bytes, cursor + index * referenceSize, referenceSize), 'key reference'));
            valueRefs.push(toSafeNumber(readUnsigned(bytes, cursor + (count + index) * referenceSize, referenceSize), 'value reference'));
          }
          for (let index = 0; index < count; index++) {
            const keyNode = BinaryPlistDecoder.decodeObject(bytes, offsets, referenceSize, objectCount, keyRefs[index], objectLimit, cache, depth + 1);
            if (keyNode.kind !== 'string') {
              throw new Error('bplist00 dictionary key is not a string');
            }
            const valueNode = BinaryPlistDecoder.decodeObject(bytes, offsets, referenceSize, objectCount, valueRefs[index], objectLimit, cache, depth + 1);
            dictionary.dictionaryValue.set(keyNode.stringValue, valueNode);
          }
          return dictionary;
        }
        const array = PlistNode.array([]);
        cache.set(reference, array);
        for (let index = 0; index < count; index++) {
          const childRef = toSafeNumber(readUnsigned(bytes, cursor + index * referenceSize, referenceSize), 'array reference');
          array.arrayValue.push(BinaryPlistDecoder.decodeObject(bytes, offsets, referenceSize, objectCount, childRef, objectLimit, cache, depth + 1));
        }
        return array;
      }
      throw new Error(`Unsupported bplist00 object type ${type}`);
    }

  private static decodeLength(
      bytes: Uint8Array,
      cursor: number,
      info: number,
      objectLimit: number
    ): DecodedLength {
      if (info < 15) {
        const result: DecodedLength = { length: info, cursor };
        return result;
      }
      if (cursor >= objectLimit) {
        throw new Error('Missing bplist00 extended length');
      }
      const marker = bytes[cursor];
      if ((marker >>> 4) !== 1) {
        throw new Error('bplist00 extended length is not an integer');
      }
      const size = 1 << (marker & 0x0f);
      if (cursor + 1 + size > objectLimit) {
        throw new Error('Truncated bplist00 extended length');
      }
      const length = toSafeNumber(readUnsigned(bytes, cursor + 1, size), 'object length');
      const result: DecodedLength = { length, cursor: cursor + 1 + size };
      return result;
    }
}

function readUnsigned(bytes: Uint8Array, offset: number, width: number): bigint {
  if (width < 1 || width > 16 || offset < 0 || offset + width > bytes.length) {
    throw new Error('Invalid bplist00 integer range');
  }
  let value = BigInt(0);
  for (let index = 0; index < width; index++) {
    value = (value << BigInt(8)) | BigInt(bytes[offset + index]);
  }
  return value;
}

function readSigned(bytes: Uint8Array, offset: number, width: number): bigint {
  const unsigned = readUnsigned(bytes, offset, width);
  const signBit = BigInt(1) << BigInt(width * 8 - 1);
  return (unsigned & signBit) !== BigInt(0)
    ? unsigned - (BigInt(1) << BigInt(width * 8))
    : unsigned;
}

function toSafeNumber(value: bigint, description: string): number {
  if (value < BigInt(0) || value > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new Error(`bplist00 ${description} is out of range`);
  }
  return Number(value);
}

function decodeUtf16Be(bytes: Uint8Array): string {
  if (bytes.length % 2 !== 0) {
    throw new Error('Invalid UTF-16BE bplist00 string');
  }
  let value = '';
  for (let index = 0; index < bytes.length; index += 2) {
    value += String.fromCharCode((bytes[index] << 8) | bytes[index + 1]);
  }
  return value;
}
