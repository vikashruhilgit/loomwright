# automate-speed/02 — Phase 4.5 spends its rounds on new defects: read CI once, run pin mutations once

## Status: pending

> Propose-only, from the timing analysis of run `automate-2026-10-13-181331` (item `verified-rule-checks`, PR #533).
> Promoted 2026-10-14 (owner); decisions resolved below. Merges the earlier drafts "CI red visible before drain" and "pin mutations run once" (owner,
> 2026-10-14: same problem, same file).

## Source
1. **Every item maxes Phase 4.5.** In `.supervisor/postmortem/results.jsonl` (`source: automate_drain`), every item
   since **2026-10-12** recorded `self_heal_rounds=3`, the maximum, including a 5-file/151-line PR. Before that, 0–1
   was common. The start date matches **6e8c757** (2026-10-11 22:48). That commit made the Phase 4.5 code reviewer
   run EVERY `## Pin mutations` row in a scratch copy on every review iteration (`agents/code-reviewer.md`, "Pin
   mutations (same EXECUTION DIRECTIVE gate)"). This is correlated by date, not A/B tested. On PR #533: 16 pin rows
   ⇒ ~32 suite runs per review, and the suite grew 56→74→106 assertions across fix rounds, so each review took longer
   than the last (7.5 → 10 min).
2. **A red CI went unread for three heal rounds.** GitHub `CI` concluded **failure** on every PR #533 push:
   `b62b67d` (16:34Z), `4edc602`, `9b43421`, `fc1e826` (17:55Z). It first went green on `698c56a` (19:47Z), the
   drain's round-1 fix. The cause was the static `scripts/check-locale-prefix.sh` gate plus a `pipefail` + `grep -q`
   defect in the suite. Phase 4.5 (16:53→17:52) never looked at CI. The owned drain then spent its whole first round
   (17:52→20:03, **2h11m**) fixing it plus two bot findings.
3. **Workers' "targeted tests" were a hand-typed list.** The worker and both fix workers ran suite lists written into
   their spawn prompts (owner rule 2026-10-12: background workers do not run the full `scripts/ci-local.sh`).
   `check-locale-prefix.sh` was on none of them, although `scripts/ci-local.sh --affected` already exists ("run only
   the suites mapped from the changed files + the early set").

## Depends on
none

## Touches
loomwright/agents/code-reviewer.md
loomwright/agents/worker.md
loomwright/agents/supervisor.md
loomwright/skills/self-heal-advisory/SKILL.md
loomwright/skills/async-orchestration/SKILL.md
loomwright/skills/supervisor-readiness/SKILL.md
loomwright/scripts/run-pin-mutations.sh
loomwright/scripts/test-run-pin-mutations.sh
scripts/ci-local.sh
scripts/test-ci-local.sh
AGENT_GUIDELINES.md
changelog.d/automate-speed-02-phase45-rounds.md

## Problem
Phase 4.5's review rounds are the expensive, LLM-driven part of every item. Today they spend that budget on work a
script does better and skip the cheapest signal available:
- **Pin mutations are mechanical** (apply a one-line edit, run one test, expect red). An LLM reviewer re-runs every
  row on every iteration, including rows whose code did not change, and the cost grows with the suite.
- **A red required check is the most certain finding there is**, and Phase 4.5 never reads it. It waits for the
  drain, after up to three review rounds.
- **CI-only gates are invisible to workers** because their test set is a list someone typed, not the project's own
  "affected" plan.

## Goal
Each Phase 4.5 round is spent on finding and fixing new defects. Mechanical checks run once per code state, by a
script. CI failures reach the first round's fix worker, and workers catch most of them locally first.

## Scope
1. **Pin mutations by script, once.** New `run-pin-mutations.sh <brief> [--root <checkout>]` parses the brief's
   `## Pin mutations` table. For each row, in a `mktemp -d` copy of HEAD: the pin must pass unmutated, the mutation
   must apply, and the pin must fail mutated. It prints `held` / `not_held` / `unverified (<reason>)` per row and
   exits 0 / 1 / 2. Every mutant is validated (non-empty, differs from the original, `bash -n` clean). It runs at the
   Phase 3 deterministic gate beside `verify-provides.sh`; a `not_held` sends the worker a retry, like an outputs
   gap. In Phase 4.5 it re-runs only rows whose protected file changed since the last verdict. The reviewer prompt
   receives the verdict lines as DATA and no longer runs rows itself. A `not_held` is still a BLOCKING finding.
2. **Phase 4.5 reads CI.** At the top of each review iteration, after the push settles, read the PR's required checks
   once with the drain's existing reader (`wait-for-checks.sh` / the review-heal check read — reuse it, do not
   re-implement), bounded per D2. Each red required check becomes one BLOCKING `new` finding carrying the failing
   step's log tail (as data, in the EXTERNAL_TEXT envelope), so the same round's fix worker gets it. Pending or
   unreadable CI raises no finding and stays the drain's job.
3. **One targeted command for workers.** Worker, Phase 4.5 fix-worker and drain fix-worker prompts say "run `bash
   scripts/ci-local.sh --affected`" (where the project has it) instead of a hand list. The owner rule stands: never the
   full pool from a background worker. `--affected`'s early set includes every `scripts/check-*.sh` step the CI
   `static` job runs (`.github/workflows/ci.yml`), and a test fails when the two drift.

## Owner decisions (resolved 2026-10-14)
- **D1 → keep fallback.** The reviewer applies a pin mutation itself ONLY for a row the script reports `unverified`;
  `held` / `not_held` rows are never re-run by the reviewer.
- **D2 → read once, no wait.** Phase 4.5 reads CI once per iteration; pending or unreadable raises no finding.
- **D3 → pass to drain.** A red required check the fix worker cannot clear (infra / `untrusted_infra` probe hit) is
  passed through to the owned drain unchanged, with a note — Phase 4.5 does not escalate on it.
- **D4 → no.** Per-claim scratch repros stay unchanged (out of scope).
## Acceptance criteria
- Given a brief whose pin rows all turn their pins red, when `run-pin-mutations.sh` runs, then every row reads `held`,
  exit 0. A row whose mutant stays green reads `not_held`, exit 1. A row whose mutation does not apply, or whose
  unmutated pin fails, reads `unverified`, exit 2.
- Given Phase 4.5 iteration 2 where no protected file changed, then no pin row is re-run and the reviewer prompt carries
  the previous verdicts; `agents/code-reviewer.md` no longer instructs the reviewer to apply mutations itself (except
  the D1 fallback).
- Given a PR whose required `CI` check is red at Phase 4.5 iteration 1, then that iteration carries one BLOCKING
  finding per red required check with its log tail, and the fix worker receives it. Pending or unreadable CI raises
  none.
- Given a change that breaks `check-locale-prefix.sh`, when a worker runs `ci-local.sh --affected`, then that gate runs
  and fails locally. A static gate in `ci.yml` missing from the early set fails `test-ci-local.sh`.
- Worker and fix-worker spawn templates reference `ci-local.sh --affected`, not a hand-written suite list.

## Validation (must pass before merge)
1. `test-run-pin-mutations.sh`, `test-ci-local.sh` and the self-heal seam tests; report `<passed>/<total>`.
2. Mutation controls: make the script skip the "must fail" re-run ⇒ the `not_held` leg goes red; drop
   `check-locale-prefix.sh` from the early set ⇒ the drift test goes red.
3. Running system: run `run-pin-mutations.sh` on PR #533's brief (`.supervisor/jobs/done/2026-10-13-verified-rule-checks.md`);
   paste the 16 verdict lines and wall-clock. Then a scratch PR with a deliberate locale-prefix violation; paste the
   Phase 4.5 iteration-1 CI finding.
4. After release: re-measure `self_heal_rounds` and Phase 4.5 duration in the ledger over the next 5 items.
5. Rollback: `git revert`.

## Non-goals
- Removing the executing review lens or the EXECUTION DIRECTIVE.
- Changing Plan Reviewer Criterion 19 (briefs still author pin rows).
- Running the full `ci-local.sh` pool from background workers.
- Merging or rerunning CI from Phase 4.5.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-14T09:04:32Z
- **Brief:** .supervisor/jobs/done/2026-10-14-automate-speed-02-phase45-rounds.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/538
