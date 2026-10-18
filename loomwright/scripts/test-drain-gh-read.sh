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
run required-checks acme/widget release/2.x
[ "$RC" -eq 0 ] && [ "$(argv_line)" = "api --method GET repos/acme/widget/branches/release/2.x/protection/required_status_checks " ] \
  && ok "required-checks → GET .../branches/release/2.x/protection/required_status_checks" || no "required-checks argv wrong ($(argv_line))"

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

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
