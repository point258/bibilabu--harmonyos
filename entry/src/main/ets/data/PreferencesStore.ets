/**
 * PreferencesStore.ets — 键值持久化底座
 * 生产模式：
 *   - 单例 + ready 防并发 init 竞态；
 *   - getStringSync 读不到返回 undefined，以区分"盘上就是空"与"没读到"；
 *   - 写后 flush（异步），避免掉电丢设置。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '../common/Logger';

const TAG: string = 'PreferencesStore';
const STORE_NAME: string = 'skindeck_settings';

export class PreferencesStore {
  private static ctx: common.Context | undefined = undefined;
  private static store: preferences.Preferences | undefined = undefined;

  /** EntryAbility.onCreate 里调用一次 */
  static init(ctx: common.Context): void {
    PreferencesStore.ctx = ctx;
    try {
      PreferencesStore.store = preferences.getPreferencesSync(ctx, { name: STORE_NAME });
      Logger.i(TAG, 'preferences ready');
    } catch (e) {
      Logger.err(TAG, 'getPreferencesSync', e);
      PreferencesStore.store = undefined;
    }
  }

  private static ensure(): preferences.Preferences | undefined {
    if (PreferencesStore.store === undefined && PreferencesStore.ctx !== undefined) {
      PreferencesStore.init(PreferencesStore.ctx);
    }
    return PreferencesStore.store;
  }

  static getString(key: string, def: string): string {
    const s: preferences.Preferences | undefined = PreferencesStore.ensure();
    if (!s) {
      return def;
    }
    try {
      const v: preferences.ValueType = s.getSync(key, def);
      return typeof v === 'string' ? v : def;
    } catch (e) {
      return def;
    }
  }

  static getNumber(key: string, def: number): number {
    const s: preferences.Preferences | undefined = PreferencesStore.ensure();
    if (!s) {
      return def;
    }
    try {
      const v: preferences.ValueType = s.getSync(key, def);
      return typeof v === 'number' ? v : def;
    } catch (e) {
      return def;
    }
  }

  static getBoolean(key: string, def: boolean): boolean {
    const s: preferences.Preferences | undefined = PreferencesStore.ensure();
    if (!s) {
      return def;
    }
    try {
      const v: preferences.ValueType = s.getSync(key, def);
      return typeof v === 'boolean' ? v : def;
    } catch (e) {
      return def;
    }
  }

  static put(key: string, value: preferences.ValueType): void {
    const s: preferences.Preferences | undefined = PreferencesStore.ensure();
    if (!s) {
      return;
    }
    try {
      s.putSync(key, value);
      s.flush((err: Object) => {
        if (err) {
          Logger.err(TAG, `flush ${key}`, err);
        }
      });
    } catch (e) {
      Logger.err(TAG, `put ${key}`, e);
    }
  }

  /** 数组/对象类数据统一以 JSON 字符串落盘 */
  static getJson<T>(key: string): T | undefined {
    const raw: string = PreferencesStore.getString(key, '');
    if (raw.length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(raw) as T;
    } catch (e) {
      Logger.w(TAG, `JSON.parse ${key} 失败，按空处理`);
      return undefined;
    }
  }

  static putJson(key: string, value: Object): void {
    try {
      PreferencesStore.put(key, JSON.stringify(value));
    } catch (e) {
      Logger.err(TAG, `stringify ${key}`, e);
    }
  }
}
