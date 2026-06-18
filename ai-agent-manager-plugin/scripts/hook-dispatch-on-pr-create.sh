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
# The branch term is FAIL-CLOSED: if state.md does not yield a branch value in
# either the canonical lowercase (`- branch:`) or the bold (`- **Branch:**`) form
# (absent file or no branch line), the PR is unconfirmable and dispatch is skipped
# (no current-branch fallback) — preserving "never hijack an unrelated manual PR".
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

# ---- SESSION-SCOPE GATE (AC3) ----------------------------------------------
# Dispatch ONLY when ALL THREE terms hold. Bare in-progress non-empty is NOT
# sufficient. Any failing term → log one line + exit 0.

# (i) .supervisor/jobs/in-progress/ is NON-EMPTY (cleared on completion).
if ! { [ -d .supervisor/jobs/in-progress ] && [ -n "$(ls -A .supervisor/jobs/in-progress 2>/dev/null)" ]; }; then
  log "no in-progress job — not an active plugin run; skipping dispatch"
  exit 0
fi

# (ii) .supervisor/state.md status word (under `## Session`) is NOT a TERMINAL
#      status. Terminal = completed | completed_with_escalation | failed (the
#      Supervisor Phase 4.5 completion tail flips `- status:` to one of these on
#      exit). Non-terminal (running | paused) is the only state that permits
#      dispatch.
#      FORMAT-TOLERANT: matches BOTH the canonical lowercase bullet
#      (`- status: running`) AND the inline-Supervisor bold display style
#      (`- **Status:** running`). Match is case-insensitive on the key and strips
#      any bold `**` markers before taking the first word, so either form yields
#      the same status word.
#      (state.md retains the last session's branch after completion, so this
#      status term guards the stale-branch case. state.md absent → unknown →
#      does NOT fail on this term alone.)
if [ -f .supervisor/state.md ]; then
  # Strip bold `**` markers FIRST so both `- status:` and `- **Status:**`
  # collapse to a bare `- status:` key, then strip the key + leading space and
  # take the first word.
  STATUS_WORD="$(grep -m1 -iE '^- (\*\*)?status:?' .supervisor/state.md 2>/dev/null \
    | sed -E 's/\*\*//g' \
    | sed -E 's/^- [Ss][Tt][Aa][Tt][Uu][Ss]:[[:space:]]*//' \
    | awk '{print $1}' || true)"
  case "$STATUS_WORD" in
    completed|completed_with_escalation|failed)
      log "session Status is '$STATUS_WORD' (terminal/stale) — skipping dispatch"
      exit 0
      ;;
  esac
fi

# (iii) BRANCH MATCH: the session feature branch MUST be resolvable from
#       .supervisor/state.md's branch line AND equal the current branch.
#       FORMAT-TOLERANT: matches BOTH the canonical lowercase bullet
#       (`- branch: feature/foo`) AND the inline-Supervisor bold display style
#       (`- **Branch:** feature/foo`). Match is case-insensitive on the key; the
#       bold `**` markers, the key, and surrounding whitespace are all stripped so
#       the bold value is extracted cleanly (no embedded `**`).
#       The env var is the TEST SEAM (lets the self-test control current branch).
#
#       FAIL-CLOSED on a missing branch (no fallback). If state.md yields no
#       branch value — whether the file is absent OR present-but-branchless —
#       the PR cannot be confirmed as THIS session's, so SKIP. An earlier revision
#       fell back to current_branch, which made term (iii) trivially pass and
#       weakened "never hijack an unrelated manual PR" to "(i)+(ii) alone" whenever
#       the branch line was missing. A real plugin run always records `- branch:`
#       at Phase 1 ACQUIRE, so this fail-closed path never blocks the happy path —
#       it only refuses dispatch in a degraded/foreign state where the branch is
#       unconfirmable. Keeps the anti-hijack posture fully fail-closed.
current_branch="${AI_AGENT_MANAGER_HOOK_CURRENT_BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)}"
session_branch=""
if [ -f .supervisor/state.md ]; then
  # Strip bold `**` markers FIRST so both `- branch:` and `- **Branch:**`
  # collapse to a bare `- branch:` key, then strip the key + leading whitespace
  # and any trailing whitespace, yielding a clean branch value.
  session_branch="$(grep -m1 -iE '^- (\*\*)?branch:?' .supervisor/state.md 2>/dev/null \
    | sed -E 's/\*\*//g' \
    | sed -E 's/^- [Bb][Rr][Aa][Nn][Cc][Hh]:[[:space:]]*//' \
    | sed -E 's/[[:space:]]+$//' || true)"
fi
if [ -z "$session_branch" ]; then
  log "no branch line in state.md — cannot confirm PR belongs to this session; skipping dispatch"
  exit 0
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
