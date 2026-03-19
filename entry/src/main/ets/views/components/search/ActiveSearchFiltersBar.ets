import { SearchFilter, SearchStatus } from '../../../models/SearchFilter';

const CHIP_HEIGHT: number = 30;

/**
 * 已激活过滤条件显示条（对齐 Flutter: ActiveSearchFiltersBar）
 * - 展示：分类 / 标签 / 状态 / 时间范围
 * - 支持逐项清除与清除全部
 */
@ComponentV2
export struct ActiveSearchFiltersBar {
  @Param filter: SearchFilter = new SearchFilter();
  @Event onClearCategory: () => void = () => {};
  @Event onRemoveTag: (tag: string) => void = () => {};
  @Event onClearStatus: () => void = () => {};
  @Event onClearDateRange: () => void = () => {};
  @Event onClearAll: () => void = () => {};

  build() {
    if (this.filter.isEmpty) {
      Blank()
    } else {
      Column() {
        Scroll() {
          Row() {
            if (this.filter.categoryName !== null && (this.filter.categoryName as string).length > 0) {
              this.Chip(`#${this.filter.categoryName as string}`, () => this.onClearCategory(), true)
            }

            ForEach(this.filter.tags, (t: string) => {
              this.Chip(t, () => this.onRemoveTag(t), true)
            }, (t: string) => t)

            if (this.filter.status !== null) {
              this.Chip((this.filter.status as SearchStatus).label, () => this.onClearStatus(), true)
            }

            if (this.filter.afterDate !== null || this.filter.beforeDate !== null) {
              this.Chip(this.filter.formatShortDateRange(), () => this.onClearDateRange(), true)
            }

            // 清除全部
            this.Chip($r('app.string.clear_all'), () => this.onClearAll(), false)
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .alignItems(VerticalAlign.Center)
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .backgroundColor($r('app.color.background'))

        Divider()
          .color($r('app.color.divider_light'))
          .strokeWidth(1)
          .margin({ left: 16, right: 16 })
      }
      .width('100%')
    }
  }

  @Builder
  Chip(label: string | Resource, onRemove: () => void, showRemove: boolean) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.on_surface'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (showRemove) {
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(12)
            .fontColor([$r('app.color.on_surface_secondary')])
        }
        .width(18)
        .height(18)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .margin({ left: 6 })
      }
    }
    .height(CHIP_HEIGHT)
    .padding({ left: 10, right: 10 })
    .backgroundColor($r('app.color.search_bar_background'))
    .borderRadius(8)
    .margin({ right: 8 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      onRemove();
    })
  }
}
