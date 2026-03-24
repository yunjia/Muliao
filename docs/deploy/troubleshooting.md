# 部署常见问题与排查记录

记录 RPi / OpenClaw 部署过程中踩过的真实的坑，供复现时快速定位。

---

## 1. Gateway 启动崩溃：`RangeError: Invalid time zone specified: Etc/Unknown`

**现象**

```
RangeError: Invalid time zone specified: Etc/Unknown
    at new Intl.DateTimeFormat (<anonymous>)
    ...
```

OpenClaw gateway 反复崩溃重启。

**根本原因**

Ubuntu 24.04 cloud-init 完成后，系统时区默认为 `Etc/Unknown`（无效值）。
`.env` 中没有 `TZ` 时，Node.js 读宿主机的 `/etc/localtime` symlink，
发现目标是 `Etc/Unknown` → 抛出 RangeError 崩溃。

**修复方法**

第一步：修复宿主机系统时区（一次性）：

```bash
sudo timedatectl set-timezone Asia/Shanghai   # 按实际时区填写
```

第二步：在 `/home/muliao/.env` 中显式设置 `TZ`（**这才是关键**）：

```bash
echo "TZ=Asia/Shanghai" >> /home/muliao/.openclaw/.env
systemctl --user restart openclaw-gateway.service
```

第三步：确认 gateway 正常启动：

```bash
openclaw gateway status
```

**为什什修复宿主机时区还不够？**

`timedatectl` 改了系统时区，但 OpenClaw gateway 通过 EnvironmentFile 读取 `~/.openclaw/.env`。
`.env` 中没有 `TZ`，gateway 仍然拿到空字符串，问题不解。
必须在 `.env` 里显式声明 `TZ` 才能生效。

**预防措施**

`teams/<team>/.env` 已加入 `TZ=Asia/Shanghai` 字段。
下次用 `deploy-team.sh` 同步数据时会自动部署到 RPi，无需手动操作。

---

## 2. `.env` 文件读取报 `Permission denied`

**现象**

OpenClaw gateway 启动时报无法读取 `/home/muliao/.openclaw/.env`。

**根本原因**

`deploy-team.sh` 用 `rsync` 把 `.env` 推到 RPi 时，文件所有者变成了当前 SSH 用户（root 或其他），
`openclaw-gateway.service`（用户服务）以 `muliao` 用户身份读取时权限不足。

**修复方法**

```bash
sudo chown muliao:muliao /home/muliao/.openclaw/.env
sudo chmod 600 /home/muliao/.openclaw/.env
```

**预防措施**

已在 `deploy-team.sh` 的 rsync `.env` 步骤之后加入自动 `chown + chmod`，
后续部署不会再出现此问题。

---

## 3. OpenClaw gateway 无法启动

**现象**

`systemctl --user status openclaw-gateway.service` 显示 failed。

**常见原因**

1. `.deploy-pending` 标记文件还存在（deploy-team.sh 未运行）
2. `.env` 中缺少必要的 API key
3. OpenClaw 未正确安装（`openclaw --version` 检查）

**修复方法**

```bash
# 诊断服务状态
openclaw doctor

# 查看日志
journalctl --user -u openclaw-gateway.service -n 50 --no-pager

# 重新安装服务
openclaw gateway install --force
systemctl --user restart openclaw-gateway.service
```
