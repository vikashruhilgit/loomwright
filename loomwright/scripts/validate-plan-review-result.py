#!/usr/bin/env python3
"""validate-plan-review-result.py — deterministic validator for PLAN_REVIEW_RESULT v1.

Replaces the `type: prompt` (haiku, 30s timeout) SubagentStop hook on the
`loomwright:plan-reviewer` matcher with a zero-token `type: command` script.

RULE SOURCE: the SIX numbered rules below are transcribed from the prompt
string in `loomwright/hooks/hooks.json` under SubagentStop matcher
`loomwright:plan-reviewer`. The prompt specifies no verbatim reason strings, so
each reason names its rule number and the offending issue index.

  (1) a PLAN_REVIEW_RESULT block with a schema_version field equal to 1
  (2) decision is one of PASS, FAIL, or NEEDS_HUMAN
  (3) if FAIL or NEEDS_HUMAN, issues array is non-empty with severity and
      description
  (4) if decision is FAIL, at least one issue must have severity BLOCKING or HIGH
  (5) each issue includes section field
  (6) summary field is present

Rule (5) applies to EVERY issue, on every decision — a PASS block whose issues
array is empty vacuously satisfies it, but a PASS that lists issues must still
give each one a section.

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
            "validate-plan-review-result: result_block_parser unavailable, failing "
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

BLOCK = "PLAN_REVIEW_RESULT"

VALID_DECISION = ("PASS", "FAIL", "NEEDS_HUMAN")
ISSUES_REQUIRED_DECISIONS = ("FAIL", "NEEDS_HUMAN")
BLOCKING_SEVERITIES = ("BLOCKING", "HIGH")

MISSING_BLOCK = (
    "missing PLAN_REVIEW_RESULT block — the Plan Reviewer must emit one; its "
    "decision gates the brief save (agents/plan-reviewer.md §\"Output Format\")"
)


def main():
    _name, fields, _text, _payload = load_block(BLOCK, MISSING_BLOCK)

    # ── (1) schema_version equal to 1 ────────────────────────────────────────
    if not present(fields, "schema_version"):
        emit(False, "PLAN_REVIEW_RESULT is missing the schema_version field (rule 1)")
    schema_version, bad_sv = as_int(fields.get("schema_version"))
    if schema_version != 1:
        emit(
            False,
            "PLAN_REVIEW_RESULT schema_version must be the integer 1; got %s (rule 1)"
            % (bad_sv if schema_version is None else schema_version),
        )

    # ── (2) decision enum ────────────────────────────────────────────────────
    if not present(fields, "decision"):
        emit(False, "PLAN_REVIEW_RESULT is missing the decision field (rule 2)")
    decision = as_text(fields.get("decision")).strip()
    if decision not in VALID_DECISION:
        emit(
            False,
            "decision must be one of PASS, FAIL, or NEEDS_HUMAN; got %r (rule 2)"
            % decision,
        )

    issues_raw = fields.get("issues")
    if present(fields, "issues") and issues_raw is not None and not isinstance(issues_raw, list):
        emit(False, "issues must be an array; got %r (rule 3)" % as_text(issues_raw))
    issues = issues_raw if isinstance(issues_raw, list) else []
    issues = [i for i in issues if i is not None]

    # ── (3) FAIL / NEEDS_HUMAN ⇒ non-empty issues, each with severity+description
    if decision in ISSUES_REQUIRED_DECISIONS:
        if not issues:
            emit(
                False,
                "decision=%s requires a non-empty issues array (rule 3)" % decision,
            )
        for index, issue in enumerate(issues):
            if not isinstance(issue, dict):
                emit(
                    False,
                    "issues[%d] is not a mapping; each issue needs severity and "
                    "description (rule 3)" % index,
                )
            for key in ("severity", "description"):
                if key not in issue or is_empty_scalar(issue.get(key)):
                    emit(
                        False,
                        "issues[%d] is missing a non-empty %s field (rule 3)"
                        % (index, key),
                    )

    # ── (4) FAIL ⇒ at least one BLOCKING or HIGH issue ───────────────────────
    if decision == "FAIL":
        severities = [
            as_text(issue.get("severity")).strip()
            for issue in issues
            if isinstance(issue, dict)
        ]
        if not any(sev in BLOCKING_SEVERITIES for sev in severities):
            emit(
                False,
                "decision=FAIL requires at least one issue with severity BLOCKING "
                "or HIGH; got severities %s (rule 4)" % (severities or "[]"),
            )

    # ── (5) every issue includes a section field ─────────────────────────────
    for index, issue in enumerate(issues):
        if not isinstance(issue, dict):
            emit(False, "issues[%d] is not a mapping and cannot carry a section "
                        "field (rule 5)" % index)
        if "section" not in issue or is_empty_scalar(issue.get("section")):
            emit(
                False,
                "issues[%d] is missing a non-empty section field (rule 5)" % index,
            )

    # ── (6) summary present ──────────────────────────────────────────────────
    if not present(fields, "summary") or is_empty_scalar(fields.get("summary")):
        emit(
            False,
            "PLAN_REVIEW_RESULT summary field must be present and non-empty (rule 6)",
        )

    emit(True)


if __name__ == "__main__":
    run_validator(main)
