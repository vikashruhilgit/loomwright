# 03 — Doc hygiene: SKILLS_INDEX parity + CI check, roadmap de-staling (P0, small)

## Goal
Stop two documented drift sources: SKILLS_INDEX.md version cells (already drifted twice)
and the stale IMPROVEMENTS_ROADMAP.md whose P0 items describe already-solved problems.

## Evidence (re-verified 2026-07-06 post-v15.2.0)
- `loomwright/skills/SKILLS_INDEX.md`: supervisor-readiness row STILL drifted (index
  1.1.1 vs actual 1.1.2). automate-loop is NOW ALIGNED at 1.2.0 (fixed in the v15.2.0
  work) — which proves the failure mode is recurring: rows drift whenever a release
  touches a skill and only get fixed when a release happens to sweep them. The CI parity
  check is the durable fix, not the row edit. CLAUDE.md itself lists "per-row skill
  version cells in SKILLS_INDEX.md" as a known doc-currency-gate blind spot.
- `loomwright/docs/IMPROVEMENTS_ROADMAP.md` P0-1/P0-2 ("per-agent hooks silently ignored —
  plugin may be broken today") are RESOLVED by the hooks.json centralization; 2026-07-05
  review verdict: of 19 items ~12 implemented, 3 deferred-by-design, 4 open (Red Team
  `effort: high`, WorktreeRemove hook, RED_TEAM_RESULT formal schema, AGENT_GUIDELINES
  full version sweep). An agent or contributor trusting this doc will re-litigate solved work.

## Scope
1. **Fix drifted index rows** — as of 2026-07-06 only supervisor-readiness (→ 1.1.2);
   re-verify ALL rows against frontmatter at execution time (drift recurs per release).
2. **New CI check `scripts/check-skills-index-sync.sh`** (repo-root scripts/, alongside
   check-doc-currency.sh): for every `loomwright/skills/*/SKILL.md` with a `version:`
   frontmatter field, assert SKILLS_INDEX.md contains a row for that skill whose version
   cell matches. Fail with a per-skill diff list. Also assert no index row references a
   nonexistent skill dir. Bash-3.2-safe, no network. Wire it into `.github/workflows/ci.yml`
   next to the other validators (hard gate).
3. **De-stale IMPROVEMENTS_ROADMAP.md**: add a dated banner at top:
   "Planning snapshot (pre-hooks.json-centralization). Verified 2026-07-05: P0-1, P0-2,
   P1-7, P3-16, P3-17 RESOLVED; P1-3, P1-5, P1-8, P2-9, P2-10, P2-11, P3-18 deferred by
   design; OPEN: P1-4 (Red Team effort), P1-6 (WorktreeRemove hook), P2-13 (RED_TEAM_RESULT
   schema), P3-15 (AGENT_GUIDELINES sweep). Current state authority: CLAUDE.md + hooks.json
   + plugin.json." Then add an inline `**[VERDICT: RESOLVED/DEFERRED/OPEN — evidence]**`
   line under each item header. Re-verify each verdict against the repo before stamping —
   do not copy the review's table blindly.
4. **Add `/setup` to Quick Start**: one line in README.md + .claude-plugin/README.md Quick
   Start: "Optional next: run `/setup` for a status dashboard and guided configuration of
   optional capabilities (observability, telemetry, notifications, Twin bootstrap)."

## Constraints / invariants
- The new CI check must NOT scan dated changelog entries or example blocks — it reads only
  SKILL.md frontmatter vs index rows (structural, not phrasing-based, so no false positives).
- If fixing an index row requires touching a SKILL.md `lastUpdated`, don't — index follows
  skill, never the reverse.
- Counts unchanged. Patch version bump + CHANGELOG entry. Keep roadmap edits additive
  (banner + verdict lines), do not delete item bodies — they hold design rationale.

## Acceptance criteria
- [ ] check-skills-index-sync.sh exists, green in CI, and demonstrably fails when a version
      cell is wrong (include a one-shot negative test in the script's own test or PR proof).
- [ ] Zero drifted rows in SKILLS_INDEX.md at merge time.
- [ ] Roadmap banner + per-item verdicts present; every OPEN verdict cites a file path.
- [ ] /setup line present in both READMEs; doc-currency + command-sync + version validators green.

## Out of scope
Actually closing the 4 OPEN roadmap items (item 06 handles two of them), restructuring
SKILLS_INDEX categories (item 07 territory).

## Status: done
- Completed 2026-07-06 via /automate → PR #93 (v15.2.3), Phase 4.5 PASS, heal_iterations 1 (LOW NOTE precision fix).
