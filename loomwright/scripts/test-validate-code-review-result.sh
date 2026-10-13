#!/usr/bin/env bash
# test-validate-code-review-result.sh — self-tests for validate-code-review-result.py,
# the `type: command` SubagentStop validator that replaced the `type: prompt`
# hook on the `loomwright:code-reviewer` matcher.
#
# WHY THE PROMPT HOOK WENT (probed 2026-09-27): the reviewer's report — the
# CODE_REVIEW_RESULT block included — reaches the runtime as the input.message
# of the LAST `SubagentHandback` tool call in agent_transcript_path, and the
# payload's last_assistant_message is only a recap that NAMES the block. The
# prompt model judged the payload, so it never had the block to check: it
# blocked one valid reviewer ("… YAML … is not valid JSON") and waved two others
# through unchecked. Section H drives the validator through that exact shape
# (the committed real-shape fixture) and asserts it both PASSES a valid handback
# block and BLOCKS an invalid one — the second is what proves the block was
# actually read, not rubber-stamped.
#
# Section I covers `--main-session`, the mode the `Stop` hook runs (a reviewer
# as the MAIN agent of its own session). It replays the committed real Stop
# payloads (fixtures/stop-payload-shape-probe.json): a main thread with a
# reviewer running in the BACKGROUND must be allowed. The retired `type: prompt`
# Stop hook judged that background child and blocked every main-thread turn end
# while it ran (2026-09-27).
#
# Section K covers the optional advisory `house_rule_verdicts` (v3 rule m,
# #431/#432): absent and empty stay valid; a malformed entry blocks; a
# `violated` verdict on a PASS block is legal. Section L keeps the verdict enum
# identical across the validator, the reviewer prompt, the Phase 4.5 prompt
# line and the schema doc.
#
# Section N covers the optional `cannot_determine` (v3 rule n, #433): absent and
# empty stay valid; every entry needs an item and a reason that is neither empty,
# missing, nor a bare "runtime-only" label; a mutant with the reason check
# disabled must accept the empty reason. Section O keeps its {item, reason} keys
# identical across the validator, the reviewer prompt, the Phase 4.5 brief line
# and the schema doc, and catches any surface still sending it to a summary line.
#
# Separate from test-result-validators.sh so the rule-by-rule coverage reads
# next to the one validator it falsifies. Same contract, same wire shape:
#   pass -> exactly `{}`;  fail -> exactly `{"decision": "block", "reason": …}`;
#   ALWAYS exit 0 (unparseable payload / absent module -> `{}`).
#
# STYLE: heredocs are never nested inside $( ) — `mk <name>` sets $F.
# EXIT: 0 on full pass, 1 on any failed assertion.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V="$SCRIPT_DIR/validate-code-review-result.py"
HOOKS="$SCRIPT_DIR/../hooks/hooks.json"
HB_FIX="$SCRIPT_DIR/fixtures/subagentstop-handback-real-shape"
HB_MAT="$HB_FIX/materialize.py"
STOP_FIX="$SCRIPT_DIR/fixtures/stop-payload-shape-probe.json"

for f in "$V" "$SCRIPT_DIR/result_block_parser.py" "$HOOKS" "$HB_MAT" \
         "$HB_FIX/payload.json" "$HB_FIX/agent-transcript.jsonl" "$STOP_FIX"; do
  if [ ! -e "$f" ]; then
    echo "FATAL  required file not found: $f" >&2
    exit 1
  fi
done

PASS_COUNT=0
FAIL_COUNT=0
ok() { echo "  ok: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
no() { echo "  FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TMPROOT="$(mktemp -d)"
cleanup() { rm -rf "$TMPROOT" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

F=""
mk() { F="$TMPROOT/$1"; cat > "$F"; }

LAST_OUT=""
LAST_RC=""

# run_v <textfile> [validator] — wrap text as last_assistant_message; the
# payload is file-redirected, never piped (see test-result-validators.sh run_v
# for the EPIPE/pipefail false-failure this avoids).
run_v() {
  local textfile="$1" validator="${2:-$V}"
  python3 -c 'import json,sys
sys.stdout.write(json.dumps({"session_id": "t", "hook_event_name": "SubagentStop",
    "agent_type": "loomwright:loomwright:code-reviewer",
    "last_assistant_message": open(sys.argv[1], encoding="utf-8").read()}))' \
    "$textfile" > "$TMPROOT/.payload.json"
  LAST_OUT="$( ( cd "$TMPROOT" && python3 "$validator" < "$TMPROOT/.payload.json" ) 2>/dev/null)"
  LAST_RC=$?
}

# verdict — "pass" for exactly {}, "block" for exactly {decision:block, reason:<non-empty>},
# else "shape:<json>" — so no assertion can pass on a drifted wire shape.
verdict() {
  printf '%s' "$LAST_OUT" | python3 -c 'import json,sys
try:
    o = json.load(sys.stdin)
except Exception:
    print("PARSE_ERROR"); sys.exit()
if o == {}:
    print("pass")
elif (isinstance(o, dict) and set(o) == {"decision", "reason"} and o["decision"] == "block"
        and isinstance(o["reason"], str) and o["reason"]):
    print("block")
else:
    print("shape:" + json.dumps(o))'
}
reason() { printf '%s' "$LAST_OUT" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("reason", ""))
except Exception: print("")'; }

assert_pass() {
  local v; v="$(verdict)"
  if [ "$LAST_RC" = "0" ] && [ "$v" = "pass" ]; then ok "$1"
  else no "$1  expected exactly {} rc 0; got rc=$LAST_RC $LAST_OUT"; fi
}
# assert_block <label> <reason substring>
assert_block() {
  local v r; v="$(verdict)"; r="$(reason)"
  if [ "$LAST_RC" = "0" ] && [ "$v" = "block" ] && [[ "$r" == *"$2"* ]]; then ok "$1"
  else no "$1  expected block with reason containing [$2]; got rc=$LAST_RC $LAST_OUT"; fi
}

# ── fixtures ────────────────────────────────────────────────────────────────
# A realistic report: prose, then the block in a ```yaml fence (what real
# reviewers emit — both 2026-09-27 captures had exactly this shape).
mk v3-diff.md <<'EOF'
## Code Review Decision: PASS

Reviewed the one changed script.

```yaml
CODE_REVIEW_RESULT:
  schema_version: 3
  review_mode: diff_review
  audit_focus: []
  trigger_paths_detected: []
  scope_expanded: []
  files_checked:
    - loomwright/scripts/send-telemetry-core.sh
  decision: PASS
  issues:
    - severity: LOW
      category: pre_existing
      file: loomwright/scripts/send-telemetry-core.sh
      line: 632
      description: "a truthy non-string agent_type would raise AttributeError"
      suggestion: "guard the type with isinstance"
  summary: "Loop fix is correct; one LOW pre-existing gap."
```
EOF
V3_DIFF="$F"

mk v3-audit.md <<'EOF'
```yaml
CODE_REVIEW_RESULT:
  schema_version: 3
  review_mode: consistency_audit
  audit_focus: [mirrored_prompt, counts]
  trigger_paths_detected: [loomwright/agents/worker.md]
  scope_expanded: [loomwright/commands/worker.md]
  files_checked:
    - loomwright/agents/worker.md
    - loomwright/commands/worker.md
  consistency_checks:
    mirrored_prompts: fail
    version_strings: pass
    counts: pass
    workflow_alignment: not_applicable
    hooks_parity: not_applicable
  consistency_summary: "commands/worker.md lags the agent prompt"
  decision: FAIL
  issues:
    - severity: HIGH
      category: drift
      drift_kind: mirrored_prompt
      file: loomwright/commands/worker.md
      description: "rule 2 wording not mirrored"
    - severity: MEDIUM
      category: drift
      drift_kind: count
      file: README.md
      description: "skill count stale"
  summary: "Mirror drift must be fixed."
```
EOF
V3_AUDIT="$F"

mk v2.md <<'EOF'
CODE_REVIEW_RESULT:
  schema_version: 2
  decision: FAIL
  issues:
    - severity: BLOCKING
      category: new
      file: src/a.py
      description: "null deref"
  summary: "one blocking bug"
EOF
V2="$F"

# sub <name> <base> <python-expr on s> — derive a variant; sets $F.
sub() {
  F="$TMPROOT/$1"
  python3 -c 'import sys
s = open(sys.argv[1], encoding="utf-8").read()
s = eval(sys.argv[2])
open(sys.argv[3], "w", encoding="utf-8").write(s)' "$TMPROOT/$2" "$3" "$F"
}

echo "== A. valid blocks pass =="
run_v "$V3_DIFF";  assert_pass "v3 diff_review (fenced YAML inside prose)"
run_v "$V3_AUDIT"; assert_pass "v3 consistency_audit, FAIL carried by HIGH drift + MEDIUM count drift (at its cap)"
run_v "$V2";       assert_pass "v2 FAIL with a new BLOCKING issue"

echo "== B. block presence + plumbing fail-safe =="
mk recap.md <<'EOF'
I've sent the review. The verdict is PASS. I sent back the CODE_REVIEW_RESULT block.
EOF
run_v "$F"; assert_block "recap that only NAMES the block -> missing" "missing CODE_REVIEW_RESULT block"
printf 'not { json' > "$TMPROOT/garbage"
LAST_OUT="$(python3 "$V" < "$TMPROOT/garbage" 2>/dev/null)"; LAST_RC=$?
assert_pass "unparseable payload -> {} exit 0 (cannot validate; never break the loop)"
LAST_OUT="$(python3 "$V" < /dev/null 2>/dev/null)"; LAST_RC=$?
assert_pass "empty stdin -> {} exit 0"

echo "== C. schema_version and COMMON rules =="
sub sv1.md v3-diff.md 's.replace("schema_version: 3", "schema_version: 1")'
run_v "$F"; assert_block "schema_version 1 -> verbatim upgrade reason" "schema_version 1 is no longer supported; upgrade to v3"
sub sv4.md v3-diff.md 's.replace("schema_version: 3", "schema_version: 4")'
run_v "$F"; assert_block "schema_version 4 -> rejected" "must be 2 or 3; got 4"
sub svnone.md v3-diff.md 's.replace("  schema_version: 3\n", "")'
run_v "$F"; assert_block "schema_version absent" "missing the schema_version field"
sub dec.md v3-diff.md 's.replace("decision: PASS", "decision: MAYBE")'
run_v "$F"; assert_block "(A) decision outside the enum" "(rule A)"
sub nosum.md v3-diff.md 's.replace("  summary: \"Loop fix is correct; one LOW pre-existing gap.\"\n", "")'
run_v "$F"; assert_block "(B) summary ABSENT" "missing the summary field (rule B)"
sub nullsum.md v3-diff.md 's.replace("summary: \"Loop fix is correct; one LOW pre-existing gap.\"", "summary: null")'
run_v "$F"; assert_block "(B) summary explicit NULL -> a DIFFERENT reason from absent" "present but empty or null (rule B)"

echo "== D. v2 rules =="
sub v2drift.md v2.md 's.replace("category: new", "category: drift")'
run_v "$F"; assert_block "v2 (a) category=drift is v3-only" "(v2 rule a)"
sub v2nofile.md v2.md 's.replace("      file: src/a.py\n", "")'
run_v "$F"; assert_block "v2 (a) issue missing file names field + index" "issue[0] is missing a non-empty file field (v2 rule a)"
sub v2med.md v2.md 's.replace("severity: BLOCKING", "severity: MEDIUM")'
run_v "$F"; assert_block "v2 (b) FAIL with no new BLOCKING/HIGH" "(v2 rule b)"
mk v2nh.md <<'EOF'
CODE_REVIEW_RESULT:
  schema_version: 2
  decision: NEEDS_HUMAN
  issues: []
  summary: "unsure"
EOF
run_v "$F"; assert_block "v2 (c) NEEDS_HUMAN with empty issues" "(v2 rule c)"

echo "== E. v3 structural rules (a-g) =="
sub mode.md v3-diff.md 's.replace("review_mode: diff_review", "review_mode: full")'
run_v "$F"; assert_block "(a) review_mode outside the enum" "(v3 rule a)"
sub focusdiff.md v3-diff.md 's.replace("audit_focus: []", "audit_focus: [docs]")'
run_v "$F"; assert_block "(b) non-empty audit_focus under diff_review" "audit_focus must be empty"
sub focusempty.md v3-audit.md 's.replace("audit_focus: [mirrored_prompt, counts]", "audit_focus: []")'
run_v "$F"; assert_block "(b) empty audit_focus under consistency_audit" "audit_focus must be non-empty"
sub focusbad.md v3-audit.md 's.replace("audit_focus: [mirrored_prompt, counts]", "audit_focus: [vibes]")'
run_v "$F"; assert_block "(b) audit_focus element outside the closed set" "audit_focus[0] must be one of"
sub notrig.md v3-diff.md 's.replace("  trigger_paths_detected: []\n", "")'
run_v "$F"; assert_block "(c) trigger_paths_detected absent" "(v3 rule c)"
sub cross.md v3-diff.md 's.replace("trigger_paths_detected: []", "trigger_paths_detected: [loomwright/agents/worker.md]")'
run_v "$F"; assert_block "(d) CROSS-FIELD: triggers under diff_review -> verbatim reason" "non-empty trigger_paths_detected requires review_mode=consistency_audit"
sub nofiles.md v3-diff.md 's.replace("  files_checked:\n    - loomwright/scripts/send-telemetry-core.sh\n", "  files_checked: []\n")'
run_v "$F"; assert_block "(e) files_checked empty -> verbatim reason" "files_checked must be a non-empty array"
sub noscope.md v3-diff.md 's.replace("  scope_expanded: []\n", "")'
run_v "$F"; assert_block "(f) scope_expanded absent" "(v3 rule f)"
sub nochecks.md v3-audit.md 's.replace("    hooks_parity: not_applicable\n", "")'
run_v "$F"; assert_block "(g) consistency_checks missing a sub-key" "missing the hooks_parity sub-key"
sub badcheck.md v3-audit.md 's.replace("version_strings: pass", "version_strings: ok")'
run_v "$F"; assert_block "(g) consistency_checks value outside the enum" "consistency_checks.version_strings must be one of"
sub nocsum.md v3-audit.md 's.replace("  consistency_summary: \"commands/worker.md lags the agent prompt\"\n", "")'
run_v "$F"; assert_block "(g) consistency_summary absent" "non-empty consistency_summary"

echo "== F. v3 issue rules (h-l) =="
sub adhoc.md v3-diff.md 's.replace("      line: 632\n", "      line: 632\n      confidence: high\n")'
run_v "$F"; assert_block "(h) ad-hoc issue key -> verbatim reason" "issue[0] contains disallowed key confidence; only schema fields are accepted"
sub nodesc.md v3-diff.md 's.replace("      description: \"a truthy non-string agent_type would raise AttributeError\"\n", "")'
run_v "$F"; assert_block "(h) issue missing description names field + index" "issue[0] is missing a non-empty description field"
sub badsev.md v3-diff.md 's.replace("severity: LOW", "severity: CRITICAL")'
run_v "$F"; assert_block "(h) severity outside the enum" "issue[0] severity must be one of"
sub nokind.md v3-audit.md 's.replace("      drift_kind: mirrored_prompt\n", "")'
run_v "$F"; assert_block "(i) drift issue without drift_kind" "(v3 rule i)"
for kind_sev in "count HIGH MEDIUM" "version_secondary BLOCKING MEDIUM" "hooks_parity MEDIUM LOW" "wording HIGH LOW"; do
  set -- $kind_sev
  sub "cap-$1.md" v3-audit.md "s.replace('severity: MEDIUM\n      category: drift\n      drift_kind: count', 'severity: $2\n      category: drift\n      drift_kind: $1')"
  run_v "$F"; assert_block "(j) drift_kind=$1 at $2 exceeds its cap $3" "drift_kind=$1 is capped at severity $3; got $2"
done
sub capok.md v3-audit.md "s.replace('severity: MEDIUM\n      category: drift\n      drift_kind: count', 'severity: LOW\n      category: drift\n      drift_kind: wording')"
run_v "$F"; assert_pass "(j) wording drift AT its LOW cap passes (boundary)"
sub konly.md v3-audit.md 's.replace("severity: HIGH", "severity: MEDIUM")'
run_v "$F"; assert_block "(k) FAIL carried only by MEDIUM issues" "(v3 rule k)"
sub kpre.md v3-audit.md 's.replace("severity: HIGH\n      category: drift\n      drift_kind: mirrored_prompt", "severity: HIGH\n      category: pre_existing")'
run_v "$F"; assert_block "(k) a HIGH pre_existing issue cannot carry FAIL" "(v3 rule k)"
sub lempty.md v3-diff.md 's.replace("decision: PASS", "decision: NEEDS_HUMAN").split("  issues:")[0] + "  issues: []\n  summary: \"x\"\n```\n"'
run_v "$F"; assert_block "(l) NEEDS_HUMAN with empty issues" "(v3 rule l)"

echo "== G. import-time fail-safe (R3) =="
mk probe.md <<'EOF'
No result block here, so a WORKING validator blocks.
EOF
PROBE="$F"
mkdir -p "$TMPROOT/nomod" "$TMPROOT/badmod"
cp "$V" "$TMPROOT/nomod/"; cp "$V" "$TMPROOT/badmod/"
printf 'def broken(:\n' > "$TMPROOT/badmod/result_block_parser.py"
run_v "$PROBE"; assert_block "control: the probe is rejected when the module IS importable" "missing CODE_REVIEW_RESULT block"
run_v "$PROBE" "$TMPROOT/nomod/$(basename "$V")"; assert_pass "result_block_parser ABSENT -> {} exit 0"
run_v "$PROBE" "$TMPROOT/badmod/$(basename "$V")"; assert_pass "result_block_parser CORRUPT -> {} exit 0"

echo "== H. SubagentHandback delivery (real payload shape, captured 2026-09-27) =="
RECAP="I've sent the review. The verdict is PASS. I sent back the CODE_REVIEW_RESULT block."
# run_hb <handback_file|-> [materialize flags…] — the committed fixture, with the
# recap in last_assistant_message and the report in the LAST SubagentHandback.
run_hb() {
  local hb="$1"; shift
  local out="$TMPROOT/hb.$RANDOM"
  python3 "$HB_MAT" "$out" "loomwright:loomwright:code-reviewer" "$hb" "$RECAP" "$@" \
    > "$out.payload.json" || { LAST_OUT="materialize failed"; LAST_RC=99; return; }
  LAST_OUT="$( ( cd "$TMPROOT" && python3 "$V" < "$out.payload.json" ) 2>/dev/null)"
  LAST_RC=$?
}
run_hb "$V3_DIFF"
assert_pass "valid block in the handback, recap in last_assistant_message -> {} (the 2026-09-27 false block)"
sub hb-bad.md v3-diff.md 's.replace("decision: PASS", "decision: NEEDS_HUMAN").split("  issues:")[0] + "  issues: []\n  summary: \"x\"\n```\n"'
run_hb "$F"
assert_block "INVALID block in the handback is BLOCKED on its rule -> the handback is really validated" "(v3 rule l)"
run_hb "$V3_AUDIT" --extra-handback "$F"
assert_pass "an earlier invalid handback is superseded by the LAST (valid) one"
run_hb -
assert_block "no handback at all, recap only -> missing block" "missing CODE_REVIEW_RESULT block"
run_hb "$V3_DIFF" --parent-handback
assert_block "a handback in the PARENT transcript is someone else's report -> not used" "missing CODE_REVIEW_RESULT block"

echo "== I. --main-session (the Stop hook; real payloads captured 2026-09-27) =="
# run_ms <probe> [agent_type|-|@absent] [textfile] [extra validator args…] —
# replay a committed Stop payload through `--main-session`, optionally
# overriding the top-level agent_type ("-" keeps it, "@absent" deletes it) and
# last_assistant_message (read from textfile).
run_ms() {
  local probe="$1" at="${2:--}" txt="${3:-}"; shift 3 2>/dev/null || shift $#
  python3 - "$STOP_FIX" "$probe" "$at" "$txt" > "$TMPROOT/.stop.json" <<'EOF'
import json, sys
fix, probe, at, txt = sys.argv[1:5]
d = json.load(open(fix, encoding="utf-8"))
p = dict(d["probe_a_main_thread_with_background_reviewer"]["payload_while_reviewer_runs"]
         if probe == "a" else d["probe_b_agent_session_reviewer"]["payload_first_turn_end"])
if at == "@absent":
    p.pop("agent_type", None)
elif at != "-":
    p["agent_type"] = at
if txt:
    p["last_assistant_message"] = open(txt, encoding="utf-8").read()
sys.stdout.write(json.dumps(p))
EOF
  LAST_OUT="$( ( cd "$TMPROOT" && python3 "$V" --main-session "$@" < "$TMPROOT/.stop.json" ) 2>/dev/null)"
  LAST_RC=$?
}
run_ms a
assert_pass "main thread, reviewer RUNNING in background_tasks[], no top-level agent_type -> {} (the 2026-09-27 false block)"
LAST_OUT="$( ( cd "$TMPROOT" && python3 "$V" < "$TMPROOT/.stop.json" ) 2>/dev/null)"; LAST_RC=$?
assert_block "control: the same payload WITHOUT --main-session is validated and blocked -> the gate is what allows it" "missing CODE_REVIEW_RESULT block"
sub ms-bad.md v3-diff.md 's.replace("decision: PASS", "decision: NEEDS_HUMAN").split("  issues:")[0] + "  issues: []\n  summary: \"x\"\n```\n"'
MS_BAD="$F"
run_ms a @absent "$MS_BAD"
assert_pass "main thread whose last message HOLDS a broken CODE_REVIEW_RESULT (inline /code-reviewer, prose about reviews) -> {}"
run_ms b
assert_block "--agent code-reviewer session, reply without a block -> blocked (the case the Stop hook exists for)" "missing CODE_REVIEW_RESULT block"
run_ms b - "$V3_DIFF"
assert_pass "--agent code-reviewer session, valid v3 block -> {}"
run_ms b - "$MS_BAD"
assert_block "--agent code-reviewer session, INVALID block -> blocked on its own rule" "(v3 rule l)"
run_ms b "loomwright:code-reviewer"
assert_block "single-prefix agent_type (the frontmatter name, user-level install) is the reviewer too" "missing CODE_REVIEW_RESULT block"
run_ms b "loomwright:loomwright:review-pr-runner"
assert_pass "another --agent session (review-pr-runner) -> {}"
run_ms b "other-plugin:code-reviewer"
assert_pass "a different plugin's code-reviewer -> {} (identity is anchored to loomwright)"
printf 'not json' > "$TMPROOT/.stop.json"
LAST_OUT="$( ( cd "$TMPROOT" && python3 "$V" --main-session < "$TMPROOT/.stop.json" ) 2>/dev/null)"; LAST_RC=$?
assert_pass "unparseable Stop payload -> {} exit 0"
printf '["loomwright:loomwright:code-reviewer"]' > "$TMPROOT/.stop.json"
LAST_OUT="$( ( cd "$TMPROOT" && python3 "$V" --main-session < "$TMPROOT/.stop.json" ) 2>/dev/null)"; LAST_RC=$?
assert_pass "non-object Stop payload -> {} exit 0"

echo "== K. house_rule_verdicts (v3 rule m — OPTIONAL, advisory, shape-checked; #431/#432) =="
# The per-rule verdict record. Absent stays valid (every pre-#431 emitter, and a
# review with no applicable house rule); present must be well-formed. A
# `violated` / `conflicts_with_requirement` verdict on a PASS block is LEGAL —
# the field never changes `decision`, so no rule ties a verdict value to it.
HRV='  house_rule_verdicts:
    - id: ui-select-max-10
      verdict: conflicts_with_requirement
      reason: "AC5 asks for a Select over 20 cities; the rule wants AutoComplete above ~10"
    - id: ui-failure-not-toast-only
      verdict: violated
      reason: "the refusal path only raises a toast"
    - id: ui-button-component
      verdict: followed
      reason: "uses <Button> from the design system"
    - id: api-error-envelope
      verdict: not_applicable
      reason: "the diff touches no API handler"
'
export HRV
sub hrv.md v3-diff.md 's.replace("  summary: ", __import__("os").environ["HRV"] + "  summary: ")'
HRV_OK="$F"
run_v "$HRV_OK"; assert_pass "(m) present: all four verdict values on a PASS block pass (advisory — never tied to decision)"
run_v "$V3_DIFF"; assert_pass "(m) absent: a block with no house_rule_verdicts still passes (old emitters)"
sub hrvempty.md v3-diff.md 's.replace("  summary: ", "  house_rule_verdicts: []\n  summary: ")'
run_v "$F"; assert_pass "(m) present but empty array passes"
sub hrvenum.md hrv.md 's.replace("verdict: violated", "verdict: broken")'
run_v "$F"; assert_block "(m) bad enum value -> names index, enum and value" "house_rule_verdicts[1] verdict must be one of followed, violated, conflicts_with_requirement, not_applicable; got 'broken'"
sub hrvscalar.md v3-diff.md 's.replace("  summary: ", "  house_rule_verdicts: all followed\n  summary: ")'
run_v "$F"; assert_block "(m) a scalar instead of an array" "house_rule_verdicts must be an array when present"
sub hrvstritem.md v3-diff.md 's.replace("  summary: ", "  house_rule_verdicts:\n    - ui-select-max-10 followed\n  summary: ")'
run_v "$F"; assert_block "(m) an array entry that is a plain string, not a mapping" "house_rule_verdicts[0] is not a mapping"
sub hrvnoreason.md hrv.md 's.replace("      reason: \"uses <Button> from the design system\"\n", "")'
run_v "$F"; assert_block "(m) entry without a reason" "house_rule_verdicts[2] is missing a non-empty reason field"
sub hrvnoid.md hrv.md 's.replace("    - id: api-error-envelope\n      verdict", "    - verdict")'
run_v "$F"; assert_block "(m) entry without an id" "house_rule_verdicts[3] is missing a non-empty id field"
sub hrvkey.md hrv.md 's.replace("      verdict: followed\n", "      verdict: followed\n      severity: LOW\n")'
run_v "$F"; assert_block "(m) ad-hoc entry key" "house_rule_verdicts[2] contains disallowed key severity"
sub hrvdup.md hrv.md 's.replace("id: ui-button-component", "id: ui-select-max-10")'
run_v "$F"; assert_block "(m) the same rule given two verdicts" "house_rule_verdicts[2] repeats id ui-select-max-10"
# Mutation control: a validator with the enum check deleted must ACCEPT the bad
# value — proving the bad-enum assertion above is carried by that check alone.
MUT_V="$TMPROOT/mut-validate-code-review-result.py"
python3 - "$V" "$MUT_V" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
needle = "        if verdict not in HOUSE_RULE_VERDICTS:\n"
assert s.count(needle) == 1, "mutation anchor not found exactly once"
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(needle, "        if False:\n"))
PY
cp "$SCRIPT_DIR/result_block_parser.py" "$TMPROOT/"
if [ -s "$MUT_V" ] && ! cmp -s "$V" "$MUT_V"; then
  sub hrvenum2.md hrv.md 's.replace("verdict: violated", "verdict: broken")'
  run_v "$F" "$MUT_V"; assert_pass "(m-mut) CONFIRMED: with the enum check removed the bad value is accepted (the check is load-bearing)"
  run_v "$F"; assert_block "(m-mut) positive control: the real validator still rejects it" "verdict must be one of"
else
  no "(m-mut) INVALID mutant: empty or identical to the original"
fi

echo "== L. house_rule_verdicts: prompt <-> validator <-> schema parity =="
# The verdict enum lives in the validator; the reviewer prompt, the Phase 4.5
# prompt line and the schema doc each restate it. One drifted copy would make a
# reviewer emit a value the hook rejects (or never emit one it accepts). And the
# ids the reviewer must answer by only exist when its read passes --with-ids.
PLUGIN_DIR="$SCRIPT_DIR/.."
parity="$(python3 - "$V" "$PLUGIN_DIR" <<'PY'
import os, re, sys
v, root = sys.argv[1], sys.argv[2]
src = open(v, encoding="utf-8").read()
m = re.search(r'^HOUSE_RULE_VERDICTS = \(([^)]*)\)', src, re.M)
if not m:
    print("validator HOUSE_RULE_VERDICTS tuple not found"); sys.exit()
enum = re.findall(r'"([a-z_]+)"', m.group(1))
surfaces = {
    "agents/code-reviewer.md": "5c. **House-rule conformance",
    "skills/self-heal-advisory/SKILL.md": "**HOUSE-RULES ADVISORY (non-gating",
    "docs/result-schemas/code-review-result.md": "house_rule_verdicts: object[]",
}
bad = []
for rel, anchor in surfaces.items():
    text = open(os.path.join(root, rel), encoding="utf-8").read()
    i = text.find(anchor)
    if i < 0:
        bad.append("%s: anchor %r missing" % (rel, anchor)); continue
    window = text[i:i + 2500]
    for val in enum:
        if not re.search(r"(?<![a-z_])%s(?![a-z_])" % val, window):
            bad.append("%s: verdict %s not restated next to %r" % (rel, val, anchor))
for rel in ("agents/code-reviewer.md", "skills/self-heal-advisory/SKILL.md"):
    text = open(os.path.join(root, rel), encoding="utf-8").read()
    if not re.search(r'read-rules\.sh" <[^<>]{0,40}> --with-ids', text):
        bad.append("%s: the house-rules read no longer passes --with-ids" % rel)
print("ok" if not bad and len(enum) == 4 else "; ".join(bad) or "enum size %d" % len(enum))
PY
)"
if [ "$parity" = "ok" ]; then ok "verdict enum restated on all three surfaces; both reads pass --with-ids"
else no "house_rule_verdicts parity: $parity"; fi

echo "== N. cannot_determine (v3 rule n — OPTIONAL; every entry needs a reason; #433) =="
# What the reviewer could not decide by reading the code. #433: a PASS listed
# focus order as "runtime-only" with no reason, and a human then found the
# defect by reading the same diff. Absent stays valid (old emitters); present,
# each entry must say WHY — what would have to run to decide it.
CD='  cannot_determine:
    - item: "toolbar wraps at 320px"
      reason: "needs the page rendered at a 320px viewport to see whether the buttons wrap"
    - item: "AC4: list filters in under 200ms"
      reason: "needs a timed run against the real dataset"
'
export CD
sub cd.md v3-diff.md 's.replace("  summary: ", __import__("os").environ["CD"] + "  summary: ")'
CD_OK="$F"
run_v "$CD_OK"; assert_pass "(n) reason present on every entry -> pass"
# The PR-body-only criterion (#511/PR #520's step-5a case) names what would have
# to be READ, not run — it must satisfy the same rule.
sub cdprbody.md cd.md 's.replace("reason: \"needs a timed run against the real dataset\"", "reason: \"only the PR body shows it; the body is not in the diff\"")'
run_v "$F"; assert_pass "(n) a PR-body-only criterion with a reason naming where the evidence lives -> pass"
run_v "$V3_DIFF"; assert_pass "(n) absent: a block with no cannot_determine still passes (old emitters)"
sub cdempty.md v3-diff.md 's.replace("  summary: ", "  cannot_determine: []\n  summary: ")'
run_v "$F"; assert_pass "(n) present but empty array passes"
sub cdblank.md cd.md 's.replace("reason: \"needs a timed run against the real dataset\"", "reason: \"\"")'
run_v "$F"; assert_block "(n) EMPTY reason -> block naming the index and the field" "cannot_determine[1] is missing a non-empty reason field"
sub cdmissing.md cd.md 's.replace("      reason: \"needs a timed run against the real dataset\"\n", "")'
run_v "$F"; assert_block "(n) MISSING reason key -> block" "cannot_determine[1] is missing a non-empty reason field"
sub cdbare.md cd.md 's.replace("reason: \"needs a timed run against the real dataset\"", "reason: \"Runtime-only.\"")'
run_v "$F"; assert_block "(n) a bare runtime label is not a reason (the #433 shape)" "cannot_determine[1] reason 'Runtime-only.' only restates the label"
sub cdnoitem.md cd.md 's.replace("    - item: \"toolbar wraps at 320px\"\n      reason", "    - reason")'
run_v "$F"; assert_block "(n) entry without an item" "cannot_determine[0] is missing a non-empty item field"
sub cdkey.md cd.md 's.replace("      reason: \"needs a timed run", "      severity: LOW\n      reason: \"needs a timed run")'
run_v "$F"; assert_block "(n) ad-hoc entry key" "cannot_determine[1] contains disallowed key severity"
sub cdscalar.md v3-diff.md 's.replace("  summary: ", "  cannot_determine: focus order (runtime-only)\n  summary: ")'
run_v "$F"; assert_block "(n) a scalar summary line instead of an array" "cannot_determine must be an array when present"
sub cdstr.md v3-diff.md 's.replace("  summary: ", "  cannot_determine:\n    - focus order\n  summary: ")'
run_v "$F"; assert_block "(n) an array entry that is a plain string, not a mapping" "cannot_determine[0] is not a mapping"
# Mutation control: with the required-field loop disabled the empty reason must
# be ACCEPTED — the EMPTY-reason assertion above is carried by that check alone.
MUT_N="$TMPROOT/mutn-validate-code-review-result.py"
python3 - "$V" "$MUT_N" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
needle = "        for key in CANNOT_DETERMINE_KEYS:\n            if key not in entry or is_empty_scalar(entry.get(key)):\n"
assert s.count(needle) == 1, "mutation anchor not found exactly once"
open(sys.argv[2], "w", encoding="utf-8").write(
    s.replace(needle, "        for key in CANNOT_DETERMINE_KEYS:\n            if False:\n"))
PY
cp "$SCRIPT_DIR/result_block_parser.py" "$TMPROOT/"
if [ -s "$MUT_N" ] && ! cmp -s "$V" "$MUT_N"; then
  sub cdblank2.md cd.md 's.replace("reason: \"needs a timed run against the real dataset\"", "reason: \"\"")'
  run_v "$F" "$MUT_N"; assert_pass "(n-mut) CONFIRMED: with the reason check removed an empty reason is accepted (the check is load-bearing)"
  run_v "$F"; assert_block "(n-mut) positive control: the real validator still rejects it" "is missing a non-empty reason field"
else
  no "(n-mut) INVALID mutant: empty or identical to the original"
fi

echo "== O. cannot_determine: validator <-> reviewer <-> Phase 4.5 line <-> schema parity =="
# The entry keys live in the validator. The reviewer prompt, the Phase 4.5 brief
# line and the schema doc each restate where cannot_determine goes. A surface
# still saying "one summary line" would have a reviewer emit a scalar the hook
# now rejects.
parity_cd="$(python3 - "$V" "$SCRIPT_DIR/.." <<'PY'
import os, re, sys
v, root = sys.argv[1], sys.argv[2]
src = open(v, encoding="utf-8").read()
m = re.search(r'^CANNOT_DETERMINE_KEYS = \(([^)]*)\)', src, re.M)
if not m:
    print("validator CANNOT_DETERMINE_KEYS tuple not found"); sys.exit()
keys = re.findall(r'"([a-z_]+)"', m.group(1))
surfaces = {
    "agents/code-reviewer.md": "**`cannot_determine` — admission rule",
    "skills/self-heal-advisory/SKILL.md": "**BRIEF-CONFORMANCE ADVISORY (",
    "docs/result-schemas/code-review-result.md": "cannot_determine: object[]",
}
bad = []
for rel, anchor in surfaces.items():
    text = open(os.path.join(root, rel), encoding="utf-8").read()
    i = text.find(anchor)
    if i < 0:
        bad.append("%s: anchor %r missing" % (rel, anchor)); continue
    window = text[i:i + 4000]
    for k in keys:
        if not re.search(r"(?<![a-z_])%s(?=[:,}`])" % k, window):
            bad.append("%s: entry key %s not restated next to %r" % (rel, k, anchor))
    if re.search(r"(?i)one summary line[^.]{0,60}cannot_determine|cannot_determine[^.]{0,40}one-line summary", window):
        bad.append("%s: still sends cannot_determine to a summary line" % rel)
print("ok" if not bad and keys == ["item", "reason"] else "; ".join(bad) or "keys %r" % keys)
PY
)"
if [ "$parity_cd" = "ok" ]; then ok "cannot_determine {item, reason} restated on all three surfaces; none still says 'summary line'"
else no "cannot_determine parity: $parity_cd"; fi

echo "== J. hooks.json wiring =="
wiring="$(python3 - "$HOOKS" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
leaves = [h for m in d["hooks"]["SubagentStop"] if m.get("matcher") == "loomwright:code-reviewer"
          for h in m["hooks"]]
prompts = [h for h in leaves if h.get("type") == "prompt"]
val = [h for h in leaves if h.get("type") == "command"
       and "validate-code-review-result.py" in h.get("command", "")]
stop = [h for m in d["hooks"].get("Stop", []) for h in m["hooks"]]
stop_val = [h for h in stop if h.get("type") == "command"
            and "validate-code-review-result.py" in h.get("command", "")]
if prompts:
    print("prompt hook still wired")
elif len(val) != 1:
    print("expected exactly one validator leaf, got %d" % len(val))
elif not val[0]["command"].rstrip().endswith("|| true"):
    print("validator leaf lacks the fail-safe `|| true`")
elif "--main-session" in val[0]["command"]:
    print("SubagentStop leaf must not carry --main-session")
elif [h for h in stop if h.get("type") == "prompt"]:
    print("Stop still carries a prompt hook")
elif len(stop_val) != 1 or "--main-session" not in stop_val[0]["command"]:
    print("Stop: expected exactly one validator leaf with --main-session")
elif not stop_val[0]["command"].rstrip().endswith("|| true"):
    print("Stop validator leaf lacks the fail-safe `|| true`")
else:
    print("ok")
EOF
)"
if [ "$wiring" = "ok" ]; then ok "code-reviewer matcher + Stop: one command validator leaf each (Stop with --main-session), || true, no prompt leaf"
else no "code-reviewer matcher wiring: $wiring"; fi

echo "RESULT  pass=$PASS_COUNT  fail=$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
