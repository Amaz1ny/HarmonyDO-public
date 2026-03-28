import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import fileIo from '@ohos.file.fs';
import { AppContext } from './AppContext';

const TAG: string = 'AppLogService';
const DEFAULT_FILE_NAME: string = 'app_logs.jsonl';
const DEFAULT_MAX_BYTES: number = 512 * 1024;

export type AppLogLevel = 'info' | 'warning' | 'error';
export type AppLogType = 'lifecycle' | 'general';

export interface AppLogEntry {
  timestamp: string;
  level: AppLogLevel;
  type: AppLogType;
  message: string;
  tag?: string;
  details?: string;
}

export interface AppLogFileAdapter {
  readText(): string;
  writeText(text: string): void;
  clear(): void;
}

class DefaultAppLogFileAdapter implements AppLogFileAdapter {
  private getPath(): string {
    const ctx = AppContext.getUIAbilityContext();
    const cacheDir: string = ctx !== null ? ctx.cacheDir : '';
    if (cacheDir.length > 0) {
      return `${cacheDir}/${DEFAULT_FILE_NAME}`;
    }
    return DEFAULT_FILE_NAME;
  }

  readText(): string {
    try {
      const file = fileIo.openSync(this.getPath(), fileIo.OpenMode.READ_ONLY);
      try {
        const stat: fileIo.Stat = fileIo.statSync(file.fd);
        const size: number = stat.size > 0 ? stat.size : 0;
        if (size <= 0) {
          return '';
        }
        const buffer: ArrayBuffer = new ArrayBuffer(size);
        const bytesRead: number = fileIo.readSync(file.fd, buffer);
        if (bytesRead <= 0) {
          return '';
        }
        const decoder: util.TextDecoder = new util.TextDecoder('utf-8', { ignoreBOM: true });
        return decoder.decodeToString(new Uint8Array(buffer).slice(0, bytesRead));
      } finally {
        fileIo.closeSync(file);
      }
    } catch (_) {
      return '';
    }
  }

  writeText(text: string): void {
    const file = fileIo.openSync(
      this.getPath(),
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    try {
      fileIo.writeSync(file.fd, text);
    } finally {
      fileIo.closeSync(file);
    }
  }

  clear(): void {
    this.writeText('');
  }
}

export class AppLogService {
  private static instance: AppLogService | null = null;
  private adapter: AppLogFileAdapter;
  private maxBytes: number;

  static getInstance(): AppLogService {
    if (AppLogService.instance === null) {
      AppLogService.instance = new AppLogService(new DefaultAppLogFileAdapter(), DEFAULT_MAX_BYTES);
    }
    return AppLogService.instance;
  }

  constructor(adapter: AppLogFileAdapter, maxBytes: number = DEFAULT_MAX_BYTES) {
    this.adapter = adapter;
    this.maxBytes = maxBytes;
  }

  write(entry: AppLogEntry): void {
    try {
      const serialized: string = JSON.stringify(entry);
      const current: string = this.adapter.readText();
      const merged: string = current.length > 0 ? `${current}\n${serialized}` : serialized;
      this.adapter.writeText(this.trimToMaxBytes(merged));
    } catch (err) {
      hilog.warn(0x0000, TAG, 'write failed: %{public}s', JSON.stringify(err));
    }
  }

  info(type: AppLogType, message: string, tag: string = '', details: string = ''): void {
    this.write(this.makeEntry('info', type, message, tag, details));
  }

  warning(type: AppLogType, message: string, tag: string = '', details: string = ''): void {
    this.write(this.makeEntry('warning', type, message, tag, details));
  }

  error(type: AppLogType, message: string, tag: string = '', details: string = ''): void {
    this.write(this.makeEntry('error', type, message, tag, details));
  }

  readEntries(): AppLogEntry[] {
    const content: string = this.adapter.readText();
    if (content.trim().length === 0) {
      return [];
    }

    const lines: string[] = content.split('\n');
    const rows: AppLogEntry[] = [];
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      try {
        const parsed: AppLogEntry = JSON.parse(line) as AppLogEntry;
        if (parsed.timestamp !== undefined && parsed.message !== undefined) {
          rows.push(parsed);
        }
      } catch (_) {
      }
    }

    return rows.reverse();
  }

  clear(): void {
    try {
      this.adapter.clear();
    } catch (err) {
      hilog.warn(0x0000, TAG, 'clear failed: %{public}s', JSON.stringify(err));
    }
  }

  private makeEntry(level: AppLogLevel, type: AppLogType, message: string, tag: string, details: string): AppLogEntry {
    const safeMessage: string = message !== undefined && message !== null ? message.trim() : '';
    const safeTag: string = tag !== undefined && tag !== null ? tag.trim() : '';
    const safeDetails: string = details !== undefined && details !== null ? details.trim() : '';

    return {
      timestamp: new Date().toISOString(),
      level,
      type,
      message: safeMessage,
      tag: safeTag.length > 0 ? safeTag : undefined,
      details: safeDetails.length > 0 ? safeDetails : undefined
    };
  }

  private trimToMaxBytes(content: string): string {
    if (content.length <= this.maxBytes) {
      return content;
    }

    const lines: string[] = content.split('\n');
    let start: number = 0;
    let result: string = content;

    while (result.length > this.maxBytes && start < lines.length - 1) {
      start = start + 1;
      result = lines.slice(start).join('\n');
    }

    return result;
  }
}
