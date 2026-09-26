/**
 * 悠悠有品 数据源。
 *
 * 接口路径取自平台 PC 网页版的懒加载 chunk（`p__GoodsList__index.<hash>.async.js`，
 * webpack chunk 663）：
 *   POST /api/homepage/pc/goods/market/queryOnSaleCommodityList   在售列表
 *   POST /api/homepage/pc/goods/market/queryOnLeaseCommodityList  租赁列表
 *   POST /api/homepage/pc/goods/market/queryTemplateDetail
 *   POST /api/homepage/pc/goods/market/querySortList
 * 请求体字段同样照抄该 chunk：{ pageIndex, pageSize, gameId, listType, listSortType, sortType,
 * keyWords, sortTypeKey, templateId, ... }。响应外层是 { Code, Msg, Data: 数组, TotalCount }，
 * Code === 0 才是成功（84101 / 84103 / 2002 表示需要登录）。
 *
 * 取数恒定走网页桥接，原生直连没有成功可能：平台网关（阿里云 ALB + WAF）对非浏览器客户端
 * 一律返回 503 或 403，换成浏览器内核访问同一 URL 才能拿到 JSON。
 * 页面上下文是 https://www.youpin898.com，跨域打到 pc-api，与平台自家前端的行为一致。
 */

import { AppError, FailKind, FetchChannel, Game, ItemSummary, MarketQuery,
  PageResult, Platform, PlatformMeta, TrendData } from '../model/Types';
import { MarketProvider } from './MarketProvider';
import { WebBridge, BridgeResult, BridgeHeader } from './WebBridge';
import { WebSessionBridge } from './WebSessionBridge';
import { ParseUtil } from './ParseUtil';
import { PreferencesStore } from './PreferencesStore';
import { Logger } from '../common/Logger';

const TAG: string = 'UuProvider';

const KEY_LIST_PATH: string = 'uu_path_list';
const KEY_SEARCH_PATH: string = 'uu_path_search';
const KEY_TREND_PATH: string = 'uu_path_trend';
const KEY_DETAIL_PATH: string = 'uu_path_detail';
const KEY_DEVICE_ID: string = 'uu_device_id';
const KEY_SECRET_V: string = 'uu_secret_v';

/** 桥接头的 localStorage 占位前缀（由 WebBridge 解析） */
const LS_PREFIX: string = '@ls:';

/**
 * 默认路径：照抄平台自家 PC 网页版前端（可在设置页覆盖）。
 *  - `querySaleTemplate`：分类浏览（/market 页的商品网格），只认 listSortType/sortType/翻页，
 *    **不认 keyWords**。
 *  - `lenovoSearch`：平台自己的搜索接口（/market 页搜索框走的它，入参 keyWords + listType）。
 *  - `queryOnSaleCommodityList`：某个款式（templateId）下的在售单列表（/market/goods-list 二级页）。
 */
const DEFAULT_LIST_PATH: string = '/api/homepage/pc/goods/market/querySaleTemplate';
const DEFAULT_SEARCH_PATH: string = '/api/homepage/pc/goods/market/lenovoSearch';
/** 走势平台未提供，用同一个搜索路径占位（设置页第三个框现在是"搜索路径"） */
const DEFAULT_TREND_PATH: string = '/api/homepage/pc/goods/market/lenovoSearch';
/** 单款式下的在售单（取最低价用） */
const DEFAULT_DETAIL_PATH: string = '/api/homepage/pc/goods/market/queryOnSaleCommodityList';

/** 平台前端版本号（网关按此识别自家客户端，缺了它拿不到数据） */
const APP_VERSION: string = '5.26.0';
const SECRET_V_DEFAULT: string = 'h5_v1';

/** 列表请求里与平台约定一致的固定值（取自平台前端实际发出的报文） */
const LIST_SORT_TYPE_SALE: number = 0;
const SORT_TYPE_DEFAULT: number = 0;
/** 平台搜索/排序接口用的"在售"业务线标识（平台报文里是字符串 "10"） */
const LIST_TYPE_SALE: string = '10';

/**
 * CS2 的市场请求**不带 gameId**（平台自家报文就是 `{"listSortType":0,"sortType":0,"pageSize":20,"pageIndex":1}`）。
 * 多带 gameId 时接口仍回 `Code:0` 但 `Data:null`，拿不到条目，所以默认不带；
 * 只有切到其它品类时才补 gameId。
 */
const CS2_GAME_ID: number = 730;

/** 统一外层：Data 是**数组**，不是对象 */
interface UuEnvelope {
  Code?: number;
  Msg?: string;
  Data?: UuRawItem[];
  TotalCount?: number;
  HasNext?: boolean;
}

/** 商品项：字段名照抄平台前端表格列定义（两个接口的命名不同，全部兜住） */
interface UuRawItem {
  /** 在售单接口的商品 ID */
  id?: string | number;
  /** 款式（模板）ID —— 市场浏览列表用的就是这个 */
  templateId?: string | number;
  /** 展示名 */
  commodityName?: string;
  name?: string;
  iconUrl?: string;
  /** 在售价，单位**元**（前端直接 `¥{price}` 渲染，没有除 100） */
  price?: string | number;
  /** 款式列表给的是最低价 */
  minPrice?: string | number;
  /** 磨损文本，如"略有磨损" */
  abradeText?: string;
  /** 渐变/花色文本 */
  fadeText?: string;
  /** 在售数量 */
  surplusQuantity?: number;
  onSaleCount?: number;
}

/** 搜索请求体 */
interface UuSearchBody {
  keyWords: string;
  listType: string;
}

/** 某款式下的在售单请求体（取最低价用） */
interface UuPriceBody {
  gameId?: number;
  templateId: string;
  listType: string;
  listSortType: number;
  sortType: number;
  pageIndex: number;
  pageSize: number;
}

/** 列表请求体（对齐 querySaleTemplate 的实际报文；gameId 可选） */
interface UuListBody {
  gameId?: number;
  pageIndex: number;
  pageSize: number;
  listSortType: number;
  sortType: number;
  keyWords?: string;
}

// ---------------------------------------------------------------------------
// 匿名设备标识
// 平台前端把 deviceId / uk / deviceUk 本地生成后长期复用（抓包可见）。
// 这里同样本地生成并持久化，不涉及账号，只是让网关认得出是个正常客户端。
// ---------------------------------------------------------------------------

const HEX_CHARS: string = 'abcdef0123456789';

function randomFrom(alphabet: string, len: number): string {
  let s: string = '';
  for (let i = 0; i < len; i++) {
    s += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
  }
  return s;
}

function uuidLike(): string {
  return `${randomFrom(HEX_CHARS, 8)}-${randomFrom(HEX_CHARS, 4)}-` +
    `${randomFrom(HEX_CHARS, 4)}-${randomFrom(HEX_CHARS, 4)}-${randomFrom(HEX_CHARS, 12)}`;
}

function persisted(key: string, factory: () => string): string {
  const cached: string = PreferencesStore.getString(key, '');
  if (cached.length > 0) {
    return cached;
  }
  const v: string = factory();
  PreferencesStore.put(key, v);
  return v;
}

export class UuDevice {
  /** 本地生成的设备 uuid（平台前端同样是本地生成） */
  static deviceId(): string {
    return persisted(KEY_DEVICE_ID, () => uuidLike());
  }

  static secretV(): string {
    return PreferencesStore.getString(KEY_SECRET_V, SECRET_V_DEFAULT);
  }
}

export class UuEndpoints {
  static listPath(): string {
    return PreferencesStore.getString(KEY_LIST_PATH, DEFAULT_LIST_PATH);
  }

  /**
   * 搜索接口（带关键词时走它，而不是分类浏览接口）。
   * 与设置页的"搜索路径"共用同一个 Preferences 键（KEY_TREND_PATH）。
   */
  static searchPath(): string {
    return PreferencesStore.getString(KEY_TREND_PATH, DEFAULT_SEARCH_PATH);
  }

  static trendPath(): string {
    return PreferencesStore.getString(KEY_TREND_PATH, DEFAULT_TREND_PATH);
  }

  static detailPath(): string {
    return PreferencesStore.getString(KEY_DETAIL_PATH, DEFAULT_DETAIL_PATH);
  }

  static setListPath(p: string): void {
    PreferencesStore.put(KEY_LIST_PATH, p);
  }

  static setSearchPath(p: string): void {
    PreferencesStore.put(KEY_SEARCH_PATH, p);
  }

  static setTrendPath(p: string): void {
    PreferencesStore.put(KEY_TREND_PATH, p);
  }

  static setDetailPath(p: string): void {
    PreferencesStore.put(KEY_DETAIL_PATH, p);
  }

  static defaultListPath(): string {
    return DEFAULT_LIST_PATH;
  }

  static defaultSearchPath(): string {
    return DEFAULT_SEARCH_PATH;
  }

  static defaultTrendPath(): string {
    return DEFAULT_TREND_PATH;
  }

  static defaultDetailPath(): string {
    return DEFAULT_DETAIL_PATH;
  }
}

export class UuProvider implements MarketProvider {
  hasSession(): boolean {
    return WebSessionBridge.isLoggedIn(Platform.UU);
  }

  async list(query: MarketQuery, channel: FetchChannel): Promise<PageResult> {
    /*
     * 分类浏览接口（querySaleTemplate）同时承担浏览与关键词过滤：平台自家 /market 页的搜索框
     * 确认后，就是把 `keyWords` 塞进同一份列表参数里的。它是唯一带 `minPrice` 的列表接口 ——
     * 搜索接口（lenovoSearch）只回名字和 templateId、不带价格，拿它当列表会让比价把
     * 悠悠有品全判成"没有这件货"。所以这里统一走它，`searchPath()` 只用于按名字找 templateId。
     */
    const kw: string = query.keyword.trim();
    const body: string = UuProvider.buildListBody(query, '');
    const text: string = await UuProvider.fetch(UuEndpoints.listPath(), 'POST', body);
    const raw: UuRawItem[] = UuProvider.unwrap(text);
    const items: ItemSummary[] = [];
    for (let i = 0; i < raw.length; i++) {
      const mapped: ItemSummary | undefined = UuProvider.mapItem(raw[i], query.game);
      if (mapped !== undefined) {
        items.push(mapped);
      }
    }
    Logger.i(TAG, `悠悠有品列表 ${items.length} 条（关键词=${kw.length > 0 ? kw : '无'}）`);
    return { items: items, hasMore: raw.length >= query.pageSize };
  }

  /**
   * 单品当前价，两步：
   *   1) 用搜索接口按名字拿到 `templateId`；
   *   2) 用"款式下在售单"接口（queryOnSaleCommodityList）取该款式的最低在售价。
   *
   * 搜索接口（lenovoSearch）只回名字和 templateId、不带价格，直接拿搜索结果当价格会全是 null，
   * 比价就会把悠悠有品判成"没有这件货"。
   */
  async quote(item: ItemSummary, channel: FetchChannel): Promise<number | null> {
    const kw: string = UuProvider.baseName(item.name);
    if (kw.length === 0) {
      return null;
    }
    const text: string = await UuProvider.fetch(UuEndpoints.searchPath(), 'POST',
      UuProvider.buildSearchBody(kw));
    const raw: UuRawItem[] = UuProvider.unwrap(text);

    // 先挑款式：优先同 id，其次同名
    let templateId: string = '';
    let fallback: string = '';
    for (let i = 0; i < raw.length; i++) {
      const row: UuRawItem = raw[i];
      const tid: string = `${row.templateId ?? row.id ?? ''}`;
      if (tid.length === 0) {
        continue;
      }
      // 搜索结果自带 minPrice 时直接用（部分响应会带）
      const direct: number | null = UuProvider.priceToCent(row.minPrice ?? row.price);
      if (tid === item.goodsId) {
        if (direct !== null) {
          return direct;
        }
        templateId = tid;
        break;
      }
      if (fallback.length === 0
        && UuProvider.baseName(row.commodityName ?? row.name ?? '') === kw) {
        fallback = tid;
        if (direct !== null) {
          return direct;
        }
      }
    }
    if (templateId.length === 0) {
      templateId = fallback;
    }
    if (templateId.length === 0) {
      return null;
    }

    // 取该款式的最低在售价
    const body: UuPriceBody = {
      gameId: Number.parseInt(UuProvider.gameId(item.game), 10),
      templateId: templateId,
      listType: LIST_TYPE_SALE,
      listSortType: LIST_SORT_TYPE_SALE,
      sortType: SORT_TYPE_DEFAULT,
      pageIndex: 1,
      pageSize: 20
    };
    const priceText: string = await UuProvider.fetch(UuEndpoints.detailPath(), 'POST',
      JSON.stringify(body));
    const offers: UuRawItem[] = UuProvider.unwrap(priceText);
    let min: number | null = null;
    for (let i = 0; i < offers.length; i++) {
      const cent: number | null = UuProvider.priceToCent(offers[i].price ?? offers[i].minPrice);
      if (cent !== null && (min === null || cent < min)) {
        min = cent;
      }
    }
    Logger.i(TAG, `取价 ${item.name} → templateId=${templateId} 报价 ${offers.length} 条 最低=${min}`);
    return min;
  }

  /**
   * 成交价走势：悠悠有品网页端没有公开的走势接口（前端只有模板详情 / 排序表 / 联想搜索）。
   * 不猜路径：返回空序列，详情页显示"0 笔成交"而不是整页报错。
   */
  async trend(item: ItemSummary, channel: FetchChannel): Promise<TrendData> {
    Logger.i(TAG, '悠悠有品未提供走势接口，返回空序列');
    const empty: TrendData = {
      goodsId: item.goodsId,
      platform: Platform.UU,
      points: [],
      minCent: 0,
      maxCent: 0,
      volume: 0
    };
    return empty;
  }

  // -------------------------------------------------------------------------
  // 请求
  // -------------------------------------------------------------------------

  /** 搜索请求体：平台 /market 搜索框实际发出的就是 {keyWords, listType} */
  private static buildSearchBody(kw: string): string {
    const b: UuSearchBody = { keyWords: kw, listType: LIST_TYPE_SALE };
    return JSON.stringify(b);
  }

  private static buildListBody(query: MarketQuery, keywordOverride: string): string {
    const gameId: number = Number.parseInt(UuProvider.gameId(query.game), 10);
    const kw: string = keywordOverride.length > 0 ? keywordOverride : query.keyword.trim();
    // ArkTS 不允许运行时改对象结构，所以按"是否 CS2 / 有无关键词"分别建字面量。
    // 逐字对齐平台自家报文：CS2 默认请求不带 gameId。
    const needGame: boolean = gameId !== CS2_GAME_ID;
    let body: UuListBody;
    if (needGame && kw.length > 0) {
      body = { gameId: gameId, listSortType: LIST_SORT_TYPE_SALE, sortType: SORT_TYPE_DEFAULT,
        pageSize: query.pageSize, pageIndex: query.pageNum, keyWords: kw };
    } else if (needGame) {
      body = { gameId: gameId, listSortType: LIST_SORT_TYPE_SALE, sortType: SORT_TYPE_DEFAULT,
        pageSize: query.pageSize, pageIndex: query.pageNum };
    } else if (kw.length > 0) {
      body = { listSortType: LIST_SORT_TYPE_SALE, sortType: SORT_TYPE_DEFAULT,
        pageSize: query.pageSize, pageIndex: query.pageNum, keyWords: kw };
    } else {
      body = { listSortType: LIST_SORT_TYPE_SALE, sortType: SORT_TYPE_DEFAULT,
        pageSize: query.pageSize, pageIndex: query.pageNum };
    }
    return JSON.stringify(body);
  }

  private static gameId(g: Game): string {
    // Steam AppID：CS2=730、DOTA2=570、RUST=252490、TF2=440
    if (g === Game.DOTA2) {
      return '570';
    }
    if (g === Game.RUST) {
      return '252490';
    }
    if (g === Game.TF2) {
      return '440';
    }
    return '730';
  }

  /**
   * 平台网关要求的自定义头。两条硬规则：
   *  1. 这组头**必须有**。不带时网关让浏览器直接 `Failed to fetch`
   *     （XHR 表现为 `status=0` + 空 body）；带上返回 200。
   *  2. `uk` / `deviceUk` **不能用随机值**。它们由平台用浏览器指纹加密后经
   *     `POST /api/deviceW2` 签发、写进 `localStorage`（键名 `WEB_UK` / `WEB_DEVICE_UK`）；
   *     发随机值会被判定为非法客户端，平台回的是
   *     `{"code":85100,"msg":"当前app版本过低，请前往更新"}`。
   *     这里用 `@ls:` 占位符，让桥接在**平台自己的页面**里读它签发的值：
   *     隐藏容器加载的就是 www.youpin898.com，平台前端会自行完成注册。
   *     `deviceId` 则是本地生成的 uuid（平台自己也是本地生成）。
   */
  private static headers(): BridgeHeader[] {
    const hs: BridgeHeader[] = [];
    hs.push({ name: 'secret-v', value: UuDevice.secretV() });
    hs.push({ name: 'platform', value: 'pc' });
    hs.push({ name: 'appType', value: '1' });
    hs.push({ name: 'AppVersion', value: APP_VERSION });
    hs.push({ name: 'App-Version', value: APP_VERSION });
    hs.push({ name: 'deviceId', value: UuDevice.deviceId() });
    hs.push({ name: 'uk', value: LS_PREFIX + 'WEB_UK' });
    hs.push({ name: 'deviceUk', value: LS_PREFIX + 'WEB_DEVICE_UK' });
    /*
     * 登录态：平台的登录令牌放在 **JS 可读的 Cookie `uu_token`** 里，平台前端把它读出来
     * 作为 `Authorization` 头发出去。没登录时这个 Cookie 不存在，此时跳过该头即可
     * （浏览接口匿名可用）。不能靠 Cookie 自动携带：接口 CORS 是 `Allow-Origin: *`，
     * 开 withCredentials 会被拦。
     */
    hs.push({ name: 'authorization', value: '@optcookie:uu_token' });
    return hs;
  }

  /**
   * 发起请求。**恒定走网页桥接**（忽略全局取数通道设置）：
   * 平台网关对非浏览器客户端一律 503，原生直连没有成功可能。
   * 绝对 URL 会被 XHR 当跨域请求，页面上下文是 www.youpin898.com —— 与平台自家前端一致。
   */
  private static async fetch(path: string, method: string, jsonBody: string): Promise<string> {
    const url: string = `${PlatformMeta.apiBase(Platform.UU)}${path}`;
    Logger.i(TAG, `桥接请求 ${method} ${path} 体=${jsonBody}`);
    const res: BridgeResult = await WebBridge.run(
      Platform.UU, url, method, jsonBody, UuProvider.headers());
    // 诊断用：把平台原始响应打进 hilog（排查接口/参数用，稳定后可降级为 d 级）
    const peek: string = res.text.length > 700 ? res.text.substring(0, 700) : res.text;
    Logger.i(TAG, `响应 HTTP ${res.status} origin=${res.origin} 原文=${peek}`);
    if (res.status === 0) {
      // status 0 = 浏览器根本没拿到响应：跨域被拦（多半是自定义头没被放行）/ 请求被中止 / 网络中断
      const needIdentity: boolean = res.text.indexOf('missing-localStorage:') >= 0;
      throw new AppError(FailKind.UNAVAILABLE, needIdentity
        ? '还没拿到悠悠有品的设备标识。请在「我的 → 去官网登录」里打开一次悠悠有品网页' +
          '（让平台前端完成设备注册），再回来重试。'
        : '没能拿到悠悠有品的响应（连接被中断）。可能是平台网关拦截或网络中断，' +
          '稍后或换个网络（如移动数据）再试。');
    }
    if (res.status === 429) {
      throw new AppError(FailKind.UNAVAILABLE, '访问过于频繁被悠悠有品限流，请等几分钟再试');
    }
    if (res.status === 403 || res.status === 503) {
      throw new AppError(FailKind.UNAVAILABLE,
        `被悠悠有品风控拦截（HTTP ${res.status}），请稍后再试`);
    }
    if (res.status < 200 || res.status >= 300) {
      throw new AppError(FailKind.UNAVAILABLE, `悠悠有品返回 HTTP ${res.status}`);
    }
    UuProvider.assertNotBlocked(res.text);
    return res.text;
  }

  /** 把平台的风控/网关拦截页翻译成人话，别把 HTML 当成"解析失败" */
  private static assertNotBlocked(text: string): void {
    const head: string = text.length > 4096 ? text.substring(0, 4096) : text;
    if (head.indexOf('block_message') >= 0 || head.indexOf('errors.aliyun.com') >= 0) {
      throw new AppError(FailKind.UNAVAILABLE,
        '请求被悠悠有品风控拦截（同一网络访问过于频繁）。请稍后再试，' +
        '或换成移动数据/其他网络重试。');
    }
    if (head.indexOf('<center>alb</center>') >= 0
      || head.indexOf('Service Temporarily Unavailable') >= 0) {
      throw new AppError(FailKind.UNAVAILABLE,
        '悠悠有品网关暂时不可用（503），请稍后重试');
    }
    if (head.indexOf('405 Not Allowed') >= 0 || head.indexOf('403 Forbidden') >= 0) {
      throw new AppError(FailKind.UNAVAILABLE,
        '悠悠有品拒绝了这次请求，接口地址可能已变更');
    }
  }

  // -------------------------------------------------------------------------
  // 解析
  // -------------------------------------------------------------------------

  private static unwrap(text: string): UuRawItem[] {
    if (text.length === 0) {
      throw new AppError(FailKind.PARSE, '悠悠有品返回空响应');
    }
    let env: UuEnvelope;
    try {
      env = JSON.parse(text) as UuEnvelope;
    } catch (e) {
      throw new AppError(FailKind.PARSE, '悠悠有品响应不是合法 JSON');
    }
    const code: number = env.Code ?? -1;
    if (code === 84101 || code === 84103 || code === 2002) {
      throw new AppError(FailKind.NEED_LOGIN, '请先在悠悠有品网页端登录');
    }
    if (code !== 0) {
      throw new AppError(FailKind.UNAVAILABLE,
        env.Msg ?? `接口返回 Code=${code}`);
    }
    return env.Data ?? [];
  }

  private static mapItem(src: UuRawItem, game: Game): ItemSummary | undefined {
    // 两个接口的字段名不同：款式列表给 templateId/minPrice，在售单列表给 id/price
    const id: string = `${src.templateId ?? src.id ?? ''}`;
    if (id.length === 0) {
      return undefined;
    }
    const price: string | number | undefined = src.minPrice ?? src.price;
    const item: ItemSummary = {
      goodsId: id,
      platform: Platform.UU,
      game: game,
      name: src.commodityName ?? src.name ?? '',
      sellPriceCent: UuProvider.priceToCent(price),
      buyPriceCent: null,
      deltaPct: null,
      sellNum: ParseUtil.toInt(src.surplusQuantity ?? src.onSaleCount),
      iconUrl: src.iconUrl ?? '',
      exterior: src.abradeText ?? '',
      rarity: '',
      floatRange: src.fadeText ?? '',
      detailPath: `/goodsDetail?commodityId=${id}`
    };
    return item;
  }

  /** "1234.56" / 1234.56 → 分；非法或非正返回 null */
  private static priceToCent(v: string | number | undefined): number | null {
    if (v === undefined || v === null) {
      return null;
    }
    const n: number = typeof v === 'number' ? v : Number.parseFloat(v);
    if (Number.isNaN(n) || n <= 0) {
      return null;
    }
    return Math.round(n * 100);
  }

  /** 去掉磨损后缀的基础名，用于搜索与配对 */
  private static baseName(name: string): string {
    const idx: number = name.indexOf('(');
    const core: string = idx > 0 ? name.substring(0, idx) : name;
    return core.replace(/\s+/g, ' ').trim();
  }
}
