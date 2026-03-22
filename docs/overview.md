# 项目名称与背景

Muliao 是一个基于 OpenClaw 等多 Agent 框架的“AI 助手团队”项目，目标是让普通人也能拥有一支长期在线、可执行操作、可持续进化的个人/工作 AI 团队。
OpenClaw 提供自托管网关、多渠道接入（WhatsApp、Telegram、Slack 等）、工具执行和多 Agent 协作能力，Muliao 在此基础上聚焦“对普通人真正友好”的产品化体验与方法论。 [docs.openclaw](https://docs.openclaw.ai/start/openclaw)
> 商业模式与三层架构设计见 [business-model.md](business-model.md)。
***

## Muliao 的核心设计理念

1. 以真实生活/工作场景为中心
   - 从“个人效率（邮件、日程、待办）”“学习/科研资料管理”“家庭生活与理财”等具体故事出发，而不是从“技能列表”出发。 [every](https://every.to/source-code/openclaw-setting-up-your-first-personal-ai-agent)
   - 每个场景对应一组固定的 Agent + Skills 组合，如“主助手 + 邮件代理 + 日历代理 + 文档整理代理”。 [claw.csdn](https://claw.csdn.net/69b4d4880a2f6a37c59754f9.html)

2. 幕僚团队——团队长 + 专职幕僚
   - 用户拥有一支**可见的**幕僚团队：团队长（默认入口，负责协调分派）和多名专职幕僚（各有名字、性格和专长）。用户可以直接找专人对话，也可以统一通过团队长交互。 [post.smzdm](https://post.smzdm.com/p/a9kp7xl0)
   - 通过 Sub-Agents、任务派发与回调模式，由团队长协调整个 Muliao 团队——但幕僚不是隐形的，用户知道是谁在做事。 [cloud.tencent](https://cloud.tencent.com/developer/article/2630641)

3. 贴近日常的交互入口
   - 优先通过用户已经在用的 IM/协作工具接入（如 WhatsApp、Telegram、Slack、Feishu/企业微信 等），减少学习成本。 [enclaveai](https://enclaveai.app/blog/2026/02/14/openclaw-personal-ai-assistant-guide/)
   - 自然语言容错良好：用户可以说“帮我整理这周的日程和未读邮件”，而不是记住任何技术命令或技能名称。 [docs.openclaw](https://docs.openclaw.ai/start/openclaw)

4. 强安全感与可控感
   - 遵循“最小权限”原则，逐步授予对邮箱、日历、文件系统等的访问权限，并随时可撤销。 [cnblogs](https://www.cnblogs.com/aibi1/p/19627802)
   - 提供清晰的操作日志、权限面板和“后悔药”（如最近操作回滚、重要动作二次确认），缓解“AI 会乱动我东西”的焦虑。 [cnblogs](https://www.cnblogs.com/aibi1/p/19627802)

5. 透明、可编辑的记忆与成长
   - 将长期记忆与偏好配置暴露为可编辑文件（如 SOUL.md、memory/ 目录中结构化记忆），用户可以理解和调整助手的“性格”和习惯。 [claw.csdn](https://claw.csdn.net/69b4d4880a2f6a37c59754f9.html)
   - 利用心跳任务（heartbeat）和定时任务让助手具备“主动性”，同时通过 HEARTBEAT.md 之类的策略文件，让用户清楚它在“自己干什么活”。 [every](https://every.to/source-code/openclaw-setting-up-your-first-personal-ai-agent)

***

## Muliao 关键能力要点（基于 OpenClaw）

1. 多渠道统一网关
   - 一个 Gateway 统一处理来自 WhatsApp、Telegram、Slack、Discord 等多渠道的消息，通过路由规则分发给不同会话/Agent。 [github](https://github.com/openclaw/openclaw)
   - 这样既能保持用户用熟悉的应用聊天，又能在后端集中管理记忆、工具和自动化。

2. 多 Agent 协作模式
   - 路由型（Multi-Agent Routing）：按频道/群组/账号，将不同对话路由到不同 Agent，用于“家庭 Agent vs 工作 Agent”“不同客户专属 Agent”等。 [x](https://x.com/PeterT69358109/status/2024806810243465217)
   - 子代理型（Sub-Agents）：一个 Director/主 Agent 通过 sessions_spawn 调用分析员、开发者、写作者等子 Agent，实现流水线式工作流。 [163](https://www.163.com/dy/article/KMSF5HK50511DPVD.html)

3. 工作区与状态管理
   - 为每个 Agent 配置独立的 workspace（含 SOUL.md、AGENTS.md、memory/、skills/ 等），做到角色清晰、记忆隔离又可协作。 [post.smzdm](https://post.smzdm.com/p/a9kp7xl0)
   - 通过 openclaw.json 等配置集中管理 Agents 列表、默认 Sub-Agents 限制（最大深度、并发数等）、通道绑定和路由策略。 [github](https://github.com/openclaw/openclaw)

4. 主动性（Heartbeats 与定时任务）
   - 利用 Heartbeat 让 Muliao 定期自检：读取 HEARTBEAT.md 决定是否需要执行定期任务，例如整理未读邮件、归档当天文档等。 [docs.openclaw](https://docs.openclaw.ai/start/openclaw)
   - 通过定时任务让 Agent 自己安排“夜间工作”“周报生成”“定期备份”等任务，使助手从被动响应变为主动助理。 [enclaveai](https://enclaveai.app/blog/2026/02/14/openclaw-personal-ai-assistant-guide/)

5. 可扩展的 Skills 体系
   - 通过共享 skills/ 目录引入社区和自定义技能（如代码分析器、自动测试、文档归档、财务记账等），在多个 Agent 间复用。 [claw.csdn](https://claw.csdn.net/69b4d4880a2f6a37c59754f9.html)
   - Muliao 可以为典型生活/工作场景策划一组“官方推荐技能包”，降低非技术用户选型和组合成本。 [cloud.tencent](https://cloud.tencent.com/developer/article/2630641)

***

## 面向“普通人友好”的设计原则

1. 交互与配置的“去工程化”
   - 尽量用自然语言向导、网页表单或聊天式向导，包装底层的 YAML/JSON 配置，让用户通过一系列简单问题完成初始化与授权。 [enclaveai](https://enclaveai.app/blog/2026/02/14/openclaw-personal-ai-assistant-guide/)
   - 用“我可以帮你做这些事”的语言展示能力，而不是直接列出技能名、API 名称。

2. 场景化的预设模板
   - 设计若干预设方案，例如“个人效率助手套装”“学习科研助手套装”“家庭账本与日程套装”，一键启用对应的 Agents + Skills + 心跳任务。 [every](https://every.to/source-code/openclaw-setting-up-your-first-personal-ai-agent)
   - 每个模板附带清晰的说明：能做什么、不做什么、需要哪些权限，便于普通用户理解和信任。

3. 明确边界与解释能力
   - 对每一次跨界操作（比如首次访问某个文件夹、首次代表用户发邮件）给出简短解释并请求确认。 [cnblogs](https://www.cnblogs.com/aibi1/p/19627802)
   - 提供“为什么这么做”的简单说明（参考链式思维的简化版本），增强用户的理解和掌控感。 [163](https://www.163.com/dy/article/KMSF5HK50511DPVD.html)

***

## Muliao 推进路线（可直接作为 Roadmap）

1. 第一阶段：选场景 → 做一个 MVP
   - 从 1–2 个高频、低风险场景切入（推荐：个人效率助手、学习/科研资料整理助手）。
   - 基于 OpenClaw 搭建最小可用的多 Agent 工作流，跑在一个主要渠道（如 WhatsApp/Telegram/Feishu）上，收集早期用户反馈。 [docs.openclaw](https://docs.openclaw.ai/start/openclaw)

2. 第二阶段：设计“非技术用户友好”的控制面
   - 开发一个简单的 Web 控制台或聊天式“设置向导”，完成账号绑定、权限授权、常用偏好设置和模板切换。 [cnblogs](https://www.cnblogs.com/aibi1/p/19627802)
   - 把 openclaw.json 和各 Agent workspace 的关键配置抽象成可视化操作，屏蔽技术细节。 [github](https://github.com/openclaw/openclaw)

3. 第三阶段：沉淀多 Agent 模板与模式
   - 抽象和开源 Muliao 常用协作模式（如“主助手 + 研究员 + 写作者”“主助手 + 邮件整理 + 日历管理”），形成可一键导入的配置与文档。 [x](https://x.com/PeterT69358109/status/2024806810243465217)
   - 借鉴社区经验（如 5 角色协作 OS、14 子代理写作系统等），优化角色划分与协作接口，提升稳定性和可维护性。 [cloud.tencent](https://cloud.tencent.com/developer/article/2630641)

4. 第四阶段：建立体验评估与迭代闭环
   - 制定统一的体验指标：节省时间、任务完成率、需要人工干预次数、错误/惊吓事件、用户主观安心度等。 [post.smzdm](https://post.smzdm.com/p/a9kp7xl0)
   - 基于这些指标对不同模板、技能组合、交互设计做 A/B 测试，反向指导 Muliao 的产品化演进。

5. 第五阶段：生态与社区
   - 将 Muliao 角色设计、配置模板、最佳实践公开分享，鼓励他人基于自身场景二次定制。
   - 逐步形成“Muliao 风格”的一套规范：命名约定、SOUL.md 模板、权限分级、日志格式等，降低协作与分享成本。 [github](https://github.com/AlexAnys/opencrew)
