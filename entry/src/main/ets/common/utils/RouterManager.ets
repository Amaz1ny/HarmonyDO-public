/**
 * 路由常量
 */
export class RouteConstants {
  static readonly PAGE_TOPIC_LIST: string = 'TopicList';
  static readonly PAGE_TOPIC_DETAIL: string = 'TopicDetail';
  static readonly PAGE_CATEGORY_TOPIC_LIST: string = 'CategoryTopicList';
  static readonly PAGE_PROFILE: string = 'Profile';
  static readonly PAGE_LOGIN: string = 'Login';
  static readonly PAGE_SEARCH: string = 'Search';
  static readonly PAGE_NOTIFICATIONS: string = 'Notifications';
  static readonly PAGE_SETTINGS: string = 'Settings';
  static readonly PAGE_BOOKMARKS: string = 'Bookmarks';
  static readonly PAGE_DRAFTS: string = 'Drafts';
  static readonly PAGE_MY_TOPICS: string = 'MyTopics';
  static readonly PAGE_MY_BADGES: string = 'MyBadges';
  static readonly PAGE_BROWSING_HISTORY: string = 'BrowsingHistory';
  static readonly PAGE_USER_PROFILE: string = 'UserProfile';
  static readonly PAGE_FOLLOW_LIST: string = 'FollowList';
  static readonly PAGE_BADGE_DETAIL: string = 'BadgeDetail';
  static readonly PAGE_IMAGE_PREVIEW: string = 'ImagePreview';
  static readonly PAGE_WEB_VIEW: string = 'WebView';
  static readonly PAGE_CF_CHALLENGE: string = 'CfChallenge';
  static readonly PAGE_TRUST_LEVEL: string = 'TrustLevel';
  static readonly PAGE_INVITE_LINKS: string = 'InviteLinks';
  static readonly PAGE_ABOUT_APP: string = 'AboutApp';
  static readonly PAGE_OPEN_SOURCE_INFO: string = 'OpenSourceInfo';
  static readonly PAGE_APP_LOGS: string = 'AppLogs';
  static readonly PAGE_FEATURE_SETTINGS: string = 'FeatureSettings';
}

/**
 * 话题详情路由参数（兼容旧入参：number topicId）
 */
export class TopicDetailRouteParam {
  topicId: number = 0;
  initialPostNumber: number = 0;

  constructor(topicId: number, initialPostNumber: number = 0) {
    this.topicId = topicId;
    this.initialPostNumber = initialPostNumber;
  }
}

/**
 * 图片预览路由参数
 */
export class ImagePreviewRouteParam {
  urls: string[] = [];
  initialIndex: number = 0;

  constructor(urls: string[], initialIndex: number = 0) {
    const list: string[] = [];
    if (urls !== undefined && urls !== null) {
      for (let i = 0; i < urls.length; i++) {
        const u: string = urls[i] !== undefined && urls[i] !== null ? (urls[i] as string).trim() : '';
        if (u.length > 0) list.push(u);
      }
    }
    this.urls = list;
    this.initialIndex = initialIndex;
  }
}

/**
 * 关注/粉丝列表路由参数
 */
export class FollowListRouteParam {
  username: string = '';
  isFollowing: boolean = true;

  constructor(username: string, isFollowing: boolean) {
    this.username = username;
    this.isFollowing = isFollowing;
  }
}

/**
 * 搜索页路由参数
 */
export class SearchRouteParam {
  initialQuery: string = '';
  initialInTypeValue: string = '';

  constructor(initialQuery: string = '', initialInTypeValue: string = '') {
    this.initialQuery = initialQuery !== undefined && initialQuery !== null ? initialQuery.trim() : '';
    this.initialInTypeValue = initialInTypeValue !== undefined && initialInTypeValue !== null
      ? initialInTypeValue.trim()
      : '';
  }
}

/**
 * 徽章详情路由参数
 */
export class BadgeDetailRouteParam {
  badgeId: number = 0;
  badgeSlug: string = '';
  username: string = '';

  constructor(badgeId: number, badgeSlug: string = '', username: string = '') {
    this.badgeId = badgeId;
    this.badgeSlug = badgeSlug !== undefined && badgeSlug !== null ? badgeSlug.trim() : '';
    this.username = username !== undefined && username !== null ? username.trim() : '';
  }
}

/**
 * 通用 WebView 路由参数
 */
export class WebViewRouteParam {
  url: string = '';
  title: string = '';

  constructor(url: string, title: string = '') {
    this.url = url !== undefined && url !== null ? url.trim() : '';
    this.title = title !== undefined && title !== null ? title.trim() : '';
  }
}

/**
 * 路由管理器
 * 封装 NavPathStack 操作
 */
export class RouterManager {
  private static pathStack: NavPathStack | null = null;

  /**
   * 初始化路由（在 Index 页面设置）
   */
  static init(pathStack: NavPathStack): void {
    RouterManager.pathStack = pathStack;
  }

  /**
   * 获取 NavPathStack
   */
  static getPathStack(): NavPathStack | null {
    return RouterManager.pathStack;
  }

  /**
   * 跳转到指定页面
   */
  static pushPath(name: string, param: Object | null = null): void {
    if (RouterManager.pathStack !== null) {
      if (param !== null) {
        RouterManager.pathStack.pushPath({ name: name, param: param });
      } else {
        RouterManager.pathStack.pushPath({ name: name });
      }
    }
  }

  /**
   * 返回上一页
   */
  static pop(): void {
    if (RouterManager.pathStack !== null) {
      RouterManager.pathStack.pop();
    }
  }

  /**
   * 替换当前页面
   */
  static replacePath(name: string, param: Object | null = null): void {
    if (RouterManager.pathStack !== null) {
      if (param !== null) {
        RouterManager.pathStack.replacePath({ name: name, param: param });
      } else {
        RouterManager.pathStack.replacePath({ name: name });
      }
    }
  }

  /**
   * 清空路由栈
   */
  static clear(): void {
    if (RouterManager.pathStack !== null) {
      RouterManager.pathStack.clear();
    }
  }

  /**
   * 跳转到话题详情
   */
  static pushTopicDetail(topicId: number, initialPostNumber: number = 0): void {
    if (initialPostNumber > 0) {
      RouterManager.pushPath(
        RouteConstants.PAGE_TOPIC_DETAIL,
        new TopicDetailRouteParam(topicId, initialPostNumber) as Object
      );
    } else {
      RouterManager.pushPath(RouteConstants.PAGE_TOPIC_DETAIL, topicId as Object);
    }
  }

  /**
   * 跳转到用户主页
   */
  static pushUserProfile(username: string): void {
    RouterManager.pushPath(RouteConstants.PAGE_USER_PROFILE, username as Object);
  }

  /**
   * 跳转到搜索页
   */
  static pushSearch(initialQuery: string = '', initialInTypeValue: string = ''): void {
    RouterManager.pushPath(
      RouteConstants.PAGE_SEARCH,
      new SearchRouteParam(initialQuery, initialInTypeValue) as Object
    );
  }

  /**
   * 跳转到关注/粉丝列表
   */
  static pushFollowList(username: string, isFollowing: boolean): void {
    RouterManager.pushPath(
      RouteConstants.PAGE_FOLLOW_LIST,
      new FollowListRouteParam(username, isFollowing) as Object
    );
  }

  /**
   * 跳转到登录页
   */
  static pushLogin(): void {
    RouterManager.pushPath(RouteConstants.PAGE_LOGIN);
  }

  static pushNotifications(): void {
    RouterManager.pushPath(RouteConstants.PAGE_NOTIFICATIONS);
  }

  static pushBookmarks(): void {
    RouterManager.pushPath(RouteConstants.PAGE_BOOKMARKS);
  }

  static pushDrafts(): void {
    RouterManager.pushPath(RouteConstants.PAGE_DRAFTS);
  }

  static pushMyTopics(): void {
    RouterManager.pushPath(RouteConstants.PAGE_MY_TOPICS);
  }

  static pushMyBadges(): void {
    RouterManager.pushPath(RouteConstants.PAGE_MY_BADGES);
  }

  static pushBrowsingHistory(): void {
    RouterManager.pushPath(RouteConstants.PAGE_BROWSING_HISTORY);
  }

  static pushTrustLevel(): void {
    RouterManager.pushPath(RouteConstants.PAGE_TRUST_LEVEL);
  }

  static pushInviteLinks(): void {
    RouterManager.pushPath(RouteConstants.PAGE_INVITE_LINKS);
  }

  static pushAboutApp(): void {
    RouterManager.pushPath(RouteConstants.PAGE_ABOUT_APP);
  }

  static pushOpenSourceInfo(): void {
    RouterManager.pushPath(RouteConstants.PAGE_OPEN_SOURCE_INFO);
  }

  static pushAppLogs(): void {
    RouterManager.pushPath(RouteConstants.PAGE_APP_LOGS);
  }

  static pushFeatureSettings(): void {
    RouterManager.pushPath(RouteConstants.PAGE_FEATURE_SETTINGS);
  }

  /**
   * 跳转到徽章详情
   */
  static pushBadgeDetail(badgeId: number, badgeSlug: string = '', username: string = ''): void {
    RouterManager.pushPath(
      RouteConstants.PAGE_BADGE_DETAIL,
      new BadgeDetailRouteParam(badgeId, badgeSlug, username) as Object
    );
  }

  /**
   * 打开图片预览
   */
  static pushImagePreview(urls: string[], initialIndex: number = 0): void {
    RouterManager.pushPath(
      RouteConstants.PAGE_IMAGE_PREVIEW,
      new ImagePreviewRouteParam(urls, initialIndex) as Object
    );
  }

  /**
   * 打开应用内 WebView
   */
  static pushWebView(url: string, title: string = ''): void {
    RouterManager.pushPath(
      RouteConstants.PAGE_WEB_VIEW,
      new WebViewRouteParam(url, title) as Object
    );
  }
}
