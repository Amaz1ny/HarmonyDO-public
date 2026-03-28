import { HdsNavDestination } from '@kit.UIDesignKit';
import { RouterManager } from '../../common/utils/RouterManager';
import { AppLogEntry, AppLogService } from '../../common/utils/AppLogService';
import { ClipboardService } from '../../common/utils/ClipboardService';
import { ToastService } from '../../common/utils/ToastService';

export type AppLogsFilterType = 'all' | 'error' | 'lifecycle' | 'general';

export function filterEntries(entries: AppLogEntry[], filter: AppLogsFilterType): AppLogEntry[] {
  if (filter === 'all') {
    return entries;
  }
  if (filter === 'error') {
    return entries.filter((entry: AppLogEntry) => entry.level === 'error');
  }
  if (filter === 'lifecycle') {
    return entries.filter((entry: AppLogEntry) => entry.type === 'lifecycle');
  }
  return entries.filter((entry: AppLogEntry) => entry.type === 'general');
}

@ComponentV2
export struct AppLogsPage {
  @Local entries: AppLogEntry[] = [];
  @Local filter: AppLogsFilterType = 'all';
  @Local selectedEntry: AppLogEntry | null = null;
  @Local clearConfirmVisible: boolean = false;

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    this.entries = AppLogService.getInstance().readEntries();
  }

  private getVisibleEntries(): AppLogEntry[] {
    return filterEntries(this.entries, this.filter);
  }

  private buildEntryText(entry: AppLogEntry): string {
    const details: string = entry.details !== undefined && entry.details !== null ? entry.details.trim() : '';
    if (details.length > 0) {
      return `${entry.timestamp}\n[${entry.level}/${entry.type}] ${entry.message}\n${details}`;
    }
    return `${entry.timestamp}\n[${entry.level}/${entry.type}] ${entry.message}`;
  }

  private onCopySelected(): void {
    if (this.selectedEntry === null) {
      return;
    }
    ClipboardService.copyText(this.buildEntryText(this.selectedEntry), false)
      .then((ok: boolean) => {
        ToastService.show(ok ? '已复制日志详情' : '复制失败');
      })
      .catch(() => {
        ToastService.show('复制失败');
      });
  }

  private onClearConfirmed(): void {
    AppLogService.getInstance().clear();
    this.clearConfirmVisible = false;
    this.selectedEntry = null;
    this.reload();
    ToastService.show('已清空日志');
  }

  @Builder
  private TopBar() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontColor([$r('app.color.on_surface')]);
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        RouterManager.pop();
      });

      Text('应用日志')
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface'));

      Text('清空')
        .width(44)
        .height(44)
        .textAlign(TextAlign.Center)
        .fontSize(13)
        .fontColor($r('app.color.primary'))
        .onClick(() => {
          this.clearConfirmVisible = true;
        });
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8 })
    .backgroundColor($r('app.color.background'))
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  private FilterChip(label: string, value: AppLogsFilterType) {
    Text(label)
      .fontSize(12)
      .fontColor(this.filter === value ? Color.White : $r('app.color.on_surface'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.filter === value ? $r('app.color.primary') : $r('app.color.surface_variant'))
      .onClick(() => {
        this.filter = value;
      });
  }

  @Builder
  private FilterBar() {
    Row({ space: 8 }) {
      this.FilterChip('全部', 'all');
      this.FilterChip('错误', 'error');
      this.FilterChip('生命周期', 'lifecycle');
      this.FilterChip('通用', 'general');
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 });
  }

  @Builder
  private EntryRow(entry: AppLogEntry, isLast: boolean) {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text(`[${entry.level}/${entry.type}] ${entry.message}`)
            .fontSize(14)
            .fontColor($r('app.color.on_surface'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(entry.timestamp)
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'));
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.on_surface_tertiary')]);
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })
      .onClick(() => {
        this.selectedEntry = entry;
      });

      if (!isLast) {
        Divider()
          .strokeWidth(1)
          .color($r('app.color.divider'));
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16 });
  }

  @Builder
  private EmptyState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(26)
        .fontColor([$r('app.color.on_surface_tertiary')]);
      Text('暂无日志')
        .fontSize(14)
        .fontColor($r('app.color.on_surface_secondary'));
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  private DetailOverlay() {
    if (this.selectedEntry !== null) {
      Column() {
        Blank()
          .layoutWeight(1)
          .onClick(() => {
            this.selectedEntry = null;
          });

        Column({ space: 8 }) {
          Text('日志详情')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'));
          Text((this.selectedEntry as AppLogEntry).timestamp)
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'));
          Text(`[${(this.selectedEntry as AppLogEntry).level}/${(this.selectedEntry as AppLogEntry).type}] ${(this.selectedEntry as AppLogEntry).message}`)
            .fontSize(14)
            .fontColor($r('app.color.on_surface'));
          if (
            (this.selectedEntry as AppLogEntry).details !== undefined &&
            (this.selectedEntry as AppLogEntry).details !== null &&
            ((this.selectedEntry as AppLogEntry).details as string).trim().length > 0
          ) {
            Text((this.selectedEntry as AppLogEntry).details as string)
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'));
          }
          Row({ space: 12 }) {
            Button('复制')
              .onClick(() => {
                this.onCopySelected();
              });
            Button('关闭')
              .onClick(() => {
                this.selectedEntry = null;
              });
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.background'))
        .borderRadius({ topLeft: 16, topRight: 16 });
      }
      .position({ x: 0, y: 0 })
      .width('100%')
      .height('100%')
      .backgroundColor('#66000000');
    }
  }

  @Builder
  private ClearConfirmOverlay() {
    if (this.clearConfirmVisible) {
      Column() {
        Blank()
          .layoutWeight(1)
          .onClick(() => {
            this.clearConfirmVisible = false;
          });

        Column({ space: 12 }) {
          Text('确认清空日志？')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'));
          Row({ space: 12 }) {
            Button('取消')
              .onClick(() => {
                this.clearConfirmVisible = false;
              });
            Button('清空')
              .onClick(() => {
                this.onClearConfirmed();
              });
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.background'))
        .borderRadius({ topLeft: 16, topRight: 16 });
      }
      .position({ x: 0, y: 0 })
      .width('100%')
      .height('100%')
      .backgroundColor('#66000000');
    }
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          this.TopBar();
          this.FilterBar();

          if (this.getVisibleEntries().length === 0) {
            this.EmptyState();
          } else {
            List() {
              ForEach(this.getVisibleEntries(), (entry: AppLogEntry, index: number) => {
                ListItem() {
                  this.EntryRow(entry, index === this.getVisibleEntries().length - 1);
                }
              }, (entry: AppLogEntry) => `${entry.timestamp}_${entry.message}`);
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off);
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'));

        this.DetailOverlay();
        this.ClearConfirmOverlay();
      }
      .width('100%')
      .height('100%');
    }
  }
}
