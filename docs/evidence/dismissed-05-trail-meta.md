# dismissed-05 — trail / meta-sync / lanes suites (Group C): evidence

Source requirement: `.supervisor/requirements/dismissed-followups/05-test-coverage-gaps.md` (gitignored, so this file is
the committed record). Findings F331, F043, F044, F095 and F141. Base commit `26eda742b616a339f971b34b5b7d8740c9654851`.
The finding text is the original reviewer's, quoted there as untrusted data. Production scripts are unchanged: every
mutant below was built in a scratch copy of the tree under the session scratchpad (`<S>` below), never in the repo.
Each mutant was gated on non-empty, differs from the original, and `bash -n`.

## Dispositions

| Finding | Re-verified on base | Disposition | Leg / reason |
|---|---|---|---|
| F331 | present | fixed | `test-automate-lanes.sh` suite-top `unset` now also names `LOOMWRIGHT_PHASE_DIR LOOMWRIGHT_RUN_LOCK_SESSION_ID`; new legs AN0b / AN0c in `test-automate-lanes.d/06-phase-sessions.sh`. Red on pre-fix: child-process repro (inbox written vs untouched), and AN0b red in a plain run of the mutant runner (see F331 below) |
| F043 | present | fixed | `test-meta-sync.d/02-guards-mode-base.sh` leg `a reader that exits 0 printing nothing -> exit 1 mode_unknown 'printed nothing'` (in group 43). Red on two scratch mutants of `meta-sync.sh` (see F043 below) |
| F044 | present | fixed | `test-meta-sync.d/02-guards-mode-base.sh` leg group `42b. a FIFO, and a dangling symlink, at <gitdir>/meta-base` (6 legs: a fixture check, push, pull per shape). Red on the scratch mutant that deletes `is not a regular file$kind` from `meta-sync.d/plan.sh` |
| F095 | present | fixed | `test-automate-trail.d/05-finalize-closeout-others.sh` leg `(DS4)` (3 assertions). Red on a scratch `closeout.sh` that drops the first non-done `## Status:` heading after appending (see F095 below) |
| F141 | present | fixed (doc-only) | `test-automate-trail.sh` §SW header: the pin-mutation list now names every `sw_mutant` call in `test-automate-trail.d/06-sweep.sh`, in order, and names that file as its authority; the header also now describes the SW7 and SWU legs. No pin (header wording) |

## Re-verification (before any change)

- **F331:** `test-automate-lanes.sh`'s only global unset was `unset CLAUDE_PLUGIN_ROOT LOOMWRIGHT_ROOT LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS`.
  `automate-lanes.d/relay.sh` routes on `if [ -n "${LOOMWRIGHT_PHASE_DIR:-}" ]; then _lanes_relay_phase "$in"; return 0; fi`.
  `hermetic-test-env.sh` does not touch either variable. Reproduced. See the child-run table below.
- **F043:** `meta-sync.sh` has the arm `"") MODE_STATE="unknown"; MODE_REASON="setup-memory.sh mode printed nothing"`.
  A grep for `printed nothing` in `test-meta-sync.d/` found nothing.
- **F044:** `meta-sync.d/plan.sh` `refuse_bad_base()` refuses any meta-base that exists (or is a symlink) and is not a
  regular file. The only leg was group 42 (`mkdir` meta-base). A grep found no `mkfifo` or symlink meta-base leg in `test-meta-sync.d/`.
- **F095:** `brief-shipped` appeared in no `test-automate-trail.d/` part. DS1–DS3 use `pending` only.
- **F141:** the §SW header listed 6 pin mutations: tip, app, sweep verdict, closeout 3a verdict, coverage, escaped-byte.
  `06-sweep.sh` builds 11: `tip app verdict coverage unverif gitstatus rmrefused bytes prcache coverdict unresolved`
  (re-grepped with `grep -oE 'sw_mutant [a-z]+ '`). The header was missing `unverif`, `gitstatus`, `rmrefused`,
  `prcache` and `unresolved`.

## F331: ambient phase variables (child-process repro)

The scratch "real" phase inbox is a valid phase dir:
`<S>/f331/<pre|post>/proj/.supervisor/automate/run-x.phase/supervisor` (it passes `_lanes_phase_dir_ok`). Both runs:
`env LOOMWRIGHT_PHASE_DIR=<that dir> LOOMWRIGHT_RUN_LOCK_SESSION_ID=sess-ambient-x bash loomwright/scripts/test-automate-lanes.sh`.

| Runner | Suite result | Files written into the scratch inbox |
|---|---|---|
| pre-fix (`git archive` of base) | `passed: 1027  failed: 43` | 19 (`inbox/questions/toolu_q1.json`, `toolu_q9.json`, `toolu_s1.json`, `toolu_x5.json`, `toolu_x9.json`, `toolu_p7.json`, …) |
| post-fix (this branch) | `passed: 1071  failed: 1` | 0 (only the 5 planted directories exist; no `inbox/` was created) |

The pre-fix run's 43 FAILs are the relay legs whose questions went to the ambient phase dir instead of the lane inbox
(J3, J4, K1b–K16, X2–X9, AD4–AD12, AM1–AM7b, …). Both runs' one shared FAIL, `AH9 lane-wait writes nothing into any
lane` (`expected [1] got [0]`), is a load artefact. Those two runs went alongside the meta-sync and trail suites, four
suites at once, and AH9 compares `find -newer` counts across a one-second lane-wait pass. AH9 passed in two other
runs: the plain post-fix run below, and an earlier, less-loaded ambient pre-fix run. That earlier run's totals are not
used anywhere else, because the runner was edited while it ran. AH9 reads no phase variable.

**Committed leg.** A plain CI run never has the variables set at suite start. So AN0b does not re-run the whole
suite. It takes the runner's own suite-top `unset CLAUDE_PLUGIN_ROOT …` line and runs it in a child that has both
variables set. The leg then asserts that both read `unset`. A newline separates the line from the probe, so a trailing
`#` comment on the line cannot swallow the probe. A scratch repro hit exactly that bug with a `;` separator on the
base line. Results for that line:

| Runner the line is read from | Child prints |
|---|---|
| this branch | `unset:unset` |
| mutant (the two names removed: the Pin-mutations row) | `/x/supervisor:sess-ambient` |
| base | `/x/supervisor:sess-ambient` |

A full plain run of the mutant suite (no ambient variables, the CI shape) gives `passed: 1071  failed: 1`. The one
FAIL is AN0b: `expected [unset:unset] got [<T>/ambient-phase/supervisor:sess-ambient]`. So the regression is red in CI.
The full plain post-fix run gives `passed: 1072  failed: 0` (AH9 ok).

AN0c asserts that neither variable is set in the suite's own shell when part 06 starts. It is vacuous in a plain run.
It has teeth only in a run started with the variables set, where it catches an earlier part that exports one.

## F043: empty mode-reader output

The leg plants a `setup-memory.sh` that runs `exit 0` and prints nothing beside a copy of `meta-sync.sh`. It runs
`status` and asserts exit 1 plus the exact line `meta_sync: mode_unknown — setup-memory.sh mode printed nothing; nothing was changed`.

| Scratch mutant of `meta-sync.sh` | Leg result |
|---|---|
| none (this branch, full suite) | ok (`test-meta-sync: 366 passed, 0 failed`) |
| `MODE_REASON="setup-memory.sh mode printed nothing"` replaced by `:` (the Pin-mutations row) | FAIL — output `mode_unknown — ; nothing was changed …` |
| the `""` arm mapped to `MODE_STATE="off"` (the finding's own mutant) | FAIL — the run went past the mode check, so the message is absent |

## F044: FIFO / dangling-symlink meta-base

Group 42b reuses group 42's world: a synced pair, A pushes `x.md` v2, and B holds a new local file. B's
`<gitdir>/meta-base` is then replaced by a FIFO (`mkfifo`) or by a symlink to a path that does not exist. For push and
for pull, each leg asserts all of the following:
- exit 1 and the `meta_sync: refusing — meta-base …/meta-base is not a regular file; remove or replace it by hand. Nothing was changed …` line;
- the planted shape is kept (still a FIFO; still a symlink whose target was never created);
- the branch tip is unchanged and B's file is not on the branch;
- `x.md` is still v1 and B's local file is untouched;
- **nothing fetched**: A's new tip commit is still absent from B's object store. A fixture check before the run confirms it starts absent.

The scratch mutant deletes `is not a regular file$kind` from `meta-sync.d/plan.sh` (the Pin-mutations row). On it,
all 4 refusal legs of 42b FAIL (FIFO push and pull, dangling push and pull). The 2 fixture checks stay ok, as they
should. Group 42's 2 legs FAIL too, because the deleted text carries its `(it is a directory)` suffix. This mutant
shared one scratch tree with the first F043 mutant. Their legs are disjoint: the F043 leg plants no meta-base, and the
42b legs plant no reader. Result: `test-meta-sync: 207 passed, 7 failed`, i.e. 4 (42b) + 2 (42) + 1 (F043). That
tree's runner sourced only parts 01 and 02 (see "Trimmed runners" under F095).

## F095: closeout over a `brief-shipped` requirement (DS4)

DS4 uses fixture 371. The requirement is `# req a`, a blank line, then `## Status: brief-shipped`, and the PR is MERGED.
DS4 asserts:
1. the `closeout: stamped — <req> (## Status: done, brief .supervisor/jobs/done/brief-a.md)` line;
2. the `## Status:` headings read, in order, `brief-shipped,done`;
3. the requirement is the brief-shipped bytes plus the step-5 printf block, byte for byte (Completed normalised to `<TS>`).

On this branch: all 3 ok (`test-automate-trail: 813 passed, 0 failed`).

Scratch mutant: `closeout.sh` appends the block, then deletes the first `## Status:` heading that is not `done`. That
is the "replace the first heading instead of appending" shape. Result: `test-automate-trail: 711 passed, 3 failed`, from
parts 01–05.
- `(DS4) status headings in order: 'done'`
- `(DS4) stamped bytes differ: 3d2|< ## Status: brief-shipped|`
- `(DS2) stamped bytes differ: 3d2|< ## Status: pending|` (DS2's own byte check also catches this mutant on the pending case)

DS4's stamped-line assertion stays ok on the mutant, as it should: the stamp is still written. An earlier, broader
mutant also deleted the done heading when the heading was the first one. It went red in part 02's AC11 re-run legs
too, so it was replaced by this targeted one.

Trimmed runners: a scratch mutant tree's runner sometimes sourced only the parts its leg needs. The trail tree dropped
part 06, and the meta-sync tree dropped parts 03 and 04. This only shortens the run. The legs are unchanged, and the
committed runners still source every part.

## Honest limits

- AN0b pins the runner's unset LINE by running it, not the whole suite as a child. A suite that re-exports a phase
  variable after that line would not be caught in CI. AN0c catches that only in a run started with the variables set.
- The F043 / F044 / F095 legs pin observable output and file state. They do not pin which internal function produced it.
- F141 is a hand-regenerated list. No CI check compares it with the `sw_mutant` calls. The header now names
  `06-sweep.sh` as the authority, so the next editor knows where to regenerate it from.
