# Evidence — a skipped guard arm leaves a durable trace (af/39c)

Real output captured 2026-10-28 on branch `feature/af39c-guard-arm-trace`, running the BRANCH copy of
`loomwright/scripts/guard-arm.sh` against scratch projects (`mktemp -d` + `git init`, nothing in the real
`.supervisor/`). Paths are redacted to `<scratch>`; the exit codes and rows are verbatim. Every run exits 0:
the leaf stays fail-SAFE and keeps its `|| true` in `hooks.json`.

## Branch copy, three fixture payloads

### Fixture 1 — jq hidden from PATH (valid session_id)
```text
$ printf '{"session_id":"sess-evid-1","tool_input":{"subagent_type":"loomwright:loomwright:worker"}}' | PATH=<dir of symlinks to cat git sed date tr mkdir rm, no jq> CLAUDE_PROJECT_DIR=<scratch> bash loomwright/scripts/guard-arm.sh arm-from-payload
exit=0
$ cat <scratch>/.supervisor/logs/sess-evid-1.jsonl
{"event":"guard_arm_skipped","reason":"jq_missing","subagent_type":"loomwright:loomwright:worker","session_id":"sess-evid-1","cc_session_id":"sess-evid-1","ts":"2026-10-28T07:59:45Z"}
$ find <scratch>/.supervisor -type f
.supervisor/logs/sess-evid-1.jsonl
```

### Fixture 2 — payload without a session_id
```text
$ printf '{"tool_input":{"subagent_type":"loomwright:loomwright:worker"}}' | CLAUDE_PROJECT_DIR=<scratch> bash loomwright/scripts/guard-arm.sh arm-from-payload
exit=0
$ cat <scratch>/.supervisor/guard/arm-skipped.jsonl
{"event":"guard_arm_skipped","reason":"no_session_id","subagent_type":"loomwright:loomwright:worker","ts":"2026-10-28T07:59:45Z"}
$ find <scratch>/.supervisor -type f
.supervisor/guard/arm-skipped.jsonl
```

### Fixture 3 — unwritable guard dir (`.supervisor/guard` is a regular file)
```text
$ printf '{"session_id":"sess-evid-3","tool_input":{"subagent_type":"loomwright:loomwright:worker"}}' | CLAUDE_PROJECT_DIR=<scratch> bash loomwright/scripts/guard-arm.sh arm-from-payload
guard_arm_failed: cannot create guard dir
exit=0
$ cat <scratch>/.supervisor/logs/sess-evid-3.jsonl
{"event":"guard_arm_skipped","reason":"marker_write_failed","subagent_type":"loomwright:loomwright:worker","session_id":"sess-evid-3","cc_session_id":"sess-evid-3","ts":"2026-10-28T07:59:45Z"}
```

The `guard_arm_failed: cannot create guard dir` line in fixture 3 is `write_marker`'s own pre-existing
stderr; the trace row is the new part.

## Installed copy + completion tail

Run 2026-10-28 from the owner's opted-out session, against the INSTALLED plugin copy
(`~/.claude/plugins/cache/atelier/loomwright/17.21.1/scripts/guard-arm.sh`). **That copy is v17.21.1,
which predates this change, so it shows the OLD silent behaviour** — this is the baseline the change
fixes, not evidence of the new code. Same scratch-repo fixtures as above:

| Fixture | Exit | Row written |
|---|---|---|
| no `session_id` | 0 | none (nothing under `.supervisor/`) |
| `jq` hidden from PATH, valid id | 0 | none |
| guard dir is a regular file, valid id | 0 | none (one stderr line `guard_arm_failed: cannot create guard dir`) |

The branch copy's behaviour for the same three payloads is in the sections above. The installed copy
picks up the new behaviour only after this PR merges and the plugin is updated.

**Completion tail `**Test guard:**` line:** this run's own Supervisor completion tail ran on the
installed v17.21.1 driver, which has no `test_guard` field, so its `## Outcome` cannot show the new
line. The branch behaviour of that line is pinned by `test-supervisor-next-step.sh`'s `test_guard`
cases and the regenerated handover goldens (`test_guard: "unarmed (marker_missing)"`).