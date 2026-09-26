/**
 * 网页上下文取数通道（ArkWeb 桥）。
 *
 * 平台接口带签名、设备指纹等网页端专属校验、原生直连拿不到数据时，把请求交给一个隐藏的
 * ArkWeb 容器，用页面同源上下文发起 XHR，等价于在该网页里打开一次接口。
 * 机制：注入 XHR 脚本 → 页面内执行 → 通过 javaScriptProxy 回调 native 回传结果。
 */

import { webview } from '@kit.ArkWeb';
import { AppStorageV2 } from '@kit.ArkUI';
import { AppError, FailKind, Platform } from '../model/Types';
import { WebSessionBridge } from './WebSessionBridge';
import { Logger } from '../common/Logger';

const TAG: string = 'WebBridge';
const BRIDGE_TIMEOUT_MS: number = 20000;

/** 容器状态（由 components/WebBridgeHost.ets 消费） */
@ObservedV2
export class WebBridgeState {
  /**
   * 是否挂载隐藏容器。默认 false，冷启动不创建 Web 组件：省掉 WebView 初始化开销，
   * 也避免 ArkWeb 不可用的设备在首帧把整棵 UI 树带崩。只有真正走 bridge 通道取数时才置 true。
   */
  @Trace enabled: boolean = false;
  /** 隐藏容器当前加载的地址 */
  @Trace src: string = 'about:blank';
  @Trace pageReady: boolean = false;
}

/** 绝不返回 undefined（解引用会抛异常） */
export function connectWebBridgeState(): WebBridgeState {
  try {
    const s: WebBridgeState | undefined =
      AppStorageV2.connect(WebBridgeState, 'v2_webBridge', () => new WebBridgeState());
    if (s !== undefined) {
      return s;
    }
  } catch (e) {
    Logger.w(TAG, 'AppStorageV2 不可用，退回本地实例');
  }
  return new WebBridgeState();
}

/** 注入到页面的代理对象（必须是只有方法的类，且方法名与 methodList 一致） */
export class WebBridgeProxy {
  onResult(id: string, payload: string): void {
    // payload = "<status>|<origin>|<responseText>"；分开传多个参数会动 methodList 契约，
    // 编码进一个串更稳。origin 用于区分"CORS/页面 origin 不对"与"连接被重置"。
    const p1: number = payload.indexOf('|');
    const p2: number = p1 < 0 ? -1 : payload.indexOf('|', p1 + 1);
    if (p1 < 0 || p2 < 0) {
      WebBridge.resolve(id, 0, payload, '');
      return;
    }
    const status: number = Number.parseInt(payload.substring(0, p1), 10);
    const origin: string = payload.substring(p1 + 1, p2);
    const text: string = payload.substring(p2 + 1);
    Logger.i(TAG, `页面回传 origin=${origin} status=${status} bytes=${text.length}`);
    WebBridge.resolve(id, Number.isNaN(status) ? 0 : status, text, origin);
  }

  onError(id: string, msg: string): void {
    WebBridge.reject(id, new AppError(FailKind.NETWORK, msg));
  }
}

/**
 * 额外请求头。值支持三种占位符：
 *  - `@ls:<key>`         从页面 localStorage 取值，取不到就轮询等待（必需）
 *  - `@cookie:<name>`    从 document.cookie 取值，取不到就轮询等待（必需）
 *  - `@optcookie:<name>` 同上，取不到就跳过这个头（可选，例如未登录时的 Authorization）
 *
 * 有的网关按自定义头放行：缺这组头时浏览器内核表现为 XHR readyState=4 + status=0 + 空 body，
 * 带上才返回 200。这类头由各平台的 Provider 自己提供，桥只负责透传。
 *
 * 占位符用来取"运行时才存在"的值：设备标识由平台前端依据浏览器指纹签发后写进 localStorage；
 * 登录令牌放在 JS 可读的 Cookie 里，由前端读出后写进 Authorization 头（接口 CORS 是
 * `Allow-Origin: *`，开 withCredentials 反而会被浏览器拦掉）。这里不复刻平台那套指纹与加密，
 * 只加载平台自己的页面让它完成注册和登录，再读它签发的值。
 */
export interface BridgeHeader {
  name: string;
  value: string;
}

/**
 * 桥接结果。必须带 status：XHR 在 CORS 被拦、被 abort、被网关拦截时，readyState 同样是 4、
 * responseText 同样是空串，只看 body 会误判成"响应为空"。status===0 表示请求根本没拿到响应。
 */
export class BridgeResult {
  status: number;
  text: string;
  /** 发起请求时页面所处的 origin（排查 CORS/origin 问题用） */
  origin: string;

  constructor(status: number, text: string, origin: string = '') {
    this.status = status;
    this.text = text;
    this.origin = origin;
  }
}

class Pending {
  resolve: (r: BridgeResult) => void;
  reject: (err: AppError) => void;

  constructor(resolve: (r: BridgeResult) => void, reject: (err: AppError) => void) {
    this.resolve = resolve;
    this.reject = reject;
  }
}

export class WebBridge {
  private static controllerHolder: webview.WebviewController | undefined = undefined;
  private static proxyHolder: WebBridgeProxy | undefined = undefined;
  private static pending: Map<string, Pending> = new Map();
  private static seq: number = 0;
  private static currentUrl: string = '';
  private static loadingUrl: string = '';
  private static waiters: Array<() => void> = [];

  static controller(): webview.WebviewController {
    if (WebBridge.controllerHolder === undefined) {
      WebBridge.controllerHolder = new webview.WebviewController();
    }
    return WebBridge.controllerHolder;
  }

  static proxy(): WebBridgeProxy {
    if (WebBridge.proxyHolder === undefined) {
      WebBridge.proxyHolder = new WebBridgeProxy();
    }
    return WebBridge.proxyHolder;
  }

  /** WebBridgeHost 的 onPageEnd 回调 */
  static markPageEnd(url: string): void {
    Logger.i(TAG, `隐藏容器 onPageEnd: ${url}`);
    WebBridge.currentUrl = url;
    WebBridge.pageLoaded = true;
    if (WebBridge.loadingUrl.length > 0) {
      WebBridge.loadingUrl = '';
    }
    connectWebBridgeState().pageReady = true;
    const ws: Array<() => void> = WebBridge.waiters;
    WebBridge.waiters = [];
    ws.forEach((w: () => void) => w());
  }

  static resolve(id: string, status: number, text: string, origin: string): void {
    const p: Pending | undefined = WebBridge.pending.get(id);
    if (p) {
      WebBridge.pending.delete(id);
      p.resolve(new BridgeResult(status, text, origin));
    }
  }

  static reject(id: string, err: AppError): void {
    const p: Pending | undefined = WebBridge.pending.get(id);
    if (p) {
      WebBridge.pending.delete(id);
      p.reject(err);
    }
  }

  /**
   * 在页面上下文里请求接口（path 可以是相对路径或绝对 URL；绝对 URL 会按跨域发出）。
   * @param platform 目标平台（决定加载哪个站点，从而决定页面 origin 与 Cookie）
   * @param path 相对路径或绝对 URL
   * @param method GET | POST
   * @param jsonBody POST 的 JSON 文本；GET 传空串
   */
  static async run(platform: Platform, path: string, method: string,
    jsonBody: string, headers: BridgeHeader[] = []): Promise<BridgeResult> {
    return WebBridge.runAt(`${WebSessionBridge.cookieUrlOf(platform)}/`,
      path, method, jsonBody, headers);
  }

  /**
   * 同 run，但直接指定页面 origin 落在哪个站点，不限于 BUFF / 悠悠有品。
   *
   * 第三方站点对原生 HTTP 客户端的请求形状可能不友好：rcp 直连 `steamcommunity.com` 拿到
   * HTTP 400 + 空响应体，而浏览器引擎正常，这类情况用本方法。
   *
   * @param home 页面 origin（如 `https://steamcommunity.com/`），决定同源上下文与 Cookie
   */
  static async runAt(home: string, path: string, method: string,
    jsonBody: string, headers: BridgeHeader[] = []): Promise<BridgeResult> {
    await WebBridge.ensurePageAt(home);
    WebBridge.seq++;
    const id: string = `req_${WebBridge.seq}_${Date.now()}`;
    const script: string = WebBridge.buildScript(id, path, method, jsonBody, headers);

    return new Promise<BridgeResult>((resolve: (r: BridgeResult) => void,
      reject: (e: AppError) => void) => {
      WebBridge.pending.set(id, new Pending(resolve, reject));
      WebBridge.controller().runJavaScript(script, (err: Object) => {
        if (err) {
          WebBridge.reject(id, new AppError(FailKind.NETWORK, '注入脚本执行失败'));
        }
      });
      setTimeout(() => {
        WebBridge.reject(id, new AppError(FailKind.TIMEOUT, '网页桥接超时'));
      }, BRIDGE_TIMEOUT_MS);
    });
  }

  /** 确保隐藏容器已加载对应站点首页（首次调用才真正加载，避免拖慢冷启动） */
  private static async ensurePageAt(home: string): Promise<void> {
    if (WebBridge.currentUrl === home) {
      return;
    }
    const st: WebBridgeState = connectWebBridgeState();
    if (WebBridge.loadingUrl !== home) {
      WebBridge.loadingUrl = home;
      st.pageReady = false;
      st.src = home;
      // 先置地址再挂载容器，保证 Web 首次创建时就带正确的 src
      st.enabled = true;
      Logger.i(TAG, `隐藏容器开始加载 ${home}`);
    }
    await new Promise<void>((resolve: () => void) => {
      WebBridge.waiters.push(resolve);
      // 超时兜底：页面迟迟不 onPageEnd 也要放行，让 xhr 自己去失败
      setTimeout(() => {
        resolve();
      }, BRIDGE_TIMEOUT_MS);
    });
  }

  private static buildScript(id: string, path: string, method: string,
    jsonBody: string, headers: BridgeHeader[]): string {
    const payload: string = jsonBody.length > 0 ? JSON.stringify(jsonBody) : 'null';
    const hs: string = JSON.stringify(headers);
    // 1) 先把带 @ls: 的头从 localStorage 里解析出来（服务端签发的身份标识要等前端写完）；
    // 2) 再把 x.status 与 location.origin 一起回传 —— CORS 被拦/被 abort 时
    //    readyState 同样是 4、body 同样为空，只看 body 会误判成"响应为空"。
    return `(function(){`
      + `var id=${JSON.stringify(id)},method=${JSON.stringify(method)},url=${JSON.stringify(path)},body=${payload};`
      + `var done=false;function fin(s,t){if(done){return;}done=true;try{window.skinBridge.onResult(id,s+'|'+location.origin+'|'+t);}catch(e){}}`
      + `var hs=${hs};`
      + `function ls(k){try{return window.localStorage.getItem(k)||'';}catch(e){return '';}}`
      + `function ck(n){try{var ps=document.cookie?document.cookie.split('; '):[];for(var q=0;q<ps.length;q++){var ix=ps[q].indexOf('=');if(ix>0&&ps[q].substring(0,ix)===n){return decodeURIComponent(ps[q].substring(ix+1));}}}catch(e){}return '';}`
      + `function attempt(){`
      + `var out=[],miss='',i,v,k,got;`
      + `for(i=0;i<hs.length;i++){v=hs[i].value;`
      + `if(v.indexOf('@ls:')===0){k=v.substring(4);got=ls(k);if(!got){miss=k;break;}out.push({name:hs[i].name,value:got});}`
      + `else if(v.indexOf('@optcookie:')===0){got=ck(v.substring(11));if(got){out.push({name:hs[i].name,value:got});}}`
      + `else if(v.indexOf('@cookie:')===0){k=v.substring(8);got=ck(k);if(!got){miss=k;break;}out.push({name:hs[i].name,value:got});}`
      + `else{out.push({name:hs[i].name,value:v});}}`
      + `if(miss){attempt.n=(attempt.n||0)+1;if(attempt.n>20){`
      + `var ks=[];try{for(var q=0;q<window.localStorage.length;q++){ks.push(window.localStorage.key(q));}}catch(e3){}`
      + `fin(0,'missing-localStorage:'+miss+'|have='+ks.join(',').substring(0,300)+'|ready='+document.readyState);return;}`
      + `setTimeout(attempt,400);return;}`
      + `send(out);}`
      + `function send(res){try{`
      + `var x=new XMLHttpRequest();x.open(method,url,true);`
      // 不要开 withCredentials：平台接口的 CORS 是 `Access-Control-Allow-Origin: *`，
      // 带凭据会在预检阶段被拦掉（匿名请求也会变成 status=0）。
      // 登录态由调用方通过 `Authorization` 头带（见 UuProvider.headers）。
      + `x.setRequestHeader('Content-Type','application/json;charset=UTF-8');`
      + `x.setRequestHeader('Accept','application/json, text/plain, */*');`
      + `for(var i=0;i<res.length;i++){try{x.setRequestHeader(res[i].name,res[i].value);}catch(e2){}}`
      + `x.timeout=15000;`
      + `x.onreadystatechange=function(){if(x.readyState===4){fin(x.status,x.responseText||'');}};`
      + `x.onerror=function(){fin(0,'network-or-cors-blocked');};`
      + `x.onabort=function(){fin(0,'aborted');};`
      + `x.ontimeout=function(){fin(0,'xhr-timeout');};`
      + `x.send(body);`
      + `}catch(e){fin(-1,String(e));}}`
      + `attempt();})();`;
  }

  /** 释放待处理请求（页面销毁时调用） */
  static reset(): void {
    WebBridge.pending.forEach((p: Pending) => {
      p.reject(new AppError(FailKind.UNAVAILABLE, '页面桥接已重置'));
    });
    WebBridge.pending.clear();
    WebBridge.waiters = [];
    WebBridge.currentUrl = '';
    WebBridge.loadingUrl = '';
    WebBridge.lastHttpStatus = 0;
  }

  // -------------------------------------------------------------------------
  // 导航式取数
  // -------------------------------------------------------------------------

  private static lastHttpStatus: number = 0;
  /** 本次导航是否真的 onPageEnd 过（用来区分"新页面"与"上一页残留"） */
  private static pageLoaded: boolean = false;

  /** WebBridgeHost 的 onHttpErrorReceive 回调：记下这次导航的真实状态码 */
  static markHttpStatus(url: string, code: number): void {
    Logger.w(TAG, `导航收到 HTTP ${code}：${url}`);
    WebBridge.lastHttpStatus = code;
  }

  private static waitPageEnd(timeoutMs: number = BRIDGE_TIMEOUT_MS): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      WebBridge.waiters.push(resolve);
      // 超时兜底：页面迟迟不 onPageEnd 也要放行，让正文侧自己去失败
      setTimeout(() => {
        resolve();
      }, timeoutMs);
    });
  }

  /**
   * 用页面导航的方式取一个地址的文本，等价于在浏览器地址栏打开这个 URL。
   *
   * 站点对原生客户端不友好、而浏览器能打开时用它兜底。导航本身拿不到状态码，需由宿主组件的
   * `onHttpErrorReceive` 回传（见 markHttpStatus）。注意本通道对 `steamcommunity.com` 的
   * 库存接口返回 400（换成浏览器同款 UA 也无效），那类接口走原生 rcp。
   */
  static async navigateTo(url: string): Promise<BridgeResult> {
    return await WebBridge.doNavigate(url);
  }

  /** 真正的一次导航：置地址 → 等 onPageEnd → 读正文 */
  private static async doNavigate(url: string): Promise<BridgeResult> {
    WebBridge.lastHttpStatus = 0;
    WebBridge.pageLoaded = false;
    const st: WebBridgeState = connectWebBridgeState();
    if (!st.enabled) {
      // 首次：容器还不存在，用 src 决定首次加载地址（先置地址再挂载）
      st.src = url;
      st.enabled = true;
      Logger.i(TAG, `隐藏容器挂载并加载 ${url}`);
    } else {
      /*
       * 已在运行时必须走 `loadUrl`，不能再改 `src`：同一个 URL 再赋一次相同值，Web 组件认为
       * 没变化而不会重新加载，表现是 onPageEnd 永不触发（只能等到超时），读回来还是上一页的内容。
       */
      Logger.i(TAG, `隐藏容器导航 ${url}`);
      try {
        WebBridge.controller().loadUrl(url);
      } catch (e) {
        st.src = url;
      }
    }
    await WebBridge.waitPageEnd();

    // 每次导航记一行上下文（UA + cookie 长度）：站点认不认这个会话基本就看这两项
    try {
      const diag: string = await WebBridge.controller().runJavaScript(
        `navigator.userAgent+' | cookieLen='+document.cookie.length`);
      Logger.i(TAG, `导航上下文：${diag}`);
    } catch (e) {
      Logger.w(TAG, '读取导航上下文失败');
    }

    let text: string = '';
    try {
      text = await WebBridge.controller().runJavaScript(
        '(function(){var b=document.body;if(!b){return "";}return b.innerText||b.textContent||"";})()');
    } catch (e) {
      Logger.w(TAG, '读取页面正文失败');
    }
    /*
     * 状态码优先级：onHttpErrorReceive 报的真实码 > onPageEnd 且正文非空 = 200 > 0（没拿到）。
     * 不能只看"正文非空"就判 200：上一页残留的正文会被当成本次结果。
     */
    let status: number = 0;
    if (WebBridge.lastHttpStatus > 0) {
      status = WebBridge.lastHttpStatus;
    } else if (WebBridge.pageLoaded && text.length > 0) {
      status = 200;
    }
    Logger.i(TAG, `导航结果 status=${status} loaded=${WebBridge.pageLoaded} bytes=${text.length}`);
    return new BridgeResult(status, text, url);
  }
}
