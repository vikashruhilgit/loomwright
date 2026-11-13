# The drain honours a named required-checks set on a base branch that cannot be protected

**Story: the drain honours a named required-checks set on a base branch that cannot be protected** (type: story)

**As an** owner running `/automate` or `/review-pr --until-mergeable` on a private repo on a free GitHub plan,
**I want** to name the checks that gate READY once, in `.supervisor/config.json`,
**so that** a check that is red for a reason no code fix can reach (a deployment integration failing on the git author's permissions) stops blocking READY forever, while the checks I named still have to pass.

Source: GitHub issue vikashruhilgit/loomwright#805 (seen on v17.26.0, 2026-11-02).

## Problem

When the base branch's required-check list cannot be read, the drain has nothing that says which checks count. Its only routes all fail:

- **No list and no flag:** `rh_required` in `scripts/review-heal-next-step.sh` escalates `required_checks_unavailable` before any review.
- **GitHub's paid-plan refusal** (added 2026-11-06, `631886f`): `required_mode no_required_list`, so every non-neutral check blocks READY.
- **`--required-checks all-non-neutral`**, the only value the flag accepts: the same rule. The flag parser refuses anything else.

Under the last two, a check that is red for a non-code reason blocks READY for good. The drain correctly spawns no fix worker for it, so READY is unreachable. `/automate` passes no `--required-checks` to any drain (fresh-phase, inline or lane), and no config key exists, so a repo has no way to fix this from inside itself.

## Evidence (read on origin/main `0c83614`, 2026-11-12; nothing was run)

- `review-heal-next-step.sh`, the `--required-checks)` arm of the flag parser: refuses every value except `all-non-neutral`.
- `rh_required`: the three branches above, in that order: `protected`, then `all-non-neutral`, then the paid-plan `no_required_list`, else `required_checks_unavailable`.
- `rh_read` (the READY read): `required_names == null` ⇒ every non-NEUTRAL, non-SKIPPED rollup check is required.
- `wait-for-checks.sh` reads protection itself (its own `gh api …/protection` call and `no_required_list` flag). The drain's choice does not reach it today, and the confirming pass calls it with `--required-only --names`.
- `drain-gh-read.sh required-checks` now unions classic protection with active rulesets (#874). Classic 404 plus an unreadable ruleset read exits 1. **Not verified:** whether the issue's exact case (classic 404, rulesets paid-plan 403) lands in `no_required_list` or `required_checks_unavailable` on today's main. AC 9 pins it instead of assuming.
- `automate-lanes.d/create.sh` copies the primary's `.supervisor/config.json` into each lane clone (`cp -p`), so a config key reaches every lane drain with no new plumbing.
- `gate_eval` condition 5 (`automate-helpers.sh`) reads protection itself. With an empty list it reads the whole rollup (#839) and stays untouched here.

## Goal

A repo can declare `required_checks: ["<name>", …]` in `.supervisor/config.json`, or pass `--required-checks name:<a>,<b>`. When, and only when, branch protection cannot supply a required list, the drain waits on and gates READY on exactly that set. A named check that is missing or never reports still fails closed. Readable protection always wins. The merge gate never reads the set.

## Scope

1. **The flag form.** `--required-checks name:<a>[,<b>…]` alongside `all-non-neutral`. Names are exact check-run / status-context names. Empty names, an empty list, or a malformed value is a usage error (exit 2, as the parser does today).
2. **The config key.** `.supervisor/config.json` `.required_checks`: a non-empty array of non-empty strings. A present but malformed value (not an array, empty, or a non-string member) ⇒ ESCALATED `required_checks_unavailable`, with the message naming the malformed key. A bad declaration is never silently ignored.
3. **Precedence in `rh_required`.** Readable protection (`protected`) > the `--required-checks` flag (`name:` or `all-non-neutral`) > config `required_checks` > the paid-plan `no_required_list` > `required_checks_unavailable`. The new mode is recorded as `required_mode named`, with `required_names` = the set.
4. **The wait honours it.** `wait-for-checks.sh` takes the named set from the drain (a new argument; its form is the implementer's choice, documented in the script header). It uses that set instead of its own protection read only when that read yields no list. This covers both the scoped wait and the confirming `--required-only` pass. A named check absent from the rollup is not green.
5. **Absent never becomes READY.** A named check that never appears on the head SHA within `--check-wait-timeout` ⇒ ESCALATED `required_check_absent <name>`, a new escalation reason distinct from `check_wait_elapsed`, so the owner can tell a typo from a slow check.
6. **`/automate` needs no new plumbing.** The fresh-phase drain, the inline drain and every lane drain all run `review-heal-next-step.sh` against their own `$ROOT/.supervisor/config.json`, and lane clones copy that file. Tests prove each path reads it (Acceptance, `/automate` paths).
7. **Surface it in `/setup base-branch status`** (`scripts/setup-base-branch.sh`), the module that already reads the base branch. It adds one advisory line when the base's required list is unreadable and `required_checks` is unset: "base branch has no readable required-check list and no `required_checks` set — every drain will gate READY on every non-neutral check (or escalate)", plus the fix line. It is read-only, and its exit status is unchanged.
8. **Docs, updated in the same change as the behaviour** (house rule: a restating copy moves with its authority): `skills/review-heal/SKILL.md` (§U2 discovery and the flag table), `commands/review-pr.md` and its mirror `agents/review-pr.md`, `docs/result-schemas/review-heal-next-step.md` (`required_mode` values), `docs/result-schemas/review-heal-result.md` (the new escalation reason), and `docs/loop-inventory/review-heal.md`. Token-budget entries rise only where a measured doc outgrows its ceiling.

## Non-goals

- **The `--auto-merge` gate.** `gate_eval` never reads `required_checks`. A repo-local file must not lower the merge bar. On these repos the gate already parks `unprotected_branch`, or under `--trust-unprotected` reads the whole rollup (#839), so a red deployment check still parks a merge. That is intended.
- **A `/automate --required-checks` flag** or a `## Run Config` field. The config key already covers sequential, `--parallel N` and single-lane runs; a second route is a second thing to keep in sync. (The issue listed it as optional.)
- **`/loomwright:doctor`** (#803, still open). Only `/setup` gains the line.
- **Supervisor Phase 4.5's `phase45-ci-read.sh`** and the lanes readiness report (`automate-lanes.d/readiness.sh`, which uses `gh pr checks --required`). Both are advisory readers that print nothing or NOT-RUN when no list exists; they block nothing.
- **Narrowing readable protection,** including protection that requires reviews only (a readable, empty list): protection wins and the config set is ignored there.
- **Re-syncing a lane's config copy** after the lane was created.

## Owner decisions

- 2026-11-12: write the requirement for #805 at the size estimated in session (one PR; the gate excluded).

## Acceptance criteria

**Happy path:**
- [ ] 1. Given protection unreadable and config `required_checks: ["Unit Tests"]`, and a rollup with `Unit Tests` SUCCESS and a deployment check FAILURE, when the drain runs, then it waits only on `Unit Tests` (plus review-producing checks, as today), records `required_mode named`, ignores the deployment check, and can reach READY.
- [ ] 2. Given the same and `--required-checks name:Unit Tests,Lint`, when the drain runs, then the flag's set wins over the config's (`Lint` is required).
- [ ] 3. Given the confirming pass on a pushed fix commit under `required_mode named`, when it runs, then it confirms only the named set, not every non-neutral check.

**Edge cases:**
- [ ] 4. Given readable protection requiring `ci` and config `required_checks: ["Unit Tests"]`, when the drain runs, then the required set is exactly `["ci"]` with `required_mode protected`. The config set is neither added nor substituted.
- [ ] 5. Given readable protection with an empty required list (reviews only) and the config set, when the drain runs, then the config set is ignored (protection wins).
- [ ] 6. Given protection unreadable, config set, and `--required-checks all-non-neutral`, when the drain runs, then the flag wins (`required_mode all-non-neutral`).

**Error scenarios:**
- [ ] 7. Given `required_checks: ["Unit Tests"]` and a head whose rollup never shows `Unit Tests`, when the wait bound passes, then the drain ends ESCALATED `required_check_absent Unit Tests`, never READY.
- [ ] 8. Given `required_checks` set to `[]`, `"Unit Tests"`, or `[1]`, when the drain runs with protection unreadable, then it ends ESCALATED `required_checks_unavailable`, with a message naming the malformed key.
- [ ] 9. Given neither readable protection, nor a flag, nor a config key, when the drain runs, then the outcome is byte-identical to main before this change for each of: a plain 404 with no ruleset, the paid-plan 403, and classic 404 + rulesets paid-plan 403 (a test written first pins main's current outcome for each and still passes after).
- [ ] 10. Given `--required-checks name:` or `name:,a`, when the drain starts, then it exits 2 with a usage error.

**`/automate` paths (issue acceptance 4):**
- [ ] 11. Given a lane created from a primary whose config carries `required_checks`, when the lane's drain runs, then it reads the set from the lane clone's own config (test: the create copy keeps the key, and the driver reads `$ROOT`'s config).
- [ ] 12. Given the inline drain and the fresh-phase drain prompt, then both invoke `review-heal-next-step.sh` with no `--required-checks`, so the config set applies (a test asserts the absence, so a later passthrough cannot silently shadow the key).

**Setup surface:**
- [ ] 13. Given a stubbed unreadable base protection and no `required_checks`, when `setup-base-branch.sh status` runs, then it prints the advisory line and the fix line and exits as it does today. With the key set, the line is absent.

## Validation (must pass before merge)

1. **Static — the project's gates:** `bash scripts/ci-local.sh --affected` passes, covering `test-review-heal-next-step.sh`, `test-wait-for-checks.sh`, `test-setup-base-branch.sh`, the lanes create test, `check-doc-currency.sh`, `check-token-budget.sh`, `check-prompt-history-refs.sh` and `test-citation-drift.sh`. `bash scripts/check-version-bump.sh` passes, with a `changelog.d/` fragment and no hand-edited version.
2. **Running system — a real unprotectable repo reaches READY:** on one of the owner's private repos on GitHub Free whose PR has a green named check and a red non-code check, run `/review-pr <pr-url> --until-mergeable` with `required_checks` set in that repo's config. It reaches READY, and with the named check renamed to a typo it ends ESCALATED `required_check_absent`. The output goes in `docs/evidence/drain-named-required-checks.md` with the owner and repo names redacted, and `Verdict: PASS for Validation 2`.

### Priority
- [x] Phase 2 - Important but not blocking launch

**Rationale:** It blocks every drain on a whole class of repos (private, free plan), but public repos and protected bases are unaffected, and a by-hand merge works meanwhile.

### Assumptions
- Check names in the rollup are stable enough to match exactly (GitHub check-run `name` / status `context`). A rename makes the check absent, which fails closed (AC 7).
- `.supervisor/config.json` is the owner's local file (gitignored), so declaring the set there is the owner's act, not something a cloned repo can impose. The merge-gate non-goal holds either way.
- Lanes read the config copied at lane creation; a key added mid-wave reaches only lanes created afterwards.

### Dependencies
- Depends on: none
- Blocks: none
- Related: #803 (`/loomwright:doctor` could later reuse the `/setup` line); #839 (gate side of the same repos, already merged).

### Risks
- **The new mode narrows what READY means on these repos.** That is the request, but a wrong declaration (an important check left out) is invisible until a human looks. Mitigation: the result block records `required_mode named` and the set, so the PR comment shows what READY was judged on.
- **`wait-for-checks.sh` gains a second source for its required set,** and its own protection read must still win when readable. AC 4 and AC 5 pin that order.

### Success Metrics
- On a private Free repo with a permanently red deployment check, an `/automate` item reaches a READY park instead of escalating or looping, with no per-run flag.

### Handoff
Ready for: `/launch-pad goal: ".supervisor/requirements/2026-11-12-081956-drain-honours-a-named-required-checks-set.md"`, or `/automate --folder` over it.

## Depends on
none

## Touches
loomwright/scripts/review-heal-next-step.sh
loomwright/scripts/wait-for-checks.sh
loomwright/scripts/setup-base-branch.sh
loomwright/scripts/test-review-heal-next-step.sh
loomwright/scripts/test-wait-for-checks.sh
loomwright/scripts/test-setup-base-branch.sh
loomwright/scripts/fixtures/review-heal-golden/named-required-ready
loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh
loomwright/skills/review-heal/SKILL.md
loomwright/commands/review-pr.md
loomwright/agents/review-pr.md
loomwright/docs/result-schemas/review-heal-next-step.md
loomwright/docs/result-schemas/review-heal-result.md
loomwright/docs/loop-inventory/review-heal.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
docs/evidence/drain-named-required-checks.md
changelog.d/drain-named-required-checks.md

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-11-13-drain-named-required-checks.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-13T15:30:17Z
- **Brief:** .supervisor/jobs/done/2026-11-13-drain-named-required-checks.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/905
