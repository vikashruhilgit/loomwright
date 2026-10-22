# af/15 — Telemetry: pin MEDIUM/LOW severity counting in a test, and delete the unreachable 7.0 score branch

## Status: pending

## Re-scoped 2026-10-22 (owner, /product-owner session; re-verified read-only against main 7b7cb08 / v17.14.1)
Promoted from `proposed` and shrunk. Both original findings are fixed on main:
- **Count bug — fixed** by ee5b1e7 (2026-10-13, closes #508): in `send-telemetry-core.sh`, inside the
  `count-from-parsed-findings` mutation-control block, `issues_by_severity` now counts from `review_issues` (the
  shared `result_block_parser` output), every severity and category, plus `raw_data.issues_by_category`. Reproduced
  with a sandboxed `--dry-run` (fake HOME, stub `gh`, 0 calls): HIGH + MEDIUM + LOW `new` + LOW `nit` ⇒
  `high:1, medium:1, low:2`, `new:3, nit:1`.
- **`Failed: true` title — gone** with #508: the title is `[Telemetry] {agent_type} thread`; a FAIL round opens or
  joins a per-review-target thread that the later PASS closes (`telemetry:healed-in-loop`). `score_code_review()`
  keeps `success = (decision == "PASS")`, so the body's `Success: false` means "this round did not pass" —
  consistent with the thread model; no change.
- Issues #282, #287, #297, #302 are CLOSED (not planned, 2026-10-01). The owner's close decision is done.
The original text is kept below, demoted, under `## Original text`; it is stale where it differs from this header.

## Problem
Nothing pins MEDIUM/LOW counting: the only code-review golden (`code-review-fail__allow_with_repo.golden.txt`) has a
single HIGH finding, and T8's mutant (b) in `test-telemetry-threads.sh` is caught only through the drift fixture. A
regression back to counting BLOCKING/HIGH only — the exact 5d9f7a2 bug — would pass every test. Separately,
`score_code_review()` has a `base = 7.0` branch that can never run (the `9.0` condition above it subsumes it), and
`docs/TELEMETRY.md` §"Rubric B" row 2 documents that unreachable case.

## Goal
The count fix cannot silently regress, and the scorer and its doc describe only reachable cases.

## Scope
1. `test-telemetry-threads.sh`: a mixed-severity code-review fixture asserting `"medium": 1`, `"low": 2`,
   `"nit": 1`, and a new mutant that keeps only BLOCKING/HIGH counts, which that assertion must catch.
2. `send-telemetry-core.sh` `score_code_review()`: delete the unreachable `7.0` branch; scores do not change.
3. `docs/TELEMETRY.md` §"Rubric B": remove row 2 (the unreachable case).
Privacy (owner rule 2026-10-13, telemetry = plugin facts only): the fixture and assertions use integer counts and
enums only, never finding text, paths, repo or PR names.

## Non-goals
Changing any score. Renaming `Success:`. Reopening or commenting on the closed issues. Posting anything.

## Owner decisions (from _BACKLOG.md)
- 2026-10-22: pin the counts and delete the dead branch (not make 7.0 reachable); scores stay as they are.

## Acceptance criteria
- The mixed-severity assertion passes on the branch; the BLOCKING/HIGH-only mutant fails it.
- `score_code_review()` returns the same score as on main for every existing fixture, and the `7.0` branch is gone.
- `TELEMETRY.md` §"Rubric B" matches the code's reachable cases.
- `bash scripts/check-version-bump.sh` passes with the `changelog.d/af15-telemetry-count-pins.md` fragment.

## Validation (must pass before merge)
1. `test-telemetry-threads.sh`, `test-send-telemetry-core.sh`, `check-doc-currency.sh`, `test-citation-drift.sh`.
   Full `ci-local` on GitHub CI (owner rule 2026-10-12). No test may post to GitHub.
2. Running system: the sandboxed `--dry-run` above (fake HOME, stub `gh` on PATH) on the mixed fixture — paste the
   `issues_by_severity` line and the stub's call count (0) into the PR body.
3. Rollback: `git revert`.

## Depends on
none

## Touches
loomwright/scripts/test-telemetry-threads.sh
loomwright/scripts/send-telemetry-core.sh
loomwright/docs/TELEMETRY.md
changelog.d/af15-telemetry-count-pins.md

## Original text (2026-10-01, demoted — stale where the header above differs)

### Telemetry: code-review severity counts drop MEDIUM/LOW, and a correct FAIL review is reported as `Failed: true`

#### Status: proposed

> **Origin.** Finding 17 (surfaced during item 10's close-out), recovered by the item-13 triage sweep
> (run automate-2026-09-30-054439, classified 2026-10-01 against main@0dc0a5b, owner-approved as *draft*).
> Owner decision 2026-10-01: close telemetry issues #282, #287, #297, #302 with a note pointing here.

#### Finding (verbatim summary)
> Telemetry issue #302 counted `high: 1, medium: 0, low: 0` for a review that raised 1 HIGH + 1 MEDIUM + 1 LOW + 1 nit
> — the telemetry scorer appears to drop non-HIGH findings. Also decide whether the four open
> `[Telemetry] code-reviewer … Failed: true` issues (#282, #287, #297, #302) should be closed.

#### Evidence on main (reproduced)
- Path: `hooks.json` SubagentStop → `send-telemetry.sh` → `loomwright/scripts/send-telemetry-core.sh` embedded
  `STAGE1_PY`. `parse_issue_blocks()` parses all four severities correctly — the input format is NOT the problem.
- Root cause: in "Build prospective body components" (CODE_REVIEW_RESULT branch) the human-readable `issues` list is
  filtered to `for sev in ("BLOCKING", "HIGH")` and `category == "new"`; the Raw Data counter
  (`issue_severity_rx` / `issues_by_severity`) is then computed FROM that list, so `medium`/`low` are always 0 for a
  code review and non-`new` findings are never counted. Introduced by 5d9f7a2 (2026-09-23 field-selection privacy
  hardening), whose comment claims the counter is "distinct from the `issues` list above".
- Repro: extracted `STAGE1_PY` (the `test-send-telemetry-core.sh` Group 7 technique — no `gh`, no network) on a
  synthetic FAIL review with 1 HIGH + 1 MEDIUM + 1 LOW + 1 LOW nit ⇒ `"high": 1, "medium": 0, "low": 0`,
  `Score: 2 | Failed: true` — identical to #302.
- `Failed: true`: `score_code_review()` sets `success = (decision == "PASS")`; `docs/TELEMETRY.md` §"Success
  derivation" / §"Title format" specify exactly that, so a reviewer that correctly FAILs a defective PR is reported
  as an agent failure. By-spec — a design flaw, not a code bug. Every correct FAIL review will keep opening an issue.
- Side note: in `score_code_review()` the `base = 7.0` branch is unreachable (the `9.0` condition subsumes it).

#### Scope (recommendation)
1. Count fix (code): build `issues_by_severity` from `parse_issue_blocks(result_block)` directly (decide: `new` only,
   or per-category counts); leave the body list alone. New fixture with MEDIUM + LOW findings + golden.
   Files: `loomwright/scripts/send-telemetry-core.sh`, `loomwright/scripts/test-send-telemetry-core.sh`,
   `loomwright/scripts/telemetry-fixtures/`, `loomwright/docs/TELEMETRY.md` (Raw Data `issues` semantics).
2. `Failed` semantics (owner decision first): e.g. code-reviewer success = "returned a valid verdict" with the
   verdict as a label, or drop `Failed` from the CODE_REVIEW_RESULT title. Touches `score_code_review()`, the
   interest-filter success set, `docs/TELEMETRY.md` §Success / §Title / §Interest filter.
