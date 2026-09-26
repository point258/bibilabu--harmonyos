/**
 * EntryAbility.ets
 * 启动顺序（严格按此序，否则会遇到首帧闪白 / 设置不生效）：
 *   1) PreferencesStore.init       —— 打开 preferences
 *   2) bootstrapSettings/Watchlist/Session —— 页面创建前注册全局状态
 *   3) 应用用户选择的深浅色
 *   4) ImmersiveWindow.init        —— 常驻全屏 + 安全区发布
 *   5) loadContent，并在回调内 setWindowBackgroundColor
 */

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { ImmersiveWindow } from '../common/ImmersiveWindow';
import { Logger } from '../common/Logger';
import { PreferencesStore } from '../data/PreferencesStore';
import { SettingsState, bootstrapSettings } from '../state/SettingsState';
import { bootstrapWatchlist } from '../state/WatchlistState';
import { bootstrapSession } from '../state/SessionState';
import { bootstrapSteam } from '../state/SteamState';

const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  private startupDark: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 1) 打开 preferences
    PreferencesStore.init(this.context);

    // 2) 页面创建前装载全局状态
    const settings: SettingsState | undefined = bootstrapSettings();
    bootstrapWatchlist();
    bootstrapSession();
    bootstrapSteam();

    // 3) 应用用户选择的深浅色（未设置则跟随系统）
    if (settings !== undefined) {
      try {
        this.context.getApplicationContext().setColorMode(settings.colorMode);
      } catch (e) {
        Logger.err(TAG, 'setColorMode', e);
      }
    }
    this.startupDark = this.isSystemDark();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // getMainWindowSync 可能抛异常：拿不到就跳过沉浸式配置，不能因此起不来
    let mainWindow: window.Window | undefined = undefined;
    try {
      mainWindow = windowStage.getMainWindowSync();
    } catch (e) {
      Logger.err(TAG, 'getMainWindowSync', e);
    }

    // 4) 常驻全屏 + 系统栏透明 + 安全区发布
    if (mainWindow !== undefined) {
      ImmersiveWindow.init(mainWindow);
      ImmersiveWindow.setTransparentBars();
      ImmersiveWindow.applyBarContentColor(this.startupDark);
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        Logger.err(TAG, 'loadContent', err);
        return;
      }
      // 首帧底色由 module.json5 的 startWindowBackground 声明式兜底
      // （setWindowBackgroundColor 在 phone/tablet/2in1 上均被标为不可用，故不调用）
      Logger.i(TAG, '首屏已就绪');
    });
  }

  onConfigurationUpdate(): void {
    // 深浅色/语言变化：同步系统栏前景色。
    // 严禁在此回调里再调 setColorMode。
    this.startupDark = this.isSystemDark();
    ImmersiveWindow.applyBarContentColor(this.startupDark);
  }

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
  }

  onBackground(): void {
  }

  onDestroy(): void {
  }

  private isSystemDark(): boolean {
    try {
      return this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } catch (e) {
      return false;
    }
  }
}
