---
description: Audit the provenance, permissions, and supply-chain risk of a browser extension. Supports Firefox (AMO/XPI) and Chrome (Chrome Web Store/CRX). Use when asked to audit, review, or check the security of a browser addon or extension.
allowed-tools:
  - Bash
  - WebSearch
argument-hint: "<addon-url-or-id-or-github-repo> [--no-download]"
---

# Browser Addon Provenance & Supply-Chain Audit

Audit the browser extension identified by `$ARGUMENTS`. The argument may be:
- A Chrome Web Store URL (e.g. `https://chromewebstore.google.com/detail/lock-tab/nhbdiieigbgalknjplfpgmjnpbnkchnb`)
- A Chrome extension ID — 32 lowercase letters (e.g. `nhbdiieigbgalknjplfpgmjnpbnkchnb`)
- A Firefox AMO addon slug (e.g. `auto-tab-groups`)
- A Firefox AMO URL (e.g. `https://addons.mozilla.org/en-US/firefox/addon/auto-tab-groups/`)
- A GitHub repo URL or `owner/repo` (e.g. `gabrielmaldi/chrome-lock-tab`)

Pass `--no-download` to skip the binary download/hash step (read-only checks only).

---

## Step 0 — Normalise inputs and detect browser

Determine the target browser and canonical identifier:

```python
# Chrome indicators:
#   - chromewebstore.google.com URL
#   - chrome.google.com/webstore URL
#   - 32-character all-lowercase identifier (e.g. nhbdiieigbgalknjplfpgmjnpbnkchnb)
# Firefox indicators:
#   - addons.mozilla.org URL → extract slug after /addon/
#   - Short human-readable slug without numbers (e.g. auto-tab-groups)
# GitHub repo → check the homepage field for a CWS or AMO URL to detect the browser:
#   gh api repos/<owner>/<repo> --jq '.homepage'
```

Set `BROWSER` to `chrome` or `firefox`. Set `SLUG` (Firefox) or `EXTENSION_ID` (Chrome) for subsequent steps.

If a GitHub repo was given and the homepage is ambiguous, check the `manifest.json` for
`browser_specific_settings.gecko.id` (Firefox) or `update_url` containing `clients2.google.com` (Chrome).

---

## Step 1 — Store listing check

### Firefox (AMO API — public)

```bash
curl -s "https://addons.mozilla.org/api/v5/addons/addon/${SLUG}/" \
  | python3 -c '
import sys, json
d = json.load(sys.stdin)
cv = d["current_version"]
f = cv["file"]
print(json.dumps({
  "name": d.get("name", {}).get("en-US"),
  "guid": d["guid"],
  "status": d["status"],
  "daily_users": d.get("average_daily_users"),
  "weekly_downloads": d.get("weekly_downloads"),
  "created": d.get("created"),
  "last_updated": d.get("last_updated"),
  "authors": [{"name": a.get("name"), "username": a.get("username")} for a in d.get("authors", [])],
  "current_version": {
    "version": cv["version"],
    "file_id": f["id"],
    "reviewed": cv.get("reviewed"),
    "hash": f.get("hash"),
    "size": f.get("size"),
    "is_mozilla_signed": f.get("is_mozilla_signed_extension"),
    "status": f.get("status"),
    "permissions": f.get("permissions", []),
    "optional_permissions": f.get("optional_permissions", []),
    "host_permissions": f.get("host_permissions", []),
    "download_url": f.get("url"),
  }
}, indent=2))'
```

Record: GUID, current version + file hash (AMO's canonical SHA-256), permissions, Mozilla-signed status, author username.

### Chrome (CWS listing page — no public API)

```bash
curl -sL "https://chromewebstore.google.com/detail/${EXTENSION_ID}" \
  | python3 -c "
import sys, re
content = sys.stdin.read()
for label, pattern in [
  ('Version',  r'Version</div><div[^>]*>([0-9.]+)'),
  ('Users',    r'([\d,]+)\s*users?'),
  ('Updated',  r'Updated</div><div[^>]*>([^<]+)'),
  ('Rating',   r'(\d\.\d)\s*out of 5'),
]:
    m = re.search(pattern, content, re.IGNORECASE)
    print(label + ':', m.group(1) if m else 'NOT FOUND')
"
```

Record: published version, user count, last updated date. Note that CWS provides no public
per-file hash and no machine-readable version history API.

---

## Step 2 — Version history / permission drift

### Firefox

```bash
curl -s "https://addons.mozilla.org/api/v5/addons/addon/${SLUG}/versions/?page_size=10" \
  | python3 -c '
import sys, json
d = json.load(sys.stdin)
print("Total versions:", d.get("count"))
for v in d.get("results", []):
    f = v.get("file", {})
    print(v["version"], "|", v.get("reviewed"), "|", f.get("permissions"))
'
```

A sudden new permission across versions is the primary supply-chain escalation signal.

### Chrome

CWS has no public version history API. Check the GitHub commit history as a proxy:

```bash
gh api repos/<owner>/<repo>/commits --jq '.[0:20] | .[] | [.sha[0:8], .commit.author.date, .commit.message] | @tsv'
```

Look for commit messages referencing new permissions or manifest changes. Check
`git log --follow -p manifest.json` equivalents via the API:

```bash
gh api repos/<owner>/<repo>/commits --jq '.[].sha' | while read SHA; do
  gh api "repos/<owner>/<repo>/commits/${SHA}" --jq \
    '.files[] | select(.filename | contains("manifest")) | {sha: .sha[0:8], patch: .patch}'
done 2>/dev/null | head -100
```

---

## Step 3 — GitHub repo check

```bash
# Repo metadata
gh api repos/<owner>/<repo> --jq '{stars:.stargazers_count, default_branch, pushed_at, archived, fork, license:.license.name}'

# Releases and tags (no releases = no build provenance)
gh api repos/<owner>/<repo>/releases --jq 'length'
gh api repos/<owner>/<repo>/tags --jq 'length'

# CI/CD workflows (no workflows = manual upload)
gh api repos/<owner>/<repo>/actions/workflows --jq '.total_count, (.workflows[]? | .path)'

# GitHub Deployments
gh api "repos/<owner>/<repo>/deployments?environment=Production&per_page=3" \
  --jq '.[] | {creator: .creator.login, ref, task}'
```

**Flag:** If "Production" deployment creator is `vercel[bot]` or `netlify[bot]`, it is a docs site, not the extension binary.

**Flag:** 0 releases + 0 tags + no CI = build is local/manual, chain is opaque below store review.

---

## Step 4 — Source permission cross-reference

If the repo has a static `manifest.json`:

```bash
gh api "search/code?q=repo:<owner>/<repo>+filename:manifest.json" --jq '.items[].path'
gh api repos/<owner>/<repo>/contents/<path> --jq '.content' | base64 -d | python3 -m json.tool
```

If the repo has a `wxt.config.ts` (WXT-based extension), the manifest is generated at build time:

```bash
gh api repos/<owner>/<repo>/contents/wxt.config.ts \
  --jq '.content' | base64 -d | grep -A 20 'permissions'
```

Cross-reference source permissions with the store's declared permissions. Discrepancy = red flag.

---

## Step 5 — Download and inspect the binary (skip with `--no-download`)

### Firefox (XPI)

```bash
mkdir -p /tmp/addon-audit-${SLUG}
cd /tmp/addon-audit-${SLUG}

DOWNLOAD_URL=$(curl -s "https://addons.mozilla.org/api/v5/addons/addon/${SLUG}/" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["current_version"]["file"]["url"])')
VERSION=$(curl -s "https://addons.mozilla.org/api/v5/addons/addon/${SLUG}/" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["current_version"]["version"])')

curl -fL -o "${SLUG}-${VERSION}.xpi" "$DOWNLOAD_URL"
```

#### 5a-FF — Hash verification

```bash
EXPECTED=$(curl -s "https://addons.mozilla.org/api/v5/addons/addon/${SLUG}/" \
  | python3 -c 'import sys,json; h=json.load(sys.stdin)["current_version"]["file"]["hash"]; print(h.split(":")[-1])')
ACTUAL=$(shasum -a 256 "${SLUG}-${VERSION}.xpi" | awk '{print $1}')
[ "$ACTUAL" = "$EXPECTED" ] && echo "✅ HASH MATCH" || echo "❌ HASH MISMATCH — STOP"
```

If hashes differ, **stop and report** — the served binary does not match AMO's record.

#### 5b-FF — Extract and inspect

```bash
mkdir -p extracted
unzip -q "${SLUG}-${VERSION}.xpi" -d extracted/
python3 -m json.tool extracted/manifest.json
```

Verify: `permissions` matches AMO record and source; `browser_specific_settings.gecko.id` matches GUID.

#### 5c-FF — Mozilla signing verification

```bash
ls extracted/META-INF/
# Expect: cose.sig, cose.manifest, manifest.mf, mozilla.rsa, mozilla.sf
openssl pkcs7 -inform DER -in extracted/META-INF/mozilla.rsa -print_certs -noout \
  | grep -E 'subject|issuer|notAfter'
# issuer should contain "Mozilla AMO Production Signing Service"
```

---

### Chrome (CRX3)

```bash
mkdir -p /tmp/addon-audit-${EXTENSION_ID}
cd /tmp/addon-audit-${EXTENSION_ID}

# Download CRX from the CWS update endpoint
curl -sL "https://clients2.google.com/service/update2/crx?response=redirect&acceptformat=crx3&prodversion=131&x=id%3D${EXTENSION_ID}%26installsource%3Dondemand%26uc" \
  -o "${EXTENSION_ID}.crx"

file "${EXTENSION_ID}.crx"   # should say "Google Chrome extension, version 3"
ls -lh "${EXTENSION_ID}.crx"
```

#### 5a-CR — Extract ZIP from CRX3

CRX3 format: 4-byte magic (`Cr24`) + 4-byte version + 4-byte protobuf header length + header + ZIP.

```bash
python3 -c "
import struct
data = open('${EXTENSION_ID}.crx', 'rb').read()
magic   = data[:4]
version = struct.unpack('<I', data[4:8])[0]
hdr_sz  = struct.unpack('<I', data[8:12])[0]
zip_offset = 12 + hdr_sz
zip_data   = data[zip_offset:]
print(f'Magic: {magic}  CRX version: {version}  Header: {hdr_sz} bytes  ZIP: {len(zip_data)} bytes')
with open('${EXTENSION_ID}.zip', 'wb') as f:
    f.write(zip_data)
"
mkdir -p extracted
unzip -q "${EXTENSION_ID}.zip" -d extracted/
ls extracted/
```

#### 5b-CR — Inspect manifest and verified_contents

```bash
python3 -m json.tool extracted/manifest.json
```

Check `extracted/_metadata/verified_contents.json` (Google's per-file hash + signing payload):

```bash
python3 -c "
import json, base64
vc = json.load(open('extracted/_metadata/verified_contents.json'))
payload_b64 = vc[0]['signed_content']['payload']
payload = json.loads(base64.b64decode(payload_b64 + '==').decode())
print('item_id:     ', payload['item_id'])
print('item_version:', payload['item_version'])
print('Signers:     ', [s['header']['kid'] for s in vc[0]['signed_content']['signatures']])
print()
print('Per-file hashes (tree-SHA256):')
for f in payload['content_hashes'][0]['files']:
    print(f'  {f[\"path\"]}: {f[\"root_hash\"]}')
"
```

Verify:
- `item_id` matches the extension ID in the CWS URL
- `item_version` matches the published version and GitHub source
- Signatures include both `"publisher"` and `"webstore"` kid entries (Google dual-signing)

**Note:** Unlike Firefox, there is no independently verifiable SHA-256 hash published by Google.
The chain of trust is: Chrome trusts Google's JWS signature → Google ran the review.

#### 5c-CR — Permissions comparison

```bash
python3 -c "
import json
crx = json.load(open('extracted/manifest.json'))
print('CRX permissions:')
for p in crx.get('permissions', []): print(' ', p)
print('CRX host_permissions:')
for p in crx.get('host_permissions', []): print(' ', p)
print('CRX content_scripts matches:')
for cs in crx.get('content_scripts', []):
    print(' ', cs.get('matches'))
"
```

Cross-reference against the GitHub source manifest. Note that CWS automatically injects `update_url` — that is expected and not a red flag.

---

## Step 6 — JS red-flag scan

Run against all background scripts and content scripts from `extracted/`:

```bash
# Find all JS files in the extension
JS_FILES=$(find extracted/ -name "*.js" -not -path "*/node_modules/*")

echo "=== eval / new Function ==="
grep -rn 'eval(\|new Function' $JS_FILES | grep -v '//' | head -20

echo "=== fetch() targets ==="
python3 -c "
import re, glob
for f in glob.glob('extracted/**/*.js', recursive=True):
    content = open(f).read()
    for m in re.finditer(r'fetch\(', content):
        start = max(0, m.start()-200); end = min(len(content), m.end()+300)
        print(f'--- {f} offset {m.start()} ---'); print(content[start:end]); print()
"

echo "=== external URLs ==="
grep -ohE 'https?://[a-zA-Z0-9._/-]+' $JS_FILES \
  | sort -u | grep -v 'chrome-extension\|moz-extension\|localhost\|clients2.google' | head -20

echo "=== base64 blobs ==="
grep -oE '[A-Za-z0-9+/]{100,}={0,2}' $JS_FILES | head -5

echo "=== dynamic import() ==="
grep -n 'import(' $JS_FILES | head -10

echo "=== XMLHttpRequest / WebSocket ==="
grep -n 'XMLHttpRequest\|WebSocket\|open.*GET.*http' $JS_FILES | head -10
```

Flag anything that makes outbound network calls to non-extension origins.

---

## Step 7 — Produce the audit report

Output a structured report with these sections:

### Chain of Custody
Describe the full path: source → build → store upload → review → signing → distribution.
Explicitly state what is **opaque** (unattested) vs **verifiable**.

### Binary Verification
Table of: hash/signing check, manifest match, signing chain details, permissions match, red flags found.

### Permission Risk Assessment
For each permission, state what it grants and worst-case capability.
Rate overall blast radius: LOW / MODERATE / HIGH.

**Key thresholds (apply to both browsers):**
- `tabs` alone: can exfiltrate browsing history via background fetch — **MODERATE**
- `tabs` + any host permission: can correlate tab content — **HIGH**
- `tabs` + `webRequest` + host: full MITM capability — **CRITICAL**
- `scripting` + `<all_urls>`: can inject arbitrary code into any page — **CRITICAL**
- `content_scripts: <all_urls>`: broad DOM access on every page — **MODERATE** baseline, escalates if JS is compromised

### Supply-Chain Risk
Identify the most likely compromise paths. Rate: LOW / MODERATE / HIGH.
Key factors: store account security, build attestation (CI/CD vs manual), dependency chain (postinstall hooks), user base size.

### Mitigations

**Firefox:**
1. **Freeze auto-updates:** `about:addons` → extension → **Automatic Updates: Off**
2. Monitor AMO versions API for permission escalations
3. Re-audit before each manual update

**Chrome:**
1. **Freeze auto-updates:** Chrome does not expose per-extension auto-update control. Options:
   - Use managed device policy: `ExtensionAutoUpdateEnabled = false` (enterprise only)
   - Keep Chrome offline or use `chrome://extensions` to note the version and watch for prompt on re-connect
2. Subscribe to GitHub repo / watch `manifest.json` commits for permission changes
3. Chrome will show a permission prompt if a CWS update requests **new** permissions — watch for and reject unexpected prompts
4. Re-audit manually before confirming any permission-escalating update

**Both browsers:**
- Trade-off: frozen extensions don't receive security fixes — pair with monitoring

---

## Cleanup (optional)

```bash
rm -rf /tmp/addon-audit-${SLUG:-${EXTENSION_ID}}
```

---

## Key Red Flags (stop and escalate if found)

### Firefox
- Hash mismatch between downloaded XPI and AMO record
- Missing `META-INF/mozilla.rsa` (not Mozilla-signed)
- Signing issuer is not `Mozilla AMO Production Signing Service`
- Permissions in extracted manifest differ from AMO API declaration

### Chrome
- `file` command shows CRX is not CRX version 3 (or can't be extracted)
- `_metadata/verified_contents.json` missing (unreviewed sideload)
- `item_id` in signing payload does not match the extension ID
- `item_version` in signing payload does not match the CWS listing or GitHub source
- Signatures list does not include `"webstore"` kid (not properly signed by Google)
- Permissions in extracted manifest differ from GitHub source (beyond expected `update_url`)

### Both browsers
- `eval()` or `new Function(data)` in background scripts
- `fetch()` to hardcoded external URLs in background script
- `XMLHttpRequest` or `WebSocket` connections to external origins
- Large base64 blobs in JS (potential encoded payload)
- `postinstall` scripts in `package.json` (build-time code execution)
- Version history / commit history shows a sudden new sensitive permission
  (`<all_urls>`, `cookies`, `scripting`, `webRequest`, `nativeMessaging`)
- Deployment creator is `vercel[bot]` / `netlify[bot]` (website deploy, not extension)
