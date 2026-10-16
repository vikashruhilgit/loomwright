### `--parallel` `## Progress` lines (parallel-automate/21)

Appended (never rewritten), like every `## Progress` line. Each is written only on a `--parallel` run (the tokens line only on a single-lane `--parallel 1` parent; the wave lines only on N > 1); a sequential run never writes one. Authority: `skills/automate-loop/SKILL.md` §2 "`--limit N`" and §14 "Wave close" / "Policy answers".

| Line | Run file | Written by | Meaning |
|---|---|---|---|
| `skipped AUT-QUEUE: lane backlog written by lane-create from the owner's --parallel command` | lane | the lane's engine at Queue confirm | The Queue confirm (gate `AUT-QUEUE`) was not asked: the lane's source is the one-line backlog `lane-create` wrote. |
| `policy answer: <code> → <label> (policy_sha <first 12>)` | lane | the lane's own `relay-hook` | A catalogued `allowed` gate was answered from the lane's carried policy (exact lookup) instead of being relayed. Fail-SAFE: a failed append never blocks the answer. |
| `wave policy: <code>=<label>, …` | parent | `lane-policy.sh wave-set` | The owner's per-wave policy answers, recorded when `.supervisor/automate/<run_id>.wave-policy.json` was written. |
| `fleet closeout: <lane> <item> done (PR <url>)` | parent | `fleet-closeout` | The lane's run file reads `## Status: done`; its item was checked off the parent `## Queue`. |
| `fleet closeout: <lane> tokens TOTAL=<n>` | parent | `fleet-closeout` (step 5, before that lane's `lane-remove`) or `lane-remove` (plain / `--abandon`, before deleting the lane directory) — single-lane parents (`- parallel: 1`) only, once per lane | The lane's `read-token-ledger.sh` TOTAL (`unknown` when unreadable), recorded while its directory still exists: the whole-run `--max-tokens` ceiling's only record of a removed lane — `lane-create --parallel 1 --max-tokens T` reads it, and a removed lane with no such line (or `unknown`) refuses `token_ceiling ledger_unreadable` (`skills/automate-loop/lanes.md` "Single-lane mode"). |
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

A question file with no answer file is a pending HUMAN question (`lane-status <parent_runfile> --inbox`). When the lane's `relay-hook` records a NEW question id, every older question file of that lane with no answer file is **superseded**: a deferred question ends the lane's process, so a new id means the session abandoned the old one (it ended a plain turn and re-asked, or a bundled call was denied and re-asked). The file moves to `inbox/questions/superseded/<tool_use_id>.json` with `superseded_by` (the newer id) and `superseded_at` (UTC) added, and the lane run file gets one `## Progress` line `<ts> question superseded: <ids> by <new id> (…)`. A superseded question is never pending (no reader globs the subdirectory), and `lane-answer` refuses its id with `superseded by <newer id>`. Authority: `skills/automate-loop/SKILL.md` §14 "Policy answers"; codes and labels: `docs/LANE_GATES.md`.
