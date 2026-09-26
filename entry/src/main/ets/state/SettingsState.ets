/**
 * SettingsState.ets — 设置域状态（状态管理 V2，一域一文件）。
 * 三层数据：Preferences（盘）→ @ObservedV2 状态类（内存）→ @Local（UI）。
 * 全局量由 EntryAbility 单点写入，组件只读。
 */

import { AppStorageV2 } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { PreferencesStore } from '../data/PreferencesStore';
import { MaterialGate, MaterialLevelKey } from '../common/MaterialGate';
import { FetchChannel } from '../model/Types';
import { Logger } from '../common/Logger';

const TAG: string = 'SettingsState';
const KEY: string = 'v2_settings';

const K_COLOR_MODE: string = 'color_mode';
const K_MATERIAL_LEVEL: string = 'material_level';
const K_UI_EFFECTS: string = 'ui_effects_on';
const K_CHANNEL: string = 'fetch_channel';

@ObservedV2
export class SettingsState {
  /** ConfigurationConstant.ColorMode：-1 跟随系统 / 0 浅色 / 1 深色 */
  @Trace colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  @Trace materialLevel: MaterialLevelKey = 'adaptive';
  /** 是否开启玻璃/材质效果（关掉可省电，低端机友好） */
  @Trace uiEffectsOn: boolean = true;
  @Trace fetchChannel: FetchChannel = FetchChannel.DIRECT;
  /** 最近一次全局刷新时间戳 */
  @Trace lastRefreshTs: number = 0;

  /** 从盘上装载（EntryAbility 中先于 loadContent 调用） */
  load(): void {
    this.colorMode = PreferencesStore.getNumber(
      K_COLOR_MODE, ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    const lv: string = PreferencesStore.getString(K_MATERIAL_LEVEL, 'adaptive');
    this.materialLevel = SettingsState.parseLevel(lv);
    this.uiEffectsOn = PreferencesStore.getBoolean(K_UI_EFFECTS, true);
    const ch: string = PreferencesStore.getString(K_CHANNEL, FetchChannel.DIRECT);
    this.fetchChannel = ch === FetchChannel.BRIDGE ? FetchChannel.BRIDGE : FetchChannel.DIRECT;
    MaterialGate.levelKey = this.materialLevel;
    Logger.i(TAG, `设置已装载：mode=${this.colorMode} level=${this.materialLevel} ch=${this.fetchChannel}`);
  }

  private static parseLevel(s: string): MaterialLevelKey {
    if (s === 'exquisite' || s === 'gentle' || s === 'smooth') {
      return s;
    }
    return 'adaptive';
  }

  setColorMode(mode: number, ctx: common.Context): void {
    this.colorMode = mode;
    PreferencesStore.put(K_COLOR_MODE, mode);
    try {
      ctx.getApplicationContext().setColorMode(mode);
    } catch (e) {
      Logger.err(TAG, 'setColorMode', e);
    }
  }

  setMaterialLevel(lv: MaterialLevelKey): void {
    this.materialLevel = lv;
    MaterialGate.levelKey = lv;
    PreferencesStore.put(K_MATERIAL_LEVEL, lv);
  }

  setUiEffects(on: boolean): void {
    this.uiEffectsOn = on;
    PreferencesStore.put(K_UI_EFFECTS, on);
  }

  setFetchChannel(ch: FetchChannel): void {
    this.fetchChannel = ch;
    PreferencesStore.put(K_CHANNEL, ch);
  }

  markRefreshed(): void {
    this.lastRefreshTs = Date.now();
  }
}

/** 绝不返回 undefined：否则组件 build 里解引用会抛异常导致整页白屏 */
export function connectSettings(): SettingsState {
  try {
    const s: SettingsState | undefined =
      AppStorageV2.connect(SettingsState, KEY, () => new SettingsState());
    if (s !== undefined) {
      return s;
    }
  } catch (e) {
    Logger.w(TAG, 'AppStorageV2 不可用，退回本地实例');
  }
  return new SettingsState();
}

/**
 * 启动期装载。
 * 必须在 loadContent 之前调用，
 * 否则首帧会用到默认值再闪一次。
 * Ability 上下文里 AppStorageV2 不可用时静默降级（页面侧 connectSettings 会兜底重载）。
 */
export function bootstrapSettings(): SettingsState | undefined {
  try {
    const s: SettingsState = connectSettings();
    s.load();
    return s;
  } catch (e) {
    Logger.w(TAG, 'AppStorageV2 在启动期不可用，改由页面侧首次装载');
    return undefined;
  }
}
