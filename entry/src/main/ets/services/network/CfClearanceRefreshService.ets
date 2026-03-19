import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { PreferencesUtil } from '../storage/PreferencesUtil';
import { CookieStore } from './CookieStore';

const TAG: string = 'CfClearanceRefresh';

/**
 * cf_clearance 自动续期服务
 *
 * 参考安卓/Flutter 方案：
 * - 维持一个隐藏 WebView，加载 Turnstile widget（refresh-expired=auto）
 * - 覆写 window.fetch，拦截 Turnstile 内部对 /rc/ 端点的调用
 * - ArkTS 使用 NetworkKit 发起真实 POST，再把响应回灌给 JS 的 pending Promise
 */
export class CfClearanceRefreshService {
  private static instance: CfClearanceRefreshService | null = null;
  private static readonly KEY_SITEKEY: string = 'cf_turnstile_sitekey';
  private static readonly MAX_CONSECUTIVE_FAILURES: number = 3;
  private static readonly INITIAL_TIMEOUT_MS: number = 30 * 1000;
  private static readonly START_RETRY_MAX: number = 5;

  private inited: boolean = false;
  private sitekey: string = '';
  private cookieStore: CookieStore = CookieStore.getInstance();

  private controller: webview.WebviewController | null = null;
  private bridge: CfRefreshBridge | null = null;
  private proxyRegistered: boolean = false;

  private paused: boolean = false;
  private running: boolean = false;
  private starting: boolean = false;
  private callingRc: boolean = false;

  private consecutiveFailures: number = 0;
  private initialTimerId: number = -1;
  private startRetryTimerId: number = -1;
  private startRetryCount: number = 0;

  private lastStartSkipReason: string = '';
  private lastStartSkipAt: number = 0;

  private constructor() {
  }

  static getInstance(): CfClearanceRefreshService {
    if (CfClearanceRefreshService.instance === null) {
      CfClearanceRefreshService.instance = new CfClearanceRefreshService();
    }
    return CfClearanceRefreshService.instance;
  }

  async init(): Promise<void> {
    if (this.inited) return;
    try {
      await PreferencesUtil.ensureInit();
      this.sitekey = await PreferencesUtil.getString(CfClearanceRefreshService.KEY_SITEKEY, '');
      this.inited = true;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Init failed: %{public}s', JSON.stringify(err));
    }
  }

  getSitekey(): string {
    return this.sitekey;
  }

  updateSitekey(sitekey: string): void {
    const next: string = sitekey.trim();
    if (next.length === 0) return;
    if (next === this.sitekey) return;
    this.sitekey = next;
    PreferencesUtil.putString(CfClearanceRefreshService.KEY_SITEKEY, next).catch((err: Object) => {
      hilog.error(0x0000, TAG, 'Persist sitekey failed: %{public}s', JSON.stringify(err));
    });
    hilog.info(0x0000, TAG, 'Sitekey updated, len=%{public}d', next.length);

    // 有可能之前因缺 sitekey 无法启动续期；此处尝试启动
    this.startIfPossible();
  }

  extractAndUpdateSitekey(html: string): void {
    try {
      const match = /data-sitekey="([0-9a-zA-Zx_-]+)"/.exec(html);
      if (match !== null && match.length >= 2) {
        this.updateSitekey(match[1]);
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Extract sitekey failed: %{public}s', JSON.stringify(err));
    }
  }

  bindController(controller: webview.WebviewController): void {
    this.controller = controller;
    this.proxyRegistered = false;
    if (this.bridge === null) {
      this.bridge = new CfRefreshBridge(this);
    }
    this.startIfPossible();
  }

  unbindController(): void {
    this.stop();
    this.controller = null;
    this.proxyRegistered = false;
  }

  // 生命周期
  stop(): void {
    this.clearInitialTimer();
    this.clearStartRetryTimer();
    this.running = false;
    this.starting = false;
    this.callingRc = false;
    this.consecutiveFailures = 0;

    if (this.controller !== null) {
      try {
        // 用空白页卸载 turnstile，减少后台网络与资源占用
        this.controller.loadData(
          '<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body></body></html>',
          'text/html',
          'UTF-8',
          AppConstants.BASE_URL,
          AppConstants.BASE_URL
        );
      } catch (_) {
      }
    }
  }

  pause(): void {
    if (this.paused) return;
    this.paused = true;
    this.stop();
  }

  resume(): void {
    if (!this.paused) return;
    this.paused = false;
    this.startIfPossible();
  }

  startIfPossible(): void {
    this.startIfPossibleInternal().catch((err: Object) => {
      hilog.error(0x0000, TAG, 'startIfPossible failed: %{public}s', JSON.stringify(err));
    });
  }

  private logStartSkip(reason: string): void {
    const now: number = Date.now();
    if (reason === this.lastStartSkipReason && (now - this.lastStartSkipAt) < 3000) return;
    this.lastStartSkipReason = reason;
    this.lastStartSkipAt = now;
    hilog.info(0x0000, TAG, 'startIfPossible skipped: %{public}s', reason);
  }

  private async startIfPossibleInternal(): Promise<void> {
    await this.init();
    if (this.paused) {
      this.logStartSkip('paused');
      return;
    }
    if (this.controller === null) {
      this.logStartSkip('no_controller');
      return;
    }
    if (this.running || this.starting) {
      this.logStartSkip(this.running ? 'already_running' : 'already_starting');
      return;
    }
    if (this.sitekey.length === 0) {
      this.logStartSkip('missing_sitekey');
      return;
    }

    await this.cookieStore.init();
    const clearance: string | null = this.cookieStore.getCookieValue('cf_clearance');
    if (clearance === null || clearance.length === 0) {
      // 未通过过 CF 验证时不启动续期
      this.logStartSkip('missing_clearance');
      return;
    }

    this.starting = true;
    try {
      this.syncCookiesToWebView();
      this.registerProxyIfNeeded();
      this.loadTurnstileHtml(this.sitekey);

      this.running = true;
      this.consecutiveFailures = 0;
      this.startRetryCount = 0;
      this.scheduleInitialTimeout();
      this.lastStartSkipReason = '';
      hilog.info(0x0000, TAG, 'Turnstile refresh started');
    } catch (err) {
      hilog.error(0x0000, TAG, 'Start failed: %{public}s', JSON.stringify(err));
      this.running = false;
      this.scheduleStartRetry();
    } finally {
      this.starting = false;
    }
  }

  private registerProxyIfNeeded(): void {
    if (this.controller === null) return;
    if (this.bridge === null) return;
    if (this.proxyRegistered) return;

    try {
      this.controller.registerJavaScriptProxy(
        this.bridge as Object,
        'CfRefresh',
        ['onRcIntercepted', 'onTurnstileError']
      );
      this.proxyRegistered = true;
    } catch (err) {
      // 某些机型/版本可能需要等待 Web 组件完全创建后才能注册，交给重试机制处理
      hilog.error(0x0000, TAG, 'registerJavaScriptProxy failed: %{public}s', JSON.stringify(err));
      throw new Error('registerJavaScriptProxy failed');
    }
  }

  private loadTurnstileHtml(sitekey: string): void {
    if (this.controller === null) return;
    try {
      this.controller.setCustomUserAgent(AppConstants.USER_AGENT);
    } catch (_) {
    }

    const html: string = this.buildTurnstileHtml(sitekey);
    try {
      this.controller.loadData(html, 'text/html', 'UTF-8', AppConstants.BASE_URL, AppConstants.BASE_URL);
    } catch (err) {
      hilog.error(0x0000, TAG, 'loadData failed: %{public}s', JSON.stringify(err));
      throw new Error('loadData failed');
    }
  }

  private scheduleStartRetry(): void {
    if (this.paused) return;
    if (this.controller === null) return;
    if (this.startRetryTimerId >= 0) return;

    if (this.startRetryCount >= CfClearanceRefreshService.START_RETRY_MAX) {
      hilog.error(0x0000, TAG, 'Start retry exceeded, stop service');
      this.stop();
      return;
    }

    this.startRetryCount++;
    this.startRetryTimerId = setTimeout(() => {
      this.startRetryTimerId = -1;
      this.startIfPossible();
    }, 900);
  }

  private clearStartRetryTimer(): void {
    if (this.startRetryTimerId >= 0) {
      clearTimeout(this.startRetryTimerId);
      this.startRetryTimerId = -1;
    }
  }

  private scheduleInitialTimeout(): void {
    this.clearInitialTimer();
    this.initialTimerId = setTimeout(() => {
      this.initialTimerId = -1;
      if (!this.running) return;
      this.consecutiveFailures++;
      hilog.error(0x0000, TAG, 'Initial solve timeout (failures=%{public}d)', this.consecutiveFailures);
      this.checkAndStopIfNeeded();
    }, CfClearanceRefreshService.INITIAL_TIMEOUT_MS);
  }

  private clearInitialTimer(): void {
    if (this.initialTimerId >= 0) {
      clearTimeout(this.initialTimerId);
      this.initialTimerId = -1;
    }
  }

  private syncCookiesToWebView(): void {
    try {
      this.cookieStore.syncToWebView();
    } catch (err) {
      hilog.error(0x0000, TAG, 'syncCookiesToWebView failed: %{public}s', JSON.stringify(err));
    }
  }

  // ---------------------------------------------------------------------------
  // JS Bridge 回调
  // ---------------------------------------------------------------------------

  onTurnstileError(message: string): void {
    this.clearInitialTimer();
    this.consecutiveFailures++;
    hilog.error(0x0000, TAG, 'Turnstile error: %{public}s', message);
    this.checkAndStopIfNeeded();
  }

  onRcIntercepted(payload: string): void {
    this.clearInitialTimer();
    if (!this.running) return;
    if (this.paused) return;
    if (this.controller === null) return;

    let data: RcInterceptPayload | null = null;
    try {
      const parsed: Object = JSON.parse(payload) as Object;
      data = parsed as RcInterceptPayload;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Parse rc payload failed: %{public}s', JSON.stringify(err));
      return;
    }
    if (data === null) return;

    const id: string = typeof data.id === 'string' ? data.id as string : '';
    const chlId: string = typeof data.chlId === 'string' ? data.chlId as string : '';
    const secondaryToken: string = typeof data.secondaryToken === 'string' ? data.secondaryToken as string : '';
    const sitekey: string = typeof data.sitekey === 'string' ? data.sitekey as string : '';
    const effectiveSitekey: string = sitekey.length > 0 ? sitekey : this.sitekey;

    if (id.length === 0) return;

    if (this.callingRc) {
      this.resolveRcPromise(id, 503, '{}');
      return;
    }
    if (chlId.length === 0) {
      this.resolveRcPromise(id, 400, '{}');
      return;
    }
    if (effectiveSitekey.length === 0) {
      this.resolveRcPromise(id, 400, '{}');
      return;
    }

    this.callRcEndpoint(id, chlId, secondaryToken, effectiveSitekey).catch((err: Object) => {
      hilog.error(0x0000, TAG, 'callRcEndpoint failed: %{public}s', JSON.stringify(err));
    });
  }

  // ---------------------------------------------------------------------------
  // rc 端点调用
  // ---------------------------------------------------------------------------

  private async callRcEndpoint(id: string, chlId: string, secondaryToken: string, sitekey: string): Promise<void> {
    this.callingRc = true;
    const httpRequest = http.createHttp();
    try {
      await this.cookieStore.init();
      const url: string = `${AppConstants.BASE_URL}/cdn-cgi/challenge-platform/h/g/rc/${chlId}`;
      const headers: Record<string, string> = {};
      headers['User-Agent'] = AppConstants.USER_AGENT;
      headers['Accept'] = '*/*';
      headers['Content-Type'] = 'application/json';
      headers['Origin'] = AppConstants.BASE_URL;
      headers['Referer'] = `${AppConstants.BASE_URL}/`;

      const cookieHeader: string = this.cookieStore.getCookieHeader();
      if (cookieHeader.length > 0) {
        headers['Cookie'] = cookieHeader;
      }

      const bodyObj: Record<string, Object> = {};
      bodyObj['sitekey'] = sitekey;
      if (secondaryToken.length > 0) {
        bodyObj['secondaryToken'] = secondaryToken;
      }
      const body: string = JSON.stringify(bodyObj);

      const req: Record<string, Object> = {};
      req['method'] = http.RequestMethod.POST;
      req['header'] = headers;
      req['connectTimeout'] = AppConstants.REQUEST_TIMEOUT;
      req['readTimeout'] = AppConstants.REQUEST_TIMEOUT;
      req['extraData'] = body;

      const response = await httpRequest.request(url, req);
      const code: number = response.responseCode as number;
      let result: string = '';
      if (typeof response.result === 'string') {
        result = response.result as string;
      } else {
        try {
          result = JSON.stringify(response.result);
        } catch (_) {
          result = '{}';
        }
      }

      this.syncCookiesFromResponseHeader(response.header);
      this.resolveRcPromise(id, code, result);

      const cf: string | null = this.cookieStore.getCookieValue('cf_clearance');
      if (cf !== null && cf.length > 0) {
        this.consecutiveFailures = 0;
        hilog.info(0x0000, TAG, 'cf_clearance refreshed, len=%{public}d', cf.length);
      } else {
        this.consecutiveFailures++;
        hilog.error(0x0000, TAG, 'cf_clearance not updated (failures=%{public}d)', this.consecutiveFailures);
        this.checkAndStopIfNeeded();
      }
    } catch (err) {
      this.resolveRcPromise(id, 500, '{}');
      this.consecutiveFailures++;
      hilog.error(0x0000, TAG, 'rc request error: %{public}s', JSON.stringify(err));
      this.checkAndStopIfNeeded();
    } finally {
      this.callingRc = false;
      httpRequest.destroy();
    }
  }

  private syncCookiesFromResponseHeader(headerObj: Object | undefined | null): void {
    if (headerObj === undefined || headerObj === null) return;
    try {
      const headers: Record<string, Object> = headerObj as Record<string, Object>;
      const keys: string[] = Object.keys(headers);
      const setCookies: string[] = [];
      for (let i = 0; i < keys.length; i++) {
        const key: string = keys[i];
        if (key.toLowerCase() !== 'set-cookie') continue;
        const v = headers[key];
        if (typeof v === 'string') {
          setCookies.push(v as string);
        } else if (Array.isArray(v)) {
          const arr: Object[] = v as Object[];
          for (let j = 0; j < arr.length; j++) {
            const item = arr[j];
            if (typeof item === 'string') setCookies.push(item as string);
          }
        }
      }
      if (setCookies.length > 0) {
        this.cookieStore.ingestSetCookieHeaders(setCookies);
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Sync cookies failed: %{public}s', JSON.stringify(err));
    }
  }

  private resolveRcPromise(id: string, statusCode: number, body: string): void {
    if (this.controller === null) return;
    const escapedBody: string = CfClearanceRefreshService.escapeForJsString(body);
    const script: string = `window._resolveRc('${id}', ${statusCode}, '${escapedBody}')`;
    try {
      this.controller.runJavaScript(script).catch((_err: Object) => {
      });
    } catch (_) {
    }
  }

  private checkAndStopIfNeeded(): void {
    if (this.consecutiveFailures >= CfClearanceRefreshService.MAX_CONSECUTIVE_FAILURES) {
      hilog.error(0x0000, TAG, 'Too many failures, stop service');
      this.stop();
    }
  }

  private static escapeForJsString(s: string): string {
    let out: string = s;
    out = out.replace(/\\/g, '\\\\');
    out = out.replace(/'/g, '\\\'');
    out = out.replace(/\n/g, '\\n');
    out = out.replace(/\r/g, '\\r');
    return out;
  }

  private buildTurnstileHtml(sitekey: string): string {
    return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <script>
    var _originalFetch = window.fetch;
    var _pendingRc = {};
    var _rcId = 0;

    window.fetch = function(url, options) {
      var urlStr = '';
      if (typeof url === 'string') {
        urlStr = url;
      } else if (url && typeof url.url === 'string') {
        urlStr = url.url;
      }

      if (urlStr &&
          urlStr.indexOf('/cdn-cgi/challenge-platform/') !== -1 &&
          urlStr.indexOf('/rc/') !== -1) {
        var id = 'rc_' + (++_rcId);
        var parts = urlStr.split('/rc/');
        var chlId = parts.length > 1 ? parts[1].split('?')[0] : '';
        var body = {};
        try { body = JSON.parse(options && options.body ? options.body : '{}'); } catch(e) {}

        try {
          CfRefresh.onRcIntercepted(JSON.stringify({
            id: id,
            chlId: chlId,
            secondaryToken: body.secondaryToken || '',
            sitekey: body.sitekey || ''
          }));
        } catch (e) {}

        return new Promise(function(resolve) {
          _pendingRc[id] = resolve;
        });
      }
      return _originalFetch.apply(this, arguments);
    };

    window._resolveRc = function(id, status, body) {
      if (_pendingRc[id]) {
        try {
          _pendingRc[id](new Response(body || '{}', { status: status }));
        } catch (e) {
          _pendingRc[id](new Response('{}', { status: status }));
        }
        delete _pendingRc[id];
      }
    };
  </script>
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onTurnstileLoad" async defer></script>
</head>
<body>
  <div id="turnstile-container"></div>
  <script>
    function onTurnstileLoad() {
      try {
        turnstile.render('#turnstile-container', {
          sitekey: '${sitekey}',
          appearance: 'interaction-only',
          'refresh-expired': 'auto',
          'error-callback': function(error) {
            try { CfRefresh.onTurnstileError((error || 'render_error').toString()); } catch(e) {}
          }
        });
      } catch (e) {
        try { CfRefresh.onTurnstileError(e.toString()); } catch(_) {}
      }
    }
  </script>
</body>
</html>`;
  }
}

interface RcInterceptPayload {
  id?: string;
  chlId?: string;
  secondaryToken?: string;
  sitekey?: string;
}

class CfRefreshBridge {
  private service: CfClearanceRefreshService;

  constructor(service: CfClearanceRefreshService) {
    this.service = service;
  }

  onRcIntercepted(payload: string): void {
    this.service.onRcIntercepted(payload);
  }

  onTurnstileError(message: string): void {
    this.service.onTurnstileError(message);
  }
}
