# Supervisor Job: af/15 — pin MEDIUM/LOW code-review severity counting in a test and delete the unreachable Rubric B 7.0 branch

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-22-123646/L5
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-followups/15-telemetry-measures-the-agent-not-the-code.md
- **Base commit:** 237adab3f71e30ac817b34b9fb630e50e9661cb2

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash 3.2 test harness + the core's embedded Python; no new tooling |
| 2 | Dependency Availability | GO | No new dependency; the hermetic harness (`hermetic-test-env.sh`, recording `gh` stub) already exists in `test-telemetry-threads.sh` |
| 3 | Architecture Fit | GO | Extends the existing T2 count assertions and T8 `mutant()` mutation controls; deletes one dead `elif` |
| 4 | Scope vs Supervisor Capability | GO | 3 modify + 2 create, well under the single-agent threshold |
| 5 | Hard Blockers | GO | Count fix (ee5b1e7) is already on main; the `count-from-parsed-findings` sentinels exist; the `7.0` branch is provably subsumed by the `9.0` condition above it |

**Overall Verdict:** GO

## Task
**Goal:** Make the code-review MEDIUM/LOW/category counting fix impossible to regress silently, and make `score_code_review()` and `docs/TELEMETRY.md` §"Rubric B" describe only reachable cases — without changing any score.

**Problem Statement:**
The plugin maintainer needs a test that pins MEDIUM/LOW severity and per-category counting for `CODE_REVIEW_RESULT` telemetry because nothing does today.
Currently, both code-review goldens (`code-review-fail__allow_with_repo.golden.txt`, `code-review-shuffled__allow_with_repo.golden.txt`) carry a single HIGH `new` finding, T8 mutant (b) in `test-telemetry-threads.sh` is caught only through the drift fixture, and T3's `T3_close_series` pins only the per-round TOTAL (`round_total = sum(issues_by_severity.values())`). So the suite checks only the total finding count per round (T3) and the drift category (T2): a regression that drops or misfiles MEDIUM/LOW severity or non-drift category counts while keeping the total is not caught, and no test pins the MEDIUM/LOW severity split or any non-drift category count. Separately, `score_code_review()` keeps a `base = 7.0` branch whose condition is a strict subset of the `9.0` condition before it; Rubric B's table row 2 documents that dead case, and its **Worked example** (PASS, two `new` MEDIUM → base `7`, bucket `medium`) describes it too — the code scores that input 9, bucket `high`.
Success looks like: a mixed-severity fixture asserting `"medium": 1`, `"low": 2`, `"nit": 1` passes on the branch, a BLOCKING/HIGH-only mutant fails it, the dead branch and its doc row are gone, and every existing golden score is byte-identical.

**Non-goals:** changing any score; renaming `Success:`; reopening or commenting on closed issues #282/#287/#297/#302; posting anything to GitHub; touching the reachable `base = 7.0` branches of Rubric A (`score_supervisor`) or Rubric C (`score_qa`).

**Privacy (owner rule 2026-10-13 — telemetry = plugin facts only):** the new fixture's findings carry neutral placeholder `file:`/`description:` values (the validator's `ISSUE_REQUIRED` needs both), and every new assertion checks integer counts and enum keys only — never finding text, paths, repo or PR names.

## Acceptance Criteria
- [ ] 1. Given a new `mixed` code-review fixture in `loomwright/scripts/test-telemetry-threads.sh` (decision `FAIL`; findings HIGH `new` + MEDIUM `new` + LOW `new` + LOW `nit`, all neutral placeholder text), when T2 runs it through the real `send-telemetry-core.sh --dry-run`, then it asserts `"high": 1`, `"medium": 1`, `"low": 2`, `"new": 3` and `"nit": 1` in the output, and all pass on the branch.
- [ ] 2. Given a new T8 mutant (e) built with the existing `mutant()` helper over the `count-from-parsed-findings` sentinels, whose replacement counts only BLOCKING/HIGH severities, when it runs on the `mixed` fixture, then its output lacks `"medium": 1` and `"low": 2` (asserted with `assert_not_match`), proving the AC-1 assertions catch the 5d9f7a2 regression; the header's "WHAT IT PROVES" T2/T8 lines name the new coverage.
- [ ] 3. Given `score_code_review()` in `loomwright/scripts/send-telemetry-core.sh`, when the change lands, then the `elif decision == "PASS" and (new_medium > 0 or new_low > 0) …` branch and its `base = 7.0` line are deleted, the now-unused `new_medium, new_low = …` assignment is removed, and `bash loomwright/scripts/test-telemetry.sh`, `bash loomwright/scripts/test-send-telemetry-core.sh` and `bash loomwright/scripts/test-telemetry-threads.sh` pass with no golden regenerated (every existing fixture's score unchanged).
- [ ] 4. Given `loomwright/docs/TELEMETRY.md` §"Rubric B — `CODE_REVIEW_RESULT`", when the change lands, then the `| \`decision == "PASS"\` AND only \`new\` issues at MEDIUM or LOW severity | **7** |` row is removed and the table lists exactly the four reachable cases (9 / 4 / 2 / 3) the code implements; the **Worked example** paragraph is rewritten to the score the code actually gives that input (`decision: "PASS"`, two `new` MEDIUM issues, zero BLOCKING/HIGH/drift -> base `9`, no deltas -> **`9`**. Bucket: `high`.); afterwards the section-scoped check `awk '/^### Rubric B/{f=1;next} /^### Rubric C/{f=0} f' loomwright/docs/TELEMETRY.md | grep -cF 'base `7`'` prints `0` (a whole-file grep would still hit Rubric C's reachable worked example, which stays); the Adjustments table is unchanged. (A doc correction — the code's score for that input is already 9 on main, so no score changes.)
- [ ] 5. Given the sandboxed running-system check (fake `HOME`, recording `gh` stub on `PATH`, the `mixed` fixture, `send-telemetry-core.sh --dry-run`), when it is run on the branch, then a committed evidence file `docs/evidence/af15-telemetry-count-pins.md` contains the exact command, the pasted `issues_by_severity` / `"issues"` line, the `issues_by_category` line and the stub's call count (`0`), and the PR body links to it.
- [ ] 6. Given the fragment `changelog.d/af15-telemetry-count-pins.md` (fragment format per `changelog.d/README.md`, `<!-- bump: patch -->`), when `bash scripts/check-version-bump.sh` runs, then it passes; no version file is hand-edited.
- [ ] 7. Given the validation set, when run, then `test-telemetry-threads.sh`, `test-send-telemetry-core.sh`, `scripts/check-doc-currency.sh` and `loomwright/scripts/test-citation-drift.sh` pass locally and no test posts to GitHub (stub only); full `ci-local` runs on GitHub CI (owner rule 2026-10-12). Rollback is `git revert`.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

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

> Applied here: Rubric B's table in `docs/TELEMETRY.md` restates `score_code_review()`'s branches, so AC 3 and AC 4 land in the same change. The fragment and evidence file state no version or count literal.

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| telemetry | `loomwright/scripts/test-telemetry-threads.sh`, `loomwright/scripts/send-telemetry-core.sh`, `loomwright/docs/TELEMETRY.md` | `changelog.d/af15-telemetry-count-pins.md`, `docs/evidence/af15-telemetry-count-pins.md` | HIGH |

> **Validator-owned surfaces:** `scripts/check-doc-currency.sh` and `test-citation-drift.sh` scan `loomwright/docs/TELEMETRY.md`; the change adds no version/count claim and no bare `file:N` citation there, so no further surface is expected to need an update.

**Total estimated files:** 3 modify + 2 create

## Touched-file invariants

> Grounded at base `237adab3f71e30ac817b34b9fb630e50e9661cb2`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/send-telemetry-core.sh`** — keep: the count block and both its sentinels byte-identical (T8 mutants (b) and the new (e) splice between them): `# MUTATION_CONTROL_BEGIN: count-from-parsed-findings`, `issues_by_severity[sev] += 1`, `issues_by_category[cat] += 1`; keep the success derivation `success = (decision == "PASS")`, the defensive default `score_default_used schema=CODE_REVIEW_RESULT` and the adjustment lines (`base += -0.25 * drift_total`) unchanged; delete ONLY `elif decision == "PASS" and (new_medium > 0 or new_low > 0) and new_blocking == 0 and new_high == 0:` plus its `base = 7.0` body, and the then-unused `new_medium, new_low = n("MEDIUM", "new"), n("LOW", "new")`. The two other `base = 7.0` lines (Rubric A `score_supervisor`, Rubric C `score_qa`) are reachable and stay. Exit-code contract (0..5, fail-SAFE emitter — CLAUDE.md §"Failure-Mode Invariants") unchanged. fired by: `hooks.json` SubagentStop matchers for code-reviewer / qa-executor / supervisor → `send-telemetry.sh` → this core; only the code-reviewer path reaches `score_code_review()`, but the count block runs for all three schemas — its `else:` branch (`issues_by_severity["unspecified"] = len(issues)`) is the qa/supervisor path, so mutant (e)'s replacement must keep it or the qa/supervisor goldens break. pinned by: `loomwright/scripts/test-telemetry.sh` goldens (`code-review-fail__allow_with_repo.golden.txt`, `code-review-shuffled__allow_with_repo.golden.txt` — must NOT be regenerated), `loomwright/scripts/test-send-telemetry-core.sh` (`# MUTATION_CONTROL_BEGIN: resolve-egress-config-integration`), `loomwright/scripts/test-telemetry-threads.sh`.
- **`loomwright/scripts/test-telemetry-threads.sh`** — keep: hermetic entry `hermetic-test-env.sh`, `# bash-3.2-safe.` (no bash-4 syntax, no `${arr[@]}` on a possibly-empty array under `set -u`), no network (`gh` is the recording stub only); reuse: the Python fixture generator's `def write(name, text` + `review(decision, issue_lines)` for the `mixed` fixture, `assert_match`/`assert_not_match`, `run_core "$REPO" "$FIX/<name>.json" --dry-run`, and `mutant() {` with a `$SANDBOX/repl-e` replacement file for mutant (e) — do not hand-roll a new splice; mirror: the replacement block must stay valid Python at the sentinels' indentation and keep the `else:` branch's `issues_by_severity["unspecified"] = len(issues)` like `repl-b` does; header: update the `T8  mutation controls` and T2 lines of "WHAT IT PROVES".
- **`loomwright/docs/TELEMETRY.md`** — keep: the Rubric B intro sentence `` `pre_existing` and `nit` issues do not affect the score `` and the Adjustments table; remove the `| \`decision == "PASS"\` AND only \`new\` issues at MEDIUM or LOW severity` row, and rewrite the `**Worked example.**` paragraph under the Adjustments table (today: `BLOCKING/HIGH/drift -> base \`7\`, no deltas -> **\`7\`**. Bucket: \`medium\`.`) to base `9` / **`9`** / bucket `high` — it is a second restated copy of the dead case (house rule "restating copy is updated in the SAME change"). Bucket bounds per §"Bucket ranges" (score ≥ 8 ⇒ `high`) are unchanged. No test pins the example's text.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-telemetry-threads.sh` — T2 mixed `"high": 1` | flip `issues_by_severity[sev] += 1` → `issues_by_severity[sev] += int(sev not in ("blocking", "high"))` in `loomwright/scripts/send-telemetry-core.sh` |
| `loomwright/scripts/test-telemetry-threads.sh` — T2 mixed `"medium": 1` | flip `issues_by_severity[sev] += 1` → `issues_by_severity[sev] += int(sev in ("blocking", "high"))` in `loomwright/scripts/send-telemetry-core.sh` |
| `loomwright/scripts/test-telemetry-threads.sh` — T2 mixed `"low": 2` | flip `issues_by_severity[sev] += 1` → `issues_by_severity[sev] += int(sev in ("blocking", "high"))` in `loomwright/scripts/send-telemetry-core.sh` |
| `loomwright/scripts/test-telemetry-threads.sh` — T2 mixed `"nit": 1` | delete `issues_by_category[cat] += 1` in `loomwright/scripts/send-telemetry-core.sh` |
| `loomwright/scripts/test-telemetry-threads.sh` — T2 mixed `"new": 3` | delete `issues_by_category[cat] += 1` in `loomwright/scripts/send-telemetry-core.sh` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Pin mixed-severity counts, add BLOCKING/HIGH-only mutant, delete dead Rubric B 7.0 branch + doc row | all | 3 modify, 2 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/send-telemetry-core.sh", name: "score_code_review"}
  - {kind: "symbol", path: "loomwright/scripts/test-telemetry-threads.sh", name: "repl-e"}
  - {kind: "symbol", path: "loomwright/docs/TELEMETRY.md", name: "Rubric B"}
  - {kind: "file", path: "changelog.d/af15-telemetry-count-pins.md"}
  - {kind: "file", path: "docs/evidence/af15-telemetry-count-pins.md"}
requires: []
lanes:
  - "loomwright/scripts/test-telemetry-threads.sh"
  - "loomwright/scripts/send-telemetry-core.sh"
  - "loomwright/docs/TELEMETRY.md"
  - "changelog.d/af15-telemetry-count-pins.md"
  - "docs/evidence/af15-telemetry-count-pins.md"
external_requires: []
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| The new `mixed` fixture is rejected by the sibling validator (exit 5, `validator_rejected`) so the T2 assertions never see counts | MEDIUM | Decision `FAIL` with a `new` HIGH finding satisfies v3 rule k; every issue carries `severity`/`category`/`file`/`description` (`ISSUE_REQUIRED`); assert `would_exit` = 0 before the count needles |
| `"low": 2` / `"medium": 1` needles match an unrelated substring of the dry-run output, so the mutant stays green | MEDIUM | AC 2's mutant (e) must actually turn those needles absent — run it; check the needles against the mutant output, not only the branch output |
| Deleting the dead branch accidentally edits the reachable Rubric A/C `base = 7.0` lines (same literal appears 3× in the core) | MEDIUM | Anchor the edit on the `elif decision == "PASS" and (new_medium > 0 …` line, not on `base = 7.0`; goldens for supervisor/qa must stay byte-identical |
| A golden regenerated "to make it pass" would hide a score change | HIGH | AC 3 forbids `WRITE_GOLDENS=1`; `git diff --stat loomwright/scripts/telemetry-fixtures/` must be empty |
| Placeholder fixture text leaks project-like content into a post | LOW | Use neutral placeholders; T7 privacy assertions already scan every posted body; new assertions are counts/enums only |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-24-af15-telemetry-count-pins.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-24T04:24:56Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/689
- **Branch:** feature/af15-telemetry-count-pins
- **Files changed:** 5
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Mixed-severity T2 fixture pins high1/medium1/low2/new3/nit1; T8 mutant (e) (BLOCKING/HIGH-only count) proves the pins catch the regression; dead Rubric B PASS base=7.0 branch, unused new_medium/new_low and the matching TELEMETRY.md row + worked example removed (example now 9/high, the score the code already gave). Evidence file + patch fragment added; goldens untouched. Phase 4.5 holistic review PASS on iteration 1 with 3 LOW pre_existing/nit findings dismissed; pin mutations 5/5 held; ground truth 2/2.

## Not verified
- **Full `ci-local.sh` pool** — owner rule: full run happens on GitHub CI; only --affected (19 entries) ran locally and passed (subtask 1)
