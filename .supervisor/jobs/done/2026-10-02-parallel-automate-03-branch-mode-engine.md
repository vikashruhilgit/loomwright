# Supervisor Job: Branch mode in the /automate engine — code only, default OFF (parallel-automate/03)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean except this run's automate run file (modified), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (sessions run the INSTALLED plugin — 15.117.2 here, equal to repo `main` today — so nothing this PR adds runs in a live `/automate` until it is merged AND the plugin is reinstalled; that is exactly why M1 is a separate operator item)
- **Source requirement:** .supervisor/requirements/parallel-automate/03-branch-mode-engine.md
- **Base commit:** d887ae2db8946e236b23c353011c22ed25791508

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe scripts beside the other `loomwright/scripts/*.sh`; markdown skill/command/doc edits. Same stack. |
| 2 | Dependency Availability | GO | `loomwright/scripts/meta-sync.sh` (item 02, merged in #334 at 7808a00) provides `init`/`pull`/`push --paths-from`/`status`; `git`, `jq`, `gh` present. |
| 3 | Architecture Fit | GO | Every change is a flag-gated branch: mode OFF (the default, and this repo's state until M1) takes today's code path byte-unchanged. The mode switch lives in the managed `.gitignore` block that `setup-memory.sh` already owns. |
| 4 | Scope vs Supervisor Capability | CAUTION | ~20 files across 5 scripts + their tests + 3 fixture corpora + 6 doc surfaces. One subtask (Single-Agent Path — `/autonomous` does not forward `--sequential`, so it is the only path that works under `/automate`); both prior items' workers hit the 40-turn limit and were resumed via SendMessage. A fixed, commit-per-step order is mandatory. |
| 5 | Hard Blockers | CAUTION | **Stale premise in the requirement (Scope 4):** `meta-sync.sh status` is NOT offline — `cmd_status` calls `fetch_remote`, which runs `git ls-remote` and `git fetch` (see `remote_probe` / `fetch_remote`). SessionStart must therefore NOT call `status`; AC5 below replaces it with an offline existence check of the documented `<gitdir>/meta-base` file (`ARCHITECTURE_CONTRACTS.md` §"Metadata branch", "3-way rule" paragraph). |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add an opt-in **branch mode** to the `/automate` engine: a repo that turns it on (via `/setup memory`) keeps its run history on the metadata branch that `meta-sync.sh` syncs — pulled before the engine first reads run history, pushed (evidence-gated, loudly on failure) where the trail PR is opened today — while a repo that has not opted in (the default, and this repo until operator item M1) behaves byte-for-byte as before. No tracked run-history file and no `.gitignore` line of this repo changes in this PR.

**Problem Statement:**
With item 02's `meta-sync.sh` merged, the engine still commits run history to `main` through a trail PR, so nothing can yet take run history off `main`. Two measured dangers shape the switch:
- **Silent amnesia.** With run history absent every reader exits 0 with EMPTY output: `resume-glob` returning nothing means `/automate` would not see a paused run with an open PR and would start a new one. So the pull must happen before the first read, and a failed pull must stop the engine, never fall through to an empty read.
- **The migration cannot ride this PR.** Sessions run the INSTALLED plugin. If this PR also untracked the files, the old engine's `trail-pr` — which drops every candidate `git check-ignore` reports ignored (`_trail_candidates`, "Drop gitignored candidates") — would close out this very item by committing nothing anywhere. So this PR is code only; M1 migrates the repo.
Success looks like: one tracked mode switch, one reader, a pull-first entry check that aborts or parks loudly, a push that keeps the trail PR's evidence gate, push failures that are impossible to miss, and CI coverage that no longer silently depends on the tracked corpus.

## Acceptance Criteria
- [ ] AC1 (mode switch, `setup-memory.sh`): Given `setup-memory.sh apply --branch-mode <branch>` (the branch value is required — a bare `--branch-mode` is a usage error, nothing written; the name is validated with `git check-ref-format --branch`; `meta-sync.sh`'s own default is `loomwright-meta`, which `/setup memory` offers as the suggested value), when it writes the managed block, then the block (a) OMITS every run-history re-include line — `!.supervisor/requirements/`, the `!.supervisor/jobs/` + `.supervisor/jobs/*` + `!.supervisor/jobs/done/` + `!.supervisor/jobs/failed/` group, the `!.supervisor/automate/` + `.supervisor/automate/*` + `!.supervisor/automate/*.md` group, and the three ledger lines — while KEEPING `.claude/*`, `!.claude/agent-memory/`, `.supervisor/*`, `!.supervisor/memory/` and the nested `*/**/.supervisor/` exclude; and (b) records the mode as ONE comment line inside the sentinels, exact shape `# loomwright-meta-branch: <branch>` (tracked, so a fresh clone can read it). `apply --branch-mode off` writes today's block (no mode line). A plain `apply` (no `--branch-mode`) PRESERVES the mode line already in the block — without this, today's `apply` would silently rewrite the block and re-include run history. `remove` deletes the whole block as today (mode included). With mode OFF, `apply` writes a block byte-identical to today's (`proposed_applied_content` unchanged for every off-mode input). The header invariant stays true and is restated for the new flag: the script never runs `git add` / `git rm` / `git commit`; switching mode only rewrites `.gitignore` — untracking the existing run history is operator item M1, never a sub-step of this script. All new paths keep the FAIL-SAFE CONTRACT (exit 0, status lines carry the outcome).
- [ ] AC2 (one reader, owner decision 2026-10-02): Given `setup-memory.sh mode [--root <checkout>]`, when run, then it prints exactly ONE line and exits 0: `off` (no managed block, or a block without a mode line), `on <branch>` (the block's mode line), or `unknown <reason>` (the block fails `gitignore_gate`'s sentinel sanity check, more than one mode line, or a mode line whose branch fails `git check-ref-format --branch`). Every caller below uses this reader; nothing else parses the block. `meta-sync.sh` is NOT edited (owner decision — the reader sits with the block's only writer).
- [ ] AC3 (pull BEFORE the first read, `automate-helpers.sh meta-entry`): Given a new subcommand `automate-helpers.sh meta-entry [--branch-from-mode]` (exact argument shape the worker's choice; it must take no input that lets a caller assert the mode), when run, then it reads `setup-memory.sh mode` itself and prints ONE verdict line, always exit 0: `meta-entry: off` (mode off — proceed exactly as today, no network); `meta-entry: pulled <branch>` (mode on, `meta-sync.sh pull --branch <branch>` exited 0); `meta-entry: failed — <reason>` (mode on and pull exited non-zero — the reason carries meta-sync's own `no_remote_branch` / `conflict <path>` / fetch-failure text, naming the path on a conflict); `meta-entry: failed — mode unknown (<reason>)` (reader said `unknown`). It creates and writes NOTHING under `.supervisor/automate/` itself. The SKILL prose (AC8) makes it the FIRST action of every `/automate` entry — before `resume-glob`, before any run file is created, before the PICK run-lock acquire — and maps `failed` to: **no run file targeted** (new run, or bare `/automate` / `--resume` with no matching local run file) ⇒ ABORT with the message, create nothing (parking would create a run file that makes the next resume ambiguous); **an existing local run file targeted by `--resume <id>`** ⇒ park it, new `pause_reason: meta_unreachable`, one `## Progress` line naming the reason (a conflict names the path).
- [ ] AC4 (`pause_reason: meta_unreachable`): Given `docs/RESULT_SCHEMAS.md` §"AUTOMATE_RUN" and `skills/automate-loop/SKILL.md` (the §3 template's `pause_reason` list and the §3 `## Status` semantics list), when this lands, then `meta_unreachable` is added to every enumeration of `pause_reason` values in BOTH surfaces in the same commit (house rule: a restated list moves with its authority), with a one-line meaning (`meta-entry` failed on a resume of an existing run). It is a RUN-level park with no item-level `status` counterpart (like `limit_reached` / `resume_ambiguous`).
- [ ] AC5 (SessionStart: no network, `session-resume.sh`): Given a session start with `setup-memory.sh mode` printing `on <branch>`, when `session-resume.sh` runs, then it makes NO network call and does NOT call `meta-sync.sh status` (stale premise — `status` runs `git ls-remote` + `git fetch`, Feasibility #5); instead it checks, offline, whether the documented merge-base file `<gitdir>/meta-base` exists (`<gitdir>` = `git rev-parse --git-dir` of the root `meta-sync.sh` resolves — the FIRST `git worktree list --porcelain` entry), and when it does NOT, appends exactly one line to its existing output: ``run history is on branch `<branch>` and has not been pulled — run `meta-sync.sh pull` `` (the worker may add the runtime path prefix the other hints in that file use). Mode `off` / `unknown`, or `meta-base` present ⇒ no line, output byte-identical to today. Always exit 0. The PR body names this as a deliberate deviation from Scope 4's "runs `meta-sync.sh status`".
- [ ] AC6 (push replaces the trail PR — keeping its filters, `automate-trail.sh`): Given `trail-pr` with `setup-memory.sh mode` = `on <branch>`, when any of its three triggers fires (inside `closeout` after merge evidence; a skipped/abandoned check-off; run end), then it opens NO PR and creates no trail worktree; it builds the push list from `_trail_candidates` + `_evidence_gate` exactly as today EXCEPT that the `git check-ignore` drop is skipped on the mode-on path (after M1 every run-history path IS gitignored, so keeping the drop would push nothing) — candidates outside `meta-sync.sh`'s managed set are simply ignored by meta-sync; done claims ride only for MERGED work; a path the evidence gate excludes is NOT in the list and is named (`; excluded <path> — pr not merged`, same text as today). **Ledger rule (owner decision 2026-10-02):** `.supervisor/postmortem/results.jsonl` is listed as a whole file — meta-sync's line-union and its scrub rule (a) (foreign `.repo` ⇒ exit 2) apply; the PR body names this as a deliberate deviation from Scope 5's "only this run's ledger lines". **Dropped drafts become real deletions:** this run's dismissed drafts that are ABSENT on disk and whose `<run_id>.dismissed-decisions` last row reads `drop`, `fix-now` or `moved` are ADDED to the push list, so meta-sync's `L absent, R == B` rule deletes them on the branch (the mode-on counterpart of today's dropped-draft retraction). It then runs `meta-sync.sh push --branch <branch> --paths-from <list> --message "chore(supervisor): <run_id> trail (<reason>)"` and prints ONE line: `trail-pr: meta-pushed <branch>` / `trail-pr: skipped — meta no_changes` / `trail-pr: meta-push FAILED — <reason>`, with any `; excluded …` appended. `trail-unstage` on the mode-on path prints `trail-unstage: skipped — branch mode` and touches no index entry; `closeout`'s sync skips the `.trail-staged` re-stage on the mode-on path; no `.trail-staged` record is written. Mode OFF ⇒ every legacy line of `trail-pr` / `trail-unstage` / `closeout` is byte-unchanged in behaviour (proved by AC10's unedited legacy assertions). `trail-pr` stays advisory: always exit 0, never `run-lock.sh`, never a merge, never a force push.
- [ ] AC7 (push failures are loud): Given a mode-on `trail-pr` whose `meta-sync.sh push` exits non-zero (1 = conflict / no_remote_branch / fetch failure / exhausted retries / tree_guard / locked; 2 = scrub hit) or whose mode reads `unknown`, when it returns, then it (a) appends ONE `## Progress` line `meta-push FAILED: <reason>` to the run file itself (via `automate-helpers.sh progress-append`, so it is recorded even when the caller is `closeout` or the merge watcher, which do not append trail lines); (b) fires the notify through the existing fail-safe `notify-desktop.sh` + `send-webhook.sh` pair; (c) writes the gitignored marker `.supervisor/automate/<run_id>.meta-push-failed` (one line: UTC timestamp + reason; NOT `*.md`, so `resume-glob` never lists it and meta-sync never manages it) — removed by the next SUCCESSFUL mode-on push (`meta-pushed` or `no_changes`). A new read-only `automate-helpers.sh meta-push-failed <runfile>` prints the marker's line or nothing, always exit 0; the SKILL's PICK step (AC8) reports a non-empty answer to the owner and appends it to `## Progress` BEFORE picking (report, not block — item 05's `lane-remove` is the future consumer that refuses on it). A scrub hit's output names every offending path (meta-sync already prints one `meta_sync: scrub <path>: <rule>` line per hit); `trail-pr` carries the first line into its reason and the full list into the marker.
- [ ] AC8 (docs): Given the docs, when this lands, then `skills/automate-loop/SKILL.md` gains ONE new flag-gated section `## §13 — Branch mode (opt-in, default OFF)` (or the next free § number; wording is the worker's) holding the whole contract: the mode switch + reader, `meta-entry` first at entry and its abort-vs-park mapping, the mode-on `trail-pr` push list and ledger rule, the dropped-draft deletion, the loud-failure marker and its PICK report, the no-network SessionStart line, and the honest limits (AC12). §4 ("On every start") and §6 ("Trail PR after merge and at run end") each get exactly ONE pointer line to it; every other existing section is untouched apart from AC4's enumeration additions. `skills/SKILLS_INDEX.md` gets the version/date bump that a SKILL.md edit forces, in the same commit. `commands/automate.md` gets a one-line mention under its overview pointing at the new section; `commands/setup.md` §"Module: memory" documents `--branch-mode <branch>` / `--branch-mode off` / plain-apply preservation / `setup-memory.sh mode`, and states that switching does NOT untrack existing files (M1). `docs/ARCHITECTURE_CONTRACTS.md` §"Metadata branch" gets a short "Engine integration (branch mode)" paragraph pointing at the SKILL section; `docs/PITFALLS.md` gets one entry: "a repo in branch mode whose metadata branch was never pulled reads as having no run history — `meta-entry` exists so this fails loudly; never bypass it". `skills/setup/SKILL.md` is edited ONLY if it restates the memory module's subcommand list (house rule — then it moves in the same commit). Vendor coupling: `loomwright/skills/automate-loop/SKILL.md` has allowance 5 and `loomwright/scripts/automate-helpers.sh` / `loomwright/scripts/test-automate-helpers.sh` have 2 each in `loomwright/docs/vendor-coupling-manifest.json`; new prose describes the plugin-root variable rather than spelling it unless an invocation genuinely needs it, and any raise is measured with `scripts/check-vendor-coupling.sh --print-allowances` and named in the PR body.
- [ ] AC9 (CI coverage must not evaporate): Given the tests that read the tracked corpus and SKIP silently without it — `loomwright/scripts/test-context-digest.sh` (the "no archived brief corpus under .supervisor/jobs/" SKIP and the "octal-value check needs the gitignored corpus brief" SKIP) and `loomwright/scripts/test-harvest-conventions.sh` (its `.claude/agent-memory` + ledger-gated block) — when this lands, then each reads a FROZEN fixture corpus under `loomwright/scripts/fixtures/` (new subfolders; real briefs/ledger lines copied and scrubbed of home paths and foreign slugs, small enough to review) when the live corpus is absent, so the gate still RUNS; and `loomwright/scripts/test-automate-dismissed.sh`'s byte-compare of the proposed/ README template compares against a fixture copy under `loomwright/scripts/fixtures/`, not the live `.supervisor/requirements/proposed/README.md`. Record the `SKIP` line count of the full loop before and after (AC10's baseline); after ≤ before. The fixtures carry no absolute home path, e-mail or non-allowlisted forge slug (the worker runs `meta-sync.sh`'s scrub patterns over them, or an equivalent grep, and pastes the clean result).
- [ ] AC10 (tests): Given the suites, when run under `/bin/bash` 3.2 (macOS), then: **mode OFF** — `test-automate-trail.sh`, `test-automate-helpers.sh` and `test-setup-memory.sh` pass with ZERO edits to their existing (legacy-path) assertions (new cases are appended, never edits to old ones — the PR body pastes `git diff origin/main -- <suite>` showing only additions); `setup-memory.sh apply` with mode off writes a block byte-identical to today's (`cmp` against the base commit's output). **Mode ON** (hermetic: `hermetic-test-env.sh` sourced first; a `mktemp -d` work dir with a LOCAL bare remote, never GitHub; `gh` stubbed by a recorder that FAILS the test if `pr create` is ever invoked): unreachable remote + no run file ⇒ `meta-entry` prints `failed`, and `ls .supervisor/automate` is unchanged; a paused run file present only on the metadata branch ⇒ after `meta-entry` (`pulled`), `resume-glob` lists it; `closeout` on a merged item opens NO PR, the branch then holds the closed-out item's stamp and the run file, and a dropped draft is gone from the branch (`git ls-tree -r` on the branch); an UNMERGED item's done stamp is NOT on the branch (`; excluded … — pr not merged` printed); a push that meta-sync refuses (e.g. a scrub hit seeded into a candidate) ⇒ exit 0 from trail-pr, the `meta-push FAILED:` line in `## Progress`, the marker present, `meta-push-failed` prints it, and the next successful push removes it; `trail-unstage` mode on ⇒ `skipped — branch mode`, index untouched; `setup-memory.sh`: `apply --branch-mode X` writes the expected block + mode line, a following plain `apply` preserves it (byte-identical), `apply --branch-mode off` restores today's block, `remove` removes it, `mode` prints `off` / `on X` / `unknown …` for the three shapes, an invalid branch name is refused with nothing written; `session-resume.sh` (in `test-session-resume.sh`): mode on + no `meta-base` ⇒ exactly one hint line and NO network (assert by pointing `origin` at an unreachable URL and asserting no fetch happened / the run finishes without it), `meta-base` present ⇒ no line, mode off ⇒ output byte-identical. **Mutation controls (run inside the tests as self-checks, each shown turning red):** (i) a `meta-sync.sh pull` stand-in that exits 0 on fetch failure (test seam: an env var read ONLY by the tests, naming the meta-sync script `meta-entry` invokes — stated in the helper header and PR body) MUST fail the "abort, nothing created" assertion; (ii) a variant that bypasses `_evidence_gate` on the mode-on push list (same kind of test-only seam, or a patched copy of the script in the work dir) MUST fail the "unmerged stamp not on the branch" assertion.
- [ ] AC11 (unchanged repo state): Given the finished branch, when checked, then `git diff --stat origin/main` shows NO change to `.gitignore` and none under `.supervisor/` except this requirement's own stamp; `setup-memory.sh mode` run on this repo prints `off`; no `--branch-mode` apply is ever run against this repo (fixtures and scratch clones only).
- [ ] AC12 (honest limits, stated in the SKILL section and the PR body): a manual whole-set `meta-sync.sh push` bypasses the evidence gate (only `trail-pr` applies it); a done claim already on the branch for work later reverted is the branch's content (no retroactive retraction on the mode-on path — `reconcile-status` is the tool); `meta-entry`'s pull needs the network, so an offline machine in branch mode cannot start or resume a run (deliberate — the alternative is silent amnesia); the SessionStart hint reads only `meta-base` presence, so a stale-but-synced clone gets no hint (the entry pull covers it).
- [ ] AC13 (bump, P7): Given this PR, when it is finalized, then its LAST commit is the output of `bash scripts/bump-version.sh` run with this item's own fragment `changelog.d/parallel-automate-03-branch-mode-engine.md` (first line `<!-- bump: minor -->`), so the PR carries the new version in all three version files and no fragment remains. Never hard-code a target version.

## Validation (must pass before merge — evidence goes in the PR body)
1. **Baseline:** the full pre-push gate `bash scripts/ci-local.sh` (CLAUDE.md §"Pre-push test run?" — never a hand-rolled serial `test-*.sh` loop) on the untouched base commit AND on the finished branch; record `<passed>/<total>` and the count of `SKIP` lines for both (the AC9 before/after).
2. **Unchanged path (mode OFF):** AC10's mode-off results, the `git diff origin/main -- loomwright/scripts/test-automate-trail.sh loomwright/scripts/test-automate-helpers.sh loomwright/scripts/test-setup-memory.sh` showing additions only, the `cmp` of the off-mode block against the base commit's, and AC11's `git diff --stat origin/main` + `setup-memory.sh mode` output on this repo. Note for after merge + reinstall (not in this PR): one real single-item `/automate` on this repo must still open its trail PR exactly as before.
3. **Running system (mode ON, scratch clone + local bare remote, never GitHub):** in a scratch clone of THIS repo with a local bare `origin`: `meta-sync.sh init`, `setup-memory.sh apply --branch-mode loomwright-meta` in the scratch clone, then paste (a) the abort on an unreachable remote with `ls .supervisor/automate` unchanged before/after; (b) `resume-glob` listing a paused run after `meta-entry`'s pull; (c) the branch contents (`git ls-tree -r --name-only loomwright-meta`) after a closeout with a stubbed `gh` that reports the PR merged — and the recorder showing no `pr create`. Because this repo's real run history hits meta-sync's scrub (item 02 found home paths in several tracked files — M1's job to clean), build the scratch run history from the hermetic fixtures, not the live corpus, or paste the exit-2 scrub output first and exclude those paths, naming them.
4. **A failure this must catch:** AC10's two mutation controls, shown failing.
5. **Rollback:** `git revert`. No repo is in branch mode yet, so nothing is stranded.
6. **Premise re-check (before designing):** re-confirm the requirement's "Verified premises" on the base commit and paste: `_trail_candidates`'s `git check-ignore` drop; the three `trail-pr` triggers in SKILL §6; `setup-memory.sh`'s header invariant ("NEVER runs `git add`, `git rm`, `git commit`"); and the stale one — `meta-sync.sh status` calling `fetch_remote` (Feasibility #5).

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Branch mode: setup-memory switch + reader, meta-entry, mode-on trail push + loud failures, offline SessionStart hint, corpus fixtures, docs, this PR's own bump | all | 21 modify (loomwright/scripts/setup-memory.sh, loomwright/scripts/test-setup-memory.sh, loomwright/scripts/automate-trail.sh, loomwright/scripts/test-automate-trail.sh, loomwright/scripts/automate-helpers.sh, loomwright/scripts/test-automate-helpers.sh, loomwright/scripts/session-resume.sh, loomwright/scripts/test-session-resume.sh, loomwright/scripts/test-context-digest.sh, loomwright/scripts/test-harvest-conventions.sh, loomwright/scripts/test-automate-dismissed.sh, loomwright/skills/automate-loop/SKILL.md, loomwright/skills/SKILLS_INDEX.md, loomwright/commands/automate.md, loomwright/commands/setup.md, loomwright/docs/RESULT_SCHEMAS.md, loomwright/docs/ARCHITECTURE_CONTRACTS.md, loomwright/docs/PITFALLS.md, CHANGELOG.md, .claude-plugin/marketplace.json, loomwright/.claude-plugin/plugin.json; conditional: loomwright/skills/setup/SKILL.md, loomwright/docs/vendor-coupling-manifest.json), create fixture files under loomwright/scripts/fixtures/ + 1 fragment created then folded | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md`, `skills/commit/SKILL.md` | LAUNCHABLE |

**Fixed in-subtask order (commit after each step, so a turn-limit stop resumes from a clean committed point):** (a) Validation 6 premise re-check + Validation 1 baseline on the base commit (not committed); (b) `setup-memory.sh` mode switch + `mode` reader + appended `test-setup-memory.sh` cases (AC1, AC2); (c) `automate-helpers.sh meta-entry` + `meta-push-failed` + appended `test-automate-helpers.sh` cases incl. mutation control (i) (AC3, AC7 reader); (d) `automate-trail.sh` mode-on push path + loud failure + appended `test-automate-trail.sh` cases incl. mutation control (ii) (AC6, AC7); (e) `session-resume.sh` offline hint + `test-session-resume.sh` cases (AC5); (f) corpus fixtures + the three test rewires, SKIP count recorded (AC9); (g) docs — SKILL §"Branch mode" + pointers + `SKILLS_INDEX.md`, RESULT_SCHEMAS `meta_unreachable`, `commands/automate.md`, `commands/setup.md`, ARCHITECTURE_CONTRACTS paragraph, PITFALLS entry (AC4, AC8, AC12); full `bash scripts/ci-local.sh` green; (h) Validation 3 running-system check in scratch clones, output kept for the PR body; (i) write `changelog.d/parallel-automate-03-branch-mode-engine.md` with `<!-- bump: minor -->`; (j) `bash scripts/bump-version.sh` — its result is the PR's LAST commit.

### Subtask Contracts

```yaml
# Subtask 1 — whole item, single-agent (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "loomwright-meta-branch"}
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "--branch-mode"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "meta-entry"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "meta-push-failed"}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.sh", name: "meta-pushed"}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.sh", name: "meta-push FAILED"}
  - {kind: "symbol", path: "loomwright/scripts/session-resume.sh", name: "meta-base"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "meta_unreachable"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "Branch mode"}
requires: []
lanes:
  - "loomwright/scripts/setup-memory.sh"
  - "loomwright/scripts/test-setup-memory.sh"
  - "loomwright/scripts/automate-trail.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/session-resume.sh"
  - "loomwright/scripts/test-session-resume.sh"
  - "loomwright/scripts/test-context-digest.sh"
  - "loomwright/scripts/test-harvest-conventions.sh"
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "loomwright/scripts/fixtures/**"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/skills/setup/SKILL.md"
  - "loomwright/commands/automate.md"
  - "loomwright/commands/setup.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/PITFALLS.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "changelog.d/*.md"
  - "CHANGELOG.md"
  - ".claude-plugin/marketplace.json"
  - "loomwright/.claude-plugin/plugin.json"
external_requires:
  - "loomwright/scripts/meta-sync.sh (item 02, merged #334) — init / pull / push --paths-from / status, exit codes 0/1/2; NOT edited"
  - "git (incl. check-ref-format, ls-tree, a local bare remote for tests), jq, bash 3.2 (macOS) and GNU bash (CI)"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md`, `skills/commit/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Stale premise: requirement Scope 4 has SessionStart run `meta-sync.sh status`, but `status` performs `git ls-remote` + `git fetch` (Feasibility (Phase 2.5) #5) | HIGH | AC5 replaces it with an offline `<gitdir>/meta-base` existence check (a documented contract in `ARCHITECTURE_CONTRACTS.md` §"Metadata branch"); AC10 asserts no fetch happens; the PR body names the deviation. |
| A mode-on change leaks into the mode-off path (this repo stays mode-off until M1; a regression would break every live `/automate` trail after reinstall) | HIGH | Every new branch keys on `setup-memory.sh mode`; AC10 requires the three legacy suites to pass with zero edits to existing assertions and the off-mode block byte-identical (`cmp`); Validation 2 pastes the additions-only diffs. |
| Keeping `_trail_candidates`' `git check-ignore` drop on the mode-on path would push NOTHING after M1 (every run-history path becomes ignored) — the same silent-nothing failure that forced the M1 split | HIGH | AC6 skips the drop on the mode-on path only; AC10's mode-on closeout test runs with run history gitignored in the scratch clone so a kept drop turns it red. |
| Silent amnesia: a failed pull falling through to an empty `resume-glob` starts a second run beside a paused one with an open PR | HIGH | `meta-entry` is the first entry action and fails loudly; abort when no run file is targeted (create nothing), park `meta_unreachable` on a resume; mutation control (i) proves the abort test catches a pull that lies. |
| A done claim for unmerged work reaching the metadata branch (trail-pr's evidence gate is the only filter on the mode-on path) | HIGH | AC6 keeps `_evidence_gate`; mutation control (ii) proves the "unmerged stamp not on the branch" test catches a bypass; AC12 states the manual-push limit. |
| Ledger whole-file push carries other runs' lines and could carry a foreign repo's record (owner decision: whole-file union) | MEDIUM | meta-sync scrub rule (a) fails the push CLOSED (exit 2) on any non-allowlisted `.repo` → AC7's loud path; PR body names the deviation from Scope 5. |
| Prior churn (postmortem ledger): `automate-helpers.sh` (9), `automate-loop/SKILL.md` (9), `session-resume.sh` (4), `setup-memory.sh` (2), `automate-trail.sh` (1) — recurring `drain_churn` / `self_heal_churn`, `self_heal_miss` recurred | HIGH | Self-heal misses recurred on these exact files: prompt is program — state-trace every new SKILL prose branch (entry abort vs park, PICK report) against the helper's real output lines; reviewers check each new `## Progress` line and pause_reason against RESULT_SCHEMAS. Source: Prior churn (postmortem ledger). |
| Scope size in one worker context (Feasibility (Phase 2.5) #4) | MEDIUM | Fixed commit-per-step order; resume the worker via SendMessage on a turn-limit stop, never respawn. |
| Fixture corpora copied from the live corpus carry home paths / foreign slugs into tracked test files | MEDIUM | AC9 requires scrubbed fixtures and a pasted clean scan. |
| `pause_reason` enumeration drift (RESULT_SCHEMAS and SKILL both restate the list) | MEDIUM | AC4: both in the same commit; `check-doc-currency.sh` + reviewer grep for every `run_lock_held` occurrence to find each copy. |
| `setup-memory.sh` plain `apply` today REWRITES the block — without preservation it silently re-includes run history in a branch-mode repo | MEDIUM | AC1 preservation + AC10 byte-identical second apply. |
| bash 3.2 / BSD userland (`sed -i`, `stat`, `find -printf`, empty arrays under `set -u`, `timeout`) | MEDIUM | None of those; temp file + `mv`; run every suite under `/bin/bash` on macOS. |
| Vendor-coupling ratchet on SKILL.md (allowance 5) and automate-helpers.sh (2) | LOW | Describe the plugin-root variable in prose; measure any raise with `--print-allowances` and name it in the PR body (AC8). |
| The bump version depends on `main` at bump time | LOW | The bump is the LAST commit; if `main` moves before merge, drop the bump commit (restores the fragment), rebase, re-run `bash scripts/bump-version.sh`. |
| `ci.yml` wiring: `loomwright/scripts/test-*.sh` is auto-globbed | LOW | No workflow edit (a workflow edit would also make `claude-code-action` skip its review). |

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- Wording that carries a contract — a heading a gate greps for, a sentence that states a guarantee — is treated as an interface: renaming it is a change to that interface and its consumers move with it.
  - id: documentation-wording-that-carries-a-contract-a-heading-a-gate-greps-for-a-sentence-that-states-a-guarantee-is-treated-as-an-interface-renaming-it-is-a-change-to-that-interface-and-its-consumers-move-with-it
  - enforcement: advisory
  - category: documentation
  - check (data only, NOT executed by this reader): (none)
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

## Worker Advisories (Plan Review attempt 1/3 PASS — 6 LOW, carried by owner decision 2026-10-02)
- **A1 (AC4):** `meta_unreachable` must also join SKILL §6 "Trail PR after merge and at run end"'s "No park calls it:" list (beside `run_lock_held` / `resume_ambiguous` — `meta-entry` runs before the PICK lock acquire, so it never held the lock); `test-automate-trail.sh` loops over that list. RESULT_SCHEMAS.md §AUTOMATE_RUN carries three copies (template line, Status table, `pause_reason` row). Grep every `run_lock_held` occurrence and update each copy.
- **A2 (AC12):** add the honest limit — `meta-sync.sh push` plans over the WHOLE managed set even under `--paths-from`, so a conflict on ANY managed path (not this run's) blocks this run's trail push until a human resolves it (AC7 makes it loud).
- **A3 (AC1):** build plain-apply mode preservation INSIDE `proposed_applied_content()` so `check`, `apply` and `remove` agree (a mode-on block must not read as drift to `check`); add a `check` case to AC10. Validate the branch name exactly as `meta-sync.sh` does (`git check-ref-format refs/heads/<name>`), not `--branch`.
- **A4 (AC1):** the managed block's "Committed on purpose: … the judgement TRAIL …" comment is false in a mode-on block — the mode-on block replaces/drops that paragraph; mode-off bytes stay unchanged.
- **A5 (AC6, PR body):** with the `check-ignore` drop skipped, the ledger allowlist is honoured by meta-sync's scrub rule (a), so a foreign-repo ledger line blocks the WHOLE push (every trail path), not just the ledger — say so in the PR body.
- **A6 (Validation 6):** re-verify the premises the reviewer could not finish: vendor-coupling allowances (5/2/2), the exact SKIP strings in `test-context-digest.sh` / `test-harvest-conventions.sh`, `ARCHITECTURE_CONTRACTS.md` §"Metadata branch" "3-way rule" paragraph, SKILL §4 "On every start" heading, `commands/setup.md` §"Module: memory", `session-resume.sh` hint format.

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-02-parallel-automate-03-branch-mode-engine.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-02T11:25:44Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/347
- **Branch:** feature/parallel-automate-03-branch-mode-engine
- **Files changed:** 34
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Branch mode (default OFF): setup-memory --branch-mode + the one `mode` reader, meta-entry pull-first verdict, mode-on trail push via meta-sync (evidence-gated, loud failures), offline SessionStart hint, corpus fixtures, SKILL §13, v15.118.0. Phase 4.5 consistency_audit FAIL ×3: iter1 reader reused writer gate (fixed f162a5a, verified), iter2 option-shaped branch names (fixed fa0f859, verified), iter3 writer fail-open on empty/garbage reader answer + empty-branch mode line read off (fixed 5a9404a, NOT re-reviewed; also removed LC_ALL=C from read_mode after Homebrew bash 5.3 post-fork locale segfaults). Ground truth 2/2, benchmark pass, contract conformance pass (2 contracts), risk high. Default drain suppressed by /automate (auto_review=false) — the engine owns the drain.

## Not verified
- **real /automate entry+resume on an installed plugin in branch mode** — needs merge + reinstall + M1 (subtask 1)
- **Linux/GNU bash CI run of the new cases** — only macOS bash run locally (subtask 1)
- **real desktop/webhook delivery on meta-push FAILED** — exercised through stubbed notifiers only (subtask 1)
- **fix iteration 3 (5a9404a)** — final heal iteration, not LLM re-reviewed (fix-3)
