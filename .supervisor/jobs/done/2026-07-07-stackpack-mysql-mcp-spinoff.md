# Supervisor Job: Spin off tech-stack skills into `stackpack` + MySQL MCP into `mysql-mcp` (two new sibling plugins)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh, v15.5.0)
- **Git:** clean, branch: main @ 7846db9
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/review-remediation/07-tech-stack-skills-spinoff.md
- **legacy_brief:** true

## Task
**Goal:** Sharpen Loomwright's identity by (a) moving all 18 generic tech-stack skills into a new sibling plugin `stackpack` in the `atelier` marketplace, and (b) moving the bundled read-only MySQL MCP server into a second new sibling plugin `mysql-mcp` (user-expanded scope, confirmed 2026-07-07). Marketplace lists 3 plugins. Loomwright keeps the orchestration core (41 skills), no agents/commands/hooks change, minor version bump to v15.6.0.

**User decisions (recorded):** MOVE all 18 (no deletion of the Next.js cluster); final plugin name `stackpack`; additionally extract the MySQL MCP into its own plugin (`mysql-mcp`).

## The 18 skills moving to stackpack (dependency audit PASSED — none is agent-preloaded)
nextjs-routing, nextjs-components, nextjs-api-routes, nextjs-data-fetching, nextjs-auth, nestjs-controllers, nestjs-services, nestjs-guards, nestjs-typeorm, nestjs-drizzle, gateway-auth-middleware, gateway-correlation, gateway-proxy-patterns, gateway-rate-limiting, mysql, postgresql, redis-caching, docker

**Audit findings (verified by repo-wide grep 2026-07-07):**
- No candidate appears in any agent frontmatter `skills:` list. Preloaded skills (unit-testing, error-handling, ci-cd, monitoring-observability, playwright-e2e, quality-checklist, context7-lookup, qa-*, frontend-ui) all STAY.
- Candidates cross-link only among themselves (nextjs-auth↔nestjs-guards↔gateway-auth-middleware; postgresql↔mysql↔nestjs-typeorm/drizzle↔redis-caching↔docker) — links stay intact inside stackpack.
- Inbound references from STAYING surfaces (must be rewritten, itemized in Subtask 3):
  - `skills/error-handling/SKILL.md` → nestjs-controllers, gateway-auth-middleware (Related-skills lines 25, 255, 257)
  - `skills/unit-testing/SKILL.md` → nestjs-services, mysql, postgresql (lines 25, 200)
  - `skills/monitoring-observability/SKILL.md` → gateway-correlation, redis-caching, docker (lines 210–212)
  - `skills/ci-cd/SKILL.md` → docker (lines 24, 239)
  - `skills/context7-lookup/SKILL.md` → nextjs-routing cache-path examples (lines 63–70) — illustrative cache paths, genericize only if they name `skills/` paths. NOTE: the `/postgresql/{version}` row (~line 218) is a Context7 LIBRARY-ID table row, NOT a skill reference — NO ACTION.
  - `skills/frontend-ui/SKILL.md` → nextjs-components, nextjs-routing (lines 882–883 + refs at 49, 239)
  - `agents/code-reviewer.md` conditional-load instructions (lines 291–292, 351–353 incl. the `skills/gateway-*/SKILL.md` glob at 353) + example at 176 + `skills/gateway-proxy-patterns/SKILL.md` example suggestion at 628
  - `agents/orchestrator.md` illustrative examples (lines 70, 79, 161, 258–294, 376–377)
  - `agents/launch-pad.md` illustrative examples (lines 265, 327–328, 794–796)
  - `agents/plan-reviewer.md` example (line 129)
  - `agents/worker.md` skill-reference table rows (lines ~291–292: nestjs-typeorm, mysql)
  - `commands/code-reviewer.md` skill list (lines 216–218)
  - `commands/orchestrator.md` example (line 49? verify: nextjs-components at 49, 239)
  - `skills/SKILLS_INDEX.md` — 18 rows removed
  - `docs/SPIKES/NORTH_STAR_DIRECTION.md` — the passage describing the tech-stack-skills spin-off idea (search for "catalogued in `SKILLS_INDEX` and cross-reference each other") — add a shipped/status note; use descriptive anchors, not absolute line refs
- NOT skill references (no action): `mysql`/`docker` substring hits in commands/setup.md, skills/setup/SKILL.md, docs/OBSERVABILITY.md, agents/qa-executor.md (docker-compose / MCP-module prose).

## MySQL MCP extraction (Subtask 2)
- MCP wired in TWO places: `loomwright/.mcp.json` AND `loomwright/.claude-plugin/plugin.json` `mcpServers` block. Both move to the new `mysql-mcp/` plugin (own `.claude-plugin/plugin.json` v1.0.0 + `.mcp.json`), removed from loomwright.
- `/setup mysql-mcp` module STAYS in loomwright (status+guidance only) but its guidance text is rewritten: "provided by the mysql-mcp plugin — /plugin install mysql-mcp@atelier" (commands/setup.md lines 17, 78, 300-block; skills/setup/SKILL.md line 49).
- Description surfaces drop "bundled read-only MySQL MCP server": plugin.json + marketplace.json descriptions, CLAUDE.md line 34/47, README, .claude-plugin/README.md, docs/CAPABILITY_BASELINE.json line 47, commands/agent-help.md line 1083.

## Acceptance Criteria
- [ ] Marketplace lists 3 plugins (loomwright, stackpack, mysql-mcp); `bash scripts/validate-version.sh` passes covering ALL plugins.
- [ ] 18 skills `git mv`-ed to `stackpack/skills/`; stackpack has `.claude-plugin/plugin.json` (v1.0.0), `skills/SKILLS_INDEX.md`, minimal README; no agents/commands/hooks.
- [ ] mysql-mcp plugin has `.claude-plugin/plugin.json` (v1.0.0) + `.mcp.json` with the server block; loomwright's `.mcp.json` removed (or emptied) and plugin.json `mcpServers` block removed.
- [ ] Loomwright: zero dangling references to moved skills — repo-wide grep of each moved skill name over `loomwright/` returns only sanctioned mentions (migration notes / "install stackpack" pointers).
- [ ] All agent frontmatter preloads unchanged (diff shows no `skills:` list changes).
- [ ] Skills count 59 → 41 swept across EVERY doc-currency surface + gate blind spots (grep old numbers with flexible separators: "59", "22 hooks" unchanged, "14 agents / 21 commands / 41 skills / 22 hooks").
- [ ] CI gates (validate-version.sh, check-doc-currency.sh, check-skills-index-sync.sh) cover all plugins and pass locally.
- [ ] CHANGELOG + README migration note; loomwright bumped to v15.6.0; descriptions updated IN PLACE (anti-rebloat).

## Outcomes Rubric
- [ ] `ls stackpack/skills/ | wc -l` shows 19 entries (18 skills + SKILLS_INDEX.md) and `ls loomwright/skills/ | grep -c /` equivalent shows 41 skill dirs + index/template.
- [ ] `jq '.plugins | length' .claude-plugin/marketplace.json` == 3.
- [ ] `grep -rn "mcpServers" loomwright/.claude-plugin/plugin.json` returns nothing; mysql-mcp/.mcp.json contains the uvx server block.
- [ ] `for s in <18 names>; do grep -rn "skills/$s/" loomwright/; done` returns zero hits.
- [ ] `bash scripts/validate-version.sh && bash scripts/check-doc-currency.sh && bash scripts/check-skills-index-sync.sh && bash scripts/check-command-sync.sh` all pass.
- [ ] plugin.json version == 15.6.0 == marketplace.json plugins[loomwright].version; CHANGELOG has a v15.6.0 entry with the migration note.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Create stackpack plugin + git mv 18 skills + stackpack index/README/manifest + marketplace registration | ~25 (18 moves + 5 create + 2 modify) | LAUNCHABLE |
| 2 | Create mysql-mcp plugin + move MCP wiring out of loomwright + setup-module guidance rewrite | 3 create, 5 modify | BLOCKED (by #1 — marketplace.json overlap) |
| 3 | Loomwright reference sweep: staying-skill pointers, agent/command examples, SKILLS_INDEX prune, counts 59→41, descriptions, CLAUDE.md/README/CHANGELOG, v15.6.0 bump | ~20 modify | BLOCKED (by #1, #2 — needs final state) |
| 4 | CI multi-plugin coverage: parameterize validate-version.sh + check-doc-currency.sh + check-skills-index-sync.sh; verify all gates green | 3–4 modify | BLOCKED (by #3) |

## Parallelism Analysis
- Sequential execution recommended (`--sequential` semantics): every subtask touches shared manifest/doc surfaces (marketplace.json, SKILLS_INDEX, counts). Batches: S1 → S2 → S3 → S4. Recommended workers: 1.

## Configuration
- Base Branch: main
- Suggested branch: feature/stackpack-spinoff
- Heal iterations: 3 (default)

## Risk Assessment
| Risk | Severity | Mitigation |
|------|----------|------------|
| Doc-currency gate blind spots (counts in prose the gate doesn't scan) | MEDIUM | Grep old value "59" with flexible separators repo-wide (per sweep-grep-gate-variants lesson); consistency_audit auto-expands in Phase 4.5 since diff touches skills/ + metadata |
| `git mv` of 18 dirs breaks context7-lookup cache-path EXAMPLES | LOW | Those are illustrative `.cache/context7/` paths, not skill paths — genericize only if they name `skills/` paths |
| Multi-plugin CI parameterization regresses single-plugin checks | MEDIUM | Run all 5 root scripts locally before PR; keep loops over `jq '.plugins[]'` |
| Plugin-manager UX: users lose skills silently on upgrade | MEDIUM | CHANGELOG + README migration note naming both new plugins with install commands |
| Illustrative example rewrites change agent behavior | LOW | Keep examples but genericize names (e.g. "skills/<domain>/SKILL.md") or point at staying skills; never delete the instructional structure |

## Skills Referenced
- skills/quality-checklist/SKILL.md (gates)
- skills/commit/SKILL.md (conventional commits)

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-07-07-stackpack-mysql-mcp-spinoff.md

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/97 (head 261fd15)
- **heal_loop_ran:** true | **heal_decision:** PASS | **heal_iterations:** 0
- **Advisory fixes applied post-PASS:** 4 (1 MEDIUM duplicate MCP def, 3 LOW)
- **rubric_score:** 6/6
- **Until-mergeable dispatched:** false (suppressed by /automate — engine owns the drain)
