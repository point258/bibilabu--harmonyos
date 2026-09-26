/**
 * 「比价」页（容器）。
 *
 * 底部页签为 行情 / 比价 / 库存 / 工具 / 我的，「自选」并入本页，页内分两栏：
 *   固定顶部（让位 + 分栏）  ← 与首页「网易BUFF / 悠悠有品」那一栏同款 chip
 *   ├─ 比价   → ComparePane
 *   └─ 自选   → WatchlistPane
 *
 * 几个约定：
 *  1. 分栏做成固定头，不放进滚动内容。首页的平台/排序 chip 是筛选器，滚走无所谓；
 *     这里是切页面，滚走就没法切了。
 *  2. 比价排第一位并作为默认：详情页的「跨平台比价」会直接落到这里，进来第一眼就该看到搜索框。
 *  3. 用 if/else 惰性挂载，而不是两份都建好再切可见性：这样在比价页时自选不会去批量取价。
 *     切回来会重建，单品取价有缓存兜着。
 *  4. 顶部让位由本容器统一负责，两个 pane 传 `embedded: true`，各自只留一点间距。
 */

import { ShellState, connectShell } from '../state/ShellState';
import { FontSize, Layout, Radius, Space } from '../common/Theme';
import { WindowMetrics, connectWindowMetrics } from '../state/WindowMetrics';
import { WatchlistPane } from './WatchlistPane';
import { ComparePane } from './ComparePane';
import { Logger } from '../common/Logger';

const TAG: string = 'CompareTab';

/** 0 = 比价，1 = 自选 */
const SEG_COMPARE: number = 0;
const SEG_WATCH: number = 1;

@ComponentV2
export struct CompareTab {
  @Local metrics: WindowMetrics = connectWindowMetrics();
  @Local shell: ShellState = connectShell();
  @Local seg: number = SEG_COMPARE;

  aboutToAppear(): void {
    Logger.i(TAG, '比价页（比价/自选 二合一）aboutToAppear');
  }

  /**
   * 详情页点了「跨平台比价」：ShellState 写入关键词 + 自增 nonce。
   * 这里只负责把分栏切到「比价」；关键词由 ComparePane 自己消费
   * （它挂在 if 分支下，切过来时 aboutToAppear 会补一次消费）。
   */
  @Monitor('shell.compareNonce')
  onCompareRequested(): void {
    if (this.seg !== SEG_COMPARE) {
      this.seg = SEG_COMPARE;
    }
  }

  /** 与首页 MarketTab.chip 完全同款，保证设计语言一致 */
  @Builder
  segChip(index: number, label: string) {
    Text(label)
      .fontSize(FontSize.CAPTION)
      .fontColor(this.seg === index
        ? $r('app.color.brand_on') : $r('app.color.text_secondary'))
      .backgroundColor(this.seg === index
        ? $r('app.color.brand_primary') : $r('app.color.tag_bg'))
      .borderRadius(Radius.PILL)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .onClick(() => {
        this.seg = index;
      })
  }

  build() {
    Column() {
      // 顶部让位 + 分栏（固定，不随内容滚动）
      Column({ space: Space.SM }) {
        Row()
          .width('100%')
          .height(this.metrics.topInsetVp + Layout.TOP_BAR_H)
        Row({ space: Space.SM }) {
          this.segChip(SEG_COMPARE, '比价')
          this.segChip(SEG_WATCH, '自选')
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: Space.LG, right: Space.LG, bottom: Space.SM })
      .backgroundColor($r('app.color.page_bg'))

      if (this.seg === SEG_COMPARE) {
        ComparePane({ embedded: true })
      } else {
        WatchlistPane({ embedded: true })
      }
    }
    .width('100%')
    .height('100%')
  }
}
