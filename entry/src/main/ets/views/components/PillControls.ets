/**
 * 通用胶囊控件：
 * - 下拉选择胶囊（绑定 Menu）
 * - 图标操作胶囊（如 +🏷 / +💬）
 *
 * 目标：复用首页/分类页一致的“最新/默认/+”样式与菜单样式。
 */

// 筛选选项：游客态（对齐安卓：只显示 最新/排行榜/热门）
export const SORT_FILTER_OPTIONS: string[] = ['最新', '排行榜', '热门'];

// 筛选选项：登录态（对齐 FluxDO：新增 新话题/未读完/未浏览，并支持括号计数）
export const SORT_FILTER_OPTIONS_LOGGED_IN: string[] = ['最新', '新话题', '未读完', '未浏览', '排行榜', '热门'];
export const SORT_ORDER_OPTIONS: string[] = ['默认', '活跃度', '创建时间', '点赞数', '浏览量', '回复数', '参与者'];

@ComponentV2
export struct PillMenuButton {
  @Param value: string = '';
  @Param valueLabel: string = '';
  @Param options: string[] = [];
  @Param menuWidth: number = 200;
  @Param rightMargin: number = 0;

  // 胶囊样式（默认用于筛选栏；紧凑模式可覆盖）
  // 对齐安卓（Flutter FilterDropdown / OrderDropdown）：padding(10,6) + radius(8) + font(13)
  @Param valueFontSize: number = 13;
  @Param arrowFontSize: number = 16;
  @Param paddingLeft: number = 10;
  @Param paddingRight: number = 10;
  @Param paddingTop: number = 6;
  @Param paddingBottom: number = 6;
  @Param radius: number = 8;
  @Param pillHeight: number = 32;

  // 菜单样式：压缩 MenuItem 高度，避免遮挡内容（对齐安卓 PopupMenuItem 的紧凑观感）
  @Param menuRadius: number = 12;
  @Param menuItemHeight: number = 40;

  // 菜单项显示文本（允许 value 与 label 分离：用于括号计数/升降序箭头）
  @Param optionLabelBuilder: (opt: string) => string = (opt: string): string => opt;

  @Event onValueChange: (value: string) => void = () => {};

  @Builder
  MenuBuilder() {
    Menu() {
      ForEach(this.options, (opt: string) => {
        MenuItem() {
          Row() {
            if (this.value === opt) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(16)
                .fontColor([$r('app.color.primary')])
            } else {
              Blank()
                .width(16)
                .height(16)
            }

            Text(this.optionLabelBuilder(opt))
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
        .height(this.menuItemHeight)
        .onChange((selected: boolean) => {
          if (selected) {
            this.onValueChange(opt);
          }
        })
      }, (opt: string) => opt)
    }
    .width(this.menuWidth)
    .backgroundColor($r('app.color.search_bar_background'))
    .borderRadius(this.menuRadius)
    .shadow({ radius: 10, color: '#22000000', offsetX: 0, offsetY: 6 })
  }

  build() {
    Row() {
      Text(this.valueLabel.length > 0 ? this.valueLabel : this.value)
        .fontSize(this.valueFontSize)
        .fontColor($r('app.color.on_surface'))
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(this.arrowFontSize)
        .fontColor([$r('app.color.on_surface_secondary')])
        .margin({ left: 2 })
    }
    .height(this.pillHeight)
    .padding({
      left: this.paddingLeft,
      right: this.paddingRight,
      top: this.paddingTop,
      bottom: this.paddingBottom
    })
    .backgroundColor($r('app.color.search_bar_background'))
    .borderRadius(this.radius)
    .margin({ right: this.rightMargin })
    .alignItems(VerticalAlign.Center)
    .bindMenu(this.MenuBuilder())
  }
}

@ComponentV2
export struct PillIconButton {
  @Param leftSymbol: Resource = $r('sys.symbol.plus');
  @Param rightSymbol: Resource = $r('sys.symbol.message');
  @Param symbolSize: number = 14;
  @Param rightMargin: number = 0;
  @Event onAction: () => void = () => {};

  build() {
    Button() {
      Row() {
        SymbolGlyph(this.leftSymbol)
          .fontSize(this.symbolSize)
          .fontColor([$r('app.color.on_surface_secondary')])
        SymbolGlyph(this.rightSymbol)
          .fontSize(this.symbolSize)
          .fontColor([$r('app.color.on_surface_secondary')])
          .margin({ left: 2 })
      }
      .alignItems(VerticalAlign.Center)
    }
    .height(32)
    .padding({ left: 8, right: 8 })
    .borderRadius(6)
    .border({ width: 1, color: $r('app.color.divider_light') })
    .backgroundColor($r('app.color.surface'))
    .margin({ right: this.rightMargin })
    .onClick(() => {
      this.onAction();
    })
  }
}
