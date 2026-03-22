import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { ArkWebHelper } from '../../common/utils/ArkWebHelper';
import { WindowManager } from '../../common/utils/WindowManager';
import { RouterManager } from '../../common/utils/RouterManager';
import { CookieStore } from '../../services/network/CookieStore';
import { CfChallengeService, CfVerifyContext } from '../../services/network/CfChallengeService';
import { CfClearanceRefreshService } from '../../services/network/CfClearanceRefreshService';
import { LoadingSpinner } from '../components/LoadingSpinner';

const TAG: string = 'CfChallengePage';
const VERIFY_URL: string = `${AppConstants.BASE_URL}/challenge`;

interface RcInterceptPayload {
  id: string;
  chlId: string;
  secondaryToken: string;
  sitekey: string;
}

interface ChallengePlatformResponsePayload {
  url: string;
  statusCode: number;
  via: string;
}

interface ChallengePageSnapshot {
  href: string;
  title: string;
  bodyText: string;
  hasActiveChallenge: boolean;
  activeSignals: string;
}

const NO_CHALLENGE_PRIMARY_DELAY_MS: number = 1500;
const NO_CHALLENGE_RETRY_DELAY_MS: number = 3500;
const NO_CHALLENGE_MAX_RETRY_COUNT: number = 2;

@ComponentV2
export struct CfChallengePage {
  @Local isLoading: boolean = true;
  @Local progress: number = 0;
  @Local errorMessage: string = '';

  private controller: webview.WebviewController = new webview.WebviewController('cf_challenge');
  private pollTimerId: number = -1;
  private noChallengeTimerId: number = -1;
  private finished: boolean = false;

  private bridge: CfChallengeBridge | null = null;
  private proxyRegistered: boolean = false;
  private callingRc: boolean = false;
  private rcInterceptTriggered: boolean = false;
  private challengePlatformResponseSeen: boolean = false;
  private initialCfClearanceSnapshot: string = '';
  private checkingClearance: boolean = false;
  private noChallengeRetryCount: number = 0;

  aboutToAppear(): void {
    ArkWebHelper.configureLinuxDoHostsUserAgent();
    this.resetVerifySignals();
    if (this.bridge === null) {
      this.bridge = new CfChallengeBridge(this);
    }

    CookieStore.getInstance().init()
      .then(() => {
        this.prepareCookies();
        this.snapshotInitialClearanceFromWebCookie();
        this.logEnterReason();
        this.startPolling();
      })
      .catch((_err: Object) => {
        this.prepareCookies();
        this.snapshotInitialClearanceFromWebCookie();
        this.logEnterReason();
        this.startPolling();
      });
  }

  aboutToDisappear(): void {
    this.stopPolling();
    this.stopNoChallengeCheck();
  }

  private prepareCookies(): void {
    // 删除旧的 cf_clearance（CookieStore + WebCookie）
    CookieStore.getInstance().delete('cf_clearance');
    try {
      // 优先尝试覆盖 HttpOnly（API 14+）
      webview.WebCookieManager.configCookieSync(
        AppConstants.BASE_URL,
        'cf_clearance=; Max-Age=0; Path=/;',
        false,
        true
      );
    } catch (err) {
      try {
        webview.WebCookieManager.configCookieSync(
          AppConstants.BASE_URL,
          'cf_clearance=; Max-Age=0; Path=/;',
          false
        );
      } catch (_) {
      }
      hilog.error(0x0000, TAG, 'Clear cf_clearance via WebCookieManager failed: %{public}s', JSON.stringify(err));
    }
    CookieStore.getInstance().syncToWebView();
  }

  private resetVerifySignals(): void {
    this.rcInterceptTriggered = false;
    this.challengePlatformResponseSeen = false;
    this.noChallengeRetryCount = 0;
  }

  private logEnterReason(): void {
    const ctx: CfVerifyContext | null = CfChallengeService.getInstance().getVerifyContext();
    const hits: string = ctx !== null && ctx.cfBodyHits.length > 0 ? ctx.cfBodyHits.join(',') : '-';
    const caller: string = ctx !== null && ctx.caller.length > 0 ? ctx.caller : '-';
    hilog.info(
      0x0000,
      TAG,
      'Enter verify page, enterReason=urlPath=%{public}s status=%{public}d isCfHeader=%{public}s isCfBody=%{public}s hits=%{public}s hasCfClearance=%{public}s cookieHeaderLen=%{public}d caller=%{public}s snapshotLen=%{public}d',
      ctx !== null ? ctx.urlPath : '-',
      ctx !== null ? ctx.statusCode : 0,
      ctx !== null && ctx.isCfHeader ? 'Y' : 'N',
      ctx !== null && ctx.isCfBody ? 'Y' : 'N',
      hits,
      ctx !== null && ctx.hasCfClearance ? 'Y' : 'N',
      ctx !== null ? ctx.cookieHeaderLength : 0,
      caller,
      this.initialCfClearanceSnapshot.length
    );
  }

  private extractCookieValue(cookieHeader: string, cookieName: string): string {
    const raw: string = cookieHeader.trim();
    if (raw.length === 0) return '';

    const parts: string[] = raw.split(';');
    for (let i = 0; i < parts.length; i++) {
      const item: string = parts[i].trim();
      if (item.length === 0) continue;
      const eq: number = item.indexOf('=');
      if (eq <= 0) continue;
      const name: string = item.substring(0, eq).trim();
      if (name !== cookieName) continue;
      return item.substring(eq + 1).trim();
    }
    return '';
  }

  private snapshotInitialClearanceFromWebCookie(): void {
    // Flutter 对齐：验证页加载时抓取 WebView 中的 cf_clearance 快照，用于过滤“旧值残留”
    this.initialCfClearanceSnapshot = '';
    try {
      const raw: string = webview.WebCookieManager.fetchCookieSync(AppConstants.BASE_URL, false);
      if (raw.length === 0) return;
      const cf: string = this.extractCookieValue(raw, 'cf_clearance');
      if (cf.length > 0) {
        this.initialCfClearanceSnapshot = cf;
        hilog.warn(0x0000, TAG, 'Initial WebCookie cf_clearance snapshot exists, len=%{public}d (will ignore same value)', cf.length);
      }
    } catch (_) {
    }
  }

  private startPolling(): void {
    if (this.pollTimerId >= 0) return;
    this.pollTimerId = setInterval(() => {
      this.checkClearanceCookie();
    }, 500);
  }

  private stopPolling(): void {
    if (this.pollTimerId >= 0) {
      clearInterval(this.pollTimerId);
      this.pollTimerId = -1;
    }
  }

  private stopNoChallengeCheck(): void {
    if (this.noChallengeTimerId >= 0) {
      clearTimeout(this.noChallengeTimerId);
      this.noChallengeTimerId = -1;
    }
  }

  private checkClearanceCookie(): void {
    if (this.finished || this.checkingClearance) return;
    this.checkingClearance = true;
    this.checkClearanceCookieInternal()
      .catch((err: Object) => {
        hilog.error(0x0000, TAG, 'checkClearanceCookie failed: %{public}s', JSON.stringify(err));
      })
      .finally(() => {
        this.checkingClearance = false;
      });
  }

  private async checkClearanceCookieInternal(): Promise<void> {
    if (this.finished) return;
    const store: CookieStore = CookieStore.getInstance();
    store.syncFromWebView();

    const cf: string | null = store.getCookieValue('cf_clearance');
    if (cf === null || cf.length === 0) {
      return;
    }
    if (this.initialCfClearanceSnapshot.length > 0 && cf === this.initialCfClearanceSnapshot) {
      store.delete('cf_clearance');
      hilog.info(0x0000, TAG, 'cf_clearance equals initial snapshot, ignore, len=%{public}d', cf.length);
      return;
    }
    await this.confirmVerificationReady(cf);
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

  private async confirmVerificationReady(cf: string): Promise<void> {
    if (this.finished) return;

    const snapshot: ChallengePageSnapshot = await this.readChallengePageSnapshot();
    if (snapshot.hasActiveChallenge) {
      hilog.info(
        0x0000,
        TAG,
        'New cf_clearance detected but challenge page still visible, continue waiting signals=%{public}s title=%{public}s url=%{public}s',
        snapshot.activeSignals.length > 0 ? snapshot.activeSignals : '-',
        snapshot.title,
        snapshot.href
      );
      return;
    }

    const store: CookieStore = CookieStore.getInstance();
    const syncedHeader: string = store.syncFromWebView();
    const confirmed: string | null = store.getCookieValue('cf_clearance');
    if (confirmed === null || confirmed.length === 0) {
      hilog.warn(0x0000, TAG, 'cf_clearance disappeared after syncFromWebView, cookieHeaderLen=%{public}d', syncedHeader.length);
      return;
    }
    if (this.initialCfClearanceSnapshot.length > 0 && confirmed === this.initialCfClearanceSnapshot) {
      store.delete('cf_clearance');
      hilog.info(0x0000, TAG, 'Confirmed cf_clearance still equals initial snapshot, ignore');
      return;
    }

    hilog.info(
      0x0000,
      TAG,
      'cf_clearance verified ready, rawLen=%{public}d confirmedLen=%{public}d',
      cf.length,
      confirmed.length
    );
    this.onSuccess();
  }

  private scheduleNoChallengeCheck(delayMs: number = NO_CHALLENGE_PRIMARY_DELAY_MS): void {
    this.stopNoChallengeCheck();
    this.noChallengeTimerId = setTimeout(() => {
      this.noChallengeTimerId = -1;
      this.checkNoChallengeState()
        .catch((err: Object) => {
          hilog.error(0x0000, TAG, 'checkNoChallengeState failed: %{public}s', JSON.stringify(err));
        });
    }, delayMs);
  }

  private async checkNoChallengeState(): Promise<void> {
    if (this.finished) return;
    const snapshot: ChallengePageSnapshot = await this.readChallengePageSnapshot();
    if (this.finished) return;

    if (snapshot.hasActiveChallenge) {
      hilog.info(
        0x0000,
        TAG,
        'Active challenge still visible, reschedule no-challenge check signals=%{public}s title=%{public}s url=%{public}s',
        snapshot.activeSignals.length > 0 ? snapshot.activeSignals : '-',
        snapshot.title,
        snapshot.href
      );
      this.scheduleNoChallengeCheck(NO_CHALLENGE_RETRY_DELAY_MS);
      return;
    }

    const store: CookieStore = CookieStore.getInstance();
    const syncedHeader: string = store.syncFromWebView();
    const cf: string | null = store.getCookieValue('cf_clearance');
    const hasNewCf: boolean = cf !== null
      && cf.length > 0
      && (this.initialCfClearanceSnapshot.length === 0 || cf !== this.initialCfClearanceSnapshot);

    if (hasNewCf) {
      hilog.info(
        0x0000,
        TAG,
        'No active challenge detected but new cf_clearance exists, auto success cookieHeaderLen=%{public}d cfLen=%{public}d title=%{public}s url=%{public}s',
        syncedHeader.length,
        cf !== null ? cf.length : 0,
        snapshot.title,
        snapshot.href
      );
      this.onSuccess();
      return;
    }

    const notFoundHint: boolean = this.hasPageNotFoundHint(snapshot);
    const shouldRetryWait: boolean = (notFoundHint || this.rcInterceptTriggered || this.challengePlatformResponseSeen)
      && this.noChallengeRetryCount < NO_CHALLENGE_MAX_RETRY_COUNT;
    if (shouldRetryWait) {
      this.noChallengeRetryCount += 1;
      hilog.warn(
        0x0000,
        TAG,
        'No active challenge and no new cf_clearance yet, wait longer retry=%{public}d/%{public}d cookieHeaderLen=%{public}d title=%{public}s url=%{public}s notFound=%{public}s rcIntercept=%{public}s challengeResponse=%{public}s',
        this.noChallengeRetryCount,
        NO_CHALLENGE_MAX_RETRY_COUNT,
        syncedHeader.length,
        snapshot.title,
        snapshot.href,
        notFoundHint ? 'Y' : 'N',
        this.rcInterceptTriggered ? 'Y' : 'N',
        this.challengePlatformResponseSeen ? 'Y' : 'N'
      );
      this.scheduleNoChallengeCheck(NO_CHALLENGE_RETRY_DELAY_MS);
      return;
    }

    hilog.warn(
      0x0000,
      TAG,
      'No active challenge and no new cf_clearance after delay, auto exit cookieHeaderLen=%{public}d title=%{public}s url=%{public}s notFound=%{public}s rcIntercept=%{public}s challengeResponse=%{public}s retry=%{public}d',
      syncedHeader.length,
      snapshot.title,
      snapshot.href,
      notFoundHint ? 'Y' : 'N',
      this.rcInterceptTriggered ? 'Y' : 'N',
      this.challengePlatformResponseSeen ? 'Y' : 'N',
      this.noChallengeRetryCount
    );
    this.onNoChallengeFailure();
  }

  private async readChallengePageSnapshot(): Promise<ChallengePageSnapshot> {
    const fallback: ChallengePageSnapshot = {
      href: VERIFY_URL,
      title: '',
      bodyText: '',
      hasActiveChallenge: false,
      activeSignals: ''
    };
    const script: string = `(function() {
      try {
        var href = location && location.href ? String(location.href) : '';
        var title = document && document.title ? String(document.title) : '';
        var body = document && document.body ? document.body : null;
        var text = body && body.innerText ? String(body.innerText) : '';
        if (text.length > 600) {
          text = text.substring(0, 600);
        }
        var lowerTitle = title.toLowerCase();
        var lowerText = text.toLowerCase();
        var lowerHtml = body && body.innerHTML ? String(body.innerHTML).toLowerCase() : '';
        var hasNotFoundHint = lowerTitle.indexOf('找不到页面') >= 0
          || lowerText.indexOf('该页面不存在') >= 0
          || lowerText.indexOf('不是一个不公开页面') >= 0
          || lowerText.indexOf('或者是一个不公开页面') >= 0
          || lowerTitle.indexOf('page does not exist') >= 0
          || lowerText.indexOf('page does not exist') >= 0
          || lowerText.indexOf('not a public page') >= 0;
        var hasChallengeTitle = lowerTitle.indexOf('请稍候') >= 0
          || lowerTitle.indexOf('just a moment') >= 0;
        var hasChallengeText = lowerText.indexOf('请稍候') >= 0
          || lowerText.indexOf('just a moment') >= 0
          || lowerText.indexOf('verifying you are human') >= 0
          || lowerText.indexOf('checking your browser before accessing') >= 0;
        var hasChallengeHtml = lowerHtml.indexOf('challenge-running') >= 0
          || lowerHtml.indexOf('challenge-stage') >= 0
          || lowerHtml.indexOf('cf_chl_opt') >= 0
          || lowerHtml.indexOf('challenge-platform') >= 0;
        var signals = [];
        if (hasChallengeTitle) {
          signals.push('title');
        }
        if (hasChallengeText) {
          signals.push('text');
        }
        if (hasChallengeHtml) {
          signals.push('html');
        }
        var hasActive = !hasNotFoundHint && (hasChallengeTitle || hasChallengeText || hasChallengeHtml);
        return JSON.stringify({
          href: href,
          title: title,
          bodyText: text,
          hasActiveChallenge: hasActive,
          activeSignals: signals.join(',')
        });
      } catch (e) {
        return JSON.stringify({
          href: '',
          title: '',
          bodyText: '',
          hasActiveChallenge: false,
          activeSignals: ''
        });
      }
    })();`;
    try {
      const raw: string = await this.controller.runJavaScript(script);
      const normalized: string = this.normalizeJsStringResult(raw);
      if (normalized.length === 0) {
        return fallback;
      }
      const parsed: Object = JSON.parse(normalized) as Object;
      if (parsed === null || typeof parsed !== 'object') {
        return fallback;
      }
      const obj: Record<string, Object> = parsed as Record<string, Object>;
      return {
        href: typeof obj['href'] === 'string' ? obj['href'] as string : fallback.href,
        title: typeof obj['title'] === 'string' ? obj['title'] as string : '',
        bodyText: typeof obj['bodyText'] === 'string' ? obj['bodyText'] as string : '',
        hasActiveChallenge: obj['hasActiveChallenge'] === true,
        activeSignals: typeof obj['activeSignals'] === 'string' ? obj['activeSignals'] as string : ''
      };
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Read challenge page snapshot failed: %{public}s', JSON.stringify(err));
      return fallback;
    }
  }

  private hasPageNotFoundHint(snapshot: ChallengePageSnapshot): boolean {
    const title: string = snapshot.title.trim().toLowerCase();
    const body: string = snapshot.bodyText.trim().toLowerCase();
    return title.indexOf('该页面不存在') >= 0
      || body.indexOf('该页面不存在') >= 0
      || body.indexOf('不是一个不公开页面') >= 0
      || body.indexOf('或者是一个不公开页面') >= 0
      || title.indexOf('page does not exist') >= 0
      || body.indexOf('page does not exist') >= 0
      || body.indexOf('not a public page') >= 0;
  }

  private tryExtractSitekeyFromPage(): void {
    try {
      this.controller.runJavaScript('document.documentElement.outerHTML')
        .then((html: string) => {
          if (typeof html === 'string' && html.length > 0) {
            CfClearanceRefreshService.getInstance().extractAndUpdateSitekey(html);
          }
        })
        .catch((_err: Object) => {
        });
    } catch (_) {
    }
  }

  private registerProxyIfNeeded(): void {
    if (this.proxyRegistered) return;
    if (this.bridge === null) return;
    try {
      this.controller.registerJavaScriptProxy(
        this.bridge as Object,
        'CfChallenge',
        ['onRcIntercepted', 'onTurnstileError', 'onChallengePlatformResponse']
      );
      this.proxyRegistered = true;
    } catch (err) {
      hilog.error(0x0000, TAG, 'registerJavaScriptProxy failed: %{public}s', JSON.stringify(err));
    }
  }

  private installRcInterceptor(): void {
    const sk: string = CfClearanceRefreshService.getInstance().getSitekey();
    const script: string = this.buildRcInterceptorScript(sk);
    try {
      this.controller.runJavaScript(script).catch((_err: Object) => {
      });
    } catch (_) {
    }
  }

  private buildRcInterceptorScript(sitekey: string): string {
    const escaped: string = CfChallengePage.escapeForJsString(sitekey);
    return `(function() {
  try {
    if (window._hmCfRcInstalled) return;
    window._hmCfRcInstalled = true;

    window._hmCfSitekey = '${escaped}';

    var _originalFetch = window.fetch;
    var _originalXhrOpen = XMLHttpRequest.prototype.open;
    var _originalXhrSend = XMLHttpRequest.prototype.send;
    var _pending = {};
    var _rcId = 0;

    function _safeJsonParse(s) {
      try { return JSON.parse(s); } catch (e) { return null; }
    }

    function _getSitekeyFromDom() {
      try {
        var el = document && document.querySelector ? document.querySelector('[data-sitekey]') : null;
        if (el && el.getAttribute) {
          return el.getAttribute('data-sitekey') || '';
        }
      } catch (e) {}
      return '';
    }

    function _extractUrl(input) {
      if (typeof input === 'string') return input;
      if (input && typeof input.url === 'string') return input.url;
      return '';
    }

    function _notifyChallengeResponse(url, statusCode, via) {
      try {
        if (!url || url.indexOf('/cdn-cgi/challenge-platform/') === -1) return;
        if (typeof CfChallenge === 'undefined' || !CfChallenge) return;
        if (typeof CfChallenge.onChallengePlatformResponse !== 'function') return;
        CfChallenge.onChallengePlatformResponse(JSON.stringify({
          url: url,
          statusCode: typeof statusCode === 'number' ? statusCode : 0,
          via: via || ''
        }));
      } catch (e) {}
    }

    window._resolveRc = function(id, statusCode, body) {
      try {
        var p = _pending[id];
        if (!p) return;
        delete _pending[id];
        var text = (typeof body === 'string') ? body : (body ? ('' + body) : '');
        var resp = new Response(text, { status: statusCode, headers: { 'Content-Type': 'application/json' } });
        p.resolve(resp);
      } catch (e) {
        try {
          var p2 = _pending[id];
          if (p2) { delete _pending[id]; p2.reject(e); }
        } catch (e2) {}
      }
    };

    XMLHttpRequest.prototype.open = function(method, url) {
      try {
        this._hmCfUrl = _extractUrl(url);
      } catch (e) {
        this._hmCfUrl = '';
      }
      return _originalXhrOpen.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function() {
      var self = this;
      try {
        if (self._hmCfUrl && self._hmCfUrl.indexOf('/cdn-cgi/challenge-platform/') !== -1) {
          self.addEventListener('load', function() {
            _notifyChallengeResponse(self._hmCfUrl, self.status || 0, 'xhr');
          });
        }
      } catch (e) {}
      return _originalXhrSend.apply(this, arguments);
    };

    window.fetch = function(url, options) {
      var urlStr = _extractUrl(url);

      if (urlStr &&
          urlStr.indexOf('/cdn-cgi/challenge-platform/') !== -1 &&
          urlStr.indexOf('/rc/') !== -1 &&
          typeof CfChallenge !== 'undefined' &&
          CfChallenge &&
          typeof CfChallenge.onRcIntercepted === 'function') {
        var id = '' + (++_rcId);
        _pending[id] = {};
        var p = new Promise(function(resolve, reject) {
          _pending[id].resolve = resolve;
          _pending[id].reject = reject;
        });

        var chlId = '';
        try {
          var parts = urlStr.split('/rc/');
          if (parts.length >= 2) {
            var rest = parts[1];
            var q = rest.indexOf('?');
            chlId = q >= 0 ? rest.substring(0, q) : rest;
          }
        } catch (e) {}

        var secondaryToken = '';
        var sitekey = (window._hmCfSitekey && typeof window._hmCfSitekey === 'string') ? window._hmCfSitekey : '';
        try {
          var domSk = _getSitekeyFromDom();
          if (domSk) sitekey = domSk;
        } catch (e) {}

        try {
          var bodyStr = options && options.body ? options.body : '';
          if (bodyStr && typeof bodyStr === 'string') {
            var obj = _safeJsonParse(bodyStr);
            if (obj) {
              if (obj.secondaryToken && typeof obj.secondaryToken === 'string') secondaryToken = obj.secondaryToken;
              if ((!sitekey) && obj.sitekey && typeof obj.sitekey === 'string') sitekey = obj.sitekey;
            }
          }
        } catch (e) {}

        try {
          CfChallenge.onRcIntercepted(JSON.stringify({
            id: id,
            chlId: chlId,
            secondaryToken: secondaryToken,
            sitekey: sitekey
          }));
        } catch (e) {}
        return p;
      }
      var fetchResult = _originalFetch.apply(this, arguments);
      if (urlStr && urlStr.indexOf('/cdn-cgi/challenge-platform/') !== -1) {
        return Promise.resolve(fetchResult).then(function(resp) {
          try {
            _notifyChallengeResponse(urlStr, resp && typeof resp.status === 'number' ? resp.status : 0, 'fetch');
          } catch (e) {}
          return resp;
        });
      }
      return fetchResult;
    };
  } catch (e) {}
})();`;
  }

  private static escapeForJsString(s: string): string {
    let out: string = s;
    out = out.replace(/\\/g, '\\\\');
    out = out.replace(/'/g, '\\\'');
    out = out.replace(/\n/g, '\\n');
    out = out.replace(/\r/g, '\\r');
    return out;
  }

  private resolveRcPromise(id: string, statusCode: number, body: string): void {
    const escapedBody: string = CfChallengePage.escapeForJsString(body);
    const script: string = `window._resolveRc('${id}', ${statusCode}, '${escapedBody}')`;
    try {
      this.controller.runJavaScript(script).catch((_err: Object) => {
      });
    } catch (_) {
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
        CookieStore.getInstance().ingestSetCookieHeaders(setCookies);
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Sync cookies from rc failed: %{public}s', JSON.stringify(err));
    }
  }

  private async callRcEndpoint(id: string, chlId: string, secondaryToken: string, sitekey: string): Promise<void> {
    this.callingRc = true;
    const httpRequest = http.createHttp();
    try {
      await CookieStore.getInstance().init();
      const url: string = `${AppConstants.BASE_URL}/cdn-cgi/challenge-platform/h/g/rc/${chlId}`;
      const headers: Record<string, string> = {};
      headers['User-Agent'] = AppConstants.USER_AGENT;
      headers['Accept'] = '*/*';
      headers['Content-Type'] = 'application/json';
      headers['Origin'] = AppConstants.BASE_URL;
      headers['Referer'] = `${AppConstants.BASE_URL}/`;

      const cookieHeader: string = CookieStore.getInstance().getCookieHeader();
      if (cookieHeader.length > 0) {
        headers['Cookie'] = cookieHeader;
      }

      const bodyObj: Record<string, Object> = {};
      bodyObj['sitekey'] = sitekey;
      if (secondaryToken.length > 0) {
        bodyObj['secondaryToken'] = secondaryToken;
      }

      const req: Record<string, Object> = {};
      req['method'] = http.RequestMethod.POST;
      req['header'] = headers;
      req['connectTimeout'] = AppConstants.REQUEST_TIMEOUT;
      req['readTimeout'] = AppConstants.REQUEST_TIMEOUT;
      req['extraData'] = JSON.stringify(bodyObj);

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
      this.handleChallengePlatformResponse(url, code, 'native_rc');
      this.resolveRcPromise(id, code, result);

      const cf: string | null = CookieStore.getInstance().getCookieValue('cf_clearance');
      if (cf !== null && cf.length > 0) {
        hilog.info(0x0000, TAG, 'cf_clearance updated via rc, len=%{public}d', cf.length);
        setTimeout(() => {
          this.checkClearanceCookie();
        }, 200);
      }
    } catch (err) {
      this.resolveRcPromise(id, 500, '{}');
      hilog.error(0x0000, TAG, 'rc request error: %{public}s', JSON.stringify(err));
    } finally {
      this.callingRc = false;
      httpRequest.destroy();
    }
  }

  // ---------------------------------------------------------------------------
  // JS Bridge 回调（由 registerJavaScriptProxy 注入）
  // ---------------------------------------------------------------------------

  onTurnstileError(message: string): void {
    if (this.finished) return;
    if (message.length > 0) {
      this.errorMessage = message;
    }
  }

  onChallengePlatformResponse(payload: string): void {
    if (this.finished) return;

    let data: ChallengePlatformResponsePayload | null = null;
    try {
      const parsed: Object = JSON.parse(payload) as Object;
      data = parsed as ChallengePlatformResponsePayload;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Parse challenge platform payload failed: %{public}s', JSON.stringify(err));
      return;
    }
    if (data === null) return;

    const url: string = typeof data.url === 'string' ? data.url as string : '';
    const statusCode: number = typeof data.statusCode === 'number' ? data.statusCode as number : 0;
    const via: string = typeof data.via === 'string' ? data.via as string : '';
    this.handleChallengePlatformResponse(url, statusCode, via);
  }

  onRcIntercepted(payload: string): void {
    if (this.finished) return;
    this.rcInterceptTriggered = true;

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
    const fallbackSk: string = CfClearanceRefreshService.getInstance().getSitekey();
    const effectiveSk: string = sitekey.length > 0 ? sitekey : fallbackSk;

    if (id.length === 0) return;

    if (this.callingRc) {
      this.resolveRcPromise(id, 503, '{}');
      return;
    }
    if (chlId.length === 0) {
      this.resolveRcPromise(id, 400, '{}');
      return;
    }
    if (effectiveSk.length === 0) {
      this.resolveRcPromise(id, 400, '{}');
      return;
    }

    this.callRcEndpoint(id, chlId, secondaryToken, effectiveSk).catch((err: Object) => {
      hilog.error(0x0000, TAG, 'callRcEndpoint failed: %{public}s', JSON.stringify(err));
    });
  }

  private handleChallengePlatformResponse(url: string, statusCode: number, via: string): void {
    if (this.finished) return;
    this.challengePlatformResponseSeen = true;
    hilog.info(
      0x0000,
      TAG,
      'Challenge platform response observed via=%{public}s status=%{public}d url=%{public}s',
      via.length > 0 ? via : '-',
      statusCode,
      url.length > 0 ? url : '-'
    );
    this.checkClearanceCookie();
    setTimeout(() => {
      this.checkClearanceCookie();
    }, 300);
    setTimeout(() => {
      this.checkClearanceCookie();
    }, 1200);
    this.scheduleNoChallengeCheck(NO_CHALLENGE_RETRY_DELAY_MS);
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
      'CfChallenge load failure: mainFrame=%{public}s code=%{public}d url=%{public}s message=%{public}s',
      isMainFrame ? 'Y' : 'N',
      code,
      requestUrl,
      message
    );
    if (!isMainFrame) {
      return;
    }
    this.isLoading = false;
    this.errorMessage = message.length > 0 ? message : '加载失败';
  }

  private onSuccess(): void {
    if (this.finished) return;
    this.finished = true;
    this.stopPolling();
    this.stopNoChallengeCheck();
    const cf: string | null = CookieStore.getInstance().getCookieValue('cf_clearance');
    const cfLen: number = cf !== null ? (cf as string).length : 0;
    hilog.info(
      0x0000,
      TAG,
      'Exit verify page, exitReason=success rcIntercept=%{public}s challengeResponse=%{public}s retry=%{public}d cfLen=%{public}d',
      this.rcInterceptTriggered ? 'Y' : 'N',
      this.challengePlatformResponseSeen ? 'Y' : 'N',
      this.noChallengeRetryCount,
      cfLen
    );
    // 先 pop 触发页面返回动画，再延迟一帧 resolve Promise
    // 避免 complete(true) 立即唤醒 HttpClient 重试，与 pop 动画竞争再次 push CF 页面
    RouterManager.pop();
    setTimeout(() => {
      CfChallengeService.getInstance().complete(true);
    }, 16);
  }

  private onNoChallengeFailure(): void {
    if (this.finished) return;
    this.finished = true;
    this.stopPolling();
    this.stopNoChallengeCheck();
    hilog.warn(
      0x0000,
      TAG,
      'Exit verify page, exitReason=no_active_challenge_no_new_cookie rcIntercept=%{public}s challengeResponse=%{public}s retry=%{public}d',
      this.rcInterceptTriggered ? 'Y' : 'N',
      this.challengePlatformResponseSeen ? 'Y' : 'N',
      this.noChallengeRetryCount
    );
    RouterManager.pop();
    setTimeout(() => {
      CfChallengeService.getInstance().complete(false);
    }, 16);
  }

  private onCancel(): void {
    if (this.finished) return;
    this.finished = true;
    this.stopPolling();
    this.stopNoChallengeCheck();
    hilog.info(
      0x0000,
      TAG,
      'Exit verify page, exitReason=cancel rcIntercept=%{public}s challengeResponse=%{public}s retry=%{public}d',
      this.rcInterceptTriggered ? 'Y' : 'N',
      this.challengePlatformResponseSeen ? 'Y' : 'N',
      this.noChallengeRetryCount
    );
    CfChallengeService.getInstance().complete(false);
    RouterManager.pop();
  }

  private onRetry(): void {
    this.errorMessage = '';
    this.resetVerifySignals();
    try {
      this.controller.refresh();
    } catch (err) {
      hilog.error(0x0000, TAG, 'Retry refresh failed: %{public}s', JSON.stringify(err));
    }
  }

  @Builder
  TopBar() {
    Row() {
      // 返回/取消
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
        this.onCancel();
      })

      Text('安全验证')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .margin({ left: 4 })

      Blank().layoutWeight(1)

      // 重试
      if (this.errorMessage.length > 0) {
        Text('重载')
          .fontSize(14)
          .fontColor($r('app.color.primary'))
          .margin({ right: 12 })
          .onClick(() => {
            this.onRetry();
          })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8, top: WindowManager.getSystemAvoidAreaTopVp() })
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
          Web({ src: VERIFY_URL, controller: this.controller })
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
              this.stopNoChallengeCheck();
              this.registerProxyIfNeeded();
            })
            .onProgressChange((event: OnProgressChangeEvent) => {
              this.progress = event.newProgress;
            })
            .onPageEnd(() => {
              this.isLoading = false;
              this.progress = 100;
              this.registerProxyIfNeeded();
              this.installRcInterceptor();
              this.checkClearanceCookie();
              this.tryExtractSitekeyFromPage();
              // Managed Challenge 等验证完成后需要额外时间写 cookie，兜底多检测两次
              setTimeout(() => {
                this.checkClearanceCookie();
              }, 200);
              setTimeout(() => {
                this.checkClearanceCookie();
              }, 600);
              this.scheduleNoChallengeCheck();
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
              this.handlePageLoadFailure(event.request, errorInfo.length > 0 ? errorInfo : '加载失败', errorCode);
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
                : '加载失败';
              this.handlePageLoadFailure(event.request, httpMessage, responseCode);
            })

          if (this.isLoading && this.errorMessage.length === 0) {
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
                .fontSize(26)
                .fontColor([$r('app.color.on_surface_tertiary')])
                .margin({ bottom: 10 })
              Text('验证页加载失败')
                .fontSize(14)
                .fontColor($r('app.color.on_surface'))
                .margin({ bottom: 6 })
              Text(this.errorMessage)
                .fontSize(12)
                .fontColor($r('app.color.on_surface_secondary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Button('重试')
                .margin({ top: 12 })
                .onClick(() => {
                  this.onRetry();
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
    }
    .hideTitleBar(true)
    .hideToolBar(true)
    .backgroundColor($r('app.color.background'))
  }
}

class CfChallengeBridge {
  private page: CfChallengePage;

  constructor(page: CfChallengePage) {
    this.page = page;
  }

  onRcIntercepted(payload: string): void {
    this.page.onRcIntercepted(payload);
  }

  onTurnstileError(message: string): void {
    this.page.onTurnstileError(message);
  }

  onChallengePlatformResponse(payload: string): void {
    this.page.onChallengePlatformResponse(payload);
  }
}
