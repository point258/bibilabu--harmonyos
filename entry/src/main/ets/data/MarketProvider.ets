/**
 * MarketProvider.ets — 平台数据源接口
 * 两个平台（BUFF / 悠悠有品）各自实现一份，聚合层只依赖此接口，
 * 便于某个平台接口变动时只改一个文件。
 */

import { FetchChannel, ItemSummary, MarketQuery, PageResult, TrendData } from '../model/Types';

export interface MarketProvider {
  /** 行情列表（分页） */
  list(query: MarketQuery, channel: FetchChannel): Promise<PageResult>;

  /** 单品质检走势（成交记录） */
  trend(item: ItemSummary, channel: FetchChannel): Promise<TrendData>;

  /** 单品当前最低在售价（分）；拿不到返回 null */
  quote(item: ItemSummary, channel: FetchChannel): Promise<number | null>;

  /** 当前会话是否可用于取数 */
  hasSession(): boolean;
}
