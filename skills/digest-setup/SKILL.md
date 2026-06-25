---
description: Bootstrap the notification digest system for a new user, or update the routine prompt across all live routines. Assembles a fully self-contained prompt from the bundled template and the four collector skills, then pushes to the cloud routines.
allowed-tools:
  - Read
  - Edit
  - Write
  - mcp__claude_ai_Atlassian_Rovo__createConfluencePage
  - mcp__claude_ai_Atlassian_Rovo__getConfluencePage
  - mcp__claude_ai_Atlassian_Rovo__updateConfluencePage
  - mcp__claude_ai_Atlassian_Rovo__getConfluenceSpaces
  - mcp__claude_ai_Atlassian_Rovo__getAccessibleAtlassianResources
  - mcp__claude_ai_Slack__slack_search_users
  - RemoteTrigger
argument-hint: "[--update-routines] [--recreate-page] [--recreate-routines]"
---

# digest-setup

Bootstrap or update the notification digest system for any user. This skill is the **single source of truth** for system documentation, setup procedures, and the assembled routine prompt.

---

## Overview

### What it is

Harry Nguyen's personal notification digest. Runs as a cloud routine 4× per day, aggregating notifications from 4 sources into a prioritised, urgency-tagged summary on a private Confluence page. A 5th routine runs every Sunday evening for weekly reflection. Harry reads the page and leaves feedback as inline or footer comments; the routine picks them up on the next run.

### Build pipeline

This skill bundles `${CLAUDE_SKILL_DIR}/routine-prompt.template.md` — the prompt scaffolding containing the dispatcher, page-load/feedback/render logic, and `INCLUDE` markers. The four collector skills (flat siblings in `agent.md/skills/`) hold the collection logic, each fenced with `<!-- COLLECTION:START/END -->` markers.

At setup or `--update-routines` time, the **Assemble** procedure reads the template, resolves the INCLUDE markers from the sibling skills' fenced regions, substitutes identity variables, strips the frontmatter, and pushes the result directly to the cloud routines. The assembled prompt is never committed as a file.

```
digest-setup/
  SKILL.md                      ← this file (docs + setup + assemble procedure)
  routine-prompt.template.md    ← bundled scaffolding (dispatcher, page logic, INCLUDE markers)

digest-slack/SKILL.md           ┐ COLLECTION:START/END fenced
digest-jira/SKILL.md            │ source of truth for collection logic
digest-meetings-gmail/SKILL.md  │ still invocable standalone as personal:digest-*
digest-github-gmail/SKILL.md    ┘
```

To update collection logic: edit the relevant collector skill. To update the dispatcher, feedback, or render logic: edit `routine-prompt.template.md`. Then run `personal:digest-setup --update-routines` to push.

### Data sources & status

| Source | Skill | Status |
|--------|-------|--------|
| Slack (DMs, @mentions, saved items) | `digest-slack` | ✅ Working |
| Jira + Confluence watched pages | `digest-jira` | ✅ Working |
| Google Meet notes (via Gmail) | `digest-meetings-gmail` | ✅ Working |
| GitHub PRs (via Gmail) | `digest-github-gmail` | ℹ️ Verifying — routing changed 2026-06-20 |

### Schedule (ICT = UTC+7)

| Slot | ICT | Cron (UTC) | Routine ID |
|------|-----|------------|------------|
| Morning | 9:02am | `2 2 * * *` | `trig_01ABZBa8Phg5eo5MopcbQ34F` |
| Midday | 2:05pm | `5 7 * * *` | `trig_017D2rxiWfTRiUKrnHbZs4fL` |
| Evening | 7:10pm | `10 12 * * *` | `trig_01TexcywPxmXcbMAhPuVz62P` |
| Night | 3:00am | `0 20 * * *` | `trig_011j7JDs14GJzX4irdjME7to` |
| Reflect | Sun 6pm | `0 11 * * 0` | `trig_016tc6N2qKs4xRy2tSHwBmxP` |

Future: a 5th routine for `MODE: cleanup` (Gmail label + archive). The template dispatcher already reserves that branch.

### Confluence page structure

**Page:** https://airtasker.atlassian.net/wiki/x/BID7NQE (ID: `5200642052`)

6 `<h2>` sections maintained by the routine:
1. **About** — human-facing overview; routine carries forward verbatim each run
2. **Instructions** — Harry edits freely; applied as editorial filters each run
3. **Ignore list** — permanent skip list
4. **Snoozed** — items snoozed until a date
5. **Digest** — routine rewrites each run
6. **State** — JSON block; routine manages; do not edit

### Feedback model

Leave comments on the page. Routine processes open comments at run start and replies `🤖 Digest:`.
- **Inline** (highlight a digest item line): `ignore` / `snooze until <date>` / `working on it` / `tell me more`
- **Footer** (bottom of page): `ignore <key>` / `snooze <key> until <date>` / `tell me more about <id>`

### State schema

```json
{
  "last_run": "ISO timestamp or null",
  "seen_jira": {"MAKE-121": "YYYY-MM-DD"},
  "seen_slack_saved": ["message_ts"],
  "seen_confluence_saved": ["page_id"],
  "slack_in_progress": ["item_id"],
  "processed_comment_ids": ["comment_id"]
}
```

| Key | Owner |
|-----|-------|
| `last_run` | Routine (set after all collectors complete) |
| `seen_jira` | `digest-jira` (all assigned-open keys, surfaced or not) |
| `seen_slack_saved` | `digest-slack` |
| `seen_confluence_saved` | `digest-jira` |
| `slack_in_progress` | Routine — Step 2 feedback processing |
| `processed_comment_ids` | Routine — Step 2 feedback processing |

### Key IDs (Harry's live instance — do not recreate)

| Resource | Value |
|----------|-------|
| Atlassian cloud ID | `73663d72-ff40-4c60-a45c-357594791a92` |
| Atlassian account ID | `712020:0c974b3b-9fc7-4e6b-ab7f-e82839551d04` |
| Confluence digest page ID | `5200642052` |
| Confluence page URL | https://airtasker.atlassian.net/wiki/x/BID7NQE |
| Personal Confluence space ID | `3810656435` |
| Space homepage (parent page) | `3810656510` |
| Slack member ID | `U08383K69RS` |
| GitHub username | `harry-da` |
| Skills location | `/Users/harry/agent.md/skills/` |
| Personal plugin | `personal@agent-md` in `~/.claude/settings.json` |

### Required MCP connectors (all routines)

| Connector | UUID | URL |
|-----------|------|-----|
| Atlassian-Rovo | `ab29c762-b41c-4ac8-bfbc-37b4107d8997` | `https://mcp.atlassian.com/v1/mcp` |
| Slack | `38e2c689-d040-4c45-b049-d07e2de71d9b` | `https://mcp.slack.com/mcp` |
| Gmail | `b15f0a0d-53ed-4043-b134-018650bc0cc6` | `https://gmailmcp.googleapis.com/mcp/v1` |
| Google Drive | `1abf6f79-0bbf-4905-84a1-7dd6a0aa2e3f` | `https://drivemcp.googleapis.com/mcp/v1` |

### Open TODOs

- [ ] Confirm GitHub routing — check `from:notifications@github.com` in Gmail after next PR activity; remove the routing caveat from `digest-github-gmail/SKILL.md` once confirmed
- [ ] Implement Gmail cleanup routine — hourly `MODE: cleanup`; needs `gh/*` + `meetings/notes` Gmail labels
- [ ] Create Gmail labels — `gh/review`, `gh/mention`, `gh/my-prs`, `gh/ci`, `gh/dependabot`, `gh/noise`, `meetings/notes`
- [x] Fix routine display names — "SGT" → "ICT" in all 4 names ✅ already done
- [x] Remove page test data — `stand-up` in Ignore list + `MAKE-121` in Snoozed ✅ 2026-06-25
- [x] Restore About section lost from page ✅ 2026-06-25
- [x] Add `run_history` to State schema + tracking in Step 5b ✅ 2026-06-25
- [x] Add `MODE: reflect` Reflect Flow + 5th Sunday routine ✅ 2026-06-25

---

## Modes

- **Default** — full bootstrap: collect identity → fill skills → create page → create routines
- **`--update-routines`** — assemble prompt from template + siblings → push to all 4 existing routines (skips identity + page creation)
- **`--recreate-page`** — recreate the Confluence page from scratch (wipes State — use carefully)
- **`--recreate-routines`** — recreate routines (delete old ones first at https://claude.ai/code/routines)

---

## Step 1 — Collect identity

Ask the user for the following (or resolve automatically where possible):

| Field | How to get it |
|-------|---------------|
| `display_name` | Ask the user — their full name as it appears in meeting notes (e.g. `Harry Nguyen`) |
| `email` | Ask the user — their Atlassian/work email |
| `github_username` | Ask the user — their GitHub handle (no `@`) |
| `slack_member_id` | `slack_search_users(query=display_name)` → find the matching user → copy `id` field (starts with `U`) |
| `atlassian_cloud_id` | `getAccessibleAtlassianResources` → extract `id` for the user's Atlassian site |
| `atlassian_account_id` | `getAccessibleAtlassianResources` → or `atlassianUserInfo` |
| `confluence_space_id` | `getConfluenceSpaces` → find the user's personal space → copy `id` |
| `confluence_parent_page_id` | The homepage of their personal space — ask the user or resolve from `getPagesInConfluenceSpace` |
| `timezone` | Ask the user — used to set routine schedule (e.g. `Asia/Saigon`) |

Confirm all values with the user before proceeding.

---

## Step 2 — Fill identity into skill files

Each collector skill has an `identity:` block in its YAML frontmatter. Use the `Edit` tool to do a targeted replacement of the entire `identity:` block in each file — do not rewrite the whole file.

The template (`routine-prompt.template.md`) holds the **superset** of identity vars. Fill it too.

| File | Identity fields to fill |
|------|------------------------|
| `${CLAUDE_SKILL_DIR}/routine-prompt.template.md` | `display_name`, `email`, `slack_member_id`, `atlassian_account_id`, `atlassian_cloud_id`, `confluence_page_id` *(after Step 3)*, `confluence_page_url` *(after Step 3)*, `github_username` |
| `digest-slack/SKILL.md` | `display_name`, `slack_member_id`, `atlassian_cloud_id`, `atlassian_account_id`, `confluence_page_id` *(after Step 3)*, `confluence_page_url` *(after Step 3)* |
| `digest-jira/SKILL.md` | `email`, `display_name` |
| `digest-github-gmail/SKILL.md` | `github_username`, `email` |
| `digest-meetings-gmail/SKILL.md` | `display_name` |

Note: `confluence_page_id` and `confluence_page_url` must be filled after Step 3 (page creation) — go back and update `digest-slack/SKILL.md` and the template once the page ID is known.

---

## Step 3 — Create the Confluence page

Skip if page already exists. To recreate, pass `--recreate-page`.

Call `createConfluencePage` with:
```
cloudId:       {atlassian_cloud_id}
spaceId:       {confluence_space_id}
parentId:      {confluence_parent_page_id}
title:         🔔 Notification Digest
isPrivate:     true
contentFormat: html
body:          <see Page skeleton below>
```

Record the returned `pageId` and `_links.webui` (page URL). Back-fill `digest-slack/SKILL.md` and the template (Step 2).

### Page skeleton

```html
<h2>About</h2>
<p>This page is written by an automated digest routine that runs 4× per day. It aggregates notifications from Slack, Jira/Confluence, Google Meet notes, and GitHub into a prioritised summary.</p>
<p><strong>Giving feedback:</strong> leave an inline comment on any digest item (highlight the line) or a footer comment at the bottom. The routine picks up open comments at run start and replies 🤖 Digest:.</p>
<ul>
<li><p>Inline: <code>ignore</code> / <code>snooze until &lt;date&gt;</code> / <code>working on it</code> / <code>tell me more</code></p></li>
<li><p>Footer: <code>ignore &lt;key&gt;</code> / <code>snooze &lt;key&gt; until &lt;date&gt;</code> / <code>tell me more about &lt;id&gt;</code></p></li>
</ul>

<h2>Instructions</h2>
<p>Edit this section freely — the routine reads it and applies it as editorial filters on each run.</p>
<p>Examples: "skip Confluence mentions unless I'm directly tagged", "always surface MAKE tickets even if FYI", "don't show stand-up notes".</p>

<h2>Ignore list</h2>
<p>Items listed here are permanently skipped. One per line. Use ticket keys (MAKE-121), repo/PR slugs (airtasker/mobile#948), or keywords (stand-up).</p>
<ul>
<li><p>stand-up</p></li>
</ul>

<h2>Snoozed</h2>
<p>Managed by the routine. Items snoozed until a date.</p>
<table>
<thead><tr><th><p>Item</p></th><th><p>Until</p></th></tr></thead>
<tbody>
</tbody>
</table>

<h2>Digest — (not yet run)</h2>
<p><em>The routine has not run yet.</em></p>

<h2>State</h2>
<p>Managed by the routine. Do not edit.</p>
<pre><code>{
  "last_run": null,
  "seen_jira": {},
  "seen_slack_saved": [],
  "seen_confluence_saved": [],
  "slack_in_progress": [],
  "processed_comment_ids": []
}</code></pre>
```

---

## Assemble the routine prompt

This procedure is called by both Step 4 (bootstrap) and Step 5 (`--update-routines`). It produces a fully self-contained prompt from the template + the four collector skill files.

1. **Read the template**: `Read("${CLAUDE_SKILL_DIR}/routine-prompt.template.md")`
2. **Parse frontmatter**: extract the `identity:` block from the YAML front matter. Hold each key-value as a substitution map.
3. **Resolve INCLUDE markers**: for each `<!-- INCLUDE: <skill> COLLECTION -->` in the template body:
   a. Read the sibling: `Read("${CLAUDE_SKILL_DIR}/../<skill>/SKILL.md")`
   b. Extract the text between `<!-- COLLECTION:START -->` and `<!-- COLLECTION:END -->` (exclusive of the fence lines themselves).
   c. Downgrade all headings in the extracted text by one level (`##` → `###`, `###` → `####`) so they nest under the Step 3 subheading.
   d. Replace the `<!-- INCLUDE: <skill> COLLECTION -->` marker with the extracted, downgraded text.
4. **Substitute identity variables**: replace every `{variable}` in the assembled body with the matching value from the frontmatter identity map (e.g. `{display_name}` → `Harry Nguyen`).
5. **Strip frontmatter**: remove the `---` … `---` YAML block from the result. The cloud routine sees only the body.
6. **Review**: write the assembled result to a scratchpad file (e.g. `/tmp/digest-assembled-prompt.md`) so you can inspect it before pushing. Confirm with the user if there are any concerns.
7. **Use as push payload**: the assembled body string is what gets embedded in the routine's `job_config`.

**Verify the assembled result** before pushing:
- All four `<!-- INCLUDE: ... -->` markers are replaced (none remain)
- No `<!-- COLLECTION:START/END -->` fence lines remain
- No `{variable}` placeholders remain unresolved
- The dispatcher ("What to do now") and About sections appear at the top
- Steps 1, 2, 4, 5, 6 of Digest Flow are present (verbatim from template)
- Step 3 contains the inlined collection logic for all four sources

---

## Step 4 — Create the cloud routines

Skip if routines already exist. To recreate, pass `--recreate-routines`.

### Schedule

Suggest these four times as defaults — let the user adjust. Convert to UTC based on their timezone.

| Slot | Local | UTC (Asia/Saigon example) | Cron |
|------|-------|--------------------------|------|
| Morning | 9:00am | 2:00am | `0 2 * * *` |
| Midday | 2:00pm | 7:00am | `0 7 * * *` |
| Evening | 7:00pm | 12:00pm | `0 12 * * *` |
| Night | 3:00am | 8:00pm prev day | `0 20 * * *` |

### Routine prompt

Run **Assemble the routine prompt** (above) first. Use the assembled body string as the routine prompt — do not read `routine-prompt.md` or any other file.

### Job config shape

```json
{
  "name": "Notification Digest — {slot} {timezone}",
  "cron_expression": "{cron}",
  "enabled": true,
  "job_config": {
    "ccr": {
      "environment_id": "env_01FS2QbHQV5VYyNUDycxA4bo",
      "session_context": {
        "model": "claude-sonnet-4-6",
        "allowed_tools": ["Bash", "Read", "Write", "Edit"]
      },
      "events": [{
        "data": {
          "uuid": "<fresh lowercase v4 uuid — generate one per routine>",
          "session_id": "",
          "type": "user",
          "parent_tool_use_id": null,
          "message": {
            "role": "user",
            "content": "<assembled prompt body>"
          }
        }
      }]
    }
  },
  "mcp_connections": [
    {"connector_uuid": "ab29c762-b41c-4ac8-bfbc-37b4107d8997", "name": "Atlassian-Rovo", "url": "https://mcp.atlassian.com/v1/mcp"},
    {"connector_uuid": "38e2c689-d040-4c45-b049-d07e2de71d9b", "name": "Slack", "url": "https://mcp.slack.com/mcp"},
    {"connector_uuid": "b15f0a0d-53ed-4043-b134-018650bc0cc6", "name": "Gmail", "url": "https://gmailmcp.googleapis.com/mcp/v1"},
    {"connector_uuid": "1abf6f79-0bbf-4905-84a1-7dd6a0aa2e3f", "name": "Google-Drive", "url": "https://drivemcp.googleapis.com/mcp/v1"}
  ]
}
```

Record the returned routine IDs and report them to the user.

---

## Step 5 — Update routine prompt only (`--update-routines`)

Use this when `routine-prompt.template.md` or any collector skill's COLLECTION logic changes and you need to push the updated assembled prompt to all 4 existing routines.

1. Run **Assemble the routine prompt** (above). Review the scratchpad result.
2. List routines: `RemoteTrigger({action: "list"})` — identify the 4 digest routines by name.
3. For each routine, call:
   ```
   RemoteTrigger({action: "update", trigger_id: "...", body: {
     job_config: { ccr: { ... events with assembled body ... } }
   }})
   ```
4. Confirm all 4 return HTTP 200.

---

## Step 6 — Verify

After setup or update:
1. `getConfluencePage(cloudId, pageId, contentFormat="html")` → all 6 `<h2>` sections parse cleanly (About, Instructions, Ignore list, Snoozed, Digest, State)
2. `RemoteTrigger({action: "list"})` → all routines appear, enabled, correct cron, all 4 MCP connections
3. Optionally trigger one routine: `RemoteTrigger({action: "run", trigger_id: "..."})` and confirm it writes to the page with About section intact at top

Report:
```
✅ Confluence page: {confluence_page_url} (pageId: {confluence_page_id})
✅ Routines: 4 active
   - Notification Digest — 9:02am ICT  (trig_01ABZBa8Phg5eo5MopcbQ34F)
   - Notification Digest — 2:05pm ICT  (trig_017D2rxiWfTRiUKrnHbZs4fL)
   - Notification Digest — 7:10pm ICT  (trig_01TexcywPxmXcbMAhPuVz62P)
   - Notification Digest — 3:00am ICT  (trig_011j7JDs14GJzX4irdjME7to)
✅ Skills updated: digest-slack, digest-jira, digest-github-gmail, digest-meetings-gmail
✅ Assembled prompt: no INCLUDE markers remain, no {vars} remain
```
