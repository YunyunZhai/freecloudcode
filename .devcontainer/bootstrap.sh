#!/bin/bash
# bootstrap.sh — 写入 .bashrc/.profile 触发块
# 由 devcontainer.json 的 onCreateCommand 调用（首次创建，后台运行）

BASHRC="$HOME/.bashrc"
PROFILE="$HOME/.profile"
MARKER="# >>> FreeCloudCode >>>"

# 已有则检查是否需要升级（旧版可能缺少新函数或有拼写错误）
NEED_REWRITE=0
if grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
    # 修复：旧版 son/xor → sor/xor，cc-conect → cc-connect
    if grep -q 'son/xor\|cc-conect' "$BASHRC" 2>/dev/null; then
        sed -i 's/son\/xor/sor\/xor/g; s/cc-conect/cc-connect/g' "$BASHRC"
    fi
    # 升级：替换整个 FreeCloudCode block（旧版缺少 saa/xaa 等函数）
    if ! grep -q 'sor()' "$BASHRC" 2>/dev/null; then
        sed -i '/^# >>> FreeCloudCode >>>$/,/^# <<< FreeCloudCode <<<$/d' "$BASHRC"
        NEED_REWRITE=1
    fi
    # 无升级需求则退出
    [ "$NEED_REWRITE" -eq 0 ] && exit 0
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

# 首次安装（仅当 marker 不存在时）— 后台运行，按回车跳过等待
if [ ! -f "$HOME/.freecloudcode.setup.done" ]; then
    if [ -f "$_FCC_HOME/.devcontainer/setup.sh" ]; then
        echo "🚀 FreeCloudCode 首次安装中（后台运行）..."
        bash "$_FCC_HOME/.devcontainer/setup.sh" &
        _FCC_SETUP_PID=$!
        echo "   安装 PID: $_FCC_SETUP_PID"
        echo "   按回车直接进入终端，安装继续在后台运行"
        echo "   查看进度: tail -f ~/.freecloudcode/logs/setup.log"
        read -t 10 -r _ 2>/dev/null || true
    fi
fi

# 启动服务（每次打开终端只执行一次）
if [ -z "$_FCC_STARTUP_DONE" ]; then
    export _FCC_STARTUP_DONE=1
    if [ -f "$_FCC_HOME/.devcontainer/start.sh" ]; then
        # 等待 setup.sh 完成（后台），最多等 5 秒
        if [ -n "$_FCC_SETUP_PID" ]; then
            for i in $(seq 1 5); do
                kill -0 "$_FCC_SETUP_PID" 2>/dev/null || break
                sleep 1
            done
        fi
        bash "$_FCC_HOME/.devcontainer/start.sh"
    fi
fi

# ===== 别名 =====
alias cc='claude'
alias codex='codex'
alias oc='opencode'
alias or='omniroute'
alias ccli='cloudcli'
alias pocket='ccpocket-bridge'
alias cr='CLAUDE_CODE_ENTRYPOINT=sdk-cli claude -r'
alias fcc='bash -c "source ~/freecloudcode/lib/utils.sh; source ~/freecloudcode/lib/status.sh; show_status"'

# 服务管理函数依赖 utils.sh 中的 tmux_start/tmux_stop
source "$_FCC_HOME/lib/utils.sh"

# ===== 服务管理 =====
scc() { tmux_start cloudcli cloudcli ~/.freecloudcode/logs/cloudcli.log && echo "✓ CloudCLI 已启动"; }
xcc() { tmux_stop cloudcli cloudcli; echo "✓ CloudCLI 已停止"; }
sccn() { tmux_start cc-connect cc-connect ~/.cc-connect/logs/cc-connect.log && echo "✓ cc-connect 已启动"; }
xccn() { tmux_stop cc-connect cc-connect; echo "✓ cc-connect 已停止"; }
sbp() { tmux_start bridge ccpocket-bridge ~/.freecloudcode/logs/bridge.log && echo "✓ Bridge 已启动"; }
xbp() { tmux_stop bridge ccpocket-bridge; echo "✓ Bridge 已停止"; }
saa() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^agents-anywhere-server$'; then echo "⚠ Agents-Anywhere Server 已在运行"; return; fi
    docker rm -f agents-anywhere-server >/dev/null 2>&1
    docker run -d --name agents-anywhere-server -p 5174:8000 -v agents-anywhere-data:/data -e AGENT_SERVER_SECRET=liuxu-1989 agents-anywhere-server:latest >/dev/null 2>&1
    sleep 3
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^agents-anywhere-server$'; then echo "✓ Agents-Anywhere Server 已启动"; else echo "⚠ 启动失败"; fi
}
xaa() { docker stop agents-anywhere-server >/dev/null 2>&1 && echo "✓ Agents-Anywhere Server 已停止" || echo "⚠ 未运行"; }
saac() { tmux_start agents-anywhere-connector "cd '$HOME/Agents-Anywhere/connector' && bash start-cli.sh" ~/.agents-anywhere/logs/connector.log && echo "✓ Agents-Anywhere Connector 已启动"; }
xaac() { tmux_stop agents-anywhere-connector agents-anywhere-connector; echo "✓ Agents-Anywhere Connector 已停止"; }
sor() {
    if omniroute doctor --no-liveness >/dev/null 2>&1; then echo "⚠ OmniRoute 已在运行"; return; fi
    omniroute serve --daemon > ~/.freecloudcode/logs/omniroute.log 2>&1
    sleep 3
    if omniroute doctor --no-liveness >/dev/null 2>&1; then echo "✓ OmniRoute 已启动"; else echo "⚠ OmniRoute 启动失败，日志: ~/.freecloudcode/logs/omniroute.log"; fi
}
xor() {
    if omniroute stop 2>/dev/null; then echo "✓ OmniRoute 已停止"; return; fi
    local pidfile="$HOME/.omniroute/omniroute.pid"
    if [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null; then
        echo "✓ OmniRoute 已停止"; rm -f "$pidfile"; return
    fi
    echo "⚠ OmniRoute 未运行"
}

# ===== 状态提示（仅交互式终端，只显示一次） =====
if [[ $- == *i* ]] && [ -z "$_FCC_HINTS_PRINTED" ]; then
    export _FCC_HINTS_PRINTED=1
    echo "📌 cc(claude) codex oc(opencode) or(omniroute) ccli(cloudcli) pocket(bridge) cr(重连) fcc(状态)"
    echo "   scc/xcc(CloudCLI) sbp/xbp(Bridge) sor/xor(OmniRoute) sccn/xccn(cc-connect)"
    echo "   saa/xaa(AA-Server) saac/xaac(AA-Connector)"
fi

# <<< FreeCloudCode <<<
BASHRC_BLOCK

# ===== 写入 .profile（login shell，如 SSH） =====
PROFILE_MARKER="# >>> FreeCloudCode >>>"
if ! grep -q "$PROFILE_MARKER" "$PROFILE" 2>/dev/null; then
    cat >> "$PROFILE" << 'PROFILE_BLOCK'

# >>> FreeCloudCode >>>
# Login shell（SSH 等）需手动 source .bashrc
# 只在 .bashrc 尚未加载时才 source，避免默认 .profile 已 source 导致的重复
if [ -f "$HOME/.bashrc" ] && [ -z "$_FCC_HOME" ]; then
    . "$HOME/.bashrc"
fi
# <<< FreeCloudCode <<<
PROFILE_BLOCK
fi
