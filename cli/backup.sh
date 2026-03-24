#!/bin/bash
# ==============================================================================
# backup.sh — Team 数据备份与还原工具
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
#
# Options:
#   --team NAME         团队名称，对应 teams/<NAME>/（默认：muliao）
#   --force             还原时跳过覆盖确认
#   -h, --help          显示帮助
#
# Description:
#   将 teams/<name>/ 完整打包为 zip（含 config、workspace、sessions 等），
#   备份文件存放在 teams/.backups/ 目录下。
#   文件名格式：<team>-<YYYY-MM-DD-HHMMSS>.zip
#
# Examples:
#   backup.sh backup                              # 备份 muliao team
#   backup.sh backup --team hermes                # 备份 hermes team
#   backup.sh list                                # 列出所有备份
#   backup.sh list --team hermes                  # 仅列出 hermes 的备份
#   backup.sh restore teams/.backups/muliao-2026-03-20-153045.zip
#   backup.sh restore muliao-2026-03-20-153045.zip --team muliao --force
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

# --------------------------------------------------------------------------- #
# Dependency check
# --------------------------------------------------------------------------- #
check_deps() {
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' 未安装，请先安装：sudo apt install $cmd"
    done
}

# --------------------------------------------------------------------------- #
# Parse arguments
# --------------------------------------------------------------------------- #
COMMAND=""
TEAM="muliao"
TEAM_SET=0
FORCE=0
RESTORE_FILE=""

parse_args() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    # First positional arg is the command
    case "$1" in
        backup|restore|list)
            COMMAND="$1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            die "未知命令: $1（可用命令: backup, restore, list）"
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

    # Parse remaining options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --team)
                [[ $# -ge 2 ]] || die "--team 需要参数"
                TEAM="$2"
                TEAM_SET=1
                shift 2
                ;;
            --force)
                FORCE=1
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
# Main
# --------------------------------------------------------------------------- #
parse_args "$@"

case "$COMMAND" in
    backup)  do_backup  ;;
    restore) do_restore ;;
    list)    do_list ;;
esac
