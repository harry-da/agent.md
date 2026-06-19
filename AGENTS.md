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

Each plan file is symlinked back into `~/.claude/plans/` so Claude Code can find it.

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

3. **When creating a plan**, create it at the top level of the feature directory:
   ```bash
   ~/Projects/<feature-name>/<descriptive-name>.md
   ```
   Then symlink it into `~/.claude/plans/` so Claude Code can find it:
   ```bash
   ln -s ~/Projects/<feature-name>/<descriptive-name>.md \
         ~/.claude/plans/<feature-name>-<descriptive-name>.md
   ```
   e.g. `ln -s ~/Projects/MAKE-31-edit-profile-photo/api-design.md ~/.claude/plans/MAKE-31-edit-profile-photo-api-design.md`

## Relationship to `.claude/worktrees`

Actual worktree files live at `<repo>/.claude/worktrees/<branch>/` (Claude Code convention). The `~/Projects/<feature-name>/<repo-name>` symlink is a navigation convenience only — Claude sessions and git operations use the worktree path directly.
