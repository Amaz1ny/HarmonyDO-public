import { hilog } from '@kit.PerformanceAnalysisKit';
import { SmartAvatar } from '../components/SmartAvatar';
import { AvatarWithFlair } from '../components/AvatarWithFlair';
import { UserStatusEmoji } from '../components/UserStatusEmoji';
import { PostRichContent } from '../components/PostRichContent';
import { RouterManager, RouteConstants } from '../../common/utils/RouterManager';
import { WindowManager } from '../../common/utils/WindowManager';
import { AnimatedGradientBackground } from '../components/AnimatedGradientBackground';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { ApiClient } from '../../services/network/ApiClient';
import { Badge } from '../../models/Badge';
import {
  SummaryCategory,
  SummaryLink,
  SummaryReply,
  SummaryTopic,
  SummaryUserWithCount,
  User,
  UserStatus,
  UserSummary
} from '../../models/User';
import { UserAction, UserActionType, UserReaction } from '../../models/UserAction';
import { AuthService } from '../../services/auth/AuthService';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';
import { PrivateMessageComposerSheet } from '../components/PrivateMessageComposerSheet';
import { TimeUtils } from '../../common/utils/TimeUtils';
import { UrlUtils } from '../../common/utils/UrlUtils';
import { ShareUtils } from '../../common/utils/ShareUtils';
import { SystemShareService } from '../../common/utils/SystemShareService';
import { ExternalLinkService } from '../../common/utils/ExternalLinkService';
import { ClipboardService } from '../../common/utils/ClipboardService';
import { ToastService } from '../../common/utils/ToastService';

const TOP_BAR_HEIGHT: number = 56; // 不含状态栏安全区
const HEADER_AVATAR_SIZE: number = 72;
const TAB_HEIGHT: number = 36;
const EXPANDED_HEIGHT: number = 410; // 不含状态栏安全区
const TAG: string = 'UserProfilePage';
const ACTION_PAGE_SIZE: number = 30;
const REACTION_PAGE_SIZE: number = 20;

/**
 * 他人主页（游客态可用）
 *
 * UI 对齐目标：安卓端“查看其他人的个人主页”页面（顶部深色头图 + 统计 + Tabs + 总结分区）
 *
 * 说明：
 * - 已接入真实后端：/u/{username}.json + /u/{username}/summary.json
 */
@ComponentV2
export struct UserProfilePage {
  @Param username: string = '';

  @Local currentTabIndex: number = 0;
  @Local scrollOffset: number = 0;
  @Local isLoading: boolean = true;
  @Local errorMessage: string = '';
  @Local profile: User | null = null;
  @Local summary: UserSummary | null = null;
  @Local isLoggedIn: boolean = false;
  @Local currentUsername: string = '';
  @Local isOwnProfile: boolean = false;
  @Local isFollowed: boolean = false;
  @Local isFollowLoading: boolean = false;
  @Local notificationLevel: string = 'normal';
  @Local profileFollowingCount: number | null = null;
  @Local profileFollowersCount: number | null = null;
  @Local isPrivateMessageSheetVisible: boolean = false;
  @Local privateMessageSheetRequestKey: string = '';
  @Local isUserInfoSheetVisible: boolean = false;

  // Tab 数据（游客态可用）：动态/话题/回复/赞（user_actions）+ 回应（reactions）
  @Local actionsAll: UserAction[] = [];     // 4,5
  @Local actionsTopics: UserAction[] = [];  // 4
  @Local actionsReplies: UserAction[] = []; // 5
  @Local actionsLikes: UserAction[] = [];   // 1

  @Local actionsAllLoaded: boolean = false;
  @Local actionsTopicsLoaded: boolean = false;
  @Local actionsRepliesLoaded: boolean = false;
  @Local actionsLikesLoaded: boolean = false;

  @Local actionsAllHasMore: boolean = true;
  @Local actionsTopicsHasMore: boolean = true;
  @Local actionsRepliesHasMore: boolean = true;
  @Local actionsLikesHasMore: boolean = true;

  @Local actionsAllLoading: boolean = false;
  @Local actionsTopicsLoading: boolean = false;
  @Local actionsRepliesLoading: boolean = false;
  @Local actionsLikesLoading: boolean = false;

  @Local actionsAllLoadingMore: boolean = false;
  @Local actionsTopicsLoadingMore: boolean = false;
  @Local actionsRepliesLoadingMore: boolean = false;
  @Local actionsLikesLoadingMore: boolean = false;

  @Local actionsAllLoadMoreFailed: boolean = false;
  @Local actionsTopicsLoadMoreFailed: boolean = false;
  @Local actionsRepliesLoadMoreFailed: boolean = false;
  @Local actionsLikesLoadMoreFailed: boolean = false;

  @Local actionsAllError: string = '';
  @Local actionsTopicsError: string = '';
  @Local actionsRepliesError: string = '';
  @Local actionsLikesError: string = '';

  @Local reactions: UserReaction[] = [];
  @Local reactionsLoaded: boolean = false;
  @Local reactionsHasMore: boolean = true;
  @Local reactionsLoading: boolean = false;
  @Local reactionsLoadingMore: boolean = false;
  @Local reactionsLoadMoreFailed: boolean = false;
  @Local reactionsError: string = '';
  @Local reactionsRequiresLogin: boolean = false;
  private scroller: Scroller = new Scroller();
  private scrollSyncTimerId: number = -1;

  private readonly tabLabels: string[] = ['总结', '动态', '话题', '回复', '赞', '回应'];
  private authStateListener: (() => void) | null = null;

  aboutToAppear(): void {
    // 进入他人主页：开启沉浸式（内容延伸到状态栏下），并让系统栏与头图/列表风格一致
    WindowManager.setWindowLayoutFullScreen(true);
    WindowManager.setSystemBarStyle('#00000000', '#FFFFFF', '#FFFFFF', '#000000');
    this.attachAuthStateListener();
    this.bootstrapPage().catch((err: Object) => {
      hilog.error(0x0000, TAG, 'Bootstrap user profile failed: %{public}s', JSON.stringify(err));
    });
  }

  aboutToDisappear(): void {
    // 恢复全局默认系统栏样式（沉浸式保持开启，由 EntryAbility 统一控制）
    WindowManager.setSystemBarStyle('#00000000', '#FFFFFF', '#000000', '#000000');
    this.clearScrollSyncTimer();
    this.detachAuthStateListener();
  }

  private attachAuthStateListener(): void {
    if (this.authStateListener !== null) {
      return;
    }
    this.authStateListener = () => {
      this.initAuthState().catch((err: Object) => {
        hilog.error(0x0000, TAG, 'Auth state listener failed: %{public}s', JSON.stringify(err));
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

  private async bootstrapPage(): Promise<void> {
    await this.initAuthState();
    await this.loadUserData();
  }

  private async initAuthState(): Promise<void> {
    const auth: AuthService = AuthService.getInstance();
    await auth.init();
    this.isLoggedIn = auth.getIsLoggedIn();
    this.currentUsername = auth.getCurrentUsername().trim();
    this.syncProfileRelationshipState();
  }

  private getTargetUsername(): string {
    if (this.profile !== null && (this.profile as User).username.trim().length > 0) {
      return (this.profile as User).username.trim();
    }
    return this.username.trim();
  }

  private syncProfileRelationshipState(): void {
    const target: string = this.getTargetUsername().toLowerCase();
    const current: string = this.currentUsername.trim().toLowerCase();
    this.isOwnProfile = this.isLoggedIn && current.length > 0 && current === target;
    if (this.profile !== null) {
      const profile: User = this.profile as User;
      this.isFollowed = profile.isFollowed === true;
      this.notificationLevel = profile.ignored === true ? 'ignore' : (profile.muted === true ? 'mute' : 'normal');
    } else {
      this.isFollowed = false;
      this.notificationLevel = 'normal';
    }
  }

  private async loadUserData(): Promise<void> {
    const u: string = this.username.trim();
    if (u.length === 0) {
      this.errorMessage = '无效的用户名';
      this.isLoading = false;
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';
    this.profile = null;
    this.summary = null;
    this.profileFollowingCount = null;
    this.profileFollowersCount = null;
    this.isFollowed = false;
    this.notificationLevel = 'normal';

    try {
      const api: ApiClient = ApiClient.getInstance();
      const profilePromise: Promise<User> = api.getUserProfile(u);
      const summaryPromise: Promise<UserSummary> = api.getUserSummary(u);

      const p: User = await profilePromise;
      const s: UserSummary = await summaryPromise;

      this.profile = p;
      this.summary = s;
      this.profileFollowingCount = p.totalFollowing;
      this.profileFollowersCount = p.totalFollowers;
      this.syncProfileRelationshipState();
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load user data failed: %{public}s', JSON.stringify(err));
      this.errorMessage = '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  private getProfileAvatarUrl(size: number): string {
    if (this.profile === null) return '';
    return (this.profile as User).getAvatarUrl(size);
  }

  private getProfileBackgroundUrl(): string {
    if (this.profile === null) return '';
    return (this.profile as User).backgroundUrl;
  }

  private hasProfileBackground(): boolean {
    return this.getProfileBackgroundUrl().trim().length > 0;
  }

  private getProfileFlairUrl(): string | null {
    if (this.profile === null) return null;
    return (this.profile as User).flairUrl;
  }

  private getProfileFlairName(): string | null {
    if (this.profile === null) return null;
    return (this.profile as User).flairName;
  }

  private getProfileFlairBgColor(): string | null {
    if (this.profile === null) return null;
    return (this.profile as User).flairBgColor;
  }

  private getProfileFlairColor(): string | null {
    if (this.profile === null) return null;
    return (this.profile as User).flairColor;
  }

  private getProfileDisplayName(): string {
    if (this.profile !== null) {
      const name: string | null = (this.profile as User).name;
      if (name !== null && (name as string).length > 0) {
        return name as string;
      }
    }
    const username: string = this.getTargetUsername();
    return username.length > 0 ? username : '用户';
  }

  private getProfileTrustLevelText(): string {
    if (this.profile === null) return '';
    return (this.profile as User).trustLevelString;
  }

  private getProfileBioText(): string {
    if (this.profile !== null) {
      const profile: User = this.profile as User;
      if (profile.bio !== null && profile.bio.length > 0) {
        return this.stripHtml(profile.bio);
      }
      if (profile.bioRaw !== null && profile.bioRaw.length > 0) {
        return profile.bioRaw;
      }
    }
    return '这个人很懒，什么都没写';
  }

  private hasProfileBio(): boolean {
    if (this.profile === null) return false;
    const profile: User = this.profile as User;
    return (profile.bio !== null && this.stripHtml(profile.bio).length > 0)
      || (profile.bioRaw !== null && profile.bioRaw.trim().length > 0);
  }

  private getProfileBioCookedHtml(): string {
    if (this.profile === null) return '';
    const cooked: string | null = (this.profile as User).bioCooked;
    return cooked !== null ? cooked : '';
  }

  private getProfileFollowingCount(): number | null {
    return this.profileFollowingCount;
  }

  private getProfileFollowersCount(): number | null {
    return this.profileFollowersCount;
  }

  private hasFollowStats(): boolean {
    return this.profileFollowingCount !== null || this.profileFollowersCount !== null;
  }

  private getSummaryLikesReceived(): number {
    if (this.summary === null) return 0;
    return (this.summary as UserSummary).likesReceived;
  }

  private getSummaryVisits(): number {
    if (this.summary === null) return 0;
    return (this.summary as UserSummary).daysVisited;
  }

  private getSummaryTopics(): number {
    if (this.summary === null) return 0;
    return (this.summary as UserSummary).topicCount;
  }

  private getSummaryReplies(): number {
    if (this.summary === null) return 0;
    return (this.summary as UserSummary).postCount;
  }

  private hasSummaryStats(): boolean {
    return this.summary !== null;
  }

  private hasProfileTrustLevel(): boolean {
    return this.getProfileTrustLevelText().trim().length > 0;
  }

  private hasRecentActivity(): boolean {
    if (this.profile === null) return false;
    const profile: User = this.profile as User;
    return profile.lastSeenAt !== null || profile.lastPostedAt !== null;
  }

  private getProfileStatusEmojiText(): string {
    if (this.profile === null) return '';
    const status: UserStatus | null = (this.profile as User).status;
    if (status === null || status.emoji === null) return '';
    return (status.emoji as string).trim();
  }

  private hasProfileExtraInfo(): boolean {
    if (this.profile === null) return false;
    const profile: User = this.profile as User;
    return this.hasProfileBio()
      || this.getProfileLocationText().length > 0
      || this.getProfileWebsiteText().length > 0
      || profile.createdAt !== null
      || profile.isSuspended
      || profile.isSilenced;
  }

  private hasRestrictionBanner(): boolean {
    if (this.profile === null) return false;
    const profile: User = this.profile as User;
    return profile.isSuspended || profile.isSilenced;
  }

  private getProfileLastSeenText(): string {
    if (this.profile === null) return '';
    const profile: User = this.profile as User;
    const targetTime: Date | null = profile.lastSeenAt !== null ? profile.lastSeenAt : profile.lastPostedAt;
    return TimeUtils.formatRelativeTime(targetTime);
  }

  private getSummaryTopicList(): SummaryTopic[] {
    if (this.summary === null) return [];
    return (this.summary as UserSummary).topics;
  }

  private getSummaryReplyList(): SummaryReply[] {
    if (this.summary === null) return [];
    return (this.summary as UserSummary).replies;
  }

  private getSummaryLinksList(): SummaryLink[] {
    if (this.summary === null) return [];
    return (this.summary as UserSummary).links;
  }

  private getSummaryMostRepliedToUsersList(): SummaryUserWithCount[] {
    if (this.summary === null) return [];
    return (this.summary as UserSummary).mostRepliedToUsers;
  }

  private getSummaryMostLikedByUsersList(): SummaryUserWithCount[] {
    if (this.summary === null) return [];
    return (this.summary as UserSummary).mostLikedByUsers;
  }

  private getSummaryMostLikedUsersList(): SummaryUserWithCount[] {
    if (this.summary === null) return [];
    return (this.summary as UserSummary).mostLikedUsers;
  }

  private getSummaryTopCategoriesList(): SummaryCategory[] {
    if (this.summary === null) return [];
    return (this.summary as UserSummary).topCategories;
  }

  private getSummaryBadgesList(): Badge[] {
    if (this.summary === null) return [];
    return (this.summary as UserSummary).badges;
  }

  private hasSummaryContent(): boolean {
    return this.getSummaryTopicList().length > 0
      || this.getSummaryReplyList().length > 0
      || this.getSummaryLinksList().length > 0
      || this.getSummaryMostRepliedToUsersList().length > 0
      || this.getSummaryMostLikedByUsersList().length > 0
      || this.getSummaryMostLikedUsersList().length > 0
      || this.getSummaryTopCategoriesList().length > 0
      || this.getSummaryBadgesList().length > 0;
  }

  private getReplyTopicTitle(reply: SummaryReply): string {
    if (reply.topic !== null) {
      const t: SummaryTopic = reply.topic as SummaryTopic;
      if (t.title.length > 0) return t.title;
    }
    return '回复';
  }

  private getSummaryLinkTitle(link: SummaryLink): string {
    if (link.title !== null && (link.title as string).length > 0) {
      return link.title as string;
    }
    if (link.url.length > 0) return link.url;
    return '链接';
  }

  private openSummaryTopic(topic: SummaryTopic): void {
    if (topic.id > 0) {
      RouterManager.pushTopicDetail(topic.id);
    }
  }

  private openSummaryReply(reply: SummaryReply): void {
    let topicId: number = 0;
    if (reply.topicId !== null) {
      topicId = reply.topicId as number;
    } else if (reply.topic !== null) {
      topicId = (reply.topic as SummaryTopic).id;
    }

    if (topicId <= 0) return;
    const postNumber: number = reply.postNumber > 0 ? reply.postNumber : 0;
    RouterManager.pushTopicDetail(topicId, postNumber);
  }

  private openSummaryLink(link: SummaryLink): void {
    if (link.topicId !== null && link.postNumber !== null) {
      const topicId: number = link.topicId as number;
      const postNumber: number = link.postNumber as number;
      if (topicId > 0 && postNumber > 0) {
        RouterManager.pushTopicDetail(topicId, postNumber);
        return;
      }
    }
    const url: string = UrlUtils.resolveUrl(link.url);
    if (url.length > 0) {
      ExternalLinkService.openInBrowser(url);
    }
  }

  private canShowFollowButton(): boolean {
    if (!this.isLoggedIn || this.profile === null || this.isOwnProfile) return false;
    return (this.profile as User).canFollow !== false;
  }

  private canOpenPrivateMessage(): boolean {
    if (!this.isLoggedIn || this.profile === null || this.isOwnProfile) return false;
    return (this.profile as User).canSendPrivateMessageToUser !== false;
  }

  private canManageNotificationLevel(): boolean {
    return this.isLoggedIn && this.profile !== null && !this.isOwnProfile;
  }

  private getProfileJoinedText(): string {
    if (this.profile === null) return '未知';
    return TimeUtils.formatShortDate((this.profile as User).createdAt);
  }

  private getProfileLastSeenDetailText(): string {
    if (this.profile === null) return '未知';
    const profile: User = this.profile as User;
    const targetTime: Date | null = profile.lastSeenAt !== null ? profile.lastSeenAt : profile.lastPostedAt;
    const text: string = TimeUtils.formatDetailTime(targetTime);
    return text.length > 0 ? text : '未知';
  }

  private getProfileLocationText(): string {
    if (this.profile === null) return '';
    const location: string | null = (this.profile as User).location;
    return location !== null ? location : '';
  }

  private getProfileWebsiteText(): string {
    if (this.profile === null) return '';
    const websiteName: string | null = (this.profile as User).websiteName;
    if (websiteName !== null && websiteName.trim().length > 0) {
      return websiteName;
    }
    const website: string | null = (this.profile as User).website;
    return website !== null ? website : '';
  }

  private getProfileWebsiteUrl(): string {
    if (this.profile === null) return '';
    const website: string | null = (this.profile as User).website;
    return website !== null ? website.trim() : '';
  }

  private openProfileWebsiteInApp(): void {
    const websiteUrl: string = this.getProfileWebsiteUrl();
    if (websiteUrl.length === 0) {
      return;
    }
    const websiteTitle: string = this.getProfileWebsiteText().trim().length > 0
      ? this.getProfileWebsiteText().trim()
      : '网站';
    this.closeUserInfoSheet();
    setTimeout(() => {
      RouterManager.pushWebView(websiteUrl, websiteTitle);
    }, 180);
  }

  private openFollowList(isFollowing: boolean): void {
    const username: string = this.getTargetUsername();
    if (username.length === 0) return;
    RouterManager.pushFollowList(username, isFollowing);
  }

  private openUserInfoSheet(): void {
    if (this.profile === null || !this.hasProfileExtraInfo()) return;
    this.isUserInfoSheetVisible = true;
  }

  private closeUserInfoSheet(): void {
    this.isUserInfoSheetVisible = false;
  }

  private openPrivateMessageSheet(): void {
    if (!this.canOpenPrivateMessage()) {
      if (!this.isLoggedIn) {
        ToastService.showLoginRequired();
      }
      return;
    }
    this.privateMessageSheetRequestKey = `pm_${Date.now()}`;
    this.isPrivateMessageSheetVisible = true;
  }

  private handlePrivateMessageSheetDismiss(_: boolean): void {
    this.isPrivateMessageSheetVisible = false;
    this.privateMessageSheetRequestKey = '';
  }

  private async toggleFollow(): Promise<void> {
    if (!this.isLoggedIn) {
      ToastService.showLoginRequired();
      return;
    }
    if (this.profile === null || this.isOwnProfile || this.isFollowLoading) {
      return;
    }

    const username: string = this.getTargetUsername();
    if (username.length === 0) return;

    const previous: boolean = this.isFollowed;
    this.isFollowLoading = true;
    try {
      const api: ApiClient = ApiClient.getInstance();
      if (previous) {
        await api.unfollowUser(username);
      } else {
        await api.followUser(username);
      }
      this.isFollowed = !previous;
      const currentFollowers: number = this.profileFollowersCount !== null ? this.profileFollowersCount as number : 0;
      this.profileFollowersCount = Math.max(0, currentFollowers + (previous ? -1 : 1));
      ToastService.show(this.isFollowed ? '已关注' : '已取消关注');
    } catch (err) {
      const message: string = err !== undefined && err !== null
        ? err.toString().replace('Error: ', '')
        : '操作失败';
      ToastService.show(message);
    } finally {
      this.isFollowLoading = false;
    }
  }

  private buildIgnoreExpiringAt(days: number): string {
    if (days <= 0) {
      return '';
    }
    return new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
  }

  private async updateNotificationLevel(level: string, expiringAt: string = ''): Promise<void> {
    if (!this.canManageNotificationLevel()) {
      if (!this.isLoggedIn) {
        ToastService.showLoginRequired();
      }
      return;
    }
    const username: string = this.getTargetUsername();
    if (username.length === 0) return;

    const previous: string = this.notificationLevel;
    this.notificationLevel = level;
    try {
      const api: ApiClient = ApiClient.getInstance();
      await api.updateUserNotificationLevel(username, level, expiringAt);
      if (level === 'ignore') {
        ToastService.show(expiringAt.length > 0 ? '已设置忽略' : '已永久忽略');
      } else if (level === 'mute') {
        ToastService.show('已设置免打扰');
      } else {
        ToastService.show('已恢复常规通知');
      }
    } catch (err) {
      this.notificationLevel = previous;
      const message: string = err !== undefined && err !== null
        ? err.toString().replace('Error: ', '')
        : '设置失败';
      ToastService.show(message);
    }
  }

  private getSummaryCategoryColor(category: SummaryCategory): string {
    if (category.color !== null && (category.color as string).length > 0) {
      return `#${category.color as string}`;
    }
    return '#3366CC';
  }

  private hexWithAlpha(hex: string, alpha: number): string {
    let colorHex: string = hex;
    if (colorHex.startsWith('#')) {
      colorHex = colorHex.substring(1);
    }
    const a: number = Math.max(0, Math.min(1, alpha));
    const alphaHex: string = Math.round(a * 255).toString(16).padStart(2, '0');
    if (colorHex.length === 6) {
      return `#${alphaHex}${colorHex}`;
    }
    if (colorHex.length === 8) {
      return `#${alphaHex}${colorHex.substring(2)}`;
    }
    return `#${alphaHex}3366CC`;
  }

  private getSummaryUserDisplayName(user: SummaryUserWithCount): string {
    if (user.name !== null && (user.name as string).trim().length > 0) {
      return (user.name as string).trim();
    }
    return user.username;
  }

  private getSummaryLinkSubtitle(link: SummaryLink): string {
    if (link.topic !== null && (link.topic as SummaryTopic).title.trim().length > 0) {
      return (link.topic as SummaryTopic).title.trim();
    }
    const resolvedUrl: string = UrlUtils.resolveUrl(link.url).trim();
    return resolvedUrl;
  }

  private getBadgeAccentColor(badge: Badge): string {
    if (badge.badgeTypeId === 1) return '#F59E0B';
    if (badge.badgeTypeId === 2) return '#78909C';
    return '#A1887F';
  }

  private getBadgeBackgroundColor(badge: Badge): string {
    return this.hexWithAlpha(this.getBadgeAccentColor(badge), 0.1);
  }

  private getBadgeBorderColor(badge: Badge): string {
    return this.hexWithAlpha(this.getBadgeAccentColor(badge), 0.28);
  }

  private getCompactCountText(count: number): string {
    if (count >= 10000) {
      return `${(count / 10000).toFixed(1)}w`;
    }
    if (count >= 1000) {
      return `${(count / 1000).toFixed(1)}k`;
    }
    return count.toString();
  }

  private openAvatarPreview(): void {
    const url: string = this.getProfileAvatarUrl(360);
    if (url.length === 0) return;
    RouterManager.pushImagePreview([url], 0);
  }

  private getSuspendedLabel(): string {
    if (this.profile === null) return '';
    const profile: User = this.profile as User;
    if (!profile.isSuspended) return '';
    if (profile.isSuspendedForever) {
      return '该用户已被永久封禁';
    }
    return `该用户已被封禁至 ${TimeUtils.formatDetailTime(profile.suspendedTill)}`;
  }

  private getSilencedLabel(): string {
    if (this.profile === null) return '';
    const profile: User = this.profile as User;
    if (!profile.isSilenced) return '';
    if (profile.isSilencedForever) {
      return '该用户已被永久禁言';
    }
    return `该用户已被禁言至 ${TimeUtils.formatDetailTime(profile.silencedTill)}`;
  }

  private getSuspendReasonText(): string {
    if (this.profile === null) return '';
    const reason: string | null = (this.profile as User).suspendReason;
    return reason !== null ? reason.trim() : '';
  }

  private getSilenceReasonText(): string {
    if (this.profile === null) return '';
    const reason: string | null = (this.profile as User).silenceReason;
    return reason !== null ? reason.trim() : '';
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Refresh({ refreshing: false }) {
          List({ scroller: this.scroller }) {
            ListItem() {
              Column() {
                // 关键：为“折叠区间”提供占位高度，使内容在完全折叠时从 pinned header 下方开始
                Blank().height(this.getExpandedHeight() - this.getPinnedHeaderHeight())

                this.CurrentTabContent()
              }
              .width('100%')
              .padding({ top: this.getPinnedHeaderHeight(), bottom: this.getBottomSafeHeight() })
            }
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.background'))
          .scrollBar(BarState.Off)
          .onScrollFrameBegin((offset: number, state: ScrollState) => {
            // 先按 offset 预测更新，保证折叠跟手；再异步用 scroller.currentOffset() 同步一次，避免到顶/到底回弹导致的“偏移漂移”。
            this.scrollOffset = Math.max(0, this.scrollOffset + offset);
            this.scheduleScrollOffsetSync();
            return { offsetRemain: offset };
          })
          .onReachEnd(() => {
            this.loadMoreForCurrentTab();
          })
        }
        .onRefreshing(() => {
          this.refreshCurrentTab();
        })

        Column() {
        }
        .width(0)
        .height(0)
        .bindSheet($$this.isPrivateMessageSheetVisible, this.PrivateMessageSheetBuilder, {
          height: SheetSize.LARGE,
          dragBar: false,
          showClose: false,
          backgroundColor: $r('app.color.surface')
        })

        Column() {
        }
        .width(0)
        .height(0)
        .bindSheet($$this.isUserInfoSheetVisible, this.UserInfoSheetBuilder, {
          height: SheetSize.MEDIUM,
          dragBar: false,
          showClose: false,
          backgroundColor: $r('app.color.surface')
        })

        // 顶部折叠头图 + pinned Tabs + pinned TopBar（ScrollOffset 驱动）
        this.CollapsingHeader()
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.background'))
    .hideTitleBar(true)
    .hideToolBar(true)
  }

  @Builder
  CollapsingHeader() {
    Column() {
      // FlexibleSpace（深色头图 + 遮罩 + 内容）
      Stack({ alignContent: Alignment.TopStart }) {
        // 背景：复刻安卓 Flutter 的 AnimatedGradientBackground（流体动效）
        AnimatedGradientBackground()
          .width('100%')
          // 固定 Canvas 的渲染尺寸，避免随折叠高度变化触发 Canvas 重建/重置导致滚动时闪烁
          .height(this.getFlexibleMaxHeight())

        if (this.hasProfileBackground()) {
          Image(this.getProfileBackgroundUrl())
            .width('100%')
            .height(this.getFlexibleMaxHeight())
            .objectFit(ImageFit.Cover)
        }

        // 统一压暗遮罩：展开 0.6 → 收起 0.85
        Column() {}
          .width('100%')
          .height(this.getFlexibleHeight())
          .backgroundColor(Color.Black)
          .opacity(this.getMaskAlpha())

        // 展开态内容（淡入/淡出）
        Column() {
          this.ExpandedHeaderContent()
        }
        .width('100%')
        .height('100%')
        .padding({ left: 20, right: 20, bottom: 24 })
        .justifyContent(FlexAlign.End)
        .opacity(this.getContentOpacity())

        // 收起态标题（淡入；点击回到顶部）
        Column() {
          Row() {
            AvatarWithFlair({
              avatarUrl: this.getProfileAvatarUrl(64),
              avatarSize: 32,
              avatarRadius: 16,
              fallbackText: this.getTargetUsername().length > 0 ? this.getTargetUsername() : 'U',
              bgColor: '#2A2E39',
              flairUrl: this.getProfileFlairUrl(),
              flairName: this.getProfileFlairName(),
              flairBgColor: this.getProfileFlairBgColor(),
              flairColor: this.getProfileFlairColor(),
              flairSize: 14
            })

            Text(this.getProfileDisplayName())
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .margin({ left: 12 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 60, right: 48, bottom: 14 })
        .justifyContent(FlexAlign.End)
        .opacity(this.getTitleOpacity())
        .onClick(() => {
          if (this.getTitleOpacity() > 0.5) {
            this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 220, curve: Curve.EaseOut } });
          }
        })

        // pinned TopBar（透明，白色图标）
        this.TopBarOverlay()
      }
      .width('100%')
      .height(this.getFlexibleHeight())
      .clip(true)

      // pinned Tabs（随 headerHeight 上移，最终停在 TopBar 下方）
      this.TabRowOverlay()
    }
    .width('100%')
    .height(this.computeHeaderHeight())
  }

  private computeHeaderHeight(): number {
    const raw: number = this.getExpandedHeight() - this.scrollOffset;
    return this.clamp(raw, this.getPinnedHeaderHeight(), this.getExpandedHeight());
  }

  private computeCollapseT(): number {
    // 对齐 Flutter：t=1 展开，t→0 收起（公式来自 LayoutBuilder 近似）
    const denom: number = Math.max(1, this.getExpandedHeight() - this.getTopBarHeight());
    return this.clamp(1 - this.scrollOffset / denom, 0, 1);
  }

  private computeTitleOpacity(t: number): number {
    if (t < 0.3) return 1;
    return this.clamp(1 - (t - 0.3) / 0.7, 0, 1);
  }

  private computeContentOpacity(t: number): number {
    return this.clamp((t - 0.4) / 0.6, 0, 1);
  }

  private computeMaskAlpha(t: number): number {
    // easeOut(1 - t) 近似：1 - (1-x)^2
    const x: number = this.clamp(1 - t, 0, 1);
    const eased: number = 1 - (1 - x) * (1 - x);
    // 对齐 Flutter：展开 0.6 → 收起 0.85
    return 0.6 + (0.85 - 0.6) * eased;
  }

  private clamp(v: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, v));
  }

  private getFlexibleHeight(): number {
    return Math.max(this.getTopBarHeight(), this.computeHeaderHeight() - TAB_HEIGHT);
  }

  private getFlexibleMaxHeight(): number {
    return Math.max(this.getTopBarHeight(), this.getExpandedHeight() - TAB_HEIGHT);
  }

  private getTopSafeHeight(): number {
    return WindowManager.getSystemAvoidAreaTopVp();
  }

  private getBottomSafeHeight(): number {
    return WindowManager.getSystemAvoidAreaBottomVp();
  }

  private getTopBarHeight(): number {
    return TOP_BAR_HEIGHT + this.getTopSafeHeight();
  }

  private getPinnedHeaderHeight(): number {
    return this.getTopBarHeight() + TAB_HEIGHT;
  }

  private getExpandedHeight(): number {
    return EXPANDED_HEIGHT + this.getTopSafeHeight();
  }

  private getTitleOpacity(): number {
    return this.computeTitleOpacity(this.computeCollapseT());
  }

  private getContentOpacity(): number {
    return this.computeContentOpacity(this.computeCollapseT());
  }

  private getMaskAlpha(): number {
    return this.computeMaskAlpha(this.computeCollapseT());
  }

  @Builder
  TopBarOverlay() {
    Row() {
      // 返回
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontColor([Color.White])
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        RouterManager.pop();
      })

      Blank().layoutWeight(1)

      // 右侧按钮：搜索 + 私信 + 更多
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          RouterManager.pushPath(RouteConstants.PAGE_SEARCH, `@${this.getTargetUsername()}` as Object);
        })

        if (this.canOpenPrivateMessage()) {
          Row() {
            SymbolGlyph($r('sys.symbol.message'))
              .fontSize(18)
              .fontColor([Color.White])
          }
          .width(44)
          .height(44)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.openPrivateMessageSheet();
          })
        }

        Row() {
          SymbolGlyph($r('sys.symbol.ellipsis_message'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .bindMenu(this.MoreMenuBuilder())
      }
      .width(this.canOpenPrivateMessage() ? 132 : 88)
      .height(TOP_BAR_HEIGHT)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(this.getTopBarHeight())
    .padding({ left: 8, right: 8, top: this.getTopSafeHeight() })
    .backgroundColor(Color.Transparent)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  MoreMenuBuilder() {
    Menu() {
      this.MoreMenuItem($r('sys.symbol.info_circle'), '关于用户', () => {
        this.openUserInfoSheet();
      })

      this.MoreMenuItem($r('sys.symbol.share'), '分享用户', () => {
        this.shareUser();
      })

      this.MoreMenuItem($r('sys.symbol.link'), '在浏览器中打开', () => {
        this.openUserInBrowser();
      })

      if (this.canManageNotificationLevel()) {
        this.MoreMenuItem($r('sys.symbol.bell'), '恢复常规通知', () => {
          this.updateNotificationLevel('normal').catch((_: Object) => {
          });
        })

        if (this.profile !== null && (this.profile as User).canMuteUser !== false) {
          this.MoreMenuItem($r('sys.symbol.bell'), '设为免打扰', () => {
            this.updateNotificationLevel('mute').catch((_: Object) => {
            });
          })
        }

        if (this.profile !== null && (this.profile as User).canIgnoreUser === true) {
          this.MoreMenuItem($r('sys.symbol.clock'), '忽略 1 天', () => {
            this.updateNotificationLevel('ignore', this.buildIgnoreExpiringAt(1)).catch((_: Object) => {
            });
          })

          this.MoreMenuItem($r('sys.symbol.clock'), '忽略 1 周', () => {
            this.updateNotificationLevel('ignore', this.buildIgnoreExpiringAt(7)).catch((_: Object) => {
            });
          })

          this.MoreMenuItem($r('sys.symbol.calendar'), '忽略 1 个月', () => {
            this.updateNotificationLevel('ignore', this.buildIgnoreExpiringAt(30)).catch((_: Object) => {
            });
          })

          this.MoreMenuItem($r('sys.symbol.xmark_circle_fill'), '永久忽略', () => {
            this.updateNotificationLevel('ignore').catch((_: Object) => {
            });
          })
        }
      }
    }
    .width(220)
    .backgroundColor('#2A2E39')
    .borderRadius(12)
    .shadow({ radius: 10, color: '#22000000', offsetX: 0, offsetY: 6 })
  }

  @Builder
  MoreMenuItem(icon: Resource, label: string, onSelect: () => void = () => {}) {
    MenuItem() {
      Row() {
        SymbolGlyph(icon)
          .fontSize(16)
          .fontColor([Color.White])
          .margin({ right: 10 })
        Text(label)
          .fontSize(14)
          .fontColor(Color.White)
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
    }
    .selected(false)
    .selectIcon(false)
    .height(44)
    .onChange((selected: boolean) => {
      if (selected) {
        onSelect();
      }
    })
  }

  @Builder
  ExpandedHeaderContent() {
    Column() {
      // 头像 + 名称/等级
      Row() {
        AvatarWithFlair({
          avatarUrl: this.getProfileAvatarUrl(144),
          avatarSize: HEADER_AVATAR_SIZE,
          avatarRadius: HEADER_AVATAR_SIZE / 2,
          fallbackText: this.getTargetUsername().length > 0 ? this.getTargetUsername() : 'U',
          bgColor: '#2A2E39',
          flairUrl: this.getProfileFlairUrl(),
          flairName: this.getProfileFlairName(),
          flairBgColor: this.getProfileFlairBgColor(),
          flairColor: this.getProfileFlairColor(),
          flairSize: 30
        })
        .onClick(() => {
          this.openAvatarPreview();
        })

        Column() {
          Row() {
            Text(this.getProfileDisplayName())
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if (this.getProfileStatusEmojiText().length > 0) {
              UserStatusEmoji({
                rawEmoji: this.getProfileStatusEmojiText(),
                iconSize: 16,
                marginLeft: 6
              })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(`@${this.getTargetUsername().length > 0 ? this.getTargetUsername() : 'user'}`)
            .fontSize(13)
            .fontColor('#B7BBC4')
            .margin({ top: 2, bottom: 6 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.hasProfileTrustLevel()) {
            Row() {
              Text(this.getProfileTrustLevelText())
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .backgroundColor('#33FFFFFF')
                .borderRadius(12)
            }
          }
        }
        .layoutWeight(1)
        .margin({ left: 14 })
        .alignItems(HorizontalAlign.Start)

        if (this.canShowFollowButton()) {
          Button() {
            Row() {
              SymbolGlyph(this.isFollowed ? $r('sys.symbol.checkmark') : $r('sys.symbol.plus'))
                .fontSize(14)
                .fontColor([this.isFollowed ? Color.White : Color.Black])
                .margin({ right: 4 })
              Text(this.isFollowLoading ? '处理中...' : (this.isFollowed ? '已关注' : '关注'))
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isFollowed ? Color.White : Color.Black)
            }
            .alignItems(VerticalAlign.Center)
          }
          .type(ButtonType.Capsule)
          .height(34)
          .enabled(!this.isFollowLoading)
          .backgroundColor(this.isFollowed ? '#26FFFFFF' : Color.White)
          .borderRadius(17)
          .onClick(() => {
            this.toggleFollow().catch((_: Object) => {
            });
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.hasRestrictionBanner()) {
        if (this.profile !== null && (this.profile as User).isSuspended) {
          this.ProfileRestrictionBanner($r('sys.symbol.xmark_circle_fill'), '#FF8C8C', this.getSuspendedLabel(), this.getSuspendReasonText())
        }
        if (this.profile !== null && (this.profile as User).isSilenced) {
          this.ProfileRestrictionBanner($r('sys.symbol.exclamationmark_triangle'), '#FFBC6A', this.getSilencedLabel(), this.getSilenceReasonText())
        }
      } else {
        Row() {
          Text(this.getProfileBioText())
            .fontSize(13)
            .fontColor(this.hasProfileBio() ? '#E8EAF0' : '#8CFFFFFF')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.hasProfileExtraInfo()) {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor(['#B7BBC4'])
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 14, bottom: 14 })
        .margin({ top: 14 })
        .backgroundColor('#1AFFFFFF')
        .borderRadius(10)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          if (this.hasProfileExtraInfo()) {
            this.openUserInfoSheet();
          }
        })
      }

      // 关注/粉丝
      if (this.hasFollowStats()) {
        Row() {
          if (this.getProfileFollowingCount() !== null) {
            this.HeaderStat(this.getCompactCountText(this.getProfileFollowingCount() as number), '关注', () => {
              this.openFollowList(true);
            })
          }
          if (this.getProfileFollowersCount() !== null) {
            this.HeaderStat(this.getCompactCountText(this.getProfileFollowersCount() as number), '粉丝', () => {
              this.openFollowList(false);
            })
          }
          Blank().layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 14 })
      }

      // 统计行
      if (this.hasSummaryStats()) {
        Row() {
          this.HeaderMiniStat(this.getCompactCountText(this.getSummaryLikesReceived()), '获赞')
          this.HeaderMiniStat(this.getCompactCountText(this.getSummaryVisits()), '访问')
          this.HeaderMiniStat(this.getCompactCountText(this.getSummaryTopics()), '话题')
          this.HeaderMiniStat(this.getCompactCountText(this.getSummaryReplies()), '回复')
        }
        .width('100%')
        .padding({ top: this.hasFollowStats() ? 12 : 14 })
      }

      // 最近活动时间（占位）
      if (this.hasRecentActivity()) {
        Row() {
          SymbolGlyph($r('sys.symbol.bolt_fill'))
            .fontSize(12)
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .fontColor(['#B3FFFFFF'])
            .margin({ right: 4 })
          Text(this.getProfileLastSeenText())
            .fontSize(11)
            .fontColor('#B3FFFFFF')
        }
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .backgroundColor('#26FFFFFF')
        .borderRadius(12)
        .margin({ top: 12 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  HeaderStat(value: string, label: string, onClick: () => void = () => {}) {
    Row() {
      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
      Text(` ${label}`)
        .fontSize(13)
        .fontColor('#B7BBC4')
    }
    .margin({ right: 18 })
    .onClick(() => {
      onClick();
    })
  }

  @Builder
  ProfileRestrictionBanner(icon: Resource, accentColor: string, label: string, reason: string) {
    Column() {
      Row() {
        SymbolGlyph(icon)
          .fontSize(18)
          .fontColor([accentColor])
          .margin({ right: 8 })
        Text(label)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (reason.trim().length > 0) {
        Text(reason)
          .fontSize(12)
          .fontColor('#D6D9E0')
          .margin({ top: 8 })
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .margin({ top: 14 })
    .backgroundColor('#1AFFFFFF')
    .borderRadius(12)
    .onClick(() => {
      this.openUserInfoSheet();
    })
  }

  @Builder
  HeaderMiniStat(value: string, label: string) {
    Column() {
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
      Text(label)
        .fontSize(12)
        .fontColor('#B7BBC4')
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  TabRowOverlay() {
    // 说明：
    // - 通过 CollapsingHeader 的 Column 布局保证其 y=flexibleHeight（展开时在头图底部，收起时 pinned 到 TopBar 下方）
    // - Scroll 内容已为 pinned header 预留 paddingTop，不需要额外占位 TabRow
    this.TabRow()
  }

  @Builder
  CurrentTabContent() {
    if (this.currentTabIndex === 0) {
      this.SummaryTab()
    } else if (this.currentTabIndex === 1) {
      this.ActionsTab('4,5')
    } else if (this.currentTabIndex === 2) {
      this.ActionsTab('4')
    } else if (this.currentTabIndex === 3) {
      this.ActionsTab('5')
    } else if (this.currentTabIndex === 4) {
      this.ActionsTab('1')
    } else {
      this.ReactionsTab()
    }
  }

  @Builder
  TabRow() {
    Column() {
      Row() {
        ForEach(this.tabLabels, (label: string, index: number) => {
          Column() {
            Text(label)
              .fontSize(14)
              .fontWeight(this.currentTabIndex === index ? FontWeight.Bold : FontWeight.Medium)
              .fontColor(this.currentTabIndex === index ? $r('app.color.on_surface') : $r('app.color.on_surface_secondary'))
              .padding({ left: 10, right: 10, top: 10, bottom: 8 })

            // 指示条
            Rect()
              .width(18)
              .height(3)
              .radius(2)
              .fill(this.currentTabIndex === index ? $r('app.color.primary') : Color.Transparent)
          }
          .layoutWeight(1)
          .height(TAB_HEIGHT)
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.selectTab(index);
          })
        })
      }
      .width('100%')
      .padding({ left: 0, right: 0 })
      .backgroundColor($r('app.color.surface'))

      Divider()
        .color($r('app.color.divider_light'))
        .strokeWidth(1)
        .margin({ left: 16, right: 16 })
    }
    .width('100%')
  }

  private scheduleScrollOffsetSync(): void {
    if (this.scrollSyncTimerId >= 0) return;
    this.scrollSyncTimerId = setTimeout(() => {
      this.scrollSyncTimerId = -1;
      const y: number = this.scroller.currentOffset().yOffset;
      this.scrollOffset = Math.max(0, y);
    }, 0);
  }

  private clearScrollSyncTimer(): void {
    if (this.scrollSyncTimerId >= 0) {
      clearTimeout(this.scrollSyncTimerId);
      this.scrollSyncTimerId = -1;
    }
  }

  private getActionFilterForTabIndex(index: number): string {
    if (index === 1) return '4,5';
    if (index === 2) return '4';
    if (index === 3) return '5';
    if (index === 4) return '1';
    return '';
  }

  private selectTab(index: number): void {
    if (this.currentTabIndex === index) return;
    this.currentTabIndex = index;
    this.clearScrollSyncTimer();
    this.scrollOffset = 0;
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 180, curve: Curve.EaseOut } });
    this.ensureTabLoaded(index);
  }

  private ensureTabLoaded(index: number): void {
    if (index === 0) return;

    if (index === 5) {
      if (!this.reactionsLoaded && !this.reactionsLoading) {
        this.loadReactions(false);
      }
      return;
    }

    const filter: string = this.getActionFilterForTabIndex(index);
    if (filter.length === 0) return;
    if (!this.getActionsLoaded(filter) && !this.getActionsLoading(filter)) {
      this.loadActions(filter, false);
    }
  }

  private refreshCurrentTab(): void {
    if (this.currentTabIndex === 0) {
      this.loadUserData();
      return;
    }

    if (this.currentTabIndex === 5) {
      this.reactionsLoadMoreFailed = false;
      this.reactionsError = '';
      this.reactionsHasMore = true;
      this.reactionsRequiresLogin = false;
      this.loadReactions(false);
      return;
    }

    const filter: string = this.getActionFilterForTabIndex(this.currentTabIndex);
    if (filter.length === 0) return;
    this.setActionsLoadMoreFailed(filter, false);
    this.setActionsError(filter, '');
    this.setActionsHasMore(filter, true);
    this.loadActions(filter, false);
  }

  private loadMoreForCurrentTab(): void {
    if (this.currentTabIndex === 0) return;

    if (this.currentTabIndex === 5) {
      if (this.reactionsLoadMoreFailed) return;
      this.loadReactions(true);
      return;
    }

    const filter: string = this.getActionFilterForTabIndex(this.currentTabIndex);
    if (filter.length === 0) return;
    if (this.getActionsLoadMoreFailed(filter)) return;
    this.loadActions(filter, true);
  }

  private getActionsList(filter: string): UserAction[] {
    if (filter === '4,5') return this.actionsAll;
    if (filter === '4') return this.actionsTopics;
    if (filter === '5') return this.actionsReplies;
    if (filter === '1') return this.actionsLikes;
    return [];
  }

  private setActionsList(filter: string, list: UserAction[]): void {
    if (filter === '4,5') this.actionsAll = list;
    else if (filter === '4') this.actionsTopics = list;
    else if (filter === '5') this.actionsReplies = list;
    else if (filter === '1') this.actionsLikes = list;
  }

  private getActionsLoaded(filter: string): boolean {
    if (filter === '4,5') return this.actionsAllLoaded;
    if (filter === '4') return this.actionsTopicsLoaded;
    if (filter === '5') return this.actionsRepliesLoaded;
    if (filter === '1') return this.actionsLikesLoaded;
    return false;
  }

  private setActionsLoaded(filter: string, value: boolean): void {
    if (filter === '4,5') this.actionsAllLoaded = value;
    else if (filter === '4') this.actionsTopicsLoaded = value;
    else if (filter === '5') this.actionsRepliesLoaded = value;
    else if (filter === '1') this.actionsLikesLoaded = value;
  }

  private getActionsHasMore(filter: string): boolean {
    if (filter === '4,5') return this.actionsAllHasMore;
    if (filter === '4') return this.actionsTopicsHasMore;
    if (filter === '5') return this.actionsRepliesHasMore;
    if (filter === '1') return this.actionsLikesHasMore;
    return false;
  }

  private setActionsHasMore(filter: string, value: boolean): void {
    if (filter === '4,5') this.actionsAllHasMore = value;
    else if (filter === '4') this.actionsTopicsHasMore = value;
    else if (filter === '5') this.actionsRepliesHasMore = value;
    else if (filter === '1') this.actionsLikesHasMore = value;
  }

  private getActionsLoading(filter: string): boolean {
    if (filter === '4,5') return this.actionsAllLoading;
    if (filter === '4') return this.actionsTopicsLoading;
    if (filter === '5') return this.actionsRepliesLoading;
    if (filter === '1') return this.actionsLikesLoading;
    return false;
  }

  private setActionsLoading(filter: string, value: boolean): void {
    if (filter === '4,5') this.actionsAllLoading = value;
    else if (filter === '4') this.actionsTopicsLoading = value;
    else if (filter === '5') this.actionsRepliesLoading = value;
    else if (filter === '1') this.actionsLikesLoading = value;
  }

  private getActionsLoadingMore(filter: string): boolean {
    if (filter === '4,5') return this.actionsAllLoadingMore;
    if (filter === '4') return this.actionsTopicsLoadingMore;
    if (filter === '5') return this.actionsRepliesLoadingMore;
    if (filter === '1') return this.actionsLikesLoadingMore;
    return false;
  }

  private setActionsLoadingMore(filter: string, value: boolean): void {
    if (filter === '4,5') this.actionsAllLoadingMore = value;
    else if (filter === '4') this.actionsTopicsLoadingMore = value;
    else if (filter === '5') this.actionsRepliesLoadingMore = value;
    else if (filter === '1') this.actionsLikesLoadingMore = value;
  }

  private getActionsLoadMoreFailed(filter: string): boolean {
    if (filter === '4,5') return this.actionsAllLoadMoreFailed;
    if (filter === '4') return this.actionsTopicsLoadMoreFailed;
    if (filter === '5') return this.actionsRepliesLoadMoreFailed;
    if (filter === '1') return this.actionsLikesLoadMoreFailed;
    return false;
  }

  private setActionsLoadMoreFailed(filter: string, value: boolean): void {
    if (filter === '4,5') this.actionsAllLoadMoreFailed = value;
    else if (filter === '4') this.actionsTopicsLoadMoreFailed = value;
    else if (filter === '5') this.actionsRepliesLoadMoreFailed = value;
    else if (filter === '1') this.actionsLikesLoadMoreFailed = value;
  }

  private getActionsError(filter: string): string {
    if (filter === '4,5') return this.actionsAllError;
    if (filter === '4') return this.actionsTopicsError;
    if (filter === '5') return this.actionsRepliesError;
    if (filter === '1') return this.actionsLikesError;
    return '';
  }

  private setActionsError(filter: string, value: string): void {
    if (filter === '4,5') this.actionsAllError = value;
    else if (filter === '4') this.actionsTopicsError = value;
    else if (filter === '5') this.actionsRepliesError = value;
    else if (filter === '1') this.actionsLikesError = value;
  }

  private getActionKey(action: UserAction): string {
    const type: number = action.actionType !== null ? action.actionType as number : 0;
    return `${action.topicId}_${action.postNumber}_${type}`;
  }

  private dedupActions(list: UserAction[]): UserAction[] {
    const seen: Map<string, boolean> = new Map();
    const out: UserAction[] = [];
    for (let i = 0; i < list.length; i++) {
      const a: UserAction = list[i];
      const key: string = this.getActionKey(a);
      if (!seen.has(key)) {
        seen.set(key, true);
        out.push(a);
      }
    }
    return out;
  }

  private mergeActions(base: UserAction[], incoming: UserAction[]): UserAction[] {
    const seen: Map<string, boolean> = new Map();
    const out: UserAction[] = [];

    for (let i = 0; i < base.length; i++) {
      const a: UserAction = base[i];
      const key: string = this.getActionKey(a);
      if (!seen.has(key)) {
        seen.set(key, true);
        out.push(a);
      }
    }

    for (let i = 0; i < incoming.length; i++) {
      const a: UserAction = incoming[i];
      const key: string = this.getActionKey(a);
      if (!seen.has(key)) {
        seen.set(key, true);
        out.push(a);
      }
    }

    return out;
  }

  private async loadActions(filter: string, loadMore: boolean = false): Promise<void> {
    const u: string = this.username.trim();
    if (u.length === 0) return;

    if (loadMore) {
      if (this.getActionsLoadMoreFailed(filter)) return; // 失败后需点 footer 重试
      if (this.getActionsLoading(filter) || this.getActionsLoadingMore(filter)) return;
      if (!this.getActionsHasMore(filter)) return;
      this.setActionsLoadingMore(filter, true);
    } else {
      if (this.getActionsLoading(filter)) return;
      this.setActionsLoading(filter, true);
      this.setActionsError(filter, '');
      this.setActionsLoadMoreFailed(filter, false);
      this.setActionsHasMore(filter, true);
    }

    const offset: number = loadMore ? this.getActionsList(filter).length : 0;
    try {
      const api: ApiClient = ApiClient.getInstance();
      const resp = await api.getUserActions(u, filter, offset);
      const incoming: UserAction[] = resp.actions;
      const nextList: UserAction[] = loadMore
        ? this.mergeActions(this.getActionsList(filter), incoming)
        : this.dedupActions(incoming);
      this.setActionsList(filter, nextList);
      this.setActionsLoaded(filter, true);
      this.setActionsHasMore(filter, incoming.length >= ACTION_PAGE_SIZE);
      this.setActionsError(filter, '');
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load user actions failed: %{public}s', JSON.stringify(err));
      if (loadMore) {
        this.setActionsLoadMoreFailed(filter, true);
      } else {
        this.setActionsError(filter, '加载失败');
      }
    } finally {
      if (loadMore) {
        this.setActionsLoadingMore(filter, false);
      } else {
        this.setActionsLoading(filter, false);
      }
    }
  }

  private dedupReactions(list: UserReaction[]): UserReaction[] {
    const seen: Map<number, boolean> = new Map();
    const out: UserReaction[] = [];
    for (let i = 0; i < list.length; i++) {
      const r: UserReaction = list[i];
      if (!seen.has(r.id)) {
        seen.set(r.id, true);
        out.push(r);
      }
    }
    return out;
  }

  private mergeReactions(base: UserReaction[], incoming: UserReaction[]): UserReaction[] {
    const seen: Map<number, boolean> = new Map();
    const out: UserReaction[] = [];
    for (let i = 0; i < base.length; i++) {
      const r: UserReaction = base[i];
      if (!seen.has(r.id)) {
        seen.set(r.id, true);
        out.push(r);
      }
    }
    for (let i = 0; i < incoming.length; i++) {
      const r: UserReaction = incoming[i];
      if (!seen.has(r.id)) {
        seen.set(r.id, true);
        out.push(r);
      }
    }
    return out;
  }

  private async loadReactions(loadMore: boolean = false): Promise<void> {
    const u: string = this.username.trim();
    if (u.length === 0) return;

    if (loadMore) {
      if (this.reactionsLoadMoreFailed) return;
      if (this.reactionsLoading || this.reactionsLoadingMore) return;
      if (!this.reactionsHasMore) return;
      this.reactionsLoadingMore = true;
    } else {
      if (this.reactionsLoading) return;
      this.reactionsLoading = true;
      this.reactionsError = '';
      this.reactionsLoadMoreFailed = false;
      this.reactionsHasMore = true;
      this.reactionsRequiresLogin = false;
    }

    const beforeId: number = loadMore && this.reactions.length > 0 ? this.reactions[this.reactions.length - 1].id : 0;
    try {
      const api: ApiClient = ApiClient.getInstance();
      const resp = await api.getUserReactions(u, beforeId);
      if (resp.requiresLogin()) {
        this.reactions = [];
        this.reactionsLoaded = true;
        this.reactionsHasMore = false;
        this.reactionsError = '';
        this.reactionsLoadMoreFailed = false;
        this.reactionsRequiresLogin = true;
        return;
      }
      const incoming: UserReaction[] = resp.reactions;
      const nextList: UserReaction[] = loadMore ? this.mergeReactions(this.reactions, incoming) : this.dedupReactions(incoming);
      this.reactions = nextList;
      this.reactionsLoaded = true;
      this.reactionsHasMore = incoming.length >= REACTION_PAGE_SIZE;
      this.reactionsError = '';
      this.reactionsRequiresLogin = false;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load user reactions failed: %{public}s', JSON.stringify(err));
      if (loadMore) {
        this.reactionsLoadMoreFailed = true;
      } else {
        this.reactionsError = '加载失败';
        this.reactionsRequiresLogin = false;
      }
    } finally {
      if (loadMore) {
        this.reactionsLoadingMore = false;
      } else {
        this.reactionsLoading = false;
      }
    }
  }

  private getUserShareUrl(): string {
    return ShareUtils.buildShareUrl(`/u/${this.getTargetUsername()}`);
  }

  private async shareUser(): Promise<void> {
    const url: string = this.getUserShareUrl();
    const ok: boolean = await SystemShareService.shareText(url, this.getTargetUsername(), false);
    if (ok) return;
    const copied: boolean = await ClipboardService.copyText(url, true);
    if (!copied) {
      ToastService.showShareFailed();
    }
  }

  private openUserInBrowser(): void {
    ExternalLinkService.openInBrowser(this.getUserShareUrl());
  }

  private stripHtml(input: string): string {
    if (input.length === 0) return input;
    try {
      return input.replace(/<[^>]+>/g, '').trim();
    } catch (_) {
      return input;
    }
  }

  private getUserActionIcon(actionType: number | null): Resource {
    if (actionType === null) return $r('sys.symbol.clock');
    const t: number = actionType as number;
    if (t === UserActionType.LIKE) return $r('sys.symbol.heart_fill');
    if (t === UserActionType.WAS_LIKED) return $r('sys.symbol.heart');
    if (t === UserActionType.NEW_TOPIC) return $r('sys.symbol.doc_text');
    if (t === UserActionType.REPLY) return $r('sys.symbol.message');
    return $r('sys.symbol.clock');
  }

  private getUserActionLabel(actionType: number | null): string {
    if (actionType === null) return '动态';
    const t: number = actionType as number;
    if (t === UserActionType.LIKE) return '点赞';
    if (t === UserActionType.WAS_LIKED) return '被赞';
    if (t === UserActionType.NEW_TOPIC) return '发布了话题';
    if (t === UserActionType.REPLY) return '回复了';
    return '动态';
  }

  @Builder
  SummaryTab() {
    if (this.isLoading) {
      Column() {
        LoadingSpinner({ message: '' })
      }
      .width('100%')
      .height(220)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.background'))
    } else if (this.errorMessage.length > 0) {
      Column() {
        ErrorView({
          title: $r('app.string.load_failed'),
          message: this.errorMessage,
          showRetry: true,
          onRetry: () => {
            this.loadUserData();
          }
        })
      }
      .width('100%')
      .height(220)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.background'))
    } else if (this.summary === null) {
      Column() {
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(26)
          .fontColor([$r('app.color.on_surface_tertiary')])
          .margin({ bottom: 10 })
        Text('暂无总结数据')
          .fontSize(14)
          .fontColor($r('app.color.on_surface_secondary'))
      }
      .width('100%')
      .height(220)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.background'))
    } else {
      Column() {
        if (!this.hasSummaryContent()) {
          Column() {
            SymbolGlyph($r('sys.symbol.info_circle'))
              .fontSize(26)
              .fontColor([$r('app.color.on_surface_tertiary')])
              .margin({ bottom: 10 })
            Text('暂无总结数据')
              .fontSize(14)
              .fontColor($r('app.color.on_surface_secondary'))
          }
          .width('100%')
          .height(220)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
    } else {
      if (this.getSummaryTopicList().length > 0) {
            this.SectionTitle('热门话题', $r('sys.symbol.doc_text'))
            ForEach(this.getSummaryTopicList(), (t: SummaryTopic) => {
              this.SimpleTopicRow(t.title, t.likeCount, () => {
                this.openSummaryTopic(t);
              })
            }, (t: SummaryTopic) => t.id.toString())
          }

          if (this.getSummaryReplyList().length > 0) {
            this.SectionTitle('热门回复', $r('sys.symbol.message'))
            ForEach(this.getSummaryReplyList(), (r: SummaryReply) => {
              this.SimpleTopicRow(this.getReplyTopicTitle(r), r.likeCount, () => {
                this.openSummaryReply(r);
              })
            }, (_r: SummaryReply, index: number) => index.toString())
          }

          if (this.getSummaryLinksList().length > 0) {
            this.SectionTitle('热门链接', $r('sys.symbol.link'))
            ForEach(this.getSummaryLinksList(), (l: SummaryLink) => {
              this.SimpleLinkRow(l, () => {
                this.openSummaryLink(l);
              })
            }, (_l: SummaryLink, index: number) => index.toString())
          }

          if (this.getSummaryMostRepliedToUsersList().length > 0) {
            this.SectionTitle('最多回复至', $r('sys.symbol.arrowshape_turn_up_left'))
            this.UserChipRow(this.getSummaryMostRepliedToUsersList())
          }

          if (this.getSummaryMostLikedByUsersList().length > 0) {
            this.SectionTitle('被谁赞的最多', $r('sys.symbol.heart_fill'))
            this.UserChipRow(this.getSummaryMostLikedByUsersList())
          }

          if (this.getSummaryMostLikedUsersList().length > 0) {
            this.SectionTitle('赞最多', $r('sys.symbol.hand_thumbsup'))
            this.UserChipRow(this.getSummaryMostLikedUsersList())
          }

          if (this.getSummaryTopCategoriesList().length > 0) {
            this.SectionTitle('热门类别', $r('sys.symbol.label'))
            this.CategoryChipRow(this.getSummaryTopCategoriesList())
          }

          if (this.getSummaryBadgesList().length > 0) {
            this.SectionTitle('热门徽章', $r('sys.symbol.medal'))
            this.BadgeChipRow(this.getSummaryBadgesList())
          }
        }

        Blank().height(24)
      }
      .width('100%')
      .backgroundColor($r('app.color.background'))
    }
  }

  @Builder
  ActionsTab(filter: string) {
    if (this.getActionsLoading(filter) && this.getActionsList(filter).length === 0 && this.getActionsError(filter).length === 0) {
      Column() {
        LoadingSpinner({ message: '' })
      }
      .width('100%')
      .height(220)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.background'))
    } else if (this.getActionsError(filter).length > 0 && this.getActionsList(filter).length === 0) {
      Column() {
        ErrorView({
          title: $r('app.string.load_failed'),
          message: this.getActionsError(filter),
          showRetry: true,
          onRetry: () => {
            this.loadActions(filter, false);
          }
        })
      }
      .width('100%')
      .height(220)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.background'))
    } else {
    Column() {
      if (!this.getActionsLoading(filter) && this.getActionsList(filter).length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(26)
            .fontColor([$r('app.color.on_surface_tertiary')])
            .margin({ bottom: 10 })
          Text($r('app.string.empty_data'))
            .fontSize(14)
            .fontColor($r('app.color.on_surface_secondary'))
        }
        .width('100%')
        .height(220)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        ForEach(this.getActionsList(filter), (a: UserAction) => {
          this.UserActionCard(a)
        }, (a: UserAction) => this.getActionKey(a))

        // footer：加载中 / 失败重试 / 加载更多
        if (this.getActionsLoadingMore(filter)) {
          Row() {
            LoadingProgress()
              .width(16)
              .height(16)
            Text($r('app.string.loading'))
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'))
              .margin({ left: 8 })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        } else if (this.getActionsLoadMoreFailed(filter)) {
          Row() {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
              .fontSize(16)
              .fontColor([$r('app.color.on_surface_secondary')])
            Text($r('app.string.load_failed_tap_retry'))
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'))
              .margin({ left: 8 })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.setActionsLoadMoreFailed(filter, false);
            this.loadActions(filter, true);
          })
        } else if (this.getActionsHasMore(filter)) {
          Row() {
            Text($r('app.string.load_more'))
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'))
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.loadActions(filter, true);
          })
        }
      }

      Blank().height(24)
    }
    .width('100%')
    .backgroundColor($r('app.color.background'))
    }
  }

  @Builder
  ReactionsTab() {
    if (this.reactionsLoading && this.reactions.length === 0 && this.reactionsError.length === 0) {
      Column() {
        LoadingSpinner({ message: '' })
      }
      .width('100%')
      .height(220)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.background'))
    } else if (this.reactionsError.length > 0 && this.reactions.length === 0) {
      Column() {
        ErrorView({
          title: $r('app.string.load_failed'),
          message: this.reactionsError,
          showRetry: true,
          onRetry: () => {
            this.loadReactions(false);
          }
        })
      }
      .width('100%')
      .height(220)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.background'))
    } else {
    Column() {
      if (this.reactionsRequiresLogin && !this.isLoggedIn) {
        Column() {
          SymbolGlyph($r('sys.symbol.lock'))
            .fontSize(26)
            .fontColor([$r('app.color.on_surface_tertiary')])
            .margin({ bottom: 10 })
          Text('回应仅登录后可查看')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'))
          Text('游客态无法查看该用户收到的回应')
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 6 })
        }
        .width('100%')
        .height(220)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (!this.reactionsLoading && this.reactions.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.message'))
            .fontSize(26)
            .fontColor([$r('app.color.on_surface_tertiary')])
            .margin({ bottom: 10 })
          Text('暂无回应')
            .fontSize(14)
            .fontColor($r('app.color.on_surface_secondary'))
        }
        .width('100%')
        .height(220)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        ForEach(this.reactions, (r: UserReaction) => {
          this.UserReactionCard(r)
        }, (r: UserReaction) => r.id.toString())

        if (this.reactionsLoadingMore) {
          Row() {
            LoadingProgress()
              .width(16)
              .height(16)
            Text($r('app.string.loading'))
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'))
              .margin({ left: 8 })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        } else if (this.reactionsLoadMoreFailed) {
          Row() {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
              .fontSize(16)
              .fontColor([$r('app.color.on_surface_secondary')])
            Text($r('app.string.load_failed_tap_retry'))
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'))
              .margin({ left: 8 })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.reactionsLoadMoreFailed = false;
            this.loadReactions(true);
          })
        } else if (this.reactionsHasMore) {
          Row() {
            Text($r('app.string.load_more'))
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'))
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.loadReactions(true);
          })
        }
      }

      Blank().height(24)
    }
    .width('100%')
    .backgroundColor($r('app.color.background'))
    }
  }

  @Builder
  PlaceholderTab(label: string) {
    Column() {
      SymbolGlyph($r('sys.symbol.clock'))
        .fontSize(26)
        .fontColor([$r('app.color.on_surface_tertiary')])
        .margin({ bottom: 10 })
      Text(`${label}（UI 占位）`)
        .fontSize(14)
        .fontColor($r('app.color.on_surface_secondary'))
    }
    .width('100%')
    .height(220)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  SectionTitle(title: string, icon: Resource) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([$r('app.color.primary')])
        .margin({ right: 8 })
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 20, bottom: 10 })
  }

  @Builder
  SimpleTopicRow(title: string, count: number, onClick: () => void = () => {}) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface'))
        .lineHeight(22)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ right: 12 })

      Row() {
        SymbolGlyph($r('sys.symbol.heart'))
        .fontSize(14)
          .fontColor([$r('app.color.on_surface_tertiary')])
        Text(` ${count}`)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
      }
      .padding({ left: 10, right: 4, top: 2, bottom: 2 })
    }
    .width('100%')
    .padding({ left: 18, right: 16, top: 14, bottom: 14 })
    .backgroundColor('#F7F8FC')
    .borderRadius(18)
    .border({ width: 1, color: '#EEF1F6' })
    .shadow({ radius: 6, color: '#10000000', offsetX: 0, offsetY: 2 })
    .margin({ left: 16, right: 16, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      onClick();
    })
  }

  @Builder
  SimpleLinkRow(link: SummaryLink, onClick: () => void = () => {}) {
    Row() {
      SymbolGlyph($r('sys.symbol.link'))
        .fontSize(18)
        .fontColor([$r('app.color.on_surface_secondary')])
        .margin({ right: 10 })

      Column() {
        Text(this.getSummaryLinkTitle(link))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.getSummaryLinkSubtitle(link).length > 0) {
          Text(this.getSummaryLinkSubtitle(link))
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(`${link.clicks} 次点击`)
        .fontSize(12)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 18, right: 16, top: 14, bottom: 14 })
    .backgroundColor('#F7F8FC')
    .borderRadius(18)
    .border({ width: 1, color: '#EEF1F6' })
    .shadow({ radius: 6, color: '#10000000', offsetX: 0, offsetY: 2 })
    .margin({ left: 16, right: 16, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      onClick();
    })
  }

  @Builder
  UserActionCard(action: UserAction) {
    Column() {
      // 头部：动作类型 + 时间
      Row() {
        SymbolGlyph(this.getUserActionIcon(action.actionType))
          .fontSize(16)
          .fontColor([$r('app.color.primary')])
        Text(` ${this.getUserActionLabel(action.actionType)}`)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary'))

        Blank().layoutWeight(1)

        if (action.actingAt !== null) {
          Text(TimeUtils.formatRelativeTime(action.actingAt))
            .fontSize(11)
            .fontColor($r('app.color.on_surface_tertiary'))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 标题
      Text(action.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 10 })

      // 摘要
      if (action.excerpt !== null && (action.excerpt as string).length > 0) {
        Text(this.stripHtml(action.excerpt as string))
          .fontSize(13)
          .fontColor($r('app.color.on_surface_secondary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(20)
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#F7F8FC')
    .borderRadius(18)
    .border({ width: 1, color: '#EEF1F6' })
    .shadow({ radius: 6, color: '#10000000', offsetX: 0, offsetY: 2 })
    .margin({ left: 16, right: 16, bottom: 12 })
    .onClick(() => {
      if (action.topicId <= 0) return;
      const postNumber: number = action.postNumber > 0 ? action.postNumber : 0;
      RouterManager.pushTopicDetail(action.topicId, postNumber);
    })
  }

  @Builder
  UserReactionCard(reaction: UserReaction) {
    Column() {
      // 头部：回应 + 时间
      Row() {
        SymbolGlyph($r('sys.symbol.star'))
          .fontSize(16)
          .fontColor([$r('app.color.primary')])
        Text(` 回应了${reaction.reactionValue !== null && (reaction.reactionValue as string).length > 0 ? ' ' + (reaction.reactionValue as string) : ''}`)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary'))

        Blank().layoutWeight(1)

        if (reaction.createdAt !== null) {
          Text(TimeUtils.formatRelativeTime(reaction.createdAt))
            .fontSize(11)
            .fontColor($r('app.color.on_surface_tertiary'))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (reaction.topicTitle !== null && (reaction.topicTitle as string).length > 0) {
        Text(reaction.topicTitle as string)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 10 })
      }

      if (reaction.excerpt !== null && (reaction.excerpt as string).length > 0) {
        Text(this.stripHtml(reaction.excerpt as string))
          .fontSize(13)
          .fontColor($r('app.color.on_surface_secondary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(20)
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#F7F8FC')
    .borderRadius(18)
    .border({ width: 1, color: '#EEF1F6' })
    .shadow({ radius: 6, color: '#10000000', offsetX: 0, offsetY: 2 })
    .margin({ left: 16, right: 16, bottom: 12 })
    .onClick(() => {
      if (reaction.topicId <= 0) return;
      const postNumber: number = reaction.postNumber > 0 ? reaction.postNumber : 0;
      RouterManager.pushTopicDetail(reaction.topicId, postNumber);
    })
  }

  @Builder
  UserChipRow(users: SummaryUserWithCount[]) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(users, (u: SummaryUserWithCount) => {
        Row() {
          SmartAvatar({
            avatarUrl: u.getAvatarUrl(72),
            avatarSize: 24,
            avatarRadius: 12,
            fallbackText: u.username,
            bgColor: '#E8EAF0'
          })
          Text(this.getSummaryUserDisplayName(u))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'))
            .margin({ left: 6 })

          Text(u.count.toString())
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor('#31598F')
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .backgroundColor('#E4EEFF')
            .borderRadius(10)
            .margin({ left: 6 })
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor('#F7F8FC')
        .borderRadius(18)
        .border({ width: 1, color: '#EEF1F6' })
        .margin({ right: 10, bottom: 10 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          RouterManager.pushUserProfile(u.username);
        })
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  CategoryChipRow(categories: SummaryCategory[]) {
    Column() {
      ForEach(categories, (c: SummaryCategory) => {
        Row() {
          Rect()
            .width(16)
            .height(16)
            .radius(5)
            .fill(this.getSummaryCategoryColor(c))
            .margin({ right: 10 })

          Text(c.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'))
            .layoutWeight(1)

          Text(`${c.topicCount} 话题`)
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))

          Text(`${c.postCount} 回复`)
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ left: 14 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 18, bottom: 18 })
        .backgroundColor('#F7F8FC')
        .borderRadius(18)
        .border({ width: 1, color: '#EEF1F6' })
        .shadow({ radius: 6, color: '#10000000', offsetX: 0, offsetY: 2 })
        .margin({ bottom: 12 })
        .alignItems(VerticalAlign.Center)
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  BadgeChipRow(badges: Badge[]) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(badges, (b: Badge) => {
        Row() {
          SymbolGlyph($r('sys.symbol.medal'))
            .fontSize(14)
            .fontColor([this.getBadgeAccentColor(b)])
            .margin({ right: 6 })
          Text(b.name)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'))
        }
        .padding({ left: 12, right: 12, top: 7, bottom: 7 })
        .backgroundColor(this.getBadgeBackgroundColor(b))
        .border({ width: 1, color: this.getBadgeBorderColor(b) })
        .borderRadius(14)
        .margin({ right: 10, bottom: 10 })
        .alignItems(VerticalAlign.Center)
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  PrivateMessageSheetBuilder() {
    PrivateMessageComposerSheet({
      targetUsername: this.getTargetUsername(),
      targetAvatarUrl: this.getProfileAvatarUrl(80),
      requestKey: this.privateMessageSheetRequestKey,
      onDismiss: (submitted: boolean) => {
        this.handlePrivateMessageSheetDismiss(submitted);
      }
    })
  }

  @Builder
  UserInfoSheetBuilder() {
    Column() {
      Row() {
      }
      .width(34)
      .height(4)
      .backgroundColor('#D9DDE5')
      .borderRadius(2)
      .margin({ top: 12, bottom: 16 })

      Row() {
        Text('关于')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
        Blank().layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 16 })

      Row() {
      }
      .width('100%')
      .height(1)
      .margin({ left: 16, right: 16 })
      .backgroundColor('#EEF1F5')

      Scroll() {
        Column() {
          if (this.profile !== null && (this.profile as User).isSuspended) {
            this.UserInfoAlertCard(
              '封禁状态',
              $r('sys.symbol.xmark_circle_fill'),
              '#D9485F',
              '#FFF4F6',
              '#F7D8DE',
              this.getSuspendedLabel(),
              this.getSuspendReasonText()
            )
          }

          if (this.profile !== null && (this.profile as User).isSilenced) {
            this.UserInfoAlertCard(
              '禁言状态',
              $r('sys.symbol.exclamationmark_triangle'),
              '#E08821',
              '#FFF8EE',
              '#F4D7B0',
              this.getSilencedLabel(),
              this.getSilenceReasonText()
            )
          }

          if (this.getProfileBioCookedHtml().length > 0) {
            this.UserInfoSectionTitle('个人简介')
            PostRichContent({
              cookedHtml: this.getProfileBioCookedHtml(),
              blockGapVp: 6,
              onOpenLink: (url: string) => {
                ExternalLinkService.openInBrowser(url);
              },
              onOpenImagePreview: (urls: string[], initialIndex: number) => {
                RouterManager.pushImagePreview(urls, initialIndex);
              }
            })
              .width('100%')
          } else if (this.hasProfileBio()) {
            this.UserInfoSectionTitle('个人简介')
            Text(this.getProfileBioText())
              .fontSize(15)
              .lineHeight(24)
              .fontColor($r('app.color.on_surface'))
              .width('100%')
          }

          if (this.getProfileLocationText().length > 0
            || this.getProfileWebsiteText().length > 0
            || (this.profile !== null && (this.profile as User).createdAt !== null)) {
            this.UserInfoSectionTitle('更多信息')

            if (this.getProfileLocationText().length > 0) {
              this.UserInfoRow($r('sys.symbol.info_circle'), '位置', this.getProfileLocationText())
            }

            if (this.getProfileWebsiteText().length > 0) {
              this.UserInfoRow($r('sys.symbol.link'), '网站', this.getProfileWebsiteText(), true, () => {
                this.openProfileWebsiteInApp();
              })
            }

            if (this.profile !== null && (this.profile as User).createdAt !== null) {
              this.UserInfoRow($r('sys.symbol.calendar'), '加入时间', this.getProfileJoinedText())
            }
          }
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 24 + WindowManager.getSystemAvoidAreaBottomVp() })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface'))
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  UserInfoSectionTitle(title: string) {
    Text(title)
      .fontSize(15)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.primary'))
      .width('100%')
      .margin({ top: 28, bottom: 14 })
  }

  @Builder
  UserInfoAlertCard(title: string, icon: Resource, accentColor: string, backgroundColor: string, borderColor: string,
    label: string, reason: string) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(accentColor)
        .width('100%')
        .margin({ bottom: 12 })

      Row() {
        SymbolGlyph(icon)
          .fontSize(18)
          .fontColor([accentColor])
          .margin({ right: 8 })
        Text(label)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (reason.trim().length > 0) {
        Text(reason)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ top: 8 })
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(backgroundColor)
    .border({ width: 1, color: borderColor })
    .borderRadius(16)
    .margin({ bottom: 24 })
  }

  @Builder
  UserInfoRow(icon: Resource, label: string, value: string, clickable: boolean = false, onClick: () => void = () => {}) {
    Row() {
      Row() {
        SymbolGlyph(icon)
          .fontSize(18)
          .fontColor([$r('app.color.on_surface_secondary')])
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor('#F2F5F8')
      .borderRadius(12)

      Column() {
        Text(label)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(value)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .margin({ left: 14, right: 12 })
      .alignItems(HorizontalAlign.Start)

      if (clickable && value.length > 0) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(13)
          .fontColor([$r('app.color.on_surface_tertiary')])
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#FAFBFC')
    .border({ width: 1, color: '#EDF1F5' })
    .borderRadius(16)
    .margin({ bottom: 12 })
    .onClick(() => {
      if (clickable && value.length > 0) {
        onClick();
      }
    })
  }
}
