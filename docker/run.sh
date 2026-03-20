#!/bin/bash
# ==============================================================================
# run.sh — OpenClaw Runtime Container
# ==============================================================================
#
# Usage:
#   run.sh [options]
#   run.sh --help
#
# Description:
#   基于上游 node:24-bookworm 镜像创建 OpenClaw 运行容器。
#   挂载配置目录、workspace、X11 socket，支持 GUI 浏览器控制。
#   不依赖 OpenClaw 官方镜像，从标准 Node.js 镜像启动。
#
# Features:
#   - node:24-bookworm 作为基础镜像（upstream，无需定制 image）
#   - ~/.openclaw 持久化挂载（配置 + workspace + session 全部保留）
#   - X11 passthrough，支持有头 Chromium（GUI 浏览器模式）
#   - --shm-size 2g，防止 Chromium OOM
#   - --cap-add SYS_ADMIN，支持 browser sandbox（比 --privileged 更保守）
#
# Directory layout (repo-relative):
#   teams/<name>/config/     运行时状态（credentials、sessions）— gitignored 内容
#                            挂载 → /home/node/.openclaw
#   teams/<name>/workspace/  Agent "大脑"（AGENTS.md、SOUL.md、skills/、memory/）
#                            挂载 → /home/node/.openclaw/workspace（叠加挂载）
#
# Options:
#   --restart         强制删除并重新创建容器
#   --name NAME       容器名称（默认：openclaw）
#   --network MODE    网络模式：host（默认）| bridge
#   --team NAME       团队名称，对应 teams/<NAME>/（默认：default）
#   --build           强制重新构建本地镜像（docker/Dockerfile）
#   --image TAG       Docker 镜像 tag（默认：ghcr.io/teabots/pantheon:latest）
#   --no-browser      跳过 SYS_ADMIN cap 和 shm（不需要 GUI 浏览器时使用）
#   --gateway         进入容器后直接启动 openclaw gateway（默认：bash）
#   -h, --help        显示帮助
#
# Examples:
#   run.sh                          # 交互式 bash
#   run.sh --network bridge         # bridge 网络（需要端口隔离时使用）
#   run.sh --restart                # 强制重建容器
#   run.sh --team hermes            # 启动 hermes 团队
#   run.sh --gateway                # 直接启动 gateway
#   run.sh --no-browser             # 无浏览器模式，更轻量
#   run.sh --image ghcr.io/teabots/pantheon:dev  # 指定镜像
# ==============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Help
# --------------------------------------------------------------------------- #
show_help() {
    sed -n '/^# Usage:/,/^# ====/{/^# ====/d; p}' "$0" | sed 's/^# \{0,1\}//'
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

# --------------------------------------------------------------------------- #
# Defaults
# --------------------------------------------------------------------------- #
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"

container="openclaw"
network="host"
team_name="default"
config_dir="${REPO_ROOT}/teams/${team_name}/config"
workspace_dir="${REPO_ROOT}/teams/${team_name}/workspace"
browser_support=1
gateway_mode=0
restart=0
build=0
tag=""
docker_args=()

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
options=$(getopt -o h --long restart,build,name:,network:,team:,image:,no-browser,gateway,help -- "$@")
eval set -- "$options"

while true; do
    case "$1" in
    -h | --help)
        show_help; exit 0 ;;
    --restart)
        restart=1; shift ;;
    --build)
        build=1; shift ;;
    --name)
        container="$2"; shift 2 ;;
    --network)
        network="$2"; shift 2 ;;
    --image)
        tag="$2"; shift 2 ;;
    --team)
        team_name="$2"
        config_dir="${REPO_ROOT}/teams/${team_name}/config"
        workspace_dir="${REPO_ROOT}/teams/${team_name}/workspace"
        shift 2 ;;
    --no-browser)
        browser_support=0; shift ;;
    --gateway)
        gateway_mode=1; shift ;;
    --)
        shift; break ;;
    esac
done

# --------------------------------------------------------------------------- #
# Image selection / build
# --------------------------------------------------------------------------- #
local_tag="ghcr.io/teabots/pantheon:latest"
if [[ -z "${tag:-}" ]]; then
    tag="$local_tag"
fi

# 仅在 --build 时构建本地镜像
if [[ "$build" -eq 1 ]]; then
    "${REPO_ROOT}/docker/build.sh" --tag "${tag}"
fi

echo "Using image: ${tag}"

# --------------------------------------------------------------------------- #
# Network
# --------------------------------------------------------------------------- #
docker_args+=(--network "$network")
echo "Network mode: ${network}"

# --------------------------------------------------------------------------- #
# Browser: SYS_ADMIN + shm（Chromium sandbox 需要）
# --------------------------------------------------------------------------- #
if [[ "$browser_support" -eq 1 ]]; then
    echo "Browser support enabled (--cap-add SYS_ADMIN, --shm-size 2g)"
    echo "  Tip: set browser.noSandbox=true in openclaw.json if Chrome still fails."
    docker_args+=(--cap-add SYS_ADMIN)
    docker_args+=(--shm-size 2g)
fi

# --------------------------------------------------------------------------- #
# Ensure dirs exist on host
# --------------------------------------------------------------------------- #
echo "Config dir:    ${config_dir}"
echo "Workspace dir: ${workspace_dir}"
mkdir -p "${config_dir}"
mkdir -p "${workspace_dir}"

# --------------------------------------------------------------------------- #
# Container lifecycle
# --------------------------------------------------------------------------- #
if docker inspect "${container}" &>/dev/null; then
    if [[ "$restart" -eq 1 ]]; then
        echo "Removing existing container ${container}..."
        docker rm -f "${container}"
    else
        running=$(docker inspect --format '{{.State.Running}}' "${container}")
        if [[ "$running" == "false" ]]; then
            echo "Starting existing container ${container}..."
            docker start "${container}"
        fi
    fi
fi

if ! docker inspect "${container}" &>/dev/null; then
    echo "Creating new container ${container}..."

    # Port mapping（仅 bridge 模式有意义）:
    #   18789 — OpenClaw Gateway / Control UI
    #   18791 — Browser control service（gateway port + 2）
    #
    # 关键：Gateway 默认绑定 loopback（127.0.0.1），容器内的 loopback
    # 对宿主机不可见，-p 端口映射会失效。
    # 必须设 OPENCLAW_GATEWAY_BIND=lan 让 Gateway 监听 0.0.0.0，
    # Docker 的端口转发才能生效。
    # （host 模式下 Gateway 直接绑定宿主机 loopback，无需此变量）
    port_args=()
    if [[ "$network" == "bridge" ]]; then
        port_args+=(-p 18789:18789 -p 18791:18791)
        port_args+=(-e OPENCLAW_GATEWAY_BIND=lan)
    fi

    docker run -itd \
        --name "${container}" \
        \
        `# 以宿主机 uid/gid 运行，bind mount 文件归属一致` \
        --user "$(id -u):$(id -g)" \
        `# /home/node 作为 HOME，tmpfs 保证任意 uid 可写（重启后清空无妨）` \
        `# exec 必须显式加：Docker tmpfs 默认带 noexec，否则 npm 安装的二进制无法执行` \
        --tmpfs "/home/node:uid=$(id -u),gid=$(id -g),exec" \
        -e HOME=/home/node \
        `# npm 全局前缀重定向到 tmpfs HOME，避免写入 root 所有的 /usr/local` \
        -e NPM_CONFIG_PREFIX=/home/node/.npm-global \
        -e "PATH=/home/node/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        \
        `# X11 GUI 浏览器支持` \
        -e DISPLAY \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        \
        `# 时区同步` \
        -v /etc/timezone:/etc/timezone:ro \
        -v /etc/localtime:/etc/localtime:ro \
        \
        `# SSH keys（只读，用于 git / remote gateway 场景）` \
        -v "${HOME}/.ssh:/home/node/.ssh:ro" \
        \
        `# OpenClaw 配置持久化（运行时状态：credentials、sessions）` \
        -v "${config_dir}:/home/node/.openclaw" \
        `# Agent workspace 单独叠加挂载（大脑：AGENTS.md、skills/、memory/）` \
        -v "${workspace_dir}:/home/node/.openclaw/workspace" \
        \
        `# 透传宿主机环境变量（如已设置 API key）` \
        ${ANTHROPIC_API_KEY:+-e ANTHROPIC_API_KEY} \
        ${OPENAI_API_KEY:+-e OPENAI_API_KEY} \
        ${TELEGRAM_BOT_TOKEN:+-e TELEGRAM_BOT_TOKEN} \
        ${DISCORD_BOT_TOKEN:+-e DISCORD_BOT_TOKEN} \
        ${OPENCLAW_GATEWAY_TOKEN:+-e OPENCLAW_GATEWAY_TOKEN} \
        \
        "${port_args[@]}" \
        "${docker_args[@]}" \
        "$tag"
fi

# --------------------------------------------------------------------------- #
# Enter container
# --------------------------------------------------------------------------- #
if [[ "$gateway_mode" -eq 1 ]]; then
    echo "Starting OpenClaw gateway in container ${container}..."
    docker exec -it "${container}" bash -c "
        command -v openclaw &>/dev/null || npm install -g openclaw@latest
        openclaw gateway --port 18789 --verbose
    "
else
    echo "Dropping into bash in container ${container}..."
    echo ""
    echo "Quick start inside the container:"
    echo "  npm install -g openclaw@latest"
    echo "  openclaw onboard          # --install-daemon 在容器内无效，容器即进程管理器"
    echo ""
    echo "For GUI browser (Chromium headless):"
    echo "  npx playwright install chromium --with-deps"
    echo "  # Then in ~/.openclaw/openclaw.json:"
    echo "  # { \"browser\": { \"enabled\": true, \"headless\": true, \"noSandbox\": true } }"
    echo ""
    docker exec -it "${container}" bash
fi
