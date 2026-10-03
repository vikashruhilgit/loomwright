# Supervisor Job: Worker deviations record (WORKER_RESULT.deviations → ## Worker Results → Phase 4.5 advisory)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: feature/loop-gaps-01-worker-deviations (== origin/main @ e388d9d)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/six-phase-loop-gaps/01-worker-deviations.md

## Feasibility (optional — Launch Pad v10.3+)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure markdown/Python/bash edits threading one new optional field through an existing pipeline; no new tooling. |
| 2 | Dependency Availability | GO | No new dependency. |
| 3 | Architecture Fit | GO | Mirrors the `out_of_lane` field precedent EXACTLY (same "optional, additive, does not bump schema_version, validated when present" shape) — a pattern this codebase already has end-to-end, from `RESULT_SCHEMAS.md` through the validator, parity check, worker prompt, Context-Keeper, state template, Supervisor record sites, and (new) the Phase 4.5 advisory consumer. |
| 4 | Scope vs Supervisor Capability | CAUTION | 17 files (16 modify, 1 create) across a single cohesive schema-threading change — every touch point depends on the SAME field definition (name, shape, bound), so genuine parallelism isn't available (splitting would just serialize on the schema decision anyway). Kept single-subtask, consistent with items 06/08 in this run. |
| 5 | Hard Blockers | GO | No migration framework, no new credentials. Every premise re-verified live during planning (see Risk Assessment for the 2 corrections found: script paths, and confirming the token-budget figures are still exactly accurate — no drift). |

**Overall Verdict:** CAUTION (proceeds silently per Phase 2.5 flow, feeds Risk Assessment)

## Task
**Goal:** Give workers and Phase 4.5 fixers a near-zero-cost way to record deviations from the plan (edge cases, open decisions, test diagnoses) that survives worktree removal and reaches the Phase 4.5 review lens as an advisory — mirroring the existing `out_of_lane` field's plumbing exactly.

**Problem Statement:**
A worker that departs from its subtask's plan, hits an edge case the brief never mentioned, or decides something the brief left open records that fact nowhere durable — `grep -i deviat loomwright/agents/worker.md` returns nothing. `WORKER_RESULT` (schema_version 2) has `summary` ("what was done") and `outputs_gap` ("what I did not deliver") but no "where I departed from what was asked." The per-worker narrative file (`.worker-summary.md`) is written in the worktree, which is removed at FINALIZE — Execute Manager reads and compresses it into `EXECUTE_RESULT`, an orchestrator-summary drift point. Consequence: Phase 4.5's code-reviewer must infer plan drift from the integrated diff alone; the existing `brief_conformance` advisory asks "is each acceptance criterion addressed?" but cannot ask "did the worker knowingly do something else, and why?" — only the worker that made the deviation knows. Success looks like: every worker and Phase 4.5 fixer can record each deviation as one bounded string; worker records survive worktree removal in `state.md`'s `## Worker Results`; Phase 4.5 hands the union to the review lens as one advisory line placed after the existing `BRIEF-CONFORMANCE ADVISORY`; and a deviation that contradicts a stated acceptance criterion surfaces as an ordinary reviewer finding — nothing about `heal_decision`, bounds, or never-merge changes.

## Acceptance Criteria
- [ ] Given `scripts/validate-worker-result.py`, when run against a v2 WORKER_RESULT block with no `deviations` key, with `deviations: []`, or with `["plan: skipped migration down-direction — brief did not ask; flagged open", "test: audit-log format — assertion wrong: asserted the pre-change format", "skipped the migration"]` (an unprefixed entry), then all three are ACCEPTED; given `deviations: null`, a bare string instead of an array, `[""]`, 13 entries, or a 201-character entry, then each is REJECTED with a message naming "rule 10".
- [ ] Given `loomwright/docs/RESULT_SCHEMAS.md` §FIX_RESULT, when read, then it lists `deviations` with the SAME shape (≤12 entries, ≤200 chars each, optional/additive) as §WORKER_RESULT's new field, and the Phase 4.5 fix-task spawn prompt's output shape includes it.
- [ ] Given `scripts/check-contract-parity.sh`, when run with `deviations` appended to the WORKER_RESULT MANIFEST row, then it PASSES; given the row reverted to omit `deviations` while `RESULT_SCHEMAS.md` still lists the field, then it FAILS (the parity check's own negation test).
- [ ] Given `loomwright/agents/context-keeper.md`'s `record_worker_result` result-object row and `loomwright/skills/state-management/SKILL.md`'s `## Worker Results` template, when read, then both list/render `deviations` alongside `out_of_lane`; given both Supervisor record sites (Single-Agent step + Sequential-path per-subtask loop) and Execute Manager's poll-loop record call, then all name `deviations` in the same sentence as `out_of_lane`.
- [ ] Given `loomwright/skills/self-heal-advisory/SKILL.md`, when read, then step 1g "Deviations advisory" exists as a sibling to 1c/1e/1f, runs on every Phase 4.5 iteration (not only the first), reads both `state.md`'s per-subtask `deviations` entries and a per-run `fixer_deviations` list, and its `DEVIATIONS ADVISORY` line is placed directly after the code-reviewer Task prompt's `BRIEF-CONFORMANCE ADVISORY` line — included only when non-empty, with a truncation marker when the bound is exceeded.
- [ ] Given `loomwright/agents/worker.md`'s WORKER_RESULT output block, when read, then a `deviations: ["plan: …", "edge: …", …] # OPTIONAL` line appears directly after `memory_candidates` (not `out_of_lane`, which precedes `memory_candidates` in this file's own ordering — the two files order the two fields differently and this brief follows each file's own existing order, not a single global order); a new §"deviations" subsection names the four kinds (plan:/edge:/open:/test:), the ≤12/≤200 bound, the transient-vs-durable distinction from `memory_candidates`, and the "never secrets/PII" rule; the `.worker-summary.md` echo rule mirrors the `memory_candidates` one byte-for-byte (a `## deviations` heading, one `- ` bullet per entry, heading omitted when empty).
- [ ] Given `bash scripts/check-token-budget.sh` after the worker.md prose addition, when run, then it PASSES with the raised budget recorded in `loomwright/docs/prompt-token-budgets.json` (measured + ~10% headroom) and a matching raise-log row in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets".
- [ ] Given `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "`, when run after this change, then it still resolves to exactly the five surfaces CLAUDE.md's invariant enumerates (this item touches none of them, so the count must be unchanged).
- [ ] Given the full existing test loop (`loomwright/scripts/test-*.sh` + root `scripts/check-*.sh` and `scripts/test-*.sh`), when run, then all are green with zero regressions, including a new mutation control on the length check (delete it, the 201-char rejection case must go red) and a new seam test mirroring `loomwright/scripts/test-brief-conformance-seam.sh`'s shape (static/grep-based, asserting step 1g's existence, the `DEVIATIONS ADVISORY` token's placement, per-iteration wording, and `fixer_deviations`, with its own mutation control).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Worker deviations record (schema → validator → parity → prompts → carriage → advisory) | all | 16 modify, 1 create | none needed (plain markdown/Python/bash edits) | LAUNCHABLE |

```yaml
# Subtask 1 — Worker deviations record (LAUNCHABLE, sole subtask)
provides:
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "deviations"}
  - {kind: "symbol", path: "loomwright/scripts/validate-worker-result.py", name: "REASON_DEVIATIONS_SHAPE"}
  - {kind: "file", path: "loomwright/scripts/test-deviations-advisory-seam.sh"}
requires: []
lanes:
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/scripts/validate-worker-result.py"
  - "loomwright/scripts/test-result-validators.sh"
  - "scripts/check-contract-parity.sh"
  - "loomwright/scripts/test-check-contract-parity.sh"
  - "loomwright/agents/worker.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/agents/context-keeper.md"
  - "loomwright/skills/state-management/SKILL.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/agents/code-reviewer.md"
  - "loomwright/scripts/test-deviations-advisory-seam.sh"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

### File Impact Map (verified line numbers — re-check at implementation time, this is a live, frequently-edited codebase)

**Modify:**
- `loomwright/docs/RESULT_SCHEMAS.md` — §WORKER_RESULT: add `deviations: string[]` after `out_of_lane` (line 31) and before `memory_candidates` (line 32), mirroring `out_of_lane`'s exact comment shape (optional/additive/does-not-bump-schema_version/validated-when-present) but describing the ≤12-entries/≤200-chars bound and the four-prefix convention (`plan:`/`edge:`/`open:`/`test:`, unprefixed read as `other:`, never rejected). Add the same invariant-note treatment `out_of_lane` gets (the paragraph starting near line 49). §FIX_RESULT (starts line 456, two YAML shapes at 460-467 and 477-484): add the SAME field/shape/bound to both shapes.
- `loomwright/scripts/validate-worker-result.py` — new rule 10, modeled EXACTLY on rule 9's `out_of_lane` implementation (lines 311-327: `if present(fields, "out_of_lane"): ... isinstance(..., list) ... isinstance(item, str) and not is_empty_scalar(item)`) plus the NEW constraints rule 9 doesn't have: ≤12 entries, each ≤200 chars. Add a `REASON_DEVIATIONS_SHAPE` constant mirroring `REASON_OUT_OF_LANE_SHAPE` (lines 142-145). Transcribe rule 10 into the module docstring's rule list exactly as rules 1-9 are documented (rule 9 is documented at lines 31-49). Absence accepted at ANY schema_version (same as rule 9).
- `loomwright/scripts/test-result-validators.sh` (3305 lines; `V_WORKER="$SCRIPT_DIR/validate-worker-result.py"` at line 54, `ok()`/`no()` counters at lines 78-79) — add a rule-10 case block mirroring rule 9's block (starts line 3093, comment `# rule 9 — out_of_lane...`, runs to ~line 3217): absent→accept, `[]`→accept, 4-prefixed-entries→accept, unprefixed-entry→accept, `null`→reject, non-array→reject, `[""]`→reject, 13-entries→reject, 201-char-entry→reject, each rejection asserting the message names "rule 10". Mutation control: delete the length check, confirm the 201-char case flips to accepted (proving the check is load-bearing).
- `scripts/check-contract-parity.sh` (repo root — NOT `loomwright/scripts/`, verified absent there) — WORKER_RESULT MANIFEST row (line 353: `worker|worker.md|WORKER_RESULT|schema_version,task_id,status,files_modified,summary,outputs_verified,outputs_gap,out_of_lane`) — append `,deviations` after `out_of_lane`.
- `loomwright/scripts/test-check-contract-parity.sh` — must still pass with the row change; add the requirement's own "one-off negation check" (row reverted to omit `deviations` while `RESULT_SCHEMAS.md` still lists it ⇒ FAIL).
- `loomwright/agents/worker.md` — WORKER_RESULT output block: insert `- deviations: ["plan: …", "edge: …", …]   # OPTIONAL` directly after line 213 (`memory_candidates`), before line 214 (`error`) — this file orders `out_of_lane`(212) before `memory_candidates`(213), the SAME relative order `RESULT_SCHEMAS.md` uses (`out_of_lane` at line 31, `memory_candidates` at line 32); place `deviations` after `memory_candidates` here specifically per the source requirement's explicit instruction (Scope item 4a: "directly after `memory_candidates`"), independent of where it lands in `RESULT_SCHEMAS.md`'s own schema-doc narrative (between `out_of_lane` and `memory_candidates` there, per that section's Scope item 1 instruction). New §"deviations" subsection beside §"memory_candidates" (which has the `.worker-summary.md` echo rule at Step 5.6, line 183) — four kinds, one example each, the ≤12/≤200 bound, the transient-(deviations)-vs-durable-(memory_candidates) distinction ("never cross-post" between the two), "never secrets/PII". Add the SAME echo rule for `deviations` as line 183's `memory_candidates` rule: a `## deviations` heading in `.worker-summary.md`, one `- ` bullet per entry verbatim, heading omitted when empty. **Token budget:** live-measured at planning time as EXACTLY `worker 5876/5905, 29 headroom` (re-verified, matches the requirement's cited figure with zero drift) — this new prose will not fit in the remaining 29-token headroom; raise `.agents.worker` in `loomwright/docs/prompt-token-budgets.json` (line 72 `"worker": {`, `note` field at line 75) to measured+~10% AFTER adding the prose and re-measuring (do not guess the new figure), and add a raise-log row in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" (heading line 494, worker row at line 519, existing raise-log template examples at lines 525/527/545) — never trim unrelated worker.md prose to make room. **Fixer prompt:** the Phase 4.5 fix-task spawn prompt (inside `loomwright/skills/self-heal-advisory/SKILL.md`'s review-and-fix loop) gains the `deviations` line in its FIX_RESULT output shape with conditional-mandatory wording: a FIX_RESULT whose diff edits a test assertion and carries no `test:` entry is incomplete.
- `loomwright/agents/context-keeper.md` — `record_worker_result` result-object row (line 44) — append `, deviations` to the field list, same treatment as `out_of_lane` already got there.
- `loomwright/skills/state-management/SKILL.md` — `## Worker Results` template (lines 104-111, `out_of_lane` bullet at line 110) — add a sibling `- deviations: [{entries}]   # empty when none; REPORT-ONLY` bullet after line 110.
- `loomwright/agents/supervisor.md` — BOTH mentions of "including the worker's `out_of_lane` field" (Single-Agent Path step 2, lines 288-289; Sequential Path per-subtask loop, lines 311-313) — extend both sentences to also name `deviations`. Also update Execute Manager's poll-loop record call (search for the parallel-path equivalent) to name `deviations` alongside `out_of_lane`.
- `loomwright/skills/self-heal-advisory/SKILL.md` — new step **1g "Deviations advisory (worker- and fixer-recorded plan drift — pre-review enrichment, ADVISORY ONLY, fail-safe)"** as a sibling paragraph to 1c (line 611), 1e (line 612), 1f (line 613) — same dense single-paragraph shape, no sub-bullets. Collect every `deviations` entry from `state.md`'s `## Worker Results` (prefixed by subtask_id) plus a NEW per-run `fixer_deviations` list (appended from each Phase 4.5 iteration's FIX_RESULT.deviations, prefixed `fix-<iteration>`, recorded in `state.md`'s `## Decisions Log` via `record_decision` on each append so it survives compaction) — bound to the same cap Part 1 uses for `brief_conformance`, with a VISIBLE truncation marker (item 02 §9 exempts truncated advisories, so the marker must be visible to the reviewer). Thread into the code-reviewer Task spawn prompt as a `DEVIATIONS ADVISORY` line placed directly after the `BRIEF-CONFORMANCE ADVISORY` line (confirmed anchor: line 702 inside the prompt block, NOT the descriptive prose at line 613 or the Miss-Class Checklist reference at line 694). Runs on EVERY Phase 4.5 iteration, not only the first. Skip silently (empty) when no `state.md` / no `## Worker Results` / zero entries. `record_decision(phase: SELF_HEAL, decision: "deviations_advisory: {non-empty|empty}", …)` on every path. Contract (state verbatim): fed to the review lens only, never to workers/fixers as an instruction; NEVER changes `heal_decision`, adds no gate, no schema field; the reviewer's response to a deviation IS ordinary findings (one `category: new` finding per deviation contradicting a stated acceptance criterion or Outcomes Rubric bullet, quoting both) — a merely-unexpected deviation is not a finding.
- `loomwright/agents/code-reviewer.md` — "Self-heal lens" paragraph (line 182, lists `brief_conformance` among the advisory inputs) — add `deviations` with the one-line question ("does this deviation break a stated criterion, not would-I-have-done-it-differently") and note that an unprefixed entry reads as `other:`. `scripts/check-command-sync.sh` does not cover this prose (memory `agent-command-mirror-drift-on-fixes`) — this is a manual consistency edit, no automated gate will catch its omission.
- `CHANGELOG.md` — one paragraph. `loomwright/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` — version bump only (README.md/CLAUDE.md do NOT need their own bump per the `release-surfaces-readme-claude-md-no-longer-bump` convention already used throughout this run).

**Create:**
- `loomwright/scripts/test-deviations-advisory-seam.sh` — mirrors `loomwright/scripts/test-brief-conformance-seam.sh`'s shape EXACTLY (226 lines; pure static/grep-based, no code execution — "every surface here is MARKDOWN"; `pass`/`fail` + local `ok()`/`no()` counters; a `prompt_line_adjacent()`-style awk check for the `DEVIATIONS ADVISORY` line's placement directly after `BRIEF-CONFORMANCE ADVISORY`; a bounded-cap-stated-once check; a reviewer-mirror check (code-reviewer.md names it); a checklist-mention check; a BLOCKING mutation control deleting the step-1g prompt line from a copy and asserting the check goes red). Also asserts: step 1g exists, runs per-iteration (not first-only), reads `fixer_deviations`.

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | none needed — plain markdown/Python/bash edits, no framework-specific skill applies |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope vs Supervisor Capability CAUTION — 17 files (16 modify, 1 create), single cohesive schema-threading change | MEDIUM | Kept single-subtask deliberately (every touch depends on the same field definition, splitting would just serialize); worker should expect multiple turn-limit resumes, matching items 06/08's scale in this run. |
| `deviations`' insertion point differs between the two files, though both order `out_of_lane`/`memory_candidates` identically | LOW | Both `RESULT_SCHEMAS.md` (out_of_lane:31, memory_candidates:32) and `worker.md` (out_of_lane:212, memory_candidates:213) order the two existing fields the SAME way — verified, not opposite. The requirement's explicit instruction ("directly after `memory_candidates`") is worker.md-specific (Scope item 4a); `RESULT_SCHEMAS.md` places `deviations` between `out_of_lane` and `memory_candidates` per that section's own Scope item 1 instruction. Two different explicit per-file instructions, not two files disagreeing on field order. |
| Requirement's caller-level prose said `loomwright/scripts/check-contract-parity.sh` and similar | LOW | Independently re-verified: `check-contract-parity.sh` and `check-token-budget.sh` live at REPO-ROOT `scripts/`, not `loomwright/scripts/` — confirmed absent from the latter. The requirement's OWN Scope/Acceptance-criteria text already uses the correct root-relative form; only a caller-level restatement was imprecise. File Impact Map above uses the verified root-relative paths throughout. |
| Token-budget headroom (29 tokens) will not fit the new prose | LOW (expected, in scope) | Requirement explicitly scopes the raise as part of this item — re-measure via `bash scripts/check-token-budget.sh` AFTER writing the prose (live-verified at planning time as still exactly 5876/5905/29 headroom, zero drift from the requirement's cited figure), never guess the new number in advance. |
| `agent-command-mirror-drift-on-fixes` — no automated gate covers `code-reviewer.md`'s prose sync with `self-heal-advisory/SKILL.md` | LOW | Flagged explicitly in the File Impact Map; this is a manual-consistency edit the worker must remember, not something `check-command-sync.sh` will catch if forgotten. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-23-worker-deviations.md
```
