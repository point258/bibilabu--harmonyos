/**
 * MarketService.ets — 数据聚合层
 * 职责：平台分发、涨跌幅补算、短时缓存、双平台比价。
 * UI 只依赖本层，不直接触碰 Provider。
 */

import { AppError, CompareRow, FailKind, FetchChannel, Game, ItemSummary, MarketQuery,
  PageResult, Platform, PlatformMeta, SortBy, TrendData } from '../model/Types';
import { MarketProvider } from './MarketProvider';
import { BuffProvider } from './BuffProvider';
import { UuProvider } from './UuProvider';
import { SnapshotStore } from './SnapshotStore';
import { Logger } from '../common/Logger';

const TAG: string = 'MarketService';
/** 列表短时缓存，避免切 Tab / 回退时重复打接口 */
const CACHE_TTL_MS: number = 60 * 1000;

interface CacheEntry {
  items: ItemSummary[];
  hasMore: boolean;
  ts: number;
}

/** 比价时单平台的取数条数 */
const COMPARE_PAGE_SIZE: number = 20;

/**
 * 磨损档（中文为准，英文名做映射）。
 * 比价的配对键必须带上它：饰品价格几乎完全由磨损档决定，
 * 把"崭新出厂"和"战痕累累"配到一起，价差能虚高到 80% 以上。
 */
const WEAR_CN: string[] = ['崭新出厂', '略有磨损', '久经沙场', '破损不堪', '战痕累累'];
const WEAR_EN: string[] = ['factory new', 'minimal wear', 'field-tested',
  'well-worn', 'battle-scarred'];

/**
 * 单品现价的短时缓存。
 * 自选页每次进入/刷新会对每一条各发一次请求；同一件商品在详情页、自选页、
 * 比价页之间来回切换时也会反复问同一个接口。缓存能显著压低请求量 ——
 * 平台的阿里云 WAF 是按访问频率拦截的，请求少一点更不容易被风控。
 */
const QUOTE_TTL_MS: number = 60 * 1000;

interface QuoteEntry {
  cent: number | null;
  ts: number;
}

export class MarketService {
  private static providers: Map<string, MarketProvider> = new Map();
  private static cache: Map<string, CacheEntry> = new Map();
  private static quoteCache: Map<string, QuoteEntry> = new Map();

  private static provider(p: Platform): MarketProvider {
    let impl: MarketProvider | undefined = MarketService.providers.get(`${p}`);
    if (impl === undefined) {
      impl = p === Platform.BUFF ? new BuffProvider() : new UuProvider();
      MarketService.providers.set(`${p}`, impl);
    }
    return impl;
  }

  /** 指定平台当前是否可取数（决定 UI 上的"去登录"引导） */
  static hasSession(p: Platform): boolean {
    return MarketService.provider(p).hasSession();
  }

  static async list(query: MarketQuery, channel: FetchChannel,
    useCache: boolean = true): Promise<PageResult> {
    const key: string = MarketService.cacheKey(query, channel);
    if (useCache && query.pageNum === 1) {
      const hit: CacheEntry | undefined = MarketService.cache.get(key);
      if (hit !== undefined && Date.now() - hit.ts < CACHE_TTL_MS) {
        Logger.d(TAG, '命中列表缓存');
        return { items: hit.items, hasMore: hit.hasMore };
      }
    }

    const result: PageResult = await MarketService.provider(query.platform)
      .list(query, channel);
    const items: ItemSummary[] = MarketService.enrich(result.items);

    if (query.pageNum === 1) {
      MarketService.cache.set(key, {
        items: items,
        hasMore: result.hasMore,
        ts: Date.now()
      });
    }
    return { items: items, hasMore: result.hasMore };
  }

  static async trend(item: ItemSummary, channel: FetchChannel): Promise<TrendData> {
    return MarketService.provider(item.platform).trend(item, channel);
  }

  /** 单品当前价（自选列表用）；失败返回 null，不打断整页刷新 */
  static async quote(item: ItemSummary, channel: FetchChannel): Promise<number | null> {
    const key: string = `${item.platform}:${item.goodsId}`;
    const hit: QuoteEntry | undefined = MarketService.quoteCache.get(key);
    if (hit !== undefined && Date.now() - hit.ts < QUOTE_TTL_MS) {
      return hit.cent;
    }
    try {
      const cent: number | null =
        await MarketService.provider(item.platform).quote(item, channel);
      // 只缓存成功值：失败不缓存，用户重试时能立刻再试一次
      if (cent !== null) {
        MarketService.quoteCache.set(key, { cent: cent, ts: Date.now() });
      }
      return cent;
    } catch (e) {
      Logger.w(TAG, `取 ${item.name} 现价失败`);
      return null;
    }
  }

  /**
   * 双平台比价：同一关键词各拉一页，按"基础名"（去掉磨损后缀）配对。
   * 单边失败不阻断整体 —— 有一边就展示一边，并在 advice 里说明。
   */
  static async compare(keyword: string, channel: FetchChannel,
    sortBy: SortBy): Promise<CompareRow[]> {
    const buffQuery: MarketQuery = {
      platform: Platform.BUFF, game: Game.CSGO, keyword: keyword,
      sortBy: sortBy, pageNum: 1, pageSize: COMPARE_PAGE_SIZE
    };
    const uuQuery: MarketQuery = {
      platform: Platform.UU, game: Game.CSGO, keyword: keyword,
      sortBy: sortBy, pageNum: 1, pageSize: COMPARE_PAGE_SIZE
    };

    let buffItems: ItemSummary[] = [];
    let uuItems: ItemSummary[] = [];
    let buffErr: AppError | undefined = undefined;
    let uuErr: AppError | undefined = undefined;

    try {
      buffItems = (await MarketService.list(buffQuery, channel, false)).items;
    } catch (e) {
      buffErr = MarketService.asAppError(e);
      Logger.w(TAG, `比价取 BUFF 失败：${buffErr.message}`);
    }
    try {
      uuItems = (await MarketService.list(uuQuery, channel, false)).items;
    } catch (e) {
      uuErr = MarketService.asAppError(e);
      Logger.w(TAG, `比价取悠悠有品失败：${uuErr.message}`);
    }
    if (buffErr !== undefined && uuErr !== undefined) {
      throw buffErr;
    }

    const buffMap: Map<string, ItemSummary> = MarketService.indexByName(buffItems);
    const uuMap: Map<string, ItemSummary> = MarketService.indexByName(uuItems);
    const keys: string[] = [];
    buffMap.forEach((v: ItemSummary, k: string) => {
      keys.push(k);
    });
    uuMap.forEach((v: ItemSummary, k: string) => {
      if (keys.indexOf(k) < 0) {
        keys.push(k);
      }
    });

    const rows: CompareRow[] = [];
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      const b: ItemSummary | undefined = buffMap.get(k);
      const u: ItemSummary | undefined = uuMap.get(k);
      const bp: number | null = b?.sellPriceCent ?? null;
      const up: number | null = u?.sellPriceCent ?? null;
      let diff: number | null = null;
      let diffPct: number | null = null;
      if (bp !== null && up !== null) {
        diff = bp - up;
        const lower: number = Math.min(bp, up);
        diffPct = lower > 0 ? (diff / lower) * 100 : 0;
      }
      // 名字用 BUFF 的（更规范），但要**保证里面带着参与比价的那个磨损档**：
      // 万一某一侧的 name 没写磨损、磨损是从结构化字段来的，就补在末尾，
      // 免得又出现"看不出来比的是哪一档"。
      let displayName: string = b?.name ?? u?.name ?? k;
      const wear: string = k.substring(k.lastIndexOf('|') + 1);
      if (wear.length > 0 && displayName.indexOf(wear) < 0) {
        displayName = `${displayName} (${wear})`;
      }
      const row: CompareRow = {
        name: displayName,
        buffPriceCent: bp,
        uuPriceCent: up,
        diffCent: diff,
        diffPct: diffPct,
        advice: MarketService.adviceOf(diffPct, bp, up)
      };
      rows.push(row);
    }
    // 价差大的排前面，便于一眼看到机会
    rows.sort((a: CompareRow, b: CompareRow) => {
      const av: number = Math.abs(a.diffPct ?? 0);
      const bv: number = Math.abs(b.diffPct ?? 0);
      return bv - av;
    });
    return rows;
  }

  static clearCache(): void {
    MarketService.cache.clear();
    MarketService.quoteCache.clear();
  }

  /**
   * 详情页跳比价时用的关键词：去掉磨损后缀（"(崭新出厂)" 这类），
   * 否则两平台搜出来的磨损档不同、配对不上。
   * 与 baseName 的区别：这里保留原始书写形态（空格/大小写），搜索框里更好认。
   */
  static compareKeywordOf(name: string): string {
    const idx: number = name.indexOf('(');
    const core: string = idx > 0 ? name.substring(0, idx) : name;
    return core.trim();
  }

  // -------------------------------------------------------------------------
  // 内部
  // -------------------------------------------------------------------------

  /** 补算涨跌幅并写回快照 */
  private static enrich(items: ItemSummary[]): ItemSummary[] {
    for (let i = 0; i < items.length; i++) {
      const it: ItemSummary = items[i];
      const p: number | null = it.sellPriceCent;
      if (p === null) {
        continue;
      }
      it.deltaPct = SnapshotStore.deltaPctOf(`${it.platform}`, it.goodsId, p);
      SnapshotStore.put(`${it.platform}`, it.goodsId, p);
    }
    SnapshotStore.flush();
    return items;
  }

  private static cacheKey(query: MarketQuery, channel: FetchChannel): string {
    return `${query.platform}|${channel}|${query.game}|${query.sortBy}|${query.keyword}`;
  }

  private static asAppError(e: Object): AppError {
    if (e instanceof AppError) {
      return e;
    }
    if (e instanceof Error) {
      return new AppError(FailKind.NETWORK, e.message);
    }
    return new AppError(FailKind.NETWORK, `${e}`);
  }

  // -------------------------------------------------------------------------
  // 配对键
  // -------------------------------------------------------------------------

  /** 全角括号/竖线统一成半角：两个平台的 name 混用全角与半角，不统一就配不上 */
  private static toHalfWidth(s: string): string {
    return s.split('（').join('(').split('）').join(')').split('｜').join('|');
  }

  /** 磨损文本归一：英文名映射成中文，去掉空格 */
  private static normWear(raw: string): string {
    const s: string = MarketService.toHalfWidth(raw).replace(/\s+/g, '').toLowerCase();
    if (s.length === 0) {
      return '';
    }
    for (let i = 0; i < WEAR_EN.length; i++) {
      if (s === WEAR_EN[i].replace(/\s+/g, '')) {
        return WEAR_CN[i];
      }
    }
    for (let i = 0; i < WEAR_CN.length; i++) {
      if (s === WEAR_CN[i]) {
        return WEAR_CN[i];
      }
    }
    return s;
  }

  /** 从名字末尾的括号组里认磨损（兼容全角括号）；认不出返回空串 */
  private static wearFromName(name: string): string {
    const s: string = MarketService.toHalfWidth(name);
    const end: number = s.lastIndexOf(')');
    if (end < 0) {
      return '';
    }
    const start: number = s.lastIndexOf('(', end);
    if (start < 0) {
      return '';
    }
    const w: string = MarketService.normWear(s.substring(start + 1, end));
    for (let i = 0; i < WEAR_CN.length; i++) {
      if (w === WEAR_CN[i]) {
        return w;
      }
    }
    return '';
  }

  /**
   * 该条目自身的磨损档。
   * 优先用**结构化字段**（BUFF 的 `exterior` / 悠悠有品的 `abradeText`），
   * 字段为空时才退回从名字里认。
   */
  private static wearOf(item: ItemSummary): string {
    const fromField: string = MarketService.normWear(item.exterior);
    if (fromField.length > 0) {
      return fromField;
    }
    return MarketService.wearFromName(item.name);
  }

  /**
   * 配对键 = **款式 + 磨损**。
   *
   * 只按"去掉磨损后缀的基础名"配对、再在同一款式的所有磨损里取最便宜的一条当代表，
   * 会出现"名字是一个档、价格是另一个档"的行。只剥掉**确实是磨损**的那个括号组，
   * 别把 "(★)" 这类款式名的一部分也剥掉。
   */
  private static pairKey(item: ItemSummary): string {
    const s: string = MarketService.toHalfWidth(item.name);
    const wear: string = MarketService.wearOf(item);
    let base: string = s;
    if (MarketService.wearFromName(item.name).length > 0) {
      const end: number = s.lastIndexOf(')');
      const start: number = end < 0 ? -1 : s.lastIndexOf('(', end);
      if (start >= 0) {
        base = s.substring(0, start);
      }
    }
    return `${base.replace(/\s+/g, '').toLowerCase()}|${wear}`;
  }

  /** 按"款式+磨损"归并，同一组里取最便宜的一条作为代表 */
  private static indexByName(items: ItemSummary[]): Map<string, ItemSummary> {
    const m: Map<string, ItemSummary> = new Map();
    for (let i = 0; i < items.length; i++) {
      const it: ItemSummary = items[i];
      const k: string = MarketService.pairKey(it);
      if (k.length <= 1) {
        continue;
      }
      const exist: ItemSummary | undefined = m.get(k);
      // 取更便宜的一条作为该款式的代表
      if (exist === undefined) {
        m.set(k, it);
      } else {
        const a: number = exist.sellPriceCent ?? Number.MAX_SAFE_INTEGER;
        const b: number = it.sellPriceCent ?? Number.MAX_SAFE_INTEGER;
        if (b < a) {
          m.set(k, it);
        }
      }
    }
    return m;
  }

  private static adviceOf(diffPct: number | null, bp: number | null,
    up: number | null): string {
    if (bp === null && up === null) {
      return '两边都没有在售';
    }
    if (bp === null) {
      return `仅 ${PlatformMeta.shortLabel(Platform.UU)} 有货`;
    }
    if (up === null) {
      return `仅 ${PlatformMeta.shortLabel(Platform.BUFF)} 有货`;
    }
    if (diffPct === null) {
      return '价差未知';
    }
    if (diffPct >= 8) {
      return `BUFF 贵 ${diffPct.toFixed(1)}%，可从悠悠有品入手`;
    }
    if (diffPct <= -8) {
      return `悠悠有品贵 ${Math.abs(diffPct).toFixed(1)}%，可从 BUFF 入手`;
    }
    return `价差 ${Math.abs(diffPct).toFixed(1)}%，两平台接近`;
  }
}
