import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CookieStore } from '../network/CookieStore';
import { AppConstants } from '../../common/constants/AppConstants';

const TAG: string = 'MessageBusService';
const MAX_BACKOFF_SECONDS: number = 30;
const MIN_POLL_INTERVAL_MS: number = 100;
const SHORT_POLL_ELAPSED_THRESHOLD_MS: number = 2500;
const SHORT_POLL_DELAY_MIN_MS: number = 1500;
const SHORT_POLL_DELAY_MAX_MS: number = 2300;
const RATE_LIMIT_JITTER_MAX_SECONDS: number = 30;

interface DestroyableHttpRequest {
  destroy: () => void;
}

export class MessageBusMessage {
  channel: string = '';
  messageId: number = -1;
  data: Object | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): MessageBusMessage {
    const m: MessageBusMessage = new MessageBusMessage();
    const channelVal = json['channel'];
    m.channel = channelVal !== undefined && channelVal !== null ? channelVal.toString() : '';
    const idVal = json['message_id'];
    m.messageId = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : -1;
    const dataVal = json['data'];
    m.data = dataVal !== undefined && dataVal !== null ? dataVal as Object : null;
    return m;
  }
}

class ChannelSubscription {
  channel: string = '';
  lastMessageId: number = -1;
  callbacks: ((message: MessageBusMessage) => void)[] = [];

  constructor(channel: string, lastMessageId: number) {
    this.channel = channel;
    this.lastMessageId = lastMessageId;
  }
}

export class MessageBusService {
  private static instance: MessageBusService | null = null;

  private subscriptions: Map<string, ChannelSubscription> = new Map();
  private clientId: string = '';
  private cookieStore: CookieStore = CookieStore.getInstance();
  private baseUrl: string | null = null;
  private sharedSessionKey: string | null = null;
  private fallbackBaseLogged: boolean = false;

  private isPolling: boolean = false;
  private shouldStop: boolean = false;
  private pollGeneration: number = 0;
  private failureCount: number = 0;
  private lastPollAt: number = 0;
  private everSucceeded: boolean = false;

  private currentHttpRequest: DestroyableHttpRequest | null = null;
  private currentAbort: (() => void) | null = null;
  private wakeBackoff: (() => void) | null = null;

  private constructor() {
    this.clientId = this.generateClientId();
  }

  static getInstance(): MessageBusService {
    if (MessageBusService.instance === null) {
      MessageBusService.instance = new MessageBusService();
    }
    return MessageBusService.instance;
  }

  hasEverSucceeded(): boolean {
    return this.everSucceeded;
  }

  private getSchemeFromAppBaseUrl(): string {
    try {
      const base: string = AppConstants.BASE_URL;
      const idx: number = base.indexOf('://');
      if (idx > 0) {
        return base.substring(0, idx);
      }
    } catch (_) {
    }
    return 'https';
  }

  private getFallbackPollingBaseUrl(): string | null {
    try {
      // linux.do 的 message-bus 轮询域名与主站不同：从 /latest data-preloaded 可见 long_polling_base_url 为 https://ping.linux.do
      const base: string = AppConstants.BASE_URL.trim();
      if (base.length === 0) return null;

      let scheme: string = this.getSchemeFromAppBaseUrl();
      let host: string = base;
      const idx: number = base.indexOf('://');
      if (idx > 0) {
        scheme = base.substring(0, idx);
        host = base.substring(idx + 3);
      }
      const slash: number = host.indexOf('/');
      if (slash >= 0) host = host.substring(0, slash);
      host = host.trim();
      if (host.length === 0) return null;

      if (host.toLowerCase() === 'linux.do') {
        return `${scheme}://ping.linux.do`;
      }
    } catch (_) {
    }
    return null;
  }

  private getEffectiveBaseUrl(): string {
    let use: string = this.baseUrl !== null ? (this.baseUrl as string) : '';
    use = use.trim();
    if (use.length === 0) {
      const fallback: string | null = this.getFallbackPollingBaseUrl();
      if (fallback !== null && fallback.length > 0) {
        use = fallback;
        if (!this.fallbackBaseLogged && AppConstants.DEBUG_TRACKING) {
          this.fallbackBaseLogged = true;
          hilog.info(0x0000, TAG, 'Using fallback long_polling_base_url=%{public}s', use);
        }
      } else {
        use = AppConstants.BASE_URL;
      }
    }

    // Discourse 可能返回 scheme-relative：//example.com
    if (use.startsWith('//')) {
      use = `${this.getSchemeFromAppBaseUrl()}:${use}`;
    } else if (use.startsWith('/') && use !== '/') {
      // 兼容相对路径（少数站点可能部署在子路径）
      const base: string = AppConstants.BASE_URL.endsWith('/')
        ? AppConstants.BASE_URL.substring(0, AppConstants.BASE_URL.length - 1)
        : AppConstants.BASE_URL;
      use = `${base}${use}`;
    } else if (use === '/') {
      const fallback: string | null = this.getFallbackPollingBaseUrl();
      use = fallback !== null && fallback.length > 0 ? fallback : AppConstants.BASE_URL;
      if (!this.fallbackBaseLogged && AppConstants.DEBUG_TRACKING) {
        this.fallbackBaseLogged = true;
        hilog.info(0x0000, TAG, 'Using fallback long_polling_base_url=%{public}s', use);
      }
    }

    if (use.endsWith('/')) {
      use = use.substring(0, use.length - 1);
    }
    return use;
  }

  private sanitizePreview(text: string, maxLen: number): string {
    try {
      const trimmed: string = text.trim();
      if (trimmed.length === 0) return '';
      const sliced: string = trimmed.length > maxLen ? trimmed.substring(0, maxLen) : trimmed;
      return sliced
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\t', ' ');
    } catch (_) {
    }
    return '';
  }

  private getHeaderValue(headerObj: Object | undefined | null, name: string): string {
    if (headerObj === undefined || headerObj === null) return '';
    try {
      const headers: Record<string, Object> = headerObj as Record<string, Object>;
      const keys: string[] = Object.keys(headers);
      const target: string = name.toLowerCase();
      for (let i = 0; i < keys.length; i++) {
        const k: string = keys[i];
        if (k.toLowerCase() !== target) continue;
        const v: Object = headers[k];
        if (typeof v === 'string') return v as string;
        if (Array.isArray(v)) {
          const arr: Object[] = v as Object[];
          for (let j = 0; j < arr.length; j++) {
            const item: Object = arr[j];
            if (typeof item === 'string') return item as string;
          }
        }
        return v !== null && v !== undefined ? v.toString() : '';
      }
    } catch (_) {
    }
    return '';
  }

  configure(baseUrl: string | null, sharedSessionKey: string | null): void {
    const nextBase: string | null = baseUrl !== null && baseUrl.length > 0 ? baseUrl : null;
    const nextShared: string | null = sharedSessionKey !== null && sharedSessionKey.length > 0 ? sharedSessionKey : null;
    const changed: boolean = this.baseUrl !== nextBase || this.sharedSessionKey !== nextShared;
    this.baseUrl = nextBase;
    this.sharedSessionKey = nextShared;

    if (changed) {
      const use: string = this.getEffectiveBaseUrl();
      hilog.info(0x0000, TAG, 'Configured baseUrl=%{public}s', use);
      this.restartPollingIfRunning();
    }
  }

  updateLastMessageId(channel: string, messageId: number): void {
    if (!this.subscriptions.has(channel)) return;
    const sub: ChannelSubscription = this.subscriptions.get(channel) as ChannelSubscription;
    if (messageId > sub.lastMessageId) {
      sub.lastMessageId = messageId;
    }
  }

  subscribeWithMessageId(channel: string, callback: (message: MessageBusMessage) => void, messageId: number): void {
    const isNewChannel: boolean = !this.subscriptions.has(channel);
    if (!this.subscriptions.has(channel)) {
      this.subscriptions.set(channel, new ChannelSubscription(channel, messageId));
    }
    const sub: ChannelSubscription = this.subscriptions.get(channel) as ChannelSubscription;
    sub.callbacks.push(callback);
    if (messageId > sub.lastMessageId) {
      sub.lastMessageId = messageId;
    }

    if (!this.isPolling) {
      this.startPolling();
    } else if (isNewChannel) {
      // 对齐 FluxDO：新增频道时中止当前请求，立即让下一轮轮询包含新 payload
      this.restartPollingIfRunning();
    }
  }

  unsubscribe(channel: string, callback: ((message: MessageBusMessage) => void) | null = null): void {
    if (!this.subscriptions.has(channel)) return;
    const sub: ChannelSubscription = this.subscriptions.get(channel) as ChannelSubscription;
    if (callback !== null) {
      const next: ((message: MessageBusMessage) => void)[] = [];
      for (let i = 0; i < sub.callbacks.length; i++) {
        if (sub.callbacks[i] !== callback) {
          next.push(sub.callbacks[i]);
        }
      }
      sub.callbacks = next;
      if (sub.callbacks.length === 0) {
        this.subscriptions.delete(channel);
      }
    } else {
      this.subscriptions.delete(channel);
    }

    if (this.subscriptions.size === 0) {
      this.stopPolling();
    }
  }

  private startPolling(): void {
    if (this.isPolling) return;
    this.isPolling = true;
    this.shouldStop = false;
    this.failureCount = 0;
    this.pollGeneration = this.pollGeneration + 1;
    const gen: number = this.pollGeneration;
    this.poll(gen);
  }

  private stopPolling(): void {
    this.shouldStop = true;
    this.pollGeneration = this.pollGeneration + 1;
    this.isPolling = false;
    this.abortCurrentRequest();
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      const tid = setTimeout(() => {
        this.wakeBackoff = null;
        resolve();
      }, ms);
      this.wakeBackoff = () => {
        clearTimeout(tid);
        resolve();
      };
    });
  }

  private generateClientId(): string {
    const a: string = Math.random().toString(36).substring(2);
    const b: string = Math.random().toString(36).substring(2);
    return `${Date.now().toString(36)}${a}${b}`.substring(0, 32);
  }

  private abortCurrentRequest(): void {
    if (this.currentAbort !== null) {
      try {
        (this.currentAbort as () => void)();
      } catch (_) {
      }
      this.currentAbort = null;
    }
    if (this.currentHttpRequest === null) return;
    try {
      (this.currentHttpRequest as DestroyableHttpRequest).destroy();
    } catch (_) {
    }
    this.currentHttpRequest = null;
  }

  private restartPollingIfRunning(): void {
    if (!this.isPolling) return;
    if (this.shouldStop) return;
    if (this.subscriptions.size === 0) return;

    this.pollGeneration = this.pollGeneration + 1;
    const gen: number = this.pollGeneration;
    this.abortCurrentRequest();
    if (this.wakeBackoff !== null) {
      try {
        (this.wakeBackoff as () => void)();
      } catch (_) {
      }
      this.wakeBackoff = null;
    }
    this.poll(gen);
  }

  private encodeFormBody(params: Record<string, Object>): string {
    const keys: string[] = Object.keys(params);
    const parts: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const raw: Object = params[key];
      if (raw === null || raw === undefined) continue;

      if (Array.isArray(raw)) {
        const arr: Object[] = raw as Object[];
        for (let j = 0; j < arr.length; j++) {
          const item: Object = arr[j];
          if (item === null || item === undefined) continue;
          if (typeof item === 'string' || typeof item === 'number' || typeof item === 'boolean') {
            parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(item.toString())}`);
          }
        }
        continue;
      }

      if (typeof raw === 'string' || typeof raw === 'number' || typeof raw === 'boolean') {
        parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(raw.toString())}`);
      }
    }
    return parts.join('&');
  }

  private buildHeaders(extraHeaders: Record<string, string>, requestUrl: string): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['User-Agent'] = AppConstants.USER_AGENT;
    headers['Accept'] = 'application/json';
    headers['Content-Type'] = 'application/x-www-form-urlencoded';

    const cookieHeader: string = this.cookieStore.getCookieHeader(requestUrl);
    if (cookieHeader.length > 0) {
      headers['Cookie'] = cookieHeader;
    }

    const keys: string[] = Object.keys(extraHeaders);
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      const v: string = extraHeaders[k];
      if (v !== undefined && v !== null && v.length > 0) {
        headers[k] = v;
      }
    }
    return headers;
  }

  private getRetryAfterSeconds(headerObj: Object | undefined | null): number | null {
    if (headerObj === undefined || headerObj === null) return null;
    try {
      const headers: Record<string, Object> = headerObj as Record<string, Object>;
      const keys: string[] = Object.keys(headers);
      for (let i = 0; i < keys.length; i++) {
        const k: string = keys[i];
        if (k.toLowerCase() !== 'retry-after') continue;
        const v: Object = headers[k];
        if (v === undefined || v === null) continue;
        const parsed: number = Number(v.toString());
        if (!isNaN(parsed) && parsed > 0) {
          return parsed;
        }
      }
    } catch (_) {
    }
    return null;
  }

  private async poll(gen: number): Promise<void> {
    while (!this.shouldStop && this.subscriptions.size > 0 && gen === this.pollGeneration) {
      // 最小轮询间隔保护
      const now: number = Date.now();
      if (this.lastPollAt > 0 && now - this.lastPollAt < MIN_POLL_INTERVAL_MS) {
        await this.delay(MIN_POLL_INTERVAL_MS - (now - this.lastPollAt));
        if (this.shouldStop || gen !== this.pollGeneration) break;
      }

      const pollStartedAt: number = Date.now();
      let receivedData: boolean = false;
      // 是否收到非 /__status 的业务消息：仅收到 /__status 时也应放慢下一轮轮询，避免短轮询风暴触发 429
      let hasBusinessMessage: boolean = false;
      let lastBase: string = '';
      let lastUrl: string = '';
      let lastCode: number = 0;
      let lastContentType: string = '';
      let lastServer: string = '';
      let lastTailPreview: string = '';

      const payload: Record<string, Object> = {};
      const channels: string[] = [];
      this.subscriptions.forEach((_: ChannelSubscription, ch: string) => {
        channels.push(ch);
      });
      for (let i = 0; i < channels.length; i++) {
        const channel: string = channels[i];
        const sub: ChannelSubscription = this.subscriptions.get(channel) as ChannelSubscription;
        payload[channel] = sub.lastMessageId.toString();
      }

      const extraHeaders: Record<string, string> = {};
      // 对齐网页端：MessageBus poll 使用 text/plain 响应；不要强制 Discourse-Background=true，
      // 否则部分站点（如 linux.do）会按 anon_polling_interval 批量回包，导致“查看新话题”计数呈现 25s 一跳。
      extraHeaders['Accept'] = 'text/plain, */*; q=0.01';
      extraHeaders['X-SILENCE-LOGGER'] = 'true';
      if (this.sharedSessionKey !== null) {
        extraHeaders['X-Shared-Session-Key'] = this.sharedSessionKey as string;
      }

      this.lastPollAt = pollStartedAt;
      try {
        await this.cookieStore.init();

        const use: string = this.getEffectiveBaseUrl();
        const url: string = `${use}/message-bus/${this.clientId}/poll`;
        lastBase = use;
        lastUrl = url;

        const httpRequest = http.createHttp();
        const destroyable: DestroyableHttpRequest = httpRequest as DestroyableHttpRequest;
        this.currentHttpRequest = destroyable;

        let streamBuffer: string = '';
        const decoder: util.TextDecoder = new util.TextDecoder('utf-8', { ignoreBOM: true });

        httpRequest.on('dataReceive', (data: ArrayBuffer) => {
          if (this.shouldStop || gen !== this.pollGeneration) return;
          receivedData = true;
          try {
            const textPart: string = decoder.decodeToString(new Uint8Array(data), { stream: true });
            if (textPart.length === 0) return;
            streamBuffer = streamBuffer + textPart;

            let idx: number = streamBuffer.indexOf('|');
            while (idx >= 0) {
              const chunk: string = streamBuffer.substring(0, idx).trim();
              streamBuffer = streamBuffer.substring(idx + 1);
              if (chunk.length > 0) {
                hasBusinessMessage = hasBusinessMessage || this.processChunk(chunk);
              }
              idx = streamBuffer.indexOf('|');
            }
          } catch (err) {
            let errText: string = '';
            try {
              errText = err !== null && err !== undefined ? err.toString() : '';
            } catch (_) {
              errText = '';
            }
            if (errText.length === 0) {
              try {
                errText = JSON.stringify(err);
              } catch (_) {
                errText = '';
              }
            }
            hilog.warn(0x0000, TAG, 'Stream parse failed: %{public}s', errText);
          }
        });

        let headerObj: Object | undefined | null = null;
        httpRequest.on('headersReceive', (header: Object) => {
          headerObj = header;
        });

        let code: number = 0;
        let ended: boolean = false;
        let endResolver: (() => void) | null = null;
        const endPromise: Promise<void> = new Promise<void>((resolve) => {
          endResolver = resolve;
        });

        const endStream = (): void => {
          if (ended) return;
          ended = true;
          try {
            const flushText: string = decoder.decodeToString(new Uint8Array(0), { stream: false });
            if (flushText.length > 0) {
              streamBuffer = streamBuffer + flushText;
            }
          } catch (_) {
          }
          const tail: string = streamBuffer.trim();
          const shouldParseTail: boolean = code >= 200 && code < 300;
          if (tail.length > 0 && shouldParseTail) {
            hasBusinessMessage = hasBusinessMessage || this.processChunk(tail);
          }
          if (endResolver !== null) {
            endResolver();
          }
        };

        const abort: () => void = () => {
          endStream();
        };
        this.currentAbort = abort;

        httpRequest.on('dataEnd', () => {
          if (this.shouldStop || gen !== this.pollGeneration) {
            endStream();
            return;
          }
          endStream();
        });
        try {
          const body: string = this.encodeFormBody(payload);
          const headers: Record<string, string> = this.buildHeaders(extraHeaders, url);

          const req: Record<string, Object> = {};
          req['method'] = http.RequestMethod.POST;
          req['header'] = headers;
          req['connectTimeout'] = AppConstants.REQUEST_TIMEOUT;
          // 匿名 MessageBus 在部分设备/网络栈下会表现为“整段缓冲→dataEnd 才回调”，
          // 让客户端看起来只能每 ~25s 批量更新（与 anon_polling_interval 的连接生命周期一致）。
          // 这里对匿名态主动缩短 readTimeout，强制每隔一段时间断开重连，从而更频繁地“冲刷缓冲区”。（对齐安卓端更接近实时的体验）
          const readTimeoutMs: number = this.sharedSessionKey === null ? 5000 : 60000;
          req['readTimeout'] = readTimeoutMs;
          // 站点匿名轮询在部分设备上会默认走 HTTP/3（NetStack httpVer=3），
          // 可能导致 requestInStream 的 dataReceive 仅在 dataEnd 才回调，从而表现为“批量跳变不实时”。这里强制使用 HTTP/2。
          req['usingProtocol'] = http.HttpProtocol.HTTP2;
          req['extraData'] = body;
          req['usingCache'] = false;

          code = await httpRequest.requestInStream(url, req);
          await endPromise;
        } finally {
          endStream();
          if (this.currentAbort === abort) {
            this.currentAbort = null;
          }
          if (this.currentHttpRequest === destroyable) {
            this.currentHttpRequest = null;
          }
          httpRequest.destroy();
        }

        lastCode = code;
        lastContentType = this.getHeaderValue(headerObj, 'content-type');
        lastServer = this.getHeaderValue(headerObj, 'server');
        lastTailPreview = this.sanitizePreview(streamBuffer, 180);

        if (code === 429) {
          const retryAfter: number | null = this.getRetryAfterSeconds(headerObj);
          const baseWaitSeconds: number = retryAfter !== null ? (retryAfter as number) : 60;
          const jitterSeconds: number = Math.floor(Math.random() * (RATE_LIMIT_JITTER_MAX_SECONDS + 1));
          const waitSeconds: number = baseWaitSeconds + jitterSeconds;
          hilog.warn(0x0000, TAG, 'Rate limited, wait=%{public}d (base=%{public}d jitter=%{public}d)', waitSeconds, baseWaitSeconds, jitterSeconds);
          await this.delay(waitSeconds * 1000);
          continue;
        }

        if (code < 200 || code >= 300) {
          throw new Error(`HTTP ${code}`);
        }

        this.failureCount = 0;
        // requestInStream 下 body 通过 dataReceive 获取；若仅收到 /__status 或无业务消息，视为无消息返回并做节流延迟
        const elapsedMs: number = Date.now() - pollStartedAt;
        if (!hasBusinessMessage && elapsedMs < SHORT_POLL_ELAPSED_THRESHOLD_MS) {
          const span: number = Math.max(0, SHORT_POLL_DELAY_MAX_MS - SHORT_POLL_DELAY_MIN_MS);
          const delayMs: number = SHORT_POLL_DELAY_MIN_MS + Math.floor(Math.random() * (span + 1));
          if (AppConstants.DEBUG_TRACKING) {
            hilog.info(0x0000, TAG, 'Short poll without business messages, elapsed=%{public}dms delay=%{public}dms', elapsedMs, delayMs);
          }
          await this.delay(delayMs);
        }
      } catch (err) {
        if (this.shouldStop || gen !== this.pollGeneration) {
          break;
        }
        let errText: string = '';
        try {
          errText = err !== null && err !== undefined ? err.toString() : '';
        } catch (_) {
          errText = '';
        }
        if (errText.length === 0) {
          try {
            errText = JSON.stringify(err);
          } catch (_) {
            errText = '';
          }
        }
        const lower: string = errText.toLowerCase();
        const isTimeout: boolean = lower.indexOf('timeout') >= 0 || lower.indexOf('timed out') >= 0;
        if (isTimeout) {
          // 对齐 FluxDO：长轮询超时视为正常（不进入指数退避）
          this.failureCount = 0;
          if (AppConstants.DEBUG_TRACKING) {
            const elapsedMs: number = Date.now() - pollStartedAt;
            hilog.info(0x0000, TAG, 'Poll timeout (normal), elapsed=%{public}dms receivedData=%{public}s',
              elapsedMs, receivedData ? 'true' : 'false');
          }
          continue;
        }

        this.failureCount = this.failureCount + 1;
        const backoff: number = Math.min(Math.pow(2, this.failureCount), MAX_BACKOFF_SECONDS);
        if (lastCode > 0 || lastUrl.length > 0) {
          hilog.warn(
            0x0000,
            TAG,
            'Poll failed: %{public}s, code=%{public}d base=%{public}s url=%{public}s ct=%{public}s server=%{public}s tail=%{public}s backoff=%{public}d',
            errText.length > 0 ? errText : 'unknown error',
            lastCode,
            lastBase,
            lastUrl,
            lastContentType,
            lastServer,
            lastTailPreview,
            backoff
          );
        } else {
          hilog.warn(0x0000, TAG, 'Poll failed: %{public}s, backoff=%{public}d', errText.length > 0 ? errText : 'unknown error', backoff);
        }
        await this.delay(backoff * 1000);
      }
    }

    if (gen === this.pollGeneration) {
      this.isPolling = false;
    }
  }

  private processText(text: string): void {
    const trimmed: string = text.trim();
    if (trimmed.length === 0) return;

    const chunks: string[] = trimmed.split('|');
    for (let i = 0; i < chunks.length; i++) {
      const chunk: string = chunks[i].trim();
      if (chunk.length === 0) continue;
      this.processChunk(chunk);
    }
  }

  private processChunk(chunk: string): boolean {
    try {
      const parsed: Object = JSON.parse(chunk) as Object;
      if (!Array.isArray(parsed)) return false;
      const arr: Object[] = parsed as Object[];
      let hasBusinessMessage: boolean = false;
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item === null || item === undefined || typeof item !== 'object') continue;
        const msg: MessageBusMessage = MessageBusMessage.fromJson(item as Record<string, Object>);
        if (msg.channel.length > 0 && msg.channel !== '/__status') {
          hasBusinessMessage = true;
        }
        this.handleMessage(msg);
      }
      return hasBusinessMessage;
    } catch (err) {
      let errText: string = '';
      try {
        errText = err !== null && err !== undefined ? err.toString() : '';
      } catch (_) {
        errText = '';
      }
      if (errText.length === 0) {
        try {
          errText = JSON.stringify(err);
        } catch (_) {
          errText = '';
        }
      }
      const preview: string = this.sanitizePreview(chunk, 120);
      hilog.warn(0x0000, TAG, 'Chunk parse failed: %{public}s, preview=%{public}s', errText, preview);
    }
    return false;
  }

  private handleMessage(message: MessageBusMessage): void {
    if (message.channel.length === 0) return;

    if (message.channel === '/__status') {
      const wasEverSucceeded: boolean = this.everSucceeded;
      this.everSucceeded = true;
      if (!wasEverSucceeded && AppConstants.DEBUG_TRACKING) {
        hilog.info(0x0000, TAG, 'MessageBus ready (__status received)');
      }
      const dataObj: Object | null = message.data;
      if (dataObj === null || dataObj === undefined || typeof dataObj !== 'object') return;
      const data: Record<string, Object> = dataObj as Record<string, Object>;
      const keys: string[] = Object.keys(data);
      for (let i = 0; i < keys.length; i++) {
        const ch: string = keys[i];
        if (!this.subscriptions.has(ch)) continue;
        const idVal: Object = data[ch];
        if (idVal === undefined || idVal === null) continue;
        const id: number = Number(idVal.toString());
        if (isNaN(id)) continue;
        const sub: ChannelSubscription = this.subscriptions.get(ch) as ChannelSubscription;
        if (id > sub.lastMessageId) {
          sub.lastMessageId = id;
        }
      }
      return;
    }

    if (!this.subscriptions.has(message.channel)) return;
    const sub: ChannelSubscription = this.subscriptions.get(message.channel) as ChannelSubscription;
    if (message.messageId > sub.lastMessageId) {
      sub.lastMessageId = message.messageId;
    }

    for (let i = 0; i < sub.callbacks.length; i++) {
      try {
        sub.callbacks[i](message);
      } catch (_) {
      }
    }
  }
}
