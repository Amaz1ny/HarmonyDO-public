import { webview } from '@kit.ArkWeb';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { ArkWebHelper } from '../../common/utils/ArkWebHelper';
import { WindowManager } from '../../common/utils/WindowManager';
import { RouterManager } from '../../common/utils/RouterManager';
import { ToastService } from '../../common/utils/ToastService';
import { AuthService } from '../../services/auth/AuthService';
import { AuthSessionService } from '../../services/auth/AuthSessionService';
import { UserSummarySnapshotService } from '../../services/storage/UserSummarySnapshotService';
import { CookieStore } from '../../services/network/CookieStore';
import { ApiClient } from '../../services/network/ApiClient';
import { User, UserSummary } from '../../models/User';

const TAG: string = 'LoginPage';
const LOGIN_URL: string = `${AppConstants.BASE_URL}/login`;
const TOP_BAR_HEIGHT: number = 56;
const LOGIN_STATE_POLL_MS: number = 900;
const NATIVE_USER_RETRY_COUNT: number = 3;
const NATIVE_USER_RETRY_INTERVAL_MS: number = 400;
const LOGIN_PASSKEY_BLOCK_SCRIPT: string = `(function() {
  try {
    if (!location || location.origin !== '${AppConstants.BASE_URL}') {
      return;
    }
    if (!location.pathname || location.pathname.indexOf('/login') !== 0) {
      return;
    }
    if (window.__HarmonyDoPasskeyPatchInstalled === true) {
      return;
    }
    try {
      Object.defineProperty(window, '__HarmonyDoPasskeyPatchInstalled', {
        configurable: true,
        value: true
      });
    } catch (_) {
      window.__HarmonyDoPasskeyPatchInstalled = true;
    }

    function buildNotSupportedError() {
      try {
        return new DOMException('WebAuthn disabled on Harmony login WebView', 'NotSupportedError');
      } catch (_) {
        var fallback = new Error('WebAuthn disabled on Harmony login WebView');
        fallback.name = 'NotSupportedError';
        return fallback;
      }
    }

    function rejectNotSupported() {
      return Promise.reject(buildNotSupportedError());
    }

    function hasPublicKeyOptions(options) {
      return !!options && typeof options === 'object' && !!options.publicKey;
    }

    var creds = navigator && navigator.credentials ? navigator.credentials : null;
    if (creds) {
      var rawGet = typeof creds.get === 'function' ? creds.get.bind(creds) : null;
      var rawCreate = typeof creds.create === 'function' ? creds.create.bind(creds) : null;
      var wrappedGet = function(options) {
        if (hasPublicKeyOptions(options)) {
          return rejectNotSupported();
        }
        return rawGet ? rawGet(options) : rejectNotSupported();
      };
      var wrappedCreate = function(options) {
        if (hasPublicKeyOptions(options)) {
          return rejectNotSupported();
        }
        return rawCreate ? rawCreate(options) : rejectNotSupported();
      };
      try {
        Object.defineProperty(creds, 'get', {
          configurable: true,
          value: wrappedGet
        });
      } catch (_) {
        try {
          creds.get = wrappedGet;
        } catch (_) {
        }
      }
      try {
        Object.defineProperty(creds, 'create', {
          configurable: true,
          value: wrappedCreate
        });
      } catch (_) {
        try {
          creds.create = wrappedCreate;
        } catch (_) {
        }
      }
    }

    var falseAsync = function() {
      return Promise.resolve(false);
    };
    var publicKeyCtor = typeof window.PublicKeyCredential !== 'undefined' ? window.PublicKeyCredential : null;
    if (publicKeyCtor) {
      try {
        Object.defineProperty(publicKeyCtor, 'isUserVerifyingPlatformAuthenticatorAvailable', {
          configurable: true,
          value: falseAsync
        });
      } catch (_) {
        try {
          publicKeyCtor.isUserVerifyingPlatformAuthenticatorAvailable = falseAsync;
        } catch (_) {
        }
      }
      try {
        Object.defineProperty(publicKeyCtor, 'isConditionalMediationAvailable', {
          configurable: true,
          value: falseAsync
        });
      } catch (_) {
        try {
          publicKeyCtor.isConditionalMediationAvailable = falseAsync;
        } catch (_) {
        }
      }
    } else {
      var FakePublicKeyCredential = function() {
      };
      FakePublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable = falseAsync;
      FakePublicKeyCredential.isConditionalMediationAvailable = falseAsync;
      try {
        Object.defineProperty(window, 'PublicKeyCredential', {
          configurable: true,
          value: FakePublicKeyCredential
        });
      } catch (_) {
        window.PublicKeyCredential = FakePublicKeyCredential;
      }
    }
  } catch (_) {
  }
})();`;

interface PageLoginInfo {
  username: string;
  csrfToken: string;
  pageUrl: string;
}

@ComponentV2
export struct LoginPage {
  @Local isPageLoading: boolean = true;
  @Local isCheckingLogin: boolean = false;
  @Local progress: number = 0;
  @Local errorMessage: string = '';
  @Local currentPageUrl: string = LOGIN_URL;

  private controller: webview.WebviewController = new webview.WebviewController('login_web_view');
  private loginCompleted: boolean = false;
  private loginStatePollTimerId: number = -1;
  private finalizingLogin: boolean = false;
  private passkeyBlockScripts: Array<ScriptItem> = [{
    script: LOGIN_PASSKEY_BLOCK_SCRIPT,
    scriptRules: [AppConstants.BASE_URL]
  }];

  aboutToAppear(): void {
    ArkWebHelper.configureLinuxDoHostsUserAgent();
    AuthSessionService.getInstance().advance('login_page_enter');
    ApiClient.getInstance().resetCurrentUserSessionState();
    hilog.info(0x0000, TAG, 'LoginPage passkey/WebAuthn block enabled for %{public}s/login', AppConstants.BASE_URL);
    this.startLoginStatePolling();
    CookieStore.getInstance().init()
      .then(() => {
        CookieStore.getInstance().syncToWebView();
      })
      .catch((_err: Object) => {
        CookieStore.getInstance().syncToWebView();
      });
  }

  aboutToDisappear(): void {
    this.stopLoginStatePolling();
  }

  private startLoginStatePolling(): void {
    if (this.loginStatePollTimerId >= 0) {
      return;
    }
    this.loginStatePollTimerId = setInterval(() => {
      this.inspectLoginState().catch((err: Object) => {
        hilog.error(0x0000, TAG, 'inspectLoginState polling failed: %{public}s', JSON.stringify(err));
      });
    }, LOGIN_STATE_POLL_MS);
  }

  private stopLoginStatePolling(): void {
    if (this.loginStatePollTimerId >= 0) {
      clearInterval(this.loginStatePollTimerId);
      this.loginStatePollTimerId = -1;
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  private normalizeJsStringResult(raw: string): string {
    const trimmed: string = typeof raw === 'string' ? raw.trim() : '';
    if (trimmed.length < 2) {
      return trimmed;
    }
    if (!(trimmed.startsWith('"') && trimmed.endsWith('"'))) {
      return trimmed;
    }
    try {
      const parsed: Object = JSON.parse(trimmed) as Object;
      return typeof parsed === 'string' ? (parsed as string) : trimmed;
    } catch (_) {
      return trimmed;
    }
  }

  private async fetchPageLoginInfo(): Promise<PageLoginInfo> {
    const empty: PageLoginInfo = {
      username: '',
      csrfToken: '',
      pageUrl: this.currentPageUrl
    };
    const script: string = `(function() {
      try {
        var username = '';
        var usernameMeta = document.querySelector('meta[name="current-username"]');
        if (usernameMeta && usernameMeta.content) {
          username = usernameMeta.content;
        } else if (typeof Discourse !== 'undefined' &&
          Discourse.User &&
          typeof Discourse.User.current === 'function' &&
          Discourse.User.current()) {
          username = Discourse.User.current().username || '';
        }
        var csrfToken = '';
        var csrfMeta = document.querySelector('meta[name="csrf-token"]');
        if (csrfMeta && csrfMeta.content) {
          csrfToken = csrfMeta.content;
        }
        return JSON.stringify({
          username: username || '',
          csrfToken: csrfToken || '',
          pageUrl: location && location.href ? location.href : ''
        });
      } catch (e) {
        return JSON.stringify({ username: '', csrfToken: '', pageUrl: '' });
      }
    })();`;
    try {
      const raw: string = await this.controller.runJavaScript(script);
      const text: string = this.normalizeJsStringResult(raw);
      if (text.length === 0) {
        return empty;
      }
      const json: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      const usernameVal: Object = json['username'];
      const csrfVal: Object = json['csrfToken'];
      const urlVal: Object = json['pageUrl'];
      return {
        username: usernameVal !== undefined && usernameVal !== null ? usernameVal.toString().trim() : '',
        csrfToken: csrfVal !== undefined && csrfVal !== null ? csrfVal.toString().trim() : '',
        pageUrl: urlVal !== undefined && urlVal !== null ? urlVal.toString().trim() : this.currentPageUrl
      };
    } catch (err) {
      hilog.error(0x0000, TAG, 'Fetch page login info failed: %{public}s', JSON.stringify(err));
      return empty;
    }
  }

  private buildFallbackUser(username: string): User {
    const user: User = new User();
    user.username = username;
    user.name = username;
    return user;
  }

  private async buildHydratedFallbackUser(username: string): Promise<User> {
    const normalizedUsername: string = username.trim();
    if (normalizedUsername.length === 0) {
      return this.buildFallbackUser(username);
    }
    try {
      const profileUser: User = await ApiClient.getInstance().getUserProfile(normalizedUsername);
      if (profileUser.username.trim().length > 0) {
        return profileUser;
      }
    } catch (err) {
      hilog.warn(
        0x0000,
        TAG,
        'Hydrate fallback user failed username=%{public}s err=%{public}s',
        normalizedUsername,
        ApiClient.formatError(err)
      );
    }
    return this.buildFallbackUser(username);
  }

  private isRateLimitError(err: Object): boolean {
    if (err === undefined || err === null) {
      return false;
    }
    return err.toString().indexOf('HTTP 429') >= 0;
  }

  private async fetchCurrentUserWithRetry(fallbackUsername: string): Promise<User | null> {
    const normalizedFallbackUsername: string = fallbackUsername.trim();
    const maxAttempts: number = normalizedFallbackUsername.length > 0 ? 1 : NATIVE_USER_RETRY_COUNT;
    for (let i = 0; i < maxAttempts; i++) {
      try {
        const currentUser: User | null = await ApiClient.getInstance().getCurrentUser();
        if (currentUser !== null) {
          return currentUser;
        }
      } catch (err) {
        hilog.warn(
          0x0000,
          TAG,
          'Fetch current user after token failed attempt=%{public}d/%{public}d: %{public}s',
          i + 1,
          maxAttempts,
          ApiClient.formatError(err)
        );
        if (normalizedFallbackUsername.length > 0 && this.isRateLimitError(err)) {
          hilog.warn(
            0x0000,
            TAG,
            'Current user still rate limited after token, fallback to username hydration username=%{public}s',
            normalizedFallbackUsername
          );
          break;
        }
      }
      if (i < maxAttempts - 1) {
        await this.sleep(NATIVE_USER_RETRY_INTERVAL_MS);
      }
    }
    if (normalizedFallbackUsername.length > 0) {
      return await this.buildHydratedFallbackUser(normalizedFallbackUsername);
    }
    return null;
  }

  private async prefetchSummarySnapshot(username: string): Promise<void> {
    const normalizedUsername: string = username.trim();
    if (normalizedUsername.length === 0) {
      return;
    }
    try {
      const summary: UserSummary = await ApiClient.getInstance().getUserSummary(normalizedUsername);
      await UserSummarySnapshotService.save(normalizedUsername, summary);
      hilog.info(
        0x0000,
        TAG,
        'Prefetched login summary snapshot username=%{public}s days=%{public}d postsRead=%{public}d likes=%{public}d replies=%{public}d',
        normalizedUsername,
        summary.daysVisited,
        summary.postsReadCount,
        summary.likesReceived,
        summary.postCount
      );
    } catch (err) {
      hilog.warn(
        0x0000,
        TAG,
        'Prefetch login summary snapshot failed username=%{public}s err=%{public}s',
        normalizedUsername,
        ApiClient.formatError(err)
      );
    }
  }

  private async applyLoginSuccess(user: User, cookieHeader: string, csrfToken: string): Promise<void> {
    const auth: AuthService = AuthService.getInstance();
    const previousUsername: string = auth.getCurrentUsername().trim().toLowerCase();
    const nextUsername: string = user.username.trim().toLowerCase();
    if (previousUsername.length > 0 && nextUsername.length > 0 && previousUsername !== nextUsername) {
      ApiClient.getInstance().resetCurrentUserSessionState();
    }
    await this.prefetchSummarySnapshot(user.username);
    auth.setCurrentUser(user);
    ApiClient.getInstance().setCachedCurrentUser(user);
    await auth.saveLoginInfo(cookieHeader, csrfToken, user.username);
    this.loginCompleted = true;
    this.finalizingLogin = false;
    this.stopLoginStatePolling();
    ToastService.show('登录成功');
    RouterManager.pop();
  }

  private async inspectLoginState(): Promise<void> {
    if (this.loginCompleted || this.isCheckingLogin || this.finalizingLogin) {
      return;
    }
    if (this.errorMessage.length > 0) {
      return;
    }

    this.isCheckingLogin = true;
    try {
      const store: CookieStore = CookieStore.getInstance();
      await store.init();
      const cookieHeader: string = store.syncFromWebView();
      const tToken: string | null = store.getCookieValue('_t');
      const forumSession: string | null = store.getCookieValue('_forum_session');
      const cfClearance: string | null = store.getCookieValue('cf_clearance');
      hilog.info(
        0x0000,
        TAG,
        'Inspect login state url=%{public}s cookieLen=%{public}d has_t=%{public}s has_forum_session=%{public}s has_cf=%{public}s',
        this.currentPageUrl,
        cookieHeader.length,
        tToken !== null && tToken.length > 0 ? 'Y' : 'N',
        forumSession !== null && forumSession.length > 0 ? 'Y' : 'N',
        cfClearance !== null && cfClearance.length > 0 ? 'Y' : 'N'
      );

      if (tToken === null || tToken.length === 0) {
        return;
      }

      this.finalizingLogin = true;

      const pageInfo: PageLoginInfo = await this.fetchPageLoginInfo();
      if (pageInfo.pageUrl.length > 0) {
        this.currentPageUrl = pageInfo.pageUrl;
      }
      hilog.info(
        0x0000,
        TAG,
        'Token detected in WebView, username=%{public}s csrfLen=%{public}d pageUrl=%{public}s',
        pageInfo.username.length > 0 ? pageInfo.username : '-',
        pageInfo.csrfToken.length,
        this.currentPageUrl
      );

      const refreshedCookieHeader: string = store.syncFromWebView();
      const effectiveCookieHeader: string = refreshedCookieHeader.length > 0 ? refreshedCookieHeader : cookieHeader;
      const currentUser: User | null = await this.fetchCurrentUserWithRetry(pageInfo.username);
      if (currentUser === null) {
        hilog.warn(0x0000, TAG, 'Token exists but native current user is still unavailable, wait next poll');
        return;
      }

      const effectiveCsrfToken: string = pageInfo.csrfToken.length > 0
        ? pageInfo.csrfToken
        : AuthService.getInstance().getCsrfToken();
      await this.applyLoginSuccess(currentUser, effectiveCookieHeader, effectiveCsrfToken);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Inspect login state failed: %{public}s', ApiClient.formatError(err));
    } finally {
      this.isCheckingLogin = false;
      if (!this.loginCompleted) {
        this.finalizingLogin = false;
      }
    }
  }

  private reloadPage(): void {
    this.errorMessage = '';
    this.isPageLoading = true;
    this.progress = 0;
    try {
      this.controller.refresh();
    } catch (_) {
      this.isPageLoading = false;
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
      'LoginPage web load failure: mainFrame=%{public}s code=%{public}d url=%{public}s message=%{public}s',
      isMainFrame ? 'Y' : 'N',
      code,
      requestUrl,
      message
    );
    if (!isMainFrame) {
      return;
    }
    this.isPageLoading = false;
    this.errorMessage = message.length > 0 ? message : '页面加载失败';
  }

  @Builder
  private TopBar() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontColor([$r('app.color.on_surface')])
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        RouterManager.pop();
      })

      Text('登录 Linux.do')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row() {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(18)
          .fontColor([$r('app.color.on_surface')])
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.reloadPage();
      })
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .padding({ left: 8, right: 8 })
    .backgroundColor($r('app.color.background'))
    .alignItems(VerticalAlign.Center)
  }

  build() {
    HdsNavDestination() {
      Column() {
        this.TopBar()

        if (this.progress > 0 && this.progress < 100 && this.errorMessage.length === 0) {
          Progress({ value: this.progress, total: 100 })
            .height(2)
            .color($r('app.color.primary'))
        }

        Stack() {
          Web({ src: LOGIN_URL, controller: this.controller })
            .width('100%')
            .height('100%')
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .databaseAccess(true)
            .onlineImageAccess(true)
            .imageAccess(true)
            .runJavaScriptOnDocumentStart(this.passkeyBlockScripts)
            .onPageBegin((event: OnPageBeginEvent) => {
              this.isPageLoading = true;
              this.errorMessage = '';
              this.progress = 0;
              this.currentPageUrl = event.url;
              hilog.info(0x0000, TAG, 'LoginPage onPageBegin url=%{public}s', this.currentPageUrl);
            })
            .onProgressChange((event: OnProgressChangeEvent) => {
              this.progress = event.newProgress;
            })
            .onTitleReceive((event: OnTitleReceiveEvent) => {
              hilog.info(0x0000, TAG, 'LoginPage onTitleReceive title=%{public}s', event.title);
            })
            .onPageEnd((event: OnPageEndEvent) => {
              this.isPageLoading = false;
              this.progress = 100;
              this.currentPageUrl = event.url;
              hilog.info(0x0000, TAG, 'LoginPage onPageEnd url=%{public}s', this.currentPageUrl);
              this.inspectLoginState().catch((err: Object) => {
                hilog.error(0x0000, TAG, 'inspectLoginState onPageEnd failed: %{public}s', JSON.stringify(err));
              });
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

          if (this.errorMessage.length > 0) {
            Column() {
              SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
                .fontSize(28)
                .fontColor([$r('app.color.on_surface_tertiary')])
                .margin({ bottom: 10 })
              Text('登录页加载失败')
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
      .padding({ top: WindowManager.getSystemAvoidAreaTopVp() })
      .backgroundColor($r('app.color.background'))
    }
    .hideTitleBar(true)
    .hideToolBar(true)
    .backgroundColor($r('app.color.background'))
  }
}
