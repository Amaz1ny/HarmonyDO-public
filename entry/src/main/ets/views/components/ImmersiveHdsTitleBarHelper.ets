import { LengthMetrics } from '@kit.ArkUI';
import {
  HdsNavigationBackgroundStyle,
  HdsNavigationBadgeIconOptions,
  HdsNavigationIconItemStyle,
  HdsNavigationIconOptions,
  HdsNavigationMenuContentOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitle,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleBarStyle,
  HdsNavigationTitleStyle,
  HdsTitleBarContentStyle,
  ScrollEffectOptions,
  ScrollEffectType,
  SystemMaterialParams,
  TitleBarContentOptions,
  TitleBarStyleOptions,
  hdsMaterial
} from '@kit.UIDesignKit';
import { WindowManager } from '../../common/utils/WindowManager';

const TITLE_BAR_SCROLL_EFFECT_START_OFFSET_VP: number = 0;
const TITLE_BAR_SCROLL_EFFECT_END_OFFSET_VP: number = 56;
const TITLE_BAR_HEIGHT_MINI_VP: number = 56;
const TITLE_BAR_MASK_EXTRA_HEIGHT_VP: number = 20;
const TITLE_BAR_BLUR_RADIUS: number = 22;
const TITLE_BAR_TRANSLUCENT_LIGHT: string = '#CCFFFFFF';
const TITLE_BAR_TRANSLUCENT_DARK: string = '#B31B1D22';
const LIGHT_STATUS_BAR_CONTENT_COLOR: string = '#FF1A1A1A';
const DARK_STATUS_BAR_CONTENT_COLOR: string = '#FFE0E0E0';

export class ImmersiveHdsTitleBarHelper {
  private static buildNavigationTitle(title: string | Resource): HdsNavigationTitle {
    const navigationTitle: HdsNavigationTitle = {
      mainTitle: title
    };
    return navigationTitle;
  }

  private static buildTitleStyle(): HdsNavigationTitleStyle {
    const titleStyle: HdsNavigationTitleStyle = {
      mainTitleColor: $r('app.color.on_surface')
    };
    return titleStyle;
  }

  private static buildIconItemStyle(): HdsNavigationIconItemStyle {
    const iconItemStyle: HdsNavigationIconItemStyle = {
      backgroundColor: Color.Transparent,
      iconColor: $r('app.color.on_surface'),
      textColor: $r('app.color.on_surface')
    };
    return iconItemStyle;
  }

  private static getTitleBarBackgroundColor(): string {
    return WindowManager.isDarkMode() ? TITLE_BAR_TRANSLUCENT_DARK : TITLE_BAR_TRANSLUCENT_LIGHT;
  }

  private static buildContentStyle(includeMenuStyle: boolean): HdsTitleBarContentStyle {
    const titleStyle: HdsNavigationTitleStyle = ImmersiveHdsTitleBarHelper.buildTitleStyle();
    const backIconStyle: HdsNavigationIconItemStyle = ImmersiveHdsTitleBarHelper.buildIconItemStyle();

    if (includeMenuStyle) {
      const menuStyle: HdsNavigationIconItemStyle = ImmersiveHdsTitleBarHelper.buildIconItemStyle();
      const contentStyle: HdsTitleBarContentStyle = {
        titleStyle: titleStyle,
        backIconStyle: backIconStyle,
        menuStyle: menuStyle
      };
      return contentStyle;
    }

    const contentStyle: HdsTitleBarContentStyle = {
      titleStyle: titleStyle,
      backIconStyle: backIconStyle
    };
    return contentStyle;
  }

  private static buildTitleBarStyle(includeBackgroundStyle: boolean, includeMaskStyle: boolean,
    includeMenuStyle: boolean): HdsNavigationTitleBarStyle {
    const contentStyle: HdsTitleBarContentStyle =
      ImmersiveHdsTitleBarHelper.buildContentStyle(includeMenuStyle);

    if (includeBackgroundStyle) {
      let backgroundStyle: HdsNavigationBackgroundStyle;
      if (includeMaskStyle) {
        backgroundStyle = {
          backgroundColor: ImmersiveHdsTitleBarHelper.getTitleBarBackgroundColor(),
          maskExtraHeight: TITLE_BAR_MASK_EXTRA_HEIGHT_VP,
          blurRadius: TITLE_BAR_BLUR_RADIUS
        };
      } else {
        backgroundStyle = {
          backgroundColor: Color.Transparent
        };
      }

      const titleBarStyle: HdsNavigationTitleBarStyle = {
        backgroundStyle: backgroundStyle,
        contentStyle: contentStyle
      };
      return titleBarStyle;
    }

    const titleBarStyle: HdsNavigationTitleBarStyle = {
      contentStyle: contentStyle
    };
    return titleBarStyle;
  }

  private static buildScrollEffectOptions(): ScrollEffectOptions {
    const scrollEffectOptions: ScrollEffectOptions = {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
      enableRefreshOffsetChange: true,
      blurEffectiveStartOffset: LengthMetrics.vp(TITLE_BAR_SCROLL_EFFECT_START_OFFSET_VP),
      blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BAR_SCROLL_EFFECT_END_OFFSET_VP)
    };
    return scrollEffectOptions;
  }

  private static buildSystemMaterialParams(): SystemMaterialParams {
    const systemMaterialParams: SystemMaterialParams = {
      materialType: hdsMaterial.MaterialType.IMMERSIVE,
      materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
    };
    return systemMaterialParams;
  }

  static getMiniTitleBarHeightVp(): number {
    return TITLE_BAR_HEIGHT_MINI_VP;
  }

  static getMaskExtraHeightVp(): number {
    return TITLE_BAR_MASK_EXTRA_HEIGHT_VP;
  }

  static getStatusBarContentColor(): string {
    return WindowManager.isDarkMode() ? DARK_STATUS_BAR_CONTENT_COLOR : LIGHT_STATUS_BAR_CONTENT_COLOR;
  }

  static getContentTopSpacerHeightVp(): number {
    return WindowManager.getSystemAvoidAreaTopVp() + TITLE_BAR_HEIGHT_MINI_VP + TITLE_BAR_MASK_EXTRA_HEIGHT_VP;
  }

  static buildPlainTitleBar(title: string | Resource,
    enableComponentSafeArea: boolean = true): HdsNavigationTitleBarOptions {
    const content: TitleBarContentOptions = {
      title: ImmersiveHdsTitleBarHelper.buildNavigationTitle(title)
    };
    const style: TitleBarStyleOptions = {
      originalStyle: ImmersiveHdsTitleBarHelper.buildTitleBarStyle(false, false, false),
      scrollEffectStyle: ImmersiveHdsTitleBarHelper.buildTitleBarStyle(false, false, false),
      systemMaterialEffect: ImmersiveHdsTitleBarHelper.buildSystemMaterialParams(),
      thermoCtrl: true
    };
    const titleBarOptions: HdsNavigationTitleBarOptions = {
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: enableComponentSafeArea,
      content: content,
      style: style
    };
    return titleBarOptions;
  }

  static buildImmersiveTitleBar(title: string | Resource): HdsNavigationTitleBarOptions {
    const content: TitleBarContentOptions = {
      title: ImmersiveHdsTitleBarHelper.buildNavigationTitle(title)
    };
    const style: TitleBarStyleOptions = {
      scrollEffectOpts: ImmersiveHdsTitleBarHelper.buildScrollEffectOptions(),
      originalStyle: ImmersiveHdsTitleBarHelper.buildTitleBarStyle(true, false, false),
      scrollEffectStyle: ImmersiveHdsTitleBarHelper.buildTitleBarStyle(true, true, false),
      systemMaterialEffect: ImmersiveHdsTitleBarHelper.buildSystemMaterialParams(),
      thermoCtrl: true
    };
    const titleBarOptions: HdsNavigationTitleBarOptions = {
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false,
      content: content,
      style: style
    };
    return titleBarOptions;
  }

  static buildImmersiveTitleBarWithMenu(title: string | Resource, menuIcon: Resource, menuLabel: string | Resource,
    menuAction: () => void, menuEnabled: boolean = true): HdsNavigationTitleBarOptions {
    const iconOptions: HdsNavigationIconOptions = {
      icon: menuIcon,
      label: menuLabel,
      isEnabled: menuEnabled,
      action: menuAction
    };
    const menuItem: HdsNavigationBadgeIconOptions = {
      content: iconOptions
    };
    const menuItems: Array<HdsNavigationMenuItemOptions> = [
      menuItem
    ];
    const menu: HdsNavigationMenuContentOptions = {
      value: menuItems,
      maxCount: 1
    };
    const content: TitleBarContentOptions = {
      title: ImmersiveHdsTitleBarHelper.buildNavigationTitle(title),
      menu: menu
    };
    const style: TitleBarStyleOptions = {
      scrollEffectOpts: ImmersiveHdsTitleBarHelper.buildScrollEffectOptions(),
      originalStyle: ImmersiveHdsTitleBarHelper.buildTitleBarStyle(true, false, true),
      scrollEffectStyle: ImmersiveHdsTitleBarHelper.buildTitleBarStyle(true, true, true),
      systemMaterialEffect: ImmersiveHdsTitleBarHelper.buildSystemMaterialParams(),
      thermoCtrl: true
    };
    const titleBarOptions: HdsNavigationTitleBarOptions = {
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false,
      content: content,
      style: style
    };
    return titleBarOptions;
  }

  static buildImmersiveTitleBarWithTwoMenus(title: string | Resource,
    firstMenuIcon: Resource, firstMenuLabel: string | Resource, firstMenuAction: () => void,
    secondMenuIcon: Resource, secondMenuLabel: string | Resource, secondMenuAction: () => void,
    firstMenuEnabled: boolean = true, secondMenuEnabled: boolean = true): HdsNavigationTitleBarOptions {
    const firstIconOptions: HdsNavigationIconOptions = {
      icon: firstMenuIcon,
      label: firstMenuLabel,
      isEnabled: firstMenuEnabled,
      action: firstMenuAction
    };
    const firstMenuItem: HdsNavigationBadgeIconOptions = {
      content: firstIconOptions
    };
    const secondIconOptions: HdsNavigationIconOptions = {
      icon: secondMenuIcon,
      label: secondMenuLabel,
      isEnabled: secondMenuEnabled,
      action: secondMenuAction
    };
    const secondMenuItem: HdsNavigationBadgeIconOptions = {
      content: secondIconOptions
    };
    const menuItems: Array<HdsNavigationMenuItemOptions> = [
      firstMenuItem,
      secondMenuItem
    ];
    const menu: HdsNavigationMenuContentOptions = {
      value: menuItems,
      maxCount: 2
    };
    const content: TitleBarContentOptions = {
      title: ImmersiveHdsTitleBarHelper.buildNavigationTitle(title),
      menu: menu
    };
    const style: TitleBarStyleOptions = {
      scrollEffectOpts: ImmersiveHdsTitleBarHelper.buildScrollEffectOptions(),
      originalStyle: ImmersiveHdsTitleBarHelper.buildTitleBarStyle(true, false, true),
      scrollEffectStyle: ImmersiveHdsTitleBarHelper.buildTitleBarStyle(true, true, true),
      systemMaterialEffect: ImmersiveHdsTitleBarHelper.buildSystemMaterialParams(),
      thermoCtrl: true
    };
    const titleBarOptions: HdsNavigationTitleBarOptions = {
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false,
      content: content,
      style: style
    };
    return titleBarOptions;
  }
}
