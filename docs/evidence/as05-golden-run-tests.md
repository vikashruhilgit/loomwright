# Evidence — automate-speed/05: golden run-file tests

Source requirement: `.supervisor/requirements/automate-speed/05-golden-run-tests.md`.
Suite: `loomwright/scripts/test-automate-golden.sh`; fixtures and map: `loomwright/scripts/fixtures/automate-golden/`.
Every output below was produced on this branch, on macOS: `bash` on `PATH` is 5.3, and the suite was also run under
`/bin/bash` 3.2.57 (`/bin/bash loomwright/scripts/test-automate-golden.sh` → `PASS: 62 FAIL: 0`). Repo paths are
shown as `<repo>`.

## What the suite pins

- **Unit map.** Every `##`/`###`/`####` heading and column-0 numbered item of `per-item-loop.md`,
  `modes-and-merge-gate.md` and `resume.md` is extracted live (fenced blocks skipped) and must have a `MAP.tsv`
  row naming a case, or `judgment — covered at the step boundary: <case>`. The map is printed on every run.
- **Golden cases.** Each case copies a run file built from a real `.supervisor/automate/` run into a scratch
  `git init` checkout, runs the helper calls the prose orders for that step (`steps`), and compares the run file
  (`expected.md`) and each step's stdout / stderr / exit code (`expected.out`) byte for byte, ISO timestamps and
  scratch paths normalised. `gh` is a stub on `PATH` driven by the case's `gh.stub`; steps that need git
  (`closeout`, `trail-pr`, `trail-gate`, `trail-unstage`, `sweep`, `gate-eval` conditions 6/7) run for real in the
  scratch checkout, with a bare scratch origin where a sync or push happens (the case's `setup`).
- **Where the loop has no helper**, a step is written `loop: <shell>` (e.g. the `## Status:` line through
  `runfile-write`), so a reader sees exactly which writes are still model-authored (Findings F1, F2).
- **Provenance.** Each case's `source` names its real run id and what was trimmed or reconstructed.
- **Committable fixtures.** A case's `tree/` stores dot-paths as `dot-<name>` (`tree/dot-supervisor/`,
  `tree/lanes/L1/dot-supervisor/`); the harness maps each `dot-<name>` component back to `.<name>` in the scratch
  root. When the fixtures dir in use is in a git work tree, any file under it that `git check-ignore` reports is a
  `FAIL: ignored fixture <path>` (leg M9).

## CI-red root cause (review iteration 1)

Head `b645ef1` had the required check `ci` red. Root cause: the 75 files under 28 cases' `tree/.supervisor/` (and
`tree/lanes/L1/.supervisor/`) matched `.gitignore` `*/**/.supervisor/`, so they were never committed. The suite was
green only in this checkout, where the ignored files exist on disk. Reproduced in a clean clone of `b645ef1`
(`GOLDEN_SKIP_LEGS=1`): `PASS: 19 FAIL: 49`, 27 cases red with `run file differs` / `step output differs`.
Fix: the directories are stored as `dot-supervisor/` (not ignored; `git status --short --ignored
loomwright/scripts/fixtures/automate-golden` prints nothing) and mapped back at copy time. Prevention: the
ignored-fixture guard above fails the suite locally, so an uncommittable fixture can no longer be green only on the
author's disk. The same review added two unit-map guards: a fence closes only on a same-character run at least as
long as the opening one (leg M7), and a repeated unit id is `FAIL: duplicate unit <id>` (leg M8).

Committing those files exposed them to the other repo gates for the first time. `bash scripts/ci-local.sh --affected`
then failed `check-vendor-coupling` on 7 `tree/` requirement/job files carrying harness path, CLI and hook tokens in
prose no helper reads. Those tokens were rewritten (`.app-harness/`, `<harness> -p`, `Subagent-stop`; each affected
case's `source` records it). Every case's run file and step output stayed identical.

## CI-red root cause (review iteration 2)

Head `1db705e` had `ci` red on shard `suite (2)`: `FAIL: gate-validation-waive: step output differs`, the diff a
single added stderr line `! <TMP>/bundle/automate-lanes.sh: line 3039: printf: write error: Broken pipe`. Mechanism:
Finding F9. It passed locally and in a clean clone because a default-disposition macOS shell kills the reader
silently. CI's runner hands the job SIGPIPE ignored, so the write fails loudly.

**Harness rule (the only stderr filter).** In step output only, applied identically to the actual and the expected
`.out` (and to what `GOLDEN_WRITE` writes), a recorded stderr line matching
`^! .*: line [0-9]+: printf: write error: Broken pipe$` is dropped. Every other stderr line is still compared byte
for byte, a missing final newline included. The line is the bash builtin's report of the F9 race and carries no
contract. Guards:

- The scrub phase fails `sigpipe noise pinned in <case>/expected.out` if any committed `expected.out` holds the line.
- Leg M10 (built in), on fixtures copies of `gate-validation-waive` with one line inserted before the waive step's
  `= ` line. **a**: the Broken-pipe line → the case stays green and the scrub names it. **b**: the same line with
  `echo:` for `printf:` → `step output differs`. **c**: `! unexpected stderr` → `step output differs`. **d**: the
  unmutated case run with SIGPIPE inherited as ignored (the CI condition) → green.
- Non-vacuity, by hand: a scratch copy of the harness with the filter replaced by `cat`, run under
  `trap '' PIPE` → `FAIL: gate-validation-waive: step output differs` (the `+! …Broken pipe` line), `PASS: 5 FAIL: 1`.
  The real harness, same condition → `PASS: 6 FAIL: 0`.

**Class sweep.** Each check below was run on the golden cases (`GOLDEN_SKIP_LEGS=1`), and each was green, 48/48:

| Variant | Result |
|---|---|
| SIGPIPE inherited as ignored (`bash -c "trap '' PIPE; exec bash …"`) | 48/48. Before the rule: 5/5 runs red on `gate-validation-waive` only |
| `TZ=Asia/Kolkata` | 48/48 |
| `LC_ALL=C` / `LC_ALL=en_US.UTF-8` | 48/48 each |
| `TMPDIR=<scratch>` | 48/48 |

Static sweep of the helpers the cases call (`automate-{helpers,lanes,trail,dismissed,wave}.sh`, 68 pipes into
`head` / `grep -q|-m` / `awk … exit` / `sed -n …q`). Only a producer that makes several writes can hit EPIPE after
its consumer exits: a bash builtin in a loop, or output larger than one stdio buffer. `automate-lanes.sh`'s
`--waive` branch of `lanes_validation_gate` (`_lanes_validation_rows | awk … exit`) is the only such producer on a path a case runs. The
other `_lanes_validation_rows` callers read it into a file or a command substitution in full. The rest are
single-write producers (`printf '%s\n' "$x"` of a short value, `sed`/`jq` over small files) or are not reached by
any case (`lane-readiness`'s `while … ls -t | head`, `fleet-closeout`, `automate-wave.sh`; the cases' `closeout`
is `automate-trail.sh`'s). Other nondeterminism the harness could pin:

- pids and `.tmp.$$` names, epoch seconds (`date +%s`), `mktemp` suffixes: none appear in any `expected.out` /
  `expected.md`. A pid or a second-resolution value would also differ between the five back-to-back runs below,
  which all match.
- ISO `…Z` timestamps: normalised to `<TS>`.
- `date +%z` (lanes.sh): not reached by a case, and the `TZ` variant is green.
- Listing order: the `ls` steps (`brief-repair-merged`, `resume-config-crash-restore`, `run-config-suppress-restore`)
  and `resume-glob`'s glob list names whose order is the same under C and UTF-8 collation (both locale variants are
  green). `learning-emit-end-of-drain` already sorts with `env LC_ALL=C sort`. The harness's own `find` output
  is either sorted (`check_ignored`) or order-free (`stage_tree` renames).

So no second fix was needed. Limit: the sweep ran on macOS (BSD userland). GNU tools on Linux also report EPIPE
when SIGPIPE is ignored (`sed: couldn't write …`, `grep: write error`). Those are external-tool messages, not the
builtin's, so the rule does NOT drop them. The static sweep found no multi-write external producer on a case path.

Verification of this fix: five back-to-back full runs → 5/5 `PASS: 62 FAIL: 0` (validation 1); a clean clone of
the fix commit → `PASS: 62 FAIL: 0`; `bash scripts/ci-local.sh --affected` → `all 17 self-tests passed`,
`ci-local --affected: PASS after 50s`, `test-automate-golden.sh` `PASS 48s` (run before this paragraph was
written; the harness and fixtures are as committed).

## Findings (behaviour not changed)

Cases pin TODAY's output. Where today's output, a real run, or the absence of a helper disagrees with what the
prose says, the case still pins today's output and the disagreement is listed here. Nothing was fixed.

**Prose vs. today's output / real runs**

- **F3 — `sidecar-check: ok` lines.** §6 steps 2–3 say only a `fail …` line is `progress-append`ed. Real run
  `automate-2026-10-13-181331` appended `sidecar-check: ok …` lines for every sidecar. Cases `run-record-pr` and
  `drain-owned-drain-started` follow the prose (no `ok` line). A `next-step` script must choose one.
- **F4 — validation-gate `--check` value is ambiguous.** §6 step 4 says the `--check` value is the `V<n> <title>`
  text between `unrun — ` and "the `: ` that opens the evidence". Today's step titles themselves contain `: ` and are
  truncated (`V2 Running system: one real \`--parallel 1\` run of a trivial ite: listed under …`, and the real waiver
  line `V3 Running system: one real \`/automate --backlog\` run in this r`). The opening `: ` cannot be located
  mechanically. Case `gate-validation-gate-unrun-escalated` pins the first-`: ` cut (`V2 Running system`).
- **F5 — rate-limit park vs. a PR that already exists.** The only real main-scope `rate_limit` row
  (`automate-2026-10-12-181635-L1`, 15:21Z, after `picked`) occurred mid-RUN, and RUN still produced PR #502. That run
  correctly did not park, but the prose's "Rate-limit park" has no branch for "rate-limit row, yet a PR exists": read
  literally it parks with `pr: null` and re-runs RUN, duplicating the PR. Case `rate-limit-park` pins the prose park
  on the no-PR state.
- **F8 — `reconcile-status: would stamp <file> (<status>)`.** §4 step 7 does not say how `<status>` comes from the
  `plan` row's third column, which carries the full status text (`done (PR #109, merge 19cd52b)`). The real lane run
  `automate-2026-10-08-033739-L2` wrote the bare status (`(done)`, `(done_with_escalation — ABANDONED)`). Case
  `resume-reconcile-status` pins the bare form (`${st%% (*}`).

**Writes the prose orders but no helper performs (model-authored today)**

- **F1 — `## Status:`.** No helper writes `## Status: paused|running|done` (only `finalize-empty` writes `done`).
  Every park, resume and termination case writes it with `loop: sed … | runfile-write`.
- **F2 — `## Current` side lines.** No helper writes `- owned_drain_started: … | owned_drain_result: … |
  suppressed_default_dispatch: …` or `- pending_decisions: … | fix_now_reentered: …`. Cases write them through
  `runfile-write` (`drain-owned-drain-started`, `drain-superseded-by-merge`, `park-first-ready-park`,
  `park-first-decisions-recorded`, `dismissed-fix-now-re-drain`, `dismissed-findings-decision-step`).
- **F6 — line texts the prose does not pin.** No exact text is given for: the `limit_reached` exit's
  `remaining: <n>` (§6 Termination), the CHECK OFF Progress line (§6 step 6), the escalated park's Progress line
  (§9), the `--auto-merge` fail-closed park line, the `closeout leftover: <run_id> <step> <detail>` field values,
  and the `rate-limited — …` line (given only as "e.g."). The cases pin the loop-authored text they use; a
  `next-step` script may pick another and update the case on purpose.
- **F7 — park-first steps 3–5** (arm the merge watcher, notify, `run-lock.sh release`) cannot run hermetically. Case
  `park-first-ready-park` supplies the watcher's marker file as fixed input; notify and release write nothing to the
  run file (MAP.tsv marks L2.3–L2.5 as boundary rows).

**Branches no real run carries (inputs built from the nearest real run, named in each `source`)**

- `drain-superseded-by-merge`: no run holds the pinned `drain superseded_by_merge — …` line. `automate-2026-09-30-054439`
  (#305 merged mid-drain) recorded it in prose, and its later lines say the value was off-enum then.
- Escalated park with `current-escalation` (`escalated-park`, from `automate-2026-08-06-175851`, which predates the
  helper); the `trail_pr_open`, `live_lane`, `token_ceiling`, `closeout_leftover` and `resume_ambiguous` parks; a
  `limit_reached` exit with `current-set`; the `rate_limit` park (F5); a fix-now re-pass with the pinned re-drain
  lines (`automate-2026-10-01-142337` used the legacy wording).
**Helper races (nondeterministic output)**

- **F9 — `validation-gate --waive` can print `printf: write error: Broken pipe` on stderr.** `automate-lanes.sh`
  `lanes_validation_gate`'s waiver branch pipes `_lanes_validation_rows` (the shared Validation reader: one `printf`
  per row inside a `while … read` loop) into an `awk` that `exit`s on the first matching row. When the process
  inherits SIGPIPE as IGNORED, the reader's next `printf` after awk exits gets EPIPE and bash prints
  `<path>/automate-lanes.sh: line <n>: printf: write error: Broken pipe`. With SIGPIPE at its default the reader's
  subshell is killed silently instead. So the line depends on the inherited disposition and on whether awk has
  exited yet. Stdout, the exit code (no `set -e` in that file) and the run file are unchanged. Seen in CI on
  `1db705e` (shard `suite (2)`, case `gate-validation-waive`). Reproduced locally 5/5 by running the suite under
  `bash -c "trap '' PIPE; exec bash …"`. Not fixed here: the requirement forbids helper behaviour changes. A fix
  belongs in the helper (read the rows into a variable before filtering, as `automate-helpers.sh` already does with
  its here-strings). The harness rule below keeps the pin deterministic meanwhile.
  (The brief named the reader `_lanes_validation_reader`; the function is `_lanes_validation_rows`.)

- Observation, not a disagreement: `current-rebuild` appends `current_rebuilt: …` with no leading timestamp (as the
  real `automate-2026-09-30-054439` line shows); the prose does not require one.

## Pin mutations (by hand, on scratch copies — red/green record)

Method: for each row, build the helper bundle exactly as the suite does (`_ah_bundle` beside symlinks to every
`scripts/` entry) in a scratch dir. Mutate ONE character of the anchor, in the bundle (dispatcher and
`automate-helpers.d/` families) or in a COPY of the sibling script (its bundle-dir symlink removed first, so nothing
is written through a link). Gate: the anchor occurs exactly once, the mutant is non-empty, differs and passes
`bash -n`. Then run `GOLDEN_HELPERS=<scratch bundle> GOLDEN_SKIP_LEGS=1 GOLDEN_CASES=<case> bash
loomwright/scripts/test-automate-golden.sh`. Unmutated, every case is green (validation 1). After all rows,
`git diff --quiet -- loomwright/scripts ':!loomwright/scripts/fixtures'` held.

Rows M1–M6 are also built-in legs (M7–M9 are built-in legs for the unit-map fence/duplicate guards and the ignored-fixture guard; M10 for the stderr noise rule) of the suite (validation 1 shows them red on every run). Every helper subcommand
family that appears in any case's `steps` has a row:

| Row | Family (subcommands in `steps`) | Anchor → one-char mutation | Case that must go red | Result |
|---|---|---|---|---|
| M1 | `progress-append` guard | `owned drain started)'` → `owned drain startex)'` (`_progress_current_guard` `re_g`) | drain-pinned-start-line-current-not-set | RED (built-in leg + V2) |
| M2 | `current-rebuild` | `local msg="current_rebuilt:` → `…current_rebuilx:` | resume-current-rebuild | RED (built-in leg) |
| M3 | `dismissed-decide` | `dismissed: $decision` → `dismissex: $decision` (automate-dismissed.sh copy) | dismissed-findings-decision-step | RED (built-in leg); real file unchanged |
| M4 | unit map | `### Scratch heading` appended to a prose copy | `FAIL: unmapped unit per-item-loop.md\|Scratch heading` | RED (built-in leg) |
| M5 | unit map | `### Termination (two exits)` removed from a prose copy | `FAIL: stale map row per-item-loop.md\|Termination (two exits)` | RED (built-in leg) |
| M6 | scrub | a `/Users/x/` line added to a fixtures copy | `FAIL: home path in MAP.tsv` | RED (built-in leg) |
| H1 | `progress-append` | `AH_NEWLINE="- $line"` → `AH_NEWLINE="* $line"` | pick-current-set-then-picked | RED |
| H2 | `runfile-write` | `grep -qE '^## Queue'` → `'^## Queuf'` | rate-limit-park | RED |
| H3 | `current-set` | `echo "current-set: written"` → `…writtem"` | pick-current-set-then-picked | RED |
| H4 | `current-escalation` | `new_line="- escalation_cause: $cause` → `…escalation_causf: $cause` | escalated-park | RED |
| H5 | `remaining` | `grep -c '^- \[ \] '` → one extra space after the box | termination-limit-reached | RED |
| H6 | `queue-checkoff` | `item "  # " mark ": " reason` → `mark "; " reason` | skipped-item-check-off | RED |
| H7 | `ceiling-check` | `echo "PARK: ledger_unreadable"` → `…unreadablx"` (the empty-reader arm: the literal is on two code lines, so the row anchors on the unique preceding line `grep -q 'LEDGER_UNREADABLE=1' <<<"$ledger_out"; then`) | pick-time-token-ceiling-park | RED |
| H8 | `config-orig` / `config-suppress` / `config-restore` | `if [ ! -f "$src" ]; then echo "absent"` → `echo "absenx"` | run-config-suppress-restore | RED |
| H9 | `closeout-classify` | `echo "complete"` → `echo "completf"` | sync-closeout-no-trail | RED |
| H10 | `reconcile-item` | `echo "merged"; return 0` → `echo "mergex"; return 0` | reconcile-closeout-merged | RED |
| H11 | `park-ask-gate` | `merge watcher armed"` → `merge watcher armex"` | park-first-ready-park | RED |
| H12 | `resume-glob` | `echo "$f"` → `echo "$f,"` (on the line after the unique `[ "$(_resume_title_run_id "$f")" = "$own" ]`) | resume-glob-finalize | RED |
| H13 | `gate-eval` | `echo "PARK: head_sha_moved"` → `…head_sha_movex"` | gate-eval-head-sha-moved-park | RED |
| H14 | `learning-emit` | `review_rounds: $err` → `review_roundx: $err` | learning-emit-end-of-drain | RED |
| H15 | `brief-repair` | `echo "brief-repair: repaired ` → `…repairex ` | brief-repair-merged | RED |
| H16 | `reconcile-status` | `printf 'plan\t%s\t%s\t%s\n' "$rel" "$status_line" "$just"` → `'plam\t…'` | resume-reconcile-status | RED |
| H17 | `dismissed-drafts` | `echo "dismissed-drafts: $n per-finding` → `…per-findinf` | park-first-ready-park | RED |
| H18 | `dismissed-pending` | `  echo "$c"` → `  echo "$c."` | park-first-ready-park | RED |
| H19 | `dismissed-cost` | `DISMISSED_COST_DEFAULT="fix_now_cost: ≈ 1h06m` → `≈ 1h07m` | park-first-decisions-recorded | RED |
| H20 | `closeout` | `sp="closeout: stamped — $item` → `…stampex — $item` | sync-closeout-no-trail | RED |
| H21 | `trail-pr` | `mode="opened"` → `mode="openex"` | termination-queue-resolved | RED |
| H22 | `trail-gate` | `C="trail-gate: clear — no open trail PR;"` → `…clean — …` | reconcile-closeout-merged | RED |
| H23 | `trail-unstage` | `echo "trail-unstage: unstaged $n path(s) — $done_l"` → `…unstagex …` | reconcile-closeout-merged | RED |
| H24 | `sidecar-check` | `say("ok %s" % path)` → `say("oj %s" % path)` | drain-owned-drain-started | RED |
| H25 | `sweep` | `printf 'sweep: summary — %s: %s %s` → `— %s; %s %s` | termination-queue-resolved | RED |
| H26 | `validation-gate` | `echo "$G ok — $k running-system step(s) evidenced"` → `…evidencex"` | gate-validation-recheck-at-reconcile | RED |
| H27 | `pick-guard` | `echo "refuse: live_lane $run $lane"` → `…live_lanf …` | pick-time-lane-guard-park | RED |
| H28 | `lane-park` | `else echo ready_for_release; fi` → `…ready_for_releasf; fi` | dismissed-findings-decision-step | RED |

Two first attempts were wrong and are recorded rather than hidden. H23 first mutated `echo "$S nothing staged"` and
stayed GREEN: after `closeout`'s real `trail-pr`, `trail-unstage` takes its `unstaged <n> path(s)` branch, so the
row now mutates that literal (RED). H12 and H16 first used anchors that occur 3 and 2 times; the gate refused them
before they ran, and both now use unique anchors.

Run of every H row in one pass (`<id> | target | case | inner-suite FAIL lines`):

```text
H1 | bundle | pick-current-set-then-picked | FAIL: pick-current-set-then-picked: run file differs;
H2 | bundle | rate-limit-park | FAIL: rate-limit-park: run file differs;FAIL: rate-limit-park: step output differs;
H3 | bundle | pick-current-set-then-picked | FAIL: pick-current-set-then-picked: step output differs;
H4 | bundle | escalated-park | FAIL: escalated-park: run file differs;
H5 | bundle | termination-limit-reached | FAIL: termination-limit-reached: run file differs;FAIL: termination-limit-reached: step output differs;
H6 | bundle | skipped-item-check-off | FAIL: skipped-item-check-off: run file differs;
H7 | bundle | pick-time-token-ceiling-park | FAIL: pick-time-token-ceiling-park: step output differs;
H8 | bundle | run-config-suppress-restore | FAIL: run-config-suppress-restore: step output differs;
H9 | bundle | sync-closeout-no-trail | FAIL: sync-closeout-no-trail: step output differs;
H10 | bundle | reconcile-closeout-merged | FAIL: reconcile-closeout-merged: run file differs;FAIL: reconcile-closeout-merged: step output differs;
H11 | bundle | park-first-ready-park | FAIL: park-first-ready-park: run file differs;FAIL: park-first-ready-park: step output differs;
H12 | bundle | resume-glob-finalize | FAIL: resume-glob-finalize: step output differs;
H13 | bundle | gate-eval-head-sha-moved-park | FAIL: gate-eval-head-sha-moved-park: run file differs;FAIL: gate-eval-head-sha-moved-park: step output differs;
H14 | bundle | learning-emit-end-of-drain | FAIL: learning-emit-end-of-drain: step output differs;
H15 | bundle | brief-repair-merged | FAIL: brief-repair-merged: run file differs;FAIL: brief-repair-merged: step output differs;
H16 | bundle | resume-reconcile-status | FAIL: resume-reconcile-status: run file differs;FAIL: resume-reconcile-status: step output differs;
H17 | automate-dismissed.sh | park-first-ready-park | FAIL: park-first-ready-park: run file differs;FAIL: park-first-ready-park: step output differs;
H18 | automate-dismissed.sh | park-first-ready-park | FAIL: park-first-ready-park: step output differs;
H19 | automate-dismissed.sh | park-first-decisions-recorded | FAIL: park-first-decisions-recorded: run file differs;FAIL: park-first-decisions-recorded: step output differs;
H20 | automate-trail.sh | sync-closeout-no-trail | FAIL: sync-closeout-no-trail: run file differs;FAIL: sync-closeout-no-trail: step output differs;
H21 | automate-trail.sh | termination-queue-resolved | FAIL: termination-queue-resolved: run file differs;FAIL: termination-queue-resolved: step output differs;
H22 | automate-trail.sh | reconcile-closeout-merged | FAIL: reconcile-closeout-merged: run file differs;FAIL: reconcile-closeout-merged: step output differs;
H23 | automate-trail.sh | reconcile-closeout-merged | FAIL: reconcile-closeout-merged: run file differs;FAIL: reconcile-closeout-merged: step output differs;
H24 | automate-trail.sh | drain-owned-drain-started | FAIL: drain-owned-drain-started: step output differs;
H25 | automate-trail.sh | termination-queue-resolved | FAIL: termination-queue-resolved: run file differs;FAIL: termination-queue-resolved: step output differs;
H26 | automate-lanes.sh | gate-validation-recheck-at-reconcile | FAIL: gate-validation-recheck-at-reconcile: run file differs;FAIL: gate-validation-recheck-at-reconcile: step output differs;
H27 | automate-lanes.sh | pick-time-lane-guard-park | FAIL: pick-time-lane-guard-park: step output differs;
H28 | automate-lanes.sh | dismissed-findings-decision-step | FAIL: dismissed-findings-decision-step: step output differs;
working tree: loomwright/scripts unchanged (git diff --quiet)
```

## validation 1

Drain round 1 (refreshed count): `bash loomwright/scripts/test-automate-golden.sh` → `PASS: 64 FAIL: 0`, and the
same under `bash -c "trap '' PIPE; …"` → `PASS: 64 FAIL: 0`. The two new checks are the phase-2 `$PREV` lint
(`ok: no step reads $PREV after current-set / runfile-write (or before any step)`) and leg M11
(`FAIL: pick-time-lane-guard-park: $PREV read after current-set` on the pre-fix steps). Three fixtures had
pinned `current-set: written`, or blank fields, as their park's Progress line: `pick-time-lane-guard-park`,
`pick-time-token-ceiling-park` and `closeout-leftover-gate-non-interactive`. Each now caches its producer's stdout
right after it (`loop: cp "$PREV" "$ROOT/.<name>.line"`), so each gains one step, and its last Progress line is
the real diagnostic: `refuse: live_lane automate-2026-10-08-033739-L1 L1`, `PARK: ledger_unreadable`, and
`closeout leftover: automate-2026-10-13-181331 stamp skipped — no done brief`. Running the lint on the pre-fix
fixtures flags exactly those three cases and no others. The transcript below is review iteration 2's and keeps
its counts.

Review iteration 2: five back-to-back runs of `bash loomwright/scripts/test-automate-golden.sh` →
`PASS: 62 FAIL: 0` all five (5/5), and `/bin/bash` 3.2.57 → `PASS: 62 FAIL: 0`.

`bash loomwright/scripts/test-automate-golden.sh` — **62/62, 0 failures** (map lines elided; the run prints one
`map: <unit id> → <case>` line for each of the 50 units):

```text
== test-automate-golden.sh — prose: <repo>/loomwright/scripts/../skills/automate-loop · fixtures: <repo>/loomwright/scripts/fixtures/automate-golden
-- 1. unit map
  ok: MAP.tsv: no stale row, every named case exists
  ok: unit map read: 50 unit(s) extracted live from resume.md per-item-loop.md modes-and-merge-gate.md
-- 2. home-path scrub
  ok: no /Users/ or /home/ path under the fixtures
  ok: no expected.out pins the SIGPIPE noise line
  ok: no gitignored file under the fixtures (a clean checkout sees every fixture)
-- 3. golden cases
  ok: brief-repair-merged: run file + step output match (4 step(s))
  ok: check-off-progress: run file + step output match (2 step(s))
  ok: closeout-leftover-gate-non-interactive: run file + step output match (3 step(s))
  ok: dismissed-findings-decision-step: run file + step output match (13 step(s))
  ok: dismissed-fix-now-re-drain: run file + step output match (11 step(s))
  ok: drain-owned-drain-started: run file + step output match (5 step(s))
  ok: drain-pinned-start-line-current-not-set: run file + step output match (1 step(s))
  ok: drain-superseded-by-merge: run file + step output match (7 step(s))
  ok: escalated-park: run file + step output match (6 step(s))
  ok: fix-now-became-follow-up: run file + step output match (3 step(s))
  ok: gate-eval-checks-not-green-park: run file + step output match (5 step(s))
  ok: gate-eval-drain-not-ready-park: run file + step output match (5 step(s))
  ok: gate-eval-head-sha-moved-park: run file + step output match (5 step(s))
  ok: gate-eval-high-risk-diff-park: run file + step output match (5 step(s))
  ok: gate-eval-merge: run file + step output match (3 step(s))
  ok: gate-eval-review-decision-blocking-park: run file + step output match (5 step(s))
  ok: gate-eval-rules-gate-head-mismatch-park: run file + step output match (5 step(s))
  ok: gate-eval-unprotected-branch-park: run file + step output match (5 step(s))
  ok: gate-validation-gate-unrun-escalated: run file + step output match (8 step(s))
  ok: gate-validation-recheck-at-reconcile: run file + step output match (3 step(s))
  ok: gate-validation-waive: run file + step output match (4 step(s))
  ok: learning-emit-end-of-drain: run file + step output match (3 step(s))
  ok: park-first-decisions-recorded: run file + step output match (6 step(s))
  ok: park-first-ready-park: run file + step output match (9 step(s))
  ok: pick-current-set-then-picked: run file + step output match (2 step(s))
  ok: pick-pending-decisions-ask: run file + step output match (4 step(s))
  ok: pick-time-lane-guard-park: run file + step output match (4 step(s))
  ok: pick-time-token-ceiling-park: run file + step output match (4 step(s))
  ok: pick-time-trail-gate-park: run file + step output match (4 step(s))
  ok: rate-limit-park: run file + step output match (3 step(s))
  ok: reconcile-closeout-merged: run file + step output match (9 step(s))
  ok: resume-ambiguous-park: run file + step output match (2 step(s))
  ok: resume-config-crash-restore: run file + step output match (2 step(s))
  ok: resume-current-rebuild: run file + step output match (2 step(s))
  ok: resume-glob-finalize: run file + step output match (2 step(s))
  ok: resume-rate-limit-park: run file + step output match (4 step(s))
  ok: resume-reconcile-status: run file + step output match (2 step(s))
  ok: run-config-suppress-restore: run file + step output match (7 step(s))
  ok: run-record-pr: run file + step output match (4 step(s))
  ok: skipped-item-check-off: run file + step output match (5 step(s))
  ok: sync-closeout-no-trail: run file + step output match (2 step(s))
  ok: termination-limit-reached: run file + step output match (4 step(s))
  ok: termination-queue-resolved: run file + step output match (7 step(s))
-- 4. mutation legs
  ok: M1: inner run red (exit 1), names: FAIL: drain-pinned-start-line-current-not-set:
  ok: M2: inner run red (exit 1), names: FAIL: resume-current-rebuild:
  ok: M3: inner run red (exit 1), names: FAIL: dismissed-findings-decision-step:
  ok: M3: the real automate-dismissed.sh is unchanged
  ok: M4: inner run red (exit 1), names: FAIL: unmapped unit per-item-loop.md|Scratch heading
  ok: M5: inner run red (exit 1), names: FAIL: stale map row per-item-loop.md|Termination (two exits)
  ok: M6: inner run red (exit 1), names: FAIL: home path in MAP.tsv
  ok: M7: inner run red (exit 1), names: FAIL: unmapped unit per-item-loop.md|After mixed fence
  ok: M8: inner run red (exit 1), names: FAIL: duplicate unit per-item-loop.md|Termination (two exits)
  ok: M9: inner run red (exit 1), names: FAIL: ignored fixture run-record-pr/tree/.supervisor/leak
  ok: M10a: Broken-pipe line dropped (case green), and the scrub names it as pinned
  ok: M10b: inner run red (exit 1), names: FAIL: gate-validation-waive: step output differs
  ok: M10c: inner run red (exit 1), names: FAIL: gate-validation-waive: step output differs
  ok: M10d: gate-validation-waive green with SIGPIPE inherited as ignored
PASS: 62 FAIL: 0
```

Clean clone of the committed fix (CI's shape, no ignored file on disk; review iteration 1's record — iteration 2's
clean-clone run is under "CI-red root cause (review iteration 2)"):

```text
$ git clone -q <repo> <scratch>/c && git -C <scratch>/c checkout -q <fix commit>
$ bash <scratch>/c/loomwright/scripts/test-automate-golden.sh
  ok: no gitignored file under the fixtures (a clean checkout sees every fixture)
  ok: M9: inner run red (exit 1), names: FAIL: ignored fixture run-record-pr/tree/.supervisor/leak
PASS: 57 FAIL: 0
```

`bash loomwright/scripts/test-automate-helpers.sh` — **737/737, 0 failures** in a clean local clone of this branch (CI's shape: no gitignored
`.supervisor/` queue, so W19 SKIPs). In this lane checkout the same suite reads **761 passed, 1 failed**; the one
failure is W19, which parses the GITIGNORED local `.supervisor/requirements/parallel-automate/22-*.md` (`.gitignore`
`.supervisor/*`). This branch changes nothing W19 reads, and run `automate-2026-10-13-181331` recorded the same env-only
W19 red. Clean-clone tail (ratio from its `RESULT:` line):

```text
$ git clone -q --branch feature/as05-golden-run-tests <repo> <scratch>/clone && cd <scratch>/clone
$ bash loomwright/scripts/test-automate-helpers.sh
  SKIP: W19 <scratch>/clone/.supervisor/requirements/parallel-automate absent (gitignored) — real-queue Touches parse not checked here
…
RESULT: 737 passed, 0 failed

# same suite in the lane checkout (gitignored queue present):
  FAIL: W19 real 22-split-automate-engine-surfaces.md ## Touches parses (known) (rc=0) got: wave 1: pa/01-copy.md|wave 2: pa/02-probe.md err: plan-waves: no <tmp>/.agent/companions…
RESULT: 761 passed, 1 failed
```

## validation 2

Mutation control by hand, outside the built-in legs: a SCRATCH bundle copy of `automate-helpers.sh` (built with
`_ah_bundle` beside symlinks to the sibling scripts) with the `owned drain started` alternative of the
`current_not_set` guard changed, then `GOLDEN_HELPERS=<that copy> bash loomwright/scripts/test-automate-golden.sh`.

```text
$ diff automate-helpers.sh.orig automate-helpers.sh
436c436
<   local re_g='^([^ ]+ )?(picked |ran /autonomous|owned drain started)'
---
>   local re_g='^([^ ]+ )?(picked |ran /autonomous|owned drain startex)'
$ GOLDEN_HELPERS=<scratch>/automate-helpers.sh bash loomwright/scripts/test-automate-golden.sh
V2 exit=1
FAIL: drain-pinned-start-line-current-not-set: step output differs
PASS: 52 FAIL: 1
```

(Recorded at head `33972e2`, when the suite had 53 checks; the leg set has grown since, so the tally is historical.)

Non-zero exit, naming the case. The other cases stay green because only this case drives the guard over an unset
`## Current`. The suite's own M1–M6 legs (at that head) still build their own bundles and pass inside that run.

## ci-local

`bash scripts/ci-local.sh` at head `33972e2` (then `bash scripts/ci-local.sh --wait`). The early phase (16 gates,
vendor-coupling included) was green, and the pool ran **165 of 166 self-tests green**. `test-automate-golden.sh` passed
(`PASS 41s`). The one red is the env-only W19 assertion inside `test-automate-helpers.sh` described under validation 1:
ci-local runs in this lane checkout, where the gitignored `.supervisor/` queue is present. In a clean clone that suite
reads 737/737. The previous attempt (head `351148c`) failed the early vendor-coupling gate on runtime-identity tokens in
the new files; `33972e2` removed them (no manifest edit).

```text
ci-local: early phase green after 16s — starting the pool
PASS 41s loomwright/scripts/test-automate-golden.sh
RESULT: 761 passed, 1 failed
1 of 166 self-tests FAILED (wall 863s):
  loomwright/scripts/test-automate-helpers.sh
ci-local: not run locally — ci.yml's sdk-spike step (npm build + node suites); CI still runs it.
ci-local: FAIL after 879s — see the FAIL banners above (nothing cached)
```

Review iteration 1: `bash scripts/ci-local.sh --affected` on the fix (fixtures and harness as committed; this
evidence file differed by this paragraph only) — `all 17 self-tests passed`, `ci-local --affected: PASS after 44s`,
`test-automate-golden.sh` `PASS 41s`. The first run of that command, before the token rewrite above, failed only
`check-vendor-coupling`.

`bash scripts/check-version-bump.sh`:

```text
bump-version: check OK — not bumped (version 17.3.0, the merge base's); 1 fragment(s) pending — legal, the next bump folds them (base origin/main, merge base f5c2d0e23fb7)
```

## Honest limits

- The cases replay the helper calls each step makes. They do not run the model: RUN's `/autonomous`, DRAIN's
  `/review-pr`, every owner answer, the detached merge watcher and notifications are fixed input (MAP.tsv's
  judgment/boundary rows). A `next-step` script that changes WHICH helper a branch calls fails a case only through
  the run file or the step output it changes.
- Loop-authored lines (`loop:` steps, F1/F2/F6) pin text this author chose where the prose gives none. A migration
  may change them deliberately and update the case.
- Real-run inputs were trimmed. Several branches have no real run, and those inputs were built from the nearest real
  run (each `source` names the gap). `gh` answers are stubs: PR bodies, branch-protection payloads and check
  rollups are reduced shapes, not captured API responses.
- The unit map covers the three files the brief names. `SKILL.md`, `lanes.md`, `intake.md` and the other
  `skills/automate-loop/` files are out of scope (item 04's inventory).
- Verified on macOS only (bash 5.3 and `/bin/bash` 3.2.57; BSD userland). The Linux CI run is the GNU-userland
  check.
