# --- ctx-owned-key REFUSAL (AC2, the single most important new behavior) ---
# A ctx that tries to hand the gate a pre-computed verdict for ANY now-gate-owned
# key is refused BEFORE anything else runs, regardless of the value it carries.
for K in high_risk risk_reasons head_sha base review_decision \
         unresolved_human_thread protection_enforceable checks_green rubric_satisfied; do
  gate "$(pass_ctx | jq --arg k "$K" '.[$k]=false')"
  if [ "$RUN_OUT" = "PARK: ctx_carries_gate_owned_key" ] && [ "$(merges)" -eq 0 ]; then
    ok "gate refuses gate-owned ctx key '$K' ⇒ PARK: ctx_carries_gate_owned_key, no merge"
  else
    no "gate did NOT refuse gate-owned ctx key '$K' (out='$RUN_OUT' merges=$(merges))"
  fi
done

# --- Condition 1 / 1b (unchanged ctx reads) ---
gate "$(pass_ctx | jq '.drain_result="ESCALATED"')"
if [ "$RUN_OUT" = "PARK: drain_not_ready" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: drain ESCALATED ⇒ PARK, no merge"
else
  no "gate drain wrong (out='$RUN_OUT' merges=$(merges))"
fi
# automate-followups/20: the two owned_drain_result values with no REVIEW_HEAL_RESULT behind
# them never reach the gate; if one is ever passed as drain_result, cond 1 parks it.
for DR in superseded_by_merge died; do
  gate "$(pass_ctx | jq --arg d "$DR" '.drain_result=$d')"
  if [ "$RUN_OUT" = "PARK: drain_not_ready" ] && [ "$(merges)" -eq 0 ]; then
    ok "gate fail-closed: drain_result $DR ⇒ PARK: drain_not_ready, no merge"
  else
    no "gate drain_result $DR not parked (out='$RUN_OUT' merges=$(merges))"
  fi
done
gate "$(pass_ctx | jq '.termination_reason="sub_floor_converged"')"
if [ "$RUN_OUT" = "PARK: sub_floor_not_merge_eligible" ] && [ "$(merges)" -eq 0 ]; then
  ok "AC9 fail-closed: sub_floor_converged READY ⇒ PARK, no merge"
else
  no "AC9 sub_floor_converged wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx | jq 'del(.termination_reason)')"
if [ "$RUN_OUT" = "PARK: sub_floor_not_merge_eligible" ] && [ "$(merges)" -eq 0 ]; then
  ok "AC9 fail-closed: MISSING termination_reason ⇒ PARK (no fail-open)"
else
  no "AC9 missing-termination_reason FAILED OPEN (out='$RUN_OUT' merges=$(merges))"
fi

# --- Condition 1c (ci-trust-probe-01) — `ci_untrusted` is NEVER merge-eligible.
# Two cases, both must PARK (brief AC): the well-formed shape a real drain
# actually emits (drain_result ESCALATED, since an untrusted_infra required
# check still blocks READY) AND, as a defense-in-depth mutation control, a
# deliberately-malformed drain_result READY + termination_reason ci_untrusted
# combination — proving even a hypothetically-corrupted ctx can't merge on
# this reason. ---
gate "$(pass_ctx | jq '.drain_result="ESCALATED" | .termination_reason="ci_untrusted"')"
if [ "$RUN_OUT" = "PARK: drain_not_ready" ] && [ "$(merges)" -eq 0 ]; then
  ok "ci-trust-probe-01: well-formed ci_untrusted (ESCALATED) ⇒ PARK: drain_not_ready, no merge"
else
  no "ci-trust-probe-01 well-formed ci_untrusted wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx | jq '.termination_reason="ci_untrusted"')"   # drain_result stays "READY" from pass_ctx — the mutation
if [ "$RUN_OUT" = "PARK: ci_untrusted_not_merge_eligible" ] && [ "$(merges)" -eq 0 ]; then
  ok "ci-trust-probe-01: mutation control — corrupted READY+ci_untrusted ctx still ⇒ PARK, no merge"
else
  no "ci-trust-probe-01 mutation-control ci_untrusted FAILED OPEN (out='$RUN_OUT' merges=$(merges))"
fi

# --- Condition 1 cross-check (NEW) — the drain's self-report must match the
# REVIEW_HEAL_RESULT artifact it actually wrote. ---
gate "$(pass_ctx | jq '.review_heal_result_path="/no/such/file"')"
if [ "$RUN_OUT" = "PARK: review_heal_result_unreadable" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: unreadable review_heal_result_path ⇒ PARK, no merge"
else
  no "gate review_heal_result unreadable wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx | jq --arg p "$RHR_ESCALATED" '.review_heal_result_path=$p')"
if [ "$RUN_OUT" = "PARK: drain_result_mismatch" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: ctx drain_result disagrees with the REVIEW_HEAL_RESULT artifact ⇒ PARK, no merge (the drain's self-report is corroborated, never trusted blind)"
else
  no "gate drain_result_mismatch wrong (out='$RUN_OUT' merges=$(merges))"
fi

# --- Condition 2 — self-resolved via live `gh pr view` (headRefOid/baseRefName) ---
J_MOVE_SHA='{"headRefOid":"def456","baseRefName":"main","statusCheckRollup":[{"name":"ci","conclusion":"SUCCESS"}]}'
printf '%s\n' "$J_MOVE_SHA" > "$GH_STUB_DIR/pr-view.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: head_sha_moved" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: live headRefOid != ctx ready_sha ⇒ PARK: head_sha_moved, no merge (never caller-asserted)"
else
  no "gate moved-sha wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live

printf '{"headRefOid":"%s","baseRefName":"develop","statusCheckRollup":[{"name":"ci","conclusion":"SUCCESS"}]}\n' "$E_PR_HEAD" > "$GH_STUB_DIR/pr-view.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: base_not_main" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: live baseRefName != main ⇒ PARK: base_not_main, no merge"
else
  no "gate base-not-main wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live

touch "$GH_STUB_DIR/pr-view-fail"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: head_sha_moved" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: gh pr view (headRefOid read) fails entirely ⇒ PARK: head_sha_moved, no merge"
else
  no "gate pr-view-fail wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live

# --- Condition 3 — self-resolved via a SEPARATE `gh pr view --json reviewDecision` ---
printf '{"reviewDecision":"CHANGES_REQUESTED"}\n' > "$GH_STUB_DIR/pr-view-rd.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: review_decision_blocking" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: live reviewDecision CHANGES_REQUESTED ⇒ PARK, no merge"
else
  no "gate changes-requested wrong (out='$RUN_OUT' merges=$(merges))"
fi
printf '{"reviewDecision":"REVIEW_REQUIRED"}\n' > "$GH_STUB_DIR/pr-view-rd.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: review_decision_blocking" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: live reviewDecision REVIEW_REQUIRED ⇒ PARK, no merge"
else
  no "gate review-required wrong (out='$RUN_OUT' merges=$(merges))"
fi
touch "$GH_STUB_DIR/pr-view-rd-fail"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: review_decision_unreadable" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: gh pr view (reviewDecision read) fails ⇒ PARK: review_decision_unreadable (independently reachable — not masked by cond 2), no merge"
else
  no "gate review-decision-unreadable wrong (out='$RUN_OUT' merges=$(merges))"
fi
rm -f "$GH_STUB_DIR/pr-view-rd-fail"

# "none" reviewDecision (reviews-not-required — a successfully-read null) defers
# to cond 4 rather than parking here (the checks-only / --trust-unprotected
# reachability fix).
printf '{"reviewDecision":null}\n' > "$GH_STUB_DIR/pr-view-rd.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: null (successfully-read) reviewDecision + enforceable checks-only protection ⇒ MERGE (cond 4 reachable)"
else
  no "gate none+protected wrong (out='$RUN_OUT' merges=$(merges))"
fi
printf '{"required_pull_request_reviews":{"required_approving_review_count":0},"required_status_checks":{"contexts":[]}}\n' > "$GH_STUB_DIR/protection.json"
gate "$(pass_ctx | jq '.trust_unprotected=true')"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: null reviewDecision + unprotected + --trust-unprotected ⇒ MERGE (escape hatch reachable)"
else
  no "gate none+trust wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: unprotected_branch" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: null reviewDecision + unprotected + no trust ⇒ PARK"
else
  no "gate none+unprotected-no-trust wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live

# unresolved human/untrusted-actor thread (GraphQL, self-computed).
printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[{"isResolved":false,"comments":{"nodes":[{"author":{"login":"someone","__typename":"User"}}]}}]}}}}}\n' > "$GH_STUB_DIR/graphql.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: unresolved_human_thread" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: unresolved thread whose actor is NOT in the trusted-actor set ⇒ PARK, no merge"
else
  no "gate human-thread wrong (out='$RUN_OUT' merges=$(merges))"
fi
# ...but an exact-listed trusted actor's unresolved thread does NOT block.
mkdir -p "$WD/trustedhome/.claude/loomwright"
printf '["someone"]\n' > "$WD/trustedhome/.claude/loomwright/trusted-actors.json"
rm -f "$GH_STUB_DIR/merge.log"
printf '%s' "$(pass_ctx)" > "$WD/ctx.json"
RUN_OUT="$( env PATH="$BIN:$PATH" GH_STUB_DIR="$GH_STUB_DIR" HOME="$WD/trustedhome" bash "$GWD/automate-helpers.sh" gate-eval "$PR" "$WD/ctx.json" --root "${E_GATE_ROOT:-$E_ROOT}" 2>/dev/null )"; RUN_RC=$?
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: unresolved thread whose actor IS exact-listed in the trusted-actor set ⇒ NOT blocking (MERGE)"
else
  no "gate trusted-actor wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live
# hasNextPage truncation (>100 threads) fails CLOSED even with zero visible nodes.
printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":true},"nodes":[]}}}}}\n' > "$GH_STUB_DIR/graphql.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: unresolved_human_thread" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: reviewThreads hasNextPage=true (truncated >100) ⇒ PARK, no merge"
else
  no "gate truncated-threads wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live
touch "$GH_STUB_DIR/graphql-fail"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: unresolved_human_thread" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: GraphQL review-threads read errors ⇒ PARK, no merge"
else
  no "gate graphql-fail wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live

# --- Condition 4 — self-resolved via `gh api repos/.../branches/main/protection` ---
printf '{"required_pull_request_reviews":{"required_approving_review_count":0},"required_status_checks":{"contexts":[]}}\n' > "$GH_STUB_DIR/protection.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: unprotected_branch" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: toothless (no reviews, no checks) protection ⇒ PARK: unprotected_branch, no merge"
else
  no "gate unprotected wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx | jq '.trust_unprotected=true')"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: --trust-unprotected overrides only the protection condition (MERGE)"
else
  no "trust-unprotected override wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live
touch "$GH_STUB_DIR/protection-404"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: unprotected_branch" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: branches/main/protection 404 ⇒ unprotected (false), no trust ⇒ PARK, no merge"
else
  no "gate protection-404 wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live
touch "$GH_STUB_DIR/protection-fail"
gate "$(pass_ctx | jq '.trust_unprotected=true')"
if [ "$RUN_OUT" = "PARK: protection_unreadable" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: a NON-404 protection read error ⇒ PARK: protection_unreadable, NEVER treated as either protected or unprotected (not even with --trust-unprotected)"
else
  no "gate protection-unreadable wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live

# --- Condition 5 — checks (self-resolved from the SAME protection payload's
# required-context list, cross-referenced against statusCheckRollup) + rubric
# (now a FILE READ, never caller-asserted). ---
printf '{"headRefOid":"%s","baseRefName":"main","statusCheckRollup":[{"name":"ci","conclusion":"FAILURE"}]}\n' "$E_PR_HEAD" > "$GH_STUB_DIR/pr-view.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: checks_not_green" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: required check 'ci' not green ⇒ PARK, no merge"
else
  no "gate checks-not-green wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live
gate "$(pass_ctx | jq --arg p "$SUP_OK" '.supervisor_result_path=$p')"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: rubric_score N==M (parsed from the file itself) ⇒ MERGE"
else
  no "gate rubric-true wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx | jq --arg p "$SUP_BAD" '.supervisor_result_path=$p')"
if [ "$RUN_OUT" = "PARK: rubric_unsatisfied" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: rubric_score 6/7 (parsed from the file) ⇒ PARK: rubric_unsatisfied, no merge"
else
  no "gate rubric-false wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx | jq '.supervisor_result_path="/no/such/supervisor-result.md"')"
if [ "$RUN_OUT" = "PARK: supervisor_result_unreadable" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: unreadable supervisor_result_path ⇒ PARK: supervisor_result_unreadable, no merge"
else
  no "gate supervisor-result-unreadable wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: no rubric_score line in the file ⇒ 'na' (not a blocker) ⇒ MERGE"
else
  no "gate rubric-na wrong (out='$RUN_OUT' merges=$(merges))"
fi

# --- malformed ctx.json ---
gate 'this is not json {'
if [ "$RUN_OUT" = "PARK: ctx_unreadable" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: malformed ctx.json ⇒ PARK: ctx_unreadable, no merge"
else
  no "gate ctx-unreadable wrong (out='$RUN_OUT' merges=$(merges))"
fi

# --- Condition 6 — the gate ITSELF invokes classify-risk.sh; NO ctx input feeds
# this condition any more (that is exactly what the ctx-owned-key loop above
# already proved is refused). ---
printf '{"high_risk": true, "reasons": ["path: src/auth/x.ts matched *auth*","content: 2 changed line(s) matched *token*","size: changed_lines 512 > 400","path: skills/x/SKILL.md matched skills/"], "source":"classify-risk.sh"}\n' > "$GH_STUB_DIR/risk.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: high_risk_diff (path: src/auth/x.ts matched *auth*; content: 2 changed line(s) matched *token*; size: changed_lines 512 > 400)" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: gate-computed high_risk=true ⇒ PARK: high_risk_diff (first 3 reasons quoted), no merge"
else
  no "gate high-risk-true wrong (out='$RUN_OUT' merges=$(merges))"
fi
printf '{"high_risk": null, "reasons": ["unclassifiable: bad_ref"], "source":"classify-risk.sh"}\n' > "$GH_STUB_DIR/risk.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: high_risk_diff (unclassifiable: bad_ref)" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: gate-computed high_risk=null (unclassifiable) ⇒ PARK, no merge"
else
  no "gate high-risk-null wrong (out='$RUN_OUT' merges=$(merges))"
fi
printf '{"high_risk": "false", "reasons": [], "source":"classify-risk.sh"}\n' > "$GH_STUB_DIR/risk.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: high_risk_diff (no risk_reasons recorded)" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: JSON STRING \"false\" high_risk ⇒ PARK (boolean false only — no type erasure), no merge"
else
  no "gate string-false-high-risk FAILED OPEN (out='$RUN_OUT' merges=$(merges))"
fi
# --trust-unprotected is cond 4 ONLY — it must NOT override cond 6.
printf '{"required_pull_request_reviews":{"required_approving_review_count":0},"required_status_checks":{"contexts":[]}}\n' > "$GH_STUB_DIR/protection.json"
printf '{"high_risk": true, "reasons": ["path: billing/x.ts matched billing/**"], "source":"classify-risk.sh"}\n' > "$GH_STUB_DIR/risk.json"
gate "$(pass_ctx | jq '.trust_unprotected=true')"
if [ "$RUN_OUT" = "PARK: high_risk_diff (path: billing/x.ts matched billing/**)" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: trust_unprotected=true + gate-computed high_risk=true ⇒ PARK (the override is scoped to cond 4), no merge"
else
  no "gate trust-unprotected-vs-high-risk wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live

