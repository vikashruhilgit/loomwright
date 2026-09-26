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

DELIBERATE STRENGTHENING BEYOND THE PROMPT (recorded, not accidental):
  * Rule (2) rejects a NEGATIVE tests_generated / tests_passed. The prompt
    required only that they be "present as integers", so `tests_passed: -1`
    would have satisfied it. The strengthening is kept because a negative test
    count is not a state any QA Executor can legitimately report and rule (4)'s
    `tests_generated > 0` conditional reads a signed value, but it IS a
    deviation from the transcribed rule and is disclosed here rather than left
    for a reader to discover — R4 in the brief asks that the transcription not
    silently drift from the prompt in EITHER direction.

VERIFY_RESULT BRANCH (the qa-executor `--verify` mode, added with `/verify`).
RULE SOURCE: docs/RESULT_SCHEMAS.md §VERIFY_RESULT. The same hook command
validates BOTH blocks; which rules apply is decided by NAME, not by position:

  * `QA_RESULT` WINS WHENEVER IT IS PRESENT, regardless of where it sits — a
    payload carrying both blocks is validated EXACTLY as today by the five
    rules above (the VERIFY_RESULT block is ignored). Each block is located
    with the single-name `find_last_block(text, <name>)`; the multi-name
    `find_last_named_block` / a `load_block` name tuple both return whichever
    block occurs LAST, which would invert this rule.
  * else a `VERIFY_RESULT` block is accepted iff:
      (V1) schema_version is the integer 1
      (V2) run_id and run_dir are present, non-empty strings
      (V3) summary is present and non-empty
      (V4) status is one of [completed, aborted, paused]
      (V5) counts is a mapping whose pass / fail / blocked / not_verifiable /
           total are all present integers
      (V6) counts.total == pass + fail + blocked + not_verifiable
      (V7) pause_reason is a REQUIRED KEY / NULLABLE VALUE: non-null and one
           of [needs_auth, session_expired] iff status == paused; null iff
           status is completed/aborted (either direction of mismatch fails)
      (V8) spec_sources (token-economy 07) is OPTIONAL — absent validates
           unchanged (the V7 precedent: additive, no schema_version bump).
           Present: must be a mapping with EXACTLY the keys replayed /
           authored / rederived, each a non-negative integer (mirrors V5's
           as_int conversion for `counts` — this text-block parser never
           distinguishes a quoted numeric literal from a bare one, so "a
           string" rejected here means a value that does not parse as an
           integer at all, e.g. `replayed: three`)
    (`counts` is COPIED from `verify-run.sh finish`'s printed row — the agent
    never tallies; V6 is what catches a hand-edited row. `spec_sources` is
    COPIED from the same `finish`/`summary-build` derived line, same rule.)
  * else the existing `missing QA_RESULT block` reason, unchanged.

INVARIANT: ALWAYS exits 0. Decision on stdout only — including when the shared
module below cannot be imported (see the guard).
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    from result_block_parser import (  # noqa: E402
        NO_OUTPUT_REASON,
        PAYLOAD_UNPARSEABLE,
        as_int,
        as_text,
        emit,
        extract_payload,
        find_last_block,
        is_empty_scalar,
        parse_block,
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
            "safe (pass, `{}`): %s: %s\n" % (type(_import_exc).__name__, _import_exc)
        )
    except BaseException:
        pass
    try:
        sys.stdout.write(_json.dumps({}) + "\n")  # pass: no decision
        sys.stdout.flush()
    except BaseException:
        pass
    os._exit(0)

BLOCK = "QA_RESULT"
VERIFY_BLOCK = "VERIFY_RESULT"

VERIFY_VALID_STATUS = ("completed", "aborted", "paused")
VERIFY_COUNT_KEYS = ("pass", "fail", "blocked", "not_verifiable", "total")
VERIFY_PAUSE_REASONS = ("needs_auth", "session_expired")
SPEC_SOURCES_KEYS = ("replayed", "authored", "rederived")

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


def locate_blocks():
    """The stdin → text → block prologue, with the QA_RESULT-wins rule.

    Mirrors `load_block`'s failure paths (unparseable stdin → ok:true; no agent
    output → NO_OUTPUT_REASON; neither block → MISSING_BLOCK; a malformed body
    → explicit parse failure) but locates EACH block BY NAME so precedence is
    decided by presence, never by which block happens to occur last.
    Returns (block_name, fields).
    """
    text, _payload = extract_payload()
    if text is PAYLOAD_UNPARSEABLE:
        emit(True)
    if not text:
        emit(False, NO_OUTPUT_REASON)

    name = BLOCK
    block = find_last_block(text, BLOCK)
    if block is None:
        name = VERIFY_BLOCK
        block = find_last_block(text, VERIFY_BLOCK)
    if block is None:
        emit(False, MISSING_BLOCK)

    fields, errors = parse_block(block)
    if errors:
        emit(
            False,
            "%s block could not be parsed (unsupported or malformed YAML): %s"
            % (name, "; ".join(errors[:3])),
        )
    return name, fields


def validate_verify(fields):
    """The VERIFY_RESULT rules (V1)–(V8); see the module docstring."""
    # ── (V1) schema_version equal to 1 ───────────────────────────────────────
    if not present(fields, "schema_version"):
        emit(False, "VERIFY_RESULT is missing the schema_version field (rule V1)")
    schema_version, bad_sv = as_int(fields.get("schema_version"))
    if schema_version != 1:
        emit(
            False,
            "VERIFY_RESULT schema_version must be the integer 1; got %s (rule V1)"
            % (bad_sv if schema_version is None else schema_version),
        )

    # ── (V2) run_id and run_dir present, non-empty strings ───────────────────
    for key in ("run_id", "run_dir"):
        if not present(fields, key):
            emit(False, "VERIFY_RESULT is missing the %s field (rule V2)" % key)
        value = fields.get(key)
        if not isinstance(value, str) or is_empty_scalar(value):
            emit(False, "VERIFY_RESULT %s must be a non-empty string; got %r (rule V2)" % (key, value))

    # ── (V3) summary present ─────────────────────────────────────────────────
    if not present(fields, "summary") or is_empty_scalar(fields.get("summary")):
        emit(False, "VERIFY_RESULT summary field must be present and non-empty (rule V3)")

    # ── (V4) status enum ─────────────────────────────────────────────────────
    if not present(fields, "status"):
        emit(False, "VERIFY_RESULT is missing the status field (rule V4)")
    status = as_text(fields.get("status")).strip()
    if status not in VERIFY_VALID_STATUS:
        emit(False, "VERIFY_RESULT status must be one of [completed, aborted, paused]; got %r (rule V4)" % status)

    # ── (V5) counts: a mapping of five integers ──────────────────────────────
    if not present(fields, "counts"):
        emit(False, "VERIFY_RESULT is missing the counts field (rule V5)")
    counts = fields.get("counts")
    if not isinstance(counts, dict):
        emit(False, "VERIFY_RESULT counts must be a mapping; got %r (rule V5)" % (counts,))
    values = {}
    for key in VERIFY_COUNT_KEYS:
        if key not in counts:
            emit(False, "VERIFY_RESULT counts is missing %s (rule V5)" % key)
        value, bad = as_int(counts.get(key))
        if value is None:
            emit(False, "VERIFY_RESULT counts.%s must be an integer; got %s (rule V5)" % (key, bad))
        if value < 0:
            emit(False, "VERIFY_RESULT counts.%s must be a non-negative integer; got %d (rule V5)" % (key, value))
        values[key] = value

    # ── (V6) total == pass + fail + blocked + not_verifiable ─────────────────
    expected = values["pass"] + values["fail"] + values["blocked"] + values["not_verifiable"]
    if values["total"] != expected:
        emit(
            False,
            "VERIFY_RESULT counts.total must equal pass+fail+blocked+not_verifiable "
            "(%d); got %d — counts are COPIED from `verify-run.sh finish`, never tallied (rule V6)"
            % (expected, values["total"]),
        )

    # ── (V7) pause_reason paired with status, in BOTH directions ─────────────
    # Absent and explicit-null are treated identically here (the `classification`
    # null/absent convention already used by §VERIFY_EVIDENCE) so a pre-item-04
    # emitter that never sends the key at all keeps validating unchanged for every
    # non-paused status — only a `paused` status ever requires a real value.
    pause_reason_empty = is_empty_scalar(fields.get("pause_reason"))
    if status == "paused":
        if pause_reason_empty:
            emit(False, "VERIFY_RESULT pause_reason must be non-null when status is paused (rule V7)")
        pause_reason = as_text(fields.get("pause_reason")).strip()
        if pause_reason not in VERIFY_PAUSE_REASONS:
            emit(
                False,
                "VERIFY_RESULT pause_reason must be one of [needs_auth, session_expired] "
                "when status is paused; got %r (rule V7)" % pause_reason,
            )
    else:
        if not pause_reason_empty:
            emit(
                False,
                "VERIFY_RESULT pause_reason must be null when status is %r; got %r (rule V7)"
                % (status, fields.get("pause_reason")),
            )

    # ── (V8) spec_sources: OPTIONAL, additive, no schema_version bump ────────
    # token-economy 07 — the V7 precedent (absent ⇒ a pre-item emitter keeps validating unchanged).
    if present(fields, "spec_sources"):
        spec_sources = fields.get("spec_sources")
        if not isinstance(spec_sources, dict):
            emit(False, "VERIFY_RESULT spec_sources must be a mapping; got %r (rule V8)" % (spec_sources,))
        extra_keys = sorted(set(spec_sources) - set(SPEC_SOURCES_KEYS))
        if extra_keys:
            emit(
                False,
                "VERIFY_RESULT spec_sources carries unknown key(s) %s; it must have EXACTLY "
                "replayed/authored/rederived (rule V8)" % ", ".join(extra_keys),
            )
        for key in SPEC_SOURCES_KEYS:
            if key not in spec_sources:
                emit(False, "VERIFY_RESULT spec_sources is missing %s (rule V8)" % key)
            value, bad = as_int(spec_sources.get(key))
            if value is None:
                emit(False, "VERIFY_RESULT spec_sources.%s must be an integer; got %s (rule V8)" % (key, bad))
            if value < 0:
                emit(
                    False,
                    "VERIFY_RESULT spec_sources.%s must be a non-negative integer; got %d (rule V8)"
                    % (key, value),
                )

    emit(True)


def main():
    name, fields = locate_blocks()
    if name == VERIFY_BLOCK:
        validate_verify(fields)

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
