# S3 — Stabilization queue run as waves (OPERATOR-RUN wave spike — not an `/automate` item; no plugin change)

## Status: parked (operator-run: lives in `operator-run/` so folder intake never enqueues it; start after step 0, the release of S2's four fragments, and a plugin reinstall)

**Usage check:** every command in an `operator-run/` runbook is checked against the shipped script's usage text (`<script> --help`) before the runbook is used — by hand, no checker script; a flag `--help` does not list (e.g. the dry-run flag M1 step 1 once named) is a runbook bug to fix first.

## Depends on
- S2 closed (all five PRs merged, lanes torn down, `leaks` empty — done 2026-10-05).
- Step 0: one release bump folding `changelog.d/` (items agnostic-phase1/01, automate-followups/16, 24, 26), merged
  and installed, so wave 1's lanes run S2's fixes.
- The S1/S2 harness `~/Documents/work/AI/ai-agent-manager-lanes-v2/s1h.sh`, now with `launch <lane> --resume-run
  <run_id>` (added 2026-10-05; backup in `archive/`).

## HANDOVER (2026-10-07 ~04:40Z) — from session 2216aefd to session f849e0cc for wave 3 (owner: "handover … ask that to start wave 3")
**Single owner from now: session f849e0cc.** 2216aefd runs nothing for S3 (no lane, monitor, watcher) and edits no
S3 record after this push. Wave 2 is fully closed — §"Wave 2 result" has the numbers, the operator's #402 fix and seven
new gaps; read it, and §"Lessons from wave 1" below (they all held again).

### State at handover (verified 04:35Z)
- `main` = `f4b0732` (#409, **v15.124.0**). **15.124.0 is installed** (install record `installPath …/loomwright/15.124.0`).
  Primary clean on `main`, no extra worktrees, `loomwright-meta` synced. No open loomwright PR.
- Nothing running for S3: no lanes (`s1h.sh leaks` empty), no monitor, **no caffeinate**. `wave/s3w2` and
  `loomwright-meta-s3w2` are deleted (owner yes). The one live `automate-merge-watch.sh` (pid 23691, cwd
  `~/Documents/work/Tray/hub`, a 15.123.0 install) belongs to another project — not S3; leave it.
- Harness changes this wave: `s1h.sh answer` now accepts **comma-joined labels for multiSelect questions** (each label
  validated; backup `archive/s1h.sh.backup-2026-10-07-pre-multiselect`). New in the harness dir: **`s3-monitor.sh`**
  (the 30 s poll used in wave 2: changed lane lines, `PENDING-AT-ARM`, `HIGH-LOAD` ≥ 60, `VERY-HIGH-LOAD` ≥ 90,
  `NO-CAFFEINATE` / `CAFFEINATE back`; run it under Monitor, re-arm every 30 min) and **`load-test-3clones.sh`** (the
  #402 three-clone staggered `ci-local` test with a load1 kill switch — hard-codes the `pr402` ref; adapt before reuse).
  The `/lanes` pane mod v0.4.0 (machine/load/caffeinate line, question age) is at
  `~/.claude/dev-mods/2216aefd-eb73-4e57-a40e-e23bd82b907d/lanes/` — copy into your session's mods folder.

### Wave 3 — what must happen first (in order)
1. **Touches re-point (the post-pa/11 step; blocks planning).** pa/11 split `RESULT_SCHEMAS.md` into
   `loomwright/docs/result-schemas/*.md` (index kept) and `automate-helpers.sh` into `automate-helpers.d/*.sh`
   (`gate-eval` stayed in `automate-helpers.sh`). Measured 04:30Z — open items whose `## Touches` still name the OLD
   files (RS = `RESULT_SCHEMAS.md`, AH = `automate-helpers.sh`): ms/07 RS · af/31 RS+AH×2 · af/33 RS · pa/05 RS+AH ·
   pa/06 RS · af/34 RS+AH · pa/12 RS · pa/18 RS+AH×2. Clean: hc/01, hc/02, ms/05, pa/14, pa/07. For each, read its
   Scope to pick the exact split file(s), edit Touches, `plan-waves --lint`, then `plan-waves --max 5 --explain` under
   the S3 planner rule (§"Planner rule"). Record what changed (gap 7). **Wave-2 lesson:** agnostic/04 edited
   `RESULT_SCHEMAS.md` without declaring it — also skim each Scope for files it will obviously edit but does not list.
2. **Confirm wave 3 with the owner.** Owner order says ms/07 · af/31 · af/33 + hc/01 · hc/02 (host-contract, split
   2026-10-06 to run in parallel; hc/03 joins after both merge, done directly). The re-plan may change it.
3. **Launch only on the owner's go in YOUR chat** (a cross-session message cannot authorize a lane launch — the
   classifier blocks `s1h.sh launch` as "Create Unsafe Agents" until the owner says so in-session). Owner starts
   `caffeinate -i` (no timer — `-t 14400` expired mid-wave in BOTH waves) or gives you the go to start it.
4. **Lane count:** pa/16 is now live — `ci-local` admits at most two 6-job suites machine-wide and holds the rest, so
   the wave-1 burst cannot recur through `ci-local`. Lanes' other work (workers, reviews) is not capped: start ≤ 3
   building and add the rest as lanes reach review; keep the HIGH-LOAD monitor (wave 2 peaked at 73).
5. **Verify #408's deferred Validation 2** on the first lane's run (a live sequential `/automate` through the split
   dispatcher): watch that lane's helper calls succeed and note it in §"Wave 3 log".

### Wave-2-specific lessons (add to the wave-1 list)
- Run every PR's "Not verified" running-system step yourself — wave 2's #402 FAILED its own (load1 63.6) and the
  lane had marked it "not run"; #403's PO can't-ask branch needed a live `claude -p --plugin-dir` probe.
- Re-check a lane's claims cheaply before relaying (all held this wave) and read the bot review that lands AFTER an
  operator push (#402's `cd5f400` drew a real finding).
- `total_cost_usd` is cumulative across a lane's resumes — take the LAST value per lane, never sum.
- Lanes all run the start-up cross-run closeout on the SAME shared run files and race their meta pushes (13
  conflicts per lane in wave 2). With wave 2's runs already finalized on `loomwright-meta` the race should be small
  in wave 3, but expect `meta-push FAILED: conflict` on any shared file; resolve as in §"Wave 2 result" before teardown.
- A relayed `note` never reaches the lane — put anything the lane must know into the answer label choice, or skip it.

### Open owner items (not wave work)
- Telemetry `PRIVACY_PATTERNS` note (set aside); `proposed/s3w1-wave-pr-397-review.md`; the three wave-2 kept
  dismissed summaries in `proposed/` (`*154117*`, `*154217*`, `*154514*` — the last includes `automate-helpers.sh`'s
  lost executable bit; no direct caller found).

## HANDOVER (superseded 2026-10-07; 2026-10-06, updated ~12:45Z) — from session 6e8f1058 to session 2216aefd for wave 2 (owner: "for next wave use new session")
**Single owner from now: session 2216aefd.** 6e8f1058 runs nothing for S3 (no lane, monitor, sampler, watcher) and
edits no S3 record after this push.

### Update since the first version of this handover (read this first — it supersedes "Not done" below)
- **Released v15.123.1** (#401, `a14db34`) folding #398 (pa/19), #399 (ms/11), #400 (wave-1 review fixes); the owner
  **reinstalled — 15.123.1 is installed** (`~/.claude/plugins/cache/atelier/loomwright/15.123.1`, install record =
  15.123.1). `main` = `a14db34`, primary clean, no extra worktrees, `loomwright-meta` synced.
- **pa/19 is DONE and live-verified** (merged #398; on #401 the run log showed `Set structured_output with 1 field(s)`
  and `the reviewer posted its own review — no fallback needed`). Its wave-2 placement question is moot.
- **ms/11 is DONE** (#399) — wave 3 is now ms/07 · af/31 · af/33.
- **Wave 2 = pa/11 · pa/16 · agnostic/04** (owner order), at most 2 lanes building until pa/16 merges.
- **Drain every wave PR** (owner-accepted recommendation): `/loomwright:review-pr <wave-PR-url> --until-mergeable`;
  if claude-review posts nothing, the drain's earned fallback runs a `code-reviewer` diff review.
- Still open: the telemetry `PRIVACY_PATTERNS` note (owner set it aside); the smaller notes in
  `proposed/s3w1-wave-pr-397-review.md`.

### State at handover
- **Wave 1 done.** #397 (`wave/s3w1`) merged with a merge commit (`f0b4b66`, v15.123.0); the four lane PRs flipped
  MERGED and closed out by their watchers; records carried to `loomwright-meta`; lanes torn down (`leaks` empty);
  `loomwright-meta-s3w1` deleted (owner yes). Primary on `main` `f0b4b66`, clean; its legacy `meta-base` was adopted
  by 15.123.0's meta-sync (`synced … on loomwright-meta`). Full numbers: §"Wave 1 result".
- **Plan restructured twice on 2026-10-06** (§"Restructure 2026-10-06", §"…second pass") and the **owner's wave order**
  is §"Wave plan — OWNER ORDER 2026-10-06": **wave 2 = pa/11 · pa/16 · agnostic/04**.
- ~~New item `parallel-automate/19-review-large-prs.md`~~ — DONE (#398), see the update above. (Original note:
  owner "ok" to filing it; its placement was the owner's call at launch: before wave 2, or as a 4th wave-2 lane started
  first so it can merge before pa/11's large move-only PR is reviewed. A PR that edits a workflow file cannot review
  itself (claude-code-action skips it, green, no comment).
- **Not done / not running:** 15.123.0 was NOT yet in `~/.claude/plugins/cache/atelier/loomwright/` at handover
  (owner reinstalling) — lanes run the installed plugin, so check before launch. `caffeinate` not running (owner
  starts `caffeinate -i -t 14400` in a terminal tab; it expires after 4 h — wave 1's died mid-wave). No lanes, no
  monitor. `archive/s3-a..d` + `launch.log` hold wave 1's lane logs.

### Next steps
1. Confirm `15.123.1` in the plugin cache (owner reinstalled 2026-10-06 after #401). Owner starts `caffeinate`; confirm with `pgrep -fl caffeinate`.
2. (pa/19 done — nothing to decide.)
3. `echo "# ---- wave s3w2 starts $(date -u +%FT%TZ) ----" >> launch.log`; move `snapshot-*.txt` into
   `archive/s3w1/`; `bash s1h.sh snapshot before`; `export S1H_META_BRANCH=loomwright-meta-s3w2`; set up lanes from
   the primary (first with `--seed`): `bash s1h.sh setup <lane> .supervisor/requirements/<folder>/<item>.md [--seed]`.
4. **At most 2 lanes building at once until pa/16 merges** (wave 1 froze the machine at load1 119 with 3 lanes in
   `ci-local`); start the third when one reaches review. Owner may override (they did once: "start all").
5. Monitor: poll `s1h.sh status --json` every 30 s, print changed lane lines, `PENDING-AT-ARM` question lines at
   each (re-)arm, and a `HIGH-LOAD` line when `sysctl -n vm.loadavg` load1 ≥ 60; re-arm every 30 min.
6. At park: merge checks (below), then integrate on `wave/s3w2` exactly as wave 1 (§"Integration method";
   §"Wave 1 result" has the commands' outcome). After pa/11 merges: re-check every open item's Touches against the
   split files and re-plan waves 3+ (the owner order for 3+ is a simulation).

### Lessons from wave 1 (apply them)
- Relay verbatim, ≤4 per AskUserQuestion, never merge two lanes' questions; re-read `pending.id` right before
  `s1h.sh answer`; check a lane's factual claim read-only when cheap (several were checked in wave 1; all held).
- Merge checks found real gaps the PR bodies left open: run every "Not verified" running-system step yourself in a
  scratch clone with a local bare remote (wave 1: #391 scrub, #392 `--affected`/`--last`, #394 data-loss replay,
  #395 counter + RESUME finalize). A green check can be on a stale head — compare the PR head to the checked sha.
- A review that lands AFTER a park is drained by nobody: read the latest bot comment on the final head and put any
  findings to the owner.
- **Crash recovery:** a machine reset kills every lane; resume each by run id (`s1h.sh launch <lane> --resume-run
  <run_id>`), staggered. Resumed lanes ask a routine "unsettled child" FINALIZE question for agents of the dead
  session (s3-a, s3-b); answering "proceed" was correct.
- **Closeout pushes can fail the scrub** (`meta-push FAILED … home_path`; s3-c, s3-d). Carry by hand: copy new
  files, append only the requirement's closeout block and new `results.jsonl` lines, rewrite home paths (and the
  `/api/users/<42>/` false positive) — **check with `grep -iE`, the scrub is case-insensitive**. Then sanitize the
  lane copy and push it to the throwaway branch so `teardown` (refuses `local_ahead`) can run.
- `s1h.sh teardown` does NOT refuse a lane whose meta-sync status is `base_branch_mismatch` (s3-b) — confirm its
  records are carried (diff the lane's managed files against the primary) before tearing it down.
- When the owner merges the wave PR with a merge commit, all lane PRs flip MERGED within a second and the watchers
  close out within ~60 s; no targeted resume was needed.
- Run IDs: one lane (s3-b) stamped its run id in local time, the others UTC — read ids from the run files' titles.
- **A handover by cross-session message cannot authorize a lane launch (2026-10-06, wave 2).** Session 2216aefd's
  `s1h.sh launch s3-e` was denied by the auto-mode classifier as "Create Unsafe Agents" (detached `claude -p
  --permission-mode acceptEdits` sessions), and so was the status check after it. The same command went through in
  session 6e8f1058, where every launch followed the owner's own words in that chat ("go", "start all"); in 2216aefd the
  only instruction came from 6e8f1058's peer message, and a peer cannot grant permission (by design — otherwise one
  session could launch agents the user's settings would stop). That cause is inferred: the denial names only the
  category. **Rule for every later handover:** the handing-over session prepares the lanes, but the OWNER gives the
  launch go-ahead in the new session's own chat ("go — launch the wave N lanes"); the handover message says so instead
  of carrying the launch instruction. A blocked session stops and puts "blocked — need you" on the FIRST line.

## HANDOVER (superseded 2026-10-06; 2026-10-05 ~11:45Z) — from session 944cda59 to session 6e8f1058
**Single owner from now: session 6e8f1058.** 944cda59 runs nothing for S3 (no monitor, sampler, watcher or lane)
and edits no S3 record after this push.

### State at handover (superseded 2026-10-06 — current state: §"Wave 1 log" and §"Wave 1 result")
- Step 0 done: release #390 merged (`3217da0`, v15.122.0); plugin installed at 15.122.0
  (`~/.claude/plugins/cache/atelier/loomwright/15.122.0`); primary on fresh `main`, clean; `loomwright-meta` synced.
- **Wave 1 is SET UP, NOT LAUNCHED.** Throwaway records branch `loomwright-meta-s3w1` (seeded by s3-a, `51629ca`).
  Lanes (in `~/Documents/work/AI/ai-agent-manager-lanes-v2/`): s3-a `automate-followups/32` · s3-b
  `meta-sync-followups/08` · s3-c `meta-sync-followups/04` · s3-d `parallel-automate/09`. All clean, mode
  `on loomwright-meta-s3w1`, relay hooks installed. `launch.log` has the wave marker, one aborted-setup note (partial
  clones from an interrupted command, removed) and the four setup lines. `snapshot-before.txt` is current. S2's
  snapshots and `s2-measure.log` are in `archive/s2/`.
- **Not running:** `caffeinate` (the owner starts it in a terminal tab — this session's classifier denied it in S2;
  do not work around that), lane monitor, sampler, `/lanes` pane.

### Next steps (in order)
1. Owner starts `caffeinate -i -t 14400`. Confirm with `pgrep -fl caffeinate`.
2. `export S1H_META_BRANCH=loomwright-meta-s3w1`, then from the primary:
   `bash ~/Documents/work/AI/ai-agent-manager-lanes-v2/s1h.sh launch s3-a` (… s3-b, s3-c, s3-d) within a minute.
3. Start the lane monitor (S2 handover recipe in `S2-five-lane-spike.md` §Watching; prime it with the current state and
   print `PENDING-AT-ARM` lines so no question slips between re-arms; re-arm every 30 min) and, if measuring,
   `s2-sampler.sh` adapted to s3 lane names (it is hard-coded to `s2-a..e`; copy it to `s3-sampler.sh`). Background
   commands in a session are capped at 2 h — the owner can run the sampler in a terminal tab instead.
4. Expect each lane to ask the stale-runs "Start new run?" + "process the 1-item queue?" first (item 28 is not fixed
   yet — it is in s3-a). Relay verbatim.
5. At park: merge checks (S2 handover list), then the **wave-branch integration** in §"Integration method" below —
   lanes are NOT merged directly; one wave PR per wave, merged by the owner with a merge commit.

### Lessons from S2 and this session (apply them)
- Relay rules: verbatim, ≤4 questions per AskUserQuestion call, never merge two lane questions, one label per answer,
  free text only as `note`; check a lane's factual claim read-only when cheap; re-read `pending.id` right before
  `s1h.sh answer` (the owner may answer in the `/lanes` pane).
- **Escalated parks arm no watcher.** Close them out with `s1h.sh launch <lane> --resume-run <run_id>` (sends
  `/loomwright:automate --resume <run_id>`; proven on s2-d and s2-a). Never the launch prompt, never a bare `--resume`:
  a lane clone holds every unfinished run file of the primary.
- 3 of 5 S2 lanes escalated for temporary reasons (a `test-ci-local.sh` (L) slot-timeout flake; `claude-review`
  settling ~23 min, past the drain's 1200 s bound). Check the actual check state before telling the owner anything.
- A BEHIND PR does not need `gh pr update-branch` when the owner merges by admin bypass (S1 Q4); S2's update churn was
  the operator's choice. With the wave branch it does not arise. Update a branch only with the owner's go.
- Records: after each closeout carry the lane's records to `loomwright-meta` with
  `meta-sync.sh push --branch loomwright-meta --paths-from <list>` (ALWAYS `--branch`). Copy new files; for a
  requirement append ONLY the `<!-- loomwright:requirement-closeout -->` block; append only that PR's
  `results.jsonl` line; skip the lane's stale copies of other requirements. Rewrite `/Users/<name>/` → `~/` first —
  the scrub blocked 3 of 5 S2 pushes (briefs' `Project:` line; `reconcile-status` paths in run files).
- `trail-pr` appends its own "meta-pushed" line after pushing, so a lane reads `local_ahead 1` afterwards; push that
  run file to the throwaway branch before `teardown` (teardown refuses `local_ahead`).
- Lane teardown: archive `.supervisor/{s1h-lane.log,s1-questions,s1-answers,logs}` to `archive/<lane>/`, then
  `S1H_META_BRANCH=… bash s1h.sh teardown <lane>`. Delete the throwaway branch only with the owner's yes.
- The Bash tool runs zsh: `set -- $pair` and unquoted `$LIST` do not word-split — use explicit calls or `bash -c`.
  An `rm -rf "$VAR/..."` is blocked by a safety check; use literal paths after inspecting the target.
- An interrupted or rejected command may already have run part-way (s3-a's clone): inspect side effects before
  retrying.
- Hard-coded plugin path for a manual closeout is now
  `~/.claude/plugins/cache/atelier/loomwright/15.122.0/scripts/automate-helpers.sh closeout <runfile> <item> <pr_url>`.
- Optional `/lanes` pane: the mod is in `~/.claude/dev-mods/3679fac4-1abb-4fb1-b18d-a49e84d3ddb5/lanes/` (validated);
  load the `plugin-authoring` skill, copy that folder into the new session's mods folder, enable hot reload, `/lanes`.

## Purpose
Owner decision 2026-10-05: stabilize parallel automation, then release it for other repos, and build that queue
**with waves, the way S2 ran** — as a spike that also looks for gaps the requirements below do not name. S2 had one
wave; S3 is the first run of **several waves in a row**, with a release and reinstall between waves (the
pa/06 one-bump-per-wave model, by hand) and with the wave runner's own replacement (pa/05) built mid-queue.

## The queue (19 items after the 2026-10-06 restructures, §"Restructure 2026-10-06"; was 22 — owner decision 2026-10-05: "finish parallel automation and everything related"; 19 + `parallel-automate/16` (after wave 1 froze the machine) + `meta-sync-followups/09, 10` (#391's leftovers), all added the same day)
Merged on 2026-10-05 (originals parked with pointers; text kept verbatim as parts):
`meta-sync-followups/08` = ms/02 + 03 + 06 · `automate-followups/32` = af/14 + 28 + 29 · `automate-followups/33` =
af/17 + 25. New the same day: `meta-sync-followups/07` (onboard any repo to branch mode), `automate-followups/31`
(temporary escalations); `parallel-automate/06` amended (watcher on `escalated` parks, targeted `--resume`).
Added to the scope the same day: `parallel-automate/09, 11, 12, 13, 14, 15`, `automate-followups/22, 23`; later
`parallel-automate/16` (machine load guard) and an amendment to `parallel-automate/05` Scope 16 (load guard + reset
recovery), both from the wave 1 crash (§"Wave 1 log").
Out of scope (not parallel work): the rest of the backlog, including the 7 older items with no Touches / Depends on.

## Restructure 2026-10-06 (owner decisions relayed by session 53b1897e: fewer, larger items)
Why: a run costs ~$17–20 plus 4+ owner questions even for a tiny change (S2 lanes $17–40; S3 wave 1 $20–42).
Same lossless procedure as af/32, af/33, ms/08 (originals verbatim as parts, originals parked with a pointer,
dependents re-pointed; a line check found no original line lost — only deliberate edits: fragment names, re-pointed
depends, the moved pa/06 fragments).
- `meta-sync-followups/09` + `/10` → **`meta-sync-followups/11-scrub-precision.md`** (A = 10 anchor, B = 09 schema examples).
- `automate-followups/22` + `/23` → **`automate-followups/34-sweep-and-janitor.md`** (A = 22 sweep, B = 23 registry + `/janitor`).
- `parallel-automate/13` → **`parallel-automate/06` Part S**, REWRITTEN for wave-branch integration (13's premise —
  lane PRs merging into `main` one by one — no longer applies); pa/06 also amended: wave close on a wave branch, no
  release lane (wave 1 evidence). Open owner decision recorded there: may the coordinator run the merges into `wave/*`.
- `meta-sync-followups/05` Part D (rehearsal harness + M2 runbook, AC D1–D3) → **`meta-sync-followups/07` Part D**;
  ms/07 no longer depends on ms/05; **`parallel-automate/05`'s Depends re-pointed ms/05 → ms/07**.
- `parallel-automate/06`'s 2026-10-05 "arm the merge watcher at an `escalated` park" (bullet, its test, its validation
  note) → **`automate-followups/31`**, which no longer depends on pa/06 (also fixes the sequential case).
- New: **`parallel-automate/17-right-size-check-and-merge-items.md`** (filed by 53b1897e); owner: keep separate from pa/15.
- Milestone A unchanged: after ms/07 + agnostic/04.

## Restructure 2026-10-06, second pass (owner decisions relayed by session 53b1897e)
- `parallel-automate/15` + `/17` → **`parallel-automate/18-backlog-board-and-right-size.md`** (A = 15 board, B = 17
  right-size; the size verdict + merge candidates are a column on the board; the writer/intake line and
  `merge-items` stay). Lossless check: only the two fragment names differ. 15 items left.
- **`parallel-automate/11` now splits `loomwright/docs/RESULT_SCHEMAS.md` too** (Scope 4 amended, AC + Touches added):
  per-schema files under `docs/result-schemas/`, `RESULT_SCHEMAS.md` kept as the anchor-preserving index, every
  parser of the doc kept working, and every open item's Touches re-pointed after the merge.

## Done directly, not as a lane (owner 2026-10-06: "why do we need a wave for this")
Small items whose lane overhead (~$20 + 4+ questions) exceeds the work run in the operator session as a plain branch +
PR (ci-local, then the owner merges); they leave the wave plan.
- **pa/19** → PR #398 (workflow-only). Root cause measured: the same prompt + `--allowed-tools` reproduced locally on
  #397's merge commit finished a full review with 0 denials — the review was done, the POST was missed. Fix: review
  also returned as `--json-schema` structured output; a step posts it (github-actions[bot], marked) when claude[bot]
  did not. Cannot review itself (workflow PR) — first live check is the next non-workflow PR.
- **ms/11** → PR #399 (anchored `home_path` scrub, guard, schema placeholders; test-meta-sync 233/0).
- The locally recovered review of #397 (5 non-blocking findings + notes) is saved for triage at
  `proposed/s3w1-wave-pr-397-review.md`.
- Wave 3 in the owner order loses ms/11 (done): wave 3 = ms/07 · af/31 · af/33.
- **Merged 2026-10-06:** #400 (`72b6655`, the five #397 review findings, drained READY after 1 round), #399
  (`1b5adb5`, ms/11, drained READY), #398 (`7bd43ce`, pa/19, drained READY: CI self-skips workflow PRs, so the drain's
  earned fallback `code-reviewer` reviewed it — 6 findings fixed, incl. the PR's own false claim that the drain reads
  claude[bot] only). Three `changelog.d/` fragments are unreleased; installed plugin is still 15.122.0.
- **#398 live check PASSED** on release PR #401 (v15.123.1, 2026-10-06): run log `Set structured_output with 1 field(s)`,
  `the reviewer posted its own review — no fallback needed`, claude-review green, claude[bot] review posted (no findings).
- **Pending:**   the telemetry `PRIVACY_PATTERNS` note from #399's review is undecided (owner set it aside).

## Wave plan — OWNER ORDER 2026-10-06 (critical path first; relayed by session 53b1897e; supersedes the planner tables below)
Wave 2 confirmed by the operator with `plan-waves --max 5 --explain` under the S3 rule on the real files at
`e141b08`: pa/11 · pa/16 · agnostic/04 share no file. agnostic/04 is on the critical path of both Milestone A
(ms/07 + agnostic/04) and pa/05; ms/05 is on neither since pa/05 depends on ms/07. Milestone A moves to after wave 3.
| Wave | Items | Lanes | Note |
|---|---|---|---|
| 2 | pa/11 (+ `RESULT_SCHEMAS.md` split) · pa/16 machine load guard · agnostic/04 non-interactive gates | 3 | at most 2 building at once until pa/16 merges; the third starts when one reaches review |
| 3 | ms/07 · ms/11 · af/31 · af/33 · **hc/01 · hc/02** | 5–6 | relies on pa/11's split (only `RESULT_SCHEMAS.md` keeps them apart today) → **Milestone A**. host-contract added 2026-10-06 (owner: "prep now, lane at wave 3", then "split": 01 ∥ 02 as two lanes, no shared file; 03 = contract join, done directly after the wave merges — a single lane would have parked after 01 until a merge, pushing 02 to wave 4). hc/01 edits `ci.yml` ⇒ claude-review skips the wave PR |
| 4 | pa/05 lane coordinator | 1 | |
| 5 | pa/06 (+ Part S) · pa/14 | 2 | |
| 6 | af/34 sweep + janitor | 1 | |
| 7 | ms/05 learning stores (A–C) | 1 | |
| 8 | pa/12 policy answers | 1 | |
| 9 | pa/18 board + right-size | 1 | |
| 10 | pa/07 pilot + docs | 1 | → **Milestone B** |
Waves 3+ are a simulation, to be confirmed by the post-pa/11 re-plan (Touches re-checked against the split files).
Waves 6–9 serialize on `automate-loop/SKILL.md` and `commands/automate.md` (not split by pa/11) and on
`automate-helpers.sh` (split by pa/11, not modelled), so the re-plan may join some of them.

## Wave plan (planner, 2026-10-06 second pass — superseded by the owner order above; S3 planner rule; `plan-waves --max 5`; 15 items)
| Wave | Items | Lanes |
|---|---|---|
| 2 | pa/11 split hotspots (+ RESULT_SCHEMAS) · pa/16 machine load guard · ms/05 learning stores (A–C) | 3 |
| 3 | ms/11 scrub precision | 1 |
| 4 | af/33 children-settled gate | 1 |
| 5 | ms/07 onboard any repo (+ Part D) | 1 |
| 6 | agnostic/04 non-interactive gates (→ Milestone A) | 1 |
| 7 | pa/05 lane coordinator | 1 |
| 8 | pa/06 wave close (+ Part S) · pa/14 lanes pane | 2 |
| 9 | af/31 temporary escalations | 1 |
| 10 | pa/12 policy answers | 1 |
| 11 | pa/18 board + right-size | 1 |
| 12 | af/34 sweep + janitor | 1 |
| 13 | pa/07 pilot + docs (→ Milestone B) | 1 |
- **ms/11 left wave 2:** its Part B edits `RESULT_SCHEMAS.md`, which pa/11 now splits; the planner put ms/05 in its
  place (ms/05 conflicts with ms/11 only on `meta-sync.sh`).
- **Post-split estimate** (same run with `RESULT_SCHEMAS.md` dropped from every other item's Touches): **10 waves**
  (wave 2: pa/11 · pa/16 · ms/11 · af/33 · ms/07; then ms/05 → agnostic/04 → pa/05 → pa/06 · pa/14 → af/31 → pa/12 →
  pa/18 → af/34 → pa/07). Not ~7: after the schema doc, the tail serializes on **`automate-loop/SKILL.md`** and
  **`commands/automate.md`** (af/31, pa/12, pa/18, af/34, pa/07 all edit one or both) and on pa/05 → pa/12 / pa/06 →
  pa/07 dependencies. Splitting the skill is the next lever; pa/11 keeps it out (prose engine, state-trace review).

## Wave plan (re-planned 2026-10-06, first pass — superseded by the second pass above)
16 items left (20 after the restructure, 4 merged in wave 1). **Pre-split plan — re-check Touches after pa/11.**
| Wave | Items | Lanes |
|---|---|---|
| 2 | pa/11 split hotspots · pa/16 machine load guard · ms/11 scrub precision | 3 |
| 3 | af/33 children-settled gate · ms/05 learning stores (A–C) | 2 |
| 4 | ms/07 onboard any repo (+ Part D harness) | 1 |
| 5 | agnostic/04 non-interactive gates (→ Milestone A) | 1 |
| 6 | pa/05 lane coordinator | 1 |
| 7 | pa/06 wave close (+ Part S) · pa/14 lanes pane | 2 |
| 8 | af/31 temporary escalations (+ escalated-park watcher) | 1 |
| 9 | pa/12 policy answers | 1 |
| 10 | pa/15 backlog board | 1 |
| 11 | af/34 sweep + janitor | 1 |
| 12 | pa/17 right-size + merge-items | 1 |
| 13 | pa/07 pilot + docs (→ Milestone B) | 1 |
**Finding:** `loomwright/docs/RESULT_SCHEMAS.md` (declared by 7 of 16 items) is now the main serializer — af/31,
af/34 and pa/17 have no dependency on the items they wait for, only this file and `automate-helpers.sh`
(which pa/11 splits). Input for pa/11's scope or a planner rule, like the three table docs.

## Wave plan, original (2026-10-05 — superseded by the re-plan above)
| Wave | Items | Lanes |
|---|---|---|
| 1 | af/32 run-file lifecycle · ms/08 meta-sync hardening · ms/04 home-path scrub · pa/09 fewer full CI runs | 4 |
| 2 | pa/11 split shared hotspot files · **pa/16 machine load guard** (owner decision 2026-10-05: "Wave 2, beside pa/11" — replaces "pa/11 alone"; no Touches overlap, checked) · **ms/10 anchor the `home_path` scrub** (owner 2026-10-05, at #391's park; needs ms/08 merged) | 3 |
| — | **Re-check every remaining item's `## Touches` against the split layout, then re-plan waves 3+** | — |
| 3+ (pre-split plan, will widen) | ms/09 scrub-safe schema examples (after af/32) · af/33 · ms/05 → ms/07 · agnostic/04 (Milestone A) → pa/05 → pa/06 · pa/14 → af/31 → pa/12 → pa/13 → pa/15 → af/22 → af/23 → pa/07 (Milestone B) | 1–3 |

Milestone A (after ms/07 + agnostic/04): release; any repo can move to branch mode and run sequential `/automate`.
Milestone B (pa/07 last, so the pilot exercises pa/12–14 and the docs cover them): release; parallel lanes on other
repos. Before the merges and the relaxed rule the original 11 items planned to 10 waves; the full 19 plan to 12
before pa/11's split.

## Planner rule for this spike (owner decision 2026-10-05: "Allow, measure")
Companion-only overlaps on the three table docs — `loomwright/docs/ARCHITECTURE_CONTRACTS.md`,
`loomwright/docs/prompt-token-budgets.json`, `loomwright/skills/SKILLS_INDEX.md` — do not keep items apart. Plan
with a scratch clone whose `.agent/companions.json` drops just those three entries from the non-`new` rules (the
`new: true` doc-currency rules stay); declared overlaps still serialize. **Measure:** at each merge, whether any of
those three files conflicted (S2 evidence: three PRs edited `ARCHITECTURE_CONTRACTS.md` and merged by lines). The
result is input for `parallel-automate/11` or a planner rule.

## Integration method: a wave branch (owner decision 2026-10-05)
S2 merged each lane PR into `main` and then updated every sibling and re-ran CI. S3 integrates on a wave branch
instead, with no plugin change:
1. Lanes run exactly as in S2 and open PRs against `main` (CI only runs for PRs into `main`, `ci.yml`), drain, and
   park `awaiting_merge` with their merge watchers armed. Nobody merges a lane PR directly.
2. When every lane of the wave has parked (or is excluded), the operator creates `wave/s3w<N>` from `main` and
   merges each lane's exact PR head into it in planner order (`git merge --no-ff <head sha>`). A conflict is
   resolved in that merge commit on the wave branch; a lane's own branch is never rewritten or pushed to. Then
   `ci-local`, then `bash scripts/bump-version.sh` as the wave branch's LAST commit (P7, one bump per wave — no
   release lane), then ONE PR `wave/s3w<N>` → `main`. The operator runs the merge checks on that PR.
3. The owner merges the wave PR with **"Create a merge commit"** (never squash — squash merges are enabled on this
   repo). GitHub then marks each lane PR merged, because its head commit is on `main`; each lane's watcher sees
   `MERGED` and runs closeout itself. **Spike question:** confirm this in wave 1; fallback is the targeted
   `--resume` closeout proven on S2's s2-d.
4. A lane found broken by the wave branch's CI is fixed on its own PR branch (its drain or a fix), and its new head
   is merged into the wave branch again.
5. Measure: conflicts resolved on the wave branch (files, by hand or clean), wave PR CI and review wall-clock, and
   whether every lane PR flipped to merged.
If it holds, amend `parallel-automate/06` (wave close on a wave branch; no release lane) and
`parallel-automate/13` (conflicts repaired on the wave branch, never on a lane PR), and decide whether the
coordinator may merge into `wave/*` (an owner decision on the single-merge-executor invariant).

## Run rules (carried from S2's handover)
- Owner merges every PR by hand. Questions relayed verbatim, ≤4 per call, never merged; an answer is one label.
- Merge checks before "safe to merge": the item's must-pass Validation (run any "Not verified" running-system step
  in a scratch clone), scope fence vs Touches (+ companions), `ci` + `claude-review` green on the current head,
  dismissed findings decided. A PR that is BEHIND gets `gh pr update-branch` only with the owner's go.
- Escalated lanes close out with `s1h.sh launch <lane> --resume-run <run_id>` (never the launch prompt, never a
  bare `--resume`). Records carried to `loomwright-meta` (`--branch` always), home paths rewritten before a push.
- Between waves: the wave PR carries that wave's release bump; after the owner merges it, reinstall, verify the
  running version, `snapshot`, then launch the next wave on fresh `main`.
- Throwaway records branch per wave: `loomwright-meta-s3w<N>`, deleted (owner's yes) after that wave's carry.

## Gaps to watch (spike questions — not in the requirements)
1. **Mid-queue upgrades.** Waves 1–3 change the engine later lanes run; pa/05 replaces `s1h.sh`. Does a reinstall
   between waves break a parked lane, a run file or the harness?
2. **The undeclared manifest.** `loomwright/docs/vendor-coupling-manifest.json` conflicted in S2 (#385 vs #384/#386)
   though most items do not declare it. Record every wave where it conflicts.
3. **Temporary escalations** (3 of 5 lanes in S2): count them per wave until af/31 lands.
4. **Release-per-wave cost:** wall-clock from last merge of a wave to the next wave's launch.
5. **Lane questions:** count per lane, human vs routine (item 12 input), longest wait.
6. Anything the operator does by hand that no requirement covers → file it, link it here.
7. **Touches drift after a split.** Once pa/11 merges, items written before it may name files in a layout that no
   longer exists. Nothing re-checks a queued item's Touches against the current tree; record what had to change.

## Measure (per wave)
Lanes, launch → park per lane, questions, escalations and cause, merge order and each sibling's `mergeable` after
each merge, table-doc and manifest conflicts, release wall-clock, final `total_cost_usd` per lane, leaks after
teardown, machine (load, swap, free) at peak.

## Wave 1 log
- 11:47Z launched 4 lanes (s3-a..d); first questions (stale runs + queue) answered 11:48–11:49Z; 4 brief decisions
  12:05–12:17Z; s3-c PR #391 at 12:29Z (42 min); s3-c fix-now on a MEDIUM (home-path rule widened, `268fc98`).
- **12:5x–13:29Z machine overload → 13:40Z watchdog reset (crash).** 13:17Z load1 119 / 15-min 37 on 12 CPUs, 3 lanes
  in `ci-local` at once. Panic `panic-base+socd-2026-10-05-191808.panic` ("SOCD report detected: (iBoot panic)"),
  reset counter `Boot faults: wdog,…`. All four lanes died (last writes ~13:29Z); `caffeinate`, the operator monitor
  and the session's scratchpad went with it. Nothing lost: s3-a 8, s3-b 2, s3-d 1 local commits (not pushed), s3-c
  PR #391 green at `268fc98` + 2 uncommitted lines of a drain fix. No sampler was running, so there is no per-lane
  attribution; that is item 16's Part 0.
- Owner decision 2026-10-05: resume **two at a time** (s3-c + s3-a 16:07Z via `--resume-run`; s3-b and s3-d when one
  parks). Run ids: s3-a `automate-2026-10-05-114905`, s3-b `automate-2026-10-05-171908` (stamped in local time, the
  others in UTC — record as a gap), s3-c `…-114920`, s3-d `…-114919`.
- Owner 2026-10-05 ~16:35Z: "start all" — s3-b and s3-d resumed by run id before either running lane parked (load1
  ~4 at the time); the HIGH-LOAD alert is the only backstop until pa/16.
- 16:25Z s3-c parked `awaiting_merge` on #391 (cb73aac); merge checks all pass (scope 11/11, ci + claude-review green,
  AC1 re-run by the operator in a scratch clone: new-template brief exit 0, control exit 2). Owner, on its "Not verified"
  list: SPIKES home path fixed ON #391 (operator commit `1f0571b`, ci-local 143/143 first, remote head checked; item
  04's Touches amended) — needs ci + claude-review again; schema/fixture paths → `meta-sync-followups/09`; regex anchor
  → `meta-sync-followups/10` (wave 2). The operator's own first drafts of 09/10 tripped the scrub (case-insensitive) —
  more evidence for 10.
- **Crash orphans hit the children-settled gate:** s3-b (worker died mid-`ci-local`) and s3-a (context-keeper of the
  crashed session) each asked a FINALIZE "unsettled child" question after the resume; both answered "proceed". A
  child of a dead session is indistinguishable from a running one → input for af/33 and pa/05's reset recovery.
- s3-d PR #392 ~17:00Z; s3-b PR #394 17:07Z.
- s3-a PR #395. Owner decisions on dismissed findings (2026-10-05/06): s3-b #394 fix-now on a pre-existing HIGH
  (`meta-base` not keyed by branch → a plain pull after a mode-line switch deletes local run history; the S2 harness
  already drops `meta-base` at lane setup, which is why lanes never hit it) + LOW summary kept; s3-d #392 fix-now on all
  four (incl. `--last` reporting PASS for a NOT-cached run) + LOW summary dropped; s3-a #395 fix-now on F1 + F2, F3
  dropped, LOW summary kept. Owner answered ~01:44Z after an overnight gap; lanes waited parked on questions meanwhile.
- `caffeinate -i -t 14400` (started ~16:05Z) expired ~20:05Z with lanes still live: a timer-only hold outlives nothing
  useful and dies mid-wave — pa/05 Scope 16 already says `-w <coordinator pid>`, not `-t`.
- claude-review on #391's operator push (`1f0571b`) posted 3 comments AFTER the lane parked — nobody drains a review
  that lands after the park (known: drain-dies-before-review). Owner: 1 (CI guard for 04's example grep) + 2
  (`meta-sync.sh` header wording) folded into ms/10; 3 (changelog wording nit) dropped.
- **Operator rule until pa/16 + pa/05's load guard merge:** at most 2 lanes building at once; the lane monitor also
  prints `HIGH-LOAD` at load1 ≥ 60, and on it the operator resumes no further lane.
- Unrecorded follow-up (s3-c, fix-now chosen): anchoring the `meta-sync.sh` `home_path` regex — the draft was deleted
  with the fix-now; owner to decide whether to file it.

### Wave 1 result (closed 2026-10-06 ~03:40Z)
- **Integration on a wave branch works (spike question answered: yes).** `wave/s3w1` = `main` + the four parked heads
  `--no-ff` in planner order (#395 `68e2aa9`, #394 `65e5586`, #391 `1f0571b`, #392 `3e4be57`), all clean (0 conflicts,
  incl. the three table docs and `vendor-coupling-manifest.json`), ci-local PASS 496 s, bump `bd5557d` (v15.123.0) last.
  Wave PR #397 merged by the owner with a merge commit (`f0b4b66`, 03:20:10Z); GitHub marked all four lane PRs MERGED at
  03:20:11Z and every lane's merge watcher closed out by itself within 60 s. No `gh pr update-branch`, no sibling
  re-CI, no targeted `--resume` needed.
- **claude-review FAILED on #397** (not a finding): 45 turns, $1.86, 8 permission denials, `success` with no comment ⇒
  the workflow's "a review was actually posted" assert failed. A 34-file / ~3,100-line wave diff is the likely cause
  (tool starvation per the assert's own hint; output hidden). The owner merged anyway. Gap: a wave PR needs a review
  budget/tool set sized for it, or per-lane reviews are its only review (they were all green).
- **Closeout pushes:** s3-a, s3-b pushed to the throwaway branch; s3-c and s3-d `meta-push FAILED … home_path` (lanes
  ran 15.122.0, before #391's template fix; s3-c's own run file quoted `/api/users/<42>/` literally — ms/10's false
  positive). Operator rewrote home paths and carried all four to `loomwright-meta` (`f53181e`, 29 paths) incl. s3-c's
  runbook usage-check line (M1/S1/S2/S3/00-overview) and M1 step 1.
- **Teardown:** s3-b's legacy `meta-base` matched no throwaway-branch tree ⇒ the new 15.123.0 code reports
  `base_branch_mismatch`, and `s1h.sh teardown` does not refuse on it (only `local_ahead`/`conflict`) — a mismatched
  lane could hide unpushed records; its records were verified carried by diff first. `leaks` empty after teardown.
  Primary's legacy base was adopted cleanly by 15.123.0 (`synced … on loomwright-meta`).
- **Cost (sum of each lane session's final `total_cost_usd`):** s3-a $42.32 · s3-b $25.39 · s3-c $20.58 · s3-d $20.25 ·
  wave ≈ **$108.5** (+ $1.86 for the wave PR's review).
- **Questions:** 29 relayed (s3-a 9, s3-b 6, s3-c 5, s3-d 9); routine 6 (startup) + 2 (crash orphans); the rest were
  brief / dismissed-finding decisions. Longest wait: ~8.5 h overnight (17:24Z → 01:44Z).
- **Launch → park:** s3-c 4 h 39 m, s3-d / s3-b / s3-a ~15 h — wall-clock dominated by the crash (13:40Z, resume 16:07Z)
  and the overnight wait, not by work.
- **Peak load:** 119 before the crash (3 lanes in `ci-local`); after the resume ≤ 7 observed by the monitor.

### Wave 2 result (closed 2026-10-07 ~04:13Z, operator session 2216aefd)
- **Merged:** wave PR #409 (`wave/s3w2`) by the owner with a merge commit, `f4b0732` (v15.124.0), 04:07:16Z; #408 (pa/11),
  #403 (agnostic/04), #402 (pa/16) flipped MERGED at 04:07:18Z; all three merge watchers closed out within ~60 s.
  Integration order #408 → #403 → #402 (`000b8e5`, `4e7fc8d`, `f67a6e8`), bump `88c3c02` last; ci-local 148/148 on the
  integrated tree. Drain of #409: READY in round 0 (claude-review posted "no new findings"; no fix cycle).
- **One conflict:** `RESULT_SCHEMAS.md` (#408 split it, #403 edited its AUTONOMOUS_RUN schema). Resolved in the merge
  commit: index kept, #403's four hunks applied verbatim to `result-schemas/autonomous-run.md` (+10/−3). **Touches gap:**
  agnostic/04 never declared `RESULT_SCHEMAS.md` (plus 5 other files outside its Touches, incl. a new `CLAUDE.md`
  Failure-Mode rule), so the planner's "wave 2 shares no file" was wrong — gap 7's sibling: Touches drift *during* a run.
  Table docs / `vendor-coupling-manifest.json`: no conflict.
- **pa/16 failed its own running-system Validation; operator fixed it on #402.** Three `ci-local --force` runs from three
  clones (2 GitHub-origin, 1 local-bare), staggered 30 s, were ALL admitted on a lagging `ok` (load1 3.5 → 13 at the
  grants) and drove load1 to **63.6** (operator kill switch at 60). Root cause: admission on load1 alone; load1 lags a
  suite's ramp ~1 min, and `ok` had no machine-wide cap. Fix `cd5f400`: committed-work cap in `machine_admit` (live
  holders' jobs + own ≤ CPUs, sole caller always admitted ⇒ ≤ 2 six-job suites on 12 CPUs) + test G12 with mutation
  control; (X)/(G7)/(G10) clear the machine list first. **Re-run:** C held 22 polls (`committed 12+6 jobs > 12 CPUs`),
  **peak load1 24.05**, all three PASS. `e9a3977` docs the cap (claude-review finding on `cd5f400`). The wave-2 "≤2
  lanes building" rule's premise is now enforced by the gate itself for `ci-local`.
- **Merge checks the operator ran (wave-1 lesson held: every PR's "Not verified" hid something):** #408 — both
  Validation-4 failure controls and the `revert -m 1` rollback re-run; #403 — AC1–4 + a **live probe** of the PO
  can't-ask branch (`claude -p --plugin-dir`, writes allowed: `po_gate: needs_owner`, nothing written, $0.37); #402 — the
  three-clone test above. Still unverified (in #409's body): #408's live sequential `/automate` on the split (first lane
  run on 15.124.0), #403's end-to-end `/automate` can't-ask stop, #402's Linux reader on a real host.
- **Cost (final `total_cost_usd` per lane session — it is cumulative across resumes, take the LAST value, never sum):**
  s3-e $38.80 · s3-f $55.24 · s3-g $52.24 · wave ≈ **$146.3** (+ $0.37 probe).
- **Questions:** 12 relayed calls (s3-e 3, s3-f 5, s3-g 4), ~40 individual answers; 3 brief decisions, 1 FINALIZE
  children-settled (7 turn-limit-stopped agents with no terminal lifecycle row — logging gap), 1 adjudication, the rest
  dismissed-finding decisions (s3-g alone: 12 in three batches). Longest wait: ~6.5 h overnight (~18:30Z → 00:26Z).
- **Launch → park:** s3-f 9 h 53 m, s3-g 9 h 52 m, s3-e 10 h 27 m — dominated by the overnight wait, not work.
- **Peak load:** 73 at 18:01Z (two lanes in `ci-local` + a lane worktree), 66 at 16:13Z (mostly an unrelated
  `Tray/hub` jest run, 11 workers). No crash. s3-g was started early on the owner's override (3 lanes building).
- **New gaps (file or fold into the queue):** (1) **start-up closeout race:** all three lanes finalized the SAME 13 old
  run files at start-up ~5 s apart; the first push won and the rest hit 13 `meta-push` conflicts each (records were
  duplicates; resolved by taking the branch copy before teardown) — pa/05 input. (2) the harness's `answer` refused valid
  **multiSelect** answers (fixed in `s1h.sh`: comma-joined labels, each validated; backup
  `archive/s1h.sh.backup-2026-10-07-pre-multiselect`). (3) relayed `note` text never reaches the lane (the hook passes
  only labels). (4) lane `ci-local` (~620 s) exceeds a lane's 600 s single-command limit (s3-e re-ran it). (5) the
  "Start new run?" question is asked inconsistently (s3-f asked, s3-e/s3-g did not). (6) s3-g armed two merge watchers
  (one per park); both exited cleanly, one closeout. (7) `caffeinate -t 14400` expired mid-wave again (16:50Z); the
  operator restarted it detached with `-t 28800` on the owner's go.
- **Records:** carried to `loomwright-meta` `f7709f0` (32 paths; s3-f by hand — its push failed the `home_path` scrub on
  `reconcile-status` lines and its brief). Lanes torn down, `leaks` empty, primary clean on `f4b0732`.

## Done when
All items in the queue (19 after the 2026-10-06 restructures) merged or closed by the owner, each wave's records on `loomwright-meta`, lanes torn down with `leaks`
empty, the measures above recorded in this file, and P2 (default lane count) revisited with S2 + S3 evidence.
