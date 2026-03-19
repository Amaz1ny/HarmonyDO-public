import { TimeUtils } from '../common/utils/TimeUtils';
import { UrlUtils } from '../common/utils/UrlUtils';

/**
 * 徽章模型
 */
export class Badge {
  id: number = 0;
  name: string = '';
  description: string = '';
  badgeTypeId: number = 3; // 1=Gold, 2=Silver, 3=Bronze
  imageUrl: string | null = null;
  icon: string | null = null;
  grantCount: number = 0;
  enabled: boolean = true;
  allowTitle: boolean = false;
  multipleGrant: boolean = false;
  longDescription: string | null = null;
  slug: string = '';
  badgeGroupingId: number | null = null;

  constructor() {
  }

  /**
   * 获取徽章类型名称
   */
  get badgeTypeName(): string {
    if (this.badgeTypeId === 1) return '金牌';
    if (this.badgeTypeId === 2) return '银牌';
    return '铜牌';
  }

  static fromJson(json: Record<string, Object>): Badge {
    const badge = new Badge();

    const idVal = json['id'];
    badge.id = idVal !== undefined && idVal !== null ? idVal as number : 0;

    const nameVal = json['name'];
    badge.name = nameVal !== undefined && nameVal !== null ? nameVal as string : '';

    const descVal = json['description'];
    badge.description = descVal !== undefined && descVal !== null ? descVal as string : '';

    const typeVal = json['badge_type_id'];
    badge.badgeTypeId = typeVal !== undefined && typeVal !== null ? typeVal as number : 3;

    const imgVal = json['image_url'];
    badge.imageUrl = imgVal !== undefined && imgVal !== null ? imgVal as string : null;

    const iconVal = json['icon'];
    badge.icon = iconVal !== undefined && iconVal !== null ? iconVal as string : null;

    const grantVal = json['grant_count'];
    badge.grantCount = grantVal !== undefined && grantVal !== null ? grantVal as number : 0;

    const enabledVal = json['enabled'];
    badge.enabled = enabledVal !== undefined && enabledVal !== null ? enabledVal as boolean : true;

    const allowVal = json['allow_title'];
    badge.allowTitle = allowVal !== undefined && allowVal !== null ? allowVal as boolean : false;

    const multiVal = json['multiple_grant'];
    badge.multipleGrant = multiVal !== undefined && multiVal !== null ? multiVal as boolean : false;

    const longVal = json['long_description'];
    badge.longDescription = longVal !== undefined && longVal !== null ? longVal as string : null;

    const slugVal = json['slug'];
    badge.slug = slugVal !== undefined && slugVal !== null ? slugVal as string : '';

    const groupVal = json['badge_grouping_id'];
    badge.badgeGroupingId = groupVal !== undefined && groupVal !== null ? groupVal as number : null;

    return badge;
  }
}

/**
 * 帖子已授予徽章（post.badges_granted）
 *
 * 说明：Discourse 在 topic/post JSON 里会给出简化 badge 字段，用于在楼层头部快速展示图标。
 */
export class GrantedBadge {
  id: number = 0;
  name: string = '';
  icon: string | null = null;
  imageUrl: string | null = null;
  slug: string = '';
  badgeTypeId: number = 3;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): GrantedBadge {
    const badge = new GrantedBadge();

    const idVal = json['id'];
    badge.id = idVal !== undefined && idVal !== null ? idVal as number : 0;

    const nameVal = json['name'];
    badge.name = nameVal !== undefined && nameVal !== null ? nameVal as string : '';

    const iconVal = json['icon'];
    badge.icon = iconVal !== undefined && iconVal !== null ? iconVal as string : null;

    const imgVal = json['image_url'];
    badge.imageUrl = imgVal !== undefined && imgVal !== null ? imgVal as string : null;

    const slugVal = json['slug'];
    badge.slug = slugVal !== undefined && slugVal !== null ? slugVal as string : '';

    const typeVal = json['badge_type_id'];
    badge.badgeTypeId = typeVal !== undefined && typeVal !== null ? typeVal as number : 3;

    return badge;
  }
}

/**
 * 用户徽章模型
 */
export class UserBadge {
  id: number = 0;
  badgeId: number = 0;
  userId: number = 0;
  grantedAt: Date | null = null;
  topicId: number | null = null;
  topicTitle: string | null = null;
  postNumber: number | null = null;
  username: string | null = null;
  count: number = 1;
  badge: Badge | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): UserBadge {
    const out = new UserBadge();

    const idVal = json['id'];
    out.id = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;

    const badgeIdVal = json['badge_id'];
    out.badgeId = badgeIdVal !== undefined && badgeIdVal !== null ? Number(badgeIdVal.toString()) : 0;

    const userIdVal = json['user_id'];
    out.userId = userIdVal !== undefined && userIdVal !== null ? Number(userIdVal.toString()) : 0;

    const grantedVal = json['granted_at'];
    out.grantedAt = grantedVal !== undefined && grantedVal !== null
      ? TimeUtils.parseUtcTime(grantedVal as string) : null;

    const topicIdVal = json['topic_id'];
    out.topicId = topicIdVal !== undefined && topicIdVal !== null ? Number(topicIdVal.toString()) : null;

    const topicTitleVal = json['topic_title'];
    out.topicTitle = topicTitleVal !== undefined && topicTitleVal !== null ? topicTitleVal as string : null;

    const postNumVal = json['post_number'];
    out.postNumber = postNumVal !== undefined && postNumVal !== null ? Number(postNumVal.toString()) : null;

    const usernameVal = json['username'];
    out.username = usernameVal !== undefined && usernameVal !== null ? usernameVal as string : null;

    const countVal = json['count'];
    out.count = countVal !== undefined && countVal !== null ? Number(countVal.toString()) : 1;

    const badgeVal = json['badge'];
    out.badge = badgeVal !== undefined && badgeVal !== null ? Badge.fromJson(badgeVal as Record<string, Object>) : null;

    return out;
  }
}

/**
 * 徽章详情页中的用户信息
 */
export class BadgeUser {
  id: number = 0;
  username: string = '';
  name: string | null = null;
  avatarTemplate: string = '';
  flairName: string | null = null;
  flairUrl: string | null = null;
  flairGroupId: number | null = null;
  trustLevel: number = 0;
  animatedAvatar: string | null = null;
  admin: boolean = false;
  moderator: boolean = false;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): BadgeUser {
    const user: BadgeUser = new BadgeUser();

    const idVal = json['id'];
    user.id = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;

    const usernameVal = json['username'];
    user.username = usernameVal !== undefined && usernameVal !== null ? usernameVal.toString() : '';

    const nameVal = json['name'];
    user.name = nameVal !== undefined && nameVal !== null ? nameVal.toString() : null;

    const avatarVal = json['avatar_template'];
    user.avatarTemplate = avatarVal !== undefined && avatarVal !== null ? avatarVal.toString() : '';

    const flairNameVal = json['flair_name'];
    user.flairName = flairNameVal !== undefined && flairNameVal !== null ? flairNameVal.toString() : null;

    const flairUrlVal = json['flair_url'];
    user.flairUrl = flairUrlVal !== undefined && flairUrlVal !== null ? flairUrlVal.toString() : null;

    const flairGroupIdVal = json['flair_group_id'];
    user.flairGroupId = flairGroupIdVal !== undefined && flairGroupIdVal !== null
      ? Number(flairGroupIdVal.toString())
      : null;

    const trustLevelVal = json['trust_level'];
    user.trustLevel = trustLevelVal !== undefined && trustLevelVal !== null ? Number(trustLevelVal.toString()) : 0;

    const animatedAvatarVal = json['animated_avatar'];
    user.animatedAvatar = animatedAvatarVal !== undefined && animatedAvatarVal !== null
      ? animatedAvatarVal.toString()
      : null;

    const adminVal = json['admin'];
    user.admin = adminVal !== undefined && adminVal !== null ? adminVal as boolean : false;

    const moderatorVal = json['moderator'];
    user.moderator = moderatorVal !== undefined && moderatorVal !== null ? moderatorVal as boolean : false;

    return user;
  }

  getAvatarUrl(size: number = 96): string {
    if (this.animatedAvatar !== null && (this.animatedAvatar as string).trim().length > 0) {
      return UrlUtils.resolveUrl(this.animatedAvatar as string);
    }
    if (this.avatarTemplate.trim().length === 0) {
      return '';
    }
    return UrlUtils.resolveUrl(this.avatarTemplate.replace('{size}', size.toString()));
  }
}

/**
 * 徽章详情响应
 */
export class BadgeDetailResponse {
  badge: Badge = new Badge();
  userBadges: UserBadge[] = [];
  grantedUsers: BadgeUser[] = [];
  totalCount: number = 0;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): BadgeDetailResponse {
    const response: BadgeDetailResponse = new BadgeDetailResponse();

    const badgesMap: Map<number, Badge> = new Map();
    const badgesVal = json['badges'];
    if (badgesVal !== undefined && badgesVal !== null && Array.isArray(badgesVal)) {
      const badgesArr: Object[] = badgesVal as Object[];
      for (let i = 0; i < badgesArr.length; i++) {
        const badge: Badge = Badge.fromJson(badgesArr[i] as Record<string, Object>);
        if (badge.id > 0) {
          badgesMap.set(badge.id, badge);
        }
      }
    }

    const usersVal = json['users'];
    if (usersVal !== undefined && usersVal !== null && Array.isArray(usersVal)) {
      const arr: Object[] = usersVal as Object[];
      const list: BadgeUser[] = [];
      for (let i = 0; i < arr.length; i++) {
        list.push(BadgeUser.fromJson(arr[i] as Record<string, Object>));
      }
      response.grantedUsers = list;
    }

    const topicTitleMap: Map<number, string> = new Map();
    const topicsVal = json['topics'];
    if (topicsVal !== undefined && topicsVal !== null && Array.isArray(topicsVal)) {
      const arr: Object[] = topicsVal as Object[];
      for (let i = 0; i < arr.length; i++) {
        const item: Record<string, Object> = arr[i] as Record<string, Object>;
        const idVal = item['id'];
        const titleVal = item['title'];
        const topicId: number = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;
        const topicTitle: string = titleVal !== undefined && titleVal !== null ? titleVal.toString() : '';
        if (topicId > 0 && topicTitle.length > 0) {
          topicTitleMap.set(topicId, topicTitle);
        }
      }
    }

    let userBadgesSource: Object[] = [];
    const userBadgeInfoVal = json['user_badge_info'];
    if (userBadgeInfoVal !== undefined && userBadgeInfoVal !== null && typeof userBadgeInfoVal === 'object') {
      const info: Record<string, Object> = userBadgeInfoVal as Record<string, Object>;
      const infoBadgesVal = info['user_badges'];
      if (infoBadgesVal !== undefined && infoBadgesVal !== null && Array.isArray(infoBadgesVal)) {
        userBadgesSource = infoBadgesVal as Object[];
      }
      const grantCountVal = info['grant_count'];
      response.totalCount = grantCountVal !== undefined && grantCountVal !== null
        ? Number(grantCountVal.toString())
        : 0;
    } else {
      const userBadgesVal = json['user_badges'];
      if (userBadgesVal !== undefined && userBadgesVal !== null && Array.isArray(userBadgesVal)) {
        userBadgesSource = userBadgesVal as Object[];
      }
    }

    const userBadges: UserBadge[] = [];
    for (let i = 0; i < userBadgesSource.length; i++) {
      const userBadge: UserBadge = UserBadge.fromJson(userBadgesSource[i] as Record<string, Object>);
      if (userBadge.badge === null && badgesMap.has(userBadge.badgeId)) {
        userBadge.badge = badgesMap.get(userBadge.badgeId) as Badge;
      }
      if ((userBadge.topicTitle === null || (userBadge.topicTitle as string).trim().length === 0)
        && userBadge.topicId !== null
        && topicTitleMap.has(userBadge.topicId as number)) {
        userBadge.topicTitle = topicTitleMap.get(userBadge.topicId as number) as string;
      }
      userBadges.push(userBadge);
    }
    response.userBadges = userBadges;

    const badgeVal = json['badge'];
    if (badgeVal !== undefined && badgeVal !== null && typeof badgeVal === 'object') {
      response.badge = Badge.fromJson(badgeVal as Record<string, Object>);
    } else if (userBadges.length > 0 && userBadges[0].badge !== null) {
      response.badge = userBadges[0].badge as Badge;
    } else if (badgesMap.size > 0) {
      const badgeIds: number[] = Array.from(badgesMap.keys());
      response.badge = badgesMap.get(badgeIds[0]) as Badge;
    }

    if (response.totalCount <= 0) {
      response.totalCount = response.badge.grantCount > 0 ? response.badge.grantCount : response.userBadges.length;
    }

    return response;
  }
}

export class UserBadgeListResponse {
  userBadges: UserBadge[] = [];
  totalCount: number = 0;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): UserBadgeListResponse {
    const response = new UserBadgeListResponse();

    const badgesMap: Map<number, Badge> = new Map();
    const badgesVal = json['badges'];
    if (badgesVal !== undefined && badgesVal !== null && Array.isArray(badgesVal)) {
      const badgesArr: Object[] = badgesVal as Object[];
      for (let i = 0; i < badgesArr.length; i++) {
        const badge: Badge = Badge.fromJson(badgesArr[i] as Record<string, Object>);
        if (badge.id > 0) {
          badgesMap.set(badge.id, badge);
        }
      }
    }

    const userBadgesVal = json['user_badges'];
    if (userBadgesVal !== undefined && userBadgesVal !== null && Array.isArray(userBadgesVal)) {
      const arr: Object[] = userBadgesVal as Object[];
      const list: UserBadge[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item: UserBadge = UserBadge.fromJson(arr[i] as Record<string, Object>);
        if (item.badge === null && badgesMap.has(item.badgeId)) {
          item.badge = badgesMap.get(item.badgeId) as Badge;
        }
        list.push(item);
      }
      response.userBadges = list;
    }

    let totalCount: number = 0;
    for (let i = 0; i < response.userBadges.length; i++) {
      totalCount += Math.max(1, response.userBadges[i].count);
    }
    response.totalCount = totalCount;

    return response;
  }
}
