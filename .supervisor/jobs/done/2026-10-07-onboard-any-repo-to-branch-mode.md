# Supervisor Job: Onboard any repo to branch mode — guided, human-gated migration (`migrate-branch-mode.sh` + rehearsal harness)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes-v2/s3-h
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (this checkout's `.gitignore` is skip-worktree with mode line `on loomwright-meta-s3w3`; committed HEAD says `loomwright-meta` — tests must never read the live checkout's mode)
- **Source requirement:** .supervisor/requirements/meta-sync-followups/07-onboard-any-repo-to-branch-mode.md
- **Base commit:** f4b0732b8f3e6a7b64fc960073e8ab680d5af9f0

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash 3.2 + git + jq + gh scripts, same stack as `meta-sync.sh` / `setup-memory.sh` |
| 2 | Dependency Availability | CAUTION | `meta-sync.sh` exposes no scrub-only entry and no managed-path lister (`is_managed()`/`scan_file()` are internal; 04 shipped option A, no `push --dry-run`). Owner decision 2026-10-07: add `meta-sync.sh scrub` + `list-managed` subcommands (Subtask 1) rather than copy the predicate |
| 3 | Architecture Fit | CAUTION | `/setup memory` docs state the module NEVER runs `git add`/`rm`/`commit`; the migration's untrack step (`git rm -r --cached` on a NEW branch, PR opened, never merged) needs an explicit, scoped exception in `commands/setup.md` + `skills/setup/SKILL.md`. `setup-memory.sh` itself keeps its header invariant (unchanged behaviour) |
| 4 | Scope vs Supervisor Capability | CAUTION | ~16 files, well over 800 changed lines ⇒ split `context-bound` into 4 dependency-ordered subtasks |
| 5 | Hard Blockers | GO | None. Validation item 3 (full flow on a second real repo, owner doing steps e and g) is a post-PR owner step, not executable by workers |

**Overall Verdict:** CAUTION

## Task
**Goal:** Ship a deterministic, resumable, human-gated `migrate-branch-mode.sh` (plus a committed rehearsal harness) that takes ANY repo from default mode to branch mode via `/setup memory`, replacing the this-repo-only M1 runbook.

**Problem Statement:**
Repo owners adopting branch mode need a guided migration because today it exists only as `parallel-automate/operator-run/M1-migrate-this-repo.md`, a half-day hand runbook for THIS repo.
Currently, a second repo would repeat M1 by hand, including its known failures (no scrub dry run, a Rollback recipe that loses post-migration edits, an untrack PR merged before the step-6 re-check). This causes data-loss risk and hours of operator time per repo.
Success looks like `migrate-branch-mode.sh plan` + per-step subcommands that dry-run first, stop at every owner-only step (ruleset, merge), refuse to continue past a failed check, and are proved by fixtures on a local bare remote.

## Acceptance Criteria
- [ ] AC1 (subcommands): Given any checkout, when `meta-sync.sh list-managed [--tracked]` runs, then it prints exactly the paths `is_managed()` accepts (one per line — `--tracked` reads `git ls-files`, default the local tree) and exits 0; when `meta-sync.sh scrub --paths-from <list>` runs, then each hit prints ONE line `meta_sync: scrub-hit <path>:<line>: <rule>` (a NEW prefix, so the existing `meta_sync: scrub <path>: <rule>` contract that callers parse is untouched) where `<line>` is the first matching 1-based line for line-based rules (`email`, `home_path`, `token_*`, `deny_pattern:<n>`) and the literal `-` for whole-file rules (`forge_slug`, `ledger_repo`, `ledger_unverifiable`, `unreadable`, `scan_error(...)`, `deny_pattern_invalid:<n>`); exit 2 on any hit, 0 when clean, 1 on usage errors. Both paths call ONE `scan_file()` (a with-line mode flag), `push` keeps its stderr lines and exit code 2 byte-for-byte, `scrub-hit` lines go to stderr (like push's scrub lines; the `unreadable` hit, today printed by `scrub_candidates`, is printed by `scrub`'s own caller), `scrub` and `list-managed` need no branch and SKIP the mode/branch resolution that runs before dispatch (they work in a checkout whose mode reads `unknown`), the ARCHITECTURE_CONTRACTS.md §"Metadata branch" sentence listing the subcommands that run that check is updated in the same change, the meta-sync.sh SCRUB header documents the new line, the usage check that rejects `--paths-from` outside `push` is widened to `scrub`, and a test asserts a `push` hit and a `scrub` hit on the same planted file report the same rule.
- [ ] AC1b (branch-name validator): Given any name, when `setup-memory.sh valid-branch <name>` runs, then it writes nothing and exits 0 iff the EXISTING `valid_branch_name` predicate accepts it (1 otherwise, one reason line on stderr) — the same predicate `apply --branch-mode` uses, never a copy; a `test-setup-memory.sh` leg covers accept, `off`, `HEAD`, `@`, a `-`-leading name and an invalid ref, and asserts no file changed.
- [ ] AC2 (case detection): Given a repo with no managed path tracked on the default branch, when `migrate-branch-mode.sh plan` runs, then it reports case `fresh` with steps mode block → init → protect → done; given tracked managed paths, it reports case `history` with the full sequence; given a repo whose mode line already reads `on <b>` and has no tracked managed paths, it reports `already in branch mode on <b>` (the branch read from `setup-memory.sh mode`, never hard-coded) and writes nothing; a mode reading `unknown <reason>` is reported as a refusal with that reason (exit 1), never a crash. `plan` detects "already migrated" BEFORE running preconditions and is read-only in every case (no file, ref or index change — asserted by fixture).
- [ ] AC2b (fresh-case end to end): Given a fixture repo with a bare remote and no tracked managed paths, when the fresh flow runs (`plan` → `preflight` → `scrub` → `init --branch <b>` → `protect` / `protect --verify` against a PATH-stubbed `gh` → `mode-pr`), then the branch exists on the remote, the protection check passed, no untrack PR is opened, and the mode block reaches the default branch ONLY through `mode-pr`: `setup-memory.sh apply --branch-mode <b>` on a NEW branch, one commit of `.gitignore` only, a PR opened and never merged (the same scoped new-branch exception as `untrack-pr`); the flow ends with the owner told to merge it. `apply`'s side files are handled, never left behind: the `.gitignore.backup.<ts>` it writes is moved under the gitignored `.supervisor/migrate-branch-mode/` and its path recorded in the state file, and a `.supervisor/config.json` it seeds stays under `.supervisor/` (ignored by the block apply writes); the fixture's `.gitignore` has NO `.gitignore.backup.*` line and the test asserts `git status --porcelain` is empty after `mode-pr`.
- [ ] AC3 (preconditions): Given each precondition failing in turn (not on default branch; dirty tree; not equal to `origin`; a `resume-glob` run in flight; `run-lock.sh status` LOCKED; an open `chore/*-trail-*` PR; a dirty linked worktree), when `migrate-branch-mode.sh preflight` runs, then it prints each check with its result and exits non-zero, and no later step subcommand runs while the recorded preflight result is not PASS.
- [ ] AC4 (scrub gate): Given a planted scrub hit in a would-be-pushed file, when the flow runs, then `scrub` stops it BEFORE `init` with file, line and rule, and nothing is pushed.
- [ ] AC5 (rehearsal): Given a checkout, when `meta-sync-rehearsal.sh` runs (with config by default, and with `--no-config`), then it builds a scratch clone + local bare remote and runs init → push → verify (every managed path present, blob-identical, nothing extra, file types as declared) → second-checkout pull round trip (byte-identical) → corrected rollback after a post-migration edit/add/delete, drilled by running the shipped `migrate-branch-mode.sh rollback` subcommand (never a re-implemented recipe), with all kept and `.gitignore` back to pre-migration content → the twin reader contract count after a round trip; it prints one `PASS`/`FAIL` line per check, exits non-zero on any FAIL, never touches the real remote, and cleans up. Its self-test shows each check going red under its mutant (dropped file, changed blob, the M1 old rollback order, a contract without provenance).
- [ ] AC6 (create/protect/seed): Given an owner-confirmed branch name (default `loomwright-meta`; validity decided by `setup-memory.sh valid-branch <name>` BEFORE anything is written — never a copied `valid_branch_name`, and never inferred from `apply`, which exits 0 on refusal), when `init` runs, then it calls `meta-sync.sh init --branch <name>` and records the name in the state file; EVERY later meta-sync.sh call (seed push, verify-pr push, after-merge pull, rehearsal) passes `--branch <recorded name>` (fixture with a non-default name such as `team-meta` proves no call falls back to `loomwright-meta`); `protect` prints the exact ruleset (target the branch; block deletion and non-fast-forward; no bypass) and the `gh api` command, never creates or edits a ruleset itself, and `protect --verify` checks `gh api repos/<o>/<r>/rulesets` before `seed` may run; `seed` runs `meta-sync.sh push` then the A/B check against the CURRENT `origin/<default>` (A = tracked managed paths via `list-managed --tracked`, B = branch tree; A=B, every blob equal, no non-`.md`/`results.jsonl` entry on the branch) and lists tracked `.supervisor/` paths outside the managed set for an owner decision, never dropping them silently. A ≠ B stops the flow before `untrack-pr`.
- [ ] AC7 (untrack PR + merge-time re-check): Given a passing seed, when `untrack-pr` runs, then it writes the branch-mode `.gitignore` block via `setup-memory.sh apply --branch-mode <b>`, `git rm -r --cached` the managed paths on a NEW branch, opens a PR whose body carries the A/B counts, the empty diffs, the pre-migration SHA and the instruction to run `migrate-branch-mode.sh verify-pr <n>` immediately before merging — and never merges; `verify-pr <n>` repeats the seed check against the then-current default branch and pushes anything new first; `after-merge` runs `git pull` then `meta-sync.sh pull`, confirms the files are back and `git status --porcelain` is empty, and prints the two commands every other checkout must run. `untrack-pr` handles `apply`'s `.gitignore.backup.<ts>` exactly like `mode-pr` (moved under `.supervisor/migrate-branch-mode/`, path recorded), so `after-merge`'s empty-porcelain check passes in a repo that does not ignore backup files (asserted by fixture).
- [ ] AC8 (rollback + resumability): Given a migrated fixture with a post-migration edit, add and delete, when `rollback` runs, then it implements the corrected #361 recipe (re-track the CURRENT branch files; nothing written since migration is lost) using BSD/GNU-portable commands (no GNU-only `xargs -r`); each step records its result in a gitignored state file under `.supervisor/` so a flow stopped at `protect` or `untrack-pr` resumes from there. Mutation controls in `test-migrate-branch-mode.sh`: skipping the `verify-pr` re-check, and the old M1 rollback order, each fail a test.
- [ ] AC9a (setup docs): Given the change, when `commands/setup.md` and `skills/setup/SKILL.md` are read, then they document a `memory migrate` flow (the command owns only the asking; the script owns every step) and state the ONE scoped exception to the module's never-`git add/rm/commit` rule: `migrate-branch-mode.sh` `mode-pr` / `untrack-pr` commit on a NEW branch and open a PR, never merge; `setup-memory.sh` itself keeps its header invariant.
- [ ] AC9b (hint): Given the change, when `test-setup-memory.sh` runs, then the apply `Next:` hint and disclosure name `migrate-branch-mode.sh plan` instead of "the migration runbook, M1", its matching assertions are updated in the same change, and every other leg stays green (no other behaviour change).
- [ ] AC9c (CI pull): Given a CI run, when `.github/workflows/ci.yml` executes, then a separate, self-contained read-only `meta-sync.sh pull` step runs AFTER the self-test suite step and BEFORE the sdk-spike step, and its failure can never fail the job (`continue-on-error: true`).
- [ ] AC9d (schema + changelog): Given the change, when `test-result-schemas-split.sh` runs, then `loomwright/docs/result-schemas/migrate-branch-mode-state.md` and its `RESULT_SCHEMAS.md` index entry pass checks A–F; and a `changelog.d/meta-sync-followups-07-onboard-any-repo-to-branch-mode.md` fragment exists in the `changelog.d/README.md` format.
- [ ] AC10 (D.4 metadata docs, outside the code diff): Given Subtask 4, when its worker finishes, then it has written, by ABSOLUTE path into the PRIMARY checkout (the path is passed in its spawn prompt), the corrected #361 Rollback recipe replacing M1's `## Rollback` section in `.supervisor/requirements/parallel-automate/operator-run/M1-migrate-this-repo.md`, and a new `M2-carry-learning-stores.md` beside it (backup → rehearsal via `meta-sync-rehearsal.sh` → real push → verify → consent recorded; pause for owner at each step; only commands/flags present in the shipped scripts' `--help`); the Supervisor confirms both before FINALIZE (file exists; M1's Rollback no longer contains the old `git revert` → `meta-sync pull` → `git add` order) and the PR body lists them as metadata-branch edits that ride this run's trail meta-push.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `meta-sync.sh` `scrub` + `list-managed` subcommands; `setup-memory.sh valid-branch` | AC1, AC1b, AC4 (scrub half) | 5 modify, 0 create | `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | `migrate-branch-mode.sh` (plan, preflight, scrub, rehearse, init, protect, mode-pr, seed, untrack-pr, verify-pr, after-merge, rollback, state) + self-test | AC2, AC2b, AC3, AC4, AC6, AC7, AC8 | 0 modify, 2 create | `skills/error-handling/SKILL.md`, `skills/ci-cd/SKILL.md`, `skills/automate-loop/SKILL.md` | BLOCKED (by #1) |
| 3 | `meta-sync-rehearsal.sh` harness + self-test | AC5 | 2 modify, 2 create | `skills/ci-cd/SKILL.md` | BLOCKED (by #2) |
| 4 | Docs, `/setup memory migrate`, setup-memory hint, CI pull step, schema file, changelog, vendor manifest, D.4 metadata docs | AC9a, AC9b, AC9c, AC9d, AC10 | 7 modify, 2 create (+2 metadata-branch files) | `skills/ci-cd/SKILL.md`, `skills/setup/SKILL.md` | BLOCKED (by #3) |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/meta-sync.sh"}
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "cmd_scrub"}
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "cmd_list_managed"}
  - {kind: "symbol", path: "loomwright/scripts/test-meta-sync.sh", name: "list-managed"}
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "valid-branch"}
requires: []
lanes:
  - "loomwright/scripts/meta-sync.sh"
  - "loomwright/scripts/test-meta-sync.sh"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/scripts/setup-memory.sh"
  - "loomwright/scripts/test-setup-memory.sh"
external_requires:
  - "git, jq (already required by meta-sync.sh)"

# Subtask 2
provides:
  - {kind: "file", path: "loomwright/scripts/migrate-branch-mode.sh"}
  - {kind: "file", path: "loomwright/scripts/test-migrate-branch-mode.sh"}
  - {kind: "symbol", path: "loomwright/scripts/migrate-branch-mode.sh", name: "cmd_plan"}
  - {kind: "symbol", path: "loomwright/scripts/migrate-branch-mode.sh", name: "cmd_verify_pr"}
  - {kind: "symbol", path: "loomwright/scripts/migrate-branch-mode.sh", name: "cmd_rollback"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "cmd_scrub"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "cmd_list_managed"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "valid-branch"}
lanes:
  - "loomwright/scripts/migrate-branch-mode.sh"
  - "loomwright/scripts/test-migrate-branch-mode.sh"
external_requires:
  - "gh CLI (stubbed in tests via a PATH stub; never called live by the self-test)"

# Subtask 3
provides:
  - {kind: "file", path: "loomwright/scripts/meta-sync-rehearsal.sh"}
  - {kind: "file", path: "loomwright/scripts/test-meta-sync-rehearsal.sh"}
requires:
  - {from: "2", kind: "symbol", path: "loomwright/scripts/migrate-branch-mode.sh", name: "cmd_rollback"}
lanes:
  - "loomwright/scripts/meta-sync-rehearsal.sh"
  - "loomwright/scripts/test-meta-sync-rehearsal.sh"
  - "loomwright/scripts/migrate-branch-mode.sh"
  - "loomwright/scripts/test-migrate-branch-mode.sh"
external_requires: []

# Subtask 4
provides:
  - {kind: "file", path: "loomwright/docs/result-schemas/migrate-branch-mode-state.md"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "MIGRATE_BRANCH_MODE_STATE"}
  - {kind: "file", path: "changelog.d/meta-sync-followups-07-onboard-any-repo-to-branch-mode.md"}
  - {kind: "symbol", path: "loomwright/commands/setup.md", name: "migrate-branch-mode.sh"}
  - {kind: "symbol", path: "loomwright/skills/setup/SKILL.md", name: "migrate-branch-mode.sh"}
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "migrate-branch-mode.sh plan"}
  - {kind: "symbol", path: ".github/workflows/ci.yml", name: "meta-sync.sh pull"}
requires:
  - {from: "2", kind: "file", path: "loomwright/scripts/migrate-branch-mode.sh"}
  - {from: "3", kind: "file", path: "loomwright/scripts/meta-sync-rehearsal.sh"}
lanes:
  - "loomwright/commands/setup.md"
  - "loomwright/skills/setup/SKILL.md"
  - "loomwright/scripts/setup-memory.sh"
  - "loomwright/scripts/test-setup-memory.sh"
  - ".github/workflows/ci.yml"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/result-schemas/migrate-branch-mode-state.md"
  - "changelog.d/meta-sync-followups-07-onboard-any-repo-to-branch-mode.md"
external_requires:
  - "Metadata-branch docs (AC10) are written in the PRIMARY checkout's gitignored .supervisor/requirements/parallel-automate/operator-run/, not in the worktree diff"
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3 ──→ Subtask 4
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 2 | Subtask 3 | `loomwright/scripts/migrate-branch-mode.sh`, `loomwright/scripts/test-migrate-branch-mode.sh` (3 wires the `rehearse` step to the new harness and tests it) | YES (ordered by requires) |
| Subtask 1 | Subtask 4 | `loomwright/scripts/setup-memory.sh`, `loomwright/scripts/test-setup-memory.sh` (1 adds `valid-branch`; 4 re-points the Next hint) | YES (ordered: 4 is downstream of 1 via 2 and 3) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2
- **Batch 3:** Subtask 3
- **Batch 4:** Subtask 4
- **Recommended workers:** 1
- **Estimated batches:** 4

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/error-handling/SKILL.md` |
| 2 | `skills/error-handling/SKILL.md`, `skills/ci-cd/SKILL.md`, `skills/automate-loop/SKILL.md` (§"Branch mode", resume-glob / run-lock preconditions) |
| 3 | `skills/ci-cd/SKILL.md` |
| 4 | `skills/ci-cd/SKILL.md`, `skills/setup/SKILL.md` |

## Implementation Notes (from Phase 3 analysis — read before coding)
- **One predicate, one rule table.** `list-managed` MUST call the existing `is_managed()`; `scrub` MUST reuse `scan_file()`'s rule table (extend it to report the first matching line number, e.g. `grep -n`), so `push` and `scrub` cannot drift. `push`'s existing stderr lines and exit code 2 stay byte-for-byte (existing test-meta-sync.sh legs must stay green). Allowlist resolution for `forge_slug` is the same as push (`setup-memory.sh allowlist`).
- **Test conventions:** new tests source `hermetic-test-env.sh` as their first executable line (`scripts/check-test-hermetic.sh`); reuse the `mkworld`/`clone`/`ms` fixture shape from `test-meta-sync.sh` (bare `origin.git` in one `mktemp -d`); `ok`/`FAIL` lines + a final `N passed, M failed` line, exit by fail count. Mutation controls follow `build_mutant` (copy, sed, assert differs, `bash -n`; a mutant that does not build counts as FAIL). Stub `gh` with a PATH stub (pattern: `test-automate-trail.sh`'s `$STUBBIN/gh`); CI has no network and no gh.
- **macOS bash 3.2 + BSD userland:** no GNU-only flags (`xargs -r`, `sed -i` without suffix, `stat -c`), no `timeout`, `env LC_ALL=C` not a temp locale prefix (`scripts/check-locale-prefix.sh`), guard empty-array expansion under `set -u`.
- **Never read this checkout's live mode/lock in tests** — the live `.gitignore` is skip-worktree on `loomwright-meta-s3w3` and the run lock is held by this /automate run. Every test builds its own fixture repo.
- **`plan` detects "already migrated" before running preconditions** (the run lock is legitimately held during an /automate run).
- **Tracked non-managed `.supervisor/` paths** (this repo: two `salvage/*/check.sh`) are listed for an owner decision in `seed`, never dropped.
- **CI step placement:** after the self-test suite step and before the sdk-spike step (two existing tests change behaviour when real run history is present — `test-harvest-conventions.sh`, `test-automate-helpers.sh` W19), `continue-on-error: true` or `|| echo`, read-only (pull never pushes). Do not cite ci.yml by bare line number anywhere (`test-citation-drift.sh`).
- **No vendor tokens in Subtasks 1–3:** `meta-sync.sh`, `migrate-branch-mode.sh`, `meta-sync-rehearsal.sh` and their tests must contain no counted vendor token (`CLAUDE_PLUGIN_ROOT`, `CLAUDE_CODE_`, `claude -p`, `.claude/`, `AskUserQuestion`, …) — they are `core` with allowance 0 until Subtask 4, and the ratchet would fail mid-run. If one is unavoidable, the SAME subtask adds the manifest allowance.
- **Vendor-coupling ratchet:** a new script needs a `vendor-coupling-manifest.json` allowance only if it carries a literal token (e.g. `.claude/`); raising `commands/setup.md` / `skills/setup/SKILL.md` allowances needs a changed `allowance_reasons` line. Run `scripts/check-vendor-coupling.sh`.
- **Result-schema split:** the new per-schema file starts with the same `## ` heading as its index entry and has exactly one top-level `## `; the index entry is `See [result-schemas/<f>.md](result-schemas/<f>.md).` (`test-result-schemas-split.sh` checks A–F).
- **Version:** never hand-edit version files; only the `changelog.d/` fragment (`changelog.d/README.md`).
- **Pre-push:** `bash scripts/ci-local.sh` only.

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

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| `scrub`/`list-managed` drift from `push`'s scrub and `is_managed()` (Feasibility (Phase 2.5)) | HIGH | Reuse the existing functions; a test asserts `scrub` and a `push` over the same planted hit report the same rule, and `list-managed` equals the set `push` would publish |
| Rollback loses post-migration edits (M1's documented failure) | HIGH | Implement only the corrected #361 recipe; mutation control with the old M1 order must fail a test; rehearsal drills it before anything real |
| Untrack PR merged before the merge-time re-check (M1's lesson) | HIGH | `verify-pr` is a precondition written into the PR body; mutation control "skip verify-pr" must fail a test; script never merges |
| `git rm --cached` contradicts the setup module's never-`git rm` invariant (Feasibility (Phase 2.5)) | MEDIUM | Confine it to `migrate-branch-mode.sh untrack-pr` on a new branch with an opened, unmerged PR; document the scoped exception; `setup-memory.sh` stays write-limited |
| Tests read the live checkout's mode line/run lock (skip-worktree `.gitignore`, lock held by this run) | MEDIUM | All fixtures in `mktemp -d` repos with their own bare remotes; never `--root` the primary |
| `setup-memory.sh apply` side files (`.gitignore.backup.<ts>`, seeded `.supervisor/config.json`) left untracked in a target repo break the empty-porcelain checks | MEDIUM | `mode-pr`/`untrack-pr` move the backup under `.supervisor/migrate-branch-mode/` and record it; fixtures without a `.gitignore.backup.*` ignore line assert porcelain-clean |
| CI pull step changes other tests' inputs or fails the job | MEDIUM | Place after the self-test suite; `continue-on-error`; read-only |
| BSD vs GNU userland (`xargs -r`, `sed -i`, `stat`) — macOS-green ≠ CI-green | MEDIUM | Portable constructs only; run tests under `/bin/bash` 3.2 locally and on CI Linux |
| Full flow on a second real repo (Validation 3) and the D3 CI outcome (sdk-spike corpus sweep reports `parseBrief threw on …` instead of `SKIP` on main) cannot be verified by workers | MEDIUM | Both listed as post-merge owner checks in the PR body, with the exact command sequence and what to paste back |
| Scope size (4 subtasks, ~16 files) (Feasibility (Phase 2.5)) | MEDIUM | Sequential batches, one worker, each subtask green before the next |
| The PR edits `.github/workflows/ci.yml`, so `claude-review` skips itself and exits green with NO review posted | MEDIUM | PR body states "workflow file changed — claude-review skipped; owner reviews by hand"; Phase 4.5 integrated review is the executing lens; never read a green `claude-review` as reviewed |
| `ci.yml` is shared with `host-contract/01` (adds its own CI step) — merge conflict | MEDIUM | The pull step is a separate, self-contained step; on a conflict escalate, never force-resolve |
| AC10 metadata docs live outside the worktree and outside `outputs_verified` (not gate-verified) | MEDIUM | Worker writes them by absolute primary-checkout path given in its spawn prompt; Supervisor checks both before FINALIZE; they ride the trail meta-push after merge |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 4
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-07-onboard-any-repo-to-branch-mode.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-07T09:35:10Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/417
- **Branch:** feature/meta-sync-followups-07-onboard-branch-mode
- **Files changed:** 18
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** migrate-branch-mode.sh + meta-sync-rehearsal.sh + meta-sync scrub/list-managed + setup-memory valid-branch, /setup memory migrate docs, CI pull step, schema, changelog. 3 heal iterations each fixed a reproduced HIGH; the final fix (500d1b0) was not re-reviewed. Ground truth 2/2.

## Not verified
- **Real gh / GitHub rulesets paths (protect --verify; PR creation in mode-pr, untrack-pr, rollback)** — tested only against a stubbed gh (subtask 2/4)
- **.github/workflows/ci.yml pull step** — no Actions runner; YAML parse + step order only (subtask 4)
- **M1 Rollback replaced / M2-carry-learning-stores.md created (operator-run/, gitignored)** — not run; outside the outputs_verified gate (subtask 4)
