# Plan: RPi 5 部署方案 — Muliao 极简 AI 助手设备

> **定位说明**：本文档专注于**硬件与基础设施层**——RPi 5 设备形态、Docker 编排、OS 镜像、网络配置、云端 Relay 架构。Muliao 的应用层能力（赫耳墨斯 HR 流程、团队管理、自然成长机制等）属于独立的设计范畴，见 [docs/design.md](../design.md)。两层之间的关系：本文档解决"设备怎么跑起来"，design.md 解决"Agent 怎么工作"。

## TL;DR

将 Muliao 打包为**预装好的 RPi 5 成品设备**，用户拿到手后插电联网即可使用。底层仍是 Docker，用户通过 **`muliao.io` 云端 PWA** 完成设备初始化和日常管理——手机浏览器访问 `muliao.io`，PWA 通过云端中继与局域网内的 RPi 设备通信，将所有 IT 概念对用户完全隐藏。分两个大阶段推进：**Phase A（团队辅助部署）** → **Phase B（DIY 开箱即用）**。

---

## 一、产品形态定义

### 硬件 BOM

| 组件 | 选型 | 说明 |
|------|------|------|
| 主板 | RPi 5 16GB | 充足内存跑 Docker + Chromium + 多容器 |
| 存储 | NVMe SSD 256GB（via M.2 HAT） | 可靠读写、长期运行不担心 SD 卡寿命 |
| 电源 | 官方 27W USB-C | 稳定供电，NVMe HAT 需要额外功耗 |
| 外壳 | 支持 NVMe HAT 的散热外壳（如 Argon ONE V3 M.2 / Pimoroni NVMe Base） | 被动散热 + 整洁外观 |
| 网络 | 板载千兆以太网 / WiFi 6 | Phase A 用网线；Phase B 可能无网口（CM5 自研载板），WiFi AP 配网 |
| 可选 | 状态显示小屏（SSD1306 OLED 0.96"） | 显示 IP、运行状态、心跳指示——后期加分项 |

### 软件架构分层

```
┌──────────────────────────────────────────────────────┐
│  muliao.io（云端）                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │ PWA 前端     │  │ Relay 服务   │  │ 用户账号   │ │
│  │ (静态托管)   │  │ (WebSocket)  │  │ & 设备绑定 │ │
│  └──────┬───────┘  └──────┬───────┘  └────────────┘ │
│         │    HTTPS         │                          │
└─────────┼─────────────────┼──────────────────────────┘
          │                  │
   用户手机浏览器      RPi 主动外连（outbound WebSocket）
   访问 muliao.io    无需端口转发 / NAT 穿透
          │                  │
          ▼                  ▼
┌─────────────────────────────────────────┐
│  RPi 5 设备                              │
├─────────────────────────────────────────┤
│  Docker Compose                          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│  │ OpenClaw │ │ Device   │ │ Watchtower│ │
│  │ (Agent)  │ │ Agent    │ │ (更新)    │ │
│  └──────────┘ └──────────┘ └──────────┘ │
├─────────────────────────────────────────┤
│  Ubuntu Server 24.04 LTS (64-bit)       │
│  + Docker CE                            │
└─────────────────────────────────────────┘
│  NVMe SSD / RPi 5 16GB / 网络           │
└─────────────────────────────────────────┘

用户触点：
  - Telegram / WhatsApp / 飞书 ←→ RPi（通过 IM 服务器中转）
  - muliao.io PWA ←→ RPi（通过云端 Relay 中转）
```

---

## 二、关键 UX 难题与方案

### 核心交互界面：muliao.io 云端 PWA

所有目标客户都是手机用户。用户访问 **`muliao.io`**（云端托管的 PWA），通过云端中继与局域网内的 RPi 设备通信。可"添加到主屏幕"获得 App 级体验。

**为什么是云端 PWA（`muliao.io`）而非本地 Web（`muliao.local`）：**
- 用户只需记住一个正常网址 `muliao.io`，无需理解局域网地址
- 彻底规避 mDNS 兼容性问题（Android 部分机型 / 部分路由器不支持 `.local`）
- HTTPS 天然可用（云端域名正规证书），PWA 安装和 Service Worker 都需要 HTTPS
- **不在同一 WiFi 也能管理设备**——出门在外也能查看助手状态、改设置
- 后续加 Push Notification、用户账号体系、多设备管理都是顺理成章的事

**设备发现与通信机制：**
- RPi 启动后，Device Agent 主动通过 WebSocket 外连 `muliao.io` 云端 Relay
- 用户在 `muliao.io` 登录后，PWA 通过 Relay 与自己绑定的设备通信
- 所有通信都是 RPi **主动外连**，无需端口转发、无需用户配置路由器
- 参考：Home Assistant Cloud (Nabu Casa)、Plex Remote Access 均采用类似架构

**用户入口策略：PWA Web + Capacitor iOS/Android App（同一套前端代码，两个分发渠道）**

- **Web 版（muliao.io）**：桌面浏览器访问、首次体验、无需装 App 的场景——任何设备都能用
- **iOS/Android App（Capacitor Shell）**：App Store / Google Play 分发，原生 BLE 桥接解决 WiFi 配网，APNs Push 更可靠，Keychain 保护敏感数据——手机用户的首选
- **前端代码唯一**：Vue/React 页面只写一遍，`npx cap sync` 同步到原生项目；Capacitor 插件通过 JS Bridge 暴露原生能力，Web 逻辑无需感知平台差异
- 设置 Telegram Bot 时，同一台手机上切换 Telegram ↔ App 粘贴 Token，零跨设备摩擦
- 桌面浏览器也能访问，不需要额外适配

**PWA 承担的角色（覆盖全生命周期）：**
1. **开箱引导** — 首次设置向导：配对设备、选场景、配 Telegram、个性化
2. **日常管理** — 状态仪表盘、助手设置、推送频率调整
3. **系统维护** — 更新、备份、日志查看
4. **远程管理** — 不在家也能查看设备状态和调整配置
5. **未来扩展** — 多团队管理、产品知识库编辑（丽姐场景）、研究兴趣编辑（文哲场景）

### 难题 1: API Key 配置（最大门槛）

丽姐和文哲不知道什么是 API Key。这是非技术用户面前最大的障碍。

**Phase A 方案（团队辅助 / muliao.io 引导）：**
- 由团队成员在设备出厂前完成 API Key 配置；或通过 muliao.io PWA 远程引导用户完成
- API Key 写入设备本地，不上传云端

**Phase B 方案（DIY），可选路径：**

| 方案 | UX | 复杂度 | 推荐 |
|------|-----|--------|------|
| **B1: API 代理服务** — 你运营一个云端代理，用户按月付费，无需自己管 Key | ⭐⭐⭐⭐⭐ | 高（需运营 billing + proxy） | ✅ 长期方向 |
| **B2: 图文引导** — Web 门户内嵌截图 + 视频，手把手教用户去 Google AI Studio / OpenAI 申请 Key | ⭐⭐⭐ | 中 | ✅ MVP 可行 |
| **B3: OAuth 登录** — 对支持 OAuth 的提供商（Google），用"用微信扫码登录"式体验 | ⭐⭐⭐⭐ | 中高 | ⬜ 适合后期 |

**推荐**：Phase A 用团队辅助；Phase B 先做 B2（图文引导），同时规划 B1（代理服务）作为终极方案。

### 难题 2: Telegram Bot 创建

用户需要和 @BotFather 交互创建 Bot 并获取 Token。

**Phase A 方案：**
- 团队成员为每位用户预创建 Bot，Token 预写入设备
- 或远程辅助用户完成（发截图引导）

**Phase B 方案：**
- Web 门户内嵌交互式引导：
  1. "打开 Telegram，搜索 @BotFather"
  2. "发送 /newbot"
  3. "给你的助手起个名字（比如：丽姐的销售助手）"
  4. "把 BotFather 回复中的那串长数字粘贴到下面"
  5. 实时验证 Token 有效性，成功后自动配置
- 全过程用中文截图引导，预计 3-5 分钟

### 难题 3: 网络发现（已由云端架构解决）

用户插上网线/连上 WiFi 后，怎么找到设备？

**在 `muliao.io` 架构下，这个问题基本消失：**
- RPi 启动后 Device Agent 主动连接 `muliao.io` 云端
- 用户在 `muliao.io` 上看到设备自动上线，无需手动输入任何地址
- 设备发现 = 后端匹配（Device Agent 上报 → 云端关联到用户账号 → PWA 显示设备在线）

**配对方式（首次绑定设备到用户账号）：**
- **Phase A**：团队出厂前预绑定，用户无感
- **Phase B**：设备附带配对码（印在说明卡片上 / OLED 屏显示），用户在 `muliao.io` 输入配对码完成绑定

**离线 fallback（可选）：**
- 保留 Avahi mDNS，设备仍可通过 `muliao.local` 局域网直连（备用）
- OLED 小屏显示 IP + 配对码（后期加分项）

### 难题 4: 首次联网（WiFi 配网）

无屏设备的经典鸡生蛋问题：**设备还没联网 → 没法访问 muliao.io → 没法配置 WiFi**。

**Phase A：网线直连（最简单）**
- 说明卡写"请用网线连接路由器"，网线插上就有网，零配置
- RPi 5 有千兆以太网口，即插即用
- 随设备附带一根短网线，成本几块钱
- **Phase A 全部用网线，不考虑 WiFi 配网**

**Phase B：WiFi AP 模式（智能硬件标准做法）**

Phase B 可能使用 RPi 5 CM（Compute Module）+ 自研载板，没有以太网口，必须走 WiFi。采用智能家居设备的通用做法（Google Home、小米 IoT、ESP32 设备均如此）：

```
RPi 首次启动，检测到无网络连接
  │
  ├─ 自动创建 WiFi 热点："Muliao-XXXX"（XXXX = 配对码后 4 位）
  │   └─ 开放网络（无密码），仅用于配网，配网后自动关闭
  │
  ├─ 用户手机连接这个热点
  │   └─ 自动弹出 Captive Portal（或引导访问 192.168.4.1）
  │
  ├─ 配网页面（纯本地，极简 HTML）：
  │   ├─ "选择你家的 WiFi" → 列出扫描到的 SSID
  │   └─ "输入 WiFi 密码"
  │
  ├─ 提交 → RPi 尝试连接
  │   ├─ 成功 → 关闭热点 → 切到正常模式 → Device Agent 上线
  │   │   └─ 页面提示："连接成功！请切回家庭 WiFi，打开 muliao.io 继续"
  │   └─ 失败 → 提示"密码可能不对，请重试"
  │
  └─ 后续启动：已保存的 WiFi 自动连接，无需重复配网
```

**实现方式：**
- `hostapd` + `dnsmasq` 创建 AP + DHCP + DNS 劫持（Captive Portal）
- 极简本地 Web 页面（纯 HTML + vanilla JS，< 50KB）专做 WiFi 配置
- systemd 服务：开机检测网络 → 无网 → AP 模式 → WiFi 配好 → 正常模式
- AP ↔ Station 模式切换由 `muliao-wifi-setup.service` 管理

**备选：蓝牙配网（BLE Provisioning）+ iOS 原生 App = PWA Shell**

与其只做一个极简配网工具，不如直接把 **muliao.io PWA 整体包进原生 iOS App**（Capacitor 方案）：

- **核心思路**：App 内核是 WKWebView 加载 muliao.io，与 Web 版完全共享同一套前端代码；Capacitor 插件层为 Web 侧提供原生能力桥接
- **BLE 问题就此根治**：Web Bluetooth API 在 iOS Safari 永久不可用，但 Capacitor 的 `@capacitor-community/bluetooth-le` 插件可通过 JS Bridge 调用原生 CoreBluetooth，配网流程在 App 内原生完成
- **额外收益**：
  - App Store 上架 → 用户主动搜索安装，无需手动"添加到主屏幕"
  - 原生 Push Notification（APNs），比 PWA Service Worker 推送更可靠
  - WKWebView 内可访问 Keychain 保护 API Key，不依赖 LocalStorage
  - Xcode 打包一次，iPhone + iPad 通吃
- **Android 同理**：Capacitor 同一套代码构建 APK；Web Bluetooth 在 Android Chrome 已原生支持，可作为增强而非必需
- **Web 版继续保留**：桌面浏览器、不想装 App 的用户仍可直接访问 muliao.io——App 与 Web 是同一个产品的两个分发渠道，不是两套代码

**实现拆分：**

| 层次 | 内容 | 维护方式 |
|------|------|----------|
| 前端逻辑 | Vue/React + PWA 全部页面 | 统一在 muliao.io 仓库维护 |
| 原生 Shell | Capacitor iOS 项目（`ios/`） | 只在发版时 `npx cap sync` + Xcode 打包 |
| 原生插件 | BLE、APNs Push、Keychain、生物识别 | 按需引入 Capacitor 社区插件 |

**优先级**：AP 模式（无 App）仍是 Phase B 的首选路径；iOS App = Phase B 增强选项，也是长期产品化的必经之路。

---

## 三、部署流程设计

### Phase A: 团队辅助部署（MVP）

此阶段由你/团队成员在设备交付前完成大部分配置。用户体验 = 插电即用。

#### 出厂准备流程（团队操作）

```
Step 1: 烧录系统镜像
  └─ Ubuntu Server 24.04 LTS 镜像 → NVMe SSD
  └─ 写入 cloud-init user-data，首次启动自动安装 Docker、拉取 Muliao 镜像、启用 systemd services

Step 2: 首次启动 & 基础配置
  └─ 接上网络，设备自动连接 muliao.io 云端
  └─ 通过 muliao.io PWA 完成配置（或 SSH 辅助）：
      - 配对设备到用户账号
      - 配置 API Keys（Gemini / OpenAI / Anthropic）
      - 创建 Telegram Bot，写入 Token
      - 选择场景模板（销售助手 / 研究助手）
      - 配置用户信息（名字、时区、语言）

Step 3: 验收测试
  └─ Telegram 发消息确认 Agent 回复正常
  └─ 检查心跳任务、定时任务
  └─ 备份初始配置

Step 4: 交付
  └─ 设备 + 电源 + 网线 + 简单说明卡片
  └─ 说明卡片内容：插电、连网线、打开 Telegram 跟 XXX 说话
  └─ 卡片上印有配对码（Phase B 需要；Phase A 已预绑定可省略）
```

#### 用户日常操作

用户完全通过 Telegram 与 AI 助手交互，不需要接触任何技术界面。

#### 远程维护

- **Tailscale**：设备出厂前安装 Tailscale，加入你的 tailnet
- 你可以随时远程 SSH 进设备排查问题、更新配置
- 用户无感知

### Phase B: DIY 开箱即用（迭代目标）

此阶段目标 = 用户自己完成全部设置，无需技术人员介入。

#### 开箱体验设计

```
用户拿到设备
  │
  ├─ 1. 插电
  │     └─ 设备启动，约 60 秒后就绪
  │
  ├─ 1.5 连接网络
  │     ├─ 有网线？插上即可，跳到步骤 2
  │     └─ 纯 WiFi？手机连接 "Muliao-XXXX" 热点
  │           └─ 弹出配网页面 → 选择家庭 WiFi → 输密码 → 连接成功
  │           └─ 手机切回家庭 WiFi
  │
  ├─ 2. 手机浏览器访问 muliao.io（扫说明卡上的二维码，或直接输入网址）
  │     └─ 看到欢迎页面："你好！让我们花 5 分钟把你的 AI 助手设置好"
  │
  ├─ 3. 配对设备
  │     └─ 输入说明卡上的配对码（6 位数字）→ 设备自动绑定到账号
  │
  ├─ 4. 设置向导（muliao.io）
  │     ├─ 选择场景："我想用来…" → 销售助手 / 研究助手
  │     ├─ 设置 Telegram（交互式截图引导）
  │     ├─ 配置 AI 能力（API Key 或付费订阅）
  │     └─ 个性化："你希望助手叫你什么？"
  │
  ├─ 5. 完成！
  │     └─ "设置完成！现在去 Telegram 找 [你的助手名字] 说句话试试 👋"
  │     └─ 提示"添加到主屏幕"获得 App 级体验
  │
  └─ 日常管理（muliao.io，随时随地可访问）
        ├─ 系统状态：运行中 ✅ / 内存 48% / 存储 12%
        ├─ 助手设置：修改名字、调整推送频率
        └─ 系统更新：一键更新（或自动更新）
```

---

## 四、技术实现步骤

### Step 1: Docker Compose 化（当前 → Compose）
*前置：无依赖*

当前 `run.sh` 使用 raw `docker run`，需迁移到 Docker Compose 以支持多容器编排。

**新增文件**: `docker/docker-compose.yml`

**Services 定义：**
- `openclaw` — 主 Agent 容器（基于现有 Dockerfile）
- `device-agent` — 设备代理（维持与 `muliao.io` 云端 Relay 的 WebSocket 长连接，转发配置指令到本地）
- `watchtower` — 自动更新容器镜像（containrrr/watchtower）

**关键设计：**
- `run.sh` 保留作为 Compose 的 wrapper，向后兼容
- 环境变量从 `.env` 文件读取（替代目前在 run.sh 中 pass-through）
- Volume 挂载保持与现有 `teams/` 结构一致

### Step 2: Ubuntu Server 镜像构建（cloud-init）
*前置：无依赖，可与 Step 1 并行*

**新增目录**: `deploy/rpi/`

**基础 OS：Ubuntu Server 24.04 LTS (Noble Numbat) 64-bit for RPi**

选择 Ubuntu 而非 RPi OS 的理由：
- **cloud-init**：Ubuntu 镜像原生集成 cloud-init，首次启动时自动执行声明式 YAML 配置，无需维护 pi-gen 构建流水线
- **10 年 LTS**：24.04 LTS 安全更新到 2034（RPi OS 无明确 EOL 承诺）
- **开发者友好**：snap、netplan、APT 生态更完善，老陈等 power user 可自行扩展
- **可移植性**：同一 cloud-init 配置可复用到 cloud VPS、CM5、其他 SBC
- **K3s / MicroK8s**：未来如需编排升级，Ubuntu 是 Canonical 主场

**镜像构建方案：**

无需自行构建 `.img`，直接使用 Canonical 官方预编译镜像 + cloud-init 自定义：

1. 下载 `ubuntu-24.04-preinstalled-server-arm64+raspi.img.xz`
2. 烧录到 NVMe SSD
3. 在 `system-boot` 分区写入 `user-data`（cloud-init YAML）
4. 首次开机时 cloud-init 自动完成所有初始化

**cloud-init `user-data` 配置要点：**

```yaml
#cloud-config
package_update: true
packages:
  - docker-ce
  - docker-compose-plugin
  - avahi-daemon          # 局域网 fallback
  - tailscale
  - hostapd               # WiFi AP 配网
  - dnsmasq               # WiFi AP DHCP/DNS

runcmd:
  # 预拉取 Docker 镜像
  - docker pull ghcr.io/teabots/muliao:latest
  - docker pull containrrr/watchtower
  # 启用 Muliao 服务
  - systemctl enable --now muliao.service

write_files:
  - path: /etc/systemd/system/muliao.service
    content: |  # systemd unit（开机自启 Docker Compose）
      ...
```

**新增文件：**
- `deploy/rpi/user-data` — cloud-init 配置（声明式 YAML，一切初始化逻辑集中于此）
- `deploy/rpi/flash-ssd.sh` — 烧录 + 注入 cloud-init 的自动化脚本
- `deploy/rpi/muliao.service` — systemd unit file
- `deploy/rpi/wifi-setup/` — WiFi AP 配网服务（hostapd 配置 + Captive Portal 页面 + systemd service）

### Step 3: 场景模板系统
*前置：无依赖，可与 Step 1/2 并行*

> **注**：本节只定义模板的**文件结构和部署位置**，属于基础设施范畴。各文件的具体内容（人格设定、Skill 组合、HR 流程等）由应用层决定，见 [docs/design.md](../design.md)。

当前 `teams/default/workspace/` 是通用模板。需要为丽姐和文哲创建专属场景模板。

**新增目录**: `templates/`

```
templates/
  sales-assistant/       ← 丽姐场景
    workspace/
      SOUL.md            — 销售助手人格
      IDENTITY.md        — 名字/头像/调性
      USER.md            — 模板（首次使用时填入真实用户信息）
      AGENTS.md          — 销售场景的操作手册
      TOOLS.md           — 空模板
      skills/
        product-kb/SKILL.md    — 产品知识库 Skill（模板）
        customer-analysis/SKILL.md — 客户画像分析 Skill
    config-overlay.json  — 场景特定的 openclaw.json 覆盖项
  research-assistant/    ← 文哲场景
    workspace/
      SOUL.md            — 研究助手人格
      IDENTITY.md
      USER.md
      AGENTS.md
      skills/
        paper-search/SKILL.md  — 复用已有设计
      core-interests.md  — 研究兴趣配置文件
    config-overlay.json
```

**设置流程**：用户在 Web 门户选择场景后，`muliao-setup` 脚本将对应模板复制到 `teams/<name>/workspace/` 并应用 config overlay。

### Step 4: muliao.io 云端 PWA + Device Agent
*依赖：Step 1（Compose 结构），Step 3（模板）*

这是整个用户体验的核心入口。拆分为两个子项目：

#### Step 4a: muliao.io 云端服务（独立部署）

**独立仓库 / 部署单元**（不在 RPi 上运行）

**技术选型：**
- 前端 PWA：Vue 3 / React，手机优先响应式设计，PWA manifest + Service Worker
- 后端：Node.js (Express/Fastify) 或 Python (FastAPI)
- WebSocket Relay：负责转发 PWA ↔ Device Agent 之间的指令
- 用户账号：邮箱 / 手机号注册，设备绑定（一个账号可绑多台设备）
- 托管：Cloudflare Pages (静态) + Fly.io / Railway (后端 + Relay)
- 域名：`muliao.io`，HTTPS 标配

**PWA 特性：**
- `manifest.json`：图标、名称、主题色，支持"添加到主屏幕"
- Service Worker：缓存静态资源（离线显示"设备离线"提示页），Push Notification
- 全屏模式（`display: standalone`）：从主屏幕启动时看起来像原生 App

**核心页面：**
1. **开箱向导**（首次使用）
   - 注册 / 登录账号
   - 配对设备：输入配对码（6 位数字）
   - 选场景："我想用来…" → 销售助手 / 研究助手
   - 设置 Telegram：交互式引导 + 截图 + 实时验证 Token
   - 配置 AI：API Key 输入 + 连通性验证（或 → 付费订阅选项）
   - 个性化：称呼、时区、语言
   - 完成："去 Telegram 跟你的助手打个招呼吧！"
2. **状态仪表盘**（日常）
   - 运行状态 ✅ / 内存 / 存储 / 网络
   - Telegram 连接状态
   - 最近对话摘要
3. **助手设置**
   - 修改称呼、推送频率、心跳时间段
   - 丽姐：编辑产品知识库（文本输入即可）
   - 文哲：编辑研究兴趣关键词
4. **系统管理**
   - 查看日志（简化版）
   - 一键更新
   - 备份 / 恢复
   - "允许远程协助"开关

**安全考虑：**
- 用户账号 + 设备绑定，非绑定用户无法访问设备
- API Key 通过 Relay 加密传输到设备本地存储，**云端不留存 API Key**
- API Key 在 PWA 前端脱敏显示
- Relay 仅转发指令，不存储对话内容（隐私优先）

#### Step 4b: Device Agent（RPi 端组件）

**新增目录**: `device-agent/`

Device Agent 是 RPi 端的轻量服务，负责：
- 启动时通过 outbound WebSocket 连接 `muliao.io` 云端 Relay
- 接收并执行来自 PWA 的配置指令（写入 openclaw.json、应用模板等）
- 上报设备状态（CPU / 内存 / 存储 / 容器健康）
- 管理配对码生成与验证

**技术选型：**
- 语言：Node.js（与 OpenClaw 生态一致）
- 通信：WebSocket client → `wss://relay.muliao.io`
- 容器化：独立 Dockerfile，纳入 Docker Compose

**关键设计：**
- 配对码在设备首次启动时生成（6 位数字，有效期 24 小时）
- 配对成功后，设备与用户账号绑定，后续自动认证
- 所有敏感配置（API Key、Bot Token）仅写入设备本地，不上传云端
- 断线自动重连（指数退避），设备 ID 持久化

### Step 5: 自动更新机制
*依赖：Step 1（Compose），Step 2（systemd）*

**方案：Watchtower + 版本标签**

- Watchtower 容器定期检查 `ghcr.io/teabots/muliao:latest` 是否有新镜像
- 发现更新 → 拉取新镜像 → 优雅重启 OpenClaw 容器
- 通过 Telegram 通知用户："系统已自动更新到 v2026.4.1 ✅"

**保守策略（推荐）：**
- 不自动更新，而是在 Web 门户显示"有新版本可用"
- 用户点击"更新"按钮 → 触发更新流程
- 避免自动更新导致的意外中断

### Step 6: 远程管理通道（Tailscale）
*依赖：Step 2（镜像预装 Tailscale）*

**Phase A 必备：**
- 设备出厂前加入你的 Tailscale tailnet
- 你可以通过 `ssh pi@<tailscale-ip>` 远程排查任何问题
- 用户不需要知道 Tailscale 的存在

**Phase B 可选：**
- 用户可以在 Web 门户选择"允许远程协助"
- 开启后你的团队可以远程连接帮助排查

---

## 五、步骤依赖与并行关系

```
     ┌─── Step 1: Docker Compose 化 ───┐
     │                                   │
     │    ┌─── Step 2: Ubuntu 镜像 ───┐  │
     │    │                           │  │
     │    │    Step 3: 场景模板 ────┐ │  │
     │    │         (全部可并行)     │ │  │
     │    └──────────┬─────────────┘ │  │
     │               │               │  │
     └───────────────┼───────────────┘  │
                     ▼                   │
          Step 4a: muliao.io 云端 PWA  │
          (依赖 Step 3 模板)             │
                     │                   │
          Step 4b: Device Agent          │
          (依赖 Step 1 Compose)          │
                     │                   │
          ┌──────────┼──────────┐        │
          ▼          ▼          ▼        │
     Step 5:    Step 6:                  │
     自动更新    远程管理                 │
     (依赖 1+2) (依赖 2)                 │
```

**推荐执行顺序：**
- **第一批（并行）**：Step 1 + Step 2 + Step 3 + Step 4a（云端 PWA 无硬件依赖，可同步开发）
- **第二批**：Step 4b（Device Agent）— 与 Step 4a 配合联调
- **持续**：Step 5 + Step 6 按需加入

---

## 六、Phase A vs Phase B 功能清单

| 功能 | Phase A（团队辅助） | Phase B（DIY） |
|------|---------------------|----------------|
| 首次联网 | 网线直连 | WiFi AP 配网（蓝牙备选） |
| 系统镜像构建 | ✅ 手动烧录 + cloud-init | ✅ cloud-init 自动化 |
| API Key 配置 | 团队成员代为配置 | PWA 图文引导 / API 代理服务 |
| Telegram Bot | 团队成员预创建 | PWA 交互式引导 |
| 场景模板 | PWA 向导选择 | PWA 可视化选择 |
| 远程维护 | Tailscale SSH | Tailscale + PWA 远程协助开关 |
| 系统更新 | SSH + docker pull | PWA 一键更新 / 自动更新 |
| 状态监控 | muliao.io 仪表盘 | muliao.io 仪表盘 |
| 备份恢复 | CLI backup.sh + PWA | PWA 操作 |
| 多用户/团队 | ❌ 单用户 | ✅ muliao.io 管理多团队 |

---

## 七、涉及的文件变更

### 新增

| 路径 | 用途 |
|------|------|
| `docker/docker-compose.yml` | 多容器编排定义 |
| `docker/.env.example` | 环境变量模板 |
| `deploy/rpi/user-data` | cloud-init 配置（首次启动自动初始化） |
| `deploy/rpi/flash-ssd.sh` | 烧录 Ubuntu 镜像 + 注入 cloud-init 的自动化脚本 |
| `deploy/rpi/muliao.service` | systemd 开机自启服务 |
| `deploy/rpi/README.md` | RPi 部署文档 |
| `deploy/rpi/wifi-setup/` | WiFi AP 配网服务（Captive Portal + hostapd 配置） |
| `device-agent/` | RPi 端设备代理（WebSocket 连接云端、执行配置指令、上报状态） |
| `muliao-cloud/`（独立仓库） | muliao.io 云端服务：PWA 前端 + Relay 后端 + 用户账号 |
| `templates/sales-assistant/` | 丽姐场景模板 |
| `templates/research-assistant/` | 文哲场景模板 |

### 修改

| 路径 | 变更 |
|------|------|
| `docker/run.sh` | 改为 Compose wrapper，向后兼容 |
| `docker/build.sh` | 增加 ARM64 单独构建快捷方式 |
| `readme.md` | 增加 RPi 部署说明 |
| `docs/design.md` | 更新 Roadmap 反映硬件部署方向 |

---

## 八、验证计划

### Phase A 验证

1. **冒烟测试**：从头用自定义镜像烧录 SSD → 首次启动 → PWA setup → Telegram 对话正常
2. **场景测试 — 丽姐**：选择销售助手模板 → Telegram 发送客户问题 → Agent 用销售助手人格回复 → 客户画像生成
3. **场景测试 — 文哲**：选择研究助手模板 → Telegram 发送"搜最近的 diffusion policy 论文" → Agent 返回 arXiv 摘要
4. **稳定性测试**：连续运行 72 小时，检查内存泄漏、容器重启、日志增长
5. **远程管理**：通过 Tailscale SSH 进入设备，执行更新和备份
6. **断电恢复**：拔电重启后，所有服务自动恢复，Telegram 连接重新建立

### Phase B 验证

7. **盲测**：让一个非技术用户（不是团队成员）仅凭说明卡片完成全部设置
8. **PWA 门户**：完成完整设置向导，所有步骤无报错
9. **自动更新**：推送新镜像后，设备在 24 小时内完成更新

---

## 九、决策记录

| 决策 | 选择 | 理由 |
|------|------|------|
| 产品形态 | 预装成品设备 | 用户确认 |
| 硬件 | RPi 5 16GB + NVMe SSD | 用户确认；16GB 为 Chromium + 多容器留足余量 |
| LLM 策略 | 纯云端 API | 用户确认；RPi 做编排和转发，不做本地推理 |
| 初期用户数 | 单用户专属 | 用户确认；后期扩展到团队 |
| 容器编排 | Docker Compose（非 K8s） | RPi 单机场景用 K8s 过重，Compose 足够 |
| 用户入口 | `muliao.io` 云端 PWA + Capacitor iOS/Android App（同一套前端代码） | Web 版全平台可用；App 版解决 iOS BLE 配网、APNs Push、App Store 分发；两者共享同一前端仓库 |
| 设备通信 | 云端 Relay（WebSocket） | RPi 主动外连无需端口转发；参考 Nabu Casa / Plex 架构 |
| 网络发现 | 配对码 + 云端自动匹配（Avahi mDNS 作为局域网 fallback） | 用户输入配对码即可，无需查找设备 IP |
| 远程管理 | Tailscale | 穿透 NAT，无需公网 IP 或端口转发 |
| 自动更新 | Watchtower（保守模式：通知但不自动更新） | 避免意外中断 |
| 基础 OS | Ubuntu Server 24.04 LTS + cloud-init | 10 年 LTS、cloud-init 声明式配置、开发者友好、可移植到 cloud/CM5 |
| 首次联网 | Phase A 网线；Phase B WiFi AP 模式优先，iOS App（Capacitor + BLE）作增强 | 网线零配置最稳；AP 模式是智能硬件标准做法；iOS App = PWA Shell，BLE 配网通过 Capacitor 原生插件实现 |

---

## 十、待进一步讨论

1. **API 计费模式**：长期来看，是否考虑运营 API 代理服务？用户按月付费，你统一管理 API Key？这对丽姐体验最好（完全不用管 Key），但需要你承担运营成本和计费系统开发。当前 Phase A 无此问题（团队辅助配置），但 Phase B 的 DIY 体验很大程度取决于此决策。

2. **设备品牌化**：是否需要给设备起一个面向用户的名字（如"小盒子"/"问问"），让丽姐觉得这是一个产品而不是一台电脑？包括外壳上的 logo、说明卡片的设计等。

3. **离线降级**：断网时 Agent 完全不可用（纯云端 API）。是否需要设计一个"断网提示"机制（比如 OLED 屏显示网络状态、恢复后 Telegram 自动通知用户"我回来了"）？

4. **muliao.io 云端成本**：Relay 服务 + 静态托管 + 用户账号存储，初期免费 tier 方案？Cloudflare Pages (免费静态托管) + Fly.io (免费 tier 小实例) 能否支撑早期用户量？

5. **用户账号体系**：邮箱注册？手机号？微信扫码？需要考虑目标用户习惯。丽姐可能更习惯微信。Phase A 可以手动创建账号。

6. **数据隐私与信任**：Relay 只转发指令不存储对话内容，但用户如何验证这一点？是否需要一个"隐私承诺"页面？API Key 加密传输后仅存储在设备本地——这个设计需要在向导中向用户说明以建立信任。

7. **CM5 自研载板**：Phase B 可能从 RPi 5 迁移到 RPi 5 Compute Module + 自研 Carrier Board。这影响：硬件 BOM（去掉以太网口、自定义接口）、OS 镜像构建（CM5 的 eMMC vs NVMe）、外壳设计。何时启动载板设计？是否先做 CM5 + 官方 IO Board 的验证？
