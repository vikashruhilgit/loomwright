# af39f — `/janitor --report` on the developer machine

The output below is `janitor-report.sh --root <primary>` (the `/janitor --report` path), run against the primary
checkout of this repo while the lane wave that built `/janitor` was live. Home paths are written as `/Users/<name>/`.
It changed nothing: the report path is read-only. It was re-generated after review iteration 1, which demoted a
look-alike under a live host session to action `none` and added each look-alike's command line to its evidence.

## What it shows

- **Processes:** the live lane sessions of the running wave as `running` registry entries (action `none`), two
  phase entries past their cap (`reap`), the old registry entries as ONE `fin` row (reap prunes the files, no
  signal), and two unregistered look-alikes.
- **The two unregistered look-alikes are the wave coordinator's own `lane-wait` watcher and its shell wrapper.**
  `lane-wait` matches the scan predicate (a plugin script path, older than an hour) and is not registered, which is
  the scan's stated honest limit ("a WANTED long-lived plugin process that neither registers nor descends from a
  registered one is counted"; `proc-registry.sh` header). Their snapshot ppid chain reaches the coordinator's live
  host session (the desktop app's `claude`, pid 79176), so `/janitor` shows them with action `none` — "its session
  is still alive — the session owns it" — and never offers them for stopping. The evidence column now carries each
  command line (`… automate-lanes.sh lane-wait …`). Follow-up: `lane-wait` should register itself as the lane
  sampler does, so it reads `running` instead.
- **Run locks:** the coordinator's lock (holder alive, `none`) and two lane locks whose holder pid is dead while
  their run still says `running` — shown with action `none`, never reclaimed from here.
- **Lanes:** the running lanes (`none`, the coordinator owns them), and `lane-remove` for lanes of an old wave that
  read `abandoned` with their clone still on disk; each wave's `lane-status --leaks` first line as-is.
- **Worktrees and branches:** the `sweep` dry run — 31 branches removable under the squash-safe rule (each row's
  `sweep-apply` applies the WHOLE sweep, and its id carries the would-remove set), app-made worktrees kept.
- **Stale run state:** `retention-sweep` candidates in `logs/` and one metadata-push failure, report-only.
- **Not the plugin's:** the coordinator's host session itself, report-only.

## Report

```text
janitor: report — primary /Users/<name>/Documents/work/AI/ai-agent-manager — 2026-10-26T01:53:47Z — read-only, nothing changed
## Processes
- reg-825dc5af | lane process pid 32033 (registry entry 32033-4bc8882678d984bf)
    owner: plugin — lane entry · age: 8h41m · state: running
    evidence: identity matches; age 31301s <= cap 86400s
    action: none — running within its cap — the run that started it owns it
- reg-a212c68b | lane process pid 61680 (registry entry 61680-e27922b92b09342a)
    owner: plugin — lane entry · age: 8h04m · state: running
    evidence: identity matches; age 29097s <= cap 86400s
    action: none — running within its cap — the run that started it owns it
- reg-d5b5fbb1 | lane process pid 61758 (registry entry 61758-0a2c51645f350778)
    owner: plugin — lane entry · age: 8h04m · state: running
    evidence: identity matches; age 29097s <= cap 86400s
    action: none — running within its cap — the run that started it owns it
- reg-a34eef54 | phase process pid 86588 (registry entry 86588-e0551e4ae83bfbf8)
    owner: plugin — phase entry · age: 8h03m · state: overdue
    evidence: age 29014s > cap 21600s
    action: reap — overdue: reap re-checks its lstart and command-line hash, sends TERM, then KILL after its grace only if it still matches
- reg-7a33de33 | phase process pid 86660 (registry entry 86660-879b086264c0a352)
    owner: plugin — phase entry · age: 8h03m · state: overdue
    evidence: age 29014s > cap 21600s
    action: reap — overdue: reap re-checks its lstart and command-line hash, sends TERM, then KILL after its grace only if it still matches
- unreg-b245bded | unregistered process pid 39710
    owner: unregistered — a descendant of live host session pid 79176 · age: 4h35m · state: running, unregistered, its session alive
    evidence: plugin script path /Users/<name>/.claude/plugins/cache/atelier/loomwright/17.16.1/scripts/automate-lanes.sh; lstart=Sun Oct 25 21:17:22 2026; cmd_hash=sha1:b256157b87bcb92c06f058b97aba1ff41dc0809f; command: /bin/zsh -c source /Users/<name>/.claude/shell-snapshots/snapshot-zsh-1792947994436-68fn6h.sh 2>/dev/null || true && setopt NO_EXTENDED_GLOB NO_BARE_GLOB_QUAL 2>/dev/null || true && { \builtin un...; session: pid 79176 /Users/<name>/Library/Application Support/Claude/claude-code/2.1.308/a93ded4b1b47/claude.app/Contents/MacOS/claude --output-format stream-json --verbose --input-format stream-json --effort=high --model=claude-opus-5-5 --permission-prompt-tool=stdio --allowedTools=mcp__computer-use,mcp__ccd_session__spawn_task,mcp__ccd_session__dismiss_task,mcp__ccd_session__mark_chapter,mcp__ccd_session_mgmt__list_sessions,mcp__ccd_session_mgmt__get_session,mcp__ccd_session_mgmt__get_usage,mcp__ccd_host__get_storage_usage,mcp__ccd_session_mgmt__set_session_title,mcp__ccd_session_mgmt__send_message,mcp__ccd_session_mgmt__detach_session,mcp__ccd_sidebar__list_groups,mcp__ccd_sidebar__create_group,mcp__ccd_sidebar__set_view,mcp__ccd_sidebar__list_sections,mcp__ccd_sidebar__create_section,mcp__ccd_turn__wrap_up,mcp__ccd_turn__update_plan,mcp__ccd_session_mgmt__search_session_transcripts,mcp__ccd_session_mgmt__list_events,mcp__ccd_session_mgmt__export_transcript,mcp__scheduled-tasks__list_task_runs,mcp__ccd_session__read_widget_context,mcp__ccd_session__list_start_targets,mcp__ccd_view__show_pane,mcp__ccd_view__close_pane,mcp__ccd_view__get_layout,mcp__ccd_view__set_transcript_view,mcp__ccd_settings__get_settings,mcp__mcp-registry__search_mcp_registry,mcp__mcp-registry__suggest_connectors,mcp__mcp-registry__list_connectors,mcp__ccd_connectors__session_connectors_status,mcp__ccd_connectors__reconnect_session_connector,mcp__ccd_pr__get_status,mcp__ccd_window__open_session_in,mcp__ccd_window__close_split,mcp__ccd_window__set_sidebar_collapsed,mcp__ccd_window__get_window_layout --disallowedTools=SubscribePR --setting-sources=user,project,local --permission-mode=auto --allow-dangerously-skip-permissions --include-partial-messages --await-initialize --thinking-display omitted --replay-user-messages --settings {"fastMode":false,"deniedMcpServers":[{"serverName":"Claude Browser"},{"serverName":"Claude Code Android Emulator"},{"serverName":"Claude Code iOS Simulator"},{"serverName":"Claude Preview"},{"serverName":"Claude_Browser"},{"serverName":"Claude_Code_Android_Emulator"},{"serverName":"Claude_Code_iOS_Simulator"},{"serverName":"Claude_Preview"},{"serverName":"Claude_for_Chrome"},{"serverName":"Framebuffer"},{"serverName":"Window Halo"},{"serverName":"Window_Halo"},{"serverName":"ccd_connectors"},{"serverName":"ccd_directory"},{"serverName":"ccd_host"},{"serverName":"ccd_pr"},{"serverName":"ccd_session"},{"serverName":"ccd_session_mgmt"},{"serverName":"ccd_settings"},{"serverName":"ccd_sidebar"},{"serverName":"ccd_turn"},{"serverName":"ccd_view"},{"serverName":"ccd_window"},{"serverName":"claude-in-chrome"},{"serverName":"claude_browser"},{"serverName":"claude_code_android_emulator"},{"serverName":"claude_code_ios_simulator"},{"serverName":"claude_for_chrome"},{"serverName":"claude_in_chrome"},{"serverName":"claude_preview"},{"serverName":"computer-use"},{"serverName":"computer_use"},{"serverName":"cowork"},{"serverName":"cowork-onboarding"},{"serverName":"cowork_onboarding"},{"serverName":"dev-debug"},{"serverName":"dev_debug"},{"serverName":"dispatch"},{"serverName":"framebuffer"},{"serverName":"mcp-registry"},{"serverName":"mcp_registry"},{"serverName":"plugins"},{"serverName":"remote-devices"},{"serverName":"remote_devices"},{"serverName":"scheduled-tasks"},{"serverName":"scheduled_tasks"},{"serverName":"session_info"},{"serverName":"skills"},{"serverName":"window_halo"}]}
    action: none — its session is still alive — the session owns it (pid 79176); it ends with that session, or stop it from there
- unreg-5aedcdee | unregistered process pid 39752
    owner: unregistered — a descendant of live host session pid 79176 · age: 4h35m · state: running, unregistered, its session alive
    evidence: plugin script path /Users/<name>/.claude/plugins/cache/atelier/loomwright/17.16.1/scripts/automate-lanes.sh; lstart=Sun Oct 25 21:17:22 2026; cmd_hash=sha1:aa6927fca8b3965a7af00109529953fc611820d0; command: bash /Users/<name>/.claude/plugins/cache/atelier/loomwright/17.16.1/scripts/automate-lanes.sh lane-wait .supervisor/automate/automate-2026-10-22-123646.md; session: pid 79176 /Users/<name>/Library/Application Support/Claude/claude-code/2.1.308/a93ded4b1b47/claude.app/Contents/MacOS/claude --output-format stream-json --verbose --input-format stream-json --effort=high --model=claude-opus-5-5 --permission-prompt-tool=stdio --allowedTools=mcp__computer-use,mcp__ccd_session__spawn_task,mcp__ccd_session__dismiss_task,mcp__ccd_session__mark_chapter,mcp__ccd_session_mgmt__list_sessions,mcp__ccd_session_mgmt__get_session,mcp__ccd_session_mgmt__get_usage,mcp__ccd_host__get_storage_usage,mcp__ccd_session_mgmt__set_session_title,mcp__ccd_session_mgmt__send_message,mcp__ccd_session_mgmt__detach_session,mcp__ccd_sidebar__list_groups,mcp__ccd_sidebar__create_group,mcp__ccd_sidebar__set_view,mcp__ccd_sidebar__list_sections,mcp__ccd_sidebar__create_section,mcp__ccd_turn__wrap_up,mcp__ccd_turn__update_plan,mcp__ccd_session_mgmt__search_session_transcripts,mcp__ccd_session_mgmt__list_events,mcp__ccd_session_mgmt__export_transcript,mcp__scheduled-tasks__list_task_runs,mcp__ccd_session__read_widget_context,mcp__ccd_session__list_start_targets,mcp__ccd_view__show_pane,mcp__ccd_view__close_pane,mcp__ccd_view__get_layout,mcp__ccd_view__set_transcript_view,mcp__ccd_settings__get_settings,mcp__mcp-registry__search_mcp_registry,mcp__mcp-registry__suggest_connectors,mcp__mcp-registry__list_connectors,mcp__ccd_connectors__session_connectors_status,mcp__ccd_connectors__reconnect_session_connector,mcp__ccd_pr__get_status,mcp__ccd_window__open_session_in,mcp__ccd_window__close_split,mcp__ccd_window__set_sidebar_collapsed,mcp__ccd_window__get_window_layout --disallowedTools=SubscribePR --setting-sources=user,project,local --permission-mode=auto --allow-dangerously-skip-permissions --include-partial-messages --await-initialize --thinking-display omitted --replay-user-messages --settings {"fastMode":false,"deniedMcpServers":[{"serverName":"Claude Browser"},{"serverName":"Claude Code Android Emulator"},{"serverName":"Claude Code iOS Simulator"},{"serverName":"Claude Preview"},{"serverName":"Claude_Browser"},{"serverName":"Claude_Code_Android_Emulator"},{"serverName":"Claude_Code_iOS_Simulator"},{"serverName":"Claude_Preview"},{"serverName":"Claude_for_Chrome"},{"serverName":"Framebuffer"},{"serverName":"Window Halo"},{"serverName":"Window_Halo"},{"serverName":"ccd_connectors"},{"serverName":"ccd_directory"},{"serverName":"ccd_host"},{"serverName":"ccd_pr"},{"serverName":"ccd_session"},{"serverName":"ccd_session_mgmt"},{"serverName":"ccd_settings"},{"serverName":"ccd_sidebar"},{"serverName":"ccd_turn"},{"serverName":"ccd_view"},{"serverName":"ccd_window"},{"serverName":"claude-in-chrome"},{"serverName":"claude_browser"},{"serverName":"claude_code_android_emulator"},{"serverName":"claude_code_ios_simulator"},{"serverName":"claude_for_chrome"},{"serverName":"claude_in_chrome"},{"serverName":"claude_preview"},{"serverName":"computer-use"},{"serverName":"computer_use"},{"serverName":"cowork"},{"serverName":"cowork-onboarding"},{"serverName":"cowork_onboarding"},{"serverName":"dev-debug"},{"serverName":"dev_debug"},{"serverName":"dispatch"},{"serverName":"framebuffer"},{"serverName":"mcp-registry"},{"serverName":"mcp_registry"},{"serverName":"plugins"},{"serverName":"remote-devices"},{"serverName":"remote_devices"},{"serverName":"scheduled-tasks"},{"serverName":"scheduled_tasks"},{"serverName":"session_info"},{"serverName":"skills"},{"serverName":"window_halo"}]}
    action: none — its session is still alive — the session owns it (pid 79176); it ends with that session, or stop it from there
- fin-f00ab0e8 | 154 finished registry entries
    owner: plugin — registry · age: - · state: finished
    evidence: pid gone or recycled: 10240-d0c74e89f1adf5fc 12133-2cf390b50e5efc80 12281-4f350d0afceda8e8 12423-0a53d9f241e15b0c 12561-adc166045cc4bb05 +149 more
    action: reap — their processes are gone; reap prunes the entry files and sends no signal
  note: proc-registry.sh: 161 row(s); scan: 2 unregistered
## Run locks
- lock-7ed85c8e | run lock — primary /Users/<name>/Documents/work/AI/ai-agent-manager
    owner: automate-lanes:automate-2026-10-22-123646 · age: 8h43m · state: held, holder alive
    evidence: LOCKED owner=automate-lanes:automate-2026-10-22-123646 pid=79176 age=31435; liveness=alive; run automate-2026-10-22-123646: running
    action: none — its holder is alive — the run owns the lock (it releases it when it ends)
- lock-ee3bb451 | run lock — lane /Users/<name>/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-22-123646/L8
    owner: automate:automate-2026-10-22-123646-L8 · age: 8h41m · state: held, holder dead, run still says running
    evidence: LOCKED owner=automate:automate-2026-10-22-123646-L8 pid=21073 age=31272; liveness=dead; run automate-2026-10-22-123646-L8: running
    action: none — its holder pid is dead but run automate-2026-10-22-123646-L8 still says running (it may continue in a fresh session) — `/automate --resume automate-2026-10-22-123646-L8` re-takes it; never reclaimed from here
- lock-a077166a | run lock — lane /Users/<name>/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-22-123646/L9
    owner: automate:automate-2026-10-22-123646-L9 · age: 8h40m · state: held, holder dead, run still says running
    evidence: LOCKED owner=automate:automate-2026-10-22-123646-L9 pid=26285 age=31255; liveness=dead; run automate-2026-10-22-123646-L9: running
    action: none — its holder pid is dead but run automate-2026-10-22-123646-L9 still says running (it may continue in a fresh session) — `/automate --resume automate-2026-10-22-123646-L9` re-takes it; never reclaimed from here
  note: 3 checkout(s) checked (primary + lanes), 0 unlocked
## Lanes
- lane-50eaa6a9 | lane L1 of automate-2026-10-08-033739
    owner: run automate-2026-10-08-033739 · age: 17d21h · state: abandoned
    evidence: path /Users/<name>/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-08-033739/L1; item .supervisor/requirements/s3-validation/01-scratch-doc-a.md; pr -
    action: lane-remove — abandoned, its clone still on disk — lane-remove salvages and removes it (it refuses unpushed, dirty or live lanes)
- lane-5206ebb0 | lane L2 of automate-2026-10-08-033739
    owner: run automate-2026-10-08-033739 · age: 17d21h · state: abandoned
    evidence: path /Users/<name>/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-08-033739/L2; item .supervisor/requirements/s3-validation/02-scratch-doc-b.md; pr -
    action: lane-remove — abandoned, its clone still on disk — lane-remove salvages and removes it (it refuses unpushed, dirty or live lanes)
- leaks-b5780e83 | leak check of wave automate-2026-10-08-033739
    owner: run automate-2026-10-08-033739 · age: - · state: leaks: found — worktrees, lanes-dir, config-checksum (claude-p not compared — pre-v2 snapshot; merge-watch not compared — pre-v2 snapshot)
    evidence: lane-status /Users/<name>/Documents/work/AI/ai-agent-manager/.supervisor/automate/automate-2026-10-08-033739.md --leaks (compare mode)
    action: none — report only — `lane-status /Users/<name>/Documents/work/AI/ai-agent-manager/.supervisor/automate/automate-2026-10-08-033739.md --leaks` prints each changed section
- lane-feef777f | lane L8 of automate-2026-10-22-123646
    owner: run automate-2026-10-22-123646 · age: 8h41m · state: running
    evidence: path /Users/<name>/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-22-123646/L8; item .supervisor/requirements/automate-followups/39f-janitor-command.md; pr -
    action: none — running — the wave's coordinator owns it (`/automate --resume automate-2026-10-22-123646`; fleet-closeout removes it after merge)
- lane-8bff6330 | lane L9 of automate-2026-10-22-123646
    owner: run automate-2026-10-22-123646 · age: 8h41m · state: answer_pending
    evidence: path /Users/<name>/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-22-123646/L9; item .supervisor/requirements/parallel-automate/25-backlog-board-feeds.md; pr -; answer to toolu_01ThZZ5whnjhbqYFZsfXVbGa held 2026-10-26T01:52:04Z (last launch state: held_for_load — memory_pressure); the next /automate --resume poll delivers it: lane-answer /Users/<name>/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-22-123646/L9 --deliver-pending --owner-command '<cmd>'
    action: none — answer_pending — the wave's coordinator owns it (`/automate --resume automate-2026-10-22-123646`; fleet-closeout removes it after merge)
- leaks-55c2bc1c | leak check of wave automate-2026-10-22-123646
    owner: run automate-2026-10-22-123646 · age: - · state: leaks: found — lanes-dir, claude-p
    evidence: lane-status /Users/<name>/Documents/work/AI/ai-agent-manager/.supervisor/automate/automate-2026-10-22-123646.md --leaks (compare mode)
    action: none — report only — `lane-status /Users/<name>/Documents/work/AI/ai-agent-manager/.supervisor/automate/automate-2026-10-22-123646.md --leaks` prints each changed section
  note: 7 wave(s) skipped: every lane removed
## Worktrees and branches
- wt-9b6f0a3c | app /Users/<name>/Documents/work/AI/ai-agent-manager/.claude/worktrees/infallible-pike-587cfa
    owner: the host app · age: 4d08h · state: kept
    evidence: clean and merged (branch fix/salvage-drain-records: PR #664 MERGED, tip == merged head ab8f375f06a4) — left in place; the app removes its own worktrees
    action: none — report only — the sweep keeps it for the reason in its evidence; `sweep --apply` never removes it while that holds
- wt-e8bf748f | app /Users/<name>/Documents/work/AI/ai-agent-manager/.claude/worktrees/objective-snyder-c34717
    owner: the host app · age: 3d14h · state: kept
    evidence: clean and merged (branch fix/lanes-test-parts-standalone-guard: PR #678 MERGED, tip == merged head 7bf9c9005a73) — left in place; the app removes its own worktrees
    action: none — report only — the sweep keeps it for the reason in its evidence; `sweep --apply` never removes it while that holds
- wt-82a8c7aa | app /Users/<name>/Documents/work/AI/ai-agent-manager/.claude/worktrees/resolve-679-conflict-698bc9
    owner: the host app · age: 2d08h · state: kept
    evidence: branch merge-679-main: no PR for this branch — left in place; the app removes its own worktrees
    action: none — report only — the sweep keeps it for the reason in its evidence; `sweep --apply` never removes it while that holds
- br-0666c0c8 | branch chore/dreaming-2026-10-02
    owner: local branch · age: 23d17h · state: removable
    evidence: PR #344 MERGED, tip == merged head e6dfb378b73f
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-f9df53a7 | branch chore/m1-untrack-run-history
    owner: local branch · age: 22d21h · state: removable
    evidence: PR #361 MERGED, tip == merged head f4282631dc0e
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-c77b4baa | branch chore/meta-scrub-cleanup
    owner: local branch · age: 22d23h · state: removable
    evidence: PR #359 MERGED, tip == merged head b06a5054bcb9
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-5ba487c8 | branch chore/release-15.126.0
    owner: local branch · age: 16d09h · state: removable
    evidence: PR #444 MERGED, tip == merged head 0d3c120743cc
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-00d1b257 | branch chore/release-15.128.1
    owner: local branch · age: 14d23h · state: removable
    evidence: PR #467 MERGED, tip == merged head 856df84870bd
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-e7e28d9f | branch chore/release-v17.3.0
    owner: local branch · age: 10d14h · state: removable
    evidence: PR #557 MERGED, tip == merged head a1142f11a3a0
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-807dc619 | branch chore/triage-proposed-2026-10-01
    owner: local branch · age: 23d18h · state: removable
    evidence: PR #343 MERGED, tip == merged head 2ec967b486ae
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-280bd78e | branch claude/nostalgic-lovelace-c60600
    owner: local branch · age: 8d19h · state: removable
    evidence: PR #590 MERGED, tip == merged head bbe8c80f4a19
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-1b0ddbae | branch docs/final-state-d1-d2-amendment
    owner: local branch · age: 25d12h · state: removable
    evidence: PR #316 MERGED, tip == merged head 2a63137ccfaf
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-37405451 | branch feat/po-wave-shaping-scope-fence
    owner: local branch · age: 8d21h · state: removable
    evidence: PR #586 MERGED, tip == merged head a91efe930e52
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-4bf45b29 | branch feature/lanes-pane-ux
    owner: local branch · age: 13d00h · state: removable
    evidence: PR #507 MERGED, tip == merged head f35fd4301ff7
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-c1488f45 | branch fix/automate-runfile-write-fail-closed
    owner: local branch · age: 24d21h · state: removable
    evidence: PR #322 MERGED, tip == merged head 4e03626c03c6
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-ebcbcdbe | branch fix/automate-trail-pr-behind-main
    owner: local branch · age: 23d12h · state: removable
    evidence: PR #356 MERGED, tip == merged head 742690b0d944
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-a830e087 | branch fix/bash53-locale-prefix-segfault
    owner: local branch · age: 23d10h · state: removable
    evidence: PR #355 MERGED, tip == merged head 56ebd80b6e37
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-8aa17b35 | branch fix/harvest-c3-path-independent
    owner: local branch · age: 22d17h · state: removable
    evidence: PR #363 MERGED, tip == merged head a7657ab537b4
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-d9c6bc10 | branch fix/lane-task-plan-push
    owner: local branch · age: 15d11h · state: removable
    evidence: PR #457 MERGED, tip == merged head 01fcd5f7edfe
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-b3c18965 | branch fix/pin-no-pr-run-line
    owner: local branch · age: 9d21h · state: removable
    evidence: PR #572 MERGED, tip == merged head ba9b161de1fc
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-574bcbb1 | branch fix/repo-scan-gates-skip-ignored
    owner: local branch · age: 22d17h · state: removable
    evidence: PR #362 MERGED, tip == merged head bc9eb0a415c7
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-d8019743 | branch fix/token-ledger-transcript-identity-gate
    owner: local branch · age: 17d01h · state: removable
    evidence: PR #439 MERGED, tip == merged head c83f7f187e26
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-073f74b9 | branch fix/w2-lane-defects
    owner: local branch · age: 14d23h · state: removable
    evidence: PR #466 MERGED, tip == merged head 12a36944408a
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-1b31a7a6 | branch release/v17-after-wave7
    owner: local branch · age: 5d01h · state: removable
    evidence: PR #649 MERGED, tip == merged head 0e0291ccc494
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-7eeef581 | branch wave/automate-2026-10-14-041009-w1
    owner: local branch · age: 11d17h · state: removable
    evidence: PR #541 MERGED, tip == merged head 3925a6323390
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-e29f35f2 | branch wave/automate-2026-10-15-163325-w1
    owner: local branch · age: 10d01h · state: removable
    evidence: PR #567 MERGED, tip == merged head ec62ca25f22b
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-fa0bf4b7 | branch wave/automate-2026-10-15-163325-w2
    owner: local branch · age: 9d15h · state: removable
    evidence: PR #582 MERGED, tip == merged head 77164c518f72
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-d49efdbb | branch wave/automate-2026-10-15-163325-w3
    owner: local branch · age: 8d13h · state: removable
    evidence: PR #596 MERGED, tip == merged head 4c6b4720b232
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-9f664b8a | branch wave/automate-2026-10-15-163325-w4
    owner: local branch · age: 7d15h · state: removable
    evidence: PR #606 MERGED, tip == merged head e71e0b89929a
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-923a7d4d | branch wave/automate-2026-10-15-163325-w7
    owner: local branch · age: 5d11h · state: removable
    evidence: PR #641 MERGED, tip == merged head 0988e3899fe0
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-7097b99a | branch wave/automate-2026-10-22-123646-w1
    owner: local branch · age: 2d07h · state: removable
    evidence: PR #685 MERGED, tip == merged head 3f51d0446b5d
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-5e9385cb | branch wave/w2
    owner: local branch · age: 15d06h · state: removable
    evidence: PR #465 MERGED, tip == merged head 94fa1b3b67ed
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-1bc5ec72 | branch wave/w3
    owner: local branch · age: 14d17h · state: removable
    evidence: PR #474 MERGED, tip == merged head df7ced0a195a
    action: sweep-apply — the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep (31 would-remove row(s)) — sweep has no per-path filter
- br-2d4b88ad | branch wave/w4
    owner: local branch · age: 14d10h · state: removable
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
    evidence: candidates: 50 file(s), 178849 bytes, oldest 183 days, newest 93 days
    action: none — report only — `retention-sweep.sh --project-root /Users/<name>/Documents/work/AI/ai-agent-manager --delete` removes them (irreversible)
- mpf-348e0132 | metadata push failure of run automate-2026-10-08-033739
    owner: run automate-2026-10-08-033739 · age: 17d21h · state: push failed
    evidence: 2026-10-08T04:44:53Z scrub .supervisor/automate/automate-2026-10-08-033739.md: home_path
    action: none — report only — the run's next trail push retries it (`/automate --resume automate-2026-10-08-033739`), or publish by hand with meta-sync.sh push
  note: retention-sweep: summary — 50 candidate file(s); nothing removed (report-only; pass --delete to remove the files listed above)
## Plugin-adjacent (report only)
  (no rows)
  note: ci-slot.sh status: 0 holder(s), 0 waiter(s), 2 slot(s)
## Not the plugin's (report only)
- ext-8b02b1cb | host session pid 79176
    owner: not the plugin's — the host's own session · age: 8h46m · state: running
    evidence: /Users/<name>/Library/Application Support/Claude/claude-code/2.1.308/a93ded4b1b47/claude.app/Contents/MacOS/claude --output-format stream-json --verbose --input-format stream-json --effort=high --model=claude-opus-5-5 --permission-prompt-tool=stdio --allowedTools=mcp__computer-use,mcp__ccd_session__spawn_task,mcp__ccd_session__dismiss_task,mcp__ccd_session__mark_chapter,mcp__ccd_session_mgmt__list_sessions,mcp__ccd_session_mgmt__get_session,mcp__ccd_session_mgmt__get_usage,mcp__ccd_host__get_storage_usage,mcp__ccd_session_mgmt__set_session_title,mcp__ccd_session_mgmt__send_message,mcp__ccd_session_mgmt__detach_session,mcp__ccd_sidebar__list_groups,mcp__ccd_sidebar__create_group,mcp__ccd_sidebar__set_view,mcp__ccd_sidebar__list_sections,mcp__ccd_sidebar__create_section,mcp__ccd_turn__wrap_up,mcp__ccd_turn__update_plan,mcp__ccd_session_mgmt__search_session_transcripts,mcp__ccd_session_mgmt__list_events,mcp__ccd_session_mgmt__export_transcript,mcp__scheduled-tasks__list_task_runs,mcp__ccd_session__read_widget_context,mcp__ccd_session__list_start_targets,mcp__ccd_view__show_pane,mcp__ccd_view__close_pane,mcp__ccd_view__get_layout,mcp__ccd_view__set_transcript_view,mcp__ccd_settings__get_settings,mcp__mcp-registry__search_mcp_registry,mcp__mcp-registry__suggest_connectors,mcp__mcp-registry__list_connectors,mcp__ccd_connectors__session_connectors_status,mcp__ccd_connectors__reconnect_session_connector,mcp__ccd_pr__get_status,mcp__ccd_window__open_session_in,mcp__ccd_window__close_split,mcp__ccd_window__set_sidebar_collapsed,mcp__ccd_window__get_window_layout --disallowedTools=SubscribePR --setting-sources=user,project,local --permission-mode=auto --allow-dangerously-skip-permissions --include-partial-messages --await-initialize --thinking-display omitted --replay-user-messages --settings {"fastMode":false,"deniedMcpServers":[{"serverName":"Claude Browser"},{"serverName":"Claude Code Android Emulator"},{"serverName":"Claude Code iOS Simulator"},{"serverName":"Claude Preview"},{"serverName":"Claude_Browser"},{"serverName":"Claude_Code_Android_Emulator"},{"serverName":"Claude_Code_iOS_Simulator"},{"serverName":"Claude_Preview"},{"serverName":"Claude_for_Chrome"},{"serverName":"Framebuffer"},{"serverName":"Window Halo"},{"serverName":"Window_Halo"},{"serverName":"ccd_connectors"},{"serverName":"ccd_directory"},{"serverName":"ccd_host"},{"serverName":"ccd_pr"},{"serverName":"ccd_session"},{"serverName":"ccd_session_mgmt"},{"serverName":"ccd_settings"},{"serverName":"ccd_sidebar"},{"serverName":"ccd_turn"},{"serverName":"ccd_view"},{"serverName":"ccd_window"},{"serverName":"claude-in-chrome"},{"serverName":"claude_browser"},{"serverName":"claude_code_android_emulator"},{"serverName":"claude_code_ios_simulator"},{"serverName":"claude_for_chrome"},{"serverName":"claude_in_chrome"},{"serverName":"claude_preview"},{"serverName":"computer-use"},{"serverName":"computer_use"},{"serverName":"cowork"},{"serverName":"cowork-onboarding"},{"serverName":"cowork_onboarding"},{"serverName":"dev-debug"},{"serverName":"dev_debug"},{"serverName":"dispatch"},{"serverName":"framebuffer"},{"serverName":"mcp-registry"},{"serverName":"mcp_registry"},{"serverName":"plugins"},{"serverName":"remote-devices"},{"serverName":"remote_devices"},{"serverName":"scheduled-tasks"},{"serverName":"scheduled_tasks"},{"serverName":"session_info"},{"serverName":"skills"},{"serverName":"window_halo"}]}
    action: none — report only — the plugin did not start it; close it from the host (end that session, or quit the app)
janitor: summary — 55 row(s), 36 actionable (reap=3, sweep-apply=31, lane-remove=2)
```

## Interactive run

pending — owner run at review
