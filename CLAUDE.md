# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is FreeCloudCode?

A GitHub Codespace devcontainer that pre-installs cloud AI development tools (Claude Code, OpenAI Codex, OmniRoute, CloudCLI, Tailscale, CCPocket) so they're ready the moment a Codespace opens.

## Architecture

The project is a devcontainer-only setup — no application code, just the environment:

- **`.devcontainer/devcontainer.json`** — Codespace definition. Uses host-mode (no Docker), installs GitHub CLI and Node LTS via devcontainer features. Uses two lifecycle hooks:
  - `onCreateCommand` → `setup.sh` (first-time install only)
  - `postStartCommand` → `start.sh` (every startup)
- **`.devcontainer/setup.sh`** — One-time setup (runs on first Codespace creation). Installs system deps, Tailscale, Claude Code, npm tools, and writes aliases + service management functions to `~/.bashrc`.
- **`.devcontainer/start.sh`** — Every-boot startup (runs on every restart). Starts `tailscaled`, connects Tailscale network, launches OmniRoute (daemon mode) and CloudCLI (tmux session).

### Why Two Scripts?

The original monolithic `startservice.sh` mixed installation (slow, one-time) with service startup (fast, every boot). Splitting them means:
- **First creation**: `setup.sh` runs via `onCreateCommand` (async, doesn't block VS Code opening)
- **Every restart**: `start.sh` runs via `postStartCommand` (fast, only starts services)
- VS Code opens immediately without waiting for npm installs

### Service Management

Written to `~/.bashrc` by `setup.sh` — available in every terminal:

| Command | Action |
|---------|--------|
| `scc` — start CloudCLI | `xcc` — stop |
| `sbp` — start Bridge | `xbp` — stop |

### Installed Aliases (in ~/.bashrc)

```
cc → claude
codex → codex
oc → omniroute
ccli → cloudcli
pocket → ccpocket-bridge
cr → reconnect Claude session
```

## Common Tasks

- **Edit which tools get installed** — update the `NPM_PACKAGES` array in `setup.sh`
- **Add a new bash alias** — add to the `.bashrc` block in `setup.sh`
- **Add a new auto-started service** — add a `_tmux_run` call in `start.sh`
- **Change the devcontainer base** — edit `devcontainer.json`

## Key Details

- `.gitignore` excludes `.claude/` — Claude Code's per-project settings are never committed
- Node LTS is provided by the devcontainer `node` feature; no `.nvmrc` or `.node-version` file
- No tests, no build step — this is a pure devcontainer config repo
- Tailscale uses kernel TUN device for direct connection (host-mode Codespace supports it)
