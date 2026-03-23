# =============================================================================
# Muliao — OpenClaw Runtime Image
# =============================================================================
# Description:
#   基于上游 node:24-bookworm，为 OpenClaw 添加必要的系统依赖。
#   muliao 用户具有 passwordless sudo，便于容器内 apt install 额外工具。
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
#   - muliao 用户 passwordless sudo（可 sudo apt install 任意包）
#   - 常见 Skill 依赖预装（ffmpeg、jq、ripgrep 等）
#   - Chromium sandbox 所需依赖
#   - OpenClaw 预装到镜像层（/usr/local），restart / recreate 后始终可用
#
# User: muliao (UID 1000)，与 WSL2 / RPi cloud-init 默认用户 UID 一致
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

# 将 node 用户重命名为 muliao（node base image 自带 node:node 用户）
RUN groupmod -n muliao node && \
    usermod -l muliao -d /home/muliao -m node && \
    echo "muliao ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# 预装 OpenClaw（写入 /usr/local，镜像层永久保留）
RUN npm install -g openclaw@latest && npm cache clean --force

USER muliao
WORKDIR /home/muliao
