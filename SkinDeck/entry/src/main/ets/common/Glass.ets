/**
 * Glass.ets — 手动玻璃外观：材质不可用时的统一兜底
 * 提供 sectionTitle（@Builder 全局函数）与 GlassPanel（@ComponentV2 容器组件）。
 */

import { Space, Radius, Glass, FontSize } from './Theme';

/**
 * 分区小标题（18fp 标题 / 14fp 正文 / 12fp 辅助）
 * 全局 @Builder 函数只传值参数，调用形式：sectionTitle('文案')
 */
@Builder
export function sectionTitle(text: string) {
  Text(text)
    .fontSize(FontSize.SUBTITLE)
    .fontWeight(FontWeight.Medium)
    .fontColor($r('app.color.text_primary'))
    .margin({ bottom: Space.SM })
}

/**
 * 半透明磨砂面板：半透明底 + 磨砂 + 0.5vp 高光描边 + 柔和投影。
 *
 * 用组件而不是带 content 参数的 @Builder 函数：
 *   全局 @Builder 函数里写 `content();` 会报
 *   "10905204 'content();' does not meet UI component syntax"。
 *   正确做法是 @ComponentV2 + @BuilderParam（见下），调用处用尾随闭包传内容。
 *
 * 用法：
 *   GlassPanel({ isDark: false, effectsOn: true }) {
 *     Text('内容')
 *   }
 */
@ComponentV2
export struct GlassPanel {
  @Param isDark: boolean = false;
  @Param effectsOn: boolean = true;
  @Require @BuilderParam content: () => void;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(Space.MD)
    .backgroundColor(this.effectsOn ? Glass.panel(this.isDark) : $r('app.color.surface_bg'))
    .backgroundBlurStyle(this.effectsOn ? BlurStyle.COMPONENT_ULTRA_THICK : BlurStyle.NONE,
      { scale: 0.85 })
    .border({
      width: 0.5,
      color: this.effectsOn ? Glass.border(this.isDark) : $r('app.color.divider')
    })
    .borderRadius(Radius.LG)
    .shadow(this.effectsOn ? Glass.shadow() : { radius: 0, color: '#00000000' })
  }
}
