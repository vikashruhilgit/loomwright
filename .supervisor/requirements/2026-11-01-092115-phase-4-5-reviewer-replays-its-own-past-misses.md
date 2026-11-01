# Phase 4.5 reviewer replays its own past misses before a reviewer change ships

## Status: pending

> From the 2026-11-01 review of Anthropic's "How the Claude Code team does code review"
> (https://claude.dev/blog/solving-code-review-at-anthropic/). There, past incident- and revert-causing PRs form a set
> run against the reviewer, and a prompt, tool or model change is kept only if the score goes up. Loomwright records
> its misses (`/pr-postmortem`, `self_heal_misses`, CI lens rounds) but never replays them, so a reviewer change can
> lower catch rate silently.

**As a** plugin owner who edits the code-reviewer prompt, the Phase 4.5 protocol or its model routing,
**I want** a repeatable suite that re-runs the Phase 4.5 reviewer on real PRs it once missed and reports how many it
now catches,
**so that** a prompt diet, split or model change that weakens the review is caught before it ships.

## Evidence (measured 2026-11-01, re-verify: main moves)

1. **Misses exist and are recorded.** `.supervisor/postmortem/results.jsonl`, 43 items since 2026-10-14: CI
   `claude-review` rounds > 0 on 19 items, so the CI lens found something after Phase 4.5 PASS/ESCALATED.
   `self_heal_misses > 0` on 3.
2. **The reviewer changes often.** It changed on main in this window with no catch-rate check: prompt diet and moved
   preloads (automate-speed/26, PR #634), protocol split (`cb9e69c`), routing (`4aefe4d`, `8d602e8`).
3. **No replay exists.** `loomwright/evals/` holds only `coordinator-model/`, which tests the `/automate` driver.
   Its harness (`claude plugin eval`, deterministic regex graders, a model-free `lib/selftest.sh`, a mutation-control
   case) is the pattern to reuse.

## Scope
- New `claude plugin eval` suite `loomwright/evals/phase45-reviewer/`. Each case stages ONE recorded miss in the
  sandbox: a scratch repo at the PR's base with the PR's pre-drain head applied (the last commit before the first
  drain or CI-lens fix). Then it runs the `loomwright:code-reviewer` agent with the Phase 4.5 spawn prompt for
  round 1, read from the plugin, never copied into the case.
- **Corpus builder:** a script picks cases from the postmortem ledger and git history: PRs whose later CI-lens or
  drain fix commit changed a file the pre-drain diff also changed. It writes each case's expected finding as
  `{file, severity floor}`. A human confirms each case before it is committed (the article's "confirmed by engineers
  who know the code"). Cases come only from this public repo's own merged PRs.
- **Controls:** at least two clean cases (merged, no CI-lens round, no revert) that measure noise. Their grader
  reports BLOCKING/HIGH findings on them as a separate noise number. It never fails the suite on noise alone.
- **Graders are deterministic:** a regex over the reviewer's `CODE_REVIEW_RESULT` block. A case is caught when a
  finding at or above the severity floor names the expected file. No LLM judge.
- **Selftest without a model:** `lib/selftest.sh` feeds canned reviewer outputs and proves the graders score a hit,
  a miss, a wrong-file finding and a below-floor finding correctly, plus one mutation-control case whose expectation
  is deliberately wrong and must FAIL. It runs in CI. The model-backed suite does not.
- **When it runs:** on demand, by one documented command, and named in `AGENT_GUIDELINES.md` as required evidence
  for a PR that edits `agents/code-reviewer.md`, `skills/self-heal-advisory/` or Phase 4.5 routing: the PR body
  carries the before/after caught count. It is never in GitHub CI (it spends the subscription cap; see the
  machine-level weekly-cap lesson).
- `docs/evidence/phase45-reviewer-replay.md`: the baseline run on the merge commit (caught / total, noise on
  controls, model, wall clock, cost from the token ledger).

## Acceptance criteria

**Happy path**
- [ ] Given the committed corpus, when the documented command runs on the current reviewer, then it prints caught /
      total, the per-case result, and the controls' noise count.
- [ ] Given a candidate PR from the ledger, when the corpus builder runs, then it prints the case's base sha,
      pre-drain head sha and expected `{file, severity floor}`, and writes nothing until the owner confirms.
- [ ] Given a PR that edits the code-reviewer prompt, when it is opened, then `AGENT_GUIDELINES.md` names the
      replay as required evidence and the PR body template has a line for the before/after count.

**Edge cases**
- [ ] Given a case whose base or head sha is no longer reachable, when the suite runs, then that case reports
      `UNSTAGEABLE` and is excluded from the denominator, never counted as caught.
- [ ] Given a reviewer reply with no parseable `CODE_REVIEW_RESULT` block, when it is graded, then the case is
      `MISSED (unparseable)`, never caught.

**Error scenarios**
- [ ] Given `claude plugin eval` is unavailable, when the command runs, then it exits non-zero naming the missing
      tool. It never prints a caught count.
- [ ] Given the selftest's graders are edited to always match, when CI runs, then the mutation-control case fails
      CI.

## Validation (must pass before merge)
1. `lib/selftest.sh` passes, and its mutation control fails as designed. It is wired into CI the way coordinator-model's
   is (a leg of an existing `test-*.sh`, or its own `loomwright/scripts/test-*.sh`).
2. The baseline evidence file is committed with real numbers from one model-backed run, and the corpus holds every
   case the owner confirmed (minimum agreed with the owner at Launch Pad).
3. `bash scripts/check-version-bump.sh` passes; `bash scripts/ci-local.sh --affected` is green.

## Non-goals
- A daily or CI-scheduled model run.
- Using the score as a merge gate. It is evidence the owner reads.
- Replaying the CI `claude-review` lens or the `/review-pr` drain.
- Shipping any finding prose outside this repo (telemetry rule: plugin facts only).

## Assumptions
- A pre-drain head can be identified from commit history for most candidate PRs. If too few qualify, the item parks
  with the count rather than padding the corpus with synthetic cases.
- One case's run fits the eval harness's timeout. Phase 4.5 reviews have taken 7–10 min with pin mutations, so
  cases run round 1 only, with the brief's pin-mutation block omitted.

## Risks
| Risk | Impact | Mitigation |
|---|---|---|
| Reviewer output varies run to run | noisy caught count | report per-case results; the PR evidence compares the same cases on both reviewers, and a 1-case swing is not a signal on its own |
| Cost per run | subscription cap pressure | on-demand only, round 1 only, corpus size agreed up front |
| Corpus reflects only this repo | blind to external-project misses | stated in the evidence file; revisit when external postmortem data exists |

## Depends on
none

## Touches
loomwright/evals/phase45-reviewer
loomwright/scripts/build-reviewer-replay-case.sh
loomwright/scripts/test-build-reviewer-replay-case.sh
docs/evidence/phase45-reviewer-replay.md
AGENT_GUIDELINES.md
.github/pull_request_template.md
changelog.d/phase45-reviewer-replay.md
