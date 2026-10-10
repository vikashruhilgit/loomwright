# Supervisor Job: Append the overdue rules re-measurement row to `RULES_BASELINE.md`

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-10-194230/L3 (a `/automate --parallel` lane clone of `vikashruhilgit/loomwright`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main @ `4e0f255` (== origin/main)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/twin-loop/07-rules-baseline-remeasurement.md

> **Warning (1):** this checkout is lane L3 of wave `automate-2026-10-10-194230`; sibling lanes run in other clones.
> Stay inside this directory. Branch mode is ON (`loomwright-meta`): the postmortem ledger is no longer tracked on
> `main` — see Feasibility check 5 and the measurement method below.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown edit + an existing read-only bash/python instrument. |
| 2 | Dependency Availability | GO | `bash`, `python3`, `jq`, `git`, `gh` present; `loomwright/scripts/measure-heal-signal.sh` present. |
| 3 | Architecture Fit | GO | `RULES_BASELINE.md` §"Re-measurement instruction" asks for exactly this appended row. |
| 4 | Scope vs Supervisor Capability | GO | One doc row + one changelog fragment — single subtask. |
| 5 | Hard Blockers | CAUTION | The documented recipe pins the ledger on a `main` commit. Since `2e07bc8` (M1, 2026-10-03) `.supervisor/postmortem/results.jsonl` is untracked on `main` and lives on `origin/loomwright-meta`. The instrument still runs; its INPUT location moved. Requirement Scope §3 covers this: say so in the row and record the substitute. |

**Overall Verdict:** GO (1 CAUTION carried into Risk Assessment)

## Task
**Goal:** Append one dated comparison row to `loomwright/docs/RULES_BASELINE.md` §"Subsequent rows", measured with the baseline's own instrument, over the PRs whose ledger records landed after the first harvested rule batch (`3f4bb2e`), with an honest reading of what it can and cannot show.

**Problem Statement:**
twin-loop/05 (PR #147) committed the baseline row (2026-08-14) and promised a comparison row once N ≥ 20 PRs merged after `3f4bb2e` (2026-09-01). That threshold passed long ago, but §"Subsequent rows" still reads "None yet", so nobody knows whether the house rules moved review churn.

**Launch Pad analysis (verified, for the worker to re-derive, not trust):**
- The baseline row still reproduces exactly with today's instrument at `5293d06` (84 records / 225 findings / 95 misses, same per-class table).
- At `3f4bb2e` the ledger held **85** lines; the current `origin/loomwright-meta` ledger (commit `1df5d34`, blob `b4e09cc`) holds **158**, and its first 85 lines are byte-identical to the `3f4bb2e` copy — so the post-rules window is ledger lines **86–158 (73 records)**.
- Those 73 records are **72 `source: automate_drain` + 1 `/pr-postmortem`** record; the baseline's 84 were mostly `/pr-postmortem` / `manual_postmortem` records (46 + 10) with 29 `automate_drain`. The engine-native emitter labels findings with mechanical classes (`drain_churn`, `self_heal_churn`) rather than the classifier's `convention_mismatch`/`quality_gap`/… — a probe of the window gave `drain_churn` 54, `self_heal_churn` 31, `convention_mismatch` 2. **The labelling channel changed between the two rows; that is the headline confounder and must be stated, not buried.**
- `.agent/rules/` changes in the window: `3f4bb2e` (2 harvested rules), `9ac669f` (drift-check fix), `c0d8a30` (rules gate docs).

## Acceptance Criteria
- [ ] Given `RULES_BASELINE.md`, when the change is applied, then §"Subsequent rows" holds exactly ONE new dated row (2026-10-10) and the "_None yet …_" placeholder is replaced by it; the baseline row, its table and every other section are byte-unchanged.
- [ ] Given the row, when read, then it states the window: the ledger pin (commit + blob sha + line range), the first and last PR of the window, and the record count; plus the distinct-PR count beside the record count; and that every distinct PR in the window merged after `3f4bb2e` (date 2026-09-01T05:38:59Z) — `gh pr view <n> --json mergedAt` checked for ALL distinct (repo, number) pairs, any that predate it named as a caveat (the instrument's table stays as is).
- [ ] Given the row, when read, then it carries the same table shape as the baseline (class / findings / share / misses / share / miss-rate) from `measure-heal-signal.sh --distribution` run over the window, plus the label-quality line, with each class's baseline value shown beside it (a class absent from one row reads 0 there).
- [ ] Given the documented recipe can no longer run as written (the ledger is off `main`), when the row is read, then it says so explicitly and records the exact substitute: the ledger read from `origin/loomwright-meta` at a pinned commit/blob, the window carved as a line range into a scratch git repo passed via `--repo`, the instrument unchanged.
- [ ] Given the row, when read, then it has one line naming what changed in the rules store since the baseline (the rule count at the window pin and whether any `applies_to` was widened since the baseline's one-rule state), and one paragraph naming what changed, what can and cannot be attributed to the rules — at minimum the record-source/labelling-channel shift (`automate_drain` vs `/pr-postmortem`), other review-lane changes in the window, and the guessed-label caveat.
- [ ] Given the PR body, when read, then it pastes the exact command(s) that reproduce every number in the row.
- [ ] Given `changelog.d/twin-loop-07-rules-baseline-remeasurement.md`, when `bash scripts/bump-version.sh --dry-run` parses it, then it is a valid fragment (`<!-- bump: patch -->` + headline + body); no version file is edited.
- [ ] Given the whole change, when `bash scripts/check-doc-currency.sh` and `bash loomwright/scripts/test-citation-drift.sh` run, then both exit 0.

## Outcomes Rubric
- The new row is appended under §"Subsequent rows"; the baseline row and its table are unchanged.
- The row states the ledger pin (commit + blob), line range, first/last PR, record count and distinct-PR count, and names the instrument command used.
- Per-class values sit beside the baseline values in the baseline's table shape, including the label-quality line.
- The ledger relocation off `main` and the substitute method are stated explicitly, not silently applied.
- The reading paragraph names the labelling-channel shift as a confounder and does not claim the rules caused any change.
- Only `loomwright/docs/RULES_BASELINE.md` and the new changelog fragment change.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Measure the post-rules window and append the comparison row | ALL (AC-1 … AC-8) | 1 modify, 1 create | `quality-checklist` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1 — Measure the post-rules window and append the comparison row
provides:
  - {kind: "file",   path: "changelog.d/twin-loop-07-rules-baseline-remeasurement.md"}
  - {kind: "symbol", path: "loomwright/docs/RULES_BASELINE.md", name: "2026-10-10"}
requires: []
lanes:
  - "loomwright/docs/RULES_BASELINE.md"
  - "changelog.d/twin-loop-07-rules-baseline-remeasurement.md"
external_requires:
  - "origin/loomwright-meta branch (the ledger's home since 2e07bc8)"
```

## Measurement method (the worker re-runs this; it does not trust the numbers above)

```bash
git fetch origin loomwright-meta
git rev-parse --short origin/loomwright-meta                                    # pin the commit
git rev-parse --short origin/loomwright-meta:.supervisor/postmortem/results.jsonl # pin the blob
git show 3f4bb2e:.supervisor/postmortem/results.jsonl | wc -l                    # window start (85)
W=$(mktemp -d); git -C "$W" init -q; mkdir -p "$W/.supervisor/postmortem"
git show <pinned-commit>:.supervisor/postmortem/results.jsonl | sed -n '86,$p' > "$W/.supervisor/postmortem/results.jsonl"
bash loomwright/scripts/measure-heal-signal.sh --distribution --repo "$W"
```

Derive the window start rather than hard-coding it: `N=$(git show 3f4bb2e:.supervisor/postmortem/results.jsonl | wc -l)`, then `sed -n "$((N+1)),\$p"`. Prefix check: `cmp <(git show 3f4bb2e:.supervisor/postmortem/results.jsonl) <(git show <pin>:.supervisor/postmortem/results.jsonl | head -n "$N")`. Record the instrument's commit sha (the `main` HEAD the script was run from) in the row, since the instrument itself is not pinned to the baseline's `5293d06` copy.

Also verify the 85-line prefix is byte-identical to the `3f4bb2e` copy (else the line-range window is wrong — say so). Use the PINNED commit sha in the doc, never the moving branch name. A supplementary per-source breakdown is allowed only if clearly labelled as an extra view, never in place of the instrument's table.

## Parallelism Analysis
single-agent (no fan-out)

- Recommended workers: 1

## Skill References

| Skill | Why |
|---|---|
| `skills/quality-checklist/SKILL.md` | Pre/post gates |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Ledger off `main` — documented recipe cannot run as written (Feasibility 5, CAUTION) | MEDIUM | AC-4: state it and record the substitute; instrument unchanged |
| Labelling channel shift makes the class shares non-comparable | HIGH | AC-5: the reading names it first; no causal claim |
| Measuring from a moving branch / dirty copy (the 2026-08-15 correction) | MEDIUM | Pin commit + blob; measure from `git show` of the pin, never the working-tree ledger |
| Editing the baseline row (append-only rule) | HIGH | AC-1: baseline byte-unchanged |
| New bare `file:N` citation fails `test-citation-drift.sh` | LOW | Use descriptive anchors |
| Restating a version/count claim that `check-doc-currency.sh` scans | LOW | No plugin version or agent/skill count in the row |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/auto-2026-10-10-194526-rules-baseline-remeasurement.md
```

---

## Outcome
- **Status:** completed
- **Completed:** 2026-10-10T15:02:07Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/459
- **Branch:** feature/twin-loop-07-rules-baseline-remeasurement
- **Files changed:** 2
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Rubric score:** 6/6
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Appended the 2026-10-10 post-rules row (ledger loomwright-meta 1df5d34 / blob b4e09cc, lines 86–158, 73 records / 73 PRs, #170–#455). It leads with the automate_drain labelling-channel confounder, states the ledger relocation and the substitute method, and makes no causal claim. Phase 4.5: two FAIL iterations, both on AC-6 (PR-body repro commands), fixed by PR-body edits only, then PASS. 1 MEDIUM + 4 LOW dismissed.

## Not verified
- **the row's git worktree add /tmp/remeasure line** — recipe run from this checkout at 4e0f255 rather than a fresh worktree (subtask 1). Phase 4.5 iteration 3 later ran it in a scratch clone and it held.
