# 环境变量参考

> 模板文件：[.env.example](../../.env.example)

## 使用方式

每个团队一份完整的 `.env`，所有配置都在同一个文件里：

```bash
cp .env.example teams/hermes/.env
vim teams/hermes/.env              # 填入 API keys 等
./cli/dev.sh launch --team hermes  # 启动开发 VM
```

`dev.sh launch --team <name>` 首次运行时会自动从 `.env.example` 复制。

| 文件 | 说明 |
|------|------|
| `.env.example` | 模板，包含所有可配项和注释；入库 |
| `teams/<name>/.env` | 团队的完整配置文件；gitignore |

---

## 变量说明

### 系统

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `TZ` | 宿主机时区 | 系统时区 |

### AI API Keys

至少配置一个 LLM provider，OpenClaw 才能工作。

| 变量 | 获取地址 |
|------|----------|
| `ANTHROPIC_API_KEY` | https://console.anthropic.com/ |
| `OPENAI_API_KEY` | https://platform.openai.com/api-keys |
| `DEEPSEEK_API_KEY` | https://platform.deepseek.com/ |

### IM Bot Tokens

按需配置，连接哪个平台就填哪个。

| 变量 | 格式 | 说明 |
|------|------|------|
| `TELEGRAM_BOT_TOKEN` | `123456:ABC-DEF...` | BotFather 生成的 Bot Token |
| `DISCORD_BOT_TOKEN` | 长字符串 | Discord Developer Portal → Bot → Token |
| `SLACK_BOT_TOKEN` | `xoxb-...` | Bot User OAuth Token |
| `SLACK_APP_TOKEN` | `xapp-1-...` | App-Level Token（Socket Mode 必需，scope: `connections:write`）|

> 详细配置指南：
> - Telegram: [OpenClaw 文档](https://docs.openclaw.ai/channels/telegram)
> - Discord: [OpenClaw 文档](https://docs.openclaw.ai/channels/discord)
> - Slack: [Slack Socket Mode 配置](../../docs/openclaw/slack-socket-mode.md)

### Gateway

| 变量 | 说明 |
|------|------|
| `OPENCLAW_GATEWAY_TOKEN` | 可选；设置后远程访问 Gateway 需要此 token 认证 |

### RPi 部署

以下变量仅在 `deploy/rpi/flash-ssd.sh` 烧录时读取，不影响运行时。

| 变量 | 默认值 | CLI 等效 | 说明 |
|------|--------|----------|------|
| `TAILSCALE_AUTHKEY` | — | `--tailscale-key` | Tailscale pre-auth key；从 [admin console](https://login.tailscale.com/admin/settings/keys) 生成，建议勾选 Reusable |
| `HOSTNAME_PREFIX` | 与团队名相同 | `--hostname-prefix` | 主机名前缀；自动追加 RPi 序列号后 4 位（如 `hermes-a1b2`）|
| `TIMEZONE` | 回退读 `TZ`；再回退读 `/etc/timezone` | `--timezone` | RPi 系统时区；仅影响 cloud-init |
| `HDMI_RESOLUTION` | `800x480` | `--resolution` | HDMI 输出分辨率；预设 `720p`/`1080p`/`2k`/`4k` 或自定义 `WxH` |

---

## 典型新团队流程

```bash
# 1. 复制模板
cp .env.example teams/hermes/.env

# 2. 编辑，填入 API keys、Bot tokens、Tailscale key 等
vim teams/hermes/.env

# 3. 本地测试
cli/dev.sh launch --team hermes

# 4. 烧录 RPi（所有配置从 .env 读取）
sudo flash-ssd.sh /dev/sda --team hermes

# 5. RPi 启动后部署团队数据
deploy-team.sh hermes-a1b2 --team hermes --start
```
