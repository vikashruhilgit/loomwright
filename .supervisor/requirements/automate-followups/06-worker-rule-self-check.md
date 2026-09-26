# 06 — Rules reach the WORK: the worker replays its stamped must-checks and records failures as `deviations`

## Status: pending

## Depends on
`six-phase-loop-gaps/01` (WORKER_RESULT `deviations`, **done**, PR #257) and `twin-loop/08`
(`rules-check.sh --if-stamped`, **done**, PR #267). Both already on `main` — no ordering constraint remains.

## Prior art — read before starting
`twin-remediation/03-mechanize-rules-tier1.md` (unrun, no status stamp) already frames this as Bet 6 Tier 1,
and its scope 3 is "confirm (and fix where prose-only) that worker Step-5 verify and Phase 4.5 actually RUN
the fast/local and full/integrated check subsets". **This item is the worker half of that scope, now
buildable because the stamp exists.** Honour 03's non-goal — "No new gating paths" — which this item does:
`deviations` is REPORT-ONLY and nothing here gates. Do NOT re-derive 03's classification table; if a conflict
appears, stop and escalate rather than choosing for the owner.

> **Origin (2026-09-26).** Same owner question as item 05. The worker is the one actor holding full context on
> the change *while the fix is still free*, and it is the one actor that never reads the store: it receives
> house rules as an **advisory prose paste** injected at spawn (`agents/supervisor.md` ~741 via the
> `async-orchestration` spawn contract, stamped "NEVER-gating") and runs nothing. Every violation it introduces
> therefore survives until Phase 4.5 at the earliest — one worker run plus one review round later.

## Problem
A convention that is already mechanized as a `must` rule with a `check`, and already authorized by a human on
this machine, is still not executed at the moment it would cost nothing to honour. The worker has:
- the diff in its own worktree,
- the context that produced it,
- and a `deviations` field, already validated and already fed to the Phase 4.5 reviewer lens (step 1g).

What it lacks is the one call that connects them.

## Goal
Before emitting `WORKER_RESULT`, the worker replays the human-confirmed `must`-rule checks and either fixes what
fails or declares it in `deviations`. No new gate, no new schema field, no new executor.

## Scope (recommendation, not pre-decided)

**(a) The call is `rules-check.sh --if-stamped` — repo-wide, unscoped, from the worktree.**
> **Do NOT add path scoping.** `rules-check.sh` "does NOT follow that routing and takes NO path arguments …
> That is a decision, not an oversight" — routing is an *emission filter* for advisory injection, execution is
> repo-wide. Worse, its arg loop **warns-and-ignores** anything unrecognized, so a worker that passed paths
> would silently run the full set anyway while believing it had scoped. Run the full must-set; it is
> deterministic and cheap.

**(b) It works from a worktree, which is why this is viable at all.** The stamp is keyed by the *physical*
`git rev-parse --git-common-dir`, which every linked worktree of one repository shares — "a set confirmed in the
main checkout replays in an `/automate` worktree of the same repo". A separate clone has its own key and stays
`unstamped`.

**(c) Failures become `deviations` entries under a new `rule:` convention prefix.** Prefixes are a *consumer
convention*, not a validation rule (an unprefixed entry reads as `other:` and is never rejected), so adding a
fifth prefix is non-breaking and needs no `schema_version` bump. Respect the existing bound: **at most 12
entries, each at most 200 characters** — report at most the first few failing rule ids plus a count, never one
entry per rule on a large store.

**(d) Fix-or-declare is a prompt contract, not a gate.** A failing stamped check the worker can fix, it fixes; a
failure it judges out of lane it declares. `deviations` stays **REPORT-ONLY** — it must not influence `status`,
`outputs_gap`, or any other validation rule, mirroring `out_of_lane`'s documented independence.

**(e) `unstamped` is silent.** No stamp on this machine ⇒ the replay reports nothing and the worker behaves
exactly as today. Enforcement must never depend on a machine having been stamped.

## Acceptance criteria
- [ ] With a valid stamp and a failing `must` check, the worker's `WORKER_RESULT` carries a `rule:`-prefixed
      `deviations` entry naming the rule id.
- [ ] With a valid stamp and all checks passing, `deviations` is **unchanged** from today (absent, or carrying
      only what the worker would otherwise report) — no "all rules passed" noise entry.
- [ ] Unstamped ⇒ byte-identical worker behaviour to pre-item, and **nothing executes**: asserted with a canary
      `check` that would create a file, proving the file never appears.
- [ ] A store with more failing rules than the bound allows ⇒ at most 12 entries, each ≤200 chars, with a count;
      `scripts/validate-worker-result.py` rule 10 accepts the result.
- [ ] `deviations` still never influences `status`/`outputs_gap` — a fixture with a failing rule and
      `status: complete` validates.
- [ ] Mutation control: removing the replay call makes the first AC produce no `rule:` entry.
- [ ] `check-contract-parity.sh` green (WORKER_RESULT MANIFEST row unchanged — no new field).
- [ ] The full test loop is green — BOTH `loomwright/scripts/test-*.sh` AND root `scripts/test-*.sh` plus
      `scripts/check-vendor-coupling.sh`.

## Out of scope
- Adding path scoping to `rules-check.sh` (explicitly refused above).
- Any new `WORKER_RESULT` field, or any `schema_version` bump.
- Making a rule failure block the worker — that decision belongs to item 07 (parked: `proposed/automate-followups-07-rule-enforcement-at-review-and-merge.md`).

## Risks
- **Worker prompt budget.** `agents/worker.md` took three consecutive raises during the hardening run
  (six/01, six/02, harness-port/01), each re-measuring headroom. Re-measure before adding prose;
  `check-token-budget.sh` fails CI CLOSED on an undeclared or exceeded budget.

## Verified premises (read at `main @ 4f681d0`, 2026-09-26)
- `agents/worker.md`: `grep -c -iE 'read-rules|\.agent/rules|house.rules|rules-check'` ⇒ **0**.
- `scripts/rules-check.sh` header: "This checker does NOT follow that routing and takes NO path arguments (see
  the Usage line below; the arg loop warns-and-ignores anything unrecognized). That is a decision, not an
  oversight."; `Usage:  rules-check.sh [--confirm] [--no-cmd] [--if-stamped]`; unrecognized argv ⇒
  `warning: ignoring unrecognized argument`.
- `skills/rules/SKILL.md` §8.1: keyed by the physical `git rev-parse --git-common-dir`, "so a set confirmed in
  the main checkout replays in an `/automate` worktree of the same repo; a separate clone has its own key";
  invalid/absent stamp ⇒ `[SKIP] all (unstamped)`, `Checks passed: 0/0`, exit 0, "the per-rule loop is not even
  entered".
- `docs/RESULT_SCHEMAS.md` WORKER_RESULT: `deviations: string[]` optional, additive, **no** `schema_version`
  bump (stays 2), "at most 12 entries, each at most 200 characters", prefixes `plan:`/`edge:`/`open:`/`test:`
  with unprefixed read as `other:` and "NEVER rejected for lacking a prefix", REPORT-ONLY, validated by
  `validate-worker-result.py` rule 10, consumed by `self-heal-advisory/SKILL.md` step 1g.
- `agents/supervisor.md` ~741: house-rules injection into the worker prompt is "ADVISORY / fail-safe /
  NEVER-gating", computed via `read-rules.sh` (args, never stdin), and a rule's `check` is DATA, never executed.
