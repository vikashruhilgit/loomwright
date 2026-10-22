# Open items after the 2026-10-22 sweep — plan doc (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now
A 2026-10-22 read-only sweep of all 271 requirement items against main (7b7cb08, v17.14.1) found 224 shipped but
mostly still labelled `pending`: requirement `## Status:` lines and `_BACKLOG.md` checkboxes are not updated on
merge. Seven items had real work left; each was re-verified file by file against main, and its stale premises were
corrected (renamed or split scripts, moved docs, work shipped since). This set is that remaining work, reshaped so
every item fits one PR and the set runs in parallel waves. `18a-backlog-board.md` removes the hand cross-check this
sweep needed.

## Owner decisions
none recorded

## Order
| Item | Delivers | Depends on | Can run in parallel with |
|---|---|---|---|
| pa/18b | `right-size` verdict + merge candidates + `merge-items`; ends "count by hand" | none | 39e, pa/07, tr/09b, af/15 |
| af/39e | process registry (register/list/reap) + launcher registration + test-watchdog group fix | none | 18b, pa/07, tr/09b, af/15 |
| pa/07 | pilot report from the 2026-10-15 `--parallel 4` run + parallel docs close-out | none | 18b, 39e, tr/09b, af/15 |
| tr/09b | native overlap entries 2b/2d, KEEP for 2c/2e, scan reminder on minor bumps | none | 18b, 39e, pa/07, af/15 |
| af/15 | MEDIUM/LOW count pin + mutant; dead 7.0 score branch removed | none | all wave-1 items |
| pa/18a | `/backlog` board: every item's real state from evidence | pa/18b | af/39g |
| af/39g | `ci-local` leak gate (if kept) + SessionStart and run-end attention lines | af/39e | pa/18a |
| af/39f | `/janitor` report + owner-picked actions | af/39e | pa/25 |
| pa/25 | board feeds: Floor surface, `BACKLOG.md` (if approved), `lane-status` pointer, daily nudge | pa/18a | af/39f |
| af/39c | guard-arm skip trace + `test_guard:` line | none | **runs alone — not in this set** |

## Run
/automate --backlog .supervisor/requirements/_BACKLOG-2026-10-22-084146-open-items-reshape.md --parallel 4
Safe mode (the owner merges each wave PR). No new follow-up items beyond what an item's Scope says to file under
`proposed/`.
- **Why N = 4:** the set's widest wave is 5, but N = 5 and N = 4 both finish in three waves; 4 keeps each wave PR
  smaller to review, and 4 lanes is the load this machine held on 2026-10-15 (lanes were HELD for load at launch).
  With N = 4, af/15 moves from wave 1 to wave 2 (it conflicts with nothing).
- **Final waves (planner, `--max 4`):**
  - wave 1: pa/18b, af/39e, pa/07, tr/09b
  - wave 2: af/15, pa/18a, af/39g
  - wave 3: af/39f, pa/25
- **Serialisations:** pa/18a waits on pa/18b (its right-size column calls `right-size`); af/39g and af/39f wait on
  af/39e (both read the registry); af/39f also waits on pa/18a: both add a slash command, so both edit the
  command-count surfaces (`plugin.json`, `marketplace.json`, `README.md`, `CLAUDE.md`, `agent-help`), the token budgets
  and `ARCHITECTURE_CONTRACTS.md`, partly via the existing `loomwright/commands/*` companions rule; pa/25 waits on
  pa/18a (it feeds the board's reader).
- **Hotspots and their owner per wave:** `prompt-token-budgets.json` + `ARCHITECTURE_CONTRACTS.md` — 18b (w1), 18a
  (w2), 39f (w3); `CLAUDE.md` / `README.md` — pa/07 (w1), 18a (w2), 39f (w3); `automate-helpers.sh` +
  `skills/automate-loop/helpers.md` — 18b (w1), 18a (w2); `automate-next-step.sh` + `test-automate-lanes.d/` — 39e
  (w1), 39g (w2), pa/25 (w3, lanes tests only); `HOOKS.md` + `session-resume.sh` — 39g (w2), pa/25 (w3). Every one
  is declared in its item's Touches; no item edits a hotspot it does not declare.
- **Companions:** no new rule proposed — `.agent/companions.json` already expands `loomwright/commands/*` and
  `loomwright/agents/*.md` to the count and budget surfaces.
- **af/39c runs separately**, before this set or after it finishes, never during it: it edits the guard-protected
  `guard-arm.sh`, so the owner launches it from a shell that exports the human-only opt-out, and every lane launched
  from that shell would inherit gate-edit rights. Use
  `/automate --backlog .supervisor/requirements/_BACKLOG-2026-10-22-084146-af39c-alone.md` (sequential). It also
  edits the budgets, `ARCHITECTURE_CONTRACTS.md` and `HOOKS.md`, so it must not overlap a running wave.
- **Before `--parallel`:** every item in the Checklist must be on `loomwright-meta` (a lane is a fresh clone; an
  item that exists only locally makes `lane-create` abort). Push exactly these paths with `meta-sync.sh push`.

## Considered and not queued
- `twin-remediation/08` — closed: items 1–4 shipped (#487, #548), and fresh session per phase became the default in
  #628; the `/autonomous` multi-iteration half was dropped by the owner (recorded in 08b).
- A fresh `--parallel 2` pilot (pa/07's original plan) — the 2026-10-15 run is the pilot (owner, 2026-10-22). Tokens
  per lane and a sequential baseline are not measurable from its record; pa/07's report names what to log next time.
- Making af/15's unreachable 7.0 score branch reachable — it would shift code-review scores; the owner chose delete.
- 39d as one item — 20+ files, over the one-PR limit; split into 39e/39f/39g.
- tr/09 items 2c (Workflow tool), 2e (Agent Teams) beyond a KEEP line, and the seven 2026-10-12 CANDIDATEs — the
  owner chose 2b + 2d only; the CANDIDATEs stay `awaiting owner decision` in `CAPABILITY_BASELINE.json`.
- Changing `/automate`'s default lane count — stays unset; a separate one-line change if wanted.
- Operator-run items (`orca-derived/04b`, `orca-derived/06b`, `verify-walkthrough/08`) — hand-run research, never an
  `/automate` item; outside this set.

## Revisit when
- af/39g's Launch Pad answer drops the `ci-local` leak gate, or pa/25's drops the generated `BACKLOG.md` — record the
  drop in that item's Non-goals.
- After pa/18a merges: re-run the pending count with `/backlog` instead of a hand sweep, and stamp what it finds.
- The `isolation: worktree` re-probe (tr/09b 2d) is run in a reinstalled-plugin session.

## Checklist
- [ ] .supervisor/requirements/parallel-automate/18b-right-size-check.md
- [ ] .supervisor/requirements/automate-followups/39e-proc-registry-and-reap.md
- [ ] .supervisor/requirements/parallel-automate/07-pilot-and-docs.md
- [ ] .supervisor/requirements/twin-remediation/09b-overlap-map-and-scan-cadence.md
- [ ] .supervisor/requirements/automate-followups/15-telemetry-measures-the-agent-not-the-code.md
- [ ] .supervisor/requirements/parallel-automate/18a-backlog-board.md
- [ ] .supervisor/requirements/automate-followups/39g-leak-gate-and-attention-lines.md
- [ ] .supervisor/requirements/automate-followups/39f-janitor-command.md
- [ ] .supervisor/requirements/parallel-automate/25-backlog-board-feeds.md
