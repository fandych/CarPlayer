export interface DerTlv {
  tag: number;
  start: number;
  valueOffset: number;
  end: number;
}

export function readDerTlv(input: Uint8Array, offset: number, limit: number): DerTlv {
  if (offset < 0 || offset + 2 > limit || limit > input.length) {
    throw new Error(`Truncated DER tag/length at offset ${offset}`);
  }
  const tag = input[offset];
  if (tag === undefined || (tag & 0x1f) === 0x1f) {
    throw new Error(`Unsupported DER tag at offset ${offset}`);
  }
  const firstLength = input[offset + 1];
  if (firstLength === undefined) {
    throw new Error(`Missing DER length at offset ${offset + 1}`);
  }
  let headerLength = 2;
  let contentLength = firstLength;
  if (firstLength >= 0x80) {
    const lengthBytes = firstLength & 0x7f;
    if (lengthBytes === 0 || lengthBytes > 4 || offset + 2 + lengthBytes > limit) {
      throw new Error(`Invalid DER length encoding at offset ${offset + 1}`);
    }
    if (input[offset + 2] === 0) {
      throw new Error(`Non-canonical DER length at offset ${offset + 2}`);
    }
    contentLength = 0;
    for (let index = 0; index < lengthBytes; index++) {
      contentLength = contentLength * 256 + (input[offset + 2 + index] ?? 0);
    }
    if (contentLength < 0x80) {
      throw new Error(`Non-canonical DER long-form length at offset ${offset + 1}`);
    }
    headerLength += lengthBytes;
  }
  const valueOffset = offset + headerLength;
  const end = valueOffset + contentLength;
  if (!Number.isSafeInteger(end) || end > limit) {
    throw new Error(`DER element exceeds its container at offset ${offset}`);
  }
  const result: DerTlv = { tag, start: offset, valueOffset, end };
  return result;
}

export function readDerSequenceLength(input: Uint8Array, offset: number): number {
  if (offset + 2 > input.length || input[offset] !== 0x30) {
    throw new Error(`MFi certificate payload is not a DER SEQUENCE at offset ${offset}`);
  }
  const firstLength = input[offset + 1];
  if (firstLength === undefined) {
    throw new Error('MFi DER sequence is missing its length');
  }
  if (firstLength < 0x80) {
    const totalLength = 2 + firstLength;
    if (offset + totalLength > input.length) {
      throw new Error('MFi DER sequence length exceeds the payload');
    }
    return totalLength;
  }
  const lengthBytes = firstLength & 0x7f;
  if (lengthBytes === 0 || lengthBytes > 4 || offset + 2 + lengthBytes > input.length) {
    throw new Error(`MFi DER sequence has invalid length encoding (${lengthBytes} length bytes)`);
  }
  if (input[offset + 2] === 0) {
    throw new Error('MFi DER sequence uses a non-canonical leading zero length');
  }
  let contentLength = 0;
  for (let index = 0; index < lengthBytes; index++) {
    contentLength = contentLength * 256 + (input[offset + 2 + index] ?? 0);
  }
  if (contentLength < 0x80) {
    throw new Error('MFi DER sequence uses a non-canonical long-form length');
  }
  const headerLength = 2 + lengthBytes;
  const totalLength = headerLength + contentLength;
  if (offset + totalLength > input.length || !Number.isSafeInteger(totalLength)) {
    throw new Error('MFi DER sequence length exceeds the payload bounds');
  }
  return totalLength;
}

export function derSequenceHeaderLength(input: Uint8Array, offset: number): number {
  if (offset + 2 > input.length || input[offset] !== 0x30) {
    return -1;
  }
  const firstLength = input[offset + 1];
  if (firstLength === undefined) {
    return -1;
  }
  if (firstLength < 0x80) {
    return 2;
  }
  const lengthBytes = firstLength & 0x7f;
  if (lengthBytes === 0 || lengthBytes > 4 || offset + 2 + lengthBytes > input.length) {
    return -1;
  }
  return 2 + lengthBytes;
}
