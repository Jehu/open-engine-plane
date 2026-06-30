# Plane API Contract for Open Engine

Use this reference after loading `oe-plane-runner` and before making Plane API changes.

## Authentication

Load configuration from environment variables, or optionally from the file named by `PLANE_SECRETS_FILE`.

Required variables:

- `PLANE_API_TOKEN`
- `PLANE_WORKSPACE_SLUG`
- optional `PLANE_API_BASE_URL`, default `https://api.plane.so`

Use headers:

- `X-API-Key: $PLANE_API_TOKEN`
- `x-workspace-slug: $PLANE_WORKSPACE_SLUG`
- `Accept: application/json`
- `Content-Type: application/json` for POST/PATCH

Never print token values.

## Core endpoints

Use Plane Cloud API base `https://api.plane.so` unless `PLANE_API_BASE_URL` overrides it.

- Projects: `GET /api/v1/workspaces/{workspace_slug}/projects/`
- Work items list: `GET /api/v1/workspaces/{workspace_slug}/projects/{project_id}/work-items/?expand=state,labels`
- Work item detail: `GET /api/v1/workspaces/{workspace_slug}/projects/{project_id}/work-items/{work_item_id}/?expand=state,labels`
- Work item update: `PATCH /api/v1/workspaces/{workspace_slug}/projects/{project_id}/work-items/{work_item_id}/`
- Work item comments: `GET|POST /api/v1/workspaces/{workspace_slug}/projects/{project_id}/work-items/{work_item_id}/comments/`
- States: `GET /api/v1/workspaces/{workspace_slug}/projects/{project_id}/states/`
- Labels: `GET /api/v1/workspaces/{workspace_slug}/projects/{project_id}/labels/`

The older `/issues/` endpoints may also work, but prefer `/work-items/`.

Many Plane list endpoints, including comments and activities, return paginated objects with a `results` array rather than a raw JSON array. Always parse `(.results // .)` when handling list responses.

## Existing Open Engine project

Find project by name `Open Engine` or identifier `OE`.

Known setup:

- Workspace slug: from secrets file
- Project name: `Open Engine`
- Project identifier: `OE`
- Current known project id: `1e33b040-9ec2-47a6-9071-8dbb858be605`

Do not rely on the known id unless verification confirms it still exists.

## Required states

Resolve state IDs by name before patching status:

- `Agent Todo`
- `Agent Working`
- `Agent Needs Input`
- `Agent Review`
- `Agent Done`
- `Agent Failed`

Plane also has default states such as `Backlog`, `Todo`, `In Progress`, `Done`, and `Cancelled`. Do not create a separate `Triage` state; use Plane's existing Triage/Intake/Backlog concept for incoming unclear work.

## Required labels

Resolve label IDs by name when creating test work items:

- `agent-instructions`
- `agent-standing`
- `agent-task`
- `requires-human`
- `requires-repo`
- `requires-browser`
- `agent-smoke-test`

## Eligibility filter

A new task is eligible only if all are true:

1. State name is `Agent Todo`.
2. Label list includes `agent-instructions`.
3. Title starts with `[agent instructions][<agent-code>][task]`.
4. It is not archived/deleted/draft.

Sort eligible items by oldest sequence id or oldest creation time and process exactly one.

## Status update contract

To move a work item, PATCH:

```json
{"state":"<state_uuid>"}
```

After every state PATCH:

1. Re-read the work item detail with `?expand=state,labels`.
2. Resolve the returned state name.
3. Continue only if the status name matches the intended state.
4. If verification fails, leave `AGENT FAILED` if comments are available, update ledger if possible, and stop.

Never report a state transition as successful without verification.

## Receipt comment format

Create receipt comments on the task work item. Use compact plain text/HTML. Include the exact receipt token as the first line.

Preferred plain text body shape:

```text
AGENT CLAIMED
Agent: <agent-code>
At: <ISO8601 UTC timestamp>
Runtime: <runtime name>
Claimed for one-run Open Engine queue check.
```

```text
AGENT DONE
Agent: <agent-code>
At: <ISO8601 UTC timestamp>
Changed: Plane comments and status only.
Checks: Re-read status verified as Agent Done.
Needs human: none.
```

For blocker states:

```text
AGENT BLOCKED
Agent: <agent-code>
At: <ISO8601 UTC timestamp>
Question: <one specific question answerable on this Plane work item>
```

```text
AGENT HUMAN HOLD
Agent: <agent-code>
At: <ISO8601 UTC timestamp>
Question: <one specific question that belongs in the human's agent thread/app>
Reason: <permission/install/account/private-context/external-approval>
```

## Ledger format

On work item `#1` status ledger, add or update an `AGENT STATUS` comment.

The helper updates one status comment in place per agent and prunes duplicate status comments for that same agent. Do not append extra status comments during normal operation.

```text
AGENT STATUS
Agent: <agent-code>
Human/operator: Marco
Runtime: Agent Zero or assigned runtime
Automation: manual
Automation state: manual-required
Last heartbeat: <ISO8601 UTC timestamp>
Last queue result: <checking | none | claimed #N | completed #N | blocked #N | holding #N | failed #N>
Last successful run: <ISO8601 UTC timestamp or unknown>
Local context: Open Engine v1; routing map v1
Notes: <none or short blocker>
```

## Delegation and follow-up receipts

When an agent delegates work to another agent:

```text
AGENT DELEGATED
Agent: <source-agent>
At: <ISO8601 UTC timestamp>
Target agent: <target-agent>
Delegated issue: #<child-seq>
Parent issue: #<parent-seq>
Task: <delegated task title>
```

When a source agent observes that a delegated issue has reached a terminal or review state:

```text
AGENT FOLLOW-UP
Agent: <source-agent>
At: <ISO8601 UTC timestamp>
Delegated issue: #<seq>
Observed status: Agent Done | Agent Review | Agent Failed
Summary: Delegated work changed to terminal/review state.
```

Helper commands for delegation:

- `delegate <source-agent> <target-agent> <parent-seq-or-id> <delegated-task-title>`
- `follow-up <source-agent>` checks all delegated tasks for this source agent and posts `AGENT FOLLOW-UP` on issues that reached terminal/review status without an existing follow-up receipt.
- `delegated <source-agent>` lists delegated tasks created by this agent.

## Standing preflight

`preflight <agent>` returns a compact JSON snapshot of standing-context hashes and versions:

- routing map hash (from `description_stripped` of routing map issue)
- core context hash
- local skill/reference/helper/runner file hashes (first 16 chars of SHA-256)
- version labels: engine, routing map, core context, runner

This allows a runtime or human to detect standing-context changes across runs without re-reading full standing issues every time.

## Review path

`review <agent> <seq> [message]` is the helper command for work that is complete but requires human judgment:

1. Verifies the item is `Agent Working`.
2. Leaves `AGENT DONE` with the result message.
3. Moves to `Agent Review` and verifies.
4. Updates ledger with `completed #N` and a review note.

## Smoke-test rule

For a task titled `Say hello from the queue`, there is normally no missing information. The correct successful path is:

1. Move to `Agent Working` and verify.
2. Leave `AGENT CLAIMED`.
3. Re-read task.
4. Leave a short hello/proof comment or include it in `AGENT DONE`.
5. Move to `Agent Done` and verify.
6. Leave/update ledger result as `completed #N`.
7. Stop.

Do not use `AGENT HUMAN HOLD` for the smoke-test `If blocked` section unless there is an actual missing permission or private-context question.

## Description formatting

For work item descriptions, set only compact one-line `description_html`.

Do not set `description_stripped`; Plane generates it from `description_html`. This was verified in the `Open Engine` project by creating a temporary work item with only `description_html` and reading back a populated `description_stripped`.

Avoid newlines between HTML tags because Plane's editor can render them as extra blank lines.

## Claim concurrency lesson

A pre-fix concurrency test on Work Item #14 showed that two parallel helper `claim` calls could both move/read the item as `Agent Working` and both write `AGENT CLAIMED`. This produced duplicate claims and proves that a naive status PATCH is not sufficient as an atomic lock.

Current local helper mitigation:

- Serialize claim attempts per Plane work item id with a local `flock` file under `/tmp/open_engine_plane_claim_locks/`.
- Before writing `AGENT CLAIMED`, re-read the work item and require `state == Agent Todo`.
- Count existing `AGENT CLAIMED` comments using the paginated Plane comments shape `(.results // .)` and require `claimed_count == 0`.
- If either precondition fails, return JSON `{ok:false,error:"claim_conflict",...}` and exit non-zero without writing another receipt.

Verified post-fix on Work Item #15: two concurrent claim attempts produced exactly one successful `AGENT CLAIMED`; the other returned `claim_conflict` with state `Agent Working` and `claimed_count:1`.

Limitation: local `flock` protects concurrent helper processes on the same host/container. Distributed multi-host runners still need a Plane-side atomic compare-and-set mechanism, an external shared lock, or a stronger claim protocol.

## Status ledger update-in-place

`plane_queue_helper.sh ledger <agent> <result> [notes]` must maintain at most one `AGENT STATUS` comment per agent in the Status Ledger work item. The helper finds existing ledger comments whose stripped text starts with `AGENT STATUS` and contains the exact line `Agent: <agent>`, patches the newest matching comment, and prunes older duplicates for that agent. This prevents ledger comment spam while preserving one current heartbeat/status record per runtime.

## Routing validation

`plane_queue_helper.sh` treats the Plane Routing Map work item as the canonical source for valid production agent routes. The helper extracts route codes from the `Production routes` section of `[agent instructions][all agents][standing_routing] Open Engine routing map` until `Routing policy`.

Commands:

- `routes` returns `{routes:[...]}`.
- `validate-route <agent-code>` returns `{ok:true,...}` for known production routes or `{ok:false,error:"unknown_agent_route",valid_routes:[...]}` for unknown routes.

Agent-scoped commands call `require_valid_agent` before doing work. Unknown agent routes exit with code `4` and do not read/process tasks or write Plane changes. This applies to `next`, `working`, `paused`, `ledger`, `create-smoke`, `create-blocked-test`, `create-human-hold-test`, `claim`, `done`, `block`, `hold`, `resume`, `resume-hold`, and `fail`.

For intentional protocol tests with temporary agent codes, set `OPEN_ENGINE_ALLOW_UNKNOWN_AGENT=1` explicitly. Production runs should not use this override.


## Assignee / operator filter

The helper resolves the current operator UUID automatically via `GET /api/v1/users/me/`.
Override with `OPEN_ENGINE_OPERATOR_UUID=<uuid>` if needed.

`next`, `working`, and `paused` filter results by assignee when a UUID is resolved.
When no UUID is available (e.g. API key without user context), the filter is skipped (solo-compatible).

New command:
- `assignee-check`: prints the resolved operator UUID.

Compact item output now includes `assignees` array.
