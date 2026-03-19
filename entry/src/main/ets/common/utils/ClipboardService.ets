import pasteboard from '@ohos.pasteboard';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ToastService } from './ToastService';

const TAG: string = 'ClipboardService';

/**
 * 剪贴板工具（复制文本）
 */
export class ClipboardService {
  static async copyText(text: string, showToast: boolean = true): Promise<boolean> {
    const content: string = text !== undefined && text !== null ? text.trim() : '';
    if (content.length === 0) return false;

    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, content);
      await systemPasteboard.setData(data);
      if (showToast) {
        ToastService.show($r('app.string.copied_link'));
      }
      return true;
    } catch (err) {
      hilog.error(0x0000, TAG, 'copyText failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }
}
