# Supervisor Job: automate-speed/26 — prompt diet for the four most-spawned subagents (code-reviewer, execute-manager, plan-reviewer, worker)

## Environment
- **Project:** lane clone `L24` of `ai-agent-manager` (`~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-15-163325/L24`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main (lane clone; origin = vikashruhilgit/loomwright)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/automate-speed/26-diet-subagent-prompts.md
- **Base commit:** ee3d7ea3bb069c50a07c3b37222c52c88202263b

> **Warning (1):** this checkout is lane `L24` of the `--parallel` run `automate-2026-10-15-163325`. Stay inside this item's File Impact Map. This PR carries a `changelog.d/` fragment and NO version bump (`changelog.d/README.md` §"Who runs the bump": in a parallel wave, lanes write fragments only; the release lane folds them). `bash scripts/check-version-bump.sh` must pass.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown prompt edits + one JSON + one doc table; no code. |
| 2 | Dependency Availability | GO | `scripts/check-token-budget.sh` measures the spawn weight (agent file + frontmatter-preloaded skills, bytes/4 proxy); `loomwright/scripts/read-token-ledger.sh` reports peak context. |
| 3 | Architecture Fit | GO | Same method as automate-speed items 13–16 (rule homes out, stories to `loomwright/docs/rationale/`, on-demand skill Reads — e.g. `SKILLS_INDEX.md`'s Supervisor rows "on-demand Read at Phase … entry — deliberately NOT preloaded"). |
| 4 | Scope vs Supervisor Capability | CAUTION | Single-agent default holds: 10 files, ~800 changed lines estimated (≈30% of the four prompts' 2569 lines deleted, about the same moved verbatim into the rationale doc, plus bookkeeping), so no split reason fires. Turn budget is the pressure point: four large prompts plus ~30 suites that pin literal prose inside them (see Risk Assessment). |
| 5 | Hard Blockers | CAUTION | The ≥30% target is tight for the two agents with no preloads to shed: `plan-reviewer` live 12377 → ≤ 8663 and `worker` 9127 → ≤ 6388, both from prose alone, and Criteria 12/14/17–20 (plan-reviewer) and Step 5/5.5/5.7 (worker) are heavily pinned. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Each of `loomwright/agents/{code-reviewer,execute-manager,plan-reviewer,worker}.md` carries instructions and short rules only, preloads only the skills it uses on every spawn, and Reads the rest on demand at the step that needs it — cutting each agent's spawn weight by ≥30% without changing what any agent decides, reviews or returns.

**Problem Statement:** Items 13–16 shrank what the main thread reads; nothing shrank what each subagent reads at spawn. Subagents were 36% of PR #555's item context (63M of 172M tokens) and 14% of vendsy/hub PR #445's. Every spawn pays its prompt again, and code-reviewer and plan-reviewer each spawn up to 3× per item.

**Baseline (live `bash scripts/check-token-budget.sh` at base `ee3d7ea`, proxy tokens):**

| Agent | Live weight | Preloaded skills | ≥30% target (≤) | JSON `measured` today |
|---|---|---|---|---|
| `code-reviewer` | 27473 | 5 (quality-checklist, context7-lookup, unit-testing, error-handling, monitoring-observability) | 19231 | 25057 |
| `execute-manager` | 31405 | 3 (async-orchestration, context-summarization, state-management) | 21983 | 38698 |
| `plan-reviewer` | 12377 | 0 | 8663 | 6392 (frozen v15.10.0 baseline) |
| `worker` | 9127 | 0 | 6388 | 4158 (frozen v15.10.0 baseline) |

(Requirement's 2026-10-15 figures differ slightly — execute-manager's preloaded `async-orchestration` already lost `finalize.md` in an earlier item. The worker re-measures at start and uses its own start figure as "before" if it differs from this table.)

**Method — Part A (rule homes and stories out):** a rule already enforced by a SubagentStop validator, a hook, `verify-provides.sh` or another existing script loses its prose (keep one line only where the agent would otherwise attempt the blocked action). History and incident narrative moves to `loomwright/docs/rationale/subagents.md`, keeping a one-line "because" only where it blocks a tempting wrong shortcut (owner decision D2). Every removed rule line names its enforcing script/hook or its new on-demand location in that doc (owner decision D1: no rule is dropped).

**Method — Part B (preloads):** for each frontmatter `skills:` entry, keep it only if the agent uses it on every spawn; otherwise delete the entry and add an on-demand `Read ${CLAUDE_PLUGIN_ROOT}/skills/<x>/SKILL.md` at the step that needs it, with its trigger (e.g. code-reviewer reads `monitoring-observability` only when the diff touches logging/metrics/tracing code; `unit-testing` only when the diff touches tests; `error-handling` only when it touches error paths; `context7-lookup` only when CLAUDE.md lacks a library fact; execute-manager reads `state-management` only at the step that uses it). Record each keep/move decision and its trigger in the rationale doc. Skill CONTENT is not edited.

**Out of scope:** changing what any agent decides, reviews or returns; model/effort changes; lowering any `budget` ceiling (item 18); editing any skill's content (async-orchestration → items 11/15, review-heal → 12/14); any other agent file.

## Acceptance Criteria
- [ ] **AC1 (≥30% per agent, evidence committed).** Given the PR branch, when `bash scripts/check-token-budget.sh` runs, then each of the four agents' weight is ≤ 70% of its "before" figure (targets in the Baseline table: code-reviewer ≤ 19231, execute-manager ≤ 21983, plan-reviewer ≤ 8663, worker ≤ 6388), and a committed evidence file `docs/evidence/as26-diet-subagent-prompts.md` contains the before/after/percent table per agent plus the exact `check-token-budget.sh` output lines it was read from, and the PR body links to it.
- [ ] **AC2 (result blocks are interfaces — validators unchanged).** Given the PR branch, then `bash loomwright/scripts/test-result-validators.sh`, `bash loomwright/scripts/test-validate-code-review-result.sh` and `bash loomwright/scripts/test-emit-block-parses.sh` pass with NO edit to any `validate-*-result.py`, `result_block_parser.py`, any validator test or any fixture; every emit template (`CODE_REVIEW_RESULT:`, `PLAN_REVIEW_RESULT`, `WORKER_RESULT`, `EXECUTE_RESULT`, `EXECUTE_CHECKPOINT`) is byte-identical to base; and `bash loomwright/scripts/build-capabilities.sh --check` passes with `loomwright/capabilities.json` unchanged (its `result_blocks` are derived from the templates and from emit verbs such as "Always emit a CODE_REVIEW_RESULT block", and `tools` from frontmatter — keep both).
- [ ] **AC3 (mutation control, reported honestly).** Given a scratch copy of the PR tree (`git archive HEAD | tar -x -C "$SCRATCH"`, never the working tree), when one field line (e.g. `files_checked`) is deleted from the copy's `agents/code-reviewer.md` `CODE_REVIEW_RESULT:` template — the mutant checked valid first (non-empty, differs from the original) — and `test-result-validators.sh`, `test-emit-block-parses.sh`, `scripts/check-contract-parity.sh` and `build-capabilities.sh --check` are run from inside the copy, then `docs/evidence/as26-diet-subagent-prompts.md` records the command and, per suite, red or green with its output line. If NO suite goes red, the evidence file states that gap plainly (no gate pins the template's field set) and the worker files it under `not_verified` as a follow-up candidate; it does not add a new pin in this PR.
- [ ] **AC4 (rationale doc maps every removed rule).** Given `loomwright/docs/rationale/subagents.md` (new, modeled on `loomwright/docs/rationale/supervisor.md`'s header paragraph), then it has one `##` section per agent; each removed rule line appears in a table `| removed line (short quote) | home |` whose home is `script:<file>`, `hook:<hooks.json leaf>`, `on-demand:<skill path> at <step>`, or `kept-as-one-line` — never blank; moved stories are under `###` headings, verbatim; and a `### Preload decisions` subsection per agent lists every original `skills:` entry as `kept (used every spawn because …)` or `moved → Read at <step> when <trigger>`. Spot check: every `script:`/`hook:` home names a file that exists (`test -f loomwright/scripts/<file>` / a matching `hooks.json` command).
- [ ] **AC5 (behaviour-preserving pins stay green).** Given the PR branch, then every suite that pins literal text in the four agents passes unmodified — at minimum `scripts/check-contract-parity.sh`, `scripts/check-shared-prefix.sh`, and `loomwright/scripts/test-{rules-seams,rule-conformance-seam,reviewer-interaction-lens,pr-body-evidence-seam,brief-conformance-seam,deviations-advisory-seam,closed-enum-pins-seam,phase45-rounds-seam,execution-directive-seam,agent-memory-permission,verify-provides,check-children-settled,not-verified-transport-seam,worktree-audit,no-self-matching-wait,worker-rule-selfcheck,build-capabilities}.sh`. No test, fixture or pin needle is edited to make a cut pass (the Touched-file invariants list the anchors). The code reviewer's EXECUTION DIRECTIVE and pin-mutation rules keep their meaning; no per-subtask LLM reviewer is introduced.
- [ ] **AC6 (frontmatter invariants).** Given each agent's frontmatter, then `name`, `description`, `tools`, `disallowedTools`, `model`, `effort`, `maxTurns`, `memory`, `permissionMode` and the `hooks:` copies (code-reviewer `Stop` prompt hook, execute-manager/worker `SubagentStop` command hooks — kept for `~/.claude/agents/` compatibility per CLAUDE.md "Hook gotcha") are byte-identical to base; only `skills:` entries are removed. Any agent left with no preloads drops the `skills:` key entirely rather than leaving an empty list.
- [ ] **AC7 (measured values + mirror + restated preload lists).** Given `loomwright/docs/prompt-token-budgets.json`, then `.agents[code-reviewer|execute-manager|plan-reviewer|worker].measured` equal the final live `check-token-budget.sh` figures (re-measured after the LAST prose edit of the PR, including any Phase 4.5 fix that touches these files), every `budget` is unchanged, and each `note` is one line (< 200 chars) naming automate-speed/26; the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror rows carry the same measured figures and the new "Preloaded skills" counts, `plan-reviewer` and `worker` become ¹-marked live rows (update footnote ¹ and the bold marked-set enumeration paragraph that names the unmarked rows), and one `> **Re-measure log (automate-speed/26 …)**` entry records before → after per agent. `loomwright/skills/SKILLS_INDEX.md`'s "Used by" cells (its `Agent Consumers` column) drop every `Code Reviewer (preload)` / `Execute Manager` preload claim that no longer holds and say the on-demand trigger instead; a repo-wide grep for each moved skill name paired with the agent (`grep -rn "<skill>" --include=*.md . | grep -iE "code reviewer|code-reviewer|execute.manager"`, excluding `CHANGELOG.md`, `.supervisor/` and fixtures) shows no surviving preload claim.
- [ ] **AC8 (running system, honest).** Given the slimmed prompts, when one real Plan Review and one real code-review round are run on them — `claude -p --plugin-dir <worktree>/loomwright --agent <plan-reviewer's runtime agent name> --max-budget-usd 3` on this brief's text, and the same for the code-reviewer with `--max-budget-usd 5` on this PR's diff (`review_mode: diff_review`); the worker confirms the runtime agent name and that the worktree copy (not the installed plugin) was loaded, and records how — then `docs/evidence/as26-diet-subagent-prompts.md` records, per spawn, the session id, whether a valid `PLAN_REVIEW_RESULT` / `CODE_REVIEW_RESULT` block was emitted, and the peak context read from that session's transcript the way `loomwright/scripts/read-token-ledger.sh` computes it (largest single message's input + cache_creation + cache_read), with the command used. If a run cannot be done (CLI flag rejected, auth, budget), the evidence file says `UNVERIFIED — <reason>` for that spawn and the worker lists it under `not_verified`; never a guessed number.
- [ ] **AC9 (fragment, no bump).** Given the PR diff, then `changelog.d/as26-diet-subagent-prompts.md` exists (format per `changelog.d/README.md`, first line `<!-- bump: minor -->`), no version file (`loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`) is touched, and `bash scripts/check-version-bump.sh` passes.
- [ ] **AC10 (CI green).** Given the PR branch, when `bash scripts/ci-local.sh` runs (wait with `bash scripts/ci-local.sh --wait`), then it passes — including `check-token-budget.sh`, `check-shared-prefix.sh`, `test-result-validators.sh`, `check-doc-currency.sh` and `test-citation-drift.sh` (no bare `file:N` citation and no `/Users/<name>/` path in the new rationale/evidence docs); `docs/evidence/as26-diet-subagent-prompts.md` records the `<passed>/<total>` line.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent
- corpus-task: emit-block-parses
- corpus-task: parity-emit-block

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

(Rule 1: the rationale doc states no plugin-wide agent/skill counts. Rule 2: `SKILLS_INDEX.md`'s "Used by" preload claims and the `ARCHITECTURE_CONTRACTS.md` mirror rows are restated copies of the frontmatter / JSON and change in this same PR — AC7.)

## Configuration
- **Mode:** single-agent
- **Base Branch:** main
- **Workers:** 1

## Touched-file invariants

> Grounded at base `ee3d7ea3bb069c50a07c3b37222c52c88202263b`. These are markdown/JSON, not scripts, but each is read by pinning tests; a cut that removes an anchor below turns a suite red (or makes a mutant INVALID, which also fails). Before cutting a section, grep every `loomwright/scripts/test-*.sh` and `scripts/check-*.sh` for its distinctive phrases.

- **`loomwright/agents/code-reviewer.md`**
  - keep: the `<!-- SHARED-AGENT-PREFIX v1 BEGIN -->` … END block byte-identical (`scripts/check-shared-prefix.sh`).
  - keep: the `CODE_REVIEW_RESULT:` template under `### Environment-Blocked Reviews` and the emit verb sentence (`test-emit-block-parses.sh`, `build-capabilities.sh --check`); every field name `check-contract-parity.sh` greps (`schema_version, decision, summary, severity, category, review_mode, audit_focus, trigger_paths_detected, scope_expanded, files_checked`).
  - keep: the ordered anchors `test-reviewer-interaction-lens.sh` checks (`4. **Determine Review Scope**`, `### Review Process`, `**Interaction-behaviour lens (static`, `4. **Adversarial-Input Lens`, `6. **Flag Issues by Severity**`, `### Output Format`, …) and its six `` - `id` — `` lens lines.
  - keep: step 5's `**Pin mutations (same EXECUTION DIRECTIVE gate).**`, `**Scratch-dir adversarial repro`, `**Mutation guardrails (NON-NEGOTIABLE` and `**Read-only via Bash too:**` lines with every phrase `test-execution-directive-seam.sh` / `test-closed-enum-pins-seam.sh` / `test-phase45-rounds-seam.sh` match; steps 5a/5b/5c with the phrases `test-pr-body-evidence-seam.sh`, `test-brief-conformance-seam.sh`, `test-deviations-advisory-seam.sh`, `test-validate-code-review-result.sh` match (incl. the `Self-heal lens` line under `### Severity Rules for Drift`); the `read-rules.sh" <…> --with-ids` call shape (`test-rules-seams.sh`); and must NOT gain `rules-check.sh`, `audit-rules.sh` or `Sole exception`.
  - keep: `### Agent memory write permission` (exactly once) with its four pinned phrases (`test-agent-memory-permission.sh`).
  - pinned by: the suites named above.
- **`loomwright/agents/plan-reviewer.md`**
  - keep: `## 20 Review Criteria`; `All 20 review criteria must be checked`; the conditional-criteria sentences; `### 12.` (Gate-parseable anchor / GATE PARSE / parse_warnings text), `### 17.`, `### 18.`, `### 19.`, `### 20.` blocks with every sentence `test-rule-conformance-seam.sh`, `test-closed-enum-pins-seam.sh`, `test-pr-body-evidence-seam.sh`, `test-verify-provides.sh` match; the Decision Matrix rows for 17c and 20; the Output Format category enumeration line; the Quality Checklist "All 20 criteria checked" line; the Criterion 1 and 16 `docs/evidence/` exemptions; all four `PLAN_REVIEW_RESULT` templates. Frontmatter `tools`/`disallowedTools` unchanged (`test-build-capabilities.sh` derives `Glob,Grep,Read`). Cuts come from Criteria 2–11, 13, 15 prose, examples and history.
- **`loomwright/agents/execute-manager.md`**
  - keep: the prefix block; all seven `EXECUTE_RESULT` / `EXECUTE_CHECKPOINT` templates, and the two strings `test-emit-block-parses.sh` needs exactly once (`adjudication_options:` block and the `reason: "Lane collision: {subtask_id} wrote …` line); Step 2a's `git worktree add ../{project}-{subtask_id} feature/{subtask_id}`; Step 2b's `--kind-table` text with no `\s`/`\b` and the `Record each check result` mutation anchor; Step 4's `--- v12 outputs_verified gate` and `--- Pin-mutation gate (automate-speed/02)` sections with every phrase `test-verify-provides.sh`, `test-phase45-rounds-seam.sh`, `test-check-children-settled.sh`, `test-not-verified-transport-seam.sh` match; the backticked `read-rules.sh … <touched paths...>` in the Step 3 spawn prompt; the Error Handling `Pin mutation not_held` row.
- **`loomwright/agents/worker.md`**
  - keep: the prefix block; all three `WORKER_RESULT` templates and the 12 field names `check-contract-parity.sh` greps; `### Step 5: Verify` with `ci-local.sh --affected`, `never the full `ci-local.sh` pool from a background worker`, `every static CI gate`, and `the waiter matches itself and never exits` within 3 lines of each `pre-push command` line; the `worker-rule-selfcheck.sh` + `--root` + `REPORT-ONLY` line inside Step 5; `### Step 5.7:` with `` `rule:` ``; the Step 5.5 ``verify own `provides:` `` block (ABSOLUTE worktree path, `brief_unreadable`/`jq_missing`, `subtask_not_found`); frontmatter `model: inherit` and `tools:`.
- **`loomwright/skills/SKILLS_INDEX.md`** — keep: edit ONLY the curated `Agent Consumers` cells (what AC7 calls "Used by") of the moved skills' rows; the Version / Last Updated cells, the row set and the `**Total: N skills**` line are GENERATED from SKILL.md frontmatter and must not be hand-edited, and the column order is load-bearing (the parser reads Directory from column 3 and Version from column 6). Since no SKILL.md changes, `bash scripts/check-skills-index-sync.sh` must pass with no `--write` diff.
  - pinned by: `scripts/check-skills-index-sync.sh` (index parity / generated-cell diff), `loomwright/scripts/test-skills-index-companion.sh`, `scripts/check-doc-currency.sh`.
- **`loomwright/docs/prompt-token-budgets.json`** — keep: JSON valid (`jq empty`); every `budget` unchanged; only the four agents' `measured` and `note` change; `check-token-budget.sh` mirror check requires the `ARCHITECTURE_CONTRACTS.md` row's budget and measured cells to equal the JSON.
- **`loomwright/docs/ARCHITECTURE_CONTRACTS.md`** — keep: every other row and raise-log entry byte-unchanged; no bare `file:N` citation (`test-citation-drift.sh`); it is in `check-doc-currency.sh`'s scan, so grep the OLD measured values repo-wide after the edit (lesson `0d7865dc`).

## Subtask Structure

| # | Title | Criteria | Est. Files | Skills | Status |
|---|-------|----------|-----------|--------|--------|
| 1 | Diet the four subagent prompts (Parts A + B), rationale doc, re-measure + JSON/mirror/SKILLS_INDEX, evidence file, fragment | AC1–AC10 | 7 modify, 3 create | quality-checklist | LAUNCHABLE |

### Subtask 1 — prompt diet (LAUNCHABLE)
- **Files (modify):** `loomwright/agents/code-reviewer.md` (HIGH), `loomwright/agents/plan-reviewer.md` (HIGH), `loomwright/agents/execute-manager.md` (HIGH), `loomwright/agents/worker.md` (HIGH), `loomwright/docs/prompt-token-budgets.json` (HIGH), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (HIGH — four mirror rows, footnote ¹ marked-set text, one re-measure log entry), `loomwright/skills/SKILLS_INDEX.md` (MEDIUM — "Used by" cells for moved skills only)
- **Files (create):** `loomwright/docs/rationale/subagents.md` (HIGH), `docs/evidence/as26-diet-subagent-prompts.md` (HIGH), `changelog.d/as26-diet-subagent-prompts.md` (HIGH)
- **Read-only inputs:** `loomwright/docs/rationale/supervisor.md` (format), `loomwright/hooks/hooks.json`, the `validate-*-result.py` validators, every pinning suite listed in Touched-file invariants.
- **Order of work (turn budget):** measure first (`bash scripts/check-token-budget.sh`); then one agent at a time — code-reviewer, plan-reviewer, execute-manager, worker — move preloads first, then cut prose section by section, running that agent's pinning suites after each section and appending its rationale-doc section before moving on; bookkeeping (JSON, mirror, SKILLS_INDEX, evidence, fragment) last, after the final re-measure; AC8 spawns after bookkeeping. Commit after each agent so a partial run is resumable.
- **Part B note (code-reviewer):** the existing line under `**For BACKEND code specifically**` that begins `Always available:` and names the error-handling, unit-testing and monitoring-observability SKILL.md files is rewritten into the on-demand Read wording, with each skill's trigger. Once those skills are no longer preloaded, it must not still claim they are always available.
- **Done when:** AC1–AC10 hold; the final `measured` values were taken after the last prose edit.

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/docs/rationale/subagents.md"}
  - {kind: "symbol", path: "loomwright/docs/rationale/subagents.md", name: "code-reviewer"}
  - {kind: "symbol", path: "loomwright/docs/rationale/subagents.md", name: "plan-reviewer"}
  - {kind: "symbol", path: "loomwright/docs/rationale/subagents.md", name: "execute-manager"}
  - {kind: "symbol", path: "loomwright/docs/rationale/subagents.md", name: "worker"}
  - {kind: "symbol", path: "loomwright/docs/rationale/subagents.md", name: "Preload decisions"}
  - {kind: "symbol", path: "loomwright/agents/code-reviewer.md", name: "Read ${CLAUDE_PLUGIN_ROOT}/skills/monitoring-observability/SKILL.md"}
  - {kind: "symbol", path: "loomwright/agents/execute-manager.md", name: "state-management/SKILL.md"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "automate-speed/26"}
  - {kind: "symbol", path: "loomwright/docs/prompt-token-budgets.json", name: "automate-speed/26"}
  - {kind: "file", path: "docs/evidence/as26-diet-subagent-prompts.md"}
  - {kind: "file", path: "changelog.d/as26-diet-subagent-prompts.md"}
requires: []
lanes:
  - "loomwright/agents/code-reviewer.md"
  - "loomwright/agents/plan-reviewer.md"
  - "loomwright/agents/execute-manager.md"
  - "loomwright/agents/worker.md"
  - "loomwright/docs/rationale/subagents.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "docs/evidence/as26-diet-subagent-prompts.md"
  - "changelog.d/as26-diet-subagent-prompts.md"
external_requires:
  - "claude CLI with --plugin-dir and --agent (AC8 running-system spawns; UNVERIFIED fallback when unavailable)"
```

## Parallelism Analysis
single-agent (no fan-out)

- Recommended workers: 1

## Skill References
- `loomwright/skills/quality-checklist/SKILL.md`

## Risk Assessment

| Risk | Level | Source | Mitigation |
|------|-------|--------|------------|
| A cut deletes a phrase a seam test pins (or a mutation anchor), turning a suite red | HIGH | Analysis (~30 pinning suites) | Touched-file invariants list the anchors; grep tests for a section's phrases before cutting it; run the agent's pinning suites after each section; never edit a test to make a cut pass. |
| One worker runs out of its 100-turn budget across four large prompts | MEDIUM | Feasibility (Phase 2.5) | Agent-by-agent order with a commit after each; run only the touched agent's pinning suites per section, the full `ci-local.sh` once at the end. |
| ≥30% unreachable for plan-reviewer / worker without cutting a behaviour rule | HIGH | Feasibility (Phase 2.5) | Cut stories, examples, restated schemas (point to `docs/RESULT_SCHEMAS.md`) and rules a script/hook enforces first; if a target is still missed, stop and report the shortfall with the remaining-candidate list — never drop a behaviour rule to hit the number (D1). |
| Prior churn on these exact files, including a recorded `self_heal_miss` | HIGH | Prior churn (postmortem ledger) | ARCHITECTURE_CONTRACTS.md (61), prompt-token-budgets.json (23), code-reviewer/worker (13 each), execute-manager (11); classes drain_churn, self_heal_churn, convention_mismatch. Keep the ARCHITECTURE_CONTRACTS edit to the four rows + footnote + one log entry; grep OLD measured values repo-wide; run doc-currency and token-budget before push. |
| Moving a preload changes behaviour (agent no longer applies a checklist it used every spawn) | MEDIUM | Analysis | Keep any skill used every spawn; for each move, the on-demand Read sits at the exact step with an explicit trigger; record both in the rationale doc's Preload decisions. |
| `measured` drifts after a Phase 4.5 fix edits an agent | MEDIUM | Requirement (AC7) | Re-measure after the last edit; any fix task that touches the four agents re-syncs `measured` + mirror row in the same commit. |
| Restated preload lists elsewhere go stale | MEDIUM | House rules (restated-list rule) | AC7's SKILLS_INDEX update + repo-wide grep. |
| AC8 nested `claude -p` run unavailable or costly | LOW | Feasibility | `--max-budget-usd` caps; `UNVERIFIED — <reason>` + `not_verified` when it cannot run. |
| Home path or bare `file:N` in the new docs breaks the trail push / citation drift | LOW | `meta-sync.sh` scrub, `test-citation-drift.sh` | Placeholder paths only; descriptive anchors. |

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-10-20-as26-diet-subagent-prompts.md

## Outcome
- **Status:** completed
- **Completed:** 2026-10-20T10:38:13Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/634
- **Branch:** feature/as26-diet-subagent-prompts
- **Files changed:** 11
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Four subagent prompts dieted ≥30% (code-reviewer 27473→17681, execute-manager 31405→19283, plan-reviewer 12377→8591, worker 9127→5836); templates/validators/frontmatter (except skills:) unchanged; rationale doc, re-measured JSON/mirror/SKILLS_INDEX, evidence file, fragment. Phase 4.5: 3 reviews, 2 fixes (restored dropped Criterion 14/17c + worker Step 5.7 clauses; refreshed AC10 CI evidence). GitHub CI green on b360b9a; local ci-local 189/192 (3 environmental).

## Not verified
- **CODE_REVIEW_RESULT template field set** — no gate pins it — deleting files_checked kept all four AC3 suites green; follow-up pin candidate (subtask 1)
- **Plan Reviewer block formatting on the slim prompt** — 1 of 2 claude -p samples emitted a multi-line summary the strict parser rejects; 1 base control sample was valid — too few samples to rule a regression in or out (subtask 1)
- **ci-local test-automate-next-step.sh and test-automate-trail.sh** — both timed out at the 900s cap under host load average 24-166; not re-run on an idle host (subtask 1)
