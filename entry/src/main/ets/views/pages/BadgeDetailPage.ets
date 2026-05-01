import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { Badge, BadgeDetailResponse, BadgeUser, UserBadge } from '../../models/Badge';
import { ApiClient } from '../../services/network/ApiClient';
import { RouterManager } from '../../common/utils/RouterManager';
import { WindowManager } from '../../common/utils/WindowManager';
import { ThemeManager } from '../../common/theme/ThemeManager';
import { BadgeIconResolver } from '../../common/utils/BadgeIconResolver';
import { EmojiResolver } from '../../common/utils/EmojiResolver';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';
import { SmartAvatar } from '../components/SmartAvatar';
import { TimeUtils } from '../../common/utils/TimeUtils';
import { PostRichContent } from '../components/PostRichContent';
import { ImmersiveHdsTitleBarHelper } from '../components/ImmersiveHdsTitleBarHelper';

const HERO_HEIGHT: number = 210;

@ComponentV2
export struct BadgeDetailPage {
  @Param badgeId: number = 0;
  @Param badgeSlug: string = '';
  @Param username: string = '';

  @Local detail: BadgeDetailResponse = new BadgeDetailResponse();
  @Local isLoading: boolean = true;
  @Local isRefreshing: boolean = false;
  @Local errorMessage: string = '';
  @Local heroImageFailed: boolean = false;

  private contentScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    WindowManager.applyDefaultSystemChrome();
    if (this.detail.userBadges.length === 0) {
      this.loadDetail(true).catch(() => {
      });
    }
  }

  aboutToDisappear(): void {
    WindowManager.applyDefaultSystemChrome();
  }

  private normalizeErrorMessage(err: Object): string {
    if (err === undefined || err === null) {
      return '加载徽章详情失败';
    }
    const text: string = err.toString().replace('Error: ', '').trim();
    return text.length > 0 ? text : '加载徽章详情失败';
  }

  private async loadDetail(showLoading: boolean): Promise<void> {
    if (this.badgeId <= 0) {
      this.errorMessage = '无效的徽章';
      this.isLoading = false;
      this.isRefreshing = false;
      return;
    }
    if (showLoading) {
      this.isLoading = true;
    } else {
      this.isRefreshing = true;
    }
    this.errorMessage = '';
    this.heroImageFailed = false;

    try {
      const api: ApiClient = ApiClient.getInstance();
      const badge: Badge = await api.getBadge(this.badgeId);
      const response: BadgeDetailResponse = await api.getBadgeUsers(this.badgeId, this.username);
      response.badge = badge;
      if (response.totalCount <= 0) {
        response.totalCount = badge.grantCount > 0 ? badge.grantCount : response.userBadges.length;
      }
      this.detail = response;
    } catch (err) {
      this.errorMessage = this.normalizeErrorMessage(err);
    } finally {
      this.isLoading = false;
      this.isRefreshing = false;
    }
  }

  private getBadgeColor(badgeTypeId: number): string {
    if (badgeTypeId === 1) return '#F59E0B';
    if (badgeTypeId === 2) return '#78909C';
    return '#A1887F';
  }

  private getBadgeTypeLabel(badgeTypeId: number): string {
    if (badgeTypeId === 1) return '金牌徽章';
    if (badgeTypeId === 2) return '银牌徽章';
    return '铜牌徽章';
  }

  private findGrantedUser(userId: number): BadgeUser | null {
    for (let i = 0; i < this.detail.grantedUsers.length; i++) {
      const item: BadgeUser = this.detail.grantedUsers[i];
      if (item.id === userId) {
        return item;
      }
    }
    return null;
  }

  private openUserBadge(userBadge: UserBadge): void {
    if (userBadge.topicId !== null && (userBadge.topicId as number) > 0) {
      const postNumber: number = userBadge.postNumber !== null ? userBadge.postNumber as number : 0;
      RouterManager.pushTopicDetail(userBadge.topicId as number, postNumber);
      return;
    }
    const grantedUser: BadgeUser | null = this.findGrantedUser(userBadge.userId);
    if (grantedUser !== null && (grantedUser as BadgeUser).username.trim().length > 0) {
      RouterManager.pushUserProfile((grantedUser as BadgeUser).username);
      return;
    }
    if (userBadge.username !== null && (userBadge.username as string).trim().length > 0) {
      RouterManager.pushUserProfile(userBadge.username as string);
    }
  }

  private getBadgeAccentColor(): string {
    return this.getBadgeColor(this.detail.badge.badgeTypeId);
  }

  private getGrantedCount(): number {
    if (this.detail.badge.grantCount > 0) {
      return this.detail.badge.grantCount;
    }
    if (this.detail.totalCount > 0) {
      return this.detail.totalCount;
    }
    return this.detail.userBadges.length;
  }

  private getAwardedUserCount(): number {
    return this.detail.userBadges.length;
  }

  private getUserDisplayName(userBadge: UserBadge): string {
    const grantedUser: BadgeUser | null = this.findGrantedUser(userBadge.userId);
    if (grantedUser !== null && (grantedUser as BadgeUser).username.trim().length > 0) {
      return (grantedUser as BadgeUser).username;
    }
    if (userBadge.username !== null && (userBadge.username as string).trim().length > 0) {
      return userBadge.username as string;
    }
    return `用户 #${userBadge.userId}`;
  }

  private getUserAvatarUrl(userBadge: UserBadge): string {
    const grantedUser: BadgeUser | null = this.findGrantedUser(userBadge.userId);
    return grantedUser !== null ? (grantedUser as BadgeUser).getAvatarUrl(96) : '';
  }

  private isBadgeAdmin(userBadge: UserBadge): boolean {
    const grantedUser: BadgeUser | null = this.findGrantedUser(userBadge.userId);
    return grantedUser !== null && (grantedUser as BadgeUser).admin;
  }

  private isBadgeModerator(userBadge: UserBadge): boolean {
    const grantedUser: BadgeUser | null = this.findGrantedUser(userBadge.userId);
    return grantedUser !== null && (grantedUser as BadgeUser).moderator;
  }

  private getTopSafeHeight(): number {
    return WindowManager.getSystemAvoidAreaTopVp();
  }

  private getHeroHeight(): number {
    return HERO_HEIGHT + this.getTopSafeHeight();
  }

  private getNavigationTitle(): string {
    const badgeName: string = this.detail.badge.name.trim();
    return badgeName.length > 0 ? badgeName : '徽章';
  }

  private escapeHtml(raw: string): string {
    let out: string = raw;
    out = out.replace(/&/g, '&amp;');
    out = out.replace(/</g, '&lt;');
    out = out.replace(/>/g, '&gt;');
    return out;
  }

  private buildRichTextHtml(raw: string | null): string {
    const text: string = raw !== null && raw !== undefined ? raw.toString().trim() : '';
    if (text.length === 0) {
      return '';
    }
    const escaped: string = this.escapeHtml(text);
    const emojiReplaced: string = escaped.replace(/:([a-zA-Z0-9_+\-.]+):/g, (match: string, name: string): string => {
      const url: string = EmojiResolver.resolveEmojiUrl(name);
      if (url.length === 0) {
        return match;
      }
      return `<img src="${url}" alt=":${name}:" class="emoji" title=":${name}:">`;
    });
    const lineBreakReplaced: string = emojiReplaced.replace(/\r?\n/g, '<br>');
    return `<p>${lineBreakReplaced}</p>`;
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Refresh({ refreshing: this.isRefreshing }) {
          if (this.isLoading && this.errorMessage.length === 0 && this.detail.userBadges.length === 0) {
            Column() {
              LoadingSpinner({ message: '' })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.errorMessage.length > 0 && this.detail.userBadges.length === 0) {
            Column() {
              ErrorView({
                title: '加载失败',
                message: this.errorMessage,
                onRetry: () => {
                  this.loadDetail(true).catch(() => {
                  });
                }
              })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            Scroll(this.contentScroller) {
              Column() {
                this.HeroSection()

                Column() {
                  this.BadgeSummaryCard()
                  this.GrantedUsersHeader()

                  if (this.detail.userBadges.length === 0) {
                    this.EmptyGrantedUsers()
                  } else {
                    ForEach(this.detail.userBadges, (item: UserBadge) => {
                      this.UserBadgeRow(item)
                    }, (item: UserBadge) => item.id.toString())
                  }
                }
                .width('100%')
                .padding({
                  left: 16,
                  right: 16,
                  top: 18,
                  bottom: 20 + WindowManager.getSystemAvoidAreaBottomVp()
                })
              }
              .width('100%')
            }
            .width('100%')
            .height('100%')
            .backgroundColor($r('app.color.background'))
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
        .onRefreshing(() => {
          this.loadDetail(false).catch(() => {
          });
        })
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
    }
    .backgroundColor($r('app.color.background'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .titleBar(ImmersiveHdsTitleBarHelper.buildImmersiveTitleBar(this.getNavigationTitle()))
    .hideTitleBar(false)
    .hideBackButton(false)
    .hideToolBar(true)
    .bindToScrollable([this.contentScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .systemBarStyle(
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() },
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() }
    )
  }

  @Builder
  private HeroSection() {
    Column() {
      if (BadgeIconResolver.getResolvedImageUrl(this.detail.badge).length > 0 && !this.heroImageFailed) {
        Image(BadgeIconResolver.getResolvedImageUrl(this.detail.badge))
          .width(104)
          .height(104)
          .objectFit(ImageFit.Contain)
          .onError(() => {
            this.heroImageFailed = true;
          })
      } else {
        SymbolGlyph(BadgeIconResolver.getBadgeSymbol(this.detail.badge))
          .fontSize(104)
          .fontColor([this.getBadgeAccentColor()])
      }
    }
    .width('100%')
    .height(this.getHeroHeight())
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .linearGradient({
      angle: 180,
      colors: [
        [ThemeManager.hexWithAlpha(this.getBadgeAccentColor(), 0.18), 0],
        ['#FFF9FAFD', 0.58],
        [ThemeManager.hexWithAlpha(this.getBadgeAccentColor(), 0.04), 1]
      ]
    })
  }

  @Builder
  private BadgeSummaryCard() {
    Column() {
      Text(this.detail.badge.name)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(this.getBadgeTypeLabel(this.detail.badge.badgeTypeId))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getBadgeAccentColor())
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
        .backgroundColor(ThemeManager.hexWithAlpha(this.getBadgeAccentColor(), 0.1))
        .border({
          width: 1,
          color: ThemeManager.hexWithAlpha(this.getBadgeAccentColor(), 0.18)
        })
        .borderRadius(18)
        .margin({ top: 12 })

      if (this.detail.badge.description.trim().length > 0) {
        Text(this.detail.badge.description)
          .fontSize(16)
          .lineHeight(24)
          .fontColor($r('app.color.on_surface'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 22 })
      }

      if (this.buildRichTextHtml(this.detail.badge.longDescription).length > 0) {
        Column() {
          PostRichContent({
            cookedHtml: this.buildRichTextHtml(this.detail.badge.longDescription),
            blockGapVp: 4,
            dense: true
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(16)
        .margin({ top: 14 })
        .alignItems(HorizontalAlign.Start)
      }

      Blank()
        .width('100%')
        .height(1)
        .backgroundColor(ThemeManager.hexWithAlpha('#A7B0BE', 0.22))
        .margin({ top: 24, bottom: 18 })

      Row() {
        SymbolGlyph($r('sys.symbol.medal'))
          .fontSize(18)
          .fontColor([$r('app.color.on_surface_secondary')])
          .margin({ right: 8 })

        Text(`已授予 ${this.getGrantedCount()} 次`)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface_secondary'))
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 22 })
    .backgroundColor($r('app.color.surface'))
    .border({
      width: 1,
      color: ThemeManager.hexWithAlpha('#A7B0BE', 0.18)
    })
    .borderRadius(22)
    .shadow({ radius: 16, color: '#0A000000', offsetX: 0, offsetY: 8 })
  }

  @Builder
  private GrantedUsersHeader() {
    Row() {
      SymbolGlyph($r('sys.symbol.person_2'))
        .fontSize(18)
        .fontColor([$r('app.color.primary')])
        .margin({ right: 8 })

      Text('获得者')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))

      Blank().layoutWeight(1)

      Text(`${this.getAwardedUserCount()} 位`)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface_secondary'))
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(12)
    }
    .width('100%')
    .padding({ top: 18, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private EmptyGrantedUsers() {
    Column() {
      SymbolGlyph($r('sys.symbol.person_2'))
        .fontSize(30)
        .fontColor([$r('app.color.on_surface_tertiary')])

      Text('暂时还没有用户获得该徽章')
        .fontSize(13)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ top: 12 })
    }
    .width('100%')
    .padding({ top: 36, bottom: 56 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private UserBadgeRow(userBadge: UserBadge) {
    Row() {
      SmartAvatar({
        avatarUrl: this.getUserAvatarUrl(userBadge),
        avatarSize: 44,
        avatarRadius: 22,
        fallbackText: this.getUserDisplayName(userBadge),
        bgColor: '#E8EAF0'
      })

      Column() {
        Row() {
          Text(this.getUserDisplayName(userBadge))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.isBadgeAdmin(userBadge) || this.isBadgeModerator(userBadge)) {
            SymbolGlyph($r('sys.symbol.checkmark_circle'))
              .fontSize(14)
              .fontColor([this.isBadgeAdmin(userBadge) ? '#D32F2F' : '#1976D2'])
              .margin({ left: 6, top: 2 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        if (userBadge.grantedAt !== null) {
          Text(`${TimeUtils.formatRelativeTime(userBadge.grantedAt)} 获得`)
            .fontSize(12)
            .fontColor($r('app.color.on_surface_tertiary'))
            .margin({ top: 6 })
        }

        if (userBadge.topicTitle !== null && (userBadge.topicTitle as string).trim().length > 0) {
          Row() {
            SymbolGlyph($r('sys.symbol.doc_text'))
              .fontSize(12)
              .fontColor([this.getBadgeAccentColor()])
              .margin({ right: 6 })

            Text(userBadge.topicTitle as string)
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.surface_variant'))
          .borderRadius(12)
          .margin({ top: 10 })
          .alignItems(VerticalAlign.Center)
        }
      }
      .layoutWeight(1)
      .margin({ left: 14 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.surface'))
    .border({
      width: 1,
      color: ThemeManager.hexWithAlpha('#A7B0BE', 0.16)
    })
    .borderRadius(18)
    .margin({ bottom: 12 })
    .alignItems(VerticalAlign.Top)
    .onClick(() => {
      this.openUserBadge(userBadge);
    })
  }
}
