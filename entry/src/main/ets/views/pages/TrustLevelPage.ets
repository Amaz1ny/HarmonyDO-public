import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { ArkWebHelper } from '../../common/utils/ArkWebHelper';
import { WindowManager } from '../../common/utils/WindowManager';
import { ThemeManager } from '../../common/theme/ThemeManager';
import { CookieStore } from '../../services/network/CookieStore';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';
import { ImmersiveHdsTitleBarHelper } from '../components/ImmersiveHdsTitleBarHelper';

const TAG: string = 'TrustLevelPage';
const CONNECT_URL: string = 'https://connect.linux.do/';
const EXTRACT_DELAY_MS: number = 600;
const MAX_PAGE_LOADS: number = 10;

// ── Data Models ──

enum TlBadgeType {
  SUCCESS = 'success',
  WARNING = 'warning',
  DANGER = 'danger'
}

class TlRingData {
  label: string = '';
  current: number = 0;
  max: number = 0;
  isMet: boolean = false;
}

class TlBarData {
  label: string = '';
  current: number = 0;
  target: number = 0;
  progress: number = 0;
  isMet: boolean = false;
}

class TlQuotaData {
  label: string = '';
  value: string = '';
  isMet: boolean = false;
}

class TlVetoData {
  label: string = '';
  value: string = '';
  isMet: boolean = false;
}

class TrustLevelData {
  title: string = '';
  badgeText: string = '';
  badgeType: TlBadgeType = TlBadgeType.DANGER;
  subtitle: string = '';
  rings: TlRingData[] = [];
  bars: TlBarData[] = [];
  quotas: TlQuotaData[] = [];
  vetos: TlVetoData[] = [];
  footerHint: string = '';
  statusText: string = '';
  isStatusMet: boolean = false;
}

// ── Page Component ──

@ComponentV2
export struct TrustLevelPage {
  @Local data: TrustLevelData | null = null;
  @Local isLoading: boolean = true;
  @Local isRefreshing: boolean = false;
  @Local errorMessage: string = '';
  @Local webViewVisible: boolean = false;

  private controller: webview.WebviewController = new webview.WebviewController('trust_level');
  private pageLoadCount: number = 0;
  private extracting: boolean = false;
  private finished: boolean = false;
  private webViewReady: boolean = false;
  private loadUrl: string = CONNECT_URL;
  private contentScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    WindowManager.applyDefaultSystemChrome();
    ArkWebHelper.configureLinuxDoHostsUserAgent();
    CookieStore.getInstance().init()
      .then(() => {
        CookieStore.getInstance().syncToWebView();
      })
      .catch((_err: Object) => {
        CookieStore.getInstance().syncToWebView();
      });
  }

  aboutToDisappear(): void {
    WindowManager.applyDefaultSystemChrome();
    this.finished = true;
  }

  // ── Data Extraction ──

  private isTrustLevelPage(url: string): boolean {
    const lower: string = url.toLowerCase();
    // connect.linux.do 最终页面（SSO 完成后回到 connect.linux.do）
    return lower.indexOf('connect.linux.do') >= 0
      && lower.indexOf('/session/sso') < 0;
  }

  private isCfChallengePage(url: string): boolean {
    const lower: string = url.toLowerCase();
    return lower.indexOf('challenges.cloudflare.com') >= 0
      || lower.indexOf('/cdn-cgi/') >= 0;
  }

  private hasChallengeContent(title: string, bodyText: string): boolean {
    const lowerTitle: string = title.toLowerCase();
    const lowerText: string = bodyText.toLowerCase();
    return lowerTitle.indexOf('请稍候') >= 0
      || lowerTitle.indexOf('just a moment') >= 0
      || lowerText.indexOf('请稍候') >= 0
      || lowerText.indexOf('just a moment') >= 0
      || lowerText.indexOf('verifying you are human') >= 0;
  }

  private tryExtractHtml(): void {
    if (this.extracting || this.finished) return;
    this.extracting = true;

    // 延迟提取，等页面 JS 渲染完成
    setTimeout(() => {
      this.doExtractHtml().catch((err: Object) => {
        hilog.error(0x0000, TAG, 'Extract HTML failed: %{public}s', JSON.stringify(err));
      }).finally(() => {
        this.extracting = false;
      });
    }, EXTRACT_DELAY_MS);
  }

  private async doExtractHtml(): Promise<void> {
    if (this.finished) return;

    // 先获取当前 URL 和 title
    let currentUrl: string = '';
    let currentTitle: string = '';
    try {
      currentUrl = this.controller.getUrl();
    } catch (_) {
    }
    try {
      currentTitle = this.controller.getTitle();
    } catch (_) {
    }

    hilog.info(0x0000, TAG, 'Check page: url=%{public}s title=%{public}s loadCount=%{public}d',
      currentUrl, currentTitle, this.pageLoadCount);

    // 如果是 CF challenge 页面，显示 WebView 让用户交互
    if (this.isCfChallengePage(currentUrl)) {
      this.webViewVisible = true;
      hilog.info(0x0000, TAG, 'CF challenge page detected, showing WebView');
      return;
    }

    // 检查是否是目标页面（connect.linux.do 的信任等级内容）
    if (!this.isTrustLevelPage(currentUrl)) {
      hilog.info(0x0000, TAG, 'Not trust level page yet, waiting for redirect');
      return;
    }

    // 提取 outerHTML
    const script: string = `(function() {
      try {
        return document.documentElement.outerHTML;
      } catch(e) {
        return '';
      }
    })()`;

    let rawHtml: string = '';
    try {
      const result: string = await this.controller.runJavaScript(script);
      // runJavaScript 返回值可能被包在引号中（JSON string）
      if (result.length > 0) {
        const trimmed: string = result.trim();
        if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
          try {
            rawHtml = JSON.parse(trimmed) as string;
          } catch (_) {
            rawHtml = trimmed;
          }
        } else {
          rawHtml = trimmed;
        }
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'runJavaScript failed: %{public}s', JSON.stringify(err));
    }

    if (rawHtml.length === 0) {
      hilog.warn(0x0000, TAG, 'Empty HTML extracted');
      return;
    }

    // 检查是否仍然是 CF challenge 内容
    if (this.hasChallengeContent(currentTitle, rawHtml.substring(0, Math.min(2000, rawHtml.length)))) {
      this.webViewVisible = true;
      hilog.info(0x0000, TAG, 'Challenge content detected in HTML, showing WebView');
      return;
    }

    hilog.info(0x0000, TAG, 'Got HTML from WebView, len=%{public}d', rawHtml.length);

    // 同步 cookie 回 CookieStore
    CookieStore.getInstance().syncFromWebView(
      ['https://linux.do', 'https://connect.linux.do', 'https://ping.linux.do']
    );

    const parsed: TrustLevelData | null = this.parseHtml(rawHtml);
    if (parsed === null) {
      this.errorMessage = '信任信息解析失败';
      this.isLoading = false;
      this.isRefreshing = false;
      return;
    }

    this.data = parsed;
    this.isLoading = false;
    this.isRefreshing = false;
    this.webViewVisible = false;
    this.finished = true;
  }

  private reload(): void {
    this.data = null;
    this.errorMessage = '';
    this.isLoading = true;
    this.isRefreshing = false;
    this.webViewVisible = false;
    this.pageLoadCount = 0;
    this.extracting = false;
    this.finished = false;
    this.loadUrl = CONNECT_URL;
    try {
      this.controller.loadUrl(CONNECT_URL);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Reload failed: %{public}s', JSON.stringify(err));
    }
  }

  // ── HTML Parsing ──

  private parseHtml(html: string): TrustLevelData | null {
    try {
      const data: TrustLevelData = new TrustLevelData();

      // Extract title from card-title
      const titleMatch: RegExpMatchArray | null = html.match(/class="card-title"[^>]*>([\s\S]*?)<\//);
      if (titleMatch !== null && titleMatch.length > 1) {
        data.title = this.stripTags(titleMatch[1]).trim();
      }
      // Fallback: h1 tag for title
      if (data.title.length === 0) {
        const h1Match: RegExpMatchArray | null = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/);
        if (h1Match !== null && h1Match.length > 1) {
          data.title = this.stripTags(h1Match[1]).trim();
        }
      }

      // Extract subtitle from card-subtitle
      const subtitleMatch: RegExpMatchArray | null = html.match(/class="card-subtitle"[^>]*>([\s\S]*?)<\//);
      if (subtitleMatch !== null && subtitleMatch.length > 1) {
        data.subtitle = this.stripTags(subtitleMatch[1]).trim();
      }

      // Extract badge
      const badgeMatch: RegExpMatchArray | null =
        html.match(/class="badge\s+badge-(success|warning|danger)"[^>]*>([\s\S]*?)<\//);
      if (badgeMatch !== null && badgeMatch.length > 2) {
        const badgeTypeStr: string = badgeMatch[1];
        data.badgeText = this.stripTags(badgeMatch[2]).trim();
        if (badgeTypeStr === 'success') {
          data.badgeType = TlBadgeType.SUCCESS;
        } else if (badgeTypeStr === 'warning') {
          data.badgeType = TlBadgeType.WARNING;
        } else {
          data.badgeType = TlBadgeType.DANGER;
        }
      }

      // Parse rings
      data.rings = this.parseRings(html);

      // Parse bars
      data.bars = this.parseBars(html);

      // Parse quotas
      data.quotas = this.parseQuotas(html);

      // Parse vetos
      data.vetos = this.parseVetos(html);

      // Parse footer status
      const statusMetMatch: RegExpMatchArray | null = html.match(/class="[^"]*status-met[^"]*"[^>]*>([\s\S]*?)<\//);
      const statusUnmetMatch: RegExpMatchArray | null =
        html.match(/class="[^"]*status-unmet[^"]*"[^>]*>([\s\S]*?)<\//);
      if (statusMetMatch !== null && statusMetMatch.length > 1) {
        data.statusText = this.stripTags(statusMetMatch[1]).trim();
        data.isStatusMet = true;
      } else if (statusUnmetMatch !== null && statusUnmetMatch.length > 1) {
        data.statusText = this.stripTags(statusUnmetMatch[1]).trim();
        data.isStatusMet = false;
      }

      // Parse footer hint
      const hintMatch: RegExpMatchArray | null = html.match(/class="[^"]*text-hint[^"]*"[^>]*>([\s\S]*?)<\//);
      if (hintMatch !== null && hintMatch.length > 1) {
        data.footerHint = this.stripTags(hintMatch[1]).trim();
      }

      // Must have title or at least some data to be considered valid
      if (data.title.length === 0 && data.rings.length === 0 && data.bars.length === 0) {
        return null;
      }
      return data;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Parse HTML failed: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  private parseRings(html: string): TlRingData[] {
    const rings: TlRingData[] = [];
    // 匹配 class="tl3-ring" 或 class="tl3-ring met" 等容器
    // 使用 [" ] 确保 tl3-ring 后面紧跟引号或空格，排除 tl3-ring-label / tl3-ring-circle
    const ringBlockRegex: RegExp = new RegExp('class="tl3-ring[" ][^>]*>([\\s\\S]*?)(?=class="tl3-ring[" ][^>]*>|class="tl3-bar|class="tl3-quota|class="tl3-veto|class="card-footer|$)', 'g');
    let ringMatch = ringBlockRegex.exec(html);
    while (ringMatch !== null) {
      const block: string = ringMatch[1];
      const ring: TlRingData = new TlRingData();

      // Label
      const labelMatch: RegExpMatchArray | null = block.match(/class="[^"]*tl3-ring-label[^"]*"[^>]*>([\s\S]*?)<\//);
      if (labelMatch !== null && labelMatch.length > 1) {
        ring.label = this.stripTags(labelMatch[1]).trim();
      }

      // Values: try CSS variables first, then data attributes, then sub-elements
      const circleBlock: string = block;
      ring.current = this.extractCssVar(circleBlock, 'val') ??
        this.extractCssVar(circleBlock, 'value') ??
        this.extractDataAttr(circleBlock, 'value') ??
        this.extractDataAttr(circleBlock, 'val') ??
        this.extractSubElementNumber(circleBlock, 'tl3-ring-current') ?? 0;

      ring.max = this.extractCssVar(circleBlock, 'max') ??
        this.extractCssVar(circleBlock, 'target') ??
        this.extractDataAttr(circleBlock, 'max') ??
        this.extractDataAttr(circleBlock, 'target') ??
        this.extractSubElementNumber(circleBlock, 'tl3-ring-target') ?? 0;

      // Met status
      ring.isMet = circleBlock.indexOf('met') >= 0 && circleBlock.indexOf('unmet') < 0;
      // More precise check
      const metClassMatch: RegExpMatchArray | null = circleBlock.match(/class="[^"]*\bmet\b[^"]*"/);
      const unmetClassMatch: RegExpMatchArray | null = circleBlock.match(/class="[^"]*\bunmet\b[^"]*"/);
      if (unmetClassMatch !== null) {
        ring.isMet = false;
      } else if (metClassMatch !== null) {
        ring.isMet = true;
      }

      if (ring.label.length > 0) {
        rings.push(ring);
      }
      ringMatch = ringBlockRegex.exec(html);
    }
    return rings;
  }

  private parseBars(html: string): TlBarData[] {
    const bars: TlBarData[] = [];
    const barBlockRegex: RegExp =
      new RegExp('class="tl3-bar-item[^"]*"[^>]*>([\\s\\S]*?)(?=class="tl3-bar-item[^"]*"|class="tl3-quota|class="tl3-veto|class="card-footer|</div>\\s*</div>\\s*</div>)', 'g');
    let barMatch = barBlockRegex.exec(html);
    while (barMatch !== null) {
      const block: string = barMatch[1];
      const bar: TlBarData = new TlBarData();

      // Label
      const labelMatch: RegExpMatchArray | null = block.match(/class="[^"]*tl3-bar-label[^"]*"[^>]*>([\s\S]*?)<\//);
      if (labelMatch !== null && labelMatch.length > 1) {
        bar.label = this.stripTags(labelMatch[1]).trim();
      }

      // Try to parse nums "current / target" from tl3-bar-nums
      const numsMatch: RegExpMatchArray | null = block.match(/class="tl3-bar-nums[^"]*"[^>]*>([\s\S]*?)<\//);
      if (numsMatch !== null && numsMatch.length > 1) {
        const numsText: string = this.stripTags(numsMatch[1]).trim();
        const parts: string[] = numsText.split('/');
        if (parts.length >= 2) {
          bar.current = this.parseIntSafe(parts[0].trim());
          bar.target = this.parseIntSafe(parts[1].trim());
        }
      }

      // Fallback to CSS vars
      if (bar.current === 0 && bar.target === 0) {
        bar.current = this.extractCssVar(block, 'val') ??
          this.extractDataAttr(block, 'value') ?? 0;
        bar.target = this.extractCssVar(block, 'max') ??
          this.extractDataAttr(block, 'max') ?? 0;
      }

      // Calculate progress
      if (bar.target > 0) {
        bar.progress = Math.min(1.0, bar.current / bar.target);
      }

      // Met status
      const metMatch: RegExpMatchArray | null = block.match(/class="[^"]*\bmet\b[^"]*"/);
      const unmetMatch: RegExpMatchArray | null = block.match(/class="[^"]*\bunmet\b[^"]*"/);
      if (unmetMatch !== null) {
        bar.isMet = false;
      } else if (metMatch !== null) {
        bar.isMet = true;
      } else {
        bar.isMet = bar.target > 0 && bar.current >= bar.target;
      }

      if (bar.label.length > 0) {
        bars.push(bar);
      }
      barMatch = barBlockRegex.exec(html);
    }
    return bars;
  }

  private parseQuotas(html: string): TlQuotaData[] {
    const quotas: TlQuotaData[] = [];
    const quotaBlockRegex: RegExp =
      new RegExp('class="tl3-quota-card[^"]*"[^>]*>([\\s\\S]*?)(?=class="tl3-quota-card|class="tl3-veto|</div>\\s*</div>\\s*</div>)', 'g');
    let quotaMatch = quotaBlockRegex.exec(html);
    while (quotaMatch !== null) {
      const fullMatch: string = quotaMatch[0];
      const block: string = quotaMatch[1];
      const quota: TlQuotaData = new TlQuotaData();

      // Label
      const labelMatch: RegExpMatchArray | null = block.match(/class="[^"]*tl3-quota-label[^"]*"[^>]*>([\s\S]*?)<\//);
      if (labelMatch !== null && labelMatch.length > 1) {
        quota.label = this.stripTags(labelMatch[1]).trim();
      }

      // Value (nums)
      const numsMatch: RegExpMatchArray | null = block.match(/class="[^"]*tl3-quota-nums[^"]*"[^>]*>([\s\S]*?)<\//);
      if (numsMatch !== null && numsMatch.length > 1) {
        quota.value = this.stripTags(numsMatch[1]).trim();
      }

      // Met status from outer class (word-boundary match, consistent with rings/bars)
      const quotaMetMatch: RegExpMatchArray | null = fullMatch.match(/class="[^"]*\bmet\b[^"]*"/);
      const quotaUnmetMatch: RegExpMatchArray | null = fullMatch.match(/class="[^"]*\bunmet\b[^"]*"/);
      if (quotaUnmetMatch !== null) {
        quota.isMet = false;
      } else {
        quota.isMet = quotaMetMatch !== null;
      }

      if (quota.label.length > 0) {
        quotas.push(quota);
      }
      quotaMatch = quotaBlockRegex.exec(html);
    }
    return quotas;
  }

  private parseVetos(html: string): TlVetoData[] {
    const vetos: TlVetoData[] = [];
    const vetoBlockRegex: RegExp =
      new RegExp('class="tl3-veto-item[^"]*"[^>]*>([\\s\\S]*?)(?=class="tl3-veto-item|class="[^"]*text-hint|class="[^"]*status-|</div>\\s*</div>\\s*</div>)', 'g');
    let vetoMatch = vetoBlockRegex.exec(html);
    while (vetoMatch !== null) {
      const fullMatch: string = vetoMatch[0];
      const block: string = vetoMatch[1];
      const veto: TlVetoData = new TlVetoData();

      // Label
      const labelMatch: RegExpMatchArray | null = block.match(/class="[^"]*tl3-veto-label[^"]*"[^>]*>([\s\S]*?)<\//);
      if (labelMatch !== null && labelMatch.length > 1) {
        veto.label = this.stripTags(labelMatch[1]).trim();
      }

      // Value
      const valueMatch: RegExpMatchArray | null = block.match(/class="[^"]*tl3-veto-value[^"]*"[^>]*>([\s\S]*?)<\//);
      if (valueMatch !== null && valueMatch.length > 1) {
        veto.value = this.stripTags(valueMatch[1]).trim();
      }

      // Met status (word-boundary match, consistent with rings/bars)
      const vetoMetMatch: RegExpMatchArray | null = fullMatch.match(/class="[^"]*\bmet\b[^"]*"/);
      const vetoUnmetMatch: RegExpMatchArray | null = fullMatch.match(/class="[^"]*\bunmet\b[^"]*"/);
      if (vetoUnmetMatch !== null) {
        veto.isMet = false;
      } else {
        veto.isMet = vetoMetMatch !== null;
      }

      if (veto.label.length > 0) {
        vetos.push(veto);
      }
      vetoMatch = vetoBlockRegex.exec(html);
    }
    return vetos;
  }

  // ── Parsing Helpers ──

  private stripTags(text: string): string {
    return text.replace(/<[^>]*>/g, '');
  }

  private parseIntSafe(text: string): number {
    const cleaned: string = text.replace(/[^0-9\-]/g, '');
    if (cleaned.length === 0) {
      return 0;
    }
    const parsed: number = parseInt(cleaned);
    if (isNaN(parsed)) {
      return 0;
    }
    return parsed;
  }

  private extractCssVar(block: string, varName: string): number | null {
    const regex: RegExp = new RegExp(`--${varName}\\s*:\\s*([0-9]+)`);
    const match: RegExpMatchArray | null = block.match(regex);
    if (match !== null && match.length > 1) {
      return this.parseIntSafe(match[1]);
    }
    return null;
  }

  private extractDataAttr(block: string, attrName: string): number | null {
    const regex: RegExp = new RegExp(`data-${attrName}="([0-9]+)"`);
    const match: RegExpMatchArray | null = block.match(regex);
    if (match !== null && match.length > 1) {
      return this.parseIntSafe(match[1]);
    }
    return null;
  }

  private extractSubElementNumber(block: string, className: string): number | null {
    const regex: RegExp = new RegExp(`class="[^"]*${className}[^"]*"[^>]*>([\\s\\S]*?)<\\/`);
    const match: RegExpMatchArray | null = block.match(regex);
    if (match !== null && match.length > 1) {
      const text: string = this.stripTags(match[1]).trim();
      if (text.length > 0) {
        return this.parseIntSafe(text);
      }
    }
    return null;
  }

  // ── Layout Helpers ──

  private getMetColor(): string {
    return '#43A047';
  }

  private getUnmetColor(): string {
    return '#E53935';
  }

  private getWarningColor(): string {
    return '#F57C00';
  }

  private getBadgeColor(badgeType: TlBadgeType): string {
    if (badgeType === TlBadgeType.SUCCESS) {
      return this.getMetColor();
    }
    if (badgeType === TlBadgeType.WARNING) {
      return this.getWarningColor();
    }
    return this.getUnmetColor();
  }

  private getRingProgress(ring: TlRingData): number {
    if (ring.max <= 0) {
      return 0;
    }
    return Math.min(100, Math.round(ring.current / ring.max * 100));
  }

  // ── Build ──

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 隐藏 WebView（处理 CF challenge + SSO 重定向 + 加载目标页面）
        // 如果需要用户交互验证则显示
        Web({ src: this.loadUrl, controller: this.controller })
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .databaseAccess(true)
          .onlineImageAccess(true)
          .imageAccess(true)
          .visibility(this.webViewVisible ? Visibility.Visible : Visibility.Hidden)
          .onPageEnd(() => {
            this.pageLoadCount += 1;
            let url: string = '';
            try {
              url = this.controller.getUrl();
            } catch (_) {
            }
            hilog.info(0x0000, TAG, 'WebView onPageEnd: url=%{public}s count=%{public}d', url, this.pageLoadCount);

            if (this.pageLoadCount > MAX_PAGE_LOADS) {
              this.errorMessage = '信任信息加载超时';
              this.isLoading = false;
              return;
            }

            this.tryExtractHtml();
          })
          .onErrorReceive((event: OnErrorReceiveEvent) => {
            let isMainFrame: boolean = false;
            try {
              isMainFrame = event.request.isMainFrame();
            } catch (_) {
            }
            if (!isMainFrame) return;

            let errorInfo: string = '';
            try {
              errorInfo = event.error.getErrorInfo();
            } catch (_) {
            }
            hilog.error(0x0000, TAG, 'WebView error: %{public}s', errorInfo);
            this.errorMessage = errorInfo.length > 0 ? errorInfo : '信任信息加载失败';
            this.isLoading = false;
          })
          .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
            let isMainFrame: boolean = false;
            try {
              isMainFrame = event.request.isMainFrame();
            } catch (_) {
            }
            if (!isMainFrame) return;

            let responseCode: number = 0;
            try {
              responseCode = event.response.getResponseCode();
            } catch (_) {
            }
            // 忽略 CF 相关的错误（403 由 CF Turnstile 处理）
            if (responseCode === 403) {
              hilog.info(0x0000, TAG, 'HTTP 403 in WebView, likely CF challenge');
              return;
            }
          })

        // 数据加载完成后显示原生 UI
        Refresh({ refreshing: this.isRefreshing }) {
          if (this.isLoading && this.data === null && this.errorMessage.length === 0 && !this.webViewVisible) {
            Column() {
              LoadingSpinner({ message: '' })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.errorMessage.length > 0 && this.data === null) {
            Column() {
              ErrorView({
                title: '加载失败',
                message: this.errorMessage,
                onRetry: () => {
                  this.reload();
                }
              })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          } else if (this.data !== null) {
            Scroll(this.contentScroller) {
              Column() {
                Blank()
                  .height(ImmersiveHdsTitleBarHelper.getContentTopSpacerHeightVp())
                  .width('100%')

                if (this.data !== null) {
                  this.HeaderPanel(this.data as TrustLevelData)
                  this.ContentSection(this.data as TrustLevelData)
                  this.FooterSection(this.data as TrustLevelData)
                }

                // Bottom padding
                Blank()
                  .height(40 + WindowManager.getSystemAvoidAreaBottomVp())
                  .width('100%')
              }
              .width('100%')
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
        .onRefreshing(() => {
          this.reload();
        })
        .visibility(this.webViewVisible ? Visibility.Hidden : Visibility.Visible)
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.background'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .titleBar(ImmersiveHdsTitleBarHelper.buildImmersiveTitleBar($r('app.string.trust_level_page_title')))
    .hideTitleBar(false)
    .hideBackButton(false)
    .hideToolBar(true)
    .bindToScrollable([this.contentScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .systemBarStyle(
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() },
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() }
    )
  }

  // ── Header Panel ──

  @Builder
  private HeaderPanel(data: TrustLevelData) {
    Column() {
      // Shield decoration
      Row() {
        SymbolGlyph($r('sys.symbol.security_shield'))
          .fontSize(36)
          .fontColor([this.getBadgeColor(data.badgeType)])
      }
      .width(64)
      .height(64)
      .borderRadius(32)
      .backgroundColor(ThemeManager.hexWithAlpha(this.getBadgeColor(data.badgeType), 0.12))
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      if (data.title.length > 0) {
        Text(data.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .textAlign(TextAlign.Center)
          .margin({ top: 12 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (data.subtitle.length > 0) {
        Text(data.subtitle)
          .fontSize(13)
          .fontColor($r('app.color.on_surface_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ top: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (data.badgeText.length > 0) {
        Row() {
          Text(data.badgeText)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
        }
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor(this.getBadgeColor(data.badgeType))
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 24 })
    .alignItems(HorizontalAlign.Center)
  }

  // ── Content Section ──

  @Builder
  private ContentSection(data: TrustLevelData) {
    Column({ space: 12 }) {
      // Activity rings
      if (data.rings.length > 0) {
        Column() {
          Text($r('app.string.trust_level_activity'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .padding({ left: 16, top: 16, bottom: 8 })
            .width('100%')

          this.RingsContent(data.rings)
        }
        .width('100%')
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)
        .shadow({ radius: 8, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 })
      }

      // Interaction bars
      if (data.bars.length > 0) {
        Column() {
          Text($r('app.string.trust_level_interaction'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .padding({ left: 16, top: 16, bottom: 8 })
            .width('100%')

          this.BarsContent(data.bars)
        }
        .width('100%')
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)
        .shadow({ radius: 8, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 })
      }

      // Compliance: quotas + vetos
      if (data.quotas.length > 0 || data.vetos.length > 0) {
        Column() {
          Text($r('app.string.trust_level_compliance'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .padding({ left: 16, top: 16, bottom: 8 })
            .width('100%')

          this.ComplianceContent(data.quotas, data.vetos)
        }
        .width('100%')
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)
        .shadow({ radius: 8, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  // ── Ring Progress ──

  @Builder
  private RingsContent(rings: TlRingData[]) {
    Row() {
      ForEach(rings, (ring: TlRingData, index: number) => {
        Column() {
          Stack() {
            Progress({
              value: this.getRingProgress(ring),
              total: 100,
              type: ProgressType.Ring
            })
              .width(64)
              .height(64)
              .color(ring.isMet ? this.getMetColor() : this.getUnmetColor())
              .backgroundColor(ThemeManager.hexWithAlpha(ring.isMet ? this.getMetColor() : this.getUnmetColor(), 0.12))
              .style({ strokeWidth: 6 })

            Column() {
              Text(`${ring.current}`)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(ring.isMet ? this.getMetColor() : this.getUnmetColor())
              Text(`/ ${ring.max}`)
                .fontSize(10)
                .fontColor($r('app.color.on_surface_tertiary'))
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          .width(64)
          .height(64)

          Text(ring.label)
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 8 })
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // Met indicator
          Row() {
            SymbolGlyph(ring.isMet ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.xmark_circle_fill'))
              .fontSize(14)
              .fontColor([ring.isMet ? this.getMetColor() : this.getUnmetColor()])
          }
          .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 4, bottom: 16 })
      }, (ring: TlRingData, index: number) => `ring_${index}_${ring.label}`)
    }
    .width('100%')
    .padding({ left: 8, right: 8 })
    .justifyContent(FlexAlign.SpaceEvenly)
  }

  // ── Bar Progress ──

  @Builder
  private BarsContent(bars: TlBarData[]) {
    Column({ space: 12 }) {
      ForEach(bars, (bar: TlBarData, index: number) => {
        Column({ space: 6 }) {
          Row() {
            Text(bar.label)
              .fontSize(13)
              .fontColor($r('app.color.on_surface'))
              .layoutWeight(1)

            Row({ space: 4 }) {
              Text(`${bar.current}`)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(bar.isMet ? this.getMetColor() : this.getUnmetColor())
              Text(`/ ${bar.target}`)
                .fontSize(13)
                .fontColor($r('app.color.on_surface_tertiary'))
            }

            SymbolGlyph(bar.isMet ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.xmark_circle_fill'))
              .fontSize(16)
              .fontColor([bar.isMet ? this.getMetColor() : this.getUnmetColor()])
              .margin({ left: 6 })
          }
          .width('100%')

          Progress({
            value: Math.round(bar.progress * 100),
            total: 100,
            type: ProgressType.Linear
          })
            .width('100%')
            .height(6)
            .color(bar.isMet ? this.getMetColor() : this.getUnmetColor())
            .backgroundColor(ThemeManager.hexWithAlpha(bar.isMet ? this.getMetColor() : this.getUnmetColor(), 0.12))
            .borderRadius(3)
        }
        .width('100%')
      }, (bar: TlBarData, index: number) => `bar_${index}_${bar.label}`)
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 16 })
  }

  // ── Compliance (Quotas + Vetos) ──

  @Builder
  private ComplianceContent(quotas: TlQuotaData[], vetos: TlVetoData[]) {
    Column({ space: 8 }) {
      // Quota items
      ForEach(quotas, (quota: TlQuotaData, index: number) => {
        Row() {
          SymbolGlyph(quota.isMet ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.xmark_circle_fill'))
            .fontSize(18)
            .fontColor([quota.isMet ? this.getMetColor() : this.getUnmetColor()])

          Text(quota.label)
            .fontSize(13)
            .fontColor($r('app.color.on_surface'))
            .layoutWeight(1)
            .margin({ left: 10 })

          Text(quota.value)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(quota.isMet ? this.getMetColor() : this.getUnmetColor())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }, (quota: TlQuotaData, index: number) => `quota_${index}_${quota.label}`)

      // Divider between quotas and vetos
      if (quotas.length > 0 && vetos.length > 0) {
        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 16, right: 16 })
      }

      // Veto items
      ForEach(vetos, (veto: TlVetoData, index: number) => {
        Row() {
          SymbolGlyph(veto.isMet ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.exclamationmark_triangle_fill'))
            .fontSize(18)
            .fontColor([veto.isMet ? this.getMetColor() : this.getUnmetColor()])

          Text(veto.label)
            .fontSize(13)
            .fontColor($r('app.color.on_surface'))
            .layoutWeight(1)
            .margin({ left: 10 })

          Text(veto.value)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(veto.isMet ? this.getMetColor() : this.getUnmetColor())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }, (veto: TlVetoData, index: number) => `veto_${index}_${veto.label}`)
    }
    .width('100%')
    .padding({ bottom: 12 })
  }

  // ── Footer ──

  @Builder
  private FooterSection(data: TrustLevelData) {
    Column({ space: 8 }) {
      if (data.footerHint.length > 0) {
        Text(data.footerHint)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_tertiary'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ left: 20, right: 20 })
      }

      if (data.statusText.length > 0) {
        Row() {
          SymbolGlyph(data.isStatusMet
            ? $r('sys.symbol.checkmark_circle_fill')
            : $r('sys.symbol.xmark_circle_fill'))
            .fontSize(16)
            .fontColor([data.isStatusMet ? this.getMetColor() : this.getUnmetColor()])
            .margin({ right: 6 })

          Text(data.statusText)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(data.isStatusMet ? this.getMetColor() : this.getUnmetColor())
        }
        .justifyContent(FlexAlign.Center)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .borderRadius(20)
        .backgroundColor(ThemeManager.hexWithAlpha(
          data.isStatusMet ? this.getMetColor() : this.getUnmetColor(), 0.08
        ))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 16 })
  }
}
