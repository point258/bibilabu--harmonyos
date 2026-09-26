/**
 * rcp（Remote Communication Kit）单例封装。
 *
 * API 形态对着本机 SDK 声明核对过（`sdk/default/hms/ets/api/@hms.collaboration.rcp.d.ts`）：
 *  - `Configuration`（createSession 的 requestConfiguration）没有 headers 字段，
 *    请求头只能放在 `Request` 上；
 *  - `rcp.Request` 是 class，用 `new rcp.Request(url, method?, headers?, content?)` 构造；
 *  - `Response.body` 是 `ArrayBuffer | undefined`，取文本用 `Response.toString(): string | null`；
 *  - 统一用 `session.fetch(request)` 发送。
 *
 * 部分平台网页接口对 UA 有要求，故带桌面 Chrome UA，并声明 Referer 匹配网页端同源上下文。
 */

import { rcp } from '@kit.RemoteCommunicationKit';
import { AppError, FailKind } from '../model/Types';
import { Logger } from '../common/Logger';

const TAG: string = 'HttpClient';

/** 桌面 Chrome UA：平台网页接口按此识别为网页端会话 */
export const DESKTOP_UA: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

const MAX_ATTEMPT: number = 3;

/** getRaw 的返回：状态码 + 响应体文本（不抛异常，交调用方分型） */
export interface HttpResult {
  status: number;
  text: string;
}

export class HttpClient {
  private static session: rcp.Session | undefined = undefined;

  private static ensureSession(): rcp.Session {
    if (HttpClient.session === undefined) {
      // 只配置 transfer：Configuration 里没有 headers，别往里塞
      const transfer: rcp.TransferConfiguration = {
        autoRedirect: true,
        maxAutoRedirects: 10,
        timeout: { connectMs: 15000, transferMs: 30000 }
      };
      const requestConfiguration: rcp.Configuration = { transfer: transfer };
      const sessionConfiguration: rcp.SessionConfiguration = {
        requestConfiguration: requestConfiguration
      };
      HttpClient.session = rcp.createSession(sessionConfiguration);
    }
    return HttpClient.session;
  }

  /**
   * Response → 文本。`Response.toString()` 在响应体为空时返回的是字符串 `"null"`（不是 null），
   * 直接取会把 "null" 当成内容，所以先看 `body` 的长度。
   */
  private static readText(resp: rcp.Response): string {
    const bytes: ArrayBuffer | undefined = resp.body;
    if (bytes === undefined || bytes.byteLength === 0) {
      return '';
    }
    try {
      return resp.toString() ?? '';
    } catch (e) {
      Logger.w(TAG, 'Response.toString() 失败，按空响应处理');
      return '';
    }
  }

  /** 请求头构造（get / getRaw 共用） */
  private static headersOf(cookie: string, referer: string): rcp.RequestHeaders {
    const headers: rcp.RequestHeaders = {};
    headers['user-agent'] = DESKTOP_UA;
    headers['accept'] = 'application/json, text/plain, */*';
    headers['accept-language'] = 'zh-CN,zh;q=0.9';
    if (cookie.length > 0) {
      headers['cookie'] = cookie;
    }
    if (referer.length > 0) {
      headers['referer'] = referer;
    }
    return headers;
  }

  /**
   * 单次 GET，不判状态码、不重试：把状态码和响应体原样交回调用方。
   *
   * 有些站点的失败原因只写在响应体里（400/429、WAF 拦截页），只拿到一句 `HTTP 400`
   * 无法判断是哪一层出的问题。调用方自己按状态码分型，并把响应体片段写进日志。
   */
  static async getRaw(url: string, cookie: string = '',
    referer: string = ''): Promise<HttpResult> {
    const session: rcp.Session = HttpClient.ensureSession();
    const req: rcp.Request =
      new rcp.Request(url, 'GET', HttpClient.headersOf(cookie, referer));
    try {
      const resp: rcp.Response = await session.fetch(req);
      return { status: resp.statusCode, text: HttpClient.readText(resp) };
    } catch (e) {
      // 故意原样抛出：由调用方按"连不上 / 超时"统一分型（见 SteamProvider.asAppError）。
      // ArkTS 不允许 throw 任意类型（arkts-limited-throw），故统一收敛成 Error。
      throw e instanceof Error ? e : new Error(`${e}`);
    }
  }

  /** GET 请求；cookie 为空则不带头。失败抛 AppError */
  static async get(url: string, cookie: string = '', referer: string = ''): Promise<string> {
    const session: rcp.Session = HttpClient.ensureSession();
    const headers: rcp.RequestHeaders = HttpClient.headersOf(cookie, referer);

    let lastErr: AppError = new AppError(FailKind.NETWORK, '未知网络错误');
    for (let attempt = 1; attempt <= MAX_ATTEMPT; attempt++) {
      try {
        const req: rcp.Request = new rcp.Request(url, 'GET', headers);
        const resp: rcp.Response = await session.fetch(req);
        const status: number = resp.statusCode;

        if (status >= 200 && status < 300) {
          return HttpClient.readText(resp);
        }
        if (status >= 500 || status === 429) {
          lastErr = new AppError(
            status === 429 ? FailKind.HTTP_4XX : FailKind.HTTP_5XX, `HTTP ${status}`);
        } else {
          // 4xx：不重试，直接抛
          throw new AppError(status === 401 || status === 403
            ? FailKind.NEED_LOGIN : FailKind.HTTP_4XX, `HTTP ${status}`);
        }
      } catch (e) {
        if (e instanceof AppError) {
          if (e.kind === FailKind.HTTP_4XX || e.kind === FailKind.NEED_LOGIN) {
            throw e;
          }
          lastErr = e;
        } else if (e instanceof Error) {
          const msg: string = e.message.toLowerCase();
          lastErr = new AppError(
            msg.indexOf('timeout') >= 0 ? FailKind.TIMEOUT : FailKind.NETWORK, e.message);
        } else {
          lastErr = new AppError(FailKind.NETWORK, `${e}`);
        }
      }
      if (attempt < MAX_ATTEMPT) {
        const backoff: number = 300 * Math.pow(2, attempt - 1);
        Logger.w(TAG, `第 ${attempt} 次失败(${lastErr.kind})，${backoff}ms 后重试`);
        await HttpClient.sleep(backoff);
      }
    }
    throw lastErr;
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  static reset(): void {
    HttpClient.session?.close();
    HttpClient.session = undefined;
  }
}
