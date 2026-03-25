#!/bin/bash
# ==============================================================================
# dev.sh — Multipass 开发 VM 管理工具
# ==============================================================================
#
# Usage:
#   dev.sh <command> [options]
#   dev.sh --help
#
# Commands:
#   launch              创建并启动开发 VM（cloud-init 自动配置）
#   shell [TEAM]        进入 VM bash（等同 multipass shell）
#   start [TEAM]        启动已停止的 VM
#   stop [TEAM]         停止 VM
#   delete [TEAM]       删除 VM（需确认）
#   list                列出所有 Muliao VM
#   gateway [TEAM]      在 VM 中启动 openclaw gateway
#
# Options:
#   --team NAME         团队名称（默认：muliao）
#   --cpus N            CPU 核数（默认：2）
#   --memory NG         内存大小（默认：4G）
#   --disk NG           磁盘大小（默认：20G）
#   --no-mount          不挂载 teams/<name>/ 到 VM
#   -h, --help          显示帮助
#
# Prerequisites:
#   sudo snap install multipass
#
# Description:
#   使用 Multipass 创建 Ubuntu VM 作为开发环境，通过 cloud-init（与 RPi
#   共享同一份 base 模板）自动安装 Node.js、OpenClaw、Docker 等依赖。
#
#   teams/<name>/ 通过 Multipass mount 双向共享到 VM 内的
#   /home/muliao/.openclaw，宿主机编辑文件 VM 立即可见。
#
# Examples:
#   dev.sh launch                       # 创建默认 VM
#   dev.sh launch --team hermes         # 创建 hermes 团队 VM
#   dev.sh launch --cpus 4 --memory 8G  # 自定义资源
#   dev.sh shell                        # 进入 VM
#   dev.sh gateway                      # 启动 gateway
#   dev.sh stop                         # 停止 VM
#   dev.sh delete                       # 删除 VM
# ==============================================================================

set -euo pipefail

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

# --------------------------------------------------------------------------- #
# Resolve repo root
# --------------------------------------------------------------------------- #
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
CLOUD_INIT_DIR="${REPO_ROOT}/deploy/cloud-init"

# --------------------------------------------------------------------------- #
# Defaults
# --------------------------------------------------------------------------- #
COMMAND=""
TEAM="muliao"
CPUS=2
MEMORY="4G"
DISK="20G"
NO_MOUNT=0

# VM name prefix
vm_name() { echo "muliao-${TEAM}"; }

# --------------------------------------------------------------------------- #
# Dependency check
# --------------------------------------------------------------------------- #
check_multipass() {
    command -v multipass >/dev/null 2>&1 \
        || die "Multipass 未安装。请运行: sudo snap install multipass"
}

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
parse_args() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    case "$1" in
        launch|shell|start|stop|delete|list|gateway)
            COMMAND="$1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            die "未知命令: $1（可用: launch, shell, start, stop, delete, list, gateway）"
            ;;
    esac

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --team)
                [[ $# -ge 2 ]] || die "--team 需要参数"
                TEAM="$2"; shift 2 ;;
            --cpus)
                [[ $# -ge 2 ]] || die "--cpus 需要参数"
                CPUS="$2"; shift 2 ;;
            --memory)
                [[ $# -ge 2 ]] || die "--memory 需要参数"
                MEMORY="$2"; shift 2 ;;
            --disk)
                [[ $# -ge 2 ]] || die "--disk 需要参数"
                DISK="$2"; shift 2 ;;
            --no-mount)
                NO_MOUNT=1; shift ;;
            -h|--help)
                show_help; exit 0 ;;
            *)
                # 允许 shell/start/stop/delete/gateway 后面直接跟 team name
                if [[ "$COMMAND" =~ ^(shell|start|stop|delete|gateway)$ && ! "$1" == --* ]]; then
                    TEAM="$1"; shift
                else
                    die "未知选项: $1"
                fi
                ;;
        esac
    done
}

# --------------------------------------------------------------------------- #
# .env initialization
# --------------------------------------------------------------------------- #
init_env() {
    local team_dir="${REPO_ROOT}/teams/${TEAM}"
    local team_env="${team_dir}/.env"

    if [[ ! -f "$team_env" ]]; then
        mkdir -p "$team_dir"
        info "初始化 teams/${TEAM}/.env ..."
        cp "${REPO_ROOT}/.env.example" "$team_env"
        echo ""
        warn "请编辑 teams/${TEAM}/.env 填入 API keys 等配置。"
        echo "  vim teams/${TEAM}/.env"
        echo ""
    fi
}

# --------------------------------------------------------------------------- #
# Load team .env for timezone
# --------------------------------------------------------------------------- #
_read_env_key() {
    local file="$1" key="$2"
    [[ -f "$file" ]] && grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- || true
}

# --------------------------------------------------------------------------- #
# cmd: launch
# --------------------------------------------------------------------------- #
do_launch() {
    check_multipass
    init_env

    local name
    name="$(vm_name)"

    # 检查 VM 是否已存在
    if multipass info "$name" &>/dev/null; then
        die "VM '$name' 已存在。使用 'dev.sh delete ${TEAM}' 先删除，或 'dev.sh start ${TEAM}' 启动。"
    fi

    # 准备 team 数据目录
    local team_dir="${REPO_ROOT}/teams/${TEAM}"
    mkdir -p "$team_dir"

    # 读取时区
    local team_env="${team_dir}/.env"
    local timezone
    timezone=$(_read_env_key "$team_env" "TZ")
    [[ -z "$timezone" ]] && timezone=$(_read_env_key "$team_env" "TIMEZONE")
    [[ -z "$timezone" ]] && timezone="$(cat /etc/timezone 2>/dev/null || echo UTC)"

    # 渲染 cloud-init user-data
    local user_data
    user_data=$(mktemp "$HOME/muliao-cloud-init-XXXXXX.yaml")

    info "渲染 cloud-init user-data..."
    "${CLOUD_INIT_DIR}/render.sh" \
        --base "${CLOUD_INIT_DIR}/base-user-data.yaml" \
        --overlay "${CLOUD_INIT_DIR}/dev-overlay.yaml" \
        --var "HOSTNAME=${name}" \
        --var "TIMEZONE=${timezone}" \
        -o "$user_data"
    chmod 644 "$user_data"

    # 启动 VM
    info "创建 VM: ${name}（${CPUS} CPU, ${MEMORY} RAM, ${DISK} disk）..."
    local launch_args=(
        multipass launch 24.04
        --name "$name"
        --cpus "$CPUS"
        --memory "$MEMORY"
        --disk "$DISK"
        --cloud-init "$user_data"
    )

    "${launch_args[@]}"
    rm -f "$user_data"

    # 挂载 teams 目录
    if [[ "$NO_MOUNT" -eq 0 ]]; then
        info "挂载 teams/${TEAM}/ → /home/muliao/.openclaw ..."
        multipass mount "$team_dir" "${name}:/home/muliao/.openclaw" \
            --uid-map "$(id -u):1000" --gid-map "$(id -g):1000" \
            || warn "挂载失败，你可以手动执行: multipass mount ${team_dir} ${name}:/home/muliao/.openclaw"
    fi

    ok "VM '${name}' 已就绪"
    echo ""
    echo "下一步："
    echo "  dev.sh shell ${TEAM}             # 进入 VM"
    echo "  dev.sh gateway ${TEAM}           # 启动 OpenClaw gateway"
    echo ""
    echo "等待 cloud-init 完成初始化（约 3-5 分钟），可通过以下命令查看进度："
    echo "  multipass exec ${name} -- tail -f /var/log/cloud-init-output.log"
}

# --------------------------------------------------------------------------- #
# cmd: shell
# --------------------------------------------------------------------------- #
do_shell() {
    check_multipass
    local name
    name="$(vm_name)"
    multipass shell "$name"
}

# --------------------------------------------------------------------------- #
# cmd: start
# --------------------------------------------------------------------------- #
do_start() {
    check_multipass
    local name
    name="$(vm_name)"
    info "启动 VM: ${name}..."
    multipass start "$name"
    ok "VM '${name}' 已启动"
}

# --------------------------------------------------------------------------- #
# cmd: stop
# --------------------------------------------------------------------------- #
do_stop() {
    check_multipass
    local name
    name="$(vm_name)"
    info "停止 VM: ${name}..."
    multipass stop "$name"
    ok "VM '${name}' 已停止"
}

# --------------------------------------------------------------------------- #
# cmd: delete
# --------------------------------------------------------------------------- #
do_delete() {
    check_multipass
    local name
    name="$(vm_name)"

    if ! multipass info "$name" &>/dev/null; then
        die "VM '${name}' 不存在"
    fi

    echo "⚠️  即将删除 VM: ${name}"
    echo "   teams/${TEAM}/ 目录不会被删除（仅 VM 本身）。"
    read -r -p "   确认删除？[y/N] " answer
    case "$answer" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "已取消。"; exit 0 ;;
    esac

    info "删除 VM: ${name}..."
    multipass delete "$name" --purge
    ok "VM '${name}' 已删除"
}

# --------------------------------------------------------------------------- #
# cmd: list
# --------------------------------------------------------------------------- #
do_list() {
    check_multipass
    info "Muliao VM 列表："
    multipass list | head -1
    multipass list | grep -E "^muliao-" || echo "  （无 Muliao VM）"
}

# --------------------------------------------------------------------------- #
# cmd: gateway
# --------------------------------------------------------------------------- #
do_gateway() {
    check_multipass
    local name
    name="$(vm_name)"

    # 检查 VM 是否运行中
    local state
    state=$(multipass info "$name" --format csv 2>/dev/null | tail -1 | cut -d, -f2)
    [[ "$state" == "Running" ]] || die "VM '${name}' 未运行。请先执行: dev.sh start ${TEAM}"

    # 将 .env 注入为 VM 内的环境变量并启动 gateway
    local team_env="${REPO_ROOT}/teams/${TEAM}/.env"

    info "在 VM '${name}' 中启动 openclaw gateway..."

    if [[ -f "$team_env" ]]; then
        # 读取 .env 中的 export 变量（过滤注释和空行），注入到 VM 并启动 gateway
        local env_exports=""
        while IFS= read -r line; do
            # 跳过注释和空行
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue
            # 只传有值的变量
            local key="${line%%=*}"
            local val="${line#*=}"
            [[ -z "$val" ]] && continue
            env_exports+="export ${key}='${val}'; "
        done < "$team_env"

        multipass exec "$name" -- sudo -u muliao -i bash -c \
            "${env_exports} openclaw gateway"
    else
        multipass exec "$name" -- sudo -u muliao -i bash -c "openclaw gateway"
    fi
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
parse_args "$@"

case "$COMMAND" in
    launch)  do_launch  ;;
    shell)   do_shell   ;;
    start)   do_start   ;;
    stop)    do_stop    ;;
    delete)  do_delete  ;;
    list)    do_list    ;;
    gateway) do_gateway ;;
esac
