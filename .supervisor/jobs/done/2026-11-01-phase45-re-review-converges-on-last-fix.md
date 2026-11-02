# Supervisor Job: Phase 4.5 re-reviews converge on what the last fix changed

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-11-01-195532/L1
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/2026-11-01-092114-phase-4-5-re-reviews-converge-on-what-the-last-fix-changed.md
- **Base commit:** 26eda742b616a339f971b34b5b7d8740c9654851

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe shell + `jq` + `git`, the same stack as every `loomwright/scripts/*.sh` helper |
| 2 | Dependency Availability | GO | no new dependency; the fingerprint hash uses `git hash-object --stdin` (git is always present), so no `shasum`/`sha256sum` portability copy is added |
| 3 | Architecture Fit | GO | deterministic helper beside the prose loop, the `fix-floor.sh` / `run-pin-mutations.sh` / `module-shape-facts.sh` pattern; config key resolved in `supervisor-config` like step 2.10 |
| 4 | Scope vs Supervisor Capability | CAUTION | 8 modify + 6 create, ~1,150 changed lines est. — over the `context-bound` bound, so a 2-subtask sequential split |
| 5 | Hard Blockers | CAUTION | Validation 2a (a real headless `/automate` item run with `--plugin-dir` in `shadow`) is a multi-hour live run a worker may not be able to complete in-session |

**Overall Verdict:** CAUTION

## Task
**Goal:** Make every Supervisor Phase 4.5 heal round after the first review only the files the previous fix changed (read whole) and never re-report a finding already fixed or dismissed in the run, shipped behind a `heal_review_scope` config key that defaults to `shadow` so the effect is measured before any review is narrowed.

**Problem Statement:**
The plugin owner running `/automate` and `/supervisor` needs heal rounds ≥ 2 to converge on what the last fix changed because every round today re-reviews the whole PR.
Currently, the Phase 4.5 reviewer prompt in `loomwright/skills/self-heal-advisory/SKILL.md` sets the scope to `git diff origin/$BASE_BRANCH...HEAD` on every iteration and says "look for everything"; dismissed findings are not handed back to the next round. Items on plugin ≥ 17.2.0 ran heal fix rounds 0/1/2/3 = 1/3/7/5 of 16, with Phase 4.5 durations up to 2h 27m (`docs/evidence/review-gate-rounds.md`).
Success looks like: rounds ≥ 2 record what a files-scoped review would have covered (`shadow`, the default), the owner can read `heal-review-scope.sh --shadow-report` as promotion evidence, and `files` mode narrows rounds ≥ 2 and drops exact repeats — with round 1 and `full` byte-identical to today, and catch rate not traded for speed.

**Owner decision carried from the requirement (D1, 2026-11-01):** the round ≥ 2 scope is every file the previous round's fix commit(s) changed, reviewed in full, and nothing else — not hunk-only, not the full PR diff.

**Owner decision D2 (2026-11-01, Launch Pad Phase 6 `LP-SAVE-NOTE` → "Refine further"; narrows requirement Part B's DO-NOT-REPORT and AC3):** repeat suppression applies to **`dismissed`** fingerprints only. A re-reported **`fixed`** fingerprint usually means the fix did not work, so it stays a normal finding that reaches the fix task, and is counted as `repeat_of_fixed` on the round record (the shadow report lists each one). Suppression therefore never changes `iter_decision` or `heal_decision`: there is no "all suppressed ⇒ PASS" rule.

**Design decisions this brief makes (the requirement left them open):**
- **Record file:** `.supervisor/heal-rounds/<brief basename without .md>.jsonl`, gitignored (all of `.supervisor/` is), named like the Phase 4.5 pin-mutation cache `.supervisor/pin-mutations/<brief basename without .md>.tsv`. Every record carries `run_id` = the run's `state.md` `## Session` `session_id`, which stays the same on `--continue`, so a re-run of the same brief appends under a new `run_id`, and `suppress` / `prev-sha` read only the current run's records. The record schema lives in `heal-review-scope.sh`'s header (the authority). `loomwright/docs/result-schemas/supervisor-result.md` carries a pointer subsection that names the file and its fail-SAFE writer and does not restate the value sets.
- **Fingerprint triple for a Phase 4.5 finding:** `CODE_REVIEW_RESULT` issues carry no `rule` field (the issue key set is closed: `ISSUE_KEYS = ("severity", "category", "drift_kind", "file", "line", "description", "suggestion")` in `validate-code-review-result.py`). So `file` = `issue.file`; `issue_category` = `issue.category`, or `drift:<drift_kind>` when `category: drift`; `rule` = the first 12 hex chars of `git hash-object --stdin` over the description lower-cased with whitespace runs collapsed to one space. This mirrors `review-heal-next-step.sh`'s fallback fingerprint (`(.fingerprint // (.source + "|" + .finding))`), stores no finding prose (only the hash), and matches exact repeats only — a reworded repeat under-fires, which only makes the review report more. No reviewer schema change.

## Acceptance Criteria

**Happy path**
- [ ] AC1 — Given round 1 of a Phase 4.5 loop, when the reviewer is spawned, then its scope is the full `origin/$BASE_BRANCH...HEAD` diff, unchanged from today (the round-1 prompt is byte-identical to the base prompt — AC15's seam test).
- [ ] AC2 — Given `heal_review_scope: files` and round 2 after a fix commit that changed files X and Y, when the reviewer is spawned, then its scope names exactly X and Y, each to be read whole, and the prompt says to report only findings in them (the full PR diff stays read-only context for intent).
- [ ] AC3 — Given `heal_review_scope: files` and a finding fingerprint fixed in round 1, when round 2's reviewer reports the same fingerprint, then it is NOT dropped: it reaches the fix task as a normal finding, and the round's record counts it as `repeat_of_fixed` (owner decision D2). The DO-NOT-REPORT block never lists `fixed` fingerprints.
- [ ] AC4 — Given no `heal_review_scope` key (the shipped default, `shadow`), when round 2 runs, then the reviewer's prompt and the fix task's input are identical to `full`, and the round's records carry `would_scope`, `in_would_scope` per finding and `would_suppress`.
- [ ] AC5 — Given shadow records from several items, when `heal-review-scope.sh --shadow-report` runs, then it prints the total findings over rounds ≥ 2, the outside-scope findings each with fingerprint and PR, the would-suppress count with each would-suppress fingerprint and PR, the `repeat_of_fixed` fingerprints each with PR, and the estimated skipped review minutes. It writes nothing.
- [ ] AC6 — Given `heal_review_scope: full` or an unknown/malformed value, when any round runs, then the helper's `scope` and `suppress` subcommands are not called and the round is today's full review.
- [ ] AC7 — Given `heal_review_scope: files` and a finding dismissed in round 1, when it is reported again at a severity no higher than the dismissed record's, then it is dropped before `fixable_issues` and `heal_dismissed` are built, counted as `suppressed_repeat`, and stays in `heal_dismissed` exactly once. A re-report at a HIGHER severity is a normal finding (never suppressed). A dismissed fingerprint from an EARLIER run (a different `run_id`) is never suppressed.
- [ ] AC8 — Given any heal round, when it ends, then the record file holds one `finding` record per actionable or dismissed finding with `run_id`, `iteration`, `reviewed_sha`, `file`, `issue_category`, `rule`, `severity` and `outcome` (`fixed` | `dismissed` | `remaining`), plus one `round` record — and no finding prose.

**Edge cases**
- [ ] AC9 — Given the previous reviewed sha is not an ancestor of HEAD, when round N starts, then the round runs the full scope and records `scope_fallback: not_ancestor`.
- [ ] AC10 — Given the fix commit only deleted files or left no file to scope, when round N starts, then the round runs the full scope and records `scope_fallback: empty_scope`.
- [ ] AC11 — Given the commits in `<prev_sha>..HEAD` include a merge commit, when round N starts, then the round runs the full scope and records `scope_fallback: merge_commit`; given no previous reviewed sha is recorded (missing/unreadable record file), it records `scope_fallback: missing_prev_sha`.
- [ ] AC12 — Given stacked mode (`STACKED=true`), when round ≥ 2 runs under `files`, then the same file scoping applies inside the stacked diff (the scope helper reads `<prev_sha>..HEAD`, independent of the base).

**Error scenarios**
- [ ] AC13 — Given `heal-review-scope.sh` is missing or exits non-zero, when round N starts, then the full scope is used and `scope_fallback: helper_error` recorded. The loop never stops on this.
- [ ] AC14 — Given a record write fails, when the round continues, then the loop is unaffected and one `record_decision` line names the failure (`heal_round_record_failed: <reason>`).

**Validation (from the requirement — must pass before merge)**
- [ ] AC15 — `loomwright/scripts/test-heal-review-scope.sh` covers: round 1 → `full`; a two-commit scratch repo → exactly the changed files; deleted file excluded; non-ancestor → fallback; merge fix commit → fallback; deletion-only → fallback; `mode` resolution (absent → `shadow`, `files`, `full`, unknown → `full`, malformed JSON → `full`); `suppress` drops a same-run dismissed fingerprint, and does NOT drop a fixed fingerprint (it counts it `repeat_of_fixed`), a dismissed fingerprint re-reported at a higher severity, or a dismissed fingerprint recorded under a different `run_id`; `prev-sha` ignores another run's round records; `record` rejects a record carrying a prose key; `--shadow-report` output and that it writes nothing. Each scope case runs as a mutation control: the test FAILS when `scope` is edited to print `scope: full` always (each mutant checked non-empty, different from the original, and `bash -n` clean before trusting it).
- [ ] AC16 — A prompt-seam test `loomwright/scripts/test-heal-review-scope-seam.sh` (pattern: `loomwright/scripts/test-execution-directive-seam.sh`) proves the round ≥ 2 prompt under `files` carries the HEAL RE-REVIEW SCOPE block and the DO-NOT-REPORT block, each guarded to `HEAL_REVIEW_SCOPE == files` and `heal_iterations ≥ 1`, and that the reviewer prompt with those two guarded lines removed is byte-identical to the base prompt committed as `loomwright/scripts/fixtures/phase45-reviewer-prompt-base.txt` (so round 1 under every mode, and every round under `shadow` and `full`, is today's prompt). It also asserts that the HEAL RE-REVIEW SCOPE line and the `agents/code-reviewer.md` paragraph each carry the precedence sentence: for REPORTING only, it overrides the DIFF-SCOPE OVERRIDE and the "look for everything" sentence, and the full diff stays read-only context. It asserts that the DO-NOT-REPORT line lists dismissed fingerprints only. On a byte-identity failure it prints the exact command that regenerates the fixture. It includes mutation controls (an unguarded copy, a copy with the scope line deleted, a copy without the precedence sentence) that turn it red.
- [ ] AC17 — Given the pre-release run (requirement Validation 2a: one real `/automate` item run headless with `claude -p --plugin-dir <this branch>/loomwright` in `shadow` mode), when it completes, then a committed evidence file `docs/evidence/phase45-converging-re-review.md` contains that item's record-file lines and the `heal-review-scope.sh --shadow-report` output (or, if no round ≥ 2 happened, says so and carries a second item's), and the PR body links to it.
- [ ] AC18 — Token budgets for every edited skill dir and agent stay within budget: `bash scripts/check-token-budget.sh` passes, with any raised `.skills[...]`/`.agents[...]` entry in `loomwright/docs/prompt-token-budgets.json` and its mirror row in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" changed in the same edit (a one-line `note`).
- [ ] AC19 — `bash scripts/check-version-bump.sh` passes and `bash scripts/ci-local.sh --affected` is green.

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

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| helper | — | `loomwright/scripts/heal-review-scope.sh` (new module: mode / scope / record / suppress / `--shadow-report` — one home for every deterministic step) | HIGH |
| helper-tests | — | `loomwright/scripts/test-heal-review-scope.sh` | HIGH |
| loop-wiring | `loomwright/skills/self-heal-advisory/SKILL.md` (421 — appended: the review-and-fix loop is the single authority for per-iteration steps; stays under 500) | — | HIGH |
| config | `loomwright/skills/supervisor-config/SKILL.md` (92 — new step 2.11 beside step 2.10, the config-resolution authority) | — | HIGH |
| reviewer | `loomwright/agents/code-reviewer.md` (444 — one paragraph in §"Review Modes & Scope Expansion": the scope block's reporting rule) | — | HIGH |
| schema | `loomwright/docs/result-schemas/supervisor-result.md` (231 — the owning schema doc; new subsection for the record file) | — | HIGH |
| budgets | `loomwright/docs/prompt-token-budgets.json` (93), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1051 — appended to the mirror rows only: the single §"Prompt Token Budgets" mirror authority) | — | HIGH |
| inventory | `loomwright/docs/loop-inventory/supervisor.md` (1326 — appended rows + `## Counts`/gap list: the inventory is the single table `test-loop-inventory.sh` checks) | — | MEDIUM |
| seam-test | — | `loomwright/scripts/test-heal-review-scope-seam.sh`, `loomwright/scripts/fixtures/phase45-reviewer-prompt-base.txt` (base reviewer prompt, extracted from SKILL.md at the base commit) | HIGH |
| user-doc | `loomwright/commands/supervisor.md` (one sentence in the `**Phase 4.5:**` paragraph pointing at supervisor-config step 2.11 for `heal_review_scope`; 818 proxy tokens of command headroom at base) | — | HIGH |
| release | — | `changelog.d/phase45-converging-re-review.md`, `docs/evidence/phase45-converging-re-review.md` | HIGH |

> **Validator-owned surfaces:** `scripts/check-token-budget.sh` (reads `prompt-token-budgets.json` + the ARCHITECTURE_CONTRACTS mirror rows), `loomwright/scripts/test-loop-inventory.sh` (every new `###`/`####` heading in `self-heal-advisory/SKILL.md` needs an `h:` row in `loop-inventory/supervisor.md`, and `## Counts` must equal the table), `scripts/check-doc-currency.sh` (doc surface). All folded into the map above.

**Module layout:** every new responsibility has one home — the deterministic scope/record/suppress/report logic is the CREATE `heal-review-scope.sh`; the per-iteration wiring is appended to the loop in `self-heal-advisory/SKILL.md` (421 lines, under the 500-line threshold, with a stated reason); the record schema extends the owning `supervisor-result.md`. No helper is copied: the fingerprint hash uses `git hash-object --stdin` instead of a fourth copy of the `shasum`/`sha256sum` idiom; config resolution uses `jq` directly with the `if has("heal_review_scope")` form (never `// empty`). The two size-past-threshold MODIFY paths (`ARCHITECTURE_CONTRACTS.md`, `loop-inventory/supervisor.md`) receive only table rows, each the single authority for that table.

**Total estimated files:** 8 modify + 6 create

## Touched-file invariants

> Grounded at base `26eda742b616a339f971b34b5b7d8740c9654851`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/skills/self-heal-advisory/SKILL.md`** — keep: the advisory contract `**HARD ADVISORY CONTRACT (applies to every advisory step in every file of this skill):**` — record writes and shadow counts are advisory and fail-safe, never change `heal_decision`; keep the prompt-line order pinned by tests — `**ANTI-OVERLAP (every iteration` is directly followed by `**EXECUTION DIRECTIVE (every iteration — Phase 4.5 only):**`, and `**PIN-MUTATION VERDICTS (DATA` follows the DEVIATIONS ADVISORY line; insert the two new guarded lines AFTER `**MODULE-SHAPE ADVISORY (DATA, a hint` and BEFORE `BASE_BRANCH={BASE_BRANCH}`, each with the same "include this line ONLY when … ; omit entirely when …" guard idiom the advisory lines use; keep `heal_dismissed += [` itemising only non-suppressed issues (AC7); keep the round cap `max_heal_iterations = {--heal-iterations value, default 3}`, the fix task's step 1a `**Fix the CLASS, not just the flagged instance`, and the PIN MUTATIONS once-per-code-state call `--cache .supervisor/pin-mutations/{brief basename without .md}.tsv --budget 540` unchanged; reuse: invoke the helper "from the plugin install root like every other script in this file" (`<plugin root>/scripts/…`), and log via `record_decision(phase: SELF_HEAL, …)`; pinned by: `loomwright/scripts/test-execution-directive-seam.sh` (`DIRECTIVE_PREFIX='**EXECUTION DIRECTIVE (every iteration'`), `loomwright/scripts/test-module-shape-facts.sh` (`'**MODULE-SHAPE ADVISORY ('`), `loomwright/scripts/test-phase45-rounds-seam.sh`, `loomwright/scripts/test-deviations-advisory-seam.sh`, `loomwright/scripts/test-brief-conformance-seam.sh`, `loomwright/scripts/test-loop-inventory.sh` (heading coverage), `scripts/check-token-budget.sh`, and (new) `loomwright/scripts/test-heal-review-scope-seam.sh` with its frozen base prompt `loomwright/scripts/fixtures/phase45-reviewer-prompt-base.txt` — any later edit to the reviewer Task prompt must regenerate that fixture in the same change (the seam test prints the command).
- **`loomwright/commands/supervisor.md`** — keep: the `**Phase 4.5:**` paragraph's existing claims; add one sentence only; pinned by: `scripts/check-token-budget.sh` (command row `supervisor`, 818 headroom at base), `scripts/check-doc-currency.sh`.
- **`loomwright/skills/supervisor-config/SKILL.md`** — keep: step 2.10's resolve-by-script idiom `2.10. Resolve the **fix floor**` (resolve once at INIT, record the value, consumed by Phase 4.5); the new step 2.11 records `HEAL_REVIEW_SCOPE` from `heal-review-scope.sh mode --root .` and never stops the run (unknown ⇒ `full`, unlike fix-floor's exit 2 — a config error here may only widen a review); keep the driver note that steps `5a.2.6–5a.2.10 (the Phase 4.5 flags …)` stay the Supervisor's own — extend that range to 5a.2.11; pinned by: `loomwright/scripts/test-non-interactive-gates-seam.sh` (`init_input_missing_non_interactive`), `loomwright/scripts/test-run-lock.sh`, `loomwright/scripts/test-check-contract-parity.sh`.
- **`loomwright/agents/code-reviewer.md`** — keep: `**Diff-first, expand when needed:**` and `Record every expansion in \`scope_expanded[]\`` (under the scope block, reading beyond the listed files is still allowed and recorded; only REPORTING is limited to them); keep the scratch-dir carve-out sentence byte-identical in both of its copies (`**Mutation guardrails (NON-NEGOTIABLE` and `**Read-only via Bash too:**`); mirror: the new paragraph names the prompt line exactly as SKILL.md spells it (`HEAL RE-REVIEW SCOPE`); pinned by: `loomwright/scripts/test-execution-directive-seam.sh` (`CARVE='Scratch-dir exception`), `loomwright/scripts/test-module-shape-facts.sh` (`MODULE-SHAPE ADVISORY`), `loomwright/scripts/test-validate-code-review-result.sh`, `scripts/check-token-budget.sh` (agent row `code-reviewer`, 1160 headroom at base).
- **`loomwright/docs/result-schemas/supervisor-result.md`** — keep: `heal_dismissed: [{finding: string, reason: string, source: string, severity?: string}]` and its closed `reason` enum `pre_existing | nit | drift | below_severity_floor` unchanged (suppression is not a new dismissal reason — a suppressed repeat never enters `heal_dismissed`); the record file is NOT a `SUPERVISOR_RESULT` field (no `schema_version` bump, nothing added to `scripts/result_nested_keys.py`); pinned by: `loomwright/scripts/test-supervisor-next-step.sh`, `loomwright/scripts/test-classify-risk.sh`.
- **`loomwright/docs/prompt-token-budgets.json` + `loomwright/docs/ARCHITECTURE_CONTRACTS.md`** — keep: the JSON and its mirror row change together (`"self-heal-advisory": {"budget": 37695` ↔ `| \`self-heal-advisory\` | 37695 | 34268 |`); a raise carries a ONE-line `note` under 200 chars; `self-heal-advisory` has 776 proxy tokens of headroom at base, so this change will breach it and must raise it; pinned by: `scripts/check-token-budget.sh`, `scripts/test-check-token-budget.sh`.
- **`loomwright/docs/loop-inventory/supervisor.md`** — keep: the nine-column table, `SV-NNN` ids never reused, the `## Counts` lines (`- rows: 777` at base) equal to the table, and every GAP row named once in the gap list; a new row's `q:` anchor (≥ 12 chars) must be a substring of one line of its file; pinned by: `loomwright/scripts/test-loop-inventory.sh`.

## Closed enumerations touched

> Sibling grep at base `26eda742b616a339f971b34b5b7d8740c9654851`: `grep -rnF '.fix_floor' --exclude=CHANGELOG.md loomwright/ scripts/ README.md CLAUDE.md` → 22 hits in 14 files (config-key sibling); `grep -rnF 'multi_voter_heal' --exclude=CHANGELOG.md .` (outside `.supervisor/` and fixtures) → 6 hits in 6 files.

- **`heal_review_scope`** (config key; sibling: `.fix_floor` / `.multi_voter_heal`) — must be named in:
  - `loomwright/skills/supervisor-config/SKILL.md` — the Phase 0 INIT resolution steps (`2.10. Resolve the **fix floor**`) — extend (new step 2.11).
  - `loomwright/docs/loop-inventory/supervisor.md` — per-branch rows (`SV-513` names `.multi_voter_heal`) — extend (rows for the three modes and the fallback branch).
  - `loomwright/commands/supervisor.md` — the user-facing `**Phase 4.5:**` paragraph — extend (one sentence pointing at step 2.11; not a closed list, but the owner's only user-facing route to the key).
  - `loomwright/commands/review-pr.md`, `loomwright/commands/launch-pad.md`, `loomwright/skills/review-heal/SKILL.md`, `loomwright/skills/automate-loop/invariants.md`, `loomwright/agents/launch-pad.md`, `loomwright/docs/rationale/supervisor.md`, `loomwright/scripts/dispatch-pr-review.sh`, `loomwright/scripts/fix-floor.sh`, `loomwright/scripts/test-fix-floor.sh`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (line 165 self-heal pattern), `loomwright/docs/loop-inventory/{review-heal,automate-loop}.md` — no change: each names `.fix_floor` / `--fix-floor` because that setting governs Launch Pad and `/review-pr` too or is a CLI flag; `heal_review_scope` is a Phase 4.5-only config key with no flag and no drain or Launch Pad consumer (the requirement's Non-goals exclude the `/review-pr` drain).
- **`heal_review_scope` values `shadow` | `files` | `full`** and **`scope_fallback` reasons `not_ancestor` | `empty_scope` | `merge_commit` | `missing_prev_sha` | `helper_error`** — new closed sets with no existing sibling; defined ONCE in `heal-review-scope.sh`'s header; `supervisor-result.md` points at that header and does not restate them (house rule on restated lists).
- **Record `outcome` `fixed` | `dismissed` | `remaining`** — new closed set; same single home. Sibling `below_severity_floor` (`heal_dismissed.reason`) is NOT extended: a suppressed repeat is counted on the round record, never itemised as a dismissal.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-heal-review-scope.sh` — two-commit scratch repo → exactly the changed files | make the `scope` arm of `loomwright/scripts/heal-review-scope.sh` print `scope: full` and exit 0 before computing the file list |
| `loomwright/scripts/test-heal-review-scope.sh` — deleted file excluded | delete `--diff-filter=d` in `loomwright/scripts/heal-review-scope.sh` |
| `loomwright/scripts/test-heal-review-scope.sh` — non-ancestor → `scope_fallback: not_ancestor` | delete `merge-base --is-ancestor "$PREV" "$HEAD_SHA"` in `loomwright/scripts/heal-review-scope.sh` |
| `loomwright/scripts/test-heal-review-scope.sh` — merge fix commit → `scope_fallback: merge_commit` | delete `rev-list --merges` in `loomwright/scripts/heal-review-scope.sh` |
| `loomwright/scripts/test-heal-review-scope.sh` — unknown mode → `full` | flip `*) echo full ;;` → `*) echo shadow ;;` in `loomwright/scripts/heal-review-scope.sh` |
| `loomwright/scripts/test-heal-review-scope.sh` — round 1 → `scope: full` with no fallback line | make the round-1 branch of the `scope` arm in `loomwright/scripts/heal-review-scope.sh` fall through to the prev-sha checks (it then prints `scope_fallback: missing_prev_sha`) |
| `loomwright/scripts/test-heal-review-scope.sh` — deletion-only fix → `scope_fallback: empty_scope` | delete `empty_scope` in `loomwright/scripts/heal-review-scope.sh` |
| `loomwright/scripts/test-heal-review-scope.sh` — `-` / missing prev → `scope_fallback: missing_prev_sha` | delete `missing_prev_sha` in `loomwright/scripts/heal-review-scope.sh` |
| `loomwright/scripts/test-heal-review-scope.sh` — absent key → `shadow` | delete `has("heal_review_scope")` in `loomwright/scripts/heal-review-scope.sh` |
| `loomwright/scripts/test-heal-review-scope.sh` — malformed config JSON → `full` | make the `mode` arm of `loomwright/scripts/heal-review-scope.sh` print `shadow` when `jq` fails to parse the config |
| `loomwright/scripts/test-heal-review-scope.sh` — same-run dismissed fingerprint is suppressed | flip `outcome == "dismissed"` → `outcome == "never"` in `loomwright/scripts/heal-review-scope.sh` |
| `loomwright/scripts/test-heal-review-scope.sh` — fixed fingerprint is NOT suppressed (counted `repeat_of_fixed`) | make `suppress` in `loomwright/scripts/heal-review-scope.sh` also match `outcome == "fixed"` records as suppressible |
| `loomwright/scripts/test-heal-review-scope.sh` — another run's dismissed fingerprint is NOT suppressed | delete `.run_id == $run` in `loomwright/scripts/heal-review-scope.sh` |
| `loomwright/scripts/test-heal-review-scope.sh` — `record` refuses a prose key | remove the closed-key-set rejection in the `record` arm of `loomwright/scripts/heal-review-scope.sh` (unknown keys then append) |
| `loomwright/scripts/test-heal-review-scope.sh` — `--shadow-report` writes nothing | add a `touch "$DIR/.report-ran"` at the start of the `--shadow-report` arm in `loomwright/scripts/heal-review-scope.sh` |
| `loomwright/scripts/test-heal-review-scope-seam.sh` — scope line is guarded | strip `include this line ONLY when HEAL_REVIEW_SCOPE == files` from the HEAL RE-REVIEW SCOPE line in `loomwright/skills/self-heal-advisory/SKILL.md` |
| `loomwright/scripts/test-heal-review-scope-seam.sh` — precedence sentence present (SKILL.md and code-reviewer.md) | delete `for REPORTING only` in `loomwright/skills/self-heal-advisory/SKILL.md` |
| `loomwright/scripts/test-heal-review-scope-seam.sh` — `files` round ≥ 2 prompt carries the scope block | delete `**HEAL RE-REVIEW SCOPE (` in `loomwright/skills/self-heal-advisory/SKILL.md` |
| `loomwright/scripts/test-heal-review-scope-seam.sh` — base prompt byte-identity | delete `**DO-NOT-REPORT (` in `loomwright/skills/self-heal-advisory/SKILL.md`, then re-insert it without its `include this line ONLY when` guard (reviewer D1 fallback) |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `heal-review-scope.sh` helper + its unit test | AC5, AC9, AC10, AC11, AC13 (helper side), AC15 | 0 modify, 2 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Phase 4.5 wiring, config key, reviewer rule, schema, budgets, inventory, seam test, release + evidence | AC1–AC4, AC6–AC8, AC12, AC13 (loop side), AC14, AC16–AC19 | 8 modify, 4 create | `skills/self-heal-advisory/SKILL.md`, `skills/supervisor-config/SKILL.md`, `skills/quality-checklist/SKILL.md` | BLOCKED (by #1) |

### Subtask 1 — work detail

Create `loomwright/scripts/heal-review-scope.sh` (bash 3.2 / BSD safe, `set -uo pipefail`, every subcommand exits 0 except a usage error which exits 2; header lists every subcommand, closed set and record field — the single authority):
- `mode [--root <dir>]` → one line `shadow` | `files` | `full`: absent file/key ⇒ `shadow`; `files`/`full`/`shadow` string ⇒ itself; anything else (unknown string, non-string, malformed JSON) ⇒ `full`. Read with `jq` using `if has("heal_review_scope") then … else … end` (never `// empty`).
- `scope --round <N> --prev <sha|-> --head <sha> [--root <dir>]` → line 1 `scope: full` or `scope: files`; under `files`, one repo-relative path per following line (`git diff --name-only --diff-filter=d "$PREV" "$HEAD_SHA"`, sorted, unique); under a fallback, line 2 `scope_fallback: <reason>`. Round 1 ⇒ `scope: full` with NO fallback line. `-`/missing/unresolvable prev ⇒ `missing_prev_sha`; not `git merge-base --is-ancestor "$PREV" "$HEAD_SHA"` ⇒ `not_ancestor`; any `git rev-list --merges "$PREV..$HEAD_SHA"` ⇒ `merge_commit`; empty list ⇒ `empty_scope`.
- `fingerprint` (stdin: one `CODE_REVIEW_RESULT` issue JSON) → `{file, issue_category, rule}` per the brief's §Task design decision.
- `record --file <jsonl>` (stdin: JSON lines) → validates each against the closed key sets for `kind: "round"` (`kind, run_id, iteration, reviewed_sha, pr, mode, scope, scope_files, full_files, would_scope, scope_fallback, would_suppress, suppressed_repeat, repeat_of_fixed, review_started_at, review_ended_at`) and `kind: "finding"` (`kind, run_id, iteration, reviewed_sha, pr, file, issue_category, rule, severity, outcome, fix_commit, in_would_scope`); a record missing `run_id`, or with any other key (e.g. `description`, `suggestion`, `finding`), is refused; appends valid lines with `mkdir -p` of the parent; on ANY failure prints one stderr line `heal_round_record_failed: <reason>` and still exits 0.
- `prev-sha --file <jsonl> --run-id <id>` → the `reviewed_sha` of the current run's last `round` record, or nothing (another run's records are ignored).
- `suppress --file <jsonl> --run-id <id> [--count-only]` (stdin: JSON array of issues) → stdout one JSON object `{kept: [...], suppressed: [{fingerprint}], count: N, repeat_of_fixed: [{fingerprint}]}`. A suppressible repeat is an issue whose fingerprint equals a `finding` record of the SAME `run_id` with `outcome: dismissed`, and whose severity is no higher than that record's (`BLOCKING > HIGH > MEDIUM > LOW`). An issue matching a same-run `outcome: fixed` record is never suppressed: it stays in `kept` and is listed in `repeat_of_fixed` (owner decision D2). `--count-only` keeps every issue (shadow) and reports `count` as the would-suppress number. On any error: every issue kept, `count: 0`, one stderr line, so suppression fails toward reporting more.
- `--shadow-report [--since <sha>] [--dir <dir, default .supervisor/heal-rounds>]` → read-only; over every `round` record with `iteration ≥ 2` and `mode: shadow` (with `--since`: only rounds whose `reviewed_sha` descends from `<sha>`; unreachable shas counted as `unreachable: N`): `rounds`, `findings_total`, `outside_scope` (one line each: fingerprint + PR), `would_suppress` (count, plus one line each: fingerprint + PR), `repeat_of_fixed` (one line each: fingerprint + PR), `skipped_review_minutes_est` (Σ review duration × (1 − scope_files ÷ full_files) over non-fallback rounds, labelled an estimate), `fallbacks` by reason. Writes nothing (the test asserts the tree and the dir are byte-identical after it).

Create `loomwright/scripts/test-heal-review-scope.sh` (self-contained scratch `git init` repos under `mktemp -d`, `git -c user.name=t -c user.email=t@x`, `ok()`/`no()` + `RESULT: N passed, M failed`, sourcing `hermetic-test-env.sh` like its siblings) covering AC15's list, with the `scope: full`-always mutation control.

### Subtask 2 — work detail

1. `skills/supervisor-config/SKILL.md`: step 2.11 resolves `HEAL_REVIEW_SCOPE` once at INIT via `heal-review-scope.sh mode --root .` (missing helper ⇒ `full`); extend the driver note's Phase 4.5 flag range.
2. `skills/self-heal-advisory/SKILL.md` Part 2 loop, one `###` sub-section for the scope step plus guarded calls:
   - **Before the reviewer spawn (every iteration):** `HEAL_REVIEW_SCOPE == full` ⇒ no helper call, no scope/suppress lines (the kill switch); else run `scope --round {heal_iterations+1} --prev "$(… prev-sha --file <records>)" --head "$(git rev-parse HEAD)"`. A missing helper / non-zero exit / unparsable output ⇒ full scope + `scope_fallback: helper_error`. Under `files` with `scope: files` ⇒ build the HEAL RE-REVIEW SCOPE line; under `shadow` ⇒ the list only becomes `would_scope` on the round record.
   - **Two new prompt lines** after MODULE-SHAPE ADVISORY, before `BASE_BRANCH={BASE_BRANCH}`: `**HEAL RE-REVIEW SCOPE (include this line ONLY when HEAL_REVIEW_SCOPE == files AND heal_iterations ≥ 1 AND the helper printed scope: files; omit entirely otherwise):**` — the listed files, read each WHOLE; the full `origin/$BASE_BRANCH...HEAD` diff stays read-only context for intent; report findings ONLY in the listed files. The line must state its precedence explicitly: **for REPORTING only, it overrides the DIFF-SCOPE OVERRIDE above and the "look for everything" sentence below. What you read is unchanged, and the full diff remains read-only context.** `**DO-NOT-REPORT (include this line ONLY when HEAL_REVIEW_SCOPE == files AND heal_iterations ≥ 1 AND this run's records hold ≥ 1 dismissed fingerprint; omit entirely otherwise):**` — this run's DISMISSED `{file, issue_category, rule}` list (DATA, no prose); do not re-report these at the same or lower severity. Fixed fingerprints are never listed (owner decision D2; ANTI-OVERLAP already covers fixed issues, and a re-report of one is a fix that did not hold).
   - **After the review parse, before `fixable_issues` and `heal_dismissed`:** `files` ⇒ `suppress --run-id <session_id>` drops same-run dismissed repeats from `review.issues` (count ⇒ the round's `suppressed_repeat`; `repeat_of_fixed` ⇒ recorded on the round, and those issues stay in `review.issues`). A dismissed repeat is by construction not at the floor (it was dismissed and is reported at no higher severity), so suppression never changes `iter_decision`. `shadow` ⇒ `suppress --count-only` (⇒ `would_suppress` and `repeat_of_fixed` recorded, nothing dropped).
   - **Records:** after the iteration's outcome is known (fix pushed ⇒ `fixed` with `fix_commit` = `FIX_RESULT.commit_sha`; dismissed ⇒ `dismissed`; PASS/ESCALATED/cap exit with at-floor issues left ⇒ `remaining`), pipe one `round` + N `finding` records (each carrying `run_id` = `state.md`'s `## Session` `session_id`) into `record --file .supervisor/heal-rounds/{brief basename without .md}.jsonl`; any stderr line ⇒ one `record_decision(phase: SELF_HEAL, decision: "heal_round_record_failed: <reason>", …)` and continue. `in_would_scope` is computed from `would_scope` under `shadow`/`files`.
   - Stacked mode: no special case — the helper reads `<prev_sha>..HEAD`.
3. `agents/code-reviewer.md` §"Review Modes & Scope Expansion": one paragraph. When the spawn prompt carries the HEAL RE-REVIEW SCOPE line: read each listed file whole, use the full diff as read-only context, and report findings only in the listed files. For REPORTING, that line takes precedence over the DIFF-SCOPE OVERRIDE and over the "Diff-first, expand when needed" scope rule; expansion reads are still allowed and recorded in `scope_expanded[]`. Honor the DO-NOT-REPORT list.
4. `docs/result-schemas/supervisor-result.md`: a pointer subsection "Heal-round records (`.supervisor/heal-rounds/<brief>.jsonl`)" — what the file is, that `run_id` keys it per run, that its writer is fail-SAFE and stores no prose, and that `heal-review-scope.sh`'s header is the single authority for record kinds, fields and value sets (not restated here, per the restated-list house rule).
4a. `commands/supervisor.md` `**Phase 4.5:**` paragraph: one sentence saying rounds ≥ 2 are shaped by `.supervisor/config.json` `heal_review_scope` (`shadow` default; see `skills/supervisor-config/SKILL.md` step 2.11).
5. Budgets (+ mirror rows), loop-inventory rows + counts, the seam test + base-prompt fixture (extract the reviewer Task prompt from SKILL.md at the base commit `26eda74` with `git show 26eda74:loomwright/skills/self-heal-advisory/SKILL.md`), `changelog.d/phase45-converging-re-review.md` (`<!-- bump: minor -->`), the evidence file (AC17), then `bash scripts/bump-version.sh` so `bash scripts/check-version-bump.sh` passes.

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/heal-review-scope.sh"}
  - {kind: "symbol", path: "loomwright/scripts/heal-review-scope.sh", name: "scope_fallback"}
  - {kind: "symbol", path: "loomwright/scripts/heal-review-scope.sh", name: "--shadow-report"}
  - {kind: "file", path: "loomwright/scripts/test-heal-review-scope.sh"}
requires: []
lanes:
  - "loomwright/scripts/heal-review-scope.sh"
  - "loomwright/scripts/test-heal-review-scope.sh"
external_requires:
  - "jq (already required by sibling scripts)"
  - "git (merge-base --is-ancestor, rev-list --merges, hash-object --stdin)"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "HEAL RE-REVIEW SCOPE"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "DO-NOT-REPORT"}
  - {kind: "symbol", path: "loomwright/skills/supervisor-config/SKILL.md", name: "HEAL_REVIEW_SCOPE"}
  - {kind: "symbol", path: "loomwright/agents/code-reviewer.md", name: "HEAL RE-REVIEW SCOPE"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/supervisor-result.md", name: "heal-rounds"}
  - {kind: "file", path: "loomwright/scripts/test-heal-review-scope-seam.sh"}
  - {kind: "file", path: "loomwright/scripts/fixtures/phase45-reviewer-prompt-base.txt"}
  - {kind: "file", path: "docs/evidence/phase45-converging-re-review.md"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "heal_review_scope"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/heal-review-scope.sh"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/heal-review-scope.sh", name: "scope_fallback"}
lanes:
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/skills/supervisor-config/SKILL.md"
  - "loomwright/agents/code-reviewer.md"
  - "loomwright/docs/result-schemas/supervisor-result.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/loop-inventory/supervisor.md"
  - "loomwright/commands/supervisor.md"
  - "loomwright/scripts/test-heal-review-scope-seam.sh"
  - "loomwright/scripts/fixtures/phase45-reviewer-prompt-base.txt"
  - "changelog.d/phase45-converging-re-review.md"
  - "docs/evidence/phase45-converging-re-review.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires:
  - "claude -p --plugin-dir for the AC17 pre-release shadow run"
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 2 ──→ Subtask 1
```

(Edges derived from `requires.from`: Subtask 2 consumes Subtask 1's helper.)

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | YES (dependency: #2 requires #1) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` |
| 2 | `skills/self-heal-advisory/SKILL.md`, `skills/supervisor-config/SKILL.md`, `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| A real bug outside the touched files goes unreported by Phase 4.5 under `files` | HIGH | Round 1 stays full; `shadow` is the shipped default and measures exactly this (`in_would_scope: false`); the owner promotes only from `--shadow-report`; CI lens unchanged |
| Repeat suppression hides a fix that did not work, or a finding that grew more severe | MEDIUM | Owner decision D2: only same-run `dismissed` fingerprints re-reported at no higher severity are suppressed. A re-reported `fixed` fingerprint always reaches the fix task, is counted `repeat_of_fixed`, and is listed by the shadow report. Suppression never changes `iter_decision`; it applies only under `files` (shadow counts and never drops). |
| A re-run of the same brief inherits an earlier run's dismissals | LOW | Every record carries `run_id`; `suppress` and `prev-sha` read only the current run (AC7, AC15) |
| The base-prompt fixture freezes the whole reviewer prompt, so any future prompt edit breaks the seam test | LOW | The seam test's failure prints the regenerate command; the SKILL.md touched-file invariant names the fixture so editors update both together |
| The description-hash `rule` under-fires (a reworded repeat is not matched), so suppression saves little | MEDIUM | Safe by construction (reports more); `would_suppress` in the shadow report measures it; a reviewer-supplied `rule` field is a possible follow-up, deliberately out of scope (it would change the closed `CODE_REVIEW_RESULT` issue key set) |
| Feasibility (Phase 2.5): AC17's pre-release headless `/automate` run may not complete inside the worker's session | MEDIUM | The evidence file is a committed deliverable; if the run cannot complete in-session, the worker records that state in the evidence file and the item is surfaced to the owner rather than claimed done |
| Feasibility (Phase 2.5): change exceeds one worker's context | MEDIUM | `context-bound` split: the helper and its tests land and pass first; Subtask 2 consumes a tested contract |
| The new prompt lines break an existing seam test's adjacency pin | MEDIUM | Lines go after MODULE-SHAPE ADVISORY and before `BASE_BRANCH=`, outside every pinned adjacency (ANTI-OVERLAP→EXECUTION DIRECTIVE, DEVIATIONS→PIN-MUTATION VERDICTS); `ci-local.sh --affected` runs every seam test |
| Token-budget breach on `self-heal-advisory` (776 headroom at base) | LOW | Raise in the same edit with a one-line note + mirror row (AC18) |
| A fix touching `CHANGELOG.md` via `release-refold.sh` puts a large file in the round ≥ 2 scope | LOW | Per D1 every touched file is in scope; a refold only fires when a fix added a fragment; the shadow report's minutes estimate shows the cost |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-01-phase45-re-review-converges-on-last-fix.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-01T17:33:17Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/781
- **Branch:** feature/phase45-re-review-converges-on-last-fix
- **Files changed:** 14
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 1
- **Heal reason:** needs_human
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** unarmed (marker_missing)
- **Summary:** Shipped heal-review-scope.sh (scope/record/suppress/--shadow-report) and wired heal_review_scope (default shadow) into the Phase 4.5 loop, with config step 2.11, the reviewer rule, schema pointer, seam test plus frozen fixture, budgets and inventory rows. Lane PR carries changelog.d/ fragments only (the worker's bump was reverted; owner adjudicated the CHANGELOG.md provides gap as D). Phase 4.5: 2 reviews and 1 fix (files-mode reporting exemption). Escalated because the only remaining at-floor finding, AC17's real headless /automate shadow-run evidence, needs an owner run; the Supervisor stopped the loop before the cap since a fix task cannot close it. 9 below-floor findings were dismissed (PR comment).

## Not verified
- **heal-review-scope.sh called from the Phase 4.5 loop** — subtask 2 wires it; subtask 1 had no consumer yet (subtask 1)
- **AC17 pre-release headless /automate shadow run** — not executed (multi-hour live run) (subtask 2)
- **Phase 4.5 loop calling heal-review-scope.sh at run time** — prose wiring; seam test pins text only (subtask 2)
- **code-reviewer honouring HEAL RE-REVIEW SCOPE / DO-NOT-REPORT** — needs a live round >= 2 under files (subtask 2)
- **PR body link to the evidence file** — no PR existed when the worker ran; the body was written at FINALIZE without the link line (subtask 2)
