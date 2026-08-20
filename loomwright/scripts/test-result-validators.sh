#!/usr/bin/env bash
# test-result-validators.sh — self-tests for result_block_parser.py and the five
# per-schema validators that replace the mechanical `type: prompt` SubagentStop
# hooks (Fix 4 / 4e, Subtask 1).
#
# DETERMINISTIC, NO LIVE SIDE EFFECTS. Every case pipes a synthesized
# SubagentStop payload into a validator and asserts on its stdout JSON and its
# exit code. Committed fixtures live in result-validator-fixtures/; negative
# variants are synthesized in-harness so each one reads next to the rule it
# falsifies.
#
# FALSIFY, DO NOT CONFIRM (AC-4). Per schema the suite covers, at minimum:
#   * a valid block                     -> ok:true
#   * a MISSING block                   -> ok:false  (a real finding)
#   * a malformed/unparseable payload   -> ok:TRUE   (hook plumbing broken; we
#                                          cannot validate and must not break
#                                          the agent loop)
#   * a malformed BLOCK body            -> ok:false  (explicit parse failure —
#                                          never a silent coercion)
#   * a MISSING required key            -> ok:false
#   * an EXPLICIT-NULL required key     -> ok:false, with a DIFFERENT reason
#                                          from the missing-key case (the
#                                          nullable-vs-absent lesson: presence
#                                          and truthiness are different tests)
#   * >= 1 cross-field invariant violation
#
# Plus, for every one of the six Python files, the exit-0-by-contract check on
# garbage and on empty stdin (R3: a validator that exits non-zero under
# `|| true` is a silently dead validator).
#
# STYLE NOTE: heredocs are never nested inside $( ) here — bash mis-parses that
# combination. Fixtures are written with `mk <name>` (sets $F) and consumed on
# the following line.
#
# EXIT: 0 on full pass, 1 on any failed assertion.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXDIR="$SCRIPT_DIR/result-validator-fixtures"

PARSER="$SCRIPT_DIR/result_block_parser.py"
V_WORKER="$SCRIPT_DIR/validate-worker-result.py"
V_EXECUTE="$SCRIPT_DIR/validate-execute-result.py"
V_SUPERVISOR="$SCRIPT_DIR/validate-supervisor-result.py"
V_PLAN="$SCRIPT_DIR/validate-plan-review-result.py"

ALL_PY="$PARSER $V_WORKER $V_EXECUTE $V_SUPERVISOR $V_PLAN"

for f in $ALL_PY "$FIXDIR/worker-valid-bullet.md" "$FIXDIR/worker-valid-yaml.md" \
         "$FIXDIR/execute-result-valid.md" "$FIXDIR/execute-checkpoint-valid.md" \
         "$FIXDIR/supervisor-valid.md" \
         "$FIXDIR/plan-review-valid.md" "$FIXDIR/subagentstop-payload.json"; do
  if [ ! -e "$f" ]; then
    echo "FATAL  required file not found: $f" >&2
    exit 1
  fi
done
if ! command -v python3 >/dev/null 2>&1; then
  echo "FATAL  python3 required to run this suite" >&2
  exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0
ok() { echo "  ok: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
no() { echo "  FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TMPROOT="$(mktemp -d)"
cleanup() { rm -rf "$TMPROOT" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# SANDBOX is the cwd every validator runs in: an empty dir carrying a
# .worker-summary.md so the worker validator's strongest (on-disk) rule-3 tier
# is the one under test, not the transcript-evidence fallback.
#
# The file carries a REALISTIC WORKER_SUMMARY body naming its task. Rule 3's
# tier 1 is task-scoped by content (the file name is task-agnostic by
# contract), so an EMPTY file would no longer satisfy it — that is the point:
# a stale `.worker-summary.md` must not vouch for a later, unrelated worker.
# Two sandboxes because the committed fixtures and the synthesized blocks use
# different task_ids.
write_summary() {  # write_summary <dir> <task_id>
  mkdir -p "$1"
  cat > "$1/.worker-summary.md" <<EOF
## WORKER_SUMMARY
- subtask_id: $2
- status: completed
- files_modified: [a.py]
- notes: harness fixture summary for $2
EOF
}

SANDBOX="$TMPROOT/sandbox"
write_summary "$SANDBOX" "st1"

# The committed worker fixtures use task_id add-jwt-guard.
SANDBOX_JWT="$TMPROOT/sandbox-jwt"
write_summary "$SANDBOX_JWT" "add-jwt-guard"

# STALE carries someone ELSE's summary file — the finding-6a scenario.
STALE="$TMPROOT/stale"
write_summary "$STALE" "some-other-subtask"

# BARE is a cwd with NO summary-file evidence at all (rule 3 negative case).
BARE="$TMPROOT/bare"
mkdir -p "$BARE"

GARBAGE="$TMPROOT/garbage.txt"
printf 'not { valid json at all' > "$GARBAGE"

# ── helpers ──────────────────────────────────────────────────────────────────

F=""
# mk <name> — read a heredoc from stdin into $TMPROOT/<name>; sets $F.
mk() { F="$TMPROOT/$1"; cat > "$F"; }

# cat_mk <name> <base-file> — base file + heredoc from stdin; sets $F.
cat_mk() { F="$TMPROOT/$1"; { cat "$TMPROOT/$2"; cat; } > "$F"; }

# text_payload <textfile> — wrap agent output text in a realistic SubagentStop
# payload (the `last_assistant_message` rung of the extraction ladder).
text_payload() {
  python3 -c 'import json,sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    text = fh.read()
sys.stdout.write(json.dumps({
    "session_id": "test-result-validators",
    "hook_event_name": "SubagentStop",
    "agent_type": "test",
    "last_assistant_message": text,
}))' "$1"
}

LAST_OUT=""
LAST_RC=""

# run_v <validator> <textfile> [cwd] — run a validator over wrapped text.
#
# THE PAYLOAD IS MATERIALISED TO A FILE AND REDIRECTED, NEVER PIPED. Piping it
# made this helper intermittently report a FALSE failure, and the mechanism is
# worth recording because it looks like a validator bug and is not:
# the import-guard paths (sections J's ABSENT / CORRUPT module cases) fail
# before any stdin read and `os._exit(0)` immediately, so the writing process
# gets EPIPE on a payload larger than the pipe buffer, dies with rc 1/120, and
# `set -o pipefail` promotes THAT to the pipeline's status. The validator's own
# verdict and exit code were correct every time; only the harness lied. Observed
# as a one-off `exit 120, expected 0` and reproduced deterministically at a
# 200KB payload. A file redirect has no writer to break.
run_v() {
  local validator="$1" textfile="$2" wd="${3:-$SANDBOX}"
  text_payload "$textfile" > "$TMPROOT/.payload.json"
  LAST_OUT="$( ( cd "$wd" && python3 "$validator" < "$TMPROOT/.payload.json" ) 2>/dev/null)"
  LAST_RC=$?
}

# run_raw <validator> <stdin-file> [cwd] — feed a file straight to stdin
# (used for the garbage-payload cases, where the input is NOT valid JSON).
run_raw() {
  local validator="$1" stdinfile="$2" wd="${3:-$SANDBOX}"
  LAST_OUT="$( ( cd "$wd" && python3 "$validator" < "$stdinfile" ) 2>/dev/null)"
  LAST_RC=$?
}

# text_payload_cwd <textfile> <cwd> — like text_payload, but carrying the
# payload's own `cwd` field, which is what the validators treat as the
# authoritative project root.
text_payload_cwd() {
  python3 -c 'import json,sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    text = fh.read()
sys.stdout.write(json.dumps({
    "session_id": "test-result-validators",
    "hook_event_name": "SubagentStop",
    "agent_type": "test",
    "cwd": sys.argv[2],
    "last_assistant_message": text,
}))' "$1" "$2"
}

# run_v_cwd <validator> <textfile> <payload_cwd> <process_cwd> — the two cwds
# are deliberately independent: the hook PROCESS can run anywhere, and the
# payload states where the project actually is.
run_v_cwd() {
  local validator="$1" textfile="$2" pcwd="$3" wd="$4"
  # File-redirected, not piped — see run_v for the EPIPE/pipefail reason.
  text_payload_cwd "$textfile" "$pcwd" > "$TMPROOT/.payload.json"
  LAST_OUT="$( ( cd "$wd" && python3 "$validator" < "$TMPROOT/.payload.json" ) 2>/dev/null)"
  LAST_RC=$?
}

json_ok() {
  printf '%s' "$LAST_OUT" | python3 -c 'import json,sys
try:
    print("true" if json.load(sys.stdin).get("ok") is True else "false")
except Exception:
    print("PARSE_ERROR")'
}

json_reason() {
  printf '%s' "$LAST_OUT" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("reason", ""))
except Exception:
    print("")'
}

# assert_pass <label> — the last run decided ok:true and exited 0.
assert_pass() {
  local label="$1"
  if [ "$LAST_RC" != "0" ]; then
    no "$label  (exit $LAST_RC, expected 0)"
    return
  fi
  if [ "$(json_ok)" = "true" ]; then
    ok "$label"
  else
    no "$label  expected ok:true, got: $LAST_OUT"
  fi
}

# assert_fail <label> [reason-substring] — ok:false, exit 0, reason matches.
assert_fail() {
  local label="$1" needle="${2:-}" reason
  if [ "$LAST_RC" != "0" ]; then
    no "$label  (exit $LAST_RC, expected 0 — validators are exit-0-by-contract)"
    return
  fi
  if [ "$(json_ok)" != "false" ]; then
    no "$label  expected ok:false, got: $LAST_OUT"
    return
  fi
  if [ -n "$needle" ]; then
    reason="$(json_reason)"
    case "$reason" in
      *"$needle"*) ok "$label" ;;
      *) no "$label  reason did not mention '$needle'; got: $reason" ;;
    esac
  else
    ok "$label"
  fi
}

# ── A. shared parser unit tests ──────────────────────────────────────────────
echo "== A. result_block_parser.py — parse subset, nulls, last-block-wins =="

PARSER_TESTS="$TMPROOT/parser_tests.py"
cat > "$PARSER_TESTS" <<'PYEOF'
import io
import json
import sys

sys.path.insert(0, sys.argv[1])
import result_block_parser as R


_CHECKS = [0]


def check(label, cond):
    _CHECKS[0] += 1
    print(("PASS " if cond else "FAIL ") + label)


def emit_trailer():
    """Print the self-declared check count as the LAST line of this harness.

    THE HARNESS USED TO LOSE CASES SILENTLY. This whole file is one python
    script whose stdout a bash `case` consumes, matching only `PASS `/`FAIL `
    prefixes. An exception anywhere aborts the script, every later check() call
    emits nothing at all, and the traceback matches neither prefix — so cases
    VANISHED rather than failing, and nothing compared the number that arrived
    against the number that should have. Measured: three checks disappeared
    (290 -> 287) while the suite still reported fail=0 and exited 0.

    That matters more here than it would in an ordinary suite: no converted hook
    has been observed FIRING (the installed plugin is a copy, not a symlink), so
    this suite is the change's ONLY evidence. Evidence that can quietly shrink
    is not evidence.

    The fix is a trailer the bash side REQUIRES. Its absence is itself a
    failure, so a mid-script crash can no longer read as a clean run.
    """
    print("CHECKS %d" % _CHECKS[0])


# --- the five YAML null spellings, all PRESENT-but-null ----------------------
block = "\n".join([
    "X_RESULT:",
    "  a: null",
    "  b: Null",
    "  c: NULL",
    "  d: ~",
    "  e:",
])
fields, errors = R.parse_block(block)
check("five null spellings parse without error", errors == [])
for key in "abcde":
    check("null spelling %r -> present and null" % key,
          key in fields and fields[key] is None)

# --- quoted "null" is the STRING, not the null value -------------------------
fields, errors = R.parse_block('X_RESULT:\n  q: "null"\n  s: \'null\'\n  e: ""')
check("quoted null literals parse cleanly", errors == [])
check('double-quoted "null" is the string "null"', fields.get("q") == "null")
check("single-quoted 'null' is the string \"null\"", fields.get("s") == "null")
check('empty quoted string is "" and NOT null',
      fields.get("e") == "" and fields["e"] is not None)

# --- presence vs null vs absent are three distinct outcomes ------------------
fields, _ = R.parse_block("X_RESULT:\n  present_null:\n  present_value: 3")
check("present-but-null: key in fields", R.present(fields, "present_null"))
check("present-but-null: is_null true", R.is_null(fields, "present_null"))
check("absent key: not present", not R.present(fields, "absent_key"))
check("absent key: is_null false (NOT confusable with an explicit null)",
      not R.is_null(fields, "absent_key"))

# --- inline flow arrays ------------------------------------------------------
fields, errors = R.parse_block("X_RESULT:\n  files: [a.py, b.py]\n  empty: []")
check("flow array parses", errors == [] and fields.get("files") == ["a.py", "b.py"])
check("empty flow array is [] and not null", fields.get("empty") == [])

# --- block sequences ---------------------------------------------------------
fields, errors = R.parse_block(
    "X_RESULT:\n  merge_order:\n    - feature/a\n    - feature/b")
check("block sequence parses",
      errors == [] and fields.get("merge_order") == ["feature/a", "feature/b"])

# --- block SEQUENCE OF MAPPINGS ---------------------------------------------
block = "\n".join([
    "X_RESULT:",
    "  outputs_verified:",
    "    - kind: file",
    "      path: a.ts",
    "      status: present",
    "    - kind: symbol",
    "      path: a.ts",
    "      name: Foo",
    "      status: missing",
])
fields, errors = R.parse_block(block)
seq = fields.get("outputs_verified")
check("block sequence of mappings parses",
      errors == [] and isinstance(seq, list) and len(seq) == 2)
check("seq-of-mappings entry 0 shape",
      seq and seq[0] == {"kind": "file", "path": "a.ts", "status": "present"})
check("seq-of-mappings entry 1 carries the optional name",
      seq and seq[1].get("name") == "Foo" and seq[1].get("status") == "missing")

# --- FLOW sequence of mappings (the bullet-form outputs_verified shape) ------
fields, errors = R.parse_block(
    "X_RESULT:\n  outputs_verified: [{kind: file, path: a.ts, status: present}, "
    "{kind: type, path: b.ts, name: Bar, status: missing}]"
)
seq = fields.get("outputs_verified")
check("flow sequence of mappings parses",
      errors == [] and isinstance(seq, list) and len(seq) == 2)
check("flow seq-of-mappings entry 0", seq and seq[0].get("path") == "a.ts")
check("flow seq-of-mappings entry 1 name", seq and seq[1].get("name") == "Bar")

# --- nested block mapping ----------------------------------------------------
fields, errors = R.parse_block(
    "X_RESULT:\n  resume_context:\n    tool_calls_used: 58\n"
    "    feature_branch: feature/x")
check("nested block mapping parses",
      errors == [] and fields.get("resume_context", {}).get("feature_branch") == "feature/x")

# --- UNSUPPORTED constructs must be EXPLICIT failures, never coerced ---------
unsupported = [
    ("block scalar |", "X_RESULT:\n  summary: |\n    multi\n    line"),
    ("block scalar >", "X_RESULT:\n  summary: >\n    folded"),
    ("anchor", "X_RESULT:\n  a: &anchor value"),
    ("alias", "X_RESULT:\n  a: *anchor"),
    ("merge key", "X_RESULT:\n  <<: *base\n  a: 1"),
    ("tab indentation", "X_RESULT:\n\ta: 1"),
    ("unterminated flow sequence", "X_RESULT:\n  a: [1, 2"),
    ("unterminated flow mapping", "X_RESULT:\n  a: {k: v"),
    ("unterminated quote", 'X_RESULT:\n  a: "oops'),
    ("trailing junk after a flow collection", "X_RESULT:\n  a: [1, 2] junk"),
    ("missing space after colon", "X_RESULT:\n  a:1"),
    ("duplicate key", "X_RESULT:\n  a: 1\n  a: 2"),
    ("document marker", "X_RESULT:\n  ---"),
]
for label, text in unsupported:
    _, errs = R.parse_block(text)
    check("unsupported construct reported: %s" % label, errs != [])

# --- LAST block wins ---------------------------------------------------------
text = "X_RESULT:\n  a: first\n\nprose\n\nX_RESULT:\n  a: second\n"
fields, _ = R.parse_block(R.find_last_block(text, "X_RESULT"))
check("LAST block wins (yaml form)", fields.get("a") == "second")
text = "## X_RESULT\n- a: first\n\nprose\n\n## X_RESULT\n- a: second\n"
fields, _ = R.parse_block(R.find_last_block(text, "X_RESULT"))
check("LAST block wins (markdown bullet form)", fields.get("a") == "second")
check("find_last_block returns None when the block is absent",
      R.find_last_block("nothing here", "X_RESULT") is None)

# --- find_last_named_block picks the later of two alternatives ---------------
text = "A_RESULT:\n  a: 1\n\nB_RESULT:\n  b: 2\n"
name, _ = R.find_last_named_block(text, ("A_RESULT", "B_RESULT"))
check("find_last_named_block picks the LATER alternative", name == "B_RESULT")
text = "B_RESULT:\n  b: 2\n\nA_RESULT:\n  a: 1\n"
name, _ = R.find_last_named_block(text, ("A_RESULT", "B_RESULT"))
check("find_last_named_block is order-independent", name == "A_RESULT")

# --- payload extraction ladder ----------------------------------------------
def extract(payload, argv=None):
    return R.extract_payload_text(argv or [], io.StringIO(json.dumps(payload)))


check("ladder rung 1: last_assistant_message wins over result_block",
      extract({"last_assistant_message": "one", "result_block": "two"}) == "one")
check("ladder rung 2: result_block", extract({"result_block": "two"}) == "two")
check("ladder rung 3: output", extract({"output": "three"}) == "three")
check("ladder rung 4: agent_output", extract({"agent_output": "four"}) == "four")
check("ladder order matches the documented order",
      R.PAYLOAD_TEXT_KEYS == ("last_assistant_message", "result_block", "output",
                              "agent_output")
      and R.PAYLOAD_TRANSCRIPT_KEYS == ("agent_transcript_path", "transcript_path"))
check("no text field found -> empty string (a real finding, not a crash)",
      extract({"session_id": "x"}) == "")
check("non-JSON stdin -> PAYLOAD_UNPARSEABLE",
      R.extract_payload_text([], io.StringIO("not json at all"))
      is R.PAYLOAD_UNPARSEABLE)
check("JSON that is not an object -> PAYLOAD_UNPARSEABLE",
      R.extract_payload_text([], io.StringIO("[1,2,3]")) is R.PAYLOAD_UNPARSEABLE)
check("--raw mode: stdin IS the agent text",
      R.extract_payload_text(["--raw"], io.StringIO("## X_RESULT\n- a: 1"))
      == "## X_RESULT\n- a: 1")

# --- transcript fallback rungs ----------------------------------------------
import tempfile
tmpdir = tempfile.mkdtemp()
agent_tp = tmpdir + "/agent.jsonl"
session_tp = tmpdir + "/session.jsonl"
with open(agent_tp, "w") as fh:
    fh.write(json.dumps({"role": "assistant",
                         "message": {"role": "assistant",
                                     "content": [{"text": "from-agent-transcript"}]}}) + "\n")
with open(session_tp, "w") as fh:
    fh.write(json.dumps({"role": "assistant",
                         "message": {"role": "assistant",
                                     "content": [{"text": "from-session-transcript"}]}}) + "\n")
check("ladder rung 5: agent_transcript_path preferred over transcript_path",
      extract({"agent_transcript_path": agent_tp, "transcript_path": session_tp})
      == "from-agent-transcript")
check("ladder rung 6: transcript_path used when agent_transcript_path is absent",
      extract({"transcript_path": session_tp}) == "from-session-transcript")

# --- destructive-command scan: usage fires, prose does not -------------------
check("destructive scan: rm -rf in command position fires",
      R.find_destructive_command("$ rm -rf build/") == "rm -rf")
check("destructive scan: git push fires",
      R.find_destructive_command("git push origin x") == "git push")
check("destructive scan: git reset --hard fires",
      R.find_destructive_command("git reset --hard origin/main") == "git reset --hard")
check("destructive scan: DROP TABLE fires",
      R.find_destructive_command("DROP TABLE users;") == "DROP")
check("destructive scan: TRUNCATE fires",
      R.find_destructive_command("TRUNCATE TABLE audit;") == "TRUNCATE")
check("destructive scan: after && fires",
      R.find_destructive_command("cd /tmp && rm -rf x") == "rm -rf")
check("destructive scan: negated prose does NOT fire",
      R.find_destructive_command(
          "I did not run git push; no rm -rf was used.") is None)
check("destructive scan: the plugin's own rule text does NOT fire",
      R.find_destructive_command(
          "no destructive commands were used (rm -rf, git push, "
          "git reset --hard, DROP, TRUNCATE)") is None)
check("destructive scan: 'we drop the field' prose does NOT fire",
      R.find_destructive_command("We drop the field from the schema.") is None)
check("destructive scan: clean text is None",
      R.find_destructive_command("all good") is None)

# --- typed reads -------------------------------------------------------------
check("as_int accepts an integer literal", R.as_int("42")[0] == 42)
check("as_int accepts a negative literal", R.as_int("-1")[0] == -1)
check("as_int rejects a float literal", R.as_int("4.2")[0] is None)
check("as_int rejects a word", R.as_int("many")[0] is None)
check("as_int rejects null", R.as_int(None)[0] is None)
check("as_bool accepts true/True/TRUE",
      R.as_bool("true")[0] is True and R.as_bool("True")[0] is True
      and R.as_bool("TRUE")[0] is True)
check("as_bool accepts the false spellings", R.as_bool("FALSE")[0] is False)
check("as_bool rejects 'yes'", R.as_bool("yes")[0] is None)

# --- FINDING 3: a blank line INSIDE a block must not truncate it -------------
# Before the fix, strict blank-line termination produced MISLEADING verdicts:
# a SUPERVISOR_RESULT with one internal blank line reported "missing the
# heal_loop_ran field" when the field was present just past the break, and a
# `## WORKER_RESULT` heading followed by the conventional markdown blank line
# reported "missing block". Both emission shapes are asserted here.
text = "\n".join([
    "SUPERVISOR_RESULT:",
    "  schema_version: 1",
    "  status: completed",
    "  pr_url: https://example.invalid/pull/1",
    "",
    "  heal_loop_ran: false",
    "  summary: one internal blank line",
])
fields, errors = R.parse_block(R.find_last_block(text, "SUPERVISOR_RESULT"))
check("yaml form: an internal blank line does not truncate the block",
      errors == [] and R.present(fields, "heal_loop_ran")
      and fields.get("summary") == "one internal blank line")

blk = R.find_last_block(
    "## WORKER_RESULT\n\n- schema_version: 2\n- task_id: st1\n"
    "- summary: heading then the conventional markdown blank line\n",
    "WORKER_RESULT")
check("markdown form: heading + conventional blank line is still FOUND", blk is not None)
fields, errors = R.parse_block(blk) if blk else ({}, ["block not found"])
check("markdown form: heading + blank line parses every bullet",
      errors == [] and fields.get("task_id") == "st1")

# ...and the tolerance is BOUNDED: it must not over-read past the block.
fields, errors = R.parse_block(R.find_last_block(
    "SUPERVISOR_RESULT:\n  schema_version: 1\n  summary: done\n\n"
    "  This indented paragraph is prose, not a body line.\n", "SUPERVISOR_RESULT"))
check("yaml form: indented trailing PROSE after a blank line is NOT swallowed",
      errors == [] and set(fields) == {"schema_version", "summary"})

fields, errors = R.parse_block(R.find_last_block(
    "## X_RESULT\n- a: 1\n\nNext steps:\n- run the tests\n", "X_RESULT"))
check("markdown form: a following unrelated bullet list is NOT swallowed",
      errors == [] and set(fields) == {"a"})

fields, _ = R.parse_block(R.find_last_block(
    "X_RESULT:\n  a: first\n\nX_RESULT:\n  a: second\n", "X_RESULT"))
check("blank-line tolerance still respects LAST-block-wins on adjacent blocks",
      fields.get("a") == "second")

# --- FINDING 4: non-negations must not disarm the destructive tripwire -------
# `check`, `scan`, `scanned`, `scanning`, `skip`, `skipped` and `blocked` are
# not negations, and `\bno\b` matched inside `no-op`. Each line below was a
# VERIFIED non-detection before the cue set was restricted.
must_fire = [
    ("rm -rf dist  # to check the build", "rm -rf"),
    ("rm -rf dist to scan for leftovers", "rm -rf"),
    ("$ git push origin feature/x  (skipped review)", "git push"),
    ("git reset --hard HEAD~1 in the no-op branch", "git reset --hard"),
    ("rm -rf build/  # blocked nothing", "rm -rf"),
    ("git push --force  # scanned the diff first", "git push"),
    ("DROP TABLE audit;  -- check with the DBA", "DROP"),
]
for line, label in must_fire:
    check("destructive scan FIRES despite a non-negation cue: %r" % line,
          R.find_destructive_command(line) == label)

# The cue must PRECEDE the match: this pair proves the filter is live AND that
# it is direction-scoped (the third line was suppressed before the fix).
check("destructive scan: a PRECEDING negation still suppresses",
      R.find_destructive_command("echo no; rm -rf dist") is None)
check("destructive scan: the same line without a cue fires",
      R.find_destructive_command("echo yes; rm -rf dist") == "rm -rf")
check("destructive scan: a cue that only FOLLOWS the match does not disarm it",
      R.find_destructive_command("echo yes; rm -rf dist  # not a drill") == "rm -rf")
check("destructive scan: 'no-op' does not read as the negation 'no'",
      R.find_destructive_command("echo x; rm -rf no-op/") == "rm -rf")

# --- FINDING 6c: bracketed plain scalars fail EXPLICITLY, with a fix named ---
_, errs = R.parse_block("X_RESULT:\n  summary: [WIP] refactored the guard")
check("bracketed plain scalar is an explicit failure naming the quoting fix",
      errs != [] and "quote it" in errs[0])
fields, errs = R.parse_block('X_RESULT:\n  summary: "[WIP] refactored the guard"')
check("quoting the bracketed prefix parses cleanly (the documented workaround)",
      errs == [] and fields.get("summary") == "[WIP] refactored the guard")
_, errs = R.parse_block("X_RESULT:\n  files_modified: [a.py, b.py")
check("a genuinely truncated flow array is STILL an error, not a fallback string",
      errs != [])

# --- FINDING 7: a trailing `#` comment must NOT be folded into the value -----
#
# THE DEFECT. `status: completed  # done` parsed to the STRING
# "completed  # done". Nothing reported it, because absorbing a comment is not
# a construct failure — every downstream `==` simply stopped matching. In
# validate-worker-result.py that silently disabled rules 2, 4 and 8 (all three
# are guarded by `status == "completed"`), so a block with no files, an
# unresolved error AND a non-empty outputs_gap answered ok:true. The other four
# validators, whose comparable fields are enum- or int-checked, instead
# REJECTED valid blocks. Fail-open on one side, spurious rejects on the other.
#
# HOW TO READ THE LABELS — this distinction is the evidence, not decoration:
#   [FALSIFIES] verified to FAIL against the pre-fix parser (HEAD 03b5535).
#   [CONTROL]   passes before AND after. Present to prove the fix did not
#               over-reach; on its own a control proves nothing.
# Each fail-open case is PAIRED with a comment-free control that was already
# rejected pre-fix, so the pair proves the block is non-conforming for reasons
# other than the comment and that the fix restored the rule, not the reason.

# [FALSIFIES] the reported bug, in both emission shapes.
fields, errors = R.parse_block("X_RESULT:\n  status: completed  # all good")
check("[FALSIFIES] plain scalar: a trailing comment is stripped, not absorbed",
      errors == [] and fields.get("status") == "completed")
fields, errors = R.parse_block(
    R.find_last_block("## X_RESULT\n- status: completed  # all good\n", "X_RESULT"))
check("[FALSIFIES] markdown bullet form: trailing comment stripped",
      errors == [] and fields.get("status") == "completed")
fields, errors = R.parse_block("X_RESULT:\n  n: 2\t# tab-separated comment")
check("[FALSIFIES] a TAB before the '#' also introduces a comment",
      errors == [] and fields.get("n") == "2")

# [CONTROL] quoted scalars are untouched — a '#' inside quotes is content.
fields, errors = R.parse_block('X_RESULT:\n  summary: "fixed the # parsing"')
check("[CONTROL] a '#' inside a double-quoted scalar is NOT stripped",
      errors == [] and fields.get("summary") == "fixed the # parsing")
fields, errors = R.parse_block("X_RESULT:\n  summary: 'fixed the # parsing'")
check("[CONTROL] a '#' inside a single-quoted scalar is NOT stripped",
      errors == [] and fields.get("summary") == "fixed the # parsing")
fields, errors = R.parse_block('X_RESULT:\n  summary: "a # b"  # real comment')
check("[CONTROL] quoted '#' survives while a REAL trailing comment is stripped",
      errors == [] and fields.get("summary") == "a # b")

# [CONTROL] no preceding whitespace => not a comment (the stated control).
fields, errors = R.parse_block("X_RESULT:\n  tag: v1#2")
check("[CONTROL] a '#' with no preceding whitespace stays part of the value",
      errors == [] and fields.get("tag") == "v1#2")

# FINDING 8a: a value that is ENTIRELY a comment reads as YAML null, in EVERY
# position. This flips two assertions that a previous revision shipped as
# [CONTROL]s, on a justification that measurement falsified — see the
# strip_comment docstring for the three demonstrated fail-opens (one per
# validator, each answering ok:true where the explicit-null control fires).
fields, errors = R.parse_block("X_RESULT:\n  color: #ff0000")
check("[FALSIFIES] a value that is ENTIRELY a comment is YAML null, PRESENT "
      "(was the '#ff0000' string, which satisfied every non-empty-string rule)",
      errors == [] and R.present(fields, "color") and fields.get("color") is None)
fields, errors = R.parse_block('X_RESULT:\n  color: "#ff0000"')
check("[CONTROL] QUOTING a '#'-leading value still yields the string — the "
      "documented escape for an emitter that really means one",
      errors == [] and fields.get("color") == "#ff0000")
fields, errors = R.parse_block(
    "X_RESULT:\n  files_modified:\n    - # nothing yet")
check("[FALSIFIES] a comment-only SEQUENCE ELEMENT is null, not a non-empty "
      "string — this one made WORKER_RESULT rule 2 pass on a block naming no file",
      errors == [] and fields.get("files_modified") == [None])
fields, errors = R.parse_block("X_RESULT:\n  files_modified: [# nothing yet]")
check("[FALSIFIES] same in FLOW element position",
      errors == [] and fields.get("files_modified") == [None])

# Flow collections. The TRAILING-comment case already worked (parse_value's
# tail check tolerated a leading '#'), so it is a control, not a bug fix — but
# a comment INSIDE the collection was absorbed into an element, which is the
# same defect one level down.
fields, errors = R.parse_block("X_RESULT:\n  files: [a.py, b.py]  # two files")
check("[CONTROL] flow sequence with a TRAILING comment already parsed cleanly",
      errors == [] and fields.get("files") == ["a.py", "b.py"])
fields, errors = R.parse_block("X_RESULT:\n  files: [a.py # first, b.py]")
check("[FALSIFIES] a comment INSIDE a flow sequence is an EXPLICIT failure "
      "(it eats the ']'), never an element carrying '# first'",
      errors != [] and "unterminated flow sequence" in errors[0])
fields, errors = R.parse_block(
    "X_RESULT:\n  outputs_verified: [{kind: file, path: a.ts  # the module, "
    "status: present}]")
check("[FALSIFIES] a comment inside a flow SEQ-OF-MAPPINGS is an explicit failure",
      errors != [] and "unterminated flow mapping" in errors[0])
fields, errors = R.parse_block('X_RESULT:\n  files: ["a # b", c]  # note')
check("[CONTROL] a quoted '#' inside a flow element survives the trailing strip",
      errors == [] and fields.get("files") == ["a # b", "c"])

# Block sequences — the plain-scalar path one level down. Both were absorbing.
fields, errors = R.parse_block(
    "X_RESULT:\n  merge_order:\n    - feature/a  # merged first\n    - feature/b")
check("[FALSIFIES] block sequence entry: trailing comment stripped",
      errors == [] and fields.get("merge_order") == ["feature/a", "feature/b"])
fields, errors = R.parse_block(
    "X_RESULT:\n  outputs_verified:\n    - kind: file  # the module\n"
    "      path: a.ts\n      status: present  # verified on disk")
seq = fields.get("outputs_verified")
check("[FALSIFIES] block sequence OF MAPPINGS: trailing comments stripped",
      errors == []
      and seq == [{"kind": "file", "path": "a.ts", "status": "present"}])

# A residual '#' can no longer masquerade as a comment. Pre-fix both of these
# were silently ACCEPTED (the tail checks tolerated any leading '#'), which
# contradicted the very rule the strip implements.
_, errors = R.parse_block('X_RESULT:\n  a: "abc"#note')
check("[FALSIFIES] '#' with no preceding whitespace after a quoted scalar is "
      "an explicit failure, not a silently accepted comment",
      errors != [] and "trailing content after quoted scalar" in errors[0])
_, errors = R.parse_block("X_RESULT:\n  a: [x, y]#note")
check("[FALSIFIES] '#' with no preceding whitespace after a flow collection is "
      "an explicit failure",
      errors != [] and "trailing content after flow collection" in errors[0])

# A key line carrying ONLY a comment. With a nested body this is ordinary YAML
# and pre-fix it produced a bogus 'unexpected indentation' error.
fields, errors = R.parse_block(
    "X_RESULT:\n  resume_context:  # carried forward\n    tool_calls_used: 58")
check("[FALSIFIES] a key line with only a comment, then a nested body, parses",
      errors == []
      and fields.get("resume_context") == {"tool_calls_used": "58"})
fields, errors = R.parse_block("X_RESULT:\n  a: # nothing to say\n  b: 1")
check("[FALSIFIES] a comment-only value with NO nested body is PRESENT-and-null, "
      "not the '# nothing to say' string (the reading that failed OPEN)",
      errors == [] and R.present(fields, "a") and fields.get("a") is None
      and fields.get("b") == "1")
fields, errors = R.parse_block("X_RESULT:\n  # a whole-line comment\n  a: 1")
check("[CONTROL] a whole-line comment inside a block is skipped, as before",
      errors == [] and set(fields) == {"a"})

# Guards on the tightened tail checks: the pre-existing explicit failures must
# still be explicit failures, and an unterminated quote must not be repaired.
_, errors = R.parse_block("X_RESULT:\n  a: [1, 2] junk")
check("[CONTROL] trailing junk after a flow collection is still an error",
      errors != [])
_, errors = R.parse_block('X_RESULT:\n  a: "oops # x')
check("[CONTROL] an unterminated quote is still reported, not silently closed "
      "by the comment strip",
      errors != [] and "unterminated quoted scalar" in errors[0])

# The cost of the fix, asserted so it can never change by accident: an
# UNQUOTED value that legitimately contains ' # ' IS truncated. That is real
# YAML and the reason emitters must quote such values. Labelled honestly — it
# also falsifies against the pre-fix parser, because it IS a behaviour change,
# not a control.
fields, errors = R.parse_block("X_RESULT:\n  summary: fixed the # parsing")
check("[FALSIFIES / DOCUMENTED LIMIT] an unquoted ' # ' truncates the value "
      "(quote it) — the accepted cost of honouring comments",
      errors == [] and fields.get("summary") == "fixed the")

# strip_comment as a unit (the helper is new, so there is no pre-fix baseline).
check("[NEW API] strip_comment is idempotent",
      R.strip_comment(R.strip_comment("a  # b")) == R.strip_comment("a  # b"))
check("[NEW API] strip_comment leaves a comment-free string identical",
      R.strip_comment("plain value") == "plain value")
check("[NEW API] strip_comment does not scan past an unterminated quote",
      R.strip_comment('"oops # x') == '"oops # x')

# --- FINDING 8b: COMMENT LINES vs BLOCK FRAMING ------------------------------
#
# THE DEFECT. `_tokenize` has always skipped whole-line `#` comments, but
# `find_last_block`'s framing predicates did not recognise one, so a comment
# inside a block TERMINATED it and every field past the comment was silently
# discarded. Fail-OPEN, not merely a diagnosis cost: any OPTIONAL field whose
# only failure mode is present-and-bad simply vanished and its rule never ran.
#
# LABELS ARE MEASURED, not asserted — each was run against the two prior parser
# revisions materialised from git. This distinction is the evidence:
#   [FALSIFIES @4f63dea]  fails against the CURRENTLY COMMITTED parser.
#   [CONTROL @4f63dea]    already correct there; falsifies against 03b5535
#                         (pre-framing-fix) and is kept so the earlier half of
#                         the fix cannot silently regress.
#   [CONTROL]             correct in all three revisions — a bound guard,
#                         proving the tolerance did not over-reach. On its own
#                         a control proves nothing.
#
# Measured matrix (fields recovered from `a: 1` + comment + `b: 2`):
#   case                    03b5535     4f63dea              now
#   md blank+comment        [a] silent  [a,b] + PARSE ERROR  [a,b] clean
#   md comment NO blank     [a] silent  [a] silent           [a,b] clean
#   yaml blank+comment      [a] silent  [a,b] clean          [a,b] clean
#   yaml comment NO blank   [a,b]       [a,b]                [a,b]

MD_BLANK = "## W_RESULT\n- a: 1\n\n# note from the worker\n- b: 2\n"
fields, errors = R.parse_block(R.find_last_block(MD_BLANK, "W_RESULT"))
check("[FALSIFIES @4f63dea] markdown form: blank line + comment + more bullets "
      "parses cleanly (was an explicit '# note ... is not a bullet' failure, "
      "which rejected a legitimately annotated block)",
      errors == [] and fields.get("a") == "1" and fields.get("b") == "2")

MD_NOBLANK = "## W_RESULT\n- a: 1\n# note from the worker\n- b: 2\n"
fields, errors = R.parse_block(R.find_last_block(MD_NOBLANK, "W_RESULT"))
check("[FALSIFIES @4f63dea] markdown form: comment with NO preceding blank line "
      "continues the block (was a SILENT truncation that dropped every later "
      "field and then blamed the emitter for omitting them)",
      errors == [] and fields.get("a") == "1" and fields.get("b") == "2")

YAML_BLANK = "W_RESULT:\n  a: 1\n\n  # note from the agent\n  b: 2\n"
fields, errors = R.parse_block(R.find_last_block(YAML_BLANK, "W_RESULT"))
check("[CONTROL @4f63dea] YAML form: blank line + comment + more fields "
      "(falsifies against 03b5535; guards the committed half of the fix)",
      errors == [] and fields.get("a") == "1" and fields.get("b") == "2")

YAML_NOBLANK = "W_RESULT:\n  a: 1\n  # note from the agent\n  b: 2\n"
fields, errors = R.parse_block(R.find_last_block(YAML_NOBLANK, "W_RESULT"))
check("[CONTROL] YAML form: comment with no blank line was always fine",
      errors == [] and fields.get("a") == "1" and fields.get("b") == "2")

# BOUND GUARDS. The tolerance must not reach into a FOLLOWING section. All four
# of these terminate the block in every revision; they are what makes the
# comment tolerance a bounded rule rather than a shape-only one.
fields, _ = R.parse_block(
    R.find_last_block("## W_RESULT\n- a: 1\n\n## Next steps\n- ship it now\n",
                      "W_RESULT"))
check("[CONTROL] a following '## Next steps' section whose bullets are PROSE "
      "still terminates the block (_is_kv_bullet is why)",
      set(fields) == {"a"})
fields, _ = R.parse_block(
    R.find_last_block("## W_RESULT\n- a: 1\n# c1\n# c2\n# c3\n# c4\n- b: 2\n",
                      "W_RESULT"))
check("[CONTROL] a comment run longer than _MAX_COMMENT_RUN terminates the block",
      set(fields) == {"a"})
fields, _ = R.parse_block(
    R.find_last_block("## W_RESULT\n- a: 1\n\n\n\n# note\n- b: 2\n", "W_RESULT"))
check("[CONTROL] a blank run longer than _MAX_BLANK_RUN terminates the block "
      "even when a comment follows",
      set(fields) == {"a"})
fields, _ = R.parse_block(
    R.find_last_block("## W_RESULT\n- a: 1\n# note\n- just a sentence\n",
                      "W_RESULT"))
check("[CONTROL] a comment resumed by a NON-'key: value' bullet terminates",
      set(fields) == {"a"})
block = R.find_last_block(
    "W_RESULT:\n  a: 1\n\n# dedented heading, not a body line\n  b: 2\n",
    "W_RESULT")
fields, _ = R.parse_block(block)
check("[CONTROL] YAML form: a comment DEDENTED to the header's own indent still "
      "terminates (the YAML form's bound is the indent rule, not a run cap)",
      set(fields) == {"a"})

# The tolerance can never MERGE two differently-named blocks, comment or not.
two = "W_RESULT:\n  a: 1\n\n# note\nOTHER_RESULT:\n  b: 2\n"
fields, _ = R.parse_block(R.find_last_block(two, "W_RESULT"))
check("[CONTROL] a comment cannot bridge into a DIFFERENT named block",
      set(fields) == {"a"})

emit_trailer()
PYEOF

# Consume the parser harness's output. Three guards, all added because the
# earlier loop could DISCARD cases (see emit_trailer above):
#   1. a line matching neither prefix goes to STDERR, not stdout — a traceback
#      must be loud, not a tidy "(parser harness) ..." note in the pass stream;
#   2. the `CHECKS n` trailer is REQUIRED, and n must equal the number of
#      PASS/FAIL lines actually consumed — a crash mid-script drops the trailer
#      and is reported as a failure instead of vanishing;
#   3. a non-zero exit from python3 is reported too.
PARSER_RESULTS="$(python3 "$PARSER_TESTS" "$SCRIPT_DIR" 2>&1)"
PARSER_RC=$?
PARSER_SEEN=0
PARSER_DECLARED=""
while IFS= read -r line; do
  case "$line" in
    "PASS "*) ok "${line#PASS }"; PARSER_SEEN=$((PARSER_SEEN + 1)) ;;
    "FAIL "*) no "${line#FAIL }"; PARSER_SEEN=$((PARSER_SEEN + 1)) ;;
    "CHECKS "*) PARSER_DECLARED="${line#CHECKS }" ;;
    *) [ -n "$line" ] && echo "  (parser harness, unrecognised output) $line" >&2 ;;
  esac
done <<< "$PARSER_RESULTS"

if [ "$PARSER_RC" != "0" ]; then
  no "parser harness exited $PARSER_RC (expected 0) — output above may be truncated"
fi
if [ -z "$PARSER_DECLARED" ]; then
  no "parser harness emitted no CHECKS trailer — it aborted part-way and its later cases were LOST (see the traceback on stderr)"
elif [ "$PARSER_DECLARED" != "$PARSER_SEEN" ]; then
  no "parser harness declared $PARSER_DECLARED checks but $PARSER_SEEN reached the harness — cases were lost in transit"
else
  ok "parser harness case accounting: $PARSER_SEEN/$PARSER_DECLARED cases arrived (no silent loss)"
fi

# ── B. worker validator ──────────────────────────────────────────────────────
echo "== B. validate-worker-result.py — 8 rules =="

run_v "$V_WORKER" "$FIXDIR/worker-valid-bullet.md" "$SANDBOX_JWT"
assert_pass "worker: valid markdown-bullet block (committed fixture)"

run_v "$V_WORKER" "$FIXDIR/worker-valid-yaml.md" "$SANDBOX_JWT"
assert_pass "worker: valid YAML-form block, status partial with a non-empty outputs_gap"

mk worker-no-block.md <<'EOF'
I finished the subtask and everything looks fine, but I forgot the result block.
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: MISSING block" "missing WORKER_RESULT block"

run_raw "$V_WORKER" "$GARBAGE"
assert_pass "worker: malformed (non-JSON) payload -> ok:true, never break the agent loop"

mk worker-malformed-block.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py, b.py
- outputs_verified: []
- outputs_gap: ""
- summary: broken flow sequence above
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: malformed BLOCK body -> explicit parse failure" "could not be parsed"

mk worker-missing-key.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_verified: []
- outputs_gap: ""
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: MISSING required key (summary) [rule 1]" "missing required field(s): summary"

mk worker-null-key.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_verified: []
- outputs_gap: ""
- summary:
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: EXPLICIT-NULL required key (summary:) [rule 1]" "must be a non-empty string"

mk worker-no-files.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: []
- files_created: []
- outputs_verified: []
- outputs_gap: ""
- summary: claims completion but touched nothing
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: status=completed with empty files_modified AND files_created [rule 2]" "(rule 2)"

run_v "$V_WORKER" "$FIXDIR/worker-valid-bullet.md" "$BARE"
assert_fail "worker: no .worker-summary.md and no degradation marker [rule 3]" "(rule 3)"

mk worker-marker.md <<'EOF'
Could not write the summary file (read-only worktree): summary_file_write_failed

## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_verified: []
- outputs_gap: ""
- summary: summary_file_write_failed recorded in place of the summary file
EOF
run_v "$V_WORKER" "$F" "$BARE"
assert_pass "worker: summary_file_write_failed marker accepted in lieu of the file [rule 3]"

mk worker-unresolved-error.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_verified: []
- outputs_gap: ""
- error: the migration step still throws on startup
- summary: mostly done
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: status=completed with an unresolved error [rule 4]" "(rule 4)"

mk worker-failed-no-error.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: failed
- files_modified: []
- outputs_verified: []
- outputs_gap: ""
- summary: it did not work
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: status=failed with no error field [rule 4]" "(rule 4)"

mk worker-destructive.md <<'EOF'
Cleaning the tree before handing off:

    $ git reset --hard origin/main

## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_verified: []
- outputs_gap: ""
- summary: reset the tree
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: destructive command in the run output [rule 5]" "(rule 5)"

mk worker-v2-missing-gap.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_verified: []
- summary: outputs_gap is absent
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: v2 without outputs_gap [rule 6, verbatim reason]" \
  "WORKER_RESULT schema_version>=2 requires outputs_verified (array) and outputs_gap (string) fields"

mk worker-v2-missing-verified.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_gap: ""
- summary: outputs_verified is absent
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: v2 without outputs_verified [rule 6, verbatim reason]" \
  "WORKER_RESULT schema_version>=2 requires outputs_verified (array) and outputs_gap (string) fields"

mk worker-v1.md <<'EOF'
## WORKER_RESULT
- schema_version: 1
- task_id: st1
- status: completed
- files_modified: [a.py]
- summary: legacy v1 emission, accepted for the transition window
EOF
run_v "$V_WORKER" "$F"
assert_pass "worker: v1 block exempt from the v2 outputs contract [rule 6]"

mk worker-bad-entry.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_verified: [{kind: file, status: present}]
- outputs_gap: ""
- summary: the entry has no path
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: outputs_verified entry missing path [rule 7, verbatim reason]" \
  "outputs_verified entries must include {kind, path, status}"

mk worker-bad-kind.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_verified: [{kind: module, path: a.py, status: present}]
- outputs_gap: ""
- summary: kind is out of enum
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: outputs_verified kind out of enum [rule 7]" \
  "outputs_verified entries must include {kind, path, status}"

mk worker-bad-entry-status.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_verified: [{kind: file, path: a.py, status: verified}]
- outputs_gap: ""
- summary: entry status is out of enum
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: outputs_verified entry status out of enum [rule 7]" \
  "outputs_verified entries must include {kind, path, status}"

mk worker-gap-invariant.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_verified: [{kind: file, path: b.py, status: missing}]
- outputs_gap: "b.py"
- summary: claims completed while an output is missing
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: CROSS-FIELD outputs_gap non-empty + status completed [rule 8, verbatim]" \
  "outputs_gap non-empty must map to status: partial"

mk worker-gap-partial.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: partial
- files_modified: [a.py]
- outputs_verified: [{kind: file, path: b.py, status: missing}]
- outputs_gap: "b.py"
- summary: correctly reports partial alongside a non-empty gap
EOF
run_v "$V_WORKER" "$F"
assert_pass "worker: non-empty outputs_gap with status partial is the VALID shape [rule 8]"

# --- FINDING 2: present-but-null on the v12 contract fails OPEN -------------
# `outputs_verified: null` was coerced to [], so rule 7's entry-shape checks
# never ran; `outputs_gap: null` satisfied "(string)" and short-circuited rule
# 8's cross-field invariant via an empty as_text(). A wrong-typed SCALAR was
# already rejected, so null was the single non-conforming value slipping
# through. Both spellings must now be rejected, and with a reason that reads
# DIFFERENTLY from the absent-field case (the nullable-vs-absent lesson).
mk worker-null-verified.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_verified: null
- outputs_gap: ""
- summary: outputs_verified is EXPLICITLY null, not absent
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: EXPLICIT-NULL outputs_verified [rule 6, nullable-vs-absent]" \
  "outputs_verified is present but null"

mk worker-null-gap.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_verified: []
- outputs_gap: null
- summary: outputs_gap is EXPLICITLY null, which used to satisfy "(string)"
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: EXPLICIT-NULL outputs_gap [rule 6, nullable-vs-absent]" \
  "outputs_gap is present but null"

# The null spelling must not be able to smuggle a bad entry past rule 7 either.
mk worker-null-verified-bad-entry.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_verified:
- outputs_gap: ""
- summary: empty-after-colon is one of the five null spellings
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: empty-after-colon outputs_verified is null too [rule 6]" \
  "outputs_verified is present but null"

# --- FINDING 6a: a STALE .worker-summary.md must not vouch for a later worker
# Rule 3 tier 1 keys on a file whose NAME is task-agnostic by contract, so one
# stale file at the cwd used to satisfy rule 3 for every subsequent worker,
# whatever its task_id. (The committed fixtures never mention
# `.worker-summary.md` in prose, so tier 5 cannot rescue this case.)
run_v "$V_WORKER" "$FIXDIR/worker-valid-bullet.md" "$STALE"
assert_fail "worker: a .worker-summary.md naming ANOTHER task does not satisfy rule 3" \
  "(rule 3)"

run_v "$V_WORKER" "$FIXDIR/worker-valid-bullet.md" "$SANDBOX_JWT"
assert_pass "worker: a .worker-summary.md naming THIS task does satisfy rule 3"

# --- FINDING 6b: status=partial is a RECORDED exemption from rule 4 ----------
# agents/worker.md's own worked `partial` example carries a non-empty error
# alongside a non-empty outputs_gap, so an outstanding error is the POINT of
# that status. Extending rule 4 to cover it would false-fail the documented
# shape; the exemption is asserted here so it stays deliberate.
mk worker-partial-error.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: partial
- files_modified: [a.py]
- outputs_verified: [{kind: symbol, path: a.py, name: Foo, status: missing}]
- outputs_gap: "a.py:Foo"
- error: Tests fail — the rotation test expects a cookie the HttpOnly flag hides
- summary: partial legitimately carries an outstanding error
EOF
run_v "$V_WORKER" "$F"
assert_pass "worker: status=partial with a non-empty error is EXEMPT from rule 4"

# --- FINDING 3 (validator level): the conventional markdown blank line -------
mk worker-blank-after-heading.md <<'EOF'
## WORKER_RESULT

- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_verified: []
- outputs_gap: ""
- summary: a blank line after the heading is conventional markdown
EOF
run_v "$V_WORKER" "$F"
assert_pass "worker: heading + conventional blank line is not reported as a MISSING block"

# --- FINDING 7 (validator level): a trailing comment on `status` failed OPEN --
#
# Rules 2, 4 and 8 are ALL guarded by `status == "completed"`. When the parser
# folded a trailing comment into the value, `completed  # done` matched none of
# them, so all three checks were silently SKIPPED — the fail-open class this
# whole PR exists to prevent, and invisible because these run as `type: command`
# hooks under `|| true`. Worker is the only one of the five validators where
# this fails OPEN rather than merely rejecting: its `status` is a DELIBERATE
# non-enum (see the module docstring), so a polluted value slips past the `==`
# instead of tripping an enum or int guard.
#
# Each of the three is a PAIR: the commented block (which answered ok:true
# pre-fix) and the identical block with the comment removed (which was already
# rejected pre-fix). The pair is what proves the fix restored the RULE and not
# merely the reason string.

# rule 2 — no files touched.
mk worker-c7-rule2-comment.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed  # all good
- files_modified: []
- files_created: []
- outputs_verified: []
- outputs_gap: ""
- error: none
- summary: claims completion having touched no files
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: [FALSIFIES] trailing comment on status no longer skips rule 2" \
  "(rule 2)"

mk worker-c7-rule2-control.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: []
- files_created: []
- outputs_verified: []
- outputs_gap: ""
- error: none
- summary: claims completion having touched no files
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: [CONTROL] the same block WITHOUT the comment was already rejected" \
  "(rule 2)"

# rule 4 — an unresolved error alongside status=completed.
mk worker-c7-rule4-comment.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed  # done
- files_modified: [a.py]
- files_created: []
- outputs_verified: []
- outputs_gap: ""
- error: the migration step never completed
- summary: completed with an unresolved error still recorded
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: [FALSIFIES] trailing comment on status no longer skips rule 4" \
  "(rule 4)"

mk worker-c7-rule4-control.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- files_created: []
- outputs_verified: []
- outputs_gap: ""
- error: the migration step never completed
- summary: completed with an unresolved error still recorded
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: [CONTROL] the same block WITHOUT the comment was already rejected" \
  "(rule 4)"

# rule 8 — outputs_gap non-empty must map to status: partial.
mk worker-c7-rule8-comment.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed  # shipped
- files_modified: [a.py]
- files_created: []
- outputs_verified: [{kind: file, path: a.py, status: present}]
- outputs_gap: "src/x.py:Foo"
- error: none
- summary: completed while a promised output is still missing
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: [FALSIFIES] trailing comment on status no longer skips rule 8" \
  "outputs_gap non-empty must map to status: partial"

mk worker-c7-rule8-control.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- files_created: []
- outputs_verified: [{kind: file, path: a.py, status: present}]
- outputs_gap: "src/x.py:Foo"
- error: none
- summary: completed while a promised output is still missing
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: [CONTROL] the same block WITHOUT the comment was already rejected" \
  "outputs_gap non-empty must map to status: partial"

# The OTHER half of the defect: on every typed/enum field the same pollution
# produced a SPURIOUS REJECT of a conforming block. Both of these answered
# ok:false pre-fix.
mk worker-c7-spurious.md <<'EOF'
## WORKER_RESULT
- schema_version: 2  # v2 contract
- task_id: st1
- status: completed  # all criteria met
- files_modified: [a.py]  # one file
- files_created: []
- outputs_verified:
    - kind: file  # the module itself
      path: a.py
      status: present  # verified on disk
- outputs_gap: ""  # nothing missing
- error: none
- summary: "a conforming block that annotates itself — including a # inside quotes"
EOF
run_v "$V_WORKER" "$F"
assert_pass "worker: [FALSIFIES] a fully conforming block with trailing comments is accepted"

mk worker-c7-hash-in-value.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- files_created: []
- outputs_verified: []
- outputs_gap: ""
- error: none
- summary: "closes #118 — the '#' must survive inside a quoted scalar"
EOF
run_v "$V_WORKER" "$F"
assert_pass "worker: [CONTROL] a '#' inside a quoted summary is content, not a comment"

# --- FINDING 8c: the framing defect END-TO-END, through the validator --------
#
# The parser-level cases live in section A; these prove the CONSEQUENCE, which
# is the part that matters: a comment line truncated the block, so an OPTIONAL
# field past the comment was discarded and its rule NEVER RAN. `error` under
# `status: completed` (rule 4) is the worker's instance — the field is optional,
# its only failure mode is present-and-bad, and dropping it is therefore
# invisible.
#
# Measured against the committed parser at 4f63dea:
#   blank + comment  -> ok:FALSE, but on a bogus "'# note' is not a bullet"
#                       PARSE error, so rule 4 still never ran
#   comment NO blank -> ok:TRUE   <-- the outright fail-open
mk worker-f8-rule4-blank-comment.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- files_created: []
- outputs_verified: []
- outputs_gap: ""
- summary: an annotated block whose error field follows a blank line and a comment

# addendum from the worker
- error: the migration step never completed
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: [FALSIFIES @4f63dea] blank line + comment no longer hides the error field from rule 4" \
  "(rule 4)"

mk worker-f8-rule4-noblank-comment.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- files_created: []
- outputs_verified: []
- outputs_gap: ""
- summary: an annotated block whose error field follows a comment with no blank line
# addendum from the worker
- error: the migration step never completed
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: [FALSIFIES @4f63dea] comment with NO blank line was an outright fail-OPEN (ok:true) on rule 4" \
  "(rule 4)"

mk worker-f8-rule4-unbroken.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- files_created: []
- outputs_verified: []
- outputs_gap: ""
- summary: the same block with no comment at all
- error: the migration step never completed
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: [CONTROL] the same block with NO comment was always rejected — so the comment was the only difference" \
  "(rule 4)"

# --- rule 7 is scoped BY PRESENCE, not by schema_version ---------------------
# The prompt says "when present"; rules 6 and 8 say "if schema_version is 2 or
# higher". Keeping rule 7's loop inside the version gate exempted a v1 block
# carrying outputs_verified from ANY shape check. Measured at 4f63dea: ok:true.
mk worker-v1-bad-entry.md <<'EOF'
## WORKER_RESULT
- schema_version: 1
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_verified: [{kind: bogus, path: a.py, status: present}]
- summary: a v1 block whose outputs_verified entry has an invalid kind
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: [FALSIFIES @4f63dea] rule 7 applies to a v1 block that CARRIES outputs_verified" \
  "outputs_verified entries must include {kind, path, status}"

mk worker-v1-good-entry.md <<'EOF'
## WORKER_RESULT
- schema_version: 1
- task_id: st1
- status: completed
- files_modified: [a.py]
- outputs_verified: [{kind: file, path: a.py, status: present}]
- summary: a v1 block whose outputs_verified entry is well formed
EOF
run_v "$V_WORKER" "$F"
assert_pass "worker: [CONTROL] a v1 block with a WELL-FORMED entry still passes (the hoist did not add a v1 requirement)"

mk worker-v1-no-verified.md <<'EOF'
## WORKER_RESULT
- schema_version: 1
- task_id: st1
- status: completed
- files_modified: [a.py]
- summary: a v1 block with no outputs_verified at all, which v1 does not require
EOF
run_v "$V_WORKER" "$F"
assert_pass "worker: [CONTROL] v1 without outputs_verified is still accepted (rules 6/8 stay version-gated)"

# ── C. execute-manager validator ─────────────────────────────────────────────
echo "== C. validate-execute-result.py — 6 rules =="

run_v "$V_EXECUTE" "$FIXDIR/execute-result-valid.md"
assert_pass "execute: valid EXECUTE_RESULT (committed fixture)"

run_v "$V_EXECUTE" "$FIXDIR/execute-checkpoint-valid.md"
assert_pass "execute: valid EXECUTE_CHECKPOINT with a complete adjudication tri-field"

mk execute-no-block.md <<'EOF'
The batch is done but I never emitted a structured block.
EOF
run_v "$V_EXECUTE" "$F"
assert_fail "execute: MISSING block" "missing EXECUTE_RESULT / EXECUTE_CHECKPOINT block"

run_raw "$V_EXECUTE" "$GARBAGE"
assert_pass "execute: malformed (non-JSON) payload -> ok:true"

mk execute-malformed-block.md <<'EOF'
EXECUTE_RESULT:
  schema_version: 1
  subtasks_completed: [{task_id: a, status: completed
  merge_order: [feature/a]
  worktrees: []
  summary: broken
EOF
run_v "$V_EXECUTE" "$F"
assert_fail "execute: malformed BLOCK body -> explicit parse failure" "could not be parsed"

mk execute-missing-key.md <<'EOF'
EXECUTE_RESULT:
  schema_version: 1
  subtasks_completed:
    - task_id: a
      status: completed
      branch: feature/a
  merge_order: [feature/a]
  summary: worktrees field is absent
EOF
run_v "$V_EXECUTE" "$F"
assert_fail "execute: MISSING required key (worktrees) [rule 2]" "missing required field(s): worktrees"

mk execute-null-reason.md <<'EOF'
EXECUTE_CHECKPOINT:
  schema_version: 1
  completed_so_far: []
  remaining:
    - task_id: b
      status: pending
  resume_context:
    feature_branch: feature/x
  reason:
EOF
run_v "$V_EXECUTE" "$F"
assert_fail "execute: EXPLICIT-NULL required key (reason:) [rule 3]" "reason field must be non-empty"

mk execute-absent-reason.md <<'EOF'
EXECUTE_CHECKPOINT:
  schema_version: 1
  completed_so_far: []
  remaining:
    - task_id: b
      status: pending
  resume_context:
    feature_branch: feature/x
EOF
run_v "$V_EXECUTE" "$F"
assert_fail "execute: ABSENT required key (reason) reports differently from null [rule 3]" \
  "missing required field(s): reason"

mk execute-no-sv.md <<'EOF'
EXECUTE_RESULT:
  subtasks_completed: []
  subtasks_failed: [{task_id: a, status: failed}]
  merge_order: []
  worktrees: []
  summary: no schema_version
EOF
run_v "$V_EXECUTE" "$F"
assert_fail "execute: schema_version absent [rule 1]" "(rule 1)"

mk execute-empty-both.md <<'EOF'
EXECUTE_RESULT:
  schema_version: 1
  subtasks_completed: []
  subtasks_failed: []
  merge_order: []
  worktrees: []
  summary: nothing completed and nothing failed
EOF
run_v "$V_EXECUTE" "$F"
assert_fail "execute: empty subtasks_completed without an escalation [rule 2]" "(rule 2)"

mk execute-all-failed.md <<'EOF'
EXECUTE_RESULT:
  schema_version: 1
  subtasks_completed: []
  subtasks_failed:
    - task_id: a
      status: failed
      error: "worker exhausted retries"
      retry_count: 3
  merge_order: []
  worktrees:
    - task_id: a
      path: /tmp/other-project-a
      branch: feature/a
      status: failed
  summary: "0/1 subtasks completed; escalating the all-failed case."
EOF
run_v "$V_EXECUTE" "$F"
assert_pass "execute: empty subtasks_completed IS legal alongside a non-empty subtasks_failed [rule 2]"

mk execute-bad-worktree.md <<'EOF'
EXECUTE_RESULT:
  schema_version: 1
  subtasks_completed:
    - task_id: a
      status: completed
      branch: feature/a
  merge_order: [feature/a]
  worktrees:
    - task_id: a
      path: relative/not/absolute
      branch: feature/a
      status: completed
  summary: worktree path is relative
EOF
run_v "$V_EXECUTE" "$F"
assert_fail "execute: a relative path resolving INSIDE the project is not a sibling [rule 4]" "(rule 4)"

mk execute-no-worktree-path.md <<'EOF'
EXECUTE_RESULT:
  schema_version: 1
  subtasks_completed:
    - task_id: a
      status: completed
      branch: feature/a
  merge_order: [feature/a]
  worktrees:
    - task_id: a
      branch: feature/a
      status: completed
  summary: worktree entry has no path at all
EOF
run_v "$V_EXECUTE" "$F"
assert_fail "execute: worktree entry with no path [rule 4]" "(rule 4)"

for phrase in "toolset_gap" "Task tool unavailable" "Agent tool unavailable"; do
  mk execute-toolset.md <<EOF
EXECUTE_CHECKPOINT:
  schema_version: 1
  completed_so_far: []
  remaining:
    - task_id: b
      status: pending
  resume_context:
    feature_branch: feature/x
  reason: "Halting because $phrase in this environment."
EOF
  run_v "$V_EXECUTE" "$F"
  assert_fail "execute: reason cites '$phrase' [rule 5, verbatim reason]" \
    "toolset_gap is not a valid escalation reason"
done

mk execute-adj-6a.md <<'EOF'
EXECUTE_CHECKPOINT:
  schema_version: 1
  completed_so_far: []
  remaining:
    - task_id: b
      status: pending
  resume_context:
    feature_branch: feature/x
  reason: "Outputs gap detected."
  adjudication_required: true
  missing_outputs: []
  adjudication_options: []
EOF
run_v "$V_EXECUTE" "$F"
assert_fail "execute: CROSS-FIELD adjudication_required=true with empty arrays [rule 6a, verbatim]" \
  "adjudication_required: true requires adjudication_options plus an evidence array"

mk execute-adj-6a-half.md <<'EOF'
EXECUTE_CHECKPOINT:
  schema_version: 1
  completed_so_far: []
  remaining:
    - task_id: b
      status: pending
  resume_context:
    feature_branch: feature/x
  reason: "Outputs gap detected."
  adjudication_required: true
  missing_outputs:
    - item: src/a.ts
      producing_subtask: a
      check_run: "ls"
EOF
run_v "$V_EXECUTE" "$F"
assert_fail "execute: adjudication_required=true with adjudication_options absent [rule 6a]" \
  "adjudication_required: true requires adjudication_options plus an evidence array"

mk execute-adj-6b.md <<'EOF'
EXECUTE_CHECKPOINT:
  schema_version: 1
  completed_so_far: []
  remaining:
    - task_id: b
      status: pending
  resume_context:
    feature_branch: feature/x
  reason: "Outputs gap detected."
  missing_outputs:
    - item: src/a.ts
      producing_subtask: a
      check_run: "ls"
EOF
run_v "$V_EXECUTE" "$F"
assert_fail "execute: CROSS-FIELD missing_outputs without adjudication_required [rule 6b, verbatim]" \
  "the fields are all-or-nothing"

mk execute-adj-6b-false.md <<'EOF'
EXECUTE_CHECKPOINT:
  schema_version: 1
  completed_so_far: []
  remaining:
    - task_id: b
      status: pending
  resume_context:
    feature_branch: feature/x
  reason: "Outputs gap detected."
  adjudication_required: false
  adjudication_options: ["A: re-queue producer"]
EOF
run_v "$V_EXECUTE" "$F"
assert_fail "execute: adjudication_options with adjudication_required=false [rule 6b]" \
  "the fields are all-or-nothing"

# ── rule 6, D6 widening (v15.20.0) — the lane-collision adjudication raiser ──────────────
# A lane collision has no producer/consumer `requires` edge, so no missing_outputs[]. Before
# the widening, rule 6a rejected this shape outright ("requires non-empty missing_outputs"),
# which made agents/execute-manager.md's lane-collision gate UNEMITTABLE — its own SubagentStop
# hook failed the Execute Manager every time the gate fired. Reproduced against the exact
# checkpoint the prompt emits before fixing. All four corners are pinned below so the widening
# cannot silently become a weakening.
mk execute-adj-lane-ok.md <<'EOF'
EXECUTE_CHECKPOINT:
  schema_version: 1
  completed_so_far: []
  remaining:
    - task_id: b
      status: pending
  resume_context:
    feature_branch: feature/x
  reason: "Lane collision: 2 wrote shared/types.ts inside sibling 4's declared lane."
  adjudication_required: true
  adjudication_kind: lane_collision
  colliding_lanes:
    - path: shared/types.ts
      owning_subtask: "4"
      this_subtask: "2"
  adjudication_options: ["A: Re-queue writer with the sibling lane excluded", "B: Serialize the pair (add a requires edge)", "C: Exit to Launch Pad", "D: Widen the writer's declared lane"]
EOF
run_v "$V_EXECUTE" "$F"
assert_pass "execute: rule 6a — colliding_lanes satisfies the evidence requirement with NO missing_outputs (lane-collision gate is emittable)"

mk execute-adj-neither.md <<'EOF'
EXECUTE_CHECKPOINT:
  schema_version: 1
  completed_so_far: []
  remaining:
    - task_id: b
      status: pending
  resume_context:
    feature_branch: feature/x
  reason: "Lane collision with no evidence recorded."
  adjudication_required: true
  adjudication_kind: lane_collision
  adjudication_options: ["A: Re-queue writer with the sibling lane excluded"]
EOF
run_v "$V_EXECUTE" "$F"
assert_fail "execute: rule 6a — adjudication with NEITHER evidence array is still rejected (widened, not weakened)" \
  "adjudication_required: true requires adjudication_options plus an evidence array"

mk execute-adj-badkind.md <<'EOF'
EXECUTE_CHECKPOINT:
  schema_version: 1
  completed_so_far: []
  remaining:
    - task_id: b
      status: pending
  resume_context:
    feature_branch: feature/x
  reason: "Lane collision."
  adjudication_required: true
  adjudication_kind: not_a_real_kind
  colliding_lanes:
    - path: shared/types.ts
      owning_subtask: "4"
      this_subtask: "2"
  adjudication_options: ["A: Re-queue writer with the sibling lane excluded"]
EOF
run_v "$V_EXECUTE" "$F"
assert_fail "execute: rule 6 — adjudication_kind is a CLOSED enum (an unknown kind would fall through to the wrong option set and the wrong Option-C failure reason)" \
  "adjudication_kind, when present, must be one of"

mk execute-adj-lane-orphan.md <<'EOF'
EXECUTE_CHECKPOINT:
  schema_version: 1
  completed_so_far: []
  remaining:
    - task_id: b
      status: pending
  resume_context:
    feature_branch: feature/x
  reason: "Budget exceeded."
  colliding_lanes:
    - path: shared/types.ts
      owning_subtask: "4"
      this_subtask: "2"
EOF
run_v "$V_EXECUTE" "$F"
assert_fail "execute: rule 6b — orphan colliding_lanes without adjudication_required is rejected (same all-or-nothing rule as missing_outputs)" \
  "the fields are all-or-nothing"

mk execute-adj-none.md <<'EOF'
EXECUTE_CHECKPOINT:
  schema_version: 1
  completed_so_far: []
  remaining:
    - task_id: b
      status: pending
  resume_context:
    feature_branch: feature/x
  reason: "Budget exhausted; no adjudication needed."
EOF
run_v "$V_EXECUTE" "$F"
assert_pass "execute: all three adjudication fields absent is the other legal shape [rule 6]"

# --- FINDING 5: rule 4 must key on the PAYLOAD's cwd, not the hook's ---------
# Keying on os.getcwd() meant a hook invoked with its cwd set to the project's
# PARENT — exactly where the `../{project}-{subtask_id}` siblings live —
# classified every sibling as "inside the project root" and rejected every
# healthy EXECUTE_RESULT. The payload's own `cwd` is authoritative, matching
# what worker_summary_file_evidence already does.
WT_PARENT="$TMPROOT/wt"
WT_PROJ="$WT_PARENT/myapp"
mkdir -p "$WT_PROJ" "$WT_PARENT/myapp-a"

mk execute-sibling-abs.md <<EOF
EXECUTE_RESULT:
  schema_version: 1
  subtasks_completed:
    - task_id: a
      status: completed
      branch: feature/a
  merge_order: [feature/a]
  worktrees:
    - task_id: a
      path: $WT_PARENT/myapp-a
      branch: feature/a
      status: completed
  summary: "1/1 subtasks completed."
EOF
EXE_SIBLING="$F"

run_v_cwd "$V_EXECUTE" "$EXE_SIBLING" "$WT_PROJ" "$WT_PARENT"
assert_pass "execute: payload cwd is authoritative — hook running from the project's PARENT [rule 4]"

run_v_cwd "$V_EXECUTE" "$EXE_SIBLING" "$WT_PROJ" "$WT_PROJ"
assert_pass "execute: same block also passes with the hook inside the project [rule 4]"

run_v "$V_EXECUTE" "$EXE_SIBLING" "$WT_PROJ"
assert_pass "execute: os.getcwd() is still the fallback when the payload carries no cwd [rule 4]"

# The sibling rule itself is unchanged — a nested path still fails, and it
# fails from the parent too (i.e. the fix did not simply disable the check).
mk execute-nested.md <<EOF
EXECUTE_RESULT:
  schema_version: 1
  subtasks_completed:
    - task_id: a
      status: completed
      branch: feature/a
  merge_order: [feature/a]
  worktrees:
    - task_id: a
      path: $WT_PROJ/nested/worktree-a
      branch: feature/a
      status: completed
  summary: "worktree nested inside the project root"
EOF
run_v_cwd "$V_EXECUTE" "$F" "$WT_PROJ" "$WT_PARENT"
assert_fail "execute: a path nested INSIDE the project root still fails from the parent [rule 4]" \
  "(rule 4)"

# The added ABSOLUTE-path demand was DROPPED (the replaced prompt never asked
# for it, and the convention is written as the relative `../{project}-{sub}`).
# A relative path now resolves against the project root and faces the same
# sibling test.
mk execute-relative.md <<'EOF'
EXECUTE_RESULT:
  schema_version: 1
  subtasks_completed:
    - task_id: a
      status: completed
      branch: feature/a
  merge_order: [feature/a]
  worktrees:
    - task_id: a
      path: ../myapp-a
      branch: feature/a
      status: completed
  summary: "the documented relative ../{project}-{subtask_id} form"
EOF
run_v_cwd "$V_EXECUTE" "$F" "$WT_PROJ" "$WT_PARENT"
assert_pass "execute: relative ../{project}-{subtask} path accepted (absolute demand dropped) [rule 4]"

# ── D. supervisor-runner validator ───────────────────────────────────────────
echo "== D. validate-supervisor-result.py — 13 rules =="

run_v "$V_SUPERVISOR" "$FIXDIR/supervisor-valid.md"
assert_pass "supervisor: valid block (committed fixture)"

mk sup-no-block.md <<'EOF'
The run finished and the PR is open, but no structured block was emitted.
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: MISSING block" "missing SUPERVISOR_RESULT block"

run_raw "$V_SUPERVISOR" "$GARBAGE"
assert_pass "supervisor: malformed (non-JSON) payload -> ok:true"

mk sup-malformed.md <<'EOF'
SUPERVISOR_RESULT:
  schema_version: 1
  summary: |
    a block scalar is outside the supported subset
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: malformed BLOCK body (block scalar) -> explicit parse failure" \
  "could not be parsed"

# Reusable bases so each case shows only the lines it is falsifying.
cat > "$TMPROOT/sup-skip-base" <<'EOF'
SUPERVISOR_RESULT:
  schema_version: 1
  task_id: t
  status: completed
  pr_url: https://github.com/o/r/pull/9
  branch: feature/x
  heal_loop_ran: false
EOF
cat > "$TMPROOT/sup-ran-base" <<'EOF'
SUPERVISOR_RESULT:
  schema_version: 1
  task_id: t
  status: completed
  pr_url: https://github.com/o/r/pull/9
  branch: feature/x
  heal_loop_ran: true
EOF

cat_mk sup-null-iters.md sup-skip-base <<'EOF'
  heal_iterations: null
  heal_decision: null
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  error: null
  summary: skipped the heal loop
EOF
run_v "$V_SUPERVISOR" "$F"
assert_pass "supervisor: heal_loop_ran=false with EXPLICIT nulls [rule 6, the valid shape]"

cat_mk sup-absent-iters.md sup-skip-base <<'EOF'
  heal_decision: null
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  summary: heal_iterations key is ABSENT, not null
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: ABSENT heal_iterations != explicit null [rule 6, nullable-vs-absent]" \
  "PRESENT and null; the field is absent"

cat_mk sup-absent-decision.md sup-skip-base <<'EOF'
  heal_iterations: null
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  summary: heal_decision key is ABSENT, not null
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: ABSENT heal_decision != explicit null [rule 6, nullable-vs-absent]" \
  "PRESENT and null; the field is absent"

cat_mk sup-nonnull-iters.md sup-skip-base <<'EOF'
  heal_iterations: 2
  heal_decision: null
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  summary: heal_loop_ran=false but iterations were reported
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: heal_loop_ran=false with heal_iterations=2 [rule 6]" \
  "requires heal_iterations=null"

cat_mk sup-nonzero-fixed.md sup-skip-base <<'EOF'
  heal_iterations: null
  heal_decision: null
  heal_fixable_issues_fixed: 3
  heal_remaining_issues: 0
  summary: heal_loop_ran=false but issues were reported fixed
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: heal_loop_ran=false with heal_fixable_issues_fixed=3 [rule 6]" \
  "heal_fixable_issues_fixed=0 exactly"

mk sup-sv2.md <<'EOF'
SUPERVISOR_RESULT:
  schema_version: 2
  status: completed
  pr_url: https://github.com/o/r/pull/9
  heal_loop_ran: false
  heal_iterations: null
  heal_decision: null
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  summary: wrong schema version
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: schema_version != 1 [rule 1]" "must be the integer 1"

mk sup-bad-status.md <<'EOF'
SUPERVISOR_RESULT:
  schema_version: 1
  status: paused
  pr_url: https://github.com/o/r/pull/9
  heal_loop_ran: false
  heal_iterations: null
  heal_decision: null
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  summary: out-of-enum status
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: out-of-enum status [rule 2]" "(rule 2)"

mk sup-null-pr.md <<'EOF'
SUPERVISOR_RESULT:
  schema_version: 1
  status: completed
  pr_url: null
  heal_loop_ran: false
  heal_iterations: null
  heal_decision: null
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  summary: EXPLICIT-NULL pr_url on a completed run
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: EXPLICIT-NULL pr_url with status=completed [rule 3]" "(rule 3)"

mk sup-absent-pr.md <<'EOF'
SUPERVISOR_RESULT:
  schema_version: 1
  status: completed_with_escalation
  heal_loop_ran: false
  heal_iterations: null
  heal_decision: null
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  summary: ABSENT pr_url on a completed_with_escalation run
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: ABSENT pr_url with status=completed_with_escalation [rule 3]" "(rule 3)"

mk sup-bad-bool.md <<'EOF'
SUPERVISOR_RESULT:
  schema_version: 1
  status: checkpoint
  heal_loop_ran: maybe
  heal_iterations: null
  heal_decision: null
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  summary: heal_loop_ran is not a boolean
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: heal_loop_ran not a boolean [rule 4]" "(rule 4)"

mk sup-negative-count.md <<'EOF'
SUPERVISOR_RESULT:
  schema_version: 1
  status: checkpoint
  heal_loop_ran: false
  heal_iterations: null
  heal_decision: null
  heal_fixable_issues_fixed: -1
  heal_remaining_issues: 0
  summary: negative counter
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: negative heal_fixable_issues_fixed [rule 5]" "(rule 5)"

mk sup-null-count.md <<'EOF'
SUPERVISOR_RESULT:
  schema_version: 1
  status: checkpoint
  heal_loop_ran: false
  heal_iterations: null
  heal_decision: null
  heal_fixable_issues_fixed:
  heal_remaining_issues: 0
  summary: EXPLICIT-NULL counter
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: EXPLICIT-NULL heal_fixable_issues_fixed [rule 5]" "(rule 5)"

cat_mk sup-skipped-decision.md sup-ran-base <<'EOF'
  heal_iterations: 1
  heal_decision: SKIPPED
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  summary: SKIPPED is not a legal heal_decision when the loop ran
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: heal_decision=SKIPPED with heal_loop_ran=true [rule 7]" \
  "SKIPPED is NOT allowed"

cat_mk sup-ran-null-iters.md sup-ran-base <<'EOF'
  heal_iterations: null
  heal_decision: PASS
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  summary: EXPLICIT-NULL heal_iterations while the loop ran
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: EXPLICIT-NULL heal_iterations with heal_loop_ran=true [rule 7]" "(rule 7)"

cat_mk sup-pass-remaining.md sup-ran-base <<'EOF'
  heal_iterations: 3
  heal_decision: PASS
  heal_fixable_issues_fixed: 1
  heal_remaining_issues: 2
  summary: PASS while issues remain
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: CROSS-FIELD heal_decision=PASS with remaining>0 [rule 8]" "(rule 8)"

cat_mk sup-escalated-bare.md sup-ran-base <<'EOF'
  heal_iterations: 3
  heal_decision: ESCALATED
  heal_fixable_issues_fixed: 1
  heal_remaining_issues: 0
  error: null
  summary: escalated with nothing to point at
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: ESCALATED with 0 remaining and a null error [rule 9]" "(rule 9)"

cat_mk sup-escalated-thrash.md sup-ran-base <<'EOF'
  heal_iterations: 3
  heal_decision: ESCALATED
  heal_fixable_issues_fixed: 1
  heal_remaining_issues: 0
  error: self_heal_resume_thrash
  summary: escalated via the documented resume-thrash path
EOF
run_v "$V_SUPERVISOR" "$F"
assert_pass "supervisor: ESCALATED with 0 remaining but a non-empty error [rule 9 carve-out]"

cat_mk sup-escalated-remaining.md sup-ran-base <<'EOF'
  heal_iterations: 3
  heal_decision: ESCALATED
  heal_fixable_issues_fixed: 1
  heal_remaining_issues: 2
  error: null
  summary: escalated with issues still outstanding
EOF
run_v "$V_SUPERVISOR" "$F"
assert_pass "supervisor: ESCALATED with remaining>=1 and a null error [rule 9]"

mk sup-failed-no-error.md <<'EOF'
SUPERVISOR_RESULT:
  schema_version: 1
  status: failed
  heal_loop_ran: false
  heal_iterations: null
  heal_decision: null
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  error: null
  summary: failed but reported no error
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: status=failed with an EXPLICIT-NULL error [rule 10]" "(rule 10)"

mk sup-no-summary.md <<'EOF'
SUPERVISOR_RESULT:
  schema_version: 1
  status: checkpoint
  heal_loop_ran: false
  heal_iterations: null
  heal_decision: null
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: MISSING summary [rule 11]" "(rule 11)"

cat_mk sup-bad-profile.md sup-ran-base <<'EOF'
  heal_iterations: 1
  heal_decision: PASS
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  summary: bad cost profile
  cost_profile: budget
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: cost_profile out of enum [rule 12]" "(rule 12)"

cat_mk sup-null-profile.md sup-ran-base <<'EOF'
  heal_iterations: 1
  heal_decision: PASS
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  summary: null cost profile is legal
  cost_profile: null
EOF
run_v "$V_SUPERVISOR" "$F"
assert_pass "supervisor: EXPLICIT-NULL cost_profile is accepted [rule 12]"

cat > "$TMPROOT/sup-rubric-base" <<'EOF'
SUPERVISOR_RESULT:
  schema_version: 1
  status: completed
  pr_url: https://github.com/o/r/pull/9
  heal_loop_ran: true
  heal_iterations: 1
  heal_decision: PASS
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  summary: rubric probe
EOF
mk_rubric() {
  F="$TMPROOT/sup-rubric.md"
  { cat "$TMPROOT/sup-rubric-base"; printf '  rubric_score: %s\n' "$1"; } > "$F"
}

for good in '"7/7"' '"0/5"' '"3/10"'; do
  mk_rubric "$good"
  run_v "$V_SUPERVISOR" "$F"
  assert_pass "supervisor: rubric_score $good accepted [rule 13]"
done

for bad in '"8/7"' '"7/0"' '"07/7"' '"7"' '"a/b"' '"-1/5"' '"7/"' '7.5'; do
  mk_rubric "$bad"
  run_v "$V_SUPERVISOR" "$F"
  assert_fail "supervisor: rubric_score $bad rejected [rule 13, verbatim reason]" \
    "rubric_score must be null or a string 'N/M' with N >= 0, M >= 1, M >= N"
done

mk_rubric "null"
run_v "$V_SUPERVISOR" "$F"
assert_pass "supervisor: EXPLICIT-NULL rubric_score accepted [rule 13]"

cat_mk sup-rubric-absent.md sup-ran-base <<'EOF'
  heal_iterations: 1
  heal_decision: PASS
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  summary: rubric_score is absent, which rule 13 explicitly accepts
EOF
run_v "$V_SUPERVISOR" "$F"
assert_pass "supervisor: ABSENT rubric_score accepted (rule 13 forbids rejecting on absence)"

# --- FINDING 3 (validator level): an internal blank line must not truncate ---
# SUPERVISOR_RESULT carries ~20 fields including nested blocks, so this is the
# most reachable case. Before the fix this reported "missing the heal_loop_ran
# field" — a fail-closed but actively misleading reason, since the field is
# present just past the break.
mk sup-internal-blank.md <<'EOF'
SUPERVISOR_RESULT:
  schema_version: 1
  task_id: t
  status: completed
  pr_url: https://github.com/o/r/pull/9

  heal_loop_ran: false
  heal_iterations: null
  heal_decision: null
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  summary: one internal blank line, every field present
EOF
run_v "$V_SUPERVISOR" "$F"
assert_pass "supervisor: an internal blank line does not truncate the block into a false missing-field"

# --- FINDING 8d: the framing defect on SUPERVISOR_RESULT.rubric_score --------
#
# rubric_score is the supervisor's optional present-and-bad-only field, exactly
# as `error` is the worker's, so truncating the block before it makes rule 13
# unreachable. `9/4` is deliberately invalid (N > M) so a REACHED rule always
# rejects — ok:true therefore proves the field was never seen.
#
# HONEST CLASSIFICATION, measured per emission form:
#   YAML form, blank + comment      -> already correct at 4f63dea. This is a
#                                      CONTROL there; it falsifies against
#                                      03b5535, the pre-framing-fix parser, and
#                                      is kept so that earlier half of the fix
#                                      cannot silently regress.
#   markdown-bullet form, no blank  -> ok:TRUE at 4f63dea. A genuine fail-open,
#                                      and the reason this pair is not
#                                      YAML-only: the two forms had DIFFERENT
#                                      bugs and only one was fixed.
mk sup-f8-yaml-blank-comment.md <<'EOF'
SUPERVISOR_RESULT:
  schema_version: 1
  task_id: t
  status: completed
  pr_url: https://github.com/o/r/pull/9
  heal_loop_ran: true
  heal_iterations: 1
  heal_decision: PASS
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  summary: rubric recorded after a blank line and a comment

  # the rubric grader answered late
  rubric_score: "9/4"
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: [CONTROL @4f63dea / FALSIFIES @03b5535] YAML blank+comment keeps rubric_score reachable by rule 13" \
  "rubric_score must be null or a string 'N/M' with N >= 0, M >= 1, M >= N"

mk sup-f8-md-noblank-comment.md <<'EOF'
## SUPERVISOR_RESULT
- schema_version: 1
- task_id: t
- status: completed
- pr_url: https://github.com/o/r/pull/9
- heal_loop_ran: true
- heal_iterations: 1
- heal_decision: PASS
- heal_fixable_issues_fixed: 0
- heal_remaining_issues: 0
- summary: rubric recorded after a comment with no blank line
# the rubric grader answered late
- rubric_score: "9/4"
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: [FALSIFIES @4f63dea] markdown form, comment with NO blank line was an outright fail-OPEN (ok:true) on rule 13" \
  "rubric_score must be null or a string 'N/M' with N >= 0, M >= 1, M >= N"

mk sup-f8-md-blank-comment.md <<'EOF'
## SUPERVISOR_RESULT
- schema_version: 1
- task_id: t
- status: completed
- pr_url: https://github.com/o/r/pull/9
- heal_loop_ran: true
- heal_iterations: 1
- heal_decision: PASS
- heal_fixable_issues_fixed: 0
- heal_remaining_issues: 0
- summary: rubric recorded after a blank line and a comment

# the rubric grader answered late
- rubric_score: "9/4"
EOF
run_v "$V_SUPERVISOR" "$F"
assert_fail "supervisor: [FALSIFIES @4f63dea] markdown form, blank+comment was rejected on a bogus parse error so rule 13 never ran" \
  "rubric_score must be null or a string 'N/M' with N >= 0, M >= 1, M >= N"

# ── E. (moved) qa-executor validator ─────────────────────────────────────────
# validate-qa-result.py and its 5-rule arm now live in the SELVEDGE plugin, with
# their fixture: selvedge/scripts/test-result-validators.sh. A plugin's tests
# belong with the plugin; CI's hard-gate loop runs every plugin's test-*.sh, so
# the coverage moved rather than being lost. Deliberately NOT pointed
# cross-plugin from here — that would re-couple the two trees this split undoes.

# ── F. plan-reviewer validator ───────────────────────────────────────────────
echo "== F. validate-plan-review-result.py — 6 rules =="

run_v "$V_PLAN" "$FIXDIR/plan-review-valid.md"
assert_pass "plan: valid FAIL block with a BLOCKING issue (committed fixture)"

mk plan-no-block.md <<'EOF'
The brief looks sound overall, but no structured block was emitted.
EOF
run_v "$V_PLAN" "$F"
assert_fail "plan: MISSING block" "missing PLAN_REVIEW_RESULT block"

run_raw "$V_PLAN" "$GARBAGE"
assert_pass "plan: malformed (non-JSON) payload -> ok:true"

mk plan-malformed.md <<'EOF'
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: PASS
  issues: [{severity: LOW, section: "x"
  summary: broken flow mapping
EOF
run_v "$V_PLAN" "$F"
assert_fail "plan: malformed BLOCK body -> explicit parse failure" "could not be parsed"

mk plan-pass.md <<'EOF'
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: PASS
  issues: []
  summary: "Brief is well-structured; all paths verified."
EOF
run_v "$V_PLAN" "$F"
assert_pass "plan: PASS with an empty issues array"

mk plan-missing-summary.md <<'EOF'
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: PASS
  issues: []
EOF
run_v "$V_PLAN" "$F"
assert_fail "plan: MISSING required key (summary) [rule 6]" "(rule 6)"

mk plan-null-summary.md <<'EOF'
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: PASS
  issues: []
  summary:
EOF
run_v "$V_PLAN" "$F"
assert_fail "plan: EXPLICIT-NULL required key (summary:) [rule 6]" "(rule 6)"

mk plan-sv.md <<'EOF'
PLAN_REVIEW_RESULT:
  schema_version: 3
  decision: PASS
  issues: []
  summary: wrong schema version
EOF
run_v "$V_PLAN" "$F"
assert_fail "plan: schema_version != 1 [rule 1]" "must be the integer 1"

mk plan-bad-decision.md <<'EOF'
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: APPROVED
  issues: []
  summary: out-of-enum decision
EOF
run_v "$V_PLAN" "$F"
assert_fail "plan: out-of-enum decision [rule 2]" "(rule 2)"

mk plan-fail-empty.md <<'EOF'
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: FAIL
  issues: []
  summary: FAIL with no issues
EOF
run_v "$V_PLAN" "$F"
assert_fail "plan: decision=FAIL with an empty issues array [rule 3]" "(rule 3)"

mk plan-needs-human-empty.md <<'EOF'
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: NEEDS_HUMAN
  issues: []
  summary: NEEDS_HUMAN with no issues
EOF
run_v "$V_PLAN" "$F"
assert_fail "plan: decision=NEEDS_HUMAN with an empty issues array [rule 3]" "(rule 3)"

mk plan-issue-null-desc.md <<'EOF'
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: NEEDS_HUMAN
  issues:
    - severity: MEDIUM
      section: "Subtask Structure"
      description:
  summary: EXPLICIT-NULL description on an issue
EOF
run_v "$V_PLAN" "$F"
assert_fail "plan: EXPLICIT-NULL issue description [rule 3]" "missing a non-empty description"

mk plan-issue-absent-sev.md <<'EOF'
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: NEEDS_HUMAN
  issues:
    - section: "Subtask Structure"
      description: "Scope is ambiguous."
  summary: ABSENT severity on an issue
EOF
run_v "$V_PLAN" "$F"
assert_fail "plan: ABSENT issue severity [rule 3]" "missing a non-empty severity"

mk plan-fail-medium.md <<'EOF'
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: FAIL
  issues:
    - severity: MEDIUM
      section: "Subtask Structure"
      description: "Scope is a little broad."
  summary: FAIL carried only a MEDIUM issue
EOF
run_v "$V_PLAN" "$F"
assert_fail "plan: CROSS-FIELD decision=FAIL with no BLOCKING/HIGH issue [rule 4]" "(rule 4)"

mk plan-fail-high.md <<'EOF'
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: FAIL
  issues:
    - severity: HIGH
      section: "Parallelism Analysis"
      description: "Hidden file overlap between LAUNCHABLE subtasks."
    - severity: LOW
      section: "Skill References"
      description: "Cosmetic."
  summary: FAIL with a HIGH issue is the valid shape
EOF
run_v "$V_PLAN" "$F"
assert_pass "plan: decision=FAIL with a HIGH issue is the VALID shape [rule 4]"

mk plan-no-section.md <<'EOF'
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: FAIL
  issues:
    - severity: BLOCKING
      description: "Path does not exist."
  summary: the issue has no section field
EOF
run_v "$V_PLAN" "$F"
assert_fail "plan: issue missing the section field [rule 5]" "(rule 5)"

mk plan-pass-issue-no-section.md <<'EOF'
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: PASS
  issues:
    - severity: LOW
      description: "Cosmetic nit."
  summary: rule 5 applies on PASS too when issues are listed
EOF
run_v "$V_PLAN" "$F"
assert_fail "plan: PASS-with-issues still requires a section on each [rule 5]" "(rule 5)"

# ── G. exit-0-by-contract on garbage, per file (R3) ──────────────────────────
echo "== G. exit-0-by-contract — every Python file, per file, never masked =="
for v in $ALL_PY; do
  printf 'garbage' | ( cd "$SANDBOX" && python3 "$v" ) >/dev/null 2>&1
  rc=$?
  if [ "$rc" = "0" ]; then
    ok "exit 0 on garbage stdin: $(basename "$v")"
  else
    no "exit $rc on garbage stdin: $(basename "$v")  (|| true would MASK this)"
  fi
done
for v in $ALL_PY; do
  ( cd "$SANDBOX" && python3 "$v" ) >/dev/null 2>&1 </dev/null
  rc=$?
  if [ "$rc" = "0" ]; then
    ok "exit 0 on EMPTY stdin: $(basename "$v")"
  else
    no "exit $rc on empty stdin: $(basename "$v")"
  fi
done
for v in $V_WORKER $V_EXECUTE $V_SUPERVISOR $V_PLAN; do
  printf '{"last_assistant_message": 12345}' | ( cd "$SANDBOX" && python3 "$v" ) >/dev/null 2>&1
  rc=$?
  if [ "$rc" = "0" ]; then
    ok "exit 0 on a WRONG-TYPE payload field: $(basename "$v")"
  else
    no "exit $rc on a wrong-type payload field: $(basename "$v")"
  fi
done

# ── H / I. real payload shape and --raw mode ─────────────────────────────────
echo "== H. real-shaped SubagentStop payload (committed fixture) =="
LAST_OUT="$( ( cd "$SANDBOX" && python3 "$V_WORKER" ) < "$FIXDIR/subagentstop-payload.json" 2>/dev/null)"
LAST_RC=$?
assert_fail "worker: full real-field-set payload with no result block" "missing WORKER_RESULT block"

echo "== I. --raw mode (stdin IS the agent text, no JSON envelope) =="
LAST_OUT="$( ( cd "$SANDBOX_JWT" && python3 "$V_WORKER" --raw ) < "$FIXDIR/worker-valid-bullet.md" 2>/dev/null)"
LAST_RC=$?
assert_pass "worker: --raw mode accepts the bare agent text"

echo "== J. import-time fail-safe — shared module ABSENT or CORRUPT (R3) =="
# run_validator() guarantees exit 0 for anything raised INSIDE main(), but it
# cannot guard its own import. With result_block_parser.py absent or
# syntactically broken, the validator used to exit 1 with a traceback and put
# NOTHING on stdout; the `type: command` + `|| true` wiring MASKS that, so the
# hook silently validated nothing — the security regression CLAUDE.md
# §Failure-Mode Invariants names. This edge belongs to the shared-module
# design: the template these are modelled on (validate-launch-pad-result.py)
# is self-contained and has no import to fail.
#
# The probe input is DISCRIMINATING on purpose: it carries no result block, so
# a WORKING validator answers ok:FALSE. ok:true therefore proves the fail-safe
# path was taken, and the assertion cannot pass vacuously.
mk import-guard-probe.md <<'EOF'
There is no result block anywhere in this text, so a WORKING validator answers ok:false.
EOF
GUARD_PROBE="$F"

NOMOD="$TMPROOT/nomod"
BADMOD="$TMPROOT/badmod"
mkdir -p "$NOMOD" "$BADMOD"
# A module that exists but does not compile (SyntaxError at import time).
printf 'def broken(:\n' > "$BADMOD/result_block_parser.py"

for v in $V_WORKER $V_EXECUTE $V_SUPERVISOR $V_PLAN; do
  base="$(basename "$v")"
  cp "$v" "$NOMOD/$base"
  cp "$v" "$BADMOD/$base"

  # Control: the same probe against the REAL validator must answer ok:false,
  # proving the input discriminates and the two assertions below are not
  # vacuously green.
  run_v "$v" "$GUARD_PROBE"
  assert_fail "$base: control — the probe is rejected when the module IS importable"

  run_v "$NOMOD/$base" "$GUARD_PROBE"
  assert_pass "$base: result_block_parser ABSENT -> exit 0 + ok:true (never a masked traceback)"

  run_v "$BADMOD/$base" "$GUARD_PROBE"
  assert_pass "$base: result_block_parser CORRUPT -> exit 0 + ok:true (never a masked traceback)"
done

echo ""
# ---------------------------------------------------------------------------
# rule 9 — out_of_lane (v15.20.0, D6). Optional + additive at schema_version 2, so
# ABSENCE must pass; when PRESENT it must be an array of non-empty strings. The rule
# must never touch status/outputs_gap (the `completed` iff `outputs_gap == ""`
# biconditional is independent of it). These branches had zero coverage here --
# only the MANIFEST name-pin was checked, which cannot see behavior.
# ---------------------------------------------------------------------------
mk worker-r9-absent.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- files_created: []
- outputs_verified: []
- outputs_gap: ""
- summary: out_of_lane absent entirely — optional/additive, must still validate
EOF
run_v "$V_WORKER" "$F"
assert_pass "worker: rule 9 — out_of_lane ABSENT is accepted (optional/additive, no schema bump)"

mk worker-r9-empty.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- files_created: []
- outputs_verified: []
- outputs_gap: ""
- out_of_lane: []
- summary: explicit empty list — the in-lane case
EOF
run_v "$V_WORKER" "$F"
assert_pass "worker: rule 9 — out_of_lane [] is accepted (in-lane, presence-gated not truthiness-gated)"

mk worker-r9-populated.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py, shared/types.ts]
- files_created: []
- outputs_verified: []
- outputs_gap: ""
- out_of_lane: [shared/types.ts]
- summary: REPORT-ONLY — a populated out_of_lane must NOT flip status away from completed
EOF
run_v "$V_WORKER" "$F"
assert_pass "worker: rule 9 — populated out_of_lane coexists with status:completed + empty outputs_gap (report-only, invariant untouched)"

mk worker-r9-nonlist.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- files_created: []
- outputs_verified: []
- outputs_gap: ""
- out_of_lane: "shared/types.ts"
- summary: present but a bare string, not an array
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: rule 9 — out_of_lane present-but-NOT-a-list is rejected" "rule 9"

mk worker-r9-emptystring.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- files_created: []
- outputs_verified: []
- outputs_gap: ""
- out_of_lane: ["", "shared/types.ts"]
- summary: present list containing an empty-string entry
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: rule 9 — out_of_lane with an empty-string entry is rejected" "rule 9"

# Explicit NULL. Distinct from ABSENT above and covered by its own branch in rule 9:
# `present()` is a key-PRESENCE test (`key in fields`), so `out_of_lane: null` is PRESENT with a
# None value and must be rejected, while omitting the key entirely stays accepted. This is the
# nullable-but-required trap that shipped past review once already in this repo (PR #84's
# read-rules.sh `check`): a type guard that only rejects the WRONG type silently accepts null
# when null is also a legal YAML scalar. Both halves are asserted so the pair cannot drift apart.
mk worker-r9-null.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- files_created: []
- outputs_verified: []
- outputs_gap: ""
- out_of_lane: null
- summary: explicit null is PRESENT with a None value — rejected, unlike an omitted key
EOF
run_v "$V_WORKER" "$F"
assert_fail "worker: rule 9 — explicit out_of_lane: null is rejected (present-with-None, not absent)" "rule 9"

# Non-string-LOOKING element. Rule 9 also carries an `isinstance(item, str)` guard, and this
# pins what actually happens to it: NOTHING on this carrier. `load_block` sources `fields`
# exclusively from the markdown block text via `parse_block`, and that parser normalizes every
# scalar to a Python str -- verified: `[123, "shared/types.ts"]` parses to `['123',
# 'shared/types.ts']`. So `123` arrives as the string "123", which IS a valid non-empty path
# string, and the block is correctly ACCEPTED. The isinstance half is defensive-only: unreachable
# unless a future carrier (e.g. a JSON hook payload preserving native types) feeds these
# validators. Asserted as a PASS deliberately -- writing this as an expected failure would encode
# a promise the contract does not make, and would fail the moment someone read the parser. If a
# typed carrier is ever added, THIS assertion flips and points straight at the reason.
mk worker-r9-nonstring-item.md <<'EOF'
## WORKER_RESULT
- schema_version: 2
- task_id: st1
- status: completed
- files_modified: [a.py]
- files_created: []
- outputs_verified: []
- outputs_gap: ""
- out_of_lane: [123, "shared/types.ts"]
- summary: 123 normalizes to the string "123" on this carrier — a valid non-empty path string
EOF
run_v "$V_WORKER" "$F"
assert_pass "worker: rule 9 — a bare 123 in out_of_lane is ACCEPTED (the markdown carrier stringifies every scalar; the isinstance guard is unreachable here by construction)"

echo "RESULT  pass=$PASS_COUNT  fail=$FAIL_COUNT"
if [ "$FAIL_COUNT" -eq 0 ]; then
  exit 0
fi
exit 1
