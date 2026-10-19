"""result_nested_keys.py — the ONE table of nested-object key sets for result blocks.

Mirrors the "Nested-object key sets" paragraphs of docs/result-schemas/supervisor-result.md
and docs/result-schemas/review-heal-result.md; update together with them.

Three readers import it (issue #616 — before it, the table lived only inside the
automate-trail.d/sidecar.sh heredoc, so a malformed nested object was caught only at the trail
push, after the agent that could fix it had exited):
  - automate-trail.d/sidecar.sh  `sidecar-check` (the trail evidence gate) — first error wins;
  - automate-next-step.sh        the RUN report refusal under /automate (write time);
  - validate-supervisor-result.py the supervisor-runner result hook (rule 15).

`nested_errors()` is pure: it never prints and never exits, it returns every error in the
order the old sidecar check met them, so `errors[0]` is the message that check printed.
Each error is (token, message): token is one of NESTED_TOKENS — stable, plugin-defined, no
project content — and message is the human text ("SUPERVISOR_RESULT ground_truth missing
required key checked"). Value enums are not checked here — key shape only.
"""

import result_block_parser as R

# Per field: (shape, required, optional, item_tables) where shape is "map" (one mapping) or
# "list" (a list of mappings, each item checked against required/optional; None = items must
# be mappings, keys unpinned), and item_tables maps a list-valued key of the mapping to its own
# (required, optional) item table.
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

# The closed reason-token set an error carries (#618 reports these, never the message text).
NESTED_TOKENS = ("wrong_shape", "missing_key", "non_schema_key")


def _check_map(errs, name, label, obj, required, optional):
    if not isinstance(obj, dict):
        errs.append(("wrong_shape", "%s %s is not a mapping" % (name, label)))
        return
    if required is None:
        return
    for k in required:
        if k not in obj:
            errs.append(("missing_key", "%s %s missing required key %s" % (name, label, k)))
    allowed_keys = set(required) | set(optional)
    for k in obj:
        if k not in allowed_keys:
            errs.append(("non_schema_key", "%s %s carries non-schema key %s" % (name, label, k)))


def _check_list(errs, name, label, val, required, optional):
    if not isinstance(val, list):
        errs.append(("wrong_shape", "%s %s is not a list" % (name, label)))
        return
    for i, item in enumerate(val):
        _check_map(errs, name, "%s[%d]" % (label, i), item, required, optional)


def nested_errors(name, fields):
    """Every nested key-set error of a parsed `name` block (SUPERVISOR_RESULT or
    REVIEW_HEAL_RESULT), in check order. [] when clean or when `name` has no table."""
    errs = []
    for key, (shape, required, optional, items) in sorted(NESTED[name].items()):
        if not R.present(fields, key):
            continue
        val = fields.get(key)
        if shape == "list":
            _check_list(errs, name, key, val, required, optional)
            continue
        # Skip form: checked false + status skipped|unverified makes the count/list keys
        # optional (absent reads as 0 / []). `checked` itself stays required.
        if key in SKIP_OPTIONAL and isinstance(val, dict) \
                and R.as_bool(val.get("checked"))[0] is False \
                and R.as_text(val.get("status")).strip() in ("skipped", "unverified"):
            required = [k for k in required if k not in SKIP_OPTIONAL[key]]
            optional = optional + SKIP_OPTIONAL[key]
        before = len(errs)
        _check_map(errs, name, key, val, required, optional)
        if len(errs) > before and not isinstance(val, dict):
            continue
        for sub, (ireq, iopt) in sorted(items.items()):
            if sub in val:
                _check_list(errs, name, "%s.%s" % (key, sub), val[sub], ireq, iopt)
    return errs
