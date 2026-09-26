/**
 * 双平台比价。
 * 输入关键词 → 两平台各拉一页 → 按"款式 + 磨损"配对 → 价差排序 → 给出入手建议。
 * 单边失败不阻断：有一边就展示一边，并在建议里注明。
 *
 * 搜索栏与本页状态无关，恒常渲染：它是本功能的唯一入口，不能只在"有结果"时才出现，
 * 否则首次进入（还没有结果）时页面上一个输入框都没有。
 *
 * 跨页签入口：详情页「跨平台比价」通过 ShellState 写入关键词 + 请求序号，
 * 本页 @Monitor('shell.compareNonce') 收到后自动填入并立即发起比价。
 */

import { AppError, CompareRow, FailKind, SortBy } from '../model/Types';
import { MarketService } from '../data/MarketService';
import { BasicDataSource } from '../datasource/BasicDataSource';
import { SettingsState, connectSettings } from '../state/SettingsState';
import { ShellState, connectShell } from '../state/ShellState';
import { WindowMetrics, connectWindowMetrics } from '../state/WindowMetrics';
import { StateView } from '../components/StateView';
import { ParseUtil } from '../data/ParseUtil';
import { FontSize, Icons, Layout, PriceColor, Radius, Space } from '../common/Theme';

/**
 * 比价结果行。
 * 用组件 + @Param 而不是 @Builder 传值：@Builder 的按值参数会被固化，
 * 换关键词重查后价格不会刷新。
 */
@ComponentV2
struct CompareRowView {
  @Require @Param row: CompareRow;

  @Builder
  priceCell(label: string, cent: number | null, highlight: boolean) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.text_tertiary'))
      Text(ParseUtil.centToYuan(cent))
        .fontSize(FontSize.BODY)
        .fontWeight(highlight ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(highlight ? $r('app.color.brand_primary') : $r('app.color.text_primary'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: Space.SM }) {
      Text(this.row.name)
        .fontSize(FontSize.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row({ space: Space.MD }) {
        this.priceCell('网易BUFF',
          this.row.buffPriceCent,
          this.row.diffCent !== null && this.row.diffCent < 0)
        this.priceCell('悠悠有品',
          this.row.uuPriceCent,
          this.row.diffCent !== null && this.row.diffCent > 0)
        Column({ space: 2 }) {
          Text('价差')
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.text_tertiary'))
          Text(ParseUtil.pctText(this.row.diffPct))
            .fontSize(FontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(PriceColor.ofPct(this.row.diffPct === null ? null : -this.row.diffPct))
        }
        .width(72)
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')

      Text(this.row.advice)
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.tag_fg'))
        .backgroundColor($r('app.color.tag_bg'))
        .borderRadius(Radius.SM)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
    }
    .width('100%')
    .padding(Space.MD)
    .backgroundColor($r('app.color.surface_bg'))
    .borderRadius(Radius.MD)
    .border({ width: 0.5, color: $r('app.color.divider') })
  }
}

@ComponentV2
export struct ComparePane {
  /**
   * 作为「比价」页的子视图嵌入时为 true：顶部让位交给容器统一负责，
   * 自己只留一点间距，否则会出现两次让位、把内容压下去。
   */
  @Param embedded: boolean = false;
  @Local settings: SettingsState = connectSettings();
  @Local shell: ShellState = connectShell();
  @Local metrics: WindowMetrics = connectWindowMetrics();

  @Local keyword: string = '';
  @Local rowCount: number = 0;
  @Local loading: boolean = false;
  @Local searched: boolean = false;
  @Local errMsg: string = '';
  @Local failKind: FailKind = FailKind.UNAVAILABLE;

  /** 稳定实例，避免每次 build 重建丢监听器 */
  private ds: BasicDataSource<CompareRow> = new BasicDataSource<CompareRow>();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    // 本页可能是在详情页点「跨平台比价」之后才第一次被创建的，
    // 而 @Monitor 只在组件已存在时触发，所以这里补一次。
    this.consumePendingCompare();
  }

  /** 详情页请求了比价：填入关键词并立即开跑 */
  @Monitor('shell.compareNonce')
  onCompareRequested(): void {
    this.consumePendingCompare();
  }

  private consumePendingCompare(): void {
    const kw: string = this.shell.takePendingCompare();
    if (kw.length === 0) {
      return;
    }
    this.keyword = kw;
    this.runCompare();
  }

  private async runCompare(): Promise<void> {
    const kw: string = this.keyword.trim();
    if (kw.length === 0) {
      return;
    }
    this.loading = true;
    this.errMsg = '';
    try {
      const rows: CompareRow[] =
        await MarketService.compare(kw, this.settings.fetchChannel, SortBy.DEFAULT);
      this.ds.replaceData(rows);
      this.rowCount = rows.length;
      this.searched = true;
    } catch (e) {
      const err: AppError = e instanceof AppError
        ? e : new AppError(FailKind.NETWORK, '比价失败');
      this.errMsg = err.message;
      this.failKind = err.kind;
      this.ds.replaceData([]);
      this.rowCount = 0;
    } finally {
      this.loading = false;
    }
  }

  // -------------------------------------------------------------------------
  // 视图
  // -------------------------------------------------------------------------

  @Builder
  searchBar() {
    Row({ space: Space.SM }) {
      SymbolGlyph(Icons.compare)
        .fontSize(18)
        .fontColor([$r('app.color.text_tertiary')])
      TextInput({ text: this.keyword, placeholder: '输入饰品名，如 蝴蝶刀 | 渐变' })
        .placeholderFont({ size: FontSize.BODY })
        .fontSize(FontSize.BODY)
        .backgroundColor(Color.Transparent)
        .padding(0)
        .height(36)
        .layoutWeight(1)
        .enterKeyType(EnterKeyType.Search)
        .onChange((v: string) => {
          this.keyword = v;
        })
        .onSubmit(() => {
          this.runCompare();
        })
      Button('比价')
        .fontSize(FontSize.CAPTION)
        .height(30)
        .backgroundColor($r('app.color.brand_primary'))
        .fontColor($r('app.color.brand_on'))
        .type(ButtonType.Capsule)
        .enabled(!this.loading)
        .onClick(() => {
          this.runCompare();
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: Space.MD, right: Space.SM })
    .backgroundColor($r('app.color.surface_sunken'))
    .borderRadius(Radius.PILL)
  }

  /** 搜索栏 + 说明/计数：与页面状态无关，任何分支下都在 */
  @Builder
  searchHeader() {
    Column({ space: Space.SM }) {
      this.searchBar()
      Row() {
        Text('同时查网易BUFF 与 悠悠有品，按款式配对后按价差降序')
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.text_tertiary'))
          .layoutWeight(1)
        if (this.loading) {
          LoadingProgress()
            .width(16)
            .height(16)
        } else if (this.searched && this.rowCount > 0) {
          Text(`${this.rowCount} 条`)
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.text_tertiary'))
        }
      }
      .width('100%')
    }
    .width('100%')
  }

  /** 列表内的占位（加载/空/错误），不走 StateView 的居中布局 */
  @Builder
  hint(text: string) {
    Text(text)
      .fontSize(FontSize.BODY)
      .fontColor($r('app.color.text_secondary'))
      .textAlign(TextAlign.Center)
      .width('100%')
      .padding({ top: 48, bottom: 48, left: Space.XL, right: Space.XL })
  }

  build() {
    Column() {
      List({ scroller: this.scroller }) {
        // 顶部让位 + 搜索栏都放进滚动内容：静止时在顶部模糊条下方，滚动时钻到条下面
        ListItem() {
          Column()
            .width('100%')
            .height(this.embedded ? Space.SM : this.metrics.topInsetVp + Layout.TOP_BAR_H)
        }

        // 搜索栏恒常渲染：这是本功能的唯一入口，不能只在"有结果"时才出现
        ListItem() {
          this.searchHeader()
        }
        .padding({ left: Space.LG, right: Space.LG, bottom: Space.SM })

        if (this.loading) {
          ListItem() {
            StateView({ kind: 'loading' })
          }
        } else if (this.errMsg.length > 0) {
          ListItem() {
            StateView({
              kind: 'error',
              message: this.errMsg,
              failKind: this.failKind,
              actionText: '重试',
              onAction: () => {
                this.runCompare();
              }
            })
          }
        } else if (!this.searched) {
          ListItem() {
            this.hint('输入饰品名后点「比价」，一次看清两个平台的差价')
          }
        } else if (this.rowCount === 0) {
          ListItem() {
            this.hint(`两边都没有匹配「${this.keyword}」的在售`)
          }
        } else {
          LazyForEach(this.ds, (row: CompareRow, index: number) => {
            ListItem() {
              CompareRowView({ row: row })
            }
            .padding({ left: Space.LG, right: Space.LG, top: Space.XS, bottom: Space.XS })
          }, (row: CompareRow, index: number) => `${index}:${row.name}`)
        }

        // 底部留白做占位 item，不要用 List().padding({bottom})（会在底部留出灰带）
        ListItem() {
          Column()
            .width('100%')
            .height(this.metrics.bottomInsetVp + 88)
        }
      }
      .width('100%')
      .height('100%')
      .cachedCount(5)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      // 滚动容器自己扩展进状态栏区域，内容才能滚到状态栏后面被标题栏模糊
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
  }
}
