import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppContext } from './AppContext';

const DOMAIN: number = 0x0000;
const TAG: string = 'WindowManager';
const TRANSPARENT_COLOR: string = '#00000000';
const LIGHT_WINDOW_BACKGROUND: string = '#FFFFFF';
const DARK_WINDOW_BACKGROUND: string = '#121212';
const LIGHT_NAVIGATION_SURFACE: string = '#FFFFFF';
const DARK_NAVIGATION_SURFACE: string = '#1E1E1E';
const LIGHT_SYSTEM_CONTENT: string = '#000000';
const DARK_SYSTEM_CONTENT: string = '#FFFFFF';

type SystemBarName = 'status' | 'navigation';
type SystemChromeStyle = 'default' | 'profile_header';

interface UIContextLike {
  px2vp: (value: number) => number;
}

interface WindowUIContextLike {
  getUIContext?: () => UIContextLike | null | undefined;
}

interface SystemBarPropertiesLike {
  statusBarColor?: string;
  navigationBarColor?: string;
  statusBarContentColor?: string;
  navigationBarContentColor?: string;
}

interface WindowSystemBarLike {
  setWindowSystemBarProperties?: (properties: SystemBarPropertiesLike) => Promise<void>;
  setSystemBarProperties?: (properties: SystemBarPropertiesLike) => Promise<void>;
  setWindowLayoutFullScreen?: (isLayoutFullScreen: boolean) => Promise<void>;
  setWindowSystemBarEnable?: (names: SystemBarName[]) => Promise<void>;
  setWindowBackgroundColor?: (color: string) => void;
  getWindowAvoidArea?: (type: window.AvoidAreaType) => window.AvoidArea;
  setPreferredOrientation?: (orientation: number) => Promise<void>;
}

export class WindowManager {
  private static mainWindow: window.Window | null = null;
  private static currentChromeStyle: SystemChromeStyle = 'default';

  static init(mainWindow: window.Window): void {
    WindowManager.mainWindow = mainWindow;
  }

  private static getCurrentColorMode(): number {
    try {
      const ctx = AppContext.getUIAbilityContext();
      if (ctx !== null && ctx.config !== undefined) {
        const colorMode: number | undefined = ctx.config.colorMode;
        if (colorMode !== undefined) {
          return colorMode;
        }
      }
    } catch (_) {
    }
    return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }

  static isDarkMode(colorMode?: number): boolean {
    const resolvedColorMode: number = colorMode === undefined ? WindowManager.getCurrentColorMode() : colorMode;
    return resolvedColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private static getWindowBackgroundHex(colorMode?: number): string {
    return WindowManager.isDarkMode(colorMode) ? DARK_WINDOW_BACKGROUND : LIGHT_WINDOW_BACKGROUND;
  }

  private static getNavigationSurfaceHex(colorMode?: number): string {
    return WindowManager.isDarkMode(colorMode) ? DARK_NAVIGATION_SURFACE : LIGHT_NAVIGATION_SURFACE;
  }

  private static getSystemContentHex(colorMode?: number): string {
    return WindowManager.isDarkMode(colorMode) ? DARK_SYSTEM_CONTENT : LIGHT_SYSTEM_CONTENT;
  }

  static applyDefaultSystemChrome(colorMode?: number): void {
    WindowManager.currentChromeStyle = 'default';
    WindowManager.setWindowLayoutFullScreen(true);
    WindowManager.setWindowBackgroundColor(WindowManager.getWindowBackgroundHex(colorMode));
    const navigationColor: string = WindowManager.getNavigationSurfaceHex(colorMode);
    const contentColor: string = WindowManager.getSystemContentHex(colorMode);
    WindowManager.setSystemBarStyle(TRANSPARENT_COLOR, navigationColor, contentColor, contentColor);
  }

  static applyProfileHeaderSystemChrome(colorMode?: number): void {
    WindowManager.currentChromeStyle = 'profile_header';
    WindowManager.setWindowLayoutFullScreen(true);
    WindowManager.setWindowBackgroundColor(WindowManager.getWindowBackgroundHex(colorMode));
    const navigationColor: string = WindowManager.getNavigationSurfaceHex(colorMode);
    const navigationContentColor: string = WindowManager.getSystemContentHex(colorMode);
    WindowManager.setSystemBarStyle(TRANSPARENT_COLOR, navigationColor, DARK_SYSTEM_CONTENT, navigationContentColor);
  }

  static refreshCurrentSystemChrome(colorMode?: number): void {
    if (WindowManager.currentChromeStyle === 'profile_header') {
      WindowManager.applyProfileHeaderSystemChrome(colorMode);
      return;
    }
    WindowManager.applyDefaultSystemChrome(colorMode);
  }

  static async applyPortraitLock(enabled: boolean): Promise<void> {
    const win: window.Window | null = WindowManager.mainWindow;
    if (win === null) {
      return;
    }
    const adapter: WindowSystemBarLike = win as WindowSystemBarLike;
    if (adapter.setPreferredOrientation === undefined) {
      return;
    }
    const orientation: number = enabled
      ? window.Orientation.PORTRAIT
      : window.Orientation.AUTO_ROTATION;
    await adapter.setPreferredOrientation(orientation);
  }

  private static pxToVp(px: number): number {
    const win: window.Window | null = WindowManager.mainWindow;

    if (win === null) return 0;

    const adapter: WindowUIContextLike = win as WindowUIContextLike;
    if (adapter.getUIContext === undefined) return 0;

    try {
      const uiContext: UIContextLike | null | undefined = adapter.getUIContext();
      if (uiContext === undefined || uiContext === null) return 0;
      return uiContext.px2vp(px);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'pxToVp failed. Cause: %{public}s', JSON.stringify(err));
      return 0;
    }
  }

  static setSystemBarColors(statusBarColor: string, navigationBarColor: string): void {
    const win: window.Window | null = WindowManager.mainWindow;
    if (win === null) return;

    const adapter: WindowSystemBarLike = win as WindowSystemBarLike;
    const props: SystemBarPropertiesLike = {
      statusBarColor: statusBarColor,
      navigationBarColor: navigationBarColor
    };

    if (adapter.setWindowSystemBarProperties !== undefined) {
      adapter.setWindowSystemBarProperties(props).catch((err: Object) => {
        hilog.error(DOMAIN, TAG, 'setWindowSystemBarProperties failed. Cause: %{public}s', JSON.stringify(err));
      });
      return;
    }

    if (adapter.setSystemBarProperties !== undefined) {
      adapter.setSystemBarProperties(props).catch((err: Object) => {
        hilog.error(DOMAIN, TAG, 'setSystemBarProperties failed. Cause: %{public}s', JSON.stringify(err));
      });
    }
  }

  static setSystemBarStyle(statusBarColor: string, navigationBarColor: string, statusBarContentColor: string,
    navigationBarContentColor: string): void {
    const win: window.Window | null = WindowManager.mainWindow;
    if (win === null) return;

    const adapter: WindowSystemBarLike = win as WindowSystemBarLike;
    const props: SystemBarPropertiesLike = {
      statusBarColor: statusBarColor,
      navigationBarColor: navigationBarColor,
      statusBarContentColor: statusBarContentColor,
      navigationBarContentColor: navigationBarContentColor
    };

    if (adapter.setWindowSystemBarProperties !== undefined) {
      adapter.setWindowSystemBarProperties(props).catch((err: Object) => {
        hilog.error(DOMAIN, TAG, 'setWindowSystemBarProperties failed. Cause: %{public}s', JSON.stringify(err));
      });
      return;
    }

    if (adapter.setSystemBarProperties !== undefined) {
      adapter.setSystemBarProperties(props).catch((err: Object) => {
        hilog.error(DOMAIN, TAG, 'setSystemBarProperties failed. Cause: %{public}s', JSON.stringify(err));
      });
    }
  }

  static setWindowLayoutFullScreen(isLayoutFullScreen: boolean): void {
    const win: window.Window | null = WindowManager.mainWindow;
    if (win === null) return;

    const adapter: WindowSystemBarLike = win as WindowSystemBarLike;
    if (adapter.setWindowLayoutFullScreen === undefined) return;

    adapter.setWindowLayoutFullScreen(isLayoutFullScreen).catch((err: Object) => {
      hilog.error(DOMAIN, TAG, 'setWindowLayoutFullScreen failed. Cause: %{public}s', JSON.stringify(err));
    });
  }

  static setWindowSystemBarEnable(names: SystemBarName[]): void {
    const win: window.Window | null = WindowManager.mainWindow;
    if (win === null) return;

    const adapter: WindowSystemBarLike = win as WindowSystemBarLike;
    if (adapter.setWindowSystemBarEnable === undefined) return;

    adapter.setWindowSystemBarEnable(names).catch((err: Object) => {
      hilog.error(DOMAIN, TAG, 'setWindowSystemBarEnable failed. Cause: %{public}s', JSON.stringify(err));
    });
  }

  static setWindowBackgroundColor(color: string): void {
    const win: window.Window | null = WindowManager.mainWindow;
    if (win === null) return;

    const adapter: WindowSystemBarLike = win as WindowSystemBarLike;
    if (adapter.setWindowBackgroundColor === undefined) return;

    try {
      adapter.setWindowBackgroundColor(color);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setWindowBackgroundColor failed. Cause: %{public}s', JSON.stringify(err));
    }
  }

  static getSystemAvoidAreaTopVp(): number {
    const win: window.Window | null = WindowManager.mainWindow;
    if (win === null) return 0;

    const adapter: WindowSystemBarLike = win as WindowSystemBarLike;
    if (adapter.getWindowAvoidArea === undefined) return 0;

    try {
      const avoidArea: window.AvoidArea = adapter.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      return WindowManager.pxToVp(avoidArea.topRect.height);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'getWindowAvoidArea failed. Cause: %{public}s', JSON.stringify(err));
      return 0;
    }
  }

  static getSystemAvoidAreaBottomVp(): number {
    const win: window.Window | null = WindowManager.mainWindow;
    if (win === null) return 0;

    const adapter: WindowSystemBarLike = win as WindowSystemBarLike;
    if (adapter.getWindowAvoidArea === undefined) return 0;

    try {
      const avoidArea: window.AvoidArea = adapter.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      return WindowManager.pxToVp(avoidArea.bottomRect.height);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'getWindowAvoidArea failed. Cause: %{public}s', JSON.stringify(err));
      return 0;
    }
  }
}
