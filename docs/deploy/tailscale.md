# Tailscale 在幕僚 RPi 部署中的应用

> 本文记录 Tailscale 技术调研结论及在 RPi 部署方案（Step 6：远程管理通道）中的具体设计决策。

---

## 一、Tailscale 是什么

Tailscale 是基于 **WireGuard 协议**构建的零信任 VPN 平台，核心能力是把分散在不同网络中的设备组成一个**点对点 Mesh 网络（tailnet）**。

- 每台设备获得一个稳定的 `100.x.y.z` 私有 IP（Tailscale IP）
- 设备之间直接通信，不经过中心服务器（NAT 穿透成功时）
- NAT 穿透失败时，流量经由 Tailscale 运营的 **DERP 中继服务器**转发
- 身份认证基于设备证书（Node Key），不依赖 IP

**与传统 VPN 的区别：**

| 传统 VPN | Tailscale |
|---------|-----------|
| 中心化流量（所有流量过网关） | 点对点直连 |
| 需要公网 IP / 端口转发 | 自动 NAT 穿透 |
| 用户名/密码认证 | 设备证书 + 身份提供商（Google/GitHub 等） |
| 复杂配置 | 零配置（安装后 `tailscale up` 即接入） |

---

## 二、WireGuard 与 Tailscale 的关系

### WireGuard

- **作者**：Jason A. Donenfeld（网名 zx2c4），独立开发，**与 Tailscale 公司无任何关联**
- **开源协议**：Linux 内核实现 GPLv2，跨平台实现 MIT/BSD
- **内核集成**：Linux 5.6（2020 年）起正式进入内核主线
- **代码规模**：~4,000 行（对比 OpenVPN 的数十万行），极简设计，安全审计友好
- **定位**：纯粹的 VPN **协议 + 内核模块**，只负责加密隧道，不涉及密钥分发和设备管理

### Tailscale

- **创始人**：前 Google 工程师——Avery Pennarun（CEO）、David Crawshaw、Brad Fitzpatrick
- **定位**：基于 WireGuard 协议的**管理层**，解决 WireGuard 本身不处理的问题：
  - 设备发现与密钥自动分发
  - NAT 穿透（DERP 中继）
  - ACL 访问控制策略
  - MagicDNS（设备名解析）
  - Admin Console 集中管理
- **关系比喻**：WireGuard 是引擎，Tailscale 是整车（含导航、遥控、仪表盘）

### 开源替代：Headscale

Headscale 是 Tailscale 控制平面（Control Plane）的开源自托管替代实现，可完全替代 Tailscale 云端服务。幕僚当前 Phase A 不需要，但了解此选项有助于未来评估自托管路线。

---

## 三、Tailscale Admin Console

访问地址：`login.tailscale.com/admin`

主要功能：

| 功能 | 说明 |
|------|------|
| Machines | 查看所有接入设备、状态、Tailscale IP、最后在线时间 |
| Auth Keys | 生成注册 Key（用于设备自动加入 tailnet，无需交互式登录） |
| ACLs | 定义哪些设备/用户可以访问哪些设备 |
| MagicDNS | 设备名自动 DNS 解析（如 `muliao-lijie.tailnet-name.ts.net`） |
| Users | 成员管理（邀请协作者） |
| Logs | 网络活动审计日志 |

### Auth Key 类型

- **一次性（One-off）Key**：使用一次后失效
- **可复用（Reusable）Key**：批量烧录多台设备时推荐；设备注册后 Key 仍可用于下一台
- **Ephemeral Key**：设备下线后自动从 Console 移除（适合 CI/CD 场景）

---

## 四、幕僚 RPi 部署方案中的 Tailscale 设计

### Phase A 角色

```
团队（你）
  │
  └─ Tailscale tailnet
        ├─ 你的开发机
        ├─ muliao-lijie（丽姐的 RPi）   100.64.x.x
        ├─ muliao-wenzhe（文哲的 RPi）  100.64.x.y
        └─ muliao-laoliu（老六的 RPi）  100.64.x.z
```

- **用户无感知**：Tailscale 是团队的运维工具，不暴露给终端用户
- **SSH 维护**：`ssh ubuntu@100.64.x.x` 直接进入任意设备排查问题（穿透 NAT，无需端口转发）
- **配合 backup.sh**：
  ```bash
  # 从丽姐的 RPi 拉取备份到本地
  cli/backup.sh pull --from ubuntu@100.64.x.x --team lijie
  ```

### 设备注册流程（cloud-init 集成）

在 `deploy/rpi/user-data` 的 `runcmd` 段中：

```yaml
runcmd:
  # 使用 RPi 硬件序列号作为 hostname，确保重刷系统后名称不变
  - RPI_SERIAL=$(cat /proc/cpuinfo | grep Serial | awk '{print $3}' | tail -c 9)
  - hostnamectl set-hostname muliao-${RPI_SERIAL}
  # 加入 tailnet（Auth Key 在出厂前替换为实际 Key）
  - tailscale up --authkey=tskey-reusable-REPLACE_ME --hostname=muliao-${RPI_SERIAL}
```

### 为什么用 RPi 硬件序列号而非 machine-id

| 标识符 | 来源 | 重刷系统后 |
|--------|------|-----------|
| `/etc/machine-id` | OS 首次启动生成 | **重新生成**（每次不同） |
| `/proc/cpuinfo Serial` | RPi CPU 硅片编号 | **不变**（物理固定） |

使用硬件序列号作为 Tailscale hostname，重刷系统后：
- Tailscale 会生成新的 Node Key（新的机器条目）
- 但 hostname 保持一致（如 `muliao-abc12345`），Admin Console 里容易识别
- 手动删除旧的离线条目，新条目接管即可

### Auth Key 与设备唯一性

常见误解：复用同一个 Auth Key 烧录多台设备会不会产生重复 Machine？

**不会**。区分设备的是 **Node Key**（每台设备独立生成的密钥对），不是 Auth Key。Auth Key 只是"进门的钥匙"，每台设备拿着同一把钥匙进门，但进门后都绑定自己的身份证（Node Key）。

---

## 五、设备重刷场景分析

当用户设备（如丽姐的 RPi）需要重刷系统时：

### Tailscale 层面

1. 重刷后 Tailscale 重新安装，生成**新的 Node Key**
2. Admin Console 出现新的机器条目（新的 Tailscale IP）
3. 旧条目显示"离线"，需要手动从 Console 删除
4. 若使用了硬件序列号命名：新旧条目 hostname 相同，识别容易

### 数据层面（重要）

重刷系统会**清空 NVMe SSD**，`teams/` 目录全部丢失：

| 丢失内容 | 影响 |
|---------|------|
| API Key | Agent 无法调用 LLM |
| Telegram Bot Token | Telegram 机器人失联 |
| `workspace/memory/` | 助手"失忆"（所有对话记忆清空） |
| `openclaw.json` | 所有配置归零 |

### 恢复流程

```bash
# Step 1: 重刷系统（cloud-init 自动安装所有软件）
./deploy/rpi/flash-ssd.sh

# Step 2: 设备上线后，通过 Tailscale SSH 进入
ssh ubuntu@<new-tailscale-ip>

# Step 3: 从备份恢复数据
# 方式 A：从本地拉取（本地有备份的情况）
cli/backup.sh restore teams/.backups/lijie-2026-03-20-153045.zip --team lijie

# 方式 B：先从本地推送，再 SSH 进设备恢复
scp teams/.backups/lijie-xxxx.zip ubuntu@<ip>:/tmp/
ssh muliao@<ip> "cd /home/muliao && cli/backup.sh restore /tmp/lijie-xxxx.zip --team lijie"

# Step 4: 重启服务
ssh ubuntu@<ip> "systemctl restart muliao"
```

---

## 六、备份策略建议

### Phase A：团队持有备份

- **基线备份**：出厂配置完成后立即备份（API Key、Token 均已写入）
- **定期备份**：可通过 cron 在 RPi 本地执行 `cli/backup.sh backup --team <name>`，再通过 `--remote` 推送到开发机
- **救援工具**：`cli/backup.sh pull --from ubuntu@<tailscale-ip> --team <name>` 从远端拉取

```bash
# 推荐的出厂后基线备份命令（在开发机上执行）
cli/backup.sh pull --from ubuntu@100.64.x.x --team lijie
# 备份存入：teams/.backups/lijie-<timestamp>.zip
```

### Phase B：muliao.io 自动备份（待实现）

- 在 muliao.io PWA 仪表盘提供"一键备份"/"备份历史"功能
- `teams/` 加密后上传到云端（用户自己的存储，如 S3/Cloudflare R2）
- 设备更换/重刷时，从 PWA 一键恢复

---

## 七、Tailscale 免费层限额

| 指标 | Personal 免费层 |
|------|-----------------|
| 用户数 | 3 |
| 设备数 | 最多 100 台 |
| 子网路由 | ✅ |
| MagicDNS | ✅ |
| ACL | ✅（基础） |
| 日志保留 | 1 天 |

Phase A（< 10 台设备，团队内部使用）完全在免费层内，无需付费。

---

## 八、相关命令速查

```bash
# 设备端（RPi 上）
tailscale up --authkey=<key> --hostname=muliao-<serial>  # 首次注册
tailscale status                                           # 查看连接状态
tailscale ip                                               # 查看本机 Tailscale IP

# 运维端（开发机上）
ssh ubuntu@<tailscale-ip>                                  # SSH 进 RPi
cli/backup.sh pull --from ubuntu@<tailscale-ip> --team lijie  # 拉取备份
```

---

## 九、WSL2 安装 Tailscale 并连接 RPi

WSL2 下 `.local` mDNS 解析不可靠，推荐通过 Tailscale 连接 RPi。

### 安装

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### 启动与登录

**方式 A：WSL2 支持 systemd（Windows 11 + 较新 WSL 版本）**

```bash
sudo systemctl enable --now tailscaled
sudo tailscale up
```

**方式 B：WSL2 无 systemd**

```bash
sudo tailscaled --tun=userspace-networking &
sudo tailscale up
```

`tailscale up` 会输出一个 `https://login.tailscale.com/a/...` 链接，复制到 Windows 浏览器中打开，用和 RPi 烧录时**同一个 Tailscale 账号**登录。

### 确认连接

```bash
tailscale status
```

应该能看到 WSL2 和 RPi 都在列表中：

```
100.x.x.x   wsl2-xxx         你的开发机
100.x.x.y   muliao-a820      RPi
```

### SSH 到 RPi

```bash
# 通过 Tailscale 主机名（推荐）
ssh muliao@muliao-a820

# 或通过 Tailscale IP
ssh muliao@100.x.x.y
```

### 常见问题

| 问题 | 解决 |
|------|------|
| `tailscaled not running` | 先运行 `sudo tailscaled --tun=userspace-networking &` |
| 浏览器链接无法打开 | 手动复制链接到 Windows 浏览器 |
| `tailscale status` 看不到 RPi | 确认 RPi 和 WSL2 登录的是**同一个 Tailscale 账号** |
| WSL2 网络不通 | 尝试加 `--tun=userspace-networking` 参数启动 tailscaled |
| `ssh muliao@xxx.local` 失败 (exit 255) | WSL2 的 mDNS 支持有限，改用 Tailscale 主机名连接 |

---

## 十、RPi 连接 WiFi（nmcli）

RPi 初次部署通常用有线网。若需切换到 WiFi（如没有网线的场景），用 `nmcli` 操作。

> `network-manager` 已加入 `user-data` 包列表，新烧录的 RPi 开箱即用。
> 旧设备手动安装：`sudo apt install network-manager`

### 扫描可用 WiFi

```bash
nmcli device wifi list
```

### 连接 WiFi

```bash
sudo nmcli device wifi connect "WiFi名称" password "WiFi密码"
```

### 确认连接

```bash
nmcli connection show --active
ip addr show wlan0
```

### 常用命令速查

```bash
# 查看所有接口状态
nmcli device status

# 断开 WiFi
sudo nmcli device disconnect wlan0

# 查看已保存的连接
nmcli connection show

# 删除已保存的连接（重新配置）
sudo nmcli connection delete "WiFi名称"
```

### 切换有线 → WiFi 注意事项

连上 WiFi 后可以拔掉网线，Tailscale 会自动切换到 WiFi 接口，**SSH 不会断**。
如果 RPi 同时接有线和 WiFi，两个接口都会保持，无需额外配置。
