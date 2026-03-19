import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CfClearanceRefreshService } from '../../services/network/CfClearanceRefreshService';

const TAG: string = 'CfRefreshHost';
const INITIAL_SRC: string = 'about:blank';

/**
 * cf_clearance 自动续期宿主（隐藏 Web）
 *
 * 说明：
 * - WebviewController 必须与 Web 组件绑定后才能调用 runJavaScript / registerJavaScriptProxy 等 API
 * - 因此通过一个 1x1vp、opacity=0 的 Web 组件常驻在根页面，供 CfClearanceRefreshService 驱动
 */
@ComponentV2
export struct CfRefreshHost {
  private controller: webview.WebviewController = new webview.WebviewController('cf_refresh_host');

  aboutToAppear(): void {
    hilog.info(0x0000, TAG, 'Bind controller, initial src=%{public}s', INITIAL_SRC);
    CfClearanceRefreshService.getInstance().bindController(this.controller);
  }

  aboutToDisappear(): void {
    CfClearanceRefreshService.getInstance().unbindController();
  }

  build() {
    Web({ src: INITIAL_SRC, controller: this.controller })
      .width(1)
      .height(1)
      .opacity(0.0)
  }
}

