/**
 * MineTab.ets — 我的
 * 账号档案（登录态只读探测 + 跳官方网页登录）、设置入口、光感档位快捷切换、
 * 缓存清理、合规声明。
 */

import { Platform, PlatformMeta } from '../model/Types';
import { SessionState, connectSession } from '../state/SessionState';
import { SettingsState, connectSettings } from '../state/SettingsState';
import { MarketService } from '../data/MarketService';
import { SnapshotStore } from '../data/SnapshotStore';
import { MaterialGate, MaterialLevelKey } from '../common/MaterialGate';
import { WindowMetrics, connectWindowMetrics } from '../state/WindowMetrics';
import { FontSize, Icons, Layout, Radius, Space } from '../common/Theme';
import { sectionTitle } from '../common/Glass';
import { Nav } from '../common/Nav';

/** 时间戳 → "9/20 14:30"（模块级函数：struct 内不声明静态方法） */
function timeText(ts: number): string {
  if (ts <= 0) {
    return '—';
  }
  const d: Date = new Date(ts);
  const hh: string = `${d.getHours()}`.padStart(2, '0');
  const mm: string = `${d.getMinutes()}`.padStart(2, '0');
  return `${d.getMonth() + 1}/${d.getDate()} ${hh}:${mm}`;
}

@ComponentV2
export struct MineTab {
  @Local session: SessionState = connectSession();
  @Local settings: SettingsState = connectSettings();
  @Local metrics: WindowMetrics = connectWindowMetrics();
  @Local toast: string = '';
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.session.refreshLoginState();
  }

  private showToast(msg: string): void {
    this.toast = msg;
    setTimeout(() => {
      this.toast = '';
    }, 2000);
  }

  private goLogin(p: Platform): void {
    Nav.toWeb(PlatformMeta.homeUrl(p), `${PlatformMeta.label(p)} 网页登录`, p);
  }

  private levelLabel(k: MaterialLevelKey): string {
    if (k === 'exquisite') {
      return '强';
    }
    if (k === 'gentle') {
      return '均衡';
    }
    if (k === 'smooth') {
      return '弱';
    }
    return '自适应';
  }

  @Builder
  accountCard(p: Platform) {
    Column({ space: Space.SM }) {
      Row({ space: Space.SM }) {
        Text(PlatformMeta.label(p))
          .fontSize(FontSize.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.session.accountOf(p)?.loggedIn === true ? '会话有效' : '未登录')
          .fontSize(FontSize.CAPTION)
          .fontColor(this.session.accountOf(p)?.loggedIn === true
            ? $r('app.color.price_down') : $r('app.color.text_tertiary'))
          .backgroundColor($r('app.color.tag_bg'))
          .borderRadius(Radius.SM)
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
      }
      .width('100%')

      Text(this.session.accountOf(p)?.loggedIn === true
        ? `最近确认：${timeText(this.session.accountOf(p)?.lastCheckTs ?? 0)}`
        : '登录与验证码都在平台官方网页内完成，本应用不接触你的账号密码')
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')

      Row({ space: Space.SM }) {
        Button(this.session.accountOf(p)?.loggedIn === true ? '重新登录' : '去官网登录')
          .fontSize(FontSize.CAPTION)
          .height(32)
          .backgroundColor($r('app.color.brand_primary'))
          .fontColor($r('app.color.brand_on'))
          .type(ButtonType.Capsule)
          .onClick(() => {
            this.goLogin(p);
          })
        if (this.session.accountOf(p)?.loggedIn === true) {
          Button('退出')
            .fontSize(FontSize.CAPTION)
            .height(32)
            .backgroundColor($r('app.color.tag_bg'))
            .fontColor($r('app.color.text_secondary'))
            .type(ButtonType.Capsule)
            .onClick(() => {
              this.session.logout();
              this.showToast('已清除网页会话');
            })
        }
        Blank()
      }
      .width('100%')
    }
    .width('100%')
    .padding(Space.MD)
    .backgroundColor($r('app.color.surface_bg'))
    .borderRadius(Radius.MD)
    .border({ width: 0.5, color: $r('app.color.divider') })
  }

  @Builder
  levelChip(k: MaterialLevelKey, enabled: boolean) {
    Text(this.levelLabel(k))
      .fontSize(FontSize.CAPTION)
      .fontColor(!enabled ? $r('app.color.text_tertiary')
        : (this.settings.materialLevel === k
          ? $r('app.color.brand_on') : $r('app.color.text_secondary')))
      .backgroundColor(this.settings.materialLevel === k && enabled
        ? $r('app.color.brand_primary') : $r('app.color.tag_bg'))
      .borderRadius(Radius.PILL)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .enabled(enabled)
      .onClick(() => {
        if (enabled) {
          this.settings.setMaterialLevel(k);
          MaterialGate.invalidateCache();
        }
      })
  }

  @Builder
  settingRow(label: string, value: string, onTap: () => void) {
    Row({ space: Space.MD }) {
      Text(label)
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text(value)
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.text_tertiary'))
      SymbolGlyph(Icons.chevronRight)
        .fontSize(16)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .height(48)
    .onClick(onTap)
  }

  build() {
    Stack() {
      Scroll(this.scroller) {
        Column({ space: Space.LG }) {
          // 顶部让位放在滚动内容里：滚动时内容能钻到顶部模糊条下面
          Row()
            .width('100%')
            .height(this.metrics.topInsetVp + Layout.TOP_BAR_H - Space.LG)

          sectionTitle('账号')
          this.accountCard(Platform.BUFF)
          this.accountCard(Platform.UU)

          sectionTitle('外观')
          Column({ space: Space.MD }) {
            Row({ space: Space.SM }) {
              Text('沉浸光感档位')
                .fontSize(FontSize.BODY)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text(MaterialGate.supportsImmersive() ? '本机支持' : '本机降级为毛玻璃')
                .fontSize(FontSize.CAPTION)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width('100%')

            Row({ space: Space.SM }) {
              this.levelChip('adaptive', true)
              this.levelChip('exquisite', MaterialGate.supportsExplicitImmersive())
              this.levelChip('gentle', MaterialGate.supportsExplicitImmersive())
              this.levelChip('smooth', true)
            }
            .width('100%')

            this.settingRow('更多设置', '主题 / 取数方式', () => {
              Nav.toSettings();
            })
          }
          .width('100%')
          .padding(Space.MD)
          .backgroundColor($r('app.color.surface_bg'))
          .borderRadius(Radius.MD)
          .border({ width: 0.5, color: $r('app.color.divider') })

          sectionTitle('数据')
          Column({ space: 0 }) {
            this.settingRow('清除行情缓存', '', () => {
              MarketService.clearCache();
              this.showToast('行情缓存已清除');
            })
            Divider().color($r('app.color.divider'))
            this.settingRow('重置价格快照', '', () => {
              SnapshotStore.clear();
              this.showToast('价格快照已重置');
            })
          }
          .width('100%')
          .padding({ left: Space.MD, right: Space.MD })
          .backgroundColor($r('app.color.surface_bg'))
          .borderRadius(Radius.MD)
          .border({ width: 0.5, color: $r('app.color.divider') })

          sectionTitle('关于')
          Column({ space: Space.SM }) {
            Row({ space: Space.SM }) {
              SymbolGlyph(Icons.info)
                .fontSize(18)
                .fontColor([$r('app.color.warn_fg')])
              Text('合规声明')
                .fontSize(FontSize.BODY)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')

            Text('本应用是第三方信息聚合工具，与网易BUFF、悠悠有品官方无任何隶属关系。' +
              '所有登录、下单、支付、发货都在平台官方网页内完成，本应用不代理、不截取、' +
              '不篡改任何交易数据，也不保存你的账号密码。行情数据来自平台网页端公开接口，' +
              '仅供参考。请遵守各平台用户协议。')
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.text_secondary'))
              .lineHeight(20)
              .width('100%')

            Text(`取数方式：${this.settings.fetchChannel === 'bridge'
              ? '网页桥接（隐藏容器同源请求）' : '直连接口'}`)
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
          }
          .width('100%')
          .padding(Space.MD)
          .backgroundColor($r('app.color.surface_bg'))
          .borderRadius(Radius.MD)
          .border({ width: 0.5, color: $r('app.color.divider') })

          Text('比比辣卜 v1.0.0 · HarmonyOS NEXT')
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: Space.MD, bottom: this.metrics.bottomInsetVp + 80 })
        }
        .width('100%')
        .padding(Space.LG)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      // 滚动容器自己扩展进状态栏区域，内容才能滚到状态栏后面被标题栏模糊
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      if (this.toast.length > 0) {
        Column() {
          Text(this.toast)
            .fontSize(FontSize.BODY)
            .fontColor($r('app.color.brand_on'))
            .backgroundColor('#CC000000')
            .borderRadius(Radius.PILL)
            .padding({ left: Space.LG, right: Space.LG, top: Space.SM, bottom: Space.SM })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .padding({ bottom: this.metrics.bottomInsetVp + 96 })
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
  }
}
