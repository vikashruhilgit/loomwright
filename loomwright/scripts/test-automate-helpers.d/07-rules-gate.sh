# =============================================================================
echo "== R. gate-eval condition 7 — rules gate (self-resolved via sibling rules-gate-verdict.sh; named PARK reasons; refused ctx keys; gated mutants) =="
# Section letter "R" (rules): "F" is already this file's learning-emit section.
# Reuses Section E's harness ($GWD gate copy + stub rules-gate-verdict.sh, gate(),
# pass_ctx, merges, reset_live). Every case runs on an otherwise ALL-GREEN PR
# (conditions 1–6 hold), so the ONLY variable is the verdict the stub returns.

# rules_fixture <verdict> <countable-json> <failing-json> <unresolved-json> [advisory-json]
# — write a well-formed verdict object (every field, the helper's own contract shape).
rules_fixture() {
  jq -nc --arg v "$1" --argjson c "$2" --argjson f "$3" --argjson u "$4" --argjson a "${5:-[]}" \
    '{verdict:$v, selected:(($c + ($a|map(.id))) | unique), countable:$c, advisory:$a,
      passed:[], failing:$f, unresolved:$u, checks_passed:null}' > "$GH_STUB_DIR/rules.json"
}
rules_called() { [ -f "$GH_STUB_DIR/rules-called.log" ]; }
# R_EXP_ROOT — the argv the gate must hand its sibling: `--root <the checkout gate() passed>`.
R_EXP_ROOT="--root $E_ROOT"

# R1 (AC1 gate half) — a stamped, countable, FAILING must-check ⇒ PARK: rules_check_failed (<id>).
reset_live
rules_fixture fail '["r-lint"]' '["r-lint"]' '[]'
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: rules_check_failed (r-lint)" ] && [ "$(merges)" -eq 0 ] \
   && rules_called && [ "$(cat "$GH_STUB_DIR/rules-called.log")" = "$R_EXP_ROOT" ]; then
  ok "R1 cond 7: verdict fail ⇒ PARK: rules_check_failed (r-lint), 0 merges, and the gate ITSELF called its sibling with '$R_EXP_ROOT'"
else
  no "R1 cond-7 fail wrong (out='$RUN_OUT' merges=$(merges) argv='$(cat "$GH_STUB_DIR/rules-called.log" 2>/dev/null)')"
fi

# R1b — ids: at most 3, "; "-joined, COUNTABLE only (a failing ADVISORY id never names a blocker).
reset_live
rules_fixture fail '["a","b","c","d"]' '["adv-x","a","b","c","d"]' '[]' '[{"id":"adv-x","reason":"binds_undeclared"}]'
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: rules_check_failed (a; b; c)" ] && [ "$(merges)" -eq 0 ]; then
  ok "R1b cond 7: fail reason names up to 3 COUNTABLE failing ids joined by '; ' (advisory adv-x excluded)"
else
  no "R1b cond-7 id list wrong (out='$RUN_OUT')"
fi

# R2 (AC2 gate half) — verdict ok ⇒ the condition holds ⇒ MERGE (1 merge).
reset_live
rules_fixture ok '["r-lint"]' '[]' '[]'
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ] && rules_called; then
  ok "R2 cond 7: verdict ok ⇒ MERGE (exactly 1 merge; the helper WAS consulted)"
else
  no "R2 cond-7 ok wrong (out='$RUN_OUT' merges=$(merges))"
fi

# R3 (AC10 gate half) — unresolved (a forged / truncated replay) ⇒ PARK: rules_check_unresolved (<ids>).
reset_live
rules_fixture unresolved '["r-lint","r-fmt"]' '[]' '["r-lint","r-fmt"]'
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: rules_check_unresolved (r-lint; r-fmt)" ] && [ "$(merges)" -eq 0 ]; then
  ok "R3 cond 7: verdict unresolved ⇒ PARK: rules_check_unresolved (r-lint; r-fmt), 0 merges"
else
  no "R3 cond-7 unresolved wrong (out='$RUN_OUT' merges=$(merges))"
fi

# R4 (AC3 / AC7 gate legs, D3 middle form) — unstamped WITH countable must-checks ⇒ PARK;
# the helper answers `none` when nothing is countable (all advisory, even one FAILING) ⇒ MERGE.
reset_live
rules_fixture unstamped '["r-lint","r-fmt"]' '[]' '[]'
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: rules_unstamped (2 countable must-check(s) never confirmed on this machine)" ] && [ "$(merges)" -eq 0 ]; then
  ok "R4 cond 7: unstamped with 2 countable ⇒ PARK: rules_unstamped (2 countable must-check(s) never confirmed on this machine)"
else
  no "R4 cond-7 unstamped wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live
rules_fixture none '[]' '["r-lint"]' '[]' '[{"id":"r-lint","reason":"unbound:scripts/lint.sh"}]'
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ] && rules_called; then
  ok "R4b cond 7: verdict none (only advisory must-checks — here an unbound one that FAILS) ⇒ MERGE: nothing uncounted gates"
else
  no "R4b cond-7 none-with-advisory wrong (out='$RUN_OUT' merges=$(merges))"
fi
# R4c — unstamped by COUNTABLE-SET DRIFT with ZERO live countable ids (the last stamped,
# failing countable rule demoted away — test-rules-gate-verdict.sh (cs 4)) ⇒ PARK with the
# drift text, never the self-contradictory "0 countable must-check(s) never confirmed".
reset_live
rules_fixture unstamped '[]' '[]' '[]'
jq -c '. + {unstamped_reason: "countable_set_drift"}' "$GH_STUB_DIR/rules.json" > "$GH_STUB_DIR/rules.tmp" && mv "$GH_STUB_DIR/rules.tmp" "$GH_STUB_DIR/rules.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: rules_unstamped (countable rule set changed since the last /rules check --confirm on this machine)" ] && [ "$(merges)" -eq 0 ]; then
  ok "R4c cond 7: unstamped by countable-set drift with 0 live countable ⇒ PARK: rules_unstamped (countable rule set changed …), 0 merges"
else
  no "R4c cond-7 drift unstamped wrong (out='$RUN_OUT' merges=$(merges))"
fi
# R4d — unstamped by a LEGACY stamp ⇒ its own text; still 0 merges.
reset_live
rules_fixture unstamped '["r-lint"]' '[]' '[]'
jq -c '. + {unstamped_reason: "legacy_stamp"}' "$GH_STUB_DIR/rules.json" > "$GH_STUB_DIR/rules.tmp" && mv "$GH_STUB_DIR/rules.tmp" "$GH_STUB_DIR/rules.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: rules_unstamped (the stamp predates the recorded countable rule set; re-run /rules check --confirm on this machine)" ] && [ "$(merges)" -eq 0 ]; then
  ok "R4d cond 7: unstamped by a legacy stamp ⇒ PARK: rules_unstamped (the stamp predates …), 0 merges"
else
  no "R4d cond-7 legacy unstamped wrong (out='$RUN_OUT' merges=$(merges))"
fi
# R4e — an UNKNOWN / non-string unstamped_reason is message text only: it still PARKs
# (never-confirmed text), because the park is keyed on the verdict.
reset_live
rules_fixture unstamped '["r-lint"]' '[]' '[]'
jq -c '. + {unstamped_reason: {"x":1}}' "$GH_STUB_DIR/rules.json" > "$GH_STUB_DIR/rules.tmp" && mv "$GH_STUB_DIR/rules.tmp" "$GH_STUB_DIR/rules.json"
gate "$(pass_ctx)"
R4E_A="$RUN_OUT"; R4E_MA="$(merges)"
reset_live
rules_fixture unstamped '["r-lint"]' '[]' '[]'
jq -c '. + {unstamped_reason: "something_new"}' "$GH_STUB_DIR/rules.json" > "$GH_STUB_DIR/rules.tmp" && mv "$GH_STUB_DIR/rules.tmp" "$GH_STUB_DIR/rules.json"
gate "$(pass_ctx)"
R4E_EXP="PARK: rules_unstamped (1 countable must-check(s) never confirmed on this machine)"
if [ "$R4E_A" = "$R4E_EXP" ] && [ "$R4E_MA" -eq 0 ] && [ "$RUN_OUT" = "$R4E_EXP" ] && [ "$(merges)" -eq 0 ]; then
  ok "R4e cond 7: a non-string or unknown unstamped_reason still PARKs rules_unstamped (never-confirmed text), 0 merges"
else
  no "R4e cond-7 unknown reason wrong (a='$R4E_A'/$R4E_MA b='$RUN_OUT'/$(merges))"
fi

# R5 (AC4 gate leg) — cmd_disabled ⇒ PARK: rules_cmd_disabled (the gate cannot verify).
reset_live
rules_fixture cmd_disabled '["r-lint"]' '[]' '[]'
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: rules_cmd_disabled" ] && [ "$(merges)" -eq 0 ]; then
  ok "R5 cond 7: verdict cmd_disabled ⇒ PARK: rules_cmd_disabled, 0 merges"
else
  no "R5 cond-7 cmd_disabled wrong (out='$RUN_OUT' merges=$(merges))"
fi

# R6 — every unreadable shape fails CLOSED on ONE named reason: rules_gate_unreadable.
r6_case() {  # r6_case <label> <rules.json body or __NONE__> [exit-code]
  reset_live
  if [ "$2" = "__NONE__" ]; then rm -f "$GH_STUB_DIR/rules.json"; else printf '%s\n' "$2" > "$GH_STUB_DIR/rules.json"; fi
  [ -n "${3:-}" ] && printf '%s' "$3" > "$GH_STUB_DIR/rules-exit"
  gate "$(pass_ctx)"
  if [ "$RUN_OUT" = "PARK: rules_gate_unreadable" ] && [ "$(merges)" -eq 0 ]; then
    ok "R6 cond 7 fail-closed: $1 ⇒ PARK: rules_gate_unreadable, 0 merges"
  else
    no "R6 cond-7 $1 FAILED OPEN or misnamed (out='$RUN_OUT' merges=$(merges))"
  fi
}
r6_case "verdict unreadable"            '{"verdict":"unreadable","selected":[],"countable":[],"advisory":[],"passed":[],"failing":[],"unresolved":[],"checks_passed":null}'
r6_case "non-JSON helper output"        'Checks passed: 1/1'
r6_case "empty helper output"           '__NONE__'
r6_case "JSON that is not an object"    '["ok"]'
r6_case "missing .verdict"              '{"selected":[],"countable":[]}'
r6_case "non-string .verdict (true)"    '{"verdict":true}'
r6_case "null .verdict"                 '{"verdict":null}'
r6_case "unrecognised verdict string"   '{"verdict":"OK"}'
r6_case "non-zero helper exit with an ok body" '{"verdict":"ok","selected":[],"countable":[],"advisory":[],"passed":[],"failing":[],"unresolved":[],"checks_passed":null}' 3
# Helper ABSENT beside the gate — moved away, then restored.
reset_live
mv "$GWD/rules-gate-verdict.sh" "$WD/rules-gate-verdict.sh.away"
gate "$(pass_ctx)"
mv "$WD/rules-gate-verdict.sh.away" "$GWD/rules-gate-verdict.sh"
if [ "$RUN_OUT" = "PARK: rules_gate_unreadable" ] && [ "$(merges)" -eq 0 ]; then
  ok "R6 cond 7 fail-closed: sibling rules-gate-verdict.sh ABSENT ⇒ PARK: rules_gate_unreadable, 0 merges"
else
  no "R6 cond-7 helper-absent FAILED OPEN (out='$RUN_OUT' merges=$(merges))"
fi

# R7 (AC5) — the three new gate-owned ctx keys are REFUSED before anything runs; the
# rules helper is NEVER called (call-log) — even a value asserting a pass cannot help.
for K in rules_gate rules_ok rules_check; do
  for V in 'true' '"ok"' 'false'; do
    reset_live
    rules_fixture ok '["r-lint"]' '[]' '[]'
    gate "$(pass_ctx | jq --arg k "$K" --argjson v "$V" '.[$k]=$v')"
    if [ "$RUN_OUT" = "PARK: ctx_carries_gate_owned_key" ] && [ "$(merges)" -eq 0 ] && ! rules_called; then
      ok "R7 refuses ctx key '$K'=$V ⇒ PARK: ctx_carries_gate_owned_key, 0 merges, helper never called"
    else
      no "R7 ctx key '$K'=$V NOT refused (out='$RUN_OUT' merges=$(merges) called=$(rules_called && echo yes || echo no))"
    fi
  done
done

# R8 — precedence: cond 7 is evaluated AFTER cond 6 (a high-risk diff parks on its own
# reason and the rules helper is never even called).
reset_live
printf '{"high_risk": true, "reasons": ["path: billing/x.ts matched billing/**"], "source":"classify-risk.sh"}\n' > "$GH_STUB_DIR/risk.json"
rules_fixture fail '["r-lint"]' '["r-lint"]' '[]'
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: high_risk_diff (path: billing/x.ts matched billing/**)" ] && [ "$(merges)" -eq 0 ] && ! rules_called; then
  ok "R8 precedence: cond 6 PARK wins over a failing cond 7, and cond 7's helper is not called (evaluated after cond 6)"
else
  no "R8 cond-6/7 precedence wrong (out='$RUN_OUT' called=$(rules_called && echo yes || echo no))"
fi

# R9 (AC9(b)) — GATED mutation controls. Each mutant is a sed COPY of the gate, trusted only
# if non-empty, differs from the original, passes `bash -n`, and carries the injected marker.
# (i) the cond-7 PARK test disabled (the condition deleted) ⇒ the AC1 failing case prints MERGE.
# (ii) ONLY the helper invocation commented out ⇒ the AC1 failing case does NOT merge — it
#      fails CLOSED on rules_gate_unreadable (removing the call can never open the gate) —
#      and the instrumented call log proves the helper was never called.
# Positive control: the UN-mutated gate copy, same stubs, calls the helper on the all-green
# path (log proves it, MERGE) and PARKs the failing case on rules_check_failed.
r9_run() {  # r9_run <dir> — gate-eval from <dir>'s copy; sets R9_OUT
  rm -f "$GH_STUB_DIR/merge.log" "$GH_STUB_DIR/rules-called.log"
  printf '%s' "$(pass_ctx)" > "$WD/ctx.json"
  R9_OUT="$( env PATH="$BIN:$PATH" GH_STUB_DIR="$GH_STUB_DIR" HOME="$WD/nohome" bash "$1/automate-helpers.sh" gate-eval "$PR" "$WD/ctx.json" --root "${E_GATE_ROOT:-$E_ROOT}" 2>/dev/null )"
}
r9_dir() {  # r9_dir <sed-expr> <marker-regex> — prints a gated mutant dir, or nothing
  local d; d="$(mktemp -d)"
  sed "$1" "$GWD/automate-helpers.sh" > "$d/automate-helpers.sh"
  if [ -s "$d/automate-helpers.sh" ] && ! cmp -s "$GWD/automate-helpers.sh" "$d/automate-helpers.sh" \
     && bash -n "$d/automate-helpers.sh" 2>/dev/null && grep -q "$2" "$d/automate-helpers.sh"; then
    cp "$GWD/classify-risk.sh" "$GWD/resolve-base-branch.sh" "$GWD/rules-gate-verdict.sh" "$d/"
    printf '%s' "$d"
  else
    rm -rf "$d"
  fi
}
reset_live
M_PARK="$(r9_dir 's/^\(  if \[ "\$rules_ok" != "true" \]; then\)$/  if false \&\& [ "$rules_ok" != "true" ]; then/' 'if false && \[ "\$rules_ok" != "true" \]; then')"
M_CALL="$(r9_dir 's/^\(  if \[ -r "\$rules_bin" \]; then\)$/  if false \&\& [ -r "$rules_bin" ]; then/' 'if false && \[ -r "\$rules_bin" \]; then')"
if [ -n "$M_PARK" ] && [ -n "$M_CALL" ]; then
  rules_fixture fail '["r-lint"]' '["r-lint"]' '[]'
  r9_run "$M_PARK"
  if [ "$R9_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
    ok "R9 (mutant i) cond-7 PARK test deleted ⇒ the AC1 failing-check case prints MERGE — condition 7 is what parks it"
  else
    no "R9 mutant (i) did NOT flip the failing case to MERGE (out='$R9_OUT' merges=$(merges)) — the cond-7 PARK is not load-bearing"
  fi
  r9_run "$M_CALL"
  if [ "$R9_OUT" = "PARK: rules_gate_unreadable" ] && [ "$(merges)" -eq 0 ] && [ ! -f "$GH_STUB_DIR/rules-called.log" ]; then
    ok "R9 (mutant ii) invocation commented out ⇒ helper never called (log absent) and the failing case parks rules_gate_unreadable, not rules_check_failed — fail CLOSED, never MERGE"
  else
    no "R9 mutant (ii) wrong (out='$R9_OUT' merges=$(merges) called=$([ -f "$GH_STUB_DIR/rules-called.log" ] && echo yes || echo no))"
  fi
  # Positive control on the UN-mutated copy.
  CTRL="$(mktemp -d)"; cp "$GWD/automate-helpers.sh" "$GWD/classify-risk.sh" "$GWD/resolve-base-branch.sh" "$GWD/rules-gate-verdict.sh" "$CTRL/"
  r9_run "$CTRL"
  R9_FAIL_OUT="$R9_OUT"; R9_FAIL_MERGES="$(merges)"
  rules_fixture ok '["r-lint"]' '[]' '[]'
  r9_run "$CTRL"
  if [ "$R9_FAIL_OUT" = "PARK: rules_check_failed (r-lint)" ] && [ "$R9_FAIL_MERGES" -eq 0 ] \
     && [ "$R9_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ] && [ -f "$GH_STUB_DIR/rules-called.log" ]; then
    ok "R9 (positive control) the UN-mutated gate PARKs the failing case on rules_check_failed and, on the all-green path, DOES call the helper (log) and MERGE — the mutants' outcomes are caused by their one-line edits"
  else
    no "R9 positive control failed (fail-case='$R9_FAIL_OUT'/$R9_FAIL_MERGES green='$R9_OUT'/$(merges)) — cannot trust the mutation results without it"
  fi
  rm -rf "$CTRL"
else
  no "R9 cond-7 mutation controls not gated (a mutant was empty, identical to the original, failed bash -n, or lacked its injected marker)"
fi
rm -rf "${M_PARK:-/nonexistent-r9}" "${M_CALL:-/nonexistent-r9}"

# R10 — END-TO-END against the REAL siblings (rules-gate-verdict.sh + rules-check.sh +
# rules-replay-lib.sh beside the gate copy; only gh and classify-risk.sh stubbed): a real
# fixture store stamped by a genuine `rules-check.sh --confirm` in a sandboxed HOME.
# A countable (binds: []) FAILING must-check ⇒ PARK: rules_check_failed (<id>); the same
# store with the check PASSING ⇒ MERGE. Proves the stub's JSON shape is the real one.
TAB_CHAR="$(printf '\t')"
reset_live
rm -f "$GH_STUB_DIR/rules.json"
IWD="$(mktemp -d)"; IWD="$(cd "$IWD" && pwd -P)"
cp "$GWD/automate-helpers.sh" "$GWD/classify-risk.sh" "$GWD/resolve-base-branch.sh" "$IWD/"
cp "$HERE/rules-gate-verdict.sh" "$HERE/rules-check.sh" "$HERE/rules-replay-lib.sh" "$IWD/"
r10_store() {  # r10_store <name> <check> — a committed temp repo + stamped store; prints "<repo>\t<home>"
  local r="$IWD/$1" h="$IWD/home-$1"
  mkdir -p "$r/.agent/rules" "$h"
  jq -cn --arg id "e2e-$1" --arg c "$2" \
    '[{id:$id, category:"test", statement:("s " + $id), enforcement:"must", check:$c, binds:[], provenance:{source:"test"}}]' \
    > "$r/.agent/rules/r.json"
  # The store is COMMITTED with `f` (automate-followups/16): an untracked store would leave the
  # checkout dirty and park every leg rules_gate_dirty_tree before the real helper ever ran.
  # `--confirm` runs AFTER the commit, on the committed bytes (the stamp lives in HOME).
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
      && echo init > f && git add f .agent && git commit -qm init \
      && git update-ref refs/remotes/origin/main HEAD \
      && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main ) >/dev/null 2>&1   # cond 6 resolves its base on disk
  ( cd "$r" && env -u RULES_CHECK_NO_CMD -u RULES_CHECK_STAMP_FILE HOME="$h" bash "$IWD/rules-check.sh" --confirm </dev/null >/dev/null 2>&1 )
  printf '%s\t%s' "$r" "$h"
}
r10_gate() {  # r10_gate <repo> <home> [<pr-head>] — sets R10_OUT; the stubbed live head (and ctx ready_sha)
  # is <pr-head>, defaulting to <repo>'s OWN real HEAD so the cond-7 pin sees an at-head checkout.
  local ph; ph="${3:-$(git -C "$1" rev-parse HEAD 2>/dev/null)}"
  rm -f "$GH_STUB_DIR/merge.log"
  printf '{"headRefOid":"%s","baseRefName":"main","statusCheckRollup":[{"name":"ci","conclusion":"SUCCESS"}]}\n' "$ph" > "$GH_STUB_DIR/pr-view.json"
  printf '%s' "$(pass_ctx | jq --arg s "$ph" '.ready_sha=$s')" > "$WD/ctx.json"
  R10_OUT="$( cd "$1" && env -u RULES_CHECK_NO_CMD -u RULES_CHECK_STAMP_FILE PATH="$BIN:$PATH" GH_STUB_DIR="$GH_STUB_DIR" HOME="$2" bash "$IWD/automate-helpers.sh" gate-eval "$PR" "$WD/ctx.json" --root "$1" 2>/dev/null )"
}
IFS="$TAB_CHAR" read -r R10_REPO R10_HOME <<R10A
$(r10_store fails false)
R10A
r10_gate "$R10_REPO" "$R10_HOME"
if [ "$R10_OUT" = "PARK: rules_check_failed (e2e-fails)" ] && [ "$(merges)" -eq 0 ]; then
  ok "R10 end-to-end (real siblings): stamped countable FAILING must-check ⇒ PARK: rules_check_failed (e2e-fails), 0 merges"
else
  no "R10 end-to-end failing case wrong (out='$R10_OUT' merges=$(merges))"
fi
IFS="$TAB_CHAR" read -r R10_REPO R10_HOME <<R10B
$(r10_store passes true)
R10B
r10_gate "$R10_REPO" "$R10_HOME"
if [ "$R10_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "R10 end-to-end (real siblings): the same store shape with the check PASSING ⇒ MERGE (1 merge)"
else
  no "R10 end-to-end passing case wrong (out='$R10_OUT' merges=$(merges))"
fi
# R10 stale-HEAD leg (automate-followups/16) — the SAME passing store, real siblings, but the live
# PR head is a real child commit the checkout is NOT on ⇒ the pin parks before the real helper
# runs, even though that helper would have answered `ok` (the leg just above MERGEd on it).
R10_TIP="$(git -C "$R10_REPO" commit-tree "HEAD^{tree}" -p HEAD -m tip 2>/dev/null)" || R10_TIP=""
r10_gate "$R10_REPO" "$R10_HOME" "$R10_TIP"
if [ -n "$R10_TIP" ] && [ "$R10_OUT" = "PARK: rules_gate_head_mismatch" ] && [ "$(merges)" -eq 0 ]; then
  ok "R10 end-to-end (real siblings): the passing store, but the live PR head is a commit the checkout is not on ⇒ PARK: rules_gate_head_mismatch, 0 merges"
else
  no "R10 end-to-end stale-HEAD leg wrong (tip='$R10_TIP' out='$R10_OUT' merges=$(merges))"
fi
rm -rf "$IWD"
reset_live

# R11 (automate-followups/16) — cond 7's CHECKOUT PIN, evaluated BEFORE the rules helper:
# `--root` must be AT the live head cond 2 confirmed (else rules_gate_head_mismatch) and clean
# outside .supervisor/ and $E_MEM (else rules_gate_dirty_tree). Every PARK leg
# runs with the stub verdict `ok`, so the ONLY thing standing between it and a MERGE is the pin;
# every leg also asserts the helper was NOT called (the pin runs first). Each leg restores the
# checkout and r11_restored proves it, so no leg leaks dirt into the next.
r11_restored() {  # r11_restored <label> — the shared checkout is back at E_HEAD and clean
  if [ "$(git -C "$E_ROOT" rev-parse HEAD 2>/dev/null)" != "$E_HEAD" ] \
     || [ -n "$(git -C "$E_ROOT" status --porcelain -uall --ignored 2>/dev/null)" ]; then
    no "R11 $1: the shared checkout was NOT restored (head/dirt leaked) — later cases are untrustworthy"
  fi
}
r11_park() {  # r11_park <label> <expected-reason> — assert PARK <reason>, 0 merges, helper never called
  if [ "$RUN_OUT" = "PARK: $2" ] && [ "$(merges)" -eq 0 ] && ! rules_called; then
    ok "R11 $1 ⇒ PARK: $2, 0 merges, rules helper never called"
  else
    no "R11 $1 wrong (out='$RUN_OUT' merges=$(merges) called=$(rules_called && echo yes || echo no))"
  fi
}
r11_decides() {  # r11_decides <label> — the verdict still decides: fail ⇒ rules_check_failed, ok ⇒ MERGE
  reset_live; rules_fixture fail '["r-lint"]' '["r-lint"]' '[]'; gate "$(pass_ctx)"
  local fo="$RUN_OUT" fm; fm="$(merges)"
  local fargv; fargv="$(cat "$GH_STUB_DIR/rules-called.log" 2>/dev/null)"
  reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'; gate "$(pass_ctx)"
  if [ "$fo" = "PARK: rules_check_failed (r-lint)" ] && [ "$fm" -eq 0 ] \
     && [ "$fargv" = "--root ${E_GATE_ROOT:-$E_ROOT}" ] \
     && [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ] && rules_called; then
    ok "R11 $1 ⇒ pin passes and the verdict decides (fail ⇒ rules_check_failed, ok ⇒ MERGE; helper called with --root unchanged)"
  else
    no "R11 $1 wrong (fail-case='$fo'/$fm argv='$fargv' ok-case='$RUN_OUT'/$(merges))"
  fi
}

# R11a (AC1) — stale HEAD: the live PR head (and ready_sha, so cond 2 holds) is E_TIP, a real
# commit the checkout is not on.
E_PR_HEAD="$E_TIP"; reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
gate "$(pass_ctx)"
r11_park "stale HEAD (checkout at E_HEAD, live PR head E_TIP)" rules_gate_head_mismatch
# Control — the SAME stubs with the checkout moved ONTO E_TIP ⇒ MERGE: HEAD is the only variable.
git -C "$E_ROOT" checkout -q --detach "$E_TIP" >/dev/null 2>&1
rm -f "$GH_STUB_DIR/rules-called.log"; gate "$(pass_ctx)"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ] && rules_called; then
  ok "R11a control: the same stubs with the checkout AT the PR head ⇒ MERGE (HEAD is the only variable)"
else
  no "R11a control wrong (out='$RUN_OUT' merges=$(merges))"
fi
git -C "$E_ROOT" checkout -q - >/dev/null 2>&1
E_PR_HEAD="$E_HEAD"; reset_live
r11_restored "R11a"

# R11a' — cond 6 still takes precedence over the pin (a high-risk, stale-HEAD PR parks high_risk_diff).
E_PR_HEAD="$E_TIP"; reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
printf '{"high_risk": true, "reasons": ["path: billing/x.ts matched billing/**"], "source":"classify-risk.sh"}\n' > "$GH_STUB_DIR/risk.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: high_risk_diff (path: billing/x.ts matched billing/**)" ] && [ "$(merges)" -eq 0 ] && ! rules_called; then
  ok "R11a' precedence: cond 6 PARK wins over a stale-HEAD cond 7 pin"
else
  no "R11a' cond-6-over-pin precedence wrong (out='$RUN_OUT')"
fi
E_PR_HEAD="$E_HEAD"; reset_live

# R11b (AC2) — an unreadable HEAD fails CLOSED, never a match: not a checkout, a repo with no
# commit, a path that does not exist. nogit/ and emptyrepo/ name their base in a
# `.supervisor/config.json` (engine-owned, so it is not dirt) so condition 6's resolver answers and
# the pin is what parks them. A path that does not exist cannot name a base at all, so condition 6
# parks it first — `base_branch_unresolved`, still fail-CLOSED, still before the rules helper.
mkdir -p "$WD/nogit/.supervisor"
( cd "$WD" && git init -q emptyrepo ) >/dev/null 2>&1; mkdir -p "$WD/emptyrepo/.supervisor"
printf '{"base_branch":"main"}\n' > "$WD/nogit/.supervisor/config.json"
printf '{"base_branch":"main"}\n' > "$WD/emptyrepo/.supervisor/config.json"
for R11_ROOT in "$WD/nogit" "$WD/emptyrepo" "$WD/does-not-exist"; do
  reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
  E_GATE_ROOT="$R11_ROOT"; gate "$(pass_ctx)"; E_GATE_ROOT=""
  case "$R11_ROOT" in
    */does-not-exist) r11_park "unreadable HEAD (--root ${R11_ROOT#$WD/})" base_branch_unresolved ;;
    *)                r11_park "unreadable HEAD (--root ${R11_ROOT#$WD/})" rules_gate_head_mismatch ;;
  esac
done

# R11c (AC3) — dirt outside the engine-owned paths ⇒ rules_gate_dirty_tree. Each case: dirty, gate, undo.
r11_dirty() {  # r11_dirty <label> — run the gate on the (already dirtied) checkout, assert the dirty PARK
  reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
  gate "$(pass_ctx)"
  r11_park "$1" rules_gate_dirty_tree
}
echo more >> "$E_ROOT/sub/a"
r11_dirty "tracked modification (sub/a)"
git -C "$E_ROOT" checkout -q -- sub/a; r11_restored "tracked modification"
rm "$E_ROOT/sub/a"
r11_dirty "tracked deletion (sub/a)"
git -C "$E_ROOT" checkout -q -- sub/a; r11_restored "tracked deletion"
echo s > "$E_ROOT/staged.txt"; git -C "$E_ROOT" add staged.txt
r11_dirty "staged new file"
git -C "$E_ROOT" rm -q --cached staged.txt >/dev/null 2>&1; rm -f "$E_ROOT/staged.txt"; r11_restored "staged new file"
echo u > "$E_ROOT/untracked.txt"
r11_dirty "untracked non-ignored file at the top level"
git -C "$E_ROOT" config status.showUntrackedFiles no
r11_dirty "untracked file under the repo's status.showUntrackedFiles=no (the pin's -uall overrides it)"
git -C "$E_ROOT" config --unset status.showUntrackedFiles; rm -f "$E_ROOT/untracked.txt"; r11_restored "untracked file"
E_MEM_SIB="$E_ROOT/$(dirname "$E_MEM")/other"   # a sibling of the agent-memory dir, same parent
mkdir -p "$E_MEM_SIB"; echo o > "$E_MEM_SIB/o.md"
r11_dirty "untracked file beside, but OUTSIDE, $E_MEM"
rm -rf "$E_MEM_SIB"; r11_restored "agent-memory sibling"
mkdir -p "$E_ROOT/sub/.supervisor"; echo n > "$E_ROOT/sub/.supervisor/n.md"
r11_dirty "a NESTED sub/.supervisor/ file (the exclusion is anchored at the repo top level)"
rm -rf "$E_ROOT/sub/.supervisor"; r11_restored "nested .supervisor"
# Subdirectory --root: dirt elsewhere in the repo is still seen (the porcelain read is whole-repo).
echo u > "$E_ROOT/top.txt"
E_GATE_ROOT="$E_ROOT/sub"; r11_dirty "subdirectory --root (sub/) with an untracked file at the repo top level"; E_GATE_ROOT=""
rm -f "$E_ROOT/top.txt"; r11_restored "subdirectory root"
# A FAILING `git status` (corrupt index; `rev-parse HEAD` still reads fine) parks the same way.
cp "$E_ROOT/.git/index" "$WD/index.bak"; printf 'garbage' > "$E_ROOT/.git/index"
r11_dirty "git status fails (corrupt index)"
cp "$WD/index.bak" "$E_ROOT/.git/index"; r11_restored "corrupt index"

# R11d (AC4) — dirt ONLY under the engine-owned paths (tracked edits AND new untracked files)
# or only gitignored ⇒ the pin passes and the verdict decides exactly as today.
echo y >> "$E_ROOT/.supervisor/automate/run.md"; echo '{}' > "$E_ROOT/.supervisor/automate/run.sidecar.json"
r11_decides ".supervisor/-only dirt (tracked run-file edit + untracked sidecar)"
E_GATE_ROOT="$E_ROOT/sub"; r11_decides ".supervisor/-only dirt with a SUBDIRECTORY --root (exclusion still anchored at the top)"; E_GATE_ROOT=""
git -C "$E_ROOT" checkout -q -- .supervisor; rm -f "$E_ROOT/.supervisor/automate/run.sidecar.json"; r11_restored ".supervisor dirt"
echo y >> "$E_ROOT/$E_MEM/loomwright:code-reviewer/MEMORY.md"
mkdir -p "$E_ROOT/$E_MEM/loomwright:qa-executor"; echo n > "$E_ROOT/$E_MEM/loomwright:qa-executor/MEMORY.md"
r11_decides "$E_MEM-only dirt (tracked memory edit + untracked new agent dir)"
git -C "$E_ROOT" checkout -q -- "$E_MEM"; rm -rf "$E_ROOT/$E_MEM/loomwright:qa-executor"; r11_restored "agent-memory dirt"
echo i > "$E_ROOT/ignored.log"
r11_decides "gitignored-only file"
rm -f "$E_ROOT/ignored.log"; r11_restored "ignored file"

# R11f (review iteration 1) — LOCAL-ONLY git state must not hide dirt from the pin. Each
# leg below is invisible to a plain `git status --porcelain -uall` (the pre-fix pin MERGEd
# every one), so each parks only because of the reads the fix added.
r11_env_on() { export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fileMode GIT_CONFIG_VALUE_0=false; }
r11_env_off() { unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0; }
for R11_FLAG in assume-unchanged skip-worktree; do
  git -C "$E_ROOT" update-index --"$R11_FLAG" sub/a
  r11_dirty "tracked file flagged $R11_FLAG, unedited (any hiding flag parks)"
  echo more >> "$E_ROOT/sub/a"
  if [ -z "$(git -C "$E_ROOT" status --porcelain -uall 2>/dev/null)" ]; then
    r11_dirty "tracked edit hidden from git status by $R11_FLAG"
  else
    no "R11f $R11_FLAG: git status still shows the edit — the leg does not exercise the hiding flag"
  fi
  git -C "$E_ROOT" update-index --no-"$R11_FLAG" sub/a; git -C "$E_ROOT" checkout -q -- sub/a
  r11_restored "$R11_FLAG"
done
cp "$E_ROOT/.git/info/exclude" "$WD/exclude.bak" 2>/dev/null || : > "$WD/exclude.bak"
echo hid.txt >> "$E_ROOT/.git/info/exclude"; echo h > "$E_ROOT/hid.txt"
r11_dirty "untracked file hidden by .git/info/exclude"
cp "$WD/exclude.bak" "$E_ROOT/.git/info/exclude"; rm -f "$E_ROOT/hid.txt"; r11_restored "info/exclude"
echo hid.txt > "$WD/xfile"; git -C "$E_ROOT" config core.excludesFile "$WD/xfile"; echo h > "$E_ROOT/hid.txt"
r11_dirty "untracked file hidden by the repo's core.excludesFile"
git -C "$E_ROOT" config --unset core.excludesFile; rm -f "$E_ROOT/hid.txt"; r11_restored "core.excludesFile"
mkdir -p "$E_ROOT/evil"; echo '*' > "$E_ROOT/evil/.gitignore"; echo e > "$E_ROOT/evil/f"
# The park reads `evil/.gitignore` out of `ls-files -o -i --directory`; it relies on git
# LISTING the contents of a directory no rule ignores (observed on git 2.54/2.55) rather than
# collapsing it to `evil/`. Assert that assumption on the harness git, so a git that collapses
# turns this red with a named cause instead of a bare wrong-outcome leg.
if grep -qx 'evil/\.gitignore' <<<"$(git -C "$E_ROOT" ls-files -o -i --directory --exclude-per-directory=.gitignore 2>/dev/null)"; then
  ok "R11f precondition: this git lists evil/.gitignore under ls-files -o -i --directory (no collapse to evil/)"
else
  no "R11f precondition: this git ($(git --version 2>/dev/null)) collapses the self-ignoring directory — the untracked-.gitignore park cannot see it"
fi
r11_dirty "self-ignoring untracked evil/.gitignore hiding its whole directory"
rm -rf "$E_ROOT/evil"; r11_restored "self-ignoring .gitignore"
chmod +x "$E_ROOT/sub/a"; r11_env_on
r11_dirty "mode change hidden by env-injected core.fileMode=false (GIT_CONFIG_COUNT)"
r11_env_off; chmod -x "$E_ROOT/sub/a"; r11_restored "env-injected config"
E_GATE_ROOT="$E_ROOT/.git"; r11_dirty "--root inside .git/ at the live head (rev-parse --show-toplevel fails)"; E_GATE_ROOT=""
# Control: an untracked .gitignore inside a COMMITTED-ignored directory (node_modules/-style)
# is never read by git, so it is not dirt — the verdict still decides.
mkdir -p "$E_ROOT/ignored-dir/pkg"; echo '*' > "$E_ROOT/ignored-dir/pkg/.gitignore"; echo z > "$E_ROOT/ignored-dir/pkg/z"
r11_decides "untracked .gitignore nested in a committed-ignored directory"
rm -rf "$E_ROOT/ignored-dir"; r11_restored "ignored-dir"

# R11h (review iteration 2) — LIVENESS: the USER's global excludes file is honoured, so an
# at-head, otherwise-clean checkout holding a globally-only-ignored file (.DS_Store, .idea/,
# settings.local.json) still lets the verdict decide. Precondition first: with no global
# ignore the same file IS dirt (so each MERGE below is caused by the global file, nothing else).
# Relocated XDG_CONFIG_HOME / HOME fixtures only; the real user config is never read.
R11_XDG="$WD/xdg"; mkdir -p "$R11_XDG/git" "$WD/nohome/.config/git"
r11_gfix() { echo n > "$E_ROOT/notes.local"; mkdir -p "$E_ROOT/.idea"; echo i > "$E_ROOT/.idea/ws.xml"; }
r11_gundo() { rm -rf "$E_ROOT/notes.local" "$E_ROOT/.idea"; }
r11_gfix
r11_dirty "globally-ignorable files with NO global ignore configured (precondition: they are dirt)"
printf 'notes.local\n.idea/\n' > "$R11_XDG/git/ignore"; export XDG_CONFIG_HOME="$R11_XDG"
r11_decides "untracked files ignored only by \$XDG_CONFIG_HOME/git/ignore (user global ignore)"
unset XDG_CONFIG_HOME; rm -f "$R11_XDG/git/ignore"
printf 'notes.local\n.idea/\n' > "$WD/nohome/.config/git/ignore"
r11_decides "untracked files ignored only by \$HOME/.config/git/ignore (XDG unset fallback)"
rm -f "$WD/nohome/.config/git/ignore"
printf 'notes.local\n.idea/\n' > "$WD/gx-ignore"
printf '[core]\n\texcludesFile = %s\n' "$WD/gx-ignore" > "$WD/nohome/.gitconfig"
r11_decides "untracked files ignored only by core.excludesFile in the user's ~/.gitconfig"
# A RELATIVE global excludesFile would resolve against the checkout (repo bytes as ignore source).
mkdir -p "$E_ROOT/ignored-dir"; cp "$WD/gx-ignore" "$E_ROOT/ignored-dir/gx"
printf '[core]\n\texcludesFile = ignored-dir/gx\n' > "$WD/nohome/.gitconfig"
r11_dirty "global core.excludesFile given as a RELATIVE path (resolves into the checkout) is not honoured"
printf '[core]\n\texcludesFile = %s\n' "$E_ROOT/ignored-dir/gx" > "$WD/nohome/.gitconfig"
r11_dirty "global core.excludesFile pointing INSIDE the checkout (a committed-ignored file) is not honoured"
rm -f "$WD/nohome/.gitconfig"; rm -rf "$E_ROOT/ignored-dir"
# Env-injected excludesFile stays refused: GIT_CONFIG_COUNT and GIT_CONFIG_GLOBAL both unset by _ge_git.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile GIT_CONFIG_VALUE_0="$WD/gx-ignore"
r11_dirty "env-injected core.excludesFile (GIT_CONFIG_COUNT) is not honoured"
r11_env_off
printf '[core]\n\texcludesFile = %s\n' "$WD/gx-ignore" > "$WD/gcfg-injected"
export GIT_CONFIG_GLOBAL="$WD/gcfg-injected"
r11_dirty "env-injected global config (GIT_CONFIG_GLOBAL) naming an excludesFile is not honoured"
unset GIT_CONFIG_GLOBAL
r11_gundo; rm -f "$WD/gcfg-injected"; r11_restored "global ignore legs"
# info/exclude stays refused even WITH a global ignore configured (only the user-scope file is read).
printf 'unrelated\n' > "$R11_XDG/git/ignore"; export XDG_CONFIG_HOME="$R11_XDG"
echo hid.txt >> "$E_ROOT/.git/info/exclude"; echo h > "$E_ROOT/hid.txt"
r11_dirty "untracked file hidden by .git/info/exclude while a user global ignore is configured"
cp "$WD/exclude.bak" "$E_ROOT/.git/info/exclude"; rm -f "$E_ROOT/hid.txt"
unset XDG_CONFIG_HOME; rm -f "$R11_XDG/git/ignore"; r11_restored "info/exclude with global ignore"

# R11j (owner fix-now B2) — LIVENESS: a global core.excludesFile set through an [include] or
# [includeIf "gitdir:…"] in the user's ~/.gitconfig is followed exactly as git follows it, so
# the globally-ignored file does not park (the R11h precondition leg proved it is dirt without).
r11_gfix
printf '[core]\n\texcludesFile = %s\n' "$WD/gx-ignore" > "$WD/gx-inc"
printf '[include]\n\tpath = %s\n' "$WD/gx-inc" > "$WD/nohome/.gitconfig"
r11_decides "global core.excludesFile reached through an [include] in ~/.gitconfig"
printf '[includeIf "gitdir:%s/"]\n\tpath = %s\n' "$E_ROOT" "$WD/gx-inc" > "$WD/nohome/.gitconfig"
r11_decides "global core.excludesFile reached through an [includeIf \"gitdir:<checkout>/\"] in ~/.gitconfig"
rm -f "$WD/nohome/.gitconfig"

# R11k (owner fix-now B3) — the "outside the checkout" test is PHYSICAL: a directory alias of
# the checkout (a symlinked directory — the /tmp vs /private/tmp class) and a symlink outside
# the checkout whose target is an in-repo file are both refused, so the in-repo ignore is NOT
# honoured and the globally-ignorable files park. Control: a symlinked dotfile whose target
# is OUTSIDE the checkout (how dotfile managers install ~/.gitignore_global) is honoured.
mkdir -p "$E_ROOT/ignored-dir"; cp "$WD/gx-ignore" "$E_ROOT/ignored-dir/gx"
ln -s "$E_ROOT" "$WD/alias-co"; ln -s "$E_ROOT/ignored-dir/gx" "$WD/gx-link-in"; ln -s "$WD/gx-ignore" "$WD/gx-link-out"
printf '[core]\n\texcludesFile = %s\n' "$WD/alias-co/ignored-dir/gx" > "$WD/nohome/.gitconfig"
r11_dirty "global core.excludesFile spelled through a directory ALIAS of the checkout is not honoured"
printf '[core]\n\texcludesFile = %s\n' "$WD/gx-link-in" > "$WD/nohome/.gitconfig"
r11_dirty "global core.excludesFile that is a symlink OUTSIDE the checkout pointing at an in-repo file is not honoured"
printf '[core]\n\texcludesFile = %s\n' "$WD/gx-link-out" > "$WD/nohome/.gitconfig"
r11_decides "global core.excludesFile that is a symlink to a file OUTSIDE the checkout (control: honoured)"
rm -f "$WD/nohome/.gitconfig"; rm -rf "$E_ROOT/ignored-dir"; r11_gundo; r11_restored "global ignore include/physical legs"

# R11l (owner fix-now B1) — SUBMODULES. A separate superproject ($SM_TOP, submodule `lib`
# from $SM_LIB over a local path, protocol.file.allow only inside this fixture) whose COMMITTED
# .gitmodules says `ignore = all`. Precondition legs prove a plain `git status` sees nothing,
# so each PARK is the pin's own doing; the control (clean, correctly-pinned submodule) MERGEs
# and the gate leaves both index files untouched (it writes nothing, no submodule refresh).
SM_LIB="$WD/smlib"; SM_TOP="$WD/smtop"
r11_sm_git() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false -c protocol.file.allow=always "$@"; }
( git init -q "$SM_LIB" && cd "$SM_LIB" && echo l > l && git add l && r11_sm_git commit -qm l \
    && echo l2 > l2 && git add l2 && r11_sm_git commit -qm l2 \
  && git init -q "$SM_TOP" && cd "$SM_TOP" && echo t > t && git add t && r11_sm_git commit -qm t \
    && r11_sm_git submodule add -q "$SM_LIB" lib && r11_sm_git commit -qm sub \
    && git config -f .gitmodules submodule.lib.ignore all && git add .gitmodules && r11_sm_git commit -qm ign \
    && git update-ref refs/remotes/origin/main HEAD \
    && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main ) >/dev/null 2>&1   # cond 6 resolves its base on disk
SM_HEAD="$(git -C "$SM_TOP" rev-parse --verify -q HEAD 2>/dev/null)" || SM_HEAD=""
SM_GD="$(cd "$SM_TOP/lib" 2>/dev/null && git rev-parse --absolute-git-dir 2>/dev/null)" || SM_GD=""
r11_sm_clean() {  # the fixture is back: lib at its recorded commit, nothing dirty anywhere
  [ -n "$SM_HEAD" ] && [ -n "$SM_GD" ] \
    && [ -z "$(git -C "$SM_TOP" status --porcelain -uall --ignored --ignore-submodules=none 2>/dev/null)" ] \
    && [ -z "$(git -C "$SM_TOP/lib" status --porcelain -uall --ignored 2>/dev/null)" ]
}
if r11_sm_clean && [ -f "$SM_TOP/lib/l2" ]; then
  ok "R11l harness: superproject with a checked-out, correctly-pinned submodule and a committed ignore=all"
else
  no "R11l harness: could not build the submodule fixture (head='$SM_HEAD' gd='$SM_GD') — the R11l legs are meaningless"
fi
E_PR_HEAD="$SM_HEAD"; E_GATE_ROOT="$SM_TOP"
touch -t 200001010000 "$SM_TOP/.git/index" "$SM_GD/index"; touch -t 200101010000 "$WD/sm-ref"
r11_decides "clean superproject with a clean, correctly-pinned submodule (control)"
if [ -z "$(find "$SM_TOP/.git/index" "$SM_GD/index" -newer "$WD/sm-ref" 2>/dev/null)" ] && r11_sm_clean; then
  ok "R11l the gate wrote neither the superproject's nor the submodule's index (no refresh, no lock)"
else
  no "R11l the gate rewrote an index file (gate must write nothing)"
fi
echo dirt >> "$SM_TOP/lib/l"
r11_dirty "tracked edit inside a submodule whose committed .gitmodules says ignore=all"
git -C "$SM_TOP/lib" checkout -q -- l
git -C "$SM_TOP/lib" checkout -q HEAD~1 >/dev/null 2>&1
if [ -z "$(git -C "$SM_TOP" status --porcelain -uall 2>/dev/null)" ] && [ -n "$(git -C "$SM_TOP" status --porcelain --ignore-submodules=none 2>/dev/null)" ]; then
  r11_dirty "submodule checked out at a commit OTHER than the recorded one (hidden by committed ignore=all)"
else
  no "R11l stale-commit precondition: plain git status should be blind and --ignore-submodules=none should see it"
fi
git -C "$SM_TOP/lib" checkout -q - >/dev/null 2>&1
cp "$SM_GD/info/exclude" "$WD/sm-exclude.bak" 2>/dev/null || : > "$WD/sm-exclude.bak"
echo u >> "$SM_GD/info/exclude"; echo u > "$SM_TOP/lib/u"
if [ -z "$(git -C "$SM_TOP" status --porcelain -uall --ignore-submodules=none 2>/dev/null)" ]; then
  r11_dirty "untracked file inside a submodule hidden by the SUBMODULE's own info/exclude"
else
  no "R11l submodule info/exclude precondition: the top-level status should be blind to it"
fi
cp "$WD/sm-exclude.bak" "$SM_GD/info/exclude"; rm -f "$SM_TOP/lib/u"
git -C "$SM_TOP/lib" update-index --assume-unchanged l; echo dirt >> "$SM_TOP/lib/l"
r11_dirty "tracked edit inside a submodule hidden by the submodule's assume-unchanged flag"
git -C "$SM_TOP/lib" update-index --no-assume-unchanged l; git -C "$SM_TOP/lib" checkout -q -- l
E_PR_HEAD="$E_HEAD"; E_GATE_ROOT=""; reset_live
r11_sm_clean || no "R11l: the submodule fixture was NOT restored"

# R11e (AC6) — GATED mutation controls: delete each pin (its `if` line becomes `if false; then`)
# ⇒ the leg that pin guards turns into a MERGE, proving each leg can fail. Trusted only if the
# mutant is non-empty, differs from the original, passes `bash -n`, and carries its marker; the
# UN-mutated copy is run on the same two legs first (positive control).
M_HEAD="$(r9_dir 's/^  if \[ "\$root_head_rc" -ne 0 \] .*; then$/  if false; then # R11-MUTANT-HEAD/' 'R11-MUTANT-HEAD')"
M_DIRTY="$(r9_dir 's/^  if \[ "\$root_dirt_rc" -ne 0 \] .*; then$/  if false; then # R11-MUTANT-DIRTY/' 'R11-MUTANT-DIRTY')"
if [ -n "$M_HEAD" ] && [ -n "$M_DIRTY" ]; then
  CTRL="$(mktemp -d)"; cp "$GWD/automate-helpers.sh" "$GWD/classify-risk.sh" "$GWD/resolve-base-branch.sh" "$GWD/rules-gate-verdict.sh" "$CTRL/"
  # stale-HEAD leg: original parks, mutant merges.
  E_PR_HEAD="$E_TIP"; reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
  r9_run "$CTRL"; R11_CO="$R9_OUT"; R11_CM="$(merges)"
  r9_run "$M_HEAD"
  if [ "$R11_CO" = "PARK: rules_gate_head_mismatch" ] && [ "$R11_CM" -eq 0 ] && [ "$R9_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
    ok "R11e (mutant) HEAD pin deleted ⇒ the stale-HEAD leg MERGEs (control: the un-mutated gate parks it rules_gate_head_mismatch) — the leg can fail"
  else
    no "R11e HEAD-pin mutant did not discriminate (control='$R11_CO'/$R11_CM mutant='$R9_OUT'/$(merges))"
  fi
  E_PR_HEAD="$E_HEAD"; reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
  # dirty-tree leg: original parks, mutant merges. A TRACKED edit (not an untracked file),
  # because untracked files are now also caught by the ls-files read below the status one.
  echo more >> "$E_ROOT/sub/a"
  r9_run "$CTRL"; R11_CO="$R9_OUT"; R11_CM="$(merges)"
  r9_run "$M_DIRTY"
  if [ "$R11_CO" = "PARK: rules_gate_dirty_tree" ] && [ "$R11_CM" -eq 0 ] && [ "$R9_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
    ok "R11e (mutant) dirty-tree pin deleted ⇒ the dirty-tree leg MERGEs (control: the un-mutated gate parks it rules_gate_dirty_tree) — the leg can fail"
  else
    no "R11e dirty-pin mutant did not discriminate (control='$R11_CO'/$R11_CM mutant='$R9_OUT'/$(merges))"
  fi
  git -C "$E_ROOT" checkout -q -- sub/a; r11_restored "R11e"
  rm -rf "$CTRL"
else
  no "R11e pin mutation controls not gated (a mutant was empty, identical to the original, failed bash -n, or lacked its marker)"
fi
rm -rf "${M_HEAD:-/nonexistent-r11}" "${M_DIRTY:-/nonexistent-r11}"

# R11g (review iteration 1) — GATED mutants for each read the fix added: disable ONE read's
# park (or the env unset, or the show-toplevel fail-closed branch) ⇒ the R11f leg that only
# that read catches MERGEs; the un-mutated copy parks the same leg first (positive control).
r11g() {  # r11g <mutant-dir> <label> <setup> <undo> — control parks, mutant merges
  local co cm
  reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
  eval "$3"
  r9_run "$CTRL"; co="$R9_OUT"; cm="$(merges)"
  r9_run "$1"
  if [ "$co" = "PARK: rules_gate_dirty_tree" ] && [ "$cm" -eq 0 ] && [ "$R9_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
    ok "R11g (mutant) $2 ⇒ its leg MERGEs (control: the un-mutated gate parks it rules_gate_dirty_tree) — the read is load-bearing"
  else
    no "R11g $2 mutant did not discriminate (control='$co'/$cm mutant='$R9_OUT'/$(merges))"
  fi
  eval "$4"; r11_restored "R11g $2"
}
M_FLAGS="$(r9_dir 's/^  if \[ "\$root_flags_rc" -ne 0 \] .*; then$/  if false; then # R11-MUTANT-FLAGS/' 'R11-MUTANT-FLAGS')"
M_UNT="$(r9_dir 's/^  if \[ "\$root_unt_rc" -ne 0 \] .*; then$/  if false; then # R11-MUTANT-UNT/' 'R11-MUTANT-UNT')"
M_IGN="$(r9_dir 's/^  if \[ "\$root_ign_rc" -ne 0 \] .*; then$/  if false; then # R11-MUTANT-IGN/' 'R11-MUTANT-IGN')"
M_ENV="$(r9_dir 's/ -u GIT_CONFIG_COUNT / -u R11_MUTANT_ENV /' 'R11_MUTANT_ENV')"
M_TOP="$(r9_dir 's/^    root_dirt_rc=1$/    root_dirt_rc=0 # R11-MUTANT-TOP/' 'R11-MUTANT-TOP')"
M_INREPO="$(r9_dir 's/ || _ge_inside "\$ge_xf_p" "\$root_top"; then / ; then : R11-MUTANT-INREPO; /' 'R11-MUTANT-INREPO')"
# Owner fix-now mutants: B3 (symlink resolution dropped; physical resolution AND the -ef walk
# both reverted to the old lexical compare) and B1 (the submodule recursion's park deleted;
# `--ignore-submodules=none` dropped from the top-level status read).
M_LINK="$(r9_dir 's/^    while \[ -L "\$p" \]; do$/    while false; do # R11-MUTANT-LINK/' 'R11-MUTANT-LINK')"
M_LEX="$(r9_dir 's/^      ge_xf_p="\$(_ge_phys "\$ge_xf")" || ge_xf_p=""$/      ge_xf_p="$ge_xf" # R11-MUTANT-LEX/;s/^      \[ "\$d" -ef "\$2" \] \&\& return 0$/      [ "$d" = "$2" ] \&\& return 0/' 'R11-MUTANT-LEX')"
M_SUBS="$(r9_dir 's/^  if \[ "\$root_subs_rc" -ne 0 \]; then$/  if false; then # R11-MUTANT-SUBS/' 'R11-MUTANT-SUBS')"
M_SUBFLAG="$(r9_dir 's/^\(    root_dirt=.* status --porcelain -uall\) --ignore-submodules=none \(.*\)$/\1 \2 # R11-MUTANT-SUBFLAG/' 'R11-MUTANT-SUBFLAG')"
if [ -n "$M_FLAGS" ] && [ -n "$M_UNT" ] && [ -n "$M_IGN" ] && [ -n "$M_ENV" ] && [ -n "$M_TOP" ] && [ -n "$M_INREPO" ] \
   && [ -n "$M_LINK" ] && [ -n "$M_LEX" ] && [ -n "$M_SUBS" ] && [ -n "$M_SUBFLAG" ]; then
  CTRL="$(mktemp -d)"; cp "$GWD/automate-helpers.sh" "$GWD/classify-risk.sh" "$GWD/resolve-base-branch.sh" "$GWD/rules-gate-verdict.sh" "$CTRL/"
  r11g "$M_FLAGS" "assume-unchanged read deleted" \
    'git -C "$E_ROOT" update-index --assume-unchanged sub/a; echo more >> "$E_ROOT/sub/a"' \
    'git -C "$E_ROOT" update-index --no-assume-unchanged sub/a; git -C "$E_ROOT" checkout -q -- sub/a'
  r11g "$M_UNT" "committed-.gitignore-only untracked read deleted" \
    'echo hid.txt >> "$E_ROOT/.git/info/exclude"; echo h > "$E_ROOT/hid.txt"' \
    'cp "$WD/exclude.bak" "$E_ROOT/.git/info/exclude"; rm -f "$E_ROOT/hid.txt"'
  r11g "$M_IGN" "untracked-.gitignore read deleted" \
    'mkdir -p "$E_ROOT/evil"; echo "*" > "$E_ROOT/evil/.gitignore"; echo e > "$E_ROOT/evil/f"' \
    'rm -rf "$E_ROOT/evil"'
  r11g "$M_ENV" "GIT_CONFIG_COUNT unset removed" \
    'chmod +x "$E_ROOT/sub/a"; r11_env_on' \
    'r11_env_off; chmod -x "$E_ROOT/sub/a"'
  r11g "$M_TOP" "show-toplevel failure no longer fails closed" \
    'E_GATE_ROOT="$E_ROOT/.git"' \
    'E_GATE_ROOT=""'
  r11g "$M_INREPO" "in-checkout global excludesFile refusal removed" \
    'mkdir -p "$E_ROOT/ignored-dir"; printf "notes.local\n" > "$E_ROOT/ignored-dir/gx"; printf "[core]\n\texcludesFile = %s\n" "$E_ROOT/ignored-dir/gx" > "$WD/nohome/.gitconfig"; echo n > "$E_ROOT/notes.local"' \
    'rm -rf "$E_ROOT/ignored-dir" "$E_ROOT/notes.local" "$WD/nohome/.gitconfig"'
  r11g "$M_LINK" "symlinked global excludesFile no longer resolved" \
    'mkdir -p "$E_ROOT/ignored-dir"; printf "notes.local\n" > "$E_ROOT/ignored-dir/gx"; printf "[core]\n\texcludesFile = %s\n" "$WD/gx-link-in" > "$WD/nohome/.gitconfig"; echo n > "$E_ROOT/notes.local"' \
    'rm -rf "$E_ROOT/ignored-dir" "$E_ROOT/notes.local" "$WD/nohome/.gitconfig"'
  r11g "$M_LEX" "outside-the-checkout test reverted to a lexical prefix compare" \
    'mkdir -p "$E_ROOT/ignored-dir"; printf "notes.local\n" > "$E_ROOT/ignored-dir/gx"; printf "[core]\n\texcludesFile = %s\n" "$WD/alias-co/ignored-dir/gx" > "$WD/nohome/.gitconfig"; echo n > "$E_ROOT/notes.local"' \
    'rm -rf "$E_ROOT/ignored-dir" "$E_ROOT/notes.local" "$WD/nohome/.gitconfig"'
  E_PR_HEAD="$SM_HEAD"
  r11g "$M_SUBS" "submodule recursion park deleted" \
    'E_GATE_ROOT="$SM_TOP"; echo u >> "$SM_GD/info/exclude"; echo u > "$SM_TOP/lib/u"' \
    'E_GATE_ROOT=""; cp "$WD/sm-exclude.bak" "$SM_GD/info/exclude"; rm -f "$SM_TOP/lib/u"'
  r11g "$M_SUBFLAG" "--ignore-submodules=none dropped from the top-level status" \
    'E_GATE_ROOT="$SM_TOP"; git -C "$SM_TOP/lib" checkout -q HEAD~1 >/dev/null 2>&1' \
    'E_GATE_ROOT=""; git -C "$SM_TOP/lib" checkout -q - >/dev/null 2>&1'
  E_PR_HEAD="$E_HEAD"; reset_live
  r11_sm_clean || no "R11g: the submodule fixture was NOT restored after its mutants"
  rm -rf "$CTRL"
else
  no "R11g read mutation controls not gated (a mutant was empty, identical to the original, failed bash -n, or lacked its marker)"
fi
rm -rf "${M_FLAGS:-/nonexistent-r11}" "${M_UNT:-/nonexistent-r11}" "${M_IGN:-/nonexistent-r11}" "${M_ENV:-/nonexistent-r11}" "${M_TOP:-/nonexistent-r11}" "${M_INREPO:-/nonexistent-r11}" \
  "${M_LINK:-/nonexistent-r11}" "${M_LEX:-/nonexistent-r11}" "${M_SUBS:-/nonexistent-r11}" "${M_SUBFLAG:-/nonexistent-r11}"

# R11i (review iteration 2) — GATED liveness mutant: drop the global `--exclude-from` ⇒ the
# R11h XDG leg PARKs again (the iteration-1 behaviour), while the un-mutated copy MERGEs it.
M_XF="$(r9_dir 's/^    if \[ -n "\$ge_xf" \] && \[ -f "\$ge_xf" \] && \[ -r "\$ge_xf" \]; then ge_xargs=.*$/    : # R11-MUTANT-XF/' 'R11-MUTANT-XF')"
if [ -n "$M_XF" ]; then
  CTRL="$(mktemp -d)"; cp "$GWD/automate-helpers.sh" "$GWD/classify-risk.sh" "$GWD/resolve-base-branch.sh" "$GWD/rules-gate-verdict.sh" "$CTRL/"
  reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
  printf 'notes.local\n' > "$R11_XDG/git/ignore"; export XDG_CONFIG_HOME="$R11_XDG"; echo n > "$E_ROOT/notes.local"
  r9_run "$CTRL"; R11_CO="$R9_OUT"; R11_CM="$(merges)"
  r9_run "$M_XF"
  if [ "$R11_CO" = "MERGE" ] && [ "$R11_CM" -eq 1 ] && [ "$R9_OUT" = "PARK: rules_gate_dirty_tree" ] && [ "$(merges)" -eq 0 ]; then
    ok "R11i (mutant) global --exclude-from dropped ⇒ the globally-ignored-file leg PARKs (control: the un-mutated gate MERGEs it) — the liveness leg can fail"
  else
    no "R11i global-ignore mutant did not discriminate (control='$R11_CO'/$R11_CM mutant='$R9_OUT'/$(merges))"
  fi
  unset XDG_CONFIG_HOME; rm -f "$R11_XDG/git/ignore" "$E_ROOT/notes.local"; r11_restored "R11i"
  rm -rf "$CTRL"
else
  no "R11i global-ignore mutation control not gated (mutant empty, identical to the original, failed bash -n, or lacked its marker)"
fi
rm -rf "${M_XF:-/nonexistent-r11}"

# R11m (owner fix-now B2) — GATED liveness mutant: drop `--includes` from the global
# excludesFile read ⇒ the R11j [include] leg PARKs (git's own lookup would have followed the
# include), while the un-mutated copy MERGEs it.
M_INC="$(r9_dir 's/ config --global --includes --path --get core\.excludesFile / config --global --path --get core.excludesFile /;s/^\(    ge_xf=.*core\.excludesFile .*\)$/\1 # R11-MUTANT-INC/' 'R11-MUTANT-INC')"
if [ -n "$M_INC" ]; then
  CTRL="$(mktemp -d)"; cp "$GWD/automate-helpers.sh" "$GWD/classify-risk.sh" "$GWD/resolve-base-branch.sh" "$GWD/rules-gate-verdict.sh" "$CTRL/"
  reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
  printf '[include]\n\tpath = %s\n' "$WD/gx-inc" > "$WD/nohome/.gitconfig"; echo n > "$E_ROOT/notes.local"
  r9_run "$CTRL"; R11_CO="$R9_OUT"; R11_CM="$(merges)"
  r9_run "$M_INC"
  if [ "$R11_CO" = "MERGE" ] && [ "$R11_CM" -eq 1 ] && [ "$R9_OUT" = "PARK: rules_gate_dirty_tree" ] && [ "$(merges)" -eq 0 ]; then
    ok "R11m (mutant) --includes dropped ⇒ the [include]-reached global ignore leg PARKs (control: the un-mutated gate MERGEs it) — the liveness leg can fail"
  else
    no "R11m --includes mutant did not discriminate (control='$R11_CO'/$R11_CM mutant='$R9_OUT'/$(merges))"
  fi
  rm -f "$WD/nohome/.gitconfig" "$E_ROOT/notes.local"; r11_restored "R11m"
  rm -rf "$CTRL"
else
  no "R11m --includes mutation control not gated (mutant empty, identical to the original, failed bash -n, or lacked its marker)"
fi
rm -rf "${M_INC:-/nonexistent-r11}"
reset_live

unset GH_STUB_DIR
rm -rf "$WD"

