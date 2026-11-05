# Merge one parked item, gate fixes and --cheap end to end — plan doc (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now
Issue vikashruhilgit/loomwright#829: a safe-mode item parked `awaiting_merge` has no supported way through the `--auto-merge` gate, which blocks two Studio phase 8 items. All of this comes from one gap: `--resume` knows only what is in the run file, so `--cheap` is forgotten and `ready_sha` is wiped. The remaining `--cheap` work joins here because it edits the same driver. Its baseline is about 82.7M tokens per item median (`.supervisor/cost-trials/fix-floor-high.md`).

## Owner decisions
none recorded

## Order
| Item | Delivers | Depends on | Can run in parallel with |
|---|---|---|---|
| 2026-11-05-192934 | `--merge-parked`: one parked item through the existing gate | none | 2026-11-05-192935 |
| 2026-11-05-192935 | `--trust-unprotected` on private Free repos; condition 5 reads CI with no required list | none | 2026-11-05-192934 |
| 2026-11-05-192936 | `--cheap` persisted, `--no-cheap`, and the drain honours it | none | none (shares `automate-next-step.sh` with 192934) |

## Run
/automate --backlog .supervisor/requirements/_BACKLOG-2026-11-05-192934-merge-parked-and-cheap.md --parallel 2
Safe mode. Start only after PR 822 merges: it changes `automate-next-step.sh`, `commands/automate.md`, `automate-run.md`, `run-file.md`, `runfile.sh` and the driver's tests.
N = 2 because that is the widest wave the Touches allow. The owner merges one wave PR per wave.
Plan: wave 1: 192934 + 192935 · wave 2: 192936.
Serialisation: 192936 waits on 192934: both edit `automate-next-step.sh`, its test, `commands/automate.md`, `automate-run.md`, `run-file.md`, `prompt-token-budgets.json` and `ARCHITECTURE_CONTRACTS.md`.
Hotspots in wave 1: `scripts/automate-helpers.sh` and `modes-and-merge-gate.md` belong to 192935; `automate-next-step.sh`, `commands/automate.md`, `resume.md` and `loop-inventory/automate-loop.md` belong to 192934. Each item's Scope says to leave the other's alone. The one cross-reference is `resume.md`'s heading `### Merging one parked item`, named in both items.
Proposed companions rule: none.

## Considered and not queued
- Building #829 as `--resume --auto-merge`: `--resume` wipes the state the gate needs and continues the run, and it would look like `--no-cheap` while behaving oppositely (one-time versus permanent).
- Adding the staleness checks to `gate_eval`: they would need a `ready_at` ctx key and an eighth condition, and would put both wave 1 items in one file. They live in the `--merge-parked` guard instead, where the long gap exists. Revisit if a plain `--auto-merge` gate merges over a late finding.
- Parking on `mergeStateStatus` `BEHIND`: not a reliable signal with strict protection off. The compare API's `behind_by` is used instead.
- Reusing PR 6 on studio-sandbox as the p14 retest: its failed resume should already have erased its `ready_sha`, so a new item is needed.
- Treating `changelog.d/` as a shared Touches path: every PR adds its own uniquely named fragment. The two new items declare their exact file. Fixing the older stories' directory form is a separate, small cleanup.
- Fixing `plan-waves` for a declared `changelog.d/` directory: real but unrelated to this set.

## Revisit when
p14 fails on a fresh sandbox item, a `--merge-parked` run merges over a finding posted after READY, or a `--cheap` run's ledger still shows full-model spawns.

## Checklist
- [ ] .supervisor/requirements/2026-11-05-192934-merge-one-parked-item-through-the-gate.md
- [ ] .supervisor/requirements/2026-11-05-192935-trust-unprotected-private-free-and-empty-checks.md
- [ ] .supervisor/requirements/2026-11-05-192936-cheap-honoured-end-to-end.md
