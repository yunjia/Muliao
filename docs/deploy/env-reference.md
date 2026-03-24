# 环境变量参考

> 模板文件：[.env.example](../../.env.example)
> 新团队上手：`cp .env.example teams/<name>/.env`，填好后即可用于所有脚本。

---

## 配置文件位置与优先级

| 文件 | 用途 |
|------|------|
| `.env.example` | 模板，包含所有可配项和注释；入库 |
| `.env` | 根目录配置，所有团队共享的默认值；gitignore |
| `teams/<name>/.env` | 团队级配置，覆盖根目录同名变量；gitignore |

**优先级**（越靠后越高）：

```
内置默认值 → .env（根目录）→ teams/<name>/.env → CLI 参数
```

---

## 容器运行时变量

以下变量由 `docker-compose.yml` 使用，通过 `docker/run.sh` 启动容器时生效。

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MULIAO_IMAGE` | `ghcr.io/muliaoio/muliao:latest` | Docker 镜像地址 |
| `MULIAO_CONTAINER_NAME` | `muliao` | 容器名称；`run.sh` 会自动追加团队名 |
| `MULIAO_DATA_DIR` | 开发机: `teams/<name>/`；RPi: `/home/muliao/.openclaw` | OpenClaw 运行时数据目录 |
| `TZ` | 宿主机时区 | 容器时区 |

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

---

## RPi 部署变量

以下变量仅在 `deploy/rpi/flash-ssd.sh` 烧录时读取，不影响 Docker 容器运行。
填好后 `flash-ssd.sh` 几乎不需要额外 CLI 参数。

| 变量 | 默认值 | CLI 等效 | 说明 |
|------|--------|----------|------|
| `TAILSCALE_AUTHKEY` | — | `--tailscale-key` | Tailscale pre-auth key；从 [admin console](https://login.tailscale.com/admin/settings/keys) 生成，建议勾选 Reusable |
| `GHCR_TOKEN` | — | `--ghcr-token` | GitHub Token（`packages:read` 权限）；RPi 首次启动拉取私有镜像用 |
| `HOSTNAME_PREFIX` | 与团队名相同 | `--hostname-prefix` | 主机名前缀；启动后自动追加 RPi 序列号后 4 位（如 `hermes-a1b2`）|
| `TIMEZONE` | 回退读 `TZ`；再回退读开发机 `/etc/timezone` | `--timezone` | RPi 系统时区；仅影响 cloud-init，不影响容器 |
| `HDMI_RESOLUTION` | `800x480` | `--resolution` | HDMI 输出分辨率；预设 `720p`/`1080p`/`2k`/`4k` 或自定义 `WxH` |

---

## 各脚本读取方式

### docker/run.sh

通过 `--team` 参数推导 `MULIAO_DATA_DIR` 和 `MULIAO_CONTAINER_NAME`，然后 `export` 为环境变量供 `docker compose` 使用。CLI 参数优先于 `.env` 文件。

```bash
docker/run.sh --team hermes          # 启动 hermes 团队
docker/run.sh --team hermes --build  # 重新构建镜像
```

### deploy/rpi/flash-ssd.sh

用 `_read_env_key()` 逐个从 `.env` 文件提取变量，三层覆盖：

```
.env（根目录）→ teams/<name>/.env → CLI 参数（最高）
```

填好 `teams/<name>/.env` 后：

```bash
flash-ssd.sh /dev/sda --team hermes   # 只需指定设备和团队
```

### deploy/rpi/deploy-team.sh

整文件查找 `.env`（`--env` > `teams/<name>/.env` > `.env`），然后通过 rsync 同步到 RPi。部署时自动将 `MULIAO_DATA_DIR` 改写为 RPi 路径。

```bash
deploy-team.sh hermes-a1b2 --team hermes --start
```

---

## 典型新团队流程

```bash
# 1. 复制模板
cp .env.example teams/hermes/.env

# 2. 编辑，填入 API keys、Bot tokens、Tailscale key 等
vim teams/hermes/.env

# 3. 本地测试
docker/run.sh --team hermes

# 4. 烧录 RPi（所有配置从 .env 读取）
sudo flash-ssd.sh /dev/sda --team hermes

# 5. RPi 启动后部署团队数据
deploy-team.sh hermes-a1b2 --team hermes --start
```
