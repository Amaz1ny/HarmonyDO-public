export class ModalChromeHelper {
  static getSheetBlurStyle(): BlurStyle {
    return BlurStyle.COMPONENT_REGULAR;
  }

  static getDialogBlurStyle(): BlurStyle {
    return BlurStyle.COMPONENT_THICK;
  }

  static getSheetBackgroundColor(): ResourceColor {
    return $r('app.color.modal_glass_surface');
  }

  static getDialogBackgroundColor(): ResourceColor {
    return $r('app.color.modal_glass_surface');
  }

  static getMaskColor(): ResourceColor {
    return $r('app.color.modal_glass_mask');
  }
}
