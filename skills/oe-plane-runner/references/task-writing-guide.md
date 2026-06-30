# Agent-Ready Task Writing Guide

Skill name: agent-ready-task-writing-guide
Version: 1.0
Specification: https://agentskills.io/specification
Last updated: 2026-06-29

## What this skill teaches

How to write tasks that any Open Engine agent can process cold — without prior conversation context, without guessing, without follow-up questions that could have been answered upfront.

## Why it matters

Most agent failures are not model-intelligence failures. They are task-writing failures:
- Missing sources
- Unclear boundaries
- No acceptance criteria
- Vague desired outcomes

A well-written task takes 2 minutes longer to create and saves 20 minutes of back-and-forth.


## Local installation

This guide is intended to be installed or adapted as an Agent Skills compatible skill body.

The canonical specification is:

https://agentskills.io/specification

Each runtime is responsible for choosing its own supported local skill location and adaptation mechanism. This guide deliberately does not prescribe runtime-specific paths for Agent Zero, Codex, Claude Code, Hermes, or other systems.

Required skill identity:

- name: `agent-ready-task-writing-guide`
- version: `1.0`
- format: Agent Skills compatible `SKILL.md` or an equivalent runtime-supported adaptation

After local installation or adaptation, the runtime should post `AGENT APPLIED` on the corresponding Standing Skill issue.

## The 7-part task record

Every agent-ready task should contain these parts. If a part is not needed, say so explicitly.

### 1. Requester

Who is asking, and who has authority to approve changes.

**Good:** `Marco Michely — operator of local-a0-developer`
**Bad:** `me`

### 2. Desired outcome

The concrete, observable result that should exist when the task is done.

**Good:** `Add a rollback section to the plugin installer docs at /a0/usr/workdir/a0-plugins/README.md`
**Bad:** `improve the docs`

### 3. Sources

Which files, links, issues, docs, or APIs are authoritative for this task.

**Good:**
```
- /a0/usr/workdir/a0-plugins/README.md (current docs)
- /a0/usr/workdir/a0-plugins/install.sh (installer script)
- https://docs.example.com/plugin-rollback-patterns
```
**Bad:** `the usual files`

### 4. Acceptance criteria

Observable, checkable conditions that prove the task is done.

**Good:**
```
- README.md contains a section titled "Rollback"
- Section mentions backup before install
- Section mentions how to revert a failed install
- No code changes outside docs
```
**Bad:** `looks good`

### 5. Boundaries

What the agent may do freely, what needs approval, and what is out of scope.

**Good:**
```
May: edit README.md, read install.sh
Needs approval: push to remote, open PR, publish
Out of scope: change installer code, modify other files
```
**Bad:** (nothing — agent guesses what is allowed)

### 6. Blocker rule

What the agent should do when information is missing.

**Good:** `If the rollback pattern is unclear, leave AGENT BLOCKED with one specific question on this issue.`
**Bad:** (nothing — agent either guesses or stops silently)

### 7. Output handoff

Where the result should go: a comment, a file, a PR, a status update.

**Good:** `Comment on this issue with changed file paths and a summary of what was added.`
**Bad:** `send it to me`

## Title pattern

Every task follows this title pattern:
```
[agent instructions][<agent-code>][task] <short outcome>
```

Examples:
```
[agent instructions][local-a0-developer][task] Add rollback section to plugin docs
[agent instructions][local-a0-researcher][task] Find three citations for agent handoff patterns
[agent instructions][local-a0-default][task] Review and summarize weekly queue status
```

## Good vs bad task: a full example

### Bad task

```
Title: [agent instructions][local-a0-developer][task] fix the login
Description: the login page is broken, can you look at it?
```

Problems: no sources, no acceptance criteria, no boundaries, vague outcome, no blocker rule.

### Good task

```
Title: [agent instructions][local-a0-developer][task] Fix session timeout error on login page

Requester: Marco Michely

Desired outcome:
The login page at src/auth/login.html no longer shows "Session timeout" when a user
logs in within 30 seconds of page load.

Sources:
- src/auth/login.html (login page)
- src/auth/session.py (session handler)
- Issue #42 (original bug report)

Acceptance criteria:
- Login works when page load to submit is under 30 seconds
- No console errors on successful login
- Existing session tests still pass

Boundaries:
May: edit src/auth/login.html and src/auth/session.py
Needs approval: deploy to production, change auth library version
Out of scope: UI redesign, password reset flow

Blocker rule:
If the root cause is in the auth library itself (not our code), leave AGENT BLOCKED
with the specific error and which library function is suspected.

Output handoff:
Comment on this issue with the root cause, the fix, changed files, and test results.
```

## Quick checklist for task writers

Before creating an agent task, check:

- [ ] Title follows `[agent instructions][<agent-code>][task] <outcome>`
- [ ] Desired outcome is concrete and observable
- [ ] Sources list specific files, links, or issue IDs
- [ ] Acceptance criteria are checkable (not vibes)
- [ ] Boundaries say what needs approval
- [ ] Blocker rule says what to do when stuck
- [ ] Output handoff says where the result goes

If any of these are missing, the agent will either guess (risky) or block (slow).
