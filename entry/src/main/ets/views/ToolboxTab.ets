/**
 * ToolboxTab.ets — 工具箱（纯本地计算，不发请求）。
 * 1) 磨损换算：float → 外观等级 + 区间位置
 * 2) 挂刀比例：Steam 挂单价 / BUFF 买入价 → 是否值得挂刀
 * 3) 租金收益：饰品价格 + 日租金 + 租期 → 年化收益率
 *
 * 交互：输入 → 点「确定」→ 结果写入 @Local → ResultPanel（@Param）渲染。
 * 结果不能用 @Builder 的按值参数承载：参数会被固化，结果区不会刷新；
 * 输入非法时面板给出具体原因，不会把上一次结果留在屏上。
 *
 * 布局用 List 而不是 Scroll：本页内容比视口短，Scroll 会把内容垂直居中，
 * 让位占位之外多出一大块空白；List 恒顶部对齐，也与其它页签一致。
 */

import { FontSize, Layout, Radius, Space } from '../common/Theme';
import { sectionTitle } from '../common/Glass';
import { LabeledInput } from '../components/LabeledInput';
import { ResultPanel } from '../components/ResultPanel';
import { WindowMetrics, connectWindowMetrics } from '../state/WindowMetrics';
import { Logger } from '../common/Logger';

const TAG: string = 'ToolboxTab';

/** CS2 外观等级区间（官方阈值） */
interface ExteriorBand {
  name: string;
  min: number;
  max: number;
}

const BANDS: ExteriorBand[] = [
  { name: '崭新出厂', min: 0.00, max: 0.07 },
  { name: '略有磨损', min: 0.07, max: 0.15 },
  { name: '久经沙场', min: 0.15, max: 0.38 },
  { name: '破损不堪', min: 0.38, max: 0.45 },
  { name: '战痕累累', min: 0.45, max: 1.00 }
];

/** Steam 市场手续费率 */
const STEAM_FEE: number = 0.15;

/** 玩具计算结果：主结论 + 明细行 */
interface CalcResult {
  ok: boolean;
  headline: string;
  lines: string[];
}

// ---------------------------------------------------------------------------
// 计算（模块级函数：struct 内不声明静态方法）
// ---------------------------------------------------------------------------

function calcWear(text: string): CalcResult {
  const f: number = Number.parseFloat(text);
  if (Number.isNaN(f) || f < 0 || f > 1) {
    return {
      ok: false,
      headline: '磨损值不合法',
      lines: ['请填写 0 ~ 1 之间的小数，例如 0.1523']
    };
  }
  let band: ExteriorBand = BANDS[BANDS.length - 1];
  for (let i = 0; i < BANDS.length; i++) {
    if (f < BANDS[i].max) {
      band = BANDS[i];
      break;
    }
  }
  const span: number = band.max - band.min;
  const pos: number = span > 0 ? ((f - band.min) / span) * 100 : 0;
  return {
    ok: true,
    headline: band.name,
    lines: [
      `磨损值：${f.toFixed(4)}`,
      `等级区间：${band.min.toFixed(2)} ~ ${band.max.toFixed(2)}`,
      `落在该区间第 ${pos.toFixed(1)}% 的位置`,
      `距下一等级阈值：还差 ${(band.max - f).toFixed(4)}`
    ]
  };
}

function calcSwitch(buffText: string, steamText: string): CalcResult {
  const buff: number = Number.parseFloat(buffText);
  const steam: number = Number.parseFloat(steamText);
  if (Number.isNaN(buff) || Number.isNaN(steam) || buff <= 0 || steam <= 0) {
    return {
      ok: false,
      headline: '价格不完整',
      lines: ['BUFF 买入价与 Steam 挂单价都要填大于 0 的数字']
    };
  }
  const ratio: number = steam / buff;
  const net: number = steam * (1 - STEAM_FEE) - buff;
  let verdict: string = '不建议';
  if (ratio >= 1.25) {
    verdict = '很划算';
  } else if (ratio >= 1.18) {
    verdict = '可以考虑';
  } else if (ratio >= 1.12) {
    verdict = '偏紧，看余额需求';
  }
  return {
    ok: true,
    headline: `比例 ${ratio.toFixed(3)} · ${verdict}`,
    lines: [
      `挂刀比例：Steam ${steam.toFixed(2)} ÷ BUFF ${buff.toFixed(2)} = ${ratio.toFixed(3)}`,
      `Steam 扣 ${(STEAM_FEE * 100).toFixed(0)}% 手续费后到手 ${(steam * (1 - STEAM_FEE)).toFixed(2)} 元`,
      `净收益：${net >= 0 ? '+' : ''}${net.toFixed(2)} 元`,
      `结论：${verdict}`
    ]
  };
}

function calcLease(priceText: string, rentText: string, daysText: string): CalcResult {
  const price: number = Number.parseFloat(priceText);
  const rent: number = Number.parseFloat(rentText);
  if (Number.isNaN(price) || Number.isNaN(rent) || price <= 0 || rent <= 0) {
    return {
      ok: false,
      headline: '数据不完整',
      lines: ['饰品成本与日租金都要填大于 0 的数字']
    };
  }
  const parsedDays: number = Number.parseFloat(daysText);
  const days: number = Number.isNaN(parsedDays) || parsedDays <= 0 ? 7 : parsedDays;
  const periodRent: number = rent * days;
  const periodRoi: number = (periodRent / price) * 100;
  const annualRoi: number = (rent * 365 / price) * 100;
  const coverDays: number = price / rent;
  return {
    ok: true,
    headline: `年化约 ${annualRoi.toFixed(1)}%`,
    lines: [
      `单期（${days} 天）租金：${periodRent.toFixed(2)} 元`,
      `单期收益率：${periodRoi.toFixed(2)}%`,
      `年化收益率：约 ${annualRoi.toFixed(1)}%`,
      `约 ${coverDays.toFixed(0)} 天可收回成本`
    ]
  };
}

@ComponentV2
export struct ToolboxTab {
  @Local tool: number = 0;
  @Local metrics: WindowMetrics = connectWindowMetrics();

  // 磨损
  @Local floatText: string = '';

  // 挂刀
  @Local buffPriceText: string = '';
  @Local steamPriceText: string = '';

  // 租金
  @Local itemPriceText: string = '';
  @Local dayRentText: string = '';
  @Local daysText: string = '7';

  // 输出栏：只有按下「确定」后才写入
  @Local outShown: boolean = false;
  @Local outOk: boolean = false;
  @Local outHeadline: string = '';
  @Local outLines: string[] = [];

  private scroller: Scroller = new Scroller();

  private clearOutput(): void {
    this.outShown = false;
    this.outOk = false;
    this.outHeadline = '';
    this.outLines = [];
  }

  private pickTool(index: number): void {
    if (this.tool === index) {
      return;
    }
    this.tool = index;
    // 换工具就清空输出，避免把上一个工具的结果留在屏上
    this.clearOutput();
  }

  /** 「确定」：把当前工具的输入算成结果写进输出栏 */
  private confirm(): void {
    let r: CalcResult;
    if (this.tool === 0) {
      r = calcWear(this.floatText);
    } else if (this.tool === 1) {
      r = calcSwitch(this.buffPriceText, this.steamPriceText);
    } else {
      r = calcLease(this.itemPriceText, this.dayRentText, this.daysText);
    }
    this.outOk = r.ok;
    this.outHeadline = r.headline;
    this.outLines = r.lines;
    this.outShown = true;
    Logger.i(TAG, `工具 ${this.tool} 计算完成 ok=${r.ok}`);
  }

  /** 「清空」：输入与输出一起复位 */
  private resetAll(): void {
    this.floatText = '';
    this.buffPriceText = '';
    this.steamPriceText = '';
    this.itemPriceText = '';
    this.dayRentText = '';
    this.daysText = '7';
    this.clearOutput();
  }

  // -------------------------------------------------------------------------
  // 视图
  // -------------------------------------------------------------------------

  /** 无参数 @Builder：内部直接读 this.tool，依赖登记在本组件上，可以正常刷新 */
  @Builder
  toolChip(index: number, label: string) {
    Text(label)
      .fontSize(FontSize.CAPTION)
      .fontColor(this.tool === index
        ? $r('app.color.brand_on') : $r('app.color.text_secondary'))
      .backgroundColor(this.tool === index
        ? $r('app.color.brand_primary') : $r('app.color.tag_bg'))
      .borderRadius(Radius.PILL)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .onClick(() => {
        this.pickTool(index);
      })
  }

  @Builder
  actionBar() {
    Row({ space: Space.MD }) {
      Button('清空')
        .layoutWeight(1)
        .height(44)
        .type(ButtonType.Capsule)
        .backgroundColor($r('app.color.tag_bg'))
        .fontColor($r('app.color.text_secondary'))
        .onClick(() => {
          this.resetAll();
        })
      Button('确定')
        .layoutWeight(2)
        .height(44)
        .type(ButtonType.Capsule)
        .backgroundColor($r('app.color.brand_primary'))
        .fontColor($r('app.color.brand_on'))
        .onClick(() => {
          this.confirm();
        })
    }
    .width('100%')
  }

  @Builder
  outputArea() {
    Column({ space: Space.SM }) {
      if (this.outShown) {
        ResultPanel({
          ok: this.outOk,
          headline: this.outHeadline,
          lines: this.outLines,
          title: '计算结果'
        })
      } else {
        Text('填好上面的数据后点「确定」，结果会显示在这里。')
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding(Space.MD)
          .backgroundColor($r('app.color.surface_bg'))
          .borderRadius(Radius.MD)
          .border({ width: 0.5, color: $r('app.color.divider') })
      }
    }
    .width('100%')
  }

  build() {
    List({ scroller: this.scroller }) {
      // 顶部让位放在滚动内容里：滚动时内容能钻到顶部模糊条下面
      ListItem() {
        Column()
          .width('100%')
          .height(this.metrics.topInsetVp + Layout.TOP_BAR_H)
      }

      ListItem() {
        Row({ space: Space.SM }) {
          this.toolChip(0, '磨损换算')
          this.toolChip(1, '挂刀比例')
          this.toolChip(2, '租金收益')
        }
        .width('100%')
      }
      .padding({ left: Space.LG, right: Space.LG, top: Space.SM })

      ListItem() {
        Column({ space: Space.MD }) {
          if (this.tool === 0) {
            sectionTitle('磨损换算')
            Text('输入检视器里的 float 值，换算成外观等级与区间位置。')
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
            LabeledInput({
              label: '磨损值（0 ~ 1）',
              value: this.floatText,
              placeholder: '如 0.1523',
              onValue: (v: string) => {
                this.floatText = v;
              }
            })
          } else if (this.tool === 1) {
            sectionTitle('挂刀比例')
            Text('挂刀 = 在 BUFF 买入、到 Steam 市场卖出换余额。比例 = Steam 价 ÷ BUFF 价，' +
              '已按 15% 市场手续费折算净收益。')
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
            LabeledInput({
              label: 'BUFF 买入价',
              value: this.buffPriceText,
              placeholder: '如 1200',
              suffix: '元',
              onValue: (v: string) => {
                this.buffPriceText = v;
              }
            })
            LabeledInput({
              label: 'Steam 挂单价',
              value: this.steamPriceText,
              placeholder: '如 1600',
              suffix: '元',
              onValue: (v: string) => {
                this.steamPriceText = v;
              }
            })
          } else {
            sectionTitle('租金收益')
            Text('按日租金与饰品成本估算单期与年化收益率（未计押金、平台手续费与空租期）。')
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
            LabeledInput({
              label: '饰品成本',
              value: this.itemPriceText,
              placeholder: '如 3000',
              suffix: '元',
              onValue: (v: string) => {
                this.itemPriceText = v;
              }
            })
            LabeledInput({
              label: '日租金',
              value: this.dayRentText,
              placeholder: '如 4.5',
              suffix: '元',
              onValue: (v: string) => {
                this.dayRentText = v;
              }
            })
            LabeledInput({
              label: '租期',
              value: this.daysText,
              placeholder: '如 7',
              suffix: '天',
              onValue: (v: string) => {
                this.daysText = v;
              }
            })
          }

          this.actionBar()
          this.outputArea()

          Text('以上计算均为本地估算，不构成任何投资建议。')
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .padding({ left: Space.LG, right: Space.LG, top: Space.LG })

      // 底部留白做占位 item，不要用 List().padding({bottom})（会在底部留出灰带）
      ListItem() {
        Column()
          .width('100%')
          .height(this.metrics.bottomInsetVp + 88)
      }
    }
    .width('100%')
    .height('100%')
    .cachedCount(3)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    // 滚动容器自己扩展进状态栏区域，内容才能滚到状态栏后面被标题栏模糊
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
