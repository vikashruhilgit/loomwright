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
  (7) v12 outputs_verified shape — WHEN PRESENT (the prompt's own scoping, at
      any schema_version), each entry needs kind (file|symbol|type),
      path (string), status (present|missing)
  (8) v12 outputs_gap/status invariant — outputs_gap non-empty with
      status: completed is rejected

DELIBERATE NON-ADDITIONS / NARROWINGS (recorded, not accidental):
  * The prompt does NOT constrain WORKER_RESULT.status to an enum, so neither
    does this script (R4: transcribe, do not silently strengthen).
    RESULT_SCHEMAS.md's `status ∈ {completed, failed, partial}` is enforced by
    the schema doc and by check-contract-parity.sh's ENUMS table, not here.
  * Rule (4) is evaluated for `failed` and `completed` only. `partial` is
    EXEMPT — see the rule-4 block for why (its documented example legitimately
    carries a non-empty error).
  * Rule (3)'s tiers are deliberately lax in two places, disclosed in
    result_block_parser.worker_summary_file_evidence.

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
        find_destructive_command,
        is_empty_scalar,
        load_block,
        present,
        run_validator,
        worker_summary_file_evidence,
    )
except BaseException as _import_exc:  # noqa: BLE001 — LAST LINE OF DEFENCE
    # R3, IMPORT-TIME edition. run_validator() guarantees exit 0 for anything
    # raised inside main(), but it cannot guard its own import: with
    # result_block_parser.py absent, unreadable or syntactically broken, this
    # module never finishes loading, python exits 1 with a traceback, and
    # NOTHING reaches stdout. Under the `type: command` + `|| true` wiring that
    # non-zero exit is MASKED, so the hook silently validates nothing — the
    # silently-dead-validator failure CLAUDE.md §Failure-Mode Invariants calls a
    # security regression.
    #
    # This edge is OURS: the template these scripts are modelled on
    # (validate-launch-pad-result.py) is self-contained and has no import to
    # fail. The shared-module design introduced it, so the shared-module design
    # guards it. Catch BaseException deliberately — nothing may escape.
    #
    # Fail SAFE, byte-identically to emit(True): we cannot validate, and we must
    # not break the agent loop.
    import json as _json

    try:
        sys.stderr.write(
            "validate-worker-result: result_block_parser unavailable, failing "
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
# Same verbatim rule-6 string, with the null diagnosis appended. A present-but-
# null field and an ABSENT field are different defects and must read differently
# (the nullable-vs-absent lesson); the verbatim prefix is preserved intact.
REASON_V2_NULL = (
    REASON_V2_FIELDS
    + " — %s is present but null, and a null is neither an array nor a string "
    "(an explicit null is a DIFFERENT defect from an absent field)"
)
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
    #
    # DELIBERATE NARROWING — `status: partial` is EXEMPT from rule 4, and this
    # is a recorded exemption rather than an oversight. `partial` is a
    # documented emission path whose own worked example in agents/worker.md
    # §"Output Format" carries a NON-EMPTY error ("Tests fail: refresh token
    # rotation test expects cookie but HttpOnly flag prevents access in test
    # environment") alongside a non-empty outputs_gap. On `partial`, an
    # outstanding error is the POINT of the status, not a contract violation;
    # extending rule 4 to cover it would false-fail the documented shape. The
    # `partial` contract is instead enforced by rules 6-8, where a non-empty
    # outputs_gap must map to exactly this status.
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

    # ── (6) v12 outputs_verified / outputs_gap PRESENCE and TYPE ─────────────
    # PRESENCE, not truthiness: `outputs_gap: ""` is legal and means "nothing
    # missing", while an ABSENT outputs_gap is a contract violation. A
    # truthiness check cannot tell those apart.
    #
    # PRESENT-BUT-NULL IS ALSO REJECTED, on both fields. An earlier revision
    # coerced `outputs_verified: null` to `[]` (so rule 7's entry-shape checks
    # never ran) and accepted `outputs_gap: null` as satisfying "(string)" (so
    # rule 8's cross-field invariant short-circuited on an empty as_text()).
    # A wrong-typed SCALAR was already rejected, which made null the single
    # non-conforming value slipping through — an inconsistency, not a reading of
    # the rule. The rule says "array" and "string"; a null is neither.
    if schema_version >= 2:
        if not present(fields, "outputs_verified") or not present(fields, "outputs_gap"):
            emit(False, REASON_V2_FIELDS)
        outputs_verified = fields.get("outputs_verified")
        if outputs_verified is None:
            emit(False, REASON_V2_NULL % "outputs_verified")
        if not isinstance(outputs_verified, list):
            emit(False, REASON_V2_FIELDS)
        outputs_gap_raw = fields.get("outputs_gap")
        if outputs_gap_raw is None:
            emit(False, REASON_V2_NULL % "outputs_gap")
        if not isinstance(outputs_gap_raw, str):
            emit(False, REASON_V2_FIELDS)

        # ── (8) outputs_gap / status cross-field invariant ───────────────────
        outputs_gap = as_text(outputs_gap_raw).strip()
        if outputs_gap and status == "completed":
            emit(False, REASON_GAP_STATUS)

    # ── (7) outputs_verified entry shape ─────────────────────────────────────
    # SCOPED BY PRESENCE, NOT BY schema_version — deliberately OUTSIDE the
    # `schema_version >= 2` block above. Rules 6 and 8 say "if schema_version is
    # 2 or higher" verbatim; rule 7 says "WHEN PRESENT". A v1 block is not
    # required to carry outputs_verified, but if it does, the entries still have
    # to be well-formed, and gating this loop on the version silently exempted
    # exactly that case from any shape check.
    if present(fields, "outputs_verified"):
        entries = fields.get("outputs_verified")
        # A null or wrong-typed outputs_verified is rule 6's business and is
        # already rejected above for v2. On a v1 block there is no such rule to
        # lean on, so a non-list is simply not iterable entry-shape data — skip
        # rather than invent a v1 type rule the prompt never stated (R4:
        # transcribe, do not silently strengthen).
        if isinstance(entries, list):
            for entry in entries:
                if not isinstance(entry, dict):
                    emit(False, REASON_ENTRY_SHAPE)
                for required in ("kind", "path", "status"):
                    if required not in entry or is_empty_scalar(entry.get(required)):
                        emit(False, REASON_ENTRY_SHAPE)
                if as_text(entry.get("kind")).strip() not in VALID_KINDS:
                    emit(False, REASON_ENTRY_SHAPE)
                if as_text(entry.get("status")).strip() not in VALID_ENTRY_STATUS:
                    emit(False, REASON_ENTRY_SHAPE)

    emit(True)


if __name__ == "__main__":
    run_validator(main)
