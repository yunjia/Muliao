#!/bin/bash
# ==============================================================================
# wsl-mount.sh — WSL2 下挂载 SSD 的 system-boot 分区（Windows 盘符 → drvfs）
# ==============================================================================
#
# Usage:
#   wsl-mount.sh <盘符>             # 挂载，如 wsl-mount.sh E
#   wsl-mount.sh --unmount          # 卸载
#   wsl-mount.sh -h, --help         # 显示帮助
#
# Examples:
#   wsl-mount.sh E                   # 挂载 E: → /mnt/e
#   flash-ssd.sh --boot-dir /mnt/e --team muliao
#   wsl-mount.sh --unmount           # 卸载
# ==============================================================================

set -euo pipefail

MOUNT_LETTER=""
STATE_FILE="/tmp/.muliao-wsl-mount"

die()  { echo "❌ $*" >&2; exit 1; }
ok()   { echo "✅ $*"; }
info() { echo "ℹ️  $*"; }

show_help() {
    sed -n '/^# Usage:/,/^# ====/{/^# ====/d; p}' "$0" | sed 's/^# \{0,1\}//'
}

do_mount() {
    local letter="$1"
    local lower
    lower=$(echo "$letter" | tr '[:upper:]' '[:lower:]')
    local mount_point="/mnt/${lower}"

    if mountpoint -q "$mount_point" 2>/dev/null; then
        ok "已挂载: ${mount_point}"
    else
        sudo mkdir -p "$mount_point"
        sudo mount -t drvfs "${letter}:" "$mount_point"
        ok "已挂载: ${letter}: → ${mount_point}"
    fi

    echo "$letter" > "$STATE_FILE"

    if [[ -f "${mount_point}/cmdline.txt" ]] || [[ -f "${mount_point}/config.txt" ]]; then
        ok "检测到 RPi system-boot 分区"
    fi

    echo ""
    echo "下一步："
    echo "  flash-ssd.sh --boot-dir ${mount_point} --team <name>"
}

do_unmount() {
    if [[ ! -f "$STATE_FILE" ]]; then
        info "没有已挂载的磁盘"
        exit 0
    fi

    local letter
    letter=$(cat "$STATE_FILE")
    local lower
    lower=$(echo "$letter" | tr '[:upper:]' '[:lower:]')
    local mount_point="/mnt/${lower}"

    if mountpoint -q "$mount_point" 2>/dev/null; then
        sudo umount "$mount_point"
        ok "已卸载 ${mount_point}"
    fi

    rm -f "$STATE_FILE"
    echo "现在可以从 Windows 安全弹出 SSD。"
}

# --- Main ---
action="mount"

while [[ $# -gt 0 ]]; do
    case "$1" in
    -h|--help)       show_help; exit 0 ;;
    --unmount|--umount) action="unmount"; shift ;;
    -*)              die "未知选项: $1" ;;
    *)               MOUNT_LETTER="$1"; shift ;;
    esac
done

case "$action" in
    unmount) do_unmount ;;
    mount)
        [[ -n "$MOUNT_LETTER" ]] || die "请指定 Windows 盘符，如: $0 E"
        MOUNT_LETTER=$(echo "$MOUNT_LETTER" | tr '[:lower:]' '[:upper:]' | tr -d ':')
        [[ "$MOUNT_LETTER" =~ ^[A-Z]$ ]] || die "盘符格式错误: $MOUNT_LETTER"
        do_mount "$MOUNT_LETTER"
        ;;
esac
