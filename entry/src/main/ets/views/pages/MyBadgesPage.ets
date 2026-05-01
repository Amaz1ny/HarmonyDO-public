import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { Badge, UserBadge, UserBadgeListResponse } from '../../models/Badge';
import { AuthService } from '../../services/auth/AuthService';
import { ApiClient } from '../../services/network/ApiClient';
import { ThemeManager } from '../../common/theme/ThemeManager';
import { RouterManager } from '../../common/utils/RouterManager';
import { WindowManager } from '../../common/utils/WindowManager';
import { BadgeIconResolver } from '../../common/utils/BadgeIconResolver';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';
import { ImmersiveHdsTitleBarHelper } from '../components/ImmersiveHdsTitleBarHelper';

const HERO_HEIGHT: number = 176;
const BADGE_CARD_HEIGHT: number = 142;

@ComponentV2
struct BadgeIconOrb {
  @Param badge: Badge = new Badge();
  @Param tintColor: string = '#A1887F';

  @Local private imageFailed: boolean = false;

  private getResolvedImageUrl(): string {
    return BadgeIconResolver.getResolvedImageUrl(this.badge);
  }

  private getSymbol(): Resource {
    return BadgeIconResolver.getBadgeSymbol(this.badge);
  }

  private getOrbBackgroundColor(): string {
    if (!WindowManager.isDarkMode()) {
      return ThemeManager.hexWithAlpha('#FFFFFF', 0.92);
    }
    return ThemeManager.hexWithAlpha(this.tintColor, 0.18);
  }

  private getOrbBorderColor(): string {
    return ThemeManager.hexWithAlpha(this.tintColor, WindowManager.isDarkMode() ? 0.30 : 0.10);
  }

  private getOrbShadowColor(): string {
    if (WindowManager.isDarkMode()) {
      return '#00000000';
    }
    return ThemeManager.hexWithAlpha(this.tintColor, 0.20);
  }

  build() {
    Row() {
      if (this.getResolvedImageUrl().length > 0 && !this.imageFailed) {
        Image(this.getResolvedImageUrl())
          .width(26)
          .height(26)
          .objectFit(ImageFit.Contain)
          .onError(() => {
            this.imageFailed = true;
          })
      } else {
        SymbolGlyph(this.getSymbol())
          .fontSize(24)
          .fontColor([this.tintColor])
      }
    }
    .width(48)
    .height(48)
    .borderRadius(24)
    .backgroundColor(this.getOrbBackgroundColor())
    .border({ width: 1, color: this.getOrbBorderColor() })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .shadow({ radius: 10, color: this.getOrbShadowColor(), offsetX: 0, offsetY: 4 })
  }
}

@ComponentV2
export struct MyBadgesPage {
  @Local userBadges: UserBadge[] = [];
  @Local isLoading: boolean = true;
  @Local isRefreshing: boolean = false;
  @Local errorMessage: string = '';

  private username: string = '';
  private contentScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    WindowManager.applyDefaultSystemChrome();
    if (this.userBadges.length === 0) {
      this.loadBadges(true).catch(() => {
      });
    }
  }

  aboutToDisappear(): void {
    WindowManager.applyDefaultSystemChrome();
  }

  private normalizeErrorMessage(err: Object): string {
    if (err === undefined || err === null) {
      return '加载徽章失败';
    }
    const text: string = err.toString().replace('Error: ', '').trim();
    return text.length > 0 ? text : '加载徽章失败';
  }

  private async ensureUsername(): Promise<void> {
    const auth: AuthService = AuthService.getInstance();
    await auth.init();
    this.username = auth.getCurrentUsername().trim();
    if (this.username.length === 0) {
      throw new Error('请先登录');
    }
  }

  private async loadBadges(showLoading: boolean): Promise<void> {
    if (showLoading) {
      this.isLoading = true;
    } else {
      this.isRefreshing = true;
    }
    this.errorMessage = '';
    try {
      await this.ensureUsername();
      const response: UserBadgeListResponse = await ApiClient.getInstance().getUserBadges(this.username);
      this.userBadges = response.userBadges;
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

  private getBadgeSectionTitle(badgeTypeId: number): string {
    if (badgeTypeId === 1) return '金牌徽章';
    if (badgeTypeId === 2) return '银牌徽章';
    return '铜牌徽章';
  }

  private getHeroTintColor(): string {
    if (this.hasBadgeSection(1)) {
      return this.getBadgeColor(1);
    }
    if (this.hasBadgeSection(2)) {
      return this.getBadgeColor(2);
    }
    return this.getBadgeColor(3);
  }

  private getTotalBadgeCount(): number {
    return this.userBadges.length;
  }

  private getTopSafeHeight(): number {
    return WindowManager.getSystemAvoidAreaTopVp();
  }

  private getHeroHeight(): number {
    return HERO_HEIGHT + this.getTopSafeHeight();
  }

  private getWatermarkTopOffset(): number {
    return Math.max(0, this.getTopSafeHeight() - 18);
  }

  private filterBadges(badgeTypeId: number): UserBadge[] {
    const list: UserBadge[] = [];
    for (let i = 0; i < this.userBadges.length; i++) {
      const item: UserBadge = this.userBadges[i];
      if (item.badge !== null && (item.badge as Badge).badgeTypeId === badgeTypeId) {
        list.push(item);
      }
    }
    return list;
  }

  private hasBadgeSection(badgeTypeId: number): boolean {
    return this.filterBadges(badgeTypeId).length > 0;
  }

  private getBadgeCountText(badgeTypeId: number): string {
    return this.filterBadges(badgeTypeId).length.toString();
  }

  private getBadgeName(userBadge: UserBadge): string {
    if (userBadge.badge === null) {
      return '徽章';
    }
    return (userBadge.badge as Badge).name;
  }

  private getBadgeForDisplay(userBadge: UserBadge): Badge {
    return userBadge.badge !== null ? userBadge.badge as Badge : new Badge();
  }

  private openBadge(userBadge: UserBadge): void {
    if (userBadge.badge === null) {
      return;
    }
    const badge: Badge = userBadge.badge as Badge;
    if (badge.id <= 0) {
      return;
    }
    RouterManager.pushBadgeDetail(badge.id, badge.slug, this.username);
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Refresh({ refreshing: this.isRefreshing }) {
          if (this.isLoading && this.userBadges.length === 0 && this.errorMessage.length === 0) {
            Column() {
              LoadingSpinner({ message: '' })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.errorMessage.length > 0 && this.userBadges.length === 0) {
            Column() {
              ErrorView({
                title: '加载失败',
                message: this.errorMessage,
                onRetry: () => {
                  this.loadBadges(true).catch(() => {
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
                  if (this.userBadges.length === 0) {
                    this.EmptySection()
                  } else {
                    this.BadgeSection(1)
                    this.BadgeSection(2)
                    this.BadgeSection(3)
                  }
                }
                .width('100%')
                .padding({
                  left: 16,
                  right: 16,
                  top: 20,
                  bottom: 20 + WindowManager.getSystemAvoidAreaBottomVp()
                })
              }
              .width('100%')
            }
            .width('100%')
            .height('100%')
            .backgroundColor($r('app.color.background'))
            .scrollBar(BarState.Off)
          }
        }
        .onRefreshing(() => {
          this.loadBadges(false).catch(() => {
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
    .titleBar(ImmersiveHdsTitleBarHelper.buildImmersiveTitleBar($r('app.string.profile_my_badges')))
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
    Stack({ alignContent: Alignment.BottomStart }) {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.star'))
            .fontSize(64)
            .fontColor([ThemeManager.hexWithAlpha(this.getHeroTintColor(), 0.16)])
        }
        .width(148)
        .height(148)
        .borderRadius(74)
        .backgroundColor(ThemeManager.hexWithAlpha(this.getHeroTintColor(), 0.08))
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Top)
      .padding({ top: this.getWatermarkTopOffset(), right: 14 })

      Column() {
        Text('累计获得')
          .fontSize(14)
          .fontColor($r('app.color.on_surface_secondary'))
          .fontWeight(FontWeight.Medium)

        Text(this.getTotalBadgeCount().toString())
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .margin({ top: 4 })

        Text('枚徽章')
          .fontSize(14)
          .fontColor($r('app.color.on_surface_tertiary'))
          .margin({ top: 4 })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 22 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(this.getHeroHeight())
    .backgroundColor($r('app.color.surface'))
    .linearGradient({
      angle: 135,
      colors: [
        [ThemeManager.hexWithAlpha(this.getHeroTintColor(), 0.18), 0],
        ['#FFF8FAFD', 0.62],
        [ThemeManager.hexWithAlpha(this.getHeroTintColor(), 0.04), 1]
      ]
    })
  }

  @Builder
  private EmptySection() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.medal'))
          .fontSize(30)
          .fontColor([$r('app.color.on_surface_tertiary')])
      }
      .width(72)
      .height(72)
      .borderRadius(36)
      .backgroundColor($r('app.color.surface'))
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Text('暂无徽章')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ top: 14 })
    }
    .width('100%')
    .padding({ top: 56, bottom: 72 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private BadgeSection(badgeTypeId: number) {
    if (this.hasBadgeSection(badgeTypeId)) {
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.medal'))
            .fontSize(18)
            .fontColor([this.getBadgeColor(badgeTypeId)])

          Text(this.getBadgeSectionTitle(badgeTypeId))
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getBadgeColor(badgeTypeId))
            .margin({ left: 10 })

          Blank().layoutWeight(1)

          Text(this.getBadgeCountText(badgeTypeId))
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getBadgeColor(badgeTypeId))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(ThemeManager.hexWithAlpha(this.getBadgeColor(badgeTypeId), 0.12))
            .borderRadius(12)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 14 })

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.filterBadges(badgeTypeId), (item: UserBadge) => {
            this.BadgeCard(item)
          }, (item: UserBadge) => item.id.toString())
        }
        .width('100%')
      }
      .width('100%')
      .margin({ bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private BadgeCard(userBadge: UserBadge) {
    Stack({ alignContent: Alignment.Center }) {
      if (userBadge.count > 1) {
        Row() {
          Text(`×${userBadge.count}`)
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getBadgeColor(this.getBadgeForDisplay(userBadge).badgeTypeId))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(ThemeManager.hexWithAlpha(this.getBadgeColor(this.getBadgeForDisplay(userBadge).badgeTypeId), 0.14))
            .borderRadius(12)
            .border({
              width: 1,
              color: ThemeManager.hexWithAlpha(this.getBadgeColor(this.getBadgeForDisplay(userBadge).badgeTypeId), 0.24)
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(VerticalAlign.Top)
        .padding({ top: 10, right: 10 })
      }

      Column() {
        BadgeIconOrb({
          badge: this.getBadgeForDisplay(userBadge),
          tintColor: this.getBadgeColor(this.getBadgeForDisplay(userBadge).badgeTypeId)
        })

        Text(this.getBadgeName(userBadge))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 12 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .width('48%')
    .height(BADGE_CARD_HEIGHT)
    .backgroundColor($r('app.color.surface'))
    .linearGradient({
      angle: 135,
      colors: [
        [ThemeManager.hexWithAlpha(this.getBadgeColor(this.getBadgeForDisplay(userBadge).badgeTypeId), 0.16), 0],
        [ThemeManager.hexWithAlpha(this.getBadgeColor(this.getBadgeForDisplay(userBadge).badgeTypeId), 0.05), 0.62],
        [ThemeManager.hexWithAlpha(this.getBadgeColor(this.getBadgeForDisplay(userBadge).badgeTypeId), 0.015), 1]
      ]
    })
    .border({
      width: 1.2,
      color: ThemeManager.hexWithAlpha(this.getBadgeColor(this.getBadgeForDisplay(userBadge).badgeTypeId), 0.22)
    })
    .borderRadius(20)
    .shadow({
      radius: 16,
      color: ThemeManager.hexWithAlpha(this.getBadgeColor(this.getBadgeForDisplay(userBadge).badgeTypeId), 0.09),
      offsetX: 0,
      offsetY: 8
    })
    .margin({ bottom: 16 })
    .onClick(() => {
      this.openBadge(userBadge);
    })
  }
}
