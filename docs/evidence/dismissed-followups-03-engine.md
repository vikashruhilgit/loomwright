# Dismissed follow-ups 03 — engine group: dispositions

Base commit: `f071613abefa18cb4e4a94e2191364771db5e458`. Each re-verify check ran on the base text
(`git show f071613:<path> | grep -nF -- '<anchor>'`; the line numbers are the base file's). Pre-fix red
runs: the fix branch's files copied to a scratch tree (rsync, no `.git`, then a fresh `git init` +
commit there) with the eight fixed scripts — `lane-sampler.sh`, `automate-lanes.d/common.sh`,
`automate-lanes.d/launch.sh`, `automate-lanes.d/status-read.sh`, `automate-helpers.d/plan-waves.sh`,
`automate-trail.d/sweep.sh`, `janitor-report.sh`, `setup-memory.sh` — put back to their
`git show f071613:<path>` text, and the NEW test files run there:

| Suite (scratch tree, base scripts) | Result | On the fix branch |
|---|---|---|
| `bash loomwright/scripts/test-lane-sampler.sh` | 77 passed, 6 failed (3 legs + the 3 mutation controls, whose target text does not exist yet) | 83 passed, 0 failed |
| `bash loomwright/scripts/test-automate-lanes.sh` | 1257 passed, 3 failed (G4b, G4c, G4d) | 1260 passed, 0 failed |
| `bash loomwright/scripts/test-automate-helpers.sh 13-plan-waves` | 169 passed, 2 failed (X1f, X1g) | 171 passed, 0 failed |
| `bash loomwright/scripts/test-automate-trail.sh --group 1` | 396 passed, 2 failed (SW9 apply, and the liveread mutant that has nothing to mutate) | 399 passed, 0 failed |
| `bash loomwright/scripts/test-janitor-report.sh` | 108 passed, 4 failed (both leg_empty_id legs, and the emptyid mutant's two gates) | 111 passed, 0 failed |
| `bash loomwright/scripts/test-setup-memory.sh` | 587 passed, 2 failed (the two extra-argument legs) | 589 passed, 0 failed |

Every X1 leg of `13-plan-waves.sh` and the `W-AS24` plan-waves goldens (`explain.golden` included)
stay byte-identical on the fix branch.

| Finding | Re-verify check on base | Disposition | Test file :: leg | Pre-fix red result |
|---|---|---|---|---|
| F351 | `grep -nF "trap 'exit 0' TERM INT HUP" loomwright/scripts/lane-sampler.sh` (line 346: the trap removes nothing); `grep -nF -- "printf 'sample: %s\n' \"\$1\"; }"` (line 254: two-line trip file, no pid); `grep -nF '[ -e "$LN_PRIMARY/.supervisor/automate/$LN_PARENT.memory-pressure" ]' loomwright/scripts/automate-lanes.d/launch.sh` (line 13: bare existence holds); `grep -nF -- '--arg mp "$([ -e "$primary/.supervisor/automate/$parent.memory-pressure" ]' loomwright/scripts/automate-lanes.d/status-read.sh` (line 640) | fixed | `loomwright/scripts/test-lane-sampler.sh` :: `(GT) trip file line 3 = sampler_pid: <the sampler's pid>`, `(GT) an adopting sampler re-points sampler_pid: at itself, lines 1-2 kept`, `(GT) TERM while tripped removes the trip file` (control `(GT) a TERM never removes a trip file that names another sampler`; three mutation controls); `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` :: `G4b a trip naming a dead sampler pid does not hold memory_pressure`, `G4c … lane-status --json reads memory_pressure: false`, `G4d … and lane-status --verbose prints no 'new launches held'` (controls `G4e`/`G4f` live pid holds, `G4g` no `sampler_pid:` line holds, and the unchanged `G4`) | `FAIL (GT) trip file line 3 = sampler_pid: <the sampler's pid> (want 'sampler_pid: 99567', got '')`; `FAIL (GT) an adopting sampler re-points …` (2 lines, no line 3); `FAIL (GT) TERM while tripped removes the trip file (want 'no', got 'yes')`; `FAIL - G4b … expected [4:lane-launch: HELD — L1 — load overloaded] got [4:lane-launch: HELD — L1 — memory_pressure]`; `FAIL - G4c … expected [false] got [true]`; `FAIL - G4d … unexpected [new launches held]` |
| F023 | `grep -nF "printf 'wave %s full (--max %s)\n'" loomwright/scripts/automate-helpers.d/plan-waves.sh` (line 587: the full-wave branch records only that line, no `_pw_conflicts` call) | fixed | `loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh` :: `X1f explain: a full-wave item also names its conflict with a wave member` | `FAIL: X1f … got: …|explain q/03-c.md (wave 2):|  wave 1 full (--max 2)|  small (1 files): …` (no `conflicts with q/01-a.md on a/x.sh (declared)` line) |
| F025 | `grep -nF "for j in \$waitj; do printf 'depends on %s\n'" loomwright/scripts/automate-helpers.d/plan-waves.sh` (line 609: the deps-unmet branch records only dependency lines) | fixed | `13-plan-waves.sh` :: `X1g explain: an item with an unmet dependency also names its missing Touches` | `FAIL: X1g … got: …|explain q/02-b.md (wave 2):|  depends on q/01-a.md` (no `runs alone: Touches unknown (missing)` line) |
| F142 | `grep -nF 'function flush() { if (n > 1 && path != "")' loomwright/scripts/automate-trail.d/sweep.sh` (line 206: record 1 is dropped by position) | fixed (no observable change; no leg) | — (`flush()` is now `if (path != "")`; the primary is skipped by the explicit `[ "$cp" = "$SW_PRI" ]` check) | — Observed neutral: the base and fixed `automate-trail.sh sweep` print byte-identical output for a normal primary with two linked worktrees, a bare repository rooted at its linked worktree, and a `--separate-git-dir` primary (scratch probe, `gh`/`lsof` stubbed). In the last two layouts the sweep examines nothing either way: the computed primary (the parent of the git common dir) is not a checkout, so `git worktree list` there prints nothing |
| F137 | `grep -nF '[ -z "$SW_LIVE_STATE" ] || return 0' loomwright/scripts/automate-trail.d/sweep.sh` (line 120: one lsof read per sweep; the apply branch never re-reads before `git worktree remove`) | fixed | `loomwright/scripts/test-automate-trail.d/06-sweep.sh` :: `(SW9) --apply re-reads liveness before each removal: the first worktree is removed, the second (a live cwd since the first read) is kept` (control `(SW9) dry run: ONE lsof read for two removable worktrees (both would-remove)`; mutation control `(SWM) control: without the re-read before the removal …`) | `FAIL: (SW9) --apply: sweep: removed worktree …/proj-late-a — … \| sweep: removed worktree …/proj-late-b — …` (both removed: the late live cwd was never read) |
| F138 | `git show f071613:loomwright/scripts/automate-trail.d/finalize.sh \| grep -nF 'sw="$( (sweep_run --root "$root") 2>/dev/null \| tail -n1)"'` (line 149: dry sweep at every run end) and `grep -nF 'Cost: one' …/sweep.sh` (line 46: the header names the cost, memoised per branch in `SW_PR_CACHE`) | recorded | — | Not a defect: the run-end sweep is dry, reads `gh` at most once per branch (memoised), and the PR that added it accepted that cost; bounding it would hide branches from the run-end report |
| F353 | `grep -nF '*) case "$a" in *[!A-Za-z0-9-]*)' loomwright/scripts/janitor-report.sh` (line 887: an empty argument matches neither arm, so `ids=" "` passes the no-id check) | fixed | `loomwright/scripts/test-janitor-report.sh` :: `leg_empty_id act --confirm '' exits 2 with 'act — empty row id' on stderr, no checkout refusal`, `leg_empty_id act '' (no --confirm) exits 2 the same way` (mutation control `act's empty-id arm deleted …`) | `FAIL: leg_empty_id act --confirm '' …` and `FAIL: leg_empty_id act '' …` (base: exit 0 with `janitor: refused — not a git checkout (…)`) |
| F355 | `git show f071613:loomwright/scripts/janitor-report.sh \| grep -nF '_jr_snap_get() { awk'` (line 293: `_jr_snap_get() { awk -F'\t' -v p="$1" -v c="$2" '$1 == p { print $c; exit }' <<<"$JR_SNAP"; }`) | recorded | — | Already fixed at f071613: `_jr_snap_get` feeds awk a here-string (`<<<"$JR_SNAP"`), no `printf` pipe, so no broken-pipe write can occur |
| F058 | `grep -nF "*) echo \"setup-memory: unknown arg '\$1' (try --help)\" >&2; shift ;;" loomwright/scripts/setup-memory.sh` (line 320: an extra positional after `valid-branch <name>` only warns, and the name is judged) | fixed | `loomwright/scripts/test-setup-memory.d/05-branch-mode-consent.sh` :: `(vb) an extra argument after the name is refused: exit 1, ONE exact stderr line`, `(vb) a split name (my branch) is refused, never judged as 'my'` (control `(vb) control: the bare name alone is still accepted (exit 0, silent)`) | `FAIL: (vb) valid-branch loomwright-meta extra ⇒ rc=0 err='setup-memory: unknown arg 'extra' (try --help)'`; the same for `my branch` |

Pin mutations (each applied to a scratch copy of the fixed tree; every one turns its leg red):

| Pin | Mutation | Red legs |
|---|---|---|
| F351 sampler line 3 / TERM release | drop the `sampler_pid:` printf in `write_trip`; drop `release_trip` from the TERM trap; drop the owner check in `release_trip` | in-suite mutation controls of `test-lane-sampler.sh` (all three `ok`) |
| F351 admission | `_lanes_trip_live` → `[ -e` in `_lanes_admission` (`launch.sh`) | `G4b` (part 01 only) |
| F351 lane-status | `_lanes_trip_live` → `[ -e` in the `--arg mp` read (`status-read.sh`) | `G4c`, `G4d` (part 01 only) |
| F351 no `sampler_pid:` line holds | the `''|*[!0-9]*` arm of `_lanes_trip_live` returns 1 | `G4`, `G4g` (part 01 only) |
| F023 | the full-wave `_pw_conflicts` loop disabled | `X1f` |
| F025 | the deps-unmet `runs alone: Touches unknown` printf removed | `X1g` |
| F137 | the `SW_LIVE_STATE=""` reset before the removal deleted | in-suite `(SWM) control` |
| F353 | the `'')` arm deleted | in-suite `run_mutant` |
| F058 | the extra-argument refusal disabled | both `(vb)` extra-argument legs |

Design notes (where the fix goes past the brief's wording, and why):

- F351: a sampler that starts while a trip file exists adopts it (the existing rule) and now also
  re-points line 3 at itself (`adopt_trip`, lines 1-2 kept). Without that, an adopted trip would name
  the previous, dead sampler, so `_lanes_trip_live` would admit launches while the new sampler still
  reads itself as tripped. The TERM/INT/HUP trap removes the trip file only when line 3 names this
  sampler (`release_trip`), so a TERM'd `--once` run never removes a file another sampler owns.
- F137: the three-way liveness verdict (live / lsof unverifiable / path unverifiable) moved into one
  helper, `_sw_live_keep`, called at the first check and again right before the removal, so the two
  sites cannot word it two ways.
