#!/usr/bin/env bash
# test-wait-for-checks.sh — self-tests for wait-for-checks.sh (red-team-hardening
# item 04). Fixture-driven: a scripted `$GH` stub returns a SEQUENCE of rollup
# responses across polls (via a per-run counter file), never a real network call.
# Exit 0 = all pass, 1 = any failure. UNCOUNTED by the doc-currency gate (test-*.sh).
#
# Covers (AC1/AC2):
#   1. pending -> green: required check starts IN_PROGRESS, settles SUCCESS on
#      the next poll => SETTLED sha=<sha> required=green.
#   2. pending -> red: required check settles FAILURE => SETTLED required=red.
#   3. wrong-sha -> right-sha: the rollup initially reports a DIFFERENT sha
#      (never treated as settled), then the correct sha with a green check =>
#      SETTLED only once the sha matches.
#   4. never-settles: the required check stays IN_PROGRESS forever => the wait
#      hits its --bound and prints ELAPSED, never hangs past bound + one
#      poll interval.
#   5. --review-check-pattern scope: a review-producing (non-required) check
#      still in flight blocks settlement; once it goes green, SETTLED.
#   6. --required-only scope: a review-producing check left pending is IGNORED
#      (only required checks are waited on).
#   7. always exits 0, even on a bad/missing gh (degrades to ELAPSED).
#   8. bad usage (missing --sha/--bound) => ELAPSED, never a non-zero exit.
#   9/10. (PR #251 review finding 2) a branch-protection read that fails with
#      a non-404 error => required=unknown, NEVER a vacuous green; a genuine
#      404 (real unprotected branch) => required=green (verified empty).
#  11-16. (automate-followups/31) the opt-in --names flag: default line byte-
#      unchanged; pending_names (required included, absent required = pending,
#      sha_mismatch) and red_names (name@run_id, '-' without a run id); scope.
#  17. (review iteration 2) --names green needs EACH of conclusion/state green.
#  18-24. (implementation-quality/02 T03) resumable --call-max mode: CONTINUE,
#      persisted total deadline, --continue fail-closed, new-sha key, mutation
#      control (deadline reset), no state leak into the cwd.
#  25-27. (fix-now A) a first call that finds an UNEXPIRED deadline for its key
#      keeps it (a dropped --continue never earns a fresh total) and warns;
#      --restart replaces it; an expired one is replaced; gated mutant.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/wait-for-checks.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

PR="https://github.com/acme/widgets/pull/42"
SHA="deadbeef00"

# fresh_stub_dir — an isolated temp dir holding the scripted gh stub + its
# per-run call counter. Echoes the dir.
fresh_stub_dir() {
  local d; d="$(mktemp -d)"
  printf '%s' "$d"
}

# ----------------------------------------------------------------------------
# Case 1/2: pending -> green|red. First poll: required check IN_PROGRESS at
# the target sha. Second poll: COMPLETED with the given conclusion.
# ----------------------------------------------------------------------------
write_pending_then_settle_stub() {
  local dir="$1" conclusion="$2"
  cat > "$dir/gh" <<EOF
#!/usr/bin/env bash
CNT="$dir/count"
if [ "\$1 \$2" = "pr" ] 2>/dev/null; then :; fi
case "\$*" in
  *baseRefName*)
    printf '{"baseRefName":"main"}\n'
    exit 0
    ;;
  *headRefOid*)
    [ -f "\$CNT" ] || echo 0 > "\$CNT"
    n=\$(cat "\$CNT"); n=\$((n+1)); echo "\$n" > "\$CNT"
    if [ "\$n" -lt 2 ]; then
      printf '{"headRefOid":"$SHA","statusCheckRollup":[{"name":"ci","status":"IN_PROGRESS","conclusion":"","state":""}]}\n'
    else
      printf '{"headRefOid":"$SHA","statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"$conclusion","state":""}]}\n'
    fi
    exit 0
    ;;
esac
if [ "\$1" = "api" ]; then
  printf '{"required_status_checks":{"contexts":["ci"]}}\n'
  exit 0
fi
exit 0
EOF
  chmod +x "$dir/gh"
}

echo "== 1. pending -> green: SETTLED sha=<sha> required=green =="
D1="$(fresh_stub_dir)"
write_pending_then_settle_stub "$D1" "SUCCESS"
OUT1="$(GH="$D1/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 10 --interval 1 --required-only)"
RC1=$?
if [ "$RC1" -eq 0 ] && grep -qE '^SETTLED sha=deadbeef00 required=green' < <(printf '%s' "$OUT1"); then
  ok "pending->green: $OUT1"
else
  no "pending->green wrong (rc=$RC1 out='$OUT1')"
fi
rm -rf "$D1"

echo "== 2. pending -> red: SETTLED sha=<sha> required=red =="
D2="$(fresh_stub_dir)"
write_pending_then_settle_stub "$D2" "FAILURE"
OUT2="$(GH="$D2/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 10 --interval 1 --required-only)"
RC2=$?
if [ "$RC2" -eq 0 ] && grep -qE '^SETTLED sha=deadbeef00 required=red' < <(printf '%s' "$OUT2"); then
  ok "pending->red: $OUT2"
else
  no "pending->red wrong (rc=$RC2 out='$OUT2')"
fi
rm -rf "$D2"

# ----------------------------------------------------------------------------
# Case 3: wrong-sha -> right-sha. First poll reports a DIFFERENT commit
# entirely (with an already-green rollup for THAT sha — a trap for a script
# that forgets to check headRefOid) — must NOT be treated as settled. Second
# poll reports the correct sha, green.
# ----------------------------------------------------------------------------
echo "== 3. wrong-sha -> right-sha: a rollup for a DIFFERENT sha is NEVER treated as settled =="
D3="$(fresh_stub_dir)"
cat > "$D3/gh" <<EOF
#!/usr/bin/env bash
CNT="$D3/count"
case "\$*" in
  *baseRefName*)
    printf '{"baseRefName":"main"}\n'
    exit 0
    ;;
  *headRefOid*)
    [ -f "\$CNT" ] || echo 0 > "\$CNT"
    n=\$(cat "\$CNT"); n=\$((n+1)); echo "\$n" > "\$CNT"
    if [ "\$n" -lt 2 ]; then
      # A DIFFERENT sha, already "green" — must be ignored entirely.
      printf '{"headRefOid":"some-other-commit","statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS","state":""}]}\n'
    else
      printf '{"headRefOid":"$SHA","statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS","state":""}]}\n'
    fi
    exit 0
    ;;
esac
if [ "\$1" = "api" ]; then
  printf '{"required_status_checks":{"contexts":["ci"]}}\n'
  exit 0
fi
exit 0
EOF
chmod +x "$D3/gh"
OUT3="$(GH="$D3/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 10 --interval 1 --required-only)"
RC3=$?
CALLS3="$(cat "$D3/count" 2>/dev/null || echo 0)"
if [ "$RC3" -eq 0 ] && grep -qE '^SETTLED sha=deadbeef00 required=green' < <(printf '%s' "$OUT3") && [ "$CALLS3" -ge 2 ]; then
  ok "wrong-sha->right-sha: settled only once the sha matched ($OUT3, polls=$CALLS3)"
else
  no "wrong-sha->right-sha wrong (rc=$RC3 out='$OUT3' polls=$CALLS3)"
fi
rm -rf "$D3"

# ----------------------------------------------------------------------------
# Case 4: never-settles. Required check is IN_PROGRESS on every poll. The wait
# must terminate at --bound (never hang), printing ELAPSED.
# ----------------------------------------------------------------------------
echo "== 4. never-settles: hits --bound, prints ELAPSED, never hangs past bound + one poll interval =="
D4="$(fresh_stub_dir)"
cat > "$D4/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *baseRefName*)
    printf '{"baseRefName":"main"}\n'
    exit 0
    ;;
  *headRefOid*)
    printf '{"headRefOid":"$SHA","statusCheckRollup":[{"name":"ci","status":"IN_PROGRESS","conclusion":"","state":""}]}\n'
    exit 0
    ;;
esac
if [ "\$1" = "api" ]; then
  printf '{"required_status_checks":{"contexts":["ci"]}}\n'
  exit 0
fi
exit 0
EOF
chmod +x "$D4/gh"
START4=$SECONDS
OUT4="$(GH="$D4/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 2 --interval 1 --required-only)"
RC4=$?
ELAPSED4=$((SECONDS - START4))
# Bound (2s) + one poll interval (1s) + generous scheduling slack.
if [ "$RC4" -eq 0 ] && grep -qE '^ELAPSED sha=deadbeef00' < <(printf '%s' "$OUT4") && [ "$ELAPSED4" -le 8 ]; then
  ok "never-settles: ELAPSED within bound+interval ($OUT4, wall=${ELAPSED4}s)"
else
  no "never-settles wrong (rc=$RC4 out='$OUT4' wall=${ELAPSED4}s)"
fi
rm -rf "$D4"

# ----------------------------------------------------------------------------
# Case 5: --review-check-pattern scope — a review-producing (non-required)
# check still in flight blocks settlement even though the required check is
# already green; once it also settles, SETTLED fires.
# ----------------------------------------------------------------------------
echo "== 5. --review-check-pattern scope: review-producing check in flight blocks settlement =="
D5="$(fresh_stub_dir)"
cat > "$D5/gh" <<EOF
#!/usr/bin/env bash
CNT="$D5/count"
case "\$*" in
  *baseRefName*)
    printf '{"baseRefName":"main"}\n'
    exit 0
    ;;
  *headRefOid*)
    [ -f "\$CNT" ] || echo 0 > "\$CNT"
    n=\$(cat "\$CNT"); n=\$((n+1)); echo "\$n" > "\$CNT"
    if [ "\$n" -lt 2 ]; then
      printf '{"headRefOid":"$SHA","statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS","state":""},{"name":"claude-review","status":"IN_PROGRESS","conclusion":"","state":""}]}\n'
    else
      printf '{"headRefOid":"$SHA","statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS","state":""},{"name":"claude-review","status":"COMPLETED","conclusion":"SUCCESS","state":""}]}\n'
    fi
    exit 0
    ;;
esac
if [ "\$1" = "api" ]; then
  printf '{"required_status_checks":{"contexts":["ci"]}}\n'
  exit 0
fi
exit 0
EOF
chmod +x "$D5/gh"
OUT5="$(GH="$D5/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 10 --interval 1 --review-check-pattern '*review*')"
RC5=$?
CALLS5="$(cat "$D5/count" 2>/dev/null || echo 0)"
if [ "$RC5" -eq 0 ] && grep -qE '^SETTLED sha=deadbeef00 required=green review_producing=settled' < <(printf '%s' "$OUT5") && [ "$CALLS5" -ge 2 ]; then
  ok "review-check-pattern scope: waited for claude-review too ($OUT5, polls=$CALLS5)"
else
  no "review-check-pattern scope wrong (rc=$RC5 out='$OUT5' polls=$CALLS5)"
fi
rm -rf "$D5"

echo "== 6. --required-only scope: a review-producing check left pending is IGNORED =="
D6="$(fresh_stub_dir)"
cat > "$D6/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *baseRefName*)
    printf '{"baseRefName":"main"}\n'
    exit 0
    ;;
  *headRefOid*)
    printf '{"headRefOid":"$SHA","statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS","state":""},{"name":"claude-review","status":"IN_PROGRESS","conclusion":"","state":""}]}\n'
    exit 0
    ;;
esac
if [ "\$1" = "api" ]; then
  printf '{"required_status_checks":{"contexts":["ci"]}}\n'
  exit 0
fi
exit 0
EOF
chmod +x "$D6/gh"
OUT6="$(GH="$D6/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 10 --interval 1 --required-only)"
RC6=$?
if [ "$RC6" -eq 0 ] && grep -qE '^SETTLED sha=deadbeef00 required=green' < <(printf '%s' "$OUT6"); then
  ok "required-only scope: settled on the FIRST poll, ignoring claude-review's IN_PROGRESS ($OUT6)"
else
  no "required-only scope wrong (rc=$RC6 out='$OUT6')"
fi
rm -rf "$D6"

echo "== 7. always exits 0 even when gh is unusable (degrades to ELAPSED, never hangs/crashes) =="
D7="$(fresh_stub_dir)"
cat > "$D7/gh" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
chmod +x "$D7/gh"
OUT7="$(GH="$D7/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 1 --interval 1 --required-only)"
RC7=$?
if [ "$RC7" -eq 0 ] && grep -q '^ELAPSED' < <(printf '%s' "$OUT7"); then
  ok "unusable gh: exit 0, degrades to ELAPSED ($OUT7)"
else
  no "unusable gh wrong (rc=$RC7 out='$OUT7')"
fi
rm -rf "$D7"

echo "== 8. bad usage (missing --sha/--bound) => exit 0, ELAPSED, never a non-zero exit =="
OUT8="$(bash "$SUT" "$PR" 2>/dev/null)"
RC8=$?
if [ "$RC8" -eq 0 ] && grep -q '^ELAPSED' < <(printf '%s' "$OUT8"); then
  ok "bad usage: exit 0, ELAPSED ($OUT8)"
else
  no "bad usage wrong (rc=$RC8 out='$OUT8')"
fi

# ----------------------------------------------------------------------------
# Case 9/10 (PR #251 review finding 2): an unreadable branch-protection read
# must NEVER be silently reported as required=green — that is the exact
# vacuous-success hole this whole item exists to close. A genuinely
# unprotected branch (real 404 "Branch not protected") is the ONE case that
# is a VERIFIED empty required set and stays required=green; anything else
# (403/5xx/garbage) must surface required=unknown so the caller's fail-CLOSED
# rule (review-heal/SKILL.md §U2) can escalate instead of proceeding blind.
# ----------------------------------------------------------------------------
write_protection_failure_stub() {
  local dir="$1" errline="$2"
  cat > "$dir/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *baseRefName*)
    printf '{"baseRefName":"main"}\n'
    exit 0
    ;;
  *headRefOid*)
    printf '{"headRefOid":"$SHA","statusCheckRollup":[]}\n'
    exit 0
    ;;
esac
if [ "\$1" = "api" ]; then
  echo "$errline" >&2
  exit 1
fi
exit 0
EOF
  chmod +x "$dir/gh"
}

echo "== 9. branch-protection read fails with a non-404 error (403) => required=unknown, NEVER green =="
D9="$(fresh_stub_dir)"
write_protection_failure_stub "$D9" "gh: Resource not accessible by integration (HTTP 403)"
OUT9="$(GH="$D9/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 10 --interval 1 --required-only)"
RC9=$?
if [ "$RC9" -eq 0 ] && grep -qE '^SETTLED sha=deadbeef00 required=unknown' < <(printf '%s' "$OUT9"); then
  ok "protection 403: required=unknown, not green ($OUT9)"
else
  no "protection 403 wrong (rc=$RC9 out='$OUT9') -- must never claim required=green on an unreadable read"
fi
rm -rf "$D9"

echo "== 10. branch-protection read fails with a genuine 404 (unprotected branch) => required=green (verified empty, NOT unknown) =="
D10="$(fresh_stub_dir)"
write_protection_failure_stub "$D10" "gh: Branch not protected (HTTP 404)"
OUT10="$(GH="$D10/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 10 --interval 1 --required-only)"
RC10=$?
if [ "$RC10" -eq 0 ] && grep -qE '^SETTLED sha=deadbeef00 required=green' < <(printf '%s' "$OUT10"); then
  ok "genuinely unprotected (404): required=green, not unknown ($OUT10)"
else
  no "genuinely unprotected (404) wrong (rc=$RC10 out='$OUT10') -- a verified-empty required set must not be punished as unknown"
fi
rm -rf "$D10"

# ----------------------------------------------------------------------------
# Cases 11-16 (automate-followups/31): the OPT-IN --names flag. Without it the
# line is byte-unchanged (11); with it two trailing fields name the scoped set.
# ----------------------------------------------------------------------------
# write_names_stub <dir> <rollup_json> [<protection_contexts_json>] — one fixed
# rollup for every poll; branch protection names the given contexts (default ["ci"]).
write_names_stub() {
  local dir="$1" rollup="$2" ctx="${3:-[\"ci\"]}"
  printf '%s\n' "$rollup" > "$dir/rollup.json"
  printf '{"required_status_checks":{"contexts":%s}}\n' "$ctx" > "$dir/prot.json"
  cat > "$dir/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *baseRefName*) printf '{"baseRefName":"main"}\n'; exit 0 ;;
  *headRefOid*) cat "$dir/rollup.json"; exit 0 ;;
esac
[ "\$1" = "api" ] && { cat "$dir/prot.json"; exit 0; }
exit 0
EOF
  chmod +x "$dir/gh"
}
N_ROLL_PEND='{"headRefOid":"deadbeef00","statusCheckRollup":[{"name":"ci","status":"IN_PROGRESS","conclusion":"","state":""},{"name":"claude-review","status":"IN_PROGRESS","conclusion":"","state":""},{"name":"lint","status":"IN_PROGRESS","conclusion":"","state":""}]}'

echo "== 11. no --names => the output line is byte-unchanged (no pending_names/red_names fields) =="
D11="$(fresh_stub_dir)"; write_names_stub "$D11" "$N_ROLL_PEND"
OUT11="$(GH="$D11/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 0 --interval 1)"
if [ "$OUT11" = "ELAPSED sha=deadbeef00 required=pending review_producing=elapsed pending=claude-review" ]; then
  ok "default output unchanged without --names ($OUT11)"
else
  no "default output changed without --names: '$OUT11'"
fi
rm -rf "$D11"

echo "== 12. --names: pending_names lists every scoped pending check, REQUIRED included (pending= omits it); unscoped 'lint' excluded =="
D12="$(fresh_stub_dir)"; write_names_stub "$D12" "$N_ROLL_PEND"
OUT12="$(GH="$D12/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 0 --interval 1 --names)"
if [ "$OUT12" = "ELAPSED sha=deadbeef00 required=pending review_producing=elapsed pending=claude-review pending_names=ci,claude-review red_names=none" ]; then
  ok "--names pending: $OUT12"
else
  no "--names pending wrong: '$OUT12'"
fi
rm -rf "$D12"

echo "== 13. --names: red_names carries name@run_id parsed from detailsUrl, '-' when absent; neutral/skipped are not red =="
D13="$(fresh_stub_dir)"
write_names_stub "$D13" '{"headRefOid":"deadbeef00","statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://github.com/acme/widgets/actions/runs/777/job/9"},{"name":"claude-review","status":"COMPLETED","conclusion":"CANCELLED"},{"name":"review-lint","status":"COMPLETED","conclusion":"NEUTRAL"},{"name":"claude-x","status":"COMPLETED","conclusion":"SKIPPED"}]}'
OUT13="$(GH="$D13/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 0 --interval 1 --names)"
if [ "$OUT13" = "SETTLED sha=deadbeef00 required=red review_producing=settled pending_names=none red_names=ci@777,claude-review@-" ]; then
  ok "--names red: $OUT13"
else
  no "--names red wrong: '$OUT13'"
fi
rm -rf "$D13"

echo "== 14. --names: a required context ABSENT from the rollup is pending (never read as green) =="
D14="$(fresh_stub_dir)"
write_names_stub "$D14" '{"headRefOid":"deadbeef00","statusCheckRollup":[{"name":"claude-review","status":"COMPLETED","conclusion":"SUCCESS"}]}' '["ci"]'
OUT14="$(GH="$D14/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 0 --interval 1 --names)"
case "$OUT14" in
  *" pending_names=ci red_names=none") ok "--names absent required context is pending ($OUT14)" ;;
  *) no "--names absent required context wrong: '$OUT14'" ;;
esac
rm -rf "$D14"

echo "== 15. --names: a rollup for a DIFFERENT sha => pending_names=sha_mismatch =="
D15="$(fresh_stub_dir)"
write_names_stub "$D15" '{"headRefOid":"other00","statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]}'
OUT15="$(GH="$D15/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 0 --interval 1 --names)"
case "$OUT15" in
  *" pending=sha_mismatch pending_names=sha_mismatch red_names=none") ok "--names sha mismatch: $OUT15" ;;
  *) no "--names sha mismatch wrong: '$OUT15'" ;;
esac
rm -rf "$D15"

echo "== 16. --required-only --names: review-producing checks are out of scope =="
D16="$(fresh_stub_dir)"; write_names_stub "$D16" "$N_ROLL_PEND"
OUT16="$(GH="$D16/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 0 --interval 1 --required-only --names)"
case "$OUT16" in
  *" pending_names=ci red_names=none") ok "--required-only --names scope: $OUT16" ;;
  *) no "--required-only --names scope wrong: '$OUT16'" ;;
esac
rm -rf "$D16"

echo "== 17. (review iteration 2) --names: green only when EACH of conclusion/state is a green value — never a prefix of their concatenation =="
D17="$(fresh_stub_dir)"
N_ROLL_MIX='{"headRefOid":"deadbeef00","statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"claude-review","status":"COMPLETED","conclusion":"SUCCESS","state":"FAILURE"}]}'
write_names_stub "$D17" "$N_ROLL_MIX"
OUT17="$(GH="$D17/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 0 --interval 1 --names)"
case "$OUT17" in
  *" pending_names=none red_names=claude-review@-") ok "--names SUCCESS conclusion + FAILURE state is red ($OUT17)" ;;
  *) no "--names mixed conclusion/state wrong: '$OUT17'" ;;
esac
# MUTATION CONTROL: drop the per-field state check (back to the concatenated-prefix
# reading) ⇒ claude-review reads green.
M17="$D17/mut-wait-for-checks.sh"
grep -vxF "    case \"\$_up_sta\" in ''|SUCCESS) ;; *) _g=0 ;; esac" "$SUT" > "$M17"
if [ -s "$M17" ] && ! cmp -s "$SUT" "$M17" && bash -n "$M17" && [ "$(( $(wc -l < "$SUT") - $(wc -l < "$M17") ))" = 1 ]; then
  OUT17M="$(GH="$D17/gh" bash "$M17" "$PR" --sha "$SHA" --bound 0 --interval 1 --names)"
  case "$OUT17M" in *" red_names=none") ok "mutation control: without the per-field state check the mixed entry reads green ($OUT17M)" ;;
    *) no "mutation control did NOT discriminate: '$OUT17M'" ;; esac
else
  no "case 17 mutant invalid (empty / identical / bash -n / not exactly 1 line)"
fi
rm -rf "$D17"

# ----------------------------------------------------------------------------
# 18-24. (implementation-quality/02 T03) resumable mode: --call-max + a persisted
# TOTAL deadline. Every call runs with its cwd inside a temp dir, so the state
# (.supervisor/check-wait/) can never leak into this test's own cwd (the
# drain-rounds LEAK PIN lesson) — asserted in case 24.
# ----------------------------------------------------------------------------
LEAK_BEFORE=0; [ -d .supervisor/check-wait ] && LEAK_BEFORE=1
write_never_settles_stub() {
  cat > "$1/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *baseRefName*) printf '{"baseRefName":"main"}\n'; exit 0 ;;
  *headRefOid*) printf '{"headRefOid":"$SHA","statusCheckRollup":[{"name":"ci","status":"IN_PROGRESS","conclusion":"","state":""}]}\n'; exit 0 ;;
esac
[ "\$1" = "api" ] && printf '{"required_status_checks":{"contexts":["ci"]}}\n'
exit 0
EOF
  chmod +x "$1/gh"
}
# wfc <dir> <script> <args...> — run the wait with cwd = <dir> (state lands in <dir>).
wfc() { local d="$1" s="$2"; shift 2; ( cd "$d" && GH="$d/gh" bash "$s" "$@" 2>/dev/null ); }
state_count() { find "$1/.supervisor/check-wait" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }

echo "== 18. --bound 4 --call-max 2: call 1 prints CONTINUE remaining≈2 within call-max + one interval =="
D18="$(fresh_stub_dir)"; write_never_settles_stub "$D18"
T0=$SECONDS
OUT18="$(wfc "$D18" "$SUT" "$PR" --sha "$SHA" --bound 4 --call-max 2 --interval 1 --required-only)"
T18=$((SECONDS - T0))
case "$OUT18" in
  "CONTINUE sha=$SHA remaining="[123]" pending=none") ok "call 1 CONTINUE ($OUT18) in ${T18}s" ;;
  *) no "call 1 expected CONTINUE remaining 1-3: '$OUT18'" ;;
esac
[ "$T18" -le 5 ] && ok "call 1 returned within call-max + one interval (+2 s slack for a loaded pool)" || no "call 1 took ${T18}s"
[ "$(state_count "$D18")" = 1 ] && ok "call 1 persisted exactly one deadline" || no "call 1 state files: $(state_count "$D18")"

echo "== 19. call 2 (--continue, same sha) ELAPSES within the REMAINING budget, not a fresh 4 s =="
T0=$SECONDS
OUT19="$(wfc "$D18" "$SUT" "$PR" --sha "$SHA" --bound 4 --call-max 2 --interval 1 --required-only --continue)"
T19=$((SECONDS - T0))
case "$OUT19" in
  "ELAPSED sha=$SHA required=pending review_producing=settled pending=none") ok "call 2 ELAPSED ($OUT19) in ${T19}s" ;;
  *) no "call 2 expected ELAPSED: '$OUT19'" ;;
esac
[ "$T19" -le 4 ] && ok "call 2 elapsed within the remaining budget" || no "call 2 took ${T19}s (budget reset?)"
[ "$(state_count "$D18")" = 0 ] && ok "terminal outcome removed the state file" || no "state left after ELAPSED"
OUT19B="$(wfc "$D18" "$SUT" "$PR" --sha "$SHA" --bound 4 --call-max 2 --interval 1 --required-only --continue)"
case "$OUT19B" in *"pending=unreadable_deadline") ok "--continue after a terminal outcome fails closed" ;; *) no "post-terminal --continue: '$OUT19B'" ;; esac

echo "== 20. a continuation whose required check settles green prints SETTLED required=green =="
D20="$(fresh_stub_dir)"
cat > "$D20/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *baseRefName*) printf '{"baseRefName":"main"}\n'; exit 0 ;;
  *headRefOid*)
    [ -f "$D20/count" ] || echo 0 > "$D20/count"
    n=\$(cat "$D20/count"); n=\$((n+1)); echo "\$n" > "$D20/count"
    if [ "\$n" -lt 4 ]; then st=IN_PROGRESS; c=""; else st=COMPLETED; c=SUCCESS; fi
    printf '{"headRefOid":"$SHA","statusCheckRollup":[{"name":"ci","status":"%s","conclusion":"%s","state":""}]}\n' "\$st" "\$c"
    exit 0 ;;
esac
[ "\$1" = "api" ] && printf '{"required_status_checks":{"contexts":["ci"]}}\n'
exit 0
EOF
chmod +x "$D20/gh"
OUT20A="$(wfc "$D20" "$SUT" "$PR" --sha "$SHA" --bound 30 --call-max 1 --interval 1 --required-only)"
OUT20B="$(wfc "$D20" "$SUT" "$PR" --sha "$SHA" --bound 30 --call-max 1 --interval 1 --required-only --continue)"
while case "$OUT20B" in CONTINUE*) true ;; *) false ;; esac; do
  OUT20B="$(wfc "$D20" "$SUT" "$PR" --sha "$SHA" --bound 30 --call-max 1 --interval 1 --required-only --continue)"
done
case "$OUT20A|$OUT20B" in
  "CONTINUE sha=$SHA remaining="*"|SETTLED sha=$SHA required=green review_producing=settled") ok "CONTINUE then SETTLED green ($OUT20B)" ;;
  *) no "continuation settle: '$OUT20A' / '$OUT20B'" ;;
esac

echo "== 21. a NEW sha is a NEW key: fresh deadline, the old sha's deadline untouched =="
D21="$(fresh_stub_dir)"; write_never_settles_stub "$D21"
wfc "$D21" "$SUT" "$PR" --sha "$SHA" --bound 4 --call-max 1 --interval 1 --required-only >/dev/null
OUT21C="$(wfc "$D21" "$SUT" "$PR" --sha "cafef00d11" --bound 4 --call-max 1 --interval 1 --required-only --continue)"
case "$OUT21C" in *"pending=unreadable_deadline") ok "--continue on a never-started sha has no deadline (keyed on sha)" ;; *) no "new-sha --continue: '$OUT21C'" ;; esac
OUT21="$(wfc "$D21" "$SUT" "$PR" --sha "cafef00d11" --bound 100 --call-max 1 --interval 1 --required-only)"
R21="${OUT21#CONTINUE sha=cafef00d11 remaining=}"; R21="${R21%% *}"
case "$OUT21" in
  "CONTINUE sha=cafef00d11 remaining="*" pending=sha_mismatch")
    if [ "$R21" -ge 90 ] 2>/dev/null; then ok "new sha got a fresh full budget ($OUT21)"; else no "new sha budget not fresh: '$OUT21'"; fi ;;
  *) no "new sha fresh deadline: '$OUT21'" ;;
esac
[ "$(state_count "$D21")" = 2 ] && ok "two shas ⇒ two independent deadlines" || no "state files: $(state_count "$D21")"

echo "== 22. unreadable state on continuation ⇒ ELAPSED pending=unreadable_deadline, never a fresh budget =="
D22="$(fresh_stub_dir)"; write_never_settles_stub "$D22"
wfc "$D22" "$SUT" "$PR" --sha "$SHA" --bound 60 --call-max 1 --interval 1 --required-only >/dev/null
for f in $(find "$D22/.supervisor/check-wait" -name '*.json'); do printf 'garbage{' > "$f"; done
T0=$SECONDS
OUT22="$(wfc "$D22" "$SUT" "$PR" --sha "$SHA" --bound 60 --call-max 1 --interval 1 --required-only --continue)"
case "$OUT22" in
  "ELAPSED sha=$SHA required=pending review_producing=elapsed pending=unreadable_deadline") ok "garbage state fails closed ($OUT22)" ;;
  *) no "garbage state: '$OUT22'" ;;
esac
[ $((SECONDS - T0)) -le 2 ] && ok "fail-closed without waiting" || no "garbage-state call waited"
OUT22B="$(wfc "$D22" "$SUT" "$PR" --sha "$SHA" --bound 60 --call-max abc --interval 1 --required-only)"
case "$OUT22B" in *"pending=bad_usage") ok "non-numeric --call-max ⇒ bad_usage" ;; *) no "bad --call-max: '$OUT22B'" ;; esac

echo "== 23. MUTATION CONTROL: a copy that re-writes the deadline on every call fails case 19 =="
M23="$D18/mut-reset.sh"
# Both reads are disabled: the --continue read AND the keep-unexpired read a first call does.
sed -e 's/^  if \[ "\$CONTINUE" -eq 1 \]; then$/  if false; then/' \
    -e 's/^    if \[ "\$RESTART" -eq 0 \]; then$/    if false; then/' "$SUT" > "$M23"
if [ -s "$M23" ] && ! cmp -s "$SUT" "$M23" && bash -n "$M23"; then
  wfc "$D18" "$M23" "$PR" --sha "$SHA" --bound 4 --call-max 2 --interval 1 --required-only >/dev/null
  OUT23="$(wfc "$D18" "$M23" "$PR" --sha "$SHA" --bound 4 --call-max 2 --interval 1 --required-only --continue)"
  case "$OUT23" in ELAPSED*) no "mutation control did NOT discriminate: '$OUT23'" ;;
    *) ok "mutation control: a reset deadline makes call 2 CONTINUE instead of ELAPSE ($OUT23)" ;; esac
else
  no "case 23 mutant invalid (empty / identical / bash -n)"
fi

echo "== 25. a first call that finds an UNEXPIRED deadline keeps it (a dropped --continue) and warns =="
# Call 1: --bound 3 --call-max 1 ⇒ CONTINUE with ~2 s left. Call 2 DROPS --continue and asks for
# --bound 100: keeping the persisted deadline ELAPSES within ~2 s; a fresh budget would CONTINUE at
# call-max 5 with ~95 s left — the unbounded-wait signature.
D25="$(fresh_stub_dir)"; write_never_settles_stub "$D25"
wfc "$D25" "$SUT" "$PR" --sha "$SHA" --bound 3 --call-max 1 --interval 1 --required-only >/dev/null
ERR25="$( (cd "$D25" && GH="$D25/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 100 --call-max 5 --interval 1 --required-only > "$D25/out25") 2>&1 )"
OUT25="$(cat "$D25/out25" 2>/dev/null)"
case "$OUT25" in
  "ELAPSED sha=$SHA required=pending review_producing=settled pending=none") ok "dropped --continue ELAPSES on the kept deadline ($OUT25)" ;;
  *) no "dropped --continue should ELAPSE on the kept deadline, got: '$OUT25'" ;;
esac
case "$ERR25" in *"unexpired deadline for this (pr, sha, scope) is in flight — keeping it"*) ok "dropped --continue: stderr names the kept deadline" ;; *) no "no keep warning on stderr: '$ERR25'" ;; esac
[ "$(state_count "$D25")" = 0 ] && ok "the kept deadline elapsed ⇒ state removed" || no "state left: $(state_count "$D25")"

echo "== 26. --restart replaces an unexpired deadline; an EXPIRED one is replaced without it =="
D26="$(fresh_stub_dir)"; write_never_settles_stub "$D26"
wfc "$D26" "$SUT" "$PR" --sha "$SHA" --bound 4 --call-max 1 --interval 1 --required-only >/dev/null
OUT26="$(wfc "$D26" "$SUT" "$PR" --sha "$SHA" --bound 100 --call-max 1 --interval 1 --required-only --restart)"
R26="${OUT26#CONTINUE sha=$SHA remaining=}"; R26="${R26%% *}"
case "$OUT26" in
  "CONTINUE sha=$SHA remaining="*) if [ "$R26" -ge 90 ] 2>/dev/null; then ok "--restart got a fresh full budget ($OUT26)"; else no "--restart budget not fresh: '$OUT26'"; fi ;;
  *) no "--restart: '$OUT26'" ;;
esac
for f in $(find "$D26/.supervisor/check-wait" -name '*.json'); do printf '{"deadline":1,"sha":"%s","scope":"required"}\n' "$SHA" > "$f"; done
OUT26B="$(wfc "$D26" "$SUT" "$PR" --sha "$SHA" --bound 100 --call-max 1 --interval 1 --required-only)"
R26B="${OUT26B#CONTINUE sha=$SHA remaining=}"; R26B="${R26B%% *}"
case "$OUT26B" in
  "CONTINUE sha=$SHA remaining="*) if [ "$R26B" -ge 90 ] 2>/dev/null; then ok "an expired deadline is replaced by a fresh one ($OUT26B)"; else no "expired deadline not replaced: '$OUT26B'"; fi ;;
  *) no "expired deadline: '$OUT26B'" ;;
esac
OUT26C="$(wfc "$D26" "$SUT" "$PR" --sha "$SHA" --bound 4 --call-max 1 --interval 1 --required-only --continue --restart)"
R26C="${OUT26C#CONTINUE sha=$SHA remaining=}"; R26C="${R26C%% *}"
case "$OUT26C" in
  "CONTINUE sha=$SHA remaining="*) if [ "$R26C" -ge 80 ] 2>/dev/null; then ok "--restart is ignored with --continue (deadline read, never rewritten: $OUT26C)"; else no "--continue --restart rewrote the deadline: '$OUT26C'"; fi ;;
  *) no "--continue --restart: '$OUT26C'" ;;
esac

echo "== 27. MUTATION CONTROL: a copy without the keep-unexpired read hands a dropped --continue a fresh budget =="
M27="$D25/mut-nokeep.sh"
sed -e 's/^    if \[ "\$RESTART" -eq 0 \]; then$/    if false; then/' "$SUT" > "$M27"
if [ -s "$M27" ] && ! cmp -s "$SUT" "$M27" && bash -n "$M27"; then
  wfc "$D25" "$M27" "$PR" --sha "$SHA" --bound 3 --call-max 1 --interval 1 --required-only >/dev/null
  OUT27="$(wfc "$D25" "$M27" "$PR" --sha "$SHA" --bound 100 --call-max 5 --interval 1 --required-only)"
  case "$OUT27" in ELAPSED*) no "mutation control did NOT discriminate: '$OUT27'" ;;
    *) ok "mutation control: without the keep read the second first-call CONTINUEs on a fresh budget ($OUT27)" ;; esac
else
  no "case 27 mutant invalid (empty / identical / bash -n)"
fi

echo "== 24. no state leaked into this test's cwd =="
if [ "$LEAK_BEFORE" -eq 1 ] || [ ! -d .supervisor/check-wait ]; then ok "cwd has no new .supervisor/check-wait"; else no "state LEAKED into $(pwd)/.supervisor/check-wait"; fi
rm -rf "$D18" "$D20" "$D21" "$D22" "$D25" "$D26"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
