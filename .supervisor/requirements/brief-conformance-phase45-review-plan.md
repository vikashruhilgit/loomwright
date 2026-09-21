# Task Plan — brief-conformance-phase45-review

**Source brief:** `.supervisor/jobs/in-progress/2026-09-13-brief-conformance-phase45-review.md` (authoritative for AC1–AC9 and the Implementation-shape list; this plan does not restate them)
**Owner decisions (do not re-litigate):** R1 no new gate · R2 ordinary `new`/HIGH findings · R4 `/review-pr` out of scope — `.supervisor/requirements/review-gate-brief-conformance/00-overview.md`
**Persistence:** file fallback (no `.beads/`) · **Base branch:** main (verified: `origin/main` == plugin.json 15.68.0)
**Planned:** 2026-09-13 by Orchestrator

## Threshold validation

Brief's single-subtask structure is CONFIRMED against `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold":
- `file-conflict`: n/a — one work group; every lane is edited by one worker
- `context-bound`: 9 files (8 modify + 1 create) < 12; estimated ~250–400 changed lines < 800
- `genuine-parallelism`: the 9 lanes are one coherent seam (skill → agent mirror → checklist → test → budgets → release) — no zero-overlap group of ≥3 files exists that does not depend on the skill wording landing first
→ ONE task. No `Split reason` line. No per-subtask reviewer (Review Gate Policy).

## EPIC: brief-conformance-phase45-review

### TASK brief-conformance-phase45-review-1 — BRIEF-CONFORMANCE enrichment (skill + mirrors + seam test + release) — LAUNCHABLE
- [ ] **Status:** open
- **Blocked by:** nothing (`requires: []`, `external_requires: []`)
- **Acceptance criteria:** AC1–AC9 of the brief (all). Verified starting state 2026-09-13 — all seven `provides` tokens are 0-hit today: `1f.` / `BRIEF-CONFORMANCE` / `25 bullets` in `loomwright/skills/self-heal-advisory/SKILL.md`; `not_addressed` in `loomwright/agents/code-reviewer.md`; `brief_conformance` in `loomwright/skills/quality-checklist/SKILL.md`; `BRIEF-CONFORMANCE` in `CHANGELOG.md`; `loomwright/scripts/test-brief-conformance-seam.sh` absent.
- **Files (verified: exist):**
  - `loomwright/skills/self-heal-advisory/SKILL.md` — Part 1 H2 goes after `## House-rules advisory (committed convention enrichment)` (line ~104, before `## Post-review advisory checks`); step `1f.` after `1e.` (line ~520); prompt line after **HOUSE-RULES ADVISORY** (line ~607); DIFFERENT-LENS DIRECTIVE parenthetical (line ~599); fix-prompt step 1a class list (line ~654)
  - `loomwright/agents/code-reviewer.md` — Review Process rule; **ALSO** the existing "Self-heal lens" sentence (line ~182 [pins: `Self-heal lens (Supervisor Phase 4.5`]) restates the miss-class enumeration inline — add `brief_conformance` there too, or it is the exact "restated-list drift" the checklist flags
  - `loomwright/skills/quality-checklist/SKILL.md` — §"Self-Heal Miss-Class Checklist" bullet (≤ ~120 words; preloaded by 6 agents, orchestrator headroom 837 proxy tokens)
  - `loomwright/docs/prompt-token-budgets.json` + `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" — ONLY if `check-token-budget.sh` breaches (code-reviewer headroom today 2773)
  - `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md` — 15.68.0 → 15.69.0, in-place `vX.Y.Z` in both descriptions, ONE bold-paragraph top entry, "Counts unchanged"
  - **[TO BE CREATED]** `loomwright/scripts/test-brief-conformance-seam.sh` — modelled on `loomwright/scripts/test-rules-seams.sh` (verified: exists); `ok()`/`no()` DEFINED (meta-gate `test-suite-helpers-defined.sh`); auto-included by the `loomwright/scripts/test-*.sh` glob in `.github/workflows/ci.yml` (verified line 72)
- **Ordered DO steps:** brief's "Implementation shape" 1→9, executed in that order (Part 1 section first so step 1f / prompt line / test can cite "the cap in Part 1")
- **State-trace before finishing (AC3/AC4):** no `brief_path` path; brief without `## Acceptance Criteria`; zero bullets; 40-criteria truncation with rubric present
- **Gate (deterministic, worker self-verified):** `bash loomwright/scripts/test-brief-conformance-seam.sh` green + mutant red; `bash scripts/check-token-budget.sh`; `bash scripts/check-doc-currency.sh`; FULL `for t in loomwright/scripts/test-*.sh; do bash "$t"; done`; `grep -rn "15\.68\.0" --include=*.json --include=CHANGELOG.md .` shows only historical mentions
- **Skills:** `skills/self-heal-advisory/SKILL.md` (Part 1 §"House-rules advisory" = shape to copy), `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` (mutation control), `AGENT_GUIDELINES.md` §"Read-Before-Write Verification Gate"
- **Estimated:** 90–150 min single worker

## Review lane
No paired review subtask. Gate = the deterministic checks above. Sole LLM review = Supervisor Phase 4.5 integrated review over the merged branch — which, once this task lands, is itself the surface being changed (the reviewer of this PR runs on the OLD skill text; the new BRIEF-CONFORMANCE line first takes effect on the NEXT job). Do not expect AC1's behaviour to be observable on this PR's own Phase 4.5 run.

## Risks (delta over the brief's table)
| Risk | Mitigation |
|---|---|
| `code-reviewer.md:182` inline enumeration left stale while the checklist gains a class | Named above as an explicit edit in the same lane |
| Seam-test regex for "adjacent to HOUSE-RULES" matches the Part 1 prose mention at line ~170 instead of the Part 2 prompt line | Anchor (a) on the `**HOUSE-RULES ADVISORY (non-gating` prompt-line literal, not the bare token |
| CHANGELOG growth pushes nothing (not preloaded) — but `code-reviewer.md` growth counts against 2773 headroom | Raise only on breach; measured + ~10% |
