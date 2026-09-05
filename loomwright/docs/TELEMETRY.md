# Telemetry — GitHub Issues as Storage

**Status:** Initial design draft (Subtask #1). Architecture diagram, post-implementation
authoritative tables, and the no-default-repo subsection will be expanded in Subtask #5
once the wrapper, core, and `/telemetry` slash command land.

---

## Overview

Telemetry is an **opt-in**, structured feedback channel that turns finished
agent runs (`SUPERVISOR_RESULT`, `CODE_REVIEW_RESULT`, `QA_RESULT`) into GitHub
issues in a target repo of the user's choice. Each issue carries a derived
score, a labelled categorisation, and a redacted JSON payload. The goal is
longitudinal analysis: identify weak agents, find recurring failure modes,
and improve prompts and skills over many runs.

The system is:

- **Opt-in only.** Disabled until the user explicitly runs `/telemetry enable`
  or sets the `LOOMWRIGHT_TELEMETRY_REPO` env var.
- **Storage-free for the plugin.** No backend. GitHub Issues is the database;
  labels are the index.
- **Hook-driven, fire-and-forget.** A `SubagentStop` hook invokes a wrapper
  shell script. The wrapper never blocks the agent run — it always exits 0.
- **Privacy-first.** A regex deny-list inside the core script blocks any
  payload that looks like a secret, file path, email, or `.env` content.
- **Deterministic.** The same result block scored twice produces the same
  number — no randomness, no timestamps in the score function.

Out of scope for the initial implementation (tracked in
[Future Work](#future-work) below): session-level batch issues, weekly
summary bots, and any backend service.

---

## Architecture

The system is split into a **wrapper** and a **core** to satisfy two
otherwise-contradictory requirements:

1. The hook contract requires the script to never fail the agent run
   (always exit 0).
2. Privacy and configuration violations must fail closed (refuse to send,
   exit non-zero, leave an audit trail).

The split lets each script honour exactly one of those requirements.

```
SubagentStop hook (hooks.json)
       |
       | stdin: JSON payload from Claude Code
       v
[ ${CLAUDE_PLUGIN_ROOT}/scripts/send-telemetry.sh ]   <-- WRAPPER
       |   - pipes stdin to core
       |   - captures core's exit code + stderr
       |   - redacts stderr through the privacy whitelist
       |   - appends one structured line to .supervisor/logs/telemetry.log
       |   - opportunistically reaps stale per-session flags (>24h)
       |   - ALWAYS exits 0
       v
[ ${CLAUDE_PLUGIN_ROOT}/scripts/send-telemetry-core.sh ]   <-- CORE
       - resolves the agent's result text (§Result-text extraction)
       - parses the resolved result block
       - resolves consent + target repo
       - applies interest filter and dedup
       - runs privacy whitelist (fail-closed)
       - derives score per the rubric below
       - formats issue body + labels
       - calls `gh issue create`
       - writes to telemetry-sent.log on success
       - exits 0..5 per the contract below
```

> **Diagram note:** This sketch will be promoted to a fuller diagram
> in Subtask #5 alongside the post-implementation polish.

### Result-text extraction (SubagentStop payload shape) — authoritative

Both `send-telemetry-core.sh` and `send-webhook.sh` (the `supervisor_result`
path) need the finishing subagent's final output text to parse the
`SUPERVISOR_RESULT` / `CODE_REVIEW_RESULT` / `QA_RESULT` block out of it. That
text is **not** in a top-level `result_block` field — a real Claude Code
`SubagentStop` payload does not carry one.

**Verified payload shape** (captured from a real `SubagentStop` hook fire — the
Claude Code hook docs guarantee only `transcript_path`, but current payloads
carry these fields):

```json
{
  "session_id": "…",
  "transcript_path": "…/<session>.jsonl",
  "agent_transcript_path": "…/<session>/subagents/agent-<id>.jsonl",
  "agent_id": "…",
  "agent_type": "loomwright:supervisor-runner",
  "hook_event_name": "SubagentStop",
  "stop_hook_active": false,
  "last_assistant_message": "## SUPERVISOR_RESULT\n- status: completed\n…",
  "cwd": "…", "permission_mode": "…", "effort": { "level": "…" }
}
```

There is **no** `result_block`, no `output`, no `agent_output`. The subagent's
final text is in **`last_assistant_message`**.

**Resolution chain (both scripts, in order):**

1. `last_assistant_message` — the real, observed inline field. **Primary.**
2. `result_block` → `output` → `agent_output` — legacy / forward-compat names.
   Retained so existing fixtures and any future payload that re-adds them keep
   working; absent on real payloads today.
3. Last assistant message read out of the transcript JSONL — preferring the
   subagent-scoped **`agent_transcript_path`** (the `code-reviewer` /
   `qa-executor` / `supervisor-runner` SubagentStop hooks all fire from a
   Task-spawned subagent, whose own messages live here), then the shared
   session **`transcript_path`**. This is the only field the hook docs
   guarantee, so it is the durable fallback.

`scripts/validate-launch-pad-result.py` (the `launch-pad-runner` SubagentStop
validator) uses the same chain — keep all three in sync. The historical
mistake (reading only `.result_block`, which is always empty) silently
suppressed every supervisor-completion webhook and every telemetry post until
v14.2.1.

> **Privacy note:** when the result text is recovered from the transcript
> JSONL it is **not** a top-level payload field, so the raw-payload secret scan
> (which walks payload string fields) would not see it. The core therefore also
> raw-scans the *resolved* result text before redaction, preserving the
> fail-closed guarantee. See §Deny-list.

### Token ledger (additive session-log probe)

**Probe result:** the verified `SubagentStop` payload shape above carries
**no** `usage`, `input_tokens`, `output_tokens`, `cache_read_input_tokens`,
`cache_creation_input_tokens`, or nested `usage` object. Exact token counts
are not available on the hook fire. The plugin therefore records an additive
`token_ledger` JSONL event that prefers real usage fields when present and
falls back to a **transcript-byte proxy** when they are absent (the expected
path today). The proxy is **never** labelled as tokens and **never** invents
token counts.

**Emitter:** `${CLAUDE_PLUGIN_ROOT}/scripts/emit-token-ledger.sh` — fail-SAFE,
always exits 0. Reads SubagentStop JSON from stdin; appends **one** additive
line to `.supervisor/logs/{session_id}.jsonl` (creates the dir/file as needed).
Requires `python3` (same dependency as `send-telemetry.sh`); when python3 is
absent the emitter no-ops and prints a **one-time** stderr note (flag file under
`.supervisor/logs/`). Empty stdin, unreadable proxy paths, or no resolvable
session id → silent no-op, exit 0.

**Session-id resolution (join key):** SubagentStop's `session_id` is Claude
Code's session UUID, but plugin session logs (including `session_end`) are named
by the **plugin** session id (e.g. `supervisor-2026-07-07-fable-parity`). To keep
`token_ledger` joinable to a run/PR for `/insights` and job 04's
`graph_context_used` pairing, the emitter:

1. Prefers `.supervisor/state.md`'s `- session_id:` when `- status:` is
   `running` or `checkpoint` (active Supervisor run).
2. Falls back to the Claude Code UUID from the payload otherwise.
3. Always records the Claude Code UUID as additive `cc_session_id` when present.

> **Best-effort join caveat:** the state.md join is per-project, not per-subagent —
> while a Supervisor run is `running`/`checkpoint`, a qualifying subagent completing
> for an UNRELATED context in the same project (e.g. a standalone `/review-pr` drain
> or an ad-hoc `/code-reviewer`) will land its `token_ledger` line in that run's log.
> Advisory-only data; use `cc_session_id` to disambiguate when it matters.

**Event schema** (`"event":"token_ledger"` — matches session-log conventions):

```json
{
  "event": "token_ledger",
  "session_id": "supervisor-2026-07-14-token-ledger",
  "cc_session_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "ts": "2026-07-14T09:00:00Z",
  "agent_type": "loomwright:code-reviewer",
  "agent_id": "…",
  "proxy": true,
  "token_proxy_kind": "transcript_bytes",
  "token_proxy_transcript_bytes": 12345
}
```

| Field | When | Meaning |
|-------|------|---------|
| `session_id` | always (when emitted) | Plugin session id when an active `state.md` run is present; else the Claude Code UUID. Log filename key. |
| `cc_session_id` | when SubagentStop carries `session_id` | Claude Code UUID retained for debug / cross-tool correlation |
| `proxy` | always | `false` when any real usage signal is present; `true` for the transcript-byte fallback |
| `usage` / `input_tokens` / `output_tokens` / `cache_*` | usage present only | Copied from the payload as-is — never invented |
| `token_proxy_kind` | proxy path only | Closed value today: `"transcript_bytes"` |
| `token_proxy_transcript_bytes` | proxy path only | Byte size of `agent_transcript_path` (preferred) or `transcript_path` via `os.path.getsize` only |
| `agent_type`, `agent_id`, `ts` | optional / when present | Identity + UTC ISO timestamp; **omitted when absent** (never the literal `"unknown"`) |

**Additive key (v15.12.0+):** `orientation_source` — emitted only when `LOOMWRIGHT_ORIENTATION_SOURCE` is one of `memos|repo_map|graphify|none` (orientation attribution); omitted on unset/empty/invalid (fail-safe — the event line still writes). **Reader-side plumbing only in v15.12.0 — no in-repo producer sets the env var yet.** The emitter runs inside a SubagentStop `type: command` hook, which inherits the MAIN session environment — an `export` inside a subagent's Bash call (where the orientation tier is actually known) does NOT reach the hook process. The intended producer (a follow-up) writes the tier to a small gitignored state file under `.supervisor/` that the hook-side emitter reads; until that lands, the field is reserved plumbing and is simply omitted.

**Additive key (v15.14.0+):** `advisory_total` (+ `advisory_total_kind: "context_bytes"`) — a per-run TOTAL advisory-context SIZE summed across memos + rules + bridge + brain-context, read from `LOOMWRIGHT_ADVISORY_TOTAL_BYTES`. Emitted only when that value is a non-negative integer; **any other/unset value omits BOTH fields** (fail-safe — the event line still writes; same namespace discipline as `orientation_source`). Note `0` is a legal value and IS emitted (the guard is an integer check, not a truthiness test). **Same reader-side-plumbing caveat as `orientation_source` and `shared_prefix`: no in-repo producer sets this env var yet** — the SubagentStop hook inherits the MAIN session environment, so an `export` inside a subagent's Bash call does not reach the hook process; set it in the session environment to opt in. **Distinct from the era-bucket `advisory_tokens`** rendered in `/insights` (from `build-loop-evidence.sh`): `advisory_total` is a per-run **size-of-injected-context** measure, whereas `advisory_tokens` is a per-era **compute-spend** proxy. They are cross-linked on the dashboard and neither supersedes the other.

**Additive key (v15.13.0+):** `shared_prefix` — emitted as the JSON boolean `true` only when `LOOMWRIGHT_SHARED_PREFIX` is exactly `1`; omitted on any other/unset value (fail-safe — the event line still writes; same namespace discipline as `orientation_source`). Marks ledger lines from runs where the shared-agent-prefix layout is active, for the same-role-respawn cache-read measurement plan in `docs/POINTER_AUDIT.md` (cross-agent cache reuse is structurally zero — see the HONEST CACHE EXPECTATION there). Same reader-side-plumbing caveat as `orientation_source`: the SubagentStop hook inherits the MAIN session environment, and no in-repo producer sets the env var yet — set it in the session environment (e.g. shell profile or CI env) to opt in.

**Reserved future key (do not emit yet):** `graph_context_used` — reserved for
job 04 (graph/brain context attribution). Leave room in readers; the emitter
MUST NOT write this key today.

**Hook coverage:** the emitter is chained on the **same** `type: command`
hook lines that already run `send-telemetry.sh` (stdin fan-out — both scripts
see the payload; chaining onto an existing hook line adds no new hook
entry — see `loomwright/docs/HOOKS.md` §"Hook Table" for the authoritative,
current count):

| Matcher | Emits `token_ledger`? |
|---------|----------------------|
| `loomwright:code-reviewer` | yes |
| `loomwright:qa-executor` | yes |
| `loomwright:supervisor-runner` | yes |
| `loomwright:worker` | **no** — its SubagentStop hooks are validator/progress-event command hooks; no telemetry command hook |
| `loomwright:execute-manager` | **no** — its only SubagentStop hook is the validator command hook; no telemetry command hook (and no progress-event hook either — `emit-progress-event.sh` is on the `loomwright:worker` matcher above, not this one) |
| `loomwright:plan-reviewer` / `loomwright:launch-pad-runner` | no |

Self-test: `scripts/test-token-ledger.sh` (fixtures under
`scripts/token-ledger-fixtures/`).

### Progress state (`subtask_complete` event — one-writer-derived-state, v15.16.0)

**Probe result / why this exists:** progress state (`state.md`'s `## Session`
block — `session_id`/`branch`/`status`/`phase`) used to be written by
prompt-instructed Context-Keeper operations (`set_task` / `set_subtasks` /
`update_phase` / `checkpoint`) that the model had to remember to call while
doing the real work. This repo's own logs measured the miss rate: **785**
hook-written `token_ledger` events vs **6** agent-written `phase_transition`
events across 11+ sessions (a live re-count during this change; the
2026-07-28 requirement and CLAUDE.md cite an earlier **560**-event count —
785 supersedes it, cite 785 going forward). A second live re-count taken at
authoring time of this subtask (Subtask 3, one grep-hop later) found
**836** `token_ledger` events across **30** log files and **still only 6**
`phase_transition` events — the growth is this job's own Subtask 1/2
worker and reviewer spawns adding more `token_ledger` lines, while the
`phase_transition` count stayed flat at 6 even though those same
Subtask-1/2 workers ran under the **pre-deletion** prompts (the deletion
only lands in the files ST-2 itself edits) and so still had the mechanism
available to invoke — reinforcing, not just repeating, the miss-rate
finding. Numbers drift between any two counts taken hours apart in an
active repo; re-run these two commands from the repo root for a number
current to your own moment, rather than trusting either 785 or 836 as a
fixed constant — **note the two events are written with different JSON
keys** (`token_ledger` uses `"event":`, `phase_transition` uses `"type":`;
a single grep pattern does not catch both):

```
grep -o '"event":"token_ledger"' .supervisor/logs/*.jsonl | wc -l
grep -o '"type":"phase_transition"' .supervisor/logs/*.jsonl | wc -l
```

Re-run at authoring time of this fix (2026-07-29): **843** `token_ledger`
events (across 30 log files) vs **6** `phase_transition` events (across 4
log files) — consistent with the miss-rate finding above; this is a
point-in-time snapshot, not a new constant to cite in place of 785/836. On
2026-07-27 all 5 subtasks of
a job were merged while `state.md` still read `phase: ACQUIRE` / all
`PENDING` — `--continue` would have silently re-executed the whole job. The
fix follows the exact `token_ledger` shape above: replace prompt-instructed
bookkeeping with a single hook-triggered writer, and derive `state.md` from
the log instead of trusting an agent to keep it current.

**What fires it.** A `type: command` entry under the **existing**
`loomwright:worker` `SubagentStop` matcher in `hooks/hooks.json` (stdin
fan-out, same shape as the `token_ledger` chain):

```json
{
  "type": "command",
  "command": "payload=$(cat); printf '%s' \"$payload\" | bash \"${CLAUDE_PLUGIN_ROOT}/scripts/emit-progress-event.sh\" || true"
}
```

Unlike `token_ledger` (chained onto `code-reviewer` / `qa-executor` /
`supervisor-runner`), this event fires **only** on `loomwright:worker`
completion — the Single-Agent Path's one worker and every subtask worker on
the Parallel Path, but not the reviewer, Execute Manager, or Supervisor
itself. `emit-progress-event.sh` reads the same verified `SubagentStop`
payload shape documented above (`last_assistant_message` /
`agent_transcript_path`, no `result_block`) — proven by a committed fixture
at `loomwright/scripts/progress-event-fixtures/`, not by an invented key.

**What it writes.** One additive JSONL line per worker completion, appended
to `.supervisor/logs/{session_id}.jsonl` (the SAME log file `token_ledger`
and `session_end` already write to — one append-only log per session, not a
new file):

```json
{"event":"subtask_complete","type":"subtask_complete","session_id":"supervisor-2026-07-28-one-writer","cc_session_id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","agent_type":"loomwright:worker","agent_id":"…","branch":"feature/one-writer-derived-state","ts":"2026-07-29T05:23:00Z"}
```

| Field | When | Meaning |
|-------|------|---------|
| `session_id` | always (when emitted) | Same two-source join key as `token_ledger`: the plugin session id from `.supervisor/state.md`'s `- session_id:` when `- status:` is `running` (`checkpoint` also accepted, backward-compat only — it is not in the closed status enum and the projector never emits it), else the Claude Code UUID. Log filename key. |
| `cc_session_id` | when SubagentStop carries `session_id` | Claude Code UUID, retained even when `session_id` above resolved to the plugin id |
| `agent_type`, `agent_id` | when present in the payload | Copied as-is |
| `branch` | always when resolvable | The **session** feature branch (see anchoring below) — never a subtask branch, never empty on a successful write |
| `ts` | when `date -u` succeeds | UTC ISO-8601; omitted (not `"unknown"`) on failure |

**Always-exit-0 fail-safe contract.** `emit-progress-event.sh` is modelled
line-for-line in discipline on `emit-token-ledger.sh`: `set -u` with **no**
`set -e`, `trap 'exit 0' EXIT`, and every failure mode absorbs to a silent
no-op — empty stdin, missing `python3`/`jq`, an unresolvable main worktree,
an unwritable log dir, malformed JSON, or a not-a-git-repo cwd all exit 0
with zero side effects. This is what makes the `hooks.json` entry's
trailing `\|\| true` legal per CLAUDE.md §Failure-Mode Invariants — it is
legal **only** because the emitter is fail-SAFE by construction, never
because the hook wrapper masks a real failure.

**Main-worktree anchoring (and why it exists).** Never bare `$PWD`, bare
`git branch --show-current`, or `dirname` of the git common dir — a worker
on the Parallel Path runs inside a **linked git worktree** on a **subtask**
branch (or detached), with no `.supervisor/` directory of its own. A bare
derivation would silently write to the wrong (or a nonexistent) log path,
or project a wrong/empty `- branch:`, which fails the `s1_branch` equality
guard in `hook-dispatch-on-pr-create.sh`'s Source 1 block and kills the
until-mergeable review drain with no error. Both `emit-progress-event.sh` and `build-state.sh`
instead resolve the **main worktree by name** (`git worktree list
--porcelain`'s first entry) plus a `--show-toplevel` cross-check that
aborts (exit 0) on mismatch — verified empirically 2026-07-28 on git 2.50.1
from inside a real linked worktree, where `git branch --show-current`
returned empty and no `.supervisor/` existed. `emit-token-ledger.sh` was
updated to the same anchoring (keeping its `$PWD` fallback only for
byte-identical compatibility with its proven 785-event history); the new
emitter has no such legacy fallback and simply exits 0 when anchoring
fails.

**How `build-state.sh` projects `## Session`.** `emit-progress-event.sh`
invokes `scripts/build-state.sh <session_id> <main_root>` after every
append. The projector reads the append-only log and derives `## Session`
from evidence only — it never guesses:

| Field | Derived from | Absent-evidence behavior |
|---|---|---|
| `session_id` | the id the emitter resolved | file not written |
| `branch` | **live** `git -C main_root branch --show-current` at projection time (a property of the checkout, not stored per-event) | field omitted |
| `status` | **ordering rule** (PR #116 review fix, replacing "any `session_end` present"): the LAST of `{subtask_complete, session_end}` in the log decides. Last event `subtask_complete` ⇒ `running` (even when an EARLIER `session_end` exists — the multi-task `/autonomous` LOOP case, so task 1's `session_end` can't mark task 2 `completed`); last event `session_end` ⇒ its own `status` mapped into `completed \| completed_with_escalation \| failed` (unrecognized/missing status ⇒ `completed`, the closest safe closed-enum reading — not a zero-evidence guess). **Staleness backstop (v15.49.0):** a derived `running` is downgraded to `failed` when the newest **owner-originated** event in the log is older than `LOOMWRIGHT_STALE_RUN_SECONDS` (default 86400) — age is measured over owner lines ONLY (see §"Run ownership"); the backstop skips when ownership or a timestamp cannot be established, and introduces no new status word (`paused` is never emitted). **Pre-first-event window:** with NO log the projector can still emit the staleness verdict alone — `failed`/`LOOP`, never `running` — measured against the run-creation seed's `started_at` (see §"Run ownership"); with no seed it exits as before | `status` is **never** omitted once the file exists — an absent `- status:` trips the `s1_status` presence guard in `hook-dispatch-on-pr-create.sh`'s Source 1 block and fails closed |
| `phase` | same ordering rule: last event `subtask_complete` ⇒ `EXECUTE`; last event `session_end` ⇒ `LOOP` | file not written |
| *(non-derived keys, e.g. `task_id`, `self_heal_resume_count`)* | preserved verbatim from the pre-projection `## Session` block, in original order (PR #116 review fix — this projector owns exactly the four keys above, not the whole block) | n/a — nothing to preserve on a brand-new block |

Both fields always land inside the closed enums in
`skills/state-management/SKILL.md` §"State File Schema". The write is a
**targeted in-place edit of `## Session` only** (temp-file + rename),
preserving `## Decisions Log`, `## Phase Flags`, `## Checkpoint`, and every
other section byte-for-byte. An absent/empty log still means **no `state.md` is
ever CREATED** — start-fresh, strictly better than the pre-change failure mode
(a stale lie left on disk); the one thing it can now do is close out an
ALREADY-EXISTING non-terminal block for the same run, and only as the staleness
verdict (see §"Run ownership"). Self-test: `scripts/test-progress-state.sh`
(fixture-driven; 189 assertions covering idempotency, every fail-safe path,
the worktree-anchoring hazard from inside a real `git worktree add`, the
Parallel-Path case, projector round-trip byte-identity, section
preservation, the AC-5 hook-dispatch positive/negative cases, and the
PR #116 review round's ordering rule, mkdir-lock, permission-preservation,
non-derived-key-preservation, and `reproject-state-on-terminal.sh` cases,
plus the run-ownership, agent-identity, and staleness-backstop cases added
in v15.49.0 and the pre-first-event-window cases added with the run-creation
seed — see §"Run ownership" below). The seed itself has its own suite,
`scripts/test-seed-run-owner.sh`.

**Honest limits of this change (not papered over):**

**1. The operator re-measurement procedure (AC-8 iii).** A live
post-change adherence count is **not producible inside this PR**: the
installed plugin at `~/.claude/plugins/cache/atelier/loomwright/<version>`
is a **copy**, not a symlink (verified — distinct inodes for
`hooks/hooks.json` before vs. after this change), so the edited hook does
not fire until the plugin is reinstalled from this checkout. To measure the
real before/after adherence after merging, an operator runs:

1. Reinstall the plugin from this checkout so the edited `hooks.json` takes
   effect: `/plugin uninstall loomwright` then `/plugin install
   loomwright@atelier` (or the equivalent local-marketplace reinstall for a
   dev checkout).
2. Confirm the new hook is live: `grep -n "emit-progress-event"
   ~/.claude/plugins/cache/atelier/loomwright/*/hooks/hooks.json`
   should show the `type: command` entry from this change.
3. Run at least one `/supervisor` job with ≥1 subtask to completion (the
   Single-Agent Path's single worker is sufficient — it still fires
   `SubagentStop` once).
4. Count `subtask_complete` events written since reinstall: `grep -l
   '"event":"subtask_complete"' .supervisor/logs/*.jsonl | wc -l` (per-file
   presence) or `grep -c '"event":"subtask_complete"'
   .supervisor/logs/*.jsonl` (per-file event count) across the sessions run
   after step 1.
5. Compare against the **785**-vs-**6** pre-change baseline (`token_ledger`
   vs `phase_transition`, this repo's logs as of 2026-07-28): the new
   number should track 1:1 with completed workers, not lag behind them —
   that is the adherence fix landing for real, as opposed to in a PR
   description.

**2. Terminal status now fires mechanically (PR #116 review Finding 1 —
fixed, not merely "less stale").** Before the review round, `build-state.sh`
only ever ran when `emit-progress-event.sh` invoked it, and that emitter
only fires on the `loomwright:worker` `SubagentStop` matcher — so a
Phase 4.5 completion tail that appends `session_end` had nothing to
re-invoke the projector afterward, and `state.md` sat at `running`/`EXECUTE`
for the rest of the run's on-disk life (the "headline claim doesn't fire"
finding). This is now closed by a SECOND `type: command` hook,
`scripts/reproject-state-on-terminal.sh`, registered under the *existing*
`PostToolUse[Bash]` matcher (already firing on every Bash tool call for the
PR-create backstop). It cheaply checks whether `state.md`'s status is
non-terminal and the session log's tail carries a `session_end` event, and
if so invokes `build-state.sh` to re-derive `## Session`. Because
`session_end` itself is appended via a Bash-tool command (a JSONL append),
the very Bash call that writes `session_end` is itself followed by this
hook firing — the terminal flip typically lands within the same tool call
that produced the evidence, not on some later unrelated Bash invocation.
**Residual, now narrower:** if a future code path ever appended
`session_end` via a non-Bash mechanism (it does not today), the flip would
wait for the next Bash tool call in that session rather than firing
immediately — still bounded, still mechanical, just not same-call. Do
**not** close that narrower residual by re-adding a "flip the status"
prompt instruction — that is the exact anti-pattern this whole change
removes; the fix is another mechanical hook site if a non-Bash
`session_end` writer is ever introduced, not a written-instruction
workaround.

**Extension — the join key that matters for this residual.** `session_end`
only over-reports `state.md`'s `- status:` line usefully if it is appended
to the SAME log file `subtask_complete` events already landed in — the
projector only reads one file per invocation (`build-state.sh <session_id>`).
Both writers resolve `{session_id}` for `.supervisor/logs/{session_id}.jsonl`
from the identical source: `## Session`'s seeded/derived `session_id`
(seeded once by Context-Keeper's `initialize`, see `agents/context-keeper.md`
§"Progress state"). Before that seed existed, the FIRST `subtask_complete`
event of a fresh run would have found no `## Session` block yet and fallen
back to the Claude Code SubagentStop UUID (`scripts/emit-progress-event.sh`'s
documented fallback) — a DIFFERENT id than whatever plugin-generated
`session_id` Supervisor separately carries forward to its own `session_end`
append, splitting the two writers across two log files with no terminal
evidence ever landing where `subtask_complete` events accumulated.
`initialize`'s one-time seed (status `running`) closes this for the ordinary
fresh-run case: the first `subtask_complete` event now resolves the same
seeded plugin `session_id` Supervisor uses for `session_end`, so both writers
target one file. The join is NOT independently guaranteed by anything that
validates it at write time — it holds because both call sites are documented
to read/reuse the same `## Session.session_id`, not because either script
cross-checks the other.

**3. Residual — the base-mismatch cleanup path is invisible to every
automated read-side check.** When a subtask worktree's base branch no
longer matches the expected merge base, the completion tail's
base-mismatch cleanup path returns **before** reaching the completion tail
that would emit `session_end` — so that path's `failed` outcome is never
derived into `state.md` at all (not even as a stale `running`; there is
simply no evidence for the projector to read). **No automated read-side
check catches this.** `scripts/reconcile-resume-state.sh` reads only the
`## Session` block's `branch` field and the `## Subtasks` table's `Status`
column — it never reads `.supervisor/jobs/failed/` (where the job file
actually lands on this path) and never reads `## Decisions Log` (where the
`record_decision` call on this path — retained, see the delete-set
scope deviations — is the only durable record of what happened). An
operator investigating a job that silently stopped progressing must check
`.supervisor/jobs/failed/` and the Decisions Log directly; `state.md` and
`reconcile-resume-state.sh` alone will not surface this path.

**4. Residual — a `/supervisor --continue` resume straight into FINALIZE or
Phase 4.5 leaves the until-mergeable review drain silently undispatched.**
The correctness argument for deleting the Phase 1 ACQUIRE direct-write ("a
worker `SubagentStop` fires before `gh pr create`") holds for a fresh run,
where at least one `loomwright:worker` completes in-session before PR
creation and derives `state.md` for that session. It does NOT hold for a
resume that lands directly in FINALIZE or Phase 4.5 after every subtask
already completed in a **prior** session: no `loomwright:worker` fires in
the resumed session, so nothing re-derives `state.md` for it. If the
carried-over `state.md` is absent, or its `- status:` word is one of the
terminal set (`completed`/`completed_with_escalation`/`failed`), then
`hook-dispatch-on-pr-create.sh`'s Source 1 does not authorize (its gate
requires a present, non-terminal status word AND a matching branch — see
that script's header) and control falls through to Source 2 (the
`/autonomous` state.json fallback). Outside `/autonomous`, no state.json
exists either, so authorization fails closed and the backstop silently does
not dispatch the drain for that `gh pr create` call — Supervisor's own
step-5.5 in-context dispatch remains the only path on this shape, and if it
is skipped the drain never fires at all this run. **Consequence, precisely
stated:** a silently-undispatched review drain, not data loss or a
corrupted merge — the PR is still opened normally. **Fallbacks that still
apply:** running under `/autonomous`, Source 2's state.json (when its
`.current_branch`/`.current_status`/`.current_brief_path` conditions are
met) still authorizes; and an operator can always run `/review-pr
--until-mergeable <url>` inline to drain the same PR by hand. Do **not**
close this residual by re-adding a `state.md` write to the resumed session's
ACQUIRE/FINALIZE path — that reintroduces the exact prompt-instructed
bookkeeping this change removes; the gap is in `hook-dispatch-on-pr-create.sh`'s
authorization sources, not in the derivation mechanism, and is deliberately
left open here as a known, accepted limitation of this change's scope.

**5. Honest limits — `state.md` went from one serialized writer to two
(PR #116 review Finding 2).** Before this fix, `build-state.sh`'s
read-modify-write (whole-file read → awk → temp file → rename) was the
file's only writer of any kind touching `## Session`, and Context-Keeper's
own read-modify-write (via the Edit tool) against `## Decisions Log` /
`## Worker Results` / `## Error Log` / `## Phase Flags` could interleave
with it — reproduced deterministically 6/6: an interleaved Context-Keeper
write-back clobbers the freshly projected `## Session` block (the
*projection* is lost, not the decision — note the direction, it is easy to
misstate). `build-state.sh` now takes a portable `mkdir`-based lock
(`.supervisor/.state.lock`; `flock(1)` is not on stock macOS) around its
read-modify-write. **What the lock guarantees:** no two `build-state.sh`
invocations can be inside the read-modify-write at the same time, so a
projection can no longer be clobbered mid-write by a concurrent projection.
**What it does NOT guarantee:** it does nothing to serialize against
Context-Keeper's Edit-tool write-back, which does not take this lock (Edit
is a harness-level operation, not a shell process this script can
coordinate with) — the two writers are still, in principle, two independent
serialized-with-themselves writers of the same file, not one arbiter over
both. **Why skipping under contention is safe:** the log is append-only, so
a projection that loses the lock race (or a stale lock older than 60s that
gets stolen — see the script's `acquire_lock`/`lock_age_seconds` comments
for the exact staleness policy) simply does not run; the very next
`subtask_complete`/`session_end` event re-derives the identical `## Session`
content from the same evidence, so a skipped projection is a delay, never a
lost fact. This narrows Finding 2's clobber window without closing the
class of problem it identified — a full fix would require Context-Keeper's
Edit-tool writes to also participate in a shared lock, which is out of this
change's scope (Context-Keeper is a separate agent process, not a script
this repo's shell-level lock can reach).

**6. Residual — the ACQUIRE→first-worker-completion window has zero
`state.md` evidence (PR #116 follow-up review, Finding 1).** Deleting the
old Phase 1 ACQUIRE direct-write means nothing creates `state.md` until the
first `loomwright:worker` `SubagentStop` fires in Phase 3 EXECUTE — the
span covering Phase 1.5 PRE-FLIGHT SYNC and all of Phase 2 PLAN has no
on-disk trace that a session is in flight. A crash in that window leaves
`/supervisor --continue` finding no state file at all, which correctly
routes to "start fresh" (`skills/state-management/SKILL.md` Resume
Priority item 3) — that path is unchanged and was already correct. What
was NOT survivable is what "start fresh" then does: it re-enters Phase 1
ACQUIRE and re-selects the same `{task_id}-{short-desc}`, whose branch the
crashed run already created. **This is now handled at the point that
actually breaks — the ACQUIRE branch-creation step itself is idempotent**
(see Phase 1 ACQUIRE step 4 in `agents/supervisor.md`): it checks for an
existing same-named branch first, reuses it when its tip is byte-identical
to the current `$BASE_BRANCH` tip (provably zero commits beyond base — the
exact shape a crash in this window leaves), and otherwise stops with a
diagnostic rather than guessing or deleting anything. **What this does and
does NOT affect:** it closes the hard-error crash (`fatal: a branch named
'...' already exists`) for the specific case this window creates. It does
**not** put any evidence back on disk for the window itself — Phase 1.5 and
Phase 2 still produce nothing durable if the run is interrupted mid-phase
and NOT re-run (e.g., the operator kills the session and never calls
`--continue`); there is simply nothing to reconcile because nothing was
acquired durably yet. That is an accepted gap, not a silent one: the only
thing a session commits to disk in this window is the branch itself
(inspectable via plain `git branch`/`git log`, independent of `state.md`),
so an operator auditing "was a session here" during this window reads git,
not `state.md`. Do **not** close this residual by re-adding a `state.md`
write inside ACQUIRE or PLAN — that is the exact prompt-instructed
bookkeeping this whole change deletes; the branch-guard above is the
narrower, mechanical fix for the one failure mode this window actually
produces (a hard-erroring resume), not a reintroduction of per-phase
checkpointing.

**7. A run resumed under a DIFFERENT Claude Code session id will no longer
join its original log.** This is the accepted cost of the run-ownership gate
below, stated plainly rather than hedged: ownership is keyed on the
`cc_session_id` recorded for the run — the run-creation seed for the strict
consumers, the log's first line for the emitters (§"Run ownership") — and the
**seed does not change this conclusion**, because it is written once at
creation and names the ORIGINAL session; a resumed session is foreign to both
sources alike. The one case it does decide is a run that stranded before any
log line AND before any seed existed: the resuming session's first edit of
`state.md` seeds it as the owner, which is correct — that session is the one
actually running it now. So if the same logical run is
resumed in a new Claude Code session (a `--resume`/`--continue` that the
harness gives a fresh UUID, or a crash-and-restart), that session is a
foreign session by this rule. Its events land in `<new-cc-uuid>.jsonl`, the
original run's log stops receiving them, and `build-state.sh` will project
the original run's status from the evidence that log already holds — which,
once the staleness threshold elapses, reads `failed`. The resumed work is
not lost and nothing blocks: the events are all on disk, just split across
two files, and `/insights` and the postmortem readers aggregate across log
files. The trade is deliberate — a split log for a genuinely resumed run is
strictly cheaper than the alternative it replaces, which was one finished
run silently capturing 140 later sessions' events. Do **not** close this by
widening ownership to "any session whose id appears anywhere in the log":
that is the measure-over-all-lines mistake that made the original loop
circular.

**8. A close-out whose SessionEnd payload is empty or unparseable does not
fire, and the run stays stranded.** `close-stranded-run.sh` identifies itself
from the payload's `session_id`. When stdin arrives empty or unparseable
there is no `cc_session_id` to compare, so a log that has a KNOWN owner —
the normal state of any real run past its first worker completion, and
therefore exactly the 140-session incident this work exists to close — takes
the non-owner branch and the script writes nothing. It exits 0 silently, with
no error and no signal.

This is deliberate and is **not** closed by writing anyway. The script cannot
distinguish "I am the owner but my payload was lost" from "a different,
still-LIVE session owns this run", and writing on that ambiguity would stamp
`status: failed` onto a live run — the same false-positive corruption the
`clear` guard exists to prevent, and strictly worse than the condition it
would be trying to fix. The asymmetry decides it: a stranded run is
recoverable, a wrongly-closed live run is not.

**Recovery path:** `LOOMWRIGHT_STALE_RUN_SECONDS` (default 86400), the
staleness backstop in `build-state.sh` described above — a derived `running`
whose newest owner-originated event is older than the threshold is downgraded
to `failed` without needing any `session_end` to land. So the run does reach a
terminal status; it reaches it on the backstop's timescale rather than
immediately. Pinned by case 4j in `scripts/test-close-stranded-run.sh` (empty
stdin + known owner ⇒ nothing written, exit 0, `state.md` still non-terminal),
and by case 4d for the same payload against an UNKNOWN owner — see limit 9,
which is why that case no longer adopts either.

**9. Ownership is now recorded AT RUN CREATION, so the pre-first-event window
is no longer a guess.** The rule this entry used to describe is intact and
unchanged: an unknown log owner is adoptable by the `SessionEnd` close-out
**only** by a session whose payload `session_id` equals the run id `state.md`
names. What changed is how often "unknown" happens.

The problem was that a run's owner became knowable only when the FIRST line of
`.supervisor/logs/<run_id>.jsonl` was written, and that line does not exist
until the first worker `SubagentStop`. `.supervisor/state.md` is **repo-global,
not session-scoped** — every session anchored to the same main worktree reads
the same `- session_id:` and `- status: running` — so across the whole
`initialize` → ACQUIRE → PRE-FLIGHT SYNC → PLAN span (minutes, not an instant)
nothing could tell a **stranded** run from a **live** one. Both available
guesses were wrong: guessing *stranded* let any ending session stamp
`status: failed` onto a LIVE run and leave a fabricated hard-signal
`session_end` that `build-insights.sh` consumes and nothing retracts; guessing
*live* left a stranded run non-terminal forever. And for **slug-keyed** runs the
gap was GUARANTEED rather than incidental — `/autonomous` and `/automate` mint a
synthetic `auto-2026-09-05-050440` id, while a `SessionEnd` payload always
carries the real Claude Code uuid, so the self-identification test above was
structurally unsatisfiable for them and the unknown-owner path was *unreachable*
rather than occasionally missed.

**The fix is a SCRIPT-OWNED seed, not a prompt instruction.** `seed-run-owner.sh`
runs on `PostToolUse[Write|Edit]` and writes
`.supervisor/logs/<run_id>.owner` — `cc_session_id`, `session_id`, `started_at` —
the moment `.supervisor/state.md` is created. See §"Run ownership" for the
mechanism, the write-once guarantee, and why the seed takes precedence over the
log's first line. Two properties it depends on were **measured against a live
headless CLI session** (see §"Run ownership" for the exact invocation) rather
than assumed: `PostToolUse[Write]` does fire for a
SUBAGENT's Write (Context-Keeper has no Bash — see its `disallowedTools` — so
the Write tool is the only way it can create the file), and the payload
`session_id` for that firing is **byte-identical** to the `SessionEnd` payload's
`session_id` for the same CLI session, which is exactly the value the close-out
compares against. The seed is deliberately NOT written by the agent that creates
`state.md`: that would put a fact a hook must rely on into an agent prompt, and
this repo has measured what that costs (560 hook-written `token_ledger` events
vs 6 agent-written `phase_transition` events — `docs/PITFALLS.md`). An agent
also cannot know its own Claude Code session id; the hook payload is the only
place it appears.

Both consumers named in the old residual now work in that window. The close-out
takes its ordinary known-owner path (pinned by cases 5a/5b/5c/5d/5e in
`scripts/test-close-stranded-run.sh`), and the staleness backstop — which used
to return early on `build-state.sh`'s log-exists guard, since in this window the
log does not exist at all — now reaches it, because the seed supplies both the
owner and a `started_at` that counts as owner-originated evidence (cases 38a-38i
and 39a-39c in `scripts/test-progress-state.sh`). No new `status` or `phase`
word is introduced: the log-less branch can emit only `failed`/`LOOP`, the same
pair a `session_end` produces, and it can write nothing else — not even
`running` — so it can never overwrite a live run's phase.

**What actually remains, stated so it is not mistaken for closed:**

| Residual | Why it remains | Recovery |
|---|---|---|
| A run with **no seed** — every run whose `state.md` predates this release, and any run whose state file was not created through the watched Write/Edit tool path | The seed is written forward-only; nothing retro-fits an owner onto a run already in flight | The old rule verbatim: the run's OWN session can still close it out (case 4m), no other session can (4n/4o), and it otherwise stays `running` |
| The seed stops being written if the harness ever stops firing `PostToolUse` for subagent tool calls | The plugin cannot assert a harness behaviour continuously — it was verified on 2026-09-05, not pinned | Fail-SAFE and INVISIBLE: with no seed, behaviour reverts exactly to the row above. Nothing breaks; the window simply reopens |
| A killed terminal's run stays `running` for up to `LOOMWRIGHT_STALE_RUN_SECONDS` (default 24h) **and** until the next Bash tool call in that checkout | `SessionEnd` never fires for a killed terminal, so only the staleness backstop can reach it, and only a hook can invoke the projector | Bounded rather than permanent, which is the change — previously it was forever |
| An owning session whose `SessionEnd` payload arrives empty or unparseable still cannot prove ownership | Unchanged from limit 8; a seeded run has a KNOWN owner, so it takes the non-owner branch | Staleness backstop, as before (case 4j) |
| **The two emitters are NOT changed and still resolve ownership from the log's first line alone**, adopting on unknown | Non-negotiable: their protected property is the fresh-run bootstrap, and this change deliberately did not touch it | See the follow-up below |

**One follow-up is named rather than bundled.** Because the emitters read only
the log's first line, their ownership gate is **inert for `/autonomous` runs**:
those logs open with an `autonomous_session_start` line that carries no
`cc_session_id`, so the owner reads unknown and every session adopts. A foreign
session's worker completion can therefore still fan into a slug-keyed run's log
during this window. Neither the close-out nor the projector is fooled by it —
both prefer the seed, and case 5d pins that a foreign first-line appender does
not thereby own the run — but the log itself still grows. Closing it is the same
three-line sidecar fallback added to `loom_log_owner` in
`emit-progress-event.sh` / `emit-token-ledger.sh`, and it would STRENGTHEN the
gate rather than weaken adopt-on-unknown (an unknown owner would still adopt;
it would simply be unknown less often). It is left out of this change because
those two emitters are covered by an explicit non-negotiable and their suites
are the load-bearing ones, so it deserves its own change and its own controls —
not a rider on this one.

### Run ownership

**The problem this exists to stop.** Both emitters used to join a run's log
whenever `.supervisor/state.md` read `status: running`/`checkpoint`. A run
that ended WITHOUT emitting `session_end` left that status on disk forever,
so every later session's SubagentStop appended to that one run's log —
measured on this repo: **14,416 lines, 3.9 MB, 140 distinct
`cc_session_id`s** in a single file. `build-state.sh` then re-derived
`running` from the newest FOREIGN `subtask_complete` in that same log, so
the stale status caused the fan-in and the fan-in re-asserted the stale
status. The Floor rendered ordinary interactive chat turns as a live
Supervisor run.

**The owner is recorded at RUN CREATION — `.supervisor/logs/<run_id>.owner`.**
`seed-run-owner.sh` fires on `PostToolUse[Write|Edit]`, recognises a write to
the main worktree's `.supervisor/state.md`, and records three `key=value` lines:

```
cc_session_id=<the Claude Code session that created this run>
session_id=<the run id state.md names>
started_at=<UTC ISO-8601 — the projector's staleness anchor>
```

Why a hook and not the agent that creates the file: the fact has to be readable
BY a hook, an agent cannot know its own Claude Code session id, and
prompt-instructed bookkeeping is measurably unreliable here (560 hook-written
events vs 6 agent-written — `docs/PITFALLS.md`). Why this trigger: Context-Keeper
has no Bash (`disallowedTools`), so the Write tool is the only way `initialize`
can create `state.md`, which makes the session that wrote it the run's owner **by
definition** — there is no "first observer claims it" race for an unrelated
session to win. A seed driven by the already-firing `PostToolUse[Bash]` matcher
was rejected for exactly that reason. Both harness properties it rests on were
measured on a live `claude -p` session, not assumed: `PostToolUse[Write]` fires
for a SUBAGENT's Write, and its `session_id` is byte-identical to the
`SessionEnd` payload's for the same CLI session.

Creation is atomic (`set -C` → `O_EXCL`), so it is **write-once**: a run's owner
cannot change under it, and a second firing — Context-Keeper edits `state.md`
many times per run — is a no-op. The seed is never written for a terminal run,
and never for a run whose log already records an owner (so a
`/supervisor --continue` resume cannot contradict the original owner).

It is a **sidecar rather than a JSONL line** because the log may already have a
first line by the time `state.md` exists (`/autonomous` appends
`autonomous_session_start` at INIT), because the log is append-only, and because
a new event type would grow a case in `build-insights.sh`,
`build-loop-evidence.sh`, `build-floor.sh` and every other consumer.
`.supervisor/logs/` already holds non-JSONL files and every consumer globs
`*.jsonl` explicitly, so `.owner` is inert to all of them.

**The fallback owner rule.** The log's FIRST line records who opened it: the
owner of `.supervisor/logs/<PLUGIN_SESSION_ID>.jsonl` is the `cc_session_id` on
that first line. This is the only source that existed before the seed, and it
remains the answer for any run with no seed. Only that session may join the log.
On an owner mismatch, both
`emit-token-ledger.sh` and `emit-progress-event.sh` blank
`PLUGIN_SESSION_ID`, so the firing falls back to the Claude Code UUID and
lands in its own `<cc_uuid>.jsonl` — the owned log's line count is
unchanged. The gate is defined AFTER the status block in each emitter, not
before it, so the CI-pinned `running|checkpoint)` case line does not drift.

**Precedence: the seed wins over the log's first line.** Where the two
disagree, the disagreement IS the foreign-append case — while the owner is
unknown the emitters' adopt-on-unknown rule (below) explicitly permits a
FOREIGN session's event to land as the log's first line, whereas the seed was
written at run creation by the session that created the run. Only the two
STRICT consumers apply this precedence — the `SessionEnd` close-out and
`build-state.sh` — because they are the ones a wrong owner can make write a
false verdict. `seed-run-owner.sh` never seeds a run whose log already records
an owner, so the two can only ever diverge that way round.

**Unknown owner means ADOPT (do not invert this).** An absent, empty, or
unreadable log, an unparseable first line, or a first line carrying no
`cc_session_id` all yield an empty owner, and an empty owner adopts the
plugin session id exactly as before. A broken or missing `jq` (probed
functionally, never by `command -v` alone) also yields an empty owner, i.e.
adopt. This direction is load-bearing: refusing on unknown owner would
regress the very first worker completion of every fresh run, because the log
does not exist yet at that point and there is nothing to be the owner of.

**Session close-out (`SessionEnd` → `close-stranded-run.sh`).** The gate
stops the fan-in; it does not by itself make a stranded run terminal. The
plugin's `SessionEnd` hook runs `scripts/close-stranded-run.sh`, which
appends exactly ONE `session_end` record carrying `status: failed` and
`reason: session_ended_without_completion` — with BOTH the canonical `event`
key and the legacy `type` key, the contract `build-insights.sh` filters on
(see `docs/RESULT_SCHEMAS.md` §"`session_end` JSONL hard-signal fields") —
then re-projects via `build-state.sh`. It writes nothing when `state.md` is
already terminal, when there is no `state.md`, or when this session is not
the run's owner — including the ownership-unprovable case in §"Honest limits"
entry 8, where the payload arrives empty or unparseable against a run that
has a known owner. **A seeded run has a known owner from creation**, so it
reaches this ordinary path during the pre-first-event window instead of the
unknown-owner rule below; that is what makes a stranded `/autonomous` or
`/automate` run closable at all (§"Honest limits" entry 9).

**Ownership for the close-out is stricter than for the emitters**, and
deliberately so:

| Log owner | Emitters (`emit-*.sh`) | Close-out (`close-stranded-run.sh`) |
|---|---|---|
| recorded, matches payload | join the run's log | close the run out |
| recorded, differs | divert to `<cc_uuid>.jsonl` | write nothing |
| **not recorded** | **ADOPT** (fresh-run bootstrap) | **adopt only if the payload `session_id` IS the run id** |

**The two columns also read DIFFERENT sources, and that asymmetry is
deliberate.** "Log owner" above means, for the close-out, the run-creation seed
first and the log's first line second; for the emitters it means the log's first
line ONLY. The emitters were left unchanged because their protected property is
the fresh-run bootstrap and the worst they can do is mis-file an event, whereas
the close-out can mark a LIVE run dead and `state.md` is repo-global so any
session can reach it. `build-state.sh` reads the same two sources as the
close-out, in the same order, for the same reason — its staleness backstop can
also turn a run `failed`. The consequence of leaving the emitters on one source
(their gate is inert for `/autonomous` runs, whose first log line carries no
`cc_session_id`) is named as follow-up, with the change that would close it, in
§"Honest limits" entry 9.

Full rationale, the rejected stricter variant, and the residual: §"Honest
limits" entry 9.

**`SessionEnd` is scoped to real termination — `/clear` must never close a
run.** `SessionEnd` fires for `clear` as well as for genuine termination, and
`cc_session_id` is STABLE across `/clear` within one CLI process. A user
running `/clear` mid-run therefore presents a NON-TERMINAL `state.md` with a
MATCHING owner: every condition above is satisfied, and an unscoped hook would
write `status: failed` over a run that is still executing — corrupting state
in the OPPOSITE direction from the fan-in this work exists to close. Two
layers stop it: `hooks.json` registers the hook under
`"matcher": "logout|prompt_input_exit|other"`, and the script itself exits 0
writing nothing when the payload's `.reason` is exactly `clear`. The in-script
layer is a **DENY-LIST, never an allow-list**: an absent, empty, or
unparseable reason PROCEEDS, because the no-`reason` payload is the main path
(the self-tests emit exactly that), and because a stranded run is recoverable
via the staleness backstop while a wrongly-closed live run is not. Pinned by
cases 4k (`clear` ⇒ no-op) and 4l (`logout` ⇒ still closes out) in
`scripts/test-close-stranded-run.sh`; 4l is the control that stops 4k from
passing under a blanket suppression of every reason-bearing payload.

`failed` is the only status it emits; `paused` is never
used, because `paused` is classified LIVE by
`hook-dispatch-on-pr-create.sh` and DEAD by both emitters, so emitting it
would put two consumers in disagreement about the same file. Like the
emitters, it is fail-SAFE by construction and always exits 0 — it can never
block session teardown.

**`LOOMWRIGHT_STALE_RUN_SECONDS` (default 86400).** A close-out only fires
if the session that owned the run actually reaches `SessionEnd`; a killed
terminal or a crashed host never does. `build-state.sh` therefore carries a
backstop: when the derived status would be `running` but the newest
**owner-originated** event in the log is older than
`LOOMWRIGHT_STALE_RUN_SECONDS`, it emits `failed` instead. **Owner-only
measurement is the entire point** — measuring age over ALL lines is exactly
what made the original loop circular, because foreign sessions kept
appending fresh events to a finished run's log and so the log always looked
fresh. The backstop SKIPS (never guesses a run dead) when no owner can be
resolved, when no owner timestamp parses, or when the override is not a
positive integer, in which case the default applies.

**It reaches the pre-first-event window too, via the seed.** When there is no
log at all, `build-state.sh` used to return on its log-exists guard before any
derivation ran, so a run stranded between `initialize` and its first worker
completion could never be closed by anything. It now takes the seed's owner and
treats `started_at` as owner-originated evidence — the last thing we know the
owner did, when the owner has emitted no events of its own — and the later of
{newest owner line, `started_at`} is what the age is measured against, so a log
that DOES carry owner lines stays authoritative. That branch is narrow by
construction: with no log it may write ONLY the staleness verdict
`failed`/`LOOP`, never `running`, so it cannot overwrite a live run's phase, and
it never brings a `state.md` into existence (an absent state file still means
start-fresh). `reproject-state-on-terminal.sh` gains the matching cheap trigger
— when the log is absent it checks the seed's mtime instead of the log's tail —
because nothing else can invoke the projector in that window, and a KILLED
terminal never reaches `SessionEnd` for the close-out to fire either. That mtime
check is a COST gate only; the projector re-decides from `started_at` and owns
the verdict.

The backstop still
introduces no new status word: it can only turn a derived `running` into
`failed`, both already members of the closed enum in
`skills/state-management/SKILL.md` §"State File Schema". `paused` is never
emitted by this projector.

**Agent identity on emitted lines (`agent_type`).** The real `SubagentStop`
payload frequently carries no `agent_type` at all. Both emitters resolve it the
**same way** — from the payload only — and neither ever invents it:

| Emitter | Resolution order |
|---|---|
| `emit-progress-event.sh` | payload `agent_type` → key **omitted** (no env fallback) |
| `emit-token-ledger.sh` | payload `agent_type` → key **omitted** (no env fallback) |

In both cases "omitted" means the key is absent entirely — never an empty
string, never `null`.

**A matcher does not identify the agent — measured, not assumed.** An earlier
revision of this change injected the matcher's own name into
`emit-progress-event.sh` through a `LOOMWRIGHT_AGENT_TYPE` env var set by the
`loomwright:worker` hook entry, on the claim that a single matcher "provably
discriminates". **That claim is false and the mechanism was removed.** Grouping
untyped events by `agent_id` on the live log yields a fixed **2 `token_ledger` :
1 `subtask_complete`** in every bucket — (2,1)×125, (18,9)×107, (24,12)×63,
(22,11)×61, (4,2)×45, (26,13)×37. The single `loomwright:worker` block therefore
runs on the **same untyped payloads** as the three ledger blocks. Registering an
emitter under one matcher prevents DUPLICATION; it proves nothing about
DISCRIMINATION. Injecting `loomwright:worker` would have stamped that identity
onto thousands of completions that are not workers — and the injected literal
was single-prefix, while the payload vocabulary is doubled-prefix
(`loomwright:loomwright:worker`), so it would not have matched even on a real
worker.

`emit-token-ledger.sh` has had **no** env fallback for the same reason: it is
registered under THREE `SubagentStop` matchers that only discriminate when the
payload already carries an `agent_type` (see the duplicate guard below: 94/94
typed firings emitted 1 line, 4,376/4,376 untyped emitted 2, so more than one
block runs for an untyped payload). Adopting the identity of whichever matcher
happened to run would be a **guess in exactly the population where we have no
identity**, and it would also defeat the byte-identity dedupe guard — two lines
differing only in a fabricated `agent_type` can never compare equal. The
standing rule is: **`agent_type` is never invented.**

**Accepted limit, not a gap.** The consequence is that **most Floor lanes will
still read `identity unknown`**, because the hook layer genuinely cannot tell
which agent fired: the payload is the only trustworthy source and it usually
carries nothing. That is an honest limit of the current hook surface. Closing it
requires a payload that actually carries `agent_type` — not a matcher-derived
substitute, which would only replace "unknown" with "wrong".

**Adjacent-duplicate guard (confirmed, not assumed).**
`emit-token-ledger.sh` is registered under three `SubagentStop` matchers
(`loomwright:code-reviewer`, `loomwright:qa-executor`,
`loomwright:supervisor-runner`). They are **not** mutually exclusive in
practice: they only discriminate when the payload actually carries an
`agent_type`. Measured on the live log: **94/94** typed firings emitted
exactly 1 line, and **4,376/4,376** untyped firings emitted exactly 2 — the
duplication is perfectly correlated with the absence of `agent_type`, and
typed agents were never duplicated.

**Open question — why 2 and not 3.** Three blocks are registered but only two
lines were measured per untyped firing, so exactly one block's emitter
produces nothing. What is established from the repo: an emitter handed empty
stdin writes no line and exits 0 (probed directly); both
`validate-qa-result.py` and `validate-supervisor-result.py` read stdin to EOF
via `result_block_parser.extract_payload()`, and each sits in the same matcher
block AHEAD of that block's ledger command, whereas the `code-reviewer`
block's preceding hook is `type: prompt` (not a stdin-consuming subprocess);
and all three registrations landed in a single commit, so "the third block was
added after the measurement" is ruled out. **One datum refutes the shared-stdin
explanation:** the `loomwright:worker` block has the SAME shape — a
stdin-reading Python validator (`validate-worker-result.py`) at entry 0 and an
emitter at entry 1 — and its emitter demonstrably DOES write (the
`subtask_complete` lines counted in the ratio above). So a preceding
stdin-consuming validator does not silence the emitter behind it, which sharpens
the prediction to **3** rather than explaining 2. What is NOT established: a
stdin-consumed explanation predicts **1** surviving line if the hook runner
shares one stdin stream across the entries of a block, and **3** if it hands
each command its own copy — neither yields 2, and the datum above argues
against the sharing variant. Deciding between them requires
observing the harness's stdin delivery semantics, which this repo does not
pin. Recorded as unresolved rather than guessed; the guard below is correct
either way, since it keys on byte-identity and not on a duplicate count.

The guard is minimal and consecutive-only: skip the append when the line is
byte-identical to the log's CURRENT last line. Duplicate blocks fire
back-to-back within one firing, so they are always adjacent. Byte-identity
spans `ts`, `agent_id` and the transcript byte count together. That is
**vanishingly unlikely to collide, not impossible**: `ts` is only
second-granularity, `agent_id` is OMITTED for exactly the untyped population
this guard targets, and parallel worker completion is a designed feature — so
a collision requires two distinct completions in the same second, with an
identical transcript byte count, and no `agent_id` on either. The failure
direction is benign and one-way: the loser is one **advisory** ledger line,
silently dropped. No state, decision, or gate reads it. Reading only the last
line keeps this O(1) on a large log, and every failure absorbs to the normal
append path.

### Script-location convention

- `loomwright/scripts/` — **plugin-runtime** scripts shipped
  with the plugin and invoked at agent runtime. Telemetry's wrapper, core,
  test harness, and fixtures all live here. (This is the source-tree
  layout. Hooks and slash commands MUST reference these scripts via
  `${CLAUDE_PLUGIN_ROOT}/scripts/...` — that env var is set by Claude
  Code for plugin-distributed hooks/commands and resolves to the plugin
  install dir on both dev checkouts and marketplace installs. Hard-coded
  `loomwright/...` paths under `${CLAUDE_PROJECT_DIR}` only
  resolve for the plugin maintainer working from this repo's checkout.)
- Repo-root `scripts/` — **release/CI tooling** only (e.g.
  `validate-version.sh`, `check-command-sync.sh`). Do NOT add runtime
  scripts at repo root; consistency audits will flag the drift.

---

## Core exit codes (authoritative)

The core is the only script that may exit non-zero. The wrapper logs the
core's exit code and always returns 0 to the hook. Tests and `/telemetry status`
read these codes to decide what happened.

| Code | Name                  | Meaning                                                                                  |
|------|-----------------------|------------------------------------------------------------------------------------------|
| 0    | `sent`                | Issue successfully created via `gh issue create`. One line appended to `telemetry-sent.log`. |
| 1    | `generic_error`       | Unexpected failure (e.g. `gh` not authed, network error, malformed JSON from `gh`). Logged with redacted stderr. |
| 2    | `privacy_blocked`     | Privacy whitelist matched the prospective issue body or stderr; nothing was sent. Logged with the matched pattern's name only — never the matched content. |
| 3    | `no_consent`          | `.supervisor/telemetry-consent.json` is missing, set to `prompt`, or set to `no`. Wrapper rate-limits the user-facing notice to once per session. |
| 4    | `no_repo_configured`  | Neither `LOOMWRIGHT_TELEMETRY_REPO` nor consent-file `telemetry_repo` is set. Wrapper logs `telemetry_repo_unset` once per session. |
| 5    | `filter_skipped`      | Interest filter, schema mismatch (`unknown_payload_skipped`), or dedup window suppressed the send. Not an error. |

The wrapper's behaviour is invariant of the core exit code: log the code,
log the redacted stderr, exit 0.

---

## Scoring rubric (deterministic, per-result-block)

The three result block schemas (`SUPERVISOR_RESULT`, `CODE_REVIEW_RESULT`,
`QA_RESULT`) use different status enums, different counters, and different
notions of "success". A single unified mapping cannot disambiguate them, so
the rubric is expressed as **three separate tables**. The score function
selects exactly one table per call based on which result block was found.

**Determinism rule:** Same input -> same output. The score function does
not call `date`, does not read random sources, and does not depend on
filesystem ordering. Subtask #2b implements this contract verbatim.

**Bucket ranges (used by the `score:{low|medium|high}` label):**

| Bucket   | Range          |
|----------|----------------|
| `low`    | score `< 4`    |
| `medium` | `4 <= score < 8` (i.e. `4..7` inclusive) |
| `high`   | `score >= 8`   |

Lower bound is inclusive; the upper bound flips to the next bucket. (Per
spec §2 — "low < 4, medium 4-7, high 8+".)

After all adjustments, the score is **clamped to `[0, 10]`** with a floor
of `0` and ceiling of `10`. Negative deductions never push below 0.

---

### Rubric A — `SUPERVISOR_RESULT`

| Condition                                                                          | Base score |
|------------------------------------------------------------------------------------|------------|
| `status == "completed"` AND `heal_decision == "PASS"` AND `heal_remaining_issues == 0` | **9** |
| `status == "completed"` AND `heal_decision == "PASS"` AND `heal_remaining_issues > 0`  | **7** |
| `status == "completed_with_escalation"`                                            | **5** |
| `status == "checkpoint"`                                                           | **4** |
| `status == "failed"`                                                               | **2** |
| Anything else (unrecognised status enum within `SUPERVISOR_RESULT`)                | **3** (defensive default; logged as `score_default_used`) |

**Adjustments (applied after base score is selected):**

| Signal                                          | Delta            |
|-------------------------------------------------|------------------|
| Each item in `subtasks_failed`                  | `-0.5`           |
| `heal_remaining_issues > 0` (AND not already deducted by base) | `-0.25 * heal_remaining_issues` (max `-1.0`) |

Floor at `0`, ceiling at `10`. Round-half-up to one decimal place.

**Worked example.** `status: "completed"`, `heal_decision: "PASS"`,
`heal_remaining_issues: 0`, `subtasks_failed: ["BD-15a"]` -> base `9`
minus `0.5` = **`8.5`**. Bucket: `high`.

---

### Rubric B — `CODE_REVIEW_RESULT`

The score reflects severity of **new** issues only. `pre_existing` and
`nit` issues do not affect the score.

| Condition                                                                  | Base score |
|----------------------------------------------------------------------------|------------|
| `decision == "PASS"` AND no `new` issues at BLOCKING or HIGH severity       | **9** |
| `decision == "PASS"` AND only `new` issues at MEDIUM or LOW severity        | **7** |
| `decision == "NEEDS_HUMAN"`                                                | **4** |
| `decision == "FAIL"`                                                       | **2** |
| Anything else                                                              | **3** (defensive default) |

**Adjustments:**

| Signal                                       | Delta   |
|----------------------------------------------|---------|
| Each `new` BLOCKING issue                    | `-1.0`  |
| Each `new` HIGH issue                        | `-0.5`  |
| Each `drift` issue (any `drift_kind`)        | `-0.25` |

Floor at `0`, ceiling at `10`.

**Worked example.** `decision: "PASS"`, two `new` MEDIUM issues, zero
BLOCKING/HIGH/drift -> base `7`, no deltas -> **`7`**. Bucket: `medium`.

---

### Rubric C — `QA_RESULT`

The score is anchored to the test pass ratio, then adjusted for coverage.
If `tests_generated == 0`, the run is treated as `filter_skipped` (exit 5)
upstream and never scored.

Let `r = tests_passed / tests_generated`.

| Condition          | Base score |
|--------------------|------------|
| `r == 1.0`         | **9** |
| `0.9 <= r < 1.0`   | **7** |
| `0.7 <= r < 0.9`   | **5** |
| `r < 0.7`          | **3** |

**Adjustments:**

| Signal                              | Delta   |
|-------------------------------------|---------|
| `coverage_estimate < 0.5`           | `-1.0`  |
| `self_check_gates_passed < 5` (out of 5) | `-0.5 * (5 - passed)` |

Floor at `0`, ceiling at `10`.

**Worked example.** `tests_passed: 9`, `tests_generated: 10` -> `r = 0.9`,
base `7`. `coverage_estimate: 0.42` -> `-1.0`. Final score **`6`**.
Bucket: `medium`.

---

## Issue body template

Every issue follows the layout from `temp/self-learning.md` §1. Sections
appear in this order; sections with no data are omitted (the renderer
should not emit empty headers).

```markdown
## Task Summary
- Task Type: <agent_type, e.g. supervisor / code-reviewer / qa-executor>
- Task ID: <task_id from the result block>
- Success: <true|false — derived from status enum, see below>
- Score: <N>/10
- Bucket: <low|medium|high>

## Agent Scores
- <agent>: <sub-score>/10        (one line per sub-agent if available)
                                  (omit section entirely if no sub-scores)

## Issues Detected
- <one bullet per error / failed subtask / new BLOCKING issue / failing test name>
                                  (omit section if empty)

## AI Suggestions
- (placeholder — static text in this release; future work in §Future Work)

## Tools Used
- <one bullet per distinct agent tool / skill referenced in the run if available>
                                  (omit section if empty)

## Raw Data
\`\`\`json
{
  "schema_version": 1,
  "task_id": "...",
  "agent_type": "...",
  "score": 7,
  "score_bucket": "medium",
  "status": "...",
  "redacted": true,
  ...
}
\`\`\`
```

**`Success` derivation:**

- `SUPERVISOR_RESULT`: `true` iff `status == "completed"` AND `heal_decision == "PASS"`.
- `CODE_REVIEW_RESULT`: `true` iff `decision == "PASS"`.
- `QA_RESULT`: `true` iff `tests_passed == tests_generated` AND no failing gates.

**Title format (exact):**

```
[Telemetry] {agent_type} | Score: {N} | Failed: {true|false}
```

`{N}` is the integer score (round-half-up from the rubric's clamped float).
`Failed` is the inverse of `Success` above.

---

## Labels

Every issue gets at least two labels (`telemetry` + a `score:` tier).
Additional labels stack as conditions are met.

| Label                              | When applied                                                                               |
|------------------------------------|--------------------------------------------------------------------------------------------|
| `telemetry`                        | Always.                                                                                    |
| `score:low`                        | Final score `< 4`.                                                                         |
| `score:medium`                     | Final score `4..7` (inclusive).                                                            |
| `score:high`                       | Final score `>= 8`.                                                                        |
| `task:supervisor`                  | `agent_type == "supervisor"` (matched on `SUPERVISOR_RESULT`).                             |
| `task:code-reviewer`               | `CODE_REVIEW_RESULT`.                                                                      |
| `task:qa-executor`                 | `QA_RESULT`.                                                                               |
| `agent:{name}-weak`                | When any sub-score `< 5`. `{name}` is the sub-agent identifier (lowercased, dash-separated). E.g. `agent:planner-weak`. |

Label creation is the issuer's responsibility — Subtask #2b should
`gh label create --force` (idempotent) before `gh issue create`, so missing
labels in the target repo don't fail the send.

---

## Consent flow (no-prompt-in-hook)

A `type: command` hook **cannot** drive an interactive prompt. Therefore
the hook never asks the user anything. First-run UX is mediated entirely
by the user invoking `/telemetry enable`. This is the only design that is
actually runnable with Claude Code hooks.

### Consent file schema (`.supervisor/telemetry-consent.json`)

```json
{
  "telemetry": "always_allow" | "no" | "prompt",
  "telemetry_repo": "<owner>/<repo>"
}
```

Both fields are required when present, with these semantics:

| `telemetry` value | Behaviour                                                                                              |
|-------------------|--------------------------------------------------------------------------------------------------------|
| `always_allow`    | Send (subject to interest filter, dedup, privacy, target-repo resolution).                             |
| `no`              | Never send. One `denied — skipped` line per session (rate-limited).                                    |
| `prompt`          | Treated as uninitialised (see below). The hook still does not prompt; the user must run `/telemetry enable`. |

If the file does not exist, behaviour is identical to `prompt`.

`telemetry_repo` is optional inside the file. The env var
`LOOMWRIGHT_TELEMETRY_REPO` overrides it (see Target repo
resolution below).

### Uninitialised state — pending notice

When the hook fires and consent is uninitialised (`prompt` or file
missing), the wrapper writes **one** rate-limited line to
`.supervisor/logs/telemetry.log`:

```
telemetry pending — run `/telemetry enable` or `/telemetry disable`
```

No issue is created, no network call is made, the wrapper exits 0.

### Session-scoped rate limiting

The wrapper extracts `session_id` from the hook's stdin JSON payload
(Claude Code provides this on every hook payload — see the existing
`WorktreeCreate` block in `hooks.json:112` [pins: `"WorktreeCreate"`] for the stdin parsing
pattern). The pending-notice marker is then a **per-session** flag file:

```
.supervisor/logs/telemetry-pending-shown-${session_id}.flag
```

- One file per session, not a single global file.
- The wrapper opportunistically reaps any
  `telemetry-pending-shown-*.flag` older than 24h on each invocation
  (`find ... -mtime +1 -delete`) so the log directory does not grow
  unboundedly.
- **Fallback:** if `session_id` is missing or empty in the stdin JSON
  (defence in depth), use a per-hour bucket flag:
  `telemetry-pending-shown-nosession-$(date +%Y%m%d%H).flag`. Worst case,
  the user sees one notice per hour from a bug-stripped payload.

The slash command `/telemetry status` reports a count of **retained**
pending markers from approximately the last 24 hours by globbing the
`telemetry-pending-shown-*.flag` files. The wording must explicitly say
"retained ~24h" — not "all-time" or "ever" — because the reaper deletes
older markers.

### `/telemetry enable` — sole first-run path

Subtask #3 implements the slash command. The handler:

1. Asks the user which repo should receive telemetry (suggesting the
   maintainer repo `vikashruhilgit/loomwright` as the canonical
   community-shared signal target, but accepting any `owner/repo`).
2. Writes:
   ```json
   { "telemetry": "always_allow", "telemetry_repo": "<chosen>" }
   ```
   to `.supervisor/telemetry-consent.json`.
3. Confirms by printing the resolved target.

`/telemetry disable` writes `{"telemetry": "no"}`. `/telemetry status` reports
the resolved state. `/telemetry test` runs `send-telemetry-core.sh --dry-run`
against either the latest matching log payload or a built-in fixture.

---

## Target repo resolution

The plugin runs in arbitrary user projects whose `origin` is the user's
own app repo. Defaulting telemetry to `origin` would post issues into the
user's repo — wrong on every axis (privacy, signal vs noise, support
burden). Therefore **telemetry is disabled by default until explicitly
configured**, and there is no `origin` fallback.

Resolution precedence (first non-empty wins):

1. Environment variable `LOOMWRIGHT_TELEMETRY_REPO` (must match
   shape `owner/repo`).
2. `.supervisor/telemetry-consent.json` -> `telemetry_repo` field.
3. Unset -> core exits `4` (`no_repo_configured`); wrapper logs
   `telemetry_repo_unset — set LOOMWRIGHT_TELEMETRY_REPO or run /telemetry enable to choose target` (rate-limited per session).

There is **no automatic fallback to `git remote`**. Subtask #2b must NOT
introduce one.

---

## Privacy whitelist (lives in core)

The whitelist is enforced inside `send-telemetry-core.sh`. The wrapper
does no payload inspection — it cannot, because it must always exit 0
even on privacy violations. Wrapper-side inspection would force the
contradiction the split was created to resolve.

### Deny-list (regex)

The core scans two surfaces inside `send-telemetry-core.sh`: the **raw
input payload** (every string field, plus the *resolved* result text — which
may have been read from the transcript JSONL and is therefore not itself a
payload field; scanned before consent so privacy violations always log even on
healthy runs) AND the **prospective issue body** (the rendered title + body +
redacted JSON payload, post-render). Any single match in either scan -> fail
closed (exit 2). The core's stderr is
redacted separately by the wrapper before it lands in `telemetry.log`
(see "Stderr redaction" below) — that is defence in depth, not part of
the fail-closed check.

| Pattern (regex)                 | Catches                                          |
|---------------------------------|--------------------------------------------------|
| `sk-[A-Za-z0-9]{20,}`           | OpenAI / Anthropic-style API keys                |
| `ghp_[A-Za-z0-9]{20,}`          | GitHub personal access tokens                    |
| `api[_-]?key`                   | Generic key labels (`api_key`, `api-key`, `apikey`) |
| `Bearer\s+[A-Za-z0-9._\-]+`     | Bearer auth headers                              |
| `password\s*[:=]\s*\S+`         | Inline passwords (config-style)                  |
| `/Users/[a-zA-Z._\-]+/`         | macOS home paths (PII — usernames)               |
| `/home/[a-zA-Z._\-]+/`          | Linux home paths (PII — usernames)               |
| `[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}` | Email addresses |
| `^\s*[A-Z_][A-Z0-9_]*=.+$` (multiline) | Raw `.env` style assignments              |

Subtask #2b owns the canonical list in code; this table is the spec.
Any change to the regex set must update both this doc and the script in
the same commit (consistency audit will catch drift).

### Fail-closed behaviour

On match, the core:

1. Does **not** call `gh issue create`.
2. Writes a structured `privacy_blocked` log entry naming **which
   pattern** matched — never the matched content. Example:
   ```
   {"event":"privacy_blocked","pattern_name":"github_pat","script":"send-telemetry-core","ts":"<ISO>"}
   ```
3. Exits `2`.

### Stderr redaction

The core's stderr is captured by the wrapper (`send-telemetry.sh`) into
a tmp file, then redacted by the same whitelist BEFORE the wrapper
appends it to `telemetry.log`. The redaction lives in the wrapper, not
the core, so a runaway core script (e.g. uncaught exception printing a
traceback that includes a secret) cannot bypass it. Error messages can
themselves echo secrets (e.g. `gh`'s "401 unauthorized: ghp_..."), so
this is defence in depth on top of the body + raw-payload scans the
core already runs at lines 5-6 of the pipeline.

---

## Interest filter

To avoid spam on healthy runs, the core skips uninteresting outcomes
even when consent + target repo are configured.

**Skip (exit 5) if:** derived score `>= 5` AND status is in the success set.

| Result block         | Success set                  |
|----------------------|------------------------------|
| `SUPERVISOR_RESULT`  | `{"completed"}` (with `heal_decision == "PASS"`) |
| `CODE_REVIEW_RESULT` | `{"PASS"}`                   |
| `QA_RESULT`          | `tests_passed == tests_generated` AND all gates passed |

**Send if:** derived score `< 5` OR status is in the interesting set:

| Result block         | Interesting set                                                                  |
|----------------------|----------------------------------------------------------------------------------|
| `SUPERVISOR_RESULT`  | `{"failed", "completed_with_escalation"}` (also `"checkpoint"` is interesting)  |
| `CODE_REVIEW_RESULT` | `{"FAIL", "NEEDS_HUMAN"}`                                                       |
| `QA_RESULT`          | any failing test, or any failing self-check gate                                 |

The interest filter runs **after** privacy and target-repo resolution,
**before** dedup. Order matters: privacy violations always log even on
"healthy" runs (audit trail integrity); dedup runs last so dedup never
suppresses a privacy event.

---

## Dedup window

Same {`task_id`, `score_bucket`, `primary_error`} within the last 6 hours
-> skip (exit 5).

Implementation:

- Hash key: `sha256(task_id + "::" + score_bucket + "::" + primary_error)`
  (using `hashlib.sha256(...).hexdigest()` in stage 1 — `sha256` is in the
  Python stdlib and always available, so there is no `md5` fallback).
- Storage: `.supervisor/logs/telemetry-sent.log` — one line per
  successful send, six tab-separated columns:
  `<iso_ts>\t<hash>\t<task_id>\t<score>\t<bucket>\t<issue_url>`.
- Lookup: scan the last 6h of entries (`awk` on timestamp prefix is
  sufficient at expected volumes). Match column 1 (timestamp) against the
  6h window and column 2 (hash) against the current run's hash; columns
  3-6 are recorded for `/telemetry status` reporting and post-mortem
  triage but are NOT consulted during dedup. If the hash is present, exit 5.

`primary_error`:

- `SUPERVISOR_RESULT`: first item in `subtasks_failed`, else
  `heal_decision` if not `PASS`, else empty.
- `CODE_REVIEW_RESULT`: first `new` BLOCKING issue's `description`, else
  first `new` HIGH issue's `description`, else empty. (The schema has no
  `title` field — see allowed issue keys in the SubagentStop validator at
  `hooks/hooks.json` and the v3 schema in `docs/RESULT_SCHEMAS.md`.)
- `QA_RESULT`: first failing test name, else empty.

---

## Log files

All telemetry logs live under `.supervisor/logs/`. The directory is
already gitignored via the existing `.supervisor/` rule (see CLAUDE.md
quick reference).

| Path                                                      | Format                                                                | Purpose                                |
|-----------------------------------------------------------|-----------------------------------------------------------------------|----------------------------------------|
| `.supervisor/logs/telemetry.log`                          | one JSON-ish line per event (`{"event":"...","ts":"...", ...}`)        | Full audit (sends, skips, errors, privacy blocks) |
| `.supervisor/logs/telemetry-sent.log`                     | six tab-separated columns: `<iso_ts>\t<hash>\t<task_id>\t<score>\t<bucket>\t<issue_url>` (hash is sha256; cols 3-6 are for `/telemetry status` + post-mortem triage, not consulted by dedup) | Dedup lookup (cols 1+2); `/telemetry status` last-sent timestamp |
| `.supervisor/logs/telemetry-pending-shown-${session_id}.flag` | empty file (mtime is the signal)                                  | Per-session "consent pending" rate-limit marker |
| `.supervisor/logs/telemetry-pending-shown-nosession-$(date +%Y%m%d%H).flag` | empty file (mtime is the signal)                     | Fallback marker when `session_id` is missing |

Log files are append-only from the script's perspective. Operators can
truncate or rotate them externally; the scripts must tolerate missing
files by creating them on first write.

---

## Webhook Notifications

**v12.2.0+ — complement to GitHub Issues telemetry, different purpose.**

The webhook system is a separate, opt-in delivery channel for **real-time
operational alerts** (e.g., a Slack incoming-webhook, an internal monitoring
endpoint, a Discord webhook, a PagerDuty Events API URL). It is intentionally
distinct from the GitHub Issues telemetry described above:

| Channel | Purpose | Trigger | Cadence |
|---------|---------|---------|---------|
| GitHub Issues telemetry | **Longitudinal analytics** — agent scores, issue patterns, trend lines aggregated over weeks | `code-reviewer`, `qa-executor`, `supervisor-runner` SubagentStop | Per qualifying run, dedup-windowed |
| Webhook notifications  | **Real-time ops alerts** — "did the run finish? what's the PR? did self-heal escalate? is it paused waiting on me?" | `supervisor-runner` SubagentStop; `/autonomous` gates (v14.0.0); `PreToolUse[AskUserQuestion]` pauses (v14.1.0) | Fire-and-forget per event |

Both can be enabled simultaneously, neither depends on the other, and both
fail closed (silent no-op) when their respective configuration is absent.

### Setup

```bash
export LOOMWRIGHT_WEBHOOK_URL=https://hooks.example.com/services/T000/B000/XXXX
```

That's it — once the env var is set in the shell that launches Claude Code,
every Supervisor SubagentStop fires a single POST. No `/telemetry`-style
consent file, no interactive enable command, no per-session state. To
disable, `unset LOOMWRIGHT_WEBHOOK_URL`.

### v14.1.0 — paused-event hook, file-config fallback, ntfy payload

**Third event type — `paused`.** Beyond the `supervisor_result` (completion) and `gate` (`/autonomous`) paths, `send-webhook.sh` now fires a `paused` event from a `PreToolUse[AskUserQuestion]` hook whenever the plugin blocks on a user question (Supervisor adjudication, `/autonomous` rubric gate, Plan Reviewer NEEDS_HUMAN, Launch Pad Phase 6, merge-and-continue). It is stdin-driven (the hook payload is read from stdin and matched on `hook_event_name=PreToolUse` + `tool_name=AskUserQuestion`), runs the same three-marker scope gate as `notify-desktop.sh` (`LOOMWRIGHT_NOTIFY_SCOPE=plugin` default, `all` to fire everywhere; the `Notification` hook is exempt), and POSTs:

```json
{ "event": "paused", "question": "<first question text>", "timestamp": "..." }
```

**File-config fallback.** When `LOOMWRIGHT_WEBHOOK_URL` is unset, the script falls back to `.supervisor/config.json` → `.webhook_url` (legacy `.supervisor/notify-config.json` is still read as a fallback; the new path wins when both exist). This fixes the common failure where a URL exported only in `~/.zshrc` never reaches the non-interactive (bash) hook subprocess. The env var wins when both are present.

**ntfy-aware payload.** When the resolved URL matches `*ntfy.sh/*` (or `LOOMWRIGHT_WEBHOOK_FORMAT=ntfy` is set for self-hosted instances), the `paused` event sends a **plain-text body** plus `Title` / `Priority` / `Tags` headers instead of JSON — so an ntfy phone push is readable rather than a raw JSON blob. All other endpoints (Slack/Discord/custom) receive JSON.

The `supervisor_result` and `gate` paths are **unchanged**; `LOOMWRIGHT_WEBHOOK_DRY_RUN=1` works for the `paused` path too (prints the would-be body instead of POSTing).

### Payload schema

A single JSON object, `Content-Type: application/json`:

```json
{
  "agent": "supervisor",
  "status": "completed",
  "pr_url": "https://github.com/owner/repo/pull/123",
  "summary": "Implemented v12.2.0 webhook notification...",
  "timestamp": "2026-05-10T22:53:00Z"
}
```

Field semantics:

- **`agent`** — always the literal string `"supervisor"` for v12.2.0; reserved
  for future expansion (e.g., `"qa-executor"`) without breaking consumers.
- **`status`** — copied verbatim from `SUPERVISOR_RESULT.status`. One of
  `completed | completed_with_escalation | failed | checkpoint`. The
  `SUPERVISOR_RESULT` block is located inside the agent's resolved result text
  (`last_assistant_message`, then legacy inline fields, then the transcript
  JSONL — see §Result-text extraction), **not** a top-level `result_block`
  field. Empty string if extraction failed (jq missing or malformed payload —
  see below); the payload-validity guard then suppresses the POST.
- **`pr_url`** — copied verbatim from `SUPERVISOR_RESULT.pr_url`. Empty
  string when `status ∈ {failed, checkpoint}` (no PR was created).
- **`summary`** — copied verbatim from `SUPERVISOR_RESULT.summary`, **truncated to 2,048 bytes** (with a trailing `...` ellipsis) to stay well under the body-size limits common to chat webhooks (Slack incoming-webhooks reject bodies > 40 KB; many enterprise endpoints are stricter). Receivers needing the full text should reach the PR link.
- **`timestamp`** — UTC ISO-8601 (`%Y-%m-%dT%H:%M:%SZ`) at the moment the
  hook fired (NOT when the Supervisor started).

**Forward-compatibility note:** new fields may be added to the payload in
future versions; consumers MUST ignore unknown fields rather than reject.

### Why a `type: command` wrapper, not `type: http`

Claude Code's hook system supports a native `type: http` hook, but its
env-var interpolation only substitutes `${VAR}` inside the `headers` block
— **not inside the `url`**. Since the entire feature is gated on
`LOOMWRIGHT_WEBHOOK_URL`, the URL has to resolve at hook-fire time
inside a script with shell-level env access, not inside the hook config.
A `type: command` wrapper invoking `send-webhook.sh` is the only way to
read the env var and conditionally fire (or silently skip) the request.

### Tool requirements & graceful degradation

The wrapper requires `curl` to fire the webhook and prefers `jq` for safe
JSON extraction and payload composition. Behaviour when tools are missing:

| Missing / Condition | Behaviour |
|---------------------|-----------|
| `LOOMWRIGHT_WEBHOOK_URL` unset | exit 0 immediately, zero side effects |
| `curl` not on PATH | log one line to stderr, exit 0 (no webhook fired) |
| `jq` not on PATH | field extraction skipped, `status` stays empty → payload-validity guard exits 0, webhook is NOT fired |
| Result text not resolvable (no `last_assistant_message` / legacy inline field / readable transcript) or `status` empty after extraction | logs `"no status in result block — skipping POST"` to stderr, exit 0 (no webhook fired) |
| Webhook returns non-2xx, times out (>5s), or DNS fails | curl error suppressed, exit 0 |

The wrapper **always exits 0**. The fire-and-forget contract means a slow
or unreachable webhook endpoint will never block a Supervisor run beyond
the 5-second curl timeout.

### URL safety — user responsibility

Unlike GitHub Issues telemetry, which goes only to a target repo configured
through an interactive `/telemetry enable` flow, the webhook URL is taken
verbatim from the env var and POSTed to with no domain whitelist or
validation. Setting `LOOMWRIGHT_WEBHOOK_URL` is an explicit operator
action; the operator is responsible for:

- ensuring the URL points to an endpoint they control or trust;
- ensuring the endpoint accepts unauthenticated POSTs OR carries auth
  inside the URL (e.g., a Slack webhook with a per-channel token in the
  path) — the wrapper does not support arbitrary auth headers in this
  release;
- treating the URL itself as a secret if the endpoint trusts knowledge of
  the URL (Slack, Discord, etc.) — do not commit it.

### Privacy posture

The payload contains only:

- a fixed agent label,
- a Supervisor status enum,
- the GitHub PR URL (already public on the user's repo),
- the SUPERVISOR_RESULT summary string (one or two sentences the
  Supervisor itself authored),
- a timestamp.

No file paths, no diffs, no tool transcripts, no consent file contents,
no env-var dumps. Because the operator chose the destination URL, the
deny-list redaction used by GitHub Issues telemetry does NOT run here —
the trust model is "operator picked the URL and accepts what reaches it."

### Disabling

```bash
unset LOOMWRIGHT_WEBHOOK_URL
```

The next Supervisor SubagentStop will see the wrapper exit 0 immediately
with no log line, no network call, and no side effects.

### Gate events (v14+)

**New in v14.0.0** — `send-webhook.sh` accepts a second event type used by the
`/autonomous` orchestration shell to surface user-gate moments in real time.
The supervisor_result path described above is **unchanged**; gate events run
alongside it on the same script with a separate payload shape.

**Invocation contract** (CLI-flag driven; stdin is NOT read for gate events):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/send-webhook.sh" \
  --event-type gate \
  --gate-type <phase6_save|rubric|no_rubric|adjudication> \
  --iteration <N> \
  --session-id <session_id> \
  --context "<freeform string>"
```

All flags except `--gate-type` are optional from the script's contract, though
the autonomous-loop call sites always populate `--iteration` and `--session-id`
for correlation. `LOOMWRIGHT_WEBHOOK_URL` gates the POST exactly as it
does for the supervisor_result path — the script exits 0 immediately when
the env var is unset.

**Known `gate_type` values and firing sites** (closed set in v14.0.0; new
values require updating both this doc and `skills/autonomous-loop/SKILL.md`):

| `gate_type`      | Firing site                                                                                 | When                                                                                                |
|------------------|---------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| `phase6_save`    | Launch Pad — Phase 6 brief-save prompt                                                      | Loop is about to ask the user to confirm saving the assembled brief to `.supervisor/jobs/pending/`. |
| `rubric`         | `autonomous-loop` — Signal 1 rubric gate (see `skills/autonomous-loop/SKILL.md` §"Signal 1") | Iteration ended `completed` with `rubric_score N<M` and the gate is asking the user to continue / stop / force. |
| `no_rubric`      | `autonomous-loop` — no-rubric gate (see `skills/autonomous-loop/SKILL.md` §"No-rubric gate") | Iteration ended `completed` but the brief had no `## Outcomes Rubric`; gate is asking continue / stop. |
| `adjudication`   | Supervisor — Phase 3 adjudication AskUserQuestion                                           | Supervisor's existing 4-option adjudication prompt is firing; loop emits the gate event as advance notice. |

**Injection-safety guarantee.** Both the call sites in `skills/autonomous-loop/SKILL.md`
(which forward the user-supplied context string verbatim) and `send-webhook.sh`
itself construct the JSON payload via `jq --arg` on every field — no
shell-templated JSON. The `--context` parameter is therefore safe against
single quotes, double quotes, backslashes, embedded newlines, ASCII control
characters, and Unicode; the receiver sees the exact round-tripped string
with no parse error. **Never** construct the gate payload inline at the call
site; always go through `send-webhook.sh --event-type gate`.

**Dry-run debug switch.** Setting `LOOMWRIGHT_WEBHOOK_DRY_RUN=1` (any
non-empty value) makes the script print the constructed JSON payload to
stdout INSTEAD of POSTing. The env-var gate on `LOOMWRIGHT_WEBHOOK_URL`
still applies — set it to any non-empty value (e.g., `test`) to satisfy the
gate. Useful for the injection-safety self-tests:

```bash
LOOMWRIGHT_WEBHOOK_URL=test \
  LOOMWRIGHT_WEBHOOK_DRY_RUN=1 \
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/send-webhook.sh" \
  --event-type gate \
  --gate-type rubric \
  --iteration 2 \
  --session-id auto-2026-05-16-143022 \
  --context "fix user's \"auth\" bug" \
  | jq -e .
```

**Example payload:**

```json
{
  "event_type": "gate",
  "gate_type": "rubric",
  "iteration": "2",
  "session_id": "auto-2026-05-16-143022",
  "context": "iter 2 completed PR https://github.com/org/repo/pull/57 with rubric 3/5; awaiting user decision",
  "timestamp": "2026-05-16T14:55:00Z"
}
```

Field semantics:

- **`event_type`** — always the literal string `"gate"`. Distinguishes gate
  payloads from supervisor_result payloads (which have `"agent": "supervisor"`
  as their stable type discriminator).
- **`gate_type`** — one of the four values in the table above. Consumers
  SHOULD treat unrecognized values as opaque rather than rejecting; new
  values may be added in future versions.
- **`iteration`** — **emitted as a JSON string** (e.g., `"2"`, `"0"`), not
  a number. The value is a 1-indexed iteration counter (`"0"` for
  pre-EXECUTE gates like `phase6_save` before any iteration ran). The
  string shape is a deliberate choice in `send-webhook.sh` (uses
  `jq --arg` rather than `--argjson`) so a non-numeric `--iteration`
  argument from a future caller cannot crash the payload construction.
  Consumers MUST `parseInt(payload.iteration, 10)` (or the local
  equivalent) before doing arithmetic on it — no strict-equality
  comparison against numeric literals like `payload.iteration === 2`.
- **`session_id`** — autonomous-loop session identifier (`auto-{YYYY-MM-DD}-{HHMMSS}`).
- **`context`** — freeform string the call site uses to describe the gate
  state; safe to include PR URLs, rubric scores, and short prose.
- **`timestamp`** — UTC ISO-8601 at the moment the hook fired.

**Privacy posture.** Same as supervisor_result events: the operator chose
the destination URL and accepts what reaches it. The deny-list redaction
used by GitHub Issues telemetry does NOT run here. Gate `context` strings
are author-controlled (autonomous-loop sets them) and typically contain a
PR URL plus a one-line summary — but operators who route the webhook to a
public channel should treat `context` as if it could contain anything the
loop saw fit to forward.

**Cross-references:**

- `skills/autonomous-loop/SKILL.md` §"Signal 1" and §"No-rubric gate" — the
  call sites where `--event-type gate` is invoked.
- `scripts/send-webhook.sh` — the implementation (both event-type paths
  live in the same script).

---

## Future work (out of scope for this PR)

- **Session-level batch mode.** One issue summarising N tasks per
  session instead of N issues. Spec'd in `temp/self-learning.md` §6B.
- **Weekly summary bot.** Cron-driven aggregation across created issues
  (top failures, trend per agent type).
- **Backend service.** Replacing GitHub Issues with a structured store
  once volume justifies it.
- **AI-generated suggestions.** Currently the `## AI Suggestions`
  section is static placeholder text; a future iteration could derive
  suggestions from the score breakdown and the failing signals.
- **Auto-PR for prompt fixes.** When `agent:{name}-weak` recurs N times,
  draft a PR adjusting the relevant agent's prompt.

These are intentionally deferred so the v1 surface stays small enough
to review and reason about.

---

## Post-Implementation Notes (Subtask #5 — v11.2.0)

The sections below are authoritative references added after the wrapper,
core, hook, and `/telemetry` slash command landed. They reflect what was
actually shipped, not just what was originally designed.

### Wrapper-vs-Core Architecture (Data Flow)

The runtime data flow from a `SubagentStop` hook firing through to a
posted (or rejected) GitHub issue:

```
SubagentStop hook (Claude Code)
      |
      v stdin (JSON payload)
send-telemetry.sh (wrapper, ALWAYS exit 0)
      |
      +-- captures session_id, runs reaper
      |
      v stdin
send-telemetry-core.sh (core, exit 0..5)
      |
      +-- parse → score → privacy (raw + body) → consent → repo
      |          → interest → dedup → gh
      |
      v exit code + raw stderr
send-telemetry.sh (wrapper, post-core)
      |
      +-- redacts core stderr via the privacy whitelist (defence in depth)
      |   then appends one structured line to telemetry.log
      |
      v exit 0 (always)
.supervisor/logs/telemetry.log
```

Key invariants reflected in the diagram:

- **Wrapper is fire-and-forget.** Claude Code's `SubagentStop` hook can
  never receive a non-zero exit from this pipeline — the wrapper absorbs
  every failure mode of the core (privacy block, no consent, no repo,
  filter skip, generic error) and translates it into a structured log
  line plus `exit 0`.
- **Privacy runs first.** Raw-payload privacy scan happens BEFORE
  consent and target-repo resolution (heal iter 1 of v11.2.0 reorder)
  so a healthy/successful run that contains a leaked secret still emits
  a `PRIVACY_BLOCKED` audit-log entry and exits 2 — never short-circuits
  silently via the interest filter.
- **Core owns all decisions.** Parsing, scoring, consent reading,
  target-repo resolution, the privacy whitelist, the interest filter,
  dedup, and the actual `gh issue create` invocation all live in
  `send-telemetry-core.sh`. The wrapper does no payload inspection.
- **Wrapper owns stderr redaction.** The core's stderr is captured by
  the wrapper to a tmp file, then redacted via the same regex set
  (defined in both `send-telemetry-core.sh` stage-1 Python and
  `send-telemetry.sh` Python — kept in sync per the deny-list table
  above) before being written to `telemetry.log`. This is defence in
  depth: even if a regex bug let a secret leak from core into stderr,
  the wrapper's second-pass redaction blocks it from reaching the log.
- **session_id flows from stdin.** Claude Code injects `session_id` into
  every hook payload; the wrapper extracts it for per-session
  rate-limiting flags (`telemetry-pending-shown-${session_id}.flag` and
  `telemetry-repo-unset-shown-${session_id}.flag`). The reaper deletes
  any of these flags older than ~24 hours opportunistically on each run
  so the log directory does not accumulate stale markers.

### Core Exit Codes (Authoritative)

The canonical exit-code table is defined inline in this document under
[Core exit codes (authoritative)](#core-exit-codes-authoritative). The
mirror below adds the **wrapper-action** column so log-parsers can
correlate a core exit code with what the wrapper does in response. See
the linked section above for the source-of-truth definitions.

| Code | Name                | Meaning                                                                                          | Wrapper action                                                                                                                            |
|------|---------------------|--------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| 0    | sent                | Issue posted to GitHub via `gh issue create`. URL appended to `.supervisor/logs/telemetry-sent.log`. | Log primary line `CORE_EXIT=0`. Exit 0.                                                                                                   |
| 1    | generic_error       | Unexpected error (malformed args, JSON parse failure inside repo handling, `gh` CLI failure).     | Log primary line with redacted stderr. Exit 0.                                                                                            |
| 2    | privacy_blocked     | Privacy whitelist matched; issue NOT posted; structured `PRIVACY_BLOCKED pattern=<label>` on stderr (NEVER the matched content). | Log primary line. Exit 0.                                                                                                                 |
| 3    | no_consent          | `.supervisor/telemetry-consent.json` missing or `{"telemetry":"prompt"}`/absent.                  | Log primary line; if per-session pending flag is new, set `PENDING_FLAG_NEW=true` and touch the flag (rate-limits the user-facing notice). Exit 0. |
| 4    | no_repo_configured  | Neither `LOOMWRIGHT_TELEMETRY_REPO` env var nor consent-file `telemetry_repo` is set.       | Log primary line; if the per-session repo-unset flag is new, append a SECOND `telemetry_repo_unset` line with the user-facing remediation hint. Exit 0. |
| 5    | filter_skipped      | Healthy run (score >= 5 AND status in success set), or unknown payload schema.                    | Log primary line `CORE_EXIT=5`. Exit 0.                                                                                                   |

The wrapper's primary log line shape is:

```
[<utc-ts>] CORE_EXIT=<rc> SESSION=<sid|nosession> PENDING_FLAG_NEW=<true|false> STDERR=<one-line-redacted>
```

with sentinel forms for absorbed wrapper-internal failure modes (empty
stdin, missing core executable, redaction unavailable). See the Subtask
#2a worker summary and the wrapper source for the complete log-line
grammar.

### No Default Repo — Explicit Configuration Required

The plugin is intended to be installed in **arbitrary user projects**.
The `origin` remote of the host project is, in nearly every case, the
user's own application repository — not a place where loomwright
telemetry should land. Defaulting telemetry's target repo to `origin`
would silently leak agent-run metadata, derived scores, and redacted
payloads into the user's app issue tracker, polluting their backlog and
violating the spirit of opt-in consent.

The design therefore disables telemetry **by default** until the user
explicitly configures a target repo via one of two paths: setting the
`LOOMWRIGHT_TELEMETRY_REPO` environment variable, or running
`/telemetry enable` (which prompts interactively for the target repo
and writes it to `.supervisor/telemetry-consent.json`). When neither is
set, the core exits with code `4` (`no_repo_configured`) and the
wrapper logs a single per-session reminder. This decision is also
recorded in the brief at §3 line 70.

### Plugin-Internal `scripts/` vs Repo-Root `scripts/`

The plugin uses two distinct `scripts/` directories with non-overlapping
roles:

- **`loomwright/scripts/`** — runtime scripts shipped with
  the plugin and invoked at runtime by hooks or slash commands. The
  telemetry wrapper (`send-telemetry.sh`), core (`send-telemetry-core.sh`),
  fixtures (`telemetry-fixtures/`), and test harness (`test-telemetry.sh`)
  all live here. New runtime scripts MUST go here so they ship with the
  plugin install.
- **Repo-root `scripts/`** — release/CI tooling that exists only in the
  repository checkout, never inside the installed plugin. Examples:
  `validate-version.sh` (version parity between `marketplace.json` and
  `plugin.json`) and `check-command-sync.sh` (drift guard between
  command files and agent prompts). New CI/release helpers go here. New
  runtime scripts MUST NOT go here.
