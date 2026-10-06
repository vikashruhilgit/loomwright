# Supervisor Job: Branch mode — scrub-safe brief template + an M1 step 1 that runs on the shipped meta-sync.sh

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes-v2/s3-c
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (branch mode is on — `setup-memory.sh mode` = `on loomwright-meta-s3w1`; every `.supervisor/` run-history file is gitignored on `main` and lives on the metadata branch)
- **Source requirement:** .supervisor/requirements/meta-sync-followups/04-scrub-safe-briefs-and-push-rehearsal.md
- **Base commit:** 3217da0a7fa49a315d60625321be2ae6b20637b9

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown prompt/skill edits + one changelog fragment; no code |
| 2 | Dependency Availability | GO | `meta-sync.sh` (init/pull/push/status, `--root`, `--paths-from`) is shipped; option A needs no new flag |
| 3 | Architecture Fit | GO | The brief template's single home is `skills/supervisor-readiness/SKILL.md`; the other files only carry examples |
| 4 | Scope vs Supervisor Capability | GO | 10 modify + 1 create in the code PR, plus 5 gitignored metadata-branch files — single subtask, below the Decomposition Threshold |
| 5 | Hard Blockers | CAUTION | The runbook files (`operator-run/*.md`, `00-overview.md`) are gitignored in branch mode, so they are NOT in a worktree checkout and NOT in the PR diff — they are edited in the primary checkout and reach `loomwright-meta` only through a `meta-sync.sh push` (see Risk Assessment) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Make a brief written from the Supervisor-Ready Brief template pass the `meta-sync.sh` scrub (no `home_path` hit), remove the `/Users/<name>/...` examples from the agent/command/skill prompts, and replace M1 step 1 with a rehearsal recipe (owner chose option A, 2026-10-05) that names only commands and flags the shipped `meta-sync.sh` has.

**Problem Statement:**
Every `/automate` lane in branch mode needs its closeout records (done brief, requirement stamp, run file, ledger line) to reach `loomwright-meta` through `meta-sync.sh push`, which fails CLOSED on the `home_path` scrub rule (`/(Users|home)/<name>/`).
Currently, the brief template asks for `- **Project:** {absolute path}` and Launch Pad / agent-output examples show `/Users/<name>/...`, so a brief that follows the template makes the whole lane's trail push exit 2 (lane v2-b lost its closeout push this way on 2026-10-04). Separately, M1 step 1 tells the operator to run `meta-sync.sh push --dry-run`, a flag that does not exist.
Success looks like: a template-shaped brief pushes through the scrub cleanly, `grep -rn '/Users/name' loomwright/agents loomwright/commands loomwright/skills` returns nothing, and M1 step 1 is a command sequence that runs on the shipped script and reaches `push` exit 0 on a scratch clone.

## Acceptance Criteria
- [ ] Given the updated template in `loomwright/skills/supervisor-readiness/SKILL.md`, when its `- **Project:**` line is read, then it asks for the home-relative form (`~/...` when the checkout is under `$HOME`, else the repo directory name) and states that an absolute `/Users/<name>/` or `/home/<name>/` path ANYWHERE in a brief (not only on this line — the scrub reads the whole file) trips the `meta-sync.sh` `home_path` scrub and blocks the lane's whole trail push; the same one-sentence rule appears in `agents/launch-pad.md` Phase 5 PACKAGE so the brief author sees it at assembly time.
- [ ] Given `loomwright/agents/launch-pad.md`, `loomwright/commands/launch-pad.md`, `loomwright/skills/agent-output/SKILL.md`, `loomwright/agents/orchestrator.md`, `loomwright/agents/supervisor.md`, `loomwright/commands/orchestrator.md`, `loomwright/commands/supervisor.md`, `loomwright/commands/code-reviewer.md` and `loomwright/commands/product-owner.md`, when `grep -rn '/Users/name' loomwright/agents loomwright/commands loomwright/skills` runs, then it returns nothing (each example rewritten to a `~/...` form, or a placeholder that is not `/(Users|home)/<word>/`).
- [ ] Given a brief rendered from the updated template (a fresh instance: fill every `{…}` placeholder of the template with realistic values, `Project:` in the home-relative form), when it is placed under `.supervisor/jobs/done/` of a scratch clone and `meta-sync.sh push --root <clone>` scrubs it against a local bare remote, then the push reports no `home_path` hit and exits 0. (The scrub reads the WHOLE file, not one field — every brief must be scrub-clean end to end, which is why this brief writes the placeholder `/Users/<name>/`.)
- [ ] Given `.supervisor/requirements/parallel-automate/operator-run/M1-migrate-this-repo.md` in the PRIMARY checkout, when its `## Steps` item 1 is read, then it is the option-A rehearsal recipe — scratch clone, `git init --bare` scratch remote, re-point the clone's `origin`, copy `.supervisor/config.json` into the clone (the scrub's `setup_memory.repo_allowlist` lives there), `meta-sync.sh init --root <clone>` + `meta-sync.sh push --root <clone>`, iterate until `push` exits 0 — and it names no flag absent from `meta-sync.sh --help` (no `--dry-run`).
- [ ] Given the M1 step-1 recipe followed literally on a scratch clone of the current `main` with NO extra payload (nothing pushed to GitHub), when `push` runs, then it exits 0 — record the exact commands run and their exit codes in the worker result.
- [ ] Given `M1-migrate-this-repo.md`, `S1-two-lane-spike.md`, `S2-five-lane-spike.md`, `S3-stabilization-wave-spike.md` and `parallel-automate/00-overview.md` in the primary checkout, when read, then each carries ONE line stating that every command in an `operator-run/` runbook is checked against the shipped script's usage text (`<script> --help`) before the runbook is used — no checker script is built.
- [ ] Given the plugin-file changes, when `changelog.d/` is listed, then it carries `meta-sync-followups-04-scrub-safe-briefs-and-push-rehearsal.md` (patch), and no version file (`plugin.json`, `marketplace.json`, `CHANGELOG.md`) is hand-edited.
- [ ] Given the finished change, when `bash scripts/ci-local.sh` runs, then it is green.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Scrub-safe `Project:` template + examples, M1 step-1 rehearsal recipe, runbook-check line | all | 10 modify, 1 create (code PR) + 5 modify (gitignored, primary checkout) | `skills/supervisor-readiness/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "changelog.d/meta-sync-followups-04-scrub-safe-briefs-and-push-rehearsal.md"}
  - {kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "## Supervisor-Ready Brief Template"}
requires: []
lanes:
  - "loomwright/skills/supervisor-readiness/SKILL.md"
  - "loomwright/agents/launch-pad.md"
  - "loomwright/commands/launch-pad.md"
  - "loomwright/skills/agent-output/SKILL.md"
  - "loomwright/agents/orchestrator.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/commands/orchestrator.md"
  - "loomwright/commands/supervisor.md"
  - "loomwright/commands/code-reviewer.md"
  - "loomwright/commands/product-owner.md"
  - "changelog.d/meta-sync-followups-04-scrub-safe-briefs-and-push-rehearsal.md"
external_requires: []
```

**Worker notes (data for the one worker):**
- Template line: change `- **Project:** {absolute path}` in `skills/supervisor-readiness/SKILL.md`'s brief template to the home-relative form, with the reason (the `meta-sync.sh` `home_path` scrub fails the WHOLE trail push). Re-checked 2026-10-05: no script under `loomwright/scripts` or `loomwright/hooks` parses the `Project:` value (only test fixtures `test-verify-provides.sh` / `test-context-digest.sh` carry one, with `/nowhere` and `/tmp/demo` — neither is a home path; leave them). `skills/context-setup/SKILL.md`'s "Project path identified" is about locating the project, not the brief value — no change.
- Examples: the 12 `/Users/<name>/...` hits in the 9 listed agent/command/skill files. Rewrite to `~/my-project`-style. Do not touch `loomwright/docs/RESULT_SCHEMAS.md` or `scripts/result-validator-fixtures/*` (worktree paths in result examples, outside this item's acceptance grep — out of scope, note them in the result as a follow-up candidate).
- Out-of-PR outputs (not lane-tracked, not in the diff): `.supervisor/requirements/parallel-automate/operator-run/{M1-migrate-this-repo,S1-two-lane-spike,S2-five-lane-spike,S3-stabilization-wave-spike}.md` and `.supervisor/requirements/parallel-automate/00-overview.md`. They are gitignored on `main` (branch mode), so they are absent from a worktree. Resolve the primary checkout with `git worktree list --porcelain` (first entry) and edit them there; never `git add` them. Do NOT run `meta-sync.sh push` against `origin` — the engine publishes them to `loomwright-meta` after merge.
- Rehearsal: run it in a `mktemp -d` scratch dir only (clone of the primary checkout's `main`, `git init --bare` remote, `git -C <clone> remote set-url origin <bare>`, copy `.supervisor/config.json`, `meta-sync.sh init --root <clone>`, then place a freshly rendered template instance under `<clone>/.supervisor/jobs/done/` and `meta-sync.sh push --root <clone>`). Nothing may reach GitHub. Delete the scratch dir afterwards.

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/supervisor-readiness/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): the five runbook files are gitignored metadata-branch files, invisible in a worker worktree and in the PR diff, so the code review cannot see them | MEDIUM | Worker edits them in the primary checkout (resolved via `git worktree list --porcelain`) and reports a unified diff of each in its result; the engine publishes them with `meta-sync.sh push --paths-from` after the PR merges |
| The rehearsal accidentally publishes to GitHub | HIGH | Re-point the scratch clone's `origin` to a local bare repo BEFORE `init`; always pass `--root <clone>`; verify `git -C <clone> remote get-url origin` is the bare path before each meta-sync call |
| An example rewrite reintroduces another scrub hit (e.g. `/home/<word>/`) | LOW | Re-run the scrub regex `/(Users|home)/[A-Za-z0-9._-]+/` (case-insensitive) over the 10 edited files before finishing |
| Doc-currency / citation-drift gates on edited prompt files | LOW | Pure in-place line edits, no line insertions above pinned citations expected; `bash scripts/ci-local.sh` before push |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-05-scrub-safe-briefs-and-push-rehearsal.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-05T12:28:12Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/391
- **Branch:** feature/meta-sync-followups-04-scrub-safe-briefs
- **Files changed:** 11
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Home-relative Project: template + whole-brief home-path rule (template + Launch Pad Phase 5 action 3b); 12 example home paths rewritten; changelog fragment. Out-of-PR: M1 step 1 option-A rehearsal recipe and a --help usage-check line in M1/S1/S2/S3/00-overview (gitignored, metadata branch). Phase 4.5 consistency_audit PASS (1 MEDIUM dismissed below the fix floor: the scrub regex is case-insensitive and unanchored, so /users/<x>/ API routes also trip it, and the new rule sentence understates that). ground_truth 2/2 pass; contract_conformance skipped (no twin store at review time).

## Not verified
- **loomwright/docs/RESULT_SCHEMAS.md and scripts/result-validator-fixtures/execute-*-valid.md /Users/<name>/ worktree paths** — out of this item's scope; follow-up candidate (subtask 1)
- **loomwright/docs/SPIKES/LOOP_EVIDENCE_2026-07.md absolute home path** — outside the acceptance grep; follow-up candidate (subtask 1)
- **A live /launch-pad assembly with the new template** — only a hand-rendered instance went through the scrub (subtask 1)
- **ci.yml sdk-spike step** — ci-local does not run it; CI does (subtask 1)
