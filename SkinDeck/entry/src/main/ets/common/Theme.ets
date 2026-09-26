/**
 * Theme.ets — 设计 token 集中处：全局光学参数集中一处，
 * 避免各页面出现不同的雾化、亮度、景深。
 *
 * 约定：
 *   - 语义色一律走 $r('app.color.*')，深浅色由 resources/dark 成对覆盖，代码不判 isDark；
 *   - 只有"盖在图片/彩色表面上的前景色"不随主题翻转，收在本文件常量里；
 *   - 间距/圆角用 vp，字号用 fp。
 */

export class Space {
  static readonly XS: number = 4;
  static readonly SM: number = 8;
  static readonly MD: number = 12;
  static readonly LG: number = 16;
  static readonly XL: number = 24;
  static readonly XXL: number = 32;
}

export class Radius {
  static readonly SM: number = 8;
  static readonly MD: number = 12;
  static readonly LG: number = 16;
  static readonly XL: number = 24;
  static readonly PILL: number = 999;
}

export class FontSize {
  static readonly TITLE: number = 18;
  static readonly SUBTITLE: number = 16;
  static readonly BODY: number = 14;
  static readonly CAPTION: number = 12;
}

/** 布局常量 */
export class Layout {
  /**
   * 标题条高度（HDS MINI 标题栏 ≈56vp）。
   * 各页签滚动内容的"首个占位"用它 + 状态栏高度：静止时首行落在标题栏下方，
   * 滚动时内容钻到标题栏下面、被原生光感模糊。
   */
  static readonly TOP_BAR_H: number = 56;
  /** 底部页签栏高度 */
  static readonly TAB_BAR_H: number = 56;
}

/** 全局光学参数（改这里即全局生效） */
export class Glass {
  static readonly BLUR_RADIUS: number = 28;
  static readonly SATURATION: number = 1.26;
  static readonly BRIGHTNESS: number = 1.06;
  /** 磨砂面板圆角 */
  static readonly PANEL_RADIUS: number = 16;

  /** 半透明底（亮/暗两套） */
  static panel(isDark: boolean): string {
    return isDark ? '#33FFFFFF' : '#50FFFFFF';
  }

  /** 高光细描边 */
  static border(isDark: boolean): string {
    return isDark ? '#1FFFFFFF' : '#33FFFFFF';
  }

  /** 柔和投影 */
  static shadow(): ShadowOptions {
    return { radius: 32, color: '#25000000', offsetX: 3, offsetY: 6 };
  }

  /** 关闭态必须显式复位，否则 AttributeModifier 残留半玻璃错态 */
  static noBlur(): BackgroundEffectOptions {
    return { radius: 0, color: '#00000000' };
  }
}

/** 盖在图片/彩色表面上、不随主题翻转的前景色 */
export class OnSurface {
  static readonly SCRIM: string = '#33000000';
  static readonly FG: string = '#FFFFFF';
  static readonly FG_DIM: string = '#D9FFFFFF';
}

/**
 * 系统符号图标集中定义。
 *
 * 这里的每个名字都在本机 SDK 的系统资源表里逐个校验过
 *   （`E:\DevEco Studio\sdk\default\openharmony\ets\build-tools\ets-loader\sysResource.js`
 *    的 SYMBOL 表），不存在的名字会在**运行期**解析失败。
 *   本 SDK 里不存在、容易想当然写出来的名字：chart_line（整个 chart_* 系列都没有）、
 *   gear（正确的是 gearshape）、dot_3（用 dot_grid_2x2）、arrow_up_right_square（正确的是 arrow_up_right）。
 *   新增图标时请照上面的文件核对，或在此类的 getter 里加 try/catch 兜底。
 */
export class Icons {
  /** 行情：本 SDK 没有 chart_* 系列，waveform 是语义最接近的走势类符号 */
  static get market(): Resource { return $r('sys.symbol.waveform'); }
  static get watchlist(): Resource { return $r('sys.symbol.star'); }
  static get watchlistFill(): Resource { return $r('sys.symbol.star_fill'); }
  static get compare(): Resource { return $r('sys.symbol.arrow_left_arrow_right'); }
  /** 库存：archivebox（本 SDK 有 archivebox / archivebox_fill） */
  static get inventory(): Resource { return $r('sys.symbol.archivebox'); }
  static get inventoryFill(): Resource { return $r('sys.symbol.archivebox_fill'); }
  /** 注意是 gearshape，不是 gear */
  static get toolbox(): Resource { return $r('sys.symbol.gearshape'); }
  static get mine(): Resource { return $r('sys.symbol.person'); }
  static get mineFill(): Resource { return $r('sys.symbol.person_fill'); }
  static get search(): Resource { return $r('sys.symbol.magnifyingglass'); }
  static get close(): Resource { return $r('sys.symbol.xmark'); }
  static get add(): Resource { return $r('sys.symbol.plus'); }
  static get remove(): Resource { return $r('sys.symbol.trash'); }
  /** 本 SDK 没有 dot_3 / ellipsis，用 2x2 点阵做"更多" */
  static get more(): Resource { return $r('sys.symbol.dot_grid_2x2'); }
  static get chevronRight(): Resource { return $r('sys.symbol.chevron_right'); }
  static get refresh(): Resource { return $r('sys.symbol.arrow_clockwise'); }
  static get link(): Resource { return $r('sys.symbol.arrow_up_right'); }
  static get lock(): Resource { return $r('sys.symbol.lock'); }
  static get info(): Resource { return $r('sys.symbol.info_circle'); }
}

/** 涨跌配色：遵循中国习惯，涨红跌绿 */
export class PriceColor {
  static of(delta: number): Resource {
    if (delta > 0) {
      return $r('app.color.price_up');
    }
    if (delta < 0) {
      return $r('app.color.price_down');
    }
    return $r('app.color.price_flat');
  }

  static ofPct(pct: number | null): Resource {
    if (pct === null) {
      return $r('app.color.price_flat');
    }
    return PriceColor.of(pct);
  }
}
