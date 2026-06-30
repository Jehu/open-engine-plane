# Open Engine Plane Operating Model

Open Engine uses Plane as the shared operating surface for agent work.

## Two-phase model

1. **Triage phase**: `oe-plane-triage` improves Backlog issues into agent-ready tasks.
2. **Execution phase**: `oe-plane-runner` processes ready tasks from `Agent Todo`.

## Key separation

- Triage improves task quality and human visibility.
- Runner executes one fully specified task per run.
- Triage must not execute the underlying work.
- Runner must not process ambiguous or incorrectly routed work.

## Human visibility

When human action is required, use visible Plane signals, not comments alone:

- state such as `Agent Needs Input` or `Agent Review`,
- label such as `requires-human`,
- assignee or mention where available,
- one concrete question or review request.

## Routing

Agent execution is gated by the canonical title pattern:

```text
[agent instructions][<agent-code>][task] <short outcome>
```

The target agent code must be explicit and valid in the Plane routing map.
