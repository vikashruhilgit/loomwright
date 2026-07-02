---
name: autonomous-loop
description: Outer-loop protocol for `/autonomous` — v14 continuous (multi-iteration default with stacked branches), single-iteration opt-in, EVALUATE PR-base verification + Signal-1 stacked rubric gate + no-rubric gate, --notify gate webhooks via send-webhook.sh, CI / non-TTY fail-closed protection, and the AUTONOMOUS_RUN summary format. Use when implementing or invoking the `/autonomous` command.
allowed-tools: [Read, Write, Bash, Grep, Task, AskUserQuestion]
version: "1.3.1"
lastUpdated: "2026-06-14"
---

# Autonomous Loop Skill

Protocol for the `/autonomous` outer loop. Owns the orchestration that chains Launch Pad → Supervisor, decides when to re-plan based on `SUPERVISOR_RESULT` signals, and emits an `AUTONOMOUS_RUN` summary. **Foreground-assisted automation, not fire-and-forget** — every interactive boundary in the inner workflows (Launch Pad Phase 6, NO-GO, Plan Review FAIL × 3, Supervisor adjudication, the loop's own rubric gate) bubbles `AskUserQuestion` to the user in-session via Claude Code's native interaction model.

<!-- v14.2.0 hardening: brief-save detection now consults `LAUNCH_PAD_RESULT.saved_brief_path` as the primary signal (schema in RESULT_SCHEMAS.md §"LAUNCH_PAD_RESULT"; emission cadence in agents/launch-pad.md Phase 7). The ls-diff of `.supervisor/jobs/pending/` is retained as a fallback for pre-v14.2.0 compatibility but is no longer the primary mechanism. The concurrent-session ambiguity that single-session-only ls-diff couldn't distinguish is closed for v14.2.0+ plugins. -->

## Quick Rules

- The loop owns no schema, mutates no agent. It reads `SUPERVISOR_RESULT` and three file-system locations (`.supervisor/jobs/pending/`, `.supervisor/jobs/failed/`, `.supervisor/requirements/`); it writes only inside `.supervisor/autonomous/{session_id}/`, creates fresh requirement files in `.supervisor/requirements/`, and appends one JSONL log line per session to `.supervisor/logs/{session_id}.jsonl` (the session log).
- **Multi-iteration is the default mode in v14.0.0** (cap 10, default 3, stacked branches). Single-iteration (v13-compat) requires explicit `--single-iteration`. The legacy `--allow-multi-iteration` flag is silently accepted as a no-op (deprecation warning emitted).
- Never auto-pick on adjudication. The 4 options surface to the user via Supervisor's existing `AskUserQuestion`.
- Two — and only two — signals trigger re-iteration: `rubric_score N<M` (in stacked-branch mode no merge is required; in `--no-stacked-branches` mode merge-and-continue is still verified) and `failed + inter_subtask_gap on this iteration's brief` (no merge needed; the job was abandoned). A third gate, the **no-rubric gate**, fires when the brief had no rubric — the user picks `continue` or `stop` explicitly rather than the loop silently terminating.
- `current_brief_path` (captured at PLAN via `ls`-diff) is the iteration-scoping anchor. `.supervisor/jobs/failed/{basename(current_brief_path)}` existence is the unambiguous "this iteration failed" signal; prior runs have different filenames and can never collide.
- **Non-interactive safety:** if `[ ! -t 0 ]` OR `$CI` is set AND multi-iter is active AND `--non-interactive-fallback` is NOT passed, INIT aborts immediately. This is the only escape from CI hangs in v14; gate-timeout is deferred to v15.
- **Stacked branches:** iter N+1's feature branch is created from `iterations[N].branch` (not `main`) by default. `--no-stacked-branches` reverts to v13 cadence (each iter branches from `main`).
- **All gate webhook POSTs go through `${CLAUDE_PLUGIN_ROOT}/scripts/send-webhook.sh --event-type gate ...`** when `--notify` is set and a webhook URL is resolvable — `LOOMWRIGHT_WEBHOOK_URL` **or** the `.supervisor/config.json` → `.webhook_url` fallback (legacy `.supervisor/notify-config.json` is still read as a fallback; the new path wins when both exist; send-webhook.sh resolves either internally; the call site does not need to check). Never construct gate-event JSON inline (jq-only payload construction is enforced by send-webhook.sh; the autonomous-loop call site must honor that boundary).
- **Fail-loud-on-misconfig (v14.2.2):** at INIT step 0, if `--notify` is set but NEITHER `$LOOMWRIGHT_WEBHOOK_URL` is set NOR `.supervisor/config.json` carries a non-empty `.webhook_url`, print ONE visible warning — `"--notify set, but no webhook URL resolvable (env var or .supervisor/config.json); gate webhooks will NOT fire. Desktop banners are unaffected."` — then proceed (do NOT abort; desktop notifications and the rest of the loop are independent of the webhook).

## When to Use This Skill

- Implementing `/autonomous` (the slash command body references this skill).
- Diagnosing why an autonomous run ended in a particular state.
- Extending the loop with new signals (a follow-up plan reads this skill before adding behavior).

## Mode Selection (v14.0.0 — multi-iter is the default)

| Mode | Trigger | Behavior |
|---|---|---|
| **Multi-iteration (default)** | no mode flag, OR `--allow-multi-iteration` (deprecated, no-op), OR explicit `--max-iterations N` | INIT → PLAN → EXECUTE → EVALUATE → (loop or DONE). EVALUATE may trigger re-plan on two signals. Default `N=3`, hard cap `N=10`. **N=1 is degenerate but valid:** the loop runs one iteration with full EVALUATE / rubric-gate reporting; if Signal 1 or Signal 2 would fire, the cap-check exits with `status: paused_max_iterations, status_reason: "max_iterations_reached"` instead of re-iterating. **N=0 or N>10** rejected at INIT with `status: aborted, status_reason: "invalid_max_iterations"`. **Stacked branches are the default** within multi-iter — iter N+1 branches from `iterations[N].branch`. Pass `--no-stacked-branches` to revert to v13 cadence (each iter branches from `main`, merge required between iterations). |
| **Single-iteration** | `--single-iteration` (explicit) | INIT → PLAN → EXECUTE → DONE. No loop, no EVALUATE branching. Pure command chaining. v13-compat. Equivalent to `--max-iterations 1` semantically but skips EVALUATE entirely (no `paused_max_iterations` status). |

**Why the default flipped in v14:** v13's "default single, opt-in multi" assumed multi-iter was advanced behavior. In practice, the only-rubric and only-Option-C signals are the common shape of real autonomous work — single-iter is the special case, not the default. Stacked branches in v14 remove the prior merge-and-wait friction that made multi-iter feel heavy. v13 callers scripting around the single-PR contract should pass `--single-iteration` explicitly.

### Migration hint (AC-1)

When INIT runs in the default-path multi-iter mode (no `--single-iteration`, no `--allow-multi-iteration`), it prints a one-line migration hint to stderr:

```
⚠️ v14.0.0 — /autonomous default is now multi-iteration (max_iterations: 3, cap 10). Pass --single-iteration for v13 one-PR behavior.
```

The hint fires once per INIT, never inside an iteration. It is informational only — execution proceeds regardless. When `--single-iteration` OR `--allow-multi-iteration` is passed, the hint is suppressed (the caller has indicated awareness of the mode choice).

## Step 0 — Load Canonical Workflow Bodies + Protocol Skill (once per `/autonomous` invocation)

Before INIT, the main thread `Read`s the canonical command files **and this skill** end-to-end. **All paths use `${CLAUDE_PLUGIN_ROOT}`**, the canonical Claude Code variable that resolves to the plugin install dir on both maintainer dev checkouts and marketplace installs. Repo-relative `loomwright/...` paths only work in the maintainer checkout and **must not** be used at runtime (see CLAUDE.md "Repo path vs. runtime path"):

```
Read ${CLAUDE_PLUGIN_ROOT}/commands/launch-pad.md
Read ${CLAUDE_PLUGIN_ROOT}/commands/supervisor.md
Read ${CLAUDE_PLUGIN_ROOT}/skills/autonomous-loop/SKILL.md   # this file — re-read at runtime so the protocol can't drift from what the command body assumes
```

This guards against prompt drift on three fronts. If Launch Pad, Supervisor, or this autonomous-loop protocol evolves between releases, `/autonomous` picks up the changes automatically. The "references, not duplicates" promise from the command body depends on this step. Without it, the autonomous body's references could become stale invocations of behaviors the main thread guesses at.

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
       (a) /autonomous \"<requirement>\" --single-iteration             # one-shot, no gates
       (b) /autonomous \"<requirement>\" --non-interactive-fallback     # multi-iter with gates failing closed
    "
  exit
```

When `--non-interactive-fallback` IS set, gates do not call AskUserQuestion — they fail closed: rubric-gate → `status: aborted, status_reason: "rubric_gate_closed_non_interactive"`; no-rubric-gate → `status: done, status_reason: "no_rubric_in_non_interactive"` (the loop accepts the iteration and exits cleanly); adjudication still fires via Supervisor's session, **and the loop auto-forwards `--non-interactive` to the inlined `/supervisor` invocation** (see EXECUTE step 1 — "Auto-forwarded flags"). The forwarding makes Supervisor's Phase 4 `gh` retry path, adjudication AskUserQuestion, and any other Supervisor-owned interactive gates fail closed consistently with the loop's own policy. A single `--non-interactive-fallback` is therefore sufficient for the CI / unattended case — the user does NOT need to also pass `--non-interactive` to `/autonomous`. (`/supervisor` standalone still accepts the flag explicitly; that's a separate invocation path.)

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

### INIT step 1+ — requirement intake

1. Read the requirement — slash command argument string OR `--requirement <path>`.
2. If string-argument: write `.supervisor/requirements/{session_id}-{slug}.md` (the `session_id` already carries the date — `auto-{YYYY-MM-DD}-{HHMMSS}` — so the path is sortable without a redundant date prefix). The file contains the requirement text plus a **non-header** placeholder hint — e.g. the HTML comment `<!-- Outcomes Rubric: leave blank for multi-iteration auto-authoring, or add a "## Outcomes Rubric" section with diff-checkable bullets -->`. **The placeholder MUST NOT begin a line with `## Outcomes Rubric`:** the canonical rubric-presence test below (`has_rubric`, a line-anchored header **plus** ≥1 bullet) would otherwise treat an empty placeholder header as a real rubric and silently suppress auto-authoring on the common inline-string path. If `--requirement <path>` is used and the file already has a real `## Outcomes Rubric` section (header + bullets), leave it intact.
3. Generate `session_id` of the form `auto-{YYYY-MM-DD}-{HHMMSS}` (or similar — must be unique enough that no two concurrent runs collide; per v1 single-session assumption, a timestamp suffices). **Collision risk in v1:** two sessions started in the same second would produce identical `session_id`s. Moot under the v1 single-session-only assumption (the loop also detects concurrent activity via the brief-save `ls`-diff and aborts with `status_reason: "concurrent_session_detected"`), but a v2 hardening can append a short random suffix (e.g., `auto-{YYYY-MM-DD}-{HHMMSS}-{4hex}`) once concurrent sessions become supported.
4. Initialize `.supervisor/autonomous/{session_id}/state.json` with the schema below.
5. Initialize `.supervisor/autonomous/{session_id}/summary.md` (running AUTONOMOUS_RUN summary; will be re-written as iterations complete).
6. Log session start to `.supervisor/logs/{session_id}.jsonl`.

### state.json schema

Example (concrete values shown — `mode` is one of the string literals `"single"` or `"multi"`, not a union annotation):

```json
{
  "_v1_note": "Advisory-only in v13.0.0 — this file is NOT AUTHORITATIVE for resume / recovery / cross-session state. It exists to seed future resume tooling (Doc 4 state.json sidecar work). The loop itself MAY read it for intra-session convenience inside the current run (e.g., the merge-verification step reads iterations[-1].branch), but external tools MUST NOT treat this file as authoritative; the markdown summary at .supervisor/autonomous/{session_id}/summary.md is the user-facing source of truth, and the SUPERVISOR_RESULT blocks in the transcript are the per-iteration source of truth.",
  "session_id": "auto-2026-05-11-143022",
  "requirement_path": ".supervisor/requirements/auto-2026-05-11-143022-add-jwt-auth.md",
  "mode": "single",
  "allow_multi_iteration": false,
  "iteration": 0,
  "max_iterations": 1,
  "current_brief_path": null,
  "iterations": [],
  "policy_decisions": [],
  "escalations_seen": [],
  "started_at": "2026-05-11T14:30:22Z",
  "last_updated": "2026-05-11T14:30:22Z"
}
```

Field types: `_v1_note: string` (advisory marker — see above); `mode: "single" | "multi"` (literal-union string); `iteration` and `max_iterations` are non-negative integers; `current_brief_path` is `string | null`; `iterations`, `policy_decisions`, `escalations_seen` are arrays; timestamps are ISO-8601 UTC. The `_v1_note` field is removable once a v2 plan defines a stable resume contract — its presence is the contract signal that tooling should not treat this file as authoritative.

### state.json ACQUIRE signals (hook-readable — carve-out from the advisory-only rule)

The `_v1_note` "Advisory-only — NOT authoritative" rule above governs the file **as a whole** for resume / recovery / cross-session state. **Two top-level fields are a deliberate, explicit carve-out** from that rule: they are **deterministic, externally-readable ACQUIRE signals** that the `hook-dispatch-on-pr-create.sh` PostToolUse hook MAY read for session disambiguation (matching the freshly-created PR's head branch to the active autonomous session). The REST of state.json stays advisory / non-authoritative as before.

These two fields are written by the inlined Supervisor (NOT by the autonomous loop itself) at **Phase 1 ACQUIRE**, immediately after feature-branch creation and BEFORE any `gh pr create`, into the ONE active session's `state.json` (identified by `current_brief_path` basename matching the `job:` brief being executed) — per `commands/supervisor.md` §"Inline-path canonical state writes". The write is best-effort / non-fatal (jq atomic update → temp-file → rename; logged no-op on any error) and is SKIPPED on the direct `/supervisor job:` path (no autonomous state.json there).

| Field | Type | Written at | Value / semantics |
|-------|------|-----------|-------------------|
| `current_branch` | `string \| null` | Phase 1 ACQUIRE | The feature-branch name just created. Absent/`null` until ACQUIRE writes it (the branch otherwise only reaches `iterations[-1].branch` at EVALUATE — post-PR / too late for the hook). |
| `current_status` | `string` | Phase 1 ACQUIRE | Set to the literal `"running"` at ACQUIRE — a **POSITIVE, non-terminal active status**. |

**Terminal-status set (consumer treats these as NOT-active), exactly:** `completed`, `completed_with_escalation`, `failed`, `aborted`, `done`, `paused_max_iterations`. A `current_status` value outside this set (e.g. `"running"`) means the session is active.

**No completion flip in state.json:** `current_status` is written at ACQUIRE only — there is intentionally NO state.json completion flip. The consumer hook additionally guards on `ended_at` being null AND the `current_brief_path` basename being present in `.supervisor/jobs/in-progress/`, so a stale `state.json` with `current_status:"running"` but a moved-out brief is correctly rejected without needing a flip. (The `.supervisor/state.md` `- status:` line IS flipped to `completed`/`completed_with_escalation` at the Phase 4.5 completion tail — that is the canonical state file, separate from this advisory sidecar.) **Residual window (accepted):** because there is no positive terminal flip here, liveness rests entirely on that external cleanup — if an autonomous run dies WITHOUT moving its brief out of `jobs/in-progress/` AND without stamping `ended_at`, its `state.json` stays "active" indefinitely, and a later unrelated PR whose head branch exactly equals that crashed feature branch could be dispatched against via Source 2. This is accepted residual risk, not a blocker: the window is narrow (requires an exact branch-name collision AND the stale brief still in `in-progress/` — which the plugin already treats as an active run), it is Source-2-only (a non-terminal `state.md` is the preferred Source 1), and the drain is fail-safe (NEVER merges, NEVER force-pushes).

## PLAN (per iteration)

**Rubric-presence test (canonical — used by PLAN step 2, step 6, and step 7).** Everywhere PLAN checks whether `<requirement_path>` or `current_brief_path` "has a rubric", it means a **real, non-empty** Outcomes Rubric: a line-anchored `^## Outcomes Rubric` header **AND** at least one `-`/`*` bullet inside that section. An empty placeholder header, a prose mention, or an HTML-commented header does NOT count (this is why INIT writes a *non-header* placeholder). Use `has_rubric` below for every such check — a `grep -qF` substring match is NOT sufficient (it fires on commented headers, inline mentions, and empty placeholder headers, which would silently suppress auto-authoring):

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
2. **Inline-instruction to Launch Pad (no source change):** before invoking Launch Pad, the main thread includes this directive in its inlined Launch Pad context: *"If the requirement file at `<requirement_path>` has an `## Outcomes Rubric` section, copy it verbatim into the saved brief during Phase 5 (PACKAGE — Brief Assembly). Do not paraphrase, do not drop items, do not reformat."* Launch Pad will see this as part of the inlined workflow body.

   **Conditional auto-authoring directive (multi-iteration only, no rubric at intake):** when the run is in **multi-iteration mode** (`mode == "multi"`, i.e. NOT `--single-iteration`) AND `! has_rubric "$requirement_path"` (no real rubric per the canonical test above — an empty/placeholder header counts as absent), the inlined directive ALSO instructs Launch Pad to **auto-author** a rubric via its guarded Phase 5 step: *"This requirement has no `## Outcomes Rubric` and the caller is running in multi-iteration mode. During Phase 5, auto-author a rubric — derive 3–7 diff-checkable bullets from the brief's Acceptance Criteria and the Phase 3 analysis, following `agents/launch-pad.md` Phase 5 step 7 and the authoring rules in `skills/supervisor-readiness/SKILL.md` §\"Auto-Authoring (multi-iteration)\". Do not restate those rules here — defer to them as the single source of truth."* (Those producers own the authoring contract; this directive only triggers it — see the `### Auto-Authoring (multi-iteration)` subsection in `skills/supervisor-readiness/SKILL.md`.)

   **When the conditional directive does NOT apply:** in **single-iteration mode** (`mode == "single"`, `--single-iteration`) OR when `has_rubric "$requirement_path"` (the requirement already has a real rubric), ONLY the preserve-verbatim directive above applies — no authoring is requested and behavior is unchanged from prior versions.

   **Degenerate-rubric fallback:** if Launch Pad cannot derive ≥3 diff-checkable bullets (the brief lacks enough concrete, diff-checkable acceptance signal), it emits NO `## Outcomes Rubric` section — and the loop proceeds under its existing no-rubric gate (Signal 1 stacked rubric gate is skipped; see EVALUATE's no-rubric handling). Auto-authoring is best-effort, never a hard precondition.
3. Launch Pad runs Phases 1–6 inline including:
   - Phase 2.5 feasibility AskUserQuestion (NO-GO → override/revise/abort)
   - Phase 5.5 mandatory plan-reviewer Task spawn (max 3 FAIL retries → AskUserQuestion)
   - Phase 6 save/refine/discard AskUserQuestion
4. **Brief-save detection — primary path: `LAUNCH_PAD_RESULT` (v14.2.0+):**
   - After Launch Pad finishes its inline run, scan the transcript for the **last** `LAUNCH_PAD_RESULT` YAML block (schema in `RESULT_SCHEMAS.md` §"LAUNCH_PAD_RESULT"; emission cadence: one per Launch Pad invocation, emitted in Phase 7).
   - **Validate the block before trusting it (closes the inline-path validation gap):** the SubagentStop hook on `launch-pad-runner` validates the block only when Launch Pad runs as an agent-owned session (`claude --agent loomwright:launch-pad-runner`). For the inline slash-command path that `/autonomous` actually invokes, run the validator from this skill so schema violations are caught on every invocation:
     ```bash
     # Extract the block text, then pipe it to the validator in --raw mode.
     # Emits {"ok": true} or {"ok": false, "reason": "..."}.
     printf '%s' "$BLOCK_TEXT" | python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate-launch-pad-result.py" --raw
     ```
     - `ok: true` → block well-formed; continue with the per-status branch below.
     - `ok: false` → malformed. Record `policy_decisions[].decision = "launch_pad_result_malformed"` with `reason` from the validator. Fall through to the `ls`-diff fallback. Do NOT abort the loop — the fallback is functionally equivalent for the common single-session case.
   - **If the block is present AND validates** (the v14.2.0+ path):
     - `status: saved` → set `current_brief_path = LAUNCH_PAD_RESULT.saved_brief_path`. Verify the file exists (`test -f`); if not, treat as malformed and fall through to the fallback.
     - `status: discarded` → `status: aborted, status_reason: "user_discarded_at_phase_6"`. Exit.
     - `status: blocked` → `status: aborted, status_reason: "launch_pad_blocked"`. Exit.
     - `status: aborted` → `status: aborted, status_reason: "user_aborted_at_launch_pad"`. Exit.
   - **If the block is absent or fails validation** (pre-v14.2.0 plugin, main thread skipped Phase 7, or schema violation), fall through to the `ls`-diff fallback below. Record `policy_decisions[].decision = "launch_pad_result_fallback"` (or `"launch_pad_result_malformed"`) so the run is auditable.

   **Brief-save detection — fallback path: `ls`-diff (pre-v14.2.0 compatibility, single-session-only):**
   - **Pre-snapshot stale-session-id sanity check (catches the rubric_dropped_from_brief retry footgun):** before the `briefs_before` snapshot, check whether any file matching `<session_id>-*.md` already exists in `.supervisor/jobs/pending/`. The `session_id` is freshly minted in INIT (timestamp-based), so a pre-existing match is an invariant violation — almost always a stale brief left over from a prior aborted run of *this same `/autonomous` invocation pattern* (most commonly a previous `rubric_dropped_from_brief` abort whose stale brief the user didn't clean up). Surface this as a warning to the user with the explicit cleanup hint: `"Found stale brief(s) from a prior run with the same session-id shape: <files>. Move them to .supervisor/jobs/failed/ before continuing, or pick 'abort' below. Continuing now may produce a concurrent_session_detected error after Phase 6."` Then `AskUserQuestion` whether to (a) abort now, (b) move the stale files automatically and continue, or (c) continue anyway (force, recorded in policy_decisions for audit). Strictly speaking the timestamp-based session_id makes exact collisions impossible in v1, so this check fires only on the rubric_dropped_from_brief retry footgun and similar leftover-brief cases.
   - Before Phase 6's AskUserQuestion: `briefs_before = $(ls .supervisor/jobs/pending/*.md 2>/dev/null | sort)`
   - After Phase 6 (whether user picked save, refine-then-save, or discard): `briefs_after = $(ls .supervisor/jobs/pending/*.md 2>/dev/null | sort)`
   - `new_briefs = comm -13 <(echo "$briefs_before") <(echo "$briefs_after")`
   - If `new_briefs` is empty → user picked discard or refine failed. Mark `status: aborted, status_reason: "user_discarded_at_phase_6"`. Exit.
   - If `new_briefs` has exactly one entry → that path is `current_brief_path`. Record it in state.json. Proceed.
   - If `new_briefs` has >1 entries → ambiguity (concurrent run violated the single-session assumption). Abort with `status_reason: "concurrent_session_detected"`.

   The fallback path remains the **only** detection mechanism when the plugin version pre-dates v14.2.0 (no Phase 7 emission). For v14.2.0+ plugins, `LAUNCH_PAD_RESULT.saved_brief_path` is authoritative and the `ls`-diff is informational only.
5. Handle Launch Pad's other abort paths:
   - User aborted at NO-GO → `status_reason: "user_aborted_at_no_go"`. Exit.
   - User aborted after Plan Review FAIL × 3 → `status_reason: "user_aborted_at_plan_review_fail"`. Exit.
6. **Rubric preservation verification (when applicable):** if `has_rubric "$requirement_path"` (the requirement carried a real rubric at intake):
   ```bash
   if ! has_rubric "$current_brief_path"; then
     # Inline-instruction was not honored. Abort cleanly — the loop chose
     # to stop because a precondition for multi-iteration was violated,
     # not because the system itself failed. Pairs with status: aborted
     # per RESULT_SCHEMAS.md AUTONOMOUS_RUN status↔reason table.
     status=aborted; status_reason="rubric_dropped_from_brief"; exit
   fi
   ```
   This protects multi-iteration mode from silently degrading to single-iteration when Launch Pad ignores the inline instruction.
7. **Persist + freeze an authored rubric (multi-iteration only):** an AUTHORED rubric (from PLAN step 2's conditional auto-authoring directive) lives only in the saved brief at this point, but **every refined-requirement template** (the stacked-mode and merge-and-continue templates in the EVALUATE Signal-1 section, AND the Option-C inter-subtask-gap re-plan template) copies `<original requirement body, including ## Outcomes Rubric verbatim>` from `<requirement_path>` — NOT from the brief — into every iteration N+1. Because the freeze lands in the requirement body, all of these paths inherit the rubric automatically. So an authored rubric must be written back into the requirement body now, or iteration 2+ would score against an absent rubric. This step:
   - **Fires ONLY when ALL of:** `mode == "multi"` AND the **current** requirement file at `<requirement_path>` has no real rubric yet (`! has_rubric "$requirement_path"`) AND the saved brief (`current_brief_path`) now has a real rubric (`has_rubric "$current_brief_path"` — Launch Pad auto-authored one and the human approved it at Phase 6). **The has_rubric-on-the-current-file guard is what makes this step idempotent:** on iteration 1 the rubric was just authored and the requirement lacks it → the step fires exactly once; on every later iteration the refined-requirement template (below) already copied the frozen rubric into `<requirement_path>`, so the grep matches and the step is a no-op — it never appends a second `## Outcomes Rubric`. **Do NOT gate on a run-global "had rubric at intake" flag** — such a value never changes across iterations, so it would re-fire the append on every iteration and accumulate duplicate rubric sections.
   - **Extract + append + verify (all inside one idempotency guard):** copy the `## Outcomes Rubric` section verbatim from `current_brief_path` (from the `## Outcomes Rubric` header through to the next top-level `## ` header or EOF), append it to `<requirement_path>`, and confirm it landed — **all within the same guard** so the verification (and its warning) runs ONLY when a freeze was actually attempted, never on the degenerate no-rubric path:
     ```bash
     # Idempotency guard: freeze only when the CURRENT requirement file does not
     # already carry the rubric — true on exactly the iteration that authored it,
     # a no-op on every later iteration (the refined-requirement template already
     # copied the frozen rubric into $requirement_path). Never gate on a run-global flag.
     if [ "$mode" = "multi" ] \
        && ! has_rubric "$requirement_path" \
        && has_rubric "$current_brief_path"; then
       # Extract the rubric section verbatim from the saved brief, then append.
       rubric_section="$(awk '/^## Outcomes Rubric/{f=1} f&&/^## /&&!/^## Outcomes Rubric/{exit} f' "$current_brief_path")"
       printf '\n\n%s\n' "$rubric_section" >> "$requirement_path"
       # Freeze verification — inside the guard, so it only fires after a genuine
       # append. If the append somehow did NOT take, the verbatim refined-requirement
       # templates would copy a body with no rubric and iteration 2+ would score
       # against an absent rubric — surface a warning.
       if ! has_rubric "$requirement_path"; then
         echo "WARNING: rubric freeze failed — '## Outcomes Rubric' not found in $requirement_path after append. Later iterations will run under the no-rubric gate." >&2
       fi
     fi
     ```
   - **Degenerate-case no-op:** if Launch Pad fell back (no rubric authored — the degenerate-rubric fallback in PLAN step 2's directive), `current_brief_path` has no `## Outcomes Rubric`, the guard's third condition is false, the whole block (append AND verification) is skipped — no misleading "freeze failed" warning — and the loop proceeds under its existing no-rubric gate.
8. Update `current_brief_path` in state.json. Proceed to EXECUTE.

## EXECUTE (per iteration)

1. Reference the loaded `commands/supervisor.md` workflow. Invoke it inline on the main thread, passing `job: <current_brief_path>` plus the **stacked-mode flag passthrough** described below.

   **`--base-branch` passthrough (v14.0.0 stacked-mode belt-and-suspenders):** when this iteration is iter N+1 of a stacked-mode multi-iter run (i.e., `iteration > 1` AND `--no-stacked-branches` is NOT active), the loop MUST pass `--base-branch "$expected_base"` to Supervisor on top of the `job:` argument:

   ```text
   expected_base = iterations[-2].branch   # parent iter's branch — same value EVALUATE's PR-base verification uses
   /supervisor job: <current_brief_path> --base-branch "$expected_base"
   ```

   The brief is ALSO expected to carry a `Base Branch:` field under `## Configuration` (the stacked-mode refined-requirement template in EVALUATE writes it; see "Refined requirement (stacked mode)" below). The CLI flag is the **authoritative source** — Supervisor's Phase 0 reads `--base-branch` first; the brief field is a secondary anchor that Plan Reviewer validates for consistency.

   **Why both:** if Launch Pad's inline directive is ignored and the brief is saved without `Base Branch:`, the CLI flag still wins. If the CLI flag is somehow stripped (e.g., a future refactor that re-parses argv), the brief field is the fallback. The two paths must agree at Plan Review time, or Plan Reviewer Criterion 13 will FAIL (v14.0.0+).

   **`--no-stacked-branches` mode and iter 1:** do NOT pass `--base-branch`. Supervisor's Phase 0 defaults to `main` when the flag is absent, which is the correct behavior for both cases. Iter 1 of every autonomous run is unstacked by definition (no parent iter exists).

   **`--non-interactive-fallback` mode:** also pass `--non-interactive` to Supervisor so its Phase 4 gh-failure path and any AskUserQuestion gates fail closed consistently with the loop's own non-interactive policy. Without this, the loop is fail-closed at gates it owns but Supervisor's Phase 4 retry-loop AskUserQuestion is still interactive.

2. Supervisor runs its existing 7-phase workflow inline (orchestrator → execute-manager → worker → code-reviewer → Phase 4.5 self-heal → Rubric Grader → **Phase 4.5 step 5.5 until-mergeable review-drain dispatch**). Adjudication 4-option AskUserQuestion (when outputs_gap triggers it) bubbles to the user in-session per existing FAILURE_ESCALATION; the autonomous loop never auto-picks.

   **The Supervisor Phase 4.5 enumeration MUST NOT stop at Rubric Grader.** When `/autonomous` runs Supervisor inline, the **entire** inline Supervisor workflow runs — including Supervisor's **Phase 4.5 step 5.5**, the **until-mergeable review-drain dispatch** that is **DEFAULT-ON after PR creation** (`agents/supervisor.md` Phase 4.5 step 5.5; opt-out via `--no-until-mergeable` / `.supervisor/config.json` `.auto_until_mergeable == false`, or suppress the whole dispatch via `--no-auto-review` / `.auto_review == false`). Step 5.5 dispatches a fresh, **detached** standalone review-and-heal run (the `--agent loomwright:review-pr-runner` form) that drains required CI checks, bot reviews/threads/comments, and check outputs until the PR is mergeable. It is best-effort / fire-and-forget and **never gates or blocks** the `/supervisor` run (the dispatcher always exits 0; the drain never changes the `heal_decision` and never blocks the PR — see the fail-safe invariant in CLAUDE.md and `agents/supervisor.md` step 5.5).

   **Parity consequence — single-iteration mode reaches the post-PR drain.** Because step 5.5 is part of the inline Supervisor workflow, **single-iteration `/autonomous` reaches the post-PR until-mergeable drain through Supervisor step 5.5** — identical to a direct `/supervisor` run (where step 5.5 dispatches unconditionally on a PASS/normal completion that produced a PR). This holds **even though single-iteration mode short-circuits EVALUATE** (see "AC-2 single-iteration short-circuit" in EVALUATE): the loop's own EVALUATE review-heal is NOT the only drain path, so single-iteration's skipping of EVALUATE no longer means "no post-PR drain." (Defense-in-depth: the `PostToolUse[Bash]` hook backstop documented in `agents/supervisor.md` step 5.5 ALSO dispatches the same drain at `gh pr create` time on the inline path; the dispatcher's per-PR idempotency marker guarantees exactly one dispatch.)

   **The loop's own EVALUATE review-heal is an ADDITIONAL gate, not the only drain.** The chained review-heal in EVALUATE (see "EVALUATE review-heal step") is an extra inline gate that feeds the **multi-iteration stacking decision** — its behavior is unchanged. It runs ONLY in multi-iteration mode (single-iteration short-circuits EVALUATE before it ever runs), is diff-only (it does NOT pass `--until-mergeable`), and never merges. It is therefore additive to — never a substitute for — Supervisor step 5.5's post-PR until-mergeable drain.

   **Multi-iteration interplay with the detached drain (R9 — do NOT duplicate or redesign).** Because step 5.5's drain is **detached**, it may keep pushing fix commits to the PR branch **after** the inline Supervisor run is marked complete. **Branch-dependent downstream work — a stacked iteration N+1 (which branches from `iterations[N].branch`) or a human merge — SHOULD wait until the detached drain reaches a terminal `READY` / `ESCALATED` state before proceeding**, otherwise it may stack on or merge a branch the drain is still mutating. This is the **R9 downstream-ordering invariant** authored in `commands/supervisor.md` §"R9 — downstream ordering" and `skills/review-heal/SKILL.md` §"Cardinal guarantee (AC12, R9)"; it is **not redefined here** — cross-link only. The visible trail to check is the job `## Outcome` block's `**Until-mergeable dispatched:** true` + `**Until-mergeable log:** {path}` markers (mirrored on `SUPERVISOR_RESULT` as `until_mergeable_dispatched` / `until_mergeable_log`) plus the drain's best-effort terminal `READY`/`ESCALATED` notification.
3. Supervisor moves the job through `pending/ → in-progress/ → done/ or failed/` per its existing lifecycle. The autonomous loop never touches the job lifecycle.
4. Capture the emitted `SUPERVISOR_RESULT` block (the last one in the transcript per `RESULT_SCHEMAS.md` §"SUPERVISOR_RESULT" emission-cadence note) and record relevant fields into state.json's `iterations[]` array: `n`, `brief_path`, `supervisor_status`, `pr_url` (when present), `rubric_score`, `branch` (read directly from the `SUPERVISOR_RESULT.branch` field — a required v12.2-schema string), `summary`, `error` (when failed), `heal_decision`, `escalation_reason` (when completed_with_escalation). The `branch` field is what the merge-verification step (Signal 1 in EVALUATE) resolves to a SHA via `git rev-parse`.

   **`review_heal` field (added for the chained EVALUATE review-heal step):** when EVALUATE runs the chained review-and-heal step (see EVALUATE §"review-heal step"), it attaches the parsed `REVIEW_HEAL_RESULT` block to this same `iterations[]` entry under a `review_heal` field. The field is **null** when the step was skipped (no `pr_url`, or `supervisor_status == failed`); otherwise it holds the `REVIEW_HEAL_RESULT` shape from `skills/review-heal/SKILL.md` (`decision` (`PASS|ESCALATED`; the schema v2 `READY` value is `--until-mergeable`-only and **never emitted by EVALUATE** — it does not pass that flag), `iterations`, `issues_fixed`, `remaining_issues`, `pr_url`, `notified`). Recording it alongside the `SUPERVISOR_RESULT`-derived fields keeps the per-iteration record complete and consistent with how every other per-iteration result is stored. Example entry:

   ```yaml
   iterations:
     - n: 1
       brief_path: .supervisor/jobs/done/auto-...-add-jwt-auth.md
       supervisor_status: completed
       pr_url: "https://github.com/.../pull/42"
       rubric_score: "3/5"
       branch: feature/jwt-auth
       summary: "..."
       heal_decision: PASS
       review_heal:                       # the chained EVALUATE review-heal REVIEW_HEAL_RESULT (null if skipped)
         decision: PASS                   # PASS | ESCALATED
         iterations: 1
         issues_fixed: 0
         remaining_issues: 0
         pr_url: "https://github.com/.../pull/42"
         notified: false
   ```

5. **Fallback when Supervisor emits no `SUPERVISOR_RESULT`** (Supervisor crashed, terminal died mid-execute, network error before completion, Task spawn returned without a result block). Detect this by searching the transcript and finding zero `SUPERVISOR_RESULT` blocks for this iteration. The loop cannot infer Supervisor's actual state, but it CAN determine the loop-level outcome from filesystem evidence:
   - If `.supervisor/jobs/in-progress/{basename(current_brief_path)}` still exists → Supervisor never finished its lifecycle move. The job is in a half-state.
   - If `.supervisor/jobs/done/{basename(current_brief_path)}` exists but no `SUPERVISOR_RESULT` was emitted → likely a result-emission failure after the job moved; recoverable in principle but not in v1.
   - If `.supervisor/jobs/failed/{basename(current_brief_path)}` exists but no `SUPERVISOR_RESULT` was emitted → Supervisor moved it to `failed/` but crashed before emitting the result block.
   
   In all three cases, v1 terminates the loop with `AUTONOMOUS_RUN.status: failed`, `status_reason: "supervisor_failed_other"`, and **records a synthetic iteration entry** in `iterations[]` so the array length matches `total_iterations` per schema:
   
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
   
   The user is expected to manually investigate `.supervisor/jobs/`, `.supervisor/state.md`, and `.supervisor/logs/{session_id}.jsonl` before re-running. The `error: "no_supervisor_result_emitted"` string is grep-stable for future tooling that may treat this case differently.

## EVALUATE (multi-iteration mode only)

**AC-2 single-iteration short-circuit:** EVALUATE's very first step is:

```text
if mode == "single_iteration":
  emit AUTONOMOUS_RUN.status="done", status_reason=null, last_phase="EXECUTE"
  exit
```

Single-iteration mode therefore never enters the body of EVALUATE — no PR-base verification, no rubric gate, no Signal-1 / Signal-2 evaluation. Single-iter is pure command chaining: INIT → PLAN → EXECUTE → DONE.

Multi-iteration EVALUATE reads `SUPERVISOR_RESULT` (status, pr_url, error, summary, rubric_score, branch, heal_decision, branch_base, pr_state — last two added in v14 by S3) plus iteration-scoped file-system artifacts (`.supervisor/jobs/pending/` for brief-save detection during PLAN, `.supervisor/jobs/failed/{basename(current_brief_path)}` for the Option-C iteration anchor, and that failed-brief's own contents for the `inter_subtask_gap` grep). **Two re-planning signals** drive loop continuation; a **no-rubric gate** and a **default-termination branch** handle other outcomes.

### EVALUATE PR-base verification (AC-3 + AC-15)

Before evaluating signals, the loop verifies that the iteration's PR was opened against the expected base. **Skip conditions** (no verification attempted):

- `iteration == 1` — first iteration has no parent iter; base is `main` by definition.
- `--no-stacked-branches` is active — every iter branches from `main`, no stacked verification needed.
- `pr_url` is null — Supervisor failed before creating a PR (merge conflict, env error, etc.). AC-15 says: skip verification (don't call `gh pr view "null"`), fall through to Signal evaluation; `status: failed` then takes the default-termination branch with `status_reason: "supervisor_failed_other"`.

When NOT skipped (`iteration > 1` AND stacked AND `pr_url` non-null):

```bash
expected_base="$(jq -r '.iterations[-2].branch' .supervisor/autonomous/${session_id}/state.json)"
# Pseudocode — see the in-memory-state note in Signal 1 above. iterations[-1] is the
# CURRENT iteration (just appended by EXECUTE); iterations[-2] is the parent iter whose
# branch is the expected base for this iter's stacked PR. Real implementations should
# keep `parent_iter.branch` in memory rather than re-reading state.json here.

actual_base="$(gh pr view "$pr_url" --json baseRefName -q .baseRefName 2>/dev/null)"
if [ $? -ne 0 ]; then
  sleep 5
  actual_base="$(gh pr view "$pr_url" --json baseRefName -q .baseRefName 2>/dev/null)"  # retry once (AC-14)
  if [ $? -ne 0 ]; then
    if [ "$non_interactive" = "true" ]; then
      # AC-14 non-interactive fall-through: log and skip verify
      log "gh pr view --json baseRefName failed twice; non-interactive — skipping PR-base verification."
      goto signal_evaluation
    else
      # AC-14 interactive fallback: AskUserQuestion(retry / skip-verify-once / abort)
      AskUserQuestion(
        "gh pr view --json baseRefName failed twice for PR ${pr_url}. Pick one:",
        ["retry", "skip-verify-once", "abort"]
      )
      # retry: re-run gh once more (manual third attempt); on success continue with actual_base.
      #        On failure of the third attempt, re-prompt this same AskUserQuestion once more
      #        (max one re-prompt). If the user picks retry a second time and that fails too,
      #        auto-abort with status_reason="user_aborted_gh_retry" — same as the explicit
      #        abort option. This bounds the retry loop deterministically.
      # skip-verify-once: record policy_decisions entry, continue as if verified.
      # abort: emit AUTONOMOUS_RUN.status=aborted, status_reason="user_aborted_gh_retry", exit.
    fi
  fi
fi

if [ "$actual_base" != "$expected_base" ]; then
  emit AUTONOMOUS_RUN.status="aborted", status_reason="iter_pr_base_mismatch"
  log "Iter $iteration PR opened against $actual_base, expected $expected_base. Aborting."
  exit
fi
```

The verification site here is the **second line of defense** — Supervisor's own Phase 4 self-verify (S3 lands the symmetric block in `agents/supervisor.md`) is the first. Defense in depth handles the case where Supervisor's self-verify was silenced (env error, `gh` outage) but Phase 4.5 still completed and emitted `SUPERVISOR_RESULT`. Identical retry policy on both sites avoids divergence.

### EVALUATE review-heal step (chained PR review-and-heal — fresh isolated Task context)

After PR-base verification passes and **before** any Signal evaluation (Signal 1 / Signal 2 / no-rubric gate / default termination), the loop runs the standalone PR **review-and-heal** workflow as a chained step. The `review-heal` skill (`${CLAUDE_PLUGIN_ROOT}/skills/review-heal/SKILL.md`) is the authority for this step's loop semantics; this section only describes how the autonomous loop invokes it and records its outcome.

> **This is an ADDITIONAL multi-iteration-only gate, not the post-PR drain.** EVALUATE runs only in multi-iteration mode (single-iteration short-circuits EVALUATE — see "AC-2 single-iteration short-circuit" above), and this chained review-heal exists to inform the **multi-iteration stacking decision** (does iteration N+1 stack on a PR the reviewer flagged?). It is **diff-only** — it does NOT pass `--until-mergeable`. The **post-PR until-mergeable drain** is a separate, default-ON path dispatched by **Supervisor Phase 4.5 step 5.5** during EXECUTE (see EXECUTE step 2), which runs in **both** single- and multi-iteration mode. So this EVALUATE step is additive to step 5.5's drain, never a replacement for it — single-iteration mode still reaches the post-PR drain via step 5.5 even though it never runs this EVALUATE step.

**Skip conditions** (no review-heal attempted — fall straight through to Signal evaluation):

- `pr_url` is null — the iteration did not produce a PR (Supervisor failed before PR creation, merge conflict, env error). There is nothing for review-heal to operate on.
- `SUPERVISOR_RESULT.status == failed` — the iteration did not complete successfully. Review-heal runs **only after a SUCCESSFUL Supervisor iteration that produced a PR** (`status == completed` or `completed_with_escalation`, with a non-null `pr_url`).

**Execution form (AC6 — Task step, NOT a nested `claude` process):** the `/autonomous` path runs review-and-heal as a **`Task`-spawned step with fresh isolated context** — this is entry sense **(b)** in `skills/review-heal/SKILL.md` §"Two entry senses of 'fresh'". It is **NOT** a nested `claude --agent loomwright:review-pr-runner` operating-system process (that runner-as-its-own-session form is entry sense (a), reserved for the plain `/supervisor` completion-tail path). Per the review-heal skill's execution-contract rule (AC9), the loop also does **NOT** `Task`-spawn the `review-pr-runner` agent (a Task-spawned runner would sit one spawn-level too deep and its own child spawns would fail). Instead, the Task step itself runs the review-heal **loop body inline** (the bounded review→fix→re-review machinery from `review-heal` skill Step 2):

```text
review_heal = Task(
  subagent_type: "general-purpose",
  # Fresh isolated context. The Task body runs the review-heal loop body inline
  # per skills/review-heal/SKILL.md Step 1 (PR-URL → branch resolution) + Step 2
  # (the bounded review→fix→re-review loop, default 3 iterations). It does NOT
  # Task-spawn loomwright:review-pr-runner (AC9 — runner is never
  # Task-spawned); it emits a REVIEW_HEAL_RESULT block.
  prompt: "Run the PR review-and-heal loop on PR <pr_url> exactly per
           skills/review-heal/SKILL.md (resolve the head branch, bounded
           review→fix→re-review, default 3 iterations, NEVER --force, NEVER
           auto-merge). Emit a REVIEW_HEAL_RESULT block (schema_version 1) with
           decision (PASS|ESCALATED), iterations, issues_fixed, remaining_issues,
           pr_url, notified."
  # NOTE: this step does NOT pass --until-mergeable, so it emits schema_version 1
  # and NEVER decision: READY. READY + the drain/postmortem fields are the
  # opt-in --until-mergeable (schema v2) surface, which /autonomous does not use.
)
# Parse the REVIEW_HEAL_RESULT block from the Task transcript.
```

**Record the outcome:** attach the parsed `REVIEW_HEAL_RESULT` to this iteration's `iterations[]` entry under the `review_heal` field (see the `iterations[]` shape in EXECUTE step 4). This records the chained review-heal result alongside the iteration's `SUPERVISOR_RESULT`-derived fields, consistent with how the loop records other per-iteration results.

**Branch on `decision` (per the `review-heal` skill outcome model):**

- **`PASS`** → the PR diff is clean (review-heal made no further-needed fixes, or fixed all new+BLOCKING/HIGH issues across its bounded iterations). The loop **continues normally to Signal evaluation** (Signal 1 rubric gate / Signal 2 / no-rubric gate / default termination) — review-heal PASS does not itself change the iterate-or-stop decision.
- **`ESCALATED`** → review-heal exhausted its bound or the reviewer returned `NEEDS_HUMAN`; findings were posted to the PR and best-effort notifications fired. Surface this to the user through the loop's **existing `AskUserQuestion` escalation surface** — the same in-session interaction model EVALUATE already uses for adjudication / gate surfacing. **Do NOT invent a new gate or prompt mechanism.** The prompt informs the user that the chained review-and-heal escalated (with `remaining_issues` and `pr_url`) and offers the existing continue / stop choices; record a `policy_decisions` entry `{iteration: N, phase: EVALUATE, decision: "review_heal_escalated", source: "autonomous_review_heal"}`. Under `--non-interactive-fallback` (no TTY), this escalation fails closed consistent with the loop's other gates rather than calling AskUserQuestion.
- **`READY` / any unrecognized decision** → EVALUATE **never emits `READY`**: it invokes the loop body **without** `--until-mergeable`, and `READY` (with the v2 drain/postmortem fields) is emitted **only** under that opt-in `/review-pr`-only mode (`REVIEW_HEAL_RESULT` schema v2 — see `docs/RESULT_SCHEMAS.md`). Defensively, the parser treats `READY` (or any decision value it does not recognize) as a **terminal, non-re-iterate** state — it does **NOT** loop back to PLAN and does NOT fire the escalation `AskUserQuestion`; it degrades safely by falling through to normal Signal evaluation exactly as it does for `PASS` (a v1 consumer thus continues / lets the cap-check terminate rather than crashing on an unexpected value). This keeps the v2 `READY` value forward-compatible without changing `/autonomous`'s iterate-or-stop behavior.
- **Forward-compat with the additive v2 drain fields** → the all-channel drain landed four OPTIONAL/additive `REVIEW_HEAL_RESULT` fields (`channels_scanned`, `findings_validated`, `findings_dismissed`, `checks_waited`; see `docs/RESULT_SCHEMAS.md` §"REVIEW_HEAL_RESULT"). EVALUATE keys **only** off `decision` (and the v1 core fields it records into `review_heal`), so these — and any future additive field — are simply **ignored** by the parser: their presence never makes EVALUATE choke or change its iterate-or-stop behavior. They appear only under `--until-mergeable`, which EVALUATE does not pass. The until-mergeable readiness semantics are NOT restated here — `skills/review-heal/SKILL.md` is the single source of truth.

This step is **additive** — it does not alter the PR-base verification above it or the Signal-1 / Signal-2 logic below it; it slots between them. Review-heal **never merges** the PR (no-auto-merge contract, `review-heal` skill §"No auto-merge ever"), so it cannot create a new PR that would retrigger the loop.

### Signal 1 — `status: completed` AND `rubric_score N/M` with N<M (stacked rubric gate)

Loop pauses. **AC-5 webhook gate POST (when `--notify` AND `$LOOMWRIGHT_WEBHOOK_URL` are set)** — fired BEFORE the AskUserQuestion so the receiver knows a gate is imminent even if the user hangs:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/send-webhook.sh" \
  --event-type gate \
  --gate-type rubric \
  --iteration "$iteration" \
  --session-id "$session_id" \
  --context "iter $iteration completed PR $pr_url with rubric $rubric_score; awaiting user decision" &
# Backgrounded — fire-and-forget, exit 0 always per send-webhook.sh contract. The
# AskUserQuestion below runs synchronously immediately after; the webhook delivery
# may complete after or before the user answers — the loop does not wait.
```

Main-thread `AskUserQuestion` then fires. The prompt branches on stacked vs non-stacked:

**Stacked-branch mode (v14 default):**

> *"Iteration {N} completed with PR #{X} (rubric score {N/M}). Iteration {N+1} will branch from `iterations[{N}].branch` directly — no merge is required between iterations. Options:*
> - *(a) continue-to-next-iteration (proceed with iter N+1 stacked on top of iter N's branch — the typical v14 path),*
> - *(b) stop-here (accept the current rubric score, exit),*
> - *(c) force-continue-anyway (here, equivalent to continue-to-next-iteration; preserved for v13-compat scripting that expects this option)."*

**`--no-stacked-branches` mode (v13-compat cadence):**

> *"Iteration {N} completed with PR #{X} (rubric score {N/M}). `--no-stacked-branches` is active, so iteration {N+1} will branch from `main` — PR #{X} should be merged first. Options:*
> - *(a) merge-and-continue (merge PR #{X} manually now, then pick this to proceed),*
> - *(b) stop-here (accept the current rubric score, exit),*
> - *(c) force-continue-anyway (proceed without merge; risk: iteration {N+1}'s branch won't include iteration {N}'s changes, likely producing conflicting PRs)."*

**Non-interactive fallback:** when `--non-interactive-fallback` is set AND no TTY, the gate does NOT call AskUserQuestion. The loop exits with `status: aborted, status_reason: "rubric_gate_closed_non_interactive"`. The fail-closed policy is intentional — silently picking `continue` would be unsafe in CI, and silently picking `stop` would silently degrade multi-iter to single-iter.

**Stacked mode — `continue-to-next-iteration` (no merge verification needed):** iter N+1's branch will be created from `iterations[N].branch` at the start of EXECUTE in the next iteration. No `gh pr view` merge check. Use the **stacked-mode refined-requirement template** (below) — it differs from the merge-and-continue template because it must tell Launch Pad: (a) the parent iter's PR is unmerged and stacked, (b) the new brief must carry `Base Branch: <iter N's branch>` in its `## Configuration` block so Plan Reviewer and Supervisor agree on the stacking parent, and (c) re-discovery should compare against `iterations[N].branch` (not the default branch) when scoping the next brief.

**Refined requirement (stacked mode) — write this file at `.supervisor/requirements/{session_id}-iter{N+1}.md`:**

```
{session_id}-iter{N+1}.md
---
<original requirement body, including `## Outcomes Rubric` verbatim>

---

## Iteration Note (autonomous loop, stacked-mode auto-generated <ISO timestamp>)

Prior iteration {N} scored **{N/M}** on the Outcomes Rubric. PR #{X} (`<pr_url>`) is **unmerged** and is the stacking parent for this iteration — iteration {N+1}'s feature branch MUST be created from `iterations[N].branch` (`<iter_N_branch_name>`), NOT from `main`.

**Inline directive to Launch Pad (mandatory for this iteration):**
- The saved brief's `## Configuration` block MUST contain the line `Base Branch: <iter_N_branch_name>` verbatim. Plan Reviewer Criterion 13 will FAIL the brief if this is missing or refers to a branch that does not locally resolve.
- Re-discovery (Phase 1) MUST compare the current state of `<iter_N_branch_name>` against the rubric (NOT against `main` / `<default_branch>`) when scoping remaining work. Iteration {N}'s changes are present on `<iter_N_branch_name>` but NOT on `main`.
- The full rubric is preserved above; this iteration must satisfy all items, including any not satisfied by iteration {N}.
- Out-of-order merge of stacked PRs corrupts the stack. Reviewers must merge iter 1 first, then iter 2, etc. The AUTONOMOUS_RUN summary's `iterations[]` array preserves the merge order.
```

The autonomous-loop main thread then also passes `--base-branch "<iter_N_branch_name>"` on the EXECUTE Supervisor invocation (see EXECUTE step 1 — "passthrough is the authoritative source"). If Launch Pad ignores the inline directive and saves a brief without the `Base Branch:` field, the CLI flag still wins; Plan Reviewer Criterion 13 also catches the missing-field case at Phase 5.5.

**`--no-stacked-branches` mode — `merge-and-continue` (verified):** the loop verifies the merge before re-planning, identical to v13 behavior. Use the v13 merge-and-continue refined-requirement template (below).

**If user picks `merge-and-continue`, the loop verifies the merge before re-planning.** The branch name comes from `SUPERVISOR_RESULT.branch` (an existing schema-1 field — see `docs/RESULT_SCHEMAS.md` §"SUPERVISOR_RESULT" for the field list); it was captured into `iterations[N].branch` during EXECUTE. The SHA is resolved from that branch name via `git rev-parse` on the **local** ref (not `origin/<branch>`, because we want the SHA the user pushed and we don't want a stale remote ref to hide the real tip):

> **Implementation note — `jq` is illustrative, not required.** The pseudocode below uses `jq` to extract `iterations[-1].branch` from `state.json` because it's the most concise way to write the example. In practice, **implementations should keep `current_brief_path` and the `iterations[].branch` values as in-memory state during the run**; reading state.json back at this point is wasteful and adds a `jq` (or equivalent JSON parser) dependency you don't need. The state.json writes are for persistence and future-recovery seed value (see "v1-only `_v1_note` field" later in this skill), NOT for intra-session lookups. Treat the `jq` line as a stand-in for "look up the most recent iteration's branch name from wherever your implementation stores it."

```bash
# PSEUDOCODE — see callout above. The `jq` extraction here illustrates
# the lookup; real implementations should use in-memory state.

# Read branch name from this iteration's recorded SUPERVISOR_RESULT
iter_N_branch="$(jq -r ".iterations[-1].branch" .supervisor/autonomous/${session_id}/state.json)"

# Resolve to a commit SHA — prefer the local ref the user pushed from
iter_N_branch_sha="$(git rev-parse "refs/heads/$iter_N_branch" 2>/dev/null \
                     || git rev-parse "origin/$iter_N_branch" 2>/dev/null)"
if [ -z "$iter_N_branch_sha" ]; then
  # Can't resolve a SHA for this branch at all. Treat merge as unverifiable —
  # do NOT auto-confirm. Re-prompt or fall through to gh-only verification.
  iter_N_branch_sha=""
fi

# Primary: gh CLI on the PR URL
merged=
state=$(gh pr view "$pr_url" --json state -q .state 2>/dev/null)
if [ "$state" = "MERGED" ]; then merged=true; fi

# Fallback: local ancestry check (only meaningful if we resolved a SHA)
if [ -z "$merged" ] && [ -n "$iter_N_branch_sha" ]; then
  default_branch=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo main)
  git fetch origin "$default_branch" 2>/dev/null
  if git merge-base --is-ancestor "$iter_N_branch_sha" "origin/$default_branch" 2>/dev/null; then merged=true; fi
fi

if [ -z "$merged" ]; then
  # Re-prompt user — don't proceed on premature click or unverifiable merge
  AskUserQuestion "PR #$X is not yet showing as merged (gh: ${state:-unknown}; local ancestry: $( [ -n "$iter_N_branch_sha" ] && echo "checked" || echo "branch SHA unresolvable" )). Refresh and pick merge-and-continue again, or pick stop-here / force-continue-anyway."
fi
```

**If both `gh` is unavailable AND `iter_N_branch_sha` is unresolvable** (e.g., the branch has been deleted locally and never fetched from origin), the loop cannot positively verify the merge — it re-prompts the user rather than proceeding. The user can re-run after fetching, choose stop-here, or use force-continue-anyway (which records the bypass in `policy_decisions` for audit).

The loop **never** advances to iteration N+1 on `merge-and-continue` until one of the two checks confirms merge. This prevents premature re-iteration from a user who clicked too early.

**If `merge-and-continue` (verified):** create refined requirement:

```
{session_id}-iter{N+1}.md
---
<original requirement body, including `## Outcomes Rubric` verbatim>

---

## Iteration Note (autonomous loop, auto-generated 2026-05-11T14:55:00Z)

Prior iteration {N} scored **{N/M}** on the Outcomes Rubric. PR #{X} (`<pr_url>`) was merged before this iteration started.

The full rubric is preserved above; the next iteration must satisfy all items, including any not satisfied by the previously merged PR. Launch Pad's re-discovery (Phase 1) should compare the current `<default_branch>` state against the rubric and scope the new brief around the remaining gaps.
```

Loop back to PLAN with this new requirement file. Record `policy_decisions` entry: `{iteration: N, phase: EVALUATE, decision: "user_picked_merge_and_continue", source: "autonomous_rubric_gate"}`.

**If `stop-here`:** summary status=done, record `rubric_final_score: N/M`, last_phase=EVALUATE. Exit.

**If `force-continue-anyway`:** create refined requirement as above; merge is NOT verified; record `policy_decisions` entry with `decision: "user_picked_force_continue_anyway"`, source same. Loop back to PLAN.

### Signal 2 — `status: failed` AND Option C triggered this iteration

**Iteration-scoping anchor — anchor by filename, not by global grep:**

The autonomous loop already knows `current_brief_path` (set during PLAN). When Supervisor picks Option C, it moves the brief from `.supervisor/jobs/in-progress/` to `.supervisor/jobs/failed/` (per `agents/supervisor.md` Phase 3 adjudication-Option-C handler and `FAILURE_ESCALATION.md` §"Inter-Subtask Gap / Scope Expansion" Option C flow). So **the unambiguous current-iteration anchor is `.supervisor/jobs/failed/{basename(current_brief_path)}` existence**. Prior runs have different brief filenames (different date / session_id / slug), so this filename uniquely identifies this iteration's failed brief.

**Why not `grep "inter_subtask_gap" .supervisor/state.md` directly:** state.md is per-Supervisor-session and Context-Keeper rewrites it atomically (`agents/context-keeper.md:15`). A global grep MIGHT be naturally scoped, but the filename anchor is more robust against pathological cases (state.md not yet updated, concurrent inconsistency, etc.).

**Detection algorithm (after Supervisor returns `status: failed`):**

The pseudocode below is implementation-illustrative, not literally runnable bash. `EXIT_TO_DEFAULT_TERMINATION` is a structured-flow marker — a real implementation uses a function return, state-machine transition, or labeled break. The `RESULT_*` placeholders represent fields already extracted from the captured `SUPERVISOR_RESULT` block (see EXECUTE step 4); they are not shell environment variables and do not need to be exported.

```text
# Inputs available at this point:
#   current_brief_path           -- recorded in PLAN
#   RESULT_ERROR                 -- value of SUPERVISOR_RESULT.error   (string|null)
#   RESULT_SUMMARY               -- value of SUPERVISOR_RESULT.summary (string)
#
# Output:
#   gap_detected                 -- boolean; true = Signal 2 (Option C) fired

failed_path = ".supervisor/jobs/failed/" + basename(current_brief_path)

if not file_exists(failed_path):
    # Supervisor failed for some reason that didn't move this iteration's
    # brief to failed/ — merge conflict, env blocker, hard error before
    # adjudication, or any other crash path. NOT an Option C trigger.
    EXIT_TO_DEFAULT_TERMINATION   # see "Default termination" branch below

# Brief was marked failed. Check three iteration-scoped sources for
# the grep-stable substring "inter_subtask_gap" (any match = Option C).
# By load-bearing weight:
#   (b) SUPERVISOR_RESULT.error    -- PRIMARY signal. The gap reason is
#       Supervisor's own output, emitted by this iteration's
#       SUPERVISOR_RESULT block. This is where the string is reliably
#       present on Option C.
#   (c) SUPERVISOR_RESULT.summary  -- PRIMARY signal. Same Supervisor
#       block; the summary often reiterates the abort reason.
#   (a) the failed brief's contents -- BELT-AND-SUSPENDERS only. The
#       brief is a Launch Pad product (subtask specs, AC, rubric);
#       Supervisor moves the file to failed/ on Option C but in
#       current Supervisor versions does NOT necessarily append the
#       gap reason to the brief body. Keep this check in case a
#       future Supervisor version annotates the failed brief (a
#       reasonable hardening), but do not rely on it in v1 — sources
#       (b) and (c) are the real anchors.
#
# Filename is session_id-tagged so no other run can share it,
# eliminating cross-run false positives.
#
# .supervisor/state.md is intentionally NOT consulted — Context-Keeper
# rewrites it atomically (skills/state-management/SKILL.md), and pre-
# rewrite stale content from a prior session could survive briefly,
# producing a false positive. The three sources above are all inherently
# scoped to this iteration.
gap_detected = (
    file_contains_substring(failed_path,  "inter_subtask_gap")
 or string_contains_substring(RESULT_ERROR,   "inter_subtask_gap")
 or string_contains_substring(RESULT_SUMMARY, "inter_subtask_gap")
)

if not gap_detected:
    # Failed brief exists but no gap signal — Supervisor failed AND moved
    # the brief to failed/ for some non-Option-C reason.
    EXIT_TO_DEFAULT_TERMINATION   # see "Default termination" branch below

# Signal 2 fired. Continue with Option-C re-plan.
```

If `gap_detected=true`: Option C was the trigger. **No merge prompt** — the job was abandoned, no PR was created.

Create refined requirement:

```
{session_id}-iter{N+1}.md
---
<original requirement body, including `## Outcomes Rubric` verbatim (if one was authored/frozen)>

---

## Iteration Note (autonomous loop, auto-generated <timestamp>)

Prior iteration {N} was abandoned via adjudication Option C ("Exit to Launch Pad") due to inter-subtask gap. (The "original requirement body" copied above is the current `<requirement_path>` file body, which carries the frozen `## Outcomes Rubric` verbatim if one was authored — same as the Signal-1 templates.) The brief at `<current_brief_path>` had unresolvable producer-consumer mismatches that required re-planning from scratch.

The new iteration should re-discover dependencies and produce a fresh Subtask Structure with stricter `provides` / `requires` contracts.

(Note for Launch Pad re-discovery: the failed brief is preserved at `<failed_path>` for reference if helpful.)
```

Loop back to PLAN with this new requirement file. Record `policy_decisions` entry: `{iteration: N, phase: EVALUATE, decision: "supervisor_option_c_detected", source: "supervisor_adjudication"}`. **Note:** unlike the other entries in `policy_decisions` that capture a user choice at a *loop-level* `AskUserQuestion` gate, this one is **inferred by the loop from filesystem evidence** after Supervisor's own adjudication AskUserQuestion concluded inside Supervisor's session. The `_detected` suffix is a deliberate naming convention to flag this distinction for future tooling that parses `policy_decisions`.

### No-rubric gate (v14.0.0+ — `status: completed` AND `rubric_score` is null)

When the iteration's brief had no `## Outcomes Rubric` AND multi-iter is active, the loop fires the no-rubric gate. In v13 this case silently terminated as `done`; in v14 the gate makes the decision explicit because multi-iter without a rubric is the common shape of refactor / cleanup goals where the user genuinely wants to keep iterating.

**AC-5 webhook gate POST first (when `--notify` set):**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/send-webhook.sh" \
  --event-type gate \
  --gate-type no_rubric \
  --iteration "$iteration" \
  --session-id "$session_id" \
  --context "iter $iteration completed PR $pr_url without rubric; awaiting continue/stop decision" &
```

Then `AskUserQuestion`:

> *"Iteration {N} completed with PR #{X}. The brief had no `## Outcomes Rubric`, so there is no per-item score to evaluate. Continue to iteration {N+1} (re-plan to refine or extend), or stop here? Options:*
> - *(a) continue (loop to PLAN with a refined-requirement note appended),*
> - *(b) stop (accept and exit with `status: done`)."*

**Non-interactive fallback:** when `--non-interactive-fallback` is set AND no TTY, the gate exits with `status: done, status_reason: "no_rubric_in_non_interactive"`. The loop accepts the iteration cleanly (does NOT abort) — without a rubric there is no quality signal to gate against, so continuing in CI would be busywork. This is the explicit non-failure exit; the rubric-gate, by contrast, fails closed because a rubric signal IS available and silently dropping it is unsafe.

**`continue`:** create refined requirement (same template shape as Signal 1's, minus the rubric reference), loop to PLAN. Record `policy_decisions` entry: `{iteration: N, phase: EVALUATE, decision: "user_continued_no_rubric", source: "autonomous_no_rubric_gate"}`.

**`stop`:** emit AUTONOMOUS_RUN.status=done, status_reason="user_stopped_at_no_rubric_gate", exit.

### Default termination — any other SUPERVISOR_RESULT outcome ends the loop

Not a re-planning signal — this is the catch-all branch when neither Signal 1 nor Signal 2 nor the no-rubric gate fires. The loop emits the AUTONOMOUS_RUN summary and exits:

| `SUPERVISOR_RESULT.status` | Other condition | Loop action | summary status | status_reason |
|---|---|---|---|---|
| `completed` | rubric_score = `N/N` (perfect score) | terminate | `done` | null |
| `completed` | rubric_score = `N/M` with N<M, user picks `stop-here` at rubric gate | terminate | `done` | `user_stopped_at_rubric_gate` |
| `completed` | rubric_score is null, user picks `stop` at no-rubric gate | terminate | `done` | `user_stopped_at_no_rubric_gate` |
| `completed` | rubric_score is null, non-interactive fallback | terminate | `done` | `no_rubric_in_non_interactive` |
| `completed_with_escalation` | any | terminate; populate `escalations_seen` | `done` | null (caveat in escalations_seen) |
| `failed` | `pr_url == null` (Supervisor pre-PR failure, AC-15) | terminate | `failed` | `supervisor_failed_other` |
| `failed` | inter_subtask_gap NOT detected, `pr_url` non-null | terminate | `failed` | `supervisor_failed_other` |
| `failed` | `base_branch_mismatch` from Supervisor Phase 4.5 cleanup (S3-added path) | terminate | `failed` | `supervisor_base_branch_mismatch` |
| `failed` | `error`/`status_reason` = `preflight_overlap_detected` (Supervisor Phase 1.5 pre-flight fail-closed abort — CI / non-TTY OVERLAP or SUPERSEDED) | terminate (loop stops; do NOT re-iterate) | `failed` | `preflight_overlap_detected` |
| `checkpoint` | any | terminate (no auto-resume in v1) | `aborted` | `supervisor_checkpoint` |

### Phase 1.5 pre-flight gate — CI fail-closed termination (v14.8.0+)

Supervisor's Phase 1.5 PRE-FLIGHT SYNC gate runs *after* task acquisition (Phase 1 ACQUIRE) and *before* Phase 2 PLAN spawns the Orchestrator or any worker. It fetches remote state, inspects recent `origin/$BASE_BRANCH` commits and open PRs, and classifies the requested work as `CLEAR | OVERLAP | SUPERSEDED`. The autonomous loop interacts with that gate only through `SUPERVISOR_RESULT`:

- **CI fail-closed behavior.** When the inlined `/supervisor` invocation runs under `--non-interactive` (auto-forwarded by the loop's `--non-interactive-fallback` policy — see EXECUTE step 1, "Auto-forwarded flags") or a non-TTY session, an `OVERLAP` or `SUPERSEDED` pre-flight classification cannot be escalated interactively. Supervisor therefore fails closed: it aborts with `SUPERVISOR_RESULT.status: failed` and `error`/`status_reason` = `preflight_overlap_detected`, rather than silently spending tokens on decomposition and execution. The loop maps that outcome to `terminate` (see the Default-termination table row above) and surfaces it as `AUTONOMOUS_RUN.status_reason: "preflight_overlap_detected"`. This is a terminal outcome — the loop does **not** re-iterate, because the overlap is a precondition violation the user must resolve (revise scope, or re-run with Supervisor's `--skip-preflight-sync` escape hatch), not a quality signal the next iteration could improve on.
  - **Flag-forwarding note:** the loop forwards ONLY `--non-interactive` to the inlined `/supervisor` (see "Auto-forwarded flags" above); it does **not** forward `--skip-preflight-sync` (same as `--cheap` — unknown flags are not passed through). The Phase 1.5 gate therefore runs in **every** autonomous iteration. To deliberately skip it, run `/supervisor --skip-preflight-sync` manually for a one-off requirement.

- **Complements — does NOT double-fire with — EVALUATE PR-base verification + stacked `--base-branch` passthrough.** The Phase 1.5 pre-flight gate and the loop's existing EVALUATE PR-base verification (see "EVALUATE PR-base verification") cover **different failure modes at different points in the lifecycle** and never overlap:
  - The **pre-flight gate** verifies *work overlap before* decomposition/execution — it inspects whether the requested *work* intersects recent commits / open PRs on `$BASE_BRANCH` (same-file overlap or an already-merged equivalent), and fires *between Phase 1 and Phase 2*, before any worker is spawned.
  - The **EVALUATE PR-base check** verifies the *PR `baseRefName` after* FINALIZE — it confirms that iter N+1's stacked PR was actually opened against `iterations[N].branch` (the value the `--base-branch` passthrough sent in), and fires *after* Supervisor returns `SUPERVISOR_RESULT` with a `pr_url`.

  Because the pre-flight gate scopes its overlap scan to `$BASE_BRANCH` (AC6) it does **not** flag the stacked parent iteration's own commits/PR as overlap, so a stacked-mode multi-iter run does not trip the gate on its own chain. The `preflight_overlap_detected` and `iter_pr_base_mismatch` / `supervisor_base_branch_mismatch` status reasons are therefore mutually exclusive in practice — distinct gates, distinct timing, distinct `status_reason` values.

### Max-iterations cap

If signal 1 or 2 would re-plan AND `iteration + 1 > max_iterations`: terminate with summary status=`paused_max_iterations`, status_reason=`max_iterations_reached`. Record the unprocessed iteration intent in policy_decisions for audit.

## DONE — AUTONOMOUS_RUN Summary

Written to `.supervisor/autonomous/{session_id}/summary.md` (markdown for users) and `.supervisor/autonomous/{session_id}/state.json` (machine-readable sidecar). Echoed to main-thread output.

**Canonical schema:** see `loomwright/docs/RESULT_SCHEMAS.md` § "AUTONOMOUS_RUN" for the formal `schema_version: 2` definition, the closed `status_reason` enum, validation rules, and a worked example. This skill describes the protocol that produces an `AUTONOMOUS_RUN` block; the schema doc is the source of truth for its shape.

The status enum is **autonomous-layer-only**: `done | paused_max_iterations | aborted | failed`. None of these values appear in `SUPERVISOR_RESULT.status` (which is `completed | completed_with_escalation | failed | checkpoint`). The two enums are intentionally distinct to prevent confusion and to keep the AUTONOMOUS_RUN summary out of scope for the Supervisor SubagentStop hook (which validates SUPERVISOR_RESULT, not AUTONOMOUS_RUN).

### summary.md format

```markdown
# Autonomous Run Summary

- **session_id:** auto-2026-05-11-143022
- **requirement_path:** `.supervisor/requirements/auto-2026-05-11-143022-add-jwt-auth.md`
- **mode:** single | multi
- **allow_multi_iteration:** true | false
- **max_iterations:** integer ≥ 1 (`1` for single-iteration runs — the implicit cap; the configured value for multi-iteration runs, default 3)
- **status:** done | paused_max_iterations | aborted | failed
- **status_reason:** null | "max_iterations_reached" | "user_discarded_at_phase_6" | "user_aborted_at_no_go" | "user_aborted_at_plan_review_fail" | "user_stopped_at_rubric_gate" | "user_stopped_at_no_rubric_gate" | "supervisor_checkpoint" | "supervisor_failed_other" | "supervisor_base_branch_mismatch" | "rubric_dropped_from_brief" | "concurrent_session_detected" | "invalid_max_iterations" | "non_interactive_without_fallback" | "conflicting_mode_flags" | "iter_pr_base_mismatch" | "rubric_gate_closed_non_interactive" | "no_rubric_in_non_interactive" | "user_aborted_gh_retry" | "preflight_overlap_detected"
- **total_iterations:** 2
- **last_phase:** DONE | EVALUATE | PLAN | EXECUTE
- **started_at:** 2026-05-11T14:30:22Z
- **ended_at:** 2026-05-11T14:54:11Z
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

Same fields as summary.md, structured as JSON. v1 writes it for two purposes: (a) intra-session convenience reads by the loop itself (the merge-verification step reads `iterations[-1].branch` from this file — see Signal 1 pseudocode above), and (b) seeding future Doc 4 state.json sidecar work. v1 explicitly does NOT use it for cross-session resume (no `--continue` flag exists), and no SubagentStop hook validates it. The file is **not authoritative for resume / recovery / cross-session state**.

**v1-only `_v1_note` field:** every state.json this loop writes begins with a `_v1_note` string field (see the schema example earlier in this skill). The field's contents explicitly mark the file as **advisory-only** in v1 and warn tooling against treating it as authoritative. The presence of `_v1_note` IS the v1 contract signal. A future v2 plan that defines a stable resume contract will remove this field; tooling that finds `_v1_note` MUST refuse to use the file for **resume / recovery / cross-session state** queries until a v2-compatible state.json (without `_v1_note`) is observed. The intent is to make accidental dependence on v1's advisory state impossible to do silently. **Carve-out exception:** the two top-level **ACQUIRE signals** `current_branch` + `current_status` are deterministic hook-readable fields (see §"state.json ACQUIRE signals (hook-readable — carve-out from the advisory-only rule)" earlier in this skill) — the `hook-dispatch-on-pr-create.sh` session-disambiguation read of those two fields is explicitly permitted even while `_v1_note` is present; the advisory-only / not-for-resume rule still governs the rest of the file.

## Concurrency / Single-Session Assumption

**Concurrent-session safety (v14.2.0+).** Brief-save detection now reads `LAUNCH_PAD_RESULT.saved_brief_path` as the primary signal (see PLAN phase §"Brief-save detection — primary path"), so a concurrent `/launch-pad` invocation writing to the same `.supervisor/jobs/pending/` cannot be mistaken for this loop's save — Launch Pad emits exactly one result block per invocation, and the loop only consults the result block from the Launch Pad call it inlined. The `ls`-diff fallback retains the v1 single-session-only constraint and is used only when the result block is absent (pre-v14.2.0 plugin or transcript-scan failure). Session-id-tagged filenames in `.supervisor/requirements/` and `.supervisor/autonomous/{session_id}/` continue to isolate the loop's own state.

## Failure Modes & Recovery

| Failure | Detection | Recovery |
|---|---|---|
| User discards at Phase 6 | `new_briefs` empty after Phase 6 | Clean exit, summary status=aborted |
| Launch Pad ignores rubric-preservation inline instruction | `has_rubric "$current_brief_path"` returns absent (no real rubric in the saved brief) | Loop aborts with `status: aborted, status_reason: "rubric_dropped_from_brief"` (no iteration reaches EXECUTE; `total_iterations: 0`, `iterations: []`). **Cleanup required before re-running:** the abort fires *after* Launch Pad's Phase 6 save, so the saved brief is still sitting in `.supervisor/jobs/pending/` (filename starts with this run's `session_id`). The user must move or delete the stale brief before re-running `/autonomous`, otherwise the next run's brief-save `ls`-diff will see it as a "new" file and either pick it up by accident or trip `concurrent_session_detected`. One-liner: `mv .supervisor/jobs/pending/<this-session-id>-*.md .supervisor/jobs/failed/`. **Recovery paths:** re-run without `--allow-multi-iteration` (single-iteration ignores the rubric-preservation gate entirely), or pre-author the brief by hand with the rubric included. |
| Concurrent autonomous run or manual launch-pad | `new_briefs` has >1 entry after Phase 6 | Abort with status_reason="concurrent_session_detected" |
| Session terminated mid-loop | Process killed, terminal closed, machine restart | **v1: unsupported.** User must clean up `.supervisor/jobs/in-progress/`, close abandoned PRs, restart with `/autonomous`. Resume contract is its own plan (depends on Doc 4 state.json sidecar). |
| `gh` unavailable for merge check | `gh pr view` returns non-zero | Fallback to `git merge-base --is-ancestor`; if neither confirms, re-prompt user |
| `inter_subtask_gap` string drift (FAILURE_ESCALATION.md changes the grep-stable string) | Signal 2 detection silently fails | Loop falls through to the default-termination branch with `status_reason=supervisor_failed_other`; user inspects failed brief and re-runs. Promotion to typed enum is future work. |

## Hard Reuse Contract (no source changes)

- **Launch Pad inline workflow:** referenced via Step 0 + PLAN invocation. One inline instruction added (rubric preservation), delivered through the inlined prompt, not a Launch Pad source change.
- **Supervisor inline workflow:** referenced via Step 0 + EXECUTE invocation. No instruction modifications.
- **Adjudication 4-option escalation:** Supervisor surfaces existing options A/B/C/D via AskUserQuestion. The autonomous loop never auto-picks. Option C produces `failed + inter_subtask_gap` — the `inter_subtask_gap` substring is documented as grep-stable in `FAILURE_ESCALATION.md` §"Inter-Subtask Gap / Scope Expansion" (the doc explicitly promises grep-stability for telemetry / state.md consumers).
- **SUPERVISOR_RESULT schema (v12.2):** v1 reads existing fields only — `status`, `pr_url`, `error`, `summary`, `rubric_score`, `branch`. No schema change. `reason` does not exist on the block; v1 reads gap context from `SUPERVISOR_RESULT.error` / `SUPERVISOR_RESULT.summary` and from the failed brief's contents (see Signal 2 detection algorithm above).
- **`.supervisor/jobs/` lifecycle:** Supervisor remains sole writer/mover. The autonomous loop only reads `pending/` (for brief-save detection) and `failed/` (for Option-C anchor check).
- **`.supervisor/state.md`:** writer is **path-dependent**, not unconditionally Context-Keeper. On the **parallel path** Context-Keeper remains the **sole writer** per `agents/context-keeper.md`. On the **inline path** — which is how `/autonomous` runs `/supervisor` (Step 0 inlines `commands/supervisor.md`; **no Context-Keeper is spawned**) — the inline Supervisor writes `.supervisor/state.md` **directly** (Phase 1 ACQUIRE writes the canonical lowercase `## Session` block with `- status: running` / `- branch: <feature-branch>`; the Phase 4.5 completion tail flips `- status:` to `completed`/`completed_with_escalation`), per `commands/supervisor.md` §"Inline-path canonical state writes". The Context-Keeper write is the sole writer on the PARALLEL path and a harmless **idempotent overlap** when both apply — it does NOT contradict the inline-path direct write. (Scope guard: this clarifies the autonomous-loop cross-link only; the genuinely-correct parallel-path "sole writer" contract in `agents/context-keeper.md` and `skills/state-management/SKILL.md` is unchanged.) Separately, the autonomous loop **does not** grep state.md for `inter_subtask_gap` — Signal 2 detection uses only the three iteration-scoped sources (failed-brief contents, `SUPERVISOR_RESULT.error`, `SUPERVISOR_RESULT.summary`) to avoid any false-positive risk from pre-rewrite stale content.

## Cross-References

- `${CLAUDE_PLUGIN_ROOT}/commands/launch-pad.md` — inline workflow Step 0 loads at runtime
- `${CLAUDE_PLUGIN_ROOT}/commands/supervisor.md` — inline workflow Step 0 loads at runtime; v14 `--base-branch` + `--non-interactive` flags surface here
- `${CLAUDE_PLUGIN_ROOT}/skills/autonomous-loop/SKILL.md` — this skill; Step 0 loads at runtime
- `${CLAUDE_PLUGIN_ROOT}/skills/review-heal/SKILL.md` — authority for the chained EVALUATE review-heal step (entry sense (b): Task-spawned step with fresh isolated context, NOT a nested `claude` process; emits `REVIEW_HEAL_RESULT`)
- `${CLAUDE_PLUGIN_ROOT}/scripts/send-webhook.sh` — `--event-type gate` path used by every gate-firing site when `--notify` is set
- `loomwright/agents/supervisor.md` — Phase 0 preamble (clear_flag base_mismatch_detected + non_interactive), Phase 4 self-verify, Phase 4.5 base-mismatch cleanup; SUPERVISOR_RESULT now optionally carries `branch_base` and `pr_state`
- `loomwright/agents/context-keeper.md` — `set_flag` / `get_flag` / `clear_flag` operations consumed by Supervisor's Phase 0/4/4.5 cycle
- `loomwright/docs/RESULT_SCHEMAS.md` § "AUTONOMOUS_RUN" — canonical schema (v14 bumps to `schema_version: 2` adding the new closed `status_reason` values listed above)
- `loomwright/docs/FAILURE_ESCALATION.md` §"Inter-Subtask Gap / Scope Expansion" — adjudication 4 options and the `inter_subtask_gap` grep-stable string (documented as grep-stable for telemetry / `state.md` consumers, and re-used here as Signal 2's substring anchor)
- `loomwright/docs/RESULT_SCHEMAS.md` — `SUPERVISOR_RESULT` schema including `rubric_score`
- `loomwright/skills/supervisor-readiness/SKILL.md` — brief format the autonomous loop relies on Launch Pad to produce
- `loomwright/skills/state-management/SKILL.md` — atomic-rewrite semantics of `.supervisor/state.md`
- `loomwright/agents/context-keeper.md` — sole-writer contract for state.md
- `loomwright/agents/supervisor.md` §"Phase 3 — Adjudication" / Option C handler — file-move behavior (brief moves from `in-progress/` to `failed/` when Option C is selected; reason `inter_subtask_gap` recorded in state.md)
