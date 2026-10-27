# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is FreeCloudCode?

A manual install kit: run `bash install.sh` inside any blank container (OCI / WSL / Codespace) and it installs cloud AI development tools (Claude Code, OpenAI Codex, OpenCode, OmniRoute, Orca Server, Tailscale) and writes shell aliases + service-management functions. CloudCLI, CCPocket, cc-connect and claude-sync are optional and NOT installed by default.

## Architecture

No application code — just environment setup scripts:

- **`install.sh`** — Manual install entry (run after SSH: `bash install.sh`). Sources `lib/install.sh`, runs the install pipeline, writes shell config to `~/.bashrc`/`~/.profile` (aliases, service functions, hints), and shows an install check. Idempotent via `$SETUP_MARKER`.
- **`start.sh`** — Every-terminal service startup, called from the `~/.bashrc` block written by `install.sh`. Starts `tailscaled`, connects Tailscale, launches OmniRoute (daemon). Orca Server is started manually via `sorca`.
- **`.devcontainer/devcontainer.json`** — Optional minimal Codespace base container (GitHub CLI + Node LTS features). No lifecycle hooks, no auto-install scripts.
- **`lib/install.sh`** — Install functions: system deps, Node.js, Tailscale, Claude Code, OpenCode, Orca Server (`orca-ide` .deb), npm packages (OmniRoute, Codex), directories, Claude hooks (only if claude-sync installed), and `write_shell_config()`.
- **`lib/utils.sh`** — Shared helpers (logging, tmux service management, Tailscale, status queries, `NPM_PACKAGES` list).
- **`lib/start.sh` / `lib/status.sh`** — Service start + status functions.

### Service Management

Written to `~/.bashrc` by `install.sh` (`write_shell_config` in `lib/install.sh`) — available in every terminal:

| Command | Action |
|---------|--------|
| `sor` — start OmniRoute | `xor` — stop |
| `sorca` — start Orca Server | `xorca` — stop |
| `fcc` — show service status | |

> CloudCLI (`scc`/`xcc`)、CCPocket Bridge (`sbp`/`xbp`) 与 cc-connect (`sccn`/`xccn`) 默认不安装，未写入 shell 配置；需要时手动安装对应工具后自行添加函数。

### Installed Aliases (in ~/.bashrc)

```
cc → claude
codex → codex
oc → opencode
or → omniroute
cr → reconnect Claude session
fcc → show service status
```

> `ccli → cloudcli` 与 `pocket → ccpocket-bridge` 别名不随默认安装写入，需要时手动添加。

## Common Tasks

- **Edit which tools get installed** — update the `NPM_PACKAGES` array in `lib/utils.sh`
- **Add a new bash alias** — add to the `.bashrc` block in `write_shell_config()` (`lib/install.sh`)
- **Add a new auto-started service** — add a `tmux_start` call in `start.sh`
- **Change the devcontainer base** — edit `devcontainer.json`

## Key Details

- `.gitignore` excludes `.claude/` — Claude Code's per-project settings are never committed
- Node LTS is provided by the devcontainer `node` feature; no `.nvmrc` or `.node-version` file
- No tests, no build step — this is a pure devcontainer config repo
- Tailscale uses kernel TUN device for direct connection (host-mode Codespace supports it)
