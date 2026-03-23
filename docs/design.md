# Muliao 技术设计

Muliao 在 OpenClaw 之上构建「幕僚团队」——用户通过赫耳墨斯（Hermes，主 Agent，团队长兼 HR）用自然对话组建和管理一支各有专长的 AI 助手团队，而非手写配置文件。

OpenClaw 提供底层引擎（自托管网关、多渠道接入、工具执行），其 [VISION.md](https://github.com/openclaw/openclaw/blob/main/VISION.md) 明确不做 agent 层级框架。Muliao 占据这个战略空位，在引擎之上提供**团队架构**（可见的、有组织的 AI 团队）、**对话式组建**（HR 流程替代手写配置）和**自然成长**（反馈驱动的持续进化）。完整差异化分析见[下文](#与-openclaw-差异化分析)。

> 商业模式见 [business-model.md](business-model.md)；用户画像见 [target-customers.md](target-customers.md)。

---

## 设计理念

1. **场景驱动，不是功能驱动**
   - 从具体故事出发（邮件、客户跟进、论文整理），不从技能列表出发。
   - 每个场景对应一组 Agent + Skills 组合。

2. **赫耳墨斯 = 团队长 + HR**
   - 用户和赫耳墨斯对话，赫耳墨斯负责两件事：
     - **团队长**：接收用户请求，分派给合适的幕僚，汇总结果。
     - **HR**：帮用户「招聘」新幕僚——通过多轮对话提取隐性需求，翻译成 agent 配置（SOUL.md / IDENTITY.md / SKILL.md / TOOL.md），用人话确认。上岗后持续接收反馈、调整配置。
   - 幕僚不是隐形的。用户知道团队里有谁、谁在做什么。

3. **在用户熟悉的地方交互**
   - 通过 Telegram、Slack、WhatsApp、企业微信、钉钉、飞书等 IM 接入。不装新 App。
   - 微信公众号（服务号）可对接但交互受限；个人微信无官方 API，暂不支持。
   - 自然语言交互，不用记命令。

4. **用户要有掌控感**
   - OpenClaw 已提供：exec-approvals（逐条审批）、sandbox 隔离、操作日志、纯文本配置文件（SOUL.md、memory/）。
   - Muliao 在此基础上增加**渐进式信任**：新幕僚初始权限受限，随着使用积累信任后，赫耳墨斯用人话建议用户放权（「小美这周处理了 50 个客户对话都没出问题，要不要让她自己决定何时发资料？」）。犯错后自动收紧。

5. **幕僚会主动干活**
   - Heartbeat 定期自检 + 定时任务（整理邮件、生成周报、归档文档）。
   - 通过 HEARTBEAT.md 让用户知道幕僚在自动做什么。

---

## 底层能力（OpenClaw 提供）

赫耳墨斯在对话中按需引导用户使用这些能力，用户不需要直接理解。

1. **多渠道网关**：Gateway 统一处理多个 IM 渠道的消息，路由到对应幕僚。

2. **多 Agent 协作**：
   - 路由型——按渠道/群组分流到不同幕僚
   - Sub-Agent 型——赫耳墨斯分派任务给幕僚，收集结果汇总
   - Muliao 在此基础上扩展了 **HR 型**（对话式创建新幕僚），见[设计理念 #2](#设计理念)

3. **Workspace 隔离**：每个幕僚有独立的 workspace（SOUL.md、AGENTS.md、memory/、skills/）。赫耳墨斯在招聘新幕僚时负责创建其 workspace。openclaw.json 集中管理路由和权限。

4. **Heartbeat + 定时任务**：让幕僚从被动响应变成主动工作。

5. **Skills 体系**：skills/ 目录引入社区和自定义技能，多个幕僚共用。赫耳墨斯招聘新幕僚时会推荐合适的 Skills 组合。ClawHub 已收录 33,000+ 个 Skill，其中高人气工具类 Skill（如 `gog`、`summarize`、`obsidian`、`himalaya`、`slack` 等，详见[热门 Skill 全景分析](#clawhub-热门-skill-全景分析)）应作为场景模板的默认集成候选。

---

## 与 OpenClaw 差异化分析

> 依据：OpenClaw 官方文档（docs.openclaw.ai）、GitHub README、[VISION.md](https://github.com/openclaw/openclaw/blob/main/VISION.md)，2026-03 版本。

OpenClaw [VISION.md](https://github.com/openclaw/openclaw/blob/main/VISION.md) 明确声明 **不会合并**「Agent-hierarchy frameworks」和「Heavy orchestration layers」。这为 Muliao 的团队架构层提供了**战略安全区**——上游不会吸收此能力，护城河可持续。

### 八维差异对照

| # | 差异化维度 | OpenClaw 现有能力 | 重叠度 | Muliao 做什么不同 |
|---|---|---|---|---|
| 1 | **团队可见性** | `agents.list` 支持名字/头像/emoji，但无"团队"组织概念 | 中 | 有花名册、状态、角色分工的组织化团队，而非独立命名 agent 的松散集合 |
| 2 | **对话式组建（HR）** | 无。[VISION.md](https://github.com/openclaw/openclaw/blob/main/VISION.md) 明确拒绝 agent-hierarchy | **无** | 赫耳墨斯通过多轮对话帮用户「招聘」新幕僚，提取隐性需求→翻译为配置→人话确认 |
| 3 | **自然成长机制** | agent 技术上可编辑自身文件，但无结构化反馈→配置演化流程 | 低 | 纠正即学习、反馈即调整：用户日常使用中的反馈自动沉淀为配置变更。详见 [HR 驱动演化详细设计](design/natural-growth.md) |
| 4 | **场景模板** | 仅有单 agent 模板 | **无** | 预制多 Agent 组合模板（主助手 + 研究员 + 写手等），一键部署完整团队 |
| 5 | **渐进式信任** | 丰富但静态的权限控制（exec-approvals、sandbox） | **无** | 权限随信任积累动态演化：新幕僚初始受限，表现良好后赫耳墨斯建议用户放权 |
| 6 | **运维可视化** | Control UI 存在但面向开发者 | 中 | 双模式简报：① IM 内人话摘要（「小美今天接了 12 个客户，3 个需要你跟进」）② 生成带图表的临时可视化页面（一次性 URL），展示团队全局状态、各幕僚工作量和关键指标。基于 OpenClaw Canvas/A2UI 能力实现 |
| 7 | **人机协作工作区** | Canvas/A2UI 是单向展示（agent→用户），非双向协作 | 低 | 双向协作：用户和 agent 在同一工作区实时编辑，类似 VS Code Remote 共享会话 |
| 8 | **远程节点 UX** | 完整 node 体系（`openclaw node run`、设备配对、WebSocket、exec-approvals、SSH 隧道） | **高** | 不重建，仅包装：将 OpenClaw 10 步 CLI 配置封装为 2 步对话式流程 |

### 护城河评估

> 依据：ClawHub 社区搜索 + OpenClaw GitHub Issues（2026-03）。
>
> **ClawHub**：>1k 安装的多 Agent 类 skill 超过 15 个，累计安装量 ~50k+。重点核查 [`agent-team-orchestration`](https://clawhub.ai/arminnaimi/agent-team-orchestration)（12.6k）、[`agent-orchestrator`](https://clawhub.ai/aatmaan1/agent-orchestrator)（9.6k）、[`agent-council`](https://clawhub.ai/itsahedge/agent-council)（6.1k）、[`clawops`](https://clawhub.ai/okoddcat/clawops)（4.5k）、[`multi-agent-cn`](https://clawhub.ai/Be1Human/multi-agent-cn)（2.8k）、[`openclaw-team-builder`](https://clawhub.ai/eggyrooch-blip/openclaw-team-builder)（359）、[`agent-training`](https://clawhub.ai/zLiM5/agent-training)（711）等。
>
> **GitHub Issues**：搜索 "multi agent team" 返回 237 个 issue（145 open / 92 closed），需求极其活跃。关键 issue：[#35203](https://github.com/openclaw/openclaw/issues/35203)（RFC: 能力画像 + 共享黑板 + 分层记忆 + Token 治理）、[#43673](https://github.com/openclaw/openclaw/issues/43673)（org/team 一键部署 + RBAC）、[#50823](https://github.com/openclaw/openclaw/issues/50823)（策略游戏风可视化仪表盘）、[#52501](https://github.com/openclaw/openclaw/issues/52501)（Team Channels，被确认为"real feature gap"）。

**需求已验证**：`agent-team-orchestration` 以 12.6k 安装量领跑，GitHub 上 237 个相关 issue，证明多 Agent 团队协作是社区刚需。但现有方案**全部面向开发者**（CLI、结构化配置、英文 playbook、SQL schema），普通用户无法使用。Muliao 不是发明需求，而是把已验证的需求翻译成普通人能用的交互方式。

- **最强护城河**（#2 对话式组建）：社区最接近的方案 `openclaw-team-builder` 采用"**一次性复合提问**"（SKILL.md 原文：「CRITICAL: Collect ALL info in ONE message. Do NOT use multi-step Q&A」），本质是结构化表单；Muliao 的 HR 是多轮渐进对话，面向无法填写技术参数的普通用户。二者哲学相反，不构成替代关系。OpenClaw VISION.md 明确不做层级架构，上游不会收编。

- **中等护城河**（#3 自然成长 + #5 渐进式信任）：
  - **自我改进类 Skill 是 ClawHub 第一刚需**（详见[热门 Skill 全景分析](#clawhub-热门-skill-全景分析)）：`self-improving-agent`（286k）、`proactive-agent`（115k）、`self-improving`（102k）三者合计 503k 安装量。但它们全部是**单 Agent 自我改进**——记录错误、定期回顾、晋升到项目记忆。Muliao 的自然成长是**多 Agent 团队层面的 HR 驱动演化**（反馈→幕僚 SOUL.md 更新→赫耳墨斯审核→生效），维度不同，不构成直接替代
  - `agent-training`（711 安装）有"进化机制"（每日/每周定期审计），但属于手动触发的批量回顾，非对话驱动的实时演化；GitHub [#35203](https://github.com/openclaw/openclaw/issues/35203) 提出了完整 4 层架构（含"HR Performance Records"能力画像），Layer 1 与 Muliao 的自然成长用了同一隐喻，但实现路径完全不同（数据库驱动 vs 对话驱动）。需求已被充分验证，社区有竞争但方向不同
  - 渐进式信任：无社区竞品，但 [#43673](https://github.com/openclaw/openclaw/issues/43673) 已提出 per-session RBAC，OpenClaw 原生 exec-approvals 也很强，Muliao 仅在"信任积累→动态放权"环节有增量

- **较浅护城河**（#1 团队可见性 + #4 模板 + #6 可视化 + #7 协作工作区 + #8 节点包装）：
  - **#1 已有竞品**：`openclaw-team-builder` v3.6.1 已覆盖 org tree、状态总览、health check；[#43673](https://github.com/openclaw/openclaw/issues/43673) 提出 `openclaw workspace init --template team` 脚手架 CLI。Muliao 差异在非技术用户侧（IM 中文可读视图），不在数据结构本身
  - **#4 已有竞品**：`openclaw-team-builder` 内置 9 种角色模板 + 6 类部署场景 + goal-driven 推荐；[`agency-agents`](https://clawhub.ai/jerry-guo-mys/agency-agents)（1.1k 安装）直接提供 61 个专业 Agent / 8 大部门。Muliao 增量仅在对话式交付，而非模板本身
  - **#6 已有需求**：[#50823](https://github.com/openclaw/openclaw/issues/50823) 提出策略游戏风可视化仪表盘（agent 地图 + 实时 HUD + 回放），说明可视化是共性需求；team-builder `--status` 已覆盖文字侧；临时可视化 URL 无竞品
  - #7 双向协作工作区、#8 节点包装：无社区竞品

### ClawHub 热门 Skill 全景分析

> 依据：ClawHub 全站按安装量排序（2026-03-22），总收录 33,205 个 Skill。

#### 总榜 Top 25（按安装量）

| 排名 | Skill | 安装量 | ★  | 核心能力 |
|------|-------|--------|-----|---------|
| 1 | [`self-improving-agent`](https://clawhub.ai/pskoett/self-improving-agent) | **286k** | 2.6k | 错误/纠正/反馈→`.learnings/`日志→自动晋升到项目记忆 |
| 2 | [`summarize`](https://clawhub.ai/steipete/summarize) | **196k** | 749 | URL/文件/PDF/YouTube 摘要 |
| 3 | [`agent-browser`](https://clawhub.ai/TheSethRose/agent-browser) | **159k** | 696 | Rust 无头浏览器自动化 |
| 4 | [`skill-vetter`](https://clawhub.ai/spclaudehome/skill-vetter) | **139k** | 584 | 安装前安全审查 |
| 5 | [`gog`](https://clawhub.ai/steipete/gog) | **128k** | 769 | Google Workspace CLI（Gmail/Calendar/Drive/Sheets/Docs） |
| 6 | [`github`](https://clawhub.ai/steipete/github) | **126k** | 418 | gh CLI 封装（issue/PR/CI） |
| 7 | [`proactive-agent`](https://clawhub.ai/halthelobster/proactive-agent) | **115k** | 611 | 主动型 Agent 架构：WAL 协议 + Heartbeat + 逆向提问 + 成长循环 |
| 8 | [`weather`](https://clawhub.ai/steipete/weather) | **108k** | 313 | 天气查询（无需 API key） |
| 9 | [`self-improving`](https://clawhub.ai/ivangdavila/self-improving) | **102k** | 579 | 自反思 + 自批评 + 自学习 + 记忆体系 |
| 10 | [`multi-search-engine`](https://clawhub.ai/gpyAngyoujun/multi-search-engine) | **77.3k** | 392 | 17 个搜索引擎（8 中国 + 9 国际） |
| 11 | [`nano-pdf`](https://clawhub.ai/steipete/nano-pdf) | **70.1k** | 169 | 自然语言编辑 PDF |
| 12 | [`sonoscli`](https://clawhub.ai/steipete/sonoscli) | **64.7k** | 43 | Sonos 音箱控制 |
| 13 | [`notion`](https://clawhub.ai/steipete/notion) | **63k** | 203 | Notion API 封装 |
| 14 | [`nano-banana-pro`](https://clawhub.ai/steipete/nano-banana-pro) | **62.7k** | 250 | 图片生成/编辑（Gemini 3 Pro Image） |
| 15 | [`obsidian`](https://clawhub.ai/steipete/obsidian) | **61.1k** | 253 | Obsidian vault 操作 |
| 16 | [`openai-whisper`](https://clawhub.ai/steipete/openai-whisper) | **54.1k** | 236 | 本地语音转文字 |
| 17 | [`skill-creator`](https://clawhub.ai/chindden/skill-creator) | **51.3k** | 180 | Skill 创建向导 |
| 18 | [`mcporter`](https://clawhub.ai/steipete/mcporter) | **43.2k** | 127 | MCP 服务器管理 CLI |
| 19 | [`slack`](https://clawhub.ai/steipete/slack) | **31.1k** | 102 | Slack 消息/反应/Pin 控制 |
| 20 | [`himalaya`](https://clawhub.ai/lamelas/himalaya) | **30.8k** | 53 | IMAP/SMTP 邮件管理 |
| 21 | [`video-frames`](https://clawhub.ai/steipete/video-frames) | **31.6k** | 87 | 视频帧提取 |
| 22 | [`blogwatcher`](https://clawhub.ai/steipete/blogwatcher) | **27.8k** | 50 | RSS/博客监控 |
| 23 | [`model-usage`](https://clawhub.ai/steipete/model-usage) | **27k** | 95 | 模型用量/成本统计 |
| 24 | [`gemini`](https://clawhub.ai/steipete/gemini) | **24.1k** | 46 | Gemini CLI 问答/生成 |
| 25 | [`tmux`](https://clawhub.ai/steipete/tmux) | **18.1k** | 35 | tmux 会话远程控制 |

#### 需求热度分类

从总榜和分类搜索中提炼出以下 6 大社区需求方向：

| 需求方向 | 代表 Skill（安装量） | 社区热度 | Muliao 相关维度 |
|----------|---------------------|---------|----------------|
| **自我改进 / 持续学习** | `self-improving-agent`（286k）、`self-improving`（102k）、`proactive-agent`（115k） | 🔥🔥🔥🔥🔥 | **#3 自然成长** |
| **外部工具集成**（邮件/日历/笔记/搜索） | `gog`（128k）、`notion`（63k）、`obsidian`（61.1k）、`himalaya`（30.8k）、`slack`（31.1k） | 🔥🔥🔥🔥 | #4 场景模板 |
| **浏览器 / 信息获取** | `agent-browser`（159k）、`summarize`（196k）、`multi-search-engine`（77.3k） | 🔥🔥🔥🔥 | — |
| **多 Agent 协作** | `agent-team-orchestration`（12.6k）、`agent-orchestrator`（9.6k）、`agent-council`（6.1k）、`multi-agent-cn`（2.9k） | 🔥🔥🔥 | **#1 #2 #4** |
| **安全 / 审查** | `skill-vetter`（139k） | 🔥🔥🔥 | #5 渐进式信任 |
| **多媒体 / 创作** | `nano-banana-pro`（62.7k）、`openai-whisper`（54.1k）、`video-frames`（31.6k） | 🔥🔥🔥 | — |

#### 关键发现

1. **自我改进是第一刚需**。`self-improving-agent` 以 286k 安装量断层领跑全站，`self-improving`（102k）和 `proactive-agent`（115k）紧随其后——三者合计 **503k 安装量**。用户最渴望的不是更多工具，而是**让 Agent 能记住教训、自我进化**。这直接验证了 Muliao #3（自然成长）的价值判断，但也意味着 Muliao 的成长机制必须比现有方案**明显更好**才有竞争力。
   - `self-improving-agent` 的方式：错误/纠正→结构化日志（`.learnings/`）→定期回顾→晋升到项目记忆（CLAUDE.md / AGENTS.md）。本质是**被动记录**——Agent 犯错后才学习。
   - `proactive-agent` 的方式：WAL 协议（先写后回复）+ 三层记忆（SESSION-STATE / 日志 / 长期记忆）+ Heartbeat 自检 + 逆向提问。本质是**主动架构**——Agent 主动寻找改进机会。
   - **Muliao 的差异空间**：上述两者都是**单 Agent 自我改进**，不涉及多 Agent 团队层面的成长（如：「小美从和客户对话中学到的经验，自动沉淀为她的 SOUL.md 更新，赫耳墨斯审核后生效」）。Muliao 的自然成长是**团队视角的 HR 驱动演化**，不是单兵的自我反思。

2. **多 Agent 协作需求活跃但安装量偏低**。最高的 `agent-team-orchestration`（12.6k）仅为总榜第 1 名的 4.4%。这说明：
   - 需求存在（237 个 GitHub Issue 佐证），但**当前方案门槛太高**，绝大多数用户装不起来
   - `multi-agent-cn`（2.9k）作为中文版多 Agent 调度尝试，核心是「指挥官 + 5 个固定子 Agent」的轮询分派。社区评论暴露关键痛点：「没有看懂，在 OpenClaw 上怎么使用」「依然没找到如何调度非子 agent 的方法」「cant open gateway for more agents」——**即使有中文文档，普通用户依然无法使用**
   - `agent-council`（6.1k）提供了 Shell 脚本创建 Agent + Discord 频道绑定的完整方案，但**全程 CLI 操作**（`scripts/create-agent.sh --name Watson --id watson --emoji 🔬 ...`），开发者友好但普通用户完全无法使用
   - **Muliao 的机会**：多 Agent 协作的低安装量恰恰印证了核心判断——需求真实存在但交互门槛阻挡了用户。对话式组建（#2）不是在已经繁荣的市场里竞争，而是在**打开一个被门槛卡住的需求出口**

3. **外部工具集成是用户的基本盘**。`gog`（128k）、`notion`（63k）、`obsidian`（61.1k）、`himalaya`（30.8k）、`slack`（31.1k）等工具类 Skill 构成了用户日常使用的基础设施。Muliao 的场景模板（#4）应该将这些高人气工具作为默认 Skill 集成候选，而非从零构建。例如：
   - 科研场景模板 = `summarize` + `obsidian` + `multi-search-engine` + 研究员 Agent
   - 销售场景模板 = `gog`（邮件/日历）+ `slack` + 客户跟进 Agent
   - 效率场景模板 = `himalaya`（邮件）+ `notion` + 助理 Agent

4. **@steipete 一人贡献了总榜 25 个中的 14 个**。这说明 ClawHub 生态高度集中，少数核心贡献者定义了工具标准。Muliao 做场景模板时应优先集成 @steipete 系列 Skill（质量稳定、接口统一、持续维护）。

---

## 开发优先级与投资分配

采用**双轨策略**：开发者轨道（自用 dogfooding）和大众轨道（目标用户）并行，共享基础设施但侧重不同。

### 双轨优先级

| 维度 | 开发者轨道 | 大众轨道 | 说明 |
|------|-----------|---------|------|
| #2 对话式组建（HR） | **P0** | **P0** | 核心差异化，两条轨道都需要 |
| #1 团队可见性 | **P0** | **P0** | HR 的前提——团队必须可见才能管理 |
| #7 人机协作工作区 | **P0** | P3 | 开发者需要实时看到 agent 在做什么；大众用户暂不需要 |
| #3 自然成长机制 | P1 | P1 | HR 上线后自然延伸——从「招聘」到「培养」 |
| #4 场景模板 | P2 | P2 | 降低冷启动门槛，但需要先有 HR 能力来生成模板 |
| #5 渐进式信任 | P2 | P2 | 增强掌控感，但不是 MVP 阶段的阻塞项 |
| #6 运维可视化 | P2 | P3 | 开发者有 CLI/日志，大众用户初期用 IM 简报，后期加临时可视化页面 |
| #8 远程节点 UX | P2 | P3 | 包装现有能力，投入小，但优先级不高 |

### 投资分配（MVP 阶段）

```
┌─────────────────────────────────────────────────┐
│  40%  P0 — HR 对话式组建 + 团队可见性              │
│        · 赫耳墨斯 HR 流程（需求提取→配置翻译→确认）  │
│        · 团队花名册、状态、角色分工                 │
│        · 开发者轨道：协作工作区原型                 │
├─────────────────────────────────────────────────┤
│  25%  P1 — 自然成长机制（详见 design/natural-growth.md）│
│        · 反馈→配置变更的结构化流程                 │
│        · 记忆沉淀与风格演化                        │
├─────────────────────────────────────────────────┤
│  20%  P2 — 模板 + 渐进式信任                      │
│        · 2–3 个场景模板（销售 / 科研 / 效率）       │
│        · 权限动态演化原型                          │
├─────────────────────────────────────────────────┤
│  15%  P3 — 可视化 + 节点包装                      │
│        · 人话运维简报 + 临时可视化页面（Canvas/A2UI）│
│        · 节点配置对话式封装                        │
└─────────────────────────────────────────────────┘
```

### 为什么这样分配

1. **40% 投 P0**：HR + 团队可见性是 Muliao 存在的理由。如果这一层做不好，Muliao 就只是 OpenClaw 的一层皮肤。协作工作区对开发者轨道是刚需——自己用的时候需要看到 agent 在做什么。
2. **25% 投 P1**：自然成长是从「一次性配置」到「持续进化」的跨越，也是用户留存的关键——如果幕僚不会成长，用户新鲜感过后就会流失。ClawHub 数据进一步佐证：自我改进类 Skill 合计 503k 安装量断层领跑（见[热门 Skill 全景分析](#clawhub-热门-skill-全景分析)），说明这是用户最强烈的诉求。但现有方案都是单 Agent 维度，Muliao 的团队级成长机制有独特价值。
3. **20% 投 P2**：模板降低冷启动门槛（「不知道要什么团队？选一个模板先跑起来」），渐进式信任增强掌控感。
4. **15% 投 P3**：可视化和节点包装是锦上添花，MVP 阶段用 IM 文字简报兜底，后续加临时可视化页面（一次性 URL + 图表）。

---

## 推进路线

| 阶段 | 开发者轨道 | 大众轨道 | 共享基础设施 |
|------|-----------|---------|-------------|
| **1. MVP** | 协作工作区原型 + HR 流程 v1 | 1–2 个场景跑通（销售/科研），单 IM 渠道。场景模板优先集成 ClawHub 高人气 Skill：科研=`summarize`+`obsidian`+`multi-search-engine`；销售=`gog`+`slack` | 赫耳墨斯核心 + 团队花名册 + 自然成长 v0 |
| **2. 控制面** | 工作区稳定化、CLI 工具链 | 聊天式设置向导，账号绑定/权限授权/模板切换 | 场景模板库 v1 + 渐进式信任 v0 |
| **3. 模板沉淀** | 开发者模板（CI/CD agent、code review agent） | 常用协作模式模板化（主助手+研究员+写手） | 模板规范 + 一键部署 |
| **4. 体验闭环** | 性能指标、agent 行为分析 | 用户指标（省时间、完成率、人工干预次数），A/B 测试 | 运维可视化（IM 简报 + 临时图表页面） |
| **5. 生态** | 开发者社区、plugin API | 模板市场、认证培训 | 规范体系（命名、权限分级、日志格式） |
