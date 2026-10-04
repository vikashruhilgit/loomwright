# 14 — The lanes pane as an optional, installable add-on (Claude adapter; nothing depends on it)

## Status: parked (waits on item 05 — it needs `lane-status --json`, `lane-answer` and Scope 15's merge-readiness field)

## Problem
Owner (2026-10-04, after using it): "the /lanes command you build here — should that be a part of harness/plugin? …
do we have requirement for this? … is this temporary?" It is temporary today:
- In S1 v1 the pane was written as a session dev mod (`s1-lanes`) and not loaded; in S1 v2 it was repointed and
  hot-reloaded, used as a status view; in wave w1 it was rebuilt as `lanes` with a per-lane **Details** toggle (last
  20 steps) and question buttons. It lives only in that session's private mods folder
  (`~/.claude/dev-mods/<session>/lanes/`), loads only through that session's hot reloading, and talks to the spike
  harness (`s1h.sh status --json`, `s1h.sh recent`, `s1h.sh answer`), which item 05 replaces.
- The requirement set mentions a pane only as one optional client (05 Scope 13) and describes what it shows (05
  Scope 15). Nothing says how it ships, installs, or is tested.

## Goal
Anyone running parallel lanes in Claude Code can install a lanes pane that shows every lane live and answers lane
questions — while the lanes, the core scripts and every other harness behave identically with it uninstalled
(decision P9).

## Design (decided here; P9 rules apply verbatim)
- **A separate, opt-in sibling plugin in this marketplace** (working name `loomwright-lanes`), like `stackpack` and
  `mysql-mcp` — NOT inside `loomwright/`, so installing Loomwright never loads it and its Claude-only code stays out of
  the core.
- **It reads and writes only through item 05's core commands:** `lane-status --json` for state (including Scope 14's
  last actions / stalled state / CI-slot position and Scope 15's merge-readiness score), `lane-feed <lane>` (or a
  `--recent N` form) for the Details view, `lane-answer <lane> <id>` for every answer. It never reads lane files
  directly, never launches or resumes a lane itself (P9 rule 5), never holds state that matters (P9 rule 3).
- **What it shows** (the w1 prototype, kept): a `/lanes` command opening a pane; a status-line summary; a toast when
  a lane starts waiting; per lane: state glyph (running / waiting for you / stalled / parked + reason), item, PR,
  branch, last progress, last 3 actions, a Details toggle with the last ~20 steps, merge-readiness (`ready 5/5` or the
  failing checks), and the question with one button per option plus a send button that refuses until every question
  has exactly one option picked. Refresh every 15 s; an action refreshes at once.
- **Failure is fail-safe:** a failing `lane-status` call shows "status unavailable" and changes nothing; a refused
  answer shows `lane-answer`'s refusal text verbatim.

## Scope
1. **Packaging spike first (read before building):** verify on the current Claude Code build how a marketplace
   plugin ships a function-hooks module (`hooks/hooks.json` with `"modules"`), that a normal install loads it with no
   hot-reload step, and what `claude plugin validate` and `claude plugin test` check for it. Record the findings in
   this file. If a normal install cannot load a module, stop and report instead of working around it.
2. **The plugin:** `loomwright-lanes/` with `.claude-plugin/plugin.json`, `hooks/hooks.json`, `hooks/register.tsx`,
   `types/index.d.ts` (the `$.state` contract), `README.md` (what it is, that it is optional, the plain fallback:
   `lane-status --watch` + answering in the main session). Ported from the w1 prototype with the harness calls
   replaced by item 05's commands. No absolute paths: the core scripts are found through the installed Loomwright
   plugin's root or `PATH` (decide in step 1; never this repo's `scripts/`).
3. **Marketplace + docs:** add the plugin to `.claude-plugin/marketplace.json`; update the surfaces that enumerate
   the sibling plugins (`CLAUDE.md` §"Plugin Layout", `README.md`, `.claude-plugin/README.md`) and anything
   `scripts/check-doc-currency.sh` counts.
4. **Vendor coupling:** the plugin is Claude adapter code; record it in `loomwright/docs/vendor-coupling-manifest.json`
   the way the ratchet requires, so it is counted, not hidden.
5. **Tests:**
   - a static test (`scripts/test-lanes-addon.sh`): the module's every `$.process.run` argv starts with
     `lane-status`, `lane-feed` or `lane-answer` (no other command, no lane file paths); `claude plugin validate` passes
     where `claude` is available (skip with a stated reason in CI if not, never a silent pass);
   - **the P9 test, required:** item 05's lane round trip (launch → question → answer by file / main session →
     resume → park) passes with the add-on NOT installed, and the core suites run with no add-on loaded (P9 rule 7);
   - a fixture `lane-status --json` with a waiting lane renders the question with its exact option labels.

## Non-goals
- No new lane behaviour, no state, no merge actions (P1, P5). No pane for other harnesses (P9: they use the plain view).
- Not the Floor (`/ui`): the Floor is a browser run view; this is an in-session pane. They may later share
  `lane-status --json`.

## Acceptance criteria
- Installing `loomwright-lanes` from the marketplace in a fresh session gives a working `/lanes` pane over a real
  two-lane run; uninstalling it changes nothing about that run.
- `grep` over the plugin shows no read of lane files and no command other than the three core lane commands.

## Validation (must pass before merge)
1. Baseline full loop on base and branch, `<passed>/<total>` and `SKIP` counts.
2. Unchanged path: Loomwright's own suites and `check-vendor-coupling.sh` pass with the add-on absent.
3. Running system: a real two-lane wave; paste the pane (screenshot or text render) with one lane waiting, the answer
   sent through it, and the lane's answer file showing `via: lanes-addon`.
4. A failure this must catch: a module change that reads a lane's run file directly ⇒ the static test fails.
5. Rollback: remove the plugin from the marketplace (`git revert`); nothing else depends on it.

## Verified premises (re-check before starting)
- Marketplace today lists three plugins (`loomwright`, `stackpack`, `mysql-mcp`) in `.claude-plugin/marketplace.json`.
- The w1 prototype: `~/.claude/dev-mods/07b3f63c-0dc0-4bf9-82c3-1b14ef791064/lanes/` (validated with
  `claude plugin validate`, 2026-10-04); the S1 v1 original: `~/.claude/dev-mods/0d556d54-…/s1-lanes/`.

## Evidence
S1 run record (v1 mod written, v2 repointed and loaded, visibility test) and wave w1 (owner used `/lanes`, asked for
details, live tracking, and this item).

## Depends on
05

## Touches
loomwright-lanes/.claude-plugin/plugin.json
loomwright-lanes/hooks/hooks.json
loomwright-lanes/hooks/register.tsx
loomwright-lanes/types/index.d.ts
loomwright-lanes/README.md
.claude-plugin/marketplace.json
.claude-plugin/README.md
README.md
CLAUDE.md
scripts/check-doc-currency.sh
scripts/test-lanes-addon.sh
loomwright/docs/vendor-coupling-manifest.json
changelog.d/parallel-automate-14-lanes-pane-addon.md
