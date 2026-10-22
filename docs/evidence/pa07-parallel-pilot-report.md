# PA07 — Parallel pilot report: run `automate-2026-10-15-163325` (`--parallel 4`)

The owner decided on 2026-10-22 that this run is the parallel pilot (`.supervisor/requirements/parallel-automate/07-pilot-and-docs.md`, "Re-scoped 2026-10-22"). This report is built **only** from that run's record. It estimates nothing. Where the record does not carry a figure, this report says so.

## Source and citation convention

- **Parent run file:** `git show origin/loomwright-meta:.supervisor/automate/automate-2026-10-15-163325.md`. It has 242 lines and `## Status: done` (line 2), and it reached the metadata branch in commit `5db7ec0`. The same bytes are synced under `.supervisor/automate/` in the primary checkout, checked with `diff` on 2026-10-22.
- **Lane run files:** `.supervisor/automate/automate-2026-10-15-163325-L<n>.md` for n = 1…25, on the same branch.
- **Citation forms:**
  - **`[P 42 · 2026-10-15T11:18:11Z]`** is the parent file's `## Progress` line at file line 42, carrying that timestamp.
  - **`[P 52 · "fleet closeout: L1 …"]`** quotes a `## Progress` line that has no timestamp.
  - **`[L7 · 2026-10-16T02:57:59Z]`** is a `## Progress` line in lane file L7 with that timestamp.
- **Line numbers are stable.** The parent and every lane file read `## Status: done` (L5 reads `paused`), and `## Progress` is append-only.
- **Durations are computed, never hand-added.** Each one is the difference of two cited timestamps.

**The brief's wave-PR list differs from the record.** The brief and the requirement name the wave PRs "#567, #596, #606, #631, #641, #651". The record shows something else:
- Wave 2's PR is **#582** [P 90 · 2026-10-16T10:26:56Z].
- Wave 5's PR is **#614** [P 162 · 2026-10-19T04:38:16Z].
- **#651** is wave 8's *lane* PR, which the owner merged directly with no wave PR [P 236 · 2026-10-21T06:06:42Z; P 242 · 2026-10-21T06:15:44Z].

This report follows the record.

Run shape: 24 Queue items [P 38 · 2026-10-15T11:03:25Z "24 items, --parallel 4"], `mode: safe` with no `--auto-merge` (line 6), `parallel: 4` (line 8), 8 waves, 25 lanes (L1–L25; L5's item was re-run in L9 [P 65 · 2026-10-16T03:20:03Z]).

## 1. Wall-clock: first PICK to merge, per wave and overall

- **First PICK** is the earliest `picked …` line across the wave's lane files.
- **All lanes parked** is the parent's "wave N end" line.
- **Wave PR opened** is the parent's `wave built:` line.
- **Merge** is the parent line that first records the wave PR as MERGED. Only wave 2's line carries GitHub's merge time ("#582 MERGED 2026-10-16T11:27:06Z" [P 91 · 2026-10-17T03:54:43Z]). Every other merge time below is when the coordinator *recorded* the merge, so it is an upper bound on the real merge time. The record holds nothing finer.

| Wave | Items (lanes) | First PICK | All lanes parked | Wave PR opened | Merge (recorded) | First PICK → merge |
|---|---|---|---|---|---|---|
| 1 | 25, 04, 05, 17 (L1–L4) | 2026-10-15T11:19:11Z [L1 · 2026-10-15T11:19:11Z] | 2026-10-15T23:29:49Z [P 48] | 2026-10-16T00:12:45Z, #567 [P 50] | 2026-10-16T01:44:08Z [P 51] | 14h 24m 57s |
| 2 | 13, 03, 19, 06 (L6–L9; L5 parked) | 2026-10-16T02:56:57Z [L6 · 2026-10-16T02:56:57Z] | 2026-10-16T09:41:06Z [P 87] | 2026-10-16T10:26:56Z, #582 [P 90] | 2026-10-16T11:27:06Z, exact [P 91] | 8h 30m 09s |
| 3 | 07 (L10) | 2026-10-17T04:31:26Z [L10 · 2026-10-17T04:31:26Z] | 2026-10-17T11:45:46Z [P 107] | 2026-10-17T12:00:12Z, #596 [P 108] | 2026-10-17T13:56:52Z [P 111] | 9h 25m 26s |
| 4 | 11, 12, 20, 08 (L11–L14) | 2026-10-17T14:16:43Z [L11 · 2026-10-17T14:16:43Z] | 2026-10-18T09:55:34Z [P 132] | 2026-10-18T10:29:16Z, #606 [P 134] | 2026-10-18T10:59:39Z [P 140] | 20h 42m 56s |
| 5 | 14, 15, 21, 23 (L15–L18) | 2026-10-18T17:58:49Z [L15 · 2026-10-18T17:58:49Z] | 2026-10-19T04:19:13Z [P 160] | 2026-10-19T04:38:16Z, #614 [P 162] | 2026-10-19T07:51:11Z [P 173] | 13h 52m 22s |
| 6 | 09, 22 (L19, L20) | 2026-10-19T19:16:30Z [L19 · 2026-10-19T19:16:30Z] | 2026-10-20T02:31:44Z [P 188] | 2026-10-20T03:13:01Z, #631 [P 191] | 2026-10-20T04:44:31Z [P 195] | 9h 28m 01s |
| 7 | 10, 16, 24, 26 (L21–L24) | 2026-10-20T05:34:23Z [L21 · 2026-10-20T05:34:23Z] | 2026-10-20T13:20:13Z [P 218] | 2026-10-20T14:02:44Z, #641 [P 222] | 2026-10-20T14:30:45Z [P 227] | 8h 56m 22s |
| 8 | 18 (L25) | 2026-10-21T02:49:22Z [L25 · 2026-10-21T02:49:22Z] | 2026-10-21T05:39:18Z [P 234] | none, owner skipped the wave PR [P 236] | 2026-10-21T06:15:44Z, lane PR #651 [P 242] | 3h 26m 22s |

**Overall:** first PICK 2026-10-15T11:19:11Z [L1] to last merge recorded 2026-10-21T06:15:44Z [P 242] = **5d 18h 56m 33s** (500193 s).

**The spans include pauses, and none is subtracted.** The record names these pauses but cannot separate idle time from work inside a lane:

- **Waiting on owner answers inside a wave.** Example: wave 1's brief-save answers were relayed at [P 44 · 2026-10-15T15:53:59Z], and L1's dismissed-findings decisions at [P 46 · 2026-10-15T23:27:38Z]. The record does not log when each question was *asked*, so the wait cannot be measured (see §10).
- **The weekly usage limit inside wave 4.** It ran from [P 117 · 2026-10-17T18:51:56Z] to [P 119 · 2026-10-18T03:59:47Z], which is 9h 07m 51s by the parent's lines. The lanes' own rows date the cap earlier, from 2026-10-17T15:29:46Z [L12 · 2026-10-18T08:35:04Z] (see §8).
- **Owner pauses between waves.** These sit outside every per-wave span but inside the overall span:

| Gap | Wave close line | Next wave's first PICK | Interval |
|---|---|---|---|
| after wave 1 | [P 57 · 2026-10-16T01:45:36Z] | [L6 · 2026-10-16T02:56:57Z] | 1h 11m |
| after wave 2 | [P 100 · 2026-10-17T03:59:29Z] | [L10 · 2026-10-17T04:31:26Z] | 0h 31m |
| after wave 3 | [P 111 · 2026-10-17T13:56:52Z] | [L11 · 2026-10-17T14:16:43Z] | 0h 19m |
| after wave 4 | [P 140 · 2026-10-18T10:59:39Z]; owner paused [P 141] | [L15 · 2026-10-18T17:58:49Z] | 6h 59m |
| after wave 5 | [P 174 · 2026-10-19T07:57:57Z]; owner paused [P 175] | [L19 · 2026-10-19T19:16:30Z] | 11h 18m |
| after wave 6 | [P 195 · 2026-10-20T04:44:31Z]; owner paused [P 196] | [L21 · 2026-10-20T05:34:23Z] | 0h 49m |
| after wave 7 | [P 228 · 2026-10-20T14:34:55Z]; owner paused for follow-up fixes [P 229] | [L25 · 2026-10-21T02:49:22Z] | 12h 14m |

Wave 2 was merged at 2026-10-16T11:27:06Z [P 91], but the parent has no line between [P 90 · 2026-10-16T10:26:56Z] and the next coordinator resume at 2026-10-17T03:54:43Z [P 91]. Its close line therefore comes about 16 hours after the merge.

## 2. PRs opened

- **Lane PRs: one per item, 24 in total.** Each is named on a `fleet closeout:` line:
  - wave 1: #562 #559 #558 #565 [P 52–55]
  - wave 2: #573 #570 #577 #575 [P 94–97]
  - wave 3: #594 [P 109]
  - wave 4: #601 #600 #598 #599 [P 135–138]
  - wave 5: #613 #611 #609 #607 [P 169–172]
  - wave 6: #628 #626 [P 193–194]
  - wave 7: #632 #636 #635 #634 [P 223–226]
  - wave 8: #651 [P 237]

  L5 opened no PR: Launch Pad was blocked [L5 · 2026-10-16T03:15:29Z].
- **Wave PRs: one per wave for waves 1–7, so 7.** They are #567 [P 50], #582 [P 90], #596 [P 108], #606 [P 134], #614 [P 162], #631 [P 191] and #641 [P 222]. Each `wave built:` line names its release (v17.4.0, v17.5.0, v17.7.0, v17.8.0, v17.9.0, v17.11.0, v17.12.0).
- **Wave 8 had no wave PR.** The owner merged lane PR #651 directly and moved the release bump to a separate PR [P 236 · 2026-10-21T06:06:42Z]. Release PR #654 was opened afterwards [P 242 · 2026-10-21T06:15:44Z].
- **Metadata PRs: 0.** No lane file or parent line records a trail PR being opened. Lane run history went to the metadata branch instead:
  - 22 lane files carry `trail-pr: meta-pushed loomwright-meta`.
  - L16's line adds an exclusion (`excluded …L16.supervisor-result.md — … checks_total`).
  - L3's last trail line is a FAILED push, which was re-pushed by hand [P 51].
  - L5's metadata was pushed by the coordinator as `29d7941` [P 65].
  - Command: `grep -h "trail-pr:" .supervisor/automate/automate-2026-10-15-163325-L*.md | sed -E 's/^- [0-9TZ:-]+ //' | sort | uniq -c`.
- **Opened between waves, outside the Queue (not counted above):**
  - #590, the lane-number cap fix [P 113]
  - #619 #620 #622 #623 and release #625 [P 176]
  - #643–#647, #648 and release #649 [P 230]

So the shipped shape held for waves 1–7: one PR per item plus one wave PR per wave carrying the version bump. Wave 8 departed from it by the owner's choice, not by a defect.

## 3. Drain ownership per lane

- **Every lane suppressed the default drain.** All 24 lane files that reached a PR carry `suppressed_default_dispatch: true` in `## Current`. Each lane's own `## Run Config` names its own `config_backup` (e.g. L1 line 7: `config_backup: automate-2026-10-15-163325-L1.config-backup.json`). The drain toggle and its backup were per lane. Command: `grep -l "suppressed_default_dispatch: true" .supervisor/automate/automate-2026-10-15-163325-L*.md | wc -l` → 24.
- **Each lane owned at most one drain plus one fix-now re-drain.** Running `grep -c "owned drain started"` per lane file gives 1 for 23 lanes, 0 for L5 (no PR) and **2 for L7**. L7's second drain is the owner's fix-now re-drain: "L7 PR #570 4× dismissed findings 'Fix now on this PR'" [P 72 · 2026-10-16T05:41:04Z], then "L7 ready_for_release PR #570 (after 4× fix-now re-drain …)" [P 76 · 2026-10-16T06:30:02Z]. Every lane stayed within one owned drain plus at most one fix-now re-drain.
- **Nothing in the run merged a PR.** The run had `mode: safe` and no `--auto-merge` (parent line 6). The owner merged every wave PR, and lane PR #651 [P 236].

## 4. Lane parks and their causes

### Terminal parks

"Open at park" lists what the lane still carried when it parked.

| Lane | Item | PR | Park | Parent line | Open at park |
|---|---|---|---|---|---|
| L1 | 25 | #562 | `ready_for_release` [L1 · 2026-10-15T23:26:57Z] | [P 47 · 2026-10-15T23:28:10Z] | 3× follow-up [P 46] |
| L2 | 04 | #559 | `ready_for_release` [L2 · 2026-10-15T13:45:21Z] | [P 44 · 2026-10-15T15:53:59Z] | — |
| L3 | 05 | #558 | `ready_for_release` [L3 · 2026-10-15T15:54:14Z] | [P 45 · 2026-10-15T15:54:59Z] | dismissed draft kept as follow-up [P 44] |
| L4 | 17 | #565 | `ready_for_release` [L4 · 2026-10-15T23:27:58Z] | [P 48 · 2026-10-15T23:29:49Z] | 2× follow-up [P 46] |
| **L5** | 06 | none | **`escalated`** [L5 · 2026-10-16T03:15:34Z] | [P 64 · 2026-10-16T03:16:28Z] | Launch Pad blocked: Plan Review FAIL×3, owner chose 'Refine offline'. Re-run in L9 after the requirement was fixed [P 65] |
| L6 | 13 | #573 | `ready_for_release` [L6 · 2026-10-16T06:11:24Z] | [P 75 · 2026-10-16T06:12:15Z] | V3 waived [P 73]; 2× follow-up [P 74] |
| L7 | 03 | #570 | `ready_for_release` [L7 · 2026-10-16T06:29:10Z] | [P 76 · 2026-10-16T06:30:02Z] | after the 4× fix-now re-drain |
| L8 | 19 | #577 | `ready_for_release` [L8 · 2026-10-16T08:43:49Z] | [P 83 · 2026-10-16T08:45:14Z] | 2× follow-up [P 79] |
| L9 | 06 | #575 | `ready_for_release` [L9 · 2026-10-16T09:38:44Z] | [P 86 · 2026-10-16T09:40:05Z] | Supervisor heal ESCALATED `max_iterations_reached` [L9 · 2026-10-16T09:05:19Z]; 3× follow-up [P 85] |
| L10 | 07 | #594 | `ready_for_release` [L10 · 2026-10-17T11:44:33Z] | [P 107 · 2026-10-17T11:45:46Z] | 3× follow-up [P 106] |
| L11 | 11 | #601 | `ready_for_release` [L11 · 2026-10-18T07:58:28Z] | [P 126 · 2026-10-18T07:59:34Z] | V3 waived; Phase 4.5 ESCALATED needs_human (AC7) + 1 MEDIUM [P 124] |
| L12 | 12 | #600 | `ready_for_release` [L12 · 2026-10-18T09:04:23Z] | [P 129 · 2026-10-18T09:05:00Z] | 8× follow-up [P 127–128] |
| L13 | 20 | #598 | `ready_for_release` [L13 · 2026-10-18T07:49:47Z] | [P 125 · 2026-10-18T07:58:09Z] | V2 waived [P 122]; 4× follow-up [P 123] |
| L14 | 08 | #599 | `ready_for_release` [L14 · 2026-10-18T09:53:25Z] | [P 132 · 2026-10-18T09:55:34Z] | V3 waived; Phase 4.5 ESCALATED max iterations [P 130]; 1× follow-up [P 131] |
| L15 | 14 | #613 | `ready_for_release` [L15 · 2026-10-19T04:17:21Z] | [P 160 · 2026-10-19T04:19:13Z] | V3 waived with note [P 157]; 5× follow-up [P 158–159] |
| L16 | 15 | #611 | `ready_for_release` [L16 · 2026-10-19T02:57:49Z] | [P 156 · 2026-10-19T02:58:33Z] | V3 waived with note; Phase 4.5 NEEDS_HUMAN + 3 MEDIUM [P 153, 155] |
| L17 | 21 | #609 | `ready_for_release` [L17 · 2026-10-19T02:56:21Z] | [P 154 · 2026-10-19T02:57:17Z] | 4× follow-up [P 152] |
| L18 | 23 | #607 | `ready_for_release` [L18 · 2026-10-18T19:38:19Z] | [P 150 · 2026-10-18T19:39:00Z] | 2× follow-up [P 149] |
| L19 | 09 | #628 | `ready_for_release` [L19 · 2026-10-20T02:30:20Z] | [P 188 · 2026-10-20T02:31:44Z] | V2 waived with note [P 182]; 11× follow-up [P 184, 186, 187] |
| L20 | 22 | #626 | `ready_for_release` [L20 · 2026-10-20T02:23:53Z] | [P 185 · 2026-10-20T02:24:57Z] | V2 waived with note [P 181]; 2× follow-up [P 183] |
| L21 | 10 | #632 | `ready_for_release` [L21 · 2026-10-20T09:52:46Z] | [P 206 · 2026-10-20T09:53:45Z] | Phase 4.5 ESCALATED, AC6 not asked by the lane; readiness 2/5, V1 NOT-RUN [P 206] |
| L22 | 16 | #636 | `ready_for_release` [L22 · 2026-10-20T13:18:10Z] | [P 218 · 2026-10-20T13:20:13Z] | V3 waived with note [P 216]; heal ESCALATED AC4 partial, `high_risk` [P 215] |
| L23 | 24 | #635 | `ready_for_release` [L23 · 2026-10-20T12:04:15Z] | [P 214 · 2026-10-20T12:05:20Z] | V2 waived with note [P 212]; 2× follow-up [P 213] |
| L24 | 26 | #634 | `ready_for_release` [L24 · 2026-10-20T10:52:31Z] | [P 211 · 2026-10-20T10:53:23Z] | V3 waived with note [P 207]; 4× follow-up [P 209] |
| L25 | 18 | #651 | `ready_for_release` [L25 · 2026-10-21T05:37:58Z] | [P 234 · 2026-10-21T05:39:18Z] | 1 dismissed summary kept as follow-up [P 234] |

Six lanes parked READY with a Phase 4.5 or heal escalation still open: L9, L11, L14, L16, L21 and L22. Each drain was READY, and the owner merged every one by hand. This report does not read a READY drain over an open escalation as reviewer-clean.

### Non-terminal stops (lane did not finish without a hand)

| Wave | Lane(s) | Stop | Cause | Line |
|---|---|---|---|---|
| 1 | L2–L4 | `HELD` at launch | machine load busy; launched on the staggered retry | [P 42 · 2026-10-15T11:18:11Z], [P 43 · 2026-10-15T11:21:46Z] |
| 2 | L6–L8 | `HELD` at launch | machine load busy | [P 61 · 2026-10-16T02:54:42Z], [P 62 · 2026-10-16T02:58:21Z] |
| 2 | L8 | could not exit deferred | a lane-internal background until-loop polled a finished plan-reviewer transcript and never became true; the coordinator stopped it | [P 67 · 2026-10-16T03:51:13Z] |
| 2 | L8 | not parked on its question | it ended one more plain turn; resumed with `--continue` to ask again | [P 68 · 2026-10-16T03:52:12Z], [P 69 · 2026-10-16T03:54:12Z] |
| 2 | L8 | human gates | pre-flight OVERLAP 'proceed-anyway'; Phase 3 adjudication 'D'; SUP-CHILDREN 'proceed anyway' | [P 70], [P 77], [P 78] |
| 2 | L8 | could not exit deferred | a background `notify-desktop.sh` blocked on stdin for 10 min; resumed with `--continue` | [P 80 · 2026-10-16T08:40:56Z] |
| 2 | L9 | could not exit deferred | a background `notify-desktop.sh` hung 24 min (stdin never closed); resumed with `--continue` | [P 84 · 2026-10-16T09:36:24Z] |
| 3 | L11–L13 | refused at `lane-create` | the lane-number cap allowed only 1..10 per run, and L1–L9 were used; wave 3 narrowed to item 07 | [P 102 · 2026-10-17T04:29:46Z] |
| 4 | L11 died; L12–L14 stalled | weekly usage limit | account-wide cap (§8) | [P 117 · 2026-10-17T18:51:56Z] |
| 4 | L13 | SUP-CHILDREN 'proceed anyway' | a subtask-3 worker hit its turn limit | [P 120 · 2026-10-18T05:30:38Z] |
| 4 | L13 | answer `HELD` | load overloaded (load1 ~31 on 12 cpus) | [P 121 · 2026-10-18T05:32:14Z] |
| 5 | L15 | 'Finish via legacy' | `supervisor-next-step.sh` parsed nested File Impact Map rows as subtasks | [P 151 · 2026-10-19T02:55:02Z] |
| 5 | L16 | AUT-WAIVE re-asked | 17.8.0 refuses a note-less waive | [P 154 · 2026-10-19T02:57:17Z] |
| 6 | L20 | question text truncated mid-command | lane relay | [P 181 · 2026-10-20T02:18:38Z] |
| 7 | L23 | `stalled`, resumed once with `--continue` | integration subtask 4 hit its 100-turn limit | [P 204 · 2026-10-20T09:25:39Z], [P 205], [P 208] |
| 7 | L24 | decisions `HELD` | load busy | [P 210 · 2026-10-20T10:52:26Z] |
| 7 | L22 | false `phase-died` | phase wrapper's `tail\|grep -q` under pipefail hit SIGPIPE 141 | [P 215 · 2026-10-20T12:05:49Z] |

## 5. Owner-approved hand steps

### Lines the record labels "owner-approved hand step" or "standing approval"

| Line | What |
|---|---|
| [P 71 · 2026-10-16T04:03:48Z] | L8's orphaned question `toolu_01EwRWhNoNNdVMGDKcH4B3Tv` moved to `inbox/questions/superseded/` |
| [P 81 · 2026-10-16T08:42:36Z] | L8's orphaned question `toolu_0153yudehRzj15opY9KorCWr` moved to `superseded/` |
| [P 85 · 2026-10-16T09:39:35Z] | Standing approval for wave 2: orphaned questions moved to `superseded/`; L9's `toolu_01AVRsBzv1ReYiaPb47vjizK` moved |
| [P 98 · 2026-10-17T03:58:13Z] | L9's brief draft pushed to `loomwright-meta` by exact list (`83ec2d6`); `lane-convert-ready`'s list omitted `<run_id>.brief-draft.md` |
| [P 174 · 2026-10-19T07:57:57Z] | L15/L18 lane `.gitignore` appended line reverted; L16's supervisor-result sidecar meta-pushed by exact list (`16f0f11`) |
| [P 228 · 2026-10-20T14:34:55Z] | L21–L24 `launch-pad-result` sidecars meta-pushed by exact list (`c1ffffe`, `1f2605c`, `8e9aba6`, `8e78c1d`) |

### Other hand work the owner chose (not labelled "hand step" in the record)

| Line | What |
|---|---|
| [P 49 · 2026-10-15T23:59:38Z] | Raised the token-budget ceiling on lane PR #565 (`acce60f`); stopped wave worktree and branch removed; `wave-build` re-run |
| [P 51 · 2026-10-16T01:44:08Z] | L3's brief example path rewritten for the scrub, then re-pushed; L4's leftover local branch deleted on the owner's 'Clean up now' |
| [P 65 · 2026-10-16T03:20:03Z] | Item 06's requirement scope fixed and meta-pushed (`585caf5`); L5 metadata pushed (`29d7941`); L5 removed |
| [P 67, P 80, P 84] | Coordinator ended a stuck lane-internal loop (L8) and two hung notifiers (L8, L9) |
| [P 89 · 2026-10-16T09:59:03Z] | Main's lane fixes merged into L8's PR branch at `7bdcaa4` |
| [P 90, P 133, P 161, P 221] | Coordinator integration of a stopped `wave-build`: waves 2, 4, 5 and 7 (see §6) |
| [P 163–P 167] | Five rounds of CI-review fixes pushed to the wave-5 branch (`3489d2b`, `a750493`, `fabdb7c`, `a46f4ec`, `aa5e61f`) |
| [P 190 · 2026-10-20T02:53:51Z] | Test fix on the wave-6 branch (`2d227ee`); bump, push and wave PR done by hand |
| [P 236 · 2026-10-21T06:06:42Z] | Wave 8: owner skipped the wave PR and merged #651 directly |
| not recorded | The parent file's last line still says its meta-push FAILED, "awaiting owner" [P 242]. The file nevertheless reached `loomwright-meta` in commit `5db7ec0` (2026-10-21T06:39:26Z), and its line 51 now holds a `<home>/…` placeholder. **No `## Progress` line records that last hand step.** |

## 6. Conflicts and stops at wave close

| Wave | Stop | Resolution | Lines |
|---|---|---|---|
| 1 | local CI `check-token-budget`: "automate.md 6877 > #565 ceiling 6602 (as25 × as17 interaction)" | owner raised the ceiling on #565 (`acce60f`); re-run built #567 | [P 49 · 2026-10-15T23:59:38Z], [P 50 · 2026-10-16T00:12:45Z] |
| 2 | conflict merging L8 PR #577 (`automate-lanes.sh`, `test-automate-lanes.sh`, `test-automate-trail.sh`) after main gained lane fixes | owner chose port-into-#577 (`7bdcaa4`); re-run | [P 88 · 2026-10-16T09:41:47Z], [P 89] |
| 2 | second STOP at L8: L9×L8 conflict in `test-automate-trail.sh` | coordinator integration (`e05f022`); ci-local PASS 890s; built #582 | [P 90 · 2026-10-16T10:26:56Z] |
| 3 | none ("overlap none") | — | [P 108 · 2026-10-17T12:00:12Z] |
| 4 | L12 × L11 insert-vs-insert in `vendor-coupling-manifest.json` | coordinator integration (`40a9d62`, `1b29f65`); ci-local PASS 1026s | [P 133 · 2026-10-18T10:10:29Z], [P 134] |
| 5 | L16 × L15 `test-loop-inventory.sh` GROUPS header comment | coordinator integration (`3b8570e`); ci-local PASS 983s; then 5 CI-review fix rounds on the wave branch | [P 161 · 2026-10-19T04:20:57Z], [P 162–P 168] |
| 6 | local CI 175/176, `test-automate-trail-modules.sh` check 5 red, and red on plain `origin/main` too | fix on the wave branch (`2d227ee`); ci-local PASS 1087s | [P 189 · 2026-10-20T02:50:49Z], [P 190], [P 191] |
| 7 | L23 × L22 conflict in `skills/automate-loop/lanes.md` (4 hunks) and the loop inventory's AL-511 | coordinator integration (`3cd9e78`, `b7dd8c3`); ci-local PASS 1013s | [P 219 · 2026-10-20T13:21:14Z], [P 220–P 222] |
| 8 | local CI 1 of 177 failed: `test-setup-memory.sh` 1s `gh` bound under load ~12; passed alone (574/0) | owner skipped the wave PR | [P 235 · 2026-10-21T06:01:20Z], [P 236] |

## 7. Fleet close-out leak checks

| Wave | Leak line | Finding |
|---|---|---|
| 1 | [P 56 · "fleet closeout leaks: leaks: found — claude-p"] | 4 processes of another repo's wave, not this run's; left untouched [P 57 · 2026-10-16T01:45:36Z] |
| 2 | [P 99 · "leaks: found — worktrees, git-status (claude-p not compared — pre-v2 snapshot)"] | another session's worktrees and uncommitted edits in the primary [P 100 · 2026-10-17T03:59:29Z] |
| 3 | [P 110 · "leaks: found — worktrees"] | 2 desktop-app worktrees of other sessions [P 111 · 2026-10-17T13:56:52Z] |
| 4 | [P 139 · "leaks: none (vs snapshot <primary>/…leaks-snapshot)"] | clean |
| 5 | [P 174 · 2026-10-19T07:57:57Z "leaks: none"] | clean |
| 6 | [P 195 · 2026-10-20T04:44:31Z "leaks: none"] | clean |
| 7 | [P 228 · 2026-10-20T14:34:55Z "leaks: none"] | clean |
| 8 | [P 242 · 2026-10-21T06:15:44Z "leaks: worktree lane-plan-end (another session's, #653) — not a lane leak"] | not this run's |

The final dry sweep reported "31 would-remove, 100 kept (26 worktree(s), 105 branch(es) examined)" [P 241]. It ran with no `--apply`.

## 8. Rate limit and weekly cap

- **The weekly cap hit once, in wave 4.** All four lanes stopped: "'You've hit your weekly limit · resets Oct 19 at 10:30pm (Asia/Calcutta)' = 2026-10-19T17:00Z — L11 died, L12–L14 stalled" [P 117 · 2026-10-17T18:51:56Z]. The coordinator paused launching and resumed no lane.
- **The parent records the cap later than the lanes do.** The lanes' own `rate_limit` rows date the hit at 2026-10-17T15:29:46Z [L12 · 2026-10-18T08:35:04Z], 2026-10-17T15:30:45Z [L11 · 2026-10-18T07:03:54Z] and 2026-10-17T15:33:14Z [L14 · 2026-10-18T09:01:00Z]. The parent noted it about 3h 20m after the earliest of these.
- **The owner resumed the lanes early, once a probe showed the limit had cleared** (scheduled reset 2026-10-19T17:00Z). L11 restarted with `--resume-run` and L12–L14 with `--continue` [P 119 · 2026-10-18T03:59:47Z]. The lanes then re-checked the cap: none parked `rate_limit`, because the window had passed and RUN had returned a PR [L11, L12, L14 lines above].
- **No other rate limit is recorded.** The `HELD` launches and answers (§4) came from the machine-load guard, not a rate limit.

## 9. Metadata pushes

The run used branch mode. 24 of the 25 lane files (all but L6) carry `trail-unstage: skipped — branch mode` (e.g. [L1 · 2026-10-15T11:19:11Z]), and every lane trail push went to `loomwright-meta` (§2). Two pushes were refused by the `home_path` scrub in `meta-sync.sh`:

1. **L3's done brief.** `trail-pr: meta-push FAILED — scrub .supervisor/jobs/done/2026-10-15-as05-golden-run-tests.md: home_path` [L3 · 2026-10-16T01:41:29Z]. The brief's example path was rewritten to a placeholder and re-pushed [P 51 · 2026-10-16T01:44:08Z].
2. **The parent run file itself.** `trail-pr: meta-push FAILED — scrub .supervisor/automate/automate-2026-10-15-163325.md: home_path` [P 240 · 2026-10-21T06:12:05Z]. The cause was "the wave-1 progress line's quoted example path" [P 242]: the coordinator's own `## Progress` line 51 had quoted fix 1's example. The final push is not recorded (§5).

The PITFALLS entry "Run history missing from the metadata branch — meta-push failed?" (`loomwright/docs/PITFALLS.md`) is drawn from these two lines.

## 10. Not measurable from the record

Neither item below is estimated anywhere in this report.

### Tokens per lane

**Not measurable from the record.** No line in the parent or any lane file carries a token-usage figure. The word appears only in file and check names (`check-token-budget`, `test-read-token-ledger.sh`) and in risk-classifier reasons ("matched \*token\*"). `## Run Config` (lines 5–8) records no token ceiling. To measure it next time, a run would need to log:
- `lane-status <parent_runfile> --tokens` (per-lane and parent totals) appended to the parent `## Progress` at each lane park and at wave close;
- the coordinator session's own usage. The ledger cannot see it: `LEDGER_UNREADABLE=1` for the parent root is expected (`skills/automate-loop/lanes.md` §"Dismissed findings, tokens, RESUME, removal"), and CI-side review spend is out of the ledger by design (`loomwright/docs/PITFALLS.md` §"`--max-tokens` ceiling and `run-lock.sh`").

### An honest sequential baseline

**Not measurable from the record.** The record does not hold any of these:
- a sequential run of the same 24 items;
- per-item active time: a lane's first PICK to its park mixes lane work with time spent waiting for the owner, and the record logs when an answer was *relayed*, never when the question was *asked*;
- lane durations without contention: lanes ran under load (load1 ~31 on 12 cpus [P 121]; "load ~25" [P 208]).

Summing lane spans would therefore count owner wait time several times and is not a baseline. To measure it next time, a run would need to log:
- each question's asked and answered timestamps, per lane (the `lane-status --json` step `timeline`, appended to the parent at each park);
- per-phase start and end per lane (Launch Pad, Supervisor, drain), so active time can be separated from owner wait;
- a load sample at each phase boundary;
- for a true baseline, the same item set run once sequentially on the same machine, or a declared subset run both ways.

## 11. Defect check (invariants)

These are the invariants every parallel item must keep (`.supervisor/requirements/parallel-automate/00-overview.md` §"Invariants every item must preserve", and CLAUDE.md §"Failure-Mode Invariants"), checked against the record:

| Invariant | Held? | Evidence |
|---|---|---|
| One merge executor; nothing calls `gate-eval` for a parallel run | held | `mode: safe`, no `--auto-merge` (line 6); every merge was the owner's [P 51, 91, 111, 140, 173, 195, 227, 242] |
| One owned drain per PR per pass (≤ 1 fix-now re-drain), `auto_review` suppress/restore per lane | held | §3: 23 lanes × 1 drain, L7 × 2 (fix-now); 24 × `suppressed_default_dispatch: true` |
| No push onto a PR `awaiting_merge` with a watcher armed | held | Two pushes landed on lane PRs that were already `awaiting_merge`: #565 `acce60f` [P 49] and #577 `7bdcaa4` [P 89]. An N > 1 lane arms no merge watcher (`skills/automate-loop/lanes.md` §"Terminal park"), and no lane file records a watcher (`grep -i watcher` on L4, L8 and the parent: none) |
| Never force-push the metadata branch; no done stamp without merge evidence | held | each done stamp comes from `closeout` behind its own merge-evidence gate (`skills/automate-loop/lanes.md` §"Terminal park"). For example, L1's `closeout: removed — branch … (tip == merged head 524946fc63ce)` precedes its `closeout: stamped` line [L1 · 2026-10-16T01:40:37Z]. No force-push is recorded |
| Bimodal failure philosophy | held | the scrub refused fail-closed twice (§9); the notify hangs were lane-internal background calls, not an emitter exiting non-zero |
| Shipped plugin code never calls a repo-local path; project commands come from tracked config behind the human-stamp valve | **not held in the tree** (not checkable from the record) | The record cannot show which command a step ran from where; it only shows that every `wave built:` line reports `ci pass` and a release (e.g. [P 50 · 2026-10-16T00:12:45Z]). The shipped tree does call repo-local paths: `wave-build`'s ci and release steps in `loomwright/scripts/automate-wave.sh` run `scripts/ci-local.sh` and `scripts/bump-version.sh` by fixed path whenever the wave worktree has them (`grep -n 'scripts/ci-local.sh\|scripts/bump-version.sh' loomwright/scripts/automate-wave.sh`). `.supervisor/requirements/parallel-automate/21-fleet-operations.md` Part A point 4 (origin: `06-wave-close-and-closeout.md` point 4) asks instead for a release command read from tracked project config and run only when human-stamped |
| The sequential path is protected | not checkable from the record | A parallel run holds no sequential item run, and the record carries no helper-suite result. For this change only: it is docs only, `git diff --stat origin/main...HEAD` touches neither `loomwright/skills/automate-loop/SKILL.md` nor `loomwright/commands/automate.md`, and `bash loomwright/scripts/test-automate-dismissed.sh` passes on this branch. `test-automate-helpers.sh` and `test-automate-trail.sh` were not run for this report |

**The record shows no invariant broken during the run, so nothing was filed under `.supervisor/requirements/proposed/` for a run failure.** One invariant is not held in the shipped tree: the repo-local path row above. It is a source finding, not a failure the run hit. It is filed as the draft `.supervisor/requirements/proposed/wave-build-release-command-stamp-valve.md` (gitignored, so this line is the diff-visible record of it), and it is not fixed in this PR.

Defects the record names that are **already fixed** (named, not filed):
- **Lane-number cap.** `lane-create` capped lane numbers at 1..10 per run [P 102]. Fixed on `main` by **PR #590** ("installed 17.6.1 lane-create takes 1..99" [P 113 · 2026-10-17T14:16:03Z]).
- **Issues #615–#618.** These covered the lane `.gitignore` line, clean-review drafts and nested `ground_truth`. Fixed by **PRs #619, #620, #622, #623**, released as v17.10.0 in #625 [P 176 · 2026-10-19T15:43:23Z]. Wave 6 confirmed "lane trees clean — no .gitignore line" [P 188].
- **Wave-7 follow-ups.** These covered the fresh-phase false died, the checkpoint re-pick, the lane sidecar push, the stalled gap and gate header drift [P 229]. Merged as **#643–#647**, with the drain head-moved fix **#648**, released in #649 [P 230 · 2026-10-21T00:42:55Z]. The record states this; this report did not re-verify it.
- **Brief draft missing from the wave-end exact list** [P 98]. Fixed: `_lanes_meta_extras` in `loomwright/scripts/automate-lanes.d/remove.sh` now pushes `<run_id>.brief-draft.md`, and its comment names this run's L5 and L9. Checked in the tree at base `7b7cb08`.
- **Superseded lane questions moved by hand** [P 71, 81, 85]. Fixed: `_lanes_supersede_older` (`loomwright/scripts/automate-lanes.d/common.sh`) now moves them to `questions/superseded/` with a lane `## Progress` line. Checked in the tree at base `7b7cb08`.

Defects observed that **break no invariant**, with their status on `main` **not re-verified** here:
- a lane-internal background `notify-desktop.sh` blocked on an open stdin [P 80, P 84];
- `supervisor-next-step.sh` parsed nested table rows as subtasks, filed by lane L15 as `proposed/supervisor-driver-subtask-parse-nested-tables.md` [P 151];
- the 1s `gh` bound in `test-setup-memory.sh` failed under load [P 235];
- a run file's own `## Progress` can quote a path that its scrub then refuses [P 242];
- the owner's final redaction and push of the parent file is not recorded in the file (§5).

## 12. Old-claims grep (AC7)

This command was run after this change's edits. It skips `CHANGELOG.md` and `docs/evidence/`.

```
git grep -nEi 'single[- ]open[- ]PR|trail PR|Parallel / multi-item execution|will not pick a new item|sequential[- ]only|no release PR' -- ':!CHANGELOG.md' ':!docs/evidence/'
```

**Result: 283 hits.** The pattern "Parallel / multi-item execution", `sequential only` / `sequential-only` and `no release PR` match nothing, so there is no "no release PR" claim left to replace. Every hit is listed below with its verdict. Only claims that are false for a parallel run were changed, and only inside this item's files. The requirement keeps the remaining sequential and non-branch-mode hits ("the remaining 'trail PR' / 'single-open-PR' hits describe the sequential non-branch-mode path, which still works that way").

| File | Hit lines | Hits | Verdict |
|---|---|---|---|
| `README.md` | 264 | 1 | fixed: the sentence is scoped to sequential mode, and the same line now says the rule holds per lane under `--parallel N`; the anchor `Single drain, single open PR` is kept (pinned by `test-automate-dismissed.sh`) |
| `loomwright/commands/agent-help.md` | 230 | 1 | left: the sequential default's "When to Use" line, in the same block that documents `--parallel N`; the requirement lists `agent-help.md` as already correct |
| `loomwright/commands/automate.md` | 105 | 1 | left: the non-branch-mode trail-PR rule, which still works that way |
| `loomwright/docs/loop-inventory/automate-loop.md` | 29, 52, 60, 135, 144, 154, 159, 161, 166, 223, 248, 364, 366, 376, 378, 379, 395, 419, 424, 428, 574, 608, 612, 740 | 24 | left: inventory rows quoting sequential-path rules verbatim (needles pinned by `test-loop-inventory.sh`) |
| `loomwright/docs/rationale/automate-loop.md` | 25, 65, 67, 73, 75, 77, 81, 87, 89, 92, 95, 111, 125, 141 | 14 | left: rationale for the non-branch-mode trail-PR path (sequential path) |
| `loomwright/docs/result-schemas/automate-run.md` | 62, 105, 106 | 3 | left: the per-run-file rule and the sequential `trail_pr_open` enum; each lane is its own run file |
| `loomwright/docs/result-schemas/automate-run/item-lifecycle.md` | 7 | 1 | left: the per-run-file rule and the sequential `trail_pr_open` enum; each lane is its own run file |
| `loomwright/docs/result-schemas/schema-versioning.md` | 19 | 1 | left: historical reference (trail PR #311) |
| `loomwright/scripts/automate-helpers.d/reconcile-status.sh` | 49, 50, 54 | 3 | left: code for the sequential PICK gate / non-branch-mode trail path, not a doc claim |
| `loomwright/scripts/automate-helpers.sh` | 72, 83 | 2 | left: code for the sequential PICK gate / non-branch-mode trail path, not a doc claim |
| `loomwright/scripts/automate-lanes.d/notify-guards.sh` | 150 | 1 | left: code for the sequential PICK gate / non-branch-mode trail path, not a doc claim |
| `loomwright/scripts/automate-lanes.d/remove.sh` | 455 | 1 | left: code for the sequential PICK gate / non-branch-mode trail path, not a doc claim |
| `loomwright/scripts/automate-next-step.sh` | 108, 1564, 1570, 1678, 1685 | 5 | left: code for the sequential PICK gate / non-branch-mode trail path, not a doc claim |
| `loomwright/scripts/automate-trail.d/closeout.sh` | 13, 18, 25, 273, 275, 335 | 6 | left: code for the sequential PICK gate / non-branch-mode trail path, not a doc claim |
| `loomwright/scripts/automate-trail.d/finalize.sh` | 125 | 1 | left: code for the sequential PICK gate / non-branch-mode trail path, not a doc claim |
| `loomwright/scripts/automate-trail.d/stage-sync.sh` | 61, 62, 63, 64, 65, 66, 67, 68, 71, 74, 81, 96, 100, 103, 106 | 15 | left: code for the sequential PICK gate / non-branch-mode trail path, not a doc claim |
| `loomwright/scripts/automate-trail.d/trail-pr.sh` | 136, 488, 512, 671 | 4 | left: code for the sequential PICK gate / non-branch-mode trail path, not a doc claim |
| `loomwright/scripts/automate-trail.sh` | 3, 28, 121, 123, 124, 125, 135, 148, 151, 152, 155, 157, 159 | 13 | left: code for the sequential PICK gate / non-branch-mode trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/MAP.tsv` | 61, 64 | 2 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/brief-repair-merged/expected.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/brief-repair-merged/input.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/check-off-progress/expected.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/check-off-progress/input.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/closeout-leftover-gate-non-interactive/expected.md` | 21 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/closeout-leftover-gate-non-interactive/input.md` | 21 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/dismissed-findings-decision-step/expected.md` | 17 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/dismissed-findings-decision-step/input.md` | 16 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/dismissed-fix-now-re-drain/expected.md` | 21 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/dismissed-fix-now-re-drain/input.md` | 21 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/drain-owned-drain-started/expected.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/drain-owned-drain-started/input.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/drain-pinned-start-line-current-not-set/expected.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/drain-pinned-start-line-current-not-set/input.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/drain-superseded-by-merge/tree/dot-supervisor/requirements/automate-followups/11-post-park-lifecycle.md` | 1, 6, 17, 19, 66, 71, 79, 82, 95, 113, 181, 187, 204, 215 | 14 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/fix-now-became-follow-up/expected.md` | 21 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/fix-now-became-follow-up/input.md` | 21 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-eval-checks-not-green-park/expected.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-eval-checks-not-green-park/input.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-eval-drain-not-ready-park/expected.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-eval-drain-not-ready-park/input.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-eval-head-sha-moved-park/expected.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-eval-head-sha-moved-park/input.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-eval-high-risk-diff-park/expected.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-eval-high-risk-diff-park/input.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-eval-merge/expected.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-eval-merge/input.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-eval-review-decision-blocking-park/expected.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-eval-review-decision-blocking-park/input.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-eval-rules-gate-head-mismatch-park/expected.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-eval-rules-gate-head-mismatch-park/input.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-eval-unprotected-branch-park/expected.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-eval-unprotected-branch-park/input.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-validation-recheck-at-reconcile/next-step.results` | 5 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/gate-validation-waive/tree/dot-supervisor/requirements/automate-speed/01-question-gates-dont-stall.md` | 47 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/learning-emit-end-of-drain/expected.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/learning-emit-end-of-drain/input.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/park-first-decisions-recorded/expected.md` | 21 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/park-first-decisions-recorded/input.md` | 21 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/park-first-ready-park/expected.md` | 21 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/park-first-ready-park/input.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/pick-current-set-then-picked/expected.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/pick-current-set-then-picked/input.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/pick-pending-decisions-ask/expected.md` | 21 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/pick-pending-decisions-ask/input.md` | 21 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/pick-time-lane-guard-park/expected.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/pick-time-lane-guard-park/input.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/pick-time-token-ceiling-park/expected.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/pick-time-token-ceiling-park/input.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/pick-time-trail-gate-park/expected.md` | 19, 31 | 2 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/pick-time-trail-gate-park/expected.out` | 2 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/pick-time-trail-gate-park/input.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/pick-time-trail-gate-park/next-step.results` | 3 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/pick-time-trail-gate-park/source` | 2, 3 | 2 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/rate-limit-park/expected.md` | 16 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/rate-limit-park/input.md` | 16 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/reconcile-closeout-merged/expected.md` | 21, 43 | 2 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/reconcile-closeout-merged/expected.out` | 18 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/reconcile-closeout-merged/input.md` | 21 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/resume-ambiguous-park/expected.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/resume-ambiguous-park/input.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/resume-config-crash-restore/expected.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/resume-config-crash-restore/input.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/resume-glob-finalize/expected.md` | 21 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/resume-glob-finalize/input.md` | 21 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/resume-glob-finalize/tree/dot-supervisor/automate/automate-2026-10-08-033739-L2.md` | 17 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/resume-rate-limit-park/expected.md` | 16 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/resume-rate-limit-park/input.md` | 16 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/resume-reconcile-status/expected.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/resume-reconcile-status/input.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/run-config-suppress-restore/expected.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/run-config-suppress-restore/input.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/run-record-pr/expected.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/run-record-pr/input.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/skipped-item-check-off/expected.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/skipped-item-check-off/input.md` | 19 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/sync-closeout-no-trail/expected.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-golden/sync-closeout-no-trail/input.md` | 20 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden` | 2, 13 | 2 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/fixtures/phase-timing/replay-2026-10-08/automate/automate-2026-10-08-121222.md` | 5 | 1 | left: frozen fixture data for the sequential/trail path, not a doc claim |
| `loomwright/scripts/test-automate-dismissed.sh` | 901 | 1 | left: a test of the sequential/trail path, not a doc claim |
| `loomwright/scripts/test-automate-helpers.d/02-runfile.sh` | 435 | 1 | left: a test of the sequential/trail path, not a doc claim |
| `loomwright/scripts/test-automate-helpers.d/10-reconcile-status.sh` | 325, 339, 355, 356, 386, 388 | 6 | left: a test of the sequential/trail path, not a doc claim |
| `loomwright/scripts/test-automate-helpers.sh` | 129, 132, 136 | 3 | left: a test of the sequential/trail path, not a doc claim |
| `loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh` | 902 | 1 | left: a test of the sequential/trail path, not a doc claim |
| `loomwright/scripts/test-automate-next-step.sh` | 111, 1164, 1185, 1188, 1791, 1849, 2491, 2888 | 8 | left: a test of the sequential/trail path, not a doc claim |
| `loomwright/scripts/test-automate-trail.d/01-sidecar-trail-pr.sh` | 337, 357, 378, 501, 502, 544, 564 | 7 | left: a test of the sequential/trail path, not a doc claim |
| `loomwright/scripts/test-automate-trail.d/02-closeout.sh` | 111, 112, 116, 126, 127, 142, 145, 227, 323 | 9 | left: a test of the sequential/trail path, not a doc claim |
| `loomwright/scripts/test-automate-trail.d/03-stamps-gate.sh` | 292, 304, 309, 332, 333, 335, 348, 351, 354, 366, 370, 372, 378, 386, 401, 409, 417 | 17 | left: a test of the sequential/trail path, not a doc claim |
| `loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` | 104, 174, 618, 663 | 4 | left: a test of the sequential/trail path, not a doc claim |
| `loomwright/scripts/test-automate-trail.sh` | 30, 41, 63, 66, 70, 126, 141 | 7 | left: a test of the sequential/trail path, not a doc claim |
| `loomwright/skills/automate-loop/SKILL.md` | 31, 139, 159, 279, 288, 313, 318 | 7 | left: the §8 per-run-file rule (SKILL.md §1: "one open PR per run file (one per lane)") and the non-branch-mode trail-PR path |
| `loomwright/skills/automate-loop/branch-mode.md` | 3, 7 | 2 | left: true. It states that branch mode replaces the trail PR |
| `loomwright/skills/automate-loop/helpers.md` | 32, 33, 36, 38, 39 | 5 | left: the §8 per-run-file rule (SKILL.md §1: "one open PR per run file (one per lane)") and the non-branch-mode trail-PR path |
| `loomwright/skills/automate-loop/modes-and-merge-gate.md` | 7 | 1 | left: the §8 per-run-file rule (SKILL.md §1: "one open PR per run file (one per lane)") and the non-branch-mode trail-PR path |
| `loomwright/skills/automate-loop/per-item-loop.md` | 5, 49, 58, 95, 97, 103, 104 | 7 | left: the §8 per-run-file rule (SKILL.md §1: "one open PR per run file (one per lane)") and the non-branch-mode trail-PR path |
| `loomwright/skills/automate-loop/resume.md` | 45 | 1 | left: the §8 per-run-file rule (SKILL.md §1: "one open PR per run file (one per lane)") and the non-branch-mode trail-PR path |

## Honest limits

- Merge times are when the coordinator recorded them, except wave 2's (§1). This report did not read GitHub's own merge timestamps, because only the record was in scope.
- The PR states, CI results and commit SHAs quoted here come from the record. This report did not re-check them against GitHub.
- §11 checks five of its seven invariants against the record. The other two are not checkable from it: the repo-local path row rests on a read of the tree at this branch, and the sequential-path row on this change's own diff and one suite.
- The "fixed" statuses in §11 rest on the record's own lines, plus two checks in the tree at base `7b7cb08` (the brief-draft list and superseded-question retirement). The other fixes were not re-run.
