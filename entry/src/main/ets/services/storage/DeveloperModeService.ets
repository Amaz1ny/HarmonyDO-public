import { PreferencesUtil } from './PreferencesUtil';

const DEVELOPER_MODE_KEY: string = 'developer_mode';

export class DeveloperModeService {
  private static instance: DeveloperModeService | null = null;
  private enabled: boolean = false;
  private listeners: Set<() => void> = new Set();
  private initPromise: Promise<void> | null = null;

  static getInstance(): DeveloperModeService {
    if (DeveloperModeService.instance === null) {
      DeveloperModeService.instance = new DeveloperModeService();
    }
    return DeveloperModeService.instance;
  }

  ensureInit(): Promise<void> {
    if (this.initPromise !== null) {
      return this.initPromise;
    }
    this.initPromise = (async () => {
      await PreferencesUtil.ensureInit();
      this.enabled = await PreferencesUtil.getBoolean(DEVELOPER_MODE_KEY, false);
    })();
    return this.initPromise;
  }

  addListener(listener: () => void): void {
    this.listeners.add(listener);
  }

  removeListener(listener: () => void): void {
    this.listeners.delete(listener);
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  async setEnabled(enabled: boolean): Promise<void> {
    await this.ensureInit();
    this.enabled = enabled;
    await PreferencesUtil.putBoolean(DEVELOPER_MODE_KEY, enabled);
    this.listeners.forEach((listener: () => void) => {
      listener();
    });
  }
}
