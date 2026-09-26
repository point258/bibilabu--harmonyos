/**
 * BuffProvider.ets — 网易BUFF 数据源
 *
 * 取数依据：BUFF 网页端（buff.163.com）在浏览器里本就调用的公开数据接口。
 * 本应用不实现登录、不代填账号、不绕过风控 —— 会话来自用户自己在平台网页内的登录，
 * 通过 WebSessionBridge 复用；未登录时接口会返回 "Login Required"，此处直接透出
 * 「需要先在平台网页端登录」的提示。
 *
 * 接口路径集中在 BuffEndpoints：平台若调整路径，只改这里。
 */

import { AppError, BuffBillData, BuffBillEnvelope, BuffBillItem, BuffEnvelope,
  BuffGoodsInfo, BuffGoodsInfoDetail, BuffGoodsItem, BuffGoodsPage, BuffGoodsTag,
  FailKind, FetchChannel, Game, ItemSummary, MarketQuery, PageResult, Platform,
  PlatformMeta, PricePoint, SortBy, TrendData } from '../model/Types';
import { MarketProvider } from './MarketProvider';
import { HttpClient } from './HttpClient';
import { WebBridge, BridgeResult } from './WebBridge';
import { WebSessionBridge } from './WebSessionBridge';
import { ParseUtil } from './ParseUtil';
import { Logger } from '../common/Logger';

const TAG: string = 'BuffProvider';

/** 网页端公开数据接口路径（集中定义，便于跟随平台调整） */
export class BuffEndpoints {
  /** 在售商品列表 */
  static readonly LIST: string = '/api/market/goods';
  /** 成交记录（价格走势） */
  static readonly BILL: string = '/api/market/goods/bill_order';
  /** 指定商品的在售订单（取最低价） */
  static readonly SELL_ORDER: string = '/api/market/goods/sell_order';
}

export class BuffProvider implements MarketProvider {
  hasSession(): boolean {
    return WebSessionBridge.isLoggedIn(Platform.BUFF);
  }

  async list(query: MarketQuery, channel: FetchChannel): Promise<PageResult> {
    const path: string = `${BuffEndpoints.LIST}?${BuffProvider.buildListQuery(query)}`;
    const text: string = await BuffProvider.fetch(path, channel);
    return BuffProvider.parseList(text, query.pageSize);
  }

  async trend(item: ItemSummary, channel: FetchChannel): Promise<TrendData> {
    const path: string = `${BuffEndpoints.BILL}?game=${item.game}&goods_id=${item.goodsId}`;
    const text: string = await BuffProvider.fetch(path, channel);
    return BuffProvider.parseBill(text, item);
  }

  /** 单品最低在售价：在售订单接口按价格升序取第一条 */
  async quote(item: ItemSummary, channel: FetchChannel): Promise<number | null> {
    const path: string = `${BuffEndpoints.SELL_ORDER}` +
      `?game=${item.game}&goods_id=${item.goodsId}` +
      `&page_num=1&page_size=20&sort_by=price.asc`;
    const text: string = await BuffProvider.fetch(path, channel);
    return BuffProvider.parseLowest(text);
  }

  // -------------------------------------------------------------------------
  // 请求
  // -------------------------------------------------------------------------

  private static buildListQuery(query: MarketQuery): string {
    const parts: string[] = [];
    parts.push(`game=${query.game}`);
    parts.push(`page_num=${query.pageNum}`);
    parts.push(`page_size=${query.pageSize}`);
    if (query.keyword.length > 0) {
      parts.push(`search=${encodeURIComponent(query.keyword)}`);
    }
    const sort: string = BuffProvider.sortParam(query.sortBy);
    if (sort.length > 0) {
      parts.push(`sort_by=${sort}`);
    }
    return parts.join('&');
  }

  private static sortParam(s: SortBy): string {
    if (s === SortBy.PRICE_ASC) {
      return 'price.asc';
    }
    if (s === SortBy.PRICE_DESC) {
      return 'price.desc';
    }
    if (s === SortBy.HOT) {
      return 'sell_num.desc';
    }
    return '';
  }

  private static async fetch(path: string, channel: FetchChannel): Promise<string> {
    if (channel === FetchChannel.BRIDGE) {
      const res: BridgeResult = await WebBridge.run(Platform.BUFF, path, 'GET', '');
      if (res.status < 200 || res.status >= 300) {
        throw new AppError(FailKind.HTTP_5XX, `网页桥接返回 HTTP ${res.status}`);
      }
      return res.text;
    }
    const base: string = PlatformMeta.apiBase(Platform.BUFF);
    const cookie: string = WebSessionBridge.cookieOf(Platform.BUFF);
    const referer: string = `${base}/market/csgo`;
    return HttpClient.get(`${base}${path}`, cookie, referer);
  }

  // -------------------------------------------------------------------------
  // 解析
  // -------------------------------------------------------------------------

  private static parseList(text: string, pageSize: number): PageResult {
    let env: BuffEnvelope;
    try {
      env = JSON.parse(text) as BuffEnvelope;
    } catch (e) {
      throw new AppError(FailKind.PARSE, '列表响应不是合法 JSON');
    }
    const code: string = env.code ?? '';
    BuffProvider.assertCode(code, env.error);

    const page: BuffGoodsPage | undefined = env.data;
    const raw: BuffGoodsItem[] = page?.items ?? [];
    const items: ItemSummary[] = [];
    for (let i = 0; i < raw.length; i++) {
      const it: ItemSummary | undefined = BuffProvider.mapItem(raw[i]);
      if (it !== undefined) {
        items.push(it);
      }
    }
    return { items: items, hasMore: raw.length >= pageSize };
  }

  private static mapItem(src: BuffGoodsItem): ItemSummary | undefined {
    const id: number | undefined = src.id;
    if (id === undefined) {
      return undefined;
    }
    const info: BuffGoodsInfo | undefined = src.goods_info;
    const detail: BuffGoodsInfoDetail | undefined = info?.info;
    const tags: BuffGoodsTag[] | undefined = detail?.tags;

    let icon: string = info?.icon_url ?? '';
    if (icon.length > 0 && icon.charAt(0) === '/') {
      icon = `${PlatformMeta.apiBase(Platform.BUFF)}${icon}`;
    }

    let exterior: string = info?.exterior ?? '';
    if (exterior.length === 0) {
      exterior = ParseUtil.tagByCategory(tags, 'exterior');
    }

    const item: ItemSummary = {
      goodsId: `${id}`,
      platform: Platform.BUFF,
      game: Game.CSGO,
      name: src.name ?? src.market_hash_name ?? '',
      sellPriceCent: ParseUtil.toCent(src.sell_min_price),
      buyPriceCent: ParseUtil.toCent(src.buy_max_price),
      deltaPct: null, // 由 MarketService 用本地快照计算
      sellNum: ParseUtil.toInt(src.sell_num),
      iconUrl: icon,
      exterior: exterior,
      rarity: info?.rarity ?? ParseUtil.tagByCategory(tags, 'rarity'),
      floatRange: ParseUtil.tagByKeyword(tags, 'range'),
      detailPath: `/goods/${id}`
    };
    return item;
  }

  private static parseBill(text: string, item: ItemSummary): TrendData {
    let env: BuffBillEnvelope;
    try {
      env = JSON.parse(text) as BuffBillEnvelope;
    } catch (e) {
      throw new AppError(FailKind.PARSE, '成交记录响应不是合法 JSON');
    }
    const code: string = env.code ?? '';
    BuffProvider.assertCode(code, undefined);

    const data: BuffBillData | undefined = env.data;
    const raw: BuffBillItem[] = data?.items ?? [];
    const points: PricePoint[] = [];
    let min: number = Number.MAX_SAFE_INTEGER;
    let max: number = 0;
    for (let i = 0; i < raw.length; i++) {
      const cent: number | null = ParseUtil.toCent(raw[i].price);
      const ts: number = ParseUtil.toMillis(raw[i].created_at);
      if (cent === null || ts <= 0) {
        continue;
      }
      points.push({ ts: ts, priceCent: cent });
      min = Math.min(min, cent);
      max = Math.max(max, cent);
    }
    // 成交记录通常按时间倒序返回，走势图需要正序
    points.sort((a: PricePoint, b: PricePoint) => a.ts - b.ts);
    if (points.length === 0) {
      min = 0;
      max = 0;
    }
    const data2: TrendData = {
      goodsId: item.goodsId,
      platform: Platform.BUFF,
      points: points,
      minCent: min === Number.MAX_SAFE_INTEGER ? 0 : min,
      maxCent: max,
      volume: points.length
    };
    Logger.d(TAG, `走势点数 ${points.length}`);
    return data2;
  }

  /** 在售订单响应里取最低价（分） */
  private static parseLowest(text: string): number | null {
    let env: BuffEnvelope;
    try {
      env = JSON.parse(text) as BuffEnvelope;
    } catch (e) {
      throw new AppError(FailKind.PARSE, '在售订单响应不是合法 JSON');
    }
    BuffProvider.assertCode(env.code ?? '', env.error);
    const items: BuffGoodsItem[] = env.data?.items ?? [];
    let min: number | null = null;
    for (let i = 0; i < items.length; i++) {
      const cent: number | null = ParseUtil.toCent(items[i].price);
      if (cent === null) {
        continue;
      }
      if (min === null || cent < min) {
        min = cent;
      }
    }
    return min;
  }

  /** 统一处理 BUFF 的 code 语义 */
  private static assertCode(code: string, errMsg: string | undefined): void {
    if (code === 'OK') {
      return;
    }
    if (code.indexOf('Login') >= 0 || code.indexOf('login') >= 0) {
      throw new AppError(FailKind.NEED_LOGIN, '请先在 BUFF 网页端登录');
    }
    throw new AppError(FailKind.UNAVAILABLE,
      errMsg ?? (code.length > 0 ? `接口返回 ${code}` : '接口返回异常'));
  }
}
