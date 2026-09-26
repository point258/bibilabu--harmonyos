/**
 * MarketTab.ets — 行情主列表
 * 功能：平台切换 / 品类切换 / 排序 / 关键词搜索 / 下拉刷新 / 触底分页 /
 *       自选快捷操作 / 四态占位 / 登录引导。
 * 性能：LazyForEach + BasicDataSource 增量追加，cachedCount 取 Feed 经验值 5。
 */

import { AppError, FailKind, Game, ItemSummary, MarketQuery, PageResult,
  Platform, PlatformMeta, SortBy } from '../model/Types';
import { MarketService } from '../data/MarketService';
import { BasicDataSource } from '../datasource/BasicDataSource';
import { SettingsState, connectSettings } from '../state/SettingsState';
import { WatchlistState, connectWatchlist } from '../state/WatchlistState';
import { WindowMetrics, connectWindowMetrics } from '../state/WindowMetrics';
import { ItemCard } from '../components/ItemCard';
import { StateView } from '../components/StateView';
import { FontSize, Icons, Layout, Radius, Space } from '../common/Theme';
import { Nav } from '../common/Nav';
import { Logger } from '../common/Logger';

const TAG: string = 'MarketTab';
const PAGE_SIZE: number = 20;

/** 异常统一转 AppError（模块级函数：struct 内不声明静态方法） */
function toAppError(e: Object): AppError {
  if (e instanceof AppError) {
    return e;
  }
  if (e instanceof Error) {
    return new AppError(FailKind.NETWORK, e.message);
  }
  return new AppError(FailKind.UNAVAILABLE, '取数失败');
}

@ComponentV2
export struct MarketTab {
  @Local settings: SettingsState = connectSettings();
  @Local watch: WatchlistState = connectWatchlist();
  @Local metrics: WindowMetrics = connectWindowMetrics();

  @Local platform: Platform = Platform.BUFF;
  @Local game: Game = Game.CSGO;
  @Local sortBy: SortBy = SortBy.DEFAULT;
  @Local keyword: string = '';

  @Local loading: boolean = true;
  @Local refreshing: boolean = false;
  @Local loadingMore: boolean = false;
  @Local itemCount: number = 0;
  @Local errorMsg: string = '';
  @Local failKind: FailKind = FailKind.UNAVAILABLE;

  private ds: BasicDataSource<ItemSummary> = new BasicDataSource<ItemSummary>();
  private pageNum: number = 1;
  private hasMore: boolean = true;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    // 启动排查锚点：hilog 里搜 SkinDeck 即可看到每个页签是否成功构建
    Logger.i(TAG, 'MarketTab aboutToAppear');
    this.reload();
  }

  private currentQuery(page: number): MarketQuery {
    const q: MarketQuery = {
      platform: this.platform,
      game: this.game,
      keyword: this.keyword.trim(),
      sortBy: this.sortBy,
      pageNum: page,
      pageSize: PAGE_SIZE
    };
    return q;
  }

  /** 首屏 / 刷新：重置分页 */
  private async reload(): Promise<void> {
    this.pageNum = 1;
    this.hasMore = true;
    this.loading = this.itemCount === 0;
    this.errorMsg = '';
    try {
      const res: PageResult = await MarketService.list(
        this.currentQuery(1), this.settings.fetchChannel, false);
      this.ds.replaceData(res.items);
      this.itemCount = res.items.length;
      this.hasMore = res.hasMore;
      this.settings.markRefreshed();
    } catch (e) {
      const err: AppError = toAppError(e);
      this.errorMsg = err.message;
      this.failKind = err.kind;
      if (this.itemCount === 0) {
        this.ds.clear();
      }
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  /** 触底续页 */
  private async loadMore(): Promise<void> {
    if (!this.hasMore || this.loadingMore || this.loading) {
      return;
    }
    this.loadingMore = true;
    try {
      this.pageNum++;
      const res: PageResult = await MarketService.list(
        this.currentQuery(this.pageNum), this.settings.fetchChannel, false);
      this.ds.appendUnique(res.items,
        (it: ItemSummary) => `${it.platform}:${it.goodsId}`);
      this.itemCount = this.ds.totalCount();
      this.hasMore = res.hasMore;
      if (res.items.length === 0) {
        this.hasMore = false;
      }
    } catch (e) {
      this.pageNum--;
      // 续页失败不打断已有内容，静默降级
    } finally {
      this.loadingMore = false;
    }
  }

  private switchPlatform(p: Platform): void {
    if (this.platform === p) {
      return;
    }
    this.platform = p;
    this.ds.clear();
    this.itemCount = 0;
    this.reload();
  }

  private openLogin(): void {
    Nav.toWeb(PlatformMeta.homeUrl(this.platform),
      `${PlatformMeta.label(this.platform)} 网页登录`, this.platform);
  }

  // -------------------------------------------------------------------------
  // 视图
  // -------------------------------------------------------------------------

  @Builder
  chip(label: string, active: boolean, onTap: () => void) {
    Text(label)
      .fontSize(FontSize.CAPTION)
      .fontColor(active ? $r('app.color.brand_on') : $r('app.color.text_secondary'))
      .backgroundColor(active ? $r('app.color.brand_primary') : $r('app.color.tag_bg'))
      .borderRadius(Radius.PILL)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .onClick(onTap)
  }

  @Builder
  filterBar() {
    Column({ space: Space.SM }) {
      // 平台
      Row({ space: Space.SM }) {
        this.chip('网易BUFF', this.platform === Platform.BUFF, () => {
          this.switchPlatform(Platform.BUFF);
        })
        this.chip('悠悠有品', this.platform === Platform.UU, () => {
          this.switchPlatform(Platform.UU);
        })
        Blank()
        Text(this.loading ? '加载中' : `${this.itemCount} 条`)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')

      /*
       * 排序。
       * 原来的"品类"一组（CS2 / DOTA2 / RUST / 军团要塞2）已按需求移除 ——
       * 本应用实际只取 CS2 数据（悠悠有品的市场接口也是按 CS2 走的），
       * 所以 `game` 固定为 Game.CSGO，不再暴露切换入口。
       * 仍然保留 `game` 字段：MarketQuery / provider 都还要用它算 gameId(730)。
       */
      /*
       * 这里不能用 `Scroll` 包：ArkUI 的 `Scroll` 会把"比视口短"的内容居中。
       * 三个 chip 只有 647px、可用宽 1168px，整行会被推到 x=317（平台行是 x=56），
       * 看起来就是没和上面一栏对齐（偏移 = (1168-647)/2 = 260.5）。
       * 用普通 Row 即左对齐，与平台行同一条左边线。
       */
      Row({ space: Space.SM }) {
        this.chip('综合', this.sortBy === SortBy.DEFAULT, () => {
          this.sortBy = SortBy.DEFAULT;
          this.reload();
        })
        this.chip('价格↑', this.sortBy === SortBy.PRICE_ASC, () => {
          this.sortBy = SortBy.PRICE_ASC;
          this.reload();
        })
        this.chip('价格↓', this.sortBy === SortBy.PRICE_DESC, () => {
          this.sortBy = SortBy.PRICE_DESC;
          this.reload();
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: Space.LG, right: Space.LG, top: Space.SM, bottom: Space.SM })
  }

  @Builder
  searchBar() {
    // 外层给左右 16vp：与下方卡片对齐（之前是通栏，视觉上"过长"）
    Column() {
      Row({ space: Space.SM }) {
        SymbolGlyph(Icons.search)
          .fontSize(18)
          .fontColor([$r('app.color.text_tertiary')])
        // placeholder 是 TextInput 的**构造参数**，不是链式属性（写成 .placeholder() 会报
        // Property 'placeholder' does not exist on type 'TextInputAttribute'）
        TextInput({ text: this.keyword, placeholder: '搜索饰品，如 AK-47 | 红线' })
          .placeholderFont({ size: FontSize.BODY })
          .fontSize(FontSize.BODY)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .height(36)
          .layoutWeight(1)
          .enterKeyType(EnterKeyType.Search)
          .onChange((v: string) => {
            this.keyword = v;
          })
          .onSubmit(() => {
            this.reload();
          })
        if (this.keyword.length > 0) {
          SymbolGlyph(Icons.close)
            .fontSize(16)
            .fontColor([$r('app.color.text_tertiary')])
            .onClick(() => {
              this.keyword = '';
              this.reload();
            })
        }
      }
      .width('100%')
      .height(40)
      .padding({ left: Space.MD, right: Space.MD })
      .backgroundColor($r('app.color.surface_sunken'))
      .borderRadius(Radius.PILL)
    }
    .width('100%')
    .padding({ left: Space.LG, right: Space.LG })
  }

  @Builder
  body() {
    if (this.loading && this.itemCount === 0) {
      StateView({ kind: 'loading' })
    } else if (this.errorMsg.length > 0 && this.itemCount === 0) {
      StateView({
        kind: 'error',
        message: this.errorMsg,
        failKind: this.failKind,
        actionText: this.failKind === FailKind.NEED_LOGIN ? '去网页登录' : '重试',
        onAction: () => {
          if (this.failKind === FailKind.NEED_LOGIN) {
            this.openLogin();
          } else {
            this.reload();
          }
        }
      })
    } else if (this.itemCount === 0) {
      StateView({
        kind: 'empty',
        message: this.keyword.length > 0 ? `没有找到「${this.keyword}」` : '当前条件下暂无在售',
        actionText: '刷新',
        onAction: () => {
          this.reload();
        }
      })
    } else {
      List({ scroller: this.scroller }) {
        // 顶部让位做成**首个占位 item**（属于滚动内容）：
        // 静止时首行落在顶部模糊条下方；滚动时这一项会被推上去，
        // 后面的卡片就钻到条下面被模糊了 —— 让位加在容器外就永远做不到这点。
        ListItem() {
          Column()
            .width('100%')
            .height(this.metrics.topInsetVp + Layout.TOP_BAR_H)
        }

        ListItem() {
          Column({ space: Space.SM }) {
            this.searchBar()
            this.filterBar()
          }
          .padding({ bottom: Space.SM })
        }

        LazyForEach(this.ds, (it: ItemSummary) => {
          ListItem() {
            ItemCard({
              item: it,
              watch: this.watch,
              onTap: () => {
                Nav.toDetail(it);
              },
              onToggleWatch: () => {
                this.watch.toggle(it);
              }
            })
          }
          .padding({ left: Space.LG, right: Space.LG, top: Space.XS, bottom: Space.XS })
        }, (it: ItemSummary) => `${it.platform}:${it.goodsId}`)

        if (this.loadingMore) {
          ListItem() {
            Row() {
              LoadingProgress().width(20).height(20)
            }
            .width('100%')
            .height(48)
            .justifyContent(FlexAlign.Center)
          }
        } else if (!this.hasMore) {
          ListItem() {
            Text('没有更多了')
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: Space.MD })
          }
        }

        // 底部留白用"占位 item"实现，**不要**用 List().padding({bottom})
        // —— padding 是裁视口，会在列表底部永久空出一条露出页面底色的灰带，
        //    下拉回弹时那条边界还会跟着动。做成 item 就随内容滚走。
        ListItem() {
          Column()
            .width('100%')
            .height(this.metrics.bottomInsetVp + 88)
        }
      }
      .width('100%')
      .height('100%')
      .cachedCount(5)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onReachEnd(() => {
        this.loadMore();
      })
      // 滚动容器自己扩展进状态栏区域：只给根部加 expandSafeArea 不够，
      //   子级 List 仍会从状态栏下方开始布局，内容永远到不了 y=0，
      //   状态栏那一截就永远是空的、模糊也就无从发生。
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }

  build() {
    Column() {
      Refresh({ refreshing: $$this.refreshing }) {
        this.body()
      }
      .width('100%')
      .height('100%')
      .onRefreshing(() => {
        this.refreshing = true;
        this.reload();
      })
    }
    .width('100%')
    .height('100%')
  }
}
