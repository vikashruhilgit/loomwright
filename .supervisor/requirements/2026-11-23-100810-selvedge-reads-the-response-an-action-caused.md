# Selvedge reads the HTTP response an action caused

## Status: pending

**As a** developer checking a pull request with Selvedge,
**I want** a plan to check the HTTP response that a click or form submit caused (its status, one field of its JSON body, or whether a cookie was set),
**so that** criteria like "a wrong password gets a 401", "the 11th sign-in gets a 429" or "saving returns the new id" get a real PASS or FAIL instead of NOT_VERIFIABLE.

## Why now
On the 0.10.0 tuning run, 16 of 72 cases were NOT_VERIFIABLE `side_effect_not_observable`. Their planner notes give the same cause: the criterion checks an HTTP status, a POST response or a session cookie, which no browser step can read (`selvedge/CHANGELOG.md`, 0.10.1). The held-out report shows abstention at 0.587 against the Phase 3 gate's 0.20 limit (`selvedge/eval/results.json`). Hub's sign-in throttle e2e reads status codes the same way (`Tray/hub/e2e/fixtures/sign-in-throttle.ts`), so the need is not specific to one app.

## Acceptance Criteria

**Happy path**
- [ ] Given a frozen plan whose criterion does an action and then reads the response to `POST /api/login` (method and URL pattern), when `selvedge run` runs it and the app answers 401, then the read value is `401` and an `expect equals 401` is PASS.
- [ ] Given the same plan, when the app answers 200, then the criterion is FAIL and its evidence shows the expected and the read value.
- [ ] Given a criterion that reads one named field of the response's JSON body (for example `$.id`), when the response carries it, then that value is the read value, redacted in evidence and the PR comment exactly as other read values are.
- [ ] Given a criterion that checks whether the action set a named cookie, when it was set, then the read value reports the cookie's presence and flags (`HttpOnly`, `Secure`, `SameSite`), and never its value.
- [ ] Given `selvedge snapshot` during planning, when the planner performs prefix actions, then the snapshot output lists the requests each action set off (method, path, status; no bodies, no headers, no query values), so the planner can name a response it actually saw.
- [ ] The planner prompt tells the planner to use a response read for a criterion about a status, a server reply or a cookie before falling back to `side_effect_not_observable`.

**Edge cases**
- [ ] Given a response that arrives before the step could have started listening, when the run executes, then it is still caught: the listener is armed before the action it follows.
- [ ] Given an action that sets off no matching response within the step's timeout, then the criterion is NOT_VERIFIABLE `no_value_read`, never PASS.
- [ ] Given several matching responses, then the first one after the action is read, and the evidence says how many matched.
- [ ] Given a JSON field path into a body that is not JSON, then the criterion is NOT_VERIFIABLE `no_value_read` and the evidence names why.

**Error scenarios (lint)**
- [ ] A response read that does not follow an action step in the same criterion is rejected by `plan --validate` with a named problem.
- [ ] A response read whose URL pattern names an origin not in `origins` is rejected by the lint.
- [ ] A response read never sends a request itself: a test shows the run's request count is the same with and without the read step.

## Non-goals
- Sending requests from a plan (an API step). Only responses the page's own actions caused are read.
- Reading response headers other than `Set-Cookie` flags, or whole bodies.
- WebSocket frames.
- Changing the Phase 3 gate or its floors.

## Owner decisions
none recorded

## Priority: MVP
**Rationale:** The only one of the three stories that moves the measured accuracy, and the gate is what blocks Phase 3.

## Assumptions
- Playwright's response events give status, JSON body and `Set-Cookie` for requests that pass through Selvedge's guard proxy (the proxy forwards responses unchanged).
- Most of the 16 tuning cases are answerable this way; the planner notes say so, but nobody has re-planned them yet.

## Dependencies
- Depends on: none
- Blocks: the setup scout (it uses the snapshot's request list to find an app's API calls)

## Risks
- A JSON field could hold a secret; mitigated by reading only one named path and applying the existing redaction.
- The new step widens what a PR author's page can influence; mitigated by the lint (origin allowlist, must follow an action) and no request sending.
- Abstention may drop while false-PASS rises; the validation below checks both.

## Validation (must pass before merge)
1. **Static — selvedge's own gate:** `bash selvedge/tests/run.sh` passes, with new cases in `tests/test-plan-validate.sh` (the three lint refusals), `tests/test-run.sh` (401/200 PASS/FAIL, timeout → `no_value_read`, cookie value never in evidence, no extra request) and `tests/test-snapshot.sh` (request list, no bodies or query values).
2. **Running system — tuning run:** `node selvedge/eval/harness.mjs run --set tuning` on the new engine version writes a report to `selvedge/eval/results.json` in which `side_effect_not_observable` is below 16 of 72 and false-PASS is still 0 of 12 known-FAIL cases.

## Depends on
none

## Touches
selvedge/lib/plan-steps.mjs
selvedge/lib/plan-validate.mjs
selvedge/schemas/plan.schema.json
selvedge/lib/runner/steps.mjs
selvedge/lib/runner/execute.mjs
selvedge/lib/runner/evidence.mjs
selvedge/lib/verdict.mjs
selvedge/lib/comment-render.mjs
selvedge/lib/snapshot.mjs
selvedge/lib/snapshot-playwright.mjs
selvedge/prompts/planner.md
selvedge/agents/verifier.md
selvedge/README.md
selvedge/tests/test-plan-validate.sh
selvedge/tests/test-run.sh
selvedge/tests/test-snapshot.sh
selvedge/tests/fixtures/app-server.mjs
selvedge/eval/results.json
selvedge/CHANGELOG.md
selvedge/.claude-plugin/plugin.json
.claude-plugin/marketplace.json
