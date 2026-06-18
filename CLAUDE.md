# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is FreeCloudCode?

A GitHub Codespace devcontainer that pre-installs cloud AI development tools (Claude Code, OpenAI Codex, OmniRoute, CloudCLI, Tailscale, CCPocket) so they're ready the moment a Codespace opens.

## Architecture

The project is a devcontainer-only setup — no application code, just the environment:

- **`.devcontainer/devcontainer.json`** — Codespace definition. Uses host-mode (no Docker), installs GitHub CLI and Node LTS via devcontainer features. Runs `startservice.sh` as the `postCreateCommand`.
- **`.devcontainer/startservice.sh`** — Startup script (sourced on every open). Idempotent: checks are guarded by a `_START_SERVICES_LOADED` flag and `command -v` / `pgrep` pre-checks. Steps:
  1. Install system deps (`tmux`, `curl`, `wget`, `jq`)
  2. Install Tailscale (via official script)
  3. Install Claude Code binary (standalone from GCS, fallback to npm)
  4. Install npm global tools (`omniroute`, `@cloudcli-ai/cloudcli`, `@openai/codex`, `@ccpocket/bridge`)
  5. Write bash aliases to `~/.bashrc`
  6. Start `tailscaled` (userspace-networking mode)
  7. Auto-start OmniRoute and CloudCLI in tmux sessions

### Service Management Pattern

The script defines a `_tmux_run` helper and exposes shell functions:

| Command | Action |
|---------|--------|
| `cc` — start CloudCLI | `xcc` — stop |
| `cp` — start Bridge | `xcp` — stop |
| `cr` — reconnect Claude session | — |

These are sourced into the Codespace shell on every startup but are **not** persisted to `~/.bashrc` — they're available only in the startup shell context. After startup, use the aliases written to `.bashrc` (see below).

### Installed Aliases (in ~/.bashrc)

```
cc → claude
codex → openai-codex
oc → omniroute
ccli → cloudcli
pocket → ccpocket-bridge
```

## Common Tasks

- **Edit which tools get installed** — update the `NPM_PACKAGES` array and the Claude Code install block in `startservice.sh`
- **Add a new bash alias** — add to the `.bashrc` section in `startservice.sh`
- **Add a new auto-started service** — call `_tmux_run` at the end of `startservice.sh`
- **Change the devcontainer base** — edit `devcontainer.json` (currently no `image` field — uses the default Codespace image)

## Key Details

- `.gitignore` excludes `.claude/` — so Claude Code's own per-project settings are never committed
- Node LTS is provided by the devcontainer `node` feature; no `.nvmrc` or `.node-version` file
- No tests, no build step — this is a pure devcontainer config repo
- The script uses `--tun=userspace-networking` for Tailscale to avoid kernel module requirements in Codespaces
