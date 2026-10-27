#!/bin/bash
# lib/install.sh — FreeCloudCode 安装函数

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# 安装系统依赖
install_system_deps() {
    if ! sudo apt-get update -qq 2>/dev/null; then
        log_warn "apt-get update 失败"
        return 1
    fi

    if sudo apt-get install -y -qq tmux curl wget jq xvfb >/dev/null 2>&1; then
        log_success "系统依赖已就绪"
        return 0
    else
        log_warn "系统依赖安装失败"
        return 1
    fi
}

# 安装 Tailscale
install_tailscale() {
    if check_command tailscale; then
        log_success "Tailscale 已存在 ($(tailscale version | head -1))"
        return 0
    fi

    if curl -fsSL https://tailscale.com/install.sh | sh 2>/dev/null; then
        log_success "Tailscale 已安装"
        return 0
    else
        log_warn "Tailscale 安装失败"
        return 1
    fi
}

# 认证 Tailscale
auth_tailscale() {
    if ! check_command tailscale; then
        log_warn "Tailscale 未安装，跳过认证"
        return 1
    fi

    # 确保 tailscaled 守护进程已启动
    tailscale_ensure_daemon

    # 已认证
    if sudo tailscale status >/dev/null 2>&1; then
        log_success "Tailscale 已认证连接"
        return 0
    fi

    # 尝试 authkey
    if tailscale_auth; then
        log_success "Tailscale 认证成功"
        return 0
    fi

    log_warn "Tailscale 未认证（需手动运行: sudo tailscale up --ssh）"
    return 1
}

# 安装 Claude Code
install_claude() {
    if check_command claude; then
        log_success "Claude Code 已存在"
        return 0
    fi

    if curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null; then
        log_success "Claude Code 已安装"
        return 0
    else
        log_warn "Claude Code 安装失败"
        return 1
    fi
}

# 安装 OpenCode CLI
install_opencode() {
    local local_bin="$HOME/.local/bin"

    if check_command opencode; then
        # 旧容器可能只装在 ~/.opencode/bin（默认 PATH 不含该目录），补建软链到 ~/.local/bin
        if [ ! -e "$local_bin/opencode" ]; then
            ensure_dir "$local_bin"
            ln -sf "$HOME/.opencode/bin/opencode" "$local_bin/opencode"
        fi
        log_success "OpenCode CLI 已存在"
        return 0
    fi

    if curl -fsSL https://opencode.ai/install | bash 2>/dev/null; then
        # 立即更新 PATH，确保后续 check_command 能找到
        export PATH="$HOME/.opencode/bin:$PATH"
        # opencode 装在非标准目录 ~/.opencode/bin，软链到默认 PATH 已含的 ~/.local/bin，
        # 避免"claude 能用但 opencode 找不到"（任何未加载 FCC 块的 shell 都受影响）
        ensure_dir "$local_bin"
        ln -sf "$HOME/.opencode/bin/opencode" "$local_bin/opencode"
        log_success "OpenCode CLI 已安装"
        return 0
    else
        log_warn "OpenCode CLI 安装失败"
        return 1
    fi
}

# 安装 Orca Server（headless，github.com/stablyai/orca）
# 官方无 npm 包 / 容器镜像，服务端安装 Linux 原生包 orca-ide（.deb，命令名为 orca-ide）
install_orca() {
    if check_command orca-ide; then
        log_success "Orca Server 已存在（orca-ide）"
        return 0
    fi

    local arch_suffix="amd64"
    case "$(uname -m)" in
        aarch64|arm64) arch_suffix="arm64" ;;
    esac

    # 通过 GitHub API 获取最新 release 中对应架构的 .deb 资产地址
    local release_json asset_url
    release_json=$(curl -fsSL --retry 3 https://api.github.com/repos/stablyai/orca/releases/latest 2>/dev/null)
    asset_url=$(echo "$release_json" | jq -r --arg suffix "_${arch_suffix}.deb" \
        '.assets[] | select(.name | endswith($suffix)) | .browser_download_url' | head -1)

    if [ -z "$asset_url" ]; then
        log_warn "Orca Server 安装失败（未找到 ${arch_suffix} 的 .deb 资产）"
        return 1
    fi

    local orca_home="$HOME/.orca"
    ensure_dir "$orca_home"
    local deb_file="$orca_home/orca-ide.deb"

    if curl -fL --retry 3 -o "$deb_file" "$asset_url" 2>/dev/null; then
        if ! sudo dpkg -i "$deb_file" >/dev/null 2>&1; then
            # 依赖缺失时用 apt -f 修复后重试
            sudo apt-get install -y -qq -f >/dev/null 2>&1
            sudo dpkg -i "$deb_file" >/dev/null 2>&1
        fi
        rm -f "$deb_file"
        if check_command orca-ide; then
            log_success "Orca Server 已安装（orca-ide）"
            return 0
        fi
    fi
    rm -f "$deb_file"
    log_warn "Orca Server 安装失败"
    return 1
}

# 安装 npm 全局工具
install_npm_packages() {
    local failed=0

    for pkg in "${NPM_PACKAGES[@]}"; do
        local pkg_name="${pkg%%:*}"
        local bin_name
        bin_name=$(npm_bin_name "$pkg")

        if check_command "$bin_name" 2>/dev/null; then
            log_success "$pkg_name 已存在"
        elif npm install -g "$pkg_name" >/dev/null 2>&1; then
            log_success "$pkg_name 已安装"
        elif sudo npm install -g "$pkg_name" >/dev/null 2>&1; then
            # 普通用户全局前缀不可写时（空白容器常见）用 sudo 重试
            log_success "$pkg_name 已安装（sudo）"
        else
            log_warn "$pkg_name 安装失败"
            failed=1
        fi
    done

    return $failed
}

# 确保 OmniRoute 管理密码不是默认 CHANGEME（新容器首次 serve 前写入强密码）
# 注意：OmniRoute 只在"无已保存 hash"时迁移 INITIAL_PASSWORD；已运行过的容器请用 omni_passwd 重置
setup_omniroute_env() {
    local env_file="$HOME/.omniroute/.env"
    if [ ! -f "$env_file" ]; then
        log_warn "OmniRoute .env 不存在（首次 serve 后自动创建），可稍后运行 omni_passwd 设置强密码"
        return 0
    fi
    if grep -q '^INITIAL_PASSWORD=' "$env_file"; then
        log_success "OmniRoute 管理密码已配置（.env 含 INITIAL_PASSWORD）"
        return 0
    fi
    local pwd
    pwd=$(tr -dc 'A-HJ-NP-Za-km-z2-9' < /dev/urandom | head -c 24)
    if [ -z "$pwd" ]; then
        log_warn "OmniRoute 密码生成失败"
        return 1
    fi
    printf '\nINITIAL_PASSWORD=%s\n' "$pwd" >> "$env_file"
    chmod 600 "$env_file"
    log_info "OmniRoute 管理密码已生成并写入 ~/.omniroute/.env: $pwd"
    log_warn "请保存该密码；dashboard 登录用（或之后运行 omni_passwd 重置）"
}

# 安装 Node.js（空白容器可能没有 node/npm；npm 工具需要 Node 18+）
install_node() {
    if check_command node && check_command npm; then
        local major
        major=$(node -v 2>/dev/null | sed 's/^v//; s/\..*//')
        if [ "${major:-0}" -ge 18 ]; then
            log_success "Node.js 已存在 ($(node -v))"
            return 0
        fi
        log_warn "Node.js 版本过低 ($(node -v))，尝试升级"
    fi

    if sudo apt-get install -y -qq nodejs npm >/dev/null 2>&1; then
        major=$(node -v 2>/dev/null | sed 's/^v//; s/\..*//')
        if [ "${major:-0}" -ge 18 ]; then
            log_success "Node.js 已安装 ($(node -v))"
            return 0
        fi
    fi

    # apt 版本过旧时使用 NodeSource LTS（支持 amd64/arm64）
    if curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1; then
        sudo apt-get install -y -qq nodejs >/dev/null 2>&1
        if check_command node; then
            log_success "Node.js 22 已安装 ($(node -v))"
            return 0
        fi
    fi

    log_warn "Node.js 安装失败"
    return 1
}

# 创建目录结构
create_directories() {
    ensure_dir "$HOME/.freecloudcode/logs"
    ensure_dir "$HOME/.freecloudcode/config"

    # 初始化日志文件
    for logfile in tailscale omniroute orca; do
        touch "$HOME/.freecloudcode/logs/${logfile}.log"
        chmod 644 "$HOME/.freecloudcode/logs/${logfile}.log"
    done

    log_success "目录结构已创建"
}

# 主安装流程
run_setup() {
    local log_file="$LOG_DIR/setup.log"
    local fail_count_file="$LOG_DIR/.fail_count"
    ensure_dir "$LOG_DIR"

    echo "0" > "$fail_count_file"

    # 输出同时显示在终端和写入日志文件
    {
        install_system_deps || { echo $(( $(cat "$fail_count_file") + 1 )) > "$fail_count_file"; }
        install_node || { echo $(( $(cat "$fail_count_file") + 1 )) > "$fail_count_file"; }
        install_tailscale || { echo $(( $(cat "$fail_count_file") + 1 )) > "$fail_count_file"; }
        auth_tailscale || { echo $(( $(cat "$fail_count_file") + 1 )) > "$fail_count_file"; }
        install_claude || { echo $(( $(cat "$fail_count_file") + 1 )) > "$fail_count_file"; }
        install_opencode || { echo $(( $(cat "$fail_count_file") + 1 )) > "$fail_count_file"; }
        install_orca || { echo $(( $(cat "$fail_count_file") + 1 )) > "$fail_count_file"; }
        install_npm_packages || { echo $(( $(cat "$fail_count_file") + 1 )) > "$fail_count_file"; }
        setup_omniroute_env
        create_directories

        configure_claude_code_hooks
    } 2>&1 | tee "$log_file"

    cat "$fail_count_file"
}

# 配置 Claude Code hooks（SessionStart + Stop + SessionEnd hook）
configure_claude_code_hooks() {
    local settings="$HOME/.claude/settings.json"
    ensure_dir "$HOME/.claude"

    # claude-sync 默认不安装，未安装时跳过 hook 配置（hook 依赖 claude-sync）
    if ! check_command claude-sync; then
        log_warn "claude-sync 未安装，跳过 Claude Code hooks 配置"
        return 0
    fi

    if [ -f "$settings" ]; then
        if ! jq -e '.hooks.SessionStart' "$settings" >/dev/null 2>&1; then
            # 没有 SessionStart hook，追加（同时添加 Stop hook）
            jq '.hooks += {
                    "SessionStart": [{"hooks": [{"type": "command", "command": "claude-sync pull", "timeout": 30, "statusMessage": "🔄 同步云端配置..."}]}],
                    "Stop": [{"hooks": [{"type": "command", "command": "claude-sync push -q", "timeout": 30, "statusMessage": "📤 推送本地配置..."}]}],
                    "SessionEnd": [{"hooks": [{"type": "command", "command": "claude-sync push -q", "timeout": 30, "statusMessage": "📤 推送本地配置..."}]}]
                  }' \
               "$settings" > "${settings}.tmp" && mv "${settings}.tmp" "$settings"
            log_success "Claude Code hooks 已配置（SessionStart + Stop + SessionEnd）"
        fi
    else
        cat > "$settings" << EOF
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "claude-sync pull",
            "timeout": 30,
            "statusMessage": "🔄 同步云端配置..."
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "claude-sync push -q",
            "timeout": 30,
            "statusMessage": "📤 推送本地配置..."
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "claude-sync push -q",
            "timeout": 30,
            "statusMessage": "📤 推送本地配置..."
          }
        ]
      }
    ]
  }
}
EOF
        log_success "Claude Code hooks 已配置（SessionStart + Stop + SessionEnd）"
    fi
}

# 写入 shell 配置（别名 / 服务管理函数 / 提示）到 ~/.bashrc 与 ~/.profile
# 会先移除旧版 FreeCloudCode 块（含历史遗留的 ccli/pocket/scc/sccn/sbp 等），保证干净
write_shell_config() {
    local bashrc="$HOME/.bashrc"
    local profile="$HOME/.profile"
    local block_marker="# >>> FreeCloudCode >>>"

    if grep -q "$block_marker" "$bashrc" 2>/dev/null; then
        sed -i '/^# >>> FreeCloudCode >>>$/,/^# <<< FreeCloudCode <<<$/d' "$bashrc"
    fi

    cat >> "$bashrc" << 'BASHRC_BLOCK'

# >>> FreeCloudCode >>>
_FCC_HOME="${FCC_HOME:-$HOME/freecloudcode}"

# 服务启动（每次打开终端只执行一次）
if [ -z "$_FCC_STARTUP_DONE" ]; then
    export _FCC_STARTUP_DONE=1
    if [ -f "$_FCC_HOME/start.sh" ]; then
        bash "$_FCC_HOME/start.sh"
    fi
fi

# ===== 别名 =====
alias cc='claude'
alias codex='codex'
alias oc='opencode'
alias or='omniroute'
alias cr='CLAUDE_CODE_ENTRYPOINT=sdk-cli claude -r'
alias fcc='bash -c "source ~/freecloudcode/lib/utils.sh; source ~/freecloudcode/lib/status.sh; show_status"'

# 服务管理函数依赖 utils.sh 中的 tmux_start/tmux_stop
source "$_FCC_HOME/lib/utils.sh"

# ===== 服务管理 =====
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
sorca() {
    if ! check_command orca-ide; then echo "⚠ orca-ide 未安装"; return 1; fi
    if is_service_running orca "orca-ide serve"; then echo "⚠ Orca Server 已在运行"; return 0; fi
    local ts_ip; ts_ip=$(tailscale_ip)
    local addr="${ts_ip:-localhost}"
    local runner="orca-ide"
    [ -z "$DISPLAY" ] && runner="xvfb-run --auto-servernum $runner"
    tmux_start orca "LIBGL_ALWAYS_SOFTWARE=1 $runner serve --port 6768 --pairing-address $addr" ~/.freecloudcode/logs/orca.log && echo "✓ Orca Server 已启动 (http://${addr}:6768)"
}
xorca() { tmux_stop orca "orca-ide serve"; echo "✓ Orca Server 已停止"; }

# ===== 状态提示（仅交互式终端，只显示一次） =====
if [[ $- == *i* ]] && [ -z "$_FCC_HINTS_PRINTED" ]; then
    export _FCC_HINTS_PRINTED=1
    echo "📌 cc(claude) codex oc(opencode) or(omniroute) orca-ide(Orca) cr(重连) fcc(状态)"
    echo "   sor/xor(OmniRoute) sorca/xorca(Orca Server) omni_passwd(重置OmniRoute密码)"
fi

# <<< FreeCloudCode <<<
BASHRC_BLOCK

    # .profile（login shell，如 SSH 首次登录）
    local profile_marker="# >>> FreeCloudCode >>>"
    if ! grep -q "$profile_marker" "$profile" 2>/dev/null; then
        cat >> "$profile" << 'PROFILE_BLOCK'

# >>> FreeCloudCode >>>
# Login shell（SSH 等）需手动 source .bashrc
# 只在 .bashrc 尚未加载时才 source，避免默认 .profile 已 source 导致的重复
if [ -f "$HOME/.bashrc" ] && [ -z "$_FCC_HOME" ]; then
    . "$HOME/.bashrc"
fi
# <<< FreeCloudCode <<<
PROFILE_BLOCK
    fi

    # zsh 支持：zsh 不读 ~/.bashrc，检测到 ~/.zshrc 时写入相同的配置块
    if [ -f "$HOME/.zshrc" ]; then
        local zshrc="$HOME/.zshrc"
        if grep -q "# >>> FreeCloudCode (zsh) >>>" "$zshrc" 2>/dev/null; then
            sed -i '/^# >>> FreeCloudCode (zsh) >>>$/,/^# <<< FreeCloudCode (zsh) <<<$/d' "$zshrc"
        fi
        cat >> "$zshrc" << 'ZSHRC_BLOCK'

# >>> FreeCloudCode (zsh) >>>
# zsh 不读 ~/.bashrc，此块为 FreeCloudCode 的 zsh 配置（与 bashrc 块一致）
export PATH="$PATH:$HOME/.local/bin:$HOME/.opencode/bin:$(npm config get prefix 2>/dev/null)/bin"
_FCC_HOME="${FCC_HOME:-$HOME/freecloudcode}"
[ -f "$_FCC_HOME/start.sh" ] && bash "$_FCC_HOME/start.sh" &
source "$_FCC_HOME/lib/utils.sh"
alias cc='claude'
alias codex='codex'
alias oc='opencode'
alias or='omniroute'
alias cr='CLAUDE_CODE_ENTRYPOINT=sdk-cli claude -r'
alias fcc='bash -c "source ~/freecloudcode/lib/utils.sh; source ~/freecloudcode/lib/status.sh; show_status"'
sor() {
    if omniroute doctor --no-liveness >/dev/null 2>&1; then echo "⚠ OmniRoute 已在运行"; return; fi
    omniroute serve --daemon > ~/.freecloudcode/logs/omniroute.log 2>&1
    sleep 3
    if omniroute doctor --no-liveness >/dev/null 2>&1; then echo "✓ OmniRoute 已启动"; else echo "⚠ OmniRoute 启动失败"; fi
}
xor() {
    if omniroute stop 2>/dev/null; then echo "✓ OmniRoute 已停止"; return; fi
    local pidfile="$HOME/.omniroute/omniroute.pid"
    if [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null; then echo "✓ OmniRoute 已停止"; rm -f "$pidfile"; return; fi
    echo "⚠ OmniRoute 未运行"
}
sorca() {
    if ! check_command orca-ide; then echo "⚠ orca-ide 未安装"; return 1; fi
    if is_service_running orca "orca-ide serve"; then echo "⚠ Orca Server 已在运行"; return 0; fi
    local ts_ip; ts_ip=$(tailscale_ip)
    local addr="${ts_ip:-localhost}"
    local runner="orca-ide"
    [ -z "$DISPLAY" ] && runner="xvfb-run --auto-servernum $runner"
    tmux_start orca "LIBGL_ALWAYS_SOFTWARE=1 $runner serve --port 6768 --pairing-address $addr" ~/.freecloudcode/logs/orca.log && echo "✓ Orca Server 已启动 (http://${addr}:6768)"
}
xorca() { tmux_stop orca "orca-ide serve"; echo "✓ Orca Server 已停止"; }
echo "📌 cc(claude) codex oc(opencode) or(omniroute) orca-ide(Orca) cr(重连) fcc(状态)"
echo "   sor/xor(OmniRoute) sorca/xorca(Orca Server) omni_passwd(重置OmniRoute密码)"
# <<< FreeCloudCode (zsh) >>>
ZSHRC_BLOCK
        log_success "Shell 配置已写入 ~/.zshrc（zsh）"
    fi

    log_success "Shell 配置已写入 ~/.bashrc（别名 + 服务管理函数）"
}
