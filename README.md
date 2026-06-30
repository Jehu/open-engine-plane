# Open Engine for Plane

Open Engine is an operating model for coordinating AI agents through a shared work queue instead of relying on one long chat thread. Work is written down as explicit tasks, routed to a named agent/runtime, processed in small auditable steps, and handed back with receipts that humans and other agents can inspect later.

The core idea is simple:

1. **Humans or agents create work items** in a shared system of record.
2. **Triage turns rough requests into agent-ready tasks** with outcome, sources, acceptance criteria, boundaries, blocker rules, and handoff instructions.
3. **A target runtime claims exactly one ready task**, does only the scoped work, and leaves a clear receipt.
4. **Humans stay in control** through review states, visible blockers, labels, and explicit approval gates.

This repository implements that model on top of **[Plane](https://plane.so)**. Plane provides the shared operating surface: Backlog, task states, labels, comments, routing map, status ledger, and human review. The scripts and skills in this repo define how agents should prepare, claim, process, block, review, and complete that work without guessing hidden context.

## Attribution

The **Open Engine** operating idea is credited to **[Nate B. Jones](https://substack.com/@natesnewsletter)**. His Substack article **["AI Agent Handoffs"](https://natesnewsletter.substack.com/p/ai-agent-handoffs)** explains the handoff model that inspired this package. This README summarizes the practical idea so the repository is understandable even without access to the article.

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
│   ├── bootstrap_workspace.sh
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

## Bootstrap a Plane workspace

Use `scripts/bootstrap_workspace.sh` to prepare an existing empty Plane workspace for Open Engine. The script creates or reuses the `Open Engine` project, required Agent states, labels, standing work items, routing map, core context, and an optional smoke-test item.

```bash
# Preview without Plane API writes or secrets
./scripts/bootstrap_workspace.sh --dry-run

# Real setup using environment variables
PLANE_SECRETS_FILE=/path/to/plane.env ./scripts/bootstrap_workspace.sh

# Custom routes
OPEN_ENGINE_ROUTES="local-a0-default,vps-hermes-scheduler" ./scripts/bootstrap_workspace.sh --no-smoke
```

The script never prints token values. Do not commit `.env`, `secrets.env`, API tokens, or private keys.

## Validate

From the repository root:

```bash
./scripts/validate.sh
```

The validation script performs static checks only. Plane API operations still require environment configuration.

## Package status

This repository is the canonical package for Open Engine Plane skills. Runtime and triage capabilities are maintained together here so shared Plane API, routing, state, label, and receipt behavior can evolve consistently.

## License

No license has been selected yet. Add a license before broad public reuse if needed.
