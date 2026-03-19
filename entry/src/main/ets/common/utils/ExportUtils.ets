import { hilog } from '@kit.PerformanceAnalysisKit';
import fileIo from '@ohos.file.fs';
import { ApiClient } from '../../services/network/ApiClient';
import { Post } from '../../models/Post';
import { UrlUtils } from './UrlUtils';

const TAG: string = 'ExportUtils';
const POSTS_BATCH_SIZE: number = 20;

export class ExportFileResult {
  ok: boolean = false;
  filePath: string = '';
  fileUri: string = '';
  errorMessage: string = '';

  constructor() {
  }
}

export class ExportUtils {
  static async exportTopicToFile(
    topicId: number,
    topicTitle: string,
    topicShareUrl: string,
    streamIds: number[],
    scope: number, // 0=仅主帖 1=全部
    format: number, // 0=MD 1=HTML
    cacheDir: string,
    onProgress: (current: number, total: number) => void = (_: number, __: number) => {
    }
  ): Promise<ExportFileResult> {
    const res: ExportFileResult = new ExportFileResult();
    if (topicId <= 0) {
      res.errorMessage = '无效的话题ID';
      return res;
    }

    const safeCacheDir: string = cacheDir !== undefined && cacheDir !== null ? cacheDir.trim() : '';
    if (safeCacheDir.length === 0) {
      res.errorMessage = '缓存目录不可用';
      return res;
    }

    const safeShareUrl: string = topicShareUrl !== undefined && topicShareUrl !== null ? topicShareUrl.trim() : '';
    if (safeShareUrl.length === 0) {
      res.errorMessage = '分享链接不可用';
      return res;
    }

    if (streamIds.length === 0) {
      res.errorMessage = '帖子流未加载';
      return res;
    }

    // 选取导出 ID 列表
    let ids: number[] = [];
    if (scope === 0) {
      ids = [streamIds[0]];
    } else {
      ids = [...streamIds];
      // 对齐安卓：MD 全量导出上限 10 层
      if (format === 0 && ids.length > 10) {
        ids = ids.slice(0, 10);
      }
    }

    const total: number = ids.length;
    if (total <= 0) {
      res.errorMessage = '无可导出的内容';
      return res;
    }

    const apiClient: ApiClient = ApiClient.getInstance();
    const postsById: Map<number, Post> = await ExportUtils.fetchPostsByIds(apiClient, topicId, ids);

    try {
      if (format === 1) {
        // HTML
        const html: string = ExportUtils.buildHtml(topicTitle, safeShareUrl, ids, postsById, onProgress);
        const fileName: string = ExportUtils.buildFileName(topicTitle, topicId, 'html');
        const path: string = ExportUtils.joinPath(safeCacheDir, fileName);
        ExportUtils.writeTextFile(path, html);
        res.ok = true;
        res.filePath = path;
        res.fileUri = ExportUtils.toFileUri(path);
        return res;
      }

      // MD
      const md: string = await ExportUtils.buildMarkdown(
        apiClient,
        topicTitle,
        safeShareUrl,
        ids,
        postsById,
        onProgress
      );
      const fileName: string = ExportUtils.buildFileName(topicTitle, topicId, 'md');
      const path: string = ExportUtils.joinPath(safeCacheDir, fileName);
      ExportUtils.writeTextFile(path, md);
      res.ok = true;
      res.filePath = path;
      res.fileUri = ExportUtils.toFileUri(path);
      return res;
    } catch (err) {
      hilog.error(0x0000, TAG, 'exportTopicToFile failed: %{public}s', JSON.stringify(err));
      res.errorMessage = '导出失败';
      return res;
    }
  }

  private static joinPath(dir: string, name: string): string {
    const d: string = dir !== undefined && dir !== null ? dir.trim() : '';
    const n: string = name !== undefined && name !== null ? name.trim() : '';
    if (d.length === 0) return n;
    if (d.endsWith('/') || d.endsWith('\\\\')) return `${d}${n}`;
    return `${d}/${n}`;
  }

  private static toFileUri(path: string): string {
    const p: string = path !== undefined && path !== null ? path.trim() : '';
    if (p.length === 0) return '';
    return p.startsWith('file://') ? p : `file://${p}`;
  }

  private static writeTextFile(path: string, content: string): void {
    const f = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    fileIo.writeSync(f.fd, content);
    fileIo.closeSync(f);
  }

  private static sanitizeFileName(name: string): string {
    const raw: string = name !== undefined && name !== null ? name.trim() : '';
    if (raw.length === 0) return 'topic';
    // Windows/通用非法字符
    let out: string = raw.replace(/[\\\/:\*\?"<>\|]/g, '_');
    out = out.replace(/\s+/g, ' ');
    out = out.replace(/\.+$/g, '');
    out = out.trim();
    if (out.length === 0) return 'topic';
    // 避免过长
    if (out.length > 60) out = out.substring(0, 60).trim();
    return out.length > 0 ? out : 'topic';
  }

  private static buildFileName(title: string, topicId: number, ext: string): string {
    const safeTitle: string = ExportUtils.sanitizeFileName(title);
    const safeExt: string = ext !== undefined && ext !== null ? ext.trim().toLowerCase() : '';
    const suffix: string = safeExt.length > 0 ? safeExt : 'txt';
    return `${safeTitle}_${topicId}_${Date.now()}.${suffix}`;
  }

  private static async fetchPostsByIds(apiClient: ApiClient, topicId: number, ids: number[]): Promise<Map<number, Post>> {
    const map: Map<number, Post> = new Map();
    if (ids.length === 0) return map;

    const pending: number[] = [];
    for (let i = 0; i < ids.length; i++) {
      const id: number = ids[i];
      if (id <= 0) continue;
      pending.push(id);
    }

    for (let i = 0; i < pending.length; i += POSTS_BATCH_SIZE) {
      const batch: number[] = pending.slice(i, Math.min(pending.length, i + POSTS_BATCH_SIZE));
      try {
        const posts: Post[] = await apiClient.getTopicPosts(topicId, batch);
        for (let j = 0; j < posts.length; j++) {
          const p: Post = posts[j];
          if (p.id > 0 && !map.has(p.id)) {
            map.set(p.id, p);
          }
        }
      } catch (err) {
        hilog.warn(0x0000, TAG, 'fetchPostsByIds batch failed: %{public}s', JSON.stringify(err));
      }
    }

    return map;
  }

  private static escapeHtml(text: string): string {
    const s: string = text !== undefined && text !== null ? text : '';
    return s
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/\"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  private static fixRelativeUrls(html: string): string {
    const raw: string = html !== undefined && html !== null ? html : '';
    if (raw.length === 0) return '';

    // 仅修复明显的相对 src/href，避免误伤 cooked 中的其它内容
    let out: string = raw;
    out = out.replace(/src=\"(\/[^\"]*)\"/gi, (_: string, p1: string): string => {
      return `src=\"${UrlUtils.resolveUrl(p1)}\"`;
    });
    out = out.replace(/href=\"(\/[^\"]*)\"/gi, (_: string, p1: string): string => {
      return `href=\"${UrlUtils.resolveUrl(p1)}\"`;
    });
    out = out.replace(/src='(\/[^']*)'/gi, (_: string, p1: string): string => {
      return `src='${UrlUtils.resolveUrl(p1)}'`;
    });
    out = out.replace(/href='(\/[^']*)'/gi, (_: string, p1: string): string => {
      return `href='${UrlUtils.resolveUrl(p1)}'`;
    });
    return out;
  }

  private static buildHtml(
    title: string,
    shareUrl: string,
    ids: number[],
    postsById: Map<number, Post>,
    onProgress: (current: number, total: number) => void
  ): string {
    const safeTitle: string = title !== undefined && title !== null ? title : '';
    const escapedTitle: string = ExportUtils.escapeHtml(safeTitle);

    let exported: number = 0;
    onProgress(exported, ids.length);

    let body: string = '';
    for (let i = 0; i < ids.length; i++) {
      const id: number = ids[i];
      if (!postsById.has(id)) {
        continue;
      }
      const p: Post = postsById.get(id) as Post;
      const cooked: string = ExportUtils.fixRelativeUrls(p.cooked);
      const nameText: string = p.name !== null && (p.name as string).length > 0 ? (p.name as string) : p.username;
      const header: string = `<h2>#${p.postNumber} ${ExportUtils.escapeHtml(nameText)} (@${ExportUtils.escapeHtml(p.username)})</h2>`;
      body = `${body}<hr/>${header}<div>${cooked}</div>`;

      exported = exported + 1;
      onProgress(exported, ids.length);
    }

    const sourceLine: string = `<p>来源：<a href="${ExportUtils.escapeHtml(shareUrl)}">${ExportUtils.escapeHtml(shareUrl)}</a></p>`;
    return `<!doctype html><html><head><meta charset="utf-8"/><title>${escapedTitle}</title></head><body><h1>${escapedTitle}</h1>${sourceLine}${body}</body></html>`;
  }

  private static decodeHtmlEntities(text: string): string {
    let result: string = text;
    result = result.replace(/&nbsp;/g, ' ');
    result = result.replace(/&lt;/g, '<');
    result = result.replace(/&gt;/g, '>');
    result = result.replace(/&amp;/g, '&');
    result = result.replace(/&quot;/g, '"');
    result = result.replace(/&#39;/g, '\'');

    result = result.replace(/&#x([0-9a-fA-F]+);/g, (m: string, hex: string): string => {
      const code: number = parseInt(hex, 16);
      if (isNaN(code)) return m;
      try {
        return String.fromCodePoint(code);
      } catch (_) {
        return m;
      }
    });

    result = result.replace(/&#([0-9]+);/g, (m: string, dec: string): string => {
      const code: number = parseInt(dec, 10);
      if (isNaN(code)) return m;
      try {
        return String.fromCodePoint(code);
      } catch (_) {
        return m;
      }
    });

    return result;
  }

  private static stripHtmlKeepLines(html: string): string {
    const raw: string = html !== undefined && html !== null ? html : '';
    if (raw.length === 0) return '';
    let result: string = raw;
    result = result.replace(/<br\s*\/?>/g, '\n');
    result = result.replace(/<\/?p[^>]*>/g, '\n');
    result = result.replace(/<[^>]*>/g, '');
    result = ExportUtils.decodeHtmlEntities(result);
    result = result.replace(/\n{3,}/g, '\n\n');
    return result.trim();
  }

  private static async buildMarkdown(
    apiClient: ApiClient,
    title: string,
    shareUrl: string,
    ids: number[],
    postsById: Map<number, Post>,
    onProgress: (current: number, total: number) => void
  ): Promise<string> {
    const safeTitle: string = title !== undefined && title !== null ? title : '';
    let out: string = `# ${safeTitle}\n\n来源：${shareUrl}\n\n---\n`;

    let exported: number = 0;
    onProgress(exported, ids.length);

    for (let i = 0; i < ids.length; i++) {
      const id: number = ids[i];

      let meta: Post | null = null;
      if (postsById.has(id)) {
        meta = postsById.get(id) as Post;
      }

      const raw: string = await apiClient.getPostRaw(id);
      const content: string = raw.trim().length > 0
        ? raw.trim()
        : (meta !== null ? ExportUtils.stripHtmlKeepLines((meta as Post).cooked) : '');

      let header: string = `## #${i + 1}\n\n`;
      if (meta !== null) {
        header = `## #${(meta as Post).postNumber} @${(meta as Post).username}\n\n`;
      }

      out = `${out}\n${header}${content}\n\n---\n`;

      exported = exported + 1;
      onProgress(exported, ids.length);
    }

    return out.trim();
  }
}
