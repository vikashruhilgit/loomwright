#!/usr/bin/env python3
"""validate-verify-evidence.py — line/file validator for VERIFY_EVIDENCE v1.

Validates one JSONL record (`--line '<json>'`) or every record of a file
(`<file>`) against docs/RESULT_SCHEMAS.md §VERIFY_EVIDENCE — the append-only
`.supervisor/verify/<run_id>/evidence.jsonl` store that `/verify` writes one
fact at a time. Schema authority is that section; the enum constants below are
its transcription, and the seam test (test-verify-evidence.sh) greps both for
the same tokens so the two surfaces cannot drift apart silently.

DELIBERATE DEVIATION FROM THE SIBLING VALIDATORS — THE EXIT STATUS IS THE GATE.
Every other `validate-*.py` here is a SubagentStop hook EMITTER: it must ALWAYS
exit 0 and put its decision on stdout only, because a non-zero hook exit would
be masked by `|| true` and a crash would silently disable the gate. This
script is NOT a hook. It is a CLI GATE consumed by `verify-helpers.sh
evidence-append`, which appends the record only when this process exits 0, so
the exit status IS the decision and a swallowed status would let an invalid
fact into the store (the QA lane's `coverage.json` failure mode). Hence:

  exit 0  valid       stdout `{"ok": true}`
  exit 1  invalid     stdout `{"ok": false, "reason": "<code>", "line": <n|null>}`
                      (`line` is the 1-based PHYSICAL line number in file mode,
                      null in `--line` mode; blank lines are skipped but still
                      counted, so the number is the one `sed -n Np` would use)
  exit 2  usage / unreadable input — nothing on stdout, message on stderr

It also does NOT import `result_block_parser` (that module parses YAML result
blocks; these are JSON lines) — stdlib `json` / `re` / `sys` only. No
third-party imports, ever.

REASON CODES (snake_case, grep-stable; this list IS the contract — the seam test
provokes every one of them and asserts nothing outside this set is emitted):

  not_json                   the line is not parseable JSON
  not_object                 parsed, but the root is not an object
  schema_version_mismatch    `schema_version` absent, or not the integer 1
                             (a JSON `true` is NOT 1 here)
  missing_key:<k>            a required key is absent — the common keys on every
                             line, the per-event keys, AND the conditionally
                             required ones: `env.reason` when `outcome` is
                             `fail`, `pause`/`resume` `reason` (absent, null or
                             empty string all report missing_key:reason)
  bad_type:<k>               a present key has the wrong JSON type or shape —
                             includes `ts` not `YYYY-MM-DDTHH:MM:SS[.fff]Z`,
                             `run_id` not starting with `verify-`, an
                             `artifacts[]` entry that is not a relative path
                             (empty, absolute, `~`-anchored, or carrying a
                             `..` segment that would escape `<run_dir>/`)
  unknown_event              `event` is a string outside the event enum
  unknown_verdict            `ac.verdict` is a string outside the verdict enum
  unknown_enum:<k>           any OTHER enum field holds a value outside its enum
                             (ticket_kind, step, outcome, state, scope,
                             classification, severity, status)
  non_pass_without_reason    an `ac` line whose verdict is not PASS and whose
                             `reason` is absent, null or empty
  missing_classification     an `ac` line with verdict FAIL or BLOCKED and no
                             (or null) `classification`
  classification_on_pass     an `ac` line with verdict PASS or NOT_VERIFIABLE
                             carrying a non-null `classification`
  run_end_carries_counts     a `run_end` line with a `counts` or `totals` key at
                             ANY depth (counts exist only in the derived
                             summary; a fact line can never carry a total)

Check order within a line is fixed (parse → object → schema_version → common
keys → event → per-event), so a line with several defects reports the first in
that order, deterministically.

Unknown additive keys are TOLERATED on every event (forward-compat) — the only
forbidden keys are `counts` / `totals` on `run_end`.
"""

import json
import re
import sys

SCHEMA_VERSION = 1

EVENTS = ("run_start", "env", "auth", "ac", "issue", "pause", "resume", "run_end", "impact_surfaces",
          "spec_replay", "spec_rederived")
TICKET_KINDS = ("requirement", "brief")
ENV_STEPS = ("non_prod_assert", "start", "health", "seed", "reset", "stop")
ENV_OUTCOMES = ("pass", "fail", "skipped")
AUTH_STATES = ("authenticated", "anonymous", "needs_auth", "expired")
AC_SCOPES = ("ticket", "impact")
VERDICTS = ("PASS", "FAIL", "BLOCKED", "NOT_VERIFIABLE")
CLASSIFICATIONS = ("REAL_BUG", "DISCOVERY_GAP", "ENVIRONMENT_ISSUE")
SEVERITIES = ("BLOCKING", "HIGH", "MEDIUM", "LOW")
RUN_END_STATUSES = ("completed", "aborted")

# Verdicts that MUST carry a classification / MUST NOT carry one.
CLASSIFIED_VERDICTS = ("FAIL", "BLOCKED")
UNCLASSIFIED_VERDICTS = ("PASS", "NOT_VERIFIABLE")

FORBIDDEN_RUN_END_KEYS = ("counts", "totals")
RUN_ID_PREFIX = "verify-"
TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$")

EXIT_VALID = 0
EXIT_INVALID = 1
EXIT_USAGE = 2

USAGE = (
    "usage: validate-verify-evidence.py --line '<json>'\n"
    "       validate-verify-evidence.py <evidence.jsonl>\n"
    "exit 0 valid · 1 invalid (JSON reason on stdout) · 2 usage/unreadable input\n"
)


class Invalid(Exception):
    """Raised with the reason code as its single argument."""


def fail(reason):
    raise Invalid(reason)


# --- type helpers -----------------------------------------------------------
# JSON `true`/`false` decode to bool, which is an int subclass in Python — every
# integer check below excludes bool explicitly so `"schema_version": true` is a
# mismatch, not a match.


def is_str(v):
    return isinstance(v, str)


def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def is_nonempty_str(v):
    return isinstance(v, str) and v != ""


def require(rec, key):
    if key not in rec:
        fail("missing_key:%s" % key)
    return rec[key]


def require_str(rec, key):
    v = require(rec, key)
    if not is_str(v):
        fail("bad_type:%s" % key)
    return v


def require_nonempty_reason(rec):
    """`reason` required non-empty: absent, null and "" are all missing_key;
    any other non-string type is bad_type."""
    v = rec.get("reason")
    if v is None or v == "":
        fail("missing_key:reason")
    if not is_str(v):
        fail("bad_type:reason")
    return v


def require_enum(rec, key, allowed):
    v = require_str(rec, key)
    if v not in allowed:
        fail("unknown_enum:%s" % key)
    return v


def optional_str(rec, key):
    if key in rec and rec[key] is not None and not is_str(rec[key]):
        fail("bad_type:%s" % key)


def is_relative_path(item):
    """A path RELATIVE to <run_dir>/ that stays inside it: non-empty, not
    absolute, not home-anchored, and no `..` segment anywhere (a leading
    `../x` and an interior `a/../b` both escape the run dir)."""
    if item == "" or item.startswith("/") or item.startswith("~"):
        return False
    return ".." not in item.split("/")


def check_str_array(rec, key, relative_paths=False):
    v = rec[key]
    if not isinstance(v, list):
        fail("bad_type:%s" % key)
    for item in v:
        if not is_str(item):
            fail("bad_type:%s" % key)
        if relative_paths and not is_relative_path(item):
            fail("bad_type:%s" % key)


def carries_forbidden_key(node):
    """True when `counts` / `totals` appears as a key at ANY depth (objects
    nested in objects or arrays included)."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k in FORBIDDEN_RUN_END_KEYS:
                return True
            if carries_forbidden_key(v):
                return True
    elif isinstance(node, list):
        for v in node:
            if carries_forbidden_key(v):
                return True
    return False


# --- per-event checks -------------------------------------------------------


def check_run_start(rec):
    require_str(rec, "ticket_path")
    require_enum(rec, "ticket_kind", TICKET_KINDS)
    require_str(rec, "branch")
    require_str(rec, "head_sha")
    require_str(rec, "base_sha")
    h = require(rec, "env_contract_hash")  # required KEY, nullable VALUE
    if h is not None and not is_str(h):
        fail("bad_type:env_contract_hash")


def check_env(rec):
    require_enum(rec, "step", ENV_STEPS)
    outcome = require_enum(rec, "outcome", ENV_OUTCOMES)
    if outcome == "fail":
        require_nonempty_reason(rec)
    else:
        optional_str(rec, "reason")


def check_auth(rec):
    require_enum(rec, "state", AUTH_STATES)


def check_ac(rec):
    ac_id = require_str(rec, "ac_id")
    if ac_id == "":
        fail("bad_type:ac_id")
    require_str(rec, "text")
    require_enum(rec, "scope", AC_SCOPES)
    verdict = require_str(rec, "verdict")
    if verdict not in VERDICTS:
        fail("unknown_verdict")
    require(rec, "steps")
    check_str_array(rec, "steps")
    require(rec, "artifacts")
    check_str_array(rec, "artifacts", relative_paths=True)
    if "surfaces" in rec and rec["surfaces"] is not None:
        check_str_array(rec, "surfaces")
    optional_str(rec, "reason")
    if verdict != "PASS" and not is_nonempty_str(rec.get("reason")):
        fail("non_pass_without_reason")
    classification = rec.get("classification")
    if verdict in CLASSIFIED_VERDICTS:
        if classification is None:
            fail("missing_classification")
        if not is_str(classification):
            fail("bad_type:classification")
        if classification not in CLASSIFICATIONS:
            fail("unknown_enum:classification")
    elif verdict in UNCLASSIFIED_VERDICTS and classification is not None:
        fail("classification_on_pass")


def check_issue(rec):
    require_str(rec, "text")
    require_enum(rec, "severity", SEVERITIES)
    optional_str(rec, "route")
    if "artifacts" in rec and rec["artifacts"] is not None:
        check_str_array(rec, "artifacts", relative_paths=True)


def check_pause_resume(rec):
    require_nonempty_reason(rec)


def check_run_end(rec):
    if carries_forbidden_key(rec):
        fail("run_end_carries_counts")
    require_enum(rec, "status", RUN_END_STATUSES)


def check_impact_surfaces(rec):
    """One line per run, item 06: the diff->surfaces classification the impact pass records.
    `surfaces` maps a surface name to the files (from the diff) classified into it - an empty
    mapping is legal (nothing classified yet); `unmapped` names diff files no surface claimed;
    `brief_surfaces` names subsystems sourced from a done brief's Blast-Radius section (may be
    empty - the common case, per the owning brief's Risk Assessment); `limit` is the
    --impact-limit bound the prior-AC regression pass used."""
    require(rec, "files")
    check_str_array(rec, "files")
    surfaces = require(rec, "surfaces")
    if not isinstance(surfaces, dict):
        fail("bad_type:surfaces")
    for k, v in surfaces.items():
        if not is_str(k) or not isinstance(v, list) or not all(is_str(x) for x in v):
            fail("bad_type:surfaces")
    require(rec, "unmapped")
    check_str_array(rec, "unmapped")
    require(rec, "brief_surfaces")
    check_str_array(rec, "brief_surfaces")
    limit = require(rec, "limit")
    if not is_int(limit) or limit < 0:
        fail("bad_type:limit")


def check_spec_replay(rec):
    """One line per replayed spec, token-economy 07: `verify-run.sh spec-replay` copied a prior
    run's `specs/<ac_id>.spec.ts` into this run byte-for-byte. `ac_id` / `source_run_id` / `text_sha`
    are non-empty strings; `churn_files` is a required KEY / nullable VALUE (int >= 0, or null when
    the source run's ac line carried no `surfaces` — never a missing key, per the
    nullable-required-field-needs-presence-check lesson)."""
    ac_id = require_str(rec, "ac_id")
    if ac_id == "":
        fail("bad_type:ac_id")
    source_run_id = require_str(rec, "source_run_id")
    if source_run_id == "":
        fail("bad_type:source_run_id")
    text_sha = require_str(rec, "text_sha")
    if text_sha == "":
        fail("bad_type:text_sha")
    churn = require(rec, "churn_files")  # required KEY, nullable VALUE
    if churn is not None and not (is_int(churn) and churn >= 0):
        fail("bad_type:churn_files")


def check_spec_rederived(rec):
    """One line per re-derivation, token-economy 07: a replayed spec that was BLOCKED for a harness
    reason was re-authored, at most once per ac_id per run. `ac_id` and `reason` are non-empty
    strings (a genuine assertion FAIL is never re-derived and never reaches this event)."""
    ac_id = require_str(rec, "ac_id")
    if ac_id == "":
        fail("bad_type:ac_id")
    require_nonempty_reason(rec)


EVENT_CHECKS = {
    "run_start": check_run_start,
    "env": check_env,
    "auth": check_auth,
    "ac": check_ac,
    "issue": check_issue,
    "pause": check_pause_resume,
    "resume": check_pause_resume,
    "run_end": check_run_end,
    "impact_surfaces": check_impact_surfaces,
    "spec_replay": check_spec_replay,
    "spec_rederived": check_spec_rederived,
}


# --- one record -------------------------------------------------------------


def validate_record(text):
    """Return None when valid, else the reason code string."""
    try:
        try:
            rec = json.loads(text)
        except (ValueError, TypeError, RecursionError):
            fail("not_json")
        if not isinstance(rec, dict):
            fail("not_object")
        sv = rec.get("schema_version")
        if not (is_int(sv) and sv == SCHEMA_VERSION):
            fail("schema_version_mismatch")
        ts = require_str(rec, "ts")
        if not TS_RE.match(ts):
            fail("bad_type:ts")
        run_id = require_str(rec, "run_id")
        if not run_id.startswith(RUN_ID_PREFIX):
            fail("bad_type:run_id")
        event = require_str(rec, "event")
        if event not in EVENTS:
            fail("unknown_event")
        EVENT_CHECKS[event](rec)
    except Invalid as exc:
        return exc.args[0]
    return None


# --- CLI --------------------------------------------------------------------


def emit(ok, reason=None, line=None):
    if ok:
        decision = {"ok": True}
    else:
        decision = {"ok": False, "reason": reason, "line": line}
    sys.stdout.write(json.dumps(decision, sort_keys=False) + "\n")
    sys.stdout.flush()


def usage_error(message):
    sys.stderr.write("validate-verify-evidence: %s\n%s" % (message, USAGE))
    return EXIT_USAGE


def run_line(text):
    reason = validate_record(text)
    if reason is None:
        emit(True)
        return EXIT_VALID
    emit(False, reason, None)
    return EXIT_INVALID


def run_file(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.read().split("\n")
    except (OSError, UnicodeDecodeError) as exc:
        return usage_error("cannot read %s: %s" % (path, exc))
    # A trailing newline yields one final empty element; it is blank and skipped
    # like any other blank line, so the physical numbering stays exact.
    for idx, raw in enumerate(lines, start=1):
        if raw.strip() == "":
            continue
        reason = validate_record(raw)
        if reason is not None:
            emit(False, reason, idx)
            return EXIT_INVALID
    emit(True)
    return EXIT_VALID


def main(argv):
    args = argv[1:]
    if not args:
        return usage_error("no input")
    if args[0] == "--line":
        if len(args) != 2:
            return usage_error("--line takes exactly one JSON argument")
        return run_line(args[1])
    if len(args) != 1:
        return usage_error("expected exactly one file path")
    if args[0].startswith("-"):
        return usage_error("unknown option %s" % args[0])
    return run_file(args[0])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
