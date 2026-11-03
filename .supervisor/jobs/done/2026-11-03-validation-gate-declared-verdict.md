# Supervisor Job: Validation gate accepts committed evidence with a declared verdict

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-11-03-125828/L1
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/2026-11-03-064334-validation-gate-accepts-committed-evidence-with-a-declared-verdict.md
- **Base commit:** 18f857b8816f4ce5d2e5aaef84fe8683249c6263

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash 3.2 + awk + jq + `gh`, the stack `readiness.sh` already uses |
| 2 | Dependency Availability | GO | Every `gh` call shape the design needs was run read-only against PR #802: `gh pr view 802 --json headRefOid,files` (30 files, 2 under `docs/evidence/`), `gh api repos/vikashruhilgit/loomwright/contents/docs/evidence?ref=<head>` (directory listing), `gh api -H 'Accept: application/vnd.github.raw' repos/…/contents/docs/evidence/<f>.md?ref=<head>` (raw file text) |
| 3 | Architecture Fit | GO | Extends the one shared Validation reader (`_lanes_validation_rows`), so `validation-gate` and `lane-readiness` keep one parser |
| 4 | Scope vs Supervisor Capability | CAUTION | About 28 files (24 modify + 4 create) across code, tests, golden fixtures and doc surfaces: over the `context-bound` bound, so two subtasks with no file overlap |
| 5 | Hard Blockers | GO | None |

**Overall Verdict:** CAUTION

## Task
**Goal:** `validation-gate` and `lane-readiness` accept a committed `docs/evidence/*.md` file that the PR adds or changes as evidence for a `## Validation` step. The file counts only when it declares the step and its result on a `Verdict:` line and holds fenced output. The authoring surfaces teach that line, and the gate's remedy points at the evidence file, never at the PR body.

**Problem Statement:**
The plugin owner needs a Running system Validation step whose evidence sits in a committed file to park READY without a waiver, because a waiver should mean "not run".
Currently the evidence rule (#511) puts evidence in committed `docs/evidence/` files, but the validation gate reads only the PR body. So every Running system step written to the rule parks `validation_unrun`, and the owner waives evidence that exists. Run `automate-2026-11-02-173506` (PR #802) parked this way on V3 and V4. The requirement measured why reusing the PR-body passage reader on the files does not work: the heading anchor, the `(V4)` form, and expected `FAIL` output in a fixture.
Success looks like this: an item whose evidence file declares `Verdict: PASS for Validation <n>` and holds fenced output reads `validation-gate: ok`, naming that file, with no `--waive`.

**Declared verdict line (the contract, fixed by this brief):**
- Form: a whole line at column 0, outside any ``` / ~~~ fence: `Verdict: <PASS|FAIL|NOT-RUN> for Validation <n>` (trailing whitespace allowed). One line per step. A file may carry several lines for different steps.
- A `Verdict:` line inside a fence is output, never a declaration. A line that starts `Verdict:` but does not match the form declares nothing.
- The gate never infers the step or the result from headings or from words inside the output.

**Read order (fixed by this brief):** the PR-body reader runs first, exactly as today. A body result of PASS or FAIL is final. Only a step the body leaves NOT-RUN (including an unreadable body) consults evidence files. Then the candidate files are the `docs/evidence/*.md` paths at the PR head that are also in the PR's changed-file list. If several candidates declare the same step, the worst declared result wins (FAIL over NOT-RUN over PASS), naming its file.

## Acceptance Criteria

**Happy Path:**
- [ ] AC1: Given a Running system step, when a `docs/evidence/` file the PR adds or changes declares `Verdict: PASS for Validation <n>` for that step and holds fenced output, then `validation-gate` reads the step as evidenced. The `ok` line names the file, for example `validation-gate: ok — 1 running-system step(s) evidenced (V4 in docs/evidence/x.md)`. An `ok` with no file-evidenced step prints exactly today's line.
- [ ] AC2: Given that file's fenced output contains the word `FAIL` (expected output of a failing fixture), when its declared verdict is a pass, then the step still reads as evidenced.
- [ ] AC3: Given a step already evidenced by output pasted in the PR body, when the gate runs, then the result is byte-identical to today, and the file path makes no extra `gh` call.
- [ ] AC4: Given `lane-readiness`, when it reports the validation check for the same PR, then each step's result and evidence source match `validation-gate`'s. Both read the one shared reader, `_lanes_validation_rows`.

**Edge Cases:**
- [ ] AC5: Given an evidence file that declares a passing verdict but that the PR does not add or change, when the gate runs, then the file is not used.
- [ ] AC6: Given an evidence file with no declared verdict line (such as PR #802's), when the gate runs, then the file evidences no step, and the gate's line names the file as having no declared verdict.
- [ ] AC7: Given a file declaring a verdict for one step, when the item has two Running system steps, then only the declared step is evidenced.
- [ ] AC8: Given a declared verdict that is not a pass, when the gate runs, then the step reads FAIL (declared `FAIL`) or NOT-RUN (declared `NOT-RUN`), naming the file.
- [ ] AC9: Given a declared `PASS` in a file with no fenced output, when the gate runs, then the step reads NOT-RUN with the reason `declared but no output`, naming the file.

**Error Scenarios:**
- [ ] AC10: Given the PR's changed-file list, the evidence directory listing, or an evidence file cannot be read (a `gh` failure, a PR value that is not a `https://github.com/<owner>/<repo>/pull/<n>` URL, or no PR), when the gate runs, then the step reads NOT-RUN with the reason. The gate fails closed (unreadable never counts as evidence), still prints exactly one line and exits 0.
- [ ] AC11: Given a step that is not evidenced after both the body and the files are read, when the gate prints `unrun`, then the remedy says to add the declared verdict line and the fenced output to the step's `docs/evidence/` file, and never says to paste into the PR body. This applies to the `unrun` line's evidence text, the `validation_unrun` bullet in `skills/automate-loop/modes-and-merge-gate.md`, and the RECONCILE re-check paragraph in `skills/automate-loop/per-item-loop.md`.

**Authoring surfaces:**
- [ ] AC12: Given the Evidence rule in `skills/supervisor-readiness/SKILL.md` (under the template's `## Acceptance Criteria`) and the item rule plus the Story Template's Running system entry in `skills/user-story-writing/SKILL.md`, when an author reads them, then they say a Running system step's output goes in the step's committed `docs/evidence/<slug>.md` with the declared line `Verdict: PASS for Validation <n>`. `user-story-writing` no longer says that output is pasted into the PR body. `test-pr-body-evidence-seam.sh` and `test-requirement-shape.sh` pin the new text.
- [ ] AC13: Given the gate's other descriptions (`docs/result-schemas/automate-run.md`'s `validation_unrun` row, `docs/rationale/automate-loop.md`'s gate paragraph, `automate-helpers.sh`'s `validation-gate` usage comment, and the header comments of `readiness.sh` and the new module), when the change lands, then each names the evidence-file path beside the PR body. Nothing still says the gate reads only the PR body.

**Mutation controls and release:**
- [ ] AC14: Given `bash loomwright/scripts/test-automate-lanes.sh`, when it runs, then every AC1–AC11 behavior has a leg with a stubbed `gh`. Each Pin mutations row below turns its pin red when applied, including the three the requirement names: the file read removed, the "PR changes the file" filter removed, and the FAIL-in-output exemption removed.
- [ ] AC15: Given the branch, when `bash scripts/check-version-bump.sh` runs, then it passes (a `changelog.d/validation-gate-declared-verdict.md` fragment, folded by `bash scripts/bump-version.sh`), and `bash scripts/ci-local.sh --affected` is green.
- [ ] AC16: Given this item's Validation 4, then a committed evidence file `docs/evidence/validation-gate-declared-verdict.md` contains the line `Verdict: PASS for Validation 4` at column 0 outside any fence, plus the fenced output of the new gate reading that file. The PR body links to the file. Once the PR exists, the gate on this item's PR prints `validation-gate: ok` naming that file, with no `--waive` in the run file's `## Progress`.

**Evidence rule (Launch Pad Phase 2 action 3; Plan Reviewer Criterion 20):** a criterion's evidence lives in the diff, never only in the PR body. AC16's evidence is the committed `docs/evidence/validation-gate-declared-verdict.md`, a File Impact Map create, listed in FINALIZE's `## Evidence` section.

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------------------------|-----------------|------------|
| gate code | `loomwright/scripts/automate-lanes.d/readiness.sh` (506: call sites only. `_lanes_validation_rows` gains an optional 5th arg `<evdir>` and calls the new module for a body NOT-RUN row; `lanes_readiness` and `lanes_validation_gate` pass an evdir; the `ok` line names file-evidenced steps; header comments updated. The new responsibility lives in the CREATE module, not here) · `loomwright/scripts/automate-lanes.sh` (416: one `_lanes_source evidence` block before readiness, plus the header module map) · `loomwright/scripts/automate-helpers.sh` (1170: the `validation-gate` `#:` usage line only, which `--help` prints) · `loomwright/scripts/fixtures/automate-helpers-help/hdr-lanes.golden` (25: its line 16 mirrors that usage line byte-for-byte; update it in the same change) | `loomwright/scripts/automate-lanes.d/evidence.sh`: the home for the evidence-file reader (list, filter, read, parse `Verdict:` lines, per-step lookup) | HIGH |
| gate tests | `loomwright/scripts/test-automate-lanes.sh` (260: one `tal_part 07-evidence-files` line) · `loomwright/scripts/test-automate-lanes.d/05-timeline-and-gate.sh` (622: changed pins only. Its exact `unrun` strings gain the evidence-file reason; no new legs go here) · `loomwright/scripts/test-automate-lanes-modules.sh` (313: `MODS_WANT` gains `evidence`) | `loomwright/scripts/test-automate-lanes.d/07-evidence-files.sh`: the home for every new leg (AC1–AC11, AC14) with its own `gh` stub | HIGH |
| golden fixtures | `loomwright/scripts/fixtures/automate-golden/gate-validation-waive/{gh.stub,expected.out,expected.md}` and `loomwright/scripts/fixtures/automate-golden/gate-validation-gate-unrun-escalated/{gh.stub,expected.out,expected.md}` (small data files: their `unrun` lines come from body NOT-RUN rows, so they now carry the file reason. Add `gh.stub` rules for the new calls or update the expected text, whichever `bash loomwright/scripts/test-automate-golden.sh` shows) | — | MEDIUM |
| evidence + release | — | `docs/evidence/validation-gate-declared-verdict.md` (AC16) · `changelog.d/validation-gate-declared-verdict.md` (folded by the bump) | HIGH |
| authoring + doc surfaces | `loomwright/skills/supervisor-readiness/SKILL.md` (556: one sentence appended to the Evidence rule, the single authority for it) · `loomwright/skills/user-story-writing/SKILL.md` (334) · `loomwright/skills/automate-loop/modes-and-merge-gate.md` (59) · `loomwright/skills/automate-loop/per-item-loop.md` (104) · `loomwright/docs/result-schemas/automate-run.md` (158) · `loomwright/docs/rationale/automate-loop.md` (215) | — | HIGH |
| authoring pin tests | `loomwright/scripts/test-pr-body-evidence-seam.sh` (296) · `loomwright/scripts/test-requirement-shape.sh` (255) | — | HIGH |

> **Validator-owned surfaces:** `check-token-budget.sh` measures the `supervisor-readiness` (492 tokens of headroom at base), `user-story-writing` (519) and `automate-loop` (1141) skill dirs. If an edit goes over, raise that skill's entry in `loomwright/docs/prompt-token-budgets.json` (measured + ~10%) and its mirror row in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets". `check-prompt-history-refs.sh` scans the skill files, so add no PR or issue numbers to them. `check-doc-currency.sh` scans the doc surface (Executable Acceptance above). `test-automate-golden.sh` replays the golden fixtures in the map.

**Total estimated files:** 24 modify (16 in Subtask 1, 8 in Subtask 2, plus the two token-budget files only if a budget is exceeded) + 4 create.

## Touched-file invariants

> Grounded at base `18f857b8816f4ce5d2e5aaef84fe8683249c6263`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-lanes.d/readiness.sh`**
  - keep: the gate's read-only contract `Read-only form — fails CLOSED, prints EXACTLY one line, always exits 0 (stdout IS the verdict)`. Keep the pre-check that reads no PR, `rows="$(_lanes_validation_rows "$itemf" /dev/null 0)"`. Keep the waiver's lookup `_lanes_validation_rows "$itemf" /dev/null 0 | awk`, which takes no evdir, so it never calls `gh`. Keep the `unrun` branch `echo "$G unrun — V$n $title: $ev"; return 0`. Keep the reader's unparsed and duplicate-number fail-closed rows (`0\t(no parseable entry)\tunparsed\tNOT-RUN`, `entry number $n is not unique`).
  - keep: today's body decisions unchanged (`ev="no evidence in the PR body"`, `elif [ "$kind" != repro ] && grep -qw 'FAIL' <<<"$sec"; then st=FAIL`). The file path only adds to a NOT-RUN row's evidence text, or replaces that row's status.
  - keep: an evidence text holds no tab, `|` or newline. `current-escalation --check` takes `V<n> <title>`, and golden step `gate-validation-gate-unrun-escalated/steps` parses `s/^validation-gate: unrun — \(V[0-9][0-9]* [^:]*\): .*/\1/p`.
  - reuse: the one `gh` seam, `"$LANES_GH" pr view`, and the `mktemp -d` temp-dir idiom with `rm -rf "$tmp"` on every exit path. Bash 3.2: `IFS="$(printf '\t')"` reads and no `mapfile`.
  - mirror: `lane-readiness` and `validation-gate` both call `_lanes_validation_rows`, the comment `THE Validation reader, shared by` (the `no second parser` rule). The file path goes inside that one reader, never in a caller.
  - pinned by: `loomwright/scripts/test-automate-lanes.d/05-timeline-and-gate.sh` `AL1_WANT="validation-gate: unrun — V2 Running system: no evidence in the PR body"` (and AL11c, AL13–AL16's exact `unrun` strings). Its AL10 mutation control (`an unconditional ok verdict turns AL1 red`) must stay red.
- **`loomwright/scripts/automate-lanes.sh`**
  - keep: modules are sourced by name, never globbed (`Listed by name, never globbed`), one `_lanes_source <name> || { return 1 2>/dev/null || exit 1; }` line between `# >>> automate-lanes.d/<name>.sh` / `# <<< automate-lanes.d/<name>.sh` markers. That is the form `_lanes_bundle` inlines.
  - keep: ONE header map under `# Modules (sourced in this order from automate-lanes.d/):` naming every module in source order.
  - pinned by: `loomwright/scripts/test-automate-lanes-modules.sh` (`the header carries ONE module map naming every module, in source order`).
- **`loomwright/scripts/test-automate-lanes-modules.sh`**
  - extend `MODS_WANT="common create launch relay remove notify-guards status-read park-leaks status readiness wave phase"` with `evidence` in its source position, immediately before `readiness` (it becomes `… park-leaks status evidence readiness wave phase`), matching the `_lanes_source` order and the header map.
  - keep `SPLIT_MODS` unchanged: it is the historical split commit's list.
  - keep every module at or under its `[ "${n:-0}" -le 800 ]` size check.
- **`loomwright/scripts/test-automate-lanes.sh`**
  - keep: parts are sourced by name at top level (`tal_part() { [ -r "$HERE/test-automate-lanes.d/$1.sh" ]`, each part sourced by an explicit line).
  - add exactly one `tal_part 07-evidence-files && . "$HERE/test-automate-lanes.d/07-evidence-files.sh"` line after the `06-phase-sessions` line.
  - the new part's first line is the standalone guard that 06 carries, `declare -F tal_pgrep >/dev/null && [ -n "${T:-}" ] && [ -d "$T" ] ||`.
  - the suite's default `gh` stub fails every call (`echo "gh $*" >> "${GH_CALLS:-/dev/null}"; exit 1`). New legs pass their own stub through `LOOMWRIGHT_GH_BIN`, as AL's `vg()` does.
- **`loomwright/scripts/test-automate-lanes.d/05-timeline-and-gate.sh`**
  - keep: the AL fixtures under `fixtures/validation-gate/` are untouched, and the stubs `vg-gh402` / `vg-ghbody` still answer `pr view`.
  - only the expected `unrun` strings change, to the new evidence text.
- **`loomwright/scripts/automate-helpers.sh`**
  - keep: `validation-gate` is delegated to automate-lanes.sh (`delegated to automate-lanes.sh — the READY-park gate`).
  - only that `#:` usage line changes. It sits in the `#:@ hdr-lanes` help segment, so `--help` prints it. AL1b (`the dispatcher delegates validation-gate`) pins the delegation.
  - pinned by: `loomwright/scripts/fixtures/automate-helpers-help/hdr-lanes.golden` (line 16, `validation-gate  <runfile> <item> <pr_url> [--waive <n> --words <text>]`), compared byte-for-byte to `--help` output by `loomwright/scripts/test-automate-helpers-dispatch.sh` check 5. Update the golden in the same change.
- **`loomwright/scripts/test-pr-body-evidence-seam.sh`**
  - keep: the authoring-surface loop's allow-filter `grep -viE 'docs/evidence|evidence-file form|Criterion 20|Evidence rule|every review criterion'`. Every edited line that names the PR body must still name `docs/evidence`.
  - change: the pin `` '`## Validation (must pass before merge)` running-system steps are different' `` gives way to a pin on the new text.
  - keep its mutation-control pattern: each mutant built in a TEMP copy, gated on `cmp`.
- **`loomwright/scripts/test-requirement-shape.sh`**
  - keep S6's `case "$vg" in "validation-gate: unrun — V"*"Running system"*) vg_rs=1`. It calls the gate with an empty PR, which must still read `unrun` on that prefix, and `validation-gate: none — ` for the static-only copy.
  - keep the M4 control's `sed "/^## Story Template\$/,/^## Example: Staff Scheduling Story\$/` range.
- **Golden fixtures (`gate-validation-waive`, `gate-validation-gate-unrun-escalated`)**
  - keep the `gh.stub` table format (`<rc>\t<glob>\t<output>`, first glob match wins, unmatched ⇒ exit 1).
  - `gate-validation-recheck-at-reconcile` (body PASS) and `dismissed-findings-decision-step` (`none`) must replay unchanged, which is AC3's byte-identical proof.
- **`loomwright/scripts/test-automate-next-step.sh`**
  - no change. Its reader-prefix extractor scans `automate-lanes.d/readiness.sh` for `## Progress` line regexes. The new module reads no run-file `## Progress` line, so it is not added to that scan list.

## Closed enumerations touched

> Sibling grep at base `18f857b8816f4ce5d2e5aaef84fe8683249c6263`: `grep -rnF 'automate-lanes.d/readiness.sh' --exclude=CHANGELOG.md --exclude-dir=.supervisor .` returns 14 hits in 8 files (plus `grep -rnF 'park-leaks status readiness' --exclude=CHANGELOG.md .` → 2 hits in 1 file).

- **`evidence`** (a new automate-lanes module; sibling: `readiness`). It must be named in:
  - `loomwright/scripts/automate-lanes.sh`: the `# >>> automate-lanes.d/<name>.sh` source blocks, plus the header map `# Modules (sourced in this order from automate-lanes.d/):`. Extend both.
  - `loomwright/scripts/test-automate-lanes-modules.sh`: `MODS_WANT="… readiness wave phase"`. Extend it.
  - `loomwright/scripts/test-automate-lanes-modules.sh`: `SPLIT_MODS`. No change: it is the historical module list of commit `c7d4f9a`.
  - `loomwright/scripts/test-automate-next-step.sh`: `for f in automate-helpers.d/runfile.sh automate-lanes.d/readiness.sh automate-lanes.d/park-leaks.sh`. No change: it lists `## Progress` line readers, and the new module reads none.
  - `loomwright/scripts/test-automate-golden.sh`: three comment and fixture mentions of a `readiness.sh` SIGPIPE line. No change: they are a synthetic noise string, not a module list.
  - `loomwright/scripts/automate-helpers.d/plan-waves.sh`: a prose mention of the scope fence. No change.
  - `docs/evidence/as19-split-lanes-and-trail-scripts.md`, `docs/evidence/coordinator-model-ab.md`, `docs/evidence/as24-terse-script-output.md`, `docs/evidence/dismissed-05-golden.md`: frozen evidence of past runs. No change.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-automate-lanes.d/07-evidence-files.sh`: the AC1 leg (declared PASS + fence ⇒ `ok` naming the file) | delete `# ev-read: content` in `loomwright/scripts/automate-lanes.d/evidence.sh` |
| `loomwright/scripts/test-automate-lanes.d/07-evidence-files.sh`: the AC5 leg (a declared file the PR does not change is not used) | delete `# ev-filter: changed-only` in `loomwright/scripts/automate-lanes.d/evidence.sh` |
| `loomwright/scripts/test-automate-lanes.d/07-evidence-files.sh`: the AC2 leg (FAIL in fenced output, declared PASS ⇒ evidenced) | delete `# ev-exempt: declared verdict outranks output words` in `loomwright/scripts/automate-lanes.d/evidence.sh` |
| `loomwright/scripts/test-automate-lanes.d/07-evidence-files.sh`: the AC10 leg (changed-file list unreadable ⇒ NOT-RUN with the reason) | delete `# ev-closed: unreadable list` in `loomwright/scripts/automate-lanes.d/evidence.sh` |
| `loomwright/scripts/test-automate-lanes.d/07-evidence-files.sh`: the AC4 leg (lane-readiness rows match validation-gate's) | flip `"$pr" "$tmp/ev" > "$tmp/val"` → `"$pr" "" > "$tmp/val"` in `loomwright/scripts/automate-lanes.d/readiness.sh` |
| `loomwright/scripts/test-automate-lanes.d/05-timeline-and-gate.sh`: AL1 (changed expected `unrun` text) | delete `echo "$G unrun — V$n $title: $ev"; return 0` in `loomwright/scripts/automate-lanes.d/readiness.sh` |
| `loomwright/scripts/test-pr-body-evidence-seam.sh`: the template Evidence rule teaches the verdict line | delete `Verdict: PASS for Validation <n>` in `loomwright/skills/supervisor-readiness/SKILL.md` |
| `loomwright/scripts/test-pr-body-evidence-seam.sh`: the user-story-writing item rule teaches the verdict line (it replaces the `running-system steps are different` pin) | delete `Verdict: PASS for Validation <n>` in `loomwright/skills/user-story-writing/SKILL.md` |
| `loomwright/scripts/test-requirement-shape.sh`: the Story Template's Running system entry names its evidence file and verdict line | delete `with its declared verdict line` in `loomwright/skills/user-story-writing/SKILL.md` |

**Literal contract for the rows above (the worker writes these exactly):**
- Each `# ev-…:` marker ends the ONE line that holds its guard. The code before that line sets the unguarded default, so deleting the line disables exactly that guard. For example, the candidate list starts as the full directory listing, and the marked line narrows it to changed paths. The FAIL scan is enabled first, and the marked line disables it.
- `Verdict: PASS for Validation <n>` appears on exactly one line in each of the two skill files.
- `with its declared verdict line` appears exactly once in `user-story-writing/SKILL.md`, inside the Story Template's Running system entry.
- lane-readiness's reader call is written `_lanes_validation_rows "$itemf" "$tmp/body" "$gh_ok" "$pr" "$tmp/ev" > "$tmp/val"`.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Evidence-file reader in the shared Validation reader, tests, fixtures, evidence, release | AC1–AC11 (the gate's own line), AC13 (code comments), AC14, AC15, AC16 | 16 modify, 4 create | `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | Authoring and doc surfaces teach the verdict line; remedy points at the evidence file | AC11 (docs), AC12, AC13 (docs) | 8 modify, 0 create | `skills/user-story-writing/SKILL.md`, `skills/supervisor-readiness/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/automate-lanes.d/evidence.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/evidence.sh", name: "# ev-filter: changed-only"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/evidence.sh", name: "# ev-read: content"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/evidence.sh", name: "# ev-exempt: declared verdict outranks output words"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/evidence.sh", name: "# ev-closed: unreadable list"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/readiness.sh", name: "\"$pr\" \"$tmp/ev\" > \"$tmp/val\""}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "_lanes_source evidence"}
  - {kind: "file", path: "loomwright/scripts/test-automate-lanes.d/07-evidence-files.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-lanes.sh", name: "07-evidence-files"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-lanes-modules.sh", name: "status evidence readiness"}
  - {kind: "file", path: "docs/evidence/validation-gate-declared-verdict.md"}
  - {kind: "symbol", path: "docs/evidence/validation-gate-declared-verdict.md", name: "Verdict: PASS for Validation 4"}
requires: []
lanes:
  - "loomwright/scripts/automate-lanes.d/evidence.sh"
  - "loomwright/scripts/automate-lanes.d/readiness.sh"
  - "loomwright/scripts/automate-lanes.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/hdr-lanes.golden"
  - "loomwright/scripts/test-automate-lanes.sh"
  - "loomwright/scripts/test-automate-lanes.d/05-timeline-and-gate.sh"
  - "loomwright/scripts/test-automate-lanes.d/07-evidence-files.sh"
  - "loomwright/scripts/test-automate-lanes-modules.sh"
  - "loomwright/scripts/fixtures/automate-golden/gate-validation-waive/*"
  - "loomwright/scripts/fixtures/automate-golden/gate-validation-gate-unrun-escalated/*"
  - "docs/evidence/validation-gate-declared-verdict.md"
  - "changelog.d/validation-gate-declared-verdict.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires:
  - "gh CLI: `gh pr view <pr> --json headRefOid,files` and `gh api [-H 'Accept: application/vnd.github.raw'] repos/<owner>/<repo>/contents/<path>?ref=<sha>` (verified read-only against PR #802 at planning time)"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "Verdict: PASS for Validation <n>"}
  - {kind: "symbol", path: "loomwright/skills/user-story-writing/SKILL.md", name: "Verdict: PASS for Validation <n>"}
  - {kind: "symbol", path: "loomwright/skills/user-story-writing/SKILL.md", name: "with its declared verdict line"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/modes-and-merge-gate.md", name: "for `validation_unrun` only:"}
  - {kind: "symbol", path: "loomwright/scripts/test-pr-body-evidence-seam.sh", name: "Verdict: PASS for Validation <n>"}
  - {kind: "symbol", path: "loomwright/scripts/test-requirement-shape.sh", name: "with its declared verdict line"}
requires: []
lanes:
  - "loomwright/skills/supervisor-readiness/SKILL.md"
  - "loomwright/skills/user-story-writing/SKILL.md"
  - "loomwright/skills/automate-loop/modes-and-merge-gate.md"
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/docs/rationale/automate-loop.md"
  - "loomwright/scripts/test-pr-body-evidence-seam.sh"
  - "loomwright/scripts/test-requirement-shape.sh"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
external_requires: []
```

**Subtask 1 notes:**
- **Changelog fragment:** write `changelog.d/validation-gate-declared-verdict.md` (a `<!-- bump: minor -->` user-visible behavior change), then run `bash scripts/bump-version.sh`. This is a single-lane run (`lane.json` `single_lane: true`), so the lane's PR carries the bump (`changelog.d/README.md` §"Who runs the bump"). The fragment is deleted by the fold, so it is not a `provides` entry.
- **Evidence file:** `docs/evidence/validation-gate-declared-verdict.md` holds the `Verdict: PASS for Validation 4` line. Its fenced output is the new gate run in a hermetic replay that serves this very file through a stub `gh`. The live gate on the PR then reads it at RECONCILE/GATE time.

**Subtask 2 notes:**
- Use exactly the declared-line form from `## Task`.
- The `validation_unrun` remedy bullet and the per-item-loop RECONCILE paragraph tell the owner to add the verdict line and the fenced output to the step's `docs/evidence/` file and `--resume`. Neither says to paste into the PR body.
- Keep every edited line that names the PR body also naming `docs/evidence`, which the seam test's allow-filter requires.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (independent)
Subtask 2 (independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2 (parallel, both have empty `requires`)
- **Recommended workers:** 2
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/error-handling/SKILL.md` (fail-closed reads) |
| 2 | `skills/user-story-writing/SKILL.md`, `skills/supervisor-readiness/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope spans about 28 files (code, tests, golden fixtures, doc surfaces), over one worker's context | MEDIUM | Feasibility (Phase 2.5). The `context-bound` split into two subtasks with zero file overlap |
| Existing exact-string pins (AL1, AL11c, AL13–AL16) and two golden fixtures change, because a body NOT-RUN row now carries the evidence-file reason | MEDIUM | Treat them as changed pins. AL10's mutation control must stay red. Recheck-at-reconcile (body PASS) and `none` fixtures replay byte-identical (AC3) |
| `gh pr view --json files` may cap the changed-file list on very large PRs, so an evidence file could be missed | LOW | Fails closed (step stays NOT-RUN with a reason), never a false PASS. Note it in the module header |
| Self-reference: AC16's file declares PASS for the very gate it proves | LOW | Its fenced output is a hermetic replay of the new gate on that file. The live READY park (`validation-gate: ok` naming the file, no `--waive`) is the running-system proof, recorded in `## Progress` |
| Skill token budgets: `supervisor-readiness` has 492 tokens of headroom | LOW | Keep the Evidence-rule addition to one sentence. Raise the budget entry and its mirror row only if `check-token-budget.sh` fails |
| Shares `readiness.sh` and automate-loop docs with pending `dismissed-followups/03` and `/12` (per the requirement) | LOW | Not in the same `--parallel` wave. This run is single-lane |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 1
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-03-validation-gate-declared-verdict.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-11-03T12:48:12Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/809
- **Branch:** feature/validation-gate-declared-verdict
- **Files changed:** 27
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** unknown (no_driver_handover)
- **Summary:** Resumed (--continue) after a DNS outage stopped the previous session at publish. Pushed 4021fe2, opened PR #809 (base main verified), live validation-gate on the PR printed ok naming docs/evidence/validation-gate-declared-verdict.md. Phase 4.5 round 1 FAIL: one HIGH (an unreadable PR body let a file's declared PASS turn a body FAIL into ok) plus a red required `ci` check (pipe into grep -q under pipefail in test-requirement-shape.sh); fix iteration 1 (c439c62) fixed both with new EV10i-k/EV13g legs. Round 2 PASS, no issues. 3 MEDIUMs dismissed below the HIGH fix floor.

## Not verified
- **live validation-gate on real PR (AC16 second half)** — no PR at worker time; since run by the Supervisor on PR #809: ok naming the evidence file (subtask 1)
- **test-automate-lanes.sh launch/relay groups** — outside the worker sandbox (subtask 1)
- **full ci-local.sh pool and golden mutation legs M0-M11** — worker ran GOLDEN_SKIP_LEGS=1 (subtask 1)
- **test-automate-next-step.sh pool groups 2 and 3** — not run by the worker (subtask 1)
- **validation-gate behaviour described in automate-run.md row and rationale/automate-loop.md paragraph** — prose checked against the brief's contract only (subtask 2)
