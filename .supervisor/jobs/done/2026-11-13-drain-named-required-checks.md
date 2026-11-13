# Supervisor Job: The drain honours a named required-checks set on a base branch that cannot be protected

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (3 entries: `REQUIREMENTS-SITE-V2.md`, `reports/`, `research_notes/` — none in this brief's paths), branch: docs/site-v2-selvedge (planned against `origin/main`, read from a `git archive` snapshot of it)
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (dirty tree on a non-base branch; 3 agent worktrees under `.claude/worktrees/`)
- **Source requirement:** .supervisor/requirements/drain-named-required-checks/2026-11-12-081956-drain-honours-a-named-required-checks-set.md
- **Base commit:** 40b3f49b1525e647ea1ee7d0a49084357857cd8d

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq + `gh`, the drain's existing stack; no new dependency |
| 2 | Dependency Availability | GO | Reuses `drain-gh-read.sh required-checks`, `protection-paid-plan.sh`, `required-checks-rulesets.sh`, `wait-for-checks-line.sh` |
| 3 | Architecture Fit | GO | `rh_required` already holds the required-mode precedence; the config read follows the driver's existing `cfg="$ROOT/.supervisor/config.json"` idiom |
| 4 | Scope vs Supervisor Capability | CAUTION | 19 files (16 modify, 3 create): over the one-worker bound, split `context-bound` into 3 subtasks |
| 5 | Hard Blockers | CAUTION | Validation 2 (running system) needs an owner private GitHub-Free repo with a green named check and a red non-code check; an unattended worker may not reach one. AC 5's "reviews-only protection" response from `…/protection/required_status_checks` is not verified live (see Risk Assessment) |

**Overall Verdict:** CAUTION

## Task
**Goal:** A repo can declare `required_checks: ["<name>", …]` in `.supervisor/config.json`, or pass `--required-checks name:<a>,<b>`. When, and only when, branch protection cannot supply a required list, the `/review-pr --until-mergeable` drain waits on and gates READY on exactly that set. A named check that is missing or never reports fails closed (`required_check_absent <name>`). Readable protection always wins. The `--auto-merge` gate never reads the set.

**Problem Statement:**
An owner running `/automate` or `/review-pr --until-mergeable` on a private GitHub-Free repo needs to name the checks that gate READY once, because a check that is red for a reason no code fix can reach (a deployment integration failing on the git author's permissions) blocks READY forever today.
Currently, when the base's required-check list cannot be read, `rh_required` either escalates `required_checks_unavailable` or (paid-plan refusal / `--required-checks all-non-neutral`) gates READY on every non-neutral check. The drain correctly spawns no fix worker for a non-code red check, so READY is unreachable, and `/automate` has no flag or config route to change that (GitHub issue vikashruhilgit/loomwright#805).
Success looks like: on a private Free repo with a permanently red deployment check, an `/automate` item reaches a READY park with no per-run flag.

## Acceptance Criteria

**Happy path:**
- [ ] 1. Given protection unreadable and config `required_checks: ["Unit Tests"]`, and a rollup with `Unit Tests` SUCCESS and a deployment check FAILURE, when the drain runs, then it waits only on `Unit Tests` (plus review-producing checks, as today), records `required_mode named` with `required_names` = `["Unit Tests"]`, ignores the deployment check, and can reach READY (a new golden case `fixtures/review-heal-golden/named-required-ready` pins it).
- [ ] 2. Given the same and `--required-checks name:Unit Tests,Lint`, when the drain runs, then the flag's set wins over the config's (`required_names` = `["Unit Tests","Lint"]`; `Lint` is required).
- [ ] 3. Given the confirming pass on a pushed fix commit under `required_mode named`, when it runs (`wait-for-checks.sh --required-only --names` plus the named set), then it confirms only the named set, not every non-neutral check.

**Edge cases:**
- [ ] 4. Given readable protection requiring `ci` and config `required_checks: ["Unit Tests"]`, when the drain runs, then the required set is exactly `["ci"]` with `required_mode protected`; the config set is neither added nor substituted — in `rh_required` and in `wait-for-checks.sh` (its own readable read wins over the drain's named set).
- [ ] 5. Given readable protection with an empty required list (reviews only) and the config set, when the drain runs, then the config set is ignored (protection wins) in both the drain and the wait — the outcome equals main's for the same protection with no config key.
- [ ] 6. Given protection unreadable, config set, and `--required-checks all-non-neutral`, when the drain runs, then the flag wins (`required_mode all-non-neutral`).

**Error scenarios:**
- [ ] 7. Given `required_checks: ["Unit Tests"]` and a head whose rollup never shows `Unit Tests`, when the wait bound passes, then the drain ends ESCALATED with message `required_check_absent` naming `Unit Tests` (a reason distinct from `check_wait_elapsed`), never READY.
- [ ] 8. Given `required_checks` set to `[]`, `"Unit Tests"`, or `[1]`, when the drain runs with protection unreadable, then it ends ESCALATED `required_checks_unavailable`, with a message naming the malformed key `required_checks`.
- [ ] 9. Given neither readable protection, nor a flag, nor a config key, when the drain runs, then the outcome is byte-identical to main before this change for each of: a plain 404 with no ruleset, the paid-plan 403, and classic 404 + rulesets paid-plan 403. The three pins are written first, pass against base `40b3f49`, and still pass after.
- [ ] 10. Given `--required-checks name:` or `--required-checks name:,a`, when the drain starts, then it exits 2 with a usage error, prints nothing and writes nothing.

**`/automate` paths:**
- [ ] 11. Given a lane created from a primary whose config carries `required_checks`, when the lane's drain runs, then it reads the set from the lane clone's own config: `test-automate-lanes.d/01-create-to-wait.sh` asserts the copied config keeps the `required_checks` key, and `test-review-heal-next-step.sh` asserts the driver reads `--root`'s `.supervisor/config.json` (not the cwd's).
- [ ] 12. Given the inline drain and the fresh-phase drain prompt built by `scripts/automate-next-step.sh` (and the fix-now re-drain), then each invokes the drain with no `--required-checks`, so the config set applies; a test in `test-review-heal-next-step.sh` asserts that absence over every `/review-pr … --until-mergeable` invocation string `automate-next-step.sh` builds, so a later passthrough cannot silently shadow the key.

**Setup surface:**
- [ ] 13. Given a stubbed unreadable base protection and no `required_checks`, when `setup-base-branch.sh status` runs, then it prints the advisory line "base branch has no readable required-check list and no `required_checks` set — every drain will gate READY on every non-neutral check (or escalate)" plus a fix line, and exits as it does today (0). With the key set, the line is absent. Every existing `test-setup-base-branch.sh` case still passes unchanged.

**Validation:**
- [ ] 14. Given the merged-ready branch, when `bash scripts/ci-local.sh --affected` and `bash scripts/check-version-bump.sh` run, then both pass (covering `test-review-heal-next-step.sh`, `test-wait-for-checks.sh`, `test-setup-base-branch.sh`, the lanes create test, `test-loop-inventory.sh`, `check-doc-currency.sh`, `check-token-budget.sh`, `check-prompt-history-refs.sh`, `test-citation-drift.sh`), with a `changelog.d/drain-named-required-checks.md` fragment and no hand-edited version file.
- [ ] 15. Given one of the owner's private GitHub-Free repos whose PR has a green named check and a red non-code check, when `/review-pr <pr-url> --until-mergeable` runs with `required_checks` set in that repo's `.supervisor/config.json`, then it reaches READY, and with the named check renamed to a typo it ends ESCALATED `required_check_absent`; then a committed evidence file `docs/evidence/drain-named-required-checks.md` contains both runs' fenced output (owner and repo names redacted) and the column-0 line `Verdict: PASS for Validation 2`, and the PR body links to it. If no such repo is reachable from the run, the file records that and carries `Verdict: NOT RUN for Validation 2` — never a PASS for a run that did not happen.

## Scope widening
- loomwright/scripts/fixtures/review-heal-golden/MAP.tsv
- accepted: LP-SCOPE 2026-11-13

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

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| drain + wait (Subtask 1) | `loomwright/scripts/review-heal-next-step.sh` (1211 — `rh_required` and the flag parser are the single authority for the required-mode precedence; the config read and named-set validation are ~30 lines beside them), `loomwright/scripts/wait-for-checks.sh` (622 — its protection-read block is the one place its required set is decided; the named-set argument plugs into it), `loomwright/scripts/test-review-heal-next-step.sh` (1442 — its `B:` leg already owns every required-mode case), `loomwright/scripts/test-wait-for-checks.sh` (1027 — the stubbed-`$GH` protection cases live here), `loomwright/scripts/fixtures/review-heal-golden/MAP.tsv` (23 — one row for the new case), `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` (825 — one assertion beside its `A5 config.json byte-for-byte` check) | `loomwright/scripts/fixtures/review-heal-golden/named-required-ready/` (drive, gh.table, wait.lines, report-1.json, expected.*) | HIGH |
| setup surface (Subtask 2) | `loomwright/scripts/setup-base-branch.sh` (288), `loomwright/scripts/test-setup-base-branch.sh` (297) | — | HIGH |
| docs + release (Subtask 3) | `loomwright/skills/review-heal/SKILL.md` (583 — §U2 and the flag table are the authority being amended), `loomwright/commands/review-pr.md` (72), `loomwright/agents/review-pr.md` (151), `loomwright/docs/result-schemas/review-heal-next-step.md` (113), `loomwright/docs/result-schemas/review-heal-result.md` (130), `loomwright/docs/loop-inventory/review-heal.md` (422), `loomwright/docs/prompt-token-budgets.json` (93 — only if a measured doc outgrows its ceiling), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1069 — only the §"Prompt Token Budgets" mirror row of a budget that moves) | `changelog.d/drain-named-required-checks.md`, `docs/evidence/drain-named-required-checks.md` | HIGH (budgets/ARCH: MEDIUM — conditional) |

> **Validator-owned surfaces:** `check-doc-currency.sh`, `check-token-budget.sh` (budgets for `skills/review-heal`, `commands/review-pr`, `agents/review-pr`), `test-loop-inventory.sh` (every `q:` row in `docs/loop-inventory/review-heal.md` quotes its source text — an edited quote in SKILL.md / review-pr.md must be mirrored there), the `PROSE_PINS` heredoc in `loomwright/scripts/test-review-heal-next-step.sh` (fixed literals it greps in the docs Subtask 3 edits — RH-006 `**`--required-checks all-non-neutral`**`, RH-097 `**Escape hatch:** `--required-checks all-non-neutral``, RH-300 `Default behavior **fails CLOSED** — unreadable metadata ⇒ the loop MUST NOT claim READY`) and `test-citation-drift.sh` (no new bare `file:N` citation) all scan files this brief edits.

**Unchanged but load-bearing (read, not edited):** `loomwright/scripts/automate-lanes.d/create.sh` (copies `config.json` into the lane), `loomwright/scripts/automate-next-step.sh` (builds the three drain invocations), `loomwright/scripts/drain-gh-read.sh`, `loomwright/scripts/protection-paid-plan.sh`, `loomwright/scripts/required-checks-rulesets.sh`, `loomwright/scripts/wait-for-checks-line.sh`, `loomwright/scripts/automate-helpers.sh` (`gate_eval` — must stay untouched).

**Module layout:** new responsibilities and their one home — (a) `name:` flag parse → the existing `--required-checks)` arm of `review-heal-next-step.sh`; (b) config `required_checks` read + validation → `rh_required` in the same file (single authority for precedence); (c) named set handed to the wait and the confirming pass → the existing `args=(…)` arrays in `rh_wait` / `rh_confirm`; (d) `required_check_absent` detection → `rh_wait`'s `ELAPSED` arm; (e) the wait's second required-set source → `wait-for-checks.sh`'s protection-read block; (f) `/setup` advisory → `do_status` in `setup-base-branch.sh`, reusing `drain-gh-read.sh required-checks` + `protection-paid-plan.sh` (no new protection reader). No helper is copied by 2+ siblings, so no extract row.

## Touched-file invariants

> Grounded at base `40b3f49b1525e647ea1ee7d0a49084357857cd8d`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/review-heal-next-step.sh`** — keep: fail-CLOSED default `rh_escalate_to required_checks_unavailable other 0` (the last `else` of `rh_required` stays the escalate); the paid-plan fallback `|| protection_paid_plan_refusal() { return 1; }`; the protected branch `st_setj required_names "$names"; st_set required_mode protected` stays FIRST; usage errors exit 2 via `rh_die2`, nothing printed or written; drain flags are taken by `--start drain` only and persist in the sidecar (`flag_required_checks: $rq`); never merges/approves (`Never merges, never approves, never force-pushes`). reuse: the ROOT-relative config idiom `cfg="$ROOT/.supervisor/config.json"` (read `$ROOT`'s file, never the cwd's); the `RH_WAIT_CMD` seam for tests; `rh_escalate_to <reason> <cause_kind> …` — `required_check_absent` uses the check-driven kind like `check_wait_elapsed check 0` so `escalation_cause` comes from the existing helper (no new `escalation_cause` value). mirror: the wait line is read only through `wfc_line_parse` (`. "$HERE/wait-for-checks-line.sh"`); `rh_wait`'s `*" required=unknown "*)` arm must not escalate a named-mode run whose wait used the named set; `rh_confirm` keeps `--required-only --names`. pinned by: `test-review-heal-next-step.sh` (`required_checks_unavailable`, `--required-checks all-non-neutral`, `paid_case`) and the golden harness (`REQUIRED_BRANCHES`, `MAP.tsv`).
- **`loomwright/scripts/wait-for-checks.sh`** — keep: `ALWAYS exits 0`; exactly one final line, grammar `SETTLED sha=<sha> required=<green|red|unknown>` unchanged (any grammar change changes `wait-for-checks-line.sh` in the same commit — prefer no grammar change); `"${GH:-gh}"` test seam; bash 3.2, no `timeout`; a required context absent from the rollup is pending, never green (`A required context ABSENT from the rollup is`). Without the new argument the output is byte-unchanged for every existing caller (`phase45-ci-read.sh`, `automate-helpers.d/escalation.sh`, `dispatch-pr-review.sh`, `drain-subfloor-decision.sh`). The named set replaces the read's result only when that read yields no list: the paid-plan arm (`elif [ "$_prot_rc" -ne 0 ] && protection_paid_plan_refusal "$_prot"; then`), the unreadable arms (`protection_unknown=1`), and the 404-no-ruleset arm (`none) required_contexts_json="[]" ;;  # verified: no classic protection, no ruleset check`); a 200 read (even an empty list) and a 404 + ruleset list always win. pinned by: `test-wait-for-checks.sh`.
- **`loomwright/scripts/setup-base-branch.sh`** — keep: `status` is read-only and exits 0 (`FAIL-SAFE CONTRACT`; `Only a usage error`… exits 2); `THE RESOLUTION IS NOT RESTATED HERE` (no second base resolver); every existing status line byte-unchanged. reuse: `drain-gh-read.sh required-checks` and `protection-paid-plan.sh` for the read; a repo with no GitHub `owner/repo` origin prints no advisory line (nothing to read). pinned by: `test-setup-base-branch.sh`, which runs with `a failing `gh` stub first on PATH (no case may reach the network)` — new cases stub `gh`; no case reaches the network.
- **`loomwright/scripts/test-review-heal-next-step.sh`** — keep: hermetic (`a stub `gh` first on PATH`), every existing case unchanged and green; the golden G leg's contract — every branch in `REQUIRED_BRANCHES=` is mapped in `MAP.tsv` and every case dir has one row (add the new branch id to `REQUIRED_BRANCHES` with its row); the `PROSE_PINS` heredoc (`PROSE_PINS_EOF`) — Subtask 1 does not edit its RH-006/RH-097/RH-300 rows; reuse: `paid_case()` and `setup_case`/`gh_row` for the AC 9 pins and the new named-mode cases (AC 9's three pins are written and run against base first). Subtask 3 may edit this file ONLY to update a `PROSE_PINS` row whose doc literal it deliberately rewrote (it is ordered after Subtask 1, so the lanes do not race).
- **`loomwright/scripts/test-wait-for-checks.sh`** — keep: fixture-driven, the scripted `$GH` stub (`GH="$D1/gh" bash "$SUT"`), `never a real network call`; every existing numbered case unchanged. New cases call the SUT with the named-set argument and pin: a 200 read wins (AC 4/5), the paid-plan / unreadable / 404-no-ruleset arms use the named set, an absent named check is pending, and without the argument the output is byte-unchanged.
- **`loomwright/scripts/test-setup-base-branch.sh`** — keep: `run() { local e="$1" r="$2"; shift 2;` and the `CASES=` list's existing cases unchanged (their status output byte-identical: the local bare origin has no GitHub slug, so no advisory line prints); new cases (line printed / line absent with the key) use a `gh` stub on PATH that answers the protection read, never the network.
- **`loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh`** — keep `check "A5 config.json byte-for-byte"`; add the key-level assertion beside it, never replacing it.
- **`loomwright/scripts/fixtures/review-heal-golden/MAP.tsv`** — keep its contract (header: `every row names an existing case directory`, and every case directory but `_common/` has exactly one row); one new row for `named-required-ready`.

## Closed enumerations touched

> Sibling greps at base `40b3f49`: `grep -rnF 'no_required_list' --exclude=CHANGELOG.md .` → 5 hits in 2 files; `grep -rnF 'head_unstable' --exclude=CHANGELOG.md .` → 8 hits in 3 files; `grep -rnF 'all-non-neutral' --exclude=CHANGELOG.md .` → 34 hits in 9 files.

- **`required_mode named`** (sibling: `no_required_list`) — must be named in:
  - `loomwright/scripts/review-heal-next-step.sh` — `rh_required`'s mode assignments — extend.
  - `loomwright/scripts/wait-for-checks.sh` — its own `no_required_list` flag, not the drain's mode — no change: the wait takes the named set as an argument, not a mode.
  - `loomwright/docs/result-schemas/review-heal-next-step.md` — the `required` step row (`` `required` ``) — extend: list every `required_mode` value (`protected`, `all-non-neutral`, `named`, `no_required_list`) in precedence order (scope 8).
- **`required_check_absent`** (sibling: `head_unstable`) — must be named in:
  - `loomwright/scripts/review-heal-next-step.sh` — the escalation sites — extend.
  - `loomwright/docs/result-schemas/review-heal-next-step.md` — the `wait` step row — extend.
  - `loomwright/docs/result-schemas/review-heal-result.md` — the ESCALATED reasons prose (`` - `ESCALATED` ``) — extend (scope 8).
  - `loomwright/scripts/test-review-heal-next-step.sh` — pins — extend (AC 7).
- **`--required-checks name:<a>[,<b>…]`** (sibling value: `all-non-neutral`) — must be named in:
  - `loomwright/scripts/review-heal-next-step.sh` — the `--required-checks)` arm and the USAGE header — extend.
  - `loomwright/skills/review-heal/SKILL.md` — flag table row `Required-check fallback` and §U2 `Escape hatch` — extend.
  - `loomwright/commands/review-pr.md` — flag row `--required-checks all-non-neutral` — extend.
  - `loomwright/agents/review-pr.md` — `Fail CLOSED on unknowns (AC14).` — extend.
  - `loomwright/docs/loop-inventory/review-heal.md` — rows RH-006, RH-097, RH-138, RH-300, RH-365 quoting the flag — extend (each `q:` must still match its source).
  - `loomwright/docs/result-schemas/review-heal-next-step.md`, `loomwright/docs/result-schemas/review-heal-result.md` — usage line / ESCALATED prose — extend.
  - `loomwright/scripts/test-review-heal-next-step.sh` — pins — extend (AC 2, 6, 10).
  - `loomwright/docs/SPIKES/FABLE_PARITY_EVAL.md` — a historical eval table — no change: a frozen record, not a list of accepted values.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-review-heal-next-step.sh` — AC 9 paid-plan pin (main's outcome) | delete `st_setj required_names 'null'; st_set required_mode no_required_list` in `loomwright/scripts/review-heal-next-step.sh` |
| `loomwright/scripts/test-review-heal-next-step.sh` — AC 4 protection wins | delete `st_setj required_names "$names"; st_set required_mode protected` in `loomwright/scripts/review-heal-next-step.sh` |
| `loomwright/scripts/test-review-heal-next-step.sh` — AC 12 no passthrough | flip `local dinv="/review-pr $PR --until-mergeable --no-auto-postmortem"` → `local dinv="/review-pr $PR --until-mergeable --no-auto-postmortem --required-checks all-non-neutral"` in `loomwright/scripts/automate-next-step.sh` |
| `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` — AC 11 key kept | flip `for cf in config.json notify-config.json; do` → `for cf in notify-config.json; do` in `loomwright/scripts/automate-lanes.d/create.sh` |
| `loomwright/scripts/test-review-heal-next-step.sh` — AC 1 named mode | Move the new config branch below the paid-plan branch in `rh_required` (paid-plan then wins ⇒ `required_mode no_required_list`, the deployment check blocks READY) |
| `loomwright/scripts/test-review-heal-next-step.sh` — AC 2 / AC 6 flag over config | Swap the flag and config branches in `rh_required` (config then wins over `name:` / `all-non-neutral`) |
| `loomwright/scripts/test-review-heal-next-step.sh` — AC 7 absent | Delete the `required_check_absent` escalation in `rh_wait`'s ELAPSED arm (falls back to `check_wait_elapsed`) |
| `loomwright/scripts/test-review-heal-next-step.sh` — AC 8 malformed | Delete the `required_checks` type/emptiness validation (a malformed value is then read as unset) |
| `loomwright/scripts/test-review-heal-next-step.sh` — AC 10 empty names | Delete the empty-name/empty-list refusal in the `name:` parse |
| `loomwright/scripts/test-review-heal-next-step.sh` — AC 3 confirming pass | Drop the named-set argument from `rh_confirm`'s `args=(…)` (the confirm then reads every non-neutral check after a paid-plan read) |
| `loomwright/scripts/test-wait-for-checks.sh` — AC 4/5 own readable read wins | Make the named-set argument override the 200-read arm in the protection-read block |
| `loomwright/scripts/test-wait-for-checks.sh` — named absent is pending | Count only materialized named checks toward `_req_total` (an absent named check then settles green) |
| `loomwright/scripts/test-setup-base-branch.sh` — AC 13 line | Delete the advisory-line `echo` in `do_status` |
| `loomwright/scripts/test-setup-base-branch.sh` — AC 13 key set | Drop the `required_checks`-present guard on the advisory line (the line then prints with the key set) |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Drain + wait honour the named set (flag, config, precedence, absent, confirm) with tests and golden case | 1–12, 14 (its gates) | 6 modify, 1 create | `skills/review-heal/SKILL.md` (read-only reference), `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | `/setup base-branch status` advisory line | 13, 14 (its gate) | 2 modify, 0 create | `skills/review-heal/SKILL.md` (read-only reference) | LAUNCHABLE |
| 3 | Docs, budgets, changelog fragment, Validation 2 evidence | 14, 15 | 8 modify, 2 create | `skills/review-heal/SKILL.md` | BLOCKED (by #1, #2) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/review-heal-next-step.sh", name: "required_check_absent"}
  - {kind: "symbol", path: "loomwright/scripts/review-heal-next-step.sh", name: "required_mode named"}
  - {kind: "file", path: "loomwright/scripts/fixtures/review-heal-golden/named-required-ready/expected.result.md"}
  - {kind: "symbol", path: "loomwright/scripts/fixtures/review-heal-golden/MAP.tsv", name: "named-required-ready"}
requires: []
lanes:
  - "loomwright/scripts/review-heal-next-step.sh"
  - "loomwright/scripts/wait-for-checks.sh"
  - "loomwright/scripts/test-review-heal-next-step.sh"
  - "loomwright/scripts/test-wait-for-checks.sh"
  - "loomwright/scripts/fixtures/review-heal-golden/named-required-ready/**"
  - "loomwright/scripts/fixtures/review-heal-golden/MAP.tsv"
  - "loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh"
external_requires:
  - "GitHub REST: repos/<o>/<r>/branches/<b>/protection/required_status_checks 404 body for a reviews-only protected branch (verify, see Risk Assessment)"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/scripts/setup-base-branch.sh", name: "no readable required-check list"}
requires: []
lanes:
  - "loomwright/scripts/setup-base-branch.sh"
  - "loomwright/scripts/test-setup-base-branch.sh"
external_requires: []

# Subtask 3
provides:
  - {kind: "symbol", path: "loomwright/skills/review-heal/SKILL.md", name: "required_checks"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/review-heal-next-step.md", name: "required_check_absent"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/review-heal-result.md", name: "required_check_absent"}
  - {kind: "symbol", path: "loomwright/commands/review-pr.md", name: "--required-checks name:"}
  - {kind: "file", path: "docs/evidence/drain-named-required-checks.md"}
  - {kind: "file", path: "changelog.d/drain-named-required-checks.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/review-heal-next-step.sh", name: "required_check_absent"}
  - {from: "2", kind: "symbol", path: "loomwright/scripts/setup-base-branch.sh", name: "no readable required-check list"}
lanes:
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/commands/review-pr.md"
  - "loomwright/agents/review-pr.md"
  - "loomwright/docs/result-schemas/review-heal-next-step.md"
  - "loomwright/docs/result-schemas/review-heal-result.md"
  - "loomwright/docs/loop-inventory/review-heal.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/drain-named-required-checks.md"
  - "docs/evidence/drain-named-required-checks.md"
  - "loomwright/scripts/test-review-heal-next-step.sh"  # PROSE_PINS rows only, after Subtask 1
external_requires:
  - "An owner private GitHub-Free repo with a green named check and a red non-code check (Validation 2)"
```

**Subtask 3 notes:** the changelog fragment is a lane-style fragment (no bump in the worker; `bash scripts/bump-version.sh` folds it where the run's release step does — `bash scripts/check-version-bump.sh` must pass). Budgets and the `ARCHITECTURE_CONTRACTS.md` mirror row move only for a doc whose measured weight outgrows its ceiling (`check-token-budget.sh` decides). The README/setup command docs are not edited (scope 7 names only the script). Keep the three `PROSE_PINS` literals (RH-006, RH-097, RH-300) verbatim and add the `name:` form and the config key beside them; if a literal must change, update its `PROSE_PINS` row and its loop-inventory `q:` row in the same commit. SKILL.md §U2's sentence `This is the only way to proceed past an unreadable read` becomes false once the config key exists — correct it and loop-inventory row RH-097 together.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 3
Subtask 2 ──→ Subtask 3
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 1 | Subtask 3 | `loomwright/scripts/test-review-heal-next-step.sh` (3 touches only its `PROSE_PINS` rows) | YES (requires — 3 runs after 1) |
| Subtask 2 | Subtask 3 | none | YES (requires) |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2 (parallel)
- **Batch 2:** Subtask 3 (after 1 and 2)
- **Recommended workers:** 2
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/review-heal/SKILL.md` (§U2, §U2.5, §U4 — read, do not edit), `skills/unit-testing/SKILL.md` |
| 2 | `skills/review-heal/SKILL.md` (§U2 — read) |
| 3 | `skills/review-heal/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): AC 5 — the drain reads `…/protection/required_status_checks`, which for a protected branch with no required status checks answers 404 (believed "Required status checks not enabled", NOT verified live); the wait reads `…/protection` (200). If the drain reads that 404 as "no list", the config set would apply on a reviews-only protected base, violating AC 5 | HIGH | Subtask 1 verifies the real 404 body with a read-only `gh api` GET on a reviews-only protected test branch (or GitHub's REST docs) and records it in the AC 5 test's stub; the named branch in `rh_required` fires only for: the paid-plan refusal, a classic 404 whose body is "Branch not protected" with no ruleset list, or another unreadable read — never for a 404 that says the protection exists |
| Feasibility (Phase 2.5): Validation 2 needs an owner private GitHub-Free repo; an unattended worker may not reach one | MEDIUM | AC 15 lets the evidence file carry `Verdict: NOT RUN for Validation 2` with the reason (never a fabricated PASS); the owner runs Validation 2 before merge and the `/automate` validation gate parks until then |
| Feasibility (Phase 2.5): 19 files exceed one worker's bound | MEDIUM | Split `context-bound` into 3 subtasks; 1 and 2 share no file |
| The drain and the wait decide "no list" from two different reads (`required_status_checks` vs `protection`) | HIGH | Touched-file invariant on `wait-for-checks.sh`: the drain only passes the named set when it chose `named`, and the wait uses it only when its own read yields no list (paid-plan / unreadable / 404 with no ruleset); AC 4 and AC 5 are pinned at both layers |
| Config applies on ANY unreadable read (as `--required-checks all-non-neutral` already does), so a token that cannot read a real protection list lets a repo-local file narrow READY | MEDIUM | Scope 3's precedence is the owner's decision; the merge gate never reads the key (non-goal, `gate_eval` untouched), and the config file is the owner's gitignored local file |
| A named check that is absent from the rollup reads as "not red" in `rh_read` (it only scans rollup rows), so the absence must be caught before READY | HIGH | The wait counts an absent named check as pending (never settled); the ELAPSED arm escalates `required_check_absent <name>` when a named check is missing from the rollup; AC 7 + its pin mutation |
| The requirement's mitigation says the result block records `required_mode named` and the set; on base, `required_mode`/`required_names` live only in the sidecar, not in `REVIEW_HEAL_RESULT` | LOW | Not added here (a result-schema key change is outside scope); the sidecar keeps both and `docs/result-schemas/review-heal-next-step.md` documents them. Noted for the owner |
| Golden harness: a new case dir with no `MAP.tsv` row fails the harness (`every case directory … has exactly one row`); `MAP.tsv` is outside the requirement's Touches | LOW | Subtask 1 adds exactly one row; recorded under Scope widening when accepted |
| Loop-inventory `q:` rows quote SKILL.md / review-pr.md text; editing the quoted sentences without the row fails `test-loop-inventory.sh` | MEDIUM | Subtask 3 edits each quoting row in the same change (house rule: restating copy moves with its authority) |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-13-drain-named-required-checks.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-11-13T09:56:24Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/905
- **Branch:** feature/drain-named-required-checks
- **Files changed:** 30
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** 3/3 subtasks merged (drain + wait honour a named required-checks set from `.supervisor/config.json` `required_checks` or `--required-checks name:`; `/setup base-branch status` advisory; docs, changelog fragment, Validation 2 evidence recorded NOT RUN). Phase 4.5: round 1 FAIL (HIGH named set overrode readable classic list when rulesets unreadable; MEDIUM setup predicates drifted; CI red pipefail grep -q) → fix 0221a50 (shared required-checks-named.sh); round 2 FAIL (HIGH reviews-only 404 + unreadable rulesets) → fix c99d19e; round 3 PASS, required CI green. 5 dismissed follow-ups posted to the PR (1 drift, 1 pre_existing, 2 nit, 1 below floor). Validation 2 (AC 15) still needs the owner's live run on a private GitHub-Free repo. Until-mergeable drain not dispatched: /automate owns the drain (auto_review false).

## Not verified
- **live GitHub protection read** — stubbed gh only (subtask 2)
- **setup docs mention of advisory lines** — out of lane; brief says setup docs not edited (subtask 2)
- **404 body 'Required status checks not enabled' for reviews-only protected branch** — no such branch reachable read-only; stubbed; fails closed if different (subtask 1)
- **Validation 2 live drain** — owner repo (subtask 1)
- **Validation 2 live drain** — read-only on real repos; NOT RUN recorded (subtask 3)
