/**
 * WindowMetrics.ets — 窗口安全区状态（状态管理 V2 单例）。
 *
 * 不用 @StorageProp：@StorageProp/@StorageLink 在状态管理 V2 里没有对应物，
 * 迁移路径是 AppStorageV2.connect 状态类 + @Local 持有。本文件是"窗口度量"这一域的
 * 唯一状态源（一域一文件）。
 *
 * 写入方唯一：EntryAbility 经由 ImmersiveWindow.init 调用 publishWindowMetrics()，组件只读。
 */

import { AppStorageV2 } from '@kit.ArkUI';
import { Logger } from '../common/Logger';

@ObservedV2
export class WindowMetrics {
  /** 状态栏高度（vp） */
  @Trace topInsetVp: number = 0;
  /** 底部导航条高度（vp） */
  @Trace bottomInsetVp: number = 0;
  /** 断点：'sm' | 'md' | 'lg' | 'xl'，由根容器 onAreaChange 驱动 */
  @Trace breakpoint: string = 'sm';
  /** 是否为宽屏（Split 分栏） */
  @Trace isWide: boolean = false;
}

const KEY: string = 'v2_windowMetrics';

/**
 * 组件侧：拿到全局共享的窗口度量实例。
 * 绝不返回 undefined —— 返回 undefined 会让组件 build 里的 `this.metrics.topInsetVp`
 * 直接抛 TypeError，整页白屏。拿不到共享实例时退回本地实例（值可能不同步，但不会崩）。
 */
export function connectWindowMetrics(): WindowMetrics {
  try {
    const m: WindowMetrics | undefined =
      AppStorageV2.connect(WindowMetrics, KEY, () => new WindowMetrics());
    if (m !== undefined) {
      return m;
    }
  } catch (e) {
    Logger.w('WindowMetrics', 'AppStorageV2 不可用，退回本地实例');
  }
  return new WindowMetrics();
}

/**
 * 写入方（EntryAbility）：同时写 AppStorage 键与 V2 实例。
 * 双层写入的原因：AppStorage 键可在 Ability 上下文稳定写入；
 * V2 实例供 @ComponentV2 组件精确订阅（避免 @StorageProp 在 V2 缺位）。
 */
export function publishWindowMetrics(topVp: number, bottomVp: number): void {
  AppStorage.setOrCreate<number>('sysTopInsetVp', topVp);
  AppStorage.setOrCreate<number>('sysBottomInsetVp', bottomVp);
  try {
    const m: WindowMetrics | undefined =
      AppStorageV2.connect(WindowMetrics, KEY, () => new WindowMetrics());
    if (m) {
      m.topInsetVp = topVp;
      m.bottomInsetVp = bottomVp;
    }
  } catch (e) {
    // Ability 上下文若不可用 AppStorageV2，AppStorage 键仍生效，降级不报错
    Logger.w('WindowMetrics', 'AppStorageV2 写入失败，已退化为 AppStorage 通道');
  }
}

/** 断点由根容器 onAreaChange 驱动（mediaquery 在窗口未建时不可靠） */
export function applyBreakpoint(widthVp: number): void {
  let bp: string = 'sm';
  if (widthVp >= 1200) {
    bp = 'xl';
  } else if (widthVp >= 840) {
    bp = 'lg';
  } else if (widthVp >= 600) {
    bp = 'md';
  }
  try {
    const m: WindowMetrics | undefined =
      AppStorageV2.connect(WindowMetrics, KEY, () => new WindowMetrics());
    if (m) {
      m.breakpoint = bp;
      m.isWide = widthVp >= 600;
    }
  } catch (e) {
    Logger.w('WindowMetrics', '断点写入失败');
  }
}
