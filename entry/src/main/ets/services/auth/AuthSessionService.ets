import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'AuthSessionService';

/**
 * 认证会话代管理器
 *
 * 目标：
 * - 登录页进入 / 登录成功 / 退出登录等会话切换时推进 generation
 * - 让网络层能够识别“旧会话返回的响应”，避免旧请求把 cookie 再写回当前会话
 */
export class AuthSessionService {
  private static instance: AuthSessionService | null = null;

  private generation: number = 0;

  private constructor() {
  }

  static getInstance(): AuthSessionService {
    if (AuthSessionService.instance === null) {
      AuthSessionService.instance = new AuthSessionService();
    }
    return AuthSessionService.instance;
  }

  getGeneration(): number {
    return this.generation;
  }

  captureGeneration(): number {
    return this.generation;
  }

  isCurrentGeneration(generation: number): boolean {
    return generation === this.generation;
  }

  advance(reason: string): number {
    this.generation += 1;
    hilog.info(
      0x0000,
      TAG,
      'Advance auth session generation=%{public}d reason=%{public}s',
      this.generation,
      reason
    );
    return this.generation;
  }
}
