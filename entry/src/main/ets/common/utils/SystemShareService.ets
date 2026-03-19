import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { systemShare } from '@kit.ShareKit';
import { AppContext } from './AppContext';
import { ToastService } from './ToastService';

const TAG: string = 'SystemShareService';

/**
 * 系统分享（ShareKit）
 */
export class SystemShareService {
  static async shareText(text: string, title: string = '', showFailToast: boolean = true): Promise<boolean> {
    const content: string = text !== undefined && text !== null ? text.trim() : '';
    if (content.length === 0) return false;

    const ctx: common.UIAbilityContext | null = AppContext.getUIAbilityContext();
    if (ctx === null) {
      if (showFailToast) {
        ToastService.showShareFailed();
      }
      return false;
    }

    try {
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: content,
        title: title,
        description: title
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      await controller.show(ctx, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
      return true;
    } catch (err) {
      hilog.error(0x0000, TAG, 'shareText failed: %{public}s', JSON.stringify(err));
      if (showFailToast) {
        ToastService.showShareFailed();
      }
      return false;
    }
  }

  static async shareImage(uriOrPath: string, title: string = '', showFailToast: boolean = true): Promise<boolean> {
    const raw: string = uriOrPath !== undefined && uriOrPath !== null ? uriOrPath.trim() : '';
    if (raw.length === 0) return false;

    const ctx: common.UIAbilityContext | null = AppContext.getUIAbilityContext();
    if (ctx === null) {
      if (showFailToast) {
        ToastService.showShareFailed();
      }
      return false;
    }

    try {
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.IMAGE,
        content: raw,
        title: title,
        description: title
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      await controller.show(ctx, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
      return true;
    } catch (err) {
      hilog.error(0x0000, TAG, 'shareImage failed: %{public}s', JSON.stringify(err));
      if (showFailToast) {
        ToastService.showShareFailed();
      }
      return false;
    }
  }

  static async shareFile(uriOrPath: string, title: string = '', showFailToast: boolean = true): Promise<boolean> {
    const raw: string = uriOrPath !== undefined && uriOrPath !== null ? uriOrPath.trim() : '';
    if (raw.length === 0) return false;

    const ctx: common.UIAbilityContext | null = AppContext.getUIAbilityContext();
    if (ctx === null) {
      if (showFailToast) {
        ToastService.showShareFailed();
      }
      return false;
    }

    try {
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.FILE,
        content: raw,
        title: title,
        description: title
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      await controller.show(ctx, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
      return true;
    } catch (err) {
      hilog.error(0x0000, TAG, 'shareFile failed: %{public}s', JSON.stringify(err));
      if (showFailToast) {
        ToastService.showShareFailed();
      }
      return false;
    }
  }
}
