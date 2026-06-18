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
# A bare non-empty .supervisor/jobs/in-progress/ is NOT sufficient — ALL THREE
# gate terms (in-progress job exists AND state.md Status not completed/failed
# AND PR head branch == session feature branch) are required before dispatch.
#
# DOCUMENTED LIMITATION
# ---------------------
# This hook covers PR creation via `gh pr create` through the Bash tool only
# (the plugin's only PR-creation path). For any other PR-creation mechanism
# (e.g. an MCP tool), Supervisor step 5.5 remains the in-context dispatch path.

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

# ---- Defensive: only act on Bash tool calls (AC6 — malformed JSON → empty) --
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
if [ "$TOOL_NAME" != "Bash" ]; then
  # Not a Bash tool call (or malformed JSON yielding empty) — no-op.
  exit 0
fi

# ---- Extract the tool response text (stdout + stderr) -----------------------
RESP="$(printf '%s' "$INPUT" | jq -r '(.tool_response.stdout // "") + "\n" + (.tool_response.stderr // "")' 2>/dev/null || true)"
if [ -z "$RESP" ]; then
  # jq failed or no response text — nothing to scan.
  exit 0
fi

# ---- Extract a PR URL from the response (AC2: no URL → not a PR creation) ---
PR_URL="$(printf '%s' "$RESP" | grep -oE 'https://github\.com/[^/[:space:]]+/[^/[:space:]]+/pull/[0-9]+' | head -1 || true)"
if [ -z "$PR_URL" ]; then
  # No PR URL in the response — this Bash call was not a PR creation.
  exit 0
fi

# ---- Confirm the command was a `gh pr create` (defense-in-depth) -------------
# The PR-URL above is the primary trigger; additionally require the command
# itself to be a PR-creation so a mid-session `gh pr view`/`gh pr list`/`git log`
# that merely PRINTS a /pull/<n> URL cannot trigger a drain against a foreign PR
# (tightens the session gate's false-positive surface). Matches the documented
# scope: `gh pr create` via the Bash tool.
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
case "$CMD" in
  *"pr create"*) : ;;  # a PR-creation command — proceed
  *)
    log "command is not a 'gh pr create' (response carried a PR URL) — skipping"
    exit 0
    ;;
esac

# ---- SESSION-SCOPE GATE (AC3) ----------------------------------------------
# Dispatch ONLY when ALL THREE terms hold. Bare in-progress non-empty is NOT
# sufficient. Any failing term → log one line + exit 0.

# (i) .supervisor/jobs/in-progress/ is NON-EMPTY (cleared on completion).
if ! { [ -d .supervisor/jobs/in-progress ] && [ -n "$(ls -A .supervisor/jobs/in-progress 2>/dev/null)" ]; }; then
  log "no in-progress job — not an active plugin run; skipping dispatch"
  exit 0
fi

# (ii) .supervisor/state.md first `## Status:` word is NOT completed/failed.
#      (state.md retains the last session's `- branch:` after completion, so this
#      Status term guards the stale-branch case. state.md absent → unknown →
#      does NOT fail on this term alone.)
if [ -f .supervisor/state.md ]; then
  STATUS_WORD="$(grep -m1 '^## Status:' .supervisor/state.md 2>/dev/null | sed -E 's/^## Status:[[:space:]]*//' | awk '{print $1}' || true)"
  case "$STATUS_WORD" in
    completed|failed)
      log "session Status is '$STATUS_WORD' (stale) — skipping dispatch"
      exit 0
      ;;
  esac
fi

# (iii) BRANCH MATCH: current branch == session feature branch.
#       The env var is the TEST SEAM (lets the self-test control current branch).
current_branch="${AI_AGENT_MANAGER_HOOK_CURRENT_BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)}"
session_branch=""
if [ -f .supervisor/state.md ]; then
  session_branch="$(grep -m1 '^- branch:' .supervisor/state.md 2>/dev/null | sed -E 's/^- branch:[[:space:]]*//' | sed -E 's/[[:space:]]+$//' || true)"
fi
# No `- branch:` line in state.md → fall back to current_branch (gate (iii) then
# passes, relying on (i)+(ii)). Gate (iii) FAILS only when a state.md branch
# exists AND differs from current_branch.
if [ -z "$session_branch" ]; then
  session_branch="$current_branch"
fi
if [ "$session_branch" != "$current_branch" ]; then
  log "branch mismatch (current='$current_branch' session='$session_branch') — not this session's PR; skipping dispatch"
  exit 0
fi

# ---- All gate terms pass — dispatch via the existing dispatcher --------------
# The dispatcher owns opt-out (AC4), per-PR idempotency (AC5), default-ON
# gating, the detached launch, and the until-mergeable signal. Do NOT
# reimplement any of that here.
bash "$DISPATCHER" --pr-url "$PR_URL" || true

exit 0
