import netSocket from '@ohos.net.socket';
import { settleSocketWithin } from '../network/SocketDeadline';
import { decodeUtf8, encodeUtf8, concatBytes, toArrayBuffer } from '../protocol/Iap2Codec';
import { AirPlayControlCipher } from './ControlCipher';
import { BinaryPlist, formatPlistDiagnostic } from './BinaryPlist';
import { CARPLAY_SENDER_SOURCE_VERSION } from '../protocol/CarPlaySenderCompatibility';
import { formatNetworkError, getSocketAddressFamily, WifiNetworkLease } from '../network/WifiNetworkLease';
import { formatProtocolEvent, formatRawBytesDiagnostic } from '../session/ProtocolLogger';

export interface AirPlayRtspResponse {
  statusCode: number;
  statusLine: string;
  headers: Map<string, string>;
  body: Uint8Array;
}

export interface AirPlayRtspHeaders {
  contentType?: string;
  appleHkp?: boolean;
  applePd?: boolean;
  userAgent?: string;
}

interface PendingResponse {
  cseq: number;
  method: string;
  path: string;
  startedAt: number;
  resolve: (response: AirPlayRtspResponse) => void;
  reject: (error: Error) => void;
  timeoutId: number;
}

const RTSP_REQUEST_TIMEOUT_MS: number = 10_000;

export class AirPlayRtspClient {
  private socket?: netSocket.TCPSocket;
  private messageHandler?: (info: netSocket.SocketMessageInfo) => void;
  private errorHandler?: (error: Error) => void;
  private closeHandler?: () => void;
  private receiveBuffer: Uint8Array = new Uint8Array(0);
  private pending?: PendingResponse;
  private cipher?: AirPlayControlCipher;
  private receiveQueue: Promise<void> = Promise.resolve();
  private requestQueue: Promise<void> = Promise.resolve();
  private nextCseq: number = 1;
  private readonly onError: (message: string) => void;
  private readonly onDisconnected: (message: string) => void;
  private readonly wifiNetworkLease: WifiNetworkLease;
  private disconnectNotified: boolean = false;

  constructor(
    onError: (message: string) => void,
    onDisconnected: (message: string) => void,
    wifiNetworkLease: WifiNetworkLease
  ) {
    this.onError = onError;
    this.onDisconnected = onDisconnected;
    this.wifiNetworkLease = wifiNetworkLease;
  }

  get isConnected(): boolean {
    return this.socket !== undefined && !this.disconnectNotified;
  }

  async connect(host: string, port: number): Promise<void> {
    if (this.socket) {
      throw new Error('AirPlay RTSP client is already connected');
    }
    if (!host || port < 1 || port > 65535) {
      throw new Error('Invalid AirPlay RTSP endpoint');
    }
    const socket = netSocket.constructTCPSocketInstance();
    this.socket = socket;
    this.disconnectNotified = false;
    this.messageHandler = (info: netSocket.SocketMessageInfo): void => {
      const data = new Uint8Array(info.message);
      this.receiveQueue = this.receiveQueue
        .then((): Promise<void> => this.handleIncoming(data))
        .catch((error: Error): void => {
          this.onError(`AirPlay RTSP receive failed: ${formatNetworkError(error)}`);
          this.failPending(error);
        });
    };
    this.errorHandler = (error: Error): void => {
      const message = formatNetworkError(error);
      this.onError(`AirPlay RTSP socket error: ${message}`);
      this.failPending(new Error(message));
      this.notifyDisconnected(socket, `RTSP socket error: ${message}`);
    };
    this.closeHandler = (): void => {
      this.failPending(new Error('AirPlay RTSP socket closed by peer'));
      this.notifyDisconnected(socket, 'RTSP socket closed by peer');
    };
    try {
      socket.on('message', this.messageHandler);
      socket.on('error', this.errorHandler);
      socket.on('close', this.closeHandler);
      const options: netSocket.TCPConnectOptions = {
        address: { address: host, port },
        timeout: 5000
      };
      if (await this.wifiNetworkLease.bindSocket(socket, 'AirPlay RTSP TCP', getSocketAddressFamily(host))) {
        this.onError('AirPlay RTSP socket 已绑定指定车机 Wi-Fi 网络');
      }
      await socket.connect(options);
    } catch (error) {
      const message = formatNetworkError(error);
      try {
        await this.close();
      } catch (cleanupError) {
        const cleanupMessage = cleanupError instanceof Error ? cleanupError.message : String(cleanupError);
        throw new Error(`AirPlay RTSP connect failed: ${message}; cleanup failed: ${cleanupMessage}`);
      }
      throw new Error(`AirPlay RTSP connect failed: ${message}`);
    }
  }

  async request(
    method: string,
    path: string,
    body: Uint8Array = new Uint8Array(0),
    headers: AirPlayRtspHeaders = {}
  ): Promise<AirPlayRtspResponse> {
    const previous = this.requestQueue;
    let release: () => void = (): void => {};
    this.requestQueue = new Promise<void>((resolve: () => void): void => {
      release = resolve;
    });
    try {
      await previous;
      return await this.sendRequest(method, path, body, headers);
    } finally {
      release();
    }
  }

  private async sendRequest(
    method: string,
    path: string,
    body: Uint8Array,
    headers: AirPlayRtspHeaders
  ): Promise<AirPlayRtspResponse> {
    const socket = this.socket;
    if (!socket) {
      throw new Error('AirPlay RTSP client is not connected');
    }
    if (this.pending) {
      throw new Error('An AirPlay RTSP request is already pending');
    }
    const cseq = this.nextCseq++;
    let requestText = `${method} ${path} RTSP/1.0\r\nCSeq: ${cseq}\r\n`;
    requestText += `User-Agent: ${headers.userAgent ?? `AirPlay/${CARPLAY_SENDER_SOURCE_VERSION}`}\r\n`;
    if (headers.contentType) {
      requestText += `Content-Type: ${headers.contentType}\r\n`;
    }
    if (headers.appleHkp) {
      requestText += 'X-Apple-HKP: 2\r\n';
    }
    if (headers.applePd) {
      requestText += 'X-Apple-PD: 1\r\n';
    }
    requestText += `Content-Length: ${body.length}\r\n\r\n`;
    const plaintext = concatBytes(encodeUtf8(requestText), body);
    const outbound = this.cipher ? await this.cipher.encrypt(plaintext) : plaintext;
    const startedAt = Date.now();

    const responsePromise = new Promise<AirPlayRtspResponse>((resolve, reject) => {
      const timeoutId = setTimeout((): void => {
        this.failPending(new Error(`AirPlay RTSP ${method} ${path} timed out`));
      }, RTSP_REQUEST_TIMEOUT_MS);
      const pending: PendingResponse = { cseq, method, path, startedAt, resolve, reject, timeoutId };
      this.pending = pending;
    });
    void responsePromise.catch((): void => {});
    this.onError(formatRawWireBytes(
      'TX',
      outbound,
      this.cipher === undefined && isSensitiveRtspPath(path)
    ));
    this.onError(formatProtocolEvent('airplay.rtsp.request',
      'method', method,
      'path', path,
      'cseq', cseq,
      'bodyBytes', body.length,
      'encrypted', this.cipher !== undefined,
      'contentType', headers.contentType ?? null,
      'bodySummary', formatRtspBodySummary(path, headers.contentType, body),
      'timeoutMs', RTSP_REQUEST_TIMEOUT_MS,
      'meaning', `向接收端发送 ${method} ${path}，等待对应 CSeq=${cseq} 的响应`
    ));
    const sendOptions: netSocket.TCPSendOptions = { data: toArrayBuffer(outbound) };
    try {
      await socket.send(sendOptions);
    } catch (error) {
      const message = formatNetworkError(error);
      this.failPending(new Error(`AirPlay RTSP write failed: ${message}`));
    }
    return responsePromise;
  }

  activateEncryption(readKey: Uint8Array, writeKey: Uint8Array): void {
    if (this.pending) {
      throw new Error('Cannot enable AirPlay control encryption while a request is pending');
    }
    if (this.receiveBuffer.length > 0) {
      throw new Error('Cannot enable AirPlay control encryption with unparsed plaintext data');
    }
    this.cipher = new AirPlayControlCipher(readKey, writeKey);
  }

  async close(): Promise<void> {
    this.failPending(new Error('AirPlay RTSP connection closed'));
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
        failures.push(`message listener: ${formatNetworkError(error)}`);
      }
    }
    if (this.errorHandler) {
      try {
        socket.off('error', this.errorHandler);
      } catch (error) {
        failures.push(`error listener: ${formatNetworkError(error)}`);
      }
    }
    if (this.closeHandler) {
      try {
        socket.off('close', this.closeHandler);
      } catch (error) {
        failures.push(`close listener: ${formatNetworkError(error)}`);
      }
    }
    this.messageHandler = undefined;
    this.errorHandler = undefined;
    this.closeHandler = undefined;
    try {
      await settleSocketWithin(socket.close(), 1500, 'RTSP socket close timed out');
    } catch (error) {
      failures.push(`socket close: ${formatNetworkError(error)}`);
    }
    if (failures.length > 0) {
      throw new Error(`AirPlay RTSP cleanup failed (${failures.join('; ')})`);
    }
  }

  private async handleIncoming(data: Uint8Array): Promise<void> {
    const cipher = this.cipher;
    this.onError(formatRawWireBytes(
      'RX',
      data,
      cipher === undefined && isSensitiveRtspPath(this.pending?.path ?? '')
    ));
    const plaintext = cipher ? await cipher.decrypt(data) : data;
    if (plaintext.length === 0) {
      this.onError(formatProtocolEvent('airplay.rtsp.receive.interpretation',
        'wireBytes', data.length,
        'encrypted', cipher !== undefined,
        'plaintextBytes', 0,
        'meaning', '本次数据尚未组成完整的加密控制帧，等待后续字节'
      ));
      return;
    }
    if (this.receiveBuffer.length + plaintext.length > 1024 * 1024) {
      this.receiveBuffer = new Uint8Array(0);
      throw new Error('AirPlay RTSP response exceeded the 1 MiB safety limit');
    }
    this.receiveBuffer = concatBytes(this.receiveBuffer, plaintext);
    this.parseResponse();
    const pending = this.pending;
    this.onError(formatProtocolEvent('airplay.rtsp.receive.interpretation',
      'wireBytes', data.length,
      'encrypted', cipher !== undefined,
      'plaintextBytes', plaintext.length,
      'bufferedPlaintextBytes', this.receiveBuffer.length,
      'waitingFor', pending ? `${pending.method} ${pending.path} CSeq=${pending.cseq}` : null,
      'meaning', pending
        ? '已解密数据；RTSP 响应尚未完整，继续等待'
        : '已解密并解析 RTSP 响应'
    ));
  }

  private parseResponse(): void {
    while (this.pending) {
      const headerEnd = findHeaderEnd(this.receiveBuffer);
      if (headerEnd < 0) {
        return;
      }
      const headerText = decodeUtf8(this.receiveBuffer.slice(0, headerEnd));
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
      if (this.receiveBuffer.length < responseLength) {
        return;
      }
      const cseqValue = headers.get('cseq');
      if (cseqValue && Number.parseInt(cseqValue, 10) !== this.pending.cseq) {
        throw new Error(`AirPlay RTSP CSeq mismatch: expected ${this.pending.cseq}, got ${cseqValue}`);
      }
      const response: AirPlayRtspResponse = {
        statusCode,
        statusLine,
        headers,
        body: this.receiveBuffer.slice(bodyStart, responseLength)
      };
      this.receiveBuffer = this.receiveBuffer.slice(responseLength);
      this.resolvePending(response);
    }
  }

  private resolvePending(response: AirPlayRtspResponse): void {
    const pending = this.pending;
    if (!pending) {
      throw new Error('Received an unsolicited AirPlay RTSP response');
    }
    clearTimeout(pending.timeoutId);
    this.pending = undefined;
    this.onError(formatProtocolEvent('airplay.rtsp.response',
      'method', pending.method,
      'path', pending.path,
      'cseq', pending.cseq,
      'statusCode', response.statusCode,
      'statusLine', response.statusLine,
      'bodyBytes', response.body.length,
      'contentType', response.headers.get('content-type') ?? null,
      'bodySummary', formatRtspBodySummary(
        pending.path,
        response.headers.get('content-type'),
        response.body
      ),
      'meaning', response.statusCode >= 200 && response.statusCode < 300
        ? '接收端已成功处理该请求'
        : '接收端返回非成功状态，调用方应检查状态码和响应内容',
      'elapsedMs', Date.now() - pending.startedAt
    ));
    pending.resolve(response);
  }

  private failPending(error: Error): void {
    const pending = this.pending;
    if (!pending) {
      return;
    }
    clearTimeout(pending.timeoutId);
    this.pending = undefined;
    this.onError(formatProtocolEvent('airplay.rtsp.failure',
      'method', pending.method,
      'path', pending.path,
      'cseq', pending.cseq,
      'elapsedMs', Date.now() - pending.startedAt,
      'error', error.message,
      'meaning', '等待窗口内没有收到完整响应，当前 RTSP 请求已失败'
    ));
    pending.reject(error);
  }

  private notifyDisconnected(socket: netSocket.TCPSocket, message: string): void {
    if (this.socket !== socket || this.disconnectNotified) {
      return;
    }
    this.disconnectNotified = true;
    this.onDisconnected(message);
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

const MAX_RAW_LOG_BYTES: number = 16 * 1024;

function isPairingPath(path: string): boolean {
  return path.includes('/pair-setup') || path.includes('/pair-verify');
}

function isSensitiveRtspPath(path: string): boolean {
  return isPairingPath(path) || path === '/setup' || path === '/info' || path.endsWith('/auth-setup');
}

function formatRtspBodySummary(path: string, contentType: string | undefined, body: Uint8Array): string {
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

function formatRawWireBytes(direction: string, bytes: Uint8Array, redact: boolean): string {
  let maskedBytes: Uint8Array | undefined;
  if (redact) {
    maskedBytes = new Uint8Array(bytes.length);
    for (let index = 0; index < maskedBytes.length; index++) {
      maskedBytes[index] = 1;
    }
  }
  return formatRawBytesDiagnostic(direction, 'AirPlay RTSP', bytes, MAX_RAW_LOG_BYTES, maskedBytes);
}
