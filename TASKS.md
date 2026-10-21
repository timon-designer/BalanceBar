# BalanceBar 待办（交给 WorkBuddy 执行）

> 分工：这个项目的**代码全部在 WorkBuddy 内写**。Hermes 只负责调研、搜索、审查、打包、上下文交接。
> 完整背景见同目录 `HANDOFF.md`；铁律见技能 `balancebar-project`。
> 已完成的任务保留在文末归档，正文只列未做的。

---

## TASK-03（P2，等用户确认）

设置页还缺 `refreshSeconds` / `menuTitle` / `lowWarn` 的编辑入口（HANDOFF.md 第 2 节已记）。
**先问用户要不要，不要自己开做。**

---

## 完成后要交回的东西
1. `--probe` / `--ui-test` / `--menu-test` 的**真实输出**（贴原文，不要复述）。
2. 更新 `HANDOFF.md`：对应条目移进「已完成」，本文件对应任务标注 `[x]` 已完成。
3. 告诉用户还差他本人提供什么（智谱 `GLM_API_KEY`、中转站地址 + key —— 现在应能在设置页里直接填）。

---

## [x] TASK-03（P2）设置页补通用设置入口 —— 2026-09-24 已完成（用户确认要做）

> 设置页顶部新增「通用」区块：刷新间隔(秒) / 菜单栏标题，保存即生效
> （`balancebar.configSaved` 通知 → 定时器立刻重排）；`lowWarn`（低余额阈值）按平台进
> `ProviderMeta.extras`，每个平台区块里可直接改。
> 实测：`--ui-test` dump 出现 `通用 · 刷新间隔(秒) · 600 · 菜单栏标题 · auto` 与各平台「低余额阈值」行。

---

## 归档

### [x] TASK-01（P0）BUG：设置页输入框粘不进 key —— 2026-09-24 已完成

原规格：补 `NSApp.mainMenu`（编辑菜单 ⌘Z/⌘⇧Z/⌘X/⌘C/⌘V/⌘A + 应用菜单 ⌘Q）、输入框右键菜单、
确认 `NSSecureTextField` 可粘贴；顺带把 `.env` 从 644 收紧到 600。

落地与验收：
- `App.swift` 新增 `AppMenus.install()`（App 启动 + 全部无头自检模式都调用）；
  `FieldShell.menu(for:)` 挂右键菜单（剪切/拷贝/粘贴/全选，nil target 走 responder chain）。
- `KeyStore.enforcePermissions()`：`.env` 600、`~/.balancebar/` 700，启动与每次写入都收紧；
  `--env-test` 增加 600 断言。
- 新增 `--menu-test`（列主菜单 + 键等价物，断言 ⌘V/⌘C/⌘Q 已注册）；
  `--ui-test` 末尾增加真实粘贴链路断言（假 key 经 `paste:` action 进密文框，长度断言）。
- 实测：`MENU-TEST PASS`、`PASTE-TEST PASS`（字段长度 17 = 假 key 长度）、`ENV-TEST PASS`。
- ⚠️ 无头环境里 borderless 窗口成不了 key window，粘贴断言走「直递字段编辑器」兜底；
  真实使用时用户点开的 popover 是 key window，⌘V 走正常 keyWindow 链。

### [x] TASK-02（P1）：把 GitHub 上找到的现成项目的思路整合进来 —— 2026-09-24 已完成

> 只借思路，未引入任何外部依赖、未拷贝第三方源码。

| 借自 | 落点 | 状态 |
|---|---|---|
| dsh-api-balance | PROVIDERS 表驱动 → `Config.swift` 的 `ProviderMeta.table`（type → 字段/默认地址/额外参数/适配器闭包），`Settings.swift` 全部按表派生 | ✅ `grep` 无按 type 硬编码分支 |
| dsh-api-balance | 余额 + 用量 → `BalanceResult.usage`，行内 detail 后缀 + `--probe` 单独一行；无用量接口的平台不渲染 | ✅ 代码就绪，OpenRouter/relay 需用户 key 实测 |
| dsh-api-balance | extraParams → 设置页自动渲染 `relayUnit` / `relayDivisor` 并写盘 | ✅ `--settings-save-test` 改 relayDivisor 端到端 PASS |
| one-api-hub | 站点类型识别 → relay detail 回显 `billing/subscription · one-api/new-api 系` / `api/user/self · new-api 系`，含 used_quota | ✅ 代码就绪，需真实中转站验证 |
| one-api-hub | 聚合余额 + 已用量 → 同上（used_quota ÷ relayDivisor） | ✅ 同上 |
| CodexBar | 禁止假百分比/占位 → 全工程 `grep` 无 `100%`/`0%`/`.percent`；无接口平台显示「—」而非报错 | ✅ |
| quota-bar | 仅作对照，视觉仍按黑白灰 / 4px 网格规范，未抄配色排版 | ✅ |
| new-api-checker | 查询站点的模型限制 | ⏸ P2 暂缓 |
