# Evidence: split test-automate-helpers.sh into a runner + sourced parts (automate-speed/21)

Base commit: `3a03dfa`. Branch: `feature/as21-split-automate-helpers-tests`.
All runs: macOS (bash 3.2 system shell, Homebrew bash on PATH), 2026-10-18/19, in the lane checkout
`automate-2026-10-15-163325/L17`. Base runs of `test-automate-helpers.sh` used the same checkout: the
first ran the unmodified file before any edit, the second ran `git show 3a03dfa:…` copied beside the
scripts (same siblings, same gitignored `.supervisor/`) and removed afterwards. Base consumer-gate
runs (§7) used a detached `git worktree` at `3a03dfa`.

The cut is mechanical. One script `sed -n 'a,bp'`s every part out of the base file and writes the runner
from base ranges plus the runner-only blocks. No leg was edited by hand.

## 1. Same result, same assertions (AC1)

| Run | `RESULT:` line | exit |
|---|---|---|
| Base (unmodified file, run 1) | `RESULT: 765 passed, 1 failed` | 1 |
| Base (copy of `3a03dfa`, run 2) | `RESULT: 765 passed, 1 failed` | 1 |
| Branch (runner before review) | `RESULT: 765 passed, 1 failed` | 1 |
| Branch (runner after review iteration 1) | `RESULT: 765 passed, 1 failed` | 1 |

The one failure on every run is the pre-existing, environment-dependent W19 leg (`W19 real
22-split-automate-engine-surfaces.md ## Touches parses`). It reads the gitignored queue under
`.supervisor/requirements/` and fails in this lane clone (`plan-waves: no …/.agent/companions.json`).
It is left alone (move-only, D6).

Multiset command, per run: `grep -E '^  (ok|FAIL): ' <out> | env LC_ALL=C sort`, then `diff`.

- Raw base run 1 vs raw base run 2: 4 differing lines. Raw base vs branch: 3 or 4 differing lines,
  depending on timing. Two runs of the SAME base file differ, so the raw diff is never empty. The
  differences fall into two volatile classes:
  - a `mktemp` name echoed inside a leg label (`…/tmp.929EmlGn20/…` vs `…/tmp.65kejLXNxz/…`, in W19,
    QG1e and R1);
  - a measured duration (`QG2j' it answered when the marker appeared (3s)` vs `(2s)`).
- With those two classes normalized
  (`sed -E 's#/tmp\.[A-Za-z0-9]{10}#/tmp.XXXXXXXXXX#g; s/marker appeared \([0-9]+s\)/marker appeared (Ns)/'`),
  every pair is identical, 766 lines each, and the `diff` output is empty:

```
normalized base vs base2: identical (766 lines)
normalized base vs branch: identical (766 lines)
normalized base vs branch2: identical (766 lines)
normalized base2 vs branch2: identical (766 lines)
normalized base vs branch (final runner): identical
normalized base (fresh copy, 2026-10-19) vs branch (review iteration 1 runner): identical (766 lines)
```

## 2. Move-only proof (AC2)

The runner adds four kinds of lines to base text:
1. five `# >>> runner-only` … `# <<< runner-only` blocks (71 lines with markers). They hold the header
   paragraph, the loader (with its list-agreement checks), the `if`/`fi` around the inline MERGE leg, and
   the subset-mode cleanup plus the sourced-vs-selected check;
2. 17 part-source lines of the form `tah_run <part> && . "$TAH_D/<part>.sh"`;
3. the one allowed hoist, base 3513–3517, at runner lines 308–312. It sits outside every runner-only
   block, and its first line occurs exactly once in the runner (`grep -nxF` → `308:`);
4. nothing else.

Runner size: 320 base lines (1–299, the hoist, the MERGE leg 1999–2011 and the tail 6214–6216) + 71
runner-only + 17 part-source = 408 lines.

Expansion script (`expand-runner.sh <scripts-dir>`). It fails if the hoist start occurs anywhere but once
outside the runner-only blocks:

```bash
#!/usr/bin/env bash
set -euo pipefail
S="$1"; R="$S/test-automate-helpers.sh"; D="$S/test-automate-helpers.d"
HOIST_FIRST='# The automate-loop skill and the AUTOMATE_RUN doc are split indexes (parallel-automate/22): the prose'
stripped="$(mktemp)"; hoist="$(mktemp)"
awk '/^# >>> runner-only$/ {skip=1; next} /^# <<< runner-only$/ {skip=0; next} !skip' "$R" > "$stripped"
hl="$(grep -nxF -- "$HOIST_FIRST" "$stripped" | cut -d: -f1)"
[ "$(printf '%s\n' "$hl" | grep -c .)" = 1 ] || { echo "hoist start found $(printf '%s\n' "$hl" | grep -c .) times (want exactly 1)" >&2; exit 1; }
sed -n "${hl},$((hl+4))p" "$stripped" > "$hoist"
lnum=0
while IFS= read -r line || [ -n "$line" ]; do
  lnum=$((lnum+1))
  [ "$lnum" -ge "$hl" ] && [ "$lnum" -le $((hl+4)) ] && continue
  case "$line" in
    'tah_run '*' && . "$TAH_D/'*'.sh"')
      p="${line#tah_run }"; p="${p%% *}"
      [ "$line" = "tah_run $p && . \"\$TAH_D/$p.sh\"" ] || { echo "malformed part-source line: $line" >&2; exit 1; }
      if [ "$p" = 09-brief-repair ]; then sed -n '1,3p' "$D/$p.sh"; cat "$hoist"; sed -n '4,$p' "$D/$p.sh"
      else cat "$D/$p.sh"; fi ;;
    *) printf '%s\n' "$line" ;;
  esac
done < "$stripped"
rm -f "$stripped" "$hoist"
```

The hoist goes back after line 3 of `09-brief-repair` (base 3510 + 3 = 3513). Command and output on the
final tree:

```
$ bash expand-runner.sh loomwright/scripts > expanded.sh
$ git show 3a03dfa:loomwright/scripts/test-automate-helpers.sh | cmp - expanded.sh && echo AC2_OK_IN_TREE
AC2_OK_IN_TREE
$ git show 3a03dfa:loomwright/scripts/test-automate-helpers.sh | diff - expanded.sh
$
```

## 3. Parts (AC3)

Each part is one contiguous base line range, numbered in base order. `09-brief-repair` is the exception:
its range minus the hoisted 3513–3517.

| Part | Exercises | Base lines | Lines |
|---|---|---|---|
| *(runner)* header + setup | — | 1–299 | 299 |
| `01-config` | config.sh (A, A7) | 300–519 | 220 |
| `02-runfile` | runfile.sh (B, B9, B10) | 520–1116 | 597 |
| `03-intake` | intake resolvers (C) | 1117–1333 | 217 |
| `04-resume` | resume (D) | 1334–1570 | 237 |
| `05-gate-eval-harness` | dispatcher gate-eval: section E harness (`reset_live`, `pass_ctx`, `gate`, `merges`, E-harness leg) | 1571–1693 | 123 |
| `05-gate-eval` | dispatcher gate-eval: E conditions up to the all-pass leg | 1694–1998 | 305 |
| *(runner, inline)* | E all-pass MERGE leg | 1999–2011 | 13 |
| `06-gate-eval-tail` | dispatcher gate-eval: TOCTOU, merge-fails, cond-6 mutation control | 2012–2085 | 74 |
| `07-rules-gate` | dispatcher gate-eval cond 7 (R) | 2086–2839 | 754 |
| `08-learning-emit` | learning (F) | 2840–3509 | 670 |
| *(runner setup, hoisted)* | G's split-index lines | 3513–3517 | 5 |
| `09-brief-repair` | learning brief-repair (G) | 3510–3512, 3518–3778 | 264 |
| `10-reconcile-status` | reconcile-status (H) | 3779–4478 | 700 |
| `11-ceiling` | runfile.sh `ceiling-check` (I1–I7) | 4479–4610 | 132 |
| `12-meta` | meta (branch mode) | 4611–4761 | 151 |
| `13-plan-waves` | plan-waves (W, X) | 4762–5428 | 667 |
| `14-escalation` | escalation (ESC) | 5429–5826 | 398 |
| `15-lane-seams` | dispatcher lane seams (LANE, SINGLELANE, LANEGUARD) | 5827–5972 | 146 |
| `16-queue-gates` | queue gates (QG1–QG4) | 5973–6213 | 241 |
| *(runner)* summary | — | 6214–6216 | 3 |

Largest part: `07-rules-gate`, 754 lines (limit 800). The runner is 408 lines, above the problem
statement's "~350". The floor is the 320 base lines the brief keeps in the runner (the 202-line header,
the setup, the hoist, the inline MERGE leg and the summary); the other 88 are the loader and its checks.

## 4. Loader behavior (AC4, AC5)

Every case below ran from one script, `loader-cases.sh <repo> <workdir>`, on a fresh scratch copy of
`loomwright/` per case (`HOME` relocated). "Probe parts" means every part replaced by one line,
`ok "probe <name> argc=$#"`. Output is the runner's `FAIL` / `ok: probe` / `==` / `RESULT` lines.

| Case | Output | exit |
|---|---|---|
| `09-brief-repair.sh` moved away, no args | `  FAIL: missing test part: test-automate-helpers.d/09-brief-repair.sh` (the only line; no leg ran) | 1 |
| `12-meta.sh` mode 000, `12-meta` | `  FAIL: missing test part: test-automate-helpers.d/12-meta.sh` | 1 |
| `99-nope` | `  FAIL: unknown test part: 99-nope (known: …)` | 1 |
| `"01-config 02-runfile"` (one argument) | `  FAIL: unknown test part: 01-config 02-runfile (known: …)` | 1 |
| `""` | `  FAIL: unknown test part:  (known: …)` | 1 |
| `01-config.sh` | `  FAIL: unknown test part: 01-config.sh (known: …)` | 1 |
| an unparseable `03-intake.sh` (line 11 deleted, leaving an empty `then`), `03-intake` | `  FAIL: test part does not parse (bash -n): test-automate-helpers.d/03-intake.sh` | 1 |
| `01-config.sh` gains `echo a \|& cat` (bash 4+ syntax); runner run as `/bin/bash` 3.2 with bash 5.3 first on `PATH`, `01-config` | `  FAIL: test part does not parse (bash -n): test-automate-helpers.d/01-config.sh` | 1 |
| reviewer repro: probe parts + `17-probe.sh` (one `no` leg) + a `tah_run 17-probe && . …` line, not in `TAH_PARTS`, no args | `  FAIL: test part not in TAH_PARTS: test-automate-helpers.d/17-probe.sh` (before any leg) | 1 |
| probe parts + the `tah_run 17-probe` line only (no file), `01-config` | `ok: probe 01-config argc=0`, then `  FAIL: part not in TAH_PARTS: 17-probe` | 1 |
| probe parts + `17-probe` in `TAH_PARTS` and a file, but no source line, `17-probe` | `  FAIL: parts sourced ( ) differ from parts selected ( 17-probe ): …` | 1 |
| probe parts + a second `tah_run 01-config` line, `01-config` | `ok: probe 01-config argc=0`, then `  FAIL: part has more than one source line: 01-config` | 1 |
| probe parts, the `12-meta` source line moved below `13-plan-waves`, `12-meta 13-plan-waves` | both probes, then `  FAIL: parts sourced ( 13-plan-waves 12-meta ) differ from parts selected ( 12-meta 13-plan-waves ): …` | 1 |
| probe parts, `tah_prereq` names `05-gate-eval-harnes`, `11-ceiling` | `  FAIL: prerequisite of 05-gate-eval not in TAH_PARTS: 05-gate-eval-harnes` (before any leg) | 1 |
| probe parts, `16-queue-gates 01-config 01-config` | 01-config then 16-queue-gates, each once, `argc=0`; `RESULT: 2 passed, 0 failed` | 0 |
| probe parts, `07-rules-gate 05-gate-eval-harness` | the harness once, then 07; `RESULT: 2 passed, 0 failed` | 0 |
| probe parts, `06-gate-eval-tail` | the harness pulled in, then 06; `RESULT: 2 passed, 0 failed` | 0 |

Every selected part is checked (present, readable, `-n`) before any part is sourced, and checked again
at its source line. The `-n` check runs under `$BASH`, the interpreter that will source the part, not
the first `bash` on `PATH` (review iteration 1: before that, the bash-4-syntax case above passed the
guard, failed at `.`, and ended green). The `-n` check is not in the trail precedent. It was added after
AC8's first mutation: without it, an unparseable part made `.` fail, all of that part's legs were
skipped, and the run printed `RESULT: 0 passed, 0 failed` with exit 0. The one-file base could not do
that, because there a syntax error ends the script.

The part list is stated four ways: `TAH_PARTS`, the `tah_prereq` map, the files in
`test-automate-helpers.d/`, and the 17 source lines. Review iteration 1 added a check for each against
`TAH_PARTS`: every prerequisite and every `*.sh` file in the directory must be named in it (checked at
start, before any leg); `tah_run` refuses a name not in it and a second source line for the same name;
and before `RESULT:` the sourced list (`tah_done`, appended only when a part is actually sourced) must
equal the selected list in `TAH_PARTS` order (`tah_list`). That catches a `TAH_PARTS` entry with no
source line and source lines out of order. Before this, the reviewer's repro (a `17-probe` part with
only a failing `no` leg, sourced but not listed) gave `RESULT: 18 passed, 0 failed`, exit 0. Names are
compared exactly, not by substring: a first draft used `case " $TAH_PARTS " in *" $1 "*`, which accepted
the one-argument `"01-config 02-runfile"`; the scratch run above caught it before commit. The directory
check reads the directory with a glob only to compare names; parts are still sourced by name (AC4).

Each part run alone (`bash loomwright/scripts/test-automate-helpers.sh <part>`, re-run on the review
iteration 1 runner, same totals as before):

| Part | Parts run (prerequisites included) | Result | exit |
|---|---|---|---|
| `01-config` | 01-config | 18 passed, 0 failed | 0 |
| `02-runfile` | 02-runfile | 74 passed, 0 failed | 0 |
| `03-intake` | 03-intake | 19 passed, 0 failed | 0 |
| `04-resume` | 04-resume | 33 passed, 0 failed | 0 |
| `05-gate-eval-harness` | 05-gate-eval-harness | 1 passed, 0 failed | 0 |
| `05-gate-eval` | 05-gate-eval-harness 05-gate-eval (+ inline MERGE leg) | 47 passed, 0 failed | 0 |
| `06-gate-eval-tail` | 05-gate-eval-harness 06-gate-eval-tail | 5 passed, 0 failed | 0 |
| `07-rules-gate` | 05-gate-eval-harness 07-rules-gate | 102 passed, 0 failed | 0 |
| `08-learning-emit` | 08-learning-emit | 28 passed, 0 failed | 0 |
| `09-brief-repair` | 09-brief-repair | 32 passed, 0 failed | 0 |
| `10-reconcile-status` | 10-reconcile-status | 56 passed, 0 failed | 0 |
| `11-ceiling` | 11-ceiling | 7 passed, 0 failed | 0 |
| `12-meta` | 12-meta | 32 passed, 0 failed | 0 |
| `13-plan-waves` | 13-plan-waves | 171 passed, 1 failed (W19, pre-existing) | 1 |
| `14-escalation` | 14-escalation | 62 passed, 0 failed | 0 |
| `15-lane-seams` | 15-lane-seams | 26 passed, 0 failed | 0 |
| `16-queue-gates` | 16-queue-gates | 55 passed, 0 failed | 0 |

No count-sum rule applies. As a consistency check only: subtracting the harness's one leg from each of
its three dependents gives 766 = 765 + 1, the full suite. No part log shows `unbound variable`,
`command not found` or `No such file` (0 occurrences, as in base). No dependency beyond the harness
showed up, so the prerequisite map has one entry.

## 5. Merge-command invariant grep (AC6)

`grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not " | cut -d: -f1 | env LC_ALL=C sort -u`,
identical on base and branch (`diff` empty):

```
loomwright/commands/agent-help.md
loomwright/docs/loop-inventory/automate-loop.md
loomwright/scripts/automate-helpers.sh
loomwright/scripts/fixtures/automate-golden/drain-superseded-by-merge/tree/dot-supervisor/requirements/automate-followups/11-post-park-lifecycle.md
loomwright/scripts/result_block_parser.py
loomwright/scripts/test-automate-helpers.sh
loomwright/skills/automate-loop/modes-and-merge-gate.md
loomwright/skills/automate-loop/per-item-loop.md
```

The test's three hits (header line 61, MERGE-leg comment, MERGE-leg `ok`) stay in the runner. No part
matches. `git diff 3a03dfa -- CLAUDE.md loomwright/skills/automate-loop/invariants.md` is empty.
`test-automate-next-step.sh` passes (§7).

## 6. Mutation control (AC8)

Scratch copy of `loomwright/`. Deleted line 135 of `test-automate-helpers.d/03-intake.sh`:
`[ "$RUN_OUT" = "$DPROP/05-ready.md" ] && ok "resolve-folder: a drafted proposed/…-0a1b2c3d.md is NOT listed" || no "…"`.

| Invocation (scratch runner) | Unmutated | Mutated |
|---|---|---|
| `bash test-automate-helpers.sh 03-intake` | 19 passed, 0 failed | 18 passed, 0 failed |
| `bash test-automate-helpers.sh` (full) | 740 passed, 1 failed | 739 passed, 1 failed |

The normalized multisets of the two full runs differ by exactly that one `ok:` line. The scratch copy
is not a git work tree and has no root `scripts/` or `.supervisor/`, so its full total is not 765: W19
skips there, and W20 fails (`parsed FILES set (or PLUGIN_JSON) is empty`) on both sides alike. Only
the unmutated-vs-mutated comparison in the same scratch environment matters.

## 7. Consumer gates (AC7)

| Gate | Base `3a03dfa` | Branch | Note |
|---|---|---|---|
| `test-automate-helpers-dispatch.sh` | 45 passed, 0 failed | 45 passed, 0 failed | |
| `test-automate-golden.sh` | PASS 64 FAIL 0 | PASS 64 FAIL 0 | |
| `test-automate-loop-split.sh` | 40 passed, 0 failed | 40 passed, 0 failed (also after review iteration 1) | §H `wiring()` finds `assemble.sh` in the runner (the hoist), scans the parts |
| `test-automate-next-step.sh` | PASS 141 FAIL 0 | PASS 141 FAIL 0 | `SURFACE_BASE` unchanged |
| `test-no-pipefail-grep-q.sh` | 27 passed, 0 failed | 27 passed, 0 failed | parts scanned through `test-*.d/*.sh` |
| `test-no-fixed-sleep-race.sh` | 27 passed, 0 failed | 27 passed, 0 failed | no baseline row needed (no fixed sleep in this test) |
| `test-loop-inventory.sh` | 43/43 passed | 43/43 passed | `script:test-automate-helpers.sh` cells need only the file |
| `test-citation-drift.sh` | 26 passed, 0 failed | 26 passed, 0 failed | no pinned citation of this file exists |
| `scripts/check-test-hermetic.sh` | OK, 177/177 | OK, 177/177 | parts are not standalone tests |
| `scripts/check-vendor-coupling.sh` | OK, 0 breaches, 2675 refs | OK, 0 breaches, 2675 refs | see below |
| `scripts/check-locale-prefix.sh` | OK, 404/404 files | OK, 421/421 files | +17 = the new parts |
| `scripts/check-version-bump.sh` | OK, 0 fragments | OK, 1 fragment | +1 = this item's fragment (no bump, lane rule) |

Vendor coupling, move-only. The test's 3 measured references (`install_root` ×3, allowance 3) now sit
in `05-gate-eval-harness.sh` (1) and `05-gate-eval.sh` (2), and the runner measures 0. As in the
automate-speed/19 precedent, the runner's key and its reason are removed. Each receiving part gets a
count entry and the reason `moved by automate-speed/21 split — no reference added`. Allowance sum
2712 on base and branch; reference total 2675 on both.

AC9: `git diff --stat 3a03dfa` lists only the runner, the 17 parts, `vendor-coupling-manifest.json`,
the changelog fragment and this file. `automate-helpers.sh` and every `automate-helpers.d/*.sh` are
unchanged.

After review iteration 1, these were re-run on the branch with the same results as in the table:
`test-automate-loop-split.sh`, `test-no-pipefail-grep-q.sh`, `check-locale-prefix.sh` (421/421),
`check-test-hermetic.sh` (177/177), `check-version-bump.sh` (1 fragment) and `check-vendor-coupling.sh`.
The `ci-local` row below is from before review iteration 1.

### `bash scripts/ci-local.sh`

| Tree | Result |
|---|---|
| Branch (staged tree, final runner) | FAIL after 1265s: 23 ci.yml gates + 168 self-tests. Early phase 16/16 green. Pool: 174 of 175 passed. The one red entry is `test-automate-helpers.sh` at `RESULT: 765 passed, 1 failed`, the pre-existing W19 leg (§1) |
| Base `3a03dfa` | not run through `ci-local` (one more ~20-minute pool). The same `test-automate-helpers.sh` exits 1 with W19 on base in this checkout (§1), so base's pool has the same red entry |

W19 reads the gitignored `.supervisor/requirements/` queue. That queue is present in this lane clone and
absent on a CI runner, where the leg skips (header of the test, section W). ci-local's `sdk-spike` step
is not run locally; CI runs it.

## 8. Known limits

- The loader branches (missing, unreadable, unparseable, wrong-interpreter parse, unknown, the four
  list-agreement checks, subset selection) are proven by the recorded scratch runs in §4, not by a
  committed CI leg. AC9 forbids a new file and AC1 fixes the `RESULT:` count, so the follow-up is a
  separate `test-automate-helpers-modules.sh` (automate-speed/19 precedent).
- Prose pointers elsewhere name `test-automate-helpers.sh §X7` / `section R` / `ESC` (for example in
  `automate-helpers.d/plan-waves.sh` and `automate-dismissed.sh`). They remain true, because running
  the runner runs those sections. They are not re-pointed to the parts: AC9 freezes the helper files,
  and the section letters stay in the runner header.
