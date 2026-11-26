import { BinaryPlist, formatPlistDiagnostic } from './BinaryPlist';
import { formatNetworkError } from '../network/WifiNetworkLease';
import { formatRawBytesDiagnostic } from '../session/ProtocolLogger';

const MAX_RAW_LOG_BYTES: number = 16 * 1024;

export function isSensitiveRtspPath(path: string): boolean {
  return isPairingPath(path) || path === '/setup' || path === '/info' || path.endsWith('/auth-setup');
}

export function formatRtspBodySummary(path: string, contentType: string | undefined, body: Uint8Array): string {
  if (isPairingPath(path) || path.endsWith('/auth-setup')) {
    return `authentication payload redacted (${body.length}B)`;
  }
  if (body.length === 0) {
    return 'empty body';
  }
  if (contentType?.toLowerCase().includes('binary-plist')) {
    try {
      return formatPlistDiagnostic(BinaryPlist.decode(body));
    } catch (error) {
      return `invalid binary plist: ${formatNetworkError(error)}`;
    }
  }
  return `body omitted (${body.length}B; content type=${contentType ?? 'unspecified'})`;
}

export function formatRtspRawBytes(direction: string, bytes: Uint8Array, redact: boolean): string {
  let maskedBytes: Uint8Array | undefined;
  if (redact) {
    maskedBytes = new Uint8Array(bytes.length);
    for (let index = 0; index < maskedBytes.length; index++) {
      maskedBytes[index] = 1;
    }
  }
  return formatRawBytesDiagnostic(direction, 'AirPlay RTSP', bytes, MAX_RAW_LOG_BYTES, maskedBytes);
}

function isPairingPath(path: string): boolean {
  return path.includes('/pair-setup') || path.includes('/pair-verify');
}
