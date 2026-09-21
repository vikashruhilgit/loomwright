# 06 — Remaining script tests + small roadmap remainders (P1, medium)

## Goal
Close the highest-value remaining test gaps (webhook payload safety, rules-check
confirmation gate, notify-desktop) and the two cheap OPEN roadmap items, in one sweep.

## Evidence
- Untested runtime scripts (2026-07-05 audit): `send-webhook.sh` (536 lines, jq-only payloads
  but unproven), `notify-desktop.sh` (188 lines), and `rules-check.sh`'s confirmation-gate
  matrix (test-rules-check.sh covers fixture parsing, not the gate precedence).
- OPEN roadmap items after item 03's verification — REBASELINED 2026-07-06: P1-4 is
  ALREADY RESOLVED (red-team has `effort: xhigh`); the stale text below kept for
  history: P1-4 (`effort: high` missing on
  red-team-reviewer frontmatter), P1-6 (WorktreeRemove hook missing; WorktreeCreate exists).

## Scope
1. **`loomwright/scripts/test-send-webhook.sh`** (new):
   - Payload-construction assertions: feed hostile `$CONTEXT`/summary values (double quotes,
     backslashes, newlines, `$(...)`, unicode) through the gate/paused/supervisor-result
     paths in dry-run/print mode; parse output with `jq -e` to prove valid JSON and exact
    round-trip of the hostile string as data.
   - Branch coverage: ntfy plain-text path vs JSON webhook path vs Slack shape;
     `LOOMWRIGHT_WEBHOOK_URL` unset → silent no-op exit 0.
   - Never performs a real POST: point at an unroutable localhost port or use the script's
     dry-run mode (read the script first; prefer its own dry-run if present).
   - Fail-safe proof: every failure path still exits 0.
2. **Extend `loomwright/scripts/test-rules-check.sh`** with a gate-precedence matrix:
   `--no-cmd` alone → all checks skipped; `--no-cmd` + `--confirm` → --no-cmd WINS (skip);
   `--confirm` alone → executes fixture checks (side-effect fixture: check writes a marker
   file, assert marker exists); no flags + non-TTY stdin → default skip with
   "needs confirmation" marker and NO execution; failing check → tallied, script does not
   crash (no set -e regression). Confirm test asserts the reader (`read-rules.sh`) is never
   invoked as an executor (re-run test-rules-seams.sh as part of this).
3. **`loomwright/scripts/test-notify-desktop.sh`** (new, small): platform-guarded — on
   macOS assert graceful no-op when terminal-notifier absent (PATH sandbox), assert exit 0
   on every path, assert timeout/gtimeout fallback selection logic picks something sane.
   Keep it skippable-green on Linux CI (detect platform, assert the Linux path's no-op).
4. **Roadmap remainder P1-4: ALREADY DONE (verified 2026-07-06)** —
   red-team-reviewer.md already carries `effort: xhigh`. Do NOT touch the frontmatter;
   just flip roadmap P1-4's verdict to RESOLVED in this PR's roadmap touch. Likewise
   RED_TEAM_RESULT is already documented in RESULT_SCHEMAS.md (schema_version 1,
   advisory, no validator) — stamp roadmap P2-13 RESOLVED-as-advisory, not
   "intentionally-advisory pending".
5. **Roadmap remainder P1-6**: add a `WorktreeRemove` hook to `loomwright/hooks/hooks.json`
   mirroring WorktreeCreate (type: command, log to `.supervisor/logs/worktrees.log`,
   `|| true`, always exit 0). FIRST verify the WorktreeRemove event actually exists in
   current Claude Code hooks (needs verification — check docs/claude-code-guide agent);
   if unsupported, instead stamp roadmap P1-6 DEFERRED-with-reason and skip.
   NOTE: if the hook lands, hook count 21→22 → update EVERY count surface
   (plugin.json/marketplace descriptions in place, CLAUDE.md §hooks table + banner counts,
   READMEs) in the same change or doc-currency CI fails.
6. **Optional belt-and-suspenders**: add `|| true` to the hook command strings in hooks.json
   that lack it (scripts already exit 0 unconditionally — this only guards against
   missing-interpreter/syntax-error edge cases). Zero-risk, include it.
7. **LSP wiring (last Bet-1 remnant, restored from the pre-review north-star pending list
   item #8)**: code-reviewer is currently the only agent with LSP in its `tools:`
   frontmatter. Add LSP to `loomwright/agents/worker.md`, `qa-executor.md`, and
   `launch-pad.md` frontmatter, plus ONE short usage line each in the prompt body at the
   natural consumption point (worker: self-verify diagnostics on modified files before
   emitting WORKER_RESULT; qa-executor: Phase 5 static-analysis leg; launch-pad: Phase 3
   ANALYZE impact-map grounding). FIRST verify the exact tool name/availability for
   plugin-agent frontmatter against current Claude Code docs (mirror code-reviewer.md's
   declaration verbatim — verify-invocation-shapes-from-the-file discipline). No behavior
   gate: diagnostics are input, never a new blocker. Agent↔command mirror sweep if any
   command doc enumerates these agents' tools.

## Constraints / invariants
- All new tests: deterministic, sandboxed temp dirs, no network, bash-3.2 + Linux CI safe
  (stat/date/sed -i portability; validate numerics before `$(( ))` under set -u).
- rules invariants intact: reader never executes; rules-check remains sole execution path;
  no advisory seam gains execution. Re-run test-rules-seams.sh + test-add-rule.sh.
- Emitters keep ALWAYS-exit-0. Gates keep fail-closed. Minor version bump + CHANGELOG.

## Acceptance criteria
- [ ] 2 new test files + extended rules-check matrix, all green in CI's test loop.
- [ ] Hostile-string webhook assertions prove jq round-trip (paste one example in PR).
- [ ] Roadmap P1-4 and P2-13 verdicts flipped to RESOLVED (no frontmatter/schema edits —
      both already satisfied in the repo as of v15.2.0).
- [ ] WorktreeRemove hook added with full count-surface sweep, OR roadmap P1-6 stamped
      DEFERRED with the verification evidence.
- [ ] LSP declared in worker/qa-executor/launch-pad frontmatter (mirroring
      code-reviewer.md's shape) with one usage line each; no new gating behavior.
- [ ] All existing tests + validators green.

## Out of scope
RED_TEAM_RESULT formal schema (advisory-only design stands — stamp roadmap P2-13 as
intentionally-advisory in this PR's roadmap touch), build-insights/read-bridge/lessons
tests (lower risk, backlog), observability probe hardening.

## Status: done
- Completed: 2026-07-07 via PR https://github.com/vikashruhilgit/loomwright/pull/96 (v15.5.0)
