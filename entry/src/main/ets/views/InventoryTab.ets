/**
 * InventoryTab.ets — 「库存」页
 *
 * 用 Steam 公开库存接口展示自己的 CS2 库存（无需 API key，前提是库存公开）。
 * 设计语言与其余页签保持一致：同样的留白/圆角/描边/字号 token、
 * 顶部让位放在滚动内容的首项、底部留白做占位 item、四态占位复用 StateView。
 *
 * 不做自动轮询：Steam 侧有频率限制，而且国内网络需要代理，
 *    所以只在"进入页面且还没数据"和用户点「读取库存」时才真正请求。
 */

import { AppError, FailKind } from '../model/Types';
import { SteamProvider, SteamInvItem, SteamInventory } from '../data/SteamProvider';
import { SteamState, connectSteam } from '../state/SteamState';
import { WindowMetrics, connectWindowMetrics } from '../state/WindowMetrics';
import { StateView } from '../components/StateView';
import { FontSize, Icons, Layout, Radius, Space } from '../common/Theme';
import { sectionTitle } from '../common/Glass';
import { Logger } from '../common/Logger';

const TAG: string = 'InventoryTab';

@ComponentV2
export struct InventoryTab {
  @Local steam: SteamState = connectSteam();
  @Local metrics: WindowMetrics = connectWindowMetrics();

  @Local inputText: string = '';
  @Local items: SteamInvItem[] = [];
  @Local totalCount: number = 0;
  @Local loading: boolean = false;
  /** 是否成功取过一次（用来区分"还没取"和"取到了但真的没东西"） */
  @Local loaded: boolean = false;
  @Local errMsg: string = '';
  @Local failKind: FailKind = FailKind.UNAVAILABLE;

  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    // 只把上次填过的 ID 回填到输入框，**不自动请求**：
    // Steam 社区站按 IP 限流（同一网络下多打几次会返回 429），
    // 每次切页签都自动拉一次会把额度烧光，所以取数一律由用户点「读取库存」触发。
    this.inputText = this.steam.input;
  }

  private async load(): Promise<void> {
    const raw: string = this.inputText.trim();
    if (raw.length === 0) {
      this.failKind = FailKind.UNAVAILABLE;
      this.errMsg = '先填写 SteamID64、自定义 ID 或个人资料链接';
      return;
    }
    this.loading = true;
    this.errMsg = '';
    try {
      const id: string = await SteamProvider.resolveSteamId(raw);
      this.steam.save(id, raw);
      const inv: SteamInventory = await SteamProvider.fetchInventory(id);
      this.items = inv.items;
      this.totalCount = inv.totalCount;
      this.loaded = true;
      Logger.i(TAG, `库存读取完成：${inv.items.length} 项`);
    } catch (e) {
      const err: AppError = e instanceof AppError
        ? e : new AppError(FailKind.NETWORK, '读取库存失败');
      this.errMsg = err.message;
      this.failKind = err.kind;
      this.items = [];
      this.totalCount = 0;
    } finally {
      this.loading = false;
    }
  }

  // -------------------------------------------------------------------------
  // 视图
  // -------------------------------------------------------------------------

  /** 账号卡：输入 + 读取按钮 + 代理提醒（与其它页的卡片同一套描边/圆角） */
  @Builder
  accountCard() {
    Column({ space: Space.MD }) {
      Column({ space: Space.XS }) {
        Text('Steam 账号')
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        TextInput({
          text: this.inputText,
          placeholder: 'SteamID64 / 自定义 ID / 个人资料链接'
        })
          .fontSize(FontSize.BODY)
          .height(44)
          .backgroundColor($r('app.color.surface_sunken'))
          .borderRadius(Radius.SM)
          .onChange((v: string) => {
            this.inputText = v;
          })
          .onSubmit(() => {
            this.load();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row({ space: Space.MD }) {
        Button('读取库存')
          .layoutWeight(1)
          .height(40)
          .type(ButtonType.Capsule)
          .backgroundColor($r('app.color.brand_primary'))
          .fontColor($r('app.color.brand_on'))
          .enabled(!this.loading)
          .onClick(() => {
            this.load();
          })
        if (this.steam.steamId.length > 0) {
          Button('清空')
            .height(40)
            .type(ButtonType.Capsule)
            .backgroundColor($r('app.color.tag_bg'))
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => {
              this.steam.clear();
              this.inputText = '';
              this.items = [];
              this.totalCount = 0;
              this.loaded = false;
              this.errMsg = '';
            })
        }
      }
      .width('100%')

      Text(this.steam.steamId.length > 0
        ? `已绑定：${this.steam.steamId}`
        : '只读取你公开的库存列表，不涉及账号密码，也不做任何修改操作')
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
    }
    .width('100%')
    .padding(Space.MD)
    .backgroundColor($r('app.color.surface_bg'))
    .borderRadius(Radius.MD)
    .border({ width: 0.5, color: $r('app.color.divider') })
  }

  @Builder
  summaryRow() {
    Row({ space: Space.SM }) {
      Text(`库存 ${this.totalCount} 件`)
        .fontSize(FontSize.SUBTITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      if (this.items.length > 0 && this.items.length < this.totalCount) {
        Text(`已载入 ${this.items.length} 项`)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.text_tertiary'))
      }
      Blank()
      if (this.loading) {
        LoadingProgress().width(18).height(18)
      } else if (this.steam.steamId.length > 0) {
        SymbolGlyph(Icons.refresh)
          .fontSize(18)
          .fontColor([$r('app.color.brand_primary')])
          .onClick(() => {
            this.load();
          })
      }
    }
    .width('100%')
    .padding({ left: Space.LG, right: Space.LG, top: Space.SM, bottom: Space.SM })
  }

  @Builder
  row(item: SteamInvItem) {
    Row({ space: Space.MD }) {
      Stack() {
        if (item.iconUrl.length > 0) {
          Image(item.iconUrl)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .interpolation(ImageInterpolation.Medium)
        }
      }
      .width(56)
      .height(56)
      .borderRadius(Radius.MD)
      .backgroundColor($r('app.color.surface_sunken'))
      .clip(true)

      Column({ space: Space.XS }) {
        Text(item.name.length > 0 ? item.name : item.marketName)
          .fontSize(FontSize.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row({ space: Space.SM }) {
          if (item.exterior.length > 0) {
            Text(item.exterior)
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.tag_fg'))
              .backgroundColor($r('app.color.tag_bg'))
              .borderRadius(Radius.SM)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          }
          if (item.rarity.length > 0) {
            Text(item.rarity)
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.text_tertiary'))
          }
          if (!item.tradable) {
            Text('不可交易')
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.warn_fg'))
              .backgroundColor($r('app.color.warn_bg'))
              .borderRadius(Radius.SM)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (item.amount > 1) {
        Text(`×${item.amount}`)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.tag_bg'))
          .borderRadius(Radius.SM)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      }
    }
    .width('100%')
    .padding(Space.MD)
    .backgroundColor($r('app.color.surface_bg'))
    .borderRadius(Radius.MD)
    .border({ width: 0.5, color: $r('app.color.divider') })
  }

  build() {
    List({ scroller: this.scroller }) {
      // 顶部让位放在滚动内容里：滚动时内容能钻到顶部模糊条下面
      ListItem() {
        Column()
          .width('100%')
          .height(this.metrics.topInsetVp + Layout.TOP_BAR_H)
      }

      ListItem() {
        Column({ space: Space.MD }) {
          sectionTitle('我的库存')
          this.accountCard()
          Text('库存接口来自 Steam 社区公开数据；国内网络通常需要自备代理。' +
            '只支持公开库存，私密库存会返回 403。')
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .padding({ left: Space.LG, right: Space.LG, top: Space.SM })

      if (this.loading && this.items.length === 0) {
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
              this.load();
            }
          })
        }
      } else if (this.items.length === 0) {
        ListItem() {
          StateView({
            kind: 'empty',
            message: this.loaded
              ? '这个账号下没有可展示的 CS2 库存物品'
              : (this.steam.steamId.length > 0
                ? '点上面的「读取库存」把库存拉下来（Steam 有限流，不会自动刷新）'
                : '填上你的 SteamID，点「读取库存」把库存拉下来')
          })
        }
      } else {
        ListItem() {
          this.summaryRow()
        }
        ForEach(this.items, (item: SteamInvItem) => {
          ListItem() {
            this.row(item)
          }
          .padding({ left: Space.LG, right: Space.LG, top: Space.XS, bottom: Space.XS })
        }, (item: SteamInvItem) => item.assetId)
      }

      // 底部留白做占位 item（不要用 List().padding({bottom})，会露出底色灰带）
      ListItem() {
        Column()
          .width('100%')
          .height(this.metrics.bottomInsetVp + 88)
      }
    }
    .width('100%')
    .height('100%')
    .cachedCount(6)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    // 滚动容器自己扩展进状态栏区域，内容才能滚到状态栏后面被标题栏模糊
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
