# Supervisor Job: Route the restated-list house rule to the surfaces where the drift actually lands

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-10-194230/L2 (lane L2 clone of `vikashruhilgit/loomwright`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main @ `4e0f255` (= origin/main)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/churn-ledger/01-restated-lists-diverge-from-authority.md

> **Warning (1):** this checkout is lane L2 of a `--parallel 3` `/automate` wave. Other lanes run in sibling clones. Stay inside this clone; the PR carries a `changelog.d/` fragment and NO version bump (lanes never bump).

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | A JSON rule object written by the repo's own `loomwright/scripts/add-rule.sh` plus a markdown fragment. No code. |
| 2 | Dependency Availability | GO | `jq`, `bash` present; `add-rule.sh`, `read-rules.sh`, `audit-rules.sh` exist on disk. |
| 3 | Architecture Fit | GO | Uses the documented curation actions (`add-rule.sh --retract` then add, `loomwright/skills/rules/SKILL.md` §7/§7.5). `add-rule.sh` stays the sole writer of `.agent/rules/`. |
| 4 | Scope vs Supervisor Capability | GO | One rule replacement + one fragment — single subtask, below the Decomposition Threshold. |
| 5 | Hard Blockers | GO | None. |

**Overall Verdict:** GO

## Task
**Goal:** Make the existing advisory house rule against silently drifting restated lists reach the files where that drift has actually been found, and record the named cause of the `convention_mismatch`/`self_heal` ledger pattern.

**Problem Statement:**
The postmortem ledger holds 62 entries classed `convention_mismatch` at flow stage `self_heal`. Read at their source lines (`.supervisor/postmortem/results.jsonl`), they share ONE cause: a surface restates a list, count, version, table, cross-reference or line number owned by another surface, and the copy is not moved in the same change as its authority (examples: "3 restated copies diverged from authoritative taxonomy", "ARCHITECTURE_CONTRACTS timeout-table drift", "SKILLS_INDEX row 1.2.1 vs SKILL.md 1.3.0", "stale 19 count inside the 20-hooks table").

Counts/versions and line-number citations already have mechanisms (`check-doc-currency.sh`, the count/version rule in `.agent/rules/process.json`, `test-citation-drift.sh` pins, `check-skills-index-sync.sh`). The restated LIST/TABLE/ENUMERATION class has only an advisory rule — `process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-…` — and that rule's `applies_to` is `["CLAUDE.md", "loomwright/scripts/*"]`. Verified in the running reader on 2026-10-10: `read-rules.sh loomwright/docs/ARCHITECTURE_CONTRACTS.md` emits it 0 times; `read-rules.sh CLAUDE.md` emits it once. So Phase 4.5's house-rules advisory (`skills/self-heal-advisory/SKILL.md`, which calls `read-rules.sh <touched files>`) never shows the rule on a PR that touches `loomwright/docs/`, `agents/`, `commands/`, `skills/`, `README.md` or `CHANGELOG.md` — the surfaces where the cited drift landed.

Success looks like: the rule is shown on every markdown surface and every script under `loomwright/scripts/` and root `scripts/`, exactly one copy of it exists (the narrowly-routed object is retracted and re-added with the wider routing, both through `add-rule.sh`), and the cause plus the change are written where a future session reads them.

## Acceptance Criteria
- [ ] AC-1: Given the change, when `.agent/rules/process.json` is read, then the restated-list rule exists exactly once, with the SAME `statement` text and id as before, `category: process`, `enforcement: advisory`, `check: null`, `applies_to` exactly `["*.md", "loomwright/scripts/*", "scripts/*"]`, NO `supersedes` member, and a `provenance.source` naming `.supervisor/requirements/churn-ledger/01-restated-lists-diverge-from-authority.md` and the original source `dreaming:auto-2026-08-20-013613`. It is produced by TWO `add-rule.sh` calls — `--retract --target <old id> --reason … --confirm`, then the add — never a hand edit; both printed lines are recorded verbatim in `WORKER_RESULT` and the PR body. (A verbatim re-add WITHOUT the retract is refused by `validate-entry.sh`'s duplicate check, score ≈95% ≥ 90, before the confirm gate.)
- [ ] AC-2: Given the change, when the count/version rule object (index 0) is compared byte-for-byte against `origin/main`, then it is unchanged, and `.agent/rules/documentation.json` is unchanged.
- [ ] AC-3: Given `bash loomwright/scripts/read-rules.sh --with-ids loomwright/docs/ARCHITECTURE_CONTRACTS.md`, when run, then the restated-list rule's id is emitted exactly once; the same holds for `loomwright/agents/supervisor.md`, `loomwright/skills/SKILLS_INDEX.md`, `CHANGELOG.md`, `loomwright/scripts/read-rules.sh` and `scripts/check-doc-currency.sh` (root `scripts/` — the doc-currency authority and `bump-version.sh` live there, and `.agent/companions.json` restates `check-doc-currency.sh`'s `FILES` array) — each recorded verbatim (command + the id lines) in `WORKER_RESULT` and the PR body.
- [ ] AC-4: Given `bash loomwright/scripts/read-rules.sh --with-ids CLAUDE.md`, when run, then the restated-list rule is emitted exactly once.
- [ ] AC-5: Given `bash loomwright/scripts/read-rules.sh --with-ids stackpack/.claude-plugin/plugin.json` (a non-markdown, non-script path), when run, then the restated-list rule is NOT emitted — proving the routing is a real filter, not a repo-wide fall-open. Recorded verbatim.
- [ ] AC-6: Given `bash loomwright/scripts/audit-rules.sh` (read-only), when run, then it exits 0 (no findings — in particular no `dead_rule`) and its output is recorded verbatim in `WORKER_RESULT` and the PR body.
- [ ] AC-7: Given the change, when `changelog.d/churn-ledger-01-restated-lists-diverge-from-authority.md` is read, then it is a valid fragment (`changelog.d/README.md` format, `<!-- bump: patch -->`) whose body names the cause (restated copies not moved with their authority), the routing defect it fixes, and the measurement limit below; and `CHANGELOG.md`, `loomwright/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` are untouched.
- [ ] AC-8: Given the whole change, when `bash scripts/ci-local.sh` runs, then it exits 0 (covers `check-doc-currency.sh`, `test-citation-drift.sh`, the rules test suites).
- [ ] AC-9: Given the PR body, when read, then it states (a) the pattern is ONE cause, (b) which sub-classes were already mechanized before this change and by what, (c) the measurement limit: since 2026-09 the ledger's lines are almost all `source: automate_drain`, which carry classes `drain_churn`/`self_heal_churn` and no finding text, so the ledger can no longer observe `convention_mismatch` at all — the drop from 45 entries (2026-06) to 2 (2026-09) and 0 (2026-10) is NOT evidence the pattern stopped, and (d) the stale sentence in `.agent/rules/README.md` §"This repo ships the README/schema, NOT live rules" ("there are **no populated live `*.json` rules** in `.agent/rules/` here" — quoted verbatim with its path in the PR body) as a found instance of this class, left for a follow-up because that file is outside this item's declared `## Touches`.

## Outcomes Rubric

- The restated-list rule is now emitted for markdown doc surfaces and scripts, verified by running `read-rules.sh` on concrete paths, not asserted.
- The rule exists exactly once with the wider routing, produced by `add-rule.sh` retract + add (no hand edit), and `audit-rules.sh` stays clean.
- A non-matching path proves the new routing still filters.
- The named cause and the ledger's measurement blind spot are written in the changelog fragment and the PR body.
- No version file and no `CHANGELOG.md` is edited; one fragment is added.
- `bash scripts/ci-local.sh` is green.

## Executable Acceptance
- corpus-task: doc-currency-green

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Supersede the restated-list rule with doc-wide routing + changelog fragment | ALL (AC-1 … AC-9) | 1 modify, 1 create | `rules`, `quality-checklist` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1 — the whole change (LAUNCHABLE; no siblings)
provides:
  - {kind: "file",   path: "changelog.d/churn-ledger-01-restated-lists-diverge-from-authority.md"}
  - {kind: "symbol", path: ".agent/rules/process.json", name: "scripts/*"}
requires: []
lanes:
  - ".agent/rules/process.json"
  - "changelog.d/churn-ledger-01-restated-lists-diverge-from-authority.md"
external_requires: []
```

**Exact-name mandate:** the fragment filename is literal; the rule's id stays the base id (no suffix). Invocation — proven by Launch Pad in a scratch copy of this repo on 2026-10-10 (retract printed `retracted rule id=…`, add printed `wrote rule id=…`, `read-rules.sh` emitted the rule once for `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, `CLAUDE.md`, `scripts/check-doc-currency.sh` and 0 times for `stackpack/.claude-plugin/plugin.json`, `audit-rules.sh` exit 0):

```bash
OLD=$(jq -r '.[1].id' .agent/rules/process.json); ST=$(jq -r '.[1].statement' .agent/rules/process.json)
bash loomwright/scripts/add-rule.sh --retract --target "$OLD" --reason "superseded: re-routed applies_to (churn-ledger/01)" --confirm
bash loomwright/scripts/add-rule.sh --category process --statement "$ST" --enforcement advisory \
  --applies-to '*.md' --applies-to 'loomwright/scripts/*' --applies-to 'scripts/*' \
  --source ".supervisor/requirements/churn-ledger/01-restated-lists-diverge-from-authority.md (convention_mismatch/self_heal@L3.1,L3.4,L3.6,L4.3,L4.5; was dreaming:auto-2026-08-20-013613)" \
  --confirm
```

Check `.[1]` IS the restated-list rule before running (match on `restates a list` in its statement).

## Parallelism Analysis

### Dependency Graph
Single subtask — no graph.

### File Overlap Matrix
Not applicable (one subtask).

### Batch Plan
One batch, one worker.

## Skill References

| Skill | Why |
|---|---|
| `skills/rules/SKILL.md` | The rule schema, `applies_to` case-glob semantics (`*` crosses `/`), `--retract` + add, `add-rule.sh` as sole writer, `audit-rules.sh` findings |
| `skills/quality-checklist/SKILL.md` | Pre/post-implementation gates |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Hand-editing `process.json` (changing the rule's `applies_to` in place) | MEDIUM | AC-1: `add-rule.sh` is the sole writer (`skills/rules/SKILL.md` §9.1); retract + add are its two sanctioned actions. |
| Re-add refused as a duplicate | HIGH | The retract MUST run first; `validate-entry.sh` refuses a ≥90% overlap with a stored statement. Proven order above. Using `--supersedes` instead would be refused for the same reason and would leave a permanent `dead_rule` audit finding. |
| Retract drops the original provenance | LOW | The new `--source` carries the original `dreaming:auto-2026-08-20-013613` token; git history keeps the old object. |
| `*.md` read as a gitignore glob that stops at `/` | MEDIUM | `applies_to` is a bash `case` glob — `*` crosses `/` (`.agent/rules/README.md` §"Pattern syntax"). AC-3 verifies on nested paths in the running reader. |
| Rule shows twice | LOW | One object only after retract + add; AC-4 asserts single emission. |
| Wider routing adds prompt noise to unrelated PRs | LOW | Advisory, one short statement; AC-5 shows non-markdown non-script paths stay excluded. |
| The fix is judged effective from the ledger trend | MEDIUM | The ledger cannot observe the class since automate_drain lines replaced pr_postmortem lines (AC-9c). The PR claims only the routing fix, not an effect. |
| A version bump inside a lane | MEDIUM | Lanes carry a fragment and no bump (`changelog.d/README.md`, AC-7). |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main
- **Branch:** feature/churn-ledger-01-restated-list-rule-routing

## Handoff
```
/supervisor job: .supervisor/jobs/pending/auto-2026-10-10-141638-restated-list-rule-routing.md
```

## Plan Review Notes (owner-approved at Phase 6 — pass to the worker)
Plan Review PASSed on attempt 2. The owner chose "Save + pass notes"; these do not change the plan, they sharpen it:
1. (MEDIUM) The contract's `provides` symbol `scripts/*` already appears in `process.json` today (inside `loomwright/scripts/*`), so the outputs gate cannot tell before from after. Verify the new routing by the `*.md` element — which appears nowhere in `process.json` before the change — and record that check in `WORKER_RESULT`.
2. (LOW) The subtask title says "Supersede"; the approach is `add-rule.sh --retract` then a plain re-add. Do NOT use `--supersedes`.
3. (LOW) The requirement file's `## Status: done` stamp (which retires the evidence set) is written by the `/automate` close-out after the PR merges — not by this PR. Do not edit `.supervisor/requirements/`.

## Outcome
- **Status:** completed
- **Completed:** 2026-10-10T14:49:32Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/460
- **Branch:** feature/churn-ledger-01-restated-list-rule-routing
- **Files changed:** 2
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Retracted and re-added the restated-list house rule through add-rule.sh (same id/statement) with applies_to *.md, loomwright/scripts/*, scripts/*; changelog fragment added. Phase 4.5 PASS on the first review (1 MEDIUM evidence-format finding addressed in the PR body, 2 LOW dismissed); rubric 6/6; ground truth doc-currency-green pass; ci-local PASS. classify-risk reads high_risk only because "authority" matches *auth* (advisory; red-team lens not enabled).
