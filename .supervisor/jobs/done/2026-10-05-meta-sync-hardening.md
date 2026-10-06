# Supervisor Job: meta-sync hardening — symlinked non-managed files, pinned hardening branches, branch from the mode line

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes-v2/s3-b
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 tracked changes), branch: main @ 3217da0 (== origin/main)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/meta-sync-followups/08-meta-sync-hardening.md
- **Base commit:** 3217da0a7fa49a315d60625321be2ae6b20637b9

> **Warning (1):** sibling lane checkouts (`../s3-*`) may run at the same time from their own directories. Never `cd`
> outside this checkout; never use bare `git stash`. Branch mode is ON in this checkout (mode line
> `# loomwright-meta-branch: loomwright-meta-s3w1`): `.supervisor/requirements/**` lives on the metadata branch and is
> gitignored on `main` — this PR must not commit any requirement file. **Never run `meta-sync.sh push` against this
> checkout's real `origin`** — every running-system check uses a scratch bare origin under `mktemp -d`.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + git; the existing hermetic `test-meta-sync.sh` harness (bare origin + clones in one `mktemp -d`, `build_mutant` sed mutants). |
| 2 | Dependency Availability | GO | `git`; `setup-memory.sh mode` already exists and is the ONE mode-line reader (`meta-sync.sh` already shells out to its sibling `setup-memory.sh` for `allowlist`). |
| 3 | Architecture Fit | GO | Part A narrows one predicate; Part B adds test legs only; Part C adds an argument-resolution step before any fetch/lock. |
| 4 | Scope vs Supervisor Capability | GO | One subtask: 1 script, 1 test file, 1 doc section, 1 fragment (+ bump). All three parts touch the same two files, so a split would only serialize on them. |
| 5 | Hard Blockers | GO | None. |

**Overall Verdict:** GO

## Task
**Goal:** One `meta-sync.sh` change set: (A) a symlinked non-managed FILE under `.supervisor/requirements/` no longer refuses the whole sync; (B) four untested iteration-2 hardening branches are pinned by test legs, each proven by a sed mutant; (C) with no `--branch`, the default branch comes from the checkout's mode line, and a `--branch` that disagrees with the mode line is refused unless forced.

**Problem Statement:**
(A) `symlink_hazard`'s second arm `is_managed "$1/x.md"` matches every path under `requirements/`, so a symlinked `requirements/q/design.png` makes `pull`/`push` exit 1 `meta_sync: symlink …`, although such a file can neither hide managed files nor be written through, and the documented rule says "any **folder** under requirements/". (B) The `--no-write-fetch-head` fallback, `union_into`'s "changed during the sync" re-check, nested `reclaim_lock`, and `write_base_file`'s directory guard have no test. (C) `BRANCH="loomwright-meta"` is a constant; a plain `meta-sync.sh pull|push` in a lane checkout whose mode line names another branch targets the REAL `loomwright-meta` (seen in S1 v2's wrap-up).

## Acceptance Criteria

### Part A — symlinked non-managed file
- [ ] AC-A1 Given `.supervisor/requirements/q/design.png` is a symlink to a regular file (target outside `.supervisor/`), when `pull` and `push` run, then both exit 0, no `meta_sync: symlink` line is printed, and the branch carries no `design.png` entry.
- [ ] AC-A2 Given (each separately) a symlinked DIRECTORY under `requirements/`, a DANGLING symlink under `requirements/` (e.g. `requirements/q/gone` → nonexistent), and a symlinked managed `.md` under `requirements/`, when `pull` and `push` run, then each exits 1 with `meta_sync: symlink <path>`, the branch tip and `meta-base` are unchanged, and nothing is deleted from the branch. (Existing leg 26 already covers the symlinked folder and managed-file shapes; add the dangling shape and keep the others green.)
- [ ] AC-A3 The fix applies the `"$1/x.md"` arm only when the symlink resolves to a directory or is dangling (`[ -d "$ROOT/$1" ] || [ ! -e "$ROOT/$1" ]`, or an equivalent precise rule); the first arm (`is_managed "$1"`) and the fixed-name ancestor list are unchanged.
- [ ] AC-A4 A sed mutant restoring the old unconditional `is_managed "$1" || is_managed "$1/x.md"` turns the AC-A1 assertion red.

### Part B — pin the iteration-2 hardening branches (meta-sync.sh edited only where a leg exposes a defect — AC-B4 already does)
- [ ] AC-B1 **Fetch fallback:** with a PATH `git` shim that rejects any invocation carrying `--no-write-fetch-head` (exit 129, stderr naming the option the way git's own "unknown option" error does) and passes everything else to the real git, `pull` and `push` still succeed (exit 0, the pushed/pulled content correct), and the shim log proves the flagged fetch was attempted and the plain-fetch retry ran. A mutant that drops the retry (the fallback's second `g fetch` replaced by `return 1`) turns the leg red.
- [ ] AC-B2 **Changed during the sync:** the fixture's remote change makes the pull plan a UNION on `.supervisor/postmortem/results.jsonl` AND a TAKE_R on at least one managed path that sorts BEFORE it (e.g. a `.supervisor/automate/*.md` or `.supervisor/jobs/done/*.md` file). A deterministic hook (PATH `git` shim, legs 22/27 technique) appends a line to the local ledger INSIDE the real window — after the planning `hash-object` of the ledger has returned and before `union_into` copies the working file (`cat "$4" > "$WORK/u.l"`); e.g. append AFTER the real git returns on the first `hash-object` invocation naming the ledger, or on `union_into`'s `g cat-file blob "$r"`. Assert: `pull` exits non-zero with `changed during the sync`; the local ledger = pre-pull bytes + the injected line only; `meta-base` byte-unchanged; and NO other managed file was written or deleted (the TAKE_R path keeps its pre-pull bytes). **Known defect this exposes:** on base, `cmd_pull` walks the plan in path order and writes TAKE_R paths before the ledger's union fails, so the "nothing changed" half is red today — fix it minimally (e.g. build every UNION result into its temp file in a pre-pass before the first write/delete, then rename; or an equivalent that keeps the containment re-checks) and say so in the PR body (AC-B4 precedent). A mutant that removes the hash re-check turns the leg red.
- [ ] AC-B3 **Nested reclaim:** with `<gitdir>/meta-sync.lock` (pid file = a dead pid P) AND `<gitdir>/meta-sync.lock.reclaim.P` (pid file = a dead pid Q) planted, the next `push` reclaims both (neither directory remains afterwards), proceeds, exits 0, and never runs with two holders (reuse leg 27's holder log technique). A mutant that removes the one-level-up reclaim (`if lock_is_stale "$m" "$w"; then reclaim_lock …` dropped) turns the leg red (the run waits out `META_SYNC_LOCK_WAIT_SECS` — set it small in the leg — and dies `locked`).
- [ ] AC-B4 **meta-base directory guard — a defect the leg exposes, fixed:** on base 3217da0, `load_base` reads a directory `meta-base` as "no base" (`[ -f ]` fails), so `push` PUBLISHES and only then dies `pushed <sha> but could not write meta-base`, and `pull` WRITES local files and then dies `could not write meta-base` — the requirement's "nothing is published" does not hold today. Fix: `pull` and `push` refuse up front, after the lock and before any fetch-driven write or publish, when `<gitdir>/meta-base` exists and is not a regular file — exit 1 with a message containing `meta-base` and `is a directory` (or `not a regular file`), branch tip unchanged, no local managed file written or deleted, the directory left in place (nothing moved into it). `write_base_file`'s own `[ -d "$META_BASE" ]` guard stays as defence in depth. Leg: `push` with a local change and `pull` with a remote change, each against a directory meta-base, assert all of the above. A mutant that removes the NEW up-front check turns the leg red (the push publishes). The PR body states this was a defect fix, not a test-only change.
- [ ] AC-B5 Before writing B legs, re-check coverage: drop any branch an existing leg already pins (the find-failure refusal is leg 29's and is out of scope) and say so in WORKER_RESULT.

### Part C — default branch from the mode line
- [ ] AC-C1 With no `--branch`, `meta-sync.sh` reads the mode via its sibling `bash "$HERE/setup-memory.sh" --root "$ROOT" mode` (the ONE mode-line reader — never parse `.gitignore` itself): `on <Y>` (non-empty Y) ⇒ target branch `Y`; `off` ⇒ `loomwright-meta` (unchanged behaviour for unmigrated repos); `unknown <reason>` ⇒ exit 1 `meta_sync: mode_unknown — <reason>; nothing was changed`. **Any other reader answer** — empty output, a non-zero exit with no line (missing sibling, crash), a multi-line or unrecognised answer — is treated as `unknown` (fail closed, the same posture as `automate-trail.sh`'s `_branch_mode` and `meta-entry`'s `*)` arm).
- [ ] AC-C2 `--branch X` when the mode reads `on Y` with `Y ≠ X` ⇒ exit 1 with a `branch_mismatch` message naming both `X` and `Y`, nothing changed (no fetch result written, no lock left, branch and meta-base untouched); `--branch X` equal to `Y`, or any `--branch X` when the mode is `off`, proceeds as today. `--branch X` under an `unknown` mode (including a failed reader) WITHOUT `--allow-branch-mismatch` ⇒ exit 1 `mode_unknown`, nothing changed. `--branch X --allow-branch-mismatch` proceeds with `X` (also when the mode is `unknown`). `--allow-branch-mismatch` without `--branch` is a usage error (exit 1, nothing changed) — never a silent no-op.
- [ ] AC-C3 The mode check runs for every subcommand (`init`, `pull`, `push`, `status`) after the root is resolved and BEFORE any lock, fetch or write.
- [ ] AC-C4 `status` prints `synced <sha> on <branch>` on the synced path (the other status words unchanged); every consumer of the old `synced <sha>` form in the repo (tests, docs) is updated in the same change — grep the old form repo-wide.
- [ ] AC-C5 Tests: a clone with a throwaway mode line (written via `setup-memory.sh apply --branch-mode <throwaway>` or the exact mode-line shape it writes) pulls and pushes the throwaway branch with no flag (the real `loomwright-meta` ref on the fixture origin is untouched); a mismatched `--branch` is refused; the override works; no mode line ⇒ `loomwright-meta`; a mode line naming `loomwright-meta` with no flag targets `loomwright-meta` and `--branch loomwright-meta` is accepted (the primary's unchanged path — requirement Part C Validation 2); `unknown` ⇒ refused, both with no flag and with a bare `--branch X`; a failed reader (e.g. a mutant/sandbox copy with no sibling `setup-memory.sh`) ⇒ refused `mode_unknown`; `status` names the branch. A mutant that ignores the mode line (default stays the constant) turns the throwaway-clone leg red.
- [ ] AC-C6 Callers stay correct: `automate-helpers.sh meta-entry` and `automate-trail.sh trail-pr` already pass `--branch <the mode's branch>`, so they keep working; `bash loomwright/scripts/test-automate-helpers.sh` and `bash loomwright/scripts/test-automate-trail.sh` stay green.

### Shared
- [ ] AC-S1 The script header (usage + `--branch` default + the new `--allow-branch-mismatch` option + SYMLINKS paragraph + STATUS vocabulary + the EXIT list, which gains `branch_mismatch`, `mode_unknown` and the up-front meta-base-not-a-regular-file refusal; and the stale "Nothing calls this script yet" line, already false — `automate-helpers.sh meta-entry` and `automate-trail.sh trail-pr` call it — is corrected) and `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Metadata branch" (default branch sentence, "Symlinks fail closed" paragraph, the `status` vocabulary and the exit-1 reasons in "Exit codes", and its stale "Nothing calls it yet" claim) state the rules exactly as implemented; the `# Covers` header list at the top of `test-meta-sync.sh` names every new leg and mutation control.
- [ ] AC-S2 `bash scripts/ci-local.sh` green (includes `loomwright/scripts/run-self-tests.sh`, root `scripts/test-*.sh` and `scripts/check-*.sh`); the PR body records the baseline full-loop `<passed>/<total>` and SKIP counts on base and branch, each part's validation labelled by part, every mutant's sed expression and its red output, and the Part C running-system output (below). The PR carries `changelog.d/meta-sync-followups-08-meta-sync-hardening.md` and **NO version bump**: this checkout is a lane of the S3 parallel wave, and `changelog.d/README.md` §"Who runs the bump" says lanes write fragments only — the release lane bumps once per wave. Never run `scripts/bump-version.sh`, never edit `plugin.json` / `marketplace.json` / `CHANGELOG.md`.
- [ ] AC-S3 **Running system (Part C):** in a scratch dir, a bare origin + a clone whose mode line names a throwaway branch (`init` it there); paste `meta-sync.sh status` and `meta-sync.sh push` output (no flags) showing the throwaway branch is the target, plus a `--branch loomwright-meta` refusal. Never against this checkout's real `origin`.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | meta-sync hardening A+B+C, tests + mutants, doc, fragment | ALL | 3 modify, 1 create (fragment) | `unit-testing`, `quality-checklist` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "allow-branch-mismatch"}
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "branch_mismatch"}
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "mode_unknown"}
  - {kind: "symbol", path: "loomwright/scripts/test-meta-sync.sh", name: "changed during the sync"}
  - {kind: "symbol", path: "loomwright/scripts/test-meta-sync.sh", name: "no-write-fetch-head"}
  - {kind: "symbol", path: "loomwright/scripts/test-meta-sync.sh", name: "design.png"}
  - {kind: "symbol", path: "loomwright/scripts/test-meta-sync.sh", name: "branch_mismatch"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "allow-branch-mismatch"}
  - {kind: "symbol", path: "changelog.d/meta-sync-followups-08-meta-sync-hardening.md", name: "meta-sync — symlinked non-managed files sync, hardening branches pinned, default branch from the mode line"}
requires: []
lanes:
  - "loomwright/scripts/meta-sync.sh"
  - "loomwright/scripts/test-meta-sync.sh"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/meta-sync-followups-08-meta-sync-hardening.md"
external_requires:
  - "git rejecting an unknown fetch option with exit 129 (emulated by a PATH shim)"
```

**Exact-name mandate:** the new option is spelled `--allow-branch-mismatch`; the refusals carry the literal tokens `branch_mismatch` and `mode_unknown`; the AC-B2 assertion matches the literal `changed during the sync`; the AC-B1 shim matches the literal `--no-write-fetch-head`. The fragment `changelog.d/meta-sync-followups-08-meta-sync-hardening.md` stays in the PR (no lane bump — the wave's release lane folds it); its headline line MUST be exactly `meta-sync — symlinked non-managed files sync, hardening branches pinned, default branch from the mode line` (em dash), so the later fold is verifiable.

## Parallelism Analysis

### Dependency Graph
Single subtask — no graph.

### File Overlap Matrix
Not applicable (one subtask).

### Batch Plan
One batch, one worker.

## Implementation Notes (for the worker)
- **Harness:** reuse `mkworld`, `clone`, `synced_pair`, `ms`, `put`, `br_tip`, `br_has`, `br_names`, `base_of`, `check`, `mkshim` (leg 22), leg 27's holder-log technique, and `build_mutant`. New legs go before the `# Mutation controls` divider, new mutation controls after control 37; number them from 38 upward in order. `build_mutant` already copies the sibling `setup-memory.sh` beside each mutant — Part C needs that copy to exist (the mutant calls `$HERE/setup-memory.sh`).
- **Fixtures have no mode line today** (`mkworld` writes `.supervisor/` only into `.gitignore`), so `setup-memory.sh mode` reads `off` there and every existing leg keeps targeting `loomwright-meta`. Confirm this before relying on it (`bash loomwright/scripts/setup-memory.sh --root <clone> mode`). For the Part C legs, produce the mode line with `setup-memory.sh --root <clone> apply --branch-mode <throwaway>` if that works hermetically under the sandboxed HOME; otherwise write the managed block by copying the exact shape `apply` writes (read `setup-memory.sh` for it — do not invent it).
- **Part C order:** resolve the mode right after `ROOT`/`GITDIR` are resolved and before `META_BASE`/`LOCK_DIR` are used — i.e. before `acquire_lock`, `fetch_remote`, `cmd_init`. Keep the existing `git check-ref-format "refs/heads/$BRANCH"` check AFTER the final branch is chosen, so a mode-line branch is validated too. Track whether `--branch` was given with a flag variable (do not compare against the constant — `--branch loomwright-meta` in a lane must still be refused).
- **Part B shims:** match the git verb by scanning all args (the SUT calls `git -C <root> <verb> …` through `g()`, so the verb is not `$1`); resolve the real git path BEFORE prepending the shim dir to PATH; scope PATH changes to the one SUT call. For AC-B2 the window is narrow (Plan Review finding): appending BEFORE the planning `hash-object` changes the planned L (no mismatch), and appending on `union_into`'s own `hash-object` is too late (it re-hashes the copy already taken). Append AFTER the real git returns on the planning `hash-object` of the ledger (key on a marker so it fires once), or on `union_into`'s `cat-file blob "$r"`. Prove the window with the mutant: without the re-check the leg must go red.
- **Mutants:** gate each through `build_mutant` (non-empty, differs, expected text present, `bash -n`); a sed delimiter must not collide with the target line (lesson fa32a308); an unbuildable mutant is an inconclusive FAIL, never a pass. A red-by-crash is inconclusive, not proof.
- **If a leg exposes a real defect** in `meta-sync.sh`, fix it minimally and report it in WORKER_RESULT. Two are already known (AC-B2 partial write before a union refusal; AC-B4 directory meta-base publishing before it fails); otherwise Part B changes nothing in `meta-sync.sh`.
- **Bash 3.2 / BSD:** no `declare -A`, no `timeout`, no GNU-only flags. Validate with `bash loomwright/scripts/test-meta-sync.sh`.
- **No requirement file is committed** (branch mode).
- **No bump (parallel-wave lane):** commit code + tests + doc + fragment; do NOT run `scripts/bump-version.sh` (`changelog.d/README.md` §"Who runs the bump": lanes write fragments only).

## Skill References

| Skill | Why |
|---|---|
| `skills/unit-testing/SKILL.md` | One observable per assertion; exact output in each check message |
| `skills/quality-checklist/SKILL.md` | Pre/post-implementation gates |

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift. (Applies here: the script header ↔ ARCHITECTURE_CONTRACTS §"Metadata branch" ↔ the test's `# Covers` list.)

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Part C breaks the engine's own calls (`meta-entry`, `trail-pr`) or other suites that run `meta-sync.sh` against fixtures carrying a mode line | HIGH | Both callers pass `--branch` = the mode's branch (equal ⇒ allowed); run `test-automate-helpers.sh` + `test-automate-trail.sh` + the full `ci-local.sh` loop (AC-C6, AC-S2) |
| An `unknown` mode silently falls back to the constant — the exact trap Part C exists to close | HIGH | AC-C1 makes `unknown` a refusal; a test pins it |
| A mutation control that silently no-ops reads as a pass | MEDIUM | `build_mutant` gating; inconclusive ⇒ FAIL (lesson fa32a308) |
| The AC-B2 hook fires at the wrong moment (before planning, or after the write), so the leg passes for the wrong reason | MEDIUM | Assert the injected line is present in the local ledger after the run AND that `meta-base` is unchanged; the mutant without the re-check must turn it red |
| Running-system check pushes to the real metadata branch | MEDIUM | AC-S3: scratch bare origin only; never this checkout's `origin` |
| The `synced <sha>` → `synced <sha> on <branch>` change leaves a stale consumer | LOW | AC-C4: grep the old form repo-wide (lesson 0d7865dc) |
| A lane bump would conflict with sibling S3 lanes and double-bump on the wave branch (Plan Review attempt 1) | MEDIUM | Fragment only; no edit of the three version files (AC-S2) |
| The AC-B2 partial-write fix reorders pull's writes and weakens a containment re-check | MEDIUM | Keep the pre-pass + per-path re-checks; the full `test-meta-sync.sh` suite (legs 24/26/28/29) must stay green |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-10-05-meta-sync-hardening.md

## Plan Review: PASS (attempt 2/3)

## Outcome
- **Status:** completed
- **Completed:** 2026-10-05T17:15:24Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/394
- **Branch:** feature/meta-sync-followups-08-meta-sync-hardening
- **Files changed:** 4
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** meta-sync Part A (symlinked non-managed files sync), Part B (four hardening branches pinned by legs 39–42 with mutants; two defects fixed: union-before-TAKE_R, up-front non-regular meta-base refusal), Part C (default branch from the mode line; branch_mismatch / mode_unknown / --allow-branch-mismatch; status names the branch). Resumed after a parent-session crash; FINALIZE children-check unsettled (dead worker a2da246) — owner chose proceed after independent re-verification (ci-local PASS 143/143). Phase 4.5 consistency_audit PASS on iteration 1; 1 pre_existing HIGH + 2 LOW dismissed. Ground truth 2/2; risk high (size 705 > 400).

## Not verified
- **automate-loop SKILL.md / commands/setup.md prose** — still says meta-sync's default is loomwright-meta (true when the mode is off); out of lane, so not edited (subtask 1)
- **real GitHub origin** — every running-system check used a scratch bare origin (subtask 1)
