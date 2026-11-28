# Orca PR claim for Loomwright — plan doc (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now
Orca bots already take and enforce the loomwright-orca CLAIM.md v1 claim, and the `claim-guard` hook is installed on this Mac: it fails closed for `vikashruhilgit` repos. Loomwright drains do not take the claim yet. So a bot can work the same PR at the same time, and once a bot holds the claim, a drain's push is refused. The shared PR-merge bot also has no signal for the PRs Loomwright's gate declined. Owner approved 2026-11-28; orca-plugin-dev answered the open questions the same day.

## Owner decisions
none recorded

## Order
| Item | Delivers | Depends on | Can run in parallel with |
|---|---|---|---|
| 01 | `pr-claim.sh` (take / renew / release / assert / holder / session-check, plus `release --parked`: handover to `pr-merge`, label, HANDOFF.md v1 handoff) | none | none |
| 02 | `/review-pr` drains hold the claim, holder in every writing session's env | 01 | none |
| 03 | `/automate` per-run holder in every session's env, item claim, a gate PARK hands the PR to `pr-merge` (handover, label, handoff) | 02 | none |

## Run
/automate --backlog .supervisor/requirements/orca-claim/_BACKLOG-2026-11-28-065541-orca-pr-claim.md
Safe mode, sequential (each item needs the previous one). Not before the repo-wide `/automate` lock is free.

## Considered and not queued
- Marker field `reason=parked`: rejected, because release deletes the marker, so the field would disappear with it.
- One holder per machine: rejected, because lanes and concurrent drains would be indistinguishable (design note §"Holder id").
- Background renew heartbeat: rejected, because it risks leaking a child process; renewal happens on driver calls instead.
- Claiming inside Supervisor Phase 4.5 / FINALIZE: deferred, because no drain works the PR yet.
- Label-only wake-up for `pr-merge`: dropped on 2026-11-28, because Orca's `github.labeled` trigger ignores labels the owner's own account adds. The label stays, and a gate PARK also sends a direct `orca orchestration send --to bot:pr-merge --type handoff` (01 Part B, wired in 03).
- Release, then label, then send: replaced on 2026-11-28 by orca-plugin-dev's final answer. A gate PARK hands the claim to `pr-merge` with `claim-step handover` first (no gap, never two holders), then labels, then sends; release plus label is only the fallback (loomwright-orca `docs/HANDOFF.md` §5, PR #7 `a1de67b`).
- A `LOOMWRIGHT_CLAIM_HOLDER=` command prefix (`write-prefix`): dropped on 2026-11-28, because the guard reads identity from the session env and ignores a prefix for merges when that is set (loomwright-orca `docs/GUARD.md`, PR #9 `5ad9434`).
- `dev-bot: <the run's holder>`: dropped on 2026-11-28, because pr-merge replies to the dev bot and a Loomwright run cannot act on a reply. It is `LOOMWRIGHT_ORCA_DEV_BOT`, else `none`.

## Revisit when
CLAIM.md or HANDOFF.md changes past v1, or the merge bot's wake contract changes (for example, Orca's `github.labeled` starts firing for the owner's own labels, which would make the direct handoff redundant).

## Checklist
- [ ] .supervisor/requirements/orca-claim/2026-11-28-065541-pr-claim-01-helper.md
- [ ] .supervisor/requirements/orca-claim/2026-11-28-065541-pr-claim-02-drains.md
- [ ] .supervisor/requirements/orca-claim/2026-11-28-065541-pr-claim-03-automate.md
