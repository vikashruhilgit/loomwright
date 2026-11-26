# Selvedge can check a criterion about the server's reply (status, body, session cookie), through the same guards as the browser

## Status: done
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/983 (selvedge 0.11.0; stamp corrected 2026-11-27)

> Phase 2 engine revision for `qa-split/00-plan.md` (rev 2). Decisions D5, D6, D7, D11, D12, D13; non-goals
> N5, N7, N8. Spends one of Phase 2's two engine revisions (time box about 2026-12-11). Drafted
> 2026-11-23 from the 0.10.0 tuning report; the three owner decisions below were approved 2026-11-23.

**As the** owner measuring Selvedge against the Phase 3 gate,
**I want** a plan step that sends one request to an allowed origin and reads its reply,
**so that** criteria written about an API (a status code, a JSON field, a session cookie) get a verdict
instead of NOT_VERIFIABLE `side_effect_not_observable`.

## Why (measured)

The 0.10.0 tuning run (`selvedge/eval/results.json`, set `tuning`; 72 cases, abstention 43/72) left 16
criteria as `side_effect_not_observable`. Their planner notes, required since 0.10.0, give the same
cause: each criterion is about a server reply no browser step can read. The criterion texts, grouped
by what they would need:

| Group | Count | Example | Needs |
|---|---|---|---|
| A — reply to an anonymous request | 7 | `GET /api/weather/forecast` without a session answers 401; signup with a bad email answers 400 with a message | this item only |
| B — sign in by request | 6 | `POST /api/auth/login` with the seeded admin's email and password succeeds with a session cookie | this item + test credentials in the eval workspace (08c) |
| C — reply to a signed-in request | 5 | a signed-in `GET /api/teams/<teamId>/players` answers 200 | this item + a session in the eval workspace (08c) |

(The planner listed 18; the report counts 16. The other 2 sit in plans of targets 007 and 008 that
failed the lint on other criteria and never froze, so the report counts them as BLOCKED `plan_invalid`.
Checked by comparing each run folder's `plan.json` with its `verdict.json`.)

The held-out set (0.9.0: 49 of 126 `side_effect_not_observable`) has not been read, and must not be:
it is the builder-blind set. So how far this moves the held-out number is unknown until a held-out run.

## Probe that fixes the design (run 2026-11-23, Playwright 1.65.1)

A local app plus a counting proxy, with the guarded context's shape (`context.route('**/*')` and a
launch proxy):

| How the request is sent | `context.route` sees it | proxy sees it | sends the context's cookies |
|---|---|---|---|
| `context.request.post(…)` (APIRequestContext) | **no** | yes, as `CONNECT host:port` only | yes |
| `fetch` inside the page (`page.evaluate`, runner-owned function) | yes | yes | yes |

`context.request` skips the route layer, so `remote_mutation_refused` (route-layer only) would not
apply to it, and over a tunnel the proxy cannot see the method either. **So the step is sent as a
`fetch` from inside the page**, never with `context.request`. An HttpOnly session cookie is not
readable from page code, but the runner reads it with `context.cookies()`.

## Scope

1. **One new step type, `request`** (`lib/plan-steps.mjs` STEP_TYPES / STEP_FIELDS, the schema, README):
   `{"type": "request", "method": "GET"|"POST"|"PUT"|"PATCH"|"DELETE", "url", "json"?}`.
   - `url`'s origin must be in `origins`, and equal to the origin of the page the criterion is on at
     that point (the last `goto` before it). The lint checks this: a cross-origin `fetch` would depend
     on the app's CORS policy, not on Selvedge.
   - `json` is a plain JSON object whose string leaves are literals or `{{NAME}}` (D11; the
     placeholder rule extends from `fill`/`select` values to `json` leaves). No headers field, no raw
     body, no code-like content (the existing CODE_LIKE_PATTERNS apply to every string).
   - A `request` whose method is not GET is an action (ACTION_TYPES), so rule 1 (a read after the
     last action) and the negative baseline rule apply to it unchanged.
2. **The executor** (`lib/runner/steps.mjs`, the one executor): runs a fixed, runner-owned function in
   the page with the method, URL and body passed as arguments, never as source text. It keeps the last
   reply on the criterion's run state: status, response text (capped, e.g. 64 KiB), content type. A
   guard refusal surfaces as the guard's reason (`host_not_allowed`, `remote_mutation_refused`) through
   `reasonOfResponse`, like `goto`.
3. **New read properties, no locator** (READ_PROPERTIES):
   - `response_status`: the number.
   - `response_text`: the body as text.
   - `response_json:<JSON Pointer>`: RFC 6901 pointer into the parsed body, e.g. `/0/createdBy/name`
     (string, number, boolean, or `null` when the pointer does not resolve; a non-JSON body is
     `no_value_read`).
   - `cookie:<name>`: never the value. It is a fingerprint (a sha256 prefix of the value), or `null`
     when the cookie is absent, so `changed_from` can compare before and after, and
     `expect matches` cannot be used to fish for a value.
   The existence rules extend to these reads: `cookie:<name>` alone cannot satisfy a positive
   criterion with `gt`, `contains ""` and so on (vacuousExpect), and "a cookie exists" needs
   `changed_from` from a baseline read.
4. **Lint** (`plan-validate.mjs`): the origin rule, a `read response_*` with no `request` before it in
   the criterion (`response_without_request`), the placeholder rule, and the README's PLAN_PROBLEMS list.
5. **Planner prompt**: a section on the request step with one positive and one negative example;
   `side_effect_not_observable` stays the reason only when neither a page nor a reply shows the effect.
6. **Snapshot prefix**: allow a GET `request` in a prefix, so the planner can look at a reply while
   planning (status and the first 2 KiB of the body appended to the snapshot output). A non-GET request
   in a prefix is refused (`prefix_mutation_refused`): the planner should not change the app while looking.
7. **Evidence and the comment (D13, N8)**: `response_text` and `response_json` reads are read values,
   so they are unpublished by default and redacted when `comment.read_values` is on. A request body
   is never written to evidence, only its keys. `cookie:` fingerprints are never shown.
8. **Tests** for every arm above, each red under its own mutation, plus a guard test that a
   `request` to an unlisted origin and a remote POST without `allow_remote_mutation` are refused by
   the route layer (the probe as a fixture).
9. **Release**: selvedge 0.11.0 (a new step type is a feature).

## Acceptance

- [ ] Given a criterion "GET /api/x without a session answers 401", when the planner plans it, then the
      plan is `goto` the origin, `request GET`, `read response_status`, `expect equals 401`, and the
      run derives PASS or FAIL from the status read.
- [ ] Given a `request` to an origin not in `selvedge.json`, when it runs, then it is BLOCKED
      `host_not_allowed` and the route layer records it (no request reaches the host).
- [ ] Given a remote origin with `allow_remote_mutation` off, when a plan's `request POST` runs, then it
      is BLOCKED `remote_mutation_refused`.
- [ ] Given a `read cookie:<name>`, then no evidence file, verdict, stdout line or comment holds the
      cookie's value.
- [ ] Given a `request` whose `json` has `{{PASS}}`, then the plan, evidence and comment never hold the
      value, and an unset `PASS` is BLOCKED `placeholder_unset`.
- [ ] Given the 0.11.0 tuning run, with the same settings as the 0.10.0 report (sonnet, 1 plan, 1 run per
      target), group A's 7 criteria get a PASS or FAIL verdict, and false-PASS stays 0 on the known-FAIL
      cases. Groups B and C are measured after 08c.

## Non-goals

- No new target (N5): requests go only to the web target's own allowlisted origins, from its page.
- No free headers, no raw body, no auth header field. Sessions come from D11's storage state only.
- No value carried from one reply into a later step (e.g. a teamId read then used in a URL). The
  planner reads the seeded value at plan time and writes it into the plan. Revisit only if measured.
- No `context.request`, and no Node-side HTTP client in the runner (the probe above).
- No change to the gate or the abstention cap (N7).

## 08c — eval-workspace credentials and session (separate item, eval-only)

Groups B and C need the eval target to carry what a real repo would: `auth.env` names for the seeded
admin's email and password (values from the sports-management seed, passed through the environment,
never committed), and an `auth_setup` hook so `selvedge run` loads a storage state. This changes the
harness and driver (`selvedge/eval/`), not the engine, so it is not an engine revision. Draft it after
08b's design is approved.

## Owner decisions (all three approved by the owner, 2026-11-23)

1. **D6 amendment:** add `request` to the closed step vocabulary (D6 lists seven types). Recommended:
   yes. It is typed data like the others, run by the one executor, and checked by the same guards.
2. **N5 reading:** a request to the web target's own origin counts as part of the web adapter, not a
   new target. Recommended: yes, because D17's adapter contract already includes "read structured state".
3. **Revision budget:** this uses Phase 2's first counted engine revision. A held-out run only counts
   once the known-FAIL floor (60) is met, which needs item 07's planted defects. Recommended: build
   08b, measure on tuning, and run held-out once the planted set lands.

## Rationale

The cheap fix (0.10.0) taught the planner to look on other pages. The tuning notes show the rest are
criteria about replies, not pages, so more page-hunting cannot recover them. Refusing them is honest,
but at 22% of the tuning set they alone exceed the 20% abstention cap.
