import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import { hilog } from '@kit.PerformanceAnalysisKit';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import { common } from '@kit.AbilityKit';

const TAG: string = 'MediaSaveService';
const PERMISSION_WRITE_IMAGEVIDEO: Permissions = 'ohos.permission.WRITE_IMAGEVIDEO' as Permissions;

export class MediaSaveService {
  private static async ensureWritePermission(ctx: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(ctx, [PERMISSION_WRITE_IMAGEVIDEO]);
      if (result.authResults.length === 0) {
        return false;
      }
      for (let i = 0; i < result.authResults.length; i++) {
        if (result.authResults[i] !== 0) {
          return false;
        }
      }
      return true;
    } catch (err) {
      hilog.warn(0x0000, TAG, 'ensureWritePermission failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  private static sanitizeTitle(title: string): string {
    const raw: string = title !== undefined && title !== null ? title.trim() : '';
    if (raw.length === 0) return 'share_image';
    let out: string = raw.replace(/[\\\/:\*\?"<>\|]/g, '_');
    out = out.replace(/\s+/g, ' ').trim();
    if (out.length === 0) return 'share_image';
    if (out.length > 60) out = out.substring(0, 60).trim();
    return out.length > 0 ? out : 'share_image';
  }

  private static normalizeImageExt(mimeOrExt: string): string {
    const raw: string = mimeOrExt !== undefined && mimeOrExt !== null ? mimeOrExt.toString().trim().toLowerCase() : '';
    if (raw.length === 0) return 'jpg';

    // mime -> ext
    if (raw.indexOf('/') >= 0) {
      if (raw.startsWith('image/png')) return 'png';
      if (raw.startsWith('image/jpeg') || raw.startsWith('image/jpg')) return 'jpg';
      if (raw.startsWith('image/webp')) return 'webp';
      if (raw.startsWith('image/gif')) return 'gif';
      if (raw.startsWith('image/bmp')) return 'bmp';
      return 'jpg';
    }

    // ext
    let ext: string = raw;
    if (ext.startsWith('.')) ext = ext.substring(1);
    if (ext === 'jpeg') ext = 'jpg';
    if (!/^[a-z0-9]+$/.test(ext)) return 'jpg';
    if (ext.length < 2 || ext.length > 5) return 'jpg';
    return ext;
  }

  static async saveImageBytesToGallery(
    ctx: common.UIAbilityContext,
    bytes: ArrayBuffer,
    mimeOrExt: string,
    title: string
  ): Promise<boolean> {
    if (bytes === undefined || bytes === null || bytes.byteLength <= 0) {
      return false;
    }

    const granted: boolean = await MediaSaveService.ensureWritePermission(ctx);
    if (!granted) {
      return false;
    }

    try {
      const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(ctx);
      const safeTitle: string = MediaSaveService.sanitizeTitle(title);
      const ext: string = MediaSaveService.normalizeImageExt(mimeOrExt);
      const request: photoAccessHelper.MediaAssetChangeRequest = photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(
        ctx,
        photoAccessHelper.PhotoType.IMAGE,
        ext,
        { title: safeTitle }
      );
      request.addResource(photoAccessHelper.ResourceType.IMAGE_RESOURCE, bytes);
      await helper.applyChanges(request);
      try {
        await helper.release();
      } catch (_) {
      }
      return true;
    } catch (err) {
      hilog.error(0x0000, TAG, 'saveImageBytesToGallery failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  static async savePngToGallery(
    ctx: common.UIAbilityContext,
    pngBuffer: ArrayBuffer,
    title: string
  ): Promise<boolean> {
    return await MediaSaveService.saveImageBytesToGallery(ctx, pngBuffer, 'png', title);
  }
}
