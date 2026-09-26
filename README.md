# 比比辣卜

## 有需要和想法还有bug什么的直接issue
HarmonyOS NEXT 上的 CS2（CS:GO）饰品行情工具。工程名 SkinDeck，包名 `com.skindeck.point`。

## 这个 App 干什么

买饰品要在网易BUFF 和悠悠有品之间来回切：一边看价、一边翻库存、还得自己算磨损和手续费。这个 App 把这几件事放在一起。

- **行情**：按平台（网易BUFF / 悠悠有品）、按游戏（CS2、DOTA2、RUST、军团要塞2）看饰品列表，支持搜索、排序、下拉刷新和翻页，可以直接加自选。
- **比价**：输入一个饰品名，两个平台各查一次，按款式和磨损配对后列出差价，告诉你在哪边买更划算。里面的「自选」栏是自己关注的饰品，可以记成本价，看当前盈亏和涨跌。
- **库存**：填自己的 SteamID 就能把 CS2 库存拉下来看，带图标、名称、磨损、品质和是否可交易。
- **工具**：磨损换算（float 换算成外观等级和区间位置）、挂刀比例（算掉 Steam 手续费之后的净收益）、租金收益（年化和回本天数）。
- **我的**：登录状态管理、深浅色、界面效果开关。

点进任意饰品能看详情：两个平台的当前最低在售、成交价走势、区间最低最高均价，也能直接跳去两个平台的网页。

## 怎么用起来

平台数据来自官方网页接口，不需要自己申请 key，但两点要注意：

- 悠悠有品的搜索和比价需要先在 App 里打开它的网页登录一次（登录态存在网页容器里）。
- Steam 库存接口只读公开库存；库存设成私密会取不到。国内网络访问 Steam 通常要自备代理，代理怎么开由你自己决定。

## 构建

用 DevEco Studio 打开工程目录就能构建（首次打开会自动补 hvigor 依赖）。命令行：

```powershell
Remove-Item -Recurse -Force entry\build
$env:DEVECO_SDK_HOME = "<DevEco>\sdk"
& "<DevEco>\tools\node\node.exe" "<DevEco>\tools\hvigor\bin\hvigorw.js" `
  --mode module -p product=default assembleHap --no-daemon
```

`<DevEco>` 指 DevEco Studio 的安装目录，产物在 `entry\build\default\outputs\default\` 下。

工程里不带签名材料，所以这样构出来的是未签名的包，装不到设备上。要装机先在 DevEco 里生成一次签名：File → Project Structure → Signing Configs → 勾选 Automatically generate signature，之后重新构建会输出 `entry-default-signed.hap`：

```powershell
hdc install -r entry\build\default\outputs\default\entry-default-signed.hap
hdc shell "aa start -a EntryAbility -b com.skindeck.point"
```

`dist\entry-default-unsigned.hap` 是一份预先构好的产物，同样是未签名的，要装也得先签名。

## 工程结构

```
AppScope/            应用级配置：包名、版本、图标、应用名
entry/               主模块
  src/main/ets/
    pages/           首页外壳、详情页、网页容器、设置页
    views/           五个页签 + 详情/自选/比价等子视图
    components/      通用组件（卡片、状态占位、输入框、隐藏网页容器…）
    data/            取数层：BuffProvider / UuProvider / SteamProvider / MarketService
    datasource/      列表数据源
    state/           全局状态类（窗口度量、设置、自选、登录态、页签意图）
    model/           数据类型与错误分型
    common/          主题 token、导航、日志、沉浸式窗口
  src/main/resources/ 颜色、字符串、图标、路由表
tools/               两个离线校验脚本（比价配对、库存解析），不依赖设备
dist/                预先构好的未签名产物（要自己签名才能安装）
```

`build/`、`.hvigor/`、`oh_modules/` 是构建缓存和中间产物，没有一起打包，首次构建会自动生成。

## 改动备忘

- 应用名在 `entry/src/main/resources/base/element/string.json` 的 `app_name`，图标是 `entry/src/main/resources/base/media/app_icon.png`（打包后会归一化成 512×512）。
- 改包名（`AppScope/app.json5` 的 `bundleName`）之后要重新做一次自动签名，否则构建会停在签名这一步。换包名等于装了一个新应用，原来的数据和网页登录态都不会跟过来。
- 改过比价配对或库存解析之后，跑一下 `tools\` 里的校验脚本：

```powershell
node tools\verify_compare_pairing.js
node tools\verify_steam_parse.js
```
