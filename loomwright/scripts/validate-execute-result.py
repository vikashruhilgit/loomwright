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

INVARIANT: ALWAYS exits 0. Decision on stdout only — including when the shared
module below cannot be imported (see the guard).
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
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
except BaseException as _import_exc:  # noqa: BLE001 — LAST LINE OF DEFENCE
    # R3, IMPORT-TIME edition. run_validator() cannot guard its own import: an
    # absent or syntactically broken result_block_parser.py exits 1 with a
    # traceback and NOTHING on stdout, which `|| true` then MASKS — a silently
    # dead validator. Fail SAFE, byte-identically to emit(True). Full rationale:
    # validate-worker-result.py's copy of this guard.
    import json as _json

    try:
        sys.stderr.write(
            "validate-execute-result: result_block_parser unavailable, failing "
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

# (6a) / (6b) — reason strings from the hooks.json prompt, WIDENED for D6.
#
# The original prompt named `missing_outputs` because the Step 2b requires-gap gate was the
# ONLY raiser of `adjudication_required`. v15.20.0 added a second raiser — the lane-collision
# gate (agents/execute-manager.md) — which has no producer/consumer `requires` edge and so no
# `missing_outputs[]` to report. Verified before this change: a lane-collision checkpoint was
# REJECTED outright by rule 6a ("requires non-empty missing_outputs"), i.e. the new gate was
# unemittable — its own SubagentStop hook failed the Execute Manager whenever it fired.
#
# The invariant itself is preserved and is the point: `adjudication_required: true` must always
# carry EVIDENCE plus options. What widened is which evidence field satisfies it — now
# `missing_outputs` (requires gap) OR `colliding_lanes` (lane collision). This is a widening,
# never a weakening: an adjudication with NEITHER evidence array is still rejected.
REASON_ADJUDICATION_INCOMPLETE = (
    "adjudication_required: true requires adjudication_options plus an evidence array — "
    "missing_outputs (requires-gap adjudication) or colliding_lanes (lane-collision "
    "adjudication); both empty is never valid"
)
REASON_ADJUDICATION_ORPHAN = (
    "missing_outputs/colliding_lanes/adjudication_options present without "
    "adjudication_required: true — the fields are all-or-nothing"
)
# Closed enum for the optional discriminator. ABSENT is legal and means `requires_gap` (every
# pre-v15.20.0 checkpoint predates the field), so consumers branch deterministically instead of
# pattern-matching the free-text `reason` prose.
VALID_ADJUDICATION_KIND = ("requires_gap", "lane_collision")
REASON_ADJUDICATION_KIND = (
    "adjudication_kind, when present, must be one of: %s (rule 6)"
    % ", ".join(VALID_ADJUDICATION_KIND)
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


def _project_root(payload):
    """The project root that worktree paths must be siblings OF.

    The hook payload's own `cwd` is AUTHORITATIVE; the hook process's
    os.getcwd() is only the fallback. This module already treats the payload
    cwd as authoritative in worker_summary_file_evidence, and rule 4 must agree
    with it: keying on os.getcwd() alone meant that a hook invoked with its cwd
    set to the project's PARENT — precisely where the `../{project}-{subtask_id}`
    siblings live — classified every one of them as "inside the project root"
    and rejected every healthy EXECUTE_RESULT.
    """
    if isinstance(payload, dict):
        cwd = payload.get("cwd")
        if isinstance(cwd, str) and cwd.strip():
            return os.path.realpath(cwd.strip())
    return os.path.realpath(os.getcwd())


def _check_worktree_paths(worktrees, payload):
    """(4) all worktree paths reference valid sibling directories.

    SHAPE check, deliberately not an on-disk existence check. TWO reasons, both
    verified — an earlier revision justified this with the claim that "the
    Execute Manager removes worktrees during cleanup BEFORE emitting its result
    block", which is FALSE: worktree removal is Supervisor Phase 4 FINALIZE
    step 4 (`skills/async-orchestration/SKILL.md` §"Cleanup worktrees"), which
    runs AFTER the Execute Manager has returned, and the Execute Manager's own
    Output Format records `worktrees:` explicitly "for cleanup"
    (`agents/execute-manager.md` §"Output Format"). The real reasons:

      1. An existence probe is RACY against FINALIZE. This SubagentStop hook
         fires when the Execute Manager finishes, i.e. BEFORE FINALIZE removes
         the worktrees — but a checkpoint/resume run, a crash, or a re-emitted
         block can land on either side of that removal. The same healthy run
         would then pass or fail depending on timing.
      2. The hook's cwd is not guaranteed to be the main checkout, so a
         filesystem probe is not a reliable signal in the first place (the very
         defect _project_root above exists to contain).

    What IS reliably verifiable is the recorded SHAPE: a non-empty path that
    resolves to a SIBLING of the project root — not the root itself and not
    nested inside it (the `../{project}-{subtask_id}` convention in
    docs/ARCHITECTURE_CONTRACTS.md).

    ABSOLUTE-PATH DEMAND: DROPPED, deliberately. An earlier revision rejected
    any non-absolute path, which the replaced prompt did not require — its rule
    4 asks only for "valid sibling directories". Since the convention is
    literally written as the RELATIVE `../{project}-{subtask_id}`, that added
    demand was a silent strengthening (R4 warns against exactly this) with a
    real false-fail cost. A relative path is now resolved against the project
    root and then held to the same sibling test, so `../myapp-a` passes while
    `relative/not/absolute` still fails — as a non-sibling, which is the rule
    actually being enforced.
    """
    root = _project_root(payload)
    for index, entry in enumerate(worktrees):
        if isinstance(entry, dict):
            path = as_text(entry.get("path")).strip()
        else:
            path = as_text(entry).strip()
        if not path:
            return (
                "worktrees[%d] has no path — every worktree entry must record the "
                "sibling directory it used (rule 4)" % index
            )
        resolved = os.path.realpath(
            path if os.path.isabs(path) else os.path.join(root, path)
        )
        if resolved == root or resolved.startswith(root + os.sep):
            return (
                "worktrees[%d].path %r resolves inside the project root (%s), not "
                "to a sibling directory (rule 4)" % (index, path, root)
            )
    return None


def _validate_result(fields, payload):
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

    problem = _check_worktree_paths(worktrees, payload)
    if problem:
        emit(False, problem)


def _validate_checkpoint(fields, payload):
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
        problem = _check_worktree_paths(worktrees, payload)
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
    colliding_lanes = _as_list(fields.get("colliding_lanes")) or []
    adjudication_options = _as_list(fields.get("adjudication_options")) or []
    required_flag = None

    # Discriminator is OPTIONAL (absent == requires_gap, the pre-D6 shape) but CLOSED when
    # present — an unrecognized kind would silently fall through Supervisor's reason-keyed
    # branch to the requires-gap default, which is the wrong option set and the wrong Option-C
    # failure reason.
    if present(fields, "adjudication_kind"):
        if as_text(fields.get("adjudication_kind")).strip() not in VALID_ADJUDICATION_KIND:
            emit(False, REASON_ADJUDICATION_KIND)
    if present(fields, "adjudication_required"):
        required_flag, bad = as_bool(fields.get("adjudication_required"))
        if required_flag is None and fields.get("adjudication_required") is not None:
            emit(
                False,
                "EXECUTE_CHECKPOINT adjudication_required must be a boolean; got %s "
                "(rule 6)" % bad,
            )

    if required_flag is True:
        # (6a) — options ALWAYS required; evidence satisfied by EITHER array (see the
        # REASON_ADJUDICATION_INCOMPLETE note). Neither present is still a hard reject.
        has_evidence = _non_empty(missing_outputs) or _non_empty(colliding_lanes)
        if not has_evidence or not _non_empty(adjudication_options):
            emit(False, REASON_ADJUDICATION_INCOMPLETE)
    else:
        # (6b) — present (non-empty) without adjudication_required: true
        if (
            _non_empty(missing_outputs)
            or _non_empty(colliding_lanes)
            or _non_empty(adjudication_options)
        ):
            emit(False, REASON_ADJUDICATION_ORPHAN)


def main():
    name, fields, _text, payload = load_block(BLOCKS, MISSING_BLOCK)

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
        _validate_result(fields, payload)
    else:
        _validate_checkpoint(fields, payload)

    emit(True)


if __name__ == "__main__":
    run_validator(main)
