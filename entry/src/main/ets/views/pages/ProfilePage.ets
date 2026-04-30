import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { ThemeManager } from '../../common/theme/ThemeManager';
import { WindowManager } from '../../common/utils/WindowManager';
import { RouterManager } from '../../common/utils/RouterManager';
import { ToastService } from '../../common/utils/ToastService';
import { UserSummarySnapshotService } from '../../services/storage/UserSummarySnapshotService';
import { AuthService } from '../../services/auth/AuthService';
import { NotificationTrackingService } from '../../services/messagebus/NotificationTrackingService';
import { ApiClient } from '../../services/network/ApiClient';
import { CookieStore } from '../../services/network/CookieStore';
import { User, UserSummary, UserStatus } from '../../models/User';
import { AvatarWithFlair } from '../components/AvatarWithFlair';
import { UserStatusEmoji } from '../components/UserStatusEmoji';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';
import { NotificationQuickPanel } from '../components/NotificationQuickPanel';
import {
  FLOATING_TAB_BAR_HEIGHT_VP,
  FLOATING_TAB_BAR_MARGIN_BOTTOM_VP,
  FLOATING_TAB_BAR_OFFSET_UP_VP,
  FLOATING_TAB_BAR_CONTENT_EXTRA_PADDING_VP
} from '../../common/constants/LayoutConstants';

const TAG: string = 'ProfilePage';
const HEADER_AVATAR_SIZE: number = 72;

interface ProfileOptionItem {
  iconSymbol: Resource;
  iconBgColor: string;
  iconColor: string;
  title: Resource;
  subtitle: Resource | null;
  showDivider: boolean;
  onClick: () => void;
}

interface ProfileQuickActionItem {
  iconSymbol: Resource;
  iconBgColor: string;
  iconColor: string;
  title: Resource;
  subtitle: Resource;
  onClick: () => void;
}

@ComponentV2
export struct ProfilePage {
  @Local isLoading: boolean = true;
  @Local isRefreshing: boolean = false;
  @Local isSummaryLoading: boolean = false;
  @Local isNotificationQuickPanelVisible: boolean = false;
  @Local errorMessage: string = '';
  @Local isLoggedIn: boolean = false;
  @Local showTitle: boolean = false;
  @Local scrollOffset: number = 0;
  @Local currentUser: User | null = null;
  @Local summary: UserSummary | null = null;
  @Local isLoggingOut: boolean = false;

  private scroller: Scroller = new Scroller();
  private hasBootstrapped: boolean = false;
  private loadRequestId: number = 0;
  private authStateListener: (() => void) | null = null;
  private notificationTrackingListener: (() => void) | null = null;
  private lastFreshCurrentUserSyncAt: number = 0;

  aboutToAppear(): void {
    this.attachAuthStateListener();
    this.attachNotificationTrackingListener();
    const showLoading: boolean = !this.hasBootstrapped;
    this.hasBootstrapped = true;
    this.refreshPage(showLoading).catch((err: Object) => {
      hilog.error(0x0000, TAG, 'Refresh page failed: %{public}s', JSON.stringify(err));
    });
  }

  aboutToDisappear(): void {
    this.detachAuthStateListener();
    this.detachNotificationTrackingListener();
  }

  private getFloatingTabBarReservedBottomVp(): number {
    return WindowManager.getSystemAvoidAreaBottomVp()
      + FLOATING_TAB_BAR_HEIGHT_VP
      + FLOATING_TAB_BAR_MARGIN_BOTTOM_VP
      + FLOATING_TAB_BAR_OFFSET_UP_VP
      + FLOATING_TAB_BAR_CONTENT_EXTRA_PADDING_VP;
  }

  private attachAuthStateListener(): void {
    if (this.authStateListener !== null) {
      return;
    }
    this.authStateListener = () => {
      this.handleAuthStateChanged().catch((err: Object) => {
        hilog.error(0x0000, TAG, 'Handle auth state change failed: %{public}s', JSON.stringify(err));
      });
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

  private syncNotificationStateFromSessionUser(): void {
    if (!this.isLoggedIn) {
      return;
    }
    const sessionUser: User | null = AuthService.getInstance().getCurrentUser();
    if (sessionUser === null) {
      return;
    }
    if (this.currentUser === null) {
      this.currentUser = sessionUser;
      return;
    }
    const currentUsername: string = (this.currentUser as User).username.trim().toLowerCase();
    const sessionUsername: string = sessionUser.username.trim().toLowerCase();
    if (currentUsername.length > 0 && sessionUsername.length > 0 && currentUsername === sessionUsername) {
      this.currentUser = this.mergeSessionAndProfileUser(sessionUser, this.currentUser as User);
      return;
    }
    this.currentUser = sessionUser;
  }

  private attachNotificationTrackingListener(): void {
    if (this.notificationTrackingListener !== null) {
      return;
    }
    this.notificationTrackingListener = () => {
      this.syncNotificationStateFromSessionUser();
    };
    NotificationTrackingService.getInstance().addListener(this.notificationTrackingListener);
    this.syncNotificationStateFromSessionUser();
  }

  private detachNotificationTrackingListener(): void {
    if (this.notificationTrackingListener === null) {
      return;
    }
    NotificationTrackingService.getInstance().removeListener(this.notificationTrackingListener);
    this.notificationTrackingListener = null;
  }

  private buildFallbackCurrentUser(username: string): User {
    const user: User = new User();
    user.username = username;
    user.name = username;
    return user;
  }

  private needsProfileDetails(user: User): boolean {
    return user.avatarTemplate === null
      || (user.avatarTemplate as string).trim().length === 0
      || (user.name === null || (user.name as string).trim().length === 0)
      || user.status === null
      || user.flairUrl === null;
  }

  private mergeSessionAndProfileUser(sessionUser: User, profileUser: User): User {
    profileUser.unreadNotifications = sessionUser.unreadNotifications;
    profileUser.unreadHighPriorityNotifications = sessionUser.unreadHighPriorityNotifications;
    profileUser.allUnreadNotificationsCount = sessionUser.allUnreadNotificationsCount;
    profileUser.seenNotificationId = sessionUser.seenNotificationId;
    profileUser.notificationChannelPosition = sessionUser.notificationChannelPosition;

    if ((profileUser.name === null || (profileUser.name as string).trim().length === 0)
      && sessionUser.name !== null && (sessionUser.name as string).trim().length > 0) {
      profileUser.name = sessionUser.name;
    }
    if ((profileUser.avatarTemplate === null || (profileUser.avatarTemplate as string).trim().length === 0)
      && sessionUser.avatarTemplate !== null && (sessionUser.avatarTemplate as string).trim().length > 0) {
      profileUser.avatarTemplate = sessionUser.avatarTemplate;
    }
    if ((profileUser.animatedAvatar === null || (profileUser.animatedAvatar as string).trim().length === 0)
      && sessionUser.animatedAvatar !== null && (sessionUser.animatedAvatar as string).trim().length > 0) {
      profileUser.animatedAvatar = sessionUser.animatedAvatar;
    }
    if (profileUser.status === null && sessionUser.status !== null) {
      profileUser.status = sessionUser.status;
    }
    if (profileUser.flairUrl === null && sessionUser.flairUrl !== null) {
      profileUser.flairUrl = sessionUser.flairUrl;
      profileUser.flairName = sessionUser.flairName;
      profileUser.flairBgColor = sessionUser.flairBgColor;
      profileUser.flairColor = sessionUser.flairColor;
      profileUser.flairGroupId = sessionUser.flairGroupId;
    }
    return profileUser;
  }

  private shouldNotifyHydratedUser(previousUser: User | null, nextUser: User): boolean {
    if (previousUser === null) {
      return true;
    }
    const previousName: string = previousUser.name !== null ? (previousUser.name as string).trim() : '';
    const nextName: string = nextUser.name !== null ? (nextUser.name as string).trim() : '';
    const previousAvatar: string = previousUser.avatarTemplate !== null ? (previousUser.avatarTemplate as string).trim() : '';
    const nextAvatar: string = nextUser.avatarTemplate !== null ? (nextUser.avatarTemplate as string).trim() : '';
    if (previousAvatar.length === 0 && nextAvatar.length > 0) {
      return true;
    }
    if (previousName.length === 0 && nextName.length > 0) {
      return true;
    }
    if (previousUser.trustLevel !== nextUser.trustLevel) {
      return true;
    }
    if (previousUser.status === null && nextUser.status !== null) {
      return true;
    }
    if (previousUser.flairUrl === null && nextUser.flairUrl !== null) {
      return true;
    }
    return false;
  }

  private async hydrateVisibleUserByUsername(
    api: ApiClient,
    auth: AuthService,
    username: string,
    requestId: number
  ): Promise<void> {
    const normalizedUsername: string = username.trim();
    if (normalizedUsername.length === 0) {
      return;
    }

    let resolvedUser: User | null = this.currentUser;
    const currentVisibleUser: User | null = this.currentUser;
    const shouldFetchProfile: boolean = resolvedUser === null
      || this.needsProfileDetails(resolvedUser as User)
      || (resolvedUser as User).trustLevel <= 0;

    if (shouldFetchProfile) {
      try {
        const profileUser: User = await api.getUserProfile(normalizedUsername);
        if (requestId !== this.loadRequestId) {
          return;
        }
        resolvedUser = resolvedUser !== null
          ? this.mergeSessionAndProfileUser(resolvedUser as User, profileUser)
          : profileUser;
        this.currentUser = resolvedUser;
        auth.setCurrentUser(resolvedUser, this.shouldNotifyHydratedUser(currentVisibleUser, resolvedUser));
        api.setCachedCurrentUser(resolvedUser);
      } catch (profileErr) {
        hilog.warn(0x0000, TAG, 'Hydrate visible user by username failed: %{public}s', ApiClient.formatError(profileErr));
      }
    }

    const summaryUsername: string = resolvedUser !== null ? resolvedUser.username.trim() : normalizedUsername;
    const shouldFetchSummary: boolean = summaryUsername.length > 0 && (this.summary === null || this.isRefreshing);
    if (!shouldFetchSummary) {
      return;
    }

    this.isSummaryLoading = true;
    try {
      const summary: UserSummary = await api.getUserSummary(summaryUsername);
      if (requestId !== this.loadRequestId) {
        return;
      }
      this.summary = summary;
      this.isSummaryLoading = false;
      this.persistSummarySnapshot(summaryUsername, summary).catch((persistErr: Object) => {
        hilog.warn(0x0000, TAG, 'Persist hydrated profile summary snapshot failed: %{public}s', JSON.stringify(persistErr));
      });
    } catch (summaryErr) {
      hilog.warn(0x0000, TAG, 'Hydrate profile summary by username failed: %{public}s', ApiClient.formatError(summaryErr));
      if (requestId === this.loadRequestId) {
        this.isSummaryLoading = false;
      }
    }
  }

  private isRateLimitError(err: Object): boolean {
    if (err === undefined || err === null) {
      return false;
    }
    return err.toString().indexOf('HTTP 429') >= 0;
  }

  private async loadSummarySnapshot(username: string): Promise<UserSummary | null> {
    return await UserSummarySnapshotService.load(username);
  }

  private async persistSummarySnapshot(username: string, summary: UserSummary): Promise<void> {
    await UserSummarySnapshotService.save(username, summary);
  }

  private async handleAuthStateChanged(): Promise<void> {
    this.loadRequestId += 1;
    const auth: AuthService = AuthService.getInstance();
    if (!auth.getIsLoggedIn()) {
      this.applyLoggedOutState();
      return;
    }

    const cachedUser: User | null = auth.getCurrentUser();
    if (cachedUser !== null) {
      const currentUsername: string = this.currentUser !== null ? (this.currentUser as User).username.trim().toLowerCase() : '';
      const cachedUsername: string = cachedUser.username.trim().toLowerCase();
      if (this.currentUser !== null
        && currentUsername.length > 0
        && cachedUsername.length > 0
        && currentUsername === cachedUsername) {
        this.currentUser = this.mergeSessionAndProfileUser(cachedUser, this.currentUser as User);
        this.isLoggedIn = true;
        this.errorMessage = '';
        return;
      }
      this.currentUser = cachedUser;
    } else {
      const username: string = auth.getCurrentUsername().trim();
      if (username.length > 0) {
        this.currentUser = this.buildFallbackCurrentUser(username);
      }
    }
    this.isLoggedIn = true;
    this.errorMessage = '';
    await this.refreshPage(false, false);
  }

  private async pullToRefresh(): Promise<void> {
    this.errorMessage = '';
    if (this.isLoggedIn) {
      this.isSummaryLoading = true;
    }
    ApiClient.getInstance().invalidateCurrentUserCache();
    await this.refreshPage(false, false);
  }

  private async refreshPage(showLoading: boolean = true, clearAuthWhenServerUserMissing: boolean = true): Promise<void> {
    const requestId: number = ++this.loadRequestId;
    if (showLoading) {
      this.isLoading = true;
      this.errorMessage = '';
    } else if (this.isLoggedIn) {
      this.isRefreshing = true;
    }

    try {
      const auth: AuthService = AuthService.getInstance();
      await auth.init();
      if (requestId !== this.loadRequestId) {
        return;
      }

      if (!auth.getIsLoggedIn()) {
        this.applyLoggedOutState();
        return;
      }

      const cachedUser: User | null = auth.getCurrentUser();
      if (cachedUser !== null) {
        this.currentUser = cachedUser;
        this.isLoggedIn = true;
      } else {
        const fallbackUsername: string = auth.getCurrentUsername().trim();
        if (fallbackUsername.length > 0) {
          this.currentUser = this.buildFallbackCurrentUser(fallbackUsername);
          this.isLoggedIn = true;
        }
      }

      const snapshotUsername: string = this.currentUser !== null ? (this.currentUser as User).username.trim() : '';
      if (snapshotUsername.length > 0 && this.summary === null) {
        const startupSummary: UserSummary | null = await this.loadSummarySnapshot(snapshotUsername);
        if (requestId !== this.loadRequestId) {
          return;
        }
        if (startupSummary !== null) {
          this.summary = startupSummary;
          this.isSummaryLoading = false;
        }
      }

      const api: ApiClient = ApiClient.getInstance();
      const now: number = Date.now();
      if (showLoading || this.isRefreshing || now - this.lastFreshCurrentUserSyncAt >= 6000) {
        api.invalidateCurrentUserCache();
        this.lastFreshCurrentUserSyncAt = now;
      }
      const currentUser: User | null = await api.getCurrentUser();
      if (requestId !== this.loadRequestId) {
        return;
      }

      if (currentUser === null) {
        if (!clearAuthWhenServerUserMissing) {
          hilog.warn(0x0000, TAG, 'Server current_user unavailable during auth sync, keep cached login state');
          this.isLoggedIn = true;
          this.errorMessage = '';
          if (snapshotUsername.length > 0) {
            await this.hydrateVisibleUserByUsername(api, auth, snapshotUsername, requestId);
          }
          return;
        }
        await this.clearLocalAuth(false);
        ToastService.show('登录状态已失效，请重新登录');
        return;
      }

      let resolvedUser: User = currentUser;
      if (this.needsProfileDetails(currentUser)) {
        try {
          const profileUser: User = await api.getUserProfile(currentUser.username);
          if (requestId !== this.loadRequestId) {
            return;
          }
          resolvedUser = this.mergeSessionAndProfileUser(currentUser, profileUser);
        } catch (profileErr) {
          hilog.warn(0x0000, TAG, 'Load profile details failed, keep session user: %{public}s', ApiClient.formatError(profileErr));
        }
      }

      auth.setCurrentUser(resolvedUser);
      api.setCachedCurrentUser(resolvedUser);
      NotificationTrackingService.getInstance().syncStateFromCurrentUser(resolvedUser, true);
      this.currentUser = resolvedUser;
      this.isLoggedIn = true;
      this.errorMessage = '';
      const cachedSummary: UserSummary | null = await this.loadSummarySnapshot(resolvedUser.username);
      if (requestId !== this.loadRequestId) {
        return;
      }
      this.summary = cachedSummary;
      this.isSummaryLoading = cachedSummary === null;

      try {
        const summary: UserSummary = await api.getUserSummary(resolvedUser.username);
        if (requestId === this.loadRequestId) {
          this.summary = summary;
          this.isSummaryLoading = false;
          this.persistSummarySnapshot(resolvedUser.username, summary).catch((persistErr: Object) => {
            hilog.warn(0x0000, TAG, 'Persist profile summary snapshot failed: %{public}s', JSON.stringify(persistErr));
          });
        }
      } catch (summaryErr) {
        hilog.error(0x0000, TAG, 'Load user summary failed: %{public}s', ApiClient.formatError(summaryErr));
        if (requestId === this.loadRequestId) {
          this.isSummaryLoading = false;
        }
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load profile data failed: %{public}s', ApiClient.formatError(err));
      if (requestId === this.loadRequestId && this.currentUser !== null && this.isRateLimitError(err)) {
        this.isLoggedIn = true;
        this.errorMessage = '';
        const visibleUsername: string = (this.currentUser as User).username.trim();
        if (visibleUsername.length > 0) {
          await this.hydrateVisibleUserByUsername(ApiClient.getInstance(), AuthService.getInstance(), visibleUsername, requestId);
        } else {
          this.isSummaryLoading = false;
        }
        return;
      }
      if (requestId === this.loadRequestId && this.currentUser === null) {
        this.errorMessage = this.normalizeErrorMessage(err, '加载个人信息失败');
        this.isSummaryLoading = false;
      }
    } finally {
      if (requestId === this.loadRequestId) {
        this.isLoading = false;
        this.isRefreshing = false;
      }
    }
  }

  private normalizeErrorMessage(err: Object, fallback: string): string {
    if (err === undefined || err === null) {
      return fallback;
    }
    const text: string = err.toString().replace('Error: ', '').trim();
    return text.length > 0 ? text : fallback;
  }

  private applyLoggedOutState(): void {
    this.loadRequestId += 1;
    this.isLoggedIn = false;
    this.currentUser = null;
    this.summary = null;
    this.isSummaryLoading = false;
    this.isNotificationQuickPanelVisible = false;
    this.errorMessage = '';
    this.showTitle = false;
    this.isLoading = false;
    this.isRefreshing = false;
  }

  private async clearLocalAuth(showToast: boolean): Promise<void> {
    try {
      await AuthService.getInstance().logout();
    } catch (err) {
      hilog.error(0x0000, TAG, 'Auth logout failed: %{public}s', JSON.stringify(err));
    }

    try {
      await CookieStore.getInstance().init();
    } catch (_) {
    }

    const allCookies: Record<string, string> = CookieStore.getInstance().getAllCookies();
    const cookieNames: string[] = Object.keys(allCookies);
    CookieStore.getInstance().clearAll();

    for (let i = 0; i < cookieNames.length; i++) {
      const name: string = cookieNames[i];
      if (name.trim().length === 0) continue;
      try {
        webview.WebCookieManager.configCookieSync(
          AppConstants.BASE_URL,
          `${name}=; Max-Age=0; Path=/;`,
          false,
          true
        );
      } catch (err) {
        try {
          webview.WebCookieManager.configCookieSync(
            AppConstants.BASE_URL,
            `${name}=; Max-Age=0; Path=/;`,
            false
          );
        } catch (_) {
        }
        hilog.error(0x0000, TAG, 'Clear web cookie failed: %{public}s', JSON.stringify(err));
      }
    }

    try {
      webview.WebCookieManager.saveCookieAsync();
    } catch (_) {
    }

    this.applyLoggedOutState();
    this.scrollToTop();
    if (showToast) {
      ToastService.show('已退出登录');
    }
  }

  private scrollToTop(): void {
    try {
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 220, curve: Curve.EaseOut } });
    } catch (_) {
      this.scroller.scrollBy(0, -99999);
    }
  }

  private getDisplayName(): string {
    if (this.currentUser === null) {
      return '未登录';
    }
    const name: string | null = (this.currentUser as User).name;
    if (name !== null && name.trim().length > 0) {
      return name.trim();
    }
    return (this.currentUser as User).username;
  }

  private getUsername(): string {
    if (this.currentUser === null) {
      return '';
    }
    return (this.currentUser as User).username.trim();
  }

  private getAvatarUrl(size: number): string {
    if (this.currentUser === null) {
      return '';
    }
    return (this.currentUser as User).getAvatarUrl(size);
  }

  private getTrustLevelText(): string {
    if (this.currentUser === null) {
      return '';
    }
    return (this.currentUser as User).trustLevelString;
  }

  private getTrustLevelColor(): string {
    if (this.currentUser === null) {
      return '#999999';
    }
    return ThemeManager.getTrustLevelColor((this.currentUser as User).trustLevel);
  }

  private getStatus(): UserStatus | null {
    if (this.currentUser === null) {
      return null;
    }
    return (this.currentUser as User).status;
  }

  private getStatusEmojiText(): string {
    const status: UserStatus | null = this.getStatus();
    if (status === null || status.emoji === null) {
      return '';
    }
    return (status.emoji as string).trim();
  }

  private getStatusDescription(): string {
    const status: UserStatus | null = this.getStatus();
    if (status === null || status.description === null) {
      return '';
    }
    return (status.description as string).trim();
  }

  private getUnreadCount(): number {
    const localCount: number = this.currentUser !== null ? (this.currentUser as User).allUnreadNotificationsCount : 0;
    const trackedCount: number = NotificationTrackingService.getInstance().getAllUnreadCount();
    return Math.max(localCount, trackedCount);
  }

  private canShowInviteLinks(): boolean {
    return this.currentUser !== null && (this.currentUser as User).trustLevel >= 3;
  }

  private openMyProfile(): void {
    const username: string = this.getUsername();
    if (username.length > 0) {
      RouterManager.pushUserProfile(username);
    }
  }

  private openProfileEdit(): void {
    const username: string = this.getUsername();
    if (username.length > 0) {
      RouterManager.pushWebView(`${AppConstants.BASE_URL}/u/${username}/preferences/account`, '编辑资料');
    }
  }

  private openNotifications(): void {
    this.isNotificationQuickPanelVisible = true;
  }

  private openNotificationsPage(): void {
    this.isNotificationQuickPanelVisible = false;
    setTimeout(() => {
      RouterManager.pushNotifications();
    }, 0);
  }

  private openBookmarks(): void {
    RouterManager.pushBookmarks();
  }

  private openDrafts(): void {
    RouterManager.pushDrafts();
  }

  private openMyTopics(): void {
    RouterManager.pushMyTopics();
  }

  private openBadges(): void {
    RouterManager.pushMyBadges();
  }

  private openBrowsingHistory(): void {
    RouterManager.pushBrowsingHistory();
  }

  private openInviteLinks(): void {
    const username: string = this.getUsername();
    if (username.length > 0) {
      RouterManager.pushInviteLinks();
    }
  }

  private showPendingToast(title: string): void {
    ToastService.show(`${title}待接入`);
  }

  private async logout(): Promise<void> {
    if (this.isLoggingOut) {
      return;
    }
    this.isLoggingOut = true;
    try {
      await this.clearLocalAuth(true);
    } finally {
      this.isLoggingOut = false;
    }
  }

  build() {
    Column() {
      this.TopBar()

      if (this.isLoading && this.currentUser === null && this.errorMessage.length === 0) {
        Column() {
          LoadingSpinner({ message: '' })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.errorMessage.length > 0 && this.currentUser === null) {
        Column() {
          ErrorView({
            title: '加载失败',
            message: this.errorMessage,
            onRetry: () => {
              this.refreshPage(true).catch((err: Object) => {
                hilog.error(0x0000, TAG, 'Retry refresh failed: %{public}s', JSON.stringify(err));
              });
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Refresh({ refreshing: this.isRefreshing }) {
          Scroll(this.scroller) {
            Column() {
              this.HeaderSection()
              Blank().height(24)

              if (this.isLoggedIn && this.summary !== null) {
                this.StatsCard()
                Blank().height(24)
              } else if (this.isLoggedIn && this.currentUser !== null && (this.isSummaryLoading || this.isRefreshing)) {
                this.SummaryLoadingCard()
                Blank().height(24)
              } else if (this.isLoggedIn && this.currentUser !== null) {
                this.SummaryPlaceholderCard()
                Blank().height(24)
              }

              if (this.isLoggedIn && this.currentUser !== null) {
                this.LoggedInQuickAccessCard()
                Blank().height(20)
                this.SectionHeader($r('app.string.profile_section_growth'), $r('app.string.profile_section_growth_subtitle'))
                Blank().height(12)
                this.LoggedInOptionsCard()
                Blank().height(20)
              }

              this.SectionHeader($r('app.string.profile_section_services'), $r('app.string.profile_section_services_subtitle'))
              Blank().height(12)
              this.AboutCard()
              Blank().height(32)
              this.AuthButton()
              Blank().height(48)
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 12,
              bottom: this.getFloatingTabBarReservedBottomVp()
            })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .onScrollFrameBegin((offset: number, _state: ScrollState) => {
            const next: number = Math.max(0, this.scrollOffset + offset);
            this.scrollOffset = next;
            const shouldShow: boolean = this.isLoggedIn && next > 80;
            if (shouldShow !== this.showTitle) {
              this.showTitle = shouldShow;
            }
            return { offsetRemain: offset };
          })
        }
        .onRefreshing(() => {
          this.pullToRefresh().catch((err: Object) => {
            hilog.error(0x0000, TAG, 'Pull to refresh profile failed: %{public}s', JSON.stringify(err));
          });
        })
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: WindowManager.getSystemAvoidAreaTopVp() })
    .backgroundColor($r('app.color.background'))
    .bindSheet($$this.isNotificationQuickPanelVisible, this.NotificationQuickPanelBuilder, {
      height: SheetSize.LARGE,
      dragBar: false,
      showClose: false,
      backgroundColor: $r('app.color.surface')
    })
  }

  @Builder
  private TopBar() {
    Row() {
      if (this.showTitle && this.currentUser !== null) {
        Row() {
          AvatarWithFlair({
            avatarUrl: this.getAvatarUrl(56),
            avatarSize: 28,
            fallbackText: this.getDisplayName(),
            flairUrl: (this.currentUser as User).flairUrl,
            flairName: (this.currentUser as User).flairName,
            flairBgColor: (this.currentUser as User).flairBgColor,
            flairColor: (this.currentUser as User).flairColor,
            flairSize: 12
          })

          Text(this.getDisplayName())
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .margin({ left: 8 })
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .onClick(() => {
          this.scrollToTop();
        })
      } else {
        Blank().layoutWeight(1)
      }

      if (this.isLoggedIn) {
        Row() {
          Row() {
            if (this.isRefreshing) {
              LoadingProgress().width(18).height(18)
            } else if (this.errorMessage.length > 0) {
              SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
                .fontSize(16)
                .fontColor([$r('app.color.on_surface_tertiary')])
            } else {
              Blank().width(18).height(18)
            }
          }
          .width(24)
          .height(24)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)

          Row() {
            this.PillActionButton($r('sys.symbol.gearshape'), () => {
              this.openProfileEdit();
            })

            Stack({ alignContent: Alignment.TopEnd }) {
              Row() {
                SymbolGlyph($r('sys.symbol.bell'))
                  .fontSize(18)
                  .fontColor([$r('app.color.on_surface')])
              }
              .width(34)
              .height(34)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.openNotifications();
              })

              if (this.getUnreadCount() > 0) {
                Row() {
                  Text(this.getUnreadCount() > 99 ? '99+' : this.getUnreadCount().toString())
                    .fontSize(9)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                }
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .backgroundColor($r('app.color.error'))
                .borderRadius(8)
                .margin({ top: 1, right: 0 })
              }
            }
            .width(34)
            .height(34)
          }
          .padding({ left: 4, right: 4, top: 4, bottom: 4 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(22)
          .shadow({ radius: 10, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 4 })
          .margin({ left: 8 })
        }
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.background'))
    .alignItems(VerticalAlign.Center)
    .shadow({ radius: this.scrollOffset > 0 ? 8 : 0, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 })
  }

  @Builder
  private TopIconButton(symbol: Resource, onClick: () => void = () => {}) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(19)
        .fontColor([$r('app.color.on_surface')])
    }
    .width(36)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .margin({ left: 8 })
    .onClick(() => {
      onClick();
    })
  }

  @Builder
  private HeaderSection() {
    Column() {
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(HEADER_AVATAR_SIZE + 12)
            .height(HEADER_AVATAR_SIZE + 12)
            .fill(this.getHeaderHaloColor())

          AvatarWithFlair({
            avatarUrl: this.getAvatarUrl(144),
            avatarSize: HEADER_AVATAR_SIZE,
            avatarRadius: HEADER_AVATAR_SIZE / 2,
            fallbackText: this.isLoggedIn ? this.getDisplayName() : '',
            bgColor: '#E8EAF0',
            flairUrl: this.currentUser !== null ? (this.currentUser as User).flairUrl : null,
            flairName: this.currentUser !== null ? (this.currentUser as User).flairName : null,
            flairBgColor: this.currentUser !== null ? (this.currentUser as User).flairBgColor : null,
            flairColor: this.currentUser !== null ? (this.currentUser as User).flairColor : null,
            flairSize: 24
          })
        }
        .width(HEADER_AVATAR_SIZE + 12)
        .height(HEADER_AVATAR_SIZE + 12)

        Column() {
          Text(this.getDisplayName())
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.isLoggedIn && this.getUsername().length > 0) {
            Text(`@${this.getUsername()}`)
              .fontSize(14)
              .fontColor($r('app.color.on_surface_secondary'))
              .margin({ top: 4 })
          } else {
            Text('登录后体验更多功能')
              .fontSize(14)
              .fontColor($r('app.color.on_surface_secondary'))
              .margin({ top: 4 })
          }

          if (this.isLoggedIn && this.currentUser !== null) {
            Flex({ wrap: FlexWrap.Wrap }) {
              Text(this.getTrustLevelText())
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.getTrustLevelColor())
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor(ThemeManager.hexWithAlpha(this.getTrustLevelColor(), 0.14))
                .borderRadius(10)
                .margin({ right: 8, bottom: 4 })

              if (this.getStatusEmojiText().length > 0 || this.getStatusDescription().length > 0) {
                Row() {
                  if (this.getStatusEmojiText().length > 0) {
                    UserStatusEmoji({
                      rawEmoji: this.getStatusEmojiText(),
                      iconSize: 14,
                      marginLeft: 0
                    })
                  }
                  if (this.getStatusDescription().length > 0) {
                    Text(this.getStatusDescription())
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.on_surface_secondary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ left: this.getStatusEmojiText().length > 0 ? 4 : 0 })
                  }
                }
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(10)
                .margin({ bottom: 4 })
              }
            }
            .margin({ top: 10 })
          }
        }
        .layoutWeight(1)
        .margin({ left: 18 })
        .alignItems(HorizontalAlign.Start)

        if (this.isLoggedIn && this.currentUser !== null) {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.on_surface_secondary')])
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor($r('app.color.card_background'))
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .margin({ left: 12 })
          .shadow({ radius: 6, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 })
        }
      }
      .width('100%')
      .margin({ top: 14 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
    .backgroundColor(this.getHeaderPanelBackground())
    .borderRadius(24)
    .border({ width: 1, color: this.getHeaderPanelBorderColor() })
    .shadow({ radius: 14, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 6 })
    .onClick(() => {
      if (this.isLoggedIn && this.currentUser !== null) {
        this.openMyProfile();
      }
    })
  }

  @Builder
  private StatsCard() {
    Column() {
      Row() {
        Column() {
          Text($r('app.string.profile_stats_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))

          Text($r('app.string.profile_stats_subtitle'))
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text($r('app.string.profile_stats_chip'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getHeaderAccentColor())
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(this.getStatsChipBackground())
          .borderRadius(12)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Blank().height(18)

      Row() {
        this.StatItem(this.formatCount((this.summary as UserSummary).daysVisited), $r('app.string.days_visited'))
        this.VerticalDivider()
        this.StatItem(this.formatCount((this.summary as UserSummary).postsReadCount), $r('app.string.posts_read'))
        this.VerticalDivider()
        this.StatItem(this.formatCount((this.summary as UserSummary).likesReceived), $r('app.string.likes_received'))
        this.VerticalDivider()
        this.StatItem(this.formatCount((this.summary as UserSummary).postCount), $r('app.string.posts_created'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
    .backgroundColor(this.getStatsCardBackground())
    .borderRadius(22)
    .border({ width: 1, color: this.getStatsCardBorderColor() })
    .shadow({ radius: 14, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 6 })
  }

  @Builder
  private SummaryLoadingCard() {
    Column() {
      Row() {
        Column() {
          Text($r('app.string.profile_stats_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))

          Text($r('app.string.profile_stats_subtitle'))
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text($r('app.string.profile_stats_chip'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getHeaderAccentColor())
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(this.getStatsChipBackground())
          .borderRadius(12)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        LoadingProgress().width(18).height(18)
        Text($r('app.string.profile_stats_loading'))
          .fontSize(13)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ left: 8 })
      }
      .margin({ top: 18 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
    .backgroundColor(this.getStatsCardBackground())
    .borderRadius(22)
    .border({ width: 1, color: this.getStatsCardBorderColor() })
    .shadow({ radius: 14, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 6 })
  }

  @Builder
  private SummaryPlaceholderCard() {
    Column() {
      Row() {
        Column() {
          Text($r('app.string.profile_stats_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))

          Text($r('app.string.profile_stats_subtitle'))
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text($r('app.string.profile_stats_chip'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getHeaderAccentColor())
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(this.getStatsChipBackground())
          .borderRadius(12)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Blank().height(18)

      Row() {
        this.StatItem('--', $r('app.string.days_visited'))
        this.VerticalDivider()
        this.StatItem('--', $r('app.string.posts_read'))
        this.VerticalDivider()
        this.StatItem('--', $r('app.string.likes_received'))
        this.VerticalDivider()
        this.StatItem('--', $r('app.string.posts_created'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
    .backgroundColor(this.getStatsCardBackground())
    .borderRadius(22)
    .border({ width: 1, color: this.getStatsCardBorderColor() })
    .shadow({ radius: 14, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 6 })
    .opacity(0.86)
  }

  @Builder
  private VerticalDivider() {
    Blank()
      .width(1)
      .height(28)
      .backgroundColor(this.getStatsCardBorderColor())
  }

  @Builder
  private PillActionButton(symbol: Resource, onClick: () => void = () => {}) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(18)
        .fontColor([$r('app.color.on_surface')])
    }
    .width(34)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      onClick();
    })
  }

  @Builder
  private StatItem(value: string, label: Resource) {
    Column() {
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getHeaderAccentColor())
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ top: 6 })
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private SectionHeader(title: Resource, subtitle: Resource) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))

      Text(subtitle)
        .fontSize(12)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private LoggedInQuickAccessCard() {
    Column() {
      this.SectionHeader($r('app.string.profile_section_workspace'), $r('app.string.profile_section_workspace_subtitle'))
      Blank().height(16)

      Row() {
        this.QuickAccessItem({
          iconSymbol: $r('sys.symbol.message'),
          iconBgColor: '#E0F7FA',
          iconColor: '#00ACC1',
          title: $r('app.string.profile_my_topics'),
          subtitle: $r('app.string.profile_workspace_topics_hint'),
          onClick: () => { this.openMyTopics(); }
        })
        Blank().width(12)
        this.QuickAccessItem({
          iconSymbol: $r('sys.symbol.bookmark'),
          iconBgColor: '#FFF3E0',
          iconColor: '#FB8C00',
          title: $r('app.string.profile_my_bookmarks'),
          subtitle: $r('app.string.profile_workspace_bookmarks_hint'),
          onClick: () => { this.openBookmarks(); }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Blank().height(12)

      Row() {
        this.QuickAccessItem({
          iconSymbol: $r('sys.symbol.notepad'),
          iconBgColor: '#E0F2F1',
          iconColor: '#00897B',
          title: $r('app.string.profile_my_drafts'),
          subtitle: $r('app.string.profile_workspace_drafts_hint'),
          onClick: () => { this.openDrafts(); }
        })
        Blank().width(12)
        this.QuickAccessItem({
          iconSymbol: $r('sys.symbol.medal'),
          iconBgColor: '#FFF8E1',
          iconColor: '#FFB300',
          title: $r('app.string.profile_my_badges'),
          subtitle: $r('app.string.profile_workspace_badges_hint'),
          onClick: () => { this.openBadges(); }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(24)
    .border({ width: 1, color: $r('app.color.divider_light') })
    .shadow({ radius: 14, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 6 })
  }

  @Builder
  private LoggedInOptionsCard() {
    Column() {
      this.OptionItem({
        iconSymbol: $r('sys.symbol.clock'),
        iconBgColor: '#F3E5F5',
        iconColor: '#8E24AA',
        title: $r('app.string.profile_browsing_history'),
        subtitle: $r('app.string.profile_growth_history_hint'),
        showDivider: true,
        onClick: () => { this.openBrowsingHistory(); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.security_shield'),
        iconBgColor: '#E8F5E9',
        iconColor: '#43A047',
        title: $r('app.string.profile_trust_requirements'),
        subtitle: $r('app.string.profile_growth_trust_hint'),
        showDivider: this.canShowInviteLinks(),
        onClick: () => { RouterManager.pushTrustLevel(); }
      })
      if (this.canShowInviteLinks()) {
        this.OptionItem({
          iconSymbol: $r('sys.symbol.link'),
          iconBgColor: '#E0F7FA',
          iconColor: '#00ACC1',
          title: $r('app.string.profile_invite_links'),
          subtitle: $r('app.string.profile_growth_invite_hint'),
          showDivider: false,
          onClick: () => { this.openInviteLinks(); }
        })
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .border({ width: 1, color: $r('app.color.divider_light') })
    .shadow({ radius: 12, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 6 })
  }

  @Builder
  private QuickAccessItem(params: ProfileQuickActionItem) {
    Column() {
      Row() {
        Row() {
          SymbolGlyph(params.iconSymbol)
            .fontSize(22)
            .fontColor([params.iconColor])
        }
        .width(50)
        .height(50)
        .borderRadius(16)
        .backgroundColor(this.getOptionIconBackground(params.iconBgColor, params.iconColor))
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)

        Blank().layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('app.color.on_surface_tertiary')])
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(params.title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 14 })

      Text(params.subtitle)
        .fontSize(12)
        .fontColor($r('app.color.on_surface_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
    }
    .layoutWeight(1)
    .height(122)
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(this.getQuickActionSurface(params.iconColor))
    .borderRadius(18)
    .border({ width: 1, color: this.getQuickActionBorder(params.iconColor) })
    .onClick(() => {
      params.onClick();
    })
  }

  @Builder
  private AboutCard() {
    Column() {
      this.OptionItem({
        iconSymbol: $r('sys.symbol.archivebox'),
        iconBgColor: '#FBE9E7',
        iconColor: '#F4511E',
        title: $r('app.string.profile_metaverse'),
        subtitle: $r('app.string.profile_service_metaverse_hint'),
        showDivider: true,
        onClick: () => { this.showPendingToast('元宇宙'); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.robot'),
        iconBgColor: '#E0F7FA',
        iconColor: '#00ACC1',
        title: $r('app.string.profile_ai_model_service'),
        subtitle: $r('app.string.profile_service_ai_hint'),
        showDivider: true,
        onClick: () => { this.showPendingToast('AI 模型服务'); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.paintbrush'),
        iconBgColor: '#E0F2F1',
        iconColor: '#00897B',
        title: $r('app.string.profile_appearance'),
        subtitle: $r('app.string.profile_service_appearance_hint'),
        showDivider: true,
        onClick: () => { this.showPendingToast('外观设置'); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.wifi'),
        iconBgColor: '#E8F5E9',
        iconColor: '#43A047',
        title: $r('app.string.profile_network_settings'),
        subtitle: $r('app.string.profile_service_network_hint'),
        showDivider: true,
        onClick: () => { this.showPendingToast('网络设置'); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.gearshape'),
        iconBgColor: '#EDE7F6',
        iconColor: '#5E35B1',
        title: $r('app.string.profile_feature_settings'),
        subtitle: $r('app.string.profile_service_feature_hint'),
        showDivider: true,
        onClick: () => { RouterManager.pushFeatureSettings(); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.archivebox'),
        iconBgColor: '#EFEBE9',
        iconColor: '#6D4C41',
        title: $r('app.string.profile_data_management'),
        subtitle: $r('app.string.profile_service_data_hint'),
        showDivider: true,
        onClick: () => { RouterManager.pushDataManagement(); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.info_circle'),
        iconBgColor: '#E8EAF6',
        iconColor: '#3949AB',
        title: $r('app.string.profile_about_app'),
        subtitle: $r('app.string.profile_service_about_hint'),
        showDivider: false,
        onClick: () => { RouterManager.pushAboutApp(); }
      })
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .border({ width: 1, color: $r('app.color.divider_light') })
    .shadow({ radius: 12, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 6 })
  }

  @Builder
  private AuthButton() {
    if (this.isLoggedIn) {
      Button() {
        Row() {
          if (this.isLoggingOut) {
            LoadingProgress().width(18).height(18)
            Text('正在退出...')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.error'))
              .margin({ left: 8 })
          } else {
            Text('退出当前账号')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.error'))
          }
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(48)
      .backgroundColor(this.getDangerActionBackground())
      .borderRadius(24)
      .onClick(() => {
        this.logout().catch((err: Object) => {
          hilog.error(0x0000, TAG, 'Logout failed: %{public}s', JSON.stringify(err));
          ToastService.show('退出失败');
        });
      })
    } else {
      Button() {
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(20)
            .fontColor([Color.White])
            .margin({ right: 8 })
          Text('登录 Linux.do')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(52)
      .backgroundColor($r('app.color.primary'))
      .borderRadius(16)
      .onClick(() => {
        RouterManager.pushLogin();
      })
    }
  }

  @Builder
  private NotificationQuickPanelBuilder() {
    NotificationQuickPanel({
      onClose: () => {
        this.isNotificationQuickPanelVisible = false;
      },
      onViewAll: () => {
        this.openNotificationsPage();
      }
    })
  }

  private formatCount(count: number): string {
    if (count >= 10000) {
      return `${(count / 10000).toFixed(1)}w`;
    }
    if (count >= 1000) {
      return `${(count / 1000).toFixed(1)}k`;
    }
    return count.toString();
  }

  private getDangerActionBackground(): string {
    return WindowManager.isDarkMode()
      ? ThemeManager.hexWithAlpha('#EF5350', 0.18)
      : ThemeManager.hexWithAlpha('#D32F2F', 0.08);
  }

  private getHeaderAccentColor(): string {
    if (this.currentUser === null) {
      return '#0088CC';
    }
    return this.getTrustLevelColor();
  }

  private getHeaderPanelBackground(): string {
    const accent: string = this.getHeaderAccentColor();
    return ThemeManager.hexWithAlpha(accent, WindowManager.isDarkMode() ? 0.22 : 0.07);
  }

  private getHeaderPanelBorderColor(): string {
    const accent: string = this.getHeaderAccentColor();
    return ThemeManager.hexWithAlpha(accent, WindowManager.isDarkMode() ? 0.26 : 0.12);
  }

  private getHeaderHaloColor(): string {
    const accent: string = this.getHeaderAccentColor();
    return ThemeManager.hexWithAlpha(accent, WindowManager.isDarkMode() ? 0.18 : 0.12);
  }

  private getStatsCardBackground(): string {
    const accent: string = this.getHeaderAccentColor();
    return ThemeManager.hexWithAlpha(accent, WindowManager.isDarkMode() ? 0.16 : 0.05);
  }

  private getStatsCardBorderColor(): string {
    const accent: string = this.getHeaderAccentColor();
    return ThemeManager.hexWithAlpha(accent, WindowManager.isDarkMode() ? 0.24 : 0.10);
  }

  private getStatsChipBackground(): string {
    const accent: string = this.getHeaderAccentColor();
    return ThemeManager.hexWithAlpha(accent, WindowManager.isDarkMode() ? 0.22 : 0.10);
  }

  private getQuickActionSurface(iconColor: string): string {
    return ThemeManager.hexWithAlpha(iconColor, WindowManager.isDarkMode() ? 0.18 : 0.06);
  }

  private getQuickActionBorder(iconColor: string): string {
    return ThemeManager.hexWithAlpha(iconColor, WindowManager.isDarkMode() ? 0.26 : 0.10);
  }

  private getOptionIconBackground(iconBgColor: string, iconColor: string): string {
    if (!WindowManager.isDarkMode()) {
      return iconBgColor;
    }
    return ThemeManager.hexWithAlpha(iconColor, 0.18);
  }

  @Builder
  private OptionItem(params: ProfileOptionItem) {
    Column() {
      Row() {
        Column() {
          SymbolGlyph(params.iconSymbol)
            .fontSize(20)
            .fontColor([params.iconColor])
        }
        .width(38)
        .height(38)
        .borderRadius(12)
        .backgroundColor(this.getOptionIconBackground(params.iconBgColor, params.iconColor))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column() {
          Text(params.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (params.subtitle !== null) {
            Text(params.subtitle)
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 4 })
          }
        }
          .margin({ left: 14 })
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.on_surface_tertiary')])
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 15, bottom: 15 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        params.onClick();
      })

      if (params.showDivider) {
        Divider()
          .color($r('app.color.divider_light'))
          .strokeWidth(0.5)
          .margin({ left: 66 })
      }
    }
    .width('100%')
  }
}
