import { WindowManager } from '../../common/utils/WindowManager';

const IMAGE_PREVIEW_CONTROL_SIZE_VP: number = 40;
const IMAGE_PREVIEW_CONTROL_ICON_SIZE_VP: number = 20;
const IMAGE_PREVIEW_CONTROL_RADIUS_VP: number = 20;
const IMAGE_PREVIEW_CONTROL_BLUR_RADIUS_VP: number = 48;
const IMAGE_PREVIEW_CONTROL_MARGIN_TOP_VP: number = 10;
const IMAGE_PREVIEW_CONTROL_PADDING_H_VP: number = 20;
const IMAGE_PREVIEW_INDICATOR_HEIGHT_VP: number = 32;
const IMAGE_PREVIEW_LIGHT_STATUS_BAR_CONTENT_COLOR: string = '#FFFFFF';
const IMAGE_PREVIEW_DARK_STATUS_BAR_CONTENT_COLOR: string = '#FFFFFF';

export class ImagePreviewChromeHelper {
  static getTopSafeHeightVp(): number {
    return WindowManager.getSystemAvoidAreaTopVp();
  }

  static getTopControlsOffsetVp(): number {
    return ImagePreviewChromeHelper.getTopSafeHeightVp() + IMAGE_PREVIEW_CONTROL_MARGIN_TOP_VP;
  }

  static getControlHorizontalPaddingVp(): number {
    return IMAGE_PREVIEW_CONTROL_PADDING_H_VP;
  }

  static getControlSizeVp(): number {
    return IMAGE_PREVIEW_CONTROL_SIZE_VP;
  }

  static getControlIconSizeVp(): number {
    return IMAGE_PREVIEW_CONTROL_ICON_SIZE_VP;
  }

  static getControlRadiusVp(): number {
    return IMAGE_PREVIEW_CONTROL_RADIUS_VP;
  }

  static getControlBlurRadiusVp(): number {
    return IMAGE_PREVIEW_CONTROL_BLUR_RADIUS_VP;
  }

  static getIndicatorHeightVp(): number {
    return IMAGE_PREVIEW_INDICATOR_HEIGHT_VP;
  }

  static getStatusBarContentColor(): string {
    return WindowManager.isDarkMode()
      ? IMAGE_PREVIEW_DARK_STATUS_BAR_CONTENT_COLOR
      : IMAGE_PREVIEW_LIGHT_STATUS_BAR_CONTENT_COLOR;
  }
}
