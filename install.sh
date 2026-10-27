#!/bin/bash
# install.sh — FreeCloudCode 手动安装入口
# 用法: 创建空白容器后 SSH 进入，将本仓库克隆到容器内，然后运行:
#   bash install.sh
# 自动安装默认工具集（Claude Code、OpenCode、Orca Server、OmniRoute、Codex、Tailscale 等）
# 并写入 shell 配置（别名、服务管理函数）。幂等，可重复运行。

# 注意：lib/*.sh 内部也定义了 SCRIPT_DIR（指向各自目录），source 后会覆盖本变量，
# 因此这里用唯一的 REPO_DIR，避免后续 ln -s 指向错误的 lib/ 目录
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$REPO_DIR/lib"

source "$LIB_DIR/utils.sh"
source "$LIB_DIR/install.sh"

# 确保 PATH 包含各工具目录
export PATH="$HOME/.opencode/bin:$PATH:$HOME/.local/bin:$(npm config get prefix 2>/dev/null)/bin"

# ===== 创建 ~/freecloudcode → 仓库目录 符号链接 =====
LINK="$HOME/freecloudcode"
if [ -d "$REPO_DIR" ] && [ ! -e "$LINK" ]; then
    ln -s "$REPO_DIR" "$LINK"
    echo "✓ 已创建链接 ~/freecloudcode -> $REPO_DIR"
fi

# ===== 幂等检查 =====
if [ -f "$SETUP_MARKER" ]; then
    echo "✅ 已完成过安装（标记: $SETUP_MARKER）"
    echo "   重新写入 shell 配置（清理历史遗留别名/函数）..."
    write_shell_config
    echo "完成。如需重装全部软件，先删除 $SETUP_MARKER 再运行本脚本。"
    exit 0
fi

# ===== 并发锁 =====
ensure_dir "$LOG_DIR"
LOCK_FILE="$LOG_DIR/setup.lock"
if [ -f "$LOCK_FILE" ]; then
    lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        echo "⏳ 安装进行中（PID $lock_pid），退出..." >&2
        exit 0
    fi
    rm -f "$LOCK_FILE"
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

echo "========================================="
echo " FreeCloudCode — 手动安装"
echo "=========================================" | tee -a "$LOG_DIR/setup.log"

FAILED_COUNT=$(run_setup)
FAILED_COUNT="${FAILED_COUNT:-0}"

touch "$SETUP_MARKER"

# ===== 写入 shell 配置 =====
write_shell_config

# ===== 安装检查与配置提醒 =====
{
echo ""
echo "========================================="
echo " 🔧 配置提醒"
echo "========================================="

# Tailscale
ts_ip=$(tailscale_ip)
result=$(query_tailscale)
IFS='|' read -r status _ hint <<< "$result"
display_status_line "$status" "Tailscale" "$hint"
if [ "$status" = "skip" ]; then
    echo "     认证: sudo tailscale up --ssh"
fi

# OmniRoute
result=$(query_omniroute "${ts_ip:-localhost}")
IFS='|' read -r status _ hint <<< "$result"
display_status_line "$status" "OmniRoute" "$hint"
if [ "$status" = "fail" ] || [ "$status" = "skip" ]; then
    echo "     运行: oc（首次使用需配置 API key）"
fi

# 安装检查
echo ""
echo "========================================="
echo " 📋 安装检查"
echo "========================================="
for cmd in tailscale claude opencode orca-ide; do
    if check_command "$cmd"; then
        display_status_line "ok" "$cmd" "✓"
    else
        display_status_line "fail" "$cmd" "未找到"
    fi
done
for pkg in "${NPM_PACKAGES[@]}"; do
    cmd=$(npm_bin_name "$pkg")
    if check_command "$cmd"; then
        display_status_line "ok" "$cmd" "✓"
    else
        display_status_line "fail" "$cmd" "未找到"
    fi
done

echo ""
if [ "${FAILED_COUNT:-0}" -eq 0 ]; then
    echo "✅ 所有工具安装成功！"
else
    echo "⚠️  有 $FAILED_COUNT 个工具安装失败，日志: $LOG_DIR/setup.log"
fi
echo "   常用命令: cc(claude) codex oc(opencode) or(omniroute) orca-ide(Orca) fcc(状态)"
echo "   服务管理: sor/xor(OmniRoute) sorca/xorca(Orca Server)"
} | tee -a "$LOG_DIR/setup.log"

echo ""
echo "✅ 安装完成。重新打开终端或运行: source ~/.bashrc"
