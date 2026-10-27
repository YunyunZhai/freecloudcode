#!/bin/bash
# start.sh — FreeCloudCode 每次打开终端时启动服务
# 由 install.sh 写入的 ~/.bashrc 调用

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/utils.sh"
source "$LIB_DIR/start.sh"

# 确保 npm 全局命令在 PATH 中
export PATH="$PATH:$HOME/.local/bin:$(npm config get prefix 2>/dev/null)/bin:$HOME/.opencode/bin"

# 尚未安装时提示（手动安装模式下应已运行过 install.sh）
if [ ! -f "$SETUP_MARKER" ]; then
    echo "⏳ 尚未安装（缺少 $SETUP_MARKER），先运行: bash ~/freecloudcode/install.sh" >&2
    exit 0
fi

# 运行服务启动流程
run_start
