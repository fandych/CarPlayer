import { hilog } from '@kit.PerformanceAnalysisKit';
import { formatRawByteBlock } from '../protocol/RawByteFormatter';
import { formatLocalClock } from './LogTimestamp';

export type ProtocolLogLevel = 'DEBUG' | 'INFO' | 'WARN' | 'ERROR';
export type ProtocolEventValue = string | number | boolean | null | string[];

export interface ProtocolLogContext {
  sessionId: string;
  attempt: number;
}

const LOG_DOMAIN: number = 0xCA21;
const SENSITIVE_FIELD: RegExp = /(password|passphrase|presharedkey|sharedsecret|privatekey|secret|challenge|signature|credential|token|authorization|certificate|payload|data)/i;
const NON_SENSITIVE_SUFFIX: RegExp = /(bytes|length|size|count|elapsedms|durationms|port|offset|sequence|fingerprint|sha256|format|candidates|attempt|summary)$/i;
const SENSITIVE_ASSIGNMENT: RegExp = /(password|passphrase|pre[_-]?shared[_-]?key|shared[_-]?secret|private[_-]?key|secret|challenge|signature|credential|token|authorization|certificate)(\s*[:=]\s*)([^\s,;]+)/gi;

function protocolEventLabel(event: string): string {
  switch (event) {
    case 'protocol.interpretation': return '协议含义';
    case 'iap2.transport.rx': return 'iAP2 接收 RFCOMM 数据';
    case 'iap2.transport.receive.queue-delay': return 'iAP2 接收队列延迟';
    case 'iap2.link.rx': return 'iAP2 接收链路帧';
    case 'iap2.link.tx': return 'iAP2 发送链路帧';
    case 'wifi.link.already_connected': return '已连接车机 Wi-Fi';
    case 'wifi.candidate.add_failed': return '添加 Wi-Fi 候选失败';
    case 'wifi.candidate.added': return '添加车机 Wi-Fi 候选';
    case 'wifi.candidate.connect.requested': return '请求连接车机 Wi-Fi';
    case 'wifi.candidate.retained': return '保留车机 Wi-Fi 配置';
    case 'wifi.candidate.add_retry': return '重试添加 Wi-Fi 候选';
    case 'wifi.candidate.list_failed': return '读取 Wi-Fi 候选列表失败';
    case 'wifi.candidate.removed': return '移除 Wi-Fi 候选';
    case 'wifi.candidate.remove_failed': return '移除 Wi-Fi 候选失败';
    case 'wifi.link.poll': return '等待车机 Wi-Fi 地址';
    case 'wifi.link.connected': return '已连接车机 Wi-Fi';
    case 'wifi.link.timeout': return '连接车机 Wi-Fi 超时';
    case 'wifi.join.failed': return '加入车机 Wi-Fi 失败';
    case 'mdns.discovery.started': return '开始搜索 AirPlay 服务';
    case 'mdns.discovery.stopped': return 'AirPlay 服务搜索结束';
    case 'mdns.discovery.timeout': return 'AirPlay 服务发现超时';
    case 'mdns.service.found': return '发现 AirPlay 服务';
    case 'mdns.service.invalid': return 'AirPlay 服务信息无效';
    case 'mdns.service.resolved': return 'AirPlay 服务解析完成';
    case 'mdns.service.resolve_failed': return 'AirPlay 服务解析失败';
    case 'mdns.raw.rx': return '收到 mDNS 原始数据';
    case 'mdns.raw.capture.started': return '启动 mDNS RAW 监听';
    case 'mdns.raw.capture.stopped': return '停止 mDNS RAW 监听';
    case 'carplay.ctrl.transport.rx': return '收到 CarPlay 控制数据';
    case 'carplay.ctrl.request': return '车机 CarPlay 控制请求';
    case 'carplay.ctrl.response': return '发送 CarPlay 控制响应';
    case 'airplay.rtsp.request': return '发送 AirPlay RTSP 请求';
    case 'airplay.rtsp.receive.interpretation': return '解析 AirPlay RTSP 接收数据';
    case 'airplay.rtsp.response': return '收到 AirPlay RTSP 响应';
    case 'airplay.rtsp.failure': return 'AirPlay RTSP 失败';
    case 'airplay.timing.request.invalid': return '收到无效 AirPlay 时钟请求';
    case 'airplay.timing.request': return '收到 AirPlay 时钟请求';
    case 'airplay.timing.response': return '发送 AirPlay 时钟响应';
    case 'airplay.timing.response.failure': return '发送 AirPlay 时钟响应失败';
    case 'airplay.keep_alive.tx': return '发送 AirPlay 保活包';
    case 'airplay.event.transport.rx.summary': return '收到 AirPlay 事件数据';
    case 'airplay.event.hid.summary': return '收到车机 HID 事件';
    case 'airplay.event.request': return 'AirPlay 事件请求';
    case 'airplay.event.receive.queue-delay': return 'AirPlay 事件队列延迟';
    case 'airplay.event.receive.processing-delay': return 'AirPlay 事件处理延迟';
    case 'airplay.event.plaintext.tx': return '发送 AirPlay 明文事件响应';
    case 'airplay.audio.rtp.tx': return '发送 AirPlay 音频包';
    case 'airplay.audio.sync.tx': return '发送 AirPlay 音频同步包';
    case 'airplay.video.codec_config.tx': return '发送 AirPlay 视频格式信息';
    case 'airplay.video.frame.tx': return '发送 AirPlay 视频帧';
    default: return event.split('.').map(protocolEventPartLabel).join(' · ');
  }
}

function protocolEventPartLabel(part: string): string {
  switch (part) {
    case 'iap2': return 'iAP2';
    case 'wifi': return 'Wi-Fi';
    case 'mdns': return 'mDNS';
    case 'airplay': return 'AirPlay';
    case 'carplay': return 'CarPlay';
    case 'transport': return '传输';
    case 'receive':
    case 'rx': return '接收';
    case 'received': return '已接收';
    case 'send':
    case 'tx': return '发送';
    case 'sent': return '已发送';
    case 'link': return '链路';
    case 'frame': return '帧';
    case 'queue': return '队列';
    case 'delay': return '延迟';
    case 'candidate': return '候选';
    case 'retained': return '保留';
    case 'retry': return '重试';
    case 'list': return '列表';
    case 'add': return '添加';
    case 'remove': return '移除';
    case 'poll': return '轮询';
    case 'connected': return '已连接';
    case 'already': return '已经';
    case 'timeout': return '超时';
    case 'failed':
    case 'failure': return '失败';
    case 'started': return '开始';
    case 'stopped': return '结束';
    case 'service': return '服务';
    case 'found': return '发现';
    case 'invalid': return '无效';
    case 'resolved': return '解析完成';
    case 'request': return '请求';
    case 'response': return '响应';
    case 'summary': return '摘要';
    case 'interpretation': return '含义';
    case 'event': return '事件';
    case 'raw': return '原始数据';
    case 'timing': return '时钟';
    case 'keep_alive': return '保活';
    case 'codec_config': return '格式配置';
    case 'rtp': return 'RTP';
    case 'sync': return '同步';
    case 'hid': return 'HID';
    case 'plaintext': return '明文';
    case 'processing': return '处理';
    default: return part;
  }
}

function protocolFieldLabel(key: string): string {
  switch (key) {
    case 'transport': return '传输层';
    case 'chunkBytes': return '数据块长度';
    case 'queueWaitMs': return '队列等待';
    case 'pendingChunks': return '待处理数据块';
    case 'control': return '控制字';
    case 'sequence': return '序号';
    case 'acknowledgement': return '确认序号';
    case 'sessionId': return 'iAP2 会话号';
    case 'payloadBytes': return '载荷长度';
    case 'payloadSummary': return '载荷摘要';
    case 'meaning': return '含义';
    case 'ssid': return '网络名';
    case 'securityType': return '安全类型';
    case 'channel': return '信道';
    case 'networkId': return '网络编号';
    case 'requestedSsid': return '请求网络';
    case 'currentSsid': return '当前网络';
    case 'ssidMatched': return '网络匹配';
    case 'hasIpAddress': return '已分配地址';
    case 'elapsedMs': return '耗时';
    case 'serviceType': return '服务类型';
    case 'serviceName': return '服务名';
    case 'host': return '主机';
    case 'port': return '端口';
    case 'txtKeys': return 'TXT 字段';
    case 'error': return '错误';
    case 'method': return '方法';
    case 'path': return '路径';
    case 'cseq': return 'CSeq';
    case 'bodyBytes': return '正文长度';
    case 'encrypted': return '已加密';
    case 'contentType': return '内容类型';
    case 'timeoutMs': return '超时阈值';
    case 'statusCode': return '状态码';
    case 'packet': return '包序号';
    case 'frame': return '帧序号';
    case 'keyFrame': return '关键帧';
    case 'source': return '来源';
    case 'sourcePort': return '来源端口';
    case 'group': return '组播组';
    case 'direction': return '方向';
    case 'dnsSummary': return 'DNS 摘要';
    case 'serviceCount': return '服务数';
    case 'retry': return '重试次数';
    case 'reason': return '原因';
    case 'outcome': return '结果';
    case 'localIp': return '本机地址';
    case 'candidateIndex': return '候选序号';
    case 'frameBytes': return '帧长度';
    case 'packetBytes': return '包长度';
    case 'signatureBytes': return '签名长度';
    case 'challengeBytes': return '挑战长度';
    case 'certificateBytes': return '证书长度';
    default: return key.replace(/([a-z])([A-Z])/g, '$1 $2');
  }
}

function sanitizeEventValue(value: ProtocolEventValue): ProtocolEventValue {
  if (typeof value === 'string') {
    return value.replace(SENSITIVE_ASSIGNMENT, '$1$2[已脱敏]').replace(/\r?\n/g, ' ');
  }
  if (Array.isArray(value)) {
    return value.map((item: string): string =>
      item.replace(SENSITIVE_ASSIGNMENT, '$1$2[已脱敏]').replace(/\r?\n/g, ' ')
    );
  }
  return value;
}

export function redactProtocolText(message: string): string {
  return message.replace(SENSITIVE_ASSIGNMENT, '$1$2[已脱敏]');
}

export function formatProtocolEvent(event: string, ...fields: ProtocolEventValue[]): string {
  const label = protocolEventLabel(event);
  const details: string[] = [];
  let pendingKey: string = '';
  let awaitingValue: boolean = false;
  for (const field of fields) {
    if (!awaitingValue) {
      pendingKey = typeof field === 'string' ? field : '';
      awaitingValue = true;
      continue;
    }
    const keyValue = pendingKey;
    pendingKey = '';
    awaitingValue = false;
    if (keyValue.length === 0 || keyValue === 'event') {
      continue;
    }
    const normalizedKey = keyValue.replace(/[^a-z0-9]/gi, '');
    const value = field;
    const sensitive = SENSITIVE_FIELD.test(normalizedKey) && !NON_SENSITIVE_SUFFIX.test(normalizedKey);
    const safeValue = sensitive ? '[已脱敏]' : sanitizeEventValue(value);
    const fieldLabel = protocolFieldLabel(keyValue);
    const printableValue = Array.isArray(safeValue)
      ? safeValue.join(', ')
      : safeValue === null
        ? '无'
        : typeof safeValue === 'boolean'
          ? safeValue ? '是' : '否'
          : String(safeValue);
    details.push(`${fieldLabel}=${printableValue}`);
  }
  return `【${label}】 (${event})${details.length > 0 ? ` ${details.join('；')}` : ''}`;
}

export function formatRawBytesDiagnostic(
  direction: string,
  transport: string,
  bytes: Uint8Array,
  maximumBytes: number = 16 * 1024,
  maskedBytes?: Uint8Array
): string {
  return formatRawByteBlock(direction, transport, bytes, maximumBytes, maskedBytes);
}

export class ProtocolLogger {
  private readonly onEntry: (line: string) => void;
  private context?: ProtocolLogContext;

  constructor(onEntry: (line: string) => void) {
    this.onEntry = onEntry;
  }

  setContext(context: ProtocolLogContext | undefined): void {
    this.context = context;
  }

  write(stage: string, message: string, level: ProtocolLogLevel = 'INFO'): void {
    const safeLines = redactProtocolText(message).replace(/\r/g, '').split('\n');
    const context = this.context
      ? ` [会话 ${this.context.sessionId}${this.context.attempt > 0 ? ` / 尝试 ${this.context.attempt}` : ''}]`
      : '';
    const prefix = `${formatLocalClock()} ${level}${context} ${stage}: `;
    let firstLine: string = '';
    let isFirstLine: boolean = true;
    const blockLines: string[] = [];
    for (const line of safeLines) {
      if (isFirstLine) {
        firstLine = line;
        isFirstLine = false;
      } else {
        blockLines.push(`    ${line}`);
      }
    }
    blockLines.unshift(prefix + firstLine);
    const block = blockLines.join('\n');
    this.onEntry(block);
    if (level === 'ERROR') {
      hilog.error(LOG_DOMAIN, 'CarPlayerProtocol', '%{public}s', prefix + firstLine);
    } else if (level === 'WARN') {
      hilog.warn(LOG_DOMAIN, 'CarPlayerProtocol', '%{public}s', prefix + firstLine);
    } else if (level === 'DEBUG') {
      hilog.debug(LOG_DOMAIN, 'CarPlayerProtocol', '%{public}s', prefix + firstLine);
    } else {
      hilog.info(LOG_DOMAIN, 'CarPlayerProtocol', '%{public}s', prefix + firstLine);
    }
  }

}