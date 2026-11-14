# Evidence: which repository gates reach `selvedge/`

Recorded 2026-11-13 on the qa-split/01 branch (base `58edd34`), with the selvedge plugin, its
marketplace entry, the `CLAUDE.md` / `.claude-plugin/README.md` names and the CI step in place.
Each scope is quoted from the gate's own defining line; "observed" is the gate's last output line
from a run on this branch, not an expectation.

**Result: every gate passed and none needed an exclusion for `selvedge/`.**

## Loomwright's count / budget / doc-currency / citation / prompt-history gates

| Gate | Scan scope (quoted defining line) | Reaches `selvedge/`? | Observed |
|---|---|---|---|
| `scripts/check-doc-currency.sh` | the `FILES=(` list: `CLAUDE.md`, `README.md`, `AGENT_GUIDELINES.md`, `.claude-plugin/README.md`, `.claude-plugin/marketplace.json`, `"$PLUGIN_JSON"`, loomwright docs/commands; the description check reads only `select(.name == "loomwright")` | No file under `selvedge/`. It does scan the new selvedge names in `CLAUDE.md`, `.claude-plugin/README.md` and the selvedge entry of `marketplace.json`, which carry no count or Loomwright-version claim | `✓ doc-currency: all checked version/count claims match the authoritative source.` |
| `scripts/check-token-budget.sh` | `AGENTS_DIR="${TOKEN_BUDGET_AGENTS_DIR:-loomwright/agents}"`, `SKILLS_DIR="${TOKEN_BUDGET_SKILLS_DIR:-loomwright/skills}"`, `COMMANDS_DIR="${TOKEN_BUDGET_COMMANDS_DIR:-loomwright/commands}"`, `COMMAND_PARTS_DIR="${TOKEN_BUDGET_COMMAND_PARTS_DIR:-loomwright/docs/command-parts}"` | No | `check-token-budget: OK — every agent, skill dir and command doc within its declared prompt-inventory budget.` |
| `loomwright/scripts/test-citation-drift.sh` | `SURFACES="$(git ls-files -- 'loomwright/scripts/*.sh' 'loomwright/scripts/*.py' 'loomwright/skills/*.md' 'loomwright/commands/*.md' 'loomwright/agents/*.md' 'loomwright/docs/*.md' 'scripts/*.sh' 'CLAUDE.md' 'AGENT_GUIDELINES.md' 'README.md' '.claude-plugin/README.md' '.claude/agent-memory/*.md' '.supervisor/memory/*.md' '.github/workflows/*.yml' …)"` (tracked files only) | No file under `selvedge/`. It does scan the edited `CLAUDE.md`, `.claude-plugin/README.md` and `ci.yml`; the new text there uses descriptive anchors, no `file:N` | `citation-drift: 26 passed, 0 failed` |
| `scripts/check-prompt-history-refs.sh` | `SCANNED_DIRS="loomwright/agents` / `loomwright/commands` / `loomwright/skills` / `loomwright/docs/command-parts"` | No | `check-prompt-history-refs: OK — no runtime prompt above its baseline, and the baseline did not rise.` |
| `scripts/check-skills-index-sync.sh` | `done < <(jq -r '.plugins[].source' "$MARKETPLACE_JSON")` with `[ -d "$sdir" ] \|\| continue   # plugin ships no skills (e.g. mysql-mcp) — out of scope, skip silently` | **Yes, through marketplace discovery** (`.plugins[].source` now includes `./selvedge`), and it **skips** selvedge because `selvedge/skills/` does not exist | output names only `[loomwright/skills]` and `[stackpack/skills]`, both `✓` |
| `scripts/check-command-sync.sh` | `targets=(` `"${repo_root}/loomwright/commands/code-reviewer.md"` `)` | No | `check-command-sync: OK` |

## Repo-wide portability gates

| Gate | Scan scope (quoted defining line) | Reaches `selvedge/`? | Observed |
|---|---|---|---|
| `scripts/check-locale-prefix.sh` | `git -c core.quotePath=false ls-files -z --cached --others --exclude-standard -- '*.sh' '*.bash'` (tracked + untracked-unignored) | **Yes**: all four `selvedge/tests/*.sh` (`check-release.sh`, `run.sh`, `test-check-release.sh`, `test-cli.sh`). They pass because none runs a command under a temporary `LC_ALL=` assignment (`grep -c LC_ALL` is 0 in each; the convention, if one is ever needed, is `env LC_ALL=C cmd`). `selvedge/bin/selvedge` has no `.sh` extension, so it is NOT scanned; it also has no `LC_ALL` | `check-locale-prefix: OK — 542/542 scanned shell files (git mode) carry no temporary locale assignment at command position` |
| `scripts/check-test-hermetic.sh` | `files=(loomwright/scripts/test-*.sh loomwright/scripts/adapters/*/test-*.sh scripts/test-*.sh)` | No. `selvedge/tests/test-*.sh` are hermetic on their own terms instead: each makes a fresh temp `HOME` and sources nothing from `loomwright/` (decision D4). The only network the suite uses is the pinned Playwright library + Chromium download that `test-route-guard.sh` makes through `tests/lib/playwright-cache.sh` (into a selvedge-owned cache, with `PLAYWRIGHT_BROWSERS_PATH` exported before `HOME` moves); every other arm, and every fixture server and proxy, stays on `127.0.0.1` | `check-test-hermetic: OK — 213/213 covered tests source hermetic-test-env.sh as their first executable line` |
| `scripts/check-mkdir-lock.sh` (not in the brief's list; checked because it is repo-wide) | `{ git ls-files -- loomwright/scripts scripts; git ls-files -o --exclude-standard -- loomwright/scripts scripts; }` | No (selvedge uses only `mkdir -p` anyway) | `check-mkdir-lock: PASS — 338 files scanned, no unjustified bare mkdir` |

## qa-split/02 additions (2026-11-14)

The target-safety item adds Node modules under `selvedge/lib/` and three shell files the shared
gates can see: `selvedge/tests/test-proxy.sh`, `selvedge/tests/test-route-guard.sh` and the sourced
helper `selvedge/tests/lib/playwright-cache.sh`. `check-locale-prefix.sh` scans all of them (its
git mode lists tracked + untracked-unignored `*.sh`); none uses a temporary `LC_ALL=` assignment.
Observed on this branch: `check-locale-prefix: OK — 546/546 scanned shell files (git mode) carry no
temporary locale assignment at command position`. The helpers under `tests/lib/` and
`tests/fixtures/` are not named `test-*`, so `selvedge/tests/run.sh` runs only the top-level tests.

CI cost: `test-route-guard.sh` installs Playwright (`--with-deps` under `CI`) and Chromium on every
`static` run (no cache in this item). The selvedge step's added wall time is to be read from this
branch's first CI run; locally, with a warm cache, the whole `bash selvedge/tests/run.sh` took about
15 s.

## Release gates

| Gate | Scope | Reaches `selvedge/`? | Observed |
|---|---|---|---|
| `scripts/validate-version.sh` | `done < <(jq -c '.plugins[]' "$MARKETPLACE_JSON")` — every marketplace entry: source resolves, manifest exists, marketplace `version` == `plugin.json` `version` | **Yes, by design** (AC2): the selvedge entry is checked against `selvedge/.claude-plugin/plugin.json` | `✓ [selvedge] Marketplace source resolves: ./selvedge → ./selvedge/.claude-plugin/plugin.json` / `✓ [selvedge] Versions match: 0.1.0` |
| `scripts/check-version-bump.sh` | the branch's fragments and version files against the merge base | This branch carries no fragment and no Loomwright bump | `bump-version: check OK — not bumped (version 17.38.0, the merge base's); 0 fragment(s) pending — legal, the next bump folds them (base origin/main, merge base 58edd3428171)` |
| `selvedge/tests/run.sh` (selvedge's own, CI `static` step) | `selvedge/` only | — | `selvedge gate: PASS (release check + 2 test file(s))` |

## `claude plugin validate selvedge` (AC1)

Run from the repository root, `claude` `2.1.319`:

```
$ claude plugin validate selvedge
Validating plugin manifest: /Users/vikashruhil/Documents/work/AI/ai-agent-manager-qa-split-01-1/selvedge/.claude-plugin/plugin.json

Plugin directory checks for /Users/vikashruhil/Documents/work/AI/ai-agent-manager-qa-split-01-1/selvedge. The plugin directory is the catalog that plugins are submitted to; this is a subset of what it runs.

⚠ Found 1 plugin directory warning:

  ❯ .claude-plugin/plugin.json icon: No icon (ICON_MISSING). No icon found in the plugin. The validator looked for `icon` in plugin.json and for a file at .claude-plugin/icon.png or .svg, assets/icon.png or .svg, or a similar path.
    Fix: Add a square PNG to the plugin folder at .claude-plugin/icon.png, or set `icon` in plugin.json to the path of a square PNG or JPEG in the plugin: 512 to 2048 px on each side, under 2 MB. SVG and WebP are not accepted. That file may become the listing icon only once: the first time the plugin is saved or submitted in the developer portal. Adding or changing it later does not change the icon.

These plugin directory checks do not change the result below.

The directory also runs a safety scan and a policy review that this command does not.

✔ Validation passed
```

The icon warning is a plugin-directory listing check that, per its own output, does not change
the result.

## Not measurable before merge

`/plugin install selvedge@atelier` resolves the `atelier` marketplace from the remote default
branch, so it can only install selvedge after this branch merges. Post-merge check:
`/plugin install selvedge@atelier`, then `claude plugin list` shows `selvedge@atelier`,
`Version: 0.1.0`, `Status: ✔ enabled`. A pre-merge install from a directory-source marketplace in
a scratch `CLAUDE_CONFIG_DIR` did succeed (`docs/cli-discovery.md`, case 2).
