# ~/agent.md

Personal Claude Code config. Contains personal workflow rules and skills that shouldn't live in the shared team repo.

## Structure

```
~/agent.md/
  AGENTS.md                  # Personal instructions — injected into every Claude session via SessionStart hook.
                             # Also symlinked to ~/AGENTS.md for cross-tool compatibility (Cursor, Codex, etc.).
  skills/                    # Personal plugin skills, available as /personal:<skill>
    browser-addon-audit/     # /personal:browser-addon-audit — Firefox/Chrome extension supply-chain audit
    new-skill/               # /personal:new-skill — scaffold a new personal skill
  .claude-plugin/            # Plugin + marketplace manifests (agent-md marketplace, personal plugin)
  bin/
    install.sh               # One-time bootstrap — run once per machine
    sync.sh                  # SessionStart hook — runs every Claude Code session
```

## Setup (per machine)

```bash
bash ~/agent.md/bin/install.sh
```

That's it. Restart Claude Code to activate. What it does:
1. `git init` (idempotent)
2. Registers the `agent-md` marketplace and installs the `personal` plugin
3. Symlinks `~/AGENTS.md → ~/agent.md/AGENTS.md`
4. Adds the `sync.sh` SessionStart hook to `~/.claude/settings.local.json` (idempotent)

## Adding a skill

```
/personal:new-skill <name> ["description"]
```

Or manually: create `~/agent.md/skills/<name>/SKILL.md`, commit, and start a new session.

## Editing personal workflow rules

Edit `~/agent.md/AGENTS.md`. The changes take effect on the next Claude Code session start.

## Cross-machine sync (optional)

The repo is local-only by default. To enable `git pull` on every session start:

```bash
git -C ~/agent.md remote add origin <your-private-github-repo>
git -C ~/agent.md push -u origin main
```

Once a remote exists, `bin/sync.sh` auto-pulls on each session (when the tree is clean).

## How it sits beside the team config

The team's `ai-global-context` hook runs first (wired in `settings.json`). This repo's `sync.sh`
runs additively via `settings.local.json` — the team's merge never touches `settings.local.json`.
Skills are namespaced (`/personal:*` vs `/sdlc-tools:*` etc.) so no collisions.
