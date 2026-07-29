#!/usr/bin/env python3
"""validate-qa-result.py — deterministic validator for QA_RESULT v1.

Replaces the `type: prompt` (haiku, 30s timeout) SubagentStop hook on the
`loomwright:qa-executor` matcher with a zero-token `type: command` script.

RULE SOURCE: the FIVE numbered rules below are transcribed from the prompt
string in `loomwright/hooks/hooks.json` under SubagentStop matcher
`loomwright:qa-executor`. The prompt specifies no verbatim reason strings, so
each reason names its rule number and the offending value.

  (1) a QA_RESULT block with a schema_version field equal to 1
  (2) tests_generated and tests_passed are present as integers
  (3) summary field is present
  (4) if tests were run, coverage_estimate is present
  (5) status is one of [passed, failed, partial, skipped, needs_human,
      plan_created, all_scopes_completed]

"IF TESTS WERE RUN" is pinned by docs/RESULT_SCHEMAS.md §QA_RESULT, which
states the hook-enforced conditional as "when tests were actually run (i.e.
tests_generated > 0)". That is the interpretation implemented here — not a
guess. Note rule (4) is a PRESENCE check (including present-but-null being a
distinct outcome from absent), not a range check on the value.

INVARIANT: ALWAYS exits 0. Decision on stdout only — including when the shared
module below cannot be imported (see the guard).
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    from result_block_parser import (  # noqa: E402
        as_int,
        as_text,
        emit,
        is_empty_scalar,
        load_block,
        present,
        run_validator,
    )
except BaseException as _import_exc:  # noqa: BLE001 — LAST LINE OF DEFENCE
    # R3, IMPORT-TIME edition. run_validator() cannot guard its own import: an
    # absent or syntactically broken result_block_parser.py exits 1 with a
    # traceback and NOTHING on stdout, which `|| true` then MASKS — a silently
    # dead validator. Fail SAFE, byte-identically to emit(True). Full rationale:
    # validate-worker-result.py's copy of this guard.
    import json as _json

    try:
        sys.stderr.write(
            "validate-qa-result: result_block_parser unavailable, failing "
            "safe (ok:true): %s: %s\n" % (type(_import_exc).__name__, _import_exc)
        )
    except BaseException:
        pass
    try:
        sys.stdout.write(_json.dumps({"ok": True}) + "\n")
        sys.stdout.flush()
    except BaseException:
        pass
    os._exit(0)

BLOCK = "QA_RESULT"

VALID_STATUS = (
    "passed",
    "failed",
    "partial",
    "skipped",
    "needs_human",
    "plan_created",
    "all_scopes_completed",
)

MISSING_BLOCK = (
    "missing QA_RESULT block — the QA Executor must always emit one, even on "
    "failure, timeout, or skip (agents/qa-executor.md)"
)


def main():
    _name, fields, _text, _payload = load_block(BLOCK, MISSING_BLOCK)

    # ── (1) schema_version equal to 1 ────────────────────────────────────────
    if not present(fields, "schema_version"):
        emit(False, "QA_RESULT is missing the schema_version field (rule 1)")
    schema_version, bad_sv = as_int(fields.get("schema_version"))
    if schema_version != 1:
        emit(
            False,
            "QA_RESULT schema_version must be the integer 1; got %s (rule 1)"
            % (bad_sv if schema_version is None else schema_version),
        )

    # ── (2) tests_generated and tests_passed present, as integers ────────────
    counts = {}
    for key in ("tests_generated", "tests_passed"):
        if not present(fields, key):
            emit(False, "QA_RESULT is missing the %s field (rule 2)" % key)
        value, bad = as_int(fields.get(key))
        if value is None:
            emit(False, "%s must be an integer; got %s (rule 2)" % (key, bad))
        if value < 0:
            emit(False, "%s must be a non-negative integer; got %d (rule 2)" % (key, value))
        counts[key] = value

    # ── (3) summary present ──────────────────────────────────────────────────
    if not present(fields, "summary") or is_empty_scalar(fields.get("summary")):
        emit(False, "QA_RESULT summary field must be present and non-empty (rule 3)")

    # ── (4) coverage_estimate present when tests were run ────────────────────
    # PRESENCE, not truthiness: `coverage_estimate: 0.0` is a legitimate value
    # and must not be confused with an absent field.
    if counts["tests_generated"] > 0:
        if not present(fields, "coverage_estimate"):
            emit(
                False,
                "coverage_estimate must be present when tests were run "
                "(tests_generated=%d > 0) (rule 4)" % counts["tests_generated"],
            )
        if fields.get("coverage_estimate") is None:
            emit(
                False,
                "coverage_estimate is present but null; a run that generated %d "
                "tests must report a coverage estimate (rule 4)"
                % counts["tests_generated"],
            )

    # ── (5) status enum ──────────────────────────────────────────────────────
    if not present(fields, "status"):
        emit(False, "QA_RESULT is missing the status field (rule 5)")
    status = as_text(fields.get("status")).strip()
    if status not in VALID_STATUS:
        emit(
            False,
            "status must be one of [passed, failed, partial, skipped, needs_human, "
            "plan_created, all_scopes_completed]; got %r (rule 5)" % status,
        )

    emit(True)


if __name__ == "__main__":
    run_validator(main)
