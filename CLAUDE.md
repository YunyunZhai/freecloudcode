# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is FreeCloudCode?

A GitHub Codespace devcontainer that pre-installs cloud AI development tools (Claude Code, OpenAI Codex, OpenCode, OmniRoute, Orca Server, Tailscale) so they're ready the moment a Codespace opens. CloudCLI, CCPocket, cc-connect and claude-sync are optional and NOT installed by default.

## Architecture

The project is a devcontainer-only setup — no application code, just the environment:

- **`.devcontainer/devcontainer.json`** — Codespace definition. Uses host-mode (no Docker), installs GitHub CLI and Node LTS via devcontainer features. Uses two lifecycle hooks:
  - `onCreateCommand` → `setup.sh` (first-time install only)
  - `postStartCommand` → `start.sh` (every startup)
- **`.devcontainer/setup.sh`** — One-time setup (runs on first Codespace creation). Installs system deps, Tailscale, Claude Code, npm tools, and writes aliases + service management functions to `~/.bashrc`.
- **`.devcontainer/start.sh`** — Every-boot startup (runs on every restart). Starts `tailscaled`, connects Tailscale network, launches OmniRoute (daemon mode)。Orca Server 需手动启动 (`sorca`)。CloudCLI / CCPocket / cc-connect / claude-sync 默认不安装（可选）。

### Why Two Scripts?

The original monolithic `startservice.sh` mixed installation (slow, one-time) with service startup (fast, every boot). Splitting them means:
- **First creation**: `setup.sh` runs via `onCreateCommand` (async, doesn't block VS Code opening)
- **Every restart**: `start.sh` runs via `postStartCommand` (fast, only starts services)
- VS Code opens immediately without waiting for npm installs

### Service Management

Written to `~/.bashrc` by `setup.sh` — available in every terminal:

| Command | Action |
|---------|--------|
| `sor` — start OmniRoute | `xor` — stop |
| `sorca` — start Orca Server | `xorca` — stop |
| `saa` — start AA-Server | `xaa` — stop |
| `saac` — start AA-Connector | `xaac` — stop |
| `fcc` — show service status | |

> CloudCLI (`scc`/`xcc`)、CCPocket Bridge (`sbp`/`xbp`) 与 cc-connect (`sccn`/`xccn`) 默认不安装，对应函数已在 `.devcontainer/bootstrap.sh` 中注释，需要时手动启用。

### Installed Aliases (in ~/.bashrc)

```
cc → claude
codex → codex
oc → opencode
or → omniroute
cr → reconnect Claude session
fcc → show service status
```

> `ccli → cloudcli` 与 `pocket → ccpocket-bridge` 别名仅在手动安装对应工具后、取消 `.devcontainer/bootstrap.sh` 中注释时生效。

## Common Tasks

- **Edit which tools get installed** — update the `NPM_PACKAGES` array in `lib/utils.sh`
- **Add a new bash alias** — add to the `.bashrc` block in `setup.sh`
- **Add a new auto-started service** — add a `tmux_start` call in `start.sh`
- **Change the devcontainer base** — edit `devcontainer.json`

## Key Details

- `.gitignore` excludes `.claude/` — Claude Code's per-project settings are never committed
- Node LTS is provided by the devcontainer `node` feature; no `.nvmrc` or `.node-version` file
- No tests, no build step — this is a pure devcontainer config repo
- Tailscale uses kernel TUN device for direct connection (host-mode Codespace supports it)
