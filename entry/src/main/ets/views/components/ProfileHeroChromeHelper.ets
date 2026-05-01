import { ThemeManager } from '../../common/theme/ThemeManager';
import { WindowManager } from '../../common/utils/WindowManager';

const PROFILE_HERO_TOP_BAR_HEIGHT_VP: number = 56;
const PROFILE_HERO_TAB_HEIGHT_VP: number = 36;
const PROFILE_HERO_EXPANDED_HEIGHT_VP: number = 410;
const PROFILE_HERO_BUTTON_TOUCH_SIZE_VP: number = 44;
const PROFILE_HERO_BUTTON_VISUAL_SIZE_VP: number = 36;
const PROFILE_HERO_BUTTON_ICON_SIZE_VP: number = 16;
const PROFILE_HERO_BUTTON_BLUR_RADIUS_VP: number = 44;
const PROFILE_HERO_TOP_BAR_PADDING_H_VP: number = 10;
const PROFILE_HERO_STATUS_BAR_CONTENT_COLOR: string = '#FFFFFF';

export class ProfileHeroChromeHelper {
  static getTopBarBaseHeightVp(): number {
    return PROFILE_HERO_TOP_BAR_HEIGHT_VP;
  }

  static getTabHeightVp(): number {
    return PROFILE_HERO_TAB_HEIGHT_VP;
  }

  static getTopSafeHeightVp(): number {
    return WindowManager.getSystemAvoidAreaTopVp();
  }

  static getBottomSafeHeightVp(): number {
    return WindowManager.getSystemAvoidAreaBottomVp();
  }

  static getTopBarHeightVp(): number {
    return PROFILE_HERO_TOP_BAR_HEIGHT_VP + ProfileHeroChromeHelper.getTopSafeHeightVp();
  }

  static getPinnedHeaderHeightVp(): number {
    return ProfileHeroChromeHelper.getTopBarHeightVp() + PROFILE_HERO_TAB_HEIGHT_VP;
  }

  static getExpandedHeightVp(): number {
    return PROFILE_HERO_EXPANDED_HEIGHT_VP + ProfileHeroChromeHelper.getTopSafeHeightVp();
  }

  static getFlexibleHeightVp(headerHeightVp: number): number {
    return Math.max(ProfileHeroChromeHelper.getTopBarHeightVp(), headerHeightVp - PROFILE_HERO_TAB_HEIGHT_VP);
  }

  static getFlexibleMaxHeightVp(): number {
    return Math.max(
      ProfileHeroChromeHelper.getTopBarHeightVp(),
      ProfileHeroChromeHelper.getExpandedHeightVp() - PROFILE_HERO_TAB_HEIGHT_VP
    );
  }

  static getHeroMaskAlpha(collapseT: number): number {
    const x: number = ProfileHeroChromeHelper.clamp(1 - collapseT, 0, 1);
    const eased: number = 1 - (1 - x) * (1 - x);
    return 0.6 + (0.85 - 0.6) * eased;
  }

  static getHeaderGlassSurface(alphaDark: number, alphaLight: number): string {
    return ThemeManager.hexWithAlpha('#FFFFFF', WindowManager.isDarkMode() ? alphaDark : alphaLight);
  }

  static getTopBarButtonBlurRadiusVp(): number {
    return PROFILE_HERO_BUTTON_BLUR_RADIUS_VP;
  }

  static getTopBarButtonTouchSizeVp(): number {
    return PROFILE_HERO_BUTTON_TOUCH_SIZE_VP;
  }

  static getTopBarButtonVisualSizeVp(): number {
    return PROFILE_HERO_BUTTON_VISUAL_SIZE_VP;
  }

  static getTopBarButtonRadiusVp(): number {
    return PROFILE_HERO_BUTTON_VISUAL_SIZE_VP / 2;
  }

  static getTopBarButtonIconSizeVp(): number {
    return PROFILE_HERO_BUTTON_ICON_SIZE_VP;
  }

  static getTopBarTrailingGroupWidthVp(buttonCount: number): number {
    return PROFILE_HERO_BUTTON_TOUCH_SIZE_VP * buttonCount;
  }

  static getTopBarHorizontalPaddingVp(): number {
    return PROFILE_HERO_TOP_BAR_PADDING_H_VP;
  }

  static getTopBarButtonFallbackColor(): string {
    return ProfileHeroChromeHelper.getHeaderGlassSurface(0.10, 0.08);
  }

  static getTopBarButtonShadowColor(): string {
    return WindowManager.isDarkMode() ? '#00000000' : '#18000000';
  }

  static getStatusBarContentColor(): string {
    return PROFILE_HERO_STATUS_BAR_CONTENT_COLOR;
  }

  private static clamp(v: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, v));
  }
}
