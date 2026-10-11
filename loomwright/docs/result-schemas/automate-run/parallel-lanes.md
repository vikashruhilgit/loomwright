### `--parallel` `## Progress` lines (parallel-automate/21)

Appended (never rewritten), like every `## Progress` line. Each is written only on a `--parallel N>1` run; a sequential run never writes one. Authority: `skills/automate-loop/SKILL.md` §2 "`--limit N`" and §14 "Wave close" / "Policy answers".

| Line | Run file | Written by | Meaning |
|---|---|---|---|
| `skipped AUT-QUEUE: lane backlog written by lane-create from the owner's --parallel command` | lane | the lane's engine at Queue confirm | The Queue confirm (gate `AUT-QUEUE`) was not asked: the lane's source is the one-line backlog `lane-create` wrote. |
| `policy answer: <code> → <label> (policy_sha <first 12>)` | lane | the lane's own `relay-hook` | A catalogued `allowed` gate was answered from the lane's carried policy (exact lookup) instead of being relayed. Fail-SAFE: a failed append never blocks the answer. |
| `wave policy: <code>=<label>, …` | parent | `lane-policy.sh wave-set` | The owner's per-wave policy answers, recorded when `.supervisor/automate/<run_id>.wave-policy.json` was written. |
| `fleet closeout: <lane> <item> done (PR <url>)` | parent | `fleet-closeout` | The lane's run file reads `## Status: done`; its item was checked off the parent `## Queue`. |
| `fleet closeout leaks: <first line>` | parent | `fleet-closeout` | The first line of `lane-status <parent_runfile> --leaks` after the last lane was removed (`leaks: none` on a clean wave). |
| `wave_paused: main_red after <sha>` | parent | `fleet-closeout` | `origin/<base>` HEAD's `ci` check concluded `failure` at wave close. Informational: no revert, no block, never a `pause_reason`. |

### Lane inbox answer file (`<lane>/.supervisor/inbox/answers/<tool_use_id>.json`)

One JSON file per answered lane question, beside its question file `inbox/questions/<tool_use_id>.json` (`{id, asked_at, questions}`). Two writers, one shape:

| Field | Owner answer (`lane-answer`) | Policy answer (the lane's `relay-hook`) |
|---|---|---|
| `answers` | `{"0": "<label>", …}` — the question's own option labels | same |
| `note` | the owner's optional note, or `null` | none — a policy carries no note |
| `source` | `"human"` | `"policy"` |
| `via` | the client the owner answered through | `"policy"` |
| `at` | UTC timestamp | UTC timestamp |
| `policy_sha` | — | the carried policy's `policy_sha` (sha256 of its canonical answers) |
| `gate` | — | the catalog code (`header`) the policy answered |

A question file with no answer file is a pending HUMAN question (`lane-status <parent_runfile> --inbox`). Authority: `skills/automate-loop/SKILL.md` §14 "Policy answers"; codes and labels: `docs/LANE_GATES.md`.
