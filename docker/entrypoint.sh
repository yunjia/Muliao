#!/bin/bash
# =============================================================================
# entrypoint.sh — UID/GID 动态映射 + gosu 降权
# =============================================================================
#
# 两种启动模式：
#
#   1. Root 启动（默认，run.sh 场景）
#      通过 PUID/PGID 环境变量将容器内 node 用户的 UID/GID 映射到宿主机，
#      然后用 gosu 降权执行命令。bind mount 文件归属自动匹配。
#
#   2. 非 Root 启动（K8s runAsUser / Compose user: / --user 场景）
#      跳过 UID 映射，直接执行命令。
#
# Environment:
#   PUID    目标 UID（默认：1000）
#   PGID    目标 GID（默认：1000）
# =============================================================================

set -e

if [ "$(id -u)" = "0" ]; then
    # ---- Root 路径：UID/GID 映射 + gosu 降权 ----
    PUID="${PUID:-1000}"
    PGID="${PGID:-1000}"

    cur_uid=$(id -u node)
    cur_gid=$(id -g node)

    [ "$PGID" != "$cur_gid" ] && groupmod -g "$PGID" node
    [ "$PUID" != "$cur_uid" ] && usermod -u "$PUID" -o node
    chown node:node /home/node

    exec gosu node "$@"
else
    # ---- 非 Root 路径：直接执行 ----
    exec "$@"
fi
