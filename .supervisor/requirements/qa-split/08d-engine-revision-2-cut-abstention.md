# Engine revision 2: cut held-out abstention from 45.5% to at most 20% — plan doc

## Status: done (index document — engine revision 2 shipped in #989 (0.12.0) and #990 (0.12.1); held-out report #992 met the Phase 3 gate on 2026-11-26)

## Why now
The first held-out report at the floor (selvedge 0.11.1, 2026-11-24, PR #988) missed the Phase 3 gate on
abstention alone: 107 of 235 (45.5%, 95% CI 39.0–52.1%) against a cap of 20%. False-PASS was 0 of 85
(95% CI 0–4.2%), so the safety half of the gate holds. False-FAIL was 4 of 150.

The measurement backlog allows Phase 2 **at most two engine revisions** and the two-revision rule
(`selvedge/eval/README.md`, "The Phase 3 gate") sends the owner to the §8 review if the next held-out
report also misses. So this is the last revision before that review: bundle the fixes, then run one
held-out measurement. Phase 2 is time-boxed to 3 weeks from 2026-11-20 (ends 2026-12-11).

**Target:** at most 47 abstentions of 235 (the cap is 20% of 235 = 47), i.e. remove at least 60.

## Where the 107 come from (held-out report, reasons only)

| Reason | Held-out | Tuning 0.11.0 (72 cases) | Item |
|---|---:|---:|---|
| `placeholder_unset` (needs a login) | 30 | 9 | 08c |
| `plan_invalid` | 23 | 6 | 08e |
| `material_assumption` | 21 | 6 | 08f |
| `side_effect_not_observable` | 19 | 1 | 08g (diagnose first) |
| `exploration_budget` | 6 | 1 | (none: watch) |
| `no_value_read` | 5 | 2 | 08f |
| `step_failed` | 3 | 0 | (none: watch) |
| `planner_failed` (tuning only) | 0 | 3 | (none: watch) |

Every cause below was read on the **tuning** side only (`$TMPDIR/selvedge-eval-work/tuning-0.11.0-b`).
The held-out runs' per-case output was not read and must not be.

## Causes found on the tuning side

1. **`plan_invalid`: there is no way to say "this text is absent".** `EXPECT_OPS` is `equals,
   contains, matches, gt, lt, changed_from`. For "the page does not show 14-day" the planner writes
   `matches "^(?![\s\S]*14-day)[\s\S]+$"`, and `existence_only_expect` correctly rejects it (it holds
   for any ordinary text). Seen in targets 008 and 014.
2. **`plan_invalid`: one bad criterion blocks the whole plan.** The lint fails the plan, nothing freezes,
   and every criterion on that target is BLOCKED `plan_invalid`, including the ones whose steps were
   fine. In tuning, 6 `plan_invalid` came from 2 bad criteria (3 criteria per target).
3. **`material_assumption`: JSON reads point at one index.** "Soccer is at index 3 of the data array"
   and "the seeded data has only one post" are both assumptions forced by a read that can only name one
   JSON pointer. The criterion means "some element has name Soccer" or "no element has a non-null
   contactEmail".
4. **`material_assumption` / `no_value_read`: requests cannot be probed while planning.** "I could not
   send a POST while planning", "I could not snapshot that reply", so the planner guesses body fields
   and reply pointers, then either declares the guess material or reads nothing.
5. **`side_effect_not_observable`: 19 held-out, 1 tuning.** The tuning run that showed it predates the
   57 planted tuning cases, which are the ones that look like the held-out planted set. No cause is
   known yet.

## Items

| Item | Delivers | Expected recovery (held-out, estimate) |
|---|---|---|
| 08c | eval-workspace credentials and session (already specified in `08b-…md` §"08c") | most of 30 |
| 08e | an `absent` expect op (text or JSON value does not contain X) with the `existence_only_expect` probe check applied to it; plan lint marks only the offending criterion BLOCKED and freezes the rest | most of 23 |
| 08f | JSON reads that search an array: `any` / `every` element where a field equals, contains or is null; planning-time probe of a request step against the local eval target | about half of 26 |
| 08g | rerun tuning on 0.11.2 (now 129 cases incl. 57 planted), read its `side_effect_not_observable` cases, then fix what they show | unknown until diagnosed |

Honest limit: the estimates add up to roughly 55–70 of the 60 needed. 08g is the swing item, so run it
**first** (one tuning run, ~1 h and ~8M planner tokens), before writing 08e/08f code, so the revision
covers its cause too.

## Order
08g diagnose → 08c, 08e, 08f (independent; can run in parallel) → 0.12.0 release → **tuning run** →
**one held-out run**. Do not run held-out between items: each held-out report of a new engine version
counts toward the two-revision rule.

## Also look at
- The 4 false-FAILs on held-out. Their case ids must not be read from the builder side. Look for false-FAILs
  on the tuning rerun instead; 0.11.0 tuning had none, so new ones there would point at the same cause.

## 08g result: tuning on 0.11.2 (2026-11-24, 129 cases)
Work dir `$TMPDIR/selvedge-eval-work/tuning-0.11.2`; report in `tuning-0.11.2.results.json` there (kept out
of the repo). False-PASS 0/45, false-FAIL 3/84, abstention 37/129 (28.7%): placeholder_unset 9,
plan_invalid 12, material_assumption 8, side_effect_not_observable 4, exploration_budget 2,
no_value_read 1, step_failed 1. Planner tokens 6.5M.

**`side_effect_not_observable` (4): the step vocabulary has no way to see these, not a runner bug.**
| Criterion (tuning) | What the planner could not express |
|---|---|
| GET /silent-cookie sets `selvedge_secret` HttpOnly | cookie attributes / response headers (a cookie read gives only a value fingerprint) |
| POST /api/login with a non-JSON body answers 400 | a raw (non-JSON) request body, or request headers |
| Tabbing through /controls never focuses a hidden button | a key press, and a read of the focused element |
| GET /api/teams/<id>/discussions names each creator | needs a login (401): **mis-labelled**, belongs to `placeholder_unset` / 08c |

**False-FAILs (3), each a different cause:**
1. *"Immediately after /slow loads, Price reads pending"*: the first read was `Price: pending` (right); the
   stable wait then re-read `Price: 42` and judged that. The stable wait is deliberate (it stops a
   read taken before a side effect lands from passing), but nothing lets a plan say "the state at load".
2. *"GET /control/expire-sessions answers … the text ok"*: `response_text` was `"ok\n"`, the plan said
   `equals "ok"`. DOM text reads come back trimmed; a reply body does not.
3. *"The public tournament API never returns registrants' emails or payment fields"* (real PR 407):
   no absence op, so the planner wrote a negative-lookahead regex; it slipped past `existence_only_expect`
   because it also required `"registrations"`, and it rejected the organisation's `contactEmail`. The
   planner even marked "contactEmail is not a registrant email" as a **material** assumption, yet the
   verdict was FAIL: `lib/verdict.mjs` applies `material_assumption` only to a match, never to a mismatch.

## Items after 08g (amended)
| Item | Adds |
|---|---|
| 08c | (unchanged) credentials; plus: a 401/403 with no credentials is `placeholder_unset`, never `side_effect_not_observable` |
| 08e | `absent` op + per-criterion invalidation (unchanged); plus: `existence_only_expect` also rejects a lookahead regex that carries a positive anchor |
| 08f | array-search reads + planning-time request probe (unchanged) |
| 08h (new) | step vocabulary: read response headers and cookie attributes; request with a raw body and headers; key press + read of the focused element |
| 08i (new) | false-FAIL fixes: `response_text` trimmed like DOM text; an opt-in "at load" read that skips the stable wait (positive `equals`/`contains` only); owner decision below on a mismatch under a material assumption |

## Owner decisions
- 2026-11-24: the residual exposure in public commit be589296 is **accepted**; no history rewrite.
  The commit shows that 2 of the 21 planted held-out groups have a criterion with
  `fail_on_known_pass` > 0. It shows no per-group split and no false-PASS. Later reports strip the
  per-group split of planted held-out groups (`withoutSplit`, 0.11.2).
- 2026-11-24: a mismatch under a `material: true` assumption is **NOT_VERIFIABLE material_assumption**,
  not FAIL (08i). The rule in `lib/verdict.mjs` moves above the mismatch check, so a guessed premise
  never yields a verdict either way. Expect fewer false-FAILs and a few more abstentions; the
  tuning run after 0.12.0 shows how many.

## Revisit when
The 08g tuning rerun shows `side_effect_not_observable` is not a Selvedge bug (e.g. a planted variant
whose side effect is genuinely invisible to a browser and one request): then those cases are
NOT_VERIFIABLE by design, and the owner decides whether the 20% cap or the set changes. Nothing in
the harness raises the cap.

## 0.12.0 tuning result (2026-11-25)

Tuning set, 129 cases, test accounts on (`SELVEDGE_EVAL_CREDENTIALS`, names only in meta):
false-PASS 1/45 (2.2%), false-FAIL 0/84, abstention 8/129 (6.2%; was 37/129 on 0.11.2).
Abstained: material_assumption 3, no_value_read 3, step_failed 1, stuck_screen 1. Flips 0.

**The false-PASS (sm-pr-406 parent e5f56c7, "GET /api/lfg never returns a poster's contact email,
phone or exact lat/long").** The bug is that the reply *includes* those keys; the only seeded post
has them as `null`. The plan read `response_json_each:/posts|/contactEmail` and expected `[null]`.
`responseJsonEach` (`selvedge/lib/runner/steps.mjs`) maps a missing field to `null`, so "the key is
returned, value null" (the bug) and "the key is withheld" (the fix) read the same text. The planner
saw the gap ("a post with email or phone was not available") but marked it `material: false`.
Cause: a lossy read the 0.12.0 vocabulary added, not the planner alone.

## 0.12.1 tuning result (2026-11-25, before the truncation fix)

false-PASS 0/45, false-FAIL 1/84, abstention 10/129 (7.8%). Abstained: placeholder_unset 5,
material_assumption 3, no_value_read 1, stuck_screen 1. Flips 0.

- **false-FAIL** (sm-pr-298 nd-org-page fix 49346ac): `response_text` of `/pdbva` (a Next.js page)
  was cut at 64 KiB and the org name came after the cut; `contains` judged the kept part. Fixed in
  PR #990 (68c1f65): every body read of a truncated reply reads no value.
- **placeholder_unset × 5** (variants pd-424e742e0b, pd-52435f0eae; sample-app, `env_names: []`):
  the planner wrote `{{TEST_USER}}`/`{{TEST_PASSWORD}}` as the 0.12.0 prompt tells it to when no
  name is listed. On 0.12.0 the same criteria used literal `demo` (the sample app takes any
  non-empty sign-in) and were judged. Planner variance on our own rule. Owner decision pending.

## 0.12.1-b tuning result (2026-11-26, commit 01702f2, proven-literal sign-in rule)

129 cases: false-PASS 0/45, false-FAIL 1/84, abstention 4/129 (3.1%). placeholder_unset fell 5 → 1
(the remaining one is a bearer-token criterion, not a sign-in). The one false-FAIL (sm-pr-363,
e04e7a33, admin sign-in): the `text` read uses innerText, which applies CSS `text-transform`, so the
page read "PLATFORM ADMIN" while the snapshot (DOM text) showed "Platform Admin" and the plan
expected that. Open: owner to decide fix-before-held-out.
