/**
 * TrendChart.ets — 价格走势图（零依赖自绘）
 *
 * 为什么不用 Canvas：Canvas 的 fillStyle 只接受颜色字符串，无法直接用 $r() 语义资源，
 * 深浅色要额外管道；而 Path 组件的 fill/stroke 接受 ResourceColor，
 * 因此用 Path 的 commands 画折线 + 面积，天然跟随主题。
 */

import { PricePoint } from '../model/Types';
import { FontSize } from '../common/Theme';

const TREND_HEIGHT: number = 160;
const PAD: number = 10;

@ComponentV2
export struct TrendChart {
  @Require @Param points: PricePoint[];
  @Param minCent: number = 0;
  @Param maxCent: number = 0;
  @Local chartW: number = 0;

  private xAt(i: number, n: number): number {
    if (n <= 1) {
      return PAD;
    }
    return PAD + (i / (n - 1)) * (this.chartW - PAD * 2);
  }

  private yAt(cent: number): number {
    const span: number = Math.max(1, this.maxCent - this.minCent);
    const usable: number = TREND_HEIGHT - PAD * 2;
    return TREND_HEIGHT - PAD - ((cent - this.minCent) / span) * usable;
  }

  private lineCommands(): string {
    const n: number = this.points.length;
    if (n < 2 || this.chartW <= PAD * 2) {
      return '';
    }
    let d: string = '';
    for (let i = 0; i < n; i++) {
      const x: number = this.xAt(i, n);
      const y: number = this.yAt(this.points[i].priceCent);
      d += `${i === 0 ? 'M' : 'L'}${x.toFixed(1)} ${y.toFixed(1)} `;
    }
    return d;
  }

  private areaCommands(): string {
    const n: number = this.points.length;
    if (n < 2 || this.chartW <= PAD * 2) {
      return '';
    }
    const line: string = this.lineCommands();
    // toFixed 返回 string，别标成 number
    const lastX: string = this.xAt(n - 1, n).toFixed(1);
    const firstX: string = this.xAt(0, n).toFixed(1);
    const bottom: number = TREND_HEIGHT;
    return `${line}L${lastX} ${bottom} L${firstX} ${bottom} Z`;
  }

  build() {
    Column() {
      if (this.points.length >= 2 && this.chartW > PAD * 2) {
        Stack() {
          Path()
            .commands(this.areaCommands())
            .fill($r('app.color.chart_fill'))
            .width(this.chartW)
            .height(TREND_HEIGHT)
          Path()
            .commands(this.lineCommands())
            .fill(Color.Transparent)
            .stroke($r('app.color.chart_line'))
            .strokeWidth(2)
            .strokeLineCap(LineCapStyle.Round)
            .strokeLineJoin(LineJoinStyle.Round)
            .width(this.chartW)
            .height(TREND_HEIGHT)
        }
        .width(this.chartW)
        .height(TREND_HEIGHT)
      } else {
        Column() {
          Text('暂无成交数据')
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .height(TREND_HEIGHT)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height(TREND_HEIGHT)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const w: number = Number(newArea.width);
      if (w > 0 && w !== this.chartW) {
        this.chartW = w;
      }
    })
  }
}
