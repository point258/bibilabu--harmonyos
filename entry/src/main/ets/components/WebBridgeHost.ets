/**
 * WebBridgeHost.ets — 隐藏的 ArkWeb 容器（网页上下文取数通道的宿主）
 *
 * 默认不创建 Web（`bridge.enabled === false` 时 if 分支不成立）：
 * 只有真正走 bridge 通道取数时 Web 才会被实例化 —— 既省掉冷启动的 WebView 初始化，
 * 也避免"设备上 ArkWeb 不可用"这类问题在首帧把整棵 UI 树带崩。
 *
 * 布局：外层 1×1、近乎透明、不拦触摸、固定在左上角，绝不参与视觉；
 * 内层 Web 保持 1×1 真实布局（太小会被判定不可见而不加载，所以不能用 0×0）。
 */

import { WebBridge, WebBridgeState, connectWebBridgeState } from '../data/WebBridge';

@ComponentV2
export struct WebBridgeHost {
  @Local bridge: WebBridgeState = connectWebBridgeState();

  build() {
    Stack() {
      if (this.bridge.enabled) {
        Web({ src: this.bridge.src, controller: WebBridge.controller() })
          /*
           * domStorageAccess 必须显式开！
           *   ArkWeb SDK 原文："If this attribute is not explicitly called, the DOM Storage API
           *   permission is disabled by default."
           *   不开的话页面里的 localStorage 是空的：平台前端算出的设备标识（悠悠有品的
           *   WEB_UK / WEB_DEVICE_UK）写不进去，随后带上去的 uk 就是空的，
           *   平台会把整个客户端判成非法，回一句极具误导性的
           *   {"code":85100,"msg":"当前app版本过低，请前往更新"}。
           */
          .domStorageAccess(true)
          .javaScriptProxy({
            object: WebBridge.proxy(),
            name: 'skinBridge',
            methodList: ['onResult', 'onError'],
            controller: WebBridge.controller()
          })
          .onPageEnd((event) => {
            WebBridge.markPageEnd(event.url);
          })
          // 导航式取数拿不到状态码（runJavaScript 只回正文），由这里把真实码回传
          .onHttpErrorReceive((event) => {
            try {
              WebBridge.markHttpStatus(event.request.getRequestUrl(),
                event.response.getResponseCode());
            } catch (e) {
              // 事件字段取不到就只当没发生，正文侧仍会给出结果
            }
          })
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
      }
    }
    .width(1)
    .height(1)
    .opacity(0.01)
    .hitTestBehavior(HitTestMode.None)
    .position({ x: 0, y: 0 })
  }
}
