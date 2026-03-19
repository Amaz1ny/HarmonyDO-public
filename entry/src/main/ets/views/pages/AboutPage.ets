import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { ClipboardService } from '../../common/utils/ClipboardService';
import { ExternalLinkService } from '../../common/utils/ExternalLinkService';
import { RouterManager } from '../../common/utils/RouterManager';
import { SystemShareService } from '../../common/utils/SystemShareService';
import { ToastService } from '../../common/utils/ToastService';
import { WindowManager } from '../../common/utils/WindowManager';
import { UpdateCheckResult, UpdateService } from '../../services/network/UpdateService';
import { AppLogEntry, AppLogStore } from '../../services/storage/AppLogStore';
import { AppSettingsService } from '../../services/storage/AppSettingsService';
import { DeveloperModeService } from '../../services/storage/DeveloperModeService';

const TOP_BAR_HEIGHT: number = 56;
const VERSION_TAP_THRESHOLD: number = 7;
const VERSION_TAP_WINDOW_MS: number = 2000;

@ComponentV2
export struct AboutPage {
  @Local version: string = AppConstants.APP_VERSION;
  @Local isCheckingUpdate: boolean = false;
  @Local updateSubtitle: string = '检查最新版本与发布说明';
  @Local developerModeEnabled: boolean = false;
  @Local logs: AppLogEntry[] = [];
  @Local logFilter: string = 'all';
  @Local isUpdateSheetVisible: boolean = false;
  @Local isLogsSheetVisible: boolean = false;
  @Local latestUpdate: UpdateCheckResult | null = null;

  private readonly updateService: UpdateService = new UpdateService();
  private versionTapCount: number = 0;
  private lastVersionTapAt: number = 0;
  private developerModeListener: (() => void) | null = null;
  private logStoreListener: (() => void) | null = null;

  aboutToAppear(): void {
    this.attachDeveloperModeListener();
    this.attachLogStoreListener();
    this.bootstrap().catch(() => {
    });
  }

  aboutToDisappear(): void {
    if (this.developerModeListener !== null) {
      DeveloperModeService.getInstance().removeListener(this.developerModeListener);
      this.developerModeListener = null;
    }
    if (this.logStoreListener !== null) {
      AppLogStore.getInstance().removeListener(this.logStoreListener);
      this.logStoreListener = null;
    }
  }

  private async bootstrap(): Promise<void> {
    await AppSettingsService.getInstance().ensureInit();
    await DeveloperModeService.getInstance().ensureInit();
    await AppLogStore.getInstance().ensureInit();
    this.version = await this.updateService.getCurrentVersion();
    this.developerModeEnabled = DeveloperModeService.getInstance().isEnabled();
    this.refreshLogs();
  }

  private attachDeveloperModeListener(): void {
    if (this.developerModeListener !== null) {
      return;
    }
    this.developerModeListener = () => {
      this.developerModeEnabled = DeveloperModeService.getInstance().isEnabled();
    };
    DeveloperModeService.getInstance().addListener(this.developerModeListener);
  }

  private attachLogStoreListener(): void {
    if (this.logStoreListener !== null) {
      return;
    }
    this.logStoreListener = () => {
      this.refreshLogs();
    };
    AppLogStore.getInstance().addListener(this.logStoreListener);
  }

  private refreshLogs(): void {
    this.logs = AppLogStore.getInstance().snapshot();
  }

  private onVersionTap(): void {
    const now: number = Date.now();
    if (this.lastVersionTapAt > 0 && now - this.lastVersionTapAt > VERSION_TAP_WINDOW_MS) {
      this.versionTapCount = 0;
    }
    this.lastVersionTapAt = now;
    this.versionTapCount = this.versionTapCount + 1;
    if (this.versionTapCount < VERSION_TAP_THRESHOLD) {
      return;
    }
    this.versionTapCount = 0;
    if (this.developerModeEnabled) {
      ToastService.show('开发者模式已开启');
      return;
    }
    DeveloperModeService.getInstance().setEnabled(true).then(() => {
      ToastService.show('开发者模式已开启');
    }).catch(() => {
      ToastService.show('开启开发者模式失败');
    });
  }

  private async disableDeveloperMode(): Promise<void> {
    await DeveloperModeService.getInstance().setEnabled(false);
    ToastService.show('开发者模式已关闭');
  }

  private async checkForUpdate(): Promise<void> {
    if (this.isCheckingUpdate) {
      return;
    }
    this.isCheckingUpdate = true;
    this.updateSubtitle = '正在检查更新...';
    try {
      const result: UpdateCheckResult = await this.updateService.checkForUpdate();
      this.latestUpdate = result;
      if (result.hasUpdate) {
        const latestVersion: string = result.latestVersion.trim().length > 0 ? result.latestVersion : '未知版本';
        this.updateSubtitle = `发现新版本 ${latestVersion}`;
        this.isUpdateSheetVisible = true;
      } else {
        this.updateSubtitle = `当前已是最新版本 ${result.currentVersion}`;
        ToastService.show(`当前已是最新版本 ${result.currentVersion}`);
      }
    } catch (err) {
      const message: string = this.normalizeErrorMessage(err, '检查更新失败');
      this.updateSubtitle = message;
      ToastService.show(message);
    } finally {
      this.isCheckingUpdate = false;
    }
  }

  private normalizeErrorMessage(err: Object, fallback: string): string {
    if (err === undefined || err === null) {
      return fallback;
    }
    const text: string = err.toString().replace('Error: ', '').trim();
    return text.length > 0 ? text : fallback;
  }

  private getFilteredLogs(): AppLogEntry[] {
    if (this.logFilter === 'all') {
      return this.logs;
    }
    const next: AppLogEntry[] = [];
    for (let i: number = 0; i < this.logs.length; i++) {
      const entry: AppLogEntry = this.logs[i];
      if (entry.level.trim().toLowerCase() === this.logFilter) {
        next.push(entry);
      }
    }
    return next;
  }

  private formatLogEntry(entry: AppLogEntry): string {
    const timestamp: string = entry.createdAt.trim().length > 0 ? entry.createdAt : '-';
    const level: string = entry.level.trim().length > 0 ? entry.level.trim().toUpperCase() : 'INFO';
    const tag: string = entry.tag.trim().length > 0 ? entry.tag.trim() : 'APP';
    return `[${timestamp}] [${level}] [${tag}] ${entry.message}`;
  }

  private async copyAllLogs(): Promise<void> {
    const content: string = AppLogStore.getInstance().exportText();
    if (content.trim().length === 0) {
      ToastService.show('暂无应用日志');
      return;
    }
    await ClipboardService.copyText(content, true);
  }

  private async shareAllLogs(): Promise<void> {
    const content: string = AppLogStore.getInstance().exportText();
    if (content.trim().length === 0) {
      ToastService.show('暂无应用日志');
      return;
    }
    const ok: boolean = await SystemShareService.shareText(content, `${AppConstants.APP_NAME} 应用日志`, false);
    if (!ok) {
      await ClipboardService.copyText(content, true);
    }
  }

  private async clearLogs(): Promise<void> {
    await AppLogStore.getInstance().clear();
    ToastService.show('应用日志已清空');
  }

  private openLogsSheet(): void {
    this.refreshLogs();
    this.isLogsSheetVisible = true;
  }

  private openRepositorySource(): void {
    ExternalLinkService.openPreferred(AppConstants.REPOSITORY_URL, 'HarmonyDo 项目源码').catch(() => {
    });
  }

  private openRepositoryIssues(): void {
    ExternalLinkService.openPreferred(AppConstants.REPOSITORY_ISSUES_URL, 'HarmonyDo 反馈问题').catch(() => {
    });
  }

  private openRepositoryLicense(): void {
    ExternalLinkService.openPreferred(AppConstants.REPOSITORY_LICENSE_URL, 'HarmonyDo 开源许可').catch(() => {
    });
  }

  private openReleasePage(): void {
    const update: UpdateCheckResult | null = this.latestUpdate;
    const releaseUrl: string = update !== null && update.releaseUrl.trim().length > 0
      ? update.releaseUrl
      : AppConstants.REPOSITORY_RELEASES_URL;
    this.isUpdateSheetVisible = false;
    ExternalLinkService.openPreferred(releaseUrl, 'HarmonyDo 更新').catch(() => {
    });
  }

  private formatPublishedAt(value: string): string {
    const raw: string = value.trim();
    if (raw.length === 0) {
      return '未知';
    }
    if (raw.indexOf('T') > 0) {
      return raw.replace('T', ' ').replace('Z', '');
    }
    return raw;
  }

  @Builder
  private TopBar() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontColor([$r('app.color.on_surface')])
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        RouterManager.pop();
      })

      Text(`关于 ${AppConstants.APP_NAME}`)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private HeaderCard() {
    Column() {
      Image($r('app.media.startIcon'))
        .width(88)
        .height(88)
        .borderRadius(22)

      Text(AppConstants.APP_NAME)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .margin({ top: 18 })

      Text(`Version ${this.version}`)
        .fontSize(13)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ top: 8 })
        .onClick(() => {
          this.onVersionTap();
        })

      Text(this.developerModeEnabled ? '开发者模式已开启' : '连续点击版本 7 次可开启开发者模式')
        .fontSize(12)
        .fontColor(AppSettingsService.getInstance().getPrimaryColor())
        .margin({ top: 10 })
    }
    .width('100%')
    .padding({ top: 28, bottom: 28, left: 20, right: 20 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(24)
  }

  @Builder
  private SectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppSettingsService.getInstance().getPrimaryColor())
      .width('100%')
      .margin({ top: 18, bottom: 10, left: 4 })
  }

  @Builder
  private OptionRow(iconSymbol: Resource, title: string, subtitle: string, trailing: string, showDivider: boolean,
    onClick: () => void) {
    Column() {
      Row() {
        Row() {
          SymbolGlyph(iconSymbol)
            .fontSize(18)
            .fontColor([AppSettingsService.getInstance().getPrimaryColor()])
        }
        .width(38)
        .height(38)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(AppSettingsService.getInstance().getPrimaryColorWithAlpha(0.12))
        .borderRadius(12)

        Column() {
          Text(title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'))
          if (subtitle.trim().length > 0) {
            Text(subtitle)
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'))
              .margin({ top: 4 })
          }
        }
        .layoutWeight(1)
        .margin({ left: 12, right: 12 })
        .alignItems(HorizontalAlign.Start)

        Row() {
          if (trailing.trim().length > 0) {
            Text(trailing)
              .fontSize(12)
              .fontColor($r('app.color.on_surface_tertiary'))
              .margin({ right: 4 })
          }
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([$r('app.color.on_surface_tertiary')])
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        onClick();
      })

      if (showDivider) {
        Divider()
          .strokeWidth(1)
          .color('#12000000')
          .margin({ left: 66 })
      }
    }
    .width('100%')
  }

  @Builder
  private InfoSectionCard() {
    Column() {
      this.OptionRow(
        $r('sys.symbol.arrow_clockwise'),
        '检查更新',
        this.updateSubtitle,
        this.isCheckingUpdate ? '检查中' : '',
        true,
        () => {
          this.checkForUpdate().catch(() => {
          });
        }
      )
      this.OptionRow(
        $r('sys.symbol.doc_text'),
        '开源许可',
        '查看当前仓库 LICENSE',
        'GitHub',
        false,
        () => {
          this.openRepositoryLicense();
        }
      )
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
  }

  @Builder
  private DevelopSectionCard() {
    Column() {
      this.OptionRow(
        $r('sys.symbol.gearshape'),
        '开发者模式',
        this.developerModeEnabled ? '已开启，点按可关闭' : '连续点击版本 7 次可开启',
        this.developerModeEnabled ? '已开启' : '',
        true,
        () => {
          if (this.developerModeEnabled) {
            this.disableDeveloperMode().catch(() => {
            });
          } else {
            ToastService.show('连续点击版本 7 次可开启开发者模式');
          }
        }
      )
      this.OptionRow(
        $r('sys.symbol.link'),
        '项目源码',
        '默认指向当前 origin 对应的 GitHub 仓库',
        'GitHub',
        true,
        () => {
          this.openRepositorySource();
        }
      )
      this.OptionRow(
        $r('sys.symbol.doc_text'),
        '应用日志',
        '查看、复制、分享和清空应用内日志',
        `${this.logs.length} 条`,
        true,
        () => {
          this.openLogsSheet();
        }
      )
      this.OptionRow(
        $r('sys.symbol.info_circle'),
        '反馈问题',
        '打开当前仓库 Issues',
        'Issues',
        false,
        () => {
          this.openRepositoryIssues();
        }
      )
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
  }

  @Builder
  private LogFilterChip(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.logFilter === value ? AppSettingsService.getInstance().getPrimaryColor() : $r('app.color.on_surface_secondary'))
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(this.logFilter === value ? AppSettingsService.getInstance().getPrimaryColorWithAlpha(0.12) : $r('app.color.surface_variant'))
    .borderRadius(16)
    .margin({ right: 8, bottom: 8 })
    .onClick(() => {
      this.logFilter = value;
    })
  }

  @Builder
  private LogsSheetBuilder() {
    Column() {
      Row() {
        Text('应用日志')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
        Text(`${this.logs.length} 条`)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ left: 8 })
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap }) {
        this.LogFilterChip('全部', 'all')
        this.LogFilterChip('信息', 'info')
        this.LogFilterChip('警告', 'warn')
        this.LogFilterChip('错误', 'error')
      }
      .width('100%')
      .margin({ top: 14 })

      Row() {
        this.LogActionButton('复制全部', () => {
          this.copyAllLogs().catch(() => {
          });
        })
        this.LogActionButton('分享', () => {
          this.shareAllLogs().catch(() => {
          });
        })
        this.LogActionButton('清空', () => {
          this.clearLogs().catch(() => {
          });
        })
      }
      .width('100%')
      .margin({ top: 4, bottom: 12 })

      if (this.getFilteredLogs().length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(30)
            .fontColor([$r('app.color.on_surface_tertiary')])
          Text('当前筛选下暂无日志')
            .fontSize(13)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 10 })
        }
        .width('100%')
        .padding({ top: 56, bottom: 56 })
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.getFilteredLogs(), (entry: AppLogEntry) => {
            ListItem() {
              Column() {
                Row() {
                  Text(entry.tag.trim().length > 0 ? entry.tag : 'APP')
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(AppSettingsService.getInstance().getPrimaryColor())
                    .layoutWeight(1)
                  Text(entry.level.trim().toUpperCase())
                    .fontSize(11)
                    .fontColor($r('app.color.on_surface_secondary'))
                }
                .width('100%')

                Text(entry.message)
                  .fontSize(13)
                  .fontColor($r('app.color.on_surface'))
                  .width('100%')
                  .margin({ top: 8 })

                Text(entry.createdAt)
                  .fontSize(11)
                  .fontColor($r('app.color.on_surface_tertiary'))
                  .width('100%')
                  .margin({ top: 8 })
              }
              .width('100%')
              .padding(14)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(16)
              .margin({ bottom: 10 })
              .onClick(() => {
                ClipboardService.copyText(this.formatLogEntry(entry), true).catch(() => {
                });
              })
            }
          }, (entry: AppLogEntry) => entry.id.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 20, bottom: 20 + WindowManager.getSystemAvoidAreaBottomVp() })
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private LogActionButton(label: string, onClick: () => void) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(AppSettingsService.getInstance().getPrimaryColor())
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(AppSettingsService.getInstance().getPrimaryColorWithAlpha(0.12))
    .borderRadius(16)
    .margin({ right: 8 })
    .onClick(() => {
      onClick();
    })
  }

  @Builder
  private UpdateSheetBuilder() {
    Column() {
      Text('发现新版本')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))

      if (this.latestUpdate !== null) {
        Text(`${(this.latestUpdate as UpdateCheckResult).currentVersion} -> ${(this.latestUpdate as UpdateCheckResult).latestVersion}`)
          .fontSize(14)
          .fontColor(AppSettingsService.getInstance().getPrimaryColor())
          .margin({ top: 8 })

        Text((this.latestUpdate as UpdateCheckResult).releaseName.trim().length > 0
          ? (this.latestUpdate as UpdateCheckResult).releaseName
          : 'HarmonyDo 发布说明')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
          .margin({ top: 14 })

        Text(`发布时间：${this.formatPublishedAt((this.latestUpdate as UpdateCheckResult).publishedAt)}`)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ top: 6 })

        Text((this.latestUpdate as UpdateCheckResult).body.trim().length > 0
          ? (this.latestUpdate as UpdateCheckResult).body
          : '当前版本已有新的发布说明，可点击查看 GitHub Releases。')
          .fontSize(12)
          .lineHeight(20)
          .fontColor($r('app.color.on_surface_secondary'))
          .width('100%')
          .margin({ top: 14 })
      }

      Row() {
        this.LogActionButton('稍后', () => {
          this.isUpdateSheetVisible = false;
        })
        this.LogActionButton('查看发布页', () => {
          this.openReleasePage();
        })
      }
      .width('100%')
      .margin({ top: 18 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 24 + WindowManager.getSystemAvoidAreaBottomVp() })
    .backgroundColor($r('app.color.surface'))
  }

  build() {
    HdsNavDestination() {
      Column() {
        this.TopBar()
        Scroll() {
          Column() {
            this.HeaderCard()
            this.SectionTitle('信息')
            this.InfoSectionCard()
            this.SectionTitle('开发')
            this.DevelopSectionCard()
            Blank().height(24 + WindowManager.getSystemAvoidAreaBottomVp())
          }
          .width('100%')
          .padding({ left: 12, right: 12 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .padding({ top: WindowManager.getSystemAvoidAreaTopVp() })
      .backgroundColor($r('app.color.background'))
      .bindSheet($$this.isUpdateSheetVisible, this.UpdateSheetBuilder, {
        height: SheetSize.MEDIUM,
        showClose: false,
        dragBar: true,
        backgroundColor: $r('app.color.surface')
      })
      .bindSheet($$this.isLogsSheetVisible, this.LogsSheetBuilder, {
        height: SheetSize.LARGE,
        showClose: false,
        dragBar: true,
        backgroundColor: $r('app.color.surface')
      })
    }
    .backgroundColor($r('app.color.background'))
    .hideTitleBar(true)
    .hideToolBar(true)
  }
}
