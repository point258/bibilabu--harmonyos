/**
 * Nav.ets — 单例导航栈 + 强类型路由参数
 * 路由名用枚举；每路由一对 Param 接口 + 类型守卫；深链/子页统一走这里。
 *
 * 单例不在模块加载期构造：
 *   那会在 import 阶段（UI 上下文尚未就绪）构造 ArkUI 对象。
 *   正确做法是由壳组件在 aboutToAppear 里 attach 它自己 @Local 持有的栈
 *   （组件字段初始化发生在组件构造期，上下文是安全的）。
 */

import { ItemSummary, Platform } from '../model/Types';
import { Logger } from './Logger';

const TAG: string = 'Nav';

export enum RouteName {
  DETAIL = 'detail',
  WEB = 'web',
  SETTINGS = 'settings'
}

export interface DetailRouteParam {
  item: ItemSummary;
}

export interface WebRouteParam {
  url: string;
  title: string;
  platform: Platform;
}

export interface SettingsRouteParam {
  from: string;
}

export class Nav {
  /** 由壳组件注入；未注入时兜底惰性创建，保证 push 调用不至于崩 */
  private static stackRef: NavPathStack | undefined = undefined;

  /** 壳组件 aboutToAppear 中调用 */
  static attach(stack: NavPathStack): void {
    Nav.stackRef = stack;
    Logger.d(TAG, '导航栈已挂载');
  }

  static stack(): NavPathStack {
    if (Nav.stackRef === undefined) {
      Logger.w(TAG, '导航栈尚未挂载，已惰性创建兜底实例');
      Nav.stackRef = new NavPathStack();
    }
    return Nav.stackRef;
  }

  static toDetail(item: ItemSummary): void {
    const p: DetailRouteParam = { item: item };
    Nav.stack().pushPathByName(RouteName.DETAIL, p);
  }

  static toWeb(url: string, title: string, platform: Platform): void {
    const p: WebRouteParam = { url: url, title: title, platform: platform };
    Nav.stack().pushPathByName(RouteName.WEB, p);
  }

  static toSettings(): void {
    const p: SettingsRouteParam = { from: 'mine' };
    Nav.stack().pushPathByName(RouteName.SETTINGS, p);
  }

  static back(): void {
    Nav.stack().pop();
  }

  static clear(): void {
    Nav.stack().clear();
  }
}
