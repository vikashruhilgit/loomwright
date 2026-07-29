#!/usr/bin/env python3
"""validate-worker-result.py — deterministic validator for WORKER_RESULT.

Replaces the `type: prompt` (haiku, 30s timeout) SubagentStop hook on the
`loomwright:worker` matcher with a zero-token `type: command` script.

RULE SOURCE: the EIGHT numbered rules below are transcribed from the prompt
string in `loomwright/hooks/hooks.json` under SubagentStop matcher
`loomwright:worker` — NOT paraphrased from docs/RESULT_SCHEMAS.md, which lists
rules (3) and (5) only "for transparency". Where the prompt specifies a reason
string verbatim, that exact string is used.

  (1) a WORKER_RESULT block with schema_version, task_id, status,
      files_modified, and summary fields
  (2) at least one of files_modified or files_created is non-empty when
      status=completed (create-only subtasks are valid)
  (3) a worker summary file was written — {worktree}/.worker-summary.md or
      .supervisor/worker-summaries/{task_id}.md — OR the output records the
      literal marker summary_file_write_failed
  (4) no unresolved errors remain
  (5) no destructive commands were used (rm -rf, git push, git reset --hard,
      DROP, TRUNCATE)
  (6) v12 outputs_verified contract — schema_version >= 2 requires BOTH
      outputs_verified (array) AND outputs_gap (string) to be PRESENT
  (7) v12 outputs_verified shape — each entry needs kind (file|symbol|type),
      path (string), status (present|missing)
  (8) v12 outputs_gap/status invariant — outputs_gap non-empty with
      status: completed is rejected

DELIBERATE NON-ADDITIONS: the prompt does NOT constrain WORKER_RESULT.status to
an enum, so neither does this script (R4: transcribe, do not silently
strengthen). RESULT_SCHEMAS.md's `status ∈ {completed, failed, partial}` is
enforced by the schema doc and by check-contract-parity.sh's ENUMS table, not
here.

INVARIANT: ALWAYS exits 0. Decision on stdout only.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from result_block_parser import (  # noqa: E402
    as_int,
    as_text,
    emit,
    find_destructive_command,
    is_empty_scalar,
    load_block,
    present,
    run_validator,
    worker_summary_file_evidence,
)

BLOCK = "WORKER_RESULT"

# (1) — required fields, in the prompt's own order.
REQUIRED_FIELDS = ("schema_version", "task_id", "status", "files_modified", "summary")

VALID_KINDS = ("file", "symbol", "type")
VALID_ENTRY_STATUS = ("present", "missing")

# Verbatim reason strings from the hooks.json prompt.
REASON_V2_FIELDS = (
    "WORKER_RESULT schema_version>=2 requires outputs_verified (array) and "
    "outputs_gap (string) fields"
)
REASON_ENTRY_SHAPE = "outputs_verified entries must include {kind, path, status}"
REASON_GAP_STATUS = (
    "outputs_gap non-empty must map to status: partial — a worker that did not "
    "deliver all promised outputs has not completed"
)

MISSING_BLOCK = (
    "missing WORKER_RESULT block — every worker execution must end with one "
    "(agents/worker.md §\"Output Format\")"
)


def _non_empty_list(value):
    """True when the field carries at least one real item.

    Accepts both the flow form (`files_modified: [a, b]` -> list) and a bare
    scalar; `[]`, null, and the conventional `none` placeholder are empty.
    """
    if value is None:
        return False
    if isinstance(value, list):
        return any(not is_empty_scalar(item) for item in value)
    return not is_empty_scalar(value)


def main():
    _name, fields, text, payload = load_block(BLOCK, MISSING_BLOCK)

    # ── (1) required field presence ──────────────────────────────────────────
    missing = [f for f in REQUIRED_FIELDS if not present(fields, f)]
    if missing:
        emit(
            False,
            "WORKER_RESULT is missing required field(s): %s (rule 1)"
            % ", ".join(missing),
        )
    if is_empty_scalar(fields.get("summary")):
        emit(False, "WORKER_RESULT summary field must be a non-empty string (rule 1)")
    task_id = as_text(fields.get("task_id")).strip()
    if not task_id:
        emit(False, "WORKER_RESULT task_id field must be a non-empty string (rule 1)")

    schema_version, bad_sv = as_int(fields.get("schema_version"))
    if schema_version is None:
        emit(
            False,
            "WORKER_RESULT schema_version must be an integer; got %s (rule 1)" % bad_sv,
        )

    status = as_text(fields.get("status")).strip()

    # ── (2) completed subtasks must have touched at least one file ───────────
    if status == "completed":
        if not (
            _non_empty_list(fields.get("files_modified"))
            or _non_empty_list(fields.get("files_created"))
        ):
            emit(
                False,
                "status=completed requires at least one of files_modified or "
                "files_created to be non-empty (create-only subtasks are valid) "
                "(rule 2)",
            )

    # ── (3) worker summary file / degradation marker ─────────────────────────
    if not worker_summary_file_evidence(task_id, text, payload):
        emit(
            False,
            "no worker summary file evidence — expected {worktree}/.worker-summary.md "
            "or .supervisor/worker-summaries/%s.md, or the literal marker "
            "summary_file_write_failed in the output (rule 3)" % task_id,
        )

    # ── (4) no unresolved errors remain ──────────────────────────────────────
    # Deterministic reading of "unresolved": the block's own `error` field.
    # `error: none` is the documented no-error spelling (agents/worker.md).
    error_value = fields.get("error")
    if status == "failed":
        if not present(fields, "error") or is_empty_scalar(error_value):
            emit(
                False,
                "status=failed requires a non-empty error field describing what "
                "went wrong (rule 4)",
            )
    elif status == "completed":
        if present(fields, "error") and not is_empty_scalar(error_value):
            emit(
                False,
                "status=completed but an unresolved error remains: %r (rule 4)"
                % as_text(error_value),
            )

    # ── (5) destructive-command scan ─────────────────────────────────────────
    destructive = find_destructive_command(text)
    if destructive:
        emit(
            False,
            "destructive command detected in the worker output: %r — workers "
            "perform no git operations and no destructive filesystem or database "
            "commands (rule 5)" % destructive,
        )

    # ── (6) v12 outputs_verified / outputs_gap PRESENCE ──────────────────────
    # PRESENCE, not truthiness: `outputs_gap: ""` is legal and means "nothing
    # missing", while an ABSENT outputs_gap is a contract violation. A
    # truthiness check cannot tell those apart.
    if schema_version >= 2:
        if not present(fields, "outputs_verified") or not present(fields, "outputs_gap"):
            emit(False, REASON_V2_FIELDS)
        outputs_verified = fields.get("outputs_verified")
        if outputs_verified is None:
            outputs_verified = []
        if not isinstance(outputs_verified, list):
            emit(False, REASON_V2_FIELDS)
        outputs_gap_raw = fields.get("outputs_gap")
        if isinstance(outputs_gap_raw, (list, dict)):
            emit(False, REASON_V2_FIELDS)

        # ── (7) outputs_verified entry shape ─────────────────────────────────
        for entry in outputs_verified:
            if not isinstance(entry, dict):
                emit(False, REASON_ENTRY_SHAPE)
            for required in ("kind", "path", "status"):
                if required not in entry or is_empty_scalar(entry.get(required)):
                    emit(False, REASON_ENTRY_SHAPE)
            if as_text(entry.get("kind")).strip() not in VALID_KINDS:
                emit(False, REASON_ENTRY_SHAPE)
            if as_text(entry.get("status")).strip() not in VALID_ENTRY_STATUS:
                emit(False, REASON_ENTRY_SHAPE)

        # ── (8) outputs_gap / status cross-field invariant ───────────────────
        outputs_gap = as_text(outputs_gap_raw).strip()
        if outputs_gap and status == "completed":
            emit(False, REASON_GAP_STATUS)

    emit(True)


if __name__ == "__main__":
    run_validator(main)
