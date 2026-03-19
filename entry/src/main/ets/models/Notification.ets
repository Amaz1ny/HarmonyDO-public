import { TimeUtils } from '../common/utils/TimeUtils';
import { UrlUtils } from '../common/utils/UrlUtils';

/**
 * Discourse 通知类型
 */
export class NotificationType {
  static readonly MENTIONED: number = 1;
  static readonly REPLIED: number = 2;
  static readonly QUOTED: number = 3;
  static readonly EDITED: number = 4;
  static readonly LIKED: number = 5;
  static readonly PRIVATE_MESSAGE: number = 6;
  static readonly POSTED: number = 9;
  static readonly LINKED: number = 11;
  static readonly GRANTED_BADGE: number = 12;
  static readonly LIKED_CONSOLIDATED: number = 19;
  static readonly BOOKMARK_REMINDER: number = 24;
  static readonly REACTION: number = 25;
  static readonly FOLLOWING: number = 800;
  static readonly FOLLOWING_CREATED_TOPIC: number = 801;
  static readonly FOLLOWING_REPLIED: number = 802;

  /**
   * 获取通知类型标签
   */
  static getLabel(typeId: number): string {
    if (typeId === 1) return '提及';
    if (typeId === 2) return '回复';
    if (typeId === 3) return '引用';
    if (typeId === 4) return '编辑';
    if (typeId === 5) return '点赞';
    if (typeId === 6) return '私信';
    if (typeId === 9) return '发帖';
    if (typeId === 11) return '链接';
    if (typeId === 12) return '获得徽章';
    if (typeId === 19) return '点赞汇总';
    if (typeId === 24) return '书签提醒';
    if (typeId === 25) return '反应';
    if (typeId === 800) return '关注';
    if (typeId === 801) return '关注的用户创建了话题';
    if (typeId === 802) return '关注的用户回复了';
    return '通知';
  }
}

/**
 * 通知详细数据
 */
export class NotificationData {
  displayUsername: string | null = null;
  topicTitle: string | null = null;
  badgeName: string | null = null;
  badgeId: number | null = null;
  badgeSlug: string | null = null;
  count: number | null = null;
  username: string | null = null;
  username2: string | null = null;
  originalUsername: string | null = null;
  avatarTemplate: string | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): NotificationData {
    const data = new NotificationData();
    const displayVal = json['display_username'];
    data.displayUsername = displayVal !== undefined && displayVal !== null ? displayVal as string : null;

    const titleVal = json['topic_title'];
    data.topicTitle = titleVal !== undefined && titleVal !== null ? titleVal as string : null;

    const badgeNameVal = json['badge_name'];
    data.badgeName = badgeNameVal !== undefined && badgeNameVal !== null ? badgeNameVal as string : null;

    const badgeIdVal = json['badge_id'];
    data.badgeId = badgeIdVal !== undefined && badgeIdVal !== null ? badgeIdVal as number : null;

    const badgeSlugVal = json['badge_slug'];
    data.badgeSlug = badgeSlugVal !== undefined && badgeSlugVal !== null ? badgeSlugVal as string : null;

    const countVal = json['count'];
    data.count = countVal !== undefined && countVal !== null ? countVal as number : null;

    const usernameVal = json['username'];
    data.username = usernameVal !== undefined && usernameVal !== null ? usernameVal as string : null;

    const username2Val = json['username2'];
    data.username2 = username2Val !== undefined && username2Val !== null ? username2Val as string : null;

    const originalUsernameVal = json['original_username'];
    data.originalUsername = originalUsernameVal !== undefined && originalUsernameVal !== null
      ? originalUsernameVal as string : null;

    const avatarVal = json['acting_user_avatar_template'];
    if (avatarVal !== undefined && avatarVal !== null) {
      data.avatarTemplate = avatarVal as string;
    } else {
      const avatarVal2 = json['avatar_template'];
      data.avatarTemplate = avatarVal2 !== undefined && avatarVal2 !== null ? avatarVal2 as string : null;
    }

    return data;
  }
}

/**
 * Discourse 通知模型
 */
export class DiscourseNotification {
  id: number = 0;
  userId: number = 0;
  notificationTypeId: number = 0;
  read: boolean = false;
  highPriority: boolean = false;
  createdAt: Date | null = null;
  postNumber: number | null = null;
  topicId: number | null = null;
  slug: string | null = null;
  data: NotificationData = new NotificationData();
  fancyTitle: string | null = null;
  actingUserAvatarTemplate: string | null = null;

  constructor() {
  }

  /**
   * 获取通知标题
   */
  get title(): string {
    const displayName: string = this.data.displayUsername !== null
      ? this.data.displayUsername
      : (this.data.originalUsername !== null
        ? this.data.originalUsername
        : (this.data.username !== null ? this.data.username : ''));

    if (this.notificationTypeId === NotificationType.GRANTED_BADGE) {
      return this.data.badgeName !== null ? `获得了 '${this.data.badgeName}'` : '获得徽章';
    }
    if (this.notificationTypeId === NotificationType.FOLLOWING) {
      return displayName.length > 0 ? `${displayName} 开始关注你` : '关注';
    }
    if (this.notificationTypeId === NotificationType.LIKED_CONSOLIDATED) {
      const count: number = this.data.count !== null ? this.data.count as number : 0;
      if (displayName.length > 0) {
        return `${displayName} 点赞了你的 ${count} 个帖子`;
      }
      return `${count} 人赞了你的帖子`;
    }

    if (this.data.topicTitle !== null && this.data.topicTitle.length > 0) {
      return this.data.topicTitle;
    }
    if (this.fancyTitle !== null && this.fancyTitle.length > 0) {
      return this.fancyTitle;
    }
    return NotificationType.getLabel(this.notificationTypeId);
  }

  /**
   * 获取通知描述
   */
  get description(): string {
    const username: string = this.data.displayUsername !== null
      ? this.data.displayUsername
      : (this.data.originalUsername !== null
        ? this.data.originalUsername
        : (this.data.username !== null ? this.data.username : ''));

    if (this.notificationTypeId === NotificationType.MENTIONED) return `${username} 在帖子中提及了你`;
    if (this.notificationTypeId === NotificationType.REPLIED) return `${username} 回复了你的帖子`;
    if (this.notificationTypeId === NotificationType.LIKED) return `${username} 赞了你的帖子`;
    if (this.notificationTypeId === NotificationType.QUOTED) return `${username} 引用了你的帖子`;
    if (this.notificationTypeId === NotificationType.POSTED) return `${username} 发布了新帖子`;
    if (this.notificationTypeId === NotificationType.PRIVATE_MESSAGE) return `${username} 发送了私信`;
    if (this.notificationTypeId === NotificationType.LINKED) return `${username} 链接了你的帖子`;
    if (this.notificationTypeId === NotificationType.GRANTED_BADGE) {
      return this.data.badgeName !== null ? `获得了 '${this.data.badgeName}'` : '获得了新徽章';
    }
    return NotificationType.getLabel(this.notificationTypeId);
  }

  get username(): string {
    if (this.data.displayUsername !== null && this.data.displayUsername.length > 0) {
      return this.data.displayUsername;
    }
    if (this.data.username !== null && this.data.username.length > 0) {
      return this.data.username;
    }
    if (this.data.originalUsername !== null && this.data.originalUsername.length > 0) {
      return this.data.originalUsername;
    }
    return '';
  }

  getAvatarUrl(size: number = 96): string {
    const template: string = this.actingUserAvatarTemplate !== null && (this.actingUserAvatarTemplate as string).length > 0
      ? this.actingUserAvatarTemplate as string
      : (this.data.avatarTemplate !== null ? this.data.avatarTemplate as string : '');
    if (template.length === 0) {
      return '';
    }
    return UrlUtils.resolveUrl(template.replace('{size}', size.toString()));
  }

  static fromJson(json: Record<string, Object>): DiscourseNotification {
    const notification = new DiscourseNotification();

    const idVal = json['id'];
    notification.id = idVal !== undefined && idVal !== null ? idVal as number : 0;

    const userIdVal = json['user_id'];
    notification.userId = userIdVal !== undefined && userIdVal !== null ? userIdVal as number : 0;

    const typeVal = json['notification_type'];
    notification.notificationTypeId = typeVal !== undefined && typeVal !== null ? typeVal as number : 0;

    const readVal = json['read'];
    notification.read = readVal !== undefined && readVal !== null ? readVal as boolean : false;

    const highVal = json['high_priority'];
    notification.highPriority = highVal !== undefined && highVal !== null ? highVal as boolean : false;

    const createdVal = json['created_at'];
    notification.createdAt = createdVal !== undefined && createdVal !== null
      ? TimeUtils.parseUtcTime(createdVal as string) : null;

    const postNumVal = json['post_number'];
    notification.postNumber = postNumVal !== undefined && postNumVal !== null ? postNumVal as number : null;

    const topicIdVal = json['topic_id'];
    notification.topicId = topicIdVal !== undefined && topicIdVal !== null ? topicIdVal as number : null;

    const slugVal = json['slug'];
    notification.slug = slugVal !== undefined && slugVal !== null ? slugVal as string : null;

    const dataVal = json['data'];
    if (dataVal !== undefined && dataVal !== null) {
      notification.data = NotificationData.fromJson(dataVal as Record<string, Object>);
    }

    const fancyVal = json['fancy_title'];
    notification.fancyTitle = fancyVal !== undefined && fancyVal !== null ? fancyVal as string : null;

    const actingAvatarVal = json['acting_user_avatar_template'];
    notification.actingUserAvatarTemplate = actingAvatarVal !== undefined && actingAvatarVal !== null
      ? actingAvatarVal as string : null;

    return notification;
  }
}

export class NotificationListResponse {
  notifications: DiscourseNotification[] = [];
  totalRowsNotifications: number = 0;
  seenNotificationId: number = 0;
  loadMoreNotifications: string | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): NotificationListResponse {
    const response = new NotificationListResponse();

    const rowsVal = json['total_rows_notifications'];
    response.totalRowsNotifications = rowsVal !== undefined && rowsVal !== null ? Number(rowsVal.toString()) : 0;

    const seenVal = json['seen_notification_id'];
    response.seenNotificationId = seenVal !== undefined && seenVal !== null ? Number(seenVal.toString()) : 0;

    const moreVal = json['load_more_notifications'];
    response.loadMoreNotifications = moreVal !== undefined && moreVal !== null ? moreVal as string : null;

    const notificationsVal = json['notifications'];
    if (notificationsVal !== undefined && notificationsVal !== null && Array.isArray(notificationsVal)) {
      const arr: Object[] = notificationsVal as Object[];
      const list: DiscourseNotification[] = [];
      for (let i = 0; i < arr.length; i++) {
        list.push(DiscourseNotification.fromJson(arr[i] as Record<string, Object>));
      }
      response.notifications = list;
    }

    return response;
  }
}
