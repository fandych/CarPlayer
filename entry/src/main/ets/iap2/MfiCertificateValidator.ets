import cert from '@ohos.security.cert';
import { loadMfiCertificatePayload } from './MfiCertificatePayload';
import {
  certificateNames,
  classifyMfiPkixTrustFailure,
  formatPkixFailure,
  isMfiPinEligiblePkixFailure,
  mfiTrustPromptInfo,
  sha256Fingerprint,
  toAsn1Time,
  x509Fingerprint
} from './MfiCertificateSupport';
import { MfiTrustCandidate, MfiTrustPromptInfo, ValidatedMfiCertificate } from './MfiVerifierTypes';

export interface MfiCertificateValidationOptions {
  allowIntermediateDownload: boolean;
  pinnedFingerprints: string[];
  requestTrust?: (info: MfiTrustPromptInfo) => Promise<boolean>;
  log: (message: string) => void;
}

export async function validateMfiAccessoryCertificate(
  certificatePayload: Uint8Array,
  options: MfiCertificateValidationOptions
): Promise<ValidatedMfiCertificate> {
  if (certificatePayload.length === 0) {
    throw new Error('MFi certificate payload is empty');
  }
  const allowIntermediateDownload = options.allowIntermediateDownload;
  const pinnedFingerprints = options.pinnedFingerprints;
  const requestTrust = options.requestTrust;
  const log = options.log;
  const loaded = await loadMfiCertificatePayload(certificatePayload, log);
  const candidateCertificates = loaded.candidateCertificates;
  const untrustedCertificates = loaded.untrustedCertificates;
  const encodingName = loaded.encodingName;
  const serializedChain = loaded.serializedChain;
  const fingerprint = await sha256Fingerprint(serializedChain);
  log(
    `MFi certificate payload parsed: format=${encodingName}, bytes=${serializedChain.length}, ` +
      `certificates=${untrustedCertificates.length}, sha256=${fingerprint}`
  );
  const validationTime = toAsn1Time(new Date());
  const validationParams: cert.CertValidationParams = {
    untrustedCerts: untrustedCertificates,
    trustSystemCa: true,
    date: validationTime,
    validateDate: true,
    allowDownloadIntermediateCa: allowIntermediateDownload,
    keyUsage: [cert.KeyUsageType.KEYUSAGE_DIGITAL_SIGNATURE]
  };
  log(
    `MFi PKIX uses system CA; AIA intermediate download ${allowIntermediateDownload ? 'enabled' : 'disabled'}`
  );
  log(
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
    log(`MFi PKIX candidate ${index}: ${certificateNames(item)}`);
    try {
      await validator.validateCert(item, validationParams);
      trustedCandidates.push({
        certificate: item,
        trustSource: 'system-pkix',
        fingerprintToPersist: ''
      });
    } catch (error) {
      const pkixFailure = error instanceof Error ? error.message : String(error);
      log(`MFi PKIX candidate ${index} rejected: ${pkixFailure}`);
      if (!isMfiPinEligiblePkixFailure(pkixFailure)) {
        validationErrors.push(formatPkixFailure(index, pkixFailure, allowIntermediateDownload));
        continue;
      }
      const certificateFingerprint = await x509Fingerprint(item);
      const trustDecision = classifyMfiPkixTrustFailure(
        pkixFailure,
        certificateFingerprint,
        pinnedFingerprints
      );
      log(
        `MFi PKIX trust decision: candidate=${index}, decision=${trustDecision}, ` +
          `fingerprint=${certificateFingerprint}`
      );
      if (trustDecision === 'already-pinned') {
        validateUserPinnedCertificateValidity(item, validationTime);
        trustedCandidates.push({
          certificate: item,
          trustSource: 'user-pinned',
          fingerprintToPersist: ''
        });
        log(`MFi certificate accepted by exact user-pinned SHA-256 fingerprint ${certificateFingerprint}`);
        continue;
      }
      if (!requestTrust) {
        validationErrors.push(formatPkixFailure(index, pkixFailure, allowIntermediateDownload));
        continue;
      }
      const prompt = mfiTrustPromptInfo(
        item,
        certificateFingerprint,
        formatPkixFailure(index, pkixFailure, allowIntermediateDownload)
      );
      log(`MFi first-use trust prompt opened: subject=${prompt.subject}, issuer=${prompt.issuer}`);
      const approved = await requestTrust(prompt);
      if (!approved) {
        log(`MFi first-use trust prompt declined: fingerprint=${certificateFingerprint}`);
        throw new Error(`MFi certificate trust declined for SHA-256 ${certificateFingerprint}`);
      }
      log(`MFi first-use trust prompt approved: fingerprint=${certificateFingerprint}`);
      validateUserPinnedCertificateValidity(item, validationTime);
      trustedCandidates.push({
        certificate: item,
        trustSource: 'user-pinned',
        fingerprintToPersist: certificateFingerprint
      });
      log(
        `User approved first-use MFi fingerprint ${certificateFingerprint}; challenge signature verification follows ` +
          `the current diagnostics setting`
      );
    }
  }
  if (trustedCandidates.length === 0) {
    throw new Error(
      `MFi PKIX validation failed against the system CA (${untrustedCertificates.length} certificate(s), ` +
        `date=${validationTime}, AIA download=${allowIntermediateDownload})` +
        `${validationErrors.length > 0 ? `: ${validationErrors.join('; ')}` : ''}` +
        `${allowIntermediateDownload ? '' : '; enable optional AIA lookup only for a trusted receiver'}`
    );
  }
  return {
    candidates: trustedCandidates,
    certificateCount: untrustedCertificates.length,
    encodingName
  };
}

function validateUserPinnedCertificateValidity(certificate: cert.X509Cert, validationTime: string): void {
  try {
    certificate.checkValidityWithDate(validationTime);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(
      `User-pinned MFi leaf failed certificate validity-date check; not saved or accepted: ${message}`
    );
  }
}
