import { Category } from '../../../models/Category';
import { SearchFilter, SearchStatus } from '../../../models/SearchFilter';
import { BadgeIconUtils } from '../TopicBadges';

const HANDLE_WIDTH: number = 32;
const HANDLE_HEIGHT: number = 4;
const SUBCATEGORY_GUIDE_ESTIMATE_COLUMNS: number = 3;
const SUBCATEGORY_GUIDE_ROW_HEIGHT: number = 32; // 约等于 chip(≈24) + runSpacing(8)

/**
 * 高级搜索过滤面板（Sheet 内容）
 * 支持分类、标签、状态和日期范围筛选
 */
@ComponentV2
export struct SearchFilterPanel {
  @Param filter: SearchFilter = new SearchFilter();
  @Param categories: Category[] = [];
  @Param hotTags: string[] = [];

  @Event onReset: () => void = () => {};
  @Event onApply: () => void = () => {};
  @Event onSetStatus: (status: SearchStatus | null) => void = () => {};
  @Event onSetDateRange: (after: Date | null, before: Date | null) => void = () => {};
  @Event onOpenCustomDate: () => void = () => {};
  @Event onCategoryChange: (category: Category | null, parentSlug: string | null) => void = () => {};
  @Event onToggleTag: (tag: string) => void = () => {};
  @Event onOpenTagMore: () => void = () => {};

  build() {
    Column() {
      // 拖动柄
      Column() {
        Rect()
          .width(HANDLE_WIDTH)
          .height(HANDLE_HEIGHT)
          .radius(2)
          .fill($r('app.color.divider_light'))
      }
      .width('100%')
      .padding({ top: 12 })
      .alignItems(HorizontalAlign.Center)

      // 标题栏：左标题 + 右“重置”
      Row() {
        Text($r('app.string.advanced_search'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .layoutWeight(1)

        Text($r('app.string.reset'))
          .fontSize(14)
          .fontColor($r('app.color.error'))
          .opacity(this.filter.isNotEmpty ? 1 : 0)
          .onClick(() => {
            if (this.filter.isNotEmpty) {
              this.onReset();
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      Divider().color($r('app.color.divider_light')).strokeWidth(1)

      // 内容区域
      Scroll() {
        Column() {
          this.SectionTitle($r('app.string.filter_status'))
          this.StatusSection()

          Blank().height(24)

          this.SectionTitle($r('app.string.filter_time_range'))
          this.DateRangeSection()

          Blank().height(24)

          this.SectionTitle($r('app.string.filter_category'))
          this.CategorySection()

          Blank().height(24)

          this.TagsHeader()
          this.TagsSection()

          Blank().height(24)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 20 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // 底部确认按钮
      Column() {
        Button() {
          Text($r('app.string.apply_filter'))
            .fontSize(16)
            .fontColor(Color.White)
        }
        .width('100%')
        .height(48)
        .backgroundColor($r('app.color.primary'))
        .borderRadius(12)
        .onClick(() => {
          this.onApply();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      .backgroundColor($r('app.color.surface'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  SectionTitle(title: Resource) {
    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.on_surface'))
      .width('100%')
  }

  @Builder
  StatusSection() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      // 全部
      this.FilterChip($r('app.string.filter_all'), this.filter.status === null, null, () => {
        this.onSetStatus(null);
      })

      ForEach(SearchStatus.values(), (s: SearchStatus) => {
        this.FilterChip(s.label, this.filter.status === s, null, () => {
          this.onSetStatus(this.filter.status === s ? null : s);
        })
      }, (s: SearchStatus) => s.value)
    }
    .width('100%')
    .margin({ top: 12 })
  }

  @Builder
  DateRangeSection() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      this.FilterChip($r('app.string.filter_no_limit'), !this.hasDateRange(), null, () => {
        this.onSetDateRange(null, null);
      })

      // 快捷选项（点击后直接设置日期范围，不强制显示选中态）
      this.FilterChip($r('app.string.filter_last_week'), false, null, () => {
        const now: Date = new Date();
        const after: Date = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
        this.onSetDateRange(after, now);
      })
      this.FilterChip($r('app.string.filter_last_month'), false, null, () => {
        const now: Date = new Date();
        const after: Date = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
        this.onSetDateRange(after, now);
      })
      this.FilterChip($r('app.string.filter_last_year'), false, null, () => {
        const now: Date = new Date();
        const after: Date = new Date(now.getTime() - 365 * 24 * 60 * 60 * 1000);
        this.onSetDateRange(after, now);
      })

      // 自定义
      this.FilterChip(
        this.hasDateRange() && this.filter.formatShortDateRange().length > 0 ? this.filter.formatShortDateRange() : $r('app.string.filter_custom'),
        this.hasDateRange(),
        $r('sys.symbol.calendar'),
        () => {
          this.onOpenCustomDate();
        }
      )
    }
    .width('100%')
    .margin({ top: 12 })
  }

  @Builder
  TagsHeader() {
    Row() {
      Text($r('app.string.filter_tags'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface'))
      Blank().layoutWeight(1)
      Row() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(16)
          .fontColor([$r('app.color.on_surface_secondary')])
          .margin({ right: 4 })
        Text($r('app.string.search_more'))
          .fontSize(13)
          .fontColor($r('app.color.on_surface_secondary'))
      }
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .onClick(() => {
        this.onOpenTagMore();
      })
    }
    .width('100%')
  }

  @Builder
  TagsSection() {
    if (this.hotTags.length === 0 && this.getExtraSelectedTags(this.hotTags, this.filter.tags).length === 0) {
      Text('暂无热门标签')
        .fontSize(13)
        .fontColor($r('app.color.on_surface_tertiary'))
        .margin({ top: 10 })
        .width('100%')
    } else {
      Column() {
        if (this.getExtraSelectedTags(this.hotTags, this.filter.tags).length > 0) {
          Text($r('app.string.selected_tags'))
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 12, bottom: 8 })

          this.TagWrap(this.getExtraSelectedTags(this.hotTags, this.filter.tags))
        }

        if (this.hotTags.length > 0) {
          Text($r('app.string.hot_tags'))
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 16, bottom: 8 })

          this.TagWrap(this.hotTags)
        }
      }
      .width('100%')
    }
  }

  @Builder
  TagWrap(tags: string[]) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(tags, (t: string) => {
        this.TagChip(t, this.filter.tags.indexOf(t) >= 0)
      }, (t: string) => t)
    }
    .width('100%')
  }

  @Builder
  TagChip(tag: string, selected: boolean) {
    Row() {
      if (BadgeIconUtils.getTagSymbol(tag) !== null) {
        SymbolGlyph(BadgeIconUtils.getTagSymbol(tag) as Resource)
          .fontSize(14)
          .fontColor([BadgeIconUtils.getTagColor(tag)])
          .margin({ right: 4 })
      } else if (!selected) {
        SymbolGlyph($r('sys.symbol.label'))
          .fontSize(12)
          .fontColor([$r('app.color.on_surface_secondary')])
          .margin({ right: 4 })
      }
      Text(tag)
        .fontSize(12)
        .fontColor(selected ? $r('app.color.primary') : $r('app.color.on_surface_secondary'))
        .fontWeight(selected ? FontWeight.Bold : FontWeight.Normal)

      if (selected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontColor([$r('app.color.primary')])
          .margin({ left: 4 })
      }
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor(selected ? $r('app.color.badge_background_light') : $r('app.color.search_bar_background'))
    .borderRadius(8)
    .border({ width: 1, color: selected ? $r('app.color.primary') : Color.Transparent })
    .margin({ right: 8, bottom: 8 })
    .onClick(() => {
      this.onToggleTag(tag);
    })
  }

  private getExtraSelectedTags(hotTags: string[], selected: string[]): string[] {
    const extras: string[] = [];
    for (let i = 0; i < selected.length; i++) {
      const t: string = selected[i];
      if (hotTags.indexOf(t) < 0) extras.push(t);
    }
    return extras;
  }

  @Builder
  CategorySection() {
    Column() {
      // 顶部区域："全部"
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        this.CategoryChipAll(this.filter.categoryId === null)
      }

      if (this.getTopCategories().length > 0) {
        Blank().height(16)
      }

      // 按顶级分类原始顺序逐组输出：父分类在前，子分类在下
      ForEach(this.getTopCategories(), (parent: Category) => {
        Column() {
          this.CategoryChipItem(parent, false, null)

          if (this.hasSubcategories(parent.id)) {
            Blank().height(8)

            Row() {
              // 左侧引导线
              Column() {}
                .width(2)
                .height(this.estimateSubcategoryGuideHeight(parent.id))
                .backgroundColor(this.hexWithAlpha(this.normalizeHex(parent.color), 0.3))
                .borderRadius(1)
                .margin({ left: 12, right: 12, top: 4, bottom: 4 })

              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(this.getSubcategories(parent.id), (sub: Category) => {
                  this.CategoryChipItem(sub, true, parent)
                }, (sub: Category) => sub.id.toString())
              }
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: this.getCategoryBlockBottomMargin(parent.id) })
      }, (p: Category) => p.id.toString())
    }
    .width('100%')
    .margin({ top: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  private estimateSubcategoryGuideHeight(parentId: number): number {
    const count: number = this.getSubcategories(parentId).length;
    const safeCount: number = Math.max(1, count);
    const rows: number = Math.max(1, Math.ceil(safeCount / SUBCATEGORY_GUIDE_ESTIMATE_COLUMNS));
    // line 自带 top/bottom 4 margin，因此这里略短一点，避免视觉上过高
    const est: number = rows * SUBCATEGORY_GUIDE_ROW_HEIGHT - 8;
    return Math.max(16, est);
  }

  private hasDateRange(): boolean {
    return this.filter.afterDate !== null || this.filter.beforeDate !== null;
  }

  private hasSubcategories(parentId: number): boolean {
    for (let i = 0; i < this.categories.length; i++) {
      const c: Category = this.categories[i];
      if (c.parentCategoryId !== null && (c.parentCategoryId as number) === parentId) return true;
    }
    return false;
  }

  private getSubcategories(parentId: number): Category[] {
    const subs: Category[] = [];
    for (let i = 0; i < this.categories.length; i++) {
      const c: Category = this.categories[i];
      if (c.parentCategoryId !== null && (c.parentCategoryId as number) === parentId) {
        subs.push(c);
      }
    }
    return subs;
  }

  private getTopCategories(): Category[] {
    const list: Category[] = [];
    for (let i = 0; i < this.categories.length; i++) {
      const c: Category = this.categories[i];
      if (c.parentCategoryId === null || c.parentCategoryId === 0) {
        list.push(c);
      }
    }
    return list;
  }

  private getCategoryBlockBottomMargin(parentId: number): number {
    if (this.hasSubcategories(parentId)) {
      return 16;
    }
    return 8;
  }

  @Builder
  CategoryChipAll(selected: boolean) {
    Row() {
      Text($r('app.string.filter_all'))
        .fontSize(12)
        .fontColor($r('app.color.on_surface'))
        .fontWeight(selected ? FontWeight.Bold : FontWeight.Medium)
      if (selected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontColor([$r('app.color.primary')])
          .margin({ left: 6 })
      }
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.search_bar_background'))
    .borderRadius(6)
    .border({ width: 1, color: selected ? $r('app.color.primary') : Color.Transparent })
    .margin({ right: 8, bottom: 8 })
    .onClick(() => {
      this.onCategoryChange(null, null);
    })
  }

  @Builder
  CategoryChipItem(category: Category, isSub: boolean, parentCategory: Category | null) {
    Row() {
      if (this.getCategorySymbol(category, parentCategory) !== null) {
        SymbolGlyph(this.getCategorySymbol(category, parentCategory) as Resource)
          .fontSize(15)
          .fontColor([this.getCategoryColorHex(category)])
          .margin({ right: 6 })
      } else if (category.readRestricted) {
        SymbolGlyph($r('sys.symbol.lock'))
          .fontSize(12)
          .fontColor([this.getCategoryColorHex(category)])
          .margin({ right: 6 })
      } else {
        Circle()
          .width(8)
          .height(8)
          .fill(this.getCategoryColorHex(category))
          .margin({ right: 6 })
      }

      Text(category.name)
        .fontSize(isSub ? 12 : 12)
        .fontColor($r('app.color.on_surface'))
        .fontWeight(this.isCategorySelected(category.id) ? FontWeight.Bold : FontWeight.Medium)

      if (this.isCategorySelected(category.id)) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontColor([this.getCategoryColorHex(category)])
          .margin({ left: 6 })
      }
    }
    .padding({ left: isSub ? 6 : 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor(this.getCategoryBgColor(category))
    .borderRadius(6)
    .border({ width: 1, color: this.getCategoryBorderColor(category) })
    .margin({ right: 8, bottom: 8 })
    .onClick(() => {
      const nextSelected: boolean = this.filter.categoryId !== null && (this.filter.categoryId as number) === category.id;
      if (nextSelected) {
        this.onCategoryChange(null, null);
        return;
      }
      const parentSlug: string | null = parentCategory !== null ? (parentCategory as Category).slug : null;
      this.onCategoryChange(category, parentSlug);
    })
  }

  @Builder
  FilterChip(label: string | Resource, selected: boolean, icon: Resource | null, onTap: () => void) {
    Row() {
      if (icon !== null) {
        SymbolGlyph(icon as Resource)
          .fontSize(14)
          .fontColor([selected ? $r('app.color.primary') : $r('app.color.on_surface_secondary')])
          .margin({ right: 4 })
      }
      Text(label)
        .fontSize(12)
        .fontColor(selected ? $r('app.color.primary') : $r('app.color.on_surface_secondary'))
        .fontWeight(selected ? FontWeight.Bold : FontWeight.Medium)
      if (selected && icon === null) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontColor([$r('app.color.primary')])
          .margin({ left: 4 })
      }
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(selected ? $r('app.color.badge_background_light') : $r('app.color.search_bar_background'))
    .borderRadius(8)
    .border({ width: 1, color: selected ? $r('app.color.primary') : Color.Transparent })
    .margin({ right: 8, bottom: 8 })
    .onClick(() => {
      onTap();
    })
  }

  private isCategorySelected(categoryId: number): boolean {
    return this.filter.categoryId !== null && (this.filter.categoryId as number) === categoryId;
  }

  private getCategoryColorHex(category: Category): string {
    return this.normalizeHex(category.color);
  }

  private getCategorySymbol(category: Category, parentCategory: Category | null): Resource | null {
    return BadgeIconUtils.getCategorySymbol(category, parentCategory);
  }

  private getCategoryBgColor(category: Category): string {
    const colorHex: string = this.normalizeHex(category.color);
    return this.hexWithAlpha(colorHex, this.isCategorySelected(category.id) ? 0.15 : 0.08);
  }

  private getCategoryBorderColor(category: Category): string {
    const colorHex: string = this.normalizeHex(category.color);
    return this.hexWithAlpha(colorHex, this.isCategorySelected(category.id) ? 1 : 0.2);
  }

  private normalizeHex(hex: string): string {
    if (hex.length === 0) return '#999999';
    if (hex.startsWith('#')) return hex;
    return `#${hex}`;
  }

  private hexWithAlpha(hex: string, alpha: number): string {
    let colorHex: string = hex;
    if (colorHex.startsWith('#')) {
      colorHex = colorHex.substring(1);
    }
    const a: number = Math.max(0, Math.min(1, alpha));
    const alphaHex: string = Math.round(a * 255).toString(16).padStart(2, '0');
    return `#${alphaHex}${colorHex}`;
  }
}
