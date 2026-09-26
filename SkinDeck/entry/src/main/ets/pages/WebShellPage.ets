/**
 * WebShellPage.ets — 平台官方网页容器
 *
 * 定位（合规红线）：这里承载平台官方网页，用户的登录、验证码、下单、支付、发货
 * 全部在平台自己的页面里完成。本应用不做任何注入、不修改页面、不拦截表单，
 * 只在页面加载完成后**只读地**探测一次登录态，用于"我的"页显示会话状态。
 *
 * 外链处理：非 http/https 协议（支付宝/微信等）交给系统打开，避免 WebView 内白屏。
 */

import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { PlatformMeta } from '../model/Types';
import { WebSessionBridge } from '../data/WebSessionBridge';
import { SessionState, connectSession } from '../state/SessionState';
import { WindowMetrics, connectWindowMetrics } from '../state/WindowMetrics';
import { WebRouteParam } from '../common/Nav';
import { PageHeader } from '../components/PageHeader';
import { FontSize, Icons, Radius, Space } from '../common/Theme';
import { Logger } from '../common/Logger';

const TAG: string = 'WebShellPage';

@Builder
export function WebShellPageBuilder(param: WebRouteParam) {
  WebShellPage({ param: param })
}

@ComponentV2
struct WebShellPage {
  @Require @Param param: WebRouteParam;
  @Local session: SessionState = connectSession();
  @Local metrics: WindowMetrics = connectWindowMetrics();

  @Local progress: number = 0;
  @Local loading: boolean = true;
  @Local failed: boolean = false;
  @Local loggedIn: boolean = false;

  private controller: webview.WebviewController = new webview.WebviewController();

  private onPageFinished(): void {
    this.loading = false;
    this.failed = false;
    this.loggedIn = WebSessionBridge.isLoggedIn(this.param.platform);
    if (this.loggedIn) {
      // 只登记"登录态存在"，不保存任何凭据
      this.session.upsertAccount(this.param.platform,
        PlatformMeta.shortLabel(this.param.platform));
    }
  }

  /** 非 http(s) 协议交给系统（支付/唤起 App），返回 true 表示已被本应用处理 */
  private handleUrl(url: string): boolean {
    if (url.length === 0) {
      return false;
    }
    const isWeb: boolean = url.startsWith('http://') || url.startsWith('https://')
      || url.startsWith('about:') || url.startsWith('data:');
    if (isWeb) {
      return false;
    }
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.openLink(url).catch((e: Object) => {
        Logger.err(TAG, `openLink ${url}`, e);
      });
    } catch (e) {
      Logger.err(TAG, 'handleUrl', e);
    }
    return true;
  }

  /**
   * 不要把这个 @Builder 命名为 toolbar —— `toolbar` 是 CustomComponent 上已有的
   * 属性方法签名 (value: CustomBuilder) => CommonAttribute，同名会导致
   * "Property 'toolbar' in type 'WebShellPage' is not assignable to the same property
   *  in base type 'CustomComponent'"。
   */
  @Builder
  sessionBar() {
    Row({ space: Space.MD }) {
      SymbolGlyph(Icons.refresh)
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
        .onClick(() => {
          this.controller.refresh();
        })
      Text(this.loggedIn ? '会话有效' : '未检测到登录态')
        .fontSize(FontSize.CAPTION)
        .fontColor(this.loggedIn
          ? $r('app.color.price_down') : $r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.tag_bg'))
        .borderRadius(Radius.SM)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      Blank()
      Text('登录后返回即可看到行情数据')
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .padding({ left: Space.LG, right: Space.LG, top: Space.SM, bottom: Space.SM })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: this.param.title })

        if (this.progress > 0 && this.progress < 100) {
          // type 是 Progress 的**构造参数**，不能链式调用（否则报
          // Property 'type' does not exist on type 'ProgressAttribute'）
          Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
            .height(2)
            .color($r('app.color.brand_primary'))
        }
        this.sessionBar()

        Stack() {
          Web({ src: this.param.url, controller: this.controller })
            .domStorageAccess(true)
            .databaseAccess(true)
            .fileAccess(true)
            .imageAccess(true)
            .zoomAccess(false)
            .darkMode(WebDarkMode.Auto)
            .forceDarkAccess(false)
            .mixedMode(MixedMode.None)
            .horizontalScrollBarAccess(false)
            .verticalScrollBarAccess(false)
            .onPageBegin(() => {
              this.loading = true;
              this.failed = false;
            })
            .onPageEnd(() => {
              this.onPageFinished();
            })
            .onProgressChange((event) => {
              this.progress = event.newProgress;
            })
            .onErrorReceive(() => {
              this.loading = false;
              this.failed = true;
            })
            .onLoadIntercept((event) => {
              return this.handleUrl(event.data.getRequestUrl());
            })
            .width('100%')
            .height('100%')

          if (this.loading) {
            Column() {
              LoadingProgress().width(36).height(36)
                .color($r('app.color.brand_primary'))
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.page_bg'))
            .hitTestBehavior(HitTestMode.None)
          } else if (this.failed) {
            Column({ space: Space.MD }) {
              Text('页面加载失败')
                .fontSize(FontSize.BODY)
                .fontColor($r('app.color.text_secondary'))
              Button('重新加载')
                .type(ButtonType.Capsule)
                .backgroundColor($r('app.color.brand_primary'))
                .fontColor($r('app.color.brand_on'))
                .onClick(() => {
                  this.failed = false;
                  this.loading = true;
                  this.controller.refresh();
                })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.page_bg'))
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.metrics.bottomInsetVp })
      .backgroundColor($r('app.color.page_bg'))
    }
    // 全屏窗口里默认标题栏会顶到状态栏，改由 PageHeader 自绘
    .hideTitleBar(true)
    .onBackPressed(() => {
      // 网页还能后退就后退，否则交给路由
      if (this.controller.accessBackward()) {
        this.controller.backward();
        return true;
      }
      return false;
    })
    .backgroundColor($r('app.color.page_bg'))
  }
}
