import { hilog } from '@kit.PerformanceAnalysisKit';
import { Category, SiteResponse } from '../../models/Category';
import { SearchPost, SearchResult, SearchTopic, SearchUser } from '../../models/SearchResult';
import { Topic, TopicListResponse } from '../../models/Topic';
import { ApiClient } from '../../services/network/ApiClient';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';
import { SmartAvatar } from '../components/SmartAvatar';
import { RouterManager } from '../../common/utils/RouterManager';
import { PreferencesUtil } from '../../services/storage/PreferencesUtil';
import { SearchFilter, SearchInType, SearchStatus } from '../../models/SearchFilter';
import { SearchSortOrder } from '../../models/SearchSort';
import { TagInfo } from '../../models/TagSearchResult';
import { ActiveSearchFiltersBar } from '../components/search/ActiveSearchFiltersBar';
import { SearchPostCard } from '../components/search/SearchPostCard';
import { SearchFilterPanel } from '../components/search/SearchFilterPanel';
import { TagSelectionSheet } from '../components/TagControls';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { WindowManager } from '../../common/utils/WindowManager';

const TAG: string = 'SearchPage';
const TOP_BAR_HEIGHT: number = 56;
const SEARCH_FIELD_HEIGHT: number = 40;
const SHEET_NONE: number = 0;
const SHEET_FILTER: number = 1;
const SHEET_TAG_MORE: number = 2;
const SHEET_DATE_RANGE: number = 3;
const RECENT_SEARCH_KEY: string = 'search_recent_queries';
const RECENT_SEARCH_LIMIT: number = 20;
const SEARCH_SORT_ORDER_KEY: string = 'search_sort_order';
const HOT_TAG_LIMIT: number = 30;
const HOT_TAG_TOPIC_SAMPLE_PAGES: number = 2;

/**
 * 搜索页面（游客态可用）
 *
 * 说明：
 * - 已接入真实 Discourse /search.json：话题/帖子/用户三分区展示
 * - 高级筛选仍按 Discourse 语法拼装 query（SearchFilter.toQueryString）
 */
@ComponentV2
export struct SearchPage {
  @Param initialQuery: string = '';
  @Param initialInTypeValue: string = '';

  @Local query: string = '';
  @Local isLoading: boolean = true;
  @Local errorMessage: string = '';

  @Local categories: Category[] = [];
  @Local categoryMap: Map<number, Category> = new Map();

  // 搜索结果：三分区（话题/帖子/用户）
  @Local topicResults: SearchTopic[] = [];
  @Local postResults: SearchPost[] = [];
  @Local userResults: SearchUser[] = [];
  @Local hasMorePosts: boolean = false;
  @Local hasMoreUsers: boolean = false;
  @Local currentPage: number = 1;
  @Local isLoadingMore: boolean = false;
  @Local lastSearchQuery: string = '';
  @Local sortOrder: SearchSortOrder = SearchSortOrder.RELEVANCE;

  // 高级筛选（已应用 + 草稿）
  @Local filter: SearchFilter = new SearchFilter();
  @Local draftFilter: SearchFilter = new SearchFilter();
  @Local hotTags: string[] = [];

  // Sheet 状态（筛选 / 标签搜索更多 / 自定义日期范围）
  @Local isSheetVisible: boolean = false;
  @Local sheetMode: number = SHEET_NONE;
  @Local isTagMoreSheetVisible: boolean = false;

  // 最近搜索
  @Local recentSearches: string[] = [];
  @Local isLoadingRecent: boolean = true;
  @Local isClearingRecent: boolean = false;

  // 自定义日期范围草稿 / 选择器
  @Local dateAfterDraft: Date | null = null;
  @Local dateBeforeDraft: Date | null = null;
  @Local datePickerValue: Date = new Date();
  @Local isAfterDateSheetVisible: boolean = false;
  @Local isBeforeDateSheetVisible: boolean = false;

  private listScroller: Scroller = new Scroller();
  private hotTagsLoadVersion: number = 0;

  aboutToAppear(): void {
    this.initializePage();
  }

  private async initializePage(): Promise<void> {
    const initialSortOrder: SearchSortOrder | null = this.extractSortOrderFromQuery(this.initialQuery);
    this.query = this.stripSortOrderFromQuery(this.initialQuery);
    await this.loadSortOrder();
    if (initialSortOrder !== null) {
      this.sortOrder = initialSortOrder;
      this.persistSortOrder(initialSortOrder);
    }

    const initialInType: SearchInType | null = this.resolveInitialInType();
    if (initialInType !== null) {
      this.filter = new SearchFilter(null, null, null, null, [], null, null, null, initialInType);
      this.draftFilter = new SearchFilter(null, null, null, null, [], null, null, null, initialInType);
    }
    this.loadRecentSearches();
    this.loadData();
  }

  private resolveInitialInType(): SearchInType | null {
    const value: string = this.initialInTypeValue.trim();
    if (value.length === 0) {
      return null;
    }
    const values: SearchInType[] = SearchInType.values();
    for (let i = 0; i < values.length; i++) {
      const item: SearchInType = values[i];
      if (item.value === value) {
        return item;
      }
    }
    return null;
  }

  private async loadData(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';

    try {
      const apiClient: ApiClient = ApiClient.getInstance();

      // 1) 分类（用于 TopicCard 的分类标签）
      const siteResponse: SiteResponse = await apiClient.getSiteInfo();
      this.categories = siteResponse.categories;
      const newMap: Map<number, Category> = new Map();
      for (let i = 0; i < this.categories.length; i++) {
        const c: Category = this.categories[i];
        newMap.set(c.id, c);
      }
      this.categoryMap = newMap;
      await this.loadHotTags(this.filter.categoryId);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load search data failed: %{public}s', JSON.stringify(err));
      this.errorMessage = '加载失败';
    } finally {
      this.isLoading = false;
      if (this.errorMessage.length === 0 && this.hasRunnableSearchCriteria(this.query, this.filter)) {
        this.performSearch();
      }
    }
  }

  private resetSearchResults(): void {
    this.topicResults = [];
    this.postResults = [];
    this.userResults = [];
    this.hasMorePosts = false;
    this.hasMoreUsers = false;
    this.currentPage = 1;
    this.isLoadingMore = false;
    this.lastSearchQuery = '';
  }

  private cloneFilter(filter: SearchFilter): SearchFilter {
    return filter.copyWith({ tags: [...filter.tags] });
  }

  private hasRunnableSearchCriteria(query: string, filter: SearchFilter): boolean {
    return query.trim().length > 0 || filter.isNotEmpty;
  }

  private hasAppliedSearchCriteria(): boolean {
    return this.hasRunnableSearchCriteria(this.query, this.filter);
  }

  private pushUniqueTag(target: string[], rawName: string): void {
    const name: string = rawName.trim();
    if (name.length === 0) {
      return;
    }
    if (target.indexOf(name) >= 0) {
      return;
    }
    target.push(name);
  }

  private extractHotTagNames(results: TagInfo[]): string[] {
    const tags: string[] = [];
    for (let i = 0; i < results.length; i++) {
      const info: TagInfo = results[i];
      this.pushUniqueTag(tags, info.name);
    }
    return tags;
  }

  private collectHotTagsFromTopics(topics: Topic[]): string[] {
    const counts: Map<string, number> = new Map();
    const tags: string[] = [];
    for (let i = 0; i < topics.length; i++) {
      const topic: Topic = topics[i];
      for (let j = 0; j < topic.tags.length; j++) {
        const tagName: string = topic.tags[j].name.trim();
        if (tagName.length === 0) {
          continue;
        }
        if (counts.has(tagName)) {
          counts.set(tagName, (counts.get(tagName) as number) + 1);
        } else {
          counts.set(tagName, 1);
          tags.push(tagName);
        }
      }
    }
    tags.sort((a: string, b: string): number => {
      const countDiff: number = (counts.get(b) as number) - (counts.get(a) as number);
      if (countDiff !== 0) {
        return countDiff;
      }
      return a.localeCompare(b);
    });
    return tags.length > HOT_TAG_LIMIT ? tags.slice(0, HOT_TAG_LIMIT) : tags;
  }

  private async loadHotTagTopics(categoryId: number | null): Promise<Topic[]> {
    const apiClient: ApiClient = ApiClient.getInstance();
    const category: Category | null = categoryId !== null ? this.getCategoryById(categoryId) : null;
    const topics: Topic[] = [];
    for (let page = 0; page < HOT_TAG_TOPIC_SAMPLE_PAGES; page++) {
      let response: TopicListResponse;
      if (category !== null && category.slug.trim().length > 0) {
        response = await apiClient.getCategoryTopics(category.slug, category.id, page);
      } else {
        response = await apiClient.getLatestTopics(page);
      }
      for (let i = 0; i < response.topics.length; i++) {
        topics.push(response.topics[i]);
      }
      if (response.topics.length < response.perPage || topics.length >= HOT_TAG_LIMIT * 3) {
        break;
      }
    }
    return topics;
  }

  private buildHotTagFallback(): string[] {
    const tags: string[] = [];
    for (let i = 0; i < this.filter.tags.length; i++) {
      this.pushUniqueTag(tags, this.filter.tags[i]);
    }
    for (let i = 0; i < this.draftFilter.tags.length; i++) {
      this.pushUniqueTag(tags, this.draftFilter.tags[i]);
    }

    for (let i = 0; i < this.topicResults.length; i++) {
      const topic: SearchTopic = this.topicResults[i];
      for (let j = 0; j < topic.tags.length; j++) {
        this.pushUniqueTag(tags, topic.tags[j]);
      }
    }

    for (let i = 0; i < this.postResults.length; i++) {
      const post: SearchPost = this.postResults[i];
      if (post.topic === null) {
        continue;
      }
      const topic: SearchTopic = post.topic as SearchTopic;
      for (let j = 0; j < topic.tags.length; j++) {
        this.pushUniqueTag(tags, topic.tags[j]);
      }
    }
    return tags;
  }

  private async loadHotTags(categoryId: number | null): Promise<void> {
    const loadVersion: number = this.hotTagsLoadVersion + 1;
    this.hotTagsLoadVersion = loadVersion;
    const next: string[] = [];

    try {
      const topicTags: string[] = this.collectHotTagsFromTopics(await this.loadHotTagTopics(categoryId));
      for (let i = 0; i < topicTags.length; i++) {
        this.pushUniqueTag(next, topicTags[i]);
        if (next.length >= HOT_TAG_LIMIT) {
          break;
        }
      }
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Load hot tags from topics failed: %{public}s', JSON.stringify(err));
    }

    if (next.length < HOT_TAG_LIMIT) {
      try {
        const apiClient: ApiClient = ApiClient.getInstance();
        const primaryResponse = await apiClient.searchTags('', categoryId, null, 20, false);
        const primaryTags: string[] = this.extractHotTagNames(primaryResponse.results);
        for (let i = 0; i < primaryTags.length; i++) {
          this.pushUniqueTag(next, primaryTags[i]);
          if (next.length >= HOT_TAG_LIMIT) {
            break;
          }
        }

        if (next.length < HOT_TAG_LIMIT && primaryTags.length > 0) {
          const secondaryResponse = await apiClient.searchTags('', categoryId, next, 20, false);
          const secondaryTags: string[] = this.extractHotTagNames(secondaryResponse.results);
          for (let i = 0; i < secondaryTags.length; i++) {
            this.pushUniqueTag(next, secondaryTags[i]);
            if (next.length >= HOT_TAG_LIMIT) {
              break;
            }
          }
        }
      } catch (err) {
        hilog.warn(0x0000, TAG, 'Load hot tags from tag search failed: %{public}s', JSON.stringify(err));
      }
    }

    if (loadVersion !== this.hotTagsLoadVersion) {
      return;
    }

    const fallback: string[] = next.length > 0 ? next : this.buildHotTagFallback();
    this.hotTags = fallback.length > HOT_TAG_LIMIT ? fallback.slice(0, HOT_TAG_LIMIT) : fallback;
  }

  private performSearch(): void {
    const rawQuery: string = this.query.trim();
    const typedSortOrder: SearchSortOrder | null = this.extractSortOrderFromQuery(rawQuery);
    if (typedSortOrder !== null) {
      this.sortOrder = typedSortOrder;
      this.persistSortOrder(typedSortOrder);
    }

    const q: string = this.stripSortOrderFromQuery(rawQuery);
    this.query = q;
    if (!this.hasRunnableSearchCriteria(q, this.filter)) {
      this.resetSearchResults();
      return;
    }

    const searchQuery: string = this.buildSearchQuery(q, this.filter);
    if (searchQuery.length === 0) {
      this.resetSearchResults();
      return;
    }
    hilog.info(0x0000, TAG, 'Perform search: %{public}s', searchQuery);

    this.saveRecentQuery(q);

    this.lastSearchQuery = searchQuery;
    this.currentPage = 1;
    this.topicResults = [];
    this.postResults = [];
    this.userResults = [];
    this.hasMorePosts = false;
    this.hasMoreUsers = false;
    this.errorMessage = '';

    this.isLoading = true;
    this.fetchSearchPage(searchQuery, 1, true).catch((err: Object) => {
      hilog.error(0x0000, TAG, 'Search failed: %{public}s', JSON.stringify(err));
      this.errorMessage = '搜索失败';
      this.isLoading = false;
    });
  }

  private loadMore(): void {
    if (this.isLoading || this.isLoadingMore) return;
    if (this.lastSearchQuery.length === 0) return;
    if (!this.hasMorePosts) return;

    this.isLoadingMore = true;
    const nextPage: number = this.currentPage + 1;
    this.fetchSearchPage(this.lastSearchQuery, nextPage, false).finally(() => {
      this.isLoadingMore = false;
    });
  }

  private async fetchSearchPage(searchQuery: string, page: number, scrollToTop: boolean): Promise<void> {
    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const resp: SearchResult = await apiClient.search(searchQuery, page, 'topic');

      if (page <= 1) {
        this.topicResults = resp.topics;
        this.postResults = resp.posts;
        this.userResults = resp.users;
      } else {
        this.topicResults = this.mergeTopics(this.topicResults, resp.topics);
        this.postResults = this.mergePosts(this.postResults, resp.posts);
        this.userResults = this.mergeUsers(this.userResults, resp.users);
      }

      this.hasMorePosts = resp.hasMorePosts;
      this.hasMoreUsers = resp.hasMoreUsers;
      this.currentPage = page;

      if (scrollToTop) {
        this.listScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 120, curve: Curve.EaseOut } });
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'fetchSearchPage failed: %{public}s', JSON.stringify(err));
      this.errorMessage = '搜索失败';
    } finally {
      this.isLoading = false;
    }
  }

  private mergeTopics(base: SearchTopic[], incoming: SearchTopic[]): SearchTopic[] {
    const out: SearchTopic[] = [];
    const seen: Map<number, boolean> = new Map();
    for (let i = 0; i < base.length; i++) {
      const t: SearchTopic = base[i];
      out.push(t);
      if (t.id > 0) seen.set(t.id, true);
    }
    for (let i = 0; i < incoming.length; i++) {
      const t: SearchTopic = incoming[i];
      if (t.id <= 0) continue;
      if (seen.has(t.id)) continue;
      seen.set(t.id, true);
      out.push(t);
    }
    return out;
  }

  private mergePosts(base: SearchPost[], incoming: SearchPost[]): SearchPost[] {
    const out: SearchPost[] = [];
    const seen: Map<number, boolean> = new Map();
    for (let i = 0; i < base.length; i++) {
      const p: SearchPost = base[i];
      out.push(p);
      if (p.id > 0) seen.set(p.id, true);
    }
    for (let i = 0; i < incoming.length; i++) {
      const p: SearchPost = incoming[i];
      if (p.id <= 0) continue;
      if (seen.has(p.id)) continue;
      seen.set(p.id, true);
      out.push(p);
    }
    return out;
  }

  private mergeUsers(base: SearchUser[], incoming: SearchUser[]): SearchUser[] {
    const out: SearchUser[] = [];
    const seen: Map<number, boolean> = new Map();
    for (let i = 0; i < base.length; i++) {
      const u: SearchUser = base[i];
      out.push(u);
      if (u.id > 0) seen.set(u.id, true);
    }
    for (let i = 0; i < incoming.length; i++) {
      const u: SearchUser = incoming[i];
      if (u.id <= 0) continue;
      if (seen.has(u.id)) continue;
      seen.set(u.id, true);
      out.push(u);
    }
    return out;
  }

  private getCategoryById(categoryId: number | null): Category | null {
    if (categoryId === null) return null;
    const id: number = categoryId as number;
    if (this.categoryMap.has(id)) {
      return this.categoryMap.get(id) as Category;
    }
    return null;
  }

  private openFilterSheet(): void {
    this.draftFilter = this.cloneFilter(this.filter);
    this.loadHotTags(this.draftFilter.categoryId).catch(() => {});
    this.sheetMode = SHEET_FILTER;
    this.isSheetVisible = true;
  }

  private closeSheet(): void {
    this.isSheetVisible = false;
    this.isTagMoreSheetVisible = false;
    this.isAfterDateSheetVisible = false;
    this.isBeforeDateSheetVisible = false;
  }

  private applyDraftFilter(): void {
    this.filter = this.cloneFilter(this.draftFilter);
    this.draftFilter = this.cloneFilter(this.filter);
    this.loadHotTags(this.filter.categoryId).catch(() => {});
    this.closeSheet();
    this.performSearch();
  }

  private resetDraftFilter(): void {
    this.draftFilter = this.draftFilter.clear();
    this.loadHotTags(null).catch(() => {});
  }

  private clearAllFilters(): void {
    this.filter = this.filter.clear();
    this.draftFilter = this.cloneFilter(this.filter);
    this.loadHotTags(null).catch(() => {});
    this.performSearch();
  }

  private clearFilterCategory(): void {
    this.filter = this.filter.copyWith({ clearCategory: true });
    this.draftFilter = this.cloneFilter(this.filter);
    this.loadHotTags(null).catch(() => {});
    this.performSearch();
  }

  private removeFilterTag(tagName: string): void {
    const next: string[] = [];
    for (let i = 0; i < this.filter.tags.length; i++) {
      const t = this.filter.tags[i];
      if (t !== tagName) next.push(t);
    }
    this.filter = this.filter.copyWith({ tags: next });
    this.draftFilter = this.cloneFilter(this.filter);
    this.performSearch();
  }

  private clearFilterStatus(): void {
    this.filter = this.filter.copyWith({ clearStatus: true });
    this.draftFilter = this.cloneFilter(this.filter);
    this.performSearch();
  }

  private clearFilterDateRange(): void {
    this.filter = this.filter.copyWith({ clearDateRange: true });
    this.draftFilter = this.cloneFilter(this.filter);
    this.performSearch();
  }

  private onDraftCategoryChange(category: Category | null, parentSlug: string | null): void {
    if (category === null) {
      this.draftFilter = this.draftFilter.copyWith({ clearCategory: true });
      this.loadHotTags(null).catch(() => {});
      return;
    }
    this.draftFilter = this.draftFilter.copyWith({
      categoryId: category.id,
      categorySlug: category.slug,
      categoryName: category.name,
      parentCategorySlug: parentSlug
    });
    this.loadHotTags(category.id).catch(() => {});
  }

  private toggleDraftTag(tagName: string): void {
    const idx: number = this.draftFilter.tags.indexOf(tagName);
    if (idx >= 0) {
      const next: string[] = [];
      for (let i = 0; i < this.draftFilter.tags.length; i++) {
        const t = this.draftFilter.tags[i];
        if (t !== tagName) next.push(t);
      }
      this.draftFilter = this.draftFilter.copyWith({ tags: next });
      return;
    }
    this.draftFilter = this.draftFilter.copyWith({ tags: [...this.draftFilter.tags, tagName] });
  }

  private openTagMoreSheet(): void {
    this.isTagMoreSheetVisible = true;
  }

  private openDateRangeSheet(): void {
    this.dateAfterDraft = this.draftFilter.afterDate !== null
      ? new Date((this.draftFilter.afterDate as Date).getTime())
      : null;
    this.dateBeforeDraft = this.draftFilter.beforeDate !== null
      ? new Date((this.draftFilter.beforeDate as Date).getTime())
      : null;
    this.sheetMode = SHEET_DATE_RANGE;
    this.isSheetVisible = true;
  }

  private formatDateText(date: Date): string {
    const y: number = date.getFullYear();
    const m: number = date.getMonth() + 1;
    const d: number = date.getDate();
    return `${y}-${m.toString().padStart(2, '0')}-${d.toString().padStart(2, '0')}`;
  }

  private getDateDraftText(date: Date | null): string {
    return date !== null ? this.formatDateText(date as Date) : '未选择';
  }

  private buildPickedDate(): Date {
    return new Date(
      this.datePickerValue.getFullYear(),
      this.datePickerValue.getMonth(),
      this.datePickerValue.getDate(),
      0,
      0,
      0,
      0
    );
  }

  private openAfterDatePicker(): void {
    this.datePickerValue = this.dateAfterDraft !== null
      ? new Date((this.dateAfterDraft as Date).getTime())
      : new Date();
    this.isAfterDateSheetVisible = true;
  }

  private openBeforeDatePicker(): void {
    this.datePickerValue = this.dateBeforeDraft !== null
      ? new Date((this.dateBeforeDraft as Date).getTime())
      : new Date();
    this.isBeforeDateSheetVisible = true;
  }

  private applyAfterDatePicker(): void {
    this.dateAfterDraft = this.buildPickedDate();
    this.isAfterDateSheetVisible = false;
  }

  private applyBeforeDatePicker(): void {
    this.dateBeforeDraft = this.buildPickedDate();
    this.isBeforeDateSheetVisible = false;
  }

  private clearDateDraft(isAfter: boolean): void {
    if (isAfter) {
      this.dateAfterDraft = null;
      return;
    }
    this.dateBeforeDraft = null;
  }

  private applyDateRangeDraft(): void {
    let afterDate: Date | null = this.dateAfterDraft !== null ? new Date((this.dateAfterDraft as Date).getTime()) : null;
    let beforeDate: Date | null = this.dateBeforeDraft !== null ? new Date((this.dateBeforeDraft as Date).getTime()) : null;
    if (afterDate !== null && beforeDate !== null && afterDate.getTime() > beforeDate.getTime()) {
      const temp: Date = afterDate;
      afterDate = beforeDate;
      beforeDate = temp;
    }
    this.draftFilter = this.draftFilter.copyWith({ afterDate: afterDate, beforeDate: beforeDate });
    this.sheetMode = SHEET_FILTER;
  }

  private buildAvailableTags(): string[] {
    const tags: string[] = [];
    for (let i = 0; i < this.hotTags.length; i++) {
      this.pushUniqueTag(tags, this.hotTags[i]);
    }
    for (let i = 0; i < this.filter.tags.length; i++) {
      this.pushUniqueTag(tags, this.filter.tags[i]);
    }

    for (let i = 0; i < this.topicResults.length; i++) {
      const t: SearchTopic = this.topicResults[i];
      for (let j = 0; j < t.tags.length; j++) {
        this.pushUniqueTag(tags, t.tags[j]);
      }
    }

    for (let i = 0; i < this.postResults.length; i++) {
      const p: SearchPost = this.postResults[i];
      if (p.topic === null) continue;
      const t: SearchTopic = p.topic as SearchTopic;
      for (let j = 0; j < t.tags.length; j++) {
        this.pushUniqueTag(tags, t.tags[j]);
      }
    }
    return tags;
  }

  private buildSearchQuery(query: string, filter: SearchFilter): string {
    const base: string = query.trim();
    const filterQuery: string = filter.toQueryString().trim();
    const parts: string[] = [];
    if (base.length > 0) {
      parts.push(base);
    }
    if (filterQuery.length > 0) {
      parts.push(filterQuery);
    }
    if (this.sortOrder.orderValue.length > 0) {
      parts.push(`order:${this.sortOrder.orderValue}`);
    }
    return parts.join(' ').trim();
  }

  private async loadSortOrder(): Promise<void> {
    try {
      const raw: string = await PreferencesUtil.getString(SEARCH_SORT_ORDER_KEY, SearchSortOrder.RELEVANCE.key);
      this.sortOrder = SearchSortOrder.fromKey(raw);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load sort order failed: %{public}s', JSON.stringify(err));
      this.sortOrder = SearchSortOrder.RELEVANCE;
    }
  }

  private persistSortOrder(order: SearchSortOrder): void {
    PreferencesUtil.putString(SEARCH_SORT_ORDER_KEY, order.key).catch((err: Object) => {
      hilog.error(0x0000, TAG, 'Persist sort order failed: %{public}s', JSON.stringify(err));
    });
  }

  private stripSortOrderFromQuery(query: string): string {
    return query.replace(/\s*order:(relevance|latest|likes|views|latest_topic)\s*/g, ' ').replace(/\s+/g, ' ').trim();
  }

  private extractSortOrderFromQuery(query: string): SearchSortOrder | null {
    const match: RegExpMatchArray | null = query.match(/order:(relevance|latest|likes|views|latest_topic)/);
    if (match === null || match.length < 2) {
      return null;
    }
    return SearchSortOrder.fromOrderValue(match[1]);
  }

  private onSortOrderChange(order: SearchSortOrder): void {
    if (this.sortOrder.key === order.key) {
      return;
    }
    this.sortOrder = order;
    this.persistSortOrder(order);
    if (this.hasAppliedSearchCriteria()) {
      this.performSearch();
    }
  }

  private getResultCountText(): string {
    if (this.postResults.length <= 0) {
      return '0 条结果';
    }
    return `${this.postResults.length}${this.hasMorePosts ? '+' : ''} 条结果`;
  }

  private getParentCategory(category: Category | null): Category | null {
    if (category === null) {
      return null;
    }
    const parentId: number | null = (category as Category).parentCategoryId;
    if (parentId === null) {
      return null;
    }
    if (this.categoryMap.has(parentId)) {
      return this.categoryMap.get(parentId) as Category;
    }
    return null;
  }

  private async loadRecentSearches(): Promise<void> {
    this.isLoadingRecent = true;
    try {
      const raw: string = await PreferencesUtil.getString(RECENT_SEARCH_KEY, '[]');
      const parsed: Object = JSON.parse(raw) as Object;
      const list: string[] = [];
      if (Array.isArray(parsed)) {
        const arr: Object[] = parsed as Object[];
        for (let i = 0; i < arr.length; i++) {
          const item = arr[i];
          if (typeof item === 'string' && (item as string).trim().length > 0) {
            list.push((item as string).trim());
          }
        }
      }
      this.recentSearches = list;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load recent searches failed: %{public}s', JSON.stringify(err));
      this.recentSearches = [];
    } finally {
      this.isLoadingRecent = false;
    }
  }

  private async persistRecentSearches(list: string[]): Promise<void> {
    try {
      await PreferencesUtil.putString(RECENT_SEARCH_KEY, JSON.stringify(list));
    } catch (err) {
      hilog.error(0x0000, TAG, 'Persist recent searches failed: %{public}s', JSON.stringify(err));
    }
  }

  private saveRecentQuery(query: string): void {
    const q: string = query.trim();
    if (q.length === 0) return;
    const next: string[] = [];
    next.push(q);
    for (let i = 0; i < this.recentSearches.length; i++) {
      const item: string = this.recentSearches[i];
      if (item !== q) next.push(item);
      if (next.length >= RECENT_SEARCH_LIMIT) break;
    }
    this.recentSearches = next;
    this.persistRecentSearches(next);
  }

  private clearRecentSearches(): void {
    if (this.isClearingRecent) return;
    this.isClearingRecent = true;
    this.recentSearches = [];
    this.persistRecentSearches([]).finally(() => {
      this.isClearingRecent = false;
    });
  }

  private onRecentQueryClick(q: string): void {
    this.query = q;
    this.performSearch();
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column() {
          this.TopBar()

          if (this.filter.isNotEmpty) {
            ActiveSearchFiltersBar({
              filter: this.filter,
              onClearCategory: () => this.clearFilterCategory(),
              onRemoveTag: (t: string) => this.removeFilterTag(t),
              onClearStatus: () => this.clearFilterStatus(),
              onClearDateRange: () => this.clearFilterDateRange(),
              onClearAll: () => this.clearAllFilters()
            })
          }

          if (this.hasAppliedSearchCriteria() &&
            (!this.isLoading || this.postResults.length > 0 || this.userResults.length > 0 || this.topicResults.length > 0)) {
            this.SearchSortRow()
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
                title: $r('app.string.load_failed'),
                message: this.errorMessage,
                showRetry: true,
                onRetry: () => {
                  if (this.categories.length === 0) {
                    this.loadData();
                  } else {
                    this.performSearch();
                  }
                }
              })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (!this.hasAppliedSearchCriteria()) {
            if (this.isLoadingRecent) {
              Column() {
                LoadingSpinner({ message: '' })
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            } else if (this.recentSearches.length > 0) {
              this.RecentSearchesView()
            } else {
              Column() {
                SymbolGlyph($r('sys.symbol.magnifyingglass'))
                  .fontSize(28)
                  .fontColor([$r('app.color.on_surface_tertiary')])
                  .margin({ bottom: 12 })
                Text($r('app.string.search_empty_hint'))
                  .fontSize(14)
                  .fontColor($r('app.color.on_surface_secondary'))
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }
          } else if (this.postResults.length === 0 && this.userResults.length === 0) {
            Column() {
              SymbolGlyph($r('sys.symbol.info_circle'))
                .fontSize(26)
                .fontColor([$r('app.color.on_surface_tertiary')])
                .margin({ bottom: 10 })
              Text($r('app.string.search_no_results'))
                .fontSize(14)
                .fontColor($r('app.color.on_surface_secondary'))
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            List({ scroller: this.listScroller }) {
              if (this.postResults.length > 0) {
                ForEach(this.postResults, (p: SearchPost) => {
                  ListItem() {
                    SearchPostCard({
                      post: p,
                      category: this.getCategoryById(p.topic !== null ? (p.topic as SearchTopic).categoryId : null),
                      parentCategory: this.getParentCategory(this.getCategoryById(
                        p.topic !== null ? (p.topic as SearchTopic).categoryId : null
                      )),
                      onTap: () => {
                        RouterManager.pushTopicDetail(p.topicId, p.postNumber);
                      }
                    })
                  }
                  .padding({ bottom: 12 })
                }, (p: SearchPost) => p.id.toString())
              }

              if (this.userResults.length > 0) {
                ListItem() {
                  this.SectionHeader($r('app.string.search_users'))
                }
                ForEach(this.userResults, (u: SearchUser) => {
                  ListItem() {
                    this.UserResultRow(u)
                  }
                  .padding({ bottom: 12 })
                }, (u: SearchUser) => u.id.toString())
              }

              if (this.isLoadingMore) {
                ListItem() {
                  Row() {
                    LoadingProgress()
                      .width(14)
                      .height(14)
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
              }
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 16, right: 16, top: 8, bottom: 12 })
            .backgroundColor($r('app.color.background'))
            .onReachEnd(() => {
              this.loadMore();
            })
          }
        }
        .width('100%')
        .height('100%')
        // 全局沉浸式：为顶部状态栏安全区预留 padding，避免内容被挖孔/状态栏遮挡
        .padding({ top: WindowManager.getSystemAvoidAreaTopVp() })
      }
      .width('100%')
      .height('100%')
      .bindSheet($$this.isSheetVisible, this.BottomSheetBuilder, {
        height: SheetSize.LARGE,
        dragBar: false,
        showClose: false,
        backgroundColor: $r('app.color.surface')
      })

      Column() {
      }
      .width(0)
      .height(0)
      .bindSheet($$this.isTagMoreSheetVisible, this.TagMoreSheetBuilder, {
        height: SheetSize.MEDIUM,
        dragBar: false,
        showClose: false,
        backgroundColor: $r('app.color.surface')
      })
    }
    .backgroundColor($r('app.color.background'))
    .hideTitleBar(true)
    .hideToolBar(true)
  }

  @Builder
  TopBar() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([$r('app.color.on_surface')])
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        RouterManager.pop();
      })

      TextInput({ text: this.query, placeholder: $r('app.string.search_hint_advanced') })
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface'))
        .placeholderColor($r('app.color.on_surface_secondary'))
        .backgroundColor(Color.Transparent)
        .height(SEARCH_FIELD_HEIGHT)
        .layoutWeight(1)
        .margin({ left: 8, right: 8 })
        .onChange((value: string) => {
          if (value !== this.query) {
            this.query = value;
            if (this.query.trim().length === 0 && !this.hasRunnableSearchCriteria('', this.filter)) {
              this.errorMessage = '';
              this.resetSearchResults();
            }
          }
        })
        .onSubmit(() => {
          this.performSearch();
        })

      if (this.query.length > 0) {
        Row() {
          SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
            .fontSize(18)
            .fontColor([$r('app.color.on_surface_secondary')])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.query = '';
          this.errorMessage = '';
          if (this.filter.isNotEmpty) {
            this.performSearch();
          } else {
            this.resetSearchResults();
          }
        })
      }

      Row() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(20)
          .fontColor([$r('app.color.on_surface_secondary')])
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.performSearch();
      })

      Stack() {
        Row() {
          SymbolGlyph($r('sys.symbol.line_3_horizontal'))
            .fontSize(20)
            .fontColor([$r('app.color.on_surface_secondary')])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)

        // 激活提示点（8x8）
        if (this.filter.isNotEmpty) {
          Circle()
            .width(8)
            .height(8)
            .fill($r('app.color.primary'))
            .position({ x: 28, y: 12 })
        }
      }
      .width(44)
      .height(44)
      .onClick(() => {
        this.openFilterSheet();
      })
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .padding({ left: 8, right: 8, top: 8, bottom: 6 })
    .backgroundColor($r('app.color.background'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  SearchSortMenuBuilder() {
    Menu() {
      ForEach(SearchSortOrder.values(), (order: SearchSortOrder) => {
        MenuItem() {
          Row() {
            if (this.sortOrder.key === order.key) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(16)
                .fontColor([$r('app.color.primary')])
            } else {
              Blank()
                .width(16)
                .height(16)
            }

            Text(order.label)
              .fontSize(14)
              .fontColor($r('app.color.on_surface'))
              .layoutWeight(1)
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
            this.onSortOrderChange(order);
          }
        })
      }, (order: SearchSortOrder) => order.key)
    }
    .width(180)
    .backgroundColor($r('app.color.search_bar_background'))
    .borderRadius(12)
    .shadow({ radius: 10, color: '#22000000', offsetX: 0, offsetY: 6 })
  }

  @Builder
  SearchSortRow() {
    Row() {
      Text($r('app.string.search_sort_label'))
        .fontSize(14)
        .fontColor($r('app.color.on_surface_secondary'))

      Row() {
        Text(this.sortOrder.label)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(16)
          .fontColor([$r('app.color.on_surface_secondary')])
          .margin({ left: 3, top: 1 })
      }
      .margin({ left: 8 })
      .bindMenu(this.SearchSortMenuBuilder())

      Blank().layoutWeight(1)

      Text(this.getResultCountText())
        .fontSize(13)
        .fontColor($r('app.color.on_surface_secondary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 12 })
  }

  @Builder
  SectionHeader(title: Resource | string) {
    Row() {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface_secondary'))
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 10, bottom: 8 })
  }

  @Builder
  UserResultRow(user: SearchUser) {
    Row() {
      SmartAvatar({
        avatarUrl: user.getAvatarUrl(80),
        avatarSize: 40,
        avatarRadius: 20,
        fallbackText: user.username,
        bgColor: '#E8EAF0'
      })

      Column() {
        Text(user.username)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (user.name !== null && (user.name as string).length > 0) {
          Text(user.name as string)
            .fontSize(13)
            .fontColor($r('app.color.on_surface_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
        }
      }
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(18)
    .shadow({ radius: 10, color: '#0A000000', offsetX: 0, offsetY: 4 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      RouterManager.pushUserProfile(user.username);
    })
  }

  @Builder
  RecentSearchesView() {
    Column() {
      Row() {
        Text($r('app.string.recent_searches'))
          .fontSize(13)
          .fontColor($r('app.color.on_surface_secondary'))
          .fontWeight(FontWeight.Medium)
        Blank().layoutWeight(1)

        if (this.isClearingRecent) {
          LoadingProgress()
            .width(12)
            .height(12)
        } else {
          Text($r('app.string.clear'))
            .fontSize(13)
            .fontColor($r('app.color.primary'))
            .onClick(() => {
              this.clearRecentSearches();
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      List() {
        ForEach(this.recentSearches, (q: string) => {
          ListItem() {
            Row() {
              SymbolGlyph($r('sys.symbol.clock'))
                .fontSize(16)
                .fontColor([$r('app.color.on_surface_tertiary')])
                .margin({ right: 10 })
              Text(q)
                .fontSize(15)
                .fontColor($r('app.color.on_surface'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .height(48)
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
          }
          .onClick(() => {
            this.onRecentQueryClick(q);
          })
        }, (q: string) => q)
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.background'))
      .divider({ strokeWidth: 0.5, color: $r('app.color.divider_light'), startMargin: 16, endMargin: 16 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  BottomSheetBuilder() {
    if (this.sheetMode === SHEET_FILTER) {
      SearchFilterPanel({
        filter: this.draftFilter,
        categories: this.categories,
        hotTags: this.hotTags,
        onReset: () => {
          this.resetDraftFilter();
        },
        onApply: () => {
          this.applyDraftFilter();
        },
        onSetStatus: (s: SearchStatus | null) => {
          this.draftFilter = this.draftFilter.copyWith({ status: s });
        },
        onSetDateRange: (after: Date | null, before: Date | null) => {
          this.draftFilter = this.draftFilter.copyWith({ afterDate: after, beforeDate: before });
        },
        onOpenCustomDate: () => {
          this.openDateRangeSheet();
        },
        onCategoryChange: (c: Category | null, parentSlug: string | null) => {
          this.onDraftCategoryChange(c, parentSlug);
        },
        onToggleTag: (t: string) => {
          this.toggleDraftTag(t);
        },
        onOpenTagMore: () => {
          this.openTagMoreSheet();
        }
      })
    } else if (this.sheetMode === SHEET_DATE_RANGE) {
      this.DateRangeSheet()
    }
  }

  @Builder
  TagMoreSheetBuilder() {
    TagSelectionSheet({
      title: $r('app.string.search_more_tags'),
      doneText: $r('app.string.done'),
      availableTags: this.buildAvailableTags(),
      selectedTags: this.draftFilter.tags,
      categoryId: this.draftFilter.categoryId,
      showHeaderBar: true,
      onBack: () => {
        this.isTagMoreSheetVisible = false;
      },
      onToggleTag: (t: string) => {
        this.toggleDraftTag(t);
      },
      onDone: () => {
        this.isTagMoreSheetVisible = false;
      },
      onClear: () => {
        this.draftFilter = this.draftFilter.copyWith({ tags: [] });
      }
    })
  }

  @Builder
  DateRangeSheet() {
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

      Row() {
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
          this.sheetMode = SHEET_FILTER;
          this.isSheetVisible = true;
        })

        Text($r('app.string.custom_date_range'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Text($r('app.string.done'))
          .fontSize(14)
          .fontColor($r('app.color.primary'))
          .onClick(() => {
            this.applyDateRangeDraft();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 12 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .color($r('app.color.skeleton_base'))
        .strokeWidth(0.5)
        .margin({ left: 16, right: 16 })

      Column() {
        this.DatePickerField($r('app.string.after_date'), this.dateAfterDraft, () => {
          this.openAfterDatePicker();
        }, () => {
          this.clearDateDraft(true);
        })
        this.DatePickerField($r('app.string.before_date'), this.dateBeforeDraft, () => {
          this.openBeforeDatePicker();
        }, () => {
          this.clearDateDraft(false);
        })

        Text('复用书签中的日期选择器；支持单独选择开始或结束日期。')
          .fontSize(12)
          .fontColor($r('app.color.on_surface_tertiary'))
          .margin({ top: 10 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 18, bottom: 24 })

      Column() {
      }
      .width(0)
      .height(0)
      .bindSheet($$this.isAfterDateSheetVisible, this.AfterDateSheetBuilder, {
        height: SheetSize.FIT_CONTENT,
        dragBar: false,
        showClose: false,
        backgroundColor: $r('app.color.surface')
      })

      Column() {
      }
      .width(0)
      .height(0)
      .bindSheet($$this.isBeforeDateSheetVisible, this.BeforeDateSheetBuilder, {
        height: SheetSize.FIT_CONTENT,
        dragBar: false,
        showClose: false,
        backgroundColor: $r('app.color.surface')
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  DatePickerField(label: Resource, value: Date | null, onTap: () => void, onClear: () => void) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ bottom: 6 })
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.calendar'))
            .fontSize(16)
            .fontColor([$r('app.color.on_surface_secondary')])
            .margin({ right: 8 })

          Text(this.getDateDraftText(value))
            .fontSize(15)
            .fontColor(value !== null ? $r('app.color.on_surface') : $r('app.color.on_surface_tertiary'))
            .layoutWeight(1)
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('app.color.on_surface_tertiary')])
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 12 })
      .backgroundColor($r('app.color.search_background'))
      .borderRadius(12)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        onTap();
      })

      if (value !== null) {
        Text('清空')
          .fontSize(12)
          .fontColor($r('app.color.primary'))
          .margin({ top: 8 })
          .onClick(() => {
            onClear();
          })
      }
    }
    .width('100%')
    .margin({ bottom: 14 })
  }

  @Builder
  private AfterDateSheetBuilder() {
    Column() {
      Row() {
        Text('选择开始日期')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .layoutWeight(1)

        Text('取消')
          .fontSize(15)
          .fontColor($r('app.color.on_surface_secondary'))
          .onClick(() => {
            this.isAfterDateSheetVisible = false;
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 18, bottom: 12 })

      DatePicker({
        start: new Date('2024-01-01'),
        end: new Date('2100-12-31'),
        selected: this.datePickerValue
      })
        .width('100%')
        .lunar(false)
        .onDateChange((value: Date) => {
          this.datePickerValue = new Date(value.getTime());
        })

      Row() {
        Blank().layoutWeight(1)

        Text('确定')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary'))
          .onClick(() => {
            this.applyAfterDatePicker();
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12, bottom: 18 + WindowManager.getSystemAvoidAreaBottomVp() })
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private BeforeDateSheetBuilder() {
    Column() {
      Row() {
        Text('选择结束日期')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .layoutWeight(1)

        Text('取消')
          .fontSize(15)
          .fontColor($r('app.color.on_surface_secondary'))
          .onClick(() => {
            this.isBeforeDateSheetVisible = false;
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 18, bottom: 12 })

      DatePicker({
        start: new Date('2024-01-01'),
        end: new Date('2100-12-31'),
        selected: this.datePickerValue
      })
        .width('100%')
        .lunar(false)
        .onDateChange((value: Date) => {
          this.datePickerValue = new Date(value.getTime());
        })

      Row() {
        Blank().layoutWeight(1)

        Text('确定')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary'))
          .onClick(() => {
            this.applyBeforeDatePicker();
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12, bottom: 18 + WindowManager.getSystemAvoidAreaBottomVp() })
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
  }
}
