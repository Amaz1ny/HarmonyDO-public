import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { FollowUser } from '../../models/User';
import { ApiClient } from '../../services/network/ApiClient';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';
import { SmartAvatar } from '../components/SmartAvatar';
import { RouterManager } from '../../common/utils/RouterManager';
import { WindowManager } from '../../common/utils/WindowManager';
import { ImmersiveHdsTitleBarHelper } from '../components/ImmersiveHdsTitleBarHelper';

@ComponentV2
export struct FollowListPage {
  @Param username: string = '';
  @Param isFollowing: boolean = true;

  @Local users: FollowUser[] = [];
  @Local isLoading: boolean = true;
  @Local errorMessage: string = '';

  private contentScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadUsers();
  }

  private async loadUsers(): Promise<void> {
    const target: string = this.username.trim();
    if (target.length === 0) {
      this.errorMessage = '无效的用户名';
      this.isLoading = false;
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';
    try {
      const api: ApiClient = ApiClient.getInstance();
      this.users = this.isFollowing
        ? await api.getFollowing(target)
        : await api.getFollowers(target);
    } catch (err) {
      this.errorMessage = err !== undefined && err !== null
        ? err.toString().replace('Error: ', '')
        : '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  private getTitle(): string {
    return this.isFollowing ? '关注' : '粉丝';
  }

  private getNavigationTitle(): string {
    return `${this.username} 的${this.getTitle()}`;
  }

  build() {
    HdsNavDestination() {
      Column() {
        Refresh({ refreshing: false }) {
          if (this.isLoading && this.users.length === 0) {
            Column() {
              LoadingSpinner({ message: '' })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.errorMessage.length > 0 && this.users.length === 0) {
            Column() {
              ErrorView({
                title: $r('app.string.load_failed'),
                message: this.errorMessage,
                showRetry: true,
                onRetry: () => {
                  this.loadUsers();
                }
              })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            Scroll(this.contentScroller) {
              Column() {
                Blank()
                  .height(ImmersiveHdsTitleBarHelper.getContentTopSpacerHeightVp())
                  .width('100%')

                if (!this.isLoading && this.users.length === 0) {
                  Column() {
                    SymbolGlyph($r('sys.symbol.person'))
                      .fontSize(30)
                      .fontColor([$r('app.color.on_surface_tertiary')])
                      .margin({ bottom: 12 })
                    Text(`暂无${this.getTitle()}`)
                      .fontSize(14)
                      .fontColor($r('app.color.on_surface_secondary'))
                  }
                  .width('100%')
                  .padding({ top: 80, bottom: 80 })
                  .alignItems(HorizontalAlign.Center)
                } else {
                  ForEach(this.users, (user: FollowUser) => {
                    this.UserRow(user)
                  }, (user: FollowUser) => `${user.id}_${user.username}`)
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 + WindowManager.getSystemAvoidAreaBottomVp() })
              .alignItems(HorizontalAlign.Center)
            }
            .width('100%')
            .height('100%')
            .backgroundColor($r('app.color.background'))
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
        .onRefreshing(() => {
          this.loadUsers();
        })
        .layoutWeight(1)
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
  UserRow(user: FollowUser) {
    Row() {
      SmartAvatar({
        avatarUrl: user.getAvatarUrl(96),
        avatarSize: 44,
        avatarRadius: 22,
        fallbackText: user.username,
        bgColor: '#E8EAF0'
      })

      Column() {
        Text(user.name !== null && (user.name as string).trim().length > 0 ? user.name as string : user.username)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`@${user.username}`)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('app.color.on_surface_tertiary')])
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .margin({ bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      RouterManager.pushUserProfile(user.username);
    })
  }
}
