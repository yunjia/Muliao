#!/bin/bash
# ==============================================================================
# deploy-team.sh — 将团队数据部署到 RPi
# ==============================================================================
#
# Usage:
#   deploy-team.sh <host> [options]
#   deploy-team.sh --help
#
# Description:
#   将开发机上的团队数据（teams/<name>/ 目录）通过 rsync + SSH 部署到 RPi。
#   同时同步 docker-compose.yml 和 .env 文件。
#
#   这是 Phase A 团队辅助部署的核心脚本：
#   1. flash-ssd.sh 烧录镜像 + cloud-init 安装基础环境
#   2. RPi 启动后 Docker + Tailscale 就绪
#   3. ← 本脚本将 OpenClaw 配置 + workspace 推送到 RPi
#   4. 启动 muliao.service → Hermes 上线
#
# What gets deployed:
#   teams/<name>/          →  RPi:/home/muliao/.openclaw/ （OpenClaw 运行时数据）
#   docker-compose.yml     →  RPi:/home/muliao/         （容器编排配置）
#   .env                   →  RPi:/home/muliao/.env     （环境变量：API keys 等）
#
# Options:
#   <host>            RPi 主机名或 IP（Tailscale hostname 或 LAN IP）
#   --team NAME       团队名称，对应 teams/<NAME>/（默认：muliao）
#   --user USER       SSH 用户名（默认：muliao）
#   --env FILE        .env 文件路径（默认：teams/<name>/.env > 项目根 .env）
#   --dry-run         仅显示将同步的内容，不实际执行
#   --start           部署后启动 muliao.service
#   --restart         部署后重启 muliao.service
#   -h, --help        显示帮助
#
# Prerequisites:
#   - RPi 已通过 flash-ssd.sh 烧录并完成 cloud-init 初始化
#   - 能通过 SSH 连接到 RPi（Tailscale 或局域网）
#   - rsync 已安装
#
# Examples:
#   deploy-team.sh muliao-a1b2 --start             # 部署 muliao 团队并启动服务
#   deploy-team.sh hermes-f3c9 --team hermes --restart  # 部署 hermes 团队并重启
#   deploy-team.sh muliao-a1b2 --dry-run           # 预览将同步的内容
#   deploy-team.sh muliao-a1b2 --env /path/to/.env # 使用指定 .env（覆盖自动查找）
# ==============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Utilities
# --------------------------------------------------------------------------- #
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.."; pwd)"

die()  { echo "❌ $*" >&2; exit 1; }
info() { echo "ℹ️  $*"; }
ok()   { echo "✅ $*"; }

show_help() {
    sed -n '/^# Usage:/,/^# ====/{/^# ====/d; p}' "$0" | sed 's/^# \{0,1\}//'
}

# --------------------------------------------------------------------------- #
# Defaults
# --------------------------------------------------------------------------- #
rpi_host=""
team_name="muliao"
ssh_user="muliao"
env_file=""          # 留空，后面根据 --team 自动查找
cli_env_file=""      # --env 显式指定（最高优先级）
dry_run=0
do_start=0
do_restart=0

# Remote paths
REMOTE_BASE="/home/muliao"
REMOTE_DATA="${REMOTE_BASE}/.openclaw"

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
    -h|--help)
        show_help; exit 0 ;;
    --team)
        team_name="$2"; shift 2 ;;
    --user)
        ssh_user="$2"; shift 2 ;;
    --env)
        cli_env_file="$2"; shift 2 ;;
    --dry-run)
        dry_run=1; shift ;;
    --start)
        do_start=1; shift ;;
    --restart)
        do_restart=1; shift ;;
    -*)
        die "未知选项: $1" ;;
    *)
        if [[ -z "$rpi_host" ]]; then
            rpi_host="$1"; shift
        else
            die "多余参数: $1"
        fi ;;
    esac
done

[[ -n "$rpi_host" ]] || die "请指定 RPi 主机名或 IP 地址"

# --------------------------------------------------------------------------- #
# 解析 .env 文件（优先级：--env > teams/<name>/.env > 根目录 .env）
# --------------------------------------------------------------------------- #
if [[ -n "$cli_env_file" ]]; then
    env_file="$cli_env_file"
    [[ -f "$env_file" ]] || die "指定的 .env 文件不存在: $env_file"
    info ".env 来源: $env_file（命令行指定）"
elif [[ -f "${REPO_ROOT}/teams/${team_name}/.env" ]]; then
    env_file="${REPO_ROOT}/teams/${team_name}/.env"
    info ".env 来源: teams/${team_name}/.env"
elif [[ -f "${REPO_ROOT}/.env" ]]; then
    env_file="${REPO_ROOT}/.env"
    info ".env 来源: .env（根目录）"
fi

# --------------------------------------------------------------------------- #
# Validate
# --------------------------------------------------------------------------- #
command -v rsync >/dev/null 2>&1 || die "rsync 未安装"

local_data="${REPO_ROOT}/teams/${team_name}"
[[ -d "$local_data" ]] || die "团队目录不存在: $local_data"

compose_file="${REPO_ROOT}/docker-compose.yml"
[[ -f "$compose_file" ]] || die "docker-compose.yml 不存在: $compose_file"

if [[ -z "$env_file" ]]; then
    warn "未找到 .env 文件（已检查: teams/${team_name}/.env, .env）"
    warn "RPi 上的 .env 将仅包含基础配置（无 API keys）。"
    warn "部署后请手动编辑 RPi 上的 /home/muliao/.env 添加 API keys。"
fi

ssh_target="${ssh_user}@${rpi_host}"

# --------------------------------------------------------------------------- #
# SSH connectivity check
# --------------------------------------------------------------------------- #
info "检查 SSH 连接: ${ssh_target}..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$ssh_target" "echo ok" &>/dev/null; then
    die "无法通过 SSH 连接到 ${ssh_target}。请检查：
  - RPi 是否已启动并完成 cloud-init
  - Tailscale 是否已连接（tailscale status）
  - SSH 公钥是否已配置"
fi
ok "SSH 连接正常"

# --------------------------------------------------------------------------- #
# Display plan
# --------------------------------------------------------------------------- #
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Muliao RPi — 团队数据部署                              ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  目标:        %-40s ║\n" "$ssh_target"
printf "║  团队:        %-40s ║\n" "$team_name"
printf "║  本地数据:    %-40s ║\n" "$local_data"
printf "║  远程路径:    %-40s ║\n" "$REMOTE_DATA"
printf "║  .env:        %-40s ║\n" "${env_file:-（无）}"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# rsync options
rsync_opts=(-avz --delete --progress)
# 排除不需要同步的临时文件
rsync_opts+=(--exclude='*.reset.*' --exclude='*.deleted.*' --exclude='sessions/*.jsonl.reset.*')
# 保留文件权限
rsync_opts+=(--chmod=D755,F644)

if [[ "$dry_run" -eq 1 ]]; then
    rsync_opts+=(--dry-run)
    info "DRY RUN 模式 — 仅显示将同步的内容"
fi

# --------------------------------------------------------------------------- #
# Step 1: Ensure remote directory exists
# --------------------------------------------------------------------------- #
if [[ "$dry_run" -eq 0 ]]; then
    info "确保远程目录存在..."
    ssh "$ssh_target" "sudo mkdir -p ${REMOTE_DATA} ${REMOTE_BASE} && sudo chown -R ${ssh_user}:${ssh_user} ${REMOTE_BASE}"
fi

# --------------------------------------------------------------------------- #
# Step 2: Sync team data
# --------------------------------------------------------------------------- #
info "同步团队数据: teams/${team_name}/ → ${REMOTE_DATA}/"
rsync "${rsync_opts[@]}" \
    -e ssh \
    "${local_data}/" \
    "${ssh_target}:${REMOTE_DATA}/"
ok "团队数据同步完成"

# --------------------------------------------------------------------------- #
# Step 3: Sync docker-compose.yml
# --------------------------------------------------------------------------- #
info "同步 docker-compose.yml..."
rsync "${rsync_opts[@]}" \
    -e ssh \
    "$compose_file" \
    "${ssh_target}:${REMOTE_BASE}/docker-compose.yml"
ok "docker-compose.yml 同步完成"

# --------------------------------------------------------------------------- #
# Step 4: Deploy .env
# --------------------------------------------------------------------------- #
if [[ -n "$env_file" ]]; then
    info "同步 .env..."

    # 生成 RPi 专用 .env（确保 MULIAO_DATA_DIR 指向正确路径）
    tmpenv=$(mktemp)
    # 从开发机 .env 复制，覆盖 RPi 特有的值
    cp "$env_file" "$tmpenv"

    # 确保 MULIAO_DATA_DIR 指向 RPi 路径
    if grep -q '^MULIAO_DATA_DIR=' "$tmpenv"; then
        sed -i "s|^MULIAO_DATA_DIR=.*|MULIAO_DATA_DIR=${REMOTE_DATA}|" "$tmpenv"
    elif grep -q '^#MULIAO_DATA_DIR=' "$tmpenv"; then
        sed -i "s|^#MULIAO_DATA_DIR=.*|MULIAO_DATA_DIR=${REMOTE_DATA}|" "$tmpenv"
    else
        echo "MULIAO_DATA_DIR=${REMOTE_DATA}" >> "$tmpenv"
    fi

    # 确保容器名称设置
    if ! grep -q '^MULIAO_CONTAINER_NAME=' "$tmpenv"; then
        echo "MULIAO_CONTAINER_NAME=muliao" >> "$tmpenv"
    fi

    rsync "${rsync_opts[@]}" \
        -e ssh \
        --chmod=F600 \
        "$tmpenv" \
        "${ssh_target}:${REMOTE_BASE}/.env"
    rm -f "$tmpenv"

    ok ".env 同步完成"
else
    info "跳过 .env 同步（文件不存在）"
fi

# --------------------------------------------------------------------------- #
# Step 5: Remove deploy-pending marker
# --------------------------------------------------------------------------- #
if [[ "$dry_run" -eq 0 ]]; then
    ssh "$ssh_target" "rm -f ${REMOTE_BASE}/.deploy-pending" 2>/dev/null || true
fi

# --------------------------------------------------------------------------- #
# Step 6: Service management
# --------------------------------------------------------------------------- #
if [[ "$dry_run" -eq 0 ]]; then
    if [[ "$do_restart" -eq 1 ]]; then
        info "重启 muliao.service..."
        ssh "$ssh_target" "sudo systemctl restart muliao.service"
        ok "服务已重启"
    elif [[ "$do_start" -eq 1 ]]; then
        info "启动 muliao.service..."
        ssh "$ssh_target" "sudo systemctl start muliao.service"
        ok "服务已启动"
    else
        echo ""
        info "数据已部署。启动服务："
        echo "  ssh ${ssh_target} 'sudo systemctl start muliao.service'"
        echo ""
        echo "或重新运行本脚本加 --start 参数："
        echo "  $0 ${rpi_host} --team ${team_name} --start"
    fi
fi

# --------------------------------------------------------------------------- #
# Step 7: Verify (non-dry-run)
# --------------------------------------------------------------------------- #
if [[ "$dry_run" -eq 0 && ("$do_start" -eq 1 || "$do_restart" -eq 1) ]]; then
    echo ""
    info "等待服务启动 (10s)..."
    sleep 10

    # 检查服务状态
    if ssh "$ssh_target" "systemctl is-active muliao.service" &>/dev/null; then
        ok "muliao.service 运行中"

        # 检查容器状态
        info "容器状态:"
        ssh "$ssh_target" "docker ps --filter name=muliao --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'" || true
    else
        echo ""
        warn "muliao.service 未在运行。查看日志："
        echo "  ssh ${ssh_target} 'journalctl -u muliao.service -n 50 --no-pager'"
    fi
fi

echo ""
ok "部署完成！"
