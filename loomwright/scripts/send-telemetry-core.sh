#!/usr/bin/env bash
# send-telemetry-core.sh — TELEMETRY CORE (Subtask #2b)
#
# Authoritative spec: loomwright/docs/TELEMETRY.md
#
# Pipeline (matches docs/TELEMETRY.md §Interest filter — privacy first, gh last,
# interest-filter runs AFTER consent + target-repo + body-privacy, BEFORE dedup;
# updated in heal iter 1 of v11.2.0 to remove the prior order-of-operations
# divergence that allowed a healthy run with a secret to be filter-skipped
# without a PRIVACY_BLOCKED audit-log entry):
#   1. Parse flags (only --dry-run supported)
#   2. Read stdin
#   3. Parse JSON (session_id, agent_type, result_block) + detect schema
#   4. Compute deterministic score per the rubric (three separate per-block tables)
#   5. Raw payload privacy scan — fail-closed exit 2 BEFORE consent so
#      privacy-blocked events always log even on healthy/successful runs.
#   6. Build prospective body (redacted) + final body privacy scan (defence
#      in depth — exit 2 again on hit).
#   7. Read consent (.supervisor/telemetry-consent.json):
#        - "no" exact         -> exit 3, stderr "denied — skipped"
#        - missing/prompt/etc -> exit 3, stderr "consent_uninitialised state=..."
#   8. Resolve target repo (env -> consent file -> exit 4)
#   9. Interest filter (skip if score >= 5 AND status in success set, exit 5)
#  10. Dedup check (sha256 of task_id::score_bucket::primary_error within 6h, exit 5)
#  11. Dry-run branch (print and exit 0 with WOULD_EXIT marker)
#  12. Live: gh issue create
#  13. Append success line to telemetry-sent.log
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
CONSENT_FILE="${PWD}/.supervisor/telemetry-consent.json"
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
    PLUGIN_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version") or "unknown")' "$PLUGIN_MANIFEST" 2>/dev/null)" || PLUGIN_VERSION="unknown"
  fi
fi
case "$PLUGIN_VERSION" in ""|null) PLUGIN_VERSION="unknown" ;; esac
export LOOMWRIGHT_PLUGIN_VERSION="$PLUGIN_VERSION"

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

# ---- Stage 1: parse JSON, detect schema, compute score, build payload --------
#
# Single python invocation that returns a `key=value` line-protocol on stdout
# so bash can keep orchestrating cleanly. All redactions and regex live inside
# python so the regex set is defined exactly once for body + raw scanning.

# Load python source into a variable so the heredoc does NOT consume stdin.
# (`python3 - <<PY` reads its code from stdin, which would clobber the JSON
# payload we need to pipe in.) Using `python3 -c "$VAR"` keeps stdin free.
IFS= read -r -d '' STAGE1_PY <<'PY' || true
import json, sys, re, os

# ---------------------------------------------------------------------------
# Privacy regex deny-list — MUST stay aligned with send-telemetry.sh wrapper
# and docs/TELEMETRY.md. The first 8 tuples are the wrapper's mapping; the 9th
# (.env-style assignment, multiline) is body-only per Subtask #2a guidance.
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

def _last_assistant_text_from_transcript(path):
    """Best-effort extraction of the LAST assistant message's text from a Claude
    Code transcript JSONL. The transcript schema is not formally documented, so
    we defensively pull `text` parts from the last assistant-role entry. Returns
    "" on any read/parse failure. Mirrors the helper of the same name in
    scripts/validate-launch-pad-result.py — keep the two in sync."""
    last_text = ""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except (json.JSONDecodeError, ValueError):
                    continue
                msg = obj.get("message") if isinstance(obj, dict) else None
                if not isinstance(msg, dict):
                    msg = obj if isinstance(obj, dict) else {}
                role = msg.get("role") or obj.get("role") or obj.get("type")
                if role != "assistant":
                    continue
                content = msg.get("content")
                texts = []
                if isinstance(content, str):
                    texts.append(content)
                elif isinstance(content, list):
                    for part in content:
                        if isinstance(part, dict) and isinstance(part.get("text"), str):
                            texts.append(part["text"])
                if texts:
                    last_text = "\n".join(texts)
    except OSError:
        return ""
    return last_text

# ---- Parse JSON ------------------------------------------------------------
try:
    raw = sys.stdin.read()
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise ValueError("payload_not_object")
except Exception as e:
    fail("unknown_payload_skipped", "json_parse_failed", 5)

session_id = payload.get("session_id", "") or ""
if not isinstance(session_id, str):
    session_id = ""
session_id = "".join(c for c in session_id if c.isalnum() or c in ("-", "_"))

agent_type = payload.get("agent_type", "") or ""
if not isinstance(agent_type, str):
    agent_type = ""

# ---- Resolve the finishing subagent's output text --------------------------
# v14.2.1 correctness fix: Claude Code SubagentStop payloads do NOT carry a
# top-level `result_block` field. Empirically (verified against a real captured
# SubagentStop payload) the subagent's final text lives in
# `last_assistant_message`; the only guaranteed fallback is the transcript
# JSONL (`agent_transcript_path` for a Task-spawned subagent — the plugin's
# code-reviewer / qa-executor / supervisor-runner all fire their SubagentStop
# this way — else the shared session `transcript_path`). The legacy
# `result_block` / `output` / `agent_output` field names are retained in the
# chain so existing fixtures and any future payload that re-adds them keep
# working. Mirrors scripts/validate-launch-pad-result.py.
result_block = (
    payload.get("last_assistant_message")
    or payload.get("result_block")
    or payload.get("output")
    or payload.get("agent_output")
    or ""
)
if not isinstance(result_block, str):
    result_block = ""
if not result_block:
    for _tp_key in ("agent_transcript_path", "transcript_path"):
        _tp = payload.get(_tp_key)
        if isinstance(_tp, str) and _tp and os.path.exists(_tp):
            _txt = _last_assistant_text_from_transcript(_tp)
            if _txt:
                result_block = _txt
                break

# ---- Detect schema ---------------------------------------------------------
schema = None
if "SUPERVISOR_RESULT" in result_block:
    schema = "SUPERVISOR_RESULT"
elif "CODE_REVIEW_RESULT" in result_block:
    schema = "CODE_REVIEW_RESULT"
elif "QA_RESULT" in result_block:
    schema = "QA_RESULT"
else:
    fail("unknown_payload_skipped", "no_known_result_block", 5)

# ---- Helpers to extract fields from a result block --------
# Real agents emit YAML mapping form (`  key: value`, see agents/supervisor.md
# §"Result Block" and docs/RESULT_SCHEMAS.md). The earlier fixtures use the
# bullet form (`- key: value`) — both must be supported, since the SubagentStop
# payload echoes whatever the agent printed verbatim.
def field(text, key):
    """Return first match for `key: value` or `- key: value` (case-insensitive)."""
    rx = re.compile(r"^\s*(?:-\s*)?" + re.escape(key) + r"\s*:\s*(.+?)\s*$",
                    re.MULTILINE | re.IGNORECASE)
    m = rx.search(text)
    if not m:
        return None
    return m.group(1).strip()

def field_list(text, key):
    """Parse `- key: [a, b, c]` or empty list `[]` into a Python list."""
    raw = field(text, key)
    if raw is None:
        return []
    raw = raw.strip()
    if raw.startswith("[") and raw.endswith("]"):
        inner = raw[1:-1].strip()
        if not inner:
            return []
        # Split on commas; tolerate quoted items.
        items = [x.strip().strip('"').strip("'") for x in inner.split(",")]
        return [x for x in items if x]
    # Fallback: single-value treated as one-element list.
    return [raw]

def field_int(text, key, default=0):
    v = field(text, key)
    if v is None:
        return default
    try:
        return int(v)
    except Exception:
        try:
            return int(float(v))
        except Exception:
            return default

def field_float(text, key, default=0.0):
    v = field(text, key)
    if v is None:
        return default
    try:
        return float(v)
    except Exception:
        return default

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

def parse_count_or_list(text, key):
    """Parse `key: <int>` or `key: [a, b]` and return (count, list_items).

    Schema-canonical form is integer (`subtasks_failed: 0`). Legacy bullet
    fixtures use list form (`- subtasks_failed: []` or `[BD-1, BD-2]`).
    Returns (0, []) when the field is missing or unparseable.
    """
    raw = field(text, key)
    if raw is None:
        return (0, [])
    raw = raw.strip()
    if raw.startswith("[") and raw.endswith("]"):
        inner = raw[1:-1].strip()
        if not inner:
            return (0, [])
        items = [x.strip().strip('"').strip("'") for x in inner.split(",") if x.strip()]
        return (len(items), items)
    try:
        return (int(raw), [])
    except (ValueError, TypeError):
        try:
            return (int(float(raw)), [])
        except (ValueError, TypeError):
            return (0, [])

def score_supervisor(text):
    """Rubric A — SUPERVISOR_RESULT.
    Returns (final_score_float, status, primary_error, success_bool, sub_agent_weak_label_or_empty).
    """
    status = (field(text, "status") or "").strip().lower()
    heal_decision = (field(text, "heal_decision") or "").strip().upper()
    heal_remaining = field_int(text, "heal_remaining_issues", 0)
    sf_count, sf_list = parse_count_or_list(text, "subtasks_failed")

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

    # Adjustments
    base -= 0.5 * sf_count
    if heal_remaining > 0 and not base_deducted_for_remaining:
        delta = -0.25 * heal_remaining
        if delta < -1.0:
            delta = -1.0
        base += delta

    final = clamp(base)

    # Primary error
    primary_error = ""
    if sf_list:
        primary_error = sf_list[0]
    elif heal_decision and heal_decision != "PASS":
        primary_error = heal_decision

    # Success
    success = (status == "completed" and heal_decision == "PASS")

    # Sub-agent weak label — be conservative (omit per spec note).
    weak_label = ""

    return final, status, primary_error, success, weak_label

def parse_issue_blocks(text):
    """Parse all issue blocks from a CODE_REVIEW_RESULT result block.

    Returns a list of dicts with keys severity (upper-cased), category
    (lower-cased), description, file, drift_kind. Each block's window runs
    from one `severity: …` match to the next, so field order WITHIN a block
    is irrelevant — `description` may legally appear before `category`, and
    extra optional fields (suggestion, line, drift_kind, …) may interleave.

    The schema (docs/RESULT_SCHEMAS.md v3 + hooks/hooks.json validator)
    requires the fields to exist but imposes no ordering, so this parser
    must not either.
    """
    issues = []
    sev_rx = re.compile(r"severity\s*:\s*([A-Za-z]+)", re.IGNORECASE)
    sev_matches = list(sev_rx.finditer(text))
    for i, m in enumerate(sev_matches):
        start = m.start()
        end = sev_matches[i + 1].start() if i + 1 < len(sev_matches) else len(text)
        window = text[start:end]
        sev = m.group(1).strip().upper()
        cat_m = re.search(r"category\s*:\s*([A-Za-z_]+)", window, re.IGNORECASE)
        desc_m = re.search(r"description\s*:\s*(.+?)\s*(?:\n|$)", window, re.IGNORECASE)
        file_m = re.search(r"\bfile\s*:\s*(.+?)\s*(?:\n|$)", window, re.IGNORECASE)
        drift_m = re.search(r"drift_kind\s*:\s*([A-Za-z_]+)", window, re.IGNORECASE)
        issues.append({
            "severity": sev,
            "category": (cat_m.group(1).strip().lower() if cat_m else ""),
            "description": (desc_m.group(1).strip() if desc_m else ""),
            "file": (file_m.group(1).strip() if file_m else ""),
            "drift_kind": (drift_m.group(1).strip().lower() if drift_m else ""),
        })
    return issues

def _count_severity(parsed_issues, severity):
    """Count parsed issues at the given severity, bucketed by category.
    Operates on the output of parse_issue_blocks() so it is order-independent.
    """
    counts = {"new": 0, "pre_existing": 0, "nit": 0, "drift": 0, "_total": 0}
    target = severity.upper()
    for issue in parsed_issues:
        if issue["severity"] != target:
            continue
        cat = issue["category"]
        if cat in counts:
            counts[cat] += 1
        counts["_total"] += 1
    return counts

def score_code_review(text):
    """Rubric B — CODE_REVIEW_RESULT."""
    decision = (field(text, "decision") or "").strip().upper()

    parsed_issues = parse_issue_blocks(text)
    blocking = _count_severity(parsed_issues, "BLOCKING")
    high = _count_severity(parsed_issues, "HIGH")
    medium = _count_severity(parsed_issues, "MEDIUM")
    low = _count_severity(parsed_issues, "LOW")

    new_blocking = blocking.get("new", 0)
    new_high = high.get("new", 0)
    new_medium = medium.get("new", 0)
    new_low = low.get("new", 0)

    # Drift issues across all severities.
    drift_total = (blocking.get("drift", 0) + high.get("drift", 0)
                   + medium.get("drift", 0) + low.get("drift", 0))

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

    final = clamp(base)

    # Primary error: first `new` BLOCKING issue's description, else first `new`
    # HIGH, else empty. Iterates the structurally-parsed list so field order
    # within each issue block is irrelevant.
    primary_error = ""
    for sev_pref in ("BLOCKING", "HIGH"):
        for issue in parsed_issues:
            if issue["severity"] == sev_pref and issue["category"] == "new" and issue["description"]:
                primary_error = issue["description"].splitlines()[0]
                break
        if primary_error:
            break

    success = (decision == "PASS")
    weak_label = ""
    return final, decision.lower(), primary_error, success, weak_label

def score_qa(text):
    """Rubric C — QA_RESULT."""
    tg = field_int(text, "tests_generated", 0)
    tp = field_int(text, "tests_passed", 0)
    coverage = field_float(text, "coverage_estimate", 0.0)
    gates_passed = field_int(text, "self_check_gates_passed", 5)

    if tg == 0:
        # Per spec: filter_skipped upstream. Signal that to bash.
        emit("EXIT_CODE", 5)
        sys.stderr.write("filter_skipped reason=tests_generated_zero\n")
        sys.exit(0)

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
        missing = 5 - gates_passed
        base += -0.5 * missing

    final = clamp(base)

    # Primary error: first failing test name if obtainable.
    primary_error = ""
    failing_rx = re.compile(r"^\s*(?:-\s*)?failing_test\s*:\s*(.+?)\s*$",
                            re.MULTILINE | re.IGNORECASE)
    m = failing_rx.search(text)
    if m:
        primary_error = m.group(1).strip()

    success = (tp == tg and gates_passed >= 5)
    weak_label = ""
    return final, "qa", primary_error, success, weak_label

# ---- Run scoring -----------------------------------------------------------
if schema == "SUPERVISOR_RESULT":
    score_f, status, primary_error, success, weak_label = score_supervisor(result_block)
elif schema == "CODE_REVIEW_RESULT":
    score_f, status, primary_error, success, weak_label = score_code_review(result_block)
else:
    score_f, status, primary_error, success, weak_label = score_qa(result_block)

# Bucket
if score_f < 4:
    bucket = "low"
elif score_f < 8:
    bucket = "medium"
else:
    bucket = "high"

score_int = round_half_up_int(score_f)

# ---- task_id (from result block; fallback to session_id) -------------------
task_id = field(result_block, "task_id") or session_id or "unknown"

# ---- Normalised agent type for labels --------------------------------------
def normalise_agent(at, schema):
    s = at or ""
    # Strip plugin prefix.
    if s.startswith("loomwright:"):
        s = s.split(":", 1)[1]
    # Strip -runner suffix.
    if s.endswith("-runner"):
        s = s[:-len("-runner")]
    if not s:
        # Fall back to schema-derived label.
        if schema == "SUPERVISOR_RESULT":
            s = "supervisor"
        elif schema == "CODE_REVIEW_RESULT":
            s = "code-reviewer"
        else:
            s = "qa-executor"
    return s

agent_norm = normalise_agent(agent_type, schema)

# ---- Interest filter (deferred) --------------------------------------------
# The interest filter has MOVED to bash, where it runs AFTER consent + target
# repo resolution per docs/TELEMETRY.md §Interest filter. Stage 1 only emits
# the signals bash needs to decide:
#   - SUCCESS (per-schema)
#   - STATUS  (already emitted)
#   - SCORE_INT / SCORE_BUCKET
# This is the heal-iter-1 reorder that closes the "healthy run with a secret
# never logs PRIVACY_BLOCKED" loophole.

# ---- Failed flag (for title) -----------------------------------------------
# Failed = inverse of success per docs/TELEMETRY.md §"Title format".
failed = (not success)

# ---- Privacy-scan helper used in stage 1 (raw payload only) ----------------
# We pre-flag any raw-string secrets; bash will re-scan the prospective body
# in stage 2. Both scans must agree (defence in depth via shared regex set).
def scan_for_secret(text):
    for rx, label in PRIVACY_PATTERNS:
        if rx.search(text):
            return label
    return ""

# Walk every string field of payload (1 level deep) for raw secrets.
raw_hit = ""
for k, v in payload.items():
    if isinstance(v, str):
        h = scan_for_secret(v)
        if h:
            raw_hit = h
            break

# Also scan the RESOLVED result text. When it was read from the transcript
# JSONL (v14.2.1 fallback) it is NOT a top-level payload field, so the loop
# above would miss a secret embedded there. The body scan only ever sees the
# REDACTED copy, so this raw scan is the authoritative fail-closed gate.
if not raw_hit:
    raw_hit = scan_for_secret(result_block)

# ---- Build prospective body components -------------------------------------
# Issues Detected — per schema.
issues = []
if schema == "SUPERVISOR_RESULT":
    sf_count, sf_list = parse_count_or_list(result_block, "subtasks_failed")
    if sf_list:
        issues.extend(sf_list)
    elif sf_count > 0:
        issues.append("subtasks_failed=%d" % sf_count)
    hd = field(result_block, "heal_decision") or ""
    if hd and hd.upper() != "PASS":
        issues.append("heal_decision=" + hd)
elif schema == "CODE_REVIEW_RESULT":
    # Description lines for new BLOCKING + HIGH issues. Uses the structural
    # parser so issue field order is irrelevant.
    parsed_for_body = parse_issue_blocks(result_block)
    for sev in ("BLOCKING", "HIGH"):
        for issue in parsed_for_body:
            if issue["severity"] == sev and issue["category"] == "new" and issue["description"]:
                line = issue["description"].splitlines()[0]
                issues.append("[%s] %s" % (sev, line))
else:  # QA_RESULT
    failing_rx = re.compile(r"^\s*(?:-\s*)?failing_test\s*:\s*(.+?)\s*$",
                            re.MULTILINE | re.IGNORECASE)
    for m in failing_rx.finditer(result_block):
        issues.append(m.group(1).strip())
    tg = field_int(result_block, "tests_generated", 0)
    tp = field_int(result_block, "tests_passed", 0)
    if tg > 0 and tp < tg:
        issues.append("tests_failed=%s/%s" % (tg - tp, tg))

# Tools Used — best-effort scan.
tools = []
tools_rx = re.compile(r"^\s*(?:-\s*)?(?:tools_used|skills_used)\s*:\s*\[(.*?)\]",
                      re.MULTILINE | re.IGNORECASE)
m = tools_rx.search(result_block)
if m:
    inner = m.group(1).strip()
    if inner:
        tools = [x.strip().strip('"').strip("'") for x in inner.split(",") if x.strip()]

# Sub-scores — none extracted in v1; section will be omitted.
agent_scores = []  # placeholder; left empty for v1.

# ---- Compute labels --------------------------------------------------------
labels = ["telemetry"]
labels.append("score:" + bucket)
labels.append("task:" + agent_norm)
if weak_label:
    labels.append(weak_label)

# ---- Build redacted JSON payload (Raw Data section) ------------------------
# Only fields safe to embed; we include the post-redaction result_block so
# secrets inside the markdown can never leak into the issue body.
def redact_text(text):
    out = text
    for rx, label in PRIVACY_PATTERNS:
        out = rx.sub("[REDACTED:" + label + "]", out)
    return out

redacted_block = redact_text(result_block)
# Additive plugin-version stamp — resolved by the bash layer above from the
# plugin manifest relative to this script ("unknown" when unreadable). Purely
# additive to the redacted payload; schema_version stays 1.
plugin_version = os.environ.get("LOOMWRIGHT_PLUGIN_VERSION", "") or "unknown"
raw_data = {
    "schema_version": 1,
    "task_id": task_id,
    "agent_type": agent_norm,
    "schema": schema,
    "score": score_int,
    "score_float": round(score_f, 2),
    "score_bucket": bucket,
    "status": status,
    "primary_error": primary_error,
    "redacted": True,
    "result_block": redacted_block,
    "plugin_version": plugin_version,
}
raw_data_json = json.dumps(raw_data, indent=2, sort_keys=True)

# ---- Format issue body -----------------------------------------------------
def section(title, lines):
    if not lines:
        return ""
    return "## " + title + "\n" + "\n".join("- " + l for l in lines) + "\n\n"

body = []
body.append("## Task Summary\n")
body.append("- Task Type: %s\n" % agent_norm)
body.append("- Task ID: %s\n" % task_id)
body.append("- Success: %s\n" % ("true" if success else "false"))
body.append("- Score: %s/10\n" % score_int)
body.append("- Bucket: %s\n\n" % bucket)

if agent_scores:
    body.append(section("Agent Scores", agent_scores))

if issues:
    body.append(section("Issues Detected", issues))

body.append("## AI Suggestions\n")
body.append("- (placeholder — automatic suggestion synthesis is future work; see docs/TELEMETRY.md §Future Work)\n\n")

if tools:
    body.append(section("Tools Used", tools))

body.append("## Raw Data\n")
body.append("```json\n")
body.append(raw_data_json + "\n")
body.append("```\n")

body_text = "".join(body)

# ---- Privacy scan (final) on prospective issue body + raw payload ----------
body_hit = scan_for_secret(body_text)
hit = body_hit or raw_hit

if hit:
    sys.stderr.write("PRIVACY_BLOCKED pattern=%s\n" % hit)
    emit("EXIT_CODE", 2)
    sys.exit(0)

# ---- Title -----------------------------------------------------------------
title = "[Telemetry] %s | Score: %s | Failed: %s" % (
    agent_norm, score_int, "true" if failed else "false"
)

# ---- Dedup hash ------------------------------------------------------------
import hashlib
hash_input = "%s::%s::%s" % (task_id, bucket, primary_error)
dedup_hash = hashlib.sha256(hash_input.encode("utf-8")).hexdigest()

# ---- Emit results ---------------------------------------------------------
emit("SCHEMA", schema)
emit("AGENT_NORM", agent_norm)
emit("TASK_ID", task_id)
emit("SCORE_INT", score_int)
emit("SCORE_BUCKET", bucket)
emit("STATUS", status)
emit("SUCCESS", success)
emit("FAILED", failed)
emit("PRIMARY_ERROR", primary_error)
emit("DEDUP_HASH", dedup_hash)
emit("LABELS", "\t".join(sorted(labels)))
emit("TITLE", title)
# Body is multi-line. Encode as hex (NOT base64 — base64 padding uses `=`,
# which collides with our `key=value` line-protocol separator and gets
# stripped by bash `read -r` because `=` is in IFS). Hex is binary-safe
# and contains no IFS characters.
emit("BODY_HEX", body_text.encode("utf-8").hex())
emit("EXIT_CODE", 0)  # 0 means "stage 1 OK; bash continues to consent/repo/dedup/gh"
PY

STAGE1_OUT="$(printf '%s' "$INPUT" | python3 -c "$STAGE1_PY")"
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
FAILED=""
PRIMARY_ERROR=""
DEDUP_HASH=""
LABELS_TSV=""
TITLE=""
BODY_HEX=""
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
    FAILED) FAILED="$v" ;;
    PRIMARY_ERROR) PRIMARY_ERROR="$v" ;;
    DEDUP_HASH) DEDUP_HASH="$v" ;;
    LABELS) LABELS_TSV="$v" ;;
    TITLE) TITLE="$v" ;;
    BODY_HEX) BODY_HEX="$v" ;;
    EXIT_CODE) EXIT_CODE="$v" ;;
  esac
done <<EOF
$STAGE1_OUT
EOF

if [ -z "$EXIT_CODE" ]; then
  printf 'stage1_no_exit_code\n' >&2
  exit 1
fi

# Stage 1 may signal early exit (privacy_blocked=2, json_parse_failed/empty=5,
# QA tests_generated==0 short-circuit=5). Interest filter is NOT in stage 1
# anymore — it runs in bash after consent + target-repo resolution.
if [ "$EXIT_CODE" != "0" ]; then
  if [ "$DRY_RUN" = "true" ]; then
    printf -- '--- DRY RUN ---\n'
    printf 'stage1_early_exit=%s\n' "$EXIT_CODE"
    printf 'WOULD_EXIT=%s\n' "$EXIT_CODE"
    exit 0
  fi
  exit "$EXIT_CODE"
fi

# ---- Read consent ------------------------------------------------------------
# Missing / prompt / no -> exit 3.
CONSENT_DECISION="missing"
TELEMETRY_REPO_FROM_CONSENT=""

if [ -r "$CONSENT_FILE" ]; then
  CONSENT_OUT="$(python3 - "$CONSENT_FILE" <<'PY' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1], "r") as f:
        d = json.load(f)
    t = d.get("telemetry", "prompt")
    r = d.get("telemetry_repo", "")
    if not isinstance(t, str):
        t = "prompt"
    if not isinstance(r, str):
        r = ""
    sys.stdout.write("CONSENT=%s\n" % t)
    sys.stdout.write("REPO=%s\n" % r)
except Exception as e:
    sys.stdout.write("CONSENT=parse_error\n")
    sys.stdout.write("REPO=\n")
PY
)"
  while IFS='=' read -r ck cv; do
    case "$ck" in
      CONSENT) CONSENT_DECISION="$cv" ;;
      REPO) TELEMETRY_REPO_FROM_CONSENT="$cv" ;;
    esac
  done <<EOF
$CONSENT_OUT
EOF
fi

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
if ! printf '%s' "$TARGET_REPO" | grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'; then
  printf 'invalid_repo_format repo=%s\n' "$TARGET_REPO" >&2
  exit 1
fi

# ---- Interest filter ---------------------------------------------------------
# Per docs/TELEMETRY.md §Interest filter: runs AFTER privacy + consent +
# target-repo resolution, BEFORE dedup. Skip if score >= 5 AND status indicates
# success (per-schema definition emitted as SUCCESS by stage 1):
#   - SUPERVISOR_RESULT: status=='completed' AND heal_decision=='PASS'
#   - CODE_REVIEW_RESULT: decision=='PASS'
#   - QA_RESULT:          tests_passed==tests_generated AND gates>=5
#
# A healthy run (score>=5, success=true) whose payload contains a secret has
# ALREADY exited 2 in stage 1's raw/body privacy scans, so the audit trail is
# preserved before this short-circuit fires.
INTEREST_SKIP="false"
if [ "$SUCCESS" = "true" ] && [ -n "$SCORE_INT" ] && [ "$SCORE_INT" -ge 5 ] 2>/dev/null; then
  case "$SCHEMA" in
    SUPERVISOR_RESULT)
      # `success` (stage 1) already encodes status=completed AND heal_decision=PASS.
      INTEREST_SKIP="true"
      ;;
    CODE_REVIEW_RESULT)
      # Stage 1 emits status=<decision>.lower; success=(decision==PASS).
      INTEREST_SKIP="true"
      ;;
    QA_RESULT)
      INTEREST_SKIP="true"
      ;;
  esac
fi

if [ "$INTEREST_SKIP" = "true" ]; then
  printf 'filter_skipped reason=interest_filter score=%s status=%s\n' \
    "$SCORE_INT" "$STATUS" >&2
  if [ "$DRY_RUN" = "true" ]; then
    printf -- '--- DRY RUN ---\n'
    printf 'WOULD_EXIT=5\n'
    exit 0
  fi
  exit 5
fi

# ---- Dedup check -------------------------------------------------------------
# Scan telemetry-sent.log for the same hash within last 6h.
DEDUP_HIT="false"
if [ -r "$SENT_LOG" ]; then
  DEDUP_HIT="$(python3 - "$SENT_LOG" "$DEDUP_HASH" <<'PY' 2>/dev/null
import sys, re
from datetime import datetime, timedelta, timezone
path, want_hash = sys.argv[1], sys.argv[2]
cutoff = datetime.now(timezone.utc) - timedelta(hours=6)
hit = False
try:
    with open(path, "r") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            ts_s = parts[0].strip()
            h = parts[1].strip()
            if h != want_hash:
                continue
            try:
                # Tolerate trailing Z.
                ts = datetime.fromisoformat(ts_s.replace("Z", "+00:00"))
            except Exception:
                continue
            if ts >= cutoff:
                hit = True
                break
except FileNotFoundError:
    pass
sys.stdout.write("true" if hit else "false")
PY
)"
  if [ -z "$DEDUP_HIT" ]; then
    DEDUP_HIT="false"
  fi
fi

if [ "$DEDUP_HIT" = "true" ]; then
  printf 'dedup_hit hash=%s\n' "$DEDUP_HASH" >&2
  if [ "$DRY_RUN" = "true" ]; then
    printf -- '--- DRY RUN ---\n'
    printf 'WOULD_EXIT=5\n'
    exit 0
  fi
  exit 5
fi

# ---- Decode body for output / gh -------------------------------------------
BODY_TEXT="$(printf '%s' "$BODY_HEX" | python3 -c '
import sys
data = sys.stdin.read().strip()
sys.stdout.write(bytes.fromhex(data).decode("utf-8"))
' 2>/dev/null || true)"

# Convert TSV labels back to a sorted list.
LABELS_SORTED="$(printf '%s' "$LABELS_TSV" | tr '\t' '\n' | sort -u)"

# ---- Dry-run branch ---------------------------------------------------------
if [ "$DRY_RUN" = "true" ]; then
  printf -- '--- DRY RUN ---\n'
  printf 'TARGET_REPO=%s\n' "$TARGET_REPO"
  printf 'TITLE=%s\n' "$TITLE"
  printf 'SCORE=%s\n' "$SCORE_INT"
  printf 'BUCKET=%s\n' "$SCORE_BUCKET"
  printf 'LABELS:\n'
  printf '%s\n' "$LABELS_SORTED" | sed 's/^/  - /'
  printf 'BODY_BEGIN\n%sBODY_END\n' "$BODY_TEXT"
  printf 'WOULD_EXIT=0\n'
  exit 0
fi

# ---- Live: gh issue create --------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  printf 'gh_missing\n' >&2
  exit 1
fi

# Idempotently ensure labels exist (best-effort; ignore failures).
while IFS= read -r lbl; do
  [ -z "$lbl" ] && continue
  gh label create "$lbl" --repo "$TARGET_REPO" --force >/dev/null 2>&1 || true
done <<EOF
$LABELS_SORTED
EOF

# Write body to a temp file (avoids shell-quoting bugs).
BODY_TMP="$(mktemp "${LOG_DIR}/telemetry-body.XXXXXX" 2>/dev/null || echo "/tmp/telemetry-body-$$.tmp")"
printf '%s' "$BODY_TEXT" > "$BODY_TMP" 2>/dev/null || {
  printf 'body_write_failed\n' >&2
  exit 1
}

# Build label flags.
LABEL_FLAGS=()
while IFS= read -r lbl; do
  [ -z "$lbl" ] && continue
  LABEL_FLAGS+=(--label "$lbl")
done <<EOF
$LABELS_SORTED
EOF

ISSUE_URL="$(gh issue create \
  --repo "$TARGET_REPO" \
  --title "$TITLE" \
  --body-file "$BODY_TMP" \
  "${LABEL_FLAGS[@]}" 2>&1)"
GH_RC=$?

rm -f "$BODY_TMP" 2>/dev/null || true

if [ $GH_RC -ne 0 ]; then
  printf 'gh_failed rc=%s\n' "$GH_RC" >&2
  printf '%s\n' "$ISSUE_URL" >&2
  exit 1
fi

# Extract URL from gh output (last line is typically the URL).
ISSUE_URL_CLEAN="$(printf '%s' "$ISSUE_URL" | tail -n 1 | tr -d '[:space:]' || true)"

# ---- Append success line to telemetry-sent.log -----------------------------
UTC_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
{
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$UTC_TS" "$DEDUP_HASH" "$TASK_ID" "$SCORE_INT" "$SCORE_BUCKET" "$ISSUE_URL_CLEAN"
} >> "$SENT_LOG" 2>/dev/null || true

exit 0
