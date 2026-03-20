#!/bin/bash
# ==============================================================================
# build.sh — Build Pantheon OpenClaw Image
# ==============================================================================
#
# Usage:
#   build.sh [options]
#   build.sh --help
#
# Description:
#   构建 Pantheon OpenClaw 运行镜像（docker/Dockerfile）。
#   支持多平台构建（buildx）和推送到 ghcr.io。
#
# Options:
#   --node VERSION    Node 主版本号（22|24，默认：24）
#   --tag TAG         完整镜像 tag（默认：ghcr.io/teabots/pantheon:latest）
#   --push            构建后推送到 registry
#   --platform PLAT   目标平台（默认：linux/amd64,linux/arm64）
#   --no-cache        构建时不使用缓存
#   -h, --help        显示帮助
#
# Examples:
#   build.sh                                    # 本地构建 node24 镜像
#   build.sh --node 22                          # 构建 node22 变体
#   build.sh --push                             # 构建并推送
#   build.sh --tag ghcr.io/teabots/pantheon:dev  # 自定义 tag
#   build.sh --push --platform linux/amd64      # 仅 amd64，推送
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
DOCKERFILE="${REPO_ROOT}/docker/Dockerfile"

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
node_ver="24"
tag=""
push=0
platform="linux/amd64,linux/arm64"
no_cache=0

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
options=$(getopt -o h --long node:,tag:,push,platform:,no-cache,help -- "$@")
eval set -- "$options"

while true; do
    case "$1" in
    -h | --help)
        show_help; exit 0 ;;
    --node)
        node_ver="$2"; shift 2 ;;
    --tag)
        tag="$2"; shift 2 ;;
    --push)
        push=1; shift ;;
    --platform)
        platform="$2"; shift 2 ;;
    --no-cache)
        no_cache=1; shift ;;
    --)
        shift; break ;;
    esac
done

# --------------------------------------------------------------------------- #
# Resolve tag
# --------------------------------------------------------------------------- #
if [[ -z "$tag" ]]; then
    tag="ghcr.io/teabots/pantheon:latest"
fi

echo "Image:    ${tag}"
echo "Node:     ${node_ver}"
echo "Platform: ${platform}"
echo "Push:     $([[ $push -eq 1 ]] && echo yes || echo no)"
echo ""

# --------------------------------------------------------------------------- #
# Build
# --------------------------------------------------------------------------- #
build_args=(
    --build-arg "NODE_VER=${node_ver}"
    -f "${DOCKERFILE}"
    -t "${tag}"
    --platform "${platform}"
)

if [[ "$no_cache" -eq 1 ]]; then
    build_args+=(--no-cache)
fi

if [[ "$push" -eq 1 ]]; then
    # 推送需要 buildx（支持多平台）
    echo "Building and pushing with buildx..."
    docker buildx build "${build_args[@]}" --push "${REPO_ROOT}"
else
    if [[ "$platform" == *","* ]]; then
        # 多平台本地 load 需要 buildx，但 --load 不支持多平台，降级为当前平台
        current_platform="linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
        echo "Note: multi-platform local build is not supported without --push."
        echo "      Building for current platform only: ${current_platform}"
        build_args=(
            --build-arg "NODE_VER=${node_ver}"
            -f "${DOCKERFILE}"
            -t "${tag}"
            --platform "${current_platform}"
        )
        [[ "$no_cache" -eq 1 ]] && build_args+=(--no-cache)
        docker buildx build "${build_args[@]}" --load "${REPO_ROOT}"
    else
        docker buildx build "${build_args[@]}" --load "${REPO_ROOT}"
    fi
fi

echo ""
echo "Done: ${tag}"
