<!-- bump: minor -->
Configurable base branch through one resolver, plus `/setup base-branch` and an explicit `/setup --help`
The base branch is now resolved in one place, `loomwright/scripts/resolve-base-branch.sh`. Precedence: `--flag`, then the brief's `- **Base Branch:**` line, then `.supervisor/config.json .base_branch`, then origin/HEAD (after one `git remote set-head origin -a`), then the `gh` default branch.
With no answer it fails closed with `base_branch_unresolved` and never guesses `main`. An invalid explicit value stops with `base_branch_invalid:<flag|brief|config>`. `--explain` prints the winning value and its source.
Every script consumer now calls it: Supervisor init and acquire, `wait-for-checks.sh` (only as the fallback after the PR's own `baseRefName`), `reconcile-jobs.sh` and `worktree-audit.sh`, `migrate-branch-mode.sh`, `verify-run.sh`, and the `/automate` trail and lane modules. Correctness consumers stop with the status, always-exit-0 emitters print a `skipped` line, and fail-safe readers degrade as before.
So a repo whose integration branch is `development` gets item PRs, lanes, waves and trail PRs against that one branch.
Behaviour change: a repo with no origin/HEAD, no `gh` and no config now stops with `base_branch_unresolved` instead of silently using `main`. An invalid brief `Base Branch:` line now stops instead of being ignored.
The rubric grader, resume's landed-check and every self-heal diff-scope surface now diff against `origin/$BASE_BRANCH` for every base. Launch Pad resolves the base once at entry and always writes it into the brief.
`/setup base-branch status|set <branch>|remove` views and writes `.base_branch`. It uses a jq merge, writes a backup first, writes atomically, and refuses a branch with no `origin/<branch>`.
`/setup --help`, `-h` and `help` print every module and its subcommands from the skill's registry. An unknown module prints `Setup: unknown module '<arg>'` followed by that help.
`test-base-branch-single-resolver.sh` fails CI on a new inline origin/HEAD read or `main` fallback outside the resolver. It has built-in mutation controls and a reasoned per-rule allowlist.
