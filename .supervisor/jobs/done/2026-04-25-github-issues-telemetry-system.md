# Supervisor Job: GitHub Issues Telemetry System

**Source:** `temp/self-learning.md`
**Created:** 2026-04-25
**Last Refined:** 2026-04-25 (v5 — post-R7.1 wording polish, R8 PASS confirmation)
**Launch Pad Version:** 7.2.0 (plugin v11.1.2)
**Plan Review Status:** PASS (Round 8, 2026-04-25 — empty issues; R7.1 internal consistency + no R1–R6 regressions confirmed; see §11)

---

## 1. Environment

| Item | Status | Notes |
|------|--------|-------|
| Project root | ✓ | `~/Documents/work/AI/ai-agent-manager` |
| CLAUDE.md | ✓ fresh | v11.1.2 matches `plugin.json` |
| Git | ✓ clean | branch: `main`, no uncommitted changes |
| Worktrees | ✓ | none orphaned |
| GitHub CLI | ✓ | authenticated as `vikashruhilgit`, scope `repo` (issue creation allowed) |
| Git remote | ✓ | `https://github.com/vikashruhilgit/ai-agent-manager.git` |
| Blockers | 0 | — |
| Warnings | 0 | Supervisor will cut feature branch off `main` as normal |

_Validation: Phase 1 complete. Safe to launch Supervisor._

---

## 2. Task

**Goal:** Implement an opt-in, structured GitHub Issues telemetry system for the ai-agent-manager plugin. After a qualifying agent run completes, optionally create a GitHub issue (with labels and a structured body) that captures task outcome, derived score, and agent performance — enabling longitudinal analysis to improve prompts and find weak agents.

**Source document:** `temp/self-learning.md` (full design brief — keep as the single source of truth for issue format, labels, consent UX, and privacy rules).

**Non-goals (explicitly out of scope for this ticket):**
- Session-level batch-mode issue (one issue summarising N tasks) — tracked as future enhancement in `docs/TELEMETRY.md`.
- Weekly summary bot or automated analytics over created issues.
- Backend/server component. Telemetry creates GitHub issues only; no separate service.
- Sending telemetry for user code edits or non-agent activity.

---

## 3. Acceptance Criteria

### Consent — strict opt-in via slash command only

**Design decision (resolves consent-orchestration gap from external review v2):** A `type: command` hook cannot drive an interactive prompt. Therefore the hook NEVER attempts to ask the user anything; it only acts on pre-existing consent. First-run UX is mediated entirely by the user invoking `/telemetry enable` (typically prompted by a one-line install/README note). This split is the only design that is actually runnable with Claude Code hooks.

- [ ] **Consent — uninitialised state:** Given `.supervisor/telemetry-consent.json` does not exist OR contains `{"telemetry": "prompt"}`, when a qualifying agent run completes, then `send-telemetry.sh` (a) writes a one-line "telemetry pending — run `/telemetry enable` or `/telemetry disable`" entry to `.supervisor/logs/telemetry.log` (rate-limited to once per session — see "Session-scoped rate limiting" AC below), (b) creates NO GitHub issue, and (c) exits 0. The hook NEVER attempts an interactive prompt.
- [ ] **Session-scoped rate limiting (real session key, not a global flag):** The wrapper extracts `session_id` from the hook's stdin JSON payload (Claude Code provides this field in every hook payload — see `WorktreeCreate` reference at `hooks.json:88-107` for stdin parsing pattern). The pending-notice flag is then `.supervisor/logs/telemetry-pending-shown-${session_id}.flag` — one file per session, not a single global file. Given the hook fires twice in the same session with consent uninitialised, when the wrapper checks for the per-session flag, then it finds the flag (created on first hit) and skips the log write the second time. Given a NEW session starts (different `session_id`), when the hook fires, then no per-session flag exists yet and the notice is logged once. **Cleanup:** the wrapper opportunistically deletes any `telemetry-pending-shown-*.flag` older than 24h on each run (cheap `find … -mtime +1 -delete`) so the log directory does not accumulate stale flags indefinitely. **Fallback:** if `session_id` is missing or empty in the stdin JSON (defence in depth), fall back to `telemetry-pending-shown-nosession-$(date +%Y%m%d%H).flag` (per-hour bucket — limits noise to ~once per hour worst case).
- [ ] **Consent — explicit enable via slash command:** Given the user runs `/telemetry enable`, when the command executes, then it writes `{"telemetry": "always_allow", "telemetry_repo": "<value-from-prompt-or-env>"}` to `.supervisor/telemetry-consent.json` and prints confirmation including resolved target repo. The `/telemetry enable` command is the ONLY mechanism for first-time consent — no hook-driven prompt.
- [ ] **Consent — persistent allow:** Given `.supervisor/telemetry-consent.json` contains `{"telemetry": "always_allow"}` AND a target repo is configured, when a qualifying run completes, then the telemetry script runs non-interactively and posts the issue.
- [ ] **Consent — denied:** Given `.supervisor/telemetry-consent.json` contains `{"telemetry": "no"}`, when any agent run completes, then no issue is created, no network call is made, and the script logs nothing beyond a single "denied — skipped" entry per session.
- [ ] **Interest filter:** Given an agent run produced a result block with derived score ≥ 5 AND status `completed`/`PASS`, when telemetry evaluates, then the run is skipped (not interesting — avoids spam per spec §6A).
- [ ] **Interest filter — inverse:** Given a run has derived score < 5 OR status ∈ {`failed`, `FAIL`, `completed_with_escalation`, `ESCALATED`, `NEEDS_HUMAN`}, when telemetry evaluates, then an issue IS created (assuming consent = `always_allow` AND target repo configured).
- [ ] **Issue format:** Given telemetry creates an issue, when formatting the body, then it follows the template from `temp/self-learning.md` §1 — sections for Task Summary, Agent Scores, Issues Detected, AI Suggestions, Tools Used, Raw Data (JSON). Title format: `[Telemetry] {agent_type} | Score: {N} | Failed: {true|false}`.
- [ ] **Labels:** Given an issue is created, when labels are applied, then the issue carries `telemetry`, a `score:{low|medium|high}` tier per spec §2 (low < 4, medium 4–7, high 8+), `task:{agent-type}` (e.g., `task:supervisor`, `task:qa-executor`), and `agent:{name}-weak` when any sub-agent's derived sub-score is < 5.

### Privacy + exit semantics — wrapper/core split (resolves contradiction from external review v2)

**Design decision:** Two scripts, not one. The wrapper is what `hooks.json` calls and is contractually fire-and-forget; the core does the real work and may exit non-zero on privacy violation. Privacy fail-closed and hook-non-blocking are both honoured cleanly with this split.

- [ ] **Two scripts exist:** `ai-agent-manager-plugin/scripts/send-telemetry.sh` (thin wrapper) and `ai-agent-manager-plugin/scripts/send-telemetry-core.sh` (real logic). The wrapper is what `hooks.json` references; the core is invoked by the wrapper and may also be invoked directly for testing/debugging.
- [ ] **Wrapper guarantees exit 0:** Given the wrapper `send-telemetry.sh` is invoked by `SubagentStop`, when it runs, then it pipes stdin to `send-telemetry-core.sh`, captures the core's exit code and stderr, appends both to `.supervisor/logs/telemetry.log`, and ALWAYS exits `0` regardless of core outcome. (Mirrors existing `WorktreeCreate`/`StopFailure` log-and-continue style at `hooks.json:88-107`.)
- [ ] **Core fails closed on privacy violation:** Given `send-telemetry-core.sh` is processing a payload, when the privacy whitelist check (regex deny-list for `sk-…`, `ghp_…`, `api[_-]?key`, `Bearer\s+\w+`, `password\s*[:=]`, `/Users/[a-zA-Z._-]+/`, `/home/[a-zA-Z._-]+/`, email regex, raw `.env` content patterns) finds ANY match in the prospective issue body, then the core (a) does NOT call `gh issue create`, (b) writes a structured `privacy_blocked` log entry to `.supervisor/logs/telemetry.log` with a redacted excerpt of WHICH pattern matched (no payload contents), and (c) exits with code `2` (distinct from "no consent" = `3`, "no repo configured" = `4`, "filter skipped" = `5`, generic error = `1`). The wrapper still exits 0 to the hook; the structured log entry is the audit trail.
- [ ] **Core also fails closed on schema violation:** Given the inbound payload does not match any expected result-block schema (`SUPERVISOR_RESULT`, `CODE_REVIEW_RESULT`, `QA_RESULT`), when the core parses it, then it logs `unknown_payload_skipped` and exits with code `5` (treated as "filter skipped" — not a privacy event).
- [ ] **No leak via stderr:** Given the core has any failure mode, when it writes to stderr, then stderr content is redacted by the same privacy whitelist before the wrapper appends it to the log file (defence in depth — error messages can themselves echo secrets).

### Target repo — disabled by default (resolves wrong-default issue from external review v2)

**Design decision:** This plugin is intended to be installed in arbitrary user projects whose `origin` is the user's own app repo. Defaulting telemetry to `origin` would post issues into the user's repo, which is wrong on every axis (privacy, signal-vs-noise, support burden). Telemetry is therefore **disabled by default until explicitly configured**.

- [ ] **Target repo — explicit only:** Given neither the env var `AI_AGENT_MANAGER_TELEMETRY_REPO` nor the `telemetry_repo` field in `.supervisor/telemetry-consent.json` is set, when telemetry runs, then the core exits with code `4` (`no_repo_configured`) and the wrapper logs `telemetry_repo_unset — set AI_AGENT_MANAGER_TELEMETRY_REPO or run /telemetry enable to choose target` (rate-limited to once per session).
- [ ] **Target repo — env var precedence:** Given `AI_AGENT_MANAGER_TELEMETRY_REPO` is set to a non-empty value of the form `owner/repo`, when telemetry runs, then `gh issue create --repo $AI_AGENT_MANAGER_TELEMETRY_REPO …` is used and the consent-file `telemetry_repo` is ignored.
- [ ] **Target repo — consent-file fallback:** Given env var is unset but `.supervisor/telemetry-consent.json` contains a `telemetry_repo` value, when telemetry runs, then that value is used.
- [ ] **`/telemetry enable` collects target repo:** Given the user runs `/telemetry enable`, when the command runs interactively (in the slash-command handler, NOT in a hook), then it asks the user which repo to send telemetry to (suggesting `vikashruhilgit/ai-agent-manager` as the canonical maintainer repo for community-shared signal but accepting any `owner/repo`), and writes the answer to `telemetry_repo` in the consent file alongside `telemetry: always_allow`.
- [ ] **`/telemetry status` reports resolved target:** Given the user runs `/telemetry status`, when the command runs, then it prints: consent state, resolved target repo (or "unset — telemetry disabled"), source of the resolution (env var vs consent file vs none), last-sent timestamp from `.supervisor/logs/telemetry-sent.log` (or "never"), and a count of **retained** pending-notice session markers from approximately the last 24 hours (read by counting matching `.supervisor/logs/telemetry-pending-shown-*.flag` files — each file represents one session within the cleanup window). The wording must explicitly say "retained ~24h" and NOT "all-time" or "ever", because the wrapper's opportunistic 24h reaper (see §3 line 49) means older markers no longer exist on disk. Per-event counts are not retained.

### Other behaviour (unchanged from v1)

- [ ] **Scoring rubric documented + deterministic:** Given the same agent result block is scored twice, when the core's score function runs, then the same score is produced (deterministic). Rubric lives in `ai-agent-manager-plugin/docs/TELEMETRY.md` §Scoring. **Rubric MUST be expressed as three separate per-result-block tables — one each for `SUPERVISOR_RESULT`, `CODE_REVIEW_RESULT`, `QA_RESULT` — not a single unified enum-to-score mapping** (the three schemas use different status enums and cannot be collapsed without ambiguity).
- [ ] **Slash command surface:** Given a user types `/telemetry status` / `/telemetry enable` / `/telemetry disable` / `/telemetry test`, when the command runs, then `status` reports state per the AC above, `enable` and `disable` write the consent file (and `enable` also asks for target repo), and `test` invokes `send-telemetry-core.sh --dry-run` against either the latest matching log payload or a built-in fixture, printing the formatted issue body and target repo without calling `gh`.
- [ ] **Hook wired:** Given an agent in the matcher list (`supervisor-runner`, `code-reviewer`, `qa-executor`) completes, when Claude Code fires `SubagentStop`, then the wrapper `ai-agent-manager-plugin/scripts/send-telemetry.sh` is invoked with the hook's JSON payload on stdin. Hook is type `command` (zero-latency, matches existing `WorktreeCreate`/`StopFailure` pattern at `hooks.json:88-107`).
- [ ] **Docs updated:** Given the feature ships, when a new user installs the plugin, then `README.md`, `.claude-plugin/README.md`, and `CLAUDE.md` mention `/telemetry`, consent flow, and privacy guarantees. `SKILLS_INDEX.md` contains the new `telemetry/` skill row (count bumps 47 → 48).
- [ ] **Version bumped:** Given this feature lands, when inspecting `ai-agent-manager-plugin/.claude-plugin/plugin.json`, then `version` is `11.2.0` (minor bump — new feature, backward compatible) with an updated `description`.
- [ ] **No regressions:** Given existing hooks/agents/skills, when grep checks the repo, then no existing hook matchers, result-block schemas, or agent prompts are altered except in ways explicitly documented in this brief (version + description in plugin.json; new row in SKILLS_INDEX.md; mentions in CLAUDE.md/README.md).

---

## 4. Feasibility (Phase 2.5 — Grounded)

**Verdict: CAUTION — proceed with caution findings folded into Risk Assessment (§8).**

| Check | Result | Evidence |
|-------|--------|----------|
| Tech Stack Compatibility | **GO** | Plugin already uses `type: "command"` shell hooks (see `WorktreeCreate`, `StopFailure` in `hooks.json:88-107`). Shell + `gh` CLI is native to the plugin. |
| Dependency Availability | **GO** | `gh auth status` confirmed authenticated with `repo` scope (can create issues). No new dependencies. `jq` used in existing script patterns — assume available (flag as warning if not). |
| Architecture Fit | **CAUTION** | Spec `temp/self-learning.md` §5 proposes `core/evaluation/` and `core/telemetry/` as Node module directories. This repo is a Claude Code plugin (markdown agents + skills + hooks), not a Node app. Translation: `skills/telemetry/` for pattern, `scripts/send-telemetry.sh` for runtime, extended `hooks.json` for trigger, `commands/telemetry.md` for user control. The spec's JS example function `sendTelemetry(data)` becomes the shell script. |
| Scope vs Supervisor | **GO** | Decomposes cleanly into 6 subtasks (1, 2a, 2b, 3, 4, 5) of 30–60 min each, with one parallel pair (Batch 4: #3 ∥ #4) — within the 3–7 range. (Originally 4 subtasks in v1; Subtask 2 was split into 2a + 2b in v3 to keep within CLAUDE.md's 30–60 min ideal — see §11 Round 3 R3.2.) |
| Hard Blockers | **CAUTION** | Spec shows numeric scores (0–10) with per-agent sub-scores (Planner, Executor, QA). Our existing result blocks emit enums (`PASS`/`FAIL`/`NEEDS_HUMAN`) and counts (`heal_remaining_issues`, `subtasks_failed`, `tests_failed`). A **deterministic score-derivation function must be designed** as part of Subtask 1; otherwise the "Score: 6/10" in the spec is undefined behaviour. Mitigation: design rubric first, gate all other subtasks on its review. |

**Fallback: none.** CLAUDE.md is rich (all 5 feasibility checks had evidence). User gate not required; proceed.

---

## 5. File Impact Map

Legend: confidence **HIGH** / MEDIUM / LOW. New files = create; existing = modify.

### Create (new)

| File | Confidence | Purpose |
|------|-----------|---------|
| `ai-agent-manager-plugin/docs/TELEMETRY.md` | HIGH | Design doc: scoring rubric, issue schema, consent flow, privacy rules, future batch mode |
| `ai-agent-manager-plugin/skills/telemetry/SKILL.md` | HIGH | Reusable pattern — how to emit telemetry from a project using this plugin |
| `ai-agent-manager-plugin/scripts/send-telemetry.sh` | HIGH | **Wrapper** (thin) — what `hooks.json` calls. Pipes stdin to core, captures exit code + stderr, appends both to `.supervisor/logs/telemetry.log`, ALWAYS exits 0. ~20 lines. |
| `ai-agent-manager-plugin/scripts/send-telemetry-core.sh` | HIGH | **Core** (real logic) — read SubagentStop JSON from stdin → parse result block → derive score → check consent → check target repo → run privacy whitelist → format body → call `gh issue create`. May exit non-zero (codes: 0=sent, 1=generic err, 2=privacy_blocked, 3=no_consent, 4=no_repo_configured, 5=filter_skipped). Invoked by wrapper AND by `/telemetry test` for dry-run. |
| `ai-agent-manager-plugin/scripts/telemetry-fixtures/` (dir + 3 JSON files: `supervisor-pass.json`, `supervisor-escalated.json`, `qa-failed.json`) | HIGH | Test fixtures for reproducible dry-runs |
| `ai-agent-manager-plugin/commands/telemetry.md` | HIGH | Slash command `/telemetry [status|enable|disable|test]` |

### Modify (existing)

| File | Confidence | Change |
|------|-----------|--------|
| `ai-agent-manager-plugin/hooks/hooks.json` | HIGH | Extend `SubagentStop` with new matchers for `supervisor-runner`, `qa-executor`, `code-reviewer` to additionally invoke `scripts/send-telemetry.sh` (side-by-side with existing prompt validators — do NOT replace). New `type: command` entry per matcher. |
| `ai-agent-manager-plugin/.claude-plugin/plugin.json` | HIGH | `version`: `11.1.2` → `11.2.0`; `description` updated to mention telemetry feature. |
| `ai-agent-manager-plugin/skills/SKILLS_INDEX.md` | HIGH | Add new row under a new section (or "Workflow / Orchestration"): `Telemetry | telemetry/ | — (reference, shell-script-driven) | ~600 | 1.0.0 | 2026-04`. Update any aggregate count in intro text (currently 47 skills → 48). |
| `CLAUDE.md` (root) | HIGH | Add a new subsection under Architecture describing the telemetry system + `/telemetry` command + consent/privacy. Bump version string in "Plugin Metadata" to 11.2.0. |
| `.claude-plugin/README.md` | HIGH | Document `/telemetry` command + consent UX. |
| `README.md` | MEDIUM | User-facing one-paragraph intro + link to `docs/TELEMETRY.md`. |
| `.gitignore` | LOW | **Confirmatory only** — `.gitignore` already contains `.supervisor/` (line 34), which transitively ignores `.supervisor/telemetry-consent.json`. Subtask 5 should verify this coverage and, if kept, add an explicit `.supervisor/telemetry-consent.json` line with a comment as belt-and-braces; otherwise skip this file entirely and note the pre-existing coverage in `docs/TELEMETRY.md`. Either choice is acceptable. |
| `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` | LOW | Optional: if we define a `TELEMETRY_EVENT` schema as the canonical payload written to the issue body (recommended for future machine-parsing). Skip only if Subtask 1 decides a loose JSON blob is sufficient. |

### Read-only (discovery — not modified)

- `ai-agent-manager-plugin/agents/supervisor.md`, `agents/code-reviewer.md`, `agents/qa-executor.md` — to understand what signals are available in each result block
- `ai-agent-manager-plugin/hooks/hooks.json` (existing `WorktreeCreate`/`StopFailure` blocks lines 88–107) — as the reference style for `type: command` hooks
- `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` — to pick score-input fields precisely
- Repo-root `scripts/validate-version.sh`, `scripts/check-command-sync.sh` — for shell-script conventions (shebang, error handling style). **Note on directory convention:** new telemetry scripts go under `ai-agent-manager-plugin/scripts/` (plugin-runtime, shipped with the plugin). Repo-root `/scripts/` is reserved for release/CI tooling. Subtask 1's `docs/TELEMETRY.md` must document this split in one line so future contributors don't accidentally drop runtime scripts at repo root.

---

## 6. Subtask Structure

| # | Title | Files (create / modify) | Est. time | Depends on | Parallelism |
|---|-------|------------------------|-----------|------------|-------------|
| 1 | **Design: scoring rubric, issue schema, consent spec, privacy whitelist** | CREATE: `docs/TELEMETRY.md` (initial draft — Subtask 5 will append post-implementation sections), `skills/telemetry/SKILL.md` | 30–45 min | — | **LAUNCHABLE** |
| 2a | **Wrapper script + structured exit-code contract + fixtures** | CREATE: `scripts/send-telemetry.sh` (~20-line wrapper, ALWAYS exits 0, captures stdin → tees core output → logs exit code + redacted stderr to `.supervisor/logs/telemetry.log`), `scripts/telemetry-fixtures/{supervisor-pass.json, supervisor-escalated.json, qa-failed.json}` | 30–40 min | #1 | BLOCKED by #1 |
| 2b | **Core script: consent I/O + target-repo resolution + privacy whitelist + per-block score function + dry-run** | CREATE: `scripts/send-telemetry-core.sh` (real logic, exit codes 0–5 per §9 spec, `--dry-run` flag) | 45–60 min | #2a (depends on exit-code contract being stable) | BLOCKED by #2a |
| 3 | **Wire hooks + add `/telemetry` slash command (handles enable/disable/status/test, including interactive target-repo collection on enable)** | MODIFY: `hooks/hooks.json` (call wrapper); CREATE: `commands/telemetry.md` | 45–60 min | #2b | BLOCKED by #2b |
| 4 | **Fixture-driven verification (dry-run CI-style check)** | CREATE: `scripts/test-telemetry.sh` (runs each fixture through `send-telemetry-core.sh --dry-run`, asserts expected exit code, diffs body against golden output) | 30–45 min | #2b | **PARALLEL with #3** (no file overlap — touches scripts/, not hooks.json or commands/) |
| 5 | **Docs (incl. post-implementation update of `docs/TELEMETRY.md`) + version bump + SKILLS_INDEX count + .gitignore confirmation** | MODIFY: `plugin.json`, `SKILLS_INDEX.md`, `CLAUDE.md`, `.claude-plugin/README.md`, `README.md`, `.gitignore` (confirmatory only — see §5), AND **`docs/TELEMETRY.md`** to append: (a) wrapper-vs-core architecture diagram, (b) authoritative exit-code table mirroring §9 line "Core exit codes", (c) "No default repo — explicit configuration required" subsection mirroring the §3 design decision, (d) plugin-internal `scripts/` vs repo-root `scripts/` convention note (per R1.2) | 45–60 min (revised up from 30–45 — adds the TELEMETRY.md authoritative-content sweep that depends on Subtask 3's final command/hook names) | #3 | BLOCKED by #3 |

### Parallelism Graph

```
Batch 1:  [#1]                      (foundation — rubric + schema + privacy spec)
             │
Batch 2:  [#2a]                     (wrapper + exit-code contract + fixtures — locks the contract for #2b)
             │
Batch 3:  [#2b]                     (core — depends on contract from #2a; serial split prevents privacy-fail-closed semantics being bundled with shell plumbing in one review)
             │
Batch 4:  [#3]  [#4]                (PARALLEL — hook/command vs test harness; disjoint files: hooks.json + commands/telemetry.md vs scripts/test-telemetry.sh)
             │     │
             └──┬──┘
                │
Batch 5:  [#5]                      (docs need final hook + command names from #3, AND post-implementation TELEMETRY.md sections)
```

**Recommended max workers:** 2 (Batch 4 has one parallel pair; Batches 1/2a/2b/3/5 are serial).

---

## 7. Skill References per Subtask

| Subtask | Skills |
|---------|--------|
| #1 (design) | `quality-checklist/`, `domain-knowledge/` (for privacy rules), `pattern-detector/` |
| #2a (wrapper + fixtures) | `error-handling/` (always-exits-0 invariant + log-and-continue), `quality-checklist/` |
| #2b (core: privacy + score + dry-run) | `error-handling/` (fail-closed on privacy check + structured exit codes), `quality-checklist/` |
| #3 (hooks + command) | `workflow-management/`, existing `hooks.json` conventions (read-only reference) |
| #4 (test fixtures) | `unit-testing/` (testing approach applies to shell too) |
| #5 (docs incl. TELEMETRY.md post-impl sections) | `claude-md-validation/` (keep version counts consistent), `commit/` |

---

## 8. Risk Assessment

| Risk | Severity | Source | Mitigation |
|------|----------|--------|------------|
| **Scoring rubric ambiguity** — spec shows 0–10 numeric scores but no mapping from enum-based result blocks | **HIGH** | Feasibility (Phase 2.5) | Subtask 1 MUST publish a deterministic mapping table in `docs/TELEMETRY.md` and get Code Reviewer PASS before Subtask 2 starts. Suggested starting point: `PASS → 9`, `completed (heal=PASS) → 8`, `completed_with_escalation → 5`, `NEEDS_HUMAN → 4`, `FAIL/failed → 2`. Adjust per signal (e.g., each `heal_remaining_issue` → −1, each failing test → −0.5). |
| **Architecture translation** — spec's Node `core/telemetry/` module shape does not match plugin (markdown + shell hooks) | MEDIUM | Feasibility (Phase 2.5) | Subtask 1 documents translation in TELEMETRY.md; Plan Reviewer will reject if the design still references Node modules. |
| **Secrets leak in issue body** — a result block could contain a file path or error message with a key | **HIGH** | Security | Hard-coded privacy whitelist lives in **`send-telemetry-core.sh`** (per the wrapper/core split — the wrapper does no payload inspection): allowed fields enumerated explicitly; everything else stripped. Regex deny-list for `sk-…`, `ghp_…`, `api[_-]?key`, `Bearer\s+\w+`, `password\s*[:=]`, `/Users/[a-zA-Z._-]+/`, `/home/[a-zA-Z._-]+/`, email regex, `.env` patterns. Fail-closed (core exits code 2; wrapper still exits 0). Stderr from core is also redacted by the same whitelist before being appended to the log file (defence in depth — see "No leak via stderr" AC at §3 line 65). |
| **Hook failure cascades into agent run** | MEDIUM | Hook architecture | **Resolved structurally** by the wrapper/core split (see §3 ACs and §5): `send-telemetry.sh` (wrapper) ALWAYS exits 0; `send-telemetry-core.sh` may exit non-zero but its exit code and stderr are captured by the wrapper into `.supervisor/logs/telemetry.log` and never propagated to the hook. |
| **Issues posted to wrong repo** (plugin installed in arbitrary user projects) | **HIGH** | External review v2 (default-repo issue) | **Resolved** by removing `origin`-remote fallback. Telemetry is **disabled by default** until user explicitly sets `AI_AGENT_MANAGER_TELEMETRY_REPO` env var or runs `/telemetry enable` (which prompts for repo). Core exits code 4 with single per-session log entry when target unset — no silent posting to the wrong place. |
| **Consent UX runnability** — hook cannot prompt user mid-session | **HIGH** | External review v2 (consent orchestration) | **Resolved** by removing all hook-driven prompting. The hook is now strictly fire-and-forget: when consent is uninitialised, it writes one log line per session telling the user to run `/telemetry enable` (which is the SOLE first-run consent path — driven by the user, executed in the slash-command handler where AskUserQuestion is available). |
| **Issue spam on failing CI / many runs** | MEDIUM | Operational | Interest filter (score < 5 OR non-success) already in AC. Add a soft per-session dedup: hash {task_id + score_bucket + primary_error} — if same hash in last 6 hours in `.supervisor/logs/telemetry-sent.log`, skip. (Include in Subtask 2 or mark as future work in TELEMETRY.md — Subtask 1 decides.) |
| **Target repo confusion** — user uncertain which repo will receive telemetry | LOW | UX | Resolution path is fully covered by the "Issues posted to wrong repo" HIGH row above (no `origin` fallback; explicit configuration required). This row is retained only to track the secondary UX requirement: `/telemetry status` MUST print the resolved target repo and its source (env var vs consent file vs "unset — disabled") so the user can confirm before any send fires. AC "/telemetry status reports resolved target" in §3 covers this. |
| **`gh` auth varies per machine** | LOW | Environment | On first run: script checks `gh auth status`; if not authed, logs skip reason and exits 0 (no error). |
| **SKILLS_INDEX count drift** | LOW | Consistency audit surface | Subtask 5 updates count to 48. The repo's existing consistency audit (triggered via Code Reviewer on skills/ changes — see CLAUDE.md Code Reviewer entry) will catch drift automatically. |
| **Version-bump drift** (CLAUDE.md vs plugin.json) | LOW | Consistency audit surface | Same as above — consistency audit will flag if either file diverges. |

---

## 9. Configuration

| Setting | Location | Default | Purpose |
|---------|----------|---------|---------|
| Consent state | `.supervisor/telemetry-consent.json` (covered by existing `.supervisor/` gitignore — see Risk row 8) | absent (treated as `prompt`) | Stores `always_allow` / `no` / `prompt` and `telemetry_repo` |
| Target repo | env `AI_AGENT_MANAGER_TELEMETRY_REPO` (precedence 1) → consent-file `telemetry_repo` (precedence 2) | **unset → telemetry disabled** (exit code 4 from core, logged once per session) | Where `gh issue create` posts. **No `origin` fallback** — the plugin runs in arbitrary user projects whose `origin` is the user's app repo, not where telemetry should land. |
| First-run UX | none in hook (hooks cannot prompt). User runs `/telemetry enable` (typically from a one-line README install hint) — that command is the SOLE first-run consent path. | — | Resolves the consent-orchestration gap from external review v2 |
| Interest threshold | constant in `send-telemetry-core.sh` | `score < 5 OR status ∈ {failed, FAIL, completed_with_escalation, NEEDS_HUMAN}` | When to send |
| Score bucket boundaries | constant in `send-telemetry-core.sh` + documented in `docs/TELEMETRY.md` | low `< 4`, medium `4–7`, high `≥ 8` (per spec §2) | Label assignment |
| Dedup window | constant | 6 hours | Skip if same {task_id, score_bucket, primary_error} seen recently |
| Dry-run flag | `--dry-run` on `send-telemetry-core.sh` (NOT on the wrapper — wrapper is hook-only) | off | Prints formatted body + target repo + would-be exit code instead of calling `gh`. Used by Subtask 4 tests and by `/telemetry test`. |
| Log paths | hard-coded | `.supervisor/logs/telemetry.log` (full audit incl. exit codes + redacted error excerpts), `.supervisor/logs/telemetry-sent.log` (one line per successful send for dedup), `.supervisor/logs/telemetry-pending-shown-${session_id}.flag` (**per-session** rate-limit marker for "consent not configured" notice — `session_id` is extracted from hook stdin JSON; one file per Claude Code session, opportunistically reaped at >24h age by the wrapper). Fallback: `telemetry-pending-shown-nosession-$(date +%Y%m%d%H).flag` (per-hour bucket) when `session_id` is missing. | Audit trail |
| Core exit codes | spec'd in `docs/TELEMETRY.md` | `0=sent, 1=generic_error, 2=privacy_blocked, 3=no_consent, 4=no_repo_configured, 5=filter_skipped` | Machine-readable outcome for log analysis and `/telemetry status` reporting |

---

## 10. Handoff

```bash
# In a fresh Claude Code session (clean context, to save tokens):
/supervisor job: .supervisor/jobs/pending/2026-04-25-github-issues-telemetry-system.md
```

**Expected outcome:**
- Feature branch e.g. `feature/github-issues-telemetry-system` off `main`
- 6 subtasks (1, 2a, 2b, 3, 4, 5) merged into that feature branch — Batches 1/2/3/5 serial, Batch 4 (#3 ∥ #4) parallel — per the parallelism graph in §6
- One PR opened via `gh pr create`, ready for human sign-off
- Phase 4.5 integration review runs against the full feature-branch diff (mandatory — do not pass `--skip-self-heal`)

---

## 11. Plan Review

### Round 1 — initial Plan Reviewer (2026-04-25)

**Decision:** `PASS` with 3 LOW findings, all folded into the brief.

| # | Severity | Section | Finding | Resolution |
|---|----------|---------|---------|------------|
| R1.1 | LOW | File Impact Map / AC | `.gitignore` already covers `.supervisor/` (line 34) | §5 `.gitignore` row downgraded to LOW + marked "confirmatory only" |
| R1.2 | LOW | File Impact Map (read-only list) | Repo-root `scripts/` vs plugin-scoped `ai-agent-manager-plugin/scripts/` split should be documented | Read-only list explicitly states convention; Subtask 1's TELEMETRY.md must document |
| R1.3 | LOW | Risk Assessment (scoring rubric) | Starter mapping in §8 mixes enums from three result blocks | §3 AC "Scoring rubric documented + deterministic" mandates three separate tables |

### Round 2 — external review (2026-04-25, post-save)

User-supplied review found 4 additional issues that Plan Reviewer missed. Validity-checked, all four valid, all four fixed in this v2 brief.

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| R2.1 | **HIGH** | First-run consent flow had no defined runnable path (`type: command` hook cannot drive an interactive prompt) | Restructured §3 consent ACs: hook is strictly fire-and-forget; `/telemetry enable` is the SOLE first-run consent path. New AC "Consent — uninitialised state" makes the no-prompt behaviour explicit. |
| R2.2 | **HIGH** | Privacy fail-closed (non-zero exit) and hook non-blocking (always exit 0) were mutually contradictory | Wrapper/core split: `send-telemetry.sh` (wrapper, always exits 0) calls `send-telemetry-core.sh` (core, structured exit codes 0–5). Wrapper logs core's exit + stderr; never propagates failure. |
| R2.3 | MEDIUM | Default repo = `origin` was wrong for plugin installs (would post into user app repos) | Removed `origin` fallback. Telemetry **disabled by default** — core exits 4 (`no_repo_configured`) with one-per-session log notice. Env var `AI_AGENT_MANAGER_TELEMETRY_REPO` OR `/telemetry enable` (which prompts) is required. |
| R2.4 | LOW | Header still said `Plan Review Status: _pending_` after PASS | Header updated to `PASS` with re-validation note. |

**Open questions resolved in v2:**
- _Should first-run consent be collected by the main-thread workflow after child-agent completion, or only through explicit user invocation of `/telemetry enable`?_ → **Only through `/telemetry enable`.** Hook-driven prompts are not supported by the harness.
- _Is the telemetry destination intended to be the central plugin repo, or the host project repo?_ → **Neither by default — disabled.** User explicitly sets via env var or `/telemetry enable`. The canonical maintainer repo `vikashruhilgit/ai-agent-manager` is suggested by `/telemetry enable` as the recommended choice but never the silent default.

### Round 3 — Plan Reviewer re-validation of v2 (2026-04-25)

**Decision:** `NEEDS_HUMAN` — 1 HIGH (stale-text inconsistency, mechanical fix), 2 MEDIUM (subtask sizing + missing docs modify-target), 1 LOW (AC overstates what storage allows). All four fixes applied in v3 below.

| # | Severity | Section | Finding | Resolution applied in v3 |
|---|----------|---------|---------|--------------------------|
| R3.1 | HIGH | §8 Risk Assessment | Stale "Target repo confusion" row still said `default is origin remote`, contradicting the resolved row two rows above and §9 | Row rewritten and severity dropped to LOW; now explicitly defers to the resolved "Issues posted to wrong repo" row and tracks only the secondary `/telemetry status` UX requirement |
| R3.2 | MEDIUM | §6 Subtask Structure | Subtask 2 at 60–75 min exceeded the 30–60 min CLAUDE.md ideal | Split into `2a` (wrapper + exit-code contract + fixtures, 30–40 min) and `2b` (core: consent + privacy whitelist + score + dry-run, 45–60 min). 2b depends on 2a's locked exit-code contract. Parallelism graph and worker count updated in §6. |
| R3.3 | MEDIUM | §6 Subtask 5 | `docs/TELEMETRY.md` not in Subtask 5 modify list, but the wrapper/core architecture, full exit-code table, and no-default-repo policy were added AFTER Subtask 1 wrote the initial doc — Subtask 1 cannot author them | Subtask 5 modify list now includes `docs/TELEMETRY.md` with explicit content requirements (wrapper/core architecture, authoritative exit-code table, no-default-repo subsection, plugin-vs-root scripts convention note from R1.2). Time bumped 30–45 → 45–60 min. |
| R3.4 | LOW | §3 AC `/telemetry status reports resolved target` | AC required "count of pending entries" but §9 only specifies a boolean rate-limit flag, not a counter | AC softened: status now reports "whether at least one pending notice was logged this session (boolean from flag)". No behaviour change required. |

### Round 4 — Plan Reviewer re-validation of v3 (2026-04-25)

**Decision:** `PASS` with empty issues array. All four R3 mechanical fixes correctly applied with no regressions on R1 or R2.

**Plan Reviewer Round 4 summary (verbatim):**

> Round 4 re-validation confirms all four R3 mechanical fixes are correctly applied with no regressions. (R3.1) §8 'Target repo confusion' row rewritten to LOW severity, defers cleanly to the resolved 'Issues posted to wrong repo' row above; no surviving 'default is origin remote' assertions anywhere — only explanatory references to why origin is NOT the default. (R3.2) Subtask 2 split into 2a (30–40 min wrapper+fixtures, depends #1) and 2b (45–60 min core, depends #2a); subtasks #3 and #4 correctly rewired to depend on #2b; parallelism graph shows Batch 1=[#1], 2=[#2a], 3=[#2b], 4=[#3,#4] parallel, 5=[#5]; max workers=2 preserved; §7 has separate skill rows for 2a and 2b. (R3.3) Subtask 5 modify list now includes docs/TELEMETRY.md with all four required content additions; time bumped to 45–60 min; zero file overlap with #3 (hooks.json+commands/telemetry.md) or #4 (scripts/test-telemetry.sh); Subtask 1's initial TELEMETRY.md write and Subtask 5's append sections are temporally separated (Batch 1 vs Batch 5) so no contention. (R3.4) §3 /telemetry status AC now reads boolean from .supervisor/logs/telemetry-pending-shown.flag existence; matches §9 storage spec describing the flag as a per-session rate-limit marker; no 'count of pending entries' language survives. All R1 (3 LOW) and R2 (2 HIGH, 1 MEDIUM, 1 LOW) resolutions remain intact. File-path verification confirmed. Brief is ready for /supervisor invocation.

### Round 5 — second external review (2026-04-25, post-R4-PASS)

User-supplied review found three additional consistency issues that R1–R4 missed (one MEDIUM around fake-session-key semantics, two LOW stale-text references after the wrapper/core split and 2a/2b decomposition). All three valid, all three fixed.

| # | Severity | Finding | Resolution applied in v4 |
|---|----------|---------|--------------------------|
| R5.1 | MEDIUM | "Once per session" rate-limit was actually "once until file deleted" — the global `.supervisor/logs/telemetry-pending-shown.flag` had no real session key | Replaced with per-session file `telemetry-pending-shown-${session_id}.flag` where `session_id` is extracted from the hook's stdin JSON (Claude Code provides this). New AC "Session-scoped rate limiting (real session key, not a global flag)" added at §3 line 49. Wrapper opportunistically reaps flags >24h old. Fallback to per-hour bucket if `session_id` missing. §9 "Log paths" row + `/telemetry status` AC updated to match. |
| R5.2 | LOW | §8 "Secrets leak in issue body" risk row still said whitelist lives in `send-telemetry.sh` — contradicted the wrapper/core split where the core owns whitelist | §8 row rewritten: whitelist now correctly attributed to `send-telemetry-core.sh` with explicit cross-reference to "No leak via stderr" AC at §3 line 65 |
| R5.3 | LOW | Two stale summary fields after the 2a/2b split: §4 Feasibility "Scope vs Supervisor" still said "4 subtasks", §10 Handoff still said "5 subtasks merged sequentially" | Both updated to reflect 6 subtasks (1, 2a, 2b, 3, 4, 5) with Batch 4 (#3 ∥ #4) parallel; §10 now references §6 parallelism graph for full breakdown |

### Round 6 — Plan Reviewer re-validation of v4 (2026-04-25)

**Decision:** `PASS` with empty issues array. All three R5 fixes correctly applied with no regressions on R1–R4.

**Plan Reviewer Round 6 summary (verbatim):**

> Round 6 re-validation confirms all three R5 fixes correctly applied with no regressions on R1–R4. (R5.1) Per-session flag naming `telemetry-pending-shown-${session_id}.flag` is consistent across all four locations: §3 line 48 (Consent — uninitialised state references the new AC by name), §3 line 49 (defines the per-session scheme with stdin session_id extraction, opportunistic >24h cleanup, and per-hour fallback), §3 line 76 (/telemetry status counts distinct sessions by globbing `telemetry-pending-shown-*.flag` files), §9 line 215 (Log paths row spells out `${session_id}` interpolation + cleanup + fallback). No surviving mention of a single global `telemetry-pending-shown.flag` in current spec — the only occurrence is inside the verbatim R4 reviewer quote, which is correctly preserved as historical audit trail. (R5.2) §8 'Secrets leak in issue body' row now attributes the whitelist to `send-telemetry-core.sh` explicitly with parenthetical 'per the wrapper/core split — the wrapper does no payload inspection' and cross-references the §3 line 65 'No leak via stderr' AC; no surviving non-core attribution. (R5.3) Subtask count is consistent at 6 (1, 2a, 2b, 3, 4, 5) everywhere it appears: §4 Feasibility, §6 Subtask Structure table, §6 parallelism graph, §6 max workers=2, §10 Handoff. No surviving '4 subtasks' or '5 subtasks' stale references in current spec. All R1–R4 resolutions remain intact. Brief is ready for /supervisor invocation.

### Round 7 — third external review (2026-04-25, post-R6-PASS) — wording polish only

User-supplied review found one LOW wording issue: `/telemetry status` AC implied a durable session count, but the underlying flag files are GC'd after 24h. External reviewer explicitly stated the brief is "launchable as-is" with this as a polish-only fix.

| # | Severity | Finding | Resolution applied in v5 |
|---|----------|---------|--------------------------|
| R7.1 | LOW | `/telemetry status` AC said "count of distinct sessions in which a pending-notice has been logged" but the §3 line 49 reaper deletes flag files >24h, so the count cannot be all-time | AC at §3 line 76 reworded to "count of **retained** pending-notice session markers from approximately the last 24 hours" with explicit "NOT all-time or ever" guard and back-reference to the §3 line 49 reaper. No behavioural change — wording-only alignment. |

**Plan Reviewer NOT re-spawned for R7** — single LOW wording fix below the threshold of design change; external reviewer pre-validated the brief as launchable as-is. Re-validation deferred to Round 8.

### Round 8 — Plan Reviewer re-validation of v5 (2026-04-25, R7.1 confirmation pass)

**Decision:** `PASS` with empty issues array. R7.1 wording polish confirmed internally consistent; no R1–R6 regressions.

**Plan Reviewer Round 8 summary (verbatim):**

> Round 8 re-validation confirms R7.1 wording polish is internally consistent and no R1–R6 regressions were introduced. The §3 line 76 rewording (`/telemetry status` AC: "count of **retained** pending-notice session markers from approximately the last 24 hours" with explicit "NOT all-time or ever" guard and back-reference to the §3 line 49 reaper) now agrees cleanly with §3 line 49 (24h opportunistic flag cleanup) and §9 line 215 (per-session flag with cleanup spec). No surviving "all-time" / "ever" / "durable count" / "count of distinct sessions" language anywhere in the current spec — the only occurrences are the explicit "NOT all-time or ever" guard at line 76 itself, plus the verbatim R6 reviewer quote at line 297 and the R7.1 historical "old wording" record at line 305 (both correctly preserved as audit trail, matching the R5.1 precedent of preserving the original global-flag wording inside the R4 historical quote). All R1–R6 resolutions remain intact: R2.1 (consent: hook fire-and-forget, `/telemetry enable` sole first-run path); R2.2 (wrapper/core split); R2.3 (no origin fallback, disabled by default); R3.2 (six subtasks 1, 2a, 2b, 3, 4, 5); R3.3 (`docs/TELEMETRY.md` in Subtask 5 modify list); R5.1 (per-session flag naming `telemetry-pending-shown-${session_id}.flag`) consistent across §3 lines 48/49/76 and §9 line 215; R5.2 (whitelist attributed to `send-telemetry-core.sh`); R5.3 (subtask count = 6) consistent across §4/§6/§10. File-path verification: hooks.json:88-107 contains exactly the cited WorktreeCreate (88–97) and StopFailure (98–107) `type: command` blocks; plugin.json version is 11.1.2 (bump target 11.2.0 valid); SKILLS_INDEX.md present (47 baseline → 48 valid); CLAUDE.md, .claude-plugin/README.md, README.md, .gitignore (with `.supervisor/` at line 34) all present; RESULT_SCHEMAS.md present. All 11 Plan Review criteria satisfied with empty issues array. The brief is launchable as-is via `/supervisor job: .supervisor/jobs/pending/2026-04-25-github-issues-telemetry-system.md`.

### Final gate status

**PASS (Round 8, empty issues).** Trajectory: PASS (R1, 3 LOW folded) → R2 fixes (4 external findings) → NEEDS_HUMAN (R3, 4 mechanical) → R3 fixes → PASS (R4) → R5 fixes (3 external findings) → PASS (R6, empty issues) → R7 wording polish (1 LOW) → **PASS (R8, empty issues — R7.1 internal consistency + no R1–R6 regressions confirmed)**. Brief is safe to launch via the `/supervisor job:` command in §10.

---

## Outcome

- **Status:** completed
- **Branch:** feature/github-issues-telemetry-system
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/7
- **Commits:** 07d0d4b (initial feature), db99d13 (heal iter 1)
- **heal_loop_ran:** true
- **heal_iterations:** 1
- **heal_decision:** PASS
- **heal_fixable_issues_fixed:** 4 (1 HIGH workflow drift + 3 MEDIUM count drifts)
- **heal_remaining_issues:** 0
- **Tests:** 57/57 passing
- **Validation:** validate-version.sh OK, check-command-sync.sh OK

### Heal iteration 1 summary

Code Reviewer (consistency audit mode) flagged FAIL with 1 HIGH + 3 MEDIUM drift issues:
1. HIGH drift/workflow — interest filter ran before privacy/consent/repo, contradicting docs/TELEMETRY.md "audit trail integrity" invariant.
2. MEDIUM drift/workflow — consent=no with healthy runs logged filter_skipped instead of "denied — skipped" (cascade from #1).
3. MEDIUM drift/count — README.md said "9 commands"; actual 10.
4. MEDIUM drift/count — "10 quality gate hooks" appeared in 6 surfaces; actual 13.

Heal worker fixed by reordering core stage-1 (privacy → consent → repo → format body → final body privacy → interest → dedup → gh), distinguishing "consent_uninitialised" vs "denied — skipped" stderr markers, and updating all 6 count surfaces.

Re-review iteration 2 returned PASS with empty issues. Heal loop terminated at iter 2 (1 fix iteration + 1 verification pass).
