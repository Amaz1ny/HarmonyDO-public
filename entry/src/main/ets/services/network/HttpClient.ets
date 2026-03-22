import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { ApiConstants } from '../../common/constants/ApiConstants';
import { AuthService } from '../auth/AuthService';
import { AuthSessionService } from '../auth/AuthSessionService';
import { CookieStore } from './CookieStore';
import { CfChallengeService, CfChallengeDetectResult, CfVerifyContext } from './CfChallengeService';
import { CfClearanceRefreshService } from './CfClearanceRefreshService';

const TAG: string = 'HttpClient';

export interface CfGuardOptions {
  silent?: boolean;
  caller?: string;
}

export interface HttpBinaryResponse {
  code: number;
  bytes: ArrayBuffer;
  header: Object | null;
}

/**
 * HTTP 客户端封装
 * 使用 @ohos.net.http 原生 API
 */
export class HttpClient {
  private baseUrl: string;
  private csrfToken: string = '';
  private cookieStore: CookieStore = CookieStore.getInstance();

  constructor(baseUrl: string = AppConstants.BASE_URL) {
    this.baseUrl = baseUrl;
  }

  /**
   * 设置 CSRF Token
   */
  setCsrfToken(token: string): void {
    this.csrfToken = token;
  }

  /**
   * 设置 Cookies
   */
  setCookies(cookies: string): void {
    const normalized: string = cookies.trim();
    if (normalized.length === 0) {
      return;
    }
    this.cookieStore.ingestCookieHeader(normalized);
  }

  /**
   * 构建请求头
   */
  private buildHeaders(
    accept: string = 'application/json',
    contentType: string = 'application/json',
    extraHeaders: Record<string, string> | null = null
  ): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['User-Agent'] = AppConstants.USER_AGENT;
    headers['Accept'] = accept;
    headers['Content-Type'] = contentType;

    if (this.csrfToken.length > 0) {
      headers['X-CSRF-Token'] = this.csrfToken;
    }
    const cookieHeader: string = this.cookieStore.getCookieHeader();
    if (cookieHeader.length > 0) {
      headers['Cookie'] = cookieHeader;
    }

    if (extraHeaders !== null) {
      const keys: string[] = Object.keys(extraHeaders);
      for (let i = 0; i < keys.length; i++) {
        const k: string = keys[i];
        const v: string = extraHeaders[k];
        if (v !== undefined && v !== null && v.length > 0) {
          headers[k] = v;
        }
      }
    }
    return headers;
  }

  private syncCookiesFromResponseHeader(headerObj: Object | undefined | null, requestGeneration: number): void {
    if (headerObj === undefined || headerObj === null) return;
    if (!AuthSessionService.getInstance().isCurrentGeneration(requestGeneration)) {
      hilog.warn(0x0000, TAG, 'Skip Set-Cookie sync for stale auth session generation=%{public}d', requestGeneration);
      return;
    }
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

  private isSuccessStatus(code: number): boolean {
    return code >= 200 && code < 300;
  }

  private async syncAuthContext(): Promise<void> {
    try {
      await this.cookieStore.init();
      const auth: AuthService = AuthService.getInstance();
      await auth.init();

      const storedCsrf: string = auth.getCsrfToken().trim();
      if (storedCsrf.length > 0) {
        this.csrfToken = storedCsrf;
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Sync auth context failed: %{public}s', JSON.stringify(err));
    }
  }

  private async persistCsrfToken(token: string): Promise<void> {
    this.csrfToken = token;
    try {
      await AuthService.getInstance().updateCsrfToken(token);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Persist csrf token failed: %{public}s', JSON.stringify(err));
    }
  }

  private hasAuthCookies(): boolean {
    return this.cookieStore.getCookieHeader().length > 0;
  }

  private async fetchCsrfToken(connectTimeoutMs: number | null = null, readTimeoutMs: number | null = null): Promise<string> {
    await this.cookieStore.init();
    await this.syncAuthContext();
    const requestGeneration: number = AuthSessionService.getInstance().captureGeneration();

    if (!this.hasAuthCookies()) {
      return '';
    }

    const url: string = `${this.baseUrl}${ApiConstants.CSRF}`;
    const headers: Record<string, string> = this.buildHeaders('application/json', 'application/json', null);
    const resp: Record<string, Object> = await this.requestWithCfGuardDetailed(
      url,
      http.RequestMethod.GET,
      null,
      false,
      headers,
      connectTimeoutMs,
      readTimeoutMs,
      null,
      0
    );
    const codeVal = resp['code'];
    const code: number = codeVal !== undefined && codeVal !== null ? codeVal as number : 0;
    const resultVal = resp['result'];
    const result: string = resultVal !== undefined && resultVal !== null ? resultVal as string : '';
    if (!this.isSuccessStatus(code) || result.trim().length === 0) {
      return '';
    }

    try {
      const json: Record<string, Object> = JSON.parse(result) as Record<string, Object>;
      const csrfVal = json['csrf'];
      const csrf: string = csrfVal !== undefined && csrfVal !== null ? csrfVal.toString().trim() : '';
      if (csrf.length > 0) {
        if (!AuthSessionService.getInstance().isCurrentGeneration(requestGeneration)) {
          hilog.warn(0x0000, TAG, 'Ignore csrf token from stale auth session generation=%{public}d', requestGeneration);
          return '';
        }
        await this.persistCsrfToken(csrf);
        return csrf;
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Parse csrf token failed: %{public}s', JSON.stringify(err));
    }
    return '';
  }

  private async ensureCsrfToken(forceRefresh: boolean = false, connectTimeoutMs: number | null = null, readTimeoutMs: number | null = null): Promise<void> {
    await this.syncAuthContext();
    if (!this.hasAuthCookies()) {
      return;
    }
    if (!forceRefresh && this.csrfToken.trim().length > 0) {
      return;
    }
    await this.fetchCsrfToken(connectTimeoutMs, readTimeoutMs);
  }

  private isBadCsrfResponse(code: number, result: string): boolean {
    if (code !== 403) {
      return false;
    }
    const trimmed: string = result !== undefined && result !== null ? result.toString().trim() : '';
    return trimmed === '["BAD CSRF"]'
      || trimmed === 'BAD CSRF'
      || trimmed.indexOf('"BAD CSRF"') >= 0;
  }

  private async requestWithCsrfRetry(
    url: string,
    method: http.RequestMethod,
    body: string | null,
    accept: string,
    contentType: string,
    extraHeaders: Record<string, string> | null,
    connectTimeoutMs: number | null,
    readTimeoutMs: number | null,
    guardOptions: CfGuardOptions | null = null
  ): Promise<Record<string, Object>> {
    await this.cookieStore.init();
    await this.ensureCsrfToken(false, connectTimeoutMs, readTimeoutMs);

    let headers: Record<string, string> = this.buildHeaders(accept, contentType, extraHeaders);
    let resp: Record<string, Object> = await this.requestWithCfGuardDetailed(
      url,
      method,
      body,
      false,
      headers,
      connectTimeoutMs,
      readTimeoutMs,
      guardOptions,
      0
    );

    const codeVal = resp['code'];
    const code: number = codeVal !== undefined && codeVal !== null ? codeVal as number : 0;
    const resultVal = resp['result'];
    const result: string = resultVal !== undefined && resultVal !== null ? resultVal as string : '';
    if (!this.isBadCsrfResponse(code, result)) {
      return resp;
    }

    hilog.warn(0x0000, TAG, 'BAD CSRF detected for %{public}s %{public}s, refreshing token and retrying once', method.toString(), url);
    await this.persistCsrfToken('');
    await this.ensureCsrfToken(true, connectTimeoutMs, readTimeoutMs);
    headers = this.buildHeaders(accept, contentType, extraHeaders);
    return await this.requestWithCfGuardDetailed(
      url,
      method,
      body,
      false,
      headers,
      connectTimeoutMs,
      readTimeoutMs,
      guardOptions,
      0
    );
  }

  private toUrlPath(url: string): string {
    try {
      if (url.startsWith(this.baseUrl)) {
        const out: string = url.substring(this.baseUrl.length);
        return out.length > 0 ? out : '/';
      }
    } catch (_) {
    }
    return url;
  }

  private joinComma(list: string[]): string {
    if (list.length === 0) return '';
    let out: string = '';
    for (let i = 0; i < list.length; i++) {
      if (i > 0) out += ',';
      out += list[i];
    }
    return out;
  }

  private getHeaderValue(headerObj: Object | undefined | null, name: string): string {
    if (headerObj === undefined || headerObj === null) return '';
    try {
      const headers: Record<string, Object> = headerObj as Record<string, Object>;
      const keys: string[] = Object.keys(headers);
      const target: string = name.toLowerCase();
      for (let i = 0; i < keys.length; i++) {
        const k: string = keys[i];
        if (k.toLowerCase() !== target) continue;
        const v: Object = headers[k];
        if (typeof v === 'string') {
          return v as string;
        }
        if (Array.isArray(v)) {
          const arr: Object[] = v as Object[];
          for (let j = 0; j < arr.length; j++) {
            const item: Object = arr[j];
            if (typeof item === 'string') return item as string;
          }
        }
        return v !== null && v !== undefined ? v.toString() : '';
      }
    } catch (_) {
    }
    return '';
  }

  private isHtmlContentType(contentType: string): boolean {
    const lower: string = contentType.toLowerCase();
    if (lower.indexOf('text/html') >= 0) return true;
    if (lower.indexOf('application/xhtml') >= 0) return true;
    if (lower.indexOf('application/xml') >= 0) return true;
    return false;
  }

  private containsHit(hits: string[], key: string): boolean {
    for (let i = 0; i < hits.length; i++) {
      if (hits[i] === key) return true;
    }
    return false;
  }

  private async requestOnce(
    url: string,
    method: http.RequestMethod,
    body: string | null,
    headers: Record<string, string> | null = null,
    connectTimeout: number | null = null,
    readTimeout: number | null = null
  ): Promise<Record<string, Object>> {
    const requestGeneration: number = AuthSessionService.getInstance().captureGeneration();
    const httpRequest = http.createHttp();
    try {
      const req: Record<string, Object> = {};
      req['method'] = method;
      req['header'] = headers !== null ? headers : this.buildHeaders();
      req['connectTimeout'] = connectTimeout !== null ? connectTimeout : AppConstants.REQUEST_TIMEOUT;
      req['readTimeout'] = readTimeout !== null ? readTimeout : AppConstants.REQUEST_TIMEOUT;
      if (body !== null && body.length > 0) {
        req['extraData'] = body;
      }

      const response = await httpRequest.request(url, req).catch((err: Object) => {
        let errText: string = '';
        try {
          errText = JSON.stringify(err);
        } catch (_) {
          try {
            errText = err !== null && err !== undefined ? err.toString() : '';
          } catch (_) {
            errText = '';
          }
        }
        hilog.error(0x0000, TAG, 'Request %{public}s failed: %{public}s', url, errText);
        throw new Error(`HTTP request failed: ${url}${errText.length > 0 ? `, ${errText}` : ''}`);
      });

      // 写回 Set-Cookie
      this.syncCookiesFromResponseHeader(response.header, requestGeneration);

      const out: Record<string, Object> = {};
      out['code'] = response.responseCode as number;
      out['result'] = response.result as string;
      out['header'] = response.header as Object;
      return out;
    } finally {
      httpRequest.destroy();
    }
  }

  private async requestOnceBinary(
    url: string,
    headers: Record<string, string> | null = null,
    connectTimeout: number | null = null,
    readTimeout: number | null = null
  ): Promise<Record<string, Object>> {
    const requestGeneration: number = AuthSessionService.getInstance().captureGeneration();
    const httpRequest = http.createHttp();
    try {
      const req: Record<string, Object> = {};
      req['method'] = http.RequestMethod.GET;
      req['header'] = headers !== null ? headers : this.buildHeaders('*/*', 'application/octet-stream', null);
      req['connectTimeout'] = connectTimeout !== null ? connectTimeout : AppConstants.REQUEST_TIMEOUT;
      req['readTimeout'] = readTimeout !== null ? readTimeout : AppConstants.REQUEST_TIMEOUT;
      req['expectDataType'] = http.HttpDataType.ARRAY_BUFFER;

      const response = await httpRequest.request(url, req).catch((err: Object) => {
        let errText: string = '';
        try {
          errText = JSON.stringify(err);
        } catch (_) {
          try {
            errText = err !== null && err !== undefined ? err.toString() : '';
          } catch (_) {
            errText = '';
          }
        }
        hilog.error(0x0000, TAG, 'Binary request %{public}s failed: %{public}s', url, errText);
        throw new Error(`HTTP binary request failed: ${url}${errText.length > 0 ? `, ${errText}` : ''}`);
      });

      this.syncCookiesFromResponseHeader(response.header, requestGeneration);

      const out: Record<string, Object> = {};
      out['code'] = response.responseCode as number;
      out['result'] = response.result as ArrayBuffer;
      out['header'] = response.header as Object;
      return out;
    } finally {
      httpRequest.destroy();
    }
  }

  private async requestWithCfGuardDetailed(
    url: string,
    method: http.RequestMethod,
    body: string | null,
    skipCfGuard: boolean,
    headers: Record<string, string> | null = null,
    connectTimeout: number | null = null,
    readTimeout: number | null = null,
    guardOptions: CfGuardOptions | null = null,
    retryAttempt: number = 0
  ): Promise<Record<string, Object>> {
    const requestGeneration: number = AuthSessionService.getInstance().captureGeneration();
    const resp: Record<string, Object> = await this.requestOnce(url, method, body, headers, connectTimeout, readTimeout);
    if (!AuthSessionService.getInstance().isCurrentGeneration(requestGeneration)) {
      hilog.warn(0x0000, TAG, 'Skip CF guard for stale auth session generation=%{public}d url=%{public}s', requestGeneration, url);
      return resp;
    }
    const codeVal = resp['code'];
    const code: number = codeVal !== undefined && codeVal !== null ? codeVal as number : 0;
    const resultVal = resp['result'];
    const result: string = resultVal !== undefined && resultVal !== null ? resultVal as string : '';
    const headerVal = resp['header'];
    const headerObj: Object | undefined | null = headerVal !== undefined && headerVal !== null ? headerVal as Object : null;

    const urlPath: string = this.toUrlPath(url);
    const caller: string = guardOptions !== null && guardOptions.caller !== undefined && guardOptions.caller !== null
      ? guardOptions.caller as string
      : '';
    const silent: boolean = guardOptions !== null && guardOptions.silent === true;

    const detected: CfChallengeDetectResult = CfChallengeService.detectCfChallenge(result);
    const cfBodyHits: string[] = detected.hits;

    const contentType: string = this.getHeaderValue(headerObj, 'content-type');
    const contentTypeKnown: boolean = contentType.length > 0;
    const shouldTreatAsHtml: boolean = !contentTypeKnown || this.isHtmlContentType(contentType);

    let isCfBody: boolean = detected.isChallenge;
    if (contentTypeKnown && !shouldTreatAsHtml) {
      // 若响应类型明确为非 HTML：仅在更强特征命中时才认为是 CF challenge
      isCfBody = this.containsHit(cfBodyHits, 'cf_chl_opt') || this.containsHit(cfBodyHits, 'challenge-platform');
    }
    const isCfHeader: boolean = this.isCloudflareForbidden(headerObj);

    const cookieHeaderNow: string = this.cookieStore.getCookieHeader();
    const cookieHeaderLength: number = cookieHeaderNow.length;
    const clearance: string | null = this.cookieStore.getCookieValue('cf_clearance');
    const hasCfClearance: boolean = clearance !== null && clearance.length > 0;

    // Cloudflare 可能返回：
    // - 403/503（body 可能为空或含 challenge HTML）
    // - 200（body 直接是 challenge HTML）
    const shouldVerify: boolean = !skipCfGuard && this.isCfChallengeResponse(code, headerObj, isCfBody);

    const shouldLog: boolean = shouldVerify || code === 403 || code === 503 || isCfHeader || cfBodyHits.length > 0;
    if (shouldLog) {
      hilog.info(
        0x0000,
        TAG,
        'CFGuard urlPath=%{public}s status=%{public}d retry=%{public}d silent=%{public}s caller=%{public}s isCfHeader=%{public}s isCfBody=%{public}s hits=%{public}s hasCfClearance=%{public}s cookieHeaderLen=%{public}d triggerVerify=%{public}s',
        urlPath,
        code,
        retryAttempt,
        silent ? 'Y' : 'N',
        caller.length > 0 ? caller : '-',
        isCfHeader ? 'Y' : 'N',
        isCfBody ? 'Y' : 'N',
        cfBodyHits.length > 0 ? this.joinComma(cfBodyHits) : '-',
        hasCfClearance ? 'Y' : 'N',
        cookieHeaderLength,
        shouldVerify && !silent ? 'Y' : 'N'
      );
    }

    if (shouldVerify) {
      if (isCfBody) {
        // 备选：从响应体提取 Turnstile sitekey，供后续自动续期使用
        CfClearanceRefreshService.getInstance().extractAndUpdateSitekey(result);
      }
      if (silent) {
        // 静默模式：不弹出验证页，优先依赖自动续期恢复 cf_clearance（避免“永远静默失败”）
        CfClearanceRefreshService.getInstance().startIfPossible();
        hilog.warn(0x0000, TAG, 'CFGuard suppressed by silent mode, urlPath=%{public}s', urlPath);
        throw new Error('CF_CHALLENGE_SILENT');
      }

      // 非静默：准备走人工验证，避免与自动续期冲突
      CfClearanceRefreshService.getInstance().stop();

      const ctx: CfVerifyContext = {
        urlPath: urlPath,
        statusCode: code,
        isCfHeader: isCfHeader,
        isCfBody: isCfBody,
        cfBodyHits: cfBodyHits,
        hasCfClearance: hasCfClearance,
        cookieHeaderLength: cookieHeaderLength,
        silent: false,
        caller: caller
      };
      CfChallengeService.getInstance().setVerifyContextIfIdle(ctx);

      hilog.info(0x0000, TAG, 'CF forbidden detected(body=%{public}s, header=%{public}s), showing verify page...', isCfBody ? 'Y' : 'N', isCfHeader ? 'Y' : 'N');
      const ok: boolean = await CfChallengeService.getInstance().verify();
      if (ok) {
        const confirmOk: boolean = await CfChallengeService.getInstance().waitForCfClearanceReady();
        hilog.info(0x0000, TAG, 'CF verify completed, clearanceReady=%{public}s, urlPath=%{public}s', confirmOk ? 'Y' : 'N', urlPath);
        if (!confirmOk) {
          CfChallengeService.getInstance().enterCooldownNow('cf_clearance_confirm_failed');
          throw new Error('Cloudflare verification not effective');
        }
        // 验证成功后对原请求重试一次（跳过 guard，避免循环）
        const retryHeaders: Record<string, string> | null = this.refreshHeadersForRetry(headers);
        return await this.requestWithCfGuardDetailed(
          url,
          method,
          body,
          true,
          retryHeaders,
          connectTimeout,
          readTimeout,
          guardOptions,
          retryAttempt + 1
        );
      }
      throw new Error('Cloudflare verification failed or cancelled');
    }

    return resp;
  }

  private refreshHeadersForRetry(headers: Record<string, string> | null): Record<string, string> | null {
    if (headers === null) {
      return null;
    }

    const next: Record<string, string> = {};
    const keys: string[] = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      if (key.toLowerCase() === 'cookie') {
        continue;
      }
      next[key] = headers[key];
    }

    const cookieHeader: string = this.cookieStore.getCookieHeader();
    if (cookieHeader.length > 0) {
      next['Cookie'] = cookieHeader;
    }
    return next;
  }

  private isCloudflareForbidden(headerObj: Object | undefined | null): boolean {
    if (headerObj === undefined || headerObj === null) return false;
    try {
      const headers: Record<string, Object> = headerObj as Record<string, Object>;
      const keys: string[] = Object.keys(headers);
      for (let i = 0; i < keys.length; i++) {
        const k: string = keys[i];
        const lower: string = k.toLowerCase();
        if (lower === 'cf-ray' || lower === 'cf-mitigated' || lower === 'cf-cache-status') {
          return true;
        }
        if (lower === 'server') {
          const v: Object = headers[k];
          if (v !== undefined && v !== null) {
            const s: string = v.toString().toLowerCase();
            if (s.indexOf('cloudflare') >= 0) {
              return true;
            }
          }
        }
      }
    } catch (_) {
    }
    return false;
  }

  private isCfChallengeResponse(code: number, headerObj: Object | undefined | null, isCfBody: boolean): boolean {
    const server: string = this.getHeaderValue(headerObj, 'server').toLowerCase();
    if (server.indexOf('cloudflare') < 0) {
      return false;
    }

    const contentType: string = this.getHeaderValue(headerObj, 'content-type').toLowerCase();
    const contentTypeKnown: boolean = contentType.length > 0;
    const isHtml: boolean = !contentTypeKnown || this.isHtmlContentType(contentType);
    const cfMitigated: string = this.getHeaderValue(headerObj, 'cf-mitigated').toLowerCase();

    if (code === 403 || code === 503) {
      if (!isHtml) {
        return false;
      }
      if (cfMitigated.indexOf('challenge') >= 0) {
        return true;
      }
      return isCfBody;
    }

    if (code >= 200 && code < 300) {
      return isHtml && isCfBody;
    }

    return false;
  }

  private async requestWithCfGuard(url: string, method: http.RequestMethod, body: string | null, skipCfGuard: boolean): Promise<string> {
    const resp: Record<string, Object> = await this.requestWithCfGuardDetailed(url, method, body, skipCfGuard, null, null, null, null, 0);
    const codeVal = resp['code'];
    const code: number = codeVal !== undefined && codeVal !== null ? codeVal as number : 0;
    const resultVal = resp['result'];
    const result: string = resultVal !== undefined && resultVal !== null ? resultVal as string : '';

    if (this.isSuccessStatus(code)) {
      return result;
    }
    throw new Error(`HTTP ${code}`);
  }

  private encodeFormBody(params: Record<string, Object>): string {
    const keys: string[] = Object.keys(params);
    const parts: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const raw: Object = params[key];
      if (raw === null || raw === undefined) continue;

      if (Array.isArray(raw)) {
        const arr: Object[] = raw as Object[];
        for (let j = 0; j < arr.length; j++) {
          const item: Object = arr[j];
          if (item === null || item === undefined) continue;
          if (typeof item === 'string' || typeof item === 'number' || typeof item === 'boolean') {
            parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(item.toString())}`);
          }
        }
        continue;
      }

      if (typeof raw === 'string' || typeof raw === 'number' || typeof raw === 'boolean') {
        parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(raw.toString())}`);
      }
    }
    return parts.join('&');
  }

  /**
   * GET 请求
   */
  async get(
    path: string,
    params: Record<string, Object> | null = null,
    connectTimeoutMs: number | null = null,
    readTimeoutMs: number | null = null,
    guardOptions: CfGuardOptions | null = null
  ): Promise<string> {
    await this.cookieStore.init();
    let url: string = `${this.baseUrl}${path}`;

    // 拼接查询参数
    if (params !== null) {
      const keys: string[] = Object.keys(params);
      if (keys.length > 0) {
        const parts: string[] = [];
        for (let i = 0; i < keys.length; i++) {
          const key: string = keys[i];
          const raw: Object = params[key];

          if (raw === null || raw === undefined) {
            continue;
          }

          if (Array.isArray(raw)) {
            const arr: Object[] = raw as Object[];
            for (let j = 0; j < arr.length; j++) {
              const item: Object = arr[j];
              if (item === null || item === undefined) continue;
              if (typeof item === 'string' || typeof item === 'number' || typeof item === 'boolean') {
                parts.push(`${key}=${encodeURIComponent(item.toString())}`);
              }
            }
            continue;
          }

          if (typeof raw === 'string' || typeof raw === 'number' || typeof raw === 'boolean') {
            parts.push(`${key}=${encodeURIComponent(raw.toString())}`);
          }
        }
        if (parts.length > 0) {
          url = `${url}?${parts.join('&')}`;
        }
      }
    }

    hilog.info(0x0000, TAG, 'GET %{public}s', url);

    const resp: Record<string, Object> = await this.requestWithCfGuardDetailed(
      url,
      http.RequestMethod.GET,
      null,
      false,
      null,
      connectTimeoutMs,
      readTimeoutMs,
      guardOptions,
      0
    );
    const codeVal = resp['code'];
    const code: number = codeVal !== undefined && codeVal !== null ? codeVal as number : 0;
    const resultVal = resp['result'];
    const result: string = resultVal !== undefined && resultVal !== null ? resultVal as string : '';
    if (this.isSuccessStatus(code)) {
      return result;
    }
    throw new Error(`HTTP ${code}`);
  }

  /**
   * GET 文本（用于获取 HTML，如 data-preloaded）
   */
  async getText(
    path: string,
    params: Record<string, Object> | null = null,
    accept: string = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    readTimeoutMs: number = 60000,
    guardOptions: CfGuardOptions | null = null
  ): Promise<string> {
    await this.cookieStore.init();
    let url: string = `${this.baseUrl}${path}`;

    // 拼接查询参数（key 不编码，保持与 Discourse 参数兼容）
    if (params !== null) {
      const keys: string[] = Object.keys(params);
      if (keys.length > 0) {
        const parts: string[] = [];
        for (let i = 0; i < keys.length; i++) {
          const key: string = keys[i];
          const raw: Object = params[key];

          if (raw === null || raw === undefined) {
            continue;
          }

          if (Array.isArray(raw)) {
            const arr: Object[] = raw as Object[];
            for (let j = 0; j < arr.length; j++) {
              const item: Object = arr[j];
              if (item === null || item === undefined) continue;
              if (typeof item === 'string' || typeof item === 'number' || typeof item === 'boolean') {
                parts.push(`${key}=${encodeURIComponent(item.toString())}`);
              }
            }
            continue;
          }

          if (typeof raw === 'string' || typeof raw === 'number' || typeof raw === 'boolean') {
            parts.push(`${key}=${encodeURIComponent(raw.toString())}`);
          }
        }
        if (parts.length > 0) {
          url = `${url}?${parts.join('&')}`;
        }
      }
    }

    const headers: Record<string, string> = this.buildHeaders(accept, 'text/plain', null);
    const resp: Record<string, Object> = await this.requestWithCfGuardDetailed(
      url,
      http.RequestMethod.GET,
      null,
      false,
      headers,
      null,
      readTimeoutMs,
      guardOptions,
      0
    );
    const codeVal = resp['code'];
    const code: number = codeVal !== undefined && codeVal !== null ? codeVal as number : 0;
    const resultVal = resp['result'];
    const result: string = resultVal !== undefined && resultVal !== null ? resultVal as string : '';

    if (this.isSuccessStatus(code)) {
      return result;
    }
    throw new Error(`HTTP ${code}`);
  }

  /**
   * GET 二进制（用于图片下载等）
   * 说明：该方法不做 CF challenge 交互处理；若遇到 challenge/403，调用方应自行兜底（如改用复制链接/浏览器打开）。
   */
  async getBinaryByUrl(
    url: string,
    accept: string = '*/*',
    extraHeaders: Record<string, string> | null = null,
    connectTimeoutMs: number | null = null,
    readTimeoutMs: number | null = null
  ): Promise<HttpBinaryResponse> {
    await this.cookieStore.init();
    const full: string = url !== undefined && url !== null ? url.trim() : '';
    if (full.length === 0) {
      throw new Error('Empty url');
    }

    const headers: Record<string, string> = this.buildHeaders(accept, 'application/octet-stream', extraHeaders);
    const resp: Record<string, Object> = await this.requestOnceBinary(full, headers, connectTimeoutMs, readTimeoutMs);
    const codeVal = resp['code'];
    const code: number = codeVal !== undefined && codeVal !== null ? codeVal as number : 0;
    const headerVal = resp['header'];
    const headerObj: Object | null = headerVal !== undefined && headerVal !== null ? headerVal as Object : null;
    const resultVal = resp['result'];
    const bytes: ArrayBuffer = resultVal !== undefined && resultVal !== null ? resultVal as ArrayBuffer : new ArrayBuffer(0);

    if (this.isSuccessStatus(code)) {
      const out: HttpBinaryResponse = { code: code, bytes: bytes, header: headerObj };
      return out;
    }
    throw new Error(`HTTP ${code}`);
  }

  /**
   * POST 请求
   */
  async post(path: string, body: string = ''): Promise<string> {
    await this.cookieStore.init();
    await this.ensureCsrfToken();
    const url: string = `${this.baseUrl}${path}`;
    hilog.info(0x0000, TAG, 'POST %{public}s', url);
    const headers: Record<string, string> = this.buildHeaders('application/json', 'application/json', null);
    const resp: Record<string, Object> = await this.requestWithCsrfRetry(
      url,
      http.RequestMethod.POST,
      body,
      headers['Accept'],
      headers['Content-Type'],
      null,
      null,
      null,
      null
    );
    const codeVal = resp['code'];
    const code: number = codeVal !== undefined && codeVal !== null ? codeVal as number : 0;
    const resultVal = resp['result'];
    const result: string = resultVal !== undefined && resultVal !== null ? resultVal as string : '';
    if (this.isSuccessStatus(code)) {
      return result;
    }
    throw new Error(`HTTP ${code}`);
  }

  /**
   * POST 表单（用于 MessageBus 长轮询）
   */
  async postForm(
    path: string,
    form: Record<string, Object>,
    extraHeaders: Record<string, string> | null = null,
    readTimeoutMs: number = 60000
  ): Promise<Record<string, Object>> {
    await this.cookieStore.init();
    const url: string = `${this.baseUrl}${path}`;

    const body: string = this.encodeFormBody(form);
    return await this.requestWithCsrfRetry(
      url,
      http.RequestMethod.POST,
      body,
      'application/json',
      'application/x-www-form-urlencoded',
      extraHeaders,
      null,
      readTimeoutMs,
      null
    );
  }

  /**
   * POST 表单并返回文本响应
   */
  async postFormText(
    path: string,
    form: Record<string, Object>,
    extraHeaders: Record<string, string> | null = null,
    readTimeoutMs: number = 60000,
    connectTimeoutMs: number | null = null,
    guardOptions: CfGuardOptions | null = null
  ): Promise<string> {
    await this.cookieStore.init();
    const url: string = `${this.baseUrl}${path}`;
    const body: string = this.encodeFormBody(form);
    const resp: Record<string, Object> = await this.requestWithCsrfRetry(
      url,
      http.RequestMethod.POST,
      body,
      'application/json',
      'application/x-www-form-urlencoded',
      extraHeaders,
      connectTimeoutMs,
      readTimeoutMs,
      guardOptions
    );
    const codeVal = resp['code'];
    const code: number = codeVal !== undefined && codeVal !== null ? codeVal as number : 0;
    const resultVal = resp['result'];
    const result: string = resultVal !== undefined && resultVal !== null ? resultVal as string : '';
    if (this.isSuccessStatus(code)) {
      return result;
    }
    throw new Error(`HTTP ${code}`);
  }

  /**
   * PUT 请求
   */
  async put(path: string, body: string = ''): Promise<string> {
    await this.cookieStore.init();
    await this.ensureCsrfToken();
    const url: string = `${this.baseUrl}${path}`;
    hilog.info(0x0000, TAG, 'PUT %{public}s', url);
    const headers: Record<string, string> = this.buildHeaders('application/json', 'application/json', null);
    const resp: Record<string, Object> = await this.requestWithCsrfRetry(
      url,
      http.RequestMethod.PUT,
      body,
      headers['Accept'],
      headers['Content-Type'],
      null,
      null,
      null,
      null
    );
    const codeVal = resp['code'];
    const code: number = codeVal !== undefined && codeVal !== null ? codeVal as number : 0;
    const resultVal = resp['result'];
    const result: string = resultVal !== undefined && resultVal !== null ? resultVal as string : '';
    if (this.isSuccessStatus(code)) {
      return result;
    }
    throw new Error(`HTTP ${code}`);
  }

  /**
   * PUT 表单并返回文本响应
   */
  async putForm(
    path: string,
    form: Record<string, Object>,
    extraHeaders: Record<string, string> | null = null,
    readTimeoutMs: number = 60000,
    connectTimeoutMs: number | null = null,
    guardOptions: CfGuardOptions | null = null
  ): Promise<string> {
    await this.cookieStore.init();
    const url: string = `${this.baseUrl}${path}`;
    const body: string = this.encodeFormBody(form);
    const resp: Record<string, Object> = await this.requestWithCsrfRetry(
      url,
      http.RequestMethod.PUT,
      body,
      'application/json',
      'application/x-www-form-urlencoded',
      extraHeaders,
      connectTimeoutMs,
      readTimeoutMs,
      guardOptions
    );
    const codeVal = resp['code'];
    const code: number = codeVal !== undefined && codeVal !== null ? codeVal as number : 0;
    const resultVal = resp['result'];
    const result: string = resultVal !== undefined && resultVal !== null ? resultVal as string : '';
    if (this.isSuccessStatus(code)) {
      return result;
    }
    throw new Error(`HTTP ${code}`);
  }

  /**
   * DELETE 请求
   */
  async delete(path: string): Promise<string> {
    await this.cookieStore.init();
    await this.ensureCsrfToken();
    const url: string = `${this.baseUrl}${path}`;
    hilog.info(0x0000, TAG, 'DELETE %{public}s', url);
    const headers: Record<string, string> = this.buildHeaders('application/json', 'application/json', null);
    const resp: Record<string, Object> = await this.requestWithCsrfRetry(
      url,
      http.RequestMethod.DELETE,
      null,
      headers['Accept'],
      headers['Content-Type'],
      null,
      null,
      null,
      null
    );
    const codeVal = resp['code'];
    const code: number = codeVal !== undefined && codeVal !== null ? codeVal as number : 0;
    const resultVal = resp['result'];
    const result: string = resultVal !== undefined && resultVal !== null ? resultVal as string : '';
    if (this.isSuccessStatus(code)) {
      return result;
    }
    throw new Error(`HTTP ${code}`);
  }

  /**
   * DELETE 表单并返回文本响应
   */
  async deleteForm(
    path: string,
    form: Record<string, Object>,
    extraHeaders: Record<string, string> | null = null,
    readTimeoutMs: number = 60000,
    connectTimeoutMs: number | null = null,
    guardOptions: CfGuardOptions | null = null
  ): Promise<string> {
    await this.cookieStore.init();
    const url: string = `${this.baseUrl}${path}`;
    const body: string = this.encodeFormBody(form);
    const resp: Record<string, Object> = await this.requestWithCsrfRetry(
      url,
      http.RequestMethod.DELETE,
      body,
      'application/json',
      'application/x-www-form-urlencoded',
      extraHeaders,
      connectTimeoutMs,
      readTimeoutMs,
      guardOptions
    );
    const codeVal = resp['code'];
    const code: number = codeVal !== undefined && codeVal !== null ? codeVal as number : 0;
    const resultVal = resp['result'];
    const result: string = resultVal !== undefined && resultVal !== null ? resultVal as string : '';
    if (this.isSuccessStatus(code)) {
      return result;
    }
    throw new Error(`HTTP ${code}`);
  }
}
