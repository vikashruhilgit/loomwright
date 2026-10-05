# S3 — Stabilization queue run as waves (OPERATOR-RUN wave spike — not an `/automate` item; no plugin change)

## Status: parked (operator-run: lives in `operator-run/` so folder intake never enqueues it; start after step 0, the release of S2's four fragments, and a plugin reinstall)

## Depends on
- S2 closed (all five PRs merged, lanes torn down, `leaks` empty — done 2026-10-05).
- Step 0: one release bump folding `changelog.d/` (items agnostic-phase1/01, automate-followups/16, 24, 26), merged
  and installed, so wave 1's lanes run S2's fixes.
- The S1/S2 harness `~/Documents/work/AI/ai-agent-manager-lanes-v2/s1h.sh`, now with `launch <lane> --resume-run
  <run_id>` (added 2026-10-05; backup in `archive/`).

## Purpose
Owner decision 2026-10-05: stabilize parallel automation, then release it for other repos, and build that queue
**with waves, the way S2 ran** — as a spike that also looks for gaps the requirements below do not name. S2 had one
wave; S3 is the first run of **several waves in a row**, with a release and reinstall between waves (the
pa/06 one-bump-per-wave model, by hand) and with the wave runner's own replacement (pa/05) built mid-queue.

## The queue (11 items, after the 2026-10-05 merges)
Merged on 2026-10-05 (originals parked with pointers; text kept verbatim as parts):
`meta-sync-followups/08` = ms/02 + 03 + 06 · `automate-followups/32` = af/14 + 28 + 29 · `automate-followups/33` =
af/17 + 25. New the same day: `meta-sync-followups/07` (onboard any repo to branch mode), `automate-followups/31`
(temporary escalations); `parallel-automate/06` amended (watcher on `escalated` parks, targeted `--resume`).

## Wave plan (`plan-waves --max 5`, companion rule relaxed — see Planner rule)
| Wave | Items | Lanes |
|---|---|---|
| 1 | af/32 run-file lifecycle · ms/08 meta-sync hardening · ms/04 home-path scrub | 3 |
| 2 | af/33 children-settled gate · ms/05 learning stores + rehearsal harness | 2 |
| 3 | ms/07 onboard any repo · agnostic/04 non-interactive gates | 2 |
| 4 | pa/05 lane coordinator | 1 |
| 5 | pa/06 wave close + closeout | 1 |
| 6 | af/31 temporary escalations | 1 |
| 7 | pa/07 pilot + docs | 1 |

Milestone A after wave 3: release; any repo can move to branch mode (ms/07) and run sequential `/automate`.
Milestone B after wave 7: release; parallel lanes on other repos.
With the strict planner the same queue is 10 waves (1–2 lanes each); merging alone gave 10 → the merges plus the
relaxed rule give 7.

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

## Measure (per wave)
Lanes, launch → park per lane, questions, escalations and cause, merge order and each sibling's `mergeable` after
each merge, table-doc and manifest conflicts, release wall-clock, final `total_cost_usd` per lane, leaks after
teardown, machine (load, swap, free) at peak.

## Done when
All 11 items merged or closed by the owner, each wave's records on `loomwright-meta`, lanes torn down with `leaks`
empty, the measures above recorded in this file, and P2 (default lane count) revisited with S2 + S3 evidence.
