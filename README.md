# ~/agent.md

Personal Claude Code config. Contains personal workflow rules and skills that don't belong
in the shared team repo. Works as a template — clone it, run the install script, then make
it yours.

## Structure

```
~/agent.md/
  AGENTS.md                  # Personal instructions — injected into every Claude session via
                             # SessionStart hook. Also symlinked to ~/AGENTS.md for cross-tool
                             # compatibility (Cursor, Codex, etc.).
  skills/                    # Personal plugin skills, available as /personal:<skill>
    browser-addon-audit/     # /personal:browser-addon-audit — Firefox/Chrome extension supply-chain audit
    new-skill/               # /personal:new-skill — scaffold a new personal skill
  .claude-plugin/            # Plugin + marketplace manifests (agent-md marketplace, personal plugin)
  bin/
    install.sh               # One-time bootstrap — run once per machine
    sync.sh                  # SessionStart hook — runs every Claude Code session
```

## Prerequisites

- `git`
- `claude` — [Claude Code CLI](https://claude.ai/download)
- `jq` — `brew install jq`

## Setup (per machine)

```bash
git clone <repo-url> ~/agent.md   # must be ~/agent.md — scripts use this fixed path
bash ~/agent.md/bin/install.sh
```

Restart Claude Code or start a new session to activate. What `install.sh` does:

1. `git init` (idempotent — no-op if already a repo)
2. Registers the `agent-md` marketplace and installs the `personal` plugin
3. Symlinks `~/AGENTS.md → ~/agent.md/AGENTS.md`
4. Adds the `sync.sh` SessionStart hook to `~/.claude/settings.json` (idempotent)

## Make it yours

After setup, personalize in place:

- **Rules**: edit `~/agent.md/AGENTS.md` — changes take effect on the next session start.
- **Skills**: run `/personal:new-skill <name>` to scaffold; remove `browser-addon-audit/` if you
  don't need it.
- **Identity** (optional): set `author.name`/`author.email` in `.claude-plugin/plugin.json` and
  `owner` in `.claude-plugin/marketplace.json` — cosmetic only, not required.
- **Remote**: see *Cross-machine sync* below.

## Adding a skill

```
/personal:new-skill <name> ["description"]
```

Or manually: create `~/agent.md/skills/<name>/SKILL.md`, commit, and start a new session.

## Cross-machine sync (optional)

The repo is local-only by default. To enable `git pull` on every session start:

```bash
git -C ~/agent.md remote add origin <your-private-github-repo>
git -C ~/agent.md push -u origin main
```

Once a remote exists, `bin/sync.sh` auto-pulls on each session (when the tree is clean).
On a new machine: clone to `~/agent.md`, then run `install.sh`.

## How it sits beside the team config

Both the team hook (`claude-get-global-context.sh`) and this repo's `sync.sh` hook register
as `SessionStart` entries in `~/.claude/settings.json`. The team's daily sync merges shared
settings using `jq -s '.[0] * .[1]'` — shared config is the base, **local wins**, and arrays
(including `SessionStart`) replace entirely. That means your local `settings.json` hooks
array is preserved on every team sync.

**Ordering**: run `install.sh` after the team's initial setup so the team hook is already in
`settings.json` first; `install.sh` appends `sync.sh` after it. Both hooks run each session.

Skills are namespaced (`/personal:*` vs `/sdlc-tools:*` etc.) — no collisions with team plugins.

If you're not using the team config, the hook in `settings.json` works standalone.

## Uninstall

```bash
claude plugin uninstall personal@agent-md
claude plugin marketplace remove agent-md
# Remove the sync.sh entry from ~/.claude/settings.json (edit hooks.SessionStart array)
rm ~/AGENTS.md          # removes the symlink only, not the source file
```
