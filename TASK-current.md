# 当前任务（TASK-current）

> WorkBuddy 每次只读两个文件：HANDOFF.md（基础，长期不变）+ 本文件（当前任务，做完替换）。
> 交付时把结果追加到本文件末尾，Hermes 确认后会归档到 TASK-done/。

---

## 9. 本次任务（2026-10-08 交接）：智谱 GLM 双行显示 —— 现金余额 + 资源包 token

> 优先级最高，做完上面原有验收后必须满足本节。

### 9.1 需求

智谱 GLM 由单行改为**两行**：

1. **第一行：账户现金余额**（¥，走现金接口取数，样式与 DeepSeek 等其它平台的主行一致）
2. **第二行：资源包 token 余量**，沿用现有 k/m 缩写规则（≥1,000,000 → `xx.xm`，≥1,000 → `xx.xk`，以下原样），作为副行，字号颜色与现有 detail 行一致

### 9.2 数据来源（两接口都调，缺一不影响另一）

| 行 | 接口 | 说明 |
|---|---|---|
| 现金余额 | `GET https://www.bigmodel.cn/api/biz/account/query-customer-account-report` | 字段 `availableBalance` / `rechargeAmount` / `totalSpendAmount` / `giveAmount`；**HTTP 200 但 body 可能 `code:401`，判成功必须看 body code + success** |
| token 资源包 | `GET https://bigmodel.cn/api/biz/tokenAccounts/list/my?pageNum=1&pageSize=20&filterEnabled=false` | **2026-10-08 实测可用，Bearer 直接用现有 GLM_API_KEY，无需网页 cookie**；返回 `rows[]`，只筛 `status=="EFFECTIVE"` 且 `suitableModel` 含 `glm-5.3-flash` 的行，`availableBalance`（单位 tokens）累加 |

规则：任一接口失败 → 另一行照常显示（失败行为错误态）；两者都失败才整体报错。
当前 `zhipu()` 是「资源包命中即 return」的临时逻辑（现金被跳过），本次必须改成两路并存。

### 9.3 实现约束

- token 格式化统一走一个 `formatTokens()`（放在 JSONPick 同层或 Panel 的 D 常量旁），provider 里不硬拼字符串，面板渲染处不再自行换算；菜单栏标题现金可用时显示 ¥，仅 token 可用时显示缩写值。
- `BalanceResult` 需要能同时携带现金与 token 两行（加字段可以，但**不得破坏其它 provider 的成员初始化参数顺序**：`detail` 在 `rechargeURL` 前）。
- UI/观察者/key 链路等硬约束沿用第 5.3、7 节，不变。

### 9.4 本任务的验收（在 5.4 的①~⑤之外追加）

- `--probe --only zhipu` 输出必须**同时**包含现金 ¥ 值和 token 缩写值两行。
- `--ui-test` 的 `debugDump()` 里能断言智谱区块出现两行文本（现金行 + token 行）。
- `tail -5 ~/.balancebar/last-run.log` 中 zhipu 的渲染行含 `¥` 与 token 缩写（如 `glm-5.3-flash 41.9m`）。
- 预期值参考（2026-10-08 15:00 实测）：现金约 ¥0.20，glm-5.3-flash 资源包约 4200 万 tokens（数值随用量浮动，量级对上即可）。
- 交付：改动文件清单 + `--probe` 与 last-run.log 原样输出，追加到本文件末尾。

---

## ✅ 交付记录（2026-10-08 16:58，布迪执行）

### 改动文件清单

| 文件 | 改动 |
|---|---|
| `Sources/BalanceBar/Providers.swift` | `BalanceResult` 末尾追加 4 个字段（`tokenAmount` / `tokenLabel` / `tokenError` / `cashError`，**未动既有成员顺序**）；新增 `Fmt.tokens(_:)`（与 JSONPick 同层）；新增派生属性 `tokenLine` / `tokenNote` / `subLine` / `subLineHasError` / `statusDisplay`；重写 `Providers.zhipu()` 为 `async let` 双路并发 + 私有 `zhipuCash()` / `zhipuTokenPacks()`；删除旧的「资源包命中即 return」与 Coding Plan 兜底分支 |
| `Sources/BalanceBar/Panel.swift` | `ProviderRow.apply()` 副行改渲染 `result.subLine`（不再自行换算）；副行含失败原因时走 `D.bad`；`amount == nil` 时金额转浅灰 |
| `Sources/BalanceBar/Store.swift` | `statusTitle()` 指到单平台时用 `statusDisplay`（现金优先、退回 token 缩写）；`auto` 合计追加「无现金但有 token」平台的缩写；刷新日志用 `statusDisplay` 并把 token 副行写进括号 |
| `Sources/BalanceBar/main.swift` | `--probe` 增加「副行:」行（用 `tokenNote`）；`--ui-test` 增加 `ZHIPU-2LINE PASS/FAIL` 断言 |
| `HANDOFF.md` | 接口表 zhipu 行改为双接口；新增第 8 节「智谱 GLM 的双行」；原「做完之后」顺延为第 9 节 |
| `build/shots/list-zhipu-2line.png` | 列表页成图（新增，非源码） |

### ① `--probe --only zhipu`（原样）

```
zhipu OK ¥0.20 CNY 充值 10.00 · 已用 9.80
             副行: glm-5.3-flash 36.9m
             充值: https://open.bigmodel.cn/finance-center/finance/pay
```

### ① 全平台 `--probe`（原样）

```
deepseek OK ¥5.75 CNY 充值 1.24 · 赠送 4.50
             充值: https://platform.deepseek.com/top_up
zhipu OK ¥0.20 CNY 充值 10.00 · 已用 9.80
             副行: glm-5.3-flash 36.9m
             充值: https://open.bigmodel.cn/finance-center/finance/pay
bailian LINK —  官方无按 key 查余额接口；填 accessKeyId/accessKeySecret 可自动查阿里云账户余额
             充值: https://usercenter2.aliyun.com/finance/fund-management/recharge
mimo LINK —  MiMo API 开放平台，无公开余额接口，点开控制台查看用量与余额
```

### ③ `--ui-test`（关键三行，原样）

```
UI 列表页 刷新后 | size=(400.0, 356.0) | 余额看板 · 16:54 · [刷新] · 刷新 · [设置] · 设置 · DeepSeek · ¥5.75 · 充值 1.24 · 赠送 4.50 · [充值] · 充值 · [控制台] · 控制台 · 智谱 GLM · ¥0.20 · glm-5.3-flash 36.9m · 充值 10.00 · 已用 9.80 · [充值] · 充值 · [控制台] · 控制台 · …
UI 智谱双行 | 现金行=true token行=true → ZHIPU-2LINE PASS
UI 设置页白名单 | 违规=无 mimo=true 控制台行=4 → WHITELIST-TEST PASS
UI 粘贴链路 | paste: 分发=true 密文框=true 字段长度=17 → PASTE-TEST PASS
```

### ④ 降级路径实测（临时改坏 URL 验证，随后已恢复并重装）

```
# token 接口 404 时 —— 现金行照常，副行报错态
zhipu OK ¥0.20 CNY 充值 10.00 · 已用 9.80
             副行: 资源包接口不可用

# 现金接口 404 时 —— 主行显示 —，token 行照常
zhipu OK —
             副行: glm-5.3-flash 36.9m · 接口不存在: /account/__broken-report
```

### ⑥ `tail -5 ~/.balancebar/last-run.log`（原样）

```
[10-08 16:57:58] 刷新完成 | 标题=¥5.95 | deepseek=¥5.75 zhipu=¥0.20(glm-5.3-flash 36.9m) bailian=LINK mimo=LINK
[10-08 16:57:58] 面板渲染 | results=4 | 余额看板 · 16:57 · [刷新] · 刷新 · [设置] · 设置 · DeepSeek · ¥5.75 · 充值 1.24 · 赠送 4.50 · [充值] · 充值 · [控制台] · 控制台 · 智谱 GLM · ¥0.20 · glm-5.3-flash 36.9m · 充值 10.00 · 已用 9.80 · [充值] · 充值 · [控制台] · 控制台 · 阿里云百炼 · — · 官方无按 key 查余额接口；填 accessKeyId/accessKeySecret 可自动查阿里云账户余额 · [充值] · 充值 · [控制台] · 控制台 · 小米 MiMo · — · MiMo API 开放平台，无公开余额接口，点开控制台查看用量与余额 · [充值] · 充值 · [控制台] · 控制台 · 2/4 个平台已获取 · [配置文件] · 配置文件 · [退出] · 退出
```

### 其余验收

- `bash run-local.sh`：CDHash 校验通过 `58177a9ad6ba35550ba8a5fa8ba9bf1bc69482c7`，已安装并运行（PID 51481）
- `--menu-test`：MENU-TEST PASS
- `--env-test`：ENV-TEST PASS（`.env` 600）
- `--settings-save-test`：SAVE-TEST PASS（deepseek.lowWarn 改 7 读回 7.0，原 config.json 已恢复）
- 成图：`build/shots/list-zhipu-2line.png` —— 智谱行主行 `¥0.20`（状态点黄，低于 lowWarn=1），副行 `glm-5.3-flash 36.9m · 充值 10.00 · 已用 9.80`

### 说明

- 实测值：现金 ¥0.20 与预期一致；token 资源包 36.9m，略低于 15:00 记录的 42m（用量正常消耗，量级一致）。

---

## ✅ 交付记录（2026-10-08 18:02，布迪执行）｜菜单栏去掉图标，只留金额

### 改动文件清单

| 文件 | 改动 |
|---|---|
| `Sources/BalanceBar/App.swift` | 删掉 `StatusTitleRender`（整块，不再需要）；删掉 `markImage` 懒加载；状态项初始化改为 `image = nil` + `imagePosition = .noImage`（原 `.imageLeading` + `imageHugsTitle`）；`updateTitle()` 简化为「每次刷新都清 image + 标题 = `statusTitle()` 原样」；新增 `debugStatusButton` 供无头自检 |
| `Sources/BalanceBar/main.swift` | `--icon-test` 里删掉「菜单栏排布 7 例」块（依赖已删的 `StatusTitleRender`），`ok` 去掉 `statusOK`；新增 `--statusbar-test` 模式（起真实 `StatusBarController`，首帧 + 刷新后各断言一遍） |
| `Sources/BalanceBar/AppIcon.swift` | 注释更正：几何只供「① .icns ② 面板头部」两处，注明菜单栏不挂标记 |
| `HANDOFF.md` | 第 9 节 9.1 标题改「一处几何，两处显示」、表里删掉菜单栏行；9.2 整节重写为「菜单栏状态项只显示金额，不挂图标」；9.3 补 `--statusbar-test` 输出与校验点；9.4 加一条「验证没挂图标要真跑」的坑；第 5.4 节加 ⑤c；文件地图改「十一个无头模式」、`App.swift` 描述去掉 `StatusTitleRender`；功能表那一行同步 |
| `build/shots/menubar-amount-only.png` | 菜单栏成图（新增，非源码） |
| `build/shots/list-with-icon.png` | 面板成图重出（确认头部标记未受影响） |

**面板头部标记与 App 图标不受影响**，只动了菜单栏状态项。

### ① `--statusbar-test`（新增，原样）

```
STATUSBAR-TEST | 首帧 标题=「余额」 图标=无
STATUSBAR-TEST | 刷新后 标题=「¥5.95」 statusTitle()=「¥5.95」 图标=无 imagePosition=0
STATUSBAR-TEST | 头部件 14pt 标记仍可用=true（面板头部不受影响）
STATUSBAR-TEST PASS（顶部状态栏只显示金额、无图标）
```

### ② 其余自检（原样末行）

```
── --icon-test            ICON-TEST | 系统解析图标=(32.0, 32.0) 与自绘像素差=9.12/255 → 一致
                          ICON-TEST PASS
── --menu-test            MENU-TEST PASS（粘贴 ⌘V / 拷贝 ⌘C / 退出 ⌘Q 已注册）
── --env-test             落盘权限: 600（期望 600） → ENV-TEST PASS
── --settings-save-test   已恢复原 config.json（1707 字节） → SAVE-TEST PASS
── --ui-test              UI 智谱双行 → ZHIPU-2LINE PASS
                          UI 头部图标 | 找到=true 尺寸=(14.0, 14.0) → ICON-VIEW PASS
                          UI 设置页白名单 → WHITELIST-TEST PASS
                          UI 粘贴链路 → PASTE-TEST PASS
```

### ③ 安装

`bash run-local.sh`：CDHash 校验通过 `3755ce533b540e5183049e03e4afd023fbbfcd9b`，已安装并运行（PID 67979）

### ④ 成图

- `build/shots/menubar-amount-only.png` —— 菜单栏实况：`¥5.95`，前面**没有**任何标记（此前是「¥」标记 + 5.95）
- `build/shots/list-with-icon.png` —— 面板头部标记照旧在（`¥ 余额看板`），布局高度未变

---

## ✅ 交付记录（2026-10-08 18:50，布迪执行）｜DeepSeek 峰时 / 非峰时标签

### 改动文件清单

| 文件 | 改动 |
|---|---|
| `Sources/BalanceBar/PeakPricing.swift` | **新增**。峰谷判定唯一出口：时段窗口 `windows`、法定节假日表 `holidays`（按年分组，内置 2026）、`isPeak(_:)` / `isHoliday` / `isWeekend` / `offPeakReason` / `nextChange(after:)` / `state(at:)`（文案 + tooltip）/ `summary(at:)`；`calendar` 固定 Asia/Shanghai；`frozenNow` 仅 `--preview` 用 |
| `Sources/BalanceBar/Config.swift` | `ProviderMeta` 加 `peakPricing: Bool = false`；deepseek 行置 `true` |
| `Sources/BalanceBar/Providers.swift` | `BalanceResult` **末尾**追加 `showsPeakPricing: Bool = false`；`fetch()` 在 meta 命中后统一赋值（缺 key / link 型 / 失败路径都带上） |
| `Sources/BalanceBar/Panel.swift` | 新增 `PeakChip`（高 16pt / 内边距 4pt / 圆角 4 / 1px 描边 / 白底）；`ProviderRow` 第一行在名称右侧挂 chip（间距 4pt）；`apply()` 先 `peakChip?.refreshNow()`；首帧骨架行也带上标记 |
| `Sources/BalanceBar/App.swift` | `StatusBarController` 加 `peakTimer` + `schedulePeakTimer()`：一次性排到 `PeakPricing.nextChange()` 的真实切换时刻，到点只 `store.notify()`（不发请求）并排下一次；`didBecomeActive` 时一并重排 |
| `Sources/BalanceBar/main.swift` | `--probe` 增加「峰谷:」行（仅峰谷平台）；新增 `--peak-test`（28 例判定 + 7 例切换 + 文案断言，每条用例带期望星期）；新增 `--peak-switch-test`（定型 → notify → 断言翻转）；`--ui-test` 增加 `PEAK-CHIP` 断言；`--preview` 支持 `--peak-now` 定格时刻出图 |
| `HANDOFF.md` | 功能表加一行；文件地图加 `PeakPricing.swift`、模式数改「十四个」；5.4 加 ⑤d/⑤e 与 ⑦b；**新增第 10 节「DeepSeek 峰谷标签」**（依据来源 / 口径选择 / 展示规格 / 更新逻辑表 / 验收 / 坑），原「做完之后」顺延为第 11 节 |
| `build/shots/list-peak-on.png` `list-peak-offpeak.png` | 两种标签状态的成图（新增，非源码） |

### 判定规则（口径与官方原文一致）

- 来源：官方价目表脚注 2 —— *Peak hours are 01:00 - 04:00 and 06:00 - 10:00 UTC, Monday through Friday, excluding Chinese public holidays. All other hours are off-peak, including weekends and Chinese public holidays in full.*
- 换算北京时间：**峰时 = 工作日 09:00–12:00、14:00–18:00**；其余全部谷时；谷时价 = 峰时的一半。
- 区间左闭右开：09:00 起峰时，**12:00 整即转谷时**；14:00 起，18:00 整转谷时。
- 法定节假日表来自国办发明电〔2025〕7号（元旦 1/1–3、春节 2/15–23、清明 4/4–6、劳动节 5/1–5、端午 6/19–21、中秋 9/25–27、国庆 10/1–7）。
- 两处刻意口径：**调休上班的周六仍算谷时**（官方写 Monday through Friday 且含 weekends）；**法定节假日整天谷时**。

### 展示规格

| 项 | 值 |
|---|---|
| 位置 | `● DeepSeek [非峰时] ……… ¥5.75` —— 第一行名称右侧，间距 4pt |
| 尺寸 | 高 16pt、左右内边距 4pt、圆角 4、1px 描边、纯白底 |
| 文案 | `峰时` / `非峰时` |
| 峰时 | 描边 `D.ink` #121214 + 文字 `D.ink` + medium（压重，提示按高峰价计费） |
| 非峰时 | 描边 `D.line` #ECECEE + 文字 `D.inkFaint` #9E9EA6 + regular（安静，不抢视线） |
| tooltip | 时段规则 + 豁免原因（周末/节假日）+ 下次切换具体时刻 |

### 更新逻辑

标签值**不写进 `BalanceResult`**，每次渲染按当前时刻现算（`PeakPricing.state(at:)`），所以不存在过期值。触发点：网络刷新（默认 600s）→ `notify` → `render` → `apply`；打开面板；设置页保存；以及**时段正点切换**——`schedulePeakTimer()` 一次性排到 `nextChange()` 返回的真实时刻，到点只 `notify()`（不发网络请求）再排下一次。定时器只保证"准时"：休眠错过也会在下一帧渲染自对齐。

### ① `--peak-test`（原样）

```
PEAK-TEST | 峰谷判定 28 例 → 全部符合
PEAK-TEST | 下次切换 7 例 → 全部符合
PEAK-TEST | 当前（10/8（周四）18:48）= 非峰时
PEAK-TEST | 提示 =
           低谷时段：非高峰时段、周末、法定节假日全天
           当前按低谷价计费（高峰价的一半）
           下次切换：10/9（周五）09:00
PEAK-TEST | 摘要 = 非峰时（工作日 09:00–12:00 / 14:00–18:00 为峰时）· 下次切换 10/9（周五）09:00
PEAK-TEST PASS
```

28 例覆盖：四个窗口边界（含 12:00 / 18:00 整点）、普通工作日、周六周日、7 个法定节假日、节假日前后一天、调休周六；7 例下次切换含「周五 18:30 → 跳过整个周末到周一 09:00」「国庆末日 → 节后首个工作日」。

### ② `--peak-switch-test`（原样）

```
PEAK-SWITCH | 定格周三 22:00（谷时）→ 标签=非峰时
PEAK-SWITCH | 定格周三 10:00（峰时）+ notify() → 标签=峰时
PEAK-SWITCH | 定格周六 09:00（周末谷时）+ notify() → 标签=非峰时
PEAK-SWITCH PASS（切换时 notify 即可刷新标签，无需重新请求接口）
```

日志同步留痕（App 自己写的 `last-run.log`）：

```
10-08 18:48:03  DeepSeek → 非峰时
10-08 18:48:04  DeepSeek → 峰时
10-08 18:48:05  DeepSeek → 非峰时
```

### ③ `--ui-test`（关键行，原样）

```
UI 列表页 刷新后 | size=(400.0, 356.0) | … · DeepSeek · 非峰时 · ¥5.75 · 充值 1.24 · 赠送 4.50 · …
UI 智谱双行 | 现金行=true token行=true → ZHIPU-2LINE PASS
UI 峰谷标签 | deepseek 标签数=1 文案=非峰时 → PEAK-CHIP PASS
UI 头部图标 | 找到=true 尺寸=(14.0, 14.0) → ICON-VIEW PASS
UI 设置页白名单 | 违规=无 mimo=true 控制台行=4 → WHITELIST-TEST PASS
UI 粘贴链路 | paste: 分发=true 密文框=true 字段长度=17 → PASTE-TEST PASS
```

**面板高度仍是 356**，加标签没有引起布局跳动。

### ④ `--probe`（原样，仅 deepseek 多一行）

```
deepseek OK ¥5.75 CNY 充值 1.24 · 赠送 4.50
             峰谷: 非峰时（工作日 09:00–12:00 / 14:00–18:00 为峰时）· 下次切换 10/9（周五）09:00
             充值: https://platform.deepseek.com/top_up
```

### 其余验收

- `--icon-test` ICON-TEST PASS｜`--statusbar-test` STATUSBAR-TEST PASS｜`--menu-test` MENU-TEST PASS｜`--env-test` ENV-TEST PASS｜`--settings-save-test` SAVE-TEST PASS
- `bash run-local.sh`：CDHash 校验通过 `0a8823c3e91fddacf8d50f3c9e26e618d74301c4`，已安装并运行（PID 75003）
- 成图：`build/shots/list-peak-on.png`（定格周三 10:00 → `[峰时]` 深色描边）、`build/shots/list-peak-offpeak.png`（真实时间 18:42 → `[非峰时]` 浅灰）

### 说明

- 实时状态：2026-10-08 18:48 为**非峰时**，下次切换 10/9（周五）09:00。谷时价 = 峰时价的一半。
- `--peak-now` 只影响标签的显示时刻，其余一切（余额、涨跌、日志）仍走真实时间，是纯出图/自检开关，生产路径恒为 nil。
- ⚠️ 需人工维护：法定节假日表按年内置，国务院发次年通知后（通常 11 月）补 `PeakPricing.holidays`。不补也不会崩，只是不再豁免节假日。
