#!/bin/bash
# start.sh — FreeCloudCode 每次开机启动服务
# 由 ~/.bashrc 每次打开终端时调用

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

# 加载库
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/start.sh"

# 确保 npm 全局命令在 PATH 中
export PATH="$PATH:$HOME/.local/bin:$(npm config get prefix 2>/dev/null)/bin"

# 等待 setup.sh 完成（首次创建时可能还在安装）
if [ ! -f "$SETUP_MARKER" ]; then
    echo "⏳ 安装进行中，服务暂未启动" >&2
    echo "   查看进度: tail -f ~/.freecloudcode/logs/setup.log" >&2
    echo "   安装完成后运行: bash ~/freecloudcode/.devcontainer/start.sh" >&2
    exit 0
fi

# 运行服务启动流程
run_start

# 首次安装完成后显示配置提醒（只显示一次）
CONFIG_HINT_SHOWN="$HOME/.freecloudcode/.config-hint-shown"
if [ ! -f "$CONFIG_HINT_SHOWN" ]; then
    LOG_FILE="$HOME/.freecloudcode/logs/setup.log"
    if [ -f "$LOG_FILE" ]; then
        # 从日志中提取配置提醒部分（从 "🔧 配置提醒" 开始）
        HINT=$(awk '/^===========+$/{found=0} /🔧 配置提醒/{found=1} found' "$LOG_FILE")
        if [ -n "$HINT" ]; then
            echo "" >&2
            echo "$HINT" >&2
        fi
    fi
    touch "$CONFIG_HINT_SHOWN"
fi
