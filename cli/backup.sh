#!/bin/bash
# ==============================================================================
# backup.sh — Team 数据备份与还原工具（本地 + RPi 远程）
# ==============================================================================
#
# Usage:
#   backup.sh <command> [options]
#   backup.sh --help
#
# Commands:
#   backup              备份指定 team 的数据目录为 zip 文件
#   restore <file>      从 zip 文件还原 team 数据
#   list                列出已有备份
#   pull                从 RPi 拉取备份到本地 teams/.backups/
#   push <file>         将本地备份推送到 RPi 并还原
#
# Options:
#   --team NAME         团队名称，对应 teams/<NAME>/（默认：muliao）
#   --host HOST         RPi 主机名或 IP（pull/push 必需，Tailscale hostname 或 LAN IP）
#   --user USER         SSH 用户名（默认：muliao）
#   --force             还原/push 时跳过覆盖确认
#   --restart           push 完成后重启 muliao.service
#   -h, --help          显示帮助
#
# Description:
#   将 teams/<name>/ 完整打包为 zip（含 config、workspace、sessions 等），
#   备份文件存放在 teams/.backups/ 目录下。
#   文件名格式：<team>-<YYYY-MM-DD-HHMMSS>.zip
#
#   pull/push 命令通过 SSH（Tailscale）与 RPi 交互，实现远程备份与还原。
#   RPi 上的数据目录固定为 /home/muliao/.openclaw/（与 deploy-team.sh 一致）。
#
# Examples:
#   backup.sh backup                              # 备份 muliao team
#   backup.sh backup --team hermes                # 备份 hermes team
#   backup.sh list                                # 列出所有备份
#   backup.sh list --team hermes                  # 仅列出 hermes 的备份
#   backup.sh restore teams/.backups/muliao-2026-03-20-153045.zip
#   backup.sh restore muliao-2026-03-20-153045.zip --team muliao --force
#
#   # RPi 远程备份
#   backup.sh pull --host muliao-a1b2             # 从 RPi 拉取备份
#   backup.sh pull --host 100.64.1.5 --team hermes
#   backup.sh push muliao@muliao-a1b2-2026-03-20-153045.zip          # 自动推断 team+host
#   backup.sh push muliao@muliao-a1b2-2026-03-20-153045.zip --restart
#   backup.sh push some-backup.zip --host muliao-a1b2 --team muliao   # 手动指定
# ==============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Help
# --------------------------------------------------------------------------- #
show_help() {
    sed -n '/^# Usage:/,/^# ====/{/^# ====/d; p}' "$0" | sed 's/^# \{0,1\}//'
}

# --------------------------------------------------------------------------- #
# Utilities
# --------------------------------------------------------------------------- #
die()  { echo "❌ $*" >&2; exit 1; }
info() { echo "ℹ️  $*"; }
ok()   { echo "✅ $*"; }

# --------------------------------------------------------------------------- #
# Resolve repo root (works regardless of where the script is called from)
# --------------------------------------------------------------------------- #
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
BACKUP_DIR="${REPO_ROOT}/teams/.backups"
# RPi remote paths (must match deploy-team.sh / muliao.service)
REMOTE_DATA="/home/muliao/.openclaw"
# --------------------------------------------------------------------------- #
# Dependency check
# --------------------------------------------------------------------------- #
check_deps() {
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' 未安装，请先安装：sudo apt install $cmd"
    done
}

# --------------------------------------------------------------------------- #
# SSH connectivity check (shared by pull / push)
# --------------------------------------------------------------------------- #
check_ssh() {
    local target="$1"
    info "检查 SSH 连接: ${target}..."
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$target" "echo ok" &>/dev/null; then
        die "无法通过 SSH 连接到 ${target}。请检查：\n  - RPi 是否已启动并完成 cloud-init\n  - Tailscale 是否已连接（tailscale status）\n  - SSH 公钥是否已配置"
    fi
    ok "SSH 连接正常"
}

# --------------------------------------------------------------------------- #
# Ensure remote host has zip/unzip installed
# --------------------------------------------------------------------------- #
ensure_remote_zip() {
    local target="$1"
    if ! ssh "$target" "command -v zip >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1"; then
        info "远程主机缺少 zip/unzip，正在安装..."
        ssh "$target" "sudo apt-get update -qq && sudo apt-get install -y -qq zip unzip" \
            || die "无法在远程主机上安装 zip/unzip"
        ok "zip/unzip 已安装"
    fi
}

# --------------------------------------------------------------------------- #
# Parse arguments
# --------------------------------------------------------------------------- #
COMMAND=""
TEAM="muliao"
TEAM_SET=0
FORCE=0
RESTORE_FILE=""
RPI_HOST=""
SSH_USER="muliao"
DO_RESTART=0
PUSH_FILE=""

parse_args() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    # First positional arg is the command
    case "$1" in
        backup|restore|list|pull|push)
            COMMAND="$1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            die "未知命令: $1（可用命令: backup, restore, list, pull, push）"
            ;;
    esac

    # For restore, next positional arg is the file path
    if [[ "$COMMAND" == "restore" ]]; then
        if [[ $# -eq 0 || "$1" == --* ]]; then
            die "restore 命令需要指定备份文件路径，例如: backup.sh restore <file.zip>"
        fi
        RESTORE_FILE="$1"
        shift
    fi

    # For push, next positional arg is the file path
    if [[ "$COMMAND" == "push" ]]; then
        if [[ $# -eq 0 || "$1" == --* ]]; then
            die "push 命令需要指定备份文件路径，例如: backup.sh push <file.zip> --host <rpi>"
        fi
        PUSH_FILE="$1"
        shift
    fi

    # Parse remaining options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --team)
                [[ $# -ge 2 ]] || die "--team 需要参数"
                TEAM="$2"
                TEAM_SET=1
                shift 2
                ;;
            --host)
                [[ $# -ge 2 ]] || die "--host 需要参数"
                RPI_HOST="$2"
                shift 2
                ;;
            --user)
                [[ $# -ge 2 ]] || die "--user 需要参数"
                SSH_USER="$2"
                shift 2
                ;;
            --force)
                FORCE=1
                shift
                ;;
            --restart)
                DO_RESTART=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                die "未知选项: $1"
                ;;
        esac
    done
}

# --------------------------------------------------------------------------- #
# cmd: backup
# --------------------------------------------------------------------------- #
do_backup() {
    check_deps zip

    local team_dir="${REPO_ROOT}/teams/${TEAM}"
    [[ -d "$team_dir" ]] || die "team 目录不存在: $team_dir"

    mkdir -p "$BACKUP_DIR"

    local timestamp
    timestamp="$(date '+%Y-%m-%d-%H%M%S')"
    local filename="${TEAM}-${timestamp}.zip"
    local dest="${BACKUP_DIR}/${filename}"

    info "正在备份 teams/${TEAM}/ ..."

    # cd into team dir so zip stores relative paths
    (cd "$team_dir" && zip -r -q "$dest" .)

    local size
    size="$(du -h "$dest" | cut -f1)"
    ok "备份完成: teams/.backups/${filename}（${size}）"
}

# --------------------------------------------------------------------------- #
# cmd: restore
# --------------------------------------------------------------------------- #
do_restore() {
    check_deps unzip

    # Resolve the zip file path
    local zip_path="$RESTORE_FILE"

    # If not absolute and not found, try under BACKUP_DIR
    if [[ ! -f "$zip_path" ]]; then
        if [[ -f "${BACKUP_DIR}/${zip_path}" ]]; then
            zip_path="${BACKUP_DIR}/${zip_path}"
        else
            die "备份文件不存在: $RESTORE_FILE"
        fi
    fi

    local team_dir="${REPO_ROOT}/teams/${TEAM}"

    [[ -d "$team_dir" ]] || mkdir -p "$team_dir"

    # Confirm overwrite if team dir is not empty and --force not set
    if [[ "$(ls -A "$team_dir" 2>/dev/null)" && "$FORCE" -eq 0 ]]; then
        echo "⚠️  team 目录已存在: teams/${TEAM}/"
        read -r -p "   确认覆盖？所有现有内容将被清除 [y/N] " answer
        case "$answer" in
            [yY]|[yY][eE][sS]) ;;
            *) echo "已取消。"; exit 0 ;;
        esac
    fi

    info "正在还原到 teams/${TEAM}/ ..."

    # Clean and recreate
    rm -rf "$team_dir"
    mkdir -p "$team_dir"

    unzip -q -o "$zip_path" -d "$team_dir"

    ok "还原完成: teams/${TEAM}/（来源: $(basename "$zip_path")）"
}

# --------------------------------------------------------------------------- #
# cmd: list
# --------------------------------------------------------------------------- #
do_list() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        info "暂无备份（目录 teams/.backups/ 不存在）"
        return
    fi

    local pattern="${TEAM}-*.zip"
    # If --team not explicitly provided, show all
    if [[ "$TEAM_SET" -eq 0 ]]; then
        pattern="*.zip"
    fi

    local files
    files=$(find "$BACKUP_DIR" -maxdepth 1 -name "$pattern" -printf '%f\n' 2>/dev/null | sort -r)

    if [[ -z "$files" ]]; then
        info "暂无匹配的备份文件"
        return
    fi

    echo "📦 备份列表（teams/.backups/）:"
    echo "---"
    while IFS= read -r f; do
        local size
        size="$(du -h "${BACKUP_DIR}/${f}" | cut -f1)"
        echo "  ${f}  (${size})"
    done <<< "$files"
}

# --------------------------------------------------------------------------- #
# cmd: pull — 从 RPi 拉取备份到本地
# --------------------------------------------------------------------------- #
do_pull() {
    [[ -n "$RPI_HOST" ]] || die "pull 命令需要 --host 参数，例如: backup.sh pull --host muliao-a1b2"

    local ssh_target="${SSH_USER}@${RPI_HOST}"
    check_ssh "$ssh_target"
    ensure_remote_zip "$ssh_target"

    # Check remote data directory exists
    if ! ssh "$ssh_target" "[[ -d ${REMOTE_DATA} ]]"; then
        die "RPi 上数据目录不存在: ${REMOTE_DATA}"
    fi

    local timestamp
    timestamp="$(date '+%Y-%m-%d-%H%M%S')"
    local filename="${TEAM}@${RPI_HOST}-${timestamp}.zip"
    local remote_tmp="/tmp/muliao-backup-${filename}"

    info "正在远程打包 ${RPI_HOST}:${REMOTE_DATA}/ ..."
    ssh "$ssh_target" "cd ${REMOTE_DATA} && zip -r -q '${remote_tmp}' ." \
        || die "远程打包失败"

    mkdir -p "$BACKUP_DIR"
    local dest="${BACKUP_DIR}/${filename}"

    info "正在从 RPi 下载备份..."
    scp -q "${ssh_target}:${remote_tmp}" "$dest" \
        || die "下载备份文件失败"

    # Clean up remote temp file
    ssh "$ssh_target" "rm -f '${remote_tmp}'" 2>/dev/null || true

    local size
    size="$(du -h "$dest" | cut -f1)"
    ok "拉取完成: teams/.backups/${filename}（${size}）来源: ${RPI_HOST}"
}

# --------------------------------------------------------------------------- #
# Infer --team and --host from filename (team@host-YYYY-MM-DD-HHMMSS.zip)
# Only sets values not already provided via CLI flags.
# --------------------------------------------------------------------------- #
infer_from_filename() {
    local name
    name="$(basename "$1" .zip)"

    # Expect: {team}@{host}-YYYY-MM-DD-HHMMSS
    if [[ "$name" =~ ^([^@]+)@(.+)-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}$ ]]; then
        local inferred_team="${BASH_REMATCH[1]}"
        local inferred_host="${BASH_REMATCH[2]}"

        if [[ "$TEAM_SET" -eq 0 && -n "$inferred_team" ]]; then
            TEAM="$inferred_team"
            info "从文件名推断 team: ${TEAM}"
        fi
        if [[ -z "$RPI_HOST" && -n "$inferred_host" ]]; then
            RPI_HOST="$inferred_host"
            info "从文件名推断 host: ${RPI_HOST}"
        fi
    fi
}

# --------------------------------------------------------------------------- #
# cmd: push — 将本地备份推送到 RPi 并还原
# --------------------------------------------------------------------------- #
do_push() {
    # Try to infer --team and --host from filename before validation
    infer_from_filename "$PUSH_FILE"

    [[ -n "$RPI_HOST" ]] || die "push 命令需要 --host 参数（或使用 pull 生成的含 team@host 的文件名）"

    # Resolve the zip file path
    local zip_path="$PUSH_FILE"
    if [[ ! -f "$zip_path" ]]; then
        if [[ -f "${BACKUP_DIR}/${zip_path}" ]]; then
            zip_path="${BACKUP_DIR}/${zip_path}"
        else
            die "备份文件不存在: $PUSH_FILE"
        fi
    fi

    local ssh_target="${SSH_USER}@${RPI_HOST}"
    check_ssh "$ssh_target"
    ensure_remote_zip "$ssh_target"

    # Confirm overwrite unless --force
    if [[ "$FORCE" -eq 0 ]]; then
        echo "⚠️  即将还原到 RPi ${RPI_HOST}:${REMOTE_DATA}/"
        echo "   来源: $(basename "$zip_path")"
        [[ "$DO_RESTART" -eq 1 ]] && echo "   还原后将重启 muliao.service"
        read -r -p "   确认执行？远程数据将被覆盖 [y/N] " answer
        case "$answer" in
            [yY]|[yY][eE][sS]) ;;
            *) echo "已取消。"; exit 0 ;;
        esac
    fi

    local remote_tmp
    remote_tmp="/tmp/muliao-push-$(basename "$zip_path")"

    # Stop service before restore if --restart
    if [[ "$DO_RESTART" -eq 1 ]]; then
        info "停止 muliao.service..."
        ssh "$ssh_target" "sudo systemctl stop muliao.service" 2>/dev/null || true
    fi

    info "正在上传备份到 RPi..."
    scp -q "$zip_path" "${ssh_target}:${remote_tmp}" \
        || die "上传备份文件失败"

    info "正在远程还原 ${REMOTE_DATA}/ ..."
    ssh "$ssh_target" "
        sudo rm -rf '${REMOTE_DATA}'
        sudo mkdir -p '${REMOTE_DATA}'
        sudo unzip -q -o '${remote_tmp}' -d '${REMOTE_DATA}'
        sudo chown -R ${SSH_USER}:${SSH_USER} '${REMOTE_DATA}'
        rm -f '${remote_tmp}'
    " || die "远程还原失败"

    ok "推送还原完成: $(basename "$zip_path") → ${RPI_HOST}:${REMOTE_DATA}/"

    # Restart service if requested
    if [[ "$DO_RESTART" -eq 1 ]]; then
        info "启动 muliao.service..."
        ssh "$ssh_target" "sudo systemctl start muliao.service"
        ok "服务已重启"
    fi
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
parse_args "$@"

case "$COMMAND" in
    backup)  do_backup  ;;
    restore) do_restore ;;
    list)    do_list    ;;
    pull)    do_pull    ;;
    push)    do_push    ;;
esac
