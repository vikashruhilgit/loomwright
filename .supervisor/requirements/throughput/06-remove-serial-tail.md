# 06 — Remove the serial tail: make the three `serial` tests pool-safe, so a full run fits under 540 s

## Status: parked — superseded by `.supervisor/requirements/implementation-quality/02-iq01-and-throughput-merged.md` (owner decision 2026-10-09: implementation-quality/01 + throughput/01–09 merged into ONE item / ONE PR; this file is kept as that file's Part source)

## Depends on
none

## Touches
loomwright/scripts/test-ci-slot.sh
loomwright/scripts/test-build-floor.sh
loomwright/scripts/test-harvest-conventions.sh
loomwright/scripts/run-self-tests.sh
loomwright/scripts/test-run-self-tests.sh
loomwright/scripts/test-automate-trail.sh
loomwright/scripts/test-automate-trail-closeout.sh
loomwright/scripts/test-automate-trail-merge-watch.sh
.github/workflows/ci.yml
changelog.d/throughput-06-remove-serial-tail.md

## Problem
`loomwright/scripts/run-self-tests.sh` runs every test that carries the exact line `# run-self-tests: serial` ALONE, one at a time, after the concurrent batch. Its header `marker:` paragraph and the block above `par_idx=(); ser_idx=()` describe this: "for tests that measure wall-clock time and need an idle machine". The same script is the GitHub CI suite step, so the tail is paid locally and on every push.

**Measured (ci-slot run logs, 2026-10-08; every PR #435 log reads `152 concurrently (6 at a time), then 3 serially`):** three tests are marked, and their serial run adds a fixed tail to every full run:

| Test | Time (4 passing logs) | Reason the file gives for `serial` |
|---|---|---|
| `test-ci-slot.sh` | 111–113 s | **none.** The marker sits alone below the arms list, with no explanation. It has been there since the file was created (commit f0b6f01, 2026-10-04). |
| `test-build-floor.sh` | 38–39 s | Line-3 note: "case (x) is a calibrated wall-clock runtime ratio; under a loaded concurrent run it measured 183-222 units against its 180 bound" |
| `test-harvest-conventions.sh` | 27–29 s | Line-3 note: "(M1) feeds 'y' to a PTY after a fixed `sleep 1`; under load the writer has not reached its prompt yet and the control reads as vacuous" |

That is ≈181 s of serial tail per full run. The concurrent batch is ≈470 s of ideal work (≈2808 test-seconds / 6 jobs) against ≈650 s wall. The full run therefore does not fit the 600 s an agent's Bash call may block (`AGENT_GUIDELINES.md` §"Pre-push: one command": "A full run takes about 10 minutes, longer than one agent tool call may block (600 s)"). That is why PR #438 had to add `ci-local.sh --wait`.

The single-test floor is `test-automate-trail.sh` at 386–398 s, the slowest test in every log. It is 2473 lines with 38 `echo "== X. … =="` sections: sidecar-check, dispatcher, trail-pr, closeout ×10, evidence-gated stamps, retract, dismissed drafts, `== W. merge watcher ==` and `== WE. escalated park … ==` (AC13 / M2 / E7 / repark, about 450 lines), branch mode, finalize, closeout-classify, closeout-others and lane-clone. Even with no serial tail, the pool cannot finish sooner than its longest test.

What the brief got partly wrong, and the reshaped goal: **test-ci-slot.sh does not read the real machine.** Its setup block sandboxes `XDG_STATE_HOME`, `LOOMWRIGHT_MACHINE_STATE_DIR` and `LOOMWRIGHT_MACHINE_LOAD_CMD` (a fixture `load.sh`), and `LOOMWRIGHT_CI_CPUS` is set per arm. So "it measures admission under real load" is not why it is serial. The likely reason is wall-clock margins: elapsed-time bounds (`t0=$(date +%s)` … `el` checks such as `[ "$el" -gt 3 ]`), `--wait 1` timeouts, `sleep 1.2` "at least one more progress period", and the G10/G13 5 s reader wait against a 6 s `slow` fixture reader (a 1 s margin). This is a hypothesis. This item measures it rather than assumes it.

`run-self-tests.sh` already records the preferred repair. Its comment cites `test-write-agent-memory.sh` (j5/X): "marked too and STILL flaked under outside load, then was made deterministic (barriers instead of sleeps) and unmarked — prefer that repair whenever the ordering can be pinned".

## Goal
No test needs the serial tail, or the tail that is left is ≤ 30 s with a written, measured reason per remaining marker. A full `bash scripts/ci-local.sh` on this machine finishes in ≤ 540 s wall, which fits one foreground agent Bash call (600 s) with margin. GitHub CI's suite step loses the same tail.

## Scope
1. **Measure first, per test.**
   - Run each marked test 10× inside a loaded concurrent pool: with the marker removed, alongside the heaviest tests (e.g. `run-self-tests.sh` over the test plus `test-automate-trail.sh`, `test-meta-sync.sh`, `test-setup-ui.sh` at 6 jobs).
   - Record which arms fail and by how much.
   - For `test-ci-slot.sh`, find out which arms actually need an idle machine. The file states no reason, so this measurement is the evidence.
2. **Repair, preferring determinism over isolation:**
   - **`test-ci-slot.sh`:** replace elapsed-wall-clock assertions with event-driven ones where the property is ordering, not duration. Examples: wait on `status --json` reaching a state, or on a file appearing, with a bounded deadline, instead of asserting `el -le N`. Where a duration IS the property (a bounded `--wait N`, the G13 "bounded by the clock" arm), widen the margin so it is relative to the fixture's own timing (e.g. the fixture reader sleeps a multiple of the bound), never an absolute number tuned to an idle laptop. Keep every MUTATION CONTROL red against its mutant.
   - **`test-build-floor.sh` (x):** the ratio is calibrated in the same run, but the unit (one `jq` scan) and the projector are measured at different moments, so load that varies between them moves the ratio. Candidate repairs, chosen by measurement:
     - measure child **CPU** time (user+sys via `getrusage(RUSAGE_CHILDREN)` in the existing python3 measurement) instead of wall time;
     - interleave several unit/projector samples and take the minimum of each.

     Keep the bound's property: the consolidated readers must sit well below and the pre-consolidation code well above. Re-run the historical arm (`PERF_PRE_SHA`) where git history allows and record both ranges. The file's comment block rejects counting `jq` invocations (37 vs 35): do not reintroduce it.
   - **`test-harvest-conventions.sh` (M1):** replace the fixed `sleep 1` before feeding `y` with a wait for the prompt. Poll the PTY transcript for the prompt text with a bounded deadline, then feed. A deadline miss is a FAIL naming the missing prompt, never a vacuous pass. (M1a)'s "CONFIRMED the hazard is real" control must still go red on its mutant.
3. **Unmark only what is proven safe.** Remove `# run-self-tests: serial` from each repaired test, then run it 10× in the loaded pool with zero failures. Any test that still genuinely needs an idle machine keeps the marker. Its marker line then gets a one-line reason (as build-floor and harvest-conventions have today) and the measured failure rate under load. If two or more stay marked and they do not interfere with each other, they may run as a small concurrent batch instead of one at a time. Measure that too, and change the `schedule 1` call in the runner only if it helps.
4. **Split `test-automate-trail.sh` only if the sections are independent and it pays.**
   - Check what the sections share: the `stub gh` block, `$P`/`$TOP` fixtures, spy logs, and state set by earlier sections.
   - If clusters can be separated, split along the natural seams into independent files, each sourcing `hermetic-test-env.sh` first (`scripts/check-test-hermetic.sh`). Proposed seams: closeout (the `== C. … ==` / `== CL. … ==` / `== CO. … ==` sections) and the merge-watch block (`== W. ==` + `== WE. ==`: AC13 single-instance, M2 replace, (E7) AC9 double-arm, repark). The rest stays.
   - The two new file names in Touches, `loomwright/scripts/test-automate-trail-closeout.sh` and `loomwright/scripts/test-automate-trail-merge-watch.sh`, are **NEW** (neither exists today) and are proposals. If the measurement picks other seams, update `## Touches` before starting. If the split does not lower the pool's critical path by ≥ 60 s, do not split, and record the measurement in the PR body.
   - Shared setup moves into a sourced helper only if it already exists as a function. Do not invent a framework.
5. **Docs in the same change.**
   - `run-self-tests.sh`'s header `marker:` paragraph and the comment above `par_idx`: state which tests (if any) remain serial and why. The "Observed flaking … test-build-floor.sh (x), test-harvest-conventions.sh (M1a)" sentence must stay true.
   - `.github/workflows/ci.yml`'s `timeout-minutes` comment ("one hang in the concurrent batch, one in the serial phase after it", "A green run takes ~8 min"): update it to the measured reality.
   - `test-run-self-tests.sh` arm (S) keeps testing the marker mechanism, which stays even if no committed test uses it.
6. **Sequencing.** `automate-followups/34`, `automate-followups/36` and item 07 all touch `loomwright/scripts/test-automate-trail.sh`. The shared Touches line keeps them in different waves. If 07 lands first, the split carries its fixes. Item 08 depends on this item.

## Acceptance criteria
- Each remaining `# run-self-tests: serial` marker carries a written reason and a measured failure rate under the loaded pool. Each removed marker has 10/10 green runs in a loaded pool recorded in the PR body.
- Serial tail (the sum of the serial phase) ≤ 30 s, read from the `slowest tests` timings of a real full run.
- A full `bash scripts/ci-local.sh --force` on this machine finishes in ≤ 540 s wall. Measure before and after on the same machine with the same `SELF_TEST_JOBS` and an otherwise idle slot pool, and put both log paths in the PR body.
- Every mutation control in the touched tests still goes red on its mutant (the G13 iteration-bounded mutant, build-floor's historical arm where reachable, (M1a)).
- If `test-automate-trail.sh` is split: the union of the new files' assertions equals the original. The PR body carries the `passed:` counts before and after, and `test-suite-helpers-defined.sh` stays green. The new longest test is recorded.
- The `run-self-tests.sh` header claim about the serial marker matches what the code and the marked files now do.

## Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green; the before/after wall times and log paths in the PR body.
2. The 10× loaded-pool runs per unmarked test (command and result counts in the PR body).
3. GitHub CI on the PR: the suite step's wall time against the 10m12s baseline (run 37809076650, `783b00b`), with the `running … then N serially` line quoted.

## Non-goals
- Raising `SELF_TEST_JOBS` or the slot count. Two concurrent full runs took ~830 s against ~650 s solo (`00-overview.md` §"Considered and NOT queued").
- Sharding CI (item 08) or adding an early phase (item 05).
- Removing the `serial` marker mechanism itself: `test-run-self-tests.sh` (S) covers it, and a future wall-clock test may need it.
- Speeding up a test by deleting assertions. A split moves assertions. It never drops them.
