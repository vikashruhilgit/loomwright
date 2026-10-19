# =============================================================================
# =============================================================================
echo "== E. auto-merge gate (SELF-RESOLVING, red-team-hardening/03): fail CLOSED on EACH condition; ctx-owned-key refusal; all-pass MERGE fires once =="

WD="$(mktemp -d)"; WD="$(cd "$WD" && pwd -P)"; BIN="$WD/bin"; make_stub_bin "$BIN"
export GH_STUB_DIR="$WD/ghstub"; mkdir -p "$GH_STUB_DIR"

# E_ROOT — the `--root` every gate case hands the gate: a REAL git checkout
# (automate-followups/16 — condition 7 now pins `--root` to the live PR head and a
# clean tree before it trusts the rules verdict). Its committed tree tracks one file
# under each engine-owned path (.supervisor/ and $E_MEM, the agent-memory store) plus a
# .gitignore, so Section R can dirty them. Every fixture file (ctx.json, stubs, result
# artifacts) lives in $WD OUTSIDE the checkout, so the harness never dirties it.
# E_PR_HEAD is the head the stubbed `gh pr view` reports AND pass_ctx's `ready_sha`
# (cond 2 holds); it defaults to the checkout's own HEAD (E_HEAD), so every
# pre-existing case reaches cond 7 on an at-head, clean checkout exactly as before.
# E_TIP is a real child commit the checkout is NOT on (built with commit-tree, so the
# working tree is untouched) — the "PR moved on, the checkout did not" head.
# gate() runs with GIT_CEILING_DIRECTORIES=$WD so a non-checkout root under $WD can
# never be resolved to some enclosing repo of the temp dir.
E_ROOT="$WD/checkout"
E_MEM=".claude/agent-memory"   # the gate's second engine-owned exclusion (repo-relative)
mkdir -p "$E_ROOT/sub" "$E_ROOT/.supervisor/automate" "$E_ROOT/$E_MEM/loomwright:code-reviewer"
( cd "$E_ROOT" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
    && echo a > sub/a && echo run > .supervisor/automate/run.md \
    && echo mem > "$E_MEM/loomwright:code-reviewer/MEMORY.md" \
    && printf 'ignored.log\nignored-dir/\n' > .gitignore && git add -A && git commit -qm init ) >/dev/null 2>&1
E_HEAD="$(git -C "$E_ROOT" rev-parse --verify -q HEAD 2>/dev/null)" || E_HEAD=""
E_TIP="$(git -C "$E_ROOT" commit-tree "HEAD^{tree}" -p HEAD -m tip 2>/dev/null)" || E_TIP=""
E_PR_HEAD="$E_HEAD"
if [ -n "$E_HEAD" ] && [ -n "$E_TIP" ] && [ "$E_HEAD" != "$E_TIP" ] \
   && [ -z "$(git -C "$E_ROOT" status --porcelain -uall 2>/dev/null)" ]; then
  ok "E harness: a real, clean git checkout at E_HEAD plus a distinct child commit E_TIP"
else
  no "E harness: could not build the git checkout (head='$E_HEAD' tip='$E_TIP') — every gate case below is meaningless"
fi

# The gate now finds classify-risk.sh via a SIBLING lookup ($(dirname "$0")), so
# tests run against a scratch COPY of automate-helpers.sh alongside a STUBBED
# classify-risk.sh (never the real git-diffing script) — mirrors the brief_repair
# sibling-lookup precedent already used by Section G.
GWD="$WD/gharness"; mkdir -p "$GWD"
cp "$H" "$GWD/automate-helpers.sh"
cat > "$GWD/classify-risk.sh" <<'RISK'
#!/usr/bin/env bash
set -u
if [ -n "${GH_STUB_DIR:-}" ] && [ -f "$GH_STUB_DIR/risk.json" ]; then
  cat "$GH_STUB_DIR/risk.json"
else
  echo '{"high_risk": false, "reasons": [], "changed_files": 0, "changed_lines": 0, "source": "classify-risk.sh"}'
fi
RISK
chmod +x "$GWD/classify-risk.sh"
# Condition 7's sibling rules-gate-verdict.sh — likewise a STUB beside the gate copy
# (never the real checker): it logs its argv to rules-called.log (the call-log
# assertions prove cond 7 is gate-owned and self-resolved) and echoes rules.json.
# reset_live re-baselines rules.json to verdict `none` (nothing countable ⇒ the
# condition holds), so every PRE-EXISTING gate case MERGEs/PARKs exactly as before.
RULES_NONE='{"verdict":"none","selected":[],"countable":[],"advisory":[],"passed":[],"failing":[],"unresolved":[],"checks_passed":null}'
cat > "$GWD/rules-gate-verdict.sh" <<'RULES'
#!/usr/bin/env bash
set -u
if [ -n "${GH_STUB_DIR:-}" ]; then
  printf '%s\n' "$*" >> "$GH_STUB_DIR/rules-called.log"
  if [ -f "$GH_STUB_DIR/rules.json" ]; then cat "$GH_STUB_DIR/rules.json"; fi
  if [ -f "$GH_STUB_DIR/rules-exit" ]; then exit "$(cat "$GH_STUB_DIR/rules-exit")"; fi
fi
exit 0
RULES
chmod +x "$GWD/rules-gate-verdict.sh"

# Fixture artifact files the gate cross-checks/parses ITSELF (cond 1 cross-check,
# cond 5 rubric) — no longer caller-asserted ctx fields.
RHR="$WD/review-heal-result.md"
printf '## REVIEW_HEAL_RESULT\n- schema_version: 2\n- decision: READY\n- termination_reason: converged\n' > "$RHR"
RHR_ESCALATED="$WD/review-heal-result-escalated.md"
printf '## REVIEW_HEAL_RESULT\n- schema_version: 2\n- decision: ESCALATED\n- termination_reason: bound_hit\n' > "$RHR_ESCALATED"
SUP_NA="$WD/supervisor-result-na.md"
printf '## SUPERVISOR_RESULT\n- status: completed\n- heal_decision: PASS\n' > "$SUP_NA"
SUP_OK="$WD/supervisor-result-ok.md"
printf '## SUPERVISOR_RESULT\n- rubric_score: 7/7\n' > "$SUP_OK"
SUP_BAD="$WD/supervisor-result-bad.md"
printf '## SUPERVISOR_RESULT\n- rubric_score: 6/7\n' > "$SUP_BAD"

# reset_live — re-baseline every LIVE gh/api/classify-risk fixture to a fully
# passing state (each test then mutates ONE fixture to its failing shape).
reset_live() {
  printf '{"headRefOid":"%s","baseRefName":"main","statusCheckRollup":[{"name":"ci","conclusion":"SUCCESS"}]}\n' "$E_PR_HEAD" > "$GH_STUB_DIR/pr-view.json"
  rm -f "$GH_STUB_DIR/pr-view-fail"
  printf '{"reviewDecision":"APPROVED"}\n' > "$GH_STUB_DIR/pr-view-rd.json"
  rm -f "$GH_STUB_DIR/pr-view-rd-fail"
  printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}}\n' > "$GH_STUB_DIR/graphql.json"
  rm -f "$GH_STUB_DIR/graphql-fail"
  printf '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":["ci"]}}\n' > "$GH_STUB_DIR/protection.json"
  rm -f "$GH_STUB_DIR/protection-404" "$GH_STUB_DIR/protection-fail"
  printf '{"high_risk": false, "reasons": [], "changed_files": 0, "changed_lines": 0, "source": "classify-risk.sh"}\n' > "$GH_STUB_DIR/risk.json"
  rm -f "$GH_STUB_DIR/merge-fail" "$GH_STUB_DIR/merge-time-head"
  printf '%s\n' "$RULES_NONE" > "$GH_STUB_DIR/rules.json"
  rm -f "$GH_STUB_DIR/rules-exit" "$GH_STUB_DIR/rules-called.log"
}

# A fully-passing ctx (the SHRUNK shape — exactly the 6 allowed keys).
pass_ctx() {
  cat <<EOF
{
  "drain_result": "READY", "termination_reason": "converged",
  "ready_sha": "$E_PR_HEAD",
  "trust_unprotected": false,
  "review_heal_result_path": "$RHR",
  "supervisor_result_path": "$SUP_NA"
}
EOF
}

gate() {  # gate <ctx-json-string> -> sets RUN_OUT/RUN_RC, isolates a fresh merge.log; --root = ${E_GATE_ROOT:-$E_ROOT}
  rm -f "$GH_STUB_DIR/merge.log"
  printf '%s' "$1" > "$WD/ctx.json"
  RUN_OUT="$( env PATH="$BIN:$PATH" GH_STUB_DIR="$GH_STUB_DIR" HOME="$WD/nohome" GIT_CEILING_DIRECTORIES="$WD" bash "$GWD/automate-helpers.sh" gate-eval "$PR" "$WD/ctx.json" --root "${E_GATE_ROOT:-$E_ROOT}" 2>/dev/null )"; RUN_RC=$?
}
merges() { [ -f "$GH_STUB_DIR/merge.log" ] && grep -c MERGE_CALLED "$GH_STUB_DIR/merge.log" || echo 0; }

reset_live

