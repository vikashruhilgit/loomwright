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

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
