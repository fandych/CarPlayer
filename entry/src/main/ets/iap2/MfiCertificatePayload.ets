import cert from '@ohos.security.cert';
import {
  MfiCertificateChain,
  extractPkcs7CertificateSet,
  isPkcs7SignedDataPayload,
  parseMfiCertificateChain
} from './mfi/MfiCertificateParser';

export interface LoadedMfiCertificatePayload {
  candidateCertificates: cert.X509Cert[];
  untrustedCertificates: cert.X509Cert[];
  encodingName: string;
  serializedChain: Uint8Array;
}

export async function loadMfiCertificatePayload(
  certificatePayload: Uint8Array,
  log: (message: string) => void
): Promise<LoadedMfiCertificatePayload> {
  const isCmsPayload = isPkcs7SignedDataPayload(certificatePayload);
  log(
    `MFi certificate validation started: payloadBytes=${certificatePayload.length}, ` +
      `container=${isCmsPayload ? 'PKCS#7 SignedData' : 'X.509 certificate chain'}`
  );
  log(`MFi AA01 parameter 0 received: bytes=${certificatePayload.length}`);
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
      log(`CMS getCerts(ALL_CERTS) failed: ${allCertificateError}`);
    }
    let signerCertificates: cert.X509Cert[] = [];
    try {
      signerCertificates = await parser.getCerts(cert.CmsCertType.SIGNER_CERTS);
    } catch (error) {
      signerCertificateError = error instanceof Error ? error.message : String(error);
    }
    if (untrustedCertificates.length === 0) {
      let extracted: Uint8Array[] = [];
      try {
        extracted = extractPkcs7CertificateSet(certificatePayload);
      } catch (error) {
        certificateSetError = error instanceof Error ? error.message : String(error);
        log(`CMS certificate-set ASN.1 fallback failed: ${certificateSetError}`);
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
        log(`CMS certificate-set ASN.1 fallback extracted ${untrustedCertificates.length} certificate(s)`);
      }
    }
    if (untrustedCertificates.length === 0 && signerCertificates.length > 0) {
      untrustedCertificates = signerCertificates;
      log('CMS all-certificates extraction unavailable; using signer certificate(s) as chain input');
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
    if (signerCertificateError && untrustedCertificates.length > 0) {
      log(
        `WARN: CMS SIGNER_CERTS extraction unavailable; using available certificate chain ` +
          `(${untrustedCertificates.length} certificate(s))`
      );
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
  return { candidateCertificates, untrustedCertificates, encodingName, serializedChain };
}
