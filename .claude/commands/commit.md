---
description: 根据当前 git 变更生成中文 Conventional Commits 格式的 commit message
---

结合当前对话上下文与 git 变更，生成一条中文 Conventional Commits 格式的 commit message，放在代码块中方便复制。

## 两个信息源，各取所长

| 信息源 | 提取什么 |
|-------|---------|
| **当前对话上下文** | 意图——用户为什么要做这个改动，解决了什么问题 |
| **git diff** | 事实——实际修改了哪些文件、改了什么 |

意图优先写进标题；事实用来核实范围、选 scope，变更较大时写进正文。

## 格式

```
<type>(<scope>): <中文描述>

[可选正文：变更较大时分点说明意图，不是罗列文件]
```

**type**（英文）：`feat` `fix` `refactor` `docs` `chore` `perf` `test` `ci` `build`

**scope**（英文，选最贴切的）：
- `cli` — backup.sh / dev.sh 等命令行工具
- `deploy` — cloud-init 模板、flash-ssd、deploy-team 等部署脚本
- `rpi` — RPi 专属逻辑
- `infra` — 开发环境、VM、基础设施配置
- `docs` — 文档
- `openclaw` — OpenClaw manifest / Skill 配置
- 跨多处改动可省略 scope

**描述**：中文，概括意图而非罗列文件，不超过 50 字，不加句号

破坏性变更在 type 后加 `!`，如 `feat(deploy)!: ...`

## 示例

```
feat(cli): 添加从 RPi 拉取备份的功能，支持 SSH 连接检查
fix(deploy): 修正 cloud-init 模板中 Tailscale 启动顺序
refactor(infra): 以 Multipass VM 替换 Docker 开发环境
docs(openclaw): 添加 Slack Socket Mode 配置指南
chore(deploy): 更新 .env.example，补充缺失的环境变量说明
```

## 步骤

1. **运行 `git diff --cached`** 查看 staged 变更；若为空则用 `git diff HEAD`
2. **判断意图来源**：
   - **有对话上下文** → 从对话中提取用户的目标或问题，作为意图
   - **无上下文** → 从 diff 内容本身推断意图：新增了什么能力？移除了什么限制？修复了什么异常行为？（不要只看文件名，要看改了什么内容）
3. 用 diff 核实改动范围，选定 type 和 scope
4. 以意图为核心写标题，变更较大时在正文分点补充
5. 输出放在 ` ```text ` 代码块中