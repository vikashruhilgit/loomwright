# Guard probes — 2026-09-23

Live probes for `six-phase-loop-gaps/02-test-integrity-guard`, run against `claude 2.1.280` from a
throwaway git-init'd scratch dir (`/tmp/guard-probe-*`, never committed), using a temporary
`PreToolUse` logging hook (`cat >> "$PROBE_LOG"` / `env >> file`) — never the plugin's real
`hooks.json`. Each answer below gates a design decision in `guard-arm.sh` / `guard-test-integrity.sh`.

## P1 — session-id equality under `claude -p`

**Launch mode:** `claude -p --permission-mode bypassPermissions "<prompt>"` (run 1, no `--session-id`)
and `claude -p --permission-mode bypassPermissions --session-id <uuid> "<prompt>"` (run 2), prompt asks
the agent to run `printf '%s' "$CLAUDE_CODE_SESSION_ID" > envid.txt`.

**Answer: YES, all three agree in both runs.**
- Run 1 (no `--session-id`): `envid.txt` contents == hook payload `session_id` ==
  `a1700e13-1d0a-4fd6-ae75-3321a7120daf` (`p1-run1-payload.json`).
- Run 2 (`--session-id 12345678-1234-4234-8234-1234567890ab`): `envid.txt` contents == hook payload
  `session_id` == the passed uuid (`p1-run2-payload.json`).

**Consequence:** `CLAUDE_CODE_SESSION_ID` is a reliable naming source for `guard-arm.sh arm`'s own
marker file, and for the dispatcher's `--session-id` pre-arm — no fallback needed, no change to the
`arm` source's session-id-reading approach.

**Gotcha found while probing (not part of the P1 question itself, recorded for the next worker):** a
nested `claude -p` invocation fails auth (`Failed to authenticate: OAuth session expired and could not
be refreshed`) when launched with `--setting-sources project` (excludes the `user` source that carries
the credential path) — transient once, then reproducible whenever `--setting-sources` narrows away
`user`. Omit that flag unless you specifically need to test settings-source scoping.

## P2 — `agent_type` on a subagent's `PreToolUse`

**Launch mode:** same throwaway hook (matchers `Bash` and `Agent|Task`), one `claude -p` prompt that
(a) runs a Bash command directly on the main thread, then (b) spawns exactly one
`Task(subagent_type: general-purpose)` that runs its own Bash command.

**Answer: YES.**
- Outer main-thread `PreToolUse[Bash]` payload (`p2-outer-bash.json`): `agent_type: null`,
  `agent_id: null`.
- `PreToolUse[Agent]` spawn payload (`p2-agent-spawn.json`): `tool_name: "Agent"` (matches
  `spawn-probe-2026-09-02/pretooluse-task-1.json`'s prior finding — `Task` kept in the backstop matcher
  for older builds only).
- Inner subagent's own `PreToolUse[Bash]` payload (`p2-inner-subagent-bash.json`): `agent_type:
  "general-purpose"`, `agent_id: "ad0939f4f3bb731fa"` present. All three payloads share the same
  top-level `session_id` (the main session's id) — consistent with the memory
  `subagentstop-payload-shape` finding for `PostToolUse`, now independently confirmed for
  `PreToolUse` too.

**Consequence:** the two deny-message variants in Scope item 2 are both reachable — key on
`agent_type` presence (non-null ⇒ subagent wording, null/absent ⇒ main-thread wording). The `NO`
fallback (collapse to one wording) does not apply.

## P3 — does `settings.json`'s `env` block reach hook processes?

**Launch mode:** rather than editing the real `~/.claude/settings.json` (which holds live OAuth/API
secrets and is correctly blocked from scripted edits by the auto-mode classifier as
"Irreversible Local Destruction" — respected, not worked around), used `claude -p`'s own
`--settings '<json>'` flag ("Path to a settings JSON file or a JSON string to load **additional
settings** from") to layer an `env.LOOMWRIGHT_GUARD_P3_CANARY` key plus a `PreToolUse[Bash]` hook that
runs `env >> file` before the real command. This is the same settings-merge mechanism a real
`settings.json`'s `env` block uses — a faithful test of the question without touching the live global
file.

**Answer: YES** — `p3-payload.json` is the logged tool-call payload; the paired `env` dump (not
committed — it would contain the full hook-process environment, including this sandbox's own secrets)
showed exactly one `LOOMWRIGHT_GUARD_P3_CANARY=canary-value-12345` line, proving the settings-supplied
`env` var reached the hook command's process environment.

**Consequence:** `/.claude/settings*.json` protection in Scope item 2's `Write|Edit` matcher is
**load-bearing, not belt-and-braces** — a detached drain's fresh `claude -p` process would otherwise
honour an opt-out (or any other env override) written mid-run into `settings.json`/`settings.local.json`
by an armed agent, closing exactly the bypass route the requirement's §3 describes.

## Fixture files
- `p1-run1-payload.json`, `p1-run2-payload.json` — P1's two runs.
- `p2-outer-bash.json`, `p2-agent-spawn.json`, `p2-inner-subagent-bash.json` — P2's three logged
  payloads in call order.
- `p3-payload.json` — P3's logged `Bash` payload (paired `env` dump intentionally not committed —
  environment dumps routinely carry secrets; the canary hit is described above instead).
