#!/bin/bash
# setup.sh — FreeCloudCode 一次性安装配置
# 由 ~/.bashrc 在首次打开终端时调用（非阻塞）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

# 加载库
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/install.sh"

SETUP_MARKER="$HOME/.freecloudcode.setup.done"

# 幂等检查
if [ -f "$SETUP_MARKER" ]; then
    exit 0
fi

# 确保目录存在
ensure_dir "$HOME/.freecloudcode/logs"

echo "========================================="
echo " FreeCloudCode — 初始安装配置"
echo "========================================="

# 运行安装流程
FAILED_COUNT=$(run_setup)

# 写入完成标记
touch "$SETUP_MARKER"

# 显示配置提醒
echo ""
echo "========================================="
echo " 🔧 配置提醒"
echo "========================================="

if check_command tailscale; then
    if sudo tailscale status >/dev/null 2>&1; then
        log_success "Tailscale — 已认证"
    else
        log_warn "Tailscale — 需要认证"
        echo "     方式1: 设置环境变量 TAILSCALEAUTHKEY 后重新创建容器"
        echo "     方式2: 在终端运行: sudo tailscale up --ssh"
    fi
fi

if check_command omniroute; then
    if [ -f "$HOME/.omniroute/config.yaml" ] || [ -f "$HOME/.omniroute/config.json" ]; then
        log_success "OmniRoute — 已配置"
    else
        log_warn "OmniRoute — 未配置（首次使用需运行: oc）"
    fi
fi

if check_command claude-sync; then
    if claude-sync status -q 2>/dev/null; then
        log_success "claude-sync — 已配置"
    else
        log_warn "claude-sync — 未配置"
        echo "     首次使用需运行: claude-sync init"
    fi
fi

echo ""
echo "========================================="
echo " 📋 安装检查"
echo "========================================="
for cmd in tailscale claude omniroute cloudcli codex ccpocket-bridge claude-sync; do
    if check_command "$cmd"; then
        echo "  ✅ $cmd"
    else
        echo "  ❌ $cmd  — 未找到"
    fi
done

echo ""
if [ "$FAILED_COUNT" -eq 0 ]; then
    echo "✅ 所有工具安装成功！"
else
    echo "⚠️  有 $FAILED_COUNT 个工具安装失败，请查看上方日志"
fi
