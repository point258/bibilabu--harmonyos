/**
 * 比价配对逻辑的离线校验（不需要设备）。
 *
 * 配对是纯算法，但它出错的表现很像"对方平台没有这件货"或"价格离谱但说得通"，
 * 容易被当成接口问题去查。把它做成断言：改配对逻辑时先跑这个，再去设备上验。
 *
 * 跑法：
 *   & "<DevEco Studio>\tools\node\node.exe" tools\verify_compare_pairing.js
 *
 * 本文件的算法与 `entry/src/main/ets/data/MarketService.ets` 里的
 * `toHalfWidth / normWear / wearFromName / wearOf / pairKey / indexByName` 逐行等价。
 * 改了那边记得同步这里（它是副本，不是被引用的实现）。
 *
 * 键必须同时含"款式"和"磨损"：只按款式配对、再取该款式里最便宜的一条当代表，
 * 会出现"名字是崭新出厂、价格却是战痕累累"的行；而磨损文本全角/半角不统一时，
 * 磨损后缀剥不掉、键根本不同，一件都配不上，全变成"仅 BUFF 有货"。
 */

const WEAR_CN = ['崭新出厂', '略有磨损', '久经沙场', '破损不堪', '战痕累累'];
const WEAR_EN = ['factory new', 'minimal wear', 'field-tested', 'well-worn', 'battle-scarred'];

const toHalfWidth = (s) => s.split('（').join('(').split('）').join(')').split('｜').join('|');

function normWear(raw) {
  const s = toHalfWidth(raw).replace(/\s+/g, '').toLowerCase();
  if (s.length === 0) return '';
  for (let i = 0; i < WEAR_EN.length; i++) if (s === WEAR_EN[i].replace(/\s+/g, '')) return WEAR_CN[i];
  for (let i = 0; i < WEAR_CN.length; i++) if (s === WEAR_CN[i]) return WEAR_CN[i];
  return s;
}

function wearFromName(name) {
  const s = toHalfWidth(name);
  const end = s.lastIndexOf(')');
  if (end < 0) return '';
  const start = s.lastIndexOf('(', end);
  if (start < 0) return '';
  const w = normWear(s.substring(start + 1, end));
  return WEAR_CN.indexOf(w) >= 0 ? w : '';
}

const wearOf = (it) => normWear(it.exterior) || wearFromName(it.name);

// —— 对照：旧算法 ——
function baseName(name) {
  const idx = name.indexOf('(');
  const core = idx > 0 ? name.substring(0, idx) : name;
  return core.replace(/\s+/g, '').toLowerCase();
}

// —— 现实现 ——
function pairKey(it) {
  const s = toHalfWidth(it.name);
  const wear = wearOf(it);
  let base = s;
  if (wearFromName(it.name).length > 0) {
    const end = s.lastIndexOf(')');
    const start = end < 0 ? -1 : s.lastIndexOf('(', end);
    if (start >= 0) base = s.substring(0, start);
  }
  return `${base.replace(/\s+/g, '').toLowerCase()}|${wear}`;
}

function indexBy(items, keyFn) {
  const m = new Map();
  for (const it of items) {
    const k = keyFn(it);
    if (k.length === 0) continue;
    const ex = m.get(k);
    if (ex === undefined) m.set(k, it);
    else if ((it.sellPriceCent ?? Infinity) < (ex.sellPriceCent ?? Infinity)) m.set(k, it);
  }
  return m;
}

function run(label, keyFn, bs, us) {
  console.log(`\n===== ${label} =====`);
  const bm = indexBy(bs, keyFn), um = indexBy(us, keyFn);
  const keys = [...bm.keys(), ...[...um.keys()].filter((k) => !bm.has(k))];
  for (const k of keys) {
    const b = bm.get(k), u = um.get(k);
    const bp = b ? b.sellPriceCent : null, up = u ? u.sellPriceCent : null;
    const bWear = b ? (wearOf(b) || '(无)') : '—';
    const uWear = u ? (wearOf(u) || '(无)') : '—';
    let diff = '—';
    if (bp !== null && up !== null) diff = (((bp - up) / Math.min(bp, up)) * 100).toFixed(1) + '%';
    console.log(`  key=${k}`);
    console.log(`    BUFF  ${b ? b.name : '—'}   [磨损=${bWear}]`);
    console.log(`    UU    ${u ? u.name : '—'}   [磨损=${uWear}]`);
    console.log(`    价差 ${diff}`);
  }
}

// 样本取自设备截图（金额换算成"分"）
const buffItems = [
  { name: '蝴蝶刀（★） | 森林 DDPAT (崭新出厂)', exterior: '崭新出厂', sellPriceCent: 529950 },
  { name: '蝴蝶刀（★） | 传说 (战痕累累)',        exterior: '战痕累累', sellPriceCent: 330000 },
  { name: '蝴蝶刀（★） | 狩猎网格 (崭新出厂)',    exterior: '崭新出厂', sellPriceCent: 469900 },
];
const uuFull = [
  { name: '蝴蝶刀（★）| 森林 DDPAT（战痕累累）', exterior: '', sellPriceCent: 281600 },
  { name: '蝴蝶刀（★）| 森林 DDPAT（崭新出厂）', exterior: '', sellPriceCent: 531000 },
  { name: '蝴蝶刀（★）| 传说（崭新出厂）',       exterior: '', sellPriceCent: 616849 },
  { name: '蝴蝶刀（★）| 狩猎网格（战痕累累）',   exterior: '', sellPriceCent: 279800 },
  { name: '蝴蝶刀（★）| 狩猎网格（崭新出厂）',   exterior: '', sellPriceCent: 474000 },
];
const uuHalf = [
  { name: '蝴蝶刀（★） | 森林 DDPAT (战痕累累)', exterior: '', sellPriceCent: 281600 },
  { name: '蝴蝶刀（★） | 森林 DDPAT (崭新出厂)', exterior: '', sellPriceCent: 531000 },
  { name: '蝴蝶刀（★） | 传说 (崭新出厂)',       exterior: '', sellPriceCent: 616849 },
  { name: '蝴蝶刀（★） | 狩猎网格 (战痕累累)',   exterior: '', sellPriceCent: 279800 },
  { name: '蝴蝶刀（★） | 狩猎网格 (崭新出厂)',   exterior: '', sellPriceCent: 474000 },
];

run('旧键 × UU 用全角括号 → 一件都配不上（"只有 BUFF 有货"的来源）',
  (it) => baseName(it.name), buffItems, uuFull);
run('旧键 × UU 用半角括号 → 配上了，但拿"战痕累累"的价去比"崭新出厂"',
  (it) => baseName(it.name), buffItems, uuHalf);
run('新键 × UU 用半角括号 → 同档才配对，价差回到正常量级', pairKey, buffItems, uuHalf);

let failed = 0;
const assert = (cond, msg) => {
  if (!cond) failed++;
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${msg}`);
};
console.log('\n===== 断言 =====');
assert(baseName('蝴蝶刀（★） | 森林 DDPAT (崭新出厂)')
  === baseName('蝴蝶刀（★） | 森林 DDPAT (战痕累累)'),
  '旧键把不同磨损合并成同一键（这就是 bug 的根源）');
assert(pairKey(buffItems[0]) !== pairKey(uuHalf[0]), '新键把不同磨损分开了');
assert(pairKey(buffItems[0]) === pairKey(uuHalf[1]), '新键把半角写法的同一档配上了');
assert(pairKey(buffItems[0]) === pairKey(uuFull[1]), '新键把全角写法的同一档配上了');
assert(pairKey({ name: '蝴蝶刀（★）| 自动化', exterior: '久经沙场', sellPriceCent: 1 })
  .indexOf('蝴蝶刀(★)|自动化') === 0,
  '名字里没有磨损时不会把 "(★)" 误当磨损剥掉');
assert(pairKey({ name: '印花 | ngiN（闪亮）| 2018年伦敦锦标赛赛', exterior: '', sellPriceCent: 1 })
  .indexOf('|') > 0,
  '无磨损品类照样能配对');

console.log(failed === 0 ? '\n全部通过' : `\n有 ${failed} 条断言失败`);
process.exit(failed === 0 ? 0 : 1);
