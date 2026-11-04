import cert from '@ohos.security.cert';
import { encodeUtf8 } from '../../protocol/Iap2Codec';
import { DerTlv, derSequenceHeaderLength, readDerSequenceLength, readDerTlv } from './DerReader';

const MAX_CERTIFICATE_BYTES: number = 1024 * 1024;
const MAX_CHAIN_CERTIFICATES: number = 8;
const PEM_BEGIN: string = '-----BEGIN CERTIFICATE-----';
const PEM_END: string = '-----END CERTIFICATE-----';
const PKCS7_SIGNED_DATA_OID: number[] = [
  0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02
];

export interface MfiCertificateChain {
  leaf: Uint8Array;
  certificates: Uint8Array[];
  serialized: Uint8Array;
  count: number;
  encodingFormat: cert.EncodingFormat;
  encodingName: string;
}

export function isPkcs7SignedDataPayload(input: Uint8Array): boolean {
  if (input.length < 15 || input[0] !== 0x30) {
    return false;
  }
  let sequenceLength: number;
  try {
    sequenceLength = readDerSequenceLength(input, 0);
  } catch (_error) {
    return false;
  }
  const headerLength = derSequenceHeaderLength(input, 0);
  if (headerLength < 0 || sequenceLength !== input.length ||
    headerLength + PKCS7_SIGNED_DATA_OID.length > input.length) {
    return false;
  }
  for (let index = 0; index < PKCS7_SIGNED_DATA_OID.length; index++) {
    if (input[headerLength + index] !== PKCS7_SIGNED_DATA_OID[index]) {
      return false;
    }
  }
  return true;
}

export function extractPkcs7CertificateSet(input: Uint8Array): Uint8Array[] {
  const contentInfo = readDerTlv(input, 0, input.length);
  if (contentInfo.tag !== 0x30 || contentInfo.end !== input.length) {
    throw new Error('CMS ContentInfo is not a bounded DER SEQUENCE');
  }
  const contentType = readDerTlv(input, contentInfo.valueOffset, contentInfo.end);
  if (contentType.tag !== 0x06 || !isSignedDataOid(input, contentType)) {
    throw new Error('CMS ContentInfo does not use the SignedData OID');
  }
  const explicitContent = readDerTlv(input, contentType.end, contentInfo.end);
  if (explicitContent.tag !== 0xa0) {
    throw new Error('CMS ContentInfo is missing its explicit SignedData content');
  }
  const signedData = readDerTlv(input, explicitContent.valueOffset, explicitContent.end);
  if (signedData.tag !== 0x30 || signedData.end !== explicitContent.end) {
    throw new Error('CMS SignedData is not a bounded DER SEQUENCE');
  }

  let cursor = signedData.valueOffset;
  const version = readDerTlv(input, cursor, signedData.end);
  if (version.tag !== 0x02) {
    throw new Error('CMS SignedData has no version field');
  }
  cursor = version.end;
  const digestAlgorithms = readDerTlv(input, cursor, signedData.end);
  if (digestAlgorithms.tag !== 0x31) {
    throw new Error('CMS SignedData has no digestAlgorithms SET');
  }
  cursor = digestAlgorithms.end;
  const encapsulatedContent = readDerTlv(input, cursor, signedData.end);
  if (encapsulatedContent.tag !== 0x30) {
    throw new Error('CMS SignedData has no encapContentInfo SEQUENCE');
  }
  cursor = encapsulatedContent.end;

  while (cursor < signedData.end) {
    const field = readDerTlv(input, cursor, signedData.end);
    if (field.tag === 0xa0) {
      const certificates: Uint8Array[] = [];
      let certOffset = field.valueOffset;
      while (certOffset < field.end) {
        if (certificates.length >= MAX_CHAIN_CERTIFICATES) {
          throw new Error(`CMS certificate set exceeds ${MAX_CHAIN_CERTIFICATES} X.509 certificates`);
        }
        const certificate = readDerTlv(input, certOffset, field.end);
        if (certificate.tag === 0x30) {
          certificates.push(input.slice(certificate.start, certificate.end));
        }
        certOffset = certificate.end;
      }
      return certificates;
    }
    if (field.tag === 0x31) {
      break;
    }
    if (field.tag !== 0xa1) {
      throw new Error(`Unexpected CMS SignedData field tag 0x${field.tag.toString(16)}`);
    }
    cursor = field.end;
  }
  return [];
}

export function parseMfiCertificateChain(input: Uint8Array): MfiCertificateChain {
  if (input.length === 0 || input.length > MAX_CERTIFICATE_BYTES) {
    throw new Error(`MFi certificate payload has invalid size ${input.length}`);
  }
  if (isPkcs7SignedDataPayload(input)) {
    throw new Error('MFi payload is PKCS#7 SignedData; use the CMS parser instead of raw X.509 parsing');
  }
  if (startsWithAscii(input, PEM_BEGIN)) {
    return parsePemCertificateChain(input);
  }
  return parseDerCertificateChain(input);
}

export { readDerTlv };

function isSignedDataOid(input: Uint8Array, oid: DerTlv): boolean {
  if (oid.end - oid.valueOffset !== 9) {
    return false;
  }
  const value: number[] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02];
  for (let index = 0; index < value.length; index++) {
    if (input[oid.valueOffset + index] !== value[index]) {
      return false;
    }
  }
  return true;
}

function parseDerCertificateChain(input: Uint8Array): MfiCertificateChain {
  const certificates: Uint8Array[] = [];
  let cursor = 0;
  while (cursor < input.length) {
    if (certificates.length >= MAX_CHAIN_CERTIFICATES) {
      throw new Error(`MFi DER chain exceeds ${MAX_CHAIN_CERTIFICATES} certificates`);
    }
    const totalLength = readDerSequenceLength(input, cursor);
    certificates.push(input.slice(cursor, cursor + totalLength));
    cursor += totalLength;
  }
  if (certificates.length === 0) {
    throw new Error('MFi DER chain contains no certificate');
  }
  const leaf = certificates[0];
  if (!leaf) {
    throw new Error('MFi DER chain is missing its leaf certificate');
  }
  return {
    leaf,
    certificates,
    serialized: input.slice(),
    count: certificates.length,
    encodingFormat: cert.EncodingFormat.FORMAT_DER,
    encodingName: 'DER'
  };
}

function parsePemCertificateChain(input: Uint8Array): MfiCertificateChain {
  const text = decodeAscii(input);
  const certificates: Uint8Array[] = [];
  let cursor = 0;
  while (cursor < text.length) {
    while (cursor < text.length && isAsciiWhitespace(text.charCodeAt(cursor))) {
      cursor++;
    }
    if (cursor >= text.length) {
      break;
    }
    if (certificates.length >= MAX_CHAIN_CERTIFICATES || !text.startsWith(PEM_BEGIN, cursor)) {
      throw new Error(`MFi PEM chain has invalid certificate framing at character ${cursor}`);
    }
    const end = text.indexOf(PEM_END, cursor + PEM_BEGIN.length);
    if (end < 0) {
      throw new Error('MFi PEM certificate is missing its END marker');
    }
    const blockEnd = end + PEM_END.length;
    certificates.push(encodeUtf8(`${text.slice(cursor, blockEnd)}\n`));
    cursor = blockEnd;
  }
  if (certificates.length === 0) {
    throw new Error('MFi PEM chain contains no certificates');
  }
  const first = certificates[0];
  if (!first) {
    throw new Error('MFi PEM chain is missing its leaf certificate');
  }
  return {
    leaf: first,
    certificates,
    serialized: input.slice(),
    count: certificates.length,
    encodingFormat: cert.EncodingFormat.FORMAT_PEM,
    encodingName: 'PEM'
  };
}

function startsWithAscii(input: Uint8Array, prefix: string): boolean {
  if (input.length < prefix.length) {
    return false;
  }
  for (let index = 0; index < prefix.length; index++) {
    if (input[index] !== prefix.charCodeAt(index)) {
      return false;
    }
  }
  return true;
}

function decodeAscii(input: Uint8Array): string {
  let value = '';
  for (const byte of input) {
    if (byte > 0x7f) {
      throw new Error('MFi PEM payload contains non-ASCII bytes');
    }
    value += String.fromCharCode(byte);
  }
  return value;
}

function isAsciiWhitespace(code: number): boolean {
  return code === 9 || code === 10 || code === 13 || code === 32;
}
