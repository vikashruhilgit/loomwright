# Supervisor Job: selvedge exists as its own plugin, with its own gates and its own release

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (3 entries: `REQUIREMENTS-SITE-V2.md` modified, `reports/` and `research_notes/` untracked — none in this brief's map), branch: feature/drain-named-required-checks (already merged into origin/main, 0 commits ahead; the brief is planned against origin/main)
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (dirty tree; checkout is not on the base branch)
- **Source requirement:** .supervisor/requirements/qa-split/01-scaffold-selvedge-with-its-own-gates-and-release.md
- **Base commit:** ebd83f254f79982cac44d4f3f1836134701be7d6

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash 3.2-portable scripts + JSON manifests + GitHub Actions, the repo's own stack; `loomwright-lanes/` is an existing sibling-plugin precedent |
| 2 | Dependency Availability | GO | No new dependency. `jq` is already a CI dependency (used by the gates); the `selvedge` CLI itself must not require `jq` |
| 3 | Architecture Fit | GO | Marketplace wrapper with sibling plugins; `scripts/validate-version.sh` already validates every marketplace entry ("Validate EVERY marketplace plugin entry") |
| 4 | Scope vs Supervisor Capability | CAUTION | 17 files (7 modify, 10 create) > 12 ⇒ `context-bound` split into 2 subtasks with zero file overlap |
| 5 | Hard Blockers | CAUTION | The CLI-discovery spike needs a live `claude` session; the desktop-app case cannot be driven from a worker, and `/plugin install selvedge@atelier` resolves the remote default branch, so the marketplace install can only be exercised after merge |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add `selvedge/` as a sibling plugin in the atelier marketplace that releases on its own (own version, own changelog, own CI gate), make the release-content check scope `changelog.d/` fragments to the loomwright plugin so a selvedge-only change can never move Loomwright's version, and record whether a plugin's `bin/` reaches `PATH`.

**Problem Statement:**
The QA-split work (plan `qa-split/00-plan.md`, decisions D4 and D19) needs selvedge to be its own plugin.
Currently, repo release tooling knows only one release: `bump-version.sh` folds every `changelog.d/` fragment into Loomwright's version, so a sibling's change rides Loomwright's release (`git show --stat b685d9f`: a lanes change folded into a Loomwright bump). Nothing stops a selvedge-only PR from doing the same, and the shared-gate coupling is what made the August extraction an atomic 45-file change.
Success looks like: `selvedge/` installs from the marketplace, its own gate runs in CI's `static` job, a test proves a selvedge-only branch passes `check-version-bump.sh` with no fragment and FAILS if it carries one or bumps Loomwright, and `selvedge/docs/cli-discovery.md` answers the `bin/`-on-`PATH` question with command output.

**Implementation notes (binding; each one closes a trap found in analysis):**
- **This PR carries NO `changelog.d/` fragment and never runs `bash scripts/bump-version.sh`.** A bump writes `loomwright/.claude-plugin/plugin.json` and `loomwright/capabilities.json`, which breaks the "no file under `loomwright/` changes" criterion. `bash scripts/check-version-bump.sh` must report `not bumped … 0 fragment(s) pending`. (FINALIZE's `release-refold.sh` is a no-op on a branch with no bump.)
- **The selvedge gate is a STEP in the `static` job, not a new job.** `ci`'s aggregation block reads only `STATIC_RESULT`/`SUITE_RESULT`, and `loomwright/scripts/test-run-self-tests.sh` extracts and runs that exact block with only those two variables set. A new job would need an aggregator edit, which either breaks that loomwright test or needs a fail-open default. A `static` step is required through `ci` with no aggregator change.
- **Release scoping lives in `bump-version.sh --check`**, the one place the rule is implemented. `check-version-bump.sh` stays a thin `exec` wrapper (its header comment may name the new scope). The plain bump and `--refold` paths are unchanged.
- **Scope rule (`--check` only):** compute the branch's changed paths against the merge base (`git diff --name-only "$BASE_SHA"` plus untracked files from `git ls-files --others --exclude-standard`). Ignore the bump-owned paths (`$PLUGIN_JSON`, `$MARKETPLACE_JSON`, `$CHANGELOG`, `$CAPS_JSON`, `changelog.d/*`). If at least one remaining path is under a self-releasing plugin dir (one constant, `SELF_RELEASING_PLUGINS="selvedge"`) and none is outside one, the branch is **selvedge-only**. Then a fragment absent from the merge base (pending) OR a version different from the merge base's (a bump) is a violation, reported through the existing `chk` accumulator — one `chk` line per kind, `selvedge-only change carries a changelog.d fragment …` and `selvedge-only change carries a loomwright bump …` (exact literals: `## Pin mutations`), each naming the fix (bump `selvedge/.claude-plugin/plugin.json` + `selvedge/CHANGELOG.md` instead, D19). A branch that also changes any other path keeps today's behaviour exactly.
- **`selvedge/` imports nothing from Loomwright (D4):** no file under `selvedge/` sources, execs or reads a path under `loomwright/` (so `selvedge/tests/` does NOT source `loomwright/scripts/hermetic-test-env.sh`; it sets up its own temp `HOME`).
- **`bin/selvedge` has no `jq` dependency** (it runs on user machines): it reads `"version"` from its own `../.claude-plugin/plugin.json` with `sed`/`grep`, resolving its real path through a `readlink` loop so it works through the `install-cli` symlink (no `readlink -f`: macOS bash 3.2 / BSD).
- **selvedge changelog format:** each release is a heading `## <X.Y.Z> — <YYYY-MM-DD>`; the first such heading is the current release. The gate compares it with `plugin.json`'s `version`.
- **CLI-discovery spike method:** the desktop app loads a plugin by passing an explicit `--plugin-dir <cache path>` on its own command line, while a bare CLI session loads an installed plugin implicitly from user-scope `enabledPlugins` (project memory `desktop-vs-cli-plugin-install-location`). Probe the desktop mechanism with `claude -p --plugin-dir "$PWD/selvedge" --allowedTools Bash "<run: command -v selvedge; echo \"$PATH\">"` and record the full output. Probe the installed-CLI mechanism only in an isolated scratch config (for example a scratch `CLAUDE_CONFIG_DIR` with a directory-source marketplace pointing at the checkout); never `claude plugin install`/`marketplace add` into the user's real config. If a case cannot be measured, write `unverified` with the reason and the exact command the owner can run, and document `install-cli` as REQUIRED, not optional. `install-cli` is documented as optional only when BOTH cases are measured `yes`.

## Design decisions
- decision: implementation language for the `selvedge` CLI stub (`bin/selvedge`) and its gate
  chosen: POSIX-leaning bash, bash 3.2-portable, no `jq` in the CLI
  rejected: a Node/TypeScript CLI like `loomwright-lanes/hooks/register.tsx` — that runs inside Claude Code's mod runtime, not as a `PATH` binary; adds a toolchain the gate would need in CI (blast radius, test cost)
  rejected: Python — no Python script in `scripts/` or `loomwright-lanes/`; adds an interpreter assumption on user machines (fits-stack, test cost)
  evidence: every root gate in `.github/workflows/ci.yml` is `bash scripts/<x>.sh`; `scripts/bump-version.sh` header "Portability: bash 3.2 + BSD userland (macOS) and GNU (CI)"
  revisit when: a later qa-split item (03/04) needs real parsing or a model client in the CLI
  status: confirmed

## Acceptance Criteria
- [ ] AC1: Given `selvedge/.claude-plugin/plugin.json` (`"name": "selvedge"`, `"version": "0.1.0"`, a description that says "evidenced PASS/FAIL per acceptance criterion"), when `claude plugin validate selvedge` runs, then it prints `Validation passed`; and when `selvedge/bin/selvedge --version` runs, then it prints `selvedge 0.1.0` (the manifest version, read at run time), and with no arguments it prints the version and the subcommand list, which includes `install-cli`. The validate output is committed in `selvedge/docs/evidence/gate-scopes.md`. (`/plugin install selvedge@atelier` itself can only run after merge, since `atelier` resolves the remote default branch; the evidence file says so.)
- [ ] AC2: Given `.claude-plugin/marketplace.json`, when it is read, then it lists exactly one `selvedge` entry with `"source": "./selvedge"` and a `version` equal to `selvedge/.claude-plugin/plugin.json`'s, every other entry's bytes are unchanged, and `bash scripts/validate-version.sh` passes.
- [ ] AC3: Given a fixture branch whose only changes are under `selvedge/` (plus, in one case, the selvedge entry of `marketplace.json`), when `bash scripts/bump-version.sh --check` runs, then it exits 0 with no fragment and no Loomwright bump; given the same branch plus a pending `changelog.d/` fragment, or plus a Loomwright bump, then it exits 1 and the output contains `selvedge-only change carries`; given a branch changing `selvedge/` AND another path plus a fragment, then it exits 0. These cases live in `scripts/test-bump-version.sh`, and every existing case there still passes.
- [ ] AC4: Given `selvedge/tests/run.sh`, when it runs on the real plugin, then it exits 0 after checking that the manifest is valid JSON with `name`, `version` and `description`, that the version is the first `## <X.Y.Z> — <date>` heading of `selvedge/CHANGELOG.md`, and that every `selvedge/tests/test-*.sh` passes; and given a fixture copy whose `plugin.json` version differs from its changelog's top heading (and, separately, an invalid-JSON manifest and one missing `version`), when the gate runs on it, then it exits non-zero naming the failure (tested in `selvedge/tests/test-check-release.sh`). `.github/workflows/ci.yml`'s `static` job runs `bash selvedge/tests/run.sh` in a step with no `|| true`, placed before the release-content step.
- [ ] AC5: Given a temp `HOME`, when `selvedge install-cli` runs, then `$HOME/.local/bin/selvedge` is a symlink to the plugin's `bin/selvedge`, the command prints what it did, and a second run succeeds; given `$HOME/.local/bin/selvedge` is a regular file, when it runs, then it exits non-zero, prints `refusing to overwrite`, and leaves the file byte-identical (tested in `selvedge/tests/test-cli.sh`, which also pins `--version` against the manifest and runs the CLI through the symlink).
- [ ] AC6: Given the CLI-discovery spike, when `selvedge/docs/cli-discovery.md` is read, then it states yes or no for the desktop-app load mechanism and for the installed-CLI mechanism, each with the exact command and its full output (a case the worker cannot measure is stated `unverified` with the reason and the owner-runnable command), and it states whether `install-cli` is optional (only when both are `yes`) or required.
- [ ] AC7: Given Loomwright's count/budget/doc-currency/citation/prompt-history gates (`scripts/check-doc-currency.sh`, `scripts/check-token-budget.sh`, `loomwright/scripts/test-citation-drift.sh`, `scripts/check-prompt-history-refs.sh`, `scripts/check-skills-index-sync.sh`, `scripts/check-command-sync.sh`) and the repo-wide portability gates (`scripts/check-locale-prefix.sh`, which scans every tracked or untracked `*.sh`, so `selvedge/tests/*.sh` too; `scripts/check-test-hermetic.sh`, which covers only `loomwright/scripts/` and `scripts/test-*.sh`), when their scan scopes are read, then a committed evidence file `selvedge/docs/evidence/gate-scopes.md` lists each gate's scan scope (quoting the line that defines it), states which of them reach `selvedge/` and how — expected: `check-locale-prefix.sh` scans `selvedge/tests/*.sh` (which pass by writing `env LC_ALL=C cmd`, never `LC_ALL=C cmd` at command position); `check-skills-index-sync.sh` reaches it through marketplace discovery (`.plugins[].source`) and skips it because it ships no `skills/` dir; `scripts/validate-version.sh` reads its marketplace entry and checks it against `plugin.json` by design (AC2) — record what is observed, not this expectation, states that none needed an exclusion (or names any that did), and the PR body links to it.
- [ ] AC8: Given the finished branch, when `git diff --name-only origin/main...HEAD` is read, then no path starts with `loomwright/`, no `changelog.d/` fragment is added, and `bash scripts/check-version-bump.sh` exits 0 reporting `not bumped`.
- [ ] AC9: Given `CLAUDE.md` §"Plugin Layout" and the `.claude-plugin/README.md` layout tree, when they are read, then each names `selvedge/` as a sibling plugin that releases on its own, and neither states a plugin count (the "four sibling plugins" and "lists 4 plugins" wordings are replaced by the names).

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
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| selvedge plugin | — | `selvedge/.claude-plugin/plugin.json`, `selvedge/README.md`, `selvedge/CHANGELOG.md`, `selvedge/bin/selvedge`, `selvedge/docs/cli-discovery.md`, `selvedge/docs/evidence/gate-scopes.md` | HIGH |
| selvedge gate | — | `selvedge/tests/run.sh`, `selvedge/tests/check-release.sh`, `selvedge/tests/test-check-release.sh`, `selvedge/tests/test-cli.sh` | HIGH |
| marketplace + docs + CI | `.claude-plugin/marketplace.json` (124), `CLAUDE.md` (167), `.claude-plugin/README.md` (612 — one tree row + one count wording in the existing layout tree, the single place that tree lives), `.github/workflows/ci.yml` (373) | — | HIGH |
| release scoping | `scripts/bump-version.sh` (799 — the single authority of the release rule; its header says rule and implementation live in ONE place, and the new check reuses its `resolve_base`/`chk`/`tree_frags` internals), `scripts/check-version-bump.sh` (15 — header comment only), `scripts/test-bump-version.sh` (784 — the new cases reuse its `make_branch`/`run_check`/`expect_fail` fixture helpers, which exist only there) | — | HIGH |

**Module layout:** new responsibilities and their homes — the selvedge release gate → CREATE `selvedge/tests/check-release.sh`; the CLI → CREATE `selvedge/bin/selvedge`; the selvedge test runner → CREATE `selvedge/tests/run.sh`; release scoping → appended to `scripts/bump-version.sh` (reason in the map row); its tests → appended to `scripts/test-bump-version.sh` (reason in the map row). No helper is copied by 2+ siblings.

> **Validator-owned surfaces:** `scripts/check-doc-currency.sh` scans `CLAUDE.md`, `.claude-plugin/README.md` and `.claude-plugin/marketplace.json` (its `FILES=(` list) — all three are in the map; `scripts/validate-version.sh` reads every `marketplace.json` entry, so the selvedge entry and `selvedge/.claude-plugin/plugin.json` must agree; `loomwright/scripts/test-citation-drift.sh` scans `scripts/*.sh`, `CLAUDE.md` and `.github/workflows/*.yml` — write any new reference there as a descriptive anchor, never a bare `file:N`.

## Touched-file invariants

> Grounded at base `ebd83f254f79982cac44d4f3f1836134701be7d6`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`scripts/bump-version.sh`** — keep: `--check`'s exit contract (0 consistent, 1 violated, 2 cannot check), including `bump-version: check CANNOT RUN` on a base-less or shallow clone; the plain bump and `--refold` paths unchanged; `set -uo pipefail` and its portability rule `# Portability: bash 3.2 + BSD userland (macOS) and GNU (CI): no sed -i, no mapfile, temp file + mv.` (guard every array expansion under `set -u` the way the file does, e.g. `${frags[@]+"${frags[@]}"}`); reuse: the violation accumulator `chk() { CHK[${#CHK[@]}]="$1"; }`, `resolve_base`'s `BASE_SHA="$(git merge-base HEAD "$base_ref" 2>/dev/null)"`, and `tree_frags "$BASE_SHA"` for the merge base's fragments; mirror: the failure footer `(the invariant: changelog.d/README.md, decision P7)` stays the last line of a FAILED check; fired by: CI `bash scripts/check-version-bump.sh --base refs/bump-check/base`, and `loomwright/scripts/release-refold.sh` on the sequential push path (FINALIZE, each Phase 4.5 heal push, each `/review-pr` fix push), which runs `--refold` (unchanged) and then, at its step 4, `bash scripts/bump-version.sh --check`. A selvedge-only violation therefore also makes release-refold exit 1 (do not push) — intended, and it needs no change under `loomwright/`; pinned by: `scripts/test-bump-version.sh` (`run_check() { local d="$1"; shift; ( cd "$d" && bash scripts/bump-version.sh --check "$@" )`).
- **`scripts/check-version-bump.sh`** — keep: it stays a logic-free wrapper, `exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bump-version.sh" --check "$@"`, because `scripts/ci-local.sh` turns every `bash scripts/<x>.sh` CI line into a local gate (header: "so the mutating" script's name never appears on such a line); only its header comment may change.
- **`scripts/test-bump-version.sh`** — keep: hermetic setup `. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../loomwright/scripts/hermetic-test-env.sh"` and every existing case unchanged; the `BUMP_VERSION_UNDER_TEST` override seam; reuse: `make_branch() {`, `run_check`, `expect_fail() { # expect_fail <dir> <fixed message> <label>`; fired by: CI's release-content step (`bash scripts/test-bump-version.sh`).
- **`.github/workflows/ci.yml`** — keep: the `ci` job's `needs: [static, suite]` and its aggregation block byte-identical (pinned by `loomwright/scripts/test-run-self-tests.sh` `(AG) ci.yml's aggregating ci job fails closed`, which extracts and runs that block, and by its job-shape check); the release-content step keeps its position relative to the existing steps (it deepens the clone; its comment says `after every other gate of this job because it deepens the clone`, although the sdk-spike gate already follows it at base), and the new selvedge step goes BEFORE it; gate steps carry no `|| true` (the lanes step's comment: `No `|| true`: fail-CLOSED gate.`); add no `bash scripts/<x>.sh` line to the `ci` job. The new line `bash selvedge/tests/run.sh` does not match `scripts/ci-local.sh`'s gate pattern (`bash (scripts/[A-Za-z0-9_.-]+\.sh( --self-test)?|loomwright/scripts/...` ), so it adds no local gate — say so in the step comment.

## Closed enumerations touched

> Sibling grep at base `ebd83f2`: `git grep -nF 'loomwright-lanes' origin/main -- . ':!CHANGELOG.md' ':!loomwright-lanes/*' ':!.supervisor/*'` → 28 hits in 8 files.

- **`selvedge`** (sibling: `loomwright-lanes`) — must be named in:
  - `.claude-plugin/marketplace.json` — the `plugins` array (`"name": "loomwright-lanes"`) — extend.
  - `CLAUDE.md` — §"Plugin Layout" (`containing four sibling plugins (loomwright, stackpack, mysql-mcp, loomwright-lanes)` and the `- Sibling plugins:` line) — extend, dropping the count.
  - `.claude-plugin/README.md` — the layout tree (`├── loomwright-lanes/` row and `lists 4 plugins`) — extend, dropping the count.
  - `README.md` — the lanes feature section and its install line — no change: a feature section for `/automate --parallel`, not a list of plugins.
  - `.github/workflows/ci.yml` — the lanes step's comment — no change: describes that step only.
  - `scripts/test-lanes-addon.sh` — lanes' own gate — no change: lanes-specific.
  - `docs/evidence/as24-terse-script-output.md`, `docs/evidence/as26-diet-subagent-prompts.md` — historical evidence — no change: frozen records.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `scripts/test-bump-version.sh` — selvedge-only branch + pending fragment ⇒ exit 1 | delete `selvedge-only change carries a changelog.d fragment` in `scripts/bump-version.sh` |
| `scripts/test-bump-version.sh` — selvedge-only branch + Loomwright bump ⇒ exit 1 | delete `selvedge-only change carries a loomwright bump` in `scripts/bump-version.sh` |
| `scripts/test-bump-version.sh` — mixed branch (selvedge + another path) + fragment ⇒ exit 0 | delete `scope_other=1` in `scripts/bump-version.sh` |
| `scripts/test-bump-version.sh` — selvedge-only branch (both variants: plain, and with the selvedge marketplace entry edited), no fragment, no bump ⇒ exit 0 | flip `[ "$sv_new_frags" -gt 0 ]` → `true` in `scripts/bump-version.sh` |
| `selvedge/tests/test-check-release.sh` — version/changelog mismatch fails | delete `changelog_version_mismatch` in `selvedge/tests/check-release.sh` |
| `selvedge/tests/test-check-release.sh` — invalid-JSON manifest fails | delete `manifest_invalid_json` in `selvedge/tests/check-release.sh` |
| `selvedge/tests/test-check-release.sh` — manifest missing `version` fails | delete `manifest_missing_field` in `selvedge/tests/check-release.sh` |
| `selvedge/tests/test-cli.sh` — `install-cli` refuses a regular file | delete `refusing to overwrite` in `selvedge/bin/selvedge` |
| `selvedge/tests/test-cli.sh` — `install-cli` creates the symlink | delete `ln -s` in `selvedge/bin/selvedge` |
| `selvedge/tests/test-cli.sh` — a second `install-cli` run succeeds | flip `[ -L "$dest" ] ||` → `false ||` in `selvedge/bin/selvedge` |
| `selvedge/tests/test-cli.sh` — `--version` through the symlink prints the manifest version | flip `while [ -L "$self" ]` → `while false` in `selvedge/bin/selvedge` |
| `selvedge/tests/test-cli.sh` — `--version` prints the manifest version (not a literal) | flip `"version"` → `"nversion"` in `selvedge/bin/selvedge` |

Authoring constraint for these rows to stay machine-applicable: each literal appears on exactly ONE line of its file, and that line is the whole check:
- `selvedge-only change carries a changelog.d fragment` and `selvedge-only change carries a loomwright bump` are each on its own one-line `chk` call (AC3 greps their shared prefix `selvedge-only change carries`); the fragment arm is the single line `[ "$sv_new_frags" -gt 0 ] && chk "selvedge-only change carries a changelog.d fragment …"`, where `sv_new_frags` counts pending fragments absent from the merge base.
- `scope_other=1` is the one line that marks a changed path outside every self-releasing plugin dir.
- `changelog_version_mismatch`, `manifest_invalid_json` and `manifest_missing_field` each sit on one one-line check that fails the gate (e.g. `[ "$cl_ver" = "$pj_ver" ] || fail "changelog_version_mismatch: …"`).
- In `bin/selvedge`: the install guard is the one line `[ ! -e "$dest" ] || [ -L "$dest" ] || die "refusing to overwrite …"`; `ln -s` appears only on the line that creates the link (`ln -sf`/`ln -s` both match); the symlink-resolution loop header is `while [ -L "$self" ]`; and `"version"` appears only in the one line that extracts the manifest version.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | selvedge plugin, its gate, CI step, marketplace entry, docs and CLI-discovery spike | AC1, AC2, AC4, AC5, AC6, AC7, AC8, AC9 | 4 modify, 10 create | `ci-cd`, `unit-testing` | LAUNCHABLE |
| 2 | Release scoping: `bump-version.sh --check` rejects a fragment or bump on a selvedge-only branch | AC3, AC8 | 3 modify, 0 create | `unit-testing` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "selvedge/.claude-plugin/plugin.json"}
  - {kind: "symbol", path: "selvedge/.claude-plugin/plugin.json", name: "version"}
  - {kind: "file", path: "selvedge/README.md"}
  - {kind: "file", path: "selvedge/CHANGELOG.md"}
  - {kind: "file", path: "selvedge/bin/selvedge"}
  - {kind: "symbol", path: "selvedge/bin/selvedge", name: "install-cli"}
  - {kind: "file", path: "selvedge/tests/run.sh"}
  - {kind: "file", path: "selvedge/tests/check-release.sh"}
  - {kind: "symbol", path: "selvedge/tests/check-release.sh", name: "changelog_version_mismatch"}
  - {kind: "file", path: "selvedge/tests/test-check-release.sh"}
  - {kind: "file", path: "selvedge/tests/test-cli.sh"}
  - {kind: "file", path: "selvedge/docs/cli-discovery.md"}
  - {kind: "file", path: "selvedge/docs/evidence/gate-scopes.md"}
  - {kind: "symbol", path: ".claude-plugin/marketplace.json", name: "selvedge"}
  - {kind: "symbol", path: ".github/workflows/ci.yml", name: "bash selvedge/tests/run.sh"}
  - {kind: "symbol", path: "CLAUDE.md", name: "selvedge/"}
requires: []
lanes:
  - "selvedge/**"
  - ".claude-plugin/marketplace.json"
  - ".claude-plugin/README.md"
  - "CLAUDE.md"
  - ".github/workflows/ci.yml"
external_requires:
  - "claude CLI on PATH (claude plugin validate; claude -p --plugin-dir for the spike)"
  - "Claude Code desktop app load mechanism (measured through its --plugin-dir equivalent, or recorded unverified)"

# Subtask 2
provides:
  - {kind: "symbol", path: "scripts/bump-version.sh", name: "SELF_RELEASING_PLUGINS"}
  - {kind: "symbol", path: "scripts/bump-version.sh", name: "selvedge-only change carries"}
  - {kind: "symbol", path: "scripts/test-bump-version.sh", name: "selvedge-only change carries"}
requires: []
lanes:
  - "scripts/bump-version.sh"
  - "scripts/check-version-bump.sh"
  - "scripts/test-bump-version.sh"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (independent)
Subtask 2 (independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (Subtask 2's tests build synthetic `selvedge/` paths inside temp fixture repos, never the real plugin) | NO |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2 (parallel — both have empty `requires`)
- **Recommended workers:** 2
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/ci-cd/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): 17 files exceed one worker's bound | MEDIUM | `context-bound` split into two zero-overlap subtasks |
| Feasibility (Phase 2.5): the desktop-app and installed-CLI cases of the spike may not be measurable from a worker | MEDIUM | Measure the desktop mechanism via `claude -p --plugin-dir`; installed-CLI only in an isolated scratch config; anything unmeasured is written `unverified` with an owner-runnable command, and `install-cli` is then documented as required |
| A worker adds a `changelog.d/` fragment and runs the bump out of habit, writing `loomwright/` files | HIGH | Implementation note forbids it; AC8 checks the diff and `check-version-bump.sh` reports `not bumped` |
| Adding a `ci` job (instead of a `static` step) breaks `loomwright/scripts/test-run-self-tests.sh`'s aggregator extraction, whose fix would edit `loomwright/` | HIGH | Step in `static` only; Touched-file invariants pin the `ci` job byte-identical |
| The scope check misclassifies a mixed branch as selvedge-only and blocks a legitimate Loomwright release | MEDIUM | Only bump-owned paths are ignored; any other path makes the branch non-selvedge-only; AC3's mixed case tests it |
| `/plugin install selvedge@atelier` cannot be exercised before merge (atelier resolves the remote default branch) | LOW | `claude plugin validate selvedge` pre-merge; the evidence file names the post-merge install check |
| `changelog.d/README.md` (outside this item's Touches) does not yet mention the selvedge exemption | LOW | The `--check` failure message states the rule and the fix; a follow-up can add one line to the README |
| A new comment in `ci.yml` or `scripts/*.sh` with a bare `file:N` fails `loomwright/scripts/test-citation-drift.sh` | LOW | Descriptive anchors only (CLAUDE.md citation convention) |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 1
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-13-qa-split-01-scaffold-selvedge.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-13T19:21:53Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/912
- **Branch:** feature/qa-split-01-scaffold-selvedge
- **Files changed:** 18
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** selvedge/ scaffolded as its own plugin (0.1.0, own CHANGELOG, gate in CI static, CLI stub with install-cli, marketplace entry, CLAUDE.md/.claude-plugin/README.md name it, no plugin count); bump-version.sh --check rejects a fragment, a Loomwright bump or an edit to main's fragment on a selvedge-only branch. All three integration reviews PASS (AC1–AC9 addressed); each raised MEDIUM findings that were fixed (incl. a red ci check from printf|grep -q pipes). The round-3 fix (install-cli re-run-after-update note, 8316ba2) was not re-reviewed, hence ESCALATED. Ground truth 2/2 pass; pins 12/12 held; contract_conformance pass (1); risk high (ci.yml, size, CLAUDE.md).

## Not verified
- **Desktop app session itself** — measured through its --plugin-dir mechanism with claude -p, not the app (subtask 1)
- **Installed-plugin CLI session PATH** — scratch config could not log in; owner command in selvedge/docs/cli-discovery.md (subtask 1)
- **/plugin install selvedge@atelier** — possible only after merge (subtask 1)
- **GitHub CI static step** — local only at hand-back (subtask 1)
- **loomwright/scripts/release-refold.sh step 4 on a selvedge-only branch** — not run; it calls --check unchanged (subtask 2)
