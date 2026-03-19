import { common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from './AppContext';
import { ToastService } from './ToastService';

const TAG: string = 'ExternalLinkService';

/**
 * 外部链接能力（打开系统浏览器）
 */
export class ExternalLinkService {
  static async openInBrowser(url: string): Promise<boolean> {
    const raw: string = url !== undefined && url !== null ? url.trim() : '';
    if (raw.length === 0) return false;

    const ctx: common.UIAbilityContext | null = AppContext.getUIAbilityContext();
    if (ctx === null) {
      ToastService.showOpenBrowserFailed();
      return false;
    }

    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: raw,
      parameters: {
        'ohos.ability.params.showDefaultPicker': true
      }
    };

    try {
      await ctx.startAbility(want);
      return true;
    } catch (err) {
      hilog.error(0x0000, TAG, 'openInBrowser failed: %{public}s', JSON.stringify(err));
      ToastService.showOpenBrowserFailed();
      return false;
    }
  }
}
