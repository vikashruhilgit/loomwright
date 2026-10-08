# 24 — pa/05 Validation 4/5 fixes B: lane notification and per-lane token counts

## Status: pending

## Depends on
23-pa05-validation-fixes-a.md

## Touches
loomwright/skills/automate-loop/SKILL.md
loomwright/scripts/automate-lanes.sh
loomwright/scripts/test-automate-lanes.sh
loomwright/scripts/read-token-ledger.sh
loomwright/scripts/test-read-token-ledger.sh
loomwright/scripts/emit-token-ledger.sh
loomwright/scripts/test-token-ledger.sh
loomwright/docs/TELEMETRY.md
changelog.d/parallel-automate-24-pa05-validation-fixes-b.md

## Problem
These were found by pa/05's Validation 4/5 (run `automate-2026-10-08-033739`; evidence is in #426's description,
under "Known issues"). The pa/05 release bump waits for this item too.

- **F6 — the "wave open" notification never reaches the owner.** At a lane's `ready_for_release` park (§14 "Terminal
  park"), the lane must notify "do not merge yet — wave open". L1 called `send-webhook.sh`, which printed
  `repo_webhook_ignored` (no user-scope egress grant for this repo). There was no desktop notification, and L1 first
  logged it as sent, then appended a correction. The gate type it used, `automate_ready_for_release`, is not in
  `docs/TELEMETRY.md`'s gate list. L2 reports that it sent a desktop notification, so the two lanes behaved
  differently. The step is prose, with no helper.
- **F8 — per-lane token counts read zero.** `lane-status <rf> --tokens` printed `L1 … TOTAL=0 EVENTS=6`, `L2 …
  TOTAL=0 EVENTS=3`, `parent … LEDGER_UNREADABLE=1`. Meanwhile each lane's stream-json `total_cost_usd` summed to
  about $17.0 (L1) and $8.6 (L2). So the ledger records events with zero tokens inside lane clones, and `--max-tokens
  T` (split as `floor(T/N)` per lane in `lane.json`) can never trip. The cause is not known yet.

## Goal
Every lane park reaches the owner the same way and through a documented gate type. Per-lane and parent token totals
are real, so a lane's `--max-tokens` share can park the lane.

## Scope
1. **F6:** one helper call does the lane park notification (desktop notify plus webhook, both fail-SAFE, as the
   merge watcher does). §14 "Terminal park" names it, and `automate_ready_for_release` is added to `TELEMETRY.md`'s
   gate types. A lane's `## Progress` records what was actually delivered, never just what was attempted.
2. **F8:** first find why lane ledger events carry zero tokens: the lane's SubagentStop payload, the transcript path
   the emitter reads inside a clone, or the reader's `--root`. Write the finding into the PR. Then fix it so
   `lane-status --tokens` per-lane totals are non-zero for a lane that ran agents, and `ceiling-check` inside a lane
   reads them. If part of the lane's spend cannot be counted (the main thread, for example), §14 and `ARCHITECTURE`'s
   honest limit say exactly which part.

## Acceptance criteria
- F6: a hermetic test proves the lane park helper calls the desktop notify when the webhook is ignored, and that
  `## Progress` names what was delivered.
- F8: a fixture lane with a real-shaped SubagentStop transcript yields non-zero per-lane `TOTAL`, and `ceiling-check`
  parks a lane over its share.
- The sequential path is unchanged.

## Validation (must pass before merge)
1. `bash scripts/ci-local.sh` is green.
2. The new tests, shown failing on the pre-fix head and passing on the branch.
3. **Running system:** combine with item 23's throwaway run if both are merged before it, otherwise a one-lane
   `--parallel 2` run on a throwaway item. Paste the delivered notification line and `lane-status --tokens` showing
   non-zero lane totals.
4. Rollback: `git revert`.

## Non-goals
F3: lanes inconsistently asking the 1-item queue confirm. This is already item 21's Part B amendment 1 ("Remove
pointless questions at the source"). This run's evidence was added there. F7 is `automate-followups/37`.
