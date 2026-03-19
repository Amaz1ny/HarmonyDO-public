/**
 * 时间工具类 - 统一处理时间格式化和时区转换
 */
export class TimeUtils {
  /**
   * 解析 UTC 时间字符串并转换为本地时间
   * Discourse API 返回的时间是 UTC 格式
   */
  static parseUtcTime(timeString: string | null): Date | null {
    if (timeString === null || timeString.length === 0) {
      return null;
    }
    try {
      const timestamp: number = Date.parse(timeString);
      if (isNaN(timestamp)) {
        return null;
      }
      return new Date(timestamp);
    } catch (e) {
      return null;
    }
  }

  /**
   * 格式化时间为相对时间（刚刚、X分钟前、X小时前等）
   */
  static formatRelativeTime(time: Date | null, tick: number = 0): string {
    if (time === null) {
      return '';
    }

    const nowMs: number = tick > 0 ? tick : Date.now();
    let diffMs: number = nowMs - time.getTime();
    if (diffMs < 0) diffMs = 0;
    const diffSeconds: number = Math.floor(diffMs / 1000);
    const diffMinutes: number = Math.floor(diffSeconds / 60);
    const diffHours: number = Math.floor(diffMinutes / 60);
    const diffDays: number = Math.floor(diffHours / 24);

    if (diffSeconds < 60) {
      return '刚刚';
    }
    if (diffMinutes < 60) {
      return `${diffMinutes}分钟前`;
    }
    if (diffHours < 24) {
      return `${diffHours}小时前`;
    }
    if (diffDays < 7) {
      return `${diffDays}天前`;
    }
    if (diffDays < 30) {
      return `${Math.floor(diffDays / 7)}周前`;
    }
    if (diffDays < 365) {
      return `${Math.floor(diffDays / 30)}个月前`;
    }
    return `${Math.floor(diffDays / 365)}年前`;
  }

  /**
   * 格式化时间为详细时间字符串
   * 格式：2024-01-15 14:30
   */
  static formatDetailTime(time: Date | null): string {
    if (time === null) {
      return '';
    }
    const year: number = time.getFullYear();
    const month: string = TimeUtils.padZero(time.getMonth() + 1);
    const day: string = TimeUtils.padZero(time.getDate());
    const hour: string = TimeUtils.padZero(time.getHours());
    const minute: string = TimeUtils.padZero(time.getMinutes());
    return `${year}-${month}-${day} ${hour}:${minute}`;
  }

  /**
   * 格式化时间为短日期
   * 格式：1月15日
   */
  static formatShortDate(time: Date | null): string {
    if (time === null) {
      return '';
    }
    return `${time.getMonth() + 1}月${time.getDate()}日`;
  }

  /**
   * 格式化时间为智能日期标签
   */
  static formatSmartDate(time: Date | null): string {
    if (time === null) {
      return '';
    }
    const now: Date = new Date();
    const today: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const date: Date = new Date(time.getFullYear(), time.getMonth(), time.getDate());
    const todayTime: number = today.getTime();
    const dateTime: number = date.getTime();

    if (dateTime === todayTime) {
      return '今天';
    }
    if (dateTime === todayTime - 86400000) {
      return '昨天';
    }
    if (time.getFullYear() === now.getFullYear()) {
      return `${time.getMonth() + 1}月${time.getDate()}日`;
    }
    return `${time.getFullYear()}年${time.getMonth() + 1}月${time.getDate()}日`;
  }

  /**
   * 数字补零
   */
  private static padZero(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }
}
