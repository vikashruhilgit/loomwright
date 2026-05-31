#!/usr/bin/env python3
"""validate-launch-pad-result.py — schema validator for LAUNCH_PAD_RESULT v1.

Replaces the haiku type:prompt hook on the launch-pad-runner SubagentStop
matcher (Finding #3 in the v13.1.0 red-team audit). Performs real YAML-aware
parsing of the four-field block, robust against the five YAML null spellings
(null, Null, NULL, ~, empty-after-colon) and quoted literals that haiku
routinely confuses with the bareword null.

INVARIANT: ALWAYS exits 0. Hook output must never break the agent loop.
Validation outcome is communicated via stdout JSON only:
    {"ok": true}                  — passes
    {"ok": false, "reason": "..."} — fails

Schema authoritative in docs/RESULT_SCHEMAS.md §"LAUNCH_PAD_RESULT".

Why we don't depend on PyYAML:
    macOS system Python 3 does not ship PyYAML; a bundled-with-plugin yaml
    dependency would add an install footprint for a script that only ever
    parses four well-known key/value lines. Manual parsing of this fixed
    shape is ~50 lines and avoids the dependency.
"""

import json
import os
import re
import sys


VALID_STATUS = {"saved", "discarded", "blocked", "aborted"}
ALLOWED_KEYS = {"schema_version", "status", "saved_brief_path", "summary"}


def emit(ok, reason=""):
    """Print decision JSON and exit 0. Single exit point."""
    out = {"ok": bool(ok)}
    if not ok:
        out["reason"] = reason
    sys.stdout.write(json.dumps(out) + "\n")
    sys.exit(0)


def parse_yaml_scalar(value_str):
    """Decide what a YAML scalar after `key:` means.

    Returns (is_null, string_value). is_null=True iff the input matches one of
    the five YAML null spellings: empty-after-colon, ~, null, Null, NULL.

    A quoted "null" or 'null' is NOT a YAML null — it is the literal string
    "null", which this schema explicitly rejects when status != saved.
    """
    stripped = value_str.strip()
    if stripped == "" or stripped == "~" or stripped in ("null", "Null", "NULL"):
        return True, None
    # Strip enclosing quotes if present (returns the string, NOT null)
    if (stripped.startswith('"') and stripped.endswith('"')) or \
       (stripped.startswith("'") and stripped.endswith("'")):
        return False, stripped[1:-1]
    return False, stripped


def find_last_launch_pad_result_block(text):
    """Return the LAST LAUNCH_PAD_RESULT YAML block in `text`, or None.

    A block starts with a line matching exactly `LAUNCH_PAD_RESULT:` (with
    optional trailing whitespace) and continues with indented lines (1+ space)
    until a non-indented line or a blank line.

    Returning the LAST block matches the autonomous-loop SKILL.md PLAN-step-4
    semantics: agents may legitimately include example blocks (e.g., when
    summarizing what they emitted), and the contract is "the most recent
    emission wins."
    """
    candidates = []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        if re.match(r"^LAUNCH_PAD_RESULT:\s*$", line):
            block = [line]
            j = i + 1
            while j < len(lines):
                nxt = lines[j]
                if nxt.startswith(" "):
                    block.append(nxt)
                    j += 1
                elif nxt.strip() == "":
                    # Blank line terminates the block (strict over permissive).
                    break
                else:
                    break
            candidates.append("\n".join(block))
            i = j
        else:
            i += 1
    return candidates[-1] if candidates else None


def parse_block(block):
    """Parse the four-key YAML block manually. Returns (fields, extra_keys).

    fields is a dict mapping allowed keys to their parsed string values, with
    one extra synthetic key `_saved_brief_is_null` (True/False/None) recording
    whether saved_brief_path parsed as a YAML null.

    extra_keys is the set of top-level keys found that are NOT in ALLOWED_KEYS.

    Only handles the simple `key: value` lines this schema requires. Lists,
    nested mappings, and multi-line scalars are unsupported (and disallowed by
    the v1 schema).
    """
    fields = {"_saved_brief_is_null": None}
    extra_keys = set()
    seen_keys = set()

    for line in block.split("\n")[1:]:  # skip the LAUNCH_PAD_RESULT: header
        # Comments and blank lines are ignored
        if not line.strip() or line.strip().startswith("#"):
            continue
        if ":" not in line:
            continue
        # Indented top-level key under the LAUNCH_PAD_RESULT: header
        stripped = line.strip()
        key, _, val_part = stripped.partition(":")
        key = key.strip()
        if not key:
            continue
        if key not in ALLOWED_KEYS:
            extra_keys.add(key)
            continue
        if key in seen_keys:
            # Duplicate top-level key. Treat as malformed.
            extra_keys.add("duplicate:" + key)
            continue
        seen_keys.add(key)
        if key == "saved_brief_path":
            is_null, value = parse_yaml_scalar(val_part)
            fields["_saved_brief_is_null"] = is_null
            fields["saved_brief_path"] = value
        else:
            # Strip surrounding quotes if any; preserve the rest as a string
            value = val_part.strip()
            if (value.startswith('"') and value.endswith('"')) or \
               (value.startswith("'") and value.endswith("'")):
                value = value[1:-1]
            fields[key] = value

    return fields, extra_keys


def main():
    # Two input modes:
    #   default      → stdin is a Claude Code hook payload (JSON envelope with
    #                  a result_block / output / agent_output field). Used by
    #                  the SubagentStop[launch-pad-runner] hook in hooks.json.
    #   --raw        → stdin IS the agent's output text directly (no JSON
    #                  envelope). Used by the autonomous-loop SKILL.md PLAN
    #                  step when validating an inline-path emission.
    raw_mode = len(sys.argv) > 1 and sys.argv[1] == "--raw"

    if raw_mode:
        result_block = sys.stdin.read()
    else:
        try:
            payload = json.load(sys.stdin)
        except (json.JSONDecodeError, ValueError):
            # If stdin isn't valid JSON, the hook plumbing is malformed — we
            # cannot validate, so exit ok=true (the existing CODE_REVIEW_RESULT
            # pattern: never break the agent loop on validator failures).
            emit(True)
            return

        # Extract the agent's output text. Claude Code SubagentStop payloads
        # carry the finishing agent's output in `result_block`; some variants
        # may use `output` or `agent_output`. Be defensive about field naming.
        result_block = (
            payload.get("result_block")
            or payload.get("output")
            or payload.get("agent_output")
            or ""
        )

    if not result_block:
        emit(False, "no result_block / output field in hook payload")
        return

    block = find_last_launch_pad_result_block(result_block)
    if block is None:
        emit(
            False,
            "missing LAUNCH_PAD_RESULT block — Phase 7 emission required since v14.2.0",
        )
        return

    fields, extra_keys = parse_block(block)

    # Reject extra top-level keys (the explicit four-field discipline cap)
    if extra_keys:
        emit(
            False,
            "LAUNCH_PAD_RESULT v1 accepts exactly four fields; got extra key(s): "
            + ", ".join(sorted(extra_keys)),
        )
        return

    # schema_version must equal "1" (parsed as a string here; YAML "1" and 1
    # both serialize the same way through our manual parser).
    sv = fields.get("schema_version")
    if sv != "1":
        emit(False, "schema_version must be the integer 1; got " + repr(sv))
        return

    # status enum membership
    status = fields.get("status")
    if status not in VALID_STATUS:
        emit(
            False,
            "status must be one of [aborted, blocked, discarded, saved]; got "
            + repr(status),
        )
        return

    # summary non-empty
    summary = (fields.get("summary") or "").strip()
    if not summary:
        emit(False, "summary field must be a non-empty string")
        return

    # saved_brief_path / status invariant (the headline reason this validator
    # replaces a haiku type:prompt hook — real YAML null awareness)
    is_null = fields["_saved_brief_is_null"]
    if is_null is None:
        emit(False, "saved_brief_path field is required")
        return

    if status == "saved":
        if is_null:
            emit(
                False,
                "status=saved requires saved_brief_path to be a non-empty string "
                "matching '.supervisor/jobs/pending/*.md'; got YAML null",
            )
            return
        path = fields.get("saved_brief_path", "")
        if not (path.startswith(".supervisor/jobs/pending/") and path.endswith(".md")):
            emit(
                False,
                "status=saved requires saved_brief_path matching "
                "'.supervisor/jobs/pending/*.md'; got " + repr(path),
            )
            return
        # File-existence invariant (RESULT_SCHEMAS.md §"LAUNCH_PAD_RESULT"): the
        # brief MUST exist on disk at emission time. Resolved relative to the
        # hook/run CWD = project root. `os` is stdlib — no dependency added.
        if not os.path.exists(path):
            emit(
                False,
                "status=saved: saved_brief_path '" + path
                + "' does not exist on disk",
            )
            return
    else:
        # status ∈ {discarded, blocked, aborted}: must be YAML literal null
        if not is_null:
            emit(
                False,
                "status=" + status + " requires saved_brief_path to be the YAML "
                "literal null (NOT the string 'null', NOT empty-quoted, NOT a "
                "path); got non-null value " + repr(fields.get("saved_brief_path")),
            )
            return

    emit(True)


if __name__ == "__main__":
    main()
