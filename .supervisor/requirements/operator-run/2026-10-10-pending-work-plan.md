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

### Wave-close checklist — every `--parallel` wave until pa/21 is released AND installed

Nothing in the installed engine (15.126.0 / 15.127.0) merges lane PRs, builds a wave PR or closes out lanes after the
merge. So every multi-item wave ends with these steps. I (the coordinator session) run every step marked **[me]**; you
run every step marked **[you]**. Nothing is pushed to `main` and nothing is merged by me.

1. **[you]** Launch in a fresh session on the installed version:
   `/loomwright:automate --backlog .supervisor/requirements/operator-run/2026-10-10-wN-backlog.md --parallel <n>`.
   The launch must be typed by you (launch-authority rule).
2. **[me]** Relay lane questions verbatim (≤4 per question). Poll with `/loomwright:automate --resume <coordinator run_id>`
   until every lane reads `ready_for_release`.
3. **[me]** Wave end: run `lane-convert-ready <lane_dir>` per lane (→ `awaiting_merge`, metadata pushed). On a
   `meta-push … home_path` failure, rewrite the home paths, then re-run.
4. **[me]** Merge checks per lane PR:
   - every "Not verified" running-system step run in a scratch clone;
   - scope fence = Touches + companions;
   - `ci` + `claude-review` green on the **current** head;
   - the last bot comment read;
   - every dismissed finding decided (**[you]** answer).
5. **[me]** Build the wave PR:
   ```
   git checkout main && git pull --ff-only && git checkout -b wave/wN
   git merge --no-ff <lane PR head sha>          # each lane, planner order; conflicts resolved HERE only
   bash scripts/ci-local.sh && bash scripts/ci-local.sh --wait
   bash scripts/bump-version.sh                  # LAST commit: one release per wave (folds every changelog.d fragment)
   git push -u origin wave/wN
   gh pr create --base main --head wave/wN --title "wave wN: <items> + release" --body "<lane PRs, merge checks, Not verified>"
   ```
   - If wave CI breaks a lane, fix it on that lane's PR branch and re-merge its new head.
   - Then run `/review-pr <wave PR> --until-mergeable` (the drain) on the wave PR.
6. **[you]** Merge the wave PR with **"Create a merge commit"** (never squash). Every lane PR flips to MERGED.
7. **[me]** Lane close-out — the step wave 1 missed. Lanes have no merge watcher, so for each lane:
   ```
   $H lane-convert-ready <lane_dir>   # merged re-run: closeout --no-trail inside the lane → requirement stamped done, trail pushed
   $H lane-remove <lane_dir>
   ```
   - A `; closeout leftover: …` suffix other than `gate — … pr not merged` ⇒ do NOT `lane-remove`. Fix it first.
   - Then confirm each item's `## Status: done` and that the coordinator run reads done.
8. **[you]** Reinstall the released version, confirm the running version, and start the next run in a **fresh** session.

### Switch-over: when pa/21 takes over the wave close
W2's wave branch carries pa/21 **and** the release bump, so W3 can run on an engine that has pa/21. Before W3, I read
the installed `automate-loop` SKILL §14 and pa/21's merged PR, and drop from the checklist only the steps it really
automates (expected: steps 5 and 7, and step 3's conversion). Two cases keep a step manual:
- **Step 5 integration merges.** These stay manual if you decided at pa/21's Plan Review that the coordinator may NOT
  merge into `wave/*`. In that case pa/21 prepares and you or I run the merges.
- **Step 6, merging the wave PR into `main`.** Always yours.

Never assume a step is automated: verify it on the first wave that uses it, and keep the manual step as the fallback.

### Sequential run (single items)
```
/loomwright:automate --backlog .supervisor/requirements/operator-run/2026-10-10-seq-backlog.md      # no --parallel
```
- Each item: PR → review drain → park `awaiting_merge` → merge watcher armed.
- **[you]** merge (squash is fine) → the watcher closes it out by itself: requirement stamped, branch removed,
  `main` synced, trail pushed.
- **[you]** type `/loomwright:automate --resume` for the next item.
- **Release:** the fragments wait in `changelog.d/`. Run `bash scripts/bump-version.sh` as its own PR when the run
  finishes, or let the next wave branch's bump fold them in.

## 3b. The parallel-automate track (pa/21, pa/22, pa/18)

This track is the backbone of the wave order above:
- **pa/21 runs in W2.** Its wave close and lane-question policy then help every wave after it, once it is released and installed.
- **pa/22 runs in W3.** It splits the engine files so later engine items stop colliding.
- **pa/18 runs after the W3 re-plan.** It re-points its Touches at the split files.

Decide before pa/21's Plan Review: may the coordinator run the integration merges into `wave/*` itself? This is Part S item 4, and it touches the single-merge-executor invariant.

## 4. Manual steps that stay manual (and which item removes each)

| Manual step | Why it is manual today | Removed by |
|---|---|---|
| Building the wave branch, release bump, one wave PR | Engine opens one PR per lane only | pa/21 Part A (open owner decision: may the coordinator merge into `wave/*`? Decide it at pa/21's Plan Review) |
| Re-running `lane-convert-ready` + `lane-remove` after the wave PR merges | Lanes arm no merge watcher; `closeout-others` skips lane runs | pa/21 (split closeout / fleet-closeout backstop) |
| Merging every PR | Safe mode; auto-merge is refused with `--parallel` | Never — by design |
| Merge checks (Not-verified steps, scope fence, last bot comment) | Judgment | Partly pa/21 Part B / af/36 |
| Merging serialized items into fewer, larger ones (done by hand for af/39) | No helper yet | pa/18 Part B (`merge-items`) |
| Reinstalling the plugin between waves, fresh session per wave | Lanes run the installed version | — |
| Launch / resume typed by you in the same session | Launch-authority rule | — |
| Meta-push `home_path` scrub fixes | Scrub is correct to refuse | — |
| Routine lane questions (start new run, 1-item queue confirm, save brief on 0-issue PASS) | Gates fire per lane | pa/21 Part B (policy answers); step 0.5 removes the stale-run one now |
| tr/08, tr/09 refinement | No Touches / Depends on sections | You (or `/product-owner` / Launch Pad on each) |

## 5. Risks to watch
- **`claude-review` weekly subscription cap.** A 1-turn, $0 failure means the cap, not the PR. Several lanes draining at once burn it fast.
- **Actions billing / spending limit** on `vikashruhilgit`. Re-check the latest run, not an older one.
- **Vendor-coupling manifest.** It conflicts across lanes even though most items do not declare it. Expect a conflict on the wave branch.
- **Mid-queue upgrades.** Never reinstall while a lane is live.
