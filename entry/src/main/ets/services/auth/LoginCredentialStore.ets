import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'LoginCredentialStore';
const CREDENTIAL_ALIAS: string = 'harmonydo_login_credential';

export interface LoginCredential {
  username: string;
  password: string;
}

export class LoginCredentialStore {
  private static instance: LoginCredentialStore | null = null;

  static getInstance(): LoginCredentialStore {
    if (LoginCredentialStore.instance === null) {
      LoginCredentialStore.instance = new LoginCredentialStore();
    }
    return LoginCredentialStore.instance;
  }

  private encode(value: string): Uint8Array {
    const encoder: util.TextEncoder = new util.TextEncoder();
    return encoder.encodeInto(value);
  }

  private decode(value: Object | undefined | null): string {
    if (value === undefined || value === null) {
      return '';
    }
    const decoder: util.TextDecoder = new util.TextDecoder('utf-8', { ignoreBOM: true });
    try {
      if (value instanceof Uint8Array) {
        return decoder.decodeToString(value);
      }
    } catch (_) {
    }
    try {
      if (value instanceof ArrayBuffer) {
        return decoder.decodeToString(new Uint8Array(value));
      }
    } catch (_) {
    }
    if (Array.isArray(value)) {
      const bytes: number[] = [];
      for (let i = 0; i < value.length; i++) {
        const item: Object = value[i] as Object;
        if (typeof item === 'number') {
          bytes.push(item as number);
        }
      }
      if (bytes.length > 0) {
        return decoder.decodeToString(Uint8Array.from(bytes));
      }
    }
    return '';
  }

  private buildAliasQuery(): asset.AssetMap {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.encode(CREDENTIAL_ALIAS));
    return query;
  }

  async saveCredential(username: string, password: string): Promise<void> {
    const safeUsername: string = username !== undefined && username !== null ? username.trim() : '';
    const safePassword: string = password !== undefined && password !== null ? password : '';
    if (safeUsername.length === 0 || safePassword.length === 0) {
      await this.clearCredential();
      return;
    }

    const payload: string = JSON.stringify({
      username: safeUsername,
      password: safePassword
    });

    const attr: asset.AssetMap = new Map();
    attr.set(asset.Tag.ALIAS, this.encode(CREDENTIAL_ALIAS));
    attr.set(asset.Tag.SECRET, this.encode(payload));

    try {
      await this.clearCredential();
      asset.addSync(attr);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Save credential failed: %{public}s', JSON.stringify(err));
      throw new Error('保存登录凭据失败');
    }
  }

  async loadCredential(): Promise<LoginCredential | null> {
    try {
      const result: Array<asset.AssetMap> = asset.querySync(this.buildAliasQuery());
      if (!Array.isArray(result) || result.length === 0) {
        return null;
      }
      const secret: Object | undefined = result[0].get(asset.Tag.SECRET);
      const raw: string = this.decode(secret);
      if (raw.trim().length === 0) {
        return null;
      }
      const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      const usernameValue: Object | undefined = parsed['username'];
      const passwordValue: Object | undefined = parsed['password'];
      const username: string = usernameValue !== undefined && usernameValue !== null ? usernameValue.toString().trim() : '';
      const password: string = passwordValue !== undefined && passwordValue !== null ? passwordValue.toString() : '';
      if (username.length === 0 || password.length === 0) {
        return null;
      }
      return {
        username: username,
        password: password
      };
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Load credential failed: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  async clearCredentialIfUsernameMismatch(username: string): Promise<void> {
    const safeUsername: string = username !== undefined && username !== null ? username.trim().toLowerCase() : '';
    if (safeUsername.length === 0) {
      return;
    }
    const current: LoginCredential | null = await this.loadCredential();
    if (current === null) {
      return;
    }
    if (current.username.trim().toLowerCase() !== safeUsername) {
      await this.clearCredential();
    }
  }

  async clearCredential(): Promise<void> {
    try {
      await asset.remove(this.buildAliasQuery());
    } catch (_) {
    }
  }
}
