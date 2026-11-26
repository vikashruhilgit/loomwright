# Selvedge read-only mode and a check that the app is up

## Status: pending

**As a** developer pointing Selvedge at a local app,
**I want** to say "never change this app's data" and "this URL tells you the app is ready",
**so that** a check can't write to a database other people share, and a run against an app that isn't running says so plainly instead of failing a step.

Two parts, one story: both add a key to `selvedge.json` and touch the same config, schema, init and doc files.

## Why now
- **Read-only.** Selvedge refuses writes only to remote origins (`allow_remote_mutation`; the method check in `lib/runner/proxy.mjs` applies only when the origin is not local). Hub's local stack serves on localhost but reads the shared ZQA databases, so Selvedge would allow a POST there that changes shared data.
- **Ready.** Selvedge has no readiness check. `snapshot` handles an unreachable origin's 502 page, but nothing in `lib/` names a refused connection for `run`, so an app that isn't up most likely shows as `step_failed` on the first `goto` (read from the code, not reproduced). Hub's `scripts/e2e-local.sh` shows the value of naming the cause.

## Acceptance Criteria

**Part A — `read_only`**
- [ ] Given `"read_only": true` in `selvedge.json`, when a plan's action makes the browser send POST, PUT, PATCH or DELETE to any origin, localhost included, then the request is refused and the criterion is BLOCKED `read_only_mutation_refused`, naming the method and origin.
- [ ] Given `"read_only": true`, GET, HEAD and OPTIONS still pass, and a redirect that keeps a refused method is refused, matching how `remote_mutation_refused` treats redirect hops.
- [ ] Given `read_only` absent, behaviour is exactly today's (existing configs are unchanged).
- [ ] Given `selvedge env init` writes a new `selvedge.json`, then it writes `"read_only": true` unless the user answered that the app's data is disposable (TTY prompt, or a flag for non-interactive use).
- [ ] Given `"read_only": true`, approved `seed` / `reset` hooks are refused with BLOCKED `env_hooks_read_only` (hooks change data by design).
- [ ] `selvedge doctor` reports the read-only state in one line.

**Part B — `ready`**
- [ ] Given `"ready": {"url": "http://localhost:3001/health/ready", "status": 200, "timeout_s": 60}`, when `selvedge run` starts, then it polls that URL before the first browser launch and goes on once the status matches.
- [ ] Given the URL never answers with the status before the timeout, then every criterion is BLOCKED `target_not_ready`, nothing launches, and the output names the last status (or "no answer") and the first 300 characters of the body, redacted like read values.
- [ ] Given `ready.url` on an origin not in `origins`, then the config is refused (`config_schema_violation`).
- [ ] Given `ready` absent, behaviour is today's.
- [ ] Given `selvedge env init`, when the app is running, then it tries common health paths on the origin (`/health`, `/healthz`, `/ready`, `/health/ready`, `/api/health`) and offers the first that answers 2xx; the user confirms or skips.

**Both**
- [ ] Both keys are read from the base branch's `selvedge.json` under `--base`, like every other key, so a PR cannot switch read-only off for itself.
- [ ] The README's BLOCKED reasons table lists `read_only_mutation_refused`, `env_hooks_read_only` and `target_not_ready`.

## Non-goals
- Detecting a shared database automatically (the setup scout suggests it; this story only enforces the key).
- Changing the default for existing `selvedge.json` files.
- Diagnosing which backend service is down (hub-specific); only the ready response is shown.

## Owner decisions
- 2026-11-23 (/product-owner session): new configs get `read_only: true` unless the user says the data is disposable; existing configs without the key keep today's behaviour.

## Priority: MVP
**Rationale:** Part A closes a safety gap that must be shut before Selvedge is pointed at any app with shared data. Part B is small and makes the commonest failure clear.

## Assumptions
- This is a new capability (two new keys), not a defect fix. The "why now" notes were read from the code, not shown in a run: that a down app shows as `step_failed`, and that a local POST passes the guard. No AC depends on either note.
- The guard proxy and the route guard both see every request method, so one check point covers local origins too.

## Dependencies
- Depends on: none
- Blocks: the setup scout (it proposes both keys)

## Risks
- `read_only` on by default for new configs can confuse a user whose criterion needs a write; the BLOCKED reason and README name the key to change.
- Polling a ready URL that is rate-limited; the poll interval is at least 5 s.

## Validation (must pass before merge)
1. **Static — selvedge's own gate:** `bash selvedge/tests/run.sh` passes, with new cases in `tests/test-proxy.sh` and `tests/test-route-guard.sh` (local POST refused under `read_only`, GET allowed, redirect hop refused, key absent = today), `tests/test-env.sh` (init writes `read_only: true` by default, the disposable answer omits it, health-path offer, `ready` origin outside `origins` refused) and `tests/test-run.sh` (`target_not_ready` with no browser launched; ready app goes on).
2. **Running system — sample app:** with the sample app stopped, `selvedge run` on a frozen plan prints `BLOCKED target_not_ready`; started, the same plan runs.

## Depends on
none

## Touches
selvedge/schemas/selvedge-config.schema.json
selvedge/lib/env-config.mjs
selvedge/lib/env.mjs
selvedge/lib/runner/proxy.mjs
selvedge/lib/runner/route-guard.mjs
selvedge/lib/runner/run.mjs
selvedge/lib/doctor.mjs
selvedge/README.md
selvedge/tests/test-proxy.sh
selvedge/tests/test-route-guard.sh
selvedge/tests/test-env.sh
selvedge/tests/test-run.sh
selvedge/tests/test-doctor.sh
selvedge/CHANGELOG.md
selvedge/.claude-plugin/plugin.json
.claude-plugin/marketplace.json
