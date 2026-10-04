# 05 — Docs & hygiene sweep (stale platform premises, one code-level path bug, frontmatter defects)

## Problem
Validation against Claude Code v2.1.284's docs and the repo at `a262d00` found prose that states things the
platform or the code no longer does. Each is a "claim no check backs" (memory
`rules-violated-by-their-own-surrounding-text`); agents read these as instructions, so a stale premise is a bug.

1. **"Subagents cannot spawn subagents" is stale.** The docs now say a subagent "can spawn subagents of its own, up
   to three layers below the main conversation" (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`). The premise is still
   stated as a hard platform rule at `commands/supervisor.md:5`, `commands/launch-pad.md:5`,
   `commands/review-pr.md:5`, `skills/review-heal/SKILL.md:79-84`, `agents/review-pr.md:43`, `docs/PITFALLS.md:14`,
   `docs/ARCHITECTURE_CONTRACTS.md:35`. Meanwhile the repo also *relies* on nesting in three places
   (`autonomous-loop/SKILL.md:453` → review-heal Task spawns; `commands/qa-executor.md:15` → `agents/qa-executor.md`
   spawns `qa-strategist`; `ARCHITECTURE_CONTRACTS.md:139,169-170` inline Supervisor → Execute Manager → workers),
   so the docs contradict both the platform and themselves.
2. **"Task ignores a per-call `model:`" is stale.** `agents/rubric-grader.md:96` and
   `skills/self-heal-advisory/SKILL.md:1035-1036` say it; the docs say the per-invocation `model` parameter is
   resolved FIRST and persists on resume — which is what `--cheap` (`supervisor.md:240,287,315,356`) depends on.
3. **review-heal misstates the drain's permission flags.** `skills/review-heal/SKILL.md:72` says the dispatcher adds
   "**no** `--permission-mode`"; `scripts/dispatch-pr-review.sh:251,921` pins `dontAsk` + `--allowedTools` /
   `--disallowedTools`.
4. **Wrong agent-memory directory name — in code, not just docs.** On disk the dirs are
   `.claude/agent-memory/loomwright-loomwright-<role>/`. `scripts/setup-memory.sh:182-183` (`INTENDED_PATHS`),
   `CLAUDE.md:111` and `commands/dreaming.md:206,232` use `loomwright:<agent>`, so `setup-memory.sh`'s intended
   paths point at directories that never exist.
5. **Contradictory `## Session` writer rules.** `agents/supervisor.md:66,203` and `agents/context-keeper.md:26,56`
   say `## Session` is derived by `build-state.sh`; `ARCHITECTURE_CONTRACTS.md:140` allows "the inline main-thread
   Supervisor … best-effort direct write" and `:226` says "inline Supervisor writes `## Session` directly".
6. **Frontmatter defects.** `skills/commit/SKILL.md:2` `name: commit-skill` (dir is `commit`; the only mismatch);
   `skills/agent-output/SKILL.md:4` `allowed-tools: None`; `skills/SKILL_TEMPLATE.md` puts its frontmatter after the
   heading with no `name`/`description`; `stackpack/skills/nestjs-drizzle/SKILL.md` is named
   `nestjs-repository-patterns`.
7. **Overclaimed status note.** `.supervisor/requirements/twin-remediation/10-harness-portability.md:132-133` says
   the "ONE adapter spike" shipped (PR #239 / #237); its own acceptance criterion requires one complete requirement
   flow end-to-end under a second harness, which no PR has done.

## Goal
Every statement above matches the platform docs and the code, with the source and date cited; the memory-path bug
is fixed in code; the frontmatter is valid.

## Scope
1. **Nesting premise**: rewrite each cited statement to the current fact ("Claude Code allows subagent nesting up to
   three layers by default, configurable via `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` — per code.claude.com
   sub-agents docs, read 2026-09-30; earlier releases did not"). Look up the release that introduced nesting in the
   Claude Code changelog; cite it if found, else cite the doc read date. Keep every existing *design* choice
   (inline commands, `-runner` agents, the "inline /supervisor runs the worker loop itself" rule) but state its
   REAL reason where the old reason was the no-nesting rule; where no other reason exists, say
   "retained pending owner review; see agnostic-phase1/05" rather than inventing one. Make
   `ARCHITECTURE_CONTRACTS.md:139,169-170` consistent with `agents/supervisor.md`'s actual Phase 3 instructions
   (read both; the agent prompt is the executable truth — the contracts doc follows it).
2. **Per-call model**: correct rubric-grader and self-heal-advisory to match the docs and `--cheap`.
3. **review-heal:72**: describe the pinned permission regime accurately, pointing at `dispatch-pr-review.sh`'s
   header rather than restating flag lists.
4. **Memory path**: fix `setup-memory.sh` `INTENDED_PATHS` to the real on-disk form (derive the sanitisation rule
   from the observed dirs; do not hard-code a single role) and update `CLAUDE.md:111` + `commands/dreaming.md`.
   Add a test that `setup-memory.sh`'s intended paths match the dir naming used by the existing
   `.claude/agent-memory/` entries in the repo.
5. **`## Session` writer**: reconcile `ARCHITECTURE_CONTRACTS.md:140,226` with the agent prompts (Context-Keeper
   `initialize` seeds once; `build-state.sh` projects thereafter); if the inline direct-write path is real
   behaviour, it must appear in `supervisor.md` too — otherwise remove it from the contracts doc.
6. **Frontmatter**: `commit` name → `commit`; `agent-output` `allowed-tools` → the tools it actually needs or remove
   the key (check what an absent key means for skills and pick the documented form); `SKILL_TEMPLATE.md` → valid
   leading frontmatter with placeholder `name`/`description`; stackpack `nestjs-drizzle` name → `nestjs-drizzle`
   (grep for any reference to the old name first).
7. **twin-remediation/10 note**: amend to "a review-lens provider seam shipped (PR #239) and an orca mirror (PR #237);
   the end-to-end second-harness spike in §5 has NOT been done" — keep `## Status: pending`.
8. Sweep for other occurrences of each stale phrase (grep variants, memory `sweep-grep-gate-variants`) and fix them
   in the same pass; list every file touched in the PR body.
9. Docs-currency: CHANGELOG, version bump, token budgets for any grown agent prompt.

## Non-goals
Changing orchestration behaviour (removing the `-runner` split, making inline Supervisor spawn Execute Manager, or
any spawn change) — those are owner decisions for Phase 2. Fixing `lens-run.sh`'s gemini provider JSON mismatch
(provider-table work is Phase 2). Editing CHANGELOG history or `docs/SPIKES/` frozen surfaces.

## Acceptance criteria
- `grep -rn -i "cannot spawn further subagents\|subagents cannot spawn" loomwright CLAUDE.md` → 0 (or only lines
  that state it as a historical/pre-release fact with a version).
- `grep -n -i "silently ignored" loomwright/agents/rubric-grader.md` → no per-call-model claim;
  same for `self-heal-advisory/SKILL.md`.
- `grep -n "no\*\* \`--permission-mode\`" loomwright/skills/review-heal/SKILL.md` → 0.
- `grep -rn "agent-memory/loomwright:" loomwright CLAUDE.md` → 0; the new setup-memory test passes.
- Every `loomwright/skills/*/SKILL.md` and `stackpack/skills/*/SKILL.md` has `name` == its directory name
  (add this as a check if no existing test covers it).
- `test-citation-drift.sh`, `check-doc-currency.sh`, full test loop + root checks green.

## Verified premises (re-check before starting)
- All line numbers above verified at `d927996`; files unchanged at `a262d00` except none of the cited ones (the
  `d927996..a262d00` diff touched only automate-helpers/-merge-watch/-trail, TELEMETRY.md, automate-loop SKILL,
  plugin.json). Re-grep before editing — line numbers move.
- On-disk memory dirs: `ls -d .claude/agent-memory/*/` ⇒ `loomwright-loomwright-{code-reviewer,qa-executor,
  red-team-reviewer}`.
- Claude Code docs (read 2026-09-30): sub-agents page (nesting depth 3; per-invocation `model` first in resolution
  order).

bump = write a `changelog.d/` fragment and run `scripts/bump-version.sh`

## Status: pending

## Depends on
01

## Touches
loomwright/commands/supervisor.md
loomwright/commands/launch-pad.md
loomwright/commands/review-pr.md
loomwright/commands/autonomous.md
loomwright/commands/automate.md
loomwright/commands/agent-help.md
loomwright/commands/dreaming.md
loomwright/agents/review-pr.md
loomwright/agents/supervisor.md
loomwright/agents/rubric-grader.md
loomwright/skills/review-heal/SKILL.md
loomwright/skills/autonomous-loop/SKILL.md
loomwright/skills/self-heal-advisory/SKILL.md
loomwright/skills/commit/SKILL.md
loomwright/skills/agent-output/SKILL.md
loomwright/skills/SKILL_TEMPLATE.md
loomwright/docs/PITFALLS.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/vendor-coupling-manifest.json
loomwright/scripts/dispatch-pr-postmortem.sh
loomwright/scripts/setup-memory.sh
loomwright/scripts/test-setup-memory.sh
loomwright/scripts/test-harvest-conventions.sh
loomwright/scripts/test-skill-frontmatter.sh
stackpack/skills/nestjs-drizzle/SKILL.md
CLAUDE.md
changelog.d/agnostic-phase1-05-docs-and-hygiene-sweep.md
