import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { HttpClient } from '../network/HttpClient';
import { CfClearanceRefreshService } from '../network/CfClearanceRefreshService';
import { MessageBusService } from './MessageBusService';
import { PreferencesUtil } from '../storage/PreferencesUtil';

const TAG: string = 'PreloadedDataService';
const PRELOAD_PATH: string = '/latest';
const PREF_KEY_LONG_POLLING_BASE_URL: string = 'message_bus_long_polling_base_url_v1';
const PREF_KEY_SHARED_SESSION_KEY: string = 'message_bus_shared_session_key_v1';

/**
 * 预加载数据服务（对齐 FluxDO）
 *
 * 从 Discourse HTML 的 data-preloaded 属性中提取：
 * - siteSettings.long_polling_base_url（MessageBus 独立域名）
 * - topicTrackingStateMeta（各频道初始 message_id）
 * - topicTrackingStates（话题追踪状态，用于 new/unread 计数）
 * - meta.shared_session_key（跨域长轮询认证）
 */
export class PreloadedDataService {
  private static instance: PreloadedDataService | null = null;

  private loaded: boolean = false;
  private inFlight: Promise<void> | null = null;
  private configLoaded: boolean = false;
  private configInFlight: Promise<void> | null = null;
  private configuredFromCache: boolean = false;

  private longPollingBaseUrl: string | null = null;
  private sharedSessionKey: string | null = null;
  private cdnUrl: string | null = null;
  private s3CdnUrl: string | null = null;
  private s3BaseUrl: string | null = null;
  private topicTrackingStateMeta: Map<string, number> | null = null;
  private topicTrackingStates: Record<string, Object>[] | null = null;

  private constructor() {
  }

  static getInstance(): PreloadedDataService {
    if (PreloadedDataService.instance === null) {
      PreloadedDataService.instance = new PreloadedDataService();
    }
    return PreloadedDataService.instance;
  }

  isLoaded(): boolean {
    return this.loaded;
  }

  /**
   * 从 /site.json 的 client_settings 提取到 long_polling_base_url 时调用（绕开 CF HTML challenge）
   */
  setLongPollingBaseUrlFromApi(baseUrl: string): void {
    const normalized: string | null = this.normalizePollingBaseUrl(baseUrl);
    if (normalized === null) return;
    if (normalized === this.longPollingBaseUrl) return;
    this.longPollingBaseUrl = normalized;
    try {
      MessageBusService.getInstance().configure(this.longPollingBaseUrl, this.sharedSessionKey);
    } catch (_) {
    }
    // 缓存到 Preferences 供下次启动使用
    PreferencesUtil.putString(PREF_KEY_LONG_POLLING_BASE_URL, normalized).catch((_: Object) => {});
    if (AppConstants.DEBUG_TRACKING) {
      hilog.info(0x0000, TAG, 'longPollingBaseUrl set from site.json api: %{public}s', normalized);
    }
  }

  getLongPollingBaseUrl(): string | null {
    return this.longPollingBaseUrl;
  }

  getSharedSessionKey(): string | null {
    return this.sharedSessionKey;
  }

  getCdnUrl(): string | null {
    return this.cdnUrl;
  }

  getS3CdnUrl(): string | null {
    return this.s3CdnUrl;
  }

  getS3BaseUrl(): string | null {
    return this.s3BaseUrl;
  }

  getTopicTrackingStateMeta(): Map<string, number> | null {
    return this.topicTrackingStateMeta;
  }

  getTopicTrackingStates(): Record<string, Object>[] | null {
    return this.topicTrackingStates;
  }

  /**
   * 仅加载 MessageBus 配置（避免解析 data-preloaded 大 JSON 导致 UI/消息处理卡顿）：
   * - meta.shared_session_key
   * - siteSettings.long_polling_base_url
   *
   * 启动策略：先从 Preferences 读取缓存并 configure()，再后台抓一次 HTML 刷新；若值变化则重新 configure() 触发轮询重启。
   */
  async ensureConfigLoaded(silent: boolean = false): Promise<void> {
    await this.configureBusFromCacheIfNeeded();
    if (this.loaded) {
      this.configLoaded = true;
      try {
        MessageBusService.getInstance().configure(this.longPollingBaseUrl, this.sharedSessionKey);
      } catch (_) {
      }
      return;
    }
    if (this.configLoaded) return;
    if (this.configInFlight !== null) {
      return await this.configInFlight;
    }
    this.configInFlight = this.loadConfigOnly(silent);
    try {
      await this.configInFlight;
    } finally {
      this.configInFlight = null;
    }
  }

  async ensureLoaded(silent: boolean = false): Promise<void> {
    if (this.loaded) return;
    if (this.inFlight !== null) {
      return await this.inFlight;
    }
    this.inFlight = this.load(silent);
    try {
      await this.inFlight;
    } finally {
      this.inFlight = null;
    }
  }

  async refresh(silent: boolean = false): Promise<void> {
    this.reset();
    await this.ensureLoaded(silent);
  }

  reset(): void {
    this.loaded = false;
    this.longPollingBaseUrl = null;
    this.sharedSessionKey = null;
    this.cdnUrl = null;
    this.s3CdnUrl = null;
    this.s3BaseUrl = null;
    this.topicTrackingStateMeta = null;
    this.topicTrackingStates = null;
    this.inFlight = null;
    this.configLoaded = false;
    this.configInFlight = null;
    this.configuredFromCache = false;
  }

  private async configureBusFromCacheIfNeeded(): Promise<void> {
    if (this.configuredFromCache) return;
    this.configuredFromCache = true;

    try {
      await PreferencesUtil.ensureInit();
      const cachedBaseRaw: string = await PreferencesUtil.getString(PREF_KEY_LONG_POLLING_BASE_URL, '');
      const cachedKeyRaw: string = await PreferencesUtil.getString(PREF_KEY_SHARED_SESSION_KEY, '');

      const cachedBase: string | null = cachedBaseRaw.length > 0 ? this.normalizePollingBaseUrl(cachedBaseRaw) : null;
      const cachedKey: string | null = cachedKeyRaw.length > 0 ? cachedKeyRaw.trim() : null;

      if (cachedBase !== null) {
        this.longPollingBaseUrl = cachedBase;
      }
      if (cachedKey !== null && cachedKey.length > 0) {
        this.sharedSessionKey = cachedKey;
      }

      if (cachedBase !== null || (cachedKey !== null && cachedKey.length > 0)) {
        MessageBusService.getInstance().configure(this.longPollingBaseUrl, this.sharedSessionKey);
        if (AppConstants.DEBUG_TRACKING) {
          hilog.info(
            0x0000,
            TAG,
            'MessageBus config loaded from cache baseUrl=%{public}s keyLen=%{public}d',
            this.longPollingBaseUrl !== null ? (this.longPollingBaseUrl as string) : '',
            this.sharedSessionKey !== null ? (this.sharedSessionKey as string).length : 0
          );
        }
      }
    } catch (_) {
    }
  }

  private decodeHtmlEntities(input: string): string {
    return input
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#39;', "'");
  }

  private tryDecodeJsonEscapedString(input: string): string {
    const s: string = input;
    if (s.indexOf('\\') < 0) return s;
    try {
      // 将字符串包裹成 JSON 字符串字面量，让 JSON.parse 处理 \/、\u002F 等转义
      const safe: string = s.replaceAll('"', '\\"');
      const parsed: Object = JSON.parse(`"${safe}"`) as Object;
      return typeof parsed === 'string' ? (parsed as string) : s;
    } catch (_) {
      return s;
    }
  }

  private extractMetaContent(html: string, metaName: string): string | null {
    const reg: RegExp = new RegExp(
      `<meta[^>]+name=[\"']${metaName}[\"'][^>]+content=[\"']([^\"']+)[\"']`,
      'i'
    );
    const m: string[] | null = html.match(reg);
    if (m === null || m.length < 2) return null;
    const raw: string = m[1];
    if (raw === null || raw === undefined || raw.length === 0) return null;
    return this.decodeHtmlEntities(raw);
  }

  private extractDiscourseSetupTag(html: string): string | null {
    const reg: RegExp = new RegExp(
      `id=[\"']data-discourse-setup[\"'][^>]*>`,
      'i'
    );
    const m: string[] | null = html.match(reg);
    if (m === null || m.length < 1) return null;
    const raw: string = m[0];
    if (raw === null || raw === undefined || raw.length === 0) return null;
    return raw;
  }

  private extractDiscourseSetupAttr(tag: string, attrName: string): string | null {
    const reg: RegExp = new RegExp(
      `data-${attrName}=[\"']([^\"']+)[\"']`,
      'i'
    );
    const m: string[] | null = tag.match(reg);
    if (m === null || m.length < 2) return null;
    const raw: string = m[1];
    if (raw === null || raw === undefined || raw.length === 0) return null;

    const decoded: string = this.decodeHtmlEntities(raw).trim();
    if (decoded.length === 0) return null;
    if (decoded.endsWith('/')) {
      return decoded.substring(0, decoded.length - 1);
    }
    return decoded;
  }

  private extractCdnConfigFromHtml(html: string): void {
    const tag: string | null = this.extractDiscourseSetupTag(html);
    if (tag === null) return;

    this.cdnUrl = this.extractDiscourseSetupAttr(tag, 'cdn');
    this.s3CdnUrl = this.extractDiscourseSetupAttr(tag, 's3-cdn');
    this.s3BaseUrl = this.extractDiscourseSetupAttr(tag, 's3-base-url');

    if (this.cdnUrl !== null) {
      hilog.info(0x0000, TAG, 'cdnUrl=%{public}s', this.cdnUrl as string);
    }
    if (this.s3CdnUrl !== null || this.s3BaseUrl !== null) {
      hilog.info(
        0x0000,
        TAG,
        's3CdnUrl=%{public}s, s3BaseUrl=%{public}s',
        this.s3CdnUrl !== null ? (this.s3CdnUrl as string) : '',
        this.s3BaseUrl !== null ? (this.s3BaseUrl as string) : ''
      );
    }
  }

  private extractTurnstileSitekeyFromHtml(html: string): void {
    const match: string[] | null = html.match(/data-sitekey="([0-9a-zA-Zx_-]+)"/);
    if (match === null || match.length < 2) return;
    const sitekey: string = match[1];
    if (sitekey.length > 0) {
      CfClearanceRefreshService.getInstance().updateSitekey(sitekey);
    }
  }

  private parseMaybeJson(raw: Object): Object {
    if (raw === null || raw === undefined) return raw;
    if (typeof raw === 'string') {
      const s: string = raw as string;
      const trimmed: string = s.trim();
      if (trimmed.length === 0) return raw;
      if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) return raw;
      try {
        return JSON.parse(trimmed) as Object;
      } catch (_) {
        return raw;
      }
    }
    return raw;
  }

  private normalizePollingBaseUrl(url: string): string | null {
    const v: string = url.trim();
    if (v.length === 0) return null;

    // Discourse 可能返回 scheme-relative：//example.com
    let out: string = v;
    if (out.startsWith('//')) {
      let scheme: string = 'https';
      try {
        const base: string = AppConstants.BASE_URL;
        const idx: number = base.indexOf('://');
        if (idx > 0) {
          scheme = base.substring(0, idx);
        }
      } catch (_) {
      }
      out = `${scheme}:${out}`;
    } else if (out.startsWith('/') && out !== '/') {
      // 兼容相对路径（少数站点可能部署在子路径）
      const base: string = AppConstants.BASE_URL.endsWith('/')
        ? AppConstants.BASE_URL.substring(0, AppConstants.BASE_URL.length - 1)
        : AppConstants.BASE_URL;
      out = `${base}${out}`;
    } else if (out === '/') {
      // 视为“同源”，不强制写入
      return null;
    }

    if (out.endsWith('/')) {
      out = out.substring(0, out.length - 1);
    }
    return out.trim().length > 0 ? out : null;
  }

  private getFallbackLongPollingBaseUrl(): string | null {
    try {
      // Playwright 验证：linux.do 的 long_polling_base_url 为 https://ping.linux.do，主域 /message-bus 返回 404 属正常。
      const base: string = AppConstants.BASE_URL.trim();
      if (base.length === 0) return null;
      let scheme: string = 'https';
      let host: string = base;
      const idx: number = base.indexOf('://');
      if (idx > 0) {
        scheme = base.substring(0, idx);
        host = base.substring(idx + 3);
      }
      const slash: number = host.indexOf('/');
      if (slash >= 0) host = host.substring(0, slash);
      host = host.trim();
      if (host.toLowerCase() !== 'linux.do') return null;
      return this.normalizePollingBaseUrl(`${scheme}://ping.linux.do`);
    } catch (_) {
    }
    return null;
  }

  private async loadConfigOnly(silent: boolean): Promise<void> {
    hilog.info(0x0000, TAG, 'Preload config-only %{public}s start, silent=%{public}s', PRELOAD_PATH, silent ? 'Y' : 'N');
    const httpClient: HttpClient = new HttpClient(AppConstants.BASE_URL);

    let html: string = '';
    let htmlErrText: string = '';
    try {
      html = await httpClient.getText(
        PRELOAD_PATH,
        null,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        60000,
        { silent: silent, caller: 'preloaded_latest_config' }
      );
    } catch (err) {
      try {
        htmlErrText = err !== null && err !== undefined ? err.toString() : '';
      } catch (_) {
        htmlErrText = '';
      }
      if (htmlErrText.length === 0) {
        try {
          htmlErrText = JSON.stringify(err);
        } catch (_) {
          htmlErrText = '';
        }
      }
      html = '';
      hilog.warn(0x0000, TAG, 'Preload config-only html failed: %{public}s', htmlErrText.length > 0 ? htmlErrText : 'unknown');
    }

    if (html.length > 0) {
      // Turnstile sitekey：用于 cf_clearance 自动续期（即使本次没触发 challenge，也尽量更新一次）
      this.extractTurnstileSitekeyFromHtml(html);
    }

    // shared_session_key（跨域 MessageBus）
    const nextShared: string | null = html.length > 0 ? this.extractMetaContent(html, 'shared_session_key') : null;

    // data-preloaded: 仅抽取 siteSettings.long_polling_base_url（避免整串 decode + JSON.parse）
    let nextBase: string | null = null;
    if (html.length > 0) {
      try {
        const match: string[] | null = html.match(/data-preloaded=\"([^\"]*)\"/);
        if (match !== null && match.length >= 2) {
          const encoded: string = match[1];

          // 1) 快速路径：直接从 HTML attribute（仍是 &quot; 形式，且 siteSettings 内层 JSON 会出现 \&quot;）提取
          let rawVal: string | null = null;
          const baseMatch: string[] | null = encoded.match(
            /long_polling_base_url(?:\\)?&quot;\s*:\s*(?:\\)?&quot;(.+?)(?:\\)?&quot;/i
          );
          if (baseMatch !== null && baseMatch.length >= 2) {
            rawVal = this.decodeHtmlEntities(baseMatch[1]);
          } else {
            // 2) 兜底：只在 fast path 失败时才 decode + JSON.parse 外层，再 parse siteSettings（对齐 FluxDO 解析方式）
            try {
              const decoded: string = this.decodeHtmlEntities(encoded);
              const outer: Record<string, Object> = JSON.parse(decoded) as Record<string, Object>;
              const siteSettingsRaw = outer['siteSettings'];
              const siteSettingsObj: Object | null = siteSettingsRaw !== undefined && siteSettingsRaw !== null
                ? this.parseMaybeJson(siteSettingsRaw)
                : null;
              if (siteSettingsObj !== null && siteSettingsObj !== undefined && typeof siteSettingsObj === 'object') {
                const siteSettings: Record<string, Object> = siteSettingsObj as Record<string, Object>;
                const pollingVal = siteSettings['long_polling_base_url'];
                if (pollingVal !== undefined && pollingVal !== null) {
                  rawVal = pollingVal.toString();
                }
              }
            } catch (_) {
              rawVal = null;
            }
          }

          if (rawVal !== null && rawVal.length > 0) {
            const unescaped: string = this.tryDecodeJsonEscapedString(rawVal);
            nextBase = this.normalizePollingBaseUrl(unescaped);
          }
        }
      } catch (_) {
        nextBase = null;
      }
    }

    // 兜底：在 CF challenge（silent）导致 HTML 取不到时，给 linux.do 一个可靠的默认 long_polling_base_url
    if (nextBase === null) {
      nextBase = this.getFallbackLongPollingBaseUrl();
    }

    const prevBase: string | null = this.longPollingBaseUrl;
    const prevKey: string | null = this.sharedSessionKey;

    if (nextBase !== null) {
      this.longPollingBaseUrl = nextBase;
    }
    if (nextShared !== null && nextShared.length > 0) {
      this.sharedSessionKey = nextShared;
    }

    // configure()：即使只拿到其中一个字段，也可提高成功率（另一项可由缓存/后续刷新补齐）
    try {
      MessageBusService.getInstance().configure(this.longPollingBaseUrl, this.sharedSessionKey);
    } catch (_) {
    }

    // 写入缓存：只在拿到非空值时更新，避免覆盖已有可用缓存
    if (nextBase !== null && nextBase !== prevBase) {
      PreferencesUtil.putString(PREF_KEY_LONG_POLLING_BASE_URL, nextBase).catch((err: Object) => {
        hilog.warn(0x0000, TAG, 'Cache longPollingBaseUrl failed: %{public}s', JSON.stringify(err));
      });
    }
    if (nextShared !== null && nextShared.length > 0 && nextShared !== prevKey) {
      PreferencesUtil.putString(PREF_KEY_SHARED_SESSION_KEY, nextShared).catch((err: Object) => {
        hilog.warn(0x0000, TAG, 'Cache sharedSessionKey failed: %{public}s', JSON.stringify(err));
      });
    }

    if (AppConstants.DEBUG_TRACKING) {
      const baseChanged: boolean = nextBase !== null && nextBase !== prevBase;
      const keyChanged: boolean = nextShared !== null && nextShared.length > 0 && nextShared !== prevKey;
      if (baseChanged || keyChanged || htmlErrText.length > 0) {
        hilog.info(
          0x0000,
          TAG,
          'Config-only updated baseChanged=%{public}s keyChanged=%{public}s baseUrl=%{public}s keyLen=%{public}d htmlErr=%{public}s',
          baseChanged ? 'Y' : 'N',
          keyChanged ? 'Y' : 'N',
          this.longPollingBaseUrl !== null ? (this.longPollingBaseUrl as string) : '',
          this.sharedSessionKey !== null ? (this.sharedSessionKey as string).length : 0,
          htmlErrText.length > 0 ? htmlErrText : '-'
        );
      }
    }

    this.configLoaded = true;
  }

  private async load(silent: boolean): Promise<void> {
    hilog.info(0x0000, TAG, 'Preload %{public}s start, silent=%{public}s', PRELOAD_PATH, silent ? 'Y' : 'N');
    const httpClient: HttpClient = new HttpClient(AppConstants.BASE_URL);
    const html: string = await httpClient.getText(
      PRELOAD_PATH,
      null,
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      60000,
      { silent: silent, caller: 'preloaded_latest' }
    );

    // data-discourse-setup（CDN / S3 CDN）
    this.extractCdnConfigFromHtml(html);
    this.extractTurnstileSitekeyFromHtml(html);

    // shared_session_key（跨域 MessageBus）
    this.sharedSessionKey = this.extractMetaContent(html, 'shared_session_key');

    // data-preloaded
    const match: string[] | null = html.match(/data-preloaded="([^"]*)"/);
    if (match === null || match.length < 2) {
      hilog.error(0x0000, TAG, 'No data-preloaded found');
      this.loaded = true;
      return;
    }

    const encoded: string = match[1];
    const decoded: string = this.decodeHtmlEntities(encoded);

    let outer: Record<string, Object> | null = null;
    try {
      outer = JSON.parse(decoded) as Record<string, Object>;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Parse data-preloaded failed: %{public}s', JSON.stringify(err));
      this.loaded = true;
      return;
    }

    // siteSettings.long_polling_base_url
    const siteSettingsRaw = outer['siteSettings'];
    const siteSettingsObj: Object | null = siteSettingsRaw !== undefined && siteSettingsRaw !== null
      ? this.parseMaybeJson(siteSettingsRaw)
      : null;
    if (siteSettingsObj !== null && siteSettingsObj !== undefined && typeof siteSettingsObj === 'object') {
      const siteSettings: Record<string, Object> = siteSettingsObj as Record<string, Object>;
      const pollingVal = siteSettings['long_polling_base_url'];
      if (pollingVal !== undefined && pollingVal !== null) {
        const normalized: string | null = this.normalizePollingBaseUrl(pollingVal.toString());
        if (normalized !== null) {
          this.longPollingBaseUrl = normalized;
          hilog.info(0x0000, TAG, 'longPollingBaseUrl=%{public}s', normalized);
        }
      }
    }

    // topicTrackingStateMeta（频道初始 message_id）
    const metaRaw = outer['topicTrackingStateMeta'];
    const metaObj: Object | null = metaRaw !== undefined && metaRaw !== null ? this.parseMaybeJson(metaRaw) : null;
    if (metaObj !== null && metaObj !== undefined && typeof metaObj === 'object') {
      const metaJson: Record<string, Object> = metaObj as Record<string, Object>;
      const keys: string[] = Object.keys(metaJson);
      const map: Map<string, number> = new Map();
      for (let i = 0; i < keys.length; i++) {
        const k: string = keys[i];
        const v: Object = metaJson[k];
        if (v === undefined || v === null) continue;
        const num: number = Number(v.toString());
        if (!isNaN(num)) {
          map.set(k, num);
        }
      }
      if (map.size > 0) {
        this.topicTrackingStateMeta = map;
        hilog.info(0x0000, TAG, 'topicTrackingStateMeta size=%{public}d', map.size);
      }
    }

    // topicTrackingStates（追踪状态数组）
    const statesRaw = outer['topicTrackingStates'];
    const statesObj: Object | null = statesRaw !== undefined && statesRaw !== null ? this.parseMaybeJson(statesRaw) : null;
    if (statesObj !== null && statesObj !== undefined && Array.isArray(statesObj)) {
      const arr: Object[] = statesObj as Object[];
      const list: Record<string, Object>[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item !== null && item !== undefined && typeof item === 'object') {
          list.push(item as Record<string, Object>);
        }
      }
      this.topicTrackingStates = list;
      hilog.info(0x0000, TAG, 'topicTrackingStates size=%{public}d', list.length);
    }

    this.loaded = true;
    this.configLoaded = true;
    try {
      MessageBusService.getInstance().configure(this.longPollingBaseUrl, this.sharedSessionKey);
    } catch (_) {
    }
    if (this.longPollingBaseUrl !== null) {
      PreferencesUtil.putString(PREF_KEY_LONG_POLLING_BASE_URL, this.longPollingBaseUrl as string).catch((err: Object) => {
        hilog.warn(0x0000, TAG, 'Cache longPollingBaseUrl failed: %{public}s', JSON.stringify(err));
      });
    }
    if (this.sharedSessionKey !== null && (this.sharedSessionKey as string).length > 0) {
      PreferencesUtil.putString(PREF_KEY_SHARED_SESSION_KEY, this.sharedSessionKey as string).catch((err: Object) => {
        hilog.warn(0x0000, TAG, 'Cache sharedSessionKey failed: %{public}s', JSON.stringify(err));
      });
    }
    CfClearanceRefreshService.getInstance().startIfPossible();
  }
}
