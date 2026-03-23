#!/bin/bash
# ==============================================================================
# run.sh — OpenClaw Runtime Container (Docker Compose)
# ==============================================================================
#
# Usage:
#   run.sh [options]
#   run.sh --help
#
# Description:
#   Docker Compose wrapper，管理 Muliao OpenClaw 运行容器。
#   底层使用 docker-compose.yml 编排（host 网络模式）。
#   也可直接使用 `docker compose` 命令（详见 docker-compose.yml 注释）。
#
# Features:
#   - Muliao 自定义镜像（预装 OpenClaw + 常用依赖）
#   - ~/.openclaw 持久化挂载（配置 + workspace + session 全部保留）
#   - npm 全局包写入容器可写层，restart 后保留
#   - Chromium headless 浏览器（--cap-add SYS_ADMIN + --shm-size 2g）
#
# Directory layout (repo-relative):
#   teams/<name>/            OpenClaw 运行时数据（credentials、sessions、workspace）
#                            挂载 → /home/muliao/.openclaw
#
# Options:
#   --restart         强制删除并重新创建容器
#   --team NAME       团队名称，对应 teams/<NAME>/（默认：default）
#   --build           强制重新构建本地镜像（docker/Dockerfile）
#   --image TAG       Docker 镜像 tag（默认：ghcr.io/muliaoio/muliao:latest）
#   -h, --help        显示帮助
#
# Examples:
#   run.sh                          # 启动容器（gateway 自动运行）
#   run.sh --restart                # 强制重建容器
#   run.sh --team hermes            # 启动 hermes 团队
#   run.sh --image ghcr.io/muliaoio/muliao:dev  # 指定镜像
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


network="host"
team_name="default"
restart=0
build=0
tag=""

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
options=$(getopt -o h --long restart,build,team:,image:,help -- "$@")
eval set -- "$options"

while true; do
    case "$1" in
    -h | --help)
        show_help; exit 0 ;;
    --restart)
        restart=1; shift ;;
    --build)
        build=1; shift ;;
    --image)
        tag="$2"; shift 2 ;;
    --team)
        team_name="$2"; shift 2 ;;
    --)
        shift; break ;;
    esac
done

# --------------------------------------------------------------------------- #
# .env initialization
# --------------------------------------------------------------------------- #
if [[ ! -f "${REPO_ROOT}/.env" ]]; then
    echo "Initializing ${REPO_ROOT}/.env from .env.example..."
    cp "${REPO_ROOT}/.env.example" "${REPO_ROOT}/.env"
fi

# --------------------------------------------------------------------------- #
# Resolve team → data directory
# --------------------------------------------------------------------------- #
data_dir="${REPO_ROOT}/teams/${team_name}"
mkdir -p "${data_dir}"

# --------------------------------------------------------------------------- #
# Export overrides（CLI 参数 → 环境变量，优先级高于 .env 文件）
# --------------------------------------------------------------------------- #
export MULIAO_DATA_DIR="${data_dir}"
export MULIAO_CONTAINER_NAME="muliao-${team_name}"
export TZ="${TZ:-$(cat /etc/timezone 2>/dev/null || echo UTC)}"
[[ -n "$tag" ]] && export MULIAO_IMAGE="$tag"

# --------------------------------------------------------------------------- #
# Compose command
# --------------------------------------------------------------------------- #
compose_cmd=(docker compose -f "${REPO_ROOT}/docker-compose.yml")

# --------------------------------------------------------------------------- #
# Image build (if --build)
# --------------------------------------------------------------------------- #
if [[ "$build" -eq 1 ]]; then
    "${REPO_ROOT}/docker/build.sh" --tag "${MULIAO_IMAGE:-ghcr.io/muliaoio/muliao:latest}"
fi

# --------------------------------------------------------------------------- #
# Info
# --------------------------------------------------------------------------- #
echo "Team:      ${team_name}"
echo "Image:     ${MULIAO_IMAGE:-ghcr.io/muliaoio/muliao:latest}"
echo "Data:      ${data_dir}"
echo ""

# --------------------------------------------------------------------------- #
# Container lifecycle（Docker Compose）
# --------------------------------------------------------------------------- #
if [[ "$restart" -eq 1 ]]; then
    echo "Recreating containers..."
    "${compose_cmd[@]}" down --remove-orphans 2>/dev/null || true
fi

# 启动 openclaw 服务（已运行则无操作）
"${compose_cmd[@]}" up -d openclaw

echo ""
echo "Gateway 已启动。进入容器 bash："
echo "  docker compose -f ${REPO_ROOT}/docker-compose.yml exec openclaw bash"
