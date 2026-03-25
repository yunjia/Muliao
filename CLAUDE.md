# CLAUDE.md — Muliao 工作指引

## 项目一句话

Muliao 是在 OpenClaw 之上构建「幕僚团队」的配置/脚本仓库，目标是让非技术用户也能拥有一支长期在线的 AI 助手团队。核心架构：Hermes（团队长 + HR）+ 专职幕僚 + 用户熟悉的 IM 入口。

详情见 [readme.md](readme.md) 和 [docs/design.md](docs/design.md)。

---

## 语言约定

- 回复默认用**中文**
- 文件名、type/scope、代码、命令、变量名保持**英文**

---

## 最重要的技术事实（代码里看不出来的）

- **根目录没有 package.json**：OpenClaw 不是本地依赖，通过 cloud-init 在 VM/RPi 内 `npm install -g openclaw@latest` 安装
- **没有 CI/CD**：所有部署都是手动执行脚本
- **`teams/` 整体 gitignore**：这是 OpenClaw 运行时目录（credentials、sessions、logs、workspace），不要读取、修改或依赖它的内容
- **两套环境共用同一份 cloud-init base**：`deploy/cloud-init/base-user-data.yaml` 同时用于 Multipass 开发 VM 和 RPi 生产部署，改这个文件要两边都考虑

---

## 行为约定

- **只改被问到的内容**：这是研究/配置仓库，不要在未被要求时重构文档结构或添加额外章节
- **引用文档时给链接，不要复制长段内容**到对话里
- **Commit message**：用 `/commit` skill 生成，遵循 Conventional Commits，描述用中文，type/scope 用英文

---

## 关键文档速查

| 想了解什么 | 去哪里找 |
|-----------|---------|
| 技术架构 / 差异化定位 | [docs/design.md](docs/design.md) |
| MVP 进度 / 任务拆解 | [docs/development/0. MVP.md](docs/development/0.%20MVP.md) |
| 环境变量说明 | [docs/deploy/env-reference.md](docs/deploy/env-reference.md) |
| 部署问题排查 | [docs/deploy/troubleshooting.md](docs/deploy/troubleshooting.md) |
| Slack Socket Mode | [docs/openclaw/slack-socket-mode.md](docs/openclaw/slack-socket-mode.md) |
| 用户画像 | [docs/target-customers.md](docs/target-customers.md) |
