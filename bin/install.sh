#!/usr/bin/env bash
# One-time bootstrap for ~/agent.md personal Claude Code config.
# Safe to re-run — all steps are idempotent.

set -euo pipefail

REPO_DIR="${HOME}/agent.md"
SYNC_SCRIPT="${REPO_DIR}/bin/sync.sh"
SETTINGS_LOCAL="${HOME}/.claude/settings.json"

echo "==> Initialising git repo…"
git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 \
    && echo "    (already a git repo — skipping init)" \
    || git init "$REPO_DIR"

echo ""
echo "==> Making scripts executable…"
chmod +x "$SYNC_SCRIPT" "$REPO_DIR/bin/install.sh"

echo ""
echo "==> Registering personal plugin marketplace…"
if command -v claude >/dev/null 2>&1; then
    claude plugin marketplace add "$REPO_DIR" 2>/dev/null \
        && echo "    ✓ Marketplace agent-md registered" \
        || echo "    (already registered or add returned non-zero — continuing)"
else
    echo "    ⚠️  claude CLI not found — skipping marketplace registration"
    echo "       Run manually: claude plugin marketplace add ${REPO_DIR}"
fi

echo ""
echo "==> Installing personal plugin…"
if command -v claude >/dev/null 2>&1; then
    claude plugin install "personal@agent-md" --scope user 2>/dev/null \
        && echo "    ✓ Plugin personal@agent-md installed" \
        || echo "    (already installed or install returned non-zero — continuing)"
else
    echo "    ⚠️  claude CLI not found — skipping plugin install"
    echo "       Run manually: claude plugin install personal@agent-md --scope user"
fi

echo ""
echo "==> Symlinking ~/AGENTS.md → ${REPO_DIR}/AGENTS.md…"
if [ -e "${HOME}/AGENTS.md" ] && [ ! -L "${HOME}/AGENTS.md" ]; then
    echo "    Backing up existing ~/AGENTS.md to ~/AGENTS.md.bak"
    mv "${HOME}/AGENTS.md" "${HOME}/AGENTS.md.bak"
fi
ln -sf "${REPO_DIR}/AGENTS.md" "${HOME}/AGENTS.md"
echo "    ✓ ~/AGENTS.md → ${REPO_DIR}/AGENTS.md"

echo ""
echo "==> Wiring SessionStart hook in settings.json…"
if [ ! -f "$SETTINGS_LOCAL" ]; then
    printf '{}' > "$SETTINGS_LOCAL"
fi

# Idempotency check: skip if sync.sh is already in any SessionStart hook command
if command -v jq >/dev/null 2>&1; then
    if jq -e --arg cmd "$SYNC_SCRIPT" \
        '.hooks.SessionStart // [] | map(.hooks // [] | map(.command)) | flatten | any(. == $cmd)' \
        "$SETTINGS_LOCAL" >/dev/null 2>&1; then
        echo "    (hook already registered — skipping)"
    else
        jq --arg cmd "$SYNC_SCRIPT" \
            '.hooks.SessionStart = (.hooks.SessionStart // []) + [{"hooks": [{"type": "command", "command": $cmd}]}]' \
            "$SETTINGS_LOCAL" > "${SETTINGS_LOCAL}.tmp" \
        && mv "${SETTINGS_LOCAL}.tmp" "$SETTINGS_LOCAL"
        echo "    ✓ Hook registered: ${SYNC_SCRIPT}"
    fi
else
    echo "    ⚠️  jq not found — skipping hook registration"
    echo "       Add manually to ~/.claude/settings.local.json:"
    printf '       {"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"%s"}]}]}}\n' "$SYNC_SCRIPT"
fi

echo ""
echo "✅ Done."
echo ""
echo "   Restart Claude Code or start a new session to activate personal context."
echo "   Personal skills:"
echo "     /personal:browser-addon-audit  — audit Firefox/Chrome extension supply-chain"
echo "     /personal:new-skill            — scaffold a new personal skill"
echo ""
echo "   To add a remote for cross-machine sync:"
echo "     git -C ~/agent.md remote add origin <your-private-repo-url>"
echo "     git -C ~/agent.md push -u origin main"
