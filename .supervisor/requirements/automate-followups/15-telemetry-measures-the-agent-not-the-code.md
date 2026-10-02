# Telemetry: code-review severity counts drop MEDIUM/LOW, and a correct FAIL review is reported as `Failed: true`

## Status: proposed

> **Origin.** Finding 17 (surfaced during item 10's close-out), recovered by the item-13 triage sweep
> (run automate-2026-09-30-054439, classified 2026-10-01 against main@0dc0a5b, owner-approved as *draft*).
> Owner decision 2026-10-01: close telemetry issues #282, #287, #297, #302 with a note pointing here.

## Finding (verbatim summary)
> Telemetry issue #302 counted `high: 1, medium: 0, low: 0` for a review that raised 1 HIGH + 1 MEDIUM + 1 LOW + 1 nit
> — the telemetry scorer appears to drop non-HIGH findings. Also decide whether the four open
> `[Telemetry] code-reviewer … Failed: true` issues (#282, #287, #297, #302) should be closed.

## Evidence on main (reproduced)
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

## Scope (recommendation)
1. Count fix (code): build `issues_by_severity` from `parse_issue_blocks(result_block)` directly (decide: `new` only,
   or per-category counts); leave the body list alone. New fixture with MEDIUM + LOW findings + golden.
   Files: `loomwright/scripts/send-telemetry-core.sh`, `loomwright/scripts/test-send-telemetry-core.sh`,
   `loomwright/scripts/telemetry-fixtures/`, `loomwright/docs/TELEMETRY.md` (Raw Data `issues` semantics).
2. `Failed` semantics (owner decision first): e.g. code-reviewer success = "returned a valid verdict" with the
   verdict as a label, or drop `Failed` from the CODE_REVIEW_RESULT title. Touches `score_code_review()`, the
   interest-filter success set, `docs/TELEMETRY.md` §Success / §Title / §Interest filter.
