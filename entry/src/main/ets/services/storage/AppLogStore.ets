import { PreferencesUtil } from './PreferencesUtil';

export class AppLogEntry {
  id: number = 0;
  createdAt: string = '';
  level: string = 'INFO';
  tag: string = '';
  message: string = '';

  static fromJson(json: Record<string, Object>): AppLogEntry {
    const entry: AppLogEntry = new AppLogEntry();
    const idVal = json['id'];
    const createdAtVal = json['createdAt'];
    const levelVal = json['level'];
    const tagVal = json['tag'];
    const messageVal = json['message'];
    entry.id = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : Date.now();
    entry.createdAt = createdAtVal !== undefined && createdAtVal !== null ? createdAtVal.toString() : '';
    entry.level = levelVal !== undefined && levelVal !== null ? levelVal.toString() : 'INFO';
    entry.tag = tagVal !== undefined && tagVal !== null ? tagVal.toString() : '';
    entry.message = messageVal !== undefined && messageVal !== null ? messageVal.toString() : '';
    return entry;
  }

  toJson(): Record<string, Object> {
    const json: Record<string, Object> = {};
    json['id'] = this.id;
    json['createdAt'] = this.createdAt;
    json['level'] = this.level;
    json['tag'] = this.tag;
    json['message'] = this.message;
    return json;
  }
}

const LOG_KEY: string = 'app_logs.entries';
const LOG_LIMIT: number = 200;

export class AppLogStore {
  private static instance: AppLogStore | null = null;
  private entries: AppLogEntry[] = [];
  private listeners: Set<() => void> = new Set();
  private initPromise: Promise<void> | null = null;

  static getInstance(): AppLogStore {
    if (AppLogStore.instance === null) {
      AppLogStore.instance = new AppLogStore();
    }
    return AppLogStore.instance;
  }

  ensureInit(): Promise<void> {
    if (this.initPromise !== null) {
      return this.initPromise;
    }
    this.initPromise = (async () => {
      await PreferencesUtil.ensureInit();
      const raw: string = await PreferencesUtil.getString(LOG_KEY, '[]');
      try {
        const parsed: Object = JSON.parse(raw) as Object;
        if (Array.isArray(parsed)) {
          const arr: Object[] = parsed as Object[];
          const next: AppLogEntry[] = [];
          for (let i: number = 0; i < arr.length; i++) {
            const item: Object = arr[i];
            if (item === null || item === undefined || typeof item !== 'object') {
              continue;
            }
            next.push(AppLogEntry.fromJson(item as Record<string, Object>));
          }
          this.entries = next;
        }
      } catch (_) {
        this.entries = [];
      }
    })();
    return this.initPromise;
  }

  addListener(listener: () => void): void {
    this.listeners.add(listener);
  }

  removeListener(listener: () => void): void {
    this.listeners.delete(listener);
  }

  snapshot(): AppLogEntry[] {
    const copy: AppLogEntry[] = [];
    for (let i: number = 0; i < this.entries.length; i++) {
      copy.push(this.entries[i]);
    }
    return copy;
  }

  append(level: string, tag: string, message: string): void {
    const normalizedMessage: string = message.trim();
    if (normalizedMessage.length === 0) {
      return;
    }
    this.ensureInit().then(() => {
      const entry: AppLogEntry = new AppLogEntry();
      entry.id = Date.now();
      entry.createdAt = new Date().toISOString();
      entry.level = level.trim().length > 0 ? level.trim().toUpperCase() : 'INFO';
      entry.tag = tag.trim();
      entry.message = normalizedMessage;
      this.entries.unshift(entry);
      if (this.entries.length > LOG_LIMIT) {
        this.entries = this.entries.slice(0, LOG_LIMIT);
      }
      this.persist().catch(() => {
      });
      this.notifyChanged();
    }).catch(() => {
    });
  }

  info(tag: string, message: string): void {
    this.append('INFO', tag, message);
  }

  warn(tag: string, message: string): void {
    this.append('WARN', tag, message);
  }

  error(tag: string, message: string): void {
    this.append('ERROR', tag, message);
  }

  async clear(): Promise<void> {
    await this.ensureInit();
    this.entries = [];
    await PreferencesUtil.putString(LOG_KEY, '[]');
    this.notifyChanged();
  }

  exportText(): string {
    const lines: string[] = [];
    for (let i: number = 0; i < this.entries.length; i++) {
      const entry: AppLogEntry = this.entries[i];
      lines.push(`[${entry.createdAt}] [${entry.level}] [${entry.tag}] ${entry.message}`);
    }
    return lines.join('\n');
  }

  private async persist(): Promise<void> {
    const arr: Object[] = [];
    for (let i: number = 0; i < this.entries.length; i++) {
      arr.push(this.entries[i].toJson());
    }
    await PreferencesUtil.putString(LOG_KEY, JSON.stringify(arr));
  }

  private notifyChanged(): void {
    this.listeners.forEach((listener: () => void) => {
      listener();
    });
  }
}
