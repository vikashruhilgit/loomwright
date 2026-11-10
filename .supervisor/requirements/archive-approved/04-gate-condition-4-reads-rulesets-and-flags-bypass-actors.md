# Gate condition 4 reads GitHub rulesets and flags bypass actors

## Status: pending

Source: `loomwright-archive/requirements/gate/2026-10-30-063943-gate-condition-4-reads-github-rulesets-and-flags-bypass-actors.md` (plan doc `_BACKLOG-2026-10-30-063943-gate-verdict-required-check.md`, item 1). Refreshed against main `8ec200e` / v17.35.1.

**As the** owner (Vikash) who lets `/automate --auto-merge` merge a PR,
**I want** the trusted-merge gate's condition 4 to judge the base branch's real protection (classic branch protection AND every active GitHub ruleset on it), and to name every actor that can get around that protection (Copilot, other GitHub Apps, deploy keys, admins, roles, teams, users),
**so that** a repo protected only by rulesets is no longer read as unprotected, a check a ruleset requires is no longer skipped by condition 5, and protection a bot can bypass is no longer counted as enforceable.

### Problem (read on main `8ec200e`)

- `automate-helpers.sh` `gate_eval()` condition 4 makes one read, `gh api repos/<owner>/<repo>/branches/main/protection`. `_ge_protection_class` reads a failed read: a 404, or GitHub's paid-plan 403 ("Upgrade to GitHub Pro"), means not enforceable; any other error parks `protection_unreadable`. Enforceable = `required_approving_review_count >= 1` OR a required status check (`contexts` or `checks`).
- Condition 5 takes its required-check list from that same classic payload only. With an empty list it now reads the whole `statusCheckRollup` (any failing or pending check parks); with a named list a required check must be success or neutral.
- `skills/automate-loop/modes-and-merge-gate.md` §10 condition 4 still says "Classic branch protection only (rulesets are out of scope in v1)"; loop-inventory row AL-420 carries the same scope.
- Consequences: a ruleset-only repo reads as unprotected and parks `unprotected_branch` unless `--trust-unprotected` silences condition 4 entirely; a check made required by a ruleset is never matched by name (only the empty-list rollup read catches it, and only if it is red or pending, not if it is missing); nothing reads ruleset `bypass_actors`, classic `enforce_admins`, or classic `bypass_pull_request_allowances`, so a bypass actor is invisible.

### Scope

**Part A — read rulesets.**
- Condition 4 also reads `GET repos/<o>/<r>/rules/branches/main` (GitHub returns only rules from rulesets with `enforcement: active`, repo and org level merged) and, for each distinct `ruleset_id` on those rules, `GET repos/<o>/<r>/rulesets/<id>` for `enforcement` and `bypass_actors`. The branch name stays the gate's base (`main`, which condition 2 already requires); no second hardcoded branch.
- A rule counts only when its ruleset's detail reads `enforcement: active` (defence in depth; the rules endpoint should already exclude the rest).
- Enforceable = classic enforceable (unchanged) OR an active `pull_request` rule with `required_approving_review_count >= 1` OR an active `required_status_checks` rule with at least one `context`.
- Condition 5's required list = classic list ∪ every `context` of an active ruleset `required_status_checks` rule. The empty-list rollup read and the named-list success/neutral bar are unchanged.

**Part B — name and judge bypass actors.**
- One bypass list from: each relied-on ruleset's `bypass_actors`; classic `enforce_admins.enabled: false` (as `RepositoryAdmin:admins:always`); classic `required_pull_request_reviews.bypass_pull_request_allowances` users, teams and apps.
- Each actor is named `<actor_type>:<name-or-id>:<bypass_mode>`; an `Integration` whose id is on a pinned Copilot app-id list is named `copilot:<bypass_mode>`.
- **Parks:** a non-human actor (`Integration`, Copilot included, `DeployKey`, a classic app allowance, or any `actor_type` the gate does not recognise) with `bypass_mode` `always`, `exempt` or any unrecognised mode, on a ruleset condition 4 relies on, ⇒ `PARK: protection_bypassable (<up to 3 actors; "; ">)`.
- **Flags only:** human actors (`OrganizationAdmin`, `RepositoryRole`, `Team`, `User`, classic admin non-enforcement, classic user/team allowances) and any `pull_request`-mode actor.
- `--trust-unprotected` keeps its scope (the "no enforceable protection" park only); it never overrides `protection_bypassable`, `rulesets_unreadable` or `ruleset_bypass_unreadable`.
- stdout stays exactly one line (`MERGE` or `PARK: <reason>`). Flags go to stderr, one per line, `FLAG: bypass_actor <name>`.
- The driver keeps them: `automate-next-step.sh ns_gate_eval` today sends the gate's stderr to `<run_id>.gate-eval.err` and deletes it right after the call. It instead appends one `## Progress` line, `<ts> gate-eval: flags — <first 3 flag names; "; "> (+<n> more)`, written only when the stderr carries `FLAG:` lines, after the unchanged `gate-eval: MERGE` / park line.

**Part C — fail CLOSED on every new read.**
- `rules/branches/main` `[]` ⇒ no rulesets. 404, or the paid-plan 403 `_ge_protection_class` already recognises ⇒ no rulesets (the same classifier, never a second one). Any other error, non-JSON, a non-array body, or a rule with no `ruleset_id` ⇒ `PARK: rulesets_unreadable`.
- A relied-on ruleset whose detail read fails, or whose detail has no `bypass_actors` key (GitHub returns it only to callers with write access to the ruleset) ⇒ `PARK: ruleset_bypass_unreadable`. A missing list is never read as an empty one. A ruleset not needed for enforceability with an unreadable detail is flagged `FLAG: bypass_actor unreadable:<id>`, not parked.
- Order inside condition 4: `protection_unreadable` → `rulesets_unreadable` → `ruleset_bypass_unreadable` → `unprotected_branch` → `protection_bypassable`. Every other park keeps its place.
- The gate-owned-key refusal list gains `bypass_actors` and `ruleset_enforceable`.

**Docs.** §10 condition 4 and condition 5's required-list sentence, the gate-owned-key lists (`modes-and-merge-gate.md`, `helpers.md`), `gate_eval()`'s header comment (the authority for every park reason, with the GitHub doc URL and read date), AL-420/AL-421, the `--trust-unprotected` rows in `commands/automate.md` and `commands/agent-help.md` (name what it does not override), the Progress-line list in `docs/result-schemas/automate-run.md`, a `changelog.d/` fragment. No condition count is restated.

## Acceptance Criteria

All gate cases run in the stubbed-`gh` harness of `scripts/test-automate-helpers.sh` (its `gh` stub learns to route `rules/branches/main` and `rulesets/<id>` separately from `branches/main/protection`; today every non-graphql `api` call returns `protection.json`). No network; `check-test-hermetic.sh` stays green.

**Happy path**
- [ ] Classic 404, one active ruleset with a `pull_request` rule (`required_approving_review_count: 1`) and `bypass_actors: []`, every other condition holding, `trust_unprotected: false` ⇒ stdout `MERGE`, exactly one merge call. The same fixture on main parks `unprotected_branch` (recorded as the regression case). Test: `test-automate-helpers.d/05-gate-eval.sh`.
- [ ] Classic 404, an active ruleset requiring context `ci`: rollup `ci` = failure ⇒ `checks_not_green`; `ci` = success ⇒ `MERGE`; `ci` absent from the rollup ⇒ `checks_not_green`. Test: `05-gate-eval.sh`.
- [ ] Classic requires `a`, a ruleset requires `b`, rollup has `a` green and `b` missing ⇒ `checks_not_green`. Test: `05-gate-eval.sh`.
- [ ] Ruleset bypass actor `{RepositoryRole, 5, always}`, everything else holding ⇒ stdout exactly `MERGE`, stderr `FLAG: bypass_actor RepositoryRole:5:always`, one merge. Test: `05-gate-eval.sh`.
- [ ] Driven through `automate-next-step.sh` (a golden `gate-eval-merge` variant whose stub adds that actor) ⇒ `## Progress` reads `gate-eval: MERGE` byte-identical to the unflagged case, followed by `gate-eval: flags — RepositoryRole:5:always`; with no flags no extra line is written. Test: `test-automate-next-step.d/02-branches.sh`.

**Edge cases**
- [ ] Copilot app id as `{Integration, always}` on the only enforcing ruleset ⇒ `PARK: protection_bypassable (copilot:always)`, no merge; with `trust_unprotected: true` still the same park. Test: `05-gate-eval.sh`.
- [ ] An `Integration` id not on the Copilot list ⇒ `protection_bypassable (Integration:<id>:always)`; a `DeployKey` with `always` ⇒ parks; an `Integration` with `exempt` ⇒ parks; an unknown `actor_type` with `always` ⇒ parks; an `Integration` with `pull_request` ⇒ `MERGE` plus a flag. Test: `05-gate-eval.sh`.
- [ ] Classic enforceable with `enforce_admins.enabled: false`, rules `[]` ⇒ `MERGE` plus `FLAG: bypass_actor RepositoryAdmin:admins:always`; classic `bypass_pull_request_allowances.apps` naming an app ⇒ `protection_bypassable`. Test: `05-gate-eval.sh`.
- [ ] A rule whose ruleset detail reads `enforcement: evaluate` is not counted: classic 404 plus only that rule ⇒ `unprotected_branch`. Test: `05-gate-eval.sh`.
- [ ] A relied-on ruleset detail with no `bypass_actors` key ⇒ `ruleset_bypass_unreadable`; the same for a non-relied-on ruleset ⇒ the decision is unchanged and a `FLAG: bypass_actor unreadable:<id>` line is written. Test: `05-gate-eval.sh`.
- [ ] Rules `[]` and an enforceable classic fixture ⇒ decision byte-identical to main for that fixture. Every pre-existing case in `05-gate-eval.sh`, `06-gate-eval-tail.sh` and the `fixtures/automate-golden/gate-eval-*` goldens stays green with only a `rules/branches/main` → `[]` stub answer added. Test: those suites.
- [ ] A ctx.json carrying `bypass_actors` or `ruleset_enforceable` ⇒ `ctx_carries_gate_owned_key` before any read. Test: `05-gate-eval.sh`.

**Error scenarios**
- [ ] `rules/branches/main` fails with a non-paid-plan 403, a 500, a non-JSON body, an object instead of an array, or a rule without `ruleset_id` ⇒ `rulesets_unreadable`, no merge, `trust_unprotected: true` changes nothing. Test: `05-gate-eval.sh`.
- [ ] `rules/branches/main` 404 or the paid-plan 403 text, with classic 404 ⇒ `unprotected_branch`, and `MERGE` only with `trust_unprotected: true` (the shipped private-Free-repo path keeps working). Test: `05-gate-eval.sh`.
- [ ] Mutants: (a) the ruleset read dropped, (b) a missing `bypass_actors` read as `[]`, (c) `trust_unprotected` overriding `protection_bypassable`, (d) an `evaluate` ruleset counted, (e) the paid-plan 403 classifier skipped for the rules read (every 403 ⇒ no rulesets) — the suite fails on each. Test: `06-gate-eval-tail.sh` (gated mutant copies, the existing mutant pattern).
- [ ] `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` prints only the surfaces `skills/automate-loop/invariants.md` §11 sanctions. Test: `test-automate-next-step.sh` leg S.

## Non-goals
- Any other condition, the ctx keys the loop passes (no new input key), the `--match-head-commit` merge, or who runs `gh pr merge --squash`.
- Any write to GitHub (the gate never edits a ruleset or removes an actor).
- Bases other than `main`.
- Listing `evaluate`/`disabled` rulesets to flag them (the rules endpoint never returns them; a list read is one more read that can fail).
- Matching a ruleset check's `integration_id` / classic `app_id` (today's by-name match is kept).
- The verdict mode (item 05) and the deferred check-run items 2b/2c.

## Owner decisions
- 2026-11-09 (Vikash, in chat): APPROVED from the archive review; refreshed against main 8ec200e / v17.35.1.
- 2026-11-09 (Vikash, in chat): correctness bug in the sole `gh pr merge --squash` executor; this item goes before item 05.
- 2026-10-30 (Vikash, in the set request): stubs only, no live App or repo needed for any AC; rulesets + bypass first, verdict second.
- PO default, pending owner review (OQ-R1): park non-human `always` bypass (Integration incl. Copilot, DeployKey, classic app allowances); flag human roles and `pull_request` mode. Extended on refresh: `exempt` mode and an unrecognised actor type or mode park the same way (fail closed on the two enum values the source did not know).
- PO default, pending owner review (OQ-R2): `--trust-unprotected` does not override `protection_bypassable`, `rulesets_unreadable` or `ruleset_bypass_unreadable`.
- PO default, pending owner review (OQ-R3): Copilot recognised by a pinned app-id list with source URL and read date; the label is cosmetic, every `Integration` is judged the same.
- PO default, pending owner review (OQ-R4, changed on refresh): rules 404 and the paid-plan 403 both mean "no rulesets", through the existing `_ge_protection_class`; any other 403 parks `rulesets_unreadable`. The source rejected reading 403 text, but main has since shipped exactly that classifier for the classic read, and parking here would break the shipped private-Free-repo `--trust-unprotected` path.
- PO default, pending owner review (OQ-R5): an unreadable detail parks only for a relied-on ruleset; otherwise it is flagged.
- PO default, pending owner review (new): flags reach `## Progress` as one extra driver line, because the driver deletes the gate's stderr file today (the source assumed it was kept).

## Priority: MVP
**Rationale:** Condition 4 is wrong both ways on any ruleset-protected repo, in the only merge executor, and item 05 publishes its answer.

## Assumptions
- Each rule returned by `rules/branches/<branch>` carries `ruleset_id` (the REST page lists no per-rule fields; the implementer confirms against a live read or the OpenAPI description and cites URL + date). If it does not, the rule parks `rulesets_unreadable`, which is safe but parks every ruleset repo, so this is checked first.
- `rulesets/<id>` returns `bypass_actors` only to callers with write access to that ruleset (REST docs, read 2026-11-09); the owner's `gh` login has it on his own repos.
- The rules endpoint on a private GitHub Free repo answers with the same "Upgrade to GitHub Pro" 403 text as the classic endpoint; if its text differs, the classifier parks `rulesets_unreadable` (safe, but the Running-system check below catches it).
- `actor_type` values today: `Integration`, `OrganizationAdmin`, `RepositoryRole`, `Team`, `DeployKey`, `User`; `bypass_mode`: `always`, `pull_request`, `exempt` (REST docs, read 2026-11-09).

## Dependencies
- Depends on: none.
- Blocks: `05-gate-verdict-mode-judges-any-pr-head-without-merging.md`.

## Risks
- **More parks on the owner's repos** where a ruleset lists an app with `always` bypass. Intended; the park names the actor to remove or switch to `pull_request`.
- **Every gate golden needs a stub line.** The `fixtures/automate-golden/gate-eval-*/gh.stub` tables match exact calls; an unanswered rules read would park `rulesets_unreadable` and fail the goldens loudly, not silently.
- **High-risk diff.** `classify-risk.sh` marks this file high-risk; the owner merges the PR (safe mode).
- **Token budget.** `skills/automate-loop` has ~4,200 tokens of headroom; the commands docs carry their own ceilings. `check-token-budget.sh` fails closed if any is exceeded, and the budget row then moves in the same change.

## Validation (must pass before merge)
1. **Static — gate suites:** `bash loomwright/scripts/test-automate-helpers.sh` (legs `05-gate-eval*`, `06-gate-eval-tail`) and `bash loomwright/scripts/test-automate-next-step.sh` pass, including every AC case and mutant above.
2. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes (incl. `check-doc-currency.sh`, `test-loop-inventory.sh`, `check-prompt-history-refs.sh`, `check-token-budget.sh`, `check-test-hermetic.sh`); `bash scripts/check-version-bump.sh` passes with a `changelog.d/` fragment; no version file is hand-edited.
3. **Static — merge invariant:** `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` lists only §11-sanctioned surfaces.
4. **Running system — read-only live reads:** on one of the owner's ruleset-protected repos and one private Free repo, `gh api repos/<o>/<r>/rules/branches/main` and `gh api repos/<o>/<r>/rulesets/<id>` are run once (GET only), and their shapes (`ruleset_id` per rule, `bypass_actors` present, the paid-plan 403 text) are recorded in the PR description as the evidence for the Assumptions above.

## Depends on
none

## Touches
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/test-automate-helpers.d/05-gate-eval-harness.sh
loomwright/scripts/test-automate-helpers.d/05-gate-eval.sh
loomwright/scripts/test-automate-helpers.d/06-gate-eval-tail.sh
loomwright/scripts/automate-next-step.sh
loomwright/scripts/test-automate-next-step.sh
loomwright/scripts/test-automate-next-step.d/02-branches.sh
loomwright/scripts/fixtures/automate-golden/gate-eval-checks-not-green-park/gh.stub
loomwright/scripts/fixtures/automate-golden/gate-eval-drain-not-ready-park/gh.stub
loomwright/scripts/fixtures/automate-golden/gate-eval-head-sha-moved-park/gh.stub
loomwright/scripts/fixtures/automate-golden/gate-eval-high-risk-diff-park/gh.stub
loomwright/scripts/fixtures/automate-golden/gate-eval-merge/gh.stub
loomwright/scripts/fixtures/automate-golden/gate-eval-review-decision-blocking-park/gh.stub
loomwright/scripts/fixtures/automate-golden/gate-eval-rules-gate-head-mismatch-park/gh.stub
loomwright/scripts/fixtures/automate-golden/gate-eval-unprotected-branch-park/gh.stub
loomwright/skills/automate-loop/modes-and-merge-gate.md
loomwright/skills/automate-loop/helpers.md
loomwright/docs/loop-inventory/automate-loop.md
loomwright/docs/result-schemas/automate-run.md
loomwright/commands/automate.md
loomwright/commands/agent-help.md
changelog.d/gate-condition-4-rulesets.md

## Changes since the source was written
- **Paid-plan 403 shipped** (`3a6cb32`): classic protection's "Upgrade to GitHub Pro" 403 now reads as not enforceable via `_ge_protection_class`. OQ-R4's default changes to reuse that classifier for the rules read.
- **Empty required list reads the whole rollup** (`3a6cb32`): condition 5 no longer passes vacuously with no required contexts, so the "missed required check" harm is narrower (a ruleset check that is red or pending was already caught when the classic list was empty; a missing one, or one beside a non-empty classic list, was not). The union is still needed.
- **Empty `reviewDecision` reads as `none`** (`742046c`): no change here; condition 3 still defers a no-review branch to condition 4.
- **False premise fixed:** the source said the driver keeps the gate's stderr in `<run_id>.gate-eval.err`. `ns_gate_eval` deletes that file right after the call (it did at the source's commit too), so flags would be lost. Added the one Progress line and its driver/test/doc files.
- **API facts corrected** (REST docs read 2026-11-09): `rules/branches` never returns `evaluate` rulesets, so the "flag the evaluate ruleset" AC is dropped; `bypass_actors` needs write access, not admin; new `actor_type: User` and `bypass_mode: exempt` are handled.
- **Touches completed:** the `gh` stub lives in `test-automate-helpers.sh`, the next-step goldens have their own `gh.stub` tables, and the gate-owned-key list is restated in `helpers.md` and the `--trust-unprotected` scope in two command docs.
- `--merge-parked` (v17.33) reuses `ns_gate_eval`, so it gets the new reads and the flags line with no extra change.
