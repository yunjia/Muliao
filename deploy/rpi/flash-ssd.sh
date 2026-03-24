#!/bin/bash
# ==============================================================================
# flash-ssd.sh — 烧录 Ubuntu Server ARM64 镜像到 NVMe SSD + 注入 cloud-init
# ==============================================================================
#
# Usage:
#   flash-ssd.sh <device> [options]
#   flash-ssd.sh --boot-dir <path> [options]
#   flash-ssd.sh --help
#
# Description:
#   下载 Ubuntu Server 24.04 LTS ARM64 RPi 镜像，烧录到目标设备（NVMe SSD
#   通过 USB 适配器连接），然后注入 cloud-init user-data 配置。
#
#   ⚠️ 使用 <device> 模式时会擦除目标设备全部数据！请仔细确认设备路径。
#
# Modes:
#   <device>              Linux 原生模式：烧录 + 注入 cloud-init
#   --boot-dir <path>     WSL2 / 手动模式：跳过烧录，仅向已挂载的 boot 分区注入
#                         cloud-init 文件。适用于：
#                         1. Windows 上用 Raspberry Pi Imager 烧录
#                         2. system-boot 分区自动挂载为盘符（如 D:）
#                         3. WSL2 中通过 /mnt/d/ 访问
#
# Options:
#   --team NAME           团队名称，对应 teams/<NAME>/（默认：muliao）
#                         从 teams/<NAME>/.env 读取部署配置（推荐，避免反复传参——
#                         支持的 .env 变量见 .env.example 的「RPi 部署」区块）
#   --hostname-prefix PFX  主机名前缀（默认：与 --team 同名）
#                         启动时自动追加 RPi 序列号后 4 位（如 hermes-a1b2）
#                         也可在 .env 中设置: HOSTNAME_PREFIX=hermes
#   --timezone TZ         时区（默认：开发机当前时区）
#                         也可在 .env 中设置: TIMEZONE=Asia/Tokyo
#   --tailscale-key KEY   Tailscale pre-auth key（覆盖 .env 中的值）
#   --resolution RES      HDMI 输出分辨率（默认：800x480，适配小触摸屏）
#                         预设值: 720p / 1080p / 4k  或自定义 WxH（如 2560x1440）
#                         如果你觉得终端字会糊，说明分辨率和屏幕不匹配
#                         也可在 .env 中设置: HDMI_RESOLUTION=1080p
#   --ssh-key PATH        指定 SSH 公钥（默认自动检测 ~/.ssh/id_*.pub）
#   --image PATH          使用本地镜像文件（跳过下载）
#   --skip-flash          跳过烧录，仅注入 cloud-init（设备已烧录过）
#   -h, --help            显示帮助
#
# Prerequisites:
#   Linux:  sudo apt install xz-utils
#   macOS:  brew install xz  (或 Homebrew 自带)
#
# Examples:
#   # Linux 原生：烧录 + 注入
#   flash-ssd.sh /dev/sda
#   flash-ssd.sh /dev/sda --tailscale-key tskey-auth-xxx
#
#   # WSL2：先挂载 SSD boot 分区（Windows 盘符 E:），再注入 cloud-init
#   wsl-mount.sh E
#   flash-ssd.sh --boot-dir /mnt/e --team hermes
#   wsl-mount.sh --unmount
#
#   # 小触摸屏（800x480）字糊？指定分辨率：
#   flash-ssd.sh --boot-dir /mnt/d --resolution 800x480
#   flash-ssd.sh --boot-dir /mnt/d --resolution 1080p
#
#   # Linux：已烧录，仅注入 cloud-init
#   flash-ssd.sh /dev/sda --skip-flash
# ==============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.."; pwd)"

UBUNTU_VERSION="24.04.2"
UBUNTU_IMAGE_NAME="ubuntu-${UBUNTU_VERSION}-preinstalled-server-arm64+raspi.img.xz"
UBUNTU_IMAGE_URL="https://cdimage.ubuntu.com/releases/24.04/release/${UBUNTU_IMAGE_NAME}"
CACHE_DIR="${REPO_ROOT}/deploy/.cache"

# --------------------------------------------------------------------------- #
# Utilities
# --------------------------------------------------------------------------- #
die()  { echo "❌ $*" >&2; exit 1; }
info() { echo "ℹ️  $*"; }
ok()   { echo "✅ $*"; }
warn() { echo "⚠️  $*"; }

show_help() {
    sed -n '/^# Usage:/,/^# ====/{/^# ====/d; p}' "$0" | sed 's/^# \{0,1\}//'
}

# 确认框行格式化（自动处理中文宽度）
_box() {
    local line="  $*"
    local box_width=62
    local display_width
    display_width=$(printf '%s' "$line" | wc -L)
    local pad=$(( box_width - display_width ))
    (( pad < 1 )) && pad=1
    printf "║%s%*s║\n" "$line" "$pad" ""
}

# --------------------------------------------------------------------------- #
# Defaults
# --------------------------------------------------------------------------- #
device=""
team_name="muliao"
hostname_prefix=""          # 最终生效值：由 .env HOSTNAME_PREFIX 或 CLI 填充，留空则跟随 team_name
cli_hostname_prefix=""      # CLI --hostname-prefix 暂存（最高优先级）
timezone="$(cat /etc/timezone 2>/dev/null || echo Asia/Shanghai)"  # 内置默认：读取开发机时区
cli_timezone=""             # CLI --timezone 暂存（最高优先级）
tailscale_key=""
ssh_key_path=""             # 可选：额外注入 SSH 公钥（默认自动检测 ~/.ssh/id_*.pub）
resolution="800x480"        # 内置默认值（适配小触摸屏）；可由 .env HDMI_RESOLUTION 覆盖
cli_resolution=""           # CLI --resolution 暂存（最高优先级）
local_image=""
skip_flash=0
boot_dir=""                 # WSL2 模式：直接指定已挂载的 boot 分区
cli_tailscale_key=""        # CLI --tailscale-key 暂存（最高优先级）
ghcr_token=""               # GitHub Token，用于拉取 ghcr.io 私有镜像
cli_ghcr_token=""           # CLI --ghcr-token 暂存（最高优先级）

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
    --hostname-prefix)
        cli_hostname_prefix="$2"; shift 2 ;;  # 暂存，.env 读取后再合并
    --timezone)
        cli_timezone="$2"; shift 2 ;;          # 暂存，.env 读取后再合并
    --team)
        team_name="$2"; shift 2 ;;
    --tailscale-key)
        cli_tailscale_key="$2"; shift 2 ;;
    --ghcr-token)
        cli_ghcr_token="$2"; shift 2 ;;
    --resolution)
        cli_resolution="$2"; shift 2 ;;        # 暂存，.env 读取后再合并
    --ssh-key)
        ssh_key_path="$2"; shift 2 ;;
    --image)
        local_image="$2"; shift 2 ;;
    --skip-flash)
        skip_flash=1; shift ;;
    --boot-dir)
        boot_dir="$2"; shift 2 ;;
    -*)
        die "未知选项: $1" ;;
    *)
        if [[ -z "$device" ]]; then
            device="$1"; shift
        else
            die "多余参数: $1"
        fi ;;
    esac
done

[[ -n "$device" || -n "$boot_dir" ]] || die "请指定目标设备（如 /dev/sda）或 --boot-dir <path>"

# --------------------------------------------------------------------------- #
# 加载团队 .env 配置
# --------------------------------------------------------------------------- #
# 优先级：命令行 --tailscale-key > teams/<name>/.env > 根目录 .env
_read_env_key() {
    local file="$1" key="$2"
    [[ -f "$file" ]] && grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2-
}

# 先读根目录 .env，再用团队 .env 覆盖
team_env="${REPO_ROOT}/teams/${team_name}/.env"
root_env="${REPO_ROOT}/.env"

_ts=$(_read_env_key "$root_env" TAILSCALE_AUTHKEY || true)
[[ -n "${_ts:-}" ]] && tailscale_key="$_ts"

_ts=$(_read_env_key "$team_env" TAILSCALE_AUTHKEY || true)
[[ -n "${_ts:-}" ]] && tailscale_key="$_ts"

# 命令行参数最高优先级
[[ -n "$cli_tailscale_key" ]] && tailscale_key="$cli_tailscale_key"

# GHCR Token（用于拉取 ghcr.io 私有镜像）
_gt=$(_read_env_key "$root_env" GHCR_TOKEN || true)
[[ -n "${_gt:-}" ]] && ghcr_token="$_gt"

_gt=$(_read_env_key "$team_env" GHCR_TOKEN || true)
[[ -n "${_gt:-}" ]] && ghcr_token="$_gt"

[[ -n "$cli_ghcr_token" ]] && ghcr_token="$cli_ghcr_token"

# HOSTNAME_PREFIX（主机名前缀；优先级：CLI > teams/.env > .env > team_name）
_hp=$(_read_env_key "$root_env" HOSTNAME_PREFIX || true)
[[ -n "${_hp:-}" ]] && hostname_prefix="$_hp"

_hp=$(_read_env_key "$team_env" HOSTNAME_PREFIX || true)
[[ -n "${_hp:-}" ]] && hostname_prefix="$_hp"

[[ -n "$cli_hostname_prefix" ]] && hostname_prefix="$cli_hostname_prefix"

# 最终 fallback：用 team_name 作为主机名前缀
[[ -z "$hostname_prefix" ]] && hostname_prefix="$team_name"

# TIMEZONE（云初始化时区；仅影响 RPi 系统时区，不影响 Docker 容器的 TZ）
# 回退优先级：TIMEZONE > TZ（仅填一个 TZ 即可同时控制容器和宿主机时区）
_tz=$(_read_env_key "$root_env" TIMEZONE || true)
[[ -z "${_tz:-}" ]] && _tz=$(_read_env_key "$root_env" TZ || true)
[[ -n "${_tz:-}" ]] && timezone="$_tz"

_tz=$(_read_env_key "$team_env" TIMEZONE || true)
[[ -z "${_tz:-}" ]] && _tz=$(_read_env_key "$team_env" TZ || true)
[[ -n "${_tz:-}" ]] && timezone="$_tz"

[[ -n "$cli_timezone" ]] && timezone="$cli_timezone"

# HDMI_RESOLUTION（HDMI 输出分辨率；未设置时保留内置默认值 800x480）
_res=$(_read_env_key "$root_env" HDMI_RESOLUTION || true)
[[ -n "${_res:-}" ]] && resolution="$_res"

_res=$(_read_env_key "$team_env" HDMI_RESOLUTION || true)
[[ -n "${_res:-}" ]] && resolution="$_res"

[[ -n "$cli_resolution" ]] && resolution="$cli_resolution"

unset _ts _gt _hp _tz _res

if [[ -n "$tailscale_key" ]]; then
    if [[ -f "$team_env" ]]; then
        info "Tailscale key 来源: teams/${team_name}/.env"
    elif [[ -n "$cli_tailscale_key" ]]; then
        info "Tailscale key 来源: 命令行参数"
    else
        info "Tailscale key 来源: .env"
    fi
fi

# --------------------------------------------------------------------------- #
# Validation
# --------------------------------------------------------------------------- #

# --boot-dir 模式不需要 root 或块设备
if [[ -n "$boot_dir" ]]; then
    [[ -d "$boot_dir" ]] || die "boot 目录不存在: $boot_dir"
    skip_flash=1
else
    if [[ "$EUID" -ne 0 ]]; then
        die "需要 root 权限。请使用 sudo 运行此脚本。"
    fi
    [[ -b "$device" ]] || die "设备 $device 不存在或不是块设备"
fi

# 分辨率预设解析
case "$resolution" in
    720p)   resolution="1280x720"  ;;
    1080p)  resolution="1920x1080" ;;
    2k)     resolution="2560x1440" ;;
    4k)     resolution="3840x2160" ;;
    "")     ;;  # 留空=自动
    *)
        [[ "$resolution" =~ ^[0-9]+x[0-9]+$ ]] || die "分辨率格式错误: $resolution（示例: 1080p, 4k, 2560x1440）"
        ;;
esac

# SSH 公钥（默认自动检测本机 key，--ssh-key 可覆盖）
ssh_pubkey=""
if [[ -n "$ssh_key_path" ]]; then
    [[ -f "$ssh_key_path" ]] || die "SSH 公钥文件不存在: $ssh_key_path"
    ssh_pubkey="$(cat "$ssh_key_path")"
    info "SSH 公钥: ${ssh_key_path}"
else
    # 自动检测本机 SSH 公钥（优先 ed25519）
    for _key in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub; do
        if [[ -f "$_key" ]]; then
            ssh_pubkey="$(cat "$_key")"
            ssh_key_path="$_key"
            info "SSH 公钥（自动检测）: ${_key}"
            break
        fi
    done
    [[ -z "$ssh_pubkey" ]] && warn "未找到本机 SSH 公钥（~/.ssh/id_*.pub），RPi 将仅可通过 Tailscale SSH 访问"
fi

# --------------------------------------------------------------------------- #
# Confirmation
# --------------------------------------------------------------------------- #
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
_box "Muliao RPi 5 — 镜像烧录"
echo "╠══════════════════════════════════════════════════════════════╣"
if [[ -n "$boot_dir" ]]; then
    _box "模式:         WSL2 / 手动 (--boot-dir)"
    _box "Boot 分区:    $boot_dir"
else
    _box "目标设备:     $device"
fi
_box "团队:         $team_name"
_box "主机名前缀:   ${hostname_prefix}-<xxxx>"
_box "时区:         $timezone"
_box "Tailscale:    ${tailscale_key:+已配置}"
_box "GHCR Token:   ${ghcr_token:+已配置}"
_box "分辨率:       ${resolution:-自动检测}"
if [[ -n "$ssh_pubkey" ]]; then
    _box "SSH 公钥:     $ssh_key_path"
fi
if [[ -z "$boot_dir" && "$skip_flash" -eq 0 ]]; then
    echo "╠══════════════════════════════════════════════════════════════╣"
    _box "⚠️  目标设备上的所有数据将被擦除！"
fi
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
read -rp "确认继续？(yes/no) " confirm
[[ "$confirm" == "yes" ]] || { echo "已取消。"; exit 0; }

# --------------------------------------------------------------------------- #
# Step 1: Download image (if needed — 仅原生烧录模式)
# --------------------------------------------------------------------------- #
if [[ "$skip_flash" -eq 0 ]]; then
    mkdir -p "$CACHE_DIR"

    if [[ -n "$local_image" ]]; then
        image_path="$local_image"
        info "使用本地镜像: $image_path"
    elif [[ -f "${CACHE_DIR}/${UBUNTU_IMAGE_NAME}" ]]; then
        image_path="${CACHE_DIR}/${UBUNTU_IMAGE_NAME}"
        info "使用缓存镜像: $image_path"
    else
        image_path="${CACHE_DIR}/${UBUNTU_IMAGE_NAME}"
        info "下载 Ubuntu Server ${UBUNTU_VERSION} ARM64 镜像..."
        info "URL: ${UBUNTU_IMAGE_URL}"
        curl -fSL --progress-bar -o "$image_path" "$UBUNTU_IMAGE_URL"
        ok "镜像下载完成"
    fi
fi

# --------------------------------------------------------------------------- #
# Step 2: Flash image to device
# --------------------------------------------------------------------------- #
if [[ "$skip_flash" -eq 0 ]]; then
    info "正在烧录镜像到 ${device}..."

    # 卸载设备上所有已挂载的分区
    if command -v umount &>/dev/null; then
        umount "${device}"* 2>/dev/null || true
    fi

    # 烧录（xz 解压 + dd）
    xz -dc "$image_path" | dd of="$device" bs=4M status=progress conv=fsync

    # 通知内核重新读取分区表
    sync
    partprobe "$device" 2>/dev/null || true
    sleep 2

    ok "镜像烧录完成"
else
    info "跳过烧录（--skip-flash）"
fi

# --------------------------------------------------------------------------- #
# Step 3: Mount system-boot partition & inject cloud-init
# --------------------------------------------------------------------------- #
need_umount=0

if [[ -n "$boot_dir" ]]; then
    # WSL2 / 手动模式：直接使用已挂载的 boot 目录
    mount_point="$boot_dir"
    info "使用已挂载的 boot 分区: $mount_point"
else
    info "挂载 system-boot 分区..."

    # 确定 system-boot 分区路径（通常是第一个分区）
    # NVMe: /dev/nvme0n1p1, SATA/USB: /dev/sda1
    if [[ "$device" == /dev/nvme* ]]; then
        boot_part="${device}p1"
    else
        boot_part="${device}1"
    fi

    [[ -b "$boot_part" ]] || die "未找到 system-boot 分区: $boot_part"

    mount_point=$(mktemp -d)
    mount "$boot_part" "$mount_point"
    need_umount=1
fi

info "注入 cloud-init user-data..."

# 从模板生成 user-data，替换占位符
user_data_template="${SCRIPT_DIR}/user-data"
[[ -f "$user_data_template" ]] || die "未找到 user-data 模板: $user_data_template"

sed \
    -e "s|__HOSTNAME__|${hostname_prefix}|g" \
    -e "s|__TIMEZONE__|${timezone}|g" \
    -e "s|__TAILSCALE_AUTHKEY__|${tailscale_key}|g" \
    -e "s|__SSH_PUBKEY__|${ssh_pubkey}|g" \
    -e "s|__GHCR_TOKEN__|${ghcr_token}|g" \
    "$user_data_template" | tr -d '\r' > "${mount_point}/user-data"

# 如果没有提供 SSH key，删除空的 ssh_authorized_keys 条目
if [[ -z "$ssh_pubkey" ]]; then
    tmpfile=$(mktemp)
    sed '/ssh_authorized_keys:/,/^[^ ]/{ /ssh_authorized_keys:/d; /^[[:space:]]*- *$/d; }' "${mount_point}/user-data" > "$tmpfile"
    cp "$tmpfile" "${mount_point}/user-data"
    rm -f "$tmpfile"
fi

ok "cloud-init user-data 已写入"

# 复制 muliao.service 到 boot 分区（cloud-init runcmd 会从此处安装）
cp "${SCRIPT_DIR}/muliao.service" "${mount_point}/muliao.service"
ok "muliao.service 已写入"

# 写入 meta-data（含唯一 instance-id，确保 cloud-init 每次刷写都重新执行）
echo "instance-id: muliao-$(date +%s)" > "${mount_point}/meta-data"

# --------------------------------------------------------------------------- #
# Step 3b: 设置 HDMI 分辨率（可选）
# --------------------------------------------------------------------------- #
# RPi 5 使用 KMS/DRM 驱动，分辨率通过 cmdline.txt video= 参数设置。
# config.txt 的 framebuffer_width/height 作为 fallback。
if [[ -n "$resolution" ]]; then
    res_w="${resolution%%x*}"
    res_h="${resolution##*x}"
    info "设置 HDMI 分辨率: ${res_w}x${res_h}"

    # cmdline.txt: 追加 video= 参数（KMS 驱动使用）
    cmdline_file="${mount_point}/cmdline.txt"
    if [[ -f "$cmdline_file" ]]; then
        tmpfile=$(mktemp)
        # 移除已有的 video= 参数（如有），追加新的
        sed "s/ video=[^ ]*//g" "$cmdline_file" | \
            sed "s/$/ video=HDMI-A-1:${res_w}x${res_h}@60/" > "$tmpfile"
        cp "$tmpfile" "$cmdline_file"
        rm -f "$tmpfile"
        ok "cmdline.txt 已设置 video=${res_w}x${res_h}@60"
    else
        warn "未找到 cmdline.txt，跳过 video= 参数"
    fi

    # config.txt: 追加 framebuffer 尺寸作为 fallback
    config_file="${mount_point}/config.txt"
    if [[ -f "$config_file" ]]; then
        tmpfile=$(mktemp)
        # 移除已有的 framebuffer 设置
        grep -v -E '^framebuffer_(width|height)=' "$config_file" > "$tmpfile"
        {
            echo ""
            echo "# Muliao: HDMI 分辨率 (flash-ssd.sh --resolution ${resolution})"
            echo "framebuffer_width=${res_w}"
            echo "framebuffer_height=${res_h}"
        } >> "$tmpfile"
        cp "$tmpfile" "$config_file"
        rm -f "$tmpfile"
        ok "config.txt 已设置 framebuffer ${res_w}x${res_h}"
    else
        warn "未找到 config.txt，跳过 framebuffer 设置"
    fi
fi

# --------------------------------------------------------------------------- #
# Step 4: Cleanup
# --------------------------------------------------------------------------- #
sync
if [[ "$need_umount" -eq 1 ]]; then
    umount "$mount_point"
    rmdir "$mount_point"
fi

echo ""
ok "烧录完成！"
echo ""
echo "下一步："
if [[ -n "$boot_dir" ]]; then
    echo "  1. 安全弹出 SSD："
    echo "     sudo umount ${boot_dir}"
    echo "     然后从 Windows 右下角「安全删除硬件」"
    echo "  2. 将 SSD 插入 RPi 5（NVMe HAT）"
else
    echo "  1. 将 SSD 插入 RPi 5（NVMe HAT）"
fi
echo "  2. 接上网线和电源"
echo "  3. 等待 5-10 分钟让 cloud-init 完成初始化"
echo "  4. 主机名会自动生成为: ${hostname_prefix}-<序列号后4位>"
echo "     在 Tailscale Admin 控制台查看实际主机名"
echo "  5. 通过 Tailscale SSH 连接："
echo "     ssh muliao@${hostname_prefix}-xxxx     # Tailscale（xxxx 为序列号后4位）"
echo "     ssh muliao@${hostname_prefix}-xxxx.local  # mDNS"
echo "  6. 确认 cloud-init 完成："
echo "     cat /home/muliao/.cloud-init-done"
echo "  7. 部署团队数据："
echo "     deploy/rpi/deploy-team.sh <实际主机名> --team ${team_name}"
