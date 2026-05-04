import { StickerGroup } from '../../models/Sticker';
import { StickerMarketService } from '../../services/network/StickerMarketService';
import { ComposerStickerPreferences } from '../../services/storage/ComposerStickerPreferences';
import { ThemeManager } from '../../common/theme/ThemeManager';

@ComponentV2
export struct ComposerStickerMarketSheet {
  @Event onDone: () => void = () => {
  };
  @Event onChanged: () => void = () => {
  };

  @Local private searchQuery: string = '';
  @Local private isLoading: boolean = false;
  @Local private errorMessage: string = '';
  @Local private groups: StickerGroup[] = [];
  @Local private subscribedGroupIds: string[] = [];
  @Local private busyGroupIds: string[] = [];

  aboutToAppear(): void {
    this.loadData().catch((_: Object) => {
    });
  }

  private async loadData(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    try {
      const service: StickerMarketService = StickerMarketService.getInstance();
      this.groups = await service.getAllGroups();
      this.subscribedGroupIds = await ComposerStickerPreferences.loadSubscribedGroupIds();
    } catch (err) {
      this.errorMessage = err !== undefined && err !== null
        ? err.toString().replace('Error: ', '')
        : '表情包市场加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  private normalizeSearchQuery(query: string): string {
    return query !== undefined && query !== null ? query.trim().toLowerCase() : '';
  }

  private handleSearchChange(value: string): void {
    this.searchQuery = value;
  }

  private getVisibleGroups(): StickerGroup[] {
    const query: string = this.normalizeSearchQuery(this.searchQuery);
    if (query.length === 0) {
      return this.groups;
    }

    const out: StickerGroup[] = [];
    for (let i = 0; i < this.groups.length; i++) {
      const group: StickerGroup = this.groups[i];
      if (
        group.name.toLowerCase().indexOf(query) >= 0
        || group.id.toLowerCase().indexOf(query) >= 0
      ) {
        out.push(group);
      }
    }
    return out;
  }

  private isSubscribed(groupId: string): boolean {
    return this.subscribedGroupIds.indexOf(groupId) >= 0;
  }

  private isBusy(groupId: string): boolean {
    return this.busyGroupIds.indexOf(groupId) >= 0;
  }

  private setBusy(groupId: string, busy: boolean): void {
    const next: string[] = [];
    for (let i = 0; i < this.busyGroupIds.length; i++) {
      if (this.busyGroupIds[i] !== groupId) {
        next.push(this.busyGroupIds[i]);
      }
    }
    if (busy) {
      next.push(groupId);
    }
    this.busyGroupIds = next;
  }

  private async toggleGroup(groupId: string): Promise<void> {
    const trimmed: string = groupId !== undefined && groupId !== null ? groupId.trim() : '';
    if (trimmed.length === 0 || this.isBusy(trimmed)) {
      return;
    }
    this.setBusy(trimmed, true);
    try {
      if (this.isSubscribed(trimmed)) {
        this.subscribedGroupIds = await ComposerStickerPreferences.unsubscribeGroup(trimmed);
      } else {
        this.subscribedGroupIds = await ComposerStickerPreferences.subscribeGroup(trimmed);
      }
      this.onChanged();
    } finally {
      this.setBusy(trimmed, false);
    }
  }

  private isImageIcon(icon: string): boolean {
    const url: string = StickerMarketService.resolveAssetUrl(icon);
    return url.startsWith('http://') || url.startsWith('https://');
  }

  private getIconUrl(icon: string): string {
    return StickerMarketService.resolveAssetUrl(icon);
  }

  private getFallbackIconText(group: StickerGroup): string {
    const icon: string = group.icon !== undefined && group.icon !== null ? group.icon.trim() : '';
    if (icon.length > 0 && !this.isImageIcon(icon)) {
      return icon;
    }
    const name: string = group.name !== undefined && group.name !== null ? group.name.trim() : '';
    if (name.length > 0) {
      return name.substring(0, 1);
    }
    return '?';
  }

  @Builder
  private SearchBar() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([$r('app.color.on_surface_tertiary')])
          .margin({ right: 6 })

        TextInput({ text: this.searchQuery, placeholder: '搜索表情包...' })
          .fontSize(15)
          .fontColor($r('app.color.on_surface'))
          .placeholderColor($r('app.color.on_surface_tertiary'))
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.handleSearchChange(value);
          })

        if (this.searchQuery.length > 0) {
          Row() {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(18)
              .fontColor([$r('app.color.on_surface_tertiary')])
          }
          .width(32)
          .height(32)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.handleSearchChange('');
          })
        }
      }
      .height(40)
      .padding({ left: 14, right: 10 })
      .backgroundColor(ThemeManager.getCurrentAccentSurfaceVariantColorHex())
      .borderRadius(20)
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      Button() {
        Text('完成')
          .fontSize(14)
          .fontColor(ThemeManager.getCurrentAccentColorHex())
          .fontWeight(FontWeight.Medium)
      }
      .height(40)
      .padding({ left: 16, right: 16 })
      .borderRadius(20)
      .backgroundColor(ThemeManager.getCurrentAccentSelectedBackgroundColorHex())
      .margin({ left: 10 })
      .onClick(() => {
        this.onDone();
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private GroupIcon(group: StickerGroup) {
    if (this.isImageIcon(group.icon)) {
      Image(this.getIconUrl(group.icon))
        .width(40)
        .height(40)
        .borderRadius(10)
        .objectFit(ImageFit.Cover)
    } else {
      Row() {
        Text(this.getFallbackIconText(group))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface_secondary'))
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(ThemeManager.getCurrentAccentSurfaceVariantColorHex())
      .borderRadius(10)
    }
  }

  @Builder
  private GroupList() {
    List() {
      ForEach(this.getVisibleGroups(), (group: StickerGroup) => {
        ListItem() {
          Row() {
            this.GroupIcon(group)

            Column() {
              Text(group.name)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.on_surface'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(`${group.emojiCount} 个表情`)
                .fontSize(12)
                .fontColor($r('app.color.on_surface_secondary'))
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .margin({ left: 12, right: 12 })
            .alignItems(HorizontalAlign.Start)

            Button() {
              Row() {
                if (this.isSubscribed(group.id)) {
                  Text('✓')
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(ThemeManager.getCurrentAccentColorHex())
                    .margin({ right: 4 })
                } else {
                  SymbolGlyph($r('sys.symbol.plus'))
                    .fontSize(14)
                    .fontColor([ThemeManager.getCurrentAccentColorHex()])
                    .margin({ right: 4 })
                }

                Text(this.isSubscribed(group.id) ? '已添加' : '添加')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(ThemeManager.getCurrentAccentColorHex())
              }
            }
            .height(36)
            .padding({ left: 12, right: 12 })
            .backgroundColor(this.isSubscribed(group.id)
              ? ThemeManager.getCurrentAccentSelectedBackgroundColorHex()
              : Color.Transparent)
            .borderRadius(18)
            .border(this.isSubscribed(group.id)
              ? { width: 0 }
              : { width: 1, color: $r('app.color.divider_light') })
            .enabled(!this.isBusy(group.id))
            .opacity(this.isBusy(group.id) ? 0.55 : 1)
            .onClick(() => {
              this.toggleGroup(group.id).catch((_: Object) => {
              });
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .alignItems(VerticalAlign.Center)
        }
      }, (group: StickerGroup) => group.id)
    }
    .layoutWeight(1)
    .width('100%')
    .divider({ strokeWidth: 0.5, color: $r('app.color.skeleton_base'), startMargin: 68, endMargin: 16 })
    .scrollBar(BarState.Auto)
  }

  @Builder
  private EmptyState() {
    Column() {
      Text(this.normalizeSearchQuery(this.searchQuery).length > 0 ? '没有找到匹配的表情包' : '表情包市场为空')
        .fontSize(13)
        .fontColor($r('app.color.on_surface_tertiary'))
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private LoadingState() {
    Column() {
      LoadingProgress()
        .width(22)
        .height(22)

      Text('正在加载表情包市场...')
        .fontSize(12)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ top: 10 })
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ErrorState() {
    Column() {
      Text(this.errorMessage.length > 0 ? this.errorMessage : '表情包市场加载失败')
        .fontSize(13)
        .fontColor($r('app.color.warning'))

      Button('重试')
        .type(ButtonType.Capsule)
        .height(36)
        .margin({ top: 12 })
        .backgroundColor(ThemeManager.getCurrentAccentColorHex())
        .fontColor(Color.White)
        .onClick(() => {
          this.loadData().catch((_: Object) => {
          });
        })
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      Column() {
        Rect()
          .width(32)
          .height(4)
          .radius(2)
          .fill($r('app.color.divider_light'))
      }
      .width('100%')
      .padding({ top: 12 })
      .alignItems(HorizontalAlign.Center)

      this.SearchBar()

      Divider()
        .color($r('app.color.skeleton_base'))
        .strokeWidth(0.5)
        .margin({ left: 16, right: 16 })

      if (this.isLoading && this.groups.length === 0) {
        this.LoadingState()
      } else if (this.errorMessage.length > 0 && this.groups.length === 0) {
        this.ErrorState()
      } else if (this.getVisibleGroups().length === 0) {
        this.EmptyState()
      } else {
        this.GroupList()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeManager.getCurrentAccentSurfaceColorHex())
  }
}
