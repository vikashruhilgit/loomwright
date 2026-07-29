#!/usr/bin/env bash
# Self-test for scripts/check-contract-parity.sh (repo-root CI guard).
# Auto-run by CI's test-*.sh loop. Deterministic, no network, no repo writes
# (fixtures live in mktemp -d).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-contract-parity.sh"
[ -f "$GUARD" ] || { echo "FAIL: guard not found at $GUARD" >&2; exit 1; }

pass=0; total=0
check() { # $1 desc, $2 expected exit (0|1), then the command
  local desc="$1" want="$2"; shift 2
  total=$((total+1))
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ] || { [ "$want" -eq 1 ] && [ "$got" -ne 0 ]; }; then
    echo "ok    $desc"; pass=$((pass+1))
  else
    echo "FAIL  $desc (exit $got, wanted $want)"
  fi
}

make_fixture() { # $1 = fixture dir; writes a minimal valid tree
  local d="$1"
  mkdir -p "$d/loomwright/hooks" "$d/loomwright/agents" "$d/loomwright/scripts" \
           "$d/loomwright/skills/self-heal-advisory" \
           "$d/loomwright/skills/preflight-sync" \
           "$d/loomwright/skills/supervisor-config"
  # the gate's ENUMS scope includes this skill (v14.23.0 supervisor diet) and
  # errs loudly when a scoped file is missing — fixtures must provide it
  cat >"$d/loomwright/skills/self-heal-advisory/SKILL.md" <<'EOF2'
Advisory statuses: status: pass, status: advisory_failures, status: advisory_violations,
status: unverified, status: skipped. Gating: heal_decision: PASS / heal_decision: ESCALATED / heal_decision: null.
EOF2
  # v15.4.0 supervisor prompt refactor moved SUPERVISOR_RESULT emit sites into
  # these two skills; the ENUMS scope covers them, so fixtures must provide them
  cat >"$d/loomwright/skills/preflight-sync/SKILL.md" <<'EOF2'
Preflight emit sites: status: checkpoint on revise-scope, status: failed on abort/fail-closed.
EOF2
  cat >"$d/loomwright/skills/supervisor-config/SKILL.md" <<'EOF2'
Resume-gate refusal emit: status: failed with error resume_state_invalid.
EOF2
  # hooks.json mentioning every manifest field for every matcher (pin guard satisfied)
  python3 - "$d/loomwright/hooks/hooks.json" <<'PY'
import json,sys
def prompt(fields): return "Verify block contains " + ", ".join(fields) + " fields."
mk=lambda m,f:{"matcher":f"loomwright:{m}","hooks":[{"type":"prompt","prompt":prompt(f),"timeout":30}]}
h={"hooks":{"SubagentStop":[
  mk("worker",["schema_version","task_id","status","files_modified","summary","outputs_verified","outputs_gap"]),
  mk("execute-manager",["schema_version","subtasks_completed","worktrees","merge_order","summary","completed_so_far","remaining","resume_context","reason"]),
  mk("qa-executor",["schema_version","tests_generated","tests_passed","summary","coverage_estimate"]),
  mk("supervisor-runner",["schema_version","status","pr_url","heal_loop_ran","heal_iterations","heal_decision","heal_fixable_issues_fixed","heal_remaining_issues","error","summary"]),
  mk("plan-reviewer",["schema_version","decision","issues","severity","section","description","summary"]),
  mk("code-reviewer",["schema_version","decision","summary","severity","category","review_mode","audit_focus","trigger_paths_detected","scope_expanded","files_checked"]),
]}}
json.dump(h,open(sys.argv[1],"w"))
PY
  # agent prompts naming every required field, with in-enum literals only
  cat >"$d/loomwright/agents/worker.md" <<'EOF'
Emit WORKER_RESULT: schema_version, task_id, status: completed, files_modified,
summary, outputs_verified (status: present / status: missing), outputs_gap.
Other statuses: status: failed, status: partial.
EOF
  cat >"$d/loomwright/agents/execute-manager.md" <<'EOF'
EXECUTE_RESULT: schema_version, subtasks_completed (status: completed), worktrees,
merge_order, summary. EXECUTE_CHECKPOINT: completed_so_far, remaining (status: pending),
in_progress entries (status: in_progress), resume_context, reason. status: failed too.
EOF
  cat >"$d/loomwright/agents/qa-executor.md" <<'EOF'
QA_RESULT fields: schema_version, tests_generated, tests_passed, coverage_estimate, summary.
EOF
  cat >"$d/loomwright/agents/supervisor.md" <<'EOF'
SUPERVISOR_RESULT: schema_version, status: completed | status: failed | status: checkpoint
| status: completed_with_escalation, pr_url, heal_loop_ran, heal_iterations,
heal_decision: PASS or heal_decision: ESCALATED or heal_decision: null,
heal_fixable_issues_fixed, heal_remaining_issues, error, summary.
EOF
  cat >"$d/loomwright/agents/plan-reviewer.md" <<'EOF'
PLAN_REVIEW_RESULT: schema_version, decision: PASS / decision: FAIL / decision: NEEDS_HUMAN,
issues with severity, section, description; summary.
EOF
  cat >"$d/loomwright/agents/code-reviewer.md" <<'EOF'
CODE_REVIEW_RESULT: schema_version, decision: PASS, summary, issues with severity and
category, review_mode, audit_focus, trigger_paths_detected, scope_expanded, files_checked.
decision: FAIL and decision: NEEDS_HUMAN are the other outcomes.
EOF
}

# ── fallback-branch fixture helpers (v15.17.0) ───────────────────────────────
# make_fixture() gives EVERY matcher a `type: prompt` hook, so on its own it
# gives the guard's command-type fallback ZERO coverage. These helpers rewrite
# a matcher into the post-conversion `type: command` shape so the fallback's
# selection rule can be exercised — and falsified.

set_command_hooks() { # $1 fixture dir, $2 matcher substring, $3.. command strings
  local d="$1" matcher="$2"; shift 2
  python3 - "$d/loomwright/hooks/hooks.json" "$matcher" "$@" <<'PY'
import json,sys
p,matcher,cmds=sys.argv[1],sys.argv[2],sys.argv[3:]
h=json.load(open(p))
for e in h["hooks"]["SubagentStop"]:
    if matcher in e["matcher"]:
        e["hooks"]=[{"type":"command","command":c} for c in cmds]
json.dump(h,open(p,"w"))
PY
}

write_validator() { # $1 fixture dir, $2 plugin-relative path, $3 comma-separated fields
  local d="$1" rel="$2" fields="$3" f
  mkdir -p "$(dirname "$d/loomwright/$rel")"
  {
    echo '#!/usr/bin/env python3'
    echo '"""Stand-in validator. Real validators name required fields as dict'
    echo 'keys / constants — that literal presence is what pin-drift follows."""'
    echo 'REQUIRED = ['
    IFS=',' read -ra _fl <<<"$fields"
    for f in "${_fl[@]}"; do echo "    \"$f\","; done
    echo ']'
  } >"$d/loomwright/$rel"
}

write_decoy() { # $1 fixture dir, $2 plugin-relative path, $3 comma-separated fields
  local d="$1" rel="$2" fields="$3" f
  mkdir -p "$(dirname "$d/loomwright/$rel")"
  {
    echo '#!/usr/bin/env bash'
    echo '# Unrelated sibling command hook — models send-telemetry-core.sh,'
    echo '# which really does mention result-block field names in passing.'
    IFS=',' read -ra _fl <<<"$fields"
    for f in "${_fl[@]}"; do echo "echo \"reporting $f\""; done
  } >"$d/loomwright/$rel"
}

write_prose_validator() { # $1 dir, $2 rel, $3 code fields, $4 prose-only field, $5 module|function|comment|bare
  # A stand-in validator that names $4 ONLY as PROSE, never in executable code —
  # the shape a real validator takes when its executable rule block is deleted
  # but the surrounding commentary keeps transcribing the rule. $5 selects which
  # of the four separable prose placements carries it.
  local d="$1" rel="$2" fields="$3" prose="$4" where="$5" f
  mkdir -p "$(dirname "$d/loomwright/$rel")"
  {
    echo '#!/usr/bin/env python3'
    if [ "$where" = module ]; then
      echo '"""Stand-in validator whose module docstring transcribes its numbered'
      echo 'rules verbatim, exactly as every real ST-1 validator does:'
      echo ''
      echo "  (4) if tests were run, $prose is present"
      echo '"""'
    else
      echo '"""Stand-in validator. Rule text lives below."""'
    fi
    echo 'REQUIRED = ['
    IFS=',' read -ra _fl <<<"$fields"
    for f in "${_fl[@]}"; do echo "    \"$f\","; done
    echo ']'
    if [ "$where" = bare ]; then
      # PEP-258 "attribute docstring": a bare string STATEMENT documenting the
      # constant above it. Not body[0] of anything, so a body[0]-only strip
      # leaves it — and it is a no-op, so it is not an executable check either.
      echo "\"\"\"The required fields. Rule (4): $prose is present when tests ran.\"\"\""
    fi
    echo ''
    echo ''
    echo 'def _missing(fields):'
    if [ "$where" = function ]; then
      echo '    """Presence helper.'
      echo ''
      echo "    Rule (4): $prose is present when tests were run."
      echo '    """'
    fi
    if [ "$where" = comment ]; then
      # Section-header comment in the real validators' own shape. `#` is not an
      # AST node, so it survives any docstring strip.
      echo "    # ── (4) $prose present when tests were run ────────────────"
      echo "    # PRESENCE, not truthiness: \`$prose: 0.0\` is a legitimate value."
    fi
    echo '    return [k for k in REQUIRED if k not in fields]'
  } >"$d/loomwright/$rel"
}

write_hashstring_validator() { # $1 dir, $2 rel path, $3 comma-separated code fields, $4 field carried after a `#`-bearing string
  # A stand-in validator that is FULLY compliant — every pinned field appears in
  # executable code — but which carries a `#` INSIDE a string literal, with $4's
  # only mention after it on the same line. Models
  # validate-launch-pad-result.py:118 (`line.strip().startswith("#")`), the
  # parser's own comment-marker literal.
  #
  # This is the falsification for the tokenize-vs-regex implementation choice:
  # a line-based strip ("drop from the first `#` to end of line") deletes the
  # rest of that line along with the field name, and the guard then reports a
  # pin-drift that does not exist. Only a token-aware strip keeps it.
  local d="$1" rel="$2" fields="$3" after="$4" f
  mkdir -p "$(dirname "$d/loomwright/$rel")"
  {
    echo '#!/usr/bin/env python3'
    echo '"""Stand-in validator with a `#` inside a string literal."""'
    echo 'REQUIRED = ['
    IFS=',' read -ra _fl <<<"$fields"
    for f in "${_fl[@]}"; do echo "    \"$f\","; done
    echo ']'
    # SAME LINE, deliberately: a line-based strip works per line, so $4 must sit
    # AFTER the in-string `#` on that line for the corruption to be observable.
    echo "COMMENT_MARKER = \"#\"; KEY = \"$after\"  # marker above is not a comment"
    echo ''
    echo ''
    echo 'def _missing(fields):'
    echo '    return [k for k in REQUIRED + [KEY] if k not in fields]'
  } >"$d/loomwright/$rel"
}

QA_FIELDS='schema_version,tests_generated,tests_passed,summary,coverage_estimate'
VALIDATOR_CMD='python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate-qa-result.py" || true'
DECOY_CMD='payload=$(cat); printf "%s" "$payload" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/send-telemetry-core.sh" || true'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. Clean fixture passes
make_fixture "$TMP/clean"
check "clean fixture passes" 0 bash "$GUARD" --root "$TMP/clean"

# 2. Missing hook-required field in an agent prompt fails (the qa-executor trap class)
make_fixture "$TMP/missing-field"
# BSD sed (macOS) needs -i '' (empty backup suffix); GNU sed rejects the empty
# arg — try BSD form first, fall back to GNU on failure.
sed -i '' -e 's/coverage_estimate, summary/summary/' "$TMP/missing-field/loomwright/agents/qa-executor.md" 2>/dev/null \
  || sed -i -e 's/coverage_estimate, summary/summary/' "$TMP/missing-field/loomwright/agents/qa-executor.md"
check "missing hook-required field fails" 1 bash "$GUARD" --root "$TMP/missing-field"

# 3. Out-of-enum status literal fails (the `status: paused` class)
make_fixture "$TMP/bad-enum"
printf '\nOn crash: pause the phase (status: paused) and exit.\n' >> "$TMP/bad-enum/loomwright/agents/supervisor.md"
check "out-of-enum status literal fails" 1 bash "$GUARD" --root "$TMP/bad-enum"

# 4. Pin-drift: hooks.json drops a field the manifest still pins → fails
make_fixture "$TMP/pin-drift"
python3 - "$TMP/pin-drift/loomwright/hooks/hooks.json" <<'PY'
import json,sys
p=sys.argv[1]; h=json.load(open(p))
for e in h["hooks"]["SubagentStop"]:
    if "qa-executor" in e["matcher"]:
        e["hooks"][0]["prompt"]=e["hooks"][0]["prompt"].replace(", coverage_estimate","")
json.dump(h,open(p,"w"))
PY
check "hooks.json pin-drift fails" 1 bash "$GUARD" --root "$TMP/pin-drift"

# ── 6-9: the command-type fallback branch (AC-6c) ────────────────────────────
# Cases 1-4 above never reach it: make_fixture gives every matcher a prompt
# hook. Without these, the only thing touching the fallback is case 5 ("real
# repo tree passes") — a one-directional green check a fail-OPEN implementation
# satisfies just as happily as a correct one.

# 6. (a-i) No prompt hook + exactly one validator command hook → the guard
#    resolves the validator's SOURCE as the rule text and passes. A decoy
#    sibling command entry is present, mirroring the real post-conversion
#    matchers that also carry telemetry / progress-event hooks.
make_fixture "$TMP/cmd-fallback-ok"
write_validator "$TMP/cmd-fallback-ok" scripts/validate-qa-result.py "$QA_FIELDS"
write_decoy "$TMP/cmd-fallback-ok" scripts/send-telemetry-core.sh "$QA_FIELDS"
set_command_hooks "$TMP/cmd-fallback-ok" qa-executor "$VALIDATOR_CMD" "$DECOY_CMD"
check "command-fallback resolves the validator source" 0 bash "$GUARD" --root "$TMP/cmd-fallback-ok"

# 7. (a-ii) THE FAIL-OPEN FALSIFICATION (R0b). Same shape, but coverage_estimate
#    is dropped from the validator source while the decoy sibling script still
#    mentions it. An implementation that concatenated every command entry's
#    source would find the field in send-telemetry-core.sh and PASS — green
#    while enforcing nothing. Correct selection greps only the validator and
#    fires pin-drift.
make_fixture "$TMP/cmd-fallback-drift"
write_validator "$TMP/cmd-fallback-drift" scripts/validate-qa-result.py \
  'schema_version,tests_generated,tests_passed,summary'
write_decoy "$TMP/cmd-fallback-drift" scripts/send-telemetry-core.sh "$QA_FIELDS"
set_command_hooks "$TMP/cmd-fallback-drift" qa-executor "$VALIDATOR_CMD" "$DECOY_CMD"
check "command-fallback pin-drift fails despite decoy sibling mentioning the field" 1 \
  bash "$GUARD" --root "$TMP/cmd-fallback-drift"

# 8. (b) Zero validator command entries — only unrelated scripts. Must ERROR,
#    not fall through to an unrelated script and not silently pass.
make_fixture "$TMP/cmd-fallback-none"
write_decoy "$TMP/cmd-fallback-none" scripts/send-telemetry-core.sh "$QA_FIELDS"
set_command_hooks "$TMP/cmd-fallback-none" qa-executor "$DECOY_CMD" \
  'bash "${CLAUDE_PLUGIN_ROOT}/scripts/send-webhook.sh" || true'
check "no validator command entry errors (not silently passes)" 1 \
  bash "$GUARD" --root "$TMP/cmd-fallback-none"

# 9. (c) Two validator-matching command entries — ambiguous rule source. Must
#    ERROR rather than pick one by hook ordering that nothing asserts.
make_fixture "$TMP/cmd-fallback-two"
write_validator "$TMP/cmd-fallback-two" scripts/validate-qa-result.py "$QA_FIELDS"
write_validator "$TMP/cmd-fallback-two" scripts/validate-qa2-result.py "$QA_FIELDS"
set_command_hooks "$TMP/cmd-fallback-two" qa-executor "$VALIDATOR_CMD" \
  'python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate-qa2-result.py" || true'
check "two validator command entries error (ambiguous rule source)" 1 \
  bash "$GUARD" --root "$TMP/cmd-fallback-two"

# ── 10-11: PROSE MUST NOT SATISFY THE PIN-DRIFT GREP ─────────────────────────
# The R0b fail-open class one layer deeper. Cases 6-9 all put field names in
# executable code, so they cannot tell a guard that greps the validator's RAW
# source from one that greps only its CODE. Every real ST-1 validator opens
# with a docstring transcribing its numbered rules verbatim, so deleting an
# executable rule block leaves the field named in prose and an unstripped guard
# stays green while enforcing nothing.

# 10. Field named ONLY in the MODULE docstring → pin-drift, not a pass.
make_fixture "$TMP/cmd-fallback-prose-module"
write_prose_validator "$TMP/cmd-fallback-prose-module" scripts/validate-qa-result.py \
  'schema_version,tests_generated,tests_passed,summary' coverage_estimate module
set_command_hooks "$TMP/cmd-fallback-prose-module" qa-executor "$VALIDATOR_CMD"
check "field named only in the module docstring fails (prose is not a check)" 1 \
  bash "$GUARD" --root "$TMP/cmd-fallback-prose-module"

# 11. Same, but the field survives only in a FUNCTION docstring. Stripping just
#     the module docstring narrows the hole without closing it: on the real
#     tree files_modified survives only in validate-worker-result.py's
#     _non_empty_list() docstring, and worktrees only in
#     validate-execute-result.py's _check_worktree_paths(), once their
#     executable checks are deleted. Verified: this fixture passes against a
#     module-docstring-only strip, so without it the two implementations are
#     indistinguishable to this suite.
make_fixture "$TMP/cmd-fallback-prose-fn"
write_prose_validator "$TMP/cmd-fallback-prose-fn" scripts/validate-qa-result.py \
  'schema_version,tests_generated,tests_passed,summary' coverage_estimate function
set_command_hooks "$TMP/cmd-fallback-prose-fn" qa-executor "$VALIDATOR_CMD"
check "field named only in a function docstring fails (module-only strip is not enough)" 1 \
  bash "$GUARD" --root "$TMP/cmd-fallback-prose-fn"

# 12. Same, but the field survives only in a `#` COMMENT. Comments are not AST
#     nodes, so ANY docstring strip — module, or module+class+function — leaves
#     them fully intact: the third placement, and the one the real validators
#     carry most of (a section-header comment per rule block; qa has 4 such
#     comment-lines, execute 2, supervisor 2, plan-review 2). Verified a genuine
#     REGRESSION test, not a control: this fixture PASSES the shipped
#     docstring-only implementation at 8b09b54 and fails only after the comment
#     strip is added. (Case 14 is what forces that strip to be tokenize-based
#     rather than line-based — this case alone does not distinguish them.)
make_fixture "$TMP/cmd-fallback-prose-comment"
write_prose_validator "$TMP/cmd-fallback-prose-comment" scripts/validate-qa-result.py \
  'schema_version,tests_generated,tests_passed,summary' coverage_estimate comment
set_command_hooks "$TMP/cmd-fallback-prose-comment" qa-executor "$VALIDATOR_CMD"
check "field named only in a # comment fails (docstring strip alone is not enough)" 1 \
  bash "$GUARD" --root "$TMP/cmd-fallback-prose-comment"

# 13. Same, but the field survives only in a BARE STRING STATEMENT that is not
#     body[0] — the PEP-258 attribute-docstring convention, or a stray no-op
#     left by a partial deletion. The fourth placement: a body[0]-only strip
#     (which is what "strip docstrings" usually means) leaves it, and it is a
#     statement evaluated for no effect, so it is prose by construction.
#     Verified a genuine regression test: this fixture PASSES the shipped
#     8b09b54 implementation AND passes a comment-strip-only variant of the fix.
make_fixture "$TMP/cmd-fallback-prose-bare"
write_prose_validator "$TMP/cmd-fallback-prose-bare" scripts/validate-qa-result.py \
  'schema_version,tests_generated,tests_passed,summary' coverage_estimate bare
set_command_hooks "$TMP/cmd-fallback-prose-bare" qa-executor "$VALIDATOR_CMD"
check "field named only in a bare string statement fails (body[0]-only strip is not enough)" 1 \
  bash "$GUARD" --root "$TMP/cmd-fallback-prose-bare"

# 14. THE TOKENIZE-VS-REGEX FALSIFICATION, and the only case here that is
#     direction-reversed: a FULLY COMPLIANT validator must still PASS (exit 0)
#     when a `#` appears inside a string literal. Cases 10-13 all expect exit 1,
#     so a naive line-based `#` strip satisfies every one of them — over-
#     stripping only ever helps a test that wants failure. This case is what
#     distinguishes the two implementations: `COMMENT_MARKER = "#"` followed by
#     `KEY = "coverage_estimate"` on the next line, with coverage_estimate
#     appearing NOWHERE else in code. A line-based strip truncates at the `#`
#     inside the string, corrupting the source it hands to the grep; tokenize
#     removes only the real trailing comment. Verified: this fixture FAILS
#     (spurious pin-drift) against a line-based strip and passes against
#     tokenize. Models validate-launch-pad-result.py:118.
make_fixture "$TMP/cmd-fallback-hash-in-string"
write_hashstring_validator "$TMP/cmd-fallback-hash-in-string" scripts/validate-qa-result.py \
  'schema_version,tests_generated,tests_passed,summary' coverage_estimate
set_command_hooks "$TMP/cmd-fallback-hash-in-string" qa-executor "$VALIDATOR_CMD"
check "a \`#\` inside a string literal does not corrupt the source (tokenize, not a line strip)" 0 \
  bash "$GUARD" --root "$TMP/cmd-fallback-hash-in-string"

# 5. The guard passes against the REAL repo tree. Deliberately NOT a pure
#    fixture test: this is an integration invariant (the gate must hold on the
#    committed tree), so an agent edit that trips the gate fails here too —
#    a double signal with the CI step, by design.
check "real repo tree passes" 0 bash "$GUARD" --root "$REPO_ROOT"

echo "----"
echo "test-check-contract-parity: $pass/$total passed"
[ "$pass" -eq "$total" ]
