# S3 — Stabilization queue run as waves (OPERATOR-RUN wave spike — not an `/automate` item; no plugin change)

## Status: parked (operator-run: lives in `operator-run/` so folder intake never enqueues it; start after step 0, the release of S2's four fragments, and a plugin reinstall)

## Depends on
- S2 closed (all five PRs merged, lanes torn down, `leaks` empty — done 2026-10-05).
- Step 0: one release bump folding `changelog.d/` (items agnostic-phase1/01, automate-followups/16, 24, 26), merged
  and installed, so wave 1's lanes run S2's fixes.
- The S1/S2 harness `~/Documents/work/AI/ai-agent-manager-lanes-v2/s1h.sh`, now with `launch <lane> --resume-run
  <run_id>` (added 2026-10-05; backup in `archive/`).

## HANDOVER (2026-10-05 ~11:45Z) — from session 944cda59 to session 6e8f1058
**Single owner from now: session 6e8f1058.** 944cda59 runs nothing for S3 (no monitor, sampler, watcher or lane)
and edits no S3 record after this push.

### State at handover
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

## The queue (19 items — owner decision 2026-10-05: "finish parallel automation and everything related")
Merged on 2026-10-05 (originals parked with pointers; text kept verbatim as parts):
`meta-sync-followups/08` = ms/02 + 03 + 06 · `automate-followups/32` = af/14 + 28 + 29 · `automate-followups/33` =
af/17 + 25. New the same day: `meta-sync-followups/07` (onboard any repo to branch mode), `automate-followups/31`
(temporary escalations); `parallel-automate/06` amended (watcher on `escalated` parks, targeted `--resume`).
Added to the scope the same day: `parallel-automate/09, 11, 12, 13, 14, 15`, `automate-followups/22, 23`.
Out of scope (not parallel work): the rest of the backlog, including the 7 older items with no Touches / Depends on.

## Wave plan (`plan-waves --max 5`, companion rule relaxed — see Planner rule)
| Wave | Items | Lanes |
|---|---|---|
| 1 | af/32 run-file lifecycle · ms/08 meta-sync hardening · ms/04 home-path scrub · pa/09 fewer full CI runs | 4 |
| 2 | pa/11 split shared hotspot files — **alone** (owner decision) | 1 |
| — | **Re-check every remaining item's `## Touches` against the split layout, then re-plan waves 3+** | — |
| 3+ (pre-split plan, will widen) | af/33 · ms/05 → ms/07 · agnostic/04 (Milestone A) → pa/05 → pa/06 · pa/14 → af/31 → pa/12 → pa/13 → pa/15 → af/22 → af/23 → pa/07 (Milestone B) | 1–3 |

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

## Done when
All 19 items merged or closed by the owner, each wave's records on `loomwright-meta`, lanes torn down with `leaks`
empty, the measures above recorded in this file, and P2 (default lane count) revisited with S2 + S3 evidence.
