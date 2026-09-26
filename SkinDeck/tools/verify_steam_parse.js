/**
 * verify_steam_parse.js — 离线校验 SteamProvider.parseInventory 的解析逻辑。
 *
 * 库存接口返回 `{assets, descriptions}` 两份数据，必须按 classid_instanceid 关联才能拿到
 * 名字、图标、磨损。这段关联一旦写错，表现是"列表全是空名字"或"少了一半物品"，在设备上
 * 不容易一眼看出，所以做成断言。
 *
 * 夹具是按真实响应结构合成的样本；这里锁定"关联 + 标签提取 + 图标拼接 + 数量"这几条
 * 容易写错的规则。
 *
 * 运行：& "<DevEco Studio>\tools\node\node.exe" tools\verify_steam_parse.js
 */

const fs = require('fs');
const path = require('path');

// ---- 与 SteamProvider.ets 保持一致的实现（改一处要同步另一处）----------------

function tagOf(tags, category) {
  if (tags === undefined) return '';
  for (const t of tags) {
    if (t.category === category || t.internal_name === category) {
      return t.localized_tag_name ?? '';
    }
  }
  return '';
}

function iconUrlOf(iconUrl) {
  if (iconUrl.length === 0) return '';
  if (iconUrl.indexOf('http') === 0) return iconUrl;
  return `https://community.cloudflare.steamstatic.com/economy/image/${iconUrl}`;
}

function parseInventory(text) {
  const raw = JSON.parse(text);
  if (raw.success !== 1 && raw.success !== undefined) {
    throw new Error('Steam 未返回库存数据');
  }
  const descOf = new Map();
  const descs = raw.descriptions ?? [];
  for (const d of descs) {
    descOf.set(`${d.classid ?? ''}_${d.instanceid ?? ''}`, d);
  }
  const assets = raw.assets ?? [];
  const items = [];
  for (const a of assets) {
    const d = descOf.get(`${a.classid ?? ''}_${a.instanceid ?? ''}`);
    if (d === undefined) continue;   // 关联不上就跳过（宁可少一件也不要空名字）
    const amount = Number.parseInt(a.amount ?? '1', 10);
    items.push({
      assetId: `${a.assetid ?? ''}`,
      name: d.name ?? d.market_hash_name ?? '',
      marketName: d.market_hash_name ?? d.name ?? '',
      iconUrl: iconUrlOf(d.icon_url ?? ''),
      amount: Number.isNaN(amount) ? 1 : amount,
      exterior: tagOf(d.tags, 'Exterior'),
      rarity: tagOf(d.tags, 'Rarity'),
      tradable: (d.tradable ?? 0) === 1
    });
  }
  return { totalCount: raw.total_inventory_count ?? items.length, items };
}

// ---- 断言 ------------------------------------------------------------------

let failed = 0;
function check(name, cond, extra) {
  if (cond) {
    console.log(`  ok   ${name}`);
  } else {
    failed++;
    console.log(`  FAIL ${name}${extra !== undefined ? ` -> ${extra}` : ''}`);
  }
}

const file = path.join(__dirname, 'fixtures', 'steam_inventory_sample.json');
const inv = parseInventory(fs.readFileSync(file, 'utf8'));

console.log('Steam 库存解析校验');
check('总件数取服务器字段', inv.totalCount === 5, inv.totalCount);
check('关联不上的 asset 被跳过（4 个 asset → 3 件）', inv.items.length === 3, inv.items.length);

const tec9 = inv.items.find((i) => i.assetId === 'A1');
check('A1 关联到描述', tec9 !== undefined);
check('A1 取中文 name', tec9.name === 'Tec-9 | 蓝爆', tec9.name);
check('A1 marketName 用英文市场名', tec9.marketName === 'Tec-9 | Blue Blast (Minimal Wear)');
check('A1 磨损来自 Exterior 标签', tec9.exterior === '略有磨损', tec9.exterior);
check('A1 品质来自 Rarity 标签', tec9.rarity === '消费级', tec9.rarity);
check('A1 图标补全为完整 URL',
  tec9.iconUrl.indexOf('https://community.cloudflare.steamstatic.com/economy/image/') === 0,
  tec9.iconUrl);
check('A1 tradable=true', tec9.tradable === true);

const ssg = inv.items.find((i) => i.assetId === 'A2');
check('已是绝对地址的图标不再拼接', ssg.iconUrl === 'https://community.cloudflare.steamstatic.com/economy/image/abs',
  ssg.iconUrl);

const sticker = inv.items.find((i) => i.assetId === 'A3');
check('无 Exterior 标签时磨损为空串（不写 undefined）', sticker.exterior === '', JSON.stringify(sticker.exterior));
check('amount 解析为数字 3', sticker.amount === 3, sticker.amount);
check('tradable=0 → false', sticker.tradable === false);

// 空库存：Steam 对没有物品的账号不返回 assets 字段
const empty = parseInventory(JSON.stringify({ success: 1, total_inventory_count: 0 }));
check('空库存不抛异常且为 0 件', empty.items.length === 0 && empty.totalCount === 0);

// 失败响应必须抛错，而不是静默返回空列表
let threw = false;
try {
  parseInventory(JSON.stringify({ success: 2, Error: 'boom' }));
} catch (e) {
  threw = true;
}
check('success!==1 时抛错', threw);

console.log(failed === 0 ? '\n全部通过' : `\n失败 ${failed} 项`);
process.exit(failed === 0 ? 0 : 1);
