import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { AppConstants } from '../../common/constants/AppConstants';
import { PreferencesUtil } from '../storage/PreferencesUtil';

const TAG: string = 'CookieStore';
const DEFAULT_COOKIE_PATH: string = '/';
const DEFAULT_SYNC_URLS: string[] = ['https://linux.do', 'https://ping.linux.do'];

export interface CookieRecord {
  name: string;
  value: string;
  domain: string;
  path: string;
  secure: boolean;
  httpOnly: boolean;
  hostOnly: boolean;
  sourceHost: string;
  expiresAt: number;
  updatedAt: number;
}

/**
 * 更接近 FluxDO CookieJar 的轻量 Cookie Store。
 *
 * 当前 ArkWeb 只能直接读出 `Cookie` header 字符串，拿不到完整 cookie 对象，
 * 因此这里采用“能保留的元数据尽量保留”的策略：
 * - `Set-Cookie` 响应：保留 domain/path/httpOnly/secure/expires
 * - WebView `fetchCookieSync()`：按当前 URL 视为 host-only cookie 回灌
 * - 对外仍保留 `getCookieHeader()/getCookieValue()` 等兼容接口
 */
export class CookieStore {
  private static instance: CookieStore | null = null;
  private static readonly PREF_KEY: string = 'cookie_store_v1';

  private inited: boolean = false;
  private cookies: Map<string, CookieRecord> = new Map();
  private persistTimerId: number = -1;

  private constructor() {
  }

  static getInstance(): CookieStore {
    if (CookieStore.instance === null) {
      CookieStore.instance = new CookieStore();
    }
    return CookieStore.instance;
  }

  async init(): Promise<void> {
    if (this.inited) return;
    try {
      await PreferencesUtil.ensureInit();
      const raw: string = await PreferencesUtil.getString(CookieStore.PREF_KEY, '{}');
      const parsed: Object = JSON.parse(raw) as Object;
      this.restoreFromParsed(parsed);
      this.pruneExpiredRecords(false);
      hilog.info(0x0000, TAG, 'Initialized, cookie record count=%{public}d', this.cookies.size);
      this.inited = true;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Init failed: %{public}s', JSON.stringify(err));
      // 失败时不标记 inited，避免“早于 Preferences 初始化”导致永远读不到持久化 cookie
    }
  }

  getCookieHeader(url: string = AppConstants.BASE_URL): string {
    this.pruneExpiredRecords();
    const selected: Map<string, CookieRecord> = this.collectSelectedCookies(url);
    const names: string[] = [];
    selected.forEach((_: CookieRecord, name: string) => {
      names.push(name);
    });
    names.sort();

    const parts: string[] = [];
    for (let i = 0; i < names.length; i++) {
      const name: string = names[i];
      const record: CookieRecord | undefined = selected.get(name);
      if (record !== undefined && record.value.length > 0) {
        parts.push(`${record.name}=${record.value}`);
      }
    }
    return parts.join('; ');
  }

  getCookieValue(name: string, url: string = AppConstants.BASE_URL): string | null {
    this.pruneExpiredRecords();
    const selected: Map<string, CookieRecord> = this.collectSelectedCookies(url);
    const record: CookieRecord | undefined = selected.get(name);
    return record !== undefined ? record.value : null;
  }

  getAllCookies(url: string = AppConstants.BASE_URL): Record<string, string> {
    const out: Record<string, string> = {};
    const selected: Map<string, CookieRecord> = this.collectSelectedCookies(url);
    selected.forEach((record: CookieRecord, name: string) => {
      out[name] = record.value;
    });
    return out;
  }

  getCookieRecord(name: string, url: string = AppConstants.BASE_URL): CookieRecord | null {
    this.pruneExpiredRecords();
    const selected: Map<string, CookieRecord> = this.collectSelectedCookies(url);
    const record: CookieRecord | undefined = selected.get(name);
    return record !== undefined ? this.cloneRecord(record) : null;
  }

  upsert(name: string, value: string, url: string = AppConstants.BASE_URL): void {
    const record: CookieRecord | null = this.createHostOnlyRecord(name, value, url, false);
    if (record === null) return;
    this.upsertRecord(record);
  }

  restoreCookieRecord(record: CookieRecord | null): void {
    if (record === null || record.value.trim().length === 0) {
      return;
    }
    this.upsertRecord(this.cloneRecord(record));
  }

  delete(name: string): void {
    const keys: string[] = this.collectKeys();
    let changed: boolean = false;
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const record: CookieRecord | undefined = this.cookies.get(key);
      if (record !== undefined && record.name === name) {
        this.cookies.delete(key);
        changed = true;
      }
    }
    if (changed) {
      this.schedulePersist();
    }
  }

  clearAll(): void {
    if (this.cookies.size === 0) return;
    this.cookies.clear();
    this.schedulePersist();
  }

  syncToWebView(urls: string[] = DEFAULT_SYNC_URLS): void {
    this.pruneExpiredRecords();
    try {
      const keys: string[] = this.collectKeys();
      for (let i = 0; i < keys.length; i++) {
        const key: string = keys[i];
        const record: CookieRecord | undefined = this.cookies.get(key);
        if (record === undefined || record.value.length === 0) {
          continue;
        }
        const targetUrls: string[] = this.resolveSyncTargetUrls(record, urls);
        const cookieConfig: string = this.buildCookieConfig(record);
        for (let j = 0; j < targetUrls.length; j++) {
          this.configCookieToWebView(targetUrls[j], cookieConfig, record.httpOnly);
        }
      }
      this.flushWebViewCookies();
    } catch (err) {
      hilog.error(0x0000, TAG, 'syncToWebView failed: %{public}s', JSON.stringify(err));
    }
  }

  syncFromWebView(urls: string[] = DEFAULT_SYNC_URLS): string {
    try {
      for (let i = 0; i < urls.length; i++) {
        const url: string = urls[i];
        this.ingestWebViewCookieHeader(url, true);
        this.ingestWebViewCookieHeader(url, false);
      }
      return this.getCookieHeader(AppConstants.BASE_URL);
    } catch (err) {
      hilog.error(0x0000, TAG, 'syncFromWebView failed: %{public}s', JSON.stringify(err));
      return this.getCookieHeader(AppConstants.BASE_URL);
    }
  }

  /**
   * 从标准 Cookie header 合并（形如：a=b; c=d）
   */
  ingestCookieHeader(cookieHeader: string, url: string = AppConstants.BASE_URL, httpOnly: boolean = false): void {
    const raw: string = cookieHeader.trim();
    if (raw.length === 0) return;
    const parts: string[] = raw.split(';');
    for (let i = 0; i < parts.length; i++) {
      const item: string = parts[i].trim();
      if (item.length === 0) continue;
      const eq: number = item.indexOf('=');
      if (eq <= 0) continue;
      const name: string = item.substring(0, eq).trim();
      const value: string = item.substring(eq + 1).trim();
      if (name.length === 0) continue;
      if (value.length === 0) {
        this.delete(name);
        continue;
      }
      const record: CookieRecord | null = this.createHostOnlyRecord(name, value, url, httpOnly);
      if (record !== null) {
        this.upsertRecord(record);
      }
    }
  }

  /**
   * 从 Set-Cookie 合并（支持多个 cookie 合并到一个 header 字符串）
   */
  ingestSetCookieHeader(setCookieValue: string, requestUrl: string = AppConstants.BASE_URL): void {
    const raw: string = setCookieValue.trim();
    if (raw.length === 0) return;

    const chunks: string[] = CookieStore.splitSetCookieHeader(raw);
    for (let i = 0; i < chunks.length; i++) {
      const chunk: string = chunks[i].trim();
      if (chunk.length === 0) continue;
      this.ingestSingleSetCookie(chunk, requestUrl);
    }
  }

  ingestSetCookieHeaders(values: string[], requestUrl: string = AppConstants.BASE_URL): void {
    for (let i = 0; i < values.length; i++) {
      this.ingestSetCookieHeader(values[i], requestUrl);
    }
  }

  private restoreFromParsed(parsed: Object): void {
    if (parsed === null || typeof parsed !== 'object') {
      return;
    }
    const obj: Record<string, Object> = parsed as Record<string, Object>;
    const keys: string[] = Object.keys(obj);
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const value: Object = obj[key];
      if (typeof value === 'string') {
        const legacy: CookieRecord | null = this.createHostOnlyRecord(key, value as string, AppConstants.BASE_URL, false);
        if (legacy !== null) {
          this.cookies.set(this.buildRecordKey(legacy), legacy);
        }
        continue;
      }
      if (value === null || value === undefined || typeof value !== 'object') {
        continue;
      }
      const record: CookieRecord | null = this.recordFromJson(value as Record<string, Object>);
      if (record !== null && record.value.length > 0) {
        this.cookies.set(this.buildRecordKey(record), record);
      }
    }
  }

  private recordFromJson(json: Record<string, Object>): CookieRecord | null {
    const name: string = this.readString(json, 'name');
    const value: string = this.readString(json, 'value');
    if (name.length === 0 || value.length === 0) {
      return null;
    }

    const hostOnly: boolean = this.readBoolean(json, 'hostOnly');
    const sourceHostRaw: string = this.readString(json, 'sourceHost');
    const sourceHost: string = sourceHostRaw.length > 0
      ? CookieStore.normalizeHost(sourceHostRaw)
      : CookieStore.extractHost(AppConstants.BASE_URL);
    const domain: string = CookieStore.normalizeDomain(this.readString(json, 'domain'));
    const path: string = CookieStore.normalizePath(this.readString(json, 'path'));

    const record: CookieRecord = {
      name: name,
      value: value,
      domain: hostOnly ? '' : domain,
      path: path,
      secure: this.readBoolean(json, 'secure'),
      httpOnly: this.readBoolean(json, 'httpOnly'),
      hostOnly: hostOnly,
      sourceHost: sourceHost,
      expiresAt: this.readNumber(json, 'expiresAt'),
      updatedAt: this.readNumber(json, 'updatedAt')
    };
    if (record.updatedAt <= 0) {
      record.updatedAt = Date.now();
    }
    return record;
  }

  private readString(json: Record<string, Object>, key: string): string {
    const value: Object = json[key];
    if (value === undefined || value === null) return '';
    return value.toString().trim();
  }

  private readBoolean(json: Record<string, Object>, key: string): boolean {
    const value: Object = json[key];
    if (value === undefined || value === null) return false;
    const text: string = value.toString().trim().toLowerCase();
    return text === 'true' || text === '1';
  }

  private readNumber(json: Record<string, Object>, key: string): number {
    const value: Object = json[key];
    if (value === undefined || value === null) return 0;
    const num: number = Number(value.toString());
    return isNaN(num) ? 0 : num;
  }

  private collectKeys(): string[] {
    const keys: string[] = [];
    this.cookies.forEach((_: CookieRecord, key: string) => {
      keys.push(key);
    });
    return keys;
  }

  private pruneExpiredRecords(schedulePersist: boolean = true): void {
    const now: number = Date.now();
    const keys: string[] = this.collectKeys();
    let changed: boolean = false;
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const record: CookieRecord | undefined = this.cookies.get(key);
      if (record !== undefined && record.expiresAt > 0 && record.expiresAt <= now) {
        this.cookies.delete(key);
        changed = true;
      }
    }
    if (changed && schedulePersist) {
      this.schedulePersist();
    }
  }

  private collectSelectedCookies(url: string): Map<string, CookieRecord> {
    const selected: Map<string, CookieRecord> = new Map();
    const host: string = CookieStore.extractHost(url);
    const path: string = CookieStore.extractPath(url);
    const https: boolean = CookieStore.isHttpsUrl(url);
    const keys: string[] = this.collectKeys();

    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const record: CookieRecord | undefined = this.cookies.get(key);
      if (record === undefined) continue;
      if (!this.matchesRequest(record, host, path, https)) continue;

      const current: CookieRecord | undefined = selected.get(record.name);
      if (current === undefined || this.shouldPreferRecord(record, current)) {
        selected.set(record.name, record);
      }
    }
    return selected;
  }

  private matchesRequest(record: CookieRecord, host: string, path: string, https: boolean): boolean {
    if (record.secure && !https) return false;
    if (record.hostOnly) {
      if (CookieStore.normalizeHost(record.sourceHost) !== host) return false;
    } else {
      if (!CookieStore.matchesDomain(host, record.domain)) return false;
    }
    return CookieStore.matchesPath(path, record.path);
  }

  private shouldPreferRecord(next: CookieRecord, current: CookieRecord): boolean {
    if (next.hostOnly !== current.hostOnly) {
      return !next.hostOnly;
    }
    if (next.path.length !== current.path.length) {
      return next.path.length > current.path.length;
    }
    return next.updatedAt >= current.updatedAt;
  }

  private createHostOnlyRecord(name: string, value: string, url: string, httpOnly: boolean): CookieRecord | null {
    const n: string = name.trim();
    const v: string = value.trim();
    if (n.length === 0 || v.length === 0) {
      return null;
    }
    const host: string = CookieStore.extractHost(url);
    return {
      name: n,
      value: v,
      domain: '',
      path: DEFAULT_COOKIE_PATH,
      secure: CookieStore.isHttpsUrl(url),
      httpOnly: httpOnly,
      hostOnly: true,
      sourceHost: host,
      expiresAt: 0,
      updatedAt: Date.now()
    };
  }

  private cloneRecord(record: CookieRecord): CookieRecord {
    return {
      name: record.name,
      value: record.value,
      domain: record.domain,
      path: record.path,
      secure: record.secure,
      httpOnly: record.httpOnly,
      hostOnly: record.hostOnly,
      sourceHost: record.sourceHost,
      expiresAt: record.expiresAt,
      updatedAt: record.updatedAt
    };
  }

  private upsertRecord(record: CookieRecord): void {
    const key: string = this.buildRecordKey(record);
    const existing: CookieRecord | undefined = this.cookies.get(key);
    if (existing !== undefined) {
      record.httpOnly = record.httpOnly || existing.httpOnly;
      if (record.expiresAt <= 0) {
        record.expiresAt = existing.expiresAt;
      }
    }
    this.cookies.set(key, record);
    this.schedulePersist();
  }

  private buildRecordKey(record: CookieRecord): string {
    const scope: string = record.hostOnly
      ? `host:${CookieStore.normalizeHost(record.sourceHost)}`
      : `domain:${CookieStore.normalizeDomain(record.domain)}`;
    return `${record.name}|${scope}|${CookieStore.normalizePath(record.path)}`;
  }

  private ingestWebViewCookieHeader(url: string, includeHttpOnly: boolean): void {
    try {
      const raw: string = webview.WebCookieManager.fetchCookieSync(url, includeHttpOnly);
      if (raw.length > 0) {
        this.ingestCookieHeader(raw, url, includeHttpOnly);
      }
    } catch (_) {
    }
  }

  private resolveSyncTargetUrls(record: CookieRecord, preferredUrls: string[]): string[] {
    const out: string[] = [];
    if (record.hostOnly) {
      this.pushUniqueUrl(out, `https://${CookieStore.normalizeHost(record.sourceHost)}`);
      return out;
    }

    const domain: string = CookieStore.normalizeDomain(record.domain);
    if (domain.length === 0) {
      this.pushUniqueUrl(out, AppConstants.BASE_URL);
      return out;
    }

    const exactUrl: string = `https://${domain}`;
    this.pushUniqueUrl(out, exactUrl);
    for (let i = 0; i < preferredUrls.length; i++) {
      const url: string = preferredUrls[i];
      const host: string = CookieStore.extractHost(url);
      if (CookieStore.matchesDomain(host, domain)) {
        this.pushUniqueUrl(out, `https://${host}`);
      }
    }
    return out;
  }

  private pushUniqueUrl(urls: string[], url: string): void {
    for (let i = 0; i < urls.length; i++) {
      if (urls[i] === url) return;
    }
    urls.push(url);
  }

  private buildCookieConfig(record: CookieRecord): string {
    const parts: string[] = [];
    parts.push(`${record.name}=${record.value}`);
    parts.push(`Path=${CookieStore.normalizePath(record.path)}`);
    if (!record.hostOnly) {
      const normalizedDomain: string = CookieStore.normalizeDomain(record.domain);
      if (normalizedDomain.length > 0) {
        parts.push(`Domain=.${normalizedDomain}`);
      }
    }
    if (record.secure) {
      parts.push('Secure');
    }
    const maxAge: number | null = this.computeMaxAgeSeconds(record);
    if (maxAge !== null) {
      parts.push(`Max-Age=${maxAge.toString()}`);
    }
    return `${parts.join('; ')};`;
  }

  private computeMaxAgeSeconds(record: CookieRecord): number | null {
    if (record.expiresAt <= 0) {
      return null;
    }
    const deltaMs: number = record.expiresAt - Date.now();
    if (deltaMs <= 0) {
      return 0;
    }
    return Math.max(1, Math.floor(deltaMs / 1000));
  }

  private configCookieToWebView(url: string, cookieConfig: string, httpOnly: boolean): void {
    try {
      webview.WebCookieManager.configCookieSync(url, cookieConfig, false, httpOnly);
      return;
    } catch (err) {
      try {
        webview.WebCookieManager.configCookieSync(url, cookieConfig, false);
        return;
      } catch (_) {
      }
      hilog.error(0x0000, TAG, 'Sync cookie to WebView failed: %{public}s', JSON.stringify(err));
    }
  }

  private flushWebViewCookies(): void {
    try {
      webview.WebCookieManager.saveCookieAsync();
    } catch (_) {
    }
  }

  private ingestSingleSetCookie(setCookie: string, requestUrl: string): void {
    const firstSemi: number = setCookie.indexOf(';');
    const head: string = firstSemi >= 0 ? setCookie.substring(0, firstSemi) : setCookie;
    const eq: number = head.indexOf('=');
    if (eq <= 0) return;

    const name: string = head.substring(0, eq).trim();
    const value: string = head.substring(eq + 1).trim();
    if (name.length === 0) return;

    const requestHost: string = CookieStore.extractHost(requestUrl);
    const domainAttr: string = CookieStore.parseAttributeValue(setCookie, 'domain');
    const pathAttr: string = CookieStore.parseAttributeValue(setCookie, 'path');
    const hostOnly: boolean = domainAttr.length === 0;
    const domain: string = hostOnly ? '' : CookieStore.normalizeDomain(domainAttr);
    const sourceHost: string = hostOnly ? requestHost : '';
    const path: string = CookieStore.normalizePath(pathAttr);
    const secure: boolean = CookieStore.hasAttribute(setCookie, 'secure') || CookieStore.isHttpsUrl(requestUrl);
    const httpOnly: boolean = CookieStore.hasAttribute(setCookie, 'httponly');
    const expiresAt: number = CookieStore.parseExpiresAt(setCookie);
    const maxAge: number | null = CookieStore.parseMaxAge(setCookie);

    const shouldDelete: boolean = value.length === 0
      || (maxAge !== null && maxAge <= 0)
      || (expiresAt > 0 && expiresAt <= Date.now());
    if (shouldDelete) {
      this.deleteByScope(name, domain, path, hostOnly, sourceHost);
      return;
    }

    const record: CookieRecord = {
      name: name,
      value: value,
      domain: domain,
      path: path,
      secure: secure,
      httpOnly: httpOnly,
      hostOnly: hostOnly,
      sourceHost: sourceHost,
      expiresAt: maxAge !== null && maxAge > 0 ? Date.now() + maxAge * 1000 : expiresAt,
      updatedAt: Date.now()
    };
    this.upsertRecord(record);
  }

  private deleteByScope(name: string, domain: string, path: string, hostOnly: boolean, sourceHost: string): void {
    const normalizedPath: string = CookieStore.normalizePath(path);
    const normalizedDomain: string = CookieStore.normalizeDomain(domain);
    const normalizedHost: string = CookieStore.normalizeHost(sourceHost);
    const keys: string[] = this.collectKeys();
    let changed: boolean = false;
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const record: CookieRecord | undefined = this.cookies.get(key);
      if (record === undefined || record.name !== name) continue;
      if (CookieStore.normalizePath(record.path) !== normalizedPath) continue;
      if (record.hostOnly !== hostOnly) continue;
      if (hostOnly) {
        if (CookieStore.normalizeHost(record.sourceHost) !== normalizedHost) continue;
      } else {
        if (CookieStore.normalizeDomain(record.domain) !== normalizedDomain) continue;
      }
      this.cookies.delete(key);
      changed = true;
    }
    if (changed) {
      this.schedulePersist();
    }
  }

  private schedulePersist(): void {
    if (this.persistTimerId >= 0) return;
    this.persistTimerId = setTimeout(() => {
      this.persistTimerId = -1;
      this.persist();
    }, 80);
  }

  private async persist(): Promise<void> {
    if (!this.inited) return;
    try {
      const obj: Record<string, Object> = {};
      this.cookies.forEach((record: CookieRecord, key: string) => {
        const item: Record<string, Object> = {};
        item['name'] = record.name;
        item['value'] = record.value;
        item['domain'] = record.domain;
        item['path'] = record.path;
        item['secure'] = record.secure;
        item['httpOnly'] = record.httpOnly;
        item['hostOnly'] = record.hostOnly;
        item['sourceHost'] = record.sourceHost;
        item['expiresAt'] = record.expiresAt;
        item['updatedAt'] = record.updatedAt;
        obj[key] = item as Object;
      });
      await PreferencesUtil.putString(CookieStore.PREF_KEY, JSON.stringify(obj));
    } catch (err) {
      hilog.error(0x0000, TAG, 'Persist failed: %{public}s', JSON.stringify(err));
    }
  }

  private static extractHost(url: string): string {
    const raw: string = url.trim();
    if (raw.length === 0) return 'linux.do';
    let start: number = raw.indexOf('://');
    start = start >= 0 ? start + 3 : 0;
    let end: number = raw.length;
    const slash: number = raw.indexOf('/', start);
    if (slash >= 0 && slash < end) end = slash;
    const question: number = raw.indexOf('?', start);
    if (question >= 0 && question < end) end = question;
    const hash: number = raw.indexOf('#', start);
    if (hash >= 0 && hash < end) end = hash;
    const hostPort: string = raw.substring(start, end);
    const colon: number = hostPort.indexOf(':');
    const host: string = colon >= 0 ? hostPort.substring(0, colon) : hostPort;
    return CookieStore.normalizeHost(host);
  }

  private static extractPath(url: string): string {
    const raw: string = url.trim();
    const schemeIndex: number = raw.indexOf('://');
    const start: number = schemeIndex >= 0 ? schemeIndex + 3 : 0;
    const slash: number = raw.indexOf('/', start);
    if (slash < 0) {
      return DEFAULT_COOKIE_PATH;
    }
    let end: number = raw.length;
    const question: number = raw.indexOf('?', slash);
    if (question >= 0 && question < end) end = question;
    const hash: number = raw.indexOf('#', slash);
    if (hash >= 0 && hash < end) end = hash;
    return CookieStore.normalizePath(raw.substring(slash, end));
  }

  private static isHttpsUrl(url: string): boolean {
    return url.trim().toLowerCase().startsWith('https://');
  }

  private static normalizeHost(host: string): string {
    const out: string = host.trim().toLowerCase();
    if (out.startsWith('.')) {
      return out.substring(1);
    }
    return out;
  }

  private static normalizeDomain(domain: string): string {
    return CookieStore.normalizeHost(domain);
  }

  private static normalizePath(path: string): string {
    const raw: string = path.trim();
    if (raw.length === 0) return DEFAULT_COOKIE_PATH;
    return raw.startsWith('/') ? raw : `/${raw}`;
  }

  private static matchesDomain(host: string, domain: string): boolean {
    const normalizedHost: string = CookieStore.normalizeHost(host);
    const normalizedDomain: string = CookieStore.normalizeDomain(domain);
    if (normalizedDomain.length === 0) return false;
    return normalizedHost === normalizedDomain || normalizedHost.endsWith(`.${normalizedDomain}`);
  }

  private static matchesPath(requestPath: string, cookiePath: string): boolean {
    const normalizedRequestPath: string = CookieStore.normalizePath(requestPath);
    const normalizedCookiePath: string = CookieStore.normalizePath(cookiePath);
    if (normalizedCookiePath === DEFAULT_COOKIE_PATH) return true;
    if (normalizedRequestPath === normalizedCookiePath) return true;
    return normalizedRequestPath.startsWith(`${normalizedCookiePath}/`) || normalizedRequestPath.startsWith(normalizedCookiePath);
  }

  private static hasAttribute(setCookie: string, attributeName: string): boolean {
    const reg: RegExp = new RegExp(`(?:^|;)\\s*${attributeName}(?:=|;|$)`, 'i');
    return reg.test(setCookie);
  }

  private static parseAttributeValue(setCookie: string, attributeName: string): string {
    const reg: RegExp = new RegExp(`(?:^|;)\\s*${attributeName}=([^;]+)`, 'i');
    const match: string[] | null = setCookie.match(reg);
    if (match === null || match.length < 2) return '';
    return match[1].trim();
  }

  private static parseMaxAge(setCookie: string): number | null {
    const raw: string = CookieStore.parseAttributeValue(setCookie, 'max-age');
    if (raw.length === 0) return null;
    const value: number = parseInt(raw);
    if (isNaN(value)) return null;
    return value;
  }

  private static parseExpiresAt(setCookie: string): number {
    const raw: string = CookieStore.parseAttributeValue(setCookie, 'expires');
    if (raw.length === 0) return 0;
    const value: number = Date.parse(raw);
    return isNaN(value) ? 0 : value;
  }

  private static splitSetCookieHeader(value: string): string[] {
    // 兼容：多个 Set-Cookie 被合并为一个字符串；需避开 Expires=Wed, 21 Oct... 的逗号
    const out: string[] = [];
    let buf: string = '';
    let inExpires: boolean = false;

    for (let i = 0; i < value.length; i++) {
      const ch: string = value.charAt(i);
      if (ch === ',') {
        if (!inExpires && CookieStore.isCookieDelimiter(value, i)) {
          if (buf.trim().length > 0) out.push(buf.trim());
          buf = '';
          continue;
        }
      }

      buf += ch;

      if (ch === ';') {
        inExpires = false;
      } else if (ch === '=') {
        const lower: string = buf.toLowerCase();
        if (lower.endsWith('expires=')) {
          inExpires = true;
        }
      }
    }

    if (buf.trim().length > 0) out.push(buf.trim());
    return out;
  }

  private static isCookieDelimiter(value: string, commaIndex: number): boolean {
    let i: number = commaIndex + 1;
    while (i < value.length) {
      const c: string = value.charAt(i);
      if (c !== ' ' && c !== '\t' && c !== '\n' && c !== '\r') break;
      i++;
    }
    if (i >= value.length) return false;

    // 读取 token，直到遇到 '=' 或分隔符；若出现 '='，认为是新 cookie 的开始
    let token: string = '';
    while (i < value.length) {
      const c: string = value.charAt(i);
      if (c === '=') {
        break;
      }
      if (c === ';' || c === ',') {
        return false;
      }
      token += c;
      i++;
    }

    if (i >= value.length) return false;
    if (value.charAt(i) !== '=') return false;

    const trimmed: string = token.trim();
    if (trimmed.length === 0) return false;
    if (trimmed.indexOf(' ') >= 0 || trimmed.indexOf('\t') >= 0) return false;
    return true;
  }
}
