---
description: Audit the provenance, permissions, and supply-chain risk of a browser extension. Supports Firefox (AMO/XPI) and Chrome (Chrome Web Store/CRX). Use when asked to audit, review, or check the security of a browser addon or extension.
allowed-tools:
  - Bash
  - WebSearch
  - WebFetch
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

## Closed-source / no public repo

When no public GitHub repo exists (confirmed by web search returning nothing for `site:github.com <extension-name>`), **Steps 2–4 are N/A**. Document this explicitly:

- Chain of custody is **fully opaque** below the store upload: no build attestation, no SLSA provenance, no source-vs-binary cross-reference possible.
- State: `Source build → CWS/AMO upload → Store review → Signing → Distribution`. Everything left of the upload is unattested.
- The audit pivots entirely to binary + behavioural analysis (Steps 5–6).

Do **not** flag "0 releases + 0 tags" or "no CI" as findings — those checks are only meaningful when a repo exists.

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

**Also capture the Privacy Practices disclosure** — use WebFetch to retrieve and record
the CWS listing's "Privacy practices" / "Data usage" block verbatim. Note which data types
the developer declares collecting (e.g. "Web history", "Browsing history", "Personal info")
and the stated purpose/sharing commitments. This is privacy-relevant and not machine-readable
from the raw HTML.

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

### Work directory

Use the session scratchpad directory if one is specified in the system context (typically
`/private/tmp/claude-<uid>/.../scratchpad/`). Only fall back to `/tmp` if no scratchpad
is provided. Name the audit subdirectory `addon-audit-<id>`:

```bash
AUDIT_DIR="${SCRATCHPAD:-/tmp}/addon-audit-${SLUG:-${EXTENSION_ID}}"
mkdir -p "${AUDIT_DIR}"
cd "${AUDIT_DIR}"
```

### Firefox (XPI)

```bash
mkdir -p "${AUDIT_DIR}"
cd "${AUDIT_DIR}"

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
mkdir -p "${AUDIT_DIR}"
cd "${AUDIT_DIR}"

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
- `item_version` matches the published version and GitHub source (or CWS listing if closed-source)
- Signatures include both `"publisher"` and `"webstore"` kid entries (Google dual-signing)

**Note:** Unlike Firefox, there is no independently verifiable SHA-256 hash published by Google.
The chain of trust is: Chrome trusts Google's JWS signature → Google ran the review.

#### 5c-CR — Full MV3 manifest inspection

Read and assess **all** security-relevant manifest fields, not just permissions:

```bash
python3 -c "
import json
m = json.load(open('extracted/manifest.json'))

print('=== Core ===')
print('manifest_version:', m.get('manifest_version'))
print('version:         ', m.get('version'))
print('key present:     ', bool(m.get('key')))

print()
print('=== Permissions ===')
print('permissions:              ', m.get('permissions', []))
print('optional_permissions:     ', m.get('optional_permissions', []))
print('host_permissions:         ', m.get('host_permissions', []))
print('optional_host_permissions:', m.get('optional_host_permissions', []))

print()
print('=== Content scripts ===')
for cs in m.get('content_scripts', []):
    print('  matches:', cs.get('matches'), '| js:', cs.get('js'))

print()
print('=== externally_connectable ===')
print(m.get('externally_connectable', 'NONE'))

print()
print('=== CSP ===')
print(m.get('content_security_policy', 'NOT SET (MV3 default applies: script-src self; object-src self)'))

print()
print('=== web_accessible_resources ===')
print(m.get('web_accessible_resources', 'NONE'))

print()
print('=== Background ===')
print(m.get('background', 'NONE'))

print()
print('=== oauth2 / key ===')
print('oauth2:', m.get('oauth2', 'NONE'))
"
```

**Field-by-field assessment:**

- `externally_connectable.matches` — **critical for extensions with a companion web app**. Which web origins can message the background service worker directly? Broad patterns (wildcards, many domains) dramatically expand the attack surface. For each allowed origin, ask: if that origin were XSS'd or its subdomain taken over, what extension APIs would the attacker control?
- `content_security_policy` — flag `unsafe-eval`, `unsafe-inline`, or remote script sources. MV3 default is strict; any override is a red flag.
- `web_accessible_resources` — exposes extension files to web pages. Used for fingerprinting. Note which patterns are listed.
- `background.service_worker` (MV3) vs `background.scripts`/`background.page` (MV2) — MV3 service workers have shorter lifetimes and reduce ambient footprint.
- `optional_permissions` / `optional_host_permissions` — granted only when a feature is enabled. Still auditable and still real attack surface once granted.

Cross-reference permissions against the GitHub source manifest if available. Note that CWS automatically injects `update_url` — that is expected and not a red flag.

---

## Step 6 — JS behavioural analysis

### 6a — Detect minification and beautify before scanning

Most production extensions ship minified webpack bundles. A grep scan on a single-line 130 KB file
is near-useless: the ±200-char context window around a `fetch(` match is unreadable, and false
positives from vendored libs swamp real findings.

**Always beautify before scanning:**

```bash
# Check minification: if line count << char count, it's minified
wc -l extracted/*.js

# Check for source maps (clean de-minification if present)
grep -o 'sourceMappingURL=.*' extracted/*.js | head -5

# Beautify with js-beautify
npx --yes js-beautify --indent-size 2 extracted/background.js -o beautified/background.js
# Repeat for each JS file

wc -l beautified/background.js  # should be 5–20× the minified line count
```

If source maps are present, use them — they give original variable names and make the analysis
far more meaningful.

### 6b — Red-flag scan (run on beautified files)

```bash
BDIR=beautified
JS_FILES=$(find ${BDIR}/ -name "*.js")

echo "=== eval() / new Function() ==="
grep -n 'eval(\|new Function' ${JS_FILES} | grep -v '//' | head -20

echo "=== fetch() / XMLHttpRequest / WebSocket ==="
grep -n '\bfetch(\|XMLHttpRequest\|new WebSocket\|\.open(' ${JS_FILES} | head -30

echo "=== dynamic import() ==="
grep -n '\bimport(' ${JS_FILES} | head -10

echo "=== external URLs (sorted, deduplicated) ==="
grep -ohE 'https?://[a-zA-Z0-9._:/?=&#%@!~^-]+' ${JS_FILES} \
  | sort -u \
  | grep -v 'chrome-extension://\|moz-extension://\|localhost\|clients2\.google\.' \
  | head -40

echo "=== base64 blobs (>100 chars) ==="
grep -oE '[A-Za-z0-9+/]{100,}={0,2}' ${JS_FILES} | head -5
```

### 6c — Deep behavioural analysis (for commercial/closed-source/high-risk extensions)

For extensions with broad permissions or large user bases, do a manual read of the background
service worker after beautifying. Focus on:

**Network destinations — classify, don't just list:**
- First-party backend (expected for sync products): `api.vendor.com`, `*.vendor.com`
- Third-party analytics/telemetry: Segment, Amplitude, Datadog RUM, Sentry, Intercom, Google Analytics — privacy-relevant; enumerate each one
- Ad/tracking SDKs: flag immediately
- Categorise every external URL as first-party or third-party

**Auth/token handling:**
- Where are credentials stored? (`chrome.storage.local`, `chrome.storage.sync`, cookies)
- Are tokens or session IDs logged to the console?
- Are auth headers constructed and to which endpoints?

**`externally_connectable` message handlers — always inspect for web-app companions:**

If the manifest declares `externally_connectable.matches`, find and read the
`onMessageExternal` and `onConnectExternal` handlers:

```bash
grep -n 'onMessageExternal\|onConnectExternal' ${JS_FILES}
```

Then locate the dispatch function they call and enumerate every method/case:
- What data can an allowed-origin page read? (full tab state, history, settings, IDs)
- What mutations can it trigger? (tab navigation, tab creation, tab discard, settings changes)
- Is there an additional origin check *inside* the handler, or does it rely solely on the manifest's `externally_connectable` restriction?
- Are any methods explicitly blocked from web clients (e.g. `if (e.fromWebClient) throw`)? Note which ones are and which aren't.
- Does the handler have a generic API-proxy path (e.g. `default: callChromeAPI(e.path, ...e.args)`) that bypasses per-method review?

**Popup / UI shell pattern:**
If `popup.html` renders the extension UI as an iframe pointing to the extension's own web app,
that means the UI is server-controlled and can change without a store review cycle. Note:
- Does the `postMessage` listener validate `e.origin`?
- Is the iframe sandboxed?

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
- `history`: full read/write/delete of browsing history — **HIGH** capability (actual risk depends on what the code does with it; read the handler)
- `cookies` + host permission: can read/write session cookies — **HIGH**
- `cookies` + `<all_urls>`: can steal session tokens from any site — **CRITICAL**
- `webRequest` + `<all_urls>` + `blocking`: can intercept and modify all HTTP traffic — **CRITICAL**
- `declarativeNetRequest` / `declarativeNetRequestWithHostAccess`: can rewrite/block network requests via rules — **HIGH** (rules may be updated dynamically)
- `debugger`: can attach to any tab's JS runtime, read all JS memory/variables, breakpoint execution — **CRITICAL**
- `management`: can install, uninstall, enable, or disable other extensions — **CRITICAL**
- `nativeMessaging`: can communicate with arbitrary native binaries on the host OS — **CRITICAL** (escapes browser sandbox)
- `proxy`: can redirect all browser traffic through an attacker-controlled proxy — **CRITICAL**
- `downloads`: can write files to disk without user file-picker — **HIGH**
- `<all_urls>` as a host permission alone: extension can make credentialed requests to any site the user is logged into — **HIGH**
- `externally_connectable` with broad wildcards: any web page matching the pattern can invoke extension APIs — **HIGH**; assess each exposed method individually

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
rm -rf "${AUDIT_DIR}"
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
- `onMessageExternal` registered to the **same handler** as `onMessage` with no additional
  origin check inside — relies solely on `externally_connectable` manifest restriction;
  assess the full attack surface of what an allowed-origin XSS could invoke
- Generic API-proxy dispatch (e.g. `default: callChromeAPI(e.path, ...args)`) exposed
  to `externally_connectable` origins — all permissions become callable by the web app
- `popup.html` rendering extension UI as an `<iframe>` to the extension's own web server
  with no `sandbox` attribute and no `e.origin` check in `postMessage` listener —
  popup UI is server-controlled and can change without a store review cycle
- Third-party analytics/telemetry SDKs embedded in the extension binary (Segment, Amplitude,
  Intercom, Datadog RUM, etc.) — enumerate each one and note what data they receive
