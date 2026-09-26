/**
 * Types.ets — 全局领域模型
 * ArkTS 约束：禁止 any；对象字面量必须有类型标注；运行时不得改变对象结构。
 * 因此所有接口字段一律显式声明，来自网络的响应统一用"全可选字段 + 防御式取值"。
 */

/** 平台 */
export enum Platform {
  BUFF = 'buff',
  UU = 'uu'
}

/** 支持的游戏品类 */
export enum Game {
  CSGO = 'csgo',
  DOTA2 = 'dota2',
  RUST = 'rust',
  TF2 = 'tf2'
}

/** 排序方式 */
export enum SortBy {
  DEFAULT = 'default',
  PRICE_ASC = 'price_asc',
  PRICE_DESC = 'price_desc',
  HOT = 'hot'
}

/** 数据取数通道 */
export enum FetchChannel {
  /** 原生 HTTP 直连平台网页接口（复用 WebView 取到的会话 Cookie） */
  DIRECT = 'direct',
  /** 把查询丢进隐藏的 ArkWeb 容器，用页面同源上下文取数（接口有签名/风控时更稳） */
  BRIDGE = 'bridge'
}

/** 列表项（行情） */
export interface ItemSummary {
  /** 平台内商品 ID */
  goodsId: string;
  platform: Platform;
  game: Game;
  /** 展示名，如 "AK-47 | 红线 (略有磨损)" */
  name: string;
  /** 在售价（分），null 表示当前无在售 */
  sellPriceCent: number | null;
  /** 求购价（分） */
  buyPriceCent: number | null;
  /** 相对上次快照的涨跌幅（%） */
  deltaPct: number | null;
  /** 在售数量 */
  sellNum: number | null;
  /** 图片地址 */
  iconUrl: string;
  /** 外观，如 "崭新出厂" */
  exterior: string;
  /** 稀有度 */
  rarity: string;
  /** 磨损区间文本 */
  floatRange: string;
  /** 详情页路径（相对平台站点） */
  detailPath: string;
}

/** 价格走势点 */
export interface PricePoint {
  /** 成交时间戳（毫秒） */
  ts: number;
  /** 成交价（分） */
  priceCent: number;
}

/** 走势数据 */
export interface TrendData {
  goodsId: string;
  platform: Platform;
  points: PricePoint[];
  /** 区间最低/最高（分），用于坐标轴 */
  minCent: number;
  maxCent: number;
  /** 近 7 日成交量 */
  volume: number;
}

/** 自选条目（本地持久化） */
export interface WatchItem {
  /** 唯一键：platform + ':' + goodsId */
  key: string;
  platform: Platform;
  game: Game;
  goodsId: string;
  name: string;
  iconUrl: string;
  /** 我录入的成本价（分），0 表示未录入 */
  costCent: number;
  /** 加入自选时的价格快照（分），用于涨跌基线 */
  baseCent: number;
  /** 加入时间戳 */
  addedTs: number;
}

/** 自选条目 + 实时行情（运行时合成，不落盘） */
export interface WatchQuote {
  item: WatchItem;
  currentCent: number | null;
  /** 相对成本价的盈亏百分比 */
  profitPct: number | null;
  /** 相对加入时快照的涨跌百分比 */
  deltaPct: number | null;
}

/** 行情查询 */
export interface MarketQuery {
  platform: Platform;
  game: Game;
  keyword: string;
  sortBy: SortBy;
  pageNum: number;
  pageSize: number;
}

/** 分页结果 */
export interface PageResult {
  items: ItemSummary[];
  hasMore: boolean;
}

/** 比价结果 */
export interface CompareRow {
  name: string;
  buffPriceCent: number | null;
  uuPriceCent: number | null;
  /** 差价（分）：BUFF - UU；正数表示 BUFF 更贵 */
  diffCent: number | null;
  /** 差价百分比（相对较低价） */
  diffPct: number | null;
  /** 挂刀建议文案 */
  advice: string;
}

/** 平台账号（本地记录；Cookie 只存于 ArkWeb 自己的存储，不落盘到本文件） */
export interface AccountInfo {
  id: string;
  platform: Platform;
  /** 用户自定义别名 */
  alias: string;
  /** 最近一次探测到登录态的时间戳 */
  lastCheckTs: number;
  /** 最近一次探测时登录态是否有效 */
  loggedIn: boolean;
}

/** 统一的错误分型 */
export enum FailKind {
  TIMEOUT = 'timeout',
  NETWORK = 'network',
  HTTP_4XX = 'http_4xx',
  HTTP_5XX = 'http_5xx',
  PARSE = 'parse',
  NEED_LOGIN = 'need_login',
  UNAVAILABLE = 'unavailable'
}

/**
 * 统一业务异常。
 * 必须 extends Error —— ArkTS 的 arkts-limited-throw 规则不允许 throw 任意类型的值，
 * 只接受 Error 及其子类。别改成普通 class，否则编译直接报 10605087。
 */
export class AppError extends Error {
  kind: FailKind;

  constructor(kind: FailKind, message: string) {
    super(message);
    this.name = 'AppError';
    this.kind = kind;
  }
}

// ---------------------------------------------------------------------------
// 平台原始响应结构（字段全可选，做防御式解析）
// ---------------------------------------------------------------------------

/** BUFF 网页接口统一外层 */
export interface BuffEnvelope {
  code?: string;
  error?: string;
  data?: BuffGoodsPage;
}

/** BUFF /api/market/goods 的 data */
export interface BuffGoodsPage {
  items?: BuffGoodsItem[];
  total_count?: number;
  page_num?: number;
  page_size?: number;
}

/** BUFF 商品项 */
export interface BuffGoodsItem {
  id?: number;
  name?: string;
  market_hash_name?: string;
  sell_min_price?: string;
  buy_max_price?: string;
  /** 在售订单接口（sell_order）里的单价 */
  price?: string;
  sell_num?: number;
  goods_info?: BuffGoodsInfo;
}

export interface BuffGoodsInfo {
  icon_url?: string;
  exterior?: string;
  rarity?: string;
  info?: BuffGoodsInfoDetail;
}

export interface BuffGoodsInfoDetail {
  tags?: BuffGoodsTag[];
  steam_price_cny?: string;
}

export interface BuffGoodsTag {
  category?: string;
  internal_name?: string;
  localized_name?: string;
}

/** BUFF 成交记录 */
export interface BuffBillEnvelope {
  code?: string;
  data?: BuffBillData;
}

export interface BuffBillData {
  items?: BuffBillItem[];
  total_count?: number;
}

export interface BuffBillItem {
  price?: string;
  created_at?: number;
}

/** 平台元信息 */
export class PlatformMeta {
  static label(p: Platform): string {
    return p === Platform.BUFF ? '网易BUFF' : '悠悠有品';
  }

  static shortLabel(p: Platform): string {
    return p === Platform.BUFF ? 'BUFF' : 'UU';
  }

  /** 网页端首页（ArkWeb 承载入口） */
  static homeUrl(p: Platform): string {
    return p === Platform.BUFF ? 'https://buff.163.com/' : 'https://www.youpin898.com/';
  }

  /** Cookie 归属域（WebCookieManager 用完整 URL） */
  static cookieUrl(p: Platform): string {
    return p === Platform.BUFF ? 'https://buff.163.com' : 'https://www.youpin898.com';
  }

  /** 网页端 API 基址 */
  static apiBase(p: Platform): string {
    return p === Platform.BUFF
      ? 'https://buff.163.com'
      : 'https://pc-api.youpin898.com';
  }

  /** 商品详情页 URL */
  static detailUrl(p: Platform, game: Game, goodsId: string): string {
    if (p === Platform.BUFF) {
      return `https://buff.163.com/goods/${goodsId}?game=${game}`;
    }
    return `https://www.youpin898.com/goodsDetail?commodityId=${goodsId}&gameId=${game}`;
  }

  static all(): Platform[] {
    return [Platform.BUFF, Platform.UU];
  }
}
