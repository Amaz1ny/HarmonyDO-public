import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { PreloadedDataService } from './PreloadedDataService';
import { MessageBusMessage, MessageBusService } from './MessageBusService';

const TAG: string = 'TopicTrackingService';

class TrackedTopicState {
  topicId: number = 0;
  lastReadPostNumber: number | null = null; // null=NEW
  highestPostNumber: number = 1;
  categoryId: number | null = null;
  notificationLevel: number = 1; // 0=MUTED,1=REGULAR,2=TRACKING,3=WATCHING
  createdInNewPeriod: boolean = false;
  isSeen: boolean = false;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): TrackedTopicState {
    const s: TrackedTopicState = new TrackedTopicState();
    const idVal = json['topic_id'];
    s.topicId = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;

    const lastVal = json['last_read_post_number'];
    if (lastVal !== undefined && lastVal !== null) {
      const n: number = Number(lastVal.toString());
      s.lastReadPostNumber = isNaN(n) ? null : n;
    } else {
      s.lastReadPostNumber = null;
    }

    const highestVal = json['highest_post_number'];
    s.highestPostNumber = highestVal !== undefined && highestVal !== null ? Number(highestVal.toString()) : 1;

    const catVal = json['category_id'];
    if (catVal !== undefined && catVal !== null) {
      const c: number = Number(catVal.toString());
      s.categoryId = isNaN(c) ? null : c;
    }

    const levelVal = json['notification_level'];
    s.notificationLevel = levelVal !== undefined && levelVal !== null ? Number(levelVal.toString()) : 1;

    const createdVal = json['created_in_new_period'];
    if (createdVal !== undefined && createdVal !== null) {
      s.createdInNewPeriod = createdVal.toString() === 'true';
    } else {
      // 预加载数据可能不含该字段：未读过视为新期限内
      s.createdInNewPeriod = s.lastReadPostNumber === null;
    }

    const seenVal = json['is_seen'];
    s.isSeen = seenVal !== undefined && seenVal !== null ? seenVal.toString() === 'true' : false;
    return s;
  }
}

/**
 * 话题追踪状态（对齐 FluxDO / Discourse topic-tracking-state）
 *
 * - 统计 NEW / UNREAD 计数（用于“新话题(x)/未读完(x)”）
 * - 监听 /latest /new 频道，生成 incoming topic ids（用于“查看 X 个新的或更新的话题”）
 */
export class TopicTrackingService {
  private static instance: TopicTrackingService | null = null;

  private started: boolean = false;
  private fullStarted: boolean = false;
  private startInFlight: Promise<void> | null = null;
  private guestWarmupInFlight: Promise<void> | null = null;
  private warmupRetryTimerId: number = -1;
  private warmupRetryAttempt: number = 0;

  private states: Map<number, TrackedTopicState> = new Map();
  private incomingTopics: Map<number, number> = new Map(); // topicId -> categoryId(0 = unknown)
  private incomingHighestPostNumbers: Map<number, number> = new Map(); // topicId -> highest_post_number（用于实时更新回复数）
  private listeners: (() => void)[] = [];
  private notifyScheduled: boolean = false;

  private channelCallbacks: Map<string, (message: MessageBusMessage) => void> = new Map();

  private constructor() {
  }

  static getInstance(): TopicTrackingService {
    if (TopicTrackingService.instance === null) {
      TopicTrackingService.instance = new TopicTrackingService();
    }
    return TopicTrackingService.instance;
  }

  isStarted(): boolean {
    return this.started;
  }

  isBusReady(): boolean {
    try {
      return MessageBusService.getInstance().hasEverSucceeded();
    } catch (_) {
    }
    return false;
  }

  /**
   * 启动 topic-tracking：
   * - full=false：仅订阅 /latest + /new，用于“查看 X 个新的或更新的话题”（游客态即可）
   * - full=true ：额外加载 preloaded + 订阅 topicTrackingStateMeta，用于 new/unread 计数（登录态）
   */
  async start(full: boolean = true): Promise<void> {
    if (this.started && (!full || this.fullStarted)) return;
    if (this.startInFlight !== null) {
      return await this.startInFlight;
    }
    this.startInFlight = this.startInternal(full);
    try {
      await this.startInFlight;
    } finally {
      this.startInFlight = null;
    }
  }

  stop(): void {
    if (!this.started) return;
    if (this.warmupRetryTimerId >= 0) {
      clearTimeout(this.warmupRetryTimerId);
      this.warmupRetryTimerId = -1;
    }
    this.warmupRetryAttempt = 0;
    const bus: MessageBusService = MessageBusService.getInstance();
    const channels: string[] = [];
    this.channelCallbacks.forEach((_: (message: MessageBusMessage) => void, ch: string) => {
      channels.push(ch);
    });
    for (let i = 0; i < channels.length; i++) {
      const ch: string = channels[i];
      const cb = this.channelCallbacks.get(ch);
      if (cb !== undefined && cb !== null) {
        bus.unsubscribe(ch, cb);
      }
    }
    this.channelCallbacks.clear();
    this.started = false;
    this.fullStarted = false;
    this.states = new Map();
    this.incomingTopics = new Map();
    this.incomingHighestPostNumbers = new Map();
    this.notify();
  }

  addListener(listener: () => void): void {
    this.listeners.push(listener);
  }

  removeListener(listener: () => void): void {
    const next: (() => void)[] = [];
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] !== listener) next.push(this.listeners[i]);
    }
    this.listeners = next;
  }

  countNew(categoryId: number | null = null): number {
    let count: number = 0;
    this.states.forEach((s: TrackedTopicState) => {
      if (categoryId !== null && s.categoryId !== categoryId) return;
      if (this.isNew(s)) count = count + 1;
    });
    return count;
  }

  countUnread(categoryId: number | null = null): number {
    let count: number = 0;
    this.states.forEach((s: TrackedTopicState) => {
      if (categoryId !== null && s.categoryId !== categoryId) return;
      if (this.isUnread(s)) count = count + 1;
    });
    return count;
  }

  incomingCount(categoryId: number | null = null): number {
    if (categoryId === null) return this.incomingTopics.size;
    let count: number = 0;
    this.incomingTopics.forEach((c: number) => {
      if (c === categoryId) count = count + 1;
    });
    return count;
  }

  incomingTopicIds(categoryId: number | null = null): number[] {
    const ids: number[] = [];
    if (categoryId === null) {
      this.incomingTopics.forEach((_: number, id: number) => {
        ids.push(id);
      });
      return ids;
    }
    this.incomingTopics.forEach((c: number, id: number) => {
      if (c === categoryId) ids.push(id);
    });
    return ids;
  }

  /**
   * 获取某个话题最新的 highest_post_number（优先 tracking state，其次 /latest payload）
   * 用于列表页“回复数”在 MessageBus 更新时即时对齐安卓。
   */
  getHighestPostNumber(topicId: number): number {
    if (topicId <= 0) return 0;
    let highest: number = 0;
    if (this.states.has(topicId)) {
      const s: TrackedTopicState = this.states.get(topicId) as TrackedTopicState;
      highest = s.highestPostNumber;
    }
    if (this.incomingHighestPostNumbers.has(topicId)) {
      const v: number = this.incomingHighestPostNumbers.get(topicId) as number;
      if (!isNaN(v) && v > highest) {
        highest = v;
      }
    }
    return highest;
  }

  clearIncoming(categoryId: number | null = null): void {
    if (categoryId === null) {
      const removed: number = this.incomingTopics.size;
      if (removed > 0) {
        this.incomingTopics.clear();
        this.incomingHighestPostNumbers.clear();
        if (AppConstants.DEBUG_TRACKING) {
          hilog.info(0x0000, TAG, 'clearIncoming(all) removed=%{public}d', removed);
        }
        this.notify();
      }
      return;
    }

    const toRemove: number[] = [];
    this.incomingTopics.forEach((c: number, id: number) => {
      if (c === categoryId) toRemove.push(id);
    });
    if (toRemove.length === 0) return;
    for (let i = 0; i < toRemove.length; i++) {
      const id: number = toRemove[i];
      this.incomingTopics.delete(id);
      if (this.incomingHighestPostNumbers.has(id)) {
        this.incomingHighestPostNumbers.delete(id);
      }
    }
    if (AppConstants.DEBUG_TRACKING) {
      hilog.info(0x0000, TAG, 'clearIncoming(category=%{public}d) removed=%{public}d', categoryId, toRemove.length);
    }
    this.notify();
  }

  private notify(): void {
    // 合并同一批次内的多次 notify，避免一轮 MessageBus 响应里
    // 连续触发多次 UI 刷新造成“卡顿/不实时”的体感。
    if (this.notifyScheduled) return;
    this.notifyScheduled = true;
    setTimeout(() => {
      this.notifyScheduled = false;
      for (let i = 0; i < this.listeners.length; i++) {
        try {
          this.listeners[i]();
        } catch (_) {
        }
      }
    }, 0);
  }

  private isNew(s: TrackedTopicState): boolean {
    return s.lastReadPostNumber === null
      && s.createdInNewPeriod
      && ((s.notificationLevel !== 0 && !s.isSeen) || s.notificationLevel >= 2);
  }

  private isUnread(s: TrackedTopicState): boolean {
    return s.lastReadPostNumber !== null
      && (s.lastReadPostNumber as number) < s.highestPostNumber
      && s.notificationLevel >= 2;
  }

  private async startInternal(full: boolean): Promise<void> {
    // 1) 先把 incoming 通道拉起来（不依赖 preloaded，避免游客态等待 HTML 解析导致“新话题提示很慢”）
    this.ensureIncomingChannelsSubscribed(null);
    this.started = true;
    this.notify();

    if (!full) {
      // 游客态同样尝试后台加载 preloaded：获取 shared_session_key / long_polling_base_url，提高 MessageBus 成功率
      this.warmupBusConfiguration();
      return;
    }

    // 2) 登录态：加载 preloaded，补齐 tracking states/meta，用于 new/unread 计数
    const preloaded: PreloadedDataService = PreloadedDataService.getInstance();
    try {
      // tracking 属于后台能力：遇到 CF challenge 也不应打断前台
      await preloaded.ensureLoaded(true);
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Preloaded ensureLoaded failed(silent): %{public}s', JSON.stringify(err));
      return;
    }

    // init states
    this.states = new Map();
    const rawStates = preloaded.getTopicTrackingStates();
    if (rawStates !== null) {
      for (let i = 0; i < rawStates.length; i++) {
        const s: TrackedTopicState = TrackedTopicState.fromJson(rawStates[i]);
        if (s.topicId > 0) {
          this.states.set(s.topicId, s);
        }
      }
    }

    const bus: MessageBusService = MessageBusService.getInstance();
    bus.configure(preloaded.getLongPollingBaseUrl(), preloaded.getSharedSessionKey());

    const meta: Map<string, number> | null = preloaded.getTopicTrackingStateMeta();
    if (meta !== null) {
      const keys: string[] = [];
      meta.forEach((_: number, ch: string) => {
        keys.push(ch);
      });
      for (let i = 0; i < keys.length; i++) {
        const channel: string = keys[i];
        const messageId: number = meta.get(channel) as number;
        const cb = (message: MessageBusMessage) => {
          this.processChannelPayload(message);
        };
        this.channelCallbacks.set(channel, cb);
        bus.subscribeWithMessageId(channel, cb, messageId);
      }
      hilog.info(0x0000, TAG, 'Subscribed channels=%{public}d', keys.length);
    } else {
      hilog.warn(0x0000, TAG, 'topicTrackingStateMeta missing');
    }

    // 对齐 FluxDO：无论 meta 是否存在，都额外订阅 /latest 与 /new 以实时驱动“查看 X 个新的或更新的话题”
    this.ensureIncomingChannelsSubscribed(meta);

    this.fullStarted = true;
    this.notify();
  }

  private warmupBusConfiguration(): void {
    if (this.fullStarted) return;
    if (this.guestWarmupInFlight !== null) return;

    const preloaded: PreloadedDataService = PreloadedDataService.getInstance();
    if (preloaded.isLoaded()) {
      this.warmupRetryAttempt = 0;
      try {
        const bus: MessageBusService = MessageBusService.getInstance();
        bus.configure(preloaded.getLongPollingBaseUrl(), preloaded.getSharedSessionKey());
        this.ensureIncomingChannelsSubscribed(preloaded.getTopicTrackingStateMeta());
      } catch (_) {
      }
      return;
    }

    this.guestWarmupInFlight = preloaded.ensureConfigLoaded(true)
      .then(() => {
        this.warmupRetryAttempt = 0;
        this.ensureIncomingChannelsSubscribed(preloaded.getTopicTrackingStateMeta());
      })
      .catch((err: Object) => {
        let errText: string = '';
        try {
          errText = err !== null && err !== undefined ? err.toString() : JSON.stringify(err);
        } catch (_) {
        }
        hilog.warn(0x0000, TAG, 'Warmup preloaded failed: %{public}s', errText);
        // CF challenge / 网络失败时定时重试，避免 baseUrl 永远为 null 导致 MessageBus 404
        if (this.warmupRetryTimerId < 0 && !this.fullStarted) {
          const isSilentCfChallenge: boolean = errText.indexOf('CF_CHALLENGE_SILENT') >= 0;
          let retryDelayMs: number = 30000;
          if (isSilentCfChallenge) {
            // 静默 CF challenge 往往需要等待自动续期刷新 cf_clearance：
            // 采用短间隔指数退避（上限 30s），尽快拿到 long_polling_base_url / shared_session_key
            retryDelayMs = Math.min(5000 * Math.pow(2, this.warmupRetryAttempt), 30000);
            this.warmupRetryAttempt = Math.min(this.warmupRetryAttempt + 1, 3);
          } else {
            this.warmupRetryAttempt = 0;
          }
          this.warmupRetryTimerId = setTimeout(() => {
            this.warmupRetryTimerId = -1;
            this.warmupBusConfiguration();
          }, retryDelayMs);
        }
      })
      .finally(() => {
        this.guestWarmupInFlight = null;
      });
  }

  private ensureIncomingChannelsSubscribed(meta: Map<string, number> | null): void {
    const bus: MessageBusService = MessageBusService.getInstance();
    const channels: string[] = ['/latest', '/new'];
    for (let i = 0; i < channels.length; i++) {
      const ch: string = channels[i];
      if (this.channelCallbacks.has(ch)) {
        if (meta !== null && meta.has(ch)) {
          const v: number = meta.get(ch) as number;
          if (!isNaN(v)) {
            bus.updateLastMessageId(ch, v);
          }
        }
        continue;
      }

      let messageId: number = -1;
      if (meta !== null && meta.has(ch)) {
        const v: number = meta.get(ch) as number;
        if (!isNaN(v)) {
          messageId = v;
        }
      }

      const cb = (message: MessageBusMessage) => {
        this.processChannelPayload(message);
      };
      this.channelCallbacks.set(ch, cb);
      bus.subscribeWithMessageId(ch, cb, messageId);
    }
  }

  private addIncoming(topicId: number, categoryId: number | null, highestPostNumber: number | null = null): void {
    if (highestPostNumber !== null && highestPostNumber > 0 && !isNaN(highestPostNumber)) {
      const existing: number = this.incomingHighestPostNumbers.has(topicId)
        ? (this.incomingHighestPostNumbers.get(topicId) as number)
        : 0;
      if (existing <= 0 || highestPostNumber > existing) {
        this.incomingHighestPostNumbers.set(topicId, highestPostNumber);
      }
    }

    if (this.incomingTopics.has(topicId)) return;
    this.incomingTopics.set(topicId, categoryId !== null ? categoryId : 0);
    if (AppConstants.DEBUG_TRACKING) {
      hilog.info(
        0x0000,
        TAG,
        'incoming +1 topicId=%{public}d categoryId=%{public}d size=%{public}d',
        topicId,
        categoryId !== null ? (categoryId as number) : 0,
        this.incomingTopics.size
      );
    }
  }

  private processChannelPayload(message: MessageBusMessage): void {
    const dataObj: Object | null = message.data;
    if (dataObj === null || dataObj === undefined || typeof dataObj !== 'object') return;
    const data: Record<string, Object> = dataObj as Record<string, Object>;

    const typeVal = data['message_type'];
    const messageType: string = typeVal !== undefined && typeVal !== null ? typeVal.toString() : '';
    const topicIdVal = data['topic_id'];
    let topicId: number = topicIdVal !== undefined && topicIdVal !== null ? Number(topicIdVal.toString()) : 0;
    if (isNaN(topicId)) topicId = 0;

    const payloadVal = data['payload'];
    const payload: Record<string, Object> = payloadVal !== undefined && payloadVal !== null && typeof payloadVal === 'object'
      ? payloadVal as Record<string, Object>
      : {};

    const incomingCatVal = payload['category_id'];
    let incomingCategoryId: number | null = null;
    if (incomingCatVal !== undefined && incomingCatVal !== null) {
      const parsed = Number(incomingCatVal.toString());
      incomingCategoryId = isNaN(parsed) ? null : parsed;
    }

    // 对齐 Flutter LatestChannelNotifier：仅处理 latest/new_topic 两种消息类型
    // 直接从 data['topic_id'] 取 ID，从 payload['category_id'] 取分类，去重后 notify
    if (messageType === 'latest' || messageType === 'new_topic') {
      if (topicId > 0) {
        const highestVal = payload['highest_post_number'] !== undefined && payload['highest_post_number'] !== null
          ? payload['highest_post_number']
          : payload['posts_count'];
        let highest: number | null = null;
        if (highestVal !== undefined && highestVal !== null) {
          const parsed: number = Number(highestVal.toString());
          highest = isNaN(parsed) ? null : parsed;
        }
        this.addIncoming(topicId, incomingCategoryId, highest);
      }
      this.notify();
      return;
    }

    if (messageType === 'dismiss_new') {
      this.handleDismissNew(data);
      this.notify();
      return;
    }
    if (messageType === 'dismiss_new_posts') {
      this.handleDismissNewPosts(data);
      this.notify();
      return;
    }

    if (messageType !== 'unread' && messageType !== 'read') {
      return;
    }
    if (topicId <= 0) {
      const payloadTopicIdVal = payload['topic_id'];
      if (payloadTopicIdVal === undefined || payloadTopicIdVal === null) return;
      const parsed = Number(payloadTopicIdVal.toString());
      if (isNaN(parsed) || parsed <= 0) return;
      topicId = parsed;
    }

    const existing: TrackedTopicState | null = this.states.has(topicId) ? (this.states.get(topicId) as TrackedTopicState) : null;

    const highestVal = payload['highest_post_number'];
    const highest: number = highestVal !== undefined && highestVal !== null
      ? Number(highestVal.toString())
      : (existing !== null ? existing.highestPostNumber : 1);

    const lastReadVal = payload['last_read_post_number'];
    let lastRead: number | null = lastReadVal !== undefined && lastReadVal !== null ? Number(lastReadVal.toString()) : null;

    const levelVal = payload['notification_level'];
    let level: number | null = levelVal !== undefined && levelVal !== null ? Number(levelVal.toString()) : null;

    if (messageType === 'unread') {
      // /unread 频道的 payload 可能缺少 last_read_post_number / notification_level
      if (lastRead === null || isNaN(lastRead)) {
        lastRead = existing !== null && existing.lastReadPostNumber !== null
          ? (existing.lastReadPostNumber as number)
          : Math.max(0, highest - 1);
      }
      if (level === null || isNaN(level)) {
        level = existing !== null ? existing.notificationLevel : 2;
      }
    } else {
      if (lastRead === null || isNaN(lastRead)) {
        lastRead = existing !== null ? existing.lastReadPostNumber : null;
      }
      if (level === null || isNaN(level)) {
        level = existing !== null ? existing.notificationLevel : 1;
      }
    }

    const catVal = payload['category_id'];
    let catId: number | null = null;
    if (catVal !== undefined && catVal !== null) {
      const parsed = Number(catVal.toString());
      catId = isNaN(parsed) ? null : parsed;
    } else {
      catId = existing !== null ? existing.categoryId : null;
    }

    const createdVal = payload['created_in_new_period'];
    let createdInNewPeriod: boolean = false;
    if (createdVal !== undefined && createdVal !== null) {
      createdInNewPeriod = createdVal.toString() === 'true';
    } else {
      createdInNewPeriod = existing !== null ? existing.createdInNewPeriod : (lastRead === null);
    }

    const next: TrackedTopicState = new TrackedTopicState();
    next.topicId = topicId;
    next.lastReadPostNumber = lastRead;
    next.highestPostNumber = highest;
    next.categoryId = catId;
    next.notificationLevel = level as number;
    next.createdInNewPeriod = createdInNewPeriod;
    next.isSeen = existing !== null ? existing.isSeen : false;

    this.states.set(topicId, next);
    this.notify();
  }

  private handleDismissNew(data: Record<string, Object>): void {
    const payloadVal = data['payload'];
    if (payloadVal === undefined || payloadVal === null || typeof payloadVal !== 'object') return;
    const payload: Record<string, Object> = payloadVal as Record<string, Object>;
    const topicIdsVal = payload['topic_ids'];
    const categoryVal = payload['category_id'];
    const categoryId: number | null = categoryVal !== undefined && categoryVal !== null ? Number(categoryVal.toString()) : null;

    if (topicIdsVal !== undefined && topicIdsVal !== null && Array.isArray(topicIdsVal)) {
      const arr: Object[] = topicIdsVal as Object[];
      for (let i = 0; i < arr.length; i++) {
        const id: number = Number(arr[i].toString());
        if (!this.states.has(id)) continue;
        const s: TrackedTopicState = this.states.get(id) as TrackedTopicState;
        s.isSeen = true;
        this.states.set(id, s);
      }
      return;
    }

    // no topic_ids: dismiss by category
    this.states.forEach((s: TrackedTopicState, id: number) => {
      if (!this.isNew(s)) return;
      if (categoryId === null || s.categoryId === categoryId) {
        s.isSeen = true;
        this.states.set(id, s);
      }
    });
  }

  private handleDismissNewPosts(data: Record<string, Object>): void {
    const payloadVal = data['payload'];
    if (payloadVal === undefined || payloadVal === null || typeof payloadVal !== 'object') return;
    const payload: Record<string, Object> = payloadVal as Record<string, Object>;
    const topicIdsVal = payload['topic_ids'];
    const categoryVal = payload['category_id'];
    const categoryId: number | null = categoryVal !== undefined && categoryVal !== null ? Number(categoryVal.toString()) : null;

    const updateToHighest = (id: number): void => {
      if (!this.states.has(id)) return;
      const s: TrackedTopicState = this.states.get(id) as TrackedTopicState;
      s.lastReadPostNumber = s.highestPostNumber;
      this.states.set(id, s);
    };

    if (topicIdsVal !== undefined && topicIdsVal !== null && Array.isArray(topicIdsVal)) {
      const arr: Object[] = topicIdsVal as Object[];
      for (let i = 0; i < arr.length; i++) {
        const id: number = Number(arr[i].toString());
        updateToHighest(id);
      }
      return;
    }

    this.states.forEach((s: TrackedTopicState, id: number) => {
      if (!this.isUnread(s)) return;
      if (categoryId === null || s.categoryId === categoryId) {
        updateToHighest(id);
      }
    });
  }
}
