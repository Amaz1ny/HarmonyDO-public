import { TimeUtils } from '../common/utils/TimeUtils';
import { UserStatus } from './User';
import { GrantedBadge } from './Badge';

/**
 * 回复目标用户
 */
export class ReplyToUser {
  username: string = '';
  name: string | null = null;
  avatarTemplate: string = '';

  constructor() {
  }
}

/**
 * 链接点击统计（用于“相关链接”）
 */
export class LinkCount {
  url: string = '';
  internal: boolean = false;
  reflection: boolean = false;
  title: string | null = null;
  clicks: number = 0;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): LinkCount {
    const out: LinkCount = new LinkCount();

    const urlVal = json['url'];
    out.url = urlVal !== undefined && urlVal !== null ? (urlVal as string).trim() : '';

    const internalVal = json['internal'];
    out.internal = internalVal !== undefined && internalVal !== null ? internalVal as boolean : false;

    const reflectionVal = json['reflection'];
    out.reflection = reflectionVal !== undefined && reflectionVal !== null ? reflectionVal as boolean : false;

    const titleVal = json['title'];
    const titleText: string = titleVal !== undefined && titleVal !== null ? titleVal.toString().trim() : '';
    out.title = titleText.length > 0 ? titleText : null;

    const clicksVal = json['clicks'];
    out.clicks = clicksVal !== undefined && clicksVal !== null ? clicksVal as number : 0;

    return out;
  }
}

/**
 * 投票选项
 */
export class PollOption {
  id: string = '';
  html: string = '';
  votes: number = 0;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): PollOption {
    const out: PollOption = new PollOption();
    const idVal = json['id'];
    out.id = idVal !== undefined && idVal !== null ? idVal.toString() : '';
    const htmlVal = json['html'];
    out.html = htmlVal !== undefined && htmlVal !== null ? htmlVal.toString() : '';
    const votesVal = json['votes'];
    out.votes = votesVal !== undefined && votesVal !== null ? Number(votesVal.toString()) : 0;
    return out;
  }
}

/**
 * 投票
 */
export class Poll {
  id: number = 0;
  name: string = '';
  type: string = 'regular';
  status: string = 'open';
  results: string = 'always';
  options: PollOption[] = [];
  voters: number = 0;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): Poll {
    const out: Poll = new Poll();
    const idVal = json['id'];
    out.id = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;
    const nameVal = json['name'];
    out.name = nameVal !== undefined && nameVal !== null ? nameVal.toString() : '';
    const typeVal = json['type'];
    out.type = typeVal !== undefined && typeVal !== null ? typeVal.toString() : 'regular';
    const statusVal = json['status'];
    out.status = statusVal !== undefined && statusVal !== null ? statusVal.toString() : 'open';
    const resultsVal = json['results'];
    out.results = resultsVal !== undefined && resultsVal !== null ? resultsVal.toString() : 'always';
    const votersVal = json['voters'];
    out.voters = votersVal !== undefined && votersVal !== null ? Number(votersVal.toString()) : 0;

    const optionsVal = json['options'];
    if (optionsVal !== undefined && optionsVal !== null && Array.isArray(optionsVal)) {
      const arr: Object[] = optionsVal as Object[];
      const opts: PollOption[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item === null || item === undefined || typeof item !== 'object') continue;
        opts.push(PollOption.fromJson(item as Record<string, Object>));
      }
      out.options = opts;
    }
    return out;
  }
}

/**
 * 被提及用户（含状态信息）
 */
export class MentionedUser {
  id: number = 0;
  username: string = '';
  name: string | null = null;
  avatarTemplate: string | null = null;
  statusEmoji: string | null = null;
  statusDescription: string | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): MentionedUser {
    const out: MentionedUser = new MentionedUser();
    const idVal = json['id'];
    out.id = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;
    const usernameVal = json['username'];
    out.username = usernameVal !== undefined && usernameVal !== null ? usernameVal.toString() : '';
    const nameVal = json['name'];
    out.name = nameVal !== undefined && nameVal !== null ? nameVal.toString() : null;
    const avatarVal = json['avatar_template'];
    out.avatarTemplate = avatarVal !== undefined && avatarVal !== null ? avatarVal.toString() : null;

    const statusVal = json['status'];
    if (statusVal !== undefined && statusVal !== null && typeof statusVal === 'object') {
      const statusObj: Record<string, Object> = statusVal as Record<string, Object>;
      const emojiVal = statusObj['emoji'];
      out.statusEmoji = emojiVal !== undefined && emojiVal !== null ? emojiVal.toString() : null;
      const descVal = statusObj['description'];
      out.statusDescription = descVal !== undefined && descVal !== null ? descVal.toString() : null;
    }
    return out;
  }
}

/**
 * 帖子（回复）数据模型
 */
export class Post {
  id: number = 0;
  name: string | null = null;
  username: string = '';
  avatarTemplate: string = '';
  animatedAvatar: string | null = null;
  cooked: string = '';  // HTML 内容
  postNumber: number = 0;
  postType: number = 1;
  updatedAt: Date | null = null;
  createdAt: Date | null = null;
  likeCount: number = 0;
  replyCount: number = 0;
  replyToPostNumber: number = 0;
  replyToUser: ReplyToUser | null = null;
  bookmarked: boolean = false;
  bookmarkId: number | null = null;
  read: boolean = false;
  canEdit: boolean = false;
  canDelete: boolean = false;

  // Flair 徽章
  flairUrl: string | null = null;
  flairName: string | null = null;
  flairBgColor: string | null = null;
  flairColor: string | null = null;

  // 用户主要群组
  primaryGroupName: string | null = null;

  // 群组版主标识
  groupModerator: boolean = false;

  // 已解决问题
  acceptedAnswer: boolean = false;

  // 删除状态
  deletedAt: Date | null = null;
  userDeleted: boolean = false;

  // 用户信息
  userTitle: string | null = null;
  userStatus: UserStatus | null = null;
  userId: number | null = null;

  // 身份标识
  moderator: boolean = false;
  admin: boolean = false;

  // 已授予徽章（用于楼层头部图标展示）
  badgesGranted: GrantedBadge[] = [];

  // 隐藏
  hidden: boolean = false;

  // 当前用户是否已点赞
  liked: boolean = false;

  // 相关链接（reflection links）
  linkCounts: LinkCount[] | null = null;

  // 投票数据
  polls: Poll[] | null = null;
  pollsVotes: Map<string, string[]> | null = null;

  // 被提及用户（含状态 emoji）
  mentionedUsers: MentionedUser[] | null = null;

  // 操作代码（small_action）
  actionCode: string | null = null;
  actionCodeWho: string | null = null;

  constructor() {
  }

  /**
   * 获取头像 URL
   */
  getAvatarUrl(size: number = 120): string {
    if (this.animatedAvatar !== null && this.animatedAvatar.length > 0) {
      const t: string = this.animatedAvatar as string;
      return t.indexOf('{size}') >= 0 ? t.replace('{size}', size.toString()) : t;
    }
    const template: string = this.avatarTemplate !== undefined && this.avatarTemplate !== null ? this.avatarTemplate : '';
    return template.replace('{size}', size.toString());
  }

  /**
   * 帖子是否已被删除
   */
  get isDeleted(): boolean {
    return this.deletedAt !== null;
  }

  /**
   * 从 JSON 解析
   */
  static fromJson(json: Record<string, Object>): Post {
    const post = new Post();

    const idVal = json['id'];
    post.id = idVal !== undefined && idVal !== null ? idVal as number : 0;

    const nameVal = json['name'];
    post.name = nameVal !== undefined && nameVal !== null ? nameVal as string : null;

    const usernameVal = json['username'];
    post.username = usernameVal !== undefined && usernameVal !== null ? usernameVal as string : '';

    const avatarVal = json['avatar_template'];
    post.avatarTemplate = avatarVal !== undefined && avatarVal !== null ? avatarVal as string : '';

    const animVal = json['animated_avatar'];
    post.animatedAvatar = animVal !== undefined && animVal !== null ? animVal as string : null;

    const cookedVal = json['cooked'];
    post.cooked = cookedVal !== undefined && cookedVal !== null ? cookedVal as string : '';

    const postNumVal = json['post_number'];
    post.postNumber = postNumVal !== undefined && postNumVal !== null ? postNumVal as number : 0;

    const postTypeVal = json['post_type'];
    post.postType = postTypeVal !== undefined && postTypeVal !== null ? postTypeVal as number : 1;

    const updatedVal = json['updated_at'];
    post.updatedAt = updatedVal !== undefined && updatedVal !== null
      ? TimeUtils.parseUtcTime(updatedVal as string) : null;

    const createdVal = json['created_at'];
    post.createdAt = createdVal !== undefined && createdVal !== null
      ? TimeUtils.parseUtcTime(createdVal as string) : null;

    const likeVal = json['like_count'];
    post.likeCount = likeVal !== undefined && likeVal !== null ? likeVal as number : 0;

    const replyVal = json['reply_count'];
    post.replyCount = replyVal !== undefined && replyVal !== null ? replyVal as number : 0;

    const replyToVal = json['reply_to_post_number'];
    post.replyToPostNumber = replyToVal !== undefined && replyToVal !== null ? replyToVal as number : 0;

    const replyToUserVal = json['reply_to_user'];
    if (replyToUserVal !== undefined && replyToUserVal !== null) {
      const replyToUserJson: Record<string, Object> = replyToUserVal as Record<string, Object>;
      const replyUser: ReplyToUser = new ReplyToUser();
      const replyUsernameVal = replyToUserJson['username'];
      replyUser.username = replyUsernameVal !== undefined && replyUsernameVal !== null ? replyUsernameVal as string : '';
      const replyNameVal = replyToUserJson['name'];
      replyUser.name = replyNameVal !== undefined && replyNameVal !== null ? replyNameVal as string : null;
      const replyAvatarVal = replyToUserJson['avatar_template'];
      replyUser.avatarTemplate = replyAvatarVal !== undefined && replyAvatarVal !== null ? replyAvatarVal as string : '';
      post.replyToUser = replyUser;
    }

    const bookmarkedVal = json['bookmarked'];
    post.bookmarked = bookmarkedVal !== undefined && bookmarkedVal !== null ? bookmarkedVal as boolean : false;

    const bookmarkIdVal = json['bookmark_id'];
    post.bookmarkId = bookmarkIdVal !== undefined && bookmarkIdVal !== null ? bookmarkIdVal as number : null;

    const readVal = json['read'];
    post.read = readVal !== undefined && readVal !== null ? readVal as boolean : false;

    const canEditVal = json['can_edit'];
    post.canEdit = canEditVal !== undefined && canEditVal !== null ? canEditVal as boolean : false;

    const canDeleteVal = json['can_delete'];
    post.canDelete = canDeleteVal !== undefined && canDeleteVal !== null ? canDeleteVal as boolean : false;

    const userIdVal = json['user_id'];
    post.userId = userIdVal !== undefined && userIdVal !== null ? userIdVal as number : null;

    const groupModVal = json['group_moderator'];
    post.groupModerator = groupModVal !== undefined && groupModVal !== null ? groupModVal as boolean : false;

    const modVal = json['moderator'];
    post.moderator = modVal !== undefined && modVal !== null ? modVal as boolean : false;

    const adminVal = json['admin'];
    post.admin = adminVal !== undefined && adminVal !== null ? adminVal as boolean : false;

    const hiddenVal = json['hidden'];
    post.hidden = hiddenVal !== undefined && hiddenVal !== null ? hiddenVal as boolean : false;

    const userTitleVal = json['user_title'];
    const userTitleText: string = userTitleVal !== undefined && userTitleVal !== null ? userTitleVal.toString().trim() : '';
    post.userTitle = userTitleText.length > 0 ? userTitleText : null;

    const userStatusVal = json['user_status'];
    if (userStatusVal !== undefined && userStatusVal !== null) {
      post.userStatus = UserStatus.fromJson(userStatusVal as Record<string, Object>);
    }

    const primaryGroupVal = json['primary_group_name'];
    post.primaryGroupName = primaryGroupVal !== undefined && primaryGroupVal !== null ? primaryGroupVal as string : null;

    const flairUrlVal = json['flair_url'];
    post.flairUrl = flairUrlVal !== undefined && flairUrlVal !== null ? flairUrlVal as string : null;

    const flairNameVal = json['flair_name'];
    post.flairName = flairNameVal !== undefined && flairNameVal !== null ? flairNameVal as string : null;

    const flairBgVal = json['flair_bg_color'];
    post.flairBgColor = flairBgVal !== undefined && flairBgVal !== null ? flairBgVal as string : null;

    const flairColorVal = json['flair_color'];
    post.flairColor = flairColorVal !== undefined && flairColorVal !== null ? flairColorVal as string : null;

    const actionCodeVal = json['action_code'];
    post.actionCode = actionCodeVal !== undefined && actionCodeVal !== null ? actionCodeVal as string : null;

    const actionWhoVal = json['action_code_who'];
    post.actionCodeWho = actionWhoVal !== undefined && actionWhoVal !== null ? actionWhoVal as string : null;

    const acceptedVal = json['accepted_answer'];
    post.acceptedAnswer = acceptedVal !== undefined && acceptedVal !== null ? acceptedVal as boolean : false;

    // 解析当前用户点赞状态
    const actionsVal = json['actions_summary'];
    if (actionsVal !== undefined && actionsVal !== null) {
      const actions = actionsVal as Object[];
      for (let i = 0; i < actions.length; i++) {
        const action = actions[i] as Record<string, Object>;
        const actionTypeId = action['id'];
        if (actionTypeId !== undefined && actionTypeId as number === 2) {
          const acted = action['acted'];
          post.liked = acted !== undefined && acted !== null ? acted as boolean : false;
          break;
        }
      }
    }

    const badgesVal = json['badges_granted'];
    if (badgesVal !== undefined && badgesVal !== null) {
      const arr: Object[] = badgesVal as Object[];
      const badges: GrantedBadge[] = [];
      for (let i = 0; i < arr.length; i++) {
        badges.push(GrantedBadge.fromJson(arr[i] as Record<string, Object>));
      }
      post.badgesGranted = badges;
    }

    // 解析 link_counts（用于“相关链接”）
    const linkCountsVal = json['link_counts'];
    if (linkCountsVal !== undefined && linkCountsVal !== null && Array.isArray(linkCountsVal)) {
      const arr: Object[] = linkCountsVal as Object[];
      const links: LinkCount[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item === null || item === undefined) continue;
        try {
          const parsed: LinkCount = LinkCount.fromJson(item as Record<string, Object>);
          if (parsed.url.length > 0) {
            links.push(parsed);
          }
        } catch (_) {
        }
      }
      post.linkCounts = links.length > 0 ? links : null;
    } else {
      post.linkCounts = null;
    }

    const pollsVal = json['polls'];
    if (pollsVal !== undefined && pollsVal !== null && Array.isArray(pollsVal)) {
      const arr: Object[] = pollsVal as Object[];
      const polls: Poll[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item === null || item === undefined || typeof item !== 'object') continue;
        polls.push(Poll.fromJson(item as Record<string, Object>));
      }
      post.polls = polls.length > 0 ? polls : null;
    } else {
      post.polls = null;
    }

    const pollsVotesVal = json['polls_votes'];
    if (pollsVotesVal !== undefined && pollsVotesVal !== null && typeof pollsVotesVal === 'object') {
      const votesObj: Record<string, Object> = pollsVotesVal as Record<string, Object>;
      const keys: string[] = Object.keys(votesObj);
      const votesMap: Map<string, string[]> = new Map();
      for (let i = 0; i < keys.length; i++) {
        const key: string = keys[i];
        const value: Object = votesObj[key];
        if (!Array.isArray(value)) continue;
        const arr: Object[] = value as Object[];
        const votes: string[] = [];
        for (let j = 0; j < arr.length; j++) {
          const item: Object = arr[j];
          if (item === null || item === undefined) continue;
          votes.push(item.toString());
        }
        votesMap.set(key, votes);
      }
      post.pollsVotes = votesMap.size > 0 ? votesMap : null;
    } else {
      post.pollsVotes = null;
    }

    const mentionedUsersVal = json['mentioned_users'];
    if (mentionedUsersVal !== undefined && mentionedUsersVal !== null && Array.isArray(mentionedUsersVal)) {
      const arr: Object[] = mentionedUsersVal as Object[];
      const users: MentionedUser[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item === null || item === undefined || typeof item !== 'object') continue;
        users.push(MentionedUser.fromJson(item as Record<string, Object>));
      }
      post.mentionedUsers = users.length > 0 ? users : null;
    } else {
      post.mentionedUsers = null;
    }

    return post;
  }
}
