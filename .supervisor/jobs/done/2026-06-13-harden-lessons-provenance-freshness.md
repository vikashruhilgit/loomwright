# Supervisor Job: Harden LESSONS path — freshness tracking + provenance parity

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — modified today, 2026-06-13)
- **Git:** clean (only untracked `.claude/`), branch: main @ b3e4dd2
- **Worktrees:** none orphaned
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0

## Task
**Goal:** Bring the advisory **LESSONS** memory path up to the same safety standard as PROJECT_MEMORY, in two tiers, by extending the existing sole-writer scripts — never introducing a parallel note format or importing any external stack.

- **Tier A (freshness):** add `last_verified` + `confidence` metadata to each lesson, and add a **stale-lesson lint** on the read/consumption path so agents and `/dreaming` can detect/skip lessons past a freshness threshold.
- **Tier B (provenance parity):** give `write-lessons.sh` hash-chained provenance on write (content_hash + prev_hash chain, fail-safe no-op when no sha256 tool), and add a **chain-valid read-side gate** that emits only chain-valid `add`-backed lessons (distrust everything after a prev_hash mismatch; log drops to `.supervisor/logs/memory.log`).

**Why now:** `write-project-memory.sh` already has hash-chain provenance and `read-project-memory.sh` already enforces it read-side; `write-lessons.sh` deliberately does **not** (see its header lines 16–20, which call parity "a possible P5 hardening"). This is the unanimous top pick from four independent review passes. ADVISORY only — subordinate to human-authored CLAUDE.md; never an enforcement boundary.

## Acceptance Criteria
- [ ] Given a lesson written via `write-lessons.sh`, when it is stored, then its entry carries a machine-readable `last_verified` timestamp and a `confidence` value, and the per-category ≤3 bound + oldest-eviction + atomic temp-in-dir+mv + worktree-refusal invariant all still hold.
- [ ] Given lessons older than the freshness threshold, when the read path is invoked, then stale lessons are flagged/skipped (lint) while fresh ones pass through.
- [ ] Given a lesson written via `write-lessons.sh`, when it is stored, then a hash-chained provenance entry is appended to a **lessons-specific** chain file (NOT shared with PROJECT_MEMORY's `.provenance.jsonl`), with `prev_hash` chaining and a GENESIS root, and eviction emits an `evict` provenance entry.
- [ ] Given a tampered or out-of-band-appended LESSONS line, when the read gate runs, then that line and everything after the broken chain point is dropped and logged to `.supervisor/logs/memory.log`; verified lessons are emitted with the advisory banner.
- [ ] Given no sha256 tool is available, when either writer or reader runs, then it is a fail-safe no-op (write disabled / read emits nothing) and exit code is 0 — matching the project-memory scripts.
- [ ] Given the change lands, when CI runs the `test-*.sh` hard-gate loop, then `test-lessons.sh` (updated for the new format) and a new `test-read-lessons.sh` both pass.

## Feasibility (Phase 2.5)
**Verdict: GO.** Tech stack (bash + awk + sha256 + optional jq) is exactly what the existing memory scripts use; no new dependencies; the design mirrors the already-shipped `write-project-memory.sh`/`read-project-memory.sh` pair one-to-one. Four CAUTION findings carried into Risk Assessment.

## File Impact Map

| File | Action | Confidence | Notes |
|------|--------|-----------|-------|
| `ai-agent-manager-plugin/scripts/write-lessons.sh` | modify | HIGH | Add freshness metadata (Tier A) + hash-chain provenance write (Tier B). Already computes `content_hash`/`id` at lines 82–83 — extend, don't reinvent. Update header lines 16–20 (the "no provenance in v1 / P5" note). |
| `ai-agent-manager-plugin/scripts/read-lessons.sh` | **create** | HIGH | New sole reader / read-side gate — mirror `read-project-memory.sh` (chain-walk → trusted content_hashes → emit verified only) + add stale-lint threshold. No reader exists today. |
| `ai-agent-manager-plugin/scripts/test-lessons.sh` | modify | HIGH | Pins the `- [id] text` line format + `## <cat>` counts (lines 39–80) — must accept the new metadata-carrying format and assert provenance is written. |
| `ai-agent-manager-plugin/scripts/test-read-lessons.sh` | **create** | HIGH | New self-test for the read gate + stale-lint; auto-picked by ci.yml's `test-*.sh` glob (no ci.yml edit needed). |
| `ai-agent-manager-plugin/scripts/build-vault.sh` | modify | MEDIUM | `cat`s `LESSONS.md` raw at line 369 (no gate). Decide: route through `read-lessons.sh` (chain-valid Obsidian projection) OR document the deliberate raw projection. Plan Review to confirm direction. |
| `ai-agent-manager-plugin/commands/dreaming.md` | modify | MEDIUM | Line 82 invokes `write-lessons.sh --category --lesson --source` — update if the writer signature gains a `--confidence`/`--last-verified` flag. |
| `ai-agent-manager-plugin/scripts/write-lessons.sh` header + `docs/SPIKES/P2b_MEMORY_DESIGN.md` + `AGENT_GUIDELINES.md` | modify | MEDIUM | Document the now-shipped provenance parity (was "deferred to P5"). |

**New state artifact:** `.supervisor/memory/.lessons-provenance.jsonl` (gitignored like `.provenance.jsonl`; separate chain from PROJECT_MEMORY).

## Subtask Structure

| # | Title | Est. Files | Status | Contract |
|---|-------|-----------|--------|----------|
| 1 | Tier A — freshness metadata in `write-lessons.sh` | 1 mod (write-lessons.sh) + 1 mod (test-lessons.sh) | LAUNCHABLE | provides: `lesson_entry_format_v2` (last_verified+confidence); requires: — |
| 2 | Tier B — hash-chain provenance write-side in `write-lessons.sh` | 1 mod (write-lessons.sh) + 1 mod (test-lessons.sh) | BLOCKED (by #1 — same file) | provides: `lessons_provenance_chain` (.lessons-provenance.jsonl schema, evict entries); requires: `lesson_entry_format_v2` |
| 3 | Read gate + stale-lint — new `read-lessons.sh` | 1 create (read-lessons.sh) + 1 create (test-read-lessons.sh) | BLOCKED (by #2 — needs chain schema) | provides: `read_lessons_gate` (chain-valid emit + stale threshold); requires: `lessons_provenance_chain`, `lesson_entry_format_v2` |
| 4 | Consumer + docs wiring | build-vault.sh, dreaming.md, write-lessons.sh header, P2b/AGENT_GUIDELINES docs | BLOCKED (by #3) | provides: `consumers_wired`; requires: `read_lessons_gate` |

## Parallelism Analysis
- **Batches:** [#1] → [#2] → [#3] → [#4] — fully sequential.
- **Recommended workers: 1.** This is inherently serial single-file hardening: subtasks 1 & 2 both edit `write-lessons.sh` (hard file overlap → must serialize), and 3 & 4 depend on the chain schema defined upstream. No genuine parallelism exists; marking any subtask LAUNCHABLE-in-parallel would be dishonest.

## Risk Assessment

| Risk | Severity | Source | Mitigation |
|------|----------|--------|------------|
| Reusing PROJECT_MEMORY's `.provenance.jsonl` would interleave two chains and break both walks | HIGH | Feasibility (Phase 2.5) | Lessons MUST use a separate `.lessons-provenance.jsonl`. Pinned in acceptance criteria + subtask #2 contract. |
| Lesson entry format change silently breaks `test-lessons.sh` grep/awk pins (lines 39–80) | MEDIUM | Feasibility (Phase 2.5) | Update `test-lessons.sh` in the SAME subtask (#1) that changes the format; CI `test-*.sh` hard gate catches regressions. |
| `build-vault.sh` raw-`cat`s LESSONS.md → Obsidian projection could surface unverified/stale lessons | MEDIUM | Feasibility (Phase 2.5) | Subtask #4 decides: route through `read-lessons.sh` or document deliberate raw projection. Resolve at Plan Review. |
| `write-lessons.sh` signature change ripples to `/dreaming` invocation (dreaming.md:82) | MEDIUM | Feasibility (Phase 2.5) | Keep new flags optional with safe defaults; update dreaming.md in subtask #4. |
| Scope creep into the hook↔agent contract-parity guard | LOW | Analysis | OUT OF SCOPE — this change touches no hook result-block fields or closed enum literals; `check-contract-parity.sh` is not triggered. |

## Configuration
- **Heal iterations:** default (3)
- **Cost profile:** default (inherit)
- **Branch base:** main @ b3e4dd2
- This is a plugin-self change → expect the Code Reviewer consistency-audit auto-expand (touches `scripts/`, `commands/`, `docs/`).

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-06-13-harden-lessons-provenance-freshness.md
```

## Outcome
- **Status:** completed
- **Branch:** feature/harden-lessons-provenance-freshness
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/55
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 1 (review FAIL → fix HIGH trailer-collision + MEDIUM test + LOW sanitizer → re-review PASS)
- **heal_remaining_issues:** 0 blocking (1 residual LOW/pre-existing pathological edge, out of realistic scope)
- **Tests:** full CI test-*.sh hard gate green (test-lessons 19/19, test-read-lessons 18/18, loop exit 0); doc-currency ✓, validate-version ✓
- **Completed:** 2026-06-14
