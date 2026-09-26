/**
 * SettingsPage.ets — 设置
 * 外观（深浅色三态 / 光感档位 / 效果开关）、数据源（直连 vs 网页桥接）、
 * 高级（悠悠有品接口路径校准 —— 抓到的真实路径填这里即生效，无需重新打包）。
 */

import { ConfigurationConstant } from '@kit.AbilityKit';
import { FetchChannel } from '../model/Types';
import { SettingsState, connectSettings } from '../state/SettingsState';
import { UuEndpoints } from '../data/UuProvider';
import { MarketService } from '../data/MarketService';
import { MaterialGate, MaterialLevelKey } from '../common/MaterialGate';
import { PageHeader } from '../components/PageHeader';
import { SettingsRouteParam } from '../common/Nav';
import { FontSize, Radius, Space } from '../common/Theme';
import { sectionTitle } from '../common/Glass';

@Builder
export function SettingsPageBuilder(param: SettingsRouteParam) {
  SettingsPage({ param: param })
}

@ComponentV2
struct SettingsPage {
  @Require @Param param: SettingsRouteParam;
  @Local settings: SettingsState = connectSettings();

  @Local listPath: string = '';
  @Local trendPath: string = '';
  @Local detailPath: string = '';
  @Local advancedOpen: boolean = false;
  @Local toast: string = '';

  aboutToAppear(): void {
    this.listPath = UuEndpoints.listPath();
    this.trendPath = UuEndpoints.trendPath();
    this.detailPath = UuEndpoints.detailPath();
  }

  private showToast(msg: string): void {
    this.toast = msg;
    setTimeout(() => {
      this.toast = '';
    }, 1800);
  }

  private levelLabel(k: MaterialLevelKey): string {
    if (k === 'exquisite') {
      return '强（最细腻，耗电）';
    }
    if (k === 'gentle') {
      return '均衡';
    }
    if (k === 'smooth') {
      return '弱（最省电）';
    }
    return '系统自适应';
  }

  private colorModeLabel(): string {
    if (this.settings.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
      return '浅色';
    }
    if (this.settings.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
      return '深色';
    }
    return '跟随系统';
  }

  private channelLabel(): string {
    return this.settings.fetchChannel === FetchChannel.BRIDGE ? '网页桥接' : '直连接口';
  }

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
  pathField(label: string, value: string, onChange: (v: string) => void) {
    Column({ space: Space.XS }) {
      Text(label)
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.text_secondary'))
      TextInput({ text: value })
        .fontSize(FontSize.CAPTION)
        .height(38)
        .backgroundColor($r('app.color.surface_sunken'))
        .borderRadius(Radius.SM)
        .onChange(onChange)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  row(label: string, value: string, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text(value)
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .height(48)
    .onClick(onTap)
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '设置' })

        Stack() {
          Scroll() {
          Column({ space: Space.LG }) {
            sectionTitle('深浅色')
            Column({ space: Space.MD }) {
              Row({ space: Space.SM }) {
                this.chip('跟随系统',
                  this.settings.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET,
                  () => {
                    this.settings.setColorMode(
                      ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET, this.getUIContext()
                        .getHostContext()!);
                  })
                this.chip('浅色',
                  this.settings.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT,
                  () => {
                    this.settings.setColorMode(
                      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT, this.getUIContext()
                        .getHostContext()!);
                  })
                this.chip('深色',
                  this.settings.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK,
                  () => {
                    this.settings.setColorMode(
                      ConfigurationConstant.ColorMode.COLOR_MODE_DARK, this.getUIContext()
                        .getHostContext()!);
                  })
              }
              .width('100%')
              Text(`当前：${this.colorModeLabel()}`)
                .fontSize(FontSize.CAPTION)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
            }
            .width('100%')
            .padding(Space.MD)
            .backgroundColor($r('app.color.surface_bg'))
            .borderRadius(Radius.MD)
            .border({ width: 0.5, color: $r('app.color.divider') })

            sectionTitle('沉浸光感')
            Column({ space: Space.MD }) {
              Text(MaterialGate.supportsImmersive()
                ? '本机支持 HDS 材质'
                : '本机不支持 HDS 材质，将使用毛玻璃降级')
                .fontSize(FontSize.CAPTION)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')

              Row({ space: Space.SM }) {
                this.chip('自适应', this.settings.materialLevel === 'adaptive', () => {
                  this.applyLevel('adaptive');
                })
                this.chip('强', this.settings.materialLevel === 'exquisite', () => {
                  this.applyLevel('exquisite');
                })
                this.chip('均衡', this.settings.materialLevel === 'gentle', () => {
                  this.applyLevel('gentle');
                })
                this.chip('弱', this.settings.materialLevel === 'smooth', () => {
                  this.applyLevel('smooth');
                })
              }
              .width('100%')

              Text(`当前：${this.levelLabel(this.settings.materialLevel)}。` +
                '系统「设置 → 桌面和个性化 → 沉浸光感」的档位也会影响实际渲染，' +
                '系统关闭时会自动落到毛玻璃效果。')
                .fontSize(FontSize.CAPTION)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')

              Row() {
                Text('玻璃与动效效果')
                  .fontSize(FontSize.BODY)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: this.settings.uiEffectsOn })
                  .selectedColor($r('app.color.brand_primary'))
                  .onChange((on: boolean) => {
                    this.settings.setUiEffects(on);
                    MaterialGate.invalidateCache();
                  })
              }
              .width('100%')
            }
            .width('100%')
            .padding(Space.MD)
            .backgroundColor($r('app.color.surface_bg'))
            .borderRadius(Radius.MD)
            .border({ width: 0.5, color: $r('app.color.divider') })

            sectionTitle('数据来源')
            Column({ space: Space.MD }) {
              Row({ space: Space.SM }) {
                this.chip('直连接口', this.settings.fetchChannel === FetchChannel.DIRECT, () => {
                  this.settings.setFetchChannel(FetchChannel.DIRECT);
                  MarketService.clearCache();
                })
                this.chip('网页桥接', this.settings.fetchChannel === FetchChannel.BRIDGE, () => {
                  this.settings.setFetchChannel(FetchChannel.BRIDGE);
                  MarketService.clearCache();
                })
              }
              .width('100%')
              Text('直连：原生 HTTP 复用网页会话，快、省电，适合接口稳定的平台。\n' +
                '网页桥接：把请求交给隐藏的网页容器用同源上下文发起，接口带签名或' +
                '原生直连被拒时更可靠，代价是首次会加载一次页面。')
                .fontSize(FontSize.CAPTION)
                .fontColor($r('app.color.text_tertiary'))
                .lineHeight(19)
                .width('100%')
            }
            .width('100%')
            .padding(Space.MD)
            .backgroundColor($r('app.color.surface_bg'))
            .borderRadius(Radius.MD)
            .border({ width: 0.5, color: $r('app.color.divider') })

            sectionTitle('高级')
            Column({ space: Space.MD }) {
              Row() {
                Text('悠悠有品接口路径校准')
                  .fontSize(FontSize.BODY)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text(this.advancedOpen ? '收起' : '展开')
                  .fontSize(FontSize.CAPTION)
                  .fontColor($r('app.color.brand_primary'))
              }
              .width('100%')
              .onClick(() => {
                this.advancedOpen = !this.advancedOpen;
              })

              Text('悠悠有品的接口路径没有公开文档，这里的默认值是它 PC 网页版实际在用的路径，一般不用改。' +
                '平台改版后如果取不到数据，用代理抓一次真实请求填在这里就能生效（存在本地，不用重新打包）。' +
                '悠悠有品的数据走网页通道，所以上面的「取数通道」设置对它不生效。')
                .fontSize(FontSize.CAPTION)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')

              if (this.advancedOpen) {
                this.pathField('分类浏览路径（POST JSON）', this.listPath, (v: string) => {
                  this.listPath = v;
                })
                this.pathField('搜索路径（带关键词时走它）', this.trendPath, (v: string) => {
                  this.trendPath = v;
                })
                this.pathField('单品详情路径（预留）', this.detailPath, (v: string) => {
                  this.detailPath = v;
                })
                Row({ space: Space.MD }) {
                  Button('恢复默认')
                    .layoutWeight(1)
                    .type(ButtonType.Capsule)
                    .backgroundColor($r('app.color.tag_bg'))
                    .fontColor($r('app.color.text_secondary'))
                    .onClick(() => {
                      this.listPath = UuEndpoints.defaultListPath();
                      this.trendPath = UuEndpoints.defaultTrendPath();
                      this.detailPath = UuEndpoints.defaultDetailPath();
                      UuEndpoints.setListPath(this.listPath);
                      UuEndpoints.setTrendPath(this.trendPath);
                      UuEndpoints.setDetailPath(this.detailPath);
                      this.showToast('已恢复默认路径');
                    })
                  Button('保存')
                    .layoutWeight(1)
                    .type(ButtonType.Capsule)
                    .backgroundColor($r('app.color.brand_primary'))
                    .fontColor($r('app.color.brand_on'))
                    .onClick(() => {
                      UuEndpoints.setListPath(this.listPath);
                      UuEndpoints.setTrendPath(this.trendPath);
                      UuEndpoints.setDetailPath(this.detailPath);
                      MarketService.clearCache();
                      this.showToast('已保存，立即生效');
                    })
                }
                .width('100%')
              }
            }
            .width('100%')
            .padding(Space.MD)
            .backgroundColor($r('app.color.surface_bg'))
            .borderRadius(Radius.MD)
            .border({ width: 0.5, color: $r('app.color.divider') })

            sectionTitle('其它')
            Column({ space: 0 }) {
              this.row('清除行情缓存', '', () => {
                MarketService.clearCache();
                this.showToast('行情缓存已清除');
              })
              Divider().color($r('app.color.divider'))
              this.row('当前取数方式', this.channelLabel(), () => {
              })
            }
            .width('100%')
            .padding({ left: Space.MD, right: Space.MD })
            .backgroundColor($r('app.color.surface_bg'))
            .borderRadius(Radius.MD)
            .border({ width: 0.5, color: $r('app.color.divider') })

            Text('本应用为第三方信息聚合工具，与网易BUFF、悠悠有品官方无隶属关系；' +
              '所有交易行为均在平台官方网页内完成。行情数据来自平台网页端公开接口，仅供参考。')
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.text_tertiary'))
              .lineHeight(19)
              .width('100%')
              .padding({ bottom: Space.XXL })
          }
          .width('100%')
          .padding(Space.LG)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

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
          .padding({ bottom: 96 })
          .hitTestBehavior(HitTestMode.None)
        }
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.page_bg'))
  }

  private applyLevel(k: MaterialLevelKey): void {
    this.settings.setMaterialLevel(k);
    MaterialGate.invalidateCache();
  }
}
