/**
 * 沉浸光感统一门禁：能力探测、档位、材质实例工厂与降级。
 *
 * 铁律：
 *   1) Hds 前缀组件配 hdsMaterial（@kit.UIDesignKit），普通组件配 uiMaterial（@kit.ArkUI）。
 *      两套枚举不可互换，互换后编译通过但无效果。
 *   2) uiMaterial 命名空间在 API 23~25 上不存在，版本判断必须直接包围构造。
 *
 * 材质实例全局缓存复用（滚动中反复构造会持续重建材质）；另外提供系统档位查询，
 * 供调用方在系统关闭光感或降级时兜底到毛玻璃/纯色。
 */

import { uiMaterial } from '@kit.ArkUI';
import { hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Logger } from './Logger';

const TAG: string = 'MaterialGate';
const HDS_SYSCAP: string = 'SystemCapability.UIDesign.HDSComponent.Core';

export type MaterialLevelKey = 'adaptive' | 'exquisite' | 'gentle' | 'smooth';

export class MaterialGate {
  private static cachedSupported: boolean | undefined = undefined;
  private static cachedUiMaterialOk: boolean | undefined = undefined;
  /** 用户档位偏好，由设置页写入（默认系统自适应） */
  static levelKey: MaterialLevelKey = 'adaptive';
  /** 材质实例缓存：key = style 名，避免滚动中反复构造 */
  private static cache: Map<string, uiMaterial.Material> = new Map();

  // ---------------------------------------------------------------------------
  // HDS 分支（API 23+，hdsMaterial）—— 作用于 HdsNavigation 标题栏 / HdsTabs 底部页签
  // ---------------------------------------------------------------------------

  /** 双探测：syscap（旧设备无此能力项）+ 设备材质白名单 */
  static supportsImmersive(): boolean {
    if (MaterialGate.cachedSupported === undefined) {
      try {
        const syscapOk: boolean = canIUse(HDS_SYSCAP);
        const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
        MaterialGate.cachedSupported = syscapOk && types.length > 0;
      } catch (e) {
        // 模拟器白名单常为空、旧设备无该命名空间 —— 均为正常降级路径
        MaterialGate.cachedSupported = false;
      }
    }
    return MaterialGate.cachedSupported;
  }

  /** 设备是否支持显式 IMMERSIVE 类型（决定能否自定义强/均衡档位） */
  static supportsExplicitImmersive(): boolean {
    if (!MaterialGate.supportsImmersive()) {
      return false;
    }
    try {
      return hdsMaterial.getSystemMaterialTypes()
        .indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0;
    } catch (e) {
      return false;
    }
  }

  /**
   * HdsTabs.barFloatingStyle / HdsNavigation titleBar.style 的 systemMaterialEffect 取值。
   * 官方模式：materialType 恒 ADAPTIVE，仅按能力决定 materialLevel；
   * 不支持时返回 undefined → Hds 组件走默认渲染（避免低端机"灰白实色玻璃"反效果）。
   */
  static systemMaterialEffect(
    level: MaterialLevelKey = MaterialGate.levelKey): SystemMaterialParams | undefined {
    if (!MaterialGate.supportsImmersive()) {
      return undefined;
    }
    let materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;
    if (level !== 'adaptive') {
      // 非自适应档位只在设备支持 IMMERSIVE 时才有意义
      materialLevel = level === 'exquisite' ? hdsMaterial.MaterialLevel.EXQUISITE
        : level === 'gentle' ? hdsMaterial.MaterialLevel.GENTLE
          : hdsMaterial.MaterialLevel.SMOOTH;
    }
    return {
      materialType: hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: materialLevel
    };
  }

  // ---------------------------------------------------------------------------
  // 普通组件分支（API 26+，uiMaterial）
  // ---------------------------------------------------------------------------

  /**
   * uiMaterial 可用性双判断：
   *  - uiMaterial 命名空间在 API 23~25 上不存在，构造即抛异常；
   *  - deviceInfo.apiAvailable('26.0.0') 会误报（个别 API 24 平板构建通过但枚举缺失）
   *    → 必须 sdkApiVersion >= 26 && apiAvailable(...) 双判断 + 实际构造 probe。
   * 且 apiAvailable 必须直接置于 if 条件中（同时形成运行时保护与编译告警消除）。
   */
  static canUseUiMaterial(): boolean {
    if (MaterialGate.cachedUiMaterialOk === undefined) {
      let ok: boolean = false;
      if (deviceInfo.sdkApiVersion >= 26 && deviceInfo.apiAvailable('26.0.0')) {
        try {
          const probe: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial();
          ok = !!probe;
        } catch (e) {
          ok = false;
        }
      }
      MaterialGate.cachedUiMaterialOk = ok;
    }
    return MaterialGate.cachedUiMaterialOk;
  }

  /**
   * 普通组件材质工厂；不可用返回 undefined
   * （.systemMaterial(undefined) = 恢复系统默认，低版本等价关闭）。
   * 构造失败绝不返回 Material.empty 伪装成功。
   * 版本判断直接置于 if 条件中——既形成运行时保护，也消除低版本 API 编译告警。
   */
  static createImmersiveMaterial(style: uiMaterial.ImmersiveStyle,
    styleKey: string,
    interactive: boolean = true,
    lightEffectColor: ResourceColor | null = null): uiMaterial.Material | undefined {
    if (!MaterialGate.canUseUiMaterial()) {
      return undefined;
    }
    if (!deviceInfo.apiAvailable('26.0.0')) {
      return undefined;
    }
    const cached: uiMaterial.Material | undefined = MaterialGate.cache.get(styleKey);
    if (cached) {
      return cached;
    }
    try {
      const lightEffect: uiMaterial.LightEffectOptions | null =
        lightEffectColor === null ? null : { color: lightEffectColor };
      const m: uiMaterial.Material = new uiMaterial.ImmersiveMaterial({
        style: style,
        interactive: interactive,
        applyShadow: true,
        colorInvert: true,
        lightEffect: lightEffect
      });
      MaterialGate.cache.set(styleKey, m);
      return m;
    } catch (e) {
      Logger.w(TAG, '构造 ImmersiveMaterial 失败，降级为无材质');
      return undefined;
    }
  }

  // —— 常用预设 ——
  static topBar(): uiMaterial.Material | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      return MaterialGate.createImmersiveMaterial(
        uiMaterial.ImmersiveStyle.ULTRA_THIN, 'topBar');
    }
    return undefined;
  }

  static searchField(): uiMaterial.Material | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      return MaterialGate.createImmersiveMaterial(
        uiMaterial.ImmersiveStyle.THIN, 'search');
    }
    return undefined;
  }

  static sheet(): uiMaterial.Material | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      return MaterialGate.createImmersiveMaterial(
        uiMaterial.ImmersiveStyle.REGULAR, 'sheet');
    }
    return undefined;
  }

  static menu(): uiMaterial.Material | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      return MaterialGate.createImmersiveMaterial(
        uiMaterial.ImmersiveStyle.THICK, 'menu');
    }
    return undefined;
  }

  static dialog(): uiMaterial.Material | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      return MaterialGate.createImmersiveMaterial(
        uiMaterial.ImmersiveStyle.ULTRA_THICK, 'dialog');
    }
    return undefined;
  }

  /**
   * 是否应渲染材质。注意 metadata = disable 时主动设置的材质也失效；
   * default/enable 下组件级设置照常生效，因此这里只判 DISABLE，其余按"可用"处理。
   */
  static isKitMaterialEnabled(): boolean {
    if (!deviceInfo.apiAvailable('26.0.0')) {
      return false;
    }
    try {
      const info: uiMaterial.MaterialInfo = uiMaterial.getMaterialInfo();
      return info.state !== uiMaterial.MaterialState.DISABLE;
    } catch (e) {
      return false;
    }
  }

  /**
   * 系统级沉浸光感档位：用户在「设置 → 桌面和个性化 → 沉浸光感」里关闭，
   * 或系统更新降级后，组件材质可能不显示，据此接上毛玻璃/纯色兜底。
   * 返回 'unsupported' | 'unknown' | 档位文本。
   */
  static globalMaterialLevelText(): string {
    if (!deviceInfo.apiAvailable('26.0.0')) {
      return 'unsupported';
    }
    try {
      return `${uiMaterial.getGlobalMaterialLevel()}`;
    } catch (e) {
      return 'unknown';
    }
  }

  /** 品牌色/深浅色变化时统一失效重建 */
  static invalidateCache(): void {
    MaterialGate.cache.clear();
    MaterialGate.cachedUiMaterialOk = undefined;
    MaterialGate.cachedSupported = undefined;
  }
}
