import { TimeUtils } from '../common/utils/TimeUtils';
import { UrlUtils } from '../common/utils/UrlUtils';
import { Badge } from './Badge';

/**
 * 用户状态模型
 */
export class UserStatus {
  description: string | null = null;
  emoji: string | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): UserStatus {
    const status = new UserStatus();
    const desc = json['description'];
    const emo = json['emoji'];
    status.description = desc !== undefined && desc !== null ? desc as string : null;
    status.emoji = emo !== undefined && emo !== null ? emo as string : null;
    return status;
  }
}

/**
 * 用户数据模型
 */
export class User {
  id: number = 0;
  username: string = '';
  name: string | null = null;
  avatarTemplate: string | null = null;
  animatedAvatar: string | null = null;
  trustLevel: number = 0;
  bio: string | null = null;
  bioCooked: string | null = null;
  bioRaw: string | null = null;

  // 背景图
  cardBackgroundUploadUrl: string | null = null;
  profileBackgroundUploadUrl: string | null = null;

  // 用户状态
  status: UserStatus | null = null;

  // 时间信息
  lastPostedAt: Date | null = null;
  lastSeenAt: Date | null = null;
  createdAt: Date | null = null;
  location: string | null = null;
  website: string | null = null;
  websiteName: string | null = null;

  // Flair 徽章
  flairUrl: string | null = null;
  flairName: string | null = null;
  flairBgColor: string | null = null;
  flairColor: string | null = null;
  flairGroupId: number | null = null;

  // 关注相关（discourse-follow 插件）
  canFollow: boolean | null = null;
  isFollowed: boolean | null = null;
  totalFollowers: number | null = null;
  totalFollowing: number | null = null;

  // 私信相关
  canSendPrivateMessages: boolean | null = null;
  canSendPrivateMessageToUser: boolean | null = null;

  // 积分相关
  gamificationScore: number | null = null;

  // 通知计数
  unreadNotifications: number = 0;
  unreadHighPriorityNotifications: number = 0;
  allUnreadNotificationsCount: number = 0;
  seenNotificationId: number = 0;
  notificationChannelPosition: number = -1;

  // 订阅级别相关
  muted: boolean | null = null;
  ignored: boolean | null = null;
  canMuteUser: boolean | null = null;
  canIgnoreUser: boolean | null = null;

  // 封禁 / 禁言信息
  suspendReason: string | null = null;
  suspendedTill: Date | null = null;
  silenceReason: string | null = null;
  silencedTill: Date | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): User {
    const user = new User();

    const idVal = json['id'];
    user.id = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;

    const usernameVal = json['username'];
    user.username = usernameVal !== undefined && usernameVal !== null ? usernameVal as string : '';

    const nameVal = json['name'];
    user.name = nameVal !== undefined && nameVal !== null ? nameVal as string : null;

    const avatarVal = json['avatar_template'];
    user.avatarTemplate = avatarVal !== undefined && avatarVal !== null ? avatarVal as string : null;

    const animatedVal = json['animated_avatar'];
    user.animatedAvatar = animatedVal !== undefined && animatedVal !== null ? animatedVal as string : null;

    const trustVal = json['trust_level'];
    user.trustLevel = trustVal !== undefined && trustVal !== null ? Number(trustVal.toString()) : 0;

    const bioCookedVal = json['bio_cooked'];
    user.bioCooked = bioCookedVal !== undefined && bioCookedVal !== null
      ? User.fixHtml(bioCookedVal as string) : null;

    const bioRawVal = json['bio_raw'];
    user.bioRaw = bioRawVal !== undefined && bioRawVal !== null ? bioRawVal as string : null;

    const bioExcerptVal = json['bio_excerpt'];
    const bioExcerpt: string | null = bioExcerptVal !== undefined && bioExcerptVal !== null
      ? bioExcerptVal as string : null;
    if (user.bioCooked !== null && user.bioCooked.length > 0) {
      user.bio = user.bioCooked;
    } else if (bioExcerpt !== null && bioExcerpt.length > 0) {
      user.bio = bioExcerpt;
    } else {
      user.bio = user.bioRaw;
    }

    const cardBgVal = json['card_background_upload_url'];
    user.cardBackgroundUploadUrl = cardBgVal !== undefined && cardBgVal !== null
      ? UrlUtils.resolveUrl(cardBgVal as string) : null;

    const profileBgVal = json['profile_background_upload_url'];
    user.profileBackgroundUploadUrl = profileBgVal !== undefined && profileBgVal !== null
      ? UrlUtils.resolveUrl(profileBgVal as string) : null;

    const unreadVal = json['unread_notifications'];
    user.unreadNotifications = unreadVal !== undefined && unreadVal !== null ? Number(unreadVal.toString()) : 0;

    const unreadHiVal = json['unread_high_priority_notifications'];
    user.unreadHighPriorityNotifications = unreadHiVal !== undefined && unreadHiVal !== null ? Number(unreadHiVal.toString()) : 0;

    const allUnreadVal = json['all_unread_notifications_count'];
    user.allUnreadNotificationsCount = allUnreadVal !== undefined && allUnreadVal !== null ? Number(allUnreadVal.toString()) : 0;

    const seenVal = json['seen_notification_id'];
    user.seenNotificationId = seenVal !== undefined && seenVal !== null ? Number(seenVal.toString()) : 0;

    const channelPosVal = json['notification_channel_position'];
    user.notificationChannelPosition = channelPosVal !== undefined && channelPosVal !== null
      ? Number(channelPosVal.toString()) : -1;

    const statusVal = json['status'];
    if (statusVal !== undefined && statusVal !== null) {
      user.status = UserStatus.fromJson(statusVal as Record<string, Object>);
    }

    const lastPostedVal = json['last_posted_at'];
    user.lastPostedAt = lastPostedVal !== undefined && lastPostedVal !== null
      ? TimeUtils.parseUtcTime(lastPostedVal as string) : null;

    const lastSeenVal = json['last_seen_at'];
    user.lastSeenAt = lastSeenVal !== undefined && lastSeenVal !== null
      ? TimeUtils.parseUtcTime(lastSeenVal as string) : null;

    const createdVal = json['created_at'];
    user.createdAt = createdVal !== undefined && createdVal !== null
      ? TimeUtils.parseUtcTime(createdVal as string) : null;

    const locVal = json['location'];
    user.location = locVal !== undefined && locVal !== null ? locVal as string : null;

    const websiteVal = json['website'];
    user.website = websiteVal !== undefined && websiteVal !== null ? websiteVal as string : null;

    const websiteNameVal = json['website_name'];
    user.websiteName = websiteNameVal !== undefined && websiteNameVal !== null ? websiteNameVal as string : null;

    const flairUrlVal = json['flair_url'];
    user.flairUrl = flairUrlVal !== undefined && flairUrlVal !== null ? UrlUtils.resolveUrl(flairUrlVal as string) : null;

    const flairNameVal = json['flair_name'];
    user.flairName = flairNameVal !== undefined && flairNameVal !== null ? flairNameVal as string : null;

    const flairBgVal = json['flair_bg_color'];
    user.flairBgColor = flairBgVal !== undefined && flairBgVal !== null ? flairBgVal as string : null;

    const flairColorVal = json['flair_color'];
    user.flairColor = flairColorVal !== undefined && flairColorVal !== null ? flairColorVal as string : null;

    const flairGroupVal = json['flair_group_id'];
    user.flairGroupId = flairGroupVal !== undefined && flairGroupVal !== null ? Number(flairGroupVal.toString()) : null;

    const canFollowVal = json['can_follow'];
    user.canFollow = canFollowVal !== undefined && canFollowVal !== null ? canFollowVal as boolean : null;

    const isFollowedVal = json['is_followed'];
    user.isFollowed = isFollowedVal !== undefined && isFollowedVal !== null ? isFollowedVal as boolean : null;

    const followersVal = json['total_followers'];
    user.totalFollowers = followersVal !== undefined && followersVal !== null ? Number(followersVal.toString()) : null;

    const followingVal = json['total_following'];
    user.totalFollowing = followingVal !== undefined && followingVal !== null ? Number(followingVal.toString()) : null;

    const canPmVal = json['can_send_private_messages'];
    user.canSendPrivateMessages = canPmVal !== undefined && canPmVal !== null ? canPmVal as boolean : null;

    const canPmToVal = json['can_send_private_message_to_user'];
    user.canSendPrivateMessageToUser = canPmToVal !== undefined && canPmToVal !== null ? canPmToVal as boolean : null;

    const scoreVal = json['gamification_score'];
    user.gamificationScore = scoreVal !== undefined && scoreVal !== null ? Number(scoreVal.toString()) : null;

    const mutedVal = json['muted'];
    user.muted = mutedVal !== undefined && mutedVal !== null ? mutedVal as boolean : null;

    const ignoredVal = json['ignored'];
    user.ignored = ignoredVal !== undefined && ignoredVal !== null ? ignoredVal as boolean : null;

    const canMuteVal = json['can_mute_user'];
    user.canMuteUser = canMuteVal !== undefined && canMuteVal !== null ? canMuteVal as boolean : null;

    const canIgnoreVal = json['can_ignore_user'];
    user.canIgnoreUser = canIgnoreVal !== undefined && canIgnoreVal !== null ? canIgnoreVal as boolean : null;

    const suspendReasonVal = json['suspend_reason'];
    user.suspendReason = suspendReasonVal !== undefined && suspendReasonVal !== null ? suspendReasonVal as string : null;

    const suspendedTillVal = json['suspended_till'];
    user.suspendedTill = suspendedTillVal !== undefined && suspendedTillVal !== null
      ? TimeUtils.parseUtcTime(suspendedTillVal as string) : null;

    const silenceReasonVal = json['silence_reason'];
    user.silenceReason = silenceReasonVal !== undefined && silenceReasonVal !== null ? silenceReasonVal as string : null;

    const silencedTillVal = json['silenced_till'];
    user.silencedTill = silencedTillVal !== undefined && silencedTillVal !== null
      ? TimeUtils.parseUtcTime(silencedTillVal as string) : null;

    return user;
  }

  /**
   * 简单修复 cooked HTML 里的相对资源路径（src/href="/..."）
   */
  private static fixHtml(html: string): string {
    if (html.length === 0) return html;
    try {
      let out: string = html;
      out = out.replace(/src=(['"])(\/[^'"]+)\1/g, (_m: string, quote: string, path: string) => {
        return `src=${quote}${UrlUtils.resolveUrl(path)}${quote}`;
      });
      out = out.replace(/href=(['"])(\/[^'"]+)\1/g, (_m: string, quote: string, path: string) => {
        return `href=${quote}${UrlUtils.resolveUrl(path)}${quote}`;
      });
      return out;
    } catch (_) {
      return html;
    }
  }

  /**
   * 获取信任等级描述
   */
  get trustLevelString(): string {
    if (this.trustLevel === 0) {
      return 'L0 新用户';
    } else if (this.trustLevel === 1) {
      return 'L1 基本用户';
    } else if (this.trustLevel === 2) {
      return 'L2 成员';
    } else if (this.trustLevel === 3) {
      return 'L3 活跃用户';
    } else if (this.trustLevel === 4) {
      return 'L4 领袖';
    }
    return `等级 ${this.trustLevel}`;
  }

  /**
   * 获取头像 URL
   */
  getAvatarUrl(size: number = 120): string {
    // 优先使用动画头像
    if (this.animatedAvatar !== null && this.animatedAvatar.length > 0) {
      const t: string = this.animatedAvatar as string;
      const url: string = t.indexOf('{size}') >= 0 ? t.replace('{size}', size.toString()) : t;
      return UrlUtils.resolveUrl(url);
    }
    if (this.avatarTemplate === null) {
      return '';
    }
    const template: string = this.avatarTemplate.replace('{size}', size.toString());
    return UrlUtils.resolveUrl(template);
  }

  /**
   * 获取背景图 URL（优先 profile，其次 card）
   */
  get backgroundUrl(): string {
    if (this.profileBackgroundUploadUrl !== null && this.profileBackgroundUploadUrl.length > 0) {
      return this.profileBackgroundUploadUrl;
    }
    if (this.cardBackgroundUploadUrl !== null && this.cardBackgroundUploadUrl.length > 0) {
      return this.cardBackgroundUploadUrl;
    }
    return '';
  }

  get isSuspended(): boolean {
    return this.suspendedTill !== null && this.suspendedTill.getTime() > Date.now();
  }

  get isSuspendedForever(): boolean {
    if (this.suspendedTill === null) return false;
    return this.suspendedTill.getFullYear() - new Date().getFullYear() > 100;
  }

  get isSilenced(): boolean {
    return this.silencedTill !== null && this.silencedTill.getTime() > Date.now();
  }

  get isSilencedForever(): boolean {
    if (this.silencedTill === null) return false;
    return this.silencedTill.getFullYear() - new Date().getFullYear() > 100;
  }
}

/**
 * 关注/粉丝用户简化模型
 */
export class FollowUser {
  id: number = 0;
  username: string = '';
  name: string | null = null;
  avatarTemplate: string | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): FollowUser {
    const out: FollowUser = new FollowUser();
    const idVal = json['id'];
    out.id = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;
    const usernameVal = json['username'];
    out.username = usernameVal !== undefined && usernameVal !== null ? usernameVal.toString() : '';
    const nameVal = json['name'];
    out.name = nameVal !== undefined && nameVal !== null ? nameVal.toString() : null;
    const avatarVal = json['avatar_template'];
    out.avatarTemplate = avatarVal !== undefined && avatarVal !== null ? avatarVal.toString() : null;
    return out;
  }

  getAvatarUrl(size: number = 96): string {
    if (this.avatarTemplate === null || this.avatarTemplate.length === 0) {
      return '';
    }
    return UrlUtils.resolveUrl(this.avatarTemplate.replace('{size}', size.toString()));
  }
}

/**
 * 用户统计数据
 */
export class UserSummary {
  daysVisited: number = 0;
  postsReadCount: number = 0;
  likesReceived: number = 0;
  likesGiven: number = 0;
  topicCount: number = 0;
  postCount: number = 0;
  timeRead: number = 0;
  bookmarkCount: number = 0;

  // 详细统计（Summary Tab）
  topics: SummaryTopic[] = [];
  replies: SummaryReply[] = [];
  links: SummaryLink[] = [];
  mostRepliedToUsers: SummaryUserWithCount[] = [];
  mostLikedByUsers: SummaryUserWithCount[] = [];
  mostLikedUsers: SummaryUserWithCount[] = [];
  topCategories: SummaryCategory[] = [];
  badges: Badge[] = [];

  constructor() {
  }

  static fromJson(json: Record<string, Object>): UserSummary {
    const out = new UserSummary();

    const summaryVal = json['user_summary'];
    const summary: Record<string, Object> = summaryVal !== undefined && summaryVal !== null
      ? summaryVal as Record<string, Object> : {};

    const dv = summary['days_visited'];
    out.daysVisited = dv !== undefined && dv !== null ? Number(dv.toString()) : 0;
    const pr = summary['posts_read_count'];
    out.postsReadCount = pr !== undefined && pr !== null ? Number(pr.toString()) : 0;
    const lr = summary['likes_received'];
    out.likesReceived = lr !== undefined && lr !== null ? Number(lr.toString()) : 0;
    const lg = summary['likes_given'];
    out.likesGiven = lg !== undefined && lg !== null ? Number(lg.toString()) : 0;
    const tc = summary['topic_count'];
    out.topicCount = tc !== undefined && tc !== null ? Number(tc.toString()) : 0;
    const pc = summary['post_count'];
    out.postCount = pc !== undefined && pc !== null ? Number(pc.toString()) : 0;
    const tr = summary['time_read'];
    out.timeRead = tr !== undefined && tr !== null ? Number(tr.toString()) : 0;
    const bc = summary['bookmark_count'];
    out.bookmarkCount = bc !== undefined && bc !== null ? Number(bc.toString()) : 0;

    // sideload topics / badges
    const topicMap: Map<number, SummaryTopic> = new Map();
    const sideloadTopicsVal = json['topics'];
    if (sideloadTopicsVal !== undefined && sideloadTopicsVal !== null) {
      const topicsArr = sideloadTopicsVal as Object[];
      const topics: SummaryTopic[] = [];
      for (let i = 0; i < topicsArr.length; i++) {
        const t: SummaryTopic = SummaryTopic.fromJson(topicsArr[i] as Record<string, Object>);
        topics.push(t);
        if (t.id > 0) topicMap.set(t.id, t);
      }
      out.topics = topics;
    }

    // replies
    const repliesVal = summary['replies'];
    if (repliesVal !== undefined && repliesVal !== null) {
      const arr = repliesVal as Object[];
      const replies: SummaryReply[] = [];
      for (let i = 0; i < arr.length; i++) {
        replies.push(SummaryReply.fromJson(arr[i] as Record<string, Object>, topicMap));
      }
      out.replies = replies;
    }

    // links
    const linksVal = summary['links'];
    if (linksVal !== undefined && linksVal !== null) {
      const arr = linksVal as Object[];
      const links: SummaryLink[] = [];
      for (let i = 0; i < arr.length; i++) {
        links.push(SummaryLink.fromJson(arr[i] as Record<string, Object>, topicMap));
      }
      out.links = links;
    }

    // users with count
    out.mostRepliedToUsers = UserSummary.parseUserWithCountList(summary['most_replied_to_users']);
    out.mostLikedByUsers = UserSummary.parseUserWithCountList(summary['most_liked_by_users']);
    out.mostLikedUsers = UserSummary.parseUserWithCountList(summary['most_liked_users']);

    // categories
    const catsVal = summary['top_categories'];
    if (catsVal !== undefined && catsVal !== null) {
      const arr = catsVal as Object[];
      const cats: SummaryCategory[] = [];
      for (let i = 0; i < arr.length; i++) {
        cats.push(SummaryCategory.fromJson(arr[i] as Record<string, Object>));
      }
      out.topCategories = cats;
    }

    // badges（sideload 顶层）
    const badgesVal = json['badges'];
    if (badgesVal !== undefined && badgesVal !== null) {
      const arr = badgesVal as Object[];
      const badges: Badge[] = [];
      for (let i = 0; i < arr.length; i++) {
        badges.push(Badge.fromJson(arr[i] as Record<string, Object>));
      }
      out.badges = badges;
    }

    return out;
  }

  private static parseUserWithCountList(value: Object | undefined): SummaryUserWithCount[] {
    if (value === undefined || value === null) return [];
    const arr = value as Object[];
    const out: SummaryUserWithCount[] = [];
    for (let i = 0; i < arr.length; i++) {
      out.push(SummaryUserWithCount.fromJson(arr[i] as Record<string, Object>));
    }
    return out;
  }

  /**
   * 格式化阅读时间
   */
  get formattedTimeRead(): string {
    const hours: number = Math.floor(this.timeRead / 3600);
    if (hours > 0) {
      return `${hours}h`;
    }
    const minutes: number = Math.floor(this.timeRead / 60);
    return `${minutes}m`;
  }
}

/**
 * Summary - 话题
 */
export class SummaryTopic {
  id: number = 0;
  title: string = '';
  slug: string | null = null;
  likeCount: number = 0;
  categoryId: number | null = null;
  createdAt: Date | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): SummaryTopic {
    const t = new SummaryTopic();
    const idVal = json['id'];
    t.id = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;
    const titleVal = json['title'];
    t.title = titleVal !== undefined && titleVal !== null ? titleVal as string : '';
    const slugVal = json['slug'];
    t.slug = slugVal !== undefined && slugVal !== null ? slugVal as string : null;
    const likeVal = json['like_count'];
    t.likeCount = likeVal !== undefined && likeVal !== null ? Number(likeVal.toString()) : 0;
    const catVal = json['category_id'];
    t.categoryId = catVal !== undefined && catVal !== null ? Number(catVal.toString()) : null;
    const createdVal = json['created_at'];
    t.createdAt = createdVal !== undefined && createdVal !== null ? TimeUtils.parseUtcTime(createdVal as string) : null;
    return t;
  }
}

/**
 * Summary - 回复
 */
export class SummaryReply {
  topicId: number | null = null;
  postNumber: number = 0;
  likeCount: number = 0;
  createdAt: Date | null = null;
  topic: SummaryTopic | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>, topicMap: Map<number, SummaryTopic>): SummaryReply {
    const r = new SummaryReply();
    const topicIdVal = json['topic_id'];
    r.topicId = topicIdVal !== undefined && topicIdVal !== null ? Number(topicIdVal.toString()) : null;

    const postVal = json['post_number'];
    r.postNumber = postVal !== undefined && postVal !== null ? Number(postVal.toString()) : 0;

    const likeVal = json['like_count'];
    r.likeCount = likeVal !== undefined && likeVal !== null ? Number(likeVal.toString()) : 0;

    const createdVal = json['created_at'];
    r.createdAt = createdVal !== undefined && createdVal !== null ? TimeUtils.parseUtcTime(createdVal as string) : null;

    const topicObjVal = json['topic'];
    if (topicObjVal !== undefined && topicObjVal !== null) {
      r.topic = SummaryTopic.fromJson(topicObjVal as Record<string, Object>);
      if (r.topicId === null && r.topic !== null) r.topicId = r.topic.id;
    } else if (r.topicId !== null && topicMap.has(r.topicId as number)) {
      r.topic = topicMap.get(r.topicId as number) as SummaryTopic;
    }
    return r;
  }
}

/**
 * Summary - 链接
 */
export class SummaryLink {
  url: string = '';
  title: string | null = null;
  clicks: number = 0;
  postNumber: number | null = null;
  topicId: number | null = null;
  topic: SummaryTopic | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>, topicMap: Map<number, SummaryTopic>): SummaryLink {
    const l = new SummaryLink();
    const urlVal = json['url'];
    l.url = urlVal !== undefined && urlVal !== null ? urlVal as string : '';
    const titleVal = json['title'];
    l.title = titleVal !== undefined && titleVal !== null ? titleVal as string : null;
    const clicksVal = json['clicks'];
    l.clicks = clicksVal !== undefined && clicksVal !== null ? Number(clicksVal.toString()) : 0;
    const postVal = json['post_number'];
    l.postNumber = postVal !== undefined && postVal !== null ? Number(postVal.toString()) : null;
    const topicIdVal = json['topic_id'];
    l.topicId = topicIdVal !== undefined && topicIdVal !== null ? Number(topicIdVal.toString()) : null;

    const topicObjVal = json['topic'];
    if (topicObjVal !== undefined && topicObjVal !== null) {
      l.topic = SummaryTopic.fromJson(topicObjVal as Record<string, Object>);
      if (l.topicId === null && l.topic !== null) l.topicId = l.topic.id;
    } else if (l.topicId !== null && topicMap.has(l.topicId as number)) {
      l.topic = topicMap.get(l.topicId as number) as SummaryTopic;
    }
    return l;
  }
}

/**
 * Summary - 用户统计（最多回复/点赞等）
 */
export class SummaryUserWithCount {
  id: number = 0;
  username: string = '';
  name: string | null = null;
  avatarTemplate: string | null = null;
  count: number = 0;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): SummaryUserWithCount {
    const u = new SummaryUserWithCount();
    const idVal = json['id'];
    u.id = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;
    const usernameVal = json['username'];
    u.username = usernameVal !== undefined && usernameVal !== null ? usernameVal as string : '';
    const nameVal = json['name'];
    u.name = nameVal !== undefined && nameVal !== null ? nameVal as string : null;
    const avatarVal = json['avatar_template'];
    u.avatarTemplate = avatarVal !== undefined && avatarVal !== null ? avatarVal as string : null;
    const countVal = json['count'];
    u.count = countVal !== undefined && countVal !== null ? Number(countVal.toString()) : 0;
    return u;
  }

  getAvatarUrl(size: number = 120): string {
    return UrlUtils.getAvatarUrl(this.avatarTemplate, size);
  }
}

/**
 * Summary - 热门类别
 */
export class SummaryCategory {
  id: number = 0;
  name: string = '';
  color: string | null = null;
  slug: string | null = null;
  topicCount: number = 0;
  postCount: number = 0;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): SummaryCategory {
    const c = new SummaryCategory();
    const idVal = json['id'];
    c.id = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;
    const nameVal = json['name'];
    c.name = nameVal !== undefined && nameVal !== null ? nameVal as string : '';
    const colorVal = json['color'];
    c.color = colorVal !== undefined && colorVal !== null ? colorVal as string : null;
    const slugVal = json['slug'];
    c.slug = slugVal !== undefined && slugVal !== null ? slugVal as string : null;
    const topicCountVal = json['topic_count'];
    c.topicCount = topicCountVal !== undefined && topicCountVal !== null ? Number(topicCountVal.toString()) : 0;
    const postCountVal = json['post_count'];
    c.postCount = postCountVal !== undefined && postCountVal !== null ? Number(postCountVal.toString()) : 0;
    return c;
  }
}
