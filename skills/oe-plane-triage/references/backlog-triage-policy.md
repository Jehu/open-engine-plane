# Open Engine Backlog Triage Policy

## Decision table

| Situation | Action |
|---|---|
| `needs-agent-triage` + valid agent code in title | Normalize title, complete description, optionally mark for review |
| `needs-agent-triage` + no valid agent code | Do not guess. Ask human to provide target runtime/agent code |
| Human-only issue | Do not convert to agent task. Add/keep `requires-human` |
| Refined but not approved | Move to `Agent Review` if allowed, otherwise leave clear comment |
| Missing public task facts | `AGENT BLOCKED` + `Agent Needs Input` + concrete question |
| Missing private authority/secrets/local permissions | `AGENT HUMAN HOLD` + visible status/label if allowed |

## Minimal refined issue body

```markdown
## Requester
<name / role / authority>

## Desired outcome
<observable result>

## Target runtime / agent code
`<agent-code>` or `Not yet specified`

## Sources
- <file/link/issue/doc>

## Acceptance criteria
- <checkable criterion>

## Boundaries
May: <allowed actions>
Needs approval: <approval-gated actions>
Out of scope: <excluded actions>

## Blocker rule
If <condition>, leave `AGENT BLOCKED` or `AGENT HUMAN HOLD` with <specific question>.

## Output handoff
Comment on this issue with <expected result summary, files, checks, links, or schedule info>.
```

## Canonical title

```text
[agent instructions][<agent-code>][task] <short outcome>
```

Only create this title when `<agent-code>` is explicit and valid.
