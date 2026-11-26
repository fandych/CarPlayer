import {
  MfiTrustPromptInfo,
  ValidatedMfiCertificate
} from './MfiVerifierTypes';
import { importMfiCertificatePublicKey, verifyMfiChallengeAndPersistPin } from './MfiSignatureVerifier';
import { validateMfiAccessoryCertificate } from './MfiCertificateValidator';

export {
  MfiCertificateChain,
  extractPkcs7CertificateSet,
  isPkcs7SignedDataPayload,
  parseMfiCertificateChain
} from './mfi/MfiCertificateParser';
export {
  MfiTrustCandidate,
  MfiTrustPromptInfo,
  MfiPkixTrustDecision,
  MfiSignatureVerificationResult,
  ValidatedMfiCertificate
} from './MfiVerifierTypes';
export {
  classifyMfiPkixTrustFailure,
  isMfiPinEligiblePkixFailure
} from './MfiCertificateSupport';
export {
  verifyMfiChallengeAndPersistPin,
  verifyMfiChallengeSignature,
  verifyRawMfiP256Signature
} from './MfiSignatureVerifier';

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
    return validateMfiAccessoryCertificate(certificatePayload, {
      allowIntermediateDownload: this.allowIntermediateDownload,
      pinnedFingerprints: this.pinnedFingerprints,
      requestTrust: this.requestTrust,
      log: this.log
    });
  }

  async verifyChallenge(
    validated: ValidatedMfiCertificate,
    challenge: Uint8Array,
    signature: Uint8Array
  ): Promise<boolean> {
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
      const importedKey = await importMfiCertificatePublicKey(candidate.certificate);
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
