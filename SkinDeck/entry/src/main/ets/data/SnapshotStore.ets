/**
 * SnapshotStore.ets — 价格快照（用于计算涨跌幅）
 *
 * 行情接口本身只给当前价，涨跌幅需要"上一次看到的价格"作基线。
 * 这里把每个商品的最近一次价格与时间戳落盘，刷新时用旧值算 deltaPct，
 * 再写回新值 —— 语义明确、无额外请求。
 */

import { PreferencesStore } from './PreferencesStore';

const KEY: string = 'price_snapshots';

/** 单条快照 */
export interface PriceSnapshot {
  priceCent: number;
  ts: number;
}

/** 落盘结构：key(platform:goodsId) -> 快照 */
export interface SnapshotMap {
  map: Record<string, PriceSnapshot>;
}

/** 超过该时长（毫秒）的快照不再用于计算涨跌，避免跨天误导 */
const MAX_AGE_MS: number = 6 * 60 * 60 * 1000;

export class SnapshotStore {
  private static cache: SnapshotMap | undefined = undefined;

  private static load(): SnapshotMap {
    if (SnapshotStore.cache === undefined) {
      const raw: SnapshotMap | undefined = PreferencesStore.getJson<SnapshotMap>(KEY);
      SnapshotStore.cache = raw ?? { map: {} };
    }
    return SnapshotStore.cache!;
  }

  static key(platform: string, goodsId: string): string {
    return `${platform}:${goodsId}`;
  }

  /** 读取旧快照并返回涨跌幅（%）；无有效旧值时返回 null */
  static deltaPctOf(platform: string, goodsId: string, currentCent: number): number | null {
    const m: SnapshotMap = SnapshotStore.load();
    const prev: PriceSnapshot | undefined = m.map[SnapshotStore.key(platform, goodsId)];
    if (prev === undefined || prev.priceCent <= 0) {
      return null;
    }
    if (Date.now() - prev.ts > MAX_AGE_MS) {
      return null;
    }
    if (prev.priceCent === currentCent) {
      return 0;
    }
    return ((currentCent - prev.priceCent) / prev.priceCent) * 100;
  }

  /** 写入当前价（批量刷新结束后统一 flush 一次） */
  static put(platform: string, goodsId: string, currentCent: number): void {
    const m: SnapshotMap = SnapshotStore.load();
    m.map[SnapshotStore.key(platform, goodsId)] = {
      priceCent: currentCent,
      ts: Date.now()
    };
  }

  static flush(): void {
    if (SnapshotStore.cache !== undefined) {
      PreferencesStore.putJson(KEY, SnapshotStore.cache);
    }
  }

  static clear(): void {
    SnapshotStore.cache = { map: {} };
    PreferencesStore.putJson(KEY, SnapshotStore.cache);
  }
}
