# Open Engine Task Triage

Reusable Agent Skills-compatible instructions for Open Engine triage agents.

This skill teaches a triage/task-refinement agent how to improve manually created Open Engine Backlog issues into agent-ready tasks without executing the underlying work and without guessing the target agent code.

It is intended for runtimes such as:

- Hermes
- Agent Zero
- Claude Code
- any other agent runtime that can consume Agent Skills-style instructions

## What it does

The skill defines how a triage agent should:

- inspect Open Engine Backlog issues,
- use `needs-agent-triage` as an opt-in signal,
- validate but not invent agent codes,
- normalize explicit agent-code titles into the canonical Open Engine format,
- improve descriptions using the Open Engine task-writing standard,
- make human-required action visible with status, labels, assignee/mention, and comments,
- avoid moving work to `Agent Todo` unless all readiness criteria and local policy allow it.

## Key rule

The triage agent improves tasks. It does **not** execute them.

It must not infer or guess the target agent code. If no valid agent code is explicit, it should ask for human input instead.

## Canonical executable title

```text
[agent instructions][<agent-code>][task] <short outcome>
```

Example normalization is allowed only when the agent code is already explicit and valid:

```text
[vps-hermes-default] Set up 30-minute queue check
```

may become:

```text
[agent instructions][vps-hermes-default][task] Set up 30-minute queue check
```

## Files

- [`SKILL.md`](./SKILL.md) — main reusable skill instructions
- [`references/backlog-triage-policy.md`](./references/backlog-triage-policy.md) — compact decision table and issue template
- [`references/task-writing-guide.md`](./references/task-writing-guide.md) — bundled agent-ready task writing guide

## Related Skill: oe-plane-runner

This repository is intentionally separate from [`oe-plane-runner`](https://github.com/Jehu/oe-plane-runner) and is self-contained for triage use.

- [`oe-plane-runner`](https://github.com/Jehu/oe-plane-runner) is the runtime/execution skill. It provides the deterministic Plane queue runner, helper scripts, route validation, status transitions, and receipt handling for agents that process exactly one eligible work item per run.
- `oe-plane-triage` is the intake/refinement skill. It improves Backlog issues before execution, without executing the underlying task and without guessing the target agent code.

Use `oe-plane-triage` before a work item is ready for `Agent Todo`; use `oe-plane-runner` when a target runtime is ready to claim and process a fully specified task.

## Suggested label policy

Recommended labels:

- `needs-agent-triage`: issue may be inspected/refined by a triage agent
- `agent-task`: issue is intended to become executable agent work
- `agent-instructions`: issue contains or should contain runtime instructions
- `requires-human`: human input, decision, approval, or authority is needed

`needs-agent-triage` is an opt-in signal for triage. It is not an execution signal.

## License

Add a license before broad public reuse if needed.
