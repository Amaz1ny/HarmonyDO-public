import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { ArkWebHelper } from '../../common/utils/ArkWebHelper';
import { ExternalLinkService } from '../../common/utils/ExternalLinkService';
import { UrlUtils } from '../../common/utils/UrlUtils';
import { CookieStore } from '../../services/network/CookieStore';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ImmersiveHdsTitleBarHelper } from '../components/ImmersiveHdsTitleBarHelper';

const DEFAULT_TITLE: string = '网页';
const BLANK_URL: string = 'about:blank';
const TAG: string = 'WebViewPage';

@ComponentV2
export struct WebViewPage {
  @Param url: string = '';
  @Param title: string = '';

  @Local currentTitle: string = DEFAULT_TITLE;
  @Local currentUrl: string = '';
  @Local isLoading: boolean = true;
  @Local progress: number = 0;
  @Local errorMessage: string = '';

  private controller: webview.WebviewController = new webview.WebviewController('app_web_view');

  aboutToAppear(): void {
    ArkWebHelper.configureLinuxDoHostsUserAgent();
    this.currentTitle = this.getInitialTitle();
    this.currentUrl = this.normalizeUrl(this.url);
    if (this.currentUrl.length === 0) {
      this.errorMessage = '链接无效';
      this.isLoading = false;
      return;
    }

    CookieStore.getInstance().init()
      .then(() => {
        CookieStore.getInstance().syncToWebView();
      })
      .catch((_err: Object) => {
        CookieStore.getInstance().syncToWebView();
      });
  }

  private getInitialTitle(): string {
    const trimmed: string = this.title.trim();
    return trimmed.length > 0 ? trimmed : DEFAULT_TITLE;
  }

  private getDisplayTitle(): string {
    const trimmed: string = this.currentTitle.trim();
    return trimmed.length > 0 ? trimmed : DEFAULT_TITLE;
  }

  private normalizeUrl(rawUrl: string): string {
    const trimmed: string = rawUrl.trim();
    if (trimmed.length === 0) {
      return '';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('//')) {
      return `https:${trimmed}`;
    }
    if (trimmed.startsWith('/')) {
      return UrlUtils.resolveUrl(trimmed);
    }
    if (trimmed.indexOf('://') > 0) {
      return trimmed;
    }
    return `https://${trimmed}`;
  }

  private openInBrowser(): void {
    const targetUrl: string = this.currentUrl.length > 0 ? this.currentUrl : this.normalizeUrl(this.url);
    if (targetUrl.length === 0) {
      return;
    }
    ExternalLinkService.openInBrowser(targetUrl);
  }

  private reloadPage(): void {
    if (this.currentUrl.length === 0) {
      return;
    }
    this.errorMessage = '';
    this.isLoading = true;
    this.progress = 0;
    try {
      this.controller.refresh();
    } catch (_) {
      this.isLoading = false;
      this.errorMessage = '刷新失败';
    }
  }

  private getRequestUrl(request: WebResourceRequest): string {
    try {
      return request.getRequestUrl().trim();
    } catch (_) {
      return '';
    }
  }

  private isMainFrameRequest(request: WebResourceRequest): boolean {
    try {
      return request.isMainFrame();
    } catch (_) {
      return false;
    }
  }

  private handlePageLoadFailure(request: WebResourceRequest, message: string, code: number = 0): void {
    const requestUrl: string = this.getRequestUrl(request);
    const isMainFrame: boolean = this.isMainFrameRequest(request);
    hilog.warn(
      0x0000,
      TAG,
      'WebView load failure: mainFrame=%{public}s code=%{public}d url=%{public}s message=%{public}s',
      isMainFrame ? 'Y' : 'N',
      code,
      requestUrl,
      message
    );
    if (!isMainFrame) {
      return;
    }
    this.isLoading = false;
    this.errorMessage = message.length > 0 ? message : '页面加载失败';
  }

  build() {
    HdsNavDestination() {
      Column() {
        Blank()
          .height(ImmersiveHdsTitleBarHelper.getContentTopSpacerHeightVp())
          .width('100%')

        if (this.progress > 0 && this.progress < 100 && this.errorMessage.length === 0) {
          Progress({ value: this.progress, total: 100 })
            .height(2)
            .color($r('app.color.primary'))
        }

        Stack() {
          if (this.currentUrl.length > 0) {
            Web({ src: this.currentUrl, controller: this.controller })
              .width('100%')
              .height('100%')
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .databaseAccess(true)
              .onlineImageAccess(true)
              .imageAccess(true)
              .onPageBegin(() => {
                this.isLoading = true;
                this.errorMessage = '';
                this.progress = 0;
              })
              .onProgressChange((event: OnProgressChangeEvent) => {
                this.progress = event.newProgress;
              })
              .onTitleReceive((event: OnTitleReceiveEvent) => {
                const pageTitle: string = event.title.trim();
                if (pageTitle.length > 0) {
                  this.currentTitle = pageTitle;
                }
              })
              .onPageEnd(() => {
                this.isLoading = false;
                this.progress = 100;
              })
              .onErrorReceive((event: OnErrorReceiveEvent) => {
                let errorInfo: string = '';
                let errorCode: number = 0;
                try {
                  errorInfo = event.error.getErrorInfo();
                } catch (_) {
                }
                try {
                  errorCode = event.error.getErrorCode();
                } catch (_) {
                }
                this.handlePageLoadFailure(event.request, errorInfo.length > 0 ? errorInfo : '页面加载失败', errorCode);
              })
              .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
                let responseCode: number = 0;
                let reasonMessage: string = '';
                try {
                  responseCode = event.response.getResponseCode();
                } catch (_) {
                }
                try {
                  reasonMessage = event.response.getReasonMessage();
                } catch (_) {
                }
                const httpMessage: string = responseCode > 0
                  ? `HTTP ${responseCode}${reasonMessage.length > 0 ? ` ${reasonMessage}` : ''}`
                  : '页面加载失败';
                this.handlePageLoadFailure(event.request, httpMessage, responseCode);
              })
          } else {
            Web({ src: BLANK_URL, controller: this.controller })
              .width('100%')
              .height('100%')
          }

          if (this.isLoading && this.errorMessage.length === 0 && this.currentUrl.length > 0) {
            Column() {
              LoadingSpinner({ message: '' })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor('#00FFFFFF')
          }

          if (this.errorMessage.length > 0) {
            Column() {
              SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
                .fontSize(28)
                .fontColor([$r('app.color.on_surface_tertiary')])
                .margin({ bottom: 10 })
              Text('页面加载失败')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.on_surface'))
                .margin({ bottom: 6 })
              Text(this.errorMessage)
                .fontSize(12)
                .fontColor($r('app.color.on_surface_secondary'))
                .textAlign(TextAlign.Center)
                .margin({ left: 24, right: 24, bottom: 14 })
              Button('重试')
                .type(ButtonType.Capsule)
                .backgroundColor($r('app.color.primary'))
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.reloadPage();
                })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor($r('app.color.background'))
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
    }
    .backgroundColor($r('app.color.background'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .titleBar(ImmersiveHdsTitleBarHelper.buildImmersiveTitleBarWithTwoMenus(
      this.getDisplayTitle(),
      $r('sys.symbol.arrow_clockwise'),
      '刷新',
      () => {
        this.reloadPage();
      },
      $r('sys.symbol.link'),
      '在浏览器打开',
      () => {
        this.openInBrowser();
      }
    ))
    .hideTitleBar(false)
    .hideBackButton(false)
    .hideToolBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .systemBarStyle(
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() },
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() }
    )
  }
}
