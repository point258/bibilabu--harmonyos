/**
 * StateView.ets — 加载 / 空 / 错误 / 需登录 四态占位
 * 错误分型来自 AppError.kind，UI 按型给不同文案与动作。
 */

import { FailKind } from '../model/Types';
import { Space, FontSize, Icons } from '../common/Theme';

@ComponentV2
export struct StateView {
  /** 'loading' | 'empty' | 'error' */
  @Require @Param kind: string;
  @Param message: string = '';
  @Param failKind: FailKind = FailKind.UNAVAILABLE;
  @Param actionText: string = '';
  @Event onAction: () => void = () => {
  };

  private resolveMessage(): string {
    if (this.message.length > 0) {
      return this.message;
    }
    if (this.kind === 'loading') {
      return '加载中…';
    }
    if (this.failKind === FailKind.TIMEOUT) {
      return '请求超时，请检查网络后重试';
    }
    if (this.failKind === FailKind.NETWORK) {
      return '网络异常，请检查连接';
    }
    if (this.failKind === FailKind.NEED_LOGIN) {
      return '需要先在平台网页端登录';
    }
    if (this.failKind === FailKind.PARSE) {
      return '数据解析失败，接口可能已调整';
    }
    return '暂时拿不到数据';
  }

  private iconOf(): Resource {
    if (this.kind === 'error') {
      return Icons.info;
    }
    return Icons.search;
  }

  build() {
    Column({ space: Space.MD }) {
      if (this.kind === 'loading') {
        LoadingProgress()
          .width(36)
          .height(36)
          .color($r('app.color.brand_primary'))
      } else {
        SymbolGlyph(this.iconOf())
          .fontSize(32)
          .fontColor([$r('app.color.text_tertiary')])
      }

      Text(this.resolveMessage())
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .padding({ left: Space.XL, right: Space.XL })

      if (this.actionText.length > 0) {
        Button(this.actionText)
          .fontSize(FontSize.BODY)
          .backgroundColor($r('app.color.brand_soft'))
          .fontColor($r('app.color.brand_primary'))
          .type(ButtonType.Capsule)
          .onClick(() => {
            this.onAction();
          })
      }
    }
    .width('100%')
    .padding({ top: 72, bottom: 72 })
    .justifyContent(FlexAlign.Center)
  }
}
