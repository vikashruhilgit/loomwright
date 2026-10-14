<!-- bump: minor -->
/automate no longer holds a parked or curated run on an unanswered owner question
Run automate-2026-10-13-181331 spent 2h48m waiting on the AUT-QUEUE confirm for a backlog doc the owner had already
ordered, and 4h56m on the dismissed-findings decisions while its mergeable PR was not yet parked, watched or announced
(owner decisions D1-D3 in automate-speed/01). New read-only helper `automate-helpers.sh queue-confirm <source> <n>
<limit>`: a `--backlog` Queue no longer than `--limit` skips AUT-QUEUE and records `skipped AUT-QUEUE: backlog queue
<n> ≤ limit <N>`; folder and prompt sources, a longer Queue and an unreadable count still ask, and the lane skip
(`--lane-backlog`) keeps its Progress line byte for byte. At a sequential interactive READY park (safe mode, and the
`--auto-merge` fail-closed park) the engine now writes the `awaiting_merge` park, arms the merge watcher, notifies and
releases the run lock BEFORE it asks, and asks only after the new read-only `automate-helpers.sh park-ask-gate
<runfile> <item> <pr_url> [--wait <s>]` answers `ask`: it refuses (nothing asked, the next PICK asks) when the park was
not written, no merge-watch marker carries the PR within `--wait` (the engine passes 75s, past the watcher's 60s
replace wait) or `## Current` names another item or PR, and it allows fix-now only when its own `gh pr view --json
state` reads exactly OPEN. All fix-now answers of one decision batch are handled together: the engine re-checks the
gate, re-acquires the run lock and re-checks the gate again while holding it (the watcher's `closeout` takes the same
lock), before any `running` write, then records every fix-now answer before the ONE re-pass; otherwise each becomes a
follow-up draft with its own `fix-now became follow-up` Progress line, so no fix is pushed after a merge. The `escalated`
park, `--non-interactive-fallback` and lanes keep the decide-then-park order. Tests: test-automate-helpers.sh section
QG (both helpers with a stubbed gh, a delayed-marker leg, and a prose-order leg over the new park-first list, each
with a validated mutant); test-automate-dismissed.sh Part B pins the new order.
