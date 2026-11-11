# Supervisor Job: Fix or record every dismissed follow-up in bundle 04a+04b (next-step/review-heal drivers and gate tooling)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (two unrelated worktrees present: `.claude/worktrees/confident-gagarin-ad5777`, a scratchpad `wt-842` — not this run's)
- **Source requirement:** .supervisor/requirements/dismissed-followups/12-bundle-04ab-drivers-and-gate-tooling.md
- **Base commit:** 83a4549720197c7c235b61e0a07696645fefc8b3

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash/jq/awk/python3 scripts and Markdown prompts; no new stack |
| 2 | Dependency Availability | GO | No new dependency; every fix is local to an existing script/doc |
| 3 | Architecture Fit | GO | Fixes keep each script's existing fail-safe / fail-closed mode (CLAUDE.md §"Failure-Mode Invariants") |
| 4 | Scope vs Supervisor Capability | CAUTION | 50 findings over ~45 files: past the `context-bound` bound (> 12 files), so it is split into 2 sequential subtasks |
| 5 | Hard Blockers | GO | None; all 50 findings re-grepped on base 83a4549 and the cited code is still present |

**Overall Verdict:** CAUTION

## Task
**Goal:** For every one of the 50 findings in bundle 04a (32) and 04b (18), re-verify it on the base commit, then either fix it with a regression leg that fails on the pre-fix code, or record a one-line not-reproducible / not-worth-fixing disposition. All of it ships as ONE PR with ONE `changelog.d/` fragment.

**Problem Statement:**
The plugin owner needs the 50 dismissed-but-decided-`follow-up` review findings closed out, because each was decided "follow-up" and never acted on.
Currently, each one is still present on `main` (re-grepped at 83a4549: e.g. `local m=1; [ "$unres" -gt "$m" ]` in `review-heal-next-step.sh`, `run created \(session [A-Za-z0-9_-]+\)` in `read-token-ledger.sh`, `(.tools|type=="array")` in `test-build-capabilities.sh`). These are latent defects, mislabelled diagnostics and stale comments in the `/automate` and `/review-pr` drivers and in the CI gate scripts.
Success looks like a PR where every finding id (F0xx–F3xx) has exactly one disposition line in a committed evidence file. Each `fixed` line names its regression leg. CI is green and the version bump folds the bundle's single fragment.

## Acceptance Criteria
- [ ] AC1 (re-verify, Part 04a — 32 findings F016 F020 F119 F131 F155 F159 F162 F181 F182 F183 F261 F302 F303 F316 F317 F344 F345 F346 F014 F055 F124 F195 F197 F198 F199 F208 F259 F260 F327 F019 F209 F306): Given the base commit, when the worker re-checks each 04a finding against the code it cites, then a committed evidence file `docs/evidence/dismissed-followups-12-bundle-04ab.md` contains, under the heading `## Part 04a dispositions`, exactly one line per finding id of the form `- F<nnn> — fixed (<test file> <leg name>)` or `- F<nnn> — not reproducible: <one-line reason>` or `- F<nnn> — not worth fixing: <one-line reason>` or `- F<nnn> — duplicate of F<mmm>`, and the PR body links to it. (F199 is a sweep-declared duplicate of F195. F327 concerns a draft that lives only on the `loomwright-meta` branch and is outside this PR's reach, so it is expected to be recorded, not fixed.)
- [ ] AC2 (re-verify, Part 04b — 18 findings F065 F066 F084 F089 F263 F293 F297 F298 F366 F369 F057 F069 F121 F248 F278 F294 F295 F367): Given the base commit, when the worker re-checks each 04b finding, then the same evidence file contains, under `## Part 04b dispositions`, exactly one line per finding id in the same four forms, and the PR body links to it.
- [ ] AC3 (regression legs): Given a finding recorded `fixed` that changes behaviour (any change other than a comment, doc or message-text-only edit), when its named leg runs against the pre-fix code, then the leg fails, and it passes on the fixed code. Each such leg lives in the suite that already tests that script (the `## Pin mutations` table names the suite per finding). A comment- or doc-only fix (e.g. F124, F209, F366's header option, F066, F019) needs no leg, and its disposition line says `fixed (doc/comment only)`.
- [ ] AC4 (no new closed values): Given the fixes, when a fix needs a status/verdict value, then it reuses an existing one (e.g. `_BL_GH=unverified` for F345's truncated merged-PR read, `names_unavailable` for F367's failed diff pipeline, the existing `ok|none|unstamped|cmd_disabled|fail|unresolved|unreadable` set for F195), and no new enum/status/reason value is introduced anywhere.
- [ ] AC5 (invariants held): Given the fixed scripts, when `## Touched-file invariants` is re-checked, then every guard, exit-code contract and fail mode listed there still holds. Fail-safe readers still always exit 0, fail-closed gates still fail closed, and no `|| true` is added to or removed from any `hooks.json` leaf.
- [ ] AC6 (release): Given the whole bundle, when the worker finishes, then exactly ONE fragment `changelog.d/dismissed-followups-04a-next-step-and-review-heal-driver-defects.md` (covering both parts; the 04b fragment name is not created) with headline `Dismissed follow-ups 04a+04b: driver and gate tooling fixes` has been folded by `bash scripts/bump-version.sh`, `bash scripts/check-version-bump.sh` passes, no version file is hand-edited, `bash scripts/ci-local.sh --affected` passes locally (CLAUDE.md §"Pre-push test run?" — never a full local suite), and the PR's required `ci` check (the full suite) is green.


## Scope widening
- .agent/companions.json
- .claude-plugin/marketplace.json
- CHANGELOG.md
- docs/evidence/dismissed-followups-12-bundle-04ab.md
- loomwright/.claude-plugin/plugin.json
- loomwright/agents/worker.md
- loomwright/capabilities.json
- loomwright/docs/loop-inventory/launch-pad-autonomous.md
- loomwright/docs/prompt-history-refs-baseline.json
- loomwright/evals/coordinator-model/lib/selftest.sh
- loomwright/scripts/automate-helpers.d/intake.sh
- loomwright/scripts/automate-helpers.d/resume.sh
- loomwright/scripts/fixtures/automate-golden/**
- loomwright/scripts/test-automate-helpers-modules.sh
- loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh
- loomwright/scripts/test-automate-helpers.sh
- loomwright/scripts/test-automate-next-step.d/*.sh
- loomwright/scripts/test-build-handoff.sh
- loomwright/scripts/test-build-vault.sh
- loomwright/scripts/test-loop-inventory.sh
- loomwright/scripts/test-module-shape-facts.sh
- loomwright/scripts/test-pr-postmortem-gather.sh
- loomwright/scripts/test-read-token-ledger.sh
- loomwright/scripts/test-review-heal-next-step.sh
- loomwright/scripts/test-run-pin-mutations.sh
- loomwright/scripts/test-skills-index-companion.sh
- loomwright/scripts/test-wave-scope.sh
- loomwright/skills/pr-postmortem/SKILL.md
- loomwright/skills/review-heal/SKILL.md
- loomwright/skills/user-story-writing/SKILL.md
- scripts/test-check-prompt-history-refs.sh
- scripts/test-check-token-budget.sh
- accepted: LP-SCOPE 2026-11-11

## File Impact Map

> Line counts are `wc -l` at base 83a4549. Every fix is an in-place edit of the function the finding cites, so the "home" of each change is the cited file: no new responsibility is added (module-layout reason for appending to a file ≥ 500 lines: `(n — the finding's own code lives here)`). New regression legs go into the suite that already tests the script. For `test-automate-next-step.sh` (2775) they go into its existing `test-automate-next-step.d/` leg modules, never into the 2775-line runner.

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| 04a next-step driver | `loomwright/scripts/automate-next-step.sh` (3966 — the finding's own code lives here: F131 F181 F261 F316 F317 F208 F259 F260 F209), `loomwright/scripts/test-automate-next-step.sh` (2775 — R7/R12 legs F182/F183 live here; edit in place only), `loomwright/scripts/test-automate-next-step.d/03-run-drain.sh` (41), `loomwright/scripts/test-automate-next-step.d/09-mutants-tail.sh` (190), `loomwright/scripts/test-automate-next-step.d/02-branches.sh` (115), `loomwright/scripts/test-automate-next-step.d/08-coordinator-model.sh` (28), `loomwright/scripts/test-automate-next-step.d/04-pick-resume.sh` (195) | — | HIGH |
| 04a review-heal driver | `loomwright/scripts/review-heal-next-step.sh` (1198 — F016 F195/F199 F197 F198 code lives here), `loomwright/scripts/test-review-heal-next-step.sh` (1385 — the driver's suite), `loomwright/skills/review-heal/SKILL.md` (583 — F019 honest-limit sentence) | — | HIGH |
| 04a helpers / backlog | `loomwright/scripts/automate-helpers.sh` (1256 — `_ah_usage`/`_ah_source`, F119 F055), `loomwright/scripts/automate-helpers.d/backlog.sh` (741 — F344 trap only (no stale-break copy, see invariants), F345 F346), `loomwright/scripts/automate-helpers.d/resume.sh` (405, F155), `loomwright/scripts/automate-helpers.d/intake.sh` (149, F159), `loomwright/scripts/test-automate-helpers.sh` (443), `loomwright/scripts/test-automate-helpers-modules.sh` (192) | — | HIGH |
| 04a ledger / handoff / pins / postmortem | `loomwright/scripts/read-token-ledger.sh` (651 — F302 F303 F306), `loomwright/scripts/test-read-token-ledger.sh` (747), `loomwright/scripts/build-handoff.sh` (451, F020), `loomwright/scripts/test-build-handoff.sh` (705), `loomwright/scripts/run-pin-mutations.sh` (437, F162), `loomwright/scripts/test-run-pin-mutations.sh` (389), `loomwright/scripts/pr-postmortem-gather.sh` (443, F124 comment), `loomwright/scripts/test-pr-postmortem-gather.sh` (1018 — F124's fourth copy is a comment here), `loomwright/docs/result-schemas/postmortem-result.md` (259), `loomwright/skills/pr-postmortem/SKILL.md` (216), `loomwright/skills/user-story-writing/SKILL.md` (335, F014) | — | HIGH |
| 04b capabilities / contract | `loomwright/scripts/build-capabilities.sh` (589 — F065 F121 code lives here), `loomwright/scripts/test-build-capabilities.sh` (453, F069 + legs), `loomwright/docs/CAPABILITIES_CONTRACT.md` (116, F066), `loomwright/capabilities.json` (regenerated only if `build-capabilities.sh --check` says so) | — | MEDIUM |
| 04b gate scripts | `scripts/check-token-budget.sh` (551 — F294 F295 F297 F298 code lives here), `scripts/test-check-token-budget.sh` (641), `scripts/check-skills-index-sync.sh` (539 — F057 code and its own `--self-test` live here), `scripts/check-prompt-history-refs.sh` (399, F278), `scripts/test-check-prompt-history-refs.sh` (364), `loomwright/scripts/module-shape-facts.sh` (284, F366 F369 F367), `loomwright/scripts/test-module-shape-facts.sh` (301) | — | HIGH |
| 04b misc | `loomwright/scripts/build-vault.sh` (450, F089), `loomwright/scripts/test-build-vault.sh` (242), `loomwright/evals/coordinator-model/lib/stage-golden.sh` (240, F263), `loomwright/evals/coordinator-model/lib/selftest.sh` (95), `loomwright/agents/worker.md` (250, F084), `.agent/companions.json` (9, F293), `loomwright/docs/loop-inventory/launch-pad-autonomous.md` (1002 — LP-234 row lives here, F248), `loomwright/scripts/test-loop-inventory.sh` (676 — only if the row split moves a count it pins) | — | MEDIUM |
| shared (budgets / release / evidence) | `loomwright/docs/prompt-token-budgets.json` (93 — only if a skill/agent edit crosses its ceiling), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1066 — mirror row of any budget change only), `CHANGELOG.md` / `loomwright/.claude-plugin/plugin.json` / `.claude-plugin/marketplace.json` (written by `bump-version.sh` only) | `docs/evidence/dismissed-followups-12-bundle-04ab.md`, `changelog.d/dismissed-followups-04a-next-step-and-review-heal-driver-defects.md` (folded and deleted by the bump) | HIGH |

> **Validator-owned surfaces:** `check-token-budget.sh` (skill/agent byte ceilings in `prompt-token-budgets.json`), `check-prompt-history-refs.sh` (baseline `loomwright/docs/prompt-history-refs-baseline.json`, which may only go down), `check-doc-currency.sh`, `test-citation-drift.sh` and `build-capabilities.sh --check` all scan files this brief edits. Files scanned by these validators may need updates. Never raise the history-refs baseline: a new prompt line naming a finding id or queue path belongs in the evidence file or CHANGELOG, never in a prompt.

**Touches-listed paths with no finding mapped to them on re-verification** (expected untouched; edit only if a fix genuinely needs it): `CLAUDE.md`, `README.md`, `loomwright/docs/result-schemas/automate-run.md` (documents the `NEXT_STEP_FROM/UNTIL` seams; update it if F316 changes seam behaviour), `loomwright/scripts/automate-wave.sh`, `loomwright/scripts/test-wave-build.sh`, `loomwright/scripts/classify-bot-review.sh`, `loomwright/scripts/drain-subfloor-decision.sh`, `loomwright/scripts/rules-gate-verdict.sh`, `loomwright/scripts/emit-token-ledger.sh`, `loomwright/scripts/build-insights.sh`, `loomwright/scripts/validate-worker-result.py`, `loomwright/skills/automate-loop/lanes.md`, `loomwright/skills/automate-loop/per-item-loop.md`.

### Blast-Radius / Impact Prediction

| Touched Subsystem | Depends On (`DEPENDS_ON`) | Depended-on-by — derived dependents (`DEPENDED_ON_BY`) | Source Contract | Incident History |
|-------------------|---------------------------|-------------------------------------------------------|-----------------|------------------|
| `scripts/check-token-budget.sh` | — | `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | — | — |

**Predicted ripple beyond directly-touched files:** `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" (mirror rows). The twin graph shows no edges for the next-step, review-heal or capabilities subsystems. The F316 seam change additionally ripples to the real setters of `NEXT_STEP_FROM/UNTIL/CLOSEOUT_OUT`: the `loomwright/scripts/test-automate-next-step.sh` harness and its `test-automate-next-step.d/` legs, the `fixtures/automate-golden/*/next-step.results` goldens, and `loomwright/scripts/test-read-token-ledger.sh`, all inside Subtask 1's lanes. Not consumers: `supervisor-next-step.sh` (its own `SUPERVISOR_NEXT_STEP_FROM` seam, a substring grep hit) and `stage-golden.sh` (it only `unset`s the three seams).

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

> Applies directly to F261 (derive the `coordinator_model_invalid` message from `NS_CM_VALUES` instead of a hand copy), F084 (the `worker.md` frontmatter "mirrors hooks.json" claim) and F293 (companions rules).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Touched-file invariants

> Grounded at base `83a4549720197c7c235b61e0a07696645fefc8b3`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-next-step.sh`** — keep: its exit-code contract `# Exit codes: 0 an instruction printed (or a NEXT_STEP_UNTIL stop); 1 a helper / writer failure` and report validation `REPORT VALIDATION (fail CLOSED, exit 2, nothing written)`. Keep the gate-step bound check `if [ -z "${NEXT_STEP_FROM:-}" ] && ! ns_bound; then`. If F316 gates the seams behind a test marker, every real seam setter listed in Blast-Radius must get that marker in the same change. reuse: the closeout seam `if [ -n "${NEXT_STEP_CLOSEOUT_OUT:-}" ]; then` that `ns_sync` already uses, for F181's superseded path. reuse: `NS_CM_VALUES='session` as the single source of F261's message. mirror: `docs/result-schemas/automate-run.md` documents the seams and the coordinator_model value list. pinned by: `loomwright/scripts/test-automate-next-step.sh` (`leg_reader_prefixes`, `leg_run_idem`) and its `.d/` legs plus the `fixtures/automate-golden/*/next-step.results` goldens.
- **`loomwright/scripts/review-heal-next-step.sh`** — keep: `set -uo pipefail` and its `# Exit codes: 0 an instruction printed (or an RH_UNTIL stop); 1 a helper failure`. reuse: `rh_rules`' closed verdict allow-list for `rh_confirm` (F195/F199: factor one helper, no third copy). mirror: the closed field `rules_gate: enum [ok, none, fail, unresolved, unstamped, cmd_disabled, unreadable]` in `loomwright/docs/result-schemas/review-heal-result.md`, and the consumer `loomwright/scripts/drain-subfloor-decision.sh`, which takes the verdict via `--rules) RULES="$VAL" ;;` and passes only `RULES_PASSABLE (ok|none|unstamped|cmd_disabled)` (anything else ⇒ `not in RULES_PASSABLE`, continue). The `remaining_issues` change (F016) must keep both ESCALATED branches ESCALATED. pinned by: `loomwright/scripts/test-review-heal-next-step.sh`.
- **`loomwright/scripts/automate-helpers.sh`** — keep: the family-loader die `die "missing family file: automate-helpers.d/$1.sh"` and the `#:@ <segment>` usage grouping (F119 adds a repeat-name refusal, never a silent merge). F055: `_ah_source` must match `_ah_bundle`'s empty-is-missing rule. pinned by: `loomwright/scripts/test-automate-helpers-modules.sh`, `loomwright/scripts/test-loop-inventory.sh`.
- **`loomwright/scripts/automate-helpers.d/backlog.sh`** — keep: `_BL_PR_LIMIT=1000` read path and `_BL_GH=unverified` as the degraded header (F345 reuses it). keep: the refusal wording `refused — --date is not YYYY-MM-DD (nothing written)` style for F346's calendar check, which must be BSD/GNU-portable (no `date -j` alone; CLAUDE.md global: macOS-green ≠ CI-green for `date`). keep: the lock path `lk="$f.backlog-stamp.lock"`. F344 is scoped to an EXIT/INT/TERM trap that rmdirs the lock this process took. It must NOT add a stale-age break: five scripts already carry one (`break_lock()` in `run-lock.sh`, `meta-sync.d/lock.sh`, `automate-lanes.d/common.sh`, `stamp-requirement-status.sh`, `ns_cm_break` in `automate-next-step.sh`), and a sixth copy is barred by §"Module layout". Record the stale-break half `not worth fixing: a shared lock helper extract is its own item`. pinned by: `loomwright/scripts/test-automate-helpers.sh`.
- **`loomwright/scripts/automate-helpers.d/resume.sh`** — keep: `park_ask_gate` is READ-ONLY and fails `CLOSED toward no fix-now push`. pinned by: `loomwright/scripts/test-automate-helpers.sh` (`park-ask-gate`).
- **`loomwright/scripts/automate-helpers.d/intake.sh`** — keep: `queue-confirm`'s answers `skip — lane backlog …` and `ask` and its usage-error exit; F159 only makes positionals with `--lane-backlog` a usage error. pinned by: `loomwright/scripts/test-automate-helpers.sh` (`queue-confirm`).
- **`loomwright/scripts/read-token-ledger.sh`** — keep: `Fail SAFE: always exits 0` and `set -u`. mirror: the run-file line `run created (session <uuid>, plugin …)` written by the engine (F302's pattern must accept `,` or `)` after the id). pinned by: `loomwright/scripts/test-read-token-ledger.sh`, `loomwright/scripts/test-no-pipefail-grep-q.sh` (no `| grep -q` under pipefail).
- **`loomwright/scripts/build-handoff.sh`** and **`loomwright/scripts/build-vault.sh`** — keep: `# Exit:   0 always — a digest tool must never break its caller.` / `# Exit:   0 ALWAYS — a projection/reporting tool must never break its caller.` mirror: `RUN_TITLE_ERE` mirrors `is_run_file` in `automate-helpers.sh` (F020 changes only the delimiter/strip, never the ERE). pinned by: `loomwright/scripts/test-build-handoff.sh`, `loomwright/scripts/test-build-vault.sh`.
- **`loomwright/scripts/run-pin-mutations.sh`** — keep: `set -u` and the `unesc()` helper. F162 splits on unescaped `|` before `unesc`, and a row that does not parse still reads `unverified` (fails closed). pinned by: `loomwright/scripts/test-run-pin-mutations.sh`, `loomwright/scripts/test-closed-enum-pins-seam.sh`.
- **`loomwright/scripts/pr-postmortem-gather.sh`** / **`loomwright/docs/result-schemas/postmortem-result.md`** / **`loomwright/skills/pr-postmortem/SKILL.md`** — the F124 reason `no review can precede the commit that opened the PR` is restated in all three (in `postmortem-result.md` the sentence wraps after `no review can precede`, so a whole-phrase grep misses that copy; sweep with the anchor `no review can precede`). A fourth copy is a comment in `loomwright/scripts/test-pr-postmortem-gather.sh` (`no review can precede it`); reword it in the same change. Reword all three in the same change (house rule 2). `commits[0].is_review_fix` stays `false`.
- **`loomwright/scripts/build-capabilities.sh`** — keep: `set -uo pipefail`, the redirect scan `(?<![<>&0-9])` semantics for every current `hooks.json` leaf (`build-capabilities.sh --check` must stay green against the committed `loomwright/capabilities.json`), and the header's `unknown WINS` rule (F121 brings `$iw` into `$hc`). mirror: `loomwright/docs/CAPABILITIES_CONTRACT.md` `blocking` row (F066). pinned by: `loomwright/scripts/test-build-capabilities.sh`.
- **`scripts/check-token-budget.sh`** — keep: `Exit 1 = at` least one breach, fail CLOSED. F297 accumulates the zero-dir errors but still exits 1. F298 / F295 / F294 keep ERROR rows, never downgrade to skip. pinned by: `scripts/test-check-token-budget.sh` (root `scripts/` test: runs only because `.github/workflows/ci.yml` names it, `bash scripts/test-check-token-budget.sh`).
- **`scripts/check-skills-index-sync.sh`** — keep: `NR == 1 && !/^---[[:space:]]*$/ { exit }` semantics for a well-formed SKILL.md. F057 must fail loudly or strip a BOM, never silently drop a skill. pinned by: its own `--self-test` (`bash scripts/check-skills-index-sync.sh --self-test` in ci.yml).
- **`scripts/check-prompt-history-refs.sh`** — keep: `ERROR, exit 1 (fail CLOSED — an unreadable base never certifies a baseline)`. The baseline may only go down. F278 may narrow the pattern, which can only lower counts. If it does, lower `loomwright/docs/prompt-history-refs-baseline.json` in the same change, or record `not worth fixing`. pinned by: `scripts/test-check-prompt-history-refs.sh`.
- **`loomwright/scripts/module-shape-facts.sh`** — keep: `names_unavailable` on stderr as the only degraded signal (F367 reuses it) and `set -uo pipefail`. F369 resolves `hrev` once, right after the ref guards. pinned by: `loomwright/scripts/test-module-shape-facts.sh`.
- **`loomwright/evals/coordinator-model/lib/stage-golden.sh`** — keep: the output keys `PARITY: %s\nSKIPPED: %s\nWRONG_QUESTIONS: %s`. F263 only adds the `$3 == 0` rc check to the SKIPPED awk. pinned by: `loomwright/evals/coordinator-model/lib/selftest.sh` and case `05-mutation-control-wrong-expected`.
- **`.agent/companions.json`** — keep: the strict shape `"schema_version": 1` with `{"when": …, "add": [...]}` rows (a malformed file makes the planner exit 1 `companions_malformed`). fired by: `loomwright/scripts/automate-helpers.d/plan-waves.sh` (`<root>/.agent/companions.json expansion`) and `right-size.sh`, which expand every item's Touches with it. F293 adds only `loomwright/docs/prompt-token-budgets.json` to the `loomwright/commands/*` and `loomwright/skills/*` `"new": true` rows (both already list `loomwright/docs/ARCHITECTURE_CONTRACTS.md`; no duplicate entry), which widens the planner's Touches set for new commands/skills only. pinned by: `loomwright/scripts/test-skills-index-companion.sh`, `loomwright/scripts/test-wave-scope.sh`, `loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh` (re-run all three; update a fixture only if it reads the live file).
- **`loomwright/docs/loop-inventory/launch-pad-autonomous.md`** — keep: the row grammar `| LP-234 | commands/launch-pad.md | h: ### Critical Rules |` and the numbered GAP list entry `317. LP-234 — untested standing rule`. Splitting the row (F248) must update the GAP list and its numbering in the same change (house rule 2), or F248 is recorded `not worth fixing`. pinned by: `loomwright/scripts/test-loop-inventory.sh`.
- **`loomwright/agents/worker.md`** — keep: `Claude Code ignores frontmatter hooks for plugin-distributed agents`. F084 either mirrors every `loomwright:worker` leaf in `hooks.json` (each with its `|| true`) or drops the "mirrors" claim. pinned by: `check-token-budget.sh` (`.agents["worker"]` ceiling) and `check-prompt-history-refs.sh` baseline.

## Pin mutations

> The legs are written by the workers, so the leg names are theirs. F069 is a test-only fix (the defect is the test's own (S) predicate), so it has no code mutation row and is recorded `fixed (test-only: test-build-capabilities.sh <leg>)`; its proof is a tools-less agent fixture that the old (S) predicate rejects and the relaxed one accepts. Each row's mutation restores the pre-fix code the leg protects (quoted from base 83a4549) and must turn that leg red. Rows are in prose form (reviewer D1 fallback applies them).

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-review-heal-next-step.sh` — F016 unresolved-branch remaining_issues | restore `local m=1; [ "$unres" -gt "$m" ] && m="$unres"; [ "$seen" -gt "$m" ] && m="$seen"` on both branches in `loomwright/scripts/review-heal-next-step.sh` |
| `loomwright/scripts/test-review-heal-next-step.sh` — F195 off-list verdict | restore `st_set rules_gate "$rj_"` storing the raw string in `rh_confirm` |
| `loomwright/scripts/test-review-heal-next-step.sh` — F197 marker-less bot thread | restore `st_set human_threads "$(( $(jlen "$(stj round_threads)") - $(jlen "$thr") ))"` |
| `loomwright/scripts/test-review-heal-next-step.sh` — F198 non-Actions /job/ URL | restore `sed -n 's#.*/job/\([0-9][0-9]*\).*#\1#p'` unanchored |
| `loomwright/scripts/test-automate-helpers-modules.sh` — F119 duplicate `#:@` group | delete the new repeat-name check in `_ah_usage` (`loomwright/scripts/automate-helpers.sh`) |
| `loomwright/scripts/test-automate-helpers-modules.sh` — F055 empty family file | restore `{ [ -f "$_ah_f" ] && [ -r "$_ah_f" ]; } \|\| die` without `-s` |
| `loomwright/scripts/test-automate-helpers.sh` — F155 huge --wait / multi-doc state | delete the new length cap / first-line take in `park_ask_gate` |
| `loomwright/scripts/test-automate-helpers.sh` — F159 extra positionals | delete the new k==0 check beside `--lane-backlog) lane=1 ;;` |
| `loomwright/scripts/test-automate-helpers.sh` — F344 / F345 / F346 | delete the new lock trap; delete the new `count == _BL_PR_LIMIT` check; delete the new calendar round-trip (each its own leg) |
| `loomwright/scripts/test-run-pin-mutations.sh` — F162 escaped pipe in Pin cell | restore `pin_cell="$(trim "${inner%%\|*}")"` splitting on the first raw pipe |
| `loomwright/scripts/test-read-token-ledger.sh` — F302 real primary-run line | restore `grep -oE 'run created \(session [A-Za-z0-9_-]+\)'` |
| `loomwright/scripts/test-read-token-ledger.sh` — F303 / F306 | restore the per-item `pi_extract` call with no cache; restore the single `resumed after park` label for a fix-now re-drain |
| `loomwright/scripts/test-build-handoff.sh` — F020 `/` in title ERE | restore `sed -nE "s/${RUN_TITLE_ERE}[[:space:]]*//p"` |
| `test-automate-next-step.d/` — F131 colon in validation title | restore `chk="$(printf '%s\n' "$vg" \| sed -n 's/^validation-gate: unrun — \(V[0-9][0-9]* [^:]*\): .*/\1/p')"` in `loomwright/scripts/automate-next-step.sh` |
| `test-automate-next-step.d/` — F181 superseded closeout via seam | restore the direct `out="$(bash "$H" closeout "$RF" "$ITEM" "$pr" ${SID:+--session-id "$SID"} 2>/dev/null)"` on the superseded path |
| `loomwright/scripts/test-automate-next-step.sh` — F182 R12 reader discovery | add a new `^- `-anchored `## Progress` prefix reader in a script file outside the old fixed six-reader list, with a prefix the driver does not write; the discovering R12 must turn red (the fixed-list R12 stays green on it) |
| `loomwright/scripts/test-automate-next-step.sh` — F183 R7 rate-limit re-print | make `ns_reprint` rewrite (append a `## Progress` line) on the rate-limited-park re-send in `loomwright/scripts/automate-next-step.sh`; the new R7 case must turn red |
| `test-automate-next-step.d/` — F261 message from NS_CM_VALUES | restore the hard-coded `is not session \| claude-haiku-5-5 \| claude-sonnet-5-5` text in `ns_cm_configured` |
| `test-automate-next-step.d/` — F316 inherited seam ignored | delete the new test-marker guard around `NEXT_STEP_FROM` / `NEXT_STEP_UNTIL` / `NEXT_STEP_CLOSEOUT_OUT` |
| `test-automate-next-step.d/` — F317 refused-waiver branch | delete `st_set waive_refusal "$out"`'s surfacing in the escalation message (or, if dropped, re-add the write-only key); the refused-waiver leg must turn red |
| `test-automate-next-step.d/` — F208 stopped run not left running | delete the new `## Status` rewrite before `ns_emit done reconcile` in `ns_reconcile_open` |
| `test-automate-next-step.d/` — F259 re-print coordinator_model | delete the new re-resolve in `ns_reprint` (skip this row if F259 is recorded as doc-only) |
| `test-automate-next-step.d/` — F260 stale-lock break token | delete the new owner-token re-check in `ns_cm_break` |
| `test-automate-next-step.d/` — F209 (only if the early return is dropped) | restore `[ "$rc" -eq 0 ] \|\| { ns_err …; return 1; }` before `ns_classify_or_leftover` in `ns_reconcile_merged` |
| `test-automate-next-step.d/` — F263 `ns_checkout_of` git/pwd fallback | flip `git -C "$1" rev-parse --show-toplevel 2>/dev/null \|\| pwd` → `pwd` in `loomwright/scripts/automate-next-step.sh` |
| `loomwright/scripts/test-build-capabilities.sh` — F065 dup-fd redirect | restore the `(?<![<>&0-9])` scan without the dup-fd case in `loomwright/scripts/build-capabilities.sh` |
| `loomwright/scripts/test-build-capabilities.sh` — F121 non-literal failures.log | restore `$hc` without `$iw` in `loomwright/scripts/build-capabilities.sh` |
| `scripts/test-check-token-budget.sh` — F294 / F295 / F297 / F298 | restore `[ -n "$key" ] \|\| continue`; restore the bare `"$COMMANDS_DIR"/*.md` loop with no subdir check; restore the per-guard `exit 1`; restore the `is a dangling symlink` label for a dir symlink |
| `scripts/check-skills-index-sync.sh --self-test` — F057 BOM / leading blank | restore `NR == 1 && !/^---[[:space:]]*$/ { exit }` as the only line-1 handling |
| `scripts/test-check-prompt-history-refs.sh` — F278 | restore the unguarded `[a-z][a-z0-9-]*/[0-9]{2}[a-z]?` alternative |
| `loomwright/scripts/test-module-shape-facts.sh` — F369 / F367 / F366 (if anchored) | restore symbolic `$head` in merge-base/diff/grep; drop the pipeline status check; restore `^[ \t]*` in `DEF_AWK` |
| `loomwright/evals/coordinator-model/lib/selftest.sh` — F263 refused answer | restore `if (k[j] == 1) { a = 1; break }` without the rc test |
| `loomwright/scripts/test-build-vault.sh` — F089 | restore `duration_seconds:(.duration_seconds//null),` projection |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Part 04a: next-step / review-heal drivers, helpers, backlog, token ledger, handoff, pin runner, postmortem docs | AC1, AC3, AC4, AC5 (04a findings) | ~27 modify, 1 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | Part 04b: gate tooling + the single fragment and version bump | AC2, AC3, AC4, AC5 (04b findings), AC6 | ~20 modify, 1 create (fragment, folded) | `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "docs/evidence/dismissed-followups-12-bundle-04ab.md"}
  - {kind: "symbol", path: "docs/evidence/dismissed-followups-12-bundle-04ab.md", name: "## Part 04a dispositions"}
  - {kind: "symbol", path: "loomwright/scripts/review-heal-next-step.sh", name: "rh_confirm"}
  - {kind: "symbol", path: "loomwright/scripts/read-token-ledger.sh", name: "pi_cc_ids"}
requires: []
lanes:
  - "docs/evidence/dismissed-followups-12-bundle-04ab.md"
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.d/*.sh"
  - "loomwright/scripts/fixtures/automate-golden/**"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/scripts/review-heal-next-step.sh"
  - "loomwright/scripts/test-review-heal-next-step.sh"
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/automate-helpers.d/backlog.sh"
  - "loomwright/scripts/automate-helpers.d/resume.sh"
  - "loomwright/scripts/automate-helpers.d/intake.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers-modules.sh"
  - "loomwright/scripts/read-token-ledger.sh"
  - "loomwright/scripts/test-read-token-ledger.sh"
  - "loomwright/scripts/build-handoff.sh"
  - "loomwright/scripts/test-build-handoff.sh"
  - "loomwright/scripts/run-pin-mutations.sh"
  - "loomwright/scripts/test-run-pin-mutations.sh"
  - "loomwright/scripts/pr-postmortem-gather.sh"
  - "loomwright/docs/result-schemas/postmortem-result.md"
  - "loomwright/scripts/test-pr-postmortem-gather.sh"
  - "loomwright/skills/pr-postmortem/SKILL.md"
  - "loomwright/skills/user-story-writing/SKILL.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
external_requires:
  - "jq, awk, git, python3 on PATH (existing CI image)"

# Subtask 2
provides:
  - {kind: "symbol", path: "docs/evidence/dismissed-followups-12-bundle-04ab.md", name: "## Part 04b dispositions"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "Dismissed follow-ups 04a+04b: driver and gate tooling fixes"}
  - {kind: "symbol", path: "loomwright/scripts/build-capabilities.sh", name: "host_mode"}
requires:
  - {from: "1", kind: "symbol", path: "docs/evidence/dismissed-followups-12-bundle-04ab.md", name: "## Part 04a dispositions"}
lanes:
  - "docs/evidence/dismissed-followups-12-bundle-04ab.md"
  - "loomwright/scripts/build-capabilities.sh"
  - "loomwright/scripts/test-build-capabilities.sh"
  - "loomwright/capabilities.json"
  - "loomwright/docs/CAPABILITIES_CONTRACT.md"
  - "scripts/check-token-budget.sh"
  - "scripts/test-check-token-budget.sh"
  - "scripts/check-skills-index-sync.sh"
  - "scripts/check-prompt-history-refs.sh"
  - "scripts/test-check-prompt-history-refs.sh"
  - "loomwright/docs/prompt-history-refs-baseline.json"
  - "loomwright/scripts/module-shape-facts.sh"
  - "loomwright/scripts/test-module-shape-facts.sh"
  - "loomwright/scripts/build-vault.sh"
  - "loomwright/scripts/test-build-vault.sh"
  - "loomwright/evals/coordinator-model/lib/stage-golden.sh"
  - "loomwright/evals/coordinator-model/lib/selftest.sh"
  - "loomwright/scripts/test-automate-next-step.d/*.sh"
  - "loomwright/agents/worker.md"
  - ".agent/companions.json"
  - "loomwright/scripts/test-skills-index-companion.sh"
  - "loomwright/scripts/test-wave-scope.sh"
  - "loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh"
  - "loomwright/docs/loop-inventory/launch-pad-autonomous.md"
  - "loomwright/scripts/test-loop-inventory.sh"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/dismissed-followups-04a-next-step-and-review-heal-driver-defects.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires:
  - "jq, awk, git, python3 on PATH (existing CI image)"
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `docs/evidence/dismissed-followups-12-bundle-04ab.md`, `loomwright/scripts/test-automate-next-step.d/*.sh` (F263's `ns_checkout_of` fallback leg), `loomwright/docs/prompt-token-budgets.json`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | YES |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1; it also writes the one fragment and runs the version bump, so it must be last)
- **Recommended workers:** 1 at a time
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): 50 findings in one PR exceed one worker's context | MEDIUM | Split into 2 sequential subtasks by Part. Each worker re-verifies only its Part. A finding that turns out larger than a local fix is recorded `not worth fixing: <reason>` for the owner rather than widened |
| Feasibility (Phase 2.5): the plan needs paths outside the requirement's Touches (the `park_ask_gate`/`queue_confirm` families, three skills, `worker.md`, companions, loop-inventory, the suites that test them, the evidence file) | MEDIUM | Asked once at Phase 6 (LP-SCOPE) before save |
| F316 test-seam gating must reach every real seam setter (the next-step harness and `.d/` legs, the goldens, `test-read-token-ledger.sh`) | MEDIUM | Set the marker in the shared hermetic test env so every setter inherits it in the same change, then run those suites. Never gate the seams in `automate-next-step.sh` without that, which would turn the goldens red |
| Requirement asks dispositions be "recorded in this file", but the requirement lives under gitignored `.supervisor/requirements/`, which is absent from worker worktrees | MEDIUM | The committed evidence file is the record (AC1/AC2). The owner/closeout may copy it into the requirement on the metadata branch |
| Skill/agent prompt edits (F014, F019, F124, F084) push a byte ceiling or the history-refs baseline | MEDIUM | Write no finding ids / queue paths into prompts. Run `bash scripts/check-token-budget.sh` and `bash scripts/check-prompt-history-refs.sh`. Raise a ceiling only with the mirror row in `ARCHITECTURE_CONTRACTS.md`, never the history baseline |
| F346 calendar check uses a non-portable `date` flag (BSD vs GNU) | MEDIUM | Validate with pure arithmetic (days-in-month + leap rule) or try both `date -j -f` and `date -d`. Test on the CI (Linux) path |
| Root `scripts/test-*.sh` suites run in CI only because `ci.yml` names them | LOW | Add legs to the existing named suites (`scripts/test-check-token-budget.sh`, `scripts/test-check-prompt-history-refs.sh`). Never create a new root test file without a `ci.yml` step |
| `build-capabilities.sh` change alters a real leaf's classification | MEDIUM | Run `build-capabilities.sh --check`. A diff in `loomwright/capabilities.json` for a current leaf means the change is not latent-only: stop and record |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-11-bundle-04ab-drivers-and-gate-tooling.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-11T08:53:20Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/880
- **Branch:** feature/bundle-04ab-drivers-and-gate-tooling
- **Files changed:** 56
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal reason:** max_iterations_reached
- **Heal iterations:** 3
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** All 50 dismissed follow-ups in bundle 04a+04b have a disposition in docs/evidence/dismissed-followups-12-bundle-04ab.md (40 fixed, 1 duplicate, 1 not reproducible, 8 not worth fixing), folded as one fragment into v17.36.1. Phase 4.5 rounds 1-2 were reviewer PASS with MEDIUM findings plus a red ci check in round 2 (pipefail grep -q, fixed sleep); all were fixed. Round 3 FAIL: a HIGH lock-ownership race in the new backlog_stamp trap, reproduced by the reviewer, plus a MEDIUM BL15 flake window. Both were fixed in 1862476 with a red-then-green leg (BL17), but the cap was reached, so that fix is NOT re-reviewed. Mid-run, another session switched the main checkout to fix/874-ruleset-required-checks with uncommitted edits, so heal rounds 2-3 ran in the worktree ../ai-agent-manager-bundle04ab. Dismissed (LOW): execute-manager.md stale mirrors-hooks.json note (pre_existing); F208 reason is a testability gap; backlog_stamp mktemp copy left on kill. Ground truth 2/2 pass; rules_check none; rules_audit clean.

## Not verified
- **test-automate-helpers-modules.sh, which the brief named for F119/F055** — not edited; its loader logic is unchanged and --affected did not list it (subtask 1)
- **check-skills-index-sync.sh BOM/blank-line handling under Linux mawk/gawk** — macOS awk only; CI --self-test covers it (subtask 2)
- **PR full ci check** — not pushed at worker time (subtask 2)
