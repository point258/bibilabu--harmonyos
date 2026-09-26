/**
 * WebSessionBridge.ets — 复用 ArkWeb 会话（Cookie）
 *
 * 设计原则（合规相关，务必保持）：
 *   本应用不实现登录、不代填账号、不绕过任何平台风控。用户始终在平台官方网页内完成
 *   登录（含易盾验证码）。此处只做一件事：把用户自己在 WebView 里建立的会话 Cookie
 *   读出来，用于调用同一平台网页端本就公开的数据接口，读到的也只是用户自己可见的数据。
 *
 * API 依据：webview.WebCookieManager.fetchCookieSync / configCookie / clearAllCookiesSync
 */

import { webview } from '@kit.ArkWeb';
import { Platform } from '../model/Types';
import { Logger } from '../common/Logger';

const TAG: string = 'WebSessionBridge';

export class WebSessionBridge {
  /** 读取指定平台域下的 Cookie 串；失败返回空串 */
  static cookieOf(platform: Platform): string {
    try {
      const url: string = WebSessionBridge.cookieUrlOf(platform);
      const ck: string = webview.WebCookieManager.fetchCookieSync(url);
      return ck ?? '';
    } catch (e) {
      Logger.w(TAG, `读取 ${platform} Cookie 失败（可能尚未在网页端登录）`);
      return '';
    }
  }

  /**
   * 登录态启发式判断：
   *   BUFF  → 存在非空 session 键
   *   悠悠有品 → 存在 token / Authorization 相关键
   * 仅用于 UI 提示，不作为鉴权依据。
   */
  static isLoggedIn(platform: Platform): boolean {
    const ck: string = WebSessionBridge.cookieOf(platform);
    if (ck.length === 0) {
      return false;
    }
    if (platform === Platform.BUFF) {
      return /(^|;\s*)session=([^;]+)/.test(ck) && !/session=\s*(;|$)/.test(ck);
    }
    return /(^|;\s*)(token|Authorization|uu_token)=([^;]+)/i.test(ck);
  }

  /** 退出登录：清掉 WebView 侧会话（session cookie） */
  static clearSession(): void {
    try {
      // 注意 API 名是单数 Cookie：clearSessionCookieSync
      webview.WebCookieManager.clearSessionCookieSync();
      Logger.i(TAG, '已清除 WebView 会话 Cookie');
    } catch (e) {
      Logger.err(TAG, 'clearSessionCookieSync', e);
    }
  }

  /** 彻底清空（含持久 Cookie），用于"清理数据" */
  static clearAll(): void {
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch (e) {
      Logger.err(TAG, 'clearAllCookiesSync', e);
    }
  }

  static cookieUrlOf(platform: Platform): string {
    return platform === Platform.BUFF
      ? 'https://buff.163.com'
      : 'https://www.youpin898.com';
  }
}
