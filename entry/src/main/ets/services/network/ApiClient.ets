import { hilog } from '@kit.PerformanceAnalysisKit';
import { CfGuardOptions, HttpClient } from './HttpClient';
import { ApiConstants } from '../../common/constants/ApiConstants';
import { AppConstants } from '../../common/constants/AppConstants';
import { Topic, TopicListResponse, Tag } from '../../models/Topic';
import { Category, SiteResponse } from '../../models/Category';
import { TagSearchResult, TagInfo } from '../../models/TagSearchResult';
import { FollowUser, User, UserSummary } from '../../models/User';
import { SearchResult } from '../../models/SearchResult';
import { Draft, DraftData, DraftListResponse } from '../../models/Draft';
import { Badge, BadgeDetailResponse, UserBadgeListResponse } from '../../models/Badge';
import { NotificationListResponse } from '../../models/Notification';
import { Poll, Post } from '../../models/Post';
import { UserActionResponse, UserReactionsResponse } from '../../models/UserAction';
import { PreloadedDataService } from '../messagebus/PreloadedDataService';
import { EmojiResolver } from '../../common/utils/EmojiResolver';

const TAG: string = 'ApiClient';
const MOCK_PAGE_SIZE: number = 30;
const CURRENT_USER_CACHE_TTL_MS: number = 5000;
const CURRENT_USER_RATE_LIMIT_COOLDOWN_MS: number = 8000;

export class PostEnqueuedError extends Error {
  pendingCount: number = 0;

  constructor(pendingCount: number = 0) {
    super('POST_ENQUEUED');
    this.pendingCount = pendingCount;
  }
}

const MOCK_TAG_NAMES: string[] = [
  'harmonyos',
  'flutter',
  'bug',
  'resource',
  'ai',
  'tips',
  'help',
  'showcase',
  'release',
  'design'
];

const MOCK_CATEGORY_IDS: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

const MOCK_TITLES: string[] = [
  '鸿蒙 ArkUI 组件复刻进度：欢迎对比指出细节差异',
  '【UI】TopicList Header 两段折叠怎么实现更丝滑？',
  '求助：ArkTS 的 List onScrollFrameBegin 如何正确使用？',
  '分享：我做了一个离线 Mock 数据模式，UI 验收终于不卡了',
  '置顶：新版本更新说明（Mock）',
  '热门：这个话题为什么点赞这么多？',
  '已解决：关于 canHaveAnswer / acceptedAnswer 的 UI 表达',
  '闭帖：请先阅读发帖规范再提问',
  '资源：网盘合集（示例）',
  '教程：从 Flutter 到 ArkUI 的布局映射速查表'
];

/**
 * Discourse API 客户端
 */
export class ApiClient {
  private http: HttpClient;
  private static instance: ApiClient | null = null;

  // 会话内缓存：避免多页面重复拉取 site.json
  private siteInfoCache: SiteResponse | null = null;
  private siteInfoInFlight: Promise<SiteResponse> | null = null;
  private currentUserCache: User | null = null;
  private currentUserCacheAt: number = 0;
  private currentUserInFlight: Promise<User | null> | null = null;
  private currentUserRateLimitedUntil: number = 0;
  private currentUserSessionVersion: number = 0;

  // -------------------- Mock Data --------------------
  private static mockInited: boolean = false;
  private static mockCategories: Category[] = [];
  private static mockTopics: Topic[] = [];
  private static mockTopicDetailJson: Map<number, string> = new Map();

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

  private static ensureMockData(): void {
    if (ApiClient.mockInited) return;
    ApiClient.mockInited = true;

    // 1) 分类
    const categories: Category[] = [];
    categories.push(ApiClient.createCategory(1, '开发调优', 'dev-opt', '26A69A', null));
    categories.push(ApiClient.createCategory(2, '国产替代', 'china-alt', '43A047', null));
    categories.push(ApiClient.createCategory(3, '资源荟萃', 'resources', 'FF8F00', null));
    categories.push(ApiClient.createCategory(4, '文档共建', 'docs', 'E53935', null));
    categories.push(ApiClient.createCategory(5, '非我莫属', 'who', '42A5F5', null));
    categories.push(ApiClient.createCategory(6, '读书成诗', 'reading', '26C6DA', null));
    categories.push(ApiClient.createCategory(7, '前沿快讯', 'news', 'F4511E', null));
    categories.push(ApiClient.createCategory(8, '网络记忆', 'memory', '546E7A', null));
    categories.push(ApiClient.createCategory(9, '福利羊毛', 'welfare', 'D81B60', null));
    categories.push(ApiClient.createCategory(10, '搞七捻三', 'misc', '8E24AA', null));
    categories.push(ApiClient.createCategory(11, '虫洞广场', 'wormhole', '5E35B1', null));
    categories.push(ApiClient.createCategory(12, '运营反馈', 'ops', '90A4AE', null));

    // 子分类：用于展示“▼”菜单
    categories.push(ApiClient.createCategory(31, '网盘资源', 'cloud', 'FFB300', 3));
    categories.push(ApiClient.createCategory(121, '公告', 'announcements', 'E53935', 12));
    categories.push(ApiClient.createCategory(122, '活动', 'events', '43A047', 12));
    categories.push(ApiClient.createCategory(123, '悬赏', 'bounty', 'FF8F00', 12));

    ApiClient.mockCategories = categories;

    // 2) 话题列表
    const topics: Topic[] = [];
    for (let i = 0; i < 60; i++) {
      const t = new Topic();
      t.id = 10000 + i;
      t.title = MOCK_TITLES[i % MOCK_TITLES.length] + (i % 2 === 0 ? '' : ` #${i}`);
      t.slug = `topic-${t.id}`;

      const catId: number = MOCK_CATEGORY_IDS[i % MOCK_CATEGORY_IDS.length];
      t.categoryId = catId.toString();

      t.pinned = i < 2;
      t.closed = i === 7 || (i % 17 === 0);

      // 回复与点赞
      const basePosts: number = 1 + (i % 40);
      t.postsCount = basePosts + (i % 3 === 0 ? 20 : 0);
      t.replyCount = Math.max(0, t.postsCount - 1);
      t.likeCount = (i % 6 === 0)
        ? (t.postsCount * 2 + 30)
        : (i % 4 === 0 ? 12 + (i % 20) : (i % 3 === 0 ? 3 : 0));
      t.views = 100 + i * 37;

      // 时间
      t.createdAt = ApiClient.dateMinutesAgo(60 * 24 * (i % 7) + i);
      t.lastPostedAt = ApiClient.dateMinutesAgo(5 * i + (i % 9) * 3);
      t.lastPosterUsername = i % 2 === 0 ? 'alice' : (i % 3 === 0 ? 'bob' : 'charlie');

      // 已读/未读状态
      t.unseen = i % 5 === 0;
      t.unread = t.unseen ? 0 : (i % 7 === 0 ? (i % 6) + 1 : 0);
      t.lastReadPostNumber = (!t.unseen && t.unread === 0 && i % 4 === 0) ? (t.postsCount - 1) : 0;
      t.highestPostNumber = t.postsCount;

      // 已解决/可回答
      t.canHaveAnswer = i % 4 === 0;
      t.hasAcceptedAnswer = (i % 9 === 0);

      // tags
      t.tags = ApiClient.makeTags(i);

      topics.push(t);
    }
    ApiClient.mockTopics = topics;

    // 3) 话题详情 JSON
    for (let i = 0; i < 10; i++) {
      const topic: Topic = topics[i];
      ApiClient.mockTopicDetailJson.set(topic.id, ApiClient.buildMockTopicDetailJson(topic));
    }
  }

  private static createCategory(id: number, name: string, slug: string, color: string, parentId: number | null): Category {
    const c = new Category();
    c.id = id;
    c.name = name;
    c.slug = slug;
    c.color = color;
    c.textColor = 'FFFFFF';
    c.parentCategoryId = parentId;
    c.readRestricted = false;
    c.uploadedLogo = null;
    c.icon = null;
    return c;
  }

  private static makeTags(seed: number): Tag[] {
    const tags: Tag[] = [];
    const count: number = 1 + (seed % 3);
    for (let i = 0; i < count; i++) {
      const t = new Tag();
      const idx: number = (seed + i * 3) % MOCK_TAG_NAMES.length;
      t.name = MOCK_TAG_NAMES[idx];
      tags.push(t);
    }
    return tags;
  }

  private static dateMinutesAgo(mins: number): Date {
    return new Date(Date.now() - mins * 60 * 1000);
  }

  private static findMockTopicById(id: number): Topic | null {
    for (let i = 0; i < ApiClient.mockTopics.length; i++) {
      const t: Topic = ApiClient.mockTopics[i];
      if (t.id === id) return t;
    }
    return null;
  }

  private static buildMockTopicDetailJson(topic: Topic): string {
    const topicId: number = topic.id;
    const title: string = topic.title;
    const hasAccepted: boolean = topic.hasAcceptedAnswer;
    const acceptedAnswerPostNumber: number = hasAccepted ? 3 : 0;
    const closed: boolean = topic.closed;

    const now: Date = new Date();
    const createdAtIso: string = topic.createdAt !== null ? (topic.createdAt as Date).toISOString() : now.toISOString();
    const lastPostedAtIso: string = topic.lastPostedAt !== null ? (topic.lastPostedAt as Date).toISOString() : createdAtIso;

    const catParsed: number = parseInt(topic.categoryId);
    const categoryId: number = isNaN(catParsed) ? 1 : catParsed;

    const tags: string[] = [];
    for (let i = 0; i < topic.tags.length; i++) {
      const t: Tag = topic.tags[i];
      if (t.name.length > 0) {
        tags.push(t.name);
      }
    }

    const posts: Object[] = [];

    // small_action（对齐安卓：仅在 closed 等真实系统操作时才会出现；不要用 pinned.enabled 造假）
    if (closed) {
      const smallAction: Record<string, Object> = {};
      smallAction['id'] = topicId * 10 + 1;
      smallAction['username'] = 'system';
      smallAction['avatar_template'] = '/letter_avatar_proxy/v4/letter/s/000000/{size}.png';
      smallAction['cooked'] = '';
      smallAction['post_number'] = 0;
      smallAction['post_type'] = 3;
      smallAction['created_at'] = ApiClient.isoMinutesAgo(now, 600);
      smallAction['like_count'] = 0;
      smallAction['reply_count'] = 0;
      smallAction['action_code'] = 'closed.enabled';
      smallAction['accepted_answer'] = false;
      posts.push(smallAction);
    }

    // first post
    const firstPost: Record<string, Object> = {};
    firstPost['id'] = topicId * 10 + 2;
    firstPost['name'] = 'Alice';
    firstPost['username'] = 'alice';
    firstPost['avatar_template'] = '/letter_avatar_proxy/v4/letter/a/3366cc/{size}.png';
    firstPost['cooked'] =
      `<p>这里是 <b>Mock</b> 首贴内容，用于离线验收 UI。</p>\n` +
      `<blockquote>引用块示例：对齐安卓端样式</blockquote>\n` +
      `<pre><code class=\"language-arkts\">@ComponentV2\nstruct Demo {\n  build() { Text('Hello') }\n}</code></pre>\n` +
      `<p>图片位：<img src=\"mock://image\" /></p>`;
    firstPost['post_number'] = 1;
    firstPost['post_type'] = 1;
    firstPost['created_at'] = ApiClient.isoMinutesAgo(now, 580);
    firstPost['like_count'] = 12;
    // 对齐安卓：首贴不显示“回复数折叠按钮”，因此这里不造 reply_count
    firstPost['reply_count'] = 0;
    firstPost['actions_summary'] = ApiClient.buildLikeActionSummary(true);
    firstPost['accepted_answer'] = false;
    posts.push(firstPost);

    // reply 1
    const reply1: Record<string, Object> = {};
    reply1['id'] = topicId * 10 + 3;
    reply1['name'] = 'Bob';
    reply1['username'] = 'bob';
    reply1['avatar_template'] = '/letter_avatar_proxy/v4/letter/b/00acc1/{size}.png';
    reply1['cooked'] = `<p>回复示例：<code>onScrollFrameBegin</code> 可以用于消费 offset 以实现两段折叠。</p>`;
    reply1['post_number'] = 2;
    reply1['post_type'] = 1;
    reply1['created_at'] = ApiClient.isoMinutesAgo(now, 520);
    reply1['like_count'] = 3;
    // 用于离线验收“楼层回复折叠”：#2 有 1 条回复（来自 #4）
    reply1['reply_count'] = 1;
    reply1['actions_summary'] = ApiClient.buildLikeActionSummary(false);
    reply1['accepted_answer'] = false;
    posts.push(reply1);

    // reply 2
    const reply2: Record<string, Object> = {};
    reply2['id'] = topicId * 10 + 4;
    reply2['name'] = 'Charlie';
    reply2['username'] = 'charlie';
    reply2['avatar_template'] = '/letter_avatar_proxy/v4/letter/c/43a047/{size}.png';
    reply2['cooked'] = `<p>再来一个短回复，测试底部操作行布局与分割线。</p>`;
    reply2['post_number'] = 3;
    reply2['post_type'] = 1;
    reply2['created_at'] = ApiClient.isoMinutesAgo(now, 480);
    reply2['like_count'] = 0;
    reply2['reply_count'] = 0;
    reply2['accepted_answer'] = hasAccepted;
    posts.push(reply2);

    // reply 3（楼主回帖：用于验收“主”标识 + reply_to 关系 + 楼层回复折叠展示）
    const reply3: Record<string, Object> = {};
    reply3['id'] = topicId * 10 + 5;
    reply3['name'] = 'Alice';
    reply3['username'] = 'alice';
    reply3['avatar_template'] = '/letter_avatar_proxy/v4/letter/a/3366cc/{size}.png';
    reply3['cooked'] = `<p>楼主回帖示例：这里会显示 <b>主</b> 标识，并且作为对 #2 的回复用于测试折叠回复列表。</p>`;
    reply3['post_number'] = 4;
    reply3['post_type'] = 1;
    reply3['created_at'] = ApiClient.isoMinutesAgo(now, 470);
    reply3['like_count'] = 1;
    reply3['reply_count'] = 0;
    reply3['reply_to_post_number'] = 2;
    const replyToUser: Record<string, Object> = {};
    replyToUser['username'] = 'bob';
    replyToUser['name'] = 'Bob';
    replyToUser['avatar_template'] = '/letter_avatar_proxy/v4/letter/b/00acc1/{size}.png';
    reply3['reply_to_user'] = replyToUser;
    reply3['accepted_answer'] = false;
    posts.push(reply3);

    const json: Record<string, Object> = {};
    json['id'] = topicId;
    json['title'] = title;
    // 对齐安卓：reply_count 与 posts_count 要与帖子流一致（离线验收以 UI 为主，避免出现 1/2 但实际列表有 4 项的错觉）
    json['posts_count'] = 4;
    json['reply_count'] = 3;
    json['views'] = topic.views;
    json['category_id'] = categoryId;
    json['tags'] = tags;
    json['created_at'] = createdAtIso;
    json['last_posted_at'] = lastPostedAtIso;
    json['closed'] = closed;
    json['has_accepted_answer'] = hasAccepted;
    json['bookmarked'] = false;
    if (acceptedAnswerPostNumber > 0) {
      const acceptedAnswer: Record<string, Object> = {};
      acceptedAnswer['post_number'] = acceptedAnswerPostNumber;
      json['accepted_answer'] = acceptedAnswer;
    }

    const postStream: Record<string, Object> = {};
    postStream['posts'] = posts;
    json['post_stream'] = postStream;

    return JSON.stringify(json);
  }

  private static isoMinutesAgo(base: Date, mins: number): string {
    return new Date(base.getTime() - mins * 60 * 1000).toISOString();
  }

  private static buildLikeActionSummary(acted: boolean): Object[] {
    const list: Object[] = [];
    const action: Record<string, Object> = {};
    action['id'] = 2;
    action['acted'] = acted;
    list.push(action);
    return list;
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
   * 对齐 Flutter：/latest.json?topic_ids=1,2,3
   */
  async getTopicsByIds(topicIds: number[]): Promise<TopicListResponse> {
    if (topicIds.length === 0) {
      return new TopicListResponse();
    }
    if (AppConstants.USE_MOCK_DATA) {
      ApiClient.ensureMockData();
      // Mock：直接从本地 mockTopics 中挑选并返回（不保证顺序与线上一致，仅用于离线展示）
      const selected: Topic[] = [];
      for (let i = 0; i < topicIds.length; i++) {
        const t: Topic | null = ApiClient.findMockTopicById(topicIds[i]);
        if (t !== null) selected.push(t as Topic);
      }
      const resp: TopicListResponse = new TopicListResponse();
      resp.topics = selected;
      resp.moreTopicsUrl = null;
      resp.perPage = MOCK_PAGE_SIZE;
      return resp;
    }

    const params: Record<string, Object> = {};
    params['topic_ids'] = topicIds.join(',');
    const result: string = await this.http.get(ApiConstants.TOPIC_LIST, params);
    const json: Record<string, Object> = JSON.parse(result) as Record<string, Object>;
    return TopicListResponse.fromJson(json);
  }

  /**
   * 获取话题列表（支持分类/标签/排序/period）
   * 对齐 Flutter: DiscourseService.getFilteredTopics
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
    if (AppConstants.USE_MOCK_DATA) {
      ApiClient.ensureMockData();
      const id: number | null = categoryId !== null ? categoryId : null;
      return ApiClient.mockGetTopicList(id, page);
    }

    // 构造 path（分类优先，其次纯标签，否则全站）
    // 对齐 Flutter/安卓：
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
   * 对齐 Flutter: /tags/filter/search?q=xxx&limit=8&selected_tags=...
   */
  async searchTags(
    query: string = '',
    categoryId: number | null = null,
    selectedTags: string[] | null = null,
    limit: number = 8,
    filterForInput: boolean = false
  ): Promise<TagSearchResult> {
    if (AppConstants.USE_MOCK_DATA) {
      const r: TagSearchResult = new TagSearchResult();
      const q: string = query.trim().toLowerCase();
      const list: TagInfo[] = [];
      for (let i = 0; i < MOCK_TAG_NAMES.length; i++) {
        const name: string = MOCK_TAG_NAMES[i];
        if (q.length > 0 && name.toLowerCase().indexOf(q) < 0) continue;
        const info: TagInfo = new TagInfo();
        info.name = name;
        info.text = name;
        info.count = 0;
        list.push(info);
        if (limit > 0 && list.length >= limit) break;
      }
      r.results = list;
      r.requiredTagGroup = null;
      return r;
    }

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
      // 对齐 Flutter：selected_tags=tag1&selected_tags=tag2...
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
    if (AppConstants.USE_MOCK_DATA) {
      ApiClient.ensureMockData();
      const response = new SiteResponse();
      response.categories = ApiClient.mockCategories;
      return response;
    }

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

  private async fetchSiteInfo(): Promise<SiteResponse> {
    const result: string = await this.http.get(ApiConstants.SITE);
    const json: Record<string, Object> = JSON.parse(result) as Record<string, Object>;
    this.tryConfigureMessageBusFromSiteJson(json);
    EmojiResolver.configureFromSiteJson(json);
    return SiteResponse.fromJson(json);
  }

  async getBrowsingHistory(page: number = 0): Promise<TopicListResponse> {
    if (AppConstants.USE_MOCK_DATA) {
      ApiClient.ensureMockData();
      return ApiClient.mockGetTopicList(null, page);
    }

    const params: Record<string, Object> = {};
    if (page > 0) {
      params['page'] = page.toString();
    }
    const raw: string = await this.http.get(ApiConstants.READ_HISTORY, Object.keys(params).length > 0 ? params : null);
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    return TopicListResponse.fromJson(json);
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
    if (AppConstants.USE_MOCK_DATA) {
      ApiClient.ensureMockData();
      if (ApiClient.mockTopicDetailJson.has(id)) {
        return ApiClient.mockTopicDetailJson.get(id) as string;
      }
      // fallback：动态生成（尽量复用列表中的 meta 字段，保证离线验收一致）
      const found: Topic | null = ApiClient.findMockTopicById(id);
      if (found !== null) {
        return ApiClient.buildMockTopicDetailJson(found as Topic);
      }
      const fallback: Topic = new Topic();
      fallback.id = id;
      fallback.title = `离线话题 #${id}`;
      fallback.categoryId = '1';
      fallback.postsCount = 24;
      fallback.replyCount = 23;
      fallback.views = 174;
      fallback.createdAt = new Date();
      fallback.lastPostedAt = fallback.createdAt;
      fallback.tags = ApiClient.makeTags(id);
      fallback.closed = false;
      fallback.hasAcceptedAnswer = false;
      return ApiClient.buildMockTopicDetailJson(fallback);
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return [];
    }
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
   * 失败时返回空字符串（对齐安卓导出兜底策略）
   */
  async getPostRaw(postId: number): Promise<string> {
    if (AppConstants.USE_MOCK_DATA) {
      return '';
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return [];
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      const post: Post = new Post();
      post.id = Date.now();
      post.username = 'you';
      post.name = 'You';
      post.cooked = raw;
      post.postNumber = 1;
      post.postType = 1;
      post.createdAt = new Date();
      post.updatedAt = new Date();
      post.replyToPostNumber = replyToPostNumber;
      return post;
    }

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

  /**
   * 创建私信
   */
  async createPrivateMessage(targetUsernames: string[], title: string, raw: string): Promise<number> {
    if (AppConstants.USE_MOCK_DATA) {
      return Date.now();
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return Date.now();
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return null;
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return new DraftListResponse();
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return sequence + 1;
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return;
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return null;
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return null;
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return SearchResult.empty();
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      const u: User = new User();
      u.username = 'alice';
      u.name = 'Alice';
      u.trustLevel = 2;
      return u;
    }

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
    if (AppConstants.USE_MOCK_DATA) {
      return new NotificationListResponse();
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return;
    }
    await this.http.put(ApiConstants.NOTIFICATIONS_MARK_READ);
  }

  async markNotificationRead(id: number): Promise<void> {
    if (AppConstants.USE_MOCK_DATA || id <= 0) {
      return;
    }
    const form: Record<string, Object> = {};
    form['id'] = id.toString();
    await this.http.putForm(ApiConstants.NOTIFICATIONS_MARK_READ, form);
  }

  async getUserProfile(username: string): Promise<User> {
    if (AppConstants.USE_MOCK_DATA) {
      const u = new User();
      u.username = username;
      u.name = username;
      return u;
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return new UserSummary();
    }
    const path: string = ApiConstants.userSummary(encodeURIComponent(username));
    const raw: string = await this.http.get(path);
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    return UserSummary.fromJson(json);
  }

  async getUserBookmarks(username: string, page: number = 0): Promise<TopicListResponse> {
    if (AppConstants.USE_MOCK_DATA) {
      return ApiClient.mockGetTopicList(null, page);
    }
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

  async updateBookmark(bookmarkId: number, name: string | null = null, reminderAt: Date | null = null): Promise<void> {
    if (AppConstants.USE_MOCK_DATA || bookmarkId <= 0) {
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
    if (AppConstants.USE_MOCK_DATA || bookmarkId <= 0) {
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
    if (AppConstants.USE_MOCK_DATA || bookmarkId <= 0) {
      return;
    }
    await this.http.delete(ApiConstants.bookmark(bookmarkId));
  }

  async getUserCreatedTopics(username: string, page: number = 0): Promise<TopicListResponse> {
    if (AppConstants.USE_MOCK_DATA) {
      return ApiClient.mockGetTopicList(null, page);
    }
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

  private static mockGetTopicList(categoryId: number | null, page: number): TopicListResponse {
    const list = new TopicListResponse();
    list.perPage = MOCK_PAGE_SIZE;

    let data: Topic[] = ApiClient.mockTopics;
    if (categoryId !== null) {
      const filtered: Topic[] = [];
      for (let i = 0; i < data.length; i++) {
        const t = data[i];
        if (parseInt(t.categoryId) === categoryId) {
          filtered.push(t);
        }
      }
      data = filtered;
    }

    const start: number = Math.max(0, page) * MOCK_PAGE_SIZE;
    const end: number = Math.min(data.length, start + MOCK_PAGE_SIZE);
    const pageItems: Topic[] = [];
    for (let i = start; i < end; i++) {
      pageItems.push(data[i]);
    }

    list.topics = pageItems;
    list.moreTopicsUrl = end < data.length ? '/mock/more' : null;
    return list;
  }

  /**
   * 获取用户动态（/user_actions.json）
   */
  async getUserActions(username: string, filter: string = '', offset: number = 0): Promise<UserActionResponse> {
    if (AppConstants.USE_MOCK_DATA) {
      return new UserActionResponse();
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return new UserReactionsResponse();
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return new UserBadgeListResponse();
    }
    const params: Record<string, Object> = {};
    params['grouped'] = 'true';
    const raw: string = await this.http.get(ApiConstants.userBadges(encodeURIComponent(username)), params);
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    return UserBadgeListResponse.fromJson(json);
  }

  async getBadge(badgeId: number): Promise<Badge> {
    if (AppConstants.USE_MOCK_DATA) {
      return new Badge();
    }
    const raw: string = await this.http.get(ApiConstants.badge(badgeId));
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    const badgeVal = json['badge'];
    if (badgeVal === undefined || badgeVal === null || typeof badgeVal !== 'object') {
      throw new Error('徽章详情返回格式异常');
    }
    return Badge.fromJson(badgeVal as Record<string, Object>);
  }

  async getBadgeUsers(badgeId: number, username: string = ''): Promise<BadgeDetailResponse> {
    if (AppConstants.USE_MOCK_DATA) {
      return new BadgeDetailResponse();
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return [];
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return [];
    }
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
    if (AppConstants.USE_MOCK_DATA) {
      return;
    }
    await this.http.put(ApiConstants.followUser(encodeURIComponent(username)));
  }

  /**
   * 取消关注用户
   */
  async unfollowUser(username: string): Promise<void> {
    if (AppConstants.USE_MOCK_DATA) {
      return;
    }
    await this.http.delete(ApiConstants.followUser(encodeURIComponent(username)));
  }

  /**
   * 更新用户通知级别（normal/mute/ignore）
   */
  async updateUserNotificationLevel(username: string, level: string, expiringAt: string = ''): Promise<void> {
    if (AppConstants.USE_MOCK_DATA) {
      return;
    }
    const form: Record<string, Object> = {};
    form['notification_level'] = level;
    if (expiringAt.trim().length > 0) {
      form['expiring_at'] = expiringAt.trim();
    }
    await this.http.putForm(ApiConstants.userNotificationLevel(encodeURIComponent(username)), form);
  }
}
