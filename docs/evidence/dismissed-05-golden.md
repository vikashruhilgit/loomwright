# Evidence: dismissed-followups 05, group A (golden suite, F281–F288)

Suite: `loomwright/scripts/test-automate-golden.sh`. Fixtures: `loomwright/scripts/fixtures/automate-golden/`.
Base commit: `26eda742b616a339f971b34b5b7d8740c9654851`. Every finding was re-checked on that base (by
grep, by reading the code, or by a scratch-dir probe) before anything changed. Every red-on-pre-fix
run below used a scratch COPY of `loomwright/` with exactly one mutation applied (an exact-string
replacement whose anchor had to occur once; the mutant had to differ from the original and pass
`bash -n`), then ran the whole suite with its mutation legs. Runs used bash 5.3.20 and BSD grep
2.6.0 on macOS.

## Dispositions

| Finding | Re-verified on base | Disposition | Leg / reason |
|---|---|---|---|
| F281 | present: M1–M3 build a bundle, mutate it and expect red; no leg ran the unmutated bundle through `inner` | fixed | **M0**: a freshly built bundle, NOT mutated, runs the three M1–M3 cases and must exit 0 with each case ok. While M0 is not green, M1–M3 report `not judged` (FAIL). Red on pre-fix: the brief's mutation (M0's bundle mutated with M1's anchor before its run) ⇒ `FAIL: M0: unmutated control exit 1 …` and `FAIL: M1/M2/M3: not judged — the M0 unmutated control is not green` |
| F282 | present: `check_scrub` greps `/Users/\|/home/` only; the three copied done briefs carried `- **Project:** ~/Documents/work/AI/ai-agent-manager` (grep: 3 hits, no other `~/` under the fixtures) | fixed | `check_scrub` now also matches `~/` (widened, never narrowed). The three Project lines now read `ai-agent-manager`. No `expected.md` / `expected.out` echoes the line (grep: 0 hits), so no expected file changed. **M6b**: a fixtures copy whose done brief gets a `~/Documents/x` Project line ⇒ `FAIL: home path in <that brief>`. Red on pre-fix: `~/` removed from the grep ⇒ `FAIL: M6b: inner run exit 0, wanted non-zero naming 'FAIL: home path in …'` |
| F283 | present: the header said both sides are normalised (ISO timestamp → `<TS>`) but named no limit | fixed (doc-only) | header HONEST LIMIT line: `<TS>` hides WHICH timestamp a helper wrote, so a wrong but well-formed value still matches and no leg pins a timestamp's value or order |
| F284 | present, and wider than the finding says: the repo's own `.gitignore` lists `.DS_Store`, `*.swp`, `*.swo` and `*~`, so a stray copy under the fixtures makes `check_ignored` red in a dev checkout even without a global excludes file | fixed | `check_ignored` skips `.DS_Store`, `*.swp`, `*.swo` and `*~` before `git check-ignore`. **M9b**: the M9 scratch repo plus an ignored `.DS_Store` and `*.swp` ⇒ the real ignored fixture is still named and the junk is not. Red on pre-fix: the junk-name skip removed ⇒ `FAIL: M9b: ignored editor/OS junk was reported as a fixture` (`ignored fixture .DS_Store`, `ignored fixture run-record-pr/.steps.swp`) |
| F285 | present: `stage_tree` uses `find -depth -name 'dot-?*'` with no `-type d`, so a `dot-<x>` FILE is renamed too; no fixture holds such a file today | fixed (doc-only) | the header comment now says files map too, ON PURPOSE: a case that needs e.g. a `.gitignore` stores it as `dot-gitignore`, because a real `.gitignore` under `tree/` would act on this repo's own ignore rules. The `stage_tree` comment points to it. No `-type d` added |
| F286 | present: no leg used a four-backtick fence (grep for four backticks in the suite: 0 hits) | fixed | **M7b**: a prose copy gets a four-backtick fence holding a three-backtick line and `### Inside long fence`, then `### After long fence` ⇒ `unmapped unit …After long fence`, and `Inside long fence` must not appear at all. Red on pre-fix (the brief's mutation: close on any three-backtick line whatever the opening length): `FAIL: M7b: the heading inside the four-backtick fence was read as a unit` |
| F287 | present in the code, but NOT reachable through a NUL: `drop_sigpipe_noise` read its input with `"$(cat)"`, and command substitution drops a NUL before `grep` sees it (probe: `printf 'a\0b\nafter1\nafter2\n'` came out as `ab`, `after1`, `after2`, and bash 5.3 printed `ignored null byte`). A raw `grep -vE` on the same bytes printed only `Binary file (standard input) matches` (BSD grep), so the latent loss was real. GNU grep's other binary trigger, an invalid multibyte byte in a UTF-8 locale, could reach `grep` | fixed | the filter now writes its input to a temp file (NUL bytes kept) and runs `env LC_ALL=C grep -a -vE`, keeping a missing final newline missing. **M10f**: input with a NUL, the noise line and no final newline ⇒ output equals the input minus that line, byte for byte, with nothing on stderr. Red on pre-fix: the base filter drops the NUL and warns (probe above), so the byte compare fails. Red on the brief's mutation (drop `-a`): `FAIL: M10f: noise filter output differs …`; the output was BSD grep's `Binary file <tmp> matches`, in place of every line |
| F288 | present: `SIGPIPE_NOISE_RE='^! .*: line [0-9]+: printf: write error: Broken pipe$'` matched the line from ANY script | fixed | anchored: `^! (.*/)?automate-lanes(\.d/[^/:]+)?\.sh: line [0-9]+: printf: write error: Broken pipe$`. The `.d/<part>` form is required, not optional: bash names the file that DEFINES the printing function (probed under bash 3.2 and 5.3), and `_lanes_validation_rows` now lives in `automate-lanes.d/readiness.sh`. **M10a2**: the line naming `automate-lanes.d/readiness.sh` is dropped (green). **M10e**: the same line naming `automate-helpers.sh` is compared (`step output differs`, red). Red on pre-fix (restore the old regex): `FAIL: M10e: inner run exit 1, wanted non-zero naming 'FAIL: gate-validation-waive: step output differs'`. The old regex drops the line, so the case compares equal, and only the scrub's `sigpipe noise pinned` fires |

## Found while verifying: a crashed filter compared as a match

On the first post-fix run, M10b came back green. The inner run's log showed why: both
`norm … | drop_sigpipe_noise > …` pipelines died with `Segmentation fault: 11` in the pipeline
subshell. That left `a.out` and `x.out` empty, `cmp` found them equal, and the case passed. A later run
crashed the same way three times inside M0's inner run.

- **Cause: my first F287 fix.** It wrote the filter's grep as a temporary prefix, `LC_ALL=C grep …`.
  Every one of the 25 macOS crash reports from these runs (`~/Library/Logs/DiagnosticReports/bash-*.ips`,
  Homebrew bash 5.3) carries the stack `reset_locale_vars → libintl_setlocale →
  CFLocaleCopyPreferredLanguages → … → _os_log_preferences_refresh`, and the first is from the first
  post-change run. The base run before it produced none. This is the documented pitfall
  (`loomwright/docs/PITFALLS.md`: bash restores its locale after the prefixed command, and
  CoreFoundation is not fork-safe). `scripts/check-locale-prefix.sh`, the CI gate for it, flags that
  line (checked by putting the prefix form back briefly). Short loops of either form did not
  reproduce the crash (1500 sequential calls; 4 × 400 in parallel), so the gate, not a stress loop, is
  the guard. The filter now uses `env LC_ALL=C grep`, and the gate passes.
- **The false green was real, and older than this change:** `run_case` never checked the filter
  pipeline's status. A filter that dies, for any reason, leaves both sides empty and equal. That is
  the "fail-safe reader read as clean" shape the PITFALLS entry warns about. Fix: `run_case` reports
  `FAIL: <case>: step-output filter failed — output not compared` when either filter pipeline exits
  non-zero, and `drop_sigpipe_noise` returns non-zero on a `grep` error (exit > 1; exit 1 still means
  every line was dropped). The crashed run above shows it working: three `step-output filter failed`
  FAILs, no false green.
- **M10g**: a suite copy whose filter exits 139 at once (a crash's exit) ⇒ the case goes red with
  that message. Red on pre-fix (the status check reverted to the base's two plain pipelines):
  `FAIL: M10g: inner run exit 0, wanted non-zero naming 'FAIL: gate-validation-waive: step-output filter failed'`

## Runs

- Base: `PASS: 65 FAIL: 0`.
- After the change (`env LC_ALL=C` form): `PASS: 73 FAIL: 0` (base 65, plus M0, M6b, M7b, M9b, M10a2,
  M10e, M10f, M10g), with no `Segmentation fault` in the log. The drop-`-a` mutation was run again on
  this form and M10f still goes red.
- `loomwright/scripts/test-automate-next-step.sh` (it reads the same fixtures; run after the Project-line
  edit): `PASS: 195 FAIL: 0`.
- `scripts/check-locale-prefix.sh`, `loomwright/scripts/test-citation-drift.sh`,
  `test-no-fixed-sleep-race.sh`, `test-no-pipefail-grep-q.sh` and `test-automate-loop-split.sh`
  (which names this suite): all pass.
