const FAB_BUTTON_SIZE_VP: number = 52;
const FAB_BUTTON_EDGE_MARGIN_VP: number = 16;
const FAB_HOME_RADIUS_VP: number = 26;
const FAB_REPLY_RADIUS_VP: number = 18;
const FAB_BLUR_RADIUS_VP: number = 56;
const FAB_SATURATION: number = 1.85;
const FAB_BRIGHTNESS: number = 1.04;
const FAB_SHADOW_RADIUS_VP: number = 14;
const FAB_SHADOW_OFFSET_Y_VP: number = 8;

const FAB_MENU_RADIUS_VP: number = 16;
const FAB_MENU_BLUR_RADIUS_VP: number = 48;
const FAB_MENU_SATURATION: number = 1.58;
const FAB_MENU_BRIGHTNESS: number = 1.03;
const FAB_MENU_SHADOW_RADIUS_VP: number = 14;
const FAB_MENU_SHADOW_OFFSET_Y_VP: number = 8;

export class FloatingActionChromeHelper {
  static getButtonSizeVp(): number {
    return FAB_BUTTON_SIZE_VP;
  }

  static getEdgeMarginVp(): number {
    return FAB_BUTTON_EDGE_MARGIN_VP;
  }

  static getHomeRadiusVp(): number {
    return FAB_HOME_RADIUS_VP;
  }

  static getReplyRadiusVp(): number {
    return FAB_REPLY_RADIUS_VP;
  }

  static getBlurRadiusVp(): number {
    return FAB_BLUR_RADIUS_VP;
  }

  static getSaturation(): number {
    return FAB_SATURATION;
  }

  static getBrightness(): number {
    return FAB_BRIGHTNESS;
  }

  static getShadowRadiusVp(): number {
    return FAB_SHADOW_RADIUS_VP;
  }

  static getShadowOffsetYVp(): number {
    return FAB_SHADOW_OFFSET_Y_VP;
  }

  static getRightTranslateXVp(): number {
    return -(FAB_BUTTON_SIZE_VP + FAB_BUTTON_EDGE_MARGIN_VP);
  }

  static getBottomTranslateYVp(reservedBottomVp: number): number {
    return -(FAB_BUTTON_SIZE_VP + FAB_BUTTON_EDGE_MARGIN_VP + reservedBottomVp);
  }

  static getMenuRadiusVp(): number {
    return FAB_MENU_RADIUS_VP;
  }

  static getMenuBlurRadiusVp(): number {
    return FAB_MENU_BLUR_RADIUS_VP;
  }

  static getMenuSaturation(): number {
    return FAB_MENU_SATURATION;
  }

  static getMenuBrightness(): number {
    return FAB_MENU_BRIGHTNESS;
  }

  static getMenuShadowRadiusVp(): number {
    return FAB_MENU_SHADOW_RADIUS_VP;
  }

  static getMenuShadowOffsetYVp(): number {
    return FAB_MENU_SHADOW_OFFSET_Y_VP;
  }
}
