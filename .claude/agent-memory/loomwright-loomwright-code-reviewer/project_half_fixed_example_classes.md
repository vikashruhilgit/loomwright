---
name: half-fixed-example-classes
description: Multi-surface example/semantic classes found half-fixed — job-path examples, NEEDS_HUMAN semantics, PO step numbering, agent-help phases, insights dashboard section enumeration
metadata:
  type: project
---

Classes where a sweep fixed one occurrence but the class spans many surfaces (none scanned by doc-currency CI):

1. **`/supervisor job:` example path** — RESOLVED in the June 2026 fix/post-merge-residual-defects branch: repo-wide grep for bare `.supervisor/jobs/{...}` now returns zero hits; all handoff examples use `pending/`.
2. **Code Reviewer NEEDS_HUMAN semantics** restated in: agents/code-reviewer.md Review Decision Matrix AND "Decision Definitions" bullet (~188) AND the Output Format NEEDS_HUMAN example (~578), PLUS preloaded skills/quality-checklist/SKILL.md ("Minor style issue | NEEDS_HUMAN" row + "Gate Outcomes ≈ NEEDS_HUMAN" section). Changing the matrix without the other four creates a preloaded-skill runtime contradiction.
3. **Product Owner brainstorm step numbering** — skills/brainstorming/SKILL.md canonically names it "Phase 3.5: Reality Check" ("5-Phase Framework"); the same enumeration is mirrored in agents/product-owner.md (brainstorm step list) and commands/product-owner.md (~46 prose + ~344 embedded copy). Renumbering one surface diverges from the preloaded skill.
4. **agent-help phase enumerations** (already known: [[agent-help-phase-drift]]) — the Launch Pad section's "N-Phase Workflow" header + ASCII diagram must move together; Phase 7 is non-interactive and needs the footnote treatment used in commands/launch-pad.md.

**Why:** the v14.22-era consistency sweep (review round 2) fixed agents/launch-pad.md's handoff path, the code-reviewer matrix, and PO step numbers individually, missing each class's other surfaces — reviewer samples, fixer must sweep.

**How to apply:** when a diff touches any one occurrence of these classes, grep the exact old string repo-wide before passing the review.

5. **Kept-current count surfaces NOT scanned by doc-currency CI** (confirmed v14.23.0 review: skills 52→53 bump updated 5 surfaces, missed all 4 of these; re-checked June 2026 — `52 skill` greps clean, class 5 currently resolved): README.md ~21 (the "NEW in v14.0.0" block's trailing "14 agent roles, 17 slash commands, N skills, 19 quality gate hooks" — maintained as CURRENT despite the historical framing), README.md ~568 ("N skill files for guidance"), .claude-plugin/README.md ~9 (autonomous-mode bullet's trailing "Counts: 17 slash commands, N skills, 19 hooks"), commands/agent-help.md ~1045 (directory-tree "Skill files (N skills)"). On any count bump, grep the OLD number repo-wide (`grep -rn "52 skill"` style) — check-doc-currency.sh passes with these stale.

6. **Fictional token-savings numbers** — RESOLVED in PR #51 (fix/v14.23.1-combined, June 2026): grep for `~500 tokens|~200 tokens instead|tokens freed` now returns zero hits across agents/, commands/, skills/, CLAUDE.md, README.md.

7. **Bot-author doc simplification (PR #51, v14.23.1)** — pr-postmortem docs say a bot round needs an author that "ends with `[bot]`", but the combined gather script's `bot_author_re` is `^claude(\[bot\])?$|\[bot\]$|^github-actions` (bare `claude` / `github-actions*` logins also count). The #50-variant description survived the #49-wins conflict resolution in 5 surfaces: `skills/pr-postmortem/SKILL.md` (its `review_rounds` signal description, and separately its evidence-filter rule — the latter is the behavioral one), `docs/RESULT_SCHEMAS.md`, the `CLAUDE.md` banner, and the `CHANGELOG.md` entry for that release. Flagged MEDIUM drift/workflow in iteration 1 of the review-heal loop — iteration 2 must verify all FIVE surfaces were updated, plus `docs/FAILURE_ESCALATION.md` (the adjudication EXECUTE_CHECKPOINT flow diagram still lacking the hook-required base-fields note that `agents/execute-manager.md` and `skills/async-orchestration/SKILL.md` got — LOW). Surfaces named rather than line-numbered on purpose: this is a re-check list read on a LATER session, so a line number in it is guaranteed to have moved by the time anyone follows it.

8. **`/insights` dashboard section enumeration** (found ST4 review, 2026-06-13): `commands/insights.md` enumerates EVERY dashboard section by name ('Summary ... System Twin hard-signal ... Eval fitness ... System Twin growth ... Recent-sessions ... Cost note'); lines 13/35 restate which signals /insights surfaces. NOT scanned by doc-currency. When build-insights.sh gains a section (e.g. v14.24.0 'Per-version insights'), this enumeration drifts silently — grep commands/insights.md for the section list on any build-insights.sh section add/remove.

9. **SKILLS_INDEX version column vs skill frontmatter** (found v14.24.0 review, 2026-06-13): bumping a skill's frontmatter `version:` (e.g. pr-postmortem 1.2.1→1.3.0) does NOT auto-update its SKILLS_INDEX.md row's version cell — doc-currency only checks the TOTAL skill count, not per-row versions. On any skill version bump, grep SKILLS_INDEX.md for the old version string.

10. **SKILLS_INDEX footer `**Total: N skills**`** (found v14.41.0 /automate holistic review, 2026-06-20): adding a skill row to the SKILLS_INDEX.md table does NOT auto-update the `**Total: N skills**` footer (~line 107) — doc-currency scans the SKILLS_INDEX *header* but NOT this footer total. v14.41.0 added the `automate-loop` row (55→56) but left the footer at "Total: 55 skills" (and `_Last updated:` stale at 2026-06-16). drift_kind=count, capped MEDIUM (cannot FAIL). On any skill add/remove, grep SKILLS_INDEX.md for the old `Total: N` string in addition to the table row.
