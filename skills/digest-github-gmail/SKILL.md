---
description: Read GitHub notification emails from Gmail and return a structured, urgency-tagged list of items needing the user's attention. Covers review requests, comments on your PRs, and CI failures on your PRs. Skips Dependabot and CI noise.
allowed-tools:
  - mcp__claude_ai_Gmail__search_threads
  - mcp__claude_ai_Gmail__get_thread
argument-hint: "[lookback_hours=12]"
identity:
  github_username: "harry-da"
  email: "harry.nguyen@airtasker.com"
---

# digest-github-gmail

Read GitHub notification emails from Gmail and return a structured list of items needing the user's attention.

<!-- COLLECTION:START -->

## Instructions

> ⚠️ **Routing note (2026-06-20):** GitHub notification email delivery to `harry.nguyen@airtasker.com` was configured on 2026-06-20. Until PR activity confirms delivery, an empty result is expected — document as `🔍 GitHub — verifying routing (changed 2026-06-20)` in the digest if no emails are found. Once confirmed, remove this note.

Search Gmail for GitHub notification emails. Default lookback is 12 hours; use `$ARGUMENTS` if provided.

```
from:notifications@github.com is:unread newer_than:12h
```

For each thread, read the subject and snippet. Fetch the full body only when the snippet is insufficient to determine the action needed.

### Include in digest

| Pattern | Category | Urgency |
|---------|----------|---------|
| Subject or snippet contains "requested your review" | Review request | 🔴 |
| Subject starts with `Re:` AND snippet has a comment on a PR you authored | Comment on your PR | 🟡 |
| Subject contains "run failed" AND the PR belongs to you | CI failure (your PR) | 🟡 |
| Snippet contains `@{github_username}` or `{email}` (direct mention) | Mention | 🔴 |

Use `github_username` and `email` from the Identity section above.

### Exclude silently

- Subject matches `chore(deps): bump` — Dependabot, skip
- Subject contains "run failed" but the PR is not yours — CI noise, skip
- `X-GitHub-Sender` is `dependabot[bot]` — skip

The commenter/sender name is in the `From:` header (e.g. `Duy Trinh Duc <notifications@github.com>`) and in the body (e.g. `@duytd requested your review`). Use whichever is available.

## Output Format

Return a markdown list grouped by urgency. Each item:

```
[emoji] **[org/repo#number]** PR title — [action] by @author — [link]
```

Example:
```
🔴 **airtasker/mobile#948** migrate RadioGroup to KMP — review requested by @duytd — https://github.com/airtasker/mobile/pull/948
🟡 **airtasker/mobile#826** edit profile photo — comment by @jane — https://github.com/airtasker/mobile/pull/826
🟡 **airtasker/mobile#826** edit profile photo — CI failed (Unit tests, Build main app) — https://github.com/airtasker/mobile/actions/runs/123
```

If nothing actionable: `✅ GitHub — nothing to action`

<!-- COLLECTION:END -->
