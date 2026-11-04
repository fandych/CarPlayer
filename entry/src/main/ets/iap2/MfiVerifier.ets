import cert from '@ohos.security.cert';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { p256 } from '@noble/curves/p256';
import type { VerOpts } from '@noble/curves/abstract/weierstrass';
import { decodeUtf8, encodeUtf8 } from '../protocol/Iap2Codec';
import { DerTlv, readDerTlv } from './mfi/DerReader';
import {
  MfiCertificateChain,
  extractPkcs7CertificateSet,
  isPkcs7SignedDataPayload,
  parseMfiCertificateChain
} from './mfi/MfiCertificateParser';

export {
  MfiCertificateChain,
  extractPkcs7CertificateSet,
  isPkcs7SignedDataPayload,
  parseMfiCertificateChain
} from './mfi/MfiCertificateParser';

export interface MfiTrustCandidate {
  certificate: cert.X509Cert;
  trustSource: 'system-pkix' | 'user-pinned';
  fingerprintToPersist: string;
}

export interface MfiTrustPromptInfo {
  fingerprint: string;
  subject: string;
  issuer: string;
  pkixFailure: string;
}

export interface ValidatedMfiCertificate {
  candidates: MfiTrustCandidate[];
  certificateCount: number;
  encodingName: string;
}

export type MfiPkixTrustDecision = 'prompt-for-pin' | 'already-pinned' | 'reject';

export function classifyMfiPkixTrustFailure(
  message: string,
  fingerprint: string,
  pinnedFingerprints: string[]
): MfiPkixTrustDecision {
  if (!isMfiPinEligiblePkixFailure(message)) {
    return 'reject';
  }
  const normalized = fingerprint.toLowerCase();
  return pinnedFingerprints.some((pin: string): boolean => pin.toLowerCase() === normalized)
    ? 'already-pinned'
    : 'prompt-for-pin';
}

export interface MfiSignatureVerificationResult {
  verified: boolean;
  algorithm: string;
  errors: string[];
}

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

async function importMfiCertificatePublicKey(certificate: cert.X509Cert): Promise<ImportedMfiPublicKey> {
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

export class MfiVerifier {
  private readonly log: (message: string) => void;
  private readonly allowIntermediateDownload: boolean;
  private readonly pinnedFingerprints: string[];
  private readonly requestTrust?: (info: MfiTrustPromptInfo) => Promise<boolean>;
  private readonly persistFingerprint?: (fingerprint: string) => Promise<void>;
  private readonly skipChallengeSignatureVerification: boolean;

  constructor(
    log: (message: string) => void,
    allowIntermediateDownload: boolean = false,
    pinnedFingerprints: string[] = [],
    requestTrust?: (info: MfiTrustPromptInfo) => Promise<boolean>,
    persistFingerprint?: (fingerprint: string) => Promise<void>,
    skipChallengeSignatureVerification: boolean = false
  ) {
    this.log = log;
    this.allowIntermediateDownload = allowIntermediateDownload;
    this.pinnedFingerprints = pinnedFingerprints.map((value: string): string => value.toLowerCase());
    this.requestTrust = requestTrust;
    this.persistFingerprint = persistFingerprint;
    this.skipChallengeSignatureVerification = skipChallengeSignatureVerification;
  }

  canContinueAfterChallengeVerification(verified: boolean): boolean {
    return verified || this.skipChallengeSignatureVerification;
  }

  async validateAccessoryCertificate(certificatePayload: Uint8Array): Promise<ValidatedMfiCertificate> {
    if (certificatePayload.length === 0) {
      throw new Error('MFi certificate payload is empty');
    }
    const isCmsPayload = isPkcs7SignedDataPayload(certificatePayload);
    this.log(
      `MFi certificate validation started: payloadBytes=${certificatePayload.length}, ` +
        `container=${isCmsPayload ? 'PKCS#7 SignedData' : 'X.509 certificate chain'}`
    );
    this.log(
      `MFi AA01 parameter 0 received: bytes=${certificatePayload.length}`
    );
    let candidateCertificates: cert.X509Cert[] = [];
    let untrustedCertificates: cert.X509Cert[] = [];
    let encodingName: string = '';
    let serializedChain: Uint8Array = certificatePayload;
    if (isCmsPayload) {
      const parser = cert.createCmsParser();
      try {
        await parser.setRawData(certificatePayload, cert.CmsFormat.DER);
        if (parser.getContentType() !== cert.CmsContentType.SIGNED_DATA) {
          throw new Error('CMS ContentInfo is not SignedData');
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        throw new Error(`MFi PKCS#7 SignedData parsing failed: ${message}`);
      }
      let allCertificateError = '';
      let signerCertificateError = '';
      let certificateSetError = '';
      let contentDataError = '';
      try {
        untrustedCertificates = await parser.getCerts(cert.CmsCertType.ALL_CERTS);
      } catch (error) {
        allCertificateError = error instanceof Error ? error.message : String(error);
        this.log(`CMS getCerts(ALL_CERTS) failed: ${allCertificateError}`);
      }
      let signerCertificates: cert.X509Cert[] = [];
      try {
        signerCertificates = await parser.getCerts(cert.CmsCertType.SIGNER_CERTS);
      } catch (error) {
        signerCertificateError = error instanceof Error ? error.message : String(error);
        this.log(`CMS getCerts(SIGNER_CERTS) failed: ${signerCertificateError}`);
      }
      if (untrustedCertificates.length === 0) {
        let extracted: Uint8Array[] = [];
        try {
          extracted = extractPkcs7CertificateSet(certificatePayload);
        } catch (error) {
          certificateSetError = error instanceof Error ? error.message : String(error);
          this.log(`CMS certificate-set ASN.1 fallback failed: ${certificateSetError}`);
        }
        if (extracted.length > 0) {
          for (const encodedCertificate of extracted) {
            try {
              untrustedCertificates.push(await cert.createX509Cert({
                data: encodedCertificate,
                encodingFormat: cert.EncodingFormat.FORMAT_DER
              }));
            } catch (error) {
              const message = error instanceof Error ? error.message : String(error);
              throw new Error(`MFi CMS certificate-set X.509 parse failed: ${message}`);
            }
          }
          this.log(`CMS certificate-set ASN.1 fallback extracted ${untrustedCertificates.length} certificate(s)`);
        }
      }
      if (untrustedCertificates.length === 0 && signerCertificates.length > 0) {
        untrustedCertificates = signerCertificates;
        this.log('CMS all-certificates extraction unavailable; using signer certificate(s) as chain input');
      }
      if (untrustedCertificates.length === 0 && signerCertificates.length === 0) {
        let contentData = new Uint8Array(0);
        try {
          contentData = await parser.getContentData();
        } catch (error) {
          contentDataError = error instanceof Error ? error.message : String(error);
        }
        if (contentData.length > 0) {
          let embeddedChain: MfiCertificateChain;
          try {
            embeddedChain = parseMfiCertificateChain(contentData);
          } catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            throw new Error(
              `MFi CMS contains no signer certificate; embedded content is not an X.509 chain: ${message}; ` +
                `ALL_CERTS=${allCertificateError || 'empty'}, SIGNER_CERTS=${signerCertificateError || 'empty'}`
            );
          }
          encodingName = `PKCS#7 SignedData/${embeddedChain.encodingName} content`;
          serializedChain = embeddedChain.serialized;
          for (const encodedCertificate of embeddedChain.certificates) {
            try {
              untrustedCertificates.push(await cert.createX509Cert({
                data: encodedCertificate,
                encodingFormat: embeddedChain.encodingFormat
              }));
            } catch (error) {
              const message = error instanceof Error ? error.message : String(error);
              throw new Error(`MFi CMS embedded certificate parse failed: ${message}`);
            }
          }
          const leafCertificate = untrustedCertificates[0];
          if (!leafCertificate) {
            throw new Error('MFi CMS embedded certificate chain has no leaf certificate');
          }
          candidateCertificates = [leafCertificate];
        }
      }
      if (untrustedCertificates.length === 0) {
        throw new Error(
          `MFi CMS certificate extraction failed: ALL_CERTS=${allCertificateError || 'empty'}, ` +
            `SIGNER_CERTS=${signerCertificateError || 'empty'}, ` +
            `certificate-set=${certificateSetError || 'empty'}, ` +
            `getContentData=${contentDataError || 'not required'}`
        );
      }
      if (candidateCertificates.length === 0) {
        candidateCertificates = signerCertificates.length > 0
          ? signerCertificates
          : untrustedCertificates;
      }
      if (!encodingName) {
        encodingName = 'PKCS#7 SignedData';
      }
    } else {
      let chain: MfiCertificateChain;
      try {
        chain = parseMfiCertificateChain(certificatePayload);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        throw new Error(`MFi certificate payload format is invalid or unsupported: ${message}`);
      }
      encodingName = chain.encodingName;
      serializedChain = chain.serialized;
      for (const encodedCertificate of chain.certificates) {
        try {
          untrustedCertificates.push(await cert.createX509Cert({
            data: encodedCertificate,
            encodingFormat: chain.encodingFormat
          }));
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          throw new Error(
            `MFi certificate parse failed (${chain.encodingName}, ${encodedCertificate.length} bytes, ` +
              `certificateIndex=${untrustedCertificates.length}): ${message}`
          );
        }
      }
      const leafCertificate = untrustedCertificates[0];
      if (!leafCertificate) {
        throw new Error('MFi certificate chain has no leaf certificate');
      }
      candidateCertificates = [leafCertificate];
    }

    const fingerprint = await sha256Fingerprint(serializedChain);
    this.log(
      `MFi certificate payload parsed: format=${encodingName}, bytes=${serializedChain.length}, ` +
        `certificates=${untrustedCertificates.length}, sha256=${fingerprint}`
    );
    const validationTime = toAsn1Time(new Date());
    const validationParams: cert.CertValidationParams = {
      untrustedCerts: untrustedCertificates,
      trustSystemCa: true,
      date: validationTime,
      validateDate: true,
      allowDownloadIntermediateCa: this.allowIntermediateDownload,
      keyUsage: [cert.KeyUsageType.KEYUSAGE_DIGITAL_SIGNATURE]
    };
    this.log(
      `MFi PKIX uses system CA; AIA intermediate download ${this.allowIntermediateDownload ? 'enabled' : 'disabled'}`
    );
    this.log(
      `MFi PKIX validation started: candidates=${candidateCertificates.length}, ` +
        `untrustedCertificates=${untrustedCertificates.length}, validationTime=${validationTime}`
    );
    const validator = cert.createCertChainValidator('PKIX');
    const trustedCandidates: MfiTrustCandidate[] = [];
    const validationErrors: string[] = [];
    for (let index = 0; index < candidateCertificates.length; index++) {
      const item = candidateCertificates[index];
      if (!item) {
        continue;
      }
      this.log(`MFi PKIX candidate ${index}: ${certificateNames(item)}`);
      try {
        await validator.validateCert(item, validationParams);
        trustedCandidates.push({
          certificate: item,
          trustSource: 'system-pkix',
          fingerprintToPersist: ''
        });
      } catch (error) {
        const pkixFailure = error instanceof Error ? error.message : String(error);
        this.log(`MFi PKIX candidate ${index} rejected: ${pkixFailure}`);
        if (!isMfiPinEligiblePkixFailure(pkixFailure)) {
          validationErrors.push(formatPkixFailure(index, pkixFailure, this.allowIntermediateDownload));
          continue;
        }
        const fingerprint = await x509Fingerprint(item);
        const trustDecision = classifyMfiPkixTrustFailure(
          pkixFailure,
          fingerprint,
          this.pinnedFingerprints
        );
        this.log(
          `MFi PKIX trust decision: candidate=${index}, decision=${trustDecision}, fingerprint=${fingerprint}`
        );
        if (trustDecision === 'already-pinned') {
          this.validateUserPinnedCertificateValidity(item, validationTime);
          trustedCandidates.push({
            certificate: item,
            trustSource: 'user-pinned',
            fingerprintToPersist: ''
          });
          this.log(`MFi certificate accepted by exact user-pinned SHA-256 fingerprint ${fingerprint}`);
          continue;
        }
        const prompt = this.requestTrust;
        if (!prompt) {
          validationErrors.push(formatPkixFailure(index, pkixFailure, this.allowIntermediateDownload));
          continue;
        }
        const identity = certificateIdentity(item);
        this.log(`MFi first-use trust prompt opened: subject=${identity.subject}, issuer=${identity.issuer}`);
        const approved = await prompt({
          fingerprint,
          subject: identity.subject,
          issuer: identity.issuer,
          pkixFailure: formatPkixFailure(index, pkixFailure, this.allowIntermediateDownload)
        });
        if (!approved) {
          this.log(`MFi first-use trust prompt declined: fingerprint=${fingerprint}`);
          throw new Error(`MFi certificate trust declined for SHA-256 ${fingerprint}`);
        }
        this.log(`MFi first-use trust prompt approved: fingerprint=${fingerprint}`);
        this.validateUserPinnedCertificateValidity(item, validationTime);
        trustedCandidates.push({
          certificate: item,
          trustSource: 'user-pinned',
          fingerprintToPersist: fingerprint
        });
        this.log(
          `User approved first-use MFi fingerprint ${fingerprint}; challenge signature verification follows ` +
            `the current diagnostics setting`
        );
      }
    }
    if (trustedCandidates.length === 0) {
      throw new Error(
        `MFi PKIX validation failed against the system CA (${untrustedCertificates.length} certificate(s), ` +
          `date=${validationTime}, AIA download=${this.allowIntermediateDownload})` +
          `${validationErrors.length > 0 ? `: ${validationErrors.join('; ')}` : ''}` +
          `${this.allowIntermediateDownload ? '' : '; enable optional AIA lookup only for a trusted receiver'}`
      );
    }

    return {
      candidates: trustedCandidates,
      certificateCount: untrustedCertificates.length,
      encodingName
    };
  }

  private validateUserPinnedCertificateValidity(certificate: cert.X509Cert, validationTime: string): void {
    try {
      certificate.checkValidityWithDate(validationTime);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      throw new Error(
        `User-pinned MFi leaf failed certificate validity-date check; not saved or accepted: ${message}`
      );
    }
  }

  async verifyChallenge(validated: ValidatedMfiCertificate, challenge: Uint8Array, signature: Uint8Array):
    Promise<boolean> {
    if (challenge.length === 0 || signature.length === 0) {
      throw new Error('MFi challenge and signature are required');
    }
    this.log(
      `MFi challenge verification started: challengeBytes=${challenge.length}, ` +
        `signatureBytes=${signature.length}, candidates=${validated.candidates.length}`
    );
    if (this.skipChallengeSignatureVerification) {
      this.log(
        'WARN TEMPORARY DIAGNOSTIC BYPASS: MFi challenge signature NOT verified; ' +
          'continuing without authentication and without saving a fingerprint pin'
      );
      return false;
    }
    const errors: string[] = [];
    for (let index = 0; index < validated.candidates.length; index++) {
      const candidate = validated.candidates[index];
      if (!candidate) {
        continue;
      }
      const certificate = candidate.certificate;
      const importedKey = await importMfiCertificatePublicKey(certificate);
      this.log(
        `MFi challenge candidate ${index}: public key imported; keyAlgorithm=${importedKey.algorithm}, ` +
          `source=${candidate.trustSource}`
      );
      const verification = await verifyMfiChallengeAndPersistPin(
        importedKey.keyPair.pubKey,
        challenge,
        signature,
        candidate.fingerprintToPersist,
        this.persistFingerprint,
        this.log
      );
      if (!verification.verified) {
        errors.push(
          `certificate ${index}: no supported challenge signature verified` +
            `${verification.errors.length > 0 ? ` [${verification.errors.join('; ')}]` : ''}`
        );
        continue;
      }
      if (candidate.fingerprintToPersist.length > 0) {
        this.log('MFi fingerprint pinned after successful challenge signature');
      }
      this.log(
        `MFi ${validated.encodingName} ${candidate.trustSource} ` +
          `(${validated.certificateCount} certificate(s)); ` +
          `challenge verified using ${verification.algorithm}`
      );
      return true;
    }
    throw new Error(
      `MFi challenge signature verification failed against ${validated.candidates.length} trusted candidate(s)` +
        `${errors.length > 0 ? ` (${errors.join('; ')})` : ''}`
    );
  }

  async verifyAccessory(certificatePayload: Uint8Array, challenge: Uint8Array, signature: Uint8Array):
    Promise<void> {
    const validated = await this.validateAccessoryCertificate(certificatePayload);
    await this.verifyChallenge(validated, challenge, signature);
  }
}

interface MfiCertificateIdentity {
  subject: string;
  issuer: string;
}

function certificateIdentity(certificate: cert.X509Cert): MfiCertificateIdentity {
  try {
    const subjectBlob = certificate.getSubjectName(cert.EncodingType.ENCODING_UTF8);
    const subject = decodeUtf8(new Uint8Array(subjectBlob.data)).replace(/\0/g, '').slice(0, 240);
    const issuer = certificate.getIssuerName(cert.EncodingType.ENCODING_UTF8).slice(0, 240);
    return { subject, issuer };
  } catch (error) {
    const failure = error instanceof Error ? error.message : String(error);
    return { subject: `unavailable (${failure})`, issuer: 'unavailable' };
  }
}

function certificateNames(certificate: cert.X509Cert): string {
  const identity = certificateIdentity(certificate);
  return `subject=${identity.subject}; issuer=${identity.issuer}`;
}

export function isMfiPinEligiblePkixFailure(message: string): boolean {
  return message.includes('unable to get local issuer certificate') ||
    message.includes('No AIA extension found in certificate') ||
    message.includes('Failed to obtain the certificate issuer') ||
    message.toLowerCase().includes('untrusted certificate');
}

async function x509Fingerprint(certificate: cert.X509Cert): Promise<string> {
  const encoded = await certificate.getEncoded();
  if (encoded.encodingFormat !== cert.EncodingFormat.FORMAT_DER) {
    throw new Error(`X.509 getEncoded returned unsupported format ${encoded.encodingFormat}`);
  }
  return sha256Fingerprint(encoded.data);
}

function formatPkixFailure(index: number, error: Error | string, aiaEnabled: boolean): string {
  const message = error instanceof Error ? error.message : String(error);
  if (message.includes('No AIA extension found in certificate') ||
    message.includes('unable to get local issuer certificate')) {
    return `candidate ${index}: issuer chain is incomplete; the leaf has no usable AIA issuer URL ` +
      `(${aiaEnabled ? 'AIA lookup enabled but no URL was present' : 'AIA lookup disabled'}). ` +
      'Supply the authentic Apple Accessories intermediate certificate; the system CA must still trust its root. ' +
      `System detail: ${message}`;
  }
  return `candidate ${index}: ${message}`;
}

function toAsn1Time(date: Date): string {
  const year = date.getUTCFullYear();
  const yearText = year >= 2050
    ? year.toString().padStart(4, '0')
    : (year % 100).toString().padStart(2, '0');
  return yearText +
    (date.getUTCMonth() + 1).toString().padStart(2, '0') +
    date.getUTCDate().toString().padStart(2, '0') +
    date.getUTCHours().toString().padStart(2, '0') +
    date.getUTCMinutes().toString().padStart(2, '0') +
    date.getUTCSeconds().toString().padStart(2, '0') +
    'Z';
}

async function sha256Fingerprint(input: Uint8Array): Promise<string> {
  try {
    const digest = cryptoFramework.createMd('SHA256');
    await digest.update({ data: input });
    const result = await digest.digest();
    let fingerprint = '';
    for (const byte of result.data) {
      fingerprint += byte.toString(16).padStart(2, '0');
    }
    return fingerprint;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Unable to compute MFi certificate diagnostic fingerprint: ${message}`);
  }
}
