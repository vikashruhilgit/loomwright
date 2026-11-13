#!/usr/bin/env bash
# test-drain-gh-read.sh — drain-gh-read.sh is the detached drain's ONLY GitHub
# API surface, so its contract is security-relevant: every operation is a fixed
# READ (GET method or a fixed GraphQL query, never a caller-supplied document),
# a crafted identifier cannot smuggle gh flags or path segments, and a failed
# read exits non-zero (the drain treats that channel as UNKNOWN, never clean).
# gh is stubbed via GH= — the stub records its argv and exits $STUB_RC.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/drain-gh-read.sh"
pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
STUB="$T/gh"; ARGV="$T/argv"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
: > "$ARGV"
for a in "$@"; do printf '%s\n' "$a" >> "$ARGV"; done
echo '[]'
exit "${STUB_RC:-0}"
EOF
chmod +x "$STUB"
export ARGV

run() { rm -f "$ARGV"; OUT="$(GH="$STUB" bash "$SUT" "$@" 2>/dev/null)"; RC=$?; }
called() { [ -e "$ARGV" ]; }
argv_line() { tr '\n' ' ' < "$ARGV" 2>/dev/null; }

echo "== 1. REST reads are explicit GET on the fixed endpoint =="
run issue-comments acme/widget 42
if [ "$RC" -eq 0 ] && [ "$(argv_line)" = "api --method GET repos/acme/widget/issues/42/comments?per_page=100 " ]; then
  ok "issue-comments → GET repos/acme/widget/issues/42/comments?per_page=100"
else no "issue-comments argv wrong (rc=$RC argv='$(argv_line)')"; fi
run check-annotations acme/widget 9001
[ "$RC" -eq 0 ] && [ "$(argv_line)" = "api --method GET repos/acme/widget/check-runs/9001/annotations " ] \
  && ok "check-annotations → GET .../check-runs/9001/annotations" || no "check-annotations argv wrong ($(argv_line))"
run check-run acme/widget 9001
[ "$RC" -eq 0 ] && [ "$(argv_line)" = "api --method GET repos/acme/widget/check-runs/9001 " ] \
  && ok "check-run → GET .../check-runs/9001" || no "check-run argv wrong ($(argv_line))"

echo "== 2. review-threads sends a fixed query document — never a mutation =="
run review-threads acme/widget 42
Q="$(grep '^query=' "$ARGV" 2>/dev/null || true)"
if [ "$RC" -eq 0 ] && grep -qx 'graphql' "$ARGV" && grep -q 'reviewThreads(first:100)' "$ARGV" \
   && ! grep -qi 'mutation' "$ARGV" && grep -qx 'owner=acme' "$ARGV" && grep -qx 'repo=widget' "$ARGV" && grep -qx 'number=42' "$ARGV"; then
  ok "review-threads → graphql fixed query, owner/repo/number bound as variables"
else no "review-threads argv wrong (rc=$RC argv='$(argv_line)')"; fi
# owner/repo go through -f (raw string), number through -F (typed Int).
[ "$(grep -B1 -x 'owner=acme' "$ARGV" | head -1)" = "-f" ] && [ "$(grep -B1 -x 'number=42' "$ARGV" | head -1)" = "-F" ] \
  && ok "owner via -f (no @file / type coercion), number via -F" || no "variable flag kinds wrong ($(argv_line))"

echo "== 3. --jq is passed through to gh's own filter =="
run issue-comments acme/widget 42 --jq length
[ "$RC" -eq 0 ] && grep -qF -- '--jq length' <<<"$(argv_line)" && ok "--jq length forwarded" || no "--jq not forwarded ($(argv_line))"

echo "== 4. crafted identifiers are refused (exit 2) WITHOUT calling gh =="
for args in \
  "issue-comments acme/widget 42 -X PUT" \
  "issue-comments acme/widget/pulls/1/merge 42" \
  "issue-comments -X/widget 42" \
  "issue-comments acme 42" \
  "issue-comments acme/widget 42abc" \
  "check-annotations acme/widget ../1" \
  "check-run acme/widget 1/annotations" \
  "check-run acme/widget -X" \
  "required-checks acme/widget -fmerge" \
  "required-checks acme/widget a..b" \
  "review-threads acme/widget 1 --jq" \
  "merge acme/widget 1" \
  "issue-comments acme/widget"; do
  # shellcheck disable=SC2086
  run $args
  if [ "$RC" -eq 2 ] && ! called; then ok "refused: $args"; else no "not refused (rc=$RC called=$(called && echo yes || echo no)): $args"; fi
done
run issue-comments 'acme/wid get' 42
[ "$RC" -eq 2 ] && ! called && ok "refused: slug with a space" || no "slug with a space not refused"

echo "== 5. a failed read is NOT fail-safe: gh's non-zero status propagates =="
rm -f "$ARGV"; GH="$STUB" STUB_RC=1 bash "$SUT" issue-comments acme/widget 42 >/dev/null 2>&1; RC=$?
[ "$RC" -eq 1 ] && ok "gh exit 1 → wrapper exit 1 (channel UNKNOWN, never read as clean)" || no "gh failure swallowed (rc=$RC)"
rm -f "$ARGV"; GH="$STUB" STUB_RC=4 bash "$SUT" review-threads acme/widget 42 >/dev/null 2>&1; RC=$?
[ "$RC" -eq 4 ] && ok "gh exit 4 → wrapper exit 4" || no "gh exit status not preserved (rc=$RC)"

echo "== 6. required-checks: classic protection ∪ active rulesets (issue #874) =="
# A routing stub: the classic read answers per $CLASSIC, the ruleset read per $RULES; every argv
# line is appended to $CALLS so the test can see both reads were fixed GETs.
RSTUB="$T/gh-rc"; CALLS="$T/calls"
cat > "$RSTUB" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$*" in
  *"/protection/required_status_checks"*)
    case "$CLASSIC" in
      ok)   echo '{"url":"u","strict":true,"contexts":["ci"],"checks":[{"context":"ci","app_id":1},{"context":"lint","app_id":2}]}' ;;
      404)  echo '{"message":"Branch not protected","status":"404"}'; echo 'gh: Branch not protected (HTTP 404)' >&2; exit 1 ;;
      notenabled) echo '{"message":"Required status checks not enabled","status":"404"}'
            echo 'gh: Required status checks not enabled (HTTP 404)' >&2; exit 1 ;;
      paid) echo '{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","status":"403"}'
            echo 'gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)' >&2; exit 1 ;;
      500)  echo 'gh: Server Error (HTTP 500)' >&2; exit 1 ;;
    esac ;;
  *"/rules/branches/"*)
    case "$RULES" in
      list)    echo '[{"type":"deletion"},{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"e2e"},{"context":"ci"}]}}]' ;;
      paged)   echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"e2e"}]}}]'
               echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"unit"}]}}]' ;;
      none)    echo '[{"type":"deletion"},{"type":"pull_request","parameters":{"required_approving_review_count":1}}]' ;;
      empty)   echo '[]' ;;
      404)     echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
      paid)    echo '{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","status":"403"}'
               echo 'gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)' >&2; exit 1 ;;
      403)     echo 'gh: Resource not accessible by integration (HTTP 403)' >&2; exit 1 ;;
      garbage) echo '{"message":"oops"}' ;;
    esac ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$RSTUB"; export CALLS
rc_run() { # <classic> <rules> [extra args] — sets OUT ERR RC
  rm -f "$CALLS"
  OUT="$(CLASSIC="$1" RULES="$2" GH="$RSTUB" bash "$SUT" required-checks acme/widget release/2.x "${@:3}" 2>"$T/err")"; RC=$?
  ERR="$(cat "$T/err")"
}
ctx() { printf '%s' "$OUT" | jq -c '.contexts' 2>/dev/null; }

rc_run ok empty
if [ "$RC" -eq 0 ] && [ "$(sed -n 1p "$CALLS")" = "api --method GET repos/acme/widget/branches/release/2.x/protection/required_status_checks" ] \
   && [ "$(sed -n 2p "$CALLS")" = "api --method GET repos/acme/widget/rules/branches/release/2.x?per_page=100 --paginate" ] \
   && [ "$(wc -l < "$CALLS" | tr -d ' ')" = 2 ]; then
  ok "required-checks → two fixed GETs: classic required_status_checks, then rules/branches/<base> (paginated)"
else no "required-checks argv wrong (rc=$RC calls='$(tr '\n' '|' < "$CALLS")')"; fi
[ "$(ctx)" = '["ci","lint"]' ] && printf '%s' "$OUT" | jq -e '.strict == true' >/dev/null \
  && ok "classic only (no rulesets): contexts ∪ checks[].context, the rest of classic's JSON kept" || no "classic-only output wrong ($OUT)"

rc_run 404 list
[ "$RC" -eq 0 ] && [ "$(ctx)" = '["ci","e2e"]' ] \
  && ok "classic 404 + ruleset with required checks ⇒ exit 0, {contexts: the ruleset's checks}" || no "ruleset-only wrong (rc=$RC out='$OUT' err='$ERR')"
rc_run 404 paged
[ "$RC" -eq 0 ] && [ "$(ctx)" = '["e2e","unit"]' ] \
  && ok "paginated rules (two arrays) are merged" || no "paged rules wrong (rc=$RC out='$OUT')"
rc_run ok list
[ "$RC" -eq 0 ] && [ "$(ctx)" = '["ci","e2e","lint"]' ] \
  && ok "classic and ruleset both present ⇒ the union" || no "union wrong (rc=$RC out='$OUT')"
rc_run 404 list --jq '.contexts | length'
[ "$RC" -eq 0 ] && [ "$OUT" = 2 ] && ok "--jq applies to the merged JSON" || no "--jq on merged wrong (rc=$RC out='$OUT')"

for r in none empty 404 paid; do
  rc_run 404 "$r"
  if [ "$RC" -eq 1 ] && grep -q 'HTTP 404' <<<"$ERR"; then
    ok "classic 404 + rules '$r' (no required check) ⇒ classic's own 404 failure, unchanged — never 'every check required'"
  else no "classic 404 + rules $r wrong (rc=$RC out='$OUT' err='$ERR')"; fi
done
for r in 403 garbage; do
  rc_run 404 "$r"
  [ "$RC" -eq 1 ] && [ -z "$OUT" ] && grep -q 'ruleset read failed' <<<"$ERR" \
    && ok "classic 404 + rules '$r' (unreadable) ⇒ exit 1, no list (fail CLOSED)" || no "classic 404 + rules $r wrong (rc=$RC out='$OUT' err='$ERR')"
  ! grep -q '(classic protection readable)' <<<"$ERR" \
    && ok "classic 404 + rules '$r' ⇒ no classic-readable marker" || no "classic 404 + rules $r carries the classic-readable marker ($ERR)"
  rc_run ok "$r"
  [ "$RC" -eq 1 ] && [ -z "$OUT" ] \
    && ok "classic readable + rules '$r' (unreadable) ⇒ exit 1: a ruleset that cannot be read may require more" || no "classic ok + rules $r wrong (rc=$RC out='$OUT')"
  grep -q 'ruleset read failed for release/2.x (classic protection readable): ' <<<"$ERR" \
    && ok "classic readable + rules '$r' ⇒ the error names classic as readable (a named set never replaces it)" || no "classic ok + rules $r marker missing ($ERR)"
done
# a classic 404 + unreadable rules: the error carries the 404 (`(classic: …)`) — its body is what tells an
# unprotected base from a reviews-only one (required-checks-named.sh); stdout and the exit stay as before
rc_run 404 403
[ "$RC" -eq 1 ] && [ -z "$OUT" ] \
  && grep -q 'ruleset read failed for release/2.x (classic: gh: Branch not protected (HTTP 404)): .*HTTP 403' <<<"$ERR" \
  && ok "classic 404 + rules unreadable ⇒ exit 1, no stdout, the error carries the classic 404 and the rules error" \
  || no "classic 404 + rules 403 error shape wrong (rc=$RC out='$OUT' err='$ERR')"
rc_run notenabled 403
[ "$RC" -eq 1 ] && [ -z "$OUT" ] && [ "$(wc -l <<<"$ERR" | tr -d ' ')" = 1 ] \
  && grep -q '(classic: gh: Required status checks not enabled (HTTP 404)): ' <<<"$ERR" \
  && ok "reviews-only classic 404 + rules unreadable ⇒ the one error line names 'Required status checks not enabled'" \
  || no "reviews-only classic 404 + rules 403 wrong (rc=$RC out='$OUT' err='$ERR')"
rc_run notenabled none
[ "$RC" -eq 1 ] && grep -q 'Required status checks not enabled (HTTP 404)' <<<"$ERR" \
  && ok "reviews-only classic 404 + no ruleset check ⇒ classic's own 404, unchanged" || no "reviews-only 404 + none wrong (rc=$RC err='$ERR')"
rc_run paid list
[ "$RC" -eq 1 ] && grep -q 'Upgrade to GitHub Pro' <<<"$OUT $ERR" && [ "$(wc -l < "$CALLS" | tr -d ' ')" = 1 ] \
  && ok "classic paid-plan refusal ⇒ passed through unchanged (stdout+stderr), rules never read" || no "paid-plan passthrough wrong (rc=$RC out='$OUT' err='$ERR')"
rc_run 500 list
[ "$RC" -eq 1 ] && grep -q 'HTTP 500' <<<"$ERR" && [ "$(wc -l < "$CALLS" | tr -d ' ')" = 1 ] \
  && ok "classic 500 ⇒ unreadable, passed through; a ruleset list never stands in for it" || no "classic 500 wrong (rc=$RC out='$OUT' err='$ERR')"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
