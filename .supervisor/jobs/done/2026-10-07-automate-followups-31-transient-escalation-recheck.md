# Supervisor Job: Name a temporary escalation's cause, arm the merge watcher at escalated parks (idempotently), and re-check the named check once it settles

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes-v2/s3-i
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-followups/31-transient-escalation-recheck.md
- **Base commit:** f4b0732b8f3e6a7b64fc960073e8ab680d5af9f0

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq + gh scripts, markdown docs — the repo's own stack |
| 2 | Dependency Availability | GO | `gh run view --log-failed`, `gh run view --json attempt,status,conclusion`, `gh api …/pulls/<n>/files` all available; tests stub `gh` |
| 3 | Architecture Fit | CAUTION | Two surfaces outside the requirement's declared Touches must change: `scripts/automate-trail.sh` (`sidecar-check`'s `RH_V2_ALLOWED` allow-list rejects any unlisted `REVIEW_HEAL_RESULT` key) and `docs/TELEMETRY.md` (promises "at most ONE `automate_merge_watch` event" per watcher) |
| 4 | Scope vs Supervisor Capability | CAUTION | ~19 files ⇒ `context-bound` split into two sequential subtasks |
| 5 | Hard Blockers | GO | none |

**Overall Verdict:** CAUTION

## Task
**Goal:** When an until-mergeable drain ends ESCALATED only because a required/review-producing check is still pending, or red only in test files the PR does not touch, record that cause (with check, run id, attempt, head sha) in `REVIEW_HEAL_RESULT` and the park's `## Current`; arm the merge watcher at `escalated` parks too, idempotently; and have the watcher re-check that one check and report `now mergeable` / `still failing` exactly once — never merging, pushing, approving or rerunning anything.

**Problem Statement:**
The `/automate` owner needs to know why an item parked `escalated` and whether it has since become mergeable, because in wave S2 two of five lanes (PR #381: `ci` red from a 1-second `ci-slot` timeout in `scripts/test-ci-local.sh`, a file the PR does not touch; PR #386: `claude-review` still in progress at the 1200 s bound) escalated for temporary reasons and were mergeable unchanged. Currently the park records only `escalated`, an escalated park arms no merge watcher (so a merged escalated item waits for a manual `--resume`), and a park → fix-now re-drain → re-park can arm two watchers for one PR. This costs the owner a manual diagnosis per lane. Success looks like: replaying both S2 drains through the classifier gives `check_red_unrelated` and `check_pending`, and the watcher reports `now mergeable` for both with no push.

**Owner decisions (recorded 2026-10-07 in the requirement's `## Owner decisions` section):**
- Scope 3 → **(a)**: CI rerun stays human. The park line and the watcher's `still failing` line print the exact `gh run rerun <run_id> --failed` command; nothing in this change executes `gh run rerun`. `harness-port/07`'s rule is unchanged.
- Scope 4 → **run file only**: cause + verdict live in the run file (`## Current` / `## Progress`). `lane-status` does not exist; it is not built here.

## Acceptance Criteria
- [ ] AC1 — Given the s2-c replay fixture (required check `ci` red on head `a7f9953…`, its `--log-failed` output naming only `scripts/test-ci-local.sh`, PR files not containing that file nor `scripts/ci-local.sh`), when the classifier runs, then it prints `escalation_cause: check_red_unrelated` with `check=ci`, the run id, the attempt and the sha.
- [ ] AC2 — Given the s2-d replay fixture (`ci` green, `claude-review` IN_PROGRESS on head `1e35336…`), when the classifier runs, then it prints `escalation_cause: check_pending` with `check=claude-review`, run id, attempt and sha.
- [ ] AC3 — Given a red check whose failing test file IS in the PR's files (or whose tested script `<dir>/<stem>.sh` for `<dir>/test-<stem>.sh` is in the PR's files), when classified, then the cause is `check_red`, never `check_red_unrelated`.
- [ ] AC4 — Given an unreadable log, an unreadable/incomplete PR file list, no extractable failing test file, or any `gh` failure, when classified, then the cause is `check_red` (fail closed).
- [ ] AC5 — Mutation control: a mutant classifier that decides by test name without the PR-`files` comparison is detected — a test fails on the mutant (mutant gated non-empty, differs from original, passes `bash -n`, per the repo's valid-mutant lesson).
- [ ] AC6 — Given an ESCALATED drain, when `REVIEW_HEAL_RESULT` is emitted, then it carries `escalation_cause` (+ `escalation_check`, `escalation_run_id`, `escalation_attempt`, `escalation_sha` when check-driven; `findings`/`other` causes carry `null` for those four), the keys are documented in `docs/result-schemas/review-heal-result.md`, and `sidecar-check` returns `ok` for a sidecar carrying them (and still `fail` for a genuinely non-schema key).
- [ ] AC7 — Given an `escalated` park, when its park state is written, then `## Current` carries one `- escalation_cause: <cause> | check: <c|null> | run_id: <id|null> | attempt: <n|null> | sha: <sha|null>` line written by a validated helper (enum-checked, `|`/newline refused, file byte-unchanged on refusal), and `current-set`'s existing byte-unchanged guarantee for other `## Current` lines (test B10a) still holds with no existing assertion edited.
- [ ] AC8 — Given an `escalated` park (safe or `--auto-merge` mode), when the park tail runs, then a merge watcher is armed with the existing launch line, and a merge of that PR closes the item out (the existing `closeout` path) — documented in `automate-loop/SKILL.md` §6 "Post-merge close-out"/§9 and `commands/automate.md` (the "escalated park arms none" sentences are replaced).
- [ ] AC9 — Given two parks of the same item/PR in one run (park → fix-now re-drain → re-park), when both run the park tail's existing launch line, then the test asserts all three of: (1) the second launch prints `merge-watch: already running pid=<first pid>`; (2) the first watcher's pid is still alive after the second launch; (3) the marker's `pid` field is unchanged — and that a merge then yields exactly one closeout. Mutation control: a mutant deleting exactly the same-`pr_url` `already running` branch of the watcher's single-instance block (gated non-empty, differs from original, `bash -n` clean) must fail the test — on that mutant the second launch falls into the replace-another-PR branch, TERMs the first watcher and takes over the marker, so (1)–(3) fail (it does NOT produce two pollers; poller/closeout counts alone would let it survive).
- [ ] AC10 — Given a `check_pending` park whose check later completes `success` on the recorded sha (any attempt ≥ recorded), when the watcher polls, then it appends exactly one `merge-watch: now mergeable: <check> green on <sha>` `## Progress` line and sends exactly one notify, then keeps watching for the merge; a completed non-success appends one `merge-watch: still failing: <check> <conclusion> — rerun: gh run rerun <run_id> --failed`.
- [ ] AC11 — Given a `check_red_unrelated` park, when the watcher polls, then it reports only after a NEWER attempt (> recorded attempt — i.e. a human rerun) completes: green ⇒ one `now mergeable` line; non-green ⇒ one `still failing` line. Until then it reports nothing (the recorded red attempt never triggers `still failing` by itself).
- [ ] AC12 — Given `check_red`, `findings`, `other`, or no `escalation_cause` line, when the watcher runs, then it performs no check polling and its behavior is byte-for-byte today's (existing W legs pass unedited).
- [ ] AC13 — No new code path executes `gh run rerun`, `gh pr merge`, `git push`, or any approval: a static scan in the tests asserts the watcher and classifier contain no executed `gh run rerun` / `gh pr merge` (prose/comment mentions excluded).
- [ ] AC14 — Unchanged paths: a drain ending READY and a drain escalated on findings produce the same results as before, `wait-for-checks.sh`'s default output (without the new opt-in flag) is byte-unchanged, and no existing assertion in any test file is edited (new legs only).

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Escalation-cause classifier + result/run-file schema | AC1–AC7, AC13 (classifier half), AC14 | 11 modify, 1 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | Watcher: arm at escalated parks idempotently + settle re-check + docs | AC8–AC12, AC13 (watcher half) | 6 modify, 1 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |

### Subtask 1 — design notes (the worker owns details within these contracts)

1. **`loomwright/scripts/wait-for-checks.sh`** gains an OPT-IN `--names` flag. Without it the output line is byte-unchanged (AC14). With it, the one output line gains two trailing fields covering the scoped set (required + review-producing, same scope the mode already uses): `pending_names=<comma list|none>` (every scoped check not yet completed — required checks included, which today's `pending=` omits) and `red_names=<name@run_id,…|none>` (every scoped check completed non-success/non-neutral/non-skipped; `run_id` parsed from `detailsUrl` with the same `/actions/runs/([0-9]+)/` regex `review-heal` §U4 uses, `-` when absent). New cases in `test-wait-for-checks.sh` only.
2. **New subcommand `automate-helpers.sh escalation-cause <pr_url> --sha <sha>`** implemented in a NEW family file `loomwright/scripts/automate-helpers.d/escalation.sh` (sourced by the dispatcher like the others; uses the dispatcher's `$GH`/`$JQ` seams). Algorithm, fail-CLOSED throughout:
   - Snapshot via `wait-for-checks.sh <pr_url> --sha <sha> --bound 0 --names` (review-check pattern defaults). A `sha_mismatch`/unreadable snapshot, or one reporting `required=unknown` (branch-protection read failed — the required set is then unknown, so a red required check could be missing from `red_names`), ⇒ `check_red` (tested beside AC4).
   - Any `pending_names` ⇒ `check_pending` (first pending check; run id/attempt from `gh run view <id> --json attempt` when a run id exists, else `null`).
   - Else red checks: for EACH red check fetch `gh run view <run_id> --log-failed` (no run id ⇒ `check_red`); extract failing test files from the failed steps' `##[group]Run bash <path>` lines (path matches `(loomwright/)?scripts/(…/)?test-[A-Za-z0-9._-]+\.sh`); no extractable file ⇒ `check_red`. Fetch the PR's changed files with the paginated, count-checked reader (reuse `_rs_pr_changed_paths` from `automate-helpers.d/reconcile-status.sh` — call it, do not copy it); unreadable/incomplete ⇒ `check_red`. A failing test file is RELATED when it is in the PR files OR its tested script (`<dir>/<stem>.sh` for `<dir>/test-<stem>.sh`) is in the PR files. Every failing test file of every red check unrelated ⇒ `check_red_unrelated`; otherwise `check_red`.
   - All required green and nothing pending ⇒ `other` (the escalation was not check-driven).
   - Output exactly ONE line: `escalation_cause: <cause> check=<name|null> run_id=<id|null> attempt=<n|null> sha=<sha>`; always exit 0 (a reader/classifier; the drain consumes the line).
   - Update the dispatcher usage header in `automate-helpers.sh` and regenerate `fixtures/automate-helpers-help.golden` (`bash loomwright/scripts/automate-helpers.sh --help > loomwright/scripts/fixtures/automate-helpers-help.golden`).
3. **New subcommand `current-escalation <runfile> --cause <c> [--check <c> --run-id <id> --attempt <n> --sha <sha>]`** in `automate-helpers.d/runfile.sh`: the ONLY writer of `## Current`'s `- escalation_cause:` line (insert after the `- pause_reason:` line; with no `- pause_reason:` line, append at the end of the `## Current` block, mirroring `current-set` — tested; replace if present; `--cause null` removes it). Enum `check_pending check_red_unrelated check_red findings other null`; refuse `|`/newline values; write through the same `_runfile_install … full` validation; identical values ⇒ `current-escalation: unchanged`. `current-set` itself is NOT changed (B10a stays byte-identical).
4. **Fixtures:** replay fixtures for s2-c (red `ci`, log lines copied verbatim from `gh run view 37254186674 --log-failed --attempt 1`, e.g. `ci\tCheck the local pre-push runner (ci-local.sh)\t…##[group]Run bash scripts/test-ci-local.sh` and `FAIL (L) live: rc=1 out=ci-slot: no CI slot after 1s — giving up`) and s2-d (`claude-review` IN_PROGRESS) under `loomwright/scripts/fixtures/` (or inline in the test) with stubbed `gh`; legs for every cause, the AC3 related case, the AC4 unreadable cases, and the AC5 mutation control — all in `test-automate-helpers.sh` (new legs only).
5. **Schema docs:** `docs/result-schemas/review-heal-result.md` (v2 block + field-notes rows for the five `escalation_*` keys: present only on `decision: ESCALATED`); `docs/result-schemas/automate-run.md` (`## Current` template + field table row for the optional `- escalation_cause:` line, mirroring the `pending_decisions` OPTIONAL-line precedent, and its writer); `skills/review-heal/SKILL.md` — at each ESCALATED site (bound hit, §U2.5 wait elapsed, confirming pass red/unreadable, only-human-judgment findings, rules gate, `ci_untrusted`) state the cause: check-driven sites run `escalation-cause` and copy its fields; findings sites set `findings`; rules-gate/round-ledger/`ci_untrusted` sites set `other` (ci_untrusted stays its own termination_reason — non-goal); emit list and the canonical names table (SKILL line ~62 summary) updated in the same change.
6. **`scripts/automate-trail.sh`** (outside the requirement's Touches — required): add the five keys to `RH_V2_ALLOWED` (keep in sync with the doc, as its comment says); `test-automate-trail.sh` S-leg gains a NEW positive case (sidecar with `escalation_cause` ⇒ `ok`) — existing negatives untouched.

```yaml
# Subtask 1 — Escalation-cause classifier + result/run-file schema (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/automate-helpers.d/escalation.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/escalation.sh", name: "escalation_cause"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/runfile.sh", name: "current_escalation"}
  - {kind: "symbol", path: "loomwright/scripts/wait-for-checks.sh", name: "red_names"}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.sh", name: "escalation_cause"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/review-heal-result.md", name: "escalation_cause"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "escalation_cause"}
requires: []
lanes:
  - "loomwright/scripts/wait-for-checks.sh"
  - "loomwright/scripts/test-wait-for-checks.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/automate-helpers.d/escalation.sh"
  - "loomwright/scripts/automate-helpers.d/runfile.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help.golden"
  - "loomwright/scripts/fixtures/escalation-cause/**"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/automate-trail.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/docs/result-schemas/review-heal-result.md"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/docs/prompt-token-budgets.json"
external_requires:
  - "gh CLI (run view --log-failed, run view --json attempt, api pulls/<n>/files) — stubbed in tests"
```

### Subtask 2 — design notes

1. **Idempotent arming — diagnosis first, no new entry point.** The amendment's evidence (s3-g, #403, "two merge watchers") was re-checked at Launch Pad against the lane archive (`archive/s3-g/s1h-lane.log` + `automate-2026-10-06-154217.merge-watch.log`): the lane ran the launch line ONCE (one `pid\t86028` marker, one `merge-watch: started`, one closeout); the fix-now decision step runs BEFORE the park, so that item parked once. The watcher's single-instance block already makes a same-`pr_url` second launch print `already running` and exit, under a noclobber marker. The most likely source of the observation: every `$(…)` command substitution inside the watcher forks a subshell with the same argv, so `pgrep -f automate-merge-watch` during a poll shows two processes for one watcher. So: (a) NO `--arm` flag — both parks (`awaiting_merge` and now `escalated`) use the existing documented launch line unchanged; (b) AC9 is a REGRESSION test of the existing guard (park → fix-now re-drain → re-park of the same PR ⇒ one live poller, one closeout), its mutation control deleting exactly the in-watcher same-`pr_url` `already running` branch and failing on the already-running line / first-pid-alive / marker-pid-unchanged assertions (AC9); (c) the watcher's header and SKILL §6 "Single instance per run" gain one sentence: count watchers by the marker (`<run_id>.merge-watch` pid) or `ps -o ppid` lineage, never by `pgrep -f` (subshell forks share the argv). The PR body states this diagnosis and that the S3 record's gap 6 was a counting artifact (honest limit: inferred from the archive, not reproduced live).
2. **Settle re-check:** in the poll loop's OPEN branch (before the nap), when the run file's `## Current` names THIS item/PR and carries `- escalation_cause: check_pending|check_red_unrelated` with a non-null check + sha, poll the check — via `gh run view <run_id> --json attempt,status,conclusion` when a run id is recorded, else `gh api repos/<o>/<r>/commits/<sha>/check-runs` filtered by name. Report rule: `check_pending` ⇒ first completed state at attempt ≥ recorded; `check_red_unrelated` ⇒ first completed state at attempt > recorded. Report = ONE `progress` line (`now mergeable: <check> green on <sha>` / `still failing: <check> <conclusion> — rerun: gh run rerun <run_id> --failed`) + ONE notify with a DISTINCT gate type `automate_escalation_recheck`, then a latch (also idempotent across a watcher restart: skip if `## Progress` already holds a `merge-watch: now mergeable:`/`still failing:` line for that sha). Never merges, pushes, approves, or reruns. The new `gh` calls go through `LOOMWRIGHT_GH_BIN`; add a `run view`/`api` arm to the test's gh stub without changing how `pr view` pops `state-seq` (the existing W-leg sequences must not shift).
3. **Docs:** `skills/automate-loop/SKILL.md` — §6 "Post-merge close-out" ("Armed ONLY at … `awaiting_merge` … an `escalated` park arms none" → both parks arm, with the same launch line), §6 "Dismissed-findings decision step" step 4 park-tail wording, §9 safe-mode + ESCALATED tails, the RECONCILE live-marker sentence in §6 step 1; the §3 run-file template's `## Current` gains the optional `escalation_cause` line (mirror of `automate-run.md`); `commands/automate.md` ("an `awaiting_merge` park arms…"); the watcher's own header comment; `docs/TELEMETRY.md` table + "at most ONE `automate_merge_watch` event" sentence (add the `automate_escalation_recheck` row, at most one per watcher). Grep every old sentence repo-wide (`grep -rn "arms none\|awaiting_merge. park arms" loomwright/`) before finishing.
4. **Tests (new legs in `test-automate-trail.sh` only):** escalated park arms + merge closes out; double-arm ⇒ one live watcher + one closeout, with the liveness-check-removed mutant failing; `check_pending` → green ⇒ exactly one `now mergeable` line and one recheck notify; `check_red_unrelated` with recorded red attempt only ⇒ no report, then attempt+1 green ⇒ one `now mergeable`; non-green ⇒ one `still failing` carrying the rerun command; `check_red`/absent ⇒ no check calls; static scan: no executed `gh run rerun`/`gh pr merge` in the watcher; the bash-3.2 heredoc scan still covers the watcher.
5. **Changelog:** `changelog.d/automate-followups-31-transient-escalation-recheck.md` (`<!-- bump: minor -->`, headline, prose — states the deliberate change "a sequential `escalated` park now arms a merge watcher" and the owner decisions). Do NOT run `bump-version.sh` and do not edit `plugin.json`/`CHANGELOG.md`.

```yaml
# Subtask 2 — Watcher arms at escalated parks idempotently + settle re-check + docs (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-merge-watch.sh", name: "automate_escalation_recheck"}
  - {kind: "symbol", path: "loomwright/scripts/automate-merge-watch.sh", name: "now mergeable"}
  - {kind: "symbol", path: "loomwright/docs/TELEMETRY.md", name: "automate_escalation_recheck"}
  - {kind: "file", path: "changelog.d/automate-followups-31-transient-escalation-recheck.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-helpers.d/runfile.sh", name: "current_escalation"}
  - {from: "1", kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "escalation_cause"}
lanes:
  - "loomwright/scripts/automate-merge-watch.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/commands/automate.md"
  - "loomwright/docs/TELEMETRY.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/docs/prompt-token-budgets.json"
  - "changelog.d/automate-followups-31-transient-escalation-recheck.md"
external_requires:
  - "gh CLI (run view --json attempt,status,conclusion; api commits/<sha>/check-runs) — stubbed in tests"
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `loomwright/scripts/test-automate-trail.sh`, `loomwright/docs/vendor-coupling-manifest.json`, `loomwright/docs/prompt-token-budgets.json` | YES (and #2 requires #1's `current-escalation` line format) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| `sidecar-check`'s `RH_V2_ALLOWED` allow-list rejects the new keys, silently dropping the review-heal sidecar from trail PRs (Feasibility 3) | HIGH | Subtask 1 updates `automate-trail.sh` in the same change + a positive S-leg case |
| `docs/TELEMETRY.md` and W-leg tests assert one notify per watcher (Feasibility 3) | MEDIUM | Re-check uses a distinct gate type `automate_escalation_recheck`; existing `automate_merge_watch` counts unchanged; new legs count the new type separately; TELEMETRY.md updated |
| The `gh` stub pops `state-seq` on every `pr view <url>`; a new `pr view` per poll would shift existing W-leg sequences | MEDIUM | Re-check uses `gh run view` / `gh api` only, never an extra `pr view`; add stub arms for those |
| `check_red_unrelated` misclassifies a test that exercises a script the PR changed | MEDIUM | Related = failing test file in PR files OR its `<stem>.sh` in PR files; anything unparseable ⇒ `check_red`; the label only gates a report, never a merge |
| A human rerun creates a new attempt; the recorded red attempt would otherwise trigger "still failing" immediately | MEDIUM | Record `attempt`; `check_red_unrelated` reports only at attempt > recorded (AC11) |
| `current-set` byte-unchanged test (B10a) | MEDIUM | New writer is a separate subcommand; `current-set` untouched |
| Feasibility (Phase 2.5): ~19 files exceed one worker's context bound | MEDIUM | `context-bound` split into two sequential subtasks |
| Dispatcher `--help` golden and the vendor-coupling / prompt-token-budget ratchets shift with the edits | LOW | Regenerate the golden; re-baseline `vendor-coupling-manifest.json` / `prompt-token-budgets.json` (in BOTH subtasks' lanes, ordered #1 → #2) only if `bash scripts/ci-local.sh` reports them, with a reason string |
| The amendment's "two watchers" premise is a counting artifact, not a guard gap (Launch Pad re-diagnosis from the s3-g archive) | MEDIUM | No new arming code; AC9 regression-tests the existing guard with a valid mutant; PR body states the diagnosis and its honest limit |
| Validation step 3 (a real escalated park on a pending `claude-review`) cannot be produced inside the PR's own tests | LOW | Covered by replay fixtures; the live observation is an owner/post-merge check, stated as an honest limit in the PR body |
| Mutation controls silently invalid (lesson fa32a308) | MEDIUM | Gate each mutant on non-empty + differs + `bash -n` before trusting it |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-07-automate-followups-31-transient-escalation-recheck.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-07T11:13:04Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/415
- **Branch:** feature/automate-followups-31-transient-escalation-recheck
- **Files changed:** 22
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Escalation-cause classifier (fail-closed check_red), escalation_* REVIEW_HEAL_RESULT keys + optional ## Current line, merge watcher armed at escalated parks with a one-shot (per escalation line) settle re-check; 3 heal iterations each fixing 2–3 reproduced HIGH findings; final fix bc47a2e not LLM re-reviewed; ci-local 148/148 PASS on every pushed tree. Ground truth skipped (no Executable Acceptance) — unverified, not clean.

## Not verified
- **Live --until-mergeable drain emitting escalation_* in REVIEW_HEAL_RESULT** — needs a real escalated drain on a live PR; covered only by replay fixtures (subtask 1)
- **agents/review-pr.md, commands/review-pr.md, ARCHITECTURE_CONTRACTS.md result-field lists** — outside subtask 1's lanes (Phase 4.5 iteration 1 checked: no closed key list, no drift) (subtask 1)
- **A live /automate escalated park on a real pending or unrelated-red check** — hermetic gh stub only; needs a live forge run (subtask 2)
- **Real field shapes of gh run view and the commits check-runs API** — stubbed in tests; no network allowed (subtask 2)
