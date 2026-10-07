# 21 — Fleet operations: wave close + split closeout, and policy answers for routine lane questions

## Status: pending

## Merged from (2026-10-07, owner decision relayed by S3 session 2216aefd: merge the serialized tail into fewer, larger items — every remaining item except pa/14 shares `automate-loop/SKILL.md` with every other, so separate items buy no parallelism and cost a wave each)
- Part A: `parallel-automate/06-wave-close-and-closeout.md` — 06 — Wave close: one release bump per wave + split closeout (no extra PR, no merge train)
- Part B: `parallel-automate/12-lane-policy-answers.md` — 12 — Policy answers for routine lane questions, so the owner answers decisions, not formalities

The originals are parked with a pointer here. Their text is kept below VERBATIM as parts (headings
demoted, their Status / Depends on / Touches folded into this file's own sections). Nothing was paraphrased.
Their changelog.d fragment names are replaced by this item's one fragment.

## Depends on
01-version-bump-script.md
05-lane-coordinator.md

## Touches
loomwright/scripts/automate-lanes.sh
loomwright/scripts/automate-trail.sh
loomwright/scripts/test-automate-lanes.sh
loomwright/scripts/test-automate-trail.sh
loomwright/skills/automate-loop/SKILL.md
loomwright/skills/SKILLS_INDEX.md
loomwright/commands/automate.md
loomwright/docs/result-schemas/automate-run.md
loomwright/scripts/automate-merge-watch.sh
loomwright/scripts/lane-policy.sh
loomwright/scripts/test-lane-policy.sh
loomwright/docs/LANE_GATES.md
changelog.d/21-fleet-operations.md

## Goal
One change set for running a wave of lanes after item 05: the wave closes on a wave branch with one release bump and a split closeout (A), and routine lane questions are removed at the source or pre-answered by an owner-stamped per-wave policy, so the owner answers decisions, not formalities (B, amended 2026-10-07 below).

## Acceptance criteria
- Every part's own acceptance criteria hold, on one branch and one PR.

## Validation (must pass before merge)
1. Baseline full loop once for the merged branch, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Every part's own Validation steps, labelled by part in the PR body. A part with no Validation section is
   checked by running its acceptance criteria, and the PR body says so.
3. Any "Running system" step a part names is run, or listed under "Not verified" with the reason.
4. Rollback: `git revert`.

## Amended 2026-10-07 — Part B (policy answers): remove pointless questions at the source, and a per-wave policy (owner, relayed by S3 session 2216aefd)
Folded here, not into Part B's verbatim text. Part B's design stays: an exact-lookup policy the owner stamps,
human-only classes, no model-judged answers.
1. **Remove pointless questions at the source, not just auto-answer them.** Example: the 1-item queue confirm when
   the owner launched exactly that list (`--backlog` / a lane backlog of one item the owner chose). Where the engine
   can show the answer is already given by the owner's own invocation, it does not ask; the run file records why
   (`## Progress`: `skipped <gate_id>: <reason>`). A gate that is removed never needs a policy entry.
2. **A per-wave policy, settled during wave planning.** Before launch the owner answers the predictable routine
   questions ONCE for all lanes of the wave — start a new run over a stale paused run, the queue confirm, save the
   brief on a 0-issue Plan Review PASS, keep or drop LOW summaries — and that answer set is the wave's stamped policy
   (Part B Scope 3's store and valve, scoped to the wave's run id). Anything outside it still reaches the owner.
3. **S3 evidence:** wave 1 had 29 relayed questions and wave 2 about 40, roughly a third routine. Wave 3 (2026-10-07):
   all four lanes asked "Start new run?" over the same paused run `automate-2026-09-30-054439` (12th time across S3),
   three asked the 1-item queue confirm and **s3-k skipped it** — the same gate fires inconsistently, so it cannot be
   pre-answered reliably until it is pinned or removed.

## Parts

### Part A — 06 — Wave close: one release bump per wave + split closeout (no extra PR, no merge train)

#### Amended 2026-10-06 — wave close on a wave branch, no release lane (S3 wave 1 evidence; owner decisions 2026-10-05/06)
S3 wave 1 integrated four lanes on `wave/s3w1` (operator-run S3 §"Integration method"): each lane PR's exact parked
head merged `--no-ff` in planner order, `ci-local`, then `bump-version.sh` as the wave branch's LAST commit, ONE PR
into `main`, merged by the owner with "Create a merge commit". GitHub marked all four lane PRs merged and every lane's
merge watcher closed out by itself (#397, 2026-10-06). So:
- **The release lane (Scope Step B: merge `origin/main` into the last lane's PR, bump there) is superseded.** The bump
  is the wave branch's last commit; no lane PR carries it and no lane PR is updated from `main`.
- **Lane PRs are never merged one by one.** Conflict repair is part of integration (Part S below, from item 13).
- Closeout (Scope 6/7), the learning line (Scope 10) and the fleet-closeout backstop are unchanged.
- The text below that describes the release lane is kept for history. The brief must re-derive the steps from
  this amendment, and the tests that pin release-lane behaviour change with it.
- Open owner decision: whether the coordinator may run the integration merges into `wave/*` (Part S item 4).

#### Problem
After item 05 a wave ends with N READY PRs parked `ready_for_release`. Three things are still unsolved:
- **The version.** Lanes carry changelog fragments only (decision P7); something must fold them and bump once.
- **Closeout.** It was written for one checkout (brief repair, worktree cleanup, sync `main`, branch removal,
  stamp, check-off, trail). In N lanes it would never touch the primary or the parent queue and would leave the
  lane clones behind.
- **What NOT to build.** An earlier draft had a merge train that synced, bumped, re-drained and gated each lane,
  waiting for an owner approval. That premise is false here: the last 25 merged PRs show `REVIEW_REQUIRED` with
  zero reviews — the owner merges by admin bypass, and an author cannot approve their own PR. A bypass merge also
  does not need the branch to be up to date, so file-disjoint lane PRs need no train at all.

#### Goal
A wave closes with at most ONE extra commit (the release bump on the release lane), the owner merges the PRs by
hand as today, and each merge is followed by a closeout that opens no PR and leaves no lane behind. No new merge
path, no new drain category, no push onto a PR that is waiting for a merge.

#### Scope
1. **Wave close is stepwise and resumable** — each `/automate --resume` performs the next step and stops; nothing
   waits inside a session. Every step names its executor.
2. **Step A — release the ordinary lanes (bash, coordinator).** Every `ready_for_release` lane EXCEPT the last in
   planner order becomes `awaiting_merge`: park state written in the lane's run file by the lane's own resumed
   session (the coordinator does not write into a lane — it launches `lane-launch --resume` for that), merge
   watcher armed, notify "ready to merge". These PRs carry a fragment and no version-file change.
3. **Step B — the release lane (headless lane session).** The last lane in planner order stays
   `ready_for_release` until every sibling is merged, skipped, abandoned or parked `escalated` (a parked sibling is
   excluded, not waited for). Then, on the owner's `--resume`, in the lane:
   a. merge `origin/main` into the PR branch (conflict ⇒ park the lane `escalated`; the wave's fragments stay on
      `main` for the next bump);
   b. run the project's **release command** (below) — it folds every fragment now on the branch and bumps once;
   c. push; wait for required checks;
   d. park `awaiting_merge`, arm the watcher, notify.
   No extra owned drain is run for this commit: the push happens BEFORE the lane is ever `awaiting_merge`, the
   diff is a merge plus the three version files, CI and the static CI lens run on it, and the "one owned drain per
   pass" invariant stays intact. If the release command is unavailable, skip b and say so in `## Progress`.
4. **Release command = tracked project config, behind the human-stamp valve.** The shipped plugin must not call
   this repo's `scripts/bump-version.sh`. The command is read from tracked project config (same store and same
   provenance rule `rules-check.sh` applies to a rule's `check` command: executed unattended only when
   human-stamped; unstamped / absent ⇒ not run, recorded, never a failure). This repo's value is
   `bash scripts/bump-version.sh`. Read `rules-check.sh` and `skills/rules/SKILL.md` §8 before designing — do not
   invent a second valve.
5. **A wave of one item** never enters this code: the item's own PR bumps as its last commit (item 01) and parks
   `awaiting_merge` as today.
6. **Lane closeout** (inside the lane, evidence-gated on `reconcile-item` = `merged`, idempotent, fail-SAFE; run
   by the lane's merge watcher or the lane's resume, as today): brief repair → stamp the requirement → check off
   the lane run file → write `## Status: done` to it → `meta-sync.sh push --paths-from <evidence-gated list>`.
   No trail PR; no "sync main" (a lane is discarded, not reused). A failed push sets item 03's failure marker.
7. **Fleet closeout** (coordinator, primary, same evidence gate, on `--resume`): `meta-sync.sh pull` → check off
   the parent `## Queue` + append `## Progress` (one atomic write through `runfile-write` /
   `queue-checkoff`) → `git pull --ff-only` on the primary (it never left `main`) → `lane-remove` (refuses on the
   failure marker). Dismissed-finding drafts arrive via the pull and are asked at the parent's next interactive
   PICK through item 05's parent-aware `dismissed-pending`.
   **Amended 2026-10-03 (owner, from S1): teardown is part of the closeout, not left to the operator.**
   - `lane-remove` runs with item 05's full refusal set: a live watcher or `claude -p`, `awaiting_input`, unpushed
     metadata, the failure marker. A lane closeout runs inside the lane's own merge watcher, so the fleet
     closeout waits for that watcher to EXIT (a resumable step, re-checked on the next `--resume`, never an
     in-session wait) before it removes the lane.
   - When the last lane of the run is removed, remove the then-empty `<primary>-lanes/<run_id>/` directory. A
     non-empty one is refused and its contents are listed.
   - Then print `lane-status --leaks` (item 05 Validation 5) and append its one-line summary to `## Progress`.
     A non-empty leak report is a loud report, not a block: it names each leftover worktree, lane directory or
     live process and the command that clears it.
   - Finally run the plugin-wide sweep in dry-run mode (`automate-followups/22`) and report what it WOULD
     remove. The fleet closeout never removes anything outside this run's lanes.
   **Amended 2026-10-05 (owner, from S2): an `escalated` lane is closed out too.** Today the merge watcher is
   armed only at an `awaiting_merge` park ("an `escalated` park arms none", `automate-loop/SKILL.md` §6
   "Post-merge close-out"), and an escalated item is closed out only by `/automate --resume` RECONCILE. A lane
   exits after it parks and nothing resumes it, so after the owner merges an escalated lane's PR, Scope 6 never
   runs and Scope 7 waits on it forever.
   - **Arm the merge watcher at an `escalated` park as well:** moved 2026-10-06 to `automate-followups/31` (Part "Escalated parks arm the merge watcher" there, verbatim). The fleet-closeout backstop below stays here: only the coordinator can run it.
   - **Fleet closeout backstop:** a lane whose `reconcile-item` is `merged`, whose run file is not
     `## Status: done` and that has no live watcher gets `lane-launch --resume` from the coordinator, so the
     lane's own RECONCILE runs Scope 6 (the coordinator still never writes into a lane, Scope 2). That runs
     before `lane-remove`. **`lane-launch --resume` must send `/loomwright:automate --resume <lane run_id>` with
     the id spelled out, never the lane's launch prompt (`--backlog …`) and never a bare `--resume`.** A lane is a
     clone of the primary, so it holds every earlier unfinished run file (seven in S2's s2-d: six other runs plus
     its own). Without the id the engine either asks which run to resume or starts a new one (item 28's
     stale-runs question), and does not close the parked one out. Validate the targeted form on a real lane
     first: S2 s2-d is that check.
   - Evidence, S2 (2026-10-05): s2-c (PR #381 escalated on a `test-ci-local.sh` case (L) CI-slot flake; the
     rerun was green; merged 03:31Z) and s2-d (PR #386 escalated because `claude-review` settled green 2 min
     after the drain's 1200 s bound). Neither lane had a watcher. The operator ran s2-c's closeout by hand and
     resumed s2-d's lane. Why those escalations happened is `automate-followups/31`.
8. **PR closed unmerged** ⇒ lane is `gone`: no stamp, lane directory kept, human decides.
9. **Next wave** becomes eligible after fleet closeout of the items it depends on and starts only on the owner's
   explicit go (P6). When the last lane of the last wave is closed out, release the primary's
   `automate-lanes:<run_id>` lock.
10. **Learning line.** Unchanged: `learning-emit` runs once at end-of-DRAIN in each lane. Step B runs no drain,
    so no second line can be emitted — pin with a test that a release lane has exactly one line for its PR.
11. **Tests:** two-lane fixture — ordinary lane goes `awaiting_merge` at step A with no version-file change in its
    diff; release lane waits; after the sibling is merged the release lane's diff after step B is exactly the
    merge + the bump, with BOTH fragments folded; a sibling parked `escalated` does not block step B; a merge
    conflict at B.a parks only that lane; unstamped release command ⇒ step b skipped and recorded; closeout opens
    no PR, pushes only evidence-gated paths, removes the lane only after its watcher exited, removes the empty
    `<run_id>` directory last and appends the leak summary; unmerged-closed PR ⇒ no stamp, lane kept; the
    single-item path never enters wave-close code; (the escalated-park watcher test moved to `automate-followups/31`); a merged escalated lane with no watcher is resumed by the fleet-closeout backstop. **Mutation controls:** letting step B run while a sibling is
    still `awaiting_merge` must fail a test; pushing in step B after the lane is already `awaiting_merge` must
    fail a test.

#### Non-goals
Any automatic merge, `gate-eval` call, approval wait, or merge train for parallel runs (decision P1). GitHub
native auto-merge, merge queue, a CI job that merges (P5). Relaxing branch protection or the ruleset. Auto-starting
the next wave.

#### Acceptance criteria
- A two-item wave merges as two PRs total — no trail PR, no release PR — with ONE version bump folding both
  fragments, landed by the release lane.
- `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` resolves to the same five surfaces
  listed in CLAUDE.md §"Failure-Mode Invariants"; `git diff origin/main -- loomwright/scripts/automate-helpers.sh`
  shows no change inside `gate_eval`.
- After the wave: no lane directory and no `<run_id>` parent directory, no live `claude -p` or merge watcher from
  the wave, `lane-status --leaks` empty, the primary on fresh `main`, the parent queue checked off, stamps /
  briefs / lane run files (each `## Status: done`) on `loomwright-meta`.
- Full test loop + root checks green.

#### Validation (must pass before merge)
1. **Baseline:** full loop on base and branch; `<passed>/<total>` and `SKIP` counts for both.
2. **Unchanged path:** `test-automate-trail.sh`'s closeout groups and `test-automate-helpers.sh`'s gate groups
   pass with no edit to existing assertions; then ONE real single-item `/automate` on this repo behaves as before
   (bumped by its own last commit, parked `awaiting_merge`, closeout via push) (the escalated-park watcher change and its PR
   statement moved to `automate-followups/31`).
3. **Invariant checks, pasted:** the two greps in Acceptance criteria; `git grep -nE 'gh pr merge|gate-eval'
   loomwright/scripts/automate-lanes.sh` shows no executable use.
4. **Running system:** a real two-item wave on this repo, owner merging by hand. Paste: the diff stat of the
   ordinary lane's PR (no version file), the release lane's final commit (three version files, both fragments
   gone), `gh pr list --state merged` for the wave (exactly two), `git log --oneline -3 origin/main`,
   `git ls-tree -r --name-only origin/loomwright-meta | grep <run_id>`, and the empty lane directory listing.
5. **A failure this must catch:** the two mutation controls in Scope 11, shown failing.
6. **Rollback:** `git revert` returns parallel runs to item 05's behaviour (every lane `awaiting_merge`, no bump).
   A wave mid-close is finished by hand: merge the remaining PRs, run `scripts/bump-version.sh` in a small PR,
   push metadata from each lane, remove the lanes.

#### Spike findings
Filled 2026-10-04 from S1 Q4. The owner merged #372 (item 18) at 10:17:51Z by hand; the sibling #374 (item 19)
went `BEHIND` but stayed `MERGEABLE` and merged by hand two minutes later with **no branch update**. The two PRs
were a deliberately overlapping pair (separate `plan-waves` waves) sharing one file, `RESULT_SCHEMAS.md`, in
different hunks. **This item's premise holds: no sync is needed for ordinary lanes; step A stands as written.**
Lane closeout ran inside each lane on the watcher's `merged` event within ~12 s (sync `main`, remove the branch,
check off, reconcile `## Current`, watcher exits). One gap: v2-b's closeout metadata push FAILED on the push scrub
(an absolute home path in its brief), so the fleet closeout must surface a lane's `meta-push-failed` marker and
`meta-sync-followups/04` must land before 06 runs. Real `CONFLICTING` siblings are item 13's job.

#### Verified premises (re-check before starting)
- `gh pr list --state merged --limit 25 --json reviewDecision,reviews` on 2026-10-01: 25 × `REVIEW_REQUIRED`,
  zero reviews.
- `gh api repos/vikashruhilgit/loomwright/branches/main/protection`: `strict: true`, required check `ci`, 1
  required review. `gh api repos/vikashruhilgit/loomwright/rulesets`: ruleset 12578391 "PRs & conventional
  commits", active, branch target. Its rule details (stale-review dismissal, last-push approval, thread
  resolution) are from the red-team report — read `gh api …/rulesets/12578391` before relying on them.
- UNVERIFIED: that an admin-bypass merge succeeds on a branch that is behind `main` under `strict: true` — S1
  question 4 is the check, and this item's design depends on it.
- `automate-merge-watch.sh` only detects a merge and runs closeout; its header says it never merges anything.
- Closeout's step order and lock (`automate-loop/SKILL.md` §6 "Post-merge close-out").

#### Status note
Parked until S1 is run and item 05 has merged. Do not start from this file as written.

#### Part S — merged 2026-10-06 from `13-sibling-merge-conflict-repair.md`, REWRITTEN for wave-branch integration
Owner decision 2026-10-06 (fewer, larger items) plus the S3 integration-method decision (2026-10-05: "if it holds,
amend 06 and 13"). It held in S3 wave 1 (see the 2026-10-06 amendment at the top of this file).

##### The rewrite (this is the scope; the original below is kept verbatim for its reasoning and tests)
13's premise was that lane PRs merge into `main` one by one, so a sibling can turn `CONFLICTING` after each merge.
With a wave branch nothing merges into `main` until the wave PR, so that premise no longer applies. What survives:
1. **Conflicts are repaired during wave integration, on the wave branch, never on a lane PR.** Lane heads are
   merged into `wave/<id>` in planner order (`--no-ff`, exact parked head). A textual conflict confined to the
   markers and resolved without changing either side's intent is resolved in that merge commit. Anything larger
   stops integration and goes to the owner with the diff. A lane branch is never rewritten or pushed to by
   integration (13's "no push onto a PR with a live watcher" guard, kept).
2. **A lane the wave branch's CI finds broken** is fixed on its own PR branch (its drain, or a fix the owner
   approves), and its new head is merged into the wave branch again. Identify the lane by testing the wave branch
   at each lane-merge commit.
3. **A red `main` after a wave PR merges pauses the next wave** (13 Scope 4, now per wave PR; no automatic revert).
4. **Open owner decision:** who executes the merges into `wave/*`. In S3 the operator does it by hand. A
   coordinator doing it touches the single-merge-executor invariant (CLAUDE.md §"Failure-Mode Invariants"); do not
   build it without a recorded decision.
5. **Tests (replacing 13 Scope 5):** a fixture wave whose two lanes overlap by one line ⇒ conflict resolved on the
   wave branch, both lane branches untouched; a semantic conflict ⇒ integration stops with the diff; a lane fix ⇒
   new head re-merged, wave CI re-run; a guard test that integration never pushes a lane branch.

##### Original text of 13 (verbatim; superseded where the rewrite above says so)
###### Depends on (folded into this file's own)
05

###### Touches (folded into this file's own)
loomwright/scripts/automate-lanes.sh
loomwright/scripts/test-automate-lanes.sh
loomwright/scripts/automate-merge-watch.sh
loomwright/scripts/test-automate-merge-watch.sh
loomwright/skills/automate-loop/SKILL.md
loomwright/commands/automate.md
loomwright/docs/RESULT_SCHEMAS.md
changelog.d/parallel-automate-13-sibling-merge-conflict-repair.md

##### Part S original — 13 — After each merge, keep the other parked PRs mergeable (conflict repair, not a merge train)
###### Problem
Owner goal: 5–10 lanes at once, so 5–10 PRs parked `awaiting_merge` at the same time. Decisions P1/P5 and item 06
already settle that **no merge train is built**: the owner merges by admin bypass, a bypass merge does not need an
up-to-date branch, and file-disjoint PRs need nothing. (A train was proposed in this session's first draft and
withdrawn for that reason.) What is NOT covered:
- **Textual conflicts.** Wave items are file-disjoint by `Touches`, but a `Touches` list can be incomplete, and
  shared files still exist until item 11 lands. After one merge, a sibling can turn `CONFLICTING`, and a bypass
  merge cannot merge a conflicting PR. Nothing today notices this until the owner tries.
- **A red `main`.** Several bypass merges in a row, each green on its own stale base, can leave `main` red. Nothing
  stops the next merge or tells the owner which merge broke it.
- **The invariant that makes repair delicate:** no push onto a PR that is `awaiting_merge` with a watcher armed
  (overview invariants; skill §6). Repair must first take the PR out of that state.

###### Goal
After every merge in a wave, the coordinator checks the other parked PRs and `main`. A PR that became conflicting
is repaired through a proper handshake (watcher stopped, lane resumed, conflict merged or escalated, CI, re-parked);
a red `main` pauses the wave with the suspect merge named. No new merge path, no push onto an armed PR.

###### Scope
1. **Post-merge sweep** (coordinator, on the merge watcher's `merged` event or the owner's `--resume`): for each
   other lane parked `awaiting_merge`, read GitHub's `mergeable` / `mergeStateStatus`; for `main`, read the latest
   `ci` run on the merge commit.
2. **`CONFLICTING` ⇒ repair handshake:**
   a. stop that lane's merge watcher and record `watch_stopped: sibling_conflict` (the PR is no longer
      `awaiting_merge`; its park state becomes `repairing`);
   b. resume the lane (`lane-launch --resume`) with a single task: merge `origin/main` into the branch;
   c. a conflict confined to the conflict markers and resolved without changing either side's intent ⇒ commit,
      `ci-local` (item 08 slot), push, wait for required checks, re-park `awaiting_merge`, re-arm the watcher,
      notify; anything larger (a semantic clash, a test now failing) ⇒ park `escalated` with the diff, never guess;
   d. the "one owned drain per pass" invariant holds: a pure merge-from-main commit gets CI and the static CI lens,
      not a new drain (item 06 Step B's precedent); a resolution that edits code beyond the markers is escalated.
3. **`BEHIND` but clean ⇒ nothing** (bypass merges do not need it; P1).
4. **`main` red after a merge ⇒ wave pause:** write `wave_paused: main_red after <PR>` to the coordinator run file,
   notify, and mark every parked PR "hold — main is red" in `lane-status` and the pane until `main` is green again.
   No automatic revert.
5. **Tests:** a fixture where merging lane 1 makes lane 2 conflicting ⇒ watcher stopped, lane resumed, clean
   resolution re-parks with a re-armed watcher; a semantic conflict ⇒ `escalated`; `BEHIND`-only ⇒ untouched; a red
   `main` ⇒ wave paused; and a guard test that no push ever happens while a watcher marker for that PR is live.

###### Non-goals
- No merge train, no merge queue, no auto-merge, no CI job with merge authority (P1, P5).
- No automatic revert of a merge that turned `main` red.

###### Acceptance criteria
- In S2, every PR that turned conflicting after a sibling merge is either re-parked green or escalated with its
  diff, and no push was made onto a PR with a live watcher marker.

###### Validation (must pass before merge)
1. **Baseline:** full loop on base and branch, `<passed>/<total>` and `SKIP` counts.
2. **Unchanged path:** a wave whose PRs stay mergeable produces no repair activity (item 06's tests unchanged).
3. **Running system:** two lanes with a deliberate one-line overlap; merge one; paste the sweep, the handshake
   lines and the re-parked PR's checks.
4. **A failure this must catch:** skip step 2a (push while the watcher is armed) ⇒ the guard test fails.
5. **Rollback:** `git revert`; parked PRs keep working as in item 06.

###### Spike findings
(S1 Q4: record #374's `mergeable` / `mergeStateStatus` and what its lane and watcher did after #372 merged.
Items 18 and 19 are in different waves by `plan-waves`, so they are the overlap case on purpose.)

###### Verified premises (re-check before starting)
- `main` protection: 1 approving review, required check `ci`, `strict: true`; repo owner type `User`, so GitHub's
  merge queue is unavailable (`mergeQueue: null`), checked 2026-10-04. P5 rules it out anyway.
- Item 06 §Problem: "A bypass merge also does not need the branch to be up to date, so file-disjoint lane PRs need
  no train at all."

###### Evidence
This session's scale-up analysis (2026-10-04) and S1 Q4 once recorded.

#### Touches re-pointed 2026-10-07 (S3 operator f849e0cc, after pa/11's split — #408, v15.124.0)
- Top-level `## Touches`: `RESULT_SCHEMAS.md` → `result-schemas/automate-run.md` (wave-close park and closeout fields
  live in §AUTOMATE_RUN). The folded `#### Touches` of item 13 inside Part S is verbatim history, not machine-read,
  and is left as written.

### Part B — 12 — Policy answers for routine lane questions, so the owner answers decisions, not formalities

#### Problem
Owner goal: 5–10 lanes at once. In S1 v2, two lanes asked **15 questions in 10 deferred calls over about 2 hours**
(one every ~8 minutes). At 10 lanes that is about 75 questions per wave. Classifying v2's 15 by what the owner
actually decided:
- **Routine (8):** "start a new run" over a stale paused run (2); confirm a one-item queue (1); save a brief that
  Plan Review passed with 0 issues (1); keep or drop a LOW-only summary draft (3); proceed past the children-settled
  check when the only unsettled child is a finished non-plugin `Explore` agent, the known gap in
  `automate-followups/17` (1). The owner picked the recommended option every time.
- **Real decisions (7):** refine a brief carrying a MEDIUM finding; save-with-notes vs re-review on 4 LOW notes;
  an output-gate gap; four fix-now / follow-up picks on MEDIUM findings.

A second problem blocks any automation of the first: **the same gate is phrased differently each time.** v2-a's
resume gate had header `Resume` and option `Start new (Recommended)`; v2-b's had `Resume?` and `Start new run
(Recommended)`. Nothing stable identifies a gate or its options today.

#### Goal
Each engine gate carries a stable id and canonical option labels. The owner can write a small, human-stamped
policy that pre-answers named routine gates; such answers are recorded as `source: policy`, listed for review, and
never cover a decision class the gate catalog marks human-only. Real decisions still reach the owner, batched.

#### Scope
1. **Gate catalog** `loomwright/docs/LANE_GATES.md`: every `AskUserQuestion` the engine can raise in a lane
   (resume, queue confirm, Launch Pad Phase 6 save/refine, output gap, children-settled, pre-flight overlap,
   dismissed findings per severity, summary keep/drop, …) with a stable `gate_id`, its canonical option labels, and
   `policy: allowed | human-only`. Human-only, always: Plan Review FAIL or any MEDIUM-or-higher finding, an output
   gap, pre-flight OVERLAP, fix-now/follow-up/drop on MEDIUM-or-higher, anything that merges, deletes or pushes.
2. **Gates say who they are:** the engine's prose asks every catalogued gate with `header` = its short gate code
   and the catalog's exact labels (a `(Recommended)` marker stays allowed), so the defer hook can read
   `gate_id` and the options deterministically. A question with no known code is always human.
3. **Policy file** — tracked project config, the same store and the same human-stamp valve that `rules-check.sh`
   applies to a rule's `check` command (read `skills/rules/SKILL.md` §8; do not invent a second valve). Shape:
   `{gate_id: label}` for `policy: allowed` gates only. Unstamped, malformed or naming a human-only gate ⇒ ignored
   and reported, never partially applied (fail CLOSED toward asking the human).
4. **`lane-policy.sh decide <question.json>`**: prints the policy label or `human`. Item 05's defer hook calls it;
   on a label it writes the answer file through the same guarded `lane-answer` path with `source: policy`,
   `policy_sha`, and resumes the lane; on `human` the question goes to the inbox as today.
5. **Visible and revocable:** `lane-status` and the lanes pane show policy answers in a digest ("3 answered by
   policy since 09:00"), each with gate, label and time; the run file's `## Progress` records each one; removing the
   stamp turns all policy answering off at the next question.
6. **Batched inbox:** `lane-status` groups every lane's pending human questions in one list (oldest first), so the
   owner answers a round at a time.
7. **Tests:** a policy label is applied for an allowed gate and recorded `source: policy`; a human-only gate in the
   policy is ignored and reported; unstamped policy ⇒ every question goes to the human; an unknown header ⇒ human;
   a label not in the catalog ⇒ refused; the drifted v2 phrasings map to one gate id after Scope 2.

#### Non-goals
- No model-judged answers: policy is an exact lookup, never an LLM decision.
- No policy for anything that merges, deletes, pushes or changes a finding's fate at MEDIUM or above.

#### Acceptance criteria
- Replaying v2's 15 questions through `lane-policy.sh` with a policy covering the 8 routine gates sends exactly the
  7 real decisions to the human.
- With no stamped policy, behaviour is identical to item 05 (every question to the human).

#### Validation (must pass before merge)
1. **Baseline:** full loop on base and branch, `<passed>/<total>` and `SKIP` counts.
2. **Unchanged path:** no policy file ⇒ the lane inbox round trip from item 05's tests passes unchanged.
3. **Running system:** one real lane with a stamped two-gate policy; paste the run file's policy lines and the
   inbox showing only the remaining human questions.
4. **A failure this must catch:** let a policy name a human-only gate and apply it ⇒ the test fails.
5. **Rollback:** `git revert`, or remove the stamp (instant off).

#### Verified premises (re-check before starting)
- The 15 v2 questions and their answers: S1 run record, relays 1–8, and `ai-agent-manager-lanes-v2/v2-*/.supervisor/
  s1-questions/` + `s1-answers/` (answer files carry `source: human`, `via`).
- Item 05 Scope 13 already defines the answer file with `source: human|policy`.

#### Evidence
S1 v2 run record (relays 1–8 and the v1/v2 comparison table).
- **Wave w1 (2026-10-04) adds a routine gate:** Phase 1.5 pre-flight returned OVERLAP with **0 open PRs**, only because 4 of the last 20 commits on `main` (all merged, all in the lane's own base `95e8601`) touched files the brief edits. The owner picked "Proceed anyway". A pre-flight OVERLAP whose every hit is already contained in the branch's base and has no open PR is a candidate for `policy: allowed`, or better, for pre-flight itself to classify as CLEAR, since "overlap with your own base" is not competing work. A pre-flight OVERLAP against an OPEN PR stays human-only.
- **Wave w1, more routine gates:** w1-10 asked about 3 dismissed-finding drafts whose findings were **already fixed on the PR** (named commits, regression tests added), each with "Drop (Recommended)". The owner dropped all three. A draft whose finding the lane can show fixed on the current head (commit plus test named) is a `policy: allowed` drop candidate. A draft whose fix cannot be shown stays human.
- **S3 wave 2 (2026-10-07, owner, relayed by S3 session 2216aefd) — the same gate asked inconsistently:** the
  stale-runs "Start new run?" question was asked by lane s3-f but NOT by s3-e or s3-g, all three in the same state
  (one other incomplete run). Evidence only; operator note for the brief: a policy can pre-answer only a gate that
  fires predictably, so whether this gate fires may need the same pinning as its phrasing (S3 record §"Wave 2
  result", gap 5).

#### Touches re-pointed 2026-10-07 (S3 operator f849e0cc, after pa/11's split — #408, v15.124.0)
- `RESULT_SCHEMAS.md` → `result-schemas/automate-run.md`: the Scope names no block of its own; its schema text is the
  run file's `## Progress` policy-answer lines (Scope 5) and the `source: policy` answer record item 05 defines
  under §AUTOMATE_RUN.
