/**
 * ParseUtil.ets — 网络响应字段的防御式解析工具
 * ArkTS 禁止 any，接口字段一律可选，因此所有取值都走这里，避免各处 NaN/undefined 扩散。
 */

import type { BuffGoodsTag } from '../model/Types';

export class ParseUtil {
  /** "1234.56" → 123456（分）；非法或空返回 null */
  static toCent(raw: string | undefined): number | null {
    if (raw === undefined || raw === null || raw.length === 0) {
      return null;
    }
    const v: number = Number.parseFloat(raw);
    if (Number.isNaN(v) || v <= 0) {
      return null;
    }
    return Math.round(v * 100);
  }

  /** 数字/字符串 → 整数；非法返回 null */
  static toInt(raw: number | string | undefined): number | null {
    if (raw === undefined || raw === null) {
      return null;
    }
    const v: number = typeof raw === 'number' ? raw : Number.parseInt(raw, 10);
    return Number.isNaN(v) ? null : v;
  }

  /** 分 → "¥1,234.56" */
  static centToYuan(cent: number | null): string {
    if (cent === null) {
      return '—';
    }
    const yuan: number = cent / 100;
    const s: string = yuan >= 1000
      ? yuan.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',')
      : yuan.toFixed(2);
    return `¥${s}`;
  }

  /** 涨跌百分比 → "+3.21%" / "-1.08%" / "—" */
  static pctText(pct: number | null): string {
    if (pct === null) {
      return '—';
    }
    const sign: string = pct > 0 ? '+' : '';
    return `${sign}${pct.toFixed(2)}%`;
  }

  /** BUFF tags 里按 category 取展示名 */
  static tagByCategory(tags: BuffGoodsTag[] | undefined, category: string): string {
    if (tags === undefined) {
      return '';
    }
    for (let i = 0; i < tags.length; i++) {
      const t: BuffGoodsTag = tags[i];
      if (t.category === category) {
        return t.localized_name ?? '';
      }
    }
    return '';
  }

  /** internal_name 含关键字的 tag（例如磨损区间） */
  static tagByKeyword(tags: BuffGoodsTag[] | undefined, keyword: string): string {
    if (tags === undefined) {
      return '';
    }
    for (let i = 0; i < tags.length; i++) {
      const t: BuffGoodsTag = tags[i];
      const n: string = t.internal_name ?? '';
      if (n.indexOf(keyword) >= 0) {
        return t.localized_name ?? '';
      }
    }
    return '';
  }

  /** 秒级时间戳统一成毫秒 */
  static toMillis(ts: number | undefined): number {
    if (ts === undefined || ts <= 0) {
      return 0;
    }
    return ts < 100000000000 ? ts * 1000 : ts;
  }
}
