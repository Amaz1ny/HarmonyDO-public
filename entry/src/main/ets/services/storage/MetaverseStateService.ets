import { AuthService } from '../auth/AuthService';
import { CdkOAuthService } from '../network/CdkOAuthService';
import { LdcOAuthService } from '../network/LdcOAuthService';
import { CdkUserInfo, LdcUserInfo } from '../../models/Metaverse';
import { PreferencesUtil } from './PreferencesUtil';
import { AppLogStore } from './AppLogStore';

const LDC_ENABLED_KEY: string = 'metaverse.ldc.enabled';
const CDK_ENABLED_KEY: string = 'metaverse.cdk.enabled';
const LDC_INFO_KEY: string = 'metaverse.ldc.info';
const CDK_INFO_KEY: string = 'metaverse.cdk.info';
const LDC_OWNER_KEY: string = 'metaverse.ldc.owner';
const CDK_OWNER_KEY: string = 'metaverse.cdk.owner';

export class MetaverseStateService {
  private static instance: MetaverseStateService | null = null;

  private ldcEnabled: boolean = false;
  private cdkEnabled: boolean = false;
  private ldcInfo: LdcUserInfo | null = null;
  private cdkInfo: CdkUserInfo | null = null;
  private listeners: Set<() => void> = new Set();
  private initPromise: Promise<void> | null = null;

  static getInstance(): MetaverseStateService {
    if (MetaverseStateService.instance === null) {
      MetaverseStateService.instance = new MetaverseStateService();
    }
    return MetaverseStateService.instance;
  }

  ensureInit(): Promise<void> {
    if (this.initPromise !== null) {
      return this.initPromise;
    }
    this.initPromise = (async () => {
      await PreferencesUtil.ensureInit();
      await AuthService.getInstance().init();
      this.ldcEnabled = await PreferencesUtil.getBoolean(LDC_ENABLED_KEY, false);
      this.cdkEnabled = await PreferencesUtil.getBoolean(CDK_ENABLED_KEY, false);
      this.ldcInfo = await this.loadLdcInfo();
      this.cdkInfo = await this.loadCdkInfo();
    })();
    return this.initPromise;
  }

  addListener(listener: () => void): void {
    this.listeners.add(listener);
  }

  removeListener(listener: () => void): void {
    this.listeners.delete(listener);
  }

  isLdcEnabled(): boolean {
    return this.ldcEnabled;
  }

  isCdkEnabled(): boolean {
    return this.cdkEnabled;
  }

  getLdcInfo(): LdcUserInfo | null {
    return this.ldcInfo;
  }

  getCdkInfo(): CdkUserInfo | null {
    return this.cdkInfo;
  }

  async setLdcEnabled(enabled: boolean): Promise<void> {
    await this.ensureInit();
    this.ldcEnabled = enabled;
    await PreferencesUtil.putBoolean(LDC_ENABLED_KEY, enabled);
    if (!enabled) {
      this.ldcInfo = null;
      await this.clearLdcCache();
    }
    this.notifyChanged();
  }

  async setCdkEnabled(enabled: boolean): Promise<void> {
    await this.ensureInit();
    this.cdkEnabled = enabled;
    await PreferencesUtil.putBoolean(CDK_ENABLED_KEY, enabled);
    if (!enabled) {
      this.cdkInfo = null;
      await this.clearCdkCache();
    }
    this.notifyChanged();
  }

  async refreshLdc(): Promise<LdcUserInfo | null> {
    await this.ensureInit();
    const owner: string = this.getCurrentOwner();
    if (!this.ldcEnabled || owner.length === 0) {
      this.ldcInfo = null;
      await this.clearLdcCache();
      this.notifyChanged();
      return null;
    }
    const info: LdcUserInfo | null = await new LdcOAuthService().getUserInfo();
    this.ldcInfo = info;
    if (info !== null) {
      const persistedOwner: string = info.username.trim().length > 0 ? info.username.trim().toLowerCase() : owner;
      await PreferencesUtil.putString(LDC_INFO_KEY, JSON.stringify(info.toJson()));
      await PreferencesUtil.putString(LDC_OWNER_KEY, persistedOwner);
      AppLogStore.getInstance().info('METAVERSE', `refresh ldc success owner=${persistedOwner}`);
    } else {
      await this.clearLdcCache();
      AppLogStore.getInstance().warn('METAVERSE', 'refresh ldc returned empty user info');
    }
    this.notifyChanged();
    return info;
  }

  async refreshCdk(): Promise<CdkUserInfo | null> {
    await this.ensureInit();
    const owner: string = this.getCurrentOwner();
    if (!this.cdkEnabled || owner.length === 0) {
      this.cdkInfo = null;
      await this.clearCdkCache();
      this.notifyChanged();
      return null;
    }
    const info: CdkUserInfo | null = await new CdkOAuthService().getUserInfo();
    this.cdkInfo = info;
    if (info !== null) {
      const persistedOwner: string = info.username.trim().length > 0 ? info.username.trim().toLowerCase() : owner;
      await PreferencesUtil.putString(CDK_INFO_KEY, JSON.stringify(info.toJson()));
      await PreferencesUtil.putString(CDK_OWNER_KEY, persistedOwner);
      AppLogStore.getInstance().info('METAVERSE', `refresh cdk success owner=${persistedOwner}`);
    } else {
      await this.clearCdkCache();
      AppLogStore.getInstance().warn('METAVERSE', 'refresh cdk returned empty user info');
    }
    this.notifyChanged();
    return info;
  }

  private async loadLdcInfo(): Promise<LdcUserInfo | null> {
    const owner: string = this.getCurrentOwner();
    if (owner.length === 0) {
      await this.clearLdcCache();
      return null;
    }
    const cachedOwner: string = (await PreferencesUtil.getString(LDC_OWNER_KEY, '')).trim().toLowerCase();
    if (cachedOwner.length > 0 && cachedOwner !== owner) {
      await this.clearLdcCache();
      return null;
    }
    const raw: string = await PreferencesUtil.getString(LDC_INFO_KEY, '');
    if (raw.trim().length === 0) {
      return null;
    }
    try {
      const parsed: Object = JSON.parse(raw) as Object;
      if (parsed !== null && parsed !== undefined && typeof parsed === 'object' && !Array.isArray(parsed)) {
        return LdcUserInfo.fromJson(parsed as Record<string, Object>);
      }
    } catch (_) {
    }
    await this.clearLdcCache();
    return null;
  }

  private async loadCdkInfo(): Promise<CdkUserInfo | null> {
    const owner: string = this.getCurrentOwner();
    if (owner.length === 0) {
      await this.clearCdkCache();
      return null;
    }
    const cachedOwner: string = (await PreferencesUtil.getString(CDK_OWNER_KEY, '')).trim().toLowerCase();
    if (cachedOwner.length > 0 && cachedOwner !== owner) {
      await this.clearCdkCache();
      return null;
    }
    const raw: string = await PreferencesUtil.getString(CDK_INFO_KEY, '');
    if (raw.trim().length === 0) {
      return null;
    }
    try {
      const parsed: Object = JSON.parse(raw) as Object;
      if (parsed !== null && parsed !== undefined && typeof parsed === 'object' && !Array.isArray(parsed)) {
        return CdkUserInfo.fromJson(parsed as Record<string, Object>);
      }
    } catch (_) {
    }
    await this.clearCdkCache();
    return null;
  }

  private async clearLdcCache(): Promise<void> {
    await PreferencesUtil.delete(LDC_INFO_KEY);
    await PreferencesUtil.delete(LDC_OWNER_KEY);
  }

  private async clearCdkCache(): Promise<void> {
    await PreferencesUtil.delete(CDK_INFO_KEY);
    await PreferencesUtil.delete(CDK_OWNER_KEY);
  }

  private getCurrentOwner(): string {
    return AuthService.getInstance().getCurrentUsername().trim().toLowerCase();
  }

  private notifyChanged(): void {
    this.listeners.forEach((listener: () => void) => {
      listener();
    });
  }
}
