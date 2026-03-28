import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { PreferencesUtil } from '../services/storage/PreferencesUtil';
import { WindowManager } from '../common/utils/WindowManager';
import { CfClearanceRefreshService } from '../services/network/CfClearanceRefreshService';
import { AppContext } from '../common/utils/AppContext';
import { AppLogService } from '../common/utils/AppLogService';
import { FeatureSettingsService } from '../services/storage/FeatureSettingsService';

const DOMAIN = 0x0000;

interface WindowStageLike {
  getMainWindow?: () => Promise<window.Window>;
  getMainWindowSync?: () => window.Window;
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    PreferencesUtil.init(this.context);
    try {
      AppContext.setUIAbilityContext(this.context as common.UIAbilityContext);
    } catch (_) {
    }
    AppLogService.getInstance().info('lifecycle', 'ability onCreate', 'EntryAbility');
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

  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, 'testTag', 'Color mode updated: %{public}s', JSON.stringify(newConfig.colorMode));
    WindowManager.refreshCurrentSystemChrome(newConfig.colorMode);
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    AppLogService.getInstance().info('lifecycle', 'ability onForeground', 'EntryAbility');
    try {
      CfClearanceRefreshService.getInstance().resume();
    } catch (_) {
    }
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    AppLogService.getInstance().info('lifecycle', 'ability onBackground', 'EntryAbility');
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
        WindowManager.applyDefaultSystemChrome(this.context.config.colorMode);
        FeatureSettingsService.getInstance().replayPortraitLockPreference().catch((err: Object) => {
          hilog.error(DOMAIN, 'testTag', 'Replay portrait lock failed. Cause: %{public}s', JSON.stringify(err));
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
          WindowManager.applyDefaultSystemChrome(this.context.config.colorMode);
          FeatureSettingsService.getInstance().replayPortraitLockPreference().catch((err: Object) => {
            hilog.error(DOMAIN, 'testTag', 'Replay portrait lock failed. Cause: %{public}s', JSON.stringify(err));
          });
        })
        .catch((err: Object) => {
          hilog.error(DOMAIN, 'testTag', 'Init main window failed. Cause: %{public}s', JSON.stringify(err));
        });
      return;
    }
  }
}
