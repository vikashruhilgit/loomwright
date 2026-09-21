# Requirement: Learning Loop Phase 3 — Review-Quality RESIDUAL (Advisory Red-Team + CI Enrichment + Taxonomy)

<!-- Outcomes Rubric: single-iteration run, no rubric required. -->

## Source & Provenance

- Roadmap: `ai-agent-manager-plugin/docs/SPIKES/LEARNING_LOOP_ROADMAP.md` §"Phase 3 — Review Quality: Different Lens + Class-Based Fixer".
- Authored by `/autonomous --single-iteration` (session auto-2026-06-17-153825) from "check this:<roadmap> and start on phase 3".
- **Scope narrowed after verification (2026-06-17).** Launch Pad ANALYZE confirmed that the **v14.21.0 self-heal hardening** slice already shipped most of Phase 3. This requirement targets only the *verified residual*. User approved "full residual incl. red-team".

### Already shipped (DO NOT re-implement — verified against the v14.28.0 tree)
- **R1 base (different lens):** `agents/supervisor.md:703` DIFFERENT-LENS DIRECTIVE; `agents/code-reviewer.md:167` self-heal lens. ✅
- **R2 (class-based fixer):** `agents/supervisor.md:746` "Fix the CLASS, not just the flagged instance" + occurrence cap. ✅
- **R3 base (miss-classes):** `skills/quality-checklist/SKILL.md:145-159` "Self-Heal Miss-Class Checklist" — **5 bullets** covering all six concepts, but classes 5 & 6 are MERGED into one bullet. ⚠️

## Goal

Close the verified Phase 3 residual without changing any gate, verdict, or `heal_decision`:
1. **R4** — enrich the *independent* CI review prompt with the miss-class vocabulary (CI stays independent; convergence is NOT a goal).
2. **R3 taxonomy split** — split the merged "Count / cross-reference drift" bullet into the two distinct named classes the roadmap enumerates, and reconcile the inline class lists that reference it.
3. **R1 optional red-team** — add an **advisory, non-gating, fail-safe, opt-in** red-team/adversarial review for high-risk integrated diffs in Supervisor Phase 4.5.
4. **Docs/version** — record that Phase 3's core landed in v14.21.0; version bump + CHANGELOG + doc-currency.

## Scope (verified residual)

### R4 — Enrich the independent CI review prompt
- File: `.github/workflows/claude-code-review.yml`, the `prompt:` block (lines 33–51).
- Add a miss-class section to the prompt naming the six classes (insertion point: after line 49 "...constructive and helpful in your feedback.", before line 51 `gh pr comment`).
- Keep CI **independent**: frame as the reviewer's own additional checklist; do NOT instruct CI to match/converge with local review. Reference `ai-agent-manager-plugin/skills/quality-checklist/SKILL.md` "Self-Heal Miss-Class Checklist" as the authority, and inline the six class names (the CI reviewer should not have to read the skill to know them).

### R3 — Split the miss-class taxonomy into six named classes + reconcile references
- `skills/quality-checklist/SKILL.md:155`: split bullet 5 "Count / cross-reference drift" into TWO bullets:
  - **Count / version / restated-list drift** (counts, version strings, mirrored prompts, restated lists).
  - **Cross-reference precision drift** ("see X" / `file:line` / canonical-name references that must stay precise across files).
  - Keep all existing Class-signal text; update the token-cost note (line 166) if the bullet count materially changes the estimate.
- Reconcile the inline class enumerations that currently say "count/cross-ref drift" as one, so all surfaces name the same six classes:
  - `agents/code-reviewer.md:167` (self-heal lens list).
  - `agents/supervisor.md:705` (DIFFERENT-LENS DIRECTIVE list) and `:746` (fixer examples) — keep wording consistent with the six canonical names.
- This is **prose/taxonomy only** — no schema change (the CODE_REVIEW_RESULT `drift_kind` enum is a separate, orthogonal vocabulary and MUST NOT be touched).

### R1 — Advisory red-team review for high-risk integrated diffs (Phase 4.5)
- File: `agents/supervisor.md` Phase 4.5 (reviewer-spawn region ~699–715).
- **Opt-in, default OFF** — mirror the existing `--auto-review` / `--no-auto-review` / `.supervisor/notify-config.json .auto_review` precedent exactly:
  - New `--red-team` flag (opt-in) and `--no-red-team` (suppress); `.supervisor/notify-config.json` `.red_team_high_risk: true` as the config equivalent. Default OFF ⇒ **zero behavior change** for existing runs. (Flags on existing `/supervisor`; command COUNT unchanged at 18.)
- **Trigger:** only when enabled AND the integrated feature-branch diff classifies **high-risk** by a repo-agnostic heuristic (e.g. touches auth/authz, crypto/secrets/tokens, security middleware, payment, or DB migrations — by path/content match — OR exceeds a size threshold). When enabled but low-risk ⇒ skip silently. When disabled ⇒ never spawn.
- **Advisory contract (NON-NEGOTIABLE):** spawn `Task(subagent_type: "ai-agent-manager-plugin:red-team-reviewer", ...)` on the integrated diff as an ADDITIONAL lens whose findings are **posted to the PR as a clearly-labelled advisory comment** ("Advisory red-team review — non-gating"). Red-team findings:
  - NEVER change `heal_decision` (PASS/FAIL/ESCALATED unchanged);
  - NEVER trigger the fix loop;
  - NEVER block the PR or the run.
- **Fail-safe:** any red-team error/timeout ⇒ log + continue (the run never aborts on the red-team path). Mirrors the "side-effect emitters fail SAFE / always exit 0" invariant.
- **No `schema_version` bump:** record via a note in `SUPERVISOR_RESULT.summary` + the job `## Outcome` block (and the existing `knowledge_sources_used`/PR-comment surfaces). If a marker field is genuinely wanted, it MUST be additive-optional (no bump), following the `branch_base`/`pr_state` precedent — but default to summary+comment only.
- Mirror the flag in `commands/supervisor.md` (the consistency-audit auto-expand will check agents/↔commands/ parity).

### Docs / version
- `ai-agent-manager-plugin/.claude-plugin/plugin.json` + root `.claude-plugin/marketplace.json`: bump version (minor — additive feature), keep the four counts (14/18/55/19) unchanged, keep `description` a short summary (do NOT append a version clause).
- `CHANGELOG.md`: new top entry describing R4 + R3-split + R1-red-team-advisory.
- `CLAUDE.md`: add the new release banner (keep only the two most recent), update the Supervisor row / Phase 4.5 description to mention the opt-in advisory red-team if warranted.
- `ai-agent-manager-plugin/docs/SPIKES/LEARNING_LOOP_ROADMAP.md`: annotate Phase 3 — core shipped in v14.21.0; residual (R4 + taxonomy split + advisory red-team) shipped in this version.
- `docs/RESULT_SCHEMAS.md`: only if an additive red-team marker field is added (otherwise untouched).

## Acceptance Criteria
- [ ] CI review prompt (`.github/workflows/claude-code-review.yml`) names the six miss-classes; CI remains independent (no convergence instruction).
- [ ] `quality-checklist/SKILL.md` enumerates **six** distinct named miss-classes (count/version/restated-list drift AND cross-reference precision drift are separate bullets); `agents/code-reviewer.md` + `agents/supervisor.md` inline lists name the same six.
- [ ] Phase 4.5 has an **opt-in, default-OFF** advisory red-team path for high-risk diffs that posts a non-gating PR comment and NEVER changes `heal_decision`, the fix loop, or PR/run control flow; fail-safe on error.
- [ ] `--red-team` / `--no-red-team` flag documented in BOTH `agents/supervisor.md` and `commands/supervisor.md`; `.red_team_high_risk` config path documented.
- [ ] No new agent/command/skill/hook; counts stay 14/18/55/19. No `schema_version` bump.
- [ ] Default behavior (no `--red-team`) is byte-for-byte unchanged from v14.28.0 for the review/heal path.
- [ ] `scripts/check-doc-currency.sh` and `scripts/validate-version.sh` pass; version + CHANGELOG + CLAUDE.md banner updated in the same change.

## Non-Negotiable Constraints
- **Advisory first** — do NOT change `heal_decision`, review verdicts, or gating (roadmap §1.6; CLAUDE.md "a green heal_decision: PASS does NOT mean reviewer-clean").
- `CLAUDE.md` is the human authority; everything else subordinate.
- No new memory/storage surface; no new agent/command/skill/hook. No `schema_version` bump (prefer additive/frozen-example precedent).
- Keep CI and local review **independent** (no convergence project).
- Do NOT re-touch the already-shipped R1-base/R2 logic except to reconcile the six-class naming (R3).
- The CODE_REVIEW_RESULT `drift_kind` enum is orthogonal to the behavioral miss-classes — do not conflate or modify it.

## Explicit Non-Goals
- Not Phase 4 (postmortem-as-ledger), Phase 5–6 (brain).
- No CI/local reviewer convergence.
- No worker-prompt / worker-memory changes.
- No re-implementation of R1-base / R2 / R3-base (already shipped v14.21.0).

## Status: brief-shipped

Job `.supervisor/jobs/done/auto-2026-06-17-153825-learning-loop-phase-3-residual.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
