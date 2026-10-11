### Item lifecycle

```
queued (- [ ]) → running → rate_limit (parks, no PR yet) | pr-open → awaiting_merge → merged (- [x]) | ready_for_release (lane park) | escalated (parks) | drain_died (parks) | failed | skipped
```

- `escalated` **parks** the run (`## Status: paused`, `pause_reason: escalated`) and never opens a second PR (single-open-PR invariant — `skills/automate-loop/SKILL.md` §8/§9).
- `rate_limit` **parks** the run (`## Status: paused`, `pause_reason: rate_limit`) BEFORE a PR ever exists — RUN itself failed on a rate-limit `StopFailure` (`skills/automate-loop/SKILL.md` §6 "Rate-limit park"). It resumes through the SAME RESUME reconcile as `awaiting_merge`/`escalated` (§4) — no second park vocabulary, no second reconcile path.
- `drain_died` **parks** the run (`## Status: paused`, `pause_reason: drain_died`, `owned_drain_result: died`) when RECONCILE (§4) finds a `.died` marker for this item's PR from a DETACHED `dispatch-pr-review.sh` drain that exited without ever producing a `REVIEW_HEAL_RESULT` — **never `awaiting_merge`**, since a died drain never reached a real READY/ESCALATED verdict. Resolves through the same RESUME reconcile path as the other parks.
- A drain **superseded by a merge** (automate-followups/20) is not a park of its own: the owned drain ended without a terminal `REVIEW_HEAL_RESULT` and the PR reads `merged`, so `## Current` records `owned_drain_result: superseded_by_merge`, GATE is skipped and the item goes `pr-open → merged (- [x])` through `closeout`; the run then stops `## Status: paused` with `pause_reason: awaiting_go` (`skills/automate-loop/SKILL.md` §6).
- `ready_for_release` **parks a lane** (`## Status: paused`, `pause_reason: ready_for_release`) — written instead of `awaiting_merge` by a READY gate inside a `--parallel N>1` lane only: no merge watcher is armed, the notify says "do not merge yet — wave open", no `trail-pr` runs (it is a park). At wave end the coordinator converts it to `awaiting_merge` (`lane-convert-ready`); after the owner merges, the lane run file is closed out and finalized `## Status: done` and `fleet-closeout` checks the item off the parent Queue (`skills/automate-loop/SKILL.md` §14 "Terminal park" and "Wave close").
- `skipped`/`abandoned` items are written `- [x] <path>  # skipped|abandoned: <reason>` (above) so they are never re-picked and do not block `done`.
