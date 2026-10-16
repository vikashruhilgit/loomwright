---
name: autonomous-loop
description: Outer-loop protocol for `/autonomous` — chains Launch Pad → Supervisor, single-iteration or multi-iteration (default, stacked branches; its protocol loads from multi-iteration.md only when needed), --notify gate webhooks via send-webhook.sh, CI / non-TTY fail-closed protection, and the AUTONOMOUS_RUN summary format. Use when implementing or invoking the `/autonomous` command.
allowed-tools: [Read, Write, Bash, Grep, Task, AskUserQuestion]
version: "1.6.0"
lastUpdated: "2026-10-16"
---

# Autonomous Loop Skill

Protocol for the `/autonomous` outer loop: chain Launch Pad → Supervisor, decide when to re-plan from `SUPERVISOR_RESULT`, and emit an `AUTONOMOUS_RUN` summary. **Foreground-assisted automation, not fire-and-forget** — every interactive boundary in the inner workflows (Launch Pad Phase 6, NO-GO, Plan Review FAIL × 3, Supervisor adjudication, the loop's own rubric gate) bubbles `AskUserQuestion` to the user in-session. History and the reasons behind these rules: `docs/rationale/launch-pad-autonomous.md` §"/autonomous — why the rules read as they do".

## Quick Rules

- The loop owns no schema, mutates no agent. It reads `SUPERVISOR_RESULT` and three file-system locations (`.supervisor/jobs/pending/`, `.supervisor/jobs/failed/`, `.supervisor/requirements/`); it writes only inside `.supervisor/autonomous/{session_id}/`, creates fresh requirement files in `.supervisor/requirements/`, and appends one JSONL log line per session to `.supervisor/logs/{session_id}.jsonl`.
- **Multi-iteration is the default mode** (cap 10, default 3, stacked branches); single-iteration requires explicit `--single-iteration`. The legacy `--allow-multi-iteration` flag is accepted as a no-op (deprecation warning emitted).
- Never auto-pick on adjudication. The 4 options surface to the user via Supervisor's existing `AskUserQuestion`.
- Two — and only two — signals trigger re-iteration: `rubric_score N<M` and `failed + inter_subtask_gap on this iteration's brief`. A third gate, the **no-rubric gate**, makes the user pick `continue` or `stop` when the brief had no rubric. All three run in multi-iteration mode only (`multi-iteration.md`).
- `current_brief_path` (captured at PLAN) is the iteration-scoping anchor. `.supervisor/jobs/failed/{basename(current_brief_path)}` existence is the unambiguous "this iteration failed" signal; prior runs have different filenames and can never collide.
- **Non-interactive safety:** if `[ ! -t 0 ]` OR `$CI` is set AND multi-iter is active AND `--non-interactive-fallback` is NOT passed, INIT aborts immediately.
- **Stacked branches:** iter N+1's feature branch is created from `iterations[N].branch` (not `main`) by default; `--no-stacked-branches` branches every iteration from `main`.
- **All gate webhook POSTs go through `${CLAUDE_PLUGIN_ROOT}/scripts/send-webhook.sh --event-type gate ...`** when `--notify` is set. The script resolves the webhook URL itself — `LOOMWRIGHT_WEBHOOK_URL`, else the user-scope `~/.claude/loomwright/egress.json` entry for this repo's slug (a repo-relative `.webhook_url` is an informational request, never a grant); the call site does not check. Never construct gate-event JSON inline.
- **Fail-loud-on-misconfig:** at INIT step 0, if `--notify` is set but NO webhook URL resolves (neither `$LOOMWRIGHT_WEBHOOK_URL` nor the user-scope `~/.claude/loomwright/egress.json` entry for this repo's slug carries a non-empty `webhook_url`), print ONE visible warning — `"--notify set, but no webhook URL resolvable (env var or ~/.claude/loomwright/egress.json); gate webhooks will NOT fire. Desktop banners are unaffected."` — then proceed (do NOT abort). A repo-relative `.supervisor/config.json` `.webhook_url` does NOT satisfy this check on its own.

## When to Use This Skill

- Implementing `/autonomous` (the slash command body references this skill).
- Diagnosing why an autonomous run ended in a particular state.
- Extending the loop with new signals (a follow-up plan reads this skill before adding behavior).

## Mode Selection

| Mode | Trigger | Behavior |
|---|---|---|
| **Multi-iteration (default)** | no mode flag, OR `--allow-multi-iteration` (deprecated, no-op), OR explicit `--max-iterations N` | INIT → PLAN → EXECUTE → EVALUATE → (loop or DONE). EVALUATE may re-plan on two signals. Default `N=3`, hard cap `N=10`. **N=1 is degenerate but valid:** one iteration with full EVALUATE / rubric-gate reporting; if Signal 1 or Signal 2 would fire, the cap-check exits with `status: paused_max_iterations, status_reason: "max_iterations_reached"`. **N=0 or N>10** rejected at INIT with `status: aborted, status_reason: "invalid_max_iterations"`. Stacked branches are the default within multi-iter; `--no-stacked-branches` branches each iteration from `main` and requires a merge between iterations. |
| **Single-iteration** | `--single-iteration` (explicit) | INIT → PLAN → EXECUTE → DONE. No loop, no EVALUATE branching. Equivalent to `--max-iterations 1` semantically but skips EVALUATE entirely (no `paused_max_iterations` status). |

### Migration hint (AC-1)

When INIT runs in the default-path multi-iter mode (no `--single-iteration`, no `--allow-multi-iteration`), it prints a one-line migration hint to stderr, once per INIT, never inside an iteration (informational only — execution proceeds):

```
⚠️ v14.0.0 — /autonomous default is now multi-iteration (max_iterations: 3, cap 10). Pass --single-iteration for v13 one-PR behavior.
```

When `--single-iteration` OR `--allow-multi-iteration` is passed, the hint is suppressed.

## Step 0 — Load Canonical Workflow Bodies + Protocol Skill (once per `/autonomous` invocation)

Before INIT, the main thread `Read`s the canonical command files **and this skill** end-to-end — and the multi-iteration protocol only when the run needs it. **All paths use `${CLAUDE_PLUGIN_ROOT}`**; repo-relative `loomwright/...` paths must not be used at runtime (CLAUDE.md "Repo path vs. runtime path"):

```
Read ${CLAUDE_PLUGIN_ROOT}/commands/launch-pad.md
Read ${CLAUDE_PLUGIN_ROOT}/commands/supervisor.md
Read ${CLAUDE_PLUGIN_ROOT}/skills/autonomous-loop/SKILL.md   # this file — re-read at runtime so the protocol can't drift from what the command body assumes
# ONLY when the arguments do NOT include --single-iteration:
Read ${CLAUDE_PLUGIN_ROOT}/skills/autonomous-loop/multi-iteration.md
```

A `--single-iteration` run (every `/automate` item) never reads `multi-iteration.md`: nothing in it runs in that mode. Every section this file marks *multi-iteration only* lives there under the same heading.

## INIT (once per invocation)

### INIT step 0 — non-interactive detection (AC-6) + flag validation

**Non-interactive detection** — run BEFORE any state-writing step:

```bash
# Effective mode resolution (precedence: --single-iteration overrides everything else):
if --single-iteration:                            multi_iter=false
elif --allow-multi-iteration AND --single-iteration: abort "conflicting_mode_flags"
elif --allow-multi-iteration alone:               multi_iter=true; warn "DEPRECATED: --allow-multi-iteration is the default in v14.0.0"
else:                                              multi_iter=true; print_v14_migration_hint

non_interactive=false
if [ ! -t 0 ] || [ -n "$CI" ]:
  non_interactive=true

if non_interactive AND multi_iter AND NOT --non-interactive-fallback:
  emit AUTONOMOUS_RUN.status="aborted", status_reason="non_interactive_without_fallback"
  print to stderr:
    "ERROR: /autonomous multi-iteration mode requires interactive terminal.
     Detected: stdin is not a TTY ($([ ! -t 0 ] && echo "yes" || echo "no")), CI env set ($([ -n "$CI" ] && echo "yes" || echo "no")).
     Multi-iter gates (rubric, no-rubric, adjudication) need AskUserQuestion.
     Recovery (pick one):
       (a) /autonomous \"<requirement>\" --single-iteration --non-interactive-fallback  # one-shot; gates fail closed / take their named branches
       (b) /autonomous \"<requirement>\" --non-interactive-fallback     # multi-iter with gates failing closed
    "
  exit
```

When `--non-interactive-fallback` IS set, gates do not call AskUserQuestion — they fail closed: rubric-gate → `status: aborted, status_reason: "rubric_gate_closed_non_interactive"`; no-rubric-gate → `status: done, status_reason: "no_rubric_in_non_interactive"`; adjudication still fires via Supervisor's session, **and the loop auto-forwards `--non-interactive` to the inlined `/supervisor` invocation** (EXECUTE step 1 — "Auto-forwarded flags") so Supervisor-owned gates fail closed too. The loop also passes `--non-interactive` to the inlined **Launch Pad** (PLAN step 1 §"Launch Pad forward" — a separate forward, not part of the `/supervisor` set). A single `--non-interactive-fallback` is therefore sufficient for CI; the user does NOT also pass `--non-interactive` to `/autonomous`.

**Main-thread-only by construction:** `/autonomous` is inline-only — no plugin surface Task-spawns it — so "executing as a subagent" never arises here; its gates key on the explicit `--non-interactive-fallback` flag, with the stdin-TTY / `$CI` probe above as the additional signal (never the only one: it false-positives inside the host's Bash tool). Named statuses per gate: `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory".

**max-iterations validation (AC-10):** after parsing `--max-iterations`:

```bash
if max_iterations < 1 OR max_iterations > 10:
  emit AUTONOMOUS_RUN.status="aborted", status_reason="invalid_max_iterations"
  print to stderr:
    "ERROR: --max-iterations must be 1..10 (got: $max_iterations).
     Cap rationale: stacked-PR review burden becomes unmanageable beyond ~10 PRs; review velocity, not loop logic, is the rate-limiting step."
  exit
```

**Conflicting-flag detection (AC-11):** after flag parsing, if `--allow-multi-iteration` AND `--single-iteration` are both set:

```bash
emit AUTONOMOUS_RUN.status="aborted", status_reason="conflicting_mode_flags"
print to stderr:
  "ERROR: cannot combine --allow-multi-iteration with --single-iteration.
   --allow-multi-iteration is DEPRECATED in v14.0.0 (multi-iter is default).
   --single-iteration explicitly disables multi-iter for v13-compat.
   Pick one: drop --allow-multi-iteration (multi-iter is default), or drop --single-iteration (run multi-iter)."
exit
```

If `--allow-multi-iteration` is the only mode-flag passed: log one-line warning `"DEPRECATED: --allow-multi-iteration is the default in v14.0.0; flag is a no-op."` to stderr, proceed in multi-iter mode.

**`--cheap` cost-profile flag:** INIT parses `--cheap` and carries it in memory for the whole invocation (NOT persisted to state.json). Its only effect is that EXECUTE step 1 appends `--cheap` to **every** inlined `/supervisor job:` invocation. Valid in every mode, no flag-conflict rules, NOT gated on `--non-interactive-fallback`. Semantics and the Haiku-session caveat: `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles".

**`--max-tokens N` token ceiling:** INIT parses `--max-tokens N` and, UNLIKE `--cheap`, PERSISTS it into `state.json` (`max_tokens: N`). INIT also acquires `.supervisor/run.lock` (`scripts/run-lock.sh acquire --owner autonomous:<session_id> --session-id "<session_id>"`); `<session_id>` is the Claude Code runtime session id for THIS `/autonomous` invocation (the same shape as `/automate` PICK, `skills/automate-loop/SKILL.md` §6 step 1, and Supervisor Phase 0); the explicit `--session-id` is what lets `close-stranded-run.sh` release a crashed session's lock. A lock already held by another run aborts INIT with `status: aborted`, `status_reason: "run_lock_held"`, printing the `run_lock_held owner=<label> pid=<pid> age=<s>` line. A `run_lock_reentrant` line (exit 0) means an enclosing `/automate` in the same session holds it — proceed; this loop's own release becomes a no-op. A `run_lock_degraded` stderr line (exit 0, TTL-only lock — `docs/ARCHITECTURE_CONTRACTS.md` §"Run lock") is NOT an abort: note it once and proceed. The lock is released at the loop's own completion tail or any abort exit. Before EACH further iteration — in multi-iteration EVALUATE, immediately after the chained review-and-heal step and before the Signal 1/2 checks — the loop sums its own session's ledger via `scripts/read-token-ledger.sh --session <session_id>` and compares TOTAL against the persisted `max_tokens`; a breach OR a `LEDGER_UNREADABLE=1` reader answer ⇒ `status: aborted`, `status_reason: "token_ceiling_reached"` (never a silent continue). EXECUTE step 1 also forwards `--max-tokens N` to every inlined `/supervisor job:`. Absent ⇒ unchanged behavior. **Honest limit:** the ledger counts only what a SubagentStop hook saw — never the main thread's own tokens, never CI-side spend; no dollar conversion. See `docs/ARCHITECTURE_CONTRACTS.md` §"Token ceiling".

### INIT step 1+ — requirement intake

1. Read the requirement — slash command argument string OR `--requirement <path>`.
2. If string-argument: write `.supervisor/requirements/{session_id}-{slug}.md`. The file contains the requirement text plus a **non-header** placeholder hint — e.g. the HTML comment `<!-- Outcomes Rubric: leave blank for multi-iteration auto-authoring, or add a "## Outcomes Rubric" section with diff-checkable bullets -->`. **The placeholder MUST NOT begin a line with `## Outcomes Rubric`:** `has_rubric` (PLAN) would treat an empty placeholder header as a real rubric and silently suppress auto-authoring. If `--requirement <path>` is used and the file already has a real `## Outcomes Rubric` section (header + bullets), leave it intact.
3. Generate `session_id` of the form `auto-{YYYY-MM-DD}-{HHMMSS}`; it must be unique enough that no two concurrent runs collide. **Collision risk:** two sessions started in the same second get identical ids; under the single-session assumption the brief-save `ls`-diff catches concurrent activity (`status_reason: "concurrent_session_detected"`).
4. Initialize `.supervisor/autonomous/{session_id}/state.json` with the schema below.
5. Initialize `.supervisor/autonomous/{session_id}/summary.md` (running AUTONOMOUS_RUN summary; re-written as iterations complete).
6. Log session start to `.supervisor/logs/{session_id}.jsonl`.

### state.json schema

`mode` is one of the string literals `"single"` or `"multi"`:

```json
{
  "_v1_note": "Advisory-only in v13.0.0 — this file is NOT AUTHORITATIVE for resume / recovery / cross-session state. It exists to seed future resume tooling (Doc 4 state.json sidecar work). The loop itself MAY read it for intra-session convenience inside the current run (e.g., the merge-verification step reads iterations[-1].branch), but external tools MUST NOT treat this file as authoritative; the markdown summary at .supervisor/autonomous/{session_id}/summary.md is the user-facing source of truth, and the SUPERVISOR_RESULT blocks in the transcript are the per-iteration source of truth.",
  "session_id": "<session_id>",
  "requirement_path": ".supervisor/requirements/<session_id>-<slug>.md",
  "mode": "single",
  "allow_multi_iteration": false,
  "iteration": 0,
  "max_iterations": 1,
  "current_brief_path": null,
  "iterations": [],
  "policy_decisions": [],
  "escalations_seen": [],
  "started_at": "<ISO-8601 UTC>",
  "last_updated": "<ISO-8601 UTC>"
}
```

Field types: `_v1_note: string`; `mode: "single" | "multi"`; `iteration` and `max_iterations` are non-negative integers; `current_brief_path` is `string | null`; `iterations`, `policy_decisions`, `escalations_seen` are arrays; timestamps are ISO-8601 UTC. The `_v1_note` field's presence is the contract signal that tooling must not treat this file as authoritative.

### state.json ACQUIRE signals (hook-readable — carve-out from the advisory-only rule)

Two top-level fields are a deliberate carve-out from the advisory-only rule: **deterministic, externally-readable ACQUIRE signals** that the `hook-dispatch-on-pr-create.sh` PostToolUse hook MAY read to match a freshly-created PR's head branch to the active autonomous session. The rest of state.json stays advisory.

The inlined Supervisor (NOT the loop) writes them at **Phase 1 ACQUIRE**, after feature-branch creation and BEFORE any `gh pr create`, into the ONE active session's `state.json` (the one whose `current_brief_path` basename matches the `job:` brief) — `commands/supervisor.md` §"Inline-path canonical state writes". The write is best-effort / non-fatal (jq atomic update → temp-file → rename; logged no-op on any error) and SKIPPED on the direct `/supervisor job:` path.

| Field | Type | Written at | Value / semantics |
|-------|------|-----------|-------------------|
| `current_branch` | `string \| null` | Phase 1 ACQUIRE | The feature-branch name just created. Absent/`null` until ACQUIRE writes it. |
| `current_status` | `string` | Phase 1 ACQUIRE | Set to the literal `"running"` at ACQUIRE — a **POSITIVE, non-terminal active status**. |

**Terminal-status set (consumer treats these as NOT-active), exactly:** `completed`, `completed_with_escalation`, `failed`, `aborted`, `done`, `paused_max_iterations`. A `current_status` value outside this set (e.g. `"running"`) means the session is active.

**No completion flip in state.json:** `current_status` is written at ACQUIRE only. The consumer hook additionally guards on `ended_at` being null AND the `current_brief_path` basename being present in `.supervisor/jobs/in-progress/`, so a stale `"running"` with a moved-out brief is rejected. (`.supervisor/state.md`'s `- status:` line is derived by `scripts/emit-progress-event.sh` + `scripts/build-state.sh`, `skills/state-management/SKILL.md` §"Progress state" — a separate, canonical file.)

## PLAN (per iteration)

**Rubric-presence test (canonical — used by PLAN step 2, step 6, and step 7).** "Has a rubric" means a **real, non-empty** Outcomes Rubric: a line-anchored `^## Outcomes Rubric` header **AND** at least one `-`/`*` bullet inside that section. An empty placeholder header, a prose mention, or an HTML-commented header does NOT count. Use `has_rubric` for every such check — a `grep -qF` substring match is NOT sufficient:

```bash
has_rubric() {   # exit 0 = real (non-empty) rubric present; exit 1 = absent/empty
  # NOTE: set a flag and decide in END — a mid-rule `exit` still runs END,
  # so an END that calls `exit` would override the rule's status.
  awk '
    /^## Outcomes Rubric/                {f=1; next}   # entered the rubric section
    f && /^## /                          {f=0}        # next top-level section -> left it
    f && /^[[:space:]]*[-*][[:space:]]/  {found=1}     # a bullet inside the section
    END                                  {exit (found ? 0 : 1)}
  ' "$1"
}
```

1. Reference the loaded `commands/launch-pad.md` workflow. Invoke it inline on the main thread, passing the current requirement file path as input. On iteration 1 this is the INIT requirement file; on every later iteration it is the refined `{session_id}-iter{N+1}.md` file the prior EVALUATE wrote — **the loop sets `requirement_path` to that new file and persists it in state.json when it loops back**, so `<requirement_path>` always denotes the current iteration's requirement.

   **Launch Pad forward (separate from the `/supervisor` forward set):** when `--non-interactive-fallback` was passed at INIT, invoke the inlined Launch Pad with `--non-interactive` appended — `<requirement_path> --non-interactive` — in every iteration. That is the ONLY flag the loop forwards to Launch Pad, and ONLY under that condition: an interactive run (no `--non-interactive-fallback`) passes the requirement path alone, so Launch Pad keeps asking on the main thread exactly as before. The flag is what arms Launch Pad's Can't-ask rule (`agents/launch-pad.md` Critical Rules) — inline on the main thread Launch Pad is not a subagent, so without it a headless run would either ask (an unnamed hang) or, at Phase 6 PASS, save nothing (`save_requires_flag_non_interactive`). With it, every Launch Pad gate takes its named branch and PLAN step 4 maps a blocked/aborted outcome whose `LAUNCH_PAD_RESULT.summary` leads with the gate's named `*_non_interactive` status to `status_reason: "launch_pad_cant_ask_non_interactive"` (Launch Pad's own summary kept verbatim in summary.md), never to `user_aborted_at_launch_pad` — no user existed to abort. This forward does not touch the `/supervisor` forward set in EXECUTE step 1 (still exactly four flags).
2. **Inline-instruction to Launch Pad (no source change):** before invoking Launch Pad, the main thread includes this directive in its inlined Launch Pad context: *"If the requirement file at `<requirement_path>` has an `## Outcomes Rubric` section, copy it verbatim into the saved brief during Phase 5 (PACKAGE — Brief Assembly). Do not paraphrase, do not drop items, do not reformat."*

   **Multi-iteration only:** the conditional auto-authoring directive (no rubric at intake, NOT under `--non-interactive-fallback`) — `multi-iteration.md` §"PLAN — multi-iteration additions".

   **When the conditional directive does NOT apply:** in **single-iteration mode** (`mode == "single"`, `--single-iteration`) OR when `has_rubric "$requirement_path"` (the requirement already has a real rubric), ONLY the preserve-verbatim directive above applies — no authoring is requested.
3. Launch Pad runs Phases 1–6 inline including:
   - Phase 2.5 feasibility AskUserQuestion (NO-GO → override/revise/abort)
   - Phase 5.5 mandatory plan-reviewer Task spawn (max 3 FAIL retries → AskUserQuestion)
   - Phase 6 save/refine/discard AskUserQuestion

   Under the Launch Pad forward (step 1) none of these asks: each takes its named branch from Launch Pad's Can't-ask rule (Phase 6 PASS saves, noted `saved_on_pass_non_interactive`).
4. **Brief-save detection — primary path: `LAUNCH_PAD_RESULT`:**
   - After Launch Pad finishes its inline run, scan the transcript for the **last** `LAUNCH_PAD_RESULT` YAML block (schema in `RESULT_SCHEMAS.md` §"LAUNCH_PAD_RESULT"; one per Launch Pad invocation, emitted in Phase 7).
   - **Validate the block before trusting it:** the SubagentStop hook on `launch-pad-runner` validates the block only when Launch Pad runs as an agent-owned session, so on this inline path run the validator here, on every invocation:
     ```bash
     # Emits {} (well-formed) or {"decision": "block", "reason": "..."} (malformed).
     printf '%s' "$BLOCK_TEXT" | python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate-launch-pad-result.py" --raw
     ```
     - `{}` (no `decision` key) → block well-formed; continue with the per-status branch below.
     - `decision: block` → malformed. Record `policy_decisions[].decision = "launch_pad_result_malformed"` with `reason` from the validator. Fall through to the `ls`-diff fallback. Do NOT abort the loop.
   - **If the block is present AND validates:**
     - `status: saved` → set `current_brief_path = LAUNCH_PAD_RESULT.saved_brief_path`. Verify the file exists (`test -f`); if not, treat as malformed and fall through to the fallback.
     - `status: discarded` → `status: aborted, status_reason: "user_discarded_at_phase_6"`. Exit.
     - `status: blocked` or `status: aborted` whose `summary` (quotes stripped) begins with a named can't-ask status — a `<name>_non_interactive` token, which Launch Pad's Can't-ask rule puts there because the block has no key for it → `status: aborted, status_reason: "launch_pad_cant_ask_non_interactive"`, and summary.md carries Launch Pad's `summary` verbatim on its `launch_pad_summary` line so the gate's own status survives. Checked BEFORE the two rows below: no user existed to abort, so `user_aborted_at_launch_pad` would misname the stop. Exit.
     - `status: blocked` (any other summary) → `status: aborted, status_reason: "launch_pad_blocked"`. Exit.
     - `status: aborted` (any other summary) → `status: aborted, status_reason: "user_aborted_at_launch_pad"`. Exit.
   - **If the block is absent or fails validation**, fall through to the `ls`-diff fallback below. Record `policy_decisions[].decision = "launch_pad_result_fallback"` (or `"launch_pad_result_malformed"`) so the run is auditable.

   **Brief-save detection — fallback path: `ls`-diff (single-session-only):**
   - **Pre-snapshot stale-session-id sanity check (catches the rubric_dropped_from_brief retry footgun):** before the `briefs_before` snapshot, check whether any file matching `<session_id>-*.md` already exists in `.supervisor/jobs/pending/` — almost always a stale brief from a prior aborted run (most commonly a `rubric_dropped_from_brief` abort the user didn't clean up). Warn with the explicit cleanup hint: `"Found stale brief(s) from a prior run with the same session-id shape: <files>. Move them to .supervisor/jobs/failed/ before continuing, or pick 'abort' below. Continuing now may produce a concurrent_session_detected error after Phase 6."` Then `AskUserQuestion` whether to (a) abort now, (b) move the stale files automatically and continue, or (c) continue anyway (force, recorded in policy_decisions for audit).
   - Before Phase 6's AskUserQuestion: `briefs_before = $(ls .supervisor/jobs/pending/*.md 2>/dev/null | sort)`
   - After Phase 6 (whether user picked save, refine-then-save, or discard): `briefs_after = $(ls .supervisor/jobs/pending/*.md 2>/dev/null | sort)`
   - `new_briefs = comm -13 <(echo "$briefs_before") <(echo "$briefs_after")`
   - If `new_briefs` is empty → user picked discard or refine failed. Mark `status: aborted, status_reason: "user_discarded_at_phase_6"`. Exit.
   - If `new_briefs` has exactly one entry → that path is `current_brief_path`. Record it in state.json. Proceed.
   - If `new_briefs` has >1 entries → ambiguity (concurrent run violated the single-session assumption). Abort with `status_reason: "concurrent_session_detected"`.

   When the block validates, `LAUNCH_PAD_RESULT.saved_brief_path` is authoritative and the `ls`-diff is informational only; the fallback is the only detection mechanism when no block was emitted.
5. Handle Launch Pad's other abort paths:
   - User aborted at NO-GO → `status_reason: "user_aborted_at_no_go"`. Exit.
   - User aborted after Plan Review FAIL × 3 → `status_reason: "user_aborted_at_plan_review_fail"`. Exit.
6. **Rubric preservation verification (when applicable):** if `has_rubric "$requirement_path"` (the requirement carried a real rubric at intake):
   ```bash
   if ! has_rubric "$current_brief_path"; then
     # Inline-instruction was not honored: a precondition was violated, the system did not fail.
     status=aborted; status_reason="rubric_dropped_from_brief"; exit
   fi
   ```
   This protects multi-iteration mode from silently degrading to single-iteration when Launch Pad ignores the inline instruction.
7. **Persist + freeze an authored rubric (multi-iteration only):** `multi-iteration.md` §"PLAN — multi-iteration additions" (PLAN step 7).
8. Update `current_brief_path` in state.json. Proceed to EXECUTE.

## EXECUTE (per iteration)

1. Reference the loaded `commands/supervisor.md` workflow. Invoke it inline on the main thread, passing `job: <current_brief_path>` plus the forwarded flags below.

   **`--base-branch` passthrough (multi-iteration only, stacked mode):** `multi-iteration.md` §"`--base-branch` passthrough (stacked mode)". Iter 1 and `--no-stacked-branches` never pass it.

   **`--non-interactive-fallback` mode:** also pass `--non-interactive` to Supervisor so its Phase 4 gh-failure path and any AskUserQuestion gates fail closed consistently with the loop's own non-interactive policy.

   **`--cheap` cost-profile forward:** when `--cheap` was passed at INIT, append `--cheap` to the inlined `/supervisor job:` invocation — **unconditionally-when-present, in every iteration**, exactly once, NOT gated on `--non-interactive-fallback`. Supervisor's cost-profile engine is reused unchanged (`docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles").

   **`--max-tokens N` token-ceiling forward:** when `--max-tokens N` was passed at INIT, append `--max-tokens N` — **unconditionally-when-present, in every iteration**, the same rule as `--cheap`, NOT gated on `--non-interactive-fallback`. Supervisor's own Phase 3 poll loop enforces the SAME ceiling against its own session's ledger (`docs/ARCHITECTURE_CONTRACTS.md` §"Token ceiling"); the outer EVALUATE check bounds spend ACROSS iterations.

   ```text
   /supervisor job: <current_brief_path> [--base-branch "$expected_base"] [--non-interactive] [--cheap] [--max-tokens N]
   ```

   **Auto-forwarded flags (the complete `/supervisor` forward set):** the loop forwards exactly four flags to the inlined `/supervisor` invocation, each under its own condition:

   | Flag | Forwarded when |
   |---|---|
   | `--base-branch "$expected_base"` | stacked multi-iter run AND `iteration > 1` (`--no-stacked-branches` NOT active) |
   | `--non-interactive` | `--non-interactive-fallback` was passed at INIT |
   | `--cheap` | `--cheap` was passed to `/autonomous` at INIT (unconditional-when-present, every iteration) |
   | `--max-tokens N` | `--max-tokens N` was passed to `/autonomous` at INIT (unconditional-when-present, every iteration) |

   No other flag is forwarded to `/supervisor` — `--skip-preflight-sync` in particular is NOT passed through (so Supervisor's Phase 1.5 pre-flight gate runs in every iteration). The loop's one OTHER forward goes to Launch Pad, not `/supervisor`: `--non-interactive`, only when `--non-interactive-fallback` was passed at INIT (PLAN step 1 §"Launch Pad forward").

2. Supervisor runs its existing 7-phase workflow inline (orchestrator → execute-manager → worker → code-reviewer → Phase 4.5 self-heal → Rubric Grader → **Phase 4.5 step 5.5 until-mergeable review-drain dispatch**). Adjudication 4-option AskUserQuestion (when outputs_gap triggers it) bubbles to the user in-session; the loop never auto-picks.

   **The Supervisor Phase 4.5 enumeration MUST NOT stop at Rubric Grader.** The entire inline Supervisor workflow runs, including **Phase 4.5 step 5.5**, the until-mergeable review-drain dispatch that is **DEFAULT-ON after PR creation** (`agents/supervisor.md` Phase 4.5 step 5.5; opt-out via `--no-until-mergeable` / `.auto_until_mergeable == false`, or `--no-auto-review` / `.auto_review == false`). It dispatches a detached, best-effort review-and-heal drain that **never gates or blocks** the `/supervisor` run (the dispatcher always exits 0).

   **Parity consequence — single-iteration mode reaches the post-PR drain** through Supervisor step 5.5, exactly like a direct `/supervisor` run, even though it skips EVALUATE. **The loop's own EVALUATE review-heal is an ADDITIONAL gate, not the only drain** — multi-iteration-only and diff-only (`multi-iteration.md`), never a substitute for step 5.5.

   **Multi-iteration interplay with the detached drain (R9 — do NOT duplicate or redesign):** the detached drain may keep pushing fix commits after the inline Supervisor run completes, so **branch-dependent downstream work — a stacked iteration N+1 or a human merge — SHOULD wait until the drain reaches a terminal `READY` / `ESCALATED` state.** The R9 invariant lives in `commands/supervisor.md` §"R9 — downstream ordering" and `skills/review-heal/SKILL.md` §"Cardinal guarantee (AC12, R9)"; the trail is the job `## Outcome` block's `**Until-mergeable dispatched:** true` + `**Until-mergeable log:** {path}` markers (`SUPERVISOR_RESULT.until_mergeable_dispatched` / `until_mergeable_log`).
3. Supervisor moves the job through `pending/ → in-progress/ → done/ or failed/` per its existing lifecycle. The autonomous loop never touches the job lifecycle.
4. Capture the emitted `SUPERVISOR_RESULT` block (the last one in the transcript per `RESULT_SCHEMAS.md` §"SUPERVISOR_RESULT") and record into state.json's `iterations[]`: `n`, `brief_path`, `supervisor_status`, `pr_url` (when present), `rubric_score`, `branch` (read directly from the required `SUPERVISOR_RESULT.branch` field), `summary`, `error` (when failed), `heal_decision`, `escalation_reason` (when completed_with_escalation). Multi-iteration EVALUATE also attaches a `review_heal` field (`multi-iteration.md` §"`review_heal` field").

5. **Fallback when Supervisor emits no `SUPERVISOR_RESULT`** (Supervisor crashed, terminal died mid-execute, network error, Task spawn returned without a result block). Detect zero `SUPERVISOR_RESULT` blocks for this iteration, then read filesystem evidence:
   - If `.supervisor/jobs/in-progress/{basename(current_brief_path)}` still exists → Supervisor never finished its lifecycle move. The job is in a half-state.
   - If `.supervisor/jobs/done/{basename(current_brief_path)}` exists but no `SUPERVISOR_RESULT` was emitted → likely a result-emission failure after the job moved.
   - If `.supervisor/jobs/failed/{basename(current_brief_path)}` exists but no `SUPERVISOR_RESULT` was emitted → Supervisor moved it to `failed/` but crashed before emitting the result block.

   In all three cases, v1 terminates the loop with `AUTONOMOUS_RUN.status: failed`, `status_reason: "supervisor_failed_other"`, and **records a synthetic iteration entry** so `iterations[]` length matches `total_iterations`:

   ```yaml
   iterations:
     - n: <current iteration>
       brief_path: <current_brief_path>
       supervisor_status: failed              # synthesized — Supervisor didn't say
       pr_url: null
       rubric_score: null
       branch: ""                             # unknown; merge verification skipped
       summary: "Supervisor emitted no SUPERVISOR_RESULT block; loop synthesized this entry from filesystem evidence."
       error: "no_supervisor_result_emitted"
       heal_decision: null
       escalation_reason: null
   ```

   The user investigates `.supervisor/jobs/`, `.supervisor/state.md`, and `.supervisor/logs/{session_id}.jsonl` before re-running. `error: "no_supervisor_result_emitted"` is grep-stable.

## EVALUATE (multi-iteration mode only)

**AC-2 single-iteration short-circuit:** EVALUATE's very first step is:

```text
if mode == "single_iteration":
  emit AUTONOMOUS_RUN.status="done", status_reason=null, last_phase="EXECUTE"
  exit
```

Single-iteration mode therefore never enters the body of EVALUATE: INIT → PLAN → EXECUTE → DONE. The body — two re-planning signals, a no-rubric gate and a default-termination branch — is in `multi-iteration.md` §"EVALUATE (multi-iteration mode only)"; its sections keep the headings below.

### EVALUATE PR-base verification (AC-3 + AC-15)

Multi-iteration only — `multi-iteration.md` §"EVALUATE PR-base verification (AC-3 + AC-15)".

### EVALUATE review-heal step (chained PR review-and-heal — fresh isolated Task context)

Multi-iteration only — `multi-iteration.md` §"EVALUATE review-heal step (chained PR review-and-heal — fresh isolated Task context)".

### Signal 1 — `status: completed` AND `rubric_score N/M` with N<M (stacked rubric gate)

Multi-iteration only — `multi-iteration.md` §"Signal 1 — `status: completed` AND `rubric_score N/M` with N<M (stacked rubric gate)".

### Signal 2 — `status: failed` AND Option C triggered this iteration

Multi-iteration only — `multi-iteration.md` §"Signal 2 — `status: failed` AND Option C triggered this iteration".

### No-rubric gate (`status: completed` AND `rubric_score` is null)

Multi-iteration only — `multi-iteration.md` §"No-rubric gate (`status: completed` AND `rubric_score` is null)".

### Default termination — any other SUPERVISOR_RESULT outcome ends the loop

Multi-iteration only — `multi-iteration.md` §"Default termination — any other SUPERVISOR_RESULT outcome ends the loop".

### Phase 1.5 pre-flight gate — CI fail-closed termination

Multi-iteration only — `multi-iteration.md` §"Phase 1.5 pre-flight gate — CI fail-closed termination".

### Max-iterations cap

Multi-iteration only — `multi-iteration.md` §"Max-iterations cap".

## DONE — AUTONOMOUS_RUN Summary

Written to `.supervisor/autonomous/{session_id}/summary.md` (markdown for users) and `.supervisor/autonomous/{session_id}/state.json` (machine-readable sidecar). Echoed to main-thread output.

**Canonical schema:** `loomwright/docs/RESULT_SCHEMAS.md` § "AUTONOMOUS_RUN" (the closed `status_reason` enum, validation rules, worked example) is the source of truth for the block's shape.

The status enum is **autonomous-layer-only**: `done | paused_max_iterations | aborted | failed`. None of these values appear in `SUPERVISOR_RESULT.status` (`completed | completed_with_escalation | failed | checkpoint`); keep the two enums distinct.

### summary.md format

```markdown
# Autonomous Run Summary

- **session_id:** <session_id>
- **requirement_path:** `.supervisor/requirements/<session_id>-<slug>.md`
- **mode:** single | multi
- **allow_multi_iteration:** true | false
- **max_iterations:** integer ≥ 1 (`1` for single-iteration runs — the implicit cap; the configured value for multi-iteration runs, default 3)
- **status:** done | paused_max_iterations | aborted | failed
- **status_reason:** null | "max_iterations_reached" | "user_discarded_at_phase_6" | "user_aborted_at_no_go" | "user_aborted_at_plan_review_fail" | "user_stopped_at_rubric_gate" | "user_stopped_at_no_rubric_gate" | "supervisor_checkpoint" | "supervisor_failed_other" | "supervisor_base_branch_mismatch" | "rubric_dropped_from_brief" | "concurrent_session_detected" | "invalid_max_iterations" | "non_interactive_without_fallback" | "conflicting_mode_flags" | "iter_pr_base_mismatch" | "rubric_gate_closed_non_interactive" | "no_rubric_in_non_interactive" | "user_aborted_gh_retry" | "launch_pad_blocked" | "user_aborted_at_launch_pad" | "preflight_overlap_detected" | "review_heal_escalated_non_interactive" | "launch_pad_cant_ask_non_interactive" | "run_lock_held" | "token_ceiling_reached"
- **launch_pad_summary:** `LAUNCH_PAD_RESULT.summary` verbatim — written only when `status_reason` is `"launch_pad_cant_ask_non_interactive"` (it names the Launch Pad gate that stopped the run); omitted otherwise
- **total_iterations:** 2
- **last_phase:** DONE | EVALUATE | PLAN | EXECUTE
- **started_at:** <ISO-8601 UTC>
- **ended_at:** <ISO-8601 UTC>
- **duration_seconds:** 1429

## Iterations

| n | Brief | Supervisor Status | PR | Rubric | Branch |
|---|---|---|---|---|---|
| 1 | `.supervisor/jobs/done/auto-...-add-jwt-auth.md` | completed | https://github.com/.../pull/42 | 3/5 | feature/jwt-auth |
| 2 | `.supervisor/jobs/done/auto-...-iter2.md` | completed | https://github.com/.../pull/43 | 5/5 | feature/jwt-auth-iter2 |

## Policy Decisions

| Iter | Phase | Decision | Source |
|---|---|---|---|
| 1 | PLAN | user_picked_save | launch_pad_phase_6 |
| 1 | EVALUATE | user_picked_merge_and_continue | autonomous_rubric_gate |
| 2 | PLAN | user_picked_save | launch_pad_phase_6 |

## Escalations Seen

(none) | heal_loop_max_retries (iteration N) | self_heal_resume_thrash (iteration N) | ...
```

### state.json (machine-readable sidecar)

Same fields as summary.md, structured as JSON. Written for (a) intra-session convenience reads by the loop itself and (b) seeding future resume tooling; never for cross-session resume (no `--continue` flag exists), and no SubagentStop hook validates it. The file is **not authoritative for resume / recovery / cross-session state**.

**v1-only `_v1_note` field:** every state.json this loop writes begins with the `_v1_note` string (schema above), marking the file **advisory-only**. Tooling that finds `_v1_note` MUST refuse to use the file for **resume / recovery / cross-session state** queries until a state.json without `_v1_note` is observed. **Carve-out exception:** the two **ACQUIRE signals** `current_branch` + `current_status` (§"state.json ACQUIRE signals (hook-readable — carve-out from the advisory-only rule)") stay readable by `hook-dispatch-on-pr-create.sh` while `_v1_note` is present.

## Concurrency / Single-Session Assumption

**Concurrent-session safety.** Brief-save detection reads `LAUNCH_PAD_RESULT.saved_brief_path` from the Launch Pad call this loop inlined (one block per invocation), so a concurrent `/launch-pad` writing to the same `.supervisor/jobs/pending/` cannot be mistaken for this loop's save. The `ls`-diff fallback keeps the single-session-only constraint. Session-id-tagged filenames in `.supervisor/requirements/` and `.supervisor/autonomous/{session_id}/` isolate the loop's own state.

## Failure Modes & Recovery

| Failure | Detection | Recovery |
|---|---|---|
| User discards at Phase 6 | `new_briefs` empty after Phase 6 | Clean exit, summary status=aborted |
| Launch Pad ignores rubric-preservation inline instruction | `has_rubric "$current_brief_path"` returns absent (no real rubric in the saved brief) | Loop aborts with `status: aborted, status_reason: "rubric_dropped_from_brief"` (no iteration reaches EXECUTE; `total_iterations: 0`, `iterations: []`). **Cleanup required before re-running:** the saved brief is still in `.supervisor/jobs/pending/` (filename starts with this run's `session_id`); move or delete it, or the next run's `ls`-diff may pick it up or trip `concurrent_session_detected`. One-liner: `mv .supervisor/jobs/pending/<this-session-id>-*.md .supervisor/jobs/failed/`. **Recovery paths:** re-run without `--allow-multi-iteration` (single-iteration ignores the rubric-preservation gate entirely), or pre-author the brief by hand with the rubric included. |
| Concurrent autonomous run or manual launch-pad | `new_briefs` has >1 entry after Phase 6 | Abort with status_reason="concurrent_session_detected" |
| `gh` unavailable for merge check | `gh pr view` returns non-zero | Fallback to `git merge-base --is-ancestor`; if neither confirms, re-prompt user |

Session termination mid-loop and `inter_subtask_gap` string drift are unsupported / fall through to default termination: `docs/rationale/launch-pad-autonomous.md` §"/autonomous failure modes without a recovery path".

## Hard Reuse Contract (no source changes)

- **Launch Pad inline workflow:** referenced via Step 0 + PLAN invocation. One inline instruction (rubric preservation) is delivered through the inlined prompt, never as a Launch Pad source change.
- **Supervisor inline workflow:** referenced via Step 0 + EXECUTE invocation. No instruction modifications.
- **Adjudication 4-option escalation:** Supervisor surfaces existing options A/B/C/D via AskUserQuestion; the loop never auto-picks. Option C produces `failed + inter_subtask_gap`, a substring `FAILURE_ESCALATION.md` §"Inter-Subtask Gap / Scope Expansion" documents as grep-stable.
- **SUPERVISOR_RESULT schema (v12.2):** v1 reads existing fields only — `status`, `pr_url`, `error`, `summary`, `rubric_score`, `branch`. No schema change; `reason` does not exist on the block.
- **`.supervisor/jobs/` lifecycle:** Supervisor remains sole writer/mover. The loop only reads `pending/` (brief-save detection) and `failed/` (Option-C anchor).
- **`.supervisor/state.md`:** the `## Session` block is derived by `scripts/emit-progress-event.sh` + `scripts/build-state.sh` (`skills/state-management/SKILL.md` §"Progress state"); Context-Keeper writes the other sections. The loop **does not** grep state.md for `inter_subtask_gap`.

## Cross-References

- `${CLAUDE_PLUGIN_ROOT}/skills/autonomous-loop/multi-iteration.md` — the multi-iteration protocol; Step 0 loads it unless `--single-iteration`
- `${CLAUDE_PLUGIN_ROOT}/skills/review-heal/SKILL.md` — authority for the chained EVALUATE review-heal step
- `${CLAUDE_PLUGIN_ROOT}/scripts/send-webhook.sh` — `--event-type gate` path used by every gate-firing site when `--notify` is set
- `loomwright/docs/RESULT_SCHEMAS.md` § "AUTONOMOUS_RUN" — canonical schema; `SUPERVISOR_RESULT` schema including `rubric_score`
- `loomwright/docs/FAILURE_ESCALATION.md` §"Inter-Subtask Gap / Scope Expansion" — adjudication options and the `inter_subtask_gap` grep-stable string
- `loomwright/agents/supervisor.md` — Phase 0 preamble, Phase 3 adjudication Option-C handler, Phase 4 self-verify, Phase 4.5 base-mismatch cleanup
- `loomwright/skills/supervisor-readiness/SKILL.md` — brief format the loop relies on Launch Pad to produce
- `loomwright/skills/state-management/SKILL.md` and `loomwright/agents/context-keeper.md` — `.supervisor/state.md` write semantics
