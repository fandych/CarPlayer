import cert from '@ohos.security.cert';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { decodeUtf8 } from '../protocol/Iap2Codec';
import { MfiPkixTrustDecision, MfiTrustPromptInfo } from './MfiVerifierTypes';

interface MfiCertificateIdentity {
  subject: string;
  issuer: string;
}

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

export function isMfiPinEligiblePkixFailure(message: string): boolean {
  return message.includes('unable to get local issuer certificate') ||
    message.includes('No AIA extension found in certificate') ||
    message.includes('Failed to obtain the certificate issuer') ||
    message.toLowerCase().includes('untrusted certificate');
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

export function certificateNames(certificate: cert.X509Cert): string {
  const identity = certificateIdentity(certificate);
  return `subject=${identity.subject}; issuer=${identity.issuer}`;
}

export function mfiTrustPromptInfo(
  certificate: cert.X509Cert,
  fingerprint: string,
  pkixFailure: string
): MfiTrustPromptInfo {
  const identity = certificateIdentity(certificate);
  return {
    fingerprint,
    subject: identity.subject,
    issuer: identity.issuer,
    pkixFailure
  };
}

export async function x509Fingerprint(certificate: cert.X509Cert): Promise<string> {
  const encoded = await certificate.getEncoded();
  if (encoded.encodingFormat !== cert.EncodingFormat.FORMAT_DER) {
    throw new Error(`X.509 getEncoded returned unsupported format ${encoded.encodingFormat}`);
  }
  return sha256Fingerprint(encoded.data);
}

export function formatPkixFailure(index: number, error: Error | string, aiaEnabled: boolean): string {
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

export function toAsn1Time(date: Date): string {
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

export async function sha256Fingerprint(input: Uint8Array): Promise<string> {
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
