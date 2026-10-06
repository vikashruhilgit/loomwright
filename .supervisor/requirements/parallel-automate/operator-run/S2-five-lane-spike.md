# S2 — Five-lane spike (OPERATOR-RUN — not an `/automate` item; no plugin change)

## Status: parked (operator-run: lives in `operator-run/` so folder intake never enqueues it; run after 08, 09, 10 and the item-10 backfill are merged and the plugin is reinstalled)

**Usage check:** every command in an `operator-run/` runbook is checked against the shipped script's usage text (`<script> --help`) before the runbook is used — by hand, no checker script; a flag `--help` does not list (e.g. the dry-run flag M1 step 1 once named) is a runbook bug to fix first.

## Depends on
- 08 (shared CI slots), 09 (fewer full runs), 10 (+ its backlog backfill) merged, plugin reinstalled.
- 12 (policy answers) is optional: run S2 once without it if it is not ready, and record the question load.
- The S1 v2 harness `ai-agent-manager-lanes-v2/s1h.sh` (generalise its lane list; it already takes any lane name).

## Purpose
Owner goal (2026-10-04): **5 to 10 lanes at once.** S1 proved two lanes are isolated and that "A + relay" holds
every human gate. S2 measures what changes at five, so the default lane count (decision P2) is set from evidence,
and so 10 is attempted only if five is clean.

## Setup
1. `plan-waves --max 5 --explain` over the backfilled backlog: pick ONE wave of 5 file-disjoint items. If no wave of
   5 exists, stop and record the `--explain` output (that is item 11's input), do not force it.
2. `snapshot before` (as S1). Five clones via the harness (`setup s2-a … s2-e`, one `--seed` on a fresh throwaway
   branch `loomwright-meta-s2`). Launch all five within one minute.
3. Relay every question (the `/lanes` pane for some lanes, the main session for others — finish S1's visibility
   test here). Record each answer's latency.

## Measure
1. **CI:** `ci-slot.sh status` sampled every 10 s — slot occupancy, queue length, longest wait, per-run wall-clock
   against S1's solo 190–380 s. Full `ci-local` runs per push (item 09's target: one).
2. **Machine:** RSS of every `claude` process per lane and in total, load average, swap use, free memory — every
   60 s. (24 GB on this Mac; unmeasured until now.)
3. **Owner load:** questions per lane, human vs policy, answer latency, longest time a lane sat waiting.
4. **Merges:** merge the PRs one by one in planner order; after each, `mergeable` / `mergeStateStatus` of every
   other PR and `main`'s `ci` (item 13's input).
5. **Cost and time:** final `total_cost_usd` per session, wall-clock launch → park per lane, and the subscription
   headroom (does anything hit the weekly cap? the CI `claude-review` runs share it).
6. **Leaks:** `s1h.sh leaks` after teardown must be empty; `snapshot after` identical.

## Decide
- **P2 (default lane count):** 5 if every measure above is clean; else the largest N the data supports, with the
  limiting resource named.
- **Go/no-go for a 10-lane run (S3):** only if five was clean AND the limiting resource has headroom for double.
- **P10 (usage budget):** cost per wave against the owner's budget; record whether lanes need their own billing.

## Done when
The measures are recorded in this file's run record, P2 is set in `00-overview.md`, the five PRs are merged or
closed by the owner, and the clones and throwaway branch are removed with `leaks` empty.

## Pre-S2 evidence: wave w1 (2026-10-04, two real lanes, A + relay, harness `s1h.sh`)
- Items 08 (#375, merged `d3ee8f2`) and 10 (#377, merged `2bdb2b7`), launched together 10:29Z from `95e8601`; throwaway records branch `loomwright-meta-w1`; records carried to `loomwright-meta` (`fc2e547`); lanes torn down, `leaks` empty, primary clean.
- **~17 relayed questions** across both lanes (resume ×2, Plan Review gates ×5 including two attempt-3s, pre-flight-overlap-on-own-base ×1, children-settled ×1, dismissed findings ×4 calls). By item 12's classification, about half were routine.
- **One operator intervention:** w1-08 ended its turn mid-drain to wait for CI, so its background wait was stopped and the lane stalled (no process, no park, no question). Resumed once with a decision-free note → 05 Scope 14 stalled-lane detection.
- **Findings filed:** `automate-followups/29` (w1-10 never set `## Current` at PICK), the second cause in `/17` (turn-limit stops leave no terminal row), `/30` (case H of `test-lens-run.sh` is not concurrency-safe, found by the operator's three-clone check of #375), 05 Scope 15 (merge-readiness report; #375 itself listed its must-pass check as "Not verified"), item 12 evidence (pre-flight overlap with the lane's own base; already-fixed drafts), and a second home-path scrub failure (w1-08's brief) for `meta-sync-followups/04`.
- **Operator merge checks** caught a gap that review/heal does not cover (an unrun must-pass Validation step), and an undercounted Touches list (#377 touched the `/propose` writer scripts, not just the command file).

## HANDOVER (2026-10-05 ~00:35Z) — from session 07b3f63c ("Loomwright automation resume (fork 3)") to session 3679fac4
**Single owner from now: the new session.** The old session stops relaying and stops editing/pushing S2 records once you confirm.

### Live state at handover
- 5 lanes running (A + relay), base `main` `c1692b0`, throwaway records branch `loomwright-meta-s2` (seeded by s2-a):
  s2-a `agnostic-phase1/01` · s2-b `automate-followups/16` · s2-c `automate-followups/24` · s2-d `automate-followups/26` ·
  s2-e `meta-sync-followups/01`. All answered their resume+queue questions ("start new" + "process"); all now planning (next: Plan Review / Phase 6 brief gates).
- s2-a and s2-b show `WARN Current unset in run file` (item 29 bug — 3 of 8 lanes so far); harmless until park/closeout — check `## Current` at park.
- Owner merges every PR by hand. P10: no budget cap. Item order after S2: schedule `automate-followups/17` early (3 false children-settled gates in a day).

### Harness (`~/Documents/work/AI/ai-agent-manager-lanes-v2/`)
- `s1h.sh status [--json]` · `recent <lane> [n]` · `feed <lane>` · `answer <lane> <tool_use_id> --via main-session` (stdin `{"answers":{"0":"<exact label>",...},"note":"..."}`) · `leaks` · `teardown <lane>` (needs `S1H_META_BRANCH=loomwright-meta-s2` exported) · `snapshot before|after` (S2's before = `snapshot-before.txt`).
- Every launch/resume appends `LANE_SYS` (headless lane: never end the turn to wait; wait in the foreground) — added after two stalls.
- `launch.log` = pid history. Archives of finished lanes: `archive/<lane>/`. S1/w1/w2a snapshots in `archive/`.

### Relay rules (owner's standing rules)
- Relay each question VERBATIM with its exact options; an answer is exactly one option label (free text only as `note`).
  AskUserQuestion takes ≤4 questions per call — split across calls; do NOT merge two lane questions into one (done once for s2-e
  `toolu_016YrfSpQvrMoCq2rJo78k73`; recorded in its answer note).
- Read a pending question with `s1h.sh status --json | jq '.[]|select(.lane=="<l>")|.pending'`.
- Before relaying a factual claim from a lane (e.g. "writes landed", "already fixed"), check it read-only when cheap.

### Watching
- Monitor loop (re-arm every 30 min): `snap()` = `s1h.sh status --json | jq -r '.[]|"\(.lane) alive=\(.alive) status=\(.status) reason=\(.pause_reason) pr=\(.pr) branch=\(.branch)\(if .pending then " QUESTION="+.pending.id else "" end)"'`, print new lines every 30 s.
- **Stall** = `alive=false`, status `running`, no question, and NOT just the 1–2 s gap between an answer and the resumed pid (check
  `launch.log` latest pid + `ps`). If the last result says it ended its turn "waiting", resume once with a decision-free note
  (continue where you left off; wait in the foreground) — see `launch.log` "operator nudge" entries for the exact command.
- **Sampler** `s2-sampler.sh` → `s2-measure.log` (cols: time holders waiters load1 swap_MB free_MB rss_MB×5 procs). The old
  session's sampler + `caffeinate -i -t 14400` die when that session closes: start your own (`bash s2-sampler.sh` in the
  background — it appends; first check `pgrep -f s2-sampler.sh` is empty — and `caffeinate -i -t 14400`). Lid must stay open.
- At handover: swap 4.4 GB (pre-existing, flat), free ~100–180 MB, ~250–300 MB RSS per lane.

### At each park — merge checks before telling the owner "safe to merge"
1. The item's `## Validation (must pass before merge)` — any "Running system" step the PR lists as "Not verified" you run
   yourself in throwaway clones (scratchpad; origin = GitHub URL so CI slots are shared) — e.g. #375's three-clone check found
   the case-H flake (→ item 30, now merged).
2. Scope fence: `gh pr view N --json files` vs the item's `## Touches` (+ `changelog.d/`, companion `SKILLS_INDEX.md`).
3. `ci` + `claude-review` green on the CURRENT head; read the latest bot comment.
4. Carried Plan Review notes addressed; dismissed findings all decided.
- Red CI at park → lane parks `escalated` (no watcher). With owner OK, fix in a scratch clone of the branch, verify, push (check
  remote head unchanged first), then after merge run closeout by hand:
  `cd <lane> && bash ~/.claude/plugins/cache/atelier/loomwright/15.119.2/scripts/automate-helpers.sh closeout <runfile> <item> <pr_url>`.

### After each merge — records and teardown
- `awaiting_merge` parks close out by themselves (watcher). Then carry records to the REAL branch: files from the lane's
  `loomwright-meta-s2` commit (or from the clone if the lane logged `meta-push FAILED … home_path` — rewrite `/Users/<name>/` → `~/`);
  for the item's requirement file append ONLY the block from `<!-- loomwright:requirement-closeout -->` (never overwrite —
  the primary copy may have newer edits); append the lane's last `.supervisor/postmortem/results.jsonl` line; push with
  `bash loomwright/scripts/meta-sync.sh push --branch loomwright-meta --paths-from <list>`. **ALWAYS pass `--branch`**
  (meta-sync defaults to the real branch and ignores the mode line).
- Teardown: archive `s1h-lane.log`, `s1-questions/`, `s1-answers/`, `logs/` to `archive/<lane>/`; if the lane's
  `meta-sync.sh status --branch loomwright-meta-s2` is `local_ahead`, sanitize + push it there first; then
  `S1H_META_BRANCH=loomwright-meta-s2 bash s1h.sh teardown <lane>`. After the last lane: `snapshot after`, `git pull` main in
  the primary, ask the owner before deleting `loomwright-meta-s2`, stop sampler/caffeinate/monitor.

### S2 write-up (this file's "Measure" / "Decide")
CI slot occupancy + waits (sampler), RSS/swap/free per lane over time, questions per lane (human vs routine), merges in order and
each sibling's mergeable state after, final `total_cost_usd` per lane session, wall-clock launch→park per lane, operator
interventions, leaks. Then set P2 in `00-overview.md` and decide go/no-go for 10.
### Session-only extras (not carried)
The `/lanes` pane lives in the OLD session's mods folder (`~/.claude/dev-mods/07b3f63c-0dc0-4bf9-82c3-1b14ef791064/lanes/`).
To use it in the new session: load the `plugin-authoring` skill, copy that folder into the new session's mods folder, enable hot
reloading when asked, `/lanes`.

### How to set up and run a wave of lanes (from scratch) — the S1/w1/w2/S2 recipe
The harness is a LOCAL spike script, not in git: `~/Documents/work/AI/ai-agent-manager-lanes-v2/s1h.sh` (backup:
`archive/s1h.sh.backup-2026-10-05`). Item 05 (lane coordinator) will replace it with `lane-create`/`lane-launch`/`lane-status`/`lane-answer`.
**Prerequisites:** the primary checkout clean and on fresh `main` (`git pull --ff-only`); the Loomwright plugin installed
(lanes run the INSTALLED plugin, `~/.claude/plugins/cache/atelier/loomwright/<version>/`, not the working tree — a merged
engine fix reaches lanes only after a release + reinstall); `jq`, `gh` (authenticated), `caffeinate`.
1. **Pick the wave.** Every candidate must have valid `## Touches` / `## Depends on` (`bash loomwright/scripts/automate-helpers.sh
   plan-waves <dir|list> --lint`). Plan: `plan-waves <list-file> --max N --explain` (a list file = one item path per line). Only
   items in the SAME wave run together. Skip parked/obsolete items.
2. **Record the start:** `echo "# ---- wave <name> starts $(date -u +%FT%TZ) ----" >> launch.log`; move the previous
   `snapshot-*.txt` into `archive/<prev>/`; `bash s1h.sh snapshot before`.
3. **Pick a throwaway records branch** (never the real one): `export S1H_META_BRANCH=loomwright-meta-<wave>`.
4. **Set up lanes** (from the primary's directory): first lane with `--seed` (creates + seeds the throwaway branch from the real
   one), the rest without: `bash s1h.sh setup <lane> .supervisor/requirements/<folder>/<item>.md [--seed]`. Lane names must be
   new (a used name is refused; `teardown` first). What `setup` does: `git clone --local` of the primary → origin set to the
   GitHub URL (so CI slots and remote branches are shared) → copies `.supervisor/config.json` (+ notify config) → edits the
   clone's `.gitignore` mode line to the throwaway branch and hides that edit (`update-index --skip-worktree`) → drops
   `meta-base` → seeds or pulls the throwaway branch → installs the relay hooks (`.supervisor/s1h-ask-hook.sh` wired into
   `.claude/settings.local.json` as `PreToolUse[AskUserQuestion]` = record question + `defer` / later `allow` with the
   recorded answer, and `PermissionRequest[AskUserQuestion]` = deny a bundled question so it is re-asked alone) → writes
   `.supervisor/s1-backlog.md` (one `- [ ] <item>` line) → checks mode + clean tree.
5. **Launch:** `bash s1h.sh launch <lane>` for each (within a minute of each other). Launch = detached
   `claude -p --input-format stream-json --output-format stream-json --verbose --permission-prompt-tool stdio
   --permission-mode acceptEdits --allowedTools Bash,Read,Edit,Write,Glob,Grep,Task,Agent,AskUserQuestion
   --append-system-prompt "$LANE_SYS"` with prompt `/loomwright:automate --backlog .supervisor/s1-backlog.md`, env
   `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0` (else `-p` kills background workers after 600 s), user settings loaded (NEVER
   `--setting-sources project,local` — breaks auth), NO `--non-interactive-fallback` (else gates are decided silently).
   `launch <lane> --probe` runs a 1-question Haiku probe to test the relay without real work.
6. **Background helpers:** the monitor loop (above), `caffeinate -i -t 14400`, and a sampler if measuring. Expect each lane's
   first question to be the stale-runs "Start new run?" (item 28) + "process the 1-item queue?".
7. **Relay, check, merge, close out, carry, tear down** — the sections above. Teardown of the LAST lane: `snapshot after`
   (expect only HEAD + meta tip to differ), pull main, delete the throwaway branch (owner's yes), stop background helpers.
