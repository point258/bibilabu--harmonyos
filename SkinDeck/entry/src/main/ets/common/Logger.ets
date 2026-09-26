/**
 * Logger.ets — 统一日志出口
 * 生产规则：hilog 必须带 domain + tag，格式化参数用 %{public}s。
 * Release 下把 MIN_LEVEL 调到 WARN，避免刷日志影响性能。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0A11;

export class Logger {
  private static readonly TAG_PREFIX: string = 'SkinDeck';

  static d(tag: string, msg: string): void {
    hilog.debug(DOMAIN, `${Logger.TAG_PREFIX}.${tag}`, '%{public}s', msg);
  }

  static i(tag: string, msg: string): void {
    hilog.info(DOMAIN, `${Logger.TAG_PREFIX}.${tag}`, '%{public}s', msg);
  }

  static w(tag: string, msg: string): void {
    hilog.warn(DOMAIN, `${Logger.TAG_PREFIX}.${tag}`, '%{public}s', msg);
  }

  static e(tag: string, msg: string): void {
    hilog.error(DOMAIN, `${Logger.TAG_PREFIX}.${tag}`, '%{public}s', msg);
  }

  /** 异常统一转字符串，避免直接拼对象 */
  static err(tag: string, what: string, e: Object): void {
    let detail: string = '';
    if (e instanceof Error) {
      detail = `${e.name}: ${e.message}`;
    } else {
      detail = JSON.stringify(e);
    }
    hilog.error(DOMAIN, `${Logger.TAG_PREFIX}.${tag}`, '%{public}s',
      `${what} -> ${detail}`);
  }
}
