#!/usr/bin/env bash
set -euo pipefail

# Bootstrap an existing Plane workspace into a fully usable Open Engine workspace.
# The script is idempotent for matching assets: it reuses existing project,
# states, labels, and standing work items when names already exist.
# It never prints secret values.

API_BASE="${PLANE_API_BASE_URL:-https://api.plane.so}"
API_BASE="${API_BASE%/}"
PROJECT_NAME="${PLANE_PROJECT_NAME:-Open Engine}"
PROJECT_IDENTIFIER="${PLANE_PROJECT_IDENTIFIER:-OE}"
HUMAN_OPERATOR="${OPEN_ENGINE_HUMAN_OPERATOR:-Open Engine operator}"
ROUTES_RAW="${OPEN_ENGINE_ROUTES:-local-a0-default,local-a0-developer,local-a0-researcher,vps-hermes-scheduler,vps-hermes-marketer}"
CREATE_SMOKE="${OPEN_ENGINE_CREATE_SMOKE:-1}"
DRY_RUN="${OPEN_ENGINE_DRY_RUN:-0}"
list_expr='(.results // .)'

usage() {
  cat <<USAGE
Usage: $0 [--dry-run] [--no-smoke] [--help]

Prepare an existing Plane workspace for Open Engine.

Required environment for real execution:
  PLANE_API_TOKEN
  PLANE_WORKSPACE_SLUG

Optional environment:
  PLANE_API_BASE_URL              default: https://api.plane.so
  PLANE_PROJECT_NAME              default: Open Engine
  PLANE_PROJECT_IDENTIFIER        default: OE
  OPEN_ENGINE_ROUTES              comma/newline separated agent codes
  OPEN_ENGINE_HUMAN_OPERATOR      default: Open Engine operator
  OPEN_ENGINE_CREATE_SMOKE        default: 1
  OPEN_ENGINE_DRY_RUN             default: 0
  PLANE_SECRETS_FILE              optional env file to source

Examples:
  ./scripts/bootstrap_workspace.sh --dry-run
  PLANE_SECRETS_FILE=.env ./scripts/bootstrap_workspace.sh
  OPEN_ENGINE_ROUTES="local-a0-default,vps-hermes-scheduler" ./scripts/bootstrap_workspace.sh --no-smoke
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --no-smoke) CREATE_SMOKE=0 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

json_array_from_routes() {
  printf '%s\n' "$ROUTES_RAW" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | awk 'NF && !seen[$0]++' \
    | jq -R . \
    | jq -s .
}

require_tools() {
  command -v curl >/dev/null || { echo "ERROR: curl missing" >&2; exit 2; }
  command -v jq >/dev/null || { echo "ERROR: jq missing" >&2; exit 2; }
}

dry_run_plan() {
  local routes_json
  routes_json=$(json_array_from_routes)
  jq -n \
    --arg api_base "$API_BASE" \
    --arg workspace "${PLANE_WORKSPACE_SLUG:-<required-for-real-run>}" \
    --arg project_name "$PROJECT_NAME" \
    --arg project_identifier "$PROJECT_IDENTIFIER" \
    --arg human_operator "$HUMAN_OPERATOR" \
    --argjson routes "$routes_json" \
    --arg create_smoke "$CREATE_SMOKE" \
    '{ok:true,dry_run:true,api_base:$api_base,workspace:$workspace,project:{name:$project_name,identifier:$project_identifier},human_operator:$human_operator,routes:$routes,will_create_or_reuse:{project:true,states:["Agent Todo","Agent Working","Agent Needs Input","Agent Review","Agent Done","Agent Failed"],labels:["agent-instructions","agent-standing","agent-task","needs-agent-triage","requires-human","requires-repo","requires-browser","agent-smoke-test"],standing_items:["Open Engine status ledger","Open Engine routing map","Open Engine core context v1"],smoke_item:($create_smoke=="1")}}'
}

load_secrets_and_require_env() {
  if [[ -n "${PLANE_SECRETS_FILE:-}" ]]; then
    if [[ ! -f "$PLANE_SECRETS_FILE" ]]; then
      echo "ERROR: PLANE_SECRETS_FILE not found: $PLANE_SECRETS_FILE" >&2
      exit 2
    fi
    set -a
    # shellcheck disable=SC1090
    . "$PLANE_SECRETS_FILE"
    set +a
  fi
  : "${PLANE_API_TOKEN:?PLANE_API_TOKEN missing}"
  : "${PLANE_WORKSPACE_SLUG:?PLANE_WORKSPACE_SLUG missing}"
  WS="$PLANE_WORKSPACE_SLUG"
  AUTH=(-H "X-API-Key: $PLANE_API_TOKEN" -H "x-workspace-slug: $WS" -H "Accept: application/json")
  AUTH_JSON=(-H "X-API-Key: $PLANE_API_TOKEN" -H "x-workspace-slug: $WS" -H "Accept: application/json" -H "Content-Type: application/json")
}

log() { printf '%s\n' "$*" >&2; }
api_get() { curl -fsS --retry 4 --retry-delay 2 --retry-all-errors "${AUTH[@]}" "$API_BASE$1"; }
api_post() { curl -fsS --retry 4 --retry-delay 2 --retry-all-errors -X POST "${AUTH_JSON[@]}" --data "$2" "$API_BASE$1"; }

project_json() { api_get "/api/v1/workspaces/$WS/projects/"; }
states_json() { api_get "/api/v1/workspaces/$WS/projects/$PROJ_ID/states/"; }
labels_json() { api_get "/api/v1/workspaces/$WS/projects/$PROJ_ID/labels/"; }
items_json() { api_get "/api/v1/workspaces/$WS/projects/$PROJ_ID/work-items/?expand=state,labels"; }

project_id_or_empty() {
  project_json | jq -er --arg n "$PROJECT_NAME" --arg i "$PROJECT_IDENTIFIER" "$list_expr[]? | select(.name==\$n or .identifier==\$i) | .id" | head -1 || true
}
state_id_or_empty() {
  states_json | jq -er --arg n "$1" "$list_expr[]? | select(.name==\$n) | .id" | head -1 || true
}
label_id_or_empty() {
  labels_json | jq -er --arg n "$1" "$list_expr[]? | select(.name==\$n) | .id" | head -1 || true
}
item_id_or_empty() {
  items_json | jq -er --arg n "$1" "$list_expr[]? | select(.name==\$n) | .id" | head -1 || true
}

ensure_project() {
  local id payload out
  id=$(project_id_or_empty)
  if [[ -n "$id" ]]; then
    jq -n --arg type project --arg action existing --arg id "$id" --arg name "$PROJECT_NAME" --arg identifier "$PROJECT_IDENTIFIER" '{type:$type,action:$action,id:$id,name:$name,identifier:$identifier}'
    return 0
  fi
  payload=$(jq -n --arg name "$PROJECT_NAME" --arg identifier "$PROJECT_IDENTIFIER" '{name:$name,identifier:$identifier}')
  out=$(api_post "/api/v1/workspaces/$WS/projects/" "$payload")
  id=$(printf '%s' "$out" | jq -er '.id')
  jq -n --arg type project --arg action created --arg id "$id" --arg name "$PROJECT_NAME" --arg identifier "$PROJECT_IDENTIFIER" '{type:$type,action:$action,id:$id,name:$name,identifier:$identifier}'
}

ensure_state() {
  local name="$1" group="$2" color="$3" id payload out
  id=$(state_id_or_empty "$name")
  if [[ -n "$id" ]]; then
    jq -n --arg type state --arg action existing --arg id "$id" --arg name "$name" --arg group "$group" '{type:$type,action:$action,id:$id,name:$name,group:$group}'
    return 0
  fi
  payload=$(jq -n --arg name "$name" --arg group "$group" --arg color "$color" '{name:$name,group:$group,color:$color}')
  out=$(api_post "/api/v1/workspaces/$WS/projects/$PROJ_ID/states/" "$payload")
  id=$(printf '%s' "$out" | jq -er '.id')
  jq -n --arg type state --arg action created --arg id "$id" --arg name "$name" --arg group "$group" '{type:$type,action:$action,id:$id,name:$name,group:$group}'
}

ensure_label() {
  local name="$1" color="$2" id payload out
  id=$(label_id_or_empty "$name")
  if [[ -n "$id" ]]; then
    jq -n --arg type label --arg action existing --arg id "$id" --arg name "$name" '{type:$type,action:$action,id:$id,name:$name}'
    return 0
  fi
  payload=$(jq -n --arg name "$name" --arg color "$color" '{name:$name,color:$color}')
  out=$(api_post "/api/v1/workspaces/$WS/projects/$PROJ_ID/labels/" "$payload")
  id=$(printf '%s' "$out" | jq -er '.id')
  jq -n --arg type label --arg action created --arg id "$id" --arg name "$name" '{type:$type,action:$action,id:$id,name:$name}'
}

state_id() { local id; id=$(state_id_or_empty "$1"); [[ -n "$id" ]] || { echo "ERROR: missing state after ensure: $1" >&2; exit 3; }; printf '%s\n' "$id"; }
label_id() { local id; id=$(label_id_or_empty "$1"); [[ -n "$id" ]] || { echo "ERROR: missing label after ensure: $1" >&2; exit 3; }; printf '%s\n' "$id"; }

ensure_item() {
  local name="$1" state_name="$2" html="$3" labels_csv="$4" priority="${5:-medium}" id sid payload out label labels_json_array
  id=$(item_id_or_empty "$name")
  if [[ -n "$id" ]]; then
    jq -n --arg type work_item --arg action existing --arg id "$id" --arg name "$name" '{type:$type,action:$action,id:$id,name:$name}'
    return 0
  fi
  sid=$(state_id "$state_name")
  labels_json_array='[]'
  IFS=',' read -r -a labels <<< "$labels_csv"
  for label in "${labels[@]}"; do
    [[ -n "$label" ]] || continue
    labels_json_array=$(jq -c --arg id "$(label_id "$label")" '. + [$id]' <<< "$labels_json_array")
  done
  payload=$(jq -n --arg name "$name" --arg state "$sid" --arg html "$html" --arg priority "$priority" --argjson labels "$labels_json_array" '{name:$name,state:$state,description_html:$html,labels:$labels,priority:$priority}')
  out=$(api_post "/api/v1/workspaces/$WS/projects/$PROJ_ID/work-items/" "$payload")
  id=$(printf '%s' "$out" | jq -er '.id')
  jq -n --arg type work_item --arg action created --arg id "$id" --arg name "$name" '{type:$type,action:$action,id:$id,name:$name}'
}

html_status_ledger() {
  cat <<HTML
<div><h3>Purpose</h3><p>Open Engine status ledger. Agents update one <code>AGENT STATUS</code> comment per runtime instead of creating duplicate heartbeat comments.</p><h3>Rules</h3><ul><li>One latest status comment per agent.</li><li>Status comments use the exact <code>AGENT STATUS</code> token.</li><li>Queue runners update this ledger before and after checks.</li></ul></div>
HTML
}

html_routing_map() {
  local routes_html
  routes_html=$(json_array_from_routes | jq -r '.[] | "<li><code>" + . + "</code> — production route configured during bootstrap.</li>"' | tr -d '\n')
  cat <<HTML
<div><h3>Purpose</h3><p>Canonical routing map for Open Engine production agent codes.</p><h3>Agent-code pattern</h3><p><code>&lt;environment&gt;-&lt;runtime&gt;-&lt;role&gt;</code></p><h3>Production routes</h3><ul>$routes_html</ul><h3>Routing policy</h3><ul><li>New work starts in Backlog until human-only, agent-only, or mixed ownership is clear.</li><li>Agent execution requires title pattern <code>[agent instructions][&lt;agent-code&gt;][task] &lt;short outcome&gt;</code>.</li><li>A runtime may process only exact matching agent-code tasks.</li><li>Do not guess missing agent codes; ask for human input or review.</li></ul></div>
HTML
}

html_core_context() {
  cat <<HTML
<div><h3>Open Engine core context v1</h3><p>Open Engine uses Plane as a shared queue and coordination surface for agent handoffs.</p><h3>Origin</h3><p>The Open Engine operating idea is credited to Nate B. Jones and his article <a href="https://natesnewsletter.substack.com/p/ai-agent-handoffs">AI Agent Handoffs</a>.</p><h3>Workflow</h3><p>Backlog request → triage into agent-ready task → Agent Todo → one runtime claims and processes one eligible item → terminal receipt.</p><h3>Execution gate</h3><p><code>Agent Todo</code> is the execution gate. Items should enter it only when the task is cold-executable with requester, desired outcome, sources, acceptance criteria, boundaries, blocker rule, output handoff, and valid target agent code.</p><h3>Safety</h3><p>No publishing, deleting, billing changes, credential changes, deployments, email, Slack posting, or outward-facing side effects without explicit approval in the work item.</p></div>
HTML
}

html_smoke_task() {
  local agent="$1"
  cat <<HTML
<div><h3>Requester</h3><p>$HUMAN_OPERATOR / Open Engine bootstrap smoke test.</p><h3>Desired outcome</h3><p>Leave a short comment proving the <code>$agent</code> runtime can claim and complete a queue item.</p><h3>Sources</h3><p>This Open Engine Plane workspace and the local <code>oe-plane-runner</code> helper scripts.</p><h3>Acceptance criteria</h3><ul><li>Issue has <code>AGENT CLAIMED</code> from <code>$agent</code>.</li><li>Issue has <code>AGENT DONE</code> from <code>$agent</code>.</li><li>Issue moves to <code>Agent Done</code>.</li><li>Runtime stops after exactly one task.</li></ul><h3>Boundaries</h3><p>Do not edit files, publish, email, Slack-post, deploy, delete, or change credentials.</p><h3>If blocked</h3><p>Only block if there is an actual missing answer, permission, or authority.</p><h3>Output handoff</h3><p>Comment with the result and update status through the runner/helper.</p></div>
HTML
}

main() {
  require_tools
  if [[ "$DRY_RUN" == "1" ]]; then
    dry_run_plan
    exit 0
  fi
  load_secrets_and_require_env

  local project_result first_route routes_json
  project_result=$(ensure_project)
  PROJ_ID=$(printf '%s' "$project_result" | jq -er '.id')
  log "project_id=$PROJ_ID"
  printf '%s\n' "$project_result"

  ensure_state "Agent Todo" "unstarted" "#3B82F6"
  ensure_state "Agent Working" "started" "#F59E0B"
  ensure_state "Agent Needs Input" "started" "#EC4899"
  ensure_state "Agent Review" "started" "#8B5CF6"
  ensure_state "Agent Done" "completed" "#22C55E"
  ensure_state "Agent Failed" "cancelled" "#EF4444"

  ensure_label "agent-instructions" "#2563EB"
  ensure_label "agent-standing" "#7C3AED"
  ensure_label "agent-task" "#059669"
  ensure_label "needs-agent-triage" "#F97316"
  ensure_label "requires-human" "#DC2626"
  ensure_label "requires-repo" "#0891B2"
  ensure_label "requires-browser" "#9333EA"
  ensure_label "agent-smoke-test" "#64748B"

  ensure_item "[agent instructions][all agents][standing_status] Open Engine status ledger" "Backlog" "$(html_status_ledger)" "agent-instructions,agent-standing" "medium"
  ensure_item "[agent instructions][all agents][standing_routing] Open Engine routing map" "Backlog" "$(html_routing_map)" "agent-instructions,agent-standing" "medium"
  ensure_item "[agent instructions][all agents][standing_context] Open Engine core context v1" "Backlog" "$(html_core_context)" "agent-instructions,agent-standing" "medium"

  routes_json=$(json_array_from_routes)
  first_route=$(printf '%s' "$routes_json" | jq -r '.[0] // empty')
  if [[ "$CREATE_SMOKE" == "1" && -n "$first_route" ]]; then
    ensure_item "[agent instructions][$first_route][task] Say hello from the queue" "Agent Todo" "$(html_smoke_task "$first_route")" "agent-instructions,agent-task,agent-smoke-test" "medium"
  fi

  jq -n \
    --arg workspace "$WS" \
    --arg project_id "$PROJ_ID" \
    --arg project_name "$PROJECT_NAME" \
    --arg project_identifier "$PROJECT_IDENTIFIER" \
    --argjson routes "$routes_json" \
    --arg smoke_created "$CREATE_SMOKE" \
    '{ok:true,workspace:$workspace,project:{id:$project_id,name:$project_name,identifier:$project_identifier},routes:$routes,smoke_item_requested:($smoke_created=="1")}'
}

main "$@"
