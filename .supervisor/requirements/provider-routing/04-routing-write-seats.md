# 04 — Provider routing for write seats (worker, heal fix, drain fix)

## Status: pending

**As a** maintainer, **I want** to let a non-Claude CLI implement a subtask or apply a fix, **so that** I can use the
model I prefer for code changes — while the plugin, not that CLI, decides whether the work counts and who pushes it.

## Starting point for Launch Pad (2026-11-01)
A prior Launch Pad pass failed Plan Review 3× (last HIGH: a worker-side `write_seat_tampered` stop reaches the Phase 4.5
completion-tail guard, whose only exception is `self_heal_resume_thrash`). Its corrected, UNREVIEWED draft — fix for that
finding and the attempt-3 MEDIUM/LOW findings folded in — is
`.supervisor/requirements/provider-routing/04-routing-write-seats.launch-pad-draft-2026-11-01.txt`. Start from it, re-verify
every claim against main, and let Plan Review judge it fresh.

## Owner decisions (2026-11-01)
- **D1 — one provider per run.** The `worker` seat names one provider for every worker subtask of a run; no per-subtask
  or per-lane mixing. A provider failure therefore never leaves a branch with some subtasks by one CLI and some by another.
- **D2 — fix seats default to Claude.** An unset `heal_fix` / `drain_fix` seat resolves to Claude, never to the worker's
  provider. Routing a fix seat to a non-Claude CLI needs its own explicit seat entry and its own write grant.

## Intended shape (re-verify against main before building)

- **Seats:** `worker`, Phase 4.5 `heal_fix`, drain `drain_fix` (the `routing.seats` keys from 03), with D1 and D2 above.
- **Eligibility:** only a provider whose `setup-providers.sh check` verdict is `usable for write seats`, i.e. its
  permission probe observed a denial (05 made that an observed denial, not help text). Any other provider configured
  for a write seat is refused at config time with a named status.
- **Launch (invariant):** every write-seat launch goes through `launch-provider-cli.sh` with an isolated HOME — never the
  real HOME. Grok reads `~/.claude/settings.json`, and a `permissions.defaultMode: "auto"` there overrides
  `--permission-mode dontAsk` (see re-probe evidence below), so a real-HOME launch is fail-OPEN. Make it guarded, not
  conventional, and add a regression test that the launcher never copies `~/.claude/settings.json` into the isolated HOME.
- **Where:** the provider runs in the worktree Supervisor already creates for the subtask, environment scrubbed by the
  launcher; it never pushes — Supervisor alone commits, pushes and opens the PR.
- **What counts:** the provider's own "done" claim is ignored; the existing disk gate (`verify-provides.sh` /
  `outputs_verified`), tests/lint and Phase 4.5's integrated review decide, exactly as for a Claude worker. The probe
  shows one denial on one fixed prompt, not that every tool is denied, so these gates stay the real control.
- **Hooks:** under the isolated launch Loomwright's plugin hooks do not fire (no `.claude/` appeared in the cwd). State
  that as the contract for a non-Claude seat: no hook-written state, telemetry or guard runs inside it, and the
  Supervisor-side gates above carry the checks instead.
- **Consent:** same user-scoped per-repo grant as 03; each write seat needs an explicit separate grant (`write: true`).
- **Failure:** provider unavailable/timeout ⇒ the subtask fails through the existing worker-failure path
  (`docs/FAILURE_ESCALATION.md`), or falls back to Claude when `on_unavailable` is `fallback_to_default`.

## Depends on
03-routing-config-readonly-seats.md, 05-provider-launch-parity.md (both merged)

## Touches
unknown

## Probe status — 2026-11-01, main @ 5fadddb (v17.23.1)
- `grok 1.0.70`: auth ok (via smoke) · headless pass · permissions pinnable ⇒ usable for write seats.
- `claude 2.1.314`, `cursor-agent`: `not_logged_in_isolated` (keychain logins cannot cross the isolated HOME); cursor
  also grades `unpinnable`. `codex`, `copilot`, `gemini`: not installed.

The sections below are the evidence the shape above was derived from; their premises are now folded in.

## Probe evidence — Grok Build 1.0.70, 2026-10-31 (owner's Mac, logged in as the owner)

- `setup-providers.sh check` → `auth ok · headless pass · permissions pinnable => usable for write seats`.
- **That `pinnable` is a help-text check only** (`PROBE_PERM_PIN_FLAGS` tokens appear in `grok --help`). Hand probe in
  scratch dirs, prompt "create probe.txt":
  - `--permission-mode dontAsk`, no allow rule → **file WRITTEN**. `dontAsk` is NOT default-deny on this build.
  - `--permission-mode dontAsk --deny Write --deny Edit --deny Bash` → refused, no file. Explicit deny rules ARE enforced.
- **Grok runs this user's Claude Code plugin hooks:** each run left `.claude/settings.local.json` (OTEL attrs) in the
  cwd — Loomwright's SessionStart `set-otel-resource-attrs.sh`. A Grok seat fires Loomwright hooks inside its worktree.

## Premises this changes (rewrite before promoting)
1. Eligibility must not rest on the help-text `pinnable`: add an **enforcement probe** to `check` (dontAsk + no allow ⇒
   a write must be refused) and grade a provider `usable for write seats` only when it passes. Grok 1.0.70 fails it.
2. A write seat can only be pinned with an **explicit deny-list**, which is fail-OPEN on any tool the list omits
   (MCP tools, new built-ins). Decide whether a deny-list is an acceptable pin, or whether write seats wait for a build
   where `dontAsk` denies by default.
3. Hook side effects of a non-Claude seat (state, telemetry, guards firing under Grok) need a stated contract.

## Re-probe after 05 shipped (#764, v17.23.0) — 2026-10-31, main @ a3e8ed5

- `check` now launches through the shared isolated launcher: `grok … permissions pinnable => usable for write seats`
  (an observed denial, not help text); `claude` and `cursor-agent` → `not_logged_in_isolated` (keychain logins
  cannot cross; cursor needs `CURSOR_API_KEY`).
- **Why the first probe wrote a file — root cause found.** Grok 1.0.70 reads the user's `~/.claude/settings.json`, and
  `permissions.defaultMode: "auto"` there OVERRIDES the `--permission-mode dontAsk` CLI flag. Bisected in an isolated
  HOME: only `{"permissions":{"defaultMode":"auto"}}` → file written; the same settings minus `defaultMode` →
  `stopReason: cancelled`, no file; `.grok/config.toml` + `settings_cache.json` → no file.
- A REPO-level `.claude/settings.json` with `defaultMode: auto` in the cwd did NOT override `dontAsk` (no file).
- Isolated runs left no `.claude/` in the cwd: Loomwright hooks do not fire under the isolated launch.
- Premises 2 and 3 above are therefore narrower: `dontAsk` IS default-deny for Grok **when launched isolated**. Write
  seats are safe only if every write-seat launch goes through `launch-provider-cli.sh` (never the real HOME). Make that a
  guarded invariant, plus a regression test that copying a `~/.claude/settings.json` into the isolated HOME is refused.
- The probe shows one denial on one prompt, not that every tool is denied — keep the disk gate + Supervisor-only push.
- Un-park condition (05 shipped AND a provider passes the real probe) is now MET; promotion still needs the two open
  questions answered and these premises folded into the shape.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-01T10:35:18Z
- **Brief:** .supervisor/jobs/done/2026-11-01-provider-routing-write-seats.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/770
