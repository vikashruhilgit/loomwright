#!/usr/bin/env bash
# test-no-fixed-sleep-race.sh — lint-as-self-test (iq02 T07): no NEW fixed `sleep <literal>` lands in a
# self-test unnoticed. A fixed sleep followed by an assertion on async output is a race (S6: `sleep
# 0.3` before reading a background stub's log failed under a loaded pool and cost a full suite run);
# the repair is a bounded condition wait (loomwright/scripts/wait-lib.sh). Modeled on
# test-no-pipefail-grep-q.sh's per-file count RATCHET.
#
# WHAT IS COUNTED (a line-based heuristic — it cannot fully parse bash, and need not): a `sleep
# <number>` statement on a non-comment line that is not a loop line (while/until/for) and not inside a
# `do … done` body, outside heredoc bodies, and not a background holder (`sleep N &`).
# ESCAPE HATCH: a trailing `# fixed-sleep-ok: <reason>` on the same line exempts it — the reason is
# the review record (a settle, a quiet-period absence check, an mtime separation, a fixture's own
# late writer).
# THE RATCHET (BASELINE below, "<count> <file>"): a count above its baseline, or a counted file not in
# the baseline, is red; a count BELOW its baseline is red too, until the baseline is lowered — so it
# only shrinks. A baseline row whose file is gone is red (stale). Controls (F1)-(F7) prove it fires.
# Scope: loomwright/scripts/test-*.sh, loomwright/scripts/adapters/*/test-*.sh, scripts/test-*.sh.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
shopt -s nullglob
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok: $1"; }
no() { fail=$((fail + 1)); echo "  FAIL: $1"; }

# The counter: prints "<file>\t<line>\t<text>" per counted site.
FSR_AWK='
function strip_hd_start(l,   m) {
  if (match(l, /<<-?[ \t]*['\''"]?[A-Za-z_][A-Za-z0-9_]*['\''"]?/)) {
    m = substr(l, RSTART, RLENGTH); sub(/^<<-?[ \t]*['\''"]?/, "", m); sub(/['\''"]?$/, "", m); return m
  }
  return ""
}
FNR == 1 { hd = ""; depth = 0 }
{
  line = $0
  if (hd != "") { t = line; sub(/^[ \t]+/, "", t); if (t == hd) hd = ""; next }
  d = strip_hd_start(line); if (d != "" && line !~ /^[ \t]*#/) hd = d
  if (line ~ /^[ \t]*#/) next
  code = line; sub(/[ \t]#[^'\''"]*$/, "", code)
  nd = gsub(/(^|[ \t;&|(])do([ \t;]|$)/, "&", code); nn = gsub(/(^|[ \t;&|])done([ \t;)|&]|$)/, "&", code)
  isloop = (code ~ /(^|[ \t;&|(])(while|until|for)[ \t]/)
  if (line !~ /# fixed-sleep-ok:/ && depth == 0 && !isloop \
      && code ~ /(^|[ \t;&|({])sleep[ \t]+[0-9][0-9.]*([ \t;|)}]|&&|$)/ \
      && code !~ /(^|[ \t;&|({])sleep[ \t]+[0-9][0-9.]*[ \t]*&([^&]|$)/)
    printf "%s\t%d\t%s\n", FILENAME, FNR, line
  depth += nd - nn; if (depth < 0) depth = 0
}
'
fsr_sites() { awk "$FSR_AWK" "$@"; }
# fsr_counts <files…> — "<count> <file>" for each file with a counted site, sorted by file.
fsr_counts() { fsr_sites "$@" | cut -f1 | env LC_ALL=C sort | uniq -c | awk '{ print $1, $2 }'; }
# ratchet <baseline-text> <counts-text> — prints one line per violation; empty = holds.
ratchet() {
  awk 'NR == FNR { if (NF == 2) b[$2] = $1; next }
       NF == 2 { c[$2] = $1 }
       END {
         for (f in c) {
           if (!(f in b)) printf "NEW %s: %d fixed sleep(s), baseline 0 — wait on the condition (wait-lib.sh) or annotate `# fixed-sleep-ok: <reason>`\n", f, c[f]
           else if (c[f] > b[f]) printf "UP %s: %d fixed sleep(s), baseline %d\n", f, c[f], b[f]
           else if (c[f] < b[f]) printf "DOWN %s: %d fixed sleep(s), baseline %d — lower the baseline in this file\n", f, c[f], b[f]
         }
         for (f in b) if (!(f in c) && b[f] > 0) printf "DOWN %s: 0 fixed sleeps, baseline %d — lower the baseline in this file\n", f, b[f]
       }' <(printf '%s\n' "$1") <(printf '%s\n' "$2") | env LC_ALL=C sort
}

# BASELINE — every file's accepted count today (iq02 T07). Lower it when you fix a site; never raise
# it: wait on the condition or annotate the line instead.
BASELINE='
1 loomwright/scripts/adapters/providers/test-lens-run.sh
2 loomwright/scripts/test-agent-identity.sh
3 loomwright/scripts/test-classify-bot-review.sh
2 loomwright/scripts/test-lane-sampler.sh
1 loomwright/scripts/test-pr-postmortem-gather.sh
1 loomwright/scripts/test-run-self-tests.sh
2 loomwright/scripts/test-session-resume.sh
1 loomwright/scripts/test-set-otel-resource-attrs.sh
2 loomwright/scripts/test-setup-ui.sh
1 loomwright/scripts/test-token-ledger.sh
1 loomwright/scripts/test-verify-queue.sh
15 loomwright/scripts/test-verify-walkthrough.sh
1 loomwright/scripts/test-worktree-audit.sh
3 scripts/test-ci-local.sh
'

T0="$(mktemp -d "${TMPDIR:-/tmp}/test-no-fixed-sleep-race.XXXXXX")" || exit 1
trap 'rm -rf "$T0"' EXIT
echo "== the live suite against its baseline =="
cd "$REPO" || exit 1
files=(loomwright/scripts/test-*.sh loomwright/scripts/adapters/*/test-*.sh scripts/test-*.sh)
[ "${#files[@]}" -gt 50 ] && ok "scanned ${#files[@]} test files" || no "the globs matched only ${#files[@]} files — refusing a vacuous scan"
if fsr_sites "${files[@]}" > "$T0/live.sites"; then ok "the counter ran on the live suite"; else no "the counter failed on the live suite — refusing a vacuous pass"; fi
viol="$(ratchet "$BASELINE" "$(cut -f1 "$T0/live.sites" | env LC_ALL=C sort | uniq -c | awk '{ print $1, $2 }')")"
if [ -z "$viol" ]; then ok "every file is at its baseline"
else
  no "fixed-sleep ratchet:"; printf '%s\n' "$viol" | sed 's/^/    /'
  sed 's/^/    site: /' "$T0/live.sites" | head -60
fi
while read -r n f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || no "stale baseline row: $f no longer exists"
done <<<"$BASELINE"

echo "== controls: the counter and the ratchet can fire =="
T="$T0"
# fx <lines…> — the counted-site count of a fixture file; prints ERR (never empty) when the counter
# itself fails, so a broken awk cannot pass the "not counted" controls.
fx() {
  printf '%s\n' "$@" > "$T/test-fx.sh"
  fsr_sites "$T/test-fx.sh" > "$T/fx.sites" || { echo ERR; return; }
  n="$(wc -l < "$T/fx.sites" | tr -d ' ')"; [ "$n" = 0 ] || echo "$n"
}
[ "$(fx 'run_thing &' 'sleep 0.3' 'has "S6" "$(cat log)" "x"')" = 1 ] && ok "(F1) a new fixed sleep before an assertion is counted" || no "(F1) not counted"
[ -z "$(fx 'while [ ! -s log ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done')" ] && ok "(F2) the same sleep inside a one-line bounded while is not counted" || no "(F2) loop line counted"
[ -z "$(fx 'while [ ! -s log ]; do' '  sleep 0.1' 'done')" ] && ok "(F3) a sleep inside a multi-line do…done body is not counted" || no "(F3) loop body counted"
[ -z "$(fx 'sleep 0.3   # fixed-sleep-ok: settle before the signal')" ] && ok "(F4) a # fixed-sleep-ok: line is exempt" || no "(F4) annotation ignored"
[ -z "$(fx 'cat > stub <<EOF' 'sleep 0.5' 'EOF' 'sleep 30 &' '# sleep 0.3 in a comment')" ] && ok "(F5) heredoc bodies, background holders and comments are not counted" || no "(F5) counted"
[ "$(fx 'cat > stub <<EOF' 'x' 'EOF' 'sleep 1')" = 1 ] && ok "(F6) counting resumes after a heredoc ends" || no "(F6) heredoc never closed"
v="$(ratchet '2 a.sh' '3 a.sh
1 b.sh')"
case "$v" in *"NEW b.sh"*"UP a.sh"*|*"UP a.sh"*"NEW b.sh"*) ok "(F7) ratchet: a rise and a new file are both red" ;; *) no "(F7) ratchet missed: [$v]" ;; esac
case "$(ratchet '2 a.sh' '1 a.sh')" in "DOWN a.sh"*) ok "(F7) ratchet: a fall without lowering the baseline is red" ;; *) no "(F7) DOWN not reported" ;; esac
[ -z "$(ratchet '2 a.sh' '2 a.sh')" ] && ok "(F7) ratchet: an unchanged count holds" || no "(F7) unchanged count flagged"

echo
echo "test-no-fixed-sleep-race: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
