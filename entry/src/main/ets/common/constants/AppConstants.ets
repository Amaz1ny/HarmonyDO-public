/**
 * 应用常量定义
 */
export class AppConstants {
  /** linux.do 域名 */
  static readonly BASE_URL: string = 'https://linux.do';

  /**
   * Debug 开关：MessageBus/topic-tracking/incoming banner 相关日志
   * - true: 输出更多 hilog，便于真机抓日志定位“查看 X 个新的或更新的话题”是否实时更新
   * - false: 默认关闭，避免刷屏
   */
  static readonly DEBUG_TRACKING: boolean = true;

  /**
   * UI 复刻阶段：是否使用 Mock 数据（离线可展示 UI）
   * - true: ApiClient 直接返回本地构造数据，不发起网络请求
   * - false: 走真实网络（后续业务功能阶段）
   */
  static readonly USE_MOCK_DATA: boolean = false;

  /** API 前缀 */
  static readonly API_PREFIX: string = '';

  /** 默认每页大小 */
  static readonly DEFAULT_PAGE_SIZE: number = 30;

  /** 默认请求超时（毫秒） */
  static readonly REQUEST_TIMEOUT: number = 30000;

  /** 默认头像大小 */
  static readonly DEFAULT_AVATAR_SIZE: number = 120;

  /** 小头像大小 */
  static readonly SMALL_AVATAR_SIZE: number = 40;

  /** 应用名 */
  static readonly APP_NAME: string = 'HarmonyDO';

  /** User-Agent */
  static readonly USER_AGENT: string =
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
}
