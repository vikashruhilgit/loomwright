# af39f — `/janitor --report` on the developer machine

The output below is `janitor-report.sh --root <primary>` (the `/janitor --report` path), run against the primary
checkout of this repo while the lane wave that built `/janitor` was live. Home paths are written as `/Users/<name>/`.
It changed nothing: the report path is read-only.

## What it shows

- **Processes:** the live lane and phase sessions of the running wave as `running` registry entries (action `none`),
  the old registry entries as ONE `fin` row (reap prunes the files, no signal), and two unregistered look-alikes.
- **The two unregistered look-alikes are the wave coordinator's own `lane-wait` watcher and its shell wrapper.**
  `lane-wait` matches the scan predicate (a plugin script path, older than an hour) and is not registered, which is
  the scan's stated honest limit ("a WANTED long-lived plugin process that neither registers nor descends from a
  registered one is counted"; `proc-registry.sh` header). `/janitor` reports it faithfully and offers
  `stop-unregistered`, which the owner must NOT pick while the wave runs. Follow-up: `lane-wait` should register
  itself as the lane sampler does, so it reads `running` instead.
- **Run locks:** the coordinator's lock (holder alive, `none`) and two lane locks whose holder pid is dead while
  their run still says `running` — shown with action `none`, never reclaimed from here.
- **Lanes:** the running lanes (`none`, the coordinator owns them), and `lane-remove` for lanes of an old wave that
  read `abandoned` with their clone still on disk; each wave's `lane-status --leaks` first line as-is.
- **Worktrees and branches:** the `sweep` dry run — 31 branches removable under the squash-safe rule (each row's
  `sweep-apply` applies the WHOLE sweep), app-made worktrees kept.
- **Stale run state:** `retention-sweep` candidates in `logs/` and one metadata-push failure, report-only.

## Report

```text
janitor: report — primary /Users/<name>/Documents/work/AI/ai-agent-manager — 2026-10-25T19:53:49Z — read-only, nothing changed
## Processes
- reg-825dc5af | lane process pid 32033 (registry entry 32033-4bc8882678d984bf)
    owner: plugin — lane entry · age: 2h41m · state: running
    evidence: identity matches; age 9684s <= cap 86400s
    action: none — running within its cap — the run that started it owns it
- reg-341571b3 | lane process pid 53167 (registry entry 53167-f60eaa112a4b04bf)
    owner: plugin — lane entry · age: 1h49m · state: running
    evidence: identity matches; age 6590s <= cap 86400s
    action: none — running within its cap — the run that started it owns it
- reg-332eed8c | lane process pid 53289 (registry entry 53289-30d7baf91a8da9b9)
    owner: plugin — lane entry · age: 1h49m · state: running
    evidence: identity matches; age 6590s <= cap 86400s
    action: none — running within its cap — the run that started it owns it
- reg-a212c68b | lane process pid 61680 (registry entry 61680-e27922b92b09342a)
    owner: plugin — lane entry · age: 2h04m · state: running
    evidence: identity matches; age 7480s <= cap 86400s
    action: none — running within its cap — the run that started it owns it
- reg-d5b5fbb1 | lane process pid 61758 (registry entry 61758-0a2c51645f350778)
    owner: plugin — lane entry · age: 2h04m · state: running
    evidence: identity matches; age 7480s <= cap 86400s
    action: none — running within its cap — the run that started it owns it
- reg-2956e58b | phase process pid 7789 (registry entry 7789-4a6c2b6c35c9c7f0)
    owner: plugin — phase entry · age: 1h48m · state: running
    evidence: identity matches; age 6481s <= cap 21600s
    action: none — running within its cap — the run that started it owns it
- reg-d1a45301 | phase process pid 7917 (registry entry 7917-74b826784fd6e16b)
    owner: plugin — phase entry · age: 1h48m · state: running
    evidence: identity matches; age 6481s <= cap 21600s
    action: none — running within its cap — the run that started it owns it
- reg-7743c57e | phase process pid 86588 (registry entry 86588-e0551e4ae83bfbf8)
    owner: plugin — phase entry · age: 2h03m · state: running
    evidence: identity matches; age 7397s <= cap 21600s
    action: none — running within its cap — the run that started it owns it
- reg-f9b4f7b9 | phase process pid 86660 (registry entry 86660-879b086264c0a352)
    owner: plugin — phase entry · age: 2h03m · state: running
    evidence: identity matches; age 7397s <= cap 21600s
    action: none — running within its cap — the run that started it owns it
- unreg-48c2b17a | unregistered process pid 70364
    owner: unregistered (looks like the plugin's) · age: 2h04m · state: running, unregistered
    evidence: plugin script path /Users/<name>/.claude/plugins/cache/atelier/loomwright/17.16.1/scripts/automate-lanes.sh; lstart=Sun Oct 25 17:47:51 2026; cmd_hash=sha1:347b1b825c2480c24aa2c10846c8884269a84fbe
    action: stop-unregistered — it looks like the plugin's (plugin script path /Users/<name>/.claude/plugins/cache/atelier/loomwright/17.16.1/scripts/automate-lanes.sh) but no registry entry owns it — stopped only on your pick, after proc-registry re-checks its lstart and command-line hash
- unreg-173d34df | unregistered process pid 70369
    owner: unregistered (looks like the plugin's) · age: 2h04m · state: running, unregistered
    evidence: plugin script path /Users/<name>/.claude/plugins/cache/atelier/loomwright/17.16.1/scripts/automate-lanes.sh; lstart=Sun Oct 25 17:47:51 2026; cmd_hash=sha1:aa6927fca8b3965a7af00109529953fc611820d0
    action: stop-unregistered — it looks like the plugin's (plugin script path /Users/<name>/.claude/plugins/cache/atelier/loomwright/17.16.1/scripts/automate-lanes.sh) but no registry entry owns it — stopped only on your pick, after proc-registry re-checks its lstart and command-line hash
- fin-89566b14 | 150 finished registry entries
    owner: plugin — registry · age: - · state: finished
    evidence: pid gone or recycled: 10240-d0c74e89f1adf5fc 12133-2cf390b50e5efc80 12281-4f350d0afceda8e8 12423-0a53d9f241e15b0c 12561-adc166045cc4bb05 +145 more
    action: reap — their processes are gone; reap prunes the entry files and sends no signal
  note: proc-registry.sh: 161 row(s); scan: 2 unregistered
## Run locks
- lock-7ed85c8e | run lock — primary /Users/<name>/Documents/work/AI/ai-agent-manager
    owner: automate-lanes:automate-2026-10-22-123646 · age: 2h43m · state: held, holder alive
    evidence: LOCKED owner=automate-lanes:automate-2026-10-22-123646 pid=79176 age=9821; liveness=alive; run automate-2026-10-22-123646: running
    action: none — its holder is alive — the run owns the lock (it releases it when it ends)
- lock-ee3bb451 | run lock — lane /Users/<name>/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-22-123646/L8
    owner: automate:automate-2026-10-22-123646-L8 · age: 2h40m · state: held, holder dead, run still says running
    evidence: LOCKED owner=automate:automate-2026-10-22-123646-L8 pid=21073 age=9657; liveness=dead; run automate-2026-10-22-123646-L8: running
    action: none — its holder pid is dead but run automate-2026-10-22-123646-L8 still says running (it may continue in a fresh session) — `/automate --resume automate-2026-10-22-123646-L8` re-takes it; never reclaimed from here
- lock-a077166a | run lock — lane /Users/<name>/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-22-123646/L9
    owner: automate:automate-2026-10-22-123646-L9 · age: 2h40m · state: held, holder dead, run still says running
    evidence: LOCKED owner=automate:automate-2026-10-22-123646-L9 pid=26285 age=9640; liveness=dead; run automate-2026-10-22-123646-L9: running
    action: none — its holder pid is dead but run automate-2026-10-22-123646-L9 still says running (it may continue in a fresh session) — `/automate --resume automate-2026-10-22-123646-L9` re-takes it; never reclaimed from here
  note: 7 checkout(s) checked (primary + lanes), 4 unlocked
## Lanes
- lane-50eaa6a9 | lane L1 of automate-2026-10-08-033739
    owner: run automate-2026-10-08-033739 · age: 17d15h · state: abandoned
    evidence: path /Users/<name>/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-08-033739/L1; item .supervisor/requirements/s3-validation/01-scratch-doc-a.md; pr -
    action: lane-remove — abandoned, its clone still on disk — lane-remove salvages and removes it (it refuses unpushed, dirty or live lanes)
- lane-5206ebb0 | lane L2 of automate-2026-10-08-033739
    owner: run automate-2026-10-08-033739 · age: 17d15h · state: abandoned
    evidence: path /Users/<name>/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-08-033739/L2; item .supervisor/requirements/s3-validation/02-scratch-doc-b.md; pr -
    action: lane-remove — abandoned, its clone still on disk — lane-remove salvages and removes it (it refuses unpushed, dirty or live lanes)
- leaks-b5780e83 | leak check of wave automate-2026-10-08-033739
    owner: run automate-2026-10-08-033739 · age: - · state: leaks: found — worktrees, lanes-dir, config-checksum (claude-p not compared — pre-v2 snapshot; merge-watch not compared — pre-v2 snapshot)
    evidence: lane-status /Users/<name>/Documents/work/AI/ai-agent-manager/.supervisor/automate/automate-2026-10-08-033739.md --leaks (compare mode)
    action: none — report only — `lane-status /Users/<name>/Documents/work/AI/ai-agent-manager/.supervisor/automate/automate-2026-10-08-033739.md --leaks` prints each changed section
- lane-feef777f | lane L8 of automate-2026-10-22-123646
    owner: run automate-2026-10-22-123646 · age: 2h41m · state: running
    evidence: path /Users/<name>/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-22-123646/L8; item .supervisor/requirements/automate-followups/39f-janitor-command.md; pr -
    action: none — running — the wave's coordinator owns it (`/automate --resume automate-2026-10-22-123646`; fleet-closeout removes it after merge)
- lane-2dd6311a | lane L9 of automate-2026-10-22-123646
    owner: run automate-2026-10-22-123646 · age: 2h40m · state: running
    evidence: path /Users/<name>/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-22-123646/L9; item .supervisor/requirements/parallel-automate/25-backlog-board-feeds.md; pr -
    action: none — running — the wave's coordinator owns it (`/automate --resume automate-2026-10-22-123646`; fleet-closeout removes it after merge)
- leaks-55c2bc1c | leak check of wave automate-2026-10-22-123646
    owner: run automate-2026-10-22-123646 · age: - · state: leaks: found — lanes-dir, claude-p
    evidence: lane-status /Users/<name>/Documents/work/AI/ai-agent-manager/.supervisor/automate/automate-2026-10-22-123646.md --leaks (compare mode)
    action: none — report only — `lane-status /Users/<name>/Documents/work/AI/ai-agent-manager/.supervisor/automate/automate-2026-10-22-123646.md --leaks` prints each changed section
  note: 7 wave(s) skipped: every lane removed
## Worktrees and branches
- wt-9b6f0a3c | app /Users/<name>/Documents/work/AI/ai-agent-manager/.claude/worktrees/infallible-pike-587cfa
    owner: the host app · age: 4d02h · state: kept
    evidence: clean and merged (branch fix/salvage-drain-records: PR #664 MERGED, tip == merged head ab8f375f06a4) — left in place; the app removes its own worktrees
    action: none — report only — the sweep keeps it for the reason in its evidence; `sweep --apply` never removes it while that holds
- wt-e8bf748f | app /Users/<name>/Documents/work/AI/ai-agent-manager/.claude/worktrees/objective-snyder-c34717
    owner: the host app · age: 3d08h · state: kept
    evidence: clean and merged (branch fix/lanes-test-parts-standalone-guard: PR #678 MERGED, tip == merged head 7bf9c9005a73) — left in place; the app removes its own worktrees
    action: none — report only — the sweep keeps it for the reason in its evidence; `sweep --apply` never removes it while that holds
- wt-82a8c7aa | app /Users/<name>/Documents/work/AI/ai-agent-manager/.claude/worktrees/resolve-679-conflict-698bc9
    owner: the host app · age: 2d02h · state: kept
    evidence: branch merge-679-main: no PR for this branch — left in place; the app removes its own worktrees
    action: none — report only — the sweep keeps it for the reason in its evidence; `sweep --apply` never removes it while that holds
- br-876a0dc5 | branch chore/dreaming-2026-10-02
    owner: local branch · age: 23d11h · state: removable
    evidence: PR #344 MERGED, tip == merged head e6dfb378b73f
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-eacd5d4b | branch chore/m1-untrack-run-history
    owner: local branch · age: 22d15h · state: removable
    evidence: PR #361 MERGED, tip == merged head f4282631dc0e
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-c82b6467 | branch chore/meta-scrub-cleanup
    owner: local branch · age: 22d17h · state: removable
    evidence: PR #359 MERGED, tip == merged head b06a5054bcb9
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-771b5ad6 | branch chore/release-15.126.0
    owner: local branch · age: 16d03h · state: removable
    evidence: PR #444 MERGED, tip == merged head 0d3c120743cc
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-cbfc6d7f | branch chore/release-15.128.1
    owner: local branch · age: 14d17h · state: removable
    evidence: PR #467 MERGED, tip == merged head 856df84870bd
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-16f117aa | branch chore/release-v17.3.0
    owner: local branch · age: 10d08h · state: removable
    evidence: PR #557 MERGED, tip == merged head a1142f11a3a0
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-1743f332 | branch chore/triage-proposed-2026-10-01
    owner: local branch · age: 23d12h · state: removable
    evidence: PR #343 MERGED, tip == merged head 2ec967b486ae
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-587a40b1 | branch claude/nostalgic-lovelace-c60600
    owner: local branch · age: 8d13h · state: removable
    evidence: PR #590 MERGED, tip == merged head bbe8c80f4a19
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-5cb2b536 | branch docs/final-state-d1-d2-amendment
    owner: local branch · age: 25d06h · state: removable
    evidence: PR #316 MERGED, tip == merged head 2a63137ccfaf
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-5dc2535e | branch feat/po-wave-shaping-scope-fence
    owner: local branch · age: 8d15h · state: removable
    evidence: PR #586 MERGED, tip == merged head a91efe930e52
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-e8fb7647 | branch feature/lanes-pane-ux
    owner: local branch · age: 12d18h · state: removable
    evidence: PR #507 MERGED, tip == merged head f35fd4301ff7
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-05ef87c3 | branch fix/automate-runfile-write-fail-closed
    owner: local branch · age: 24d15h · state: removable
    evidence: PR #322 MERGED, tip == merged head 4e03626c03c6
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-86693425 | branch fix/automate-trail-pr-behind-main
    owner: local branch · age: 23d06h · state: removable
    evidence: PR #356 MERGED, tip == merged head 742690b0d944
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-9e26344f | branch fix/bash53-locale-prefix-segfault
    owner: local branch · age: 23d04h · state: removable
    evidence: PR #355 MERGED, tip == merged head 56ebd80b6e37
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-1aa6b5b6 | branch fix/harvest-c3-path-independent
    owner: local branch · age: 22d11h · state: removable
    evidence: PR #363 MERGED, tip == merged head a7657ab537b4
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-52817c73 | branch fix/lane-task-plan-push
    owner: local branch · age: 15d05h · state: removable
    evidence: PR #457 MERGED, tip == merged head 01fcd5f7edfe
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-8962ff65 | branch fix/pin-no-pr-run-line
    owner: local branch · age: 9d15h · state: removable
    evidence: PR #572 MERGED, tip == merged head ba9b161de1fc
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-a299d08b | branch fix/repo-scan-gates-skip-ignored
    owner: local branch · age: 22d11h · state: removable
    evidence: PR #362 MERGED, tip == merged head bc9eb0a415c7
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-6df1f53f | branch fix/token-ledger-transcript-identity-gate
    owner: local branch · age: 16d19h · state: removable
    evidence: PR #439 MERGED, tip == merged head c83f7f187e26
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-c737c42a | branch fix/w2-lane-defects
    owner: local branch · age: 14d17h · state: removable
    evidence: PR #466 MERGED, tip == merged head 12a36944408a
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-1cdda149 | branch release/v17-after-wave7
    owner: local branch · age: 4d19h · state: removable
    evidence: PR #649 MERGED, tip == merged head 0e0291ccc494
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-0055f032 | branch wave/automate-2026-10-14-041009-w1
    owner: local branch · age: 11d11h · state: removable
    evidence: PR #541 MERGED, tip == merged head 3925a6323390
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-a41b9b29 | branch wave/automate-2026-10-15-163325-w1
    owner: local branch · age: 9d19h · state: removable
    evidence: PR #567 MERGED, tip == merged head ec62ca25f22b
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-c1221644 | branch wave/automate-2026-10-15-163325-w2
    owner: local branch · age: 9d09h · state: removable
    evidence: PR #582 MERGED, tip == merged head 77164c518f72
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-a9534f8b | branch wave/automate-2026-10-15-163325-w3
    owner: local branch · age: 8d07h · state: removable
    evidence: PR #596 MERGED, tip == merged head 4c6b4720b232
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-cce79539 | branch wave/automate-2026-10-15-163325-w4
    owner: local branch · age: 7d09h · state: removable
    evidence: PR #606 MERGED, tip == merged head e71e0b89929a
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-46ae14ec | branch wave/automate-2026-10-15-163325-w7
    owner: local branch · age: 5d05h · state: removable
    evidence: PR #641 MERGED, tip == merged head 0988e3899fe0
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-6ba7db6a | branch wave/automate-2026-10-22-123646-w1
    owner: local branch · age: 2d01h · state: removable
    evidence: PR #685 MERGED, tip == merged head 3f51d0446b5d
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-9803ab81 | branch wave/w2
    owner: local branch · age: 15d00h · state: removable
    evidence: PR #465 MERGED, tip == merged head 94fa1b3b67ed
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-7d4d136c | branch wave/w3
    owner: local branch · age: 14d11h · state: removable
    evidence: PR #474 MERGED, tip == merged head df7ced0a195a
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-fd6fe6a5 | branch wave/w4
    owner: local branch · age: 14d04h · state: removable
    evidence: PR #481 MERGED, tip == merged head 801bff0b9f5a
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- brkept-7a7381e7 | 55 local branch(es) kept
    owner: local branches · age: - · state: kept
    evidence: backup/citation-drift-prerebase chore/parallel-automate-queue chore/parallel-automate-redteam-fixes claude/beautiful-almeida-0d02fb claude/blissful-mccarthy-76f25d +50 more
    action: none — report only — each fails the sweep's squash-safe rule (newest PR not merged at the tip, the current or base branch, or checked out); `automate-helpers.sh sweep` names each reason
  note: sweep: summary — dry run: 31 would-remove, 58 kept (3 worktree(s), 86 branch(es) examined)
## Stale run state
- ret-2d91e824 | .supervisor/logs/ exhaust older than the threshold
    owner: this checkout · age: - · state: 50 candidate file(s)
    evidence: candidates: 50 file(s), 178849 bytes, oldest 182 days, newest 93 days
    action: none — report only — `retention-sweep.sh --project-root /Users/<name>/Documents/work/AI/ai-agent-manager --delete` removes them (irreversible)
- mpf-348e0132 | metadata push failure of run automate-2026-10-08-033739
    owner: run automate-2026-10-08-033739 · age: 17d15h · state: push failed
    evidence: 2026-10-08T04:44:53Z scrub .supervisor/automate/automate-2026-10-08-033739.md: home_path
    action: none — report only — the run's next trail push retries it (`/automate --resume automate-2026-10-08-033739`), or publish by hand with meta-sync.sh push
  note: retention-sweep: summary — 50 candidate file(s); nothing removed (report-only; pass --delete to remove the files listed above)
## Plugin-adjacent (report only)
  (no rows)
  note: ci-slot.sh status: 0 holder(s), 0 waiter(s), 2 slot(s)
## Not the plugin's (report only)
  (no rows)
janitor: summary — 58 row(s), 36 actionable (reap=1, sweep-apply=31, stop-unregistered=2, lane-remove=2)
```

## Interactive run

pending — owner run at review
