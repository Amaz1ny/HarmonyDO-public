import {
  HdsNavDestination,
  HdsNavDestinationTitleMode
} from '@kit.UIDesignKit';
import {
  APPEARANCE_ACCENT_COLOR_AMBER,
  APPEARANCE_ACCENT_COLOR_BLUE,
  APPEARANCE_ACCENT_COLOR_CYAN,
  APPEARANCE_ACCENT_COLOR_GREEN,
  APPEARANCE_ACCENT_COLOR_INDIGO,
  APPEARANCE_ACCENT_COLOR_ORANGE,
  APPEARANCE_ACCENT_COLOR_PINK,
  APPEARANCE_ACCENT_COLOR_PURPLE,
  APPEARANCE_ACCENT_COLOR_RED,
  APPEARANCE_ACCENT_COLOR_TEAL,
  APPEARANCE_THEME_MODE_DARK,
  APPEARANCE_THEME_MODE_LIGHT,
  APPEARANCE_THEME_MODE_SYSTEM,
  AppearanceAccentColor,
  AppearanceSettingsService,
  AppearanceSettingsState,
  AppearanceThemeMode
} from '../../services/storage/AppearanceSettingsService';
import { ToastService } from '../../common/utils/ToastService';
import { ImmersiveHdsTitleBarHelper } from '../components/ImmersiveHdsTitleBarHelper';
import { ThemeManager } from '../../common/theme/ThemeManager';

const PAGE_HORIZONTAL_PADDING: number = 16;
const ACCENT_SWATCH_SIZE: number = 72;
const ACCENT_SWATCH_CARD_WIDTH: number = 84;

interface ThemeModeOption {
  mode: AppearanceThemeMode;
  title: Resource;
  subtitle: Resource;
  icon: Resource;
}

interface AccentColorOption {
  color: AppearanceAccentColor;
  title: Resource;
}

@ComponentV2
export struct AppearanceSettingsPage {
  @Local themeMode: AppearanceThemeMode = APPEARANCE_THEME_MODE_SYSTEM;
  @Local accentColor: AppearanceAccentColor = APPEARANCE_ACCENT_COLOR_BLUE;
  @Local isLoading: boolean = true;

  private contentScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadSettings().catch(() => {
      this.isLoading = false;
      ToastService.show($r('app.string.appearance_settings_load_failed'));
    });
  }

  private async loadSettings(): Promise<void> {
    this.isLoading = true;
    const state: AppearanceSettingsState = await AppearanceSettingsService.getInstance().loadSettings();
    this.applyState(state);
    this.isLoading = false;
  }

  private applyState(state: AppearanceSettingsState): void {
    this.themeMode = state.themeMode;
    this.accentColor = state.accentColor;
  }

  private getThemeModeOptions(): ThemeModeOption[] {
    return [
      {
        mode: APPEARANCE_THEME_MODE_SYSTEM,
        title: $r('app.string.appearance_settings_theme_mode_system'),
        subtitle: $r('app.string.appearance_settings_theme_mode_system_subtitle'),
        icon: $r('sys.symbol.gearshape')
      },
      {
        mode: APPEARANCE_THEME_MODE_LIGHT,
        title: $r('app.string.appearance_settings_theme_mode_light'),
        subtitle: $r('app.string.appearance_settings_theme_mode_light_subtitle'),
        icon: $r('sys.symbol.circle')
      },
      {
        mode: APPEARANCE_THEME_MODE_DARK,
        title: $r('app.string.appearance_settings_theme_mode_dark'),
        subtitle: $r('app.string.appearance_settings_theme_mode_dark_subtitle'),
        icon: $r('sys.symbol.drop')
      }
    ];
  }

  private getAccentColorOptions(): AccentColorOption[] {
    return [
      { color: APPEARANCE_ACCENT_COLOR_BLUE, title: $r('app.string.appearance_settings_accent_blue') },
      { color: APPEARANCE_ACCENT_COLOR_PURPLE, title: $r('app.string.appearance_settings_accent_purple') },
      { color: APPEARANCE_ACCENT_COLOR_GREEN, title: $r('app.string.appearance_settings_accent_green') },
      { color: APPEARANCE_ACCENT_COLOR_ORANGE, title: $r('app.string.appearance_settings_accent_orange') },
      { color: APPEARANCE_ACCENT_COLOR_PINK, title: $r('app.string.appearance_settings_accent_pink') },
      { color: APPEARANCE_ACCENT_COLOR_TEAL, title: $r('app.string.appearance_settings_accent_teal') },
      { color: APPEARANCE_ACCENT_COLOR_RED, title: $r('app.string.appearance_settings_accent_red') },
      { color: APPEARANCE_ACCENT_COLOR_INDIGO, title: $r('app.string.appearance_settings_accent_indigo') },
      { color: APPEARANCE_ACCENT_COLOR_AMBER, title: $r('app.string.appearance_settings_accent_amber') },
      { color: APPEARANCE_ACCENT_COLOR_CYAN, title: $r('app.string.appearance_settings_accent_cyan') }
    ];
  }

  private getCurrentAccentColorHex(): string {
    return ThemeManager.getAccentColorHex(this.accentColor);
  }

  private getCurrentAccentBackgroundColorHex(): string {
    return ThemeManager.getAccentBackgroundColorHex(this.accentColor);
  }

  private getCurrentAccentSurfaceColorHex(): string {
    return ThemeManager.getAccentSurfaceColorHex(this.accentColor);
  }

  private getCurrentAccentSurfaceVariantColorHex(): string {
    return ThemeManager.getAccentSurfaceVariantColorHex(this.accentColor);
  }

  private async onThemeModeSelected(mode: AppearanceThemeMode): Promise<void> {
    if (this.themeMode === mode) {
      return;
    }
    const previous: AppearanceThemeMode = this.themeMode;
    this.themeMode = mode;
    try {
      const state: AppearanceSettingsState = await AppearanceSettingsService.getInstance().setThemeMode(mode);
      this.applyState(state);
    } catch (_) {
      this.themeMode = previous;
      ToastService.show($r('app.string.appearance_settings_save_failed'));
    }
  }

  private async onAccentColorSelected(color: AppearanceAccentColor): Promise<void> {
    if (this.accentColor === color) {
      return;
    }
    const previous: AppearanceAccentColor = this.accentColor;
    this.accentColor = color;
    try {
      const state: AppearanceSettingsState = await AppearanceSettingsService.getInstance().setAccentColor(color);
      this.applyState(state);
    } catch (_) {
      this.accentColor = previous;
      ToastService.show($r('app.string.appearance_settings_save_failed'));
    }
  }

  @Builder
  private SectionTitle(title: Resource, subtitle: Resource) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'));
      Text(subtitle)
        .fontSize(12)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ top: 4 });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 20, bottom: 12 });
  }

  @Builder
  private ThemeModeCard(option: ThemeModeOption) {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(42)
          .height(42)
          .fill(this.themeMode === option.mode ? this.getCurrentAccentColorHex() : $r('app.color.surface_variant'));
        SymbolGlyph(option.icon)
          .fontSize(20)
          .fontColor([this.themeMode === option.mode ? Color.White : $r('app.color.on_surface_secondary')]);
      }
      .margin({ right: 12 });

      Column({ space: 4 }) {
        Text(option.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'));
        Text(option.subtitle)
          .fontSize(12)
          .lineHeight(18)
          .fontColor($r('app.color.on_surface_secondary'));
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ right: 12 });

      if (this.themeMode === option.mode) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(20)
          .fontColor([this.getCurrentAccentColorHex()]);
      } else {
        SymbolGlyph($r('sys.symbol.circle'))
          .fontSize(20)
          .fontColor([$r('app.color.on_surface_tertiary')]);
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(this.themeMode === option.mode
      ? ThemeManager.hexWithAlpha(this.getCurrentAccentColorHex(), 0.08)
      : this.getCurrentAccentSurfaceColorHex())
    .borderRadius(16)
    .border({
      width: this.themeMode === option.mode ? 1.5 : 1,
      color: this.themeMode === option.mode ? this.getCurrentAccentColorHex() : $r('app.color.divider_light')
    })
    .onClick(() => {
      this.onThemeModeSelected(option.mode).catch(() => {});
    });
  }

  @Builder
  private AccentColorCard(option: AccentColorOption) {
    Column({ space: 6 }) {
      Column() {
        Stack({ alignContent: Alignment.Center }) {
          Row()
            .width('100%')
            .height(50)
            .backgroundColor(ThemeManager.getAccentColorHex(option.color));

          if (this.accentColor === option.color) {
            Circle()
              .width(30)
              .height(30)
              .fill('#66000000');
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(19)
              .fontColor([Color.White]);
          }
        }
        .width('100%')
        .height(50);

        Row({ space: 5 }) {
          Circle()
            .width(8)
            .height(8)
            .fill(ThemeManager.getAccentColorHex(option.color));
          Circle()
            .width(8)
            .height(8)
            .fill(ThemeManager.getAccentSecondaryColorHex(option.color));
          Circle()
            .width(8)
            .height(8)
            .fill(ThemeManager.getAccentTertiaryColorHex(option.color));
        }
        .width('100%')
        .height(22)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.getCurrentAccentSurfaceColorHex());
      }
      .width(ACCENT_SWATCH_SIZE)
      .height(ACCENT_SWATCH_SIZE)
      .borderRadius(16)
      .clip(true)
      .border({
        width: this.accentColor === option.color ? 2 : 1,
        color: this.accentColor === option.color
          ? ThemeManager.getAccentColorHex(option.color)
          : $r('app.color.divider_light')
      });

      Text(option.title)
        .fontSize(11)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontWeight(this.accentColor === option.color ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.accentColor === option.color ? this.getCurrentAccentColorHex() : $r('app.color.on_surface_secondary'));
    }
    .width(ACCENT_SWATCH_CARD_WIDTH)
    .alignItems(HorizontalAlign.Center)
    .margin({ right: 12, bottom: 14 })
    .onClick(() => {
      this.onAccentColorSelected(option.color).catch(() => {});
    });
  }

  @Builder
  private AccentColorSection() {
    Column() {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.getAccentColorOptions(), (option: AccentColorOption) => {
          this.AccentColorCard(option);
        }, (option: AccentColorOption) => option.color);
      }
      .width('100%');
    }
    .width('100%');
  }

  @Builder
  private PendingNoteCard() {
    Row() {
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(18)
        .fontColor([$r('app.color.on_surface_secondary')])
        .margin({ right: 10 });
      Text($r('app.string.appearance_settings_pending_note'))
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.on_surface_secondary'))
        .layoutWeight(1);
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.getCurrentAccentSurfaceVariantColorHex())
    .borderRadius(16)
    .margin({ top: 16 });
  }

  build() {
    HdsNavDestination() {
      Column() {
        List({ scroller: this.contentScroller }) {
          // 参考浏览历史 / 关注列表等 HDS 二级页：内容滚动容器自己从顶部排列，
          // 首项只负责给沉浸式标题栏预留“状态栏 + MINI 标题栏 + 蒙版”高度。
          // 避免 Scroll 在内容不足一屏时把整组内容纵向居中，造成标题与主题之间大空隙。
          ListItem() {
            Row()
              .width('100%')
              .height(ImmersiveHdsTitleBarHelper.getContentTopSpacerHeightVp());
          }

          ListItem() {
            this.SectionTitle(
              $r('app.string.appearance_settings_section_theme_title'),
              $r('app.string.appearance_settings_section_theme_subtitle')
            );
          }

          ListItem() {
            Column({ space: 10 }) {
              ForEach(this.getThemeModeOptions(), (option: ThemeModeOption) => {
                this.ThemeModeCard(option);
              }, (option: ThemeModeOption) => option.mode);
            }
            .width('100%');
          }

          ListItem() {
            this.SectionTitle(
              $r('app.string.appearance_settings_section_accent_title'),
              $r('app.string.appearance_settings_section_accent_subtitle')
            );
          }

          ListItem() {
            this.AccentColorSection();
          }

          ListItem() {
            this.PendingNoteCard();
          }

          ListItem() {
            Row()
              .width('100%')
              .height(24);
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: PAGE_HORIZONTAL_PADDING, right: PAGE_HORIZONTAL_PADDING, top: 16 })
        .backgroundColor(this.getCurrentAccentBackgroundColorHex())
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getCurrentAccentBackgroundColorHex());
    }
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .titleBar(ImmersiveHdsTitleBarHelper.buildImmersiveTitleBar($r('app.string.profile_appearance')))
    .hideTitleBar(false)
    .hideBackButton(false)
    .hideToolBar(true)
    .bindToScrollable([this.contentScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .systemBarStyle(
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() },
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() }
    )
    .backgroundColor(this.getCurrentAccentBackgroundColorHex());
  }
}
