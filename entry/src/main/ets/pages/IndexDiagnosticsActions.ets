import { IndexHost } from './IndexHost';
import fileFs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import promptAction from '@ohos.promptAction';
import { MAX_CONNECTION_LOG_LINES } from '../session/ConnectionLogBuffer';
import { diagnosticLogArchive } from '../session/DiagnosticLogArchive';
import { formatLocalTimestamp } from '../session/LogTimestamp';
import { ProtocolLogLevel, ProtocolLogger } from '../session/ProtocolLogger';
interface ApiErrorDetails {
  code?: number;
  message?: string;
}

export function addLog(host: IndexHost, line: string): void {
    diagnosticLogArchive.append(line);
    host.pendingUiLogLines.push(line);
    if (host.uiLogFlushTimer < 0) {
      host.uiLogFlushTimer = setTimeout((): void => host.flushPendingUiLogLines(), 250);
    }
}

export function flushPendingUiLogLines(host: IndexHost): void {
    if (host.uiLogFlushTimer >= 0) {
      clearTimeout(host.uiLogFlushTimer);
      host.uiLogFlushTimer = -1;
    }
    if (host.pendingUiLogLines.length === 0) {
      return;
    }
    const newestFirst = host.pendingUiLogLines.reverse();
    host.pendingUiLogLines = [];
    host.logs = [...newestFirst, ...host.logs].slice(0, MAX_CONNECTION_LOG_LINES);
}

export async function clearLogs(host: IndexHost): Promise<void> {
    try {
      const result = await promptAction.showDialog({
        title: '清空日志？',
        message: '将删除本次运行的日志文件。此操作不可撤销。',
        buttons: [
          { text: '取消', color: '#68736D' },
          { text: '清空', color: '#A14D34' }
        ]
      });
      if (result.index !== 1) {
        return;
      }
      diagnosticLogArchive.clear();
      if (host.uiLogFlushTimer >= 0) {
        clearTimeout(host.uiLogFlushTimer);
        host.uiLogFlushTimer = -1;
      }
      host.pendingUiLogLines = [];
      host.logs = [];
    } catch (error) {
      host.showError(error instanceof Error ? error : new Error(String(error)));
    }
}

export async function exportLogs(host: IndexHost): Promise<void> {
    let openedFile: fileFs.File | undefined;
    try {
      const savedUris = await new picker.DocumentViewPicker(host.getAppContext()).save({
        newFileNames: [`CarPlayer-logs-${formatLocalTimestamp().replace(/[:.]/g, '-')}.log`]
      });
      const savedUri = savedUris[0];
      if (!savedUri) {
        return;
      }
      openedFile = await fileFs.open(
        savedUri,
        fileFs.OpenMode.WRITE_ONLY | fileFs.OpenMode.CREATE | fileFs.OpenMode.TRUNC
      );
      const contents = diagnosticLogArchive.readAllText() || host.logs.slice().reverse().join('\n');
      await fileFs.write(openedFile.fd, `${contents}\n`);
      await fileFs.close(openedFile);
      openedFile = undefined;
      await promptAction.showToast({ message: '本次运行日志已导出' });
    } catch (error) {
      host.showError(error instanceof Error ? error : new Error(String(error)));
    } finally {
      if (openedFile) {
        try {
          await fileFs.close(openedFile);
        } catch (error) {
          host.logProtocol('diagnostics', `关闭导出日志文件失败：${host.errorMessage(error)}`, 'ERROR');
        }
      }
    }
}

export function logProtocol(host: IndexHost, stage: string, message: string, level: ProtocolLogLevel = 'INFO'): void {
    if (!host.protocolLogger) {
      host.protocolLogger = new ProtocolLogger((line: string): void => host.addLog(line));
    }
    if (stage === 'iap2' && /已接受 RFCOMM 连接|重新发送 iAP2 检测标记.*重新协商链路/.test(message)) {
      host.connectionAttempt++;
    }
    host.protocolLogger.setContext({
      sessionId: host.logSessionId || host.createLogSessionId(),
      attempt: host.connectionAttempt
    });
    host.protocolLogger.write(stage, message, host.resolveProtocolLogLevel(message, level));
}

export function createLogSessionId(host: IndexHost): string {
    const digits = formatLocalTimestamp().replace(/\D/g, '');
    return digits.length >= 14 ? digits.slice(0, 14) : Date.now().toString();
}

export function resolveProtocolLogLevel(host: IndexHost, message: string, requested: ProtocolLogLevel): ProtocolLogLevel {
    if (requested !== 'INFO') {
      return requested;
    }
    if (/^(?:ERROR|错误)[:：\s]|\b(?:failed|failure|exception|error)\b|失败|异常/i.test(message)) {
      return 'ERROR';
    }
    if (/^(?:WARN|警告)[:：\s]|\b(?:timeout|timed out|not found|missing)\b|超时|未收到|未发现|缺少有效|身份冲突|诊断模式跳过/i.test(message)) {
      return 'WARN';
    }
    return 'INFO';
}

export function protocolStage(host: IndexHost, message: string): string {
    if (/MFi|certificate|证书|challenge/i.test(message)) {
      return 'mfi';
    }
    if (/Bluetooth|RFCOMM|iAP2|0x[0-9a-f]{4}/i.test(message)) {
      return 'iap2';
    }
    if (/Wi-?Fi|热点|SSID/i.test(message)) {
      return 'wifi';
    }
    if (/mDNS|Bonjour|邀请/i.test(message)) {
      return 'mdns';
    }
    if (/AirPlay|RTSP|pair-|配对|RECORD/i.test(message)) {
      return 'airplay';
    }
    return 'session';
}

export function showError(host: IndexHost, error: Error | Object): void {
    const message = host.errorMessage(error);
    host.statusMessage = message;
    host.logProtocol(host.protocolStage(message), message, 'ERROR');
    void promptAction.showToast({ message });
}

export function errorMessage(host: IndexHost, error: Error | Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    const details = error as ApiErrorDetails;
    const parts: string[] = [];
    if (details.code !== undefined) {
      parts.push(`code=${details.code}`);
    }
    if (details.message) {
      parts.push(details.message);
    }
    return parts.length > 0 ? parts.join(': ') : JSON.stringify(error) || String(error);
}

export function errorDetails(host: IndexHost, error: Error | Object): string {
    if (error instanceof Error) {
      return error.stack ? `${error.message}\n${error.stack}` : error.message;
    }
    return host.errorMessage(error);
}
