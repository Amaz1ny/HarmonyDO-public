import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Context } from '@kit.AbilityKit';

const TAG: string = 'PreferencesUtil';

/**
 * Preferences 偏好存储工具类
 */
export class PreferencesUtil {
  private static preferencesInstance: preferences.Preferences | null = null;
  private static readonly STORE_NAME: string = 'fluxdo_preferences';
  private static initPromise: Promise<void> | null = null;

  /**
   * 初始化 Preferences（在 EntryAbility 中调用）
   */
  static init(context: Context): Promise<void> {
    if (PreferencesUtil.initPromise !== null) {
      return PreferencesUtil.initPromise;
    }

    PreferencesUtil.initPromise = (async () => {
      try {
        PreferencesUtil.preferencesInstance = await preferences.getPreferences(context, PreferencesUtil.STORE_NAME);
        hilog.info(0x0000, TAG, 'Preferences initialized');
      } catch (err) {
        hilog.error(0x0000, TAG, 'Failed to init Preferences: %{public}s', JSON.stringify(err));
      }
    })();

    return PreferencesUtil.initPromise;
  }

  /**
   * 等待 Preferences 初始化完成（用于解决初始化竞态：EntryAbility 调 init 未 await）
   */
  static async ensureInit(): Promise<void> {
    if (PreferencesUtil.initPromise !== null) {
      await PreferencesUtil.initPromise;
    }
  }

  /**
   * 获取字符串值
   */
  static async getString(key: string, defaultValue: string = ''): Promise<string> {
    if (PreferencesUtil.preferencesInstance === null) {
      return defaultValue;
    }
    try {
      const value = await PreferencesUtil.preferencesInstance.get(key, defaultValue);
      return value as string;
    } catch (err) {
      hilog.error(0x0000, TAG, 'getString failed: %{public}s', JSON.stringify(err));
      return defaultValue;
    }
  }

  /**
   * 保存字符串值
   */
  static async putString(key: string, value: string): Promise<void> {
    if (PreferencesUtil.preferencesInstance === null) {
      return;
    }
    try {
      await PreferencesUtil.preferencesInstance.put(key, value);
      await PreferencesUtil.preferencesInstance.flush();
    } catch (err) {
      hilog.error(0x0000, TAG, 'putString failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 获取数字值
   */
  static async getNumber(key: string, defaultValue: number = 0): Promise<number> {
    if (PreferencesUtil.preferencesInstance === null) {
      return defaultValue;
    }
    try {
      const value = await PreferencesUtil.preferencesInstance.get(key, defaultValue);
      return value as number;
    } catch (err) {
      hilog.error(0x0000, TAG, 'getNumber failed: %{public}s', JSON.stringify(err));
      return defaultValue;
    }
  }

  /**
   * 保存数字值
   */
  static async putNumber(key: string, value: number): Promise<void> {
    if (PreferencesUtil.preferencesInstance === null) {
      return;
    }
    try {
      await PreferencesUtil.preferencesInstance.put(key, value);
      await PreferencesUtil.preferencesInstance.flush();
    } catch (err) {
      hilog.error(0x0000, TAG, 'putNumber failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 获取布尔值
   */
  static async getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    if (PreferencesUtil.preferencesInstance === null) {
      return defaultValue;
    }
    try {
      const value = await PreferencesUtil.preferencesInstance.get(key, defaultValue);
      return value as boolean;
    } catch (err) {
      hilog.error(0x0000, TAG, 'getBoolean failed: %{public}s', JSON.stringify(err));
      return defaultValue;
    }
  }

  /**
   * 保存布尔值
   */
  static async putBoolean(key: string, value: boolean): Promise<void> {
    if (PreferencesUtil.preferencesInstance === null) {
      return;
    }
    try {
      await PreferencesUtil.preferencesInstance.put(key, value);
      await PreferencesUtil.preferencesInstance.flush();
    } catch (err) {
      hilog.error(0x0000, TAG, 'putBoolean failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 删除指定 key
   */
  static async delete(key: string): Promise<void> {
    if (PreferencesUtil.preferencesInstance === null) {
      return;
    }
    try {
      await PreferencesUtil.preferencesInstance.delete(key);
      await PreferencesUtil.preferencesInstance.flush();
    } catch (err) {
      hilog.error(0x0000, TAG, 'delete failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 是否包含某个 key
   */
  static async has(key: string): Promise<boolean> {
    if (PreferencesUtil.preferencesInstance === null) {
      return false;
    }
    try {
      return await PreferencesUtil.preferencesInstance.has(key);
    } catch (err) {
      hilog.error(0x0000, TAG, 'has failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }
}
