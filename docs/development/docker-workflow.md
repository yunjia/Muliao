# Docker 开发流程

> 面向开发者：日常启动、调试、workspace 文件修改、镜像更新的操作指南。

---

## 日常启动

```bash
# 启动默认团队（首次运行自动复制 .env.example → .env）
./docker/run.sh

# 指定团队
./docker/run.sh --team hermes

# 强制重建容器（配置变更后使用）
./docker/run.sh --restart

# 本地重新构建镜像并启动（修改 Dockerfile 后使用）
./docker/run.sh --build
```

进入容器 bash：

```bash
docker compose exec openclaw bash
```

查看实时日志：

```bash
docker logs -f muliao-default
```

---

## workspace 文件热更新

`teams/<name>/` 整个目录通过 volume 挂载到容器内 `/home/muliao/.openclaw`，**宿主机的文件修改立即反映到容器内**，无需重启容器。

| 文件类型 | 生效时机 | 是否需要重启 |
|---------|---------|------------|
| `workspace/SOUL.md`、`IDENTITY.md`、`USER.md` 等人格文件 | 下一次**新 session** 第一条消息时 | ❌ 不需要 |
| `workspace/memory/` 下的记忆文件 | 下一次**新 session** 第一条消息时 | ❌ 不需要 |
| `workspace/skills/` 下的 Skill 文件 | 当前 session 的**下一个回复**（watcher 默认开启） | ❌ 不需要 |
| `openclaw.json`（Agent 配置、模型、渠道） | 需要重启 | ✅ `run.sh --restart` |
| `Dockerfile` 或系统依赖 | 需要重新构建镜像 | ✅ `run.sh --build` |

> **原理**：OpenClaw 在新 session 的**第一条消息**时将 workspace 文件内容注入 agent context（[官方文档](https://docs.openclaw.ai/concepts/agent#bootstrap-files-injected)）。因此 SOUL.md 等文件的改动需要等到**下一次新 session 开始**才生效——当前 session 进行中修改文件不会即时生效，需要开启新的对话。
>
> Skills 的生效时机更快：OpenClaw 默认开启文件监听（`skills.load.watch: true`），`SKILL.md` 变更后会自动刷新 skills 快照，**当前 session 的下一个回复就能生效**，无需新开 session（[官方文档](https://docs.openclaw.ai/tools/skills#skills-watcher-auto-refresh)）。

**注意**：当前没有文件监听进程（inotify/watch），是被动热更新而非主动推送。`docker-compose.yml` 中的 `watchtower` 服务是**镜像版本**的更新通知（monitor-only，不自动更新），与 workspace 文件无关。

---

## 环境变量

项目根目录的 `.env` 文件是唯一配置入口：

```bash
# 首次初始化（run.sh 也会自动执行）
cp .env.example .env
# 编辑 .env，填入 API Key、Bot Token 等
```

> ⚠️ **`.env.example` 已纳入版本管理**，只能放占位注释，绝对不能写入真实 Key。真实 Key 只写到 `.env`（已在 `.gitignore` 中排除）。

`run.sh --team <name>` 会自动将 `MULIAO_DATA_DIR` 设为 `teams/<name>/`，优先级高于 `.env` 中的配置。

---

## 目录结构

```
teams/
  <name>/          ←── MULIAO_DATA_DIR，挂载到容器内 /home/muliao/.openclaw
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

## 构建镜像

```bash
# 本地构建（当前平台）
./docker/build.sh

# 多平台构建并推送（amd64 + arm64）
./docker/build.sh --push

# 仅构建 ARM64（用于 RPi 验证）
./docker/build.sh --platform linux/arm64 --push

# 指定 Node 版本
./docker/build.sh --node 22
```

> **ARM64 本地 load 限制**：多平台同时 `--load` 到本地 daemon 不被 Docker 支持。本地开发只会 load 当前平台（amd64/arm64），多平台需配合 `--push` 推送到 registry。

> **`--build` 会自动重建容器**：`run.sh --build` 在构建完新镜像后，会用 `--force-recreate` 强制替换旧容器，确保新镜像立即生效，无需额外 `--restart`。
>
> **每次 `run.sh` 都会从 registry 拉取最新镜像**：`buildx --push` 只推送到 registry，本地 daemon 的镜像不会自动更新。`run.sh`（不带 `--build`）在启动前会先执行 `docker compose pull`，确保拿到 registry 最新版本。如需跳过拉取直接用本地镜像，请用 `--build`。

---

## 常见操作

```bash
# 停止容器
docker compose stop openclaw

# 完全清除容器（数据不丢失，teams/ 在宿主机）
docker compose down

# 手动触发 Cron Job 调试
docker compose exec openclaw openclaw cron run <job-id>
```
