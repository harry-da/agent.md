# Personal Workflow — Feature Directories & Worktrees

## Feature Directory Convention

All work is organised under `~/Projects/<feature-name>/`. The feature directory ties together all repos, plans, and notes for a given piece of work.

### Structure

```
~/Projects/
  MAKE-31-edit-profile-photo/
    mobile            -> symlink to mobile repo worktree
    rails             -> symlink to rails repo worktree
    api-design.md     (plan — source of truth)
    migration.md      (plan — source of truth)
    notes.md          (optional freeform notes, decisions, scratch)
```

Plan files live at the worktree root.

### Naming

`<feature-name>` follows the same Jira ticket + description convention as branches:

| Work type   | Format                         | Example                         |
|-------------|--------------------------------|---------------------------------|
| Jira ticket | `<TICKET>-<short-description>` | `MAKE-31-edit-profile-photo`    |
| No ticket   | `NT-<short-description>`       | `NT-fix-flaky-login-test`       |

Kebab-case, max 5 words after the ticket prefix. Should match the branch/worktree name.

## Setting Up a Feature Directory

When starting work on a new feature across one or more repos:

1. **Create the feature directory:**
   ```bash
   mkdir -p ~/Projects/<feature-name>
   ```

2. **For each repo, create the worktree** (via `/start-work`) then symlink it:
   ```bash
   ln -s <repo-root>/.claude/worktrees/<branch> ~/Projects/<feature-name>/<repo-name>
   ```

3. **Configure the worktree** — create `.claude/settings.json` in the worktree root:
   ```json
   {
     "autoMemoryDirectory": ".",
     "plansDirectory": "."
   }
   ```
   Memory and plans live at the worktree root, alongside the code.

## Relationship to `.claude/worktrees`

Actual worktree files live at `<repo>/.claude/worktrees/<branch>/` (Claude Code convention). The `~/Projects/<feature-name>/<repo-name>` symlink is a navigation convenience only — Claude sessions and git operations use the worktree path directly.

## Always keep a terse TLDR.md per feature

Every feature directory gets a `TLDR.md` at its root (alongside `plan.md`). Keep it current
as facts, decisions, and actions change. It is the fast-orientation doc — the thing to read
first, and the thing to hand a teammate or a fresh session.

**Format — extremely terse. Bullets and checklists, not prose.** Sections:
- **Goal** — 1-2 lines.
- **Key facts** — the load-bearing facts only (the bug, the constraint, what already exists).
- **Pending decisions** — open questions that block work, as `- [ ]` checkboxes.
- **Actions** — next steps / who-owes-what, as `- [ ]` checkboxes.
- **Links** — primary sources (Confluence/Jira/Figma/Slack), one per line.

No narrative, no restating the plan, no background essays — that's what `plan.md` and the
research docs are for. If a bullet needs a paragraph, it belongs in another doc with a link
from here. Prune stale lines instead of appending.

## Cite sources; flag inference as inference

Every factual claim, recommendation, or "the doc/precedent says X" statement written into a plan, research doc, or summary must be traceable to a specific primary source (a named Confluence page + section, a Jira ticket, a raw meeting transcript, a code file + line) — or explicitly marked as this-agent's-own inference if it isn't.

**Why:** During the NT-decouple-poster-cancellation-fee project, a plan I wrote stated "Recommend a separate feature flag... it lets poster-cancellation-fee ship on AU/GB now" as a flat recommendation with no citation. It was pure inference — no source said this — and when checked against the actual docs, it also cited the wrong precedent (a related-but-distinct doc, MAKE-125, whose flag governs a different layer of the decision than the one being recommended). The right precedent (RVNGR-1294) was sitting one Jira epic away the whole time. A reader (including future-me) can't tell inference from sourced fact unless it's labeled, and derived documents compound this silently — the next plan cites the first plan's confident-sounding line as if it were a source.

**How to apply:**
- Never write "the doc recommends X" or "the precedent is X" without opening the actual doc/ticket/transcript and quoting or pointing at the specific section. Don't rely on a prior summary of the doc (including one written earlier in the same session) — re-check the primary source when the claim matters.
- When two pieces of prior work look similar (e.g. "MAKE-125" and "RVNGR-1287/1294" both touch cancellation fees), don't assume either is the relevant precedent — check which one actually addresses the specific decision at hand. Adjacent-but-different work is a common source of mis-citation.
- If a recommendation is genuinely this agent's own reasoning (no source states it), say so plainly: "Recommendation (not sourced from any doc — my inference by analogy to X):" rather than phrasing it as a flat fact.
- A markdown file this agent wrote earlier (a plan, a research-findings doc, a summary) is a **derived document**, not a source of truth. If asked to verify or re-derive a claim, go back to the primary source it was supposedly based on — don't re-read the derived doc and treat its confident phrasing as confirmation.
- This applies most when the claim will drive a real decision (rollout mechanism, architecture choice, "already done" status) — cheap enough to always do, but especially non-negotiable there.
