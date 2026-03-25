import { hilog } from '@kit.PerformanceAnalysisKit';
import { CfGuardOptions, HttpClient, HttpMultipartFilePart, HttpTextResponse } from './HttpClient';
import { ApiConstants } from '../../common/constants/ApiConstants';
import { Topic, TopicListResponse, Tag } from '../../models/Topic';
import { Category, SiteResponse } from '../../models/Category';
import { TagSearchResult, TagInfo } from '../../models/TagSearchResult';
import { FollowUser, User, UserSummary } from '../../models/User';
import { SearchResult } from '../../models/SearchResult';
import { Draft, DraftData, DraftListResponse } from '../../models/Draft';
import { Badge, BadgeDetailResponse, UserBadgeListResponse } from '../../models/Badge';
import { NotificationListResponse } from '../../models/Notification';
import { Poll, Post, PostReactionState } from '../../models/Post';
import { UserActionResponse, UserReactionsResponse } from '../../models/UserAction';
import { Emoji } from '../../models/Emoji';
import { UploadedImage } from '../../models/UploadedImage';
import { PreloadedDataService } from '../messagebus/PreloadedDataService';
import { MessageBusService } from '../messagebus/MessageBusService';
import { EmojiResolver } from '../../common/utils/EmojiResolver';
import { ComposerUploadUrlCache } from '../../common/utils/ComposerUploadUrlCache';

const TAG: string = 'ApiClient';
const CURRENT_USER_CACHE_TTL_MS: number = 5000;
const CURRENT_USER_RATE_LIMIT_COOLDOWN_MS: number = 8000;

export class PostEnqueuedError extends Error {
  pendingCount: number = 0;

  constructor(pendingCount: number = 0) {
    super('POST_ENQUEUED');
    this.pendingCount = pendingCount;
  }
}

/**
 * Discourse API 客户端
 */
export class ApiClient {
  private http: HttpClient;
  private static instance: ApiClient | null = null;
  private static readonly LIKE_POST_ACTION_TYPE_ID: number = 2;

  // 会话内缓存：避免多页面重复拉取 site.json
  private siteInfoCache: SiteResponse | null = null;
  private siteInfoInFlight: Promise<SiteResponse> | null = null;
  private emojiGroupsCache: Map<string, Emoji[]> | null = null;
  private emojiGroupsInFlight: Promise<Map<string, Emoji[]>> | null = null;
  private currentUserCache: User | null = null;
  private currentUserCacheAt: number = 0;
  private currentUserInFlight: Promise<User | null> | null = null;
  private currentUserRateLimitedUntil: number = 0;
  private currentUserSessionVersion: number = 0;

  private constructor() {
    this.http = new HttpClient();
  }

  static formatError(err: Object): string {
    if (err === undefined || err === null) {
      return 'Unknown error';
    }
    try {
      const text: string = err.toString().trim();
      if (text.length > 0 && text !== '[object Object]') {
        return text;
      }
    } catch (_) {
    }
    try {
      const jsonText: string = JSON.stringify(err);
      if (jsonText.length > 0 && jsonText !== '{}') {
        return jsonText;
      }
    } catch (_) {
    }
    return 'Unknown error';
  }

  static isSslPeerCertificateError(err: Object): boolean {
    const text: string = ApiClient.formatError(err).toLowerCase();
    return text.indexOf('2300060') >= 0
      || text.indexOf('invalid ssl peer certificate') >= 0
      || text.indexOf('ssl peer certificate or ssh remote key') >= 0;
  }

  static getTlsCertificateErrorMessage(): string {
    return '网络证书校验失败，请检查代理/抓包证书，或使用当前调试构建的本地证书兼容模式';
  }

  static extractRetryAfterSeconds(err: Object, fallbackSeconds: number = 0): number {
    const text: string = ApiClient.formatError(err);
    const patterns: RegExp[] = [
      /retry[_ -]?after\s*[=:]\s*(\d+)/i,
      /retry[_ -]?after\s+(\d+)/i,
      /wait[_ -]?seconds\s*[=:]\s*(\d+)/i
    ];
    for (let i = 0; i < patterns.length; i++) {
      const matched: RegExpMatchArray | null = text.match(patterns[i]);
      if (matched !== null && matched.length >= 2) {
        const parsed: number = Number(matched[1]);
        if (!isNaN(parsed) && parsed > 0) {
          return Math.ceil(parsed);
        }
      }
    }
    return fallbackSeconds > 0 ? fallbackSeconds : 0;
  }

  private isRateLimitError(err: Object): boolean {
    if (err === null || err === undefined) {
      return false;
    }
    const text: string = err.toString();
    return text.indexOf('HTTP 429') >= 0;
  }

  private hasFreshCurrentUserCache(): boolean {
    return this.currentUserCache !== null
      && this.currentUserCacheAt > 0
      && Date.now() - this.currentUserCacheAt < CURRENT_USER_CACHE_TTL_MS;
  }

  private clearCurrentUserCacheState(): void {
    this.currentUserCache = null;
    this.currentUserCacheAt = 0;
    this.currentUserRateLimitedUntil = 0;
  }

  private cacheCurrentUser(user: User | null, sessionVersion: number = this.currentUserSessionVersion): void {
    if (sessionVersion !== this.currentUserSessionVersion) {
      return;
    }
    this.currentUserCache = user;
    this.currentUserCacheAt = user !== null ? Date.now() : 0;
    if (user !== null) {
      this.currentUserRateLimitedUntil = 0;
    }
  }

  private async fetchCurrentUserInternal(sessionVersion: number): Promise<User | null> {
    const raw: string = await this.http.get(ApiConstants.CURRENT_USER);
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    const currentUserVal = json['current_user'];
    if (currentUserVal === undefined || currentUserVal === null || typeof currentUserVal !== 'object') {
      this.cacheCurrentUser(null, sessionVersion);
      return null;
    }
    const user: User = User.fromJson(currentUserVal as Record<string, Object>);
    this.cacheCurrentUser(user, sessionVersion);
    return user;
  }

  setCachedCurrentUser(user: User | null): void {
    this.cacheCurrentUser(user);
  }

  invalidateCurrentUserCache(): void {
    this.clearCurrentUserCacheState();
  }

  resetCurrentUserSessionState(): void {
    this.currentUserSessionVersion += 1;
    this.currentUserInFlight = null;
    this.clearCurrentUserCacheState();
  }

  /**
   * 获取单例
   */
  static getInstance(): ApiClient {
    if (ApiClient.instance === null) {
      ApiClient.instance = new ApiClient();
    }
    return ApiClient.instance;
  }

  /**
   * 获取 HTTP 客户端（用于设置 cookies 等）
   */
  getHttpClient(): HttpClient {
    return this.http;
  }

  /**
   * 获取话题列表（最新）
   */
  async getLatestTopics(page: number = 0): Promise<TopicListResponse> {
    return await this.getFilteredTopics('latest', page, null, null, null, null, null, null, null);
  }

  /**
   * 获取分类下的话题列表
   */
  async getCategoryTopics(slug: string, id: number, page: number = 0): Promise<TopicListResponse> {
    return await this.getFilteredTopics('latest', page, null, null, null, slug, id, null, null);
  }

  /**
   * 按 topic_ids 获取话题（用于“查看新话题”banner 增量插入）
   * 请求格式：/latest.json?topic_ids=1,2,3
   */
  async getTopicsByIds(topicIds: number[]): Promise<TopicListResponse> {
    if (topicIds.length === 0) {
      return new TopicListResponse();
    }
    const params: Record<string, Object> = {};
    params['topic_ids'] = topicIds.join(',');
    const result: string = await this.http.get(ApiConstants.TOPIC_LIST, params);
    const json: Record<string, Object> = JSON.parse(result) as Record<string, Object>;
    return TopicListResponse.fromJson(json);
  }

  /**
   * 获取话题列表（支持分类/标签/排序/period）
   * 支持分类、标签、排序和 period 组合查询
   */
  async getFilteredTopics(
    filter: string,
    page: number = 0,
    period: string | null = null,
    order: string | null = null,
    ascending: boolean | null = null,
    categorySlug: string | null = null,
    categoryId: number | null = null,
    parentCategorySlug: string | null = null,
    tags: string[] | null = null,
    connectTimeoutMs: number | null = null,
    readTimeoutMs: number | null = null,
    guardOptions: CfGuardOptions | null = null
  ): Promise<TopicListResponse> {
    // 构造 path（分类优先，其次纯标签，否则全站）
    // path 规则：
    // - 热门（无分类/标签）=> /hot.json
    // - 热门（有分类或标签）=> /.../top.json?period=weekly
    // - 排行榜（无分类/标签）=> /top.json，不传 order
    // - 排行榜（有分类或标签）=> /.../top.json，可传 order
    let path: string = '';
    const params: Record<string, Object> = {};
    const hasCategoryScope: boolean = categoryId !== null && categorySlug !== null && categorySlug.length > 0;
    const scopedTags: string[] = tags !== null ? tags : [];
    const hasTagScope: boolean = scopedTags.length > 0;
    const hasScopedFilter: boolean = hasCategoryScope || hasTagScope;

    let effectiveFilter: string = filter;
    let effectivePeriod: string | null = period;
    if (filter === 'hot' && hasScopedFilter) {
      effectiveFilter = 'top';
      if (effectivePeriod === null || effectivePeriod.length === 0) {
        effectivePeriod = 'weekly';
      }
    }

    if (page > 0) {
      params['page'] = page.toString();
    }
    if (effectivePeriod !== null && effectivePeriod.length > 0) {
      params['period'] = effectivePeriod;
    }
    const allowOrderForCurrentRequest: boolean = filter !== 'top' || hasScopedFilter;
    if (allowOrderForCurrentRequest) {
      if (order !== null && order.length > 0) {
        params['order'] = order;
      }
      if (ascending !== null) {
        params['ascending'] = ascending.toString();
      }
    }

    if (hasCategoryScope) {
      if (parentCategorySlug !== null && parentCategorySlug.length > 0) {
        path = `/c/${parentCategorySlug}/${categorySlug}/${categoryId}/l/${effectiveFilter}.json`;
      } else {
        path = `/c/${categorySlug}/${categoryId}/l/${effectiveFilter}.json`;
      }
      if (scopedTags.length > 0) {
        params['tags[]'] = scopedTags;
      }
    } else if (hasTagScope) {
      path = `/tag/${scopedTags[0]}/l/${effectiveFilter}.json`;
      if (scopedTags.length > 1) {
        const rest: string[] = [];
        for (let i = 1; i < scopedTags.length; i++) {
          rest.push(scopedTags[i]);
        }
        params['tags[]'] = rest;
        params['match_all_tags'] = 'true';
      }
    } else {
      path = filter === 'hot' ? '/hot.json' : `/${effectiveFilter}.json`;
    }

    const hasParams: boolean = Object.keys(params).length > 0;
    const result: string = await this.http.get(path, hasParams ? params : null, connectTimeoutMs, readTimeoutMs, guardOptions);
    const json: Record<string, Object> = JSON.parse(result) as Record<string, Object>;
    return TopicListResponse.fromJson(json);
  }

  /**
   * 搜索标签（用于标签选择弹层）
   * 请求格式：/tags/filter/search?q=xxx&limit=8&selected_tags=...
   */
  async searchTags(
    query: string = '',
    categoryId: number | null = null,
    selectedTags: string[] | null = null,
    limit: number = 8,
    filterForInput: boolean = false
  ): Promise<TagSearchResult> {
    const params: Record<string, Object> = {};
    params['q'] = query;
    // Discourse 端对 limit 有上限保护：limit 过大可能直接返回 400（真机反馈）
    const effectiveLimit: number = limit > 0 ? Math.min(limit, 20) : limit;
    if (effectiveLimit > 0) {
      params['limit'] = effectiveLimit.toString();
    }
    if (categoryId !== null) {
      params['categoryId'] = categoryId.toString();
    }
    if (filterForInput) {
      params['filterForInput'] = 'true';
    }
    if (selectedTags !== null && selectedTags.length > 0) {
      // selected_tags 使用重复 query 参数：selected_tags=tag1&selected_tags=tag2...
      params['selected_tags'] = selectedTags;
    }

    // 标签筛选弹层对交互敏感：缩短超时，避免真机弱网/代理下卡住数分钟才失败
    const raw: string = await this.http.getText(ApiConstants.TAG_SEARCH, params, 'application/json', 15000);
    const parsed: Object = JSON.parse(raw) as Object;

    // 兼容异常返回：有些站点/反向代理可能直接返回数组
    if (Array.isArray(parsed)) {
      const arr: Object[] = parsed as Object[];
      const list: TagInfo[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item === null || item === undefined || typeof item !== 'object') continue;
        list.push(TagInfo.fromJson(item as Record<string, Object>));
      }
      const r: TagSearchResult = new TagSearchResult();
      r.results = list;
      r.requiredTagGroup = null;
      return r;
    }

    if (parsed !== null && parsed !== undefined && typeof parsed === 'object') {
      return TagSearchResult.fromJson(parsed as Record<string, Object>);
    }

    throw new Error('Invalid tag search response');
  }

  /**
   * 获取站点信息（含分类）
   */
  async getSiteInfo(): Promise<SiteResponse> {
    if (this.siteInfoCache !== null) {
      return this.siteInfoCache;
    }
    if (this.siteInfoInFlight !== null) {
      return await this.siteInfoInFlight;
    }

    this.siteInfoInFlight = this.fetchSiteInfo();
    try {
      const resp: SiteResponse = await this.siteInfoInFlight;
      this.siteInfoCache = resp;
      return resp;
    } finally {
      this.siteInfoInFlight = null;
    }
  }

  async refreshSiteInfo(): Promise<SiteResponse> {
    this.siteInfoCache = null;
    return await this.fetchSiteInfo();
  }

  async getEmojis(): Promise<Map<string, Emoji[]>> {
    if (this.emojiGroupsCache !== null) {
      return this.emojiGroupsCache;
    }
    if (this.emojiGroupsInFlight !== null) {
      return await this.emojiGroupsInFlight;
    }

    this.emojiGroupsInFlight = this.fetchEmojis();
    try {
      const groups: Map<string, Emoji[]> = await this.emojiGroupsInFlight;
      this.emojiGroupsCache = groups;
      return groups;
    } finally {
      this.emojiGroupsInFlight = null;
    }
  }

  private async fetchSiteInfo(): Promise<SiteResponse> {
    const result: string = await this.http.get(ApiConstants.SITE);
    const json: Record<string, Object> = JSON.parse(result) as Record<string, Object>;
    this.tryConfigureMessageBusFromSiteJson(json);
    EmojiResolver.configureFromSiteJson(json);
    return SiteResponse.fromJson(json);
  }

  private async fetchEmojis(): Promise<Map<string, Emoji[]>> {
    const result: string = await this.http.get(ApiConstants.EMOJIS);
    const parsed: Object = JSON.parse(result) as Object;
    if (parsed === null || parsed === undefined || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error('Invalid emoji response');
    }
    return this.parseEmojiGroups(parsed as Record<string, Object>);
  }

  private parseEmojiGroups(json: Record<string, Object>): Map<string, Emoji[]> {
    const groups: Map<string, Emoji[]> = new Map();
    const keys: string[] = Object.keys(json);
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const rawValue: Object | undefined = json[key];
      if (!Array.isArray(rawValue)) {
        continue;
      }

      const emojis: Emoji[] = [];
      const arr: Object[] = rawValue as Object[];
      for (let j = 0; j < arr.length; j++) {
        const item: Object = arr[j];
        if (item === null || item === undefined || typeof item !== 'object') {
          continue;
        }
        const emoji: Emoji = Emoji.fromJson(item as Record<string, Object>);
        if (emoji.name.trim().length === 0) {
          continue;
        }
        if (emoji.group.trim().length === 0) {
          emoji.group = key;
        }
        emojis.push(emoji);
      }

      if (emojis.length > 0) {
        groups.set(key, emojis);
      }
    }
    return groups;
  }

  private tryConfigureMessageBusFromSiteJson(json: Record<string, Object>): void {
    try {
      // /site.json 的 client_settings 包含 long_polling_base_url，用于 MessageBus 独立域名
      // 通过 JSON API 提取可绕开 CF 对 HTML 页面的 challenge
      const candidates: Object[] = [];
      const csVal = json['client_settings'];
      if (csVal !== undefined && csVal !== null && typeof csVal === 'object') {
        candidates.push(csVal);
      }
      const ssSnakeVal = json['site_settings'];
      if (ssSnakeVal !== undefined && ssSnakeVal !== null && typeof ssSnakeVal === 'object') {
        candidates.push(ssSnakeVal);
      }
      const ssCamelVal = json['siteSettings'];
      if (ssCamelVal !== undefined && ssCamelVal !== null && typeof ssCamelVal === 'object') {
        candidates.push(ssCamelVal);
      }

      let rawUrl: string = '';
      for (let i = 0; i < candidates.length; i++) {
        const obj: Record<string, Object> = candidates[i] as Record<string, Object>;
        const urlVal = obj['long_polling_base_url'] !== undefined ? obj['long_polling_base_url'] : obj['longPollingBaseUrl'];
        if (urlVal === undefined || urlVal === null) continue;
        const v: string = urlVal.toString().trim();
        if (v.length > 0) {
          rawUrl = v;
          break;
        }
      }

      if (rawUrl.length === 0 || rawUrl === '/') return;
      PreloadedDataService.getInstance().setLongPollingBaseUrlFromApi(rawUrl);
    } catch (_) {
    }
  }

  /**
   * 获取话题详情
   */
  async getTopicDetail(
    id: number,
    postNumber: number = 0,
    filter: string = '',
    usernameFilters: string = ''
  ): Promise<string> {
    const params: Record<string, Object> = {};
    const f: string = filter.trim();
    const uf: string = usernameFilters.trim();
    if (f.length > 0) params['filter'] = f;
    if (uf.length > 0) params['username_filters'] = uf;

    const path: string = ApiConstants.topicDetail(id, postNumber > 0 ? postNumber : 0);
    return await this.http.get(path, Object.keys(params).length > 0 ? params : null);
  }

  /**
   * 批量获取帖子内容（/t/{id}/posts.json?post_ids[]=...）
   */
  async getTopicPosts(topicId: number, postIds: number[]): Promise<Post[]> {
    if (postIds.length === 0) {
      return [];
    }

    const params: Record<string, Object> = {};
    params['post_ids[]'] = postIds;

    const raw: string = await this.http.get(ApiConstants.topicPosts(topicId), params);
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;

    let postStreamObj: Record<string, Object> | null = null;
    const postStreamVal = json['post_stream'];
    if (postStreamVal !== undefined && postStreamVal !== null) {
      postStreamObj = postStreamVal as Record<string, Object>;
    } else {
      postStreamObj = json;
    }

    const postsVal = postStreamObj['posts'];
    if (postsVal === undefined || postsVal === null) {
      return [];
    }

    const arr: Object[] = postsVal as Object[];
    const out: Post[] = [];
    for (let i = 0; i < arr.length; i++) {
      const item = arr[i] as Record<string, Object>;
      out.push(Post.fromJson(item));
    }
    return out;
  }

  /**
   * 获取帖子 raw（/posts/{id}.json → raw）
   *
   * 失败时返回空字符串，供导出流程兜底
   */
  async getPostRaw(postId: number): Promise<string> {
    if (postId <= 0) {
      return '';
    }

    try {
      const rawText: string = await this.http.get(ApiConstants.postDetail(postId));
      const json: Record<string, Object> = JSON.parse(rawText) as Record<string, Object>;

      const rawVal = json['raw'];
      if (rawVal !== undefined && rawVal !== null) {
        return rawVal.toString();
      }

      const postVal = json['post'];
      if (postVal !== undefined && postVal !== null && typeof postVal === 'object') {
        const postObj: Record<string, Object> = postVal as Record<string, Object>;
        const raw2 = postObj['raw'];
        if (raw2 !== undefined && raw2 !== null) {
          return raw2.toString();
        }
      }
    } catch (_) {
    }

    return '';
  }

  /**
   * 获取帖子的回复列表（/posts/{id}/replies?after=1）
   */
  async getPostReplies(postId: number, after: number = 1): Promise<Post[]> {
    if (postId <= 0) {
      return [];
    }

    const params: Record<string, Object> = {};
    params['after'] = after.toString();

    const raw: string = await this.http.get(ApiConstants.postReplies(postId), params);
    const json: Object = JSON.parse(raw) as Object;
    if (!(json instanceof Array)) {
      return [];
    }

    const arr: Object[] = json as Object[];
    const out: Post[] = [];
    for (let i = 0; i < arr.length; i++) {
      out.push(Post.fromJson(arr[i] as Record<string, Object>));
    }
    return out;
  }

  /**
   * 创建回复
   */
  async createReply(topicId: number, raw: string, replyToPostNumber: number = 0): Promise<Post> {
    const form: Record<string, Object> = {};
    form['topic_id'] = topicId.toString();
    form['raw'] = raw;
    if (replyToPostNumber > 0) {
      form['reply_to_post_number'] = replyToPostNumber.toString();
    }

    const rawText: string = await this.http.postFormText(ApiConstants.POSTS, form);
    const json: Record<string, Object> = JSON.parse(rawText) as Record<string, Object>;

    const actionVal = json['action'];
    if (actionVal !== undefined && actionVal !== null && actionVal.toString() === 'enqueued') {
      const pendingVal = json['pending_count'];
      const pendingCount: number = pendingVal !== undefined && pendingVal !== null ? Number(pendingVal.toString()) : 0;
      throw new PostEnqueuedError(pendingCount);
    }

    const postVal = json['post'];
    if (postVal !== undefined && postVal !== null && typeof postVal === 'object') {
      return Post.fromJson(postVal as Record<string, Object>);
    }

    const idVal = json['id'];
    if (idVal !== undefined && idVal !== null) {
      return Post.fromJson(json);
    }

    const successVal = json['success'];
    if (successVal !== undefined && successVal !== null && successVal.toString() === 'false') {
      const errorsVal = json['errors'];
      if (errorsVal !== undefined && errorsVal !== null && Array.isArray(errorsVal)) {
        const errs: Object[] = errorsVal as Object[];
        let message: string = '';
        for (let i = 0; i < errs.length; i++) {
          const part: string = errs[i] !== undefined && errs[i] !== null ? errs[i].toString() : '';
          if (part.length === 0) continue;
          message = message.length > 0 ? `${message}\n${part}` : part;
        }
        throw new Error(message.length > 0 ? message : '回复失败');
      }
      throw new Error('回复失败');
    }

    throw new Error('未知响应格式');
  }

  async uploadComposerImage(
    bytes: ArrayBuffer,
    fileName: string,
    mimeType: string,
    fallbackWidth: number = 0,
    fallbackHeight: number = 0
  ): Promise<UploadedImage> {
    if (bytes === undefined || bytes === null || bytes.byteLength <= 0) {
      throw new Error('图片数据不可用');
    }

    const normalizedFileName: string = fileName !== undefined && fileName !== null && fileName.trim().length > 0
      ? fileName.trim()
      : `image_${Date.now()}.jpg`;
    const normalizedMimeType: string = mimeType !== undefined && mimeType !== null && mimeType.trim().length > 0
      ? mimeType.trim()
      : 'image/jpeg';

    const clientId: string = MessageBusService.getInstance().getClientId();
    const form: Record<string, Object> = {};
    form['upload_type'] = 'composer';
    form['synchronous'] = 'true';

    const files: HttpMultipartFilePart[] = [{
      fieldName: 'file',
      fileName: normalizedFileName,
      mimeType: normalizedMimeType,
      data: bytes
    }];

    let queryParams: Record<string, Object> | null = null;
    if (clientId.trim().length > 0) {
      queryParams = {};
      queryParams['client_id'] = clientId.trim();
    }

    try {
      const rawText: string = await this.http.postMultipartText(
        ApiConstants.UPLOADS,
        form,
        files,
        queryParams
      );
      const json: Record<string, Object> = JSON.parse(rawText) as Record<string, Object>;
        const uploaded: UploadedImage = UploadedImage.fromJson(
          json,
          normalizedFileName,
          fallbackWidth,
          fallbackHeight
        );
        if (uploaded.hasUsableUrl()) {
          ComposerUploadUrlCache.register(uploaded.shortUrl, uploaded.url);
          return uploaded;
        }

      const errorsVal = json['errors'];
      if (errorsVal !== undefined && errorsVal !== null && Array.isArray(errorsVal)) {
        const errs: Object[] = errorsVal as Object[];
        let message: string = '';
        for (let i = 0; i < errs.length; i++) {
          const part: string = errs[i] !== undefined && errs[i] !== null ? errs[i].toString().trim() : '';
          if (part.length === 0) {
            continue;
          }
          message = message.length > 0 ? `${message}\n${part}` : part;
        }
        throw new Error(message.length > 0 ? message : '图片上传失败');
      }
      throw new Error('图片上传成功但未返回可用链接');
    } catch (err) {
      const message: string = err !== undefined && err !== null ? err.toString().replace('Error: ', '') : '图片上传失败';
      if (message.indexOf('HTTP 413') >= 0) {
        throw new Error('图片体积过大，请压缩后重试');
      }
      if (message.indexOf('HTTP 422') >= 0) {
        throw new Error('图片格式不受支持或上传被拒绝');
      }
      if (message.indexOf('HTTP 429') >= 0) {
        throw new Error('上传过于频繁，请稍后重试');
      }
      throw new Error(message.length > 0 ? message : '图片上传失败');
    }
  }

  /**
   * 创建私信
   */
  async createPrivateMessage(targetUsernames: string[], title: string, raw: string): Promise<number> {
    if (targetUsernames.length === 0) {
      throw new Error('缺少收件人');
    }

    const recipients: string[] = [];
    for (let i = 0; i < targetUsernames.length; i++) {
      const username: string = targetUsernames[i] !== undefined && targetUsernames[i] !== null
        ? targetUsernames[i].trim()
        : '';
      if (username.length > 0) {
        recipients.push(username);
      }
    }
    if (recipients.length === 0) {
      throw new Error('缺少收件人');
    }

    const form: Record<string, Object> = {};
    form['title'] = title;
    form['raw'] = raw;
    form['archetype'] = 'private_message';
    form['target_recipients'] = recipients.join(',');

    const rawText: string = await this.http.postFormText(ApiConstants.POSTS, form);
    const json: Record<string, Object> = JSON.parse(rawText) as Record<string, Object>;

    const actionVal = json['action'];
    if (actionVal !== undefined && actionVal !== null && actionVal.toString() === 'enqueued') {
      const pendingVal = json['pending_count'];
      const pendingCount: number = pendingVal !== undefined && pendingVal !== null ? Number(pendingVal.toString()) : 0;
      throw new PostEnqueuedError(pendingCount);
    }

    const postVal = json['post'];
    if (postVal !== undefined && postVal !== null && typeof postVal === 'object') {
      const postJson: Record<string, Object> = postVal as Record<string, Object>;
      const topicIdVal = postJson['topic_id'];
      if (topicIdVal !== undefined && topicIdVal !== null) {
        return Number(topicIdVal.toString());
      }
    }

    const topicIdVal = json['topic_id'];
    if (topicIdVal !== undefined && topicIdVal !== null) {
      return Number(topicIdVal.toString());
    }

    const successVal = json['success'];
    if (successVal !== undefined && successVal !== null && successVal.toString() === 'false') {
      const errorsVal = json['errors'];
      if (errorsVal !== undefined && errorsVal !== null && Array.isArray(errorsVal)) {
        const errs: Object[] = errorsVal as Object[];
        let message: string = '';
        for (let i = 0; i < errs.length; i++) {
          const part: string = errs[i] !== undefined && errs[i] !== null ? errs[i].toString() : '';
          if (part.length === 0) continue;
          message = message.length > 0 ? `${message}\n${part}` : part;
        }
        throw new Error(message.length > 0 ? message : '发送私信失败');
      }
      throw new Error('发送私信失败');
    }

    throw new Error('未知响应格式');
  }

  /**
   * 创建新话题
   */
  async createTopic(title: string, raw: string, categoryId: number, tags: string[] | null = null): Promise<number> {
    const normalizedTitle: string = title.trim();
    const normalizedRaw: string = raw.trim();
    if (normalizedTitle.length === 0) {
      throw new Error('请输入标题');
    }
    if (normalizedRaw.length === 0) {
      throw new Error('请输入内容');
    }

    const form: Record<string, Object> = {};
    form['title'] = normalizedTitle;
    form['raw'] = raw;
    if (categoryId > 0) {
      form['category'] = categoryId.toString();
    }
    if (tags !== null && tags.length > 0) {
      const cleanTags: string[] = [];
      for (let i = 0; i < tags.length; i++) {
        const tag: string = tags[i] !== undefined && tags[i] !== null ? tags[i].trim() : '';
        if (tag.length > 0) {
          cleanTags.push(tag);
        }
      }
      if (cleanTags.length > 0) {
        form['tags[]'] = cleanTags;
      }
    }

    const rawText: string = await this.http.postFormText(ApiConstants.POSTS, form);
    const json: Record<string, Object> = JSON.parse(rawText) as Record<string, Object>;

    const actionVal = json['action'];
    if (actionVal !== undefined && actionVal !== null && actionVal.toString() === 'enqueued') {
      const pendingVal = json['pending_count'];
      const pendingCount: number = pendingVal !== undefined && pendingVal !== null ? Number(pendingVal.toString()) : 0;
      throw new PostEnqueuedError(pendingCount);
    }

    const topicIdVal = json['topic_id'];
    if (topicIdVal !== undefined && topicIdVal !== null) {
      return Number(topicIdVal.toString());
    }

    const postVal = json['post'];
    if (postVal !== undefined && postVal !== null && typeof postVal === 'object') {
      const postJson: Record<string, Object> = postVal as Record<string, Object>;
      const postTopicIdVal = postJson['topic_id'];
      if (postTopicIdVal !== undefined && postTopicIdVal !== null) {
        return Number(postTopicIdVal.toString());
      }
    }

    const successVal = json['success'];
    if (successVal !== undefined && successVal !== null && successVal.toString() === 'false') {
      const errorsVal = json['errors'];
      if (errorsVal !== undefined && errorsVal !== null && Array.isArray(errorsVal)) {
        const errs: Object[] = errorsVal as Object[];
        let message: string = '';
        for (let i = 0; i < errs.length; i++) {
          const part: string = errs[i] !== undefined && errs[i] !== null ? errs[i].toString() : '';
          if (part.length === 0) continue;
          message = message.length > 0 ? `${message}\n${part}` : part;
        }
        throw new Error(message.length > 0 ? message : '发布话题失败');
      }
      throw new Error('发布话题失败');
    }

    throw new Error('未知响应格式');
  }

  /**
   * 获取指定草稿
   */
  async getDraft(draftKey: string): Promise<Draft | null> {
    if (draftKey.length === 0) {
      return null;
    }

    try {
      const rawText: string = await this.http.get(ApiConstants.draft(draftKey));
      const json: Record<string, Object> = JSON.parse(rawText) as Record<string, Object>;
      const draftVal = json['draft'];
      if (draftVal === undefined || draftVal === null) {
        return null;
      }
      const packed: Record<string, Object> = {};
      packed['draft_key'] = draftKey;
      packed['data'] = draftVal;
      const seqVal = json['draft_sequence'];
      packed['draft_sequence'] = seqVal !== undefined && seqVal !== null ? Number(seqVal.toString()) : 0;
      return Draft.fromJson(packed);
    } catch (err) {
      const text: string = err !== undefined && err !== null ? err.toString() : '';
      if (text.indexOf('HTTP 404') >= 0) {
        return null;
      }
      throw new Error(text.length > 0 ? text : '加载草稿失败');
    }
  }

  async getDrafts(offset: number = 0, limit: number = 20): Promise<DraftListResponse> {
    const params: Record<string, Object> = {};
    if (offset > 0) {
      params['offset'] = offset.toString();
    }
    if (limit > 0) {
      params['limit'] = limit.toString();
    }
    const rawText: string = await this.http.get(ApiConstants.DRAFTS, params);
    const json: Record<string, Object> = JSON.parse(rawText) as Record<string, Object>;
    return DraftListResponse.fromJson(json);
  }

  /**
   * 保存草稿
   */
  async saveDraft(draftKey: string, data: DraftData, sequence: number = 0): Promise<number> {
    const form: Record<string, Object> = {};
    form['draft_key'] = draftKey;
    form['data'] = data.toJsonString();
    form['sequence'] = sequence.toString();
    const rawText: string = await this.http.postFormText(ApiConstants.DRAFTS, form);
    const json: Record<string, Object> = JSON.parse(rawText) as Record<string, Object>;
    const seqVal = json['draft_sequence'];
    if (seqVal !== undefined && seqVal !== null) {
      return Number(seqVal.toString());
    }
    return sequence + 1;
  }

  /**
   * 删除草稿
   */
  async deleteDraft(draftKey: string, sequence: number = 0): Promise<void> {
    if (draftKey.length === 0) return;

    try {
      const form: Record<string, Object> = {};
      form['sequence'] = sequence.toString();
      await this.http.deleteForm(ApiConstants.deleteDraft(draftKey), form);
    } catch (err) {
      const text: string = err !== undefined && err !== null ? err.toString() : '';
      if (text.indexOf('HTTP 404') >= 0) {
        return;
      }
      throw new Error(text.length > 0 ? text : '删除草稿失败');
    }
  }

  /**
   * 投票
   */
  async votePoll(postId: number, pollName: string, options: string[]): Promise<Poll | null> {
    const form: Record<string, Object> = {};
    form['post_id'] = postId.toString();
    form['poll_name'] = pollName;
    form['options[]'] = options;
    const rawText: string = await this.http.putForm(ApiConstants.POLLS_VOTE, form);
    const json: Record<string, Object> = JSON.parse(rawText) as Record<string, Object>;
    const pollVal = json['poll'];
    if (pollVal !== undefined && pollVal !== null && typeof pollVal === 'object') {
      return Poll.fromJson(pollVal as Record<string, Object>);
    }
    return null;
  }

  /**
   * 撤销投票
   */
  async removeVote(postId: number, pollName: string): Promise<Poll | null> {
    const form: Record<string, Object> = {};
    form['post_id'] = postId.toString();
    form['poll_name'] = pollName;
    const rawText: string = await this.http.deleteForm(ApiConstants.POLLS_VOTE, form);
    const json: Record<string, Object> = JSON.parse(rawText) as Record<string, Object>;
    const pollVal = json['poll'];
    if (pollVal !== undefined && pollVal !== null && typeof pollVal === 'object') {
      return Poll.fromJson(pollVal as Record<string, Object>);
    }
    return null;
  }

  /**
   * 搜索
   */
  async search(query: string, page: number = 1, typeFilter: string = ''): Promise<SearchResult> {
    const params: Record<string, Object> = {};
    params['q'] = query;
    params['page'] = page.toString();
    const tf: string = typeFilter.trim();
    if (tf.length > 0) {
      params['type_filter'] = tf;
    }
    const raw: string = await this.http.get(ApiConstants.SEARCH, params);
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    return SearchResult.fromJson(json);
  }

  async getCurrentUser(): Promise<User | null> {
    if (this.hasFreshCurrentUserCache()) {
      return this.currentUserCache;
    }

    if (this.currentUserInFlight !== null) {
      return await this.currentUserInFlight;
    }

    if (this.currentUserRateLimitedUntil > Date.now()) {
      if (this.currentUserCache !== null) {
        return this.currentUserCache;
      }
      throw new Error('HTTP 429');
    }

    const sessionVersion: number = this.currentUserSessionVersion;
    const requestPromise: Promise<User | null> = this.fetchCurrentUserInternal(sessionVersion);
    this.currentUserInFlight = requestPromise;
    try {
      const currentUser: User | null = await requestPromise;
      if (sessionVersion !== this.currentUserSessionVersion) {
        return this.currentUserCache;
      }
      return currentUser;
    } catch (err) {
      if (sessionVersion !== this.currentUserSessionVersion) {
        return this.currentUserCache;
      }
      if (this.isRateLimitError(err)) {
        this.currentUserRateLimitedUntil = Date.now() + CURRENT_USER_RATE_LIMIT_COOLDOWN_MS;
        if (this.currentUserCache !== null) {
          hilog.warn(0x0000, TAG, 'getCurrentUser rate limited, falling back to cached current user');
          return this.currentUserCache;
        }
      }
      const errorText: string = err !== null && err !== undefined ? err.toString() : 'getCurrentUser failed';
      throw new Error(errorText);
    } finally {
      if (this.currentUserInFlight === requestPromise) {
        this.currentUserInFlight = null;
      }
    }
  }

  async getNotifications(offset: number = 0, limit: number = 60): Promise<NotificationListResponse> {
    const params: Record<string, Object> = {};
    if (limit > 0) {
      params['limit'] = limit.toString();
    }
    if (offset > 0) {
      params['offset'] = offset.toString();
    }
    const raw: string = await this.http.get(ApiConstants.NOTIFICATIONS, params);
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    return NotificationListResponse.fromJson(json);
  }

  async markAllNotificationsRead(): Promise<void> {
    await this.http.put(ApiConstants.NOTIFICATIONS_MARK_READ);
  }

  async markNotificationRead(id: number): Promise<void> {
    if (id <= 0) {
      return;
    }
    const form: Record<string, Object> = {};
    form['id'] = id.toString();
    await this.http.putForm(ApiConstants.NOTIFICATIONS_MARK_READ, form);
  }

  async getUserProfile(username: string): Promise<User> {
    const path: string = ApiConstants.userProfile(encodeURIComponent(username));
    const raw: string = await this.http.get(path);
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    const userVal = json['user'];
    const profileJson: Record<string, Object> = userVal !== undefined && userVal !== null && typeof userVal === 'object'
      ? userVal as Record<string, Object>
      : json;
    const parsedUser: User = User.fromJson(profileJson);
    if (parsedUser.username.trim().length === 0) {
      throw new Error('Invalid user profile response');
    }
    return parsedUser;
  }

  async getUserSummary(username: string): Promise<UserSummary> {
    const path: string = ApiConstants.userSummary(encodeURIComponent(username));
    const raw: string = await this.http.get(path);
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    return UserSummary.fromJson(json);
  }

  async getBrowsingHistory(page: number = 0): Promise<TopicListResponse> {
    let params: Record<string, Object> | null = null;
    if (page > 0) {
      const query: Record<string, Object> = {};
      query['page'] = page.toString();
      params = query;
    }
    const raw: string = await this.http.get(ApiConstants.READ_HISTORY, params);
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    return TopicListResponse.fromJson(json);
  }

  async getUserBookmarks(username: string, page: number = 0): Promise<TopicListResponse> {
    let params: Record<string, Object> | null = null;
    if (page > 0) {
      const query: Record<string, Object> = {};
      query['page'] = page.toString();
      params = query;
    }
    const path: string = ApiConstants.userBookmarks(encodeURIComponent(username));
    const raw: string = await this.http.get(path, params);
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    return TopicListResponse.fromJson(json);
  }

  async likePost(postId: number): Promise<void> {
    if (postId <= 0) {
      throw new Error('无效的帖子ID');
    }
    const form: Record<string, Object> = {};
    form['id'] = postId.toString();
    form['post_action_type_id'] = ApiClient.LIKE_POST_ACTION_TYPE_ID.toString();
    form['flag_topic'] = 'false';
    await this.http.postFormText(ApiConstants.POST_ACTION, form);
  }

  async unlikePost(postId: number): Promise<void> {
    if (postId <= 0) {
      throw new Error('无效的帖子ID');
    }
    await this.http.delete(ApiConstants.postAction(postId, ApiClient.LIKE_POST_ACTION_TYPE_ID));
  }

  async toggleReaction(postId: number, reactionId: string): Promise<PostReactionState> {
    if (postId <= 0) {
      throw new Error('无效的帖子ID');
    }
    const normalizedReactionId: string = reactionId !== undefined && reactionId !== null ? reactionId.toString().trim() : '';
    if (normalizedReactionId.length === 0) {
      throw new Error('无效的回应类型');
    }
    const resp: HttpTextResponse = await this.http.putDetailed(ApiConstants.togglePostReaction(postId, normalizedReactionId));
    if (resp.code < 200 || resp.code >= 300) {
      if (resp.code === 429) {
        const retryAfterSeconds: number = this.extractRetryAfterSecondsFromResponse(resp.header, resp.result);
        if (retryAfterSeconds > 0) {
          throw new Error(`HTTP 429 retry_after=${retryAfterSeconds}`);
        }
      }
      throw new Error(`HTTP ${resp.code}`);
    }
    const raw: string = resp.result;
    const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    return PostReactionState.fromJson(parsed);
  }

  private extractRetryAfterSecondsFromResponse(header: Object | null, result: string): number {
    const headerSeconds: number = this.extractRetryAfterSecondsFromHeader(header);
    if (headerSeconds > 0) {
      return headerSeconds;
    }
    const bodySeconds: number = this.extractRetryAfterSecondsFromBody(result);
    if (bodySeconds > 0) {
      return bodySeconds;
    }
    return 0;
  }

  private extractRetryAfterSecondsFromHeader(header: Object | null): number {
    if (header === null || header === undefined || typeof header !== 'object') {
      return 0;
    }
    const source: Record<string, Object> = header as Record<string, Object>;
    const keys: string[] = Object.keys(source);
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i].toLowerCase();
      if (key !== 'retry-after' && key !== 'retry_after') {
        continue;
      }
      const rawVal: Object = source[keys[i]];
      const text: string = rawVal !== undefined && rawVal !== null ? rawVal.toString().trim() : '';
      const matched: RegExpMatchArray | null = text.match(/(\d+)/);
      if (matched !== null && matched.length >= 2) {
        const parsed: number = Number(matched[1]);
        if (!isNaN(parsed) && parsed > 0) {
          return Math.ceil(parsed);
        }
      }
    }
    return 0;
  }

  private extractRetryAfterSecondsFromBody(result: string): number {
    const text: string = result !== undefined && result !== null ? result.toString().trim() : '';
    if (text.length === 0) {
      return 0;
    }
    try {
      const parsed: Object = JSON.parse(text) as Object;
      if (parsed !== null && typeof parsed === 'object') {
        const json: Record<string, Object> = parsed as Record<string, Object>;
        const retryAfterVal = json['retry_after'];
        if (retryAfterVal !== undefined && retryAfterVal !== null) {
          const retryAfter: number = Number(retryAfterVal.toString());
          if (!isNaN(retryAfter) && retryAfter > 0) {
            return Math.ceil(retryAfter);
          }
        }
        const extrasVal = json['extras'];
        if (extrasVal !== undefined && extrasVal !== null && typeof extrasVal === 'object') {
          const extras: Record<string, Object> = extrasVal as Record<string, Object>;
          const waitSecondsVal = extras['wait_seconds'];
          if (waitSecondsVal !== undefined && waitSecondsVal !== null) {
            const waitSeconds: number = Number(waitSecondsVal.toString());
            if (!isNaN(waitSeconds) && waitSeconds > 0) {
              return Math.ceil(waitSeconds);
            }
          }
        }
      }
    } catch (_) {
    }
    return 0;
  }

  async bookmarkTopic(topicId: number, name: string | null = null, reminderAt: Date | null = null): Promise<number> {
    if (topicId <= 0) {
      throw new Error('无效的话题ID');
    }
    const form: Record<string, Object> = {};
    form['bookmarkable_id'] = topicId.toString();
    form['bookmarkable_type'] = 'Topic';
    if (name !== null && name.trim().length > 0) {
      form['name'] = name.trim();
    }
    if (reminderAt !== null) {
      form['reminder_at'] = reminderAt.toISOString();
    }
    const rawText: string = await this.http.postFormText(ApiConstants.BOOKMARKS, form);
    const json: Record<string, Object> = JSON.parse(rawText) as Record<string, Object>;
    const idVal = json['id'];
    if (idVal !== undefined && idVal !== null) {
      const bookmarkId: number = Number(idVal.toString());
      if (!isNaN(bookmarkId) && bookmarkId > 0) {
        return bookmarkId;
      }
    }
    throw new Error('添加书签失败');
  }

  async bookmarkPost(postId: number, name: string | null = null, reminderAt: Date | null = null): Promise<number> {
    if (postId <= 0) {
      throw new Error('无效的帖子ID');
    }
    const form: Record<string, Object> = {};
    form['bookmarkable_id'] = postId.toString();
    form['bookmarkable_type'] = 'Post';
    if (name !== null && name.trim().length > 0) {
      form['name'] = name.trim();
    }
    if (reminderAt !== null) {
      form['reminder_at'] = reminderAt.toISOString();
    }
    const rawText: string = await this.http.postFormText(ApiConstants.BOOKMARKS, form);
    const json: Record<string, Object> = JSON.parse(rawText) as Record<string, Object>;
    const idVal = json['id'];
    if (idVal !== undefined && idVal !== null) {
      const bookmarkId: number = Number(idVal.toString());
      if (!isNaN(bookmarkId) && bookmarkId > 0) {
        return bookmarkId;
      }
    }
    throw new Error('添加书签失败');
  }

  async updateBookmark(bookmarkId: number, name: string | null = null, reminderAt: Date | null = null): Promise<void> {
    if (bookmarkId <= 0) {
      return;
    }
    const body: Record<string, Object> = {};
    if (name !== null) {
      body['name'] = name;
    }
    if (reminderAt !== null) {
      body['reminder_at'] = reminderAt.toISOString();
    }
    await this.http.put(ApiConstants.bookmark(bookmarkId), JSON.stringify(body));
  }

  async clearBookmarkReminder(bookmarkId: number): Promise<void> {
    if (bookmarkId <= 0) {
      return;
    }
    const body: Record<string, Object> = {};
    body['bookmark_ids'] = [bookmarkId];
    const operation: Record<string, Object> = {};
    operation['type'] = 'clear_reminder';
    body['operation'] = operation;
    await this.http.put(ApiConstants.BOOKMARKS_BULK, JSON.stringify(body));
  }

  async deleteBookmark(bookmarkId: number): Promise<void> {
    if (bookmarkId <= 0) {
      return;
    }
    await this.http.delete(ApiConstants.bookmark(bookmarkId));
  }

  async getUserCreatedTopics(username: string, page: number = 0): Promise<TopicListResponse> {
    let params: Record<string, Object> | null = null;
    if (page > 0) {
      const query: Record<string, Object> = {};
      query['page'] = page.toString();
      params = query;
    }
    const path: string = ApiConstants.userCreatedTopics(encodeURIComponent(username));
    const raw: string = await this.http.get(path, params);
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    return TopicListResponse.fromJson(json);
  }

  /**
   * 获取用户动态（/user_actions.json）
   */
  async getUserActions(username: string, filter: string = '', offset: number = 0): Promise<UserActionResponse> {
    const params: Record<string, Object> = {};
    params['username'] = username;
    const f: string = filter.trim();
    if (f.length > 0) params['filter'] = f;
    if (offset > 0) params['offset'] = offset.toString();

    const raw: string = await this.http.get(ApiConstants.USER_ACTIONS, params);
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    return UserActionResponse.fromJson(json);
  }

  /**
   * 获取用户回应（/discourse-reactions/posts/reactions.json）
   */
  async getUserReactions(username: string, beforeReactionUserId: number = 0): Promise<UserReactionsResponse> {
    const params: Record<string, Object> = {};
    params['username'] = username;
    if (beforeReactionUserId > 0) {
      params['before_reaction_user_id'] = beforeReactionUserId.toString();
    }

    const raw: string = await this.http.get(ApiConstants.USER_REACTIONS, params);
    const parsed: Object = JSON.parse(raw) as Object;
    return UserReactionsResponse.fromJson(parsed);
  }

  async getUserBadges(username: string): Promise<UserBadgeListResponse> {
    const params: Record<string, Object> = {};
    params['grouped'] = 'true';
    const raw: string = await this.http.get(ApiConstants.userBadges(encodeURIComponent(username)), params);
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    return UserBadgeListResponse.fromJson(json);
  }

  async getBadge(badgeId: number): Promise<Badge> {
    const raw: string = await this.http.get(ApiConstants.badge(badgeId));
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    const badgeVal = json['badge'];
    if (badgeVal === undefined || badgeVal === null || typeof badgeVal !== 'object') {
      throw new Error('徽章详情返回格式异常');
    }
    return Badge.fromJson(badgeVal as Record<string, Object>);
  }

  async getBadgeUsers(badgeId: number, username: string = ''): Promise<BadgeDetailResponse> {
    const params: Record<string, Object> = {};
    params['badge_id'] = badgeId.toString();
    const trimmedUsername: string = username.trim();
    if (trimmedUsername.length > 0) {
      params['username'] = trimmedUsername;
    }
    const raw: string = await this.http.get(ApiConstants.USER_BADGES, params);
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    return BadgeDetailResponse.fromJson(json);
  }

  /**
   * 获取关注列表
   */
  async getFollowing(username: string): Promise<FollowUser[]> {
    const raw: string = await this.http.get(ApiConstants.userFollowing(encodeURIComponent(username)));
    const parsed: Object = JSON.parse(raw) as Object;
    if (!(parsed instanceof Array)) {
      return [];
    }
    const arr: Object[] = parsed as Object[];
    const users: FollowUser[] = [];
    for (let i = 0; i < arr.length; i++) {
      users.push(FollowUser.fromJson(arr[i] as Record<string, Object>));
    }
    return users;
  }

  /**
   * 获取粉丝列表
   */
  async getFollowers(username: string): Promise<FollowUser[]> {
    const raw: string = await this.http.get(ApiConstants.userFollowers(encodeURIComponent(username)));
    const parsed: Object = JSON.parse(raw) as Object;
    if (!(parsed instanceof Array)) {
      return [];
    }
    const arr: Object[] = parsed as Object[];
    const users: FollowUser[] = [];
    for (let i = 0; i < arr.length; i++) {
      users.push(FollowUser.fromJson(arr[i] as Record<string, Object>));
    }
    return users;
  }

  /**
   * 关注用户
   */
  async followUser(username: string): Promise<void> {
    await this.http.put(ApiConstants.followUser(encodeURIComponent(username)));
  }

  /**
   * 取消关注用户
   */
  async unfollowUser(username: string): Promise<void> {
    await this.http.delete(ApiConstants.followUser(encodeURIComponent(username)));
  }

  /**
   * 更新话题通知级别（0=静音, 1=常规, 2=跟踪, 3=关注）
   */
  async updateTopicNotificationLevel(topicId: number, level: number): Promise<void> {
    if (topicId <= 0) {
      return;
    }
    const form: Record<string, Object> = {};
    form['notification_level'] = Math.max(0, Math.round(level)).toString();
    await this.http.postFormText(ApiConstants.topicNotificationLevel(topicId), form);
  }

  /**
   * 更新用户通知级别（normal/mute/ignore）
   */
  async updateUserNotificationLevel(username: string, level: string, expiringAt: string = ''): Promise<void> {
    const form: Record<string, Object> = {};
    form['notification_level'] = level;
    if (expiringAt.trim().length > 0) {
      form['expiring_at'] = expiringAt.trim();
    }
    await this.http.putForm(ApiConstants.userNotificationLevel(encodeURIComponent(username)), form);
  }
}
