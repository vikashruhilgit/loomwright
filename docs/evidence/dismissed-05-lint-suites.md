# Evidence — dismissed-followups 05, group D: lint / structure suites

Group D of the dismissed-followups 05 sweep (subtask 4): F246, F247, F249, F251, F256, F092, F169. Each finding
was re-verified on the worktree base `26eda742` before any edit, by reading the code, and for the ones the source
marks reproduced (F256, F092) by running it. The source finding text sits in a gitignored requirement file, so
this file is the committed record. Captured 2026-11-02 on macOS (bash 3.2, BSD awk) in the subtask-4 worktree.

"Red on pre-fix" below means the leg was run against the pin mutation from the brief's `## Pin mutations` table.
Each mutation was applied to a scratch copy of the tree (`mktemp -d` or the session scratch dir), gated on
non-empty, differs from the original, and `bash -n`. The legs named in a row went red and nothing else did.

## Dispositions

| Finding | Re-verified | Disposition | Leg / reason |
|---|---|---|---|
| F246 | present: the heading-coverage regex and the `^\|` row test matched column 0 only | fixed | `test-loop-inventory.sh` strips up to 3 leading spaces (`lead3`) before the heading, anchor and row tests. Legs: `AC2 (new heading indented 2 spaces)` (red), `an anchored heading indented 3 spaces stays covered, its anchor live` (green), `inventory row indented 2 spaces is parsed` (red), plus the boundary leg `exemption: a 4-space-indented ### line is code, not a heading`. Red on pre-fix: with `lead3` made a no-op, those three legs failed (50/53). |
| F247 | present: the base copy loop was `for f in "$PLUGIN"/scripts/*` with `[ -f ]`, top level only | fixed | The same copy loop now also walks `scripts/*.d/*`. Module bodies are copied; `test-*.d/*` parts become empty stand-ins like their runners. Legs: `fixture base copies scripts/<name>.d/ modules (…, body identical)` and `a script: cell naming scripts/<module> resolves in a scratch copy` (green). Red on pre-fix: with the loop reverted to top level only, both failed (51/53). |
| F249 | present: the documented limit of the indentation-blind toggle, unchanged | not worth fixing | The two fence readings disagree by design on the green real tree: 17 fence lines across 4 sources at base, including `agents/launch-pad.md`'s nested template. A disagreement warning would print on every green run and carry no signal. The DELIBERATE CHOICES header now says so. |
| F251 | present: no `expect_red` needle covered the three branches | fixed | New red legs: `shape-sources-extra` (`which is not a source of the group`), `gap-listed-twice` (`listed twice in the`), `inventory-missing` and `source-missing` (`missing or unreadable`; a scratch file deleted, gated on non-empty before and gone after). The header's FIXTURE LEGS list now names them. Red on pre-fix: with the four messages renamed in the checker's `bad(` lines only, exactly those four legs failed (49/53). |
| F256 | present, reproduced: the base run printed both `note: … no unedited baseline` lines, with no M-D2 or M-E ok line. Since the finding's snapshot `/dreaming` was edited too (fe7b78ce), so no live command is unedited | fixed | `e_baseline` picks, in each control's own order, the first command unedited since the split, in the live tree first and then in the split commit `2d500ab` (`SPLIT`: its 28 files match every split-time row of `move-only.txt`, checked). New leg M-E2 runs a scratch copy of the suite over the split-commit tree with `/setup` edited, and asserts M-E ran on a `/dreaming` part from the live tree with no note. The live run now prints the M-D2 and M-E ok lines and no note (36 passed, 0 failed; the base had 32). Red on pre-fix: the base suite printed both notes and no M-E ok line. A setup-only M-E (the brief's revert) turned M-E2 red, with the nested output showing the note. A wrong `SPLIT` pin fails closed (`… gives no unedited baseline`). Honest limit: CI checks out at depth 1, so there `SPLIT` is absent and the controls print the named note. A scratch run with no git history passed 31/0 with all four notes. `ci-local.sh` runs in a full local checkout, so there the controls run. |
| F092 | present, reproduced: the base `FSR_AWK`, evaluated by bash, printed `( sleep 2; kill $p ) &`, `{ sleep 1; touch x; } &` and the control `sleep 2; kill $p` | fixed | `FSR_AWK` gains `ungroup`: a `( … )` / `{ …; }` group closed on the same line and backgrounded (`&`, not `&&`) has its body blanked, so a sleep inside it is a holder. Controls `(F12)`: both group forms and a redirected group are not counted; a plain sleep, a foreground group, a group before `&&` and an `&>`-redirected group still are. BASELINE rows lowered in the same change: `scripts/test-ci-local.sh` (2, its two `( sleep 1; … ) &` writers), `test-classify-bot-review.sh` (1) and `test-pr-postmortem-gather.sh` (1). The last two are `( sleep "$secs"; … ) &` timeout watchdogs, so all three rows are removed at count 0. Red on pre-fix: with the `ungroup` call removed, the ratchet reported those three files as NEW and `(F12)` failed (27 passed, 2 failed). |
| F169 | present: the check F echo said Step 0 "reads" every skill split file (the header comment already said "names") | fixed (doc-only) | Echo reworded to `== F. commands/automate.md Step 0 names every skill split file, in order (AC5) ==`. The header comment notes it checks names, not reads. Check F's logic is unchanged. |

## Runs on the final tree

| Command | Result |
|---|---|
| `bash loomwright/scripts/test-loop-inventory.sh` | 53/53 passed (base: 43/43) |
| `bash loomwright/scripts/test-command-parts.sh` | 36 passed, 0 failed (base: 32) |
| `bash loomwright/scripts/test-no-fixed-sleep-race.sh` | 29 passed, 0 failed (base: 27) |
| `bash loomwright/scripts/test-automate-loop-split.sh` | 40 passed, 0 failed |
| `bash loomwright/scripts/test-no-pipefail-grep-q.sh` | 49 passed, 0 failed |
| `bash loomwright/scripts/test-rules-gate-seams.sh` | 26 passed, 0 failed |
