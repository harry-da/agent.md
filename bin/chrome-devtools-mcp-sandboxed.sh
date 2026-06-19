#!/bin/bash
set -e

# Resolve the real node binary and prefix. Bypasses asdf/shim indirection so
# sandbox policies can whitelist the actual install path.
REAL_NODE=$("$(command -v node)" -e 'console.log(process.execPath)')
NODE_BIN=$(dirname "$REAL_NODE")
NODE_PREFIX=$(dirname "$NODE_BIN")

# Resolve the real pnpm script. asdf installs pnpm as a Node.js script at a
# versioned path; `asdf which pnpm` gives the real path without going through
# the shim, so the sandbox can whitelist it for reads.
REAL_PNPM=$(asdf which pnpm 2>/dev/null || command -v pnpm)
PNPM_HOME="${HOME}/Library/pnpm"
PNPM_STORE=$("$REAL_NODE" "$REAL_PNPM" store path 2>/dev/null || echo "${PNPM_HOME}/store/v10")

# Fake HOME: node's os.homedir() and config loaders read $HOME first on POSIX.
# Redirecting it via `env` inside the sandbox (NOT in srt's parent env — that
# breaks srt settings lookup) stops every read/write under /Users/harry at the
# source, so the sandbox doesn't need /Users/harry whitelisted beyond the pnpm
# store and home.
FAKE_HOME=$(mktemp -d -t cdm-home.XXXXXX)
CONFIG=$(mktemp -t cdm-srt.XXXXXX.json)
trap 'rm -f "$CONFIG"; rm -rf "$FAKE_HOME"' EXIT

# allowRead: node install prefix (libs, bins), pnpm store (package content-
# addressable store, includes the unpacked chrome-devtools-mcp package files
# loaded at startup), pnpm home (global metadata), and the fake HOME.
# allowWrite: /private/tmp (real path; /tmp is a symlink), /tmp, pnpm store
# (pnpm dlx writes here when fetching), pnpm home, fake HOME.
# network: localhost only — MCP talks to Chrome's DevTools WS at 127.0.0.1:9222.
cat > "$CONFIG" <<EOF
{
  "network": {"allowedDomains": ["localhost", "127.0.0.1"], "deniedDomains": []},
  "filesystem": {
    "denyRead": ["/Users"],
    "allowRead": ["$NODE_PREFIX", "$PNPM_STORE", "$PNPM_HOME", "$FAKE_HOME"],
    "allowWrite": ["/private/tmp", "/tmp", "$PNPM_STORE", "$PNPM_HOME", "$FAKE_HOME"],
    "denyWrite": []
  }
}
EOF

cd /tmp
# Pass HOME/PNPM_HOME/CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS via `env` as the
# first arg inside the sandbox — they apply to the child node process only, not
# to srt itself.
# CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1 disables the telemetry watchdog
# subprocess that POSTs to play.googleapis.com and writes
# ~/Library/Application Support/chrome-devtools-mcp/telemetry_state.json.
exec srt -s "$CONFIG" -- env \
  "HOME=$FAKE_HOME" \
  "PNPM_HOME=$PNPM_HOME" \
  CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1 \
  "$REAL_NODE" "$REAL_PNPM" dlx --prefer-offline chrome-devtools-mcp@0.21.0 \
  --browser-url http://127.0.0.1:9222
