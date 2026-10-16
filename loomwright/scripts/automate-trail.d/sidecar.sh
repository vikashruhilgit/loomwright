# --------------------------------------------------------------------------- #
# sidecar-check
# --------------------------------------------------------------------------- #
sidecar_check() {
  local path="${1:-}" out
  if [ -z "$path" ]; then echo "fail : missing argument"; return 0; fi
  if [ ! -f "$path" ] || [ ! -r "$path" ]; then echo "fail $path: file not found"; return 0; fi
  if ! command -v python3 >/dev/null 2>&1; then echo "fail $path: python3 unavailable"; return 0; fi
  out="$(python3 - "$HERE" "$path" <<'PY' 2>/dev/null
import sys
here, path = sys.argv[1], sys.argv[2]
sys.path.insert(0, here)

def say(msg):
    print(msg)
    sys.exit(0)

try:
    import result_block_parser as R
except Exception as exc:  # pragma: no cover - defensive
    say("fail %s: parser unavailable (%s)" % (path, exc))

# REVIEW_HEAL_RESULT key tables — mirror docs/RESULT_SCHEMAS.md §REVIEW_HEAL_RESULT
# ("Schema v1" / "Schema v2" blocks). Update together with that section.
# `rounds` is REQUIRED for v2 here although the schema block marks only the first
# seven fields required: the --until-mergeable drain always emits it (its value is
# read from the scripts/drain-rounds.sh ledger), and the hand-rebuilt item-10
# sidecar dropped it (the #303 drift this check exists to catch).
RH_V1_REQUIRED = ["schema_version", "decision", "iterations", "issues_fixed",
                  "remaining_issues", "pr_url", "notified"]
RH_V2_REQUIRED = RH_V1_REQUIRED + ["rounds"]
RH_V2_ALLOWED = set(RH_V2_REQUIRED + [
    "max_rounds", "fix_cycles", "churn_rounds", "repeat_check_failure",
    "unresolved_bot_feedback", "postmortem_churn_threshold",
    "postmortem_dispatched", "channels_scanned", "findings_validated",
    "findings_dismissed", "checks_waited", "termination_reason",
    "severity_floor", "sub_floor_fixed", "rejected_instruction_like",
    "dismissed", "rules_gate", "checks_untrusted",
    # automate-followups/31: the escalation cause (present only on ESCALATED).
    "escalation_cause", "escalation_check", "escalation_run_id",
    "escalation_attempt", "escalation_sha"])
RH_V1_ALLOWED = set(RH_V1_REQUIRED)
# channels_scanned vocabulary — mirrors skills/review-heal/SKILL.md
# §"Step U1 — All-Channel Read" (RESULT_SCHEMAS lists channels only as "e.g.").
CHANNELS = set(["reviews", "latestReviews", "reviewThreads", "issue_comments",
                "check_outputs"])

# SUPERVISOR_RESULT key tables — mirror docs/RESULT_SCHEMAS.md §SUPERVISOR_RESULT
# (the yaml block). validate-supervisor-result.py exposes only main(), so there is
# no importable table to reuse. `error` is required only when status == failed.
SUP_REQUIRED = ["schema_version", "task_id", "status", "pr_url", "branch",
                "subtasks_completed", "subtasks_failed", "heal_loop_ran",
                "heal_iterations", "heal_decision", "heal_fixable_issues_fixed",
                "heal_remaining_issues", "summary"]
SUP_ALLOWED = set(SUP_REQUIRED + [
    "error", "cost_profile", "rubric_score", "branch_base", "pr_state",
    "contract_conformance", "benchmark_result", "ground_truth",
    "preflight_sync", "knowledge_sources_used", "until_mergeable_dispatched",
    "until_mergeable_log", "risk_classification", "heal_dismissed",
    "heal_first_decision", "heal_new_findings"])

try:
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
except Exception as exc:
    say("fail %s: unreadable (%s)" % (path, exc))

name, block = R.find_last_named_block(text, ("REVIEW_HEAL_RESULT", "SUPERVISOR_RESULT"))
if block is None:
    say("fail %s: no REVIEW_HEAL_RESULT or SUPERVISOR_RESULT block" % path)
fields, errors = R.parse_block(block)
if errors:
    say("fail %s: %s parse error (%s)" % (path, name, errors[0]))

sv, _bad = R.as_int(fields.get("schema_version"))
if name == "REVIEW_HEAL_RESULT":
    if sv == 1:
        required, allowed = RH_V1_REQUIRED, RH_V1_ALLOWED
    elif sv == 2:
        required, allowed = RH_V2_REQUIRED, RH_V2_ALLOWED
    else:
        say("fail %s: REVIEW_HEAL_RESULT schema_version must be 1 or 2" % path)
else:
    if sv != 1:
        say("fail %s: SUPERVISOR_RESULT schema_version must be 1" % path)
    required, allowed = SUP_REQUIRED, SUP_ALLOWED
    if R.as_text(fields.get("status")).strip() == "failed":
        required = required + ["error"]

for key in required:
    if not R.present(fields, key):
        say("fail %s: %s missing required key %s" % (path, name, key))
for key in fields:
    if key not in allowed:
        say("fail %s: %s carries non-schema key %s" % (path, name, key))

if name == "REVIEW_HEAL_RESULT" and R.present(fields, "channels_scanned"):
    chans = fields.get("channels_scanned")
    if not isinstance(chans, list):
        say("fail %s: channels_scanned is not a list" % path)
    for c in chans:
        if R.as_text(c) not in CHANNELS:
            say("fail %s: non-canonical channels_scanned token %s" % (path, R.as_text(c)))

if name == "SUPERVISOR_RESULT" and R.present(fields, "risk_classification"):
    rc = fields.get("risk_classification")
    if not isinstance(rc, dict) or "reasons" not in rc:
        say("fail %s: risk_classification present without reasons" % path)

# NESTED key tables (automate-followups/20) — mirror the "Nested-object key sets"
# paragraphs of docs/result-schemas/supervisor-result.md and review-heal-result.md.
# Update together with them. Per field: (shape, required, optional, item_tables)
# where shape is "map" (one mapping) or "list" (a list of mappings, each item
# checked against required/optional; None = items must be mappings, keys unpinned),
# and item_tables maps a list-valued key of the mapping to its own (required,
# optional) item table. Value enums are not checked here — key shape only.
GT_FINDING = (["check", "detail", "severity"], [])
CC_FINDING = (["subsystem", "invariant", "severity", "detail"], [])
DISMISSED_ITEM = (["finding", "reason", "source"], ["severity"])
NESTED = {
    "SUPERVISOR_RESULT": {
        "ground_truth": ("map", ["checked", "status", "checks_total", "checks_passed"],
                         ["findings"], {"findings": GT_FINDING}),
        "contract_conformance": ("map", ["checked", "status", "contracts_evaluated", "violations"],
                                 ["findings"], {"findings": CC_FINDING}),
        "benchmark_result": ("map", ["ran", "status"],
                             ["name", "metric", "value", "baseline", "delta", "unit"], {}),
        "risk_classification": ("map", ["high_risk", "reasons"], [], {}),
        "heal_dismissed": ("list",) + DISMISSED_ITEM + ({},),
    },
    "REVIEW_HEAL_RESULT": {
        "dismissed": ("list",) + DISMISSED_ITEM + ({},),
        "checks_untrusted": ("list", ["check", "reason", "run_id"], [], {}),
        "sub_floor_fixed": ("list", None, None, {}),
    },
}

# The documented skip form (supervisor-result.md "Nested-object key sets"): these keys
# become optional when checked is false and status is skipped or unverified.
SKIP_OPTIONAL = {
    "ground_truth": ["checks_total", "checks_passed"],
    "contract_conformance": ["contracts_evaluated", "violations"],
}

def check_map(label, obj, required, optional):
    if not isinstance(obj, dict):
        say("fail %s: %s %s is not a mapping" % (path, name, label))
    if required is None:
        return
    for k in required:
        if k not in obj:
            say("fail %s: %s %s missing required key %s" % (path, name, label, k))
    allowed_keys = set(required) | set(optional)
    for k in obj:
        if k not in allowed_keys:
            say("fail %s: %s %s carries non-schema key %s" % (path, name, label, k))

def check_list(label, val, required, optional):
    if not isinstance(val, list):
        say("fail %s: %s %s is not a list" % (path, name, label))
    for i, item in enumerate(val):
        check_map("%s[%d]" % (label, i), item, required, optional)

for key, (shape, required, optional, items) in sorted(NESTED[name].items()):
    if not R.present(fields, key):
        continue
    val = fields.get(key)
    if shape == "list":
        check_list(key, val, required, optional)
        continue
    # Skip form: checked false + status skipped|unverified makes the count/list keys
    # optional (absent reads as 0 / []). `checked` itself stays required.
    if key in SKIP_OPTIONAL and isinstance(val, dict) \
            and R.as_bool(val.get("checked"))[0] is False \
            and R.as_text(val.get("status")).strip() in ("skipped", "unverified"):
        required = [k for k in required if k not in SKIP_OPTIONAL[key]]
        optional = optional + SKIP_OPTIONAL[key]
    check_map(key, val, required, optional)
    for sub, (ireq, iopt) in sorted(items.items()):
        if sub in val:
            check_list("%s.%s" % (key, sub), val[sub], ireq, iopt)

say("ok %s" % path)
PY
)"
  case "$out" in
    "ok $path"|"fail $path: "*) printf '%s\n' "$out" ;;
    *) echo "fail $path: checker error" ;;
  esac
  return 0
}

