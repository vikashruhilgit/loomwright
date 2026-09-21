# 07 — CI trust: live infra probe on red required checks, fail-CLOSED (`ci_untrusted`), never a dated note

## Status: pending

## Problem
A required check can be red for reasons unrelated to the diff — the job never started (account billing/spending
block, ~2–4 s at startup), it was queued out and never assigned a runner (cancelled ~15 min), or the reviewer action
skipped itself and exited 0 (green with nothing posted). The `--until-mergeable` drain treats check conclusions as
ground truth: a never-ran red check is healed against as if it were a test failure, and a never-posted green is
trusted. The owner's original fix — a dated `CI trust` note in CLAUDE.md flagged stale after 7 days — was rejected
(decision H3): the owner's own records show such a note going wrong within hours ("worked at 11:59, blocked by
12:15"), and a note tells the drain nothing about THIS run.

## Goal
For every red REQUIRED check, the drain probes the run once and classifies it `untrusted_infra` when the evidence
says nothing ran; such checks are listed in `checks_untrusted[]`, surfaced in the notification, and the drain
terminates `ESCALATED` with `termination_reason: ci_untrusted` — it is NEVER excluded from READY-blocking and green
checks are NEVER re-classified. Nothing untrusted ⇒ field absent, behaviour byte-identical.

## Scope
1. **`loomwright/scripts/ci-run-probe.sh` (new, fail-safe, read-only):** input = a check-run's `detailsUrl`/run id +
   repo; output = one jq-built JSON object `{check, verdict: "ran"|"untrusted_infra"|"unknown", reason, steps_count,
   runner_assigned, annotation_match}` on stdout, always exit 0; `gh` missing/unauthenticated/rate-limited ⇒
   `verdict: unknown`. Evidence rules (any one ⇒ `untrusted_infra`): `steps_count == 0`; no runner ever assigned
   (`runner_name` null AND `started_at` null, or conclusion `cancelled` with 0 steps); an annotation or job
   `message` matching the fixed generic pattern list `account payments|spending limit|billing|quota|rate limit
   exceeded|workflow validation error|not started` (GitHub's own strings — no project, account or repo names).
   `unknown` is NOT `untrusted_infra`. ONE `gh api repos/<o>/<r>/actions/runs/<id>/jobs` call per red required
   check, bounded by `--max-probes 5` (default), no pagination. Test file `test-ci-run-probe.sh` with fixture JSON
   (steps 0 / real failing job / annotation match / gh absent).
2. **`loomwright/skills/review-heal/SKILL.md` §U2.5 Wait-For-Settled-Checks / §U4:** after the settled read, for
   each RED REQUIRED check run the probe. `untrusted_infra` ⇒ append to `checks_untrusted[]`, do NOT spawn a fix
   worker for it, do NOT count it as a finding, and — because the verdict of a required check is UNKNOWN, not
   green — the round cannot reach READY: when the only remaining READY-blockers are `untrusted_infra` checks the
   drain terminates `ESCALATED`, `termination_reason: ci_untrusted`, and the notification names each check and its
   reason ("re-run when infra is healthy: `gh run rerun <id> --failed`"). `ran` and `unknown` ⇒ existing behaviour
   unchanged. Green checks are never probed. State the invariant in the READY redefinition section: "an
   `untrusted_infra` required check is not green; READY is unreachable while one exists." `review-pr` budget
   1737 — re-measure.
3. **`loomwright/docs/RESULT_SCHEMAS.md` §REVIEW_HEAL_RESULT (v2 drain fields, OPTIONAL/additive):**
   `checks_untrusted: [{check: string, reason: string, run_id: string|null}]` — absent when empty; and extend the
   `termination_reason` enum with `ci_untrusted` (read every consumer of that enum first — `automate-helpers.sh`
   gate-eval cond 1b lists `converged|bound_hit|sub_floor_converged`; an unlisted value must PARK, not merge —
   verify the fail-closed arm handles the new value and add a test).
4. **`loomwright/scripts/automate-helpers.sh` gate-eval cond 1b:** `ci_untrusted` ⇒ PARK with reason
   `PARK: ci_untrusted` (fail-closed; no override). Test in `test-automate-helpers.sh`.
5. **`loomwright/commands/review-pr.md`** Parameters/outcome prose: name the new terminal reason (memory
   `agent-command-mirror-drift-on-fixes` — `check-command-sync.sh` does not cover it). `agents/review-pr.md`
   outcome restatement if it enumerates `termination_reason`.
6. **Docs:** CHANGELOG paragraph; version bump.

## Non-goals
No CLAUDE.md note, no date arithmetic (BSD/GNU `date` trap), no READY exemption, no change to which checks are
required (§U2 stays fail-CLOSED), no re-run triggered by the drain (`gh run rerun` is suggested to the human, never
executed — an unattended re-run under a billing block burns the same quota). Green-but-silent reviewer runs
(workflow-validation skip) are already covered by `no_review_lens_posted` / Earned Fallback Review — do not duplicate;
cross-reference it.

## Acceptance criteria
- `bash loomwright/scripts/ci-run-probe.sh` on fixture JSON with `steps_count: 0` ⇒ `untrusted_infra`; on a fixture
  with a real failed step ⇒ `ran`; with `gh` stubbed to fail ⇒ `unknown`, exit 0 in all cases.
- Drain fixture: one red required check probed `untrusted_infra` and nothing else open ⇒ `REVIEW_HEAL_RESULT`
  has `decision: ESCALATED`, `termination_reason: ci_untrusted`, `checks_untrusted` length 1; the notification text
  names the check. **Mutation control:** with the probe disabled, the same fixture must NOT produce `ci_untrusted`.
- A red required check whose probe says `ran` ⇒ behaviour identical to `origin/main` (trace in PR).
- No untrusted checks ⇒ `checks_untrusted` absent; block byte-identical to today's.
- `gate-eval` ctx with `termination_reason: ci_untrusted` ⇒ PARK; test asserts it.
- `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` → the same five surfaces;
  `grep -rn 'gh run rerun' loomwright/scripts` → 0 (suggested in prose only).
- `grep -nE 'date -d|date -j|stat -' loomwright/scripts/ci-run-probe.sh` → 0.
- `check-token-budget.sh`, full test loop + root checks green.

## Verified premises (re-check before starting)
- `review-heal/SKILL.md` §U2 (required-check discovery, fail CLOSED), §U2.5 (scoped wait), §"READY redefinition",
  §"Earned Fallback Review — no_review_lens_posted", §"Terminal states". No `gh run view` / jobs-API read exists in
  the skill today (grep 0).
- RESULT_SCHEMAS §REVIEW_HEAL_RESULT `termination_reason` enum + `checks_waited` field note; `automate-helpers.sh`
  gate-eval header listing cond 1b's accepted values.
- Owner's machine notes (global CLAUDE.md, 2026-09-21): billing block string, `steps_count`/`runner_name` as the
  first discriminators, mid-session trips, `claude-review` self-skip on workflow-file PRs.
