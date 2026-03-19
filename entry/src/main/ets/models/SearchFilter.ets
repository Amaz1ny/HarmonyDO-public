/**
 * 搜索范围类型（用于用户内容页面）
 * 对齐 Flutter: fluxdo-main/lib/models/search_filter.dart
 */
export class SearchInType {
  readonly value: string;
  readonly label: string;

  private constructor(value: string, label: string) {
    this.value = value;
    this.label = label;
  }

  static readonly BOOKMARKS: SearchInType = new SearchInType('bookmarks', '书签');
  static readonly CREATED: SearchInType = new SearchInType('created', '我的话题');
  static readonly SEEN: SearchInType = new SearchInType('seen', '浏览历史');

  static values(): SearchInType[] {
    return [SearchInType.BOOKMARKS, SearchInType.CREATED, SearchInType.SEEN];
  }
}

/**
 * 话题状态过滤
 * 对齐 Flutter: SearchStatus
 */
export class SearchStatus {
  readonly value: string;
  readonly label: string;

  private constructor(value: string, label: string) {
    this.value = value;
    this.label = label;
  }

  static readonly OPEN: SearchStatus = new SearchStatus('open', '进行中');
  static readonly CLOSED: SearchStatus = new SearchStatus('closed', '已关闭');
  static readonly ARCHIVED: SearchStatus = new SearchStatus('archived', '已归档');
  static readonly SOLVED: SearchStatus = new SearchStatus('solved', '已解决');
  static readonly UNSOLVED: SearchStatus = new SearchStatus('unsolved', '未解决');

  static values(): SearchStatus[] {
    return [SearchStatus.OPEN, SearchStatus.CLOSED, SearchStatus.ARCHIVED, SearchStatus.SOLVED, SearchStatus.UNSOLVED];
  }
}

export interface SearchFilterCopyOptions {
  categoryId?: number | null;
  categorySlug?: string | null;
  categoryName?: string | null;
  parentCategorySlug?: string | null;
  tags?: string[];
  status?: SearchStatus | null;
  beforeDate?: Date | null;
  afterDate?: Date | null;
  inType?: SearchInType | null;
  clearCategory?: boolean;
  clearStatus?: boolean;
  clearDateRange?: boolean;
}

/**
 * 高级搜索过滤参数
 */
export class SearchFilter {
  /** 分类 ID */
  readonly categoryId: number | null;
  /** 分类 slug */
  readonly categorySlug: string | null;
  /** 分类名称（用于显示） */
  readonly categoryName: string | null;
  /** 父分类 slug */
  readonly parentCategorySlug: string | null;
  /** 选中的标签列表 */
  readonly tags: string[];
  /** 话题状态 */
  readonly status: SearchStatus | null;
  /** 搜索时间范围：在此日期之前 */
  readonly beforeDate: Date | null;
  /** 搜索时间范围：在此日期之后 */
  readonly afterDate: Date | null;
  /** 搜索范围类型（用于用户内容页面） */
  readonly inType: SearchInType | null;

  constructor(
    categoryId: number | null = null,
    categorySlug: string | null = null,
    categoryName: string | null = null,
    parentCategorySlug: string | null = null,
    tags: string[] = [],
    status: SearchStatus | null = null,
    beforeDate: Date | null = null,
    afterDate: Date | null = null,
    inType: SearchInType | null = null
  ) {
    this.categoryId = categoryId;
    this.categorySlug = categorySlug;
    this.categoryName = categoryName;
    this.parentCategorySlug = parentCategorySlug;
    this.tags = tags;
    this.status = status;
    this.beforeDate = beforeDate;
    this.afterDate = afterDate;
    this.inType = inType;
  }

  /**
   * 检查是否为空（没有任何过滤条件）
   * 说明：不包含 inType（对齐 Flutter）
   */
  get isEmpty(): boolean {
    return this.categoryId === null
      && this.tags.length === 0
      && this.status === null
      && this.beforeDate === null
      && this.afterDate === null;
  }

  get isNotEmpty(): boolean {
    return !this.isEmpty;
  }

  /**
   * 获取激活的过滤条件数量（不包括 inType）
   */
  get activeFilterCount(): number {
    let count: number = 0;
    if (this.categoryId !== null) count++;
    count += this.tags.length;
    if (this.status !== null) count++;
    if (this.beforeDate !== null || this.afterDate !== null) count++;
    return count;
  }

  /**
   * 复制并修改
   */
  copyWith(options: SearchFilterCopyOptions): SearchFilter {
    const clearCategory: boolean = options.clearCategory === true;
    const clearStatus: boolean = options.clearStatus === true;
    const clearDateRange: boolean = options.clearDateRange === true;

    const nextCategoryId: number | null = clearCategory ? null : (options.categoryId !== undefined ? options.categoryId : this.categoryId);
    const nextCategorySlug: string | null = clearCategory ? null : (options.categorySlug !== undefined ? options.categorySlug : this.categorySlug);
    const nextCategoryName: string | null = clearCategory ? null : (options.categoryName !== undefined ? options.categoryName : this.categoryName);
    const nextParentCategorySlug: string | null = clearCategory ? null
      : (options.parentCategorySlug !== undefined ? options.parentCategorySlug : this.parentCategorySlug);

    const nextTags: string[] = options.tags !== undefined ? options.tags : this.tags;
    const nextStatus: SearchStatus | null = clearStatus ? null : (options.status !== undefined ? options.status : this.status);

    const nextBeforeDate: Date | null = clearDateRange ? null : (options.beforeDate !== undefined ? options.beforeDate : this.beforeDate);
    const nextAfterDate: Date | null = clearDateRange ? null : (options.afterDate !== undefined ? options.afterDate : this.afterDate);

    const nextInType: SearchInType | null = options.inType !== undefined ? options.inType : this.inType;

    return new SearchFilter(
      nextCategoryId,
      nextCategorySlug,
      nextCategoryName,
      nextParentCategorySlug,
      nextTags,
      nextStatus,
      nextBeforeDate,
      nextAfterDate,
      nextInType
    );
  }

  /**
   * 清除所有过滤条件（保留 inType）
   */
  clear(): SearchFilter {
    return new SearchFilter(null, null, null, null, [], null, null, null, this.inType);
  }

  /**
   * 转换为 Discourse 搜索查询字符串
   * 例如：in:bookmarks #分类 tags:flutter status:open after:2024-01-01
   */
  toQueryString(): string {
    const parts: string[] = [];

    // 搜索范围
    if (this.inType !== null) {
      parts.push(`in:${(this.inType as SearchInType).value}`);
    }

    // 分类
    if (this.categorySlug !== null && (this.categorySlug as string).length > 0) {
      if (this.parentCategorySlug !== null && (this.parentCategorySlug as string).length > 0) {
        parts.push(`#${this.parentCategorySlug as string}:${this.categorySlug as string}`);
      } else {
        parts.push(`#${this.categorySlug as string}`);
      }
    }

    // 标签
    for (let i = 0; i < this.tags.length; i++) {
      parts.push(`tags:${this.tags[i]}`);
    }

    // 状态
    if (this.status !== null) {
      parts.push(`status:${(this.status as SearchStatus).value}`);
    }

    // 时间范围
    if (this.afterDate !== null) {
      parts.push(`after:${this.formatDate(this.afterDate as Date)}`);
    }
    if (this.beforeDate !== null) {
      parts.push(`before:${this.formatDate(this.beforeDate as Date)}`);
    }

    return parts.join(' ');
  }

  private formatDate(date: Date): string {
    const y: number = date.getFullYear();
    const m: number = date.getMonth() + 1;
    const d: number = date.getDate();
    return `${y}-${m.toString().padStart(2, '0')}-${d.toString().padStart(2, '0')}`;
  }

  /**
   * 用于 UI 短格式展示（M/D - M/D、M/D 之后、M/D 之前）
   */
  formatShortDateRange(): string {
    const after: Date | null = this.afterDate;
    const before: Date | null = this.beforeDate;
    if (after !== null && before !== null) {
      return `${this.formatShortDate(after)} - ${this.formatShortDate(before)}`;
    }
    if (after !== null) {
      return `${this.formatShortDate(after)} 之后`;
    }
    if (before !== null) {
      return `${this.formatShortDate(before)} 之前`;
    }
    return '';
  }

  private formatShortDate(date: Date): string {
    const m: number = date.getMonth() + 1;
    const d: number = date.getDate();
    return `${m}/${d}`;
  }
}

