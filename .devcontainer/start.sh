#!/bin/bash
# start.sh — FreeCloudCode 每次开机启动服务

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

# 加载库
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/start.sh"

# 确保 npm 全局命令在 PATH 中
export PATH="$PATH:$HOME/.local/bin:$(npm config get prefix 2>/dev/null)/bin"

# 等待 setup.sh 完成（首次创建时可能还在安装）
SETUP_MARKER="$HOME/.freecloudcode.setup.done"
if [ ! -f "$SETUP_MARKER" ]; then
    log_warn "等待 setup.sh 完成安装..."
    for i in $(seq 1 60); do
        [ -f "$SETUP_MARKER" ] && break
        sleep 5
    done
    if [ ! -f "$SETUP_MARKER" ]; then
        log_error "setup.sh 超时（5分钟），跳过服务启动"
        echo "请在新终端运行: bash .devcontainer/setup.sh"
        exit 0
    fi
fi

# 运行服务启动流程
run_start

echo "✅ 服务启动完成"
