import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileUri } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { systemShare } from '@kit.ShareKit';
import { AppContext } from './AppContext';
import { ToastService } from './ToastService';

const TAG: string = 'SystemShareService';

/**
 * 系统分享（ShareKit）
 */
export class SystemShareService {
  private static normalizeFileInput(uriOrPath: string): string {
    const raw: string = uriOrPath !== undefined && uriOrPath !== null ? uriOrPath.trim() : '';
    if (!raw.startsWith('file://')) {
      return raw;
    }

    const body: string = raw.substring('file://'.length);
    if (body.startsWith('/')) {
      return body;
    }
    return raw;
  }

  private static buildShareUri(uriOrPath: string): string {
    const normalized: string = SystemShareService.normalizeFileInput(uriOrPath);
    if (normalized.length === 0) {
      return '';
    }

    try {
      const target: fileUri.FileUri = new fileUri.FileUri(normalized);
      return target.toString();
    } catch (_) {
    }

    if (normalized.startsWith('file://')) {
      return normalized;
    }

    try {
      return fileUri.getUriFromPath(normalized);
    } catch (_) {
    }
    return normalized;
  }

  private static inferFileUtd(uriOrPath: string, fallbackUtd: string): string {
    const normalized: string = SystemShareService.normalizeFileInput(uriOrPath);
    if (normalized.length === 0) {
      return fallbackUtd;
    }

    let fileName: string = normalized;
    try {
      const target: fileUri.FileUri = new fileUri.FileUri(normalized);
      fileName = target.name;
    } catch (_) {
      const slashIndex: number = Math.max(normalized.lastIndexOf('/'), normalized.lastIndexOf('\\'));
      if (slashIndex >= 0 && slashIndex < normalized.length - 1) {
        fileName = normalized.substring(slashIndex + 1);
      }
    }

    const queryIndex: number = fileName.indexOf('?');
    if (queryIndex >= 0) {
      fileName = fileName.substring(0, queryIndex);
    }
    const hashIndex: number = fileName.indexOf('#');
    if (hashIndex >= 0) {
      fileName = fileName.substring(0, hashIndex);
    }

    const dotIndex: number = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex >= fileName.length - 1) {
      return fallbackUtd;
    }

    const ext: string = fileName.substring(dotIndex).toLowerCase();
    try {
      return utd.getUniformDataTypeByFilenameExtension(ext, fallbackUtd);
    } catch (_) {
      return fallbackUtd;
    }
  }

  private static async shareUriRecord(
    uriOrPath: string,
    fallbackUtd: string,
    title: string,
    showFailToast: boolean,
    logLabel: string
  ): Promise<boolean> {
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
      const shareUri: string = SystemShareService.buildShareUri(raw);
      const utdType: string = SystemShareService.inferFileUtd(raw, fallbackUtd);
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: utdType,
        uri: shareUri,
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
      hilog.error(0x0000, TAG, '%{public}s failed: %{public}s', logLabel, JSON.stringify(err));
      if (showFailToast) {
        ToastService.showShareFailed();
      }
      return false;
    }
  }

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
    return await SystemShareService.shareUriRecord(
      uriOrPath,
      utd.UniformDataType.IMAGE,
      title,
      showFailToast,
      'shareImage'
    );
  }

  static async shareFile(uriOrPath: string, title: string = '', showFailToast: boolean = true): Promise<boolean> {
    return await SystemShareService.shareUriRecord(
      uriOrPath,
      utd.UniformDataType.FILE,
      title,
      showFailToast,
      'shareFile'
    );
  }
}
