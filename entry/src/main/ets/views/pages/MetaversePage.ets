import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppSettingsService } from '../../services/storage/AppSettingsService';
import { MetaverseStateService } from '../../services/storage/MetaverseStateService';
import { PreferencesUtil } from '../../services/storage/PreferencesUtil';
import { AuthService } from '../../services/auth/AuthService';
import { CdkOAuthService } from '../../services/network/CdkOAuthService';
import { LdcOAuthService } from '../../services/network/LdcOAuthService';
import { RouterManager } from '../../common/utils/RouterManager';
import { ToastService } from '../../common/utils/ToastService';
import { WindowManager } from '../../common/utils/WindowManager';
import { ExternalLinkService } from '../../common/utils/ExternalLinkService';
import { CdkUserInfo, LdcUserInfo, OAuthAuthorizationContext } from '../../models/Metaverse';

const TOP_BAR_HEIGHT: number = 56;
const LDC_REWARD_CLIENT_ID_KEY: string = 'ldc.reward.client_id';
const LDC_REWARD_CLIENT_SECRET_KEY: string = 'ldc.reward.client_secret';

@ComponentV2
export struct MetaversePage {
  @Local isLoading: boolean = true;
  @Local ldcEnabled: boolean = false;
  @Local cdkEnabled: boolean = false;
  @Local ldcInfo: LdcUserInfo | null = null;
  @Local cdkInfo: CdkUserInfo | null = null;
  @Local ldcErrorMessage: string = '';
  @Local cdkErrorMessage: string = '';
  @Local isLdcProcessing: boolean = false;
  @Local isCdkProcessing: boolean = false;
  @Local pendingAuthContext: OAuthAuthorizationContext | null = null;
  @Local isAuthSheetVisible: boolean = false;
  @Local isRewardSheetVisible: boolean = false;
  @Local rewardClientId: string = '';
  @Local rewardClientSecret: string = '';

  private stateListener: (() => void) | null = null;

  aboutToAppear(): void {
    this.attachStateListener();
    this.bootstrap().catch((err: Object) => {
      const message: string = this.normalizeErrorMessage(err, '加载元宇宙状态失败');
      this.ldcErrorMessage = message;
      this.cdkErrorMessage = message;
      this.isLoading = false;
    });
  }

  aboutToDisappear(): void {
    if (this.stateListener !== null) {
      MetaverseStateService.getInstance().removeListener(this.stateListener);
      this.stateListener = null;
    }
  }

  private attachStateListener(): void {
    if (this.stateListener !== null) {
      return;
    }
    this.stateListener = () => {
      this.syncFromStateService();
    };
    MetaverseStateService.getInstance().addListener(this.stateListener);
  }

  private async bootstrap(): Promise<void> {
    await MetaverseStateService.getInstance().ensureInit();
    this.syncFromStateService();
    this.isLoading = false;
    await this.refreshEnabledServices();
  }

  private syncFromStateService(): void {
    const service: MetaverseStateService = MetaverseStateService.getInstance();
    this.ldcEnabled = service.isLdcEnabled();
    this.cdkEnabled = service.isCdkEnabled();
    this.ldcInfo = service.getLdcInfo();
    this.cdkInfo = service.getCdkInfo();
  }

  private async refreshEnabledServices(): Promise<void> {
    if (this.ldcEnabled) {
      await this.refreshLdc();
    }
    if (this.cdkEnabled) {
      await this.refreshCdk();
    }
  }

  private normalizeErrorMessage(err: Object, fallback: string): string {
    if (err === undefined || err === null) {
      return fallback;
    }
    const text: string = err.toString().replace('Error: ', '').trim();
    return text.length > 0 ? text : fallback;
  }

  private ensureLoginBeforeAuthorize(): boolean {
    if (!AuthService.getInstance().getIsLoggedIn()) {
      ToastService.show('请先登录 Linux.do 再接入元宇宙服务');
      return false;
    }
    return true;
  }

  private async refreshLdc(): Promise<void> {
    this.ldcErrorMessage = '';
    try {
      await MetaverseStateService.getInstance().refreshLdc();
      this.syncFromStateService();
    } catch (err) {
      this.ldcErrorMessage = this.normalizeErrorMessage(err, '刷新 LDC 信息失败');
    }
  }

  private async refreshCdk(): Promise<void> {
    this.cdkErrorMessage = '';
    try {
      await MetaverseStateService.getInstance().refreshCdk();
      this.syncFromStateService();
    } catch (err) {
      this.cdkErrorMessage = this.normalizeErrorMessage(err, '刷新 CDK 信息失败');
    }
  }

  private async startLdcAuthorization(reauthorize: boolean = false): Promise<void> {
    if (!this.ensureLoginBeforeAuthorize() || this.isLdcProcessing) {
      return;
    }
    this.isLdcProcessing = true;
    this.ldcErrorMessage = '';
    try {
      if (reauthorize) {
        try {
          await new LdcOAuthService().logout();
        } catch (_) {
        }
      }
      const context: OAuthAuthorizationContext | null = await new LdcOAuthService().prepareAuthorization();
      if (context === null) {
        throw new Error('未获取到 LDC 授权确认链接');
      }
      this.pendingAuthContext = context;
      this.isAuthSheetVisible = true;
    } catch (err) {
      this.ldcErrorMessage = this.normalizeErrorMessage(err, '拉起 LDC 授权失败');
    } finally {
      this.isLdcProcessing = false;
    }
  }

  private async startCdkAuthorization(reauthorize: boolean = false): Promise<void> {
    if (!this.ensureLoginBeforeAuthorize() || this.isCdkProcessing) {
      return;
    }
    this.isCdkProcessing = true;
    this.cdkErrorMessage = '';
    try {
      if (reauthorize) {
        try {
          await new CdkOAuthService().logout();
        } catch (_) {
        }
      }
      const context: OAuthAuthorizationContext | null = await new CdkOAuthService().prepareAuthorization();
      if (context === null) {
        throw new Error('未获取到 CDK 授权确认链接');
      }
      this.pendingAuthContext = context;
      this.isAuthSheetVisible = true;
    } catch (err) {
      this.cdkErrorMessage = this.normalizeErrorMessage(err, '拉起 CDK 授权失败');
    } finally {
      this.isCdkProcessing = false;
    }
  }

  private async confirmAuthorization(): Promise<void> {
    if (this.pendingAuthContext === null) {
      this.isAuthSheetVisible = false;
      return;
    }
    const context: OAuthAuthorizationContext = this.pendingAuthContext as OAuthAuthorizationContext;
    const isLdc: boolean = context.serviceKey === 'ldc';
    this.isAuthSheetVisible = false;
    this.pendingAuthContext = null;
    if (isLdc) {
      this.isLdcProcessing = true;
      this.ldcErrorMessage = '';
    } else {
      this.isCdkProcessing = true;
      this.cdkErrorMessage = '';
    }
    try {
      const ok: boolean = isLdc
        ? await new LdcOAuthService().approveAuthorization(context)
        : await new CdkOAuthService().approveAuthorization(context);
      if (!ok) {
        throw new Error(`${context.serviceName} 授权确认失败`);
      }
      if (isLdc) {
        await MetaverseStateService.getInstance().setLdcEnabled(true);
        await this.refreshLdc();
      } else {
        await MetaverseStateService.getInstance().setCdkEnabled(true);
        await this.refreshCdk();
      }
      ToastService.show(`${context.serviceName} 已接入`);
    } catch (err) {
      const message: string = this.normalizeErrorMessage(err, `${context.serviceName} 授权失败`);
      if (isLdc) {
        this.ldcErrorMessage = message;
      } else {
        this.cdkErrorMessage = message;
      }
    } finally {
      if (isLdc) {
        this.isLdcProcessing = false;
      } else {
        this.isCdkProcessing = false;
      }
    }
  }

  private async disableLdc(): Promise<void> {
    if (this.isLdcProcessing) {
      return;
    }
    this.isLdcProcessing = true;
    try {
      try {
        await new LdcOAuthService().logout();
      } catch (_) {
      }
      await MetaverseStateService.getInstance().setLdcEnabled(false);
      this.ldcErrorMessage = '';
      ToastService.show('已退出 LDC 授权');
    } finally {
      this.syncFromStateService();
      this.isLdcProcessing = false;
    }
  }

  private async disableCdk(): Promise<void> {
    if (this.isCdkProcessing) {
      return;
    }
    this.isCdkProcessing = true;
    try {
      try {
        await new CdkOAuthService().logout();
      } catch (_) {
      }
      await MetaverseStateService.getInstance().setCdkEnabled(false);
      this.cdkErrorMessage = '';
      ToastService.show('已退出 CDK 授权');
    } finally {
      this.syncFromStateService();
      this.isCdkProcessing = false;
    }
  }

  private async openRewardConfig(): Promise<void> {
    await PreferencesUtil.ensureInit();
    this.rewardClientId = await PreferencesUtil.getString(LDC_REWARD_CLIENT_ID_KEY, '');
    this.rewardClientSecret = await PreferencesUtil.getString(LDC_REWARD_CLIENT_SECRET_KEY, '');
    this.isRewardSheetVisible = true;
  }

  private async saveRewardConfig(): Promise<void> {
    const clientId: string = this.rewardClientId.trim();
    const clientSecret: string = this.rewardClientSecret.trim();
    if (clientId.length === 0 || clientSecret.length === 0) {
      ToastService.show('请填写完整的 Client ID 与 Client Secret');
      return;
    }
    await PreferencesUtil.putString(LDC_REWARD_CLIENT_ID_KEY, clientId);
    await PreferencesUtil.putString(LDC_REWARD_CLIENT_SECRET_KEY, clientSecret);
    this.isRewardSheetVisible = false;
    ToastService.show('LDC 打赏配置已保存');
  }

  private async clearRewardConfig(): Promise<void> {
    await PreferencesUtil.delete(LDC_REWARD_CLIENT_ID_KEY);
    await PreferencesUtil.delete(LDC_REWARD_CLIENT_SECRET_KEY);
    this.rewardClientId = '';
    this.rewardClientSecret = '';
    this.isRewardSheetVisible = false;
    ToastService.show('已清空 LDC 打赏配置');
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

      Text('元宇宙')
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
  private SectionTitle(title: string, subtitle: string = '') {
    Column() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
      if (subtitle.length > 0) {
        Text(subtitle)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 8, bottom: 10 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ActionChip(label: string, primary: boolean, onClick: () => void) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(primary ? Color.White : AppSettingsService.getInstance().getPrimaryColor())
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(primary ? AppSettingsService.getInstance().getPrimaryColor() : AppSettingsService.getInstance().getPrimaryColorWithAlpha(0.12))
    .borderRadius(16)
    .margin({ right: 8, top: 8 })
    .onClick(() => {
      onClick();
    })
  }

  @Builder
  private ServiceMetric(value: string, label: string) {
    Column() {
      Text(value.trim().length > 0 ? value : '--')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppSettingsService.getInstance().getPrimaryColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private DisabledServiceCard(
    serviceName: string,
    desc: string,
    iconSymbol: Resource,
    iconColor: string,
    backgroundColor: string,
    processing: boolean,
    errorMessage: string,
    onEnable: () => void
  ) {
    Column() {
      Row() {
        Row() {
          SymbolGlyph(iconSymbol)
            .fontSize(28)
            .fontColor([iconColor])
        }
        .width(64)
        .height(64)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(backgroundColor)
        .borderRadius(18)

        Column() {
          Text(serviceName)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
          Text(desc)
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 6 })
        }
        .layoutWeight(1)
        .margin({ left: 14 })

        if (processing) {
          LoadingProgress()
            .width(20)
            .height(20)
        } else {
          this.ActionChip('启用', true, onEnable)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (errorMessage.trim().length > 0) {
        Text(errorMessage)
          .fontSize(12)
          .fontColor($r('app.color.error'))
          .width('100%')
          .margin({ top: 12 })
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
  }

  @Builder
  private LdcEnabledCard() {
    Column() {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.archivebox'))
            .fontSize(26)
            .fontColor(['#8B5CF6'])
        }
        .width(56)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor('#F3E8FF')
        .borderRadius(18)

        Column() {
          Text('LINUX DO Credits')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
          Text(this.ldcInfo !== null ? `@${(this.ldcInfo as LdcUserInfo).username}` : '已启用，等待刷新余额')
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .margin({ left: 14 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.ldcInfo !== null) {
        Row() {
          this.ServiceMetric((this.ldcInfo as LdcUserInfo).availableBalance, '可用余额')
          this.ServiceMetric((this.ldcInfo as LdcUserInfo).communityBalance, '社区余额')
          this.ServiceMetric((this.ldcInfo as LdcUserInfo).remainQuota, '剩余额度')
        }
        .width('100%')
        .margin({ top: 16 })

        Row() {
          this.ServiceMetric((this.ldcInfo as LdcUserInfo).totalReceive, '总收入')
          this.ServiceMetric((this.ldcInfo as LdcUserInfo).totalPayment, '总支出')
          this.ServiceMetric(`${(this.ldcInfo as LdcUserInfo).payScore}`, '积分')
        }
        .width('100%')
        .margin({ top: 10 })
      }

      if (this.ldcErrorMessage.trim().length > 0) {
        Text(this.ldcErrorMessage)
          .fontSize(12)
          .fontColor($r('app.color.error'))
          .width('100%')
          .margin({ top: 12 })
      }

      Flex({ wrap: FlexWrap.Wrap }) {
        this.ActionChip(this.isLdcProcessing ? '处理中...' : '刷新', false, () => {
          this.refreshLdc().catch(() => {
          });
        })
        this.ActionChip('重授权', false, () => {
          this.startLdcAuthorization(true).catch(() => {
          });
        })
        this.ActionChip('主页', false, () => {
          ExternalLinkService.openPreferred('https://credit.linux.do/home', 'LINUX DO Credits').catch(() => {
          });
        })
        this.ActionChip('退出授权', false, () => {
          this.disableLdc().catch(() => {
          });
        })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
  }

  @Builder
  private CdkEnabledCard() {
    Column() {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.medal'))
            .fontSize(26)
            .fontColor(['#0EA5E9'])
        }
        .width(56)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor('#E0F2FE')
        .borderRadius(18)

        Column() {
          Text('LINUX DO CDK')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
          Text(this.cdkInfo !== null ? `@${(this.cdkInfo as CdkUserInfo).username}` : '已启用，等待刷新余额')
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .margin({ left: 14 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.cdkInfo !== null) {
        Row() {
          this.ServiceMetric(`${(this.cdkInfo as CdkUserInfo).score}`, '可用积分')
          this.ServiceMetric(`L${(this.cdkInfo as CdkUserInfo).trustLevel}`, '信任等级')
          this.ServiceMetric((this.cdkInfo as CdkUserInfo).nickname, '昵称')
        }
        .width('100%')
        .margin({ top: 16 })
      }

      if (this.cdkErrorMessage.trim().length > 0) {
        Text(this.cdkErrorMessage)
          .fontSize(12)
          .fontColor($r('app.color.error'))
          .width('100%')
          .margin({ top: 12 })
      }

      Flex({ wrap: FlexWrap.Wrap }) {
        this.ActionChip(this.isCdkProcessing ? '处理中...' : '刷新', false, () => {
          this.refreshCdk().catch(() => {
          });
        })
        this.ActionChip('重授权', false, () => {
          this.startCdkAuthorization(true).catch(() => {
          });
        })
        this.ActionChip('主页', false, () => {
          ExternalLinkService.openPreferred('https://cdk.linux.do', 'LINUX DO CDK').catch(() => {
          });
        })
        this.ActionChip('退出授权', false, () => {
          this.disableCdk().catch(() => {
          });
        })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
  }

  @Builder
  private RewardConfigCard() {
    Column() {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(24)
            .fontColor(['#EC4899'])
        }
        .width(52)
        .height(52)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor('#FCE7F3')
        .borderRadius(16)

        Column() {
          Text('LDC 打赏配置')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
          Text('保存商户凭证，后续帖子打赏链路可直接复用')
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .margin({ left: 14 })

        Row() {
          Text('配置')
            .fontSize(12)
            .fontColor(AppSettingsService.getInstance().getPrimaryColor())
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(AppSettingsService.getInstance().getPrimaryColorWithAlpha(0.12))
        .borderRadius(16)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.openRewardConfig().catch(() => {
        });
      })

      Text('也可以直接打开 Credits 商户页创建应用')
        .fontSize(12)
        .fontColor(AppSettingsService.getInstance().getPrimaryColor())
        .margin({ top: 14 })
        .onClick(() => {
          ExternalLinkService.openPreferred('https://credit.linux.do/merchant', 'LDC 商户中心').catch(() => {
          });
        })
    }
    .width('100%')
    .padding(18)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
  }

  @Builder
  private AuthConfirmSheetBuilder() {
    Column() {
      Text(this.pendingAuthContext !== null ? `确认接入 ${((this.pendingAuthContext as OAuthAuthorizationContext).serviceName)}` : '确认授权')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))

      Text('应用会使用当前 Linux.do 登录态完成 OAuth 确认，成功后自动刷新账户信息。')
        .fontSize(13)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ top: 10 })

      if (this.pendingAuthContext !== null) {
        Text((this.pendingAuthContext as OAuthAuthorizationContext).approveUrl)
          .fontSize(12)
          .fontColor(AppSettingsService.getInstance().getPrimaryColor())
          .margin({ top: 10 })
      }

      Row() {
        this.ActionChip('取消', false, () => {
          this.isAuthSheetVisible = false;
          this.pendingAuthContext = null;
        })
        this.ActionChip('继续授权', true, () => {
          this.confirmAuthorization().catch(() => {
          });
        })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 24 + WindowManager.getSystemAvoidAreaBottomVp() })
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private RewardSheetBuilder() {
    Column() {
      Text('LDC 打赏配置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))

      Text('填写 Credits 商户应用的 Client ID 与 Client Secret。')
        .fontSize(13)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ top: 8, bottom: 14 })

      TextInput({ text: this.rewardClientId, placeholder: 'Client ID' })
        .width('100%')
        .height(46)
        .padding({ left: 12, right: 12 })
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(14)
        .onChange((value: string) => {
          this.rewardClientId = value;
        })

      TextInput({ text: this.rewardClientSecret, placeholder: 'Client Secret' })
        .width('100%')
        .height(46)
        .padding({ left: 12, right: 12 })
        .margin({ top: 10 })
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(14)
        .onChange((value: string) => {
          this.rewardClientSecret = value;
        })

      Flex({ wrap: FlexWrap.Wrap }) {
        this.ActionChip('保存', true, () => {
          this.saveRewardConfig().catch(() => {
          });
        })
        this.ActionChip('清空', false, () => {
          this.clearRewardConfig().catch(() => {
          });
        })
        this.ActionChip('商户中心', false, () => {
          this.isRewardSheetVisible = false;
          ExternalLinkService.openPreferred('https://credit.linux.do/merchant', 'LDC 商户中心').catch(() => {
          });
        })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 24 + WindowManager.getSystemAvoidAreaBottomVp() })
    .backgroundColor($r('app.color.surface'))
  }

  build() {
    HdsNavDestination() {
      Column() {
        this.TopBar()

        if (this.isLoading) {
          Column() {
            LoadingProgress().width(24).height(24)
            Text('正在同步元宇宙服务状态...')
              .fontSize(13)
              .fontColor($r('app.color.on_surface_secondary'))
              .margin({ top: 10 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll() {
            Column() {
              this.SectionTitle('我的服务', '对齐 FluxDO 的 LDC / CDK 接入与授权确认链路')

              if (this.ldcEnabled) {
                this.LdcEnabledCard()
              } else {
                this.DisabledServiceCard(
                  'LINUX DO Credits',
                  '接入后可查看 Credits 余额、额度与收支数据',
                  $r('sys.symbol.archivebox'),
                  '#8B5CF6',
                  '#F3E8FF',
                  this.isLdcProcessing,
                  this.ldcErrorMessage,
                  () => {
                    this.startLdcAuthorization(false).catch(() => {
                    });
                  }
                )
              }

              Blank().height(12)

              if (this.cdkEnabled) {
                this.CdkEnabledCard()
              } else {
                this.DisabledServiceCard(
                  'LINUX DO CDK',
                  '接入后可查看 CDK 积分和账户基础信息',
                  $r('sys.symbol.medal'),
                  '#0EA5E9',
                  '#E0F2FE',
                  this.isCdkProcessing,
                  this.cdkErrorMessage,
                  () => {
                    this.startCdkAuthorization(false).catch(() => {
                    });
                  }
                )
              }

              if (this.ldcEnabled) {
                Blank().height(12)
                this.RewardConfigCard()
              }

              Blank().height(28)
              this.SectionTitle('更多', '当前只落地 hmApp 里已有真实消费链路的服务能力')
              Column() {
                SymbolGlyph($r('sys.symbol.house'))
                  .fontSize(28)
                  .fontColor([$r('app.color.on_surface_tertiary')])
                Text('更多元宇宙服务后续继续接入')
                  .fontSize(13)
                  .fontColor($r('app.color.on_surface_secondary'))
                  .margin({ top: 8 })
              }
              .width('100%')
              .padding({ top: 28, bottom: 28 })
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(20)

              Blank().height(24 + WindowManager.getSystemAvoidAreaBottomVp())
            }
            .width('100%')
            .padding({ left: 12, right: 12 })
          }
          .layoutWeight(1)
          .width('100%')
          .backgroundColor($r('app.color.background'))
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: WindowManager.getSystemAvoidAreaTopVp() })
      .backgroundColor($r('app.color.background'))
      .bindSheet($$this.isAuthSheetVisible, this.AuthConfirmSheetBuilder, {
        height: SheetSize.MEDIUM,
        showClose: false,
        dragBar: true,
        backgroundColor: $r('app.color.surface')
      })
      .bindSheet($$this.isRewardSheetVisible, this.RewardSheetBuilder, {
        height: SheetSize.MEDIUM,
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
