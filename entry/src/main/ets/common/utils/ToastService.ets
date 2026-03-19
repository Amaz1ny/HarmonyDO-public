import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from './AppContext';

const TAG: string = 'ToastService';

interface ToastOptionsLike {
  message: string;
  duration?: number;
}

export class ToastService {
  private static resolveMessage(message: string | Resource): string {
    if (typeof message === 'string') {
      return message;
    }

    const ctx = AppContext.getUIAbilityContext();
    if (ctx === null) return '';

    try {
      return ctx.resourceManager.getStringSync(message);
    } catch (err) {
      hilog.error(0x0000, TAG, 'resolveMessage failed: %{public}s', JSON.stringify(err));
      return '';
    }
  }

  static show(message: string | Resource, duration: number = 2000): void {
    const msg: string = ToastService.resolveMessage(message).trim();
    if (msg.length === 0) return;

    try {
      const options: ToastOptionsLike = { message: msg, duration: duration };
      promptAction.showToast(options);
    } catch (err) {
      hilog.error(0x0000, TAG, 'showToast failed: %{public}s', JSON.stringify(err));
    }
  }

  static showLoginRequired(): void {
    ToastService.show($r('app.string.login_required'));
  }

  static showShareFailed(): void {
    ToastService.show($r('app.string.share_failed'));
  }

  static showOpenBrowserFailed(): void {
    ToastService.show($r('app.string.open_browser_failed'));
  }
}
