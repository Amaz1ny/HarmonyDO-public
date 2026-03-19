import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../constants/AppConstants';

const TAG: string = 'ArkWebHelper';

export class ArkWebHelper {
  private static configuredUserAgentHosts: boolean = false;

  static configureLinuxDoHostsUserAgent(): void {
    if (ArkWebHelper.configuredUserAgentHosts) {
      return;
    }
    try {
      webview.WebviewController.setUserAgentForHosts(AppConstants.USER_AGENT, [
        'linux.do',
        'ping.linux.do',
        'challenges.cloudflare.com'
      ]);
      ArkWebHelper.configuredUserAgentHosts = true;
    } catch (err) {
      hilog.warn(0x0000, TAG, 'setUserAgentForHosts failed: %{public}s', JSON.stringify(err));
    }
  }
}
