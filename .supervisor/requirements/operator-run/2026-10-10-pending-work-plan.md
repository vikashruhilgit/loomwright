# Pending-work plan — 2026-10-10

## Status: parked (operator-run plan: lives in `operator-run/` so folder intake never enqueues it; the backlog docs beside it are what `/automate --backlog` runs)

Ground truth was read on 2026-10-10 at about 12:15Z from the live repo, `gh` and the run files. Installed plugin: **15.126.0**. `main` is at `161ce27` (af/38 #455 merged).

---

## 1. Where things stand

### Open PRs
None.

### Run files (`.supervisor/automate/`)

| Run | State | What it needs |
|---|---|---|
| `automate-2026-10-10-094837` (af/38) | paused / `awaiting_go`, Queue empty, closed out by the merge watcher | Nothing by hand. The next `/automate` start finalizes it (`resume-glob --finalize`). |
| `automate-2026-09-30-054439` (af 11–21) | paused, Queue stale (14/17 folded into 32/33, 15 proposed, 16/18/19 done, 20/21 re-queued below) | **Archive** (§3 step 0.5). Every lane of every wave asks "Start new run?" over it; S3 counted that question 12 times. |
| `automate-2026-10-09-174540-L1` (af/37, PR #446 merged) | `awaiting_merge`; lane dir still present; requirement still `## Status: pending` | Lane close-out (§3 step 0.2) — this is also af/38's Validation 3. |
| `…-L2` (hc/02, #450 merged) and `…-L3` (ag/02, #445 merged) | `awaiting_merge` in the primary; lane dirs already removed; requirements already stamped (pre-merge stamp from 15.126.0) | Close out the primary copies (§3 step 0.3). |

### Why wave 1 (2026-10-09) did not close out or produce one combined PR
Two reasons, both by design in 15.126.0:

1. **No combined PR.** In a `--parallel` wave, each lane opens its own item PR against `main` and parks `ready_for_release` ("do not merge yet — wave open"). Nothing in the engine builds the wave branch or the release bump yet. That is **pa/21 Part A**, still pending. You built `wave/w1` and #454 by hand.
2. **No close-out after the merge.** A lane's READY park arms **no merge watcher**. `closeout-others` in the primary skips lane run files, and `lane-convert-ready` never ran `closeout`. af/38 (#455, merged today, **not yet released**) adds that: re-running `lane-convert-ready` on a merged lane now stamps the item done. It still has to be **triggered by hand** after the wave PR merges. pa/21 is the item that automates the whole wave close.

### Unfinished requirements — 15 real, 13 ready to run (after the 2026-10-10 merge)
All dependencies of these items are stamped done. On 2026-10-10 af/21, af/34 and ag/03 were merged into **af/39** (the originals are parked with a pointer), and tr/10 was re-scoped to its remaining docs work.

| Id | File | Size (Touches) | Ready? |
|---|---|---|---|
| pa/21 | `parallel-automate/21-fleet-operations.md` — wave close + split closeout + lane policy answers | 13 | yes — **do first** (automates the manual wave close) |
| pa/22 | `parallel-automate/22-split-automate-engine-surfaces.md` — split the shared engine files so engine items can run in parallel | 23 | yes — **do second** (removes most serialization) |
| af/36 | `automate-followups/36-s3-engine-fixes.md` | 31 | yes |
| **af/39** | `automate-followups/39-engine-hygiene.md` — merged item: Part A = af/34 (sweep + process registry + `/janitor`), Part B = ag/03 (run-lock liveness + guard-arm trace), Part C = af/21 (rules-seam false lines) | 35 | yes |
| af/20 | `automate-followups/20-automate-run-enum-gaps-and-sidecar-nested-check.md` | 6 | yes — re-scope at Plan Review: its `awaiting_go` part already exists on `main` |
| af/27 | `automate-followups/27-brief-closed-enumerations-and-pin-mutations.md` | 5 | yes |
| ag/05 | `agnostic-phase1/05-docs-and-hygiene-sweep.md` | 28 | yes — run **last** so its stale-wording sweep also covers what earlier items add |
| ch/01 | `churn-ledger/01-restated-lists-diverge-from-authority.md` | 2 | yes |
| ch/02 | `churn-ledger/02-classifier-unknowable-attribution.md` | 6 | yes |
| hc/03 | `host-contract/03-declare-host-mode-in-contract.md` | 5 | yes |
| pa/18 | `parallel-automate/18-backlog-board-and-right-size.md` | 30 | yes |
| tl/07 | `twin-loop/07-rules-baseline-remeasurement.md` | 2 | yes |
| tr/10 | `twin-remediation/10-harness-portability.md` — re-scoped 2026-10-10 to the written core contract + re-verified harness research (docs only); the `LOOMWRIGHT_ROOT` call-site migration is split out | 4 | yes |
| tr/08 | `twin-remediation/08-session-segmentation.md` | none declared | **no** — no `## Touches` / `## Depends on` (lint fails); strategic item, needs owner refinement |
| tr/09 | `twin-remediation/09-native-flow-adoption.md` | none declared | **no** — same as tr/08 |

### Not real work (no code run needed — triage only)
- **Shipped, never stamped** (reconcile-status found the merged PR): af/23 (#377), af/37 (#446), `supervisor-resume-state-lies.md` (#109), te/07 (#269).
- **Owner-abandoned, never stamped:** review-remediation/10, token-economy/06, twin-remediation/03, twin-remediation/06.
- **Top-level overview / plan / backlog docs** (not implementable): `*-overview.md`, `*-plan.md`, `_BACKLOG-*.md`, `invention-overview.md`, `loom-floor-ui-overview.md`, `final-state/00-overview.md`, `twin-loop/00-overview.md`, `twin-remediation/00-overview.md`, `host-contract/_BACKLOG.md`, `selvedge-extraction/_BACKLOG.md`.
- **Legacy items with brief-shipped / learning-loop history:** `auto-2026-06-17-*`, `auto-2026-06-18-*`, `auto-2026-09-06-030556-rules-audit-verb.md`, `local-twin-step5-apply.md`.
- **Two to confirm by you:** `2026-09-01-stranded-brief-residual-gaps.md` and `2026-08-22-092037-skills-layer-portability-probe.md`. I found no landing commit for either.
- **`proposed/`: 48 drafts** (dismissed-finding follow-ups and others). None is queued; triage when convenient.

---

## 2. Run order — 4 parallel waves + 1 sequential run

**Rule:** `--parallel` only when a wave really holds 2 or more items. Every single item goes into ONE plain sequential
`/automate` run (no lanes). A sequential run arms a merge watcher, so close-out after your merge is automatic (shown
on af/38, 2026-10-10). It needs no wave branch, no wave PR and no `lane-convert-ready` / `lane-remove`.

Each parallel backlog below was checked with `plan-waves --max 3` and plans as exactly ONE wave.

| # | Run | Items | Command | Who closes it |
|---|---|---|---|---|
| 0 | Phase 0 cleanup | release 15.127.0, close out wave-1 lanes, archive stale run, stamps | §3 Phase 0 | you + me (manual) |
| 1 | **W2** | pa/21, ch/01, tl/07 | `/loomwright:automate --backlog .supervisor/requirements/operator-run/2026-10-10-w2-backlog.md --parallel 3` | **manual wave close** (§3 checklist) — pa/21 is not built yet |
| 2 | **W3** | pa/22, hc/03 | `/loomwright:automate --backlog .supervisor/requirements/operator-run/2026-10-10-w3-backlog.md --parallel 2` | pa/21's automated wave close **if** W2's release is installed and the checks in §3 "Switch-over" pass; else the manual checklist |
| 3 | **W4** | ch/02, tr/10 | `… --backlog .supervisor/requirements/operator-run/2026-10-10-w4-backlog.md --parallel 2` | same as W3 |
| 4 | **W5** | af/27, af/20 | `… --backlog .supervisor/requirements/operator-run/2026-10-10-w5-backlog.md --parallel 2` | same as W3 |
| 5 | **Sequential** | af/39 → af/36 → pa/18 → ag/05 | `/loomwright:automate --backlog .supervisor/requirements/operator-run/2026-10-10-seq-backlog.md` (no `--parallel`) | automatic: merge watcher per item; you `--resume` for the next |
| — | later | tr/08, tr/09 (after refinement); `LOOMWRIGHT_ROOT` call-site migration (file it first) | sequential | automatic |

**Why this order**
- pa/21 first: it builds the automated wave close every later wave uses.
- pa/22 next: it splits the shared engine files.
- The 2-item waves follow.
- The engine items that collide with everything run last, one at a time, with ag/05's docs sweep at the very end so it
  also covers wording the earlier items add.
- The order between items with no dependency is free; the planner's conflicts only mean they can't run *at the same time*.

**Re-plan after W3 is installed:**
```
$H plan-waves <list of af/39, af/36, pa/18, ag/05, af/27, af/20> --max 3 --explain
```
If the pa/22 split lets some of the sequential items share a wave (for example af/39 ∥ pa/18), turn them into a
`--parallel` wave; otherwise keep the sequential run.

## 3. Steps, in order

`$P` = the installed plugin root, e.g. `~/.claude/plugins/cache/atelier/loomwright/<version>`. `H` = `bash $P/scripts/automate-helpers.sh`. All commands run from the repo root on a clean `main`.

### Phase 0 — one-time cleanup (manual, before W2; 0.1 must be released and installed before W2, so the lanes' close-out uses af/38)

**0.1 Release the four merged items.** The fragments for af/37, af/38, hc/02 and ag/02 sit in `changelog.d/`, all minor.
```
git checkout main && git pull --ff-only
git checkout -b chore/release-after-wave1
bash scripts/bump-version.sh            # folds 4 fragments, bumps plugin.json + marketplace.json (→ 15.127.0)
bash scripts/ci-local.sh && bash scripts/ci-local.sh --wait
git push -u origin HEAD && gh pr create --base main --fill
```
- Merge it, then reinstall the plugin and confirm the running version is the new one. Check the desktop install path, not `~/.claude/plugins/cache/` alone.
- Steps 0.2–0.3 need af/38's code, so they must run on the new version.

**0.2 Close out lane L1 (af/37)** — also af/38's Validation 3. Do this **before** 0.6, otherwise reconcile-status stamps af/37 instead.
```
grep '^## Status' .supervisor/requirements/automate-followups/37-done-stamp-before-merge.md   # before: pending
$H lane-convert-ready ../ai-agent-manager-lanes/automate-2026-10-09-174540/L1
grep '^## Status' .supervisor/requirements/automate-followups/37-done-stamp-before-merge.md   # after: done, PR #446
$H lane-remove ../ai-agent-manager-lanes/automate-2026-10-09-174540/L1
```
- **Expect:**
  - `lane-convert-ready` prints `already reads awaiting_merge`, the closeout lines, `; closeout complete` and `meta-pushed`.
  - The requirement shows the stamp inside the **lane clone** (`<L1 dir>/.supervisor/requirements/...`). The primary sees it after the next `meta-entry` pull.
  - Paste the before/after lines on #455 to close Validation 3.

**0.3 Close out the primary copies of L2 and L3.** For each run (`-L2` with PR #450 and hc/02; `-L3` with PR #445 and ag/02):
```
$H closeout .supervisor/automate/automate-2026-10-09-174540-L2.md .supervisor/requirements/host-contract/02-host-mode-no-repo-writes.md https://github.com/vikashruhilgit/loomwright/pull/450
$H finalize-empty .supervisor/automate/automate-2026-10-09-174540-L2.md
```
- **Expect:** `skipped — already stamped`, `checked`, `reconciled`, then `finalized`.
- **Not verified:** this path (a lane run file closed out from the primary) has never been run. If `closeout` or `finalize-empty` refuses, stop and tell me the line.

**0.4 af/38 run:** nothing by hand. The first `/automate` start of W2 finalizes it.

**0.5 Archive the stale run `automate-2026-09-30-054439`.** There is no helper, so use the same shape as earlier archived runs:
```
RF=.supervisor/automate/automate-2026-09-30-054439.md
sed 's/^## Status: paused/## Status: done/' "$RF" | $H runfile-write "$RF"
$H current-set "$RF" --pause-reason null
$H progress-append "$RF" "$(date -u +%FT%TZ) archived by owner — queue stale: 14/17 folded into 32/33, 15 proposed, 16/18/19 done, 20/21 re-queued in pending-work-plan-2026-10-10"
```

**0.6 Stamp the shipped and abandoned items:**
```
$H reconcile-status .supervisor/requirements            # dry run: expect 7 plan rows (af/23, srsl, te/07, 4 ABANDONED)
$H reconcile-status .supervisor/requirements --apply
```

**0.7 Your triage (no automation):**
- Decide `stranded-brief-residual-gaps` and `skills-layer-portability-probe`: run them, or stamp them ABANDONED/SUPERSEDED.
- Optionally move the overview/plan docs into an `archive/` folder so folder intake never sees them.

**0.8 Old lane dir** `../ai-agent-manager-lanes/automate-2026-10-08-033739` (abandoned s3-validation lanes, has `salvage/`): check `salvage/`, then delete it.

### Wave-close checklist — from W3 on (v15.128.1: pa/21 + automate-followups/40 installed)

Updated 2026-10-11 after reading the INSTALLED v15.128.1 `automate-loop` SKILL §14 ("The per-wave loop" steps 9–10,
"Wave close") and `automate-lanes.sh` `lanes_fleet_closeout`. W2 was closed with the old manual list (record:
coordinator run `automate-2026-10-10-194230`, wave PR #465). **Nothing below is verified in a running system yet** —
W3 is the first wave on this engine, so each automated step keeps its manual fallback until W3 has shown it works.

1. **[you]** Launch in a fresh session on the installed version (confirm the app runs 15.128.1):
   `/loomwright:automate --backlog .supervisor/requirements/operator-run/2026-10-10-wN-backlog.md --parallel <n>`.
2. **[me]** Relay lane questions verbatim. NEW: routine gates (resume, Queue confirm, summary drafts, Launch Pad save on
   a clean PASS, Supervisor children-unsettled) can be pre-answered by a wave policy (`lane-policy.sh wave-set`) that you
   choose at the per-wave step 4 ask; `lane-status <run file> --inbox` batches the rest, oldest first.
   **Watch:** with automate-followups/40 installed, a lane that asked questions should reach FINALIZE point 5 with every
   child settled — no `--skip-children-check`. If it still asks, D1 is not fixed in practice; stop and tell me.
3. **[me]** Wave end: `lane-convert-ready <lane_dir>` per lane (→ `awaiting_merge`, metadata pushed) — unchanged, the
   engine step 9 precondition. A `forge_slug` scrub hit on a cut-off readiness URL should no longer happen (af/40 D3).
4. **[me]** Merge checks per lane PR — unchanged, judgment: Not-verified steps, scope fence (the readiness report's
   `scope-fence` line), `ci` + `claude-review` green on the **current** head, last bot comment read, every dismissed
   finding decided.
5. **[me prints, you/me run]** Build the wave PR. NEW: `$H wave-plan <parent run file> [--wave-branch wave/wN]` prints the
   exact commands (read-only): fetch, `git checkout -b <branch> origin/main`, one `git merge --no-ff <exact PR head sha>
   -m "Merge lane <L> (<item>) PR #<n>"` per lane in planner order, `bash scripts/ci-local.sh`, `bash
   scripts/bump-version.sh` as the LAST commit, push, `gh pr create`, plus the conflict rules. The merges stay manual
   (your pa/21 Part S decision: operator merges; the engine never merges or pushes a lane branch). Then optionally
   `/review-pr <wave PR> --until-mergeable`.
6. **[you]** Merge the wave PR with **"Create a merge commit"** (never squash). Every lane PR flips to MERGED.
7. **[me]** Lane close-out — NOW AUTOMATED: `/loomwright:automate --resume <coordinator run_id>` re-runs
   `lane-convert-ready` per merged lane (done stamp + lane finalize + pushes), then `fleet-closeout <parent run file>`:
   backstop per merged lane, parent Queue check-off, primary `git pull --ff-only`, `lane-remove` per closed-out lane,
   leak check, main `ci` health, and — once the parent Queue has no `- [ ]` — releases the `automate-lanes` lock
   (`fleet-closeout: wave closed — lock released`). Stepwise: re-run `--resume` until that line prints.
   - A `human — …` line (PR closed unmerged ⇒ `lane-remove <lane_dir> --abandon`; a lane `meta-push-failed`) is yours.
   - Fallback if it misbehaves: the old manual pair, `$H lane-convert-ready <lane_dir>` then `$H lane-remove <lane_dir>`.
8. **[me] STILL MANUAL — finalize the coordinator run.** `fleet-closeout` releases the lock but does NOT write the parent
   `## Status: done`, clear its `- wave:` line, or push its trail (read in `lanes_fleet_closeout`, 2026-10-11). Same as W2:
   `current-wave <rf> --wave null`; `sed 's/^## Status: running$/## Status: done/' <rf> | $H runfile-write <rf>`;
   `current-set <rf> --pause-reason null`; `trail-pr <rf> --reason done`. Then stop the fleet sampler
   (`pkill -f 'lane-sample[r]\.sh.*<run_id>'`) — it only exits with the coordinator session.
9. **[you]** Release + reinstall when the wave carried code (the bump is already the wave branch's last commit), confirm
   the running version, and start the next run in a **fresh** session.

### Switch-over record (pa/21 took over the wave close in v15.128.0)
- Automated now: step 7 (lane close-out, parent check-off, lane removal, leaks, lock release) and the integration
  command list in step 5 (`wave-plan`, print only).
- Still manual: step 5's merges (owner decision), step 6 (always yours), step 8 (parent run finalize — a gap pa/21 did
  not cover; candidate follow-up), and all judgment in step 4.

## 4. Manual steps that stay manual (and which item removes each)

| Manual step | Why it is manual today | Removed by |
|---|---|---|
| Running the wave-branch merges, release bump, one wave PR | Owner decision at pa/21's Plan Review: the engine never merges | `wave-plan` (pa/21, v15.128.0) now PRINTS the exact commands; running them stays manual by design |
| Re-running `lane-convert-ready` + `lane-remove` after the wave PR merges | — | **Removed** by pa/21 `fleet-closeout` (v15.128.0) — run `--resume` until `wave closed — lock released`; unverified until W3 |
| Finalizing the coordinator run (`## Status: done`, clear `- wave:`, `trail-pr --reason done`) | `fleet-closeout` releases the lock but never finalizes the parent run | Not yet filed — candidate follow-up |
| Merging every PR | Safe mode; auto-merge is refused with `--parallel` | Never — by design |
| Merge checks (Not-verified steps, scope fence, last bot comment) | Judgment | Partly pa/21 Part B / af/36 |
| Merging serialized items into fewer, larger ones (done by hand for af/39) | No helper yet | pa/18 Part B (`merge-items`) |
| Reinstalling the plugin between waves, fresh session per wave | Lanes run the installed version | — |
| Launch / resume typed by you in the same session | Launch-authority rule | — |
| Meta-push `home_path` scrub fixes | Scrub is correct to refuse | — |
| Routine lane questions (start new run, 1-item queue confirm, save brief on 0-issue PASS) | Gates fire per lane | pa/21 Part B (v15.128.0): the 1-item confirm is gone; the rest can be pre-answered by a wave policy you choose per wave |
| tr/08, tr/09 refinement | No Touches / Depends on sections | You (or `/product-owner` / Launch Pad on each) |

## 5. Risks to watch
- **`claude-review` weekly subscription cap.** A 1-turn, $0 failure means the cap, not the PR. Several lanes draining at once burn it fast.
- **Actions billing / spending limit** on `vikashruhilgit`. Re-check the latest run, not an older one.
- **Vendor-coupling manifest.** It conflicts across lanes even though most items do not declare it. Expect a conflict on the wave branch.
- **Mid-queue upgrades.** Never reinstall while a lane is live.
