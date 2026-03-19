import fileIo from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from './AppContext';
import { UrlUtils } from './UrlUtils';
import { HttpBinaryResponse, HttpClient } from '../../services/network/HttpClient';

const TAG: string = 'ImageDownloadService';

export class DownloadedImage {
  ok: boolean = false;
  url: string = '';
  fileUri: string = '';
  mime: string = '';
  ext: string = '';
  bytes: ArrayBuffer | null = null;
  errorMessage: string = '';

  constructor() {
  }
}

function joinPath(dir: string, name: string): string {
  const d: string = dir !== undefined && dir !== null ? dir.trim() : '';
  const n: string = name !== undefined && name !== null ? name.trim() : '';
  if (d.length === 0) return n;
  if (d.endsWith('/') || d.endsWith('\\')) return `${d}${n}`;
  return `${d}/${n}`;
}

function getHeaderValue(headerObj: Object | null, name: string): string {
  if (headerObj === null) return '';
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

function normalizeContentType(raw: string): string {
  const s: string = raw !== undefined && raw !== null ? raw.trim().toLowerCase() : '';
  if (s.length === 0) return '';
  const semi: number = s.indexOf(';');
  if (semi >= 0) return s.substring(0, semi).trim();
  return s;
}

function guessExtFromMime(mime: string): string {
  const m: string = mime !== undefined && mime !== null ? mime.trim().toLowerCase() : '';
  if (m === 'image/png') return 'png';
  if (m === 'image/jpeg') return 'jpg';
  if (m === 'image/jpg') return 'jpg';
  if (m === 'image/webp') return 'webp';
  if (m === 'image/gif') return 'gif';
  if (m === 'image/bmp') return 'bmp';
  return '';
}

function guessExtFromUrl(url: string): string {
  const raw: string = url !== undefined && url !== null ? url.trim() : '';
  if (raw.length === 0) return '';
  let path: string = raw;
  const q: number = path.indexOf('?');
  if (q >= 0) path = path.substring(0, q);
  const dot: number = path.lastIndexOf('.');
  if (dot < 0) return '';
  const ext: string = path.substring(dot + 1).toLowerCase().trim();
  if (ext.length < 2 || ext.length > 5) return '';
  if (!/^[a-z0-9]+$/.test(ext)) return '';
  if (ext === 'jpeg') return 'jpg';
  return ext;
}

function hashString(input: string): number {
  const s: string = input !== undefined && input !== null ? input : '';
  let h: number = 0;
  for (let i = 0; i < s.length; i++) {
    h = ((h << 5) - h) + s.charCodeAt(i);
    h = h | 0;
  }
  return Math.abs(h);
}

export class ImageDownloadService {
  static async download(url: string): Promise<DownloadedImage> {
    const out: DownloadedImage = new DownloadedImage();
    const raw: string = url !== undefined && url !== null ? url.trim() : '';
    if (raw.length === 0) {
      out.errorMessage = '图片链接为空';
      return out;
    }

    const full: string = raw.startsWith('http') || raw.startsWith('file://') ? raw : UrlUtils.resolveUrl(raw);
    out.url = full;

    const ctx = AppContext.getUIAbilityContext();
    if (ctx === null) {
      out.errorMessage = '系统能力不可用';
      return out;
    }

    try {
      const client: HttpClient = new HttpClient();
      const resp: HttpBinaryResponse = await client.getBinaryByUrl(full, 'image/*', null, null, 60000);
      const bytes: ArrayBuffer = resp.bytes;
      if (bytes === undefined || bytes === null || bytes.byteLength <= 0) {
        out.errorMessage = '下载失败（空数据）';
        return out;
      }

      const ctRaw: string = normalizeContentType(getHeaderValue(resp.header, 'content-type'));
      const mime: string = ctRaw.length > 0 ? ctRaw : 'image/*';
      let ext: string = guessExtFromMime(mime);
      if (ext.length === 0) {
        ext = guessExtFromUrl(full);
      }
      if (ext.length === 0) {
        ext = 'jpg';
      }

      const hash: number = hashString(full);
      const name: string = `harmonydo_img_${hash}.${ext}`;
      const cacheDir: string = ctx.cacheDir;
      const path: string = joinPath(cacheDir, name);

      const f = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, bytes);
      fileIo.closeSync(f);

      out.ok = true;
      out.mime = mime;
      out.ext = ext;
      out.bytes = bytes;
      out.fileUri = path.startsWith('file://') ? path : `file://${path}`;
      return out;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Download image failed: %{public}s', JSON.stringify(err));
      out.errorMessage = '下载失败';
      return out;
    }
  }
}

