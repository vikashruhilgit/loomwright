# 03 — Keep the scoped check-wait under the 600 s foreground cap: a resumable `wait-for-checks.sh` with a persisted total deadline

## Status: parked — superseded by `.supervisor/requirements/implementation-quality/02-iq01-and-throughput-merged.md` (owner decision 2026-10-09: implementation-quality/01 + throughput/01–09 merged into ONE item / ONE PR; this file is kept as that file's Part source)

## Depends on
none

## Touches
loomwright/scripts/wait-for-checks.sh
loomwright/scripts/test-wait-for-checks.sh
loomwright/skills/review-heal/SKILL.md
loomwright/agents/review-pr.md
loomwright/commands/review-pr.md
loomwright/docs/PITFALLS.md
loomwright/scripts/retention-sweep.sh
loomwright/scripts/test-retention-sweep.sh
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/throughput-03-check-wait-under-bash-cap.md

## Problem
The drain's check-wait contract asks for a single foreground call that may run up to 1200 s. The host's Bash tool caps a foreground command at 600 s. Real CI already outlasts 600 s.

- **The contract** is in `loomwright/skills/review-heal/SKILL.md` §"Step U2.5", under "Bounded wait — MECHANIZED via `scripts/wait-for-checks.sh`": "a single **foreground, blocking** script call". The quote block below it reads: "Never run this wait in the background and never end the turn while waiting — under `claude -p` ending the turn ends the process and the drain dies with no result." The same sentence guards the confirming pass in §"Termination-only severity floor". The bound is "**Default sizing — 1200 s, measured, not guessed**". It is mirrored in:
  - the skill's flag table (`--check-wait-timeout N` … "default 1200");
  - `loomwright/commands/review-pr.md`'s flag table ("1200 (20 min)");
  - `loomwright/agents/review-pr.md` ("a single foreground, blocking call").
- **The cap.** The Bash tool's documented foreground limit is a 600000 ms maximum `timeout`. This repo already designed around it once, in `scripts/ci-local.sh`'s header for `--wait` (PR #438, commit 0cdf464): "default 540: under the 600 s a single agent tool call may block". The same header records what happens to a call that runs longer: "a full run takes ~10 min, so an agent's foreground call is moved to the background". Under `claude -p`, a backgrounded wait followed by a turn-end is exactly the death this script was written to prevent (`wait-for-checks.sh` header, "WHY THIS EXISTS").
- **Measured CI per push on PR #435.** Required `ci` check-run `started_at` → `completed_at`, from `gh api repos/vikashruhilgit/loomwright/commits/<sha>/check-runs`:

  | Commit | ci duration |
  |---|---|
  | 87f2205 | 11 m 31 s |
  | 3a1cf14 | 14 m 51 s |
  | 842cbe7 | 11 m 48 s |
  | 77fc06b | 13 m 32 s |
  | 783b00b | 11 m 57 s |

  Every one exceeds 600 s, so a single foreground call cannot cover even one push.
- **The workaround is manual.** The 2026-10-08 operator split each wait by hand. `.supervisor/handover-2026-10-09-to-9768c6f2.md` records it: "`wait-for-checks.sh`: two ≤580 s foreground calls on the same SHA (Bash 600 s cap)". Nothing in the skill tells a detached `review-pr-runner` (or the next operator) to do this. It has not yet killed a drain, but with CI at 11–15 min it will.
- **Root cause.** The script's only clock is in-process. The `wait-for-checks.sh` header says the bound is "tracked via the bash builtin `$SECONDS` (reset to 0 at script start)". So the total bound cannot be split across calls: a second call restarts the full budget, and a 1200 s call outlives the host cap.

## Goal
No single foreground `wait-for-checks.sh` call exceeds the host cap. The **total** bound per (PR, SHA, scope) is still honoured across calls (1200 s default, or the re-measured value). The fail-closed outcomes are unchanged: a total-budget timeout is the existing `ELAPSED` outcome, so the decision is still ESCALATED.

## Scope
1. **A resumable mode in `wait-for-checks.sh`.**
   - A per-call ceiling, e.g. `--call-max <s>`, capped at 570 s. Reuse PR #438's precedent: `ci-local.sh --wait`'s default of 540 s, a "STILL-RUNNING — call again" result, and exit 3 there.
   - The script then loops inside one call until the scoped set settles, the per-call ceiling is reached, or the total deadline passes.
   - **New outcome on the per-call ceiling, with budget left:** one final line such as `CONTINUE sha=<sha> remaining=<s> pending=<…>`. It keeps the one-line, always-exit-0 contract; the header states the new line kind beside `SETTLED`/`ELAPSED`.
   - **Without the new flag, the output is byte-unchanged** for every existing caller. That includes `automate-helpers.d/escalation.sh`'s snapshot call `--bound 0 --names`, the default line, and `--names` lines.
2. **Persisted total deadline, keyed on the same SHA.**
   - The first call for a (PR, `--sha`, scope = `--required-only` vs review-pattern) key writes an absolute deadline: epoch seconds, `date +%s`, BSD/GNU-portable. It is written to gitignored scratch, e.g. `.supervisor/check-wait/<key-hash>.json`. Reuse `drain-rounds.sh`'s `pr_hash` derivation (shasum → sha1sum → cksum fallback).
   - Continuation calls read that deadline and never reset it.
   - A **different SHA is a different key**: a new push starts a fresh 1200 s, matching the skill's "The bound starts the moment a fix is pushed".
   - **Fail-CLOSED on continuation.** If the state is unreadable or garbage on a call that claims to continue (e.g. an explicit `--continue` with no or garbage state), the call ⇒ `ELAPSED … pending=unreadable_deadline`. It never grants a fresh full budget, which would make the wait unbounded.
   - Missing state on a first call is normal: create it.
   - Register the new scratch directory in `retention-sweep.sh`'s `policy_rows` as an `exhaust` row, like `drain-rounds`, with a fixture in `test-retention-sweep.sh`.
3. **Skill loop (`review-heal/SKILL.md`).**
   - At **both** call sites (§U2.5 scoped wait and the confirming pass), the call becomes a foreground loop: call with `--bound <check_wait_timeout> --call-max 540`; on `CONTINUE`, call again immediately on the **same** `--sha`, as a new foreground tool call; stop on `SETTLED` or `ELAPSED`. Each call's tool `timeout` must be set ≥ call-max + one poll interval and < 600000 ms.
   - The "Never run this wait in the background…" sentence stays, and gains "…and a `CONTINUE` line is not a result: call again, never end the turn on it".
   - Add the Anti-Pattern: "a single wait call sized past the host's foreground cap".
   - The 1200 s sizing note keeps its measured justification. Update it to the PR #435 numbers above, since 3a1cf14's 891 s is near the note's own "if `ci` grows past ~900 s, raise the bound" threshold. Raise the bound only if the owner agrees; this item does not change the default by itself.
4. **Mirrors.**
   - `agents/review-pr.md`'s scoped-check-wait bullet: "a single foreground, blocking call" becomes "foreground, blocking calls, each under the host cap, looped on `CONTINUE`".
   - `commands/review-pr.md`'s `--check-wait-timeout` row: "total across calls".
   - `docs/PITFALLS.md`'s "A review-drain marker means 'dispatched'…" entry, whose "Fixed two ways" paragraph says "a single foreground, **blocking** script call": one clause.
5. **Unchanged:**
   - `required=unknown` ⇒ escalate;
   - SHA binding and the materialization guard;
   - AC3 (optional checks never block);
   - AC4 (elapsed ⇒ ESCALATED);
   - always exit 0;
   - the `GH`/`JQ` test stub seam.
6. **Token budget + vendor ratchet.** `review-heal/SKILL.md` is preloaded by `agents/review-pr.md`. The gate today reads `review-pr 39304 / 43235 OK 3931 headroom`. Re-measure with `bash scripts/check-token-budget.sh`; on a breach, raise per `prompt-token-budgets.json`'s `raise_rule` and update the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" `review-pr` row in the same edit. `wait-for-checks.sh` has a vendor-coupling allowance of 2 in `docs/vendor-coupling-manifest.json`. Write new comments vendor-neutral, so they do not add `claude` tokens. If that proves impossible, the manifest joins this item's Touches and its own measured-raise procedure applies.

## Acceptance criteria
- `wait-for-checks.sh --bound 1200 --call-max 540` against a stub whose required check stays IN_PROGRESS gives:
  - call 1 prints `CONTINUE … remaining≈660` within 540 s + one interval;
  - call 2 (same SHA) prints `ELAPSED …` within the remaining budget, not after another 1200 s.

  Tests use small numbers, e.g. `--bound 4 --call-max 2 --interval 1`, so the suite stays fast.
- A continuation whose required check settles green prints `SETTLED … required=green`. A new SHA starts a fresh deadline. Unreadable state on continuation ⇒ `ELAPSED … pending=unreadable_deadline`, never a fresh budget.
- Without `--call-max` (or the chosen flag), every existing `test-wait-for-checks.sh` case passes unmodified: the output is byte-identical, `escalation.sh`'s `--bound 0 --names` included.
- Mutation control: a copy of the script that resets the deadline on every call (re-writes state unconditionally) fails the "call 2 elapses within the remaining budget" case.
- Both skill call sites loop on `CONTINUE` with per-call `--call-max ≤ 570`. No prose anywhere still requires one call to cover the full bound (`grep -rn "single foreground" loomwright/` shows only updated wording). The agent, command and PITFALLS mirrors agree.
- `retention-sweep.sh` lists the new scratch dir, and its test covers it. `check-token-budget.sh` is OK. `check-vendor-coupling.sh` is OK.

## Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green.
2. The new continuation tests fail on the base commit (no `CONTINUE` line, `$SECONDS`-only bound) and pass on the branch. The mutation control fails as designed.
3. `bash loomwright/scripts/automate-helpers.sh plan-waves .supervisor/requirements/throughput/03-check-wait-under-bash-cap.md --lint` prints `Touches ok; Depends on ok`.
4. Operator follow-up, not a merge gate: on the next real drain, the transcript shows ≥2 foreground `wait-for-checks.sh` calls on one SHA with no tool call above 600 s, and a `SETTLED` reached across them.

## Non-goals
- Changing the 1200 s default or the 15 s poll interval (a separate measured decision, see Scope 3).
- Backgrounding the wait, or any notification/callback-based wait. Foreground remains the contract.
- Speeding up GitHub CI or `ci-local`.
- Changing `drain-rounds.sh`, the confirming pass's GREEN/RED/UNREADABLE mapping, or any READY/ESCALATED decision logic (item 01 owns the sub-floor decision).
