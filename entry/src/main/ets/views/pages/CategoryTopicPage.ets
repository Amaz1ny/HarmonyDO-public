import { hilog } from '@kit.PerformanceAnalysisKit';
import { Topic, TopicListResponse, Tag } from '../../models/Topic';
import { Category, SiteResponse } from '../../models/Category';
import { ApiClient } from '../../services/network/ApiClient';
import { AuthService } from '../../services/auth/AuthService';
import { TopicCard, CompactTopicCard } from '../components/TopicCard';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';
import { TopicPreviewDialog } from '../components/TopicPreviewDialog';
import { UrlUtils } from '../../common/utils/UrlUtils';
import { RouterManager, RouteConstants } from '../../common/utils/RouterManager';
import { PillIconButton, PillMenuButton, SORT_FILTER_OPTIONS, SORT_FILTER_OPTIONS_LOGGED_IN, SORT_ORDER_OPTIONS } from '../components/PillControls';
import { DEFAULT_AVAILABLE_TAGS, TagChip, TagSelectionSheet } from '../components/TagControls';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { WindowManager } from '../../common/utils/WindowManager';
import { TopicTrackingService } from '../../services/messagebus/TopicTrackingService';
import { TopicListPreferences } from '../../services/storage/TopicListPreferences';

const TAG: string = 'CategoryTopicPage';

@ComponentV2
export struct CategoryTopicPage {
  @Param category: Category | null = null;

  @Local topics: Topic[] = [];
  @Local categories: Category[] = [];
  @Local categoryMap: Map<number, Category> = new Map();
  @Local isLoading: boolean = true;
  @Local isRefreshing: boolean = false;
  @Local isLoadingMore: boolean = false;
  @Local errorMessage: string = '';
  @Local isLoggedIn: boolean = false;
  @Local trackedNewCount: number = 0;
  @Local trackedUnreadCount: number = 0;
  @Local currentPage: number = 0;
  @Local hasMore: boolean = true;

  // 排序与筛选状态
  @Local currentFilter: string = '最新';
  @Local currentOrder: string = '默认';
  @Local orderAscending: boolean = false;

  // 标签筛选（与首页共用同一套组件/交互）
  @Local selectedTags: string[] = [];
  @Local draftSelectedTags: string[] = [];
  @Local availableTags: string[] = DEFAULT_AVAILABLE_TAGS;
  @Local isTagSheetVisible: boolean = false;
  @Local previewTopic: Topic | null = null;
  @Local previewCategory: Category | null = null;
  @Local previewParentCategory: Category | null = null;
  @Local isTopicPreviewVisible: boolean = false;

  private listScroller: Scroller = new Scroller();
  private trackingListener: (() => void) | null = null;
  private authStateListener: (() => void) | null = null;
  private isResetLoading: boolean = false;

  aboutToAppear(): void {
    this.attachAuthStateListener();
    this.bootstrapPage().catch((err: Object) => {
      hilog.error(0x0000, TAG, 'Bootstrap page failed: %{public}s', JSON.stringify(err));
      this.isLoading = false;
      this.errorMessage = '加载失败，请重试';
    });
  }

  aboutToDisappear(): void {
    if (this.trackingListener !== null) {
      try {
        TopicTrackingService.getInstance().removeListener(this.trackingListener);
      } catch (_) {
      }
      this.trackingListener = null;
    }
    if (this.authStateListener !== null) {
      AuthService.getInstance().removeListener(this.authStateListener);
      this.authStateListener = null;
    }
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

  private async bootstrapPage(): Promise<void> {
    await this.restorePersistedState();
    await this.initAuthState();
    this.ensureTrackingStarted();
    await this.loadCategories();
    await this.loadTopics(true, true, false);
  }

  private async restorePersistedState(): Promise<void> {
    this.currentFilter = await TopicListPreferences.loadFilter(this.currentFilter);
    this.currentOrder = await TopicListPreferences.loadOrder(this.currentOrder);
    this.orderAscending = await TopicListPreferences.loadAscending(this.orderAscending);
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

  private persistSelectedTags(): void {
    TopicListPreferences.saveSelectedTags(this.selectedTags).catch((err: Object) => {
      hilog.error(0x0000, TAG, 'Persist selectedTags failed: %{public}s', JSON.stringify(err));
    });
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
        }
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Init auth state failed: %{public}s', JSON.stringify(err));
    }
  }

  private getCategoryTitle(): string {
    if (this.category !== null) {
      const c: Category = this.category as Category;
      if (c.name.length > 0) return c.name;
    }
    return '分类';
  }

  /**
   * 加载分类列表（用于话题卡片展示分类标签/颜色）
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
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load categories failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 加载当前分类的话题列表
   */
  async loadTopics(
    isRefresh: boolean,
    showLoading: boolean = isRefresh,
    showRefreshIndicator: boolean = false
  ): Promise<void> {
    if (this.category === null) {
      this.errorMessage = '无效的分类参数';
      this.isLoading = false;
      this.isRefreshing = false;
      this.isLoadingMore = false;
      return;
    }

    if (isRefresh) {
      if (this.isResetLoading) {
        return;
      }
      this.isResetLoading = true;
      if (showLoading) {
        this.isLoading = true;
      } else if (showRefreshIndicator) {
        this.isRefreshing = true;
      }
      this.currentPage = 0;
      this.errorMessage = '';
    } else {
      if (this.isLoadingMore || !this.hasMore) return;
      this.isLoadingMore = true;
    }

    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const c: Category = this.category as Category;

      // filter/period 映射：latest/new/unread/unseen/top/hot
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

      let parentCategorySlug: string | null = null;
      const pid: number | null = c.parentCategoryId;
      if (pid !== null && pid > 0 && this.categoryMap.has(pid)) {
        parentCategorySlug = (this.categoryMap.get(pid) as Category).slug;
      }

      const tagsParam: string[] | null = this.selectedTags.length > 0 ? [...this.selectedTags] : null;

      const response: TopicListResponse = await apiClient.getFilteredTopics(
        filterName,
        this.currentPage,
        period,
        orderParam,
        ascendingParam,
        c.slug,
        c.id,
        parentCategorySlug,
        tagsParam,
        null,
        null,
        null,
        isRefresh
      );

      if (isRefresh) {
        this.topics = response.topics;
      } else {
        this.topics = this.topics.concat(response.topics);
      }

      this.hasMore = response.topics.length >= response.perPage;
      this.currentPage = this.currentPage + 1;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load topics failed: %{public}s', JSON.stringify(err));
      if (isRefresh && (showLoading || this.topics.length === 0)) {
        this.errorMessage = '加载失败，请下拉重试';
      }
    } finally {
      if (isRefresh) {
        this.isResetLoading = false;
      }
      this.isLoading = false;
      this.isRefreshing = false;
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
          const tag: Tag = t.tags[k];
          if (tag.name === tagName) {
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

  private getParentCategory(category: Category): Category | null {
    const pid: number | null = category.parentCategoryId;
    if (pid === null || pid === 0) return null;
    if (this.categoryMap.has(pid)) {
      return this.categoryMap.get(pid) as Category;
    }
    return null;
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
    RouterManager.pushTopicDetail(topic.id);
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
  FilterBar() {
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
          // 避免 Scroll 子节点在剩余空间内被“居中”导致 chips 与“默认”之间留大空白
          .constraintSize({ minWidth: '100%' })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }

  private openTagSheet(): void {
    this.draftSelectedTags = [...this.selectedTags];
    this.isTagSheetVisible = true;
  }

  private closeTagSheet(): void {
    this.isTagSheetVisible = false;
  }

  private removeTag(tagName: string): void {
    const next: string[] = [];
    for (let i = 0; i < this.selectedTags.length; i++) {
      const t: string = this.selectedTags[i];
      if (t !== tagName) next.push(t);
    }
    this.selectedTags = next;
    this.persistSelectedTags();
    this.loadTopics(true);
  }

  private toggleTag(tagName: string): void {
    const idx: number = this.selectedTags.indexOf(tagName);
    if (idx >= 0) {
      this.removeTag(tagName);
      return;
    }
    this.selectedTags = [...this.selectedTags, tagName];
    this.persistSelectedTags();
    this.loadTopics(true);
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

  private updateFilter(next: string): void {
    if (next === this.currentFilter) return;
    this.currentFilter = next;
    this.persistSortPreferences();
    this.loadTopics(true);
  }

  private updateOrder(next: string): void {
    if (next === this.currentOrder) {
      if (next !== '默认') {
        this.orderAscending = !this.orderAscending;
        this.persistSortPreferences();
        this.loadTopics(true);
      }
      return;
    }
    this.currentOrder = next;
    this.orderAscending = false;
    this.persistSortPreferences();
    this.loadTopics(true);
  }

  private getOrderLabel(order: string): string {
    if (order === this.currentOrder && order !== '默认') {
      return this.orderAscending ? `${order} ↑` : `${order} ↓`;
    }
    return order;
  }

  private ensureTrackingStarted(): void {
    if (!this.isLoggedIn) return;

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

    svc.start()
      .then(() => {
        this.refreshTrackingUI();
      })
      .catch((err: Object) => {
        hilog.error(0x0000, TAG, 'Start topic tracking failed: %{public}s', JSON.stringify(err));
      });
  }

  private refreshTrackingUI(): void {
    const svc: TopicTrackingService = TopicTrackingService.getInstance();

    if (this.isLoggedIn && this.category !== null) {
      const c: Category = this.category as Category;
      this.trackedNewCount = svc.countNew(c.id);
      this.trackedUnreadCount = svc.countUnread(c.id);
    } else {
      this.trackedNewCount = 0;
      this.trackedUnreadCount = 0;
    }

    // 当 tracking 的 highest_post_number 增长时，同步更新分类页列表中的回复数
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

  @Builder
  TagSheetBuilder() {
    TagSelectionSheet({
      title: '选择标签',
      doneText: '确定',
      availableTags: this.availableTags,
      selectedTags: this.draftSelectedTags,
      categoryId: this.category !== null ? (this.category as Category).id : null,
      maxTags: 5,
      onToggleTag: (t: string) => {
        this.toggleDraftTag(t);
      },
      onDone: () => {
        this.selectedTags = [...this.draftSelectedTags];
        this.persistSelectedTags();
        this.closeTagSheet();
        this.loadTopics(true);
      },
      onClear: () => {
        this.draftSelectedTags = [];
      }
    })
  }

  @Builder
  TopBar() {
    Row() {
      // 返回
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

      Text(this.getCategoryTitle())
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 6, right: 10 })

      // 右侧占位（搜索按钮）
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
          RouterManager.pushPath(RouteConstants.PAGE_SEARCH);
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.background'))
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column() {
        this.TopBar()
        this.FilterBar()

        Divider().color($r('app.color.divider_light')).strokeWidth(1).margin({ left: 16, right: 16 })

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
                this.loadTopics(true);
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Refresh({ refreshing: this.isRefreshing }) {
            List({ scroller: this.listScroller }) {
              ForEach(this.topics, (topic: Topic) => {
                ListItem() {
                  if (topic.pinned) {
                    CompactTopicCard({
                      topic: topic,
                      category: this.getCategory(topic),
                      onCardClick: (t: Topic) => {
                        RouterManager.pushTopicDetail(t.id);
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
                      onCardClick: (t: Topic) => {
                        RouterManager.pushTopicDetail(t.id);
                      },
                      onCardLongPress: (t: Topic) => {
                        this.openTopicPreview(t);
                      }
                    })
                  }
                }
              })

              if (this.isLoadingMore) {
                ListItem() {
                  Row() {
                    LoadingProgress().width(20).height(20)
                    Text('加载中...')
                      .fontSize(13)
                      .fontColor($r('app.color.on_surface_tertiary'))
                      .margin({ left: 8 })
                  }
                  .width('100%')
                  .height(48)
                  .justifyContent(FlexAlign.Center)
                }
              }
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 12, right: 12, top: 8 })
            .backgroundColor($r('app.color.background'))
            .onReachEnd(() => {
              this.loadTopics(false);
            })
          }
              .onRefreshing(() => {
                this.loadTopics(true, false, true);
              })
          .layoutWeight(1)
        }
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))
        // 全局沉浸式：为顶部状态栏安全区预留 padding，避免内容被挖孔/状态栏遮挡
        .padding({ top: WindowManager.getSystemAvoidAreaTopVp() })

        this.TopicPreviewOverlay()
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .bindSheet($$this.isTagSheetVisible, this.TagSheetBuilder, {
        height: SheetSize.LARGE,
        dragBar: false,
        showClose: false,
        backgroundColor: $r('app.color.surface')
      })
    }
    .hideTitleBar(true)
    .hideToolBar(true)
  }
}
