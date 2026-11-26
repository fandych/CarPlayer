import { formatProtocolEvent } from '../session/ProtocolLogger';

export class AirPlayEventReceiveDiagnostics {
  private lastQueueDelayLogAt: number = 0;
  private lastProcessingDelayLogAt: number = 0;

  logQueueDelay(queueWaitMs: number, pendingChunks: number, log: (message: string) => void): void {
    const now = Date.now();
    if (queueWaitMs < 100 || now - this.lastQueueDelayLogAt < 1000) {
      return;
    }
    this.lastQueueDelayLogAt = now;
    log(formatProtocolEvent('airplay.event.receive.queue-delay',
      'queueWaitMs', queueWaitMs,
      'pendingChunks', pendingChunks,
      'meaning', '事件 TCP 分块在串行接收队列中的等待时间超过 100ms'
    ));
  }

  logProcessingDelay(processingMs: number, pendingChunks: number, log: (message: string) => void): void {
    const now = Date.now();
    if (processingMs < 100 || now - this.lastProcessingDelayLogAt < 1000) {
      return;
    }
    this.lastProcessingDelayLogAt = now;
    log(formatProtocolEvent('airplay.event.receive.processing-delay',
      'processingMs', processingMs,
      'pendingChunks', pendingChunks,
      'meaning', '事件 TCP 分块解密、解析或应答耗时超过 100ms'
    ));
  }
}
