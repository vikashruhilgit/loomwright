# 03 — `gate-eval` resolves the merge conditions itself; `ctx.json` shrinks to what only the drain knows

## Status: pending

## Problem
`scripts/automate-helpers.sh` `gate_eval` (lines ~361–524) is "a pure decision over a context JSON describing
the 6 conditions"; `skills/automate-loop/SKILL.md:306,339` say "the loop pre-resolves the six conditions into
a ctx.json … re-runs `classify-risk.sh`". The loop is prose executed by the model. Every fail-CLOSED read in
the gate (`has()` + `type == "boolean"`, `!= "true"` ⇒ PARK) validates the SHAPE of values the model wrote; none
of them re-derives the value. Condition 6's "NO override" is true of the script and false of the system: a
`ctx.json` with `"high_risk": false` and no `classify-risk.sh` run merges. Same for `head_sha`/`ready_sha`,
`base`, `review_decision`, `unresolved_human_thread`, `protection_enforceable`, `checks_green`. The gate
already has `$GH` and (via `--root`) `git`; `test-automate-helpers.sh` already stubs `$GH` — the boundary
is simply on the wrong side.

## Goal
The sole merge executor computes, at gate time, every condition it can compute from ground truth; the caller
supplies only what the gate cannot see (the owned drain's result + termination reason, the rubric score
source). A model-authored value can no longer satisfy conditions 2, 3, 4, 5-checks, or 6.

## Scope
1. **`gate-eval <pr_url> <ctx.json> [--root <checkout>]`** — new resolution inside the function, each with the
   existing fail-CLOSED posture (any read failure ⇒ PARK with a named reason):
   - cond 2: `gh pr view <url> --json headRefOid,baseRefName` → `head_sha`, `base`; `ready_sha` stays a
     ctx input (the drain's claim) and must equal the live `headRefOid`; `base` must be `main`.
   - cond 3: `gh pr view --json reviewDecision` (null ⇒ `none`, error ⇒ `unreadable`) and the review-threads
     GraphQL query (exact query from `review-heal/SKILL.md` §U1(b)) → `unresolved_human_thread`
     (any unresolved thread whose first-comment actor is not in the trusted-actor set from item 01 ⇒ `true`;
     `hasNextPage` ⇒ `true`; error ⇒ `true`).
   - cond 4: `gh api repos/<o>/<r>/branches/main/protection` (404 ⇒ `false`; other error ⇒ unreadable ⇒
     PARK); `trust_unprotected` stays a ctx input (it is an operator flag).
   - cond 5 checks: `gh pr view --json statusCheckRollup` + required contexts (the discovery recipe in
     `review-heal/SKILL.md` §U2) → `checks_green`; `rubric_satisfied` becomes a FILE read: ctx carries
     `supervisor_result_path`, the gate parses `rubric_score: N/M` from that file (`N == M` ⇒ true; absent
     line ⇒ `na`; unreadable file ⇒ PARK).
   - cond 6: the gate itself runs `"$(dirname "$0")/classify-risk.sh" main <live head_sha> --root <root>`
     and reads `.high_risk` / `.reasons` — the ctx keys `high_risk` / `risk_reasons` are REMOVED and, if
     present, cause `PARK: ctx_carries_gate_owned_key` (a caller that still tries to hand the gate a verdict
     is refused, never trusted).
   - cond 1 / 1b: `drain_result` + `termination_reason` remain ctx inputs BUT must also match the
     `REVIEW_HEAL_RESULT` block in the file named by ctx `review_heal_result_path` (parse the YAML tail with
     the existing `result_block_parser.py` if it exposes a CLI, else a bounded grep); mismatch ⇒ PARK.
2. **ctx.json new shape** (document in the function header and SKILL §10): `{drain_result,
   termination_reason, ready_sha, trust_unprotected, review_heal_result_path, supervisor_result_path}`.
   Every other former key is refused (see above). `schema_version` on ctx is not a RESULT schema — no bump.
3. **`skills/automate-loop/SKILL.md` §10 + §1.5:** rewrite the six-condition prose to "the gate resolves it;
   the loop passes …"; delete the "loop contract (load-bearing)" paragraphs for `review_decision: none`,
   `rubric_satisfied: na`, `unresolved_human_thread: false`, `high_risk` — they are now gate-internal. Keep
   the invariant enumeration (§11) unchanged.
4. **Tests — `test-automate-helpers.sh`:** rewrite the gate cases against `$GH` stubs that answer each
   endpoint; keep every existing PARK reason reachable; add: ctx carrying `high_risk:false` ⇒
   `PARK: ctx_carries_gate_owned_key`; live `headRefOid` ≠ `ready_sha` ⇒ `PARK: head_sha_moved`; protection
   404 without `trust_unprotected` ⇒ `PARK: unprotected_branch`; rubric file `rubric_score: 6/7` ⇒
   `PARK: rubric_unsatisfied`; classify-risk stub returning `null` ⇒ `PARK: high_risk_diff`; all-green
   stubs ⇒ `MERGE` with the stub recording exactly one `pr merge --squash` call. **Mutation control:**
   comment out the classify-risk invocation → the all-green case must NOT merge (the test asserts the
   stub saw a classify-risk call).
5. **Docs:** `docs/RESULT_SCHEMAS.md` §SUPERVISOR_RESULT high-risk paragraph (points at the gate now),
   `commands/automate.md` Parameters prose, CLAUDE.md §"Failure-Mode Invariants" merge paragraph — one
   sentence: "the gate computes its own conditions; a caller cannot hand it a verdict", CHANGELOG, bump.

## Non-goals
No second merge path; no change to the five-surface grep; no change to `classify-risk.sh` rules; no
`--trust-*` for condition 6 (owner decision R5 stands).

## Acceptance criteria
- `gate-eval` with an all-green stub set prints `MERGE` and the stub log shows `classify-risk`, `pr view`,
  `branches/main/protection`, and the GraphQL threads query were each called.
- A ctx that includes `high_risk`, `risk_reasons`, `head_sha`, `base`, `review_decision`,
  `unresolved_human_thread`, `protection_enforceable`, `checks_green`, or `rubric_satisfied` ⇒
  `PARK: ctx_carries_gate_owned_key`.
- Every previous PARK reason string still exists and is exercised by a test.
- `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` → the same five surfaces.
- Full test loop + root checks green.

## Verified premises
- `gate_eval` body lines ~398–524; `J()` helper; `$GH`/`$JQ` env-overridable; test file stubs them.
- `review-heal/SKILL.md` §U1(b) GraphQL query text and §U2 required-context discovery.
- `classify-risk.sh <base> <head> --root <dir>` output object `{high_risk, reasons, …}`; `null` on
  unclassifiable.
- `automate-loop/SKILL.md` §10 lines ~306–349, §11 enumeration.
