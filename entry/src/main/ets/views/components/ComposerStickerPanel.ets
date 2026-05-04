import { StickerGroup, StickerGroupDetail, StickerItem } from '../../models/Sticker';
import { StickerMarketService } from '../../services/network/StickerMarketService';
import { ComposerStickerPreferences } from '../../services/storage/ComposerStickerPreferences';
import { ComposerStickerMarketSheet } from './ComposerStickerMarketSheet';
import { ModalChromeHelper } from './ModalChromeHelper';
import { ThemeManager } from '../../common/theme/ThemeManager';

class StickerTabItem {
  key: string = '';
  title: string = '';
  icon: string = '';
}

@ComponentV2
export struct ComposerStickerPanel {
  @Param panelHeight: number = 320;
  @Param showHandle: boolean = true;
  @Event onSelectSticker: (markdown: string) => void = (_: string) => {
  };

  @Local private isLoadingGroups: boolean = false;
  @Local private isLoadingCurrentGroup: boolean = false;
  @Local private errorMessage: string = '';
  @Local private groups: StickerGroup[] = [];
  @Local private recentStickers: StickerItem[] = [];
  @Local private selectedGroupKey: string = '';
  @Local private groupDetails: StickerGroupDetail[] = [];
  @Local private isMarketSheetVisible: boolean = false;
  @Local private previewSticker: StickerItem | null = null;

  private detailRequestId: number = 0;

  aboutToAppear(): void {
    this.loadRecentStickers();
    this.loadSubscribedGroups().catch((_: Object) => {
    });
  }

  private async loadRecentStickers(): Promise<void> {
    this.recentStickers = await ComposerStickerPreferences.loadRecentStickers();
    this.ensureSelectedGroup();
  }

  private async loadSubscribedGroups(): Promise<void> {
    this.isLoadingGroups = true;
    this.isLoadingCurrentGroup = false;
    this.detailRequestId = this.detailRequestId + 1;
    this.hideStickerPreview();
    this.errorMessage = '';
    try {
      const subscribedIds: string[] = await ComposerStickerPreferences.loadSubscribedGroupIds();
      if (subscribedIds.length === 0) {
        this.groups = [];
        this.groupDetails = [];
        this.ensureSelectedGroup();
        return;
      }

      const allGroups: StickerGroup[] = await StickerMarketService.getInstance().getAllGroups();
      const groupMap: Map<string, StickerGroup> = new Map();
      for (let i = 0; i < allGroups.length; i++) {
        groupMap.set(allGroups[i].id, allGroups[i]);
      }

      const nextGroups: StickerGroup[] = [];
      for (let i = 0; i < subscribedIds.length; i++) {
        const groupId: string = subscribedIds[i];
        if (groupMap.has(groupId)) {
          nextGroups.push(groupMap.get(groupId) as StickerGroup);
        }
      }
      this.groups = nextGroups;

      const nextDetails: StickerGroupDetail[] = [];
      for (let i = 0; i < this.groupDetails.length; i++) {
        const detail: StickerGroupDetail = this.groupDetails[i];
        for (let j = 0; j < nextGroups.length; j++) {
          if (nextGroups[j].id === detail.id) {
            nextDetails.push(detail);
            break;
          }
        }
      }
      this.groupDetails = nextDetails;
      this.ensureSelectedGroup();
      await this.loadSelectedGroupDetail();
    } catch (err) {
      this.errorMessage = err !== undefined && err !== null
        ? err.toString().replace('Error: ', '')
        : '表情包加载失败';
    } finally {
      this.isLoadingGroups = false;
    }
  }

  private ensureSelectedGroup(): void {
    const tabs: StickerTabItem[] = this.getTabs();
    if (tabs.length === 0) {
      this.selectedGroupKey = '';
      return;
    }
    for (let i = 0; i < tabs.length; i++) {
      if (tabs[i].key === this.selectedGroupKey) {
        return;
      }
    }
    this.selectedGroupKey = tabs[0].key;
  }

  private getTabs(): StickerTabItem[] {
    const tabs: StickerTabItem[] = [];
    if (this.recentStickers.length > 0) {
      const recent: StickerTabItem = new StickerTabItem();
      recent.key = 'recent';
      recent.title = '最近';
      tabs.push(recent);
    }
    for (let i = 0; i < this.groups.length; i++) {
      const tab: StickerTabItem = new StickerTabItem();
      tab.key = this.groups[i].id;
      tab.title = this.groups[i].name;
      tab.icon = this.groups[i].icon;
      tabs.push(tab);
    }
    return tabs;
  }

  private getCurrentGroupDetail(): StickerGroupDetail | null {
    if (this.selectedGroupKey === 'recent' || this.selectedGroupKey.length === 0) {
      return null;
    }
    for (let i = 0; i < this.groupDetails.length; i++) {
      if (this.groupDetails[i].id === this.selectedGroupKey) {
        return this.groupDetails[i];
      }
    }
    return null;
  }

  private async loadSelectedGroupDetail(): Promise<void> {
    if (this.selectedGroupKey.length === 0 || this.selectedGroupKey === 'recent') {
      return;
    }
    if (this.getCurrentGroupDetail() !== null) {
      return;
    }

    const requestId: number = this.detailRequestId + 1;
    this.detailRequestId = requestId;
    this.isLoadingCurrentGroup = true;
    this.hideStickerPreview();
    this.errorMessage = '';
    try {
      const detail: StickerGroupDetail = await StickerMarketService.getInstance().getGroupDetail(this.selectedGroupKey);
      if (requestId !== this.detailRequestId) {
        return;
      }
      const nextDetails: StickerGroupDetail[] = [];
      let replaced: boolean = false;
      for (let i = 0; i < this.groupDetails.length; i++) {
        const item: StickerGroupDetail = this.groupDetails[i];
        if (item.id === detail.id) {
          nextDetails.push(detail);
          replaced = true;
        } else {
          nextDetails.push(item);
        }
      }
      if (!replaced) {
        nextDetails.push(detail);
      }
      this.groupDetails = nextDetails;
    } catch (err) {
      if (requestId === this.detailRequestId) {
        this.errorMessage = err !== undefined && err !== null
          ? err.toString().replace('Error: ', '')
          : '表情包详情加载失败';
      }
    } finally {
      if (requestId === this.detailRequestId) {
        this.isLoadingCurrentGroup = false;
      }
    }
  }

  private getVisibleStickers(): StickerItem[] {
    if (this.selectedGroupKey === 'recent') {
      return this.recentStickers;
    }
    const detail: StickerGroupDetail | null = this.getCurrentGroupDetail();
    return detail !== null ? detail.emojis : [];
  }

  private buildNextRecentStickers(sticker: StickerItem): StickerItem[] {
    const next: StickerItem[] = [];
    next.push(sticker);
    for (let i = 0; i < this.recentStickers.length; i++) {
      if (this.recentStickers[i].id !== sticker.id && this.recentStickers[i].url !== sticker.url) {
        next.push(this.recentStickers[i]);
      }
      if (next.length >= 30) {
        break;
      }
    }
    return next;
  }

  private handleStickerTap(sticker: StickerItem): void {
    const markdown: string = sticker.toMarkdown();
    if (markdown.length === 0) {
      return;
    }
    this.hideStickerPreview();
    this.recentStickers = this.buildNextRecentStickers(sticker);
    ComposerStickerPreferences.saveRecentSticker(sticker).catch((_: Object) => {
    });
    this.onSelectSticker(markdown);
  }

  private showStickerPreview(sticker: StickerItem): void {
    const url: string = StickerMarketService.resolveAssetUrl(sticker.url);
    if (url.length === 0) {
      return;
    }
    this.previewSticker = sticker;
  }

  private hideStickerPreview(): void {
    this.previewSticker = null;
  }

  private getPreviewStickerUrl(): string {
    if (this.previewSticker === null) {
      return '';
    }
    return StickerMarketService.resolveAssetUrl((this.previewSticker as StickerItem).url);
  }

  private getPreviewStickerName(): string {
    if (this.previewSticker === null) {
      return '';
    }
    const name: string = (this.previewSticker as StickerItem).name;
    return name !== undefined && name !== null ? name.trim() : '';
  }

  private shouldShowTabs(): boolean {
    return this.getTabs().length > 0;
  }

  private shouldShowAddButton(): boolean {
    return this.groups.length > 0 || this.recentStickers.length > 0;
  }

  private isImageIcon(icon: string): boolean {
    const resolved: string = StickerMarketService.resolveAssetUrl(icon);
    return resolved.startsWith('http://') || resolved.startsWith('https://');
  }

  private getIconUrl(icon: string): string {
    return StickerMarketService.resolveAssetUrl(icon);
  }

  private getTabFallbackText(tab: StickerTabItem): string {
    if (tab.key === 'recent') {
      return '最';
    }
    const icon: string = tab.icon !== undefined && tab.icon !== null ? tab.icon.trim() : '';
    if (icon.length > 0 && !this.isImageIcon(icon)) {
      return icon;
    }
    const title: string = tab.title !== undefined && tab.title !== null ? tab.title.trim() : '';
    if (title.length > 0) {
      return title.substring(0, 1);
    }
    return '?';
  }

  @Builder
  private TabBadge(tab: StickerTabItem) {
    if (tab.key === 'recent') {
      Row() {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(16)
          .fontColor([this.selectedGroupKey === tab.key
            ? ThemeManager.getCurrentAccentColorHex()
            : $r('app.color.on_surface_secondary')])
      }
      .width(24)
      .height(24)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    } else if (this.isImageIcon(tab.icon)) {
      Image(this.getIconUrl(tab.icon))
        .width(24)
        .height(24)
        .borderRadius(6)
        .objectFit(ImageFit.Cover)
    } else {
      Row() {
        Text(this.getTabFallbackText(tab))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.selectedGroupKey === tab.key
            ? ThemeManager.getCurrentAccentColorHex()
            : $r('app.color.on_surface_secondary'))
      }
      .width(24)
      .height(24)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  private HeaderHandle() {
    if (this.showHandle) {
      Rect()
        .width(32)
        .height(4)
        .radius(2)
        .fill($r('app.color.divider_light'))
        .margin({ top: 6, bottom: 8 })
    }
  }

  @Builder
  private GroupTabs() {
    Row() {
      Scroll() {
        Row() {
          ForEach(this.getTabs(), (tab: StickerTabItem) => {
            Row() {
              this.TabBadge(tab)

              Text(tab.title)
                .fontSize(12)
                .fontWeight(this.selectedGroupKey === tab.key ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(this.selectedGroupKey === tab.key
                  ? ThemeManager.getCurrentAccentColorHex()
                  : $r('app.color.on_surface_secondary'))
                .margin({ left: 6 })
                .maxLines(1)
            }
            .padding({ left: 10, right: 12, top: 8, bottom: 8 })
            .backgroundColor(this.selectedGroupKey === tab.key
              ? ThemeManager.getCurrentAccentSelectedBackgroundColorHex()
              : ThemeManager.getCurrentAccentSurfaceVariantColorHex())
            .borderRadius(18)
            .margin({ right: 8 })
            .onClick(() => {
              this.hideStickerPreview();
              this.selectedGroupKey = tab.key;
              this.loadSelectedGroupDetail().catch((_: Object) => {
              });
            })
          }, (tab: StickerTabItem) => tab.key)
        }
        .padding({ left: 16, right: 16, top: 4, bottom: 10 })
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)

      if (this.shouldShowAddButton()) {
        Row() {
          SymbolGlyph($r('sys.symbol.plus_circle'))
            .fontSize(18)
            .fontColor([ThemeManager.getCurrentAccentColorHex()])
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .margin({ right: 12 })
        .onClick(() => {
          this.hideStickerPreview();
          this.isMarketSheetVisible = true;
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private StickerGrid() {
    Scroll() {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.getVisibleStickers(), (sticker: StickerItem) => {
          Column() {
            Image(StickerMarketService.resolveAssetUrl(sticker.url))
              .width(56)
              .height(56)
              .objectFit(ImageFit.Contain)
          }
          .width(72)
          .height(72)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(Color.Transparent)
          .borderRadius(14)
          .margin({ left: 4, right: 4, top: 4, bottom: 4 })
          .gesture(
            GestureGroup(GestureMode.Exclusive,
              TapGesture()
                .onAction(() => {
                  this.handleStickerTap(sticker);
                }),
              LongPressGesture({ repeat: false, duration: 400 })
                .onAction(() => {
                  this.showStickerPreview(sticker);
                })
            )
          )
        }, (sticker: StickerItem) => sticker.id.length > 0 ? sticker.id : sticker.url)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 12 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  private LoadingState() {
    Column() {
      LoadingProgress()
        .width(22)
        .height(22)

      Text('正在加载表情包...')
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
  private EmptyState() {
    Column() {
      Text(this.groups.length === 0 ? '还没有添加表情包' : '当前分组暂无表情包')
        .fontSize(13)
        .fontColor($r('app.color.on_surface_tertiary'))

      Button(this.groups.length === 0 ? '从市场添加' : '管理表情包')
        .type(ButtonType.Capsule)
        .height(36)
        .margin({ top: 12 })
        .backgroundColor(ThemeManager.getCurrentAccentColorHex())
        .fontColor(Color.White)
        .onClick(() => {
          this.isMarketSheetVisible = true;
        })
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ErrorState() {
    Column() {
      Text(this.errorMessage.length > 0 ? this.errorMessage : '表情包加载失败')
        .fontSize(13)
        .fontColor($r('app.color.warning'))

      Button('重试')
        .type(ButtonType.Capsule)
        .height(36)
        .margin({ top: 12 })
        .backgroundColor(ThemeManager.getCurrentAccentColorHex())
        .fontColor(Color.White)
        .onClick(() => {
          this.loadSubscribedGroups().catch((_: Object) => {
          });
        })
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private MarketSheetBuilder() {
    ComposerStickerMarketSheet({
      onDone: () => {
        this.hideStickerPreview();
        this.isMarketSheetVisible = false;
      },
      onChanged: () => {
        this.hideStickerPreview();
        this.loadSubscribedGroups().catch((_: Object) => {
        });
      }
    })
  }

  @Builder
  private PreviewOverlay() {
    if (this.previewSticker !== null && this.getPreviewStickerUrl().length > 0) {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
        }
        .width('100%')
        .height('100%')
        .backgroundColor(ModalChromeHelper.getMaskColor())
        .backgroundBlurStyle(ModalChromeHelper.getDialogBlurStyle())
        .onClick(() => {
          this.hideStickerPreview();
        })

        Column() {
          Image(this.getPreviewStickerUrl())
            .width(180)
            .height(180)
            .objectFit(ImageFit.Contain)
            .interpolation(ImageInterpolation.High)

          if (this.getPreviewStickerName().length > 0) {
            Text(this.getPreviewStickerName())
              .fontSize(13)
              .fontColor($r('app.color.on_surface_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 10 })
          }

          Text('轻触关闭')
            .fontSize(11)
            .fontColor($r('app.color.on_surface_tertiary'))
            .margin({ top: this.getPreviewStickerName().length > 0 ? 6 : 10 })
        }
        .width(220)
        .padding({ left: 16, right: 16, top: 18, bottom: 16 })
        .backgroundColor(ModalChromeHelper.getDialogBackgroundColor())
        .backgroundBlurStyle(ModalChromeHelper.getDialogBlurStyle())
        .borderRadius(24)
        .shadow({ radius: 18, color: '#26000000', offsetX: 0, offsetY: 10 })
        .onClick(() => {
        })
      }
      .width('100%')
      .height('100%')
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        this.HeaderHandle()

        if (this.shouldShowTabs()) {
          this.GroupTabs()
        }

        Divider()
          .strokeWidth(0.5)
          .color($r('app.color.divider_light'))
          .margin({ left: 16, right: 16, bottom: 2 })

        if (this.isLoadingGroups && this.groups.length === 0 && this.recentStickers.length === 0) {
          this.LoadingState()
        } else if (this.errorMessage.length > 0 && this.getVisibleStickers().length === 0 && !this.isLoadingCurrentGroup) {
          this.ErrorState()
        } else if (this.isLoadingCurrentGroup && this.getVisibleStickers().length === 0) {
          this.LoadingState()
        } else if (this.getVisibleStickers().length === 0) {
          this.EmptyState()
        } else {
          this.StickerGrid()
        }

        Column() {
        }
        .width(0)
        .height(0)
        .bindSheet($$this.isMarketSheetVisible, this.MarketSheetBuilder, {
          height: SheetSize.LARGE,
          dragBar: false,
          showClose: false,
          backgroundColor: ModalChromeHelper.getSheetBackgroundColor(),
          maskColor: ModalChromeHelper.getMaskColor(),
          blurStyle: ModalChromeHelper.getSheetBlurStyle()
        })
      }
      .width('100%')
      .height('100%')

      this.PreviewOverlay()
    }
    .width('100%')
    .height(this.panelHeight)
    .backgroundColor(ThemeManager.getCurrentAccentSurfaceColorHex())
  }
}
