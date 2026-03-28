import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { StickerGroup, StickerGroupDetail, StickerMarketIndex } from '../../models/Sticker';
import { PreferencesUtil } from '../storage/PreferencesUtil';
import { FeatureSettingsService } from '../storage/FeatureSettingsService';

const TAG: string = 'StickerMarketService';

export class StickerMarketService {
  static readonly DEFAULT_BASE_URL: string = 'https://s.pwsh.us.kg';
  private static currentBaseUrl: string = StickerMarketService.DEFAULT_BASE_URL;
  private static readonly CACHE_PREFIX: string = 'sticker_market_cache_';
  private static readonly CACHE_TTL_MS: number = 24 * 60 * 60 * 1000;
  private static readonly REQUEST_TIMEOUT_MS: number = 15000;
  private static instance: StickerMarketService | null = null;

  private indexCache: StickerMarketIndex | null = null;
  private allGroupsCache: StickerGroup[] | null = null;
  private pageCache: Map<number, StickerGroup[]> = new Map();
  private detailCache: Map<string, StickerGroupDetail> = new Map();
  private lastResolvedBaseUrl: string = StickerMarketService.DEFAULT_BASE_URL;

  static getInstance(): StickerMarketService {
    if (StickerMarketService.instance === null) {
      StickerMarketService.instance = new StickerMarketService();
    }
    return StickerMarketService.instance;
  }

  static resolveAssetUrl(rawUrl: string, baseUrl: string = StickerMarketService.currentBaseUrl): string {
    const trimmed: string = rawUrl !== undefined && rawUrl !== null ? rawUrl.trim() : '';
    if (trimmed.length === 0) {
      return '';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('//')) {
      return `https:${trimmed}`;
    }
    if (trimmed.startsWith('/')) {
      const normalizedBaseUrl: string = baseUrl !== undefined && baseUrl !== null && baseUrl.trim().length > 0
        ? baseUrl.trim()
        : StickerMarketService.DEFAULT_BASE_URL;
      return `${normalizedBaseUrl}${trimmed}`;
    }
    return trimmed;
  }

  async getIndex(): Promise<StickerMarketIndex> {
    if (this.indexCache !== null) {
      return this.indexCache as StickerMarketIndex;
    }
    const data: Record<string, Object> = await this.fetchWithCache('index', '/assets/market/index/index.json');
    const index: StickerMarketIndex = StickerMarketIndex.fromJson(data);
    this.indexCache = index;
    return index;
  }

  async getGroupsPage(page: number): Promise<StickerGroup[]> {
    const safePage: number = page > 0 ? Math.floor(page) : 1;
    if (this.pageCache.has(safePage)) {
      return this.pageCache.get(safePage) as StickerGroup[];
    }
    const data: Record<string, Object> = await this.fetchWithCache(
      `page_${safePage}`,
      `/assets/market/index/page-${safePage}.json`
    );
    const groups: StickerGroup[] = this.parseGroups(data);
    this.pageCache.set(safePage, groups);
    return groups;
  }

  async getAllGroups(): Promise<StickerGroup[]> {
    if (this.allGroupsCache !== null) {
      return this.allGroupsCache as StickerGroup[];
    }
    const index: StickerMarketIndex = await this.getIndex();
    const totalPages: number = index.totalPages > 0 ? index.totalPages : 1;
    const groups: StickerGroup[] = [];
    for (let page = 1; page <= totalPages; page++) {
      const pageGroups: StickerGroup[] = await this.getGroupsPage(page);
      for (let i = 0; i < pageGroups.length; i++) {
        if (!pageGroups[i].isArchived) {
          groups.push(pageGroups[i]);
        }
      }
    }
    groups.sort((a: StickerGroup, b: StickerGroup): number => {
      if (a.order !== b.order) {
        return a.order - b.order;
      }
      return a.name.localeCompare(b.name);
    });
    this.allGroupsCache = groups;
    return groups;
  }

  async getGroupDetail(groupId: string): Promise<StickerGroupDetail> {
    const trimmedGroupId: string = groupId !== undefined && groupId !== null ? groupId.trim() : '';
    if (trimmedGroupId.length === 0) {
      return new StickerGroupDetail();
    }
    if (this.detailCache.has(trimmedGroupId)) {
      return this.detailCache.get(trimmedGroupId) as StickerGroupDetail;
    }
    const data: Record<string, Object> = await this.fetchWithCache(
      `group_${trimmedGroupId}`,
      `/assets/market/group-${trimmedGroupId}.json`
    );
    const detail: StickerGroupDetail = StickerGroupDetail.fromJson(data);
    if (detail.id.trim().length === 0) {
      detail.id = trimmedGroupId;
    }
    this.detailCache.set(trimmedGroupId, detail);
    return detail;
  }

  private parseGroups(data: Record<string, Object>): StickerGroup[] {
    const groupsVal = data['groups'];
    if (groupsVal === undefined || groupsVal === null || !Array.isArray(groupsVal)) {
      return [];
    }

    const groups: StickerGroup[] = [];
    const arr: Object[] = groupsVal as Object[];
    for (let i = 0; i < arr.length; i++) {
      const row: Object = arr[i];
      if (row === undefined || row === null || typeof row !== 'object') {
        continue;
      }
      groups.push(StickerGroup.fromJson(row as Record<string, Object>));
    }
    return groups;
  }

  private async fetchWithCache(cacheKey: string, relativePath: string): Promise<Record<string, Object>> {
    await PreferencesUtil.ensureInit();
    const baseUrl: string = await FeatureSettingsService.getInstance().getStickerSource();
    if (this.lastResolvedBaseUrl !== baseUrl) {
      this.indexCache = null;
      this.allGroupsCache = null;
      this.pageCache.clear();
      this.detailCache.clear();
      this.lastResolvedBaseUrl = baseUrl;
    }
    StickerMarketService.currentBaseUrl = baseUrl;
    const valueKey: string = `${StickerMarketService.CACHE_PREFIX}${baseUrl}_${cacheKey}`;
    const tsKey: string = `${valueKey}_ts`;
    const cachedRaw: string = await PreferencesUtil.getString(valueKey, '');
    const cachedTs: number = await PreferencesUtil.getNumber(tsKey, 0);
    const now: number = Date.now();

    if (cachedRaw.trim().length > 0 && cachedTs > 0 && now - cachedTs < StickerMarketService.CACHE_TTL_MS) {
      const parsed: Record<string, Object> | null = this.tryParseJsonObject(cachedRaw);
      if (parsed !== null) {
        return parsed;
      }
    }

    const url: string = StickerMarketService.resolveAssetUrl(relativePath, baseUrl);
    try {
      const data: Record<string, Object> = await this.requestJson(url);
      await PreferencesUtil.putString(valueKey, JSON.stringify(data));
      await PreferencesUtil.putNumber(tsKey, now);
      return data;
    } catch (err) {
      const fallback: Record<string, Object> | null = this.tryParseJsonObject(cachedRaw);
      if (fallback !== null) {
        hilog.warn(0x0000, TAG, 'Use stale cache for %{public}s after network failure', cacheKey);
        return fallback;
      }
      const message: string = err !== undefined && err !== null ? err.toString() : '表情包市场请求失败';
      throw new Error(message);
    }
  }

  private tryParseJsonObject(raw: string): Record<string, Object> | null {
    const trimmed: string = raw !== undefined && raw !== null ? raw.trim() : '';
    if (trimmed.length === 0) {
      return null;
    }
    try {
      const parsed: Object = JSON.parse(trimmed) as Object;
      if (parsed === null || parsed === undefined || typeof parsed !== 'object' || Array.isArray(parsed)) {
        return null;
      }
      return parsed as Record<string, Object>;
    } catch (_) {
      return null;
    }
  }

  private async requestJson(url: string): Promise<Record<string, Object>> {
    const request = http.createHttp();
    try {
      const req: Record<string, Object> = {};
      req['method'] = http.RequestMethod.GET;

      const headers: Record<string, string> = {};
      headers['User-Agent'] = AppConstants.USER_AGENT;
      headers['Accept'] = 'application/json';
      req['header'] = headers;
      req['connectTimeout'] = StickerMarketService.REQUEST_TIMEOUT_MS;
      req['readTimeout'] = StickerMarketService.REQUEST_TIMEOUT_MS;

      const response = await request.request(url, req);
      const code: number = response.responseCode as number;
      const result: string = response.result !== undefined && response.result !== null ? response.result as string : '';
      if (code < 200 || code >= 300) {
        throw new Error(`HTTP ${code}`);
      }

      const parsed: Object = JSON.parse(result) as Object;
      if (parsed === null || parsed === undefined || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error('表情包市场返回格式异常');
      }
      return parsed as Record<string, Object>;
    } catch (err) {
      const message: string = err !== undefined && err !== null ? err.toString() : 'request failed';
      hilog.error(0x0000, TAG, 'Request sticker market failed %{public}s: %{public}s', url, message);
      throw new Error(message);
    } finally {
      request.destroy();
    }
  }
}
