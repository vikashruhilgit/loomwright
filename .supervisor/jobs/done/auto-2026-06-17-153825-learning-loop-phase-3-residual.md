# Supervisor Job: Learning Loop Phase 3 Residual — Advisory Red-Team + CI Enrichment + Miss-Class Taxonomy

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh, v14.28.0)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** `.supervisor/requirements/auto-2026-06-17-153825-learning-loop-phase-3-review-quality.md`
- **legacy_brief:** false

## Task
**Goal:** Close the *verified residual* of Learning Loop roadmap Phase 3 ("Review Quality: Different Lens + Class-Based Fixer"). Phase 3's core (R1-base different-lens directive, R2 class-based fixer, R3-base 5-of-6 miss-classes) **already shipped in v14.21.0** — do NOT re-implement it. This job ships the three genuinely-missing/incomplete pieces, all **advisory, non-gating, additive**:
1. **R4** — enrich the *independent* CI review prompt with the six miss-classes (CI stays independent; convergence is NOT a goal).
2. **R3 taxonomy split** — split the merged "Count / cross-reference drift" bullet into the two distinct named classes the roadmap enumerates; reconcile the inline lists that reference it.
3. **R1 optional red-team** — opt-in, default-OFF, fail-safe, **non-gating** red-team review for high-risk integrated diffs in Supervisor Phase 4.5.

### Canonical six miss-class names (single source of truth — VERBATIM from `LEARNING_LOOP_ROADMAP.md` §"Phase 3 → Explicit miss-classes", lines 208–213)
1. `validation parity`
2. `numeric falsy coercion`
3. `positional args vs options object misuse`
4. `missing branch coverage`
5. `count/version/restated-list drift`
6. `cross-reference precision drift`

(Behavioral defects: 1–4. Drift: 5–6. **These are byte-identical to the roadmap's list — do NOT elaborate, hyphenate, or re-case them.** A surface may add a descriptive parenthetical AFTER the canonical phrase — e.g. quality-checklist's "validation parity (backend mirrors frontend)" — but the canonical phrase above must appear verbatim. Defining them here, identical to the roadmap, removes the cross-subtask naming dependency AND prevents the taxonomy drift this job exists to fix.)

## Acceptance Criteria
- [ ] Given the CI review workflow, when it runs, then its `prompt:` block names all six canonical miss-classes and references `skills/quality-checklist/SKILL.md` as the authority, while remaining independent of local review (no "match/converge with the local reviewer" instruction).
- [ ] Given `skills/quality-checklist/SKILL.md`, then the Self-Heal Miss-Class Checklist has **six** distinct bullets — class 5 (count/version/restated-list drift) and class 6 (cross-reference precision drift) are SEPARATE — with all existing Class-signal text preserved.
- [ ] Given the inline class lists in `agents/code-reviewer.md:167` and `agents/supervisor.md` (DIFFERENT-LENS directive + fixer examples), then they name the same six canonical classes (no surface still says "count/cross-ref drift" as one merged class where the six-class taxonomy is being enumerated).
- [ ] The six class names used across the brief, `quality-checklist/SKILL.md`, `code-reviewer.md`, `supervisor.md`, and the CI prompt are **byte-identical** to the roadmap's Explicit miss-classes list (descriptive parentheticals allowed only AFTER the canonical phrase).
- [ ] Given a `/supervisor` run WITHOUT `--red-team` (and without `.red_team_high_risk` config), then Phase 4.5 behavior is byte-for-byte unchanged from v14.28.0 (red-team default OFF ⇒ never spawns).
- [ ] Given `/supervisor --red-team` AND a high-risk integrated diff, then Phase 4.5 spawns `ai-agent-manager-plugin:red-team-reviewer` as exactly ONE additional advisory pass (outside the heal loop), posts its findings as a clearly-labelled non-gating PR comment, and does NOT change `heal_decision`, directly drive the fixer, or alter PR/run control flow; a red-team error/timeout is logged and the run continues (fail-safe).
- [ ] Given `/supervisor --red-team` AND a low-risk integrated diff, then no red-team spawn occurs (silent skip).
- [ ] `--red-team` / `--no-red-team` are documented in BOTH `agents/supervisor.md` and `commands/supervisor.md`; `.supervisor/notify-config.json .red_team_high_risk` config path is documented; `--no-red-team` wins over `--red-team` (mirrors `--no-auto-review`).
- [ ] No new agent/command/skill/hook (counts stay 14 agents / 18 commands / 55 skills / 19 hooks). No `schema_version` bump anywhere.
- [ ] Version bumped to **14.29.0** in `plugin.json` + `marketplace.json`; CHANGELOG top entry added; CLAUDE.md release banner added (keep only the two most recent); roadmap Phase 3 annotated (core in v14.21.0, residual here).
- [ ] `scripts/check-doc-currency.sh` and `scripts/validate-version.sh` pass.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | R4 — enrich CI review prompt | 1 modify | LAUNCHABLE |
| 2 | R3 — split miss-class taxonomy to six + reconcile reviewer/local lens lists | 3–4 modify | LAUNCHABLE |
| 3 | R1 — opt-in advisory red-team for high-risk diffs (Phase 4.5) | 2 modify | LAUNCHABLE |
| 4 | Docs + version bump | 5–6 modify | BLOCKED (by #1, #2, #3) |

### Subtask 1 — R4: enrich CI review prompt
- **Files:** `.github/workflows/claude-code-review.yml` (modify, the `prompt:` block, lines 33–51).
- **Do:** after line 49 ("...constructive and helpful in your feedback."), before line 51 (`Use gh pr comment ...`), add a section naming the six canonical miss-classes (above) with a one-line signal each, prefaced by something like "Additionally, watch for these recurring miss-classes (defined in `ai-agent-manager-plugin/skills/quality-checklist/SKILL.md`)". The CI reviewer must be able to apply them from the prompt alone.
- **Keep CI independent:** frame as the reviewer's own additional checklist; do NOT tell CI to match, converge with, or defer to the local/self-heal reviewer.
- **provides:** `r4_ci_miss_classes` (CI prompt names the six classes)
- **requires:** none (uses the brief's canonical names directly)

### Subtask 2 — R3: split taxonomy to six + reconcile inline lists
- **Files:** `ai-agent-manager-plugin/skills/quality-checklist/SKILL.md` (modify, ~line 155 + token note line 166); `ai-agent-manager-plugin/agents/code-reviewer.md` (modify, line 167 self-heal lens list).
- **Do (quality-checklist):** split bullet 5 "Count / cross-reference drift" (line 155) into TWO bullets — "**Count / version / restated-list drift.**" (counts, version strings, mirrored prompts, restated lists) and "**Cross-reference precision drift.**" ("see X" / `file:line` / canonical-name references that must stay precise across files). Preserve and split the existing Class-signal text appropriately. Update the line-166 token-cost note only if the change materially shifts the estimate.
- **Do (code-reviewer.md:167):** update the self-heal lens enumeration so it names all six canonical classes (currently "...and count/cross-ref drift" — expand to the two distinct classes).
- **Do (thorough one-pass sweep — per Plan Review):** ALSO scan `ai-agent-manager-plugin/skills/pr-postmortem/SKILL.md:42` and `ai-agent-manager-plugin/skills/supervisor-readiness/SKILL.md:210` for the merged "count/cross-ref drift" phrasing. Where it is an **inline class summary/enumeration** of the miss-class checklist (pr-postmortem:42), update it to name the two split classes. Where it is **genuinely self-referential prose about the drift convention itself** (supervisor-readiness:210 — judge in context), leave it unchanged. This pre-empts the Phase 4.5 consistency-audit (auto-expands on `skills/` changes) flagging them as drift against the newly-split taxonomy and costing a heal iteration.
- **Do NOT touch** the CODE_REVIEW_RESULT `drift_kind` enum (orthogonal vocabulary).
- **provides:** `r3_six_named_classes` (quality-checklist + code-reviewer lens enumerate six; stray inline summaries reconciled)
- **requires:** none (uses the brief's canonical names directly)

### Subtask 3 — R1: opt-in advisory red-team for high-risk diffs
- **Files:** `ai-agent-manager-plugin/agents/supervisor.md` (modify, Phase 4.5 reviewer-spawn region ~699–715, Phase 0 flag parsing, and the SUPERVISOR_RESULT/Outcome surfaces); `ai-agent-manager-plugin/commands/supervisor.md` (modify, Usage + Parameters table — mirror the flag).
- **Design (implement exactly):**
  - **Opt-in, default OFF**, mirroring `--auto-review`: add `--red-team` (enable) and `--no-red-team` (suppress; wins if both passed); config equivalent `.supervisor/notify-config.json` `.red_team_high_risk: true`. Default OFF ⇒ zero behavior change. Parse/record the flag at Phase 0 as a Phase Flag (so later phases survive context loss, like `--non-interactive`).
  - **Trigger:** only when enabled AND the integrated feature-branch diff classifies **high-risk** by a repo-agnostic heuristic — touches auth/authz, crypto/secrets/tokens, security middleware, payment, or DB migrations (path/content match) OR exceeds a size threshold (state a concrete default, e.g. > 400 changed lines or > 15 files). Enabled+low-risk ⇒ silent skip. Disabled ⇒ never spawn.
  - **Advisory contract (NON-NEGOTIABLE):** spawn `Task(subagent_type: "ai-agent-manager-plugin:red-team-reviewer", ...)` on the integrated diff as **exactly ONE advisory pass** — OUTSIDE/after the bounded heal loop, NOT a new iteration inside it. Post findings as a clearly-labelled PR comment ("🔴 Advisory red-team review — non-gating") and record them as risks. Red-team itself NEVER changes `heal_decision`, NEVER directly drives the fixer, NEVER blocks the PR/run, and introduces NO new gate.
  - **Overlap nuance (match the roadmap, line ~250):** red-team does not feed the fixer directly. But an issue red-team surfaces that the *code-reviewer independently also flags* as a `new` BLOCKING/HIGH issue is handled by the EXISTING class-based fix path (driven by `CODE_REVIEW_RESULT`, not by red-team). Keep these two paths distinct: red-team = advisory input/risks; the code-reviewer = the gating signal.
  - **Fail-safe:** any red-team error/timeout ⇒ log + continue; the run never aborts on this path.
  - **No schema bump:** record via a note in `SUPERVISOR_RESULT.summary` + the job `## Outcome` block. Do NOT add a result-block field unless additive-optional and clearly justified (default: no new field).
- **provides:** `r1_red_team_advisory` (Phase 4.5 opt-in advisory red-team)
- **requires:** none (uses the brief's canonical names where it references miss-classes; reuses existing `red-team-reviewer` agent)

### Subtask 4 — Docs + version bump
- **Authoritative version bump:** `ai-agent-manager-plugin/.claude-plugin/plugin.json` (version → 14.29.0; keep `description` a short summary, do NOT append a version clause); root `.claude-plugin/marketplace.json` (version → 14.29.0).
- **Doc-currency surfaces — the gate is the oracle, NOT this list.** `scripts/check-doc-currency.sh` scans a FIXED set (see its `SCAN_FILES`): `CLAUDE.md`, `README.md`, `AGENT_GUIDELINES.md`, `.claude-plugin/README.md`, `.claude-plugin/marketplace.json`, `ai-agent-manager-plugin/commands/agent-help.md`, `ai-agent-manager-plugin/docs/ARCHITECTURE.md`, `ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md`. Update EVERY one of these that carries a **current-version claim** matching the gate's phrasings (the `AI agents vX.Y.Z` headline, `plugin.json (vX.Y.Z)`, `Plugin (vX.Y.Z)`, `(vX.Y.Z) includes`) so they read 14.29.0. PR #61 (v14.28.0) had to touch `.claude-plugin/README.md`, `AGENT_GUIDELINES.md`, and `commands/agent-help.md` for exactly this reason — do not omit them. Counts are UNCHANGED (14/18/55/19), so no count phrase needs editing (but do not let a count phrase regress).
- **Narrative docs:** `CHANGELOG.md` (new top entry); `CLAUDE.md` (new release banner — keep only the two most recent; update the Supervisor row / Phase 4.5 line to mention the opt-in advisory red-team); `ai-agent-manager-plugin/docs/SPIKES/LEARNING_LOOP_ROADMAP.md` (flip the Phase 3 residual status from "remaining" to "shipped in v14.29.0" — the residual-scope prose is already present on the base; do NOT duplicate it). `docs/RESULT_SCHEMAS.md` only if subtask 3 added an additive field (default: untouched).
- **Verification (mandatory before PR):** run `bash scripts/check-doc-currency.sh` AND `bash scripts/validate-version.sh` and resolve EVERY surface they flag until both exit 0. These two passing is the binding acceptance — a hand-enumerated file list is not sufficient.
- **Counts:** keep 14 agents / 18 commands / 55 skills / 19 hooks (no surface added). Update only if a self-test/script discovers otherwise.
- **provides:** `docs_version_current`
- **requires:** `r4_ci_miss_classes`, `r3_six_named_classes`, `r1_red_team_advisory` (must document the final shape)

## Parallelism Analysis
- **Batch 1 (parallel):** Subtask 1, Subtask 2, Subtask 3 — file-disjoint (`.github/workflows/...` vs `skills/`+`agents/code-reviewer.md` vs `agents/supervisor.md`+`commands/supervisor.md`) and naming-independent (all use the brief's canonical names).
- **Batch 2:** Subtask 4 (after 1–3 merge — it documents/versions the final shape).
- **Recommended workers:** 3 (Phase 4.5 holistic review will catch any residual six-class naming drift across the merged surfaces).
- Fast-path note: edits are small; Supervisor may collapse to sequential — acceptable.

## File Impact Map (verified — every path exists)
| File | Subtask | Confidence | Note |
|---|---|---|---|
| `.github/workflows/claude-code-review.yml` | 1 | HIGH | prompt block lines 33–51; insertion after line 49 |
| `ai-agent-manager-plugin/skills/quality-checklist/SKILL.md` | 2 | HIGH | bullet at line 155; token note line 166 |
| `ai-agent-manager-plugin/agents/code-reviewer.md` | 2 | HIGH | self-heal lens list line 167 |
| `ai-agent-manager-plugin/skills/pr-postmortem/SKILL.md` | 2 | MEDIUM | inline class summary line 42 — split to six |
| `ai-agent-manager-plugin/skills/supervisor-readiness/SKILL.md` | 2 | MEDIUM | line 210 — sweep; leave if genuinely self-referential |
| `ai-agent-manager-plugin/agents/supervisor.md` | 3 | HIGH | Phase 4.5 ~699–715; Phase 0 flags; lines 705/746 six-name reconcile |
| `ai-agent-manager-plugin/commands/supervisor.md` | 3 | HIGH | Usage + Parameters table (flag mirror) |
| `ai-agent-manager-plugin/.claude-plugin/plugin.json` | 4 | HIGH | version → 14.29.0 |
| `.claude-plugin/marketplace.json` | 4 | HIGH | version → 14.29.0 |
| `.claude-plugin/README.md` | 4 | HIGH | doc-currency scan surface — update current-version claim |
| `ai-agent-manager-plugin/commands/agent-help.md` | 4 | HIGH | doc-currency scan surface — update current-version claim |
| `README.md` | 4 | MEDIUM | doc-currency scan surface — update if it carries a current-version claim |
| `AGENT_GUIDELINES.md` | 4 | MEDIUM | doc-currency scan surface — update if it carries a current-version claim |
| `ai-agent-manager-plugin/docs/ARCHITECTURE.md` | 4 | LOW | doc-currency scan surface — update only if it carries a current-version claim |
| `ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md` | 4 | LOW | doc-currency scan surface — update only if it carries a current-version claim |
| `CHANGELOG.md` | 4 | HIGH | top entry |
| `CLAUDE.md` | 4 | HIGH | release banner + Supervisor row + headline version |
| `ai-agent-manager-plugin/docs/SPIKES/LEARNING_LOOP_ROADMAP.md` | 4 | HIGH | flip Phase 3 residual status to shipped-in-14.29.0 (prose already on base) |

## Risk Assessment
| Risk | Severity | Mitigation |
|---|---|---|
| Red-team path leaks into gating (changes heal_decision / blocks PR) | **HIGH** | AC + Subtask 3 design mandate advisory-only, non-gating, fail-safe; default OFF; Phase 4.5 holistic review + Plan Review must confirm the heal-decision logic is untouched |
| Default behavior changes for existing users | HIGH | Default OFF (opt-in flag + config); AC requires byte-for-byte-unchanged default path |
| Six-class naming drifts across surfaces | MEDIUM | Canonical names fixed in this brief; all subtasks copy them verbatim; Subtask 2 sweeps the two known stray inline summaries (pr-postmortem:42, supervisor-readiness:210 per Plan Review); holistic review checks the rest |
| agents/↔commands/ supervisor mirror drift | MEDIUM | Subtask 3 edits both; code-reviewer consistency-audit auto-expands on agents/commands changes |
| Doc-currency gate failure (counts/version) | MEDIUM | Counts unchanged; Subtask 4 bumps version in plugin.json + marketplace.json + CLAUDE.md banner together; run check-doc-currency.sh + validate-version.sh before PR |
| Conflating behavioral miss-classes with `drift_kind` enum | LOW | Explicit non-goal; Subtask 2 forbidden from touching the enum |

## Configuration
- **Target version:** 14.29.0 (minor — additive opt-in feature)
- **Max workers:** 2–3
- **Base branch:** main
- **Self-heal:** enabled (default); this PR will exercise Phase 4.5 self-heal with red-team DEFAULT OFF (so the new path does not fire on its own PR)
- **schema_version bumps:** none

## Handoff
/supervisor job: .supervisor/jobs/pending/auto-2026-06-17-153825-learning-loop-phase-3-residual.md

---

## Outcome
- **Result:** completed
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/62
- **Branch:** feature/learning-loop-phase3-residual
- **Base:** main
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 1 (holistic review PASS on first pass; 1 discretionary MEDIUM drift fix applied — CHANGELOG taxonomy misattribution)
- **heal_remaining_issues:** 0
- **red_team_advisory:** disabled (no --red-team flag; default OFF)
- **preflight_sync:** clear
- **Verification:** check-doc-currency ✓ · validate-version ✓ · check-command-sync ✓ · 20/20 self-tests ✓
- **Completed:** 2026-06-17
