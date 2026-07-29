#!/usr/bin/env python3
"""validate-supervisor-result.py — deterministic validator for SUPERVISOR_RESULT v1.

Replaces the `type: prompt` (haiku, 30s timeout) SubagentStop hook on the
`loomwright:supervisor-runner` matcher with a zero-token `type: command` script.

RULE SOURCE: the THIRTEEN numbered rules below are transcribed from the prompt
string in `loomwright/hooks/hooks.json` under SubagentStop matcher
`loomwright:supervisor-runner`. Rule (13) specifies its reason string VERBATIM;
that exact string is reproduced below.

   (1) output contains a SUPERVISOR_RESULT block with schema_version 1
   (2) status is one of [completed, completed_with_escalation, failed, checkpoint]
   (3) pr_url present and non-empty when status in [completed,
       completed_with_escalation]
   (4) heal_loop_ran is boolean
   (5) heal_fixable_issues_fixed and heal_remaining_issues are both
       non-negative integers
   (6) when heal_loop_ran=false then heal_iterations=null, heal_decision=null,
       heal_fixable_issues_fixed=0, and heal_remaining_issues=0 exactly
   (7) when heal_loop_ran=true then heal_decision is one of [PASS, ESCALATED]
       (SKIPPED is NOT allowed here) and heal_iterations is a non-negative integer
   (8) when heal_decision=PASS then heal_remaining_issues=0
   (9) when heal_decision=ESCALATED then heal_remaining_issues>=1 OR error is
       non-empty
  (10) when status=failed then error is non-empty
  (11) summary is non-empty
  (12) if cost_profile is present it must be one of [default, cheap, null]
  (13) rubric_score: absent accepted, null accepted; when present and non-null
       it must be "N/M" with N >= 0, M >= 1, digits only with no leading zeros,
       and M >= N

NULLABLE-BUT-REQUIRED: rule (6) demands heal_iterations and heal_decision be
NULL, not absent. This validator therefore asserts key PRESENCE via
`present(fields, key)` and null-ness separately — a truthiness check would
silently accept a missing key, which is a different (and unreported) defect.

INVARIANT: ALWAYS exits 0. Decision on stdout only.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from result_block_parser import (  # noqa: E402
    as_bool,
    as_int,
    as_text,
    emit,
    is_empty_scalar,
    load_block,
    present,
    run_validator,
)

BLOCK = "SUPERVISOR_RESULT"

VALID_STATUS = ("completed", "completed_with_escalation", "failed", "checkpoint")
PR_REQUIRED_STATUS = ("completed", "completed_with_escalation")
VALID_HEAL_DECISION = ("PASS", "ESCALATED")
VALID_COST_PROFILE = ("default", "cheap")

MISSING_BLOCK = (
    "missing SUPERVISOR_RESULT block — exactly one is emitted per task from "
    "Phase 4.5's completion tail (agents/supervisor.md §\"Result Block\")"
)

# (13) — verbatim reason string from the hooks.json prompt.
REASON_RUBRIC_SCORE = (
    "rubric_score must be null or a string 'N/M' with N >= 0, M >= 1, M >= N"
)

# N: non-negative, digits only, no leading zeros (bare "0" is legal).
# M: positive, digits only, no leading zeros (so "0" and "01" are both invalid).
_RUBRIC_RE = re.compile(r"^(0|[1-9][0-9]*)/([1-9][0-9]*)$")


def _require_non_negative_int(fields, key, rule):
    if not present(fields, key):
        emit(False, "SUPERVISOR_RESULT is missing the %s field (rule %s)" % (key, rule))
    value, bad = as_int(fields.get(key))
    if value is None:
        emit(
            False,
            "%s must be a non-negative integer; got %s (rule %s)" % (key, bad, rule),
        )
    if value < 0:
        emit(
            False,
            "%s must be a non-negative integer; got %d (rule %s)" % (key, value, rule),
        )
    return value


def main():
    _name, fields, _text, _payload = load_block(BLOCK, MISSING_BLOCK)

    # ── (1) schema_version must be 1 ─────────────────────────────────────────
    if not present(fields, "schema_version"):
        emit(False, "SUPERVISOR_RESULT is missing the schema_version field (rule 1)")
    schema_version, bad_sv = as_int(fields.get("schema_version"))
    if schema_version != 1:
        emit(
            False,
            "SUPERVISOR_RESULT schema_version must be the integer 1; got %s (rule 1)"
            % (bad_sv if schema_version is None else schema_version),
        )

    # ── (2) status enum ──────────────────────────────────────────────────────
    if not present(fields, "status"):
        emit(False, "SUPERVISOR_RESULT is missing the status field (rule 2)")
    status = as_text(fields.get("status")).strip()
    if status not in VALID_STATUS:
        emit(
            False,
            "status must be one of [completed, completed_with_escalation, failed, "
            "checkpoint]; got %r (rule 2)" % status,
        )

    # ── (3) pr_url present and non-empty on the completed statuses ───────────
    if status in PR_REQUIRED_STATUS:
        if not present(fields, "pr_url") or is_empty_scalar(fields.get("pr_url")):
            emit(
                False,
                "pr_url must be present and non-empty when status=%s (rule 3)" % status,
            )

    # ── (4) heal_loop_ran is boolean ─────────────────────────────────────────
    if not present(fields, "heal_loop_ran"):
        emit(False, "SUPERVISOR_RESULT is missing the heal_loop_ran field (rule 4)")
    heal_loop_ran, bad_flag = as_bool(fields.get("heal_loop_ran"))
    if heal_loop_ran is None:
        emit(False, "heal_loop_ran must be a boolean; got %s (rule 4)" % bad_flag)

    # ── (5) the two heal counters are non-negative integers ──────────────────
    fixed = _require_non_negative_int(fields, "heal_fixable_issues_fixed", "5")
    remaining = _require_non_negative_int(fields, "heal_remaining_issues", "5")

    # heal_decision is nullable-but-required: PRESENCE and null-ness are
    # separate questions, and rules 6/7 need both answers.
    heal_decision_present = present(fields, "heal_decision")
    heal_decision_raw = fields.get("heal_decision")
    heal_decision = as_text(heal_decision_raw).strip()
    heal_iterations_present = present(fields, "heal_iterations")
    heal_iterations_raw = fields.get("heal_iterations")

    if heal_loop_ran is False:
        # ── (6) heal_loop_ran=false ⇒ the exact null/zero shape ──────────────
        if not heal_iterations_present:
            emit(
                False,
                "heal_loop_ran=false requires heal_iterations to be PRESENT and null; "
                "the field is absent (rule 6)",
            )
        if heal_iterations_raw is not None:
            emit(
                False,
                "heal_loop_ran=false requires heal_iterations=null; got %r (rule 6)"
                % as_text(heal_iterations_raw),
            )
        if not heal_decision_present:
            emit(
                False,
                "heal_loop_ran=false requires heal_decision to be PRESENT and null; "
                "the field is absent (rule 6)",
            )
        if heal_decision_raw is not None:
            emit(
                False,
                "heal_loop_ran=false requires heal_decision=null; got %r (rule 6)"
                % heal_decision,
            )
        if fixed != 0:
            emit(
                False,
                "heal_loop_ran=false requires heal_fixable_issues_fixed=0 exactly; "
                "got %d (rule 6)" % fixed,
            )
        if remaining != 0:
            emit(
                False,
                "heal_loop_ran=false requires heal_remaining_issues=0 exactly; "
                "got %d (rule 6)" % remaining,
            )
    else:
        # ── (7) heal_loop_ran=true ⇒ decision enum + iteration count ─────────
        if heal_decision not in VALID_HEAL_DECISION:
            emit(
                False,
                "heal_loop_ran=true requires heal_decision to be one of "
                "[PASS, ESCALATED] (SKIPPED is NOT allowed — skipping corresponds "
                "to heal_loop_ran=false); got %r (rule 7)" % heal_decision,
            )
        if not heal_iterations_present:
            emit(
                False,
                "heal_loop_ran=true requires heal_iterations to be a non-negative "
                "integer; the field is absent (rule 7)",
            )
        iterations, bad_it = as_int(heal_iterations_raw)
        if iterations is None or iterations < 0:
            emit(
                False,
                "heal_loop_ran=true requires heal_iterations to be a non-negative "
                "integer; got %s (rule 7)"
                % (bad_it if iterations is None else iterations),
            )

    error_present = present(fields, "error")
    error_empty = is_empty_scalar(fields.get("error"))

    # ── (8) heal_decision=PASS ⇒ no remaining issues ─────────────────────────
    if heal_decision == "PASS" and remaining != 0:
        emit(
            False,
            "heal_decision=PASS requires heal_remaining_issues=0; got %d (rule 8)"
            % remaining,
        )

    # ── (9) heal_decision=ESCALATED ⇒ issues remain OR an error is recorded ──
    if heal_decision == "ESCALATED":
        if remaining < 1 and (not error_present or error_empty):
            emit(
                False,
                "heal_decision=ESCALATED requires heal_remaining_issues>=1 OR a "
                "non-empty error (the resume-thrash escalation legitimately "
                "reports 0 remaining issues with error self_heal_resume_thrash) "
                "(rule 9)",
            )

    # ── (10) status=failed ⇒ error non-empty ─────────────────────────────────
    if status == "failed" and (not error_present or error_empty):
        emit(False, "status=failed requires a non-empty error field (rule 10)")

    # ── (11) summary non-empty ───────────────────────────────────────────────
    if not present(fields, "summary") or is_empty_scalar(fields.get("summary")):
        emit(False, "summary must be present and non-empty (rule 11)")

    # ── (12) cost_profile enum (present-but-null is legal) ───────────────────
    if present(fields, "cost_profile"):
        cost_profile_raw = fields.get("cost_profile")
        if cost_profile_raw is not None:
            cost_profile = as_text(cost_profile_raw).strip()
            if cost_profile not in VALID_COST_PROFILE:
                emit(
                    False,
                    "cost_profile must be one of [default, cheap, null]; got %r "
                    "(rule 12)" % cost_profile,
                )

    # ── (13) rubric_score — absent OK, null OK, else strict "N/M" ────────────
    # MUST NOT reject solely for presence or absence. Only a present, non-null,
    # malformed value is rejected.
    if present(fields, "rubric_score"):
        rubric_raw = fields.get("rubric_score")
        if rubric_raw is not None:
            if isinstance(rubric_raw, (list, dict)):
                emit(False, REASON_RUBRIC_SCORE)
            match = _RUBRIC_RE.match(as_text(rubric_raw).strip())
            if not match:
                emit(False, REASON_RUBRIC_SCORE)
            scored = int(match.group(1))
            total = int(match.group(2))
            if total < scored:
                emit(False, REASON_RUBRIC_SCORE)

    emit(True)


if __name__ == "__main__":
    run_validator(main)
