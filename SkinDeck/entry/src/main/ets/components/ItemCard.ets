/**
 * 行情列表行。
 * 列表行内不做整行磨砂（磨砂只给浮在上面的少数元素），因此这里只做纯色卡片 + 细描边。
 */

import { ItemSummary, Platform, PlatformMeta } from '../model/Types';
import { ParseUtil } from '../data/ParseUtil';
import { WatchlistState } from '../state/WatchlistState';
import { FontSize, Icons, PriceColor, Radius, Space } from '../common/Theme';

@ComponentV2
export struct ItemCard {
  /** @Require 保证构造处必须传入，无需本地默认值 */
  @Require @Param item: ItemSummary;
  /**
   * 直接持有自选状态，而不是由父组件算好一个 boolean 传进来。
   *
   * 列表项跑在 LazyForEach 里，父组件重渲染时已存在的 item 不会被重新执行，
   * 传进来的 boolean 会永久停在加入前的值，点了星标图标也不变。
   * 这里在 build 里读 watch.contains(...)，读的是 @ObservedV2 的 @Trace items，
   * 依赖被登记到 ItemCard 自己身上，任何一处改动都会让本行精确重渲染。
   */
  @Require @Param watch: WatchlistState;
  @Event onTap: () => void = () => {
  };
  @Event onToggleWatch: () => void = () => {
  };

  private watched(): boolean {
    return this.watch.contains(this.item.platform, this.item.goodsId);
  }

  private platformBadgeColor(): Resource {
    return this.item.platform === Platform.BUFF
      ? $r('app.color.brand_primary') : $r('app.color.price_down');
  }

  build() {
    Row({ space: Space.MD }) {
      /*
       * "进详情"的点击面只覆盖左侧信息区，星标是它的兄弟节点而不是子节点。
       * 若把 onClick(onTap) 挂在最外层 Row 上、星标又是它的后代，
       * 点星标会连带触发进详情，一次点击就跳走，也没法连续收藏。
       */
      Row({ space: Space.MD }) {
        // 缩略图（缺图时用底色占位，避免布局跳动）
        Stack() {
          if (this.item.iconUrl.length > 0) {
            Image(this.item.iconUrl)
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
          Text(this.item.name.length > 0 ? this.item.name : '未知饰品')
            .fontSize(FontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Row({ space: Space.SM }) {
            Text(PlatformMeta.shortLabel(this.item.platform))
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.brand_on'))
              .backgroundColor(this.platformBadgeColor())
              .borderRadius(Radius.SM)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })

            if (this.item.exterior.length > 0) {
              Text(this.item.exterior)
                .fontSize(FontSize.CAPTION)
                .fontColor($r('app.color.tag_fg'))
                .backgroundColor($r('app.color.tag_bg'))
                .borderRadius(Radius.SM)
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            }

            if (this.item.sellNum !== null) {
              Text(`在售 ${this.item.sellNum}`)
                .fontSize(FontSize.CAPTION)
                .fontColor($r('app.color.text_tertiary'))
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .onClick(() => {
        this.onTap();
      })

      Column({ space: Space.XS }) {
        Text(ParseUtil.centToYuan(this.item.sellPriceCent))
          .fontSize(FontSize.SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))

        Text(ParseUtil.pctText(this.item.deltaPct))
          .fontSize(FontSize.CAPTION)
          .fontColor(PriceColor.ofPct(this.item.deltaPct))

        SymbolGlyph(this.watched() ? Icons.watchlistFill : Icons.watchlist)
          .fontSize(20)
          .fontColor([this.watched()
            ? $r('app.color.price_up') : $r('app.color.text_tertiary')])
          .padding(4)
          .onClick(() => {
            this.onToggleWatch();
          })
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding(Space.MD)
    .backgroundColor($r('app.color.surface_bg'))
    .borderRadius(Radius.MD)
    .border({ width: 0.5, color: $r('app.color.divider') })
  }
}
