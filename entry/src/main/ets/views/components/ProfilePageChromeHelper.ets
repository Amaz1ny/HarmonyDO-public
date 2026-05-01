import { WindowManager } from '../../common/utils/WindowManager';

const PROFILE_PAGE_TOP_BAR_HEIGHT_VP: number = 56;
const PROFILE_PAGE_TOP_BAR_PADDING_H_VP: number = 12;
const PROFILE_PAGE_CONTENT_GAP_VP: number = 12;
const PROFILE_PAGE_TOP_BAR_BLUR_RADIUS_VP: number = 48;
const PROFILE_PAGE_ACTION_BLUR_RADIUS_VP: number = 40;
const PROFILE_PAGE_ACTION_HEIGHT_VP: number = 42;
const PROFILE_PAGE_ACTION_RADIUS_VP: number = 22;

export class ProfilePageChromeHelper {
  static getTopSafeHeightVp(): number {
    return WindowManager.getSystemAvoidAreaTopVp();
  }

  static getTopBarBaseHeightVp(): number {
    return PROFILE_PAGE_TOP_BAR_HEIGHT_VP;
  }

  static getTopBarTotalHeightVp(): number {
    return ProfilePageChromeHelper.getTopSafeHeightVp() + PROFILE_PAGE_TOP_BAR_HEIGHT_VP;
  }

  static getContentTopSpacerHeightVp(): number {
    return ProfilePageChromeHelper.getTopBarTotalHeightVp() + PROFILE_PAGE_CONTENT_GAP_VP;
  }

  static getTopBarHorizontalPaddingVp(): number {
    return PROFILE_PAGE_TOP_BAR_PADDING_H_VP;
  }

  static getTopBarBlurRadiusVp(): number {
    return PROFILE_PAGE_TOP_BAR_BLUR_RADIUS_VP;
  }

  static getActionBlurRadiusVp(): number {
    return PROFILE_PAGE_ACTION_BLUR_RADIUS_VP;
  }

  static getActionHeightVp(): number {
    return PROFILE_PAGE_ACTION_HEIGHT_VP;
  }

  static getActionRadiusVp(): number {
    return PROFILE_PAGE_ACTION_RADIUS_VP;
  }

  static getActionShadowColor(): string {
    return WindowManager.isDarkMode() ? '#00000000' : '#16000000';
  }
}
