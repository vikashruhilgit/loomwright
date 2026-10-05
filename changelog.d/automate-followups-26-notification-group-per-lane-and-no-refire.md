<!-- bump: patch -->
Desktop notifications at fleet scale: one banner group per session, one banner per question
`notify-desktop.sh` no longer puts every macOS banner in one fixed `terminal-notifier` group, which made each
parallel lane's banner remove every other lane's. The group is now `loomwright-<first 8 sanitised chars of the
session id>`, or `loomwright-p<cksum of the checkout path>` when no session id resolves, so a burst within one session
still coalesces. A resumed session replays the same `AskUserQuestion` tool call (same `tool_use_id`) to deliver the
answer, which re-fired the hook. Both leaves of that hook now skip an id they have already seen. `notify-desktop.sh`
uses `.supervisor/logs/.notified-ids`, records the id at first sight (before the debounce) and logs `skip replay` to
`notifications.log`. `emit-lifecycle.sh waiting ask_user` uses its own `.lifecycle-asked-ids` and records only after
the row is written, so the session JSONL carries one `waiting`/`ask_user` row per question. The two ledgers are
separate because both scripts run in sequence on one payload, and a shared one would drop the first ask's row. Each
ledger keeps the newest 200 ids and fails toward notifying. `notify-desktop.sh` also appends a
`notify group=<group> tool_use_id=<id>` audit line on every host. `send-webhook.sh` still re-fires on a replay; that
is a named follow-up.
