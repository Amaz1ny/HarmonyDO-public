import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { CookieStore } from './CookieStore';
import { AppLogStore } from '../storage/AppLogStore';

const TAG: string = 'SimpleHttpClient';

export class SimpleHttpResponse {
  statusCode: number = 0;
  body: string = '';
  headers: Object | null = null;
}

export class SimpleHttpClient {
  static async get(
    url: string,
    accept: string = 'application/json,text/plain,*/*',
    extraHeaders: Record<string, string> | null = null,
    cookieUrl: string = '',
    connectTimeoutMs: number = 30000,
    readTimeoutMs: number = 30000
  ): Promise<SimpleHttpResponse> {
    return await SimpleHttpClient.request(
      url,
      http.RequestMethod.GET,
      null,
      accept,
      'application/json',
      extraHeaders,
      cookieUrl,
      connectTimeoutMs,
      readTimeoutMs
    );
  }

  static async postJson(
    url: string,
    body: string,
    extraHeaders: Record<string, string> | null = null,
    cookieUrl: string = '',
    connectTimeoutMs: number = 30000,
    readTimeoutMs: number = 30000
  ): Promise<SimpleHttpResponse> {
    return await SimpleHttpClient.request(
      url,
      http.RequestMethod.POST,
      body,
      'application/json',
      'application/json',
      extraHeaders,
      cookieUrl,
      connectTimeoutMs,
      readTimeoutMs
    );
  }

  private static async request(
    url: string,
    method: http.RequestMethod,
    body: string | null,
    accept: string,
    contentType: string,
    extraHeaders: Record<string, string> | null,
    cookieUrl: string,
    connectTimeoutMs: number,
    readTimeoutMs: number
  ): Promise<SimpleHttpResponse> {
    const httpRequest = http.createHttp();
    try {
      const headers: Record<string, string> = await SimpleHttpClient.buildHeaders(accept, contentType, extraHeaders, cookieUrl, url);
      const req: Record<string, Object> = {};
      req['method'] = method;
      req['header'] = headers;
      req['connectTimeout'] = connectTimeoutMs;
      req['readTimeout'] = readTimeoutMs;
      if (body !== null && body.length > 0) {
        req['extraData'] = body;
      }
      const response = await httpRequest.request(url, req);
      SimpleHttpClient.syncCookies(url, response.header as Object);
      const out: SimpleHttpResponse = new SimpleHttpResponse();
      out.statusCode = response.responseCode as number;
      out.body = response.result !== undefined && response.result !== null ? response.result as string : '';
      out.headers = response.header as Object;
      return out;
    } catch (err) {
      let errorText: string = '';
      try {
        errorText = JSON.stringify(err);
      } catch (_) {
        errorText = err !== null && err !== undefined ? err.toString() : '';
      }
      hilog.error(0x0000, TAG, 'Request failed url=%{public}s err=%{public}s', url, errorText);
      AppLogStore.getInstance().warn('HTTP', `request failed url=${url} err=${errorText}`);
      throw new Error(errorText.length > 0 ? errorText : 'Request failed');
    } finally {
      httpRequest.destroy();
    }
  }

  static getHeaderValue(headers: Object | null, targetName: string): string {
    if (headers === null || headers === undefined) {
      return '';
    }
    const obj: Record<string, Object> = headers as Record<string, Object>;
    const keys: string[] = Object.keys(obj);
    const lowerTarget: string = targetName.toLowerCase();
    for (let i: number = 0; i < keys.length; i++) {
      const key: string = keys[i];
      if (key.toLowerCase() !== lowerTarget) {
        continue;
      }
      const value: Object = obj[key];
      if (typeof value === 'string') {
        return value as string;
      }
      if (Array.isArray(value) && (value as Object[]).length > 0) {
        const item: Object = (value as Object[])[0];
        return item !== undefined && item !== null ? item.toString() : '';
      }
      return value !== undefined && value !== null ? value.toString() : '';
    }
    return '';
  }

  private static async buildHeaders(
    accept: string,
    contentType: string,
    extraHeaders: Record<string, string> | null,
    cookieUrl: string,
    requestUrl: string
  ): Promise<Record<string, string>> {
    const headers: Record<string, string> = {};
    headers['User-Agent'] = AppConstants.USER_AGENT;
    headers['Accept'] = accept;
    headers['Content-Type'] = contentType;

    const store: CookieStore = CookieStore.getInstance();
    await store.init();
    const targetCookieUrl: string = cookieUrl.trim().length > 0 ? cookieUrl : requestUrl;
    const cookieHeader: string = store.getCookieHeader(targetCookieUrl);
    if (cookieHeader.length > 0) {
      headers['Cookie'] = cookieHeader;
    }

    if (extraHeaders !== null) {
      const keys: string[] = Object.keys(extraHeaders);
      for (let i: number = 0; i < keys.length; i++) {
        const key: string = keys[i];
        const value: string = extraHeaders[key];
        if (value !== undefined && value !== null && value.length > 0) {
          headers[key] = value;
        }
      }
    }
    return headers;
  }

  private static syncCookies(requestUrl: string, headerObj: Object | null): void {
    if (headerObj === null || headerObj === undefined) {
      return;
    }
    const headers: Record<string, Object> = headerObj as Record<string, Object>;
    const keys: string[] = Object.keys(headers);
    const values: string[] = [];
    for (let i: number = 0; i < keys.length; i++) {
      const key: string = keys[i];
      if (key.toLowerCase() !== 'set-cookie') {
        continue;
      }
      const value: Object = headers[key];
      if (typeof value === 'string') {
        values.push(value as string);
      } else if (Array.isArray(value)) {
        const arr: Object[] = value as Object[];
        for (let j: number = 0; j < arr.length; j++) {
          const item: Object = arr[j];
          if (typeof item === 'string') {
            values.push(item as string);
          }
        }
      }
    }
    if (values.length > 0) {
      CookieStore.getInstance().ingestSetCookieHeaders(values, requestUrl);
    }
  }
}
