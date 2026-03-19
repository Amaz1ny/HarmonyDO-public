import { ApiClient } from '../../services/network/ApiClient';
import { TimeUtils } from '../../common/utils/TimeUtils';
import { ToastService } from '../../common/utils/ToastService';
import { WindowManager } from '../../common/utils/WindowManager';

class BookmarkReminderPreset {
  readonly key: number;
  readonly label: string;

  constructor(key: number, label: string) {
    this.key = key;
    this.label = label;
  }

  static readonly ONE_HOUR: BookmarkReminderPreset = new BookmarkReminderPreset(1, '1小时后');
  static readonly TONIGHT: BookmarkReminderPreset = new BookmarkReminderPreset(2, '今晚');
  static readonly TOMORROW: BookmarkReminderPreset = new BookmarkReminderPreset(3, '明早');
  static readonly NEXT_WEEK: BookmarkReminderPreset = new BookmarkReminderPreset(4, '下周');

  static values(): BookmarkReminderPreset[] {
    return [
      BookmarkReminderPreset.ONE_HOUR,
      BookmarkReminderPreset.TONIGHT,
      BookmarkReminderPreset.TOMORROW,
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

  aboutToAppear(): void {
    this.name = this.initialName;
    this.reminderAt = this.initialReminderAt;
    this.selectedPresetKey = 0;
    this.clearReminderAt = false;
    this.isSaving = false;
    this.isDeleting = false;
    this.errorMessage = '';
  }

  private computePresetReminderAt(presetKey: number): Date | null {
    const now: Date = new Date();
    if (presetKey === BookmarkReminderPreset.ONE_HOUR.key) {
      return new Date(now.getTime() + 60 * 60 * 1000);
    }
    if (presetKey === BookmarkReminderPreset.TONIGHT.key) {
      const tonight: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 20, 0, 0, 0);
      if (tonight.getTime() <= now.getTime()) {
        tonight.setDate(tonight.getDate() + 1);
      }
      return tonight;
    }
    if (presetKey === BookmarkReminderPreset.TOMORROW.key) {
      return new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 9, 0, 0, 0);
    }
    if (presetKey === BookmarkReminderPreset.NEXT_WEEK.key) {
      return new Date(now.getFullYear(), now.getMonth(), now.getDate() + 7, 9, 0, 0, 0);
    }
    return null;
  }

  private selectPreset(preset: BookmarkReminderPreset): void {
    if (this.selectedPresetKey === preset.key) {
      this.selectedPresetKey = 0;
      this.reminderAt = this.initialReminderAt;
      this.clearReminderAt = false;
      return;
    }
    this.selectedPresetKey = preset.key;
    this.reminderAt = this.computePresetReminderAt(preset.key);
    this.clearReminderAt = false;
  }

  private clearReminder(): void {
    this.selectedPresetKey = 0;
    this.reminderAt = null;
    this.clearReminderAt = true;
  }

  private hasReminder(): boolean {
    return this.reminderAt !== null || this.initialReminderAt !== null;
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
      Column() {
      }
      .width(36)
      .height(4)
      .borderRadius(2)
      .backgroundColor($r('app.color.divider_light'))
      .margin({ top: 12, bottom: 12 })

      Row() {
        Text('编辑书签')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .layoutWeight(1)

        Button('关闭')
          .type(ButtonType.Capsule)
          .fontSize(13)
          .height(34)
          .backgroundColor($r('app.color.surface_variant'))
          .fontColor($r('app.color.on_surface_secondary'))
          .onClick(() => {
            this.onDismiss();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(12)
          .fontColor($r('app.color.warning'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 10 })
      }

      Text('书签名称')
        .fontSize(13)
        .fontColor($r('app.color.on_surface_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 14 })

      TextInput({ text: this.name, placeholder: '给这个书签起个备注（可选）' })
        .width('100%')
        .height(48)
        .padding({ left: 14, right: 14 })
        .margin({ left: 16, right: 16, top: 8 })
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(14)
        .fontSize(15)
        .fontColor($r('app.color.on_surface'))
        .placeholderColor($r('app.color.on_surface_tertiary'))
        .maxLength(100)
        .onChange((value: string) => {
          this.name = value;
          this.errorMessage = '';
        })

      Text('提醒')
        .fontSize(13)
        .fontColor($r('app.color.on_surface_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 18 })

      if (this.reminderAt !== null) {
        Row() {
          SymbolGlyph($r('sys.symbol.alarm'))
            .fontSize(14)
            .fontColor([$r('app.color.primary')])

          Text(TimeUtils.formatDetailTime(this.reminderAt))
            .fontSize(13)
            .fontColor($r('app.color.on_surface'))
            .margin({ left: 8 })
            .layoutWeight(1)

          Button('清除')
            .type(ButtonType.Capsule)
            .fontSize(12)
            .height(30)
            .backgroundColor('#FDECEC')
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
            .fontColor(this.selectedPresetKey === preset.key ? $r('app.color.primary') : $r('app.color.on_surface_secondary'))
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .backgroundColor(this.selectedPresetKey === preset.key
              ? $r('app.color.badge_background_light')
              : $r('app.color.surface_variant'))
            .borderRadius(12)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.selectPreset(preset);
            })
        }, (preset: BookmarkReminderPreset) => preset.key.toString())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })

      Row() {
        Button(this.isDeleting ? '删除中...' : '删除书签')
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(44)
          .enabled(!this.isDeleting && !this.isSaving)
          .backgroundColor('#FDECEC')
          .fontColor($r('app.color.error'))
          .onClick(() => {
            this.deleteBookmark().catch((_: Object) => {
            });
          })

        Blank().width(12)

        Button(this.isSaving ? '保存中...' : '保存')
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(44)
          .enabled(!this.isSaving && !this.isDeleting)
          .backgroundColor($r('app.color.primary'))
          .fontColor(Color.White)
          .onClick(() => {
            this.save().catch((_: Object) => {
            });
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 18 })

      Blank().height(20 + WindowManager.getSystemAvoidAreaBottomVp())
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
  }
}
