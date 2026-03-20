# =============================================================================
# Pantheon — OpenClaw Runtime Image
# =============================================================================
# Description:
#   基于上游 node:24-bookworm，为 OpenClaw 添加必要的系统依赖。
#   node 用户具有 passwordless sudo，便于容器内 apt install 额外工具。
#
# Base Image:
#   node:24-bookworm
#
# Build:
#   docker/build.sh              # 本地构建（当前平台）
#   docker/build.sh --push       # 多平台构建并推送到 ghcr.io
#   run.sh --build               # 开发时自动构建本地镜像
#
# Features:
#   - node 用户 passwordless sudo（可 sudo apt install 任意包）
#   - 常见 Skill 依赖预装（ffmpeg、jq、ripgrep 等）
#   - Chromium sandbox 所需依赖
#   - 运行时仍以非 root（node）用户启动，bind mount 归属一致
#
# User: node (UID: 1000)
# =============================================================================

ARG NODE_VER=24
FROM node:${NODE_VER}-bookworm

# Install sudo and common Skill/browser dependencies as root
RUN apt-get update && apt-get install -y --no-install-recommends \
        sudo \
        # 常用 Skill 依赖
        ffmpeg \
        jq \
        ripgrep \
        curl \
        wget \
        git \
        # Chromium / Playwright 依赖
        libnss3 \
        libatk-bridge2.0-0 \
        libcups2 \
        libdrm2 \
        libxkbcommon0 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxrandr2 \
        libgbm1 \
        libasound2 \
        # 中文字体（agent 截图 / 浏览器渲染）
        fonts-noto-cjk \
        fonts-noto-color-emoji \
    && rm -rf /var/lib/apt/lists/*

# 将 node 用户加入 sudoers（passwordless，对齐 teabot-dev 惯例）
RUN echo "node ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER node
