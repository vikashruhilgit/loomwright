# Evidence: automate-helpers suite gaps (dismissed-followups/05, group B — F223, F257, F032, F036)

Base commit: `26eda742b616a339f971b34b5b7d8740c9654851`. Branch: `feature/dismissed-05-test-coverage-gaps-2`.
All runs: macOS (bash 3.2 system shell), 2026-11-02, in the worker worktree. Every scratch copy and
mutant lived in `mktemp -d` or the session scratchpad and was removed afterwards. Production scripts
(`automate-helpers.sh`, `check-doc-currency.sh`, `hermetic-test-env.sh`) were read, never edited.

## Dispositions

| Finding | Re-verification (base) | Disposition | Leg / reason |
|---|---|---|---|
| F223 | re-verified: present | fixed | new `loomwright/scripts/test-automate-helpers-modules.sh`: L0 control, L1 missing part, L2 unparseable part, L3(a)/(b) part-source lines, L4 unknown part, LM message-deleted mutants (red: §F223) |
| F257 | re-verified: present (reproduced) | fixed | `13-plan-waves.sh` W20d: `FILES[9]=…`, `FILES[${#FILES[@]}]=…`, `  FILES[0]+=…` each fail W20 naming the line (red: §F257) |
| F032 | re-verified: present | fixed | `07-rules-gate.sh` R11n: a PATH `git` shim fails only `ls-files -v` / `-o` / `-o -i` on a clean checkout ⇒ `PARK: rules_gate_dirty_tree`; transparent-shim control; three rc-capture mutants (red: §F032) |
| F036 | re-verified: present (reproduced) | fixed | `05-gate-eval-harness.sh` `e_git_env` (used by `gate()` and `07-rules-gate.sh`'s `r9_run`) with its E-env four-case leg, + `07-rules-gate.sh` R11h0 inherited-env leg (red: §F036) |

## F223 — loader error branches had no committed failing-side leg

**Re-verification.** A repo-wide grep for the four loader messages (`missing test part`, `test part does
not parse`, `part-source lines differ from TAH_PARTS`, `unknown test part`) found them only in runner
files (`test-automate-helpers.sh` and the sibling runners that copy the same loader) and in the as21
evidence file. `loomwright/scripts/test-automate-helpers-modules.sh` did not exist.

**Fix.** The new modules test builds a scratch tree per case: a copy of the runner and of
`test-automate-helpers.d/`, beside a symlink to every other `scripts/` entry, with `skills/` and `docs/`
linked one level up (the runner assembles the split automate-loop skill from `$HERE/../skills`). Each
run gets `TMPDIR` inside the test's own temp dir, so the bundle / split dirs a loader-aborted run
leaves behind are removed with it. Each leg asserts a non-zero exit AND the branch's own whole message
line, naming the planted part where the message names one. L0 runs the byte-identical copy with
`11-ceiling` (the cheapest part, about 1s) and asserts exit 0, the parts banner, a 0-failed `RESULT`
line and none of the four messages. It is picked up by `scripts/ci-local.sh` and CI's
`loomwright/scripts/test-*.sh` globs with no registration edit.

**Red on pre-fix.** The pin mutations are the message deletions, applied by the test itself: each LM
leg deletes one message from a runner copy (gated: non-empty, differs, `bash -n`, message gone), plants
the same case, and asserts the run still takes that branch (its replacement text prints, exit non-zero)
while the matching leg's check rejects it. All four LM legs report `ok`, so each of L1–L4 can go red.
The planted unparseable part is gated the other way round: non-empty, differs, and `bash -n` FAILS.

## F257 — W20 missed indexed `FILES[...]=` assignments

**Re-verification (reproduced).** A scratch file with a `FILES=(` block plus `FILES[9]="x"` and
`FILES[${#FILES[@]}]="y"`: the base guard `grep -cE '^[[:space:]]*FILES\+?='` counts 1, so W20 passes.
The fix hint's regex `FILES(\[[^]]*\])?\+?=` counts 2: it still misses the `${#FILES[@]}` append
idiom, whose subscript holds a nested `]`.

**Fix.** Both copies of the assignment guard (the count grep and the `W20_MSG` listing grep) become
`^[[:space:]]*FILES(\[.*\])?\+?=`, which counts 3 on the same file. The block parser is unchanged, as
`check-doc-currency.sh`'s comment about 13-plan-waves.sh requires. The real `check-doc-currency.sh`
still counts exactly one assignment, so W20 itself stays green. New leg W20d (three cases) appends one
indexed line to a copy of the real file and asserts W20 fails with the "assigned outside" message
naming that line number.

**Red on pre-fix.** Pin mutation from the brief: only the count guard reverted to the base regex in
`13-plan-waves.sh`. `bash test-automate-helpers.sh 13-plan-waves` went `RESULT: 166 passed, 3 failed`.
The three W20d cases failed with `got: ''`; restored, the part is `169 passed, 0 failed`.

## F032 — the rc-only arm of the three ls-files reads was never run

**Re-verification.** gate-eval still parks on `root_flags_rc` / `root_unt_rc` / `root_ign_rc` being
non-zero, OR on content. The only suite coverage was R11-MUTANT-FLAGS/UNT/IGN, which replace the whole
`if` (rc and content), and no git shim existed in `test-automate-helpers.d/`.

**Fix (R11n, in `07-rules-gate.sh` after R11f).** A PATH `git` shim execs the real git for every call
except one root `ls-files` read chosen by `R11N_FAIL`: `-v`; `-o` without `-i`; or `-o -i`. That read
exits 128 with no stdout. The checkout is clean and at head, so every read's content is empty and only
the failing read's rc can park. Legs:
- a control with the shim failing nothing ⇒ MERGE, with a non-empty call log, so the shim is transparent and was on PATH;
- each of the three modes ⇒ `PARK: rules_gate_dirty_tree`, 0 merges, rules helper never called, with the shim's `refused ls-files (<mode>)` line asserted, so each park is that read's own doing.

**Red on pre-fix.** Pin mutations from the brief, built in the suite through `r9_dir` (gated: non-empty,
differs, `bash -n`, marker): `|| root_flags_rc=$?`, `|| root_unt_rc=$?` and `|| root_ign_rc=$?` each
flipped to `|| :` in a copy of the gate. For each, the un-mutated copy parks the rc-only leg and the
mutant MERGEs it. All three R11n mutant legs report `ok`.

## F036 — `gate()` relocated HOME but leaked XDG_CONFIG_HOME and the system git config

**Re-verification (reproduced).** `gate()` set `HOME="$WD/nohome"` only, and the R11h precondition
leg ("NO global ignore configured: they are dirt") relied on there being no user global ignore. Base
parts copied into a scratch tree and run with an inherited `XDG_CONFIG_HOME` whose `git/ignore` lists
`notes.local` and `.idea/`: `env XDG_CONFIG_HOME=<scratch> bash test-automate-helpers.sh 07-rules-gate`
went `RESULT: 101 passed, 1 failed`, with `FAIL: R11 globally-ignorable files with NO global ignore
configured (precondition: they are dirt) wrong (out='MERGE' merges=1 called=yes)`.

**Fix.** `05-gate-eval-harness.sh` records the inherited `XDG_CONFIG_HOME` / `GIT_CONFIG_NOSYSTEM` once at
load. `e_git_env` treats a var as set by the leg when its set-ness or value differs from that record, and
passes a leg-set var through. Otherwise it runs the gate with `XDG_CONFIG_HOME` unset and
`GIT_CONFIG_NOSYSTEM=1`. Both `gate()` and `07-rules-gate.sh`'s `r9_run` (the mutant runner, the same
leak) go through it. The R11h/R11i legs that export their own `XDG_CONFIG_HOME` keep it. Leg E-env
checks all four `e_git_env` cases: inherited or leg-set `XDG_CONFIG_HOME`, crossed with inherited or
leg-set `GIT_CONFIG_NOSYSTEM`, read back from a child shell. New leg R11h0
runs right after the R11h precondition on the same fixture. It records a scratch XDG dir that ignores
both files as inherited (as the harness records it at load) and exports it. It then asserts the gate
parks `rules_gate_dirty_tree`, and that every git call of the run saw `xdg=<unset> nosys=1` (the R11n
shim's env log).

**Red on pre-fix.** Two scratch-tree runs of `07-rules-gate`:
- `gate()` mutated to call `env` directly instead of through `e_git_env` (gated: one line changed, `bash -n`): `RESULT: 109 passed, 1 failed`, with `FAIL: R11h0 gate() leaked the inherited git env into the run (env seen by git: xdg=<scratch>/xdg-inherited nosys=<unset>|)`.
- the fixed parts under the same inherited `XDG_CONFIG_HOME` that broke base: `RESULT: 110 passed, 0 failed`.
- E-env, with the `keep_n`-only branch mutated to pass the env through unchanged (gated: differs, `bash -n`): `FAIL: E-env e_git_env wrong (got: <unset>|1 /leg|1 /inh|0 /leg|0)`. The third case leaked the inherited `/inh`.

**Honest limit.** `GIT_CONFIG_NOSYSTEM=1` is shown only by the env log, never by a planted system config.
The gate's `_ge_git` unsets `GIT_CONFIG_SYSTEM`, so a test cannot point the gate at a scratch system file,
and the machine's real `/etc/gitconfig` is never edited. `05-gate-eval.sh` and `06-gate-eval-tail.sh`
also run gate-eval with their own inline `env` (not through `gate()`). Those parts are outside this
group's lanes and are unchanged.

## Suite runs (post-fix)

| Run | `RESULT:` line | exit |
|---|---|---|
| `bash loomwright/scripts/test-automate-helpers-modules.sh` | `RESULT: 10 passed, 0 failed` | 0 |
| `bash loomwright/scripts/test-automate-helpers.sh 13-plan-waves` | `RESULT: 169 passed, 0 failed` | 0 |
| `bash loomwright/scripts/test-automate-helpers.sh 07-rules-gate` (before the E-env leg was added) | `RESULT: 110 passed, 0 failed` | 0 |
| `bash loomwright/scripts/test-automate-helpers.sh` (all parts, final tree) | `RESULT: 977 passed, 0 failed` | 0 |

Also green on the final tree: `test-no-fixed-sleep-race.sh`, `test-no-pipefail-grep-q.sh`,
`test-citation-drift.sh`, `scripts/check-vendor-coupling.sh`. The integrated `bash scripts/ci-local.sh`
run is the Supervisor's, after merge.
