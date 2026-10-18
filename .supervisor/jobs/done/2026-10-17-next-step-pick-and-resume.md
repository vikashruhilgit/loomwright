# Supervisor Job: next-step driver, part 3 — PICK, RECONCILE and resume move into the script; the legacy prose path is retired

## Environment
- **Project:** automate-2026-10-15-163325/L14 (lane L14 clone of the loomwright repo)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 2 (lane clone: out-of-scope findings go to `.supervisor/requirements/proposed/`, never a new Queue item; wave-4 sibling item 21 splits `loomwright/scripts/test-automate-helpers.sh`, which this item must touch for one pin — see Risk Assessment)
- **Source requirement:** .supervisor/requirements/automate-speed/08-next-step-pick-and-resume.md
- **Base commit:** a8819a38100d77fbeddc2ff1a56963e91f172a5d

## Feasibility
**Verdict:** CAUTION

| # | Check | Verdict | Detail |
|---|---|---|---|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + BSD userland + jq, same as `automate-next-step.sh` and every `automate-*.sh` helper |
| 2 | Dependency Availability | GO | dependency 07 is merged (PR #594, in base a8819a3); every helper the new steps call exists: `pick-guard`, `ceiling-check`, `dismissed-pending`, `dismissed-decide`, `reconcile-item`, `current-rebuild`, `closeout`, `closeout-classify`, `closeout-others`, `resume-glob`, `finalize-empty`, `trail-gate`, `trail-unstage`, `trail-pr`, `reconcile-status`, `meta-push-failed`, `config-restore`, `validation-gate`, `brief-repair` (arms in `automate-helpers.sh`, bodies in `automate-helpers.d/` or the sibling scripts) and `run-lock.sh acquire` (`run_lock_held owner=… pid=… age=…` exit 1, `run_lock_reentrant …` exit 0, `run_lock_degraded` on stderr) |
| 3 | Architecture Fit | GO | the driver already owns RUN → end of item through one sidecar, one writer set and one closed instruction schema; this item adds steps in front of `run` |
| 4 | Scope vs Supervisor Capability | CAUTION | three parts — driver head (PICK/RECONCILE/resume) + ~15 golden cases, legacy retirement across ~12 files and 3 test suites, and the inventory re-home + prose deletion to reach the 60% read-set target. Large but one coherent change; split into 3 sequential subtasks (context-bound) |
| 5 | Hard Blockers | CAUTION | (a) the requirement's AC "every `automate-loop` row's home is no longer `prose` except rows homed `global` or `judgment`" does not fit `test-loop-inventory.sh`'s home grammar (`prose`, `script:<file>[ <sub>]`, `hook:<leaf>`, `step-scoped`, `global`, `rationale:<doc>#<anchor>` — `judgment` is a row KIND, not a home). This brief reads it as: no row keeps home `prose` unless its kind is `judgment` (AC6). (b) the 60% target (≤ 89542 bytes default read set, from the as06 evidence's before-06 `223857`) cannot be reached by moving PICK/RECONCILE prose alone (today `180686`): Step 0's Always set and the SKILL.md index must shrink too — in scope by the requirement's Part B ("What remains in `skills/automate-loop/` is the coordinator loop, the instruction schema, the global rules … and intake") |

## Task
**Goal:** Make `loomwright/scripts/automate-next-step.sh` drive the whole `/automate` per-item loop — add the head of the loop (PICK: run lock, `pick-guard`, token ceiling, pending-decisions ask, `meta-push-failed` report; RECONCILE: in-flight item vs `gh`, `closeout` on a found merge classified by `closeout-classify` with the leftover question as an `ask` and `closeout_leftover` as its can't-ask park, the `drain_died` marker, the validation re-check, skip/abandon `trail-pr`; `trail-gate`; `trail-unstage`; the PICK `current-set` + `picked` line; and resume: `current-rebuild`, the config crash-restore, `reconcile-status` dry-run lines and the continue/start-new/archive choice) — then retire the `--legacy` prose path and the migrated prose, so `skills/automate-loop/` holds only the coordinator loop, the instruction schema, the global rules and intake, and the default `/automate` read set is at least 60% smaller than before item 06.

**Problem Statement:**
The `/automate` coordinator needs the head of the per-item loop to be script-driven because it is the last prose-executed part of the loop and every item re-reads it (plan §Why now: most of the read set is bookkeeping prose).
Currently PICK, RECONCILE and resume (`per-item-loop.md` §6 step 1, `resume.md` §4–§5) are executed by the model from prose, and `--legacy` still ships the full pre-driver tail in `legacy-tail.md` (58252 bytes).
Success looks like: the model runs one short loop — "run next-step; do the one instruction; report the result" — every golden case passes through the driver byte-identically, and `--legacy` no longer exists.

## Acceptance Criteria
- [ ] AC1 — Given each PICK / RECONCILE / resume golden case under `loomwright/scripts/fixtures/automate-golden/` — at least `pick-current-set-then-picked`, `pick-pending-decisions-ask`, `pick-time-lane-guard-park`, `pick-time-token-ceiling-park`, `pick-time-trail-gate-park`, `reconcile-closeout-merged`, `brief-repair-merged`, `gate-validation-recheck-at-reconcile`, `resume-ambiguous-park`, `resume-config-crash-restore`, `resume-current-rebuild`, `resume-glob-finalize`, `resume-rate-limit-park`, `resume-reconcile-status`, `skipped-item-check-off` — when its `input.md` + `tree/` + `gh.stub` + `setup` are driven through `automate-next-step.sh` by a new per-case `next-step.results` file (the existing grammar — `env:` / `pre:` / `call:` / `expect:` / `expect-exit:` / `gh:` / `file:` / `sidecar:` / `out:` — extended additively and documented in the test header if a case needs it), then the resulting run file is byte-identical to that case's existing `expected.md` (same normalisation as today) — asserted by `loomwright/scripts/test-automate-next-step.sh`, every one of these cases added to `REQUIRED_CASES`. Existing `input.md` / `expected.md` / `expected.out` / `steps` are read-only; model-authored free-text lines arrive through `--result` (`progress_note` / `progress_notes`), never by editing an expected file. A case whose behaviour is genuinely not a driver step (a can't-ask stop that writes nothing, or a pure helper call) is named in the evidence file with the reason and covered by a driver leg instead.
- [ ] AC2 — Given a run whose in-flight `## Current` item has an OPEN PR (status `awaiting_merge` or `escalated`), or whose own trail PR `chore/<run_id>-trail-<n>` is open (or its state unreadable), when the driver is asked to pick (`--start pick`, exact flag the worker's), then it writes today's park — `## Status: paused`, `pause_reason` unchanged/`trail_pr_open` as today, the same `## Progress` lines the golden cases pin — releases the run lock it took, prints `{"do":"park",…}`, and writes NO `picked` line and NO `current-set --item` for a new item — asserted by a `test-automate-next-step.sh` leg plus Validation 2's mutation control.
- [ ] AC3 — Given RECONCILE's `closeout` returns a leftover (`closeout-classify` prints anything but `complete`), when the run is interactive the driver prints `{"do":"ask",…}` with gate `AUT-LEFTOVER` and the catalog labels `Clean up now` / `Keep and continue` / `Stop` (human-only: the question carries no policy-answerable code beyond the catalog's own), batching ≤ 4 leftovers per ask; `--result '{"cant_ask":true}'` or `--non-interactive` takes the `closeout_leftover` park (`## Status: paused`, `current-set --pause-reason closeout_leftover`, one `closeout leftover: <run_id> <step> <detail>` line per leftover, run-lock release, no `trail-pr`) — the same lines the existing `closeout-leftover-gate-non-interactive` case pins; a `run_lock_held`-only answer at START (from `closeout-others`) is not a leftover, as today — asserted by driver legs.
- [ ] AC4 — Given the resume entry (exact shape the worker's — e.g. `automate-next-step.sh --resume <automate_dir> [--run <run_id>]`), when exactly one / more than one incomplete run exists and the run is interactive, then the driver prints `{"do":"ask",…}` with `header: "AUT-RESUME"` and options `Continue` · `Start new` · `Archive`; under `--non-interactive` with one run and no explicit run id it prints the `automate: resume_requires_flag_non_interactive <run_id>` stop and writes nothing to the incomplete run (no `current-set`, no `progress-append`), with more than one it takes `resume_ambiguous` exactly as `resume-ambiguous-park` pins; on continue it runs `current-rebuild`, the stranded-config-backup restore (`config-restore`, `resume-config-crash-restore`), the `drain_died` marker check, the reconcile and the `reconcile-status` dry-run `## Progress` lines (`resume-reconcile-status`), then PICK — asserted by driver legs and the AC1 cases.
- [ ] AC5 — Given the change, when `bash loomwright/scripts/test-loop-inventory.sh` runs, then it passes, and in `loomwright/docs/loop-inventory/automate-loop.md` no row has home `prose` except rows whose kind is `judgment` (the requirement's "homed `global` or `judgment`": `judgment` is a kind in the test's grammar, so this is the faithful reading — stated in the evidence file); every row re-homed `script:automate-next-step.sh <step>` names a real `case` arm; rules whose prose is deleted keep their row (owner decision D1: moving prose never drops a rule) with a `script:` / `hook:` / `step-scoped` / `global` / `rationale:` home recorded BEFORE the prose is removed; `## Sources` no longer lists `legacy-tail.md`.
- [ ] AC6 — Given the change, when `grep -rn -- '--legacy' loomwright/commands loomwright/skills loomwright/scripts/automate-next-step.sh` runs and `test -e loomwright/skills/automate-loop/legacy-tail.md` is checked, then neither the flag nor the file exists (historical `docs/evidence/*` mentions excepted), `commands/automate.md` describes the driver loop ("run next-step; do the one instruction; report the result") in its overview and Step 0, its Parameters table has no `--legacy` row, and every reference listed in the fact sheet (SKILL.md §1.5 row + split block + flag list; `per-item-loop.md`; `lanes.md`; `modes-and-merge-gate.md`; `docs/ARCHITECTURE_CONTRACTS.md`; `docs/result-schemas/automate-run.md`; `loomwright/docs/vendor-coupling-manifest.json` (its `legacy-tail.md` count and reason keys; the `per-item-loop.md` reason text); the driver header; `MAP.tsv` comments) is removed or repointed in the same change.
- [ ] AC7 — Given the tests that read `legacy-tail.md` — `test-automate-helpers.sh` (`QG_LOOP=…legacy-tail.md`, leg QG3a), `test-automate-dismissed.sh` (`LGT=…legacy-tail.md`, "anchor lives once, in legacy-tail.md only", and the later leg near its line 774), `test-automate-trail.d/05-finalize-closeout-others.sh` (NT6 legs on legacy-tail step 5/6 text), — when the file is deleted (and `test-automate-loop-split.sh` legs B, C, F, which build the split-file list from disk, the SKILL.md split blocks and Step 0, stay green because the SKILL.md split block and the Step 0 entry are removed together, AC6), then each leg is repointed to where the rule now lives (the driver source or its schema section) or replaced by an equivalent driver assertion, never deleted to make the suite pass, and every mutation control stays valid (non-empty + differs + `bash -n`) — `bash` of each suite reports 0 failures.
- [ ] AC8 — Given the change, when `docs/evidence/automate-speed-baseline.md` is read, then it carries a "Read set (item 08)" section with `wc -c loomwright/skills/automate-loop/*.md loomwright/commands/automate.md` before (base a8819a3) and after, the default-mode read set before item 06 (`223857`, from `docs/evidence/as06-next-step-driver-tail.md` "Before / after"), before this item (`180686`) and after, and the after value is ≤ `89542` (≥ 60% smaller than `223857`); the default read set is defined exactly as as06 defined it — Step 0's **Always** files on a sequential `/automate` run (whatever that set is after this change) — plus each Validation 1 suite's `<passed>/<total>` and the inventory `## Counts` before/after.
- [ ] AC9 — Given the change, when `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not " | cut -d: -f1 | sort -u` runs, then it prints the same file list as base a8819a3 (minus `legacy-tail.md` only if it was on it) — asserted by the existing `test-automate-next-step.sh` S leg; and `bash loomwright/scripts/test-automate-golden.sh` stays green (every removed unit's `MAP.tsv` row removed and every new unit mapped in the same change; `### Termination (two exits)` handling of M5/M8 kept or repointed with the unit).

## Validation (must pass before merge)
1. `bash loomwright/scripts/test-automate-next-step.sh`, `test-automate-golden.sh`, `test-automate-helpers.sh`, `test-automate-lanes.sh`, `test-loop-inventory.sh`, `test-automate-dismissed.sh`, `test-automate-trail.sh`, `test-automate-loop-split.sh`, `test-result-schemas-split.sh`, `bash scripts/check-doc-currency.sh`, `bash loomwright/scripts/test-citation-drift.sh`, `bash scripts/check-token-budget.sh`, `bash scripts/check-version-bump.sh`, `bash scripts/check-vendor-coupling.sh`; report `<passed>/<total>` in the evidence file.
2. Mutation control (inside `test-automate-next-step.sh`, mutant gated non-empty + differs + `bash -n`): a driver copy whose PICK skips the open-PR / trail-PR park and proceeds to `current-set` + `picked` ⇒ the AC2 leg goes red.
3. Running system (scoped to what a lane can run hermetically, as items 06/07 did): in a scratch `git init` repo (gh stubbed, no network), a run parked `awaiting_merge` whose PR the stub reports `MERGED`, driven through the resume entry: paste the `closeout` lines and the next `picked` line from the run file's `## Progress`, fenced, into the evidence file AND the PR body under a `validation 3` line. Validation 1 and 2 output is also pasted, fenced, under `validation 1` / `validation 2` lines in the PR body (the `validation-gate` reads all three from the PR body); the evidence file stays the authority. A live `/automate --resume` session is NOT run in the lane — say so under "Not verified".

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound — subtask 1 (driver head steps + resume entry + ~15 `next-step.results` fixtures + legs, several hundred lines of bash against the helper contracts), subtask 2 (legacy retirement across commands/skill/docs/manifest and three test suites' pins) and subtask 3 (inventory re-home of ~465 prose rows + prose deletion + Step 0 reshape + read-set evidence) each fill a worker context; 2 consumes 1's step names, 3 consumes 1's and 2's results.
- **Lane PR rule:** this runs in a `--parallel` lane — ship `changelog.d/as08-next-step-pick-and-resume.md` (`<!-- bump: minor -->`), never a version bump; `bash scripts/check-version-bump.sh` passes.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Phase 3: File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|---|---|---|---|
| driver | `loomwright/scripts/automate-next-step.sh` | — | HIGH |
| driver-test | `loomwright/scripts/test-automate-next-step.sh`; `loomwright/scripts/fixtures/automate-golden/<PICK/RECONCILE/resume cases>/` (a new `next-step.results` per case only) | — | HIGH |
| schema | `loomwright/docs/result-schemas/automate-run.md` (§"next-step instruction": new steps, new `--start`/resume entry, new `ask` gates `AUT-RESUME` and the pending-decisions ask, removal of the `--legacy` mention) | — | HIGH |
| legacy retirement | `loomwright/commands/automate.md`, `loomwright/skills/automate-loop/SKILL.md`, `loomwright/skills/automate-loop/per-item-loop.md`, `loomwright/skills/automate-loop/lanes.md`, `loomwright/skills/automate-loop/modes-and-merge-gate.md`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (the one `--legacy` line + the Prompt Token Budgets mirror rows), `loomwright/docs/vendor-coupling-manifest.json` (the `legacy-tail.md` entries) | — (delete `loomwright/skills/automate-loop/legacy-tail.md`) | HIGH |
| pinned tests | `loomwright/scripts/test-automate-helpers.sh` (QG_LOOP / QG3a only), `loomwright/scripts/test-automate-dismissed.sh` (LGT legs), `loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` (NT6 legs), `loomwright/scripts/test-automate-loop-split.sh` (only if a leg hard-codes the split list), `loomwright/scripts/test-automate-golden.sh` (only `PROSE_FILES` / M4–M8 anchors if a source file loses its units), `loomwright/scripts/fixtures/automate-golden/MAP.tsv` | — | MEDIUM |
| prose + inventory | `loomwright/skills/automate-loop/resume.md`, `per-item-loop.md`, `modes-and-merge-gate.md`, `invariants.md`, `intake.md`, `branch-mode.md`, `command-lanes.md`, `SKILL.md` (only where prose is deleted or repointed), `loomwright/docs/loop-inventory/automate-loop.md`, `loomwright/docs/prompt-token-budgets.json` (re-measure the shrunk skill/command entries) | `docs/evidence/automate-speed-baseline.md` gets a new section (file exists) | MEDIUM |
| release | — | `changelog.d/as08-next-step-pick-and-resume.md` | HIGH |

> **Validator-owned surfaces:** `test-loop-inventory.sh` (every `###`/`####` heading of every source file needs a row; `prose`/`global` anchors must be live; `script:<file> <sub>` must be a real case arm; `## Sources` / `## Counts` / gap list equal the table), `test-automate-golden.sh` (units extracted live from `resume.md` / `per-item-loop.md` / `modes-and-merge-gate.md` headings and column-0 numbered items — a deleted unit leaves a stale MAP row, a new one is unmapped), `test-automate-loop-split.sh` (SKILL.md index ↔ split files, the "Cited sub-section anchors" table, Step 0's index-only list naming every split file in order), `test-result-schemas-split.sh`, `check-doc-currency.sh`, `test-citation-drift.sh` (pinned citations — a deleted pin target must be repointed), `check-token-budget.sh` (`.skills[automate-loop]` budget 87895 / measured 79904; `.commands[automate]` 7565 / 6001 — re-measure after shrinking, change `measured` and the `ARCHITECTURE_CONTRACTS.md` mirror row in the same commit).

## Touched-file invariants
> Grounded at base `a8819a38100d77fbeddc2ff1a56963e91f172a5d`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-next-step.sh`** — keep: the closed instruction set `{"do":"spawn",…}` / `{"do":"ask",…}` / `{"do":"park",…}` / `{"do":"done",…}`; the exit-code contract (`Exit codes: 0 an instruction printed (or a NEXT_STEP_UNTIL stop); 1 a helper / writer failure`; exit 2 = nothing written); the idempotent re-print of a pending instruction; the sidecar binding of pending state to item + PR; REPORT VALIDATION before the first write and `NS_RESERVED_PREFIXES` (any new driver-authored line prefix — e.g. `trail-gate`, `trail-unstage`, `picked`, `closeout leftover`, `reconcile-status:` — is already or must be on that list, and R12 checks coverage); the WRITERS rule `The run file is written ONLY through automate-helpers.sh` (`current-set` BEFORE the `picked` line — the reverse order trips `progress-append`'s exit 3 `current_not_set`, which is surfaced, never swallowed); reuse `NEXT_STEP_LOCK_CMD` for the PICK acquire (`acquire --owner automate:<run_id> --session-id <sid>`), `ns_emit` / `ns_emit_park` / `ns_progress` / `ns_status` / `ns_release` / `st_set` / `st_del`; the driver never merges — `gate-eval` stays the only executor; never a multi-line value through `awk -v`. Header text that becomes false: the Honest-limits sentence "PICK / RECONCILE / resume (item 08) stay prose, including RECONCILE's crash-restore of a stranded config backup.", the USAGE paragraph's `(\`--legacy\`) starts GATE`, and the "§6 steps 2–6, §7 and §9/§10" protocol pointer — rewrite all three. Pinned by `test-automate-next-step.sh` (`REQUIRED_CASES`, the D leg comparing the schema's `step` list with the real `case` arms, the S leg).
- **`loomwright/scripts/automate-helpers.sh` and siblings** (NOT edited — called): `pick-guard` prints `ok` or `refuse: live_lane <lane_run_id> <lane>` (exit 1, fail CLOSED on any `refuse:`); `ceiling-check` prints `OK …` / `PARK: token_ceiling …` / `PARK: ledger_unreadable`, always exit 0; `trail-gate` prints `trail-gate: PARK — …` or `trail-gate: clear — …`, always exit 0; `closeout-classify` prints exactly `complete` or `leftover\t…` / `run_lock_held\t…` rows (anything but exactly `complete` is a leftover inside the loop); `current-rebuild` prints `current_rebuilt: <item> pr <url|null> state <s>` or `current-rebuild: skipped — ## Current set`; `dismissed-pending` prints a count or `unknown` (`unknown` ⇒ ask, fail closed); `reconcile-status` without `--apply` writes nothing — only its `plan\t…` rows become `reconcile-status: would stamp <file> (<status>)` lines; `closeout` with `--session-id` RE-ENTERS the PICK lock.
- **`loomwright/scripts/test-automate-next-step.sh`** — keep every existing leg and mutation control green; extend the `next-step.results` grammar only additively, documented in its header; hermetic setup unchanged (sandboxed HOME, stub `gh` first on PATH).
- **`loomwright/scripts/test-automate-helpers.sh`** — ONE edit only: repoint `QG_LOOP` (and the QG3a leg that reads it) away from the deleted `legacy-tail.md`; touch nothing else (wave-4 item 21 is splitting this file — a wider edit turns the wave merge into a conflict).
- **`loomwright/scripts/test-loop-inventory.sh`** (NOT edited): home grammar `prose, script:<file>[ <sub>], hook:<leaf>, step-scoped, global or rationale:<doc>#<anchor>`; `prose`/`global` rows need live anchors; `## Counts` equals the table.
- **`loomwright/scripts/test-automate-golden.sh`**: `PROSE_FILES="resume.md per-item-loop.md modes-and-merge-gate.md"`; `FAIL: stale map row <id>` fires when a unit disappears; M5/M8 hard-code `### Termination (two exits)` — edit only what a deletion forces, with MAP.tsv in the same change.
- **`loomwright/commands/automate.md` + `test-automate-loop-split.sh`** — Step 0's index-only list names every split file in documented order (`**Always**` / `**Only when**` triggers); removing `legacy-tail.md` means removing its SKILL.md split block AND its Step 0 entry together; `4. **Per-item loop.**`-style overview lines keep the single-drain qualifier `at most one owner-requested fix-now re-drain per item`.
- **`loomwright/scripts/test-automate-dismissed.sh`** — the `SURF` anchors and the unqualified "exactly ONE inline" scan stay satisfied: any stub that mentions an owned inline drain carries the qualifier; `SK` is assembled from SKILL.md + every split file by `fixtures/automate-loop-split/assemble.sh` (follows the split markers).
- **`loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh`** — the NT6 legs read §6 steps 5/6 out of `legacy-tail.md` through `nt_legacy()` (`awk '/^## Legacy tail — /…'`) under the comment beginning "tail is scripts/automate-next-step.sh, the prose is the --legacy path"; repoint them to where SYNC / CHECK OFF now live (the driver's `sync` / `checkoff` arms) and keep the `nt6-legacy-mutant` control valid.
- **`loomwright/docs/vendor-coupling-manifest.json`** (consumed by `scripts/check-vendor-coupling.sh`): remove the `"loomwright/skills/automate-loop/legacy-tail.md": 3` count entry and its reason entry; any per-file allowance that changes because prose moved (e.g. `per-item-loop.md`) is updated with a reason string in the same style; `check-vendor-coupling.sh` stays green.
- **`loomwright/skills/automate-loop/per-item-loop.md` and `modes-and-merge-gate.md`** — both are on `test-automate-next-step.sh`'s S-leg `SURFACE_BASE` and named in CLAUDE.md §Failure-Mode Invariants as surfaces of the positive-form merge grep: whatever shrinking subtask 3 does, keep the positive-form `gh pr merge --squash` line(s) they carry today (or change the S leg's list, CLAUDE.md's enumeration and `invariants.md` §11's list in the same change — the house rule on restated lists), so AC9 stays green.
- **`loomwright/docs/prompt-token-budgets.json`** — `measured` must equal the mirror row in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets", changed in the same commit.

## Closed enumerations touched
> Sibling grep at base `a8819a3`: `grep -rnF '"fix-now re-drain"' loomwright/` → `automate-next-step.sh`, `test-automate-next-step.sh`, `docs/result-schemas/automate-run.md` (the `spawn` row). `grep -rnF 'AUT-LEFTOVER' loomwright/` → `lane-policy.sh` catalog, `docs/LANE_GATES.md`, `automate-next-step.sh`, `docs/result-schemas/automate-run.md`.

- **New driver steps** (sibling: `sync`) — e.g. `pick`, `reconcile`, `trail-gate`, `resume` (final names the worker's) — must be named in: `automate-next-step.sh` `ns_dispatch` arms + the header STEPS block; `docs/result-schemas/automate-run.md` "Common fields" `step` list (the D leg compares it with the arms); `docs/loop-inventory/automate-loop.md` homes.
- **New `--start` value / resume entry** (sibling: `--start run|drain`) — named in the driver USAGE, its arg parser's refusal message, and the schema.
- **`ask` gates** (sibling: `AUT-DISMISS`) — the driver newly emits `AUT-RESUME` (continue / start new / archive) and `AUT-PENDING` (the PICK-time pending-decisions ask, human-only, labels `Follow-up (keep draft)` · `Drop`), and emits the EXISTING `AUT-SUMMARY` gate at a new point (PICK); all three are already in `lane-policy.sh catalog` / `docs/LANE_GATES.md` — add `AUT-RESUME` and `AUT-PENDING` to the schema's ask-gate list beside `AUT-WAIVE` / `AUT-DISMISS` / `AUT-SUMMARY` / `AUT-LEFTOVER`. No new gate code is invented.
- **No new** `pause_reason` / `status` value: `trail_pr_open`, `token_ceiling`, `live_lane`, `run_lock_held`, `closeout_leftover`, `resume_ambiguous`, `drain_died` already exist in `current-set`'s enums.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-automate-next-step.sh` — AC2 open-PR / trail-PR park leg | in a driver copy, skip the `trail-gate` / open-PR park branch and fall through to `current-set` + `picked` (Validation 2) |
| `test-automate-next-step.sh` — AC3 leftover leg | in a driver copy, treat any `closeout-classify` output as `complete` |
| `test-automate-next-step.sh` — AC4 non-interactive single-run stop | in a driver copy, auto-pick `Continue` when the run cannot ask |
| `test-automate-helpers.sh` — QG3a / QG3a' repointed from `legacy-tail.md` to the driver's park-first order | in a driver copy, move the `park-ask-gate --wait 75` call before the park write / watcher / lock release |
| `test-automate-dismissed.sh` — B "anchor lives once" legs (LGT) repointed | duplicate the repointed anchor into a `per-item-loop.md` stub (the existing stub-anchor mutant, kept against the new home) |
| `test-automate-trail.d/05-finalize-closeout-others.sh` — NT6 step 5/6 legs repointed to the driver `sync` / `checkoff` arms | in a driver copy, drop `--no-trail` from the `sync` arm's `closeout` call / check the item off a second time in `checkoff` |
| `test-automate-next-step.sh` — PICK order leg (`current-set` before `picked`) | in a driver copy, swap the two writes (exit 3 `current_not_set` must surface) |

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory

## Design notes (binding for the worker)
- **Coordinator loop.** After this item the model's whole per-item job is: call `automate-next-step.sh <rf> --start pick …` (or the resume entry), do the ONE instruction it prints (`spawn` the named work and report it, `ask` its questions and report the answers or `{"cant_ask":true}`, stop on `park`, and on `{"do":"done","status":"running"}` call `--start pick` again), never writing the run file itself. Intake (new run: source → Queue → run file, `queue-confirm`) stays model judgment in `intake.md`; the start order before a run file is targeted (`init-check`, `meta-entry`, `closeout-others`, `resume-glob --finalize`) may stay a short step list in the coordinator prose or move into the resume entry — the worker's call, documented in the schema.
- **PICK order (today's, unchanged):** run-lock acquire FIRST (`run_lock_held` ⇒ park, nothing else touched; `run_lock_degraded` ⇒ one note, proceed) → `pick-guard` (refuse ⇒ `live_lane` park + release) → `ceiling-check` when `max_tokens` is in `## Run Config` → `meta-push-failed` report (branch mode) → pending-decisions ask (interactive only; gate `AUT-PENDING`: Follow-up (keep draft) / Drop, a summary draft under `AUT-SUMMARY` in a call of its own) → RECONCILE (`closeout --session-id` on `merged`, leftover gate, validation re-check, `drain_died`, skip/abandon `trail-pr`) → `trail-gate` → `trail-unstage` → `current-set … --status running --pr null --branch null --pause-reason null` → `picked <item>` → the existing `run` step. `--limit` termination stays the existing `terminate` step.
- **Byte parity:** where prose pins an exact line, the driver writes exactly that; where a golden `expected.md` carries a model-authored line, it arrives through `--result` free text (schema documents which).
- **D1 before deletion:** in subtask 3, each prose rule gets its inventory home first (script / hook / step-scoped / global / rationale), then its prose is deleted or reduced to the coordinator loop; stories/history the owner wants kept move to a rationale doc only if it already exists — creating `loomwright/docs/rationale/automate-loop.md` is item 16's (Non-goal here), so prefer deleting prose whose rule a script enforces over moving it.
- **Read-set lever (60%):** the default set is Step 0's **Always** files. Expected shape after: `SKILL.md` (index + coordinator loop + global rules + the §1.5 helper table reduced to what the coordinator needs, or moved to a split file read **Only when** a helper's behaviour is in question) + a short `per-item-loop.md` (the coordinator loop) + `invariants.md`; `modes-and-merge-gate.md` and `resume.md` become **Only when** reads (the driver owns GATE and resume) or shrink to pointers. Measure, do not assume.
- **Not migrated (Non-goals):** fresh sessions per phase (item 09); a prompt diet of what remains beyond what the 60% target forces (item 16); lane coordinator prose (`lanes.md`, `command-lanes.md`) beyond `--legacy` references — their inventory rows may take `script:automate-lanes.sh <sub>` / `step-scoped` homes without prose deletion.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Driver head: PICK, RECONCILE, trail gate/unstage, resume entry; schema; `next-step.results` fixtures + legs; changelog fragment; evidence (driver section) | AC1–AC4, AC9 (S leg), Validation 1–3 (driver legs) | 3 modify + ~15 fixture files, 1 create | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Retire `--legacy`: delete `legacy-tail.md`, its flag and every reference; repoint the pinned tests | AC6, AC7 | ~12 modify, 1 delete | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 3 | Inventory re-home (D1) + migrated-prose deletion + Step 0 reshape + MAP.tsv + budgets + read-set evidence | AC5, AC8, AC9 (golden) | ~12 modify | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` | BLOCKED (by #2) |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/automate-next-step.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-next-step.sh"}
  - {kind: "file", path: "loomwright/scripts/fixtures/automate-golden/pick-current-set-then-picked/next-step.results"}
  - {kind: "file", path: "loomwright/scripts/fixtures/automate-golden/reconcile-closeout-merged/next-step.results"}
  - {kind: "file", path: "loomwright/scripts/fixtures/automate-golden/pick-time-trail-gate-park/next-step.results"}
  - {kind: "file", path: "loomwright/scripts/fixtures/automate-golden/resume-config-crash-restore/next-step.results"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "next-step instruction"}
  - {kind: "file", path: "changelog.d/as08-next-step-pick-and-resume.md"}
requires: []
lanes:
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.sh"
  - "loomwright/scripts/fixtures/automate-golden/*/next-step.results"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "changelog.d/as08-next-step-pick-and-resume.md"
  - "docs/evidence/automate-speed-baseline.md"
external_requires:
  - "jq on PATH (already required by automate-helpers.sh)"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/commands/automate.md", name: "Step 0"}
  - {kind: "file", path: "loomwright/skills/automate-loop/SKILL.md"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/automate-next-step.sh"}
  - {from: "1", kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "next-step instruction"}
lanes:
  - "loomwright/skills/automate-loop/legacy-tail.md"   # deleted
  - "loomwright/commands/automate.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/skills/automate-loop/lanes.md"   # the one --legacy reference only
  - "loomwright/skills/automate-loop/modes-and-merge-gate.md"   # the one --legacy reference only
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"   # the --legacy line only
  - "loomwright/docs/result-schemas/automate-run.md"   # the --legacy line only (sequential share with subtask 1)
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/scripts/automate-next-step.sh"   # header --legacy wording only (sequential share with subtask 1)
  - "loomwright/scripts/test-automate-helpers.sh"   # QG_LOOP / QG3a only
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh"
  - "loomwright/scripts/test-automate-loop-split.sh"   # only if a leg hard-codes the split list
  - "loomwright/scripts/fixtures/automate-golden/MAP.tsv"   # comment lines only
  - "loomwright/docs/loop-inventory/automate-loop.md"   # legacy-tail rows re-filed; Sources line
external_requires: []

# Subtask 3
provides:
  - {kind: "file", path: "loomwright/docs/loop-inventory/automate-loop.md"}
  - {kind: "symbol", path: "docs/evidence/automate-speed-baseline.md", name: "Read set (item 08)"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/automate-next-step.sh"}
  - {from: "2", kind: "file", path: "loomwright/skills/automate-loop/SKILL.md"}
lanes:
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/skills/automate-loop/resume.md"
  - "loomwright/skills/automate-loop/modes-and-merge-gate.md"
  - "loomwright/skills/automate-loop/invariants.md"
  - "loomwright/skills/automate-loop/intake.md"
  - "loomwright/skills/automate-loop/branch-mode.md"
  - "loomwright/skills/automate-loop/command-lanes.md"
  - "loomwright/skills/automate-loop/lanes.md"   # pointer edits only
  - "loomwright/commands/automate.md"
  - "loomwright/scripts/fixtures/automate-golden/MAP.tsv"
  - "loomwright/scripts/test-automate-golden.sh"   # PROSE_FILES / M4–M8 anchors only if a deletion forces it
  - "loomwright/scripts/test-automate-dismissed.sh"   # SURF anchors only if a deletion forces it
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"   # the Prompt Token Budgets mirror rows only
  - "docs/evidence/automate-speed-baseline.md"   # sequential share: subtask 3 fills the read-set section
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `automate-next-step.sh` (header), `docs/result-schemas/automate-run.md` | YES (ordered by `requires`) |
| Subtask 2 | Subtask 3 | `SKILL.md`, `per-item-loop.md`, `commands/automate.md`, `lanes.md`, `modes-and-merge-gate.md`, inventory, `MAP.tsv`, `test-automate-dismissed.sh`, `ARCHITECTURE_CONTRACTS.md` | YES (ordered by `requires`) |
| Subtask 1 | Subtask 3 | `docs/evidence/automate-speed-baseline.md` | YES (ordered by `requires`) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2
- **Batch 3:** Subtask 3
- **Recommended workers:** 1
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `loomwright/skills/automate-loop/SKILL.md` §1.5 (helper contracts), `per-item-loop.md` §6 step 1 + §8, `resume.md` §4–§5; `skills/unit-testing/SKILL.md` |
| 2 | `loomwright/skills/automate-loop/SKILL.md` (split index), `commands/automate.md` Step 0; `skills/unit-testing/SKILL.md` |
| 3 | `loomwright/docs/loop-inventory/automate-loop.md` + `test-loop-inventory.sh` (home grammar), `.supervisor/requirements/automate-speed/_BACKLOG.md` owner decisions D1/D2/D5; `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| The requirement's "homed `global` or `judgment`" does not fit the inventory grammar (`judgment` is a kind) (source: Feasibility (Phase 2.5)) | MEDIUM | AC5 reads it as "kind `judgment` may stay `prose`"; the evidence file states the reading; if the owner meant a new home value it is a one-line follow-up in `test-loop-inventory.sh` |
| The 60% read-set target needs Step 0 and SKILL.md to shrink, which borders item 16's prompt diet (source: Feasibility (Phase 2.5)) | HIGH | Shrink only by deleting prose whose rule is homed (D1) and by moving driver-owned files to **Only when** reads; measure each step; if ≤ 89542 is unreachable without a diet, stop and report the measured value rather than over-cut — AC8 then fails visibly, never silently |
| Wave-4 item 21 splits `test-automate-helpers.sh` in parallel; this item's QG_LOOP repoint edits it | HIGH | Edit only the `QG_LOOP` assignment and the QG3a leg (one hunk); name the hunk in the PR body so `wave-build`'s merge (or the owner after a STOPPED) re-applies it into `test-automate-helpers.d/` |
| Re-homing ~465 rows by hand drops a rule or mis-cites a case arm | HIGH | D1 order (home first, then delete); `test-loop-inventory.sh` checks script arms and live anchors; keep every row, change homes only |
| Deleting prose units makes MAP.tsv rows stale / renumbers `L<k>.<n>` units; M5/M8 hard-code `### Termination (two exits)` | HIGH | Update MAP.tsv in the same commit; run `test-automate-golden.sh` before hand-back; repoint M-legs only if their anchor is deleted |
| Pointer stubs reuse a first-match anchor or drop the single-drain qualifier (`test-automate-dismissed.sh` SURF / qualifier scan) | HIGH | Any remaining stub that mentions an owned inline drain carries `at most one owner-requested fix-now re-drain per item` |
| PICK proceeding with an open PR breaks the single-open-PR invariant | HIGH | AC2 + Validation 2 mutation control |
| A second merge path appears | HIGH | Driver calls `gate-eval` only; existing S leg (AC9) |
| `validation-gate` reads `## Validation` 1–3 from the PR body and marks each NOT-RUN without a matching fenced `validation <n>` passage | MEDIUM | FINALIZE pastes fenced output under `validation 1` / `validation 2` / `validation 3` lines and links the evidence file |
| Validation 3 is a hermetic scratch-repo drive, not a live `/automate --resume` | LOW | Stated under "Not verified"; the requirement's Measurements (next 2 real items on the driver path) are post-merge |

## Plan Review: PASS (attempt 2/3)
| # | Severity | Section | Description | Resolution |
|---|----------|---------|-------------|------------|
| 1 | BLOCKING | File Impact Map / Subtask 2 lanes | vendor-coupling manifest path was `loomwright/scripts/` (real: `loomwright/docs/`) | fixed (attempt 1) |
| 2 | MEDIUM | Closed enumerations | `AUT-PENDING` missing; `AUT-SUMMARY` is an existing gate | fixed (attempt 1) |
| 3 | MEDIUM | Touched-file invariants | NT6 legs, manifest + `check-vendor-coupling.sh`, SURFACE_BASE merge-line rule | fixed (attempt 1) |
| 4 | MEDIUM | Pin mutations | no rows for repointed pins | fixed (attempt 1) |
| 5 | LOW | AC7 | `test-automate-loop-split.sh` legs do not read legacy-tail.md | fixed (attempt 1) |
| 6 | LOW | Touched-file invariants / Risk | the QG3a repoint in `test-automate-helpers.sh` is the contiguous QG_LEAD/qg_list/qg_order/qg_lead block + its mutants (from the `QG_LOOP=` assignment on), not one line — or repoint QG_LOOP to a schema section that keeps the park-first numbered list verbatim so the extractor stays unchanged; name the block in the PR body for item 21's re-apply | deferred (below fix floor MEDIUM; owner chose Save and exit) |

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-17-next-step-pick-and-resume.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-18T08:59:53Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/599
- **Branch:** feature/as08-next-step-pick-and-resume
- **Files changed:** 35
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** automate-next-step.sh now drives the whole per-item loop (resume, PICK, RECONCILE, trail gate/un-stage, current-set+picked); 14 PICK/RECONCILE/resume golden cases byte-identical (brief-repair-merged a named exception, leg P6); --legacy and legacy-tail.md retired with pinned legs repointed to the driver; every non-judgment inventory row re-homed; default read set 223857 (pre-06) → 50412 bytes via Step 0 reshape (no prose deleted). Phase 4.5: 3 reviews / 3 fix rounds (it1: leftover-retry rc, coordinator-run pick, merge-watch note, CI grep -q; it2: resume-arm coordinator stop vs AC4, 'nothing written' claims, stale evidence; it3: parallel-marker whitespace, changelog figure) — iteration-3 fix ce24faf not re-reviewed. Ground truth 2/2; risk high (pattern-based).

## Not verified
- **live /automate --resume session** — hermetic scratch drive only (subtask 1)
- **coordinator prose calling --resume / --start pick** — no live run (subtask 1)
- **live_lane park in a real --parallel wave** — golden case static lane table only (subtask 1)
- **live /automate session on the driver-only path (no --legacy)** — no live run in the lane (subtask 2)
- **/automate coordinator using the new Step 0 (SKILL.md + invariants.md only)** — no live run; model adherence untested (subtask 3)
- **Only-when triggers for helpers.md / resume.md / per-item-loop.md / modes-and-merge-gate.md** — prose triggers, untested (subtask 3)
