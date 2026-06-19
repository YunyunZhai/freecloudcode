#!/bin/bash
# bootstrap.sh — 写入 .bashrc/.profile 触发块
# 由 devcontainer.json 的 onCreateCommand 调用（首次创建，后台运行）

BASHRC="$HOME/.bashrc"
PROFILE="$HOME/.profile"
MARKER="# >>> FreeCloudCode >>>"

# 已有则跳过
if grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
    exit 0
fi

# ===== 创建 ~/freecloudcode → /workspaces/freecloudcode 符号链接 =====
WORKSPACE="/workspaces/freecloudcode"
LINK="$HOME/freecloudcode"
if [ -d "$WORKSPACE" ] && [ ! -e "$LINK" ]; then
    ln -s "$WORKSPACE" "$LINK"
fi

# ===== 写入 .bashrc =====
cat >> "$BASHRC" << 'BASHRC_BLOCK'

# >>> FreeCloudCode >>>
_FCC_HOME="${FCC_HOME:-$HOME/freecloudcode}"

# 首次安装（仅当 marker 不存在时）— 每次都检查，但幂等执行
if [ ! -f "$HOME/.freecloudcode.setup.done" ]; then
    if [ -f "$_FCC_HOME/.devcontainer/setup.sh" ]; then
        echo "🚀 FreeCloudCode 首次安装..."
        bash "$_FCC_HOME/.devcontainer/setup.sh"
    fi
fi

# 启动服务（每次打开终端只执行一次）
if [ -z "$_FCC_STARTUP_DONE" ]; then
    export _FCC_STARTUP_DONE=1
    if [ -f "$_FCC_HOME/.devcontainer/start.sh" ]; then
        bash "$_FCC_HOME/.devcontainer/start.sh"
    fi
fi

# ===== 别名 =====
alias cc='claude'
alias codex='codex'
alias oc='omniroute'
alias ccli='cloudcli'
alias pocket='ccpocket-bridge'
alias cr='CLAUDE_CODE_ENTRYPOINT=sdk-cli claude -r'
alias fcc='bash -c "source ~/freecloudcode/lib/utils.sh; source ~/freecloudcode/lib/status.sh; show_status"'

# ===== 服务管理 =====
scc() { tmux_start cloudcli cloudcli ~/.freecloudcode/logs/cloudcli.log && echo "✓ CloudCLI 已启动"; }
xcc() { tmux_stop cloudcli cloudcli; echo "✓ CloudCLI 已停止"; }
sbp() { tmux_start bridge ccpocket-bridge ~/.freecloudcode/logs/bridge.log && echo "✓ Bridge 已启动"; }
xbp() { tmux_stop bridge ccpocket-bridge; echo "✓ Bridge 已停止"; }
xor() {
    if omniroute stop 2>/dev/null; then echo "✓ OmniRoute 已停止"; return; fi
    local pidfile="$HOME/.omniroute/omniroute.pid"
    if [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null; then
        echo "✓ OmniRoute 已停止"; rm -f "$pidfile"; return
    fi
    echo "⚠ OmniRoute 未运行"
}

# ===== 状态提示（仅交互式终端） =====
if [[ $- == *i* ]]; then
    echo "📌 cc(claude) codex oc(omniroute) ccli(cloudcli) pocket(bridge) cr(重连) fcc(状态)"
    echo "   scc/xcc(CloudCLI) sbp/xbp(Bridge) xor(OmniRoute)"
fi

# <<< FreeCloudCode <<<
BASHRC_BLOCK

# ===== 写入 .profile（login shell，如 SSH） =====
PROFILE_MARKER="# >>> FreeCloudCode >>>"
if ! grep -q "$PROFILE_MARKER" "$PROFILE" 2>/dev/null; then
    cat >> "$PROFILE" << 'PROFILE_BLOCK'

# >>> FreeCloudCode >>>
# Login shell（SSH 等）需手动 source .bashrc
if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
# <<< FreeCloudCode <<<
PROFILE_BLOCK
fi
