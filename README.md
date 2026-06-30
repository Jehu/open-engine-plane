# Open Engine Plane

Unified skill package for operating Open Engine on top of Plane.

This repository contains the two companion skills that together cover the full Open Engine Plane workflow:

- **`oe-plane-triage`** prepares Backlog issues for agent execution.
- **`oe-plane-runner`** processes ready Plane tasks exactly one work item per run.

The package is intentionally structured as a single repository because triage and execution share the same operating model: Plane work items, routing map, labels, states, comments, receipts, and human-review handling.

## Repository layout

```text
open-engine-plane/
├── README.md
├── skills/
│   ├── oe-plane-runner/
│   │   ├── SKILL.md
│   │   ├── scripts/
│   │   │   ├── plane_queue_helper.sh
│   │   │   └── run_one_queue_check.sh
│   │   └── references/
│   │       ├── plane-api-contract.md
│   │       └── task-writing-guide.md
│   └── oe-plane-triage/
│       ├── SKILL.md
│       └── references/
│           ├── backlog-triage-policy.md
│           └── task-writing-guide.md
├── scripts/
│   └── validate.sh
└── docs/
    └── operating-model.md
```

## Skills

### oe-plane-triage

Use `skills/oe-plane-triage` when a Plane Backlog item is manually created, incomplete, or labeled for task refinement.

The triage skill teaches an agent to inspect Backlog issues, use `needs-agent-triage` as the opt-in signal, validate but not invent agent codes, normalize explicit agent-code titles, improve task descriptions, and make human-required action visible.

### oe-plane-runner

Use `skills/oe-plane-runner` when a target runtime is ready to process the queue.

The runner skill provides deterministic queue checks, Plane API helper commands, route validation, status transitions, receipt comments, and one-work-item-per-run execution discipline.

## Workflow

```text
Raw request / manually created issue
→ oe-plane-triage improves it into an agent-ready task
→ human review or explicit policy promotes it to Agent Todo
→ oe-plane-runner claims and processes exactly one eligible task
```

## Execution gate

`Agent Todo` is the execution gate.

A work item should enter `Agent Todo` only when it has a canonical executable title, valid target agent code, complete enough task body for cold execution, acceptance criteria, boundaries, blocker handling, and output handoff instructions.

Canonical executable title:

```text
[agent instructions][<agent-code>][task] <short outcome>
```

## Plane operations

For actual Plane mutations, runtimes need access to Plane through one of:

- the scripts in `skills/oe-plane-runner/scripts`,
- direct Plane API access,
- a runtime-specific adapter or MCP tool.

The triage skill describes the decision policy; the runner skill contains the portable shell helpers currently used for deterministic Plane operations.

## Validate

From the repository root:

```bash
./scripts/validate.sh
```

The validation script performs static checks only. Plane API operations still require environment configuration.

## Related repositories

This repository supersedes the earlier split package approach:

- https://github.com/Jehu/open-engine-plane-runner
- https://github.com/Jehu/open-engine-task-triage

Those repositories may remain available as historical mirrors or transition artifacts.

## License

No license has been selected yet. Add a license before broad public reuse if needed.
