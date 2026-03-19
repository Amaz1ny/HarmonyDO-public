import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN: number = 0x0000;
const TAG: string = 'WindowManager';

type SystemBarName = 'status' | 'navigation';

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

  static init(mainWindow: window.Window): void {
    WindowManager.mainWindow = mainWindow;

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

  static applyPortraitLock(enabled: boolean): void {
    const win: window.Window | null = WindowManager.mainWindow;
    if (win === null) return;

    const adapter: WindowSystemBarLike = win as WindowSystemBarLike;
    if (adapter.setPreferredOrientation === undefined) return;

    let value: number | undefined = undefined;
    if (enabled) {
      value = window.Orientation.PORTRAIT;
    } else if (window.Orientation.AUTO_ROTATION !== undefined) {
      value = window.Orientation.AUTO_ROTATION;
    } else {
      value = window.Orientation.UNSPECIFIED;
    }
    if (value === undefined) {
      return;
    }
    adapter.setPreferredOrientation(value).catch((err: Object) => {
      hilog.error(DOMAIN, TAG, 'setPreferredOrientation failed. Cause: %{public}s', JSON.stringify(err));
    });
  }
}
