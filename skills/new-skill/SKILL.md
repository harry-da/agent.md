---
description: Scaffold a new personal skill in ~/agent.md/skills/. Use when asked to create a local skill, make a personal skill, or add a new Claude Code skill.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
argument-hint: "<skill-name> [\"short description of what it does\"]"
---

# new-skill

Scaffolds a new personal skill under `~/agent.md/skills/`. The skill is immediately available
as `/personal:<skill-name>` in the next Claude Code session (the plugin re-reads the local path
each session — no exclude hacks, no team-repo footprint).

Parse `$ARGUMENTS`: the first word is `SKILL_NAME`; everything after the first space (if present)
is `DESCRIPTION`. If no description is given, use `"TODO: describe what this skill does"`.

## Step 1 — Create the skill directory

```bash
mkdir -p ~/agent.md/skills/<SKILL_NAME>
```

## Step 2 — Write the SKILL.md template

Write the following to `~/agent.md/skills/<SKILL_NAME>/SKILL.md`, substituting `SKILL_NAME`
and `DESCRIPTION`:

```
---
description: <DESCRIPTION>
allowed-tools:
  - Bash
  - Read
argument-hint: "<required-arg> [optional-arg]"
---

# <SKILL_NAME>

TODO: Write the skill instructions here. Structure as numbered steps.
Each step should be a concrete action Claude will take when the skill is invoked.

## Step 1 — ...

## Step 2 — ...
```

## Step 3 — Commit

```bash
cd ~/agent.md && git add skills/<SKILL_NAME>/ && git commit -m "feat(skills): add <SKILL_NAME>"
```

## Step 4 — Confirm

```bash
ls ~/agent.md/skills/<SKILL_NAME>/
```

The SKILL.md should be listed. Start a new Claude Code session and invoke `/personal:<SKILL_NAME>`
to activate it.

---

**Trade-off:** This skill is personal — it lives in `~/agent.md` (not shared). To share a skill
with teammates, contribute it to `airtasker/claude-plugins` instead.
