# dismissed-followups-02 — repo-root scripts + release (Subtask 3, `repo-scripts`): evidence

Source requirement: `.supervisor/requirements/dismissed-followups/02-gate-closeout-and-guard-correctness.md`. It is
gitignored, so this file is the committed record. It covers findings F002, F070, F350 and F292. Base commit
`8ec200e06dce87c947aadf302a20df0102e699ce`. The finding text is the original reviewer's, quoted in the requirement as
untrusted data. Captured 2026-11-09 on macOS (Darwin 25.6.0, bash 3.2, BSD userland). `<S>` is the session
scratchpad. The sibling groups' records are `docs/evidence/dismissed-followups-02-engine.md` and
`docs/evidence/dismissed-followups-02-validators.md`.

## Dispositions

| Finding | Re-verified on base | Disposition | Leg / reason |
|---|---|---|---|
| F002 | present | fixed | `scripts/test-bump-version.sh` :: `scratch: a SIGKILLed bump keeps its backups under the git dir; git status --untracked-files=all lists no .bump-version. path` and `scratch: a SIGKILLed re-fold keeps both scratch dirs (re-fold + child bump) under the git dir; git status lists neither` |
| F070 | present | fixed | `scripts/test-bump-version.sh` :: `dry-run: a contract stale BEFORE the bump is reported stale (exit 1), never 'plugin_version only'; nothing written` and `dry-run: a generator that fails is reported (exit 1, nothing written, no scratch dir left)` (control: `dry-run: a fresh contract still prints 'also regenerates: … (plugin_version only)' (exit 0, nothing written)`) |
| F350 | present | fixed | `scripts/test-ci-local.sh` :: `(LK15)` every lsof call hangs, `(LK16)` only the after-suite listener read hangs, `(LK17)` only the `-t` fd-holder probe hangs, `(LK18)` a bad `CI_LOCAL_LSOF_BOUND` |
| F292 | present | fixed (name only) | `.github/workflows/ci.yml` step renamed to `Check prompt token budgets (agents, skills, commands)`. No leg: it is a step label, and the line count is unchanged (no `ci.yml:NN` pin moves) |

## Re-verification on the base commit (before any change)

Each anchor was grepped in the base blob (`git show 8ec200e:<path> | grep -nF '<anchor>'`):

- **F002:** `mktemp -d "$repo_root/.bump-version.XXXXXX"` hits twice in `scripts/bump-version.sh`: the re-fold's
  `CW=` and the bump's `WORK=`. `git check-ignore -v .bump-version.abc123/x` printed nothing and exited 1, so the path
  is not ignored and `git add -A` would commit a leftover dir.
- **F070:** `also regenerates: $CAPS_JSON (plugin_version only)` hits once, inside the `--dry-run` block, which exits
  before `render_capabilities` and `verify_rendered` ever run.
- **F350:** `"$leak_lsof" -nP -iTCP -sTCP:LISTEN -Fp` (the listener read, used before and after the suite) and
  `"$leak_lsof" -nP -t -- "$tmpd/leak.fd"` (the fd-holder probe) each hit once in `scripts/ci-local.sh`. Neither has a
  time bound.
- **F292:** `- name: Check per-agent prompt token budgets (prompt-inventory ratchet)` hits on line 45 of
  `.github/workflows/ci.yml`. The header of `scripts/check-token-budget.sh` says it gates "every agent, every skill
  dir and every command doc".

## Fixes

- **F002:** `scripts/bump-version.sh` sets `scratch_parent` from `git rev-parse --absolute-git-dir` once, and falls
  back to the repo root outside a git repo. Both `mktemp -d` sites move together. A SIGKILL, or backups kept after a
  failed restore, now leave the scratch dir under the git dir, where `git status` never lists it. Inside a linked
  worktree the git dir is `<main>/.git/worktrees/<name>`. The HONEST LIMITS header now says where the backups are.
- **F070:** the capabilities half of `verify_rendered` is now its own function, `verify_caps_rendered <committed>
  <regenerated>`, and `verify_rendered` calls it. A plain (not re-fold) `--dry-run` with a contract present renders
  the new `plugin.json` and the contract into a scratch dir under the git dir. It then runs that same check, prints
  either `also regenerates: … (plugin_version only)` or `REFUSES: <why>`, and exits 1 on a refusal, as the real bump
  would. The usage text and the `Exit:` line say so. The re-fold dry run is unchanged: its child bump does the real
  check.
- **F350:** `scripts/ci-local.sh` gains `leak_lsof_run OUT ARGS...`. It is the one wrapper for all three `lsof` calls.
  The call runs in the background into a file and is bounded with `finish_log`'s idiom: a `kill -0` poll with a
  counter (`CI_LOCAL_LSOF_BOUND` s, default 10, a positive integer, exit 2 otherwise), then `kill -KILL`. If the
  process is still alive after the KILL (uninterruptible sleep), it is not waited for. The call runs under
  `env -u LOOMWRIGHT_CI_LOCAL_RUN` with fd 9 closed, so neither half of the gate can attribute it. A cut-off
  listener read prints `ci-local: leak gate — listeners unchecked (lsof timed out after <N>s)` instead of the
  before/after comparison. A cut-off fd probe prints `ci-local: leak gate — inherited-fd marker unchecked (lsof
  timed out after <N>s)`. Both are report-only and never change the verdict. The listener read now writes to a file
  instead of a pipe, so a grandchild of `lsof` cannot hold the read open either. The LEAK GATE honest limits gain
  item (7), and `CI_LOCAL_LSOF_BOUND` is listed under `env:`.
  **`-b` was not added.** The brief added it only if the fd-holder probe still found a holder with it. It does not:
  with a child holding the probe file open, `lsof -nP -t -- <file>` printed the child's pid, while
  `lsof -b -nP -t -- <file>` printed `lsof: status error on <file>: Resource temporarily unavailable` and the usage
  text (lsof 4.91, macOS).
- **F292:** only the step `name:` changed (a one-line diff with no inserted line).

## Red on the pre-fix scripts, green on the fixed ones

**bump-version (F002, F070).** The suite's own seam runs it against another copy:
`BUMP_VERSION_UNDER_TEST=<S>/bump-version.base.sh bash scripts/test-bump-version.sh`, where the copy is
`git show 8ec200e:scripts/bump-version.sh`.

| Run | Result | Failing legs |
|---|---|---|
| base `bump-version.sh` | `RESULT: 143 passed, 4 failed` | both `scratch: a SIGKILLed …` legs, `dry-run: a contract stale BEFORE the bump …`, `dry-run: a generator that fails is reported …` |
| fixed `bump-version.sh` | `RESULT: 147 passed, 0 failed` | — |
| pin mutation: the re-fold's `CW=` site flipped back to `$repo_root` | `146 passed, 1 failed` | `scratch: a SIGKILLed re-fold keeps both scratch dirs …` |
| pin mutation: the dry-run render and caps verify deleted (the old one-line claim restored) | `145 passed, 2 failed` | both `dry-run: …` refusal legs |

The fresh-contract control (`dry-run: a fresh contract still prints …`) and the successful-bump control
(`scratch: a successful bump removes its scratch dir …`) pass on both scripts, as they should. So does
`scratch: outside a git repo the bump still works and leaves no scratch dir at the repo root`, the fallback branch. The SIGKILL legs kill
the bump from inside an injected validator. The bump leg kills `$PPID`. The re-fold leg kills the child bump and its
parent re-fold, so no EXIT trap runs. Each leg also asserts that the scratch dir really is under `.git`, so it cannot
pass on an empty tree.

**ci-local (F350).** The base tree is `git archive 8ec200e` extracted to `<S>/base-tree`, with the new
`scripts/test-ci-local.sh` copied over it. Command: `bash scripts/test-ci-local.sh`. The lsof stub runs
`exec sleep 30` on the named call and passes any other call to the real `lsof`. Each leg runs with
`CI_LOCAL_LSOF_BOUND=1` and requires the run to finish in under 20 s.

| Leg | Base `ci-local.sh` | Fixed `ci-local.sh` |
|---|---|---|
| (LK15) every lsof call hangs | FAIL, the run took 93 s (three 30 s hangs, nothing reported unchecked) | ok, 6 s, both halves unchecked, no survivor, PASS |
| (LK16) only the after-suite listener read hangs | FAIL, 32 s | ok, 3 s, listeners unchecked |
| (LK17) only the `-t` fd-holder probe hangs | FAIL, 33 s | ok, 4 s, inherited-fd marker unchecked |
| (LK18) `CI_LOCAL_LSOF_BOUND=0` | FAIL (no such knob, the run went ahead) | ok, exit 2, nothing ran |
| totals | `113 passed, 4 failed` | `117 passed, 0 failed` |

Every existing leg (LK1–LK14 included) passes on both. The three hang legs are also the per-call pin mutations. All
three calls go through the one wrapper, so taking a call out of the bound reverts that call site to the base shape.
The base run shows each variant red on its own: LK16 hangs only on the after-suite read, and LK17 only on the probe.

A scratch-dir repro (`<S>/repro.*`, with `HOME` relocated) also ran `leak_lsof_run`, extracted on its own, under a
marker variable and an open fd 9. A fast stub gave `rc=0` with its output intact in 0 s. A stub that forks a
`sleep 30` child and then hangs gave `rc=1` with empty output in 2 s (bound 1). Its surviving child carried neither
the marker variable nor fd 9, because `lsof -t` on the fd-9 file did not list it.

## Honest limits

- The F350 legs simulate a hang with `exec sleep`, which `kill -KILL` ends. A real `lsof` in uninterruptible sleep on
  a stale mount was not reproduced. For that case the code skips the `wait` (a bounded post-KILL poll instead), and
  the run-marker variable plus the closed fd 9 keep it from being counted as a survivor. That reasoning comes from
  reading the code, not from a run.
- With the environment hidden (`environment unverifiable`) and the fd probe cut off, a run attributes nothing. It
  says so in two lines but does not FAIL. This is the same report-only stance as the existing "lsof absent"
  fail-open, and it is documented as LEAK GATE honest limit (7).
