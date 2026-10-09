#!/usr/bin/env bash
# test-no-fixed-sleep-race.sh — lint-as-self-test (iq02 T07): no NEW fixed `sleep <literal>` lands in a
# self-test unnoticed. A fixed sleep followed by an assertion on async output is a race (S6: `sleep
# 0.3` before reading a background stub's log failed under a loaded pool and cost a full suite run);
# the repair is a bounded condition wait (loomwright/scripts/wait-lib.sh). Modeled on
# test-no-pipefail-grep-q.sh's per-file count RATCHET.
#
# WHAT IS COUNTED (a line-based heuristic — it cannot fully parse bash, and need not): a `sleep
# <number>` statement on a non-comment line that is not a loop line (while/until/for) and not inside a
# `do … done` body, outside heredoc bodies, and not a background holder (`sleep N &`). Every test is
# made on the line's UNQUOTED text: a quoted span closed on the same line ("…", '…', $'…') is blanked
# first, so a `do`, `<<WORD` or `sleep N` inside a string (a stub body, a message, a JSON fixture) is
# neither a keyword nor a site, and `do`/`done` count only in keyword position (line start or after
# `;`). The depth and heredoc state carried across lines must return to its initial state at every
# file's end — asserted on the live suite, since a leaked state silently stops the count for the rest
# of that file (the iq02 review finding: 26 of 147 files once ended at depth > 0).
# ESCAPE HATCH: a trailing `# fixed-sleep-ok: <reason>` on the same line exempts it — the reason is
# the review record (a settle, a quiet-period absence check, an mtime separation, a fixture's own
# late writer).
# THE RATCHET (BASELINE below, "<count> <file>"): a count above its baseline, or a counted file not in
# the baseline, is red; a count BELOW its baseline is red too, until the baseline is lowered — so it
# only shrinks. A baseline row whose file is gone is red (stale). Controls (F1)-(F10) prove it fires.
# Scope: loomwright/scripts/test-*.sh, loomwright/scripts/adapters/*/test-*.sh, scripts/test-*.sh.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
shopt -s nullglob
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok: $1"; }
no() { fail=$((fail + 1)); echo "  FAIL: $1"; }

# The counter (sites mode prints "<file>\t<line>\t<text>" per counted site; -v leaks=1 prints instead
# "<file>\tdepth=<n>\theredoc=<delim>" for each file the scan ENDS in a non-initial state — a leaked
# depth or heredoc silently disables counting for the rest of that file, so the live suite must end
# every file at depth 0 outside any heredoc).
FSR_AWK='
# scan(l) — one line'\''s UNQUOTED shell text: sets CODE (l with each quoted span closed on this line
# blanked to "" and a trailing comment removed; a `$( )` inside "…" is followed as code, the way bash
# nests it; an unclosed quote keeps its remainder as code, so a loop opened inside a multi-line
# `bash -c '\''…'\''` still balances) and HD (the first heredoc delimiter outside quotes, `<<<`
# here-strings excluded, else ""). No state crosses lines here.
function scan(l,   out, i, n, c, j, k, m, sp, st, pd, so, si, b) {
  out = ""; HD = ""; n = length(l); i = 1; sp = 1; st[1] = "N"; pd[1] = 0
  while (i <= n) {
    if (st[sp] == "D") {
      if (!match(substr(l, i), /["\\$]/)) break
      i += RSTART - 1; c = substr(l, i, 1)
      if (c == "\\") { i += 2; continue }
      if (c == "\"") { sp--; i++; continue }
      if (substr(l, i + 1, 1) == "(") { sp++; st[sp] = "N"; pd[sp] = 0; out = out " "; i += 2; continue }
      i++; continue
    }
    if (!match(substr(l, i), /['\''"\\#<()]/)) { out = out substr(l, i); break }
    out = out substr(l, i, RSTART - 1); i += RSTART - 1; c = substr(l, i, 1)
    if (c == "\\") { out = out substr(l, i, 2); i += 2; continue }
    if (c == "(") { pd[sp]++; out = out c; i++; continue }
    if (c == ")") {
      if (sp > 1 && pd[sp] == 0) { sp--; out = out " "; i++; continue }
      if (pd[sp] > 0) pd[sp]--
      out = out c; i++; continue
    }
    if (c == "#") {
      if (sp == 1 && (i == 1 || substr(l, i - 1, 1) ~ /[ \t;&|()]/)) break
      out = out c; i++; continue
    }
    if (c == "<") {
      if (HD == "" && substr(l, i - 1, 1) != "<" && substr(l, i + 2, 1) != "<" \
          && match(substr(l, i), /^<<-?[ \t]*['\''"]?[A-Za-z_][A-Za-z0-9_]*['\''"]?/)) {
        m = substr(l, i, RLENGTH); i += RLENGTH
        sub(/^<<-?[ \t]*['\''"]?/, "", m); sub(/['\''"]$/, "", m); HD = m; out = out " "; continue
      }
      out = out c; i++; continue
    }
    if (c == "\"") { sp++; st[sp] = "D"; so[sp] = out; si[sp] = i; out = out "\"\""; i++; continue }
    # a single quote: '\''…'\'' has no escapes; $'\''…'\'' honours backslash escapes
    k = i + 1; j = 0
    if (substr(l, i - 1, 1) != "$") { j = index(substr(l, k), "'\''"); if (j) k += j - 1 }
    else while (match(substr(l, k), /['\''\\]/)) {
      k += RSTART - 1; if (substr(l, k, 1) == "\\") { k += 2; continue }
      j = 1; break
    }
    if (!j) { out = out substr(l, i); break }
    out = out "\"\""; i = k + 1
  }
  for (b = 2; b <= sp; b++) if (st[b] == "D") { out = so[b] substr(l, si[b]); break }
  CODE = out
}
function endfile() { if (leaks && FN != "" && (depth != 0 || hd != "")) printf "%s\tdepth=%d\theredoc=%s\n", FN, depth, hd }
FNR == 1 { endfile(); hd = ""; depth = 0; FN = FILENAME }
END { endfile() }
{
  line = $0
  if (hd != "") { t = line; sub(/^[ \t]+/, "", t); if (t == hd) hd = ""; next }
  if (line ~ /^[ \t]*#/) next
  scan(line); if (HD != "") hd = HD
  nd = gsub(/(^|;|\)\))[ \t]*do([ \t;]|$)/, "&", CODE); nn = gsub(/(^|[;&])[ \t]*done([ \t;)|&<>]|$)/, "&", CODE)
  isloop = (CODE ~ /(^|[ \t;&|(])(while|until|for)[ \t(]/)
  if (!leaks && line !~ /# fixed-sleep-ok:/ && depth == 0 && !isloop \
      && CODE ~ /(^|[ \t;&|({])sleep[ \t]+[0-9][0-9.]*([ \t;|)}]|&&|$)/ \
      && CODE !~ /(^|[ \t;&|({])sleep[ \t]+[0-9][0-9.]*[ \t]*&([^&]|$)/)
    printf "%s\t%d\t%s\n", FILENAME, FNR, line
  depth += nd - nn; if (depth < 0) depth = 0
}
'
fsr_sites() { awk "$FSR_AWK" "$@"; }
fsr_leaks() { awk -v leaks=1 "$FSR_AWK" "$@"; }
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

# BASELINE — every file's accepted count today (iq02 T07; re-measured when the depth/heredoc leak
# was fixed — every row that moved then is a site already on main, previously hidden by the leak or
# a quoted string miscounted as one). Lower it when you fix a site; never raise it: wait on the
# condition or annotate the line instead.
BASELINE='
2 loomwright/scripts/test-agent-identity.sh
3 loomwright/scripts/test-automate-lanes.sh
1 loomwright/scripts/test-ci-slot.sh
1 loomwright/scripts/test-classify-bot-review.sh
2 loomwright/scripts/test-lane-sampler.sh
1 loomwright/scripts/test-pr-postmortem-gather.sh
1 loomwright/scripts/test-run-self-tests.sh
1 loomwright/scripts/test-session-resume.sh
1 loomwright/scripts/test-set-otel-resource-attrs.sh
3 loomwright/scripts/test-setup-ui.sh
1 loomwright/scripts/test-token-ledger.sh
1 loomwright/scripts/test-verify-queue.sh
15 loomwright/scripts/test-verify-walkthrough.sh
1 loomwright/scripts/test-worktree-audit.sh
2 scripts/test-ci-local.sh
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
# The line heuristic carries depth/heredoc state across lines; a file that ENDS in a non-initial
# state had its count silently switched off somewhere above its end — red, never a quiet pass.
if fsr_leaks "${files[@]}" > "$T0/live.leaks"; then
  if [ -s "$T0/live.leaks" ]; then
    no "the counter ended $(wc -l < "$T0/live.leaks" | tr -d ' ') file(s) in a non-initial state (its count was off from the leak onward):"
    sed 's/^/    leak: /' "$T0/live.leaks" | head -40
  else ok "every scanned file ends at depth 0 outside any heredoc (no leaked counter state)"; fi
else no "the leak pass failed on the live suite — refusing a vacuous pass"; fi

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
# (F8)-(F10): the leak class — a keyword or heredoc opener inside a string must not switch counting off.
[ "$(fx 'echo "nothing to do here"' 'run &' 'sleep 0.3' 'assert')" = 1 ] && ok "(F8) a \`do\` inside a string does not hide a later fixed sleep" || no "(F8) a quoted do leaked depth"
[ "$(fx 'x='"'"'{"note":"just do whatever"}'"'"'' 'grep -q y <<< word' 'printf '"'"'<<<<<<< HEAD\n'"'"'' 'echo "cat <<EOF"' 'sleep 1')" = 1 ] \
  && ok "(F9) a single-quoted do, a here-string and quoted <<WORD openers leave counting on" || no "(F9) leaked"
[ -z "$(fx 'bash -c '"'"'while [ ! -s log ]; do' '  sleep 0.1' 'done'"'"'')" ] && ok "(F9) a loop inside a multi-line quoted program still balances (its body is not counted)" || no "(F9) multi-line quoted loop"
printf '%s\n' 'while x; do' 'echo' > "$T/test-lk1.sh"; printf '%s\n' 'cat <<EOF' 'x' > "$T/test-lk2.sh"; printf '%s\n' 'echo "a do b"' > "$T/test-lk3.sh"
lk="$(fsr_leaks "$T/test-lk1.sh" "$T/test-lk2.sh" "$T/test-lk3.sh")"
case "$lk" in *"test-lk1.sh	depth=1"*"test-lk2.sh	depth=0	heredoc=EOF"*) ok "(F10) the leak pass reports an unclosed do and an unterminated heredoc" ;; *) no "(F10) leak pass silent: [$lk]" ;; esac
case "$lk" in *test-lk3.sh*) no "(F10) a balanced file reported as leaking" ;; *) ok "(F10) a file ending in its initial state is not reported" ;; esac
v="$(ratchet '2 a.sh' '3 a.sh
1 b.sh')"
case "$v" in *"NEW b.sh"*"UP a.sh"*|*"UP a.sh"*"NEW b.sh"*) ok "(F7) ratchet: a rise and a new file are both red" ;; *) no "(F7) ratchet missed: [$v]" ;; esac
case "$(ratchet '2 a.sh' '1 a.sh')" in "DOWN a.sh"*) ok "(F7) ratchet: a fall without lowering the baseline is red" ;; *) no "(F7) DOWN not reported" ;; esac
[ -z "$(ratchet '2 a.sh' '2 a.sh')" ] && ok "(F7) ratchet: an unchanged count holds" || no "(F7) unchanged count flagged"

echo
echo "test-no-fixed-sleep-race: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
