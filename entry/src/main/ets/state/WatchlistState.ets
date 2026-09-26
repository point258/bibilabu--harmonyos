/**
 * WatchlistState.ets — 自选域状态
 * 只存"我关心什么"（本地数据），实时行情由 WatchlistTab 拉取后合成 WatchQuote，
 * 避免把价格写进本地造成过期数据。
 */

import { AppStorageV2 } from '@kit.ArkUI';
import { Game, ItemSummary, Platform, WatchItem, WatchQuote } from '../model/Types';
import { PreferencesStore } from '../data/PreferencesStore';
import { Logger } from '../common/Logger';

const TAG: string = 'WatchlistState';
const KEY: string = 'v2_watchlist';
const K_ITEMS: string = 'watch_items';

@ObservedV2
export class WatchlistState {
  @Trace items: WatchItem[] = [];

  load(): void {
    const stored: WatchItem[] | undefined = PreferencesStore.getJson<WatchItem[]>(K_ITEMS);
    this.items = stored ?? [];
    Logger.i(TAG, `自选装载 ${this.items.length} 条`);
  }

  private persist(): void {
    PreferencesStore.putJson(K_ITEMS, this.items);
  }

  static keyOf(platform: Platform, goodsId: string): string {
    return `${platform}:${goodsId}`;
  }

  contains(platform: Platform, goodsId: string): boolean {
    return this.indexOf(WatchlistState.keyOf(platform, goodsId)) >= 0;
  }

  private indexOf(key: string): number {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].key === key) {
        return i;
      }
    }
    return -1;
  }

  /** 从行情条目加入自选 */
  addFromSummary(it: ItemSummary): void {
    const key: string = WatchlistState.keyOf(it.platform, it.goodsId);
    if (this.indexOf(key) >= 0) {
      return;
    }
    const w: WatchItem = {
      key: key,
      platform: it.platform,
      game: it.game,
      goodsId: it.goodsId,
      name: it.name,
      iconUrl: it.iconUrl,
      costCent: 0,
      baseCent: it.sellPriceCent ?? 0,
      addedTs: Date.now()
    };
    const next: WatchItem[] = this.items.slice();
    next.unshift(w);
    this.items = next;
    this.persist();
  }

  toggle(it: ItemSummary): boolean {
    const key: string = WatchlistState.keyOf(it.platform, it.goodsId);
    if (this.indexOf(key) >= 0) {
      this.remove(key);
      return false;
    }
    this.addFromSummary(it);
    return true;
  }

  remove(key: string): void {
    const next: WatchItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].key !== key) {
        next.push(this.items[i]);
      }
    }
    this.items = next;
    this.persist();
  }

  /** 录入成本价（分）；0 表示清除 */
  setCost(key: string, costCent: number): void {
    const next: WatchItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const w: WatchItem = this.items[i];
      if (w.key === key) {
        const updated: WatchItem = {
          key: w.key,
          platform: w.platform,
          game: w.game,
          goodsId: w.goodsId,
          name: w.name,
          iconUrl: w.iconUrl,
          costCent: costCent,
          baseCent: w.baseCent,
          addedTs: w.addedTs
        };
        next.push(updated);
      } else {
        next.push(w);
      }
    }
    this.items = next;
    this.persist();
  }

  clear(): void {
    this.items = [];
    this.persist();
  }

  /** 用最新行情合成展示行 */
  static quoteOf(item: WatchItem, currentCent: number | null): WatchQuote {
    let profitPct: number | null = null;
    if (currentCent !== null && item.costCent > 0) {
      profitPct = ((currentCent - item.costCent) / item.costCent) * 100;
    }
    let deltaPct: number | null = null;
    if (currentCent !== null && item.baseCent > 0) {
      deltaPct = ((currentCent - item.baseCent) / item.baseCent) * 100;
    }
    const q: WatchQuote = {
      item: item,
      currentCent: currentCent,
      profitPct: profitPct,
      deltaPct: deltaPct
    };
    return q;
  }

  /** 把自选条目还原成可查询的 Marker（详情/走势复用） */
  static toSummary(item: WatchItem, currentCent: number | null): ItemSummary {
    const s: ItemSummary = {
      goodsId: item.goodsId,
      platform: item.platform,
      game: item.game === undefined ? Game.CSGO : item.game,
      name: item.name,
      sellPriceCent: currentCent,
      buyPriceCent: null,
      deltaPct: null,
      sellNum: null,
      iconUrl: item.iconUrl,
      exterior: '',
      rarity: '',
      floatRange: '',
      detailPath: ''
    };
    return s;
  }
}

/** 绝不返回 undefined：否则组件 build 里解引用会抛异常导致整页白屏 */
export function connectWatchlist(): WatchlistState {
  try {
    const s: WatchlistState | undefined =
      AppStorageV2.connect(WatchlistState, KEY, () => new WatchlistState());
    if (s !== undefined) {
      return s;
    }
  } catch (e) {
    Logger.w(TAG, 'AppStorageV2 不可用，退回本地实例');
  }
  return new WatchlistState();
}

/** 启动期装载（loadContent 之前调用） */
export function bootstrapWatchlist(): void {
  try {
    connectWatchlist().load();
  } catch (e) {
    Logger.w(TAG, '自选装载延迟到页面侧');
  }
}
