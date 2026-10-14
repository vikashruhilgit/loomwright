# Evidence — automate-speed/02: Phase 4.5 spends its rounds on new defects

Recorded 2026-10-14 on branch `feature/automate-speed-02-phase45-rounds` (base `1908111`), macOS, bash 3.2.
Every command ran from the repo root. Nothing here was run against a production service: the only live
reads are read-only `gh` calls against `vikashruhilgit/loomwright` PR #533 (Validation 3c).

## 1. Test results (`<passed>/<total>`)

| Test | Result |
|---|---|
| `loomwright/scripts/test-run-pin-mutations.sh` | 33/33 (exit 0) |
| `loomwright/scripts/test-phase45-ci-read.sh` | 11/11 (exit 0) |
| `loomwright/scripts/test-phase45-rounds-seam.sh` | 61/61 (exit 0) |
| `scripts/test-ci-local.sh` | 93/93 (exit 0) |
| `loomwright/scripts/test-closed-enum-pins-seam.sh` | 79/79 (exit 0) |
| `loomwright/scripts/test-brief-conformance-seam.sh` | 26/26 (exit 0) |
| `loomwright/scripts/test-deviations-advisory-seam.sh` | 30/30 (exit 0) |
| `loomwright/scripts/test-execution-directive-seam.sh` | 50/50 (exit 0) |
| `loomwright/scripts/test-no-self-matching-wait.sh` | 5/5 (exit 0) |
| `loomwright/scripts/test-dispatch-pr-review.sh` | 52/52 (exit 0) |
| `loomwright/scripts/test-release-refold.sh` | 26/26 (exit 0) |
| `loomwright/scripts/test-citation-drift.sh` | 26/26 (exit 0) |
| `scripts/check-token-budget.sh` | exit 0 — check-token-budget: OK — all agents within their declared prompt-inventory budgets. |
| `scripts/check-doc-currency.sh` | exit 0 — ✓ doc-currency: all checked version/count claims match the authoritative source. |
| `scripts/check-version-bump.sh` | exit 0 — bump-version: check OK — not bumped (version 17.1.0, the merge base's); 1 fragment(s) pending — legal, the next bump folds them (base or |
| `scripts/check-test-hermetic.sh` | exit 0 — check-test-hermetic: OK — 167/167 covered tests source hermetic-test-env.sh as their first executable line |
| `scripts/check-locale-prefix.sh` | exit 0 — check-locale-prefix: OK — 341/341 scanned shell files (git mode) carry no temporary locale assignment at command position |

## 2. Mutation controls (red output)

Each ran on a TEMP copy (`mktemp -d` under the session scratchpad); the checkout was not edited.

**(a) `run-pin-mutations.sh` with the "must fail mutated" run skipped** — the mutated-run line
`run_pin "$pin" "$SCRATCH/logs/mutated.$idx.log"` replaced by `RUN_RC=1; RUN_TIMED_OUT=0` (the mutant is
treated as red without running), then `bash test-run-pin-mutations.sh` from the temp copy. The `not_held`
leg (N) goes red, with the held / precedence / cache legs:

```
FAIL (H) rc=0 execs=1 out=pin-mutation 1: held — a/test-lib.sh :: flip `echo 42` → `echo 43` in `a/lib.sh` ⇒ leg red
FAIL (N) rc=0 out=pin-mutation 1: held — a/test-weak.sh :: flip `echo 42` -> `echo 41` in `a/lib.sh`
FAIL (N) MUTATION CONTROL: mutant not built (anchor_found=0)
FAIL (P) rc=2 out=pin-mutation 1: held — a/test-weak.sh :: flip `echo 42` -> `echo 41` in `a/lib.sh`
FAIL (C) rc=2 execs=0 cache=[ee9f7020e797982b442ddf6d401067dff3ec9b28	held	2bb6fe7aeb29d2924e4dc17f3d1a60bf14afb773	d4a0fd78ea1c193b3db51f779bb801b5a847e497
FAIL (CI) rc=0 execs=1 out=pin-mutation 1: held — a/test-lib.sh :: flip `echo 42` → `echo 43` in `a/lib.sh` ⇒ leg red
test-run-pin-mutations: 20 passed, 6 failed
```

**(b) `ci-local.sh` with `scripts/check-locale-prefix.sh` excluded from the early-set derivation** — a
`check-locale-prefix.sh) plan_phase+=(pool) ;;` arm inserted before `*) plan_phase+=(early) ;;`, then
`bash scripts/test-ci-local.sh` from a temp tree holding the mutant, the real `ci.yml` and the runner. The
static-gate drift leg (SD) goes red and names exactly that gate:

```
ok   (L) dead holder: slot taken over, run passed, slot released
ok   (J) an explicit SELF_TEST_JOBS is passed through unchanged
FAIL (SD) rc=0 gaps=[scripts/check-locale-prefix.sh ] ran=[] out=ci-local --affected: the changed set is empty (against the merge-base with origin/main (da61dcf)) — the early set only
test-ci-local: 92 passed, 1 failed
```

**(c) `run-pin-mutations.sh` without its git-env `unset` line** (review iteration 1) — the
`unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE …` line dropped, then `bash test-run-pin-mutations.sh` from a
temp copy. With `GIT_DIR` / `GIT_INDEX_FILE` exported at the checkout, the scratch copy's
init/add/commit reach the caller's repo, and leg (G) goes red (its in-file control cannot find the
already-removed line, hence the second line):

```
FAIL (G) same=n rc=0 out=pin-mutation 1: held — a/test-lib.sh :: flip `echo 42` → `echo 43` in `a/lib.sh` ⇒ leg red
FAIL (G) MUTATION CONTROL: mutant not built (anchor_found=0)
test-run-pin-mutations: 26 passed, 2 failed
```

**(d) `phase45-ci-read.sh` with the pre-fix `,` split of `red_names`** (review iteration 1) — the matrix
leg (MX) goes red: `test (ubuntu-latest, 20)@123` became two findings,
`checks=[ 20)@123|ci@111|test (ubuntu-latest@-|]` (`test-phase45-ci-read: 10 passed, 1 failed`).

**(e) the pre-fix `run-pin-mutations.sh` (cache written once, after the last row; no `--budget`)** (review
iteration 2) — `git show HEAD~:loomwright/scripts/run-pin-mutations.sh` beside the new test in a temp dir.
The kill leg (K) goes red (TERM while row 2's pin sleeps leaves no cache at all, so the next run re-runs
row 1), and the budget leg (B) is refused as an unknown option:

```
FAIL (K) rc=143 waited=300 cache=[] dir=[] out=pin-mutation 1: held — a/test-lib.sh :: flip `echo 42` → `echo 43` in `a/lib.sh` ⇒ leg red
FAIL (K) rerun: rc=2 cache=[ee9f7020…	held	…] out=pin-mutation 1: held — a/test-lib.sh …
FAIL (B) rc=2 took=0s execs=0 out=pin-mutations: unverified (usage: unknown option --budget)
test-run-pin-mutations: 29 passed, 3 failed
```

**(f) the pre-fix `run-pin-mutations.sh` cleanup (TERM kills only the pin's own pid)** (review iteration 3)
— the iteration-2 script beside the new test. The new orphan assertion in leg (K) goes red: the slow pin's
`sleep`, counted by its recorded pid, outlives the TERMed run (reparented to PID 1):

```
FAIL (K) orphan: recorded=[3693] still alive=[ 3693]
```

## 3. Running-system validation

### 3a. `run-pin-mutations.sh` on PR #533's brief

`bash loomwright/scripts/run-pin-mutations.sh .supervisor/jobs/done/2026-10-13-verified-rule-checks.md --root .`
— its 16 rows are prose, so every row is `unverified (not_machine_applicable)` and falls to the reviewer's D1
fallback (no pin ran):

```
pin-mutation 1: unverified (not_machine_applicable) — loomwright/scripts/test-prove-rule-check.sh :: replace the counterexample leg's check run with a no-op that reports exit 1 (requirement Validation 2) ⇒ the VACUOUS test must go red
pin-mutation 2: unverified (not_machine_applicable) — loomwright/scripts/test-prove-rule-check.sh :: delete the confirmation guard so the check runs without `--confirm` ⇒ canary created, test red
pin-mutation 3: unverified (not_machine_applicable) — loomwright/scripts/test-prove-rule-check.sh :: delete the scratch `git worktree remove` line ⇒ leak test red
pin-mutation 4: unverified (not_machine_applicable) — loomwright/scripts/test-add-rule.sh :: delete the proof-required check in `add-rule.sh` ⇒ refusal test red
pin-mutation 5: unverified (not_machine_applicable) — loomwright/scripts/test-add-rule.sh :: drop the `check_sha256` comparison in `add-rule.sh` ⇒ mismatched-proof test red
pin-mutation 6: unverified (not_machine_applicable) — loomwright/scripts/test-harvest-conventions.sh :: delete `--proof \"\$PROOF\"` from `ADD_RULE_CMD_WITH_CHECK` ⇒ `(cc2c)` red
pin-mutation 7: unverified (not_machine_applicable) — loomwright/scripts/test-prove-rule-check.sh :: make leg 1's result always 0 ⇒ FAILS_NOW test red; run leg 2 unconditionally ⇒ the "leg 2 not run" assertion (scratch never created / counterexample exit absent) red
pin-mutation 8: unverified (not_machine_applicable) — loomwright/scripts/test-prove-rule-check.sh :: ignore the `git apply` exit status ⇒ test red
pin-mutation 9: unverified (not_machine_applicable) — loomwright/scripts/test-prove-rule-check.sh :: ignore the `git worktree add` exit status ⇒ test red
pin-mutation 10: unverified (not_machine_applicable) — loomwright/scripts/test-prove-rule-check.sh :: delete the watchdog kill ⇒ the run hangs past the test's own bound / verdict wrong ⇒ test red
pin-mutation 11: unverified (not_machine_applicable) — loomwright/scripts/test-prove-rule-check.sh :: delete the verify-gone step ⇒ verdict reads PROVEN ⇒ test red
pin-mutation 12: unverified (not_machine_applicable) — loomwright/scripts/test-prove-rule-check.sh :: add a write to `$HOME/.claude/loomwright/rules-check-stamp.json` in the prover ⇒ test red
pin-mutation 13: unverified (not_machine_applicable) — loomwright/scripts/test-add-rule.sh :: delete the `verdict == PROVEN` comparison in `add-rule.sh` ⇒ VACUOUS-proof test red
pin-mutation 14: unverified (not_machine_applicable) — loomwright/scripts/test-add-rule.sh :: treat an unreadable proof as absent-OK ⇒ test red
pin-mutation 15: unverified (not_machine_applicable) — loomwright/scripts/test-add-rule.sh :: drop the proof-set clause from the R1 guard ⇒ test red
pin-mutation 16: unverified (not_machine_applicable) — loomwright/scripts/test-harvest-conventions.sh :: drop `--proof \"\$PROOF\"` from `ADD_RULE_CMD_WITH_CHECK` ⇒ the documented delivery is refused by `add-rule.sh` ⇒ `(u2b)` red
pin-mutations: 0 held, 0 not_held, 16 unverified (0 cached)
rc=2 wall=0s
```

### 3b. The same 16 rows in the two-form grammar, against the current tree

Fixture brief (outside the repo, under a `mktemp -d`):

```markdown
# PR #533 pin rows, transcribed into the two-form grammar (automate-speed/02 Validation 3b)

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-prove-rule-check.sh` — VACUOUS case | flip `CE_EXIT="$RUN_RC"` → `CE_EXIT=1` in `loomwright/scripts/prove-rule-check.sh` |
| `test-prove-rule-check.sh` — needs-confirmation canary | flip `[ "$proceed" -eq 1 ] \|\| unprovable needs_confirmation` → `true \|\| unprovable needs_confirmation` in `loomwright/scripts/prove-rule-check.sh` |
| `test-prove-rule-check.sh` — no-leak | delete `git -C "$TOP" worktree remove --force "$WT"` in `loomwright/scripts/prove-rule-check.sh` |
| `test-add-rule.sh` — must+check without `--proof` refused | flip `[ "$proof_set" -eq 1 ] \|\| die "rejected: --enforcement must` → `true \|\| die "rejected: --enforcement must` in `loomwright/scripts/add-rule.sh` |
| `test-add-rule.sh` — proof for a different check refused | flip `[ "$proof_check_sha" = "$live_check_sha" ]` → `true` in `loomwright/scripts/add-rule.sh` |
| `test-harvest-conventions.sh` `(cc2c)` | flip `--check \"\$CANDIDATE\" --proof \"\$PROOF\"` → `--check \"\$CANDIDATE\"` in `loomwright/scripts/harvest-conventions.sh` |
| `test-prove-rule-check.sh` — FAILS_NOW | flip `NOW_EXIT="$RUN_RC"` → `NOW_EXIT=0` in `loomwright/scripts/prove-rule-check.sh` |
| `test-prove-rule-check.sh` — patch_does_not_apply | flip `if ! git -C "$WT" apply "$PATCH_ABS" >"$SCRATCH_LOGS/apply.log" 2>&1; then` → `git -C "$WT" apply "$PATCH_ABS" >"$SCRATCH_LOGS/apply.log" 2>&1; if false; then` in `loomwright/scripts/prove-rule-check.sh` |
| `test-prove-rule-check.sh` — worktree add fails | flip `if ! git -C "$TOP" -c core.hooksPath=/dev/null worktree add --detach "$WT" "$HEAD_SHA" >"$SCRATCH_LOGS/wt-add.log" 2>&1; then` → `git -C "$TOP" -c core.hooksPath=/dev/null worktree add --detach "$WT" "$HEAD_SHA" >"$SCRATCH_LOGS/wt-add.log" 2>&1; if false; then` in `loomwright/scripts/prove-rule-check.sh` |
| `test-prove-rule-check.sh` — timeout | delete `kill_tree "$pid"   # the watchdog kill` in `loomwright/scripts/prove-rule-check.sh` |
| `test-prove-rule-check.sh` — scratch_leak | flip `if ! scratch_gone; then` → `if false; then` in `loomwright/scripts/prove-rule-check.sh` |
| `test-prove-rule-check.sh` — stamp file untouched | flip `  FINISHED=1` → `  FINISHED=1; mkdir -p "$HOME/.claude/loomwright"; : > "$HOME/.claude/loomwright/rules-check-stamp.json"` in `loomwright/scripts/prove-rule-check.sh` |
| `test-add-rule.sh` — non-PROVEN proof refused | flip `[ "$proof_verdict" = "PROVEN" ]` → `true` in `loomwright/scripts/add-rule.sh` |
| `test-add-rule.sh` — missing / non-JSON proof refused | flip `[ -n "$proof_file" ] && [ -f "$proof_file" ] && [ -r "$proof_file" ]` → `true` in `loomwright/scripts/add-rule.sh` |
| `test-add-rule.sh` — `--proof` with `--retract` refused | flip `\|\| [ "$applies_to_set" -eq 1 ] \|\| [ "$proof_set" -eq 1 ]; then` → `\|\| [ "$applies_to_set" -eq 1 ]; then` in `loomwright/scripts/add-rule.sh` |
| `test-harvest-conventions.sh` `(u2a)`–`(u2e)` | flip `--check \"\$CANDIDATE\" --proof \"\$PROOF\"` → `--check \"\$CANDIDATE\" ` in `loomwright/scripts/harvest-conventions.sh` |
```

Transcription notes: row 7 keeps only its first mutation ("leg 1's result always 0"; the second, "run leg 2
unconditionally", is a separate mutation); row 12's "add a write" is expressed as a `flip` that appends the
write to the existing `  FINISHED=1` line; rows 6 and 16 apply the same mutation for two different pins.

`bash loomwright/scripts/run-pin-mutations.sh <fixture> --root .`:

```
pin-mutation 1: held — loomwright/scripts/test-prove-rule-check.sh :: flip `CE_EXIT="$RUN_RC"` → `CE_EXIT=1` in `loomwright/scripts/prove-rule-check.sh`
pin-mutation 2: held — loomwright/scripts/test-prove-rule-check.sh :: flip `[ "$proceed" -eq 1 ] \|\| unprovable needs_confirmation` → `true \|\| unprovable needs_confirmation` in `loomwright/scripts/prove-rule-check.sh`
pin-mutation 3: unverified (invalid_mutant: bash -n) — loomwright/scripts/test-prove-rule-check.sh :: delete `git -C "$TOP" worktree remove --force "$WT"` in `loomwright/scripts/prove-rule-check.sh`
pin-mutation 4: held — loomwright/scripts/test-add-rule.sh :: flip `[ "$proof_set" -eq 1 ] \|\| die "rejected: --enforcement must` → `true \|\| die "rejected: --enforcement must` in `loomwright/scripts/add-rule.sh`
pin-mutation 5: held — loomwright/scripts/test-add-rule.sh :: flip `[ "$proof_check_sha" = "$live_check_sha" ]` → `true` in `loomwright/scripts/add-rule.sh`
pin-mutation 6: held — loomwright/scripts/test-harvest-conventions.sh :: flip `--check \"\$CANDIDATE\" --proof \"\$PROOF\"` → `--check \"\$CANDIDATE\"` in `loomwright/scripts/harvest-conventions.sh`
pin-mutation 7: held — loomwright/scripts/test-prove-rule-check.sh :: flip `NOW_EXIT="$RUN_RC"` → `NOW_EXIT=0` in `loomwright/scripts/prove-rule-check.sh`
pin-mutation 8: held — loomwright/scripts/test-prove-rule-check.sh :: flip `if ! git -C "$WT" apply "$PATCH_ABS" >"$SCRATCH_LOGS/apply.log" 2>&1; then` → `git -C "$WT" apply "$PATCH_ABS" >"$SCRATCH_LOGS/apply.log" 2>&1; if false; then` in `loomwright/scripts/prove-rule-check.sh`
pin-mutation 9: not_held — loomwright/scripts/test-prove-rule-check.sh :: flip `if ! git -C "$TOP" -c core.hooksPath=/dev/null worktree add --detach "$WT" "$HEAD_SHA" >"$SCRATCH_LOGS/wt-add.log" 2>&1; then` → `git -C "$TOP" -c core.hooksPath=/dev/null worktree add --detach "$WT" "$HEAD_SHA" >"$SCRATCH_LOGS/wt-add.log" 2>&1; if false; then` in `loomwright/scripts/prove-rule-check.sh`
pin-mutation 10: held — loomwright/scripts/test-prove-rule-check.sh :: delete `kill_tree "$pid"   # the watchdog kill` in `loomwright/scripts/prove-rule-check.sh`
pin-mutation 11: held — loomwright/scripts/test-prove-rule-check.sh :: flip `if ! scratch_gone; then` → `if false; then` in `loomwright/scripts/prove-rule-check.sh`
pin-mutation 12: held — loomwright/scripts/test-prove-rule-check.sh :: flip `  FINISHED=1` → `  FINISHED=1; mkdir -p "$HOME/.claude/loomwright"; : > "$HOME/.claude/loomwright/rules-check-stamp.json"` in `loomwright/scripts/prove-rule-check.sh`
pin-mutation 13: held — loomwright/scripts/test-add-rule.sh :: flip `[ "$proof_verdict" = "PROVEN" ]` → `true` in `loomwright/scripts/add-rule.sh`
pin-mutation 14: held — loomwright/scripts/test-add-rule.sh :: flip `[ -n "$proof_file" ] && [ -f "$proof_file" ] && [ -r "$proof_file" ]` → `true` in `loomwright/scripts/add-rule.sh`
pin-mutation 15: held — loomwright/scripts/test-add-rule.sh :: flip `\|\| [ "$applies_to_set" -eq 1 ] \|\| [ "$proof_set" -eq 1 ]; then` → `\|\| [ "$applies_to_set" -eq 1 ]; then` in `loomwright/scripts/add-rule.sh`
pin-mutation 16: held — loomwright/scripts/test-harvest-conventions.sh :: flip `--check \"\$CANDIDATE\" --proof \"\$PROOF\"` → `--check \"\$CANDIDATE\" ` in `loomwright/scripts/harvest-conventions.sh`
pin-mutations: 14 held, 1 not_held, 1 unverified (0 cached)
rc=1 wall=634s
```

Reading the two non-`held` rows:

- **Row 3 `unverified (invalid_mutant: bash -n)`** — deleting the only line of `cleanup_scratch`'s
  `if … then` body leaves an empty block, so the mutant fails `bash -n` and is never run (AC 2: an invalid
  mutant is never `held`). A `flip` of that line to `:` would express the row; this is a grammar limit of the
  transcription, not a pin verdict.
- **Row 9 `not_held`** — with the `git worktree add` exit status ignored, `test-prove-rule-check.sh` stays
  green: the script's separate `WT_RECORDED` guard (`the scratch worktree is not in git's worktree list`)
  still refuses the run with the same `worktree_add_failed` reason, so the pin does not distinguish the
  exit-status check from the record check. PR #533's row claimed "test red"; mechanically it is not. This is
  exactly the finding the Phase 4.5 reviewer would now receive as a BLOCKING `not_held` line, without
  running the mutation itself.

Wall-clock: 634 s for 16 rows (3 distinct pins, each run once unmutated + once per row). A second run with
`--cache` and no file change re-runs nothing (test leg C).

### 3c. `phase45-ci-read.sh` against PR #533 at `b62b67d`

`bash loomwright/scripts/phase45-ci-read.sh https://github.com/vikashruhilgit/loomwright/pull/533 --sha b62b67d019a10922dcd58af16d8b542957d17110`

PR #533 is merged and its head moved to `698c56a`, so the `wait-for-checks.sh` line reads
`pending_names=sha_mismatch`; the script then reads that commit's check-runs filtered to the required
context (`ci`, from `drain-gh-read.sh required-checks`) — the read the brief allowed for a past `--sha`.
Exit 0, one finding (the real red `ci` from `check-locale-prefix.sh`). The log tail is the failing step's
40 lines ending at the first `##[error]Process completed` marker; the run's last 40 lines would have been the
aggregating `ci` job's post-job cleanup (credential removal, "Cleaning up orphan processes"):

```
{"severity":"BLOCKING","category":"new","file":"ci","check":"ci","run_id":"38430571809","description":"required check ci failed on b62b67d019a10922dcd58af16d8b542957d17110","log_tail":"<<<EXTERNAL_TEXT channel=ci-log actor=unknown trusted=no>>>\nstatic:   ok: 2.11 red: if ! LC_ALL=C tr -d '\\000' < f | cmp -s - f; then :; fi\nstatic:   ok: 2.12 red: if true; then LC_ALL=C sort f; fi\nstatic:   ok: 2.13 red: for i in 1; do LC_ALL=C sort f; done\nstatic:   ok: 2.14 red: { LC_ALL=C sort f; }\nstatic:   ok: 2.15 red:     LC_ALL=C sort f\nstatic:   ok: 2.16 red: LANG=C grep -c x f\nstatic:   ok: 2.17 red: LC_COLLATE=C sort f\nstatic:   ok: 2.18 red: LC_ALL=\"$CORPUS_LOCALE\" bash t.sh\nstatic:   ok: 2.19 red: LC_ALL=C LANG=C sort f\nstatic:   ok: 2.20 red: diff <(LC_ALL=C sort a) b\nstatic: == 3. nested dirs and *.bash are scanned ==\nstatic:   ok: 3. an offender in a nested .bash file is named\nstatic: == 4. .git/ and node_modules/ are pruned ==\nstatic:   ok: 4. pruned dirs are not scanned\nstatic: == 5. zero files => red ==\nstatic:   ok: 5. an empty tree fails closed\nstatic: == 6. mutation control: the real gitignore_gate line with its env dropped => red ==\nstatic:   ok: 6. reverting gitignore_gate's env prefix turns the gate red\nstatic: == 7. argument errors fail closed, each with its own message ==\nstatic:   ok: 7a. --root with no value is red\nstatic:   ok: 7b. an unknown argument is red\nstatic:   ok: 7c. a non-directory --root is red\nstatic: == 8. the fix hint separates external commands from builtins/functions ==\nstatic:   ok: 8. a flagged builtin gets the export remedy, not only env\nstatic: == 9. the real tree is green ==\nstatic:   FAIL: 9. real tree rc=1: check-locale-prefix: OFFENDER loomwright/scripts/test-prove-rule-check.sh:100: home_print() { ( cd \"$HOME\" && find . -type f -exec cksum {} \\; | LC_ALL=C sort ); }\nstatic: check-locale-prefix: FAIL — 1 temporary locale assignment(s) at command position in 334 scanned shell files.\nstatic:   Fix: an external command -> prefix it with env (`env LC_ALL=C sort`).\nstatic:        a builtin or shell function (read, printf, eval, a function) -> NOT env (it can only exec a binary);\nstatic:        `export LC_ALL=C` once at script scope, or as the subshell's first statement.\nstatic:   Why: Homebrew bash 5.3 segfaults restoring the locale in a forked subshell (see this script's header).\nstatic: == 10. git mode: .gitignore'd files are not scanned, tracked + untracked-unignored are ==\nstatic:   ok: 10a. an offender under a .gitignore'd path is not scanned (git mode, 1/1)\nstatic:   ok: 10b. control: the same line in a tracked file is named (and only it)\nstatic:   ok: 10c. control: an untracked-but-not-ignored file is named before it is staged\nstatic:   ok: 10d. an index entry deleted from disk is skipped, not an error\nstatic:   ok: 10e. a root below the work-tree top level walks (no inherited ignore rules scanning nothing)\nstatic: \nstatic: test-check-locale-prefix: 34 passed, 1 failed\nstatic: ##[error]Process completed with exit code 1.\n\n<<<END_EXTERNAL_TEXT>>>"}
```
