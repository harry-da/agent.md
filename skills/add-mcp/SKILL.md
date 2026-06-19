---
description: Add an MCP server to Claude Code using a sandboxed wrapper script (srt). Creates a filesystem/network-restricted launcher that prevents the MCP process from reading your home directory or making arbitrary network connections. Use when asked to add an MCP, set up an MCP server, or configure a new tool securely.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
argument-hint: "<mcp-name> <package> [--browser-url <url>] [--allow-network]"
---

# add-mcp

Adds an MCP server to Claude Code with an `srt` sandbox wrapper. The sandbox:
- **Filesystem**: denies all reads under `/Users` except the pnpm store, pnpm home, node prefix, and a throwaway fake `HOME`. Denies all writes except `/tmp`, the pnpm store, and the fake `HOME`.
- **Network**: blocks all external connections by default; only `localhost`/`127.0.0.1` allowed unless `--allow-network` is passed.

## Prerequisites check

```bash
command -v srt >/dev/null 2>&1 || { echo "ERROR: srt not installed. Install via: brew install nicholasgasior/tap/srt or equivalent."; exit 1; }
command -v asdf >/dev/null 2>&1 || { echo "ERROR: asdf not found — required to resolve real pnpm path."; exit 1; }
```

If `srt` is missing, stop and tell the user to install it. Do not proceed without the sandboxing tool.

## Parse arguments

From `$ARGUMENTS`:
- `MCP_NAME` — first word (e.g. `chrome-devtools`, `filesystem`, `fetch`)
- `PACKAGE` — second word, npm/pnpm package name with optional version (e.g. `chrome-devtools-mcp@0.21.0`)
- `--browser-url <url>` — optional; extra arg to pass to the MCP process (for browser-connected MCPs)
- `--allow-network` — optional; if present, remove network restrictions from the sandbox config

If `PACKAGE` is omitted, use `MCP_NAME` as the package name (common convention where package name matches the tool name).

## Step 1 — Check if already configured

```bash
cat ~/.claude/settings.json | python3 -c "
import json, sys
s = json.load(sys.stdin)
servers = s.get('mcpServers', {})
if '<MCP_NAME>' in servers:
    print('already configured')
else:
    print('not configured')
"
```

If already configured, show the current config and ask the user if they want to replace it.

## Step 2 — Create the sandboxed wrapper script

Write the script to `~/agent.md/bin/<MCP_NAME>-mcp-sandboxed.sh`:

```bash
#!/bin/bash
set -e

# Resolve the real node binary and prefix. Bypasses asdf/shim indirection so
# sandbox policies can whitelist the actual install path.
REAL_NODE=$("$(command -v node)" -e 'console.log(process.execPath)')
NODE_BIN=$(dirname "$REAL_NODE")
NODE_PREFIX=$(dirname "$NODE_BIN")

# Resolve the real pnpm script (bypasses asdf shim).
REAL_PNPM=$(asdf which pnpm 2>/dev/null || command -v pnpm)
PNPM_HOME="${HOME}/Library/pnpm"
PNPM_STORE=$("$REAL_NODE" "$REAL_PNPM" store path 2>/dev/null || echo "${PNPM_HOME}/store/v10")

FAKE_HOME=$(mktemp -d -t <MCP_NAME>-home.XXXXXX)
CONFIG=$(mktemp -t <MCP_NAME>-srt.XXXXXX.json)
trap 'rm -f "$CONFIG"; rm -rf "$FAKE_HOME"' EXIT

cat > "$CONFIG" <<EOF
{
  "network": {"allowedDomains": [<NETWORK_DOMAINS>], "deniedDomains": []},
  "filesystem": {
    "denyRead": ["/Users"],
    "allowRead": ["$NODE_PREFIX", "$PNPM_STORE", "$PNPM_HOME", "$FAKE_HOME"],
    "allowWrite": ["/private/tmp", "/tmp", "$PNPM_STORE", "$PNPM_HOME", "$FAKE_HOME"],
    "denyWrite": []
  }
}
EOF

cd /tmp
exec srt -s "$CONFIG" -- env \
  "HOME=$FAKE_HOME" \
  "PNPM_HOME=$PNPM_HOME" \
  "$REAL_NODE" "$REAL_PNPM" dlx --prefer-offline <PACKAGE> <EXTRA_ARGS>
```

Substitutions:
- `<MCP_NAME>` → the mcp name (e.g. `chrome-devtools`)
- `<PACKAGE>` → the package arg (e.g. `chrome-devtools-mcp@0.21.0`)
- `<EXTRA_ARGS>` → `--browser-url <url>` if provided, else empty
- `<NETWORK_DOMAINS>` → `"localhost", "127.0.0.1"` for local-only; or add specific domains if `--allow-network` was passed (ask the user which domains to allow)

Make it executable:
```bash
chmod +x ~/agent.md/bin/<MCP_NAME>-mcp-sandboxed.sh
```

## Step 3 — Add to Claude Code settings

Read `~/.claude/settings.json`, add the MCP server entry, and write it back:

```python
import json, os

settings_path = os.path.expanduser("~/.claude/settings.json")
with open(settings_path) as f:
    settings = json.load(f)

settings.setdefault("mcpServers", {})["<MCP_NAME>"] = {
    "command": os.path.expanduser("~/agent.md/bin/<MCP_NAME>-mcp-sandboxed.sh"),
    "type": "stdio"
}

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
```

Run this as an inline Python one-liner via `python3 -c '...'` or write to a temp file and execute it.

## Step 4 — Wire install.sh

Append an install step to `~/agent.md/bin/install.sh` so the script is deployed on new machines. Add it before the final `echo "✅ Done."` block:

```bash
echo ""
echo "==> Installing <MCP_NAME> MCP sandboxed launcher…"
chmod +x "$REPO_DIR/bin/<MCP_NAME>-mcp-sandboxed.sh"
echo "    ✓ <MCP_NAME>-mcp-sandboxed.sh made executable"
```

Check whether the block already exists before appending (grep for the MCP name).

## Step 5 — Commit and confirm

```bash
cd ~/agent.md && git add bin/<MCP_NAME>-mcp-sandboxed.sh bin/install.sh && git commit -m "feat(mcp): add sandboxed <MCP_NAME> MCP launcher"
```

Then verify the MCP appears in Claude Code:

```bash
cat ~/.claude/settings.json | python3 -c "import json,sys; s=json.load(sys.stdin); print(json.dumps(s.get('mcpServers',{}), indent=2))"
```

Tell the user to restart Claude Code for the new MCP to be picked up.

---

**Security note:** The sandbox isolation relies on `srt`. Without it, the MCP process runs as your user and can read all your files and make arbitrary network requests. Always verify `srt` is installed and the sandbox config is correctly scoped before adding any third-party MCP package.
