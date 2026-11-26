import { decodeUtf8 } from '../protocol/Iap2Codec';

export interface ParsedAirPlayRtspResponse {
  response: {
    statusCode: number;
    statusLine: string;
    headers: Map<string, string>;
    body: Uint8Array;
  };
  consumedBytes: number;
}

export function parseAirPlayRtspResponse(
  bytes: Uint8Array,
  expectedCseq: number
): ParsedAirPlayRtspResponse | undefined {
  const headerEnd = findHeaderEnd(bytes);
  if (headerEnd < 0) {
    return undefined;
  }
  const headerText = decodeUtf8(bytes.slice(0, headerEnd));
  const lines = headerText.split('\r\n');
  const statusLine = lines[0] ?? '';
  const statusCode = parseStatusCode(statusLine);
  const headers: Map<string, string> = new Map<string, string>();
  for (let index = 1; index < lines.length; index++) {
    const line = lines[index];
    const separator = line.indexOf(':');
    if (separator > 0) {
      headers.set(line.slice(0, separator).trim().toLowerCase(), line.slice(separator + 1).trim());
    }
  }
  if (headers.has('transfer-encoding')) {
    throw new Error('Chunked RTSP response bodies are not supported');
  }
  const contentLengthValue = headers.get('content-length') ?? '0';
  const contentLength = Number.parseInt(contentLengthValue, 10);
  if (!Number.isFinite(contentLength) || contentLength < 0 || contentLength > 1024 * 1024) {
    throw new Error(`Invalid AirPlay RTSP Content-Length: ${contentLengthValue}`);
  }
  const bodyStart = headerEnd + 4;
  const responseLength = bodyStart + contentLength;
  if (bytes.length < responseLength) {
    return undefined;
  }
  const cseqValue = headers.get('cseq');
  if (cseqValue && Number.parseInt(cseqValue, 10) !== expectedCseq) {
    throw new Error(`AirPlay RTSP CSeq mismatch: expected ${expectedCseq}, got ${cseqValue}`);
  }
  return {
    response: {
      statusCode,
      statusLine,
      headers,
      body: bytes.slice(bodyStart, responseLength)
    },
    consumedBytes: responseLength
  };
}

function findHeaderEnd(bytes: Uint8Array): number {
  for (let index = 0; index + 3 < bytes.length; index++) {
    if (bytes[index] === 13 && bytes[index + 1] === 10 && bytes[index + 2] === 13 && bytes[index + 3] === 10) {
      return index;
    }
  }
  return -1;
}

function parseStatusCode(statusLine: string): number {
  const parts = statusLine.split(' ');
  if (parts.length < 2) {
    throw new Error(`Invalid AirPlay RTSP status line: ${statusLine}`);
  }
  const statusCode = Number.parseInt(parts[1], 10);
  if (!Number.isFinite(statusCode)) {
    throw new Error(`Invalid AirPlay RTSP status code: ${statusLine}`);
  }
  return statusCode;
}
