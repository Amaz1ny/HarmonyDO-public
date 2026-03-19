import { AppConstants } from '../constants/AppConstants';

/**
 * 分享链接工具类
 *
 * 对齐安卓(FluxDO)规则：
 * - 匿名分享：不附带 `?u=` 参数
 * - 登录分享：可附带 `?u=username`
 */
export class ShareUtils {
  static buildShareUrl(path: string, username: string = '', anonymousShare: boolean = true): string {
    const p: string = path !== undefined && path !== null ? path : '';
    const base: string = `${AppConstants.BASE_URL}${p}`;

    if (anonymousShare || username.trim().length === 0) {
      return base;
    }

    // path 默认无 query；若后续有 query，则使用 & 追加
    const sep: string = base.indexOf('?') >= 0 ? '&' : '?';
    return `${base}${sep}u=${encodeURIComponent(username.trim())}`;
  }
}

