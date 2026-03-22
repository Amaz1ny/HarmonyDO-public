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

  private static parseNumber(value: Object | null | undefined): number {
    if (value === undefined || value === null) {
      return 0;
    }
    const parsed: number = Number(value.toString());
    return isNaN(parsed) ? 0 : parsed;
  }

  private static injectPosterUsers(topics: Topic[], userMap: Map<number, TopicUser>): void {
    if (userMap.size <= 0) {
      return;
    }
    for (let i = 0; i < topics.length; i++) {
      const topic: Topic = topics[i];
      if (topic.posters.length === 0) {
        continue;
      }
      for (let j = 0; j < topic.posters.length; j++) {
        const poster: TopicPoster = topic.posters[j];
        if (poster.user !== null) {
          continue;
        }
        if (userMap.has(poster.userId)) {
          poster.user = userMap.get(poster.userId) as TopicUser;
        }
      }
    }
  }

  private static cloneBookmarkItem(bookmarkJson: Record<string, Object>): Record<string, Object> {
    const out: Record<string, Object> = {};
    const keys: string[] = Object.keys(bookmarkJson);
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const value = bookmarkJson[key];
      if (value !== undefined) {
        out[key] = value;
      }
    }
    return out;
  }

  private static normalizeBookmarkTopic(
    bookmarkJson: Record<string, Object>,
    userMap: Map<number, TopicUser>
  ): Record<string, Object> {
    const topicJson: Record<string, Object> = TopicListResponse.cloneBookmarkItem(bookmarkJson);

    const bookmarkId: number = TopicListResponse.parseNumber(bookmarkJson['id']);
    if (bookmarkId > 0) {
      topicJson['_bookmark_id'] = bookmarkId;
    }

    const topicId: number = TopicListResponse.parseNumber(bookmarkJson['topic_id']);
    if (topicId > 0) {
      topicJson['id'] = topicId;
    }

    const bookmarkName = bookmarkJson['name'];
    if (bookmarkName !== undefined && bookmarkName !== null && bookmarkName.toString().trim().length > 0) {
      topicJson['_bookmark_name'] = bookmarkName.toString().trim();
    }

    const reminderAt = bookmarkJson['reminder_at'];
    if (reminderAt !== undefined && reminderAt !== null && reminderAt.toString().trim().length > 0) {
      topicJson['_bookmark_reminder_at'] = reminderAt.toString();
    }

    const bookmarkableType = bookmarkJson['bookmarkable_type'];
    if (bookmarkableType !== undefined && bookmarkableType !== null) {
      topicJson['_bookmarkable_type'] = bookmarkableType.toString();
      if (bookmarkableType.toString() === 'Post') {
        const linkedPostNumber: number = TopicListResponse.parseNumber(bookmarkJson['linked_post_number']);
        if (linkedPostNumber > 0) {
          topicJson['_bookmarked_post_number'] = linkedPostNumber;
        }
      }
    }

    const highestPostNumber: number = TopicListResponse.parseNumber(bookmarkJson['highest_post_number']);
    if (highestPostNumber > 0) {
      if (topicJson['posts_count'] === undefined || topicJson['posts_count'] === null) {
        topicJson['posts_count'] = highestPostNumber;
      }
      if (topicJson['reply_count'] === undefined || topicJson['reply_count'] === null) {
        topicJson['reply_count'] = highestPostNumber > 0 ? highestPostNumber - 1 : 0;
      }
    }

    if ((topicJson['last_posted_at'] === undefined || topicJson['last_posted_at'] === null) &&
      bookmarkJson['bumped_at'] !== undefined && bookmarkJson['bumped_at'] !== null) {
      topicJson['last_posted_at'] = bookmarkJson['bumped_at'].toString();
    }

    if (topicJson['like_count'] === undefined || topicJson['like_count'] === null) {
      topicJson['like_count'] = 0;
    }
    if (topicJson['views'] === undefined || topicJson['views'] === null) {
      topicJson['views'] = 0;
    }

    const userVal = bookmarkJson['user'];
    if (userVal !== undefined && userVal !== null && typeof userVal === 'object' && !Array.isArray(userVal)) {
      const userJson: Record<string, Object> = userVal as Record<string, Object>;
      const user: TopicUser = TopicUser.fromJson(userJson);
      if (user.id > 0) {
        userMap.set(user.id, user);
        if (topicJson['posters'] === undefined || topicJson['posters'] === null) {
          const poster: Record<string, Object> = {};
          poster['user_id'] = user.id;
          poster['description'] = 'Original Poster';
          poster['extras'] = 'latest';
          topicJson['posters'] = [poster];
        }
        if ((topicJson['last_poster_username'] === undefined || topicJson['last_poster_username'] === null) &&
          user.username.length > 0) {
          topicJson['last_poster_username'] = user.username;
        }
      }
    }

    return topicJson;
  }

  private static parseBookmarkTopics(
    bookmarksArray: Object[],
    userMap: Map<number, TopicUser>
  ): Topic[] {
    const topics: Topic[] = [];
    for (let i = 0; i < bookmarksArray.length; i++) {
      const item: Object = bookmarksArray[i];
      if (item === null || item === undefined || typeof item !== 'object' || Array.isArray(item)) {
        continue;
      }
      const topicJson: Record<string, Object> = TopicListResponse.normalizeBookmarkTopic(
        item as Record<string, Object>,
        userMap
      );
      topics.push(Topic.fromJson(topicJson));
    }
    return topics;
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

        TopicListResponse.injectPosterUsers(parsedTopics, userMap);

        response.topics = parsedTopics;
      }
      return response;
    }

    const userBookmarkListVal = json['user_bookmark_list'];
    if (userBookmarkListVal !== undefined && userBookmarkListVal !== null && typeof userBookmarkListVal === 'object' &&
      !Array.isArray(userBookmarkListVal)) {
      const userBookmarkList: Record<string, Object> = userBookmarkListVal as Record<string, Object>;
      const moreBookmarksUrl = userBookmarkList['more_bookmarks_url'];
      response.moreTopicsUrl = moreBookmarksUrl !== undefined && moreBookmarksUrl !== null
        ? moreBookmarksUrl.toString()
        : null;

      const perPageVal = userBookmarkList['per_page'];
      if (perPageVal !== undefined && perPageVal !== null) {
        const perPage: number = TopicListResponse.parseNumber(perPageVal);
        response.perPage = perPage > 0 ? perPage : response.perPage;
      }

      const bookmarksVal = userBookmarkList['bookmarks'];
      if (bookmarksVal !== undefined && bookmarksVal !== null && Array.isArray(bookmarksVal)) {
        response.topics = TopicListResponse.parseBookmarkTopics(bookmarksVal as Object[], userMap);
        TopicListResponse.injectPosterUsers(response.topics, userMap);
      }
      return response;
    }

    const bookmarksVal = json['bookmarks'];
    if (bookmarksVal !== undefined && bookmarksVal !== null && Array.isArray(bookmarksVal)) {
      const moreBookmarksUrl = json['more_bookmarks_url'];
      response.moreTopicsUrl = moreBookmarksUrl !== undefined && moreBookmarksUrl !== null
        ? moreBookmarksUrl.toString()
        : null;
      response.topics = TopicListResponse.parseBookmarkTopics(bookmarksVal as Object[], userMap);
      TopicListResponse.injectPosterUsers(response.topics, userMap);
    }

    return response;
  }
}
