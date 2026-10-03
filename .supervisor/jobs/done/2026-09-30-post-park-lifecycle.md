# Supervisor Job: The post-park lifecycle, owned by the engine — `trail-pr` at every park and at run end, and a merge watcher that runs a scripted `closeout` when the owner merges

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean apart from the gitignored run file + this brief; branch `main` == origin/main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (the engine running THIS item executes the installed 15.113.0 plugin cache, which equals the repo version; the code under change is the repo's own `loomwright/`, and the new subcommands are NOT live for this run — this run's own trail/close-out stays manual)
- **Source requirement:** .supervisor/requirements/automate-followups/11-post-park-lifecycle.md
- **Base commit:** 8d443d6ee4da8f56db092176fb4475cb90031f1e

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash scripts + bash self-tests + SKILL/command/schema prose. macOS bash 3.2 / BSD userland; no `timeout`. |
| 2 | Dependency Availability | GO | `git`, `gh`, `jq` already required by `automate-helpers.sh`. Reuses `reconcile-item`, `brief-repair`, `queue-checkoff`, `progress-append`, `worktree-salvage.sh`, `run-lock.sh`, `notify-desktop.sh`, `send-webhook.sh`, `result_block_parser.py`. |
| 3 | Architecture Fit | CAUTION | `automate-helpers.sh`'s header promises it "never runs git mutations of its own"; `trail-pr` and `closeout` are git mutators by design. Resolved by decision 1 (a sibling script, dispatched from the helper, with the header's read-only claim narrowed to name the carve-out). |
| 4 | Scope vs Supervisor Capability | CAUTION | 11 unique files (8 modify, 3 create) but an expected >800 changed lines — two new scripts plus a fixture-heavy suite (bare-repo remote, stubbed `gh`, watcher timing legs) — too much for one worker's context. Split in two sequential subtasks, one PR (`Split reason: context-bound`), exactly as the requirement's planning note asks. |
| 5 | Hard Blockers | GO | None. One premise is empirical (what checkout state lets a plain `git pull` succeed after the owner merges the trail PR) — decision 4 makes the worker establish it with a fixture before choosing. |

**Overall Verdict:** CAUTION (proceed; findings 3 and 4 carried into Risk Assessment)

## Task
**Goal:** When an `/automate` item parks (or the run ends), the engine commits its own trail as ONE PR from a temporary worktree off fresh `origin/main`, then releases the run-lock. When the park is `awaiting_merge`, a detached pure-bash watcher polls the PR; on `MERGED` it runs one deterministic, idempotent, fail-SAFE `closeout` (brief repair, squash-safe local cleanup, `main` sync, requirement stamp, trail push, queue check-off) and notifies. It never picks the next Queue item, never merges anything, and a result sidecar that fails its schema shape check is never committed.

**Problem Statement:** Nothing in the engine commits the tracked `.supervisor` trail (8 hand-built chore PRs so far; #303's hand-retyped sidecars drifted from `RESULT_SCHEMAS.md`), and a safe-mode `awaiting_merge` park is a dead end: §12 stops the `/loop` driver on `paused`, so §8's "RECONCILE re-checks the PR each tick" describes a tick that never happens. The post-merge close-out exists only as a memory note whose branch-removal guard ("0 commits outside origin/main") is wrong under squash merges.

## Design decisions (settled here so the worker does not choose)
1. **Code placement — a sibling script, dispatched from the helper.** Create `loomwright/scripts/automate-trail.sh` implementing three subcommands: `sidecar-check`, `trail-pr`, `closeout`. Add three dispatcher rows to `automate-helpers.sh`'s `main()` that `exec bash "$(dirname "$0")/automate-trail.sh" <subcmd> "$@"` (new pattern; the nearest precedent is `brief-repair` shelling out to the sibling `reconcile-jobs.sh` — one mover per concern). Update `automate-helpers.sh`'s header: add the three subcommand usage lines, and narrow the "READ-ONLY … never runs git mutations of its own" sentence to name the carve-out ("`trail-pr`/`closeout` are delegated to `automate-trail.sh`, which is a git/`gh pr create` mutator bounded to this run's trail branch and this PR's local branch/worktree — never `gh pr merge`"). Narrow the SAME claim in `skills/automate-loop/SKILL.md` §1.5's blockquote after the helper table ("`automate-helpers.sh` is READ-ONLY … no git mutations") in this change, and fix the Anti-Patterns line "the only sidecar is the transient config-backup" (already stale — it now also omits the §6 result sidecars and the new `.merge-watch` marker). The watcher is its own script, `loomwright/scripts/automate-merge-watch.sh`. Both new scripts: `set -uo pipefail` (NOT `-e`) with explicit checks, always `exit 0`, bash-3.2 safe, `LOOMWRIGHT_GH_BIN`/`LOOMWRIGHT_JQ_BIN` stub seams exactly as `automate-helpers.sh` uses them, plus a `LOOMWRIGHT_GIT_BIN` seam only if a test genuinely needs to fail `git push` (prefer a real bare-repo remote in fixtures).
2. **`sidecar-check <path>` (subtask 1) — reuse the parser, one key table per schema.** Locate the LAST block with `result_block_parser.py`'s `find_last_named_block` (or `find_last_block`) and parse it with `parse_block` (import from a small inline `python3` heredoc; do NOT add a CLI to the library). Detect the block type from its heading (`REVIEW_HEAL_RESULT` / `SUPERVISOR_RESULT`). Use a key table for BOTH (`validate-supervisor-result.py` exposes only `main()`, nothing importable). Key tables pin to `docs/RESULT_SCHEMAS.md` §REVIEW_HEAL_RESULT / §SUPERVISOR_RESULT for required + allowed keys; the `channels_scanned` vocabulary pins to `skills/review-heal/SKILL.md` §"Step U1 — All-Channel Read" (`reviews`, `latestReviews`, `reviewThreads`, `issue_comments`, `check_outputs`) — RESULT_SCHEMAS lists channels only as "e.g.". `rounds` is treated as required for v2 even though the schema block marks only the first seven fields required — say why in the table comment (the drain always emits it; the #303 drift dropped it). Out of scope for this change: the schema's empty-means-omit rules (`checks_untrusted: []`, `sub_floor_fixed` outside `sub_floor_converged`) are NOT enforced — the committed item-10 sidecar carries both and is AC2's positive control. Fail on: a missing required key (e.g. v2 `rounds`), any non-schema key (e.g. `ready_sha` — a `gate-eval` ctx key, never a result field), a non-canonical `channels_scanned` token, and `risk_classification` present without `reasons`. Output: `ok <path>` or `fail <path>: <reason>` (one line), always exit 0. Put a comment above each key table naming the schema section it mirrors (restating-copy rule).
3. **`trail-pr <runfile> [--reason <park_reason>]` (subtask 1).**
   - **Paths (explicit, never `git add -A`/`.`):** the run file; the two sidecars `<run_id>.review-heal-result.md` / `<run_id>.supervisor-result.md` IF present AND `sidecar-check` says `ok` (a `fail` sidecar is excluded and reported); every `## Queue` requirement path; every `.supervisor/jobs/done/*.md` / `jobs/failed/*.md` brief whose `- **Source requirement:**` token equals a Queue item; and `.supervisor/postmortem/results.jsonl` — but only the lines whose `automate_key` (or `run_id`) belongs to this run, appended to the trail base's copy (never the whole local file). Each candidate path is dropped unless `git check-ignore -q` says it is NOT ignored (this is how the ledger's repo-allowlist gate is honoured) and it differs from the trail base.
   - **Branch + idempotency:** look up this run's trail PRs with `gh pr list --state all --head <prefix>` (or `--search head:`) where the prefix is `chore/<run_id>-trail`. An OPEN one ⇒ fetch its branch, base the worktree on it, push fast-forward to it. None open ⇒ branch `chore/<run_id>-trail-<n>` with `n` = (count of this run's trail PRs in any state) + 1, based on fresh `origin/main`; if that remote branch already exists without a PR (crash between push and PR-open), base on it instead and open its PR. No path differs from the base ⇒ `trail-pr: skipped — trail already up to date` (no commit, no PR). Never force-push.
   - **Mechanics:** `git fetch origin`; `git worktree add` into a `mktemp -d` sibling; copy each path by explicit path from the primary checkout (gitignored scratch does not exist in a fresh worktree); `git add -- <paths>`; commit `chore(supervisor): <run_id> trail (<reason>)`; `git push -u origin <branch>`; `gh pr create --base main` (title + body naming the run, the reason, and the path list) or reuse; remove the worktree (after `worktree-salvage.sh` — it will be clean) in a trap so a failure never leaks it.
   - **Output:** exactly ONE line, `trail-pr: opened <url>` / `trail-pr: pushed <url>` / `trail-pr: skipped — <reason>` (sidecar exclusions are named inside that line or on a second `trail-pr: excluded <path> — <reason>` line — pick one and document it). Always exit 0. The loop appends the output to `## Progress`.
4. **The checkout after a trail PR (subtask 1, requirement scope (b)) — decided by a fixture, not by assumption.** First write the fixture: a primary checkout with trail paths untracked-or-modified, a trail PR branch holding identical bytes, the trail PR "merged" into the bare remote's `main`, then plain `git checkout main && git pull` in the primary. Establish which state lets that pull succeed. Candidates in preference order: (a) after a successful push, `git add -- <the committed paths>` in the primary so the index carries exactly the committed bytes (check whether a fast-forward accepts index == incoming blob for both an untracked-then-staged and a modified-then-staged path); (b) leave the working copies untouched and make `closeout`'s sync step (decision 6 step 4) move divergent-but-superset local trail copies aside, `pull --ff-only`, and move them back. Implement whichever the fixture proves; if (a) fails for the live run file (it keeps changing after staging), combine (a) for static paths with (b) for the paths whose committed bytes differ from the local file BY DESIGN — the live run file AND `.supervisor/postmortem/results.jsonl` (committed as base + this run's lines only). The AC6 fixture includes both. Document the chosen contract in the SKILL section. Never `git reset`, never `git stash drop`, never discard a byte that is not already on the remote.
5. **Wire `trail-pr` into the protocol (subtask 1).** New SKILL section `### Trail PR at every park and at run end` under §6, plus a §1.5 helper-table row for each new subcommand. Every park path (`awaiting_merge`, `escalated`, `limit_reached`, `rate_limit`, `drain_died`, `token_ceiling`) and the `## Status: done` termination call `trail-pr` BEFORE `run-lock.sh release`; update §6 step 6's release paragraph and the Termination subsection to say so. `run_lock_held` and `resume_ambiguous` parks do NOT call it (the run never acquired / never resolved). Fail-SAFE: the loop ignores `trail-pr`'s exit status; a trail failure never blocks a park or changes a gate decision.
6. **`closeout <runfile> <item> <pr_url> [--session-id <sid>]` (subtask 2).** Guards first: missing run file ⇒ one `skipped — run file not found` line, exit 0 (never let `queue-checkoff`'s `set -e` exit 1 escape); `gh` not on PATH / `gh auth status` failing ⇒ `skipped — gh unavailable` (so the reason is not the misleading `awaiting_merge` that `reconcile-item` maps a gh failure to). Then steps in this order, each printing exactly one `<verb> — …` line (`repaired|removed|synced|stamped|trailed|checked|skipped — <reason>`):
   1. **Evidence gate:** `automate-helpers.sh reconcile-item <pr_url>`; anything but `merged` ⇒ one `skipped — pr not merged (<state>)` line and stop.
   2. **Brief repair:** `automate-helpers.sh brief-repair <item> <pr_url>` (unchanged; its line is passed through).
   3. **Local cleanup, squash-safe (3a worktrees → 4 sync → 3b branch — this IS the order):** resolve `headRefName`/`headRefOid` via ONE `gh pr view --json headRefName,headRefOid`. **3a.** For each `git worktree list --porcelain` entry checked out on that branch (never the primary): `worktree-salvage.sh <wt> --reason "automate closeout"`, then `git worktree remove` — only when the worktree is clean after salvage; else keep + `skipped`. **3b (runs AFTER step 4):** the local branch: delete with `git branch -D` ONLY IF its tip == `headRefOid`; a different tip ⇒ keep + `skipped — local tip <sha> != merged head <sha>`. `-d` is wrong here (it refuses squash-merged branches by design). Never infer "merged" from git ancestry. Never touch any other branch or worktree. If step 4's sync was refused while the primary is still ON that branch, 3b is `skipped — branch checked out in primary` (git cannot delete a checked-out branch).
   4. **Sync:** refuse (`skipped`) when the primary checkout has uncommitted changes OUTSIDE the trail paths, or is on a branch other than `main` / this PR's head. Otherwise `git checkout main` then `git pull --ff-only` using decision 4's contract. A refused pull ⇒ `skipped — <reason>`, never a reset.
   5. **Requirement stamp:** if the requirement already carries `<!-- loomwright:requirement-closeout -->` (Phase 4.5's completion tail normally stamped it) ⇒ `skipped — already stamped`; otherwise append the PASS-shape footer exactly as `skills/self-heal-advisory/SKILL.md` completion-tail step 5 defines it (read it; never rewrite the heading).
   6. **Trail:** call `trail-pr <runfile> --reason closeout` via the dispatcher (a stub-able call, asserted by a spy — never an inline re-implementation).
   7. **Check off:** `automate-helpers.sh queue-checkoff <runfile> <item>` with NO reason argument (the third argument is a SKIP REASON; `done` there writes `# skipped: done`), then `progress-append` one line per step outcome.
   **Concurrency:** steps 3–7 run under `run-lock.sh acquire --owner automate-closeout:<run_id>`, passing `--session-id <sid>` through when given. RECONCILE (decision 8) runs inside a PICK that already holds `automate:<run_id>` with the loop's session id, so it MUST pass `--session-id <that id>` — the acquire then RE-ENTERS (outer owner unchanged, and closeout's own release is a no-op). The watcher passes no `--session-id`. A held lock that is not re-enterable ⇒ steps 3–7 are one `skipped — run lock held by <owner>` line and the watcher retries on a later poll. Release in a trap. **Idempotent:** a second run is all `skipped — already …` lines. **Always exit 0**, including with `gh` absent/failing.
7. **The merge watcher `automate-merge-watch.sh <runfile> <item> <pr_url>` (subtask 2).** Pure bash, detached (`env -u CLAUDE_PID -u CLAUDECODE nohup … >log 2>&1 &` by the launcher, NOT `setsid`; stdin from `/dev/null`), no Claude session, no tokens. Unsetting `CLAUDE_PID`/`CLAUDECODE` is load-bearing: otherwise `run-lock.sh`'s holder resolution records the launching Claude session's pid, and a close-out that dies without its trap leaves a lock that cannot be reclaimed while that session lives; with them unset `pid_source` is `ppid` (the watcher's shell). A test asserts `pid_source` `ppid` in the lock meta during a watcher-driven closeout.
   - **Single instance:** marker `.supervisor/automate/<run_id>.merge-watch` (a TSV `pid`/`pr_url`/`started` file — gitignored under `.supervisor/automate/*`, because it is not `*.md`). A live pid for the same run ⇒ the second launch prints `merge-watch: already running pid=<p>` and exits 0. A dead pid ⇒ reclaim.
   - **Loop:** `gh pr view <url> --json state` every `LOOMWRIGHT_MERGE_WATCH_INTERVAL` seconds (default 60), doubling on a `gh` error up to 15 min, reset on success. `MERGED` ⇒ run `closeout` (retry on a later poll while it reports `skipped — run lock held`, at most the lifetime cap), then one notify (`notify-desktop.sh` + `send-webhook.sh`, both fail-safe) and exit. `CLOSED` ⇒ `progress-append` a `gone` line, notify, exit (no cleanup — §4's `gone` rules stand). Lifetime cap `LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS` (default 259200 = 72h) ⇒ a `## Progress` line and exit. Remove the marker on every exit (trap). Sleep via `sleep` (no `timeout`).
   - **Launch point:** SKILL §9 safe-mode `READY` park — after `trail-pr`, before the lock release — launches it. An `escalated` park does NOT arm a watcher.
   - Rejected alternative (say so in the SKILL section, one sentence): an in-session `Monitor` until-loop dies with the session and is not verified headless.
8. **Resume path (subtask 2).** §6 step 1 RECONCILE: when `reconcile-item` returns `merged` for an `awaiting_merge`/`escalated` item, call `closeout` (it subsumes today's `brief-repair` call there — replace that sentence, keep the brief-repair subsection accurate) BEFORE any PICK. Also: a live watcher marker for the run's in-flight PR is noted in `## Progress` rather than launching a second watcher. §6 step 5 SYNC (auto-merge path) is unchanged.
9. **§8 fix (subtask 2).** Replace "RECONCILE re-checks the PR each tick and resumes once it merges" with the real mechanism: the merge watcher armed at the `awaiting_merge` park, plus `--resume` RECONCILE; the owner's explicit go is still required before the next item is picked. Fix the same claim where it is restated in other words: §4 step 2 ("resumed on merge per §8"), §9's safe-mode bullet ("RECONCILE resumes once a human merges"), and any hit of `each tick|resumes once|resumed on merge` in `automate-loop/SKILL.md`, `commands/automate.md` and `docs/RESULT_SCHEMAS.md` §AUTOMATE_RUN.
10. **Run-file contract (subtask 2).** `## Current` gains an optional `- merge_watch: <pid>|null` line only if the loop needs it for resume detection; otherwise the marker file is the only state. If a line is added, update the §3 template AND `docs/RESULT_SCHEMAS.md` §AUTOMATE_RUN in the same change. `commands/automate.md` mirrors ONLY the surface (one bullet each for trail-pr at park and the merge watcher/closeout in the overview list) — no contract restated.
11. **Memory note (subtask 2).** Out of the repo: NOT a worker edit. The main thread updates `automate-merge-closeout-before-next-item` after merge (scope (j)); the worker only mentions it in the PR body.
12. **Tests (both subtasks) — one new suite, `loomwright/scripts/test-automate-trail.sh`.** First executable line sources `hermetic-test-env.sh`. Fixtures: a bare repo as `origin` + a primary clone + stubbed `gh` (a script on `PATH` via `LOOMWRIGHT_GH_BIN` that answers `pr list`/`pr view`/`pr create` from files and logs its argv). Subtask 1 adds the sidecar-check legs (3 negatives + positive control), trail-pr legs (stages only trail paths — a stray untracked file and an unrelated modified file are NOT committed; re-run opens no second PR; `gh` failure ⇒ skip line + exit 0; decision-4 post-merge pull), and the park call-order leg (park ordering is SKILL prose driven by the inline loop, so it is a SKILL-text grep that `trail-pr` precedes `run-lock.sh release` on every park path, AND a behavioural assertion that `trail-pr` itself never calls `run-lock.sh`). Subtask 2 adds closeout legs (removes this PR's worktree + branch, leaves an unrelated one; tip ≠ headRefOid ⇒ kept; dirty worktree ⇒ salvaged then removed, or kept if still dirty — assert whichever decision 6 step 3 does; `OPEN` ⇒ nothing removed; idempotent second run; `gh` absent ⇒ exit 0; spy asserts `trail-pr` is invoked; the run file reads `- [x] <path>` and never `# skipped: done`) and watcher legs (`OPEN → MERGED` flip ⇒ exactly one closeout + one notify then exit; `CLOSED` ⇒ no cleanup + `gone` line; lifetime cap ⇒ clean exit; second launch ⇒ no second poller), with interval/cap env overrides so the suite runs in seconds. RECONCILE gets a BEHAVIOURAL leg, not only a grep: hold the lock as `automate:<run_id>` with session S (`run-lock.sh acquire --session-id S`), then `closeout --session-id S` on a merged fixture PR performs steps 3–7 (worktree/branch removed, item checked off) and the lock is still held by `automate:<run_id>` afterwards; the same call WITHOUT `--session-id` yields `skipped — run lock held`. Plus the SKILL-text grep that §6 step 1 names closeout before PICK. Keep every `grep -q` off a pipefail pipe (SIGPIPE trap) and every loop glob `nullglob`-safe.
13. **Release.** Minor bump 15.113.0 ⇒ 15.114.0 in `loomwright/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, new top `CHANGELOG.md` entry (single bold `**v15.114.0 — title:**` paragraph, existing convention). No agent/command/skill/hook count change; plugin descriptions untouched. Run `scripts/check-vendor-coupling.sh` after `git add` and add manifest counts for the new files only if it asks (unclassified default is `core`).

## Acceptance Criteria
**Part A (subtask 1)**
- [ ] **AC1:** `automate-helpers.sh sidecar-check|trail-pr|closeout` dispatch to `automate-trail.sh`; `--help` lists them; the helper header's read-only sentence names the carve-out.
- [ ] **AC2:** `sidecar-check` fails a REVIEW_HEAL_RESULT missing `rounds`, one carrying `ready_sha`, and a SUPERVISOR_RESULT whose `risk_classification` lacks `reasons` (three fixture legs), and passes the committed item-10 sidecars' shape (positive control built from `git show d8662b3:<path>` content copied into the fixture).
- [ ] **AC3:** `trail-pr` commits only the run's trail paths — a stray untracked file and an unrelated modified tracked file in the primary are absent from the trail commit (`git show --name-only`).
- [ ] **AC4:** re-running `trail-pr` for the same park opens no second PR (stubbed `gh pr list` returns the open one; `gh pr create` call count stays 1); a no-diff re-run prints `skipped — trail already up to date`.
- [ ] **AC5:** a failing sidecar is excluded from the commit and named in `trail-pr`'s output.
- [ ] **AC6:** after the trail PR is "merged" into the fixture remote, plain `git checkout main && git pull` in the primary succeeds with no manual reset (decision 4's contract, documented in the SKILL section).
- [ ] **AC7:** `trail-pr` always exits 0; with `gh` failing it prints one `skipped` line; it never calls `run-lock.sh`, never `gh pr merge`, never force-pushes (grep the script + the stub's argv log).
- [ ] **AC8:** SKILL §6/§9/Termination name `trail-pr` before `run-lock.sh release` on every park path listed in decision 5 and at `## Status: done`; §1.5 has the three new rows.
**Part B (subtask 2)**
- [ ] **AC9:** `closeout` on a squash-merged fixture PR (stub `MERGED`, `headRefOid` = local tip) removes that PR's worktree and local branch and leaves an unrelated branch + worktree untouched.
- [ ] **AC10:** guard legs — tip ≠ `headRefOid` ⇒ branch kept + `skipped`; dirty worktree ⇒ salvaged (salvage dir exists) then per decision 6 step 3; `OPEN` ⇒ nothing removed, one `skipped` line; primary dirty outside trail paths ⇒ sync `skipped`.
- [ ] **AC11:** `closeout` is idempotent (second run: every line `skipped — already …` or `skipped — …`, no mutation) and exits 0 with `gh` absent.
- [ ] **AC12:** `closeout` invokes `trail-pr` (spy asserted) and the run file reads `- [x] <item>` — never `# skipped: done`.
- [ ] **AC13:** watcher legs — `OPEN → MERGED` ⇒ exactly one closeout + one notify then exit; `CLOSED` ⇒ no cleanup + a `gone` Progress line; lifetime cap ⇒ exit + Progress line; a second launch for the same run ⇒ `already running`, no second poller; the marker is gone after every exit.
- [ ] **AC14:** SKILL §6 step 1 RECONCILE runs `closeout --session-id <loop sid>` on `merged` before PICK, and the decision-12 re-entry leg passes (steps 3–7 run under a lock held by `automate:<run_id>`; without `--session-id` they are skipped); a watcher-driven closeout records `pid_source` `ppid`; §4 step 2, §8 and §9 no longer claim a per-tick re-check / automatic resume on merge (decision 9 grep has no such hit).
**Both**
- [ ] **AC15 (invariants):** the `gh pr merge --squash` positive grep (CLAUDE.md §Failure-Mode Invariants) resolves to exactly the same 5 surfaces; neither new script runs `gh pr merge` or invokes `/autonomous`/PICK; no new agent/command/skill/hook.
- [ ] **AC16 (mirrors):** `commands/automate.md` mirrors only the surface; `docs/RESULT_SCHEMAS.md` §AUTOMATE_RUN updated iff a run-file line was added; `scripts/check-command-sync.sh` green.
- [ ] **AC17 (portability):** `bash -n` both new scripts; no `timeout`, no GNU-only `stat`/`date`/`sed -i` forms; the suite passes under macOS `/bin/bash` 3.2.
- [ ] **AC18 (release):** 15.114.0 in `plugin.json` + `marketplace.json`, new top CHANGELOG entry; `scripts/check-doc-currency.sh` + `scripts/validate-version.sh` green.
- [ ] **AC19 (full loop green):** under `bash`: every `loomwright/scripts/test-*.sh`, `loomwright/scripts/adapters/*/test-*.sh`, root `scripts/test-*.sh`; plus `scripts/check-vendor-coupling.sh` (after `git add`), `scripts/check-doc-currency.sh`, `scripts/check-command-sync.sh`, `scripts/check-skills-index-sync.sh`, `scripts/check-token-budget.sh`, `scripts/check-test-hermetic.sh`, `scripts/check-contract-parity.sh`, and `loomwright/scripts/test-citation-drift.sh` last.

## Non-goals
- Auto-merging the trail PR or the feature PR; picking/RUNning the next Queue item after a merge (owner's explicit go stands).
- Trail for runs outside `/automate`; changing `.gitignore`.
- The desktop PR monitor, GitHub webhooks or Actions as triggers.
- SessionStart surfacing of a live watcher (`session-resume.sh` untouched) — the lifetime cap + marker bound it; note it as a follow-up in the PR body.
- Editing the out-of-repo memory note (decision 11).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Part A — `automate-trail.sh` (`sidecar-check` + `trail-pr`), dispatcher rows + header, SKILL trail section + §1.5 rows + park wiring, new test suite, version/CHANGELOG | AC1–AC8, AC15–AC19 (as they apply) | ~6 modify, 2 create | unit-testing, quality-checklist | LAUNCHABLE |
| 2 | Part B — `closeout` in `automate-trail.sh`, `automate-merge-watch.sh`, RECONCILE/§8/§9 wiring, `commands/automate.md` surface, RESULT_SCHEMAS iff needed, test legs appended | AC9–AC19 | ~5 modify, 1 create | unit-testing, quality-checklist | BLOCKED (requires 1) |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/automate-trail.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.sh", name: "trail-pr"}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.sh", name: "sidecar-check"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "automate-trail.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-trail.sh"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "Trail PR at every park and at run end"}
  - {kind: "symbol", path: "loomwright/.claude-plugin/plugin.json", name: "15.114.0"}
requires: []
lanes:
  - "loomwright/scripts/automate-trail.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.sh", name: "closeout"}
  - {kind: "file", path: "loomwright/scripts/automate-merge-watch.sh"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "automate-merge-watch.sh"}
  - {kind: "symbol", path: "loomwright/commands/automate.md", name: "closeout"}
requires:
  - {from: 1, kind: "symbol", path: "loomwright/scripts/automate-trail.sh", name: "trail-pr"}
  - {from: 1, kind: "file", path: "loomwright/scripts/test-automate-trail.sh"}
lanes:
  - "loomwright/scripts/automate-trail.sh"
  - "loomwright/scripts/automate-merge-watch.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/commands/automate.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "CHANGELOG.md"
external_requires: []
```

## Parallelism Analysis
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (BLOCKED on 1 — same files, and `closeout` calls `trail-pr`)
- **Recommended workers:** 1 (sequential, one PR)
- **Estimated batches:** 2

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| trail + closeout engine | `loomwright/scripts/automate-helpers.sh` (3 dispatcher rows + header) | `loomwright/scripts/automate-trail.sh` | HIGH |
| watcher | — | `loomwright/scripts/automate-merge-watch.sh` | HIGH |
| tests | — | `loomwright/scripts/test-automate-trail.sh` | HIGH |
| protocol | `loomwright/skills/automate-loop/SKILL.md` (§1.5, §3 iff line added, §6 steps 1/6 + Termination + new subsections, §8, §9) | — | HIGH |
| surface mirrors | `loomwright/commands/automate.md`, `loomwright/docs/RESULT_SCHEMAS.md` (§AUTOMATE_RUN, iff a run-file line is added) | — | MEDIUM |
| coupling manifest (only if the checker asks) | `loomwright/docs/vendor-coupling-manifest.json` | — | LOW |
| release | `CHANGELOG.md`, `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | — | HIGH |

> **Validator-owned surfaces:** `scripts/check-test-hermetic.sh` (the new suite must source `hermetic-test-env.sh` first), `scripts/check-vendor-coupling.sh` (scans new scripts), `scripts/check-command-sync.sh` (`commands/automate.md`), `loomwright/scripts/test-automate-helpers.sh` (its `--help` / dispatcher expectations — run it after the dispatcher edit), `loomwright/scripts/test-citation-drift.sh` (pinned citations into `automate-helpers.sh` and `automate-loop/SKILL.md` must still resolve after insertions), and the `gh pr merge --squash` positive grep (new scripts must not match it — write prose about merging as "never merges", which the negation filter drops).

## Skill References
- `skills/automate-loop/SKILL.md` §1.5, §3, §4, §6 (steps 1/5/6, Brief-repair subsection, Termination), §8, §9, §11 — the sections being extended
- `skills/self-heal-advisory/SKILL.md` completion-tail step 5 — the `<!-- loomwright:requirement-closeout -->` footer shape (read; do not copy the policy)
- `docs/RESULT_SCHEMAS.md` §REVIEW_HEAL_RESULT, §SUPERVISOR_RESULT, §AUTOMATE_RUN — the shapes `sidecar-check` mirrors
- `scripts/worktree-salvage.sh`, `scripts/run-lock.sh` headers — salvage-before-remove, lock ownership without a session
- `skills/unit-testing/SKILL.md`, `skills/quality-checklist/SKILL.md`

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

> Advisory only. Applied here: the park-path list lives once (SKILL §6 trail section) and other mentions point to it; `sidecar-check`'s key tables name the RESULT_SCHEMAS section they mirror and are updated with it; `commands/automate.md` mirrors surface only; the "each tick" claim is fixed everywhere it is restated (decision 9).

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Deleting unmerged work in `closeout` | HIGH | Only `gh` MERGED + local tip == `headRefOid` + clean-after-salvage; `-D` only after the tip check; never ancestry. AC9/AC10. |
| An unattended process with push rights (watcher → closeout → trail-pr) | HIGH | Only this run's explicit paths, only its `chore/<run_id>-trail-*` branch, never force, lifetime cap, single-instance marker; AC7/AC13. |
| Racing the owner in the primary checkout | MEDIUM | Sync refuses when dirty outside trail paths or on another branch (decision 6 step 4, AC10). |
| The post-merge `git pull` still refuses over trail copies | MEDIUM | Decision 4: fixture first, contract second; AC6. |
| Architecture: helper header promised no git mutations (Feasibility check 3) | MEDIUM | Decision 1 moves mutators to a sibling script and narrows the header sentence. |
| Context size (Feasibility check 4) | MEDIUM | Two sequential subtasks, one PR; on a worker turn limit resume via SendMessage, never respawn. |
| Ledger over-commit (whole `results.jsonl` instead of this run's lines) | MEDIUM | Decision 3: only lines keyed to this run, appended to the base copy; allowlist gate via `git check-ignore`. |
| Orphaned watcher | LOW | Marker + dead-pid reclaim + 72h cap; SessionStart surfacing deferred (non-goal). |
| `gh pr merge --squash` grep gains a sixth surface | MEDIUM | AC15; phrase merge prose negatively. |
| bash 3.2 / BSD traps (`timeout`, `stat`, `sed -i`, `grep -q` under pipefail) | MEDIUM | AC17; validate with `/bin/bash`. |

## Configuration
- **Mode:** sequential (2 subtasks, one PR)
- **Split reason:** context-bound
- **Recommended workers:** 1
- **Estimated batches:** 2

## Carried Plan Review advisories (Plan Review PASS 2/3 — owner chose save + carry; APPLY these, they refine the decisions above)
1. **MEDIUM — decision 9 / AC14 grep:** use `re-checks the PR each tick|resumes once|resume[sd]? on merge` (not bare `each tick`). §12's "`/loop` re-invokes `/automate` each tick; … `paused` … stop the driver" is ACCURATE and stays unchanged. Add the SKILL Quality Gates bullet ("`awaiting_merge` resumes on merge") to decision 9's explicit list. `commands/automate.md` and RESULT_SCHEMAS §AUTOMATE_RUN have no hits (verified).
2. **LOW — decision 6 release:** closeout's trap releases with `run-lock.sh release --owner automate-closeout:<run_id>` ONLY — never forward `--session-id` to `release` (run-lock.sh releases on EITHER owner OR session match, which would drop the outer PICK lock mid-RECONCILE). The AC14 re-entry leg asserts the outer lock survives.
3. **LOW — decision 7 wording:** `pid_source ppid` records the closeout process (run-lock.sh's `$PPID`), not the watcher shell; a closeout dying without its trap is reclaimable via dead pid + 1800s TTL.
4. **LOW — decision 6 step 5 stamp:** the PASS footer is `<!-- loomwright:requirement-closeout -->` + `## Status: done` + `- **Completed:**` / `- **Brief:** {done/ brief path}` / `- **PR:**` (self-heal-advisory completion-tail step 5). Find the done/ brief by matching its `- **Source requirement:**` token to `<item>` under `.supervisor/jobs/done/`; none found ⇒ `skipped — no done brief` (never invent a value).
5. **LOW — decision 2 wording:** `validate-supervisor-result.py` exposes no importable schema table (it has `main()` and a private helper); key tables for both schemas stand.

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-09-30-post-park-lifecycle.md

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-09-30T03:17:39Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/305
- **Branch:** feature/automate-followups-11-post-park-lifecycle
- **Files changed:** 9
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Part A trail-pr + sidecar-check (explicit-path trail PR off origin/main, idempotent, staged-committed-blob checkout contract) and Part B closeout (squash-safe, re-enters the PICK lock via --session-id, --owner-only release) + detached automate-merge-watch.sh + trail-unstage at PICK; v15.114.0. Plan Review FAIL 1/3 → PASS 2/3 (advisories carried). Phase 4.5: iter 1 FAIL (staged trail swept into next commit; watcher misread transient skips) → 4443d14; iter 2 FAIL (bash 3.2 parse; AC6 hand-pull regression) → 866529f; iter 3 FAIL (closeout refused its own sync on a self-staged non-candidate) → 704a1d9, NOT re-reviewed (final iteration). 12 below-floor findings dismissed + posted (marker round=3). rules_check: none · ground truth 2/2 · risk high_risk=true.

## Not verified
- **real `gh pr list --search head:` behaviour** — stub gh only (subtask 1)
- **SKILL park wiring driven by the live inline /automate loop** — new subcommands go live only after a plugin release (subtask 1)
- **real gh pr view --json headRefName,headRefOid / gh auth status** — stub gh only (subtask 2)
- **watcher launched from a live /automate awaiting_merge park** — suite shell only (subtask 2)
- **desktop / webhook notification delivery from the watcher** — spy scripts only (subtask 2)
