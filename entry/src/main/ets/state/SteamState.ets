/**
 * SteamState.ets — Steam 账号配置（状态管理 V2 单例，一域一文件）
 *
 * 只存"我是谁"这类需要跨启动保留的配置，**不存库存本体**：
 * 库存是每次刷新都要重新拉的实时数据，落盘只会变旧造成误导。
 */

import { AppStorageV2 } from '@kit.ArkUI';
import { PreferencesStore } from '../data/PreferencesStore';
import { Logger } from '../common/Logger';

const TAG: string = 'SteamState';
const KEY: string = 'v2_steam';
const K_ID: string = 'steam_id64';
const K_INPUT: string = 'steam_input';
const K_API_KEY: string = 'steam_api_key';

@ObservedV2
export class SteamState {
  /** 已解析出来的 SteamID64（17 位） */
  @Trace steamId: string = '';
  /** 用户原始输入：17 位 ID / 自定义 ID / 个人资料链接 */
  @Trace input: string = '';
  /** 官方 Web API Key（可选，仅 webApi 用；公开库存接口不需要它） */
  @Trace apiKey: string = '';

  load(): void {
    this.steamId = PreferencesStore.getString(K_ID, '');
    this.input = PreferencesStore.getString(K_INPUT, '');
    this.apiKey = PreferencesStore.getString(K_API_KEY, '');
    Logger.i(TAG, `Steam 配置装载：id=${this.steamId.length > 0 ? this.steamId : '未设置'}`);
  }

  /** 解析成功后保存 */
  save(steamId: string, input: string): void {
    this.steamId = steamId;
    this.input = input;
    PreferencesStore.put(K_ID, steamId);
    PreferencesStore.put(K_INPUT, input);
  }

  setApiKey(k: string): void {
    this.apiKey = k;
    PreferencesStore.put(K_API_KEY, k);
  }

  clear(): void {
    this.steamId = '';
    this.input = '';
    PreferencesStore.put(K_ID, '');
    PreferencesStore.put(K_INPUT, '');
  }
}

/** 绝不返回 undefined：组件 build 里解引用 undefined 会整页白屏 */
export function connectSteam(): SteamState {
  try {
    const s: SteamState | undefined =
      AppStorageV2.connect(SteamState, KEY, () => new SteamState());
    if (s !== undefined) {
      return s;
    }
  } catch (e) {
    Logger.w(TAG, 'AppStorageV2 不可用，退回本地实例');
  }
  return new SteamState();
}

/** 启动期装载（loadContent 之前调用） */
export function bootstrapSteam(): void {
  try {
    connectSteam().load();
  } catch (e) {
    Logger.w(TAG, 'Steam 配置装载延迟到页面侧');
  }
}
