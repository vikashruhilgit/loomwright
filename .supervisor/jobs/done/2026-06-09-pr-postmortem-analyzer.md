# Supervisor Job: /pr-postmortem — manual PR review-churn analyzer

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh, v14.21.0)
- **Git:** branch `main`; working tree dirty at brief-creation time — branch from a clean `main` (commit/stash first).
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (dirty working tree)

## Feasibility (Phase 2.5)
**GO.** Pure additive read-only tooling. Reuses the established inline-command+skill pattern (`/autonomous`, `/insights`) and the `.supervisor/<area>/results.jsonl` trend convention (`/eval`). No new agent, no API key, no network beyond `gh`. CAUTION: adds 1 command + 1 skill — counts must be updated (doc-currency gate), handled in Subtask 3.

## Task
**Goal:** Add `/pr-postmortem <pr-url>` — a manual, on-demand, READ-ONLY analyzer that, given a merged/open PR, gathers its commits + review comments + CI history via `gh`, categorizes each review round (why the PR needed back-and-forth), attributes each to a flow stage (Launch Pad / Worker / self-heal / unknowable), prints a root-cause report, and appends one structured `POSTMORTEM_RESULT` line to a local trend file. No sub-agents are spawned; no API key required; nothing is written to the analyzed repo. The trend file is the seed corpus for a future synthetic eval harness.

**Why:** A root-cause analysis of agent PRs (otherhub #146/#129/#133/#139, this repo #24/#26/#36/#41) found the quality verdict (review rounds) lands in the PR AFTER the Supervisor session ends — an open loop nothing carries back. This tool closes it and measures whether the self-heal hardening (sibling brief `2026-06-09-self-heal-blind-spot-hardening.md`) actually reduces churn.

## Acceptance Criteria
- [ ] Given a PR URL, when `/pr-postmortem <url>` runs, then it gathers commits/reviews/CI via `gh` and prints a categorized root-cause report — READ-ONLY (no writes to the analyzed repo, no sub-agent spawned, no extra model API calls).
- [ ] Given the gathered data, when categorized, then each review round maps to exactly one of `{plan_gap, missing_context, convention_mismatch, execution_bug, quality_gap, scope_too_large}` plus an optional `self_heal_miss` flag and a flow-stage attribution.
- [ ] Given a completed analysis, when it finishes, then it appends exactly one `POSTMORTEM_RESULT` JSON line to `.supervisor/postmortem/results.jsonl` (jq-built; fail-safe; never crashes the command).
- [ ] Given a private/inaccessible PR or missing `gh`, when run, then it exits gracefully with a clear message (no stack trace, no partial-write corruption).
- [ ] `POSTMORTEM_RESULT` is documented in `RESULT_SCHEMAS.md` at `schema_version: 1` (no hook validator, mirroring EVAL_RESULT/GROUND_TRUTH_JSON).
- [ ] Counts updated to 17 commands / 52 skills across CLAUDE.md, plugin.json, marketplace.json; `scripts/check-doc-currency.sh` and all `scripts/test-*.sh` pass.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

### Subtask 1 — Gather script + self-test (LAUNCHABLE)
- **Files (create):** `ai-agent-manager-plugin/scripts/pr-postmortem-gather.sh`, `ai-agent-manager-plugin/scripts/test-pr-postmortem-gather.sh`
- Read-only `gh`-based gatherer. Input: a PR URL or `owner/repo#N`. Emits ONE normalized JSON object: `{repo, number, title, agent_generated_guess, additions, deletions, changed_files, commits:[{headline, is_review_fix}], review_rounds, review_comments:[{author, snippet}], ci_checks:[{name, state}]}`. Fail-safe: missing `gh`/jq or inaccessible PR → emits `{"status":"unavailable","reason":...}` and exits 0. jq-built (injection-safe). Self-test uses a fixture (no live network).
- **provides:**
  - {kind: file, path: ai-agent-manager-plugin/scripts/pr-postmortem-gather.sh, name: "pr-postmortem gather script + JSON output contract"}
  - {kind: file, path: ai-agent-manager-plugin/scripts/test-pr-postmortem-gather.sh, name: "gather self-test"}
- **requires:** []

### Subtask 2 — Skill + command (BLOCKED by 1)
- **Files (create):** `ai-agent-manager-plugin/skills/pr-postmortem/SKILL.md`, `ai-agent-manager-plugin/commands/pr-postmortem.md`; **(modify):** `ai-agent-manager-plugin/skills/SKILLS_INDEX.md`
- SKILL.md defines the inline analysis protocol: parse input → run the Subtask-1 gather script → categorize each review round (6-class schema + `self_heal_miss` + flow-stage attribution) → print the report → append the `POSTMORTEM_RESULT` line to `.supervisor/postmortem/results.jsonl`. Command is a thin inline shell referencing the skill (mirrors `commands/autonomous.md`: "execute inline, no delegated agent"). Add the SKILLS_INDEX row.
- **provides:**
  - {kind: file, path: ai-agent-manager-plugin/skills/pr-postmortem/SKILL.md, name: "pr-postmortem skill (analysis protocol + POSTMORTEM_RESULT append)"}
  - {kind: file, path: ai-agent-manager-plugin/commands/pr-postmortem.md, name: "/pr-postmortem inline command"}
  - {kind: symbol, path: ai-agent-manager-plugin/skills/SKILLS_INDEX.md, name: "pr-postmortem index row"}
- **requires:**
  - {from: "1", kind: file, path: ai-agent-manager-plugin/scripts/pr-postmortem-gather.sh, name: "pr-postmortem gather script + JSON output contract"}

### Subtask 3 — Schema + docs + version + counts (BLOCKED by 1,2)
- **Files (modify):** `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` (POSTMORTEM_RESULT, schema_version 1), `CLAUDE.md` (banner + count claims → 14/17/52/19), `CHANGELOG.md`, `ai-agent-manager-plugin/.claude-plugin/plugin.json` (version + count), `.claude-plugin/marketplace.json` (version + description count), `ai-agent-manager-plugin/commands/agent-help.md` (list the new command if it enumerates commands).
- Target version **v14.22.0** (PR #43 already shipped v14.21.0; main is now at 14.21.0). This brief adds 1 command + 1 skill, so counts go 14/16/51/19 → 14/17/52/19.
- **provides:**
  - {kind: symbol, path: ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md, name: "POSTMORTEM_RESULT schema"}
  - {kind: file, path: ai-agent-manager-plugin/.claude-plugin/plugin.json, name: "version + 17/52 counts"}
  - {kind: symbol, path: CLAUDE.md, name: "v14.22.0 banner + 14/17/52/19 count claims"}
  - {kind: file, path: .claude-plugin/marketplace.json, name: "version + description count"}
- **requires:**
  - {from: "1", kind: file, path: ai-agent-manager-plugin/scripts/pr-postmortem-gather.sh, name: "pr-postmortem gather script + JSON output contract"}
  - {from: "2", kind: file, path: ai-agent-manager-plugin/skills/pr-postmortem/SKILL.md, name: "pr-postmortem skill (analysis protocol + POSTMORTEM_RESULT append)"}

## Parallelism Analysis
### Dependency Graph
- 1 → 2 → 3 (serial chain: skill consumes the script's JSON contract; docs/counts document both).
### File Overlap Matrix
- S1 `scripts/pr-postmortem-gather.sh` + test · S2 `skills/pr-postmortem/SKILL.md` + `commands/pr-postmortem.md` + `skills/SKILLS_INDEX.md` · S3 docs/manifests. **No overlap.**
### Batch Plan
- Batch 1: Subtask 1. Batch 2: Subtask 2. Batch 3: Subtask 3. **Recommended workers: 1** (serial build).

## Skill References
- New `pr-postmortem` skill (Subtask 2); `state-management` (trend-file convention); `claude-md-validation` + doc-currency gate (Subtask 3).

## Risk Assessment
| Risk | Severity | Source | Mitigation |
|---|---|---|---|
| Adds 1 command + 1 skill (anti-rebloat) | LOW | Feasibility | Deliberate cost of a genuinely new user-facing capability; NO new agent (inline command+skill); counts updated in Subtask 3 |
| LLM categorization is non-deterministic | LOW | Analysis | Tool is advisory/diagnostic, never gates; gather step is deterministic, only categorization is judgment |
| `gh` rate limits / private PRs | LOW | Analysis | Fail-safe `status:"unavailable"`, exit 0, no partial write |
| Version collision with the sibling self-heal brief | LOW (resolved) | Analysis | PR #43 shipped v14.21.0; this brief now definitively targets v14.22.0 — no remaining collision |

## Configuration
- **Base Branch:** main
- **Target version:** v14.22.0 (v14.21.0 shipped via PR #43)

## Plan Review
- **Decision:** PASS (attempt 1/3). One LOW advisory (Subtask 3 provides under-described) — incorporated. All paths verified; pattern alignment with `autonomous.md` + `.supervisor/<area>/` + EVAL_RESULT/GROUND_TRUTH_JSON confirmed; DAG 1→2→3 acyclic; Executable Acceptance corpus-task-only; count arithmetic 14/16/51/19 → 14/17/52/19 correct.

## Handoff
`/supervisor job: .supervisor/jobs/pending/2026-06-09-pr-postmortem-analyzer.md`

## Outcome
- **Status:** completed
- **Completed:** 2026-06-09T20:37:22Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/45
- **Branch:** feature/pr-postmortem-analyzer
- **Files changed:** 14
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0 (holistic consistency_audit review found no new BLOCKING/HIGH; 3 LOW/MEDIUM advisory nits fixed proactively)
- **Ground truth:** pass (2/2 — corpus-task: doc-currency-green, version-consistent)
- **Benchmark:** pass (selftest_pass_count=4)
- **Summary:** Added /pr-postmortem read-only PR review-churn analyzer (gather script + self-test, inline skill+command, POSTMORTEM_RESULT schema_version 1) and bumped counts 14/16/51/19 -> 14/17/52/19, version -> v14.22.0. 3 subtasks, all per-subtask reviews PASS; all gates green (validate-version, command-sync, doc-currency, 15/15 test-*.sh).
