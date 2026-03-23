# Muliao — Workspace Instructions

**Muliao** 是一个研究型仓库，探索如何用 **OpenClaw**（及类似框架）构建对**普通人更友好**的 AI 助手。

灵感来自 OpenClaw 在社区掀起的热潮——这里记录配置方案、Skill 实验和自动化计划，为"让 AI 助手真正走入日常生活"积累可复用的经验。

> 项目背景与设计理念：见 [docs/design.md](../docs/design.md)；用户向 README：见 [readme.md](../readme.md)。

---

## 仓库结构

```
.github/
  copilot-instructions.md     # 本文件：AI agent 工作指引
  prompts/
    commit.prompt.md          # /commit — 生成中文 Conventional Commit message
    fix-md.prompt.md          # /fix-md — 修复 Markdown 格式 warning/error
    plan/                     # 规划类 prompt
cli/
  backup.sh                   # 团队 workspace 备份/恢复工具
docker/
  Dockerfile                  # 运行镜像（node:24 + OpenClaw + 中文字体 + 浏览器依赖）
  build.sh                    # 构建脚本（支持多平台 buildx）
  run.sh                      # 启动脚本（--team, --gateway, --no-browser 等）
  entrypoint.sh               # UID/GID 动态映射（PUID/PGID）
docs/
  design.md                   # 技术设计：8 维差异化、优先级、路线图
  business-model.md           # 三层商业模式：开源中间件 → 自给 → 垂直 SaaS
  target-customers.md         # 四类用户画像与场景映射
  design/
    natural-growth.md         # HR 驱动的团队级进化机制
  deploy/
    RPi 5 部署方案.prompt.md  # 树莓派硬件方案 + PWA Relay 架构
  scenarios/
    research-assistant/       # 论文追踪助手分阶段实施方案
readme.md                     # 项目简介（面向用户）
teams/                        # ← .gitignore，不纳入版本管理（OpenClaw 运行时数据）
```

> Muliao 是脚手架项目：提供 Docker 脚本和文档，团队数据（`teams/`）整体 gitignore。
> 每个团队的 `workspace/` 是独立的 git repo，可推到各自的 remote。

---

## 构建与运行

### Docker

```bash
# 构建镜像（当前平台）
./docker/build.sh
# 多平台构建并推送
./docker/build.sh --push
# 指定 Node 版本
./docker/build.sh --node 22

# 启动交互 bash
./docker/run.sh
# 启动 OpenClaw Gateway
./docker/run.sh --gateway
# 指定团队
./docker/run.sh --team hermes
# 轻量模式（无浏览器）
./docker/run.sh --no-browser
```

关键环境变量：`PUID` / `PGID`（UID/GID 映射，默认 1000）。

### 备份/恢复

```bash
cli/backup.sh backup [--team NAME]        # 备份 workspace → teams/.backups/
cli/backup.sh restore <file> [--team NAME] # 从 zip 恢复
cli/backup.sh list [--team NAME]          # 列出可用备份
```

---

## 文档索引

> 回答时引用设计细节请**链接到对应文档**，不要将长段内容复制到对话里。

| 文档 | 主题 |
|------|------|
| [readme.md](../readme.md) | 项目愿景、核心理念、能力概览 |
| [docs/design.md](../docs/design.md) | 技术架构、与 OpenClaw 的差异化定位、开发优先级 |
| [docs/business-model.md](../docs/business-model.md) | 三层商业模式、MVP 验证策略 |
| [docs/target-customers.md](../docs/target-customers.md) | 四类用户画像（丽姐/文哲/小雅/老陈） |
| [docs/design/natural-growth.md](../docs/design/natural-growth.md) | 团队自然成长机制（观察反馈、经验迁移、审批变更） |
| [docs/deploy/RPi 5 部署方案.prompt.md](../docs/deploy/RPi%205%20部署方案.prompt.md) | 树莓派消费级硬件方案、WebSocket Relay |

---

## 技术要点

- **无 package.json**：项目根目录没有 Node 项目文件，依赖在 Docker 容器内通过 `npm install -g openclaw@latest` 管理
- **无 CI/CD**：当前手动构建/部署，使用 Docker 脚本
- **Dev Container**：`.devcontainer.json` 存在，`remoteUser: "node"`
- **teams/ 是运行时数据**：包含 credentials、sessions、logs，整体 gitignore，不要修改或依赖其内容

---

## 核心领域知识

### OpenClaw

- 官网: https://openclaw.ai
- 文档: https://docs.openclaw.ai
- GitHub: https://github.com/openclaw/openclaw
- 社区 Discord: https://discord.com/invite/clawd

### ClawHub（Skill 社区）

> ⚠️ **重要**: ClawHub 的官方地址是 **https://clawhub.ai**。不要混淆其他非官方来源。

- ClawHub 是 OpenClaw 官方 Skill 发布和分发平台，当前收录 **29,000+** 个社区 Skill
- 安装 Skill 统一使用: `npx clawhub@latest install <skill-name>`
- 搜索 Skill: https://clawhub.ai/skills?q=<关键词>
- 查找 Skill 时，优先看 **下载量**（installs）和 **★ 星标数** 判断质量

---

## 开发约定

### Prompt 文件

- 所有 `.prompt.md` 文件放在 `.github/prompts/` 下
- 按用途分子目录（如 `plan/` 存放规划类）
- YAML frontmatter 必须包含 `description` 字段

### Commit Message

- 遵循 [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
- 描述用**中文**，type/scope 用英文
- 使用 `/commit` prompt 自动生成（见 `.github/prompts/commit.prompt.md`）

---

## AI Agent 行为准则

- **语言**：默认用**中文**回复；文件名、type/scope、代码、命令保持英文
- **链接而非嵌入**：回答中引用设计细节时，优先指向 `docs/design.md` 或 `readme.md`，不要将长段内容复制到对话里
- **只改被问到的内容**：这是研究/文档仓库，不要在未被要求时重构文档结构或添加额外章节
- **Skill 优先**：推荐 OpenClaw Skill 时，先查 ClawHub（下载量 + 星标），再考虑自定义
- **最小权限意识**：规划涉及邮件/日历/文件系统访问的方案时，明确提示需要哪些权限
