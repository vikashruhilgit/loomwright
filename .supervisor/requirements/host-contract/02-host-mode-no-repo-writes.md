# 02 — Host mode: when a host says so, Loomwright's hooks write nothing into the session's repo

## Status: pending

> **Origin (2026-10-06).** Loomwright Studio's probe p9, on Loomwright 15.123.0 in a throwaway git repo, found that one SDK session with Loomwright loaded **added** three files: `.claude/settings.local.json` (with `env.OTEL_RESOURCE_ATTRIBUTES`, from `set-otel-resource-attrs.sh`), `.supervisor/logs/<session>.jsonl` (`agent_identity`, `agent_lifecycle` and `token_ledger` events) and a lifecycle heartbeat file. Studio's agents work in the owner's real repos. Studio's own sessions don't read that `settings.local.json`, but the owner's own Claude Code sessions in the repo do. So a background agent silently changes the environment of the owner's later sessions, and leaves untracked files in every repo it touches.

## Wave notes (added 2026-10-06 by the S3 operator; owner decision "prep now, lane at wave 3")
- Runs after 01 in the same lane.

## Depends on
01

## Touches
loomwright/scripts/set-otel-resource-attrs.sh
loomwright/scripts/emit-lifecycle.sh
loomwright/scripts/emit-agent-identity.sh
loomwright/scripts/emit-token-ledger.sh
loomwright/scripts/emit-progress-event.sh
loomwright/scripts/stamp-requirement-status.sh
loomwright/scripts/session-resume.sh
loomwright/scripts/seed-run-owner.sh
loomwright/scripts/reproject-state-on-terminal.sh
loomwright/scripts/close-stranded-run.sh
loomwright/scripts/worktree-audit.sh
loomwright/scripts/guard-arm.sh
loomwright/scripts/guard-test-integrity.sh
loomwright/scripts/notify-desktop.sh
loomwright/scripts/send-telemetry.sh
loomwright/scripts/validate-worker-result.py
loomwright/scripts/build-capabilities.sh
loomwright/scripts/test-host-mode.sh
loomwright/capabilities.json
loomwright/docs/CAPABILITIES_CONTRACT.md
loomwright/docs/HOOKS.md
changelog.d/host-contract-02-host-mode-no-repo-writes.md

## Problem
There's no way for a host to say "you're running under me; keep your state out of the repo". The repo-writing hooks are deliberately fail-SAFE emitters, which is right. But they always write into the session's working directory.

## Goal
One **host-neutral** environment switch. Loomwright picks the name, for example `LOOMWRIGHT_HOST_MODE=1`; D32's `STUDIO_HOST=1` was only an example, and Loomwright shouldn't name a specific host. When it's set, no Loomwright hook creates or modifies any file in the session's working directory. Optionally, the state goes instead to a host-provided directory (for example `LOOMWRIGHT_HOST_STATE_DIR`), so a host like Studio can still read the token ledger and lifecycle events. When the switch is **unset**, behaviour is byte-for-byte unchanged.

## Scope
- **Audit every hook script** that `hooks/hooks.json` invokes for writes into the working directory. As of 15.123.1 these scripts reference repo-local paths (`.supervisor/…` or `settings.local.json`). Confirm each by reading it:
  - `set-otel-resource-attrs.sh`, `emit-lifecycle.sh`, `emit-agent-identity.sh`;
  - `emit-token-ledger.sh`, `emit-progress-event.sh`, `stamp-requirement-status.sh`;
  - `session-resume.sh`, `seed-run-owner.sh`, `reproject-state-on-terminal.sh`;
  - `close-stranded-run.sh`, `worktree-audit.sh`;
  - `guard-arm.sh`, `guard-test-integrity.sh`;
  - `notify-desktop.sh`, `send-telemetry.sh`, `validate-worker-result.py`.
  - Classify each: writes into the repo, or not.
- Under host mode, each repo-writing hook either:
  - **redirects** its write under `LOOMWRIGHT_HOST_STATE_DIR` (same relative layout, e.g. `$LOOMWRIGHT_HOST_STATE_DIR/logs/<session>.jsonl`) when that variable is set to an absolute, existing directory; or
  - **skips** the write (exit 0) when it isn't set.

  `set-otel-resource-attrs.sh` must not touch `.claude/settings.local.json` at all under host mode. It may still export through `CLAUDE_ENV_FILE`, which is session-scoped and not a repo file.
- **Blocking gates are NOT weakened.** The fail-CLOSED `guard-test-integrity.sh` hooks keep enforcing. If one of them persists state into the repo, redirect that state; never turn the gate into a no-op. Validators keep returning their decisions.
- Item 01's contract gains `host_switch: {env, state_dir_env, effect}`, and each hook entry gains `host_mode: "redirects" | "skips" | "unaffected"`.
- Tests:
  - With host mode on and a state dir, a session-start, a SubagentStop and a Stop hook run against a throwaway git repo. Afterwards, `git status --porcelain --ignored` shows **nothing new** in the repo, and the events are in the state dir.
  - With host mode on and no state dir, nothing new is written anywhere, and every hook exits 0.
  - With host mode unset, the existing tests pass unchanged.
  - A mutation control: break the host-mode check in one hook, and the test fails.

## Acceptance criteria
1. Under `<switch>=1`, no Loomwright hook creates or modifies any path in the session's working directory, which a test proves with `git status --porcelain --ignored`. That includes `.claude/settings.local.json` and `.supervisor/`.
2. With `LOOMWRIGHT_HOST_STATE_DIR` set, the redirected events (lifecycle, identity, token ledger, progress) land there, in the same format.
3. With the switch unset, behaviour and every existing test are unchanged.
4. Fail-CLOSED gates still enforce under host mode; only their on-disk state moves.
5. Every repo-writing hook keeps its fail-SAFE `exit 0` under host mode. That includes the cases where the state dir is invalid or missing: the hook skips, never errors.
6. The contract (`capabilities.json`) declares `host_switch` and each hook's `host_mode`, and is regenerated, so the staleness check passes.
7. `docs/HOOKS.md` documents host mode in one place. Ships a `changelog.d` fragment only — no version bump in the item's PR (wave lane; the wave branch carries the one bump, S3 run rule P7; amended 2026-10-06, owner decision).

## Non-goals
Changing what any hook does outside host mode. Studio's side of reading the state dir (Studio's phase 2).
