---
description: Read Slack notification activity (DMs, @mentions, saved items) and return a structured list of items needing the user's attention. Covers everything that would show up as a Slack notification, plus saved-for-later items not yet actioned. Processes feedback (inline + footer comments on the Confluence digest page) from previous runs before collecting.
allowed-tools:
  - mcp__claude_ai_Slack__slack_search_public_and_private
  - mcp__claude_ai_Slack__slack_search_users
  - mcp__claude_ai_Slack__slack_read_thread
  - mcp__claude_ai_Slack__slack_read_channel
  - mcp__claude_ai_Slack__slack_read_user_profile
  - mcp__claude_ai_Atlassian_Rovo__getConfluencePage
  - mcp__claude_ai_Atlassian_Rovo__updateConfluencePage
  - mcp__claude_ai_Atlassian_Rovo__getConfluencePageFooterComments
  - mcp__claude_ai_Atlassian_Rovo__createConfluenceFooterComment
  - mcp__claude_ai_Atlassian_Rovo__getConfluencePageInlineComments
  - mcp__claude_ai_Atlassian_Rovo__createConfluenceInlineComment
argument-hint: "[lookback_hours=12]"
identity:
  display_name: "Harry Nguyen"
  slack_member_id: "U08383K69RS"
  atlassian_cloud_id: "73663d72-ff40-4c60-a45c-357594791a92"
  atlassian_account_id: "712020:0c974b3b-9fc7-4e6b-ab7f-e82839551d04"
  confluence_page_id: "5200642052"
  confluence_page_url: "https://airtasker.atlassian.net/wiki/x/BID7NQE"
---

# digest-slack

Read Slack notification activity and return a structured list of items needing the user's attention.

**Primary contract (when invoked by the routine):** execute only `## Data Collection` below. Receive `ignore_list`, `snooze_list`, `in_progress`, `deep_dive`, `State` (incl. `seen_slack_saved`, `last_run`) as inputs from the routine. Return classified Slack items and `seen_slack_saved` deltas. Do **not** load the Confluence page, process feedback, render the digest, or write anything — `routine-prompt.md` Steps 1, 2, and 5 own those responsibilities.

For standalone testing (running this skill directly without the routine), see `## Appendix — Standalone mode`.

---

<!-- COLLECTION:START -->

## Data Collection

Compute a date string for `lookback_hours` ago (default 12, or `$ARGUMENTS`) in Slack's `after:YYYY-MM-DD` format.

Before running searches, you must already hold (from `## Feedback Processing`): `ignore_list`, `snooze_list` (item → until-date), `in_progress` (item IDs marked in-progress), `deep_dive` (item IDs flagged for expansion).

### Searches

**Direct messages** — human-sent only
```
is:dm after:<date>
```
`channel_types: "im"`. Exclude any result where the sender is the user themselves (sender ID == `slack_member_id`) — self-authored DMs are not notifications.

**@mentions**
```
<@{slack_member_id}> after:<date>
```
Use the `slack_member_id` from Identity. `include_bots: false`. Exclude results from automated channels like #pull-requests where bots announce PRs.

**Saved items** (persistent — no date filter)
```
is:saved
```
Fetch up to 3 pages (60 items max). Cross-reference timestamps against `seen_slack_saved` from State:
- Timestamp NOT in seen list AND saved after `last_run` → surface as new (🟡)
- Timestamp in seen list AND saved < 7 days → suppress
- Timestamp in seen list AND saved ≥ 7 days → resurface as reminder (🟡)
- On first ever run (`last_run` is null): record all timestamps to State but do NOT surface them — too noisy.

Note: skip `is:thread` — it returns all thread replies in every channel Harry is subscribed to, not threads he participated in. Too noisy.

For each actionable result, read the thread if needed using `slack_read_thread`.

### Apply feedback flags

- **Ignore**: drop any result whose ticket key, `repo#PR`, or keyword matches an entry in `ignore_list`.
- **Snooze**: drop any result matching a `snooze_list` item whose until-date is still in the future. (Surface it again once the date passes.)
- **In-progress**: suppress the item from the normal digest, BUT re-check whether it is still open against the new data. If it now appears resolved/closed, surface a one-line `✅ resolved` note; otherwise stay silent.
- **Deep-dive**: for these item IDs, read the full thread / linked ticket and include an expanded summary instead of a one-liner.

### Classify

| Condition | Urgency |
|-----------|---------|
| Direct question, time-sensitive, or someone explicitly waiting on Harry | 🔴 |
| @mention or DM needing acknowledgement | 🟡 |
| Newly saved item (saved after last_run) | 🟡 |
| Saved item resurfaced after 7 days | 🟡 |
| FYI update, passive mention | 🟢 |

### Exclude
- Bot messages without a direct action for Harry
- Self-sent DMs (Harry to Harry)
- Automated PR announcement bots (#pull-requests etc.)
- Saved items already in `seen_slack_saved` and saved < 7 days ago
- Anything matching the ignore list or an active snooze

### Assign stable item IDs

Every actionable item needs a **stable ID** so feedback (comments, ignore, snooze) can refer to it across runs. Prefer a natural key in this priority order:
1. Ticket key — `MAKE-121`
2. `repo#PR` — `airtasker/mobile#826`
3. Otherwise a slug from channel + short hash of the message permalink — `dm-jane-a1b2`

Render the ID inline in `[...]` on each digest line. This ID is the join key between the page digest body and State — and is what inline comments are anchored to.

<!-- COLLECTION:END -->

---

## Appendix — Standalone mode

> **`routine-prompt.md` Steps 1/2/5 are the canonical implementation for the cloud digest.** The sections below apply only when running `personal:digest-slack` directly for testing — they are superseded by the routine in production. When invoked by the routine, never execute feedback processing or page writes.

## State & Feedback Backend

### Backend contract (abstract)

Any backend must provide these operations. The rest of the skill is written only in terms of this contract:

| Operation | Returns / Effect |
|-----------|------------------|
| `read_instructions()` | Harry's free-text preferences |
| `read_ignore_list()` | list of permanently-skipped keys/keywords |
| `read_snoozed()` | list of `{item, until_date}` |
| `read_state()` | `{last_run, seen_jira, seen_slack_saved, seen_confluence_saved, slack_in_progress, processed_comment_ids}` |
| `read_pending_feedback()` | open inline comments on digest item lines + open footer comments |
| `write_state(state)` | persist updated State |
| `append_ignore(items)` | add new keys to the ignore list |
| `upsert_snooze(item, until_date)` | add/update a row in the snooze table |
| `post_bot_reply(comment_id, text)` | reply to a specific comment with `🤖 Digest:` prefix |
| `render_digest(items)` | rewrite the Digest section of the page body |
| `persist()` | write the mutated full page body with one `updateConfluencePage` call |

### Current backend: private Confluence page

**IDs — read from the Identity section above (do not look these up at runtime):**
- cloudId: `atlassian_cloud_id`
- Digest page ID: `confluence_page_id`
- Page URL: `confluence_page_url`
- Atlassian account ID: `atlassian_account_id`

**Page structure** the routine maintains (HTML, `contentFormat="html"`):

```html
<h2>Instructions</h2>
<!-- Harry edits freely; free text or a bullet list -->

<h2>Ignore list</h2>
<p>helper text</p>
<ul><li><p>stand-up</p></li></ul>

<h2>Snoozed</h2>
<p>helper text</p>
<table>
  <thead><tr><th><p>Item</p></th><th><p>Until</p></th></tr></thead>
  <tbody><tr><td><p>MAKE-121</p></td><td><p>2026-06-27</p></td></tr></tbody>
</table>

<h2>Digest — YYYY-MM-DD HH:MM ICT</h2>
<!-- routine rewrites this section each run; items grouped by urgency; each line carries [item_id] -->

<h2>State</h2>
<p>Managed by the routine. Do not edit.</p>
<pre><code>{ ...JSON... }</code></pre>
```

#### Read/parse primitive

`getConfluencePage(cloudId={atlassian_cloud_id}, pageId={confluence_page_id}, contentFormat="html")` once at run start. Split the returned `body` HTML on `<h2>` boundaries to extract each section. Key parsing rules:
- **Ignore list**: `<li><p>item</p></li>` — text content of each `<p>` within `<li>`
- **Snoozed table**: `<tbody><tr><td><p>item</p></td><td><p>date</p></td></tr></tbody>` — text of each cell `<p>`
- **State block**: `<pre><code>{ HTML-encoded JSON }</code></pre>` — HTML-decode (`&quot;` → `"`, `&#039;` → `'`, `&amp;` → `&`) then `JSON.parse`
- **Instructions**: everything between `<h2>Instructions</h2>` and the next `<h2>` — treat as free text

#### Write/persist primitive

Mutate all sections **in memory** (a copy of the full body string), then call:
```
updateConfluencePage(cloudId={atlassian_cloud_id}, pageId={confluence_page_id}, body=<full HTML>, contentFormat="html")
```
**One call, whole body.** The MCP auto-increments the version — no `version` param needed, no conflict risk (verified). This replaces section-by-section editing entirely.

When reconstructing sections to write back:
- **Ignore list**: `<ul>` with one `<li><p>item</p></li>` per entry
- **Snoozed table**: `<table><thead><tr><th><p>Item</p></th><th><p>Until</p></th></tr></thead><tbody>…</tbody></table>` — one `<tr>` per row
- **State block**: `<pre><code>` + JSON.stringify(state, null, 2) + `</code></pre>` (no need to HTML-encode — the MCP handles it on write)
- **Digest section header**: `<h2>Digest — YYYY-MM-DD HH:MM ICT</h2>` (replace the old heading)

#### `read_pending_feedback()`

Two sources, both called at run start **before** any writes:

1. **Open inline comments** — comments Harry has highlighted directly on a digest item line:
   ```
   getConfluencePageInlineComments(cloudId={atlassian_cloud_id}, pageId={confluence_page_id},
     resolutionStatus="open", includeReplies=true)
   ```
   Each inline comment has an `inlineCommentProperties.textSelection` — the text the comment is anchored to. Extract the `[item_id]` from that anchored text to identify which item the feedback targets.
   Exclude comments whose `id` is already in `processed_comment_ids` (State), and comments whose body starts with `🤖 Digest:` (the routine's own replies).

2. **Footer comments** — page-level free-text instructions:
   ```
   getConfluencePageFooterComments(cloudId={atlassian_cloud_id}, pageId={confluence_page_id}, includeReplies=true)
   ```
   Exclude comments already in `processed_comment_ids` and routine self-replies (`🤖 Digest:` prefix).

#### `post_bot_reply(comment_id, text)`

- If `comment_id` is an **inline comment**: `createConfluenceInlineComment(cloudId={atlassian_cloud_id}, parentCommentId=comment_id, body="🤖 Digest: " + text, contentFormat="markdown")`
- If `comment_id` is a **footer comment**: `createConfluenceFooterComment(cloudId={atlassian_cloud_id}, pageId={confluence_page_id}, parentCommentId=comment_id, body="🤖 Digest: " + text, contentFormat="markdown")`

Always prefix with `🤖 Digest:` so Harry can distinguish routine output from his own comments.

#### Implementation of each contract operation

- **`read_*`**: parse from the page body read at run start (single `getConfluencePage` call).
- **`write_state(state)`**: update the in-memory State block. Merge carefully — only write keys this skill owns (`last_run`, `seen_slack_saved`, `slack_in_progress`, `processed_comment_ids`). Never drop other skills' keys (`seen_jira`, `seen_confluence_saved`). The full body is written with `persist()` at end of run.
- **`append_ignore(items)`**: add each item as a new `<li><p>item</p></li>` in the in-memory Ignore list section.
- **`upsert_snooze(item, until_date)`**: rebuild the Snoozed table rows in memory (remove expired rows, add/update the target row).
- **`render_digest(items)`**: rewrite the `<h2>Digest — …</h2>` section and everything after it (up to `<h2>State</h2>`) in memory. Items as paragraphs: `<p>🟡 <strong>[item_id]</strong> summary — <a href="…">link</a></p>`, grouped under subheadings `<h3>🔴 Urgent</h3>` / `<h3>🟡 Attention</h3>` / `<h3>🟢 FYI</h3>` as needed. Each item's `[item_id]` is in the text so Harry can anchor an inline comment to it.
- **`persist()`**: call `updateConfluencePage` with the full mutated body. Do this **once** at the very end of the run, after all sections are updated in memory.
- **`clear_feedback()`**: no-op — comment-based feedback is deduped via `processed_comment_ids`. Unlike the old canvas `## Feedback` section, comments cannot (and need not) be deleted. Record the processed comment ID; that is sufficient.

#### State schema

The State `<pre><code>` block holds:

```json
{
  "last_run": "2026-06-20T03:10:00Z",
  "seen_jira": {},
  "seen_slack_saved": [],
  "seen_confluence_saved": [],
  "slack_in_progress": [],
  "processed_comment_ids": []
}
```

| Key | Owner |
|-----|-------|
| `last_run` | Routine (set after all skills complete) |
| `seen_jira` | digest-jira |
| `seen_slack_saved` | digest-slack |
| `seen_confluence_saved` | digest-jira |
| `slack_in_progress` | digest-slack |
| `processed_comment_ids` | routine (`routine-prompt.md` Step 2) — not this skill |

---

## Feedback Processing

Runs at the **start** of each run, before Data Collection, using only the backend contract.

1. **Load** instructions, ignore list, snoozed, State, and pending feedback (`read_pending_feedback()`).
2. **Inline comments** — for each open inline comment not in `processed_comment_ids`:
   - Extract `item_id` from the anchored text (`inlineCommentProperties.textSelection`).
   - Parse the comment body for intent:
     - `ignore` / `done` / `✅` → `append_ignore([item_id])`; add item_id to `ignore_list`
     - `working on it` / `wip` / `👀` → add `item_id` to `slack_in_progress`
     - `tell me more` / `expand` / `:tell-me-more:` → add `item_id` to `deep_dive`
     - `snooze until <date>` / `snooze <N> days` → resolve date, `upsert_snooze(item_id, date)`
     - Unrecognised → `post_bot_reply(comment_id, "didn't understand this instruction — left open: \"<quote>\"")`
   - Record comment ID in `processed_comment_ids` (even for unrecognised — avoids re-replying every run; Harry can close it or leave a clearer follow-up).
3. **Footer comments** — for each open footer comment not in `processed_comment_ids`:
   - Parse for intent:
     - `snooze <key> until <date>` / `snooze <key> <N> days` → resolve date, `upsert_snooze(key, date)`. If "until next Monday" etc., resolve relative to today's date (available in context).
     - `ignore <key>` / `stop showing <key>` → `append_ignore([key])`
     - `tell me more about <id>` / `dig into <id>` → add `id` to `deep_dive`
     - Recognised → record ID in `processed_comment_ids`, reply `🤖 Digest: done — <confirmation>`
     - Unrecognised → `post_bot_reply(comment_id, "didn't understand this instruction — left open: \"<quote>\"")`; record ID in `processed_comment_ids`
4. Hand `ignore_list`, `snooze_list`, `deep_dive`, `slack_in_progress` to Data Collection.

> **Idempotency**: a comment is processed exactly once because its ID is recorded in `processed_comment_ids`. A comment Harry manually resolves in the UI will no longer appear in `resolutionStatus="open"` results — naturally excluded. Never act on a comment ID already in `processed_comment_ids`.

---

## Output format

Console/return output (what the agent reports back, independent of the page render):

```
[emoji] **[#channel or DM from @name]** `[item_id]` @sender — one-line summary — [link]
```

Example:
```
🔴 **DM from @jane** `[dm-jane-a1b2]` — "Can you review the API design before EOD?" — [link]
🟡 **#team-mobile** `[MAKE-121]` @duy — mentioned you in thread about MAKE-121 — [link]
🟢 **#eng-general** `[eng-shawn-9f3c]` @shawn — replied to your thread on spec-driven dev — [link]
```

Also report a short feedback summary when feedback was processed this run, e.g.:
```
🤖 Processed: ignored MAKE-121 (inline comment), snoozed ONEFLARE-3829 until 2026-06-23 (footer), deep-dive PRD-677258 (inline)
```

If nothing to action: `✅ Slack — nothing to action`
