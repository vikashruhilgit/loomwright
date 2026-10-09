#!/usr/bin/env bash
# phase-timing.sh — derive per-phase wall-clock and machine-vs-owner time from
# LOCAL logs alone (iq02 Part T04). READ-ONLY and fail-SAFE: always exits 0;
# unreadable input ⇒ `null` fields plus one stderr note. Never writes a file.
#
# USAGE
#   phase-timing.sh --run <automate run file> [--logs-dir <dir>]
#                   [--ci-runs <dir> (--trees <file> | --git-range <base>..<head>) [--branch <name>]]
#   phase-timing.sh --session <plugin session id> [--logs-dir <dir>]
# Output: ONE compact JSON record on stdout.
#
# WHAT IT READS (hook- and script-written rows only — no prompt-written event,
# no `phase_transition`, no model-computed duration):
#   * the run file's `## Progress` lines (`- <ts> <text>`): `run created (session
#     <uuid>)`, `picked`, `session_id <id>`, `ran /autonomous`, `owned drain
#     started`, `… READY` / `… ESCALATED` / `… superseded_by_merge`, `parked`;
#   * the plugin session log `<logs>/<session_id>.jsonl` AND the Claude Code
#     session log `<logs>/<cc_session_id>.jsonl` — JOINED: the cc id comes from
#     the run file's `run created (session <uuid>)` line, else the
#     `<session_id>.owner` sidecar's `cc_session_id=` line. Events before
#     `autonomous_start` (Launch Pad, plan review, the first owner question) live
#     only in the cc log, so without the join those spans are `null`.
#   * rows used: agent_lifecycle (working/waiting/ended), agent_identity
#     (agent_id → agent_type), subtask_complete, autonomous_start, pr_created,
#     session_end.
#
# RULES
#   * A span with a missing endpoint is `null` — never 0, never guessed.
#   * Phases are ordered by their timestamps, never assumed (a run may FINALIZE
#     before Phase 4.5).
#   * Owner wait: `asked` = an ask_user `waiting` row (a permission_prompt row
#     counts only when no ask_user row is within LOOMWRIGHT_LIFECYCLE_HEARTBEAT_DEBOUNCE
#     s before it). `answered` = the `working`/`reason: answered` row paired by
#     `tool_use_id` (else by order) ⇒ `exact: true`; on older logs, the next
#     `working` row of ANY scope ⇒ `exact: false` (an upper bound — a background
#     subagent heartbeat during a pending question would shorten it). Asks with
#     no working row between them form ONE interval. Owner time = sum of
#     intervals, each clamped to end no later than the span's window end (an
#     answer after a phase boundary never counts in that phase); machine =
#     wall − owner; each `null` when its inputs are missing.
#     With NO ask, owner time is 0 only when the joined logs provably span the
#     window; otherwise `null`.
#   * ci-local runs are attributed by TREE KEY only (the log name's first field
#     is a commit tree on the item's branch) or by the run log's
#     `ci-local: head <sha> <branch>` line — NEVER by time window. Unmatched runs
#     are counted `unattributed`. No tree list ⇒ `ci_runs: null` (incomplete).
#   * A synthetic close-out `session_end` (`reason: session_ended_without_completion`)
#     yields a `null` completion span, never a duration ending at the close-out.
set -u
trap 'exit 0' EXIT

RUN="" SESSION="" LOGS="" CI_RUNS="" TREES="" GIT_RANGE="" BRANCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --run) RUN="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --session) SESSION="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --logs-dir) LOGS="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --ci-runs) CI_RUNS="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --trees) TREES="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --git-range) GIT_RANGE="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --branch) BRANCH="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    *) shift ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { echo "phase-timing: python3 not found" >&2; echo '{"kind":null,"error":"python3_missing"}'; exit 0; }

TREE_LIST=""
if [ -n "$GIT_RANGE" ]; then
  TREE_LIST="$(git log --format=%T "$GIT_RANGE" 2>/dev/null; git log --format=%H "$GIT_RANGE" 2>/dev/null)" || TREE_LIST=""
elif [ -n "$TREES" ] && [ -r "$TREES" ]; then
  TREE_LIST="$(cat "$TREES" 2>/dev/null)"
fi

export PT_RUN="$RUN" PT_SESSION="$SESSION" PT_LOGS="$LOGS" PT_CI_RUNS="$CI_RUNS" \
  PT_TREE_LIST="$TREE_LIST" PT_HAVE_TREES="$([ -n "$GIT_RANGE$TREES" ] && echo 1 || echo 0)" \
  PT_BRANCH="$BRANCH" PT_DEBOUNCE="${LOOMWRIGHT_LIFECYCLE_HEARTBEAT_DEBOUNCE:-60}"

python3 - <<'PYEOF' || echo '{"kind":null,"error":"derivation_failed"}'
import json, os, re, sys
from datetime import datetime, timezone

def note(msg):
    sys.stderr.write("phase-timing: %s\n" % msg)

def ep(ts):
    try:
        return int(datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())
    except Exception:
        return None

def span(a, b):
    """{start,end,seconds}; seconds is null unless BOTH endpoints are known."""
    ea, eb = (ep(a) if a else None), (ep(b) if b else None)
    secs = (eb - ea) if (ea is not None and eb is not None and eb >= ea) else None
    return {"start": a, "end": b, "seconds": secs}

def read_jsonl(path):
    rows = []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                if isinstance(r, dict):
                    rows.append(r)
    except Exception:
        return None
    return rows

try:
    debounce = int(os.environ.get("PT_DEBOUNCE", "60"))
except ValueError:
    debounce = 60

run_path = os.environ.get("PT_RUN", "")
session = re.sub(r"[^A-Za-z0-9_-]", "", os.environ.get("PT_SESSION", ""))
logs = os.environ.get("PT_LOGS", "")

progress = []   # (ts, text)
cc_id = None
if run_path:
    try:
        with open(run_path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                m = re.match(r"^- (\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ) (.*)$", line.rstrip("\n"))
                if m:
                    progress.append((m.group(1), m.group(2)))
    except Exception:
        note("run file unreadable: %s" % run_path)
    for ts, t in progress:
        m = re.search(r"run created \(session ([A-Za-z0-9_-]+)\)", t)
        if m and not cc_id:
            cc_id = m.group(1)
        m = re.match(r"session_id ([A-Za-z0-9_-]+)", t)
        if m:
            session = m.group(1)
    if not logs:
        logs = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(run_path))), "logs")
elif not logs:
    logs = ".supervisor/logs"

if session and not cc_id:
    try:
        with open(os.path.join(logs, session + ".owner"), encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("cc_session_id="):
                    cc_id = re.sub(r"[^A-Za-z0-9_-]", "", line.split("=", 1)[1].strip()) or None
    except Exception:
        pass

plugin_rows = read_jsonl(os.path.join(logs, session + ".jsonl")) if session else None
if session and plugin_rows is None:
    note("session log unreadable: %s.jsonl" % session)
cc_rows = read_jsonl(os.path.join(logs, cc_id + ".jsonl")) if cc_id else None
rows = (plugin_rows or []) + (cc_rows or [])

types = {}
for r in rows:
    aid, at = r.get("agent_id"), r.get("agent_type")
    if isinstance(aid, str) and isinstance(at, str) and at:
        types[aid] = at.split(":")[-1]
def atype(r):
    return types.get(r.get("agent_id"), "")

timed = sorted([r for r in rows if isinstance(r.get("ts"), str) and ep(r["ts"]) is not None], key=lambda r: r["ts"])
lc = [r for r in timed if r.get("event") == "agent_lifecycle"]

def first(pred, after=None, before=None):
    for r in timed:
        if pred(r) and (after is None or r["ts"] >= after) and (before is None or r["ts"] <= before):
            return r["ts"]
    return None
def last(pred, after=None, before=None):
    out = None
    for r in timed:
        if pred(r) and (after is None or r["ts"] >= after) and (before is None or r["ts"] <= before):
            out = r["ts"]
    return out

def owner_wait(lo, hi):
    """Owner intervals with asked in [lo, hi]. Returns (intervals, seconds|None)."""
    if lo is None or hi is None:
        return [], None
    asks = []
    for r in lc:
        if r.get("state") != "waiting" or not (lo <= r["ts"] <= hi):
            continue
        reason = r.get("reason")
        if reason == "ask_user":
            asks.append(r)
        elif reason == "permission_prompt":
            near = [a for a in lc if a.get("state") == "waiting" and a.get("reason") == "ask_user"
                    and 0 <= ep(r["ts"]) - ep(a["ts"]) <= debounce]
            if not near:
                asks.append(r)
    answered = [r for r in lc if r.get("state") == "working" and r.get("reason") == "answered"]
    used, out, last_end = set(), [], None
    for a in asks:
        if last_end is not None and a["ts"] <= last_end:
            continue            # a second ask before the first was answered → same interval
        ans, exact = None, False
        tid = a.get("tool_use_id")
        for i, r in enumerate(answered):
            if i in used or r["ts"] < a["ts"]:
                continue
            if tid and r.get("tool_use_id") and r.get("tool_use_id") != tid:
                continue
            ans, exact = r["ts"], True
            used.add(i)
            break
        if ans is None:
            ans = next((r["ts"] for r in lc if r.get("state") == "working" and r["ts"] > a["ts"]), None)
        # Clamp to the window: an answer (or fallback working row) landing after `hi` must not
        # stretch owner time past the phase it is split from — that would deflate or negate
        # machine_seconds and double-count the overflow in the next phase. `last_end` keeps the
        # unclamped answer so a later ask before it still merges into this interval.
        end = ans
        if end is not None and ep(end) is not None and ep(hi) is not None and ep(end) > ep(hi):
            end = hi
        iv = span(a["ts"], end)
        iv["exact"] = exact
        out.append(iv)
        last_end = ans or "9999"
    if not out:
        covered = bool(timed) and timed[0]["ts"] <= lo and timed[-1]["ts"] >= hi
        return [], (0 if covered else None)
    if any(i["seconds"] is None for i in out):
        return out, None
    return out, sum(i["seconds"] for i in out)

def split(sp, lo=None, hi=None):
    lo = lo or sp["start"]; hi = hi or sp["end"]
    ivs, owner = owner_wait(lo, hi)
    machine = (sp["seconds"] - owner) if (sp["seconds"] is not None and owner is not None) else None
    sp = dict(sp)
    sp.update({"owner_seconds": owner, "machine_seconds": machine, "owner_waits": ivs})
    return sp

# ---- Supervisor spans (plugin session log) ----------------------------------
def is_type(t):
    return lambda r: atype(r) == t
reviewers = []
seen = []
for r in lc:
    if atype(r) == "code-reviewer" and r.get("agent_id") not in seen:
        seen.append(r.get("agent_id"))
for aid in seen:
    s = first(lambda r: r.get("event") == "agent_lifecycle" and r.get("agent_id") == aid and r.get("state") == "working")
    e = last(lambda r: r.get("event") == "agent_lifecycle" and r.get("agent_id") == aid and r.get("state") == "ended")
    sp = span(s, e); sp["agent_id"] = aid
    reviewers.append(sp)
reviewers.sort(key=lambda x: x["start"] or "9999")
fix_passes = [span(reviewers[i]["end"], reviewers[i + 1]["start"]) for i in range(len(reviewers) - 1)]
ae = [r for r in timed if r.get("event") == "session_end"]
se = ae[-1] if ae else None
stranded = bool(se and se.get("reason") == "session_ended_without_completion")
exec_start = first(lambda r: r.get("event") == "agent_lifecycle" and atype(r) == "worker" and r.get("state") == "working")
exec_end = last(lambda r: r.get("event") == "subtask_complete")
pr_created = first(lambda r: r.get("event") == "pr_created")
start_ts = first(lambda r: r.get("event") == "autonomous_start")
supervisor = {
    "plan": span(first(lambda r: r.get("event") == "agent_lifecycle" and atype(r) == "plan-reviewer" and r.get("state") == "working"),
                 last(lambda r: r.get("event") == "agent_lifecycle" and atype(r) == "plan-reviewer" and r.get("state") == "ended")),
    "execute": span(exec_start, exec_end),
    "finalize": span(exec_end, pr_created),
    "pr_created": pr_created,
    "phase45_iterations": reviewers,
    "phase45_fix_passes": fix_passes,
    "completion": span(reviewers[-1]["end"] if reviewers else None, None if stranded else (se or {}).get("ts")),
    "session_end_reason": (se or {}).get("reason"),
}
supervisor["order"] = [k for k, _ in sorted(
    [(k, supervisor[k]["start"]) for k in ("plan", "execute", "finalize", "completion") if supervisor[k]["start"]]
    + [("pr_created", pr_created)] * bool(pr_created)
    + [("phase45_%d" % (i + 1), v["start"]) for i, v in enumerate(reviewers) if v["start"]],
    key=lambda kv: kv[1])]

record = {"kind": "item" if run_path else "session", "session_id": session or None, "cc_session_id": cc_id,
          "cc_log_joined": cc_rows is not None, "supervisor": supervisor}

# ---- Automate per-item spans (run file Progress) ------------------------------
if run_path:
    def p_first(rx, after=None):
        for ts, t in progress:
            if re.search(rx, t) and (after is None or ts >= after):
                return ts
        return None
    pick = p_first(r"^picked ")
    park = p_first(r"^parked ", pick)
    drains = []
    for i, (ts, t) in enumerate(progress):
        if re.match(r"owned drain started", t):
            end, result = None, None
            for ts2, t2 in progress[i + 1:]:
                m = re.search(r"\b(READY|ESCALATED|superseded_by_merge)\b", t2)
                if m and not t2.startswith("dismissed"):
                    end, result = ts2, m.group(1)
                    break
                if re.match(r"owned drain started", t2):
                    break
            d = span(ts, end); d["result"] = result; d["fix_now"] = "fix-now" in t
            drains.append(d)
    first_ready = next((d["end"] for d in drains if d["result"] == "READY"), None)
    pre = split(span(pick, start_ts))
    pre["plan_review"] = span(first(lambda r: True, pick, start_ts),
                              last(lambda r: r.get("event") == "agent_lifecycle" and atype(r) == "plan-reviewer" and r.get("state") == "ended", pick, start_ts))
    item = split(span(pick, park))
    record["item"] = {
        "pick": pick, "park": park,
        "pick_to_park": item,
        "pick_to_autonomous_start": pre,
        "autonomous": span(start_ts, p_first(r"^ran /autonomous", pick)),
        "owned_drains": drains,
        "pick_to_first_ready": span(pick, first_ready),
        "post_ready": split(span(first_ready, park)),
        "owner_seconds": item["owner_seconds"],
        "machine_seconds": item["machine_seconds"],
        "owner_exact_share": (None if not item["owner_waits"] else
                              round(sum(1 for w in item["owner_waits"] if w["exact"]) / float(len(item["owner_waits"])), 2)),
    }

# ---- ci-local runs, attributed by tree key / HEAD only (never time) ----------
ci_dir = os.environ.get("PT_CI_RUNS", "")
if ci_dir and os.environ.get("PT_HAVE_TREES") == "1":
    keys = set(x.strip() for x in os.environ.get("PT_TREE_LIST", "").split() if x.strip())
    branch = os.environ.get("PT_BRANCH", "")
    runs, unattributed = [], 0
    try:
        names = sorted(n for n in os.listdir(ci_dir) if n.endswith(".log"))
    except Exception:
        names = None
        note("ci runs dir unreadable: %s" % ci_dir)
    for n in names or []:
        tree = n.split("-", 1)[0]
        mts = re.search(r"-(\d{8}T\d{6}Z)-", n)
        start = (datetime.strptime(mts.group(1), "%Y%m%dT%H%M%SZ").strftime("%Y-%m-%dT%H:%M:%SZ") if mts else None)
        head = hb = None
        verdict, wall = None, None
        try:
            with open(os.path.join(ci_dir, n), encoding="utf-8", errors="replace") as fh:
                lines = [l.rstrip("\n") for l in fh if l.strip()]
            for l in lines[:3]:
                m = re.match(r"^ci-local: head (\S+) (\S+)", l)
                if m:
                    head, hb = m.group(1), m.group(2)
            # verdict: the last ci-local PASS/FAIL line among the final 3 (an
            # --affected run ends with an advisory line after its verdict)
            tail = next((l for l in reversed(lines[-3:]) if re.match(r"^ci-local( --affected)?: (PASS|FAIL)\b", l)), "")
            m = re.match(r"^ci-local( --affected)?: (PASS|FAIL)\b", tail)
            verdict = m.group(2) if m else "INCOMPLETE"
            m = re.search(r"after (\d+)s", tail)
            wall = int(m.group(1)) if m else None
        except Exception:
            pass
        if tree in keys or (head and head in keys) or (branch and hb == branch):
            runs.append({"log": n, "start": start, "wall_seconds": wall, "verdict": verdict})
        else:
            unattributed += 1
    record["ci_runs"] = None if names is None else runs
    record["ci_unattributed"] = None if names is None else unattributed
else:
    record["ci_runs"] = None

print(json.dumps(record, separators=(",", ":")))
PYEOF
exit 0
