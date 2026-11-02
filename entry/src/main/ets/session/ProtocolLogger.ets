import { hilog } from '@kit.PerformanceAnalysisKit';
import { formatLocalClock } from './LogTimestamp';

export type ProtocolLogLevel = 'DEBUG' | 'INFO' | 'WARN' | 'ERROR';
export type ProtocolEventValue = string | number | boolean | null | string[];

const LOG_DOMAIN: number = 0xCA21;
const SENSITIVE_FIELD: RegExp = /(password|passphrase|presharedkey|sharedsecret|privatekey|secret|challenge|signature|credential|token|authorization|certificate)/i;
const SENSITIVE_ASSIGNMENT: RegExp = /(password|passphrase|pre[_-]?shared[_-]?key|shared[_-]?secret|private[_-]?key|secret|challenge|signature|credential|token|authorization|certificate)(\s*[:=]\s*)([^\s,;]+)/gi;

function sanitizeEventValue(value: ProtocolEventValue): ProtocolEventValue {
  if (typeof value === 'string') {
    return value.replace(SENSITIVE_ASSIGNMENT, '$1$2[REDACTED]');
  }
  if (Array.isArray(value)) {
    return value.map((item: string): string => item.replace(SENSITIVE_ASSIGNMENT, '$1$2[REDACTED]'));
  }
  return value;
}

export function redactProtocolText(message: string): string {
  return message.replace(SENSITIVE_ASSIGNMENT, '$1$2[REDACTED]');
}

export function formatProtocolEvent(event: string, ...fields: ProtocolEventValue[]): string {
  let json = `{"event":${JSON.stringify(event)}`;
  for (let index = 0; index + 1 < fields.length; index += 2) {
    const keyValue = fields[index];
    if (typeof keyValue !== 'string' || keyValue === 'event') {
      continue;
    }
    const normalizedKey = keyValue.replace(/[^a-z0-9]/gi, '');
    const value = fields[index + 1];
    const safeValue = SENSITIVE_FIELD.test(normalizedKey) ? '[REDACTED]' : sanitizeEventValue(value);
    json += `,${JSON.stringify(keyValue)}:${JSON.stringify(safeValue)}`;
  }
  return `${json}}`;
}

export function formatRawBytesDiagnostic(
  direction: string,
  transport: string,
  bytes: Uint8Array,
  maximumBytes: number = 2048
): string {
  const count = Math.min(bytes.length, maximumBytes);
  const hex: string[] = [];
  for (let index = 0; index < count; index++) {
    hex.push((bytes[index] ?? 0).toString(16).padStart(2, '0'));
  }
  const truncated = count < bytes.length ? ` ... (${bytes.length - count} bytes omitted)` : '';
  return `RAW ${direction} ${transport} bytes=${bytes.length}: ${hex.join(' ')}${truncated}`;
}

export class ProtocolLogger {
  private readonly onEntry: (line: string) => void;

  constructor(onEntry: (line: string) => void) {
    this.onEntry = onEntry;
  }

  write(stage: string, message: string, level: ProtocolLogLevel = 'INFO'): void {
    const safeMessage = redactProtocolText(message).replace(/\r?\n/g, ' | ');
    const line = `${formatLocalClock()} ${level} ${stage}: ${safeMessage}`;
    this.onEntry(line);
    if (level === 'ERROR') {
      hilog.error(LOG_DOMAIN, 'CarPlayerProtocol', '%{public}s', line);
    } else if (level === 'WARN') {
      hilog.warn(LOG_DOMAIN, 'CarPlayerProtocol', '%{public}s', line);
    } else if (level === 'DEBUG') {
      hilog.debug(LOG_DOMAIN, 'CarPlayerProtocol', '%{public}s', line);
    } else {
      hilog.info(LOG_DOMAIN, 'CarPlayerProtocol', '%{public}s', line);
    }
  }

}