/**
 * ImmersiveWindow.ets — 常驻全屏沉浸窗口管理器。
 * 向状态管理 V2 发布窗口度量（安全区、系统栏前景色），供页面只读消费。
 *
 * 用法（EntryAbility.onWindowStageCreate）：
 *   const win = windowStage.getMainWindowSync();
 *   ImmersiveWindow.init(win);
 *   windowStage.loadContent('pages/Index');
 */

import { window, display } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { publishWindowMetrics } from '../state/WindowMetrics';
import { Logger } from './Logger';

const TAG: string = 'ImmersiveWindow';

/**
 * 系统栏 API 在 2in1（PC）上不生效（SDK 声明原文："This API does not take effect on
 * 2-in-1 devices"），调用它会刷无意义的告警，因此这里直接跳过。
 */
function systemBarSupported(): boolean {
  try {
    return deviceInfo.deviceType !== '2in1';
  } catch (e) {
    return true;
  }
}

export class ImmersiveWindow {
  private static win: window.Window | undefined;
  private static lastDark: boolean = false;
  /** 全屏图片预览等场景置 true，丢弃 avoidArea 归零事件，保持 padding 稳定 */
  private static suppress: boolean = false;

  /** 在 onWindowStageCreate 中调用一次，之后整个生命周期不再切换布局模式 */
  static init(win: window.Window): void {
    ImmersiveWindow.win = win;
    win.setWindowLayoutFullScreen(true).catch((e: Object) => {
      Logger.err(TAG, 'setWindowLayoutFullScreen', e);
    });
    ImmersiveWindow.applyBarContentColor(ImmersiveWindow.lastDark);
    ImmersiveWindow.syncInsets(win);
    win.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
      if (data.type === window.AvoidAreaType.TYPE_SYSTEM
        || data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
        ImmersiveWindow.syncInsets(win);
      }
    });
  }

  /** 全屏内容（图片预览/视频）隐藏状态栏前调用，防 insets 归零引起布局跳动 */
  static setSuppressInsetSync(on: boolean): void {
    ImmersiveWindow.suppress = on;
  }

  /** 深浅色变化时更新系统栏前景色（onConfigurationUpdate 中调用） */
  static applyBarContentColor(dark: boolean): void {
    ImmersiveWindow.lastDark = dark;
    ImmersiveWindow.setSystemBar({
      statusBarContentColor: dark ? '#FFFFFF' : '#000000',
      navigationBarContentColor: dark ? '#FFFFFF' : '#000000'
    });
  }

  /** 透明系统栏 */
  static setTransparentBars(): void {
    ImmersiveWindow.setSystemBar({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000'
    });
  }

  /**
   * 启动闪屏兜底：首帧底色由 module.json5 的 `startWindowBackground` +
   * resources/{base,dark}/element/color.json 的 `start_window_background` 声明式兜住。
   * `mainWindow.setWindowBackgroundColor()` 在本机 SDK 的设备支持元数据里被标为
   * phone / tablet / 2in1 均不可用（编译期会给出 "This API is unavailable to phone, tablet, 2in1"），
   * 因此这里不保留该命令式调用。
   */

  /** 系统栏属性统一出口：设备不支持则跳过，异常一律吞掉（纯装饰性） */
  private static setSystemBar(props: window.SystemBarProperties): void {
    if (ImmersiveWindow.win === undefined || !systemBarSupported()) {
      return;
    }
    try {
      ImmersiveWindow.win.setWindowSystemBarProperties(props)
        .catch((e: Object) => {
          Logger.w(TAG, 'setWindowSystemBarProperties 被拒绝，忽略');
        });
    } catch (e) {
      Logger.w(TAG, 'setWindowSystemBarProperties 同步异常，忽略');
    }
  }

  private static syncInsets(win: window.Window): void {
    if (ImmersiveWindow.suppress) {
      return;
    }
    // getWindowAvoidArea / getDefaultDisplaySync 都可能抛异常，
    // 而本方法会在 avoidAreaChange 回调里被调用——不兜住就是未捕获异常
    try {
      const sys: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const indicator: window.AvoidArea =
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      // Ability 上下文没有 px2vp，必须手动除以 density
      const density: number = display.getDefaultDisplaySync().densityPixels;
      const topVp: number = ImmersiveWindow.toVp(sys.topRect.height, density);
      const bottomVp: number = ImmersiveWindow.toVp(indicator.bottomRect.height, density);

      // 顶部 0 值防清零：主题切换瞬间 avoidArea 可能短暂为 0
      const curTop: number = AppStorage.get<number>('sysTopInsetVp') ?? 0;
      const safeTop: number = (topVp === 0 && curTop > 0) ? curTop : topVp;
      publishWindowMetrics(safeTop, bottomVp);
    } catch (e) {
      Logger.w(TAG, 'syncInsets 失败，跳过本次安全区刷新');
    }
  }

  /**
   * px → vp，并做健全性钳制。
   * 一旦 density 异常（0 / NaN）会算出 Infinity 或 NaN，写进根容器 padding 后
   * 会把整屏内容顶到看不见的地方 —— 表现出来就是"白屏什么都没有"。
   * 因此这里把非法值与离谱值统一压到安全区间。
   */
  private static toVp(px: number, density: number): number {
    if (!Number.isFinite(px) || !Number.isFinite(density) || density <= 0) {
      Logger.w(TAG, `安全区数值异常(px=${px}, density=${density})，按 0 处理`);
      return 0;
    }
    const vp: number = px / density;
    if (vp < 0) {
      return 0;
    }
    return vp > 200 ? 200 : vp;
  }
}
