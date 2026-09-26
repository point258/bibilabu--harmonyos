/**
 * PageHeader.ets — 子页（详情/网页/设置）统一页头
 *
 * 为什么子页要自绘页头、不用 NavDestination 默认标题栏：
 *   在 `setWindowLayoutFullScreen(true)` 的常驻全屏窗口里，推入的 NavDestination 默认
 *   标题栏不会正确避开状态栏，导致标题和返回按钮顶到状态栏。
 *   这里自己画：背景从屏幕顶端铺下来（和状态栏同一块面），标题/返回按钮落在状态栏下方。
 */

import { WindowMetrics, connectWindowMetrics } from '../state/WindowMetrics';
import { Nav } from '../common/Nav';
import { FontSize, Space } from '../common/Theme';

@ComponentV2
export struct PageHeader {
  @Require @Param title: string;
  @Local metrics: WindowMetrics = connectWindowMetrics();

  build() {
    Column() {
      // 状态栏占位：让标题/返回按钮落在状态栏下方，而背景从屏幕顶端铺下来
      Blank().height(this.metrics.topInsetVp)

      Row({ space: Space.SM }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([$r('app.color.text_primary')])
          .onClick(() => {
            Nav.back();
          })
        Text(this.title)
          .fontSize(FontSize.TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        // 右侧配重，让标题视觉居中
        Blank().width(24)
      }
      .width('100%')
      .height(48)
      .padding({ left: Space.MD, right: Space.MD })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
