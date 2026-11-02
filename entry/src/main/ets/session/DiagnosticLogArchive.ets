import fileFs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MAX_CONNECTION_LOG_LINES } from './ConnectionLogBuffer';
import { formatLocalClock, formatLocalDateKey } from './LogTimestamp';
import { redactProtocolText } from './ProtocolLogger';

const LOG_DOMAIN: number = 0xCA21;
const LOG_RETENTION_DAYS: number = 10;
const LOG_FILE_PREFIX: string = 'CarPlayer-';
const LOG_FLUSH_INTERVAL_MS: number = 500;
const MAX_PENDING_LOG_LINES: number = 1024;

export class DiagnosticLogArchive {
  private directoryPath: string = '';
  private currentFilePath: string = '';
  private currentDateKey: string = '';
  private currentFd: number = -1;
  private initializationError: string = '';
  private pendingEntries: string[] = [];
  private flushTimer: number = -1;

  start(filesDirectory: string): void {
    if (this.currentFd >= 0) {
      return;
    }
    try {
      this.directoryPath = `${filesDirectory}/CarPlayerLogs`;
      if (!fileFs.accessSync(this.directoryPath)) {
        fileFs.mkdirSync(this.directoryPath, true);
      }
      const now = new Date();
      this.pruneExpiredFiles(now, this.directoryPath);
      this.currentDateKey = formatLocalDateKey(now);
      const currentName = `${LOG_FILE_PREFIX}${this.currentDateKey}.log`;
      this.currentFilePath = `${this.directoryPath}/${currentName}`;
      this.currentFd = fileFs.openSync(
        this.currentFilePath,
        fileFs.OpenMode.WRITE_ONLY | fileFs.OpenMode.CREATE | fileFs.OpenMode.APPEND
      ).fd;
      this.restoreFiles = this.getLogFiles().filter((name: string): boolean => name !== currentName);
      this.append(
        `${formatLocalClock()} INFO diagnostics: Log archive initialized; daily files, retaining ` +
          `${LOG_RETENTION_DAYS} days`
      );
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

  private restoreFiles: string[] = [];

  append(line: string): void {
    if (this.directoryPath) {
      try {
        this.ensureCurrentDay(new Date());
      } catch (error) {
        this.initializationError = this.errorDetails(error);
      }
    }
    if (this.currentFd < 0) {
      hilog.error(
        LOG_DOMAIN,
        'CarPlayerLogArchive',
        'Log archive unavailable; line not persisted (%{public}s): %{public}s',
        this.initializationError || 'file descriptor is closed',
        line
      );
      return;
    }
    try {
      const safeLine = redactProtocolText(line).replace(/\r?\n/g, ' | ');
      const entryLine = /^\[[^\]]+\]/.test(safeLine) ? safeLine : `${formatLocalClock()} ${safeLine}`;
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
        'Log archive queue failed: %{public}s; unpersisted line: %{public}s',
        detail,
        line
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
      const now = new Date();
      this.pruneExpiredFiles(now);
      const currentName = `${LOG_FILE_PREFIX}${formatLocalDateKey(now)}.log`;
      fd = fileFs.openSync(
        `${directoryPath}/${currentName}`,
        fileFs.OpenMode.WRITE_ONLY | fileFs.OpenMode.CREATE | fileFs.OpenMode.APPEND
      ).fd;
      const safeMessage = redactProtocolText(message).replace(/\r?\n/g, ' | ');
      const entry = `${formatLocalClock()} ${level} ${stage}: ${safeMessage}\n`;
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
    this.rotateForRead();
    const lines: string[] = [];
    const currentName = this.currentFilePath.split('/').pop() ?? '';
    const sessionNames = [...this.restoreFiles, currentName].filter((name: string) => name.length > 0).reverse();
    for (const name of sessionNames) {
      if (!name) {
        continue;
      }
      try {
        const contents = fileFs.readTextSync(`${this.directoryPath}/${name}`);
        lines.push(`===== session ${name} =====`);
        lines.push(...contents.split(/\r?\n/).filter((line: string) => line.length > 0).reverse());
      } catch (error) {
        hilog.warn(
          LOG_DOMAIN,
          'CarPlayerLogArchive',
          'Could not restore session log %{public}s: %{public}s',
          name,
          error instanceof Error ? error.message : String(error)
        );
      }
    }
    return lines.slice(0, MAX_CONNECTION_LOG_LINES);
  }

  readAllText(): string {
    this.flush();
    this.rotateForRead();
    const sections: string[] = [];
    const sessionNames = [...this.restoreFiles, this.currentFilePath.split('/').pop() ?? '']
      .filter((name: string) => name.length > 0);
    for (const name of sessionNames) {
      if (!name) {
        continue;
      }
      try {
        const contents = fileFs.readTextSync(`${this.directoryPath}/${name}`);
        const lines = contents.split(/\r?\n/).filter((line: string) => line.length > 0);
        sections.push(`===== ${name} =====\n${lines.join('\n')}`);
      } catch (error) {
        hilog.warn(
          LOG_DOMAIN,
          'CarPlayerLogArchive',
          'Could not read log for export %{public}s: %{public}s',
          name,
          error instanceof Error ? error.message : String(error)
        );
      }
    }
    return sections.join('\n');
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
    this.restoreFiles = [];
    const now = new Date();
    this.currentDateKey = formatLocalDateKey(now);
    this.currentFilePath = `${this.directoryPath}/${LOG_FILE_PREFIX}${this.currentDateKey}.log`;
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

  private ensureCurrentDay(now: Date): void {
    const dateKey = formatLocalDateKey(now);
    if (this.currentFd >= 0 && this.currentDateKey === dateKey) {
      return;
    }
    this.flush();
    const currentName = `${LOG_FILE_PREFIX}${dateKey}.log`;
    const currentFilePath = `${this.directoryPath}/${currentName}`;
    const nextFd = fileFs.openSync(
      currentFilePath,
      fileFs.OpenMode.WRITE_ONLY | fileFs.OpenMode.CREATE | fileFs.OpenMode.APPEND
    ).fd;
    const previousFd = this.currentFd;
    this.currentFd = nextFd;
    this.currentDateKey = dateKey;
    this.currentFilePath = currentFilePath;
    this.pruneExpiredFiles(now);
    this.restoreFiles = this.getLogFiles().filter((name: string): boolean => name !== currentName);
    if (previousFd >= 0) {
      try {
        fileFs.closeSync(previousFd);
      } catch (error) {
        hilog.warn(LOG_DOMAIN, 'CarPlayerLogArchive', 'Could not close previous daily log: %{public}s',
          this.errorDetails(error));
      }
    }
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

  private rotateForRead(): void {
    if (this.currentFd < 0 || !this.directoryPath) {
      return;
    }
    try {
      this.ensureCurrentDay(new Date());
    } catch (error) {
      hilog.warn(
        LOG_DOMAIN,
        'CarPlayerLogArchive',
        'Could not rotate daily log before read: %{public}s',
        this.errorDetails(error instanceof Error ? error : new Error(String(error)))
      );
    }
  }

  private pruneExpiredFiles(now: Date, directoryPath: string = this.directoryPath): void {
    const cutoff = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (LOG_RETENTION_DAYS - 1));
    const cutoffKey = formatLocalDateKey(cutoff);
    const names = fileFs.listFileSync(directoryPath)
      .filter((name: string): boolean => name.startsWith(LOG_FILE_PREFIX) && name.endsWith('.log'))
      .sort();
    for (const name of names) {
      const dailyMatch = /^CarPlayer-(\d{4}-\d{2}-\d{2})\.log$/.exec(name);
      const legacyMatch = /^CarPlayer-(\d{13})\.log$/.exec(name);
      const dateKey = dailyMatch?.[1] ?? (legacyMatch ? formatLocalDateKey(new Date(Number(legacyMatch[1]))) : '');
      if (!dateKey || dateKey < cutoffKey) {
        fileFs.unlinkSync(`${directoryPath}/${name}`);
      }
    }
  }

  private errorDetails(error: Error | Object): string {
    if (error instanceof Error) {
      return error.stack ? `${error.message}\n${error.stack}` : error.message;
    }
    return String(error);
  }
}

export const diagnosticLogArchive: DiagnosticLogArchive = new DiagnosticLogArchive();