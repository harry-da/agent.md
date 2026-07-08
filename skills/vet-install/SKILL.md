---
description: Vet a third-party tool, package, CLI, or extension before installing it — checks provenance, version integrity, and (most importantly) exactly what trust or privilege the install grants, then gets explicit user confirmation before the actual install command runs. Use this proactively whenever you're about to run any install command for something not already trusted in this environment — brew install/tap, npm/pnpm/yarn add (especially global), pip/pipx install, curl | bash / curl | sh, a VS Code or editor extension install, or downloading a GitHub release binary. Trigger even when the tool looks obviously fine or well-known — the point is a consistent gate before installing, not risk-based judgment calls about which tools "need" checking.
allowed-tools:
  - Bash
  - WebSearch
  - WebFetch
argument-hint: "<tool-name-or-url-or-install-command> [--ecosystem brew|npm|pip|curl|vscode|github-release]"
---

# vet-install

Before installing anything third-party, spend a couple of minutes understanding where it comes
from and what it's asking you to trust — then tell the user plainly and let them decide. This
skill ends in a confirmation gate every time. Don't skip the gate because the tool is popular,
official-looking, or something you've heard of — the value of the habit is that it's consistent,
not that it's reserved for suspicious-looking things. The riskiest installs are often the
boring, well-known ones, precisely because nobody double-checks them.

If the target is a **browser extension** (Chrome Web Store / Firefox AMO), use the
`browser-addon-audit` skill instead — it has deep binary-format verification (CRX3/XPI parsing,
signing checks) that's specific to that ecosystem and goes further than this skill does.

## Why this exists

Installing a tool is rarely just "download one file." It often means trusting a whole source
going forward — a Homebrew tap, an npm registry, a package's maintainer account — not just the
one artifact you asked for. That distinction (one artifact vs. an ongoing trust relationship) is
the single most important thing to surface, and it's easy to blow past because the install
command itself looks routine. (This skill exists because of exactly that: installing
`idb-companion` from a Homebrew tap required `brew trust <tap>` first — a grant that covers
*all current and future* formulae in that tap, not just the one being installed.)

---

## Step 1 — Identify the target and ecosystem

Figure out: what's being installed, from where, and which package manager/ecosystem is involved
(Homebrew, npm/pnpm/yarn, pip/pipx, a `curl | sh`-style installer script, a VS Code/editor
marketplace extension, or a raw GitHub release binary). If it's ambiguous, ask rather than guess.

## Step 2 — Chain of custody

State plainly, for this specific ecosystem: source repo → build/publish process → registry or
distribution channel → your install command. Note what's actually attested (signed, hashed,
provenance-tracked) versus opaque (nothing but "trust the registry"). This varies a lot by
ecosystem — see the cheat sheets below for what each one actually gives you.

## Step 3 — Provenance & trust signals

- Who publishes it — an individual, an org, is it the project's own official channel or a
  third-party mirror/fork?
- Activity signals: GitHub stars/forks, last commit/release date, number of maintainers, license.
- Adoption signals where available: npm weekly downloads, PyPI download stats, Homebrew
  analytics, VS Code marketplace install count.
- Is this the same publisher/account that's published every prior version, or did a new
  maintainer just take over? (Maintainer takeover is a classic supply-chain attack vector.)

## Step 4 — Privilege & trust escalation check (the important one)

This is the step most worth doing carefully, because it's the one that's easy to miss when
you're focused on "does the tool itself look safe." Ask explicitly:

- **Does this require `sudo`?**
- **Does this extend trust to a source beyond the one artifact?** — e.g. `brew tap` + `brew
  trust` on a whole tap (not just one formula), adding an unfamiliar npm registry/scope,
  `apt-add-repository`, enabling an unsigned/unverified extension source. If so, say explicitly
  what else that trust now covers (current *and future* packages from that source) — this is the
  fact most worth putting in front of the user, since it's the part a quick glance at the install
  command won't reveal.
- **Does it modify shell rc files, global config, or `$PATH`** in a way that affects every future
  shell session, not just this one?
- **Does it request elevated OS permissions** — accessibility access, full disk access, keychain
  access, camera/mic?
- **Is the install pinned to a specific version**, or does it float to `latest`/`main`/a branch
  tip (meaning what you get today may not be what you get on the next run)?

Flag anything broader than "install this one specific, named artifact."

## Step 5 — Version & release integrity

Is there a checksum or signature you can actually verify against (see the ecosystem cheat sheets
below for the concrete command)? Is a specific version/tag being installed, or an unpinned
reference? An unpinned install to `latest` or a moving branch means this check can't give a
stable answer — say so.

## Step 6 — Behavioral scan, where feasible

For anything that runs code at install time — `curl | bash` scripts, npm `postinstall`/
`preinstall` hooks, a Homebrew formula's Ruby source — read it before it runs, not after. Look
for: `eval`/dynamic code execution, obfuscated or base64-encoded blobs, unexpected outbound
network calls, telemetry/exfiltration, one script fetching and piping another. **Never pipe a
remote script straight to a shell without reading it first** — `curl` it to a file, read the
file, then decide.

---

## Ecosystem cheat sheets

### Homebrew (formula, cask, or tap)

```bash
brew info --json=v2 <formula-or-cask>          # source, homepage, versions, whether it's from core or a tap
brew cat <formula>                              # read the actual Ruby install recipe before running it
brew tap                                        # taps already trusted in this environment
```
A formula from `homebrew/core` is reviewed by Homebrew maintainers; a formula from a third-party
tap is not — it's whatever that tap's maintainer publishes. `brew trust <tap>` (required before
Homebrew will load an untrusted tap's formulae) grants trust to that tap as a whole, not to a
single formula — say this explicitly when it comes up.

### npm / pnpm / yarn

```bash
npm view <pkg>                                  # publisher, version, repo link, last publish
npm view <pkg> maintainers                      # who can publish new versions
npm view <pkg> dist.integrity                   # published integrity hash for the current version
npm view <pkg> versions --json | tail           # version history — look for a maintainer/publish-pattern change
npm audit                                       # after install, check for known-vulnerable deps
```
Prefer packages with provenance attestations (`npm view <pkg> dist-tags` plus checking the npm
registry page for a "Provenance" badge) — these cryptographically tie the published package back
to the exact CI run and source commit that built it. A `postinstall` script is the single biggest
npm supply-chain risk surface — always check `npm view <pkg> scripts` before installing.

### pip / pipx

```bash
curl -s https://pypi.org/pypi/<pkg>/json | python3 -m json.tool   # publisher, releases, dependencies
pip download --no-deps --no-binary :all: -d /tmp/pkgcheck <pkg>   # fetch sdist without installing, to inspect first
```
PyPI publishes SHA-256 hashes per release file (in the JSON API response under
`releases.<version>[].digests`) — pip verifies these automatically against the index, but a
compromised maintainer account can still publish a malicious release with a valid hash for
*that* release. Check publish history for sudden gaps or a new maintainer.

### `curl | bash` / `curl | sh` installers

```bash
curl -fsSL <url> -o /tmp/installer.sh
less /tmp/installer.sh          # read it — all of it, not just the top
shasum -a 256 /tmp/installer.sh # compare against a published checksum if the project provides one
```
Never pipe directly (`curl ... | bash`) without this step — a script fetched fresh each time can
differ from what you reviewed a moment ago if the endpoint is compromised or serves conditionally.
If the script itself downloads and runs further payloads, follow that chain too.

### VS Code / editor extensions

Check the marketplace listing for: publisher identity (verified publisher badge), install count,
last updated date, and whether the extension links to a public source repo. If it does, treat it
like the GitHub cheat sheet below. Unverified publishers with very new accounts and a single
extension are a common pattern for typosquatting popular extension names.

### GitHub release binaries

```bash
gh api repos/<owner>/<repo> --jq '{stars:.stargazers_count, pushed_at, archived}'
gh release view <tag> --repo <owner>/<repo>     # release notes, assets, whether it's signed
gh api repos/<owner>/<repo>/releases/<id>/assets --jq '.[].name'
```
Check whether release assets are signed (GPG signature file alongside the binary, or sigstore/
cosign attestation) and whether the repo's CI (`.github/workflows/`) actually builds and
publishes releases — a repo with commits but no release-building CI means someone uploaded the
binary by hand, which is a materially weaker guarantee than a reproducible CI-built artifact.

---

## Red flags (worth calling out explicitly if found)

- Checksum/hash mismatch between what you downloaded and what the registry/index publishes
- Missing or invalid signature where the ecosystem supports one
- A version bump that adds significantly broader permissions/scope than prior versions
- `eval`/dynamic code execution, or large base64 blobs, in an install-time script
- An install script that fetches and pipes another script to a shell
- A `postinstall`/`preinstall` hook that does anything beyond expected build steps (compiling
  native bindings, etc.) — especially network calls
- A new maintainer account publishing a version shortly after taking over from the prior one
- Unpinned installs (`latest`, a branch tip, `main`) where a pinned version was available
- The install asks for more trust/permission than the tool's stated purpose plausibly needs

---

## Step 7 — Report, then stop and ask

Summarize concisely — this doesn't need to be long for a low-risk, well-known tool, but always
include the trust-escalation line explicitly:

```
## Install check: <tool>

**Source:** <registry/repo/tap>, publisher: <who>
**What this actually installs:** <artifact>, version <pinned|latest/floating>
**Trust/privilege required:** <none beyond the artifact | sudo | new tap/registry trust
  covering <scope> | shell config changes | OS permissions: <...>>
**Version integrity:** <checksum/signature verified | not independently verifiable>
**Red flags:** <none found | list>
**Recommendation:** proceed / proceed with caution / hold off
```

Then use `AskUserQuestion` (or, if that tool isn't available in context, a direct question in
your reply) to get explicit go-ahead **before running the install command** — every time,
regardless of the recommendation. If the user approves, note in your own follow-up what broader
trust was just granted (e.g. "this trusted the whole `facebook/fb` tap, not just
`idb-companion`") so it's easy to revisit later if needed.
