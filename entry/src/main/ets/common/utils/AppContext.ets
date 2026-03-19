import { common } from '@kit.AbilityKit';

/**
 * 全局 UIAbilityContext 持有者
 *
 * 说明：
 * - 用于在页面/服务层调用系统能力（分享、打开浏览器等）
 * - 由 EntryAbility 初始化写入
 */
export class AppContext {
  private static uiAbilityContext: common.UIAbilityContext | null = null;

  static setUIAbilityContext(ctx: common.UIAbilityContext): void {
    AppContext.uiAbilityContext = ctx;
  }

  static getUIAbilityContext(): common.UIAbilityContext | null {
    return AppContext.uiAbilityContext;
  }
}

