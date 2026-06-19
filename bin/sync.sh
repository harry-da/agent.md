#!/usr/bin/env bash
# Personal Claude Code SessionStart hook
# - Pulls the repo if a remote exists and tree is clean (no-op for local-only)
# - Injects AGENTS.md as additionalContext so personal workflow rules are always live
#
# ALL operational output goes to stderr. stdout is reserved exclusively for the
# JSON additionalContext payload consumed by Claude Code.

set -euo pipefail

REPO_DIR="${HOME}/agent.md"

# Defensive: exit cleanly if the repo is somehow missing
if [ ! -d "$REPO_DIR" ]; then
    exit 0
fi

# Pull if a remote is configured and the working tree is clean
# No-op while the repo is local-only; activates automatically once a remote is added.
if git -C "$REPO_DIR" remote 2>/dev/null | grep -q .; then
    if [ -z "$(git -C "$REPO_DIR" status --porcelain 2>/dev/null)" ]; then
        git -C "$REPO_DIR" pull --quiet 2>/dev/null || true
    fi
fi

# Inject AGENTS.md as session context
AGENTS_FILE="${REPO_DIR}/AGENTS.md"
if [ ! -f "$AGENTS_FILE" ]; then
    exit 0
fi

# Escape content for embedding in a JSON string value
escape_for_json() {
    local s="$1"
    s="${s//\\/\\\\}"      # backslash first (must be first)
    s="${s//\"/\\\"}"      # double-quote
    s="${s//$'\n'/\\n}"    # newline
    s="${s//$'\r'/\\r}"    # carriage return
    s="${s//$'\t'/\\t}"    # tab
    printf '%s' "$s"
}

CONTENT=$(cat "$AGENTS_FILE")
ESCAPED=$(escape_for_json "$CONTENT")

printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$ESCAPED"

exit 0
