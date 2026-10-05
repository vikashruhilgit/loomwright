# Supervisor Job: meta-sync — pin the push-retry exhaustion and missing-meta-base-object fallbacks with tests

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes-v2/s2-e
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 tracked changes), branch: main @ c1692b0 (== origin/main)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/meta-sync-followups/01-untested-push-and-base-fallbacks.md
- **Base commit:** c1692b091ef1747c6d600cd6cc2073277981f880

> **Warning (1):** sibling lane checkouts (`../s2-*`) may run at the same time from their own directories. Never `cd`
> outside this checkout; never use bare `git stash`. Branch mode is ON (`loomwright-meta-s2`):
> `.supervisor/requirements/**` lives on the metadata branch and is gitignored on `main` — this PR must not commit any
> requirement file.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + git; the existing hermetic `test-meta-sync.sh` harness (bare origin + clones in one `mktemp -d`). |
| 2 | Dependency Availability | GO | `git` (server-side `pre-receive` hooks on a local bare repo run on `git push`), `jq` not needed. |
| 3 | Architecture Fit | GO | Adds two legs + two sed-built mutation controls to an existing test file, the exact pattern legs 20/21 already use (`build_mutant`). |
| 4 | Scope vs Supervisor Capability | GO | One subtask, 1 test file + 1 fragment (+ the bump's version files as the last commit). |
| 5 | Hard Blockers | GO | None. `meta-sync.sh` is touched only if a new leg exposes a defect. |

**Overall Verdict:** GO

## Task
**Goal:** Add two test legs to `loomwright/scripts/test-meta-sync.sh` that pin two currently-untested fail-closed branches of `loomwright/scripts/meta-sync.sh` — `cmd_push`'s exhausted-retry `push_failed` exit and `load_base`'s missing-meta-base-object fallback to the no-base (history-aware) derivation — each proven load-bearing by a sed-built mutant that turns it red.

**Problem Statement:**
A regression in either branch would ship silently: no test drives a remote that rejects every push, and no test removes the tree object `<gitdir>/meta-base` records. The deny-file and jq-missing branches the original finding named are already covered (legs 32–33) and are out of scope.

## Acceptance Criteria
- [ ] AC-1 Given a bare origin whose `pre-receive` hook rejects every push (and records one line per invocation), when `meta-sync.sh push` runs from a synced clone with a local change, then it exits 1 and its output contains `push_failed — rejected <N> times; nothing forced, meta-base untouched`, the branch tip on origin is unchanged, the clone's `<gitdir>/meta-base` is byte-unchanged, the hook was invoked exactly `<N>` times where `<N>` is the script's own `MAX_ATTEMPTS` value (read from `meta-sync.sh` with a grep, never hard-coded), and no `git push` the script ran carried a force form (`--force`, `-f`, `--force-with-lease`, or a `+`-prefixed refspec) — asserted from a PATH `git` shim log of push argv (the technique legs 22/27 use). The shim log MUST hold exactly `<N>` push lines (the same `<N>` as the hook count) before the force-form check runs, so an empty log can never pass it.
- [ ] AC-2 Given a synced clone whose recorded meta-base tree object is absent from the object store, when `push` runs, then the output contains `meta-base '<sha>' is missing from the object store — falling back to the no-base (history-aware) derivation`, and the result equals the no-base derivation: a file a sibling deleted on the branch (whose local copy still equals a historical blob) is NOT re-added to the branch, and a genuinely new local file IS pushed.
- [ ] AC-3 Given the same missing-object state, when `pull` runs, then the same warning is printed and the branch-deleted file is deleted locally (not resurrected), with exit 0.
- [ ] AC-4 Given the missing-object state AND an unrelated conflict anywhere in the managed set (a local edit away from every historical blob of a path the branch holds), when `push` runs, then it exits 1 naming the conflict and the branch tip is unchanged — nothing is published before the whole-set derivation completes.
- [ ] AC-5 Each new leg turns red under its own mutant (sed-patched copy in the test's temp dir via the existing `build_mutant`, never an env-var seam in the shipped script): (a) a mutant whose exhausted-retry path exits 0 instead of dying `push_failed` turns the AC-1 assertion red; (b) a mutant whose `load_base` treats a missing base object as the EMPTY tree (`HAVE_BASE=1`, `BASE_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904`) instead of falling back to the history-aware derivation turns the AC-2 assertion red by re-adding the branch-deleted file (a red by crash — e.g. `could not list the meta-base tree` — is reported as inconclusive, not as proof). Each mutant is gated (built, differs from the original, contains the expected text, passes `bash -n`) — an unbuildable mutant is reported as an inconclusive FAIL, never a pass. The mutant's sed expression and the red leg's output are recorded in WORKER_RESULT and in the PR body.
- [ ] AC-6 The `# Covers` header list at the top of `test-meta-sync.sh` names both new legs and both new mutation controls (same change — the header restates the leg list).
- [ ] AC-7 `bash scripts/ci-local.sh` green (includes `loomwright/scripts/run-self-tests.sh`, root `scripts/test-*.sh` and `scripts/check-*.sh`); the PR carries `changelog.d/meta-sync-followups-01-untested-push-and-base-fallbacks.md`, and `bash scripts/bump-version.sh` is run as the LAST commit (no hand edit of `plugin.json` / `marketplace.json` / `CHANGELOG.md`).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Two meta-sync test legs + mutation controls, fragment, bump | ALL (AC-1 … AC-7) | 1 modify (+ bump's 3 version files), 1 create (fragment) | `unit-testing`, `quality-checklist` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/test-meta-sync.sh", name: "push_failed"}
  - {kind: "symbol", path: "loomwright/scripts/test-meta-sync.sh", name: "missing from the object store"}
  - {kind: "symbol", path: "loomwright/scripts/test-meta-sync.sh", name: "MAX_ATTEMPTS"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "meta-sync — test the push-retry exhaustion and missing-meta-base-object fallback"}
requires: []
lanes:
  - "loomwright/scripts/test-meta-sync.sh"
  - "loomwright/scripts/meta-sync.sh"
  - "changelog.d/**"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires:
  - "git server-side pre-receive hook execution on a local bare repo"
```

**Exact-name mandate:** the AC-1 assertion matches the literal `push_failed` text and reads the bound from the literal `MAX_ATTEMPTS=` line of `meta-sync.sh`; the AC-2/AC-3 assertion matches the literal `missing from the object store` warning text. The fragment `changelog.d/meta-sync-followups-01-untested-push-and-base-fallbacks.md` is folded and deleted by `bump-version.sh` in the last commit, so it is deliberately NOT a `provides` entry; instead `CHANGELOG.md` must carry the fragment's headline verbatim — the fragment's headline line MUST be exactly `meta-sync — test the push-retry exhaustion and missing-meta-base-object fallback` (em dash), so the fold is verifiable.

## Parallelism Analysis

### Dependency Graph
Single subtask — no graph.

### File Overlap Matrix
Not applicable (one subtask).

### Batch Plan
One batch, one worker.

## Implementation Notes (for the worker)
- **Harness:** reuse `synced_pair`, `ms`, `put`, `br_tip`, `br_has`, `br_show`, `base_of`, `check`, and `build_mutant` (defined above leg 20). Put the two new legs before the `# Mutation controls` divider and the two new mutation controls after controls 20/21; number them after the highest existing number (legs 34/35, controls 36/37 — or whatever is next on the branch).
- **Rejecting remote (AC-1):** `origin.git/hooks/pre-receive` that appends one line to a log file, drains stdin (`cat >/dev/null`) and `exit 1`; remove it after the leg. The script sleeps 1s between attempts, so the leg costs ~4s — acceptable. Count attempts from the hook log, not from the script's own `rejected (attempt` lines (an independent observer).
- **No-force evidence (AC-1):** a PATH shim directory with a `git` wrapper that logs `"$@"` when ANY argument is `push` (the SUT calls `git -C <root> push -q origin …` through `g()`, so the verb is NOT `$1` — match like leg 22's `mkshim`, which tests `$3`, or scan all args), then `exec`s the real git (resolve the real git path BEFORE prepending the shim to PATH). First assert the log holds exactly `<N>` push lines, THEN assert none carry `--force`, `-f`, `--force-with-lease`, or a refspec starting with `+`.
- **Missing object (AC-2/3/4) — fixed fixture:** write a well-formed but NONEXISTENT 40-hex sha (e.g. `printf '%040d\n' 1` style, or `deadbeef…`) into the clone's `.git/meta-base`, then self-check `git cat-file -e <sha>^{tree}` fails before running the SUT. Do NOT use the delete-ref-and-prune shape: the SUT's own `fetch_or_exit` runs before `load_base` and the meta-base tree after a pull is R's tree (part of branch history), so the fetch restores the object and the leg would miss the warning — a fixture problem, not a `meta-sync.sh` defect. Build the deleted-on-branch state first: in synced_pair, A deletes `$RQ/d.md` and pushes, so B's untouched `d.md` equals a historical blob.
- **Mutant (a):** sed the final `die "push_failed — …"` line into `exit 0` (or `say no_changes; exit 0`); must NOT make the loop unbounded (no infinite-retry mutant). **Mutant (b):** sed `load_base`'s fallback branch so a failed `cat-file -e` sets `HAVE_BASE=1` and `BASE_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904` (git's built-in empty tree — readable by `ls-tree` in every repo without being written) — this makes d.md read as "new local file" and re-adds it, the exact regression AC-2 guards. Use a sed delimiter that does not collide with the target line (repo lesson fa32a308).
- **If a leg exposes a real defect in `meta-sync.sh`**, fix it minimally and say so in WORKER_RESULT; otherwise do not touch `meta-sync.sh`.
- **Bash 3.2 / BSD:** no `declare -A`, no `timeout`, no GNU-only flags. Validate with `bash loomwright/scripts/test-meta-sync.sh`.
- **No requirement file is committed** (branch mode).
- **Bump last:** write the fragment, commit the test change, then `bash scripts/bump-version.sh` as its own final commit (it folds every pending `changelog.d/` fragment — that is expected).

## Skill References

| Skill | Why |
|---|---|
| `skills/unit-testing/SKILL.md` | Assertion structure, one observable per assertion |
| `skills/quality-checklist/SKILL.md` | Pre/post-implementation gates |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Prior churn on `meta-sync.sh` / `test-meta-sync.sh` — drain_churn + self_heal_churn, 2 rounds on 1 PR (Prior churn (postmortem ledger)) | MEDIUM | Keep the change test-only unless a defect is exposed; assert each observable separately with the exact output in the check message, so a reviewer can see what was proven |
| A mutation control that silently no-ops (sed did not apply / empty mutant) reads as a pass | MEDIUM | `build_mutant` gates non-empty + differs + expected text + `bash -n`; unbuildable ⇒ FAIL (lesson fa32a308) |
| A pruned-object fixture is silently restored by the SUT's own fetch (fetch runs before `load_base`; the post-pull meta-base tree is in branch history) — a missing warning would then be a fixture artefact, misread as a script defect | MEDIUM | Fixed fixture: a nonexistent 40-hex sha in `.git/meta-base`, self-checked with `cat-file -e` before the SUT; the prune shape is not used |
| The no-force shim never matches (`push` is not `$1` under `git -C <root>`), leaving an empty log that passes every force-form check | MEDIUM | AC-1 requires exactly `<N>` logged push lines before the force-form check |
| PATH `git` shim recursion (shim calls itself) or shim leaking into later legs | LOW | Resolve the real git path before prepending; scope the PATH change to the one `ms`-style call (subshell / inline `PATH=… bash …`) |
| Bump folds other merged-but-unfolded fragments (7 pending on main) | LOW | Expected by `changelog.d/README.md` "Who runs the bump"; if `main` moves before merge, drop the bump commit, rebase, re-run |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-10-05-meta-sync-untested-fallbacks.md

## Plan Review: PASS (attempt 2/3)

## Outcome
- **Status:** completed
- **Completed:** 2026-10-05T01:39:20Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/382
- **Branch:** feature/meta-sync-followups-01-untested-fallbacks
- **Files changed:** 11
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** test-meta-sync.sh legs 34 (push_failed after MAX_ATTEMPTS rejected pushes, no force form) and 35 (missing meta-base object → history-aware derivation for push/pull/whole-set conflict) + mutation controls 36/37, each red under its own sed mutant; meta-sync.sh unchanged; bump to 15.121.0 last. Phase 4.5 consistency_audit PASS on iteration 1 (9 extra reviewer mutants held); 1 MEDIUM drift dismissed (ARCHITECTURE_CONTRACTS.md "two" mutation controls). Ground truth 2/2.
