import cert from '@ohos.security.cert';

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

export interface MfiSignatureVerificationResult {
  verified: boolean;
  algorithm: string;
  errors: string[];
}
