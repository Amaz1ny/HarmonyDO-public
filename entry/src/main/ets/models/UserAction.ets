import { TimeUtils } from '../common/utils/TimeUtils';

/**
 * 用户操作类型（与 Discourse user_actions.json 对齐）
 */
export class UserActionType {
  static readonly LIKE: number = 1;      // 点赞
  static readonly WAS_LIKED: number = 2; // 被点赞
  static readonly NEW_TOPIC: number = 4; // 创建话题
  static readonly REPLY: number = 5;     // 回复
}

/**
 * 用户操作记录
 */
export class UserAction {
  actionType: number | null = null;
  topicId: number = 0;
  title: string = '';
  slug: string | null = null;
  postNumber: number = 0;
  username: string = '';
  avatarTemplate: string = '';
  actingAt: Date | null = null;
  categoryId: number | null = null;
  excerpt: string | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): UserAction {
    const a = new UserAction();

    const typeVal = json['action_type'];
    a.actionType = typeVal !== undefined && typeVal !== null ? Number(typeVal.toString()) : null;

    const topicIdVal = json['topic_id'];
    a.topicId = topicIdVal !== undefined && topicIdVal !== null ? Number(topicIdVal.toString()) : 0;

    const titleVal = json['title'];
    a.title = titleVal !== undefined && titleVal !== null ? titleVal as string : '';

    const slugVal = json['slug'];
    a.slug = slugVal !== undefined && slugVal !== null ? slugVal as string : null;

    const postNumVal = json['post_number'];
    a.postNumber = postNumVal !== undefined && postNumVal !== null ? Number(postNumVal.toString()) : 0;

    const actingUserVal = json['acting_username'];
    const userVal = json['username'];
    const uname: string = actingUserVal !== undefined && actingUserVal !== null
      ? actingUserVal as string
      : (userVal !== undefined && userVal !== null ? userVal as string : '');
    a.username = uname;

    const actingAvatarVal = json['acting_avatar_template'];
    const avatarVal = json['avatar_template'];
    const avatar: string = actingAvatarVal !== undefined && actingAvatarVal !== null
      ? actingAvatarVal as string
      : (avatarVal !== undefined && avatarVal !== null ? avatarVal as string : '');
    a.avatarTemplate = avatar;

    const actingAtVal = json['acting_at'];
    const createdVal = json['created_at'];
    const timeString: string | null = actingAtVal !== undefined && actingAtVal !== null
      ? actingAtVal as string
      : (createdVal !== undefined && createdVal !== null ? createdVal as string : null);
    a.actingAt = TimeUtils.parseUtcTime(timeString);

    const catVal = json['category_id'];
    a.categoryId = catVal !== undefined && catVal !== null ? Number(catVal.toString()) : null;

    const excerptVal = json['excerpt'];
    a.excerpt = excerptVal !== undefined && excerptVal !== null ? excerptVal as string : null;

    return a;
  }

  getAvatarUrl(size: number = 120): string {
    if (this.avatarTemplate.length === 0) return '';
    return this.avatarTemplate.replace('{size}', size.toString());
  }
}

export class UserActionResponse {
  actions: UserAction[] = [];

  constructor() {
  }

  static fromJson(json: Record<string, Object>): UserActionResponse {
    const out = new UserActionResponse();
    const val = json['user_actions'];
    if (val !== undefined && val !== null) {
      const arr = val as Object[];
      const list: UserAction[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item = arr[i] as Record<string, Object>;
        list.push(UserAction.fromJson(item));
      }
      out.actions = list;
    }
    return out;
  }
}

/**
 * 用户回应记录（discourse-reactions 插件）
 */
export class UserReaction {
  id: number = 0;
  postId: number = 0;
  topicId: number = 0;
  postNumber: number = 0;
  topicTitle: string | null = null;
  excerpt: string | null = null;
  reactionValue: string | null = null;
  createdAt: Date | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): UserReaction {
    const r = new UserReaction();

    const idVal = json['id'];
    r.id = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;

    const postIdVal = json['post_id'];
    r.postId = postIdVal !== undefined && postIdVal !== null ? Number(postIdVal.toString()) : 0;

    const createdVal = json['created_at'];
    r.createdAt = createdVal !== undefined && createdVal !== null ? TimeUtils.parseUtcTime(createdVal as string) : null;

    const postVal = json['post'];
    if (postVal !== undefined && postVal !== null) {
      const postJson: Record<string, Object> = postVal as Record<string, Object>;
      const topicIdVal = postJson['topic_id'];
      r.topicId = topicIdVal !== undefined && topicIdVal !== null ? Number(topicIdVal.toString()) : 0;

      const postNumVal = postJson['post_number'];
      r.postNumber = postNumVal !== undefined && postNumVal !== null ? Number(postNumVal.toString()) : 0;

      const titleVal = postJson['topic_title'];
      r.topicTitle = titleVal !== undefined && titleVal !== null ? titleVal as string : null;

      const excerptVal = postJson['excerpt'];
      r.excerpt = excerptVal !== undefined && excerptVal !== null ? excerptVal as string : null;
    }

    const reactionVal = json['reaction'];
    if (reactionVal !== undefined && reactionVal !== null) {
      const reactionJson: Record<string, Object> = reactionVal as Record<string, Object>;
      const valueVal = reactionJson['reaction_value'];
      r.reactionValue = valueVal !== undefined && valueVal !== null ? valueVal as string : null;
    }

    return r;
  }
}

export class UserReactionsResponse {
  reactions: UserReaction[] = [];
  errorType: string | null = null;
  errorMessage: string | null = null;

  constructor() {
  }

  requiresLogin(): boolean {
    return this.errorType === 'not_logged_in';
  }

  static fromJson(json: Object): UserReactionsResponse {
    const out = new UserReactionsResponse();

    if (Array.isArray(json)) {
      const arr: Object[] = json as Object[];
      const list: UserReaction[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item = arr[i] as Record<string, Object>;
        list.push(UserReaction.fromJson(item));
      }
      out.reactions = list;
      return out;
    }

    const obj: Record<string, Object> = json as Record<string, Object>;
    const errorTypeVal = obj['error_type'];
    out.errorType = errorTypeVal !== undefined && errorTypeVal !== null ? errorTypeVal as string : null;
    const errorsVal = obj['errors'];
    if (Array.isArray(errorsVal) && (errorsVal as Object[]).length > 0) {
      const firstError: Object = (errorsVal as Object[])[0];
      out.errorMessage = firstError !== undefined && firstError !== null ? firstError.toString() : null;
    }
    const val = obj['reactions'];
    const postsVal = obj['posts'];
    const rawList: Object[] | null = val !== undefined && val !== null
      ? val as Object[]
      : (postsVal !== undefined && postsVal !== null ? postsVal as Object[] : null);

    if (rawList !== null) {
      const list: UserReaction[] = [];
      for (let i = 0; i < rawList.length; i++) {
        const item = rawList[i] as Record<string, Object>;
        list.push(UserReaction.fromJson(item));
      }
      out.reactions = list;
    }

    return out;
  }
}
