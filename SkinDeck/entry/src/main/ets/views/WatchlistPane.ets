/**
 * 自选。
 * 功能：本地自选列表、逐条拉现价、成本录入、盈亏计算、涨跌、移出、一键刷新。
 * 取价策略：小批量并发（每批 3 条），避免瞬间打爆接口；单条失败只留空价，不打断整页。
 *
 * 两个渲染上的约束：
 * 1) 外部写入要能被感知。本页渲染靠 @Local rows，而 rows 只在 aboutToAppear 与本页操作里
 *    写入，别处改 watch.items 本页收不到 → 用 @Monitor('watch.items') 重新对账。
 * 2) 原地改内容不能用 LazyForEach + @Builder 传值。@Builder 的按值参数会被固化，
 *    逐条 onDataChange 也带不进已建好的行。现在是一轮取价结束整表替换 @Local rows，
 *    再用 ForEach + "带现价签名"的 key 重建变化的行；行本身是 @ComponentV2（WatchRow）。
 */

import { FetchChannel, ItemSummary, WatchItem, WatchQuote } from '../model/Types';
import { MarketService } from '../data/MarketService';
import { SettingsState, connectSettings } from '../state/SettingsState';
import { WatchlistState, connectWatchlist } from '../state/WatchlistState';
import { WindowMetrics, connectWindowMetrics } from '../state/WindowMetrics';
import { StateView } from '../components/StateView';
import { ParseUtil } from '../data/ParseUtil';
import { FontSize, Icons, Layout, PriceColor, Radius, Space } from '../common/Theme';
import { Nav } from '../common/Nav';
import { Logger } from '../common/Logger';

const TAG: string = 'WatchlistTab';
/** 每批并发条数 */
const BATCH: number = 3;

/**
 * ForEach 的 key：必须带"内容签名"。
 * ForEach 只有 key 变了才会用新数据重建节点 —— key 只用 item.key 的话，
 * 价格变了 key 没变，节点会继续显示旧值。
 */
function rowKey(wq: WatchQuote): string {
  const price: string = wq.currentCent === null ? 'n' : `${wq.currentCent}`;
  const profit: string = wq.profitPct === null ? 'n' : wq.profitPct.toFixed(2);
  const delta: string = wq.deltaPct === null ? 'n' : wq.deltaPct.toFixed(2);
  return `${wq.item.key}|${price}|${profit}|${delta}`;
}

/**
 * 自选行。
 *
 * 用 @ComponentV2 而不是 @Builder：@Builder 的按值参数会被固化，调用处传变量
 * （`this.row(wq)`）时，这一行的现价换了也不会重绘。ArkUI 只有"调用时传对象字面量"
 * 才算按引用传递，传变量一律按值。
 */
@ComponentV2
struct WatchRow {
  @Require @Param wq: WatchQuote;
  @Event onCost: (item: WatchItem) => void = () => {
  };
  @Event onRemove: (key: string) => void = () => {
  };
  @Event onOpen: (q: WatchQuote) => void = () => {
  };

  @Builder
  miniAction(label: string, onTap: () => void) {
    Text(label)
      .fontSize(FontSize.CAPTION)
      .fontColor($r('app.color.brand_primary'))
      .backgroundColor($r('app.color.brand_soft'))
      .borderRadius(Radius.SM)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .onClick(onTap)
  }

  build() {
    Column({ space: Space.SM }) {
      Row({ space: Space.MD }) {
        Stack() {
          if (this.wq.item.iconUrl.length > 0) {
            Image(this.wq.item.iconUrl)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
              .interpolation(ImageInterpolation.Medium)
          }
        }
        .width(52)
        .height(52)
        .borderRadius(Radius.MD)
        .backgroundColor($r('app.color.surface_sunken'))
        .clip(true)

        Column({ space: 2 }) {
          Text(this.wq.item.name)
            .fontSize(FontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(`${this.wq.item.platform === 'buff' ? 'BUFF' : 'UU'} · 成本 ` +
            `${this.wq.item.costCent > 0 ? ParseUtil.centToYuan(this.wq.item.costCent) : '未录入'}`)
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 2 }) {
          Text(ParseUtil.centToYuan(this.wq.currentCent))
            .fontSize(FontSize.SUBTITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(`盈亏 ${ParseUtil.pctText(this.wq.profitPct)}`)
            .fontSize(FontSize.CAPTION)
            .fontColor(PriceColor.ofPct(this.wq.profitPct))
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')

      Row({ space: Space.SM }) {
        Text(`较加入时 ${ParseUtil.pctText(this.wq.deltaPct)}`)
          .fontSize(FontSize.CAPTION)
          .fontColor(PriceColor.ofPct(this.wq.deltaPct))
        Blank()
        this.miniAction('录成本', () => {
          this.onCost(this.wq.item);
        })
        this.miniAction('移出', () => {
          this.onRemove(this.wq.item.key);
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(Space.MD)
    .backgroundColor($r('app.color.surface_bg'))
    .borderRadius(Radius.MD)
    .border({ width: 0.5, color: $r('app.color.divider') })
    .onClick(() => {
      this.onOpen(this.wq);
    })
  }
}

@ComponentV2
export struct WatchlistPane {
  /**
   * 作为「比价」页的子视图嵌入时为 true：顶部让位交给容器统一负责，
   * 自己只留一点间距，否则会出现两次让位、把内容压下去。
   */
  @Param embedded: boolean = false;
  @Local settings: SettingsState = connectSettings();
  @Local watch: WatchlistState = connectWatchlist();
  @Local metrics: WindowMetrics = connectWindowMetrics();

  /** 展示行（本地状态，一轮取价结束整表替换 → ForEach 必然重绘） */
  @Local rows: WatchQuote[] = [];
  @Local refreshing: boolean = false;
  @Local loading: boolean = false;
  /** 本轮取价失败的条数（部分失败时给个提示，不打断整页） */
  @Local failedCount: number = 0;

  /** 成本录入浮层 */
  @Local editingKey: string = '';
  @Local editingName: string = '';
  @Local editingValue: string = '';

  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.syncRows();
    if (this.rows.length > 0) {
      this.refresh();
    }
  }

  /**
   * 自选被别处改动时重新对账（行情页点星标、详情页加入/移出）。
   *
   * 这是本页唯一的外部变更入口：本页渲染靠 rows，而 rows 只在 aboutToAppear 与本页操作里
   * 被写入，别处改了 watch.items 本页感知不到。
   */
  @Monitor('watch.items')
  onWatchItemsChanged(): void {
    const grew: boolean = this.watch.items.length > this.rows.length;
    this.syncRows();
    if (grew) {
      // 新加入的条目还没有现价，立刻补一次
      this.refresh();
    }
  }

  /** watch.items → 展示行；同 key 的旧现价沿用，避免对账时价格闪空 */
  private syncRows(): void {
    const priceOf: Map<string, number | null> = new Map<string, number | null>();
    for (let i = 0; i < this.rows.length; i++) {
      priceOf.set(this.rows[i].item.key, this.rows[i].currentCent);
    }
    const next: WatchQuote[] = [];
    for (let i = 0; i < this.watch.items.length; i++) {
      const w: WatchItem = this.watch.items[i];
      const cached: number | null | undefined = priceOf.get(w.key);
      next.push(WatchlistState.quoteOf(w, cached === undefined ? null : cached));
    }
    this.rows = next;
  }

  private async refresh(): Promise<void> {
    // 先对账再取价：别处刚加进来的条目也要在这一轮里拿到现价
    this.syncRows();
    if (this.watch.items.length === 0) {
      this.refreshing = false;
      this.loading = false;
      return;
    }
    this.loading = true;
    this.failedCount = 0;
    const items: WatchItem[] = this.watch.items.slice();
    const quotes: Map<string, number | null> = new Map<string, number | null>();
    Logger.i(TAG, `自选取价开始：${items.length} 条`);

    for (let start = 0; start < items.length; start += BATCH) {
      const end: number = Math.min(start + BATCH, items.length);
      const tasks: Promise<void>[] = [];
      for (let i = start; i < end; i++) {
        tasks.push(this.loadOne(items[i], quotes));
      }
      await Promise.all(tasks);
    }

    // 本轮结果整表替换：逐条派发在这套结构下带不进已建好的行
    this.commitQuotes(quotes);
    this.loading = false;
    this.refreshing = false;
    Logger.i(TAG, `自选取价结束：失败 ${this.failedCount} 条`);
  }

  private async loadOne(w: WatchItem, quotes: Map<string, number | null>): Promise<void> {
    const summary: ItemSummary = WatchlistState.toSummary(w, null);
    const cent: number | null =
      await MarketService.quote(summary, this.settings.fetchChannel);
    if (cent === null) {
      this.failedCount++;
    }
    quotes.set(w.key, cent);
  }

  /** 把本轮取到的价格交给 @Local rows；本轮没取到的沿用上一轮的旧值 */
  private commitQuotes(quotes: Map<string, number | null>): void {
    const prevPrice: Map<string, number | null> = new Map<string, number | null>();
    for (let i = 0; i < this.rows.length; i++) {
      prevPrice.set(this.rows[i].item.key, this.rows[i].currentCent);
    }
    const next: WatchQuote[] = [];
    for (let i = 0; i < this.watch.items.length; i++) {
      const w: WatchItem = this.watch.items[i];
      const fresh: number | null | undefined = quotes.get(w.key);
      let cent: number | null = fresh === undefined ? null : fresh;
      if (cent === null) {
        const old: number | null | undefined = prevPrice.get(w.key);
        cent = old === undefined ? null : old;
      }
      next.push(WatchlistState.quoteOf(w, cent));
    }
    this.rows = next;
    Logger.i(TAG, `自选提交 ${next.length} 行（本轮报价 ${quotes.size} 条）`);
  }

  private openCostEditor(item: WatchItem): void {
    this.editingKey = item.key;
    this.editingName = item.name;
    this.editingValue = item.costCent > 0 ? (item.costCent / 100).toFixed(2) : '';
  }

  private saveCost(): void {
    const v: number = Number.parseFloat(this.editingValue);
    const cent: number = Number.isNaN(v) || v <= 0 ? 0 : Math.round(v * 100);
    this.watch.setCost(this.editingKey, cent);
    this.editingKey = '';
    // setCost 会触发 @Monitor → syncRows 已经用新成本重算了盈亏，这里无需再取价
  }

  // -------------------------------------------------------------------------
  // 视图
  // -------------------------------------------------------------------------

  @Builder
  header() {
    Row({ space: Space.SM }) {
      Text(`自选 ${this.rows.length} 件`)
        .fontSize(FontSize.SUBTITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      if (this.settings.fetchChannel === FetchChannel.BRIDGE) {
        Text('网页桥接')
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.warn_fg'))
          .backgroundColor($r('app.color.warn_bg'))
          .borderRadius(Radius.SM)
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
      }
      if (this.failedCount > 0) {
        Text(`${this.failedCount} 条取价失败`)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.price_up'))
      }
      Blank()
      if (this.loading) {
        LoadingProgress().width(18).height(18)
      } else {
        SymbolGlyph(Icons.refresh)
          .fontSize(18)
          .fontColor([$r('app.color.brand_primary')])
          .onClick(() => {
            this.refresh();
          })
      }
    }
    .width('100%')
    .padding({ left: Space.LG, right: Space.LG, top: Space.SM, bottom: Space.SM })
  }

  @Builder
  costEditor() {
    Column({ space: Space.MD }) {
      Text(`录入「${this.editingName}」成本价`)
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      TextInput({ text: this.editingValue, placeholder: '成本价（元），如 1234.56' })
        .type(InputType.NUMBER_DECIMAL)
        .fontSize(FontSize.BODY)
        .backgroundColor($r('app.color.surface_sunken'))
        .onChange((v: string) => {
          this.editingValue = v;
        })

      Row({ space: Space.MD }) {
        Button('取消')
          .backgroundColor($r('app.color.tag_bg'))
          .fontColor($r('app.color.text_secondary'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .onClick(() => {
            this.editingKey = '';
          })
        Button('保存')
          .backgroundColor($r('app.color.brand_primary'))
          .fontColor($r('app.color.brand_on'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .onClick(() => {
            this.saveCost();
          })
      }
      .width('100%')
    }
    .width('80%')
    .padding(Space.LG)
    .backgroundColor($r('app.color.surface_elevated'))
    .borderRadius(Radius.XL)
    .shadow({ radius: 40, color: '#40000000', offsetX: 0, offsetY: 8 })
  }

  build() {
    Stack() {
      Column() {
        if (this.rows.length === 0) {
          Column() {
            this.header()
            StateView({
              kind: 'empty',
              message: '还没有自选。去「行情」页点右侧星标即可加入',
              actionText: ''
            })
          }
          .width('100%')
          .layoutWeight(1)
          // 空态不在滚动容器里，自己让开顶部模糊条
          .padding({ top: this.embedded ? Space.SM : this.metrics.topInsetVp + Layout.TOP_BAR_H })
        } else {
          Refresh({ refreshing: $$this.refreshing }) {
            List({ scroller: this.scroller }) {
              // 顶部让位 + 表头都放进滚动内容：静止时位于顶部模糊条下方，
              // 滚动时一起钻到条下面被模糊
              ListItem() {
                Column()
                  .width('100%')
                  .height(this.embedded ? Space.SM : this.metrics.topInsetVp + Layout.TOP_BAR_H)
              }
              ListItem() {
                this.header()
              }

              ForEach(this.rows, (wq: WatchQuote) => {
                ListItem() {
                  WatchRow({
                    wq: wq,
                    onCost: (item: WatchItem) => {
                      this.openCostEditor(item);
                    },
                    onRemove: (key: string) => {
                      this.watch.remove(key);
                    },
                    onOpen: (q: WatchQuote) => {
                      Nav.toDetail(WatchlistState.toSummary(q.item, q.currentCent));
                    }
                  })
                }
                .padding({ left: Space.LG, right: Space.LG, top: Space.XS, bottom: Space.XS })
              }, (wq: WatchQuote) => rowKey(wq))

              // 底部留白做占位 item，不要用 List().padding({bottom})（会在底部留出灰带）
              ListItem() {
                Column()
                  .width('100%')
                  .height(this.metrics.bottomInsetVp + 88)
              }
            }
            .width('100%')
            .height('100%')
            .cachedCount(6)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            // 滚动容器自己扩展进状态栏区域，内容才能滚到状态栏后面被标题栏模糊
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          }
          .width('100%')
          .layoutWeight(1)
          .onRefreshing(() => {
            this.refreshing = true;
            this.refresh();
          })
        }
      }
      .width('100%')
      .height('100%')

      if (this.editingKey.length > 0) {
        Column() {
          this.costEditor()
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.editingKey = '';
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
