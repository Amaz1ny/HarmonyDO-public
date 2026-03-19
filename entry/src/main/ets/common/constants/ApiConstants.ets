/**
 * Discourse API 端点常量
 */
export class ApiConstants {
  /** 获取话题列表（首页） */
  static readonly TOPIC_LIST: string = '/latest.json';

  /** 获取话题列表（热门） */
  static readonly TOPIC_LIST_TOP: string = '/top.json';

  /** 获取话题详情 */
  static topicDetail(id: number, postNumber: number = 0): string {
    if (postNumber > 0) {
      return `/t/${id}/${postNumber}.json`;
    }
    return `/t/${id}.json`;
  }

  /** 获取更多帖子 */
  static topicPosts(id: number): string {
    return `/t/${id}/posts.json`;
  }

  /** 获取分类列表 */
  static readonly CATEGORIES: string = '/categories.json';

  /** 获取站点信息（含分类） */
  static readonly SITE: string = '/site.json';

  /** 获取当前用户 */
  static readonly CURRENT_USER: string = '/session/current.json';

  /** 获取用户信息 */
  static userProfile(username: string): string {
    return `/u/${username}.json`;
  }

  /** 获取用户摘要 */
  static userSummary(username: string): string {
    return `/u/${username}/summary.json`;
  }

  /** 获取关注列表 */
  static userFollowing(username: string): string {
    return `/u/${username}/follow/following`;
  }

  /** 获取粉丝列表 */
  static userFollowers(username: string): string {
    return `/u/${username}/follow/followers`;
  }

  /** 关注/取消关注用户 */
  static followUser(username: string): string {
    return `/follow/${username}`;
  }

  /** 更新用户通知级别 */
  static userNotificationLevel(username: string): string {
    return `/u/${username}/notification_level.json`;
  }

  /** 获取通知 */
  static readonly NOTIFICATIONS: string = '/notifications';

  /** 标记通知已读 */
  static readonly NOTIFICATIONS_MARK_READ: string = '/notifications/mark-read';

  /** 分类下话题 */
  static categoryTopics(slug: string, id: number): string {
    return `/c/${slug}/${id}/l/latest.json`;
  }

  /** 搜索 */
  static readonly SEARCH: string = '/search.json';

  /** 用户动态（user_actions） */
  static readonly USER_ACTIONS: string = '/user_actions.json';

  /** 用户回应（discourse-reactions 插件） */
  static readonly USER_REACTIONS: string = '/discourse-reactions/posts/reactions.json';

  /** 获取帖子回复列表 */
  static postReplies(postId: number): string {
    return `/posts/${postId}/replies`;
  }

  /** 获取帖子详情（含 raw 等字段） */
  static postDetail(postId: number): string {
    return `/posts/${postId}.json`;
  }

  /** 创建帖子 / 回复 */
  static readonly POSTS: string = '/posts.json';

  /** 获取指定草稿 */
  static draft(draftKey: string): string {
    return `/drafts/${draftKey}.json`;
  }

  /** 草稿保存 */
  static readonly DRAFTS: string = '/drafts.json';

  /** 删除指定草稿 */
  static deleteDraft(draftKey: string): string {
    return `/drafts/${draftKey}.json`;
  }

  /** 帖子投票 */
  static readonly POLLS_VOTE: string = '/polls/vote';

  /** CSRF Token */
  static readonly CSRF: string = '/session/csrf.json';

  /** 点赞 */
  static readonly POST_ACTION: string = '/post_actions.json';

  /** 书签 */
  static readonly BOOKMARKS: string = '/bookmarks.json';

  /** 批量书签操作 */
  static readonly BOOKMARKS_BULK: string = '/bookmarks/bulk.json';

  /** 单个书签 */
  static bookmark(id: number): string {
    return `/bookmarks/${id}.json`;
  }

  /** 获取用户书签 */
  static userBookmarks(username: string): string {
    return `/u/${username}/bookmarks.json`;
  }

  /** 获取当前用户创建的话题 */
  static userCreatedTopics(username: string): string {
    return `/topics/created-by/${username}.json`;
  }

  /** 获取用户徽章 */
  static userBadges(username: string): string {
    return `/user-badges/${username.toLowerCase()}.json`;
  }

  /** 获取单个徽章详情 */
  static badge(id: number): string {
    return `/badges/${id}.json`;
  }

  /** 获取徽章获得者 */
  static readonly USER_BADGES: string = '/user_badges.json';

  /** 搜索标签（用于标签选择弹层） */
  static readonly TAG_SEARCH: string = '/tags/filter/search';
}
