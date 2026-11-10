# Dismissed follow-ups 06b: script headers, the backlog basis, the review-heal doc mirror (`scripts` group)

Source requirement: `.supervisor/requirements/dismissed-followups/06b-docs-and-evidence-drift.md`, Subtask 3
(findings F046 F047 F352 F358 F196 F221 (the test half) F156). The sibling groups live in
`docs/evidence/dismissed-followups-06b-loop.md` and `docs/evidence/dismissed-followups-06b-docs.md`; F221's doc
half (`commands/supervisor.md`'s `--sdk-runner` row) is the `docs` group's.

**Base:** `edcdc2f3d20a23517f77bf0f3c5268cb4236fc67` (`main`). Every re-verify command below was run from the
worktree root on that base, before any edit. A match line is given as "line N" of the file the command names.

**Regression legs (AC2):** two findings change something a suite can pin. F358 changes an emitted string (the
`backlog` surface's `basis` in `floor.json`); F196 adds a pin (the driver header's `STEPS` index held equal to
the driver's case arms). Each has a new leg, shown red below on the base (F358) or on a scratch mutant (F196),
and each has an in-suite mutation control. The other findings are header-, comment- or message-only and carry
no leg; their rows say so.

## Findings

| Finding | Re-verify command | Result on base | Disposition | Kind |
|---|---|---|---|---|
| F046 | `grep -nF 'ci-slot.sh status [--json]   holders (slot, pid, checkout, name, started) + waiters in order' loomwright/scripts/ci-slot.sh` and `grep -nF "a ticket adds a fifth, the waiter's N." loomwright/scripts/ci-slot.sh` | 1 match each (lines 15 and 30) | `fixed`: `loomwright/scripts/ci-slot.sh` header (printed by `--help`). The `status [--json]` usage row now names a held waiter's hold reason, the machine view (machine holders, last load reading) and the `--json` keys: `dir`, `cpus`, `slots`, `jobs`, `holders`, `waiters` (each also `slots` and `held`), `machine {dir, holders, last_reading {at, state, load1} or null}`, read from `cmd_status`'s and `json_rec`'s emitters. The Layout line now says a held ticket carries a sixth line, its hold reason (written by `set_held`, read by `rec_field tickets/<n> 6`). Checked on the running emitter: a sandboxed `status --json` with a planted held ticket printed exactly those keys and `"held":"held for load: busy load1=30"` | header-only, no leg |
| F047 | `grep -nF 'mem_source, the raw memory reading). --json: one object with the same keys; a value that' loomwright/scripts/machine-load.sh` | 1 match (line 7) | `fixed`: `loomwright/scripts/machine-load.sh` header (printed by `--help`): `--json` is one object with the same keys plus `busy_at` and `overloaded_at` (the load1 thresholds, BUSY / OVERLOADED x CPUs; `--json` only). Checked: `machine-load.sh --json \| jq -c keys` lists both, and the plain form prints neither | header-only, no leg |
| F352 | `grep -nF 'Test seam: LOOMWRIGHT_PROC_PS_SNAPSHOT=<file> is read IN PLACE of running ps (same columns).' loomwright/scripts/proc-registry.sh` | 1 match (line 103) | `fixed`: `loomwright/scripts/proc-registry.sh` header: `LOOMWRIGHT_PROC_PS_SNAPSHOT` is a production input (`janitor-report.sh` passes its one shared ps snapshot, so every section reads one moment) as well as a test seam. `janitor-report.sh` (its `LOOMWRIGHT_PROC_PS_SNAPSHOT="$JR_SNAP_FILE" bash "$JR_PR"` call) is the correct side and is unchanged | header-only, no leg |
| F358 | `grep -nF 'so an item whose only merge evidence is a merged PR reads unknown, not merged_unstamped' loomwright/scripts/build-floor.sh` | 1 match (line 1293) | `fixed`: `loomwright/scripts/build-floor.sh`, the `backlog_basis` string now ends `reads unknown or its open-path state, not merged_unstamped` (backlog.sh steps 1–4 can still read such an item `in_flight` / `brief_shipped` offline; only step 5's `open` collapses to `unknown` — the wording of `docs/result-schemas/floor-projection.md`). :: `loomwright/scripts/test-build-floor.sh` (bl) leg `the backlog basis says an offline-unseen merged PR reads 'unknown or its open-path state', not merged_unstamped`, plus `MUTATION CONTROL: a basis tail of 'reads unknown, not merged_unstamped' turns the open-path assertion RED` | behaviour (emitted string), leg added |
| F196 | `grep -nF "The driver's header and \`skills/review-heal/SKILL.md\` point here and do not restate it." loomwright/docs/result-schemas/review-heal-next-step.md` | 1 match (line 3) | `fixed`: `loomwright/docs/result-schemas/review-heal-next-step.md`, the sentence now says `skills/review-heal/SKILL.md` points here and does not restate the step list, while the driver's header keeps a one-line-per-step `STEPS` index held equal to §"Steps" by `test-review-heal-next-step.sh`. The driver's header is unchanged. :: `loomwright/scripts/test-review-heal-next-step.sh` D legs `D: the driver header's STEPS names equal the driver's case arms, in order` (the `#   <name>  …` rows between `# STEPS — …` and the next blank `#`, compared to `$ARMS`), `MUTATION CONTROL: an extra '#   bogus' STEPS row turns the header-STEPS leg RED`, and `D: the doc names the driver header's STEPS index and the suite that holds it equal` | pin added, legs added |
| F221 (test half) | `grep -nF 'no "(20) self-heal-advisory/SKILL.md not readable at $SK' loomwright/scripts/test-system-contract.sh` | 1 match (line 1043), while `$SK` is `…/self-heal-advisory/completion-tail.md` (line 1041) | `fixed`: `loomwright/scripts/test-system-contract.sh` section 20's failure message names `self-heal-advisory/completion-tail.md`; the section's lead comment, which said the same stale file, now names it too | message/comment-only, no leg |
| F156 | `grep -rnE 'no fix (is )?pushed' loomwright/skills` and `grep -nF 'so no fix is pushed after a merge' CHANGELOG.md` | 0 matches in `loomwright/skills`; 1 match in `CHANGELOG.md` (line 111, the v17.2.0 entry) | `recorded`: CHANGELOG history is not rewritten and no skill prose carries the claim at base (the grep above), so there is no live copy to fix; the PR's changelog fragment (`changelog.d/dismissed-followups-06b-docs-and-evidence-drift.md`) carries one clarifying sentence: the v17.2.0 "no fix is pushed after a merge" means after an observed merge — a merge landing after `park-ask-gate`'s read is not prevented | recorded |

## Red results (AC2)

- **F358, red on base.** The worktree tree was copied to a scratch dir (`rsync -a --exclude .git`, then
  `git init` + one commit so the suite's repo probes resolve), `loomwright/scripts/build-floor.sh` was replaced
  with `git show edcdc2f:loomwright/scripts/build-floor.sh` (`diff` against the base blob: identical), and the
  fixed `test-build-floor.sh` was run there: `RESULT: 417 passed, 2 failed`, rc 1. The two failures:
  - `FAIL: the backlog basis does not name 'unknown or its open-path state': one item per requirement *.md … reads unknown, not merged_unstamped`
  - `FAIL: could not build the basis-tail mutant - control inconclusive` (the base has no fixed tail to revert,
    so the control reports itself inconclusive rather than passing).
  On the fixed tree: `RESULT: 421 passed, 0 failed, 1 skipped`, rc 0.
- **F196, red on a scratch driver with one extra `STEPS` row.** A scratch tree copy whose
  `review-heal-next-step.sh` has `#   bogus       x` inserted after the `#   finish  …` row:
  `PASS: 219 FAIL: 2`, rc 1 —
  - `FAIL: D: the driver header's STEPS names (start,round,…,finish,bogus) differ from the case arms (start,round,…,finish)`
  - `FAIL: MUTATION CONTROL: the extra-STEPS-row mutant was not built or the leg stayed green` (its own mutant
    then carries two `bogus` rows).
  A second scratch copy with the base-commit `review-heal-next-step.md` (`git show edcdc2f:…`):
  `PASS: 220 FAIL: 1` — `FAIL: D: the doc does not name the header's STEPS index and its pinning suite`.
  On the fixed tree: `PASS: 221 FAIL: 0`, rc 0.

## Validation

- Named suites on the fixed tree: `test-ci-slot.sh` 67 passed, 0 failed; `test-machine-load.sh` 20 passed,
  0 failed; `test-proc-registry.sh` 194 passed, 0 failed (its AC9 header leg still finds
  `LOOMWRIGHT_PROC_PS_SNAPSHOT`); `test-build-floor.sh` 421 passed, 0 failed, 1 skipped;
  `test-review-heal-next-step.sh` 221 passed, 0 failed; `test-system-contract.sh` 124 passed, 0 failed.
- `bash scripts/ci-local.sh --affected` after the edits: PASS, 24 entries (the early set, which includes
  `check-doc-currency.sh`, `check-token-budget.sh`, `check-prompt-history-refs.sh`, `check-version-bump.sh`
  and `build-capabilities.sh`, plus `test-automate-helpers-dispatch.sh`, `test-citation-drift.sh` and the six
  suites above). It listed three changed files as not covered: the fragment and this evidence file (no suite
  reads either), and `review-heal-next-step.md`, whose only reading suite is `test-review-heal-next-step.sh`
  (run, above).
- `bash scripts/check-version-bump.sh`: `check OK — not bumped (version 17.35.3, the merge base's); 1
  fragment(s) pending`. `bash scripts/bump-version.sh --dry-run` folds the fragment into a patch entry.
