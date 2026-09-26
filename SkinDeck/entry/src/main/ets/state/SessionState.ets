/**
 * SessionState.ets — 会话/账号域状态
 *
 * 关于"多账号"的实现边界（务必如实告知用户，不做超出能力的承诺）：
 *   ArkWeb 的 Cookie 存储是**按应用 + 域名**共享的，没有官方的"多容器隔离"能力。
 *   因此本应用的账号条目记录的是"这个平台我用哪个账号登录着"的档案，
 *   **切换账号 = 清掉该平台会话 Cookie 后重新在官方网页登录**，而不是并行多开。
 *   这样既不触碰平台的风控，也不需要在本地保存任何凭据。
 */

import { AppStorageV2 } from '@kit.ArkUI';
import { AccountInfo, Platform, PlatformMeta } from '../model/Types';
import { PreferencesStore } from '../data/PreferencesStore';
import { WebSessionBridge } from '../data/WebSessionBridge';
import { Logger } from '../common/Logger';

const TAG: string = 'SessionState';
const KEY: string = 'v2_session';
const K_ACCOUNTS: string = 'accounts';

@ObservedV2
export class SessionState {
  @Trace accounts: AccountInfo[] = [];

  load(): void {
    const stored: AccountInfo[] | undefined =
      PreferencesStore.getJson<AccountInfo[]>(K_ACCOUNTS);
    this.accounts = stored ?? [];
    this.refreshLoginState();
  }

  private persist(): void {
    PreferencesStore.putJson(K_ACCOUNTS, this.accounts);
  }

  /** 探测两个平台的登录态（只读 Cookie，不做任何登录动作） */
  refreshLoginState(): void {
    const next: AccountInfo[] = [];
    let changed: boolean = false;
    for (let i = 0; i < this.accounts.length; i++) {
      const a: AccountInfo = this.accounts[i];
      const ok: boolean = WebSessionBridge.isLoggedIn(a.platform);
      const ts: number = ok ? Date.now() : a.lastCheckTs;
      const updated: AccountInfo = {
        id: a.id,
        platform: a.platform,
        alias: a.alias,
        lastCheckTs: ts,
        loggedIn: ok
      };
      if (updated.loggedIn !== a.loggedIn || updated.lastCheckTs !== a.lastCheckTs) {
        changed = true;
      }
      next.push(updated);
    }
    if (changed || next.length !== this.accounts.length) {
      this.accounts = next;
      this.persist();
    }
  }

  /** 记录/更新某个平台的账号档案 */
  upsertAccount(platform: Platform, alias: string): void {
    const loggedIn: boolean = WebSessionBridge.isLoggedIn(platform);
    const next: AccountInfo[] = [];
    let found: boolean = false;
    for (let i = 0; i < this.accounts.length; i++) {
      const a: AccountInfo = this.accounts[i];
      if (a.platform === platform) {
        found = true;
        const updated: AccountInfo = {
          id: a.id, platform: platform, alias: alias,
          lastCheckTs: loggedIn ? Date.now() : a.lastCheckTs,
          loggedIn: loggedIn
        };
        next.push(updated);
      } else {
        next.push(a);
      }
    }
    if (!found) {
      const created: AccountInfo = {
        id: `${platform}_${Date.now()}`,
        platform: platform,
        alias: alias.length > 0 ? alias : PlatformMeta.shortLabel(platform),
        lastCheckTs: loggedIn ? Date.now() : 0,
        loggedIn: loggedIn
      };
      next.push(created);
    }
    this.accounts = next;
    this.persist();
    Logger.i(TAG, `${PlatformMeta.label(platform)} 账号档案已更新，登录态=${loggedIn}`);
  }

  removeAccount(id: string): void {
    const next: AccountInfo[] = [];
    for (let i = 0; i < this.accounts.length; i++) {
      if (this.accounts[i].id !== id) {
        next.push(this.accounts[i]);
      }
    }
    this.accounts = next;
    this.persist();
  }

  /** 退出：清该平台 WebView 会话（两个平台共享 Cookie 存储，故整体清理） */
  logout(): void {
    WebSessionBridge.clearSession();
    this.refreshLoginState();
  }

  accountOf(platform: Platform): AccountInfo | undefined {
    for (let i = 0; i < this.accounts.length; i++) {
      if (this.accounts[i].platform === platform) {
        return this.accounts[i];
      }
    }
    return undefined;
  }

  static loggedInCount(list: AccountInfo[]): number {
    let n: number = 0;
    for (let i = 0; i < list.length; i++) {
      if (list[i].loggedIn) {
        n++;
      }
    }
    return n;
  }
}

/** 绝不返回 undefined：否则组件 build 里解引用会抛异常导致整页白屏 */
export function connectSession(): SessionState {
  try {
    const s: SessionState | undefined =
      AppStorageV2.connect(SessionState, KEY, () => new SessionState());
    if (s !== undefined) {
      return s;
    }
  } catch (e) {
    Logger.w(TAG, 'AppStorageV2 不可用，退回本地实例');
  }
  return new SessionState();
}

/** 启动期装载（loadContent 之前调用） */
export function bootstrapSession(): void {
  try {
    connectSession().load();
  } catch (e) {
    Logger.w(TAG, '账号档案装载延迟到页面侧');
  }
}
