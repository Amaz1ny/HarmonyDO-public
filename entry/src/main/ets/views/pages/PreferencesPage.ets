import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppSettingsService } from '../../services/storage/AppSettingsService';
import { RouterManager } from '../../common/utils/RouterManager';
import { WindowManager } from '../../common/utils/WindowManager';

const TOP_BAR_HEIGHT: number = 56;

@ComponentV2
export struct PreferencesPage {
  @Local longPressPreview: boolean = true;
  @Local hideBarOnScroll: boolean = true;
  @Local openLinksInAppBrowser: boolean = true;
  @Local anonymousShare: boolean = true;
  @Local autoFillLogin: boolean = true;
  @Local portraitLock: boolean = false;
  @Local autoPanguSpacing: boolean = false;

  private settingsListener: (() => void) | null = null;

  aboutToAppear(): void {
    this.attachSettingsListener();
  }

  aboutToDisappear(): void {
    if (this.settingsListener !== null) {
      AppSettingsService.getInstance().removeListener(this.settingsListener);
      this.settingsListener = null;
    }
  }

  private attachSettingsListener(): void {
    if (this.settingsListener !== null) {
      return;
    }
    this.settingsListener = () => {
      this.syncFromService();
    };
    AppSettingsService.getInstance().addListener(this.settingsListener);
    AppSettingsService.getInstance().ensureInit().then(() => {
      this.syncFromService();
    }).catch(() => {
    });
  }

  private syncFromService(): void {
    const featureSettings = AppSettingsService.getInstance().getFeatureSettings();
    this.longPressPreview = featureSettings.longPressPreview;
    this.hideBarOnScroll = featureSettings.hideBarOnScroll;
    this.openLinksInAppBrowser = featureSettings.openLinksInAppBrowser;
    this.anonymousShare = featureSettings.anonymousShare;
    this.autoFillLogin = featureSettings.autoFillLogin;
    this.portraitLock = featureSettings.portraitLock;
    this.autoPanguSpacing = featureSettings.autoPanguSpacing;
  }

  @Builder
  private TopBar() {
    Row() {
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

      Text('功能设置')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private SectionTitle(title: string, icon: Resource) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([AppSettingsService.getInstance().getPrimaryColor()])
        .margin({ right: 8 })
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface'))
    }
    .margin({ top: 16, bottom: 10 })
  }

  @Builder
  private ToggleRow(title: string, desc: string, enabled: boolean, onToggle: () => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
        Text(desc)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row() {
        Text(enabled ? '已开启' : '已关闭')
          .fontSize(12)
          .fontColor(enabled ? AppSettingsService.getInstance().getPrimaryColor() : $r('app.color.on_surface_secondary'))
      }
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .backgroundColor(enabled ? AppSettingsService.getInstance().getPrimaryColorWithAlpha(0.12) : $r('app.color.surface_variant'))
      .borderRadius(16)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
    .margin({ bottom: 10 })
    .onClick(() => {
      onToggle();
    })
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column() {
          this.TopBar()

          Column() {
            this.SectionTitle('基础', $r('sys.symbol.gearshape'))
            this.ToggleRow('长按预览', '控制首页、分类、我的话题和书签卡片的长按预览', this.longPressPreview, () => {
              AppSettingsService.getInstance().setLongPressPreview(!this.longPressPreview).catch(() => {
              });
            })
            this.ToggleRow('滚动时隐藏导航', '控制首页滚动时顶栏和底部悬浮导航的自动收起', this.hideBarOnScroll, () => {
              AppSettingsService.getInstance().setHideBarOnScroll(!this.hideBarOnScroll).catch(() => {
              });
            })
            this.ToggleRow('站内外链优先应用内打开', '控制链接默认进入应用内 WebView 还是外部浏览器', this.openLinksInAppBrowser, () => {
              AppSettingsService.getInstance().setOpenLinksInAppBrowser(!this.openLinksInAppBrowser).catch(() => {
              });
            })
            this.ToggleRow('匿名分享', '关闭后会在分享链接里带上当前用户名参数', this.anonymousShare, () => {
              AppSettingsService.getInstance().setAnonymousShare(!this.anonymousShare).catch(() => {
              });
            })
            this.ToggleRow('自动填充登录账号', '在登录 WebView 中自动填入上次登录的账号', this.autoFillLogin, () => {
              AppSettingsService.getInstance().setAutoFillLogin(!this.autoFillLogin).catch(() => {
              });
            })
            this.ToggleRow('锁定竖屏', '切换后立即尝试更新窗口方向偏好', this.portraitLock, () => {
              AppSettingsService.getInstance().setPortraitLock(!this.portraitLock).catch(() => {
              });
            })

            this.SectionTitle('编辑器', $r('sys.symbol.square_and_pencil'))
            this.ToggleRow('自动盘古空格', '在发帖、回复和私信提交前自动补齐中英文之间的空格', this.autoPanguSpacing, () => {
              AppSettingsService.getInstance().setAutoPanguSpacing(!this.autoPanguSpacing).catch(() => {
              });
            })
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 24 + WindowManager.getSystemAvoidAreaBottomVp() })
        }
        .width('100%')
        .padding({ top: WindowManager.getSystemAvoidAreaTopVp() })
        .backgroundColor($r('app.color.background'))
      }
      .backgroundColor($r('app.color.background'))
    }
    .backgroundColor($r('app.color.background'))
    .hideTitleBar(true)
    .hideToolBar(true)
  }
}
