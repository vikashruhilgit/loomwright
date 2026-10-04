# S1 — Two-lane spike (OPERATOR-RUN — not an `/automate` item; no plugin change)

## Status: parked (operator-run: lives in `operator-run/` so folder intake never enqueues it; run by hand after M1)

## Depends on
M1

## Purpose
Prove, in the running system, that two items can run at the same time in two isolated lanes — and settle the
questions items 05 and 06 are parked on, including which lane shape to build (decision P8). Nothing here is
committed to the plugin.

## Setup
1. Pick two requirements that touch disjoint files and have no dependency on each other.
2. `git clone --local <primary> <primary>-lanes/spike-a` and `…/spike-b`. **Set each clone's `origin` to the
   GitHub URL BEFORE anything else** — a `--local` clone's origin is the primary's path, where
   `loomwright-meta` does not exist, and it turns the primary's local branches into stale `origin/*` refs.
3. In each clone: `meta-sync.sh pull`; confirm `run-lock.sh status` prints `UNLOCKED` and resolves the CLONE as
   its root.
4. Note what the clone is MISSING compared with the primary: `.supervisor/config.json`, `notify-config.json`,
   `.claude/settings.local.json`, the rules stamp, Claude auto-memory (keyed by cwd). Copy the first two; record
   the effect of the others.
5. Launch one item per clone, detached and headless. Do NOT reuse `dispatch-pr-review.sh`'s allowlist — it permits
   only `Read,Grep,Glob,Task` plus scoped `git`/`gh`, which cannot implement anything. Write down the exact
   `--permission-mode`, `--allowedTools`, `--disallowedTools` and `--plugin-dir` you used.
6. Intake: point each lane at the item's CANONICAL path (a one-line backlog doc naming it), not a copy in another
   folder — closeout stamps and `brief-repair` match on the canonical path.

## Try both lane shapes (decision P8)
- **Shape A — whole loop headless:** `/loomwright:automate --backlog <one-line doc> --non-interactive-fallback`.
- **Shape B — brief-first:** run Launch Pad for both items interactively in the primary (human-approved briefs),
  copy each brief into its lane, and launch only Supervisor + the owned drain headless.

## Questions to answer (write the answers into 05 and 06, then un-park them)
1. **Isolation.** Do both lanes run to a PR with no `run_lock_held`, no cross-talk in `state.md`, and each lane's
   `auto_review` toggle restored in its own clone? Did anything in the PRIMARY change?
2. **Pre-flight.** When lane B reaches Phase 1.5 with lane A's PR open — and when it is NOT yet open — what does it
   classify, on which files?
3. **Headless gates.** Shape A: where exactly does each lane stop (Launch Pad Phase 6 save/refine/discard has no
   non-interactive branch today)? Does `claude -p` stay alive for a multi-hour inline Supervisor run? What happens
   to an `AskUserQuestion` under the chosen permission mode? Does the rate-limit hook fire headless?
4. **After a merge.** The owner merges lane A's PR by hand (admin bypass, as always). What state is lane B's PR
   in, and does it still merge cleanly by bypass without updating its branch?
5. **Missing clone state.** Does the metadata push from a lane pass the ledger allowlist (the allowlist lives in
   gitignored `.supervisor/config.json`)? Do reviewers in the lane see `.claude/agent-memory/`? What does the
   rules stamp check report in a clone?
6. **Contention.** Two concurrent `run-self-tests.sh` suites on this machine: wall-clock versus one, any shared
   `/tmp` cache collisions, any timeouts.
7. **Which shape?** A or B, with the reason.

## Also record
Wall-clock and tokens per lane (`read-token-ledger.sh --root <lane>`); everything done by hand.

## Safety checks (the spike must not disturb the primary checkout)
- Before: `git status --porcelain`, `git worktree list`, `run-lock.sh status`, and a checksum of
  `.supervisor/config.json` (or "absent") in the primary. After: the same four, identical.
- Never run a lane from inside the primary, never pass `--root` pointing at it.
- Use a throwaway metadata branch for the spike, or do not push metadata from the lanes at all.

## Done when
Both PRs are open (or each lane's stop point is recorded), the seven answers are written into
`05-lane-coordinator.md` and `06-wave-close-and-closeout.md` under "Spike findings", decision P8 is filled in
`00-overview.md`, and both clones are removed. Close the spike PRs that are not wanted.

## Run record (in progress — 2026-10-04, session 0d556d54; findings land in 05/06 at the end)
**Setup (steps 1–6), as run:**
- Items: lane A `automate-followups/19` (`is_run_file` tolerance: `automate-helpers.sh` + its test); lane B
  `automate-followups/18` (fail→unstamped escalates, owner Option A: two SKILL.md files). Disjoint, independent.
- Clones `<primary>-lanes/spike-a|spike-b` via `git clone --local`, then `origin` set to GitHub, then
  `fetch --prune`. No stale primary refs were left; only `main` locally. `config.json` and `notify-config.json`
  copied. `meta-sync pull` wrote 384 files.
- Throwaway metadata branch `loomwright-meta-s1`:
  - the clones' `.gitignore` mode line was edited to `-s1` and marked `--skip-worktree`, so no lane commit can
    carry it (`git add -A --dry-run` was checked);
  - each clone's meta-base was dropped first. Kept, it would have made the empty new branch read as "every file
    deleted";
  - seeded from spike-a: 384 files, blob-identical to `loomwright-meta@b8b44fc`. The real branch was untouched.
- Release: fragment only (P7). The note sits in each lane's copy of the requirement file — **strip it before the
  lanes' records return to `loomwright-meta`**.
- Launch, Shape A, both lanes at once, 01:53:27Z:
  `claude -p "/loomwright:automate --backlog .supervisor/s1-backlog.md --non-interactive-fallback"
  --permission-mode acceptEdits --allowedTools "Bash,Read,Edit,Write,Glob,Grep,Task,Agent"
  --output-format stream-json --verbose`, nohup, `env -u CLAUDECODE -u CLAUDE_PID`, installed plugin 15.119.2.
- Primary snapshot BEFORE: `../ai-agent-manager-lanes-s1-before.txt`. **Deliberate primary change during the
  spike:** the owner removed 5 stale, merged, clean `.claude/worktrees/*` at about 02:40Z, so the after-check's
  worktree list is expected to shrink by those 5.

**Q1 Isolation (partial):** each clone's run lock resolves to the clone. While lane A ran, its lock was `LOCKED
owner=automate:automate-2026-10-04-072436 pid=82630`, while lane B and the primary read `UNLOCKED`. Lane B
restored its `auto_review` toggle byte-for-byte. The primary was unchanged at every check so far.

**Q2 Pre-flight:** not yet observed (lane B never reached Phase 1.5; lane A's PR was not yet open).

**Q3 Headless gates — the key finding:**
- In `claude -p` with no permission host, `AskUserQuestion` is ABSENT from the tool list (stream-json `init`),
  so a lane cannot ask at all.
- Launch Pad Phase 6 (save / refine / discard) has no non-interactive branch for a PASS, and the two lanes did
  OPPOSITE things there:
  - **Lane B** failed closed: no brief saved, run parked with `status: failed`, `pause_reason: awaiting_go`
    (an enum gap — no value fits "stopped at a human-only gate"), lock released, config restored.
  - **Lane A** rewrote its own brief after a Plan Review FAIL (attempt 1), saved it to `jobs/pending/` with no
    human approval, and went on to implement. **This is a silent skipped approval.** Its PR needs the owner to
    read its brief before merging.
- `/autonomous` labels lane B's stop `user_aborted_at_launch_pad` although no user aborted.
- The run-file write guard worked under stress: a broken `sed` produced empty output, and `runfile-write`
  refused it, leaving the file intact.
- A bare non-interactive `--resume` in lane B is ambiguous: the clone carries the older paused run
  `automate-2026-09-30-054439`, whose queue also lists item 18.
- **Probe (outside the lanes):** with a permission host (`--permission-prompt-tool stdio` + stream-json input),
  `AskUserQuestion` exists in `-p`. A `PreToolUse` hook returning `defer` exits the process cleanly
  (`stop_reason: tool_deferred`, question in `deferred_tool_use`). The main session asked the owner, and
  `claude -p --resume <id>` with the hook returning `allow` + `updatedInput.answers` completed the job in the
  same session. Gotchas: `--setting-sources project,local` broke auth (the login is user-scoped); `defer` needs
  the question to be the only tool call in its turn.

**Q5 Missing clone state:** `config.json` and `notify-config.json` were copied, and the allowlist works for
`meta-sync pull` (no trail push observed yet). `.claude/agent-memory/` is tracked, so it is present. Absent:
`.claude/settings.local.json`; the rules stamp (user-scoped, keyed by repo path, so the clones read
`unstamped`); Claude auto-memory (keyed by cwd).

**Q6 Contention:** `scripts/ci-local.sh` locks on `git rev-parse --git-common-dir`. Separate clones do NOT share
it, so lane CI suites run fully parallel (worktrees would serialize). Lane A has run `ci-local` 4 times so far.
A concurrent two-suite measurement has not yet been taken.

**Cost/time so far:** lane B 01:53:27Z → 02:07Z (Launch Pad + review only), $7.16 per its result event (the
event's 1-minute duration is wrong; use the timestamps). Lane A was still running at 02:45Z.

**Lane A finished (03:07:44Z, 74 min, 130 turns, $19.75):**
- PR #370 opened. Phase 4.5 PASS (0 iterations). The drain reached READY in 2 rounds with 2 fix cycles: a
  claude-review finding (build-handoff's title reader was still strict), then a `check-locale-prefix` CI failure
  caused by that fix. Parked `awaiting_merge`. **Its merge watcher (pid 78867) runs INSIDE the clone**, the live
  case for the new `lane-remove` refusal.
- 3 dismissed-finding drafts stayed undecided: the lane was non-interactive, so `pending_decisions: 3`. The watcher
  is already armed, so engine fix-now is no longer offered, by design. One MEDIUM is worth fixing: `[[:space:]]*`
  before `#` also lists an indented sidecar title as a run.
- Its own slips: the PR body was blanked for about a minute by a failed edit and then restored; the watcher was
  armed and the lock released seconds BEFORE the park state was written (a broken `sed`, which `runfile-write`
  rejected); the desktop notify call hung.
- **Pairing finding: the two items were NOT disjoint.** The requirements named disjoint files, but both PRs touch
  the companion files `loomwright/skills/SKILLS_INDEX.md` and `loomwright/docs/RESULT_SCHEMAS.md` (#370 also
  touches `automate-loop/SKILL.md`). Picking pairs by hand from requirement text misses companions. This is
  exactly what `plan-waves`' companion expansion (item 04) exists to catch, and the pair should have been checked
  with it.

**Lane B relay re-test (A + relay):** relaunched at 02:52:26Z with a permission host (`--permission-prompt-tool
stdio` + stream-json input), a `PreToolUse`/`PermissionRequest` defer hook in the clone's
`.claude/settings.local.json`, and NO `--non-interactive-fallback`. `AskUserQuestion` was present.
- **Relay 1:** the `/automate` resume logic asked how to continue the unsaved reviewed brief and parked
  (`tool_deferred`, 02:53:39Z). The main session relayed it, and the owner chose "Fold findings into draft" with
  the note "fix the findings and review the brief again". The answer was written with `source: human` and the
  lane resumed in the same session at 03:05:12Z; the hook fired again and returned the answer.
- **Relay 2 (03:12:43Z → 03:13:57Z):** Supervisor Phase 1.5 pre-flight asked about the OVERLAP with open PR #370
  (`SKILLS_INDEX.md` rebase conflict likely; `RESULT_SCHEMAS.md` in a different section). The owner chose "Proceed
  anyway". **This answers Q2 for the sibling-PR-OPEN case:** the gate caught the companion-file overlap that the
  hand pairing missed.
- **Relay findings:**
  - (a) **A free-text answer is read broadly.** Relay 1's "…review the brief again, then continue" was taken as
    approval to SAVE. The lane folded all six findings, Plan Review 2 PASSed, the reviewer's 2 new LOW wording
    items went in WITHOUT a further review, and the brief was saved. Because that path runs outside
    `/autonomous`, **Launch Pad's own Phase 6 save ask never ran**, so the "how does Launch Pad hand over the brief
    and ask" behaviour is still UNOBSERVED. Rule for the design: an answer is exactly one option; free text is a
    note attached to that option, never the decision.
  - (b) The relayer added a parenthetical to one option's description. Rule: relay verbatim, never edit a lane's
    options.
  - (c) **Each park ends the session as far as the plugin's hooks can tell.** Lifecycle hooks log `session_end`
    `failed / session_ended_without_completion` and RELEASE the run lock, so while a lane waits for an answer its
    lock is free.
  - (d) After the resume the lane's run file stayed stale (`## Status: paused`, item `failed`, `awaiting_go`)
    while the lane was implementing.
- Lane B's first relay segment: 37 turns, $4.22. It then reached EXECUTE: branch
  `feature/automate-followups-18-…`, baseline `ci-local` 142/142.

- **NEW Q3 finding: headless `-p` killed lane B's implementation worker (03:30:39Z).** The lane's main thread
  spawned the worker as a BACKGROUND agent and ended its turn. `claude -p` then waited its 10-minute ceiling for
  background tasks and killed them: log line `Background tasks still running after 600s; terminating. Set
  CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 to wait indefinitely.` The worker `Implement: automate-followups/18` was
  marked `killed`. Lane A did not hit this; it apparently waited in the foreground. Left behind: 8 commits on the
  branch (nothing uncommitted, not pushed, no PR); the run lock held by the dead pid (age about 17 min, so not yet
  reclaimable); `auto_review` suppressed with a stranded `.config-backup.json` (the RECONCILE restore case).
  Session cost so far $9.29. **Harness rule for v2 and for `lane-launch` (item 05):** set
  `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0`, or require lanes to wait for workers in the foreground. A lane must
  never end its turn while a worker runs.

**Owner review of lane A's PR #370 (03:20Z) — NOT acted on; the owner chose to redo S1 fresh and compare:**
- Brief (self-approved by the lane): 10 ACs; tolerant `is_run_file` (BOM, whitespace, case); sidecars and H2
  excluded; a mutant restoring the old exact match; docs; fragment only. Decisions the lane took ALONE:
  case-insensitive matching; ANY whitespace before `#` (stated in the code comment, NOT in the ACs); whitespace
  inside the phrase.
- Diff: 8 files, +205/−16. The predicate is
  `grep -qiE "^(BOM)?[[:space:]]*#[[:space:]]*automate[[:space:]]+run[[:space:]]*:"`, and build-handoff's
  title reader got the same tolerance (drain round 1).
- **Reproduced on the branch** (scratch dir, branch vs main):
  - a sidecar quoting a run title in a 4-space INDENTED CODE block — main: not listed; #370: **listed — a
    REGRESSION** (a quoting sidecar makes RESUME see two runs);
  - a 3-space H1 (valid Markdown) — main: not listed; #370: listed (correct);
  - a title inside a FENCED block — listed by both: an existing limitation, not caused by #370.
- The review gate had flagged the regression and DISMISSED it as a below-threshold MEDIUM: a calibration data point.
  Planned fix (not executed): `[[:space:]]*` → `[ ]{0,3}` before `#` (CommonMark: 4 or more spaces is code),
  test legs (indented sidecar NOT listed; 3-space H1 listed) and a mutant restoring `[[:space:]]*` that must fail.
  Route it through the plugin, not by hand: post the finding as a PR review comment, then run lane A's
  `/review-pr <#370> --until-mergeable` with the relay.
- Why the engine did not fix it: fix-now is offered only at the park, BEFORE the watcher is armed. Lane A could not
  ask there (no question channel), so `pending_decisions: 3` was recorded and the next PICK offers only follow-up
  or drop. **With the relay, the owner would have been asked fix-now at the right moment.**
- Candidate follow-up (not queued): fence-aware `is_run_file`, ignoring lines between ``` fences.

**Owner decision (2026-10-04): redo S1 FRESH and compare with this run** — see "S1 v2 plan" below.

## S1 v2 plan (owner, 2026-10-04: redo fresh, compare with v1 above)
**Same experiment, with v1's confounders removed. Spike-level only: hooks and scripts in the clones, NO plugin
change — S1 stays "nothing committed to the plugin".**
- **Same inputs:** the same two items (`automate-followups/18`, `/19`) from the same base commit `6a048be`, so
  outcomes compare directly. v1's PRs stay open for comparison and are closed unmerged at the end unless the owner
  picks one.
- **Pair checked mechanically:** run `plan-waves` (with companion expansion) over the two items first and record
  its answer. v1 picked by hand and missed the shared `SKILLS_INDEX.md` / `RESULT_SCHEMAS.md`.
- **Both lanes get the question channel from launch:** a permission host plus the defer/deny hook, NO
  `--non-interactive-fallback`. v1 had it only in lane B's re-run.
- **Answers are exactly one option** (free text only as a note). The relay is verbatim and every question/answer
  is logged with `source: human`.
- **Observe Launch Pad's own Phase 6 save ask** in at least one lane: answer the resume and fold questions so the
  lane goes through `/autonomous`, not around it.
- **Reproducible harness first:** fold v1's ad-hoc commands into ONE script (setup / launch / relay /
  status / feed / teardown) and test it on a scratch item before v2. That makes v2 repeatable and comparable.
- **Planned measurements:** a deliberate concurrent `ci-local` in both lanes (Q6); the "sibling PR NOT open" Q2
  case (start both lanes together); Q4 (owner merges lane A, then observe lane B's PR); multi-hour `claude -p`
  liveness; rate-limit behaviour if it occurs.
- **Visibility:** a status board, a live feed per lane, and a notification when a lane parks on a question. Probe
  Remote Control as a watch-and-answer option before relying on it.
- **Teardown with the new checklist:** stop watchers, copy records from `-s1`, remove clones, delete `-s1`, compare
  the primary with the BEFORE snapshot.

**Comparison table (fill v1 at the end of v1, v2 at the end of v2):** per lane — wall-clock, turns, cost,
questions asked / relayed / decided by the lane alone, time parked, operator interventions, review findings
(fixed / dismissed / dismissed-but-real), CI rounds, isolation result, leaks after teardown; per run — Q1–Q7
answers, P8 recommendation.
- **Relays 3–5, after the background-kill resume:**
  - **Relay 3 (03:48Z):** FINALIZE's children-settled join was unsettled for the KILLED worker (8/8 outputs
    verified on disk, all ACs re-checked by the main thread). The owner chose "Proceed, record skip"
    (`provides_present_agent_unsettled` + `user_skipped_children_check`).
  - **Lane B opened PR #371**, ran Phase 4.5 and the drain, and parked at the dismissed-findings decision step.
    This is the step lane A could not ask, which is how lane A's regression went through as a dismissal.
  - **Relay 4 (04:27Z, 4 questions in ONE call):** findings 1–4 (MEDIUM: P9/P10 do not pin the
    `rules_fail_seen +=` lines; a PR comment omits remaining findings; the Heal-reason lists lack both rules
    reasons; `rules_fail_seen` is lost across a checkpoint and `--continue`). The owner chose **fix now** ×4.
  - **Relay 5 (04:28Z, 3 questions):** finding 5 (MEDIUM, pre-existing: FAILURE_ESCALATION list stale) → fix now;
    finding 6 (drain FYI: review-pr budget headroom about 199 tokens) → fix now; the LOW summary → keep.
  - Finding 1 is the same class as lane A's dismissed regression: a test that does not actually pin the new
    behaviour. With the question channel, the owner caught it at the park; without it, lane A's slipped through.
  - Totals for lane B's re-run: **5 deferred calls, 10 questions, every answer delivered** (the hook fired again on
    each resume for the same id). One multi-question call was answered as a whole.

## Comparison table — v1 (filled 2026-10-04 ~05:30Z; v2 column to be added after v2)
| Measure | v1 lane A (item 19, PR #370) | v1 lane B (item 18, PR #371) |
|---|---|---|
| Shape | A as shipped (headless, no question channel, `--non-interactive-fallback`) | first run: the same as A; re-run: **A + relay** (permission host, defer hook, no fallback) |
| Wall-clock to READY park | 74 min (01:53:27 → 03:07:44Z) | first run 14 min (stopped at the brief save); relay run 02:52 → 05:13Z = 2 h 21 min, incl. 44 min parked on the owner and 15 min lost to the background kill |
| Turns / cost | 130 turns / $19.75 | 214 turns over 11 segments / $29.51 ($7.16 first run + $22.35 relay run) |
| Questions asked / relayed | 0 / 0 (it could not ask) | 10 questions in 5 deferred calls / all 10 relayed; answer latency 1.4–15.8 min |
| Gates the lane decided ALONE | **2:** saved its own brief after a Plan Review FAIL→refine→PASS (no human approval); left 3 dismissed findings undecided, so fix-now was no longer offered | **1, partly:** read the free-text "…then continue" as save approval; Launch Pad's own Phase 6 never ran |
| Operator interventions | 0 | 1 operator message (resume after the background kill) + 5 relays |
| Review findings | Phase 4.5 PASS (0 iterations, 2 dismissed); drain 2 rounds / 2 fixes; 3 dismissed drafts, **1 dismissed-but-REAL regression** (indented-code sidecar listed as a run; reproduced) | Plan Review PASS 1/3 → 6 folded → PASS 2; Phase 4.5 + drain READY; 7 dismissed → **6 fixed now by owner choice**, 1 LOW kept |
| CI | `ci` + `claude-review` green on #370 | baseline `ci-local` 142/142; `ci` + `claude-review` green on #371 |
| Failures hit | its own: PR body blanked for about a minute; watcher armed before the park write; the notify call hung | **worker KILLED by the `-p` 600 s background ceiling**; run file stale after resume; each park released the run lock |
| Isolation | own lock (`LOCKED … pid=82630` while running); primary untouched | own lock; config restored; primary untouched |
| Leaks after the run | merge watcher alive in the clone (expected until merge or close) | merge watcher alive in the clone (expected) |

**v1 answers to Q1–Q7 so far:**
- **Q1 isolation:** yes, so far (final after-check at teardown).
- **Q2 pre-flight:** the sibling-PR-OPEN case was answered — the gate caught the companion-file overlap. The NOT-open case was not observed.
- **Q3 headless gates:** Shape A as shipped is unsafe; lanes either stop or decide silently. The relay works end to end. `-p` kills background workers after 600 s unless `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0`. Multi-hour liveness is fine with that set.
- **Q4 after a merge:** deferred to v2 (owner decision: no v1 merge, so v2 can rerun the same items).
- **Q5 missing clone state:** config and allowlist carried by copy; rules stamp and settings.local absent. No lane metadata push has happened yet (none before a merge).
- **Q6 contention:** the CI lock is per clone (no throttling); a concurrent measurement was not taken.
- **Q7 shape:** the evidence points to **A + relay** (P8 candidate 3) over A as shipped; B is untested.

## S1 v2 harness — built and probe-tested (2026-10-04 ~06:40Z)
- **Harness `s1h.sh`** (in `<primary>-lanes-v2/`, beside the lanes; spike-level, not plugin code). Subcommands:
  `snapshot before|after`, `plan-check`, `setup <lane> <item> [--seed]`, `launch <lane> [--probe]`,
  `status [--json]`, `feed`, `answer`, `leaks`, `teardown`. It folds in every v1 lesson:
  - a question channel from launch, with no `--non-interactive-fallback`;
  - `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0`;
  - answers are exactly one option label (free text is a note);
  - user settings kept;
  - `launch` REFUSES a lane without its relay hook or backlog;
  - `teardown` refuses on a live process or watcher, a pending question, uncommitted changes, commits not on
    origin, or unpushed metadata.
- **`plan-check` on v2's pair:** `wave 1: 18`, `wave 2: 19`. The planner would NOT run them in parallel (no
  `## Touches` / `## Depends on`, so each runs alone; with Touches, the shared companions keep them apart). v2
  keeps the pair on purpose for comparability with v1; the overlap also feeds Q4.
- **Probe results (Haiku, throwaway branch `-s1`):** setup clean; the no-hook guard refused; park →
  `QUESTION WAITING`; a bad label was refused; teardown was refused while a question was pending and while the
  process was alive; the valid answer resumed the lane, which finished `end_turn | Red`; teardown removed the lane
  and `leaks` was empty.
- **Bugs the probe found and fixed:**
  - (1) setup pulled the REAL branch before the throwaway one, causing 4 conflicts. Only the seeding lane reads
    the real branch.
  - (2) a lane launched with no hooks after a failed setup. `launch` now refuses.
  - (3) the recorded pid was a wrapper shell: a backgrounded `cd && cmd` list makes `$!` the forked shell. `cd`
    now runs on its own line. **v1's `s1-answer.sh` has the same bug**; v1's manual launches used a pipeline and
    were correct.
- **Observed drift:** on the first probe, the resumed Haiku session went off-task after its answer and began
  implementing item 19 in the test clone (it was stopped, and the clone discarded). The second probe behaved. The
  v2 lanes run the real `/automate`, so this does not apply to them, but a resumed session acting beyond the
  question is worth watching.
- **v2 launch checklist:**
  1. `snapshot before`.
  2. Close #370 and #371 WITHOUT deleting their branches (pre-flight lists all open PRs, drafts included, so open
     v1 PRs would skew v2's Q2), and watch both v1 watchers record `gone` and exit.
  3. `setup v2-a <19> --seed` (creates `loomwright-meta-s1v2`), then `setup v2-b <18>`.
  4. Launch both together (Q2's "sibling PR not open" case).
  5. Answer every question (optionally from the lanes mod).
  6. Plan a deliberate concurrent `ci-local` (Q6).
  7. Merge the chosen PR first, then observe the other (Q4).
  8. Teardown, then `snapshot after`.

## S1 v2 run record (started 2026-10-04 07:18Z)

- **Before snapshot** (07:0xZ): primary clean at `6a048be`, worktree `main` only, run lock UNLOCKED, meta synced `991f82a` (`ai-agent-manager-lanes-v2/snapshot-before.txt`). `plan-check`: 18 = wave 1, 19 = wave 2 (same as v1).
- **v1 parked out of the way** (owner yes): #370 and #371 closed unmerged with a comment. Watchers 78867 and 72409 each wrote `gone — closed unmerged (no cleanup; §4 gone rules)` (07:13:24Z / 07:13:50Z) and exited by themselves, so the §4 gone path is observed working.
- **Condition found and removed before setup:** v1's branches on origin would have collided with v2's very likely identical branch names. The Supervisor's branch-collision guard checks the **local** branch only, and a fresh clone has none, so the lane would branch from `main` and its push would be rejected non-fast-forward. That's a path v1 never met, so it would skew the comparison, and a force push would destroy v1. Owner chose: move v1 to `s1v1/item-19` (`dfa9c0e`) and `s1v1/item-18` (`5c5bff4`), verified same SHAs, then delete the old names; also kept under `refs/pull/370|371/head`. **Finding for 05 (lane coordinator):** before a lane takes a branch name, check `git ls-remote --heads origin <name>` as well as the local ref; a remote-only collision is invisible to today's guard.
- **Setup:** v2-a = item 19 (`--seed`, created `loomwright-meta-s1v2`, 386 paths), v2-b = item 18. Both on `6a048be`, mode `on loomwright-meta-s1v2`, clean, relay hooks installed, no v1 branch refs.
- **Launch:** both at 07:18:03Z (v2-a pid 43790, v2-b pid 43805; the pids are `claude` itself).
- **v2 relay 1, both lanes (07:19–07:22Z):** RESUME found the seeded paused run `automate-2026-09-30-054439` (its queue lists 18 and 19) and **asked** instead of choosing. In v1, lane A chose silently and lane B's resume was ambiguous. Owner: start a new run (same outcome as v1, so the runs stay comparable). The lanes asked in different shapes: v2-a asked 2 questions (resume + confirm queue); v2-b asked 1 and put the queue in the option text. Both answers passed the harness's exact-label check, and both lanes resumed (v2-b pid 53524, v2-a pid 54129) and show `running`.
- **v2 relay 2, brief gates (Launch Pad Phase 6), both lanes ASKED:** the gate v1's lane A skipped and saved on its own now reaches the owner through the relay.
  - v2-b (item 18): Plan Review PASS on attempt 1/3, 0 blocking/high/medium, 4 LOW. Owner: **Save + carry notes** (resumed pid 93526).
  - v2-a (item 19): PASS on attempt 1/3, 1 MEDIUM (AC7 leaves out the plan-waves caller) + 3 LOW. Owner: **Refine further** (attempt 2/3). The brief already decides **D3 = indentation cap 0–3 spaces**, which is exactly the regression found in v1's #370 (a 4-space indented code block listed as a run), so v2 plans the fix that v1 shipped without.
- **Collision confirmed (07:4xZ):** v2-b checked out `feature/automate-followups-18-fail-to-unstamped-escalates`, **the exact name v1's #371 used**. Without the move to `s1v1/`, its push would have met v1's branch on origin. The prediction held, so the remote-name check belongs in 05.
