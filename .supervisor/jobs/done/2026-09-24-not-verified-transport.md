# Supervisor Job: `not_verified` transport end-to-end (worker → state → PR body + done brief → `/verify` impact rows)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: automate-hardening-2026-09-22 (worktree; the run's isolation branch, base main @ 076a18c)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/harness-port/04-not-verified-transport.md

## Feasibility (optional — Launch Pad v10.3+)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash script edits (`context-keeper.md`'s `record_worker_result` op, `verify-run.sh`'s `acs` command) + markdown prompt/skill/doc edits — matches the plugin's existing tech stack exactly, and `not_verified` already exists on the WORKER_RESULT schema (item 01, merged) with a validated `{surface, reason}` shape. |
| 2 | Dependency Availability | GO | No new dependency; reuses `jq` (already used throughout `verify-run.sh` and `context-keeper.md`'s state-writing conventions). |
| 3 | Architecture Fit | GO | Extends the EXISTING `out_of_lane`/`deviations` REPORT-ONLY transport pattern (`record_worker_result` → `state.md ## Worker Results` → PR body) with a third field of the same shape, and extends `verify-run.sh acs`'s existing brief-vs-requirement `ticket_kind` branch with one additive output key — both are precedent-following, not novel plumbing. |
| 4 | Scope vs Supervisor Capability | GO | 8-file, single cohesive transport-chain change (one field flowing through 5 existing surfaces); no file-conflict/context-bound/genuine-parallelism reason to split — every file in the chain depends on the one preceding it, so parallelizing would only add coordination overhead. |
| 5 | Hard Blockers | GO | No migration framework, no credentials, no missing modules. `not_verified` schema/validator already shipped (item 01, PR #259, merged into `main`). |

**Overall Verdict:** GO

## Task
**Goal:** Make a worker's `not_verified` list (item 01: "surfaces the diff affects that weren't observed running, with a reason") actually reach a human and `/verify` — today it dies in the worker's transcript the instant `EXECUTE_RESULT` is built, because no downstream surface (state file, PR body, done brief, or `/verify`'s impact-row reader) carries it forward.

**Problem Statement:**
`EXECUTE_RESULT` (`docs/RESULT_SCHEMAS.md` §EXECUTE_RESULT) has no per-worker optional fields — per-worker reports travel via Context-Keeper's `record_worker_result` operation into `state.md`'s `## Worker Results` section instead, exactly as `out_of_lane` and `deviations` already do. `record_worker_result`'s parameter contract does not yet include `not_verified`. The Phase 4 FINALIZE PR-body template has no section for it. The completion tail that stamps a brief `## Status: done` doesn't carry it either. And `/verify` resolves a ticket by reading its `## Acceptance Criteria` bullets — it has no path to a PR body at all, and no path to a worker's per-run transcript. Zero of the three "a human or `/verify` could see this" surfaces exist today.

## Acceptance Criteria
- [ ] `loomwright/agents/context-keeper.md`'s `record_worker_result` operation's parameter list gains `not_verified` (mirroring `out_of_lane`/`deviations`'s existing entries exactly); the `## Worker Results` row it writes gains one `not_verified: <n>` count when `n>0`, with the items as an indented sub-list (`- <surface> — <reason>`) directly under that row; when `n=0` or the field is absent, the row is byte-identical to today's (no `not_verified: 0`, no empty sub-list). **`loomwright/skills/state-management/SKILL.md`'s `## Worker Results` template (the `### {worker-id} ({subtask-id})` block, currently ending `- out_of_lane: [{paths}]` / `- deviations: [{entries}]`) gains the matching `- not_verified: [{surface — reason}]` template line in the SAME PR** — `context-keeper.md` states explicitly "Schema must match `skills/state-management/SKILL.md`," and both `out_of_lane` and `deviations` already updated this file alongside their `context-keeper.md` operation-table entries; this is the schema authority, not `docs/RESULT_SCHEMAS.md`.
- [ ] `loomwright/agents/execute-manager.md`'s parallel-path poll loop passes a worker's `not_verified` through to `record_worker_result` unchanged (mirrors the existing `out_of_lane`/`deviations` passthrough). `loomwright/skills/async-orchestration/SKILL.md`'s Sequential and Single-Agent paths record it the same way, with one new sentence mirroring the existing "records the report only" `out_of_lane` sentence. `EXECUTE_RESULT` stays `schema_version: 1` — this is additive-only, not a new EXECUTE_RESULT field (see the `out_of_lane` blockquote at `docs/RESULT_SCHEMAS.md` — the field genuinely never appears on EXECUTE_RESULT itself, only inside `state.md`).
- [ ] `loomwright/skills/async-orchestration/SKILL.md` Part 2's FINALIZE PR Body Template gains a new optional `## Not verified` section, placed immediately after `## Test Plan` and before `## Task`: one bullet per item across ALL workers, `- **<surface>** — <reason> (subtask <id>)`, aggregated by reading `state.md`'s `## Worker Results` section. When every worker's `not_verified` list is absent/empty, the section is OMITTED ENTIRELY (no heading, no "none" line) — a zero-item PR body must diff byte-identical against `origin/main`'s template output.
- [ ] The done-brief completion tail (`loomwright/skills/self-heal-advisory/SKILL.md` step 2.5 — the same step that stamps `## Status: done`/`## Status: done_with_escalation`) appends the SAME `## Not verified` section (same bullet shape, same omit-when-empty rule) to the brief itself when non-empty — this is the surface `/verify` can actually read; the PR body is for the human only.
- [ ] `loomwright/scripts/verify-run.sh`'s `acs <ticket>` command gains, ONLY for `ticket_kind: brief` (never `requirement` — a requirement file has no completion tail to have written the section), an additional output key `not_verified: [{id: "NV1", text: "<surface> — <reason>", source: "not_verified", surfaces: []}]`, parsed from the brief's `## Not verified` bullets; an absent section (or `ticket_kind: requirement`) ⇒ `not_verified: []`. The pre-existing `acs` array/key is UNCHANGED — this is a pure addition, verified by diffing `acs <ticket>`'s output before/after on a brief with no `## Not verified` section (must be byte-identical modulo the new empty key).
- [ ] The qa-executor `--verify` step reads `acs`'s new `not_verified` objects and feeds them into the SAME existing impact manifest the `diff`/`brief-surfaces`/`prior-acs` sources already populate (`walk --scope impact --manifest`, shape `{id, text, source, surfaces}`) — landing in the impact table, NEVER in the ticket's own PASS/FAIL/BLOCKED/NOT_VERIFIABLE score or counts line (the `summary-build scope: "ticket"` filter already enforces this for every other impact source; verify it also excludes `not_verified`-sourced rows by inspecting/testing that filter, not by assuming it).
- [ ] `loomwright/skills/verify-walkthrough/SKILL.md`'s impact-scope section documents `not_verified` as an additional best-effort source alongside the diff / classification / brief-surfaces / prior-acs / smoke sources already listed there, with the same "NEVER inflates or deflates the ticket score" sentence used for the others and `source: "not_verified"` provenance — read the section's actual current numbering/wording first (it lists 5 items under two headed groups, not literally "third" as the source requirement's shorthand suggests) and slot the new source in accurately rather than mechanically re-numbering.
- [ ] `loomwright/docs/RESULT_SCHEMAS.md` gains: (a) a transport note beside the existing `out_of_lane` blockquote under §EXECUTE_RESULT, stating `not_verified` also reaches `state.md` via Context-Keeper, not EXECUTE_RESULT itself; (b) `docs/RESULT_SCHEMAS.md`'s own `## CONTEXT_KEEPER_STATE` section does NOT document the `## Worker Results` row body today (verified: zero out_of_lane/deviations mentions there) — the actual row-shape template lives in `loomwright/skills/state-management/SKILL.md` (see the dedicated AC above), so this sub-item is satisfied there, not by inventing new RESULT_SCHEMAS.md content that doesn't match the existing out_of_lane/deviations precedent; (c) if a VERIFY_* schema documents an enumerated `source` value set for impact-manifest entries, add `not_verified` to that enum (read the actual enum first — do not assume one exists; if `source` is documented as free-form/open-set like `PLAN_REVIEW_RESULT.issues[].category`, say so instead of inventing an enum).
- [ ] Fixture: a `state.md` with two workers, one carrying exactly one `not_verified` item ⇒ the FINALIZE PR body contains exactly one `## Not verified` bullet; the same fixture with neither worker carrying one ⇒ the PR body has no such heading at all (byte-diff against `origin/main`'s template output on the same fixture).
- [ ] Fixture: the done brief for that same run carries the identical section; `bash loomwright/scripts/verify-run.sh acs <that brief path>` returns the pre-existing `acs` array completely unchanged and a `not_verified` array with exactly one object whose `source` field equals `"not_verified"`.
- [ ] Fixture: `verify-run.sh summary-build` run against evidence containing an impact-scope `ac` line sourced from an `NV1` id reports the ticket's own PASS/FAIL/BLOCKED/NOT_VERIFIABLE counts line IDENTICAL to a ticket-only fixture with no such row (i.e. the impact row is present in evidence but excluded from the ticket counts) — assert this by comparing the counts line text, not by inspection.
- [ ] Fixture: `record_worker_result` called with a `not_verified` list writes the count + sub-list correctly; called WITHOUT one writes a `## Worker Results` row byte-identical to today's (mutation/regression-style: run the same fixture on `origin/main`'s `context-keeper.md`-implied output shape and confirm no diff when the field is absent).
- [ ] `scripts/check-token-budget.sh` green — re-measure `context-keeper` live (do not trust the source requirement's cited "headroom 319" figure; independently confirmed via a live read of `docs/prompt-token-budgets.json` that the CURRENT headroom before this change is 347, not 319 — it may have shifted again since; re-measure at implementation time) and raise + mirror in `ARCHITECTURE_CONTRACTS.md` if the new parameter-list entry and Worker-Results row text breach the existing budget.
- [ ] CHANGELOG.md gains one paragraph; `plugin.json` + `marketplace.json` version bump (patch — additive, non-breaking, no gating behavior change per the source requirement's own Non-goals). README.md/CLAUDE.md are NOT touched (memory: `release-surfaces-readme-claude-md-no-longer-bump`).
- [ ] Full test loop (`loomwright/scripts/test-*.sh` + root `scripts/test-*.sh` + `scripts/check-vendor-coupling.sh` + `scripts/check-doc-currency.sh` + `scripts/test-citation-drift.sh`) green. `acs`'s existing coverage lives in `loomwright/scripts/test-verify-walkthrough.sh` (extensive `acs`-tagged assertions) — extend it with `not_verified`-key fixtures, don't bypass it. No existing `record_worker_result`/context-keeper suite covers this row today; per this repo's own precedent for the prior two advisory Worker-Results fields (`out_of_lane`, then `deviations`), each shipped with a DEDICATED new static-wiring test file rather than an extension of a generic suite — see `loomwright/scripts/test-deviations-advisory-seam.sh` as the shape to model a new test file on for the context-keeper/state-management wiring.

## Non-goals (from the source requirement — do not implement)
No change to `outputs_verified` / `outputs_gap` / adjudication. No PR-body reader added to `/verify` (the brief, not the PR body, is `/verify`'s surface). No new `ac_id` family — `AC<n>` ordinals and `summary-build`'s `scope: "ticket"` filter are untouched. No gating anywhere: a non-empty `## Not verified` section must never block FINALIZE, Phase 4.5, a `READY` drain decision, or `/automate`'s gate-eval.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `not_verified` transport: context-keeper param + state row → PR body + done brief → verify-run.sh acs + impact manifest + doc sync | all | 12 modify, 0 create | quality-checklist, async-orchestration, verify-walkthrough, self-heal-advisory | LAUNCHABLE |

```yaml
# Subtask 1 — not_verified end-to-end transport (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/agents/context-keeper.md", name: "record_worker_result"}
  - {kind: "symbol", path: "loomwright/skills/state-management/SKILL.md", name: "not_verified"}
  - {kind: "symbol", path: "loomwright/skills/async-orchestration/SKILL.md", name: "Not verified"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "Not verified"}
  - {kind: "symbol", path: "loomwright/scripts/verify-run.sh", name: "not_verified"}
  - {kind: "symbol", path: "loomwright/skills/verify-walkthrough/SKILL.md", name: "not_verified"}
requires: []
lanes:
  - "loomwright/agents/context-keeper.md"
  - "loomwright/skills/state-management/SKILL.md"
  - "loomwright/agents/execute-manager.md"
  - "loomwright/skills/async-orchestration/SKILL.md"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/scripts/verify-run.sh"
  - "loomwright/skills/verify-walkthrough/SKILL.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (single subtask — a linear transport chain: context-keeper -> state.md -> PR body / done brief
           -> verify-run.sh acs -> impact manifest; each surface depends on the one before it, so
           splitting would only add coordination cost, never real parallelism)
```

### File Overlap Matrix
N/A — single subtask, no sibling to overlap with.

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/async-orchestration/SKILL.md`, `skills/verify-walkthrough/SKILL.md`, `skills/self-heal-advisory/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| The source requirement's own headroom citation for `context-keeper` ("Headroom 319") does not match a live read of `docs/prompt-token-budgets.json` (currently 347, itself likely to have shifted again by implementation time given how many recent items in this run have touched adjacent prompt files). A worker trusting the stale citation could under- or over-estimate whether a raise is needed. | MEDIUM | Acceptance criteria explicitly require a LIVE re-measure at implementation time, never the requirement's cited figure — same pattern already applied successfully in harness-port/03. |
| `verify-walkthrough/SKILL.md`'s impact-scope section actually documents 5 numbered items across two groups ("Three sources feed the surface classification" [diff/classification/brief-surfaces] plus "Two more passes" [prior-acs/smoke]) — NOT a flat "third source after diff/brief-surfaces/prior-acs" as the source requirement's Scope item 6 shorthand implies (that shorthand skips over "classification" and reorders relative to the doc's real structure). A worker following the requirement's literal wording could insert the new source in a structurally awkward or misnumbered spot. | MEDIUM | Acceptance criterion explicitly instructs reading the section's actual current structure first and slotting the new source in accurately, rather than mechanically obeying the requirement's paraphrase — the intent (documented, non-gating, same "never inflates/deflates" sentence) is what must be preserved, not the exact ordinal. |
| The `summary-build scope: "ticket"` filter that excludes impact-scope rows from the ticket's own score is asserted by the source requirement to already work for `prior-acs`/`smoke`-sourced rows, but this item is the first time a `not_verified`-sourced row specifically needs to be proven excluded — an easy place to assume rather than verify given the filter's existing behavior for OTHER sources. | LOW | Acceptance criterion requires an explicit fixture test comparing the ticket counts line with vs. without an `NV1`-sourced impact row present in evidence, not just citing the existing filter's behavior for other sources as sufficient. |
| `record_worker_result`'s existing `## Worker Results` row-writing logic is prose in `context-keeper.md`, not a shared script both the parallel (execute-manager) and sequential (Supervisor-inline) paths call through — a worker could implement the new field correctly for one path and silently miss the other, exactly the class of bug `out_of_lane`'s Sequential-path note already had to correct for once. | MEDIUM | Acceptance criteria explicitly require the passthrough on BOTH `execute-manager.md`'s parallel-path poll loop AND `async-orchestration/SKILL.md`'s Sequential/Single-Agent paths, each verified independently against its own current wording, not inferred from the other. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-24-not-verified-transport.md
```
