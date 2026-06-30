#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
required=(
  "README.md"
  "skills/oe-plane-runner/SKILL.md"
  "skills/oe-plane-runner/scripts/plane_queue_helper.sh"
  "skills/oe-plane-runner/scripts/run_one_queue_check.sh"
  "skills/oe-plane-runner/references/plane-api-contract.md"
  "skills/oe-plane-runner/references/task-writing-guide.md"
  "skills/oe-plane-triage/SKILL.md"
  "skills/oe-plane-triage/references/backlog-triage-policy.md"
  "skills/oe-plane-triage/references/task-writing-guide.md"
  "docs/operating-model.md"
)
for path in "${required[@]}"; do
  [[ -f "$path" ]] || { echo "missing: $path" >&2; exit 1; }
done
bash -n skills/oe-plane-runner/scripts/plane_queue_helper.sh
bash -n skills/oe-plane-runner/scripts/run_one_queue_check.sh
echo "ok"
