#!/usr/bin/env bash
# send-telemetry-core.sh — TELEMETRY CORE (Subtask #2b)
#
# Authoritative spec: loomwright/docs/TELEMETRY.md
#
# Pipeline (matches docs/TELEMETRY.md §Interest filter — privacy first, gh last):
#   1. Parse flags (only --dry-run supported)
#   2. Read stdin
#   3. Stage 1 (python, `-I`):
#      a. resolve the finishing agent's text and locate its result block with
#         the SHARED result_block_parser.py — the same ladder and locator the
#         SubagentStop validators use (no second, permissive parser here)
#      b. raw payload privacy scan — fail-closed exit 2 BEFORE everything
#         else, so a privacy-blocked event always logs, healthy or not
#      c. sibling-validator verdict: run the SAME validate-*-result.py that
#         sits beside this core in the SubagentStop group on the SAME payload;
#         a stop it rejects (`decision: block`) is skipped (exit 5,
#         validator_rejected) — the agent is told to re-emit and the retry is
#         the one that is recorded. Decided from the verdict, not hook order.
#      d. parse the block with result_block_parser.parse_block; parse errors
#         also skip (exit 5, unparseable_block) — defence in depth when the
#         validator itself is unavailable
#      e. score + per-severity / per-category counts FROM THE PARSED FIELDS
#         (every category, `drift` included — never from rendered lines)
#      f. render the open / round / close texts from plugin facts only, then
#         the final body privacy scan (exit 2 again on hit)
#   4. Read consent via resolve-egress-config.sh (USER-SCOPE ONLY —
#      ~/.claude/loomwright/egress.json, keyed by repo slug; red-team-hardening
#      item 02 — a repo-relative .supervisor/telemetry-consent.json can at most
#      REQUEST, never grant, see docs/TELEMETRY.md §"Consent flow"):
#        - "no" exact         -> exit 3, stderr "denied — skipped"
#        - missing/prompt/etc -> exit 3, stderr "consent_uninitialised state=..."
#        - repo-requested telemetry_repo != resolved value -> stderr
#          "repo_consent_ignored slug=<slug>" (informational, does not change
#          the exit code by itself)
#   5. Resolve target repo (env -> user-scope entry -> exit 4)
#   6. Stage 2 (python, `-I`) — ONE THREAD PER REVIEW TARGET
#      (docs/TELEMETRY.md §"Posting policy"):
#        - thread key = sha256(destination, agent, source repo, branch) computed
#          locally; stored ONLY in the user-scope map
#          ~/.claude/loomwright/telemetry-threads.json, never posted
#        - interest filter: a success with no open thread and score >= 5 is
#          skipped (exit 5)
#        - first non-success for a key opens an issue; later rounds comment on
#          it; a success closes it (closing comment + telemetry:healed-in-loop)
#        - the same round seen twice in one thread is skipped (exit 5, dedup_hit)
#        - unreadable map -> post nothing (exit 1, thread_map_unreadable)
#        - --dry-run: reads the map, prints the would-be action, writes nothing
#        - live: the whole read-decide-post-write runs under an exclusive
#          flock on the map's lock file; the map is replaced atomically
#
# Exit codes (authoritative — match docs/TELEMETRY.md):
#   0 sent
#   1 generic_error
#   2 privacy_blocked
#   3 no_consent
#   4 no_repo_configured
#   5 filter_skipped

set -u
set -o pipefail
# Intentionally NO `set -e` — we need precise per-step exit codes.

# ---- Resolve paths -----------------------------------------------------------
LOG_DIR="${PWD}/.supervisor/logs"
SENT_LOG="$LOG_DIR/telemetry-sent.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true

# ---- Resolve plugin version (additive, defensive) ------------------------------
# Read the plugin's own manifest relative to THIS script's location
# (scripts/ -> ../.claude-plugin/plugin.json) — NOT relative to $PWD, which is the
# user's project. LOOMWRIGHT_PLUGIN_MANIFEST overrides the path (used by
# test-telemetry.sh to exercise the unreadable-manifest fallback). Any failure
# yields "unknown" — version stamping must NEVER break the telemetry pipeline.
CORE_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
PLUGIN_MANIFEST="${LOOMWRIGHT_PLUGIN_MANIFEST:-${CORE_SELF_DIR}/../.claude-plugin/plugin.json}"
PLUGIN_VERSION="unknown"
if [ -n "$CORE_SELF_DIR" ] && [ -f "$PLUGIN_MANIFEST" ]; then
  if command -v jq >/dev/null 2>&1; then
    PLUGIN_VERSION="$(jq -r '.version // "unknown"' "$PLUGIN_MANIFEST" 2>/dev/null)" || PLUGIN_VERSION="unknown"
  elif command -v python3 >/dev/null 2>&1; then
    PLUGIN_VERSION="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version") or "unknown")' "$PLUGIN_MANIFEST" 2>/dev/null)" || PLUGIN_VERSION="unknown"
  fi
fi
case "$PLUGIN_VERSION" in ""|null) PLUGIN_VERSION="unknown" ;; esac
export LOOMWRIGHT_PLUGIN_VERSION="$PLUGIN_VERSION"
# The shared parser and the sibling validators are found HERE, beside this
# script — never on $PWD (the user's project), which `python3 -I` also keeps
# off sys.path.
export LOOMWRIGHT_TELEMETRY_CORE_DIR="$CORE_SELF_DIR"

# ---- Parse flags -------------------------------------------------------------
DRY_RUN="false"
if [ "$#" -gt 0 ]; then
  case "$1" in
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --*)
      printf 'unknown_flag=%s\n' "$1" >&2
      exit 1
      ;;
  esac
fi
if [ "$#" -gt 0 ]; then
  printf 'unexpected_argument=%s\n' "$1" >&2
  exit 1
fi

# ---- python3 required --------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
  printf 'python3_missing\n' >&2
  exit 1
fi

# ---- Read stdin --------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
if [ -z "$INPUT" ]; then
  printf 'unknown_payload_skipped reason=empty_stdin\n' >&2
  exit 5
fi

# ---- Early consent read: INCLUDE_RESULT_BLOCK only ---------------------------
# This is a NON-GATING read — it does not decide whether the send proceeds
# (that is step 4 below, unchanged, at its documented pipeline position). It
# only tells stage 1 whether the (now inert) include_result_block key is set,
# so stage 1 can note that it ignores it. Calling the resolver a second time at
# step 4 for the actual consent decision is deliberate — it keeps this read
# isolated from (and unable to influence) the privacy-before-consent order.
EARLY_INCLUDE_RESULT_BLOCK=""
if [ -n "$CORE_SELF_DIR" ] && [ -f "${CORE_SELF_DIR}/resolve-egress-config.sh" ]; then
  EARLY_RESOLVER_OUT="$(bash "${CORE_SELF_DIR}/resolve-egress-config.sh" 2>/dev/null || true)"
  while IFS='=' read -r erk erv; do
    case "$erk" in
      INCLUDE_RESULT_BLOCK) EARLY_INCLUDE_RESULT_BLOCK="$erv" ;;
    esac
  done <<EOF
$EARLY_RESOLVER_OUT
EOF
fi
export LOOMWRIGHT_INCLUDE_RESULT_BLOCK="$EARLY_INCLUDE_RESULT_BLOCK"

# ---- Stage 1: parse JSON, verdict, parse block, score, build texts -----------
#
# Single python invocation that returns a `key=value` line-protocol on stdout
# so bash can keep orchestrating cleanly. All redactions and regex live inside
# python so the regex set is defined exactly once for body + raw scanning.

# Load python source into a variable so the heredoc does NOT consume stdin.
# (`python3 - <<PY` reads its code from stdin, which would clobber the JSON
# payload we need to pipe in.) Using `python3 -c "$VAR"` keeps stdin free.
IFS= read -r -d '' STAGE1_PY <<'PY' || true
import json, sys, re, os, hashlib, subprocess

# ---------------------------------------------------------------------------
# Privacy regex deny-list — MUST stay aligned with send-telemetry.sh wrapper
# and docs/TELEMETRY.md. The first 8 tuples are the wrapper's mapping; the 9th
# (.env-style assignment, multiline) is body-only per Subtask #2a guidance.
# Defined (with the two helpers below) BEFORE any exit point: the test
# harness exec()s this source and calls them directly.
# ---------------------------------------------------------------------------
PRIVACY_PATTERNS = [
    (re.compile(r"sk-[A-Za-z0-9]{20,}"),                                 "openai-key"),
    (re.compile(r"ghp_[A-Za-z0-9]{20,}"),                                "github-token"),
    (re.compile(r"(?i)api[_-]?key\s*[:=]\s*\S+"),                        "api-key"),
    (re.compile(r"Bearer\s+\S+"),                                        "bearer"),
    (re.compile(r"(?i)password\s*[:=]\s*\S+"),                           "password"),
    (re.compile(r"/Users/[a-zA-Z._-]+/"),                                "macos-home-path"),
    (re.compile(r"/home/[a-zA-Z._-]+/"),                                 "linux-home-path"),
    (re.compile(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"),      "email"),
    (re.compile(r"^\s*[A-Z_][A-Z0-9_]*=.+$", re.MULTILINE),              "env-assignment"),
]

def scan_for_secret(text, skip=()):
    for rx, label in PRIVACY_PATTERNS:
        if label in skip:
            continue
        if rx.search(text):
            return label
    return ""

# Home paths identify the user (the username) but are not credentials, and
# agent reports carry them almost always (SUPERVISOR_RESULT's worktree `path`
# is absolute BY SCHEMA; reviewers cite absolute file paths). Blocking on them
# meant nothing was ever posted. They are REDACTED out of the prospective body
# instead (`redact_home_paths` below, applied before the final body scan, which
# still runs the FULL pattern set and stays fail-closed). Every secret-class
# pattern (keys, tokens, bearer, password, email, .env assignment) still
# hard-blocks in the raw scan exactly as before.
HOME_PATH_LABELS = frozenset(("macos-home-path", "linux-home-path"))

def redact_home_paths(text):
    out = text
    for rx, label in PRIVACY_PATTERNS:
        if label in HOME_PATH_LABELS:
            out = rx.sub("[REDACTED:" + label + "]/", out)
    return out

def emit(key, value):
    # Replace newlines so bash can read line-by-line.
    if isinstance(value, bool):
        value = "true" if value else "false"
    s = str(value).replace("\r", " ").replace("\n", "\\n")
    sys.stdout.write("%s=%s\n" % (key, s))

def fail(stage, msg, exit_code):
    sys.stderr.write("%s reason=%s\n" % (stage, msg))
    emit("EXIT_CODE", exit_code)
    sys.stdout.flush()
    sys.exit(0)  # bash reads EXIT_CODE; this stage always returns 0 itself.

# ---- The shared parser (the one every SubagentStop validator uses) ---------
# Imported from the core's own directory only. A missing or broken parser
# means nothing can be verified, so nothing is posted.
CORE_DIR = os.environ.get("LOOMWRIGHT_TELEMETRY_CORE_DIR", "")
if not CORE_DIR or not os.path.isfile(os.path.join(CORE_DIR, "result_block_parser.py")):
    fail("parser_unavailable", "result_block_parser_missing", 1)
sys.path.insert(0, CORE_DIR)
try:
    import result_block_parser as rbp
except Exception:
    fail("parser_unavailable", "result_block_parser_import_failed", 1)

SCHEMA_NAMES = ("SUPERVISOR_RESULT", "CODE_REVIEW_RESULT", "QA_RESULT")
# The validator each block's SubagentStop group runs beside this core
# (hooks/hooks.json): code-reviewer, qa-executor, supervisor-runner.
SIBLING_VALIDATORS = {
    "SUPERVISOR_RESULT": "validate-supervisor-result.py",
    "CODE_REVIEW_RESULT": "validate-code-review-result.py",
    "QA_RESULT": "validate-qa-result.py",
}

# ---- Parse JSON ------------------------------------------------------------
try:
    raw = sys.stdin.read()
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise ValueError("payload_not_object")
except Exception as e:
    fail("unknown_payload_skipped", "json_parse_failed", 5)

# ---- Script events (docs/TELEMETRY.md §"Script events") ---------------------
# A plugin SCRIPT (not an agent) reports that one of its steps failed, warned or
# passed: `emit-script-event.sh` builds the payload, the wrapper pipes it here.
# PRIVACY IS FIELD SELECTION: only allow-listed fields of allow-listed shapes are
# read — a known script name, token-shaped step / code, an outcome enum, integer
# counts, and per-group counts of a fixed managed-KIND enum. Anything else in the
# payload (an extra key, a path, a message) is never copied anywhere. A required
# field that fails its shape skips the event (exit 5); an optional entry that
# fails is dropped and counted in raw_data.dropped.
# MUTATION_CONTROL_BEGIN: script-event-field-selection
SCRIPT_EVENT_SCRIPTS = ("migrate-branch-mode", "setup-memory")
SCRIPT_EVENT_OUTCOMES = ("pass", "fail", "warn")
SCRIPT_EVENT_KIND_GROUPS = ("b_only", "a_only", "blob_mismatch")
SCRIPT_EVENT_KINDS = ("md", "dismissed-decisions", "results-jsonl", "brain-baseline-jsonl",
                      "provenance-jsonl", "other")
SE_TOKEN_RX = re.compile(r"^[a-z][a-z0-9_-]{0,39}$")
SE_COUNT_KEY_RX = re.compile(r"^[a-z][a-z0-9_]{0,31}$")
SE_ID_RX = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
SE_MAX_ENTRIES = 16

def _se_int(v):
    return isinstance(v, int) and not isinstance(v, bool) and 0 <= v <= 10 ** 9

def script_event(p):
    dropped = 0
    script = p.get("script")
    if not (isinstance(script, str) and script in SCRIPT_EVENT_SCRIPTS):
        fail("unknown_payload_skipped", "script_event_invalid field=script", 5)
    req = {}
    for k in ("step", "code"):
        v = p.get(k)
        if not (isinstance(v, str) and SE_TOKEN_RX.match(v)):
            fail("unknown_payload_skipped", "script_event_invalid field=%s" % k, 5)
        req[k] = v
    outcome = p.get("outcome")
    if outcome not in SCRIPT_EVENT_OUTCOMES:
        fail("unknown_payload_skipped", "script_event_invalid field=outcome", 5)
    event_id = p.get("event_id")
    if not (isinstance(event_id, str) and SE_ID_RX.match(event_id)):
        fail("unknown_payload_skipped", "script_event_invalid field=event_id", 5)
    caller = p.get("caller")
    if caller is not None:
        parts = caller.split(".", 1) if isinstance(caller, str) else []
        if not (len(parts) == 2 and parts[0] in SCRIPT_EVENT_SCRIPTS and SE_TOKEN_RX.match(parts[1])):
            caller = None
            dropped += 1
    counts = {}
    raw_counts = p.get("counts")
    if isinstance(raw_counts, dict):
        for k, v in raw_counts.items():
            if len(counts) < SE_MAX_ENTRIES and isinstance(k, str) and SE_COUNT_KEY_RX.match(k) and _se_int(v):
                counts[k] = v
            else:
                dropped += 1
    elif raw_counts is not None:
        dropped += 1
    kinds = {}
    raw_kinds = p.get("kinds")
    if isinstance(raw_kinds, dict):
        for g, m in raw_kinds.items():
            if not (g in SCRIPT_EVENT_KIND_GROUPS and isinstance(m, dict)):
                dropped += 1
                continue
            sel = {}
            for kk, n in m.items():
                if kk in SCRIPT_EVENT_KINDS and _se_int(n):
                    sel[kk] = n
                else:
                    dropped += 1
            if sel:
                kinds[g] = sel
    elif raw_kinds is not None:
        dropped += 1
    return script, req["step"], req["code"], outcome, event_id, caller, counts, kinds, dropped
# MUTATION_CONTROL_END: script-event-field-selection

if payload.get("kind") == "script_event":
    se_script, se_step, se_code, se_outcome, se_event_id, se_caller, se_counts, se_kinds, se_dropped = script_event(payload)
    se_session = "".join(c for c in str(payload.get("session_id") or "") if c.isalnum() or c in ("-", "_"))[:64] or "script"
    se_success = se_outcome == "pass"
    se_score = 10 if se_success else (4 if se_outcome == "warn" else 2)
    se_bucket = "high" if se_success else ("medium" if se_outcome == "warn" else "low")
    se_version = os.environ.get("LOOMWRIGHT_PLUGIN_VERSION", "") or "unknown"
    se_agent = "script:%s:%s:%s" % (se_script, se_step, se_code)
    se_raw = {
        "schema_version": 1, "kind": "script_event", "script": se_script, "step": se_step,
        "code": se_code, "outcome": se_outcome, "counts": se_counts, "kinds": se_kinds,
        "dropped": se_dropped, "redacted": True, "plugin_version": se_version,
    }
    if se_caller:
        se_raw["caller"] = se_caller
    def se_lines(title, d):
        return ("## %s\n" % title + "".join("- %s: %s\n" % (k, d[k]) for k in sorted(d)) + "\n") if d else ""
    se_record = (
        "## Script Event\n- Script: %s\n- Step: %s\n- Outcome: %s\n- Code: %s\n%s- Plugin version: %s\n\n"
        % (se_script, se_step, se_outcome, se_code, ("- Caller: %s\n" % se_caller) if se_caller else "", se_version)
        + se_lines("Counts", se_counts)
        + "".join(se_lines("Kinds (%s)" % g, se_kinds[g]) for g in sorted(se_kinds))
        + "## Raw Data\n```json\n" + json.dumps(se_raw, indent=2, sort_keys=True) + "\n```\n"
    )
    se_open = (
        "## Telemetry thread — plugin script event, round @@ROUND@@\n"
        "- One thread per script step and code in one source repo: each repeat is a comment here, "
        "and the step's next pass closes the thread with the `telemetry:healed-in-loop` label.\n"
        "- Plugin facts only: no repo, branch, path or message text is ever sent (docs/TELEMETRY.md "
        "§\"Script events\").\n\n"
    ) + se_record
    se_round = "## Round @@ROUND@@\n\n" + se_record
    se_close = (
        "## Round @@ROUND@@ — step passed, thread closed\n"
        "- `%s %s` passed after @@ROUND@@ recorded round(s).\n\n" % (se_script, se_step)
    ) + se_record
    se_title = "[Telemetry] %s %s: %s" % (se_script, se_step, se_code)
    se_labels = ["telemetry", "telemetry:script-event", "script:" + se_script, "outcome:" + se_outcome]
    for _txt in (se_open, se_round, se_close, se_title, " ".join(se_labels)):
        _hit = scan_for_secret(_txt)
        if _hit:
            sys.stderr.write("PRIVACY_BLOCKED pattern=%s\n" % _hit)
            emit("EXIT_CODE", 2)
            sys.exit(0)
    se_rec = {
        "agent": se_agent, "group": "script:%s:%s" % (se_script, se_step), "schema": "SCRIPT_EVENT",
        "success": se_success, "score_int": se_score, "score_bucket": se_bucket, "status": se_outcome,
        "round_id": hashlib.sha256(("script::%s::%s" % (se_session, se_event_id)).encode("utf-8")).hexdigest(),
        "round_total": 0 if se_success else 1, "session": se_session, "title": se_title,
        "labels": sorted(se_labels), "open_text": se_open, "round_text": se_round, "close_text": se_close,
    }
    for _k, _v in (("SCHEMA", "SCRIPT_EVENT"), ("AGENT_NORM", se_agent), ("TASK_ID", se_session),
                   ("SCORE_INT", se_score), ("SCORE_BUCKET", se_bucket), ("STATUS", se_outcome),
                   ("SUCCESS", se_success), ("ROUND_ID", se_rec["round_id"]), ("SESSION_ID", se_session)):
        emit(_k, _v)
    emit("ROUND_RECORD_HEX", json.dumps(se_rec, sort_keys=True).encode("utf-8").hex())
    emit("EXIT_CODE", 0)
    sys.stdout.flush()
    sys.exit(0)

def _token(v):
    if not isinstance(v, str):
        return ""
    return "".join(c for c in v if c.isalnum() or c in ("-", "_"))

session_id = _token(payload.get("session_id", "") or "")
agent_id = _token(payload.get("agent_id", "") or "")

agent_type = payload.get("agent_type", "") or ""
if not isinstance(agent_type, str):
    agent_type = ""

# ---- Resolve the finishing subagent's output text + its block --------------
# The SAME ladder the validators use (result_block_parser.resolve_payload_text:
# inline last_assistant_message / result_block / output / agent_output, the
# SubagentHandback message when the inline text is only a recap that names
# the block, then the transcripts), and the SAME locator (the last block wins).
result_text = rbp.resolve_payload_text(payload, SCHEMA_NAMES)
if not isinstance(result_text, str):
    result_text = ""
schema, block = (None, None)
if result_text:
    schema, block = rbp.find_last_named_block(result_text, SCHEMA_NAMES)
if schema is None:
    fail("unknown_payload_skipped", "no_known_result_block", 5)

# ---- Raw privacy scan — FIRST, before any verdict or skip ------------------
# Walk every string field of payload (1 level deep) for raw secrets — EXCEPT
# the runtime's transport metadata. Claude Code always sets `cwd`,
# `transcript_path`, `agent_transcript_path` and `scratchpad_dir` to absolute
# paths, so on macOS/Linux they ALWAYS match the home-path patterns; scanning
# them blocked 100% of real events (4,580 PRIVACY_BLOCKED, 0 sent, 2026-05 ..
# 2026-09). None of them is ever copied into the issue. Every OTHER string
# field stays scanned (fail-closed default for any field a future runtime
# adds). The RESOLVED result text is scanned too: when it came from a
# transcript it is not a top-level payload field.
TRANSPORT_KEYS = frozenset((
    "cwd", "transcript_path", "agent_transcript_path", "scratchpad_dir",
    "hook_event_name", "permission_mode", "agent_id", "prompt_id",
))
raw_hit = ""
for k, v in payload.items():
    if k in TRANSPORT_KEYS:
        continue
    if isinstance(v, str):
        h = scan_for_secret(v, skip=HOME_PATH_LABELS)
        if h:
            raw_hit = h
            break
if not raw_hit:
    raw_hit = scan_for_secret(result_text, skip=HOME_PATH_LABELS)
if raw_hit:
    sys.stderr.write("PRIVACY_BLOCKED pattern=%s\n" % raw_hit)
    emit("EXIT_CODE", 2)
    sys.exit(0)

# ---- Sibling-validator verdict on the SAME payload -------------------------
# The validator and this core are sibling commands in one SubagentStop group,
# so neither sees the other's result and their order is not something to rely
# on. A stop the validator BLOCKS is not final: the runtime feeds the reason
# back and the agent re-emits — recording the rejected attempt posted it twice
# (#422/#423, #461/#462) and posted the rejected text mis-parsed (`- [HIGH] >-`).
# So the core asks the validator itself, on the bytes it was given, and skips
# a rejected stop; the accepted retry is the one recorded.
# MUTATION_CONTROL_BEGIN: sibling-validator-verdict
def sibling_verdict(schema_name, payload_text):
    path = os.path.join(CORE_DIR, SIBLING_VALIDATORS.get(schema_name, ""))
    if not os.path.isfile(path):
        return "unavailable"
    try:
        cp = subprocess.run([sys.executable, "-I", path], input=payload_text,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            universal_newlines=True, timeout=30)
    except Exception:
        return "unavailable"
    lines = [l for l in (cp.stdout or "").splitlines() if l.strip()]
    try:
        decision = json.loads(lines[-1]) if lines else None
    except ValueError:
        decision = None
    if not isinstance(decision, dict):
        return "unavailable"
    if decision.get("decision") == "block":
        return "rejected"
    return "accepted"

verdict = sibling_verdict(schema, raw)
if verdict == "rejected":
    fail("filter_skipped", "validator_rejected schema=%s" % schema, 5)
if verdict == "unavailable":
    sys.stderr.write("validator_unavailable schema=%s\n" % schema)
# MUTATION_CONTROL_END: sibling-validator-verdict

# ---- Parse the block with the shared parser --------------------------------
fields, parse_errors = rbp.parse_block(block)
if parse_errors:
    # The validator rejects this too (load_block); reaching here means it was
    # unavailable. Never score a block the shared parser cannot read.
    fail("filter_skipped", "unparseable_block schema=%s" % schema, 5)

# ---- Typed reads over the PARSED fields ------------------------------------
def ftext(key):
    v = fields.get(key)
    if isinstance(v, (list, dict)):
        return ""
    return rbp.as_text(v).strip()

def fint(key, default=0):
    v = ftext(key)
    if not v:
        return default
    try:
        return int(v)
    except ValueError:
        try:
            return int(float(v))
        except ValueError:
            return default

def ffloat(key, default=0.0):
    v = ftext(key)
    if not v:
        return default
    try:
        return float(v)
    except ValueError:
        return default

def flist(key):
    v = fields.get(key)
    return v if isinstance(v, list) else []

def count_or_list(key):
    """`key: <int>` or `key: [a, b]` -> (count, items). Missing/unparseable -> (0, [])."""
    v = fields.get(key)
    if isinstance(v, list):
        items = [rbp.as_text(x).strip() for x in v if x is not None and rbp.as_text(x).strip()]
        return (len(items), items)
    return (fint(key, 0), [])

def clamp(s):
    if s < 0:
        return 0.0
    if s > 10:
        return 10.0
    return s

def round_half_up_int(s):
    # Round half up to nearest integer (Python's bankers' rounding would round
    # 0.5 to 0, which is wrong for our spec).
    import math
    return int(math.floor(s + 0.5))

# ---------------------------------------------------------------------------
# Score functions (deterministic; same input -> same output).
# ---------------------------------------------------------------------------

def score_supervisor():
    """Rubric A — SUPERVISOR_RESULT."""
    status = ftext("status").lower()
    heal_decision = ftext("heal_decision").upper()
    heal_remaining = fint("heal_remaining_issues", 0)
    sf_count, sf_list = count_or_list("subtasks_failed")

    base_deducted_for_remaining = False
    if status == "completed" and heal_decision == "PASS" and heal_remaining == 0:
        base = 9.0
    elif status == "completed" and heal_decision == "PASS" and heal_remaining > 0:
        base = 7.0
        base_deducted_for_remaining = True  # base already accounts for it.
    elif status == "completed_with_escalation":
        base = 5.0
    elif status == "checkpoint":
        base = 4.0
    elif status == "failed":
        base = 2.0
    else:
        base = 3.0
        sys.stderr.write("score_default_used schema=SUPERVISOR_RESULT status=%s\n" % status)

    base -= 0.5 * sf_count
    if heal_remaining > 0 and not base_deducted_for_remaining:
        delta = -0.25 * heal_remaining
        if delta < -1.0:
            delta = -1.0
        base += delta

    primary_error = ""
    if sf_list:
        primary_error = sf_list[0]
    elif heal_decision and heal_decision != "PASS":
        primary_error = heal_decision
    success = (status == "completed" and heal_decision == "PASS")
    return clamp(base), status, primary_error, success

def parsed_review_issues():
    """CODE_REVIEW_RESULT `issues` as parsed by the shared parser — every
    category, `drift` included. Order-independent by construction."""
    out = []
    for it in flist("issues"):
        if not isinstance(it, dict):
            continue
        out.append({
            "severity": rbp.as_text(it.get("severity")).strip().upper(),
            "category": rbp.as_text(it.get("category")).strip().lower(),
            "description": rbp.as_text(it.get("description")).strip(),
            "drift_kind": rbp.as_text(it.get("drift_kind")).strip().lower(),
        })
    return out

def score_code_review(parsed):
    """Rubric B — CODE_REVIEW_RESULT."""
    decision = ftext("decision").upper()

    def n(sev, cat):
        return sum(1 for i in parsed if i["severity"] == sev and i["category"] == cat)

    new_blocking, new_high = n("BLOCKING", "new"), n("HIGH", "new")
    new_medium, new_low = n("MEDIUM", "new"), n("LOW", "new")
    drift_total = sum(1 for i in parsed if i["category"] == "drift")

    if decision == "PASS" and new_blocking == 0 and new_high == 0:
        base = 9.0
    elif decision == "PASS" and (new_medium > 0 or new_low > 0) and new_blocking == 0 and new_high == 0:
        base = 7.0
    elif decision == "NEEDS_HUMAN":
        base = 4.0
    elif decision == "FAIL":
        base = 2.0
    else:
        base = 3.0
        sys.stderr.write("score_default_used schema=CODE_REVIEW_RESULT decision=%s\n" % decision)

    base += -1.0 * new_blocking
    base += -0.5 * new_high
    base += -0.25 * drift_total

    # Primary error (LOCAL dedup input only — never posted): the first new
    # BLOCKING/HIGH description, else the first drift BLOCKING/HIGH one.
    primary_error = ""
    for cat in ("new", "drift"):
        for sev_pref in ("BLOCKING", "HIGH"):
            for issue in parsed:
                if issue["severity"] == sev_pref and issue["category"] == cat and issue["description"]:
                    primary_error = issue["description"].splitlines()[0]
                    break
            if primary_error:
                break
        if primary_error:
            break

    success = (decision == "PASS")
    return clamp(base), decision.lower(), primary_error, success

def qa_failing_tests():
    n = len([x for x in flist("failing_tests") if x is not None])
    if ftext("failing_test"):
        n += 1
    return n

def score_qa():
    """Rubric C — QA_RESULT."""
    tg = fint("tests_generated", 0)
    tp = fint("tests_passed", 0)
    coverage = ffloat("coverage_estimate", 0.0)
    gates_passed = fint("self_check_gates_passed", 5)

    if tg == 0:
        # Per spec: filter_skipped upstream. Signal that to bash.
        fail("filter_skipped", "tests_generated_zero", 5)

    r = float(tp) / float(tg) if tg > 0 else 0.0
    if r >= 1.0:
        base = 9.0
    elif r >= 0.9:
        base = 7.0
    elif r >= 0.7:
        base = 5.0
    else:
        base = 3.0
    if coverage < 0.5:
        base += -1.0
    if gates_passed < 5:
        base += -0.5 * (5 - gates_passed)

    primary_error = ftext("failing_test")
    if not primary_error:
        ft = [rbp.as_text(x).strip() for x in flist("failing_tests") if x is not None]
        primary_error = ft[0] if ft else ""
    success = (tp == tg and gates_passed >= 5)
    return clamp(base), "qa", primary_error, success

# ---- Run scoring -----------------------------------------------------------
review_issues = parsed_review_issues() if schema == "CODE_REVIEW_RESULT" else []
if schema == "SUPERVISOR_RESULT":
    score_f, status, primary_error, success = score_supervisor()
elif schema == "CODE_REVIEW_RESULT":
    score_f, status, primary_error, success = score_code_review(review_issues)
else:
    score_f, status, primary_error, success = score_qa()

if score_f < 4:
    bucket = "low"
elif score_f < 8:
    bucket = "medium"
else:
    bucket = "high"
score_int = round_half_up_int(score_f)

# ---- task_id (from result block; fallback to session_id) — LOCAL only ------
task_id = ftext("task_id") or session_id or "unknown"

# ---- Normalised agent type for labels --------------------------------------
def normalise_agent(at, schema):
    s = at or ""
    # Strip plugin prefix — EVERY leading occurrence: the runtime reports
    # plugin agents doubled (`loomwright:loomwright:code-reviewer`, observed
    # in a live SubagentStop payload 2026-09-27), and stripping only one left
    # `loomwright:code-reviewer` in the issue title and `task:` label.
    while s.startswith("loomwright:"):
        s = s[len("loomwright:"):]
    if s.endswith("-runner"):
        s = s[:-len("-runner")]
    if not s:
        if schema == "SUPERVISOR_RESULT":
            s = "supervisor"
        elif schema == "CODE_REVIEW_RESULT":
            s = "code-reviewer"
        else:
            s = "qa-executor"
    return s

agent_norm = normalise_agent(agent_type, schema)

# ---- Issues Detected lines + counts -----------------------------------------
# PLUGIN FACTS ONLY, NEVER PROJECT CONTENT (docs/TELEMETRY.md §"Privacy
# whitelist"). The issue lands in a repo the user chose — often PUBLIC, and
# user-scope consent can route ANY source repo there — so nothing read out of
# the project's own text is ever posted: no finding description, subtask name,
# failing-test name, task id, repo name, PR number, branch, file path or line
# number. Every Issues Detected line below is built from a fixed template plus
# integers and plugin enums; the free-text values are only COUNTED.
PLUGIN_ENUM_RX = re.compile(r"^[A-Z][A-Z_]{0,31}$")
DRIFT_KIND_RX = re.compile(r"^[a-z][a-z_]{0,31}$")
SEVERITIES = ("BLOCKING", "HIGH", "MEDIUM", "LOW")
CATEGORIES = ("new", "pre_existing", "nit", "drift")
issues = []
if schema == "SUPERVISOR_RESULT":
    sf_count, sf_list = count_or_list("subtasks_failed")
    if sf_list:
        # One line per failed subtask (the per-line count feeds
        # issues_by_severity.unspecified below); the subtask NAME is project
        # content and is not sent.
        issues.extend(["subtask_failed"] * len(sf_list))
    elif sf_count > 0:
        issues.append("subtasks_failed=%d" % sf_count)
    hd = ftext("heal_decision").upper()
    if hd and hd != "PASS":
        issues.append("heal_decision=" + (hd if PLUGIN_ENUM_RX.match(hd) else "OTHER"))
elif schema == "CODE_REVIEW_RESULT":
    # One line per BLOCKING + HIGH `new` or `drift` issue: severity, category
    # and the drift_kind enum only — the description is project content.
    for sev in ("BLOCKING", "HIGH"):
        for issue in review_issues:
            if issue["severity"] != sev:
                continue
            if issue["category"] == "new":
                # MUTATION_CONTROL_BEGIN: no-project-text-findings
                issues.append("[%s] new finding" % sev)
                # MUTATION_CONTROL_END: no-project-text-findings
            elif issue["category"] == "drift":
                kind = issue["drift_kind"]
                issues.append("[%s] drift finding (%s)" % (sev, kind if DRIFT_KIND_RX.match(kind) else "other"))
    if ftext("decision").upper() == "FAIL" and not issues:
        # Truthful empty FAIL: say so instead of rendering nothing.
        issues.append("no BLOCKING/HIGH new or drift finding was parsed (counts below)")
else:  # QA_RESULT
    failing_count = qa_failing_tests()
    if failing_count:
        # The test NAMES are project content; only their number is sent.
        issues.append("failing_tests=%d" % failing_count)
    tg = fint("tests_generated", 0)
    tp = fint("tests_passed", 0)
    if tg > 0 and tp < tg:
        issues.append("tests_failed=%s/%s" % (tg - tp, tg))

# Issues per severity — a STRUCTURED count for raw_data, computed from the
# PARSED result, never from the rendered lines above: CODE_REVIEW_RESULT
# counts every parsed issue (all four categories, so a drift-only FAIL is no
# longer posted as zero findings — #373/#378) and also splits by category;
# the other schemas have no severity concept, so their lines count as
# "unspecified".
issues_by_severity = {"blocking": 0, "high": 0, "medium": 0, "low": 0, "unspecified": 0}
issues_by_category = None
# MUTATION_CONTROL_BEGIN: count-from-parsed-findings
if schema == "CODE_REVIEW_RESULT":
    issues_by_category = {"new": 0, "pre_existing": 0, "nit": 0, "drift": 0, "other": 0}
    for issue in review_issues:
        sev = issue["severity"].lower() if issue["severity"] in SEVERITIES else "unspecified"
        issues_by_severity[sev] += 1
        cat = issue["category"] if issue["category"] in CATEGORIES else "other"
        issues_by_category[cat] += 1
else:
    issues_by_severity["unspecified"] = len(issues)
# MUTATION_CONTROL_END: count-from-parsed-findings
round_total = sum(issues_by_severity.values())

# Tools Used — a tool / skill name is a plugin fact; anything that is not a
# bare name token (a path, a file name, a sentence, a URL) is project content
# and is dropped. No `.` and no `/`: tool and skill names (`Read`,
# `loomwright:review-heal`, `mcp__srv__tool`) never need them, file names and
# URLs always do.
TOOL_NAME_RX = re.compile(r"^[A-Za-z][A-Za-z0-9_:-]{0,63}$")
_tool_src = flist("tools_used") if "tools_used" in fields else flist("skills_used")
tools = [rbp.as_text(t).strip() for t in _tool_src if t is not None]
tools = [t for t in tools if TOOL_NAME_RX.match(t)]

# ---- Labels (applied when a thread is OPENED) -------------------------------
labels = ["telemetry", "score:" + bucket, "task:" + agent_norm]

# ---- Raw Data (plugin facts only) ------------------------------------------
# PRIVACY IS FIELD SELECTION, NOT REGEX MATCHING (red-team-hardening item 08,
# Fix 3; tightened by triage PR-1): `raw_data` ships plugin facts only —
# schema/agent/version, status enum, score, per-severity (and, for reviews,
# per-category) counts and tool names. No free-text field from the result
# block is shipped: not the result_block, not primary_error, not task_id.
# PRIVACY_PATTERNS stays a SECONDARY tripwire on the rendered text, not the
# privacy boundary itself.
plugin_version = os.environ.get("LOOMWRIGHT_PLUGIN_VERSION", "") or "unknown"
status_out = status if (not status or re.fullmatch(r"[a-z_]{1,40}", status)) else "other"
raw_data = {
    "schema_version": 1,
    "agent_type": agent_norm,
    "schema": schema,
    "score": score_int,
    "score_float": round(score_f, 2),
    "score_bucket": bucket,
    "status": status_out,
    "issues": issues_by_severity,
    "tools": tools,
    "redacted": True,
    "plugin_version": plugin_version,
}
if issues_by_category is not None:
    raw_data["issues_by_category"] = issues_by_category
# The user-scope `include_result_block: true` key is INERT: the result_block
# is project content, and no consent key can re-enable it.
if os.environ.get("LOOMWRIGHT_INCLUDE_RESULT_BLOCK", "") == "true":
    sys.stderr.write("include_result_block_ignored reason=plugin_facts_only\n")
raw_data_json = json.dumps(raw_data, indent=2, sort_keys=True)

# ---- Render the three texts a round can become ------------------------------
# Stage 2 picks one (open / comment / close) and fills the two placeholders
# with integers it reads from the user-scope thread map (round number, and
# the per-round finding totals) — digits and commas only, so the privacy scan
# below covers every byte that can be posted.
def section(title, lines):
    if not lines:
        return ""
    return "## " + title + "\n" + "\n".join("- " + l for l in lines) + "\n\n"

def record(with_suggestions):
    out = []
    out.append("## Task Summary\n")
    out.append("- Task Type: %s\n" % agent_norm)
    out.append("- Success: %s\n" % ("true" if success else "false"))
    out.append("- Score: %s/10\n" % score_int)
    out.append("- Bucket: %s\n\n" % bucket)
    if issues:
        out.append(section("Issues Detected", issues))
    if with_suggestions:
        out.append("## AI Suggestions\n")
        out.append("- (placeholder — automatic suggestion synthesis is future work; see docs/TELEMETRY.md §Future Work)\n\n")
    if tools:
        out.append(section("Tools Used", tools))
    out.append("## Raw Data\n")
    out.append("```json\n")
    out.append(raw_data_json + "\n")
    out.append("```\n")
    return "".join(out)

open_text = (
    "## Telemetry thread — round @@ROUND@@\n"
    "- One thread per review target: each later round is a comment here, and a "
    "final success closes the thread with the `telemetry:healed-in-loop` label.\n"
    "- A non-pass round is the loop working (a reviewer FAIL is the reviewer doing "
    "its job); read the thread as one loop, not as separate defects.\n\n"
) + record(True)
round_text = "## Round @@ROUND@@\n\n" + record(False)
close_text = (
    "## Round @@ROUND@@ — loop closed\n"
    "- Final verdict: %s\n"
    "- Rounds recorded: @@ROUND@@\n"
    "- Findings per round (all severities): @@SERIES@@\n"
    "- Per-finding outcomes (fixed / dismissed / deferred): not recorded — this "
    "stop does not carry them (docs/TELEMETRY.md §\"Posting policy\")\n\n"
) % (status_out or "pass") + record(False)

open_text = redact_home_paths(open_text)
round_text = redact_home_paths(round_text)
close_text = redact_home_paths(close_text)

# ---- Privacy scan (final) on every text that can be posted ------------------
title = "[Telemetry] %s thread" % agent_norm
for _txt in (open_text, round_text, close_text, title, " ".join(labels)):
    body_hit = scan_for_secret(_txt)
    if body_hit:
        sys.stderr.write("PRIVACY_BLOCKED pattern=%s\n" % body_hit)
        emit("EXIT_CODE", 2)
        sys.exit(0)

# ---- Round identity (LOCAL only — dedup inside a thread) --------------------
# A stop is one round. Its identity is the finishing subagent's agent_id within
# the session when the runtime supplies one (every current SubagentStop does);
# otherwise the legacy content hash sha256(task_id::bucket::primary_error).
legacy_hash = hashlib.sha256(("%s::%s::%s" % (task_id, bucket, primary_error)).encode("utf-8")).hexdigest()
if agent_id:
    round_id = hashlib.sha256(("agent::%s::%s" % (session_id, agent_id)).encode("utf-8")).hexdigest()
else:
    round_id = legacy_hash

round_record = {
    "agent": agent_norm,
    "schema": schema,
    "success": bool(success),
    "score_int": score_int,
    "score_bucket": bucket,
    "status": status,
    "round_id": round_id,
    "round_total": round_total,
    "session": session_id,
    "title": title,
    "labels": sorted(labels),
    "open_text": open_text,
    "round_text": round_text,
    "close_text": close_text,
}

# ---- Emit results ---------------------------------------------------------
emit("SCHEMA", schema)
emit("AGENT_NORM", agent_norm)
emit("TASK_ID", task_id)
emit("SCORE_INT", score_int)
emit("SCORE_BUCKET", bucket)
emit("STATUS", status)
emit("SUCCESS", success)
emit("ROUND_ID", round_id)
emit("SESSION_ID", session_id)
# Multi-line record: hex (NOT base64 — base64 padding uses `=`, which collides
# with our `key=value` line-protocol separator). Hex carries no IFS character.
emit("ROUND_RECORD_HEX", json.dumps(round_record, sort_keys=True).encode("utf-8").hex())
emit("EXIT_CODE", 0)  # 0 means "stage 1 OK; bash continues to consent/repo/thread"
PY

STAGE1_OUT="$(printf '%s' "$INPUT" | python3 -I -c "$STAGE1_PY")"
STAGE1_RC=$?

if [ $STAGE1_RC -ne 0 ]; then
  printf 'stage1_python_failed rc=%s\n' "$STAGE1_RC" >&2
  exit 1
fi

# ---- Parse stage 1 output (line-protocol key=value) -------------------------
SCHEMA=""
AGENT_NORM=""
TASK_ID=""
SCORE_INT=""
SCORE_BUCKET=""
STATUS=""
SUCCESS=""
ROUND_ID=""
SESSION_ID=""
ROUND_RECORD_HEX=""
EXIT_CODE=""

while IFS='=' read -r k v; do
  case "$k" in
    SCHEMA) SCHEMA="$v" ;;
    AGENT_NORM) AGENT_NORM="$v" ;;
    TASK_ID) TASK_ID="$v" ;;
    SCORE_INT) SCORE_INT="$v" ;;
    SCORE_BUCKET) SCORE_BUCKET="$v" ;;
    STATUS) STATUS="$v" ;;
    SUCCESS) SUCCESS="$v" ;;
    ROUND_ID) ROUND_ID="$v" ;;
    SESSION_ID) SESSION_ID="$v" ;;
    ROUND_RECORD_HEX) ROUND_RECORD_HEX="$v" ;;
    EXIT_CODE) EXIT_CODE="$v" ;;
  esac
done <<EOF
$STAGE1_OUT
EOF

if [ -z "$EXIT_CODE" ]; then
  printf 'stage1_no_exit_code\n' >&2
  exit 1
fi

# Stage 1 may signal early exit (privacy_blocked=2, parser_unavailable=1,
# json_parse_failed/empty/no block/validator_rejected/unparseable_block/QA
# tests_generated==0 = 5). The interest filter is NOT in stage 1 — it runs in
# stage 2, after consent + target-repo resolution, because it depends on
# whether the review target already has an open thread.
if [ "$EXIT_CODE" != "0" ]; then
  if [ "$DRY_RUN" = "true" ]; then
    printf -- '--- DRY RUN ---\n'
    printf 'stage1_early_exit=%s\n' "$EXIT_CODE"
    printf 'WOULD_EXIT=%s\n' "$EXIT_CODE"
    exit 0
  fi
  exit "$EXIT_CODE"
fi

# ---- Resolve consent + target repo (USER-SCOPE ONLY) --------------------------
# red-team-hardening item 02: a repo-relative telemetry-consent.json can only
# ever REQUEST a target repo — it can never grant consent or choose a
# destination on its own. See resolve-egress-config.sh and
# docs/TELEMETRY.md §"Consent flow".
# MUTATION_CONTROL_BEGIN: resolve-egress-config-integration
CONSENT_DECISION="missing"
TELEMETRY_REPO_FROM_CONSENT=""
EGRESS_REPO_SLUG=""
EGRESS_REPO_REQUESTED_TELEMETRY_REPO=""

RESOLVER_SCRIPT="${CORE_SELF_DIR}/resolve-egress-config.sh"
if [ -n "$CORE_SELF_DIR" ] && [ -f "$RESOLVER_SCRIPT" ]; then
  RESOLVER_OUT="$(bash "$RESOLVER_SCRIPT" 2>/dev/null || true)"
  while IFS='=' read -r rk rv; do
    case "$rk" in
      REPO_SLUG) EGRESS_REPO_SLUG="$rv" ;;
      TELEMETRY) [ -n "$rv" ] && CONSENT_DECISION="$rv" ;;
      TELEMETRY_REPO) TELEMETRY_REPO_FROM_CONSENT="$rv" ;;
      REPO_REQUESTED_TELEMETRY_REPO) EGRESS_REPO_REQUESTED_TELEMETRY_REPO="$rv" ;;
    esac
  done <<EOF
$RESOLVER_OUT
EOF
fi

# A repo-relative request that does not byte-match the user-scope entry for
# this slug (including "no user-scope entry at all" — the planted-file
# reproduction) is ignored; TELEMETRY_REPO_FROM_CONSENT above never contains
# the repo's own value in that case, this line only makes the refusal visible.
if [ -n "$EGRESS_REPO_REQUESTED_TELEMETRY_REPO" ] && [ "$EGRESS_REPO_REQUESTED_TELEMETRY_REPO" != "$TELEMETRY_REPO_FROM_CONSENT" ]; then
  printf 'repo_consent_ignored slug=%s\n' "$EGRESS_REPO_SLUG" >&2
fi
# MUTATION_CONTROL_END: resolve-egress-config-integration

case "$CONSENT_DECISION" in
  always_allow)
    : # proceed
    ;;
  no)
    # User has explicitly opted out — emit `denied — skipped` marker so the
    # wrapper can distinguish this from an uninitialised-consent state and
    # NOT surface the "telemetry pending" notice. The wrapper still
    # rate-limits the log line via its per-session flag (brief AC §3 line 52).
    printf 'denied — skipped\n' >&2
    if [ "$DRY_RUN" = "true" ]; then
      printf -- '--- DRY RUN ---\n'
      printf 'WOULD_EXIT=3\n'
      exit 0
    fi
    exit 3
    ;;
  prompt|missing|parse_error|*)
    # Consent has never been chosen — emit `consent_uninitialised` so the
    # wrapper can surface the "telemetry pending — run /telemetry" notice
    # once per session via PENDING_FLAG_NEW.
    printf 'consent_uninitialised state=%s\n' "$CONSENT_DECISION" >&2
    if [ "$DRY_RUN" = "true" ]; then
      printf -- '--- DRY RUN ---\n'
      printf 'WOULD_EXIT=3\n'
      exit 0
    fi
    exit 3
    ;;
esac

# ---- Resolve target repo -----------------------------------------------------
TARGET_REPO="${LOOMWRIGHT_TELEMETRY_REPO:-}"
if [ -z "$TARGET_REPO" ]; then
  TARGET_REPO="$TELEMETRY_REPO_FROM_CONSENT"
fi

if [ -z "$TARGET_REPO" ]; then
  printf 'no_repo_configured\n' >&2
  if [ "$DRY_RUN" = "true" ]; then
    printf -- '--- DRY RUN ---\n'
    printf 'WOULD_EXIT=4\n'
    exit 0
  fi
  exit 4
fi

# Validate repo format owner/repo.
if ! grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' <<<"$TARGET_REPO"; then
  printf 'invalid_repo_format repo=%s\n' "$TARGET_REPO" >&2
  exit 1
fi

# ---- Review target (LOCAL ONLY — feeds the thread key, never posted) ---------
# The target is the branch under review. In order:
#   1. the checked-out branch of $PWD (inline Phase 4.5, an /automate lane, a
#      feature checkout) — unless it is the repo's default branch, where many
#      unrelated reviews happen and one shared thread would merge them;
#   2. LOOMWRIGHT_PR_HEAD_REF — dispatch-pr-review.sh exports the PR's head
#      branch into the detached drain, whose worktree is detached at the PR
#      head SHA, so a drain shares the inline review's thread;
#   3. the session id (one thread per session).
# The resolved value is hashed together with the destination, agent and source
# slug in stage 2 and stored only in the user-scope map.
# A SCRIPT event (docs/TELEMETRY.md §"Script events") is keyed by its script, step
# and code alone (its "agent"), so a repeat in any session or branch of the same
# source repo lands in the same thread.
TARGET_REF=""
if [ "$SCHEMA" = "SCRIPT_EVENT" ]; then
  TARGET_REF="script"
elif command -v git >/dev/null 2>&1; then
  _tl_branch="$(git -C "$PWD" symbolic-ref -q --short HEAD 2>/dev/null || true)"
  _tl_default="$(git -C "$PWD" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  _tl_default="${_tl_default#origin/}"
  if [ -n "$_tl_branch" ]; then
    if [ -n "$_tl_default" ]; then
      [ "$_tl_branch" != "$_tl_default" ] && TARGET_REF="branch:$_tl_branch"
    else
      case "$_tl_branch" in
        main|master) : ;;
        *) TARGET_REF="branch:$_tl_branch" ;;
      esac
    fi
  fi
fi
if [ -z "$TARGET_REF" ] && [ -n "${LOOMWRIGHT_PR_HEAD_REF:-}" ]; then
  TARGET_REF="branch:${LOOMWRIGHT_PR_HEAD_REF}"
fi
if [ -z "$TARGET_REF" ]; then
  TARGET_REF="session:${SESSION_ID:-unknown}"
fi

# ---- Stage 2: one thread per review target ----------------------------------
IFS= read -r -d '' STAGE2_PY <<'PY' || true
import errno, fcntl, hashlib, json, os, re, subprocess, sys, tempfile, time
from datetime import datetime, timezone, timedelta

def err(s):
    sys.stderr.write(s + "\n")

DRY = os.environ.get("TL_DRY_RUN") == "true"

def _stage2_crash(t, v, tb):
    err("stage2_failed reason=%s" % getattr(t, "__name__", "error"))
    if DRY:
        sys.stdout.write("--- DRY RUN ---\nWOULD_EXIT=1\n")
        sys.stdout.flush()
    os._exit(0 if DRY else 1)

sys.excepthook = _stage2_crash

def finish(code, lines=()):
    """Single exit point. --dry-run always returns 0 with a WOULD_EXIT line."""
    if DRY:
        sys.stdout.write("--- DRY RUN ---\n")
        for l in lines:
            sys.stdout.write(l + "\n")
        sys.stdout.write("WOULD_EXIT=%d\n" % code)
        sys.stdout.flush()
        sys.exit(0)
    sys.stdout.flush()
    sys.exit(code)

try:
    rec = json.loads(bytes.fromhex(sys.stdin.read().strip()).decode("utf-8"))
except Exception:
    err("stage2_bad_record")
    finish(1)

dest = os.environ.get("TL_DEST", "")
slug = os.environ.get("TL_SOURCE_SLUG", "")
target_ref = os.environ.get("TL_TARGET_REF", "")
home = os.environ.get("HOME", "")
sent_log = os.environ.get("TL_SENT_LOG", "")
task_id = os.environ.get("TL_TASK_ID", "")
lock_timeout = 30.0
try:
    lock_timeout = float(os.environ.get("LOOMWRIGHT_TELEMETRY_LOCK_TIMEOUT", "30"))
except ValueError:
    pass

if not home:
    err("thread_map_unreadable reason=no_home")
    finish(1)
MAP_DIR = os.path.join(home, ".claude", "loomwright")
MAP_PATH = os.path.join(MAP_DIR, "telemetry-threads.json")
LOCK_PATH = MAP_PATH + ".lock"
HEALED_LABEL = "telemetry:healed-in-loop"
SEEN_CAP = 200
CLOSED_TTL = timedelta(days=30)

# The thread key: computed here, stored in the map, never posted. The issue's
# title and body carry no repo, branch or PR — only the agent and plugin facts.
KEY = hashlib.sha256("\0".join(("v1", dest, rec["agent"], slug, target_ref)).encode("utf-8")).hexdigest()
# A script event's GROUP (script + step, docs/TELEMETRY.md §"Script events"): every
# code-thread of one step in one source repo carries the same hashed group key, so
# the step's next pass closes all of them. Agent results have no group.
GROUP_KEY = ""
if rec.get("group"):
    GROUP_KEY = hashlib.sha256("\0".join(("v1-group", dest, rec["group"], slug)).encode("utf-8")).hexdigest()

class Unreadable(Exception):
    pass

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# MUTATION_CONTROL_BEGIN: thread-map-unreadable-fails-safe
def load_map():
    """Missing file -> empty map (first use). Anything else that cannot be read
    back as a schema_version 1 map -> Unreadable: post NOTHING, because an empty
    reading could open a second issue for a target that already has a thread."""
    try:
        with open(MAP_PATH, "r", encoding="utf-8") as fh:
            doc = json.load(fh)
    except FileNotFoundError:
        return {"schema_version": 1, "threads": {}}
    except Exception as e:
        raise Unreadable(type(e).__name__)
    if not isinstance(doc, dict) or doc.get("schema_version") != 1 or not isinstance(doc.get("threads"), dict):
        raise Unreadable("bad_shape")
    return doc
# MUTATION_CONTROL_END: thread-map-unreadable-fails-safe

def save_map(doc):
    """Atomic replace: write a same-dir temp file, fsync, rename over the map."""
    cutoff = datetime.now(timezone.utc) - CLOSED_TTL
    for k in list(doc["threads"].keys()):
        t = doc["threads"][k]
        if t.get("state") != "open":
            try:
                ts = datetime.fromisoformat(str(t.get("updated_at", "")).replace("Z", "+00:00"))
            except ValueError:
                ts = None
            if ts is None or ts < cutoff:
                del doc["threads"][k]
    fd, tmp = tempfile.mkstemp(prefix=".telemetry-threads.", suffix=".tmp", dir=MAP_DIR)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(doc, fh, indent=2, sort_keys=True)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, 0o600)
        os.replace(tmp, MAP_PATH)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

def decide(doc):
    """Return (action, thread) — action in open|comment|close|close_group|skip_interest|skip_dedup.
    close_group's thread is a list of (key, thread) pairs: every open thread of the group."""
    # MUTATION_CONTROL_BEGIN: script-event-group-close
    if rec["success"] and GROUP_KEY:
        members = [(k, t) for k, t in sorted(doc["threads"].items())
                   if isinstance(t, dict) and t.get("state") == "open" and t.get("dest") == dest
                   and t.get("group_key") == GROUP_KEY and isinstance(t.get("issue"), int)
                   and rec["round_id"] not in (t.get("seen") or [])]
        if members:
            return "close_group", members
        return "skip_interest", None
    # MUTATION_CONTROL_END: script-event-group-close
    t = doc["threads"].get(KEY)
    open_t = t if (isinstance(t, dict) and t.get("state") == "open"
                   and t.get("dest") == dest and isinstance(t.get("issue"), int)) else None
    if open_t is not None and rec["round_id"] in (open_t.get("seen") or []):
        return "skip_dedup", open_t
    if rec["success"]:
        if open_t is not None:
            return "close", open_t
        if int(rec["score_int"]) >= 5:
            return "skip_interest", None
        return "open", None
    return ("comment", open_t) if open_t is not None else ("open", None)

def text_for(action, thread):
    rounds = int(thread.get("rounds", 0)) + 1 if thread else 1
    series = list(thread.get("series", [])) if thread else []
    series.append(int(rec["round_total"]))
    src = {"open": rec["open_text"], "comment": rec["round_text"], "close": rec["close_text"],
           "close_group": rec["close_text"]}[action]
    txt = src.replace("@@ROUND@@", str(rounds)).replace("@@SERIES@@", ", ".join(str(n) for n in series))
    return txt, rounds, series

def gh(args, body=None):
    """Run gh; returns (rc, stdout). The body goes through a private temp file."""
    path = None
    try:
        if body is not None:
            fd, path = tempfile.mkstemp(prefix="telemetry-body.", suffix=".md")
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(body)
            args = args + ["--body-file", path]
        cp = subprocess.run(["gh"] + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            universal_newlines=True, timeout=60)
        return cp.returncode, (cp.stdout or "") + (cp.stderr or "")
    except Exception as e:
        return 127, type(e).__name__
    finally:
        if path:
            try:
                os.unlink(path)
            except OSError:
                pass

def sent_line(action, url):
    if not sent_log:
        return
    try:
        with open(sent_log, "a", encoding="utf-8") as fh:
            fh.write("%s\t%s\t%s\t%s\t%s\t%s\t%s\n" % (
                now_iso(), rec["round_id"], task_id, rec["score_int"], rec["score_bucket"], url, action))
    except OSError:
        pass

def skip(action):
    if action == "skip_interest":
        err("filter_skipped reason=interest_filter score=%s status=%s" % (rec["score_int"], rec["status"]))
    else:
        err("dedup_hit hash=%s" % rec["round_id"])
    finish(5)

# ---- --dry-run: read the map, report the would-be action, write nothing ------
if DRY:
    try:
        doc = load_map()
    except Unreadable as e:
        err("thread_map_unreadable reason=%s — posting nothing (an empty reading could duplicate a thread)" % e)
        finish(1)
    action, thread = decide(doc)
    if action.startswith("skip_"):
        skip(action)
    if action == "close_group":
        lines = ["TARGET_REPO=%s" % dest, "THREAD_ACTION=close_group", "THREAD_COUNT=%d" % len(thread),
                 "TITLE=%s" % rec["title"], "LABELS:", "  - %s" % HEALED_LABEL]
        for _k, _t in thread:
            _txt, _r, _s = text_for("close_group", _t)
            lines.append("ISSUE=%d" % _t["issue"])
            lines.append("BODY_BEGIN\n%sBODY_END" % _txt)
        finish(0, lines)
    txt, rounds, _series = text_for(action, thread)
    lines = ["TARGET_REPO=%s" % dest,
             "THREAD_ACTION=%s" % action,
             "THREAD_ROUND=%d" % rounds,
             "TITLE=%s" % rec["title"],
             "SCORE=%s" % rec["score_int"],
             "BUCKET=%s" % rec["score_bucket"],
             "LABELS:"]
    if action == "open":
        lines += ["  - %s" % l for l in rec["labels"]]
    elif action == "close":
        lines.append("  - %s" % HEALED_LABEL)
    lines.append("BODY_BEGIN\n%sBODY_END" % txt)
    finish(0, lines)

# ---- Live: read-decide-post-write under ONE exclusive lock -------------------
try:
    os.makedirs(MAP_DIR, mode=0o700, exist_ok=True)
    lock_fd = os.open(LOCK_PATH, os.O_RDWR | os.O_CREAT, 0o600)
except OSError as e:
    err("thread_map_unreadable reason=lock_open_%s — posting nothing" % type(e).__name__)
    finish(1)
# MUTATION_CONTROL_BEGIN: thread-map-lock
deadline = time.time() + lock_timeout
while True:
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except OSError as e:
        if e.errno not in (errno.EAGAIN, errno.EACCES, errno.EWOULDBLOCK):
            err("thread_map_unreadable reason=lock_%s — posting nothing" % errno.errorcode.get(e.errno, e.errno))
            finish(1)
        if time.time() >= deadline:
            err("thread_map_lock_timeout seconds=%s — posting nothing" % lock_timeout)
            finish(1)
        time.sleep(0.1)
# MUTATION_CONTROL_END: thread-map-lock

try:
    doc = load_map()
except Unreadable as e:
    err("thread_map_unreadable reason=%s — posting nothing (an empty reading could duplicate a thread)" % e)
    finish(1)

action, thread = decide(doc)
if action.startswith("skip_"):
    skip(action)

def ensure_label(name, color, desc):
    rc, _ = gh(["label", "create", name, "--repo", dest, "--force", "--color", color, "--description", desc])
    if rc != 0:
        err("label_create_failed label=%s" % name)

def close_thread(num):
    """Label + close one thread; False when the close itself failed."""
    ensure_label(HEALED_LABEL, "0e8a16", "Telemetry thread whose review loop ended in a pass")
    rc, _ = gh(["issue", "edit", str(num), "--repo", dest, "--add-label", HEALED_LABEL])
    if rc != 0:
        err("label_add_failed label=%s" % HEALED_LABEL)
    rc, _ = gh(["issue", "close", str(num), "--repo", dest, "--reason", "completed"])
    if rc != 0:
        err("gh_failed rc=%s op=issue_close" % rc)
        return False
    return True

if action == "close_group":
    # Every open code-thread of this step: closing comment, label, close. A thread
    # whose comment or close fails stays open in the map (a later pass retries it);
    # the map is saved after each one, so a failure never loses earlier closes.
    closed = 0
    failed = False
    for k, t in thread:
        txt, rounds, series = text_for("close_group", t)
        rc, _ = gh(["issue", "comment", str(t["issue"]), "--repo", dest], txt)
        if rc != 0:
            err("gh_failed rc=%s op=issue_comment" % rc)
            failed = True
            continue
        t["rounds"] = rounds
        t["series"] = series
        t["seen"] = (list(t.get("seen") or []) + [rec["round_id"]])[-SEEN_CAP:]
        t["updated_at"] = now_iso()
        if close_thread(t["issue"]):
            t["state"] = "closed"
            closed += 1
        else:
            failed = True
        doc["threads"][k] = t
        try:
            save_map(doc)
        except Exception as e:
            err("thread_map_write_failed reason=%s" % type(e).__name__)
            finish(1)
        sent_line("close", "/issues/%d" % t["issue"])
    err("thread_close_group closed=%d of=%d" % (closed, len(thread)))
    finish(1 if failed else 0)

txt, rounds, series = text_for(action, thread)

if action == "open":
    for l in rec["labels"]:
        rc, _ = gh(["label", "create", l, "--repo", dest, "--force"])
    args = ["issue", "create", "--repo", dest, "--title", rec["title"]]
    for l in rec["labels"]:
        args += ["--label", l]
    rc, out = gh(args, txt)
    if rc != 0:
        err("gh_failed rc=%s op=issue_create" % rc)
        finish(1)
    m = re.search(r"/issues/(\d+)\s*$", out.strip())
    if not m:
        # The issue may exist, but without its number no later round can find
        # it; record nothing and say so.
        err("gh_issue_url_unparsed op=issue_create")
        finish(1)
    url = m.group(0)
    doc["threads"][KEY] = {
        "dest": dest, "issue": int(m.group(1)), "state": "open",
        "rounds": rounds, "series": series, "seen": [rec["round_id"]],
        "opened_at": now_iso(), "updated_at": now_iso(),
    }
    if GROUP_KEY:
        doc["threads"][KEY]["group_key"] = GROUP_KEY
else:
    num = thread["issue"]
    rc, _ = gh(["issue", "comment", str(num), "--repo", dest], txt)
    if rc != 0:
        err("gh_failed rc=%s op=issue_comment" % rc)
        finish(1)
    thread["rounds"] = rounds
    thread["series"] = series
    thread["seen"] = (list(thread.get("seen") or []) + [rec["round_id"]])[-SEEN_CAP:]
    thread["updated_at"] = now_iso()
    url = "/issues/%d" % num
    if action == "close":
        if not close_thread(num):
            # The closing comment is posted; the thread stays open in the map so
            # a later round still lands in it and a later pass retries the close.
            try:
                save_map(doc)
            except Exception as e:
                err("thread_map_write_failed reason=%s" % type(e).__name__)
            finish(1)
        thread["state"] = "closed"
    doc["threads"][KEY] = thread

try:
    save_map(doc)
except Exception as e:
    err("thread_map_write_failed reason=%s" % type(e).__name__)
    finish(1)
sent_line(action, url)
err("thread_%s round=%d" % (action, rounds))
finish(0)
PY

if [ "$DRY_RUN" != "true" ] && ! command -v gh >/dev/null 2>&1; then
  printf 'gh_missing\n' >&2
  exit 1
fi

printf '%s' "$ROUND_RECORD_HEX" | \
  TL_DRY_RUN="$DRY_RUN" TL_DEST="$TARGET_REPO" TL_SOURCE_SLUG="${EGRESS_REPO_SLUG:-}" \
  TL_TARGET_REF="$TARGET_REF" TL_SENT_LOG="$SENT_LOG" TL_TASK_ID="$TASK_ID" \
  python3 -I -c "$STAGE2_PY"
STAGE2_RC=$?
case "$STAGE2_RC" in
  0|1|5) exit "$STAGE2_RC" ;;
  *) printf 'stage2_python_failed rc=%s\n' "$STAGE2_RC" >&2; exit 1 ;;
esac
