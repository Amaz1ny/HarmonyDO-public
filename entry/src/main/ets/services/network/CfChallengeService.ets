import { hilog } from '@kit.PerformanceAnalysisKit';
import { RouterManager, RouteConstants } from '../../common/utils/RouterManager';
import { CookieStore } from './CookieStore';
import { CfClearanceRefreshService } from './CfClearanceRefreshService';

const TAG: string = 'CfChallengeService';
const COOLDOWN_MS: number = 30 * 1000;
const CLEARANCE_CONFIRM_DELAY_MS: number = 1500;
const CLEARANCE_CONFIRM_RETRY_COUNT: number = 3;
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

    out.isChallenge = out.hits.length > 0;
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
      if (ok) return true;
      await this.sleep(CLEARANCE_CONFIRM_RETRY_INTERVAL_MS);
      CookieStore.getInstance().syncFromWebView();
    }
    return false;
  }

  private isInCooldown(): boolean {
    return this.cooldownUntil > Date.now();
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
    if (this.isInCooldown()) {
      hilog.info(0x0000, TAG, 'Verify skipped: in cooldown');
      return Promise.resolve(false);
    }

    if (this.activePromise !== null) {
      return this.activePromise;
    }

    this.completed = false;
    this.activePromise = new Promise<boolean>((resolve) => {
      this.activeResolve = resolve;
    });

    // 记录验证开始时的 cf_clearance 快照（仅用于“旧值残留过滤”，严禁打印明文）
    this.initialCfClearanceSnapshot = CookieStore.getInstance().getCookieValue('cf_clearance');

    // 参考安卓端：进入验证前先清理旧 cf_clearance，避免 CF 直接放行导致“验证被跳过”
    CookieStore.getInstance().delete('cf_clearance');
    try {
      CfClearanceRefreshService.getInstance().stop();
    } catch (_) {
    }

    const stack: NavPathStack | null = RouterManager.getPathStack();
    if (stack === null) {
      hilog.error(0x0000, TAG, 'No NavPathStack, cannot show challenge page');
      this.complete(false);
      return this.activePromise;
    }

    RouterManager.pushPath(RouteConstants.PAGE_CF_CHALLENGE);
    return this.activePromise;
  }

  /**
   * 由验证页回调：完成本次验证
   */
  complete(success: boolean): void {
    if (this.completed) return;
    this.completed = true;

    if (success) {
      this.resetCooldown();
      try {
        CfClearanceRefreshService.getInstance().startIfPossible();
      } catch (_) {
      }
    } else {
      this.startCooldown();
    }

    this.verifyContext = null;
    this.initialCfClearanceSnapshot = null;

    if (this.activeResolve !== null) {
      this.activeResolve(success);
    }
    this.activeResolve = null;
    this.activePromise = null;
  }
}
