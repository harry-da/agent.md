---
description: Read Jira and Confluence activity via Atlassian Rovo and return a structured list of items needing the user's attention. Covers assigned issues, recent mentions, items awaiting review, and Confluence saved/bookmarked pages not yet actioned.
allowed-tools:
  - mcp__claude_ai_Atlassian_Rovo__searchJiraIssuesUsingJql
  - mcp__claude_ai_Atlassian_Rovo__getJiraIssue
  - mcp__claude_ai_Atlassian_Rovo__search
  - mcp__claude_ai_Atlassian_Rovo__searchConfluenceUsingCql
argument-hint: "[lookback_hours=12]"
identity:
  email: "harry.nguyen@airtasker.com"
  display_name: "Harry Nguyen"
---

# digest-jira

Read Jira and Confluence activity via Atlassian Rovo and return a structured list of items needing the user's attention.

<!-- COLLECTION:START -->

## Step 0 — Resolve cloudId

Call `getAccessibleAtlassianResources` first and extract the `cloudId` for `airtasker.atlassian.net`. All subsequent JQL and CQL calls require this `cloudId` parameter.

## State inputs (received from the routine)

The routine passes the following from the digest page State before invoking this skill. Use them for suppress/stale rules:

- `last_run` — ISO timestamp of the previous digest run (or `null` on first run)
- `seen_jira` — map of `{ "MAKE-121": "YYYY-MM-DD" }` — first-seen date per key; never removed
- `seen_confluence_saved` — list of Confluence page IDs already recorded

## Jira queries

Run all three; deduplicate by issue key.

**1. Assigned and open**
```jql
assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC
```
Limit 20. ⚠️ JQL responses include full issue descriptions and can exceed inline token limits — if the response is truncated, read the saved tool-result file with `jq '.issues[] | {key, summary, status: .fields.status.name}' <file>`.

For each returned issue, apply **record-all / surface-selectively** rules:

- **Always record** the key to `seen_jira` output with today's date (the routine merges this). Do this regardless of whether the issue is surfaced — future suppression depends on it.
- **Surface the issue** only if any condition holds:
  - Key is **not** in `seen_jira` → 🟡, tag as `(new to digest)`
  - `fields.updated >= last_run` → 🟡 if a comment or mention drove the update; 🟢 for status/label-only changes
  - Issue is blocking another issue or appears in queries #2 or #3 → 🔴/🟡
- **Suppress silently** if: key is already in `seen_jira`, `fields.updated < last_run`, and issue is not blocking.
- **Stale guard**: if `fields.updated` is more than 30 days old and the issue is not blocking, never surface it individually — count it in the roll-up line instead (see Output Format).

On first ever run (`last_run` is null): surface all issues as new, recording them all to `seen_jira`.

**2. Recent mentions** (issues where the user was mentioned in the last 12 hours)
```jql
issue in issueHistory() AND updated >= -1d AND text ~ "{email}" ORDER BY updated DESC
```
Use the `email` from Identity. If that returns no results, fall back to CQL on Confluence side only.

**3. Awaiting the user's input**
```jql
assignee = currentUser() AND statusCategory != Done AND updated >= -3d ORDER BY updated DESC
```
Look for issues where the most recent comment is directed at the user or contains "waiting on", "can you", "LGTM?". Cross-reference against the `display_name` from Identity.

## Confluence queries

**1. Recent mentions** — pages or comments where Harry was @mentioned in the last 12 hours:
```cql
type = page AND mention = currentUser() AND lastmodified >= now("-1d")
```
Only surface results where the user is explicitly @mentioned by name — skip pages returned only because of broad team membership or space following. Honour any "skip Confluence mentions unless directly tagged" Instruction from the digest page.

**2. Saved/bookmarked pages** — pages Harry is watching (persistent, not time-bounded):
```cql
watcher = currentUser() AND type = page ORDER BY lastModified DESC
```
Limit 10. Saved pages are persistent — cross-reference against `seen_confluence_saved` from the digest page State. Only surface page IDs NOT already in that list. Pages watched >7 days ago that are still watched get resurfaced as a reminder.

## Classification

| Condition | Urgency |
|-----------|---------|
| Blocking others, overdue, or explicit "waiting on Harry" | 🔴 |
| New comment/mention needing a response | 🟡 |
| Assigned, in progress, no blockers (FYI) | 🟢 |

## Output Format

```
[emoji] **[TICKET-123]** Issue title — [one-line action] — [link]
```

Example:
```
🔴 **MAKE-121** Add edit profile photo — @jane waiting on review — https://...
🟡 **MAKE-53** Migrate RadioGroup — new comment from @duy — https://...
🟢 **MAKE-6** AI offer generation — in progress, no blockers — https://...
🟢 +3 more assigned tickets — no recent activity — https://airtasker.atlassian.net/jira/your-work
```

For saved Confluence pages:
```
🟡 **[Page title]** (Confluence saved) — [one-line description] — [link]
```

If nothing to action: `✅ Jira/Confluence — nothing to action`

## Return seen IDs

At the end of output, include machine-readable blocks so the routine can update State.

All assigned-open issue keys from query #1 (both surfaced and suppressed):
```
JIRA_SEEN: { "MAKE-83": "2026-06-20", "MAKE-121": "2026-06-20" }
```

All Confluence saved page IDs seen this run:
```
CONFLUENCE_SAVED_SEEN: ["123456", "789012"]
```

<!-- COLLECTION:END -->
