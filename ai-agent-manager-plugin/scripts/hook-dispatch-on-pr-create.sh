#!/usr/bin/env bash
# hook-dispatch-on-pr-create.sh — PostToolUse[Bash] BACKSTOP for the
# until-mergeable review drain on PR creation (Subtask 1b).
#
# INVARIANT: ALWAYS exits 0. This is a PostToolUse[Bash] hook — it MUST NEVER
# break, slow, or fail the originating Bash tool call. Every failure mode
# (empty/malformed payload, missing jq, no PR URL, gate-fail, dispatcher error)
# is absorbed: log at most one stderr line and exit 0. Mirrors the fail-safe
# wrapper pattern of send-telemetry.sh / send-webhook.sh.
#
# WHY THIS HOOK EXISTS
# --------------------
# The until-mergeable review drain (v14.32.0 / PR #65) is triggered today ONLY by
# Supervisor Phase 4.5 prompt step 5.5 — agent-prompt logic, not a hook. On the
# inline /autonomous|/supervisor path the Supervisor IS the main thread (not a
# subagent), so SubagentStop(supervisor-runner) never fires either, and if the
# agent doesn't execute step 5.5 the drain silently never dispatches. This hook
# fires on the actual `gh pr create` Bash tool call — the agent cannot "forget"
# it — and backstops the dispatch so it runs even when step 5.5 is skipped.
#
# WHY THE SESSION-SCOPE GATE CONSUMES EXISTING DURABLE LIFECYCLE STATE
# -------------------------------------------------------------------
# A naive PostToolUse[Bash] hook fires on ANY `gh pr create` in ANY repo, which
# would hijack unrelated manual PRs. The gate must distinguish a plugin-driven
# PR from a user's hand-rolled one. It does so by consuming state the CORE
# Supervisor lifecycle ALREADY writes durably and unskippably — the feature
# branch, .supervisor/state.md, and the in-progress/ job-file move (all core
# Phase 1 ACQUIRE writes). It deliberately does NOT consume a new prompt-written
# marker: a marker written by a prompt step would reintroduce the very step-5.5
# prompt-skip fragility this hook exists to fix (the agent could skip the
# marker-write just as it skipped step 5.5). Producer = the existing Supervisor
# lifecycle; consumer = this wrapper. No new producer code is introduced.
#
# A bare non-empty .supervisor/jobs/in-progress/ is NOT sufficient. After that
# cheap necessary pre-condition (gate (i)), authorization is resolved from ONE
# COHERENT SOURCE, in order:
#
#   Source 1 — .supervisor/state.md: authorizes ONLY when its status word is
#     NON-terminal (NOT completed/completed_with_escalation/failed) AND its branch
#     line is present AND equals the current branch. FORMAT-TOLERANT: both the
#     canonical lowercase (`- status:`/`- branch:`) and the inline-Supervisor bold
#     (`- **Status:**`/`- **Branch:**`) forms are parsed. CRITICAL: a state.md that
#     is terminal OR branch-absent OR branch-mismatched is simply "NOT the active
#     source" — it does NOT skip dispatch; control FALLS THROUGH to Source 2. This
#     is the headline AC5 change: a stale terminal state.md left by a PRIOR session
#     (this repo routinely leaves `- status: completed`) must no longer short-circuit
#     ahead of the state.json fallback.
#
#   Source 2 — autonomous state.json fallback (only if Source 1 did not authorize):
#     enumerate .supervisor/autonomous/*/state.json and authorize ONLY when EXACTLY
#     ONE file matches ALL of: .current_branch == current branch; .ended_at null/
#     absent; .current_status present AND non-terminal (terminal set: completed|
#     completed_with_escalation|failed|aborted|done|paused_max_iterations — absent
#     current_status fails closed); and basename(.current_brief_path) exists under
#     .supervisor/jobs/in-progress/. Zero or >1 matches → not authorized.
#
# Otherwise FAIL CLOSED — log one line + exit 0, no dispatch. The session branch
# ALWAYS comes from a positive plugin-written source (state.md `- branch:` or
# state.json `current_branch`); there is NO current-git-branch positive fallback
# for the session branch (preserving the #67/#70 anti-hijack posture: an
# unconfirmable PR is never dispatched against).
#
# DOCUMENTED LIMITATION
# ---------------------
# This hook covers PR creation via `gh pr create` through the Bash tool only
# (the plugin's only PR-creation path). For any other PR-creation mechanism
# (e.g. an MCP tool), Supervisor step 5.5 remains the in-context dispatch path.
# The PR-URL match is github.com-only (the regex anchors on
# `https://github.com/.../pull/<n>`), so GitHub Enterprise custom domains are
# NOT recognized and the backstop will not fire there — step 5.5 remains the
# dispatch path on GHE.

set -u
# Intentionally NO `set -e` / pipefail — a PostToolUse hook must absorb every
# child failure and never propagate a non-zero exit to the originating tool call.

log() { printf 'hook-dispatch-on-pr-create: %s\n' "$1" >&2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISPATCHER="$SCRIPT_DIR/dispatch-pr-review.sh"

# ---- Read stdin (the PostToolUse payload) -----------------------------------
INPUT="$(cat 2>/dev/null || true)"
if [ -z "$INPUT" ]; then
  log "empty payload — nothing to do"
  exit 0
fi

# ---- Require jq (AC6) -------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  log "jq not found — skipping"
  exit 0
fi

# ---- Defensive: extract tool_name AND command in a SINGLE jq fork (AC6) -----
# Runs on EVERY Bash tool call, so fork jq ONCE for both fields. @tsv escapes
# embedded tabs/newlines so a multiline command can't split the fields. Malformed
# JSON yields empty META → TOOL_NAME="" (!= "Bash") → exit 0 (fail-safe).
META="$(printf '%s' "$INPUT" | jq -r '[(.tool_name // ""), (.tool_input.command // "")] | @tsv' 2>/dev/null || true)"
TOOL_NAME="${META%%$'\t'*}"
CMD="${META#*$'\t'}"
if [ "$TOOL_NAME" != "Bash" ]; then
  # Not a Bash tool call (or malformed JSON yielding empty) — no-op.
  exit 0
fi

# ---- Most-selective filter FIRST: confirm the command is a `gh pr create` ----
# matcher:"Bash" fires on EVERY Bash tool call, so short-circuit the
# overwhelmingly common non-PR Bash call with one jq BEFORE the response-text
# extraction + URL grep. This also tightens the session gate's false-positive
# surface: a mid-session `gh pr view`/`gh pr list`/`git log` that merely PRINTS
# a /pull/<n> URL cannot reach the dispatch path. Matches the documented scope:
# `gh pr create` via the Bash tool. (CMD was extracted above alongside TOOL_NAME.)
case "$CMD" in
  *"pr create"*) : ;;  # a PR-creation command — proceed
  *)
    # Not a PR-creation command (the common case) — no-op.
    exit 0
    ;;
esac

# ---- Extract the tool response text (stdout + stderr) -----------------------
RESP="$(printf '%s' "$INPUT" | jq -r '(.tool_response.stdout // "") + "\n" + (.tool_response.stderr // "")' 2>/dev/null || true)"
if [ -z "$RESP" ]; then
  # jq failed or no response text — nothing to scan.
  exit 0
fi

# ---- Extract a PR URL from the response (AC2: no URL → not a PR creation) ---
# Even for a `gh pr create`, require the PR URL in the response before dispatch.
PR_URL="$(printf '%s' "$RESP" | grep -oE 'https://github\.com/[^/[:space:]]+/[^/[:space:]]+/pull/[0-9]+' | head -1 || true)"
if [ -z "$PR_URL" ]; then
  # No PR URL in the response — the create did not surface a PR URL.
  exit 0
fi

# ---- SESSION-SCOPE GATE (AC5) ----------------------------------------------
# Dispatch ONLY when gate (i) holds AND authorization is established from ONE
# coherent source (state.md active-source OR a UNIQUE autonomous state.json).
# Otherwise log one line + exit 0.

# (i) .supervisor/jobs/in-progress/ is NON-EMPTY (cleared on completion).
#     Cheap necessary pre-condition.
if ! { [ -d .supervisor/jobs/in-progress ] && [ -n "$(ls -A .supervisor/jobs/in-progress 2>/dev/null)" ]; }; then
  log "no in-progress job — not an active plugin run; skipping dispatch"
  exit 0
fi

# Current branch comes from the env seam (TEST SEAM) falling back to the live
# git branch. NOTE: this is the CURRENT branch only — the SESSION branch is never
# derived from it; the session branch must come from a positive plugin-written
# source (state.md `- branch:` or state.json `current_branch`). This preserves the
# #67/#70 anti-hijack posture: an unconfirmable session ⇒ fail closed.
current_branch="${AI_AGENT_MANAGER_HOOK_CURRENT_BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)}"

# Terminal-status set, exactly (shared by both sources):
#   completed | completed_with_escalation | failed | aborted | done | paused_max_iterations
# A status outside this set is a POSITIVE non-terminal active status.

authorized=0

# ---- Source 1: .supervisor/state.md ----------------------------------------
# Authorize via state.md ONLY when its status word is PRESENT and NON-terminal AND
# its branch line is present AND equals the current branch. FORMAT-TOLERANT: both canonical
# lowercase (`- status:`/`- branch:`) and inline-Supervisor bold
# (`- **Status:**`/`- **Branch:**`) forms are parsed.
#
# CRITICAL (AC5 headline change): if state.md is terminal OR its branch is
# absent/mismatched, state.md is simply NOT the active source — control FALLS
# THROUGH to Source 2. It does NOT exit 0 here. (A stale terminal state.md left by
# a prior session must not short-circuit ahead of the state.json fallback.)
if [ -f .supervisor/state.md ]; then
  # Strip bold `**` markers FIRST so both forms collapse to a bare key, then strip
  # the key + leading whitespace and take the status word.
  s1_status="$(grep -m1 -iE '^- (\*\*)?status:' .supervisor/state.md 2>/dev/null \
    | sed -E 's/\*\*//g' \
    | sed -E 's/^- [Ss][Tt][Aa][Tt][Uu][Ss]:[[:space:]]*//' \
    | awk '{print $1}' || true)"
  s1_branch="$(grep -m1 -iE '^- (\*\*)?branch:' .supervisor/state.md 2>/dev/null \
    | sed -E 's/\*\*//g' \
    | sed -E 's/^- [Bb][Rr][Aa][Nn][Cc][Hh]:[[:space:]]*//' \
    | sed -E 's/[[:space:]]+$//' || true)"
  s1_terminal=0
  # The terminal set is the shared 6-member superset; state.md itself only ever
  # carries running|paused|completed|completed_with_escalation|failed (the last
  # three terminal). The extra autonomous-layer values (aborted|done|
  # paused_max_iterations) never appear in state.md, so including them is a
  # harmless DRY superset, not a claim that state.md can carry them.
  case "$s1_status" in
    completed|completed_with_escalation|failed|aborted|done|paused_max_iterations)
      s1_terminal=1 ;;
  esac
  # Require a PRESENT, non-terminal status (an absent/blank `- status:` line yields
  # an empty s1_status — which is NOT a positive non-terminal signal, so it must
  # NOT authorize; control falls through to Source 2). This mirrors Source 2's
  # `[ -n "$sj_status" ]` status-presence guard and the AC5 "non-terminal status"
  # contract. The earlier revision authorized on a branch-only/status-less state.md.
  if [ -n "$s1_status" ] && [ "$s1_terminal" -eq 0 ] && [ -n "$s1_branch" ] && [ "$s1_branch" = "$current_branch" ]; then
    authorized=1
  fi
fi

# ---- Source 2: autonomous state.json fallback ------------------------------
# Only consulted if Source 1 did NOT authorize. Enumerate
# .supervisor/autonomous/*/state.json; count files matching ALL of:
#   1. .current_branch present AND == current_branch
#   2. .ended_at null/absent (present ended_at ⇒ terminal ⇒ excluded)
#   3. .current_status present AND NOT in the terminal set (absent ⇒ NOT authorized)
#   4. basename(.current_brief_path) exists under .supervisor/jobs/in-progress/
# Authorize ONLY when EXACTLY ONE file matches. Each jq parse is `|| true` so a
# malformed/missing file is skipped, never errors.
if [ "$authorized" -eq 0 ] && [ -d .supervisor/autonomous ]; then
  match_count=0
  for sj in .supervisor/autonomous/*/state.json; do
    [ -f "$sj" ] || continue
    # Single jq fork per file: emit branch, ended_at-is-null flag, status, and
    # brief basename as tab-separated fields. Malformed JSON → empty META → skip.
    sjmeta="$(jq -r '[(.current_branch // ""), (if (.ended_at == null) then "1" else "0" end), (.current_status // ""), ((.current_brief_path // "") | split("/") | last)] | @tsv' "$sj" 2>/dev/null || true)"
    [ -n "$sjmeta" ] || continue
    sj_branch="$(printf '%s' "$sjmeta" | cut -f1)"
    sj_ended_null="$(printf '%s' "$sjmeta" | cut -f2)"
    sj_status="$(printf '%s' "$sjmeta" | cut -f3)"
    sj_brief="$(printf '%s' "$sjmeta" | cut -f4)"
    # 1. branch present and matches
    [ -n "$sj_branch" ] && [ "$sj_branch" = "$current_branch" ] || continue
    # 2. ended_at null/absent
    [ "$sj_ended_null" = "1" ] || continue
    # 3. current_status present and non-terminal (absent ⇒ fail closed)
    [ -n "$sj_status" ] || continue
    case "$sj_status" in
      completed|completed_with_escalation|failed|aborted|done|paused_max_iterations) continue ;;
    esac
    # 4. brief basename present in jobs/in-progress/
    [ -n "$sj_brief" ] && [ -f ".supervisor/jobs/in-progress/$sj_brief" ] || continue
    match_count=$((match_count + 1))
  done
  if [ "$match_count" -eq 1 ]; then
    authorized=1
  elif [ "$match_count" -gt 1 ]; then
    log "ambiguous: $match_count active autonomous sessions match current branch '$current_branch' — fail-closed; skipping dispatch"
  fi
fi

# ---- Fail closed unless a coherent source authorized -------------------------
if [ "$authorized" -ne 1 ]; then
  log "no coherent active source authorizes dispatch for branch '$current_branch' (state.md not active AND no unique autonomous state.json) — skipping dispatch"
  exit 0
fi

# ---- Authorized — dispatch via the existing dispatcher -----------------------
# The dispatcher owns opt-out (AC4), per-PR idempotency (AC5), default-ON
# gating, the detached launch, and the until-mergeable signal. Do NOT
# reimplement any of that here.
bash "$DISPATCHER" --pr-url "$PR_URL" || true

exit 0
