# 01 — Configurable base branch: one resolver, every consumer, `/setup base-branch`, explicit `/setup --help`

## Status: pending

**As a** maintainer running Loomwright on a repo whose integration branch is not `main` (e.g. `development`),
**I want** the base branch resolved once, by one script, from a setting I can view and set through `/setup`, and used by
every script and every agent prompt,
**so that** Supervisor, `/automate` lanes, waves, trail PRs, the rubric grader, resume and self-heal all branch from,
target and diff against the same branch — and I can discover `/setup`'s modules with `--help`.

> Merged from two earlier drafts (script layer + prompt layer) on 2026-10-27 so the set runs in three waves: this item
> and 02 share no file, so they form wave 1.

## Verified premises (origin/main @ bd4be26, 2026-10-27 — re-verify before dispatch)

**Script layer**

- **No central resolver, config key or env var exists.** No `BASE_BRANCH`/`LOOMWRIGHT_BASE_BRANCH` reader; no
  `.supervisor/config.json` key.
- **Supervisor:** `scripts/supervisor-next-step.sh` — `--base-branch` flag, else the brief's `- **Base Branch:**` line
  (validated with `git check-ref-format`), else hardcoded `base=main` (the `[ -n "$base" ] || base=main` line right after
  the `sn_brief_conf 'Base Branch'` read; a second `|| base=main` in the acquire step). It never consults origin/HEAD.
  Downstream steps read state `base_branch`; publish emits `gh pr create --base`; pr-verify checks `baseRefName`.
- **`/automate` scripts re-derive inline** `git symbolic-ref refs/remotes/origin/HEAD` || `main`, one copy each in:
  `scripts/automate-trail.d/{stage-sync,closeout,trail-pr,sweep}.sh`, `scripts/automate-lanes.d/{wave,launch,create}.sh`,
  `scripts/verify-run.sh`. `trail-pr.sh` and `wave.sh` open PRs with that value.
- **Other resolvers:** `scripts/wait-for-checks.sh` (PR `baseRefName` || `main`); `scripts/reconcile-jobs.sh`
  (origin/HEAD > `origin/main` > `origin/development`, reused by `worktree-audit.sh`; its own comment admits a repo that
  merges into `development` while the default is `main` "is not seen"); `scripts/migrate-branch-mode.sh`
  `default_branch()` (state > origin/HEAD > `ls-remote --symref`, no `main` fallback);
  `docs/command-parts/dreaming/{rules-pr,memory-pr}.md` (`gh repo view --json defaultBranchRef`, abort if empty).
- **Unset origin/HEAD** (common after `git init` + `remote add`) makes every inline copy fall back to `main` silently;
  only `automate-lanes.d/create.sh` runs `git remote set-head origin -a` first.
- **Consequence today:** on a repo whose origin/HEAD is `development`, `/automate` builds lanes/wave/trail on
  `development` while Supervisor fetches, branches and opens the item PR against `main`.
- `/autonomous` stacked mode passes `--base-branch` explicitly (must keep working). `/review-pr` adopts the PR's own
  `baseRefName` (correct — must not change).

**Prompt layer and `/setup`**

**Base branch in prompts**
- Hardcoded with no override: `agents/rubric-grader.md` Procedure step 1 (`git diff origin/main...{feature_branch}`,
  overridden only when a DIFF-SCOPE OVERRIDE is injected via `skills/self-heal-advisory/completion-tail.md`);
  `skills/automate-loop/resume.md` (`git log origin/main --oneline` as the "branch landed?" check);
  `agents/supervisor.md` ("Cancel: `git checkout main`"); `skills/workflow-management/SKILL.md` (ACQUIRE template
  `git checkout main && git pull`, and a second `git checkout main`).
- `agents/launch-pad.md` uses `origin/$BASE_BRANCH` (cited-line premise check, Phase 3 action 10 and its Phase 5
  carry-over) but nothing in Launch Pad resolves `BASE_BRANCH`, and Launch Pad never writes `- **Base Branch:**` into a
  brief.
- `skills/self-heal-advisory/on-entry.md` diff-scope mapping uses `origin/main` when the base is `main` but the LOCAL ref
  `$BASE_BRANCH...HEAD` otherwise — a stacked base is compared against a possibly stale local ref.
- Doc statements of "default `main`": `agents/supervisor.md`, `skills/async-orchestration/finalize.md`,
  `commands/supervisor.md`, `skills/supervisor-readiness/SKILL.md`; `skills/automate-loop/helpers.md` and the
  `automate-helpers.sh` header say trail-pr works "off fresh origin/main" while the code uses origin/HEAD.

**`/setup --help`** (correction to the owner conversation: help is not wholly missing)
- `commands/setup.md` Parameters already says "If unrecognised: print this usage block and stop", so `/setup --help`
  today prints the Usage block **by accident** — `--help` is simply an unknown module name. Nothing documents `--help`,
  `-h` or `help`; an unknown module gets no named error; and the module list is kept by hand in THREE places
  (`commands/setup.md` Usage, its Parameters `module` line, and the registry table in `skills/setup/SKILL.md`
  Pattern 2 — the authority). They agree today (nine modules; `ui` and `twin` were retired).
- `/setup`'s no-arg dashboard question is fixed at four options; a new module folds into an existing bucket
  (`docs/command-parts/setup/dashboard.md`).

## Scope

### Part 1 — the resolver
A new `loomwright/scripts/resolve-base-branch.sh` (portable bash 3.2, no network unless the steps below need it) that
prints one branch name and exits 0, or prints a named status to stderr and exits non-zero. Precedence:

1. explicit `--flag <branch>` argument (the per-run flag, passed through by the caller)
2. explicit `--brief <path>` → the brief's `- **Base Branch:**` line
3. repo config `.supervisor/config.json` `.base_branch`
4. `git symbolic-ref refs/remotes/origin/HEAD` (after one `git remote set-head origin -a` attempt when unset — the
   behaviour `create.sh` already has)
5. `gh repo view --json defaultBranchRef` when `gh` is available
6. otherwise **fail closed**: status `base_branch_unresolved`, non-zero exit. Never print `main` as a guess.

Every candidate is validated with `git check-ref-format --branch`; an invalid value at a higher step is an error
(`base_branch_invalid:<source>`), not a silent fall-through. A `--explain` flag prints which step won (for `/setup`
and debugging).

### Part 2 — every script consumer calls it
Replace the inline resolution in `supervisor-next-step.sh` (both sites), the eight `/automate` scripts, `wait-for-checks.sh`
(fallback only — PR `baseRefName` stays first), `reconcile-jobs.sh` / `worktree-audit.sh`, and `migrate-branch-mode.sh`
`default_branch()`'s origin/HEAD step. Callers that hit `base_branch_unresolved` follow the bimodal rule: interactive
callers may surface it; non-interactive runs stop with the named status (a correctness gate, fails CLOSED).

### Part 3 — guard against regrowth
A test (`loomwright/scripts/test-base-branch-single-resolver.sh`, picked up by `scripts/ci-local.sh`) that fails when a
non-test, non-fixture file under `loomwright/scripts/` contains `symbolic-ref refs/remotes/origin/HEAD` or a
`base=main` / `|| echo main` fallback outside `resolve-base-branch.sh`, with an explicit allowlist (path + reason) for
genuine exceptions.

### Part 4 — docs
`skills/supervisor-config/SKILL.md` documents `.base_branch` beside `.voter_provider` and the full precedence; the
"default `main`" statements in that skill are replaced by a pointer to the resolver (prompt-layer files are Part 5).

### Part 5 — prompt consumers use the resolver (Part 1)
Every site above obtains the base from `resolve-base-branch.sh` (or from the run state that Supervisor already records),
never a literal `main`: rubric-grader's diff, resume's landed-check, supervisor's cancel line, workflow-management's
templates, Launch Pad's `BASE_BRANCH` (resolved once at entry, and written into the brief's `## Configuration` as
`- **Base Branch:**` so Supervisor and Plan Reviewer Criterion 13 see it), and self-heal's diff scope compares against
`origin/<base>` for every base. "Default `main`" prose becomes a pointer to the resolver's precedence; the helpers.md /
automate-helpers.sh "origin/main" wording matches the code.

### Part 6 — `/setup base-branch` module
`status` (read-only: `resolve-base-branch.sh --explain` — the winning value and which step produced it) | `set <branch>`
(validates with `git check-ref-format` and that `origin/<branch>` exists; writes `.supervisor/config.json .base_branch`
by jq merge, backup-first, idempotent) | `remove` (deletes only that key). A registry row in `skills/setup/SKILL.md`
Pattern 2 + a flow part under `docs/command-parts/setup/`; folded into an existing dashboard bucket (the four-option
cap is not grown).

### Part 7 — explicit `/setup --help`
`/setup --help`, `/setup -h` and `/setup help` print the module list with each module's subcommands, **generated from
the registry** (the authority) rather than a fourth hand-kept list; read-only; no `AskUserQuestion`; then stop. An
unknown module prints `Setup: unknown module '<x>'` followed by the same help, and never falls into the dashboard. The
Usage block and Parameters line in `commands/setup.md` either derive from / point to the registry, or a test asserts
they list the same modules as the registry (rule: a restated list is updated with its authority or replaced by a
pointer).

## Acceptance criteria

**Happy path**
- [ ] Given a test repo with origin/HEAD → `development` and no config, when `resolve-base-branch.sh` runs, then it prints
  `development`; and a Supervisor publish dry run in that repo emits `gh pr create --base development`.
- [ ] Given `.supervisor/config.json {"base_branch":"release"}` and origin/HEAD → `main`, when it runs, then it prints
  `release`; and `/automate` trail-pr / wave dry runs target `release`.
- [ ] Given `--flag feat/x` and a config of `development`, then it prints `feat/x` (stacked `/autonomous` unchanged).
- [ ] Given a brief with `- **Base Branch:** development` and no flag, then it prints `development`.

**Edge cases**
- [ ] Given origin/HEAD unset but `git remote set-head origin -a` can set it, then the resolver sets it and uses it.
- [ ] Given origin/HEAD unset, no `gh`, no config, then exit non-zero with `base_branch_unresolved` on stderr and
  nothing on stdout.
- [ ] Given `.base_branch` = `"bad..name"`, then exit non-zero with `base_branch_invalid:config` (no fall-through).
- [ ] `/review-pr` on a PR targeting `development` still uses the PR's `baseRefName` (unchanged).

**Guard**
- [ ] `bash loomwright/scripts/test-base-branch-single-resolver.sh` passes on the PR, and fails when an inline
  `symbolic-ref refs/remotes/origin/HEAD … || … main` line is added to any other non-test script (mutation control in
  the test itself).

**Prompt layer + `/setup` (Parts 5–7) — happy path**
- [ ] Given a run whose resolved base is `development`, then rubric-grader diffs `origin/development...<branch>`,
  resume's landed-check reads `origin/development`, and self-heal's diff scope uses `origin/development`.
- [ ] Given Launch Pad on a repo with config `base_branch: development`, then the saved brief contains
  `- **Base Branch:** development` under `## Configuration`.
- [ ] `/setup base-branch set development` writes `.base_branch` and `/setup base-branch status` then reports
  `development (source: config)`; a second `set development` reports already-configured and changes nothing.
- [ ] `/setup --help`, `-h` and `help` each print every registry module with its subcommands and write nothing.

**Prompt layer + `/setup` — edge cases / errors**
- [ ] `/setup base-branch set no-such-branch` (no `origin/no-such-branch`) refuses with a named error and writes nothing.
- [ ] `/setup base-branch remove` deletes only `.base_branch`; other keys in `config.json` are byte-identical.
- [ ] A malformed `.supervisor/config.json` makes `set`/`remove` abort without writing (existing setup convention).
- [ ] `/setup frobnicate` prints `Setup: unknown module 'frobnicate'` plus the help, and does not open the dashboard.
- [ ] `grep -rnE "origin/main|checkout main" loomwright/agents loomwright/skills loomwright/commands` returns only lines
  that describe the resolver's precedence or quote an example, each reviewed in the PR body.

**Gates**
- [ ] `check-token-budget.sh` passes (new/changed command-part and skill text within declared budgets, raises recorded
  per the budget convention); `check-prompt-history-refs.sh` passes; `check-doc-currency.sh` passes.
- [ ] `bash scripts/check-version-bump.sh` passes.

## Priority: MVP
**Rationale:** silent wrong-branch PRs and wrong-base diffs on every non-`main` repo; Parts 6–7 are the user-facing way
to set the branch and discover `/setup`.

## Assumptions
- `.supervisor/config.json` is the right repo-scope home (same file as `.voter_provider`, `auto_review`). It is
  gitignored, so a teammate's clone does not inherit it; `/setup base-branch` (Part 6) is how each operator sets it.
- Failing closed when nothing resolves is acceptable: a repo with no remote and no config cannot open a PR anyway.
- Launch Pad writing `Base Branch:` into every brief is acceptable (the Supervisor and Plan Reviewer already read it).
- Generating help from the registry table is feasible inline (the agent reads `skills/setup/SKILL.md` at Step 0 anyway).

## Risks
- Behaviour change: repos that silently worked via the `main` fallback (no origin/HEAD, no `gh`) now stop with a named
  status. Mitigation: the `set-head -a` attempt + `gh` step cover almost every real repo; the status names the fix
  (`/setup base-branch`).
- `/automate` run files that already recorded a base keep it; only new resolution goes through the resolver.
- Prompt edits to `launch-pad.md`, `supervisor.md` and `rubric-grader.md` cost token budget; raise only with a recorded
  reason.
- `agents/launch-pad.md`'s cited-line check prose is mirrored in `skills/preflight-sync/SKILL.md` — edit both together.
- Size: one PR across scripts and prompts (~40 files). Keep the Parts as separate commits so review can follow them.

## Depends on
none

## Touches
loomwright/scripts/resolve-base-branch.sh
loomwright/scripts/test-base-branch-single-resolver.sh
loomwright/scripts/supervisor-next-step.sh
loomwright/scripts/automate-trail.d/stage-sync.sh
loomwright/scripts/automate-trail.d/closeout.sh
loomwright/scripts/automate-trail.d/trail-pr.sh
loomwright/scripts/automate-trail.d/sweep.sh
loomwright/scripts/automate-lanes.d/wave.sh
loomwright/scripts/automate-lanes.d/launch.sh
loomwright/scripts/automate-lanes.d/create.sh
loomwright/scripts/verify-run.sh
loomwright/scripts/wait-for-checks.sh
loomwright/scripts/reconcile-jobs.sh
loomwright/scripts/worktree-audit.sh
loomwright/scripts/migrate-branch-mode.sh
loomwright/skills/supervisor-config/SKILL.md
loomwright/agents/rubric-grader.md
loomwright/agents/launch-pad.md
loomwright/agents/supervisor.md
loomwright/agents/plan-reviewer.md
loomwright/skills/automate-loop/resume.md
loomwright/skills/automate-loop/helpers.md
loomwright/skills/workflow-management/SKILL.md
loomwright/skills/self-heal-advisory/on-entry.md
loomwright/skills/self-heal-advisory/completion-tail.md
loomwright/skills/async-orchestration/finalize.md
loomwright/skills/supervisor-readiness/SKILL.md
loomwright/skills/preflight-sync/SKILL.md
loomwright/commands/supervisor.md
loomwright/commands/setup.md
loomwright/skills/setup/SKILL.md
loomwright/docs/command-parts/setup
loomwright/scripts/automate-helpers.sh
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
