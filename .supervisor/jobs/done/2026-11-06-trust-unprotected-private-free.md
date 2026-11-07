# Supervisor Job: --trust-unprotected works on private Free repos, and the gate still reads CI there

## Environment
- **Project:** ai-agent-manager-lanes/automate-2026-11-06-131342/L2 (lane L2 clone of `vikashruhilgit/loomwright`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (source requirement is gitignored under `.supervisor/`, so its provenance is the metadata branch, not this checkout's history)
- **Source requirement:** .supervisor/requirements/2026-11-05-192935-trust-unprotected-private-free-and-empty-checks.md
- **Base commit:** d42212f2beb5880501c6e656156ca7014696d6c5

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash 3.2 + jq + `gh`, the stack `gate_eval` already uses |
| 2 | Dependency Availability | GO | No new dependency. Validation 2 needs one private repo on GitHub Free that the authenticated `gh` account can read |
| 3 | Architecture Fit | GO | Both changes are self-resolved reads inside `gate_eval`, which stays the single sanctioned `gh pr merge --squash` executor. No new ctx key and no new park reason |
| 4 | Scope vs Supervisor Capability | GO | 7 modify + 2 create, well under the `context-bound` bound. Single subtask |
| 5 | Hard Blockers | CAUTION | **Drain reachability:** `wait-for-checks.sh` classifies a failed protection read other than a 404 as `required=unknown` (`*"Branch not protected"*\|*"HTTP 404"*)` is its only verified-empty arm), and review-heal escalates on `required=unknown` unless `--required-checks all-non-neutral` is set. So on a private Free repo the owned drain ESCALATES before `gate-eval` runs, and this story alone does not deliver the requirement's end-to-end Success Metric. Two test-harness files outside Touches are also needed (see `## Scope widening`) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Make `gate_eval` condition 4 treat GitHub's paid-plan protection refusal (HTTP 403 + "Upgrade to GitHub Pro") as "not enforceable", match a 404 by HTTP status rather than by substring, and make condition 5 read the rollup when no required checks exist. The gate stays at seven conditions, self-resolving, with condition 6 still non-overridable.

**Problem Statement:**
An owner running `/automate --auto-merge --trust-unprotected` on a private repo on GitHub Free needs the flag to cover GitHub's "protection needs a paid plan" refusal, without merging red CI.
Currently, condition 4 accepts only a 404 as unprotected, so the paid-plan 403 parks `protection_unreadable` before `trust_unprotected` is read. That 404 test is a bare `*"404"*` substring match over stdout+stderr, so any error text containing `404` reads as unprotected. Condition 5's `checks_green` starts with `( ($req | length) == 0 ) or`, so an empty required list is green whatever the rollup says. Fixing condition 4 alone would extend that vacuous green to every private Free repo.
Success looks like: a paid-plan 403 with the flag reaches `MERGE` when CI is green and parks `checks_not_green` when it is red. Every other protection error still parks `protection_unreadable`.

## Acceptance Criteria

**Happy path:**
- [ ] AC1 — Given a stubbed paid-plan 403 (GitHub's verbatim refusal: JSON body `{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.",…,"status":"403"}` plus `gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)`) and `trust_unprotected: true`, when `gate-eval` runs with the other conditions holding, then condition 4 passes and the gate prints `MERGE`.
- [ ] AC2 — Given the same stubbed paid-plan 403 and no trust flag, when `gate-eval` runs, then it prints `PARK: unprotected_branch`.
- [ ] AC3 — Given a non-empty required list and green required checks, when `gate-eval` runs, then condition 5 behaves as it does today. The existing condition-5 pins in `05-gate-eval.sh` (the `required check 'ci' not green` case and the all-green `MERGE` cases) pass unchanged.

**Edge cases:**
- [ ] AC4 — Given an empty required list and a rollup with one `FAILURE`, when `gate-eval` runs with the trust flag, then it prints `PARK: checks_not_green`, under both the 403 path and the 404 path (two separate test cases).
- [ ] AC5 — Given an empty required list and a check still in progress (a CheckRun with `status: IN_PROGRESS` and an empty `conclusion`, and separately a StatusContext with `state: PENDING`), when `gate-eval` runs, then it prints `PARK: checks_not_green`.
- [ ] AC6 — Given an empty required list and a rollup whose checks are all `SUCCESS`, `NEUTRAL` or `SKIPPED`, when `gate-eval` runs, then condition 5 passes (the gate reaches `MERGE`).
- [ ] AC7 — Given an empty required list and an empty rollup (`statusCheckRollup: []`), when `gate-eval` runs, then condition 5 passes (`MERGE`).
- [ ] AC8 — Given protection that requires reviews only (`required_approving_review_count >= 1`, no required status checks) and a failing check in the rollup, when `gate-eval` runs, then it prints `PARK: checks_not_green`.

**Error scenarios:**
- [ ] AC9 — Given a 403 without the "Upgrade to GitHub Pro" message (for example `gh: Resource not accessible by integration (HTTP 403)`), when `gate-eval` runs with the trust flag, then it prints `PARK: protection_unreadable`.
- [ ] AC10 — Given a 500 whose text contains `404` (for example `gh: upstream returned 404 to the proxy (HTTP 500)`), when `gate-eval` runs with the trust flag, then it prints `PARK: protection_unreadable`.
- [ ] AC11 — Given a genuine `Branch not protected (HTTP 404)` (stdout `{"message":"Branch not protected",…,"status":"404"}`, stderr `gh: Branch not protected (HTTP 404)`) and the trust flag, when `gate-eval` runs, then condition 4 still passes and the gate reaches `MERGE` (no regression). The existing `protection-404` pin also keeps passing.
- [ ] AC12 — Given a high-risk diff, the paid-plan 403 and the trust flag, when `gate-eval` runs, then it prints `PARK: high_risk_diff …` (condition 6 stays non-overridable).

**Gate contract and docs:**
- [ ] AC13 — Given the change, when `gate_eval` is read, then it adds no ctx key (the gate-owned key list `for _ge_k in high_risk risk_reasons head_sha base review_decision` is unchanged), adds no park reason (the header's preserved park-reason list is unchanged), keeps seven conditions, and its header comment for cond 4 / cond 5 describes the new behaviour (paid-plan 403 reads as not enforceable; 404 matched by HTTP status; empty required list ⇒ rollup read). The description goes in the indented continuation lines only. The `#   cond 4` / `#   cond 5` first lines stay byte-identical, so `test-automate-helpers-dispatch.sh`'s `--help` golden still passes.
- [ ] AC14 — Given `loomwright/skills/automate-loop/modes-and-merge-gate.md`, when it is read, then condition 4 says the paid-plan 403 reads as not enforceable (so `--trust-unprotected` covers it) and any other error, a non-paid-plan 403 included, parks `protection_unreadable`. Condition 5 says that with no required list, a failing or pending rollup check parks `checks_not_green` and an empty rollup passes. The safe-mode bullet carries one pointer to `resume.md`'s `### Merging one parked item`. The doc adds no history reference (its `prompt-history-refs-baseline.json` entry is `0`).
- [ ] AC14b — Given `loomwright/docs/loop-inventory/automate-loop.md`, when rows AL-420 and AL-421 are read, then their condition and rule cells describe the new behaviour. AL-420: a 404 matched by HTTP status, or the paid-plan 403, ⇒ not enforceable (merge only with `--trust-unprotected`); any other error ⇒ `PARK: protection_unreadable`. AL-421: no required contexts ⇒ any failing or pending rollup check parks, and an empty rollup passes. Only those two rows' cells change. Their ids, files, `q:` anchors, type, home, implemented-by and test cells stay byte-identical, no other row changes, and `bash loomwright/scripts/test-loop-inventory.sh` passes.
- [ ] AC15 — Given the PR, when `changelog.d/trust-unprotected-private-free.md` is read, then it is a valid fragment (format: `changelog.d/README.md`) whose body states that condition 5 is now stricter for existing empty-required-list `--auto-merge` users, so a failing check (`claude-review` included) now parks runs that merged before. No version file is hand-edited.

**Validation (from the requirement's `## Validation`):**
- [ ] AC16 (Validation 1, static) — Given the branch, when `bash scripts/ci-local.sh --affected` runs, then it passes, including `check-doc-currency.sh`, `check-prompt-history-refs.sh`, `test-citation-drift.sh` and `check-token-budget.sh`. And `bash scripts/check-version-bump.sh` passes (a lane PR carries the fragment only and never bumps).
- [ ] AC17 (Validation 2, running system) — Given a private repo on GitHub Free readable by the authenticated `gh` account, when the read-only `gh api repos/<owner>/<repo>/branches/main/protection` call runs, then a committed evidence file `docs/evidence/trust-unprotected-private-free.md` holds its fenced stdout+stderr (owner and repo redacted to `<owner>/<repo>`) and a byte comparison with the test stub's 403 text. The file carries the line `Verdict: PASS for Validation 2` at column 0, outside any fence, and the PR body links to it.

## Scope widening
- loomwright/scripts/test-automate-helpers.sh
- loomwright/scripts/test-automate-helpers.d/05-gate-eval-harness.sh
- loomwright/docs/loop-inventory/automate-loop.md
- accepted: AUT-OVERLAP 2026-11-06

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Rule conflicts (open decisions)
- process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift — loop-inventory rows AL-420 / AL-421 restate gate conditions 4 / 5, which this change alters. The requirement's "Leave alone" list gives `docs/loop-inventory/automate-loop.md` to the companion wave item, which does not edit these rows. Owner's choice: honor the rule. This lane edits only the AL-420 / AL-421 cells (AC14b), and the file is recorded under `## Scope widening` for the coordinator's re-gate (Launch Pad Phase 6, 2026-11-06).

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| gate | `loomwright/scripts/automate-helpers.sh` (1186) | — | HIGH |
| gate tests | `loomwright/scripts/test-automate-helpers.d/05-gate-eval.sh` (352), `loomwright/scripts/test-automate-helpers.d/06-gate-eval-tail.sh` (74), `loomwright/scripts/test-automate-helpers.sh` (437), `loomwright/scripts/test-automate-helpers.d/05-gate-eval-harness.sh` (166) | — | HIGH |
| docs | `loomwright/skills/automate-loop/modes-and-merge-gate.md` (59), `loomwright/docs/loop-inventory/automate-loop.md` (791 — two existing rows' cells edited in place, no new responsibility) | `docs/evidence/trust-unprotected-private-free.md`, `changelog.d/trust-unprotected-private-free.md` | HIGH |

> **Validator-owned surfaces:** `check-doc-currency.sh`, `check-token-budget.sh` (the `.skills["automate-loop"]` budget counts every `*.md` under `skills/automate-loop/`), `check-prompt-history-refs.sh` (baseline `0` for `modes-and-merge-gate.md`) and `test-loop-inventory.sh` (rows AL-406 / AL-420 / AL-421 quote `modes-and-merge-gate.md`) scan files this change touches. None of their own files needs an edit if the touched text keeps its anchors and stays within budget.

**Module layout (`skills/supervisor-readiness/SKILL.md` §"Module layout"):**
- `automate-helpers.sh` (1186, large). **Protection-read classification** (status from gh's `(HTTP NNN)` suffix; 404 ⇒ unprotected; 403 + paid-plan message ⇒ not enforceable; else unreadable) goes in one `_ge_`-prefixed helper defined beside `_ge_pr_parts` / `_ge_result_field` in the same file. Reason for appending: `gate_eval` is the single sanctioned implementation of the merge gate (CLAUDE.md's one-executor invariant), and its `_ge_` helpers live with it. **Empty-required rollup read** changes the existing `checks_green` jq expression in place, with no new home.
- `05-gate-eval.sh` (352) takes the condition-4 cases (AC1, AC2, AC9–AC12), about +70 lines, staying under 500. `06-gate-eval-tail.sh` (74) takes the empty-required condition-5 cases (AC4–AC8), so `05` does not cross the threshold.
- `test-automate-helpers.sh` (437) gets one generic stub marker, about +3 lines. Reuse: the existing `make_stub_bin` stub, not a second stub.

**Total estimated files:** 7 modify + 2 create

## Touched-file invariants

> Grounded at base `d42212f2beb5880501c6e656156ca7014696d6c5`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-helpers.sh`**
  - **Keep:**
    - Any other protection error stays fail-CLOSED: `echo "PARK: protection_unreadable"; return 0`.
    - Keep the `set -e`-safe capture idiom `2>&1)" || prot_rc=$?` (stdout and stderr merged, so the JSON body and gh's `(HTTP NNN)` line are both visible).
    - The cond-4 override stays `local trust; trust="$(J '.trust_unprotected')"`.
    - The non-empty-required branch `all($req[]; . as $name` is unchanged (AC3).
    - The gate-owned key loop `for _ge_k in high_risk risk_reasons head_sha base review_decision` is unchanged, and no new ctx key is added.
    - The header's park-reason inventory (`Every PARK reason from the pre-self-resolving gate is preserved verbatim`) gains nothing.
    - Cond 6's `NO override of any kind` is untouched.
    - The executor grep `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` lists the same paths.
    - The literal `Upgrade to GitHub Pro` appears **exactly once** in this file, on the cond-4 match line. The header comment paraphrases it ("the paid-plan refusal message") so the pin-mutation flip below lands on code.
    - The literal `"skipped"` appears exactly once, in the empty-required rollup predicate.
    - The first lines of the `#   cond 4` and `#   cond 5` header comments stay byte-identical, so AC13's new wording goes only in the deeper-indented `#           ` continuation lines. Add no new `#   <lowercase>` comment line anywhere in the file. `--help` prints every `^#   [a-z]` line via `_ah_bundle | grep -E '^#   [a-z]'`, and `loomwright/scripts/fixtures/automate-helpers-help/incidental.golden` pins `cond 4  `gh api repos/<owner>/<repo>/branches/main/protection` — a 404 ⇒ unprotected (false);` byte-for-byte (compared by `test-automate-helpers-dispatch.sh` check 5).
  - **Reuse:** the `_ge_` helper naming and placement (`_ge_pr_parts() {`); the `"$JQ"` / `"$GH"` variables, never a bare `jq` / `gh`.
  - **Mirror:** `wait-for-checks.sh` classifies a genuine 404 by `*"HTTP 404"*`. The gate's new 404 test matches the same `(HTTP 404)` status token, and `wait-for-checks.sh` itself is NOT modified (see Risk Assessment).
  - **Pinned by:**
    - `fixtures/automate-helpers-help/incidental.golden`, via `test-automate-helpers-dispatch.sh` check 5: the `#   cond 4` / `#   cond 5` first lines.
    - `test-automate-helpers.d/05-gate-eval.sh`: `PARK: protection_unreadable`, `PARK: unprotected_branch`, `protection-404`, `protection-fail`, `PARK: checks_not_green`.
    - `test-automate-helpers.d/06-gate-eval-tail.sh`'s cond-6 mutant, which seds the exact line `  if [ -r "$risk_bin" ]; then`. Keep that line byte-identical.
- **`loomwright/scripts/test-automate-helpers.sh`**
  - **Keep:**
    - The `protection-404` marker's exact output, `echo "gh: Not Found (HTTP 404)" >&2; exit 1`, and the `protection-fail` marker's `echo "gh: Internal Server Error (HTTP 500)" >&2; exit 1`. Existing pins depend on both.
    - The stub's `set -u`.
  - **Extend:** the `api repos/.../branches/main/protection` arm and its header comment (`#   api repos/.../branches/main/protection          -> cat protection.json; protection-404 marker exits 1`). Add ONE generic marker whose file holds the verbatim error text, printed to stdout+stderr, then `exit 1`. Tests write GitHub's exact refusal text into it.
  - **Pinned by:** every `test-automate-helpers.d/*.sh` part that calls the stub.
- **`loomwright/scripts/test-automate-helpers.d/05-gate-eval-harness.sh`**
  - **Keep and reuse:** `reset_live`'s cleanup idiom `rm -f "$GH_STUB_DIR/protection-404" "$GH_STUB_DIR/protection-fail"`. Extend it to remove the new marker.
  - **Keep:** the default `protection.json` (`"required_status_checks":{"contexts":["ci"]}`) and the default all-green rollup, so later parts start from the same state.
- **`loomwright/scripts/test-automate-helpers.d/05-gate-eval.sh` / `06-gate-eval-tail.sh`**
  - **Reuse:** the case idiom `gate "$(pass_ctx | jq '.trust_unprotected=true')"`, with an `ok` / `no` pair asserting both `RUN_OUT` and `merges`, and `reset_live` after each section.
  - **Keep:** 06's TOCTOU, merge-fail and cond-6 mutation-control cases unchanged. New 06 cases go before them and end with `reset_live`.
  - **Mutation discipline:** any new mutant is gated on non-empty + differs-from-original + `bash -n` (lesson `fa32a308`).
- **`loomwright/skills/automate-loop/modes-and-merge-gate.md`**
  - **Keep the `q:` anchors** of loop-inventory rows AL-406, AL-420 and AL-421 as substrings of one line each:
    - `**Safe mode (default):** at the GATE, a `READY` drain that passed the validation gate`
    - `**Enforceable branch protection (OR explicit `--trust-unprotected`).**`
    - `Required checks: the required-context list from condition 4's protection payload`
  - **Keep:** `--trust-unprotected` overrides condition 4 ONLY, and `ALL SEVEN`.
  - **No history references:** no `#NNN`, dates or `vX.Y.Z` (baseline `0`).
  - **Restating copies:** loop-inventory rows AL-420 / AL-421 are updated in the same change (AC14b).
  - **Size:** net growth stays small. The `automate-loop` skill-dir budget had 2073 tokens of headroom at base, shared with the companion lane's `resume.md` edit.

- **`loomwright/docs/loop-inventory/automate-loop.md`**
  - **Keep:** for rows `| AL-420 |` and `| AL-421 |`, the id, file, `q:` anchor (`q: **Enforceable branch protection (OR explicit `--trust-unprotected`).**`, `q: Required checks: the required-context list from condition 4's protection payload`), type `deterministic`, home and implemented-by `script:automate-helpers.sh gate-eval`, and test `test-automate-helpers.sh` cells stay byte-identical. Only the condition and rule cells change.
  - **Keep:** the column count of each row, with no unescaped `|` added inside a cell. No other row is touched (the companion lane adds rows elsewhere in this file).
  - **Pinned by:** `loomwright/scripts/test-loop-inventory.sh`, which checks the row format and live anchors.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-automate-helpers.d/05-gate-eval.sh` — AC1 paid-plan 403 + trust ⇒ `MERGE` (and AC2 ⇒ `PARK: unprotected_branch`) | flip `Upgrade to GitHub Pro` → `Upgrade to GitHub Team` in `loomwright/scripts/automate-helpers.sh` |
| `loomwright/scripts/test-automate-helpers.d/05-gate-eval.sh` — AC9 non-paid-plan 403 + trust ⇒ `PARK: protection_unreadable` | reviewer-applied: drop the paid-plan message conjunct so any 403 reads as not enforceable, in `loomwright/scripts/automate-helpers.sh` |
| `loomwright/scripts/test-automate-helpers.d/05-gate-eval.sh` — AC10 500-containing-404 + trust ⇒ `PARK: protection_unreadable` | reviewer-applied: restore the bare `*"404"*` substring arm in cond 4 of `loomwright/scripts/automate-helpers.sh` |
| `loomwright/scripts/test-automate-helpers.d/05-gate-eval.sh` — AC11 genuine `Branch not protected (HTTP 404)` + trust ⇒ `MERGE` | reviewer-applied: drop the `(HTTP 404)` arm from the protection-read classifier in `loomwright/scripts/automate-helpers.sh` (expect `PARK: protection_unreadable`) |
| `loomwright/scripts/test-automate-helpers.d/05-gate-eval.sh` — AC12 paid-plan 403 + trust + high-risk diff ⇒ `PARK: high_risk_diff …` | flip `  if [ "$hr" != "false" ]; then` → `  if [ "$hr" != "false" ] && [ "$trust" != "true" ]; then` in `loomwright/scripts/automate-helpers.sh` (the trust flag now bypasses condition 6; expect `MERGE`, so the pin goes red) |
| `loomwright/scripts/test-automate-helpers.d/06-gate-eval-tail.sh` — AC4 empty list + `FAILURE` ⇒ `PARK: checks_not_green` (403 and 404), AC8 reviews-only + failing check | reviewer-applied: reinstate the vacuous `( ($req \| length) == 0 ) or` short-circuit in `checks_green` of `loomwright/scripts/automate-helpers.sh` |
| `loomwright/scripts/test-automate-helpers.d/06-gate-eval-tail.sh` — AC5 in-progress / pending check ⇒ `PARK: checks_not_green` | reviewer-applied: treat an empty `conclusion` as fine in the empty-required predicate of `loomwright/scripts/automate-helpers.sh` |
| `loomwright/scripts/test-automate-helpers.d/06-gate-eval-tail.sh` — AC6 all `SUCCESS`/`NEUTRAL`/`SKIPPED` ⇒ condition 5 passes | flip `"skipped"` → `"skipped_x"` in `loomwright/scripts/automate-helpers.sh` |
| `loomwright/scripts/test-automate-helpers.d/06-gate-eval-tail.sh` — AC7 empty rollup ⇒ condition 5 passes | reviewer-applied: require a non-empty rollup in the empty-required predicate of `loomwright/scripts/automate-helpers.sh` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Gate cond 4 paid-plan 403 + status-matched 404, cond 5 empty-required rollup read, tests, doc + inventory rows, fragment, evidence | all | 7 modify, 2 create | `skills/error-handling/SKILL.md`, `skills/automate-loop/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "Upgrade to GitHub Pro"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.d/05-gate-eval.sh", name: "Upgrade to GitHub Pro"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.d/06-gate-eval-tail.sh", name: "PARK: checks_not_green"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/modes-and-merge-gate.md", name: "Merging one parked item"}
  - {kind: "file", path: "docs/evidence/trust-unprotected-private-free.md"}
  - {kind: "symbol", path: "docs/evidence/trust-unprotected-private-free.md", name: "Verdict: PASS for Validation 2"}
  - {kind: "file", path: "changelog.d/trust-unprotected-private-free.md"}
requires: []
lanes:
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers.d/05-gate-eval-harness.sh"
  - "loomwright/scripts/test-automate-helpers.d/05-gate-eval.sh"
  - "loomwright/scripts/test-automate-helpers.d/06-gate-eval-tail.sh"
  - "loomwright/skills/automate-loop/modes-and-merge-gate.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "docs/evidence/trust-unprotected-private-free.md"
  - "changelog.d/trust-unprotected-private-free.md"
external_requires:
  - "A private repo on GitHub Free readable by the authenticated gh account (Validation 2; read-only gh api call)"
  - "GitHub's paid-plan refusal text for the branch-protection endpoint stays as reproduced on 2026-11-05"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/error-handling/SKILL.md`, `skills/automate-loop/SKILL.md` (§10 lives in `modes-and-merge-gate.md`) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Drain reachability (source: "Feasibility (Phase 2.5)"). `wait-for-checks.sh` reads the same paid-plan 403 as `required=unknown`, and the owned drain then escalates (review-heal §U2 fail-CLOSED). Unless `--required-checks all-non-neutral` is set, `gate-eval` is never reached on a private Free repo. The requirement's end-to-end Success Metric is therefore not met by this story alone. | HIGH | Do not widen into `wait-for-checks.sh`: it is outside Touches, and relaxing its fail-CLOSED read is a separate owner decision. Say so in the PR body and the changelog fragment ("gate-level fix; drain-side read unchanged"), and record a follow-up requirement for the drain's protection read. |
| Condition 5 gets stricter for every existing empty-required-list `--auto-merge` user. A failing check, `claude-review` under a billing block or the weekly cap included, now parks runs that merged before. | MEDIUM | Intended (owner decision). The fragment body must state it (AC15). |
| The owner chose to honor the restated-list rule, so this lane edits `docs/loop-inventory/automate-loop.md` rows AL-420 / AL-421. The companion lane also touches that file, which is a merge-collision risk at `wave-build`. | LOW | Edit only those two rows' condition and rule cells. The companion lane adds its own rows and does not edit these two. The file is recorded under `## Scope widening` as `pending-coordinator`. |
| The `automate-loop` skill-dir token budget had 2073 tokens of headroom at base. The companion lane grows `resume.md` in the same dir and owns `prompt-token-budgets.json`. | MEDIUM | Keep the `modes-and-merge-gate.md` net growth small, around 250 tokens: replace the cond 4/5 sentences rather than adding to them. The wave PR's `check-token-budget.sh` catches a combined overrun. |
| The safe-mode pointer names `resume.md`'s `### Merging one parked item`, which the companion item writes. The heading does not exist at base. | MEDIUM | Write it as a prose section pointer, not a link or `file:N` citation, so no gate fails on base. `wave-build` merges both lanes. If the companion lane is dropped, the wave PR review must remove the pointer. |
| The test stub's 403 text could drift from GitHub's real refusal. | LOW | Validation 2 (AC17) captures the real output and byte-compares it with the stub text. If GitHub changes the text, the gate parks `protection_unreadable`, which is fail-closed. |
| Two test-infra files outside Touches (`test-automate-helpers.sh` stub, `05-gate-eval-harness.sh` `reset_live`). | LOW | Recorded under `## Scope widening` as `pending-coordinator`. Neither file is in the companion lane's Touches. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-06-trust-unprotected-private-free.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-06T17:42:49Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/839
- **Branch:** feature/trust-unprotected-private-free
- **Files changed:** 9
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 0
- **Heal reason:** needs_human
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** gate_eval cond 4 now reads the paid-plan 403 as not enforceable and matches 404 by gh's (HTTP 404) status; cond 5 reads the rollup when no check is required. Tests, docs, AL-420/421, fragment and live evidence added; ci-local --affected PASS, ground truth 2/2. Escalated NEEDS_HUMAN: the BLOCKING pin-mutation 8 "not_held" is a harness artifact (run-pin-mutations.sh runs test-automate-helpers.d parts standalone; the mutant goes red under the full runner, confirmed three times); plus one MEDIUM — modes-and-merge-gate.md cond 4 does not say the drain's wait-for-checks.sh still escalates the 403 unless --required-checks all-non-neutral.

## Not verified
- **end-to-end /automate --auto-merge --trust-unprotected on a private Free repo** — drain-side wait-for-checks.sh still reads the 403 as required=unknown and escalates before gate-eval; out of scope per brief (subtask 1)
- **PR body link to docs/evidence/trust-unprotected-private-free.md** — worker opens no PR (subtask 1)
