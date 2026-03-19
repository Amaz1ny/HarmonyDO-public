import { hilog } from '@kit.PerformanceAnalysisKit';
import { Topic, TopicListResponse, Tag } from '../../models/Topic';
import { Category, SiteResponse } from '../../models/Category';
import { AppConstants } from '../../common/constants/AppConstants';
import { ApiClient } from '../../services/network/ApiClient';
import { AuthService } from '../../services/auth/AuthService';
import { TopicCard, CompactTopicCard } from '../components/TopicCard';
import { TopicListSkeleton } from '../components/TopicListSkeleton';
import { ErrorView } from '../components/ErrorView';
import { CategoryIcon } from '../components/CategoryIcon';
import { TopicPreviewDialog } from '../components/TopicPreviewDialog';
import { UrlUtils } from '../../common/utils/UrlUtils';
import { RouterManager, RouteConstants } from '../../common/utils/RouterManager';
import { PillIconButton, PillMenuButton, SORT_FILTER_OPTIONS, SORT_FILTER_OPTIONS_LOGGED_IN, SORT_ORDER_OPTIONS } from '../components/PillControls';
import { DEFAULT_AVAILABLE_TAGS, TagChip, TagSelectionSheet } from '../components/TagControls';
import { WindowManager } from '../../common/utils/WindowManager';
import { TopicTrackingService } from '../../services/messagebus/TopicTrackingService';
import { AppSettingsService } from '../../services/storage/AppSettingsService';
import { TopicListPreferences } from '../../services/storage/TopicListPreferences';
import {
  FLOATING_TAB_BAR_HEIGHT_VP,
  FLOATING_TAB_BAR_MARGIN_BOTTOM_VP,
  FLOATING_TAB_BAR_CONTENT_EXTRA_PADDING_VP
} from '../../common/constants/LayoutConstants';

const TAG: string = 'TopicListPage';
const SEARCH_BAR_HEIGHT: number = 56;
const TAB_ROW_HEIGHT: number = 36;
const SORT_BAR_HEIGHT: number = 44;
const COLLAPSIBLE_HEIGHT: number = SEARCH_BAR_HEIGHT + SORT_BAR_HEIGHT;
const BAR_VISIBILITY_EPS: number = 0.01;

// 游客态“查看新话题”轮询：Discourse 站点通常会把匿名 MessageBus poll 拉长到 ~25s（anon_polling_interval）
// 为了更“实时”的体验，这里额外用 /latest.json 做轻量轮询并做指数退避，避免触发 CF 频控时刷屏/卡死
const INCOMING_POLL_INTERVAL_ANON_MS: number = 5000;
const INCOMING_POLL_MAX_BACKOFF_MS: number = 60000;
const INCOMING_HIGHLIGHT_DURATION_MS: number = 2500;

const SHEET_NONE: number = 0;
const SHEET_CATEGORY: number = 1;
const SHEET_TAG: number = 2;

@ComponentV2
export struct TopicListPage {
  @Param onTopicClick: (topic: Topic) => void = () => {};
  @Param onBarVisibilityChange: (visibility: number) => void = () => {};
  @Local topics: Topic[] = [];
  @Local categories: Category[] = [];
  @Local categoryMap: Map<number, Category> = new Map();
  @Local isLoading: boolean = true;
  @Local isLoadingMore: boolean = false;
  @Local errorMessage: string = '';
  @Local isLoggedIn: boolean = false;
  @Local trackedNewCount: number = 0;
  @Local trackedUnreadCount: number = 0;
  @Local currentPage: number = 0;
  @Local hasMore: boolean = true;
  @Local currentCategoryIndex: number = 0;
  @Local pinnedCategoryIds: number[] = [];
  @Local overrideCategory: Category | null = null;

  // Header 折叠
  @Local headerOffset: number = 0; // 0 展开，COLLAPSIBLE_HEIGHT 折叠
  @Local listAtTop: boolean = true;
  @Local fabRefreshMode: boolean = false;
  private listScroller: Scroller = new Scroller();
  private headerSnapTimerId: number = -1;
  private lastReportedBarVisibility: number = 1;

  // “查看新话题” banner（对齐 Flutter：topic_ids 增量插入；Mock 下自动模拟）
  @Local incomingTopicCount: number = 0;
  @Local incomingTopicIds: number[] = [];
  @Local isLoadingIncoming: boolean = false;
  @Local highlightedTopicIds: number[] = [];
  private mockIncomingTimerId: number = -1;
  private mockIncomingSeedId: number = 20000;
  private incomingLoadTimerId: number = -1;
  private incomingPollTimerId: number = -1;
  private incomingHighlightTimerId: number = -1;
  private incomingPollInFlight: boolean = false;
  private incomingPollBackoffMs: number = INCOMING_POLL_INTERVAL_ANON_MS;
  private trackingListener: (() => void) | null = null;
  private hasBootstrapped: boolean = false;
     
  // 底部弹出层状态
  @Local isSheetVisible: boolean = false;
  @Local sheetMode: number = SHEET_NONE;
  @Local isEditingCategory: boolean = false;

  // 排序与筛选状态
  @Local currentFilter: string = '最新';
  @Local currentOrder: string = '默认';
  @Local orderAscending: boolean = false;
  @Local previewTopic: Topic | null = null;
  @Local previewCategory: Category | null = null;
  @Local previewParentCategory: Category | null = null;
  @Local isTopicPreviewVisible: boolean = false;
  @Local enableLongPressPreview: boolean = true;
  @Local allowHideBarOnScroll: boolean = true;

  // 标签筛选
  @Local selectedTags: string[] = [];
  @Local draftSelectedTags: string[] = [];
  @Local availableTags: string[] = DEFAULT_AVAILABLE_TAGS;
  private authStateListener: (() => void) | null = null;
  private settingsListener: (() => void) | null = null;

  aboutToAppear(): void {
    this.attachSettingsListener();
    this.syncSettingsState();
    this.reportBarVisibility(true);
    this.attachAuthStateListener();

    // 避免切换页面/Tab 后重复全量 bootstrap（会重新拉取列表，导致 banner 延迟出现并“一口气跳很大”）
    if (this.hasBootstrapped) {
      this.onPageResume();
      return;
    }
    this.hasBootstrapped = true;
    this.bootstrapPage().catch((err: Object) => {
      hilog.error(0x0000, TAG, 'Bootstrap page failed: %{public}s', JSON.stringify(err));
      this.isLoading = false;
      this.errorMessage = '加载失败，请重试';
    });
  }

  aboutToDisappear(): void {
    this.clearHeaderSnapTimer();
    this.clearMockIncomingTimer();
    this.clearIncomingLoadTimer();
    this.clearIncomingPollTimer();
    this.clearIncomingHighlightTimer();
    this.highlightedTopicIds = [];
    this.detachTrackingListener();
    this.detachSettingsListener();
  }

  private attachSettingsListener(): void {
    if (this.settingsListener !== null) {
      return;
    }
    this.settingsListener = () => {
      this.syncSettingsState();
      this.reportBarVisibility(true);
    };
    AppSettingsService.getInstance().addListener(this.settingsListener);
    AppSettingsService.getInstance().ensureInit().then(() => {
      this.syncSettingsState();
      this.reportBarVisibility(true);
    }).catch(() => {
    });
  }

  private detachSettingsListener(): void {
    if (this.settingsListener === null) {
      return;
    }
    AppSettingsService.getInstance().removeListener(this.settingsListener);
    this.settingsListener = null;
  }

  private syncSettingsState(): void {
    const featureSettings = AppSettingsService.getInstance().getFeatureSettings();
    this.enableLongPressPreview = featureSettings.longPressPreview;
    this.allowHideBarOnScroll = featureSettings.hideBarOnScroll;
  }

  private onPageResume(): void {
    // 页面恢复可见时：不重新拉取列表，只同步 tracking UI（对齐安卓：人在别的页也持续累加）
    this.ensureTrackingStarted();
    this.refreshTrackingUI();
    this.maybeArmIncomingBanner();

    // 登录态可能在其它页面发生变化（后续接入登录后），恢复时同步一下
    this.initAuthState()
      .then(() => {
        this.ensureTrackingStarted();
        this.refreshTrackingUI();
        this.maybeArmIncomingBanner();
      })
      .catch((err: Object) => {
        hilog.error(0x0000, TAG, 'Resume init auth failed: %{public}s', JSON.stringify(err));
      });
  }

  private attachAuthStateListener(): void {
    if (this.authStateListener !== null) {
      return;
    }
    this.authStateListener = () => {
      this.initAuthState()
        .then(() => {
          this.refreshTrackingUI();
          this.maybeArmIncomingBanner();
        })
        .catch((err: Object) => {
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

  private async bootstrapPage(): Promise<void> {
    await this.restorePersistedState();
    await this.initAuthState();
    // 提前启动 tracking：让 /latest + /new 更接近安卓”实时”体验
    this.ensureTrackingStarted();
    await this.loadCategories();
    await this.loadTopics(true);
    this.maybeArmIncomingBanner();
  }

  private async restorePersistedState(): Promise<void> {
    this.currentFilter = await TopicListPreferences.loadFilter(this.currentFilter);
    this.currentOrder = await TopicListPreferences.loadOrder(this.currentOrder);
    this.orderAscending = await TopicListPreferences.loadAscending(this.orderAscending);
    this.pinnedCategoryIds = await TopicListPreferences.loadPinnedCategoryIds();
    this.selectedTags = await TopicListPreferences.loadSelectedTags();
  }

  private persistSortPreferences(): void {
    TopicListPreferences.saveFilter(this.currentFilter).catch((err: Object) => {
      hilog.error(0x0000, TAG, 'Persist filter failed: %{public}s', JSON.stringify(err));
    });
    TopicListPreferences.saveOrder(this.currentOrder).catch((err: Object) => {
      hilog.error(0x0000, TAG, 'Persist order failed: %{public}s', JSON.stringify(err));
    });
    TopicListPreferences.saveAscending(this.orderAscending).catch((err: Object) => {
      hilog.error(0x0000, TAG, 'Persist ascending failed: %{public}s', JSON.stringify(err));
    });
  }

  private persistPinnedCategories(): void {
    TopicListPreferences.savePinnedCategoryIds(this.pinnedCategoryIds).catch((err: Object) => {
      hilog.error(0x0000, TAG, 'Persist pinned categories failed: %{public}s', JSON.stringify(err));
    });
  }

  private persistSelectedTags(): void {
    TopicListPreferences.saveSelectedTags(this.selectedTags).catch((err: Object) => {
      hilog.error(0x0000, TAG, 'Persist selectedTags failed: %{public}s', JSON.stringify(err));
    });
  }

  private clearTrackedIncomingForCurrentContext(): void {
    this.resetIncomingBannerState();
    try {
      const svc: TopicTrackingService = TopicTrackingService.getInstance();
      if (svc.isStarted()) {
        svc.clearIncoming(this.getCurrentQueryCategoryId());
      }
    } catch (_) {
    }
    this.refreshTrackingUI();
  }

  private async initAuthState(): Promise<void> {
    const auth: AuthService = AuthService.getInstance();
    try {
      await auth.init();
      const next: boolean = auth.getIsLoggedIn();
      this.isLoggedIn = next;

      if (!next) {
        this.trackedNewCount = 0;
        this.trackedUnreadCount = 0;
        if (this.currentFilter === '新话题' || this.currentFilter === '未读完' || this.currentFilter === '未浏览') {
          this.currentFilter = '最新';
          this.persistSortPreferences();
          this.resetIncomingBannerState();
        }
      } else {
        this.clearIncomingPollTimer();
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Init auth state failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 加载分类列表
   */
  async loadCategories(): Promise<void> {
    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const siteResponse: SiteResponse = await apiClient.getSiteInfo();
      this.categories = siteResponse.categories;

      const newMap: Map<number, Category> = new Map();
      for (let i = 0; i < this.categories.length; i++) {
        const cat: Category = this.categories[i];
        newMap.set(cat.id, cat);
      }
      this.categoryMap = newMap;

      // 安卓端默认“我的分类”为空：不自动填充，避免 Tab 栏出现一堆分类影响对齐验收
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load categories failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 加载话题列表
   */
  async loadTopics(isRefresh: boolean): Promise<void> {
    if (isRefresh) {
      this.isLoading = true;
      this.currentPage = 0;
      this.errorMessage = '';
    } else {
      if (this.isLoadingMore || !this.hasMore) return;
      this.isLoadingMore = true;
    }

    try {
      const apiClient: ApiClient = ApiClient.getInstance();

      // 1) filter/period/order（对齐 FluxDO：latest/new/unread/unseen/top/hot）
      let filterName: string = 'latest';
      let period: string | null = null;
      switch (this.currentFilter) {
        case '最新':
          filterName = 'latest';
          period = null;
          break;
        case '新话题':
          filterName = 'new';
          period = null;
          break;
        case '未读完':
          filterName = 'unread';
          period = null;
          break;
        case '未浏览':
          filterName = 'unseen';
          period = null;
          break;
        case '排行榜':
          filterName = 'top';
          period = null;
          break;
        case '热门':
          filterName = 'hot';
          period = null;
          break;
        default:
          filterName = 'latest';
          period = null;
          break;
      }
      let orderParam: string | null = null;
      switch (this.currentOrder) {
        case '活跃度':
          orderParam = 'activity';
          break;
        case '创建时间':
          orderParam = 'created';
          break;
        case '点赞数':
          orderParam = 'likes';
          break;
        case '浏览量':
          orderParam = 'views';
          break;
        case '回复数':
          orderParam = 'posts';
          break;
        case '参与者':
          orderParam = 'posters';
          break;
        default:
          orderParam = null;
          break;
      }
      const ascendingParam: boolean | null = orderParam !== null ? this.orderAscending : null;

      // 2) category（override > pinned tab > 全部）
      let selectedCategory: Category | null = null;
      if (this.overrideCategory !== null) {
        selectedCategory = this.overrideCategory as Category;
      } else if (this.currentCategoryIndex > 0) {
        const pinned: Category[] = this.getPinnedCategories();
        if (this.currentCategoryIndex - 1 < pinned.length) {
          selectedCategory = pinned[this.currentCategoryIndex - 1];
        }
      }

      let categorySlug: string | null = null;
      let categoryId: number | null = null;
      let parentCategorySlug: string | null = null;
      if (selectedCategory !== null) {
        categorySlug = (selectedCategory as Category).slug;
        categoryId = (selectedCategory as Category).id;
        const pid: number | null = (selectedCategory as Category).parentCategoryId;
        if (pid !== null && pid > 0 && this.categoryMap.has(pid)) {
          parentCategorySlug = (this.categoryMap.get(pid) as Category).slug;
        }
      }

      // 3) tags（多选时对齐 Flutter：match_all_tags=true）
      const tagsParam: string[] | null = this.selectedTags.length > 0 ? [...this.selectedTags] : null;

      const response: TopicListResponse = await apiClient.getFilteredTopics(
        filterName,
        this.currentPage,
        period,
        orderParam,
        ascendingParam,
        categorySlug,
        categoryId,
        parentCategorySlug,
        tagsParam
      );

      if (isRefresh) {
        this.topics = response.topics;
      } else {
        this.topics = this.topics.concat(response.topics);
      }

      this.hasMore = response.topics.length >= response.perPage;
      this.currentPage = this.currentPage + 1;
      this.maybeArmIncomingBanner();
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load topics failed: %{public}s', JSON.stringify(err));
      if (isRefresh) {
        this.errorMessage = '加载失败，请下拉重试';
      }
    } finally {
      this.isLoading = false;
      this.isLoadingMore = false;
    }
  }

  private applyTagFilter(list: Topic[]): Topic[] {
    if (this.selectedTags.length === 0) return list;

    const filtered: Topic[] = [];
    for (let i = 0; i < list.length; i++) {
      const t: Topic = list[i];
      let ok: boolean = true;
      for (let j = 0; j < this.selectedTags.length; j++) {
        const tagName: string = this.selectedTags[j];
        let hasTag: boolean = false;
        for (let k = 0; k < t.tags.length; k++) {
          if (t.tags[k].name === tagName) {
            hasTag = true;
            break;
          }
        }
        if (!hasTag) {
          ok = false;
          break;
        }
      }
      if (ok) filtered.push(t);
    }
    return filtered;
  }

  private clamp(value: number, min: number, max: number): number {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  private getFloatingTabBarReservedBottomVp(): number {
    return WindowManager.getSystemAvoidAreaBottomVp()
      + FLOATING_TAB_BAR_HEIGHT_VP
      + FLOATING_TAB_BAR_MARGIN_BOTTOM_VP
      + FLOATING_TAB_BAR_CONTENT_EXTRA_PADDING_VP;
  }

  private getFloatingTabBarReservedBottomForVisibilityVp(visibility: number): number {
    const v: number = this.clamp(visibility, 0, 1);
    const bottomSafe: number = WindowManager.getSystemAvoidAreaBottomVp();
    const tabPart: number =
      (FLOATING_TAB_BAR_HEIGHT_VP + FLOATING_TAB_BAR_MARGIN_BOTTOM_VP + FLOATING_TAB_BAR_CONTENT_EXTRA_PADDING_VP) * v;
    return bottomSafe + tabPart;
  }

  private getHomeFabTranslateY(visibility: number): number {
    const v: number = this.clamp(visibility, 0, 1);
    const bottomSafe: number = WindowManager.getSystemAvoidAreaBottomVp();
    const avoidTabBar: number = (FLOATING_TAB_BAR_HEIGHT_VP + FLOATING_TAB_BAR_MARGIN_BOTTOM_VP) * v;
    return -(72 + bottomSafe + avoidTabBar);
  }

  private computeBarVisibility(): number {
    if (!this.allowHideBarOnScroll) {
      return 1;
    }
    const raw: number = 1 - this.headerOffset / COLLAPSIBLE_HEIGHT;
    return this.clamp(raw, 0, 1);
  }

  private reportBarVisibility(force: boolean): void {
    const next: number = this.computeBarVisibility();
    if (force || Math.abs(next - this.lastReportedBarVisibility) > BAR_VISIBILITY_EPS) {
      this.lastReportedBarVisibility = next;
      this.onBarVisibilityChange(next);
    }
  }

  private clearHeaderSnapTimer(): void {
    if (this.headerSnapTimerId >= 0) {
      clearTimeout(this.headerSnapTimerId);
      this.headerSnapTimerId = -1;
    }
  }

  private clearMockIncomingTimer(): void {
    if (this.mockIncomingTimerId >= 0) {
      clearTimeout(this.mockIncomingTimerId);
      this.mockIncomingTimerId = -1;
    }
  }

  private clearIncomingLoadTimer(): void {
    if (this.incomingLoadTimerId >= 0) {
      clearTimeout(this.incomingLoadTimerId);
      this.incomingLoadTimerId = -1;
    }
  }

  private clearIncomingPollTimer(): void {
    if (this.incomingPollTimerId >= 0) {
      clearTimeout(this.incomingPollTimerId);
      this.incomingPollTimerId = -1;
    }
  }

  private clearIncomingHighlightTimer(): void {
    if (this.incomingHighlightTimerId >= 0) {
      clearTimeout(this.incomingHighlightTimerId);
      this.incomingHighlightTimerId = -1;
    }
  }

  private resetIncomingBannerState(): void {
    this.incomingTopicCount = 0;
    this.incomingTopicIds = [];
    this.isLoadingIncoming = false;
    this.incomingPollBackoffMs = INCOMING_POLL_INTERVAL_ANON_MS;
    this.highlightedTopicIds = [];
    this.clearMockIncomingTimer();
    this.clearIncomingLoadTimer();
    this.clearIncomingPollTimer();
    this.clearIncomingHighlightTimer();
  }

  private highlightIncomingTopicsOnce(topicIds: number[]): void {
    this.clearIncomingHighlightTimer();

    const uniq: number[] = [];
    const seen: Map<number, boolean> = new Map();
    for (let i = 0; i < topicIds.length; i++) {
      const id: number = topicIds[i];
      if (id <= 0) continue;
      if (seen.has(id)) continue;
      seen.set(id, true);
      uniq.push(id);
    }

    this.highlightedTopicIds = uniq;
    if (uniq.length === 0) return;

    this.incomingHighlightTimerId = setTimeout(() => {
      this.incomingHighlightTimerId = -1;
      this.highlightedTopicIds = [];
    }, INCOMING_HIGHLIGHT_DURATION_MS);
  }

  private isTopicHighlighted(topicId: number): boolean {
    return this.highlightedTopicIds.includes(topicId);
  }

  private scheduleHeaderSnap(): void {
    this.clearHeaderSnapTimer();
    this.headerSnapTimerId = setTimeout(() => {
      this.headerSnapTimerId = -1;
      this.snapHeaderIfNeeded();
    }, 120);
  }

  private snapHeaderIfNeeded(): void {
    if (this.headerOffset <= 0 || this.headerOffset >= COLLAPSIBLE_HEIGHT) return;

    const target: number = this.headerOffset > COLLAPSIBLE_HEIGHT / 2 ? COLLAPSIBLE_HEIGHT : 0;
    const uiContext = this.getUIContext();
    if (uiContext !== undefined && uiContext !== null) {
      uiContext.animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
        this.headerOffset = target;
        this.reportBarVisibility(false);
      });
    } else {
      this.headerOffset = target;
      this.reportBarVisibility(false);
    }
  }

  private getSearchProgress(): number {
    return this.clamp(this.headerOffset / SEARCH_BAR_HEIGHT, 0, 1);
  }

  private getSortProgress(): number {
    return this.clamp((this.headerOffset - SEARCH_BAR_HEIGHT) / SORT_BAR_HEIGHT, 0, 1);
  }

  private maybeArmMockIncomingBanner(): void {
    if (!AppConstants.USE_MOCK_DATA) return;
    if (this.incomingTopicCount > 0) return;
    if (this.mockIncomingTimerId >= 0) return;
    if (this.currentFilter !== '最新') return;

    this.mockIncomingTimerId = setTimeout(() => {
      this.mockIncomingTimerId = -1;
      if (this.incomingTopicCount === 0 && this.currentFilter === '最新') {
        this.incomingTopicCount = 3;
      }
    }, 2500);
  }

  private getIncomingAnchorTopicId(): number {
    for (let i = 0; i < this.topics.length; i++) {
      const t: Topic = this.topics[i];
      if (!t.pinned) return t.id;
    }
    return this.topics.length > 0 ? this.topics[0].id : 0;
  }

  private maybeArmIncomingBanner(): void {
    if (AppConstants.USE_MOCK_DATA) {
      this.maybeArmMockIncomingBanner();
      return;
    }
    if (this.currentFilter !== '最新') return;
    if (this.topics.length === 0) return;

    this.ensureTrackingStarted();
    this.refreshTrackingUI();

    if (this.isLoggedIn) return;
    if (this.incomingPollTimerId >= 0) return;

    this.incomingPollTimerId = setTimeout(() => {
      this.incomingPollTimerId = -1;
      this.checkIncomingTopics();
    }, 800);
  }

  private isIncomingPollContextUnchanged(
    snapshotOrder: string,
    snapshotCategoryIndex: number,
    snapshotOverrideCategoryId: number,
    snapshotTags: string
  ): boolean {
    if (this.currentFilter !== '最新') return false;
    if (this.currentOrder !== snapshotOrder) return false;
    if (this.currentCategoryIndex !== snapshotCategoryIndex) return false;

    const currentOverrideId: number = this.overrideCategory !== null ? (this.overrideCategory as Category).id : 0;
    if (currentOverrideId !== snapshotOverrideCategoryId) return false;

    if (this.selectedTags.join(',') !== snapshotTags) return false;
    return true;
  }

  private mergeUniqueIds(preferred: number[], extra: number[]): number[] {
    const merged: number[] = [];
    const seen: Map<number, boolean> = new Map();
    for (let i = 0; i < preferred.length; i++) {
      const id: number = preferred[i];
      if (seen.has(id)) continue;
      seen.set(id, true);
      merged.push(id);
    }
    for (let i = 0; i < extra.length; i++) {
      const id: number = extra[i];
      if (seen.has(id)) continue;
      seen.set(id, true);
      merged.push(id);
    }
    return merged;
  }

  private async checkIncomingTopics(): Promise<void> {
    if (this.isLoggedIn) return;
    if (this.incomingPollInFlight) return;
    if (this.currentFilter !== '最新') return;
    if (this.topics.length === 0) return;

    const snapshotOrder: string = this.currentOrder;
    const snapshotCategoryIndex: number = this.currentCategoryIndex;
    const snapshotOverrideCategoryId: number = this.overrideCategory !== null ? (this.overrideCategory as Category).id : 0;
    const snapshotTags: string = this.selectedTags.join(',');

    this.incomingPollInFlight = true;
    try {
      const anchorId: number = this.getIncomingAnchorTopicId();
      if (anchorId > 0) {
        let orderParam: string | null = null;
        switch (this.currentOrder) {
          case '活跃度': orderParam = 'activity'; break;
          case '创建时间': orderParam = 'created'; break;
          case '点赞数': orderParam = 'likes'; break;
          case '浏览量': orderParam = 'views'; break;
          case '回复数': orderParam = 'posts'; break;
          case '参与者': orderParam = 'posters'; break;
          default: orderParam = null; break;
        }
        const ascendingParam: boolean | null = orderParam !== null ? this.orderAscending : null;

        let selectedCategory: Category | null = null;
        if (this.overrideCategory !== null) {
          selectedCategory = this.overrideCategory as Category;
        } else if (this.currentCategoryIndex > 0) {
          const pinned: Category[] = this.getPinnedCategories();
          if (this.currentCategoryIndex - 1 < pinned.length) {
            selectedCategory = pinned[this.currentCategoryIndex - 1];
          }
        }

        let categorySlug: string | null = null;
        let categoryId: number | null = null;
        let parentCategorySlug: string | null = null;
        if (selectedCategory !== null) {
          categorySlug = (selectedCategory as Category).slug;
          categoryId = (selectedCategory as Category).id;
          const pid: number | null = (selectedCategory as Category).parentCategoryId;
          if (pid !== null && pid > 0 && this.categoryMap.has(pid)) {
            parentCategorySlug = (this.categoryMap.get(pid) as Category).slug;
          }
        }

        const tagsParam: string[] | null = this.selectedTags.length > 0 ? [...this.selectedTags] : null;
        const apiClient: ApiClient = ApiClient.getInstance();
        const response: TopicListResponse = await apiClient.getFilteredTopics(
          'latest', 0, null, orderParam, ascendingParam,
          categorySlug, categoryId, parentCategorySlug, tagsParam,
          5000,
          5000,
          { silent: true, caller: 'TopicListPage.checkIncomingTopics' }
        );

        const polled: Topic[] = [];
        for (let i = 0; i < response.topics.length; i++) {
          const t: Topic = response.topics[i];
          if (!t.pinned) polled.push(t);
        }

        if (polled.length > 0) {
          let idx: number = -1;
          for (let i = 0; i < polled.length; i++) {
            if (polled[i].id === anchorId) { idx = i; break; }
          }

          let count: number = 0;
          const ids: number[] = [];
          if (idx > 0) {
            count = idx;
          } else if (idx < 0) {
            count = Math.min(polled.length, 20);
          }

          if (count > 0) {
            if (this.isIncomingPollContextUnchanged(snapshotOrder, snapshotCategoryIndex, snapshotOverrideCategoryId, snapshotTags)) {
              for (let i = 0; i < count; i++) ids.push(polled[i].id);

              // 轮询结果优先（顺序更符合列表插入预期），再合并现有 incoming（可能来自 MessageBus）
              const mergedIds: number[] = this.mergeUniqueIds(ids, this.incomingTopicIds);
              if (mergedIds.length > this.incomingTopicCount) {
                this.incomingTopicCount = mergedIds.length;
                this.incomingTopicIds = mergedIds;
              }
            }
          }
        }
      }
      // 成功一次就复位退避（哪怕没有新话题）
      this.incomingPollBackoffMs = INCOMING_POLL_INTERVAL_ANON_MS;
    } catch (err) {
      this.incomingPollBackoffMs = Math.min(
        INCOMING_POLL_MAX_BACKOFF_MS,
        Math.max(INCOMING_POLL_INTERVAL_ANON_MS, this.incomingPollBackoffMs * 2)
      );
      hilog.warn(
        0x0000,
        TAG,
        'Check incoming topics failed(backoff=%{public}dms): %{public}s',
        this.incomingPollBackoffMs,
        JSON.stringify(err)
      );
    } finally {
      this.incomingPollInFlight = false;
    }

    if (this.currentFilter === '最新' && !this.isLoggedIn) {
      if (this.incomingPollTimerId >= 0) return;
      this.incomingPollTimerId = setTimeout(() => {
        this.incomingPollTimerId = -1;
        this.checkIncomingTopics();
      }, this.incomingPollBackoffMs);
    }
  }

  private insertIncomingTopics(incoming: Topic[]): void {
    if (incoming.length === 0) return;

    // 移除列表中已存在的同 ID（处理“更新的话题”）
    const incomingIdMap: Map<number, boolean> = new Map();
    const incomingPinned: Topic[] = [];
    const incomingNormal: Topic[] = [];
    for (let i = 0; i < incoming.length; i++) {
      const t: Topic = incoming[i];
      incomingIdMap.set(t.id, true);
      if (t.pinned) {
        incomingPinned.push(t);
      } else {
        incomingNormal.push(t);
      }
    }

    const remaining: Topic[] = [];
    for (let i = 0; i < this.topics.length; i++) {
      const t: Topic = this.topics[i];
      if (incomingIdMap.has(t.id)) continue;
      remaining.push(t);
    }

    // pinned 仍保持在最前：仅插入到“前缀 pinned”之后（incoming 内的 pinned 也放进 pinned 区）
    let pinnedPrefixCount: number = 0;
    for (let i = 0; i < remaining.length; i++) {
      if (!remaining[i].pinned) break;
      pinnedPrefixCount = pinnedPrefixCount + 1;
    }

    const merged: Topic[] = [];
    for (let i = 0; i < pinnedPrefixCount; i++) {
      merged.push(remaining[i]);
    }
    for (let i = 0; i < incomingPinned.length; i++) {
      merged.push(incomingPinned[i]);
    }
    for (let i = 0; i < incomingNormal.length; i++) {
      merged.push(incomingNormal[i]);
    }
    for (let i = pinnedPrefixCount; i < remaining.length; i++) {
      merged.push(remaining[i]);
    }
    this.topics = merged;
  }

  private async onIncomingBannerClick(): Promise<void> {
    if (this.isLoadingIncoming) return;

    if (AppConstants.USE_MOCK_DATA) {
      if (this.incomingTopicCount <= 0) return;
      this.isLoadingIncoming = true;
      this.clearIncomingLoadTimer();

      const count: number = this.incomingTopicCount;
      this.incomingLoadTimerId = setTimeout(() => {
        this.incomingLoadTimerId = -1;

        const newTopics: Topic[] = this.makeMockIncomingTopics(count);
        this.insertIncomingTopics(newTopics);
        this.highlightIncomingTopicsOnce(newTopics.map((t: Topic) => t.id));
        this.incomingTopicCount = 0;
        this.incomingTopicIds = [];
        this.isLoadingIncoming = false;

        this.listScroller.scrollTo({
          xOffset: 0,
          yOffset: 0,
          animation: { duration: 300, curve: Curve.EaseOut }
        });
        this.maybeArmMockIncomingBanner();
      }, 180);
      return;
    }

    if (this.incomingTopicCount <= 0 || this.incomingTopicIds.length === 0) return;

    this.isLoadingIncoming = true;
    this.clearIncomingLoadTimer();
    this.clearIncomingPollTimer();

    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const ids: number[] = [...this.incomingTopicIds];
      const resp: TopicListResponse = await apiClient.getTopicsByIds(ids);
      const incoming: Topic[] = resp.topics;
      if (incoming.length > 0) {
        this.insertIncomingTopics(incoming);
        this.highlightIncomingTopicsOnce(incoming.map((t: Topic) => t.id));
      }

      try {
        const svc: TopicTrackingService = TopicTrackingService.getInstance();
        if (svc.isStarted()) {
          svc.clearIncoming(this.getCurrentQueryCategoryId());
        }
      } catch (_) {
      }
      this.incomingTopicIds = [];
      this.refreshTrackingUI();

      this.listScroller.scrollTo({
        xOffset: 0,
        yOffset: 0,
        animation: { duration: 300, curve: Curve.EaseOut }
      });

      // 游客态：依赖轮询/MessageBus 继续累计新话题，插入后及时重新挂起
      this.maybeArmIncomingBanner();
    } catch (err) {
      hilog.error(0x0000, TAG, 'Insert incoming topics failed: %{public}s', JSON.stringify(err));
    } finally {
      this.isLoadingIncoming = false;
    }
  }

  private makeMockIncomingTopics(count: number): Topic[] {
    const list: Topic[] = [];
    const now: Date = new Date();
    const baseCategoryId: string = this.topics.length > 0 ? this.topics[0].categoryId : '1';

    for (let i = 0; i < count; i++) {
      const t: Topic = new Topic();
      t.id = this.mockIncomingSeedId;
      this.mockIncomingSeedId = this.mockIncomingSeedId + 1;

      t.title = `【新】离线插入话题 #${t.id}`;
      t.slug = `mock-incoming-${t.id}`;
      t.categoryId = baseCategoryId;

      t.postsCount = 1 + (i % 3);
      t.replyCount = Math.max(0, t.postsCount - 1);
      t.views = 0;
      t.likeCount = 0;

      t.createdAt = now;
      t.lastPostedAt = now;
      t.lastPosterUsername = i % 2 === 0 ? 'system' : 'alice';

      t.unseen = true;
      t.unread = 0;
      t.lastReadPostNumber = 0;
      t.highestPostNumber = t.postsCount;

      list.push(t);
    }
    return list;
  }

  @Builder
  IncomingTopicBanner() {
    Row() {
      if (this.isLoadingIncoming) {
        LoadingProgress()
          .width(16)
          .height(16)
      } else {
        Row() {
          Text('↑')
            .fontSize(14)
            .fontColor($r('app.color.primary'))
          Text(`查看 ${this.incomingTopicCount} 个新的或更新的话题`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary'))
            .margin({ left: 8 })
        }
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.badge_background_light'))
    .borderRadius(8)
    .margin({ bottom: 12 })
    .onClick(() => {
      this.onIncomingBannerClick();
    })
  }

  private onRefreshFabClick(): void {
    // 复位 Header 折叠状态，并回到顶部后刷新
    this.clearHeaderSnapTimer();
    this.headerOffset = 0;
    this.listAtTop = true;
    this.fabRefreshMode = false;
    this.reportBarVisibility(true);

    // 清理“查看新话题”状态，避免刷新后残留
    if (this.currentFilter === '最新') {
      this.clearTrackedIncomingForCurrentContext();
    } else {
      this.resetIncomingBannerState();
    }

    this.listScroller.scrollTo({
      xOffset: 0,
      yOffset: 0,
      animation: { duration: 300, curve: Curve.EaseOut }
    });

    this.loadTopics(true);
  }

  @Builder
  HomeFab(visibility: number) {
    Button() {
      SymbolGlyph(this.fabRefreshMode ? $r('sys.symbol.arrow_clockwise') : $r('sys.symbol.plus'))
        .fontSize(22)
        .fontColor([$r('app.color.primary')])
    }
    .width(56)
    .height(56)
    .borderRadius(28)
    .backgroundColor($r('app.color.surface'))
    .shadow({ radius: 10, color: '#22000000', offsetX: 0, offsetY: 6 })
    .position({ x: '100%', y: '100%' })
    // 避开底部 TabBar（随 barVisibility 收起/展开）+ 预留 16 margin
    .translate({ x: -72, y: this.getHomeFabTranslateY(visibility) })
    .onClick(() => {
      if (this.fabRefreshMode) {
        this.onRefreshFabClick();
        return;
      }
      // TODO: 打开“发帖/创建话题”页面（待接入登录态与创建页）
      hilog.info(0x0000, TAG, 'Create topic clicked (UI only)');
    })
  }

  @Builder
  CompactFilterMenuBuilder() {
    Menu() {
      ForEach(this.getFilterOptions(), (opt: string) => {
        MenuItem() {
          Row() {
            if (this.currentFilter === opt) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(16)
                .fontColor([$r('app.color.primary')])
            } else {
              Blank().width(16).height(16)
            }
            Text(this.getFilterLabel(opt))
              .fontSize(14)
              .fontColor($r('app.color.on_surface'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: 8 })
          }
          .width('100%')
          .padding({ left: 12, right: 12 })
          .alignItems(VerticalAlign.Center)
        }
        .selected(false)
        .selectIcon(false)
        .height(40)
        .onChange((selected: boolean) => {
          if (selected) {
            this.updateFilter(opt);
          }
        })
      }, (opt: string) => opt)
    }
    .width(160)
    .backgroundColor($r('app.color.search_bar_background'))
    .borderRadius(12)
    .shadow({ radius: 10, color: '#22000000', offsetX: 0, offsetY: 6 })
  }

  @Builder
  CompactFilterEntry(progress: number) {
    Row() {
      SymbolGlyph($r('sys.symbol.line_3_horizontal'))
        .fontSize(16)
        .fontColor([$r('app.color.on_surface')])
        .margin({ right: 3 })
      Text(this.getFilterLabel(this.currentFilter))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface'))
    }
    .height(TAB_ROW_HEIGHT)
    .padding({ left: 8, right: 8, top: 7, bottom: 7 })
    .alignItems(VerticalAlign.Center)
    .margin({ right: 4 })
    .backgroundColor($r('app.color.search_bar_background'))
    .borderRadius(12)
    .opacity(this.clamp(0.65 + 0.35 * Math.sqrt(this.clamp(progress, 0, 1)), 0, 1))
    .bindMenu(this.CompactFilterMenuBuilder())
  }

  private ensureTrackingStarted(): void {
    if (AppConstants.USE_MOCK_DATA) return;
    if (!this.isLoggedIn && this.currentFilter !== '最新') return;

    const svc: TopicTrackingService = TopicTrackingService.getInstance();
    if (this.trackingListener === null) {
      this.trackingListener = () => {
        this.refreshTrackingUI();
      };
      try {
        svc.addListener(this.trackingListener);
      } catch (_) {
      }
    }

    svc.start(this.isLoggedIn)
      .then(() => {
        this.refreshTrackingUI();
      })
      .catch((err: Object) => {
        hilog.error(0x0000, TAG, 'Start topic tracking failed: %{public}s', JSON.stringify(err));
      });
  }

  private detachTrackingListener(): void {
    if (this.trackingListener === null) return;
    try {
      TopicTrackingService.getInstance().removeListener(this.trackingListener);
    } catch (_) {
    }
    this.trackingListener = null;
  }

  private refreshTrackingUI(): void {
    if (AppConstants.USE_MOCK_DATA) return;
    const svc: TopicTrackingService = TopicTrackingService.getInstance();
    const categoryId: number | null = this.getCurrentQueryCategoryId();
    if (this.isLoggedIn) {
      this.trackedNewCount = svc.countNew(categoryId);
      this.trackedUnreadCount = svc.countUnread(categoryId);
    } else {
      this.trackedNewCount = 0;
      this.trackedUnreadCount = 0;
    }

    if (this.currentFilter === '最新') {
      const busCount: number = svc.incomingCount(categoryId);
      const busIds: number[] = busCount > 0 ? svc.incomingTopicIds(categoryId) : [];
      if (this.isLoggedIn) {
        this.incomingTopicCount = busCount;
        this.incomingTopicIds = busIds;
      } else {
        if (busIds.length > 0) {
          const mergedIds: number[] = [];
          const seen: Map<number, boolean> = new Map();
          // 保留轮询先到的顺序，补齐 MessageBus 可能更早到达的增量
          for (let i = 0; i < this.incomingTopicIds.length; i++) {
            const id: number = this.incomingTopicIds[i];
            if (seen.has(id)) continue;
            seen.set(id, true);
            mergedIds.push(id);
          }
          for (let i = 0; i < busIds.length; i++) {
            const id: number = busIds[i];
            if (seen.has(id)) continue;
            seen.set(id, true);
            mergedIds.push(id);
          }
          this.incomingTopicIds = mergedIds;
        }
        this.incomingTopicCount = this.incomingTopicIds.length;
      }
    }

    // 对齐安卓：当 MessageBus/tracking 的 highest_post_number 增长时，列表内已有话题的回复数也应即时变大
    this.syncTopicCountsFromTracking(svc);
  }

  private syncTopicCountsFromTracking(svc: TopicTrackingService): void {
    if (this.topics.length === 0) return;
    let changed: boolean = false;
    for (let i = 0; i < this.topics.length; i++) {
      const t: Topic = this.topics[i];
      if (t.id <= 0) continue;
      const trackedHighest: number = svc.getHighestPostNumber(t.id);
      if (trackedHighest <= 0) continue;

      const effectivePostsCount: number = Math.max(t.postsCount, t.highestPostNumber, trackedHighest, t.replyCount + 1);
      const effectiveReplyCount: number = Math.max(t.replyCount, Math.max(0, effectivePostsCount - 1));

      if (effectivePostsCount > t.postsCount) {
        t.postsCount = effectivePostsCount;
        changed = true;
      }
      if (effectivePostsCount > t.highestPostNumber) {
        t.highestPostNumber = effectivePostsCount;
        changed = true;
      }
      if (effectiveReplyCount > t.replyCount) {
        t.replyCount = effectiveReplyCount;
        changed = true;
      }
    }

    if (changed) {
      // 触发列表重绘（Topic 是普通 class，直接改字段不一定触发 UI 更新）
      this.topics = [...this.topics];
    }
  }

  private getFilterOptions(): string[] {
    return this.isLoggedIn ? SORT_FILTER_OPTIONS_LOGGED_IN : SORT_FILTER_OPTIONS;
  }

  private getFilterLabel(filter: string): string {
    if (filter === '新话题') {
      return this.trackedNewCount > 0 ? `${filter} (${this.trackedNewCount})` : filter;
    }
    if (filter === '未读完') {
      return this.trackedUnreadCount > 0 ? `${filter} (${this.trackedUnreadCount})` : filter;
    }
    return filter;
  }

  private getOrderLabel(order: string): string {
    if (order === this.currentOrder && order !== '默认') {
      return this.orderAscending ? `${order} ↑` : `${order} ↓`;
    }
    return order;
  }

  private getOpAvatarUrl(topic: Topic): string {
    if (topic.posters.length > 0) {
      const op = topic.posters[0];
      if (op.user !== null) {
        return UrlUtils.getAvatarUrl(op.user.avatarTemplate, 68);
      }
    }
    return '';
  }

  private getCategory(topic: Topic): Category | null {
    const catId: number = parseInt(topic.categoryId);
    if (isNaN(catId)) return null;
    if (this.categoryMap.has(catId)) {
      return this.categoryMap.get(catId) as Category;
    }
    return null;
  }

  private getCategoryColor(category: Category | null): string {
    if (category === null || category.color.length === 0) return '#999999';
    if (category.color.startsWith('#')) return category.color;
    return `#${category.color}`;
  }

  private getCurrentQueryCategoryId(): number | null {
    if (this.overrideCategory !== null) {
      return (this.overrideCategory as Category).id;
    }
    if (this.currentCategoryIndex > 0) {
      const pinned: Category[] = this.getPinnedCategories();
      if (this.currentCategoryIndex - 1 < pinned.length) {
        return pinned[this.currentCategoryIndex - 1].id;
      }
    }
    return null;
  }

  private openCategorySheet(): void {
    this.isEditingCategory = false;
    this.sheetMode = SHEET_CATEGORY;
    this.isSheetVisible = true;
  }

  private openTagSheet(): void {
    this.draftSelectedTags = [...this.selectedTags];
    this.sheetMode = SHEET_TAG;
    this.isSheetVisible = true;
  }

  private closeSheet(): void {
    this.isSheetVisible = false;
    this.sheetMode = SHEET_NONE;
    this.isEditingCategory = false;
  }

  private openTopicPreview(topic: Topic): void {
    const category: Category | null = this.getCategory(topic);
    this.previewTopic = topic;
    this.previewCategory = category;
    this.previewParentCategory = category !== null ? this.getParentCategory(category as Category) : null;
    this.isTopicPreviewVisible = true;
  }

  private closeTopicPreview(): void {
    this.isTopicPreviewVisible = false;
    this.previewTopic = null;
    this.previewCategory = null;
    this.previewParentCategory = null;
  }

  private openTopicFromPreview(topic: Topic): void {
    this.closeTopicPreview();
    this.onTopicClick(topic);
  }

  @Builder
  TopicPreviewOverlay() {
    if (this.isTopicPreviewVisible && this.previewTopic !== null) {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.closeTopicPreview();
        })

        TopicPreviewDialog({
          topic: this.previewTopic as Topic,
          category: this.previewCategory,
          parentCategory: this.previewParentCategory,
          onClose: () => {
            this.closeTopicPreview();
          },
          onOpen: (topic: Topic) => {
            this.openTopicFromPreview(topic);
          }
        })
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  TabItem(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(this.currentCategoryIndex === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentCategoryIndex === index ? $r('app.color.primary') : $r('app.color.on_surface_secondary'))
        .margin({ bottom: 4 })
      
      // 底部下划线指示器
      if (this.currentCategoryIndex === index) {
        Rect()
          .width(32)
          .height(3)
          .radius(2)
          .fill($r('app.color.primary'))
      } else {
        Rect()
          .width(32)
          .height(3)
          .fill(Color.Transparent)
      }
    }
    .padding({ left: 12, right: 12, top: 6 })
    .onClick(() => {
      this.currentCategoryIndex = index;
      this.overrideCategory = null;
      // 切换 Tab 时，优先展示该分类完整列表（保持 tags 选中不变，仅刷新数据）
      this.resetIncomingBannerState();
      this.refreshTrackingUI();
      this.maybeArmIncomingBanner();
      this.loadTopics(true);
    })
  }

  private updateFilter(next: string): void {
    if (next === this.currentFilter) return;
    this.currentFilter = next;
    this.persistSortPreferences();
    this.ensureTrackingStarted();
    this.refreshTrackingUI();
    this.maybeArmIncomingBanner();
    this.loadTopics(true);
  }

  private updateOrder(next: string): void {
    if (next === this.currentOrder) {
      // 再次点击已选中的排序项时：切换升/降序（仅非“默认”）
      if (next !== '默认') {
        this.orderAscending = !this.orderAscending;
        this.persistSortPreferences();
        this.ensureTrackingStarted();
        this.refreshTrackingUI();
        this.maybeArmIncomingBanner();
        this.loadTopics(true);
      }
      return;
    }

    this.currentOrder = next;
    // 选择新排序字段：默认降序（对齐 FluxDO）
    this.orderAscending = false;
    this.persistSortPreferences();
    this.ensureTrackingStarted();
    this.refreshTrackingUI();
    this.maybeArmIncomingBanner();
    this.loadTopics(true);
  }

  @Builder
  SubcategoryMenu(parentCategory: Category, forAdd: boolean) {
    Menu() {
      // 全部（父分类）
      MenuItem() {
        Row() {
          this.MenuCategoryIcon(parentCategory)
          Text(forAdd ? `${parentCategory.name}（全部）` : '全部')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
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
            if (forAdd) {
              this.addPinnedCategory(parentCategory.id);
            } else {
              this.openCategoryFromSheet(parentCategory);
            }
          }
        })

      // 子分类
      ForEach(this.getSubcategories(parentCategory.id, forAdd), (sub: Category) => {
        MenuItem() {
          Row() {
            this.MenuCategoryIcon(sub)
            Text(sub.name)
              .fontSize(14)
              .fontColor($r('app.color.on_surface'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
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
              if (forAdd) {
                this.addPinnedCategory(sub.id);
              } else {
                this.openCategoryFromSheet(sub);
              }
            }
          })
      }, (sub: Category) => sub.id.toString())
    }
    .width(220)
    .backgroundColor($r('app.color.search_bar_background'))
    .borderRadius(16)
    .shadow({ radius: 10, color: '#22000000', offsetX: 0, offsetY: 6 })
  }

  @Builder
  MenuCategoryIcon(category: Category) {
    CategoryIcon({
      category: category,
      parent: this.getParentCategory(category),
      iconSize: 20,
      color: this.getCategoryColor(category),
      preferImage: false
    })
      .margin({ right: 10 })
  }

  @Builder
  CategorySheetBuilder() {
    Column() {
      // 拖动柄
      Column() {
        Rect()
          .width(32)
          .height(4)
          .radius(2)
          .fill($r('app.color.divider_light'))
      }
      .width('100%')
      .padding({ top: 12 })
      .alignItems(HorizontalAlign.Center)

      // 标题栏
      Row() {
        if (this.isEditingCategory) {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(18)
              .fontColor([$r('app.color.on_surface')])
          }
          .width(32)
          .height(32)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.isEditingCategory = false;
          })

          Text('编辑我的分类')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .margin({ left: 8 })
            .layoutWeight(1)
        } else {
          Text('浏览分类')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .layoutWeight(1)

          Row() {
            SymbolGlyph($r('sys.symbol.pencil_line'))
              .fontSize(14)
              .fontColor([$r('app.color.primary')])
              .margin({ right: 4 })
            Text('编辑')
              .fontSize(13)
              .fontColor($r('app.color.primary'))
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.isEditingCategory = true;
          })
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 12 })
      .alignItems(VerticalAlign.Center)

      Divider().color($r('app.color.skeleton_base')).strokeWidth(0.5).margin({ left: 16, right: 16 })

      Scroll() {
        Column() {
          if (this.isEditingCategory) {
            // "编辑我的分类" 视图
            Row() {
              Text('已添加')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.on_surface'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16 })

            Text('拖拽排序，点击移除')
              .fontSize(12)
              .fontColor($r('app.color.on_surface_tertiary'))
              .width('100%')
              .padding({ left: 16, right: 16, top: 4, bottom: 12 })

            if (this.pinnedCategoryIds.length === 0) {
              Text('点击下方分类添加到标签栏')
                .fontSize(13)
                .fontColor($r('app.color.on_surface_tertiary'))
                .textAlign(TextAlign.Center)
                .width('100%')
                .margin({ top: 10, bottom: 24 })
            } else {
              // 已添加列表（支持拖拽排序）
              List() {
                ForEach(this.pinnedCategoryIds, (id: number) => {
                  ListItem() {
                    Row() {
                      SymbolGlyph($r('sys.symbol.line_3_horizontal'))
                        .fontSize(16)
                        .fontColor([$r('app.color.on_surface_tertiary')])
                        .margin({ right: 10 })

                      if (this.hasCategoryById(id)) {
                        Circle()
                          .width(8)
                          .height(8)
                          .fill(this.getCategoryColorById(id))
                          .margin({ right: 8 })

                        Text(this.getCategoryNameById(id))
                          .fontSize(14)
                          .fontColor($r('app.color.on_surface'))
                          .layoutWeight(1)
                      } else {
                        Text(this.getCategoryNameById(id))
                          .fontSize(14)
                          .fontColor($r('app.color.on_surface'))
                          .layoutWeight(1)
                      }

                      Text('移除')
                        .fontSize(13)
                        .fontColor($r('app.color.primary'))
                        .onClick(() => {
                          this.removePinnedCategory(id);
                        })
                    }
                    .width('100%')
                    .height(46)
                    .padding({ left: 16, right: 16 })
                    .alignItems(VerticalAlign.Center)
                  }
                }, (id: number) => id.toString())
                .onMove((from: number, to: number) => {
                  this.movePinnedCategory(from, to);
                })
              }
              .width('100%')
              .backgroundColor(Color.Transparent)
              .divider({ strokeWidth: 0.5, color: $r('app.color.skeleton_base'), startMargin: 16, endMargin: 16 })
              .padding({ top: 4, bottom: 16 })
              .scrollBar(BarState.Off)
            }
            
            Divider().color($r('app.color.skeleton_base')).strokeWidth(0.5).margin({ left: 16, right: 16 })

            Row() {
              Text('可添加')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.on_surface'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })

            this.CategoryGrid(true)
          } else {
            // "浏览分类" 视图
            Row() {
              Text('我的分类')
                .fontSize(13)
                .fontColor($r('app.color.on_surface_secondary'))
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 16 })

            if (this.pinnedCategoryIds.length === 0) {
              Text('点击“编辑”添加常用分类到标签栏')
                .fontSize(12)
                .fontColor($r('app.color.on_surface_tertiary'))
                .width('100%')
                .padding({ left: 20, right: 20, top: 8, bottom: 16 })
            } else {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.getPinnedCategories(), (c: Category) => {
                  this.QuickChip(c)
                })
              }
              .width('100%')
              .padding({ left: 20, right: 20, top: 10, bottom: 16 })
            }

            Row() {
              Text('全部分类')
                .fontSize(13)
                .fontColor($r('app.color.on_surface_secondary'))
            }
            .width('100%')
            .padding({ left: 20, right: 20, bottom: 16 })

            this.CategoryGrid(false)
          }
        }
        .width('100%')
        .padding({ bottom: 40 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  QuickChip(category: Category) {
    Row() {
      CategoryIcon({
        category: category,
        parent: this.getParentCategory(category),
        iconSize: 14,
        color: this.getCategoryColor(category),
        preferImage: false
      })
        .margin({ right: 6 })
      Text(category.name)
        .fontSize(13)
        .fontColor($r('app.color.on_surface'))
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor(this.hexWithAlpha(this.getCategoryColor(category), 0.08))
    .border({ width: 1, color: this.hexWithAlpha(this.getCategoryColor(category), 0.2) })
    .borderRadius(6)
    .margin({ right: 8, bottom: 8 })
    .onClick(() => {
      this.openCategoryFromSheet(category);
    })
  }

  @Builder
  CategoryGridIcon(category: Category) {
    CategoryIcon({
      category: category,
      parent: this.getParentCategory(category),
      iconSize: 24,
      color: this.getCategoryColor(category),
      preferImage: true
    })
  }

  @Builder
  CategoryGrid(forAdd: boolean) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(forAdd ? this.getAddableTopLevelCategories() : this.getTopLevelCategories(), (cat: Category) => {
        if (this.hasSubcategories(cat.id, forAdd)) {
          Column() {
            // 圆形图标区
            Stack() {
              Circle()
                .width(48)
                .height(48)
                .fill($r('app.color.search_bar_background'))
               
              this.CategoryGridIcon(cat)
            }
            .margin({ bottom: 6 })

            // 文本与下级菜单箭头
            Row() {
              Text(cat.name)
                .fontSize(12)
                .fontColor($r('app.color.on_surface'))
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(14)
                .fontColor([$r('app.color.on_surface_tertiary')])
                .margin({ left: 2 })
            }
          }
          .width('25%') // 一排大概4个
          .margin({ bottom: 16 })
          .alignItems(HorizontalAlign.Center)
          .bindMenu(this.SubcategoryMenu(cat, forAdd))
        } else {
          Column() {
            // 圆形图标区
            Stack() {
              Circle()
                .width(48)
                .height(48)
                .fill($r('app.color.search_bar_background'))
               
              this.CategoryGridIcon(cat)
            }
            .margin({ bottom: 6 })

            // 文本
            Row() {
              Text(cat.name)
                .fontSize(12)
                .fontColor($r('app.color.on_surface'))
            }
          }
          .width('25%') // 一排大概4个
          .margin({ bottom: 16 })
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            if (forAdd) {
              this.addPinnedCategory(cat.id);
            } else {
              this.openCategoryFromSheet(cat);
            }
          })
        }
      }, (cat: Category) => cat.id.toString())
    }
    .padding({ left: 12, right: 12 })
  }

  private removeTag(tagName: string): void {
    const next: string[] = [];
    for (let i = 0; i < this.selectedTags.length; i++) {
      const t: string = this.selectedTags[i];
      if (t !== tagName) next.push(t);
    }
    this.selectedTags = next;
    this.persistSelectedTags();
    this.refreshTrackingUI();
    this.loadTopics(true);
    this.maybeArmIncomingBanner();
  }

  private toggleTag(tagName: string): void {
    const idx: number = this.selectedTags.indexOf(tagName);
    if (idx >= 0) {
      this.removeTag(tagName);
      return;
    }
    this.selectedTags = [...this.selectedTags, tagName];
    this.persistSelectedTags();
    this.refreshTrackingUI();
    this.loadTopics(true);
    this.maybeArmIncomingBanner();
  }

  private removeDraftTag(tagName: string): void {
    const next: string[] = [];
    for (let i = 0; i < this.draftSelectedTags.length; i++) {
      const t: string = this.draftSelectedTags[i];
      if (t !== tagName) next.push(t);
    }
    this.draftSelectedTags = next;
  }

  private toggleDraftTag(tagName: string): void {
    const idx: number = this.draftSelectedTags.indexOf(tagName);
    if (idx >= 0) {
      this.removeDraftTag(tagName);
      return;
    }
    this.draftSelectedTags = [...this.draftSelectedTags, tagName];
  }

  @Builder
  TagSheetBuilder() {
    TagSelectionSheet({
      title: '选择标签',
      doneText: '确定',
      availableTags: this.availableTags,
      selectedTags: this.draftSelectedTags,
      categoryId: this.getCurrentQueryCategoryId(),
      maxTags: 5,
      onToggleTag: (t: string) => {
        this.toggleDraftTag(t);
      },
      onDone: () => {
        this.selectedTags = [...this.draftSelectedTags];
        this.persistSelectedTags();
        this.closeSheet();
        this.refreshTrackingUI();
        this.loadTopics(true);
        this.maybeArmIncomingBanner();
      },
      onClear: () => {
        this.draftSelectedTags = [];
      }
    })
  }

  @Builder
  BottomSheetBuilder() {
    if (this.sheetMode === SHEET_TAG) {
      this.TagSheetBuilder()
    } else {
      this.CategorySheetBuilder()
    }
  }

  build() {
    Stack() {
      Column() {
        // ─── 1. 搜索栏 ───
        if (this.getSearchProgress() < 1) {
          Column() {
            Row() {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(18)
                .fontColor([$r('app.color.on_surface_tertiary')])
                .margin({ right: 8 })
              Text($r('app.string.search_hint'))
                .fontSize(15)
                .fontColor($r('app.color.on_surface_tertiary'))
                .layoutWeight(1)
            }
            .width('100%')
            .height(40)
            .padding({ left: 16, right: 16 })
            .backgroundColor($r('app.color.search_background'))
            .borderRadius(20)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              RouterManager.pushPath(RouteConstants.PAGE_SEARCH);
            })
          }
          .width('100%')
          .height(SEARCH_BAR_HEIGHT * (1 - this.getSearchProgress()))
          .opacity(1 - this.getSearchProgress())
          .clip(true)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        }

        // ─── 2. 分类 Tab 行 ───
        Row() {
          // 左侧分类横向滚动
          Scroll() {
            Row() {
              this.TabItem('全部', 0)
              ForEach(this.getPinnedCategories(), (cat: Category, index: number) => {
                this.TabItem(cat.name, index + 1)
              })
            }
            .height('100%')
            .alignItems(VerticalAlign.Bottom) // "全部"字样下沉
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .height(TAB_ROW_HEIGHT)
          .align(Alignment.BottomStart) // 左对齐

          // 排序/筛选栏折叠后，在 Tab 行右侧渐显一个紧凑筛选入口
          if (this.getSortProgress() > 0) {
            this.CompactFilterEntry(this.getSortProgress())
          }

          // 右侧分类管理按钮
          Row() {
            SymbolGlyph($r('sys.symbol.line_3_horizontal'))
              .fontSize(18)
              .fontColor([$r('app.color.on_surface_secondary')])
          }
            .padding({ left: 8, right: 8 })
            .height(TAB_ROW_HEIGHT)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.openCategorySheet();
            })
        }
        .width('100%')
        .height(TAB_ROW_HEIGHT)
        .alignItems(VerticalAlign.Bottom)

        Divider().color($r('app.color.divider_light')).strokeWidth(1).margin({ left: 16, right: 16 })

        // ─── 3. 排序筛选栏 ───
        if (this.getSortProgress() < 1) {
          Row() {
            PillMenuButton({
              value: this.currentFilter,
              valueLabel: this.getFilterLabel(this.currentFilter),
              options: this.getFilterOptions(),
              menuWidth: 160,
              rightMargin: 8,
              optionLabelBuilder: (opt: string): string => this.getFilterLabel(opt),
              onValueChange: (v: string) => {
                this.updateFilter(v);
              }
            })

            PillMenuButton({
              value: this.currentOrder,
              valueLabel: this.getOrderLabel(this.currentOrder),
              options: SORT_ORDER_OPTIONS,
              menuWidth: 190,
              rightMargin: 8,
              optionLabelBuilder: (opt: string): string => this.getOrderLabel(opt),
              onValueChange: (v: string) => {
                this.updateOrder(v);
              }
            })

            // 标签：默认只显示“+🏷”按钮；选择后显示 chips（可横滑）
            if (this.selectedTags.length === 0) {
              PillIconButton({
                rightSymbol: $r('sys.symbol.label'),
                onAction: () => {
                  this.openTagSheet();
                }
              })
            } else {
              Scroll() {
                Row() {
                  ForEach(this.selectedTags, (t: string) => {
                    TagChip({
                      tagName: t,
                      onRemove: () => {
                        this.removeTag(t);
                      }
                    })
                  })
                  PillIconButton({
                    rightSymbol: $r('sys.symbol.label'),
                    onAction: () => {
                      this.openTagSheet();
                    }
                  })
                }
                .alignItems(VerticalAlign.Center)
                .justifyContent(FlexAlign.Start)
                // 关键：让内容容器至少占满可用宽度，避免 Scroll 子节点在剩余空间内被“居中”导致中间留空
                // 同时允许内容在超出时自然扩展，以支持横向滚动
                .constraintSize({ minWidth: '100%' })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .layoutWeight(1)
            }
          }
          .width('100%')
          .height(SORT_BAR_HEIGHT * (1 - this.getSortProgress()))
          .opacity(1 - this.getSortProgress())
          .clip(true)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        }

        // ─── 4. 话题列表 ───
        if (this.isLoading) {
          TopicListSkeleton({ itemCount: 8 })
            .width('100%')
            .layoutWeight(1)
        } else if (this.errorMessage.length > 0) {
          Column() {
            ErrorView({
              title: '加载失败',
              message: this.errorMessage,
              showRetry: true,
              onRetry: () => {
                this.resetIncomingBannerState();
                this.loadTopics(true);
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Refresh({ refreshing: false }) {
            List({ scroller: this.listScroller }) {
              if (this.incomingTopicCount > 0 && this.currentFilter === '最新') {
                ListItem() {
                  this.IncomingTopicBanner()
                }
              }

              ForEach(this.topics, (topic: Topic) => {
                ListItem() {
                  if (topic.pinned) {
                    CompactTopicCard({
                      topic: topic,
                      category: this.getCategory(topic),
                      isHighlighted: this.isTopicHighlighted(topic.id),
                      enableLongPress: this.enableLongPressPreview,
                      onCardClick: (t: Topic) => {
                        this.onTopicClick(t);
                      },
                      onCardLongPress: (t: Topic) => {
                        this.openTopicPreview(t);
                      }
                    })
                  } else {
                    TopicCard({
                      topic: topic,
                      category: this.getCategory(topic),
                      opAvatarUrl: this.getOpAvatarUrl(topic),
                      isHighlighted: this.isTopicHighlighted(topic.id),
                      enableLongPress: this.enableLongPressPreview,
                      onCardClick: (t: Topic) => {
                        this.onTopicClick(t);
                      },
                      onCardLongPress: (t: Topic) => {
                        this.openTopicPreview(t);
                      }
                    })
                  }
                }
              }, (topic: Topic) => topic.id.toString())

              if (this.isLoadingMore) {
                ListItem() {
                  Row() {
                    LoadingProgress().width(20).height(20)
                    Text('加载中...').fontSize(13).fontColor($r('app.color.on_surface_tertiary')).margin({ left: 8 })
                  }
                  .width('100%')
                  .height(48)
                  .justifyContent(FlexAlign.Center)
                }
              }

              // 让列表内容可滚动到“悬浮胶囊 TabBar”背后：仅在列表末尾预留空间，避免页面底部永久留白
              ListItem() {
                Row() {
                }
                .width('100%')
                .height(this.getFloatingTabBarReservedBottomForVisibilityVp(this.computeBarVisibility()))
              }
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 12, right: 12 })
            .backgroundColor($r('app.color.background'))
            .onReachStart(() => {
              this.listAtTop = true;
              if (this.fabRefreshMode) {
                this.fabRefreshMode = false;
              }
            })
            .onScrollFrameBegin((offset: number, state: ScrollState) => {
              // 两段折叠：先消费 offset 折叠/展开 Header，再把剩余 offset 交给 List 滚动
              let remain: number = offset;

              if (offset > 0) {
                const canCollapse: number = COLLAPSIBLE_HEIGHT - this.headerOffset;
                if (canCollapse > 0) {
                  const consume: number = Math.min(offset, canCollapse);
                  this.headerOffset = this.headerOffset + consume;
                  remain = offset - consume;
                }
              } else if (offset < 0) {
                // 仅在 List 已到顶时才展开 Header，避免中段滚动时 Header 误展开
                if (this.listAtTop && this.headerOffset > 0) {
                  const consume: number = Math.min(-offset, this.headerOffset);
                  this.headerOffset = this.headerOffset - consume;
                  remain = offset + consume;
                }
              }

              // Header 折叠状态变化 → 通知父级更新底部 TabBar 可见性
              this.reportBarVisibility(false);

              // FAB：向上滚动（朝顶部方向）→ 刷新模式；向下滚动 → 创建模式
              if (offset < -0.01) {
                if (!this.listAtTop && !this.fabRefreshMode) {
                  this.fabRefreshMode = true;
                }
              } else if (offset > 0.01) {
                if (this.fabRefreshMode) {
                  this.fabRefreshMode = false;
                }
              }

              if (remain > 0.01) {
                this.listAtTop = false;
              }

              // 松手后吸附：只允许停在 0 或 100
              if (this.headerOffset > 0 && this.headerOffset < COLLAPSIBLE_HEIGHT) {
                this.scheduleHeaderSnap();
              } else {
                this.clearHeaderSnapTimer();
              }
              return { offsetRemain: remain };
            })
            .onReachEnd(() => {
              this.loadTopics(false);
            })
          }
          .onRefreshing(() => {
            this.resetIncomingBannerState();

            // 对齐 FluxDO：下拉刷新后清除当前 tab 的 incoming（避免 banner 反复显示旧计数）
            if (this.currentFilter === '最新') {
              try {
                const svc: TopicTrackingService = TopicTrackingService.getInstance();
                if (svc.isStarted()) {
                  svc.clearIncoming(this.getCurrentQueryCategoryId());
                }
              } catch (_) {
              }
            }

            this.loadTopics(true);
            this.maybeArmIncomingBanner();
          })
          .layoutWeight(1)
        }
      }
      // 全局沉浸式：为顶部状态栏安全区预留 padding，避免内容被挖孔/状态栏遮挡
      .padding({ top: WindowManager.getSystemAvoidAreaTopVp() })
      .width('100%')
      .height('100%')

      // 登录态：右下浮动按钮（创建/刷新切换）
      if (!this.isLoading && this.errorMessage.length === 0 && this.isLoggedIn) {
        this.HomeFab(this.computeBarVisibility())
      }

      this.TopicPreviewOverlay()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .bindSheet($$this.isSheetVisible, this.BottomSheetBuilder, {
      height: SheetSize.LARGE,
      dragBar: false,
      showClose: false,
      backgroundColor: $r('app.color.surface')
    })
  }

  private getTopLevelCategories(): Category[] {
    return this.categories.filter((c: Category): boolean =>
      c.parentCategoryId === null || c.parentCategoryId === 0
    );
  }

  private getParentCategory(category: Category): Category | null {
    const pid: number | null = category.parentCategoryId;
    if (pid === null || pid === 0) return null;
    if (this.categoryMap.has(pid)) {
      return this.categoryMap.get(pid) as Category;
    }
    return null;
  }

  private getCategoryLogoUrl(category: Category): string {
    const own: string | null = category.uploadedLogo;
    if (own !== null && (own as string).length > 0) {
      return own as string;
    }

    const parent: Category | null = this.getParentCategory(category);
    if (parent !== null) {
      const p: string | null = (parent as Category).uploadedLogo;
      if (p !== null && (p as string).length > 0) {
        return p as string;
      }
    }
    return '';
  }

  private getPinnedCategories(): Category[] {
    if (this.pinnedCategoryIds.length === 0) return [];
    const pinned: Category[] = [];
    for (let i = 0; i < this.pinnedCategoryIds.length; i++) {
      const id: number = this.pinnedCategoryIds[i];
      const c: Category | null = this.getCategoryById(id);
      if (c !== null) pinned.push(c as Category);
    }
    return pinned;
  }

  private getAddableTopLevelCategories(): Category[] {
    const allTop: Category[] = this.getTopLevelCategories();
    const list: Category[] = [];
    for (let i = 0; i < allTop.length; i++) {
      const c: Category = allTop[i];
      if (this.pinnedCategoryIds.indexOf(c.id) < 0) {
        list.push(c);
      }
    }
    return list;
  }

  private getSubcategories(parentId: number, excludePinned: boolean): Category[] {
    const subs: Category[] = [];
    for (let i = 0; i < this.categories.length; i++) {
      const c: Category = this.categories[i];
      if (c.parentCategoryId !== null && c.parentCategoryId === parentId) {
        if (!excludePinned || this.pinnedCategoryIds.indexOf(c.id) < 0) {
          subs.push(c);
        }
      }
    }
    return subs;
  }

  private hasSubcategories(parentId: number, excludePinned: boolean): boolean {
    for (let i = 0; i < this.categories.length; i++) {
      const c: Category = this.categories[i];
      if (c.parentCategoryId !== null && c.parentCategoryId === parentId) {
        if (!excludePinned || this.pinnedCategoryIds.indexOf(c.id) < 0) {
          return true;
        }
      }
    }
    return false;
  }

  private getCategoryById(id: number): Category | null {
    if (this.categoryMap.has(id)) {
      return this.categoryMap.get(id) as Category;
    }
    return null;
  }

  private hasCategoryById(id: number): boolean {
    return this.getCategoryById(id) !== null;
  }

  private getCategoryNameById(id: number): string {
    const c: Category | null = this.getCategoryById(id);
    if (c !== null && (c as Category).name.length > 0) {
      return (c as Category).name;
    }
    return `分类 ${id}`;
  }

  private getCategoryColorById(id: number): string {
    const c: Category | null = this.getCategoryById(id);
    return this.getCategoryColor(c);
  }

  private switchToPinnedCategory(categoryId: number): void {
    const idx: number = this.pinnedCategoryIds.indexOf(categoryId);
    if (idx >= 0) {
      this.currentCategoryIndex = idx + 1;
      this.overrideCategory = null;
    }
  }

  private openCategoryFromSheet(category: Category): void {
    this.closeSheet();
    RouterManager.pushPath(RouteConstants.PAGE_CATEGORY_TOPIC_LIST, category as Object);
  }

  private addPinnedCategory(categoryId: number): void {
    if (this.pinnedCategoryIds.indexOf(categoryId) >= 0) return;
    this.pinnedCategoryIds = [...this.pinnedCategoryIds, categoryId];
    this.persistPinnedCategories();
  }

  private removePinnedCategory(categoryId: number): void {
    const currentPinnedId: number | null = (this.currentCategoryIndex > 0 && this.currentCategoryIndex - 1 < this.pinnedCategoryIds.length)
      ? this.pinnedCategoryIds[this.currentCategoryIndex - 1] : null;

    const next: number[] = [];
    for (let i = 0; i < this.pinnedCategoryIds.length; i++) {
      const id: number = this.pinnedCategoryIds[i];
      if (id !== categoryId) next.push(id);
    }
    this.pinnedCategoryIds = next;
    this.persistPinnedCategories();

    if (currentPinnedId !== null) {
      const newIndex: number = this.pinnedCategoryIds.indexOf(currentPinnedId);
      this.currentCategoryIndex = newIndex >= 0 ? newIndex + 1 : 0;
    } else {
      this.currentCategoryIndex = 0;
    }

    if (currentPinnedId === categoryId) {
      this.overrideCategory = null;
      this.resetIncomingBannerState();
      this.refreshTrackingUI();
      this.loadTopics(true);
      this.maybeArmIncomingBanner();
    }
  }

  private movePinnedCategory(from: number, to: number): void {
    if (from === to) return;

    const currentPinnedId: number | null = (this.currentCategoryIndex > 0 && this.currentCategoryIndex - 1 < this.pinnedCategoryIds.length)
      ? this.pinnedCategoryIds[this.currentCategoryIndex - 1] : null;

    const arr: number[] = [...this.pinnedCategoryIds];
    const tmp: number[] = arr.splice(from, 1);
    if (tmp.length > 0) {
      arr.splice(to, 0, tmp[0]);
    }
    this.pinnedCategoryIds = arr;
    this.persistPinnedCategories();

    if (currentPinnedId !== null) {
      const newIndex: number = this.pinnedCategoryIds.indexOf(currentPinnedId);
      this.currentCategoryIndex = newIndex >= 0 ? newIndex + 1 : 0;
    }
  }

  private hexWithAlpha(hex: string, alpha: number): string {
    let colorHex: string = hex;
    if (colorHex.startsWith('#')) {
      colorHex = colorHex.substring(1);
    }
    if (colorHex.length !== 6) {
      return hex;
    }
    const alphaHex: string = Math.round(alpha * 255).toString(16).padStart(2, '0');
    return `#${alphaHex}${colorHex}`;
  }
}
