# Supervisor Job: Rules reach every review — the Code Reviewer reads the house-rules store itself, so `/code-reviewer`, `/review-pr` and the `/automate` drain stop being rule-blind

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean apart from the gitignored run file; branch `main` == origin/main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (installed plugin cache is 15.108.4, repo is 15.112.0 — the inlined workflow bodies were read from the repo checkout; the code under change is the repo's own `loomwright/`)
- **Source requirement:** .supervisor/requirements/automate-followups/10-rules-reach-standalone-review.md
- **Base commit:** 5a76bdcdc622c156c6674ab55e1bb9ed8ca19cbc

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Agent/command/skill markdown + one bash self-test + docs. The test must stay macOS bash 3.2 / BSD-userland compatible. |
| 2 | Dependency Availability | GO | No new dependency. Reuses `read-rules.sh` (fail-safe, always exit 0, self-gates on `.agent/rules/*.json`) exactly as the worker and Phase 4.5 seams call it. |
| 3 | Architecture Fit | GO | Putting the read in the agent (not in each caller) covers `/code-reviewer`, `/review-pr` (review-heal Step 2 and the Earned Fallback Review spawn) and any future caller with one edit. The reviewer is read-only by frontmatter; Bash stays allowed, so no tool change. |
| 4 | Scope vs Supervisor Capability | GO | ~9 files, 0 created. One subtask. |
| 5 | Hard Blockers | GO | None. Two requirement premises have moved since 2026-09-27 and are re-verified below (budget headroom grew; `review-heal/SKILL.md` now names `rules-check.sh`/`read-rules.sh` twice, in the item-07 drain READY clause — that is the merge-gate helper, not a reviewer-prompt injection, so the premise "the drain's reviewer spawn carries no rules line" still HOLDS). |

**Overall Verdict:** GO

## Task
**Goal:** Every `loomwright:code-reviewer` run sees the house rules that apply to the files it reviews, whoever spawned it: the agent calls `read-rules.sh` with its review-scope paths as arguments right after it determines its scope, unless its spawn prompt already carries Phase 4.5's **HOUSE-RULES ADVISORY** line, in which case it uses that line and does not read again. The rules stay advisory exactly as they are at Phase 4.5 today.

**Problem Statement:** The house-rules seam is wired at the caller, not the reviewer. Phase 4.5 works only because `skills/self-heal-advisory/SKILL.md` runs the reader and pastes the result into the reviewer's Task prompt. `agents/code-reviewer.md` never reads the store (`grep -ciE 'read-rules|rules-check|audit-rules|\.agent/rules|house.rules' loomwright/agents/code-reviewer.md` = 0 at base), and no other caller injects. So standalone `/code-reviewer`, `/review-pr`, and every round of the `/automate` owned `--until-mergeable` drain review with no knowledge of the rules.

## Design decisions (settled here so the worker does not choose)
1. **New Context Setup step `4a` in `loomwright/agents/code-reviewer.md`, immediately after step 4 "Determine Review Scope" and before step 5 "Load Quality Criteria".** Use `4a` (not a renumber of 5/6) so no existing step reference moves. Title: `**Consult house rules (advisory, read-only)**`. Contents, kept to a few bullets:
   - **Dedupe first:** if the spawn prompt carries a **HOUSE-RULES ADVISORY** line (Supervisor Phase 4.5), use it as-is and do NOT read again — Phase 4.5 computed it on the integrated-diff scope, which may be wider than the scope you would infer.
   - **Otherwise** run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-rules.sh" <review-scope paths…>` — the scope paths from step 4 as command-line **ARGUMENTS, never stdin** (the no-hang shape). An empty path set fails OPEN to repo-wide, which is the safe direction.
   - **Empty output ⇒ no enrichment and no placeholder** — never write a "no house rules" line anywhere (same wording rule as Phase 4.5).
   - **Contract by pointer, not copy:** the rules are the SAME advisory input the Phase 4.5 HOUSE-RULES ADVISORY line carries — `skills/self-heal-advisory/SKILL.md` §"House-rules advisory (committed convention enrichment)" and its Part 2 prompt line. Restate only the load-bearing core in one sentence: they bias WHERE you look, never WHETHER the diff passes; a rule never adds a finding or changes `decision` by itself (anything you find where a rule pointed is judged under the existing criteria and severity rules); subordinate to CLAUDE.md and `REVIEW.md`. No new decision state, no `CODE_REVIEW_RESULT` field.
   - **Reader only:** each rule's `check` is DATA — never execute, eval, source or `bash -c` it. Write this line with the word `never`/`NEVER` next to the reader name (the seam test's (C) allowlist keys on it).
   - **Do NOT name `rules-check.sh` or `audit-rules.sh` anywhere in `agents/code-reviewer.md`, not even in a negative sentence.** Seam (B) greps the literal filename with zero tolerance for this surface (there is no `--if-stamped` exception here); say "never execute a rule's `check`" instead.
   - Frontmatter (`disallowedTools`, `tools`, `permissionMode`, `memory`, `skills`) is unchanged.
2. **Resolving the requirement's internal tension on (c).** The requirement's Goal says the rules stay advisory "exactly as they are at Phase 4.5 today", and its scope (c) says "a clear violation … may become an ordinary finding". The Phase 4.5 prompt line today says the rules NEVER change the reviewer's `decision` and bias WHERE, not WHETHER. The Goal wins: the new step uses the Phase 4.5 contract unchanged (decision 1's one-sentence core). A reviewer may still report a genuine defect in code a rule pointed it at — judged on the existing criteria, never on "the rule says so". Say this in the PR body.
3. **`loomwright/scripts/test-rules-seams.sh` — extend deliberately.**
   - Add `"$PLUGIN_ROOT/agents/code-reviewer.md"` to BOTH the `SEAMS` array (so (A)/(B)/(C) cover it; (B) is the zero-tolerance `elif grep -qF 'rules-check.sh'` branch — no exception) and the `ARGS_BEARING` array (so (D) pins the path-argument placeholder).
   - Header comment: add the reviewer to the seam list and to the (D) args-bearing list, and to the PART 2 shape (i) description (it is the same `bash read-rules.sh <paths…>` shape). **Replace the literal count word `FOUR` (both occurrences in the header: "the FOUR advisory house-rules enforcement seams" and "The FOUR advisory seams") with count-free wording** ("the advisory house-rules enforcement seams listed below"; the `SEAMS` array is the authority). This satisfies the requirement's "update the header count" and the applicable house rule (a count lives in one place). Also fix the "(D) … Three surfaces carry such an invocation" line the same way (it becomes four; write it count-free).
   - **Mutation control for (D) on the new surface (AC1):** add a small block after the (D) loop: copy `agents/code-reviewer.md` to a `mktemp` file, delete the placeholder from the reader line with a `sed` whose delimiter cannot collide with the target line, and assert (i) the mutant is non-empty, (ii) differs from the original, (iii) `grep -qE "$ARGS_SHAPE_RE"` FAILS on the mutant, and (iv) the same grep PASSES on the unmutated original (positive control). Any of (i)/(ii) failing is a test FAILURE (an invalid mutant is not evidence — lesson fa32a308), not a skip. Clean the temp file up.
4. **`loomwright/commands/code-reviewer.md` (thin wrapper).** In "What This Does", extend item 4 in place (no renumbering): `4. **Reads review rules** from optional REVIEW.md (falls back to CLAUDE.md), and the project's applicable **house rules** (advisory; skipped when Supervisor already passed them in)`. No `${CLAUDE_PLUGIN_ROOT}` token, no script path, no policy restated — `scripts/check-command-sync.sh` must stay green.
5. **Seam enumerations — update every restating copy in this change (house rule).** Insert `Code Reviewer` into the seam list at exactly these five places (grep the OLD phrases repo-wide first and fix any additional hit the same way):
   - `loomwright/commands/rules.md` frontmatter `description:` — `worker / Phase 4.5 / SessionStart-nudge seams` ⇒ `worker / Phase 4.5 / Code Reviewer / SessionStart-nudge seams`.
   - `loomwright/commands/rules.md` intro paragraph — `worker / Phase 4.5 self-heal / SessionStart-nudge seams` ⇒ `worker / Phase 4.5 self-heal / Code Reviewer / SessionStart-nudge seams`.
   - `loomwright/skills/rules/SKILL.md` Slice #3b-ii paragraph — `worker / Phase 4.5-self-heal / SessionStart-nudge seams` ⇒ `worker / Phase 4.5-self-heal / Code Reviewer / SessionStart-nudge seams`.
   - `loomwright/skills/rules/SKILL.md` bullet — `worker / Phase 4.5 / nudge seams` ⇒ `worker / Phase 4.5 / Code Reviewer / nudge seams`.
   - `loomwright/commands/agent-help.md` `/rules` Purpose paragraph — `worker / Phase 4.5 self-heal / SessionStart-nudge seams` ⇒ `worker / Phase 4.5 self-heal / Code Reviewer / SessionStart-nudge seams`.
   Also re-check `loomwright/skills/self-heal-advisory/SKILL.md` §"House-rules advisory" for a sentence claiming the Phase 4.5 prompt is the ONLY way the reviewer sees rules; if one exists, add a pointer to the new agent step (do NOT otherwise edit that file — Phase 4.5's injection is unchanged).
6. **Token budget.** Run `scripts/check-token-budget.sh` after the agent edit. At base `code-reviewer` is 25057 / 27563 (2506 headroom). Raise ONLY on a breach (anti-treadmill rule, `docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets"); if raised, update BOTH `loomwright/docs/prompt-token-budgets.json` (budget + `measured` + one-line `note` justification) and the mirror row + raise-log line in `ARCHITECTURE_CONTRACTS.md`. If not raised, touch neither file.
7. **Release.** Minor bump 15.112.0 ⇒ 15.113.0 in `loomwright/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, with a new top `CHANGELOG.md` entry (single bold `**v15.113.0 — title:**` paragraph, placed per the existing convention). No agent/command/skill/hook count changes; plugin descriptions are not edited. `agents/*` is ADAPTER class in `loomwright/docs/vendor-coupling-manifest.json` (not counted), so the new `${CLAUDE_PLUGIN_ROOT}` line in the agent needs no manifest edit — still run `scripts/check-vendor-coupling.sh` to confirm.

## Acceptance Criteria
- [ ] **AC1 (agent step + mutation control):** `loomwright/agents/code-reviewer.md` Context Setup has step `4a` invoking `read-rules.sh` with a path-argument placeholder, after step 4 "Determine Review Scope". `bash loomwright/scripts/test-rules-seams.sh` passes, including a new (D) row for `agents/code-reviewer.md`, and the decision-3 mutant (placeholder removed) makes the (D) regex fail while the unmutated original passes; the mutant is asserted non-empty and different from the original.
- [ ] **AC2 (dedupe):** step 4a states that an injected **HOUSE-RULES ADVISORY** line is used as-is and the agent does not read again. `grep -cF 'HOUSE-RULES ADVISORY' loomwright/agents/code-reviewer.md` ≥ 1 (was 0).
- [ ] **AC3 (reader only):** `grep -cE 'rules-check\.sh|audit-rules\.sh' loomwright/agents/code-reviewer.md` = 0, and `test-rules-seams.sh` (B) passes on it through the zero-tolerance branch (no exception added for this surface). (C) passes (no reader output piped/eval'd/sourced).
- [ ] **AC4 (empty store):** step 4a says empty reader output ⇒ no enrichment and no "no house rules" placeholder.
- [ ] **AC5 (contract unchanged):** no `CODE_REVIEW_RESULT` field or `schema_version` change; `docs/RESULT_SCHEMAS.md` untouched; `scripts/check-contract-parity.sh` green; the agent frontmatter is byte-identical to base.
- [ ] **AC6 (wrapper):** `loomwright/commands/code-reviewer.md` "What This Does" item 4 mentions the house-rules read; `scripts/check-command-sync.sh` green.
- [ ] **AC7 (enumerations):** the five decision-5 edits landed, and `git grep -nE 'worker / Phase 4\.5(-self-heal| self-heal)? / (SessionStart-)?nudge seams'` returns no hit outside `CHANGELOG.md` history.
- [ ] **AC8 (budget):** `scripts/check-token-budget.sh` green for `code-reviewer`; budget files touched only on a breach (decision 6).
- [ ] **AC9 (release):** version 15.113.0 in `plugin.json` + `marketplace.json`; new top CHANGELOG entry; `scripts/check-doc-currency.sh` and `scripts/validate-version.sh` green.
- [ ] **AC10 (full loop green):** run under `bash`: every `loomwright/scripts/test-*.sh`, `loomwright/scripts/adapters/*/test-*.sh` and root `scripts/test-*.sh`; plus `scripts/check-vendor-coupling.sh`, `scripts/check-doc-currency.sh`, `scripts/check-command-sync.sh`, `scripts/check-skills-index-sync.sh`, `scripts/check-token-budget.sh`, `scripts/check-test-hermetic.sh`, `scripts/check-contract-parity.sh`, and `loomwright/scripts/test-citation-drift.sh` (run the last one after the final prose edit — pinned citations into edited files must still resolve).
- [ ] **Invariants:** `skills/self-heal-advisory/SKILL.md`'s Phase 4.5 injection, `skills/review-heal/SKILL.md`, `skills/automate-loop/SKILL.md`, `scripts/automate-helpers.sh` and `.github/workflows/claude-code-review.yml` are unchanged (decision 5's conditional one-line pointer in self-heal-advisory is the only allowed exception); `read-rules.sh` routing and the rule schema are unchanged; `rules-check.sh` remains the only file that executes a rule `check`; the `gh pr merge --squash` positive grep resolves to the same 5 surfaces; no new agent/command/skill/hook.

## Non-goals
- The `claude-review` CI bot (item 02 / item 08 questions).
- Claude Code's built-in `/code-review` (not a Loomwright surface).
- Making a rule violation block, or running any `check` from the reviewer (items 06/07).
- Changing `read-rules.sh` routing or the rule schema.
- Changing what Phase 4.5 injects or how.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Reviewer step 4a + seam-guard extension with mutation control + wrapper line + seam enumerations + version/CHANGELOG | AC1–AC10, Invariants | ~9 modify, 0 create | unit-testing, quality-checklist | LAUNCHABLE |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/agents/code-reviewer.md", name: "read-rules.sh"}
  - {kind: "symbol", path: "loomwright/agents/code-reviewer.md", name: "HOUSE-RULES ADVISORY"}
  - {kind: "symbol", path: "loomwright/scripts/test-rules-seams.sh", name: "agents/code-reviewer.md"}
  - {kind: "symbol", path: "loomwright/commands/code-reviewer.md", name: "house rules"}
  - {kind: "symbol", path: "loomwright/commands/rules.md", name: "Code Reviewer / SessionStart-nudge"}
  - {kind: "symbol", path: "loomwright/skills/rules/SKILL.md", name: "Code Reviewer / nudge"}
  - {kind: "symbol", path: "loomwright/commands/agent-help.md", name: "Code Reviewer / SessionStart-nudge"}
  - {kind: "symbol", path: "loomwright/.claude-plugin/plugin.json", name: "15.113.0"}
requires: []
lanes:
  - "loomwright/agents/code-reviewer.md"
  - "loomwright/commands/code-reviewer.md"
  - "loomwright/scripts/test-rules-seams.sh"
  - "loomwright/commands/rules.md"
  - "loomwright/skills/rules/SKILL.md"
  - "loomwright/commands/agent-help.md"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

## Parallelism Analysis
- **Batch 1:** Subtask 1
- **Recommended workers:** 1 (single-agent)
- **Estimated batches:** 1

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| reviewer seam | `loomwright/agents/code-reviewer.md` (step 4a), `loomwright/commands/code-reviewer.md` (item 4) | — | HIGH |
| seam guard | `loomwright/scripts/test-rules-seams.sh` (SEAMS + ARGS_BEARING + header + mutation block) | — | HIGH |
| enumerations | `loomwright/commands/rules.md`, `loomwright/skills/rules/SKILL.md`, `loomwright/commands/agent-help.md`, `loomwright/skills/self-heal-advisory/SKILL.md` (LOW — only if decision 5's "only way" sentence exists) | — | HIGH |
| budget (only on breach) | `loomwright/docs/prompt-token-budgets.json`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | — | LOW |
| release | `CHANGELOG.md`, `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | — | HIGH |

> **Validator-owned surfaces:** AC5–AC10 depend on `scripts/check-command-sync.sh` (scans `commands/code-reviewer.md`), `scripts/check-contract-parity.sh`, `scripts/check-token-budget.sh` (measures `agents/code-reviewer.md` + its preloaded skills), `scripts/check-doc-currency.sh`, `scripts/check-vendor-coupling.sh` and `loomwright/scripts/test-citation-drift.sh`. `loomwright/scripts/test-rules-docs.sh` also greps `commands/rules.md` / `skills/rules/SKILL.md` — run it after the decision-5 edits.

## Skill References
- `skills/unit-testing/SKILL.md` (bash self-tests; gated mutants — non-empty + differs + positive control)
- `skills/quality-checklist/SKILL.md`
- `skills/self-heal-advisory/SKILL.md` §"House-rules advisory (committed convention enrichment)" + Part 2 HOUSE-RULES ADVISORY line — the contract step 4a points to (read it; do not copy it)
- `skills/rules/SKILL.md` §"applies_to" routing (fail-OPEN on an empty path set) — pointer only
- `loomwright/scripts/test-rules-seams.sh` header — the (A)–(D) semantics being extended

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

> Advisory only (no `must` rule applies, so no `rule:` bullets). Applied here: decision 3 drops the literal `FOUR`/`Three` counts from the seam test's header (the `SEAMS`/`ARGS_BEARING` arrays are the authority); decision 1 points at the Phase 4.5 contract instead of restating it; decision 5 updates every restating seam enumeration in the same change.

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Step 4a's prose names `rules-check.sh`/`audit-rules.sh` (e.g. "never run rules-check.sh") and trips seam (B)'s zero-tolerance grep | HIGH | Decision 1 last bullet; AC3 static grep = 0. |
| The reader call loses its path argument (bare `read-rules.sh` ⇒ always repo-wide) | HIGH | Decision 3 adds the surface to (D) plus a gated mutant proving (D) catches it (AC1). |
| The new step drifts from Phase 4.5's advisory contract (lets a rule change `decision`, or adds a finding "because the rule says so") | MEDIUM | Decision 2 settles the requirement's (c) tension in favor of the Phase 4.5 contract; one-sentence core + pointer. |
| Phase 4.5 reviewer reads twice when the injected line is absent (empty `house_rules`) | LOW | Harmless: same store, the scope it infers is the same diff, and empty ⇒ no enrichment. Dedupe keys on the line's presence, which is the only signal the reviewer has. |
| A seam enumeration copy is missed (5 known places) | MEDIUM | Decision 5 list + AC7 repo-wide grep for the OLD phrases. |
| `test-rules-docs.sh` regexes over `commands/rules.md` / `skills/rules/SKILL.md` break on the enumeration edit | LOW | Run it after decision 5 (validator-owned surfaces note). |
| Token budget breach on `code-reviewer` | LOW | 2506 headroom at base; decision 6 raise-on-breach-only procedure. |
| Invalid mutant silently passes (sed delimiter collision / no-op edit) | MEDIUM | Decision 3 asserts non-empty + differs + positive control; an invalid mutant FAILS the test. |
| Worker turn limit (earlier items in this queue hit 40 turns) | LOW | Resume via SendMessage on a turn-limit, never respawn. |

## Configuration
- **Mode:** single-agent
- **Recommended workers:** 1
- **Estimated batches:** 1

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-09-29-rules-reach-standalone-review.md

## Outcome
- **Status:** completed
- **Completed:** 2026-09-29T12:00:23Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/301
- **Branch:** feature/automate-followups-10-rules-reach-standalone-review
- **Files changed:** 9
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** `agents/code-reviewer.md` Context Setup step 4a reads the house rules itself (`read-rules.sh <review-scope paths…>`, args not stdin) unless Phase 4.5's HOUSE-RULES ADVISORY line is injected (dedupe); Phase 4.5 contract by pointer. `test-rules-seams.sh` covers the reviewer in (A)–(D) with a (D-mut) control, header count-free. Seam enumerations + wrapper line; v15.113.0. Plan Review PASS 1/3 (4 advisories carried). Phase 4.5: iteration 1 FAIL (HIGH: (C) exec-sink guard vacuous on the reviewer seam — also on execute-manager.md) → fix 8f0a0ef (invocation fragments never allowlisted, (C-cov), (C-mut)) → iteration 2 PASS. 6 below-floor findings dismissed + posted (marker round=2). rules_check: none · rules_audit: clean · ground truth 2/2 · risk high_risk=true.

## Not verified
- **Live /code-reviewer, /review-pr and drain reviewer spawns executing step 4a** — prompt prose; static seam-test coverage only (subtask 1)
- **test-orca-mirror.sh L on a clean CI checkout** — local failure is the gitignored sdk-spike/node_modules, reproduced on base (subtask 1)
