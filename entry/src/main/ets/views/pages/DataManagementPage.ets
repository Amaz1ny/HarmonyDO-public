import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ToastService } from '../../common/utils/ToastService';
import { AppContext } from '../../common/utils/AppContext';
import { PreferencesUtil } from '../../services/storage/PreferencesUtil';
import { CookieStore, CookieRecord } from '../../services/network/CookieStore';
import { AuthService } from '../../services/auth/AuthService';
import { ImmersiveHdsTitleBarHelper } from '../components/ImmersiveHdsTitleBarHelper';

const TAG: string = 'DataManagementPage';
const PAGE_HORIZONTAL_PADDING: number = 16;
const CARD_CORNER_RADIUS: number = 20;
const PREF_CLEAR_CACHE_ON_EXIT: string = 'pref_clear_cache_on_exit';

@ComponentV2
export struct DataManagementPage {
  @Local imageCacheSize: string = '';
  @Local isCalculatingCache: boolean = true;
  @Local isClearingImageCache: boolean = false;
  @Local isClearingCookie: boolean = false;
  @Local isClearingAll: boolean = false;
  @Local clearOnExit: boolean = false;

  private contentScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadSettings().catch(() => {});
    this.calculateCacheSize().catch(() => {});
  }

  private async loadSettings(): Promise<void> {
    await PreferencesUtil.ensureInit();
    this.clearOnExit = await PreferencesUtil.getBoolean(PREF_CLEAR_CACHE_ON_EXIT, false);
  }

  private getCacheDir(): string {
    const ctx = AppContext.getUIAbilityContext();
    if (ctx !== null) {
      return ctx.cacheDir;
    }
    return getContext().cacheDir;
  }

  private async calculateCacheSize(): Promise<void> {
    this.isCalculatingCache = true;
    try {
      const bytes: number = await this.getDirSizeBytes(this.getCacheDir());
      this.imageCacheSize = this.formatSize(bytes);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Calculate cache size failed: %{public}s', String(err));
      this.imageCacheSize = '0 B';
    } finally {
      this.isCalculatingCache = false;
    }
  }

  private async getDirSizeBytes(dir: string): Promise<number> {
    let total: number = 0;
    let entries: string[] = [];
    try {
      entries = fileIo.listFileSync(dir);
    } catch (_) {
      return 0;
    }
    for (let i = 0; i < entries.length; i++) {
      const fullPath: string = `${dir}/${entries[i]}`;
      try {
        const stat: fileIo.Stat = fileIo.statSync(fullPath);
        if (stat.isDirectory()) {
          total += await this.getDirSizeBytes(fullPath);
        } else {
          total += stat.size;
        }
      } catch (_) {
      }
    }
    return total;
  }

  private formatSize(bytes: number): string {
    if (bytes <= 0) return '0 B';
    const kb: number = bytes / 1024;
    if (kb < 1) return `${bytes} B`;
    const mb: number = kb / 1024;
    if (mb < 1) return `${kb.toFixed(1)} KB`;
    const gb: number = mb / 1024;
    if (gb < 1) return `${mb.toFixed(1)} MB`;
    return `${gb.toFixed(2)} GB`;
  }

  private async clearCacheDir(): Promise<void> {
    const dir: string = this.getCacheDir();
    let entries: string[] = [];
    try {
      entries = fileIo.listFileSync(dir);
    } catch (_) {
      return;
    }
    for (let i = 0; i < entries.length; i++) {
      const fullPath: string = `${dir}/${entries[i]}`;
      try {
        const stat: fileIo.Stat = fileIo.statSync(fullPath);
        if (stat.isDirectory()) {
          fileIo.rmdirSync(fullPath);
        } else {
          fileIo.unlinkSync(fullPath);
        }
      } catch (err) {
        hilog.warn(0x0000, TAG, 'Remove cache entry failed: %{public}s %{public}s', entries[i], String(err));
      }
    }
  }

  private async onClearImageCache(): Promise<void> {
    if (this.isClearingImageCache) return;
    this.isClearingImageCache = true;
    try {
      await this.clearCacheDir();
      await this.calculateCacheSize();
      ToastService.show($r('app.string.dm_clear_success'));
    } catch (_) {
      ToastService.show($r('app.string.dm_clear_failed'));
    } finally {
      this.isClearingImageCache = false;
    }
  }

  private async onClearCookie(): Promise<void> {
    if (this.isClearingCookie) return;
    this.isClearingCookie = true;
    try {
      const store: CookieStore = CookieStore.getInstance();
      const cfRecord: CookieRecord | null = store.getCookieRecord('cf_clearance');
      store.clearAll();
      store.restoreCookieRecord(cfRecord);
      await AuthService.getInstance().logout();
      ToastService.show($r('app.string.dm_clear_success'));
    } catch (_) {
      ToastService.show($r('app.string.dm_clear_failed'));
    } finally {
      this.isClearingCookie = false;
    }
  }

  private async onClearAll(): Promise<void> {
    if (this.isClearingAll) return;
    this.isClearingAll = true;
    try {
      await this.clearCacheDir();
      const store: CookieStore = CookieStore.getInstance();
      const cfRecord: CookieRecord | null = store.getCookieRecord('cf_clearance');
      store.clearAll();
      store.restoreCookieRecord(cfRecord);
      await AuthService.getInstance().logout();
      await this.calculateCacheSize();
      ToastService.show($r('app.string.dm_clear_success'));
    } catch (_) {
      ToastService.show($r('app.string.dm_clear_failed'));
    } finally {
      this.isClearingAll = false;
    }
  }

  private async onClearOnExitChanged(value: boolean): Promise<void> {
    this.clearOnExit = value;
    try {
      await PreferencesUtil.putBoolean(PREF_CLEAR_CACHE_ON_EXIT, value);
    } catch (_) {
      this.clearOnExit = !value;
      ToastService.show($r('app.string.dm_clear_failed'));
    }
  }

  private showConfirmDialog(title: Resource, message: Resource, onConfirm: () => void): void {
    AlertDialog.show({
      title: title,
      message: message,
      primaryButton: {
        value: $r('app.string.dm_confirm_cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: $r('app.string.dm_confirm_ok'),
        fontColor: $r('app.color.error'),
        action: () => { onConfirm(); }
      }
    });
  }

  @Builder
  private SectionHeader(title: Resource) {
    Text(title)
      .fontSize(14)
      .fontColor($r('app.color.on_surface_secondary'))
      .margin({ top: 24, bottom: 8, left: 4 });
  }

  @Builder
  private SettingRow(
    icon: Resource,
    iconColor: string,
    iconBgColor: string,
    title: Resource,
    subtitle: Resource,
    rightText: string,
    showDivider: boolean,
    isLoading: boolean,
    onClick: () => void
  ) {
    Column() {
      Row() {
        Column() {
          SymbolGlyph(icon)
            .fontSize(18)
            .fontColor([iconColor]);
        }
        .width(36)
        .height(36)
        .borderRadius(10)
        .backgroundColor(iconBgColor)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);

        Column({ space: 2 }) {
          Text(title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(subtitle)
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 14 });

        if (rightText.length > 0) {
          if (isLoading) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color($r('app.color.on_surface_tertiary'));
          } else {
            Text(rightText)
              .fontSize(14)
              .fontColor($r('app.color.on_surface_tertiary'));
          }
        }

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('app.color.on_surface_tertiary')])
          .margin({ left: 4 });
      }
      .width('100%')
      .height(64)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => { onClick(); });

      if (showDivider) {
        Divider()
          .strokeWidth(0.5)
          .color($r('app.color.divider_light'))
          .margin({ left: 64 });
      }
    }
    .width('100%');
  }

  @Builder
  private ToggleRow(
    icon: Resource,
    iconColor: string,
    iconBgColor: string,
    title: Resource,
    subtitle: Resource,
    isOn: boolean,
    onChange: (value: boolean) => void
  ) {
    Row() {
      Column() {
        SymbolGlyph(icon)
          .fontSize(18)
          .fontColor([iconColor]);
      }
      .width(36)
      .height(36)
      .borderRadius(10)
      .backgroundColor(iconBgColor)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center);

      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(subtitle)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 14, right: 12 });

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange((value: boolean) => { onChange(value); });
    }
    .width('100%')
    .height(64)
    .padding({ left: 14, right: 14 })
    .alignItems(VerticalAlign.Center);
  }

  build() {
    HdsNavDestination() {
      Column() {
        Scroll(this.contentScroller) {
          Column() {
            Blank()
              .height(ImmersiveHdsTitleBarHelper.getContentTopSpacerHeightVp())
              .width('100%');

            // --- 缓存管理 ---
            this.SectionHeader($r('app.string.dm_section_cache_title'));

            Column() {
              this.SettingRow(
                $r('sys.symbol.archivebox'),
                '#1E88E5',
                '#E3F2FD',
                $r('app.string.dm_image_cache_title'),
                $r('app.string.dm_image_cache_subtitle'),
                this.imageCacheSize,
                true,
                this.isCalculatingCache,
                () => {
                  if (this.isClearingImageCache) return;
                  this.showConfirmDialog(
                    $r('app.string.dm_image_cache_title'),
                    $r('app.string.dm_image_cache_subtitle'),
                    () => { this.onClearImageCache().catch(() => {}); }
                  );
                }
              );
              this.SettingRow(
                $r('sys.symbol.security_shield'),
                '#FF8F00',
                '#FFF8E1',
                $r('app.string.dm_cookie_cache_title'),
                $r('app.string.dm_cookie_cache_subtitle'),
                '',
                false,
                false,
                () => {
                  if (this.isClearingCookie) return;
                  this.showConfirmDialog(
                    $r('app.string.dm_confirm_cookie_title'),
                    $r('app.string.dm_confirm_cookie_message'),
                    () => { this.onClearCookie().catch(() => {}); }
                  );
                }
              );
            }
            .width('100%')
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(CARD_CORNER_RADIUS)
            .border({ width: 1, color: $r('app.color.divider_light') });

            // --- 自动管理 ---
            this.SectionHeader($r('app.string.dm_section_auto_title'));

            Column() {
              this.ToggleRow(
                $r('sys.symbol.clock'),
                '#43A047',
                '#E8F5E9',
                $r('app.string.dm_clear_on_exit_title'),
                $r('app.string.dm_clear_on_exit_subtitle'),
                this.clearOnExit,
                (value: boolean) => { this.onClearOnExitChanged(value).catch(() => {}); }
              );
            }
            .width('100%')
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(CARD_CORNER_RADIUS)
            .border({ width: 1, color: $r('app.color.divider_light') });

            // --- 清除所有 ---
            Row() {
              Text($r('app.string.dm_clear_all_title'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.error'));
            }
            .width('100%')
            .height(52)
            .margin({ top: 24 })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(CARD_CORNER_RADIUS)
            .border({ width: 1, color: $r('app.color.divider_light') })
            .onClick(() => {
              if (this.isClearingAll) return;
              this.showConfirmDialog(
                $r('app.string.dm_confirm_all_title'),
                $r('app.string.dm_confirm_all_message'),
                () => { this.onClearAll().catch(() => {}); }
              );
            });

            // 底部说明
            Text($r('app.string.dm_clear_all_subtitle'))
              .fontSize(12)
              .fontColor($r('app.color.on_surface_tertiary'))
              .margin({ top: 8, left: 4 })
              .textAlign(TextAlign.Start)
              .width('100%');
          }
          .width('100%')
          .padding({ left: PAGE_HORIZONTAL_PADDING, right: PAGE_HORIZONTAL_PADDING, top: 4, bottom: 40 })
          .alignItems(HorizontalAlign.Start);
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'));
    }
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .titleBar(ImmersiveHdsTitleBarHelper.buildImmersiveTitleBar($r('app.string.dm_page_title')))
    .hideTitleBar(false)
    .hideBackButton(false)
    .hideToolBar(true)
    .bindToScrollable([this.contentScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .systemBarStyle(
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() },
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() }
    )
    .backgroundColor($r('app.color.background'));
  }
}
