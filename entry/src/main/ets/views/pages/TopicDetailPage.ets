import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { componentSnapshot } from '@kit.ArkUI';
import fileIo from '@ohos.file.fs';
import { Post, PostReaction, PostReactionState, ReplyToUser } from '../../models/Post';
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
import { EmojiResolver } from '../../common/utils/EmojiResolver';
import { PostRichContent } from '../components/PostRichContent';
import { PostLinks } from '../components/PostLinks';
import { ReplyComposerSheet } from '../components/ReplyComposerSheet';
import { BookmarkEditSheet } from '../components/BookmarkEditSheet';
import { UserStatusEmoji } from '../components/UserStatusEmoji';
import { AppContext } from '../../common/utils/AppContext';
import { PostShareImageParams, postShareImageBuilder } from '../components/PostShareImageCard';
import { PreferencesUtil } from '../../services/storage/PreferencesUtil';
import { MAX_READ_LATER_ITEMS, ReadLaterService } from '../../services/storage/ReadLaterService';
import { MessageBusMessage, MessageBusService } from '../../services/messagebus/MessageBusService';
import { PreloadedDataService } from '../../services/messagebus/PreloadedDataService';
import { HoldingHandService, HoldingHandState } from '../../services/device/HoldingHandService';
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
const BOTTOM_BAR_SHOW_DELTA: number = 24;
const BOTTOM_BAR_HIDE_DELTA: number = 50;
const BOTTOM_BAR_ANIM_DURATION: number = 180;
const BOTTOM_BAR_SHOW_DELAY_MS: number = 1200;
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
const FAB_BOTTOM_MARGIN_VP: number = 16;
const POST_REACTION_MIN_INTERVAL_MS: number = 900;
const POST_REACTION_RATE_LIMIT_FALLBACK_SECONDS: number = 13;
const POST_REACTION_PICKER_PANEL_RADIUS: number = 30;
const POST_REACTION_PICKER_SCREEN_MARGIN: number = 16;
const POST_REACTION_PICKER_EDGE_GAP: number = 8;

class ReactionPickerAnchorRect {
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
}

/**
 * 话题详情页面
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

  // 跳楼后短暂高亮
  @Local highlightPostNumber: number = 0;
  @Local highlightOpacity: number = 0;
  @Local timeTick: number = 0;
  @Local showBottomBar: boolean = true;
  @Local bottomBarVisibility: number = 1;
  @Local isSummaryMode: boolean = false;
  @Local isAuthorOnlyMode: boolean = false;
  @Local isClosed: boolean = false;
  @Local hasAcceptedAnswer: boolean = false;
  @Local acceptedAnswerPostNumber: number = 0;
  @Local isBookmarked: boolean = false;
  @Local topicBookmarkId: number = 0;
  @Local topicBookmarkName: string = '';
  @Local topicBookmarkReminderAt: Date | null = null;
  @Local isBookmarkSheetVisible: boolean = false;
  @Local isBookmarkMutating: boolean = false;
  @Local isTopicNotificationSheetVisible: boolean = false;
  @Local isTopicNotificationMutating: boolean = false;
  @Local isInReadLater: boolean = false;
  @Local isPostBookmarkSheetVisible: boolean = false;
  @Local editingPostBookmarkPost: Post | null = null;
  @Local editingReplyPost: Post | null = null;
  @Local postBookmarkMutatingPostId: number = 0;
  @Local postLikeMutatingPostId: number = 0;
  @Local postLikeUiVersion: number = 0;
  @Local postReactionUiVersion: number = 0;
  @Local animatedLikePostId: number = 0;
  @Local likeButtonScale: number = 1;
  @Local reactionPickerPostId: number = 0;
  @Local reactionPickerLoading: boolean = false;
  @Local reactionPickerOptions: string[] = [];
  @Local reactionPickerPanelX: number = 0;
  @Local reactionPickerPanelY: number = 0;
  @Local reactionPickerPanelScale: number = 0.9;
  @Local reactionPickerPanelOpacity: number = 0;
  @Local reactionPickerPanelTranslateY: number = 8;
  @Local reactionPickerOpenBelow: boolean = false;
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
  private scrollSyncTimerId: number = -1;
  private bottomBarShowTimerId: number = -1;
  private didScrollToInitial: boolean = false;
  private streamIndexMap: Map<number, number> = new Map();
  private readLaterListener: (() => void) | null = null;

  // 话题内搜索模式
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
  @Local holdingHandStatus: HoldingHandState = HoldingHandState.UNKNOWN_STATUS;

  private timeTickTimerId: number = -1;
  private shareImageRequestId: number = 0;
  private shareImageLastScheduledRequestId: number = -1;
  private shareImagePngBuffer: ArrayBuffer | null = null;
  private highlightTimerId: number = -1;
  private likeAnimationTimerId: number = -1;
  private pendingHighlightPostNumber: number = 0;
  private pendingHighlightListIndex: number = -1;
  private lastVisibleStartIndex: number = 0;
  private lastVisibleEndIndex: number = 0;
  private pendingReplyScrollPostNumber: number = 0;
  private postLikeStateOverrides: Map<number, boolean> = new Map();
  private postLikeCountOverrides: Map<number, number> = new Map();
  private postReactionOverrides: Map<number, PostReactionState> = new Map();
  private postReactionLastActionAtMap: Map<number, number> = new Map();
  private postReactionCooldownUntilMap: Map<number, number> = new Map();
  private postReactionSectionAreaMap: Map<number, ReactionPickerAnchorRect> = new Map();
  private reactionPickerRootX: number = 0;
  private reactionPickerRootY: number = 0;
  private reactionPickerRootWidth: number = 0;
  private reactionPickerRootHeight: number = 0;
  private reactionPickerAnimationTimerId: number = -1;
  private reactionPickerAnimationToken: number = 0;

  // MessageBus：话题频道（实时新回复）
  private topicChannelKey: string = '';
  private reactionsChannelKey: string = '';
  private topicChannelCallback: ((message: MessageBusMessage) => void) | null = null;
  private reactionsChannelCallback: ((message: MessageBusMessage) => void) | null = null;
  private authStateListener: (() => void) | null = null;
  private holdingHandListener: ((status: HoldingHandState) => void) | null = null;
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
    this.attachHoldingHandListener();
    this.attachReadLaterListener();
    this.initAuthState();
    this.syncReadLaterState().catch(() => {
    });
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
    this.closeReactionPicker();
    this.clearScrollSyncTimer();
    this.clearBottomBarShowTimer();
    this.clearReactionPickerAnimationTimer();
    this.clearHighlightTimer();
    this.clearLikeAnimationTimer();
    this.detachTopicChannel();
    this.detachAuthStateListener();
    this.detachHoldingHandListener();
    this.detachReadLaterListener();
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

  private attachHoldingHandListener(): void {
    if (this.holdingHandListener !== null) {
      return;
    }
    const service: HoldingHandService = HoldingHandService.getInstance();
    this.holdingHandStatus = service.getStatus();
    this.holdingHandListener = (status: HoldingHandState) => {
      this.holdingHandStatus = status;
    };
    service.addListener(this.holdingHandListener);
  }

  private detachHoldingHandListener(): void {
    if (this.holdingHandListener === null) {
      return;
    }
    HoldingHandService.getInstance().removeListener(this.holdingHandListener);
    this.holdingHandListener = null;
  }

  private attachReadLaterListener(): void {
    if (this.readLaterListener !== null) {
      return;
    }
    this.readLaterListener = () => {
      this.syncReadLaterState().catch(() => {
      });
    };
    ReadLaterService.getInstance().addListener(this.readLaterListener);
  }

  private detachReadLaterListener(): void {
    if (this.readLaterListener === null) {
      return;
    }
    ReadLaterService.getInstance().removeListener(this.readLaterListener);
    this.readLaterListener = null;
  }

  private async syncReadLaterState(): Promise<void> {
    this.isInReadLater = await ReadLaterService.getInstance().hasTopic(this.topicId);
  }

  private getReadLaterMenuLabel(): string {
    return this.isInReadLater ? '移出浮窗' : '加入浮窗';
  }

  private getReadLaterTitle(): string {
    const title: string = this.topicTitle.trim();
    if (title.length > 0) {
      return title;
    }
    return `话题 #${this.topicId}`;
  }

  private getReadLaterPostNumber(): number {
    return this.currentPostIndex > 1 ? this.currentPostIndex : 0;
  }

  private async handleReadLaterAction(): Promise<void> {
    const service: ReadLaterService = ReadLaterService.getInstance();
    if (this.isInReadLater) {
      await service.remove(this.topicId);
      this.isInReadLater = false;
      ToastService.show('已从浮窗移除');
      return;
    }

    const added: boolean = await service.addOrUpdate(this.topicId, this.getReadLaterTitle(), this.getReadLaterPostNumber());
    if (!added) {
      ToastService.show(`浮窗已满（最多 ${MAX_READ_LATER_ITEMS} 个）`);
      return;
    }
    this.isInReadLater = true;
    ToastService.show('已加入浮窗');
  }

  private closeTopicNotificationSheet(): void {
    this.isTopicNotificationSheetVisible = false;
  }

  private openTopicNotificationSheet(): void {
    if (this.isGuestMode) {
      ToastService.showLoginRequired();
      return;
    }
    this.isTopicNotificationSheetVisible = true;
  }

  private getTopicNotificationLevelDescription(level: number): string {
    if (level <= 0) {
      return '不再接收这个话题的提醒';
    }
    if (level === 1) {
      return '仅在通知页中正常显示';
    }
    if (level === 2) {
      return '显示未读计数，但不会强提醒';
    }
    return '有人回复时优先提醒你';
  }

  private async updateTopicNotificationLevel(level: number): Promise<void> {
    if (this.isTopicNotificationMutating) {
      return;
    }
    const loggedIn: boolean = await this.ensureLoggedInForAction();
    if (!loggedIn) {
      ToastService.showLoginRequired();
      return;
    }
    if (this.topicId <= 0) {
      ToastService.show('无效的话题');
      return;
    }

    const nextLevel: number = Math.max(0, Math.min(3, Math.round(level)));
    const previousLevel: number = this.notificationLevel;
    const previousLabel: string = this.notificationLevelLabel;
    this.notificationLevel = nextLevel;
    this.notificationLevelLabel = this.getNotificationLevelLabel(nextLevel);
    this.isTopicNotificationMutating = true;

    try {
      await ApiClient.getInstance().updateTopicNotificationLevel(this.topicId, nextLevel);
      this.isTopicNotificationSheetVisible = false;
      ToastService.show(`已设为${this.notificationLevelLabel}`);
    } catch (err) {
      this.notificationLevel = previousLevel;
      this.notificationLevelLabel = previousLabel;
      const message: string = ApiClient.formatError(err).replace('Error: ', '').trim();
      ToastService.show(message.length > 0 ? message : '订阅设置失败');
    } finally {
      this.isTopicNotificationMutating = false;
    }
  }

  private isReplyFabLeftAligned(): boolean {
    return this.holdingHandStatus === HoldingHandState.LEFT_HAND_HELD;
  }

  private getReplyFabPositionX(): string | number {
    return this.isReplyFabLeftAligned() ? 16 : '100%';
  }

  private getReplyFabTranslateX(): number {
    return this.isReplyFabLeftAligned() ? 0 : -72;
  }

  private getReplyFabTranslateY(): number {
    return -(56 + FAB_BOTTOM_MARGIN_VP + this.getDetailBottomBarReservedBottomVp());
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

  private async ensureLoggedInForAction(): Promise<boolean> {
    const auth: AuthService = AuthService.getInstance();
    try {
      await auth.init();
      const loggedIn: boolean = auth.getIsLoggedIn();
      this.isGuestMode = !loggedIn;
      return loggedIn;
    } catch (_) {
      this.isGuestMode = true;
      return false;
    }
  }

  private parseBookmarkIdValue(value: Object | null | undefined): number {
    if (value === undefined || value === null) {
      return 0;
    }
    const parsed: number = Number(value.toString());
    if (isNaN(parsed) || parsed <= 0) {
      return 0;
    }
    return parsed;
  }

  private parseBookmarkNameValue(value: Object | null | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    return value.toString().trim();
  }

  private parseBookmarkReminderValue(value: Object | null | undefined): Date | null {
    if (value === undefined || value === null) {
      return null;
    }
    const text: string = value.toString().trim();
    if (text.length === 0) {
      return null;
    }
    return TimeUtils.parseUtcTime(text);
  }

  private applyTopicBookmarkStateFromJson(json: Record<string, Object>): void {
    let nextBookmarked: boolean = false;
    let nextBookmarkId: number = this.parseBookmarkIdValue(json['bookmark_id']);
    let nextBookmarkName: string = this.parseBookmarkNameValue(json['_bookmark_name']);
    let nextBookmarkReminderAt: Date | null = this.parseBookmarkReminderValue(json['_bookmark_reminder_at']);
    const topLevelBookmarkableType: string = this.parseBookmarkNameValue(json['bookmarkable_type']);
    if (nextBookmarkId > 0 && topLevelBookmarkableType !== 'Post') {
      nextBookmarked = true;
    }

    let hasBookmarksArray: boolean = false;
    let foundTopicBookmark: boolean = false;
    const bookmarksVal = json['bookmarks'];
    if (bookmarksVal !== undefined && bookmarksVal !== null && Array.isArray(bookmarksVal)) {
      hasBookmarksArray = true;
      const bookmarksArray: Object[] = bookmarksVal as Object[];
      for (let i = 0; i < bookmarksArray.length; i++) {
        const item: Object = bookmarksArray[i];
        if (item === undefined || item === null || typeof item !== 'object') {
          continue;
        }
        const bookmarkObj: Record<string, Object> = item as Record<string, Object>;
        const typeText: string = this.parseBookmarkNameValue(bookmarkObj['bookmarkable_type']);
        if (typeText !== 'Topic') {
          continue;
        }
        foundTopicBookmark = true;
        nextBookmarked = true;
        nextBookmarkId = this.parseBookmarkIdValue(bookmarkObj['id']);
        nextBookmarkName = this.parseBookmarkNameValue(bookmarkObj['name']);
        nextBookmarkReminderAt = this.parseBookmarkReminderValue(bookmarkObj['reminder_at']);
        break;
      }
    }

    if ((hasBookmarksArray && !foundTopicBookmark) || !nextBookmarked) {
      nextBookmarkId = 0;
      nextBookmarkName = '';
      nextBookmarkReminderAt = null;
    }

    this.isBookmarked = nextBookmarked;
    this.topicBookmarkId = nextBookmarkId;
    this.topicBookmarkName = nextBookmarkName;
    this.topicBookmarkReminderAt = nextBookmarkReminderAt;
  }

  private applyPostBookmarkStatesFromJson(json: Record<string, Object>, posts: Post[]): void {
    if (posts.length === 0) {
      return;
    }
    const bookmarksVal = json['bookmarks'];
    if (bookmarksVal === undefined || bookmarksVal === null || !Array.isArray(bookmarksVal)) {
      return;
    }
    const postIndexMap: Map<number, number> = new Map();
    for (let i = 0; i < posts.length; i++) {
      postIndexMap.set(posts[i].id, i);
    }
    const bookmarksArray: Object[] = bookmarksVal as Object[];
    for (let i = 0; i < bookmarksArray.length; i++) {
      const item: Object = bookmarksArray[i];
      if (item === undefined || item === null || typeof item !== 'object') {
        continue;
      }
      const bookmarkObj: Record<string, Object> = item as Record<string, Object>;
      const typeText: string = this.parseBookmarkNameValue(bookmarkObj['bookmarkable_type']);
      if (typeText !== 'Post') {
        continue;
      }
      const bookmarkableId: number = this.parseBookmarkIdValue(bookmarkObj['bookmarkable_id']);
      if (bookmarkableId <= 0 || !postIndexMap.has(bookmarkableId)) {
        continue;
      }
      const post: Post = posts[postIndexMap.get(bookmarkableId) as number];
      const bookmarkId: number = this.parseBookmarkIdValue(bookmarkObj['id']);
      const bookmarkName: string = this.parseBookmarkNameValue(bookmarkObj['name']);
      post.bookmarked = true;
      post.bookmarkId = bookmarkId > 0 ? bookmarkId : null;
      post.bookmarkName = bookmarkName.length > 0 ? bookmarkName : null;
      post.bookmarkReminderAt = this.parseBookmarkReminderValue(bookmarkObj['reminder_at']);
    }
  }

  private openTopicBookmarkSheet(): void {
    if (this.topicBookmarkId <= 0) {
      return;
    }
    this.isBookmarkSheetVisible = true;
  }

  private closeTopicBookmarkSheet(): void {
    this.isBookmarkSheetVisible = false;
  }

  private openPostBookmarkSheet(post: Post): void {
    if (post.bookmarkId === null || (post.bookmarkId as number) <= 0) {
      return;
    }
    this.editingPostBookmarkPost = post;
    this.isPostBookmarkSheetVisible = true;
  }

  private closePostBookmarkSheet(): void {
    this.isPostBookmarkSheetVisible = false;
  }

  private clearTopicBookmarkState(): void {
    this.isBookmarked = false;
    this.topicBookmarkId = 0;
    this.topicBookmarkName = '';
    this.topicBookmarkReminderAt = null;
  }

  private applyTopicBookmarkUpdate(name: string | null, reminderAt: Date | null, clearReminderAt: boolean): void {
    this.isBookmarked = this.topicBookmarkId > 0;
    this.topicBookmarkName = name !== null ? name : '';
    this.topicBookmarkReminderAt = clearReminderAt ? null : reminderAt;
  }

  private isPostBookmarkMutating(postId: number): boolean {
    return postId > 0 && this.postBookmarkMutatingPostId === postId;
  }

  private isPostLikeMutating(postId: number): boolean {
    return postId > 0 && this.postLikeMutatingPostId === postId;
  }

  private getPostReactionCooldownRemainingSeconds(postId: number): number {
    if (postId <= 0) {
      return 0;
    }
    const cooldownUntil: number = this.postReactionCooldownUntilMap.get(postId) ?? 0;
    if (cooldownUntil <= 0) {
      return 0;
    }
    const remainingMs: number = cooldownUntil - Date.now();
    if (remainingMs <= 0) {
      this.postReactionCooldownUntilMap.delete(postId);
      return 0;
    }
    return Math.max(1, Math.ceil(remainingMs / 1000));
  }

  private setPostReactionCooldown(postId: number, seconds: number): void {
    if (postId <= 0 || seconds <= 0) {
      return;
    }
    this.postReactionCooldownUntilMap.set(postId, Date.now() + seconds * 1000);
  }

  private markPostReactionAction(postId: number): void {
    if (postId <= 0) {
      return;
    }
    this.postReactionLastActionAtMap.set(postId, Date.now());
  }

  private shouldThrottlePostReactionAction(postId: number): boolean {
    if (postId <= 0) {
      return false;
    }
    const cooldownSeconds: number = this.getPostReactionCooldownRemainingSeconds(postId);
    if (cooldownSeconds > 0) {
      ToastService.show(`操作过快，请${cooldownSeconds}秒后再试`);
      return true;
    }
    const lastActionAt: number = this.postReactionLastActionAtMap.get(postId) ?? 0;
    if (lastActionAt > 0 && Date.now() - lastActionAt < POST_REACTION_MIN_INTERVAL_MS) {
      ToastService.show('操作过快，请稍后再试');
      return true;
    }
    return false;
  }

  private clearReactionPickerAnimationTimer(): void {
    if (this.reactionPickerAnimationTimerId >= 0) {
      clearTimeout(this.reactionPickerAnimationTimerId);
      this.reactionPickerAnimationTimerId = -1;
    }
  }

  private resetReactionPickerVisualState(): void {
    this.reactionPickerPanelScale = 0.9;
    this.reactionPickerPanelOpacity = 0;
    this.reactionPickerPanelTranslateY = this.reactionPickerOpenBelow ? -8 : 8;
  }

  private parseSafeNumber(value: Object | null | undefined): number {
    if (value === undefined || value === null) {
      return 0;
    }
    const parsed: number = Number(value.toString());
    return isNaN(parsed) ? 0 : parsed;
  }

  private readAreaPositionValue(area: Area, key: string): number {
    if (key === 'x') {
      const globalX: number = this.parseSafeNumber(area.globalPosition.x);
      return globalX !== 0 ? globalX : this.parseSafeNumber(area.position.x);
    }
    if (key === 'y') {
      const globalY: number = this.parseSafeNumber(area.globalPosition.y);
      return globalY !== 0 ? globalY : this.parseSafeNumber(area.position.y);
    }
    return 0;
  }

  private updateReactionPickerRootArea(area: Area): void {
    this.reactionPickerRootX = this.readAreaPositionValue(area, 'x');
    this.reactionPickerRootY = this.readAreaPositionValue(area, 'y');
    this.reactionPickerRootWidth = this.parseSafeNumber(area.width);
    this.reactionPickerRootHeight = this.parseSafeNumber(area.height);
    if (this.reactionPickerPostId > 0) {
      this.layoutReactionPicker(this.reactionPickerPostId);
    }
  }

  private updatePostReactionSectionArea(postId: number, area: Area): void {
    if (postId <= 0) {
      return;
    }
    const nextRect: ReactionPickerAnchorRect = new ReactionPickerAnchorRect();
    nextRect.x = this.readAreaPositionValue(area, 'x');
    nextRect.y = this.readAreaPositionValue(area, 'y');
    nextRect.width = this.parseSafeNumber(area.width);
    nextRect.height = this.parseSafeNumber(area.height);
    this.postReactionSectionAreaMap.set(postId, nextRect);
    if (this.isReactionPickerVisible(postId)) {
      this.layoutReactionPicker(postId);
    }
  }

  private getReactionPickerAnchorRect(postId: number): ReactionPickerAnchorRect | null {
    if (postId <= 0 || !this.postReactionSectionAreaMap.has(postId)) {
      return null;
    }
    const source: ReactionPickerAnchorRect = this.postReactionSectionAreaMap.get(postId) as ReactionPickerAnchorRect;
    const nextRect: ReactionPickerAnchorRect = new ReactionPickerAnchorRect();
    nextRect.x = source.x;
    nextRect.y = source.y;
    nextRect.width = source.width;
    nextRect.height = source.height;
    return nextRect;
  }

  private layoutReactionPicker(postId: number): void {
    const panelWidth: number = this.getPostReactionPickerPanelWidth();
    const panelHeight: number = this.getPostReactionPickerPanelHeight();
    const viewportWidth: number = this.reactionPickerRootWidth > 0 ? this.reactionPickerRootWidth : 360;
    const viewportHeight: number = this.reactionPickerRootHeight > 0 ? this.reactionPickerRootHeight : 640;
    const safeTop: number = WindowManager.getSystemAvoidAreaTopVp() + POST_REACTION_PICKER_SCREEN_MARGIN;
    const safeBottom: number = viewportHeight - POST_REACTION_PICKER_SCREEN_MARGIN;
    const anchorRect: ReactionPickerAnchorRect | null = this.getReactionPickerAnchorRect(postId);

    let anchorCenterX: number = viewportWidth - POST_REACTION_PICKER_SCREEN_MARGIN - 24;
    let anchorCenterY: number = viewportHeight - 120;
    if (anchorRect !== null) {
      anchorCenterX = anchorRect.x - this.reactionPickerRootX + Math.max(0, anchorRect.width) - 20;
      anchorCenterY = anchorRect.y - this.reactionPickerRootY + Math.max(0, anchorRect.height) / 2;
    }

    let left: number = anchorCenterX - panelWidth / 2;
    left = Math.max(POST_REACTION_PICKER_SCREEN_MARGIN, Math.min(left, viewportWidth - panelWidth - POST_REACTION_PICKER_SCREEN_MARGIN));

    let top: number = anchorCenterY - panelHeight - POST_REACTION_PICKER_EDGE_GAP;
    let openBelow: boolean = false;
    if (top < safeTop) {
      top = anchorCenterY + POST_REACTION_PICKER_EDGE_GAP;
      openBelow = true;
    }
    if (top + panelHeight > safeBottom) {
      top = Math.max(safeTop, safeBottom - panelHeight);
    }

    this.reactionPickerPanelX = left;
    this.reactionPickerPanelY = top;
    this.reactionPickerOpenBelow = openBelow;
  }

  private animateReactionPickerIn(): void {
    this.clearReactionPickerAnimationTimer();
    this.reactionPickerAnimationToken = this.reactionPickerAnimationToken + 1;
    const currentToken: number = this.reactionPickerAnimationToken;
    this.reactionPickerPanelOpacity = 0;
    this.reactionPickerPanelScale = 0.86;
    this.reactionPickerPanelTranslateY = this.reactionPickerOpenBelow ? -8 : 8;

    const uiContext = this.getUIContext();
    if (uiContext !== undefined && uiContext !== null) {
      uiContext.animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.reactionPickerPanelOpacity = 1;
        this.reactionPickerPanelScale = 1.05;
        this.reactionPickerPanelTranslateY = 0;
      });
      this.reactionPickerAnimationTimerId = setTimeout(() => {
        if (currentToken !== this.reactionPickerAnimationToken || this.reactionPickerPostId <= 0) {
          this.reactionPickerAnimationTimerId = -1;
          return;
        }
        const nextContext = this.getUIContext();
        if (nextContext !== undefined && nextContext !== null) {
          nextContext.animateTo({ duration: 125, curve: Curve.EaseOut }, () => {
            this.reactionPickerPanelScale = 1;
          });
        } else {
          this.reactionPickerPanelScale = 1;
        }
        this.reactionPickerAnimationTimerId = -1;
      }, 185) as number;
      return;
    }

    this.reactionPickerPanelOpacity = 1;
    this.reactionPickerPanelScale = 1;
    this.reactionPickerPanelTranslateY = 0;
  }

  private dismissReactionPicker(animated: boolean = true): void {
    if (this.reactionPickerPostId <= 0) {
      this.closeReactionPicker();
      return;
    }
    if (!animated) {
      this.closeReactionPicker();
      return;
    }

    this.clearReactionPickerAnimationTimer();
    this.reactionPickerAnimationToken = this.reactionPickerAnimationToken + 1;
    const currentToken: number = this.reactionPickerAnimationToken;
    const closingPostId: number = this.reactionPickerPostId;
    const exitTranslateY: number = this.reactionPickerOpenBelow ? -6 : 6;
    const uiContext = this.getUIContext();
    if (uiContext !== undefined && uiContext !== null) {
      uiContext.animateTo({ duration: 120, curve: Curve.EaseInOut }, () => {
        this.reactionPickerPanelOpacity = 0;
        this.reactionPickerPanelScale = 0.92;
        this.reactionPickerPanelTranslateY = exitTranslateY;
      });
    } else {
      this.reactionPickerPanelOpacity = 0;
      this.reactionPickerPanelScale = 0.92;
      this.reactionPickerPanelTranslateY = exitTranslateY;
    }
    this.reactionPickerAnimationTimerId = setTimeout(() => {
      if (currentToken === this.reactionPickerAnimationToken && this.reactionPickerPostId === closingPostId) {
        this.closeReactionPicker();
      }
      this.reactionPickerAnimationTimerId = -1;
    }, 125) as number;
  }

  private findPostById(postId: number): Post | null {
    if (postId <= 0) {
      return null;
    }
    for (let i = 0; i < this.posts.length; i++) {
      if (this.posts[i].id === postId) {
        return this.posts[i];
      }
    }
    for (let i = 0; i < this.expandedReplies.length; i++) {
      if (this.expandedReplies[i].id === postId) {
        return this.expandedReplies[i];
      }
    }
    return null;
  }

  private getPostLikeButtonScale(postId: number): number {
    return this.animatedLikePostId === postId ? this.likeButtonScale : 1;
  }

  private clearLikeAnimationTimer(): void {
    if (this.likeAnimationTimerId >= 0) {
      clearTimeout(this.likeAnimationTimerId);
      this.likeAnimationTimerId = -1;
    }
  }

  private clearPostLikeOverrides(): void {
    this.postLikeStateOverrides.clear();
    this.postLikeCountOverrides.clear();
    this.postLikeUiVersion = this.postLikeUiVersion + 1;
  }

  private clearPostReactionOverrides(): void {
    this.postReactionOverrides.clear();
    this.postReactionUiVersion = this.postReactionUiVersion + 1;
  }

  private isReactionPickerVisible(postId: number): boolean {
    return postId > 0 && this.reactionPickerPostId === postId;
  }

  private closeReactionPicker(): void {
    this.clearReactionPickerAnimationTimer();
    this.reactionPickerPostId = 0;
    this.reactionPickerLoading = false;
    this.reactionPickerOptions = [];
    this.resetReactionPickerVisualState();
  }

  private normalizeReactionId(reactionId: string | null | undefined): string {
    const normalized: string = reactionId !== undefined && reactionId !== null ? reactionId.toString().trim().toLowerCase() : '';
    if (normalized === 'thumbsup' || normalized === 'thumbs_up') {
      return '+1';
    }
    return normalized;
  }

  private isHeartReactionId(reactionId: string | null | undefined): boolean {
    return this.normalizeReactionId(reactionId) === 'heart';
  }

  private createPostReaction(reactionId: string, count: number = 0, type: string = 'emoji'): PostReaction {
    const reaction: PostReaction = new PostReaction();
    reaction.id = this.normalizeReactionId(reactionId);
    reaction.type = type !== undefined && type !== null && type.toString().trim().length > 0 ? type.toString().trim() : 'emoji';
    reaction.count = Math.max(0, Math.round(count));
    return reaction;
  }

  private getReactionCountById(reactions: PostReaction[], reactionId: string): number {
    const targetId: string = this.normalizeReactionId(reactionId);
    if (targetId.length === 0 || reactions.length === 0) {
      return 0;
    }
    for (let i = 0; i < reactions.length; i++) {
      if (this.normalizeReactionId(reactions[i].id) === targetId) {
        return Math.max(0, reactions[i].count);
      }
    }
    return 0;
  }

  private getReactionIconUrl(reactionId: string): string {
    const normalized: string = this.normalizeReactionId(reactionId);
    if (normalized.length === 0) {
      return '';
    }
    return EmojiResolver.resolveEmojiUrl(`:${normalized}:`);
  }

  private getReactionFallbackText(reactionId: string): string {
    const normalized: string = this.normalizeReactionId(reactionId);
    if (normalized === 'heart') return '❤️';
    if (normalized === 'thumbsup' || normalized === '+1') return '👍';
    if (normalized === 'laughing') return '😆';
    if (normalized === 'joy') return '😂';
    if (normalized === 'open_mouth') return '😮';
    if (normalized === 'clap') return '👏';
    if (normalized === 'cry') return '😢';
    if (normalized === 'angry') return '😠';
    if (normalized === 'rocket') return '🚀';
    if (normalized === 'fire') return '🔥';
    if (normalized === 'eyes') return '👀';
    if (normalized === 'thinking_face') return '🤔';
    return normalized.length > 0 ? `:${normalized}:` : '';
  }

  private buildPostReactionStateFromPost(post: Post): PostReactionState {
    const state: PostReactionState = new PostReactionState();
    const sourceReactions: PostReaction[] = PostReaction.cloneList(post.reactions);
    for (let i = 0; i < sourceReactions.length; i++) {
      const reaction: PostReaction = sourceReactions[i];
      reaction.id = this.normalizeReactionId(reaction.id);
      if (reaction.id.length === 0 || reaction.count <= 0) {
        continue;
      }
      state.reactions.push(reaction);
    }

    const currentReaction: PostReaction | null = PostReaction.cloneValue(post.currentUserReaction);
    if (currentReaction !== null) {
      currentReaction.id = this.normalizeReactionId(currentReaction.id);
      if (currentReaction.id.length > 0) {
        state.currentUserReaction = currentReaction;
      }
    }

    if (state.currentUserReaction === null && post.liked) {
      const heartCount: number = Math.max(1, Math.max(post.likeCount, this.getReactionCountById(state.reactions, 'heart')));
      state.currentUserReaction = this.createPostReaction('heart', heartCount);
    }

    if (state.reactions.length === 0) {
      const fallbackHeartCount: number = Math.max(post.likeCount, state.currentUserReaction !== null && this.isHeartReactionId((state.currentUserReaction as PostReaction).id) ? 1 : 0);
      if (fallbackHeartCount > 0) {
        state.reactions.push(this.createPostReaction('heart', fallbackHeartCount));
      }
    }

    if (state.currentUserReaction !== null) {
      const currentId: string = this.normalizeReactionId((state.currentUserReaction as PostReaction).id);
      let matched: boolean = false;
      for (let i = 0; i < state.reactions.length; i++) {
        if (this.normalizeReactionId(state.reactions[i].id) === currentId) {
          matched = true;
          if (state.reactions[i].count <= 0) {
            state.reactions[i].count = 1;
          }
          break;
        }
      }
      if (!matched) {
        const fallbackCount: number = Math.max(1, (state.currentUserReaction as PostReaction).count);
        state.reactions.push(this.createPostReaction(currentId, fallbackCount, (state.currentUserReaction as PostReaction).type));
      }
    }

    return state;
  }

  private getResolvedPostReactionState(post: Post): PostReactionState {
    const trackedVersion: number = this.postReactionUiVersion;
    if (trackedVersion < 0) {
      return this.buildPostReactionStateFromPost(post);
    }
    if (post.id > 0 && this.postReactionOverrides.has(post.id)) {
      return PostReactionState.cloneState(this.postReactionOverrides.get(post.id) as PostReactionState);
    }
    return this.buildPostReactionStateFromPost(post);
  }

  private getResolvedPostReactions(post: Post): PostReaction[] {
    return this.getResolvedPostReactionState(post).reactions;
  }

  private getResolvedCurrentUserReaction(post: Post): PostReaction | null {
    return this.getResolvedPostReactionState(post).currentUserReaction;
  }

  private getResolvedPostReactionTotalCount(post: Post): number {
    const reactions: PostReaction[] = this.getResolvedPostReactions(post);
    let total: number = 0;
    for (let i = 0; i < reactions.length; i++) {
      total += Math.max(0, reactions[i].count);
    }
    return total;
  }

  private isHeartOnlyReaction(reactions: PostReaction[]): boolean {
    let visibleCount: number = 0;
    let hasHeart: boolean = false;
    for (let i = 0; i < reactions.length; i++) {
      if (reactions[i].count <= 0) {
        continue;
      }
      visibleCount = visibleCount + 1;
      if (this.isHeartReactionId(reactions[i].id)) {
        hasHeart = true;
      }
    }
    return visibleCount === 1 && hasHeart;
  }

  private getReactionSummaryReactions(post: Post): PostReaction[] {
    const reactions: PostReaction[] = this.getResolvedPostReactions(post);
    if (this.isHeartOnlyReaction(reactions)) {
      return [];
    }
    const out: PostReaction[] = [];
    for (let i = 0; i < reactions.length; i++) {
      if (reactions[i].count <= 0) {
        continue;
      }
      out.push(reactions[i]);
      if (out.length >= 3) {
        break;
      }
    }
    return out;
  }

  private getPostReactionCountText(post: Post): string {
    const total: number = this.getResolvedPostReactionTotalCount(post);
    return total > 0 ? this.formatPostActionCount(total) : '';
  }

  private getPostReactionPickerMaxColumns(): number {
    return 5;
  }

  private getPostReactionPickerItemSize(): number {
    return 40;
  }

  private getPostReactionPickerItemGap(): number {
    return 1;
  }

  private getPostReactionPickerPanelPadding(): number {
    return 4;
  }

  private estimateInlineTextWidth(text: string, fontSize: number = 12): number {
    const safeText: string = text !== undefined && text !== null ? text.toString() : '';
    if (safeText.length === 0) {
      return fontSize;
    }
    return Math.max(fontSize, Math.round(safeText.length * fontSize * 0.72));
  }

  private getReactionPickerOptionCount(): number {
    if (this.reactionPickerOptions.length > 0) {
      return this.reactionPickerOptions.length;
    }
    return PreloadedDataService.getInstance().getEnabledReactions().length;
  }

  private getPostReactionPickerColumnCount(): number {
    const optionCount: number = this.getReactionPickerOptionCount();
    if (optionCount <= 0) {
      return 1;
    }
    return Math.min(this.getPostReactionPickerMaxColumns(), optionCount);
  }

  private getPostReactionPickerRowCount(): number {
    const optionCount: number = this.getReactionPickerOptionCount();
    if (optionCount <= 0) {
      return 1;
    }
    return Math.max(1, Math.ceil(optionCount / this.getPostReactionPickerMaxColumns()));
  }

  private getPostReactionPickerPanelWidth(): number {
    const columns: number = this.getPostReactionPickerColumnCount();
    const itemSize: number = this.getPostReactionPickerItemSize();
    const gap: number = this.getPostReactionPickerItemGap();
    const padding: number = this.getPostReactionPickerPanelPadding();
    return columns * itemSize + Math.max(0, columns - 1) * gap + padding * 2;
  }

  private getPostReactionPickerPanelHeight(): number {
    const rows: number = this.getPostReactionPickerRowCount();
    const itemSize: number = this.getPostReactionPickerItemSize();
    const gap: number = this.getPostReactionPickerItemGap();
    const padding: number = this.getPostReactionPickerPanelPadding();
    return rows * itemSize + Math.max(0, rows - 1) * gap + padding * 2;
  }

  private shouldShowPostReactionSummary(post: Post): boolean {
    return this.getResolvedPostReactionTotalCount(post) > 0;
  }

  private isCurrentPostReaction(post: Post, reactionId: string): boolean {
    const currentReaction: PostReaction | null = this.getResolvedCurrentUserReaction(post);
    return currentReaction !== null
      && this.normalizeReactionId((currentReaction as PostReaction).id) === this.normalizeReactionId(reactionId);
  }

  private getPostReactionBarWidth(post: Post): number {
    if (!this.shouldShowPostReactionSummary(post)) {
      return 44;
    }

    const summaryReactions: PostReaction[] = this.getReactionSummaryReactions(post);
    const textWidth: number = this.estimateInlineTextWidth(this.getPostReactionCountText(post), 12);
    let summaryIconsWidth: number = 0;
    if (summaryReactions.length > 0) {
      summaryIconsWidth = summaryReactions.length * 18 + Math.max(0, summaryReactions.length - 1) * 3 + 6;
    }

    const summaryWidth: number = 12 + summaryIconsWidth + textWidth + 8;
    return summaryWidth + 40;
  }

  private getPostReactionPickerPositionX(post: Post): number {
    const buttonCenterX: number = this.getPostReactionBarWidth(post) - 22;
    return buttonCenterX - this.getPostReactionPickerPanelWidth() / 2;
  }

  private getPostReactionPickerPositionY(): number {
    return -(this.getPostReactionPickerPanelHeight() + 4);
  }

  private applyPostReactionOverride(postId: number, state: PostReactionState): void {
    if (postId <= 0) {
      return;
    }
    this.postReactionOverrides.set(postId, PostReactionState.cloneState(state));
    this.postReactionUiVersion = this.postReactionUiVersion + 1;
  }

  private updatePostReactionState(postId: number, state: PostReactionState): void {
    if (postId <= 0) {
      return;
    }
    const nextState: PostReactionState = PostReactionState.cloneState(state);
    const nextCurrentReaction: PostReaction | null = PostReaction.cloneValue(nextState.currentUserReaction);
    const nextReactions: PostReaction[] = PostReaction.cloneList(nextState.reactions);
    const nextHeartCount: number = this.getReactionCountById(nextReactions, 'heart');

    const applyUpdate = (source: Post[]): Post[] => {
      if (source.length === 0) {
        return source;
      }
      let changed: boolean = false;
      const next: Post[] = [];
      for (let i = 0; i < source.length; i++) {
        const current: Post = source[i];
        if (current.id === postId) {
          const updatedPost: Post = this.clonePost(current);
          updatedPost.reactions = nextReactions.length > 0 ? PostReaction.cloneList(nextReactions) : null;
          updatedPost.currentUserReaction = PostReaction.cloneValue(nextCurrentReaction);
          updatedPost.liked = nextCurrentReaction !== null && this.isHeartReactionId((nextCurrentReaction as PostReaction).id);
          updatedPost.likeCount = nextHeartCount;
          next.push(updatedPost);
          changed = true;
          continue;
        }
        next.push(current);
      }
      return changed ? next : source;
    };

    this.posts = applyUpdate(this.posts);
    this.expandedReplies = applyUpdate(this.expandedReplies);
  }

  private buildNextReactionState(previousState: PostReactionState, reactionId: string): PostReactionState {
    const targetReactionId: string = this.normalizeReactionId(reactionId);
    const nextState: PostReactionState = PostReactionState.cloneState(previousState);
    if (targetReactionId.length === 0) {
      return nextState;
    }

    const currentReaction: PostReaction | null = PostReaction.cloneValue(nextState.currentUserReaction);
    const currentReactionId: string = currentReaction !== null ? this.normalizeReactionId((currentReaction as PostReaction).id) : '';
    if (currentReactionId.length > 0) {
      for (let i = nextState.reactions.length - 1; i >= 0; i--) {
        if (this.normalizeReactionId(nextState.reactions[i].id) !== currentReactionId) {
          continue;
        }
        nextState.reactions[i].count = Math.max(0, nextState.reactions[i].count - 1);
        if (nextState.reactions[i].count <= 0) {
          nextState.reactions.splice(i, 1);
        }
        break;
      }
      nextState.currentUserReaction = null;
      if (currentReactionId === targetReactionId) {
        return nextState;
      }
    }

    let targetIndex: number = -1;
    for (let i = 0; i < nextState.reactions.length; i++) {
      if (this.normalizeReactionId(nextState.reactions[i].id) === targetReactionId) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex >= 0) {
      nextState.reactions[targetIndex].count = Math.max(0, nextState.reactions[targetIndex].count) + 1;
      nextState.currentUserReaction = this.createPostReaction(
        nextState.reactions[targetIndex].id,
        nextState.reactions[targetIndex].count,
        nextState.reactions[targetIndex].type
      );
      return nextState;
    }

    const addedReaction: PostReaction = this.createPostReaction(targetReactionId, 1);
    nextState.reactions.push(addedReaction);
    nextState.currentUserReaction = this.createPostReaction(addedReaction.id, addedReaction.count, addedReaction.type);
    return nextState;
  }

  private async showReactionPicker(post: Post): Promise<void> {
    if (post.id <= 0) {
      return;
    }
    const loggedIn: boolean = await this.ensureLoggedInForAction();
    if (!loggedIn) {
      ToastService.showLoginRequired();
      return;
    }
    if (this.isReactionPickerVisible(post.id) && !this.reactionPickerLoading) {
      this.dismissReactionPicker();
      return;
    }

    this.reactionPickerPostId = post.id;
    this.reactionPickerOptions = PreloadedDataService.getInstance().getEnabledReactions();
    this.reactionPickerLoading = this.reactionPickerOptions.length === 0;
    this.layoutReactionPicker(post.id);
    this.animateReactionPickerIn();

    try {
      await PreloadedDataService.getInstance().ensureConfigLoaded(true);
    } catch (_) {
    }

    if (!this.isReactionPickerVisible(post.id)) {
      return;
    }
    this.reactionPickerOptions = PreloadedDataService.getInstance().getEnabledReactions();
    this.reactionPickerLoading = false;
    this.layoutReactionPicker(post.id);
  }

  private async handlePostReactionAction(post: Post, reactionId: string = ''): Promise<void> {
    if (this.isPostLikeMutating(post.id)) {
      return;
    }
    const loggedIn: boolean = await this.ensureLoggedInForAction();
    if (!loggedIn) {
      ToastService.showLoginRequired();
      return;
    }
    if (post.id <= 0) {
      ToastService.show('无效的帖子');
      return;
    }
    if (this.shouldThrottlePostReactionAction(post.id)) {
      return;
    }
    this.markPostReactionAction(post.id);

    const previousState: PostReactionState = this.getResolvedPostReactionState(post);
    const previousCurrentReaction: PostReaction | null = previousState.currentUserReaction;
    let targetReactionId: string = this.normalizeReactionId(reactionId);
    if (targetReactionId.length === 0) {
      targetReactionId = previousCurrentReaction !== null
        ? this.normalizeReactionId((previousCurrentReaction as PostReaction).id)
        : 'heart';
    }
    if (targetReactionId.length === 0) {
      targetReactionId = 'heart';
    }

    const optimisticState: PostReactionState = this.buildNextReactionState(previousState, targetReactionId);
    this.postLikeMutatingPostId = post.id;
    this.closeReactionPicker();
    this.applyPostReactionOverride(post.id, optimisticState);
    this.updatePostReactionState(post.id, optimisticState);
    this.playPostLikeAnimation(post.id);

    try {
      const latestState: PostReactionState = await ApiClient.getInstance().toggleReaction(post.id, targetReactionId);
      this.applyPostReactionOverride(post.id, latestState);
      this.updatePostReactionState(post.id, latestState);
    } catch (err) {
      this.applyPostReactionOverride(post.id, previousState);
      this.updatePostReactionState(post.id, previousState);
      const message: string = ApiClient.formatError(err).replace('Error: ', '').trim();
      if (message.indexOf('HTTP 429') >= 0) {
        const retryAfterSeconds: number = ApiClient.extractRetryAfterSeconds(err, POST_REACTION_RATE_LIMIT_FALLBACK_SECONDS);
        this.setPostReactionCooldown(post.id, retryAfterSeconds);
        ToastService.show(`操作过快，请${retryAfterSeconds}秒后再试`);
      } else {
        ToastService.show(message.length > 0 && message !== 'Unknown error' ? message : '回应失败');
      }
    } finally {
      if (this.postLikeMutatingPostId === post.id) {
        this.postLikeMutatingPostId = 0;
      }
    }
  }

  private getResolvedPostLiked(post: Post): boolean {
    const trackedVersion: number = this.postLikeUiVersion;
    if (trackedVersion < 0) {
      return post.liked;
    }
    if (post.id > 0 && this.postLikeStateOverrides.has(post.id)) {
      return this.postLikeStateOverrides.get(post.id) as boolean;
    }
    return post.liked;
  }

  private getResolvedPostLikeCount(post: Post): number {
    const trackedVersion: number = this.postLikeUiVersion;
    if (trackedVersion < 0) {
      return Math.max(0, post.likeCount);
    }
    if (post.id > 0 && this.postLikeCountOverrides.has(post.id)) {
      return Math.max(0, this.postLikeCountOverrides.get(post.id) as number);
    }
    return Math.max(0, post.likeCount);
  }

  private applyPostLikeOverride(postId: number, liked: boolean, likeCount: number): void {
    if (postId <= 0) {
      return;
    }
    this.postLikeStateOverrides.set(postId, liked);
    this.postLikeCountOverrides.set(postId, Math.max(0, likeCount));
    this.postLikeUiVersion = this.postLikeUiVersion + 1;
  }

  private clonePost(source: Post): Post {
    const cloned: Post = new Post();
    cloned.id = source.id;
    cloned.name = source.name;
    cloned.username = source.username;
    cloned.avatarTemplate = source.avatarTemplate;
    cloned.animatedAvatar = source.animatedAvatar;
    cloned.cooked = source.cooked;
    cloned.postNumber = source.postNumber;
    cloned.postType = source.postType;
    cloned.updatedAt = source.updatedAt;
    cloned.createdAt = source.createdAt;
    cloned.likeCount = source.likeCount;
    cloned.replyCount = source.replyCount;
    cloned.replyToPostNumber = source.replyToPostNumber;
    cloned.replyToUser = source.replyToUser;
    cloned.bookmarked = source.bookmarked;
    cloned.bookmarkId = source.bookmarkId;
    cloned.bookmarkName = source.bookmarkName;
    cloned.bookmarkReminderAt = source.bookmarkReminderAt;
    cloned.read = source.read;
    cloned.canEdit = source.canEdit;
    cloned.canDelete = source.canDelete;
    cloned.flairUrl = source.flairUrl;
    cloned.flairName = source.flairName;
    cloned.flairBgColor = source.flairBgColor;
    cloned.flairColor = source.flairColor;
    cloned.primaryGroupName = source.primaryGroupName;
    cloned.groupModerator = source.groupModerator;
    cloned.acceptedAnswer = source.acceptedAnswer;
    cloned.deletedAt = source.deletedAt;
    cloned.userDeleted = source.userDeleted;
    cloned.userTitle = source.userTitle;
    cloned.userStatus = source.userStatus;
    cloned.userId = source.userId;
    cloned.moderator = source.moderator;
    cloned.admin = source.admin;
    cloned.badgesGranted = source.badgesGranted;
    cloned.hidden = source.hidden;
    cloned.liked = source.liked;
    cloned.reactions = PostReaction.cloneList(source.reactions);
    cloned.currentUserReaction = PostReaction.cloneValue(source.currentUserReaction);
    cloned.linkCounts = source.linkCounts;
    cloned.polls = source.polls;
    cloned.pollsVotes = source.pollsVotes;
    cloned.mentionedUsers = source.mentionedUsers;
    cloned.actionCode = source.actionCode;
    cloned.actionCodeWho = source.actionCodeWho;
    return cloned;
  }

  private formatPostActionCount(count: number): string {
    const safeCount: number = Math.max(0, count);
    if (safeCount >= 10000) {
      return `${(safeCount / 10000).toFixed(1)}w`;
    }
    if (safeCount >= 1000) {
      return `${(safeCount / 1000).toFixed(1)}k`;
    }
    return safeCount.toString();
  }

  private getPostLikeCountText(post: Post): string {
    const likeCount: number = this.getResolvedPostLikeCount(post);
    return likeCount > 0 ? this.formatPostActionCount(likeCount) : '';
  }

  private getPostBookmarkActionLabel(post: Post): string {
    if (this.isPostBookmarkMutating(post.id)) {
      return '处理中...';
    }
    if (post.bookmarked && post.bookmarkId !== null && (post.bookmarkId as number) > 0) {
      return '编辑书签';
    }
    return '添加书签';
  }

  private updatePostBookmarkState(
    postId: number,
    bookmarked: boolean,
    bookmarkId: number | null,
    bookmarkName: string | null,
    bookmarkReminderAt: Date | null
  ): void {
    if (postId <= 0) {
      return;
    }
    const applyUpdate = (source: Post[]): Post[] => {
      if (source.length === 0) {
        return source;
      }
      let changed: boolean = false;
      const next: Post[] = [];
      for (let i = 0; i < source.length; i++) {
        const current: Post = source[i];
        if (current.id === postId) {
          const updatedPost: Post = this.clonePost(current);
          updatedPost.bookmarked = bookmarked;
          updatedPost.bookmarkId = bookmarkId;
          updatedPost.bookmarkName = bookmarkName;
          updatedPost.bookmarkReminderAt = bookmarkReminderAt;
          next.push(updatedPost);
          changed = true;
          continue;
        }
        next.push(current);
      }
      return changed ? next : source;
    };

    this.posts = applyUpdate(this.posts);
    this.expandedReplies = applyUpdate(this.expandedReplies);

    if (this.editingPostBookmarkPost !== null && (this.editingPostBookmarkPost as Post).id === postId) {
      const editingPost: Post = this.clonePost(this.editingPostBookmarkPost as Post);
      editingPost.bookmarked = bookmarked;
      editingPost.bookmarkId = bookmarkId;
      editingPost.bookmarkName = bookmarkName;
      editingPost.bookmarkReminderAt = bookmarkReminderAt;
      this.editingPostBookmarkPost = editingPost;
    }
  }

  private clearPostBookmarkState(postId: number): void {
    this.updatePostBookmarkState(postId, false, null, null, null);
  }

  private updatePostLikeState(postId: number, liked: boolean): void {
    if (postId <= 0) {
      return;
    }
    const applyUpdate = (source: Post[]): Post[] => {
      if (source.length === 0) {
        return source;
      }
      let changed: boolean = false;
      const next: Post[] = [];
      for (let i = 0; i < source.length; i++) {
        const current: Post = source[i];
        if (current.id === postId) {
          const updatedPost: Post = this.clonePost(current);
          if (updatedPost.liked !== liked) {
            updatedPost.likeCount = Math.max(0, updatedPost.likeCount + (liked ? 1 : -1));
          }
          updatedPost.liked = liked;
          next.push(updatedPost);
          changed = true;
          continue;
        }
        next.push(current);
      }
      return changed ? next : source;
    };

    this.posts = applyUpdate(this.posts);
    this.expandedReplies = applyUpdate(this.expandedReplies);
  }

  private playPostLikeAnimation(postId: number): void {
    if (postId <= 0) {
      return;
    }
    this.clearLikeAnimationTimer();
    this.animatedLikePostId = postId;
    this.likeButtonScale = 0.92;

    const uiContext = this.getUIContext();
    if (uiContext !== undefined && uiContext !== null) {
      uiContext.animateTo({ duration: 110, curve: Curve.EaseOut }, () => {
        this.likeButtonScale = 1.12;
      });
      this.likeAnimationTimerId = setTimeout(() => {
        const nextContext = this.getUIContext();
        if (nextContext !== undefined && nextContext !== null) {
          nextContext.animateTo({ duration: 170, curve: Curve.EaseOut }, () => {
            this.likeButtonScale = 1;
          });
        } else {
          this.likeButtonScale = 1;
        }
        this.likeAnimationTimerId = setTimeout(() => {
          this.likeButtonScale = 1;
          this.animatedLikePostId = 0;
          this.likeAnimationTimerId = -1;
        }, 190) as number;
      }, 120) as number;
      return;
    }

    this.likeButtonScale = 1.08;
    this.likeAnimationTimerId = setTimeout(() => {
      this.likeButtonScale = 1;
      this.animatedLikePostId = 0;
      this.likeAnimationTimerId = -1;
    }, 180) as number;
  }

  private async handlePostLikeAction(post: Post): Promise<void> {
    if (this.isPostLikeMutating(post.id)) {
      return;
    }
    const loggedIn: boolean = await this.ensureLoggedInForAction();
    if (!loggedIn) {
      ToastService.showLoginRequired();
      return;
    }
    if (post.id <= 0) {
      ToastService.show('无效的帖子');
      return;
    }

    const previousLiked: boolean = this.getResolvedPostLiked(post);
    const previousCount: number = this.getResolvedPostLikeCount(post);
    const nextLiked: boolean = !previousLiked;
    const nextCount: number = Math.max(0, previousCount + (nextLiked ? 1 : -1));
    this.postLikeMutatingPostId = post.id;
    this.applyPostLikeOverride(post.id, nextLiked, nextCount);
    this.updatePostLikeState(post.id, nextLiked);
    this.playPostLikeAnimation(post.id);
    try {
      if (nextLiked) {
        await ApiClient.getInstance().likePost(post.id);
      } else {
        await ApiClient.getInstance().unlikePost(post.id);
      }
    } catch (err) {
      this.applyPostLikeOverride(post.id, previousLiked, previousCount);
      this.updatePostLikeState(post.id, previousLiked);
      const message: string = ApiClient.formatError(err).replace('Error: ', '').trim();
      ToastService.show(message.length > 0 && message !== 'Unknown error'
        ? message
        : (nextLiked ? '点赞失败' : '取消点赞失败'));
    } finally {
      if (this.postLikeMutatingPostId === post.id) {
        this.postLikeMutatingPostId = 0;
      }
    }
  }

  private applyPostBookmarkUpdate(
    postId: number,
    name: string | null,
    reminderAt: Date | null,
    clearReminderAt: boolean
  ): void {
    const targetPost: Post | null = this.getLoadedPostById(postId);
    const bookmarkId: number | null = targetPost !== null ? targetPost.bookmarkId : null;
    this.updatePostBookmarkState(
      postId,
      bookmarkId !== null && (bookmarkId as number) > 0,
      bookmarkId,
      name,
      clearReminderAt ? null : reminderAt
    );
  }

  private async handlePostBookmarkAction(post: Post): Promise<void> {
    if (this.isPostBookmarkMutating(post.id)) {
      return;
    }
    const loggedIn: boolean = await this.ensureLoggedInForAction();
    if (!loggedIn) {
      ToastService.showLoginRequired();
      return;
    }
    if (post.bookmarked) {
      if (post.bookmarkId === null || (post.bookmarkId as number) <= 0) {
        ToastService.show('书签信息同步中，请稍后重试');
        return;
      }
      this.openPostBookmarkSheet(post);
      return;
    }
    if (post.id <= 0) {
      ToastService.show('无效的帖子');
      return;
    }

    this.postBookmarkMutatingPostId = post.id;
    try {
      const bookmarkId: number = await ApiClient.getInstance().bookmarkPost(post.id);
      this.updatePostBookmarkState(post.id, true, bookmarkId, null, null);
      ToastService.show('已添加书签');
      const targetPost: Post | null = this.getLoadedPostById(post.id);
      if (targetPost !== null) {
        this.openPostBookmarkSheet(targetPost);
      }
    } catch (err) {
      const message: string = ApiClient.formatError(err).replace('Error: ', '').trim();
      ToastService.show(message.length > 0 && message !== 'Unknown error' ? message : '添加书签失败');
    } finally {
      if (this.postBookmarkMutatingPostId === post.id) {
        this.postBookmarkMutatingPostId = 0;
      }
    }
  }

  private getTopicBookmarkMenuLabel(): string {
    if (this.isBookmarkMutating) {
      return '处理中...';
    }
    return this.isBookmarked ? '编辑书签' : '添加书签';
  }

  private async handleTopicBookmarkAction(): Promise<void> {
    if (this.isBookmarkMutating) {
      return;
    }
    const loggedIn: boolean = await this.ensureLoggedInForAction();
    if (!loggedIn) {
      ToastService.showLoginRequired();
      return;
    }
    if (this.isBookmarked) {
      if (this.topicBookmarkId <= 0) {
        ToastService.show('书签信息同步中，请稍后重试');
        return;
      }
      this.openTopicBookmarkSheet();
      return;
    }
    if (this.topicId <= 0) {
      ToastService.show('无效的话题');
      return;
    }

    this.isBookmarkMutating = true;
    try {
      const bookmarkId: number = await ApiClient.getInstance().bookmarkTopic(this.topicId);
      this.isBookmarked = true;
      this.topicBookmarkId = bookmarkId;
      this.topicBookmarkName = '';
      this.topicBookmarkReminderAt = null;
      ToastService.show('已添加书签');
      this.openTopicBookmarkSheet();
    } catch (err) {
      const message: string = ApiClient.formatError(err).replace('Error: ', '').trim();
      ToastService.show(message.length > 0 && message !== 'Unknown error' ? message : '添加书签失败');
    } finally {
      this.isBookmarkMutating = false;
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

    // 过滤模式/搜索模式：不做实时追加
    if (this.isSummaryMode || this.isAuthorOnlyMode || this.isSearchMode) return;

    const dataObj: Object | null = message.data;
    if (dataObj === null || dataObj === undefined || typeof dataObj !== 'object') return;
    const data: Record<string, Object> = dataObj as Record<string, Object>;

    const notificationLevelChangeVal: Object | undefined = data['notification_level_change'];
    if (notificationLevelChangeVal !== undefined && notificationLevelChangeVal !== null) {
      const nextLevel: number = Number(notificationLevelChangeVal.toString());
      if (!isNaN(nextLevel)) {
        this.notificationLevel = Math.max(0, Math.round(nextLevel));
        this.notificationLevelLabel = this.getNotificationLevelLabel(this.notificationLevel);
      }
      return;
    }

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

    // 若已加载到末尾且用户在底部：立即拉取正文并追加
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
    this.topicBookmarkId = 0;
    this.topicBookmarkName = '';
    this.topicBookmarkReminderAt = null;
    this.isBookmarkSheetVisible = false;
    this.isPostBookmarkSheetVisible = false;
    this.editingPostBookmarkPost = null;
    this.postBookmarkMutatingPostId = 0;
    this.postLikeMutatingPostId = 0;
    this.clearPostLikeOverrides();
    this.clearPostReactionOverrides();
    this.postReactionLastActionAtMap.clear();
    this.postReactionCooldownUntilMap.clear();
    this.postReactionSectionAreaMap.clear();
    this.animatedLikePostId = 0;
    this.likeButtonScale = 1;
    this.clearLikeAnimationTimer();
    this.closeReactionPicker();
    this.clearReactionPickerAnimationTimer();
    this.clearScrollSyncTimer();
    this.clearBottomBarShowTimer();

    this.replyCount = 0;
    this.postsCount = 0;
    this.currentPostIndex = requestedPostNumber > 0 ? requestedPostNumber : 1;
    this.scrollOffset = 0;
    this.showTitle = false;
    this.showBottomBar = true;
    this.bottomBarVisibility = 1;
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

      // slug（用于分享链接）
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

      this.applyTopicBookmarkStateFromJson(json);

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

      this.applyPostBookmarkStatesFromJson(json, parsedPosts);
      this.acceptedAnswerPostNumber = this.resolveAcceptedAnswerPostNumber(json, parsedPosts);
      this.hasAcceptedAnswer = this.resolveHasAcceptedAnswer(json, parsedPosts, this.acceptedAnswerPostNumber);
      this.posts = parsedPosts;
      this.updateTopicOwnerUsername();

      // 总帖子数优先取 stream；兜底 highest_post_number / posts_count / 已加载 posts
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
      const errText: string = ApiClient.formatError(err);
      hilog.error(0x0000, TAG, 'Load topic detail failed: %{public}s', errText);
      if (errText.indexOf('Cloudflare verification') >= 0) {
        this.errorMessage = 'Cloudflare 验证未完成，请重试';
      } else if (ApiClient.isSslPeerCertificateError(err)) {
        this.errorMessage = ApiClient.getTlsCertificateErrorMessage();
      } else {
        this.errorMessage = '加载话题详情失败';
      }
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

    this.editingReplyPost = null;
    this.replySheetTargetPostNumber = replyToPost !== null ? replyToPost.postNumber : 0;
    this.replySheetTargetUsername = replyToPost !== null ? replyToPost.username : '';
    this.replySheetTargetAvatarTemplate = replyToPost !== null ? replyToPost.avatarTemplate : '';
    this.replySheetInitialContent = initialContent;
    this.replySheetRequestKey = `reply_${Date.now()}_${this.replySheetTargetPostNumber}`;
    this.isReplySheetVisible = true;
  }

  private openEditReplySheet(post: Post): void {
    if (this.isGuestMode) {
      ToastService.show('请先登录');
      return;
    }
    if (!post.canEdit) {
      ToastService.show('当前帖子不可编辑');
      return;
    }
    this.editingReplyPost = this.clonePost(post);
    this.replySheetTargetPostNumber = 0;
    this.replySheetTargetUsername = '';
    this.replySheetTargetAvatarTemplate = '';
    this.replySheetInitialContent = '';
    this.replySheetRequestKey = `edit_${Date.now()}_${post.id}`;
    this.isReplySheetVisible = true;
  }

  private handleReplySubmitted(post: Post): void {
    if (post.id <= 0) {
      return;
    }

    if (this.editingReplyPost !== null) {
      this.replacePostInstance(post);
      ToastService.show('已保存');
      this.pendingReplyScrollPostNumber = 0;
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
    this.editingReplyPost = null;
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

  private getLoadedPostById(postId: number): Post | null {
    const idx: number = this.findPostIndexById(postId);
    if (idx < 0 || idx >= this.posts.length) {
      return null;
    }
    return this.posts[idx];
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

    // 目标楼层不在当前已加载列表时，直接按目标楼层重载一段连续帖子，
    // 避免只把单个目标楼层插到当前列表里，造成 20 后面突然接 33 的断层。
    this.reloadWithTargetPostNumber(target);
  }

  private getCategoryColor(category: Category | null): string {
    if (category === null) return this.getDefaultCategoryColor();
    const c: Category = category as Category;
    if (c.color.length === 0) return this.getDefaultCategoryColor();
    if (c.color.startsWith('#')) return c.color;
    return `#${c.color}`;
  }

  private getDefaultCategoryColor(): string {
    return WindowManager.isDarkMode() ? '#777777' : '#999999';
  }

  private getMenuShadowColor(): string {
    return WindowManager.isDarkMode() ? '#00000000' : '#22000000';
  }

  private getProgressCapsuleShadowColor(): string {
    return WindowManager.isDarkMode() ? '#00000000' : '#33000000';
  }

  private getFloatingActionShadowColor(): string {
    return WindowManager.isDarkMode() ? '#00000000' : '#55000000';
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
    const v: number = Math.max(0, Math.min(1, this.bottomBarVisibility));
    return this.getBottomSafeHeight()
      + v * (FLOATING_TAB_BAR_HEIGHT_VP + FLOATING_TAB_BAR_MARGIN_BOTTOM_VP + FLOATING_TAB_BAR_CONTENT_EXTRA_PADDING_VP);
  }

  private getProgressBottomOffset(): number {
    return this.getBottomSafeHeight()
      + PROGRESS_BOTTOM_NO_BAR
      + this.bottomBarVisibility * (BOTTOM_BAR_HEIGHT + FLOATING_TAB_BAR_MARGIN_BOTTOM_VP + PROGRESS_GAP_ABOVE_BAR);
  }

  private getProgressTranslateY(): number {
    return -(this.getProgressBottomOffset() + PROGRESS_CAPSULE_HEIGHT);
  }

  private scheduleScrollOffsetSync(): void {
    if (this.scrollSyncTimerId >= 0) {
      return;
    }
    this.scrollSyncTimerId = setTimeout(() => {
      this.scrollSyncTimerId = -1;
      const currentOffset = this.listScroller.currentOffset();
      const yOffset: number = currentOffset.yOffset;
      this.scrollOffset = Math.max(0, yOffset);
      this.showTitle = this.scrollOffset > TITLE_SHOW_OFFSET;
    }, 0);
  }

  private clearScrollSyncTimer(): void {
    if (this.scrollSyncTimerId >= 0) {
      clearTimeout(this.scrollSyncTimerId);
      this.scrollSyncTimerId = -1;
    }
  }

  private clearBottomBarShowTimer(): void {
    if (this.bottomBarShowTimerId >= 0) {
      clearTimeout(this.bottomBarShowTimerId);
      this.bottomBarShowTimerId = -1;
    }
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
    this.clearBottomBarShowTimer();
    this.showBottomBar = visible;
    this.bottomBarVisibility = visible ? 1 : 0;
  }

  private hideBottomBar(): void {
    this.clearBottomBarShowTimer();
    this.setBottomBarVisible(false);
  }

  private showBottomBarImmediate(): void {
    this.clearBottomBarShowTimer();
    this.setBottomBarVisible(true);
  }

  private scheduleBottomBarShow(): void {
    if (this.showBottomBar && this.bottomBarVisibility >= 1) {
      this.clearBottomBarShowTimer();
      return;
    }
    this.clearBottomBarShowTimer();
    this.bottomBarShowTimerId = setTimeout(() => {
      this.bottomBarShowTimerId = -1;
      this.setBottomBarVisible(true);
    }, BOTTOM_BAR_SHOW_DELAY_MS);
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
    return `#${alphaHex}${this.getDefaultCategoryColor().substring(1)}`;
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
      this.openTopicNotificationSheet();
    })
  }

  @Builder
  TopicHeader() {
    Column() {
      Column() {
        // 标题（closed/accepted icon + title）
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

        // 通知等级（chip 风格）
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

  @Builder
  private PostReactionGlyph(reactionId: string, iconSize: number = 18, filledHeart: boolean = true) {
    if (this.isHeartReactionId(reactionId)) {
      SymbolGlyph(filledHeart ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
        .fontSize(iconSize)
        .fontColor([filledHeart ? $r('app.color.like_color') : $r('app.color.on_surface_secondary')])
    } else if (this.getReactionIconUrl(reactionId).length > 0) {
      Image(this.getReactionIconUrl(reactionId))
        .width(iconSize)
        .height(iconSize)
        .objectFit(ImageFit.Contain)
    } else {
      Text(this.getReactionFallbackText(reactionId))
        .fontSize(Math.max(14, iconSize - 1))
        .fontColor($r('app.color.on_surface'))
    }
  }

  @Builder
  private PostReactionPicker(post: Post) {
    Column() {
      if (this.reactionPickerLoading) {
        Row() {
          LoadingSpinner({ message: '' })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .padding({ top: 8, bottom: 8 })
      } else {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
          ForEach(this.reactionPickerOptions, (reactionId: string) => {
            Column() {
              this.PostReactionGlyph(reactionId, 26, true)
            }
            .width(this.getPostReactionPickerItemSize())
            .height(this.getPostReactionPickerItemSize())
            .borderRadius(this.getPostReactionPickerItemSize() / 2)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(this.isCurrentPostReaction(post, reactionId) ? '#14FFFFFF' : Color.Transparent)
            .margin({
              right: this.getPostReactionPickerItemGap(),
              bottom: this.getPostReactionPickerItemGap()
            })
            .opacity(this.isPostLikeMutating(post.id) ? 0.6 : 1)
            .onClick(() => {
              this.handlePostReactionAction(post, reactionId).catch((_: Object) => {
              });
            })
          }, (reactionId: string) => reactionId)
        }
        .width(this.getPostReactionPickerPanelWidth() - this.getPostReactionPickerPanelPadding() * 2 + this.getPostReactionPickerItemGap())
      }
    }
    .width(this.getPostReactionPickerPanelWidth())
    .padding({
      left: this.getPostReactionPickerPanelPadding(),
      right: Math.max(2, this.getPostReactionPickerPanelPadding() - this.getPostReactionPickerItemGap()),
      top: this.getPostReactionPickerPanelPadding(),
      bottom: Math.max(2, this.getPostReactionPickerPanelPadding() - this.getPostReactionPickerItemGap())
    })
    .backgroundColor($r('app.color.surface_variant'))
    .borderRadius(POST_REACTION_PICKER_PANEL_RADIUS)
    .border({ width: 0.5, color: $r('app.color.divider_light') })
    .shadow({ radius: 18, color: '#26000000', offsetX: 0, offsetY: 8 })
  }

  @Builder
  private PostReactionBar(post: Post) {
    Row() {
      if (this.shouldShowPostReactionSummary(post)) {
        Row() {
          if (this.getReactionSummaryReactions(post).length > 0) {
            Row() {
              ForEach(this.getReactionSummaryReactions(post), (reaction: PostReaction, index: number) => {
                Column() {
                  this.PostReactionGlyph(reaction.id, 15, true)
                }
                .width(18)
                .height(18)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .margin({ right: index < this.getReactionSummaryReactions(post).length - 1 ? 3 : 0 })
              }, (reaction: PostReaction) => `${reaction.id}_${reaction.count}`)
            }
            .margin({ right: 6 })
          }

          Text(this.getPostReactionCountText(post))
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface_secondary'))
        }
        .height(36)
        .padding({ left: 12, right: 8 })
        .alignItems(VerticalAlign.Center)
      }

      Row() {
        if (this.getResolvedCurrentUserReaction(post) !== null) {
          this.PostReactionGlyph((this.getResolvedCurrentUserReaction(post) as PostReaction).id, 18, true)
        } else {
          this.PostReactionGlyph('heart', 18, false)
        }
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.getResolvedCurrentUserReaction(post) !== null ? $r('app.color.background') : Color.Transparent)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.closeReactionPicker();
        this.handlePostReactionAction(post).catch((_: Object) => {
        });
      })
    }
    .height(36)
    .padding({ left: this.shouldShowPostReactionSummary(post) ? 0 : 4, right: 4 })
    .borderRadius(18)
    .backgroundColor($r('app.color.surface_variant'))
    .border({
      width: this.getResolvedCurrentUserReaction(post) !== null ? 1 : 0,
      color: this.isHeartReactionId(
        this.getResolvedCurrentUserReaction(post) !== null ? (this.getResolvedCurrentUserReaction(post) as PostReaction).id : ''
      )
        ? $r('app.color.like_color')
        : $r('app.color.primary')
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .scale({
      x: this.getPostLikeButtonScale(post.id),
      y: this.getPostLikeButtonScale(post.id)
    })
    .animation({ duration: 180, curve: Curve.EaseOut })
    .opacity(this.isPostLikeMutating(post.id) ? 0.72 : 1)
    .parallelGesture(
      LongPressGesture({ repeat: false, duration: 350 })
        .onAction(() => {
          this.showReactionPicker(post).catch((_: Object) => {
          });
        })
    )
  }

  @Builder
  private PostReactionSection(post: Post) {
    Column() {
      this.PostReactionBar(post)
    }
    .width(this.getPostReactionBarWidth(post))
    .height(36)
    .margin({ right: 10 })
    .onAreaChange((_: Area, newArea: Area) => {
      this.updatePostReactionSectionArea(post.id, newArea);
    })
  }

  @Builder
  private ReactionPickerOverlayLayer() {
    if (this.reactionPickerPostId > 0) {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#01000000')
        .onClick(() => {
          this.dismissReactionPicker();
        })

        if (this.findPostById(this.reactionPickerPostId) !== null) {
          Column() {
            this.PostReactionPicker(this.findPostById(this.reactionPickerPostId) as Post)
          }
          .position({ x: this.reactionPickerPanelX, y: this.reactionPickerPanelY })
          .translate({ x: 0, y: this.reactionPickerPanelTranslateY })
          .scale({ x: this.reactionPickerPanelScale, y: this.reactionPickerPanelScale })
          .opacity(this.reactionPickerPanelOpacity)
          .enabled(this.reactionPickerPanelOpacity > 0)
        }
      }
      .width('100%')
      .height('100%')
      .clip(false)
    }
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

                  // 与首页一致：仅在列表末尾预留悬浮胶囊避让空间，
                  // 让正文可以继续滚动到胶囊后方，而不是整段内容被底部 padding 提前挡住。
                  ListItem() {
                    Row() {
                    }
                    .width('100%')
                    .height(this.getDetailBottomBarReservedBottomVp())
                  }
                }
                .width('100%')
                .layoutWeight(1)
                .backgroundColor($r('app.color.surface'))
                .onReachStart(() => {
                  this.scrollOffset = 0;
                  this.showTitle = false;
                  this._bottomBarDelta = 0;
                  this.showBottomBarImmediate();
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
                  if (this.reactionPickerPostId > 0 && Math.abs(offset) > 0.1) {
                    this.closeReactionPicker();
                  }
                  // 先用增量预测，随后再异步同步 scroller.currentOffset()，避免边界回弹造成状态漂移。
                  const next: number = Math.max(0, this.scrollOffset + offset);
                  this.scrollOffset = next;
                  this.scheduleScrollOffsetSync();

                  // 底部工具栏显隐：
                  // - 向上滚动（offset<0）→ 显示
                  // - 向下滚动（offset>0）→ 隐藏
                  if (next <= 0) {
                    this._bottomBarDelta = 0;
                    this.showBottomBarImmediate();
                  } else if (offset < -0.01) {
                    this._bottomBarDelta = 0;
                    this.showBottomBarImmediate();
                  } else {
                    this.clearBottomBarShowTimer();
                    // 方向改变时重置累计，避免轻微回弹导致阈值判断反复
                    if ((this._bottomBarDelta > 0 && offset <= 0) || (this._bottomBarDelta < 0 && offset > 0)) {
                      this._bottomBarDelta = offset;
                    } else {
                      this._bottomBarDelta = this._bottomBarDelta + offset;
                    }

                    if (this._bottomBarDelta > BOTTOM_BAR_HIDE_DELTA && this.showBottomBar) {
                      this._bottomBarDelta = 0;
                      this.hideBottomBar();
                    }
                  }

                  this.showTitle = next > TITLE_SHOW_OFFSET;
                  return { offsetRemain: offset };
                })
                .onScrollStop(() => {
                  this._bottomBarDelta = 0;
                  this.scheduleBottomBarShow();
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
          .shadow({ radius: 4, color: this.getProgressCapsuleShadowColor(), offsetX: 0, offsetY: 2 })
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
                  this.setBottomBarVisibleInstant(true);
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
              .fontColor([$r('app.color.primary')])
          }
          .width(56)
          .height(56)
          .borderRadius(16)
          .backgroundColor(Color.Transparent)
          .backgroundEffect(
            {
              radius: 64,
              saturation: 2.2,
              brightness: 1.08,
              color: $r('app.color.fab_glass_tint'),
              adaptiveColor: AdaptiveColor.DEFAULT,
              policy: BlurStyleActivePolicy.ALWAYS_ACTIVE,
              inactiveColor: $r('app.color.fab_glass_tint')
            },
            { disableSystemAdaptation: true }
          )
          .border({ width: 0.5, color: $r('app.color.fab_glass_stroke') })
          .clip(true)
          .shadow({ radius: 18, color: $r('app.color.tab_glass_shadow'), offsetX: 0, offsetY: 10 })
          .position({ x: this.getReplyFabPositionX(), y: '100%' })
          .translate({ x: this.getReplyFabTranslateX(), y: this.getReplyFabTranslateY() })
          .animation({ duration: 220, curve: Curve.EaseOut })
          .onClick(() => {
            this.openReplySheet();
          })
        }

        this.ReactionPickerOverlayLayer()

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
        .bindSheet($$this.isBookmarkSheetVisible, this.TopicBookmarkSheetBuilder, {
          height: SheetSize.MEDIUM,
          dragBar: false,
          showClose: false,
          backgroundColor: $r('app.color.surface')
        })

        Column() {
        }
        .width(0)
        .height(0)
        .bindSheet($$this.isTopicNotificationSheetVisible, this.TopicNotificationSheetBuilder, {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          backgroundColor: $r('app.color.surface')
        })

        Column() {
        }
        .width(0)
        .height(0)
        .bindSheet($$this.isPostBookmarkSheetVisible, this.PostBookmarkSheetBuilder, {
          height: SheetSize.MEDIUM,
          dragBar: false,
          showClose: false,
          backgroundColor: $r('app.color.surface'),
          onDisappear: () => {
            this.isPostBookmarkSheetVisible = false;
            this.editingPostBookmarkPost = null;
          }
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
      .onAreaChange((_: Area, newArea: Area) => {
        this.updateReactionPickerRootArea(newArea);
      })
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
            .fontColor(this.isBookmarked ? [$r('app.color.primary')] : [$r('app.color.on_surface')])
            .margin({ right: 10 })
          Text(this.getTopicBookmarkMenuLabel())
            .fontSize(14)
            .fontColor(this.isBookmarked ? $r('app.color.primary') : $r('app.color.on_surface'))
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
          this.handleTopicBookmarkAction().catch((err: Object) => {
            hilog.error(0x0000, TAG, 'Handle topic bookmark failed: %{public}s', JSON.stringify(err));
          });
        }
      })

      MenuItem() {
        Row() {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(16)
            .fontColor(this.isInReadLater ? [$r('app.color.primary')] : [$r('app.color.on_surface')])
            .margin({ right: 10 })
          Text(this.getReadLaterMenuLabel())
            .fontSize(14)
            .fontColor(this.isInReadLater ? $r('app.color.primary') : $r('app.color.on_surface'))
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
          this.handleReadLaterAction().catch((err: Object) => {
            hilog.error(0x0000, TAG, 'Handle read later action failed: %{public}s', JSON.stringify(err));
          });
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
          this.openTopicNotificationSheet();
        }
      })
    }
    .width(180)
    .backgroundColor($r('app.color.search_bar_background'))
    .borderRadius(12)
    .shadow({ radius: 10, color: this.getMenuShadowColor(), offsetX: 0, offsetY: 6 })
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
    // 底部栏“生成分享图片”默认分享主帖；若主帖未加载则提示
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
    .shadow({ radius: 10, color: this.getMenuShadowColor(), offsetX: 0, offsetY: 6 })
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
            Text('回复')
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

        if (post.canEdit) {
          MenuItem() {
            Row() {
              SymbolGlyph($r('sys.symbol.pencil_line'))
                .fontSize(16)
                .fontColor([$r('app.color.on_surface')])
                .margin({ right: 10 })
              Text('编辑')
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
              this.openEditReplySheet(post);
            }
          })
        }

        MenuItem() {
          Row() {
            SymbolGlyph(post.bookmarked ? $r('sys.symbol.bookmark_fill') : $r('sys.symbol.bookmark'))
              .fontSize(16)
              .fontColor([post.bookmarked ? $r('app.color.primary') : $r('app.color.on_surface')])
              .margin({ right: 10 })
            Text(this.getPostBookmarkActionLabel(post))
              .fontSize(14)
              .fontColor(post.bookmarked ? $r('app.color.primary') : $r('app.color.on_surface'))
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
            this.handlePostBookmarkAction(post).catch((_: Object) => {
            });
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
    .shadow({ radius: 10, color: this.getMenuShadowColor(), offsetX: 0, offsetY: 6 })
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

      // 主题选择
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
  TopicNotificationOption(level: number) {
    Row() {
      Column() {
        Text(this.getNotificationLevelLabel(level))
          .fontSize(16)
          .fontWeight(this.notificationLevel === level ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.notificationLevel === level ? $r('app.color.primary') : $r('app.color.on_surface'))

        Text(this.getTopicNotificationLevelDescription(level))
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.notificationLevel === level) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([$r('app.color.primary')])
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 14, bottom: 14 })
    .backgroundColor(this.notificationLevel === level ? $r('app.color.badge_background_light') : $r('app.color.surface'))
    .borderRadius(14)
    .alignItems(VerticalAlign.Center)
    .enabled(!this.isTopicNotificationMutating)
    .onClick(() => {
      this.updateTopicNotificationLevel(level).catch((err: Object) => {
        hilog.error(0x0000, TAG, 'Update topic notification level failed: %{public}s', JSON.stringify(err));
      });
    })
  }

  @Builder
  TopicNotificationSheetBuilder() {
    Column() {
      Row() {
        Text('订阅设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))

        Blank().layoutWeight(1)

        if (this.isTopicNotificationMutating) {
          LoadingProgress()
            .width(18)
            .height(18)
        }
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 8, bottom: 6 })
      .alignItems(VerticalAlign.Center)

      Column() {
        this.TopicNotificationOption(0)
        this.TopicNotificationOption(1)
        this.TopicNotificationOption(2)
        this.TopicNotificationOption(3)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .alignItems(HorizontalAlign.Start)

      Blank().height(12 + WindowManager.getSystemAvoidAreaBottomVp())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  TopicBookmarkSheetBuilder() {
    if (this.topicBookmarkId > 0) {
      BookmarkEditSheet({
        bookmarkId: this.topicBookmarkId,
        initialName: this.topicBookmarkName,
        initialReminderAt: this.topicBookmarkReminderAt,
        onDismiss: () => {
          this.closeTopicBookmarkSheet();
        },
        onUpdated: (name: string | null, reminderAt: Date | null, clearReminderAt: boolean) => {
          this.applyTopicBookmarkUpdate(name, reminderAt, clearReminderAt);
        },
        onDeleted: () => {
          this.clearTopicBookmarkState();
        }
      })
    }
  }

  @Builder
  PostBookmarkSheetBuilder() {
    if (this.editingPostBookmarkPost !== null
      && (this.editingPostBookmarkPost as Post).bookmarkId !== null
      && ((this.editingPostBookmarkPost as Post).bookmarkId as number) > 0) {
      BookmarkEditSheet({
        bookmarkId: (this.editingPostBookmarkPost as Post).bookmarkId as number,
        initialName: (this.editingPostBookmarkPost as Post).bookmarkName !== null
          ? (this.editingPostBookmarkPost as Post).bookmarkName as string
          : '',
        initialReminderAt: (this.editingPostBookmarkPost as Post).bookmarkReminderAt,
        onDismiss: () => {
          this.closePostBookmarkSheet();
        },
        onUpdated: (name: string | null, reminderAt: Date | null, clearReminderAt: boolean) => {
          this.applyPostBookmarkUpdate(
            (this.editingPostBookmarkPost as Post).id,
            name,
            reminderAt,
            clearReminderAt
          );
        },
        onDeleted: () => {
          this.clearPostBookmarkState((this.editingPostBookmarkPost as Post).id);
        }
      })
    }
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
      editingPost: this.editingReplyPost,
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

        // 相关链接（reflection links）
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

        // 底部操作行
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

          if (!this.isGuestMode) {
            this.PostReactionSection(post)
          }

          // 右侧：更多
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

        // 折叠回复列表（从帖子流中找 reply_to_post_number 指向当前楼层的帖子）
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
        // 图标（圆形容器）
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
