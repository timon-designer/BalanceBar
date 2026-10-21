# BalanceBar 交接说明（给 WorkBuddy）

> 这份文档是**长期基础上下文**（项目结构、接口、构建、坑），更新频率低。
> 当前要做什么请读 `TASK-current.md`（每次只含一个任务，做完归档到 `TASK-done/`）。
> 接手方只需读这两个文件，不需要看任何对话。

## 1. 这是什么

macOS 菜单栏常驻小面板「余额看板」：一屏看所有大模型 API 的余额，点一下直接进充值页。

- 源码：`~/WorkBuddy/软件制作/BalanceBar`
- 已安装：`/Applications/余额看板.app`（ad-hoc 签名，LSUIElement，无 Dock 图标）
- 用户配置：`~/.balancebar/config.json`；key 文件：`~/.balancebar/.env`
- 运行日志：`~/.balancebar/last-run.log`（每次刷新 + 每次面板渲染都会写一行）
- 已设开机自启：`~/Library/LaunchAgents/com.timon.balancebar.plist`（`bash autostart.sh off` 关闭）

## 2. 现状：哪些已完成、哪些没有

**已完成并实测通过**

| 功能 | 状态 |
|---|---|
| 菜单栏显示余额合计（如 `¥4.42`） | ✅ 实测 |
| 点图标弹出面板，列出每个平台：状态点 / 余额 / 详情 / 「充值」+「控制台」按钮 | ✅ 实测（无头 dump 验证） |
| DeepSeek 余额查询 | ✅ 官方接口实测返回 |
| 智谱 GLM 余额查询 | ✅ 实测（现金余额 + 资源包 token **两行**，见第 9 节） |
| 第三方中转站余额查询 | ⚪ **已按需求下架**（设置页无入口；适配器保留在 Providers.swift 备用） |
| 阿里云百炼 | ⚪ **设置页只保留「控制台」入口**（`consoleOnly`，无按 key 的公开余额接口） |
| 小米 MiMo 入口 | ⚪ 新增（`consoleOnly`，控制台 `platform.xiaomimimo.com/console/balance`；已探测 `api.xiaomimimo.com` 无公开余额端点） |
| **设置页白名单**：只渲染 DeepSeek / 智谱 / 阿里云百炼(仅控制台) / 小米 MiMo(仅控制台)；白名单外条目保存时自动从 config.json 移除 | ✅ 实测（`--ui-test` WHITELIST-TEST） |
| 后台每 10 分钟自动刷新（`refreshSeconds` 可调） | ✅ |
| 开机自启 / 刷新 / 退出 / 低余额变黄 | ✅ |
| **面板内「设置」页：通用区块 + 白名单平台（启用/名称/key/站点地址/充值页/控制台），保存并刷新** | ✅ 实测（`--ui-test` dump + 成图预览） |
| **设置页 ⌘V/⌘C/⌘A/⌘X/⌘Z/⌘Q 可用**（补 `NSApp.mainMenu` + 输入框右键菜单） | ✅ 实测（`--menu-test` + `--ui-test` 粘贴链路） |
| **凭据文件权限**：`~/.balancebar/` 700、`.env` 600（启动时与每次写入都强制收紧） | ✅ 实测（`--env-test` 断言 600） |
| **ProviderMeta 表驱动**（平台即数据：设置页字段/默认地址/额外参数由表派生，无按 type 的 UI 分支） | ✅ 实测（`--settings-save-test` 改 lowWarn 端到端） |
| 余额型平台不渲染假百分比/占位（CodexBar issue #3492 教训） | ✅ `grep` 全工程无 `100%`/`0%`/`.percent` |
| **通用设置入口**：设置页顶部「通用」区块可改 刷新间隔(秒) / 菜单栏标题，保存即生效（定时器立刻重排） | ✅ 实测（`--ui-test` dump） |
| **低余额阈值 lowWarn**：按平台进 ProviderMeta extras，设置页可直接改 | ✅ 实测（`--settings-save-test` 端到端） |
| **应用图标**：`.icns`（Finder/可执行文件）+ 面板头部标记，同一份几何；**菜单栏状态项只显示金额、不挂图标** | ✅ 实测（`--icon-test` ICON-TEST PASS，系统解析比对差 9.1/255；`--statusbar-test` STATUSBAR-TEST PASS） |
| **DeepSeek 峰谷标签**：行名称旁挂「峰时 / 非峰时」，按北京时间工作日 09:00–12:00、14:00–18:00 判定（周末与法定节假日全天谷时） | ✅ 实测（`--peak-test` 28 例边界 + `--peak-switch-test` 切换链路，见第 10 节） |

**尚无（都不是必须的）**

- 「＋新增中转站」按钮已随 relay 下架一起移除；如要恢复，把 relay 加回 `ProviderMeta.settingsWhitelist` 和 `table`，并在 Settings.swift 底部恢复加号按钮。

## 3. 密码 / key 从哪来（一定要理解这个链路）

`KeyStore.value(env:inline:)` 按顺序找：

1. `ProviderConfig.apiKey`（写在 config.json 里的明文，基本不用）
2. 进程环境变量
3. `~/.balancebar/.env`（**设置页要写的就是这个文件**）
4. `~/.hermes/.env`（用户已有 DeepSeek / 百炼的 key 在这里，所以 DeepSeek 开箱可用）

**不要**把 key 写进 `config.json`；也不要动 `~/.hermes/.env`。

## 4. 文件地图

```
BalanceBar/
├── Package.swift              SwiftPM，executable target，macOS 13+，Swift 5 语言模式
├── Sources/BalanceBar/
│   ├── main.swift             入口 + 十四个无头模式（--probe / --menu-test / --env-test / --settings-save-test / --ui-test / --preview / --icon-test / --statusbar-test / --peak-test / --peak-switch-test / --export-icon / 单实例保护）
│   ├── App.swift              AppDelegate + StatusBarController（菜单栏标题，只显示金额不挂图标；含网络刷新与峰谷切换两个定时器）+ AppMenus（主菜单，承载 ⌘V 等键等价物）+ KeyableWindow
│   ├── AppIcon.swift          应用图标：唯一几何来源（markPath / squircle / 各尺寸渲染 / iconset 导出 / 与系统图标比对）
│   ├── PeakPricing.swift      DeepSeek 峰谷判定：唯一规则出口（时段窗口 / 法定节假日表 / isPeak / nextChange / 标签文案与 tooltip）
│   ├── Config.swift           ProviderConfig 模型 + ProviderMeta 平台表（含适配器闭包）+ value/setValue(forKey:)
│   ├── KeyStore.swift         key 解析（加锁的并发安全缓存）+ writeEnv upsert（600 落盘）+ ConfigWriter.save
│   ├── Providers.swift        BalanceResult（含 usage）+ HTTP + JSONPick + 各平台适配器（统一签名，由 meta 表派发）
│   ├── Store.swift            BalanceStore：多观察者广播、并发拉取、菜单栏标题计算
│   ├── Panel.swift            UI：D 设计常量 / label / spacer / hairline / TextButton / DotView /
│   │                          ProviderRow（行内 detail 后缀用量）/ ListPaneController（列表页）/
│   │                          PanelViewController（容器，列表页 ⇄ 设置页）
│   ├── Settings.swift         UI：FieldShell（输入外壳 + 右键菜单）/ PrimaryButton / ProviderSectionView（按 meta 派生字段）/
│   │                          SettingsPaneController（设置页）/ FlippedView / dumpText
│   └── Log.swift              ~/.balancebar/last-run.log 轻量日志
├── Resources/Info.plist       LSUIElement=true，CFBundleDisplayName=余额看板，CFBundleIconFile=AppIcon
├── Resources/AppIcon.icns     应用图标（生成物，勿手改；由 make-icon.sh 重建）
├── run-local.sh               构建 → 组装 .app（含拷 AppIcon.icns）→ 安装到 /Applications → CDHash 自校验 → 启动
├── make-icon.sh               重新生成 Resources/AppIcon.icns（改图标形状后跑它）
├── autostart.sh               on / off / status
└── config.example.json        配置样例
```

## 5. 设置页（已实现，下面是规格 + 落地说明）

> 代码在 `Sources/BalanceBar/Settings.swift`；列表页 / 设置页的切换在 `Panel.swift` 的
> `PanelViewController`（容器）+ `ListPaneController` / `SettingsPaneController`。

### 5.0 实现时额外加的东西（超出原规格，觉得有用就留着）

- 每个区块首行左侧是「类型」小字（`deepseek` / `zhipu` / `aliyun` / `mimo`），右侧是可直接改的名称输入框。
- 名称输入框底下有一条 1px 下划线（聚焦时变深）——否则无边框输入框完全看不出能改。
- 输入框（`FieldShell`）聚焦时描边由 `#ECECEE` 变 `#121214`，点外壳的留白也能聚焦。
- 底部保存按钮是黑底白字的 `PrimaryButton`（唯一的实心元素，用来明确「主操作」）。
- 状态行默认写「key 只写入本机 ~/.balancebar/.env，不会上传」。
- 保存时做软校验：**启用的平台没填站点地址（needsBaseURL 的）/ 没填 key → 保留在设置页并黄字提示**，不切回列表页（否则提示会被切页吞掉）；没问题时才切回列表页。
- 站点地址留空 = 保留原默认地址（防止手滑把默认站点清空）；没写 `https://` 会自动补上。
- 平台没有 `apiKeyEnv` 时填了 key，会自动分配一个环境变量名（`<ID>_API_KEY`，非字母数字转 `_`）。

### 5.1 交互

面板头部加一个「设置」按钮 → 切换到设置页；设置页头部「返回」回到列表页。

设置页内容：顶部「通用」区块 + 白名单平台各一个区块，纵向滚动（最大高度 520）。

**白名单**（`ProviderMeta.settingsWhitelist`，按显示顺序）：`deepseek` → `zhipu` → `aliyun`（consoleOnly）→ `mimo`（consoleOnly）。白名单外的旧条目（moonshot / siliconflow / openrouter / relay）**设置页不渲染，保存时自动从 config.json 移除**。

每个平台区块的字段（全部左对齐，4px 网格，纯白背景，黑白灰）：

| 字段 | 控件 | 说明 |
|---|---|---|
| 启用 | 复选框 | 关掉就不查、不在列表显示 |
| 名称 | 单行文本（无边框，13px medium） | 可改名 |
| API Key | 密文输入框 | 仅 needsKey 平台（deepseek/zhipu）。占位文案：已配置 → `已配置（DEEPSEEK_API_KEY）· 留空不改`；未配置 → `粘贴 DEEPSEEK_API_KEY`。**留空 = 不改** |
| 站点地址 | 文本 | 仅 needsBaseURL 平台；填了默认地址，不要乱改 |
| 低余额阈值 | 文本 | deepseek/zhipu 的 extras，低于该值状态点变黄 |
| 充值页 / 控制台 | 文本 | 面板上「充值」「控制台」按钮跳转的地址 |

**consoleOnly 平台**（aliyun / mimo）区块只有三行：启用 + 名称、控制台。没有 API Key / 站点地址 / 充值页。

底部：保存状态文字、`保存并刷新`（「＋新增中转站」已随 relay 下架移除）。

### 5.2 保存行为

```
点「保存并刷新」
  → 收集所有字段
  → 非密文字段写回 ~/.balancebar/config.json（AppConfig.save()）
  → 密文字段（API Key / AccessKey）按「环境变量名 → 值」upsert 进 ~/.balancebar/.env
  → KeyStore.reload() → BalanceStore.reloadConfig() → BalanceStore.refresh()
  → 回到列表页
```

要写的环境变量名：优先用该平台自己的 `ProviderConfig.apiKeyEnv`；阿里云固定写 `ALIYUN_ACCESS_KEY_ID` / `ALIYUN_ACCESS_KEY_SECRET`。

**底层已经写好了，直接用**：

```swift
ConfigWriter.save(config: AppConfig, secrets: [String: String]) -> String   // 写 config.json + .env
KeyStore.writeEnv(_ pairs: [String: String], to: URL? = nil)                // upsert，保留注释与其它行
KeyStore.has(env: String?) -> Bool                                          // 设置页显示「已配置/未配置」
```

`Providers.fetch` 里阿里云分支已经改成先读 `ALIYUN_ACCESS_KEY_ID` / `ALIYUN_ACCESS_KEY_SECRET` 环境变量，再回退 config 里的明文字段。

### 5.3 实现要点（照着做能少踩一遍坑）

- **必须用多观察者，不能再用单槽闭包**。`BalanceStore` 现在是 `observe(owner, block)` + `notify()` 广播。之前用 `store.onChange = {...}` 时，菜单栏和面板互相覆盖，面板永远卡在「正在读取余额」。设置页不要碰这个机制。
- **面板容器**：`PanelViewController` 做容器（纯白背景 NSView），`addChild` 切换 `ListPaneController` / `SettingsPaneController` 两个子控制器；切页后用
  ```swift
  DispatchQueue.main.async { self.view.layoutSubtreeIfNeeded(); self.preferredContentSize = self.view.fittingSize }
  ```
  让 NSPopover 自适应高度（`preferredContentSize` 是 NSPopover 唯一认的尺寸来源）。
- **输入框内边距**：`NSTextField` 没有 padding API。用外壳实现：外层 `NSView`（wantsLayer + 1px `#ECECEE` 描边 + 圆角 4 + 白底）内放 `NSTextField`（`isBordered=false; isBezeled=false; drawsBackground=false`），左右各留 8pt，外壳高度 28。
- **滚动区**：`NSScrollView` 的 `documentView` 必须是**翻转坐标**的自定义 view（`override var isFlipped: Bool { true }`），否则内容会从底部开始排。documentView 用 NSStackView，约束 leading/trailing/top/bottom 贴住翻转容器，滚动区高度 = `min(内容高度, 520)`。
- **列表页加载态**：数据没回来时按「已启用平台数」渲染骨架行（名称 + 「读取中…」），高度一开始就对，避免 popover 先小后大跳一下。
- **设计常量**在 `Panel.swift` 的 `enum D` 里，直接用，别新造色值。

### 5.4 怎么验收（每步都要跑，别靠肉眼）

```bash
cd ~/WorkBuddy/软件制作/BalanceBar && bash run-local.sh      # 构建+安装+CDHash 校验+启动

# ① 接口层：直接打印各平台余额/错误（含用量行）
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --probe
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --probe --only deepseek

# ② 菜单/快捷键：⌘V 等键等价物必须已注册，否则设置页粘不进 key
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --menu-test        # 期望 MENU-TEST PASS

# ③ UI 层：真实构建面板并强制布局，按顺序 dump 列表页 → 设置页（含白名单断言）→ 回列表页，
#    最后走一遍真实粘贴链路（假 key 经 paste: action 打进设置页密文框，断言字段非空）
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --ui-test          # 期望 WHITELIST-TEST PASS + PASTE-TEST PASS
#   白名单断言：设置页 dump 里不得出现 moonshot/siliconflow/openrouter/relay/AccessKey/中转站，
#   必须含 mimo，控制台行 ≥ 2（aliyun/mimo 各一行）；回到列表页 size 必须回落到 (400, 297)

# ④ 写盘逻辑（在临时文件上验证 upsert + 600 权限，不碰真实配置）
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --env-test          # 期望 ENV-TEST PASS

# ⑤ 保存链路端到端（设置页 lowWarn → collect → 写盘 → 读回，跑完自动恢复原文件）
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --settings-save-test  # 期望 SAVE-TEST PASS

# ⑤b 应用图标（.icns 被 Info.plist 引用 + 系统解析出的图标与自绘一致）
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --icon-test           # 期望 ICON-TEST PASS
#   改图标形状后：bash make-icon.sh && bash run-local.sh

# ⑤c 菜单栏状态项（只显示金额、不挂图标；等真实刷新回来再断言）
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --statusbar-test      # 期望 STATUSBAR-TEST PASS

# ⑤d 峰谷时段规则（纯规则，28 例边界 + 7 例下次切换；不发请求不起 UI）
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --peak-test           # 期望 PEAK-TEST PASS

# ⑤e 峰谷切换的更新链路（定格时段 → notify → 断言标签翻转，双向各一次）
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --peak-switch-test    # 期望 PEAK-SWITCH PASS

# ⑥ 运行期：看 App 内部日志（刷新结果 + 面板每次渲染的内容）
tail -5 ~/.balancebar/last-run.log

# ⑦ 成图（本机 screencapture 是可用的，交接文档早期说被 TCC 挡死已过时）
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --preview settings > /tmp/p.txt 2>&1 &
sleep 4; WIN=$(grep PREVIEW_WINDOW /tmp/p.txt | awk '{print $2}')
screencapture -x -o -l"$WIN" build/shots/settings.png    # --preview list 出列表页
kill %1

# ⑦b 峰谷标签两种态都要出图（不然得等到明早 9 点才看得到「峰时」）
#     --peak-now 只影响标签显示，其余一切走真实时间
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --preview list --peak-now "2026-10-14 10:00" > /tmp/p.txt 2>&1 &
sleep 8; WIN=$(grep PREVIEW_WINDOW /tmp/p.txt | awk '{print $2}')
screencapture -x -o -l"$WIN" build/shots/list-peak-on.png
kill %1
```

`--ui-test` 现在覆盖：`PanelViewController.debugShowSettings() / debugShowList()` + 设置页白名单断言 + 粘贴链路，
`debugDump()` 会打印所有 `NSTextField` 的 `stringValue`/`placeholderAttributedString`、
所有 `CheckboxButton` 的 `[enable:<id>=on|off]`、以及所有按钮标题。

注意：这台机器**截图可用**（`screencapture -x` 实测能出图，2026-09-24 复测）。
`--preview` 会开一个 400pt 宽的无边框真窗口并强制 `.aqua` 浅色外观，
所以能用 `screencapture -l<windowNumber>` 精确抓面板成图。若哪天截图又被挡，就退回用 dump 断言。

## 6. 各家余额接口（已实测，可直接复用）

> 适配器统一签名 `(ProviderConfig, String, String, BalanceResult)` =（配置, 站点地址, key, 半成品结果），
> 注册在 `Config.swift` 的 `ProviderMeta.table` 里。**加平台 = 表里加一行 + Providers 里加一个函数**，
> 设置页字段/默认占位/额外参数自动跟着来，不要写按 type 的 UI 分支。

| 平台 | `type` | 接口 | 说明 |
|---|---|---|---|
| DeepSeek | `deepseek` | `GET {base}/user/balance` | 返回 `balance_infos[].total_balance` |
| 智谱 GLM | `zhipu` | ①现金 `GET https://www.bigmodel.cn/api/biz/account/query-customer-account-report` ②token `GET https://bigmodel.cn/api/biz/tokenAccounts/list/my?pageNum=1&pageSize=20&filterEnabled=false` | **两行并存**（主行现金 / 副行资源包 token），见第 9 节。余额接口在控制台主机 `www.` 上，不在 `open.` API 主机；旧 `open.…/api/biz/customer/account/getUserAccount` 已下线。判成功要看 body `code<400 && success!=false`（HTTP 200 但 body 可能 `code:401`） |
| Kimi | `moonshot` | `GET {base}/v1/users/me/balance` | **已下架**（不在设置页白名单；适配器保留备用） |
| 硅基流动 | `siliconflow` | `GET {base}/v1/user/info` | 取 `totalBalance`。**已下架**（同上） |
| OpenRouter | `openrouter` | `GET {base}/api/v1/credits` | 余额 = `total_credits - total_usage`，USD。**已下架**（同上） |
| 中转站 | `relay` | ① `GET {base}/v1/dashboard/billing/subscription` + `/v1/dashboard/billing/usage` ② `GET {base}/api/user/self` | new-api / one-api 系。①余额 = `hard_limit_usd - total_usage/100`；②`quota ÷ 500000`。**已下架**（同上） |
| 阿里云百炼 | `aliyun` | 设置页仅控制台入口（fetch 已断开） | 恢复自动查余额：把 `meta.fetch` 接回 `Providers.aliyun`（BSS `QueryAccountBalance`，HMAC-SHA1 签名）并在设置页恢复 AccessKey 字段 |
| 小米 MiMo | `mimo` | 无公开余额接口（`/v1/user/balance` 等探测均 404） | consoleOnly 入口，控制台 `https://platform.xiaomimimo.com/console/balance`；API 走 `api.xiaomimimo.com/v1`（OpenAI 兼容） |

探测未知端点的小技巧：用**假 key** 请求，**401 = 端点存在**，**404 = 不存在**，不用真 key 就能确认接口路径。

## 7. 构建与踩过的坑

**构建（本机专用）**：Xcode 工具链是 Swift 6.3，而 CLT SDK 是 6.4，**混用会报**
`failed to build module 'Swift'; this SDK is not supported by the compiler`。
所以 `run-local.sh` 优先用**整套 CLT**（`unset DEVELOPER_DIR; /usr/bin/swift build -c release --disable-sandbox`），
失败再退回 Xcode 工具链，最后才 xcodebuild；三级各自写独立日志，别混在一起看。

- `set -u` 的脚本里，**中文标点前的变量必须写 `${VAR}`**：`$PID）` 会让 bash 3.2 报 `unbound variable`。
- `static func default()` 编译不过（关键字），用 `makeDefault()`。
- `fittingSize` 是 NSView 的属性，NSViewController 里直接调会报找不到。
- 管道接 `head` 会被 SIGPIPE 打断并让 `pipefail` 终止脚本（静默失败），补 `|| true`。
- LaunchAgent 和手动启动会各拉一份实例、菜单栏出现两个图标 —— 已用 `NSRunningApplication.runningApplications(withBundleIdentifier:).count > 1 → exit(0)` 做单实例保护。
- **`NSButton` 没有可读的 `buttonType`**（只有 setter）。要在 dump 里区分勾选框，得开个子类
  （`CheckboxButton`），靠 `is` 判断。
- **`NSTextField` 用 `placeholderAttributedString` 设置占位符时，`placeholderString` 读回来是 nil**。
  dump 时要 `tf.placeholderString ?? tf.placeholderAttributedString?.string`。
- **容器切页后不能读容器自己的 `fittingSize`**：`preferredContentSize` 会被反写回 view 的 frame，
  切回列表页时容器 `fittingSize` 仍停在上一页的高度（实测卡在 676）。`relayout()` 里要量
  **当前子页**的 `fittingSize`。
- **`DotView` 必须在 bounds 内画满圆**。原来写成 `NSRect(x: 0, y: 2, w: 6, h: 6)`，
  视图只有 6 高，圆顶被裁掉两像素，肉眼看着像个小三角（已修）。
- **`KeyStore` 的 env 缓存曾经有并发竞态**：`loadEnvFiles()` 先置 `loaded = true` 再填缓存，
  而 `BalanceStore.refresh()` 是 `withTaskGroup` 并发拉多个平台的 → 第二个线程看到 `loaded == true`
  就直接拿空缓存返回，于是**面板随机出现「缺少 key（DEEPSEEK_API_KEY）」，虽然 key 明明存在**。
  复现方式：`--probe`（顺序拉取）3/3 正常，`--ui-test`（并发拉取）1/3 报 NO_KEY。
  已改成 `NSLock` + 缓存填完才置 `loaded`。**不要退回无锁版本。**
- **LSUIElement 菜单栏 App 必须手动建 `NSApp.mainMenu`**：⌘V/⌘C/⌘A/⌘X/⌘Z/⌘Q 全靠菜单项的
  keyEquivalent 分发，没有主菜单这些快捷键全部静默失效（设置页粘不进 key 就是这么来的）。
  见 `App.swift` 的 `AppMenus.install()`，App 启动和无头自检都要调用。
- **无头环境里 borderless 窗口成不了 key window**（`makeKeyAndOrderFront` + `canBecomeKey=true`
  也不行，真实点击弹出的 popover 才行）→ `sendAction(_:to:nil)` 走 keyWindow 链会失败。
  `--ui-test` 的粘贴链路因此兜底：把同一个 `paste:` action 直接递给字段编辑器
  （responder chain 里真正处理粘贴的就是它），分发结果和字段内容都能断言。
- **`keyEquivalent` 用大写字母就代表 ⇧**（`"Z"` = ⌘⇧Z），但 dump 时要把这个隐含的 ⇧ 还原出来，
  否则 `--menu-test` 会把重做键显示成 ⌘Z。
- **凭据文件权限**：`.env` 一律 600、`~/.balancebar/` 700，写入后立刻 chmod，启动时也再收紧一次
  （`KeyStore.enforcePermissions()`）。曾经是 644，任何本地进程都能读。
- **设置页字段必须由 `ProviderMeta` 表派生**：`Extras` 的 `envName` 非 nil → 凭据写 `.env`；
  nil → 普通参数写 `config.json`（走 `ProviderConfig.value/setValue(forKey:)`，新字段要在那里加分支）。
  别再往 `ProviderSectionView` 里加 `if type == ...`。

## 8. 智谱 GLM 的双行（现金 + token）

`Providers.zhipu()` 现在并发调两个接口，两路结果独立落到 `BalanceResult`：

| 行 | 字段 | 来源 |
|---|---|---|
| 主行（`¥`，与 DeepSeek 同款） | `amount` / `currency="CNY"` | `www.bigmodel.cn/api/biz/account/query-customer-account-report` 的 `availableBalance` |
| 副行（token 缩写） | `tokenAmount` / `tokenLabel` | `bigmodel.cn/api/biz/tokenAccounts/list/my` 里 `status=="EFFECTIVE"` 且 `suitableModel` 含 `glm-5.3-flash` 的行，`availableBalance` 累加 |

- **降级**：任一接口失败 → 另一行照常显示，失败原因落在 `cashError` / `tokenError`（渲染进副行并转红）；两者都失败才 `throw`。
- **换算唯一出口是 `Fmt.tokens(_:)`**（Providers.swift，紧邻 JSONPick）：≥1e6 → `xx.xm`，≥1e3 → `xx.xk`，以下原样。provider 不硬拼字符串，`ProviderRow` 直接渲染 `result.subLine`，不自行换算。
- **副行文案入口**：`subLine`（面板用，token + 现金构成 + 失败原因）与 `tokenNote`（`--probe` 用，不含现金构成，避免和主行重复）。
- **新增字段一律追加在 `BalanceResult` 末尾**：`tokenAmount / tokenLabel / tokenError / cashError`。成员初始化参数顺序（`detail` 在 `rechargeURL` 前）不能动，`Panel.swift` 的骨架行初始化依赖它。
- **菜单栏标题**：现金可用显示 `¥`；`menuTitle` 指到某平台且现金取不到时，`statusDisplay` 退回 token 缩写；`auto` 合计里「无现金但有 token」的平台会单独列出缩写值。
- 自检：`--probe --only zhipu` 出两行；`--ui-test` 打印 `ZHIPU-2LINE PASS/FAIL`（断言 dump 里同时有 `¥\d+\.\d{2}` 与 `glm-5.3-flash\s+[\d.]+[mk]`）。

## 9. 应用图标（几何只有一份定义）

**改图标形状只改 `Sources/BalanceBar/AppIcon.swift`**，然后 `bash make-icon.sh` → `bash run-local.sh`。别做图、别手工改 `.icns`。

### 9.1 一处几何，两处显示

| 位置 | 怎么来的 | 代码 |
|---|---|---|
| 应用图标 `.icns`（Finder / 可执行文件 / 关于面板） | `Contents/Resources/AppIcon.icns`，由 `Info.plist` 的 `CFBundleIconFile=AppIcon` 引用 | `BalanceIcon.drawAppIcon` |
| 面板头部标题左侧 | `BalanceIcon.glyphImage(pt:14)` 放进 `NSImageView`（14×14，与标题间距 4pt） | `ListPaneController.loadView()` |

`markPath(in:)` 是「¥」的唯一路径定义：粗圆头笔画，两横之间、V 底与第一横之间各留 ≈0.7 个笔画宽的空白（第一版间距 0.23 − 笔画 0.21 ≈ 贴死，两横糊成一块，已修）。

### 9.2 菜单栏状态项只显示金额，**不挂图标**

明确的产品决定（用户 2026-10-08 拍板）：顶部状态栏不要图标，只留金额。

- 标题就是 `store.statusTitle()` 原样输出 —— 自带 `¥`，形如 `¥5.95` / `$3.20 ...` / `36.9m`；无数据时回落 `余额`。
- `StatusBarController.updateTitle()` 里显式 `button.image = nil` + `imagePosition = .noImage`，且**每次刷新都再清一次**，防止将来有人加回图标后只在部分路径生效。
- 历史上曾让状态项挂 `glyphImage(pt:14)`，但标记本身就是「¥」，会和标题里的货币符号叠成「¥¥5.95」；靠 `StatusTitleRender.split` 顶替符号只是补救。**现在直接不挂**，那个纯函数已随之下线，别再引回来。

### 9.3 重新生成 / 验证

```bash
bash make-icon.sh     # swift build → --export-icon 渲染 10 个尺寸 → iconutil 打包 → Resources/AppIcon.icns
bash run-local.sh     # 把 .icns 拷进 .app/Contents/Resources/ 再安装
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --icon-test        # 期望 ICON-TEST PASS
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --statusbar-test   # 期望 STATUSBAR-TEST PASS
```

`--icon-test` 断言：从 `.app` 内运行、`CFBundleIconFile=AppIcon`、`.icns` 文件存在且含 10 个尺寸、`NSApp.applicationIconImage` 非空、面板头部标记可用。硬核校验一条：

- **系统解析比对**：`NSWorkspace.shared.icon(forFile: bundlePath)` 走的就是 Finder 取图标的同一条路，把它和自绘图标缩到 64×64 逐像素比，差值 < 12/255 才算「系统真的用上了这张图」（实测 9.1，仅抗锯齿差异）。**这是证明图标生效的关键一步**，别只看文件存在。

`--statusbar-test` 断言菜单栏那处的不变式（起真实 `StatusBarController`，等 9 秒到刷新回来再查）：

```
STATUSBAR-TEST | 首帧 标题=「余额」 图标=无
STATUSBAR-TEST | 刷新后 标题=「¥5.95」 statusTitle()=「¥5.95」 图标=无 imagePosition=0
STATUSBAR-TEST PASS（顶部状态栏只显示金额、无图标）
```

校验点：`button.image == nil`、`imagePosition == .noImage`、标题逐字等于 `statusTitle()`、不出现 `¥¥`、非空。

小尺寸有光学补偿：16/32px 下标记占底板 56%、≤64px 占 50%、大尺寸 45%，否则 16px 上笔画会糊成一团。

### 9.4 坑

- `run-local.sh` 原来只拷 `Info.plist`，**不拷 Resources** —— 光把 `.icns` 放进源码目录不会进 bundle，必须显式 `cp`。
- `qlmanage -t` 在本机被沙箱挡（`sandbox initialization failed`），验证图标别走它，用 9.3 的 NSWorkspace 比对。
- **验证「没挂图标」比验证「挂了图标」更需要真跑**：`button.image = nil` 只设一次容易被后续刷新路径覆盖，所以 `--statusbar-test` 连首帧和刷新后各查一遍。
- 图标底板是深色（`#252529 → #0B0B0D` 极轻渐变）+ 白色「¥」，与面板里唯一的实心元素（黑底白字的「保存并刷新」）同一套语言；面板本身仍是纯白，不冲突。

## 10. DeepSeek 峰谷标签（峰时 / 非峰时）

### 10.1 判定依据（规则来源要能追溯，别凭印象改）

规则唯一的实现出口是 `Sources/BalanceBar/PeakPricing.swift`，**全项目只此一处**判定峰谷。

- 官方价目表脚注 2（`api-docs.deepseek.com/quick_start/pricing`）：
  > Peak hours are 01:00 - 04:00 and 06:00 - 10:00 UTC, Monday through Friday, excluding Chinese
  > public holidays. All other hours are off-peak, including weekends and Chinese public holidays in full.

  换算北京时间（UTC+8）：**峰时 = 工作日 09:00–12:00、14:00–18:00**；其余全部谷时。
  谷时价 = 峰时价的一半，所以这个标签直接对应"现在调用贵不贵"。
- 法定节假日表：`PeakPricing.holidays`（按年分组，当前内置 **2026**，来自国办发明电〔2025〕7号）。

**两条刻意的口径，都与官方字面一致：**

| 情形 | 判定 | 理由 |
|---|---|---|
| 调休上班的周六（2/14、2/28、5/9、10/10） | **谷时** | 官方写的是 Monday through Friday，且明确 including weekends |
| 法定节假日 | **整天谷时** | 官方 no public holidays 是全天豁免，不只是落在工作日的那几天 |

区间取**左闭右开**：09:00 起算峰时，12:00 整即转谷时；14:00 起算，18:00 整转谷时。

⚠️ **每年更新一次**：国务院办公厅发次年放假通知后（通常 11 月），把新一年的日期加进
`PeakPricing.holidays`。没更新也不会崩——缺的年份只是不再豁免节假日，周末判定照常。

### 10.2 展示位置与样式

| 项 | 规格 |
|---|---|
| 位置 | **DeepSeek 行第一行、平台名称右侧**（`● DeepSeek [非峰时] ……… ¥5.75`） |
| 间距 | 与名称 **4pt**（4px 网格），其余仍走 stack 默认 8pt |
| 尺寸 | 高 **16pt**、左右内边距 4pt、圆角 4、1px 描边、纯白底 |
| 文案 | `峰时` / `非峰时` |
| 峰时（贵） | 描边 `D.ink`(#121214) + 文字 `D.ink` + medium —— 视觉压重，提示正在按高峰价计费 |
| 非峰时（便宜） | 描边 `D.line`(#ECECEE) + 文字 `D.inkFaint`(#9E9EA6) + regular —— 安静，不抢视线 |
| 悬停提示 | 时段规则 + 是否是节假日/周末豁免 + 下次切换的**具体时刻** |

只用黑白灰拉层级，没有引入新色相：和面板既有的「余额偏低变黄」同一套「重 = 要注意」的逻辑，
也避免和 `D.warn`（低余额）撞色。**标签不参与状态点/金额的语义**，余额取不到时照挂。

组件是 `Panel.swift` 里的 `PeakChip`，是否显示由 `ProviderMeta.peakPricing` 决定
（`BalanceResult.showsPeakPricing` 在 `Providers.fetch()` 里统一带上，加平台时只改表不加分支）。
首帧骨架行也会带上标签（`render()` 里查 meta），避免数据回来时宽度跳动。

### 10.3 刷新与切换时的更新逻辑

关键设计：**标签值不写进 `BalanceResult`**，而是每次渲染按当前时刻现算
（`PeakChip.refreshNow()` → `PeakPricing.state(at:)`）。所以不存在"值过期"的可能。

| 时机 | 走什么路径 |
|---|---|
| 定时网络刷新（默认 600s） | `store.refresh()` → `notify()` → `render()` → 每行 `apply()` → 重算标签 |
| 打开面板 | `showPopover()` → `store.refresh()`，同上 |
| 设置页保存 / 改刷新间隔 | `reloadConfig()` → `notify()`，同上 |
| **时段正点切换** | `StatusBarController.schedulePeakTimer()`：**一次性**定时器排到 `PeakPricing.nextChange()` 返回的真正切换时刻（09:00 / 12:00 / 14:00 / 18:00 或跨日），到点只调 `store.notify()`（**不发网络请求**）再排下一次 |

### 10.x 面板行为：`.applicationDefined`，截图时面板不会消失（2026-10-15 修复）

popover 曾经是 `.transient`——**任何外部交互（截图工具激活、⌘⇧4、微信截图热键）都会让 AppKit 立刻收掉面板**，
用户「点开看板 → 截图」永远拍到空位。`--capture-test` 实测证据：截图时窗口 `visible=false 在屏CGList=false`、`popover.isShown=false`。

现状：

- `popover.behavior = .applicationDefined`：AppKit 不自动收，**面板在焦点切换后仍然在屏**（实测连续两次 `screencapture -x` 后 `visible=true isShown=true`，全屏截图里完整拍到面板内容）。
- 关闭路径四条：**单击面板外空白**（全局监听，见下）/ **再点一次状态栏** / **按 Esc**（`StatusBarController` 里的本地 keyDown 监听，keyCode 53）/ 点「充值」「控制台」跳浏览器时发 `balancebar.closePanel` 通知主动收起。
- **「点外收起」与「截图不失效」共存**（2026-10-15 二次迭代）：`StatusBarController` 挂全局左键监听（自家窗口事件不进全局监听，天然不误触），mouseUp 按位移 < 3pt 判定「单击空白」→ 收起；拖拽（截图框选/划词/拖窗）不收。另有两道截图防线：点击点命中的第一扇「别人家的窗」level ≥ 1000（微信截图/SnipShot/系统截图遮罩量级）→ 不参与判定；前台进程 bundleId 含 `screencapture`/`screenshot`（系统截图会话）→ 不参与判定。
- 注意 NSPopover **没有** `.permanent`，只有 applicationDefined / transient / semitransient——别再试 `.permanent`，编译不过。
- 验收：`--capture-test`（截图时面板仍在）+ `--outside-click-test`（A 单击空白收起 / B 拖拽不收 / C 遮罩判定矩阵）。

定时器只保证"准时"，不是正确性的依赖：休眠错过、系统延迟触发都不要紧，下一帧渲染就会对齐。
`nextChange` 向后扫 15 天的候选点（每天 00:00 + 四个窗口边界），所以周五收工后会一路排到周一 09:00。

### 10.4 验收

```bash
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --peak-test          # PEAK-TEST PASS
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --peak-switch-test   # PEAK-SWITCH PASS
```

- `--peak-test`：**28 例判定**（窗口四个边界含 12:00/18:00 整点、普通工作日、周末、
  7 个法定节假日、节假日前后一天、调休周六）+ **7 例下次切换**（含"周五收工跳过整个周末"）。
  每条用例都带期望星期，日期算错会直接报「用例日期与标注的星期不符」，不会假通过。
- `--peak-switch-test`：把标签定格成谷时 → `notify()` → 峰时 → `notify()` → 周末谷时，
  断言 **非峰时 → 峰时 → 非峰时**。这条覆盖的正是定时器到点后的完整链路。
- `--ui-test` 里的 `PEAK-CHIP` 断言：列表页 dump 里「峰时/非峰时」**有且只有一个**。
  注意 `非峰时` 含 `峰时` 子串，统计必须用负向后顾 `(?<!非)峰时`，否则永远误判通过。

### 10.5 坑

- **加字段只能追加在 `BalanceResult` 末尾**（`showsPeakPricing` 在最后），成员初始化参数顺序不能动。
- **`--peak-now` 只给 `--preview` 用**（`PeakPricing.frozenNow`），生产路径恒为 nil。
  判定函数本身始终接收显式时刻，是纯函数，可被无头用例直接喂日期。
  没有这个开关就只能等到第二天早上 9 点才能看到「峰时」长什么样。
- 时区一律用 `PeakPricing.calendar`（Asia/Shanghai），**不要用 `Calendar.current`**，
  否则换个时区的机器判定会漂。

## 11. 做完之后

1. 跑第 5.4 的①～⑤、⑤b～⑤e，把 `--probe` / `--ui-test` 的真实输出 + 成图贴给用户。
   改了跟时段/图标有关的逻辑时，`--peak-test` / `--peak-switch-test` / `--icon-test` / `--statusbar-test` **必须逐个跑**，它们各自覆盖不同的不变式。
2. 平台 key 都在面板「设置」页里填，不用手改文件。当前平台：DeepSeek / 智谱已配好；阿里云百炼、小米 MiMo 是控制台入口型，无 key 可填。
3. 如果界面/间距要调，设计硬约束：极简黑白灰、左对齐、严格 4px 网格、纯白背景、不要玻璃/毛玻璃/暗色遮罩。
4. 面板「设置」页里改完点「保存并刷新」，写盘位置：非密文 → `~/.balancebar/config.json`；
   密文 → `~/.balancebar/.env`（`~/.hermes/.env` 只读，永不写）。


---

## 项目：FigmaFontCN（Chrome 扩展，2026-10-12 新增）

需求：Chrome 扩展改为**油猴（Tampermonkey）用户脚本**（用户已装油猴）。Figma 网页版字体面板把英文字体名追加显示中文名（静态对照表，不用在线翻译）。完整需求见 `FigmaFontCN/TASK-current.md`，做完归档该文件。
