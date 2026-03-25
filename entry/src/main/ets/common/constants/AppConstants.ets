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
   * 调试构建下允许跳过远端 TLS/SSL 证书校验。
   *
   * 适用场景：
   * - 本地代理 / 抓包
   * - 域名被重定向到 192.168.x.x 等开发环境
   * - 本地测试证书未加入系统信任链
   *
   * 正式环境应优先使用受信任证书；这里只给调试构建做兜底，避免首页直接被 2300060 拦死。
   */
  static readonly ALLOW_INSECURE_PROXY_SSL_IN_DEBUG: boolean = true;

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
    'Mozilla/5.0 (Phone; OpenHarmony 6.1; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36  ArkWeb/6.1.0.100 Mobile HuaweiBrowser/6.1.1.341';
}
