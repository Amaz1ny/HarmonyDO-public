import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { WindowManager } from '../../common/utils/WindowManager';
import { ExternalLinkService } from '../../common/utils/ExternalLinkService';
import { ToastService } from '../../common/utils/ToastService';
import { ImmersiveHdsTitleBarHelper } from '../components/ImmersiveHdsTitleBarHelper';
import {
  buildOpenSourceSections,
  OpenSourceInfoItem,
  OpenSourceInfoSection,
  OpenSourceItemActionType
} from '../../common/utils/OpenSourceInfoContract';

@ComponentV2
export struct OpenSourceInfoPage {
  private contentScroller: Scroller = new Scroller();

  private onItemClicked(item: OpenSourceInfoItem): void {
    if (item.actionType !== OpenSourceItemActionType.External || item.url.length === 0) {
      return;
    }
    ExternalLinkService.openInBrowser(item.url).catch(() => {
      ToastService.show('无法打开浏览器');
    });
  }

  @Builder
  private SectionTitle(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.primary'))
      .margin({ left: 24, right: 24, top: 8, bottom: 8 });
  }

  @Builder
  private InfoRow(item: OpenSourceInfoItem, isLast: boolean) {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text(item.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'));
          Text(item.subtitle)
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'));
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        if (item.actionType === OpenSourceItemActionType.External) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('app.color.on_surface_tertiary')]);
        }
      }
      .width('100%')
      .height(56)
      .padding({ top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.onItemClicked(item));

      if (!isLast) {
        Divider()
          .strokeWidth(1)
          .color($r('app.color.divider'));
      }
    }
    .width('100%')
    .padding({ left: 24, right: 24 });
  }

  build() {
    HdsNavDestination() {
      Column() {
        Scroll(this.contentScroller) {
          Column() {
            Blank()
              .height(ImmersiveHdsTitleBarHelper.getContentTopSpacerHeightVp())
              .width('100%');

            ForEach(buildOpenSourceSections(), (section: OpenSourceInfoSection, sectionIndex: number) => {
              this.SectionTitle(section.title);
              Column() {
                ForEach(section.items, (item: OpenSourceInfoItem, itemIndex: number) => {
                  this.InfoRow(item, itemIndex === section.items.length - 1);
                }, (item: OpenSourceInfoItem) => `${section.title}-${item.title}`);
              }
              .width('100%');

              if (sectionIndex < buildOpenSourceSections().length - 1) {
                Divider()
                  .strokeWidth(1)
                  .color($r('app.color.divider'))
                  .margin({ left: 24, right: 24, top: 24, bottom: 8 });
              }
            }, (section: OpenSourceInfoSection) => section.title);
          }
          .width('100%')
          .padding({ top: 12, bottom: 20 + WindowManager.getSystemAvoidAreaBottomVp() });
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .layoutWeight(1)
        .width('100%');
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'));
    }
    .backgroundColor($r('app.color.background'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .titleBar(ImmersiveHdsTitleBarHelper.buildImmersiveTitleBar('开源信息'))
    .hideTitleBar(false)
    .hideBackButton(false)
    .hideToolBar(true)
    .bindToScrollable([this.contentScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .systemBarStyle(
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() },
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() }
    );
  }
}
