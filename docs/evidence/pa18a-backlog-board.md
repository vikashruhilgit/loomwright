# Evidence: `/backlog` on this repo's live requirements (parallel-automate/18a, AC14)

A read-only run of the board engine over this checkout's real `.supervisor/requirements/`. It reads GitHub (`gh pr list`, merged and open) and writes no stamp. Paths are repo-relative. The checkout is `/Users/<name>/…/L6` on branch `feature/pa18a-backlog-board`, at the subtask 1 commits (`c49629e`, `6839cd3`) on base `237adab`.

## Command

```bash
bash loomwright/scripts/automate-helpers.sh backlog --json > live.json   # exit 0, 43 s wall
jq -c . live.json | jq -e . >/dev/null                                   # round-trips: ok
```

**Read-only check.** `.supervisor/requirements/` is gitignored here (branch mode `on loomwright-meta`), so a clean `git status` proves nothing. Instead, `find .supervisor/requirements -newermt <5 min before the check> -type f` listed no file after the run.

## Header and totals

```json
{"schema_version":1,"github":"verified","right_size":"ok","item_count":447,
 "totals":{"done":218,"abandoned":15,"parked":21,"proposed":174,"brief_shipped":3,"merged_unstamped":2,
           "pr_open":0,"in_flight":1,"conflict":0,"open":5,"unknown":8}}
```

The totals sum to 447, which equals `item_count`, so each item is counted once. `.supervisor/requirements/` holds 491 `*.md` files, and the 44 not counted are the ones `_rs_skip_path` skips (`00-*`, `_*`, `README*`, `operator-run/`, top-level task plans). Four runs are listed `stale_run`. Each is an unfinished run file whose `## Current` names an item its own stamp says is done (for example `.supervisor/automate/automate-2026-10-15-163325-L5.md` naming `automate-speed/06-next-step-driver-tail`).

**The miscount this fixes.** 104 items have `## Status: pending` as their first status line. The board reads 94 of them `done`, 4 `abandoned`, 1 `in_flight` and only 5 `open`, because close-out appended the done stamp lower in the file.

## Five sample rows (from `items[]`, `candidates` omitted)

| Item | State | Evidence (as printed) | Run / lane | Right-size |
|---|---|---|---|---|
| `af36-remainder/01-validation-unrun-gate` | `done` | `## Status: done` | – | `ok` |
| `af36-remainder/02-meta-allowlist-grant` | `done` | `## Status: done` | – | `ok` |
| `parallel-automate/18a-backlog-board` | `in_flight` | `## Current of unfinished run .supervisor/automate/automate-2026-10-22-123646-L6.md` | that run (this one) | `large` |
| `automate-followups/39c-guard-arm-trace` | `open` | `## Status: pending` | – | `ok` |
| `auto-2026-09-06-030556-rules-audit-verb` | `brief_shipped` | `## Status: brief-shipped` | – | `unknown` |

**What is behind each `done` sample.** Both have a first-line `## Status: pending`, so a first-line count would call them open.

- `af36-remainder/01-validation-unrun-gate`: line 3 is `## Status: pending`, and line 100 is the appended `## Status: done`, followed by `- **PR:** https://github.com/vikashruhilgit/loomwright/pull/502`. Run file: `.supervisor/automate/automate-2026-10-12-181635-L1.md:9: - [x] .supervisor/requirements/af36-remainder/01-validation-unrun-gate.md`.
- `af36-remainder/02-meta-allowlist-grant`: line 3 is `## Status: pending`, and line 76 is the appended `## Status: done`, followed by `- **PR:** https://github.com/vikashruhilgit/loomwright/pull/501`. Run file: `.supervisor/automate/automate-2026-10-12-181635-L2.md:9: - [x] .supervisor/requirements/af36-remainder/02-meta-allowlist-grant.md`.

## Honest limits seen on this run

- **False `merged_unstamped` from a generic basename.** Both `merged_unstamped` rows are wrong: `twin-remediation/salvage/parity-emit-block/spec` and `twin-remediation/salvage/review-churn-canary/spec` read `merged PR #269 names slug spec`. PR #269 is `feat(verify): spec replay — …` (head `feature/token-economy-07-verify-spec-replay`), so it is unrelated. The cause: precedence step 2 matches a merged PR whose title *contains* the item's basename, and `spec` is a common word. The row does name the PR, so an owner can check it before stamping. `commands/backlog.md` states this limit. A fix would be to match the folder-qualified slug, or require a word boundary plus the item's id prefix. It belongs to the engine, so it is reported here and not changed in this subtask.
- **Parked targets that do not resolve read `parked`.** `automate-followups/36-s3-engine-fixes` reads `parked … (target af36-remainder/01 not found)`. Its stamp says ``split … into `af36-remainder/01`–`04` ``, which names an id range, not a file. The fallback is `parked`, the conservative answer.
- **Timing.** 43 s wall on 447 items, most of it the single `right-size --json` call.
- **`github: verified` on this run.** The `unverified` path (gh failing) is covered by the hermetic fixture test (`test-automate-helpers.sh 18-backlog`), not by this live run.
