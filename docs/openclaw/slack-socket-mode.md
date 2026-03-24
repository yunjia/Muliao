# OpenClaw × Slack — Socket Mode 配置指南

> 适用场景：部署在**无公网 IP** 的环境（树莓派、内网服务器、家庭网络等）。  
> Socket Mode 使用 WebSocket 向外主动发起连接，Slack 无需回调你的服务器，因此无需公网 IP 或端口转发。

---

## 目录

1. [为什么用 Socket Mode](#1-为什么用-socket-mode)
2. [创建 Slack App](#2-创建-slack-app)
3. [开启 Socket Mode & 获取 App Token](#3-开启-socket-mode--获取-app-token)
4. [配置 Bot Token Scopes（权限）](#4-配置-bot-token-scopes权限)
5. [订阅 Events（事件）](#5-订阅-events事件)
6. [安装 App 到工作区 & 获取 Bot Token](#6-安装-app-到工作区--获取-bot-token)
7. [配置 OpenClaw](#7-配置-openclaw)
8. [配置 Select Channel（指定频道）](#8-配置-select-channel指定频道)
9. [权限详解](#9-权限详解)
10. [App Manifest 一键配置](#10-app-manifest-一键配置)
11. [故障排查](#11-故障排查)

---

## 1. 为什么用 Socket Mode

| 对比维度 | HTTP Events API | Socket Mode |
|--------|----------------|-------------|
| 需要公网 IP | ✅ 必须 | ❌ 不需要 |
| 需要开放端口 | ✅ 必须 | ❌ 不需要 |
| 连接方向 | Slack → 你的服务器（入站） | 你的服务器 → Slack（出站） |
| 防火墙/NAT 穿透 | 需要 | 不需要 |
| 可上架 Slack Marketplace | ✅ | ❌（仅限内部使用） |
| 适合家庭/内网部署 | ❌ | ✅ |

Socket Mode 通过 WebSocket 长连接与 Slack 通信，只要你的机器能访问互联网（出站 443），就可以正常工作。

---

## 2. 创建 Slack App

1. 访问 [api.slack.com/apps](https://api.slack.com/apps) → 点击 **Create New App**
2. 选择 **From scratch**（或使用下方 Manifest 一键导入）
3. 填写 **App Name**（例如 `OpenClaw`）
4. 选择你的 **Development Workspace**（目标工作区）
5. 点击 **Create App**

---

## 3. 开启 Socket Mode & 获取 App Token

### 开启 Socket Mode

1. 在 App 设置页左侧菜单，点击 **Settings → Socket Mode**
2. 将 **Enable Socket Mode** 开关拨到 **ON**

### 生成 App-Level Token（`xapp-...`）

开启 Socket Mode 后，页面会引导你创建 App-Level Token：

1. 点击 **Generate an app-level token**（或在 **Basic Information → App-Level Tokens** 下方找到）
2. Token Name 随意填（如 `socket-token`）
3. **Scope 必须选**：`connections:write`
4. 点击 **Generate** → 复制 `xapp-1-...` 格式的 token，**妥善保存**

> App Token 只显示一次，丢失需重新生成。

---

## 4. 配置 Bot Token Scopes（权限）

在左侧菜单 **OAuth & Permissions → Scopes → Bot Token Scopes** 下添加以下权限：

### 4.1 核心必填权限

| Scope | 用途 |
|-------|------|
| `app_mentions:read` | 读取 @提及 bot 的消息 |
| `chat:write` | 以 bot 身份发送消息 |
| `channels:history` | 读取公共频道的消息历史（附件包含在内） |
| `groups:history` | 读取私有频道的消息历史 |
| `im:history` | 读取 DM（私信）消息历史 |
| `mpim:history` | 读取群组 DM（多人私信）历史 |
| `channels:read` | 查看公共频道基础信息（名称、ID） |
| `groups:read` | 查看私有频道基础信息 |
| `im:read` | 查看 DM 基础信息 |
| `mpim:read` | 查看群组 DM 基础信息 |
| `im:write` | 向 DM 发消息（OpenClaw 必须） |
| `groups:write` | 向私有频道发消息（OpenClaw 必须） |
| `mpim:write` | 向群组 DM 发消息（OpenClaw 必须） |
| `reactions:write` | 添加/移除 Emoji 反应（ack reaction、typing reaction） |
| `reactions:read` | 查看消息上的 Emoji 反应 |

### 4.2 文件相关权限

| Scope | 用途 |
|-------|------|
| `files:read` | 读取频道中分享的文件（含附件内容） |
| `files:write` | 上传文件（bot 发送文件时需要） |
| `remote_files:read` | 读取远程文件（可选） |
| `remote_files:write` | 写入远程文件（可选） |

> **附件说明**：Slack 中的附件（图片、PDF、文档等）通过 `files:read` 访问。OpenClaw 接收到文件消息后，会自动下载内容传给 AI 处理。`mediaMaxMb` 默认 20 MB，超出则忽略。

### 4.3 Channel 成员变动权限

| Scope | 用途 |
|-------|------|
| `channels:read` | 查看频道信息（含成员列表） |
| `channels:join` | 让 bot 自动加入公共频道（可选） |
| `users:read` | 查看工作区成员信息（member joined/left 事件中的用户详情） |
| `users:read.email` | 读取成员邮箱（OpenClaw 需要） |

### 4.4 Pin（置顶）相关权限

| Scope | 用途 |
|-------|------|
| `pins:read` | 查看频道置顶内容 |
| `pins:write` | 添加/移除置顶 |

### 4.5 可选增强权限

| Scope | 用途 | 是否推荐 |
|-------|------|---------|
| `chat:write.customize` | 发消息时自定义 bot 用户名和头像 | 推荐 |
| `chat:write.public` | 向 bot 未加入的公共频道发消息 | 按需 |
| `assistant:write` | 启用 AI 助理状态（打字指示器/流式输出）| 推荐 |
| `emoji:read` | 读取自定义 emoji 列表 | 推荐 |
| `team:read` | 读取工作区名称/图标 | 推荐 |
| `usergroups:read` | 读取用户组信息 | 按需 |

---

## 5. 订阅 Events（事件）

在左侧菜单 **Event Subscriptions** → **Subscribe to bot events** 下添加：

### 5.1 消息事件（必填）

| Event | 说明 |
|-------|------|
| `app_mention` | 有人 @ 了 bot |
| `message.channels` | 公共频道中的新消息 |
| `message.groups` | 私有频道中的新消息 |
| `message.im` | DM（私信）中的新消息 |
| `message.mpim` | 群组 DM 中的新消息 |

### 5.2 Reaction 事件

| Event | 说明 |
|-------|------|
| `reaction_added` | 有人在消息上加了 Emoji |
| `reaction_removed` | 有人移除了 Emoji |

### 5.3 成员变动事件（Channel join/leave）

| Event | 说明 |
|-------|------|
| `member_joined_channel` | 有成员加入了频道（含 bot 自身） |
| `member_left_channel` | 有成员离开了频道 |

### 5.4 频道管理事件（可选）

| Event | 说明 |
|-------|------|
| `channel_rename` | 频道被重命名 |
| `channel_created` | 新频道被创建 |
| `channel_archive` | 频道被归档 |
| `channel_unarchive` | 频道解除归档 |

### 5.5 Pin 事件（可选）

| Event | 说明 |
|-------|------|
| `pin_added` | 消息被置顶 |
| `pin_removed` | 置顶被移除 |

### 5.6 App Home

在左侧菜单 **App Home** → 启用 **Messages Tab**，允许用户通过 App Home 给 bot 发 DM。

---

## 6. 安装 App 到工作区 & 获取 Bot Token

1. 左侧菜单 **OAuth & Permissions** → 点击 **Install to Workspace**
2. 授权后，页面显示 `Bot User OAuth Token`（`xoxb-...` 格式）
3. 复制并保存此 token

---

## 7. 配置 OpenClaw

编辑 `~/.openclaw/openclaw.json`：

```json5
{
  channels: {
    slack: {
      enabled: true,
      mode: "socket",           // Socket Mode，无需公网 IP
      appToken: "xapp-1-...",  // App-Level Token（connections:write）
      botToken: "xoxb-...",    // Bot User OAuth Token
    },
  },
}
```

或通过环境变量（仅适用于默认账号）：

```bash
export SLACK_APP_TOKEN=xapp-1-...
export SLACK_BOT_TOKEN=xoxb-...
```

启动网关：

```bash
openclaw gateway
```

---

## 8. 配置 Select Channel（指定频道）

OpenClaw 支持精细化控制 bot 在哪些频道响应。

### 8.1 全局开放（响应所有频道中的 @提及）

```json5
{
  channels: {
    slack: {
      enabled: true,
      mode: "socket",
      appToken: "xapp-1-...",
      botToken: "xoxb-...",
      // 默认：有人 @ bot 才回复（group channels）
    },
  },
}
```

### 8.2 仅响应特定频道（按 Channel ID）

> **如何获取 Channel ID**：在 Slack 中右键频道名 → **查看频道详情**，或从频道 URL 中复制（`C` 开头的字符串）。

```json5
{
  channels: {
    slack: {
      enabled: true,
      mode: "socket",
      appToken: "xapp-1-...",
      botToken: "xoxb-...",
      channels: {
        // 只允许 #general 和 #ai-assistant 两个频道
        "C1234567890": {       // #general 的 Channel ID
          allow: true,
          requireMention: true,   // 必须 @bot 才触发
        },
        "C0987654321": {       // #ai-assistant 的 Channel ID
          allow: true,
          requireMention: false,  // 无需 @bot，监听所有消息
          users: ["U111", "U222"], // 可选：只响应这些用户
          systemPrompt: "保持简洁，用中文回答。",
        },
      },
    },
  },
}
```

### 8.3 使用频道名称（需谨慎）

```json5
{
  channels: {
    slack: {
      channels: {
        "#general": {
          allow: true,
          requireMention: true,
        },
      },
    },
  },
}
```

> **注意**：频道名称可能变更，建议优先使用 Channel ID（`C...` 格式），更稳定可靠。若要使用名称匹配，需开启 `dangerouslyAllowNameMatching: true`（有性能开销）。

### 8.4 阻止特定频道

```json5
{
  channels: {
    slack: {
      channels: {
        "C_BLOCKED_CHANNEL": {
          allow: false,  // 明确禁止
        },
      },
    },
  },
}
```

### 8.5 Group Policy（群组策略）

控制 bot 在频道（非 DM）中的默认行为：

```json5
{
  channels: {
    slack: {
      groupPolicy: "allowlist",  // 只响应 channels 配置中 allow:true 的频道
      // "open"     → 响应所有频道（@提及仍然有效）
      // "allowlist"→ 只响应明确配置的频道（默认，更安全）
      // "disabled" → 完全不响应频道消息（只响应 DM）
    },
  },
}
```

### 8.6 完整配置示例（生产环境推荐）

```json5
{
  channels: {
    slack: {
      enabled: true,
      mode: "socket",
      appToken: "xapp-1-...",
      botToken: "xoxb-...",
      
      // DM 访问控制
      dmPolicy: "pairing",   // 新用户需要配对验证（安全）
      dm: {
        enabled: true,
        groupEnabled: false,  // 群组DM默认关闭
      },
      
      // 群组/频道默认策略
      groupPolicy: "allowlist",
      
      // 指定允许的频道
      channels: {
        "C_GENERAL": {
          allow: true,
          requireMention: true,   // #general 只在 @bot 时响应
        },
        "C_AI_BOT": {
          allow: true,
          requireMention: false,  // #ai-bot 频道监听所有消息
          systemPrompt: "你是团队的 AI 助手。",
        },
      },
      
      // 消息历史
      historyLimit: 50,
      
      // 响应方式
      replyToMode: "first",     // 第一条消息触发对话时创建线程
      
      // 流式输出（打字指示器）
      streaming: "partial",
      nativeStreaming: true,     // 需要 assistant:write scope
      
      // 确认反应（bot 收到消息时发 emoji 表示"已收到"）
      typingReaction: "hourglass_flowing_sand",
      
      // Actions 开关
      actions: {
        reactions: true,    // 允许 bot 操作 Emoji reaction
        messages: true,     // 允许读/发/编辑/删消息
        pins: true,         // 允许操作置顶
        memberInfo: true,   // 允许查询成员信息
        emojiList: true,    // 允许列出自定义 emoji
      },
      
      // 文件上传限制
      mediaMaxMb: 20,
    },
  },
}
```

---

## 9. 权限详解

### 9.1 发送消息

| 场景 | 需要的 Scope | 说明 |
|------|-------------|------|
| 发普通消息 | `chat:write` | 必填 |
| 向未加入的公共频道发消息 | `chat:write.public` | 可选 |
| 自定义 bot 用户名/头像 | `chat:write.customize` | 推荐 |
| 发文件（上传） | `files:write` | 需要时添加 |

### 9.2 读取文件和附件

Slack 中"附件"的访问路径：

1. 用户上传文件 → Slack 生成 `files.url_private`（私有 URL）
2. OpenClaw 用 bot token 携带 `Authorization` header 下载文件内容
3. 文件内容传给 AI 处理（图片/PDF/文档等）

**所需 Scope**：
- `files:read` — 读取频道中分享的文件（**必填**）
- `channels:history` / `groups:history` — 读取含附件的消息历史（**必填**）

**配置限制**：

```json5
{
  channels: {
    slack: {
      mediaMaxMb: 20,  // 默认 20MB，超出忽略
    },
  },
}
```

### 9.3 Emoji Reaction（反应）

OpenClaw 使用 Reaction 的两个场景：

| 场景 | 配置项 | 所需 Scope |
|------|--------|-----------|
| 收到消息时发确认 emoji（如 👀） | `ackReaction` | `reactions:write` |
| 处理中临时 emoji（如 ⏳）| `typingReaction` | `reactions:write` |
| 接收/处理用户的 reaction 事件 | 订阅 `reaction_added` 事件 | `reactions:read` |

配置示例：

```json5
{
  channels: {
    slack: {
      ackReaction: "eyes",                    // 👀 收到消息时
      typingReaction: "hourglass_flowing_sand", // ⏳ 处理中
      reactionNotifications: "own",           // 只通知 bot 发的消息上的 reaction
      // "off"      → 不接收 reaction 通知
      // "own"      → 只接收 bot 消息上的 reaction（默认）
      // "all"      → 接收所有消息上的 reaction
      // "allowlist"→ 只接收 reactionAllowlist 中用户的 reaction
    },
  },
}
```

### 9.4 成员 Join/Leave 事件

当有人加入或离开频道时，OpenClaw 会接收事件并映射为系统消息：

**所需事件订阅**：
- `member_joined_channel`
- `member_left_channel`

**所需 Scope**：
- `channels:read` — 读取频道成员列表
- `users:read` — 解析成员信息（用户名、头像等）

这些事件会被 OpenClaw 映射成系统事件，AI agent 可以根据成员变动做出响应（如欢迎新成员）。

### 9.5 Pin（置顶）操作

| 操作 | 所需 Scope | 所需事件 |
|------|-----------|--------|
| 读取置顶内容 | `pins:read` | `pin_added` / `pin_removed` |
| 添加/移除置顶 | `pins:write` | — |

```json5
{
  channels: {
    slack: {
      actions: {
        pins: true,  // 开启置顶操作能力
      },
    },
  },
}
```

---

## 10. App Manifest 一键配置

可在创建 App 时直接导入此 YAML Manifest，自动配置所有必要权限和事件。

访问 [api.slack.com/apps](https://api.slack.com/apps) → **Create New App** → **From an app manifest**

Manifest 文件：[docs/openclaw/manifest.yaml](manifest.yaml)



导入后，在 **Basic Information → App-Level Tokens** 中生成带 `connections:write` scope 的 App Token。

---

## 11. 故障排查

### Socket Mode 未连接

```
Error: socket mode not connecting
```

检查项：
- `appToken` 是否为 `xapp-1-...` 格式（不是 bot token）
- App Token 的 Scope 是否包含 `connections:write`
- Slack app 设置中 Socket Mode 是否已开启
- 网络出站 443 端口是否畅通（`curl https://slack.com` 测试）

### 频道消息无响应

检查项：
- Bot 是否已被邀请进入该频道（`/invite @OpenClaw`）
- 是否订阅了 `message.channels` 或 `message.groups` 事件
- `groupPolicy` 是否为 `allowlist` 但未在 `channels` 中配置该频道
- 是否需要 `requireMention: false` 才能响应非 @mention 消息

### DM 无响应

检查项：
- 是否订阅了 `message.im` 事件
- `dm.enabled` 是否为 `true`（默认 true）
- `dmPolicy` 是否为 `pairing`（新用户需先配对：`openclaw pairing approve slack <code>`）
- App Home 中 **Messages Tab** 是否已启用

### 文件/附件无法读取

检查项：
- Bot Token Scopes 是否包含 `files:read`
- 是否包含对应频道类型的 `history` Scope（`channels:history` / `groups:history`）
- 文件大小是否超过 `mediaMaxMb`（默认 20MB）

### Reaction 不工作

检查项：
- Bot Token Scopes 是否包含 `reactions:write`
- 是否订阅了 `reaction_added` / `reaction_removed` 事件
- `ackReaction` 使用的是 shortcode 格式（如 `"eyes"`）而不是 emoji 字符（`"👀"`）

---

## 参考链接

- [OpenClaw Slack 频道文档](https://docs.openclaw.ai/channels/slack)
- [OpenClaw 配置参考 - Slack 部分](https://docs.openclaw.ai/gateway/configuration-reference#slack)
- [Slack Socket Mode 官方文档](https://docs.slack.dev/apis/events-api/using-socket-mode)
- [Slack Bot Token Scopes 列表](https://docs.slack.dev/reference/scopes)
- [Slack App 管理后台](https://api.slack.com/apps)
