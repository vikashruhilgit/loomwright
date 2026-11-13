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
#  28. (external review) a quote/backslash in the review pattern keeps the
#      state file valid JSON and --continue resumable; printf-built mutant.
#  29. (V5) producer -> shared reader (wait-for-checks-line.sh) round trip:
#      spaced check names (`test (18.x)`, `build (ubuntu-latest)`) survive in
#      pending= / pending_names= / red_names=; first-occurrence scalars; the
#      shared word-split mutant (fixtures/wait-for-checks-line/wsplit.sed).
#  30-32. (configurable base) the PR's baseRefName stays FIRST (a repo config
#      naming another base is not consulted); with no baseRefName the base comes
#      from resolve-base-branch.sh (the cwd repo's .supervisor/config.json);
#      with neither, protection is never read and required=unknown — never a
#      `main` guess, never a vacuous green.
#  41. zero-padded --bound 08 / --call-max 08 read as decimal: the resumable
#      path (CONTINUE + one persisted deadline), no `value too great for base`;
#      mutation control (normalisation removed).
#  42. the poll sleep is cut to the remaining --call-max budget: --call-max 1
#      --interval 8 prints CONTINUE within 4 s; mutation control (clamp removed).
#  49-59. (drain-named-required-checks) --named-required <json>: stands in only
#      where the protection read yields no list (paid-plan, unreadable, 404 with
#      no ruleset check); a readable read (200 — even an empty list, or with an
#      unreadable ruleset read — or a 404 + ruleset list) wins; an absent named
#      check is pending; a malformed value (a blank name included) is ignored.

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
case "\$*" in *"/rules/branches/"*) echo '[]'; exit 0 ;; esac
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
case "\$*" in *"/rules/branches/"*) echo '[]'; exit 0 ;; esac
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
case "\$*" in *"/rules/branches/"*) echo '[]'; exit 0 ;; esac
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
case "\$*" in *"/rules/branches/"*) echo '[]'; exit 0 ;; esac
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
case "\$*" in *"/rules/branches/"*) echo '[]'; exit 0 ;; esac
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
case "\$*" in *"/rules/branches/"*) echo '[]'; exit 0 ;; esac
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
# Markers in <dir>: prot-404 (classic protection 404s), rulesets.json (the rules/branches
# body, default `[]`), rulesets-fail (the rules read 403s).
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
case "\$*" in *"/rules/branches/"*)
  [ -f "$dir/rulesets-fail" ] && { echo 'gh: Resource not accessible by integration (HTTP 403)' >&2; exit 1; }
  if [ -f "$dir/rulesets.json" ]; then cat "$dir/rulesets.json"; else echo '[]'; fi; exit 0 ;;
esac
[ "\$1" = "api" ] && [ -f "$dir/prot-404" ] && { echo 'gh: Branch not protected (HTTP 404)' >&2; exit 1; }
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
case "\$*" in *"/rules/branches/"*) echo '[]'; exit 0 ;; esac
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
case "\$*" in *"/rules/branches/"*) echo '[]'; exit 0 ;; esac
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

echo "== 28. a quote / backslash in the review pattern keeps the state readable (jq-built, never printf) =="
# The pattern and --sha are free text: a printf-built state file broke JSON on `"` or `\`, so every
# --continue failed closed (unreadable_deadline) and the TOTAL budget shrank to one call.
D28="$(fresh_stub_dir)"; write_never_settles_stub "$D28"
P28='cl"aude\rev*'
# st28 <script> — first call then --continue with the hostile pattern; prints the continue line.
st28() {
  rm -rf "$D28/.supervisor"
  wfc "$D28" "$1" "$PR" --sha "$SHA" --bound 60 --call-max 1 --interval 1 --review-check-pattern "$P28" >/dev/null
  wfc "$D28" "$1" "$PR" --sha "$SHA" --bound 60 --call-max 1 --interval 1 --review-check-pattern "$P28" --continue
}
OUT28="$(st28 "$SUT")"
SF28="$(find "$D28/.supervisor/check-wait" -name '*.json' 2>/dev/null | head -n 1)"
[ -n "$SF28" ] && [ "$(jq -r '.scope' "$SF28" 2>/dev/null)" = "review:$P28" ] && ok "the state file is valid JSON and round-trips the pattern" || no "state file unreadable: $(cat "$SF28" 2>/dev/null)"
case "$OUT28" in "CONTINUE sha=$SHA remaining="*) ok "--continue resumes the persisted deadline ($OUT28)" ;; *) no "hostile pattern --continue: '$OUT28'" ;; esac
M28="$D28/mut-printf.sh"   # MUTATION CONTROL: the printf-built state file (the pre-fix line)
python3 - "$SUT" "$M28" <<'PYEOF'
import re, sys
s = open(sys.argv[1]).read()
s = re.sub(r'"\$JQ_BIN" -nc --argjson d "\$DEADLINE" --arg sha "\$SHA" --arg scope "\$_scope" \\\n\s*\'\{deadline: \$d, sha: \$sha, scope: \$scope\}\'',
           "printf '{\"deadline\":%s,\"sha\":\"%s\",\"scope\":\"%s\"}\\n' \"$DEADLINE\" \"$SHA\" \"$_scope\"", s, count=1)
open(sys.argv[2], "w").write(s)
PYEOF
if [ -s "$M28" ] && ! cmp -s "$SUT" "$M28" && bash -n "$M28"; then
  case "$(st28 "$M28")" in *"pending=unreadable_deadline") ok "mutation control: the printf-built state fails the hostile-pattern --continue closed" ;;
    *) no "case 28 mutation control did NOT discriminate" ;; esac
else no "case 28 mutant invalid (empty / identical / bash -n)"; fi

echo "== 29. (V5) producer -> shared reader round trip: spaced check names survive wait-for-checks-line.sh =="
# The reader every consumer uses (escalation.sh, drain-subfloor-decision.sh) parses the line THIS
# script prints. Matrix-style names carry spaces; a word-splitting reader keeps the first word only.
LIB29="$HERE/wait-for-checks-line.sh"
# rt29 <reader> <line> — the parsed fields, `|`-joined, from a subshell that sources <reader>.
rt29() {
  ( . "$1" && wfc_line_parse "$2" \
    && printf '%s|%s|%s|%s|%s|%s|%s|%s' "$WFC_KIND" "$WFC_SHA" "$WFC_REQUIRED" "$WFC_PENDING" \
         "$WFC_PENDING_NAMES" "$WFC_RED_NAMES" "$WFC_HAVE_PENDING_NAMES" "$WFC_HAVE_RED_NAMES" )
}
D29="$(fresh_stub_dir)"
write_names_stub "$D29" '{"headRefOid":"deadbeef00","statusCheckRollup":[{"name":"test (18.x)","status":"IN_PROGRESS","conclusion":"","state":""},{"name":"claude review (pr)","status":"IN_PROGRESS","conclusion":"","state":""},{"name":"lint","status":"COMPLETED","conclusion":"SUCCESS"}]}' '["test (18.x)","lint"]'
OUT29P="$(GH="$D29/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 0 --interval 1 --names)"
WANT29P="ELAPSED sha=deadbeef00 required=pending review_producing=elapsed pending=claude review (pr) pending_names=test (18.x),claude review (pr) red_names=none"
[ "$OUT29P" = "$WANT29P" ] && ok "29a producer prints spaced pending names verbatim ($OUT29P)" || no "29a producer line: '$OUT29P'"
GOT29P="$(rt29 "$LIB29" "$OUT29P")"
[ "$GOT29P" = "ELAPSED|deadbeef00|pending|claude review (pr)|test (18.x),claude review (pr)|none|1|1" ] \
  && ok "29a reader keeps whole spaced names in pending= and pending_names= ($GOT29P)" || no "29a reader: '$GOT29P'"
write_names_stub "$D29" '{"headRefOid":"deadbeef00","statusCheckRollup":[{"name":"build (ubuntu-latest)","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://github.com/acme/widgets/actions/runs/99/job/1"},{"name":"test (18.x)","status":"COMPLETED","conclusion":"FAILURE"}]}' '["build (ubuntu-latest)","test (18.x)"]'
OUT29R="$(GH="$D29/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 0 --interval 1 --names)"
[ "$OUT29R" = "SETTLED sha=deadbeef00 required=red review_producing=settled pending_names=none red_names=build (ubuntu-latest)@99,test (18.x)@-" ] \
  && ok "29b producer prints spaced red names verbatim ($OUT29R)" || no "29b producer line: '$OUT29R'"
GOT29R="$(rt29 "$LIB29" "$OUT29R")"
[ "$GOT29R" = "SETTLED|deadbeef00|red||none|build (ubuntu-latest)@99,test (18.x)@-|1|1" ] \
  && ok "29b reader keeps whole spaced names in red_names= ($GOT29R)" || no "29b reader: '$GOT29R'"
GOT29S="$(rt29 "$LIB29" "  SETTLED sha=deadbeef00 required=green review_producing=settled pending_names=odd required=red sha=0bad red_names=none  ")"
[ "$GOT29S" = "SETTLED|deadbeef00|green||odd required=red sha=0bad|none|1|1" ] \
  && ok "29c scalars come from their FIRST occurrence; surrounding whitespace dropped ($GOT29S)" || no "29c reader: '$GOT29S'"
GOT29N="$(rt29 "$LIB29" "SETTLED sha=deadbeef00 required=green review_producing=settled")"
[ "$GOT29N" = "SETTLED|deadbeef00|green||||0|0" ] && ok "29d a line without --names fields reports both absent ($GOT29N)" || no "29d reader: '$GOT29N'"
# MUTATION CONTROL (shared with the consumers' suites): the reader reverted to word-splitting.
M29="$D29/wait-for-checks-line.sh"
sed -f "$HERE/fixtures/wait-for-checks-line/wsplit.sed" "$LIB29" > "$M29"
if [ -s "$M29" ] && ! cmp -s "$LIB29" "$M29" && bash -n "$M29"; then
  MG29P="$(rt29 "$M29" "$OUT29P")"; MG29R="$(rt29 "$M29" "$OUT29R")"
  if [ "$MG29P" != "$GOT29P" ] && [ "$MG29R" != "$GOT29R" ]; then
    ok "mutation control: a word-splitting reader cuts the spaced names (pending: $MG29P | red: $MG29R)"
  else
    no "case 29 mutation control did NOT discriminate (pending: $MG29P | red: $MG29R)"
  fi
else no "case 29 mutant invalid (empty / identical / bash -n)"; fi
rm -rf "$D29"

# ----------------------------------------------------------------------------
# Cases 30-32 (configurable base): baseRefName first, the resolver the fallback.
# The stub logs every `gh api` path; each case runs in its own scratch repo
# (no origin, so the resolver's origin-head step finds nothing) with a PATH
# whose `gh` fails, so the resolver's gh step cannot reach the network.
# ----------------------------------------------------------------------------
write_base_stub() { # <dir> <baseRefName json or "">
  local dir="$1" base="$2"
  cat > "$dir/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *baseRefName*) [ -n '$base' ] && printf '%s\n' '$base'; exit 0 ;;
  *headRefOid*) printf '{"headRefOid":"$SHA","statusCheckRollup":[]}\n'; exit 0 ;;
esac
case "\$*" in *"/rules/branches/"*) echo '[]'; exit 0 ;; esac
if [ "\$1" = "api" ]; then printf '%s\n' "\$2" >> "$dir/api.log"; echo "gh: Branch not protected (HTTP 404)" >&2; exit 1; fi
exit 0
EOF
  chmod +x "$dir/gh"
  mkdir -p "$dir/bin" "$dir/repo"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$dir/bin/gh"; chmod +x "$dir/bin/gh"
  git -C "$dir/repo" init -q >/dev/null 2>&1
}
run_base_case() { # <dir> — the SUT in the scratch repo; sets OUTB RCB
  OUTB="$(cd "$1/repo" && PATH="$1/bin:$PATH" GH="$1/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 10 --interval 1 --required-only 2>/dev/null)"
  RCB=$?
}

echo "== 30. the PR's baseRefName wins over the repo's configured base =="
D30="$(fresh_stub_dir)"
write_base_stub "$D30" '{"baseRefName":"development"}'
mkdir -p "$D30/repo/.supervisor"; printf '{"base_branch":"release"}\n' > "$D30/repo/.supervisor/config.json"
run_base_case "$D30"
if [ "$RCB" -eq 0 ] && [ "$(cat "$D30/api.log" 2>/dev/null)" = "repos/acme/widgets/branches/development/protection" ]; then
  ok "baseRefName first: protection read for development, not the configured release ($OUTB)"
else
  no "baseRefName precedence wrong (rc=$RCB api='$(cat "$D30/api.log" 2>/dev/null)' out='$OUTB')"
fi
rm -rf "$D30"

echo "== 31. no baseRefName => the base from resolve-base-branch.sh (repo config) =="
D31="$(fresh_stub_dir)"
write_base_stub "$D31" ''
mkdir -p "$D31/repo/.supervisor"; printf '{"base_branch":"release"}\n' > "$D31/repo/.supervisor/config.json"
run_base_case "$D31"
if [ "$RCB" -eq 0 ] && [ "$(cat "$D31/api.log" 2>/dev/null)" = "repos/acme/widgets/branches/release/protection" ] \
   && grep -qE '^SETTLED sha=deadbeef00 required=green' < <(printf '%s' "$OUTB"); then
  ok "fallback: protection read for the resolved base release ($OUTB)"
else
  no "resolver fallback wrong (rc=$RCB api='$(cat "$D31/api.log" 2>/dev/null)' out='$OUTB')"
fi
rm -rf "$D31"

echo "== 32. no baseRefName and an unresolvable base => required=unknown, protection never read, no main guess =="
D32="$(fresh_stub_dir)"
write_base_stub "$D32" ''
run_base_case "$D32"
if [ "$RCB" -eq 0 ] && [ ! -s "$D32/api.log" ] && grep -qE '^SETTLED sha=deadbeef00 required=unknown' < <(printf '%s' "$OUTB"); then
  ok "unresolved base: required=unknown, no protection read ($OUTB)"
else
  no "unresolved base wrong (rc=$RCB api='$(cat "$D32/api.log" 2>/dev/null)' out='$OUTB') -- must not read main's protection or claim green"
fi
rm -rf "$D32"

# ----------------------------------------------------------------------------
# GitHub's paid-plan refusal (a private repo on GitHub Free): no required list can
# exist, so every non-neutral check in the rollup counts as required. The stub's
# body and error line are the text a real `gh api` prints on such a repo.
# ----------------------------------------------------------------------------
PAID_BODY='{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","documentation_url":"https://docs.github.com/rest/branches/branch-protection#get-branch-protection","status":"403"}'
PAID_ERR='gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)'
# write_refusal_stub <dir> <protection stdout> <protection stderr> <rollup json>... — each poll serves the
# next rollup and the last one repeats; the protection read exits 1.
write_refusal_stub() {
  local dir="$1" body="$2" err="$3" i=0 r; shift 3
  for r in "$@"; do i=$((i + 1)); printf '%s\n' "$r" > "$dir/rollup.$i"; done
  printf '%s\n' "$body" > "$dir/prot.out"; printf '%s\n' "$err" > "$dir/prot.err"
  cat > "$dir/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *baseRefName*) printf '{"baseRefName":"main"}\n'; exit 0 ;;
  *headRefOid*)
    n=\$(( \$(cat "$dir/count" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$dir/count"
    [ "\$n" -le $i ] || n=$i
    printf '{"headRefOid":"$SHA","statusCheckRollup":%s}\n' "\$(cat "$dir/rollup.\$n")"
    exit 0 ;;
esac
cat "$dir/prot.out"; cat "$dir/prot.err" >&2; exit 1
EOF
  chmod +x "$dir/gh"
}
CI_RED='[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE","state":"","detailsUrl":"https://github.com/acme/widgets/actions/runs/77/job/1"}]'
CI_GREEN='[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS","state":""},{"name":"lint","status":"COMPLETED","conclusion":"SKIPPED","state":""}]'
CI_RUNNING='[{"name":"ci","status":"IN_PROGRESS","conclusion":"","state":""}]'

echo "== 33. paid-plan 403, a green rollup => required=green, under --required-only =="
D33="$(fresh_stub_dir)"
write_refusal_stub "$D33" "$PAID_BODY" "$PAID_ERR" "$CI_GREEN"
OUTP="$(WFC_NO_LIST_GRACE=0 GH="$D33/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 10 --interval 1 --required-only)"
if grep -qE '^SETTLED sha=deadbeef00 required=green' < <(printf '%s' "$OUTP"); then
  ok "paid-plan 403 is not unknown: green CI reads green ($OUTP)"
else
  no "paid-plan 403 green rollup wrong (out='$OUTP')"
fi
rm -rf "$D33"

echo "== 34. paid-plan 403, a failing check that nothing lists as required => required=red, named =="
D34="$(fresh_stub_dir)"
write_refusal_stub "$D34" "$PAID_BODY" "$PAID_ERR" "$CI_RED"
OUTP="$(WFC_NO_LIST_GRACE=0 GH="$D34/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 10 --interval 1 --required-only --names)"
if grep -qE '^SETTLED sha=deadbeef00 required=red .*red_names=ci@77$' < <(printf '%s' "$OUTP"); then
  ok "paid-plan 403 never hides a failing check: required=red ($OUTP)"
else
  no "paid-plan 403 red rollup wrong (out='$OUTP') -- a vacuous green here would let red CI reach the gate"
fi
rm -rf "$D34"

echo "== 35. paid-plan 403, a running check => the wait stays open and ELAPSED names it =="
D35="$(fresh_stub_dir)"
write_refusal_stub "$D35" "$PAID_BODY" "$PAID_ERR" "$CI_RUNNING"
OUTP="$(GH="$D35/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 1 --interval 1 --required-only --names)"
if grep -qE '^ELAPSED sha=deadbeef00 required=pending .*pending_names=ci ' < <(printf '%s' "$OUTP"); then
  ok "paid-plan 403 waits on every check ($OUTP)"
else
  no "paid-plan 403 running check wrong (out='$OUTP')"
fi
rm -rf "$D35"

echo "== 36. paid-plan 403, an empty rollup just after a push => held through the grace, then the real result =="
D36="$(fresh_stub_dir)"
write_refusal_stub "$D36" "$PAID_BODY" "$PAID_ERR" '[]' "$CI_RED"
OUTP="$(WFC_NO_LIST_GRACE=8 GH="$D36/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 20 --interval 1 --required-only)"
if grep -qE '^SETTLED sha=deadbeef00 required=red' < <(printf '%s' "$OUTP"); then
  ok "not-yet-queued checks are not read as green ($OUTP)"
else
  no "paid-plan 403 late-materializing rollup wrong (out='$OUTP') -- checks not queued yet were read as settled"
fi
rm -rf "$D36"

echo "== 36b. paid-plan 403, one green check first and a red one queued later => held through the grace, reads red =="
D36B="$(fresh_stub_dir)"
CI_LATE='[{"name":"lint","status":"COMPLETED","conclusion":"SUCCESS","state":""},{"name":"ci","status":"COMPLETED","conclusion":"FAILURE","state":""}]'
write_refusal_stub "$D36B" "$PAID_BODY" "$PAID_ERR" '[{"name":"lint","status":"COMPLETED","conclusion":"SUCCESS","state":""}]' "$CI_LATE"
OUTP="$(WFC_NO_LIST_GRACE=8 GH="$D36B/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 20 --interval 1 --required-only)"
if grep -qE '^SETTLED sha=deadbeef00 required=red' < <(printf '%s' "$OUTP"); then
  ok "a partly queued rollup is not read as green ($OUTP)"
else
  no "paid-plan 403 partly queued rollup wrong (out='$OUTP') -- a green check first hid the red one"
fi
rm -rf "$D36B"

echo "== 37. paid-plan 403, a rollup that stays empty (no CI) => settles green after the grace, never elapses =="
D37="$(fresh_stub_dir)"
write_refusal_stub "$D37" "$PAID_BODY" "$PAID_ERR" '[]'
OUTP="$(WFC_NO_LIST_GRACE=6 GH="$D37/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 20 --interval 1 --required-only)"
POLLS="$(cat "$D37/count" 2>/dev/null)"
if grep -qE '^SETTLED sha=deadbeef00 required=green' < <(printf '%s' "$OUTP") && [ "${POLLS:-0}" -ge 2 ]; then
  ok "no CI settles after the grace ($POLLS polls, $OUTP)"
else
  no "paid-plan 403 empty rollup wrong (polls=$POLLS out='$OUTP')"
fi
rm -rf "$D37"

echo "== 38. paid-plan 403, --bound 0 (a one-shot read) => no grace wait =="
D38="$(fresh_stub_dir)"
write_refusal_stub "$D38" "$PAID_BODY" "$PAID_ERR" '[]'
OUTP="$(GH="$D38/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 0 --interval 1 --required-only)"
if grep -qE '^SETTLED sha=deadbeef00 required=green' < <(printf '%s' "$OUTP") && [ "$(cat "$D38/count")" = 1 ]; then
  ok "one-shot read returns at once ($OUTP)"
else
  no "paid-plan 403 --bound 0 wrong (polls=$(cat "$D38/count") out='$OUTP')"
fi
rm -rf "$D38"

echo "== 38b. paid-plan 403 under --call-max shorter than the grace => the grace runs once across calls =="
D38B="$(fresh_stub_dir)"
write_refusal_stub "$D38B" "$PAID_BODY" "$PAID_ERR" "$CI_GREEN"
OUTP="$(CHECK_WAIT_DIR="$D38B/state" WFC_NO_LIST_GRACE=3 GH="$D38B/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 60 --interval 1 --required-only --call-max 1)"
CALLS=1
while [ "${OUTP%% *}" = CONTINUE ] && [ "$CALLS" -lt 8 ]; do
  OUTP="$(CHECK_WAIT_DIR="$D38B/state" WFC_NO_LIST_GRACE=3 GH="$D38B/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 60 --interval 1 --required-only --call-max 1 --continue)"
  CALLS=$((CALLS + 1))
done
if grep -qE '^SETTLED sha=deadbeef00 required=green' < <(printf '%s' "$OUTP"); then
  ok "the grace is not restarted by --continue ($CALLS calls, $OUTP)"
else
  no "paid-plan 403 resumable grace wrong (calls=$CALLS out='$OUTP') -- each --continue restarted the grace"
fi
rm -rf "$D38B"

echo "== 39. other refusals stay required=unknown, even with green checks =="
for pair in \
  '{"message":"Resource not accessible by integration","status":"403"}|gh: Resource not accessible by integration (HTTP 403)|token-scope 403' \
  '{"message":"Must have admin rights to Repository.","status":"403"}|gh: Must have admin rights to Repository. (HTTP 403)|permissions 403' \
  '{"message":"Upgrade to GitHub Pro","status":"500"}|gh: Upgrade to GitHub Pro (HTTP 500)|5xx quoting the upgrade text' \
  '{"message":"Server Error","status":"502"}|gh: Server Error (HTTP 502)|5xx'; do
  body="${pair%%|*}"; rest="${pair#*|}"; err="${rest%%|*}"; label="${rest#*|}"
  D39="$(fresh_stub_dir)"
  write_refusal_stub "$D39" "$body" "$err" "$CI_GREEN"
  OUTP="$(GH="$D39/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 10 --interval 1 --required-only)"
  if grep -qE '^SETTLED sha=deadbeef00 required=unknown' < <(printf '%s' "$OUTP"); then
    ok "$label: required=unknown ($OUTP)"
  else
    no "$label wrong (out='$OUTP') -- only the paid-plan refusal may leave unknown"
  fi
  rm -rf "$D39"
done

echo "== 40. the library missing beside the script => the refusal reads unknown (fail closed) =="
D40="$(fresh_stub_dir)"
write_refusal_stub "$D40" "$PAID_BODY" "$PAID_ERR" "$CI_GREEN"
mkdir "$D40/lib"; cp "$SUT" "$D40/lib/wait-for-checks.sh"
OUTP="$(GH="$D40/gh" bash "$D40/lib/wait-for-checks.sh" "$PR" --sha "$SHA" --bound 10 --interval 1 --required-only)"
if grep -qE '^SETTLED sha=deadbeef00 required=unknown' < <(printf '%s' "$OUTP"); then
  ok "no library: required=unknown ($OUTP)"
else
  no "missing library wrong (out='$OUTP')"
fi
rm -rf "$D40"

# 41-42. Zero-padded numbers and the per-call ceiling. `$((… + BOUND))` read `08` as a bad octal
# literal; the error aborted the deadline block, so `--bound 08 --call-max 1` ran the non-resumable
# path for the whole bound (no CONTINUE, no state file). And the ceiling was checked only BEFORE the
# poll sleep, so a call could overshoot --call-max by up to one --interval.
# wfc_err <dir> <script> <args...> — wfc with stderr kept in <dir>/err.
wfc_err() { local d="$1" s="$2"; shift 2; ( cd "$d" && GH="$d/gh" bash "$s" "$@" 2>"$d/err" ); }
octal_ok() {   # octal_ok SUT — exit 0 iff (41) holds; WHY41 says which part failed
  local s="$1" d out
  WHY41=""
  d="$(fresh_stub_dir)"; write_never_settles_stub "$d"
  out="$(wfc_err "$d" "$s" "$PR" --sha "$SHA" --bound 08 --call-max 1 --interval 1 --required-only)"
  case "$out" in "CONTINUE sha=$SHA remaining="[5678]" pending=none") ;; *) WHY41="--bound 08: '$out' (want CONTINUE)" ;; esac
  grep -q 'value too great' "$d/err" && WHY41="$WHY41 --bound 08 stderr: $(head -1 "$d/err")"
  [ "$(state_count "$d")" = 1 ] || WHY41="$WHY41 --bound 08 state files: $(state_count "$d")"
  rm -rf "$d"
  d="$(fresh_stub_dir)"; write_pending_then_settle_stub "$d" "SUCCESS"
  out="$(wfc_err "$d" "$s" "$PR" --sha "$SHA" --bound 09 --call-max 08 --interval 1 --required-only)"
  case "$out" in "SETTLED sha=$SHA required=green"*) ;; *) WHY41="$WHY41 --call-max 08: '$out' (want SETTLED green)" ;; esac
  grep -q 'value too great' "$d/err" && WHY41="$WHY41 --call-max 08 stderr: $(head -1 "$d/err")"
  rm -rf "$d"
  [ -z "$WHY41" ]
}
ceiling_ok() {   # ceiling_ok SUT — exit 0 iff (42) holds; WHY42 says why not
  local s="$1" d out t0 t
  d="$(fresh_stub_dir)"; write_never_settles_stub "$d"
  t0=$SECONDS
  out="$(wfc_err "$d" "$s" "$PR" --sha "$SHA" --bound 60 --call-max 1 --interval 8 --required-only)"
  t=$((SECONDS - t0))
  rm -rf "$d"
  WHY42="out='$out' in ${t}s"
  case "$out" in "CONTINUE sha=$SHA remaining="*" pending=none") [ "$t" -le 4 ] ;; *) false ;; esac
}
echo "== 41. --bound 08 / --call-max 08 are decimal: resumable CONTINUE + state, no octal error =="
if octal_ok "$SUT"; then ok "--bound 08 --call-max 1 prints CONTINUE with one persisted deadline; --call-max 08 settles; no 'value too great'"
else no "zero-padded numbers: $WHY41"; fi
M41="$(fresh_stub_dir)/mut-octal.sh"
grep -v '# BOUNDDEC$' "$SUT" > "$M41"
if [ -s "$M41" ] && ! cmp -s "$SUT" "$M41" && bash -n "$M41"; then
  if octal_ok "$M41"; then no "case 41 MUTATION CONTROL: without the --bound normalisation case 41 still passed — it proves nothing"
  else ok "case 41 MUTATION CONTROL: without the --bound normalisation case 41 fails ($WHY41)"; fi
else no "case 41 mutant invalid (empty / identical / bash -n)"; fi
rm -rf "$(dirname "$M41")"
echo "== 42. --call-max 1 --interval 8: the poll sleep ends at the per-call ceiling, not 8 s later =="
if ceiling_ok "$SUT"; then ok "the last sleep is cut to the remaining --call-max budget ($WHY42)"
else no "per-call ceiling overshoot: $WHY42"; fi
M42="$(fresh_stub_dir)/mut-ceil.sh"
grep -v '# CEILCAP$' "$SUT" > "$M42"
if [ -s "$M42" ] && ! cmp -s "$SUT" "$M42" && bash -n "$M42"; then
  if ceiling_ok "$M42"; then no "case 42 MUTATION CONTROL: without the sleep clamp case 42 still passed — it proves nothing"
  else ok "case 42 MUTATION CONTROL: without the sleep clamp the call overshoots ($WHY42)"; fi
else no "case 42 mutant invalid (empty / identical / bash -n)"; fi
rm -rf "$(dirname "$M42")"

# ----------------------------------------------------------------------------
# Cases 43-48 (issue #874): rulesets are a second protection store. A ruleset-only base answers
# the classic read 404; its required checks must still be required (never "verified empty"), the
# two stores' lists union, and an unreadable ruleset read is required=unknown, never green.
# ----------------------------------------------------------------------------
RS_ROLL='{"headRefOid":"deadbeef00","statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS","state":""},{"name":"e2e","status":"COMPLETED","conclusion":"FAILURE","state":""}]}'
RS_E2E='[{"type":"deletion"},{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"e2e"}]}}]'
rs_case() { # <num> <title> <expect-regex> <classic ctx json|404> <rulesets json|fail|none>
  local d; d="$(fresh_stub_dir)"
  if [ "$4" = 404 ]; then write_names_stub "$d" "$RS_ROLL"; touch "$d/prot-404"; else write_names_stub "$d" "$RS_ROLL" "$4"; fi
  case "$5" in fail) touch "$d/rulesets-fail" ;; none) : ;; *) printf '%s\n' "$5" > "$d/rulesets.json" ;; esac
  echo "== $1. $2 =="
  local o; o="$(GH="$d/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 0 --interval 1 --required-only --names)"
  if grep -qE "$3" <<<"$o"; then ok "$2 ($o)"; else no "$2 wrong: '$o'"; fi
  rm -rf "$d"
}
rs_case 43 "classic 404 + ruleset requiring a red check => required=red, the check named" '^SETTLED sha=deadbeef00 required=red .*red_names=e2e' 404 "$RS_E2E"
rs_case 44 "classic 404 + no ruleset check => required=green (verified empty, unchanged)" '^SETTLED sha=deadbeef00 required=green ' 404 none
rs_case 45 "classic 404 + unreadable ruleset read => required=unknown, NEVER green" '^SETTLED sha=deadbeef00 required=unknown ' 404 fail
rs_case 46 "classic [ci] alone => required=green (e2e not required)" '^SETTLED sha=deadbeef00 required=green ' '["ci"]' none
rs_case 47 "classic [ci] + ruleset [e2e] => the union: required=red on e2e" '^SETTLED sha=deadbeef00 required=red .*red_names=e2e' '["ci"]' "$RS_E2E"
rs_case 48 "classic [ci] + unreadable ruleset read => required=unknown" '^SETTLED sha=deadbeef00 required=unknown ' '["ci"]' fail

# ----------------------------------------------------------------------------
# Cases 49-56 (drain-named-required-checks): --named-required <json> stands in for the required set ONLY where
# this script's own protection read yields no list (paid-plan refusal, an unreadable read, a 404 with no ruleset
# check); a readable read (a 200, even an empty list; a 404 + ruleset list) always wins; an absent named check is
# pending; a malformed value is ignored.
# ----------------------------------------------------------------------------
NR_UT='["Unit Tests"]'
NR_ROLL='[{"name":"Unit Tests","status":"COMPLETED","conclusion":"SUCCESS","state":""},{"name":"deploy","status":"COMPLETED","conclusion":"FAILURE","state":"","detailsUrl":"https://github.com/acme/widgets/actions/runs/88/job/1"}]'
NR_UT_RED='{"headRefOid":"deadbeef00","statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS","state":""},{"name":"Unit Tests","status":"COMPLETED","conclusion":"FAILURE","state":"","detailsUrl":"https://github.com/acme/widgets/actions/runs/91/job/1"}]}'
NR_CI_ONLY='{"headRefOid":"deadbeef00","statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS","state":""}]}'
nr_refusal() { # <num> <title> <expect-regex> <body> <err> <rollup> <named arg | -> — the SUT under --required-only --names
  local d o; d="$(fresh_stub_dir)"
  write_refusal_stub "$d" "$4" "$5" "$6"
  echo "== $1. $2 =="
  if [ "$7" = - ]; then o="$(WFC_NO_LIST_GRACE=0 GH="$d/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 0 --interval 1 --required-only --names 2>/dev/null)"
  else o="$(WFC_NO_LIST_GRACE=0 GH="$d/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 0 --interval 1 --required-only --names --named-required "$7" 2>/dev/null)"; fi
  if grep -qE "$3" <<<"$o"; then ok "$2 ($o)"; else no "$2 wrong: '$o'"; fi
  rm -rf "$d"
}
nr_names() { # <num> <title> <expect-regex> <view json> <classic ctx json|404> <rulesets json|fail|none> [named arg] — sets NR_OUT
  local d; d="$(fresh_stub_dir)"
  if [ "$5" = 404 ]; then write_names_stub "$d" "$4"; touch "$d/prot-404"; else write_names_stub "$d" "$4" "$5"; fi
  case "$6" in fail) touch "$d/rulesets-fail" ;; none) : ;; *) printf '%s\n' "$6" > "$d/rulesets.json" ;; esac
  echo "== $1. $2 =="
  if [ "$#" -ge 7 ]; then NR_OUT="$(GH="$d/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 0 --interval 1 --required-only --names --named-required "$7" 2>/dev/null)"
  else NR_OUT="$(GH="$d/gh" bash "$SUT" "$PR" --sha "$SHA" --bound 0 --interval 1 --required-only --names 2>/dev/null)"; fi
  if grep -qE "$3" <<<"$NR_OUT"; then ok "$2 ($NR_OUT)"; else no "$2 wrong: '$NR_OUT'"; fi
  rm -rf "$d"
}
nr_refusal 49 "paid-plan 403 + named [Unit Tests] => only the named set: green, the red deploy check ignored" \
  '^SETTLED sha=deadbeef00 required=green review_producing=settled pending_names=none red_names=none$' "$PAID_BODY" "$PAID_ERR" "$NR_ROLL" "$NR_UT"
nr_refusal 49b "control: paid-plan 403, no named set => every non-neutral check: red on deploy (unchanged)" \
  '^SETTLED sha=deadbeef00 required=red .*red_names=deploy@88$' "$PAID_BODY" "$PAID_ERR" "$NR_ROLL" -
nr_refusal 50 "token-scope 403 (unreadable) + named => the named set, never required=unknown" \
  '^SETTLED sha=deadbeef00 required=green ' '{"message":"Resource not accessible by integration","status":"403"}' \
  'gh: Resource not accessible by integration (HTTP 403)' "$NR_ROLL" "$NR_UT"
nr_refusal 51 "paid-plan 403 + named check absent from the rollup => pending (never green), named in pending_names" \
  '^ELAPSED sha=deadbeef00 required=pending .*pending_names=Unit Tests red_names=none$' "$PAID_BODY" "$PAID_ERR" "$CI_GREEN" "$NR_UT"
nr_refusal 52 "a malformed --named-required (a bare string) is ignored => the paid-plan outcome, red on deploy" \
  '^SETTLED sha=deadbeef00 required=red .*red_names=deploy@88$' "$PAID_BODY" "$PAID_ERR" "$NR_ROLL" '"Unit Tests"'
nr_names 53 "classic 404 + no ruleset check + named => the named set: red on Unit Tests (not a vacuous green)" \
  '^SETTLED sha=deadbeef00 required=red .*red_names=Unit Tests@91$' "$NR_UT_RED" 404 none "$NR_UT"
nr_names 54 "AC 4: a readable [ci] read wins over the named set (Unit Tests absent, never waited on)" \
  '^SETTLED sha=deadbeef00 required=green .*pending_names=none red_names=none$' "$NR_CI_ONLY" '["ci"]' none "$NR_UT"
nr_names 55 "classic 404 + ruleset [e2e] wins over the named set: red on e2e" \
  '^SETTLED sha=deadbeef00 required=red .*red_names=e2e@-$' "$RS_ROLL" 404 "$RS_E2E" "$NR_UT"
nr_names 56 "AC 5: a readable EMPTY list (reviews-only protection, a 200) wins: verified empty, green" \
  '^SETTLED sha=deadbeef00 required=green ' "$NR_CI_ONLY" '[]' none "$NR_UT"
NR_WITH="$NR_OUT"
nr_names 56b "AC 5 control: the same read with no named set" '^SETTLED sha=deadbeef00 required=green ' "$NR_CI_ONLY" '[]' none
[ "$NR_WITH" = "$NR_OUT" ] && ok "AC 5: the empty-list outcome with the named set is byte-identical to the one without it" \
  || no "AC 5: the named set changed a readable empty-list outcome: '$NR_WITH' vs '$NR_OUT'"
# a READABLE classic read whose ruleset read failed is a protection, not "no list": the named set never replaces
# the classic [ci] list there — required=unknown, ci's red still named, byte-identical to the run without the flag
NR_CI_RED='{"headRefOid":"deadbeef00","statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE","state":"","detailsUrl":"https://github.com/acme/widgets/actions/runs/91/job/1"},{"name":"Unit Tests","status":"COMPLETED","conclusion":"SUCCESS","state":""}]}'
nr_names 57 "classic [ci] + unreadable ruleset read + named [Unit Tests] => required=unknown, ci red, never green" \
  '^SETTLED sha=deadbeef00 required=unknown .*red_names=ci@91$' "$NR_CI_RED" '["ci"]' fail "$NR_UT"
NR_WITH="$NR_OUT"
nr_names 57b "control: the same read with no named set" '^SETTLED sha=deadbeef00 required=unknown .*red_names=ci@91$' "$NR_CI_RED" '["ci"]' fail
[ "$NR_WITH" = "$NR_OUT" ] && ok "classic readable + rulesets unreadable: the named set changes nothing (byte-identical)" \
  || no "the named set replaced a readable classic list: '$NR_WITH' vs '$NR_OUT'"
nr_names 58 "classic 404 + unreadable ruleset read + named => no list was read: the named set, red on Unit Tests" \
  '^SETTLED sha=deadbeef00 required=red .*red_names=Unit Tests@91$' "$NR_UT_RED" 404 fail "$NR_UT"
nr_refusal 59 "a blank name (\"  \") is not a check name (the drain's rule) => ignored, the paid-plan outcome" \
  '^SETTLED sha=deadbeef00 required=red .*red_names=deploy@88$' "$PAID_BODY" "$PAID_ERR" "$NR_ROLL" '["  "]'

echo "== 24. no state leaked into this test's cwd =="
if [ "$LEAK_BEFORE" -eq 1 ] || [ ! -d .supervisor/check-wait ]; then ok "cwd has no new .supervisor/check-wait"; else no "state LEAKED into $(pwd)/.supervisor/check-wait"; fi
rm -rf "$D18" "$D20" "$D21" "$D22" "$D25" "$D26" "$D28"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
