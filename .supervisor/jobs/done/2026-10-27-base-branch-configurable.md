# Supervisor Job: Configurable base branch — one resolver, every script and prompt consumer, `/setup base-branch`, explicit `/setup --help`

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-27-125907/L1
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (source requirement lives under the gitignored `.supervisor/` tree, so its provenance is not git-verifiable)
- **Source requirement:** .supervisor/requirements/provider-routing/01-base-branch-configurable.md
- **Base commit:** 84d9023b2d7561c3c34929df3e64696bad7b2339

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Portable bash 3.2 + jq + git + optional gh; the same stack as every sibling script |
| 2 | Dependency Availability | GO | No new dependency; `gh` is optional (resolver step 5) |
| 3 | Architecture Fit | GO | A single script authority matches the plugin's "one authority, pointers elsewhere" convention (`fix-floor.sh resolve` is the precedent) |
| 4 | Scope vs Supervisor Capability | CAUTION | The File Impact Map total (scripts, prompts, `/setup`, tests) is well over the `context-bound` bound, so the brief splits it into 6 subtasks |
| 5 | Hard Blockers | CAUTION | A behaviour change: repos that relied on the silent `main` fallback now stop with a named status. Test fixtures that build repos with no origin/HEAD must be given one (or a config key) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Resolve the base branch once, through a new `loomwright/scripts/resolve-base-branch.sh`, and make every script consumer, every agent/skill prompt, `/setup base-branch` and an explicit `/setup --help` use that single resolver.

**Problem Statement:**
A maintainer running Loomwright on a repo whose integration branch is not `main` (e.g. `development`) needs every stage — Supervisor, `/automate` lanes, waves, trail PRs, the rubric grader, resume and self-heal — to branch from, target and diff against the same branch.
Currently the base is resolved in four unrelated ways: Supervisor (`supervisor-next-step.sh`) falls back to a hardcoded `main`, the `/automate` modules `automate-trail.d/{stage-sync,closeout,trail-pr,sweep}.sh` and `automate-lanes.d/{wave,launch,create}.sh` (plus `verify-run.sh`) re-derive origin/HEAD inline with a silent `main` fallback, `wait-for-checks.sh` falls back to `main`, `reconcile-jobs.sh` probes origin/HEAD > origin/main > origin/development, and several prompts hardcode `origin/main` / `git checkout main`. This causes item PRs against `main` while `/automate` lanes, waves and trail PRs use `development`, and wrong-base diffs in the rubric grader and self-heal.
Success looks like: one script prints the base (flag > brief > `.supervisor/config.json .base_branch` > origin/HEAD (after one `set-head -a`) > `gh repo view` > fail closed `base_branch_unresolved`), every consumer calls it, a CI test stops new inline copies, and `/setup base-branch status|set|remove` plus `/setup --help` let the operator view and set it.

## Acceptance Criteria

**Resolver (Part 1)**
- [ ] AC1 — Given a test repo with origin/HEAD → `development` and no config, when `resolve-base-branch.sh` runs, then it prints `development` and exits 0; and a Supervisor publish dry run in that repo (a `test-supervisor-next-step.sh` golden or case) emits `gh pr create --base development`.
- [ ] AC2 — Given `.supervisor/config.json {"base_branch":"release"}` and origin/HEAD → `main`, when it runs, then it prints `release`; and `/automate` trail-pr and wave-build dry runs (`test-automate-trail.sh` / `test-wave-build.sh` cases with a gh stub) target `release` (`--base release`).
- [ ] AC3 — Given `--flag feat/x` and a config of `development`, when it runs, then it prints `feat/x` (stacked `/autonomous` `--base-branch` keeps working).
- [ ] AC4 — Given `--brief <path>` to a brief carrying `- **Base Branch:** development` and no flag, when it runs, then it prints `development`.
- [ ] AC5 — Given origin/HEAD unset but `git remote set-head origin -a` can set it (a local bare origin), when it runs, then it sets origin/HEAD and prints that branch.
- [ ] AC6 — Given origin/HEAD unset, no `gh` on PATH, no config, when it runs, then it exits non-zero with `base_branch_unresolved` on stderr and NOTHING on stdout (never a `main` guess).
- [ ] AC7 — Given `.base_branch` = `"bad..name"` (or an invalid flag/brief value), when it runs, then it exits non-zero with `base_branch_invalid:config` (resp. `:flag` / `:brief`) and does not fall through to a lower step.
- [ ] AC8 — Given `--explain`, when it runs, then it prints the winning value and the step that produced it (`development (source: config)` form, the string `/setup base-branch status` shows).

**Script consumers (Part 2)**
- [ ] AC9 — Given each consumer — `supervisor-next-step.sh` (init and acquire), `automate-trail.d/{stage-sync,closeout,trail-pr,sweep}.sh`, `automate-lanes.d/{wave,launch,create}.sh`, `verify-run.sh`, `wait-for-checks.sh` (fallback only), `reconcile-jobs.sh` (`vcs_base_ref` / `--print-base-ref`, reused by `worktree-audit.sh`) and `migrate-branch-mode.sh` `default_branch()` (its origin/HEAD step) — when it needs a base, then it obtains it from `resolve-base-branch.sh`. On `base_branch_unresolved` each consumer behaves as classified here (no consumer is left unclassified):
  - **Stops with the named status (correctness, fail CLOSED):** Supervisor init (`sn_fail`, the run does not start); `sn_acquire` reads the `base_branch` state value init recorded and calls the resolver only when that value is empty, failing the same way; `wave.sh` wave-build (exit 1 refused, nothing created); `automate-lanes.d/create.sh` and `launch.sh` (refuse the lane with the status on stderr, nothing created).
  - **Prints its one outcome line and exits 0 (always-exit-0 emitters):** `trail-pr.sh` → `skipped — base_branch_unresolved`; `sweep.sh` → its single last line `sweep: summary — skipped: base_branch_unresolved`, exit 0; `stage-sync.sh` and `closeout.sh` → skip the base-dependent step with a `base_branch_unresolved` diagnostic on stderr and keep their existing exit contract (no new non-zero exit).
  - **Degrades as today (fail-SAFE readers):** `reconcile-jobs.sh` / `worktree-audit.sh` (empty base ref, briefs stay `unknown`); `verify-run.sh` (empty `diff.stat`); `wait-for-checks.sh` (PR `baseRefName` first; with no PR base and no resolved base, keeps its existing path with the base empty rather than inventing `main`); `migrate-branch-mode.sh default_branch()` (falls through to its existing `ls-remote --symref` step; the existing callers' `refused:` handling of an empty default is unchanged).
- [ ] AC10 — Given `wait-for-checks.sh` on a PR, then the PR's `baseRefName` stays first and the resolver is only the fallback; and `/review-pr` on a PR targeting `development` still uses the PR's own `baseRefName` (unchanged — no review-heal file is modified).

**Guard (Part 3)**
- [ ] AC11 — Given the PR, when `bash loomwright/scripts/test-base-branch-single-resolver.sh` runs, then it passes; and its built-in mutation control (a scratch copy of a non-test script with an inline `symbolic-ref refs/remotes/origin/HEAD … || … main` line added, plus one per fallback form found at base: `base=main`, `base="main"`, `base_branch="main"`, `${b:-main}`) makes it fail. The allowlist names each genuine exception with a reason (at least `send-telemetry-core.sh`'s default-branch comparison for the telemetry target ref).

**Docs + prompts (Parts 4–5)**
- [ ] AC12 — Given `skills/supervisor-config/SKILL.md`, then it documents `.base_branch` beside `.voter_provider` with the full precedence, and its "default `main`" statement becomes a pointer to the resolver.
- [ ] AC13 — Given a run whose resolved base is `development`, then `agents/rubric-grader.md` diffs `origin/development...<branch>`, `skills/automate-loop/resume.md`'s landed-check reads `origin/<base>`, and every self-heal diff-scope surface — `skills/self-heal-advisory/on-entry.md`, `completion-tail.md` and `SKILL.md` (the module-shape-facts `<base>` argument in step 1h, the DIFF-SCOPE OVERRIDE text, the review "Target:" line and the 1a fix-the-class scope line) — uses `origin/$BASE_BRANCH` for every base (never the local `$BASE_BRANCH` ref, never an `origin/main` special case); the SV-760 row in `docs/loop-inventory/supervisor.md` that quotes "(origin/main or $BASE_BRANCH)" is updated to match.
- [ ] AC14 — Given Launch Pad on a repo with config `base_branch: development`, then `agents/launch-pad.md` resolves `BASE_BRANCH` once at entry via the resolver and the saved brief contains `- **Base Branch:** development` under `## Configuration` (the cited-line check prose edited identically in `skills/preflight-sync/SKILL.md`).
- [ ] AC15 — Given `grep -rnE "origin/main|checkout main" loomwright/agents loomwright/skills loomwright/commands`, then every remaining hit describes the resolver's precedence or quotes an example, and a committed evidence file `docs/evidence/base-branch-configurable.md` contains that grep's command, its full output and a one-line justification per remaining hit; the PR body links to it.

**`/setup` (Parts 6–7)**
- [ ] AC16 — Given `/setup base-branch set development` (with `origin/development` present), then `.supervisor/config.json .base_branch` is written by jq merge (backup-first, atomic, every other key preserved) and `/setup base-branch status` reports `development (source: config)`; a second `set development` reports already-configured and changes nothing (byte-identical file, no new backup).
- [ ] AC17 — Given `/setup base-branch set no-such-branch` (no `origin/no-such-branch`) or an invalid name, then it refuses with a named error and writes nothing.
- [ ] AC18 — Given `/setup base-branch remove`, then only `.base_branch` is deleted and every other key in `config.json` is byte-identical; a malformed `config.json` makes `set`/`remove` abort without writing.
- [ ] AC19 — Given `/setup --help`, `/setup -h` and `/setup help`, then each prints every module of the `skills/setup/SKILL.md` Pattern 2 registry with its subcommands, generated from the registry, writes nothing, asks nothing and stops.
- [ ] AC20 — Given `/setup frobnicate`, then it prints `Setup: unknown module 'frobnicate'` followed by the same help and never opens the dashboard.
- [ ] AC21 — Given the module lists restated in `commands/setup.md` (Usage block, Parameters `module` line), `docs/command-parts/setup/dashboard.md`, `docs/command-parts/agent-help/more.md` (the `/setup` entry's per-module list and usage lines) and `README.md` (the `/setup` integrations sentence and the Setup row), then each either names `base-branch` or points to the registry, and no surface carries a literal module count (dashboard.md's "(9 modules > 4 …)" and more.md's "across 9 modules" become count-free pointers such as "more modules than the 4-option limit"), and a test (`loomwright/scripts/test-setup-module-registry.sh`) fails when `commands/setup.md`'s Parameters module list and the registry disagree. The dashboard keeps exactly four options; `base-branch` folds into an existing bucket.

**Gates**
- [ ] AC22 — `bash scripts/check-token-budget.sh`, `bash scripts/check-prompt-history-refs.sh` and `bash scripts/check-doc-currency.sh` pass; every budget raise in `loomwright/docs/prompt-token-budgets.json` carries a reason and its mirror row in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets".
- [ ] AC23 — `bash scripts/check-version-bump.sh` passes (a `changelog.d/base-branch-configurable.md` fragment; this lane never bumps — the wave does).
- [ ] AC24 — `bash scripts/ci-local.sh` is green (including `test-loop-inventory.sh` after any `q:` anchor in `loomwright/docs/loop-inventory/*.md` whose quoted prompt text changed is updated in the same change).

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| resolver (#1) | `loomwright/skills/supervisor-config/SKILL.md` (91) | `loomwright/scripts/resolve-base-branch.sh`, `loomwright/scripts/test-resolve-base-branch.sh` | HIGH |
| supervisor + standalone scripts (#2) | `loomwright/scripts/supervisor-next-step.sh` (1289 — call-site swap only, the resolver is its own CREATE module), `loomwright/scripts/wait-for-checks.sh` (537 — fallback swap), `loomwright/scripts/reconcile-jobs.sh` (848 — `vcs_base_ref` body swap), `loomwright/scripts/worktree-audit.sh` (644 — comment only: it reuses `--print-base-ref`), `loomwright/scripts/migrate-branch-mode.sh` (942 — one step of `default_branch()`), `loomwright/scripts/verify-run.sh` (1395 — two-line swap); their tests as needed: `loomwright/scripts/test-supervisor-next-step.sh` (1047), `loomwright/scripts/test-reconcile-jobs.sh`, `loomwright/scripts/test-worktree-audit.sh`, `loomwright/scripts/test-migrate-branch-mode.sh`, `loomwright/scripts/test-wait-for-checks.sh`, `loomwright/scripts/fixtures/supervisor-golden/**` | — | HIGH |
| /automate scripts (#3) | `loomwright/scripts/automate-trail.d/stage-sync.sh` (228), `…/closeout.sh` (401), `…/trail-pr.sh` (719 — three-line swap), `…/sweep.sh` (332), `loomwright/scripts/automate-lanes.d/wave.sh` (488), `…/launch.sh` (294), `…/create.sh` (127), `loomwright/scripts/automate-helpers.sh` (1146 — header wording only), `loomwright/scripts/automate-wave.sh` (319 — header comment "the base (origin/HEAD's name, default main)" only), `loomwright/skills/automate-loop/helpers.md` (60); tests as needed: `loomwright/scripts/test-automate-trail.sh` and its parts `loomwright/scripts/test-automate-trail.d/0[1-6]-*.sh` (06-sweep.sh's `sw_repo` "base branch main, no origin" fixture relies on the deleted fallback), `loomwright/scripts/test-wave-build.sh`, `loomwright/scripts/test-automate-lanes-modules.sh` | — | HIGH |
| prompt layer (#4) | `loomwright/agents/rubric-grader.md` (103), `loomwright/agents/launch-pad.md` (880 — edits in place, no new responsibility), `loomwright/agents/supervisor.md` (651 — two lines), `loomwright/agents/plan-reviewer.md` (373), `loomwright/skills/automate-loop/resume.md` (45), `loomwright/skills/workflow-management/SKILL.md` (442), `loomwright/skills/self-heal-advisory/on-entry.md` (140), `loomwright/skills/self-heal-advisory/completion-tail.md` (517 — edits in place), `loomwright/skills/self-heal-advisory/SKILL.md` (413 — four `origin/main` diff-scope lines), `loomwright/skills/async-orchestration/finalize.md` (100), `loomwright/skills/supervisor-readiness/SKILL.md` (556 — edits in place), `loomwright/skills/preflight-sync/SKILL.md` (122), `loomwright/commands/supervisor.md` (235), `loomwright/docs/loop-inventory/automate-loop.md` (AL-207 anchor), `loomwright/docs/loop-inventory/supervisor.md`, `loomwright/docs/loop-inventory/launch-pad-autonomous.md` (only rows whose `q:` text changes) | — | MEDIUM |
| /setup (#5) | `loomwright/commands/setup.md` (297), `loomwright/skills/setup/SKILL.md` (290), `loomwright/docs/command-parts/setup/dashboard.md`, `loomwright/docs/command-parts/agent-help/more.md` (the `/setup` module list), `README.md` (two module-list lines) | `loomwright/docs/command-parts/setup/base-branch.md`, `loomwright/scripts/setup-base-branch.sh` (the `status`/`set`/`remove` writer — the same helper-script pattern as `setup-memory.sh` / `setup-statusline.sh`), `loomwright/scripts/test-setup-base-branch.sh`, `loomwright/scripts/test-setup-module-registry.sh` | MEDIUM |
| gates (#6) | `loomwright/docs/prompt-token-budgets.json` (93), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1051 — mirror rows only, the single home of the budget table) | `loomwright/scripts/test-base-branch-single-resolver.sh`, `changelog.d/base-branch-configurable.md`, `docs/evidence/base-branch-configurable.md` | HIGH |

**Module layout.** New responsibilities and their homes: base-branch resolution → CREATE `resolve-base-branch.sh` (the extract row for the inline copy that the seven `/automate` modules, `verify-run.sh`, `supervisor-next-step.sh` and `wait-for-checks.sh` carry today: extract the origin/HEAD-or-`main` resolution into `loomwright/scripts/resolve-base-branch.sh`, the siblings MODIFY rows above); the `/setup base-branch` writer → CREATE `setup-base-branch.sh` (not appended to `commands/setup.md`); the regrowth guard and registry check → their own CREATE tests. Every MODIFY at or past 500 lines receives a call-site swap or an in-place prose edit, never a new responsibility.

> **Validator-owned surfaces:** the doc-currency, token-budget, prompt-history-refs, citation-drift and loop-inventory validators scan `agents/`, `commands/`, `skills/`, `docs/` and `README.md`; their owned files above (`prompt-token-budgets.json`, `ARCHITECTURE_CONTRACTS.md`, `docs/loop-inventory/*.md`, `README.md`) are in the map. Other files those validators scan may need updates when a quoted line moves.

> **Test and fixture ownership (every pin has an owner).** Known pins on text this change edits, assigned by lane: `test-module-shape-facts.sh` (its step-1h assertion `` '`origin/main` when `BASE_BRANCH` is `main`' `` — rewritten to the new rule) → Subtask 4; `fixtures/automate-helpers-help/hdr-trail.golden` + `test-automate-helpers-dispatch.sh` (the `trail-pr` header row, regenerated in the same commit as the header edit) → Subtask 3; `test-release-refold.sh`, `test-automate-golden.sh`, `test-automate-next-step.sh`, `fixtures/automate-golden/**`, `test-automate-lanes.d/*.sh`, `test-automate-helpers.d/*.sh` → Subtask 3; `test-session-resume.sh`, `test-host-mode.sh`, `test-setup-memory.d/05-branch-mode-consent.sh`, `test-meta-sync-rehearsal.sh` → Subtask 2; `test-command-parts.sh`, `test-setup-memory-modules.sh`, `test-setup-statusline.sh` → Subtask 5. **Read-only (assert behaviour this change keeps, so no edit is expected):** `test-no-pipefail-grep-q.sh`, `test-build-capabilities.sh`, `test-hook-dispatch-on-pr-create.sh`, `test-progress-state.sh`, `test-phase45-ci-read.sh`, `test-review-heal-next-step.sh`, `test-retention-sweep.sh`, `test-verify-walkthrough.sh`, `test-verify-queue.sh`, and the seam tests that grep prompt files. **Backstop:** any other `loomwright/scripts/test-*.sh`, `test-*.d/*.sh` or `fixtures/**` pin that a consumer subtask turns red is repaired by Subtask 6 (it runs after 2–5, so sharing those paths is legal sequential sharing), by giving the fixture repo an origin/HEAD or `.base_branch`, never by re-adding a `main` fallback to a script.
> **Out of scope, deliberately unchanged:** the root CI gates `scripts/check-doc-currency.sh`, `scripts/check-prompt-history-refs.sh` and `scripts/check-vendor-coupling.sh` diff against `origin/main` for THIS plugin repo's own release checks (their own env overrides exist). They are not plugin runtime code, live outside `loomwright/scripts/` (the guard's scan root), and are not base-branch consumers of a user project.

**Total estimated files:** ~45 modify + 9 create, plus the test/fixture files named in the ownership note above (the Feasibility and Risk rows refer to this total)

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Touched-file invariants

> Grounded at base `84d9023b2d7561c3c34929df3e64696bad7b2339`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/supervisor-next-step.sh`** — keep: `set -uo pipefail`; the flag-first precedence `base="$(fl base_branch)"` and the state key written by `st_set base_branch "$base"` (every later step reads `$(st base_branch)`, and `pr-verify` compares `if [ "$PR_BASE" = "$(st base_branch)" ]`); failures surface through `sn_fail` / `sn_die2`, never a bare `exit`. Replace both `[ -n "$base" ] || base=main` sites (init and `sn_acquire`) with a resolver call that passes the flag and the brief (`--flag`, `--brief "$jp"`); acquire reads the state value set at init and resolves only when it is empty. Behaviour change to record: an invalid brief `Base Branch:` today silently falls through (`git check-ref-format --branch "$bb"`); it now stops with `base_branch_invalid:brief`. pinned by: `test-supervisor-next-step.sh` and `fixtures/supervisor-golden/*` (the inputs that carry `- **Base Branch:** main` keep passing; fixtures with no `Base Branch:` line and no origin must be given one, or a config key, rather than relying on the deleted fallback).
- **`loomwright/scripts/automate-trail.d/{stage-sync,closeout,trail-pr}.sh`** — each carries the identical three lines `base_branch="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"` / `base_branch="${base_branch#origin/}"` / `[ -n "$base_branch" ] || base_branch="main"`; replace all three with one resolver call and keep the `base_branch` variable name every later line reads. keep: `trail-pr` "always exit 0" (it prints one `opened`/`pushed`/`skipped — <reason>` line), so `base_branch_unresolved` there is a `skipped — base_branch_unresolved` line, never a non-zero exit. keep (stage-sync, closeout): their existing exit contracts — unresolved skips only the base-dependent step with a stderr diagnostic, no new non-zero exit (AC9). pinned by: `test-automate-trail.sh` + its parts `test-automate-trail.d/01-sidecar-trail-pr.sh`, `02-closeout.sh`, `05-finalize-closeout-others.sh`.
- **`loomwright/scripts/automate-trail.d/sweep.sh`** — `base="$(git -C "$SW_PRI" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"` + `[ -n "$base" ] || base="main"`; resolve with the repo dir `$SW_PRI`. The neighbouring `cur="$(git -C "$SW_PRI" symbolic-ref -q --short HEAD …)"` (current branch, not origin/HEAD) stays. keep: the header contract "then exactly ONE `sweep: summary — …` line, last. Always" exit 0 — unresolved ⇒ `sweep: summary — skipped: base_branch_unresolved`, exit 0. pinned by: `test-automate-trail.d/06-sweep.sh` (its `sw_repo` fixture builds a repo with no origin — give it an origin/HEAD or a `.base_branch` config, and add the unresolved case), `test-retention-sweep.sh`, `test-no-pipefail-grep-q.sh`.
- **`loomwright/scripts/automate-wave.sh`** — comment only: the header phrase "the base (origin/HEAD's name, default main)" becomes a pointer to `resolve-base-branch.sh`; no code change.
- **`loomwright/skills/self-heal-advisory/SKILL.md`** (prompt, listed because AC13 changes the rule it restates) — keep: step 1h stays "ADVISORY ONLY, fail-safe"; only its `<base>` rule changes to `origin/$BASE_BRANCH` for every base. Mirror: on-entry.md and completion-tail.md carry the same rule — the three files change together. pinned by: `test-module-shape-facts.sh` (asserts step 1h contains `` `origin/main` when `BASE_BRANCH` is `main` `` — rewrite that assertion to the new `origin/$BASE_BRANCH` wording in the same commit).
- **`loomwright/scripts/automate-lanes.d/wave.sh`** — the helper `printf '%s' "${b:-main}"` returns the base for wave-build; keep the helper's name and signature (callers pass the repo dir), swap its body for the resolver. keep: wave-build exit contract (`1 refused (nothing created)`, `2 STOPPED`) — unresolved ⇒ refused before anything is created. pinned by: `test-wave-build.sh` (expects `--base=main` after `remote set-head origin -a`), `test-automate-lanes-modules.sh`, `test-release-refold.sh`.
- **`loomwright/scripts/automate-lanes.d/launch.sh`** / **`create.sh`** — `[ -n "$base" ] || base=main`; `create.sh` keeps its existing `git remote set-head origin -a` attempt only if the resolver does not already do it (the resolver owns it — remove the duplicate). pinned by: `test-no-pipefail-grep-q.sh`, `test-hook-dispatch-on-pr-create.sh`, `test-progress-state.sh`, `test-build-capabilities.sh`.
- **`loomwright/scripts/verify-run.sh`** — `[ -n "$base" ] || base="main"` feeds only the advisory `diff.stat` ("an empty file when the base is unresolvable, never a failure"); keep that fail-safe: unresolved ⇒ empty `diff.stat`, never a preflight failure. pinned by: `test-verify-walkthrough.sh`, `test-verify-queue.sh`.
- **`loomwright/scripts/wait-for-checks.sh`** — keep `set -u` and the order: `BASE_REF="$(printf '%s' "$_base" | "$JQ_BIN" -r '.baseRefName // empty' …)"` first; replace only `[ -n "$BASE_REF" ] || BASE_REF="main"`. pinned by: `test-wait-for-checks.sh` (its gh stub prints `{"baseRefName":"main"}`), `test-phase45-ci-read.sh`, `test-review-heal-next-step.sh`.
- **`loomwright/scripts/reconcile-jobs.sh`** — keep the `vcs_base_ref()` function name and the `--print-base-ref` REUSE seam (worktree-audit's `_wta_base_ref` calls `bash "$d/reconcile-jobs.sh" --print-base-ref`); the seam prints a REF (`origin/<branch>`), so prefix the resolver's branch name. keep fail-safe: unresolved ⇒ empty ref, briefs stay `unknown` (never an abort). Update the "RECALL LIMIT" comment that says a `development`-merging repo "is not seen". pinned by: `test-reconcile-jobs.sh` (its no-network merge-detection cases build a fixture with only `refs/remotes/origin/main` and no origin/HEAD — the deleted origin/main probe; give that fixture an origin/HEAD or a `.base_branch` config; its byte-identity-to-origin/main baseline covers the no-`--evidence` porcelain, which this change must keep identical), `test-worktree-audit.sh` (comment "`report`'s new columns lean on the sibling reconcile-jobs.sh's --print-base-ref"), `test-session-resume.sh`, `test-host-mode.sh` ("stranded brief whose merge is proven on a local origin/main").
- **`loomwright/scripts/worktree-audit.sh`** — keep `set +e` ("Never `set -e`/`set -u`: an emitter that dies is a gate"); only the `_wta_base_ref` comment "(origin/HEAD, else origin/main, else origin/development)" changes to point at the resolver.
- **`loomwright/scripts/migrate-branch-mode.sh`** — `default_branch()` keeps `state_get default` first and `ls-remote --symref` last; only the middle `symbolic-ref -q --short refs/remotes/origin/HEAD` step becomes a resolver call (no `main` fallback is added — the function has none today). pinned by: `test-migrate-branch-mode.sh`, `test-meta-sync-rehearsal.sh`.
- **`loomwright/scripts/automate-helpers.sh`** — header text only: the `trail-pr` row's "commits this run's explicit trail paths as ONE PR off fresh origin/main" wording matches the code (the resolved base). Its `#:` lines are a help surface — keep the `#:` prefix and one-line-per-subcommand shape. pinned by: `fixtures/automate-helpers-help/hdr-trail.golden` via `test-automate-helpers-dispatch.sh` (its `hdr-trail` segment) — regenerate the golden in the same commit as the header edit.

## Closed enumerations touched

> Sibling grep at base `84d9023`: `grep -rnF 'statusline' --exclude=CHANGELOG.md loomwright/commands loomwright/skills/setup loomwright/docs/command-parts README.md` (no backticks, so the bold `**statusline**` form is caught) — the hits that are module lists are below (new `/setup` module value `base-branch`).

- **`base-branch`** (sibling: `statusline`) — must be named in:
  - `loomwright/skills/setup/SKILL.md` — Pattern 2 registry table, `| \`statusline\` | FULL status / apply / **remove**` — extend (the authority).
  - `loomwright/commands/setup.md` — the Parameters line `- **module** (optional): one of \`observability\`, …, \`statusline\`.` — extend (pinned against the registry by the new test), plus its Usage block and the part-routing list `` - `statusline` → `${CLAUDE_PLUGIN_ROOT}/docs/command-parts/setup/statusline.md` `` — extend.
  - `loomwright/docs/command-parts/setup/dashboard.md` — the status table rows (`| statusline    | <derived>`) and one bundled option — extend; the "(9 modules > 4 → an invalid call)" count becomes the count-free pointer "more modules than the 4-option limit" (never a new literal count).
  - `loomwright/docs/command-parts/agent-help/more.md` — the `/setup` entry ("across 9 modules — **observability** … **statusline** (`status | apply | remove` …)") and its per-module usage line — extend with `base-branch` (`status | set <branch> | remove`) and drop the literal "9" for a pointer to the registry.
  - `README.md` — the "Optional integrations in one place" sentence and the `| **Setup** (command)` row — extend.
  - `loomwright/skills/setup/SKILL.md` lines naming `statusline`'s write domain (Pattern 8 / checklist) — no change: they describe that module's write class, not the module list.

> Sibling grep for the new statuses `base_branch_unresolved` / `base_branch_invalid:<source>`: `grep -rnF 'fix_floor_invalid' --exclude=CHANGELOG.md loomwright` (a script-emitted named status) → hits only in review-heal's own escalation list (`test-review-heal-next-step.sh`), loop inventories and goldens — no change: no closed list enumerates every script status; review-heal does not consume the resolver.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-resolve-base-branch.sh` — AC6 unresolved case | make the resolver's final fall-through print `main` and exit 0 instead of `base_branch_unresolved` |
| `loomwright/scripts/test-resolve-base-branch.sh` — AC7 invalid-config case | delete the `git check-ref-format --branch` validation of the config value in `loomwright/scripts/resolve-base-branch.sh` |
| `loomwright/scripts/test-resolve-base-branch.sh` — AC5 set-head case | delete the `git remote set-head origin -a` line in `loomwright/scripts/resolve-base-branch.sh` |
| `loomwright/scripts/test-resolve-base-branch.sh` — AC3 flag precedence | swap the flag and config steps' order in `loomwright/scripts/resolve-base-branch.sh` |
| `loomwright/scripts/test-base-branch-single-resolver.sh` — regrowth guard | re-add `[ -n "$base_branch" ] || base_branch="main"` in `loomwright/scripts/automate-trail.d/trail-pr.sh` |
| `loomwright/scripts/test-setup-module-registry.sh` — list parity | delete `` `statusline` `` from the Parameters module line in `loomwright/commands/setup.md` |
| `loomwright/scripts/test-setup-base-branch.sh` — remove keeps other keys | make `remove` write `{}` instead of `del(.base_branch)` in `loomwright/scripts/setup-base-branch.sh` |
| `loomwright/scripts/test-resolve-base-branch.sh` — AC4 brief step | delete the `--brief` step (the `Base Branch:` line read) in `loomwright/scripts/resolve-base-branch.sh` |
| `loomwright/scripts/test-resolve-base-branch.sh` — AC8 `--explain` source label | make `--explain` print the value without its `(source: <step>)` suffix in `loomwright/scripts/resolve-base-branch.sh` |
| `loomwright/scripts/test-supervisor-next-step.sh` — AC1 publish `--base development` | replace the resolver call in `sn_init` of `loomwright/scripts/supervisor-next-step.sh` with the literal `main` |
| `loomwright/scripts/test-supervisor-next-step.sh` — invalid brief `Base Branch:` stops | drop `--brief "$jp"` from the resolver call in `loomwright/scripts/supervisor-next-step.sh` |
| `loomwright/scripts/test-automate-trail.d/01-sidecar-trail-pr.sh` — AC2 trail-pr `--base release` | replace the resolver call in `loomwright/scripts/automate-trail.d/trail-pr.sh` with the literal `main` |
| `loomwright/scripts/test-automate-trail.d/06-sweep.sh` — unresolved ⇒ one summary line, exit 0 | make the unresolved branch in `loomwright/scripts/automate-trail.d/sweep.sh` `return 1` instead of printing the summary line |
| `loomwright/scripts/test-wave-build.sh` — AC2 wave `--base release` | replace the resolver call in the base helper of `loomwright/scripts/automate-lanes.d/wave.sh` with `printf '%s' main` |
| `loomwright/scripts/test-setup-base-branch.sh` — AC16 idempotent second `set` | delete the already-configured byte-compare early exit in `loomwright/scripts/setup-base-branch.sh` (a second backup is written) |
| `loomwright/scripts/test-setup-base-branch.sh` — AC17 refuse missing branch | delete the `origin/<branch>` existence check in `loomwright/scripts/setup-base-branch.sh` |
| `loomwright/scripts/test-setup-module-registry.sh` — AC19 `--help`/`-h`/`help` | delete the `-h` alias from the help dispatch in `loomwright/commands/setup.md` |
| `loomwright/scripts/test-module-shape-facts.sh` — step 1h base rule (rewritten pin) | restore the "`origin/main` when `BASE_BRANCH` is `main`" clause in step 1h of `loomwright/skills/self-heal-advisory/SKILL.md` |
| `loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden` — trail-pr header row (regenerated) | flip `the resolved base` → `fresh origin/main` in the `trail-pr` `#:` row of `loomwright/scripts/automate-helpers.sh` |
| `loomwright/scripts/test-setup-module-registry.sh` — AC20 unknown module | delete the `Setup: unknown module` line from `loomwright/commands/setup.md` (falls back to the bare Usage block) |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Resolver script + its unit test + supervisor-config docs | AC1 (resolver half), AC2 (resolver half), AC3–AC8, AC12 | 1 modify, 2 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | Supervisor + standalone script consumers | AC1 (publish dry run), AC9 (its scripts), AC10 | 6 modify (+ tests/fixtures), 0 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 3 | `/automate` script consumers | AC2 (trail/wave dry runs), AC9 (its scripts) | 10 modify (+ tests), 0 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 4 | Prompt-layer consumers | AC13, AC14, AC15 (prompt edits) | 16 modify, 0 create | `skills/supervisor-readiness/SKILL.md` | BLOCKED (by #1) |
| 5 | `/setup base-branch` + explicit `/setup --help` | AC16–AC21 | 5 modify, 4 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 6 | Regrowth guard, budgets, changelog fragment, evidence file | AC11, AC15 (evidence file), AC22–AC24 | 2 modify, 3 create | `skills/quality-checklist/SKILL.md` | BLOCKED (by #2, #3, #4, #5) |

### Subtask Contracts

```yaml
# Subtask 1 — resolver
provides:
  - {kind: "file", path: "loomwright/scripts/resolve-base-branch.sh"}
  - {kind: "symbol", path: "loomwright/scripts/resolve-base-branch.sh", name: "base_branch_unresolved"}
  - {kind: "symbol", path: "loomwright/scripts/resolve-base-branch.sh", name: "--explain"}
  - {kind: "file", path: "loomwright/scripts/test-resolve-base-branch.sh"}
  - {kind: "symbol", path: "loomwright/skills/supervisor-config/SKILL.md", name: "base_branch"}
requires: []
lanes:
  - "loomwright/scripts/resolve-base-branch.sh"
  - "loomwright/scripts/test-resolve-base-branch.sh"
  - "loomwright/skills/supervisor-config/SKILL.md"
external_requires:
  - "git >= 2.x (check-ref-format --branch, remote set-head -a)"
  - "gh CLI (optional — resolver step 5 only)"

# Subtask 2 — supervisor + standalone consumers
provides:
  - {kind: "symbol", path: "loomwright/scripts/supervisor-next-step.sh", name: "resolve-base-branch.sh"}
  - {kind: "symbol", path: "loomwright/scripts/wait-for-checks.sh", name: "resolve-base-branch.sh"}
  - {kind: "symbol", path: "loomwright/scripts/reconcile-jobs.sh", name: "resolve-base-branch.sh"}
  - {kind: "symbol", path: "loomwright/scripts/migrate-branch-mode.sh", name: "resolve-base-branch.sh"}
  - {kind: "symbol", path: "loomwright/scripts/verify-run.sh", name: "resolve-base-branch.sh"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/resolve-base-branch.sh"}
lanes:
  - "loomwright/scripts/supervisor-next-step.sh"
  - "loomwright/scripts/wait-for-checks.sh"
  - "loomwright/scripts/reconcile-jobs.sh"
  - "loomwright/scripts/worktree-audit.sh"
  - "loomwright/scripts/migrate-branch-mode.sh"
  - "loomwright/scripts/verify-run.sh"
  - "loomwright/scripts/test-supervisor-next-step.sh"
  - "loomwright/scripts/test-wait-for-checks.sh"
  - "loomwright/scripts/test-reconcile-jobs.sh"
  - "loomwright/scripts/test-worktree-audit.sh"
  - "loomwright/scripts/test-migrate-branch-mode.sh"
  - "loomwright/scripts/test-verify-walkthrough.sh"
  - "loomwright/scripts/test-verify-queue.sh"
  - "loomwright/scripts/test-session-resume.sh"
  - "loomwright/scripts/test-host-mode.sh"
  - "loomwright/scripts/test-meta-sync-rehearsal.sh"
  - "loomwright/scripts/test-setup-memory.d/05-branch-mode-consent.sh"
  - "loomwright/scripts/fixtures/supervisor-golden/**"
external_requires: []

# Subtask 3 — /automate consumers
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.d/trail-pr.sh", name: "resolve-base-branch.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.d/stage-sync.sh", name: "resolve-base-branch.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.d/closeout.sh", name: "resolve-base-branch.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.d/sweep.sh", name: "resolve-base-branch.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/wave.sh", name: "resolve-base-branch.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/launch.sh", name: "resolve-base-branch.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/create.sh", name: "resolve-base-branch.sh"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/resolve-base-branch.sh"}
lanes:
  - "loomwright/scripts/automate-trail.d/stage-sync.sh"
  - "loomwright/scripts/automate-trail.d/closeout.sh"
  - "loomwright/scripts/automate-trail.d/trail-pr.sh"
  - "loomwright/scripts/automate-trail.d/sweep.sh"
  - "loomwright/scripts/automate-lanes.d/wave.sh"
  - "loomwright/scripts/automate-lanes.d/launch.sh"
  - "loomwright/scripts/automate-lanes.d/create.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/automate-wave.sh"
  - "loomwright/skills/automate-loop/helpers.md"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/scripts/test-automate-trail.d/*.sh"
  - "loomwright/scripts/test-wave-build.sh"
  - "loomwright/scripts/test-automate-lanes-modules.sh"
  - "loomwright/scripts/test-retention-sweep.sh"
  - "loomwright/scripts/test-hook-dispatch-on-pr-create.sh"
  - "loomwright/scripts/test-progress-state.sh"
  - "loomwright/scripts/test-release-refold.sh"
  - "loomwright/scripts/test-automate-helpers-dispatch.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden"
  - "loomwright/scripts/test-automate-golden.sh"
  - "loomwright/scripts/test-automate-next-step.sh"
  - "loomwright/scripts/fixtures/automate-golden/**"
  - "loomwright/scripts/test-automate-lanes.d/*.sh"
  - "loomwright/scripts/test-automate-helpers.d/*.sh"
external_requires: []

# Subtask 4 — prompt layer
provides:
  - {kind: "symbol", path: "loomwright/agents/rubric-grader.md", name: "resolve-base-branch.sh"}
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "resolve-base-branch.sh"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/resume.md", name: "resolve-base-branch.sh"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/on-entry.md", name: "origin/$BASE_BRANCH"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/resolve-base-branch.sh"}
lanes:
  - "loomwright/agents/rubric-grader.md"
  - "loomwright/agents/launch-pad.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/agents/plan-reviewer.md"
  - "loomwright/skills/automate-loop/resume.md"
  - "loomwright/skills/workflow-management/SKILL.md"
  - "loomwright/skills/self-heal-advisory/on-entry.md"
  - "loomwright/skills/self-heal-advisory/completion-tail.md"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/skills/async-orchestration/finalize.md"
  - "loomwright/skills/supervisor-readiness/SKILL.md"
  - "loomwright/skills/preflight-sync/SKILL.md"
  - "loomwright/commands/supervisor.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/docs/loop-inventory/supervisor.md"
  - "loomwright/docs/loop-inventory/launch-pad-autonomous.md"
  - "loomwright/scripts/test-module-shape-facts.sh"
external_requires: []

# Subtask 5 — /setup base-branch + --help
provides:
  - {kind: "file", path: "loomwright/docs/command-parts/setup/base-branch.md"}
  - {kind: "file", path: "loomwright/scripts/setup-base-branch.sh"}
  - {kind: "file", path: "loomwright/scripts/test-setup-base-branch.sh"}
  - {kind: "file", path: "loomwright/scripts/test-setup-module-registry.sh"}
  - {kind: "symbol", path: "loomwright/skills/setup/SKILL.md", name: "base-branch"}
  - {kind: "symbol", path: "loomwright/commands/setup.md", name: "Setup: unknown module"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/resolve-base-branch.sh", name: "--explain"}
lanes:
  - "loomwright/commands/setup.md"
  - "loomwright/skills/setup/SKILL.md"
  - "loomwright/docs/command-parts/setup/base-branch.md"
  - "loomwright/docs/command-parts/setup/dashboard.md"
  - "loomwright/docs/command-parts/agent-help/more.md"
  - "loomwright/scripts/setup-base-branch.sh"
  - "loomwright/scripts/test-setup-base-branch.sh"
  - "loomwright/scripts/test-setup-module-registry.sh"
  - "loomwright/scripts/test-command-parts.sh"
  - "loomwright/scripts/test-setup-memory-modules.sh"
  - "loomwright/scripts/test-setup-statusline.sh"
  - "README.md"
external_requires: []

# Subtask 6 — guard + gates
provides:
  - {kind: "file", path: "loomwright/scripts/test-base-branch-single-resolver.sh"}
  - {kind: "file", path: "changelog.d/base-branch-configurable.md"}
  - {kind: "file", path: "docs/evidence/base-branch-configurable.md"}
requires:
  - {from: "2", kind: "symbol", path: "loomwright/scripts/supervisor-next-step.sh", name: "resolve-base-branch.sh"}
  - {from: "3", kind: "symbol", path: "loomwright/scripts/automate-trail.d/trail-pr.sh", name: "resolve-base-branch.sh"}
  - {from: "4", kind: "symbol", path: "loomwright/agents/rubric-grader.md", name: "resolve-base-branch.sh"}
  - {from: "5", kind: "file", path: "loomwright/docs/command-parts/setup/base-branch.md"}
lanes:
  - "loomwright/scripts/test-base-branch-single-resolver.sh"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/base-branch-configurable.md"
  - "docs/evidence/base-branch-configurable.md"
  # backstop pin repair (runs after 2–5: legal sequential sharing; see the File Impact Map ownership note)
  - "loomwright/scripts/test-*.sh"
  - "loomwright/scripts/test-*.d/*.sh"
  - "loomwright/scripts/fixtures/**"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──┐
          ├─→ Subtask 3 ──┤
          ├─→ Subtask 4 ──┼─→ Subtask 6
          └─→ Subtask 5 ──┘
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 2 | Subtask 3 | none (`test-no-pipefail-grep-q.sh` pins files in both but is read-only for both) | NO |
| Subtask 2/3/4/5 | each other | none | NO |
| Subtask 4 | Subtask 6 | none (Subtask 4 does not touch the budgets file; Subtask 6 re-measures after it) | NO (ordered by `requires`) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtasks 2, 3, 4, 5 (parallel — mutually unreachable, disjoint lanes)
- **Batch 3:** Subtask 6 (after 2–5: the guard scans the finished consumers; the budgets are re-measured after every prompt edit)
- **Recommended workers:** 3
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md` |
| 3 | `skills/unit-testing/SKILL.md` |
| 4 | `skills/supervisor-readiness/SKILL.md` |
| 5 | `skills/unit-testing/SKILL.md` |
| 6 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope: the File Impact Map total across scripts, prompts, `/setup` and tests (source: Feasibility (Phase 2.5)) | HIGH | Six subtasks with disjoint lanes; keep each Part as its own commit so review can follow it |
| Behaviour change: a repo with no origin/HEAD, no `gh` and no config now stops with `base_branch_unresolved` instead of silently using `main` (source: Feasibility (Phase 2.5)) | MEDIUM | The resolver tries `set-head -a` and `gh` first; the stderr status names the fix (`/setup base-branch set <branch>`). Fail-SAFE readers keep degrading (AC9) |
| Existing tests build temp repos with no origin/HEAD and rely on the deleted `main` fallback (golden fixtures, `test-automate-trail.sh`, `test-wave-build.sh` …) | HIGH | Each consumer subtask owns its tests in `lanes:`; give the fixture repo an origin/HEAD (or `.supervisor/config.json .base_branch`) — never re-add a fallback in the script to keep a test green |
| `trail-pr` and other always-exit-0 emitters must not start exiting non-zero | MEDIUM | Unresolved ⇒ a `skipped — base_branch_unresolved` line, exit 0 (Touched-file invariants) |
| `reconcile-jobs.sh --print-base-ref` returns a REF (`origin/<b>`) while the resolver returns a branch name | MEDIUM | Prefix in `vcs_base_ref`; `test-worktree-audit.sh` pins the seam |
| Prompt edits move `q:` anchors quoted by `docs/loop-inventory/*.md` (AL-207 quotes resume.md's `git log origin/main --oneline`) | MEDIUM | Update the inventory row in the same change; `test-loop-inventory.sh` fails otherwise |
| Token budgets for `launch-pad`, `supervisor`, `rubric-grader`, `setup` may need raising | LOW | Subtask 6 re-measures after 2–5 and raises only with a recorded reason + mirror row |
| `agents/launch-pad.md`'s cited-line check prose is mirrored in `skills/preflight-sync/SKILL.md` | MEDIUM | Both in Subtask 4's lanes; edit together |
| A gitignored `.supervisor/config.json` is not inherited by a teammate's clone | LOW | Documented in `supervisor-config/SKILL.md`; `/setup base-branch` is the per-operator way to set it |
| `/automate` run files that already recorded a base keep it | LOW | Only new resolution goes through the resolver; no migration of recorded state |
| Lessons [fa32a308] (mutation controls) and [ead04b14] (bash 3.2 empty arrays under `set -u`) | MEDIUM | Gate the guard's mutant on non-empty + differs-from-original + `bash -n`; the resolver is bash 3.2-safe |

## Configuration
- **Workers:** 3
- **Mode:** parallel
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-27-base-branch-configurable.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-27T14:57:32Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/724
- **Branch:** feature/base-branch-configurable
- **Files changed:** 87
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** 6/6 subtasks merged; one resolver (resolve-base-branch.sh) wired into every script/prompt consumer, /setup base-branch + /setup --help, regrowth guard. Phase 4.5: 3 review→fix iterations (de6ee53, 884c9e3, 1b3943e); the final-iteration guard-regex sweep (test-base-branch-single-resolver.sh, 47/0) was not re-reviewed. 4 LOW findings dismissed below the MEDIUM floor. Local ci-local: only persistent failures are test-automate-lanes.sh's 42 relay/inbox cases, identical on base 84d9023.

## Not verified
- **Live Supervisor / Launch Pad / /setup sessions** — prompt-layer changes checked by static gates and tests only (subtasks 4, 5)
- **Resolver gh step against a real GitHub repo** — exercised only via a PATH stub (subtask 1)
- **reconcile-jobs.sh SessionStart latency** — one set-head/gh probe may hit the network when origin/HEAD is unset; not measured (subtask 2)
