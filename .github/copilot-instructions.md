# Muliao — Workspace Instructions

**Muliao** 是一个研究型仓库，探索如何用 **OpenClaw**（及类似框架）构建对**普通人更友好**的 AI 助手。

灵感来自 OpenClaw 在社区掀起的热潮——这里记录配置方案、Skill 实验和自动化计划，为"让 AI 助手真正走入日常生活"积累可复用的经验。

> 项目背景与设计理念：见 [docs/design.md](../docs/design.md)；用户向 README：见 [readme.md](../readme.md)。

---

## 仓库结构

```
.github/
  copilot-instructions.md   # 本文件：AI agent 工作指引
  prompts/
    commit.prompt.md        # /commit — 生成中文 Conventional Commit message
    fix-md.prompt.md        # /fix-md — 修复 Markdown 格式 warning/error
    plan/
      个人研究助手.prompt.md  # /个人研究助手 — arXiv 论文搜索助手规划方案
docker/
  Dockerfile                # 运行镜像定义
  build.sh                  # 构建脚本
  run.sh                    # 启动脚本（--team NAME 选择团队）
docs/
  design.md                 # 项目设计理念、能力要点、推进路线（详细版）
teams/                      # ← .gitignore，不纳入版本管理
  <team-name>/
    config/                 # 运行时状态（credentials、sessions、logs）
    workspace/              # 团队的 git repo（SOUL.md、IDENTITY.md、memory/ 等）
readme.md                   # 项目简介（面向用户）
```

> Muliao 是脚手架项目：提供 Docker 脚本和文档，团队数据（`teams/`）整体 gitignore。
> 每个团队的 `workspace/` 是独立的 git repo，可推到各自的 remote。

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
