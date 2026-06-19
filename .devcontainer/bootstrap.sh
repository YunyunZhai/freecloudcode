#!/bin/bash
# bootstrap.sh — 仅写入 .bashrc 触发块，不执行任何安装
# 由 devcontainer.json 的 onCreateCommand 调用（首次创建，后台运行）
# 设计：极小、极快，不阻塞 VS Code 打开

BASHRC="$HOME/.bashrc"
MARKER="# >>> FreeCloudCode >>>"

# 已有则跳过
if grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
    exit 0
fi

cat >> "$BASHRC" << 'BASHRC_BLOCK'

# >>> FreeCloudCode >>>
if [ -z "$_FCC_LOADED" ]; then
export _FCC_LOADED=1

# 项目路径
_FCC_HOME="${HOME}/freecloudcode"

# 首次安装（仅当 marker 不存在时）
if [ ! -f "$HOME/.freecloudcode.setup.done" ]; then
    if [ -f "$_FCC_HOME/.devcontainer/setup.sh" ]; then
        echo "🚀 FreeCloudCode 首次安装..."
        bash "$_FCC_HOME/.devcontainer/setup.sh"
    fi
fi

# 启动服务（每次打开终端）
if [ -f "$_FCC_HOME/lib/start.sh" ]; then
    bash "$_FCC_HOME/lib/start.sh"
fi

# 命令别名
alias cc='claude'
alias codex='codex'
alias oc='omniroute'
alias ccli='cloudcli'
alias pocket='ccpocket-bridge'
alias cr='CLAUDE_CODE_ENTRYPOINT=sdk-cli claude -r'

# 服务管理函数
scc()  { tmux new-session -d -s cloudcli "cloudcli 2>&1 | tee ~/.freecloudcode/logs/cloudcli.log; sleep infinity" && echo "✓ CloudCLI 已启动"; }
xcc()  { tmux kill-session -t cloudcli 2>/dev/null; pkill -f cloudcli 2>/dev/null; echo "✓ CloudCLI 已停止"; }
sbp()  { tmux new-session -d -s bridge "ccpocket-bridge 2>&1 | tee ~/.freecloudcode/logs/bridge.log; sleep infinity" && echo "✓ Bridge 已启动"; }
xbp()  { tmux kill-session -t bridge 2>/dev/null; pkill -f "ccpocket-bridge" 2>/dev/null; echo "✓ Bridge 已停止"; }
xor()  {
    if omniroute stop 2>/dev/null; then echo "✓ OmniRoute 已停止"; return; fi
    local pidfile="$HOME/.omniroute/omniroute.pid"
    if [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null; then
        echo "✓ OmniRoute 已停止"; rm -f "$pidfile"; return
    fi
    echo "⚠ OmniRoute 未运行"
}

# 命令速查
if [[ $- == *i* ]]; then
    echo "📌 cc(claude) codex oc(omniroute) ccli(cloudcli) pocket(bridge) cr(重连)"
    echo "   scc/xcc(CloudCLI) sbp/xbp(Bridge) xor(OmniRoute)"
fi

fi  # _FCC_LOADED guard
# <<< FreeCloudCode <<<
BASHRC_BLOCK
