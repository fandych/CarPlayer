import { encodeUtf8, concatBytes } from '../protocol/Iap2Codec';
import { AirPlayControlCipher } from './ControlCipher';
import { CARPLAY_SENDER_SOURCE_VERSION } from '../protocol/CarPlaySenderCompatibility';
import { formatNetworkError, WifiNetworkLease } from '../network/WifiNetworkLease';
import { formatProtocolEvent } from '../session/ProtocolLogger';
import { AirPlayRtspConnection } from './AirPlayRtspConnection';
import { formatRtspBodySummary, formatRtspRawBytes, isSensitiveRtspPath } from './AirPlayRtspDiagnostics';
import { parseAirPlayRtspResponse } from './AirPlayRtspResponseParser';

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
  private readonly connection: AirPlayRtspConnection;
  private receiveBuffer: Uint8Array = new Uint8Array(0);
  private pending?: PendingResponse;
  private cipher?: AirPlayControlCipher;
  private receiveQueue: Promise<void> = Promise.resolve();
  private requestQueue: Promise<void> = Promise.resolve();
  private nextCseq: number = 1;
  private readonly onError: (message: string) => void;
  private readonly onDisconnected: (message: string) => void;

  constructor(
    onError: (message: string) => void,
    onDisconnected: (message: string) => void,
    wifiNetworkLease: WifiNetworkLease
  ) {
    this.onError = onError;
    this.onDisconnected = onDisconnected;
    this.connection = new AirPlayRtspConnection(
      (data: Uint8Array): void => {
        this.receiveQueue = this.receiveQueue
          .then((): Promise<void> => this.handleIncoming(data))
          .catch((error: Error): void => {
            this.onError(`AirPlay RTSP receive failed: ${formatNetworkError(error)}`);
            this.failPending(error);
          });
      },
      (error: Error): void => {
        const message = formatNetworkError(error);
        this.onError(`AirPlay RTSP socket error: ${message}`);
        this.failPending(new Error(message));
      },
      (message: string): void => {
        this.failPending(new Error(message));
        this.onDisconnected(message);
      },
      (): void => {
        this.onError('AirPlay RTSP socket 已绑定指定车机 Wi-Fi 网络');
      },
      (): void => {
        this.failPending(new Error('AirPlay RTSP connection closed'));
      },
      wifiNetworkLease
    );
  }

  get isConnected(): boolean {
    return this.connection.isConnected;
  }

  async connect(host: string, port: number): Promise<void> {
    await this.connection.connect(host, port);
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
    if (!this.connection.hasSocket) {
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
    this.onError(formatRtspRawBytes(
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
    try {
      await this.connection.send(outbound);
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
    await this.connection.close();
  }

  private async handleIncoming(data: Uint8Array): Promise<void> {
    const cipher = this.cipher;
    this.onError(formatRtspRawBytes(
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
      const parsed = parseAirPlayRtspResponse(this.receiveBuffer, this.pending.cseq);
      if (!parsed) {
        return;
      }
      this.receiveBuffer = this.receiveBuffer.slice(parsed.consumedBytes);
      this.resolvePending(parsed.response);
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

}
