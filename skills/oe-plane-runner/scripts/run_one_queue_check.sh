#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${OPEN_ENGINE_PLANE_HELPER:-$SCRIPT_DIR/plane_queue_helper.sh}"

usage() {
  cat <<USAGE
Usage: $0 [agent-code]

Prepare exactly one Open Engine Plane queue check for a production runtime.

Agent code resolution:
  1. explicit CLI argument
  2. OPEN_ENGINE_AGENT_CODE environment variable
  3. error if neither is provided

Examples:
  $0 local-a0-developer
  OPEN_ENGINE_AGENT_CODE=local-a0-developer $0

The script does not perform task work. It validates routing, updates the ledger
with checking/none as appropriate, inspects recovery/paused/new queues, and
returns one compact JSON action packet.

Actions returned:
  recover_working_task   Resume an own Agent Working item with no terminal receipt.
  resume_paused_task     Resume an own Agent Needs Input item when human answer exists.
  inspect_paused_task    Inspect paused item; human answer may still be missing.
  process_new_task       Claim and process eligible Agent Todo item.
  no_work                No eligible work found; ledger already updated to none.
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ $# -gt 1 ]; then
  usage >&2
  exit 2
fi

agent="${1:-${OPEN_ENGINE_AGENT_CODE:-}}"
if [ -z "$agent" ]; then
  echo "ERROR: agent-code missing. Pass it as an argument or set OPEN_ENGINE_AGENT_CODE." >&2
  usage >&2
  exit 2
fi

json_array_len() { jq -r 'length'; }
first_item() { jq -c '.[0]'; }
comments_for_seq() { "$HELPER" comments "$1"; }
terminal_count_for_seq() {
  comments_for_seq "$1" | jq -r '[.[] | select((.comment_stripped // "") | test("^AGENT (DONE|BLOCKED|HUMAN HOLD|FAILED)"))] | length'
}
last_receipt_for_seq() {
  comments_for_seq "$1" | jq -r '[.[] | select((.comment_stripped // "") | test("^AGENT "))] | sort_by(.created_at) | .[-1].comment_stripped // ""'
}
human_answer_after_block_for_seq() {
  comments_for_seq "$1" | jq -r '
    sort_by(.created_at) as $c
    | ($c | map(.comment_stripped // "") | map(startswith("AGENT BLOCKED")) | lastIndex(true)) as $idx
    | if $idx == null then false
      else ($c[($idx+1):] | map(.comment_stripped // "") | any(test("^(Human answer:|HUMAN ANSWER:|Answer:|Marco:|User answer:)")))
      end'
}

# Validate before any Plane write beyond validation.
validation=$("$HELPER" validate-route "$agent")
if [ "$(printf '%s' "$validation" | jq -r '.ok')" != "true" ]; then
  printf '%s\n' "$validation"
  exit 4
fi

"$HELPER" ledger "$agent" checking "run_one_queue_check starting" >/dev/null
preflight=$("$HELPER" preflight "$agent")

working=$("$HELPER" working "$agent")
working_count=$(printf '%s' "$working" | json_array_len)
if [ "$working_count" -gt 0 ]; then
  item=$(printf '%s' "$working" | first_item)
  seq=$(printf '%s' "$item" | jq -r '.sequence_id')
  term_count=$(terminal_count_for_seq "$seq")
  if [ "$term_count" = "0" ]; then
    jq -n --arg agent "$agent" --arg action "recover_working_task" --arg reason "own Agent Working item has no terminal receipt" --argjson item "$item" \
      '{ok:true,agent:$agent,action:$action,reason:$reason,preflight:$preflight,item:$item,instructions:["Inspect detail/comments","Continue scoped work without a second claim","Finish with done/block/hold/fail"]}'
    exit 0
  fi
fi

paused=$("$HELPER" paused "$agent")
paused_count=$(printf '%s' "$paused" | json_array_len)
if [ "$paused_count" -gt 0 ]; then
  item=$(printf '%s' "$paused" | first_item)
  seq=$(printf '%s' "$item" | jq -r '.sequence_id')
  last_receipt=$(last_receipt_for_seq "$seq")
  if printf '%s' "$last_receipt" | grep -q '^AGENT BLOCKED'; then
    answered=$(human_answer_after_block_for_seq "$seq")
    if [ "$answered" = "true" ]; then
      jq -n --arg agent "$agent" --arg action "resume_paused_task" --arg resume_command "resume $agent $seq" --argjson item "$item" --argjson preflight "$preflight" \
        '{ok:true,agent:$agent,action:$action,preflight:$preflight,item:$item,resume_command:$resume_command,instructions:["Run resume command","Do scoped work using the human answer","Finish with done/block/hold/fail"]}'
    else
      jq -n --arg agent "$agent" --arg action "inspect_paused_task" --arg reason "AGENT BLOCKED is still waiting for a Plane answer" --argjson item "$item" --argjson preflight "$preflight" \
        '{ok:true,agent:$agent,action:$action,reason:$reason,preflight:$preflight,item:$item,instructions:["Do not claim new work","Stop or inspect comments for a human answer"]}'
    fi
    exit 0
  elif printf '%s' "$last_receipt" | grep -q '^AGENT HUMAN HOLD'; then
    jq -n --arg agent "$agent" --arg action "inspect_paused_task" --arg reason "AGENT HUMAN HOLD requires private operator-thread answer" --argjson item "$item" --argjson preflight "$preflight" \
      '{ok:true,agent:$agent,action:$action,reason:$reason,preflight:$preflight,item:$item,instructions:["Do not treat Plane comments as private approval","Resume only after private human answer is available"]}'
    exit 0
  else
    jq -n --arg agent "$agent" --arg action "inspect_paused_task" --arg reason "paused item needs inspection" --argjson item "$item" --argjson preflight "$preflight" \
      '{ok:true,agent:$agent,action:$action,reason:$reason,preflight:$preflight,item:$item,instructions:["Inspect detail/comments","Resume only if safe"]}'
    exit 0
  fi
fi

next=$("$HELPER" next "$agent")
if [ "$(printf '%s' "$next" | jq -r '.eligible')" = "true" ]; then
  item=$(printf '%s' "$next" | jq -c '.item')
  seq=$(printf '%s' "$item" | jq -r '.sequence_id')
  jq -n --arg agent "$agent" --arg action "process_new_task" --arg claim_command "claim $agent $seq" --argjson item "$item" --argjson preflight "$preflight" \
    '{ok:true,agent:$agent,action:$action,preflight:$preflight,item:$item,claim_command:$claim_command,instructions:["Inspect detail","Claim exactly this item","Do scoped work","Finish with done/block/hold/fail","Stop after this item"]}'
  exit 0
fi

"$HELPER" ledger "$agent" none "run_one_queue_check found no eligible work" >/dev/null
jq -n --arg agent "$agent" --argjson preflight "$preflight" '{ok:true,agent:$agent,action:"no_work",preflight:$preflight,item:null,instructions:["Stop; no eligible work for this runtime"]}'
