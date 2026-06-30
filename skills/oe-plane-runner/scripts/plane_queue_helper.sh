#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_FILE="${PLANE_SECRETS_FILE:-}"
PROJECT_NAME="${PLANE_PROJECT_NAME:-Open Engine}"
PROJECT_IDENTIFIER="${PLANE_PROJECT_IDENTIFIER:-OE}"

if [ -n "$SECRETS_FILE" ]; then
  if [ ! -f "$SECRETS_FILE" ]; then
    echo "ERROR: PLANE_SECRETS_FILE not found: $SECRETS_FILE" >&2
    exit 2
  fi
  set -a
  # shellcheck disable=SC1090
  . "$SECRETS_FILE"
  set +a
fi

: "${PLANE_API_TOKEN:?PLANE_API_TOKEN missing}"
: "${PLANE_WORKSPACE_SLUG:?PLANE_WORKSPACE_SLUG missing}"
API_BASE="${PLANE_API_BASE_URL:-https://api.plane.so}"
API_BASE="${API_BASE%/}"
WS="$PLANE_WORKSPACE_SLUG"

AUTH=(-H "X-API-Key: $PLANE_API_TOKEN" -H "x-workspace-slug: $WS" -H "Accept: application/json")
AUTH_JSON=(-H "X-API-Key: $PLANE_API_TOKEN" -H "x-workspace-slug: $WS" -H "Accept: application/json" -H "Content-Type: application/json")

usage() {
  cat <<USAGE
Usage: $0 <command> [args]

Read commands:
  status                         Compact project/state/label/standing summary
  routes                         Valid production agent routes from routing map
  validate-route <agent-code>    Check whether an agent-code is in the routing map
  next <agent-code>              Oldest eligible Agent Todo task for agent
  detail <sequence-or-id>        Compact work item detail
  comments <sequence-or-id>      Compact comments for work item
  paused <agent-code>            Paused Agent Needs Input tasks for agent
  working <agent-code>           Claimed Agent Working tasks for agent, for retry/recovery
  assignee-check                Print resolved operator UUID used for assignee filtering
  preflight <agent-code>         Standing context/version/hash snapshot before task work
  delegated <agent-code>         Delegation tracking tasks created by this agent

Write commands:
  ledger <agent> <result> [notes]
  create-smoke <agent>
  create-blocked-test <agent>
  create-human-hold-test <agent>
  comment <sequence-or-id> <text>
  claim <agent> <sequence-or-id>
  done <agent> <sequence-or-id> [message]
  review <agent> <sequence-or-id> [message]
  block <agent> <sequence-or-id> <question>
  resume <agent> <sequence-or-id> [reason]
  hold <agent> <sequence-or-id> <question> <reason>
  fail <agent> <sequence-or-id> <last-safe-step>
  delegate <source-agent> <target-agent> <sequence-or-id> <delegated-task-title>
  follow-up <agent>
USAGE
}

api_get() { curl -fsS --retry 4 --retry-delay 2 --retry-all-errors "${AUTH[@]}" "$API_BASE$1"; }
api_post() { curl -fsS --retry 4 --retry-delay 2 --retry-all-errors -X POST "${AUTH_JSON[@]}" --data "$2" "$API_BASE$1"; }
api_patch() { curl -fsS --retry 4 --retry-delay 2 --retry-all-errors -X PATCH "${AUTH_JSON[@]}" --data "$2" "$API_BASE$1"; }
api_delete() { curl -fsS --retry 4 --retry-delay 2 --retry-all-errors -X DELETE "${AUTH[@]}" "$API_BASE$1"; }

list_expr='(.results // .)'

project_id() {
  api_get "/api/v1/workspaces/$WS/projects/" \
    | jq -er --arg n "$PROJECT_NAME" --arg i "$PROJECT_IDENTIFIER" "$list_expr[] | select(.name==\$n or .identifier==\$i) | .id" \
    | head -1
}

PROJ_ID="${PLANE_PROJECT_ID:-$(project_id)}"

states_json() { api_get "/api/v1/workspaces/$WS/projects/$PROJ_ID/states/"; }
labels_json() { api_get "/api/v1/workspaces/$WS/projects/$PROJ_ID/labels/"; }
items_json() { api_get "/api/v1/workspaces/$WS/projects/$PROJ_ID/work-items/?expand=state,labels"; }

state_id() {
  local name="$1"
  states_json | jq -er --arg n "$name" "$list_expr[] | select(.name==\$n) | .id" | head -1
}

label_id() {
  local name="$1"
  labels_json | jq -er --arg n "$name" "$list_expr[] | select(.name==\$n) | .id" | head -1
}

item_id_from_arg() {
  local arg="$1"
  if [[ "$arg" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    printf '%s\n' "$arg"
  elif [[ "$arg" =~ ^#?[0-9]+$ ]]; then
    local seq="${arg#\#}"
    items_json | jq -er --argjson seq "$seq" "$list_expr[] | select(.sequence_id==\$seq) | .id" | head -1
  else
    echo "ERROR: expected sequence number or UUID, got: $arg" >&2
    exit 3
  fi
}

item_detail_json() {
  local id="$1"
  api_get "/api/v1/workspaces/$WS/projects/$PROJ_ID/work-items/$id/?expand=state,labels"
}

comments_json() {
  local id="$1"
  api_get "/api/v1/workspaces/$WS/projects/$PROJ_ID/work-items/$id/comments/"
}

activities_json() {
  local id="$1"
  api_get "/api/v1/workspaces/$WS/projects/$PROJ_ID/work-items/$id/activities/"
}

compact_item_filter='{id, sequence_id, name, state:(if (.state|type)=="object" then .state.name else .state end), labels:[(.labels // [])[] | if type=="object" then .name else . end], assignees:(.assignees // []), updated_at, last_activity_at, description_stripped}'

compact_item() {
  jq -c "$compact_item_filter"
}

html_escape() {
  jq -Rs 'gsub("&";"&amp;") | gsub("<";"&lt;") | gsub(">";"&gt;")'
}

text_to_comment_html() {
  local text="$1"
  printf '%s' "$text" | html_escape | jq -r '"<p>" + (gsub("\\n";"<br>")) + "</p>"'
}

post_comment() {
  local item_id="$1" text="$2"
  local html payload
  html=$(text_to_comment_html "$text")
  payload=$(jq -n --arg h "$html" '{comment_html:$h}')
  api_post "/api/v1/workspaces/$WS/projects/$PROJ_ID/work-items/$item_id/comments/" "$payload" >/dev/null
}

patch_comment() {
  local item_id="$1" comment_id="$2" text="$3"
  local html payload
  html=$(text_to_comment_html "$text")
  payload=$(jq -n --arg h "$html" '{comment_html:$h}')
  api_patch "/api/v1/workspaces/$WS/projects/$PROJ_ID/work-items/$item_id/comments/$comment_id/" "$payload" >/dev/null
}

delete_comment() {
  local item_id="$1" comment_id="$2"
  api_delete "/api/v1/workspaces/$WS/projects/$PROJ_ID/work-items/$item_id/comments/$comment_id/" >/dev/null
}

verify_state() {
  local item_id="$1" expected="$2"
  local detail state
  detail=$(item_detail_json "$item_id")
  state=$(printf '%s' "$detail" | jq -r '.state.name // .state // ""')
  if [ "$state" != "$expected" ]; then
    jq -n --arg ok false --arg expected "$expected" --arg actual "$state" '{ok:false,error:"state verification failed",expected:$expected,actual:$actual}'
    return 1
  fi
  printf '%s' "$detail" | compact_item
}

move_state() {
  local item_id="$1" state_name="$2" sid payload
  sid=$(state_id "$state_name")
  payload=$(jq -n --arg s "$sid" '{state:$s}')
  api_patch "/api/v1/workspaces/$WS/projects/$PROJ_ID/work-items/$item_id/" "$payload" >/dev/null
  verify_state "$item_id" "$state_name"
}

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

status_cmd() {
  local items states labels
  items=$(items_json)
  states=$(states_json)
  labels=$(labels_json)
  jq -n \
    --arg project_id "$PROJ_ID" \
    --arg project "$PROJECT_NAME" \
    --arg workspace "$WS" \
    --argjson states "$(printf '%s' "$states" | jq -c "$list_expr | map({id,name,group})")" \
    --argjson labels "$(printf '%s' "$labels" | jq -c "$list_expr | map({id,name})")" \
    --argjson standing "$(printf '%s' "$items" | jq -c "$list_expr | map(select(.name | startswith(\"[agent instructions][all agents][standing_\")) | {id,sequence_id,name,state:(.state.name // .state)})")" \
    --argjson counts "$(printf '%s' "$items" | jq -c "$list_expr | group_by(.state.name // .state) | map({state:(.[0].state.name // .[0].state), count:length})")" \
    '{workspace:$workspace, project:$project, project_id:$project_id, states:$states, labels:$labels, standing:$standing, counts_by_state:$counts}'
}

next_cmd() {
  local agent="$1" opfilter
  require_valid_agent "$agent"
  opfilter=$(operator_filter_expr)
  items_json | jq -c --arg agent "$agent" "$list_expr
    | map(select((.state.name // .state)==\"Agent Todo\"))
    | map(select((.labels // [] | map(.name) | index(\"agent-instructions\")) != null))
    | map(select(.name | startswith(\"[agent instructions][\" + \$agent + \"][task]\")))
    $opfilter
    | sort_by(.sequence_id // 999999, .created_at)
    | .[0] // null
    | if . == null then {eligible:false,agent:\$agent} else {eligible:true,agent:\$agent,item:$compact_item_filter} end"
}

detail_cmd() {
  local id
  id=$(item_id_from_arg "$1")
  item_detail_json "$id" | compact_item
}

comments_cmd() {
  local id
  id=$(item_id_from_arg "$1")
  comments_json "$id" | jq -c "$list_expr | map({id,created_at,comment_stripped})"
}

ledger_item_id() {
  items_json | jq -er "$list_expr[] | select(.name==\"[agent instructions][all agents][standing_status] Open Engine status ledger\") | .id" | head -1
}


routing_item_id() {
  items_json | jq -er "$list_expr[] | select(.name==\"[agent instructions][all agents][standing_routing] Open Engine routing map\") | .id" | head -1
}

core_context_item_id() {
  items_json | jq -er "$list_expr[] | select(.name==\"[agent instructions][all agents][standing_context] Open Engine core context v1\") | .id" | head -1
}

short_sha_file() {
  local f="$1"
  if [ -f "$f" ]; then sha256sum "$f" | awk '{print substr($1,1,16)}'; else printf 'missing'; fi
}

preflight_cmd() {
  local agent="$1" rid cid rdesc cdesc skill_hash ref_hash helper_hash runner_hash
  require_valid_agent "$agent"
  rid=$(routing_item_id)
  cid=$(core_context_item_id)
  rdesc=$(item_detail_json "$rid" | jq -r '.description_stripped // ""')
  cdesc=$(item_detail_json "$cid" | jq -r '.description_stripped // ""')
  skill_hash=$(short_sha_file "$SKILL_ROOT/SKILL.md")
  ref_hash=$(short_sha_file "$SKILL_ROOT/references/plane-api-contract.md")
  helper_hash=$(short_sha_file "$SKILL_ROOT/scripts/plane_queue_helper.sh")
  runner_hash=$(short_sha_file "$SKILL_ROOT/scripts/run_one_queue_check.sh")
  jq -n --arg ok true --arg agent "$agent" --arg routing_item "$rid" --arg core_context_item "$cid" \
    --arg routing_hash "$(printf '%s' "$rdesc" | sha256sum | awk '{print substr($1,1,16)}')" \
    --arg core_context_hash "$(printf '%s' "$cdesc" | sha256sum | awk '{print substr($1,1,16)}')" \
    --arg skill_hash "$skill_hash" --arg ref_hash "$ref_hash" --arg helper_hash "$helper_hash" --arg runner_hash "$runner_hash" \
    '{ok:true,agent:$agent,standing:{routing_item:$routing_item,core_context_item:$core_context_item,routing_hash:$routing_hash,core_context_hash:$core_context_hash,skill_hash:$skill_hash,reference_hash:$ref_hash,helper_hash:$helper_hash,runner_hash:$runner_hash},local_skill_hashes:{"SKILL.md":$skill_hash,"references/plane-api-contract.md":$ref_hash,"scripts/plane_queue_helper.sh":$helper_hash,"scripts/run_one_queue_check.sh":$runner_hash},versions:{engine:"Open Engine v1",routing_map:"production routes v1",core_context:"v1",runner:"v1"}}'
}

routes_json() {
  local rid desc
  rid=$(routing_item_id)
  desc=$(item_detail_json "$rid" | jq -r '.description_stripped // ""')
  printf '%s\n' "$desc" | awk '
    BEGIN { in_routes=0 }
    /^Production routes$/ { in_routes=1; next }
    /^Routing policy$/ { in_routes=0 }
    in_routes && /^[a-z0-9]+-[a-z0-9-]+-[a-z0-9]+$/ { print }
  ' | jq -Rsc 'split("\n") | map(select(length>0)) | unique | {routes:.}'
}

routes_cmd() {
  routes_json
}

validate_route_cmd() {
  local agent="$1"
  routes_json | jq -c --arg agent "$agent" 'if (.routes | index($agent)) then {ok:true,agent:$agent,source:"routing-map"} else {ok:false,error:"unknown_agent_route",agent:$agent,valid_routes:.routes} end'
}

require_valid_agent() {
  local agent="$1" result
  if [ "${OPEN_ENGINE_ALLOW_UNKNOWN_AGENT:-0}" = "1" ]; then
    return 0
  fi
  result=$(validate_route_cmd "$agent")
  if [ "$(printf '%s' "$result" | jq -r '.ok')" != "true" ]; then
    printf '%s\n' "$result"
    exit 4
  fi
}

operator_uuid() {
  if [ -n "${OPEN_ENGINE_OPERATOR_UUID:-}" ]; then
    printf '%s\n' "$OPEN_ENGINE_OPERATOR_UUID"
  else
    api_get "/api/v1/users/me/" | jq -r '.id // empty'
  fi
}

operator_filter_expr() {
  # Returns empty string if no operator UUID is available (solo mode: no assignee filter)
  local opid
  opid=$(operator_uuid)
  if [ -n "$opid" ]; then
    printf '| map(select((.assignees // []) | index(\"%s\") != null))' "$opid"
  fi
}

paused_cmd() {
  local agent="$1" opfilter
  require_valid_agent "$agent"
  opfilter=$(operator_filter_expr)
  items_json | jq -c --arg agent "$agent" "$list_expr
    | map(select((.state.name // .state)==\"Agent Needs Input\"))
    | map(select((.labels // [] | map(if type==\"object\" then .name else . end) | index(\"agent-instructions\")) != null))
    | map(select(.name | startswith(\"[agent instructions][\" + \$agent + \"][task]\")))
    $opfilter
    | sort_by(.sequence_id // 999999, .created_at)
    | map($compact_item_filter)"
}

working_cmd() {
  local agent="$1" opfilter
  require_valid_agent "$agent"
  opfilter=$(operator_filter_expr)
  items_json | jq -c --arg agent "$agent" "$list_expr
    | map(select((.state.name // .state)==\"Agent Working\"))
    | map(select((.labels // [] | map(if type==\"object\" then .name else . end) | index(\"agent-instructions\")) != null))
    | map(select(.name | startswith(\"[agent instructions][\" + \$agent + \"][task]\")))
    $opfilter
    | sort_by(.sequence_id // 999999, .created_at)
    | map($compact_item_filter)"
}

comment_cmd() {
  local arg="$1" text="$2" id
  id=$(item_id_from_arg "$arg")
  post_comment "$id" "$text"
  jq -n --arg ok true --arg item_id "$id" '{ok:true,item_id:$item_id,commented:true}'
}

create_blocked_test_cmd() {
  local agent="$1" todo lid1 lid2 name html payload out
  require_valid_agent "$agent"
  todo=$(state_id "Agent Todo")
  lid1=$(label_id "agent-instructions")
  lid2=$(label_id "agent-task")
  name="[agent instructions][$agent][task] Draft a one-sentence project tagline"
  if items_json | jq -e --arg n "$name" "$list_expr[]? | select(.name==\$n)" >/dev/null; then
    items_json | jq -c --arg n "$name" "$list_expr[] | select(.name==\$n) | $compact_item_filter" | head -1
    return 0
  fi
  html="<div><h3>Requester</h3><p>Marco / Open Engine blocked-resume test.</p><h3>Desired outcome</h3><p>Draft a one-sentence tagline for the Open Engine project.</p><h3>Sources</h3><p>Use the project name and target audience.</p><h3>Missing information</h3><p>The target audience is intentionally missing.</p><h3>Acceptance criteria</h3><ul><li>If target audience is missing, ask exactly one question as AGENT BLOCKED.</li><li>After the answer is provided in Plane, resume and produce one tagline.</li><li>Final AGENT DONE includes the tagline.</li></ul><h3>Boundaries</h3><p>Do not invent the target audience. Do not publish, email, post, deploy, delete, or change credentials.</p><h3>If blocked</h3><p>Ask: Who is the target audience for this tagline?</p></div>"
  payload=$(jq -n --arg name "$name" --arg state "$todo" --arg html "$html" --arg l1 "$lid1" --arg l2 "$lid2" '{name:$name,state:$state,description_html:$html,labels:[$l1,$l2],priority:"medium"}')
  out=$(api_post "/api/v1/workspaces/$WS/projects/$PROJ_ID/work-items/" "$payload")
  printf '%s' "$out" | compact_item
}

create_human_hold_test_cmd() {
  local agent="$1" todo lid1 lid2 name html payload out
  require_valid_agent "$agent"
  todo=$(state_id "Agent Todo")
  lid1=$(label_id "agent-instructions")
  lid2=$(label_id "agent-task")
  name="[agent instructions][$agent][task] Draft a private-approval note"
  if items_json | jq -e --arg n "$name" "$list_expr[]? | select(.name==\$n)" >/dev/null; then
    items_json | jq -c --arg n "$name" "$list_expr[] | select(.name==\$n) | $compact_item_filter" | head -1
    return 0
  fi
  html="<div><h3>Requester</h3><p>Marco / Open Engine human-hold test.</p><h3>Desired outcome</h3><p>Draft a one-sentence private approval note after operator approval is granted in the human agent thread.</p><h3>Sources</h3><p>Use this work item and the private approval answer from the operator thread.</p><h3>Missing authority</h3><p>Operator approval is intentionally missing and must not be treated as a normal Plane blocker answer.</p><h3>Acceptance criteria</h3><ul><li>First run asks for private operator approval via AGENT HUMAN HOLD.</li><li>After private approval is provided, second run records AGENT HUMAN ANSWERED and AGENT RESUMED.</li><li>Final AGENT DONE includes the note.</li></ul><h3>Boundaries</h3><p>Do not invent approval. Do not publish, email, post, deploy, delete, or change credentials.</p><h3>If human hold required</h3><p>Ask in the human agent thread: Do I have operator approval to draft the private approval note?</p></div>"
  payload=$(jq -n --arg name "$name" --arg state "$todo" --arg html "$html" --arg l1 "$lid1" --arg l2 "$lid2" '{name:$name,state:$state,description_html:$html,labels:[$l1,$l2],priority:"medium"}')
  out=$(api_post "/api/v1/workspaces/$WS/projects/$PROJ_ID/work-items/" "$payload")
  printf '%s' "$out" | compact_item
}

resume_hold_cmd() {
  local agent="$1" arg="$2" reason="${3:-Human answered in private agent thread.}" id before seq name text moved
  require_valid_agent "$agent"
  id=$(item_id_from_arg "$arg")
  before=$(verify_state "$id" "Agent Needs Input")
  seq=$(printf '%s' "$before" | jq -r '.sequence_id')
  name=$(printf '%s' "$before" | jq -r '.name')
  text="AGENT HUMAN ANSWERED
Agent: $agent
At: $(iso_now)
Reason: $reason"
  post_comment "$id" "$text"
  moved=$(move_state "$id" "Agent Working")
  text="AGENT RESUMED
Agent: $agent
At: $(iso_now)
Reason: $reason"
  post_comment "$id" "$text"
  ledger_cmd "$agent" "resumed #$seq" "$name" >/dev/null
  jq -n --arg ok true --argjson item "$moved" '{ok:true,receipts:["AGENT HUMAN ANSWERED","AGENT RESUMED"],item:$item}'
}

resume_cmd() {
  local agent="$1" arg="$2" reason="${3:-Human answer found in Plane comments.}" id before seq name text moved
  require_valid_agent "$agent"
  id=$(item_id_from_arg "$arg")
  before=$(verify_state "$id" "Agent Needs Input")
  seq=$(printf '%s' "$before" | jq -r '.sequence_id')
  name=$(printf '%s' "$before" | jq -r '.name')
  text="AGENT UNBLOCKED
Agent: $agent
At: $(iso_now)
Reason: $reason"
  post_comment "$id" "$text"
  moved=$(move_state "$id" "Agent Working")
  text="AGENT RESUMED
Agent: $agent
At: $(iso_now)
Reason: $reason"
  post_comment "$id" "$text"
  ledger_cmd "$agent" "resumed #$seq" "$name" >/dev/null
  jq -n --arg ok true --argjson item "$moved" '{ok:true,receipts:["AGENT UNBLOCKED","AGENT RESUMED"],item:$item}'
}

ledger_cmd() {
  local agent="$1" result="$2" notes="${3:-none}" ledger_id text comments matching latest_id old_ids action pruned
  require_valid_agent "$agent"
  ledger_id=$(ledger_item_id)
  text="AGENT STATUS
Agent: $agent
Human/operator: Marco
Runtime: Agent Zero or assigned runtime $agent
Automation: manual
Automation state: manual-required
Last heartbeat: $(iso_now)
Last queue result: $result
Last successful run: $( [ "${result#completed}" != "$result" ] && iso_now || printf 'unknown' )
Local context: Open Engine v1; routing map v1
Notes: $notes"
  comments=$(comments_json "$ledger_id")
  matching=$(printf '%s' "$comments" | jq -c --arg agent "$agent" '(.results // .) | map(select((.comment_stripped // "") | startswith("AGENT STATUS")) | select((.comment_stripped // "") | contains("
Agent: " + $agent + "
"))) | sort_by(.created_at)')
  latest_id=$(printf '%s' "$matching" | jq -r '.[-1].id // empty')
  old_ids=$(printf '%s' "$matching" | jq -r '.[0:-1][]?.id')
  if [ -n "$latest_id" ]; then
    patch_comment "$ledger_id" "$latest_id" "$text"
    action="updated"
  else
    post_comment "$ledger_id" "$text"
    latest_id=$(comments_json "$ledger_id" | jq -r --arg agent "$agent" '(.results // .) | map(select((.comment_stripped // "") | startswith("AGENT STATUS")) | select((.comment_stripped // "") | contains("
Agent: " + $agent + "
"))) | sort_by(.created_at) | .[-1].id // empty')
    action="created"
  fi
  pruned=0
  if [ -n "$old_ids" ]; then
    while IFS= read -r old_id; do
      if [ -n "$old_id" ]; then
        delete_comment "$ledger_id" "$old_id"
        pruned=$((pruned + 1))
      fi
    done <<EOF_OLD_IDS
$old_ids
EOF_OLD_IDS
  fi
  local verify_count verify_result
  comments=$(comments_json "$ledger_id")
  matching=$(printf '%s' "$comments" | jq -c --arg agent "$agent" '(.results // .) | map(select((.comment_stripped // "") | startswith("AGENT STATUS")) | select((.comment_stripped // "") | contains("
Agent: " + $agent + "
"))) | sort_by(.created_at)')
  verify_count=$(printf '%s' "$matching" | jq -r 'length')
  verify_result=$(printf '%s' "$matching" | jq -r '.[-1].comment_stripped // ""' | awk -F': ' '/^Last queue result: / {print substr($0, index($0,$2)); exit}')
  if [ "$verify_count" != "1" ] || [ "$verify_result" != "$result" ]; then
    jq -n --arg ok false --arg error "ledger_verification_failed" --arg ledger_id "$ledger_id" --arg agent "$agent" --arg expected "$result" --arg actual "$verify_result" --arg count "$verify_count" '{ok:false,error:$error,ledger_id:$ledger_id,agent:$agent,expected:$expected,actual:$actual,matching_comments:($count|tonumber)}'
    return 5
  fi
  jq -n --arg ok true --arg ledger_id "$ledger_id" --arg agent "$agent" --arg result "$result" --arg action "$action" --arg comment_id "$latest_id" --argjson pruned "$pruned" '{ok:true,ledger_id:$ledger_id,agent:$agent,result:$result,action:$action,comment_id:$comment_id,pruned_duplicates:$pruned,verified:true}'
}

create_smoke_cmd() {
  local agent="$1" todo lid1 lid2 lid3 name html payload out
  require_valid_agent "$agent"
  todo=$(state_id "Agent Todo")
  lid1=$(label_id "agent-instructions")
  lid2=$(label_id "agent-task")
  lid3=$(label_id "agent-smoke-test")
  name="[agent instructions][$agent][task] Say hello from the queue"
  if items_json | jq -e --arg n "$name" "$list_expr[]? | select(.name==\$n)" >/dev/null; then
    items_json | jq -c --arg n "$name" "$list_expr[] | select(.name==\$n) | $compact_item_filter" | head -1
    return 0
  fi
  html="<div><h3>Requester</h3><p>Marco / Open Engine helper smoke test.</p><h3>Desired outcome</h3><p>Leave a short comment proving the $agent runtime claimed and completed this issue.</p><h3>Sources</h3><p>Plane standing issues, local skill oe-plane-runner, and plane_queue_helper.sh.</p><h3>Acceptance criteria</h3><ul><li>Issue has AGENT CLAIMED from $agent.</li><li>Issue has AGENT DONE from $agent.</li><li>Issue moves to Agent Done and status is verified.</li><li>Status ledger records completed for this issue.</li><li>Runtime stops after exactly one task.</li></ul><h3>Boundaries</h3><p>Do not edit files, publish, email, Slack-post, deploy, delete, or change credentials.</p><h3>If blocked</h3><p>Only block if there is an actual missing answer, permission, or authority.</p></div>"
  payload=$(jq -n --arg name "$name" --arg state "$todo" --arg html "$html" --arg l1 "$lid1" --arg l2 "$lid2" --arg l3 "$lid3" '{name:$name,state:$state,description_html:$html,labels:[$l1,$l2,$l3],priority:"medium"}')
  out=$(api_post "/api/v1/workspaces/$WS/projects/$PROJ_ID/work-items/" "$payload")
  printf '%s' "$out" | compact_item
}

claim_cmd() {
  local agent="$1" arg="$2" id detail seq name state text moved lockdir lockfile lockfd claimed_count
  require_valid_agent "$agent"
  id=$(item_id_from_arg "$arg")
  lockdir="/tmp/open_engine_plane_claim_locks"
  mkdir -p "$lockdir"
  lockfile="$lockdir/$id.lock"
  exec {lockfd}>"$lockfile"
  flock -x "$lockfd"

  detail=$(item_detail_json "$id")
  seq=$(printf '%s' "$detail" | jq -r '.sequence_id')
  name=$(printf '%s' "$detail" | jq -r '.name')
  state=$(printf '%s' "$detail" | jq -r '(.state.name // .state)')
  claimed_count=$(comments_json "$id" | jq "$list_expr | [.[] | select((.comment_stripped // \"\")|startswith(\"AGENT CLAIMED\"))] | length")
  if [ "$state" != "Agent Todo" ] || [ "$claimed_count" != "0" ]; then
    jq -n --arg ok false --arg error "claim_conflict" --arg state "$state" --arg claimed_count "$claimed_count" --arg sequence_id "$seq" --arg name "$name"       '{ok:false,error:$error,state:$state,claimed_count:($claimed_count|tonumber),item:{sequence_id:($sequence_id|tonumber),name:$name,state:$state}}'
    return 3
  fi

  moved=$(move_state "$id" "Agent Working")
  text="AGENT CLAIMED
Agent: $agent
At: $(iso_now)
Runtime: $agent
Claimed for one-run Open Engine queue check."
  post_comment "$id" "$text"
  ledger_cmd "$agent" "claimed #$seq" "$name" >/dev/null
  jq -n --arg ok true --argjson item "$moved" '{ok:true,receipt:"AGENT CLAIMED",item:$item}'
}

done_cmd() {
  local agent="$1" arg="$2" message="${3:-Hello from the Open Engine queue.}" id before seq name text moved
  require_valid_agent "$agent"
  id=$(item_id_from_arg "$arg")
  before=$(verify_state "$id" "Agent Working")
  seq=$(printf '%s' "$before" | jq -r '.sequence_id')
  name=$(printf '%s' "$before" | jq -r '.name')
  text="AGENT DONE
Agent: $agent
At: $(iso_now)
Hello: $message
Changed: Plane comments and status only.
Checks: Re-read status verified as Agent Working before completion; final status verified after patch to Agent Done.
Needs human: none."
  post_comment "$id" "$text"
  moved=$(move_state "$id" "Agent Done")
  ledger_cmd "$agent" "completed #$seq" "$name" >/dev/null
  jq -n --arg ok true --argjson item "$moved" '{ok:true,receipt:"AGENT DONE",item:$item}'
}

review_cmd() {
  local agent="$1" arg="$2" message="${3:-Scoped work complete; human review required.}" id before seq name text moved
  require_valid_agent "$agent"
  id=$(item_id_from_arg "$arg")
  before=$(verify_state "$id" "Agent Working")
  seq=$(printf '%s' "$before" | jq -r '.sequence_id')
  name=$(printf '%s' "$before" | jq -r '.name')
  text="AGENT DONE
Agent: $agent
At: $(iso_now)
Result: $message
Changed: Plane comments and status only.
Checks: Re-read status verified as Agent Working before completion; final status verified after patch to Agent Review.
Needs human: review required."
  post_comment "$id" "$text"
  moved=$(move_state "$id" "Agent Review")
  ledger_cmd "$agent" "completed #$seq" "$name — needs human review" >/dev/null
  jq -n --arg ok true --argjson item "$moved" '{ok:true,receipt:"AGENT DONE",review_required:true,item:$item}'
}

block_cmd() {
  local agent="$1" arg="$2" question="$3" id moved seq name text
  require_valid_agent "$agent"
  id=$(item_id_from_arg "$arg")
  moved=$(move_state "$id" "Agent Needs Input")
  seq=$(printf '%s' "$moved" | jq -r '.sequence_id')
  name=$(printf '%s' "$moved" | jq -r '.name')
  text="AGENT BLOCKED
Agent: $agent
At: $(iso_now)
Question: $question"
  post_comment "$id" "$text"
  ledger_cmd "$agent" "blocked #$seq" "$name" >/dev/null
  jq -n --arg ok true --argjson item "$moved" '{ok:true,receipt:"AGENT BLOCKED",item:$item}'
}

hold_cmd() {
  local agent="$1" arg="$2" question="$3" reason="$4" id moved seq name text
  require_valid_agent "$agent"
  id=$(item_id_from_arg "$arg")
  moved=$(move_state "$id" "Agent Needs Input")
  seq=$(printf '%s' "$moved" | jq -r '.sequence_id')
  name=$(printf '%s' "$moved" | jq -r '.name')
  text="AGENT HUMAN HOLD
Agent: $agent
At: $(iso_now)
Question: $question
Reason: $reason"
  post_comment "$id" "$text"
  ledger_cmd "$agent" "holding #$seq" "$name" >/dev/null
  jq -n --arg ok true --argjson item "$moved" '{ok:true,receipt:"AGENT HUMAN HOLD",item:$item}'
}

delegated_cmd() {
  local agent="$1"
  require_valid_agent "$agent"
  items_json | jq -c --arg agent "$agent" "$list_expr
    | map(select((.labels // [] | map(if type==\"object\" then .name else . end) | index(\"agent-instructions\")) != null))
    | map(select((.description_stripped // \"\") | contains(\"Delegated by: \" + \$agent)))
    | map($compact_item_filter)
    | sort_by(.sequence_id // 999999)"
}

delegate_cmd() {
  local source="$1" target="$2" parent_arg="$3" delegated_title="$4" parent_id parent seq target_todo l1 l2 name html payload out
  require_valid_agent "$source"
  require_valid_agent "$target"
  parent_id=$(item_id_from_arg "$parent_arg")
  parent=$(item_detail_json "$parent_id" | compact_item)
  seq=$(printf '%s' "$parent" | jq -r '.sequence_id')
  target_todo=$(state_id "Agent Todo")
  l1=$(label_id "agent-instructions")
  l2=$(label_id "agent-task")
  name="[agent instructions][$target][task] $delegated_title"
  html="<div><h3>Requester</h3><p>Open Engine delegation from $source.</p><h3>Desired outcome</h3><p>$delegated_title</p><h3>Sources</h3><p>Parent work item #$seq.</p><h3>Delegation</h3><p>Delegated by: $source</p><p>Parent: #$seq</p><h3>Acceptance criteria</h3><ul><li>Target runtime completes scoped delegated work.</li><li>Source runtime can later leave AGENT FOLLOW-UP on the parent or delegated issue.</li></ul><h3>Boundaries</h3><p>No external side effects unless explicitly approved.</p></div>"
  payload=$(jq -n --arg name "$name" --arg state "$target_todo" --arg html "$html" --arg l1 "$l1" --arg l2 "$l2" '{name:$name,state:$state,description_html:$html,labels:[$l1,$l2],priority:"medium"}')
  out=$(api_post "/api/v1/workspaces/$WS/projects/$PROJ_ID/work-items/" "$payload")
  local child_seq child_id text
  child_seq=$(printf '%s' "$out" | jq -r '.sequence_id')
  child_id=$(printf '%s' "$out" | jq -r '.id')
  text="AGENT DELEGATED
Agent: $source
At: $(iso_now)
Target agent: $target
Delegated issue: #$child_seq
Parent issue: #$seq
Task: $delegated_title"
  post_comment "$parent_id" "$text"
  ledger_cmd "$source" "delegated #$child_seq" "from parent #$seq to $target" >/dev/null
  printf '%s' "$out" | compact_item | jq -c --arg parent "#$seq" --arg target "$target" '{ok:true,delegated_to:$target,parent:$parent,item:.}'
}

follow_up_cmd() {
  local agent="$1" items count
  require_valid_agent "$agent"
  items=$(delegated_cmd "$agent")
  count=$(printf '%s' "$items" | jq -r 'length')
  if [ "$count" = "0" ]; then
    jq -n --arg agent "$agent" '{ok:true,agent:$agent,followups:[],count:0}'
    return 0
  fi
  local tmp results='[]' seq state name comments already text
  tmp=$(mktemp)
  printf '%s' "$items" | jq -c '.[]' > "$tmp"
  while IFS= read -r item; do
    seq=$(printf '%s' "$item" | jq -r '.sequence_id')
    state=$(printf '%s' "$item" | jq -r '.state')
    name=$(printf '%s' "$item" | jq -r '.name')
    if [ "$state" = "Agent Done" ] || [ "$state" = "Agent Review" ] || [ "$state" = "Agent Failed" ]; then
      comments=$(comments_cmd "$seq")
      already=$(printf '%s' "$comments" | jq -r --arg agent "$agent" '[.[] | select((.comment_stripped // "") | startswith("AGENT FOLLOW-UP")) | select((.comment_stripped // "") | contains("Agent: " + $agent))] | length')
      if [ "$already" = "0" ]; then
        text="AGENT FOLLOW-UP
Agent: $agent
At: $(iso_now)
Delegated issue: #$seq
Observed status: $state
Summary: Delegated work changed to terminal/review state."
        comment_cmd "$seq" "$text" >/dev/null
        results=$(printf '%s' "$results" | jq -c --arg seq "$seq" --arg state "$state" --arg name "$name" '. + [{sequence_id:($seq|tonumber),state:$state,name:$name,posted:true}]')
      else
        results=$(printf '%s' "$results" | jq -c --arg seq "$seq" --arg state "$state" --arg name "$name" '. + [{sequence_id:($seq|tonumber),state:$state,name:$name,posted:false,reason:"already_followed_up"}]')
      fi
    fi
  done < "$tmp"
  rm -f "$tmp"
  ledger_cmd "$agent" "observed" "delegated follow-up check" >/dev/null
  jq -n --arg agent "$agent" --argjson followups "$results" '{ok:true,agent:$agent,count:($followups|length),followups:$followups}'
}

fail_cmd() {
  local agent="$1" arg="$2" step="$3" id seq name text
  require_valid_agent "$agent"
  id=$(item_id_from_arg "$arg")
  move_state "$id" "Agent Failed" >/dev/null || true
  detail=$(item_detail_json "$id")
  seq=$(printf '%s' "$detail" | jq -r '.sequence_id')
  name=$(printf '%s' "$detail" | jq -r '.name')
  text="AGENT FAILED
Agent: $agent
At: $(iso_now)
Last safe step: $step"
  post_comment "$id" "$text"
  ledger_cmd "$agent" "failed #$seq" "$name" >/dev/null
  item_detail_json "$id" | compact_item | jq -c '{ok:true,receipt:"AGENT FAILED",item:.}'
}

cmd="${1:-}"
case "$cmd" in
  status) status_cmd ;;
  routes) routes_cmd ;;
  validate-route) [ $# -eq 2 ] || { usage >&2; exit 2; }; validate_route_cmd "$2" ;;
  next) [ $# -eq 2 ] || { usage >&2; exit 2; }; next_cmd "$2" ;;
  detail) [ $# -eq 2 ] || { usage >&2; exit 2; }; detail_cmd "$2" ;;
  comments) [ $# -eq 2 ] || { usage >&2; exit 2; }; comments_cmd "$2" ;;
  paused) [ $# -eq 2 ] || { usage >&2; exit 2; }; paused_cmd "$2" ;;
  working) [ $# -eq 2 ] || { usage >&2; exit 2; }; working_cmd "$2" ;;
  assignee-check) operator_uuid ;;
  preflight) [ $# -eq 2 ] || { usage >&2; exit 2; }; preflight_cmd "$2" ;;
  delegated) [ $# -eq 2 ] || { usage >&2; exit 2; }; delegated_cmd "$2" ;;
  ledger) [ $# -ge 3 ] || { usage >&2; exit 2; }; ledger_cmd "$2" "$3" "${4:-none}" ;;
  create-smoke) [ $# -eq 2 ] || { usage >&2; exit 2; }; create_smoke_cmd "$2" ;;
  create-blocked-test) [ $# -eq 2 ] || { usage >&2; exit 2; }; create_blocked_test_cmd "$2" ;;
  create-human-hold-test) [ $# -eq 2 ] || { usage >&2; exit 2; }; create_human_hold_test_cmd "$2" ;;
  comment) [ $# -eq 3 ] || { usage >&2; exit 2; }; comment_cmd "$2" "$3" ;;
  claim) [ $# -eq 3 ] || { usage >&2; exit 2; }; claim_cmd "$2" "$3" ;;
  done) [ $# -ge 3 ] || { usage >&2; exit 2; }; done_cmd "$2" "$3" "${4:-Hello from the Open Engine queue.}" ;;
  review) [ $# -ge 3 ] || { usage >&2; exit 2; }; review_cmd "$2" "$3" "${4:-Scoped work complete; human review required.}" ;;
  block) [ $# -eq 4 ] || { usage >&2; exit 2; }; block_cmd "$2" "$3" "$4" ;;
  resume) [ $# -ge 3 ] || { usage >&2; exit 2; }; resume_cmd "$2" "$3" "${4:-Human answer found in Plane comments.}" ;;
  resume-hold) [ $# -ge 3 ] || { usage >&2; exit 2; }; resume_hold_cmd "$2" "$3" "${4:-Human answered in private agent thread.}" ;;
  hold) [ $# -eq 5 ] || { usage >&2; exit 2; }; hold_cmd "$2" "$3" "$4" "$5" ;;
  fail) [ $# -eq 4 ] || { usage >&2; exit 2; }; fail_cmd "$2" "$3" "$4" ;;
  delegate) [ $# -eq 5 ] || { usage >&2; exit 2; }; delegate_cmd "$2" "$3" "$4" "$5" ;;
  follow-up) [ $# -eq 2 ] || { usage >&2; exit 2; }; follow_up_cmd "$2" ;;
  -h|--help|help|'') usage ;;
  *) echo "ERROR: unknown command: $cmd" >&2; usage >&2; exit 2 ;;
esac
