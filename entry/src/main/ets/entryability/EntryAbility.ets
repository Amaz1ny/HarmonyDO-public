import { AbilityConstant, ConfigurationConstant, UIAbility, Want, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { PreferencesUtil } from '../services/storage/PreferencesUtil';
import { AppSettingsService } from '../services/storage/AppSettingsService';
import { WindowManager } from '../common/utils/WindowManager';
import { CfClearanceRefreshService } from '../services/network/CfClearanceRefreshService';
import { AppContext } from '../common/utils/AppContext';

const DOMAIN = 0x0000;

interface WindowStageLike {
  getMainWindow?: () => Promise<window.Window>;
  getMainWindowSync?: () => window.Window;
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    PreferencesUtil.init(this.context);
    try {
      AppContext.setUIAbilityContext(this.context as common.UIAbilityContext);
    } catch (_) {
    }
    AppSettingsService.getInstance().ensureInit()
      .then(() => {
        AppSettingsService.getInstance().applyThemeModeToApplication();
      })
      .catch((err: Object) => {
        hilog.error(DOMAIN, 'testTag', 'Init app settings failed. Cause: %{public}s', JSON.stringify(err));
        try {
          this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
        } catch (_) {
        }
      });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    this.initWindowManager(windowStage);

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    try {
      CfClearanceRefreshService.getInstance().resume();
    } catch (_) {
    }
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    try {
      CfClearanceRefreshService.getInstance().pause();
    } catch (_) {
    }
  }

  private initWindowManager(windowStage: window.WindowStage): void {
    const stage: WindowStageLike = windowStage as WindowStageLike;

    if (stage.getMainWindowSync !== undefined) {
      try {
        const w: window.Window = stage.getMainWindowSync();

        WindowManager.init(w);
        WindowManager.setWindowBackgroundColor('#FFFFFF');
        // 全局开启沉浸式：内容延伸到状态栏下（全面屏），并设置默认系统栏样式（浅色背景+深色图标）
        WindowManager.setWindowLayoutFullScreen(true);
        WindowManager.setSystemBarStyle('#00000000', '#FFFFFF', '#000000', '#000000');
        AppSettingsService.getInstance().ensureInit().then(() => {
          WindowManager.applyPortraitLock(AppSettingsService.getInstance().getFeatureSettings().portraitLock);
        }).catch(() => {
        });
        return;
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', 'Init main window sync failed. Cause: %{public}s', JSON.stringify(err));
      }
    }

    if (stage.getMainWindow !== undefined) {
      stage.getMainWindow()
        .then((w: window.Window) => {
          WindowManager.init(w);
          WindowManager.setWindowBackgroundColor('#FFFFFF');
          // 全局开启沉浸式：内容延伸到状态栏下（全面屏），并设置默认系统栏样式（浅色背景+深色图标）
          WindowManager.setWindowLayoutFullScreen(true);
          WindowManager.setSystemBarStyle('#00000000', '#FFFFFF', '#000000', '#000000');
          AppSettingsService.getInstance().ensureInit().then(() => {
            WindowManager.applyPortraitLock(AppSettingsService.getInstance().getFeatureSettings().portraitLock);
          }).catch(() => {
          });
        })
        .catch((err: Object) => {
          hilog.error(DOMAIN, 'testTag', 'Init main window failed. Cause: %{public}s', JSON.stringify(err));
        });
      return;
    }
  }
}
