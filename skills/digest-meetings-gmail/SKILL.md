---
description: Read Google Meet auto-generated notes emails from Gmail and return meeting summaries plus any action items assigned to the user. Covers meetings from the last N hours (default 12).
allowed-tools:
  - mcp__claude_ai_Gmail__search_threads
  - mcp__claude_ai_Gmail__get_thread
  - mcp__claude_ai_Google_Drive__read_file_content
argument-hint: "[lookback_hours=12]"
identity:
  display_name: "Harry Nguyen"
---

# digest-meetings-gmail

Read Google Meet auto-generated notes emails from Gmail and return a structured summary of meetings and action items assigned to the user.

<!-- COLLECTION:START -->

## Instructions

Search Gmail for meeting notes emails. Default lookback is 12 hours; use `$ARGUMENTS` if provided.

```
subject:"Notes:" newer_than:12h
```

These emails follow a consistent format:
- **Subject**: `Notes: '<Meeting Name>' <Date>` or `Notes: "<Meeting Name>" <Date>` — handle both single and double quotes around the name
- **Body**: Summary paragraph → per-topic sections → "Suggested next steps" with assignees in `[Name]` brackets
- **Google Doc link**: Full transcript (do NOT fetch unless instructed via pinned channel instructions)

For each email:
1. Extract the meeting name from the subject
2. Extract the one-paragraph **Summary** from the plaintext body
3. Extract all **Suggested next steps** — surface those assigned to `[{display_name}]` or `[The group]`. Use `display_name` from the Identity section above.
4. Note the meeting date/time

## Output Format

```
📋 **[Meeting Name]** — [date]
[One-sentence summary]
Your action items:
  → [Name] [action text]
```

If no action items assigned to Harry, still include the meeting with summary but omit the action items section.

If no meeting notes found: `✅ Meetings — no notes in the last Xh`

<!-- COLLECTION:END -->
