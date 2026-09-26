/**
 * ResultPanel.ets — 工具箱的"输出栏"
 *
 * 约定：
 *   1. 结果只来自 @Param，父组件按下「确定」后一次性写入，不存在"边输入边算"的歧义；
 *   2. 输入不合法时也走同一个面板（ok=false），给出明确原因，而不是把上一次结果留在屏上；
 *   3. 不用 @Builder 按值参数承载结果：参数会被固化，结果区不会刷新。
 */

import { FontSize, Icons, Radius, Space } from '../common/Theme';

@ComponentV2
export struct ResultPanel {
  /** 是否计算成功 */
  @Require @Param ok: boolean;
  /** 主结论（一行大字） */
  @Require @Param headline: string;
  /** 明细行 */
  @Require @Param lines: string[];
  /** 面板标题 */
  @Param title: string = '计算结果';

  build() {
    Column({ space: Space.SM }) {
      Row({ space: Space.SM }) {
        SymbolGlyph(Icons.info)
          .fontSize(16)
          .fontColor([this.ok ? $r('app.color.brand_primary') : $r('app.color.warn_fg')])
        Text(this.title)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.ok ? '计算完成' : '输入有误')
          .fontSize(FontSize.CAPTION)
          .fontColor(this.ok ? $r('app.color.brand_primary') : $r('app.color.warn_fg'))
          .backgroundColor(this.ok ? $r('app.color.brand_soft') : $r('app.color.warn_bg'))
          .borderRadius(Radius.SM)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      }
      .width('100%')

      Text(this.headline)
        .fontSize(FontSize.TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.ok ? $r('app.color.text_primary') : $r('app.color.warn_fg'))
        .width('100%')

      ForEach(this.lines, (line: string, index: number) => {
        Text(line)
          .fontSize(FontSize.BODY)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(22)
          .width('100%')
      }, (line: string, index: number) => `${index}:${line}`)
    }
    .width('100%')
    .padding(Space.MD)
    .backgroundColor($r('app.color.surface_sunken'))
    .borderRadius(Radius.MD)
    .border({ width: 0.5, color: $r('app.color.divider') })
    .alignItems(HorizontalAlign.Start)
  }
}
