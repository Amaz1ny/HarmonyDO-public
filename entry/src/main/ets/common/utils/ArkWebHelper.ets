import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../constants/AppConstants';

const TAG: string = 'ArkWebHelper';

export class ArkWebHelper {
  private static configuredUserAgentHosts: boolean = false;
  private static configuredCookiePolicy: boolean = false;

  static configureLinuxDoHostsUserAgent(): void {
    ArkWebHelper.configureLinuxDoCookiePolicy();
    if (ArkWebHelper.configuredUserAgentHosts) {
      return;
    }
    try {
      webview.WebviewController.setUserAgentForHosts(AppConstants.USER_AGENT, [
        'linux.do',
        'ping.linux.do',
        'connect.linux.do',
        'challenges.cloudflare.com'
      ]);
      ArkWebHelper.configuredUserAgentHosts = true;
    } catch (err) {
      hilog.warn(0x0000, TAG, 'setUserAgentForHosts failed: %{public}s', JSON.stringify(err));
    }
  }

  static configureLinuxDoCookiePolicy(): void {
    if (ArkWebHelper.configuredCookiePolicy) {
      return;
    }

    try {
      webview.WebCookieManager.putAcceptCookieEnabled(true);
    } catch (err) {
      hilog.warn(0x0000, TAG, 'putAcceptCookieEnabled failed: %{public}s', JSON.stringify(err));
    }

    try {
      // Cloudflare Turnstile 会在 challenges.cloudflare.com iframe 中完成验证。
      // API 23 目标版本下 ArkWeb 对第三方 Cookie 策略更严格，若不显式开启，
      // 验证页可能一直停在 linux.do 首页，最终读不到新的 cf_clearance。
      webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true);
    } catch (err) {
      hilog.warn(0x0000, TAG, 'putAcceptThirdPartyCookieEnabled failed: %{public}s', JSON.stringify(err));
    }

    try {
      const acceptCookie: boolean = webview.WebCookieManager.isCookieAllowed();
      const acceptThirdParty: boolean = webview.WebCookieManager.isThirdPartyCookieAllowed();
      hilog.info(
        0x0000,
        TAG,
        'ArkWeb cookie policy configured acceptCookie=%{public}s acceptThirdParty=%{public}s',
        acceptCookie ? 'Y' : 'N',
        acceptThirdParty ? 'Y' : 'N'
      );
    } catch (_) {
    }

    ArkWebHelper.configuredCookiePolicy = true;
  }
}
