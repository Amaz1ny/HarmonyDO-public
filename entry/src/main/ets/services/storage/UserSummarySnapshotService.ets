import { PreferencesUtil } from './PreferencesUtil';
import { UserSummary } from '../../models/User';

const PROFILE_SUMMARY_SNAPSHOT_PREFIX: string = 'profile_summary_snapshot_v1_';

export class UserSummarySnapshotService {
  private static getSnapshotKey(username: string): string {
    return `${PROFILE_SUMMARY_SNAPSHOT_PREFIX}${username.trim().toLowerCase()}`;
  }

  private static serialize(summary: UserSummary): string {
    const userSummary: Record<string, Object> = {};
    userSummary['days_visited'] = summary.daysVisited;
    userSummary['posts_read_count'] = summary.postsReadCount;
    userSummary['likes_received'] = summary.likesReceived;
    userSummary['likes_given'] = summary.likesGiven;
    userSummary['topic_count'] = summary.topicCount;
    userSummary['post_count'] = summary.postCount;
    userSummary['time_read'] = summary.timeRead;
    userSummary['bookmark_count'] = summary.bookmarkCount;

    const payload: Record<string, Object> = {};
    payload['user_summary'] = userSummary as Object;
    return JSON.stringify(payload);
  }

  private static parse(raw: string): UserSummary | null {
    if (raw.trim().length === 0) {
      return null;
    }
    try {
      const parsed: Object = JSON.parse(raw) as Object;
      if (parsed instanceof Array) {
        return null;
      }
      return UserSummary.fromJson(parsed as Record<string, Object>);
    } catch (_) {
      return null;
    }
  }

  static async load(username: string): Promise<UserSummary | null> {
    const normalizedUsername: string = username.trim();
    if (normalizedUsername.length === 0) {
      return null;
    }
    await PreferencesUtil.ensureInit();
    const raw: string = await PreferencesUtil.getString(UserSummarySnapshotService.getSnapshotKey(normalizedUsername), '');
    return UserSummarySnapshotService.parse(raw);
  }

  static async save(username: string, summary: UserSummary): Promise<void> {
    const normalizedUsername: string = username.trim();
    if (normalizedUsername.length === 0) {
      return;
    }
    await PreferencesUtil.ensureInit();
    await PreferencesUtil.putString(
      UserSummarySnapshotService.getSnapshotKey(normalizedUsername),
      UserSummarySnapshotService.serialize(summary)
    );
  }
}
