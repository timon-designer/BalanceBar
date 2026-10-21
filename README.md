# 余额看板 BalanceBar

macOS 菜单栏常驻小面板：一屏看所有大模型 API 的余额，点一下就进充值页。

- 菜单栏文字 = 各平台余额合计（可改成最低余额/单平台）
- 点图标 → 面板列出每个平台：状态点 · 余额 · 详情 · 「充值」「控制台」按钮
- 后台每 10 分钟自动刷新（`refreshSeconds` 可调）

## 已接入的平台与接口

| 平台 | 类型 `type` | 余额接口 | 备注 |
|---|---|---|---|
| DeepSeek | `deepseek` | `GET {base}/user/balance` | 官方接口，CNY |
| 智谱 GLM | `zhipu` | `GET {base}/api/biz/customer/account/getUserAccount`（备选 `/api/monitor/usage/quota/limit`） | 两个接口都探测，取到余额即止 |
| 阿里云百炼 | `aliyun` | 无按 key 查余额的官方接口 → 用 BSS `QueryAccountBalance`（需 AccessKey ID/Secret） | 不填 AK/SK 时降级为「点开控制台」 |
| 第三方中转站 | `relay` | ① `GET {base}/v1/dashboard/billing/subscription` + `/v1/dashboard/billing/usage` ② `GET {base}/api/user/self` | 自动按顺序探测，命中即用（new-api / one-api 系通吃） |
| Kimi / Moonshot | `moonshot` | `GET {base}/v1/users/me/balance` | 默认关闭 |
| 硅基流动 | `siliconflow` | `GET {base}/v1/user/info` | 默认关闭 |
| OpenRouter | `openrouter` | `GET {base}/api/v1/credits` | 默认关闭（记账用 management key） |
| 任意链接 | `link` | 无 | 只显示一个可点开的入口 |

## Key 放哪

App 按顺序找 key：**进程环境变量 → `~/.balancebar/.env` → `~/.hermes/.env`**。
DeepSeek / 百炼的 key 已经在 `~/.hermes/.env` 里，直接就能用。

要新加 key，填 `~/.balancebar/.env`：

```bash
GLM_API_KEY=xxxx          # 智谱 open.bigmodel.cn 的 API Key
RELAY_API_KEY=sk-xxxx     # 中转站给你的 key
```

key 每次刷新时重新读取，改完点面板里的「刷新」即可，不用重启。

## 配置文件

`~/.balancebar/config.json`（首次运行自动生成，面板底部「配置文件」按钮可直接打开）

```json
{
  "refreshSeconds": 600,          // 刷新间隔（秒）
  "menuTitle": "auto",            // auto=合计 | min=最低余额 | <provider id>=单平台
  "providers": [
    {
      "id": "relay",              // 唯一标识
      "name": "第三方中转站",       // 面板显示名
      "type": "relay",            // 见上表
      "enabled": true,            // 填好再开
      "apiKeyEnv": "RELAY_API_KEY",
      "baseURL": "https://api.xxx.com",   // 站点根地址，不要带 /v1
      "rechargeURL": "https://api.xxx.com/topup",   // 「充值」按钮跳这里
      "consoleURL": "https://api.xxx.com/console",  // 「控制台」按钮跳这里
      "lowWarn": 10               // 低于该值状态点变黄
    }
  ]
}
```

新增平台 = 复制一段 provider；已有适配器换个 `baseURL` 就能复用。

## 自检 / 排障

```bash
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --probe        # 命令行打印各平台余额
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --probe --only relay
"/Applications/余额看板.app/Contents/MacOS/BalanceBar" --ui-test      # 验证面板能正常构建布局
cat ~/.balancebar/last-run.log                                        # App 每次刷新的结果
```

状态点含义：🟢 正常 · 🟡 余额偏低或缺 key · ⚪ 只能点开看 · 🔴 接口报错（面板上会写原因）。

## 构建 / 安装 / 自启

```bash
bash run-local.sh          # 构建 → 组装 .app → 安装到 /Applications → 校验 → 启动
bash autostart.sh on|off|status   # 开机自启
```

## 已知限制

- **阿里云百炼**没有按 API key 查余额的官方接口，余额挂在阿里云账户上。填 `accessKeyId`/`accessKeySecret`（阿里云 AccessKey，需 `AliyunBSSReadOnlyAccess` 权限）才能自动查；否则只能点开控制台。
- **中转站**的余额口径由站点决定：`/v1/dashboard/billing/subscription` 返回的 `hard_limit_usd` 是去除已用的剩余额度；若站点用 quota 计数，用 `relayDivisor`（默认 500000）换算，`relayUnit` 可写 `CNY`/`USD`/`quota`。
- 本机 Xcode 工具链（Swift 6.3）与 CLT SDK（6.4）版本不匹配，`run-local.sh` 里优先用 CLT 工具链 + CLT SDK 这套自洽组合构建。
