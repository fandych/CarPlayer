import cert from '@ohos.security.cert';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { p256 } from '@noble/curves/p256';
import type { VerOpts } from '@noble/curves/abstract/weierstrass';
import { DerTlv, readDerTlv } from './mfi/DerReader';
import { sha256Fingerprint } from './MfiCertificateSupport';
import { MfiSignatureVerificationResult } from './MfiVerifierTypes';

const MFI_CHALLENGE_SIGNATURE_ALGORITHMS: string[] = [
  'RSA|PKCS1|SHA256',
  'RSA|PKCS1|SHA1',
  'ECC|SHA256',
  'ECC|SHA1',
  'Ed25519'
];

interface ImportedMfiPublicKey {
  keyPair: cryptoFramework.KeyPair;
  algorithm: string;
}

interface MfiSubjectPublicKeyInfo {
  data: Uint8Array;
  algorithm: string;
}

function derValueHex(input: Uint8Array, value: DerTlv): string {
  let result = '';
  for (let index = value.valueOffset; index < value.end; index++) {
    const byte = input[index];
    if (byte === undefined) {
      throw new Error(`Truncated DER value at offset ${index}`);
    }
    result += byte.toString(16).padStart(2, '0');
  }
  return result;
}

function rsaModulusBits(input: Uint8Array, bitString: DerTlv): number {
  if (input[bitString.valueOffset] !== 0) {
    throw new Error('MFi RSA SubjectPublicKeyInfo has unsupported bit alignment');
  }
  const rsaKey = readDerTlv(input, bitString.valueOffset + 1, bitString.end);
  if (rsaKey.tag !== 0x30) {
    throw new Error('MFi RSA public key is not a DER SEQUENCE');
  }
  const modulus = readDerTlv(input, rsaKey.valueOffset, rsaKey.end);
  if (modulus.tag !== 0x02) {
    throw new Error('MFi RSA public key is missing its modulus');
  }
  let firstByteOffset = modulus.valueOffset;
  while (firstByteOffset < modulus.end && input[firstByteOffset] === 0) {
    firstByteOffset++;
  }
  const firstByte = input[firstByteOffset];
  if (firstByte === undefined) {
    throw new Error('MFi RSA public key has an empty modulus');
  }
  let leadingBits = 0;
  for (let value = firstByte; value > 0; value >>= 1) {
    leadingBits++;
  }
  return (modulus.end - firstByteOffset - 1) * 8 + leadingBits;
}

function readMfiSubjectPublicKeyInfo(certificateDer: Uint8Array): MfiSubjectPublicKeyInfo {
  const certificate = readDerTlv(certificateDer, 0, certificateDer.length);
  if (certificate.tag !== 0x30 || certificate.end !== certificateDer.length) {
    throw new Error('MFi certificate is not a complete DER SEQUENCE');
  }
  const tbsCertificate = readDerTlv(certificateDer, certificate.valueOffset, certificate.end);
  if (tbsCertificate.tag !== 0x30) {
    throw new Error('MFi certificate is missing TBSCertificate');
  }
  let cursor = tbsCertificate.valueOffset;
  let field = readDerTlv(certificateDer, cursor, tbsCertificate.end);
  if (field.tag === 0xa0) {
    cursor = field.end;
  }
  const precedingTags: number[] = [0x02, 0x30, 0x30, 0x30, 0x30];
  for (const expectedTag of precedingTags) {
    field = readDerTlv(certificateDer, cursor, tbsCertificate.end);
    if (field.tag !== expectedTag) {
      throw new Error(`MFi certificate has an unexpected TBSCertificate field tag ${field.tag}`);
    }
    cursor = field.end;
  }
  const subjectPublicKeyInfo = readDerTlv(certificateDer, cursor, tbsCertificate.end);
  if (subjectPublicKeyInfo.tag !== 0x30) {
    throw new Error('MFi certificate is missing SubjectPublicKeyInfo');
  }
  const algorithmIdentifier = readDerTlv(
    certificateDer,
    subjectPublicKeyInfo.valueOffset,
    subjectPublicKeyInfo.end
  );
  if (algorithmIdentifier.tag !== 0x30) {
    throw new Error('MFi SubjectPublicKeyInfo is missing AlgorithmIdentifier');
  }
  const algorithmOid = readDerTlv(certificateDer, algorithmIdentifier.valueOffset, algorithmIdentifier.end);
  if (algorithmOid.tag !== 0x06) {
    throw new Error('MFi public key AlgorithmIdentifier is missing its OID');
  }
  const oid = derValueHex(certificateDer, algorithmOid);
  let algorithm = '';
  if (oid === '2a864886f70d010101') {
    const bitString = readDerTlv(certificateDer, algorithmIdentifier.end, subjectPublicKeyInfo.end);
    if (bitString.tag !== 0x03) {
      throw new Error('MFi RSA SubjectPublicKeyInfo is missing its public key BIT STRING');
    }
    algorithm = `RSA${rsaModulusBits(certificateDer, bitString)}`;
  } else if (oid === '2a8648ce3d0201') {
    const curveOid = readDerTlv(certificateDer, algorithmOid.end, algorithmIdentifier.end);
    if (curveOid.tag !== 0x06) {
      throw new Error('MFi EC public key is missing its named-curve OID');
    }
    const curves: Record<string, string> = {
      '2a8648ce3d030107': 'ECC256',
      '2b81040021': 'ECC224',
      '2b81040022': 'ECC384',
      '2b81040023': 'ECC521'
    };
    algorithm = curves[derValueHex(certificateDer, curveOid)] ?? '';
  } else if (oid === '2b6570') {
    algorithm = 'Ed25519';
  }
  if (algorithm.length === 0) {
    throw new Error(`Unsupported MFi public key algorithm OID ${oid}`);
  }
  return {
    data: certificateDer.slice(subjectPublicKeyInfo.start, subjectPublicKeyInfo.end),
    algorithm
  };
}

export async function importMfiCertificatePublicKey(certificate: cert.X509Cert): Promise<ImportedMfiPublicKey> {
  const encoded = await certificate.getEncoded();
  if (encoded.encodingFormat !== cert.EncodingFormat.FORMAT_DER) {
    throw new Error(`MFi certificate encoding is not DER: ${encoded.encodingFormat}`);
  }
  const keyData = readMfiSubjectPublicKeyInfo(new Uint8Array(encoded.data));
  const generator = cryptoFramework.createAsyKeyGenerator(keyData.algorithm);
  const publicKeyBlob: cryptoFramework.DataBlob = { data: keyData.data };
  const keyPair = await generator.convertKey(publicKeyBlob, null);
  return { keyPair, algorithm: keyData.algorithm };
}

export function verifyRawMfiP256Signature(
  publicKeyDer: Uint8Array,
  challenge: Uint8Array,
  signature: Uint8Array
): boolean {
  if (challenge.length !== 32 || signature.length !== 64) {
    return false;
  }
  try {
    const spki = readDerTlv(publicKeyDer, 0, publicKeyDer.length);
    if (spki.tag !== 0x30 || spki.end !== publicKeyDer.length) {
      return false;
    }
    const algorithm = readDerTlv(publicKeyDer, spki.valueOffset, spki.end);
    const keyOid = readDerTlv(publicKeyDer, algorithm.valueOffset, algorithm.end);
    const curveOid = readDerTlv(publicKeyDer, keyOid.end, algorithm.end);
    const keyBits = readDerTlv(publicKeyDer, algorithm.end, spki.end);
    if (algorithm.tag !== 0x30 || keyOid.tag !== 0x06 || curveOid.tag !== 0x06 ||
      derValueHex(publicKeyDer, keyOid) !== '2a8648ce3d0201' ||
      derValueHex(publicKeyDer, curveOid) !== '2a8648ce3d030107' ||
      curveOid.end !== algorithm.end || keyBits.tag !== 0x03 || keyBits.end !== spki.end ||
      publicKeyDer[keyBits.valueOffset] !== 0) {
      return false;
    }
    const point = publicKeyDer.slice(keyBits.valueOffset + 1, keyBits.end);
    const options: VerOpts = { lowS: false, prehash: false, format: 'compact' };
    return p256.verify(signature, challenge, point, options);
  } catch (_error) {
    return false;
  }
}

export async function verifyMfiChallengeSignature(
  publicKey: cryptoFramework.PubKey,
  challenge: Uint8Array,
  signature: Uint8Array,
  log?: (message: string) => void
): Promise<MfiSignatureVerificationResult> {
  const inputBlob: cryptoFramework.DataBlob = { data: challenge };
  const signatureBlob: cryptoFramework.DataBlob = { data: signature };
  const errors: string[] = [];
  try {
    if (verifyRawMfiP256Signature(publicKey.getEncoded().data, challenge, signature)) {
      log?.('MFi challenge signature result: algorithm=ECDSA-P256-prehashed, verified=true');
      return { verified: true, algorithm: 'ECDSA-P256-prehashed', errors };
    }
  } catch (error) {
    errors.push(`ECDSA-P256-prehashed: ${error instanceof Error ? error.message : String(error)}`);
  }
  for (const algorithm of MFI_CHALLENGE_SIGNATURE_ALGORITHMS) {
    log?.(`MFi challenge signature attempt: algorithm=${algorithm}`);
    try {
      const verifier = cryptoFramework.createVerify(algorithm);
      await verifier.init(publicKey);
      if (await verifier.verify(inputBlob, signatureBlob)) {
        log?.(`MFi challenge signature result: algorithm=${algorithm}, verified=true`);
        return { verified: true, algorithm, errors };
      }
      log?.(`MFi challenge signature result: algorithm=${algorithm}, verified=false`);
      errors.push(`${algorithm}: signature mismatch`);
    } catch (error) {
      const detail = error instanceof Error
        ? `${error.message}${error.stack ? `\n${error.stack}` : ''}`
        : String(error);
      log?.(`MFi challenge signature attempt failed: algorithm=${algorithm}; ${detail}`);
      errors.push(`${algorithm}: ${detail}`);
    }
  }
  return { verified: false, algorithm: '', errors };
}

export async function verifyMfiChallengeAndPersistPin(
  publicKey: cryptoFramework.PubKey,
  challenge: Uint8Array,
  signature: Uint8Array,
  fingerprintToPersist: string,
  persistFingerprint?: (fingerprint: string) => Promise<void>,
  log?: (message: string) => void
): Promise<MfiSignatureVerificationResult> {
  const result = await verifyMfiChallengeSignature(publicKey, challenge, signature, log);
  if (!result.verified || fingerprintToPersist.length === 0) {
    return result;
  }
  if (!persistFingerprint) {
    throw new Error('MFi pin persistence callback is unavailable; refusing authentication success');
  }
  await persistFingerprint(fingerprintToPersist);
  return result;
}
