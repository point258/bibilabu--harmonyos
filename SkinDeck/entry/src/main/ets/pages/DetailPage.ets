/**
 * DetailPage.ets — 饰品详情
 * 内容：当前价、成交价走势、近 7 日成交量、在售数、加入自选、跳平台网页。
 * 通过 NavDestination 承载，标题栏沿用系统导航（返回手势自动可用）。
 */

import { AppError, FailKind, ItemSummary, Platform, PlatformMeta, TrendData } from '../model/Types';
import { MarketService } from '../data/MarketService';
import { SettingsState, connectSettings } from '../state/SettingsState';
import { WatchlistState, connectWatchlist } from '../state/WatchlistState';
import { requestCompare } from '../state/ShellState';
import { WindowMetrics, connectWindowMetrics } from '../state/WindowMetrics';
import { TrendChart } from '../components/TrendChart';
import { StateView } from '../components/StateView';
import { PageHeader } from '../components/PageHeader';
import { ParseUtil } from '../data/ParseUtil';
import { DetailRouteParam, Nav } from '../common/Nav';
import { FontSize, PriceColor, Radius, Space } from '../common/Theme';
import { sectionTitle } from '../common/Glass';

@Builder
export function DetailPageBuilder(param: DetailRouteParam) {
  DetailPage({ param: param })
}

@ComponentV2
struct DetailPage {
  @Require @Param param: DetailRouteParam;
  @Local settings: SettingsState = connectSettings();
  @Local watch: WatchlistState = connectWatchlist();
  @Local metrics: WindowMetrics = connectWindowMetrics();

  @Local trend: TrendData | undefined = undefined;
  @Local currentCent: number | null = null;
  @Local loading: boolean = true;
  @Local errMsg: string = '';
  @Local failKind: FailKind = FailKind.UNAVAILABLE;

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errMsg = '';
    const item: ItemSummary = this.param.item;
    try {
      this.currentCent = await MarketService.quote(item, this.settings.fetchChannel);
      this.trend = await MarketService.trend(item, this.settings.fetchChannel);
    } catch (e) {
      const err: AppError = e instanceof AppError
        ? e : new AppError(FailKind.NETWORK, '加载失败');
      this.errMsg = err.message;
      this.failKind = err.kind;
    } finally {
      this.loading = false;
    }
  }

  private watched(): boolean {
    return this.watch.contains(this.param.item.platform, this.param.item.goodsId);
  }

  private avgCent(): number | null {
    const t: TrendData | undefined = this.trend;
    if (t === undefined || t.points.length === 0) {
      return null;
    }
    let sum: number = 0;
    for (let i = 0; i < t.points.length; i++) {
      sum += t.points[i].priceCent;
    }
    return Math.round(sum / t.points.length);
  }

  @Builder
  statCell(label: string, value: string, colorType: number) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.text_tertiary'))
      Text(value)
        .fontSize(FontSize.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(colorType === 0 ? $r('app.color.text_primary')
          : (colorType > 0 ? $r('app.color.price_up') : $r('app.color.price_down')))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  headerCard() {
    Column({ space: Space.MD }) {
      Row({ space: Space.MD }) {
        Stack() {
          if (this.param.item.iconUrl.length > 0) {
            Image(this.param.item.iconUrl)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
          }
        }
        .width(72)
        .height(72)
        .borderRadius(Radius.LG)
        .backgroundColor($r('app.color.surface_sunken'))
        .clip(true)

        Column({ space: Space.XS }) {
          Text(this.param.item.name)
            .fontSize(FontSize.SUBTITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Row({ space: Space.SM }) {
            Text(PlatformMeta.label(this.param.item.platform))
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.brand_on'))
              .backgroundColor($r('app.color.brand_primary'))
              .borderRadius(Radius.SM)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            if (this.param.item.exterior.length > 0) {
              Text(this.param.item.exterior)
                .fontSize(FontSize.CAPTION)
                .fontColor($r('app.color.tag_fg'))
                .backgroundColor($r('app.color.tag_bg'))
                .borderRadius(Radius.SM)
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            }
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Row({ space: Space.MD }) {
        Column({ space: 2 }) {
          Text('当前最低在售')
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.text_tertiary'))
          Text(ParseUtil.centToYuan(this.currentCent))
            .fontSize(24)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Text(ParseUtil.pctText(this.param.item.deltaPct))
          .fontSize(FontSize.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(PriceColor.ofPct(this.param.item.deltaPct))
      }
      .width('100%')
    }
    .width('100%')
    .padding(Space.MD)
    .backgroundColor($r('app.color.surface_bg'))
    .borderRadius(Radius.LG)
    .border({ width: 0.5, color: $r('app.color.divider') })
  }

  @Builder
  trendCard() {
    Column({ space: Space.SM }) {
      Row() {
        sectionTitle('成交价走势')
        Blank()
        Text(this.trend === undefined
          ? '' : `${this.trend.points.length} 笔成交`)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')

      if (this.trend !== undefined) {
        TrendChart({
          points: this.trend.points,
          minCent: this.trend.minCent,
          maxCent: this.trend.maxCent
        })

        Row({ space: Space.MD }) {
          this.statCell('区间最低', ParseUtil.centToYuan(this.trend.minCent), -1)
          this.statCell('区间最高', ParseUtil.centToYuan(this.trend.maxCent), 1)
          this.statCell('均价', ParseUtil.centToYuan(this.avgCent()), 0)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(Space.MD)
    .backgroundColor($r('app.color.surface_bg'))
    .borderRadius(Radius.LG)
    .border({ width: 0.5, color: $r('app.color.divider') })
  }

  @Builder
  actions() {
    Column({ space: Space.SM }) {
      Button(this.watched() ? '移出自选' : '加入自选')
        .width('100%')
        .height(44)
        .type(ButtonType.Capsule)
        .backgroundColor(this.watched()
          ? $r('app.color.tag_bg') : $r('app.color.brand_primary'))
        .fontColor(this.watched()
          ? $r('app.color.text_secondary') : $r('app.color.brand_on'))
        .onClick(() => {
          this.watch.toggle(this.param.item);
        })

      // 比价入口：详情页是压在壳体上的 NavDestination，
      // 光切页签是看不见的，必须先把它弹掉再切。
      Button('跨平台比价（网易BUFF × 悠悠有品）')
        .width('100%')
        .height(44)
        .type(ButtonType.Capsule)
        .backgroundColor($r('app.color.brand_soft'))
        .fontColor($r('app.color.brand_primary'))
        .fontSize(FontSize.CAPTION)
        .onClick(() => {
          requestCompare(MarketService.compareKeywordOf(this.param.item.name));
          Nav.back();
        })

      Row({ space: Space.SM }) {
        Button('在 BUFF 打开')
          .layoutWeight(1)
          .height(44)
          .type(ButtonType.Capsule)
          .backgroundColor($r('app.color.brand_soft'))
          .fontColor($r('app.color.brand_primary'))
          .fontSize(FontSize.CAPTION)
          .onClick(() => {
            Nav.toWeb(
              PlatformMeta.detailUrl(Platform.BUFF, this.param.item.game,
                this.param.item.goodsId),
              '网易BUFF', Platform.BUFF);
          })
        Button('在悠悠有品打开')
          .layoutWeight(1)
          .height(44)
          .type(ButtonType.Capsule)
          .backgroundColor($r('app.color.brand_soft'))
          .fontColor($r('app.color.brand_primary'))
          .fontSize(FontSize.CAPTION)
          .onClick(() => {
            Nav.toWeb(
              PlatformMeta.detailUrl(Platform.UU, this.param.item.game,
                this.param.item.goodsId),
              '悠悠有品', Platform.UU);
          })
      }
      .width('100%')

      Text('交易、支付与发货均在平台官方网页内完成，本应用不参与交易流程。')
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
    }
    .width('100%')
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: this.param.item.name.length > 0 ? this.param.item.name : '饰品详情' })

        Scroll() {
          Column({ space: Space.LG }) {
            if (this.loading) {
              StateView({ kind: 'loading' })
            } else if (this.errMsg.length > 0) {
              StateView({
                kind: 'error',
                message: this.errMsg,
                failKind: this.failKind,
                actionText: '重试',
                onAction: () => {
                  this.load();
                }
              })
            } else {
              this.headerCard()
              this.trendCard()
              this.actions()
            }
            Blank().height(this.metrics.bottomInsetVp + 24)
          }
          .width('100%')
          .padding(Space.LG)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
    }
    // 全屏窗口里默认标题栏会顶到状态栏，改由 PageHeader 自绘
    .hideTitleBar(true)
    .backgroundColor($r('app.color.page_bg'))
  }
}
