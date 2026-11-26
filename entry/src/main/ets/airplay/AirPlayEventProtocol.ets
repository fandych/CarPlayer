import { BinaryPlist, formatPlistDiagnostic } from './BinaryPlist';
import { concatBytes, decodeUtf8, encodeUtf8 } from '../protocol/Iap2Codec';

export interface AirPlayEventRequest {
  method: string;
  target: string;
  cseq: number;
  headers: Map<string, string>;
  body: Uint8Array;
  responseBody?: Uint8Array;
}

export interface ParsedAirPlayEventRequests {
  requests: AirPlayEventRequest[];
  remaining: Uint8Array;
}

export class AirPlayHidReportSummaryWindow {
  private readonly intervalMs: number;
  private windowStartAt: number = -1;
  private reportCount: number = 0;

  constructor(intervalMs: number = 1000) {
    this.intervalMs = intervalMs;
  }

  record(now: number): number | undefined {
    this.reportCount++;
    if (this.windowStartAt >= 0 && now - this.windowStartAt < this.intervalMs) {
      return undefined;
    }
    const reportCount = this.reportCount;
    this.reportCount = 0;
    this.windowStartAt = now;
    return reportCount;
  }
}

export function parseAirPlayEventRequests(input: Uint8Array): ParsedAirPlayEventRequests {
  const requests: AirPlayEventRequest[] = [];
  let remaining = input;
  while (remaining.length > 0) {
    const headerEnd = findHeaderEnd(remaining);
    if (headerEnd < 0) {
      if (remaining.length > 64 * 1024) {
        throw new Error('AirPlay event request header exceeded 64 KiB');
      }
      break;
    }
    if (headerEnd > 64 * 1024) {
      throw new Error('AirPlay event request header exceeded 64 KiB');
    }
    const lines = decodeUtf8(remaining.slice(0, headerEnd)).split('\r\n');
    const requestLine = lines[0] ?? '';
    const requestParts = requestLine.split(' ');
    const headers: Map<string, string> = new Map<string, string>();
    for (let index = 1; index < lines.length; index++) {
      const line = lines[index];
      const separator = line.indexOf(':');
      if (separator > 0) {
        const name = line.slice(0, separator).trim().toLowerCase();
        if ((name === 'content-length' || name === 'cseq') && headers.has(name)) {
          throw new Error(`Duplicate AirPlay event ${name}`);
        }
        headers.set(name, line.slice(separator + 1).trim());
      }
    }
    if (headers.has('transfer-encoding')) {
      throw new Error('Chunked AirPlay event request bodies are not supported');
    }
    const cseqText = headers.get('cseq') ?? '';
    const cseq = Number(cseqText);
    const contentLengthText = headers.get('content-length') ?? '0';
    const contentLength = Number(contentLengthText);
    if (!/^\d+$/.test(cseqText) || !Number.isSafeInteger(cseq) || cseq < 0) {
      throw new Error('AirPlay event request is missing a valid CSeq');
    }
    if (!/^\d+$/.test(contentLengthText) || !Number.isSafeInteger(contentLength) ||
      contentLength < 0 || contentLength > 1024 * 1024) {
      throw new Error(`Invalid AirPlay event Content-Length: ${contentLengthText}`);
    }
    const bodyStart = headerEnd + 4;
    const requestLength = bodyStart + contentLength;
    if (remaining.length < requestLength) {
      break;
    }
    if (requestParts[0]?.startsWith('RTSP/') || requestParts[0]?.startsWith('HTTP/')) {
      remaining = remaining.slice(requestLength);
      continue;
    }
    if (requestParts.length !== 3 ||
      (!requestParts[1].startsWith('/') && !(requestParts[0] === 'OPTIONS' && requestParts[1] === '*')) ||
      requestParts[2] !== 'RTSP/1.0') {
      throw new Error(`Invalid AirPlay event request line: ${requestLine}`);
    }
    requests.push({
      method: requestParts[0],
      target: requestParts[1],
      cseq,
      headers,
      body: remaining.slice(bodyStart, requestLength)
    });
    remaining = remaining.slice(requestLength);
  }
  if (remaining.length > 1024 * 1024) {
    throw new Error('AirPlay event receive buffer exceeded the 1 MiB safety limit');
  }
  return { requests, remaining };
}

export function buildAirPlayEventResponse(cseq: number, body?: Uint8Array): Uint8Array {
  if (!Number.isInteger(cseq) || cseq < 0) {
    throw new Error('Invalid AirPlay event response CSeq');
  }
  if (!body || body.length === 0) {
    return encodeUtf8(`RTSP/1.0 200 OK\r\nCSeq: ${cseq}\r\nContent-Length: 0\r\n\r\n`);
  }
  return concatBytes(encodeUtf8(
    `RTSP/1.0 200 OK\r\nCSeq: ${cseq}\r\nContent-Type: application/x-apple-binary-plist\r\n` +
      `Content-Length: ${body.length}\r\n\r\n`
  ), body);
}

export function formatEventBodySummary(body: Uint8Array): string {
  if (body.length === 0) {
    return 'empty body';
  }
  try {
    return formatPlistDiagnostic(BinaryPlist.decode(body));
  } catch (error) {
    return `non-plist body (${body.length}B): ${error instanceof Error ? error.message : String(error)}`;
  }
}

function findHeaderEnd(bytes: Uint8Array): number {
  for (let index = 0; index + 3 < bytes.length; index++) {
    if (bytes[index] === 13 && bytes[index + 1] === 10 && bytes[index + 2] === 13 && bytes[index + 3] === 10) {
      return index;
    }
  }
  return -1;
}
