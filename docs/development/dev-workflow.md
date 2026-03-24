# 开发环境工作流

> 面向开发者：使用 Multipass VM 的日常开发、调试、workspace 文件修改操作指南。

---

## 前置条件

```bash
# 安装 Multipass（Ubuntu）
sudo snap install multipass
```

---

## 日常启动

```bash
# 创建开发 VM（首次运行自动复制 .env.example → .env）
./cli/dev.sh launch

# 指定团队
./cli/dev.sh launch --team hermes

# 自定义资源
./cli/dev.sh launch --cpus 4 --memory 8G --disk 40G
```

进入 VM：

```bash
./cli/dev.sh shell
# 或直接
multipass shell muliao-<team>
```

启动 OpenClaw gateway：

```bash
./cli/dev.sh gateway
```

查看 cloud-init 初始化进度（首次启动约 3-5 分钟）：

```bash
multipass exec muliao-<team> -- tail -f /var/log/cloud-init-output.log
```

---

## workspace 文件热更新

`teams/<name>/` 通过 Multipass mount 双向共享到 VM 内 `/home/muliao/.openclaw`，**宿主机的文件修改立即反映到 VM 内**。

| 文件类型 | 生效时机 | 是否需要重启 gateway |
|---------|---------|---------------------|
| `workspace/SOUL.md`、`IDENTITY.md`、`USER.md` 等人格文件 | 下一次**新 session** 第一条消息时 | ❌ 不需要 |
| `workspace/memory/` 下的记忆文件 | 下一次**新 session** 第一条消息时 | ❌ 不需要 |
| `workspace/skills/` 下的 Skill 文件 | 当前 session 的**下一个回复**（watcher 默认开启） | ❌ 不需要 |
| `openclaw.json`（Agent 配置、模型、渠道） | 需要重启 gateway | ✅ 重新执行 `dev.sh gateway` |

> **原理**：OpenClaw 在新 session 的**第一条消息**时将 workspace 文件内容注入 agent context（[官方文档](https://docs.openclaw.ai/concepts/agent#bootstrap-files-injected)）。因此 SOUL.md 等文件的改动需要等到**下一次新 session 开始**才生效——当前 session 进行中修改文件不会即时生效，需要开启新的对话。
>
> Skills 的生效时机更快：OpenClaw 默认开启文件监听（`skills.load.watch: true`），`SKILL.md` 变更后会自动刷新 skills 快照，**当前 session 的下一个回复就能生效**，无需新开 session（[官方文档](https://docs.openclaw.ai/tools/skills#skills-watcher-auto-refresh)）。

---

## 环境变量

每个团队一份 `.env`：

```bash
# 首次初始化（dev.sh launch 也会自动执行）
cp .env.example teams/<name>/.env
# 编辑 .env，填入 API Key、Bot Token 等
```

> ⚠️ **`.env.example` 已纳入版本管理**，只能放占位注释，绝对不能写入真实 Key。真实 Key 只写到 `.env`（已在 `.gitignore` 中排除）。

`dev.sh gateway` 会自动读取 `teams/<name>/.env` 并注入为 VM 内的环境变量。

---

## 目录结构

```
teams/
  <name>/          ←── 通过 Multipass mount 共享到 VM 内 /home/muliao/.openclaw
    .env           # 团队配置（API keys、tokens）
    openclaw.json  # Agent 配置（模型、渠道、权限）
    workspace/
      SOUL.md      # 人格定义（热更新生效）
      IDENTITY.md  # 身份信息（热更新生效）
      memory/      # 对话记忆（热更新生效）
      skills/      # 自定义 Skill（热更新生效）
    credentials/   # 各渠道 pairing / allowFrom 配置（Slack、Telegram 等）
    agents/
      main/
        sessions/  # 对话历史
```

---

## VM 管理

```bash
# 停止 VM（保留数据）
./cli/dev.sh stop

# 启动已停止的 VM
./cli/dev.sh start

# 删除 VM（teams/ 数据不会丢失，仅删除 VM 本身）
./cli/dev.sh delete

# 列出所有 Muliao VM
./cli/dev.sh list
```

---

## cloud-init 模板

开发 VM 和 RPi 共享同一份 base cloud-init 模板（`deploy/cloud-init/base-user-data.yaml`），通过不同的 overlay 添加场景特有配置：

```
deploy/cloud-init/
  base-user-data.yaml     # 共享基础：Node.js、OpenClaw、系统依赖、Docker（Agent Sandbox）
  dev-overlay.yaml         # 开发 VM：简化主机名、开发工具
  rpi-overlay.yaml         # RPi：Tailscale、序列号主机名、mDNS
  render.sh                # 合并工具：base + overlay → 最终 user-data
```

修改 base 模板会同时影响开发 VM 和 RPi——这正是统一环境的目的。
