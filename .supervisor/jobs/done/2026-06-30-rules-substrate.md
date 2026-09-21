# Supervisor Job: Ship the house-rules substrate — `.agent/rules/` + `read-rules.sh` + `/rules` command (north-star slice #3b-i)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean working tree, branch: main @ v14.50.0 (slice #3a `/setup twin` merged as PR #83). Supervisor branches a fresh feature branch off `origin/main`.
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0

## Feasibility (Launch Pad)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash + jq reader + a markdown command/skill — the plugin's native idiom. JSON rules store (jq-only; the repo has no `yq` dependency). |
| 2 | Dependency Availability | GO | No new deps. Mirrors the `read-bridge.sh`/`read-lessons.sh` fail-safe reader pattern + the `/automate`→`automate-loop` command+skill pattern. Corpus ids `doc-currency-green` + `version-consistent` confirmed. |
| 3 | Architecture Fit | GO | Advisory / fail-safe / no-op-when-absent (mirrors `brain-context`). The rules dir is COMMITTED (`.agent/rules/`, not gitignored) so rules travel with the repo — distinct from gitignored `.supervisor/`. |
| 4 | Scope vs Supervisor Capability | GO | 5 subtasks (schema+skill · reader · reader-test · command · version/doc). Bounded — this is the SUBSTRATE only; enforcement + close-the-loop + nudge are slice #3b-ii. |
| 5 | Hard Blockers | GO | None. The one real hazard (arbitrary `check` shell) is contained: the reader never executes; `/rules check` executes only human-invoked + confirmed. |

**Overall Verdict:** GO

## Task
**Goal:** Establish the committed house-rules substrate — a `.agent/rules/` JSON rule store with a documented schema, a fail-safe `read-rules.sh` reader (emits applicable rules, never executes them), and a new `/rules` command (`list` · `suggest` (scan-to-suggest) · `check` (human-invoked) · `add`) governed by a `rules` protocol skill — WITHOUT any enforcement wiring.

**Problem Statement:**
The plugin needs a single, committed source of truth for project conventions because today conventions are enforced almost entirely on the REVIEW side (`code-reviewer`, `frontend-ui`) and are optional/vague on the DO side (`worker`: "(optional) key patterns from CLAUDE.md") — so an implementer drifts and only (maybe) gets caught at review = churn (north-star Bet 6, grounded audit).
Currently there is no rules store, no reader, and no authoring command. This slice ships only the *substrate* — the store + reader + `/rules` — so a later slice can wire enforcement at the three seams. Success looks like: a repo can author `.agent/rules/*.json`, `/rules list` shows them, `/rules suggest` proposes rules from a repo scan (human-confirmed), and `read-rules.sh` emits applicable rules as advisory context that no-ops cleanly when absent.

This is north-star **slice #3b-i** (the foundational half of Bet 6). See `ai-agent-manager-plugin/docs/SPIKES/NORTH_STAR_DIRECTION.md` §"6. House rules". Follows #3a (`/setup twin`, PR #83). Division per the doc: **`/setup twin` bootstraps; `/rules` maintains.**

## Acceptance Criteria
- [ ] Given the committed rules store, when defined, then `.agent/rules/` is a VERSION-CONTROLLED dir (NOT added to `.gitignore` — unlike `.supervisor/`), holding zero-or-more `*.json` files each an array of rule objects with schema `{id, category, statement, enforcement: "advisory"|"must", check: <runnable shell string or null>, provenance: {source, added, ...}}`, documented in `.agent/rules/README.md` (schema + one example) + the `rules` skill. This plugin's own repo ships the README/schema but NO populated live rules (authoring is opt-in via `/rules`).
- [ ] Given `read-rules.sh`, when run, then it globs+merges `.agent/rules/*.json`, validates each is a rule array (jq-only — untrusted rule text crosses the boundary via `--rawfile`/`--argjson`/`--arg`, NEVER string-interpolated into a shell command or jq program), and emits an advisory markdown block ("## Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)") listing applicable rules with `must` flagged — mirroring `read-bridge.sh`/`read-lessons.sh`.
- [ ] **"Applicable" is defined for v1 (no guessing):** v1 emits **ALL valid rules** — there is NO path/scope filtering yet. The schema includes an OPTIONAL `applies_to` field (path-glob / language / category) **RESERVED for 3b-ii enforcement filtering and NOT consulted by the v1 reader** (documented as forward-compat). Input contract (mirror `read-postmortem.sh`'s no-hang rule): `read-rules.sh` accepts OPTIONAL positional args (currently informational/forward-compat, do not change v1 output), and **NEVER blocks on stdin** in a non-TTY context (args take precedence; if no args and stdin is not a TTY, do not read stdin) — so a future hook/agent caller cannot hang it.
- [ ] **Rule-object validation (per object, fail-safe-skip):** each object must have `id` (string, unique across the merged set), `category` (string), `statement` (string), `enforcement` ∈ {`advisory`,`must`}, `check` (string OR null), `provenance` (object). An object that is malformed, missing a required field, carries an unknown `enforcement` value, or duplicates an already-seen `id` is **SKIPPED** (not emitted) with a one-line diagnostic to `.supervisor/logs/` — the reader NEVER crashes and STILL exits 0 and emits the remaining valid rules. **Deterministic merge order (so "first-seen `id` wins" is reproducible):** process the `*.json` files in `LC_ALL=C` repo-relative-path-sorted order, each file's array by index; the first valid occurrence of an `id` wins and later duplicates skip.
- [ ] **Invariant (the reader NEVER executes a rule's `check`):** `read-rules.sh` emits each rule's `check` field as DATA (text) only and NEVER runs it, so the future unattended enforcement seams can call the reader with zero code-execution risk. The reader is `set -uo pipefail` (NO `-e`), ALWAYS exits 0 (absent dir / empty / malformed json / jq-unavailable all → emit-nothing, exit 0), is READ-ONLY (writes nothing except optional stderr/`.supervisor/logs/` diagnostics), and emits EMPTY (no banner) when no rule applies so machine consumers can gate on non-empty stdout.
- [ ] Given `/rules` (new top-level command), when invoked, then it supports `list` (calls `read-rules.sh`), `suggest` (scan-to-suggest — analyzes the repo via grep/glob + `brain-context` graph-if-present, PROPOSES rules, never blank-slate-asks, never auto-writes), `add`/author (see write semantics below), and `check` (see execution + trust boundary below). The command is a thin wrapper; the `rules` skill is the protocol authority.
- [ ] **`/rules add` write semantics (exact):** the target filename is a **slugified category** (lowercase `[a-z0-9-]`); the command MUST reject/sanitize any `category` containing `/`, `..`, a leading dot, shell metacharacters, or empty — so the write can **NEVER escape `.agent/rules/`** (path containment). It appends to `.agent/rules/<category-slug>.json` (creating the file as a single-element array if absent). Discipline mirrors the setup settings-merge: **parse-gate** the existing target (`jq -e 'type=="array"'` — abort, never clobber, on malformed JSON OR valid-but-non-array JSON, since rule files MUST be arrays) → assign a **deterministic unique `id`** = `<category-slug>-<statement-slug>` (numeric `-N` suffix on collision, checked across the merged set) → set **`provenance.source = "/rules add"`** (or the user-provided source) and **`provenance.added = <UTC ISO-8601>`** → `jq` append → write via **temp-file + atomic `mv`** → **verify** the appended rule reads back. Writes ONLY on explicit user confirmation (never blind-write); never edits/removes an existing rule in this slice (append-only).
- [ ] **`/rules check` execution semantics:** runs ONLY `must` rules whose `check` is non-null; each command runs from the **repo root** via `bash -c`; **every command is displayed before running and executes only after explicit confirmation**; under non-interactive / no-confirm it does **NOT run** any check (reports "skipped — needs confirmation"); it reports an **aggregate pass/fail** summary; and it is **NOT an unattended gate** in this slice (human-invoked only — unattended seam execution is 3b-ii, gated).
- [ ] **Trust boundary (the `check` field is arbitrary shell):** `/rules check` is HUMAN-invoked only (trust anchor = the user running it); it DISPLAYS each `must`-rule's `check` command and runs it only after explicit confirmation (never blind-executes a check authored by a cloning teammate). The reader does not execute checks at all. **Unattended execution of `check` commands (worker / Phase 4.5 seams) is explicitly DEFERRED to slice #3b-ii and MUST be gated there** (mirror `run-ground-truth.sh --no-cmd`'s machine-authored trust valve) — flag this in the `rules` skill so 3b-ii inherits the requirement.
- [ ] Given the new command + skill, when registered, then a `rules` skill exists (protocol authority: schema, the scan-to-suggest spec, the advisory/must/no-op-when-absent contract, the `check` trust boundary, and a "layering DEFERRED" note), `SKILLS_INDEX.md` gains a `rules` row, and `commands/agent-help.md` gains a `/rules` section (usage + what-it-does + examples, mirroring the `/handoff` section).
- [ ] Given the new command + skill, when counts are inspected, then commands go **20→21** and skills go **56→57** everywhere claimed — the 9 doc-currency `FILES` surfaces PLUS the **gate-blind** `skills/SKILLS_INDEX.md` `**Total: 56 skills**` line (not in the 9-file scan, must be hand-updated); agents stay 14, hooks stay 21; `plugin.json` + `marketplace.json` bump to **14.51.0** (equal) with the `vX.Y.Z` + the two counts updated in their `description`; `CLAUDE.md` gets a new banner + version line; `CHANGELOG.md` a new entry.
- [ ] Given the change, when `scripts/validate-version.sh`, `scripts/check-doc-currency.sh`, and `scripts/check-command-sync.sh` run, then all exit 0; and the new self-tests `test-read-rules.sh` + `test-rules-docs.sh` pass (both auto-registered by the `ci.yml` `test-*.sh` glob).

## Outcomes Rubric
- `.agent/rules/README.md` exists (committed, not gitignored) and documents the rule schema `{id, category, statement, enforcement, check, provenance}` with one example.
- `ai-agent-manager-plugin/scripts/read-rules.sh` (executable) + `ai-agent-manager-plugin/scripts/test-read-rules.sh` both exist.
- `read-rules.sh` contains `set -uo pipefail`, an `exit 0` fail-safe path, globs `.agent/rules/*.json`, contains NO line that executes a rule's `check` field (emitted as data only), and skips invalid rule objects (missing required field / unknown `enforcement` / duplicate `id`) without crashing; `test-read-rules.sh` covers the non-execution touch-marker, the skip cases, and deterministic ordering.
- `ai-agent-manager-plugin/skills/rules/SKILL.md` exists and documents the schema+validation, the v1 "applicable=all" + input contract, scan-to-suggest, the advisory/must/no-op contract, the `/rules add` write discipline, the `check` trust boundary, and the layering-deferred note.
- `ai-agent-manager-plugin/commands/rules.md` exists, cites the `rules` skill, and specifies `list` / `suggest` / `add` (array-only parse-gate `jq -e 'type=="array"'` + deterministic-id + `provenance.source`/`provenance.added` stamping + temp-file atomic-`mv` append, confirm-only) / `check` (confirmed must-rule checks only, never an unattended gate).
- `plugin.json` + `marketplace.json` version are both "14.51.0"; `CHANGELOG.md` has a new top entry beginning "v14.51.0"; command-count claims read 21 and skill-count claims read 57 across the doc surface (including the gate-blind `SKILLS_INDEX.md` `Total: 57 skills` line); `README.md` + `.claude-plugin/README.md` command listings include `/rules`.
- No new agent or hook (agents stay 14, `hooks/hooks.json` unchanged); `.agent/rules/` is NOT present in `.gitignore`.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Design notes (verified facts — embedded so workers don't re-derive)

- **Fail-safe reader idiom (mirror `read-bridge.sh`/`read-lessons.sh` verbatim):** `set -uo pipefail` (NO `-e` — "a read must never break its caller"); ALWAYS `exit 0`; jq-unavailable → emit nothing + exit 0; missing/empty/malformed store → silent no-op exit 0; advisory banner "subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)"; jq-only parsing (untrusted text via `--rawfile`/`--argjson`/`--arg`, never interpolated); diagnostics to `.supervisor/logs/`, never stdout; EMPTY (no banner) on no-applicable-rule so consumers gate on non-empty. (`read-bridge.sh:60-70,119-149,271,284`; `read-lessons.sh:20-39,78`.)
- **Command+skill precedent:** protocol-heavy commands pair with a skill (`/automate`→`automate-loop`, `/pr-postmortem`→`pr-postmortem`, `/setup`→`setup`, `/telemetry`→`telemetry`); thin shells don't (`/insights`,`/handoff`,`/obsidian`). `/rules` carries real protocol (scan-to-suggest, schema, trust boundary) → pair it with a `rules` skill (authority); the command stays thin.
- **`check` = arbitrary shell → trust model:** the reader emits `check` as data and never runs it (safe for unattended callers); `/rules check` runs checks ONLY human-invoked + confirmed; unattended seam execution is 3b-ii's problem and must be gated (`run-ground-truth.sh --no-cmd` precedent). This is the same trust boundary Plan Reviewer Criterion 14 enforces for `cmd:` Executable-Acceptance bullets.
- **`.agent/` is the FIRST committed-convention surface** — only referenced in `NORTH_STAR_DIRECTION.md:104-105,149` today; `.agent/` is NOT in `.gitignore` (must stay out — rules are committed). Do NOT add it to `.gitignore`.
- **Scanner for `suggest`:** grep/glob/read (always) + `brain-context` (graph-if-present, staleness-aware, degrades to grep) + `claude-md-validation` patterns. Propose-only, human-confirmed (mirror `/setup twin`). Never blocks, never auto-writes.
- **Doc-currency = the COMPLETE 9-entry `FILES` array** (`scripts/check-doc-currency.sh`): `CLAUDE.md`, `README.md`, `AGENT_GUIDELINES.md`, `.claude-plugin/README.md`, `.claude-plugin/marketplace.json`, `ai-agent-manager-plugin/.claude-plugin/plugin.json`, `ai-agent-manager-plugin/commands/agent-help.md`, `ai-agent-manager-plugin/docs/ARCHITECTURE.md`, `ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md`. Command-count regexes: `Slash commands \([0-9]+\)` / `[0-9]+ slash commands` / `[0-9]+ entry points`; skill-count regexes: `[0-9]+ reusable skills` / `[0-9]+ focused skill` / `and [0-9]+ skills` (`check-doc-currency.sh:128-135`). Grep ALL nine files for both a stale `20` (commands) and a stale `56` (skills) and bump every hit. `plugin.json#description` + `marketplace.json#description` carry both "20 slash commands" and "56 reusable skills".
- **No staleness/SHA logic needed** — committed rules are current by definition; provenance carries a timestamp but the reader does NO `built_at_commit`/HEAD comparison (avoids the prefix-tolerant-compare trap entirely).

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `rules` skill (schema + scan-to-suggest spec + contracts + trust boundary) + `.agent/rules/README.md` | rules-store schema + skill-authority criteria | 0 modify, 2 create | — | LAUNCHABLE |
| 2 | `read-rules.sh` fail-safe reader (emits rules, never executes `check`) | reader emit/fail-safe/never-execute criteria | 0 modify, 1 create | monitoring-observability, error-handling | BLOCKED (by #1) |
| 3 | `test-read-rules.sh` fixture self-test | the self-test / CI-gate criterion | 0 modify, 1 create | unit-testing | BLOCKED (by #2) |
| 4 | `/rules` command (list/suggest/check/add) + `test-rules-docs.sh` + SKILLS_INDEX row+total + agent-help section | command + trust-boundary + registration criteria | 2 modify, 2 create | — | BLOCKED (by #1, #2) |
| 5 | Version 14.51.0 + doc-currency (commands 20→21, skills 56→57) + CHANGELOG + gate scripts | counts/version + gates-green criteria | ~7 modify, 0 create | commit | BLOCKED (by #1, #4) |

### Subtask Detail

**Subtask 1 — `rules` skill + rules-store schema.** Create `ai-agent-manager-plugin/skills/rules/SKILL.md` (protocol authority: the full rule schema `{id, category, statement, enforcement: advisory|must, check, provenance, applies_to?}` incl. the per-object required-fields/types/enum/uniqueness validation rules + the optional `applies_to` reserved-for-3b-ii field; the v1 "applicable = all valid rules" definition + reader input contract; the scan-to-suggest spec — propose-only, human-confirmed, grep/brain-context scanner; the advisory/must/no-op-when-absent read contract; the `/rules add` append-with-parse-gate/atomic-mv write discipline; the `/rules check` human-invoked+confirmed execution semantics; the `check`-is-arbitrary-shell trust boundary incl. the 3b-ii unattended-gating requirement; a "company-base↔per-project layering DEFERRED" note) with version frontmatter. **Create the parent dir `.agent/rules/` and commit ONLY `.agent/rules/README.md`** (schema + ONE example rule) — do NOT populate live rules, do NOT add `.agent/` to `.gitignore`. (Plan Reviewer note: `.agent/` does not exist today; ST1 creates it.)

**Subtask 2 — `read-rules.sh`.** Fail-safe reader mirroring `read-bridge.sh`: globs+merges `.agent/rules/*.json` (jq-only, `--argjson`/`--arg`/`--rawfile` — never interpolate); performs the per-object validation (skip-with-diagnostic on malformed/missing-field/unknown-`enforcement`/duplicate-`id` — never crash) over files merged in `LC_ALL=C` path-sorted order (first-seen `id` wins); v1 emits ALL valid rules (no `applies_to` filtering); accepts optional positional args (forward-compat, no v1 effect) and never blocks on stdin in non-TTY; emits the advisory banner + rules (`must` flagged, `check` shown as DATA, **deterministic ordering** e.g. by category then id), EMPTY on no-valid-rule, `set -uo pipefail`, ALWAYS exit 0 on absent/empty/malformed/jq-missing. **Contains NO code path that executes a `check` value.** `chmod +x`. `${CLAUDE_PLUGIN_ROOT}` for any sibling calls.

**Subtask 3 — `test-read-rules.sh`.** Static fixture-driven. Cover: (a) absent `.agent/rules/` → no output, exit 0; (b) populated fixture → advisory banner + rules emitted, `must` flagged; (c) malformed `*.json` → fail-safe (no crash, exit 0); (d) jq-absent simulation → emit nothing, exit 0; (e) **`check` field is emitted as text but NOT executed** — fixture rule whose `check` is e.g. `touch /tmp/PWNED_<marker>`; assert the marker file is NOT created (proves the reader never runs it); (f) empty/no-valid → EMPTY stdout (no banner); (g) **object validation** — fixtures with a missing-required-field rule, an unknown `enforcement` value, and a duplicate `id` each get SKIPPED while sibling valid rules still emit (exit 0); (h) **deterministic ordering** — a multi-rule fixture emits in a stable order across runs. Non-zero exit on any failure. (ST3 tests ONLY `read-rules.sh` — it depends solely on ST2; the static command/skill doc-assertions live in ST4's `test-rules-docs.sh`, since `commands/rules.md` is created by ST4.)

**Subtask 4 — `/rules` command.** Create `ai-agent-manager-plugin/commands/rules.md` (thin; cites the `rules` skill as authority): `list` (invoke `read-rules.sh`), `suggest` (scan-to-suggest, propose-only, confirmed-write), `add` (append to `.agent/rules/<category>.json` with the parse-gate → unique-id → temp+atomic-`mv` → verify discipline, confirm-only, append-only — per the AC; **the target filename is a SLUGIFIED category** — lowercase, `[a-z0-9-]` only — and the command MUST reject/sanitize any `category` containing `/`, `..`, a leading dot, shell metacharacters, or empty, so the write can NEVER escape `.agent/rules/`; **the generated `id` is deterministic** = `<category-slug>-<statement-slug>` with a numeric `-N` suffix on collision), `check` (HUMAN-invoked; runs only `must` rules with non-null `check`, from repo root via `bash -c`, displays each command and runs only on confirm, no-confirm/non-interactive → skip, reports aggregate pass/fail; never an unattended gate — per the AC). Add a `rules` row to `skills/SKILLS_INDEX.md` **AND bump its `**Total: 56 skills**` line → `57` + refresh its last-updated/header** — `SKILLS_INDEX.md` is NOT in `check-doc-currency.sh`'s 9-file scan, so this total is **gate-blind** and must be updated by hand here (all `SKILLS_INDEX.md` edits stay in ST4 to avoid an ST4/ST5 race). Add a `/rules` section to `commands/agent-help.md`. **Also create `scripts/test-rules-docs.sh`** (static, auto-registered by the `test-*.sh` glob): assert `commands/rules.md` + `skills/rules/SKILL.md` contain the trust-boundary phrases (reader-never-executes, `/rules check` requires-confirmation, unattended-execution-deferred) AND document the category path-containment/slugging rule, the deterministic-id format, the **array-only parse gate (`jq -e 'type=="array"'`)**, and the **`provenance.source` + `provenance.added` stamping** of `/rules add`.

**Subtask 5 — version + doc-currency + command listings.** Bump `plugin.json` 14.50.0 → **14.51.0** + its `description` (`vX.Y.Z`, "20 slash commands"→21, "56 reusable skills"→57). Same for `marketplace.json` (version must equal — `validate-version.sh`). Update `CLAUDE.md` (new v14.51.0 banner keeping only the two most recent; `plugin.json (vX.Y.Z)` line; File Counts), and grep ALL nine doc-currency `FILES` for a stale `20`/`56` and bump (incl. `.claude-plugin/README.md`, `docs/ARCHITECTURE.md`, `docs/ARCHITECTURE_CONTRACTS.md`). **Also update the COMMAND LISTINGS (not just the counts) in `README.md` and `.claude-plugin/README.md`** to include `/rules` — `check-command-sync.sh` only guards `code-reviewer.md`, so a missing `/rules` mention in these listings is NOT caught by any gate (grep each for the existing command list / dir-tree and add `/rules`). Add a `CHANGELOG.md` top entry. RUN `bash scripts/validate-version.sh && bash scripts/check-doc-currency.sh && bash scripts/check-command-sync.sh`; fix any drift before done.

### Provides / Requires Schema

```yaml
# Subtask 1 — skill + schema (LAUNCHABLE)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/skills/rules/SKILL.md"}
  - {kind: "file", path: ".agent/rules/README.md"}
requires: []
external_requires: []
```

```yaml
# Subtask 2 — reader (BLOCKED by #1)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/read-rules.sh"}
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/skills/rules/SKILL.md"}
external_requires: []
```

```yaml
# Subtask 3 — reader test (BLOCKED by #2)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/test-read-rules.sh"}
requires:
  - {from: "2", kind: "file", path: "ai-agent-manager-plugin/scripts/read-rules.sh"}
external_requires: []
```

```yaml
# Subtask 4 — command (BLOCKED by #1, #2)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/commands/rules.md"}
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/test-rules-docs.sh"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/SKILLS_INDEX.md", name: "rules"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/SKILLS_INDEX.md", name: "Total: 57 skills"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/agent-help.md", name: "/rules"}
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/skills/rules/SKILL.md"}
  - {from: "2", kind: "file", path: "ai-agent-manager-plugin/scripts/read-rules.sh"}
external_requires: []
```

```yaml
# Subtask 5 — version + doc (BLOCKED by #1, #4)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "version"}
  - {kind: "symbol", path: ".claude-plugin/marketplace.json", name: "version"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "v14.51.0"}
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/skills/rules/SKILL.md"}
  - {from: "4", kind: "file", path: "ai-agent-manager-plugin/commands/rules.md"}
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──┬──→ Subtask 3
                          └──→ Subtask 4 ──→ Subtask 5
                               (Subtask 5 also requires Subtask 1)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| ST1 (rules skill + .agent/rules/README.md) | ST2 (read-rules.sh) | none | Yes — reader implements the ST1 schema |
| ST3 (test-read-rules.sh — reader test only) | ST4 (rules.md + test-rules-docs.sh + SKILLS_INDEX + agent-help) | none | No — parallel after ST2 (ST3 no longer touches the command/skill docs; those static assertions moved to ST4's test-rules-docs.sh) |
| ST4 | ST5 (plugin.json, marketplace.json, CLAUDE.md, README, agent-help, ARCHITECTURE*, CHANGELOG) | `agent-help.md` (ST4 adds the section; ST5 bumps its counts) | Yes — ST5 after ST4 (avoids the shared agent-help.md edit racing) |

- **Batches:** B1 = {ST1}; B2 = {ST2}; B3 = {ST3, ST4} (parallel); B4 = {ST5}. Four batches.
- **Recommended workers:** 2.

## Skill References
- `monitoring-observability`, `error-handling` — fail-safe shell reader (ST2)
- `unit-testing` — fixture self-test (ST3)
- `commit` — conventional commit + version-bump discipline (ST5)
- (consumed at runtime by `/rules`, not by workers: `brain-context`, `claude-md-validation`)

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| A rule's `check` (arbitrary shell) gets executed by the reader or an unattended path → code-execution from a committed file authored by anyone who cloned/PR'd the repo | HIGH | AC + invariant: `read-rules.sh` NEVER executes `check` (emits as data); ST3 test (e) proves it with a `touch`-marker fixture; `/rules check` is human-invoked + confirmed; unattended seam execution DEFERRED to 3b-ii with a flagged gating requirement. |
| `.agent/rules/` accidentally gitignored (rules then don't travel with the repo — defeats the whole point) | MEDIUM | AC + ST1 + rubric assert `.agent/` is NOT in `.gitignore`; the dir is committed. |
| Doc-currency drift — TWO count bumps (commands 20→21 AND skills 56→57) across 9 files; easy to miss one | MEDIUM | ST5 enumerates the full 9-file `FILES` list + both regex families; `## Executable Acceptance` `doc-currency-green` re-asserts at Phase 4.5; run all gate scripts before done. |
| `SKILLS_INDEX.md` `**Total: 56 skills**` is gate-BLIND (not in the 9-file doc-currency scan) → stale 56 ships silently | MEDIUM | ST4 explicitly bumps the Total → 57 alongside the row add (all SKILLS_INDEX edits in ST4); rubric bullet asserts it. |
| jq string-interpolation of untrusted rule text → injection | MEDIUM | AC: jq-only, untrusted text via `--rawfile`/`--argjson`/`--arg` only (mirror `read-bridge.sh`), never interpolated into shell or a jq program. |
| A malformed / missing-field / duplicate-`id` rule object crashes the reader or silently corrupts the merged set | MEDIUM | AC + ST2 require per-object validation with skip-and-diagnostic (never crash, still exit 0, emit remaining valid rules); ST3 tests (g) cover each invalid case. |
| `/rules add` clobbers or corrupts an existing `.agent/rules/<category>.json` (e.g. on pre-existing malformed JSON or a non-atomic write) | MEDIUM | AC + ST4 require parse-gate (abort on malformed) → unique-id → temp-file + atomic `mv` → read-back verify, confirm-only, append-only (mirrors the setup settings-merge discipline). |
| `/rules add` writes OUTSIDE `.agent/rules/` via a malicious/typo `category` (`../`, `/`, leading dot, metachars) — path traversal | HIGH | AC + ST4: filename is a slugified `[a-z0-9-]` single segment; reject/sanitize traversal + metachars + empty; `test-rules-docs.sh` asserts the command/skill document the containment rule. |
| Scope creep into enforcement (the 3 seams / close-the-loop / nudge) or layering | LOW | Explicitly OUT OF SCOPE — substrate only; the skill carries a "deferred to 3b-ii / layering deferred" note. |
| `/rules suggest` hard-depends on graphify (external) | LOW | Scanner degrades grep/glob-first; brain-context is graph-if-present; never blocks (mirror `/setup twin`). |
| Current branch is `main` | LOW | Supervisor branches a fresh feature branch off origin/main. |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 4
- **Base Branch:** main
- **Self-heal:** default ON (Phase 4.5) — new command + skill + reader + doc surface; consistency_audit + corpus-task ground-truth are the right gates.
- **Heal iterations:** default (3)
- **Cost profile:** default (inherit)
- **Beads:** not required (Supervisor/Launch Pad path)

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-06-30-rules-substrate.md

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/84 (base: main, OPEN)
- **Feature branch:** feature/rules-substrate
- **Subtasks:** 5/5 completed (ST1 skill+README · ST2 reader · ST3 reader-test · ST4 command+docs-test+index+help · ST5 version+doc-currency)
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 1 (holistic review PASS; 3 advisory MEDIUM/LOW doc-accuracy items proactively fixed — no BLOCKING/HIGH new issues)
- **heal_remaining_issues:** 0
- **rubric_score:** 6/6
- **Executable Acceptance (corpus-tasks):** doc-currency-green ✓ · version-consistent ✓
- **Gates:** validate-version ✓ · check-doc-currency ✓ · check-command-sync ✓
- **Self-tests:** test-read-rules.sh 29/29 · test-rules-docs.sh 12/12
- **Counts:** 14 agents · 21 commands · 57 skills · 21 hooks (commands 20→21, skills 56→57); version 14.50.0→14.51.0
- **Until-mergeable dispatched:** true
- **Until-mergeable log:** .supervisor/logs/review-pr-dispatch-20260630T075443Z-0d3ee011f999efdb5a092fa941060493a4d83f64.log
- **Note (R9):** detached until-mergeable drain in flight (isolated worktree, waiting on ci + claude-review). A human merging should wait for terminal READY/ESCALATED.
