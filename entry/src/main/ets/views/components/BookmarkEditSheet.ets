import { ApiClient } from '../../services/network/ApiClient';
import { TimeUtils } from '../../common/utils/TimeUtils';
import { ToastService } from '../../common/utils/ToastService';
import { WindowManager } from '../../common/utils/WindowManager';
import { ModalChromeHelper } from './ModalChromeHelper';
import { ThemeManager } from '../../common/theme/ThemeManager';

class BookmarkReminderPreset {
  readonly key: number;
  readonly label: string;

  constructor(key: number, label: string) {
    this.key = key;
    this.label = label;
  }

  static readonly TWO_HOURS: BookmarkReminderPreset = new BookmarkReminderPreset(1, '2小时后');
  static readonly TOMORROW: BookmarkReminderPreset = new BookmarkReminderPreset(2, '明天');
  static readonly THREE_DAYS: BookmarkReminderPreset = new BookmarkReminderPreset(3, '3天后');
  static readonly NEXT_WEEK: BookmarkReminderPreset = new BookmarkReminderPreset(4, '下周');
  static readonly CUSTOM: BookmarkReminderPreset = new BookmarkReminderPreset(5, '自定义');

  static values(): BookmarkReminderPreset[] {
    return [
      BookmarkReminderPreset.TWO_HOURS,
      BookmarkReminderPreset.TOMORROW,
      BookmarkReminderPreset.THREE_DAYS,
      BookmarkReminderPreset.NEXT_WEEK
    ];
  }
}

@ComponentV2
export struct BookmarkEditSheet {
  @Param bookmarkId: number = 0;
  @Param initialName: string = '';
  @Param initialReminderAt: Date | null = null;
  @Event onDismiss: () => void = () => {
  };
  @Event onUpdated: (name: string | null, reminderAt: Date | null, clearReminderAt: boolean) => void = (
    _name: string | null,
    _reminderAt: Date | null,
    _clearReminderAt: boolean
  ) => {
  };
  @Event onDeleted: () => void = () => {
  };

  @Local private name: string = '';
  @Local private reminderAt: Date | null = null;
  @Local private selectedPresetKey: number = 0;
  @Local private clearReminderAt: boolean = false;
  @Local private isSaving: boolean = false;
  @Local private isDeleting: boolean = false;
  @Local private errorMessage: string = '';
  @Local private customDate: Date = new Date();
  @Local private customHour: number = 9;
  @Local private customMinute: number = 0;
  @Local private customSecond: number = 0;
  @Local private isCustomPickerVisible: boolean = false;
  @Local private isCustomDateSheetVisible: boolean = false;
  @Local private isCustomTimeSheetVisible: boolean = false;
  @Local private pickerDate: Date = new Date();
  @Local private pickerTime: Date = new Date();

  aboutToAppear(): void {
    this.name = this.initialName;
    this.reminderAt = this.initialReminderAt;
    this.selectedPresetKey = 0;
    this.clearReminderAt = false;
    this.isSaving = false;
    this.isDeleting = false;
    this.errorMessage = '';
    this.isCustomPickerVisible = false;
    this.isCustomDateSheetVisible = false;
    this.isCustomTimeSheetVisible = false;
    this.resetCustomSelection(this.initialReminderAt);
  }

  private computePresetReminderAt(presetKey: number): Date | null {
    const now: Date = new Date();
    if (presetKey === BookmarkReminderPreset.TWO_HOURS.key) {
      return new Date(now.getTime() + 2 * 60 * 60 * 1000);
    }
    if (presetKey === BookmarkReminderPreset.TOMORROW.key) {
      return new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 9, 0, 0, 0);
    }
    if (presetKey === BookmarkReminderPreset.THREE_DAYS.key) {
      return new Date(now.getFullYear(), now.getMonth(), now.getDate() + 3, 9, 0, 0, 0);
    }
    if (presetKey === BookmarkReminderPreset.NEXT_WEEK.key) {
      return new Date(now.getFullYear(), now.getMonth(), now.getDate() + 7, 9, 0, 0, 0);
    }
    return null;
  }

  private selectPreset(preset: BookmarkReminderPreset): void {
    if (preset.key === BookmarkReminderPreset.CUSTOM.key) {
      this.openCustomPicker();
      return;
    }
    if (this.selectedPresetKey === preset.key) {
      this.selectedPresetKey = 0;
      this.reminderAt = this.initialReminderAt;
      this.clearReminderAt = false;
      this.isCustomPickerVisible = false;
      return;
    }
    this.selectedPresetKey = preset.key;
    this.reminderAt = this.computePresetReminderAt(preset.key);
    this.clearReminderAt = false;
    this.isCustomPickerVisible = false;
  }

  private clearReminder(): void {
    this.selectedPresetKey = 0;
    this.reminderAt = null;
    this.clearReminderAt = true;
    this.isCustomPickerVisible = false;
  }

  private hasReminder(): boolean {
    return this.reminderAt !== null || this.initialReminderAt !== null;
  }

  private resetCustomSelection(source: Date | null): void {
    let base: Date;
    if (source !== null) {
      base = new Date((source as Date).getTime());
    } else {
      const now: Date = new Date();
      const minuteBlock: number = now.getMinutes() < 30 ? 30 : 0;
      const hourOffset: number = now.getMinutes() < 30 ? 0 : 1;
      base = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours() + hourOffset, minuteBlock, 0, 0);
      if (base.getTime() <= now.getTime()) {
        base = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours() + 1, 0, 0, 0);
      }
    }
    this.customDate = new Date(base.getFullYear(), base.getMonth(), base.getDate(), 0, 0, 0, 0);
    this.customHour = base.getHours();
    this.customMinute = base.getMinutes();
    this.customSecond = base.getSeconds();
  }

  private syncPickerDraftFromCurrent(): void {
    this.resetCustomSelection(this.reminderAt !== null ? this.reminderAt : this.initialReminderAt);
    this.pickerDate = new Date(this.customDate.getTime());
    this.pickerTime = new Date(
      2026,
      0,
      1,
      this.customHour,
      this.customMinute,
      this.customSecond,
      0
    );
  }

  private openCustomPicker(): void {
    this.syncPickerDraftFromCurrent();
    this.clearReminderAt = false;
    this.isCustomPickerVisible = true;
  }

  private closeCustomPicker(): void {
    this.isCustomPickerVisible = false;
    this.isCustomDateSheetVisible = false;
    this.isCustomTimeSheetVisible = false;
  }

  private confirmCustomPicker(): void {
    this.customDate = new Date(this.pickerDate.getTime());
    this.customHour = this.pickerTime.getHours();
    this.customMinute = this.pickerTime.getMinutes();
    this.customSecond = this.pickerTime.getSeconds();
    this.applyCustomReminder();
    this.isCustomPickerVisible = false;
  }

  private openCustomDateSheet(): void {
    this.isCustomDateSheetVisible = true;
  }

  private openCustomTimeSheet(): void {
    this.isCustomTimeSheetVisible = true;
  }

  private applyCustomReminder(): void {
    this.selectedPresetKey = BookmarkReminderPreset.CUSTOM.key;
    this.reminderAt = new Date(
      this.customDate.getFullYear(),
      this.customDate.getMonth(),
      this.customDate.getDate(),
      this.customHour,
      this.customMinute,
      this.customSecond,
      0
    );
    this.clearReminderAt = false;
    this.errorMessage = '';
  }

  private adjustCustomDate(days: number): void {
    this.customDate = new Date(
      this.customDate.getFullYear(),
      this.customDate.getMonth(),
      this.customDate.getDate() + days,
      0,
      0,
      0,
      0
    );
    this.applyCustomReminder();
  }

  private adjustCustomTime(minutes: number): void {
    const totalMinutes: number = this.customHour * 60 + this.customMinute + minutes;
    let normalized: number = totalMinutes;
    while (normalized < 0) {
      normalized += 24 * 60;
      this.adjustCustomDate(-1);
    }
    while (normalized >= 24 * 60) {
      normalized -= 24 * 60;
      this.adjustCustomDate(1);
    }
    this.customHour = Math.floor(normalized / 60);
    this.customMinute = normalized % 60 >= 30 ? 30 : 0;
    this.applyCustomReminder();
  }

  private formatCustomDateLabel(): string {
    return `${TimeUtils.formatSmartDate(this.customDate)} (${this.customDate.getMonth() + 1}月${this.customDate.getDate()}日)`;
  }

  private formatCustomTimeLabel(): string {
    const hour: string = this.customHour < 10 ? `0${this.customHour}` : `${this.customHour}`;
    const minute: string = this.customMinute < 10 ? `0${this.customMinute}` : `${this.customMinute}`;
    const second: string = this.customSecond < 10 ? `0${this.customSecond}` : `${this.customSecond}`;
    return `${hour}:${minute}:${second}`;
  }

  private formatPickerDateLabel(): string {
    return `${TimeUtils.formatSmartDate(this.pickerDate)} (${this.pickerDate.getMonth() + 1}月${this.pickerDate.getDate()}日)`;
  }

  private formatPickerTimeLabel(): string {
    const hour: number = this.pickerTime.getHours();
    const minute: number = this.pickerTime.getMinutes();
    const second: number = this.pickerTime.getSeconds();
    const hourText: string = hour < 10 ? `0${hour}` : `${hour}`;
    const minuteText: string = minute < 10 ? `0${minute}` : `${minute}`;
    const secondText: string = second < 10 ? `0${second}` : `${second}`;
    return `${hourText}:${minuteText}:${secondText}`;
  }

  private async save(): Promise<void> {
    if (this.isSaving || this.isDeleting || this.bookmarkId <= 0) {
      return;
    }
    this.isSaving = true;
    this.errorMessage = '';

    try {
      const api: ApiClient = ApiClient.getInstance();
      if (this.clearReminderAt) {
        await api.clearBookmarkReminder(this.bookmarkId);
      }
      const normalizedName: string = this.name.trim();
      const shouldUpdateName: boolean = normalizedName !== this.initialName.trim();
      const shouldUpdateReminder: boolean = !this.clearReminderAt
        && (
          (this.initialReminderAt === null && this.reminderAt !== null)
          || (this.initialReminderAt !== null && this.reminderAt === null)
          || (this.initialReminderAt !== null
            && this.reminderAt !== null
            && (this.initialReminderAt as Date).getTime() !== (this.reminderAt as Date).getTime())
        );
      if (shouldUpdateName || shouldUpdateReminder) {
        await api.updateBookmark(
          this.bookmarkId,
          shouldUpdateName ? normalizedName : null,
          shouldUpdateReminder ? this.reminderAt : null
        );
      }
      this.onUpdated(
        normalizedName.length > 0 ? normalizedName : null,
        this.reminderAt,
        this.clearReminderAt
      );
      ToastService.show('书签已更新');
      this.onDismiss();
    } catch (err) {
      this.errorMessage = err !== undefined && err !== null
        ? err.toString().replace('Error: ', '')
        : '更新书签失败';
    } finally {
      this.isSaving = false;
    }
  }

  private async deleteBookmark(): Promise<void> {
    if (this.isDeleting || this.isSaving || this.bookmarkId <= 0) {
      return;
    }
    this.isDeleting = true;
    this.errorMessage = '';
    try {
      await ApiClient.getInstance().deleteBookmark(this.bookmarkId);
      this.onDeleted();
      ToastService.show('已删除书签');
      this.onDismiss();
    } catch (err) {
      this.errorMessage = err !== undefined && err !== null
        ? err.toString().replace('Error: ', '')
        : '删除书签失败';
    } finally {
      this.isDeleting = false;
    }
  }

  build() {
    Column() {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.bookmark_fill'))
            .fontSize(18)
            .fontColor([ThemeManager.getCurrentAccentColorHex()])

          Text('编辑书签')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .margin({ left: 10 })
        }
        .layoutWeight(1)

        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('app.color.on_surface_secondary')])
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.onDismiss();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 18 })
      .alignItems(VerticalAlign.Center)

      Text('书签名称（可选）')
        .fontSize(13)
        .fontColor($r('app.color.on_surface_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 18 })

      TextInput({ text: this.name, placeholder: '书签名称（可选）' })
        .width('100%')
        .height(56)
        .padding({ left: 14, right: 14 })
        .margin({ left: 16, right: 16, top: 8 })
        .backgroundColor(ThemeManager.getCurrentAccentSurfaceVariantColorHex())
        .borderRadius(18)
        .border({ width: 1, color: $r('app.color.input_border') })
        .fontSize(16)
        .fontColor($r('app.color.on_surface'))
        .placeholderColor($r('app.color.on_surface_tertiary'))
        .maxLength(100)
        .onChange((value: string) => {
          this.name = value;
          this.errorMessage = '';
        })

      Text('设置提醒')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 22 })

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(12)
          .fontColor($r('app.color.warning'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 4 })
      }

      if (this.reminderAt !== null) {
        Row() {
          SymbolGlyph($r('sys.symbol.alarm'))
            .fontSize(14)
            .fontColor([ThemeManager.getCurrentAccentColorHex()])

          Text(TimeUtils.formatDetailTime(this.reminderAt))
            .fontSize(13)
            .fontColor($r('app.color.on_surface'))
            .margin({ left: 8 })
            .layoutWeight(1)

          Button('清除')
            .type(ButtonType.Capsule)
            .fontSize(12)
            .height(30)
            .backgroundColor($r('app.color.error_background_soft'))
            .fontColor($r('app.color.error'))
            .onClick(() => {
              this.clearReminder();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10 })
        .alignItems(VerticalAlign.Center)
      } else if (this.hasReminder() && this.clearReminderAt) {
        Text('已选择清除当前提醒')
          .fontSize(12)
          .fontColor($r('app.color.error'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 10 })
      }

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(BookmarkReminderPreset.values(), (preset: BookmarkReminderPreset) => {
          Text(preset.label)
            .fontSize(12)
            .fontWeight(this.selectedPresetKey === preset.key ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.selectedPresetKey === preset.key ? ThemeManager.getCurrentAccentColorHex() : $r('app.color.on_surface_secondary'))
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .backgroundColor(this.selectedPresetKey === preset.key
              ? ThemeManager.getCurrentAccentSelectedBackgroundColorHex()
              : ThemeManager.getCurrentAccentSurfaceVariantColorHex())
            .borderRadius(12)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.selectPreset(preset);
            })
        }, (preset: BookmarkReminderPreset) => preset.key.toString())

        Text(BookmarkReminderPreset.CUSTOM.label)
          .fontSize(12)
          .fontWeight(this.selectedPresetKey === BookmarkReminderPreset.CUSTOM.key ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.selectedPresetKey === BookmarkReminderPreset.CUSTOM.key
            ? ThemeManager.getCurrentAccentColorHex()
            : $r('app.color.on_surface_secondary'))
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor(this.selectedPresetKey === BookmarkReminderPreset.CUSTOM.key
            ? ThemeManager.getCurrentAccentSelectedBackgroundColorHex()
            : ThemeManager.getCurrentAccentSurfaceVariantColorHex())
          .borderRadius(12)
          .margin({ right: 8, bottom: 8 })
          .onClick(() => {
            this.selectPreset(BookmarkReminderPreset.CUSTOM);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })

      if (this.isCustomPickerVisible) {
        Column() {
          Row() {
            Text('自定义提醒')
              .fontSize(13)
              .fontColor($r('app.color.on_surface_secondary'))

            Blank().layoutWeight(1)

            Text(`${this.formatPickerDateLabel()} ${this.formatPickerTimeLabel()}`)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeManager.getCurrentAccentColorHex())
          }
          .width('100%')

          Row() {
            Button('选择日期')
              .type(ButtonType.Capsule)
              .layoutWeight(1)
              .height(40)
              .backgroundColor(ThemeManager.getCurrentAccentSelectedBackgroundColorHex())
              .fontColor(ThemeManager.getCurrentAccentColorHex())
              .onClick(() => {
                this.openCustomDateSheet();
              })

            Blank().width(12)

            Button('选择时间')
              .type(ButtonType.Capsule)
              .layoutWeight(1)
              .height(40)
              .backgroundColor(ThemeManager.getCurrentAccentSelectedBackgroundColorHex())
              .fontColor(ThemeManager.getCurrentAccentColorHex())
              .onClick(() => {
                this.openCustomTimeSheet();
              })
          }
          .width('100%')
          .margin({ top: 12 })

          Row() {
            Button('取消自定义')
              .type(ButtonType.Capsule)
              .layoutWeight(1)
              .height(40)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.on_surface_secondary'))
              .border({ width: 0 })
              .onClick(() => {
                this.closeCustomPicker();
              })

            Blank().width(12)

            Button('确认自定义')
              .type(ButtonType.Capsule)
              .layoutWeight(1)
              .height(40)
              .backgroundColor(ThemeManager.getCurrentAccentColorHex())
              .fontColor(Color.White)
              .onClick(() => {
                this.confirmCustomPicker();
              })
          }
          .width('100%')
          .margin({ top: 12 })
        }
        .width('100%')
        .margin({ left: 16, right: 16, top: 8 })
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .backgroundColor(ThemeManager.getCurrentAccentSurfaceVariantColorHex())
        .borderRadius(16)
      }

      Row() {
        Button(this.isDeleting ? '删除中...' : '删除书签')
          .type(ButtonType.Capsule)
          .height(44)
          .enabled(!this.isDeleting && !this.isSaving)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.error'))
          .border({ width: 0 })
          .padding({ left: 0, right: 0 })
          .onClick(() => {
            this.deleteBookmark().catch((_: Object) => {
            });
          })

        Blank().width(12)

        Button('取消')
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(44)
          .enabled(!this.isSaving && !this.isDeleting)
          .backgroundColor(Color.Transparent)
          .fontColor(ThemeManager.getCurrentAccentColorHex())
          .border({ width: 0 })
          .onClick(() => {
            this.onDismiss();
          })

        Blank().width(12)

        Button(this.isSaving ? '保存中...' : '保存')
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(44)
          .enabled(!this.isSaving && !this.isDeleting)
          .backgroundColor(ThemeManager.getCurrentAccentColorHex())
          .fontColor(Color.White)
          .onClick(() => {
            this.save().catch((_: Object) => {
            });
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 24 })

      Blank().height(20 + WindowManager.getSystemAvoidAreaBottomVp())

      Column() {
      }
      .width(0)
      .height(0)
      .bindSheet($$this.isCustomDateSheetVisible, this.CustomDateSheetBuilder, {
        height: SheetSize.FIT_CONTENT,
        dragBar: false,
        showClose: false,
        backgroundColor: ModalChromeHelper.getSheetBackgroundColor(),
        maskColor: ModalChromeHelper.getMaskColor(),
        blurStyle: ModalChromeHelper.getSheetBlurStyle()
      })

      Column() {
      }
      .width(0)
      .height(0)
      .bindSheet($$this.isCustomTimeSheetVisible, this.CustomTimeSheetBuilder, {
        height: SheetSize.FIT_CONTENT,
        dragBar: false,
        showClose: false,
        backgroundColor: ModalChromeHelper.getSheetBackgroundColor(),
        maskColor: ModalChromeHelper.getMaskColor(),
        blurStyle: ModalChromeHelper.getSheetBlurStyle()
      })
    }
    .width('100%')
    .backgroundColor(ThemeManager.getCurrentAccentSurfaceColorHex())
  }

  @Builder
  private CustomDateSheetBuilder() {
    Column() {
      Row() {
        Text('选择日期')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .layoutWeight(1)

        Text('取消')
          .fontSize(15)
          .fontColor($r('app.color.on_surface_secondary'))
          .onClick(() => {
            this.isCustomDateSheetVisible = false;
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 18, bottom: 12 })

      DatePicker({
        start: new Date('2024-01-01'),
        end: new Date('2100-12-31'),
        selected: this.pickerDate
      })
        .width('100%')
        .lunar(false)
        .onDateChange((value: Date) => {
          this.pickerDate = new Date(value.getTime());
        })

      Row() {
        Blank().layoutWeight(1)

        Text('确定')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeManager.getCurrentAccentColorHex())
          .onClick(() => {
            this.isCustomDateSheetVisible = false;
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12, bottom: 18 + WindowManager.getSystemAvoidAreaBottomVp() })
    }
    .width('100%')
    .backgroundColor(ThemeManager.getCurrentAccentSurfaceColorHex())
  }

  @Builder
  private CustomTimeSheetBuilder() {
    Column() {
      Row() {
        Text('选择时间')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .layoutWeight(1)

        Text('取消')
          .fontSize(15)
          .fontColor($r('app.color.on_surface_secondary'))
          .onClick(() => {
            this.isCustomTimeSheetVisible = false;
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 18, bottom: 12 })

      TimePicker({
        selected: this.pickerTime,
        format: TimePickerFormat.HOUR_MINUTE_SECOND
      })
        .width('100%')
        .useMilitaryTime(true)
        .onChange((value: TimePickerResult) => {
          if (value.hour >= 0) {
            this.pickerTime = new Date(2026, 0, 1, value.hour, value.minute, value.second !== undefined ? value.second : 0, 0);
          }
        })

      Row() {
        Blank().layoutWeight(1)

        Text('确定')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeManager.getCurrentAccentColorHex())
          .onClick(() => {
            this.isCustomTimeSheetVisible = false;
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12, bottom: 18 + WindowManager.getSystemAvoidAreaBottomVp() })
    }
    .width('100%')
    .backgroundColor(ThemeManager.getCurrentAccentSurfaceColorHex())
  }
}
