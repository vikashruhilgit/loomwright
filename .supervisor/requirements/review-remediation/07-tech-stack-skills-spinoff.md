# 07 — Spin off generic tech-stack skills into a second marketplace plugin (P1/P2, large)

## Goal
Sharpen Loomwright's identity ("orchestration Twin", not "framework notes grab-bag") by
moving the ~18 generic tech-stack skills into a sibling plugin in the same `atelier`
marketplace, keeping the orchestration core (~34 skills) + product/discovery (5) in
loomwright. Users who want the stack references install both.

## Evidence
- ~17/57 skills are vanilla framework reference: nextjs-{routing,components,api-routes,
  data-fetching,auth}, nestjs-{controllers,services,guards,typeorm,drizzle},
  gateway-{auth-middleware,correlation,proxy-patterns,rate-limiting}, mysql, postgresql,
  redis-caching, docker (verify the exact list at plan time — categorize each of the 57;
  borderline ones like unit-testing, error-handling, ci-cd, monitoring-observability,
  playwright-e2e are PRELOADED into agents and must STAY in loomwright).
  NOTE: `frontend-ui` STAYS — item 10 (design-system substrate) Part B gives it an
  orchestration role (worker digest / possible preload for UI-path subtasks).
- These duplicate what context7-lookup (bundled, preloaded into Code Reviewer + Launch Pad)
  serves fresher; they encode the maintainer's own stack and stale silently.
- The marketplace wrapper (`.claude-plugin/marketplace.json`) already supports multiple
  plugins — this was its stated design purpose.

## Hard precondition — the preload/reference audit
Before moving anything, grep every candidate skill name across `loomwright/agents/*.md`
frontmatter `skills:` lists, `loomwright/skills/*/SKILL.md` cross-references (e.g.
nestjs-guards ↔ gateway-auth-middleware ↔ nextjs-auth are cross-linked), commands, and
docs. A skill that is preloaded by any agent, or referenced by a skill that stays, either
stays too or the reference is rewritten. Produce the dependency table in the plan and get
it Plan-Reviewed before executing.

## Scope
1. New nested plugin dir (working name `stackpack/` — pick final name at plan time) with its
   own `.claude-plugin/plugin.json` (v1.0.0), its own skills/ + SKILLS_INDEX.md, minimal
   README. No agents, no commands, no hooks in v1.
2. Register it in `.claude-plugin/marketplace.json` alongside loomwright.
3. `git mv` the cleared candidate skills; update loomwright's SKILLS_INDEX.md, skills count
   (57 → 57-N) on EVERY doc-currency surface + the gate's blind spots (grep the old number
   with flexible separators, per memory "sweep-grep-gate-variants").
4. Cross-plugin references: any remaining loomwright skill/doc that pointed at a moved
   skill gets either (a) the pointer rewritten to "install <stackpack> for X", or (b) the
   content inlined if tiny. NEVER a `${CLAUDE_PLUGIN_ROOT}` path into the other plugin.
5. CI: extend validate-version.sh / check-doc-currency.sh / check-skills-index-sync.sh to
   cover both plugins (or parameterize by plugin dir). Both plugins' checks run on PR.
6. README/CHANGELOG: migration note for existing users ("skills X moved to
   <stackpack>@atelier; install it if your workers relied on them"). Loomwright minor bump.

## Constraints / invariants
- Preloaded skills and orchestration-referenced skills DO NOT MOVE (see precondition).
- Counts: agents/commands/hooks unchanged; skills count changes → full sweep; plugin
  descriptions updated in place (anti-rebloat).
- No behavior change to any agent: after the move, spawn-time preloads must resolve
  identically (verify with a local /plugin uninstall+install + /agent-help smoke).
- Decision point to surface at plan time (AskUserQuestion): move vs DELETE the Next.js
  cluster outright — deletion is defensible since context7-lookup covers it; moving
  preserves them for existing users. Default recommendation: move (reversible).

## Acceptance criteria
- [ ] Dependency table produced and Plan-Review PASSed before any file moves.
- [ ] Marketplace lists 2 plugins; both install cleanly locally
      (`/plugin install loomwright@atelier` + `/plugin install <stackpack>@atelier`).
- [ ] Loomwright: zero dangling references to moved skills (repo-wide grep of each moved
      skill name attached to PR); all CI gates green with the new count.
- [ ] All agent preloads intact (diff of agent frontmatter shows no changes, or only
      justified reference rewrites).

## Out of scope
Adding new tech-stack skills (Prisma/GraphQL/gRPC stay "on demand"), restructuring the
orchestration skills, stackpack agents/commands.

## Status: done
(completed 2026-07-07 via /automate → PR #97, v15.6.0)
