import fileFs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MAX_CONNECTION_LOG_LINES } from './ConnectionLogBuffer';
import { formatLocalClock } from './LogTimestamp';
import { redactProtocolText } from './ProtocolLogger';

const LOG_DOMAIN: number = 0xCA21;
const LOG_FILE_PREFIX: string = 'CarPlayer-';
const LOG_FILE_NAME: string = 'CarPlayer-current.log';
const LOG_FLUSH_INTERVAL_MS: number = 500;
const MAX_PENDING_LOG_LINES: number = 1024;
const LOG_HEADER: RegExp = /^\[[^\]]+\](?:\s|$)/;

function isLogHeader(line: string): boolean {
  return LOG_HEADER.test(line);
}

function indentLogContinuation(line: string): string {
  const lines = line.replace(/\r/g, '').split('\n');
  if (lines.length < 2) {
    return lines[0] ?? '';
  }
  return [lines[0], ...lines.slice(1).map((part: string): string =>
    part.startsWith('    ') ? part : `    ${part}`
  )].join('\n');
}

function splitLogBlocks(contents: string): string[] {
  const blocks: string[] = [];
  let current: string[] = [];
  for (const line of contents.split(/\r?\n/)) {
    if (line.length === 0) {
      continue;
    }
    if (isLogHeader(line) && current.length > 0) {
      blocks.push(current.join('\n'));
      current = [];
    }
    current.push(line);
  }
  if (current.length > 0) {
    blocks.push(current.join('\n'));
  }
  return blocks;
}

export class DiagnosticLogArchive {
  private directoryPath: string = '';
  private currentFilePath: string = '';
  private currentFd: number = -1;
  private initializationError: string = '';
  private pendingEntries: string[] = [];
  private flushTimer: number = -1;

  start(filesDirectory: string): void {
    if (this.currentFd >= 0) {
      try {
        this.flush();
        fileFs.closeSync(this.currentFd);
      } catch (error) {
        this.initializationError = this.errorDetails(error instanceof Error ? error : new Error(String(error)));
        return;
      }
      this.currentFd = -1;
    }
    try {
      this.directoryPath = `${filesDirectory}/CarPlayerLogs`;
      if (!fileFs.accessSync(this.directoryPath)) {
        fileFs.mkdirSync(this.directoryPath, true);
      }
      for (const name of this.getLogFiles()) {
        fileFs.unlinkSync(`${this.directoryPath}/${name}`);
      }
      this.currentFilePath = `${this.directoryPath}/${LOG_FILE_NAME}`;
      this.currentFd = fileFs.openSync(
        this.currentFilePath,
        fileFs.OpenMode.WRITE_ONLY | fileFs.OpenMode.CREATE | fileFs.OpenMode.APPEND
      ).fd;
      this.append(`${formatLocalClock()} INFO diagnostics: Log archive initialized for current app session`);
    } catch (error) {
      this.currentFd = -1;
      this.initializationError = this.errorDetails(error);
      hilog.error(
        LOG_DOMAIN,
        'CarPlayerLogArchive',
        'Log archive initialization failed: %{public}s',
        this.initializationError
      );
    }
  }

  append(line: string): void {
    if (this.currentFd < 0) {
      hilog.error(
        LOG_DOMAIN,
        'CarPlayerLogArchive',
        'Log archive unavailable; entry not persisted (%{public}s)',
        this.initializationError || 'file descriptor is closed'
      );
      return;
    }
    try {
      const safeLine = indentLogContinuation(redactProtocolText(line));
      const lines = safeLine.split('\n');
      const entryLine = isLogHeader(lines[0] ?? '')
        ? safeLine
        : [`${formatLocalClock()} ${lines[0] ?? ''}`, ...lines.slice(1)].join('\n');
      this.pendingEntries.push(entryLine);
      if (this.pendingEntries.length >= MAX_PENDING_LOG_LINES) {
        this.flushPendingBestEffort();
      } else {
        this.scheduleFlush();
      }
    } catch (error) {
      const detail = this.errorDetails(error);
      hilog.error(
        LOG_DOMAIN,
        'CarPlayerLogArchive',
        'Log archive queue failed; entry not persisted: %{public}s',
        detail
      );
    }
  }

  flush(): void {
    if (this.flushTimer >= 0) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
    try {
      this.flushPendingEntries();
    } catch (error) {
      this.scheduleFlush();
      throw new Error(this.errorDetails(error instanceof Error ? error : new Error(String(error))));
    }
  }

  appendFromAbility(filesDirectory: string, stage: string, message: string, level: string = 'INFO'): void {
    const directoryPath = `${filesDirectory}/CarPlayerLogs`;
    let fd = -1;
    try {
      this.flush();
      if (!fileFs.accessSync(directoryPath)) {
        fileFs.mkdirSync(directoryPath, true);
      }
      fd = fileFs.openSync(
        `${directoryPath}/${LOG_FILE_NAME}`,
        fileFs.OpenMode.WRITE_ONLY | fileFs.OpenMode.CREATE | fileFs.OpenMode.APPEND
      ).fd;
      const safeMessage = indentLogContinuation(redactProtocolText(message));
      const lines = safeMessage.split('\n');
      const entry = [
        `${formatLocalClock()} ${level} ${stage}: ${lines[0] ?? ''}`,
        ...lines.slice(1)
      ].join('\n') + '\n';
      fileFs.writeSync(fd, entry);
      fileFs.fsyncSync(fd);
    } catch (error) {
      hilog.warn(
        LOG_DOMAIN,
        'CarPlayerLogArchive',
        'Could not append external ability log: %{public}s',
        this.errorDetails(error instanceof Error ? error : new Error(String(error)))
      );
    } finally {
      if (fd >= 0) {
        try {
          fileFs.closeSync(fd);
        } catch (error) {
          hilog.warn(
            LOG_DOMAIN,
            'CarPlayerLogArchive',
            'Could not close external ability log: %{public}s',
            this.errorDetails(error instanceof Error ? error : new Error(String(error)))
          );
        }
      }
    }
  }

  readRecentLines(): string[] {
    this.flushPendingBestEffort();
    const lines: string[] = [];
    if (!this.currentFilePath) {
      return lines;
    }
    try {
      const contents = fileFs.readTextSync(this.currentFilePath);
      const blocks = splitLogBlocks(contents);
      lines.push('===== current app session =====');
      lines.push(...blocks.slice(-MAX_CONNECTION_LOG_LINES).reverse());
    } catch (error) {
      hilog.warn(
        LOG_DOMAIN,
        'CarPlayerLogArchive',
        'Could not read current app session log: %{public}s',
        error instanceof Error ? error.message : String(error)
      );
    }
    return lines;
  }

  readAllText(): string {
    this.flush();
    if (!this.currentFilePath) {
      return '';
    }
    try {
      return fileFs.readTextSync(this.currentFilePath);
    } catch (error) {
      hilog.warn(
        LOG_DOMAIN,
        'CarPlayerLogArchive',
        'Could not read current app session log: %{public}s',
        error instanceof Error ? error.message : String(error)
      );
      return '';
    }
  }

  clear(): void {
    if (!this.directoryPath) {
      throw new Error('Log archive is not initialized');
    }
    if (this.flushTimer >= 0) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
    this.pendingEntries = [];
    if (this.currentFd >= 0) {
      fileFs.closeSync(this.currentFd);
      this.currentFd = -1;
    }
    for (const name of this.getLogFiles()) {
      fileFs.unlinkSync(`${this.directoryPath}/${name}`);
    }
    this.currentFilePath = `${this.directoryPath}/${LOG_FILE_NAME}`;
    this.currentFd = fileFs.openSync(
      this.currentFilePath,
      fileFs.OpenMode.WRITE_ONLY | fileFs.OpenMode.CREATE | fileFs.OpenMode.APPEND
    ).fd;
    this.initializationError = '';
  }

  private getLogFiles(): string[] {
    return fileFs.listFileSync(this.directoryPath)
      .filter((name: string): boolean => name.startsWith(LOG_FILE_PREFIX) && name.endsWith('.log'))
      .sort();
  }

  private scheduleFlush(): void {
    if (this.flushTimer >= 0 || this.pendingEntries.length === 0) {
      return;
    }
    this.flushTimer = setTimeout((): void => {
      this.flushTimer = -1;
      this.flushPendingBestEffort();
    }, LOG_FLUSH_INTERVAL_MS);
  }

  private flushPendingBestEffort(): void {
    try {
      this.flushPendingEntries();
    } catch (error) {
      hilog.error(
        LOG_DOMAIN,
        'CarPlayerLogArchive',
        'Log archive batch write failed; %{public}d lines remain queued: %{public}s',
        this.pendingEntries.length,
        this.errorDetails(error instanceof Error ? error : new Error(String(error)))
      );
      this.scheduleFlush();
    }
  }

  private flushPendingEntries(): void {
    if (this.pendingEntries.length === 0) {
      return;
    }
    if (this.currentFd < 0) {
      throw new Error(this.initializationError || 'file descriptor is closed');
    }
    const text = `${this.pendingEntries.join('\n')}\n`;
    fileFs.writeSync(this.currentFd, text);
    this.pendingEntries = [];
    fileFs.fsyncSync(this.currentFd);
  }

  private errorDetails(error: Error | Object): string {
    if (error instanceof Error) {
      return error.stack ? `${error.message}\n${error.stack}` : error.message;
    }
    return String(error);
  }
}

export const diagnosticLogArchive: DiagnosticLogArchive = new DiagnosticLogArchive();