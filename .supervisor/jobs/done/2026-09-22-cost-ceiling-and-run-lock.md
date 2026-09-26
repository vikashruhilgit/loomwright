# Supervisor Job: Token ceiling for /automate + /autonomous, and a single-run-per-repo lock

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 tracked-file changes; 3 untracked automate/job-tracking files, not source), branch: worktree-automate-hardening-2026-09-22 (== origin/main @ ed2dbcd)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/red-team-hardening/06-cost-ceiling-and-run-lock.md

## Feasibility (optional — Launch Pad v10.3+)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash + jq, matching every existing `loomwright/scripts/*.sh` helper (`automate-helpers.sh`, `dispatch-pr-review.sh`) — no new runtime dependency. |
| 2 | Dependency Availability | GO | `jq` already required repo-wide; no new library. `read-token-ledger.sh` reads plain JSONL with `jq`; `run-lock.sh` reuses `mkdir`-atomicity + `kill -0` liveness, the exact primitive `dispatch-pr-review.sh`'s `acquire_lock` already uses. |
| 3 | Architecture Fit | GO | Follows the existing `automate-helpers.sh` subcommand-dispatch pattern (§1.5) and the existing fail-safe/fail-closed bimodal philosophy in CLAUDE.md §"Failure-Mode Invariants": the ledger-breach gate is a correctness gate (fail CLOSED), the lock is a correctness gate (fail CLOSED — refuses to proceed while held), matching the invariant precisely. |
| 4 | Scope vs Supervisor Capability | CAUTION | Touches ~19 files across 2 new scripts + 2 new tests + ~15 doc/integration-seam edits (automate-helpers.sh, session-resume.sh, close-stranded-run.sh, 3 command files, 2 loop skills, supervisor-config skill, agents/supervisor.md, 2 docs, CHANGELOG, plugin.json + marketplace.json). Exceeds the `context-bound` numeric guideline (>12 files) in `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold", but the two capabilities (ledger reader, run lock) share the SAME doc files (CHANGELOG, plugin.json, both loop skills) and the SAME integration seam file (`automate-helpers.sh`'s PICK step needs both the lock acquire AND the ceiling check in one place) — a file-conflict split would force near-total serialization for no real parallelism benefit. Kept as a single subtask, consistent with items 01–05 in this same automate run (comparable or larger multi-file scope, all completed Single-Agent Path). Recorded as a Risk Assessment row below (generous worker turn budget recommended). |
| 5 | Hard Blockers | GO | No migration framework, no new credentials, no missing modules. All cited line numbers in the requirement's "Verified premises" were independently re-verified (see Risk Assessment for the two corrections found). |

**Overall Verdict:** CAUTION (user override not required — CAUTION proceeds silently per Phase 2.5 flow, feeds Risk Assessment)

## Task
**Goal:** Give `/automate` and `/autonomous` an opt-in token-spend ceiling that fails CLOSED (parks, never silently continues), and stop two `/automate`/`/autonomous`/`/supervisor` runs from sharing one checkout at the same time.

**Problem Statement:**
Operators running `/automate`/`/autonomous` unattended need a spend ceiling because there is currently NONE anywhere in the plugin — a 0-hit grep for `max_cost|spend cap|cost ceiling|token ceiling` across `loomwright/` (re-verified during planning, still 0 hits) confirms the gap. The only recorded spend signal is `emit-token-ledger.sh`'s `token_ledger` JSONL events, which are written but never read back as a limit. This already caused a real incident (2026-09-15, the Claude subscription weekly cap tripped by a single `/automate` item's Launch Pad + Supervisor + N workers + reviewers + rubric + up to 5 drain rounds, each round re-triggering CI review). Separately, `automate-loop/SKILL.md:376` documents "single-run-per-repo is an assumed constraint, not enforced" — two runs in one checkout would race `git checkout`, the `.auto_review` toggle, and `state.md` (a documented concurrency hazard). Currently an operator has no way to bound spend or prevent a second concurrent run; success looks like an opt-in `--max-tokens` flag that PARKs (never silently overspends) and a `run-lock.sh` that makes concurrent-run collision structurally impossible (not just documented as "assumed").

## Acceptance Criteria
- [ ] Given a session JSONL under `.supervisor/logs/` containing 3 well-formed `token_ledger` events (with `input_tokens`/`output_tokens`/`cache_read_input_tokens`/`cache_creation_input_tokens`), when `scripts/read-token-ledger.sh --session <id>` runs, then it prints `INPUT=<n> OUTPUT=<n> CACHE_READ=<n> CACHE_CREATE=<n> TOTAL=<n> EVENTS=<n>` summed correctly over exactly those events.
- [ ] Given a `token_ledger` event that carries `proxy: true` (no real usage fields — `emit-token-ledger.sh`'s transcript-bytes fallback path), when `read-token-ledger.sh` sums a session containing it, then the proxy-only line contributes 0 to the real-usage sums (never crashes, never silently inflates `TOTAL`) — this honest limit is stated in the script's own header comment and in the docs.
- [ ] Given `--run-id <automate run id>` instead of `--session <id>`, when `read-token-ledger.sh` runs, then it resolves the set of session ids from that run file's `## Progress` lines (adding session-id recording to `## Progress` if not already present) and sums across all of them.
- [ ] Given a missing or unreadable session JSONL, when `read-token-ledger.sh` runs, then it prints all-zero sums plus `LEDGER_UNREADABLE=1` and exits 0 (fail-safe reader, never a hard error).
- [ ] Given `/automate --max-tokens 1000` resuming a run whose ledger already sums past 1000, when the loop reaches PICK for the next item, then it parks BEFORE picking with `## Status: paused`, `pause_reason: token_ceiling` — never silently continuing over the ceiling.
- [ ] Given `--max-tokens` is NOT passed to `/automate` or `/autonomous`, when the run executes, then behavior is byte-for-byte unchanged from today (opt-in, no ceiling checked, no `## Config`/`state.json` field written).
- [ ] Given `run-lock.sh acquire --owner <label>` succeeds in a checkout with no existing `.supervisor/run.lock`, when a second `run-lock.sh acquire --owner <label2>` runs in the SAME checkout before release, then the second call prints a `run_lock_held owner=<label> pid=<pid> age=<s>` line and exits non-zero — it never silently proceeds.
- [ ] Given a `.supervisor/run.lock` whose recorded `pid` is dead AND `age >= 1800s`, when `run-lock.sh acquire` runs, then it reclaims the lock (same TTL-reclaim shape as `dispatch-pr-review.sh`'s `acquire_lock`) and succeeds; given the pid is dead but `age < 1800s`, it refuses (does not reclaim early).
- [ ] Given `automate-loop/SKILL.md`, when grepped for the literal string `assumed constraint, not enforced`, then it returns 0 hits (the line is rewritten to describe the now-enforced lock).
- [ ] Given the full existing test suite (`loomwright/scripts/test-*.sh` + root `scripts/test-*.sh` + `scripts/check-vendor-coupling.sh`) plus the two new suites `test-read-token-ledger.sh` and `test-run-lock.sh`, when run, then all suites are green with zero regressions.
- [ ] Given a mutation that makes the ledger reader always return 0 real tokens, when the breach-parks seam fixture (token-ceiling-at-PICK test) runs against that mutant, then the fixture FAILs (proving the ceiling check is load-bearing, not vacuous).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Token ceiling + run lock (ledger reader, `--max-tokens` at 3 entry points, `run-lock.sh`, docs, tests) | all | 15 modify, 4 create | `skills/automate-loop/SKILL.md`, `skills/autonomous-loop/SKILL.md`, `skills/supervisor-config/SKILL.md`, `skills/state-management/SKILL.md`, `skills/async-orchestration/SKILL.md` | LAUNCHABLE |

```yaml
# Subtask 1 — Token ceiling + run lock (LAUNCHABLE, sole subtask)
provides:
  - {kind: "file", path: "loomwright/scripts/read-token-ledger.sh"}
  - {kind: "file", path: "loomwright/scripts/run-lock.sh"}
  - {kind: "file", path: "loomwright/scripts/test-read-token-ledger.sh"}
  - {kind: "file", path: "loomwright/scripts/test-run-lock.sh"}
  - {kind: "symbol", path: "loomwright/scripts/run-lock.sh", name: "acquire"}
  - {kind: "symbol", path: "loomwright/scripts/run-lock.sh", name: "release"}
  - {kind: "symbol", path: "loomwright/scripts/run-lock.sh", name: "status"}
requires: []
lanes:
  - "loomwright/scripts/read-token-ledger.sh"
  - "loomwright/scripts/run-lock.sh"
  - "loomwright/scripts/test-read-token-ledger.sh"
  - "loomwright/scripts/test-run-lock.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/session-resume.sh"
  - "loomwright/scripts/close-stranded-run.sh"
  - "loomwright/commands/automate.md"
  - "loomwright/commands/autonomous.md"
  - "loomwright/commands/supervisor.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/skills/autonomous-loop/SKILL.md"
  - "loomwright/skills/supervisor-config/SKILL.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/PITFALLS.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

### File Impact Map (detail behind the contract above)

**Create:**
- `loomwright/scripts/read-token-ledger.sh` — `--session <id> | --run-id <automate run id>`; sums `token_ledger` JSONL events; fail-safe (`LEDGER_UNREADABLE=1` on unreadable/missing); proxy-only lines contribute 0 to real sums (documented honest limit — see `emit-token-ledger.sh:342-361` for the `proxy`/`token_proxy_kind` shape). `--run-id` resolution needs session ids recorded in the run file's `## Progress` (add if not already present — grep the existing lines first; several already embed session context, verify before assuming absence).
- `loomwright/scripts/run-lock.sh` — `acquire|release|status --owner <label>` on `.supervisor/run.lock` (a directory, `meta` TSV file). Reuse — do not reimplement from scratch — the exact `mkdir`-atomicity + TSV-meta + pid-liveness + 1800s-TTL-reclaim shape at `loomwright/scripts/dispatch-pr-review.sh:550-599` (`write_lock_meta` + `acquire_lock`); factor out a shared helper if reuse is clean, otherwise mirror the shape closely and note why in a comment. The existing `meta` TSV has NO `session_id`/`owner` fields — add both.
- `loomwright/scripts/test-read-token-ledger.sh`, `loomwright/scripts/test-run-lock.sh` — follow the established harness pattern in `loomwright/scripts/test-automate-helpers.sh` / `test-dispatch-pr-review.sh`: `set -uo pipefail`, `pass=0; fail=0`, `ok()`/`no()` helpers, SUT invoked as a subprocess (never sourced) against a `mktemp -d` sandbox with stubbed `gh`/`git`/`claude` on `PATH`, tail `echo "RESULT: $pass passed, $fail failed"; [ "$fail" -eq 0 ] || exit 1`. Include a mutation-control block (sed a guard line out of a copied SUT, `bash -n` sanity check, assert the guarded behavior now fails) per AC "mutation control" and CLAUDE.md's "a guard written to catch this class is itself often vacuous until mutated" lesson.

**Modify:**
- `loomwright/scripts/automate-helpers.sh` — add the PICK-time token-ceiling check (before picking an item, read the ledger via `read-token-ledger.sh --run-id`, compare to `--max-tokens`, park on breach or `LEDGER_UNREADABLE=1` when a ceiling is set) and the PICK-time lock acquire (via `run-lock.sh acquire --owner automate:<run_id>`), released at item completion/park.
- `loomwright/scripts/session-resume.sh` — add a new `### Stale run lock` heading (no existing heading mentions "lock" — this is new; place near the existing `### Active /autonomous sessions` (line ~741) / `### Recovery hints` (line ~747) blocks, same `append "### ..."` convention).
- `loomwright/scripts/close-stranded-run.sh` — release `.supervisor/run.lock` when its recorded `session_id` equals the ending session, following the file's existing fail-SAFE/always-exit-0 discipline (currently zero "lock" references).
- `loomwright/commands/automate.md`, `loomwright/commands/autonomous.md`, `loomwright/commands/supervisor.md` — add `--max-tokens N` to each Parameters table (mirroring the existing `--cheap` row/forwarding-note precedent verified at `commands/autonomous.md:63,65` and `skills/autonomous-loop/SKILL.md:297-301`'s literal 3-row forward table — this becomes a 4th row); document the run-lock acquire/park behavior at the relevant entry point (automate PICK / Supervisor INIT / autonomous INIT).
- `loomwright/skills/automate-loop/SKILL.md` — rewrite line 376 (`"single-run-per-repo is an assumed constraint, not enforced"`) to describe the now-enforced `run-lock.sh`; add the PICK-time ceiling+lock steps to §6/§11; add `read-token-ledger`/`run-lock` rows to the §1.5 helper table (mirroring the existing `resume-glob`/`reconcile-item` row shape at lines 63-64).
- `loomwright/skills/autonomous-loop/SKILL.md` — add `--max-tokens` to the INIT flag-parse prose (mirroring the `--cheap` INIT paragraph at line 121), persisting the parsed value into `state.json` at INIT (so EVALUATE can re-read it without re-parsing argv), and as a 4th row in the EXECUTE step 1 "Auto-forwarded flags" table (lines 297-301), plus the EVALUATE-time ceiling check (before each iteration, reading the persisted value) and the INIT-time lock acquire.
- `loomwright/skills/supervisor-config/SKILL.md` — Phase 0 INIT: parse `--max-tokens` (forwarded flag, mirrors `--cheap` resolution) and acquire `.supervisor/run.lock` (owner `supervisor:<session_id>`), released at the Phase 4.5 completion tail / Phase 4 abort.
- `loomwright/agents/supervisor.md` — Phase 0 INIT lock-acquire stanza (park with `run_lock_held owner=<label> pid=<pid> age=<s>` on a held lock, never proceed); Phase 3 poll loop entry per-iteration ceiling check (forwarded `--max-tokens`); completion-tail / Phase 4 abort lock release.
- `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — new "Token ceiling" section as a sibling to the existing §"Cost Profiles" (confirmed heading at line 564).
- `loomwright/docs/PITFALLS.md` — new pitfall entry describing the ceiling/lock and their honest limits (ledger counts only what SubagentStop hooks saw, not CI-side reviews or the main thread's own tokens; lock does not protect an IDE-hosted agent that never runs a plugin entry point).
- `CHANGELOG.md` (repo root) — new entry.
- `loomwright/.claude-plugin/plugin.json` (line 3, confirmed path — NOT bare `plugin.json`) + `.claude-plugin/marketplace.json` (repo root) — version bump in lockstep, per the release-surfaces convention (plugin.json + marketplace.json + CHANGELOG.md only).

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/automate-loop/SKILL.md`, `skills/autonomous-loop/SKILL.md`, `skills/supervisor-config/SKILL.md`, `skills/state-management/SKILL.md`, `skills/async-orchestration/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope vs Supervisor Capability CAUTION (Phase 2.5) — ~19 files, exceeds the context-bound guideline | MEDIUM | Kept single-subtask deliberately (heavy doc/automate-helpers.sh overlap between the two capabilities makes a split mostly-serial anyway); worker should expect and budget for multiple turn-limit resumes, matching items 04/05 in this same automate run (item 05 needed 5 resumes, ~1.4M subagent tokens, and still delivered a complete, independently-verified implementation). |
| `read-token-ledger.sh` must not silently treat `proxy: true` lines as real usage | HIGH | `emit-token-ledger.sh:342-361` only copies real usage fields when `usage_present(payload)`; a proxy-only line carries `proxy: true` + `token_proxy_kind`/`token_proxy_transcript_bytes` instead. The reader must explicitly zero-count (or separately flag) proxy lines rather than treating a missing key as 0-by-accident, which would silently undercount without a documented honest limit. |
| `run-lock.sh`'s reused TSV `meta` shape currently has no `session_id`/`owner` fields | LOW | `dispatch-pr-review.sh:550-558`'s `write_lock_meta` writes only `pr_url`/`pid`/`ts`/`worktree`/`run_log`. The new script needs its OWN meta shape (adding `session_id`, `owner`) — do not assume the existing function can be called unmodified; factor a shared TSV writer only if the two shapes can cleanly share one implementation, otherwise duplicate with a comment explaining why. |
| Requirement's own cited line numbers for two facts were imprecise | LOW | Independently re-verified during planning: (a) `emit-token-ledger.sh` "line ~97 derives main_root" — 97 is actually a *use* (a flag-file path); the derivation is lines 86–91, and `LOG_DIR` (the actual logs path) is set at line 114. (b) `automate-loop/SKILL.md:357` does not contain "assumed constraint, not enforced" — the sole hit is at line 376. Worker should re-grep rather than trust the requirement's line citations verbatim. |
| Lock does not protect an IDE-hosted agent that never runs a plugin entry point | LOW (accepted, non-goal) | Requirement's own Non-goals section states this explicitly — document as an honest limit in PITFALLS.md, do not attempt to solve it in this item. |
| No dollar conversion — the plugin has no price table | LOW (accepted, non-goal) | Requirement's Non-goals is explicit: token counts only, never invent a $ figure. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-22-cost-ceiling-and-run-lock.md
```

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/253
- **Reconciled:** lifecycle move completed by reconcile-jobs.sh, not by the completion tail
- **Evidence:** automate engine supplied merge evidence for .supervisor/requirements/red-team-hardening/06-cost-ceiling-and-run-lock.md (https://github.com/vikashruhilgit/loomwright/pull/253) — the engine verified the PR merged against the forge; this reconciler stayed offline
- **Caveat:** fields the completion tail would have recorded (files changed, heal decision and iterations, red-team advisory) are NOT recoverable after the fact and are deliberately omitted rather than invented.
