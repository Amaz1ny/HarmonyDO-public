import {
  HdsNavDestination,
  HdsNavDestinationTitleMode
} from '@kit.UIDesignKit';
import { FeatureSettingsService, FeatureSettingsState } from '../../services/storage/FeatureSettingsService';
import { ToastService } from '../../common/utils/ToastService';
import { ImmersiveHdsTitleBarHelper } from '../components/ImmersiveHdsTitleBarHelper';

const PAGE_HORIZONTAL_PADDING: number = 16;
const CARD_CORNER_RADIUS: number = 20;
const INPUT_CORNER_RADIUS: number = 14;

interface FeatureSettingsSection {
  title: Resource;
  subtitle: Resource;
  keys: string[];
}

@ComponentV2
export struct FeatureSettingsPage {
  @Local anonymousShare: boolean = false;
  @Local autoFillLogin: boolean = true;
  @Local autoPanguSpacing: boolean = false;
  @Local portraitLock: boolean = false;
  @Local stickerSource: string = FeatureSettingsService.DEFAULT_STICKER_SOURCE;
  @Local stickerSourceDraft: string = FeatureSettingsService.DEFAULT_STICKER_SOURCE;
  @Local isLoading: boolean = true;
  @Local isSavingStickerSource: boolean = false;
  @Local stickerSourceError: string = '';

  private contentScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadSettings().catch(() => {
      this.isLoading = false;
      ToastService.show('功能设置加载失败');
    });
  }

  private async loadSettings(): Promise<void> {
    this.isLoading = true;
    const state: FeatureSettingsState = await FeatureSettingsService.getInstance().loadSettings();
    this.applyState(state);
    this.stickerSourceDraft = state.stickerSource;
    this.stickerSourceError = '';
    this.isLoading = false;
  }

  private applyState(state: FeatureSettingsState): void {
    this.anonymousShare = state.anonymousShare;
    this.autoFillLogin = state.autoFillLogin;
    this.autoPanguSpacing = state.autoPanguSpacing;
    this.portraitLock = state.portraitLock;
    this.stickerSource = state.stickerSource;
  }

  private getSections(): FeatureSettingsSection[] {
    return [
      {
        title: $r('app.string.feature_settings_section_general_title'),
        subtitle: $r('app.string.feature_settings_section_general_subtitle'),
        keys: ['anonymousShare', 'autoFillLogin', 'portraitLock']
      },
      {
        title: $r('app.string.feature_settings_section_editor_title'),
        subtitle: $r('app.string.feature_settings_section_editor_subtitle'),
        keys: ['autoPanguSpacing']
      },
      {
        title: $r('app.string.feature_settings_section_sticker_title'),
        subtitle: $r('app.string.feature_settings_section_sticker_subtitle'),
        keys: ['stickerSource']
      }
    ];
  }

  private async onAnonymousShareChanged(value: boolean): Promise<void> {
    this.anonymousShare = value;
    try {
      const state: FeatureSettingsState = await FeatureSettingsService.getInstance().setAnonymousShare(value);
      this.applyState(state);
    } catch (_) {
      this.anonymousShare = !value;
      ToastService.show($r('app.string.feature_settings_save_failed'));
    }
  }

  private async onAutoFillLoginChanged(value: boolean): Promise<void> {
    this.autoFillLogin = value;
    try {
      const state: FeatureSettingsState = await FeatureSettingsService.getInstance().setAutoFillLogin(value);
      this.applyState(state);
    } catch (_) {
      this.autoFillLogin = !value;
      ToastService.show($r('app.string.feature_settings_save_failed'));
    }
  }

  private async onAutoPanguSpacingChanged(value: boolean): Promise<void> {
    this.autoPanguSpacing = value;
    try {
      const state: FeatureSettingsState = await FeatureSettingsService.getInstance().setAutoPanguSpacing(value);
      this.applyState(state);
    } catch (_) {
      this.autoPanguSpacing = !value;
      ToastService.show($r('app.string.feature_settings_save_failed'));
    }
  }

  private async onPortraitLockChanged(value: boolean): Promise<void> {
    this.portraitLock = value;
    try {
      const state: FeatureSettingsState = await FeatureSettingsService.getInstance().setPortraitLock(value);
      this.applyState(state);
    } catch (_) {
      this.portraitLock = !value;
      ToastService.show($r('app.string.feature_settings_save_failed'));
    }
  }

  private async saveStickerSource(): Promise<void> {
    if (this.isSavingStickerSource) {
      return;
    }
    this.isSavingStickerSource = true;
    this.stickerSourceError = '';
    try {
      const state: FeatureSettingsState = await FeatureSettingsService.getInstance().setStickerSource(this.stickerSourceDraft);
      this.applyState(state);
      this.stickerSourceDraft = state.stickerSource;
      ToastService.show($r('app.string.feature_settings_sticker_source_saved'));
    } catch (err) {
      this.stickerSourceError = err !== undefined && err !== null ? err.toString() : 'Sticker 源保存失败';
      ToastService.show(this.stickerSourceError);
    } finally {
      this.isSavingStickerSource = false;
    }
  }

  private async resetStickerSource(): Promise<void> {
    if (this.isSavingStickerSource) {
      return;
    }
    this.isSavingStickerSource = true;
    this.stickerSourceError = '';
    try {
      const state: FeatureSettingsState = await FeatureSettingsService.getInstance().resetStickerSource();
      this.applyState(state);
      this.stickerSourceDraft = state.stickerSource;
      ToastService.show($r('app.string.feature_settings_sticker_source_reset_done'));
    } catch (_) {
      ToastService.show($r('app.string.feature_settings_save_failed'));
    } finally {
      this.isSavingStickerSource = false;
    }
  }

  private resolveItemTitle(key: string): Resource {
    switch (key) {
      case 'anonymousShare':
        return $r('app.string.feature_settings_anonymous_share_title');
      case 'autoFillLogin':
        return $r('app.string.feature_settings_auto_fill_login_title');
      case 'autoPanguSpacing':
        return $r('app.string.feature_settings_auto_pangu_title');
      case 'portraitLock':
        return $r('app.string.feature_settings_portrait_lock_title');
      default:
        return $r('app.string.feature_settings_sticker_source_title');
    }
  }

  private resolveItemSubtitle(key: string): Resource {
    switch (key) {
      case 'anonymousShare':
        return $r('app.string.feature_settings_anonymous_share_subtitle');
      case 'autoFillLogin':
        return $r('app.string.feature_settings_auto_fill_login_subtitle');
      case 'autoPanguSpacing':
        return $r('app.string.feature_settings_auto_pangu_subtitle');
      case 'portraitLock':
        return $r('app.string.feature_settings_portrait_lock_subtitle');
      default:
        return $r('app.string.feature_settings_sticker_source_subtitle');
    }
  }

  private getToggleState(key: string): boolean {
    switch (key) {
      case 'anonymousShare':
        return this.anonymousShare;
      case 'autoFillLogin':
        return this.autoFillLogin;
      case 'autoPanguSpacing':
        return this.autoPanguSpacing;
      default:
        return this.portraitLock;
    }
  }

  private onToggleChange(key: string, value: boolean): void {
    switch (key) {
      case 'anonymousShare':
        this.onAnonymousShareChanged(value).catch(() => {});
        return;
      case 'autoFillLogin':
        this.onAutoFillLoginChanged(value).catch(() => {});
        return;
      case 'autoPanguSpacing':
        this.onAutoPanguSpacingChanged(value).catch(() => {});
        return;
      default:
        this.onPortraitLockChanged(value).catch(() => {});
        return;
    }
  }

  @Builder
  private SectionTitle(section: FeatureSettingsSection) {
    Column() {
      Text(section.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'));
      Text(section.subtitle)
        .fontSize(12)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ top: 4 });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 20, bottom: 12 });
  }

  @Builder
  private ToggleRow(key: string, isLast: boolean) {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text(this.resolveItemTitle(key))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'));
          Text(this.resolveItemSubtitle(key))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.on_surface_secondary'));
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ right: 12 });

        Toggle({ type: ToggleType.Switch, isOn: this.getToggleState(key) })
          .onChange((value: boolean) => {
            this.onToggleChange(key, value);
          });
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .alignItems(VerticalAlign.Center);

      if (!isLast) {
        Divider()
          .strokeWidth(1)
          .color($r('app.color.divider'));
      }
    }
    .width('100%');
  }

  @Builder
  private StickerSourceCard() {
    Column() {
      Text(this.resolveItemTitle('stickerSource'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface'));
      Text(this.resolveItemSubtitle('stickerSource'))
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ top: 4, bottom: 12 });

      TextInput({
        text: this.stickerSourceDraft,
        placeholder: $r('app.string.feature_settings_sticker_source_placeholder')
      })
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(INPUT_CORNER_RADIUS)
        .border({ width: 1, color: $r('app.color.input_border') })
        .padding({ left: 12, right: 12 })
        .height(44)
        .onChange((value: string) => {
          this.stickerSourceDraft = value;
          this.stickerSourceError = '';
        });

      Text(`${getContext().resourceManager.getStringSync($r('app.string.feature_settings_sticker_source_current').id)}：${this.stickerSource}`)
        .fontSize(11)
        .fontColor($r('app.color.on_surface_tertiary'))
        .margin({ top: 10 });

      if (this.stickerSourceError.length > 0) {
        Text(this.stickerSourceError)
          .fontSize(12)
          .fontColor($r('app.color.error'))
          .margin({ top: 8 });
      }

      Row({ space: 12 }) {
        Button(this.isSavingStickerSource
          ? $r('app.string.feature_settings_sticker_source_saving')
          : $r('app.string.feature_settings_sticker_source_save'), {
          type: ButtonType.Capsule,
          stateEffect: true
        })
          .enabled(!this.isSavingStickerSource)
          .layoutWeight(1)
          .backgroundColor($r('app.color.primary'))
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.saveStickerSource().catch(() => {});
          });

        Button($r('app.string.feature_settings_sticker_source_reset'), {
          type: ButtonType.Capsule,
          stateEffect: true
        })
          .enabled(!this.isSavingStickerSource)
          .layoutWeight(1)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.on_surface'))
          .border({ width: 1, color: $r('app.color.divider') })
          .onClick(() => {
            this.resetStickerSource().catch(() => {});
          });
      }
      .width('100%')
      .margin({ top: 16 });
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(CARD_CORNER_RADIUS)
    .border({ width: 1, color: $r('app.color.divider_light') });
  }

  build() {
    HdsNavDestination() {
      Column() {
        Scroll(this.contentScroller) {
          Column() {
            Blank()
              .height(ImmersiveHdsTitleBarHelper.getContentTopSpacerHeightVp())
              .width('100%');

            ForEach(this.getSections(), (section: FeatureSettingsSection) => {
              this.SectionTitle(section);
              if (section.keys[0] === 'stickerSource') {
                this.StickerSourceCard();
              } else {
                Column() {
                  ForEach(section.keys, (key: string, index: number) => {
                    this.ToggleRow(key, index === section.keys.length - 1);
                  }, (key: string) => key);
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 4, bottom: 4 })
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(CARD_CORNER_RADIUS)
                .border({ width: 1, color: $r('app.color.divider_light') });
              }
            }, (section: FeatureSettingsSection) => section.keys.join('_'));
          }
          .width('100%')
          .padding({ left: PAGE_HORIZONTAL_PADDING, right: PAGE_HORIZONTAL_PADDING, top: 16, bottom: 24 })
          .alignItems(HorizontalAlign.Start);
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'));
    }
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .titleBar(ImmersiveHdsTitleBarHelper.buildImmersiveTitleBar($r('app.string.profile_feature_settings')))
    .hideTitleBar(false)
    .hideBackButton(false)
    .hideToolBar(true)
    .bindToScrollable([this.contentScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .systemBarStyle(
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() },
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() }
    )
    .backgroundColor($r('app.color.background'));
  }
}
