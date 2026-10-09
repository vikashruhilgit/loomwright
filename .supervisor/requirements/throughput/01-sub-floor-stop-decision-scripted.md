# 01 — Script the sub-floor stop decision: a deterministic `continue | READY sub_floor_converged | ESCALATED` helper the drain calls instead of evaluating pseudocode

## Status: parked — superseded by `.supervisor/requirements/implementation-quality/02-iq01-and-throughput-merged.md` (owner decision 2026-10-09: implementation-quality/01 + throughput/01–09 merged into ONE item / ONE PR; this file is kept as that file's Part source)

## Depends on
none

## Touches
loomwright/scripts/drain-subfloor-decision.sh
loomwright/scripts/test-drain-subfloor-decision.sh
loomwright/skills/review-heal/SKILL.md
loomwright/agents/review-pr.md
loomwright/commands/review-pr.md
loomwright/docs/result-schemas/review-heal-result.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/throughput-01-sub-floor-stop-decision-scripted.md

## Problem
The drain's sub-floor termination rule exists **only as prose and pseudocode the model evaluates**, and on the last real run the model got it wrong. That cost a full extra round of about 33 minutes, and it also mis-recorded the result.

**Where the rule lives (all prose):** `loomwright/skills/review-heal/SKILL.md`:
- §"Step U4 — The bounded drain loop", in the pseudocode block just after `pushed_sha = capture_head_sha()`. This is the `sub_floor_eligible = (required_failing == []) and (needs_human == []) and (auto_fixable != []) and all(severity_rank(f) < severity_rank(severity_floor) for f in auto_fixable)` test. It is followed by the `confirming_required_check_pass(pushed_sha, required)` call, the `rules_after = rules_gate_read(<checkout>)` re-read, and the three-way branch: READY `sub_floor_converged`, a fall-through to the next round, or ESCALATED on RED/UNREADABLE.
- §"Termination-only severity floor (`sub_floor_converged`)", including its blockquote "PINNED SEMANTICS — reading B (fix-then-stop) only; reading A (find-then-defer) is FORBIDDEN".
- §Anti-Patterns, entry "\"Find-then-defer\" (reading A) for `sub_floor_converged`".

**No script makes this decision.** The scripts each do one smaller job:
- `loomwright/scripts/drain-rounds.sh` only counts rounds (`init`/`bump`/`check`/`read`, per its header).
- `loomwright/scripts/wait-for-checks.sh` only reports settlement. Its header says: "it never decides drain readiness itself".
- `loomwright/scripts/automate-helpers.sh` `gate-eval` only *reads* the outcome afterwards (the "Condition 1b — a `sub_floor_converged` READY is NOT auto-merge-eligible" block).

**Measured misapplication.** The evidence is run `.supervisor/automate/automate-2026-10-08-121222.md`, PR vikashruhilgit/loomwright#435, the owner-requested fix-now re-drain.
- `## Progress`: "15:08:30Z owned drain started (fix-now re-drain …) @ 842cbe7" → "16:41:29Z fix-now re-drain READY (sub_floor_converged, 2 rounds, 2 fix cycles 77fc06b/783b00b, confirming pass green on 783b00b)".
- **Round 1 (scan on 842cbe7) met every eligibility condition:**
  - required `ci` on 842cbe7 was SUCCESS at 15:20:18Z (`gh api …/commits/842cbe7…/check-runs`);
  - `remaining_issues: 0` and `rules_gate: none`;
  - the round's only validated finding was LOW: the Darwin `CLICK_ACTION` mirror in `lane-park-notify`, listed with `severity: LOW` in the sidecar's `sub_floor_fixed`;
  - it was fixed in 77fc06b.
- **The confirming required-check pass on 77fc06b would have returned GREEN.** `ci` on 77fc06b completed SUCCESS at **16:08:41Z**. By the pseudocode, the drain ends READY/`sub_floor_converged` there.
- **Instead, a second round ran.** It re-scanned and fixed one more LOW: `last_counted_mark()` scanning the whole log, fixed in 783b00b. READY came at 16:41:29Z, **32 m 48 s later than the rule allows.**
- Honest note: that second round found a real LOW. The skill accepts that trade-off in so many words, in §"Termination-only severity floor", paragraph "The residual (R2 — the honest cost)". That paragraph says it "accepts that a finding round N+1's re-scan would have *discovered* … is never found". So the extra round broke the contract. It was not a quality win the contract failed to allow.

**Bookkeeping drift in the same run.** `.supervisor/automate/automate-2026-10-08-121222.review-heal-result.md` has `sub_floor_fixed:` listing **both** rounds' findings: the Darwin `CLICK_ACTION` fix (round 1) and the `last_counted_mark()` fix (round 2). The schema says otherwise. `loomwright/docs/result-schemas/review-heal-result.md` (the file `docs/RESULT_SCHEMAS.md` §REVIEW_HEAL_RESULT points to), in its field table's `sub_floor_fixed` row, says the field holds only the findings "fixed … in the final, un-re-scanned round". The pseudocode agrees: `sub_floor_fixed += auto_fixable` sits only inside the terminal READY branch. A model building the block by hand drifted from both.

**Root cause.** A multi-clause, fail-closed decision is left to the model to evaluate across a long loop, under time pressure. Nothing mechanical checks it. The repo already mechanized the neighbouring decisions for this exact reason:
- the round ceiling, in `drain-rounds.sh` ("an executable ledger, not a prose-tracked variable", §U4's "Mechanized bound" note);
- the wait, in `wait-for-checks.sh` (red-team-hardening item 04).

The stop decision is the remaining unmechanized piece.

## Goal
On the round's real inputs, the drain's sub-floor stop decision is printed by a deterministic, tested script, and the model only acts on its one output line. `sub_floor_fixed` comes from that script's output, so it can hold only the final round's findings. The decision **semantics are unchanged**.

## Scope
**Owner decision (binding, 2026-10-09).** Reading B stays: every validated finding at every severity is still **fixed** in its round (§U3.5 Validate-Then-Fix, unchanged). Batching sub-floor findings into follow-ups is **dropped**, because that is the forbidden reading A. This item changes *who evaluates* the existing rule (script, not prose), not the rule itself.

1. **New script `loomwright/scripts/drain-subfloor-decision.sh` (NEW), plus `loomwright/scripts/test-drain-subfloor-decision.sh` (NEW).** It is a separate script, not a `drain-rounds.sh` subcommand. `drain-rounds.sh` is a per-PR, stateful, deliberately jq-free ledger. Its header's `read_field` is "dependency-free (no jq requirement)", and its four subcommands only store and compare an integer. This decision is a stateless pure function over structured findings, and needs `jq` the way `wait-for-checks.sh` does. If, after reading both, the implementer finds the subcommand route cleaner, record why in the PR body.

   The script has two calls, matching the two points where the pseudocode decides:
   - **`eligible`.** Input: the round's classified `required_failing`, `needs_human`, `auto_fixable` (each item carrying its `severity`), and `severity_floor`. Output: `confirm` (run the confirming pass) or `continue` (normal next-round bookkeeping). It implements the `sub_floor_eligible` expression exactly, with `severity_rank` as defined under the U4 pseudocode (`BLOCKING > HIGH > MEDIUM > LOW`, "below" = strictly lower).
   - **`decide`.** Input: the same round inputs, plus the confirming pass's one `wait-for-checks.sh … --required-only` output line, the `rules_after` verdict, `rules_failed_seen`, and `checks_ever_fixed`. Output: exactly one of:
     - `READY sub_floor_converged`, plus the `sub_floor_fixed` JSON, which is **this round's `auto_fixable` only**;
     - `continue`, for GREEN with the rules clause not holding (the pseudocode's `elif outcome.result == "GREEN": pass` fall-through);
     - `ESCALATED`, plus `repeat_check_failure=<bool>` per AC13 (RED whose failing names intersect `checks_ever_fixed`).

     It mirrors the pseudocode's AFFIRMATIVE READY test: `GREEN and not (unstamped and rules_failed_seen) and verdict in RULES_PASSABLE`.
2. **Fail CLOSED, never READY on unknown input:**
   - **`eligible`:** missing, unreadable or malformed input, a finding with absent or unrecognized severity, or an unknown floor ⇒ `continue`. This is the conservative path: a full next-round re-scan, which can never yield a false READY.
   - **`decide`:** a missing or unparseable wait line, `required=unknown` (per §U2's fail-CLOSED rule, quoted in the confirming-pass block: "anything other than exactly 'green' is RED"), an `ELAPSED` line, or a sha mismatch ⇒ `ESCALATED`. This matches the skill's existing rule: "never `READY` on a red or unknown SHA".
   - **Exit codes:** state them in the header, like `drain-rounds.sh`'s `check`. No path prints READY on an exit other than the documented success.
3. **`review-heal/SKILL.md` calls the script.**
   - In §U4, replace the model-evaluated `sub_floor_eligible = …` expression and the three-way branch with the two script calls and a one-line "act on the printed line" contract. Keep the AC12 earned-fallback proof comment (it argues about the inputs, not the evaluator) and the `drain-rounds.sh bump` placement.
   - §"Termination-only severity floor" keeps the PINNED SEMANTICS block and the R2 residual verbatim, and names the script as the mechanization (pattern: "MECHANIZED via `scripts/wait-for-checks.sh`").
   - The §Anti-Patterns reading-A entry stays.
   - Add one Anti-Pattern: "deciding sub-floor termination in prose instead of from `drain-subfloor-decision.sh`'s line".
4. **`sub_floor_fixed` bookkeeping fix.** The emit step takes `sub_floor_fixed` from `decide`'s READY output, never from a hand-accumulated list. Add one clarifying sentence to the `sub_floor_fixed` row of `docs/result-schemas/review-heal-result.md`: final round only; earlier rounds' fixes are counted in `issues_fixed`/`fix_cycles`, not listed here. `schema_version` stays 2. The field stays additive/optional.
5. **Mirrors.** `agents/review-pr.md`'s "Termination-only severity floor" bullet and `commands/review-pr.md` §5 "READY terminal state" each gain a pointer to the script (authority stays the skill, "not restated here"). Check the agent↔command mirror in the same commit.
6. **Token budget.** `review-heal/SKILL.md` is preloaded by `agents/review-pr.md` (`skills: [review-heal, quality-checklist]`). Today's gate reads `review-pr 39304 / 43235 OK 3931 headroom`. Re-run `bash scripts/check-token-budget.sh` after the edit:
   - a net shrink or growth within headroom ⇒ no raise;
   - a breach ⇒ a measured raise in `docs/prompt-token-budgets.json` per its `raise_rule`, **plus** the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" `review-pr` row in the same edit (the gate fails closed on a drifted mirror).
7. **Unchanged, explicitly:**
   - `automate-helpers.sh gate-eval` condition 1b: `sub_floor_converged` stays never auto-merge-eligible. Do not touch it.
   - `wait-for-checks.sh`'s output contract.
   - `drain-rounds.sh`.
   - The default `--severity-floor HIGH`.

## Acceptance criteria
- `drain-subfloor-decision.sh eligible|decide` exists, with its decision table in its header. The §U4 pseudocode no longer contains a model-evaluated `sub_floor_eligible` expression or READY/ESCALATED branch; it calls the script and acts on its single line.
- **Replay of the 2026-10-08 round 1 (fixture):**
  - `required_failing=[]`, `needs_human=[]`, `auto_fixable=[{Darwin CLICK_ACTION, LOW}]`, floor `HIGH` ⇒ `eligible` prints `confirm`;
  - with `SETTLED sha=77fc06b… required=green review_producing=settled` and rules `none` ⇒ `decide` prints `READY sub_floor_converged` with `sub_floor_fixed` holding exactly that one finding.
- Table-driven tests cover every row:
  - a HIGH or MEDIUM-at-floor finding ⇒ `continue`;
  - `required_failing != []` or `needs_human != []` ⇒ `continue`;
  - `auto_fixable == []` ⇒ `continue`;
  - `required=red` ⇒ ESCALATED, plus `repeat_check_failure=true` iff the failing name is in `checks_ever_fixed`;
  - `required=unknown`, `ELAPSED`, sha mismatch, empty or garbage line ⇒ ESCALATED;
  - GREEN + rules `fail`/`unresolved`/`unreadable`, or `unstamped` with `rules_failed_seen` ⇒ `continue`;
  - garbage or missing `eligible` input or unknown severity ⇒ `continue`.
- **Mutation control:** two mutants are run against COPIES of the script, never the file on disk (the `test-add-orientation.sh` "MUTATION CONTROLS" pattern). Each must turn at least one case red:
  - `<` → `<=` in the severity comparison;
  - dropping the `required=green` requirement.
- The emitted `REVIEW_HEAL_RESULT.sub_floor_fixed` on a two-round drain lists only the final round's findings (fixture). The schema row states it.
- `gate-eval` cond 1b is byte-unchanged (`git diff` shows no hunk in that block). `bash scripts/check-token-budget.sh` is OK. Mirrors agree.

## Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green (the new `test-*.sh` is picked up by the suite glob).
2. The new tests fail on the base commit: the script is absent and the replay fixture has no decider. The two mutation controls fail as designed.
3. `bash loomwright/scripts/automate-helpers.sh plan-waves .supervisor/requirements/throughput/01-sub-floor-stop-decision-scripted.md --lint` prints `Touches ok; Depends on ok`.
4. Operator follow-up, not a merge gate: on the next real drain that ends `sub_floor_converged`, the `## Progress` READY line's round count equals the first eligible round with a GREEN confirming pass.

## Non-goals
- Changing reading B, the default severity floor, or Validate-Then-Fix. Every validated finding is still fixed.
- Deferring or batching sub-floor findings into follow-up drafts. This is reading A, explicitly dropped by the owner.
- Making `sub_floor_converged` auto-merge-eligible, or any change to `gate-eval`.
- Mechanizing the rest of §U4 (channel scan, validation, fix dispatch). Only the stop decision is in scope.
- Shortening CI or the per-round wait. That belongs to items 02/03 and others.
