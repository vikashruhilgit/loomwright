# SubagentStop real payload shape — SubagentHandback delivery

Captured 2026-09-27 (Claude Code desktop, `claude-desktop` entrypoint) by a
temporary `SubagentStop` hook that tee'd stdin to a file, while a real
`loomwright:code-reviewer` and a real `loomwright:worker` ran. Sanitized: every
home path is `/Users/testuser/...`, ids are zeroed, and all message content is
replaced by placeholders. The **key set of `payload.json`** and the **entry
sequence of `agent-transcript.jsonl`** are exactly what the runtime produced.

What the capture showed:

- The subagent's full report (including its `*_RESULT` block) is the
  `input.message` of the LAST `SubagentHandback` `tool_use` in
  `agent_transcript_path`.
- `last_assistant_message` is only a short prose recap that typically NAMES the
  block ("I sent back the CODE_REVIEW_RESULT block") without containing it.
- `cwd`, `transcript_path`, `agent_transcript_path` and `scratchpad_dir` are
  absolute paths.

Consequence before the fix: `validate-worker-result.py` returned
`{"decision": "block", "reason": "missing WORKER_RESULT block …"}` for a worker
that had emitted a valid block, and the runtime re-prompted it
(`stop_hook_active: true` on the re-fire). `send-webhook.sh` found no `status:`
and skipped the POST; `emit-progress-event.sh` recorded
`result_block_present: false` (→ `ended_without_result`).

`materialize.py` fills the placeholders and rewrites `agent_transcript_path`
to the materialised file's absolute path. Consumers: `test-result-validators.sh`
(section L), `test-webhook.sh`, `test-progress-state.sh`.
