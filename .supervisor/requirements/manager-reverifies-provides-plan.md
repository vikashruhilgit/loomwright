# Task Plan — manager-reverifies-provides

**Source brief:** `.supervisor/jobs/in-progress/2026-09-13-manager-reverifies-provides.md` (authoritative for AC1–AC12, Decision D1 and the 7-step Implementation-shape list; this plan does not restate them)
**Owner decisions (do not re-litigate):** R1 no new gate (only the gate's INPUT stops being self-reported) · R3 deterministic script, disk authoritative · R4 `/review-pr` out of scope · nothing runs in the drain or Phase 4.5 — `.supervisor/requirements/review-gate-brief-conformance/00-overview.md`
**Persistence:** file fallback (no `.beads/`) · **Base branch:** main @ 6703218 (verified: plugin.json + marketplace.json both 15.69.0; CHANGELOG top entry 15.69.0)
**Planned:** 2026-09-13 by Orchestrator

## Threshold validation

Checked against `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold" (bounds: `context-bound` = > 12 files OR > 800 changed lines; `genuine-parallelism` = ≥ 2 zero-overlap groups each ≥ 3 files):
- `file-conflict`: n/a — one work group; every lane is edited by one worker.
- `context-bound`: **fires by the letter on file count — 13 files (2 create + 11 modify) > 12; 14 if the token budget breaches.** Lines: estimated ~600–800 (script ~220–280, test ~300–380, EM gate ~40, supervisor ~15, worker net-negative, RESULT_SCHEMAS ~25, ARCHITECTURE_CONTRACTS ~4, three mirrors ~5, changelog ~15, manifests 4) — at the line bound, not clearly over it. The excess above 12 files is the three release surfaces (`plugin.json`, `marketplace.json`, `CHANGELOG.md` — touched by every job) plus one-phrase mirrors; the engineering surface is 7 files.
- `genuine-parallelism`: does NOT fire — no zero-overlap group exists. Any split (e.g. A = script + test + RESULT_SCHEMAS kind-table; B = agent prompts + docs + mirrors + release) is a two-link `requires:` chain in BOTH directions: the test suite (AC8) greps `execute-manager.md` / `supervisor.md` / `worker.md` / `orchestrator.md` for the script citation, and the prompts cite a script that must exist. It serializes, gains no parallelism, adds a worktree + merge, and reintroduces the cross-worktree producer/consumer false-`NEEDS_HUMAN` class the Review Gate Policy removed.
→ **ONE task, with the deviation recorded:** `context-bound` is exceeded by one file, on a bound the skill itself marks "initial calibration, not a measured optimum". Item 01 (PR #215, same shape, 9 files) ran single-agent cleanly. Supervisor/owner may overrule at Phase 2; if so the split shape above (A → B, `Split reason: context-bound`) is the only sane one. No per-subtask reviewer either way (Review Gate Policy).

## EPIC: manager-reverifies-provides

### TASK manager-reverifies-provides-1 — verify-provides.sh + test suite + consumer wiring + docs + mirrors + release — LAUNCHABLE
- [ ] **Status:** open
- **Blocked by:** nothing (`requires: []`, `external_requires: []`)
- **Acceptance criteria:** AC1–AC12 of the brief (all). Verified starting state 2026-09-13: the 10 `provides` tokens are 0-hit today (`verify-provides.sh` in execute-manager.md / supervisor.md / worker.md / ARCHITECTURE_CONTRACTS.md / CHANGELOG.md; `provides_mismatch` in execute-manager.md; `kind-table:begin` in RESULT_SCHEMAS.md; both script files absent).
- **Token headroom measured (`bash scripts/check-token-budget.sh`, proxy tokens):** worker 437 (Step 5.5 edit MUST be net-negative — the 3-row table is 5 lines/~330 bytes, the replacement sentence must be shorter), orchestrator 665, execute-manager 3159 (comfortable for the ~40-line pseudo-code insert), supervisor 2081. `async-orchestration` is preloaded by execute-manager → byte-neutral rewording there.
- **Files (verified: exist):**
  - `loomwright/agents/execute-manager.md` — §"v12 outputs_verified gate" (poll-loop pseudo-code after `worker_result = parse_worker_result(result)`; today's `check_run: "worker self-verification (Step 5.5)"` is the label to replace); §"Tool call tracking" (+1 Bash per subtask); Step 2b one sentence (AC7). **Also** the failure-table row `outputs_verified gate gap (partial worker / non-empty outputs_gap)` (§"Failure Modes" table) → add "disk-missing item" so the table matches the new gate (in-lane, not in the brief's list).
  - `loomwright/agents/supervisor.md` — Single-Agent Path step 3 and Sequential Path "Deterministic gate" bullet (both cite `--root .`; anchor-cite the EM section, never line numbers). **Also** while rewriting step 3: its parenthetical says "the same check the Execute Manager runs *pre-spawn*" — the v12 gate is the *poll-loop* gate (pre-spawn is Step 2b); fix the word in passing. **Optional, same file:** the "Agents Spawned" table row `Worker (Single-Agent / Sequential path) | Parse WORKER_RESULT block…` — add "(disk re-check via `verify-provides.sh`)" so no in-file surface still describes the parse as the gate.
  - `loomwright/agents/worker.md` — Step 5.5 item 2 table → one-sentence script pointer (brief step 2). Keep items 1, 3–5 and the no-`provides:` rule. Guard: `scripts/check-contract-parity.sh` enum gate requires `present` / `missing` to remain in worker.md — they survive in items 3–4 and the Output Format block, do NOT touch those.
  - `loomwright/agents/orchestrator.md` — BOTH "(worker self-verification, zero tokens)" occurrences (§"Review Gate Policy" ~L48 and §"Quality gate (no paired review subtask)" ~L304 [pins: `worker self-verification, zero tokens`]) → cross-checked-on-disk phrasing; old phrase 0-hit afterwards (AC8 assertion).
  - `loomwright/skills/async-orchestration/SKILL.md` — the poll-loop comment "No reviewer is spawned here. If the worker's own outputs_verified gate / passed (no outputs_gap …" (~L261, spans 2 lines) — byte-neutral rewording.
  - `loomwright/docs/FAILURE_ESCALATION.md` — trigger line "OR Worker emits WORKER_RESULT with non-empty outputs_gap" (~L166). **Also** the §Cross-references list (~L236, `agents/worker.md Step 5.5 (…)`) — add a `scripts/verify-provides.sh` line (in-lane).
  - `loomwright/docs/RESULT_SCHEMAS.md` — §WORKER_RESULT (H2 at L12): one paragraph + `<!-- kind-table:begin -->`/`<!-- kind-table:end -->` block that must equal `verify-provides.sh --kind-table` byte-for-byte (AC7/AC8).
  - `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — §"Agent Invariants" table, Execute Manager row (~L131) and Worker row (~L133).
  - `loomwright/docs/prompt-token-budgets.json` + ARCHITECTURE_CONTRACTS §"Prompt Token Budgets" mirror row — ONLY on measured breach (AC11).
  - `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md` — 15.69.0 → 15.70.0, in-place `vX.Y.Z` in both descriptions, ONE bold-paragraph top entry incl. D1 + honest limits + "Counts unchanged (14/23/41/36)"; `grep -rn "15.69.0" --include=*.json --include=*.md . | grep -v CHANGELOG` empty afterwards.
  - **[TO BE CREATED]** `loomwright/scripts/verify-provides.sh` — brief step 1 (bash 3.2 / BSD sed / portable ERE; `set -uo pipefail`, always exit 0, `jq --arg` only, never `cd`, never `eval`/`source`). Extractor idea from `loomwright/scripts/build-context-digest.sh` (verified: exists), not its code.
  - **[TO BE CREATED]** `loomwright/scripts/test-verify-provides.sh` — AC8/AC9; shape per `loomwright/scripts/test-brief-conformance-seam.sh` (verified: exists); `ok()`/`no()` defined (`loomwright/scripts/test-suite-helpers-defined.sh` meta-gate, verified: exists); auto-included by the `loomwright/scripts/test-*.sh` glob in `.github/workflows/ci.yml` (verified: L72).
- **Not touched (checked, no change needed):** `scripts/check-command-sync.sh` scopes only `commands/code-reviewer.md`; `loomwright/skills/SKILLS_INDEX.md` (no new skill); `loomwright/hooks/hooks.json` and `loomwright/scripts/validate-worker-result.py` (no coupling on the `check_run` label); `CLAUDE.md`, `AGENT_GUIDELINES.md`, `README.md`, `commands/{supervisor,orchestrator,agent-help}.md` — all say "deterministic `outputs_verified` gate" without claiming the self-report is its input, so they stay true. `loomwright/scripts/write-agent-memory.sh` ~L124 comment says "the self-reported outputs_verified gate keys on it" — stays true in substance (the disk `symbol` check greps for the same token); leave unless already editing, do not add a 15th file for it.
- **Ordered DO steps:** brief "Implementation shape" 1 → 7 in that order (script first, so the test, the `--kind-table` copy in RESULT_SCHEMAS and the prompt pointers cite something that exists; measure `wc -c loomwright/agents/worker.md` before step 2 and after).
- **State-trace before finishing (D1, memory `feedback_prompt_is_program_state_trace`):** three paths through the EM gate — `job:` brief without `legacy_brief` (`no_contracts` ⇒ checkpoint), `legacy_brief: true` (`provides_unverifiable` decision + self-report retained), `/supervisor task:` no-brief (same) — plus the four routes `brief_unreadable` / `subtask_not_found` / `jq_missing` ⇒ checkpoint on every path, `worker_result_absent` with N/N present ⇒ proceed to tests/lint.
- **Gate (deterministic, zero tokens — no per-subtask reviewer):** `bash loomwright/scripts/test-verify-provides.sh` green incl. the mutant control; `bash scripts/check-token-budget.sh`; `bash scripts/check-doc-currency.sh`; `scripts/check-contract-parity.sh`; FULL `for t in loomwright/scripts/test-*.sh; do bash "$t" || echo "FAIL $t"; done` (memory `run-full-ci-suite-loop-before-push`); all 10 `provides` tokens present on disk.
- **Skills:** `skills/unit-testing/SKILL.md` (mutation control), `skills/quality-checklist/SKILL.md` (post-task gates + Self-Heal Miss-Class "count / restated-list drift", "cross-reference precision drift"), `AGENT_GUIDELINES.md` (read-before-write; every shell deliverable ships a co-located `test-*.sh`).
- **Estimated:** 3–5 h single worker (script + suite are the bulk; prompt edits are surgical).

## Sequence
```
manager-reverifies-provides-1 (all AC) → FINALIZE (PR, base main) → Phase 4.5 integrated review (sole LLM lens)
```

## Risks (beyond the brief's table)
| Risk | Mitigation |
|------|-----------|
| Threshold deviation (13 files > 12) contested at Phase 2 | Recorded above with the only sane split shape; the split gains no parallelism (bidirectional `requires`) |
| worker.md Step 5.5 replacement grows bytes → `check-token-budget.sh` fails CLOSED (437 headroom) | Replacement sentence must be shorter than the 5-line table; measure before/after; raise budget only on measured breach with the mirror row |
| `--kind-table` vs RESULT_SCHEMAS copy drift (trailing whitespace / `\|` escaping inside a markdown table cell) | AC8 byte-for-byte assertion; generate the doc block FROM the script output, don't hand-type it |
| Parser built against one brief layout | Three fixture shapes (H3+fence+`# Subtask N`, `### Subtask N` inline, `## Subtask Contracts` H2) — AC6 |
| Seam suite assertion vacuous (mutant invalid, `ok`/`no` undefined) | Mutant gated non-empty + differs; helpers defined; count assertions vs `RESULT:` tail |
| This PR's own Phase 3 gate runs on installed v15.69.0 prompts | Expected — the disk re-check is first observable on the NEXT job after reinstall; say so in the changelog (AC12) |
