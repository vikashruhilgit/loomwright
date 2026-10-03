# Supervisor Job: Ship the Handoff Digest — a `/handoff` "catch up in 2 minutes" view over the plugin's continuity surfaces

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean working tree, branch: docs/direction-spikes (the 2 SPIKE docs are committed here as 13b23f5; Supervisor should branch a fresh feature branch off `origin/main` — `origin/main` is at `a1cd018`, v14.48.0)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (current branch is an unrelated docs branch; start fresh from origin/main)

## Feasibility (Launch Pad)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash + jq deterministic assembler — identical stack to `build-insights.sh` / `build-vault.sh`. The plugin's native idiom. |
| 2 | Dependency Availability | GO | No new deps. jq already required by existing readers. 8 reusable read-side helpers already exist (`read-project-memory.sh`, `read-lessons.sh`, `read-postmortem.sh`, `read-system-contract.sh`, + `session-resume.sh` logic). Corpus ids `doc-currency-green` + `version-consistent` confirmed. |
| 3 | Architecture Fit | GO | Mirrors `/insights` exactly: command-only wrapper (no SKILL.md — matches `/insights`/`/obsidian`/`/dreaming`) over a deterministic script that writes a gitignored in-repo report. Read-only / fail-safe / always-exit-0 per the plugin invariants. |
| 4 | Scope vs Supervisor Capability | GO | 4 subtasks; engine + test + command + doc-currency. Single feature, clean boundaries. |
| 5 | Hard Blockers | GO | None. `.supervisor/` is wholesale gitignored (`.gitignore:35`), so `.supervisor/handoff/` output needs no gitignore change. |

**Overall Verdict:** GO

## Task
**Goal:** Add a new `/handoff` command + `build-handoff.sh` assembler that produces ONE unified, READ-ONLY "catch up / hand off in 2 minutes" digest — assembled from the continuity surfaces the plugin already generates — presenting, per work item: **decision · why · tried/rejected · current state · provenance**, with a freshness stamp (basis + as-of commit; stale = hint).

**Problem Statement:**
A person resuming this repo (or inheriting it from another operator/session) needs a single 2-minute view of *what was decided, why, what was tried/rejected, and where things stand* — because today that knowledge is **fragmented** across `.supervisor/jobs/`, `.supervisor/autonomous/`, `.supervisor/worker-summaries/`, `.supervisor/state.md`, `.supervisor/logs/*.jsonl`, `.supervisor/memory/`, and `.supervisor/postmortem/`, each readable only through a different lens.
Currently, `/insights` shows run *trends/aggregates* and `/obsidian` projects an *external vault*, but neither produces a recency-focused, per-work-item catch-up view. This causes every session handoff (and every "where was I?" after a break) to re-derive context from scattered artifacts.
Success looks like: `/handoff` prints (and writes to `.supervisor/handoff/digest.md`, gitignored) a mode-agnostic digest that unifies Supervisor / autonomous / automate work into one reviewable summary a second person can inherit without re-litigating.

This is north-star **Bet 2 (the handoff digest)** — "the genuine differentiator; every other framework is amnesiac between sessions." See `ai-agent-manager-plugin/docs/SPIKES/NORTH_STAR_DIRECTION.md`. It also delivers Bet 1's *decision* half (the curated `.supervisor/` decision trail). Surface decision (new command vs extend `/obsidian`): **NEW `/handoff` command**, confirmed by the user — `/obsidian` is external-vault-focused and opt-in (poor fit); a dedicated command is the cleanest intent.

## Acceptance Criteria
- [ ] Given the plugin, when `/handoff` is invoked, then it runs `bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-handoff.sh"`, which assembles ONE digest and writes it to `.supervisor/handoff/digest.md` (gitignored) AND echoes where it wrote (mirroring `/insights`).
- [ ] Given the continuity surfaces, when the digest is built, then it is **mode-agnostic** — ONE unified view across Supervisor (`.supervisor/jobs/{pending,in-progress,done,failed}/*.md`), autonomous (`.supervisor/autonomous/<session_id>/`), and automate (`.supervisor/automate/<run>.md`) work — NOT three separate per-mode digests.
- [ ] Given a work item, when rendered, then the digest shows the five facets where derivable from the artifacts: **decision · why · tried/rejected · current state · provenance** (source artifact path it was drawn from).
- [ ] Given the freshness law (Bet 3 read-side), when a digest line is rendered, then it carries a **basis**, resolved per-surface: (a) **only if the artifact records an actual commit SHA** (e.g. a brief's `Source`/PR **SHA**, a `built_at_commit`-style trailer), compare that SHA to current `HEAD` — match ⇒ fresh; mismatch ⇒ marked a **hint** with both SHAs (`hint — basis <sha>, HEAD <sha>`), stale = emit-with-hint, never silently dropped (mirrors `read-bridge.sh`); (b) **otherwise** (the common case — `session_end` logs carry `branch`/`pr_url` run-context but NO SHA; most jobs/worker-summaries/state.md carry none either) basis = the artifact's **mtime**, freshness = `unknown`, rendered as advisory **without** any SHA comparison. NEVER treat a branch name or PR URL as a commit basis, never resolve a moving branch to stand in for the artifact's basis, and never fabricate or compare a SHA the artifact doesn't carry. mtime and SHA are never conflated in one comparison.
- [ ] Given the existing readers, when `build-handoff.sh` needs verified memory/lessons, then it **reuses** `read-project-memory.sh` and `read-lessons.sh` rather than re-parsing those stores (it is the human-curation layer over the per-mode machine readers — do NOT rebuild them).
- [ ] Given an absent surface (e.g. `.supervisor/automate/` does not exist on this repo today), when the digest is built, then that surface is silently skipped (no fabricated content) and the script still **exits 0** — and with NO continuity surfaces at all it emits a benign "nothing to summarize yet" line and exits 0.
- [ ] **Invariant (read-only / fail-safe):** `build-handoff.sh`'s OWN output is confined to `.supervisor/handoff/`; it never modifies any **source-of-truth** surface (no `.supervisor/jobs/**`, no `*.jsonl` session log, no `state.md`, no `PROJECT_MEMORY.md`/`LESSONS.md`/contracts), sends nothing anywhere, and ALWAYS exits 0 (jq-absent / malformed-artifact / no-data paths all exit 0) — matching `build-insights.sh` (`set -uo pipefail`; jq-guard exit 0). **Sanctioned exception:** the reused `read-*` helpers (AC5) append advisory diagnostics to `.supervisor/logs/{memory,twin}.log` (and `mkdir -p .supervisor/logs/`) as part of THEIR existing always-exit-0 read contract — these are pre-existing, append-only diagnostic logs, NOT new source-of-truth mutations, and are the ONLY filesystem effect outside `.supervisor/handoff/` that the digest may cause.
- [ ] Given the new command, when version surfaces are inspected, then `plugin.json` + `marketplace.json` both equal **14.49.0** (descriptions' vX.Y.Z bumped), the **command count is 20** everywhere it is claimed (was 19), `CLAUDE.md` has a new top banner + updated `plugin.json (vX.Y.Z)` line + File Counts/Plugin Layout updated, `agent-help.md` gains a `/handoff` section, `README.md` command count updated, and `CHANGELOG.md` gains a new top entry. Agents/skills/hooks UNCHANGED (14/56/21).
- [ ] Given the change, when `scripts/validate-version.sh`, `scripts/check-doc-currency.sh`, and `scripts/check-command-sync.sh` run, then all exit 0; and `bash ai-agent-manager-plugin/scripts/test-build-handoff.sh` passes (auto-registered by the `ci.yml` `test-*.sh` glob).

## Outcomes Rubric
- `ai-agent-manager-plugin/scripts/build-handoff.sh` exists and is executable.
- `ai-agent-manager-plugin/scripts/test-build-handoff.sh` exists.
- `ai-agent-manager-plugin/commands/handoff.md` exists.
- `build-handoff.sh` contains `set -uo pipefail` and at least one `exit 0` fail-safe path, and references `.supervisor/handoff` as its only output directory.
- `ai-agent-manager-plugin/.claude-plugin/plugin.json` version is "14.49.0" and `.claude-plugin/marketplace.json` version is "14.49.0".
- `CHANGELOG.md` has a new top entry whose first version token is "v14.49.0".
- No new file is added under `ai-agent-manager-plugin/agents/` or `ai-agent-manager-plugin/skills/` (agent count stays 14, skill count stays 56); the new command brings `ai-agent-manager-plugin/commands/*.md` to 20.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Design notes (verified facts — embedded so workers don't re-derive)

- **Mirror `/insights` precedent:** command-only wrapper `commands/handoff.md` (no SKILL.md — `/insights`/`/obsidian`/`/dreaming` are all command-only); deterministic engine `scripts/build-handoff.sh` writing to `.supervisor/handoff/` (gitignored via the wholesale `.supervisor/` rule). Fail-safe shape: `set -uo pipefail`; `command -v jq … || { …; exit 0; }`; every no-data branch `exit 0`. (Pattern: `scripts/build-insights.sh:15,20,23,30-33,66-67`.)
- **Reusable readers (DO NOT rebuild):** `read-project-memory.sh` (verified PROJECT_MEMORY), `read-lessons.sh` (verified + fresh LESSONS), `read-postmortem.sh` (prior-churn on touched paths — optional), `read-system-contract.sh` (Twin contracts — optional), and the snapshot logic of `session-resume.sh` (in-progress/failed jobs + state.md + recent log entries). The digest CALLS these; it is the curation layer above them.
- **Continuity-surface shapes (on disk today):** jobs = `YYYY-MM-DD-<slug>.md` briefs in 4 lifecycle dirs (done/ + failed/ populated; pending/ holds THIS brief + the handoff one; in-progress/ empty). logs = `<session_id>.jsonl`, canonical event is the last `session_end` line (fields: status, branch, pr_url, heal_decision, heal_iterations, rubric_score, subtasks_completed, files_changed, plugin_version, knowledge_sources_used). worker-summaries = `*.md` (mixed naming). state.md = single file (session_id/task_id/status/phase/branch). autonomous = `auto-YYYY-MM-DD-HHMMSS/` dirs. **automate/ does NOT exist yet** (no runs) → must no-op. postmortem = `results.jsonl` (repo-scoped churn labels).
- **Provenance + freshness (per-surface basis, no commit/mtime conflation):** each digest item names the artifact path it was drawn from. Basis resolution: **commit-bearing artifacts** (only those carrying a real SHA — brief `Source`/PR SHA, `built_at_commit` trailer) → compare recorded SHA to `git rev-parse HEAD`; mismatch → `(hint — basis <sha>, HEAD <sha>)`, never dropped. **Everything else** (`session_end` logs — `branch`/`pr_url` are run-context, NOT a SHA — plus most jobs/worker-summaries/state.md) → basis = mtime, freshness `unknown`, advisory line with NO SHA comparison. Never feed an mtime, branch name, or PR URL into a SHA comparison.
- **Bounded output:** keep it a 2-minute read — cap to the most recent N work items (suggest N≈5–10, configurable later), newest first; summarize, don't dump full briefs.
- **Doc-currency surfaces for the 19→20 command bump** — the **authoritative file list is the complete 9-entry `FILES` array in ST4's detail below** (do NOT treat this bullet as the list). Common count-claim hits to expect (illustrative, NOT exhaustive — grep every file in the 9-entry list): `plugin.json#description` + `marketplace.json#description` (the "19 …" / "Slash commands" phrasings), `CLAUDE.md` (File Counts block, `## Plugin Layout` "19 entry points" line, any "19 commands"), `README.md`, `.claude-plugin/README.md` (counts line "19 slash commands…" + dir-tree "Slash commands (19)"), `commands/agent-help.md` (add a `/handoff` section + any count). doc-currency regexes key on `Slash commands \([0-9]+\)`, `[0-9]+ slash commands`, `[0-9]+ entry points` (`scripts/check-doc-currency.sh:128-130`). `check-command-sync.sh` only guards the code-reviewer thin-wrapper — `handoff.md` is a script wrapper (like insights.md), not an agent thin-wrapper, so it is out of that gate's scope.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `build-handoff.sh` digest assembler (engine) | AC1–AC7 | 0 modify, 1 create | monitoring-observability, error-handling | LAUNCHABLE |
| 2 | `test-build-handoff.sh` fixture-driven self-test | AC9 | 0 modify, 1 create | unit-testing | BLOCKED (by #1) |
| 3 | `commands/handoff.md` command wrapper | AC1, AC7 | 0 modify, 1 create | — | BLOCKED (by #1) |
| 4 | Version bump 14.49.0 + command-count 19→20 doc-currency + agent-help section + CHANGELOG | AC8, AC9 | 7 modify, 0 create | commit | BLOCKED (by #1, #3) |

### Subtask Detail

**Subtask 1 — `ai-agent-manager-plugin/scripts/build-handoff.sh`.** The deterministic assembler. Reads the continuity surfaces (jobs lifecycle dirs, logs `session_end`, worker-summaries, state.md, autonomous dirs, automate dir [no-op absent], memory via `read-project-memory.sh`/`read-lessons.sh`), composes ONE mode-agnostic digest with per-item decision/why/tried-rejected/current-state/provenance + freshness hint, writes `.supervisor/handoff/digest.md` and echoes the path. Fail-safe: `set -uo pipefail`, jq-guard `exit 0`, every no-data branch `exit 0`. Its OWN writes go nowhere but `.supervisor/handoff/`; the only other filesystem effect permitted is the reused `read-*` helpers' own advisory `.supervisor/logs/{memory,twin}.log` diagnostics (sanctioned — see the AC7 exception). Use `${CLAUDE_PLUGIN_ROOT}` for any sibling-script calls. `chmod +x`.

**Subtask 2 — `ai-agent-manager-plugin/scripts/test-build-handoff.sh`.** Fixture-driven (build a temp `.supervisor/` tree, run the script against it). Cover: (a) mode-agnostic assembly across jobs + autonomous fixtures; (b) absent-surface no-op (no `automate/`) still exits 0; (c) no-surfaces-at-all benign line + exit 0; (d) freshness stale → emit-with-hint (artifact basis ≠ HEAD); (e) read-only invariant — assert NO source-of-truth surface is created/modified (no `.supervisor/jobs/**`, no `*.jsonl` log, no `state.md`, no `memory/*.md`, no contracts); the only writes allowed are under `.supervisor/handoff/` plus the sanctioned `read-*` diagnostic logs `.supervisor/logs/{memory,twin}.log` (assert the test tolerates those, does not forbid them); (f) reuse path — verify it invokes the existing readers rather than re-parsing; (g) freshness — a commit-bearing fixture whose SHA ≠ HEAD renders a `hint` with SHAs, while a commit-less fixture renders `unknown` with NO SHA comparison. Exit non-zero on any failure (so CI catches it). Mirror an existing `test-build-*.sh` harness.

**Subtask 3 — `ai-agent-manager-plugin/commands/handoff.md`.** Thin command doc modeled on `commands/insights.md`: frontmatter `description:`; a read-only/fail-safe banner; Purpose; Usage (`/handoff`); "What it does" (runs `bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-handoff.sh"`, reads which surfaces, writes `.supervisor/handoff/digest.md`); note it's distinct from `/insights` (trends) and `/obsidian` (external vault). Do NOT embed engine logic in the command.

**Subtask 4 — version + doc-currency.** Bump `plugin.json` 14.48.0 → **14.49.0** + its description vX.Y.Z and the command count 19 → 20 (skills/agents/hooks stay 56/14/21). Same for `marketplace.json` (version must equal plugin.json — `validate-version.sh`). Update `CLAUDE.md`: new v14.49.0 banner (keep only the two most recent — remove the v14.47.0 banner, which is already in CHANGELOG, retaining v14.48.0 + v14.49.0), `plugin.json (vX.Y.Z)` line, File Counts, `## Plugin Layout` "19 entry points"→20. Update `README.md` command count. **Update `.claude-plugin/README.md`** — it is in the doc-currency `FILES` scan list and carries TWO "19" command claims: the counts line `**19 slash commands, 56 skills, 21 hooks**` (≈line 9) AND the dir-tree comment `# Slash commands (19)` (≈line 408); update BOTH to 20 (verify by grep, don't trust the line numbers). Add a `/handoff` section to `commands/agent-help.md` (and its command count if present). Add a CHANGELOG.md top entry. RUN `bash scripts/validate-version.sh && bash scripts/check-doc-currency.sh && bash scripts/check-command-sync.sh` and fix any drift before marking done.

**Full doc-currency scan surface — the COMPLETE 9-entry `FILES` array from `scripts/check-doc-currency.sh` (verified, the authoritative list ST4 must sweep):** `CLAUDE.md`, `README.md`, `AGENT_GUIDELINES.md`, `.claude-plugin/README.md`, `.claude-plugin/marketplace.json`, `ai-agent-manager-plugin/.claude-plugin/plugin.json`, `ai-agent-manager-plugin/commands/agent-help.md`, `ai-agent-manager-plugin/docs/ARCHITECTURE.md`, `ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md`. The worker MUST grep ALL nine for a stale command count (`19`/`Slash commands (19)`/`19 slash commands`/`19 entry points`) and update every hit to 20, even the two `docs/ARCHITECTURE*.md` files where a count claim may not currently exist (grep to confirm; the gate will fail if any is missed). `.github/workflows/*.yml` is deliberately NOT scanned (see the comment in check-doc-currency.sh). CHANGELOG.md is NOT scanned but gets a conventional new entry.

### Provides / Requires Schema

```yaml
# Subtask 1 — engine (LAUNCHABLE)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/build-handoff.sh"}
requires: []
external_requires:
  - "jq (already a plugin-wide runtime dependency)"
```

```yaml
# Subtask 2 — self-test (BLOCKED by #1)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/test-build-handoff.sh"}
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/scripts/build-handoff.sh"}
external_requires: []
```

```yaml
# Subtask 3 — command wrapper (BLOCKED by #1)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/commands/handoff.md"}
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/scripts/build-handoff.sh"}
external_requires: []
```

```yaml
# Subtask 4 — version + doc-currency (BLOCKED by #1, #3)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "version"}
  - {kind: "symbol", path: ".claude-plugin/marketplace.json", name: "version"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "v14.49.0"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/agent-help.md", name: "/handoff"}
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/scripts/build-handoff.sh"}
  - {from: "3", kind: "file", path: "ai-agent-manager-plugin/commands/handoff.md"}
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──┬──→ Subtask 2
            └──→ Subtask 3 ──→ Subtask 4
                 (Subtask 4 also requires Subtask 1)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| ST1 (build-handoff.sh) | ST2 (test-build-handoff.sh) | none | content dep only — ST2 tests ST1 |
| ST2 (test script) | ST3 (handoff.md) | none | No — run in parallel after ST1 |
| ST3 (handoff.md) | ST4 (plugin.json, marketplace.json, CLAUDE.md, README.md, agent-help.md, CHANGELOG.md) | none | Yes — ST4 needs the command to exist for count=20 + banner |

- **Batches:** B1 = {ST1}; B2 = {ST2, ST3} (parallel); B3 = {ST4}. Three batches.
- **Recommended workers:** 2 (B2 runs two independent subtasks concurrently).

## Skill References
- `monitoring-observability`, `error-handling` — fail-safe shell assembler discipline (ST1)
- `unit-testing` — fixture-driven self-test (ST2)
- `commit` — conventional commit + version-bump discipline (ST4)

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Digest re-parses stores the existing readers already own (rebuilds machine readers) | MEDIUM | AC5 mandates reuse of `read-project-memory.sh`/`read-lessons.sh`; ST2 test (f) asserts the readers are invoked; brief explicitly frames the digest as the curation layer ABOVE the readers |
| Stale/scope leakage — postmortem `results.jsonl` contains multi-repo churn lines | MEDIUM | If ST1 consults postmortem, it MUST go through `read-postmortem.sh` (already repo-scoped on `owner/repo`); do not raw-parse `results.jsonl` |
| Fail-safe regression — a malformed artifact throws under `set -u`/`pipefail` and breaks `exit 0` | MEDIUM | Mirror `build-insights.sh` guards exactly; ST2 test (b)+(c) feed absent/empty/malformed surfaces and assert exit 0; this is the bimodal "side-effect emitter fails SAFE" invariant |
| Command-count drift across the doc surface (19→20 missed somewhere) | LOW | ST4 enumerates every surface + runs all three gate scripts; `## Executable Acceptance` re-asserts doc-currency + version at Phase 4.5 |
| `.supervisor/automate/` absent today → untested mode path | LOW | ST2 fixture includes an automate dir to exercise that branch even though the live repo lacks one; AC6 covers absent-surface no-op |
| Over-scoping into trend/aggregate territory (overlaps `/insights`) | LOW | Keep `/handoff` recency + per-item only; bounded to newest N items; trends stay in `/insights` |
| Current branch is an unrelated docs branch | LOW | Supervisor branches a fresh feature branch off origin/main |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 3
- **Base Branch:** main
- **Self-heal:** default ON (Phase 4.5) — new script + command + doc surface; consistency_audit + corpus-task ground-truth are the right gates.
- **Heal iterations:** default (3)
- **Cost profile:** default (inherit)
- **Beads:** not required (Supervisor/Launch Pad path)

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-06-28-handoff-digest.md

## Outcome
- **Status:** completed
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 0 (review clean on first pass — no fixable BLOCKING/HIGH new issues)
- **heal_remaining_issues:** 0
- **rubric_score:** 7/7
- **contract_conformance:** PASS (corpus-tasks doc-currency-green + version-consistent both green)
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/82
- **Branch:** feature/handoff-digest (base main, head f3b381f)
- **Gates:** validate-version, check-doc-currency, check-command-sync, test-build-handoff — all exit 0
- **Completed:** 2026-06-28
