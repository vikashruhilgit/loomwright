# Supervisor Job: Manager re-verifies `provides:` on disk (verify-provides.sh)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — last commit 2026-09-06)
- **Git:** dirty (1 file — `.supervisor/postmortem/results.jsonl`, tracked ledger lines from prior drains; NOT part of this job — do not stage it), branch: main @ 6703218 (PR #215 merged, v15.69.0 live)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 2 (dirty tracked ledger above; 9 unrelated `.claude/worktrees/*` from other Claude sessions — leave untouched)
- **Source requirement:** .supervisor/requirements/review-gate-brief-conformance/02-manager-reverifies-provides.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | One bash+awk+jq script + one static `test-*.sh` + markdown prompt edits — the plugin's own stack (bash 3.2 / BSD userland; jq already a hard dependency of `automate-helpers.sh`, `send-webhook.sh`, `add-rule.sh`) |
| 2 | Dependency Availability | GO | No new dependency; `check-token-budget.sh`, `check-doc-currency.sh`, CI `loomwright/scripts/test-*.sh` glob (`.github/workflows/ci.yml` — auto-includes new suites) all exist |
| 3 | Architecture Fit | CAUTION | R3 (deterministic script, disk authoritative) fits the fail-SAFE-emitter / fail-CLOSED-consumer philosophy (CLAUDE.md §Failure-Mode Invariants). CAUTION: the requirement's literal "`no_contracts` ⇒ checkpoint" would fire on EVERY `/supervisor task:` no-brief run and on `legacy_brief: true` briefs (today those pass on the worker's `outputs_verified: []` rule) — that is a new gate in effect, contradicting R1. Resolved below (§Task "Decision D1") as: checkpoint on the `job:` path where Plan Reviewer Criterion 12 mandates contracts; retain the self-report (recorded, not gated) on no-brief / `legacy_brief` runs. |
| 4 | Scope vs Supervisor Capability | GO | 2 create + 11 modify, < 900 changed lines → single-agent (below `context-bound`); same shape as item 01 (PR #215) which one worker completed |
| 5 | Hard Blockers | CAUTION | `agents/worker.md` has only **437 proxy-token headroom** (`scripts/check-token-budget.sh`); the Step 5.5 edit MUST be net-negative or neutral in bytes (replace the 3-row table with a one-line script pointer). Raise the budget only on measured breach (AC8 rule). |

**Overall Verdict:** GO (2 CAUTION findings carried into Risk Assessment)

## Task
**Goal:** Ship `loomwright/scripts/verify-provides.sh` — the ONE deterministic implementation of the three `provides:` checks (`file` / `symbol` / `type`) — and make the Execute Manager poll-loop gate and both Supervisor inline gates run it against the tree the worker wrote to, so the on-disk result (not the worker's `WORKER_RESULT` self-report) decides whether a subtask passes the `outputs_verified` gate. A missing deliverable, or a worker that never reported, reaches the existing adjudication `EXECUTE_CHECKPOINT` every time. The worker keeps its self-verification (so it can fix its own gap before reporting) but calls the same script.

**Problem Statement:**
The per-subtask gate is the worker's own claim: `agents/worker.md` Step 5.5 runs `test -f` / `grep -nE` over its `provides:` list and emits `outputs_verified` + `outputs_gap`; the consumers (`agents/execute-manager.md` §"v12 outputs_verified gate"; `agents/supervisor.md` Single-Agent Path step 3 and Sequential Path gate) parse that block and never re-run the checks — the checkpoint even records `check_run: "worker self-verification (Step 5.5)"`. Observed consequences: a worker that dies before emitting `WORKER_RESULT` leaves the gate with no input and nothing flags it (memory `outputs-verified-silent-noop-on-dead-worker`); a worker that mis-reports `present` is believed. No script implements the check — it exists only as a prompt table duplicated in worker.md Step 5.5 and execute-manager.md Step 2b. Owner decisions R1 (no new gate — only the INPUT to the existing gate stops being self-reported) and R3 (a script, not a prompt-level "re-check") in `.supervisor/requirements/review-gate-brief-conformance/00-overview.md`.

**Owner decisions carried in (do not re-litigate):** R1 no new gate / no new adjudication option; R3 deterministic script, disk authoritative over the worker's report; R4 standalone `/review-pr` OUT of scope; nothing runs in the detached drain or Phase 4.5.

**Decision D1 (Launch Pad, resolving the Feasibility #3 CAUTION — surfaced to the owner at Phase 6):** the consumer passes the SAME pointer it handed the worker (the `.supervisor/jobs/in-progress/` brief on the `job:` path; the `.supervisor/requirements/{slug}-plan.md` plan file in `/supervisor task:` no-brief mode). `brief_unreadable`, `subtask_not_found` and `jq_missing` ⇒ checkpoint on every path (a gate that cannot read its contract does not pass). `no_contracts` ⇒ checkpoint on the `job:` path UNLESS the brief's `## Environment` declares `legacy_brief: true`; on `legacy_brief: true` and in no-brief mode (plan file with no contract blocks, or criteria passed inline with no pointer file) the consumer records `record_decision(phase: EXECUTE, decision: "provides_unverifiable: no_contracts — legacy/no-brief, worker self-report retained")` and falls through to today's self-report gate. This is exactly Plan Reviewer Criterion 12's own opt-out gate, reused — not a new flag.

## Acceptance Criteria
- [ ] AC1 — Given a fixture brief + fixture worktree where the worker's `WORKER_RESULT` says `status: completed, outputs_gap: ""` but one `provides` file is absent on disk, when the Execute Manager poll-loop protocol (`agents/execute-manager.md` §"v12 outputs_verified gate") is state-traced, then it yields an `EXECUTE_CHECKPOINT` with `adjudication_required: true`, `missing_outputs[].check_run` starting with `test -f` (the script's command + exit-code string, NOT the label `worker self-verification (Step 5.5)`), a `record_decision(... "provides_mismatch: worker=present disk=missing")` line, and the subtask is NOT marked complete. The prose must say "regardless of the worker's `status`".
- [ ] AC2 — Same fixture with NO `WORKER_RESULT` at all (dead worker / turn-limit exit, after the existing retry-once crash handling): the protocol still runs the script and yields the same checkpoint; with every item present on disk it records `record_decision(... "worker_result_absent: disk verified N/N present")` and proceeds to the tests/lint half of the gate — never a silent no-op.
- [ ] AC3 — A fixture where every `provides` item is present and the worker agrees: no checkpoint, no `provides_mismatch` decision, and exactly ONE extra Bash call per subtask — noted in the Execute Manager's tool-budget accounting (§"Tool call tracking" or the budget table: +1 Bash per subtask).
- [ ] AC4 — `verify-provides.sh <brief> <id> [--root <dir>]` prints ONE JSON object on stdout: `{"subtask_id":"<id>","outputs_verified":[{kind,path,name?,status:"present"|"missing",check_run:"<command> (exit N)"}],"outputs_gap":"<path or path:name, comma-separated, or \"\">","source":"verify-provides.sh"}` — `outputs_gap` byte-identical to the worker's format (`agents/worker.md` Step 5.5 item 4: `"src/foo.ts:Bar, src/baz.ts"`), built with `jq --arg` (never shell-templated JSON — LESSONS [a7e4fb1c]). On unreadable brief / subtask not found / no contract block it prints `{"subtask_id":"<id>","status":"unverifiable","reason":"brief_unreadable"|"subtask_not_found"|"no_contracts","source":"verify-provides.sh"}` and the reason on stderr; **always exit 0**; never writes; never executes brief content (no `eval`, no `source`). A missing `jq` is a 4th reason `jq_missing` (still exit 0); it routes like `brief_unreadable` — checkpoint on every path (D1). This is the ONE shell-templated object (jq is by definition absent): it carries `subtask_id` ONLY when the id matches the strict allowlist `^[[:alnum:]_-]+$`, otherwise omits the key — argv is caller text and must never reach the JSON unescaped.
- [ ] AC5 — ERE-special names match literally: with `name: "Foo$Bar"` and a file containing the literal `Foo$Bar` → `present`; a file containing `FooXBar` → `missing`. Fixtures for names containing each of `$`, `.`, `(`, `[` (and `+`/`*`/`?`/`|`/`{` in one combined fixture). Portable ERE only: the `type` check is `(type|interface|class|enum)[[:space:]]+<escaped>([^[:alnum:]_]|$)` (no `\s`/`\b` GNU-isms); the `symbol` check is `grep -nE -- '<escaped>' <path>`; the `file` check is `test -f <path>` — all relative to `--root` (default `.`), never `cd`-ing into it.
- [ ] AC6 — Parser tolerance (measured over real briefs — `build-context-digest.sh` header notes and `loomwright/sdk-spike/src/runner.ts` parseBrief): the contracts heading is matched case-insensitively at ANY `#` depth (`## Subtask Contracts`, `### Subtask Contracts`, `### Subtask contracts`), the YAML may sit inside a ```yaml fence or be raw; per-subtask anchors accepted: `# Subtask N …` YAML comment (the shape Launch Pad emits — see `.supervisor/jobs/done/2026-09-13-brief-conformance-phase45-review.md`), `### Subtask N …` markdown heading (inline layout with no umbrella heading), and `subtask_N:` key. Entries are `- {kind: "file", path: "x", name: "y"}` with quotes optional and a trailing `# comment` after the closing `}` stripped; `provides: []` yields `outputs_verified: []` + `outputs_gap: ""`; the `provides:` list ends at the next top-level key (`requires:` / `lanes:` / `external_requires:`), the next anchor, or the fence end. A `provides:` line with no parsable entries and no `[]` ⇒ treated as `[]` (log to stderr).
- [ ] AC7 — `verify-provides.sh --kind-table` prints the 3-row markdown check table (header + `file`/`symbol`/`type` rows with the exact commands from AC5); `docs/RESULT_SCHEMAS.md` §WORKER_RESULT embeds that table verbatim between `<!-- kind-table:begin -->` / `<!-- kind-table:end -->` markers (the single committed copy); `agents/worker.md` Step 5.5 REPLACES its 3-row table with one sentence pointing at `bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-provides.sh" <brief> <id> --root .` (net-negative bytes — worker.md headroom is 437 proxy tokens); `agents/execute-manager.md` Step 2b keeps its `requires` table but gains ONE sentence noting the commands are the same three `verify-provides.sh --kind-table` defines (non-goal: Step 2b logic unchanged).
- [ ] AC8 — Seam grep-gate (in `loomwright/scripts/test-verify-provides.sh`, one suite): `agents/execute-manager.md` §"v12 outputs_verified gate" cites `verify-provides.sh` AND the `provides_mismatch` decision AND "regardless of the worker"; `agents/supervisor.md` Single-Agent Path step 3 AND the Sequential Path gate each cite `verify-provides.sh` with `--root .` (cited by anchor, NOT line number — the file's own note says that reference "has drifted twice"); `agents/worker.md` Step 5.5 cites `verify-provides.sh`; the `--kind-table` output equals the RESULT_SCHEMAS.md marker-delimited copy byte-for-byte. Mutation control: copy execute-manager.md to a temp file, delete the line(s) carrying the script call from the poll-loop gate, gate the mutant on non-empty + differs-from-original, run the seam assertion against the mutant → MUST fail (LESSONS [fa32a308]). Suite shape per `test-brief-conformance-seam.sh`: `ok()`/`no()` DEFINED (`test-suite-helpers-defined.sh` meta-gate), pass/fail counters, `RESULT: N passed, M failed` tail, exit 1 on any failure, paths from `$BASH_SOURCE`, fixtures in `mktemp -d` with cwd elsewhere (proves `--root`), no gh/network/Docker.
- [ ] AC9 — `test-verify-provides.sh` also covers: per-kind present/missing; `provides: []`; the three `unverifiable` reasons (exit 0 + stderr reason each); two-item miss ⇒ `outputs_gap` exactly `"a/b.ts:Sym, c/d.ts"` order-preserving; a symbol whose `path` file is absent ⇒ `missing` with a `grep` check_run (exit 2); `--kind-table`; JSON validity via `jq -e .`; a `'`/`\`/newline in a `name` round-trips through the JSON (injection-safety gate); the jq-less path (jq stubbed off `PATH` via a temp dir + a subtask id containing `"`) still prints exit 0 + valid JSON with no `subtask_id` key (checked with python3 -c json.load or by asserting the literal object).
- [ ] AC10 — Docs: `docs/RESULT_SCHEMAS.md` §WORKER_RESULT gains one paragraph: `outputs_verified` is worker-reported and is cross-checked on disk by the consumer via `verify-provides.sh`; disk wins; the disagreement is recorded as `provides_mismatch` (a `/dreaming` signal, not a second gate) + the marker-delimited kind table. `docs/ARCHITECTURE_CONTRACTS.md` §"Agent Invariants" Execute Manager and Worker rows updated (manager re-verifies `provides` on disk; worker self-verifies via the same script). Three prose mirrors that describe the gate as worker-self-verified get a one-phrase edit each so no surface still claims the self-report is the gate input: `agents/orchestrator.md` — BOTH occurrences of the "(worker self-verification, zero tokens)" parenthetical, §"Review Gate Policy" (authoritative — cited by execute-manager.md and supervisor.md) AND §"Quality gate (no paired review subtask)" → "(worker self-verification cross-checked on disk by the consumer via `verify-provides.sh`, zero tokens)"; the old parenthetical must be 0-hit in orchestrator.md afterwards (assert it in the AC8 seam suite) — orchestrator headroom is 665 proxy tokens, measure, `skills/async-orchestration/SKILL.md` the "If the worker's own outputs_verified gate passed" comment (byte-neutral rewording — this skill is preloaded by execute-manager), and `docs/FAILURE_ESCALATION.md` the "Worker emits WORKER_RESULT with non-empty outputs_gap" trigger (→ "verify-provides.sh reports a missing item on disk OR the worker emits a non-empty outputs_gap"). Memory close-out (`outputs-verified-silent-noop-on-dead-worker`) is the /automate operator's, NOT this job's.
- [ ] AC11 — `bash scripts/check-token-budget.sh`, `bash scripts/check-doc-currency.sh`, and the FULL `for t in loomwright/scripts/test-*.sh; do bash "$t" || echo "FAIL $t"; done` loop are green before push (memory `run-full-ci-suite-loop-before-push`); a budget is raised ONLY on measured breach (measured + ~10%, JSON `note` + `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row in the same edit).
- [ ] AC12 — Release surfaces: `loomwright/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` versions bumped to the next minor above the LIVE `plugin.json` value read at execution (currently 15.69.0 → 15.70.0; LESSONS [16ffd26d]), the `vX.Y.Z` string in both `description` fields updated in place (never append a clause), and ONE new top entry in `CHANGELOG.md` in the established bold-paragraph shape naming: what changed, D1 (where `no_contracts` checkpoints and where it does not), the honest limits (`symbol` still matches any line containing the name — a comment passes; no semantic check; Step 2b `requires` logic untouched; nothing runs in the drain or Phase 4.5; this PR's own Phase 3 gate ran on the installed v15.69.0 prompts, so the disk re-check is first observable on the NEXT job after reinstall), and "Counts unchanged" (agents 14 / commands 23 / skills 41 / hooks 36). Grep the OLD version string repo-wide after the bump (LESSONS [0d7865dc]).

## Executable Acceptance
- cmd: bash loomwright/scripts/test-verify-provides.sh
- cmd: bash scripts/check-token-budget.sh
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | verify-provides.sh + test suite + consumer wiring (EM poll loop, Supervisor inline gates, worker Step 5.5) + docs + 3 prose mirrors + release surfaces | all (AC1–AC12) | 11 modify (+ `prompt-token-budgets.json` only on measured breach), 2 create | `skills/unit-testing/SKILL.md`, `skills/quality-checklist/SKILL.md`, `AGENT_GUIDELINES.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1 — verify-provides.sh + consumers (LAUNCHABLE)
provides:
  - {kind: "file",   path: "loomwright/scripts/verify-provides.sh"}
  - {kind: "file",   path: "loomwright/scripts/test-verify-provides.sh"}
  - {kind: "symbol", path: "loomwright/scripts/verify-provides.sh", name: "kind-table"}                 # the flag, named without its leading `--` so the installed worker's bare `grep -nE` check does not parse it as an option
  - {kind: "symbol", path: "loomwright/agents/execute-manager.md", name: "verify-provides.sh"}      # poll-loop gate cites the script (0 hits today)
  - {kind: "symbol", path: "loomwright/agents/execute-manager.md", name: "provides_mismatch"}       # the disk-wins decision string (0 hits today)
  - {kind: "symbol", path: "loomwright/agents/supervisor.md", name: "verify-provides.sh"}           # both inline gates (0 hits today)
  - {kind: "symbol", path: "loomwright/agents/worker.md", name: "verify-provides.sh"}               # Step 5.5 pointer replacing the table (0 hits today)
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "kind-table:begin"}           # marker-delimited single committed copy (0 hits today)
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "verify-provides.sh"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "verify-provides.sh"}                              # the new top entry (0 hits today)
requires: []
lanes:
  - "loomwright/scripts/verify-provides.sh"
  - "loomwright/scripts/test-verify-provides.sh"
  - "loomwright/agents/execute-manager.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/agents/worker.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/agents/orchestrator.md"
  - "loomwright/skills/async-orchestration/SKILL.md"
  - "loomwright/docs/FAILURE_ESCALATION.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CHANGELOG.md"
external_requires: []
```

**Implementation shape (the DO side — read the existing seams first, then edit in place):**
1. **`loomwright/scripts/verify-provides.sh`** (`#!/usr/bin/env bash`, `set -uo pipefail` — NOT `-e`; always `exit 0`). Header comment states: purpose, the fail-SAFE-emitter / fail-CLOSED-consumer split, D1, the honest `symbol` limit. Structure: (a) arg parse (`--kind-table` short-circuits; `<brief> <id>` positional; `--root <dir>` default `.`); (b) `jq` presence check → `unverifiable/jq_missing`; (c) `test -r "$brief"` → `brief_unreadable`; (d) ONE awk pass that is fence-aware and heading-level-agnostic (copy the extractor idea from `build-context-digest.sh`, not its code) and prints the selected subtask's `provides` entries as TAB-separated `kind<TAB>path<TAB>name` lines, plus a first status line `FOUND` / `NO_CONTRACTS` / `NOT_FOUND` / `EMPTY`; (e) per entry, run the check, capture rc, build the `check_run` string, append to a jq array via `jq -n --arg …` (`jq_missing` already excluded); (f) print the object. `ere_escape()` via `sed 's/[][\.*^$+?(){}|\\/]/\\&/g'` (bash 3.2 / BSD sed safe — the `/` escape is needed because the result feeds `grep -E`, not sed). Read no file with `cat`; use `while IFS= read -r` or awk.
2. **`agents/worker.md` Step 5.5** "After writing the summary file: verify own `provides:`": replace item 2's table with: *"Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-provides.sh" <pinned brief path> <your subtask id> --root .` (the ONE implementation of the three checks; `--kind-table` prints them) and copy its `outputs_verified` / `outputs_gap` into your result verbatim — the consumer re-runs the same script against your tree and disk wins."* Keep items 1, 3–5 and the no-`provides:`-list rule (script says `no_contracts`/`subtask_not_found` ⇒ report `[]` + `""` as today). Measure bytes before/after — must not grow.
3. **`agents/execute-manager.md` §"v12 outputs_verified gate"**: after `worker_result = parse_worker_result(result)` insert the script call (Bash, +1 tool call) against `--root {worktree_path}` with the in-progress brief path the Supervisor handed you, then the fail-CLOSED merge (AC1/AC2/D1) — pseudo-code in the same style as the surrounding block: `disk = run verify-provides.sh`; `if disk.status == "unverifiable"`: D1 routing; `missing = disk.outputs_verified where status == missing`; `if missing non-empty` ⇒ the existing `EXECUTE_CHECKPOINT` with `check_run: disk.check_run` and `reason: "verify-provides.sh: {disk.outputs_gap}"`; `elif worker_result absent` ⇒ `record_decision("worker_result_absent: …")` then continue to tests/lint; `if worker_result.outputs_gap != disk.outputs_gap` ⇒ `record_decision("provides_mismatch: worker=<x> disk=<y>")` (disk wins, no second gate). Update the §"Tool call tracking" / budget note: +1 Bash per subtask. Step 2b: ONE sentence per AC7.
4. **`agents/supervisor.md`** Single-Agent Path step 3 and Sequential Path "Deterministic gate" bullet: the same call with `--root .` and `brief_path` = the in-progress brief (or the plan-file pointer in no-brief mode), the same fail-CLOSED rule + D1, the same `record_decision` strings; cite `agents/execute-manager.md` §"v12 outputs_verified gate" by anchor (already the convention there).
5. **`loomwright/scripts/test-verify-provides.sh`** per AC8/AC9. Fixture brief written by the test into `mktemp -d` in the REAL Launch Pad shape (H3 heading, ```yaml fence, `# Subtask 1 —` comment, trailing `# …` comments on entries) plus one fixture in the `### Subtask N` inline shape and one with `## Subtask Contracts` H2. Run from a different cwd (`cd /` or the temp root) to prove `--root`.
6. **Docs + release** per AC10/AC12; token budgets per AC11.
7. **Before push:** full `test-*.sh` loop + both check scripts; `grep -rn "15.69.0" --include=*.json --include=*.md . | grep -v CHANGELOG` must be empty after the bump (`README.md` carries no version string — verified).

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` (mutation-control discipline), `skills/quality-checklist/SKILL.md` (post-task gates), `AGENT_GUIDELINES.md` (read-before-write rule; every shell deliverable ships a co-located static `test-*.sh` — LESSONS [34e7c865]) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Prior churn (postmortem ledger, same surfaces as PR #215): `self_heal_miss` recurred on `CHANGELOG.md`, `marketplace.json`/`plugin.json`, `ARCHITECTURE_CONTRACTS.md`, `prompt-token-budgets.json`; classes `drain_churn`, `convention_mismatch`, `quality_gap` | HIGH | Release-surface lockstep as a checklist (both manifests' `version` + in-place `vX.Y.Z` + ONE changelog entry); grep the old version repo-wide; budget mirror row only if raised |
| Feasibility #5: `agents/worker.md` budget headroom 437 proxy tokens — a table→pointer replacement that adds prose breaches CI (`check-token-budget.sh` fails CLOSED) | HIGH | Measure `wc -c agents/worker.md` before/after; the edit must be ≤ the original; raise only on measured breach with the mirror row |
| Feasibility #3 / D1: a literal "`no_contracts` ⇒ checkpoint" turns every `/supervisor task:` run into an adjudication stop (a new gate, violates R1) | HIGH | D1 routes `no_contracts` to checkpoint only where Criterion 12 mandates contracts (`job:` path, no `legacy_brief: true`); elsewhere record + retain self-report. State-trace all three paths (job / legacy / no-brief) in the EM prose (memory `feedback_prompt_is_program_state_trace`) |
| Parser written against ONE template (the digest builder's own recorded root cause, 3×): real briefs use H3 + fence + `# Subtask N` comments + trailing comments; the skill example is H2 | HIGH | AC6 enumerates the accepted layouts; three fixture shapes in the test; heading match is case-insensitive and depth-agnostic; fence-aware |
| ERE escaping / BSD grep: `\s`, `\b` are GNU-isms; an unescaped `$` or `.` silently matches too much (a `FooXBar` false `present`) | MEDIUM | AC5 portable patterns + literal-match fixtures for every special; run the suite on macOS AND read it as CI (ubuntu) would |
| Seam test vacuous (mutant invalid — `sed` delimiter collision or `perl \Q` interpolation — or helpers undefined → 127 swallowed) | MEDIUM | Gate the mutant on non-empty + differs-from-original + `bash -n` where applicable; define `ok`/`no`; assert the pass count matches the assertions written |
| JSON built by string templating lets a `'` / `\` / newline in a `name` (from a brief — user text) break the object or inject a field | MEDIUM | `jq --arg` only (LESSONS [a7e4fb1c]); AC9 round-trip fixture |
| Scope creep into Step 2b `requires` logic, the `symbol` regex semantics, Phase 4.5, or the drain | LOW | Non-goals explicit in the source requirement; Step 2b gets one sentence; the `symbol` limit is recorded in the script header + changelog, not fixed |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-13-manager-reverifies-provides.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-09-13T08:40:25Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/217
- **Branch:** feature/manager-reverifies-provides
- **Files changed:** 14
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** verify-provides.sh (fail-SAFE emitter, 90-assertion suite w/ two mutation controls) + fail-CLOSED consumer wiring in the EM poll-loop gate, both Supervisor inline gates and worker Step 5.5 (D1 routing); kind-table single-sourced (RESULT_SCHEMAS markers); 3 prose mirrors; v15.69.0 → v15.70.0. Heal iteration 1 fixed 2 HIGH (partial+empty-gap carve-out stop dropped; ABSENT WORKER_RESULT on legacy fall-through) + 2 MEDIUM same-class (subtask_id shape, --root per path); iteration 2 PASS; 2 residuals (changelog 75→90, checkpoint reason attribution) applied by the Supervisor main thread post-PASS. contract_conformance: pass (1 evaluated, 0 violations); benchmark: pass; ground_truth: pass 4/4 (repo runner — the installed-copy corpus checks fail "not inside a git repo": pre-existing tooling bug, task chip filed); rubric: n/a (no rubric); twin_builder: 2 written. Default drain suppressed by /automate (auto_review=false) — the engine owns the drain.
