/**
 * Steam 接入：库存、账号解析、官方 Web API。
 *
 * 1. 库存走社区公开接口 `GET https://steamcommunity.com/inventory/{steamid64}/{appid}/{contextid}`，
 *    不需要 API key，但要求对方库存公开。返回 `{assets, descriptions, total_inventory_count}`：
 *    `assets` 只有物品与数量，名字、图标、磨损要按 `classid_instanceid` 去 `descriptions` 里查，
 *    两边必须关联，否则列表全是空名字。
 * 2. 自定义 ID 与个人资料链接换成 SteamID64：`GET https://steamcommunity.com/id/{vanity}/?xml=1`
 *    解析 `<steamID64>`，同样不需要 API key。
 * 3. 官方 Web API 通用入口（`api.steampowered.com`，需要自己的 key）：`webApi(method, version, params, key)`。
 *
 * steamcommunity.com / api.steampowered.com 在国内网络通常无法直连，需要自备代理；
 * 这里不做绕过，失败时按错误类型给出提示。
 */

import { AppError, FailKind } from '../model/Types';
import { HttpClient, HttpResult } from './HttpClient';
import { BridgeResult, WebBridge } from './WebBridge';
import { Logger } from '../common/Logger';

const TAG: string = 'SteamProvider';

/** 社区站点（库存、个人资料 XML） */
const COMMUNITY_BASE: string = 'https://steamcommunity.com';
/** 官方 Web API */
const WEB_API_BASE: string = 'https://api.steampowered.com';

/** CS2 */
export const STEAM_APP_CS2: number = 730;
/** 物品上下文（CS2 固定为 2） */
export const STEAM_CONTEXT_CS2: string = '2';

// ---------------------------------------------------------------------------
// 原始响应
// ---------------------------------------------------------------------------

interface RawAsset {
  assetid?: string;
  classid?: string;
  instanceid?: string;
  amount?: string;
  appid?: number;
  contextid?: string;
}

interface RawTag {
  category?: string;
  internal_name?: string;
  localized_category_name?: string;
  localized_tag_name?: string;
  color?: string;
}

interface RawDescription {
  classid?: string;
  instanceid?: string;
  icon_url?: string;
  name?: string;
  market_hash_name?: string;
  type?: string;
  tradable?: number;
  marketable?: number;
  tags?: RawTag[];
}

interface RawInventory {
  assets?: RawAsset[];
  descriptions?: RawDescription[];
  total_inventory_count?: number;
  success?: number;
  Error?: string;
}

// ---------------------------------------------------------------------------
// 展示模型
// ---------------------------------------------------------------------------

export interface SteamInvItem {
  assetId: string;
  /** 展示名，如 "AK-47 | 红线 (久经沙场)"；缺失时退回 market_hash_name */
  name: string;
  /** 市场名（拿去平台比价时用它） */
  marketName: string;
  iconUrl: string;
  amount: number;
  /** 外观（磨损），从 descriptions.tags 的 Exterior 项取 */
  exterior: string;
  /** 稀有度 */
  rarity: string;
  tradable: boolean;
}

export interface SteamInventory {
  /** 服务器回报的库存总件数 */
  totalCount: number;
  items: SteamInvItem[];
}

// ---------------------------------------------------------------------------
// 错误分型
// ---------------------------------------------------------------------------

/** 响应体片段（只用于日志/提示，压成单行并截断） */
function snippet(body: string, n: number = 120): string {
  const s: string = body.replace(/[\r\n\t]+/g, ' ').trim();
  if (s.length === 0) {
    return '';
  }
  return s.length > n ? `${s.substring(0, n)}…` : s;
}

/**
 * 传输层异常 → AppError（只处理"没拿到 HTTP 响应"的情况）。
 * 拿到响应之后的判断一律走 httpError：不要靠 message 里有没有 "403" 来分型，
 * 响应体一含该字样就会误判。
 */
function asAppError(e: Object, what: string): AppError {
  if (e instanceof AppError) {
    if (e.kind === FailKind.TIMEOUT || e.kind === FailKind.NETWORK) {
      return new AppError(e.kind,
        `${what}失败：连不上 Steam。国内网络通常需要自备代理后再试。`);
    }
    return e;
  }
  if (e instanceof Error) {
    const m: string = e.message.toLowerCase();
    const kind: FailKind = m.indexOf('timeout') >= 0 ? FailKind.TIMEOUT : FailKind.NETWORK;
    return new AppError(kind,
      `${what}失败：${e.message}（国内网络通常需要代理）`);
  }
  return new AppError(FailKind.NETWORK, `${what}失败`);
}

/** HTTP 状态码 → AppError；响应体片段一并写日志，失败原因常常只在 body 里 */
function httpError(what: string, status: number, body: string, isInventory: boolean): AppError {
  Logger.w(TAG, `${what} HTTP ${status} body=${snippet(body, 300)}`);
  if (status === 403) {
    return new AppError(FailKind.UNAVAILABLE, isInventory
      ? 'Steam 拒绝访问（403）。多半是这个账号的「库存」不是公开状态 —— ' +
        '到 Steam 个人资料 → 隐私设置 → 库存，改成「公开」后再试。'
      : 'Steam 拒绝访问（403）：这个个人资料或库存不公开。');
  }
  if (status === 404) {
    return new AppError(FailKind.UNAVAILABLE,
      '找不到这个 SteamID（404）。检查一下 ID 或自定义链接是否写对。');
  }
  if (status === 429) {
    return new AppError(FailKind.UNAVAILABLE,
      'Steam 限流了（429）：同一网络下短时间内请求太多，等几分钟再试。');
  }
  const tail: string = snippet(body, 100);
  return new AppError(FailKind.UNAVAILABLE,
    `${what}失败：HTTP ${status}${tail.length > 0 ? `（${tail}）` : ''}`);
}

export class SteamProvider {
  /**
   * 记住能取到数据的查询串（空串 = 不带参数）。
   *
   * 库存接口带 `count` 参数返回 400 + `null`，同一个 URL 在系统浏览器里却正常；
   * 不带查询参数才能拿到完整 JSON。所以先试带语言参数的（名字是中文），失败退回不带参数，
   * 并记住成功过的那个，之后直接用它，避免每次多打一发。
   */
  private static goodQuery: string | undefined = undefined;

  /** 库存接口的候选 URL：先带上语言，失败退回不带参数 */
  private static inventoryCandidates(base: string): string[] {
    if (SteamProvider.goodQuery !== undefined) {
      return [`${base}${SteamProvider.goodQuery}`];
    }
    return [`${base}?l=schinese`, base];
  }

  // -------------------------------------------------------------------------
  // 账号
  // -------------------------------------------------------------------------

  /**
   * 把用户输入统一成 SteamID64。
   * 支持：17 位纯数字（直接用）/ 自定义 ID / 个人资料链接。
   * 自定义 ID 走个人资料 XML（**不需要 API key**）。
   */
  static async resolveSteamId(input: string): Promise<string> {
    let s: string = input.trim();
    if (s.length === 0) {
      throw new AppError(FailKind.UNAVAILABLE, '请先填写 SteamID 或自定义链接');
    }
    // 从链接里抠出 id/xxx 或 profiles/xxx
    const idIdx: number = s.indexOf('/id/');
    const profIdx: number = s.indexOf('/profiles/');
    if (profIdx >= 0) {
      s = s.substring(profIdx + '/profiles/'.length);
    } else if (idIdx >= 0) {
      s = s.substring(idIdx + '/id/'.length);
    }
    s = s.split('/')[0].split('?')[0].trim();

    if (SteamProvider.isSteamId64(s)) {
      return s;
    }

    const url: string = `${COMMUNITY_BASE}/id/${encodeURIComponent(s)}/?xml=1`;
    const xml: string = await SteamProvider.fetchText([url], '解析自定义 ID', false);
    const m: RegExpMatchArray | null = xml.match(/<steamID64>(\d{17})<\/steamID64>/);
    if (m === null) {
      throw new AppError(FailKind.UNAVAILABLE,
        '没能从这个自定义 ID 解析出 SteamID64。请直接填 17 位数字 ID，或贴个人资料链接。');
    }
    Logger.i(TAG, `自定义 ID ${s} → ${m[1]}`);
    return m[1];
  }

  static isSteamId64(s: string): boolean {
    return /^\d{17}$/.test(s);
  }

  // -------------------------------------------------------------------------
  // 库存
  // -------------------------------------------------------------------------

  /**
   * 带状态码判断的取文本，两条通道 + 查询串回退：
   *
   *  1. 原生 rcp（`HttpClient.getRaw`）：轻、快，能用就用；
   *  2. 页面导航（`WebBridge.navigateTo`）：原生被拒时，用隐藏浏览器容器导航到同一个 URL，
   *     等价于在浏览器地址栏里打开它。
   *
   * 第二条选导航而非容器内 XHR，是因为本站点对两者的反应不同：同一个 URL 下系统浏览器返回 200，
   * 原生 rcp 与容器内 XHR 都是 400 + `null`。查询串因此按候选列表逐个回退（见 inventoryCandidates）。
   *
   * 两条都失败时，优先抛原生直连的传输层错误（"连不上 / 需要代理"比一句 HTTP 码有用）。
   */
  private static async fetchText(candidates: string[], what: string,
    isInventory: boolean): Promise<string> {
    // 1) 原生直连只打第一个候选（能用它就不会有后面的事）
    let transportErr: AppError | undefined = undefined;
    try {
      const res: HttpResult = await HttpClient.getRaw(candidates[0], '', `${COMMUNITY_BASE}/`);
      if (res.status >= 200 && res.status < 300) {
        return res.text;
      }
      Logger.w(TAG, `${what}：原生直连 status=${res.status}，改用页面导航重取`);
    } catch (e) {
      transportErr = asAppError(e, what);
    }

    // 2) 页面导航：按候选顺序试，记住能用过的那一个
    let lastStatus: number = 0;
    let lastText: string = '';
    let lastOrigin: string = '';
    for (let i = 0; i < candidates.length; i++) {
      let br: BridgeResult;
      try {
        br = await WebBridge.navigateTo(candidates[i]);
      } catch (e) {
        throw transportErr ?? asAppError(e, what);
      }
      if (br.status >= 200 && br.status < 300) {
        if (candidates.length > 1) {
          SteamProvider.goodQuery = SteamProvider.queryOf(candidates[i]);
          Logger.i(TAG, `${what}：候选 #${i + 1} 可用，记住查询串「${SteamProvider.goodQuery}」`);
        }
        return br.text;
      }
      Logger.w(TAG, `${what}：候选 #${i + 1} status=${br.status} bytes=${br.text.length}`);
      if (br.status === 0) {
        break;
      }
      lastStatus = br.status;
      lastText = br.text;
      lastOrigin = br.origin;
    }
    if (lastStatus === 0) {
      // 一次响应都没拿到（网络中断 / 超时）
      throw transportErr ?? new AppError(FailKind.NETWORK,
        `${what}失败：连不上 Steam（原生直连与页面导航都没拿到响应）。` +
        '国内网络通常需要自备代理后再试。');
    }
    Logger.w(TAG, `${what} 最后一次来自 ${lastOrigin}`);
    throw httpError(what, lastStatus, lastText, isInventory);
  }

  /** 从完整 URL 里取出查询串（含 `?`；没有则空串） */
  private static queryOf(url: string): string {
    const i: number = url.indexOf('?');
    return i < 0 ? '' : url.substring(i);
  }

  /** 拉取并解析库存（默认 CS2） */
  static async fetchInventory(steamId64: string,
    appId: number = STEAM_APP_CS2,
    contextId: string = STEAM_CONTEXT_CS2): Promise<SteamInventory> {
    const base: string = `${COMMUNITY_BASE}/inventory/${steamId64}/${appId}/${contextId}`;
    const text: string = await SteamProvider.fetchText(
      SteamProvider.inventoryCandidates(base), '读取库存', true);
    return SteamProvider.parseInventory(text);
  }

  /** 关联 assets 与 descriptions；这是最容易漏的一步 */
  private static parseInventory(text: string): SteamInventory {
    if (text.length === 0) {
      throw new AppError(FailKind.UNAVAILABLE, 'Steam 返回空响应');
    }
    let raw: RawInventory;
    try {
      raw = JSON.parse(text) as RawInventory;
    } catch (e) {
      // 响应体片段写日志：站点改版 / 返回 HTML（需代理）时，一眼能看出来
      Logger.w(TAG, `库存响应不是 JSON，前 160 字符：${snippet(text, 160)}`);
      throw new AppError(FailKind.PARSE,
        'Steam 返回的不是 JSON（很可能被网络拦截或需要代理）');
    }
    if (raw.success !== 1 && raw.success !== undefined) {
      throw new AppError(FailKind.UNAVAILABLE, raw.Error ?? 'Steam 未返回库存数据');
    }

    const descOf: Map<string, RawDescription> = new Map<string, RawDescription>();
    const descs: RawDescription[] = raw.descriptions ?? [];
    for (let i = 0; i < descs.length; i++) {
      const d: RawDescription = descs[i];
      descOf.set(`${d.classid ?? ''}_${d.instanceid ?? ''}`, d);
    }

    const assets: RawAsset[] = raw.assets ?? [];
    const items: SteamInvItem[] = [];
    for (let i = 0; i < assets.length; i++) {
      const a: RawAsset = assets[i];
      const d: RawDescription | undefined =
        descOf.get(`${a.classid ?? ''}_${a.instanceid ?? ''}`);
      if (d === undefined) {
        continue;
      }
      const amount: number = Number.parseInt(a.amount ?? '1', 10);
      const item: SteamInvItem = {
        assetId: `${a.assetid ?? ''}`,
        name: d.name ?? d.market_hash_name ?? '',
        marketName: d.market_hash_name ?? d.name ?? '',
        iconUrl: SteamProvider.iconUrlOf(d.icon_url ?? ''),
        amount: Number.isNaN(amount) ? 1 : amount,
        exterior: SteamProvider.tagOf(d.tags, 'Exterior'),
        rarity: SteamProvider.tagOf(d.tags, 'Rarity'),
        tradable: (d.tradable ?? 0) === 1
      };
      items.push(item);
    }
    Logger.i(TAG, `库存解析：${items.length} 项（assets=${assets.length} / ` +
      `descriptions=${descs.length}）/ 服务器报 ${raw.total_inventory_count ?? 0} 件`);
    return { totalCount: raw.total_inventory_count ?? items.length, items: items };
  }

  private static tagOf(tags: RawTag[] | undefined, category: string): string {
    if (tags === undefined) {
      return '';
    }
    for (let i = 0; i < tags.length; i++) {
      const t: RawTag = tags[i];
      if (t.category === category || t.internal_name === category) {
        return t.localized_tag_name ?? '';
      }
    }
    return '';
  }

  /** icon_url 是相对片段，要拼成完整地址；Steam 对空值会返回一张占位图 */
  private static iconUrlOf(iconUrl: string): string {
    if (iconUrl.length === 0) {
      return '';
    }
    if (iconUrl.indexOf('http') === 0) {
      return iconUrl;
    }
    return `https://community.cloudflare.steamstatic.com/economy/image/${iconUrl}`;
  }

  // -------------------------------------------------------------------------
  // 官方 Web API（通用入口，需要用户自己的 key）
  // -------------------------------------------------------------------------

  /**
   * 调用 api.steampowered.com 的任意接口。
   * 例：`webApi('ISteamUser', 'GetPlayerSummaries', 'v0002', 'steamids=xxx', key)`
   * 本页暂未使用，留给后续接成就 / 游戏时长等能力。
   */
  static async webApi(iface: string, method: string, version: string,
    params: string, apiKey: string): Promise<string> {
    if (apiKey.trim().length === 0) {
      throw new AppError(FailKind.UNAVAILABLE, '需要先在设置里填入 Steam Web API Key');
    }
    const q: string = params.length > 0 ? `&${params}` : '';
    const url: string = `${WEB_API_BASE}/${iface}/${method}/${version}/?key=${apiKey}${q}&format=json`;
    return await SteamProvider.fetchText([url], `${iface}/${method}`, false);
  }
}
