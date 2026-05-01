import { TopicListPage } from '../views/pages/TopicListPage';
import { TopicDetailPage } from '../views/pages/TopicDetailPage';
import { CategoryTopicPage } from '../views/pages/CategoryTopicPage';
import { ProfilePage } from '../views/pages/ProfilePage';
import { SearchPage } from '../views/pages/SearchPage';
import { UserProfilePage } from '../views/pages/UserProfilePage';
import { FollowListPage } from '../views/pages/FollowListPage';
import { BadgeDetailPage } from '../views/pages/BadgeDetailPage';
import { ImagePreviewPage } from '../views/pages/ImagePreviewPage';
import { WebViewPage } from '../views/pages/WebViewPage';
import { LoginPage } from '../views/pages/LoginPage';
import { CfChallengePage } from '../views/pages/CfChallengePage';
import { NotificationsPage } from '../views/pages/NotificationsPage';
import { BookmarksPage } from '../views/pages/BookmarksPage';
import { DraftsPage } from '../views/pages/DraftsPage';
import { MyTopicsPage } from '../views/pages/MyTopicsPage';
import { MyBadgesPage } from '../views/pages/MyBadgesPage';
import { BrowsingHistoryPage } from '../views/pages/BrowsingHistoryPage';
import { TrustLevelPage } from '../views/pages/TrustLevelPage';
import { InviteLinksPage } from '../views/pages/InviteLinksPage';
import { AboutAppPage } from '../views/pages/AboutAppPage';
import { OpenSourceInfoPage } from '../views/pages/OpenSourceInfoPage';
import { AppLogsPage } from '../views/pages/AppLogsPage';
import { FeatureSettingsPage } from '../views/pages/FeatureSettingsPage';
import { DataManagementPage } from '../views/pages/DataManagementPage';
import { CfRefreshHost } from '../views/components/CfRefreshHost';
import { ReadLaterBubble } from '../views/components/ReadLaterBubble';
import { Topic } from '../models/Topic';
import { Category } from '../models/Category';
import { User } from '../models/User';
import { TopicTrackingService } from '../services/messagebus/TopicTrackingService';
import { PreloadedDataService } from '../services/messagebus/PreloadedDataService';
import { NotificationTrackingService } from '../services/messagebus/NotificationTrackingService';
import { AuthService } from '../services/auth/AuthService';
import { CfChallengeService } from '../services/network/CfChallengeService';
import {
  RouterManager,
  RouteConstants,
  TopicDetailRouteParam,
  SearchRouteParam,
  BadgeDetailRouteParam,
  ImagePreviewRouteParam,
  FollowListRouteParam,
  WebViewRouteParam
} from '../common/utils/RouterManager';
import {
  HdsAnimationMode,
  HdsNavigation,
  HdsTabs,
  HdsTabsController,
  HdsTabsFloatingStyle,
  hdsMaterial
} from '@kit.UIDesignKit';
import { WindowManager } from '../common/utils/WindowManager';
import {
  FLOATING_TAB_BAR_HEIGHT_VP,
  FLOATING_TAB_BAR_MARGIN_H_VP,
  FLOATING_TAB_BAR_MARGIN_BOTTOM_VP,
  FLOATING_TAB_BAR_OFFSET_UP_VP,
  FLOATING_TAB_BAR_OPACITY,
  FLOATING_TAB_BAR_RADIUS_VP,
  FLOATING_TAB_BAR_SHADOW_OFFSET_Y_VP,
  FLOATING_TAB_BAR_SHADOW_RADIUS_VP,
  FLOATING_TAB_BAR_WIDTH_LARGE_VP,
  FLOATING_TAB_BAR_WIDTH_MEDIUM_VP,
  FLOATING_TAB_BAR_WIDTH_SMALL_VP
} from '../common/constants/LayoutConstants';
import { SmartAvatar } from '../views/components/SmartAvatar';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppLogService } from '../common/utils/AppLogService';

const TAG: string = 'Index';
const FLOATING_TAB_SWITCH_ANIM_DURATION: number = 260;

/**
 * 应用主页面 -
 *
 * 底部导航只有 2 个 Tab：
 * - 首页（🏠）
 * - 我的（👤）
 *
 * 使用 Navigation + NavPathStack 管理路由
 */
@Entry
@ComponentV2
struct Index {
  @Local currentIndex: number = 0;
  @Local tabBarVisibility: number = 1;
  @Local pathStack: NavPathStack = new NavPathStack();
  @Local currentTabUser: User | null = null;
  @Local currentTabUsername: string = '';
  @Local showCfChallengeOverlay: boolean = false;
  @Local rootWidthVp: number = 0;

  private tabsController: HdsTabsController = new HdsTabsController();
  private authStateListener: (() => void) | null = null;
  private backgroundSessionSyncId: number = 0;
  private backgroundSessionBootstrapped: boolean = false;
  private lastBackgroundLoggedIn: boolean | null = null;

  aboutToAppear(): void {
    RouterManager.init(this.pathStack);
    CfChallengeService.getInstance().setOverlayVisibilityListener((visible: boolean) => {
      this.showCfChallengeOverlay = visible;
    });
    this.attachAuthStateListener();
    this.syncProfileTabUser().catch(() => {
    });
    this.syncBackgroundSessionSafely();
  }

  aboutToDisappear(): void {
    CfChallengeService.getInstance().setOverlayVisibilityListener(null);
    this.detachAuthStateListener();
  }

  private getEffectiveTabBarVisibility(): number {
    return this.currentIndex === 0 ? this.tabBarVisibility : 1;
  }

  private getBottomSafeHeight(): number {
    return WindowManager.getSystemAvoidAreaBottomVp();
  }

  private getHdsFloatingTabBarBottomMargin(): number {
    return this.getBottomSafeHeight() + FLOATING_TAB_BAR_MARGIN_BOTTOM_VP + FLOATING_TAB_BAR_OFFSET_UP_VP;
  }

  private getHdsFloatingTabBarGradientMaskHeight(): number {
    return FLOATING_TAB_BAR_HEIGHT_VP + this.getHdsFloatingTabBarBottomMargin() + 16;
  }

  private getFloatingTabBarHideTranslate(): number {
    return FLOATING_TAB_BAR_HEIGHT_VP + this.getHdsFloatingTabBarBottomMargin() + 24;
  }

  private parseAreaDimension(value: number | string | Resource): number {
    if (typeof value === 'number') {
      return value as number;
    }
    if (typeof value === 'string') {
      const parsed: number = Number((value as string).replace('vp', ''));
      return isNaN(parsed) ? 0 : parsed;
    }
    return 0;
  }

  private updateRootWidthVp(widthValue: number | string | Resource): void {
    const nextWidth: number = this.parseAreaDimension(widthValue);
    if (nextWidth <= 0 || Math.abs(nextWidth - this.rootWidthVp) <= 0.5) {
      return;
    }
    this.rootWidthVp = nextWidth;
  }

  private getHdsFloatingTabBarShadowWidthVp(): number {
    // 与 HDS 悬浮栏 small / medium / large 分档保持一致，让阴影底层贴合原生胶囊宽度。
    if (this.rootWidthVp <= 0 || this.rootWidthVp < 600) {
      return FLOATING_TAB_BAR_WIDTH_SMALL_VP;
    }
    if (this.rootWidthVp < 840) {
      return FLOATING_TAB_BAR_WIDTH_MEDIUM_VP;
    }
    return FLOATING_TAB_BAR_WIDTH_LARGE_VP;
  }

  private getHdsTabsFloatingStyle(): HdsTabsFloatingStyle {
    return {
      // API 23 官方能力：HdsTabsFloatingStyle.barWidth 支持按 HdsTabs 宽度分档设置悬浮页签栏宽度。
      // 这里使用固定 vp 分档，不再使用百分比，规避真机上百分比宽度导致胶囊贴右/越界的问题。
      barWidth: {
        smallWidth: FLOATING_TAB_BAR_WIDTH_SMALL_VP,
        mediumWidth: FLOATING_TAB_BAR_WIDTH_MEDIUM_VP,
        largeWidth: FLOATING_TAB_BAR_WIDTH_LARGE_VP
      },
      barSideMargin: FLOATING_TAB_BAR_MARGIN_H_VP,
      barBottomMargin: this.getHdsFloatingTabBarBottomMargin(),
      gradientMask: {
        maskColor: $r('app.color.tab_glass_mask'),
        maskHeight: this.getHdsFloatingTabBarGradientMaskHeight()
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      thermoCtrl: true,
      barOpacity: FLOATING_TAB_BAR_OPACITY
    };
  }

  private switchMainTab(index: number): void {
    if (this.currentIndex === index) {
      return;
    }
    const uiContext = this.getUIContext();
    if (uiContext !== undefined && uiContext !== null) {
      uiContext.animateTo({ duration: FLOATING_TAB_SWITCH_ANIM_DURATION, curve: Curve.EaseInOut }, () => {
        this.setMainTabIndex(index, HdsAnimationMode.CLICK_ANIMATION);
      });
    } else {
      this.setMainTabIndex(index, HdsAnimationMode.CLICK_ANIMATION);
    }
  }

  private updateTabBarVisibility(next: number): void {
    const v: number = Math.max(0, Math.min(1, next));
    if (Math.abs(v - this.tabBarVisibility) <= 0.001) {
      return;
    }
    const wasVisible: boolean = this.getEffectiveTabBarVisibility() > 0.05;
    this.tabBarVisibility = v;
    const shouldVisible: boolean = this.getEffectiveTabBarVisibility() > 0.05;
    if (wasVisible !== shouldVisible) {
      this.applyNativeTabBarVisibility(shouldVisible, HdsAnimationMode.SCROLL_ANIMATION);
    }
  }

  private setMainTabIndex(index: number, mode: HdsAnimationMode): void {
    this.currentIndex = index;
    this.applyNativeTabBarVisibilityForIndex(index, mode);
  }

  private applyNativeTabBarVisibilityForIndex(index: number, mode: HdsAnimationMode): void {
    const shouldVisible: boolean = index === 0 ? this.tabBarVisibility > 0.05 : true;
    this.applyNativeTabBarVisibility(shouldVisible, mode);
  }

  private applyNativeTabBarVisibility(visible: boolean, mode: HdsAnimationMode): void {
    try {
      if (visible) {
        this.tabsController.applyShowAnimation(mode);
      } else {
        this.tabsController.applyHideAnimation(mode);
      }
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Apply HdsTabs floating animation failed. Cause: %{public}s', JSON.stringify(err));
    }
  }

  private attachAuthStateListener(): void {
    if (this.authStateListener !== null) {
      return;
    }
    this.authStateListener = () => {
      this.syncProfileTabUser().catch(() => {
      });
      this.syncBackgroundSessionSafely();
    };
    AuthService.getInstance().addListener(this.authStateListener);
  }

  private detachAuthStateListener(): void {
    if (this.authStateListener === null) {
      return;
    }
    AuthService.getInstance().removeListener(this.authStateListener);
    this.authStateListener = null;
  }

  private async syncProfileTabUser(): Promise<void> {
    const auth: AuthService = AuthService.getInstance();
    await auth.init();
    this.currentTabUser = auth.getCurrentUser();
    this.currentTabUsername = auth.getCurrentUsername().trim();
  }

  private syncBackgroundSessionSafely(): void {
    this.syncBackgroundSession().catch((err: Object) => {
      this.backgroundSessionBootstrapped = false;
      this.lastBackgroundLoggedIn = null;
      hilog.warn(0x0000, TAG, 'Sync background session failed: %{public}s', JSON.stringify(err));
      AppLogService.getInstance().error('general', 'sync background session failed', TAG, JSON.stringify(err));
    });
  }

  private async syncBackgroundSession(): Promise<void> {
    const requestId: number = this.backgroundSessionSyncId + 1;
    this.backgroundSessionSyncId = requestId;

    const auth: AuthService = AuthService.getInstance();
    await auth.init();
    if (requestId !== this.backgroundSessionSyncId) {
      return;
    }

    const loggedIn: boolean = auth.getIsLoggedIn();
    if (this.backgroundSessionBootstrapped && this.lastBackgroundLoggedIn === loggedIn) {
      return;
    }

    const tracking: TopicTrackingService = TopicTrackingService.getInstance();
    const notificationTracking: NotificationTrackingService = NotificationTrackingService.getInstance();
    const preloaded: PreloadedDataService = PreloadedDataService.getInstance();

    tracking.stop();
    notificationTracking.stop();
    await preloaded.clearSessionScopedState();
    if (requestId !== this.backgroundSessionSyncId) {
      return;
    }

    hilog.info(
      0x0000,
      TAG,
      'Apply background session mode loggedIn=%{public}s',
      loggedIn ? 'Y' : 'N'
    );
    await tracking.start(loggedIn);
    if (requestId !== this.backgroundSessionSyncId) {
      return;
    }
    if (loggedIn) {
      await notificationTracking.start();
      if (requestId !== this.backgroundSessionSyncId) {
        notificationTracking.stop();
        return;
      }
    } else {
      notificationTracking.stop();
      notificationTracking.resetState();
    }
    this.backgroundSessionBootstrapped = true;
    this.lastBackgroundLoggedIn = loggedIn;
  }

  private shouldShowProfileTabAvatar(): boolean {
    return this.currentTabUser !== null || this.currentTabUsername.length > 0;
  }

  private getProfileTabAvatarUrl(): string {
    if (this.currentTabUser === null) {
      return '';
    }
    return (this.currentTabUser as User).getAvatarUrl(64);
  }

  private getProfileTabFallbackText(): string {
    if (this.currentTabUsername.length > 0) {
      return this.currentTabUsername;
    }
    return '我';
  }

  private getStringParam(param: Object): string {
    return typeof param === 'string' ? param as string : '';
  }

  private parseTopicDetailParam(param: Object): TopicDetailRouteParam {
    if (typeof param === 'number') {
      return new TopicDetailRouteParam(param as number, 0);
    }
    const obj: TopicDetailRouteParam = param as TopicDetailRouteParam;
    const topicId: number = obj.topicId !== undefined && obj.topicId !== null ? obj.topicId as number : 0;
    const initialPostNumber: number = obj.initialPostNumber !== undefined && obj.initialPostNumber !== null
      ? obj.initialPostNumber as number : 0;
    return new TopicDetailRouteParam(topicId, initialPostNumber);
  }

  private parseSearchParam(param: Object): SearchRouteParam {
    if (param === null || param === undefined) {
      return new SearchRouteParam('', '');
    }
    if (typeof param === 'string') {
      return new SearchRouteParam(param as string, '');
    }
    const obj: SearchRouteParam = param as SearchRouteParam;
    const initialQuery: string = obj.initialQuery !== undefined && obj.initialQuery !== null
      ? obj.initialQuery as string
      : '';
    const initialInTypeValue: string = obj.initialInTypeValue !== undefined && obj.initialInTypeValue !== null
      ? obj.initialInTypeValue as string
      : '';
    return new SearchRouteParam(initialQuery, initialInTypeValue);
  }

  private parseBadgeDetailParam(param: Object): BadgeDetailRouteParam {
    if (param === null || param === undefined) {
      return new BadgeDetailRouteParam(0, '', '');
    }
    const obj: BadgeDetailRouteParam = param as BadgeDetailRouteParam;
    const badgeId: number = obj.badgeId !== undefined && obj.badgeId !== null ? obj.badgeId as number : 0;
    const badgeSlug: string = obj.badgeSlug !== undefined && obj.badgeSlug !== null ? obj.badgeSlug as string : '';
    const username: string = obj.username !== undefined && obj.username !== null ? obj.username as string : '';
    return new BadgeDetailRouteParam(badgeId, badgeSlug, username);
  }

  private parseImagePreviewParam(param: Object): ImagePreviewRouteParam {
    const obj: ImagePreviewRouteParam = param as ImagePreviewRouteParam;
    const urls: string[] = obj.urls !== undefined && obj.urls !== null ? obj.urls as string[] : [];
    const initialIndex: number = obj.initialIndex !== undefined && obj.initialIndex !== null ? obj.initialIndex as number : 0;
    return new ImagePreviewRouteParam(urls, initialIndex);
  }

  private parseFollowListParam(param: Object): FollowListRouteParam {
    const obj: FollowListRouteParam = param as FollowListRouteParam;
    const username: string = obj.username !== undefined && obj.username !== null ? obj.username as string : '';
    const isFollowing: boolean = obj.isFollowing !== undefined && obj.isFollowing !== null
      ? obj.isFollowing as boolean : true;
    return new FollowListRouteParam(username, isFollowing);
  }

  private parseWebViewParam(param: Object): WebViewRouteParam {
    const obj: WebViewRouteParam = param as WebViewRouteParam;
    const url: string = obj.url !== undefined && obj.url !== null ? obj.url as string : '';
    const title: string = obj.title !== undefined && obj.title !== null ? obj.title as string : '';
    return new WebViewRouteParam(url, title);
  }

  @Builder
  routeMap(name: string, param: Object) {
    if (name === RouteConstants.PAGE_TOPIC_DETAIL) {
      TopicDetailPage({
        topicId: this.parseTopicDetailParam(param).topicId,
        initialPostNumber: this.parseTopicDetailParam(param).initialPostNumber
      })
    } else if (name === RouteConstants.PAGE_CATEGORY_TOPIC_LIST) {
      CategoryTopicPage({ category: param as Category })
    } else if (name === RouteConstants.PAGE_SEARCH) {
      SearchPage({
        initialQuery: this.parseSearchParam(param).initialQuery,
        initialInTypeValue: this.parseSearchParam(param).initialInTypeValue
      })
    } else if (name === RouteConstants.PAGE_NOTIFICATIONS) {
      NotificationsPage()
    } else if (name === RouteConstants.PAGE_BOOKMARKS) {
      BookmarksPage()
    } else if (name === RouteConstants.PAGE_DRAFTS) {
      DraftsPage()
    } else if (name === RouteConstants.PAGE_MY_TOPICS) {
      MyTopicsPage()
    } else if (name === RouteConstants.PAGE_MY_BADGES) {
      MyBadgesPage()
    } else if (name === RouteConstants.PAGE_BROWSING_HISTORY) {
      BrowsingHistoryPage()
    } else if (name === RouteConstants.PAGE_BADGE_DETAIL) {
      BadgeDetailPage({
        badgeId: this.parseBadgeDetailParam(param).badgeId,
        badgeSlug: this.parseBadgeDetailParam(param).badgeSlug,
        username: this.parseBadgeDetailParam(param).username
      })
    } else if (name === RouteConstants.PAGE_USER_PROFILE) {
      UserProfilePage({ username: this.getStringParam(param) })
    } else if (name === RouteConstants.PAGE_FOLLOW_LIST) {
      FollowListPage({
        username: this.parseFollowListParam(param).username,
        isFollowing: this.parseFollowListParam(param).isFollowing
      })
    } else if (name === RouteConstants.PAGE_IMAGE_PREVIEW) {
      ImagePreviewPage({
        urls: this.parseImagePreviewParam(param).urls,
        initialIndex: this.parseImagePreviewParam(param).initialIndex
      })
    } else if (name === RouteConstants.PAGE_WEB_VIEW) {
      WebViewPage({
        url: this.parseWebViewParam(param).url,
        title: this.parseWebViewParam(param).title
      })
    } else if (name === RouteConstants.PAGE_LOGIN) {
      LoginPage()
    } else if (name === RouteConstants.PAGE_CF_CHALLENGE) {
      CfChallengePage()
    } else if (name === RouteConstants.PAGE_TRUST_LEVEL) {
      TrustLevelPage()
    } else if (name === RouteConstants.PAGE_INVITE_LINKS) {
      InviteLinksPage()
    } else if (name === RouteConstants.PAGE_ABOUT_APP) {
      AboutAppPage()
    } else if (name === RouteConstants.PAGE_OPEN_SOURCE_INFO) {
      OpenSourceInfoPage()
    } else if (name === RouteConstants.PAGE_APP_LOGS) {
      AppLogsPage()
    } else if (name === RouteConstants.PAGE_FEATURE_SETTINGS) {
      FeatureSettingsPage()
    } else if (name === RouteConstants.PAGE_DATA_MANAGEMENT) {
      DataManagementPage()
    }
  }

  build() {
    Stack() {
      HdsNavigation(this.pathStack) {
        Stack({ alignContent: Alignment.Bottom }) {
          // Cloudflare: cf_clearance 自动续期宿主（隐藏 Web）
          CfRefreshHost()

          HdsTabs({ controller: this.tabsController, index: this.currentIndex }) {
            // Tab 1: 首页
            TabContent() {
              TopicListPage({
                onTopicClick: (topic: Topic) => {
                  this.pathStack.pushPath({ name: RouteConstants.PAGE_TOPIC_DETAIL, param: topic.id });
                },
                onBarVisibilityChange: (v: number) => {
                  this.updateTabBarVisibility(v);
                }
              })
            }
            .tabBar(this.TabBarItem(0, '首页', $r('sys.symbol.house'), $r('sys.symbol.house_fill')))

            // Tab 2: 我的
            TabContent() {
              ProfilePage()
            }
            .tabBar(this.TabBarItem(1, '我的', $r('sys.symbol.person'), $r('sys.symbol.person_fill')))
          }
          // API 23：使用 HDS 原生悬浮页签与沉浸光感材质，不再手写外层玻璃胶囊容器
          .barOverlap(true)
          .vertical(false)
          .barPosition(BarPosition.End)
          .barFloatingStyle(this.getHdsTabsFloatingStyle())
          .onChange((index: number) => {
            this.setMainTabIndex(index, HdsAnimationMode.CLICK_ANIMATION);
          })
          .scrollable(false)

          this.FloatingTabBarShadowPlate()

          ReadLaterBubble()
        }
        .width('100%')
        .height('100%')
        .onAreaChange((_: Area, newArea: Area) => {
          this.updateRootWidthVp(newArea.width);
        })
      }
      .navDestination(this.routeMap)
      .hideTitleBar(true)
      .hideToolBar(true)
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])

      if (this.showCfChallengeOverlay) {
        CfChallengePage({ overlayMode: true })
          .width('100%')
          .height('100%')
          .zIndex(1000)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private FloatingTabBarShadowPlate() {
    Stack() {
    }
    .width(this.getHdsFloatingTabBarShadowWidthVp())
    .height(FLOATING_TAB_BAR_HEIGHT_VP)
    .borderRadius(FLOATING_TAB_BAR_RADIUS_VP)
    .backgroundColor($r('app.color.tab_floating_surface_tint'))
    .border({ width: 0.5, color: $r('app.color.tab_floating_outline') })
    .shadow({
      radius: FLOATING_TAB_BAR_SHADOW_RADIUS_VP,
      color: $r('app.color.tab_floating_shadow'),
      offsetX: 0,
      offsetY: FLOATING_TAB_BAR_SHADOW_OFFSET_Y_VP
    })
    .opacity(this.getEffectiveTabBarVisibility())
    .margin({ bottom: this.getHdsFloatingTabBarBottomMargin() })
    .translate({ x: 0, y: (1 - this.getEffectiveTabBarVisibility()) * this.getFloatingTabBarHideTranslate() })
    .enabled(false)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  TabBarItem(index: number, label: string, icon: Resource, selectedIcon: Resource) {
    Column() {
      // 选中时显示背景胶囊
      if (this.currentIndex === index) {
        Column() {
          if (index === 1 && this.shouldShowProfileTabAvatar()) {
            SmartAvatar({
              avatarUrl: this.getProfileTabAvatarUrl(),
              avatarSize: 24,
              avatarRadius: 12,
              fallbackText: this.getProfileTabFallbackText(),
              bgColor: '#E8EAF0'
            })
          } else {
            SymbolGlyph(selectedIcon)
              .fontSize(22)
              .fontColor([$r('app.color.primary')])
          }
        }
        .width(56)
        .height(30)
        .borderRadius(15)
        .backgroundColor($r('app.color.tab_selected_pill'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        if (index === 1 && this.shouldShowProfileTabAvatar()) {
          SmartAvatar({
            avatarUrl: this.getProfileTabAvatarUrl(),
            avatarSize: 24,
            avatarRadius: 12,
            fallbackText: this.getProfileTabFallbackText(),
            bgColor: '#E8EAF0'
          })
        } else {
          SymbolGlyph(icon)
            .fontSize(22)
            .fontColor([$r('app.color.on_surface_secondary')])
        }
      }
      Text(label)
        .fontSize(11)
        .fontColor(this.currentIndex === index ? $r('app.color.primary') : $r('app.color.on_surface_secondary'))
        .margin({ top: 2 })
    }
    .width('100%')
    .height(FLOATING_TAB_BAR_HEIGHT_VP)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.switchMainTab(index);
    })
  }
}
