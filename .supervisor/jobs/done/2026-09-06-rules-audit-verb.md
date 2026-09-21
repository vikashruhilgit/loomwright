# Supervisor Job: `/rules audit` — a correctness audit over the standing `.agent/rules/` store

## Environment
- **Project:** ~/Documents/work/AI/loomwright-stateloop
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (verified at handoff — the floor-ui edits were parked in WIP commit `5726dd1`), branch: fix/name-the-untyped-lane (ALREADY MERGED as PR #191 — Supervisor MUST branch from `origin/main`, not from HEAD)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (current branch is merged; base must be `main`)
- **Source requirement:** .supervisor/requirements/auto-2026-09-06-030556-rules-audit-verb.md

## Feasibility (Phase 2.5)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash + jq, matching every existing `loomwright/scripts/*.sh` helper |
| 2 | Dependency Availability | GO | `jq` already a hard dependency of `read-rules.sh` / `add-rule.sh` / `seed-rules.sh` |
| 3 | Architecture Fit | GO | Mirrors the established read-only-engine + interactive-command split (`harvest-conventions.sh` ↔ `/dreaming`) |
| 4 | Scope vs Supervisor Capability | GO | One subtask — script, tests and docs are sequentially coupled, no genuine parallelism |
| 5 | Hard Blockers | GO | No credentials, no migration, no missing module. `audit-rules.sh` does not exist on any branch |

## Task

**Goal:** Add a `/rules audit` verb — a READ-ONLY, PROPOSE-ONLY correctness audit that re-validates
every rule in the committed `.agent/rules/` store, reports inaccuracies **with their evidence**, and
recommends fixes expressed only as EXISTING actions.

**The gap:** `loomwright/scripts/validate-entry.sh` already holds five correctness checks
(`contradiction`, `duplicate`, `provenance` — BLOCKING; `dead_reference`, `cross_repo_reference` —
ADVISORY), and `add-rule.sh` runs all five on every `/rules add`. But it runs them **once, at write
time, against the store as it stood that day.** Nothing re-validates a rule as the repo drifts
underneath it. This adds the over-time half.

## Acceptance Criteria

- [ ] AC1 — Given the committed store, when `bash loomwright/scripts/audit-rules.sh` runs, then it re-runs `validate-entry.sh`'s five checks against every standing rule and prints per-rule findings with evidence.
- [ ] AC2 — Given a `must` rule whose `check` is `null`, when the audit runs, then it is reported as an enforcement claim with no mechanism.
- [ ] AC3 — Given a rule whose `applies_to` glob matches zero repo paths, when the audit runs, then it is reported as a rule that can never fire.
- [ ] AC4 — Given a rule whose `supersedes` names an id absent from the store, when the audit runs, then a dangling supersedes target is reported.
- [ ] AC5 — Given a rule superseded by a later rule, when the audit runs, then it is reported as dead.
- [ ] AC6 — Given any store, when the audit runs, then the store is byte-identical afterwards.
- [ ] AC7 — Given any store, when the audit runs, then no rule's `check` string is ever executed.
- [ ] AC8 — Given a store with zero findings, when the audit reports, then it states the store size and frames "0 issues" as a small-N result, never as evidence the store is sound.
- [ ] AC9 — Given a `validate-entry.sh` that is missing, unreadable, truncated, or whose contract sentinel does not match, when the audit runs, then it reports UNEXAMINED and exits non-zero rather than reporting the store clean.
- [ ] AC10 — Given a `validate_duplicate` / `validate_contradiction` call, when the audit builds `--store`, then it passes a ONE-LINE-PER-RULE comparison corpus, and any `REFUSE_*_UNCOMPARABLE_SHAPE` (rc 2) is surfaced as UNKNOWN, never absorbed as clean.

## Outcomes Rubric

- [ ] `audit-rules.sh` exists, loads `validate-entry.sh` under the same three-clause LOAD GUARD `add-rule.sh` uses, and re-runs all five shared checks — it reimplements none of them
- [ ] `audit-rules.sh` has no write mode and no write flag; a run leaves the store byte-identical
- [ ] All five store-wide checks are implemented and each is proven by a mutation-controlled test, and the same suite asserts no code path ever executes a rule's `check`
- [ ] `/rules audit` is documented in both `commands/rules.md` and `skills/rules/SKILL.md`, and every recommendation it emits names an existing action (`/rules add --supersedes` or `add-rule.sh --retract`)
- [ ] `test-rules-docs.sh` asserts the audit-vs-check distinction is stated, so the naming confusion cannot drift back
- [ ] The small-N honest limit is stated in the audit's own output, not only in the docs
- [ ] An rc-2 "could not examine" from any shared check is reported as UNKNOWN and never as clean

## Executable Acceptance

- corpus-task: doc-currency-green
- corpus-task: version-consistent

> Bullets, not a fenced block: `run-ground-truth.sh` collects only leading-`-` lines between this
> heading and the next `## `, so a fenced code block resolves ZERO checks and reports
> `status: skipped` — which is UNVERIFIED, not clean. `corpus-task:` rather than bare shell because
> `skills/supervisor-readiness/SKILL.md` §"Executable Acceptance" forbids a machine-authored brief
> from emitting `cmd:` / bare-shell bullets, and `/autonomous` passes `--no-cmd` anyway. The four
> `test-*.sh` suites are covered by AC1–AC10 and the Outcomes Rubric and are run by the worker
> regardless, so duplicating them here would only add a skipped `cmd` bullet.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `/rules audit` — read-only engine, docs, and mutation-controlled tests | AC1–AC10 | 3 modify, 2 create | quality-checklist, unit-testing, rules | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1 — the whole slice (LAUNCHABLE)
provides:
  - {kind: "file",   path: "loomwright/scripts/audit-rules.sh"}
  - {kind: "file",   path: "loomwright/scripts/test-audit-rules.sh"}
  - {kind: "symbol", path: "loomwright/commands/rules.md",        name: "### `audit`"}
  - {kind: "symbol", path: "loomwright/skills/rules/SKILL.md",    name: "## §11 — `/rules audit`"}
  - {kind: "symbol", path: "loomwright/scripts/test-rules-docs.sh", name: "audit_vs_check_ok"}
requires: []
lanes:
  - "loomwright/scripts/audit-rules.sh"
  - "loomwright/scripts/test-audit-rules.sh"
  - "loomwright/commands/rules.md"
  - "loomwright/skills/rules/SKILL.md"
  - "loomwright/scripts/test-rules-docs.sh"
external_requires:
  - "jq (already a hard dependency of read-rules.sh / add-rule.sh)"
```

> **Provides-token note (learned defect, do not repeat):** `### \`audit\`` matches the existing
> heading level in `commands/rules.md` (its subcommands are `###`), and `## §11 — /rules audit`
> matches `skills/rules/SKILL.md`'s `## §N — ` convention (§1–§10 exist; §11 is the next free
> number). The third token `audit_vs_check_ok` matches `test-rules-docs.sh`'s own `<short>_ok`
> boolean-flag family (`slug_ok`, `id_ok`, `gate_ok`, `prov_ok`); its assertion block goes under a
> new `# ---- (j) ... ----` header, since the lettered blocks currently run (a) through (i).
> A token that does not match the target file's own convention forces either a malformed doc or a
> gate failure. Verify all three conventions still hold before writing.

## Parallelism Analysis

single-agent (no fan-out)

- Recommended workers: 1
- **Split reason:** none — below the Decomposition Threshold. The test suite IS the spec for the
  engine, and both docs describe an engine that must exist first; splitting them would produce a
  worker documenting a file it cannot see. Sequential coupling, no genuine parallelism.

## Skill References

- `skills/quality-checklist/SKILL.md` — pre/post-task gates
- `skills/unit-testing/SKILL.md` — mutation-control discipline
- `skills/rules/SKILL.md` — §1 schema, §2 validation/merge order, §3 routing, §8 check semantics, §9 trust boundary

## Risk Assessment

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| 1 | **The `--store` shape trap.** `validate_duplicate`/`validate_contradiction` expect ONE LINE PER STORED ENTRY. Handing them the raw JSON trips `REFUSE_*_UNCOMPARABLE_SHAPE` (rc 2, "could not decide") — which, if absorbed as rc 0, makes every rule audit as a silent false "clean". | HIGH | AC10. Build a compare corpus one line per rule (`build_compare_corpus` in ``add-orientation.sh:594 [pins: `build_compare_corpus() {`]`` and `write-agent-memory.sh` are the worked examples). Test a deliberate rc-2 and assert it surfaces as UNKNOWN. |
| 2 | **Vacuous store-wide tests.** A store-wide assertion that still passes with its mechanism deleted proves nothing; this repo has shipped that exact defect (see the shared-fixture-default lesson). | HIGH | Mutation-control every one of the five: delete the mechanism, prove the test goes RED, restore. |
| 3 | **A second copy of the correctness logic.** Reimplementing any of the five checks would make the audit violate the very `process` rule it audits ("a restated list drifts silently"). | HIGH | Source `validate-entry.sh` under the same three-clause LOAD GUARD `add-rule.sh` uses (`add-rule.sh` §`_ve_load_validator`). The three clauses are: (i) **the `source` itself exits 0** — status captured in a variable with the caller's errexit saved/restored; `\|\| true` on that line is FORBIDDEN (readability is a separate precheck ABOVE clause (i) but INSIDE the same `LOAD GUARD BEGIN`/`END` block — those delimiters mark the guard as ONE replaceable unit so mutation control can swap it in a single edit; do not move the precheck outside them); (ii) **all SEVEN names present** — `validate_duplicate`, `validate_contradiction`, `validate_provenance`, `validate_dead_reference`, `validate_cross_repo_reference`, `validate_entry_advisory_notice`, **and `validate_entry_all`** (the aggregate the call site actually invokes); (iii) `$VALIDATE_ENTRY_CONTRACT` equals the hardcoded literal `validate-entry/2`. **Copy the CODE, not the comment:** `add-rule.sh`'s own inline comment says "all five validator functions" and is stale — the loop is `for _vef in $VALIDATOR_REQUIRED_FUNCS validate_entry_all`, six names plus one. |
| 4 | **Widening the execution boundary.** Any code path that runs a rule's `check` breaks the standing invariant that `rules-check.sh` is the sole executor. | HIGH | Static lint only. AC7 asserts it with a `check` whose value would have an observable side effect (e.g. writes a canary file) and proves the canary never appears. |
| 5 | **Advisory-check false positives.** `dead_reference`/`cross_repo` were demoted to advisory after SIX rounds of prose false refusals. An audit inherits that ambiguity. | MEDIUM | Report these two as clearly-labelled ADVISORY findings with the matched text as evidence; never as a verdict, never aggregated into a pass/fail count. |
| 6 | **macOS bash 3.2 + BSD userland.** No `timeout`; `stat -f %m` succeeds with garbage on Linux; `set -u` in `$(( ))` silently empties a probe. macOS-green ≠ CI-green. | MEDIUM | Prefer `stat -c %Y` with a `-f %m` fallback, validate numeric before arithmetic, avoid `${var//[[:space:]]/}` on large strings. |
| 7 | **Small N makes the suite look green for the wrong reason.** The live store has 3 rules, all advisory, all `check: null` — none of the five store-wide conditions occurs naturally. | MEDIUM | Every store-wide test runs against a purpose-built FIXTURE store under the scratch dir, never the live one. AC8 makes the engine itself state the small-N caveat. |

## Configuration

- **Base branch:** `main` (the current branch is already merged — do NOT stack on it)
- **Workers:** 1
- **Command count:** UNCHANGED at 22 — `audit` is a verb on the existing `/rules` command, not a new
  `commands/*.md` file. Do **not** bump the count in ``CLAUDE.md:28 [pins: `(22 entry points)`]`` or ``README.md:608 [pins: `(22 commands)`]``; a bump would
  itself be a false claim of exactly the kind rule `process-a-count-or-version-claim...` forbids.
- **Token budgets:** no agent prompt is touched, so no `prompt-token-budgets.json` entry is added.
- **Skills index:** no new skill directory, so `SKILLS_INDEX.md` is unchanged.

## Handoff

/supervisor job: .supervisor/jobs/pending/2026-09-06-rules-audit-verb.md
