# --trust-unprotected works on private Free repos, and the gate still reads CI there

## Status: done
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/839

**Story: --trust-unprotected works on private Free repos, and the gate still reads CI there** (type: story)

**As an** owner running `/automate --auto-merge --trust-unprotected` on a private repo on GitHub Free,
**I want** the flag to cover GitHub's "protection needs a paid plan" refusal, with failing CI still stopping the merge,
**so that** the escape hatch works on the repos most likely to need it without merging red work.

Source: the "Related" section of GitHub issue vikashruhilgit/loomwright#829.

## Problem

Two defects in `gate_eval` (`scripts/automate-helpers.sh`) that only make sense fixed together.

**Condition 4 refuses the flag on these repos.** It treats only a 404 from the protection endpoint as unprotected; anything else parks `protection_unreadable` before `trust_unprotected` is read.

**Condition 5 passes without reading CI when there is no required list.** `checks_green` starts with `($req | length) == 0`, so an empty list is green whatever the rollup says. Today a 404 repo with the flag already reaches this. Fixing condition 4 alone would extend it to every private Free repo, where only the earlier READY would vouch for CI.

## Evidence (2026-11-05)

- **Reproduced, read-only,** on one of the owner's private repos: `gh api repos/<owner>/<repo>/branches/main/protection` exits 1 printing `{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.",…,"status":"403"}` then `gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)`.
- **Run directly:** the `checks_green` jq expression on `[{"name":"ci","conclusion":"FAILURE"}]` with `--argjson req '[]'` prints `true`.
- **Read:** condition 4 matches `*"404"*` against the whole of stdout and stderr, so any other error text that merely contains `404` also reads as unprotected.

## Goal

An explicit `--trust-unprotected` covers exactly the paid-plan 403. With no required list, condition 5 parks when the rollup shows a failing check. Every other protection error still parks, and condition 6 stays non-overridable.

## Scope

- **Condition 4:** the paid-plan refusal (HTTP 403 AND its "Upgrade to GitHub Pro" message) reads as not enforceable, so without the flag it parks `unprotected_branch` and with it continues. Any other 403 (a token scope, for example) still parks `protection_unreadable`.
- **Condition 4, the 404 match:** match the HTTP status rather than the bare substring, so an unrelated error containing `404` parks `protection_unreadable`.
- **Condition 5:** with an empty required list, any completed rollup check that did not succeed (`success`, `neutral` and `skipped` count as fine) or any still-pending check parks `checks_not_green`. This applies wherever the list is empty: the 404 path, the 403 path, and protection that only requires reviews. An empty rollup (no CI at all) still passes, since there is nothing failing to read.
- **No new condition and no new park reason:** the gate stays at seven conditions, so no surface restating that count changes.
- **Docs:** `skills/automate-loop/modes-and-merge-gate.md`, including one pointer from its safe-mode text to `resume.md`'s `### Merging one parked item`, written by the companion item in the same wave.

**Leave alone in this story (a companion item in the same wave owns them):** `scripts/automate-next-step.sh`, `commands/automate.md`, `skills/automate-loop/resume.md`, `docs/result-schemas/automate-run.md`, `docs/loop-inventory/automate-loop.md`.

## Non-goals

- Overriding condition 6 or 7 by any route.
- The `--merge-parked` entry and its staleness guard (the companion item `2026-11-05-192934-merge-one-parked-item-through-the-gate.md`).
- A new `ctx` key: both changes are self-resolved reads, and `gate_eval` stays self-resolving.
- Treating a repo with no CI as unsafe; that is a separate decision.

## Owner decisions (2026-11-05)

- Split out of #829's merge work and shipped together with it in one wave.
- The 403 fix does not ship without the condition 5 fix.

## Acceptance criteria

**Happy path:**
- [ ] Given a stubbed paid-plan 403 and `trust_unprotected: true`, when `gate-eval` runs with the other conditions holding, then condition 4 passes and the gate reaches `MERGE`.
- [ ] Given a stubbed paid-plan 403 and no trust flag, when `gate-eval` runs, then it prints `PARK: unprotected_branch`.
- [ ] Given a required list and green required checks, when `gate-eval` runs, then condition 5 behaves as it does today.

**Edge cases:**
- [ ] Given an empty required list and a rollup with one `FAILURE`, when `gate-eval` runs, then it prints `PARK: checks_not_green`, under both the 403 and the 404 path.
- [ ] Given an empty required list and a check still in progress, when `gate-eval` runs, then it prints `PARK: checks_not_green`.
- [ ] Given an empty required list and all checks `success`, `neutral` or `skipped`, when `gate-eval` runs, then condition 5 passes.
- [ ] Given an empty required list and an empty rollup, when `gate-eval` runs, then condition 5 passes.
- [ ] Given protection requiring reviews only and a failing check in the rollup, when `gate-eval` runs, then it prints `PARK: checks_not_green`.

**Error scenarios:**
- [ ] Given a 403 without the "Upgrade to GitHub Pro" message, when `gate-eval` runs with the trust flag, then it prints `PARK: protection_unreadable`.
- [ ] Given a 500 whose text contains `404`, when `gate-eval` runs with the trust flag, then it prints `PARK: protection_unreadable`.
- [ ] Given a genuine `Branch not protected (HTTP 404)` and the trust flag, when `gate-eval` runs, then condition 4 still passes (no regression).
- [ ] Given a high-risk diff, a 403 and the trust flag, when `gate-eval` runs, then it prints `PARK: high_risk_diff …`.

## Validation (must pass before merge)

1. **Static — the project's gates:** `bash scripts/ci-local.sh --affected` passes, including `check-doc-currency.sh`, `check-prompt-history-refs.sh` and `test-citation-drift.sh`; `bash scripts/check-version-bump.sh` passes, with a `changelog.d/` fragment and no hand-edited version.
2. **Running system — the stub matches GitHub's real refusal:** run the read-only `gh api` protection call on a private repo on GitHub Free, and confirm the test's stubbed 403 is the same text. The output goes in `docs/evidence/trust-unprotected-private-free.md` with the owner and repo name redacted, and `Verdict: PASS for Validation 2`.

### Priority
- [x] Phase 2 - Important but not blocking launch

**Rationale:** Studio's exit run uses a public repo, so this blocks nothing. It runs in wave 1 because it shares no files with the merge entry and closes a hole that entry makes easier to reach.

### Assumptions
- Failing `claude-review` (a billing block, or the weekly cap) now parks on repos with no required list. That is the correct direction: it fails toward a person. It is noisy on those repos until the cause clears.
- GitHub's refusal text is stable enough to match; if it changes, the gate parks `protection_unreadable`, which is fail-closed.

### Dependencies
- Depends on: none
- Blocks: none
- Should land with: `2026-11-05-192934-merge-one-parked-item-through-the-gate.md` (same wave, no shared files)

### Risks
- Condition 5 gets stricter for every existing empty-list `--auto-merge` user, which parks some runs that merged before. That is the point, so the changelog fragment must say it.

### Success Metrics
- On a private Free repo, a `--trust-unprotected` run with green CI merges, and one with red CI parks `checks_not_green`.

### Handoff
Ready for: `/launch-pad goal: ".supervisor/requirements/2026-11-05-192935-trust-unprotected-private-free-and-empty-checks.md"`, or the plan doc's `/automate --backlog` line.

## Depends on
none

## Touches
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-helpers.d/05-gate-eval.sh
loomwright/scripts/test-automate-helpers.d/06-gate-eval-tail.sh
loomwright/skills/automate-loop/modes-and-merge-gate.md
docs/evidence/trust-unprotected-private-free.md
changelog.d/trust-unprotected-private-free.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-07T09:40:22Z
- **Brief:** .supervisor/jobs/done/2026-11-06-trust-unprotected-private-free.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/839
