/**
 * LabeledInput.ets — 带标签的输入框（工具箱用）
 *
 * 用"组件"而不是带参数的 @Builder：
 *   @Builder 的按值参数会被固化，参数变化**不会**刷新 @Builder 内部的 UI
 *   （工具箱的结果区会停在第一次渲染的文案上，输入新数值也不变）。
 *   组件走 @Param，父组件重渲染时参数正常下发，输入框内容也能被程序清空。
 */

import { FontSize, Radius, Space } from '../common/Theme';

@ComponentV2
export struct LabeledInput {
  @Require @Param label: string;
  @Require @Param value: string;
  @Param placeholder: string = '';
  /** 单位/后缀提示，如「元」「天」 */
  @Param suffix: string = '';
  @Event onValue: (v: string) => void = () => {
  };

  build() {
    Column({ space: Space.XS }) {
      Text(this.label)
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Row({ space: Space.SM }) {
        TextInput({ text: this.value, placeholder: this.placeholder })
          .type(InputType.NUMBER_DECIMAL)
          .fontSize(FontSize.BODY)
          .height(44)
          .backgroundColor($r('app.color.surface_sunken'))
          .borderRadius(Radius.SM)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.onValue(v);
          })
        if (this.suffix.length > 0) {
          Text(this.suffix)
            .fontSize(FontSize.BODY)
            .fontColor($r('app.color.text_tertiary'))
        }
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
