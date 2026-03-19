import { TimeUtils } from '../common/utils/TimeUtils';
import { UrlUtils } from '../common/utils/UrlUtils';

/**
 * Discourse 搜索结果响应模型
 * /search.json
 */
export class SearchResult {
  topics: SearchTopic[] = [];
  posts: SearchPost[] = [];
  users: SearchUser[] = [];
  groupedResult: GroupedSearchResult = new GroupedSearchResult();

  constructor() {
  }

  static empty(): SearchResult {
    return new SearchResult();
  }

  static fromJson(json: Record<string, Object>): SearchResult {
    const result = new SearchResult();

    // topics
    const topicMap: Map<number, SearchTopic> = new Map();
    const topicsVal = json['topics'];
    if (topicsVal !== undefined && topicsVal !== null) {
      const topicsArr = topicsVal as Object[];
      const topics: SearchTopic[] = [];
      for (let i = 0; i < topicsArr.length; i++) {
        const tJson = topicsArr[i] as Record<string, Object>;
        const t: SearchTopic = SearchTopic.fromJson(tJson);
        topics.push(t);
        if (t.id > 0) {
          topicMap.set(t.id, t);
        }
      }
      result.topics = topics;
    }

    // posts（关联 topic）
    const postsVal = json['posts'];
    if (postsVal !== undefined && postsVal !== null) {
      const postsArr = postsVal as Object[];
      const posts: SearchPost[] = [];
      for (let i = 0; i < postsArr.length; i++) {
        const pJson = postsArr[i] as Record<string, Object>;
        const topicIdVal = pJson['topic_id'];
        const topicId: number = topicIdVal !== undefined && topicIdVal !== null ? topicIdVal as number : 0;
        const topic: SearchTopic | null = topicMap.has(topicId) ? topicMap.get(topicId) as SearchTopic : null;
        posts.push(SearchPost.fromJson(pJson, topic));
      }
      result.posts = posts;
    }

    // users
    const usersVal = json['users'];
    if (usersVal !== undefined && usersVal !== null) {
      const usersArr = usersVal as Object[];
      const users: SearchUser[] = [];
      for (let i = 0; i < usersArr.length; i++) {
        const uJson = usersArr[i] as Record<string, Object>;
        users.push(SearchUser.fromJson(uJson));
      }
      result.users = users;
    }

    // grouped meta
    const groupedVal = json['grouped_search_result'];
    if (groupedVal !== undefined && groupedVal !== null) {
      result.groupedResult = GroupedSearchResult.fromJson(groupedVal as Record<string, Object>);
    }

    return result;
  }

  get isEmpty(): boolean {
    return this.topics.length === 0 && this.posts.length === 0 && this.users.length === 0;
  }

  get hasMorePosts(): boolean {
    return this.groupedResult.moreFullPageResults || this.groupedResult.morePosts;
  }

  get hasMoreUsers(): boolean {
    return this.groupedResult.moreUsers;
  }
}

/**
 * 搜索结果中的话题信息
 */
export class SearchTopic {
  id: number = 0;
  title: string = '';
  slug: string = '';
  categoryId: number | null = null;
  tags: string[] = [];
  postsCount: number = 0;
  views: number = 0;
  closed: boolean = false;
  archived: boolean = false;
  createdAt: Date | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): SearchTopic {
    const t = new SearchTopic();
    const idVal = json['id'];
    t.id = idVal !== undefined && idVal !== null ? idVal as number : 0;
    const titleVal = json['title'];
    t.title = titleVal !== undefined && titleVal !== null ? titleVal as string : '';
    const slugVal = json['slug'];
    t.slug = slugVal !== undefined && slugVal !== null ? slugVal as string : '';

    const catVal = json['category_id'];
    t.categoryId = catVal !== undefined && catVal !== null ? catVal as number : null;

    const tagsVal = json['tags'];
    if (tagsVal !== undefined && tagsVal !== null) {
      const tagsArr = tagsVal as Object[];
      const tags: string[] = [];
      for (let i = 0; i < tagsArr.length; i++) {
        const item = tagsArr[i];
        if (typeof item === 'string') tags.push(item as string);
      }
      t.tags = tags;
    }

    const postsCountVal = json['posts_count'];
    t.postsCount = postsCountVal !== undefined && postsCountVal !== null ? postsCountVal as number : 0;
    const viewsVal = json['views'];
    t.views = viewsVal !== undefined && viewsVal !== null ? viewsVal as number : 0;
    const closedVal = json['closed'];
    t.closed = closedVal !== undefined && closedVal !== null ? closedVal as boolean : false;
    const archivedVal = json['archived'];
    t.archived = archivedVal !== undefined && archivedVal !== null ? archivedVal as boolean : false;
    const createdAtVal = json['created_at'];
    t.createdAt = createdAtVal !== undefined && createdAtVal !== null ? TimeUtils.parseUtcTime(createdAtVal as string) : null;
    return t;
  }
}

/**
 * 搜索结果中的帖子
 */
export class SearchPost {
  id: number = 0;
  topicId: number = 0;
  username: string = '';
  avatarTemplate: string = '';
  createdAt: Date | null = null;
  likeCount: number = 0;
  blurb: string = '';
  postNumber: number = 1;
  topicTitleHeadline: string | null = null;
  topic: SearchTopic | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>, topic: SearchTopic | null): SearchPost {
    const p = new SearchPost();
    const idVal = json['id'];
    p.id = idVal !== undefined && idVal !== null ? idVal as number : 0;

    const topicIdVal = json['topic_id'];
    p.topicId = topicIdVal !== undefined && topicIdVal !== null ? topicIdVal as number : 0;

    const usernameVal = json['username'];
    p.username = usernameVal !== undefined && usernameVal !== null ? usernameVal as string : '';

    const avatarVal = json['avatar_template'];
    p.avatarTemplate = avatarVal !== undefined && avatarVal !== null ? avatarVal as string : '';

    const createdVal = json['created_at'];
    p.createdAt = createdVal !== undefined && createdVal !== null ? TimeUtils.parseUtcTime(createdVal as string) : null;

    const likeVal = json['like_count'];
    p.likeCount = likeVal !== undefined && likeVal !== null ? likeVal as number : 0;

    const blurbVal = json['blurb'];
    p.blurb = blurbVal !== undefined && blurbVal !== null ? blurbVal as string : '';

    const postNumberVal = json['post_number'];
    p.postNumber = postNumberVal !== undefined && postNumberVal !== null ? postNumberVal as number : 1;

    const headVal = json['topic_title_headline'];
    p.topicTitleHeadline = headVal !== undefined && headVal !== null ? headVal as string : null;

    p.topic = topic;
    return p;
  }

  getAvatarUrl(size: number = 120): string {
    return UrlUtils.getAvatarUrl(this.avatarTemplate, size);
  }
}

/**
 * 搜索到的用户
 */
export class SearchUser {
  id: number = 0;
  username: string = '';
  name: string | null = null;
  avatarTemplate: string = '';

  constructor() {
  }

  static fromJson(json: Record<string, Object>): SearchUser {
    const u = new SearchUser();
    const idVal = json['id'];
    u.id = idVal !== undefined && idVal !== null ? idVal as number : 0;
    const usernameVal = json['username'];
    u.username = usernameVal !== undefined && usernameVal !== null ? usernameVal as string : '';
    const nameVal = json['name'];
    u.name = nameVal !== undefined && nameVal !== null ? nameVal as string : null;
    const avatarVal = json['avatar_template'];
    u.avatarTemplate = avatarVal !== undefined && avatarVal !== null ? avatarVal as string : '';
    return u;
  }

  getAvatarUrl(size: number = 120): string {
    return UrlUtils.getAvatarUrl(this.avatarTemplate, size);
  }
}

/**
 * 分组结果元信息
 */
export class GroupedSearchResult {
  term: string = '';
  morePosts: boolean = false;
  moreUsers: boolean = false;
  moreCategories: boolean = false;
  moreFullPageResults: boolean = false;
  searchLogId: number | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): GroupedSearchResult {
    const g = new GroupedSearchResult();
    const termVal = json['term'];
    g.term = termVal !== undefined && termVal !== null ? termVal as string : '';
    const mpVal = json['more_posts'];
    g.morePosts = mpVal !== undefined && mpVal !== null ? mpVal as boolean : false;
    const muVal = json['more_users'];
    g.moreUsers = muVal !== undefined && muVal !== null ? muVal as boolean : false;
    const mcVal = json['more_categories'];
    g.moreCategories = mcVal !== undefined && mcVal !== null ? mcVal as boolean : false;
    const mfpVal = json['more_full_page_results'];
    g.moreFullPageResults = mfpVal !== undefined && mfpVal !== null ? mfpVal as boolean : false;
    const idVal = json['search_log_id'];
    g.searchLogId = idVal !== undefined && idVal !== null ? idVal as number : null;
    return g;
  }
}

