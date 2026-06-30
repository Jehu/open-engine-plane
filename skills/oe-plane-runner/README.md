# Open Engine Plane Runner

Portable Open Engine runtime skill for processing exactly one Plane work item per run.

This repository contains the installable skill body, deterministic helper scripts, and reference docs for a Plane-backed Open Engine queue. Plane remains the shared operating surface for queue items, routing, receipts, and the status ledger; this Git repository packages the local/runtime skill implementation.

## Contents

```text
open-engine-plane-runner/
├── SKILL.md
├── scripts/
│   ├── plane_queue_helper.sh
│   └── run_one_queue_check.sh
└── references/
    ├── plane-api-contract.md
    └── task-writing-guide.md
```

## Requirements

Runtime host requirements:

- Bash
- `curl`
- `jq`
- access to the Plane API
- a Plane workspace/project configured for Open Engine

The scripts do not contain secrets. Provide credentials through environment variables, or optionally through a file named by `PLANE_SECRETS_FILE`. There is no hardcoded secrets path.

Required configuration:

```bash
export PLANE_API_TOKEN='...'
export PLANE_WORKSPACE_SLUG='...'
# Optional; defaults to https://api.plane.so if unset by the helper
export PLANE_API_BASE_URL='https://api.plane.so'
```

Alternatively, set:

```bash
export PLANE_SECRETS_FILE=/path/to/secrets.env
```

The secrets file should define the same variables. If `PLANE_SECRETS_FILE` is unset, the helper uses only the current environment.

## Runtime model

### Runtime identity configuration

Each runtime must know its Agent Code before running the queue check. You can provide it either as a CLI argument or as an environment variable.

Recommended for scheduled or hosted runtimes such as Hermes:

```bash
export OPEN_ENGINE_AGENT_CODE=vps-hermes-scheduler
./scripts/run_one_queue_check.sh
```

Recommended for manual testing:

```bash
./scripts/run_one_queue_check.sh local-a0-developer
```

Precedence:

```text
1. explicit CLI argument
2. OPEN_ENGINE_AGENT_CODE environment variable
3. error if neither is provided
```

The Agent Code is validated against the Plane routing map before any work is processed.

Each runtime has a stable Agent Code defined in the Plane routing map, for example:

```text
local-a0-default
local-a0-developer
local-a0-researcher
vps-hermes-scheduler
vps-hermes-marketer
```

A runtime processes only tasks whose title matches:

```text
[agent instructions][<agent-code>][task] <short outcome>
```

## Creating work items

Open Engine work usually flows through four stages:

```text
Idea / request
→ Intake or draft work item
→ agent-ready task record
→ Agent Todo
→ runner processes exactly one item
```

### Who may create work items?

Both humans and agents may create work items, but they should not all mean the same thing.

| Action | Recommended owner |
|---|---|
| Create a raw intake/draft item | Human or agent |
| Convert a raw request into an agent-ready task | Human or trusted triage agent |
| Choose the target Agent Code | Human or trusted triage agent |
| Move the item to `Agent Todo` | Human at first; later a trusted triage agent |
| Claim and process the task | Target runtime only |
| Create delegated/follow-up work | Agent, within the task boundaries |

The key rule is:

> `Agent Todo` is the execution gate. A task should enter `Agent Todo` only when a fresh runtime can process it without prior chat context.

### Agent-ready task format

A work item is agent-ready when its body contains, or explicitly marks as not needed, these seven parts:

1. Requester
2. Desired outcome
3. Sources
4. Acceptance criteria
5. Boundaries
6. Blocker rule
7. Output handoff

Example title:

```text
[agent instructions][local-a0-developer][task] Test Hermes with exported Open Engine skill
```

Example body:

```markdown
## Requester
Marco Michely

## Desired outcome
Verify that Hermes can clone this skill repository, load Plane credentials, and run one queue check.

## Sources
- https://github.com/Jehu/open-engine-plane-runner
- /opt/data/.env on the Hermes host

## Acceptance criteria
- Repository clones successfully
- `bash -n scripts/*.sh` passes
- `run_one_queue_check.sh <agent-code>` returns valid JSON
- No task is processed unless the route is valid in the Plane routing map

## Boundaries
May: read repo files, run helper scripts, call Plane API
Needs approval: changing scheduler, publishing, deleting tasks, modifying credentials
Out of scope: changing production code outside this skill

## Blocker rule
If Plane credentials are missing or invalid, leave `AGENT BLOCKED` with the exact missing variable or failing check.

## Output handoff
Comment on the Plane work item with commands run, result JSON, and any required follow-up.
```

### Practical operating modes

#### Mode A: Human-created task

A human writes an agent-ready task and moves it to `Agent Todo`. This is the safest starting mode.

#### Mode B: Agent-assisted triage

A human gives a rough request. A triage runtime, commonly `local-a0-default`, turns it into an agent-ready task, asks clarifying questions if needed, and proposes a route. The human approves by moving it to `Agent Todo`.

#### Mode C: Agent-created follow-up or delegation

A worker runtime may create follow-up or delegated tasks when the current task boundaries allow it. Delegation should leave `AGENT DELEGATED`; later status changes should be tracked with `AGENT FOLLOW-UP`.

Agents should not create arbitrary work for themselves and immediately execute it unless your local policy explicitly allows that.

## Normal usage

Run exactly one queue check with an explicit Agent Code:

```bash
./scripts/run_one_queue_check.sh local-a0-developer
```

Or set the Agent Code once in the runtime environment:

```bash
export OPEN_ENGINE_AGENT_CODE=local-a0-developer
./scripts/run_one_queue_check.sh
```

Precedence is: explicit CLI argument first, then `OPEN_ENGINE_AGENT_CODE`, then error.

The runner returns one JSON action, such as:

- `no_work`
- `process_new_task`
- `recover_working_task`
- `resume_paused_task`
- `inspect_paused_task`

Each runner response includes a `preflight` object with standing-context hashes and `local_skill_hashes`, for example `preflight.local_skill_hashes["SKILL.md"]`.

If the action is `process_new_task`, inspect the work item, run the returned `claim_command`, do the scoped work, then finish with exactly one terminal helper command:

```bash
./scripts/plane_queue_helper.sh claim local-a0-developer 123
./scripts/plane_queue_helper.sh done local-a0-developer 123 'Completed scoped work.'
```

Other terminal paths:

```bash
./scripts/plane_queue_helper.sh block local-a0-developer 123 'Question that belongs on the Plane item.'
./scripts/plane_queue_helper.sh hold local-a0-developer 123 'Private operator approval needed.'
./scripts/plane_queue_helper.sh review local-a0-developer 123 'Done, needs human review.'
./scripts/plane_queue_helper.sh fail local-a0-developer 123 'Unrecoverable failure details.'
```

## Related Skill: open-engine-task-triage

[`open-engine-task-triage`](https://github.com/Jehu/open-engine-task-triage) is the companion intake/refinement skill for Open Engine Backlog issues. It teaches a triage agent how to improve manually created issues into agent-ready tasks without executing the underlying work and without guessing the target agent code.

Use `open-engine-task-triage` when a Backlog item needs clearer requester, desired outcome, sources, acceptance criteria, boundaries, blocker rule, output handoff, or visible human-review handling. Use `open-engine-plane-runner` after the issue is fully specified, has a valid canonical title, and is ready for a target runtime to process through the Plane queue.

In short:

- `open-engine-task-triage` prepares Backlog issues for execution.
- `open-engine-plane-runner` executes ready Plane tasks one item per run.

## Standing Skill example

`references/task-writing-guide.md` is a human-readable example of a Standing Skill body. It follows the Agent Skills specification:

https://agentskills.io/specification

The corresponding Plane Standing Skill issue should coordinate skill identity, version, changelog, and `AGENT APPLIED` receipts. It should not prescribe runtime-specific local installation paths.

## Safety rules

- Process at most one work item per run.
- Never process unknown agent routes in production.
- Never claim success unless the helper verifies the final state.
- Never publish, email, deploy, delete, change billing, change credentials, or make outward-facing changes without explicit approval in the work item.
- Use `AGENT HUMAN HOLD` only when the answer belongs in a private operator/runtime thread.

## Validation

From the repository root:

```bash
bash -n scripts/plane_queue_helper.sh
bash -n scripts/run_one_queue_check.sh
./scripts/plane_queue_helper.sh routes
./scripts/run_one_queue_check.sh local-a0-default
```

## License

No license has been selected yet. Add a license before publishing outside your private environment.
