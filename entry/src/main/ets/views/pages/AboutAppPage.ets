import { AppConstants } from '../../common/constants/AppConstants';
import { PreferencesUtil } from '../../services/storage/PreferencesUtil';
import { ExternalLinkService } from '../../common/utils/ExternalLinkService';
import { RouterManager } from '../../common/utils/RouterManager';
import { ToastService } from '../../common/utils/ToastService';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { ImmersiveHdsTitleBarHelper } from '../components/ImmersiveHdsTitleBarHelper';

const TAG: string = 'AboutAppPage';
const PREF_KEY_DEVELOPER_MODE: string = 'about_app_developer_mode_enabled';

type AboutAppItemKey = 'openSource' | 'developerModeToggle' | 'sourceCode' | 'appLogs' | 'feedback';

interface AboutAppSectionDescriptor {
  title: string;
  itemKeys: AboutAppItemKey[];
}

@ComponentV2
export struct AboutAppPage {
  @Local version: string = '';
  @Local developerModeEnabled: boolean = false;
  @Local versionTapCount: number = 0;
  @Local lastTapTimestamp: number = 0;

  private contentScroller: Scroller = new Scroller();

  private static readonly TAP_THRESHOLD: number = 7;
  private static readonly TAP_INTERVAL_MS: number = 2000;

  aboutToAppear(): void {
    this.loadVersion().catch(() => {});
    this.loadDeveloperMode().catch(() => {});
  }

  private async loadVersion(): Promise<void> {
    this.version = '1.0.0';
  }

  private async loadDeveloperMode(): Promise<void> {
    await PreferencesUtil.ensureInit();
    this.developerModeEnabled = await PreferencesUtil.getBoolean(PREF_KEY_DEVELOPER_MODE, false);
  }

  private async saveDeveloperMode(enabled: boolean): Promise<void> {
    this.developerModeEnabled = enabled;
    await PreferencesUtil.ensureInit();
    await PreferencesUtil.putBoolean(PREF_KEY_DEVELOPER_MODE, enabled);
  }

  private async onVersionTapped(): Promise<void> {
    const now: number = Date.now();
    if (this.lastTapTimestamp === 0 || now - this.lastTapTimestamp > AboutAppPage.TAP_INTERVAL_MS) {
      this.versionTapCount = 0;
    }
    this.lastTapTimestamp = now;
    this.versionTapCount = this.versionTapCount + 1;

    if (this.versionTapCount >= AboutAppPage.TAP_THRESHOLD && !this.developerModeEnabled) {
      this.versionTapCount = 0;
      await this.saveDeveloperMode(true);
      ToastService.show('开发者模式已开启');
    }
  }

  private onOpenSourceInfoClicked(): void {
    RouterManager.pushOpenSourceInfo();
  }

  private onSourceCodeClicked(): void {
    ExternalLinkService.openInBrowser(AppConstants.SOURCE_CODE_URL).catch(() => {});
  }

  private onAppLogsClicked(): void {
    RouterManager.pushAppLogs();
  }

  private onFeedbackClicked(): void {
    ExternalLinkService.openInBrowser(AppConstants.ISSUES_URL).catch(() => {});
  }

  private getSections(): AboutAppSectionDescriptor[] {
    const developItemKeys: AboutAppItemKey[] = this.developerModeEnabled
      ? ['developerModeToggle', 'sourceCode', 'appLogs', 'feedback']
      : ['sourceCode', 'appLogs', 'feedback'];

    return [
      {
        title: '信息',
        itemKeys: ['openSource']
      },
      {
        title: '开发',
        itemKeys: developItemKeys
      }
    ];
  }

  private getFooterLines(): string[] {
    return [
      'LDO社区是 Linux.do 的第三方鸿蒙客户端',
      '灵感来自 FluxDO，感谢社区与开源作者'
    ];
  }

  private resolveItemSymbol(itemKey: AboutAppItemKey): Resource {
    switch (itemKey) {
      case 'openSource':
        return $r('sys.symbol.doc_text');
      case 'sourceCode':
        return $r('sys.symbol.code');
      case 'appLogs':
        return $r('sys.symbol.doc_text');
      case 'feedback':
        return $r('sys.symbol.exclamationmark_triangle');
      default:
        return $r('sys.symbol.gearshape');
    }
  }

  private resolveItemTitle(itemKey: AboutAppItemKey): string {
    switch (itemKey) {
      case 'openSource':
        return '开源信息';
      case 'sourceCode':
        return '源代码';
      case 'appLogs':
        return '应用日志';
      case 'feedback':
        return '问题反馈';
      default:
        return '开发者模式';
    }
  }

  private resolveItemSubtitle(itemKey: AboutAppItemKey): string {
    switch (itemKey) {
      case 'openSource':
        return '查看 LDO社区与 FluxDO 的开源说明';
      case 'sourceCode':
        return 'GitHub';
      case 'appLogs':
        return '调试和排查问题时使用';
      case 'feedback':
        return '在 GitHub Issues 提交反馈';
      default:
        return '点击下方开关即可关闭开发者模式';
    }
  }

  private handleItemClick(itemKey: AboutAppItemKey): void {
    switch (itemKey) {
      case 'openSource':
        this.onOpenSourceInfoClicked();
        return;
      case 'sourceCode':
        this.onSourceCodeClicked();
        return;
      case 'appLogs':
        this.onAppLogsClicked();
        return;
      case 'feedback':
        this.onFeedbackClicked();
        return;
      default:
        return;
    }
  }

  @Builder
  private HeaderSection() {
    Column({ space: 8 }) {
      Image($r('app.media.startIcon'))
        .width(92)
        .height(92)
        .borderRadius(20);

      Text(AppConstants.APP_NAME)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'));

      Text(`Version ${this.version}`)
        .fontSize(14)
        .fontColor($r('app.color.on_surface_secondary'))
        .onClick(() => {
          this.onVersionTapped().catch(() => {});
        });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 32, bottom: 28 });
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
  private ActionRow(itemKey: AboutAppItemKey, isLast: boolean) {
    Column() {
      if (itemKey === 'developerModeToggle') {
        Row() {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(20)
            .fontColor([$r('app.color.on_surface_secondary')])
            .width(24);

          Column({ space: 2 }) {
            Text(this.resolveItemTitle(itemKey))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.on_surface'));
            Text(this.resolveItemSubtitle(itemKey))
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'));
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 16 });

          Toggle({ type: ToggleType.Switch, isOn: this.developerModeEnabled })
            .onChange((value: boolean) => {
              if (!value) {
                this.saveDeveloperMode(false).catch(() => {});
              }
            });
        }
        .width('100%')
        .height(56)
        .padding({ top: 10, bottom: 10 })
        .alignItems(VerticalAlign.Center);
      } else {
        Row() {
          SymbolGlyph(this.resolveItemSymbol(itemKey))
            .fontSize(20)
            .fontColor([$r('app.color.on_surface_secondary')])
            .width(24);

          Column({ space: 2 }) {
            Text(this.resolveItemTitle(itemKey))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.on_surface'));
            Text(this.resolveItemSubtitle(itemKey))
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'));
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 16 });

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('app.color.on_surface_tertiary')]);
        }
        .width('100%')
        .height(56)
        .padding({ top: 10, bottom: 10 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.handleItemClick(itemKey);
        });
      }

      if (!isLast) {
        Divider()
          .strokeWidth(1)
          .color($r('app.color.divider'))
          .margin({ left: 40 });
      }
    }
    .width('100%')
    .padding({ left: 24, right: 24 });
  }

  @Builder
  private FooterSection() {
    Column({ space: 8 }) {
      Text(this.getFooterLines()[0])
        .fontSize(12)
        .fontColor($r('app.color.on_surface_secondary'))
        .textAlign(TextAlign.Center);
      Text(this.getFooterLines()[1])
        .fontSize(11)
        .fontColor($r('app.color.on_surface_tertiary'))
        .textAlign(TextAlign.Center);
    }
    .width('100%')
    .padding({ top: 40, bottom: 20 });
  }

  build() {
    HdsNavDestination() {
      Column() {
        Scroll(this.contentScroller) {
          Column() {
            Blank()
              .height(ImmersiveHdsTitleBarHelper.getContentTopSpacerHeightVp())
              .width('100%');

            this.HeaderSection();

            ForEach(this.getSections(), (section: AboutAppSectionDescriptor, sectionIndex: number) => {
              this.SectionTitle(section.title);
              Column() {
                ForEach(section.itemKeys, (itemKey: AboutAppItemKey, itemIndex: number) => {
                  this.ActionRow(itemKey, itemIndex === section.itemKeys.length - 1);
                }, (itemKey: AboutAppItemKey) => itemKey);
              }
              .width('100%');

              if (sectionIndex < this.getSections().length - 1) {
                Divider()
                  .strokeWidth(1)
                  .color($r('app.color.divider'))
                  .margin({ left: 24, right: 24, top: 24, bottom: 8 });
              }
            }, (section: AboutAppSectionDescriptor) => section.title);

            this.FooterSection();
          }
          .width('100%')
          .padding({ bottom: 16 });
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring);
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'));
    }
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .titleBar(ImmersiveHdsTitleBarHelper.buildImmersiveTitleBar($r('app.string.profile_about_app')))
    .backgroundColor($r('app.color.background'))
    .hideTitleBar(false)
    .hideBackButton(false)
    .hideToolBar(true)
    .bindToScrollable([this.contentScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .systemBarStyle(
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() },
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() }
    )
  }
}
