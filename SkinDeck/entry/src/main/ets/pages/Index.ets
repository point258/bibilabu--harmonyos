/**
 * Index.ets — 应用主壳
 *
 * 顶部用 HDS 原生标题栏（`systemMaterialEffect` = 原生光感模糊），不要再自绘模糊条：
 *   - 自绘的 `backgroundBlurStyle` 在跨层结构（Stack 里的 HdsTabs 子树）里采不到列表内容，
 *     表现出来就是一块半透明白块、没有任何模糊；
 *   - HDS 标题栏的 `systemMaterialEffect` 是真正的原生光感模糊，且恒常存在。
 *
 * 两个关键配置：
 *   1. `avoidLayoutSafeArea: true` —— 标题栏背景面延伸到状态栏后面，模糊从屏幕顶端连续；
 *      **根部不要再加 padding({top})**，让位交给各页签滚动内容的首个占位。
 *   2. 根部**不要** `expandSafeArea(TOP)` —— 它会波及 NavDestination 子页，导致详情页
 *      标题栏顶到状态栏。沉浸交给各页签自己的 `expandSafeArea(TOP)`。
 */

import { HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController,
  HdsTabsFloatingStyle, HdsTabsBackgroundStyle, ScrollEffectType } from '@kit.UIDesignKit';
import { MaterialGate } from '../common/MaterialGate';
import { SettingsState, connectSettings } from '../state/SettingsState';
import { ShellState, connectShell } from '../state/ShellState';
import { WindowMetrics, connectWindowMetrics, applyBreakpoint } from '../state/WindowMetrics';
import { MarketTab } from '../views/MarketTab';
import { CompareTab } from '../views/CompareTab';
import { InventoryTab } from '../views/InventoryTab';
import { ToolboxTab } from '../views/ToolboxTab';
import { MineTab } from '../views/MineTab';
import { WebBridgeHost } from '../components/WebBridgeHost';
import { DetailPageBuilder } from './DetailPage';
import { WebShellPageBuilder } from './WebShellPage';
import { SettingsPageBuilder } from './SettingsPage';
import { DetailRouteParam, Nav, RouteName, SettingsRouteParam, WebRouteParam } from '../common/Nav';
import { FontSize, Icons, Layout } from '../common/Theme';
import { Logger } from '../common/Logger';

const TAG: string = 'Index';
const HDS_SYSCAP: string = 'SystemCapability.UIDesign.HDSComponent.Core';

/** 页签描述（单对象参数：@Builder 传对象是按引用语义，最稳） */
interface TabSpec {
  index: number;
  label: string;
  icon: Resource;
  iconActive: Resource;
}

/** HDS 能力探测：放在模块级函数里，保证不会因为探测本身抛异常而拖垮首帧 */
function detectHds(): boolean {
  try {
    return canIUse(HDS_SYSCAP);
  } catch (e) {
    return false;
  }
}

/**
 * 渐变遮罩参数：必须落成有显式类型的常量，直接内联字面量会触发
 * arkts-no-untyped-obj-literals（字段类型是 HdsTabsBackgroundStyle）。
 * maskColor 官方默认 #99000000 会在浮层铺黑矩形，故显式透明。
 */
const TAB_GRADIENT_MASK: HdsTabsBackgroundStyle = {
  maskColor: '#00000000',
  maskHeight: 92
};

@Entry
@ComponentV2
struct Index {
  @Local metrics: WindowMetrics = connectWindowMetrics();
  @Local settings: SettingsState = connectSettings();
  /** 页签意图（子页可以写：例如详情页点「跨平台比价」直接切到比价页） */
  @Local shell: ShellState = connectShell();

  @Local currentIndex: number = 0;
  @Local hdsOk: boolean = detectHds();

  /** 组件字段构造（上下文安全），aboutToAppear 里交给 Nav 供子页 push */
  private navStack: NavPathStack = new NavPathStack();
  private tabController: HdsTabsController = new HdsTabsController();

  aboutToAppear(): void {
    Nav.attach(this.navStack);
    this.currentIndex = this.shell.tabIndex;
    Logger.i(TAG, `启动外壳: hds=${this.hdsOk} ` +
      `topInset=${this.metrics.topInsetVp} bottomInset=${this.metrics.bottomInsetVp}`);
  }

  /**
   * 任何页面写 shell.tabIndex 即切页签。
   * HdsTabs 的 index 是"支持状态变量动态修改"的构造参数（HDS SDK 文档原文），
   * 改 currentIndex 就会触发 onChange，无需再调 controller。
   */
  @Monitor('shell.tabIndex')
  onShellTabChanged(): void {
    if (this.currentIndex !== this.shell.tabIndex) {
      this.currentIndex = this.shell.tabIndex;
    }
  }

  /** 用户点底栏：本地索引与全局意图保持一致，否则两处会打架 */
  private onTabPicked(index: number): void {
    this.currentIndex = index;
    this.shell.tabIndex = index;
  }

  // -------------------------------------------------------------------------
  // 页签
  // -------------------------------------------------------------------------

  @Builder
  tabItem(spec: TabSpec) {
    Column({ space: 2 }) {
      SymbolGlyph(this.currentIndex === spec.index ? spec.iconActive : spec.icon)
        .fontSize(22)
        .fontColor([this.currentIndex === spec.index
          ? $r('app.color.brand_primary') : $r('app.color.text_tertiary')])
      Text(spec.label)
        .fontSize(FontSize.CAPTION)
        .fontColor(this.currentIndex === spec.index
          ? $r('app.color.brand_primary') : $r('app.color.text_tertiary'))
    }
    .width('100%')
    .height(Layout.TAB_BAR_H)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 五个页签内容。
   * 这里不加顶部让位 padding：让位在各页签滚动内容的首个占位里做，
   * 内容才能在滚动时钻到标题栏下面被光感模糊；加在这里等于把内容永久挡住。
   */
  @Builder
  tabContents() {
    TabContent() {
      MarketTab()
    }
    .tabBar(this.tabItem({
      index: 0, label: '行情', icon: Icons.market, iconActive: Icons.market
    }))

    TabContent() {
      CompareTab()
    }
    .tabBar(this.tabItem({
      index: 1, label: '比价', icon: Icons.compare, iconActive: Icons.compare
    }))

    TabContent() {
      InventoryTab()
    }
    .tabBar(this.tabItem({
      index: 2, label: '库存', icon: Icons.inventory, iconActive: Icons.inventoryFill
    }))

    TabContent() {
      ToolboxTab()
    }
    .tabBar(this.tabItem({
      index: 3, label: '工具', icon: Icons.toolbox, iconActive: Icons.toolbox
    }))

    TabContent() {
      MineTab()
    }
    .tabBar(this.tabItem({
      index: 4, label: '我的', icon: Icons.mine, iconActive: Icons.mineFill
    }))
  }

  @Builder
  pageMap(name: string, param: Object) {
    if (name === RouteName.DETAIL) {
      DetailPageBuilder(param as DetailRouteParam)
    } else if (name === RouteName.WEB) {
      WebShellPageBuilder(param as WebRouteParam)
    } else if (name === RouteName.SETTINGS) {
      SettingsPageBuilder(param as SettingsRouteParam)
    }
  }

  /**
   * 悬浮底栏样式。
   * 字段名必须与 SDK 严格一致（本机 HdsTabsFloatingStyle 没有 edgeHighlightColor）；
   * 且形参是 Optional<T>，必须先在本地声明成类型常量再传。
   */
  private hdsFloatingStyle(): HdsTabsFloatingStyle {
    const style: HdsTabsFloatingStyle = {
      barBottomMargin: this.metrics.bottomInsetVp > 0 ? this.metrics.bottomInsetVp : 24,
      barSideMargin: 16,
      gradientMask: TAB_GRADIENT_MASK,
      thermoCtrl: true,
      lightColor: $r('app.color.brand_primary'),
      systemMaterialEffect: this.settings.uiEffectsOn
        ? MaterialGate.systemMaterialEffect() : undefined
    };
    return style;
  }

  // -------------------------------------------------------------------------
  // 外壳 A：HDS 原生标题栏（光感模糊）+ 悬浮底栏
  // -------------------------------------------------------------------------

  @Builder
  hdsShell() {
    HdsNavigation(this.navStack) {
      HdsTabs({ controller: this.tabController, index: this.currentIndex }) {
        this.tabContents()
      }
      // 悬浮三条件缺一不可
      .barPosition(BarPosition.End)
      .vertical(false)
      .barOverlap(true)
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.NONE)
      .barFloatingStyle(this.hdsFloatingStyle())
      .onChange((index: number) => {
        this.onTabPicked(index);
      })
    }
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar({
      // 标题栏背景面延伸到状态栏后面：模糊从屏幕顶端连续（这就是"沉浸"）
      avoidLayoutSafeArea: true,
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: $r('app.color.hds_title_bar_scrolled_bg'),
            blurRadius: 24
          }
        },
        // 原生光感模糊：恒常存在，内容钻到标题栏下面就被它模糊
        systemMaterialEffect: this.settings.uiEffectsOn
          ? MaterialGate.systemMaterialEffect() : undefined
      },
      content: {
        title: { mainTitle: $r('app.string.app_name') }
      }
    })
    .hideBackButton(true)
    .navDestination(this.pageMap)
    .backgroundColor($r('app.color.page_bg'))
    // 根部不要加 expandSafeArea(TOP)：会波及 NavDestination 子页，导致详情页标题栏顶到
    // 状态栏。沉浸交给各页签自己的 expandSafeArea。
  }

  // -------------------------------------------------------------------------
  // 外壳 B：原生 Navigation + Tabs（设备无 HDS 时的保底渲染路径）
  // -------------------------------------------------------------------------

  @Builder
  plainShell() {
    Navigation(this.navStack) {
      Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
        this.tabContents()
      }
      .barMode(BarMode.Fixed)
      .barHeight(Layout.TAB_BAR_H + 12)
      .scrollable(false)
      .divider({ strokeWidth: 0 })
      .backgroundColor($r('app.color.page_bg'))
      .onChange((index: number) => {
        this.onTabPicked(index);
      })
    }
    .mode(NavigationMode.Stack)
    .title('比比辣卜')
    .titleMode(NavigationTitleMode.Mini)
    .navDestination(this.pageMap)
    .backgroundColor($r('app.color.page_bg'))
  }

  build() {
    Stack() {
      if (this.hdsOk) {
        this.hdsShell()
      } else {
        this.plainShell()
      }

      // 隐藏的网页取数容器（默认不挂载 Web，仅 bridge 通道真正取数时才创建）
      WebBridgeHost()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .onAreaChange((oldArea: Area, newArea: Area) => {
      applyBreakpoint(Number(newArea.width));
    })
  }
}
