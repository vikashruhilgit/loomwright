# Supervisor Job: Knowledge-corpus curation (supersession / staleness / retract) + counterfactual-eval scaffold

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — v15.6.0 counts verified against plugin.json)
- **Git:** clean, branch: main (c12819c)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/review-remediation/08-curation-half-and-counterfactual-eval.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash + jq scripts, same stack as every existing corpus reader/writer |
| 2 | Dependency Availability | GO | jq, sha256/shasum already required by the touched scripts; no new deps |
| 3 | Architecture Fit | GO | Extends existing sole-writer/advisory-reader pattern (add-rule.sh / write-lessons.sh precedent) |
| 4 | Scope vs Supervisor | CAUTION | Requirement Part B (≥3 paired /autonomous re-runs) cannot execute inside a PR-producing worker run — scoped to Part A + the pre-registered eval scaffold; paired runs are an explicit post-merge follow-up |
| 5 | Hard Blockers | GO | None — all target files exist and have test suites |

**Overall Verdict:** GO (Part B runtime portion deferred by the requirement's own sequencing: "Part B — after Part A merges")

## Task
**Goal:** Ship the write/curation half of the Twin — supersession, staleness, and human-gated retract for the churn ledger and lessons corpora, corpus-health advisory lines in /insights, and the pre-registered counterfactual-eval scaffold doc.

**Problem Statement:**
The plugin's advisory corpora (churn ledger `.supervisor/postmortem/results.jsonl`, lessons `.supervisor/memory/LESSONS.md`) are append-only; nothing supersedes, decays, or deletes, so advisory signals will eventually be poisoned by stale/wrong entries (north-star Bet 4 "anti-rot"). Currently only lessons have a staleness gate (90-day `LESSON_STALE_DAYS` in read-lessons.sh:33). Success looks like: superseded/retracted entries hidden by readers, stale churn entries dropped fail-open, a human-gated tombstoning verb per corpus, corpus-size advisory in /insights, and a pre-registered eval protocol committed so Part B's paired runs can start immediately after merge.

## Acceptance Criteria
- [ ] AC1: Given a curation record appended to `results.jsonl` with `curation_action: "retract"` (or `"supersede"`) naming a `target_key`, when `read-postmortem.sh` aggregates, then data lines whose `automate_key` OR `pr_url` equals that target are excluded from prior-churn hits.
- [ ] AC2: Given a churn-ledger data line whose `ts` is older than `CHURN_STALE_DAYS` (env, default 180), when `read-postmortem.sh` aggregates, then the line is excluded; a line with missing/unparseable `ts` is treated as FRESH (fail-open) and the reader still always exits 0.
- [ ] AC3: Given a malformed curation record (bad JSON, missing `target_key`, wrong types), when the reader runs, then the record is skipped and the targeted entries remain LIVE (fail-safe: malformed curation ⇒ treat entries as live, never crash).
- [ ] AC4: Given `curate-postmortem.sh retract|supersede --target <key> --reason <text> --confirm`, when run, then exactly ONE jq-built curation JSONL line is appended (append-only — existing lines never rewritten); without `--confirm` it prints the would-append line and exits non-zero (human gate); path/arg validation rejects empty/hostile inputs.
- [ ] AC5: Given `write-lessons.sh retract <category> <text-or-hash>`, when run, then a chain-valid `action:"retract"` provenance entry is appended and the lesson line is removed from LESSONS.md atomically; `read-lessons.sh` treats a chain-valid retract as removing that content_hash from the trusted set (a retracted lesson is never emitted even if the markdown line lingers).
- [ ] AC6: Given `/insights` runs, when corpora exist, then the dashboard contains a `## Corpus health` advisory section with one line per corpus: entries, retracted/superseded count, stale count — advisory only, never gating; absent corpora produce no error.
- [ ] AC7: Given the new/changed writer+reader paths, when the self-tests run (`test-curate-postmortem.sh` NEW, `test-lessons.sh` + `test-insights.sh` extended), then supersession-hidden, stale-annotated/dropped, malformed-fail-safe, retract-tombstone, and missing-key-presence cases all pass on bash 3.2 (macOS) without GNU-only flags.
- [ ] AC8: Given `docs/SPIKES/ADVISORY_LOOP_EVAL.md`, when read, then it pre-registers the metric (review rounds to READY from postmortem `fix_cycles`; Phase 4.5 `heal_iterations`; `rubric_score` where present), the paired-run protocol (3–5 re-runs, scratch-branch only, no PRs to main, in-session /autonomous — no API harness per the OAuth-token constraint), and the explicit keep/cut decision rule — with a status line marking runs as pending post-merge.
- [ ] AC9: Docs current: RESULT_SCHEMAS.md documents the curation-record variant (additive, `schema_version` stays 1); CLAUDE.md/CHANGELOG release notes; plugin.json + marketplace.json bumped to v15.7.0 in place; counts unchanged (14 agents / 21 commands / 41 skills / 22 hooks).

## Outcomes Rubric
- A new `loomwright/scripts/curate-postmortem.sh` exists, builds its JSONL line jq-only, appends only (no rewrite of existing lines), and requires `--confirm` to write.
- `loomwright/scripts/read-postmortem.sh` filters out curation-targeted (retracted/superseded) and stale (`CHURN_STALE_DAYS`, default 180, missing-`ts`-is-fresh) entries inside its jq aggregation, and still ends with `exit 0` on every path.
- `loomwright/scripts/write-lessons.sh` gains a `retract` action that appends an `action:"retract"` provenance-chain entry, and `loomwright/scripts/read-lessons.sh` removes retracted content_hashes from its trusted set.
- A new `loomwright/scripts/test-curate-postmortem.sh` exists and `test-lessons.sh` contains at least one retract-path assertion and one malformed-curation fail-safe assertion.
- `loomwright/scripts/build-insights.sh` emits a `## Corpus health` section and `docs/SPIKES/ADVISORY_LOOP_EVAL.md` exists with a pre-registered metric and an explicit keep/cut decision rule.
- `loomwright/.claude-plugin/plugin.json` version is `15.7.0` and the diff modifies no file under `loomwright/agents/` or `loomwright/commands/` (no new agents/commands; counts stay 14/21/41/22).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Churn-ledger curation: curator writer + reader filtering + tests | AC1–AC4, AC7 | 1 modify, 2 create | quality-checklist, error-handling | LAUNCHABLE |
| 2 | Lessons retract verb: writer action + reader drop + tests | AC5, AC7 | 3 modify | quality-checklist, error-handling | LAUNCHABLE |
| 3 | /insights corpus-health section + tests | AC6, AC7 | 2 modify | quality-checklist | LAUNCHABLE |
| 4 | Docs, eval scaffold, version bump v15.7.0 | AC8, AC9 | 5 modify, 1 create | quality-checklist | BLOCKED (by #1, #2, #3) |

```yaml
# Subtask 1 — Churn-ledger curation (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/curate-postmortem.sh"}
  - {kind: "file", path: "loomwright/scripts/test-curate-postmortem.sh"}
  - {kind: "symbol", path: "loomwright/scripts/read-postmortem.sh", name: "CHURN_STALE_DAYS"}
requires: []
external_requires:
  - "jq >= 1.6 (already a plugin runtime dependency)"

# Subtask 2 — Lessons retract (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/scripts/write-lessons.sh", name: "retract"}
  - {kind: "symbol", path: "loomwright/scripts/read-lessons.sh", name: "retract"}
requires: []
external_requires:
  - "sha256sum or shasum (already required by lessons scripts)"

# Subtask 3 — Insights corpus health (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/scripts/build-insights.sh", name: "Corpus health"}
requires: []
external_requires: []

# Subtask 4 — Docs + eval scaffold + version (BLOCKED by #1,#2,#3)
provides:
  - {kind: "file", path: "loomwright/docs/SPIKES/ADVISORY_LOOP_EVAL.md"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "curation"}
  - {kind: "symbol", path: "loomwright/.claude-plugin/plugin.json", name: "15.7.0"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/curate-postmortem.sh"}
  - {from: "2", kind: "symbol", path: "loomwright/scripts/write-lessons.sh", name: "retract"}
  - {from: "3", kind: "symbol", path: "loomwright/scripts/build-insights.sh", name: "Corpus health"}
external_requires: []
```

### Design decisions (per-corpus mechanism choices — explicit, per the requirement)
- **Curation records live IN the ledger** (`.supervisor/postmortem/results.jsonl`) with `source: "curation"` + `curation_action: "retract"|"supersede"` + `target_key` (matched against a data line's `automate_key` OR `pr_url`, exact string) + optional `replacement` (pr_url of the superseding entry) + `reason` + `ts`. Additive — `schema_version` stays 1; old readers fail-safe-skip unknown fields; no second file.
- **Reader serves head-of-chain:** any data line named by a chain of curation records is hidden; the curation records themselves never count as churn hits (already excluded today: they carry no `changed_paths`, but exclude explicitly on `source == "curation"` for clarity).
- **Staleness:** churn `CHURN_STALE_DAYS` default 180 (env-overridable); lessons keep the existing 90-day `LESSON_STALE_DAYS` — align, don't duplicate. Missing/unparseable timestamps ⇒ FRESH (fail-open advisory lint; provenance/validity gates remain the security boundary).
- **Unlearning is never silent:** churn retract requires `--confirm` (dry-run default); lessons retract goes through the provenance chain (auditable tombstone). No in-place deletion of ledger lines, ever.
- **Rules / project-memory / System-Contract corpora: OUT of this slice** (requirement: "pick minimal viable subset — churn ledger + lessons recommended first"). Rules already have human-gated add + fail-safe-skip; extendable later on the same pattern.
- **Nullable-required discipline (PR #84 lesson):** curation-record validation asserts key PRESENCE via jq `has()` for nullable-but-required fields; tests cover both missing-key and explicit-null.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──┐
Subtask 2 ──┼──→ Subtask 4
Subtask 3 ──┘
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 1 | Subtask 3 | none | NO |
| Subtask 2 | Subtask 3 | none | NO |
| Subtask 1/2/3 | Subtask 4 | docs reference the shipped contracts | YES (dependency) |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2, Subtask 3 (parallel)
- **Batch 2:** Subtask 4 (after all)
- **Recommended workers:** 2
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/error-handling/SKILL.md` |
| 2 | `skills/quality-checklist/SKILL.md`, `skills/error-handling/SKILL.md` |
| 3 | `skills/quality-checklist/SKILL.md` |
| 4 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| macOS bash 3.2 / GNU-vs-BSD drift (`stat`, `date -d`) in new test/reader code | HIGH | Reuse read-lessons.sh's `iso_to_epoch` dual-path pattern; validate numeric before arithmetic (stat-flavor lesson); tests must avoid GNU-only flags |
| Reader regression breaks a live advisory seam (Phase 4.5 `prior_churn`, Launch Pad 0b) | HIGH | Preserve the EMPTY⇒silent contract and always-exit-0; extend the existing test suites rather than replacing; no output-format change to existing hit lines |
| Curation matching misses old lines lacking `automate_key`/`pr_url` | MEDIUM | Documented limitation: pre-v14.22 lines without either key cannot be targeted; staleness TTL retires them anyway |
| write-lessons.sh atomic rewrite races a concurrent writer | LOW | Same temp+rename discipline the writer already uses; single-run-per-repo operating assumption |
| Part B misread as shipped | MEDIUM | ADVISORY_LOOP_EVAL.md carries an explicit `Status: pre-registered — paired runs pending (post-merge)` line; CHANGELOG says "scaffold" |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-07-07-curation-corpora-and-eval-scaffold.md
```

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/98
- **Branch:** feature/corpus-curation (head 1f3857b)
- **heal_loop_ran:** true | **heal_decision:** PASS | **heal_iterations:** 1 | **heal_remaining_issues:** 0
- **rubric_score:** 6/6
- **ground_truth:** pass (2/2 — doc-currency-green, version-consistent)
- **Until-mergeable dispatched:** false (suppressed — /automate owns the drain)
- **Note:** requirement Part B (paired eval runs) pre-registered in docs/SPIKES/ADVISORY_LOOP_EVAL.md, pending post-merge
