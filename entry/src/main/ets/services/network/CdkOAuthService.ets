import { OAuthAuthorizationContext, CdkUserInfo } from '../../models/Metaverse';
import { AppLogStore } from '../storage/AppLogStore';
import { SimpleHttpClient } from './SimpleHttpClient';

const TAG_CDK: string = 'CdkOAuthService';

export class CdkOAuthService {
  private static readonly BASE_URL: string = 'https://cdk.linux.do';

  async prepareAuthorization(): Promise<OAuthAuthorizationContext | null> {
    const loginResponse = await SimpleHttpClient.get(`${CdkOAuthService.BASE_URL}/api/v1/oauth/login`, 'application/json');
    if (loginResponse.statusCode < 200 || loginResponse.statusCode >= 300) {
      throw new Error(`HTTP ${loginResponse.statusCode}`);
    }
    const loginJson: Record<string, Object> = JSON.parse(loginResponse.body) as Record<string, Object>;
    const authUrlVal = loginJson['data'];
    const authUrl: string = authUrlVal !== undefined && authUrlVal !== null ? authUrlVal.toString() : '';
    if (authUrl.length === 0) {
      return null;
    }

    const authResponse = await SimpleHttpClient.get(authUrl, 'text/html,application/xhtml+xml,*/*', null, authUrl);
    const approveUrl: string = this.extractApproveUrl(authResponse.body);
    if (approveUrl.length === 0) {
      return null;
    }

    const context: OAuthAuthorizationContext = new OAuthAuthorizationContext();
    context.serviceKey = 'cdk';
    context.serviceName = 'CDK';
    context.approveUrl = approveUrl;
    return context;
  }

  async approveAuthorization(context: OAuthAuthorizationContext): Promise<boolean> {
    const response = await SimpleHttpClient.get(context.approveUrl, '*/*', null, context.approveUrl);
    const location: string = SimpleHttpClient.getHeaderValue(response.headers, 'location');
    const callbackUrl: string = location.length > 0 ? location : this.extractCallbackUrl(response.body);
    if (callbackUrl.length === 0) {
      return false;
    }
    const params: Record<string, string> = this.extractCodeAndState(callbackUrl);
    if (params['code'].length === 0 || params['state'].length === 0) {
      return false;
    }
    const payload: Record<string, Object> = {};
    payload['code'] = params['code'];
    payload['state'] = params['state'];
    const callbackResponse = await SimpleHttpClient.postJson(
      `${CdkOAuthService.BASE_URL}/api/v1/oauth/callback`,
      JSON.stringify(payload),
      null,
      CdkOAuthService.BASE_URL
    );
    const ok: boolean = callbackResponse.statusCode >= 200 && callbackResponse.statusCode < 300;
    AppLogStore.getInstance().info(TAG_CDK, ok ? 'authorize success' : `authorize failed code=${callbackResponse.statusCode}`);
    return ok;
  }

  async logout(): Promise<void> {
    await SimpleHttpClient.get(`${CdkOAuthService.BASE_URL}/api/v1/oauth/logout`, 'application/json', null, CdkOAuthService.BASE_URL);
    AppLogStore.getInstance().info(TAG_CDK, 'logout');
  }

  async getUserInfo(): Promise<CdkUserInfo | null> {
    const response = await SimpleHttpClient.get(
      `${CdkOAuthService.BASE_URL}/api/v1/oauth/user-info`,
      'application/json',
      null,
      CdkOAuthService.BASE_URL
    );
    if (response.statusCode === 401 || response.statusCode === 403) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw new Error(`HTTP ${response.statusCode}`);
    }
    const json: Record<string, Object> = JSON.parse(response.body) as Record<string, Object>;
    const dataVal = json['data'];
    if (dataVal === undefined || dataVal === null || typeof dataVal !== 'object') {
      return null;
    }
    return CdkUserInfo.fromJson(dataVal as Record<string, Object>);
  }

  private extractApproveUrl(html: string): string {
    const match: RegExpExecArray | null = /<a[^>]*href=["']([^"']*\/oauth2\/approve\/[^"']*)["'][^>]*>/i.exec(html);
    if (match === null) {
      return '';
    }
    const href: string = match[1];
    if (href.startsWith('http')) {
      return href;
    }
    return `https://connect.linux.do${href}`;
  }

  private extractCallbackUrl(html: string): string {
    const match: RegExpExecArray | null = /(https:\/\/cdk\.linux\.do[^"'\\s>]+code=[^"'\\s>]+state=[^"'\\s>]+)/i.exec(html);
    return match !== null ? match[1] : '';
  }

  private extractCodeAndState(callbackUrl: string): Record<string, string> {
    const params: Record<string, string> = {};
    params['code'] = '';
    params['state'] = '';
    try {
      const queryStart: number = callbackUrl.indexOf('?');
      if (queryStart < 0) {
        return params;
      }
      const query: string = callbackUrl.substring(queryStart + 1);
      const parts: string[] = query.split('&');
      for (let i: number = 0; i < parts.length; i++) {
        const pair: string = parts[i];
        const eq: number = pair.indexOf('=');
        const key: string = eq >= 0 ? pair.substring(0, eq) : pair;
        const value: string = eq >= 0 ? pair.substring(eq + 1) : '';
        if (key === 'code') {
          params['code'] = decodeURIComponent(value);
        } else if (key === 'state') {
          params['state'] = decodeURIComponent(value);
        }
      }
    } catch (_) {
    }
    return params;
  }
}
