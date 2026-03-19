import { AppConstants } from '../../common/constants/AppConstants';
import { AppLogStore } from '../storage/AppLogStore';
import { SimpleHttpClient } from './SimpleHttpClient';

const TAG_UPDATE: string = 'UpdateService';

export class UpdateCheckResult {
  currentVersion: string = '';
  latestVersion: string = '';
  releaseName: string = '';
  releaseUrl: string = '';
  body: string = '';
  publishedAt: string = '';
  hasUpdate: boolean = false;
}

export class UpdateService {
  async getCurrentVersion(): Promise<string> {
    return AppConstants.APP_VERSION;
  }

  async checkForUpdate(): Promise<UpdateCheckResult> {
    AppLogStore.getInstance().info(TAG_UPDATE, 'check for update');
    const response = await SimpleHttpClient.get(AppConstants.REPOSITORY_RELEASE_API_URL, 'application/json');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw new Error(`HTTP ${response.statusCode}`);
    }
    const json: Record<string, Object> = JSON.parse(response.body) as Record<string, Object>;
    const result: UpdateCheckResult = new UpdateCheckResult();
    result.currentVersion = AppConstants.APP_VERSION;
    const tagNameVal = json['tag_name'];
    const releaseNameVal = json['name'];
    const releaseUrlVal = json['html_url'];
    const bodyVal = json['body'];
    const publishedAtVal = json['published_at'];
    result.latestVersion = tagNameVal !== undefined && tagNameVal !== null ? tagNameVal.toString() : '';
    result.releaseName = releaseNameVal !== undefined && releaseNameVal !== null ? releaseNameVal.toString() : '';
    result.releaseUrl = releaseUrlVal !== undefined && releaseUrlVal !== null ? releaseUrlVal.toString() : AppConstants.REPOSITORY_RELEASES_URL;
    result.body = bodyVal !== undefined && bodyVal !== null ? bodyVal.toString() : '';
    result.publishedAt = publishedAtVal !== undefined && publishedAtVal !== null ? publishedAtVal.toString() : '';
    result.hasUpdate = this.compareVersion(result.latestVersion, result.currentVersion) > 0;
    AppLogStore.getInstance().info(TAG_UPDATE, `update checked current=${result.currentVersion} latest=${result.latestVersion}`);
    return result;
  }

  private compareVersion(left: string, right: string): number {
    const normalizedLeft: string = this.normalizeVersion(left);
    const normalizedRight: string = this.normalizeVersion(right);
    const leftSegs: string[] = normalizedLeft.split('.');
    const rightSegs: string[] = normalizedRight.split('.');
    const length: number = Math.max(leftSegs.length, rightSegs.length);
    for (let i: number = 0; i < length; i++) {
      const leftNum: number = i < leftSegs.length ? Number(leftSegs[i]) : 0;
      const rightNum: number = i < rightSegs.length ? Number(rightSegs[i]) : 0;
      if (leftNum > rightNum) return 1;
      if (leftNum < rightNum) return -1;
    }
    return 0;
  }

  private normalizeVersion(version: string): string {
    const trimmed: string = version.trim();
    if (trimmed.startsWith('v') || trimmed.startsWith('V')) {
      return trimmed.substring(1);
    }
    return trimmed;
  }
}
