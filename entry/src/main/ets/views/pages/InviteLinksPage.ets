import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { SystemShareService } from '../../common/utils/SystemShareService';
import { WindowManager } from '../../common/utils/WindowManager';
import { ToastService } from '../../common/utils/ToastService';
import { ApiClient } from '../../services/network/ApiClient';
import { InviteLinkDetails, InviteLinkResponse } from '../../models/InviteLink';
import { TimeUtils } from '../../common/utils/TimeUtils';
import { AppConstants } from '../../common/constants/AppConstants';
import { ImmersiveHdsTitleBarHelper } from '../components/ImmersiveHdsTitleBarHelper';

const TAG: string = 'InviteLinksPage';
const PAGE_HORIZONTAL_PADDING: number = 16;
const CARD_CORNER_RADIUS: number = 20;
const HERO_CARD_CORNER_RADIUS: number = 24;
const CARD_INNER_RADIUS: number = 14;

class InviteMeta {
  maxRedemptions: number;
  usedCount: number;
  expiresLabel: string;
  isNever: boolean;

  constructor(maxRedemptions: number, usedCount: number, expiresLabel: string, isNever: boolean) {
    this.maxRedemptions = maxRedemptions;
    this.usedCount = usedCount;
    this.expiresLabel = expiresLabel;
    this.isNever = isNever;
  }
}

const EXPIRY_PRESET_1_DAY: number = 0;
const EXPIRY_PRESET_7_DAYS: number = 1;
const EXPIRY_PRESET_30_DAYS: number = 2;
const EXPIRY_PRESET_90_DAYS: number = 3;
const EXPIRY_PRESET_NEVER: number = 4;

@ComponentV2
export struct InviteLinksPage {
  @Local isLoading: boolean = false;
  @Local isSubmitting: boolean = false;
  @Local errorMessage: string = '';
  @Local latestInvite: InviteLinkResponse | null = null;
  @Local selectedExpiryPreset: number = EXPIRY_PRESET_1_DAY;
  @Local showAdvancedOptions: boolean = false;
  @Local descriptionText: string = '';
  @Local emailText: string = '';

  private contentScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadPendingInvites().catch((err: Object) => {
      hilog.error(0x0000, TAG, 'loadPendingInvites failed: %{public}s', ApiClient.formatError(err));
    });
  }

  private getExpiryDays(): number | null {
    switch (this.selectedExpiryPreset) {
      case EXPIRY_PRESET_1_DAY:
        return 1;
      case EXPIRY_PRESET_7_DAYS:
        return 7;
      case EXPIRY_PRESET_30_DAYS:
        return 30;
      case EXPIRY_PRESET_90_DAYS:
        return 90;
      case EXPIRY_PRESET_NEVER:
        return null;
      default:
        return 1;
    }
  }

  private getExpiryLabel(): string {
    const resourceManager = getContext().resourceManager;

    switch (this.selectedExpiryPreset) {
      case EXPIRY_PRESET_1_DAY:
        return resourceManager.getStringSync($r('app.string.invite_1_day').id);
      case EXPIRY_PRESET_7_DAYS:
        return resourceManager.getStringSync($r('app.string.invite_7_days').id);
      case EXPIRY_PRESET_30_DAYS:
        return resourceManager.getStringSync($r('app.string.invite_30_days').id);
      case EXPIRY_PRESET_90_DAYS:
        return resourceManager.getStringSync($r('app.string.invite_90_days').id);
      case EXPIRY_PRESET_NEVER:
        return resourceManager.getStringSync($r('app.string.invite_no_expiry').id);
      default:
        return resourceManager.getStringSync($r('app.string.invite_7_days').id);
    }
  }

  private getEffectiveInviteLink(): string {
    if (this.latestInvite === null) {
      return '';
    }
    const invite: InviteLinkResponse = this.latestInvite as InviteLinkResponse;
    const raw: string = invite.inviteLink !== undefined && invite.inviteLink !== null
      ? invite.inviteLink.toString().trim()
      : '';
    if (raw.length > 0) {
      return raw;
    }
    if (invite.invite !== null && invite.invite.inviteKey !== null) {
      const key: string = (invite.invite.inviteKey as string).trim();
      if (key.length > 0) {
        return `${AppConstants.BASE_URL}/invites/${key}`;
      }
    }
    return '';
  }

  private hasInviteLink(): boolean {
    return this.getEffectiveInviteLink().length > 0;
  }

  private getExpirySummary(): string {
    const resourceManager = getContext().resourceManager;
    const days: number | null = this.getExpiryDays();

    if (days === null) {
      return resourceManager.getStringSync($r('app.string.invite_summary_never').id);
    }

    if (days === 1) {
      return resourceManager.getStringSync($r('app.string.invite_summary_day1').id);
    }

    return `链接可被 1 名用户使用，${this.getExpiryLabel()}后过期。`;
  }

  private getPageSubtitle(): string {
    return '邀请朋友加入社区，创建专属入口并管理最近生成的邀请结果';
  }

  private getFormCaption(): string {
    return this.showAdvancedOptions ? '自定义邀请说明、限制对象与有效期' : '默认生成 1 人可用的邀请链接';
  }

  private getEmptyHint(): string {
    return '创建成功后，最近一次邀请结果会展示在这里，方便你继续复制或分享。';
  }

  private async loadPendingInvites(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    try {
      const api: ApiClient = ApiClient.getInstance();
      const currentUser = await api.getCurrentUser();
      const username: string = currentUser !== null ? currentUser.username.trim() : '';
      if (username.length === 0) {
        this.isLoading = false;
        return;
      }
      const list: InviteLinkResponse[] = await api.getPendingInvites(username);
      if (list.length > 0) {
        this.latestInvite = list[0];
      }
      this.isLoading = false;
    } catch (err) {
      hilog.error(0x0000, TAG, 'loadPendingInvites failed: %{public}s', ApiClient.formatError(err));
      this.errorMessage = getContext().resourceManager
        .getStringSync($r('app.string.invite_create_failed').id);
      this.isLoading = false;
    }
  }

  private async createInvite(): Promise<void> {
    if (this.isSubmitting) {
      return;
    }
    this.isSubmitting = true;
    this.errorMessage = '';
    try {
      const api: ApiClient = ApiClient.getInstance();
      const days: number | null = this.getExpiryDays();
      let expiresAt: Date | null = null;
      if (days !== null) {
        const now: Date = new Date();
        expiresAt = new Date(now.getTime() + days * 24 * 60 * 60 * 1000);
      }
      const resp: InviteLinkResponse = await api.createInviteLink(1, expiresAt, this.descriptionText, this.emailText);
      this.latestInvite = resp;
      ToastService.show($r('app.string.invite_link_generated'));
    } catch (err) {
      const text: string = err !== undefined && err !== null ? err.toString() : '';
      if (text.indexOf('HTTP 429') >= 0) {
        this.errorMessage = getContext().resourceManager
          .getStringSync($r('app.string.invite_rate_limited').id);
      } else if (text.indexOf('HTTP 403') >= 0) {
        this.errorMessage = getContext().resourceManager.getStringSync($r('app.string.invite_permission_denied').id);
      } else {
        this.errorMessage = getContext().resourceManager.getStringSync($r('app.string.invite_create_failed').id);
      }
      ToastService.show(this.errorMessage);
    } finally {
      this.isSubmitting = false;
    }
  }

  private async copyInviteLink(): Promise<void> {
    const link: string = this.getEffectiveInviteLink();
    const trimmed: string = link !== undefined && link !== null ? link.trim() : '';
    if (trimmed.length === 0) {
      return;
    }
    try {
      const sysPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = pasteboard.createPlainTextData(trimmed);
      await sysPasteboard.setData(data);
      ToastService.show($r('app.string.invite_link_copied'));
    } catch (err) {
      hilog.error(0x0000, TAG, 'copyInviteLink failed: %{public}s', JSON.stringify(err));
      ToastService.show($r('app.string.invite_copy'));
    }
  }

  private async shareInviteLink(): Promise<void> {
    const link: string = this.getEffectiveInviteLink();
    const trimmed: string = link !== undefined && link !== null ? link.trim() : '';
    if (trimmed.length === 0) {
      return;
    }
    const subject: string = getContext().resourceManager.getStringSync($r('app.string.invite_share_subject').id);
    await SystemShareService.shareText(trimmed, subject, true);
  }

  @Builder
  private SectionTitle(title: Resource | string, subtitle: string) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
      Text(subtitle)
        .fontSize(12)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private HeroInviteCard() {
    Column() {
      Text('邀请工作台')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface_secondary'))

      Row() {
        Column() {
          Text($r('app.string.invite_page_title'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
          Text(this.getPageSubtitle())
            .fontSize(13)
            .fontColor($r('app.color.on_surface_secondary'))
            .lineHeight(20)
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text('L3+')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary'))
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor($r('app.color.badge_background_light'))
          .borderRadius(12)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .margin({ top: 10 })

      Row() {
        Column() {
          Text('当前规则')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface_tertiary'))
          Text(this.getExpirySummary())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'))
            .lineHeight(21)
            .margin({ top: 6 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 14 })
      .margin({ top: 16 })
      .backgroundColor($r('app.color.surface_variant'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.divider_light') })

      if (this.errorMessage.length > 0) {
        Row() {
          Text(this.errorMessage)
            .fontSize(13)
            .fontColor($r('app.color.error'))
            .lineHeight(20)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .margin({ top: 14 })
        .backgroundColor($r('app.color.error_background_soft'))
        .borderRadius(16)
      }

      Button(this.isSubmitting ? $r('app.string.invite_creating') : $r('app.string.invite_create_link'), {
        type: ButtonType.Capsule,
        stateEffect: true
      })
        .width('100%')
        .height(44)
        .margin({ top: 18 })
        .backgroundColor($r('app.color.on_surface'))
        .fontColor($r('app.color.surface'))
        .enabled(!this.isSubmitting)
        .onClick(() => {
          if (!this.isSubmitting) {
            this.createInvite().catch(() => {});
          }
        })

      Row() {
        Text(this.showAdvancedOptions ? $r('app.string.invite_collapse_options') : $r('app.string.invite_expand_options'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary'))
        Blank().layoutWeight(1)
        SymbolGlyph(this.showAdvancedOptions ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(14)
          .fontColor([$r('app.color.primary')])
      }
      .width('100%')
      .margin({ top: 14 })
      .padding({ top: 2, bottom: 2 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.showAdvancedOptions = !this.showAdvancedOptions;
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 18, bottom: 18 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(HERO_CARD_CORNER_RADIUS)
    .border({ width: 1, color: $r('app.color.divider_light') })
    .shadow({ radius: 14, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 6 })
  }



  @Builder
  private AdvancedInviteFormCard() {
    Column() {
      this.SectionTitle($r('app.string.invite_invite_members'), this.getFormCaption())

      Column() {
        Text('邀请说明')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
        Text('给这次邀请补充备注，方便自己区分用途。')
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ top: 4, bottom: 10 })
        TextInput({
          text: this.descriptionText,
          placeholder: $r('app.string.invite_description')
        })
          .maxLength(100)
          .backgroundColor($r('app.color.surface_variant'))
          .borderRadius(CARD_INNER_RADIUS)
          .border({ width: 1, color: $r('app.color.input_border') })
          .padding({ left: 12, right: 12 })
          .height(44)
          .onChange((value: string) => {
            this.descriptionText = value;
          })
      }
      .width('100%')
      .margin({ top: 18 })
      .alignItems(HorizontalAlign.Start)

      Column() {
        Text('限制对象')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
        Text('可限制为指定邮箱或域名，不填则任何符合条件的用户都可使用。')
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .lineHeight(18)
          .margin({ top: 4, bottom: 10 })
        TextInput({
          text: this.emailText,
          placeholder: $r('app.string.invite_restriction_hint')
        })
          .backgroundColor($r('app.color.surface_variant'))
          .borderRadius(CARD_INNER_RADIUS)
          .border({ width: 1, color: $r('app.color.input_border') })
          .padding({ left: 12, right: 12 })
          .height(44)
          .onChange((value: string) => {
            this.emailText = value;
          })
      }
      .width('100%')
      .margin({ top: 18 })
      .alignItems(HorizontalAlign.Start)

      Column() {
        Text($r('app.string.invite_max_redemptions'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
        Text('当前与站点规则保持一致，固定为单人使用。')
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ top: 4, bottom: 10 })
        Row() {
          Text('1')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
          Blank().layoutWeight(1)
          Text($r('app.string.invite_fixed'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface_secondary'))
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(CARD_INNER_RADIUS)
        .border({ width: 1, color: $r('app.color.divider_light') })
      }
      .width('100%')
      .margin({ top: 18 })
      .alignItems(HorizontalAlign.Start)

      Column() {
        Text($r('app.string.invite_expiry_time'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
        Text('根据邀请场景选择一个时效，默认使用最轻量的短期链接。')
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .lineHeight(18)
          .margin({ top: 4, bottom: 12 })
        this.ExpiryPresetChips()
      }
      .width('100%')
      .margin({ top: 18 })
      .alignItems(HorizontalAlign.Start)

      Button(this.isSubmitting ? $r('app.string.invite_creating') : $r('app.string.invite_create_link'), {
        type: ButtonType.Capsule,
        stateEffect: true
      })
        .width('100%')
        .height(42)
        .margin({ top: 22 })
        .backgroundColor($r('app.color.on_surface'))
        .fontColor($r('app.color.surface'))
        .enabled(!this.isSubmitting)
        .onClick(() => {
          if (!this.isSubmitting) {
            this.createInvite().catch(() => {});
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 18, bottom: 18 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(CARD_CORNER_RADIUS)
    .border({ width: 1, color: $r('app.color.divider_light') })
    .shadow({ radius: 12, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 6 })
  }

  @Builder
  private ExpiryPresetChips() {
    Flex({ wrap: FlexWrap.Wrap }) {
      this.ExpiryChip(EXPIRY_PRESET_1_DAY, $r('app.string.invite_1_day'))
      this.ExpiryChip(EXPIRY_PRESET_7_DAYS, $r('app.string.invite_7_days'))
      this.ExpiryChip(EXPIRY_PRESET_30_DAYS, $r('app.string.invite_30_days'))
      this.ExpiryChip(EXPIRY_PRESET_90_DAYS, $r('app.string.invite_90_days'))
      this.ExpiryChip(EXPIRY_PRESET_NEVER, $r('app.string.invite_no_expiry'))
    }
    .width('100%')
  }

  @Builder
  private ExpiryChip(index: number, label: Resource) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.selectedExpiryPreset === index ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.selectedExpiryPreset === index ? $r('app.color.primary') : $r('app.color.on_surface_secondary'))
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.selectedExpiryPreset === index ? $r('app.color.badge_background_light') : $r('app.color.surface_variant'))
      .borderRadius(12)
      .border({
        width: 1,
        color: this.selectedExpiryPreset === index ? $r('app.color.primary') : $r('app.color.divider_light')
      })
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.selectedExpiryPreset = index;
      })
  }

  @Builder
  private InviteMetaBadge(title: string, value: string, emphasized: boolean = false) {
    Column() {
      Text(title)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface_tertiary'))
      Text(value)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(emphasized ? $r('app.color.primary') : $r('app.color.on_surface'))
        .margin({ top: 4 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.surface_variant'))
    .borderRadius(14)
    .border({ width: 1, color: $r('app.color.divider_light') })
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  private getInviteMeta(): InviteMeta {
    let maxRedemptions: number = 1;
    let usedCount: number = 0;
    let expiresLabel: string = '';
    let isNever: boolean = false;

    if (this.latestInvite !== null && this.latestInvite.invite !== null) {
      const details: InviteLinkDetails = this.latestInvite.invite as InviteLinkDetails;
      if (details.maxRedemptionsAllowed !== null) {
        maxRedemptions = details.maxRedemptionsAllowed as number;
      }
      if (details.redemptionCount !== null) {
        usedCount = details.redemptionCount as number;
      }
      if (details.expiresAt !== null) {
        expiresLabel = TimeUtils.formatDetailTime(details.expiresAt as Date);
      } else {
        expiresLabel = getContext().resourceManager.getStringSync($r('app.string.invite_no_expiry').id);
        isNever = true;
      }
    } else {
      expiresLabel = getContext().resourceManager.getStringSync($r('app.string.invite_no_expiry').id);
      isNever = true;
    }

    return new InviteMeta(maxRedemptions, usedCount, expiresLabel, isNever);
  }

  private getInviteMaxRedemptions(): number {
    return this.getInviteMeta().maxRedemptions;
  }

  private getInviteUsedCount(): number {
    return this.getInviteMeta().usedCount;
  }

  private getInviteExpiresLabel(): string {
    return this.getInviteMeta().expiresLabel;
  }

  private getInviteIsNever(): boolean {
    return this.getInviteMeta().isNever;
  }

  @Builder
  private InviteResultCard() {
    Column() {
      this.SectionTitle($r('app.string.invite_latest_result'), '最近一次可用邀请结果，方便你继续复制或转发。')

      Column() {
        Text(this.getEffectiveInviteLink())
          .fontSize(14)
          .fontColor($r('app.color.on_surface'))
          .lineHeight(20)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 14 })
      .margin({ top: 16 })
      .backgroundColor($r('app.color.surface_variant'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.divider_light') })

      Row() {
        this.InviteMetaBadge('使用次数', `最多 ${this.getInviteMaxRedemptions()} 次，已使用 ${this.getInviteUsedCount()} 次`)
        Blank().width(10)
        this.InviteMetaBadge(
          this.getInviteIsNever() ? '当前状态' : '过期时间',
          this.getInviteIsNever() ? '永不过期' : this.getInviteExpiresLabel(),
          this.getInviteIsNever()
        )
      }
      .width('100%')
      .margin({ top: 14 })
      .alignItems(VerticalAlign.Top)

      Row() {
        Button($r('app.string.invite_copy'), {
          type: ButtonType.Normal,
          stateEffect: true
        })
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.surface_variant'))
          .fontColor($r('app.color.on_surface'))
          .borderRadius(20)
          .onClick(() => {
            this.copyInviteLink().catch(() => {});
          })

        Blank().width(12)

        Button($r('app.string.invite_share'), {
          type: ButtonType.Capsule,
          stateEffect: true
        })
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.on_surface'))
          .fontColor($r('app.color.surface'))
          .onClick(() => {
            this.shareInviteLink().catch(() => {});
          })
      }
      .width('100%')
      .margin({ top: 18 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 18, bottom: 18 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(CARD_CORNER_RADIUS)
    .border({ width: 1, color: $r('app.color.divider_light') })
    .shadow({ radius: 12, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 6 })
  }

  @Builder
  private InviteEmptyCard() {
    Column() {
      Text($r('app.string.invite_no_links'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface'))
      Text(this.getEmptyHint())
        .fontSize(13)
        .fontColor($r('app.color.on_surface_secondary'))
        .lineHeight(20)
        .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 18, bottom: 18 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(CARD_CORNER_RADIUS)
    .border({ width: 1, color: $r('app.color.divider_light') })
  }

  @Builder
  private PageContent() {
    Scroll(this.contentScroller) {
      Column() {
        Blank()
          .height(ImmersiveHdsTitleBarHelper.getContentTopSpacerHeightVp())
          .width('100%')

        this.HeroInviteCard()
        if (this.showAdvancedOptions) {
          Blank().height(16)
          this.AdvancedInviteFormCard()
        }

        Blank().height(16)

        if (this.hasInviteLink()) {
          this.InviteResultCard()
        } else if (!this.isLoading) {
          this.InviteEmptyCard()
        }

        Blank().height(32)
      }
      .padding({
        left: PAGE_HORIZONTAL_PADDING,
        right: PAGE_HORIZONTAL_PADDING,
        bottom: 16 + WindowManager.getSystemAvoidAreaBottomVp()
      })
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .layoutWeight(1)
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Column() {
        this.PageContent()
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
    }
    .backgroundColor($r('app.color.background'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .titleBar(ImmersiveHdsTitleBarHelper.buildImmersiveTitleBar($r('app.string.invite_page_title')))
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
}
