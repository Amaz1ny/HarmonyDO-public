import { hilog } from '@kit.PerformanceAnalysisKit';
import { RouterManager, RouteConstants } from '../../common/utils/RouterManager';
import { CookieRecord, CookieStore } from './CookieStore';
import { CfClearanceRefreshService } from './CfClearanceRefreshService';

const TAG: string = 'CfChallengeService';
const COOLDOWN_MS: number = 30 * 1000;
const CLEARANCE_CONFIRM_DELAY_MS: number = 2000;
const CLEARANCE_CONFIRM_RETRY_COUNT: number = 5;
const CLEARANCE_CONFIRM_RETRY_INTERVAL_MS: number = 500;

export interface CfChallengeDetectResult {
  isChallenge: boolean;
  hits: string[];
}

export interface CfVerifyContext {
  urlPath: string;
  statusCode: number;
  isCfHeader: boolean;
  isCfBody: boolean;
  cfBodyHits: string[];
  hasCfClearance: boolean;
  cookieHeaderLength: number;
  silent: boolean;
  caller: string;
}

/**
 * Cloudflare 验证单例服务
 *
 * 目标：
 * - 403 检测到 CF challenge 时，只允许同时存在一个验证流程（单飞）
 * - 验证失败进入冷却期，避免短时间反复弹窗
 */
export class CfChallengeService {
  private static instance: CfChallengeService | null = null;
  private static activeClearanceConfirmPromise: Promise<boolean> | null = null;

  private activePromise: Promise<boolean> | null = null;
  private activeResolve: ((value: boolean) => void) | null = null;
  private cooldownUntil: number = 0;
  private completed: boolean = false;

  private verifyContext: CfVerifyContext | null = null;
  private initialCfClearanceSnapshot: string | null = null;
  private backupCfClearance: CookieRecord | null = null;
  private clearanceConfirmed: boolean = false;
  private overlayVisibilityListener: ((visible: boolean) => void) | null = null;

  private constructor() {
  }

  static getInstance(): CfChallengeService {
    if (CfChallengeService.instance === null) {
      CfChallengeService.instance = new CfChallengeService();
    }
    return CfChallengeService.instance;
  }

  static isCfChallenge(body: string): boolean {
    const detected: CfChallengeDetectResult = CfChallengeService.detectCfChallenge(body);
    return detected.isChallenge;
  }

  static hasActiveCfChallenge(body: string): boolean {
    const lower: string = body.toLowerCase();
    return lower.indexOf('cf-turnstile') >= 0
      || lower.indexOf('challenge-running') >= 0
      || lower.indexOf('challenge-stage') >= 0
      || lower.indexOf('cf_chl_opt') >= 0;
  }

  static detectCfChallenge(body: string): CfChallengeDetectResult {
    const out: CfChallengeDetectResult = { isChallenge: false, hits: [] };
    const lower: string = body.toLowerCase();

    if (lower.indexOf('just a moment') >= 0) {
      out.hits.push('just_a_moment');
    }
    if (lower.indexOf('cf_chl_opt') >= 0) {
      out.hits.push('cf_chl_opt');
    }
    if (lower.indexOf('challenge-platform') >= 0) {
      out.hits.push('challenge-platform');
    }

    // challenge-platform 单独出现不判定为 CF challenge（所有 CF 保护的页面都包含此脚本路径）
    // 必须配合 cf_chl_opt 或 just_a_moment 才可靠
    const strongHits: number = out.hits.length - (out.hits.indexOf('challenge-platform') >= 0 ? 1 : 0);
    out.isChallenge = strongHits > 0;
    return out;
  }

  setVerifyContextIfIdle(ctx: CfVerifyContext): void {
    if (this.activePromise !== null) return;
    this.verifyContext = ctx;
  }

  getVerifyContext(): CfVerifyContext | null {
    return this.verifyContext;
  }

  getInitialCfClearanceSnapshot(): string | null {
    return this.initialCfClearanceSnapshot;
  }

  setOverlayVisibilityListener(listener: ((visible: boolean) => void) | null): void {
    this.overlayVisibilityListener = listener;
  }

  async waitForCfClearanceReady(): Promise<boolean> {
    if (CfChallengeService.activeClearanceConfirmPromise !== null) {
      return await CfChallengeService.activeClearanceConfirmPromise;
    }

    CfChallengeService.activeClearanceConfirmPromise = this.waitForCfClearanceReadyInternal();
    try {
      return await CfChallengeService.activeClearanceConfirmPromise;
    } finally {
      CfChallengeService.activeClearanceConfirmPromise = null;
    }
  }

  enterCooldownNow(reason: string): void {
    hilog.warn(0x0000, TAG, 'Enter cooldown manually: %{public}s', reason);
    this.startCooldown();
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  private async waitForCfClearanceReadyInternal(): Promise<boolean> {
    try {
      await CookieStore.getInstance().init();
    } catch (_) {
    }

    CookieStore.getInstance().syncFromWebView();
    const immediateCf: string | null = CookieStore.getInstance().getCookieValue('cf_clearance');
    if (immediateCf !== null && immediateCf.length > 0) {
      this.clearanceConfirmed = true;
      this.backupCfClearance = null;
      hilog.info(0x0000, TAG, 'Confirm cf_clearance immediate ok=Y len=%{public}d', immediateCf.length);
      return true;
    }

    await this.sleep(CLEARANCE_CONFIRM_DELAY_MS);
    CookieStore.getInstance().syncFromWebView();

    for (let i = 0; i < CLEARANCE_CONFIRM_RETRY_COUNT; i++) {
      const cf: string | null = CookieStore.getInstance().getCookieValue('cf_clearance');
      const ok: boolean = cf !== null && cf.length > 0;
      hilog.info(
        0x0000,
        TAG,
        'Confirm cf_clearance attempt=%{public}d/%{public}d ok=%{public}s len=%{public}d',
        i + 1,
        CLEARANCE_CONFIRM_RETRY_COUNT,
        ok ? 'Y' : 'N',
        ok ? (cf as string).length : 0
      );
      if (ok) {
        this.clearanceConfirmed = true;
        this.backupCfClearance = null;
        return true;
      }
      await this.sleep(CLEARANCE_CONFIRM_RETRY_INTERVAL_MS);
      CookieStore.getInstance().syncFromWebView();
    }
    this.restoreBackupCfClearance('cf_clearance_confirm_timeout');
    return false;
  }

  private restoreBackupCfClearance(reason: string): void {
    if (this.backupCfClearance === null) {
      return;
    }

    CookieStore.getInstance().restoreCookieRecord(this.backupCfClearance);
    CookieStore.getInstance().syncToWebView();
    this.backupCfClearance = null;
    this.clearanceConfirmed = false;
    try {
      CfClearanceRefreshService.getInstance().stop();
    } catch (_) {
    }
    hilog.warn(0x0000, TAG, 'Restored previous cf_clearance, reason=%{public}s', reason);
  }

  private isInCooldown(): boolean {
    return this.cooldownUntil > Date.now();
  }

  private getCooldownRemainingMs(): number {
    const remainingMs: number = this.cooldownUntil - Date.now();
    return remainingMs > 0 ? remainingMs : 0;
  }

  private startCooldown(): void {
    this.cooldownUntil = Date.now() + COOLDOWN_MS;
    hilog.info(0x0000, TAG, 'Enter cooldown, until=%{public}d', this.cooldownUntil);
  }

  private resetCooldown(): void {
    this.cooldownUntil = 0;
  }

  /**
   * 启动验证流程（如果已有验证在进行，复用同一个 Promise）
   */
  verify(): Promise<boolean> {
    const ctx: CfVerifyContext | null = this.verifyContext;
    if (this.isInCooldown()) {
      const remainingMs: number = this.getCooldownRemainingMs();
      const canBypassCooldown: boolean = ctx !== null && !ctx.silent;
      if (!canBypassCooldown) {
        const caller: string = ctx !== null ? ctx.caller : '-';
        hilog.info(
          0x0000,
          TAG,
          'Verify skipped: in cooldown remaining=%{public}d caller=%{public}s',
          remainingMs,
          caller
        );
        return Promise.resolve(false);
      }
      const caller: string = ctx !== null ? ctx.caller : '-';
      const urlPath: string = ctx !== null ? ctx.urlPath : '-';
      hilog.warn(
        0x0000,
        TAG,
        'Verify cooldown bypassed for interactive request remaining=%{public}d caller=%{public}s path=%{public}s',
        remainingMs,
        caller,
        urlPath
      );
      this.resetCooldown();
    }

    if (this.activePromise !== null) {
      return this.activePromise;
    }

    this.completed = false;
    this.clearanceConfirmed = false;
    this.activePromise = new Promise<boolean>((resolve) => {
      this.activeResolve = resolve;
    });

    // 记录验证开始时的 cf_clearance 快照（仅用于“旧值残留过滤”，严禁打印明文）
    this.initialCfClearanceSnapshot = CookieStore.getInstance().getCookieValue('cf_clearance');
    this.backupCfClearance = CookieStore.getInstance().getCookieRecord('cf_clearance');

    // 进入验证前先清理旧 cf_clearance，避免 CF 直接放行导致“验证被跳过”
    CookieStore.getInstance().delete('cf_clearance');
    try {
      CfClearanceRefreshService.getInstance().stop();
    } catch (_) {
    }

    if (this.overlayVisibilityListener !== null) {
      hilog.info(0x0000, TAG, 'Show challenge overlay');
      this.overlayVisibilityListener(true);
    } else {
      const stack: NavPathStack | null = RouterManager.getPathStack();
      if (stack === null) {
        hilog.error(0x0000, TAG, 'No NavPathStack/overlay listener, cannot show challenge page');
        this.complete(false);
        return this.activePromise;
      }

      RouterManager.pushPath(RouteConstants.PAGE_CF_CHALLENGE);
    }
    return this.activePromise;
  }

  /**
   * 由验证页回调：完成本次验证
   */
  complete(success: boolean): void {
    if (this.completed) return;
    this.completed = true;

    if (this.overlayVisibilityListener !== null) {
      this.overlayVisibilityListener(false);
    }

    if (success) {
      this.resetCooldown();
      try {
        CfClearanceRefreshService.getInstance().startIfPossible();
      } catch (_) {
      }
    } else {
      this.restoreBackupCfClearance('verify_failed_or_cancelled');
      this.startCooldown();
    }

    this.verifyContext = null;
    this.initialCfClearanceSnapshot = null;
    if (!success || this.clearanceConfirmed) {
      this.backupCfClearance = null;
    }

    if (this.activeResolve !== null) {
      this.activeResolve(success);
    }
    this.activeResolve = null;
    this.activePromise = null;
  }
}
