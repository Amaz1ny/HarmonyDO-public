import { WindowManager } from '../../common/utils/WindowManager';

const TOPIC_LIST_SEARCH_BAR_HEIGHT_VP: number = 56;
const TOPIC_LIST_TAB_ROW_HEIGHT_VP: number = 36;
const TOPIC_LIST_SORT_BAR_HEIGHT_VP: number = 44;
const TOPIC_LIST_HEADER_DIVIDER_HEIGHT_VP: number = 1;
const TOPIC_LIST_HEADER_BLUR_RADIUS_VP: number = 52;
const TOPIC_LIST_CONTROL_BLUR_RADIUS_VP: number = 44;
const TOPIC_LIST_SEARCH_FIELD_HEIGHT_VP: number = 40;
const TOPIC_LIST_SEARCH_FIELD_RADIUS_VP: number = 20;
const TOPIC_LIST_ACTION_SIZE_VP: number = 40;
const TOPIC_LIST_ACTION_VISUAL_SIZE_VP: number = 34;
const TOPIC_LIST_ACTION_RADIUS_VP: number = 18;

export class TopicListChromeHelper {
  static getTopSafeHeightVp(): number {
    return WindowManager.getSystemAvoidAreaTopVp();
  }

  static getSearchBarHeightVp(): number {
    return TOPIC_LIST_SEARCH_BAR_HEIGHT_VP;
  }

  static getTabRowHeightVp(): number {
    return TOPIC_LIST_TAB_ROW_HEIGHT_VP;
  }

  static getSortBarHeightVp(): number {
    return TOPIC_LIST_SORT_BAR_HEIGHT_VP;
  }

  static getCollapsibleHeightVp(): number {
    return TOPIC_LIST_SEARCH_BAR_HEIGHT_VP + TOPIC_LIST_SORT_BAR_HEIGHT_VP;
  }

  static getHeaderExpandedHeightVp(): number {
    return TopicListChromeHelper.getTopSafeHeightVp()
      + TOPIC_LIST_SEARCH_BAR_HEIGHT_VP
      + TOPIC_LIST_TAB_ROW_HEIGHT_VP
      + TOPIC_LIST_HEADER_DIVIDER_HEIGHT_VP
      + TOPIC_LIST_SORT_BAR_HEIGHT_VP;
  }

  static getHeaderPinnedHeightVp(): number {
    return TopicListChromeHelper.getTopSafeHeightVp()
      + TOPIC_LIST_TAB_ROW_HEIGHT_VP
      + TOPIC_LIST_HEADER_DIVIDER_HEIGHT_VP;
  }

  static getHeaderVisibleHeightVp(headerOffset: number): number {
    const collapsed: number = Math.max(0, Math.min(headerOffset, TopicListChromeHelper.getCollapsibleHeightVp()));
    const searchVisible: number = Math.max(0, TOPIC_LIST_SEARCH_BAR_HEIGHT_VP - collapsed);
    const sortCollapsed: number = Math.max(0, collapsed - TOPIC_LIST_SEARCH_BAR_HEIGHT_VP);
    const sortVisible: number = Math.max(0, TOPIC_LIST_SORT_BAR_HEIGHT_VP - sortCollapsed);
    return TopicListChromeHelper.getTopSafeHeightVp()
      + searchVisible
      + TOPIC_LIST_TAB_ROW_HEIGHT_VP
      + TOPIC_LIST_HEADER_DIVIDER_HEIGHT_VP
      + sortVisible;
  }

  static getContentTopSpacerHeightVp(headerOffset: number): number {
    return TopicListChromeHelper.getHeaderVisibleHeightVp(headerOffset);
  }

  static getHeaderBlurRadiusVp(): number {
    return TOPIC_LIST_HEADER_BLUR_RADIUS_VP;
  }

  static getControlBlurRadiusVp(): number {
    return TOPIC_LIST_CONTROL_BLUR_RADIUS_VP;
  }

  static getSearchFieldHeightVp(): number {
    return TOPIC_LIST_SEARCH_FIELD_HEIGHT_VP;
  }

  static getSearchFieldRadiusVp(): number {
    return TOPIC_LIST_SEARCH_FIELD_RADIUS_VP;
  }

  static getActionSizeVp(): number {
    return TOPIC_LIST_ACTION_SIZE_VP;
  }

  static getActionVisualSizeVp(): number {
    return TOPIC_LIST_ACTION_VISUAL_SIZE_VP;
  }

  static getActionRadiusVp(): number {
    return TOPIC_LIST_ACTION_RADIUS_VP;
  }

  static getHeaderShadowColor(): string {
    return WindowManager.isDarkMode() ? '#00000000' : '#0E000000';
  }
}
