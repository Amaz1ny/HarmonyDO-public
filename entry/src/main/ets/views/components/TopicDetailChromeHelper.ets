import { WindowManager } from '../../common/utils/WindowManager';

const TOPIC_DETAIL_TOP_BAR_HEIGHT_VP: number = 56;
const TOPIC_DETAIL_TOP_BAR_BLUR_RADIUS_VP: number = 22;
const TOPIC_DETAIL_TOP_BAR_MASK_EXTRA_HEIGHT_VP: number = 20;
const TOPIC_DETAIL_TOP_BAR_PADDING_H_VP: number = 8;
const TOPIC_DETAIL_SEARCH_FIELD_HEIGHT_VP: number = 40;
const TOPIC_DETAIL_LIGHT_STATUS_BAR_CONTENT_COLOR: string = '#000000';
const TOPIC_DETAIL_DARK_STATUS_BAR_CONTENT_COLOR: string = '#FFFFFF';

export class TopicDetailChromeHelper {
  static getTopSafeHeightVp(): number {
    return WindowManager.getSystemAvoidAreaTopVp();
  }

  static getTopBarBaseHeightVp(): number {
    return TOPIC_DETAIL_TOP_BAR_HEIGHT_VP;
  }

  static getTopBarTotalHeightVp(): number {
    return TopicDetailChromeHelper.getTopSafeHeightVp() + TOPIC_DETAIL_TOP_BAR_HEIGHT_VP;
  }

  static getTopBarMaskExtraHeightVp(): number {
    return TOPIC_DETAIL_TOP_BAR_MASK_EXTRA_HEIGHT_VP;
  }

  static getTopBarRenderHeightVp(): number {
    return TopicDetailChromeHelper.getTopBarTotalHeightVp() + TOPIC_DETAIL_TOP_BAR_MASK_EXTRA_HEIGHT_VP;
  }

  static getContentTopSpacerHeightVp(): number {
    return TopicDetailChromeHelper.getTopBarRenderHeightVp();
  }

  static getTopBarBlurRadiusVp(): number {
    return TOPIC_DETAIL_TOP_BAR_BLUR_RADIUS_VP;
  }

  static getTopBarHorizontalPaddingVp(): number {
    return TOPIC_DETAIL_TOP_BAR_PADDING_H_VP;
  }

  static getSearchFieldHeightVp(): number {
    return TOPIC_DETAIL_SEARCH_FIELD_HEIGHT_VP;
  }

  static getSearchFieldRadiusVp(): number {
    return TOPIC_DETAIL_SEARCH_FIELD_HEIGHT_VP / 2;
  }

  static getStatusBarContentColor(): string {
    return WindowManager.isDarkMode()
      ? TOPIC_DETAIL_DARK_STATUS_BAR_CONTENT_COLOR
      : TOPIC_DETAIL_LIGHT_STATUS_BAR_CONTENT_COLOR;
  }
}
