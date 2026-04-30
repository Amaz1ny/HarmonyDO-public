import { TimeUtils } from '../../common/utils/TimeUtils';
import { RouterManager } from '../../common/utils/RouterManager';
import { WindowManager } from '../../common/utils/WindowManager';
import {
  FLOATING_TAB_BAR_HEIGHT_VP,
  FLOATING_TAB_BAR_MARGIN_BOTTOM_VP,
  FLOATING_TAB_BAR_OFFSET_UP_VP
} from '../../common/constants/LayoutConstants';
import {
  MAX_READ_LATER_ITEMS,
  ReadLaterItem,
  ReadLaterService
} from '../../services/storage/ReadLaterService';
import { HoldingHandService, HoldingHandState } from '../../services/device/HoldingHandService';

const DOCK_HEIGHT: number = 48;
const DOCK_COLLAPSED_WIDTH: number = 72;
const DOCK_EXPANDED_WIDTH: number = 148;
const DOCK_VISIBLE_WIDTH: number = 36;
const DOCK_EDGE_MARGIN: number = 12;
const DOCK_VERTICAL_POSITION: string = '68%';
const DOCK_AUTO_COLLAPSE_MS: number = 1800;

@ComponentV2
export struct ReadLaterBubble {
  @Local items: ReadLaterItem[] = [];
  @Local isSheetVisible: boolean = false;
  @Local isExpanded: boolean = false;
  @Local holdingHandStatus: HoldingHandState = HoldingHandState.UNKNOWN_STATUS;

  private serviceListener: (() => void) | null = null;
  private holdingHandListener: ((status: HoldingHandState) => void) | null = null;
  private collapseTimerId: number = -1;

  aboutToAppear(): void {
    this.attachListener();
    this.attachHoldingHandListener();
    this.syncItems().catch(() => {
    });
  }

  aboutToDisappear(): void {
    this.clearCollapseTimer();
    this.detachHoldingHandListener();
    this.detachListener();
  }

  private attachListener(): void {
    if (this.serviceListener !== null) {
      return;
    }
    this.serviceListener = () => {
      this.syncItems().catch(() => {
      });
    };
    ReadLaterService.getInstance().addListener(this.serviceListener);
  }

  private detachListener(): void {
    if (this.serviceListener === null) {
      return;
    }
    ReadLaterService.getInstance().removeListener(this.serviceListener);
    this.serviceListener = null;
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

  private async syncItems(): Promise<void> {
    this.items = await ReadLaterService.getInstance().getItems();
    if (this.items.length <= 0) {
      this.clearCollapseTimer();
      this.isExpanded = false;
      this.isSheetVisible = false;
      return;
    }
    if (this.isSheetVisible) {
      this.isExpanded = true;
      return;
    }
    if (this.isExpanded) {
      this.scheduleAutoCollapse();
    }
  }

  private isDockOnLeft(): boolean {
    return this.holdingHandStatus === HoldingHandState.LEFT_HAND_HELD;
  }

  private getBottomOffsetVp(): number {
    return WindowManager.getSystemAvoidAreaBottomVp()
      + FLOATING_TAB_BAR_HEIGHT_VP
      + FLOATING_TAB_BAR_MARGIN_BOTTOM_VP
      + FLOATING_TAB_BAR_OFFSET_UP_VP
      + 24;
  }

  private getDockWidth(): number {
    return this.isExpanded || this.isSheetVisible ? DOCK_EXPANDED_WIDTH : DOCK_COLLAPSED_WIDTH;
  }

  private getDockPositionX(): string | number {
    return this.isDockOnLeft() ? 0 : '100%';
  }

  private getDockTranslateX(): number {
    const width: number = this.getDockWidth();
    if (this.isDockOnLeft()) {
      return this.isExpanded || this.isSheetVisible
        ? DOCK_EDGE_MARGIN
        : -(width - DOCK_VISIBLE_WIDTH);
    }
    return this.isExpanded || this.isSheetVisible
      ? -(width + DOCK_EDGE_MARGIN)
      : -DOCK_VISIBLE_WIDTH;
  }

  private getDockTranslateY(): number {
    return -Math.round(DOCK_HEIGHT / 2);
  }

  private clearCollapseTimer(): void {
    if (this.collapseTimerId < 0) {
      return;
    }
    clearTimeout(this.collapseTimerId);
    this.collapseTimerId = -1;
  }

  private scheduleAutoCollapse(): void {
    this.clearCollapseTimer();
    if (!this.isExpanded || this.isSheetVisible || this.items.length <= 0) {
      return;
    }
    this.collapseTimerId = setTimeout(() => {
      this.collapseTimerId = -1;
      if (this.isSheetVisible || this.items.length <= 0) {
        return;
      }
      this.isExpanded = false;
    }, DOCK_AUTO_COLLAPSE_MS);
  }

  private revealDock(): void {
    if (this.items.length <= 0) {
      return;
    }
    this.isExpanded = true;
    this.scheduleAutoCollapse();
  }

  private handleDockTap(): void {
    if (this.items.length <= 0) {
      return;
    }
    if (!this.isExpanded && !this.isSheetVisible) {
      this.revealDock();
      return;
    }
    this.openSheet();
  }

  private openSheet(): void {
    if (this.items.length <= 0) {
      return;
    }
    this.clearCollapseTimer();
    this.isExpanded = true;
    this.isSheetVisible = true;
  }

  private closeSheet(): void {
    this.isSheetVisible = false;
    if (this.items.length <= 0) {
      this.isExpanded = false;
      return;
    }
    this.scheduleAutoCollapse();
  }

  private openItem(item: ReadLaterItem): void {
    this.closeSheet();
    setTimeout(() => {
      RouterManager.pushTopicDetail(item.topicId, item.postNumber);
    }, 0);
  }

  private removeItem(item: ReadLaterItem): void {
    ReadLaterService.getInstance().remove(item.topicId).catch(() => {
    });
  }

  private getCollapsedCountLabel(): string {
    return this.items.length > 99 ? '99+' : this.items.length.toString();
  }

  private getExpandedSummary(): string {
    if (this.items.length <= 0) {
      return '暂无内容';
    }
    if (this.items.length === 1) {
      return '1 条稍后阅读';
    }
    return `${this.items.length} 条稍后阅读`;
  }

  build() {
    if (this.items.length > 0 || this.isSheetVisible) {
      Row() {
        if (!this.isExpanded && !this.isSheetVisible && !this.isDockOnLeft()) {
          Blank().layoutWeight(1)
        }

        Row() {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(18)
            .fontColor([$r('app.color.primary')])
        }
        .width(30)
        .height(30)
        .borderRadius(15)
        .backgroundColor($r('app.color.search_background'))
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)

        if (this.isExpanded || this.isSheetVisible) {
          Column() {
            Text('浮窗')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.on_surface'))
            Text(this.getExpandedSummary())
              .fontSize(11)
              .fontColor($r('app.color.on_surface_secondary'))
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .margin({ left: 10, right: 8 })
          .alignItems(HorizontalAlign.Start)

          Row() {
            Text(this.getCollapsedCountLabel())
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary'))
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor($r('app.color.search_background'))
          .borderRadius(10)

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([$r('app.color.on_surface_tertiary')])
            .margin({ left: 8 })
        } else if (this.isDockOnLeft()) {
          Blank().layoutWeight(1)
        }
      }
      .width(this.getDockWidth())
      .height(DOCK_HEIGHT)
      .padding({ left: 10, right: 12 })
      .borderRadius(24)
      .backgroundColor($r('app.color.surface'))
      .border({ width: 0.5, color: $r('app.color.fab_glass_stroke') })
      .shadow({ radius: 16, color: '#22000000', offsetX: 0, offsetY: 8 })
      .clip(true)
      .position({ x: this.getDockPositionX(), y: DOCK_VERTICAL_POSITION })
      .translate({ x: this.getDockTranslateX(), y: this.getDockTranslateY() })
      .animation({ duration: 240, curve: Curve.EaseOut })
      .onClick(() => {
        this.handleDockTap();
      })
      .bindSheet($$this.isSheetVisible, this.ReadLaterSheetBuilder, {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: false,
        backgroundColor: $r('app.color.surface'),
        onDisappear: () => {
          this.closeSheet();
        }
      })
    } else {
      Blank()
        .width(0)
        .height(0)
    }
  }

  @Builder
  private ReadLaterRow(item: ReadLaterItem) {
    Row() {
      Column() {
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          Text(TimeUtils.formatRelativeTime(item.addedAt))
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
          if (item.postNumber > 0) {
            Text(` · 第 ${item.postNumber} 楼`)
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'))
          }
        }
        .margin({ top: 6 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

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
        this.removeItem(item);
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.surface'))
    .border({
      width: { bottom: 0.5 },
      color: $r('app.color.divider')
    })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openItem(item);
    })
  }

  @Builder
  private ReadLaterSheetBuilder() {
    Column() {
      Row() {
        Text('浮窗')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
        Text(`${this.items.length}/${MAX_READ_LATER_ITEMS}`)
          .fontSize(13)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      if (this.items.length === 0) {
        Column() {
          Text('暂无浮窗内容')
            .fontSize(14)
            .fontColor($r('app.color.on_surface_secondary'))
        }
        .width('100%')
        .padding({ top: 48, bottom: 48 })
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.items, (item: ReadLaterItem) => {
            ListItem() {
              this.ReadLaterRow(item)
            }
          }, (item: ReadLaterItem) => item.topicId.toString())
        }
        .width('100%')
        .constraintSize({ maxHeight: '70%' })
        .scrollBar(BarState.Off)
      }

      Blank().height(12 + this.getBottomOffsetVp())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
