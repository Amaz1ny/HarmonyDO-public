import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { componentSnapshot } from '@kit.ArkUI';
import fileIo from '@ohos.file.fs';
import { Post, ReplyToUser } from '../../models/Post';
import { Category, SiteResponse } from '../../models/Category';
import { GrantedBadge } from '../../models/Badge';
import { UserStatus } from '../../models/User';
import { ApiClient } from '../../services/network/ApiClient';
import { AuthService } from '../../services/auth/AuthService';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';
import { SmartAvatar } from '../components/SmartAvatar';
import { AvatarWithFlair } from '../components/AvatarWithFlair';
import { TimeUtils } from '../../common/utils/TimeUtils';
import { UrlUtils } from '../../common/utils/UrlUtils';
import { RouterManager } from '../../common/utils/RouterManager';
import { TagBadge as TopicTagBadge } from '../components/TopicBadges';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { WindowManager } from '../../common/utils/WindowManager';
import { SearchPost, SearchResult } from '../../models/SearchResult';
import { ShareUtils } from '../../common/utils/ShareUtils';
import { SystemShareService } from '../../common/utils/SystemShareService';
import { ExternalLinkService } from '../../common/utils/ExternalLinkService';
import { ToastService } from '../../common/utils/ToastService';
import { ClipboardService } from '../../common/utils/ClipboardService';
import { ExportUtils } from '../../common/utils/ExportUtils';
import { MediaSaveService } from '../../common/utils/MediaSaveService';
import { DownloadedImage, ImageDownloadService } from '../../common/utils/ImageDownloadService';
import { HtmlTextMapper } from '../../common/utils/HtmlTextMapper';
import { HtmlToMarkdown } from '../../common/utils/HtmlToMarkdown';
import { PostRichContent } from '../components/PostRichContent';
import { PostLinks } from '../components/PostLinks';
import { ReplyComposerSheet } from '../components/ReplyComposerSheet';
import { UserStatusEmoji } from '../components/UserStatusEmoji';
import { AppContext } from '../../common/utils/AppContext';
import { PostShareImageParams, postShareImageBuilder } from '../components/PostShareImageCard';
import { PreferencesUtil } from '../../services/storage/PreferencesUtil';
import { MessageBusMessage, MessageBusService } from '../../services/messagebus/MessageBusService';
import {
  FLOATING_TAB_BAR_HEIGHT_VP,
  FLOATING_TAB_BAR_RADIUS_VP,
  FLOATING_TAB_BAR_MARGIN_H_VP,
  FLOATING_TAB_BAR_MARGIN_BOTTOM_VP,
  FLOATING_TAB_BAR_CONTENT_EXTRA_PADDING_VP
} from '../../common/constants/LayoutConstants';

const TAG: string = 'TopicDetailPage';
const TITLE_SHOW_OFFSET: number = 160;
const BOTTOM_BAR_HEIGHT: number = 56;
const BOTTOM_BAR_TOGGLE_DELTA: number = 50;
const BOTTOM_BAR_ANIM_DURATION: number = 180;
const BOTTOM_BAR_HIDE_EXTRA_TRANSLATE: number = 24;
const PROGRESS_CAPSULE_HEIGHT: number = 32;
const PROGRESS_BOTTOM_NO_BAR: number = 24;
const PROGRESS_GAP_ABOVE_BAR: number = 16;
const POSTS_PAGE_CHUNK: number = 20;
const BADGE_PADDING_H: number = 8;
const BADGE_PADDING_V: number = 3;
const BADGE_RADIUS: number = 6;
const BADGE_ICON_SIZE: number = 10;
const BADGE_FONT_SIZE: number = 10;
const PREF_KEY_SHARE_IMAGE_THEME: string = 'share_image_theme_v1';
const SHARE_IMAGE_THEME_NAMES: string[] = ['经典', '纯白', '深色', '纯黑', '蓝调', '绿野'];
const SHARE_IMAGE_THEME_COLORS: string[] = ['#F3EBDD', '#FFFFFF', '#1C1C1E', '#000000', '#D9E8FF', '#DDF3E2'];
const SHARE_IMAGE_THEME_INDICES: number[] = [0, 1, 2, 3, 4, 5];
const SHARE_IMAGE_SNAPSHOT_DELAY_MS: number = 240;

/**
 * 话题详情页面 — 100% 复刻安卓版
 *
 * 主体布局：
 * - AppBar：返回按钮 + 标题（滚动后显示）+ 搜索按钮 + 更多菜单
 * - 内容：帖子列表（含首贴header + 回复帖子）
 * - 浮层：
 *   - 进度胶囊（如"3/42"）
 *   - 底部工具栏：回到顶部 | 热门回复 | 只看题主 | 分享 | 浏览器
 *   - FAB 回复按钮（右下浮动，游客态隐藏）
 */
@ComponentV2
export struct TopicDetailPage {
  @Param topicId: number = 0;
  @Param initialPostNumber: number = 0;
  @Local topicTitle: string = '';
  @Local topicSlug: string = '';
  @Local topicViews: number = 0;
  @Local topicTags: string[] = [];
  @Local topicCreatedAt: Date | null = null;
  @Local topicLastPostedAt: Date | null = null;
  @Local topicTotalPostsCount: number = 0;
  @Local topicCategoryId: number = 0;
  @Local topicCategory: Category | null = null;
  @Local notificationLevelLabel: string = '常规';
  @Local topicOwnerUsername: string = '';
  @Local streamIds: number[] = [];
  @Local hasSummary: boolean = false;
  @Local notificationLevel: number = 1;

  // 游客态：隐藏回复入口（后续接入登录态后再开放）
  @Local isGuestMode: boolean = true;

  @Local posts: Post[] = [];
  @Local isLoading: boolean = true;
  @Local errorMessage: string = '';
  @Local replyCount: number = 0;
  @Local postsCount: number = 0;
  @Local currentPostIndex: number = 1;

  // 跳楼后短暂高亮（对齐安卓）
  @Local highlightPostNumber: number = 0;
  @Local highlightOpacity: number = 0;
  @Local timeTick: number = 0;
  @Local showBottomBar: boolean = false;
  @Local bottomBarVisibility: number = 0;
  @Local isSummaryMode: boolean = false;
  @Local isAuthorOnlyMode: boolean = false;
  @Local isClosed: boolean = false;
  @Local hasAcceptedAnswer: boolean = false;
  @Local acceptedAnswerPostNumber: number = 0;
  @Local isBookmarked: boolean = false;
  @Local expandedRepliesPostNumber: number = 0;
  @Local expandedRepliesLoading: boolean = false;
  @Local expandedRepliesErrorMessage: string = '';
  @Local expandedReplies: Post[] = [];
  @Local targetPostNumber: number = 0;

  // 分页：向前/向后补齐（完整阅读）
  @Local hasMoreBefore: boolean = false;
  @Local hasMoreAfter: boolean = false;
  @Local isLoadingMore: boolean = false;
  @Local isLoadMoreFailed: boolean = false;
  @Local isLoadingPrevious: boolean = false;
  @Local isLoadPreviousFailed: boolean = false;

  // AppBar 标题显隐（滚动后显示）
  @Local showTitle: boolean = false;
  @Local scrollOffset: number = 0;
  private _bottomBarDelta: number = 0;
  private listScroller: Scroller = new Scroller();
  private didScrollToInitial: boolean = false;
  private streamIndexMap: Map<number, number> = new Map();

  // 话题内搜索模式（对齐安卓）
  @Local isSearchMode: boolean = false;
  @Local searchQuery: string = '';
  @Local searchResults: SearchPost[] = [];
  @Local searchPage: number = 1;
  @Local searchHasMore: boolean = false;
  @Local isSearchLoading: boolean = false;
  @Local isSearchLoadingMore: boolean = false;
  @Local searchErrorMessage: string = '';
  private searchScroller: Scroller = new Scroller();

  // 时间线跳楼（Sheet）
  @Local isTimelineSheetVisible: boolean = false;
  @Local timelineInput: string = '';
  @Local timelineSelected: number = 1;
  @Local isTimelineEditMode: boolean = false;

  // 生成分享图片（Sheet）
  @Local isShareImageSheetVisible: boolean = false;
  @Local shareImageLoading: boolean = false;
  @Local shareImageErrorMessage: string = '';
  @Local shareImagePixelMap: image.PixelMap | null = null;
  @Local shareImageFileUri: string = '';
  @Local shareImageTargetPostNumber: number = 0;
  @Local shareImageParams: PostShareImageParams = new PostShareImageParams();
  @Local shareImageThemeIndex: number = 0;
  @Local shareImageCardId: string = 'share_post_card_0';

  // 图片长按菜单（Sheet）
  @Local isImageContextSheetVisible: boolean = false;
  @Local imageContextThumbUrl: string = '';
  @Local imageContextPreviewUrl: string = '';
  @Local imageContextPostNumber: number = 0;
  @Local imageContextUsername: string = '';
  @Local imageContextAvatarTemplate: string = '';

  // 回复输入面板（Sheet）
  @Local isReplySheetVisible: boolean = false;
  @Local replySheetTargetPostNumber: number = 0;
  @Local replySheetTargetUsername: string = '';
  @Local replySheetTargetAvatarTemplate: string = '';
  @Local replySheetInitialContent: string = '';
  @Local replySheetRequestKey: string = '';

  // 导出文章（Sheet）
  @Local isExportSheetVisible: boolean = false;
  @Local exportScope: number = 0; // 0=仅主帖 1=全部
  @Local exportFormat: number = 0; // 0=MD 1=HTML
  @Local exportLoading: boolean = false;
  @Local exportErrorMessage: string = '';
  @Local exportProgressText: string = '';

  private timeTickTimerId: number = -1;
  private shareImageRequestId: number = 0;
  private shareImageLastScheduledRequestId: number = -1;
  private shareImagePngBuffer: ArrayBuffer | null = null;
  private highlightTimerId: number = -1;
  private pendingHighlightPostNumber: number = 0;
  private pendingHighlightListIndex: number = -1;
  private lastVisibleStartIndex: number = 0;
  private lastVisibleEndIndex: number = 0;
  private pendingReplyScrollPostNumber: number = 0;

  // MessageBus：话题频道（实时新回复，对齐安卓）
  private topicChannelKey: string = '';
  private reactionsChannelKey: string = '';
  private topicChannelCallback: ((message: MessageBusMessage) => void) | null = null;
  private reactionsChannelCallback: ((message: MessageBusMessage) => void) | null = null;
  private authStateListener: (() => void) | null = null;
  private topicChannelAttached: boolean = false;
  private pendingTopicCreatedPostIds: number[] = [];
  private realtimeFetchQueue: number[] = [];
  private realtimeFetchInFlight: boolean = false;
  private realtimeRequestId: number = 0;

  aboutToAppear(): void {
    this.didScrollToInitial = false;
    this.targetPostNumber = this.initialPostNumber;
    this.startTimeTick();
    this.attachAuthStateListener();
    this.initAuthState();
    this.attachTopicChannel();

    // 分享图主题：读取上次选择（失败则回退 0=经典）
    PreferencesUtil.ensureInit()
      .then(() => PreferencesUtil.getNumber(PREF_KEY_SHARE_IMAGE_THEME, 0))
      .then((v: number) => {
        let idx: number = Math.round(v);
        if (idx < 0) idx = 0;
        if (idx >= SHARE_IMAGE_THEME_NAMES.length) idx = 0;
        this.shareImageThemeIndex = idx;
      })
      .catch((_: Object) => {
        this.shareImageThemeIndex = 0;
      });

    this.loadTopicDetail();
  }

  aboutToDisappear(): void {
    this.stopTimeTick();
    this.closeShareImageSheet();
    this.closeExportSheet();
    this.clearHighlightTimer();
    this.detachTopicChannel();
    this.detachAuthStateListener();
  }

  private attachAuthStateListener(): void {
    if (this.authStateListener !== null) {
      return;
    }
    this.authStateListener = () => {
      this.initAuthState().catch((err: Object) => {
        hilog.error(0x0000, TAG, 'Auth state listener failed: %{public}s', JSON.stringify(err));
      });
    };
    AuthService.getInstance().addListener(this.authStateListener);
  }

  private detachAuthStateListener(): void {
    if (this.authStateListener === null) {
      return;
    }
    AuthService.getInstance().removeListener(this.authStateListener);
    this.authStateListener = null;
  }

  @Monitor('isShareImageSheetVisible')
  onShareImageSheetVisibleChange(): void {
    if (!this.isShareImageSheetVisible) {
      this.shareImageRequestId = this.shareImageRequestId + 1;
      this.shareImageLoading = false;
      this.shareImageErrorMessage = '';
      this.shareImagePixelMap = null;
      this.shareImagePngBuffer = null;
      this.shareImageTargetPostNumber = 0;
      this.cleanupShareImageFile();
    }
  }

  @Monitor('shareImageCardId')
  onShareImageCardIdChange(): void {
    // 主题切换/重试会修改 cardId，但离屏节点 onAppear 不一定会再次触发；
    // 用 Monitor 确保每次 cardId 变化都必定调度一次 snapshot。
    this.maybeScheduleShareImageSnapshot(this.shareImageCardId);
  }

  private maybeScheduleShareImageSnapshot(cardId: string): void {
    if (!this.isShareImageSheetVisible) return;
    if (!this.shareImageLoading) return;
    if (cardId !== this.shareImageCardId) return;

    const requestId: number = this.shareImageRequestId;
    if (requestId === this.shareImageLastScheduledRequestId) return;
    this.shareImageLastScheduledRequestId = requestId;

    setTimeout(() => {
      this.generateShareImage(requestId, cardId);
    }, SHARE_IMAGE_SNAPSHOT_DELAY_MS);
  }

  private startTimeTick(): void {
    this.timeTick = Date.now();
    if (this.timeTickTimerId >= 0) {
      clearInterval(this.timeTickTimerId);
      this.timeTickTimerId = -1;
    }
    this.timeTickTimerId = setInterval(() => {
      this.timeTick = Date.now();
    }, 30000);
  }

  private stopTimeTick(): void {
    if (this.timeTickTimerId >= 0) {
      clearInterval(this.timeTickTimerId);
      this.timeTickTimerId = -1;
    }
  }

  private async initAuthState(): Promise<void> {
    const auth: AuthService = AuthService.getInstance();
    try {
      await auth.init();
      const loggedIn: boolean = auth.getIsLoggedIn();
      this.isGuestMode = !loggedIn;
    } catch (_) {
      this.isGuestMode = true;
    }
  }

  private attachTopicChannel(): void {
    if (this.topicChannelAttached) return;
    if (this.topicId <= 0) return;

    const bus: MessageBusService = MessageBusService.getInstance();
    this.topicChannelKey = `/topic/${this.topicId}`;
    this.reactionsChannelKey = `/topic/${this.topicId}/reactions`;

    const cb = (message: MessageBusMessage) => {
      this.handleTopicChannelMessage(message);
    };
    this.topicChannelCallback = cb;
    bus.subscribeWithMessageId(this.topicChannelKey, cb, -1);

    const rcb = (message: MessageBusMessage) => {
      this.handleTopicReactionsMessage(message);
    };
    this.reactionsChannelCallback = rcb;
    bus.subscribeWithMessageId(this.reactionsChannelKey, rcb, -1);

    this.topicChannelAttached = true;
  }

  private detachTopicChannel(): void {
    if (!this.topicChannelAttached) return;
    this.realtimeRequestId = this.realtimeRequestId + 1;
    this.realtimeFetchQueue = [];
    this.pendingTopicCreatedPostIds = [];
    this.realtimeFetchInFlight = false;

    try {
      const bus: MessageBusService = MessageBusService.getInstance();
      if (this.topicChannelKey.length > 0 && this.topicChannelCallback !== null) {
        bus.unsubscribe(this.topicChannelKey, this.topicChannelCallback);
      }
      if (this.reactionsChannelKey.length > 0 && this.reactionsChannelCallback !== null) {
        bus.unsubscribe(this.reactionsChannelKey, this.reactionsChannelCallback);
      }
    } catch (_) {
    }

    this.topicChannelKey = '';
    this.reactionsChannelKey = '';
    this.topicChannelCallback = null;
    this.reactionsChannelCallback = null;
    this.topicChannelAttached = false;
  }

  private handleTopicReactionsMessage(message: MessageBusMessage): void {
    // 最小策略：暂不处理 reactions（后续若需要可做单帖刷新）
    if (message === null || message === undefined) return;
  }

  private handleTopicChannelMessage(message: MessageBusMessage): void {
    if (message === null || message === undefined) return;

    // 过滤模式/搜索模式：不做实时追加（对齐安卓策略）
    if (this.isSummaryMode || this.isAuthorOnlyMode || this.isSearchMode) return;

    const dataObj: Object | null = message.data;
    if (dataObj === null || dataObj === undefined || typeof dataObj !== 'object') return;
    const data: Record<string, Object> = dataObj as Record<string, Object>;

    const typeVal: Object | undefined = data['type'];
    const type: string = typeVal !== undefined && typeVal !== null ? typeVal.toString() : '';
    if (type.length === 0) return;

    if (type === 'created') {
      const idVal: Object | undefined = data['id'];
      const postId: number = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;
      if (postId <= 0 || isNaN(postId)) return;
      this.handleTopicCreatedPost(postId);
      return;
    }

    // stats：兜底更新 postsCount（若站点推送）
    if (type === 'stats') {
      const postsCountVal: Object | undefined = data['posts_count'];
      const count: number = postsCountVal !== undefined && postsCountVal !== null ? Number(postsCountVal.toString()) : 0;
      if (count > 0 && count !== this.postsCount) {
        this.postsCount = count;
        this.topicTotalPostsCount = count;
        this.replyCount = Math.max(0, count - 1);
      }
    }
  }

  private isUserAtListBottom(): boolean {
    const total: number = 1
      + (this.shouldShowLoadPreviousEntry() ? 1 : 0)
      + this.posts.length
      + ((this.hasMoreAfter || this.isLoadingMore || this.isLoadMoreFailed) ? 1 : 0);
    if (total <= 0) return false;
    return this.lastVisibleEndIndex >= total - 1;
  }

  private streamContainsPostId(postId: number): boolean {
    for (let i = 0; i < this.streamIds.length; i++) {
      if (this.streamIds[i] === postId) return true;
    }
    return false;
  }

  private addPostIdToStreamEnd(postId: number): void {
    if (postId <= 0) return;
    if (this.streamContainsPostId(postId)) return;

    const next: number[] = [];
    for (let i = 0; i < this.streamIds.length; i++) {
      next.push(this.streamIds[i]);
    }
    next.push(postId);

    const newMap: Map<number, number> = new Map();
    for (let i = 0; i < next.length; i++) {
      newMap.set(next[i], i);
    }
    this.streamIds = next;
    this.streamIndexMap = newMap;

    const total: number = next.length;
    this.postsCount = total;
    this.topicTotalPostsCount = total;
    this.replyCount = Math.max(0, total - 1);
    this.updateBoundaryState();
  }

  private handleTopicCreatedPost(postId: number): void {
    if (postId <= 0) return;

    // 还未初始化 stream：先挂起，等 loadTopicDetail 完成后再补齐
    if (this.isLoading || this.streamIds.length === 0) {
      if (!this.pendingTopicCreatedPostIds.includes(postId)) {
        this.pendingTopicCreatedPostIds.push(postId);
      }
      return;
    }

    if (this.streamContainsPostId(postId)) return;

    const wasLoadedToEnd: boolean = !this.hasMoreAfter;
    const wasAtBottom: boolean = this.isUserAtListBottom();

    this.addPostIdToStreamEnd(postId);

    // 若已加载到末尾且用户在底部：立即拉取正文并追加（对齐安卓）
    if (wasLoadedToEnd && wasAtBottom) {
      this.enqueueRealtimeFetch(postId);
    }
  }

  private applyPendingTopicCreatedPostIds(): void {
    if (this.pendingTopicCreatedPostIds.length === 0) return;
    if (this.isSummaryMode || this.isAuthorOnlyMode || this.isSearchMode) {
      this.pendingTopicCreatedPostIds = [];
      return;
    }
    if (this.streamIds.length === 0) return;

    const ids: number[] = this.pendingTopicCreatedPostIds;
    this.pendingTopicCreatedPostIds = [];
    for (let i = 0; i < ids.length; i++) {
      this.addPostIdToStreamEnd(ids[i]);
    }
  }

  private enqueueRealtimeFetch(postId: number): void {
    if (postId <= 0) return;
    if (this.realtimeFetchQueue.includes(postId)) return;
    this.realtimeFetchQueue.push(postId);
    if (!this.realtimeFetchInFlight) {
      const requestId: number = this.realtimeRequestId;
      this.flushRealtimeFetchQueue(requestId).catch((_: Object) => {
      });
    }
  }

  private async flushRealtimeFetchQueue(requestId: number): Promise<void> {
    if (this.realtimeFetchInFlight) return;
    if (this.realtimeFetchQueue.length === 0) return;
    this.realtimeFetchInFlight = true;
    try {
      while (this.realtimeFetchQueue.length > 0) {
        if (requestId !== this.realtimeRequestId) return;

        const ids: number[] = [];
        while (this.realtimeFetchQueue.length > 0 && ids.length < POSTS_PAGE_CHUNK) {
          const id: number = this.realtimeFetchQueue.shift() as number;
          if (id > 0) ids.push(id);
        }
        if (ids.length === 0) continue;

        const apiClient: ApiClient = ApiClient.getInstance();
        const posts: Post[] = await apiClient.getTopicPosts(this.topicId, ids);
        if (requestId !== this.realtimeRequestId) return;
        if (posts.length > 0) {
          this.mergePostsByStream(posts, true);

          // 保持底部：追加后滚动到最后一项（仅当用户此前在底部）
          setTimeout(() => {
            try {
              const lastPostIndex: number = this.posts.length > 0 ? (this.posts.length - 1) : 0;
              const listIndex: number = this.getListIndexForPostArrayIndex(lastPostIndex);
              this.listScroller.scrollToIndex(listIndex, true, ScrollAlign.END);
            } catch (_) {
            }
          }, 30);
        }
      }
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Realtime fetch failed: %{public}s', JSON.stringify(err));
    } finally {
      this.realtimeFetchInFlight = false;
    }
  }

  /**
   * 加载话题详情
   */
  async loadTopicDetail(): Promise<void> {
    if (this.topicId <= 0) {
      this.errorMessage = '无效的话题ID';
      this.isLoading = false;
      return;
    }

    const requestedPostNumber: number = this.targetPostNumber > 0 ? this.targetPostNumber : 0;
    const requestedFilter: string = this.isSummaryMode ? 'summary' : '';
    const requestedUsernameFilters: string = (this.isAuthorOnlyMode && this.topicOwnerUsername.trim().length > 0)
      ? this.topicOwnerUsername.trim()
      : '';

    this.isLoading = true;
    this.errorMessage = '';
    this.isLoadMoreFailed = false;
    this.isLoadPreviousFailed = false;
    this.isLoadingMore = false;
    this.isLoadingPrevious = false;

    // 重置话题 meta（避免上一条残留）
    this.topicTitle = '';
    this.topicViews = 0;
    this.topicTags = [];
    this.topicCreatedAt = null;
    this.topicLastPostedAt = null;
    this.topicTotalPostsCount = 0;
    this.topicCategoryId = 0;
    this.topicCategory = null;
    this.topicOwnerUsername = '';
    this.streamIds = [];
    this.streamIndexMap = new Map();
    this.hasSummary = false;
    this.notificationLevel = 1;
    this.notificationLevelLabel = '常规';
    this.isClosed = false;
    this.hasAcceptedAnswer = false;
    this.acceptedAnswerPostNumber = 0;
    this.isBookmarked = false;

    this.replyCount = 0;
    this.postsCount = 0;
    this.currentPostIndex = requestedPostNumber > 0 ? requestedPostNumber : 1;
    this.scrollOffset = 0;
    this.showTitle = false;
    this.showBottomBar = false;
    this.bottomBarVisibility = 0;
    this._bottomBarDelta = 0;
    this.expandedRepliesPostNumber = 0;
    this.expandedRepliesLoading = false;
    this.expandedRepliesErrorMessage = '';
    this.expandedReplies = [];
    this.didScrollToInitial = false;
    this.hasMoreBefore = false;
    this.hasMoreAfter = false;

    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const result: string = await apiClient.getTopicDetail(
        this.topicId,
        requestedPostNumber,
        requestedFilter,
        requestedUsernameFilters
      );
      const json: Record<string, Object> = JSON.parse(result) as Record<string, Object>;

      // 解析标题
      const titleVal = json['title'];
      this.topicTitle = titleVal !== undefined && titleVal !== null ? titleVal as string : '';

      // slug（用于分享链接，对齐安卓）
      const slugVal = json['slug'];
      this.topicSlug = slugVal !== undefined && slugVal !== null ? slugVal.toString() : '';

      // 计数字段：最终以 stream 为真值；此处先读取 meta（兜底用）
      let metaPostsCount: number = 0;
      const postsCountVal = json['posts_count'];
      if (postsCountVal !== undefined && postsCountVal !== null) {
        metaPostsCount = Number(postsCountVal.toString());
      }
      let highestPostNumber: number = 0;
      const highestVal = json['highest_post_number'];
      if (highestVal !== undefined && highestVal !== null) {
        highestPostNumber = Number(highestVal.toString());
      }
      this.topicTotalPostsCount = metaPostsCount;
      this.replyCount = 0;
      this.postsCount = 0;

      const viewsVal = json['views'];
      this.topicViews = viewsVal !== undefined && viewsVal !== null ? viewsVal as number : 0;

      const createdVal = json['created_at'];
      this.topicCreatedAt = createdVal !== undefined && createdVal !== null
        ? TimeUtils.parseUtcTime(createdVal as string) : null;

      const lastPostedVal = json['last_posted_at'];
      this.topicLastPostedAt = lastPostedVal !== undefined && lastPostedVal !== null
        ? TimeUtils.parseUtcTime(lastPostedVal as string) : null;

      const tagsVal = json['tags'];
      const parsedTags: string[] = [];
      if (tagsVal !== undefined && tagsVal !== null) {
        const arr: (Object | string)[] = tagsVal as (Object | string)[];
        for (let i = 0; i < arr.length; i++) {
          const item: Object | string = arr[i];
          let name: string = '';
          if (typeof item === 'string') {
            name = (item as string).trim();
          } else {
            const obj: Record<string, Object> = item as Record<string, Object>;
            const nameVal = obj['name'];
            if (nameVal !== undefined && nameVal !== null) {
              name = nameVal.toString().trim();
            } else {
              name = item.toString().trim();
            }
          }
          if (name.length > 0) {
            parsedTags.push(name);
          }
        }
      }
      this.topicTags = parsedTags;

      const catVal = json['category_id'];
      this.topicCategoryId = catVal !== undefined && catVal !== null ? catVal as number : 0;
      await this.loadTopicCategory();

      const closedVal = json['closed'];
      this.isClosed = closedVal !== undefined && closedVal !== null ? closedVal as boolean : false;

      const bookVal = json['bookmarked'];
      this.isBookmarked = bookVal !== undefined && bookVal !== null ? bookVal as boolean : false;

      const hasSummaryVal = json['has_summary'];
      this.hasSummary = hasSummaryVal !== undefined && hasSummaryVal !== null ? hasSummaryVal as boolean : false;

      const nlVal = json['notification_level'];
      this.notificationLevel = nlVal !== undefined && nlVal !== null ? nlVal as number : 1;
      this.notificationLevelLabel = this.getNotificationLevelLabel(this.notificationLevel);

      // 题主（优先 details.created_by.username，避免跳楼到中间拿不到首贴）
      const detailsVal = json['details'];
      if (detailsVal !== undefined && detailsVal !== null) {
        const detailsObj: Record<string, Object> = detailsVal as Record<string, Object>;
        const createdByVal = detailsObj['created_by'];
        if (createdByVal !== undefined && createdByVal !== null) {
          const createdByObj: Record<string, Object> = createdByVal as Record<string, Object>;
          const ownerVal = createdByObj['username'];
          if (ownerVal !== undefined && ownerVal !== null) {
            this.topicOwnerUsername = ownerVal as string;
          }
        }
      }

      // 解析帖子流（stream + posts）
      const parsedStream: number[] = [];
      const parsedPosts: Post[] = [];
      const postStreamVal = json['post_stream'];
      if (postStreamVal !== undefined && postStreamVal !== null) {
        const postStream = postStreamVal as Record<string, Object>;

        const streamVal = postStream['stream'];
        if (streamVal !== undefined && streamVal !== null) {
          const streamArr: Object[] = streamVal as Object[];
          for (let i = 0; i < streamArr.length; i++) {
            const item: Object = streamArr[i];
            if (typeof item === 'number') {
              parsedStream.push(item as number);
            }
          }
        }

        const postsVal = postStream['posts'];
        if (postsVal !== undefined && postsVal !== null) {
          const postsArray = postsVal as Object[];
          for (let i = 0; i < postsArray.length; i++) {
            const postJson = postsArray[i] as Record<string, Object>;
            parsedPosts.push(Post.fromJson(postJson));
          }
        }
      }

      this.streamIds = parsedStream;
      const newMap: Map<number, number> = new Map();
      for (let i = 0; i < parsedStream.length; i++) {
        newMap.set(parsedStream[i], i);
      }
      this.streamIndexMap = newMap;

      // 按 stream 顺序排序，保证分页合并后顺序稳定
      parsedPosts.sort((a: Post, b: Post): number => {
        const ia: number = newMap.has(a.id) ? (newMap.get(a.id) as number) : a.postNumber;
        const ib: number = newMap.has(b.id) ? (newMap.get(b.id) as number) : b.postNumber;
        return ia - ib;
      });

      this.acceptedAnswerPostNumber = this.resolveAcceptedAnswerPostNumber(json, parsedPosts);
      this.hasAcceptedAnswer = this.resolveHasAcceptedAnswer(json, parsedPosts, this.acceptedAnswerPostNumber);
      this.posts = parsedPosts;
      this.updateTopicOwnerUsername();

      // 总数真值对齐安卓：优先 stream；兜底 highest_post_number / posts_count / 已加载 posts
      let effectivePostsCount: number = 0;
      if (this.streamIds.length > 0) {
        effectivePostsCount = this.streamIds.length;
      } else if (highestPostNumber > 0) {
        effectivePostsCount = highestPostNumber;
      } else if (metaPostsCount > 0) {
        effectivePostsCount = metaPostsCount;
      } else {
        effectivePostsCount = this.posts.length;
      }
      this.topicTotalPostsCount = effectivePostsCount;
      this.postsCount = effectivePostsCount;
      this.replyCount = Math.max(0, effectivePostsCount - 1);

      this.updateBoundaryState();
      this.applyPendingTopicCreatedPostIds();

      hilog.info(0x0000, TAG, 'Loaded topic %{public}d with %{public}d posts',
        this.topicId, this.posts.length);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load topic detail failed: %{public}s', JSON.stringify(err));
      this.errorMessage = '加载话题详情失败';
    } finally {
      this.isLoading = false;
      if (this.errorMessage.length === 0) {
        this.scrollToInitialPostIfNeeded();
      }
    }
  }

  private refreshTopicDetail(): void {
    if (this.isLoading) return;
    this.targetPostNumber = 0;
    this.loadTopicDetail();
  }

  private resolveAcceptedAnswerPostNumber(topicJson: Record<string, Object>, parsedPosts: Post[]): number {
    const acceptedAnswerVal = topicJson['accepted_answer'];
    if (acceptedAnswerVal !== undefined && acceptedAnswerVal !== null && typeof acceptedAnswerVal === 'object') {
      const acceptedAnswerObj: Record<string, Object> = acceptedAnswerVal as Record<string, Object>;
      const postNumberVal = acceptedAnswerObj['post_number'];
      if (postNumberVal !== undefined && postNumberVal !== null) {
        const parsed: number = Number(postNumberVal.toString());
        if (!isNaN(parsed) && parsed > 0) {
          return parsed;
        }
      }
    }

    if (!this.hasAcceptedAnswer) {
      return 0;
    }

    for (let i = 0; i < parsedPosts.length; i++) {
      const post: Post = parsedPosts[i];
      if (post.acceptedAnswer && post.postNumber > 0) {
        return post.postNumber;
      }
    }

    return 0;
  }

  private resolveHasAcceptedAnswer(topicJson: Record<string, Object>, parsedPosts: Post[], acceptedPostNumber: number): boolean {
    if (acceptedPostNumber > 0) {
      return true;
    }

    const acceptedAnswerVal = topicJson['accepted_answer'];
    if (acceptedAnswerVal !== undefined && acceptedAnswerVal !== null && typeof acceptedAnswerVal === 'object') {
      return true;
    }

    const hasAcceptedVal = topicJson['has_accepted_answer'];
    if (hasAcceptedVal !== undefined && hasAcceptedVal !== null) {
      if (typeof hasAcceptedVal === 'boolean') {
        return hasAcceptedVal as boolean;
      }
      const text: string = hasAcceptedVal.toString().trim().toLowerCase();
      if (text === 'true' || text === '1') {
        return true;
      }
      if (text === 'false' || text === '0') {
        return false;
      }
    }

    for (let i = 0; i < parsedPosts.length; i++) {
      if (parsedPosts[i].acceptedAnswer) {
        return true;
      }
    }

    return false;
  }

  private clearHighlightTimer(): void {
    if (this.highlightTimerId >= 0) {
      clearTimeout(this.highlightTimerId);
      this.highlightTimerId = -1;
    }
  }

  private normalizeQuoteMarkdown(text: string): string {
    let result: string = text !== undefined && text !== null ? text : '';
    result = result.replace(/\r/g, '');
    result = result.replace(/\u00A0/g, ' ');
    result = result.replace(/[ \t]+\n/g, '\n');
    result = result.replace(/\n[ \t]+/g, '\n');
    result = result.replace(/\n{3,}/g, '\n\n');
    return result.trim();
  }

  private buildDiscourseQuote(markdown: string, username: string, postNumber: number): string {
    const content: string = this.normalizeQuoteMarkdown(markdown);
    const safeUsername: string = username !== undefined && username !== null ? username.trim() : '';
    if (content.length === 0 || safeUsername.length === 0 || postNumber <= 0 || this.topicId <= 0) {
      return '';
    }
    return `[quote="${safeUsername}, post:${postNumber}, topic:${this.topicId}"]\n${content}\n[/quote]\n\n`;
  }

  private copyQuoteText(quote: string, successMessage: string = '已复制引用'): void {
    const text: string = quote !== undefined && quote !== null ? quote.trim() : '';
    if (text.length === 0) {
      ToastService.show('没有可引用的内容');
      return;
    }
    ClipboardService.copyText(text, false).then((ok: boolean) => {
      if (ok) {
        ToastService.show(successMessage);
      }
    });
  }

  private buildPostPlainMarkdown(post: Post): string {
    const structuredMarkdown: string = this.normalizeQuoteMarkdown(HtmlToMarkdown.convert(post.cooked));
    if (structuredMarkdown.length > 0) {
      return structuredMarkdown;
    }
    let markdown: string = this.stripHtml(post.cooked);
    markdown = markdown.replace(/\n{3,}/g, '\n\n');
    return this.normalizeQuoteMarkdown(markdown);
  }

  private formatWrappedAttrs(rawAttrs: string): string {
    const attrs: string = rawAttrs !== undefined && rawAttrs !== null ? rawAttrs.trim() : '';
    return attrs.length > 0 ? ` ${attrs}` : '';
  }

  private applySelectionHtmlContext(sourceHtml: string, htmlFragment: string): string {
    const source: string = sourceHtml !== undefined && sourceHtml !== null ? sourceHtml.trim() : '';
    const fragment: string = htmlFragment !== undefined && htmlFragment !== null ? htmlFragment.trim() : '';
    if (source.length === 0 || fragment.length === 0) {
      return fragment;
    }

    let match: RegExpMatchArray | null = source.match(/^<(h[1-6])\b([^>]*)>[\s\S]*<\/\1>$/i);
    if (match !== null) {
      return `<${match[1]}${this.formatWrappedAttrs(match[2])}>${fragment}</${match[1]}>`;
    }

    match = source.match(/^<blockquote\b([^>]*)>[\s\S]*<\/blockquote>$/i);
    if (match !== null) {
      return `<blockquote${this.formatWrappedAttrs(match[1])}>${fragment}</blockquote>`;
    }

    match = source.match(/^<details\b([^>]*)>[\s\S]*<\/details>$/i);
    if (match !== null) {
      const summaryMatch: RegExpMatchArray | null = source.match(/<summary\b[^>]*>[\s\S]*?<\/summary>/i);
      const summaryHtml: string = summaryMatch !== null ? summaryMatch[0] : '<summary>详情</summary>';
      return `<details${this.formatWrappedAttrs(match[1])}>${summaryHtml}${fragment}</details>`;
    }

    match = source.match(/^<(ol|ul)\b([^>]*)>\s*<li\b[^>]*>[\s\S]*<\/li>\s*<\/\1>$/i);
    if (match !== null) {
      return `<${match[1]}${this.formatWrappedAttrs(match[2])}><li>${fragment}</li></${match[1]}>`;
    }

    match = source.match(/^<table\b([^>]*)>\s*<tr\b([^>]*)>\s*<(td|th)\b([^>]*)>[\s\S]*<\/\3>\s*<\/tr>\s*<\/table>$/i);
    if (match !== null) {
      return `<table${this.formatWrappedAttrs(match[1])}><tr${this.formatWrappedAttrs(match[2])}><${match[3]}${this.formatWrappedAttrs(match[4])}>${fragment}</${match[3]}></tr></table>`;
    }

    match = source.match(/^<(div|span)\b([^>]*)>[\s\S]*<\/\1>$/i);
    if (match !== null) {
      const attrs: string = match[2] !== undefined && match[2] !== null ? match[2] : '';
      if (/class\s*=\s*['"][^'"]*spoiler[^'"]*['"]/i.test(attrs) || /class\s*=\s*['"][^'"]*math[^'"]*['"]/i.test(attrs)) {
        return `<${match[1]}${this.formatWrappedAttrs(attrs)}>${fragment}</${match[1]}>`;
      }
    }

    return fragment;
  }

  private buildSelectionMarkdown(selectedText: string, sourceHtml: string): string {
    const plainSelectedText: string = selectedText !== undefined && selectedText !== null ? selectedText.trim() : '';
    const htmlSource: string = sourceHtml !== undefined && sourceHtml !== null ? sourceHtml : '';
    if (plainSelectedText.length === 0) {
      return '';
    }

    if (htmlSource.length > 0) {
      const htmlFragment: string | null = HtmlTextMapper.extractHtml(htmlSource, plainSelectedText);
      if (htmlFragment !== null) {
        const contextualHtml: string = this.applySelectionHtmlContext(htmlSource, htmlFragment);
        const markdown: string = this.normalizeQuoteMarkdown(HtmlToMarkdown.convert(contextualHtml));
        if (markdown.length > 0) {
          return markdown;
        }
      }

      const fallbackMarkdown: string = this.normalizeQuoteMarkdown(HtmlToMarkdown.convert(htmlSource));
      const plainSourceText: string = this.normalizeQuoteMarkdown(this.stripHtml(htmlSource));
      if (fallbackMarkdown.length > 0 && plainSourceText === plainSelectedText) {
        return fallbackMarkdown;
      }
    }

    return this.normalizeQuoteMarkdown(plainSelectedText);
  }

  private buildPostQuote(post: Post, markdown: string): string {
    return this.buildDiscourseQuote(markdown, post.username, post.postNumber);
  }

  private buildPostQuoteFromSelection(post: Post, selectedText: string, sourceHtml: string): string {
    const markdown: string = this.buildSelectionMarkdown(selectedText, sourceHtml);
    return this.buildPostQuote(post, markdown);
  }

  private openReplySheet(replyToPost: Post | null = null, initialContent: string = ''): void {
    if (this.isGuestMode) {
      ToastService.show('请先登录');
      return;
    }

    this.replySheetTargetPostNumber = replyToPost !== null ? replyToPost.postNumber : 0;
    this.replySheetTargetUsername = replyToPost !== null ? replyToPost.username : '';
    this.replySheetTargetAvatarTemplate = replyToPost !== null ? replyToPost.avatarTemplate : '';
    this.replySheetInitialContent = initialContent;
    this.replySheetRequestKey = `reply_${Date.now()}_${this.replySheetTargetPostNumber}`;
    this.isReplySheetVisible = true;
  }

  private handleReplySubmitted(post: Post): void {
    if (post.id <= 0) {
      return;
    }

    if (this.isSummaryMode || this.isAuthorOnlyMode || this.isSearchMode) {
      ToastService.show('回复已发送，退出当前筛选后可查看');
      this.pendingReplyScrollPostNumber = 0;
      return;
    }

    this.addPostIdToStreamEnd(post.id);
    this.mergePostsByStream([post], true);
    this.pendingReplyScrollPostNumber = post.postNumber > 0 ? post.postNumber : 0;
    if (this.pendingReplyScrollPostNumber > 0) {
      this.currentPostIndex = this.pendingReplyScrollPostNumber;
    }
  }

  private handleReplySheetDismiss(submitted: boolean): void {
    this.isReplySheetVisible = false;
    this.replySheetTargetPostNumber = 0;
    this.replySheetTargetUsername = '';
    this.replySheetTargetAvatarTemplate = '';
    this.replySheetInitialContent = '';
    this.replySheetRequestKey = '';

    if (!submitted) {
      this.pendingReplyScrollPostNumber = 0;
      return;
    }

    const targetPostNumber: number = this.pendingReplyScrollPostNumber;
    this.pendingReplyScrollPostNumber = 0;
    if (targetPostNumber <= 0) {
      return;
    }
    setTimeout(() => {
      this.jumpToPostNumber(targetPostNumber);
    }, 260);
  }

  private copySelectionQuote(post: Post, selectedText: string, sourceHtml: string): void {
    const quote: string = this.buildPostQuoteFromSelection(post, selectedText, sourceHtml);
    this.copyQuoteText(quote);
  }

  private replacePostInstance(updatedPost: Post): void {
    if (updatedPost.id <= 0) {
      return;
    }

    let changed: boolean = false;
    const posts: Post[] = [];
    for (let i = 0; i < this.posts.length; i++) {
      const current: Post = this.posts[i];
      if (current.id === updatedPost.id) {
        posts.push(updatedPost);
        changed = true;
      } else {
        posts.push(current);
      }
    }
    if (changed) {
      this.posts = posts;
    }

    if (this.expandedReplies.length > 0) {
      let replyChanged: boolean = false;
      const replies: Post[] = [];
      for (let i = 0; i < this.expandedReplies.length; i++) {
        const current: Post = this.expandedReplies[i];
        if (current.id === updatedPost.id) {
          replies.push(updatedPost);
          replyChanged = true;
        } else {
          replies.push(current);
        }
      }
      if (replyChanged) {
        this.expandedReplies = replies;
      }
    }
  }

  private openPostQuoteReply(post: Post): void {
    const quote: string = this.buildPostQuote(post, this.buildPostPlainMarkdown(post));
    if (quote.length === 0) {
      ToastService.show('没有可引用的内容');
      return;
    }
    this.openReplySheet(post, quote);
  }

  private copyPostQuote(post: Post): void {
    const quote: string = this.buildPostQuote(post, this.buildPostPlainMarkdown(post));
    this.copyQuoteText(quote);
  }

  private openImageContextSheet(post: Post, imageUrl: string, previewUrl: string): void {
    this.imageContextThumbUrl = imageUrl;
    this.imageContextPreviewUrl = previewUrl;
    this.imageContextPostNumber = post.postNumber;
    this.imageContextUsername = post.username;
    this.imageContextAvatarTemplate = post.avatarTemplate;
    this.isImageContextSheetVisible = true;
  }

  private openImageQuoteReply(): void {
    const imageUrl: string = this.imageContextPreviewUrl.length > 0 ? this.imageContextPreviewUrl : this.imageContextThumbUrl;
    if (imageUrl.length === 0) {
      ToastService.show('图片地址为空');
      return;
    }

    const quote: string = this.buildDiscourseQuote(
      `![image](${imageUrl})`,
      this.imageContextUsername,
      this.imageContextPostNumber
    );
    if (quote.length === 0) {
      ToastService.show('无法生成图片引用');
      return;
    }

    const replyToPost: Post = new Post();
    replyToPost.postNumber = this.imageContextPostNumber;
    replyToPost.username = this.imageContextUsername;
    replyToPost.avatarTemplate = this.imageContextAvatarTemplate;
    this.openReplySheet(replyToPost, quote);
  }

  private armPendingHighlight(postNumber: number): void {
    const target: number = postNumber > 0 ? postNumber : 0;
    this.pendingHighlightPostNumber = target;
    this.pendingHighlightListIndex = this.getListIndexForPostNumberIfLoaded(target);
    this.maybeTriggerPendingHighlight(this.lastVisibleStartIndex, this.lastVisibleEndIndex);
  }

  private getListIndexForPostNumberIfLoaded(postNumber: number): number {
    if (postNumber <= 0) return -1;
    const idx: number = this.findPostIndexByPostNumber(postNumber);
    if (idx < 0) return -1;
    return this.getListIndexForPostArrayIndex(idx);
  }

  private maybeTriggerPendingHighlight(startIndex: number, endIndex: number): void {
    const target: number = this.pendingHighlightPostNumber;
    if (target <= 0) return;

    let listIndex: number = this.pendingHighlightListIndex;
    if (listIndex < 0) {
      listIndex = this.getListIndexForPostNumberIfLoaded(target);
      this.pendingHighlightListIndex = listIndex;
    }
    if (listIndex < 0) return;

    if (listIndex >= startIndex && listIndex <= endIndex) {
      this.pendingHighlightPostNumber = 0;
      this.pendingHighlightListIndex = -1;
      this.triggerHighlight(target);
    }
  }

  private triggerHighlight(postNumber: number): void {
    const target: number = postNumber > 0 ? postNumber : 0;
    if (target <= 0) return;

    this.clearHighlightTimer();
    this.highlightPostNumber = target;
    this.highlightOpacity = 1;

    const uiContext = this.getUIContext();
    if (uiContext !== undefined && uiContext !== null) {
      uiContext.animateTo({ duration: 2000, curve: Curve.EaseOut }, () => {
        this.highlightOpacity = 0;
      });
    } else {
      this.highlightOpacity = 0;
    }

    this.highlightTimerId = setTimeout(() => {
      this.highlightTimerId = -1;
      this.highlightPostNumber = 0;
      this.highlightOpacity = 0;
    }, 2100);
  }

  private scrollToInitialPostIfNeeded(): void {
    if (this.didScrollToInitial) return;
    if (this.targetPostNumber <= 1) return;
    if (this.posts.length === 0) return;

    let targetPostIndex: number = -1;
    for (let i = 0; i < this.posts.length; i++) {
      const p: Post = this.posts[i];
      if (p.postNumber === this.targetPostNumber) {
        targetPostIndex = i;
        break;
      }
    }
    if (targetPostIndex < 0) return;

    this.didScrollToInitial = true;
    this.armPendingHighlight(this.targetPostNumber);
    const listIndex: number = this.getListIndexForPostArrayIndex(targetPostIndex);
    setTimeout(() => {
      try {
        this.listScroller.scrollToIndex(listIndex, true, ScrollAlign.START);
      } catch (_) {
      }
    }, 80);
  }

  private async loadTopicCategory(): Promise<void> {
    if (this.topicCategoryId <= 0) {
      this.topicCategory = null;
      return;
    }
    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const siteResponse: SiteResponse = await apiClient.getSiteInfo();
      const list: Category[] = siteResponse.categories;
      for (let i = 0; i < list.length; i++) {
        const c: Category = list[i];
        if (c.id === this.topicCategoryId) {
          this.topicCategory = c;
          return;
        }
      }
      this.topicCategory = null;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load topic category failed: %{public}s', JSON.stringify(err));
      this.topicCategory = null;
    }
  }

  private updateTopicOwnerUsername(): void {
    if (this.topicOwnerUsername.trim().length > 0) {
      return;
    }
    for (let i = 0; i < this.posts.length; i++) {
      const p: Post = this.posts[i];
      if (p.postNumber === 1 && p.username.length > 0 && (p.actionCode === null || p.actionCode.length === 0)) {
        this.topicOwnerUsername = p.username;
        return;
      }
    }
  }

  private normalizeFaIconName(raw: string | null): string {
    if (raw === null) return '';
    const s: string = raw.trim().toLowerCase();
    if (s.length === 0) return '';

    const tokens: string[] = s.split(/\s+/);
    let last: string = '';
    for (let i = 0; i < tokens.length; i++) {
      let t: string = tokens[i].trim();
      if (t.length === 0) continue;
      if (
        t === 'fa-solid' || t === 'fa-regular' || t === 'fa-brands' || t === 'fa-light' || t === 'fa-thin' || t === 'fa-duotone'
        || t === 'fas' || t === 'far' || t === 'fab' || t === 'fal' || t === 'fat' || t === 'fad'
        || t === 'fa'
      ) {
        continue;
      }
      if (t.startsWith('fa-')) t = t.substring(3);
      if (t.startsWith('fas-')) t = t.substring(4);
      if (t.startsWith('far-')) t = t.substring(4);
      if (t.startsWith('fab-')) t = t.substring(4);
      last = t;
    }
    return last;
  }

  private getGrantedBadgeSymbol(icon: string | null): Resource | null {
    const name: string = this.normalizeFaIconName(icon);
    if (name.length === 0) return null;

    switch (name) {
      case 'seedling':
      case 'sprout':
      case 'leaf':
        return $r('sys.symbol.leaf');
      case 'award':
      case 'medal':
      case 'trophy':
        return $r('sys.symbol.medal');
      case 'star':
      case 'stars':
        return $r('sys.symbol.star');
      case 'check':
      case 'circle-check':
      case 'check-circle':
        return $r('sys.symbol.checkmark_circle');
      case 'shield':
      case 'shield-halved':
        return $r('sys.symbol.security_shield');
      case 'question':
      case 'circle-question':
        return $r('sys.symbol.questionmark_circle');
      case 'comment':
      case 'comments':
        return $r('sys.symbol.message');
      default:
        return null;
    }
  }

  private getGrantedBadgeTypeColor(typeId: number): Resource {
    if (typeId === 1) return $r('app.color.badge_gold');
    if (typeId === 2) return $r('app.color.badge_silver');
    return $r('app.color.badge_bronze');
  }

  private collapseReplies(): void {
    this.expandedRepliesPostNumber = 0;
    this.expandedRepliesLoading = false;
    this.expandedRepliesErrorMessage = '';
    this.expandedReplies = [];
  }

  private async toggleReplies(post: Post): Promise<void> {
    if (this.expandedRepliesPostNumber === post.postNumber) {
      this.collapseReplies();
      return;
    }

    this.expandedRepliesPostNumber = post.postNumber;
    await this.loadRepliesForPost(post);
  }

  private async loadRepliesForPost(post: Post): Promise<void> {
    this.expandedRepliesLoading = true;
    this.expandedRepliesErrorMessage = '';
    this.expandedReplies = [];

    const targetPostNumber: number = post.postNumber;
    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const replies: Post[] = await apiClient.getPostReplies(post.id, 1);
      if (this.expandedRepliesPostNumber === targetPostNumber) {
        this.expandedReplies = replies;
        this.expandedRepliesErrorMessage = '';
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load post replies failed: %{public}s', JSON.stringify(err));
      if (this.expandedRepliesPostNumber === targetPostNumber) {
        this.expandedRepliesErrorMessage = '加载回复失败';
      }
    } finally {
      if (this.expandedRepliesPostNumber === targetPostNumber) {
        this.expandedRepliesLoading = false;
      }
    }
  }

  private shouldShowLoadPreviousEntry(): boolean {
    return this.hasMoreBefore || this.isLoadingPrevious || this.isLoadPreviousFailed;
  }

  private getPostListStartIndex(): number {
    return 1 + (this.shouldShowLoadPreviousEntry() ? 1 : 0);
  }

  private getListIndexForPostArrayIndex(postIndex: number): number {
    return this.getPostListStartIndex() + postIndex;
  }

  private updateCurrentPostIndexFromScrollIndex(listIndex: number): void {
    if (this.posts.length === 0) {
      if (this.currentPostIndex !== 1) {
        this.currentPostIndex = 1;
      }
      return;
    }

    const postStartIndex: number = this.getPostListStartIndex();
    let postIndex: number = listIndex - postStartIndex;
    if (postIndex < 0) {
      postIndex = 0;
    }
    if (postIndex >= this.posts.length) {
      postIndex = this.posts.length - 1;
    }

    const postId: number = this.posts[postIndex].id;
    let next: number = postIndex + 1;
    if (this.streamIndexMap.has(postId)) {
      const idx: number = this.streamIndexMap.get(postId) as number;
      next = idx + 1;
    } else {
      const postNumber: number = this.posts[postIndex].postNumber;
      next = postNumber > 0 ? postNumber : next;
    }

    if (next !== this.currentPostIndex) {
      this.currentPostIndex = next;
    }
  }

  private getNotificationLevelLabel(level: number): string {
    // Discourse notification_level:
    // 0 muted, 1 regular, 2 tracking, 3 watching, 4 watching_first_post
    if (level <= 0) return '静音';
    if (level === 1) return '常规';
    if (level === 2) return '跟踪';
    if (level === 3) return '关注';
    if (level === 4) return '首帖关注';
    return '常规';
  }

  private getLoadedStreamRange(): number[] {
    let minIndex: number = -1;
    let maxIndex: number = -1;
    for (let i = 0; i < this.posts.length; i++) {
      const id: number = this.posts[i].id;
      if (this.streamIndexMap.has(id)) {
        const idx: number = this.streamIndexMap.get(id) as number;
        if (minIndex < 0 || idx < minIndex) {
          minIndex = idx;
        }
        if (maxIndex < 0 || idx > maxIndex) {
          maxIndex = idx;
        }
      }
    }
    return [minIndex, maxIndex];
  }

  private updateBoundaryState(): void {
    if (this.posts.length === 0 || this.streamIds.length === 0) {
      this.hasMoreBefore = false;
      this.hasMoreAfter = false;
      return;
    }

    const range: number[] = this.getLoadedStreamRange();
    const minIndex: number = range[0];
    const maxIndex: number = range[1];

    if (minIndex < 0 || maxIndex < 0) {
      this.hasMoreBefore = false;
      this.hasMoreAfter = false;
      return;
    }

    this.hasMoreBefore = minIndex > 0;
    this.hasMoreAfter = maxIndex < this.streamIds.length - 1;
  }

  private findPostIndexById(postId: number): number {
    for (let i = 0; i < this.posts.length; i++) {
      if (this.posts[i].id === postId) {
        return i;
      }
    }
    return -1;
  }

  private findPostIndexByPostNumber(postNumber: number): number {
    for (let i = 0; i < this.posts.length; i++) {
      if (this.posts[i].postNumber === postNumber) {
        return i;
      }
    }
    return -1;
  }

  private scrollToPostArrayIndex(postIndex: number): boolean {
    if (postIndex < 0 || postIndex >= this.posts.length) return false;
    const listIndex: number = this.getListIndexForPostArrayIndex(postIndex);
    setTimeout(() => {
      try {
        this.listScroller.scrollToIndex(listIndex, true, ScrollAlign.START);
      } catch (_) {
      }
    }, 30);
    return true;
  }

  private scrollToPostByIdIfLoaded(postId: number): boolean {
    const idx: number = this.findPostIndexById(postId);
    return this.scrollToPostArrayIndex(idx);
  }

  private scrollToPostByPostNumberIfLoaded(postNumber: number): boolean {
    const idx: number = this.findPostIndexByPostNumber(postNumber);
    return this.scrollToPostArrayIndex(idx);
  }

  private mergePostsByStream(incoming: Post[], incrementReplyTargets: boolean = false): void {
    if (incoming.length === 0) {
      return;
    }

    const map: Map<number, Post> = new Map();
    const existingIds: Map<number, boolean> = new Map();
    for (let i = 0; i < this.posts.length; i++) {
      const p: Post = this.posts[i];
      map.set(p.id, p);
      existingIds.set(p.id, true);
    }
    const replyIncrements: Map<number, number> = new Map();
    for (let i = 0; i < incoming.length; i++) {
      const p: Post = incoming[i];
      if (incrementReplyTargets && !existingIds.has(p.id) && p.replyToPostNumber > 0) {
        const current: number = replyIncrements.has(p.replyToPostNumber)
          ? replyIncrements.get(p.replyToPostNumber) as number
          : 0;
        replyIncrements.set(p.replyToPostNumber, current + 1);
      }
      if (!map.has(p.id)) {
        map.set(p.id, p);
      }
    }

    if (replyIncrements.size > 0) {
      for (let i = 0; i < this.posts.length; i++) {
        const p: Post = this.posts[i];
        if (!replyIncrements.has(p.postNumber)) {
          continue;
        }
        const delta: number = replyIncrements.get(p.postNumber) as number;
        if (delta <= 0) {
          continue;
        }
        p.replyCount = p.replyCount + delta;
        map.set(p.id, p);
      }
    }

    const out: Post[] = [];
    if (this.streamIds.length > 0) {
      for (let i = 0; i < this.streamIds.length; i++) {
        const id: number = this.streamIds[i];
        if (map.has(id)) {
          out.push(map.get(id) as Post);
          map.delete(id);
        }
      }
    }

    // 兜底：将未出现在 stream 里的帖子按“先旧后新”追加（正常情况下不会触发）
    if (map.size > 0) {
      for (let i = 0; i < this.posts.length; i++) {
        const p: Post = this.posts[i];
        if (map.has(p.id)) {
          out.push(p);
          map.delete(p.id);
        }
      }
      for (let i = 0; i < incoming.length; i++) {
        const p: Post = incoming[i];
        if (map.has(p.id)) {
          out.push(p);
          map.delete(p.id);
        }
      }
    }

    this.posts = out;
    this.updateTopicOwnerUsername();
    this.updateBoundaryState();
  }

  private async loadMoreAfter(): Promise<void> {
    if (this.isLoadMoreFailed) return; // 失败后需手动点 footer 重试
    if (this.isLoadingMore) return;
    if (!this.hasMoreAfter) return;
    if (this.streamIds.length === 0) return;

    const range: number[] = this.getLoadedStreamRange();
    const maxIndex: number = range[1];
    if (maxIndex < 0) return;

    const start: number = maxIndex + 1;
    const end: number = Math.min(this.streamIds.length, start + POSTS_PAGE_CHUNK);
    const ids: number[] = this.streamIds.slice(start, end);
    if (ids.length === 0) {
      this.hasMoreAfter = false;
      return;
    }

    this.isLoadingMore = true;
    this.isLoadMoreFailed = false;
    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const newPosts: Post[] = await apiClient.getTopicPosts(this.topicId, ids);
      if (newPosts.length === 0) {
        this.hasMoreAfter = false;
      } else {
        this.mergePostsByStream(newPosts);
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load more posts failed: %{public}s', JSON.stringify(err));
      this.isLoadMoreFailed = true;
    } finally {
      this.isLoadingMore = false;
      this.updateBoundaryState();
    }
  }

  private async loadPreviousBefore(): Promise<void> {
    if (this.isLoadPreviousFailed) return; // 失败后需手动点 entry 重试
    if (this.isLoadingPrevious) return;
    if (!this.hasMoreBefore) return;
    if (this.streamIds.length === 0) return;

    const range: number[] = this.getLoadedStreamRange();
    const minIndex: number = range[0];
    if (minIndex <= 0) {
      this.hasMoreBefore = false;
      return;
    }

    const start: number = Math.max(0, minIndex - POSTS_PAGE_CHUNK);
    const ids: number[] = this.streamIds.slice(start, minIndex);
    if (ids.length === 0) {
      this.hasMoreBefore = false;
      return;
    }

    const anchorId: number = this.posts.length > 0 ? this.posts[0].id : 0;

    this.isLoadingPrevious = true;
    this.isLoadPreviousFailed = false;
    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const newPosts: Post[] = await apiClient.getTopicPosts(this.topicId, ids);
      if (newPosts.length === 0) {
        this.hasMoreBefore = false;
      } else {
        this.mergePostsByStream(newPosts);
      }

      if (anchorId > 0) {
        const anchorIndex: number = this.findPostIndexById(anchorId);
        if (anchorIndex >= 0) {
          setTimeout(() => {
            try {
              this.listScroller.scrollToIndex(this.getListIndexForPostArrayIndex(anchorIndex), false, ScrollAlign.START);
            } catch (_) {
            }
          }, 30);
        }
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load previous posts failed: %{public}s', JSON.stringify(err));
      this.isLoadPreviousFailed = true;
    } finally {
      this.isLoadingPrevious = false;
      this.updateBoundaryState();
    }
  }

  private toggleSummaryMode(): void {
    if (!this.hasSummary) return;
    if (this.isSummaryMode) {
      this.isSummaryMode = false;
      this.targetPostNumber = 0;
      this.loadTopicDetail();
      return;
    }

    this.isSummaryMode = true;
    this.isAuthorOnlyMode = false;
    this.targetPostNumber = 0;
    this.loadTopicDetail();
  }

  private toggleAuthorOnlyMode(): void {
    if (this.isAuthorOnlyMode) {
      this.isAuthorOnlyMode = false;
      this.targetPostNumber = 0;
      this.loadTopicDetail();
      return;
    }

    if (this.topicOwnerUsername.trim().length === 0) {
      ToastService.show($r('app.string.topic_owner_unavailable'));
      return;
    }

    this.isAuthorOnlyMode = true;
    this.isSummaryMode = false;
    this.targetPostNumber = 0;
    this.loadTopicDetail();
  }

  private getTopicSharePath(postNumber: number = 0): string {
    const slug: string = this.topicSlug !== undefined && this.topicSlug !== null ? this.topicSlug.trim() : '';
    const safeSlug: string = slug.length > 0 ? slug : 'topic';
    if (postNumber > 0) {
      return `/t/${safeSlug}/${this.topicId}/${postNumber}`;
    }
    return `/t/${safeSlug}/${this.topicId}`;
  }

  private getTopicShareUrl(): string {
    return ShareUtils.buildShareUrl(this.getTopicSharePath());
  }

  private async shareTopic(): Promise<void> {
    const url: string = this.getTopicShareUrl();
    const ok: boolean = await SystemShareService.shareText(url, this.topicTitle, false);
    if (ok) return;

    const copied: boolean = await ClipboardService.copyText(url, true);
    if (!copied) {
      ToastService.showShareFailed();
    }
  }

  private openTopicInBrowser(): void {
    ExternalLinkService.openInBrowser(this.getTopicShareUrl());
  }

  private handlePostLinkClick(url: string): void {
    const raw: string = url !== undefined && url !== null ? url.trim() : '';
    if (raw.length === 0) return;
    if (raw.startsWith('#')) return;

    if (raw.startsWith('mailto:') || raw.startsWith('tel:')) {
      ExternalLinkService.openInBrowser(raw);
      return;
    }

    const full: string = UrlUtils.resolveUrl(raw);
    let path: string = full;
    const schemeIdx: number = full.indexOf('://');
    if (schemeIdx >= 0) {
      const after: number = schemeIdx + 3;
      const slashIdx: number = full.indexOf('/', after);
      path = slashIdx >= 0 ? full.substring(slashIdx) : '/';
    }

    if (path.startsWith('/t/')) {
      const segs: string[] = path.split('/');
      let topicId: number = 0;
      let postNumber: number = 0;
      for (let i = 2; i < segs.length; i++) {
        const s: string = segs[i].trim();
        if (s.length === 0) continue;
        const n: number = parseInt(s, 10);
        if (!isNaN(n)) {
          if (topicId <= 0) {
            topicId = n;
          } else if (postNumber <= 0) {
            postNumber = n;
            break;
          }
        }
      }

      if (topicId > 0) {
        if (topicId === this.topicId && postNumber > 0) {
          this.jumpToPostNumber(postNumber);
          return;
        }
        RouterManager.pushTopicDetail(topicId, postNumber > 0 ? postNumber : 0);
        return;
      }
    }

    if (path.startsWith('/u/')) {
      const segs: string[] = path.split('/');
      if (segs.length >= 3) {
        const username: string = segs[2].trim();
        if (username.length > 0) {
          RouterManager.pushUserProfile(username);
          return;
        }
      }
    }

    ExternalLinkService.openInBrowser(full);
  }

  private openImagePreview(urls: string[], initialIndex: number): void {
    if (urls.length === 0) return;
    let idx: number = initialIndex;
    if (idx < 0) idx = 0;
    if (idx >= urls.length) idx = urls.length - 1;
    RouterManager.pushImagePreview(urls, idx);
  }

  private resetTopicSearchResults(): void {
    this.searchResults = [];
    this.searchPage = 1;
    this.searchHasMore = false;
    this.isSearchLoading = false;
    this.isSearchLoadingMore = false;
  }

  private enterSearchMode(): void {
    this.isSearchMode = true;
    this.searchQuery = '';
    this.searchErrorMessage = '';
    this.resetTopicSearchResults();
    try {
      this.searchScroller.scrollToIndex(0, false, ScrollAlign.START);
    } catch (_) {
    }
  }

  private exitSearchMode(): void {
    this.isSearchMode = false;
    this.searchErrorMessage = '';
    this.resetTopicSearchResults();
  }

  private loadMoreTopicSearch(): void {
    if (this.isSearchLoading || this.isSearchLoadingMore) return;
    if (!this.searchHasMore) return;
    if (this.searchQuery.trim().length === 0) return;
    this.performTopicSearch(false);
  }

  private async performTopicSearch(reset: boolean): Promise<void> {
    const keyword: string = this.searchQuery.trim();
    if (keyword.length === 0) {
      this.searchErrorMessage = '';
      this.resetTopicSearchResults();
      return;
    }

    if (reset) {
      this.resetTopicSearchResults();
      this.searchErrorMessage = '';
      this.isSearchLoading = true;
    } else {
      if (this.isSearchLoadingMore) return;
      this.isSearchLoadingMore = true;
    }

    const page: number = reset ? 1 : this.searchPage;
    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const query: string = `${keyword} topic:${this.topicId}`;
      const result: SearchResult = await apiClient.search(query, page, 'topic');
      const incoming: SearchPost[] = result.posts;

      if (reset) {
        this.searchResults = incoming;
      } else {
        const map: Map<number, boolean> = new Map();
        for (let i = 0; i < this.searchResults.length; i++) {
          map.set(this.searchResults[i].id, true);
        }
        const merged: SearchPost[] = [];
        for (let i = 0; i < this.searchResults.length; i++) {
          merged.push(this.searchResults[i]);
        }
        for (let i = 0; i < incoming.length; i++) {
          const p: SearchPost = incoming[i];
          if (!map.has(p.id)) {
            merged.push(p);
          }
        }
        this.searchResults = merged;
      }

      this.searchHasMore = result.hasMorePosts;
      if (this.searchHasMore) {
        this.searchPage = page + 1;
      }
      this.searchErrorMessage = '';
    } catch (err) {
      hilog.error(0x0000, TAG, 'Topic search failed: %{public}s', JSON.stringify(err));
      this.searchErrorMessage = reset ? '搜索失败' : '加载更多失败';
    } finally {
      this.isSearchLoading = false;
      this.isSearchLoadingMore = false;
    }
  }

  private openTimelineSheet(): void {
    const max: number = this.postsCount > 0 ? this.postsCount : 1;
    let initial: number = this.currentPostIndex;
    if (initial < 1) initial = 1;
    if (initial > max) initial = max;

    this.timelineSelected = initial;
    this.timelineInput = `${initial}`;
    this.isTimelineEditMode = false;
    this.isTimelineSheetVisible = true;
  }

  private confirmTimelineJump(): void {
    const max: number = this.postsCount > 0 ? this.postsCount : 1;
    let target: number = this.timelineSelected;

    if (this.isTimelineEditMode) {
      const raw: string = this.timelineInput.trim();
      const parsed: number = parseInt(raw, 10);
      if (!isNaN(parsed)) {
        target = parsed;
      }
    }

    if (target < 1) target = 1;
    if (target > max) target = max;

    this.timelineSelected = target;
    this.timelineInput = `${target}`;
    this.isTimelineEditMode = false;
    this.isTimelineSheetVisible = false;

    if (this.streamIds.length >= target) {
      const postId: number = this.streamIds[target - 1];
      this.jumpToPostId(postId);
      return;
    }

    this.jumpToPostNumber(target);
  }

  private jumpToPostNumber(postNumber: number): void {
    this.performJumpToPostNumber(postNumber);
  }

  private jumpToPostId(postId: number): void {
    this.performJumpToPostId(postId);
  }

  private reloadWithTargetPostNumber(postNumber: number): void {
    let target: number = postNumber;
    if (target < 1) target = 1;
    if (this.postsCount > 0 && target > this.postsCount) target = this.postsCount;

    if (this.isSummaryMode || this.isAuthorOnlyMode) {
      this.isSummaryMode = false;
      this.isAuthorOnlyMode = false;
    }
    this.targetPostNumber = target;
    this.loadTopicDetail();
  }

  private async resolvePostNumberById(postId: number): Promise<number> {
    if (postId <= 0) return 0;
    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const posts: Post[] = await apiClient.getTopicPosts(this.topicId, [postId]);
      if (posts.length > 0) {
        const postNumber: number = posts[0].postNumber;
        return postNumber > 0 ? postNumber : 0;
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Resolve post number by id failed: %{public}s', JSON.stringify(err));
    }
    return 0;
  }

  private async loadPostByIdAndScroll(postId: number): Promise<boolean> {
    if (postId <= 0) return false;
    if (this.scrollToPostByIdIfLoaded(postId)) return true;

    if (this.streamIds.length > 0 && !this.streamIndexMap.has(postId)) {
      return false;
    }

    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const posts: Post[] = await apiClient.getTopicPosts(this.topicId, [postId]);
      if (posts.length > 0) {
        this.mergePostsByStream(posts);
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load post by id failed: %{public}s', JSON.stringify(err));
      return false;
    }

    return this.scrollToPostByIdIfLoaded(postId);
  }

  private async performJumpToPostId(postId: number): Promise<void> {
    const target: number = postId;
    if (target <= 0) return;

    this.exitSearchMode();

    if (this.streamIndexMap.has(target)) {
      const targetPostNumber: number = (this.streamIndexMap.get(target) as number) + 1;
      this.armPendingHighlight(targetPostNumber);
      if (this.scrollToPostByIdIfLoaded(target)) {
        return;
      }
      this.reloadWithTargetPostNumber(targetPostNumber);
      return;
    }

    const resolvedPostNumber: number = await this.resolvePostNumberById(target);
    if (resolvedPostNumber > 0) {
      this.armPendingHighlight(resolvedPostNumber);
      this.reloadWithTargetPostNumber(resolvedPostNumber);
    }
  }

  private async performJumpToPostNumber(postNumber: number): Promise<void> {
    let target: number = postNumber;
    if (target < 1) target = 1;
    if (this.postsCount > 0 && target > this.postsCount) target = this.postsCount;

    this.exitSearchMode();
    this.armPendingHighlight(target);

    if (this.scrollToPostByPostNumberIfLoaded(target)) {
      return;
    }

    // 对齐安卓：目标楼层不在当前已加载列表时，直接按目标楼层重载一段连续帖子，
    // 避免只把单个目标楼层插到当前列表里，造成 20 后面突然接 33 的断层。
    this.reloadWithTargetPostNumber(target);
  }

  private getCategoryColor(category: Category | null): string {
    if (category === null) return '#999999';
    const c: Category = category as Category;
    if (c.color.length === 0) return '#999999';
    if (c.color.startsWith('#')) return c.color;
    return `#${c.color}`;
  }

  private getTopicTimeText(): string {
    return TimeUtils.formatRelativeTime(this.topicCreatedAt, this.timeTick);
  }

  private getBottomSafeHeight(): number {
    return WindowManager.getSystemAvoidAreaBottomVp();
  }

  private getDetailBottomBarVisibleTranslateY(): number {
    return -(this.getBottomSafeHeight() + FLOATING_TAB_BAR_MARGIN_BOTTOM_VP + FLOATING_TAB_BAR_HEIGHT_VP);
  }

  private getDetailBottomBarHideTranslate(): number {
    return FLOATING_TAB_BAR_HEIGHT_VP + this.getBottomSafeHeight() + FLOATING_TAB_BAR_MARGIN_BOTTOM_VP
      + BOTTOM_BAR_HIDE_EXTRA_TRANSLATE;
  }

  private getDetailBottomBarReservedBottomVp(): number {
    return this.getBottomSafeHeight()
      + 20
      + this.bottomBarVisibility
      * (FLOATING_TAB_BAR_HEIGHT_VP + FLOATING_TAB_BAR_MARGIN_BOTTOM_VP + FLOATING_TAB_BAR_CONTENT_EXTRA_PADDING_VP);
  }

  private getProgressBottomOffset(): number {
    return this.getBottomSafeHeight()
      + PROGRESS_BOTTOM_NO_BAR
      + this.bottomBarVisibility * (BOTTOM_BAR_HEIGHT + FLOATING_TAB_BAR_MARGIN_BOTTOM_VP + PROGRESS_GAP_ABOVE_BAR);
  }

  private getProgressTranslateY(): number {
    return -(this.getProgressBottomOffset() + PROGRESS_CAPSULE_HEIGHT);
  }

  private setBottomBarVisible(visible: boolean): void {
    if (visible === this.showBottomBar) return;

    this.showBottomBar = visible;
    const target: number = visible ? 1 : 0;
    const uiContext = this.getUIContext();
    if (uiContext !== undefined && uiContext !== null) {
      uiContext.animateTo({ duration: BOTTOM_BAR_ANIM_DURATION, curve: Curve.EaseOut }, () => {
        this.bottomBarVisibility = target;
      });
    } else {
      this.bottomBarVisibility = target;
    }
  }

  private setBottomBarVisibleInstant(visible: boolean): void {
    this.showBottomBar = visible;
    this.bottomBarVisibility = visible ? 1 : 0;
  }

  private hexWithAlpha(hex: string, alpha: number): string {
    let colorHex: string = hex;
    if (colorHex.startsWith('#')) {
      colorHex = colorHex.substring(1);
    }
    const a: number = Math.max(0, Math.min(1, alpha));
    const alphaHex: string = Math.round(a * 255).toString(16).padStart(2, '0');
    if (colorHex.length === 6) {
      return `#${alphaHex}${colorHex}`;
    }
    if (colorHex.length === 8) {
      return `#${alphaHex}${colorHex.substring(2)}`;
    }
    return `#${alphaHex}999999`;
  }

  @Builder
  CategoryBadge(category: Category) {
    Row() {
      if (category.uploadedLogo !== null && (category.uploadedLogo as string).length > 0) {
        Image(UrlUtils.resolveUrl(category.uploadedLogo as string))
          .width(BADGE_ICON_SIZE)
          .height(BADGE_ICON_SIZE)
          .objectFit(ImageFit.Contain)
          .margin({ right: 4 })
      } else if (category.readRestricted) {
        SymbolGlyph($r('sys.symbol.lock'))
          .fontSize(BADGE_ICON_SIZE)
          .fontColor([this.getCategoryColor(category)])
          .margin({ right: 4 })
      } else {
        Circle()
          .width(BADGE_ICON_SIZE * 0.6)
          .height(BADGE_ICON_SIZE * 0.6)
          .fill(this.getCategoryColor(category))
          .margin({ right: 4 })
      }

      Text(category.name)
        .fontSize(BADGE_FONT_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface'))
    }
    .padding({ left: BADGE_PADDING_H, right: BADGE_PADDING_H, top: BADGE_PADDING_V, bottom: BADGE_PADDING_V })
    .backgroundColor(this.hexWithAlpha(this.getCategoryColor(category), 0.08))
    .border({ width: 1, color: this.hexWithAlpha(this.getCategoryColor(category), 0.2) })
    .borderRadius(BADGE_RADIUS)
    .alignItems(VerticalAlign.Center)
    .margin({ right: 6, bottom: 8 })
  }

  @Builder
  TagBadge(tagName: string) {
    TopicTagBadge({
      name: tagName,
      fontSize: BADGE_FONT_SIZE,
      iconSize: BADGE_ICON_SIZE,
      radius: BADGE_RADIUS,
      paddingH: BADGE_PADDING_H,
      paddingV: BADGE_PADDING_V
    })
      .margin({ right: 6, bottom: 8 })
  }

  @Builder
  MetadataItem(symbol: Resource, valueText: string, labelText: string) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(14)
        .fontColor([$r('app.color.on_surface_secondary')])
      Text(` ${valueText}`)
        .fontSize(12)
        .fontColor($r('app.color.on_surface_secondary'))
        .fontWeight(FontWeight.Medium)
      if (labelText.length > 0) {
        Text(` ${labelText}`)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_tertiary'))
          .margin({ left: 1 })
      }
    }
    .alignItems(VerticalAlign.Center)
    .margin({ right: 12 })
  }

  @Builder
  NotificationChip() {
    Row() {
      SymbolGlyph($r('sys.symbol.bell'))
        .fontSize(16)
        .fontColor([$r('app.color.primary')])
      Text(` ${this.notificationLevelLabel}`)
        .fontSize(13)
        .fontColor($r('app.color.primary'))
        .fontWeight(FontWeight.Medium)
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.badge_background_light'))
    .borderRadius(8)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      ToastService.showLoginRequired();
    })
  }

  @Builder
  TopicHeader() {
    Column() {
      Column() {
        // 标题（对齐 Flutter：closed/accepted icon + title）
        Row() {
          if (this.isClosed) {
            SymbolGlyph($r('sys.symbol.lock'))
              .fontSize(20)
              .fontColor([$r('app.color.on_surface_tertiary')])
              .margin({ right: 8 })
          }
          if (this.hasAcceptedAnswer) {
            SymbolGlyph($r('sys.symbol.checkmark_square_fill'))
              .fontSize(20)
              .fontColor([$r('app.color.success')])
              .margin({ right: 8 })
          }
          Text(this.topicTitle.length > 0 ? this.topicTitle : `#${this.topicId}`)
            .fontSize($r('app.float.text_size_title'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .lineHeight(30)
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // 分类 + tags
        if (this.topicCategory !== null || this.topicTags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            if (this.topicCategory !== null) {
              this.CategoryBadge(this.topicCategory as Category)
            }
            ForEach(this.topicTags, (t: string) => {
              this.TagBadge(t)
            }, (t: string) => t)
          }
          .width('100%')
          .margin({ top: 16 })
        }

        // 元数据行：回复 / 浏览 / 时间
        Row() {
          this.MetadataItem($r('sys.symbol.message'), `${this.replyCount}`, '回复')
          this.MetadataItem($r('sys.symbol.eye'), `${this.topicViews}`, '浏览')
          this.MetadataItem($r('sys.symbol.clock'), `${this.getTopicTimeText()}`, '')
        }
        .width('100%')
        .margin({ top: 16 })
        .alignItems(VerticalAlign.Center)

        // 通知等级（对齐 Flutter：chip 风格）
        Column() {
          this.NotificationChip()
        }
        .margin({ top: 16 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 16 })
      .backgroundColor($r('app.color.surface'))
      .alignItems(HorizontalAlign.Start)

      Divider()
        .color($r('app.color.divider_light'))
        .strokeWidth(0.5)
    }
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 主体内容层
        Column() {
          // 自定义 AppBar（Navigation 全局 TitleBar 已隐藏）
          if (this.isSearchMode) {
            this.TopicSearchTopBar()
          } else {
            this.TopBar()
          }

          if (this.isLoading) {
            Column() {
              LoadingSpinner({ message: '' })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.errorMessage.length > 0) {
            Column() {
              ErrorView({
                title: '加载失败',
                message: this.errorMessage,
                showRetry: true,
                onRetry: () => {
                  this.loadTopicDetail();
                }
              })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            if (this.isSearchMode) {
              this.TopicSearchBody()
            } else {
              Refresh({ refreshing: false }) {
                // 帖子列表
                List({ scroller: this.listScroller }) {
                  // 头部信息区（随列表一起滚动）
                  ListItem() {
                    this.TopicHeader()
                  }

                  if (this.shouldShowLoadPreviousEntry()) {
                    ListItem() {
                      this.LoadPreviousEntry()
                    }
                  }

                  ForEach(this.posts, (post: Post) => {
                    ListItem() {
                      if (post.actionCode !== null && post.actionCode.length > 0) {
                        // small_action 类型帖子
                        this.SmallActionItem(post)
                      } else {
                        // 普通帖子
                        this.PostItem(post)
                      }
                    }
                  }, (post: Post) => post.id.toString())

                  if (this.hasMoreAfter || this.isLoadingMore || this.isLoadMoreFailed) {
                    ListItem() {
                      this.LoadMoreFooter()
                    }
                  }
                }
                .width('100%')
                .layoutWeight(1)
                .backgroundColor($r('app.color.surface'))
                .padding({ bottom: this.getDetailBottomBarReservedBottomVp() })
                .onReachStart(() => {
                  this.scrollOffset = 0;
                  this.showTitle = false;
                  this.setBottomBarVisibleInstant(false);
                  this._bottomBarDelta = 0;
                })
                .onReachEnd(() => {
                  this.loadMoreAfter();
                })
                .onScrollIndex((start: number, end: number, center: number) => {
                  this.lastVisibleStartIndex = start;
                  this.lastVisibleEndIndex = end;
                  const idx: number = start >= 0 ? start : center;
                  this.updateCurrentPostIndexFromScrollIndex(idx);
                  this.maybeTriggerPendingHighlight(start, end);
                })
                .onScrollFrameBegin((offset: number, state: ScrollState) => {
                  // 记录滚动偏移，用于控制 AppBar 标题显隐（offset 为每帧增量）
                  const next: number = Math.max(0, this.scrollOffset + offset);
                  this.scrollOffset = next;

                  // 底部工具栏：对齐安卓（FluxDO）
                  // - 向上滚动（offset<0）→ 显示
                  // - 向下滚动（offset>0）→ 隐藏
                  if (next <= 0) {
                    this._bottomBarDelta = 0;
                    if (this.showBottomBar) {
                      this.setBottomBarVisible(false);
                    }
                  } else {
                    // 方向改变时重置累计，避免轻微回弹导致阈值判断反复
                    if ((this._bottomBarDelta > 0 && offset < 0) || (this._bottomBarDelta < 0 && offset > 0)) {
                      this._bottomBarDelta = offset;
                    } else {
                      this._bottomBarDelta = this._bottomBarDelta + offset;
                    }

                    if (this._bottomBarDelta < -BOTTOM_BAR_TOGGLE_DELTA && !this.showBottomBar) {
                      this._bottomBarDelta = 0;
                      this.setBottomBarVisible(true);
                    } else if (this._bottomBarDelta > BOTTOM_BAR_TOGGLE_DELTA && this.showBottomBar) {
                      this._bottomBarDelta = 0;
                      this.setBottomBarVisible(false);
                    }
                  }

                  this.showTitle = next > TITLE_SHOW_OFFSET;
                  return { offsetRemain: offset };
                })
              }
              .onRefreshing(() => {
                this.refreshTopicDetail();
              })
              .layoutWeight(1)
            }
          }
        }
        .width('100%')
        .height('100%')
        // 全局沉浸式：为顶部状态栏安全区预留 padding，避免内容被挖孔/状态栏遮挡
        .padding({ top: WindowManager.getSystemAvoidAreaTopVp() })

        // 浮层：进度胶囊 + 底部工具栏 + FAB
        if (!this.isLoading && this.errorMessage.length === 0 && !this.isSearchMode) {
          // 进度胶囊（常驻）
          Row() {
            Text(`${this.currentPostIndex}`)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.on_surface'))
            Text(`/${this.postsCount}`)
              .fontSize(13)
              .fontColor($r('app.color.on_surface_secondary'))
          }
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.surface'))
          .borderRadius(20)
          .shadow({ radius: 4, color: '#33000000', offsetX: 0, offsetY: 2 })
          .position({ x: '50%', y: '100%' })
          .translate({ x: '-50%', y: this.getProgressTranslateY() })
          .onClick(() => {
            this.openTimelineSheet();
          })

          // 底部工具栏：改为首页同款悬浮玻璃胶囊
          Row() {
            Stack() {
              Column() {
              }
              .width('100%')
              .height('100%')
              .backgroundEffect(
                {
                  radius: 64,
                  saturation: 2.2,
                  brightness: 1.08,
                  color: $r('app.color.tab_glass_tint'),
                  adaptiveColor: AdaptiveColor.DEFAULT,
                  policy: BlurStyleActivePolicy.ALWAYS_ACTIVE,
                  inactiveColor: $r('app.color.tab_glass_tint')
                },
                { disableSystemAdaptation: true }
              )

              Row() {
                // 回到顶部
                Column() {
                  SymbolGlyph($r('sys.symbol.arrow_up'))
                    .fontSize(20)
                    .fontColor([$r('app.color.on_surface_secondary')])
                }
                .layoutWeight(1)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .height('100%')
                .onClick(() => {
                  this.listScroller.scrollToIndex(0, true, ScrollAlign.START);
                  this.scrollOffset = 0;
                  this.showTitle = false;
                  this.setBottomBarVisibleInstant(false);
                  this._bottomBarDelta = 0;
                })

                // 热门回复
                if (this.hasSummary) {
                  Column() {
                    SymbolGlyph($r('sys.symbol.flame'))
                      .fontSize(20)
                      .fontColor(this.isSummaryMode ? [$r('app.color.primary')] : [$r('app.color.on_surface_secondary')])
                  }
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .height('100%')
                  .backgroundColor(this.isSummaryMode ? $r('app.color.tab_selected_pill') : Color.Transparent)
                  .borderRadius(20)
                  .margin({ top: 8, bottom: 8 })
                  .onClick(() => {
                    this.toggleSummaryMode();
                  })
                }

                // 只看题主
                Column() {
                  SymbolGlyph($r('sys.symbol.person'))
                    .fontSize(20)
                    .fontColor(this.isAuthorOnlyMode ? [$r('app.color.primary')] : [$r('app.color.on_surface_secondary')])
                }
                .layoutWeight(1)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .height('100%')
                .backgroundColor(this.isAuthorOnlyMode ? $r('app.color.tab_selected_pill') : Color.Transparent)
                .borderRadius(20)
                .margin({ top: 8, bottom: 8 })
                .onClick(() => {
                  this.toggleAuthorOnlyMode();
                })

                // 分享
                Column() {
                  SymbolGlyph($r('sys.symbol.share'))
                    .fontSize(20)
                    .fontColor([$r('app.color.on_surface_secondary')])
                }
                .layoutWeight(1)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .height('100%')
                .bindMenu(this.ShareMenuBuilder())

                // 浏览器打开
                Column() {
                  SymbolGlyph($r('sys.symbol.compass'))
                    .fontSize(20)
                    .fontColor([$r('app.color.on_surface_secondary')])
                }
                .layoutWeight(1)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .height('100%')
                .onClick(() => {
                  this.openTopicInBrowser();
                })
              }
              .width('100%')
              .height('100%')
            }
            .width('100%')
            .height(FLOATING_TAB_BAR_HEIGHT_VP)
            .border({ width: 0.5, color: $r('app.color.tab_glass_stroke') })
            .borderRadius(FLOATING_TAB_BAR_RADIUS_VP)
            .clip(true)
            .shadow({ radius: 18, color: $r('app.color.tab_glass_shadow'), offsetX: 0, offsetY: 10 })
          }
          .width('100%')
          .padding({ left: FLOATING_TAB_BAR_MARGIN_H_VP, right: FLOATING_TAB_BAR_MARGIN_H_VP })
          .opacity(this.bottomBarVisibility)
          .position({ x: 0, y: '100%' })
          .translate({
            x: 0,
            y: this.getDetailBottomBarVisibleTranslateY()
              + (1 - this.bottomBarVisibility) * this.getDetailBottomBarHideTranslate()
          })
          .enabled(this.bottomBarVisibility > 0.05)
        }

        // 游客态：隐藏回复 FAB（后续接入登录态后再开放）
        if (!this.isLoading && this.errorMessage.length === 0 && !this.isGuestMode && !this.isSearchMode) {
          Button() {
            SymbolGlyph($r('sys.symbol.message'))
              .fontSize(22)
              .fontColor([Color.White])
          }
          .width(56)
          .height(56)
          .borderRadius(16)
          .backgroundColor($r('app.color.primary'))
          .shadow({ radius: 8, color: '#55000000', offsetX: 0, offsetY: 4 })
          .position({ x: '100%', y: '100%' })
          .translate({ x: -72, y: -72 })
          .onClick(() => {
            this.openReplySheet();
          })
        }

        // 离屏分享卡片（用于生成分享图片的组件快照）
        if (this.isShareImageSheetVisible) {
          ForEach([this.shareImageCardId], (cardId: string) => {
            Column() {
              postShareImageBuilder(this.shareImageParams, this.shareImageThemeIndex)
            }
            .id(cardId)
            .width(375)
            .position({ x: -5000, y: -5000 })
            .onAppear(() => {
              this.maybeScheduleShareImageSnapshot(cardId);
            })
          }, (cardId: string) => cardId)
        }

        // 分享图片 Sheet 宿主（避免与时间线 Sheet 冲突）
        Column() {
        }
        .width(0)
        .height(0)
        .bindSheet($$this.isShareImageSheetVisible, this.ShareImageSheetBuilder, {
          height: SheetSize.LARGE,
          dragBar: false,
          showClose: false,
          backgroundColor: $r('app.color.surface')
        })

        // 导出文章 Sheet 宿主（避免与时间线 Sheet 冲突）
        Column() {
        }
        .width(0)
        .height(0)
        .bindSheet($$this.isExportSheetVisible, this.ExportSheetBuilder, {
          height: SheetSize.MEDIUM,
          dragBar: false,
          showClose: false,
          backgroundColor: $r('app.color.surface')
        })

        // 图片长按上下文菜单 Sheet
        Column() {
        }
        .width(0)
        .height(0)
        .bindSheet($$this.isImageContextSheetVisible, this.ImageContextSheetBuilder, {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          backgroundColor: $r('app.color.surface')
        })

        Column() {
        }
        .width(0)
        .height(0)
        .bindSheet($$this.isReplySheetVisible, this.ReplySheetBuilder, {
          height: SheetSize.LARGE,
          dragBar: false,
          showClose: false,
          backgroundColor: $r('app.color.surface')
        })
      }
      .width('100%')
      .height('100%')
      .bindSheet($$this.isTimelineSheetVisible, this.TimelineSheetBuilder, {
        height: SheetSize.MEDIUM,
        dragBar: false,
        showClose: false,
        backgroundColor: $r('app.color.surface')
      })
    }
    .backgroundColor($r('app.color.surface'))
    .hideTitleBar(true)
    .hideToolBar(true)
  }

  @Builder
  TopBar() {
    Column() {
      Stack() {
        if (this.showTitle) {
          Row() {
            Text(this.topicTitle.length > 0 ? this.topicTitle : `#${this.topicId}`)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.on_surface'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .width('100%')
          }
          .width('100%')
          .height(56)
          .padding({ left: 56, right: 96 })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        }

        Row() {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(18)
              .fontColor([$r('app.color.on_surface')])
          }
          .width(44)
          .height(44)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            RouterManager.pop();
          })

          Blank().layoutWeight(1)

          Row() {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(18)
              .fontColor([$r('app.color.on_surface_secondary')])
          }
          .width(44)
          .height(44)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.enterSearchMode();
          })
          Row() {
            SymbolGlyph($r('sys.symbol.ellipsis_message'))
              .fontSize(18)
              .fontColor([$r('app.color.on_surface_secondary')])
          }
          .width(44)
          .height(44)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .bindMenu(this.MoreMenuBuilder())
        }
        .width('100%')
        .height(56)
        .padding({ left: 8, right: 8 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(56)

      if (this.scrollOffset > 0) {
        Divider()
          .color($r('app.color.divider_light'))
          .strokeWidth(0.5)
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  TopicSearchTopBar() {
    Column() {
      Row() {
        // 返回（退出话题内搜索模式）
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(18)
            .fontColor([$r('app.color.on_surface')])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.exitSearchMode();
        })

        // 搜索输入框（圆角胶囊）
        Row() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([$r('app.color.on_surface_tertiary')])
            .margin({ right: 6 })

          TextInput({ text: this.searchQuery, placeholder: $r('app.string.search_hint') })
            .fontSize(15)
            .fontColor($r('app.color.on_surface'))
            .placeholderColor($r('app.color.on_surface_tertiary'))
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onChange((value: string) => {
              if (value !== this.searchQuery) {
                this.searchQuery = value;
                if (this.searchQuery.trim().length === 0) {
                  this.searchErrorMessage = '';
                  this.resetTopicSearchResults();
                }
              }
            })
            .onSubmit(() => {
              this.performTopicSearch(true);
            })

          if (this.searchQuery.length > 0) {
            Row() {
              SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
                .fontSize(18)
                .fontColor([$r('app.color.on_surface_tertiary')])
            }
            .width(32)
            .height(32)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.searchQuery = '';
              this.searchErrorMessage = '';
              this.resetTopicSearchResults();
            })
          }
        }
        .height(40)
        .padding({ left: 14, right: 10 })
        .backgroundColor($r('app.color.search_background'))
        .borderRadius(20)
        .layoutWeight(1)
        .margin({ left: 6, right: 6 })
        .alignItems(VerticalAlign.Center)

        // 搜索按钮
        Row() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([$r('app.color.on_surface_secondary')])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.performTopicSearch(true);
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .color($r('app.color.divider_light'))
        .strokeWidth(0.5)
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  TopicSearchBody() {
    Column() {
      if (this.isSearchLoading && this.searchResults.length === 0) {
        Column() {
          LoadingSpinner({ message: '' })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.searchErrorMessage.length > 0 && this.searchResults.length === 0) {
        Column() {
          ErrorView({
            title: '搜索失败',
            message: this.searchErrorMessage,
            showRetry: true,
            onRetry: () => {
              this.performTopicSearch(true);
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ scroller: this.searchScroller }) {
          if (!this.isSearchLoading && this.searchResults.length === 0) {
            ListItem() {
              Column() {
                Text('暂无结果')
                  .fontSize(13)
                  .fontColor($r('app.color.on_surface_secondary'))
              }
              .width('100%')
              .padding({ top: 28, bottom: 28 })
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }
          }

          ForEach(this.searchResults, (p: SearchPost) => {
            ListItem() {
              this.TopicSearchPostRow(p)
            }
          }, (p: SearchPost) => p.id.toString())

          if (this.isSearchLoadingMore) {
            ListItem() {
              Row() {
                LoadingProgress()
                  .width(16)
                  .height(16)
                Text('加载中...')
                  .fontSize(12)
                  .fontColor($r('app.color.on_surface_secondary'))
                  .margin({ left: 8 })
              }
              .width('100%')
              .padding({ top: 12, bottom: 12 })
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
            }
          } else if (this.searchErrorMessage.length > 0 && this.searchResults.length > 0) {
            ListItem() {
              Row() {
                SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
                  .fontSize(16)
                  .fontColor([$r('app.color.on_surface_secondary')])
                Text('加载失败，点击重试')
                  .fontSize(12)
                  .fontColor($r('app.color.on_surface_secondary'))
                  .margin({ left: 8 })
              }
              .width('100%')
              .padding({ top: 12, bottom: 12 })
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.searchErrorMessage = '';
                this.loadMoreTopicSearch();
              })
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12, top: 10 })
        .backgroundColor($r('app.color.background'))
        .onReachEnd(() => {
          this.loadMoreTopicSearch();
        })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  TopicSearchPostRow(post: SearchPost) {
    Row() {
      SmartAvatar({
        avatarUrl: post.getAvatarUrl(72),
        avatarSize: 28,
        avatarRadius: 14,
        fallbackText: post.username,
        bgColor: '#E8EAF0'
      })

      Column() {
        Text(this.stripHtml(post.blurb))
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`@${post.username} · #${post.postNumber} · ${TimeUtils.formatRelativeTime(post.createdAt, this.timeTick)}`)
          .fontSize(11)
          .fontColor($r('app.color.on_surface_tertiary'))
          .margin({ top: 6 })
      }
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
    .margin({ bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.jumpToPostNumber(post.postNumber);
    })
  }

  @Builder
  LoadPreviousEntry() {
    Row() {
      if (this.isLoadingPrevious) {
        LoadingProgress()
          .width(16)
          .height(16)
        Text('加载中...')
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ left: 8 })
      } else if (this.isLoadPreviousFailed) {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
          .fontSize(16)
          .fontColor([$r('app.color.on_surface_secondary')])
        Text('加载失败，点击重试')
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ left: 8 })
      } else {
        Text($r('app.string.load_previous'))
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (this.isLoadingPrevious) return;
      if (this.isLoadPreviousFailed) {
        this.isLoadPreviousFailed = false;
      }
      this.loadPreviousBefore();
    })
  }

  @Builder
  LoadMoreFooter() {
    Row() {
      if (this.isLoadingMore) {
        LoadingProgress()
          .width(16)
          .height(16)
        Text('加载中...')
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ left: 8 })
      } else if (this.isLoadMoreFailed) {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
          .fontSize(16)
          .fontColor([$r('app.color.on_surface_secondary')])
        Text('加载失败，点击重试')
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ left: 8 })
      } else {
        Text($r('app.string.load_more'))
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (this.isLoadingMore) return;
      if (this.isLoadMoreFailed) {
        this.isLoadMoreFailed = false;
      }
      this.loadMoreAfter();
    })
  }

  @Builder
  MoreMenuBuilder() {
    Menu() {
      MenuItem() {
        Row() {
          SymbolGlyph($r('sys.symbol.bookmark'))
            .fontSize(16)
            .fontColor([$r('app.color.on_surface')])
            .margin({ right: 10 })
          Text('书签')
            .fontSize(14)
            .fontColor($r('app.color.on_surface'))
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
      }
      .selected(false)
      .selectIcon(false)
      .height(44)
      .onChange((selected: boolean) => {
        if (selected) {
          ToastService.showLoginRequired();
        }
      })

      MenuItem() {
        Row() {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(16)
            .fontColor([$r('app.color.on_surface')])
            .margin({ right: 10 })
          Text('加入浮窗')
            .fontSize(14)
            .fontColor($r('app.color.on_surface'))
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
      }
      .selected(false)
      .selectIcon(false)
      .height(44)
      .onChange((selected: boolean) => {
        if (selected) {
          ToastService.showLoginRequired();
        }
      })

      MenuItem() {
        Row() {
          SymbolGlyph($r('sys.symbol.bell'))
            .fontSize(16)
            .fontColor([$r('app.color.on_surface')])
            .margin({ right: 10 })
          Text('订阅设置')
            .fontSize(14)
            .fontColor($r('app.color.on_surface'))
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
      }
      .selected(false)
      .selectIcon(false)
      .height(44)
      .onChange((selected: boolean) => {
        if (selected) {
          ToastService.showLoginRequired();
        }
      })
    }
    .width(180)
    .backgroundColor($r('app.color.search_bar_background'))
    .borderRadius(12)
    .shadow({ radius: 10, color: '#22000000', offsetX: 0, offsetY: 6 })
  }

  private getPostShareUrl(post: Post): string {
    const postNumber: number = post.postNumber > 0 ? post.postNumber : 1;
    return ShareUtils.buildShareUrl(this.getTopicSharePath(postNumber), '', true);
  }

  private getPostAvatarUrl(post: Post, size: number): string {
    const s: number = size > 0 ? Math.round(size) : 120;
    return UrlUtils.resolveUrl(post.getAvatarUrl(s));
  }

  private getLoadedPostByPostNumber(postNumber: number): Post | null {
    const idx: number = this.findPostIndexByPostNumber(postNumber);
    if (idx < 0 || idx >= this.posts.length) return null;
    return this.posts[idx];
  }

  private getReplyTargetAvatarUrl(post: Post, size: number): string {
    if (post.replyToUser !== null) {
      const template: string = (post.replyToUser as ReplyToUser).avatarTemplate;
      if (template !== undefined && template !== null && template.trim().length > 0) {
        return UrlUtils.getAvatarUrl(template, size);
      }
    }
    if (post.replyToPostNumber > 0) {
      const target: Post | null = this.getLoadedPostByPostNumber(post.replyToPostNumber);
      if (target !== null) {
        return this.getPostAvatarUrl(target, size);
      }
    }
    return '';
  }

  private getReplyTargetUsername(post: Post): string {
    if (post.replyToUser !== null) {
      const username: string = (post.replyToUser as ReplyToUser).username;
      if (username !== undefined && username !== null && username.trim().length > 0) {
        return username;
      }
    }
    if (post.replyToPostNumber > 0) {
      const target: Post | null = this.getLoadedPostByPostNumber(post.replyToPostNumber);
      if (target !== null) {
        return target.username;
      }
    }
    return '';
  }

  private async sharePostLink(post: Post): Promise<void> {
    const url: string = this.getPostShareUrl(post);
    const ok: boolean = await SystemShareService.shareText(url, this.topicTitle, false);
    if (!ok) {
      ToastService.showShareFailed();
    }
  }

  private joinPath(dir: string, name: string): string {
    const d: string = dir !== undefined && dir !== null ? dir.trim() : '';
    const n: string = name !== undefined && name !== null ? name.trim() : '';
    if (d.length === 0) return n;
    if (d.endsWith('/') || d.endsWith('\\')) return `${d}${n}`;
    return `${d}/${n}`;
  }

  private stripFileScheme(uriOrPath: string): string {
    const raw: string = uriOrPath !== undefined && uriOrPath !== null ? uriOrPath.trim() : '';
    if (raw.startsWith('file://')) {
      return raw.substring('file://'.length);
    }
    return raw;
  }

  private cleanupShareImageFile(): void {
    const raw: string = this.stripFileScheme(this.shareImageFileUri);
    if (raw.length === 0) return;
    try {
      fileIo.unlinkSync(raw);
    } catch (_) {
    }
    this.shareImageFileUri = '';
  }

  private buildShareImageParams(post: Post): PostShareImageParams {
    const p: PostShareImageParams = new PostShareImageParams();
    p.topicTitle = this.topicTitle;
    p.authorName = post.name !== null && post.name.length > 0 ? post.name : post.username;
    p.username = post.username;
    p.avatarUrl = this.getPostAvatarUrl(post, 80);
    p.timeText = TimeUtils.formatRelativeTime(post.createdAt, this.timeTick);
    p.floorText = `#${post.postNumber}`;
    p.contentText = this.getPlainText(post.cooked);
    p.shareUrl = this.getPostShareUrl(post);
    return p;
  }

  private async generateShareImage(requestId: number, cardId: string): Promise<void> {
    if (requestId !== this.shareImageRequestId) {
      return;
    }

    const ctx = AppContext.getUIAbilityContext();
    if (ctx === null) {
      if (requestId !== this.shareImageRequestId) return;
      this.shareImageLoading = false;
      this.shareImageErrorMessage = '系统能力不可用';
      return;
    }

    try {
      const pixelMap: image.PixelMap = await componentSnapshot.get(cardId, {
        scale: 2,
        waitUntilRenderFinished: true
      });

      if (requestId !== this.shareImageRequestId) {
        return;
      }

      this.shareImagePixelMap = pixelMap;

      const packer = image.createImagePacker();
      const opts: image.PackingOption = {
        format: 'image/png',
        quality: 100
      };
      const buf: ArrayBuffer = await packer.packing(pixelMap, opts);
      try {
        packer.release();
      } catch (_) {
      }

      if (requestId !== this.shareImageRequestId) {
        return;
      }

      this.shareImagePngBuffer = buf;
      this.cleanupShareImageFile();

      const name: string = `harmonydo_post_${this.topicId}_${this.shareImageTargetPostNumber}_${Date.now()}.png`;
      const cacheDir: string = ctx.cacheDir;
      const path: string = this.joinPath(cacheDir, name);

      const f = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, buf);
      fileIo.closeSync(f);

      if (requestId !== this.shareImageRequestId) {
        try {
          fileIo.unlinkSync(path);
        } catch (_) {
        }
        return;
      }

      this.shareImageFileUri = path.startsWith('file://') ? path : `file://${path}`;
      this.shareImageLoading = false;
      this.shareImageErrorMessage = '';
    } catch (err) {
      hilog.error(0x0000, TAG, 'Generate share image failed: %{public}s', JSON.stringify(err));
      if (requestId !== this.shareImageRequestId) return;
      this.shareImageLoading = false;
      this.shareImageErrorMessage = '生成失败';
    }
  }

  private openPostShareImage(post: Post): void {
    this.shareImageRequestId = this.shareImageRequestId + 1;
    const requestId: number = this.shareImageRequestId;

    this.cleanupShareImageFile();
    this.shareImagePixelMap = null;
    this.shareImagePngBuffer = null;
    this.shareImageErrorMessage = '';
    this.shareImageTargetPostNumber = post.postNumber;
    this.shareImageParams = this.buildShareImageParams(post);
    this.shareImageLoading = true;
    const cardId: string = `share_post_card_${requestId}`;
    this.shareImageCardId = cardId;
    this.isShareImageSheetVisible = true;
  }

  private openTopicShareImage(): void {
    // 对齐安卓：底部栏“生成分享图片”默认分享主帖；若主帖未加载则提示
    let first: Post | null = null;
    for (let i = 0; i < this.posts.length; i++) {
      const p: Post = this.posts[i];
      if (p.postNumber === 1 && (p.actionCode === null || p.actionCode.length === 0)) {
        first = p;
        break;
      }
    }
    if (first === null) {
      ToastService.show('主帖未加载');
      return;
    }
    this.openPostShareImage(first as Post);
  }

  private openExportSheet(): void {
    this.isTimelineSheetVisible = false;
    this.isShareImageSheetVisible = false;
    this.exportErrorMessage = '';
    this.exportProgressText = '';
    this.exportLoading = false;
    this.isExportSheetVisible = true;
  }

  private closeExportSheet(): void {
    this.isExportSheetVisible = false;
    this.exportErrorMessage = '';
    this.exportProgressText = '';
    this.exportLoading = false;
  }

  private async exportArticle(): Promise<void> {
    if (this.exportLoading) return;

    const ctx = AppContext.getUIAbilityContext();
    if (ctx === null) {
      this.exportErrorMessage = '系统能力不可用';
      return;
    }

    if (this.topicId <= 0) {
      this.exportErrorMessage = '无效的话题ID';
      return;
    }

    if (this.streamIds.length === 0) {
      this.exportErrorMessage = '帖子流未加载';
      return;
    }

    this.exportLoading = true;
    this.exportErrorMessage = '';
    this.exportProgressText = '';

    try {
      const shareUrl: string = this.getTopicShareUrl();
      const cacheDir: string = ctx.cacheDir;
      const result = await ExportUtils.exportTopicToFile(
        this.topicId,
        this.topicTitle,
        shareUrl,
        this.streamIds,
        this.exportScope,
        this.exportFormat,
        cacheDir,
        (current: number, total: number) => {
          this.exportProgressText = `导出中 (${current}/${total})`;
        }
      );

      if (!result.ok) {
        this.exportErrorMessage = result.errorMessage.length > 0 ? result.errorMessage : '导出失败';
        return;
      }

      this.exportProgressText = '';
      const ok: boolean = await SystemShareService.shareFile(result.fileUri, this.topicTitle, false);
      if (!ok) {
        ToastService.showShareFailed();
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'exportArticle failed: %{public}s', JSON.stringify(err));
      this.exportErrorMessage = '导出失败';
    } finally {
      this.exportLoading = false;
    }
  }

  private closeShareImageSheet(): void {
    this.shareImageRequestId = this.shareImageRequestId + 1;
    this.isShareImageSheetVisible = false;
    this.shareImageLoading = false;
    this.shareImageErrorMessage = '';
    this.shareImagePixelMap = null;
    this.shareImagePngBuffer = null;
    this.shareImageTargetPostNumber = 0;
    this.cleanupShareImageFile();
  }

  private retryShareImage(): void {
    if (!this.isShareImageSheetVisible) return;
    if (this.shareImageLoading) return;

    this.shareImageRequestId = this.shareImageRequestId + 1;
    const requestId: number = this.shareImageRequestId;
    this.cleanupShareImageFile();
    this.shareImagePixelMap = null;
    this.shareImagePngBuffer = null;
    this.shareImageErrorMessage = '';
    this.shareImageLoading = true;

    const cardId: string = `share_post_card_${requestId}`;
    this.shareImageCardId = cardId;
  }

  private selectShareImageTheme(index: number): void {
    let idx: number = Math.round(index);
    if (idx < 0) idx = 0;
    if (idx >= SHARE_IMAGE_THEME_NAMES.length) idx = 0;
    if (idx === this.shareImageThemeIndex) return;

    this.shareImageThemeIndex = idx;
    PreferencesUtil.putNumber(PREF_KEY_SHARE_IMAGE_THEME, idx).catch((_: Object) => {
    });

    // 主题切换后重新生成图片（取消当前请求并重试）
    if (!this.isShareImageSheetVisible) return;

    this.shareImageRequestId = this.shareImageRequestId + 1;
    const requestId: number = this.shareImageRequestId;
    this.cleanupShareImageFile();
    this.shareImagePixelMap = null;
    this.shareImagePngBuffer = null;
    this.shareImageErrorMessage = '';
    this.shareImageLoading = true;

    const cardId: string = `share_post_card_${requestId}`;
    this.shareImageCardId = cardId;
  }

  private async saveShareImageToGallery(): Promise<void> {
    if (this.shareImageLoading) return;
    if (this.shareImageErrorMessage.length > 0) return;

    const ctx = AppContext.getUIAbilityContext();
    if (ctx === null) {
      ToastService.show('系统能力不可用');
      return;
    }

    if (this.shareImagePngBuffer === null) {
      ToastService.show('图片未生成');
      return;
    }

    const ok: boolean = await MediaSaveService.savePngToGallery(ctx, this.shareImagePngBuffer as ArrayBuffer, this.topicTitle);
    if (ok) {
      ToastService.show('已保存到相册');
    } else {
      ToastService.show('保存失败，请检查权限或系统限制');
    }
  }

  @Builder
  ShareMenuBuilder() {
    Menu() {
      MenuItem() {
        Row() {
          SymbolGlyph($r('sys.symbol.link'))
            .fontSize(16)
            .fontColor([$r('app.color.on_surface')])
            .margin({ right: 10 })
          Text('分享链接')
            .fontSize(14)
            .fontColor($r('app.color.on_surface'))
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
      }
      .selected(false)
      .selectIcon(false)
      .height(44)
      .onChange((selected: boolean) => {
        if (selected) {
          this.shareTopic();
        }
      })

      MenuItem() {
        Row() {
          SymbolGlyph($r('sys.symbol.shutter_photo'))
            .fontSize(16)
            .fontColor([$r('app.color.on_surface')])
            .margin({ right: 10 })
          Text('生成分享图片')
            .fontSize(14)
            .fontColor($r('app.color.on_surface'))
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
      }
      .selected(false)
      .selectIcon(false)
      .height(44)
      .onChange((selected: boolean) => {
        if (selected) {
          this.openTopicShareImage();
        }
      })

      MenuItem() {
        Row() {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(16)
            .fontColor([$r('app.color.on_surface')])
            .margin({ right: 10 })
          Text('导出文章')
            .fontSize(14)
            .fontColor($r('app.color.on_surface'))
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
      }
      .selected(false)
      .selectIcon(false)
      .height(44)
      .onChange((selected: boolean) => {
        if (selected) {
          this.openExportSheet();
        }
      })
    }
    .width(200)
    .backgroundColor($r('app.color.search_bar_background'))
    .borderRadius(12)
    .shadow({ radius: 10, color: '#22000000', offsetX: 0, offsetY: 6 })
  }

  @Builder
  PostMoreMenuBuilder(post: Post) {
    Menu() {
      if (!this.isGuestMode) {
        MenuItem() {
          Row() {
            SymbolGlyph($r('sys.symbol.message'))
              .fontSize(16)
              .fontColor([$r('app.color.on_surface')])
              .margin({ right: 10 })
            Text('回复此楼')
              .fontSize(14)
              .fontColor($r('app.color.on_surface'))
          }
          .width('100%')
          .padding({ left: 12, right: 12 })
          .alignItems(VerticalAlign.Center)
        }
        .selected(false)
        .selectIcon(false)
        .height(44)
        .onChange((selected: boolean) => {
          if (selected) {
            this.openReplySheet(post);
          }
        })

        MenuItem() {
          Row() {
            SymbolGlyph($r('sys.symbol.doc_text'))
              .fontSize(16)
              .fontColor([$r('app.color.on_surface')])
              .margin({ right: 10 })
            Text('引用回复')
              .fontSize(14)
              .fontColor($r('app.color.on_surface'))
          }
          .width('100%')
          .padding({ left: 12, right: 12 })
          .alignItems(VerticalAlign.Center)
        }
        .selected(false)
        .selectIcon(false)
        .height(44)
        .onChange((selected: boolean) => {
          if (selected) {
            this.openPostQuoteReply(post);
          }
        })
      }

      MenuItem() {
        Row() {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(16)
            .fontColor([$r('app.color.on_surface')])
            .margin({ right: 10 })
          Text('复制引用')
            .fontSize(14)
            .fontColor($r('app.color.on_surface'))
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
      }
      .selected(false)
      .selectIcon(false)
      .height(44)
      .onChange((selected: boolean) => {
        if (selected) {
          this.copyPostQuote(post);
        }
      })

      MenuItem() {
        Row() {
          SymbolGlyph($r('sys.symbol.link'))
            .fontSize(16)
            .fontColor([$r('app.color.on_surface')])
            .margin({ right: 10 })
          Text('分享链接')
            .fontSize(14)
            .fontColor($r('app.color.on_surface'))
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
      }
      .selected(false)
      .selectIcon(false)
      .height(44)
      .onChange((selected: boolean) => {
        if (selected) {
          this.sharePostLink(post);
        }
      })

      MenuItem() {
        Row() {
          SymbolGlyph($r('sys.symbol.shutter_photo'))
            .fontSize(16)
            .fontColor([$r('app.color.on_surface')])
            .margin({ right: 10 })
          Text('生成分享图片')
            .fontSize(14)
            .fontColor($r('app.color.on_surface'))
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
      }
      .selected(false)
      .selectIcon(false)
      .height(44)
      .onChange((selected: boolean) => {
        if (selected) {
          this.openPostShareImage(post);
        }
      })
    }
    .width(200)
    .backgroundColor($r('app.color.search_bar_background'))
    .borderRadius(12)
    .shadow({ radius: 10, color: '#22000000', offsetX: 0, offsetY: 6 })
  }

  @Builder
  TimelineSheetBuilder() {
    Column() {
      // 标题栏
      Row() {
        Text($r('app.string.jump_to_post'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .layoutWeight(1)

        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('app.color.on_surface_secondary')])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.isTimelineSheetVisible = false;
        })
      }
      .width('100%')
      .padding({ left: 16, right: 8, top: 12, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      // 主体：左侧信息 + 右侧竖直轨道
      Row() {
        Column() {
          Text('当前楼层')
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))

          if (this.isTimelineEditMode) {
            Row() {
              TextInput({ text: this.timelineInput, placeholder: `${this.timelineSelected}` })
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.on_surface'))
                .backgroundColor($r('app.color.search_background'))
                .borderRadius(12)
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .width(96)
                .onChange((value: string) => {
                  this.timelineInput = value;
                })
                .onSubmit(() => {
                  this.confirmTimelineJump();
                })

              Text(` / ${this.postsCount}`)
                .fontSize(22)
                .fontColor($r('app.color.on_surface_tertiary'))
                .margin({ left: 6 })
            }
            .margin({ top: 10 })
            .alignItems(VerticalAlign.Center)
          } else {
            Row() {
              Text(`${this.timelineSelected}`)
                .fontSize(48)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary'))
              Text(` / ${this.postsCount}`)
                .fontSize(20)
                .fontColor($r('app.color.on_surface_tertiary'))
                .margin({ left: 6, top: 18 })

              Column() {
                SymbolGlyph($r('sys.symbol.pencil_line'))
                  .fontSize(16)
                  .fontColor([$r('app.color.on_surface_secondary')])
              }
              .width(32)
              .height(32)
              .borderRadius(16)
              .backgroundColor($r('app.color.surface_variant'))
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .margin({ left: 10, top: 18 })
              .onClick(() => {
                this.isTimelineEditMode = true;
              })
            }
            .margin({ top: 10 })
            .alignItems(VerticalAlign.Top)
          }

          Button() {
            Text('定位于此')
              .fontSize(13)
              .fontColor($r('app.color.primary'))
          }
          .height(36)
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.badge_background_light'))
          .borderRadius(18)
          .margin({ top: 18 })
          .onClick(() => {
            const max: number = this.postsCount > 0 ? this.postsCount : 1;
            let cur: number = this.currentPostIndex;
            if (cur < 1) cur = 1;
            if (cur > max) cur = max;
            this.timelineSelected = cur;
            this.timelineInput = `${cur}`;
            this.isTimelineEditMode = false;
          })
        }
        .layoutWeight(1)
        .padding({ left: 16, right: 12, top: 10, bottom: 10 })
        .alignItems(HorizontalAlign.Start)

        Column() {
          Slider({
            value: this.timelineSelected,
            min: 1,
            max: this.postsCount > 0 ? this.postsCount : 1,
            step: 1,
            direction: Axis.Vertical
          })
            .height(240)
            .onChange((value: number) => {
              const v: number = Math.round(value);
              this.timelineSelected = v;
              this.timelineInput = `${v}`;
              this.isTimelineEditMode = false;
            })
        }
        .width(68)
        .padding({ right: 16, top: 10, bottom: 10 })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 底部按钮区
      Row() {
        Button() {
          Text('取消')
            .fontSize(14)
            .fontColor($r('app.color.on_surface'))
        }
        .height(40)
        .layoutWeight(1)
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(20)
        .onClick(() => {
          this.isTimelineSheetVisible = false;
        })

        Blank().width(12)

        Button() {
          Text('跳转')
            .fontSize(14)
            .fontColor(Color.White)
        }
        .height(40)
        .layoutWeight(1)
        .backgroundColor($r('app.color.primary'))
        .borderRadius(20)
        .onClick(() => {
          this.confirmTimelineJump();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 + WindowManager.getSystemAvoidAreaBottomVp() })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  ShareImageSheetBuilder() {
    Column() {
      // 标题栏
      Row() {
        Text('分享图片')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .layoutWeight(1)

        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('app.color.on_surface_secondary')])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.closeShareImageSheet();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 8, top: 12, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      if (this.shareImageLoading) {
        Column() {
          LoadingSpinner({ message: '' })
          Text('正在生成…')
            .fontSize(13)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 12 })
        }
        .width('100%')
        .height(360)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.shareImageErrorMessage.length > 0) {
        Column() {
          Text(this.shareImageErrorMessage)
            .fontSize(13)
            .fontColor($r('app.color.on_surface_secondary'))

          Button() {
            Text('重试')
              .fontSize(13)
              .fontColor(Color.White)
          }
          .height(36)
          .padding({ left: 18, right: 18 })
          .backgroundColor($r('app.color.primary'))
          .borderRadius(18)
          .margin({ top: 14 })
          .onClick(() => {
            this.retryShareImage();
          })
        }
        .width('100%')
        .height(360)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          if (this.shareImagePixelMap !== null) {
            Image(this.shareImagePixelMap as image.PixelMap)
              .width('100%')
              .height(420)
              .objectFit(ImageFit.Contain)
              .borderRadius(12)
              .backgroundColor($r('app.color.surface_variant'))
          } else {
            Image(this.shareImageFileUri)
              .width('100%')
              .height(420)
              .objectFit(ImageFit.Contain)
              .borderRadius(12)
              .backgroundColor($r('app.color.surface_variant'))
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
      }

      // 主题选择（对齐安卓）
      Row() {
        ForEach(SHARE_IMAGE_THEME_INDICES, (idx: number) => {
          Column() {
            Stack() {
              Circle()
                .width(30)
                .height(30)
                .fill(SHARE_IMAGE_THEME_COLORS[idx])

              if (this.shareImageThemeIndex === idx) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(16)
                  .fontColor([idx === 3 ? Color.White : $r('app.color.primary')])
              }
            }
            .width(30)
            .height(30)
            .borderRadius(15)

            Text(SHARE_IMAGE_THEME_NAMES[idx])
              .fontSize(11)
              .fontColor($r('app.color.on_surface_secondary'))
              .margin({ top: 6 })
          }
          .width(52)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            if (this.shareImageLoading) return;
            if (this.shareImageErrorMessage.length > 0) return;
            this.selectShareImageTheme(idx);
          })
        }, (idx: number) => idx.toString())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Top)

      // 底部按钮区：保存到相册 / 分享
      Row() {
        Button() {
          Row() {
            SymbolGlyph($r('sys.symbol.arrow_down'))
              .fontSize(16)
              .fontColor([$r('app.color.on_surface')])
              .margin({ right: 8 })
            Text('保存到相册')
              .fontSize(14)
              .fontColor($r('app.color.on_surface'))
          }
          .alignItems(VerticalAlign.Center)
        }
        .height(44)
        .layoutWeight(1)
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(22)
        .enabled(!this.shareImageLoading && this.shareImageErrorMessage.length === 0)
        .onClick(() => {
          this.saveShareImageToGallery();
        })

        Blank().width(12)

        Button() {
          Row() {
            SymbolGlyph($r('sys.symbol.share'))
              .fontSize(16)
              .fontColor([Color.White])
              .margin({ right: 8 })
            Text('分享')
              .fontSize(14)
              .fontColor(Color.White)
          }
          .alignItems(VerticalAlign.Center)
        }
        .height(44)
        .layoutWeight(1)
        .backgroundColor($r('app.color.primary'))
        .borderRadius(22)
        .enabled(!this.shareImageLoading && this.shareImageErrorMessage.length === 0)
        .onClick(() => {
          SystemShareService.shareImage(this.shareImageFileUri, this.topicTitle, false).then((ok: boolean) => {
            if (!ok) {
              ToastService.showShareFailed();
            }
          });
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 18, bottom: 16 + WindowManager.getSystemAvoidAreaBottomVp() })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private ExportSegment(title: string, selected: boolean, onSelect: () => void) {
    Row() {
      if (selected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontColor([$r('app.color.primary')])
          .margin({ right: 6 })
      }
      Text(title)
        .fontSize(14)
        .fontWeight(selected ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(selected ? $r('app.color.primary') : $r('app.color.on_surface_secondary'))
    }
    .layoutWeight(1)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(selected ? $r('app.color.badge_background_light') : Color.Transparent)
    .borderRadius(18)
    .onClick(() => {
      onSelect();
    })
  }

  private handleImageContextAction(action: string): void {
    const previewUrl: string = this.imageContextPreviewUrl;
    const thumbUrl: string = this.imageContextThumbUrl;
    this.isImageContextSheetVisible = false;

    if (action === 'view') {
      if (previewUrl.length > 0) {
        RouterManager.pushImagePreview([previewUrl], 0);
      }
    } else if (action === 'copy_image') {
      const url: string = previewUrl.length > 0 ? previewUrl : thumbUrl;
      if (url.length > 0) {
        ClipboardService.copyText(url, false).then((ok: boolean) => {
          if (ok) ToastService.show('图片链接已复制');
        });
      }
    } else if (action === 'copy_link') {
      const url: string = previewUrl.length > 0 ? previewUrl : thumbUrl;
      if (url.length > 0) {
        ClipboardService.copyText(url, true).catch((_: Object) => {
        });
      }
    } else if (action === 'share') {
      const url: string = previewUrl.length > 0 ? previewUrl : thumbUrl;
      if (url.length > 0) {
        SystemShareService.shareText(url, '分享图片').catch((_: Object) => {
          ToastService.showShareFailed();
        });
      }
    } else if (action === 'copy_quote') {
      const url: string = previewUrl.length > 0 ? previewUrl : thumbUrl;
      if (url.length > 0) {
        const quote: string = this.buildDiscourseQuote(
          `![image](${url})`,
          this.imageContextUsername,
          this.imageContextPostNumber
        );
        if (quote.length > 0) {
          this.copyQuoteText(quote);
        } else {
          this.copyQuoteText(`![image](${url})`);
        }
      }
    } else if (action === 'quote_reply') {
      this.openImageQuoteReply();
    }

    this.imageContextThumbUrl = '';
    this.imageContextPreviewUrl = '';
    this.imageContextPostNumber = 0;
    this.imageContextUsername = '';
    this.imageContextAvatarTemplate = '';
  }

  @Builder
  ReplySheetBuilder() {
    ReplyComposerSheet({
      topicId: this.topicId,
      replyToPostNumber: this.replySheetTargetPostNumber,
      replyToUsername: this.replySheetTargetUsername,
      replyToAvatarTemplate: this.replySheetTargetAvatarTemplate,
      initialContent: this.replySheetInitialContent,
      requestKey: this.replySheetRequestKey,
      onSubmitted: (post: Post) => {
        this.handleReplySubmitted(post);
      },
      onDismiss: (submitted: boolean) => {
        this.handleReplySheetDismiss(submitted);
      }
    })
  }

  @Builder
  ImageContextSheetBuilder() {
    Column() {
      this.ImageContextItem($r('sys.symbol.magnifyingglass'), '查看大图', () => {
        this.handleImageContextAction('view');
      })

      this.ImageContextItem($r('sys.symbol.doc_text'), '复制图片', () => {
        this.handleImageContextAction('copy_image');
      })

      this.ImageContextItem($r('sys.symbol.link'), '复制链接', () => {
        this.handleImageContextAction('copy_link');
      })

      this.ImageContextItem($r('sys.symbol.share'), '分享图片', () => {
        this.handleImageContextAction('share');
      })

      if (!this.isGuestMode && this.imageContextPostNumber > 0 && this.imageContextUsername.length > 0) {
        this.ImageContextItem($r('sys.symbol.doc_text'), '引用到回复框', () => {
          this.handleImageContextAction('quote_reply');
        })
      }

      this.ImageContextItem($r('sys.symbol.doc_text'), '复制引用', () => {
        this.handleImageContextAction('copy_quote');
      })

      Blank().height(16 + WindowManager.getSystemAvoidAreaBottomVp())
    }
    .width('100%')
    .padding({ top: 8 })
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private ImageContextItem(icon: Resource, title: string, onClick: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([$r('app.color.on_surface')])
        .margin({ right: 16 })
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.on_surface'))
    }
    .width('100%')
    .height(52)
    .padding({ left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      onClick();
    })
  }

  @Builder
  ExportSheetBuilder() {
    Column() {
      // 标题栏
      Row() {
        Text('导出文章')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .layoutWeight(1)

        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('app.color.on_surface_secondary')])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.closeExportSheet();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 8, top: 12, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      // 导出范围
      Column() {
        Text('导出范围')
          .fontSize(13)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ bottom: 10 })

        Row() {
          this.ExportSegment('仅主帖', this.exportScope === 0, () => {
            this.exportScope = 0;
          })
          this.ExportSegment('全部', this.exportScope === 1, () => {
            this.exportScope = 1;
          })
        }
        .width('100%')
        .padding(2)
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(20)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10 })

      // 导出格式
      Column() {
        Text('导出格式')
          .fontSize(13)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ bottom: 10, top: 16 })

        Row() {
          this.ExportSegment('MD', this.exportFormat === 0, () => {
            this.exportFormat = 0;
          })
          this.ExportSegment('HTML', this.exportFormat === 1, () => {
            this.exportFormat = 1;
          })
        }
        .width('100%')
        .padding(2)
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(20)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      // 错误/进度提示
      if (this.exportErrorMessage.length > 0) {
        Text(this.exportErrorMessage)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ top: 14, left: 16, right: 16 })
      } else if (this.exportProgressText.length > 0) {
        Text(this.exportProgressText)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ top: 14, left: 16, right: 16 })
      }

      // 导出按钮
      Button() {
        Text(this.exportLoading ? '导出中...' : '导出')
          .fontSize(15)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .height(52)
      .margin({ top: 18 })
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.primary'))
      .borderRadius(26)
      .enabled(!this.exportLoading)
      .onClick(() => {
        this.exportArticle();
      })

      Blank().height(16 + WindowManager.getSystemAvoidAreaBottomVp())
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  PostItem(post: Post) {
    Column() {
      Stack() {
        // 跳楼高亮背景（2s 自动淡出）
        if (this.highlightPostNumber === post.postNumber && this.highlightOpacity > 0) {
          Column() {
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.badge_background_light'))
          .opacity(this.highlightOpacity)
        }

        Column() {
        // 头部：头像 + 用户名/头衔 + 右侧时间/楼层
        Row() {
          AvatarWithFlair({
            avatarUrl: this.getPostAvatarUrl(post, 80),
            avatarSize: 40,
            fallbackText: post.username,
            flairUrl: post.flairUrl,
            flairName: post.flairName,
            flairBgColor: post.flairBgColor,
            flairColor: post.flairColor,
            flairSize: 16
          })
          .onClick(() => {
            RouterManager.pushUserProfile(post.username);
          })

          Column() {
            Row() {
              Text(post.name !== null && post.name.length > 0 ? post.name : post.username)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor((post.moderator || post.admin) ? $r('app.color.primary') : $r('app.color.on_surface'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              if (
                post.userStatus !== null
                && (post.userStatus as UserStatus).emoji !== null
                && ((post.userStatus as UserStatus).emoji as string).trim().length > 0
              ) {
                UserStatusEmoji({
                  rawEmoji: ((post.userStatus as UserStatus).emoji as string).trim(),
                  iconSize: 16,
                  marginLeft: 4
                })
              }

              if (this.topicOwnerUsername.length > 0 && post.postNumber > 1 && post.username === this.topicOwnerUsername) {
                Text('主')
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.primary'))
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .backgroundColor($r('app.color.badge_background_light'))
                  .borderRadius(6)
                  .margin({ left: 6 })
              }

              if (post.moderator || post.admin || post.groupModerator) {
                SymbolGlyph($r('sys.symbol.security_shield'))
                  .fontSize(12)
                  .fontColor([$r('app.color.primary')])
                  .margin({ left: 4 })
              }
            }
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              RouterManager.pushUserProfile(post.username);
            })

            Row() {
              Text(`@${post.username}`)
                .fontSize(11)
                .fontColor($r('app.color.on_surface_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (post.userTitle !== null && (post.userTitle as string).length > 0) {
                if ((post.userTitle as string) === '种子用户') {
                  Text(`${post.userTitle as string}`)
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.seed_user_gradient_start'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ left: 6 })
                    .shaderStyle({
                      direction: GradientDirection.Right,
                      colors: [$r('app.color.seed_user_gradient_start'), $r('app.color.seed_user_gradient_end')]
                    })
                } else {
                  Text(`${post.userTitle as string}`)
                    .fontSize(11)
                    .fontColor($r('app.color.primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ left: 6 })
                }
              }

              if (post.badgesGranted.length > 0) {
                ForEach(post.badgesGranted, (b: Object) => {
                  if ((b as GrantedBadge).imageUrl !== null && ((b as GrantedBadge).imageUrl as string).length > 0) {
                    Image(UrlUtils.resolveUrl((b as GrantedBadge).imageUrl as string))
                      .width(12)
                      .height(12)
                      .objectFit(ImageFit.Contain)
                      .margin({ left: 4 })
                  } else if ((b as GrantedBadge).icon !== null && ((b as GrantedBadge).icon as string).length > 0) {
                    if (this.getGrantedBadgeSymbol((b as GrantedBadge).icon as string) !== null) {
                      SymbolGlyph(this.getGrantedBadgeSymbol((b as GrantedBadge).icon as string) as Resource)
                        .fontSize(12)
                        .fontColor([this.getGrantedBadgeTypeColor((b as GrantedBadge).badgeTypeId)])
                        .margin({ left: 4 })
                    }
                  }
                }, (b: Object) => (b as GrantedBadge).id.toString())
              }
            }
            .margin({ top: 2 })
            .alignItems(VerticalAlign.Center)
          }
          .layoutWeight(1)
          .margin({ left: 12 })
          .alignItems(HorizontalAlign.Start)

          Row() {
            if (post.replyToPostNumber > 0) {
              Row() {
                SymbolGlyph($r('sys.symbol.arrowshape_turn_up_left'))
                  .fontSize(14)
                  .fontColor([$r('app.color.primary')])
                  .margin({ right: 6 })

                if (this.getReplyTargetAvatarUrl(post, 40).length > 0 || this.getReplyTargetUsername(post).length > 0) {
                  SmartAvatar({
                    avatarUrl: this.getReplyTargetAvatarUrl(post, 40),
                    avatarSize: 20,
                    avatarRadius: 10,
                    fallbackText: this.getReplyTargetUsername(post),
                    bgColor: '#E8EAF0'
                  })
                } else {
                  Text(`#${post.replyToPostNumber}`)
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.primary'))
                }
              }
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor($r('app.color.badge_background_light'))
              .borderRadius(20)
              .border({ width: 1, color: $r('app.color.primary') })
              .onClick(() => {
                this.jumpToPostNumber(post.replyToPostNumber);
              })

              Blank().width(12)
            }

            Column() {
              Text(TimeUtils.formatRelativeTime(post.createdAt, this.timeTick))
                .fontSize(11)
                .fontColor($r('app.color.on_surface_secondary'))
              Text(`#${post.postNumber}`)
                .fontSize(10)
                .fontColor($r('app.color.on_surface_tertiary'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.End)
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // 内容
        Column() {
          PostRichContent({
            cookedHtml: post.cooked,
            post: post,
            allowPollInteraction: !this.isGuestMode,
            enableSelectionQuote: true,
            enableCopyQuoteSelection: true,
            onOpenLink: (url: string) => {
              this.handlePostLinkClick(url);
            },
            onOpenImagePreview: (urls: string[], initialIndex: number) => {
              this.openImagePreview(urls, initialIndex);
            },
            onQuoteSelection: (selectedText: string, sourceHtml: string) => {
              if (this.isGuestMode) {
                this.copySelectionQuote(post, selectedText, sourceHtml);
              } else {
                const quote: string = this.buildPostQuoteFromSelection(post, selectedText, sourceHtml);
                if (quote.length > 0) {
                  this.openReplySheet(post, quote);
                } else {
                  ToastService.show('没有可引用的内容');
                }
              }
            },
            onCopyQuoteSelection: (selectedText: string, sourceHtml: string) => {
              this.copySelectionQuote(post, selectedText, sourceHtml);
            },
            onLongPressImage: (imageUrl: string, previewUrl: string) => {
              this.openImageContextSheet(post, imageUrl, previewUrl);
            },
            onPostUpdated: (updatedPost: Post) => {
              this.replacePostInstance(updatedPost);
            }
          })
        }
        .width('100%')
        .margin({ top: 12 })

        // 相关链接（reflection links，对齐安卓 FluxDO）
        if (post.linkCounts !== null) {
          PostLinks({
            linkCounts: post.linkCounts,
            onOpenLink: (url: string) => {
              this.handlePostLinkClick(url);
            }
          })
        }

        if (post.postNumber === 1 && this.hasAcceptedAnswer && this.acceptedAnswerPostNumber > 0) {
          this.PostSolutionBanner(this.acceptedAnswerPostNumber)
        }

        // 底部操作行（UI 复刻阶段：保留基础占位）
        Row() {
          // 左侧：楼层回复数，只要 reply_count>0 就显示；首贴也可能存在真正的定向回复
          if (post.replyCount > 0) {
            Row() {
              SymbolGlyph($r('sys.symbol.message'))
                .fontSize(15)
                .fontColor([(this.expandedRepliesPostNumber === post.postNumber) ? $r('app.color.primary') : $r('app.color.on_surface_secondary')])
              Text(` ${post.replyCount}`)
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor((this.expandedRepliesPostNumber === post.postNumber) ? $r('app.color.primary') : $r('app.color.on_surface_secondary'))
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(18)
                .fontColor([(this.expandedRepliesPostNumber === post.postNumber) ? $r('app.color.primary') : $r('app.color.on_surface_secondary')])
                .rotate({ angle: (this.expandedRepliesPostNumber === post.postNumber) ? 180 : 0 })
                .margin({ left: 2 })
            }
            .height(36)
            .padding({ left: 12, right: 12 })
            .backgroundColor((this.expandedRepliesPostNumber === post.postNumber) ? $r('app.color.badge_background_light') : $r('app.color.surface_variant'))
            .borderRadius(18)
            .border({ width: (this.expandedRepliesPostNumber === post.postNumber) ? 1 : 0, color: $r('app.color.primary') })
            .onClick(() => {
              this.toggleReplies(post);
            })
          }

          Blank().layoutWeight(1)

          // 右侧：更多（游客态严格隐藏点赞，互动功能后续登录态再开放）
          Column() {
            SymbolGlyph($r('sys.symbol.ellipsis_circle'))
              .fontSize(18)
              .fontColor([$r('app.color.on_surface_secondary')])
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor($r('app.color.surface_variant'))
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .bindMenu(this.PostMoreMenuBuilder(post))
        }
        .width('100%')
        .margin({ top: 12 })
        .alignItems(VerticalAlign.Center)

        // 折叠回复列表（离线 Mock：从帖子流中找 reply_to_post_number 指向当前楼层的帖子）
        if (post.replyCount > 0 && this.expandedRepliesPostNumber === post.postNumber) {
            Column() {
              Row() {
                Rect()
                  .width(3)
                  .height(16)
                  .radius(2)
                  .fill($r('app.color.primary'))
                  .margin({ right: 8 })
                Text(`${post.replyCount} 条回复`)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.on_surface'))
              }
              .alignItems(VerticalAlign.Center)
              .justifyContent(FlexAlign.Start)
              .width('100%')

            if (this.expandedRepliesLoading) {
              Row() {
                LoadingSpinner({ message: '' })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .padding({ top: 12, bottom: 6 })
            } else if (this.expandedRepliesErrorMessage.length > 0) {
              Column() {
                Text(this.expandedRepliesErrorMessage)
                  .fontSize(12)
                  .fontColor($r('app.color.on_surface_tertiary'))
                Button() {
                  Text('重试')
                    .fontSize(12)
                    .fontColor(Color.White)
                }
                .height(32)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.primary'))
                .borderRadius(16)
                .margin({ top: 10 })
                .onClick(() => {
                  this.loadRepliesForPost(post);
                })
              }
              .width('100%')
              .margin({ top: 10 })
            } else if (this.expandedReplies.length === 0) {
              Text('暂无回复')
                .fontSize(12)
                .fontColor($r('app.color.on_surface_tertiary'))
                .margin({ top: 10 })
            } else {
              ForEach(this.expandedReplies, (r: Post) => {
                Row() {
                  AvatarWithFlair({
                    avatarUrl: this.getPostAvatarUrl(r, 56),
                    avatarSize: 28,
                    fallbackText: r.username,
                    bgColor: '#E8EAF0',
                    flairUrl: r.flairUrl,
                    flairName: r.flairName,
                    flairBgColor: r.flairBgColor,
                    flairColor: r.flairColor,
                    flairSize: 14
                  })

                  Column() {
                    Row() {
                      Text(r.name !== null && r.name.length > 0 ? r.name : r.username)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.on_surface'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })

                      if (
                        r.userStatus !== null
                        && (r.userStatus as UserStatus).emoji !== null
                        && ((r.userStatus as UserStatus).emoji as string).trim().length > 0
                      ) {
                        UserStatusEmoji({
                          rawEmoji: ((r.userStatus as UserStatus).emoji as string).trim(),
                          iconSize: 14,
                          marginLeft: 4
                        })
                      }
                      Blank().layoutWeight(1)
                      Text(`#${r.postNumber}`)
                        .fontSize(11)
                        .fontColor($r('app.color.on_surface_tertiary'))
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)

                    Text(this.getPlainText(r.cooked))
                      .fontSize(12)
                      .fontColor($r('app.color.on_surface_secondary'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 4 })
                      .width('100%')
                      .textAlign(TextAlign.Start)
                  }
                  .layoutWeight(1)
                  .margin({ left: 10 })
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding(12)
                .backgroundColor($r('app.color.surface_variant'))
                .borderRadius(12)
                .margin({ top: 10 })
                .onClick(() => {
                  this.collapseReplies();
                  this.jumpToPostNumber(r.postNumber);
                })
              }, (r: Post) => r.id.toString())
            }

            Row() {
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(18)
                .fontColor([$r('app.color.on_surface_tertiary')])
                .rotate({ angle: 180 })
                .margin({ right: 4 })
              Text('收起回复')
                .fontSize(13)
                .fontColor($r('app.color.on_surface_tertiary'))
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .padding({ top: 12, bottom: 4 })
            .onClick(() => {
              this.collapseReplies();
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 12 })
        }
        }
          .width('100%')
          .padding(16)

        if (post.acceptedAnswer) {
          Row() {
            this.AcceptedAnswerStamp()
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
          .padding({ top: 8, right: 12 })
        }
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))

      Divider()
        .color($r('app.color.divider_light'))
        .strokeWidth(0.5)
    }
    .width('100%')
    .opacity((post.isDeleted || post.hidden) ? 0.6 : 1)
  }

  private removeRichBlocks(html: string): string {
    let result: string = html;
    result = result.replace(/<blockquote[\s\S]*?<\/blockquote>/g, '');
    result = result.replace(/<pre[\s\S]*?<\/pre>/g, '');
    result = result.replace(/<img[^>]*>/g, '');
    return result;
  }

  private getPlainText(html: string): string {
    return this.stripHtml(this.removeRichBlocks(html)).trim();
  }

  @Builder
  AcceptedAnswerStamp() {
    Row() {
      SymbolGlyph($r('sys.symbol.checkmark_circle'))
        .fontSize(24)
        .fontColor([$r('app.color.success')])

      Text($r('app.string.solved'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.success'))
        .letterSpacing(2)
        .margin({ left: 8 })
    }
    .padding({ left: 12, right: 14, top: 6, bottom: 6 })
    .border({ width: 1.5, color: $r('app.color.success') })
    .borderRadius(22)
    .backgroundColor(Color.Transparent)
    .opacity(0.12)
    .rotate({ angle: -8 })
  }

  @Builder
  SmallActionItem(post: Post) {
    Column() {
      Row() {
        // 图标（圆形容器，对齐 Flutter small_action）
        Column() {
          SymbolGlyph(this.getActionSymbol(post.actionCode))
            .fontSize(16)
            .fontColor([$r('app.color.primary')])
        }
        .width(32)
        .height(32)
        .borderRadius(16)
        .backgroundColor($r('app.color.badge_background_light'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .margin({ right: 12 })

        // 描述 + 时间
        Column() {
          Text(`${post.actionCodeWho !== null && (post.actionCodeWho as string).length > 0 ? post.actionCodeWho as string : post.username} ${this.getActionLabel(post.actionCode)}`)
            .fontSize(14)
            .fontColor($r('app.color.on_surface_secondary'))
            .lineHeight(20)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(TimeUtils.formatRelativeTime(post.createdAt, this.timeTick))
            .fontSize(11)
            .fontColor($r('app.color.on_surface_tertiary'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // 头像
        SmartAvatar({
          avatarUrl: this.getPostAvatarUrl(post, 56),
          avatarSize: 28,
          fallbackText: post.username,
          bgColor: '#E8EAF0'
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .color($r('app.color.divider_light'))
        .strokeWidth(0.5)
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  PostSolutionBanner(postNumber: number) {
    Row() {
      Column() {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize($r('app.float.icon_size_medium'))
          .fontColor([$r('app.color.success')])
      }
      .width(40)
      .height(40)
      .backgroundColor($r('app.color.solution_banner_icon_background'))
      .borderRadius(20)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .shadow({ radius: 6, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 })

      Column() {
        Text($r('app.string.topic_solution_banner_title'))
          .fontSize($r('app.float.text_size_medium'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.success'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          Text($r('app.string.topic_solution_banner_action'))
            .fontSize($r('app.float.text_size_small'))
            .fontColor($r('app.color.success'))
            .maxLines(1)

          Text(`#${postNumber}`)
            .fontSize($r('app.float.text_size_tiny'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.success'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor($r('app.color.solution_banner_chip_background'))
            .borderRadius($r('app.float.border_radius_tiny'))
            .margin({ left: 6 })
        }
        .margin({ top: 4 })
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 16, right: 12 })

      SymbolGlyph($r('sys.symbol.arrow_right'))
        .fontSize($r('app.float.icon_size_small'))
        .fontColor([$r('app.color.success')])
        .opacity(0.65)
    }
    .width('100%')
    .margin({ top: 16 })
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.solution_banner_background'))
    .borderRadius($r('app.float.border_radius_medium'))
    .border({ width: 1, color: $r('app.color.solution_banner_border') })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.jumpToPostNumber(postNumber);
    })
  }

  /**
   * 简单去除 HTML 标签
   */
  private stripHtml(html: string): string {
    if (html.length === 0) {
      return '';
    }
    let result: string = html.replace(/<[^>]*>/g, '');
    result = result.replace(/&nbsp;/g, ' ');
    result = result.replace(/&lt;/g, '<');
    result = result.replace(/&gt;/g, '>');
    result = result.replace(/&amp;/g, '&');
    result = result.replace(/&quot;/g, '"');
    result = result.replace(/\n{3,}/g, '\n\n');
    return result.trim();
  }

  /**
   * 获取操作图标
   */
  private getActionSymbol(actionCode: string | null): Resource {
    if (actionCode === null) return $r('sys.symbol.info_circle');
    if (actionCode.startsWith('pinned')) return $r('sys.symbol.pin');
    if (actionCode.startsWith('closed')) return $r('sys.symbol.lock');
    if (actionCode.startsWith('archived')) return $r('sys.symbol.archivebox');
    if (actionCode.startsWith('visible')) return $r('sys.symbol.eye');
    if (actionCode === 'split_topic') return $r('sys.symbol.cut');
    return $r('sys.symbol.info_circle');
  }

  /**
   * 获取操作标签
   */
  private getActionLabel(actionCode: string | null): string {
    if (actionCode === null) return '';
    if (actionCode === 'pinned.enabled') return '置顶了此话题';
    if (actionCode === 'pinned.disabled') return '取消了置顶';
    if (actionCode === 'closed.enabled') return '关闭了此话题';
    if (actionCode === 'closed.disabled') return '重新打开了此话题';
    if (actionCode === 'archived.enabled') return '归档了此话题';
    if (actionCode === 'archived.disabled') return '取消了归档';
    if (actionCode === 'split_topic') return '拆分了此话题';
    if (actionCode === 'autoclosed.enabled') return '自动关闭了此话题';
    if (actionCode === 'visible.enabled') return '公开了此话题';
    if (actionCode === 'visible.disabled') return '隐藏了此话题';
    return actionCode;
  }
}
