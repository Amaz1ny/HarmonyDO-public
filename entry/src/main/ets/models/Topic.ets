import { TimeUtils } from '../common/utils/TimeUtils';

/**
 * 标签模型
 */
export class Tag {
  id: number = 0;
  name: string = '';
  slug: string = '';

  constructor() {
  }

  static fromJson(raw: Object | string | number | boolean): Tag {
    const t: Tag = new Tag();
    if (raw === null || raw === undefined) {
      return t;
    }

    if (typeof raw === 'string') {
      t.name = (raw as string).trim();
      return t;
    }

    if (typeof raw === 'object') {
      const obj: Record<string, Object> = raw as Record<string, Object>;
      const idVal = obj['id'];
      if (idVal !== undefined && idVal !== null) {
        t.id = Number(idVal.toString());
      }

      const nameVal = obj['name'];
      if (nameVal !== undefined && nameVal !== null) {
        t.name = nameVal.toString().trim();
      }

      const slugVal = obj['slug'];
      if (slugVal !== undefined && slugVal !== null) {
        t.slug = slugVal.toString().trim();
      }
      return t;
    }

    t.name = raw.toString().trim();
    return t;
  }
}

/**
 * 话题相关的用户信息
 */
export class TopicUser {
  id: number = 0;
  username: string = '';
  avatarTemplate: string = '';

  constructor() {
  }

  static fromJson(json: Record<string, Object>): TopicUser {
    const u: TopicUser = new TopicUser();
    const idVal = json['id'];
    u.id = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;
    const usernameVal = json['username'];
    u.username = usernameVal !== undefined && usernameVal !== null ? usernameVal as string : '';
    const avatarVal = json['avatar_template'];
    u.avatarTemplate = avatarVal !== undefined && avatarVal !== null ? avatarVal as string : '';
    return u;
  }

  getAvatarUrl(size: number = 40): string {
    return this.avatarTemplate.replace('{size}', size.toString());
  }
}

/**
 * 话题海报（参与者）信息
 */
export class TopicPoster {
  userId: number = 0;
  description: string = '';
  extras: string = '';
  user: TopicUser | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): TopicPoster {
    const p: TopicPoster = new TopicPoster();
    const userIdVal = json['user_id'];
    p.userId = userIdVal !== undefined && userIdVal !== null ? Number(userIdVal.toString()) : 0;
    const descVal = json['description'];
    p.description = descVal !== undefined && descVal !== null ? descVal as string : '';
    const extrasVal = json['extras'];
    p.extras = extrasVal !== undefined && extrasVal !== null ? extrasVal as string : '';
    return p;
  }
}

/**
 * 话题数据模型
 */
export class Topic {
  id: number = 0;
  title: string = '';
  slug: string = '';
  postsCount: number = 0;
  replyCount: number = 0;
  views: number = 0;
  likeCount: number = 0;
  excerpt: string | null = null;
  createdAt: Date | null = null;
  lastPostedAt: Date | null = null;
  lastPosterUsername: string | null = null;
  categoryId: string = '0';
  pinned: boolean = false;
  visible: boolean = true;
  closed: boolean = false;
  archived: boolean = false;
  tags: Tag[] = [];
  posters: TopicPoster[] = [];

  // 已读状态
  unseen: boolean = false;
  unread: number = 0;
  newPosts: number = 0;
  lastReadPostNumber: number = 0;
  highestPostNumber: number = 0;

  // 书签相关（/u/{username}/bookmarks.json）
  bookmarkedPostNumber: number | null = null;
  bookmarkId: number | null = null;
  bookmarkName: string | null = null;
  bookmarkReminderAt: Date | null = null;
  bookmarkableType: string | null = null;

  // 已解决问题
  hasAcceptedAnswer: boolean = false;
  canHaveAnswer: boolean = false;

  constructor() {
  }

  /**
   * 从 JSON 解析 Topic
   */
  static fromJson(json: Record<string, Object>): Topic {
    const topic = new Topic();
    const idVal = json['id'];
    topic.id = idVal !== undefined && idVal !== null ? idVal as number : 0;

    const titleVal = json['title'];
    topic.title = titleVal !== undefined && titleVal !== null ? titleVal as string : '';

    const slugVal = json['slug'];
    topic.slug = slugVal !== undefined && slugVal !== null ? slugVal as string : '';

    const postsCountVal = json['posts_count'];
    topic.postsCount = postsCountVal !== undefined && postsCountVal !== null ? postsCountVal as number : 0;

    const replyCountVal = json['reply_count'];
    topic.replyCount = replyCountVal !== undefined && replyCountVal !== null ? replyCountVal as number : 0;

    const viewsVal = json['views'];
    topic.views = viewsVal !== undefined && viewsVal !== null ? viewsVal as number : 0;

    const likeCountVal = json['like_count'];
    topic.likeCount = likeCountVal !== undefined && likeCountVal !== null ? likeCountVal as number : 0;

    const excerptVal = json['excerpt'];
    topic.excerpt = excerptVal !== undefined && excerptVal !== null ? excerptVal as string : null;

    const createdAtVal = json['created_at'];
    topic.createdAt = createdAtVal !== undefined && createdAtVal !== null
      ? TimeUtils.parseUtcTime(createdAtVal as string) : null;

    const lastPostedAtVal = json['last_posted_at'];
    topic.lastPostedAt = lastPostedAtVal !== undefined && lastPostedAtVal !== null
      ? TimeUtils.parseUtcTime(lastPostedAtVal as string) : null;

    const lastPosterVal = json['last_poster_username'];
    topic.lastPosterUsername = lastPosterVal !== undefined && lastPosterVal !== null
      ? lastPosterVal as string : null;

    const catIdVal = json['category_id'];
    topic.categoryId = catIdVal !== undefined && catIdVal !== null ? catIdVal.toString() : '0';

    const pinnedVal = json['pinned'];
    topic.pinned = pinnedVal !== undefined && pinnedVal !== null ? pinnedVal as boolean : false;

    const visibleVal = json['visible'];
    topic.visible = visibleVal !== undefined && visibleVal !== null ? visibleVal as boolean : true;

    const closedVal = json['closed'];
    topic.closed = closedVal !== undefined && closedVal !== null ? closedVal as boolean : false;

    const archivedVal = json['archived'];
    topic.archived = archivedVal !== undefined && archivedVal !== null ? archivedVal as boolean : false;

    const unseenVal = json['unseen'];
    topic.unseen = unseenVal !== undefined && unseenVal !== null ? unseenVal as boolean : false;

    const unreadVal = json['unread_posts'];
    topic.unread = unreadVal !== undefined && unreadVal !== null ? unreadVal as number : 0;

    const newPostsVal = json['new_posts'];
    topic.newPosts = newPostsVal !== undefined && newPostsVal !== null ? newPostsVal as number : 0;

    const lastReadVal = json['last_read_post_number'];
    topic.lastReadPostNumber = lastReadVal !== undefined && lastReadVal !== null ? lastReadVal as number : 0;

    const highestVal = json['highest_post_number'];
    topic.highestPostNumber = highestVal !== undefined && highestVal !== null ? highestVal as number : 0;

    const bookmarkedPostVal = json['_bookmarked_post_number'];
    topic.bookmarkedPostNumber = bookmarkedPostVal !== undefined && bookmarkedPostVal !== null
      ? Number(bookmarkedPostVal.toString()) : null;

    const bookmarkIdVal = json['_bookmark_id'];
    topic.bookmarkId = bookmarkIdVal !== undefined && bookmarkIdVal !== null
      ? Number(bookmarkIdVal.toString()) : null;

    const bookmarkNameVal = json['_bookmark_name'];
    topic.bookmarkName = bookmarkNameVal !== undefined && bookmarkNameVal !== null
      ? bookmarkNameVal.toString() : null;

    const bookmarkReminderVal = json['_bookmark_reminder_at'];
    topic.bookmarkReminderAt = bookmarkReminderVal !== undefined && bookmarkReminderVal !== null
      ? TimeUtils.parseUtcTime(bookmarkReminderVal.toString()) : null;

    const bookmarkableTypeVal = json['_bookmarkable_type'];
    topic.bookmarkableType = bookmarkableTypeVal !== undefined && bookmarkableTypeVal !== null
      ? bookmarkableTypeVal.toString() : null;

    const hasAcceptedVal = json['has_accepted_answer'];
    topic.hasAcceptedAnswer = hasAcceptedVal !== undefined && hasAcceptedVal !== null
      ? hasAcceptedVal as boolean : false;

    const canHaveVal = json['can_have_answer'];
    topic.canHaveAnswer = canHaveVal !== undefined && canHaveVal !== null ? canHaveVal as boolean : false;

    // 解析 tags
    const tagsVal = json['tags'];
    if (tagsVal !== undefined && tagsVal !== null) {
      const tagsArray = tagsVal as Object[];
      const parsedTags: Tag[] = [];
      for (let i = 0; i < tagsArray.length; i++) {
        const tagItem: Object = tagsArray[i];
        const tag: Tag = Tag.fromJson(tagItem);
        if (tag.name.length > 0) {
          parsedTags.push(tag);
        }
      }
      topic.tags = parsedTags;
    }

    // 解析 posters（需要 TopicListResponse 注入 user 详情）
    const postersVal = json['posters'];
    if (postersVal !== undefined && postersVal !== null) {
      const postersArray = postersVal as Object[];
      const parsedPosters: TopicPoster[] = [];
      for (let i = 0; i < postersArray.length; i++) {
        const posterJson: Record<string, Object> = postersArray[i] as Record<string, Object>;
        parsedPosters.push(TopicPoster.fromJson(posterJson));
      }
      topic.posters = parsedPosters;
    }

    return topic;
  }
}

/**
 * 话题列表响应
 */
export class TopicListResponse {
  topics: Topic[] = [];
  moreTopicsUrl: string | null = null;
  perPage: number = 30;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): TopicListResponse {
    const response = new TopicListResponse();

    // 解析 users（用于 posters.avatar）
    const userMap: Map<number, TopicUser> = new Map();
    const usersVal = json['users'];
    if (usersVal !== undefined && usersVal !== null) {
      const usersArray = usersVal as Object[];
      for (let i = 0; i < usersArray.length; i++) {
        const userJson: Record<string, Object> = usersArray[i] as Record<string, Object>;
        const u: TopicUser = TopicUser.fromJson(userJson);
        if (u.id > 0) {
          userMap.set(u.id, u);
        }
      }
    }

    const topicListVal = json['topic_list'];
    if (topicListVal !== undefined && topicListVal !== null) {
      const topicList = topicListVal as Record<string, Object>;
      const moreUrl = topicList['more_topics_url'];
      response.moreTopicsUrl = moreUrl !== undefined && moreUrl !== null ? moreUrl as string : null;

      const perPageVal = topicList['per_page'];
      response.perPage = perPageVal !== undefined && perPageVal !== null ? perPageVal as number : 30;

      const topicsArr = topicList['topics'];
      if (topicsArr !== undefined && topicsArr !== null) {
        const topicsArray = topicsArr as Object[];
        const parsedTopics: Topic[] = [];
        for (let i = 0; i < topicsArray.length; i++) {
          const topicJson = topicsArray[i] as Record<string, Object>;
          parsedTopics.push(Topic.fromJson(topicJson));
        }

        // 注入 posters.user
        if (userMap.size > 0) {
          for (let i = 0; i < parsedTopics.length; i++) {
            const t: Topic = parsedTopics[i];
            if (t.posters.length === 0) continue;
            for (let j = 0; j < t.posters.length; j++) {
              const p: TopicPoster = t.posters[j];
              if (p.user !== null) continue;
              if (userMap.has(p.userId)) {
                p.user = userMap.get(p.userId) as TopicUser;
              }
            }
          }
        }

        response.topics = parsedTopics;
      }
    }
    return response;
  }
}
