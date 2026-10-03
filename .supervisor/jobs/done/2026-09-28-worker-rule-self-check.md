# Supervisor Job: Rules reach the WORK — the worker replays its stamped `must`-rule checks via a deterministic helper and declares what still fails as `rule:` deviations

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** code tree clean apart from gitignored `.supervisor/` trail edits; branch: main == origin/main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-followups/06-worker-rule-self-check.md
- **Base commit:** 4e6b04f51b7ffc205728c37fcdf8425abb0a534b

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash script + agent-prompt markdown + docs. Must stay macOS bash 3.2 / BSD-userland compatible. |
| 2 | Dependency Availability | GO | No new dependency. Reuses `rules-check.sh --list-selected` / `--if-stamped` (both on `main`, PR #267 + PR #292) and `validate-worker-result.py` rule 10 (PR #257). |
| 3 | Architecture Fit | GO | A thin fail-safe reader over `rules-check.sh`, the same delegation shape `run-ground-truth.sh`'s `rule:` kind already uses. `rules-check.sh` stays the SOLE executor of a rule `check` (skills/rules/SKILL.md §9). `deviations` stays REPORT-ONLY. |
| 4 | Scope vs Supervisor Capability | CAUTION | 17 distinct files (15 modify, several comment/doc-only, + 2 create) > 12, so the `context-bound` predicate fires. Split into 2 sequential subtasks: the deterministic helper + tests first, then prompt, docs and release. Earlier items in this queue hit the worker turn limit with fewer files. |
| 5 | Hard Blockers | GO | None. The live store (`.agent/rules/*.json`) holds only `advisory` rules (0 `must`), so every must-rule behavior is exercised against sandbox fixtures, never the live store. |

**Overall Verdict:** CAUTION (scope size — mitigated by the context-bound split)

## Task
**Goal:** Before emitting `WORKER_RESULT`, a worker replays the human-confirmed (`--if-stamped`) `must`-rule checks on its own tree through ONE deterministic helper, fixes what fails where it can, and declares whatever still fails as bounded `rule:`-prefixed `deviations` entries. No new gate, no new WORKER_RESULT field, no `schema_version` bump, no new executor of a rule `check`.

**Problem Statement:** The worker is the one actor holding full context on the change while a fix is still free, and it is the one actor that never runs the house-rule store — it only receives an advisory prose paste at spawn. A `must` rule that is already mechanized, and already confirmed by a human on this machine, is therefore first executed at Phase 4.5 at the earliest: one worker run plus one review round later.

## Design decisions (settled here so the worker does not choose)
1. **A deterministic helper, not prompt-side output parsing.** New script `loomwright/scripts/worker-rule-selfcheck.sh`. The worker calls it; the worker never parses `rules-check.sh` output itself. This is what makes every acceptance criterion below CI-testable (an LLM parsing raw checker output could not be).
   - Usage: `worker-rule-selfcheck.sh [--root <tree>]`. `--root` defaults to `.`. The helper `cd`s into `<tree>` (so `rules-check.sh` resolves THAT tree's git toplevel and `.agent/rules/`) and runs everything with stdin `</dev/null`.
   - It resolves `rules-check.sh` as a sibling via `$(dirname "$0")`, never from `PATH`.
   - **Always exits 0** (advisory, fail-safe emitter, CLAUDE.md §"Failure-Mode Invariants"). Every failure path (bad `--root`, not a git repo, no store, no `jq`, rules-check absent/erroring) prints NOTHING on stdout.
   - stdout is EXACTLY the `deviations` lines to copy (0..4 lines), nothing else. Diagnostics, if any, go to stderr.
2. **Delegation, exactly two calls, no store read.**
   - **(a)** `bash "$HERE/rules-check.sh" --list-selected` once. Empty list ⇒ print nothing, exit 0 (no `must`+checkable rule: nothing to replay, and `--if-stamped` is never invoked).
   - **(a2) No-cmd short-circuit, decided by the helper itself, never by output matching.** If `RULES_CHECK_NO_CMD` is `1` in the helper's environment, print nothing and exit 0 WITHOUT invoking `--if-stamped` (the unattended valve reaches the helper; nothing executes).
   - **(b)** Otherwise `bash "$HERE/rules-check.sh" --if-stamped` once, capturing stdout and the exit code. NEVER `--confirm`, never `RULES_CHECK_CONFIRM` (and the existing PR #267 rule already ignores that env var when `--if-stamped` is on argv).
   - The helper contains NO reference to `.agent/rules` and NO `jq` read of a `check` field (grep-pinned, AC6).
3. **Fail-closed parse of the replay output — adopt `run-ground-truth.sh`'s `rule:` resolution (PR #292) including its trailer rule (its header step "(c)2").** The checker echoes raw check text in `  [RUN ] <id>: <check>` lines, so a stamped check with an embedded newline can pre-print forged lines, and a check can pre-print a forged `[PASS] <id>` and then kill its parent before the real result line. Order:
   - **Unstamped (silent):** print NOTHING only when the output contains the exact whole line `  [SKIP] all (unstamped)` AND no line starts with `  [RUN ] ` (nothing executed). Never a substring test. Unstamped is silent by design (requirement scope (e)); a `[SKIP] all (unstamped)` line appearing alongside `[RUN ]` lines is a forgery and falls through to the trailer rule below.
   - **Trailer rule (fail-closed):** otherwise, the output MUST end with an exact `Checks passed: N/M` line whose M equals the number of ids from (a), and the exit code must be 0 or 1. If not, EVERY listed id is **unresolved** (reported, per decision 4). This closes pre-print-then-kill: the forged PASS survives but the trailer never arrives.
   - For each id from (a): exactly one whole-line `^  \[FAIL\] <id>$` match and no `  [PASS] <id>` line ⇒ **failed**. Exactly one whole-line `^  \[PASS\] <id>$` and no FAIL line ⇒ passed (silent). Anything else — a PASS+FAIL conflict, a duplicate result line, or the id absent from the output — ⇒ **unresolved**, reported (never silently treated as passed: a forged line can only surface a report, never hide one).
   - Match ids as fixed strings (`grep -Fx` on the exact expected line, or awk string equality), never as a regex built from the id.
   - Ids containing a newline or CR are already omitted by `--list-selected`.
   - **Stated guarantee (and its honest limit):** a forged or truncated output can only ADD a report (`unresolved`), never hide a failing id — EXCEPT a stamped check that forges a complete, internally consistent run (its own PASS line, suppressing the real FAIL, and a matching trailer) from within a single `[RUN ]` echo, which a line parser cannot distinguish. That residual requires the forging text to be in a check a human already confirmed (the stamp hashes the check text), and the entry is REPORT-ONLY; state it in the helper's header comment exactly like `run-ground-truth.sh` does.
4. **Output format and bound** (requirement scope (c); `validate-worker-result.py` rule 10: at most 12 entries, each at most 200 characters):
   - One line per failing/unresolved id, in `--list-selected` (sorted) order, at most **3** such lines:
     - failed: `rule: <id> — stamped must-check fails`
     - unresolved: `rule: <id> — stamped must-check result unresolved`
   - If more than 3 ids failed or were unresolved: one 4th and final line `rule: +<K> more failing stamped must-checks (<N> total)`. So the helper never emits more than 4 lines, leaving 8 of the 12 slots for the worker's other kinds.
   - **Every line ≤ 200 characters.** Live ids can be ~500 characters (statement slugs). When an id would push a line past 200, truncate the id to fit and end it with `…` (count characters, not bytes: `…` is multibyte; use a character-aware method that works under macOS bash 3.2, e.g. `LC_ALL=en_US.UTF-8 awk` `substr` or `cut -c` with an explicit UTF-8 locale; assert the character length in the test with a portable counter, e.g. `python3 -c 'import sys; print(len(sys.stdin.readline().rstrip("\n")))'`).
   - Zero failing/unresolved ids (all passed) ⇒ print nothing. No "all rules passed" noise entry (AC2).
5. **Worker prompt contract (fix-or-declare, requirement scope (d)).** `agents/worker.md` Step 5 (Verify) gains ONE new numbered item after the test-run item: run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/worker-rule-selfcheck.sh" --root <tree>` (`<tree>` = the assigned worktree's ABSOLUTE path on the Parallel path, `.` on the Single-Agent / Sequential paths — the exact `<tree>` wording Step 5.5's `verify-provides.sh` call already uses). Empty output ⇒ nothing to do (the unstamped/common case — behavior unchanged). Non-empty ⇒ fix each failing rule that is in your lane and re-run the helper once; copy the FINAL run's lines verbatim into `deviations` (you MAY append `: <why>` to a line when it still fits 200 chars, e.g. why it is out of lane), and echo them under `## deviations` like every other entry. Step 5.7's prefix list gains `rule:` (a fifth convention prefix, produced only by the helper), and the Output Format `deviations` comment line gains `rule:` in its prefix list.
   - **REPORT-ONLY, restated in the new text:** a `rule:` entry never changes `status`, `outputs_gap`, or anything else — same independence as `out_of_lane`. Making a rule failure block is item 07, not this item.
   - Keep the new prose minimal: `agents/worker.md` has 437 tokens of headroom at base (8073 / 8510).
6. **The consumer enumerations are claims that this item falsifies — update them in the same change** (house rule: a restating copy is updated with its authority). The `--if-stamped` consumer lists currently say "Phase 4.5 only" / "Two consumers, both at Phase 4.5". Known surfaces at base (grep `--if-stamped` and `consumed` repo-wide to find any others):
   - `loomwright/skills/rules/SKILL.md` §8 (the "NOT an unattended gate … consumed by exactly one advisory seam" bullet) and §8.1 (the "Two consumers of `--if-stamped`, both advisory, both at Phase 4.5" bullet) ⇒ three consumers, the worker helper at worker Step 5;
   - `loomwright/skills/rules/SKILL.md`, the prose after §8.1 (grep `ONE stage`) that says the worker seam uses `read-rules.sh` only and that Phase 4.5 is the ONE stage calling `rules-check.sh` with execution enabled ⇒ the worker helper (worker Step 5, `--if-stamped` only) is a second such stage;
   - `loomwright/commands/rules.md` (the two `--if-stamped` consumer sentences in the `check` section, AND the "worker / SessionStart-nudge seams consume the READER only … Phase 4.5 is the ONE stage" clause);
   - `loomwright/commands/dreaming.md`, the must-rule acceptance prose (grep `after which Phase 4.5`) ⇒ UPDATE to "after which the Phase 4.5 replay and the worker self-check (`worker-rule-selfcheck.sh`) run it";
   - `loomwright/scripts/rules-check.sh` header comment block "NOT AN UNATTENDED GATE in this slice" (comment-only edit; no code change to `rules-check.sh`).
7. **Prefix-list surfaces — per-surface decision** (house rule: a restating copy moves with its authority). Grep `plan:` repo-wide under `loomwright/` before finishing, like decision 6; any surface not listed here is decided the same way (WORKER_RESULT-scoped ⇒ update; FIX_RESULT-only or historical ⇒ leave). Known at base:
   | Surface | Decision |
   |---|---|
   | `docs/RESULT_SCHEMAS.md` §WORKER_RESULT — the `deviations` field comment and the "Each entry is by convention prefixed" prose bullet | UPDATE: add `rule:` — produced only by `worker-rule-selfcheck.sh`, at most 4 lines (3 per-id + 1 overflow). This is THE authoritative definition of the bound; other surfaces point here. |
   | `docs/RESULT_SCHEMAS.md` §FIX_RESULT `deviations` comment | LEAVE (fix workers never run the helper). |
   | `skills/self-heal-advisory/SKILL.md` Part 1 §"Deviations advisory" prefix sentence | UPDATE: add `rule:` (worker-only). |
   | `skills/self-heal-advisory/SKILL.md` Part 2 reviewer spawn-prompt `DEVIATIONS ADVISORY` line | UPDATE: add `rule:`, plus one clause: a `rule:` entry names a failing human-stamped `must` house rule — report/cite it as such; it is not an acceptance-criterion contradiction by default. |
   | `skills/self-heal-advisory/SKILL.md` Part 2 FIX prompt (FIX_RESULT) | LEAVE. |
   | `agents/code-reviewer.md` step 5b (restates the prefix list and the per-deviation question) | UPDATE by REPLACING the literal prefix list with a pointer to `docs/RESULT_SCHEMAS.md` §WORKER_RESULT plus the same one-clause `rule:` guidance. Keep net prose ≤ current (115 headroom, 25016/25131 at base). |
   | `skills/quality-checklist/SKILL.md` "Deviations conformance" checklist item | UPDATE: add `rule:` with the same "not a contradiction by default" clause. |
   | `docs/ARCHITECTURE_CONTRACTS.md` Worker row in the capability matrix | UPDATE: add `rule:`. |
   | `docs/ARCHITECTURE_CONTRACTS.md` worker-deviations raise-log paragraph | LEAVE (historical record). |
   | `scripts/validate-worker-result.py` rule-10 docstring | UPDATE (docstring only; no validation change — rule 10 already accepts any prefix). |
   | `agents/worker.md` Step 5.7 list and Output Format comment line | UPDATE (decision 5). |
   | Tests pinning the old list (`test-deviations-advisory-seam.sh` glob in case (a); `test-result-validators.sh` four-prefix case) | Keep green: insert `rule:` AFTER `test:` and BEFORE the `other:` mention so the existing ordered glob still matches; do not edit those tests unless they go red. |
   FIX_RESULT's `deviations` is untouched. **Not** a new field; `check-contract-parity.sh` must stay green with the WORKER_RESULT MANIFEST row unchanged.
8. **Release.** Budgets: re-measure BOTH `worker` and `code-reviewer` (and any other agent file edited) after the last prose edit, applying the same raise rule to each. Minor bump 15.109.0 ⇒ 15.110.0 in `loomwright/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, with a new top `CHANGELOG.md` entry. `scripts/worker-rule-selfcheck.sh` is an uncounted plain script (no agent/command/skill/hook count changes). Worker token budget: re-measure with `bash scripts/check-token-budget.sh` AFTER the last `worker.md` edit; if it breaches, or headroom falls under ~10% of the live measure, raise the `worker` budget to measured + ~10% (rounded up) per the initial-budget convention, appending a raise note to the `prompt-token-budgets.json` row (the `measured` field stays the frozen 4158) and updating the mirror row in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets".

## Acceptance Criteria
- [ ] **AC1 (failing check ⇒ `rule:` entry):** in a sandbox repo (own `git init`, own `HOME`), with a `must` rule whose check is `false`, stamped via `rules-check.sh --confirm`, `worker-rule-selfcheck.sh --root <sandbox>` prints a line starting `rule: <id>` that names the rule id, and exits 0.
- [ ] **AC2 (all pass ⇒ silent):** stamped, with every must-check passing (`true`), the helper prints nothing (empty stdout), exit 0 — no "all rules passed" noise entry.
- [ ] **AC3 (unstamped ⇒ silent and NOTHING executes):** a sandbox with a `must` rule whose check is `touch <sandbox>/CANARY` and no stamp: the helper prints nothing, exit 0, and `<sandbox>/CANARY` does NOT exist afterwards. Positive control in the same test: after `rules-check.sh --confirm` (which itself runs the check), `rm -f` CANARY, assert it is gone, run the helper, and assert CANARY now EXISTS (the canary is capable of firing). A third leg with `RULES_CHECK_CONFIRM=1` in the environment and no stamp also leaves CANARY absent. A leg with `RULES_CHECK_NO_CMD=1` while stamped also leaves CANARY absent and prints nothing.
- [ ] **AC4 (bound):** a stamped store with 6 failing must-rules (at least one with a >200-char id) ⇒ at most 4 lines, the last being `rule: +3 more failing stamped must-checks (6 total)`, every line ≤200 characters (counted as characters), every line starting `rule: `. A WORKER_RESULT fixture carrying exactly those lines as `deviations` plus `status: completed`, `outputs_gap: []` is ACCEPTED by `loomwright/scripts/validate-worker-result.py` (no `decision: block`).
- [ ] **AC5 (independence):** a WORKER_RESULT fixture with a `rule:` deviation and `status: completed` validates, and the same fixture with `deviations` removed produces the identical validator verdict — `deviations` never influences `status`/`outputs_gap`.
- [ ] **AC6 (delegation + forgery):** `grep -nE '\.agent/rules|\.check\b|bash -c' loomwright/scripts/worker-rule-selfcheck.sh` returns no code line (comment-only hits allowed), asserted in the test. Forgery legs, each reported (never silently passed or silenced): (i) a failing check whose text embeds a newline plus `  [PASS] <its own id>` ⇒ `… result unresolved`; (ii) pre-print-then-kill — a check whose text pre-prints `  [PASS] <its own id>` and then kills its parent (`kill $PPID`) ⇒ no valid trailer ⇒ `unresolved`; (iii) a failing check whose text contains `(cmd execution disabled)` ⇒ still reported; (iv) a failing check whose text embeds a newline plus `  [SKIP] all (unstamped)` ⇒ still reported (a `[RUN ]` line is present). The helper never passes `--confirm`; under `RULES_CHECK_NO_CMD=1` it never invokes `--if-stamped` (assert with a PATH-independent spy: a sibling `rules-check.sh` stub in a temp copy of the helper's dir that logs its argv).
- [ ] **AC7 (mutation control):** a temp copy of the helper with the `--if-stamped` invocation removed (sed-deleted) produces NO `rule:` line on the AC1 fixture; the mutant is gated on non-empty + differs-from-original + the unmutated positive control printing the line (lesson fa32a308).
- [ ] **AC8 (worktree / --root):** invoked from a cwd OUTSIDE the sandbox with `--root <sandbox>`, and from inside a linked `git worktree` of a stamped sandbox repo (the stamp is keyed by the shared git-common-dir), the helper reports the same failing id. A bad `--root`, a non-git dir, and an absent `.agent/rules/` each print nothing and exit 0.
- [ ] **AC9 (prompt seam, static):** the new test pins that `loomwright/agents/worker.md` Step 5 invokes `worker-rule-selfcheck.sh` with `--root`, that Step 5.7 names the `rule:` prefix, and that the new text says REPORT-ONLY. Deleting the invocation from a temp copy of `worker.md` makes that pin fail (gated mutant, as AC7).
- [ ] **AC10 (docs):** every UPDATE row of decision 7's per-surface table carries `rule:` (and the reviewer-facing rows carry the "not an acceptance-criterion contradiction by default" clause), every LEAVE row is unchanged, and a repo-wide `plan:` grep under `loomwright/` finds no WORKER_RESULT-scoped prefix list missing `rule:`; every `--if-stamped` consumer enumeration in decision 6 names the worker helper, and a repo-wide grep (`ONE stage|exactly one advisory seam|both at Phase 4.5|READER only`) finds no surface still claiming Phase 4.5 is the only stage that runs `rules-check.sh` with execution enabled. `scripts/check-contract-parity.sh` is green with the WORKER_RESULT MANIFEST row unchanged (no new field, `schema_version` stays 2).
- [ ] **AC11 (budget + release):** `scripts/check-token-budget.sh` green (raise per decision 8 only when the rule there fires); version 15.110.0 in `plugin.json` + `marketplace.json`; new top CHANGELOG entry; `scripts/check-doc-currency.sh` green.
- [ ] **AC12 (full loop green):** run under `bash`: every `loomwright/scripts/test-*.sh`, `loomwright/scripts/adapters/*/test-*.sh` and root `scripts/test-*.sh`; plus `scripts/check-vendor-coupling.sh`, `scripts/check-doc-currency.sh`, `scripts/check-command-sync.sh`, `scripts/check-skills-index-sync.sh`, `scripts/check-token-budget.sh`, `scripts/check-test-hermetic.sh`, `scripts/check-contract-parity.sh`, and `loomwright/scripts/test-citation-drift.sh`. The new test sources `hermetic-test-env.sh` as its first executable line (the #290 ratchet).
- [ ] **Invariants:** `rules-check.sh` remains the only file that executes a rule `check` (grep `bash -c` over `loomwright/scripts/*.sh` shows no new executor). No change to `rules-check.sh` code (header comment only). The `gh pr merge --squash` positive grep resolves to the same 5 surfaces. No new agent/command/skill/hook; no WORKER_RESULT field or `schema_version` change.

## Non-goals
- Path scoping for `rules-check.sh` (explicitly refused by the requirement: execution is repo-wide; routing is an emission filter only).
- Any new WORKER_RESULT field or `schema_version` bump.
- Making a rule failure block the worker, the review, or the merge (item 07). Re-auditing the store at Phase 4.5 (item 09).
- Changing the worker's spawn-time advisory `read-rules.sh` paste (`skills/async-orchestration/SKILL.md`) or the Phase 4.5 replay.
- Re-deriving `twin-remediation/03`'s classification table (prior art; honour its "no new gating paths" non-goal — this item adds none).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Helper `worker-rule-selfcheck.sh` + its self-test (AC1–AC8 behaviour, canary, bound, forgery, mutation) + `rules-check.sh` header consumer comment | AC1–AC8, AC12 (scripts), Invariants | 1 modify (comment-only), 2 create | unit-testing, quality-checklist | LAUNCHABLE |
| 2 | Worker prompt Step 5 / 5.7 / Output Format, prompt-seam pin (AC9) added to the Subtask-1 test, prefix surfaces (decision 7), consumer lists (decision 6), budgets, version + CHANGELOG | AC9–AC12, Invariants | 15 modify (incl. the shared test file and `commands/dreaming.md`), 0 create | quality-checklist, unit-testing | BLOCKED (by #1) |

- **Split reason:** context-bound (17 distinct files > 12). Sequential: Subtask 2's worker text cites the helper path and its output contract, which Subtask 1 creates.

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/worker-rule-selfcheck.sh"}
  - {kind: "file", path: "loomwright/scripts/test-worker-rule-selfcheck.sh"}
  - {kind: "symbol", path: "loomwright/scripts/worker-rule-selfcheck.sh", name: "stamped must-check fails"}
  - {kind: "symbol", path: "loomwright/scripts/worker-rule-selfcheck.sh", name: "more failing stamped must-checks"}
  - {kind: "symbol", path: "loomwright/scripts/test-worker-rule-selfcheck.sh", name: "CANARY"}
  - {kind: "symbol", path: "loomwright/scripts/rules-check.sh", name: "worker-rule-selfcheck.sh"}
requires: []
lanes:
  - "loomwright/scripts/worker-rule-selfcheck.sh"
  - "loomwright/scripts/test-worker-rule-selfcheck.sh"
  - "loomwright/scripts/rules-check.sh"
external_requires: []

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/agents/worker.md", name: "worker-rule-selfcheck.sh"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "worker-rule-selfcheck.sh"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "worker-rule-selfcheck.sh"}
  - {kind: "symbol", path: "loomwright/skills/rules/SKILL.md", name: "worker-rule-selfcheck.sh"}
  - {kind: "symbol", path: "loomwright/commands/rules.md", name: "worker-rule-selfcheck.sh"}
  - {kind: "symbol", path: "loomwright/.claude-plugin/plugin.json", name: "15.110.0"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/worker-rule-selfcheck.sh"}
  - {from: "1", kind: "file", path: "loomwright/scripts/test-worker-rule-selfcheck.sh"}
lanes:
  - "loomwright/agents/worker.md"
  - "loomwright/scripts/test-worker-rule-selfcheck.sh"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/skills/rules/SKILL.md"
  - "loomwright/commands/rules.md"
  - "loomwright/commands/dreaming.md"
  - "loomwright/agents/code-reviewer.md"
  - "loomwright/skills/quality-checklist/SKILL.md"
  - "loomwright/scripts/validate-worker-result.py"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

## Parallelism Analysis
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1 — its `requires` name Subtask 1's helper and test files; it also appends the AC9 prompt-seam pin to Subtask 1's test)
- **Recommended workers:** 1 (sequential)
- **Estimated batches:** 2

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| helper (S1) | `loomwright/scripts/rules-check.sh` (header comment only) | `loomwright/scripts/worker-rule-selfcheck.sh`, `loomwright/scripts/test-worker-rule-selfcheck.sh` | HIGH |
| prompt (S2) | `loomwright/agents/worker.md`, `loomwright/scripts/test-worker-rule-selfcheck.sh` (append AC9 pin) | — | HIGH |
| docs (S2) | `loomwright/docs/RESULT_SCHEMAS.md`, `loomwright/skills/self-heal-advisory/SKILL.md`, `loomwright/skills/rules/SKILL.md`, `loomwright/commands/rules.md`, `loomwright/commands/dreaming.md`, `loomwright/agents/code-reviewer.md`, `loomwright/skills/quality-checklist/SKILL.md`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (Worker row), `loomwright/scripts/validate-worker-result.py` (docstring only) | — | HIGH |
| release (S2) | `loomwright/docs/prompt-token-budgets.json`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` budget mirror rows (MEDIUM — only if a budget raise rule fires), `CHANGELOG.md`, `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | — | HIGH |

> **Validator-owned surfaces:** AC10–AC12 depend on `scripts/check-doc-currency.sh`, `scripts/check-token-budget.sh`, `scripts/check-contract-parity.sh`, `scripts/check-test-hermetic.sh` and `loomwright/scripts/test-citation-drift.sh`. Any pinned `file:N` citation into an edited file (e.g. into `RESULT_SCHEMAS.md`, `rules/SKILL.md`, `self-heal-advisory/SKILL.md`) must still resolve after the edit; run the citation-drift test after the last prose edit.

## Skill References
- `skills/unit-testing/SKILL.md` (Subtasks 1, 2 — bash self-tests, sandbox `HOME` + `git init`, gated mutants)
- `skills/quality-checklist/SKILL.md` (Subtasks 1, 2)
- `skills/rules/SKILL.md` §8/§8.1/§8.2 (`--if-stamped`, the git-common-dir stamp key, `--list-selected`) and §9 (trust boundary) — read before writing the helper
- `loomwright/scripts/run-ground-truth.sh` (its `rule:` resolution is the parse pattern to mirror) and `loomwright/scripts/test-rules-check.sh` (sandbox + stamp harness to reuse)
- `loomwright/scripts/test-result-validators.sh` (how tests drive `validate-worker-result.py`)

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

> Advisory only (no `must` rules apply, so no `rule:` bullets). Applied here: the consumer enumerations that restate "who calls `--if-stamped`" are updated in the same change (decision 6), and prose avoids restating a literal consumer count where a list suffices. The helper's line bound (3 + 1) is defined ONCE, in RESULT_SCHEMAS.md, and the worker prompt points there.

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| The helper grows its own store read or `bash -c` (a second executor, breaking the §9 trust boundary) | HIGH | Decision 2 + AC6 grep + Invariants grep; `--list-selected` exists so the helper never reads the store. |
| An ambient `RULES_CHECK_CONFIRM=1` in a worker's environment launders an unstamped run | HIGH | Already neutralized inside `rules-check.sh` when `--if-stamped` is on argv (PR #267); the helper never passes `--confirm`; AC3 has an explicit env-var leg asserting CANARY stays absent. |
| A crafted stamped check forges output (embedded `[PASS]`, pre-print-then-kill, a forged `[SKIP] all (unstamped)` or `(cmd execution disabled)` line) to hide its own failure | MEDIUM | Decision 3: exact whole-line matches, the `Checks passed: N/M` trailer rule, unstamped-silence only with no `[RUN ]` lines, no-cmd decided from the env not the output; AC6 legs (i)–(iv). Residual (a fully self-consistent forgery inside one confirmed check) documented in the header. |
| `test-rules-seams.sh` seam_b fails if any line of `skills/self-heal-advisory/SKILL.md` naming `rules-check.sh` also contains `--confirm`, or a `bash … rules-check.sh` line lacks `--if-stamped` | MEDIUM | New prose in that file names only `worker-rule-selfcheck.sh`; never put `--confirm` on a line that mentions `rules-check.sh`. Run `test-rules-seams.sh` after the edit. |
| `code-reviewer.md` has 115 tokens of headroom | MEDIUM | Decision 7 replaces its literal prefix list with a pointer (net shrink target); decision 8 raise rule otherwise. |
| Existing tests pin the old four-prefix list (`test-deviations-advisory-seam.sh`, `test-result-validators.sh`) | LOW | Decision 7: insert `rule:` after `test:` and before `other:` so ordered globs keep matching. |
| ~500-char live ids overflow the 200-char entry bound and make WORKER_RESULT fail rule 10 (re-prompt loop) | MEDIUM | Decision 4 character-aware truncation with `…`; AC4 asserts ≤200 characters with a >200-char id and runs the real validator. |
| Multibyte `…` measured in bytes by a BSD tool under bash 3.2 | MEDIUM | Decision 4: character-aware method + portable character counter in the test; run under `bash` on macOS. |
| The worker parses raw checker output itself instead of the helper (untestable drift) | MEDIUM | Decision 1/5: the prompt says copy the helper's lines verbatim; AC9 pins the invocation. |
| `worker.md` token budget breach (437 headroom at base) | MEDIUM | Decision 5 keeps prose minimal; decision 8 raise rule; AC11. |
| A consumer enumeration is missed (a stale "Phase 4.5 only" claim survives) | LOW | Decision 6: grep `--if-stamped` repo-wide, not only the known list. |
| Worker turn limit (items 02/04 hit 40 turns) | LOW | Context-bound split; resume via SendMessage on a turn-limit, never respawn. |

## Configuration
- **Mode:** sequential
- **Recommended workers:** 1
- **Estimated batches:** 2
- **Split reason:** context-bound

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-09-28-worker-rule-self-check.md

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/294 (merged 6f857fc, 2026-09-28)
- **Branch:** feature/automate-followups-06-worker-rule-self-check
- **Files changed:** 18
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** New `scripts/worker-rule-selfcheck.sh` (always exits 0) delegates to `rules-check.sh --list-selected` + `--if-stamped` (never `--confirm`; skipped entirely under `RULES_CHECK_NO_CMD=1`), parses the replay fail-closed (whole-line fixed-string matches, the `Checks passed: N/M` trailer + rc 0|1 gate, unstamped silence only with no `[RUN ]` line), and prints at most 4 `rule:` lines of at most 200 characters each. `agents/worker.md` Step 5 runs it (fix in lane, re-run once, copy the final lines into the REPORT-ONLY `deviations`); `rule:` is the fifth deviations prefix on every WORKER_RESULT surface, and every `--if-stamped` consumer enumeration names the worker helper. Version 15.110.0, delivered in 2 sequential subtasks, committed together as 9847075 (Subtask 2's worker hit the 40-turn limit and was resumed). Plan Review PASSed on attempt 3/3. Phase 4.5 review FAILed on iteration 1: HIGH vendor-coupling breach from the new test's stamp-path literal (CI red; the local pre-`git add` check missed it), MEDIUM untested rc-guard/trailer-count branches, LOW CDPATH stdout leak, LOW qa-executor headroom. All were fixed in 1f024cd, and the re-review PASSed. The owned drain was READY after 2 rounds, with 1 fix cycle (5ec599e: claude-review's two LOW nits, the CHANGELOG qa-executor raise and the ac9 awk anchor). risk_classification high_risk=true. Pre-existing environment-only failure: orca-mirror case L.

## Not verified
- **The worker Step 5 self-check in a live run.** The live `.agent/rules/` store holds 0 `must` rules, so the helper is covered only by sandbox tests and the prompt seam only by a static pin.
- **The CDPATH fix on the helper's `HERE=` line.** It has no test; the re-review rated this LOW. The only caller passes an absolute `${CLAUDE_PLUGIN_ROOT}` path, which CDPATH never applies to.
- **The new Step 5 on the installed agent.** The installed plugin cache (15.108.4) predates this until it is updated.
