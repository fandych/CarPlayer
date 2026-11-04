import netSocket from '@ohos.net.socket';
import { AirPlayControlCipher } from './ControlCipher';
import { BinaryPlist, formatPlistDiagnostic } from './BinaryPlist';
import { getSocketAddressFamily, WifiNetworkLease } from '../network/WifiNetworkLease';
import { hkdfSha512 } from './AirPlayCrypto';
import { concatBytes, decodeUtf8, encodeUtf8, toArrayBuffer } from '../protocol/Iap2Codec';
import { formatProtocolEvent, formatRawBytesDiagnostic } from '../session/ProtocolLogger';

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
    const request: AirPlayEventRequest = {
      method: requestParts[0],
      target: requestParts[1],
      cseq,
      headers,
      body: remaining.slice(bodyStart, requestLength)
    };
    requests.push(request);
    remaining = remaining.slice(requestLength);
  }
  if (remaining.length > 1024 * 1024) {
    throw new Error('AirPlay event receive buffer exceeded the 1 MiB safety limit');
  }
  const result: ParsedAirPlayEventRequests = { requests, remaining };
  return result;
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

export class AirPlayEventChannel {
  private socket?: netSocket.TCPSocket;
  private messageHandler?: (info: netSocket.SocketMessageInfo) => void;
  private errorHandler?: (error: Error) => void;
  private cipher?: AirPlayControlCipher;
  private receiveBuffer: Uint8Array = new Uint8Array(0);
  private receiveQueue: Promise<void> = Promise.resolve();
  private writeQueue: Promise<void> = Promise.resolve();
  private nextCommandCseq: number = 1;
  private running: boolean = false;
  private receivedChunks: number = 0;
  private receivedRequests: number = 0;
  private receivedBytes: number = 0;
  private pendingReceiveChunks: number = 0;
  private lastTransportSummaryAt: number = 0;
  private lastQueueDelayLogAt: number = 0;
  private lastProcessingDelayLogAt: number = 0;
  private readonly hidReportSummary: AirPlayHidReportSummaryWindow = new AirPlayHidReportSummaryWindow();
  private readonly log: (message: string) => void;
  private readonly onRequest: (request: AirPlayEventRequest) => boolean;
  private readonly wifiNetworkLease: WifiNetworkLease;

  constructor(
    log: (message: string) => void,
    onRequest: (request: AirPlayEventRequest) => boolean,
    wifiNetworkLease: WifiNetworkLease
  ) {
    this.log = log;
    this.onRequest = onRequest;
    this.wifiNetworkLease = wifiNetworkLease;
  }

  async connect(host: string, port: number, sharedSecret?: Uint8Array): Promise<void> {
    if (this.socket) {
      throw new Error('AirPlay event channel is already connected');
    }
    if (!host || port < 1 || port > 65535 || sharedSecret?.length === 0) {
      throw new Error('Invalid AirPlay event endpoint or empty shared secret');
    }
    if (sharedSecret) {
      const phoneWriteKey = await hkdfSha512(
        sharedSecret,
        encodeUtf8('Events-Salt'),
        encodeUtf8('Events-Read-Encryption-Key')
      );
      const phoneReadKey = await hkdfSha512(
        sharedSecret,
        encodeUtf8('Events-Salt'),
        encodeUtf8('Events-Write-Encryption-Key')
      );
      this.cipher = new AirPlayControlCipher(phoneReadKey, phoneWriteKey);
    }
    const socket = netSocket.constructTCPSocketInstance();
    this.socket = socket;
    this.running = true;
    this.lastTransportSummaryAt = Date.now();
    this.messageHandler = (info: netSocket.SocketMessageInfo): void => {
      if (!this.running) {
        return;
      }
      const chunk = new Uint8Array(info.message);
      this.receivedChunks++;
      this.receivedBytes += chunk.length;
      this.pendingReceiveChunks++;
      const receivedAt = Date.now();
      if (receivedAt - this.lastTransportSummaryAt >= 5000) {
        this.lastTransportSummaryAt = receivedAt;
        this.log(formatProtocolEvent('airplay.event.transport.rx.summary',
          'chunks', this.receivedChunks,
          'wireBytes', this.receivedBytes,
          'requests', this.receivedRequests,
          'pendingChunks', this.pendingReceiveChunks
        ));
      }
      this.receiveQueue = this.receiveQueue
        .then(async (): Promise<void> => {
          try {
            await this.handleIncoming(chunk, receivedAt);
          } finally {
            this.pendingReceiveChunks--;
          }
        })
        .catch((error: Error): void => {
          this.log(`AirPlay event channel receive failed: ${error.message}`);
          this.running = false;
        });
    };
    this.errorHandler = (error: Error): void => {
      this.log(`AirPlay event channel socket error: ${error.message}`);
      this.running = false;
    };
    try {
      socket.on('message', this.messageHandler);
      socket.on('error', this.errorHandler);
      if (await this.wifiNetworkLease.bindSocket(socket, 'AirPlay event TCP', getSocketAddressFamily(host))) {
        this.log('AirPlay event socket 已绑定指定车机 Wi-Fi 网络');
      }
      await socket.connect({
        address: { address: host, port },
        timeout: 5000
      });
      this.log(`AirPlay ${this.cipher ? 'encrypted' : 'plaintext'} event channel connected to ${host}:${port}`);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      try {
        await this.close();
      } catch (cleanupError) {
        throw new Error(
          `AirPlay event connect failed: ${message}; cleanup failed: ` +
            `${cleanupError instanceof Error ? cleanupError.message : String(cleanupError)}`
        );
      }
      throw new Error(`AirPlay event connect failed: ${message}`);
    }
  }

  async close(): Promise<void> {
    this.running = false;
    const socket = this.socket;
    this.socket = undefined;
    if (!socket) {
      return;
    }
    const failures: string[] = [];
    if (this.messageHandler) {
      try {
        socket.off('message', this.messageHandler);
      } catch (error) {
        failures.push(`message listener: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    if (this.errorHandler) {
      try {
        socket.off('error', this.errorHandler);
      } catch (error) {
        failures.push(`error listener: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    this.messageHandler = undefined;
    this.errorHandler = undefined;
    this.cipher = undefined;
    this.receiveBuffer = new Uint8Array(0);
    this.writeQueue = Promise.resolve();
    try {
      await socket.close();
    } catch (error) {
      failures.push(`socket: ${error instanceof Error ? error.message : String(error)}`);
    }
    if (failures.length > 0) {
      throw new Error(`AirPlay event cleanup failed: ${failures.join('; ')}`);
    }
  }

  async sendCommand(body: Uint8Array): Promise<void> {
    if (!this.socket || !this.cipher || !this.running) {
      throw new Error('AirPlay event channel is not ready to send a command');
    }
    const cseq = this.nextCommandCseq++;
    const headers =
      `POST /command RTSP/1.0\r\nCSeq: ${cseq}\r\n` +
      `Content-Type: application/x-apple-binary-plist\r\nContent-Length: ${body.length}\r\n\r\n`;
    await this.sendPlaintext(
      concatBytes(encodeUtf8(headers), body),
      true,
      `发送 POST /command CSeq=${cseq}；plist=${formatEventBodySummary(body)}`
    );
  }

  private async handleIncoming(data: Uint8Array, receivedAt: number): Promise<void> {
    const processingStartedAt = Date.now();
    this.logQueueDelay(processingStartedAt - receivedAt);
    try {
      if (!this.running) {
        return;
      }
      const cipher = this.cipher;
      const plaintext = cipher ? await cipher.decrypt(data) : data;
      this.receiveBuffer = concatBytes(this.receiveBuffer, plaintext);
      const parsed = parseAirPlayEventRequests(this.receiveBuffer);
      this.receiveBuffer = parsed.remaining;
      const responses: Uint8Array[] = [];
      const responseMeanings: string[] = [];
      let hasNonHidRequest = false;
      for (const request of parsed.requests) {
        const requestNumber = ++this.receivedRequests;
        const isHidReport = this.onRequest(request);
        if (isHidReport) {
          const summarizedReports = this.hidReportSummary.record(Date.now());
          if (summarizedReports !== undefined) {
            this.log(formatProtocolEvent('airplay.event.hid.summary',
              'reports', summarizedReports,
              'request', requestNumber,
              'meaning', 'HID 输入已确认；按时间窗口汇总，省略逐包日志'
            ));
          }
        } else {
          hasNonHidRequest = true;
          this.log(formatProtocolEvent('airplay.event.request',
            'packet', requestNumber,
            'method', request.method,
            'target', request.target,
            'cseq', request.cseq,
            'bodyBytes', request.body.length,
            'bodySummary', formatEventBodySummary(request.body),
            'hidReport', false,
            'meaning', '事件已交给 AirPlay 控制请求处理器'
          ));
        }
        responses.push(buildAirPlayEventResponse(request.cseq, request.responseBody));
        responseMeanings.push(`CSeq=${request.cseq} -> RTSP 200 OK`);
      }
      if (responses.length > 0) {
        await this.sendPlaintext(
          concatBytes(...responses),
          hasNonHidRequest,
          hasNonHidRequest ? responseMeanings.join('; ') : `HID event acknowledgements=${responses.length}`
        );
      }
    } finally {
      this.logProcessingDelay(Date.now() - processingStartedAt);
    }
  }

  private logQueueDelay(queueWaitMs: number): void {
    const now = Date.now();
    if (queueWaitMs < 100 || now - this.lastQueueDelayLogAt < 1000) {
      return;
    }
    this.lastQueueDelayLogAt = now;
    this.log(formatProtocolEvent('airplay.event.receive.queue-delay',
      'queueWaitMs', queueWaitMs,
      'pendingChunks', this.pendingReceiveChunks,
      'meaning', '事件 TCP 分块在串行接收队列中的等待时间超过 100ms'
    ));
  }

  private logProcessingDelay(processingMs: number): void {
    const now = Date.now();
    if (processingMs < 100 || now - this.lastProcessingDelayLogAt < 1000) {
      return;
    }
    this.lastProcessingDelayLogAt = now;
    this.log(formatProtocolEvent('airplay.event.receive.processing-delay',
      'processingMs', processingMs,
      'pendingChunks', this.pendingReceiveChunks,
      'meaning', '事件 TCP 分块解密、解析或应答耗时超过 100ms'
    ));
  }

  private async sendPlaintext(
    plaintext: Uint8Array,
    logTraffic: boolean = true,
    meaning: string = '发送 AirPlay 事件通道响应'
  ): Promise<void> {
    const operation = this.writeQueue.then(async (): Promise<void> => {
      const socket = this.socket;
      const cipher = this.cipher;
      if (!socket || !this.running) {
        throw new Error('AirPlay event channel closed before send');
      }
      const encrypted = cipher ? await cipher.encrypt(plaintext) : plaintext;
      if (logTraffic) {
        if (cipher) {
          this.log(formatRawBytesDiagnostic('TX', 'AirPlay event TCP ciphertext', encrypted, 256));
        }
        this.log(formatProtocolEvent('airplay.event.plaintext.tx',
          'bytes', plaintext.length,
          'wireBytes', encrypted.length,
          'encrypted', cipher !== undefined,
          'meaning', meaning
        ));
      }
      await socket.send({ data: toArrayBuffer(encrypted) });
    });
    this.writeQueue = operation.catch((): void => {});
    return operation;
  }

}

function formatEventBodySummary(body: Uint8Array): string {
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
