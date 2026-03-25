# 自动化测试框架设计方案

> 面向开发者：描述如何对幕僚（OpenClaw Agent）进行自动化端到端测试的架构设计。

---

## 测试目标

**测什么**：OpenClaw harness 是否正确工作——

- 收到用户消息后，Agent 有没有调用预期的 Skill？
- Skill 有没有正确执行（工具调用、文件 I/O、外部 API）？
- memory 有没有正确落盘/读取？
- session 管理、workspace 加载、热更新是否正确？

**不测什么**：LLM 的回答质量（那是产品问题，不是工程问题）。

**核心思路**：用「剧本 LLM」替换真实 LLM。

```
用户消息 → OpenClaw → [剧本 LLM] → 返回预定义 tool_use → OpenClaw 执行 Skill → 测试验证效果
```

类比：给 HTTP 框架写集成测试，mock 掉数据库，只测路由和中间件是否正确。

---

## 四层测试策略

| Layer | 名称 | LLM | 预计耗时 | 自动化 |
|-------|------|-----|---------|--------|
| **0** | 基础设施 | 无 | ~2min | ✅ CI |
| **1** | Skill 单元测试 | 无 | ~3min | ✅ CI |
| **2** | Agent 路由测试 | 剧本 | ~5min | ✅ CI |
| **3** | 集成 + Memory | 剧本 | ~5min | ✅ CI |
| **4** | 稳定性（72h） | 可选真实 | ~72h | 手动触发 |

---

## 关键设计：剧本 LLM Server

在 VM 内启动一个 Python HTTP server，模拟 Anthropic/OpenAI API。

每个测试场景对应一个 YAML 剧本文件，定义「收到什么 prompt → 返回什么 tool_use」：

```yaml
# test/scenarios/paper-search.yaml
rules:
  - when:
      message_contains: "论文"
    respond:
      role: assistant
      content:
        - type: tool_use
          name: bash
          input:
            command: "openclaw skill run paper-search --query 'diffusion policy'"
  - when:
      message_contains: "ping"
    respond:
      role: assistant
      content:
        - type: text
          text: "pong"
```

测试时：
1. 启动剧本 LLM server，加载对应场景文件
2. 用 `openclaw agent --message "..."` CLI 注入消息（无需 Telegram/Slack）
3. 检查 Skill 执行结果（文件、输出、API 调用）

---

## 目录结构

```
test/
  run.sh                         # 入口：./test/run.sh [infra|skill|agent|all]
  lib/
    vm.sh                        # Multipass VM 生命周期（create/snapshot/restore/exec）
    skill.sh                     # openclaw skill 直接调用 wrapper
    agent.sh                     # openclaw agent --message wrapper
    scripted_llm.py              # 剧本 LLM HTTP server（读取 scenarios/*.yaml）
    assert.sh                    # assert_contains / assert_file_exists / assert_exit_ok
  scenarios/                     # 剧本文件（每个场景一个 YAML）
    paper-search.yaml            # 论文搜索场景
    memory-write.yaml            # 记忆写入场景
    hr-trigger.yaml              # HR 意图触发场景
  fixtures/
    workspace/
      SOUL.md                    # 最小化测试人格（行为可预测）
      IDENTITY.md
    openclaw-test.yaml.tmpl      # OpenClaw 配置模板（指向剧本 LLM）
  suites/
    00-infra.sh                  # Layer 0：基础设施
    01-skill-unit.sh             # Layer 1：Skill 单元
    02-agent-routing.sh          # Layer 2：Agent 路由
    03-memory-io.sh              # Layer 3：Memory I/O
    04-workspace-reload.sh       # Layer 3：Workspace 热更新
    05-stability.sh              # Layer 4：稳定性（手动）
.github/
  workflows/
    test.yml                     # CI 配置（self-hosted runner）
```

---

## 各层详细设计

### Layer 0：基础设施测试

目标：验证 Multipass VM + cloud-init + OpenClaw 安装正确。

```bash
# 00-infra.sh 检查项
assert_file_exists_in_vm "/home/muliao/.cloud-init-done"
assert_command_ok   "openclaw --version"
assert_command_ok   "docker info"
assert_dir_exists_in_vm "/home/muliao/.openclaw"
# teams/<name>/ mount 是否生效（宿主机写文件，VM 内可见）
```

---

### Layer 1：Skill 单元测试

目标：直接调用 Skill CLI，绕开 LLM 和 gateway，验证 Skill 自身逻辑。

```bash
# 01-skill-unit.sh 示例（paper-search）
result=$(vm_exec "openclaw skill run paper-search --query 'diffusion policy'")
assert_contains     "$result" "arXiv"
assert_contains     "$result" "title"
assert_file_exists_in_vm "/home/muliao/.openclaw/workspace/papers-read.md"
```

优点：最快、最隔离，适合 Skill 开发阶段的快速反馈。

---

### Layer 2：Agent 路由 + 工具调用测试

目标：用剧本 LLM 测试 OpenClaw 是否正确处理 LLM 返回的 tool_use。

```bash
# 02-agent-routing.sh 示例
start_scripted_llm "scenarios/paper-search.yaml"

response=$(send_agent_message "帮我搜一下 diffusion policy 论文")

# 验证 Skill 被执行（papers-read.md 有新记录）
assert_file_exists_in_vm   "/home/muliao/.openclaw/workspace/papers-read.md"
assert_file_updated_after  "/home/muliao/.openclaw/workspace/papers-read.md" "$TEST_START"
```

---

### Layer 3：Memory I/O 测试

目标：验证 memory 文件的创建、跨 session 读取和隔离。

```bash
# 03-memory-io.sh 示例
start_scripted_llm "scenarios/memory-write.yaml"

# 第一轮 session：写入 memory
send_agent_message "我叫小明"
assert_dir_not_empty_in_vm "/home/muliao/.openclaw/workspace/memory"

# 新 session：验证 memory 被加载（剧本 LLM 读 memory 后返回正确内容）
reset_session
response=$(send_agent_message "你还记得我叫什么吗")
assert_contains "$response" "小明"
```

---

### Layer 4：稳定性测试（手动触发）

目标：对标 MVP Day 6 验收标准（RPi 连续 72h 无异常）。

```bash
# 05-stability.sh（手动运行）
# 每 10 分钟发一次 ping，持续 N 小时
# 记录成功率、响应时间、内存占用
# 模拟断电：multipass stop → start → 验证自动恢复
```

---

## VM 生命周期：快照加速

云 cloud-init 初始化需要 5-10 分钟，通过快照避免每次等待：

```bash
# 首次（慢）：创建 VM 并打快照
multipass launch --cloud-init deploy/cloud-init/... --name muliao-test
# 等待 cloud-init 完成...
multipass snapshot muliao-test --name post-cloud-init

# 后续（快，~30s）：从快照恢复
multipass restore muliao-test --snapshot post-cloud-init

# 重置（完全清除）
multipass delete muliao-test && multipass purge
```

---

## CI 集成

需要 self-hosted runner（因为 Multipass 需要本地虚拟化）。

```yaml
# .github/workflows/test.yml
on: [push, pull_request]
jobs:
  test:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - name: Layer 0 - 基础设施
        run: ./test/run.sh infra
      - name: Layer 1 - Skill 单元测试
        run: ./test/run.sh skill
      - name: Layer 2-3 - Agent 路由 + Memory
        run: ./test/run.sh agent
```

Layer 0–3 全部使用剧本 LLM，不需要真实 API Key，可在 CI 上安全运行。

---

## 方案对比（头脑风暴）

| 方案 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| **A（推荐）** | HTTP 剧本 LLM Server | 完全可控、确定性、CI 友好 | 需了解 OpenClaw tool_use 格式 |
| B | 静态响应 + netcat | 零依赖 | 固定响应，无法根据输入切换 |
| C | Skill 直接调用 | 最快最隔离 | 不测路由层 |
| D | Session 录制重放 | 回归测试价值高 | fixture 随 API 变化失效 |
| E | YAML 对话 DSL | 非开发者可写 | 需构建 DSL 解释器 |

**推荐**：A（剧本 LLM）作为 Layer 2-3 主方案，C（直接调用）作为 Layer 1。

---

## 关键前置调研项

实施前需要在实际 VM 内确认：

1. **OpenClaw LLM API 格式**：是 Anthropic SDK 格式还是 OpenAI 格式？（决定剧本 LLM 的响应结构）
   ```bash
   # 在 VM 内抓包或查看日志
   openclaw gateway --verbose 2>&1 | grep -i "api\|model\|request"
   ```

2. **Skill 直接调用命令**：`openclaw skill run <name>` 是否支持？
   ```bash
   openclaw skill --help
   ```

3. **Agent 无头消息注入**：`openclaw agent --message` 的完整参数和输出格式？
   ```bash
   openclaw agent --help
   ```

4. **剧本 LLM 配置覆盖**：如何让 OpenClaw 指向本地 mock 而非真实 API？（`openclaw.yaml` 中 `apiBase` 字段？）

---

## 实施顺序（供后续 iteration 参考）

1. 前置调研（手动在 VM 里跑上述命令，约 1h）
2. `test/lib/assert.sh` + `test/lib/vm.sh`（~1h）
3. `test/suites/00-infra.sh` 跑通（~30min）
4. `test/lib/skill.sh` + `test/suites/01-skill-unit.sh`（~1h）
5. `test/lib/scripted_llm.py`（核心，~2h）
6. `test/suites/02-agent-routing.sh` + `test/suites/03-memory-io.sh`（~1h）
7. `test/run.sh` 入口 + `.github/workflows/test.yml`（~30min）
