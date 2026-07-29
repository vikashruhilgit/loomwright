#!/usr/bin/env python3
"""validate-execute-result.py — deterministic validator for EXECUTE_RESULT / EXECUTE_CHECKPOINT.

Replaces the `type: prompt` (haiku, 30s timeout) SubagentStop hook on the
`loomwright:execute-manager` matcher with a zero-token `type: command` script.

RULE SOURCE: the SIX numbered rules below are transcribed from the prompt
string in `loomwright/hooks/hooks.json` under SubagentStop matcher
`loomwright:execute-manager`. Rules (5) and (6a)/(6b) specify their reason
strings VERBATIM; those exact strings are reproduced below.

  (1) an EXECUTE_RESULT or EXECUTE_CHECKPOINT block with a schema_version field
  (2) EXECUTE_RESULT contains subtasks_completed (array — may be empty ONLY
      when subtasks_failed is non-empty and summary records the escalation),
      worktrees, merge_order (may be empty when no subtask completed), and
      summary fields
  (3) EXECUTE_CHECKPOINT contains completed_so_far, remaining, resume_context,
      and reason fields
  (4) all worktree paths reference valid sibling directories
  (5) v12 toolset_gap rule
  (6) v12 adjudication tri-field invariant (all-or-nothing, BIDIRECTIONAL)

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

RESULT_BLOCK = "EXECUTE_RESULT"
CHECKPOINT_BLOCK = "EXECUTE_CHECKPOINT"
BLOCKS = (RESULT_BLOCK, CHECKPOINT_BLOCK)

# (2) / (3) — required fields per block kind.
RESULT_REQUIRED = ("subtasks_completed", "worktrees", "merge_order", "summary")
CHECKPOINT_REQUIRED = ("completed_so_far", "remaining", "resume_context", "reason")

MISSING_BLOCK = (
    "missing EXECUTE_RESULT / EXECUTE_CHECKPOINT block — the Execute Manager "
    "must emit exactly one (agents/execute-manager.md §\"Output Format\")"
)

# (5) — verbatim reason string from the hooks.json prompt.
REASON_TOOLSET_GAP = (
    "toolset_gap is not a valid escalation reason; the Execute Manager spawns "
    "workers via Task and that capability is guaranteed by the harness — "
    "restate the actual blocker without referencing toolset availability"
)

# (6a) / (6b) — verbatim reason strings from the hooks.json prompt.
REASON_ADJUDICATION_INCOMPLETE = (
    "adjudication_required: true requires non-empty missing_outputs and "
    "adjudication_options arrays"
)
REASON_ADJUDICATION_ORPHAN = (
    "missing_outputs/adjudication_options present without adjudication_required: "
    "true — the three fields are all-or-nothing"
)

# (5) — the prompt names three literals plus "any variant claiming the spawning
# toolset is missing".
_TOOLSET_GAP_RE = re.compile(
    r"(?i)toolset[_ \t-]?gap"
    r"|(?:task|agent|spawn\w*|subagent)[ \t]+tool(?:set)?[ \t]+"
    r"(?:is[ \t]+)?(?:un)?available"
    r"|(?:task|agent|spawn\w*|subagent)[ \t]+tool(?:set)?[ \t]+(?:is[ \t]+)?missing"
    r"|(?:cannot|can't|could[ \t]not|unable[ \t]to)[ \t]+(?:spawn|use[ \t]+the[ \t]+task)"
)


def _as_list(value):
    """Normalise a field to a list, or return None when it is not list-shaped."""
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return None


def _non_empty(items):
    return bool(items) and any(not is_empty_scalar(item) for item in items)


def _check_worktree_paths(worktrees):
    """(4) all worktree paths reference valid sibling directories.

    SHAPE check, deliberately not an on-disk existence check: the Execute
    Manager removes worktrees during cleanup BEFORE emitting its result block,
    so an existence check would fail every healthy run. What is verifiable
    after cleanup is that each recorded path is a non-empty ABSOLUTE path that
    is a SIBLING of the project — i.e. not the project root itself and not
    nested inside it (the `../{project}-{subtask_id}` convention in
    docs/ARCHITECTURE_CONTRACTS.md).
    """
    root = os.path.realpath(os.getcwd())
    for index, entry in enumerate(worktrees):
        if isinstance(entry, dict):
            path = as_text(entry.get("path")).strip()
        else:
            path = as_text(entry).strip()
        if not path:
            return (
                "worktrees[%d] has no path — every worktree entry must record the "
                "absolute sibling directory it used (rule 4)" % index
            )
        if not os.path.isabs(path):
            return (
                "worktrees[%d].path %r is not an absolute path; worktrees are "
                "recorded as absolute sibling directories (rule 4)" % (index, path)
            )
        resolved = os.path.realpath(path)
        if resolved == root or resolved.startswith(root + os.sep):
            return (
                "worktrees[%d].path %r is inside the project root, not a sibling "
                "directory (rule 4)" % (index, path)
            )
    return None


def _validate_result(fields):
    missing = [f for f in RESULT_REQUIRED if not present(fields, f)]
    if missing:
        emit(
            False,
            "EXECUTE_RESULT is missing required field(s): %s (rule 2)"
            % ", ".join(missing),
        )
    if is_empty_scalar(fields.get("summary")):
        emit(False, "EXECUTE_RESULT summary field must be non-empty (rule 2)")

    completed = _as_list(fields.get("subtasks_completed"))
    if completed is None:
        emit(False, "EXECUTE_RESULT subtasks_completed must be an array (rule 2)")
    merge_order = _as_list(fields.get("merge_order"))
    if merge_order is None:
        emit(False, "EXECUTE_RESULT merge_order must be an array (rule 2)")
    worktrees = _as_list(fields.get("worktrees"))
    if worktrees is None:
        emit(False, "EXECUTE_RESULT worktrees must be an array (rule 2)")

    # subtasks_completed may be empty ONLY when subtasks_failed is non-empty.
    if not _non_empty(completed):
        failed = _as_list(fields.get("subtasks_failed")) or []
        if not _non_empty(failed):
            emit(
                False,
                "EXECUTE_RESULT subtasks_completed is empty, which is permitted "
                "ONLY when subtasks_failed is non-empty and summary records the "
                "escalation (rule 2)",
            )

    problem = _check_worktree_paths(worktrees)
    if problem:
        emit(False, problem)


def _validate_checkpoint(fields):
    missing = [f for f in CHECKPOINT_REQUIRED if not present(fields, f)]
    if missing:
        emit(
            False,
            "EXECUTE_CHECKPOINT is missing required field(s): %s (rule 3)"
            % ", ".join(missing),
        )
    reason = as_text(fields.get("reason")).strip()
    if not reason:
        emit(False, "EXECUTE_CHECKPOINT reason field must be non-empty (rule 3)")

    completed_so_far = _as_list(fields.get("completed_so_far"))
    if completed_so_far is None:
        emit(False, "EXECUTE_CHECKPOINT completed_so_far must be an array (rule 3)")
    remaining = _as_list(fields.get("remaining"))
    if remaining is None:
        emit(False, "EXECUTE_CHECKPOINT remaining must be an array (rule 3)")

    # (4) also applies to a checkpoint's recorded worktrees, when present.
    worktrees = _as_list(fields.get("worktrees"))
    if worktrees:
        problem = _check_worktree_paths(worktrees)
        if problem:
            emit(False, problem)

    # ── (5) toolset_gap rejection ────────────────────────────────────────────
    if _TOOLSET_GAP_RE.search(reason):
        emit(False, REASON_TOOLSET_GAP)

    # ── (6) adjudication tri-field invariant, BIDIRECTIONAL ──────────────────
    # PRESENCE test, not truthiness: `adjudication_required: false` and an
    # ABSENT adjudication_required are both "not true" for 6b, but only the
    # present-and-true case triggers 6a.
    missing_outputs = _as_list(fields.get("missing_outputs")) or []
    adjudication_options = _as_list(fields.get("adjudication_options")) or []
    required_flag = None
    if present(fields, "adjudication_required"):
        required_flag, bad = as_bool(fields.get("adjudication_required"))
        if required_flag is None and fields.get("adjudication_required") is not None:
            emit(
                False,
                "EXECUTE_CHECKPOINT adjudication_required must be a boolean; got %s "
                "(rule 6)" % bad,
            )

    if required_flag is True:
        # (6a)
        if not _non_empty(missing_outputs) or not _non_empty(adjudication_options):
            emit(False, REASON_ADJUDICATION_INCOMPLETE)
    else:
        # (6b) — present (non-empty) without adjudication_required: true
        if _non_empty(missing_outputs) or _non_empty(adjudication_options):
            emit(False, REASON_ADJUDICATION_ORPHAN)


def main():
    name, fields, _text, _payload = load_block(BLOCKS, MISSING_BLOCK)

    # ── (1) schema_version present ───────────────────────────────────────────
    if not present(fields, "schema_version"):
        emit(False, "%s is missing the schema_version field (rule 1)" % name)
    schema_version, bad_sv = as_int(fields.get("schema_version"))
    if schema_version is None:
        emit(
            False,
            "%s schema_version must be an integer; got %s (rule 1)" % (name, bad_sv),
        )

    if name == RESULT_BLOCK:
        _validate_result(fields)
    else:
        _validate_checkpoint(fields)

    emit(True)


if __name__ == "__main__":
    run_validator(main)
