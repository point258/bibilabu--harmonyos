/**
 * ShellState.ets — 主壳（HdsTabs）的页签意图状态（状态管理 V2 单例，一域一文件）。
 *
 * 子页（详情页）要"跳到比价页并带上关键词"，而页签切换的持有者是 Index 壳。
 * 用回调或事件总线会在组件重建时断链，所以把"去哪个页签""要比价什么"做成一个全局
 * @ObservedV2 单例：写入方是任意页面，读取方只有 Index 与 CompareTab。
 *
 * 用 nonce（自增请求序号）而不是直接监听 compareKeyword：同一个关键词可能被连续请求两次
 * （用户连点两次「跨平台比价」），只监听字符串不会触发第二次。
 */

import { AppStorageV2 } from '@kit.ArkUI';
import { Logger } from '../common/Logger';

const TAG: string = 'ShellState';
const KEY: string = 'v2_shell';

/**
 * 页签序号，必须与 Index.tabContents() 里的顺序严格一致：
 * 行情 / 比价 / 库存 / 工具 / 我的（自选已并入比价页）。
 */
export const TAB_MARKET: number = 0;
export const TAB_COMPARE: number = 1;
export const TAB_INVENTORY: number = 2;
export const TAB_TOOLBOX: number = 3;
export const TAB_MINE: number = 4;

/** 自选已并入比价页（`CompareTab` 内的「自选」分栏），保留常量名做兼容 */
export const TAB_WATCHLIST: number = TAB_COMPARE;

@ObservedV2
export class ShellState {
  /** 当前页签索引。任何页面都可以写，写即切页签（Index 监听后驱动 HdsTabs） */
  @Trace tabIndex: number = TAB_MARKET;

  /** 待比价的关键词 */
  @Trace compareKeyword: string = '';

  /** 比价请求序号：自增一次 = 发起一次比价 */
  @Trace compareNonce: number = 0;

  /**
   * 已被消费的请求序号。
   * 放在全局单例上而不是组件字段里：TabContent 的子树是可能重建的，
   * 组件字段一重建就归零，会把上一次请求当成新请求重跑一遍。
   */
  @Trace compareConsumedNonce: number = 0;

  /**
   * 取出一次待处理的比价请求；没有新请求时返回空串。
   * 只能在生命周期回调或事件回调里调用（会写状态），不要在 build 里调。
   */
  takePendingCompare(): string {
    if (this.compareNonce <= this.compareConsumedNonce) {
      return '';
    }
    this.compareConsumedNonce = this.compareNonce;
    return this.compareKeyword;
  }
}

/** 绝不返回 undefined：组件 build 里解引用 undefined 会整页白屏 */
export function connectShell(): ShellState {
  try {
    const s: ShellState | undefined =
      AppStorageV2.connect(ShellState, KEY, () => new ShellState());
    if (s !== undefined) {
      return s;
    }
  } catch (e) {
    Logger.w(TAG, 'AppStorageV2 不可用，退回本地实例');
  }
  return new ShellState();
}

/** 切到指定页签 */
export function switchTab(index: number): void {
  connectShell().tabIndex = index;
}

/** 详情页入口：切到比价页并按关键词立即发起一次比价 */
export function requestCompare(keyword: string): void {
  const s: ShellState = connectShell();
  s.compareKeyword = keyword;
  s.compareNonce = s.compareNonce + 1;
  s.tabIndex = TAB_COMPARE;
}
