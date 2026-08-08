---
name: pr-create-hook-false-positive-surface
description: hook-dispatch-on-pr-create.sh triggers on ANY Bash stdout containing a /pull/N URL, not just gh pr create; AC3 session gate is the only defense
metadata:
  type: project
---

`loomwright/scripts/hook-dispatch-on-pr-create.sh` (v14.34.0 PostToolUse[Bash] backstop) extracts the PR URL from `tool_response.stdout/stderr` and does NOT inspect `tool_input.command` to confirm the Bash call was actually `gh pr create`. So `gh pr view`/`gh pr list`/`git log`/`echo` emitting a `…/pull/<n>` URL all pass URL extraction. The ONLY false-positive defense is the AC3 3-term session gate (in-progress job non-empty AND state.md Status≠completed/failed AND current branch == session branch).

**Residual false-positive:** during an active /supervisor session on the feature branch, a `gh pr view <foreign-PR>` whose stdout shows a DIFFERENT PR's URL passes all three gate terms (they're all session-state, not URL-bound) → dispatches a review-heal drain against the unrelated PR.

**Why it's accepted (not a blocker):** blast radius is a read-only, never-merge /review-pr drain bounded to the active-session window; the dispatcher's per-PR idempotency marker is URL-keyed so it doesn't block the real PR. Documented as a known limitation in the wrapper header.

**Why:** the wrapper deliberately keys off the response URL because `gh pr create` is the only plugin path that creates+emits a fresh PR URL in stdout; tool_input.command inspection was a considered-but-not-taken hardening.

**How to apply:** in a future review touching this wrapper, an optional `tool_input.command` substring check for `pr create` would tighten the gate — flag it as LOW/defense-in-depth, not FAIL. Verify the fail-safe invariant (set -u only, no set -e, every exit 0, dispatcher call `|| true`) stays intact on any edit.
