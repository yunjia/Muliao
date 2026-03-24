# 部署常见问题与排查记录

记录 RPi / Docker 部署过程中踩过的真实的坑，供复现时快速定位。

---

## 1. 容器启动崩溃：`RangeError: Invalid time zone specified: Etc/Unknown`

**现象**

```
RangeError: Invalid time zone specified: Etc/Unknown
    at new Intl.DateTimeFormat (<anonymous>)
    ...
```

容器反复重启，`docker ps` 看到 `Restarting`。

**根本原因**

Ubuntu 24.04 cloud-init 完成后，系统时区默认为 `Etc/Unknown`（无效值）。
`docker-compose.yml` 里配置了 `TZ: ${TZ:-}`，当 `.env` 中没有 `TZ` 时，
容器拿到的是空字符串，Node.js 再去读宿主机的 `/etc/localtime` symlink，
发现目标是 `Etc/Unknown` → 抛出 RangeError 崩溃。

**`docker-compose.yml` 相关配置：**

```yaml
environment:
  TZ: ${TZ:-}
```

**修复方法**

第一步：修复宿主机系统时区（一次性）：

```bash
sudo timedatectl set-timezone Asia/Shanghai   # 按实际时区填写
```

第二步：在 `/home/muliao/.env` 中显式设置 `TZ`（**这才是关键**）：

```bash
echo "TZ=Asia/Shanghai" >> /home/muliao/.env
sudo systemctl restart muliao.service
```

第三步：确认容器正常启动：

```bash
docker logs muliao --tail 30
```

**为什么修复宿主机时区还不够？**

`timedatectl` 改了系统时区，但容器通过 `compose` 拿 env var，读的是 `.env` 文件。
`.env` 中没有 `TZ`，容器仍然拿到空字符串，问题不解。
必须在 `.env` 里显式声明 `TZ` 才能生效。

**预防措施**

`teams/<team>/.env` 已加入 `TZ=Asia/Shanghai` 字段。
下次用 `deploy-team.sh` 同步数据时会自动部署到 RPi，无需手动操作。

---

## 2. `.env` 文件读取报 `Permission denied`

**现象**

容器启动时报 Docker 无法读取 `/home/muliao/.env`，或 `docker compose up` 报错。

**根本原因**

`deploy-team.sh` 用 `rsync` 把 `.env` 推到 RPi 时，文件所有者变成了当前 SSH 用户（root 或其他），
`docker compose` 以 `muliao` 用户身份读取时权限不足。

**修复方法**

```bash
sudo chown muliao:muliao /home/muliao/.env
sudo chmod 600 /home/muliao/.env
```

**预防措施**

已在 `deploy-team.sh` 的 rsync `.env` 步骤之后加入自动 `chown + chmod`，
后续部署不会再出现此问题。

---

## 3. `docker pull ghcr.io/muliaoio/muliao:latest` 报 `unauthorized`

**现象**

```
Error response from daemon: pull access denied for ghcr.io/muliaoio/muliao, repository does not exist or may require 'docker login'
```

**根本原因**

镜像仓库为私有 GHCR（GitHub Container Registry），需要先登录。

**修复方法（临时）**

在 RPi 上手动登录，使用有 `read:packages` 权限的 GitHub PAT：

```bash
echo "ghp_your_token_here" | docker login ghcr.io -u x-access-token --password-stdin
```

**长期方案**

1. 在 `teams/<team>/.env` 里填写 `GHCR_TOKEN=ghp_...`
2. `flash-ssd.sh --ghcr-token` 会自动注入到 cloud-init，新烧录的 RPi 开箱自动登录
3. 已有 RPi 重新跑 `deploy-team.sh` 后，下次 systemd 启动会带 token 初始化（待完善）
