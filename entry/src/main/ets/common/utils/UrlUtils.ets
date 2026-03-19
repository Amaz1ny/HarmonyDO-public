import { AppConstants } from '../constants/AppConstants';
import { PreloadedDataService } from '../../services/messagebus/PreloadedDataService';

/**
 * URL 工具类
 */
export class UrlUtils {
  private static rewriteS3Cdn(url: string): string {
    const preloaded: PreloadedDataService = PreloadedDataService.getInstance();
    const s3CdnUrl: string | null = preloaded.getS3CdnUrl();
    const s3BaseUrl: string | null = preloaded.getS3BaseUrl();
    if (s3CdnUrl === null || s3BaseUrl === null) return url;

    const s3BaseFull: string = s3BaseUrl.startsWith('//') ? `https:${s3BaseUrl}` : s3BaseUrl;
    if (url.startsWith(s3BaseFull)) {
      return (s3CdnUrl as string) + url.substring(s3BaseFull.length);
    }
    return url;
  }

  /**
   * 解析相对 URL 为完整 URL
   */
  static resolveUrl(url: string | null): string {
    if (url === null || url.length === 0) {
      return '';
    }
    if (url.startsWith('http')) {
      return url;
    }
    if (url.startsWith('//')) {
      const fullUrl: string = `https:${url}`;
      return UrlUtils.rewriteS3Cdn(fullUrl);
    }

    const preloaded: PreloadedDataService = PreloadedDataService.getInstance();
    const cdnUrl: string | null = preloaded.getCdnUrl();
    const base: string = cdnUrl !== null ? (cdnUrl as string) : AppConstants.BASE_URL;
    if (url.startsWith('/')) {
      return `${base}${url}`;
    }
    return `${base}/${url}`;
  }

  /**
   * 获取头像 URL
   * 替换 {size} 占位符并解析相对路径
   */
  static getAvatarUrl(template: string | null, size: number = 120): string {
    if (template === null || template.length === 0) {
      return '';
    }
    const url: string = template.replace('{size}', size.toString());
    return UrlUtils.resolveUrl(url);
  }
}
