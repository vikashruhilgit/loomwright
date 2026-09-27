#!/usr/bin/env python3
"""validate-code-review-result.py — deterministic validator for CODE_REVIEW_RESULT
v2 / v3.

Replaces the `type: prompt` (haiku, 30s timeout) SubagentStop hook on the
`loomwright:code-reviewer` matcher with a zero-token `type: command` script.

WHY (probed 2026-09-27): current runtimes deliver the reviewer's report — the
CODE_REVIEW_RESULT block included — as the `input.message` of the LAST
`SubagentHandback` tool call in `agent_transcript_path`; the payload's
`last_assistant_message` is only a prose recap that NAMES the block. The prompt
model judges `$ARGUMENTS` (the payload), so it never saw a block it could
check: on one live firing it blocked a valid reviewer ("CODE_REVIEW_RESULT
block missing … YAML … is not valid JSON") and the reviewer re-emitted the
block as JSON to get past it; on two others it let the same shape through
unchecked. Either way no rule below was ever evaluated. This script resolves
the block through `load_block` → `resolve_payload_text` (handback-aware) and
checks every rule in code.

RULE SOURCE: transcribed from the prompt string this script replaced (see
git history of `loomwright/hooks/hooks.json`, SubagentStop matcher
`loomwright:code-reviewer`). Rule letters are the prompt's own; where the
prompt gave a verbatim reason string, it is reused verbatim.

  schema_version ∈ {2, 3}; 1 → 'schema_version 1 is no longer supported;
  upgrade to v3'.
  COMMON: (A) decision ∈ {PASS, FAIL, NEEDS_HUMAN}; (B) summary present.
  v2: (a) issue shape — severity/file/description/category, category ∈
      {new, pre_existing, nit}; (b) FAIL ⇒ ≥1 new BLOCKING/HIGH issue;
      (c) FAIL/NEEDS_HUMAN ⇒ issues non-empty.
  v3: (a) review_mode ∈ {diff_review, consistency_audit}; (b) audit_focus an
      array, non-empty iff consistency_audit, closed element set;
      (c) trigger_paths_detected an array; (d) CROSS-FIELD: non-empty
      trigger_paths_detected ⇒ consistency_audit; (e) files_checked a
      non-empty array of strings; (f) scope_expanded an array;
      (g) consistency_audit ⇒ consistency_checks with all 5 sub-keys ∈
      {pass, fail, not_applicable} + non-empty consistency_summary;
      (h) issue shape + closed key set; (i) drift ⇒ drift_kind in closed set;
      (j) DRIFT SEVERITY CAPS — count/version_secondary ≤ MEDIUM,
      hooks_parity/wording ≤ LOW; (k) FAIL ⇒ ≥1 new/drift BLOCKING/HIGH issue
      (the caps in (j) mean capped drift can never satisfy it);
      (l) FAIL/NEEDS_HUMAN ⇒ issues non-empty.

(B) is enforced as present AND non-empty — an empty summary carries nothing a
caller can act on, and every sibling validator reads "present" that way.

INVARIANT: ALWAYS exits 0. Decision on stdout only — `{}` to allow,
`{"decision": "block", "reason": …}` to block (result_block_parser.emit),
never the `{"ok": …}` prompt-hook shape — including when the shared module
below cannot be imported (see the guard).

`--main-session` MODE (the `Stop` hook, v15.108.1): the same rules for a
code-reviewer running as the MAIN agent of its own session
(`claude --agent loomwright:code-reviewer`), where no SubagentStop fires. The
`Stop` event fires at EVERY main-thread turn end of EVERY session, so this mode
first decides whose turn is ending from the payload's TOP-LEVEL `agent_type`
alone and allows (`{}`) anything that is not the reviewer. Probed 2026-09-27 on
Claude Code v2.1.283 (fixture: scripts/fixtures/stop-payload-shape-probe.json):
a plain main thread's Stop payload carries NO top-level `agent_type`; an
`--agent loomwright:code-reviewer` session carries
`agent_type: "loomwright:loomwright:code-reviewer"`; and a main thread with a
reviewer running in the background carries that same string only INSIDE
`background_tasks[]`. The retired `type: prompt` Stop hook read the whole
payload and judged that background child, blocking every main-thread turn end
while the reviewer ran. `background_tasks` is never read here.
"""

import io
import json
import os
import re
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
            "validate-code-review-result: result_block_parser unavailable, failing "
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

BLOCK = "CODE_REVIEW_RESULT"

VALID_DECISION = ("PASS", "FAIL", "NEEDS_HUMAN")
ISSUES_REQUIRED_DECISIONS = ("FAIL", "NEEDS_HUMAN")
SEVERITIES = ("BLOCKING", "HIGH", "MEDIUM", "LOW")
BLOCKING_SEVERITIES = ("BLOCKING", "HIGH")
V2_CATEGORIES = ("new", "pre_existing", "nit")
V3_CATEGORIES = ("new", "pre_existing", "nit", "drift")
REVIEW_MODES = ("diff_review", "consistency_audit")
AUDIT_FOCUS = ("mirrored_prompt", "metadata", "counts", "docs", "hooks", "plan_prompt")
CONSISTENCY_KEYS = (
    "mirrored_prompts", "version_strings", "counts", "workflow_alignment", "hooks_parity",
)
CONSISTENCY_VALUES = ("pass", "fail", "not_applicable")
ISSUE_KEYS = ("severity", "category", "drift_kind", "file", "line", "description", "suggestion")
ISSUE_REQUIRED = ("severity", "file", "description", "category")
DRIFT_KINDS = (
    "version_authoritative", "version_secondary", "mirrored_prompt", "count",
    "workflow", "hooks_parity", "wording",
)
# (j) — the highest severity each capped drift_kind may carry.
DRIFT_CAPS = {
    "count": "MEDIUM",
    "version_secondary": "MEDIUM",
    "hooks_parity": "LOW",
    "wording": "LOW",
}

MISSING_BLOCK = (
    "missing CODE_REVIEW_RESULT block — the Code Reviewer must emit one; its "
    "decision gates the review (agents/code-reviewer.md §\"Outputs\", "
    "docs/RESULT_SCHEMAS.md#code_review_result)"
)


def _rank(severity):
    """Lower rank = more severe; unknown severities sort last."""
    return SEVERITIES.index(severity) if severity in SEVERITIES else len(SEVERITIES)


def _array(fields, key, rule):
    """Return fields[key] when it is present and a list; block otherwise."""
    if not present(fields, key):
        emit(False, "CODE_REVIEW_RESULT is missing the %s field; it must be an array (%s)"
             % (key, rule))
    val = fields.get(key)
    if not isinstance(val, list):
        emit(False, "%s must be an array; got %r (%s)" % (key, as_text(val), rule))
    return val


def _issues(fields, rule):
    raw = fields.get("issues")
    if present(fields, "issues") and raw is not None and not isinstance(raw, list):
        emit(False, "issues must be an array; got %r (%s)" % (as_text(raw), rule))
    issues = raw if isinstance(raw, list) else []
    return [i for i in issues if i is not None]


def _check_issue_shape(issues, categories, rule):
    """Every issue: a mapping carrying non-empty severity/file/description/category
    with severity and category in their enums. Returns the (severity, category)
    pairs, stripped."""
    out = []
    for index, issue in enumerate(issues):
        if not isinstance(issue, dict):
            emit(False, "issue[%d] is not a mapping; each issue needs %s (%s)"
                 % (index, "/".join(ISSUE_REQUIRED), rule))
        for key in ISSUE_REQUIRED:
            if key not in issue or is_empty_scalar(issue.get(key)):
                emit(False, "issue[%d] is missing a non-empty %s field (%s)"
                     % (index, key, rule))
        severity = as_text(issue.get("severity")).strip()
        if severity not in SEVERITIES:
            emit(False, "issue[%d] severity must be one of %s; got %r (%s)"
                 % (index, ", ".join(SEVERITIES), severity, rule))
        category = as_text(issue.get("category")).strip()
        if category not in categories:
            emit(False, "issue[%d] category must be one of %s; got %r (%s)"
                 % (index, ", ".join(categories), category, rule))
        out.append((severity, category))
    return out


def _check_v2(fields, decision):
    issues = _issues(fields, "v2 rule a")
    pairs = _check_issue_shape(issues, V2_CATEGORIES, "v2 rule a")
    if decision in ISSUES_REQUIRED_DECISIONS and not issues:
        emit(False, "decision=%s requires a non-empty issues array (v2 rule c)" % decision)
    if decision == "FAIL" and not any(
            cat == "new" and sev in BLOCKING_SEVERITIES for sev, cat in pairs):
        emit(False, "decision=FAIL requires at least one issue with category='new' and "
                    "severity BLOCKING or HIGH (v2 rule b)")


def _check_v3(fields, decision):
    # (a) review_mode
    if not present(fields, "review_mode"):
        emit(False, "CODE_REVIEW_RESULT is missing the review_mode field (v3 rule a)")
    mode = as_text(fields.get("review_mode")).strip()
    if mode not in REVIEW_MODES:
        emit(False, "review_mode must be one of %s; got %r (v3 rule a)"
             % (", ".join(REVIEW_MODES), mode))
    audit = mode == "consistency_audit"

    # (b) audit_focus — array, non-empty iff consistency_audit, closed set
    focus = _array(fields, "audit_focus", "v3 rule b")
    if audit and not focus:
        emit(False, "audit_focus must be non-empty when review_mode=consistency_audit "
                    "(v3 rule b)")
    if not audit and focus:
        emit(False, "audit_focus must be empty when review_mode=%s (v3 rule b)" % mode)
    for index, tag in enumerate(focus):
        if as_text(tag).strip() not in AUDIT_FOCUS:
            emit(False, "audit_focus[%d] must be one of %s; got %r (v3 rule b)"
                 % (index, ", ".join(AUDIT_FOCUS), as_text(tag)))

    # (c) + (d) trigger_paths_detected and the cross-field invariant
    triggers = _array(fields, "trigger_paths_detected", "v3 rule c")
    if triggers and not audit:
        emit(False, "non-empty trigger_paths_detected requires "
                    "review_mode=consistency_audit")

    # (e) files_checked — non-empty array of strings
    files = fields.get("files_checked")
    if (not isinstance(files, list) or not files
            or any(not isinstance(f, str) or not f.strip() for f in files)):
        emit(False, "files_checked must be a non-empty array")

    # (f) scope_expanded
    _array(fields, "scope_expanded", "v3 rule f")

    # (g) consistency_audit ⇒ consistency_checks + consistency_summary
    if audit:
        checks = fields.get("consistency_checks")
        if not isinstance(checks, dict):
            emit(False, "review_mode=consistency_audit requires a consistency_checks "
                        "object (v3 rule g)")
        for key in CONSISTENCY_KEYS:
            if key not in checks:
                emit(False, "consistency_checks is missing the %s sub-key (v3 rule g)" % key)
            val = as_text(checks.get(key)).strip()
            if val not in CONSISTENCY_VALUES:
                emit(False, "consistency_checks.%s must be one of %s; got %r (v3 rule g)"
                     % (key, ", ".join(CONSISTENCY_VALUES), val))
        if (not present(fields, "consistency_summary")
                or is_empty_scalar(fields.get("consistency_summary"))):
            emit(False, "review_mode=consistency_audit requires a non-empty "
                        "consistency_summary (v3 rule g)")

    # (h) issue shape + closed key set
    issues = _issues(fields, "v3 rule h")
    pairs = _check_issue_shape(issues, V3_CATEGORIES, "v3 rule h")
    for index, issue in enumerate(issues):
        for key in issue:
            if key not in ISSUE_KEYS:
                emit(False, "issue[%d] contains disallowed key %s; only schema fields "
                            "are accepted" % (index, key))

    # (i) drift ⇒ drift_kind, and (j) its severity cap
    for index, (issue, (severity, category)) in enumerate(zip(issues, pairs)):
        if category != "drift":
            continue
        kind = as_text(issue.get("drift_kind")).strip()
        if kind not in DRIFT_KINDS:
            emit(False, "issue[%d] has category=drift and needs drift_kind in %s; got %r "
                        "(v3 rule i)" % (index, ", ".join(DRIFT_KINDS), kind))
        cap = DRIFT_CAPS.get(kind)
        if cap and _rank(severity) < _rank(cap):
            emit(False, "issue[%d] drift_kind=%s is capped at severity %s; got %s "
                        "(v3 rule j)" % (index, kind, cap, severity))

    # (l) FAIL / NEEDS_HUMAN ⇒ non-empty issues
    if decision in ISSUES_REQUIRED_DECISIONS and not issues:
        emit(False, "decision=%s requires a non-empty issues array (v3 rule l)" % decision)

    # (k) FAIL ⇒ ≥1 new/drift BLOCKING|HIGH (capped drift was rejected in (j))
    if decision == "FAIL" and not any(
            cat in ("new", "drift") and sev in BLOCKING_SEVERITIES for sev, cat in pairs):
        emit(False, "decision=FAIL requires at least one issue with category new or drift "
                    "and severity BLOCKING or HIGH (v3 rule k)")


MAIN_SESSION_FLAG = "--main-session"
# The frontmatter name is `loomwright:code-reviewer`; the runtime reports the
# plugin-doubled `loomwright:loomwright:code-reviewer` (both probed).
REVIEWER_AGENT_TYPE = re.compile(r"^(?:loomwright:){1,2}code-reviewer$")


def _main_session_stream(argv):
    """`--main-session` gate: return a replay stream of stdin when the session
    whose turn is ending IS the code-reviewer, else allow (`{}`) and exit.
    Identity is the payload's top-level `agent_type` ONLY — never
    `background_tasks[]`, never message content."""
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw)
    except ValueError:
        emit(True)
    agent_type = payload.get("agent_type") if isinstance(payload, dict) else None
    if not (isinstance(agent_type, str) and REVIEWER_AGENT_TYPE.match(agent_type)):
        emit(True)
    return io.StringIO(raw), [a for a in argv if a != MAIN_SESSION_FLAG]


def main():
    argv, stream = sys.argv[1:], None
    if MAIN_SESSION_FLAG in argv:
        stream, argv = _main_session_stream(argv)
    _name, fields, _text, _payload = load_block(BLOCK, MISSING_BLOCK, argv=argv, stream=stream)

    # ── schema_version ∈ {2, 3} ──────────────────────────────────────────────
    if not present(fields, "schema_version"):
        emit(False, "CODE_REVIEW_RESULT is missing the schema_version field")
    schema_version, bad_sv = as_int(fields.get("schema_version"))
    if schema_version == 1:
        emit(False, "schema_version 1 is no longer supported; upgrade to v3")
    if schema_version not in (2, 3):
        emit(False, "CODE_REVIEW_RESULT schema_version must be 2 or 3; got %s"
             % (bad_sv if schema_version is None else schema_version))

    # ── (A) decision enum ────────────────────────────────────────────────────
    if not present(fields, "decision"):
        emit(False, "CODE_REVIEW_RESULT is missing the decision field (rule A)")
    decision = as_text(fields.get("decision")).strip()
    if decision not in VALID_DECISION:
        emit(False, "decision must be one of PASS, FAIL, or NEEDS_HUMAN; got %r (rule A)"
             % decision)

    # ── (B) summary present ──────────────────────────────────────────────────
    if not present(fields, "summary"):
        emit(False, "CODE_REVIEW_RESULT is missing the summary field (rule B)")
    if is_empty_scalar(fields.get("summary")):
        emit(False, "CODE_REVIEW_RESULT summary is present but empty or null (rule B)")

    if schema_version == 2:
        _check_v2(fields, decision)
    else:
        _check_v3(fields, decision)

    emit(True)


if __name__ == "__main__":
    run_validator(main)
