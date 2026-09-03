#!/usr/bin/env bash
# test-setup-ui.sh — STATIC, fixture-driven self-tests for the `/setup ui` module: the
# `floor-ui/` bundle (index.html + floor.css + floor.js) and the `setup-ui.sh` engine.
#
# STATIC ONLY: no Docker, no GitHub, and — the point of group (h) — no network beyond the
# loopback interface of this machine. It runs on the plugin's Ubuntu CI like every other
# test-*.sh (auto-registered by ci.yml's `loomwright/scripts/test-*.sh` glob).
#
# Exit 0 = all pass, 1 = any assertion failed, 2 = FIXTURE SETUP is broken.
# 1 and 2 are deliberately distinct: 1 means the assertions ran and something misbehaved;
# 2 means a fixture could not be BUILT as specified, so the assertions after it would be
# testing something other than what they name.
#
# WHAT THIS FILE CAN AND CANNOT PROVE — stated up front, because the alternative is a suite
# that reads as if it verified a rendering it never loaded. Several acceptance criteria have a
# BROWSER half (does the stalled lane actually read "no event for 25m" in a DOM?) which no
# headless bash suite can answer. Those halves are verified by a human or by the Supervisor at
# Phase 4.5 against the committed fixtures, and recorded in the PR body. What lives HERE is the
# static half of each: the literal strings, the occurrence COUNTS that make "nothing animates
# on a timer" checkable, the fixture facts the browser pass will read, and the whole engine.
#
# ISOLATION IS LOAD-BEARING AND IS ASSERTED, NOT ASSUMED. Every engine case passes `--ui-dir`
# into its own `mktemp -d`, so no case can reach the developer's real `~/.claude` tree; group
# (i) hashes two trees — the fixture parent AND a fixture git repo used as the working
# directory — before and after the full apply/serve/stop/remove sequence, because `serve`
# without `--no-regen` runs `build-floor.sh` in the CWD and that write must land in the
# fixture repo rather than in this checkout.
#
# Covers (each = an acceptance criterion):
#   (a) AC-no-egress — the three bundle files carry no http/https URL, no protocol-relative
#       reference inside a src/href/url(, no @import, no preconnect, no @font-face and no
#       url() at all; the CSP meta line is present VERBATIM; floor.js fetches exactly the
#       relative path `floor.json`. With a mutation control: a copy carrying one remote href
#       must be flagged, or the scanner proves nothing
#   (b) AC-lanes / AC-stall / AC-three-states static halves — the literal strings the browser
#       pass will read, the doubled-prefix stripping expression, `cache: 'no-store'`, the stall
#       query parameter, and THE MOTION BUDGET: exactly one setInterval and zero rAF calls in
#       floor.js, counted by occurrence, with a mutation control adding a second timer. Plus
#       the two claims the page must NOT make: the idle banner is reachable only through a
#       gated verdict (with a mutation control that ungates it), and the stale banner asserts
#       no cause it cannot observe. Plus the poll's in-flight guard and both of its clear sites
#   (c) AC-motion-a11y-theme — the reduced-motion block removes animation AND transition; the
#       light palette is on bare :root, dark under the system-preference query and again on
#       an explicit data-theme; body has a token background; exactly ONE @keyframes exists and
#       it is `pulse`; the non-colour cues (dashed stalled lane, hollow read-only dot) exist
#   (d) AC-fixtures-conform — every fixtures/floor-ui/*.json is validated against the required
#       key set PARSED OUT of the `## FLOOR_PROJECTION` block of RESULT_SCHEMAS.md, exactly as
#       test-build-floor.sh case (h) does. The key list is never restated here, so a schema
#       change moves this validator with it
#   (e) fixture FACTS the browser half depends on: floor-live has 3 agent rows of which 2 are
#       typed; floor-stalled has exactly one row older than the 300 s default; floor-empty is
#       the EARNED idle case (sessions counted, a current session identified, zero agents in
#       it); floor-nosession is its contrast (sessions counted, `current` OMITTED, a note
#       saying why, beside a state surface still recording phase EXECUTE); floor-stale's
#       generation time is far older than the others'
#   (f) AC-engine-contract — check on an absent dir, apply installs, a second apply is a
#       no-op, a drifted bundle is `updated` naming the file, remove is WITHHELD on a
#       directory with no marker (and that directory survives), remove deletes an owned one.
#       With a mutation control that strips the marker gate and shows the foreign directory
#       being deleted. Plus the two paths on which a removal REPORT could be false: a
#       --ui-dir that is itself a symlink, and a real directory whose PHYSICAL path is $HOME
#       reached through a symlinked parent
#   (g) AC-engine-fail-safe — python3 absent (PATH stub) aborts serve by name; jq absent still
#       applies and warns that build-floor.sh will skip; build-floor.sh absent aborts serve by
#       name; a bad subcommand and a bad flag both exit 0; an UNSET HOME aborts by name rather
#       than tripping `set -u`. EVERY branch exits 0. Plus the `?stale=` hint serve prints when
#       --interval outgrows the page's own threshold, its control at the default interval, and
#       a parity check on the two page constants the engine mirrors to compute it
#   (h) AC-loopback — a real detached server, a real fetch from 127.0.0.1 returning the fixture
#       bytes, and a refused connect to this host's first non-loopback IPv4 on the same port.
#       SKIPPED (reported separately from passes) when the host has no non-loopback address
#   (i) AC-remove-residue — the two hashed trees described above, plus the plugin's own bundle
#       hashed before and after
#   (z) release-surface parity for the /setup ui module registration, plus the surfaces/formats
#       basis sentence, which is QUOTED from build-floor.sh rather than restated
#
# NO `producer | grep -q` PIPELINES (SIGPIPE turns a match into rc=141 under pipefail).

set -uo pipefail
export LC_ALL=C

script_dir="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$script_dir/setup-ui.sh"
BUNDLE_DIR="$script_dir/floor-ui"
FIX_DIR="$script_dir/fixtures/floor-ui"
SCHEMA_MD="$(cd "$script_dir/../docs" && pwd 2>/dev/null || echo "$script_dir/../docs")/RESULT_SCHEMAS.md"
HTML="$BUNDLE_DIR/index.html"
CSS="$BUNDLE_DIR/floor.css"
JS="$BUNDLE_DIR/floor.js"

pass=0; fail=0; skip=0
ok()    { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no()    { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }
skipn() { skip=$((skip+1)); printf '  SKIPPED — %s\n' "$1"; }
SETUP_BROKEN=0
setup_fail() { SETUP_BROKEN=1; printf '  SETUP BROKEN: %s\n' "$1" >&2; exit 2; }

# ---- primitives: no `| grep -q`, no early-exiting consumer ----
has_lit() { local c; c="$(grep -c -F -- "$2" "$1" 2>/dev/null || true)"; case "$c" in ''|*[!0-9]*) return 1 ;; esac; [ "$c" -gt 0 ]; }
has_re()  { local c; c="$(grep -c -E -- "$2" "$1" 2>/dev/null || true)"; case "$c" in ''|*[!0-9]*) return 1 ;; esac; [ "$c" -gt 0 ]; }
# occ counts OCCURRENCES (not matching lines): "exactly one timer" is a per-occurrence claim
# and grep -c would happily read two setInterval calls on one line as 1.
occ() { awk -v pat="$2" 'BEGIN{n=0}{n+=gsub(pat,"")}END{print n+0}' "$1" 2>/dev/null; }
in_str() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

csum() {
  if   command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else cksum "$1" 2>/dev/null | cut -d' ' -f1; fi
}

# tree_sig — a path+content signature of a whole tree, via `find`. git is NEVER consulted:
# `.supervisor/` is IGNORED, not untracked, so `git status` reports neither an illegal write
# into it nor the legitimate one (the same blindness test-build-floor.sh case (k) measures).
tree_sig() {
  ( cd "$1" 2>/dev/null || return 1
    find . -mindepth 1 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do
      if [ -f "$p" ]; then printf '%s %s\n' "$p" "$(csum "$p")"; else printf '%s DIR\n' "$p"; fi
    done )
}

# mutant_ok — a mutation control that is not itself verified proves nothing. Every mutant must
# be non-empty, actually DIFFER from the original, and (for shell) still parse.
mutant_ok() {
  local orig="$1" mut="$2" shell="${3:-no}"
  [ -s "$mut" ] || { no "mutation control: the mutant $mut is empty"; return 1; }
  if cmp -s "$orig" "$mut"; then no "mutation control: the mutant $mut is identical to the original"; return 1; fi
  if [ "$shell" = "shell" ]; then
    bash -n "$mut" 2>/dev/null || { no "mutation control: the mutant $mut is not syntactically valid bash"; return 1; }
  fi
  return 0
}

for f in "$ENGINE" "$HTML" "$CSS" "$JS" "$SCHEMA_MD"; do
  [ -f "$f" ] || setup_fail "required input not found: $f"
done
[ -d "$FIX_DIR" ] || setup_fail "fixture directory not found: $FIX_DIR"
command -v jq >/dev/null 2>&1 || setup_fail "jq is required to run these assertions"
printf '{}' | jq -e . >/dev/null 2>&1 || setup_fail "jq is present but non-functional"
command -v python3 >/dev/null 2>&1 || setup_fail "python3 is required to run these assertions"

TMPROOT="$(mktemp -d)" || setup_fail "mktemp -d failed"
SERVE_PIDFILES=""
cleanup_files() {
  local pf pid
  for pf in $SERVE_PIDFILES; do
    [ -f "$pf" ] || continue
    while IFS= read -r pid; do
      case "$pid" in ''|*[!0-9]*) continue ;; esac
      kill "$pid" 2>/dev/null
    done < "$pf"
  done
  chmod -R u+rwX "$TMPROOT" >/dev/null 2>&1
  rm -r "$TMPROOT" >/dev/null 2>&1
}

# finish — the RESULT summary and the exit status BOTH live in the EXIT trap, and that is
# deliberate: it is what makes the `(z)` anchor at the very bottom of this file a LIVE seam.
# A summary printed inline would have to be the last statement, so anything subtask 3 appended
# below it would be dead code that silently never ran — a test group that cannot fail is worse
# than no test group. SETUP_BROKEN keeps `exit 2` (fixture broken) distinct from `exit 1`
# (assertions ran, something misbehaved), which the trap would otherwise flatten to 0.
finish() {
  cleanup_files
  [ "$SETUP_BROKEN" -eq 1 ] && exit 2
  echo
  echo "RESULT: $pass passed, $fail failed, $skip skipped"
  [ "$fail" -eq 0 ] || exit 1
  exit 0
}
trap finish EXIT INT TERM
mktmp() { mktemp -d "$TMPROOT/d.XXXXXX"; }

REAL_BUNDLE_SIG="$(tree_sig "$BUNDLE_DIR")"

# ===========================================================================
echo "(a) AC-no-egress — the bundle references nothing off this origin"
# ===========================================================================

# scan_egress <file> -> one line per finding, empty output = clean.
# The protocol-relative check is deliberately SCOPED to src=/href=/url(: floor.js is full of
# `//` line comments and a bare `//` scan would be a permanent false positive.
scan_egress() {
  local f="$1"
  grep -n -E 'https?://' "$f" 2>/dev/null | sed 's/^/absolute-url: /' || true
  grep -n -E '(src|href)[[:space:]]*=[[:space:]]*["'"'"']?//' "$f" 2>/dev/null | sed 's/^/protocol-relative: /' || true
  grep -n -E 'url\([[:space:]]*["'"'"']?//' "$f" 2>/dev/null | sed 's/^/protocol-relative-url: /' || true
  grep -n -E '@import' "$f" 2>/dev/null | sed 's/^/at-import: /' || true
  grep -n -E '@font-face' "$f" 2>/dev/null | sed 's/^/web-font: /' || true
  grep -n -E '<link[^>]*rel=["'"'"']?(preconnect|dns-prefetch|preload)' "$f" 2>/dev/null | sed 's/^/preconnect: /' || true
  grep -n -E 'url\(' "$f" 2>/dev/null | grep -v -E 'url\([[:space:]]*["'"'"']?data:' 2>/dev/null | sed 's/^/url-not-data: /' || true
}

egress_findings=""
for f in "$HTML" "$CSS" "$JS"; do
  out="$(scan_egress "$f")"
  [ -n "$out" ] && egress_findings="$egress_findings
$(basename "$f"): $out"
done
if [ -z "$egress_findings" ]; then
  ok "(a1) index.html / floor.css / floor.js carry no remote reference of any kind"
else
  no "(a1) index.html / floor.css / floor.js carry no remote reference of any kind" "$egress_findings"
fi

CSP_LINE='<meta http-equiv="Content-Security-Policy" content="default-src '"'"'self'"'"'; img-src '"'"'self'"'"' data:; connect-src '"'"'self'"'"'; style-src '"'"'self'"'"'; script-src '"'"'self'"'"'; font-src '"'"'self'"'"'">'
if has_lit "$HTML" "$CSP_LINE"; then
  ok "(a2) index.html carries the Content-Security-Policy meta line verbatim"
else
  no "(a2) index.html carries the Content-Security-Policy meta line verbatim" "expected: $CSP_LINE"
fi

if has_lit "$JS" "fetch('floor.json', { cache: 'no-store' })"; then
  ok "(a3) floor.js fetches the relative path floor.json with cache: 'no-store'"
else
  no "(a3) floor.js fetches the relative path floor.json with cache: 'no-store'"
fi
n_fetch="$(occ "$JS" 'fetch[(]')"
[ "$n_fetch" = "1" ] \
  && ok "(a4) floor.js makes exactly ONE fetch call (found $n_fetch)" \
  || no "(a4) floor.js makes exactly ONE fetch call" "found $n_fetch"

# Mutation control: the scanner must fire on a file that really does reach off-origin.
MUT_HTML="$TMPROOT/mut-index.html"
sed 's|<link rel="stylesheet" href="floor.css">|<link rel="stylesheet" href="//cdn.example.test/x.css">|' "$HTML" > "$MUT_HTML" 2>/dev/null
if mutant_ok "$HTML" "$MUT_HTML"; then
  mout="$(scan_egress "$MUT_HTML")"
  if [ -n "$mout" ] && in_str "$mout" "protocol-relative"; then
    ok "(a5) MUTATION CONTROL: a protocol-relative stylesheet href IS flagged by the scanner"
  else
    no "(a5) MUTATION CONTROL: a protocol-relative stylesheet href IS flagged by the scanner" "scanner said: ${mout:-<nothing>}"
  fi
fi

# ===========================================================================
echo "(b) AC-lanes / AC-stall / AC-three-states — static halves in floor.js"
# ===========================================================================

check_lit() { # file, literal, label
  if has_lit "$1" "$2"; then ok "$3"; else no "$3" "not found in $(basename "$1"): $2"; fi
}
check_lit "$JS" "identity unknown"        "(b1) floor.js renders the visible text 'identity unknown' for an untyped lane"
check_lit "$JS" "events"                  "(b2) floor.js renders an event count ('events')"
check_lit "$JS" "replace(/^(?:loomwright:)+/" "(b3) floor.js strips EVERY loomwright: prefix before matching the roster"
check_lit "$JS" "no event for"            "(b4) floor.js renders the stalled label 'no event for <age>'"
check_lit "$JS" "stalled"                 "(b5) floor.js uses the 'stalled' class token"
check_lit "$JS" "qpInt('stall'"           "(b6) floor.js reads the stall threshold from the ?stall= query parameter"
check_lit "$JS" "no floor.json at this origin" "(b7) state string: 'no floor.json at this origin'"
check_lit "$JS" "no run in flight"             "(b8) state string: 'no run in flight'"
check_lit "$JS" "floor.json is stale ("        "(b9) state string: 'floor.json is stale (<age>)'"

# --- THE IDLE BANNER MUST BE EARNED, NOT DEFAULTED -------------------------------------
# build-floor.sh OMITS `sessions.detail.current` whenever no log line carries a `ts`, and
# reports the surface `unverified` when a log could not be read. Rendering "no run in flight"
# from either shape is the omit-absent-evidence rule broken in the render layer: the projector
# refused to state whether a run is in flight, and the page would answer anyway. So the string
# must be reachable ONLY through a verdict that saw a COUNTED surface carrying a `current`
# view, and every other shape must get its own, differently-worded banner.
check_lit "$JS" "session data unavailable" "(b14) floor.js has a distinct banner for a sessions surface that cannot support the idle claim"
n_idle="$(occ "$JS" 'no run in flight')"
idle_ungated="$(awk '/no run in flight/ && $0 !~ /idle/ {n++} END{print n+0}' "$JS")"
[ "$n_idle" = "1" ] && [ "$idle_ungated" = "0" ] \
  && ok "(b15) the ONE 'no run in flight' emission is gated on the idle verdict (occurrences=$n_idle ungated=$idle_ungated)" \
  || no "(b15) every 'no run in flight' emission is gated on the idle verdict" "occurrences=$n_idle ungated=$idle_ungated"
verdict_body="$(awk '/^  function sessionsVerdict/{f=1} f{print} f&&/^  }$/{exit}' "$JS")"
if in_str "$verdict_body" "'counted'" && in_str "$verdict_body" "current"; then
  ok "(b16) the idle verdict is computed from the sessions surface's own status AND its current view"
else
  no "(b16) the idle verdict is computed from the sessions surface's own status AND its current view" "sessionsVerdict body: ${verdict_body:-<function not found>}"
fi
# Mutation control for (b15): ungating the banner must be CAUGHT, or the scan proves nothing.
MUT_IDLE="$TMPROOT/mut-idle.js"
sed 's/v\.idle ?/true ?/' "$JS" > "$MUT_IDLE" 2>/dev/null
if mutant_ok "$JS" "$MUT_IDLE"; then
  m_ungated="$(awk '/no run in flight/ && $0 !~ /idle/ {n++} END{print n+0}' "$MUT_IDLE")"
  [ "$m_ungated" = "1" ] \
    && ok "(b17) MUTATION CONTROL: an ungated 'no run in flight' IS flagged (found $m_ungated)" \
    || no "(b17) MUTATION CONTROL: an ungated 'no run in flight' IS flagged" "found $m_ungated"
fi
# The freshness banner must not assert a CAUSE it cannot observe. The page polls on its own
# fixed 2 s clock and has no way to see `serve --interval <n>`; with a legal `--interval 10`
# every render is older than a 6 s default threshold, so a claim that "nothing has regenerated
# it" would be false while regeneration is working. The banner may state the age and the
# threshold it was measured against — nothing more.
n_cause="$(occ "$JS" 'nothing has regenerated it')"
[ "$n_cause" = "0" ] \
  && ok "(b18) the stale banner makes no unobservable causal claim about regeneration (found $n_cause)" \
  || no "(b18) the stale banner makes no unobservable causal claim about regeneration" "found $n_cause occurrence(s) of 'nothing has regenerated it'"
if has_lit "$JS" "freshness threshold"; then
  ok "(b19) the stale banner names the threshold it measured against, so the reader can raise it"
else
  no "(b19) the stale banner names the threshold it measured against"
fi
# --- the poll cannot stack requests against a hung origin -------------------------------
if has_lit "$JS" "inFlight"; then
  ok "(b20) the poll carries an in-flight guard, so a hung origin cannot stack fetches"
else
  no "(b20) the poll carries an in-flight guard"
fi
n_clear="$(awk '/inFlight = false/ && $0 !~ /var[[:space:]]+inFlight/ {n++} END{print n+0}' "$JS")"
[ "$n_clear" -ge 2 ] 2>/dev/null \
  && ok "(b21) the in-flight guard is cleared on BOTH the resolve and the reject path (found $n_clear clear sites)" \
  || no "(b21) the in-flight guard is cleared on both the resolve and the reject path" "found $n_clear clear site(s) — a guard set and never cleared wedges the poll permanently"

# THE MOTION BUDGET. This is the assertion that makes "nothing animates that is not backed by
# an event" checkable rather than aspirational: one timer, and it fetches.
n_int="$(occ "$JS" 'setInterval[(]')"
n_raf="$(occ "$JS" 'requestAnimationFrame')"
n_to="$(occ "$JS" 'setTimeout[(]')"
[ "$n_int" = "1" ] \
  && ok "(b10) floor.js contains exactly ONE setInterval — the poll (found $n_int)" \
  || no "(b10) floor.js contains exactly ONE setInterval — the poll" "found $n_int"
[ "$n_raf" = "0" ] && [ "$n_to" = "0" ] \
  && ok "(b11) floor.js contains NO animation-frame or timeout callback (rAF=$n_raf setTimeout=$n_to)" \
  || no "(b11) floor.js contains NO animation-frame or timeout callback" "rAF=$n_raf setTimeout=$n_to"

# Motion is gated on a CHANGED event count, not on the clock.
if has_lit "$JS" "ev !== prev"; then
  ok "(b12) the shuttle advances only when this lane's events count differs from the previous render"
else
  no "(b12) the shuttle advances only when this lane's events count differs from the previous render"
fi

# Mutation control for (b10): a second timer must be caught.
MUT_JS="$TMPROOT/mut-floor.js"
{ cat "$JS"; printf '\nsetInterval(function () { document.body.style.opacity = 0.9; }, 16);\n'; } > "$MUT_JS" 2>/dev/null
if mutant_ok "$JS" "$MUT_JS"; then
  m_int="$(occ "$MUT_JS" 'setInterval[(]')"
  [ "$m_int" = "2" ] \
    && ok "(b13) MUTATION CONTROL: a second, purely decorative timer IS counted (found $m_int)" \
    || no "(b13) MUTATION CONTROL: a second, purely decorative timer IS counted" "found $m_int"
fi

# ===========================================================================
echo "(c) AC-motion-a11y-theme — floor.css"
# ===========================================================================

if has_lit "$CSS" "@media (prefers-reduced-motion: reduce)"; then
  ok "(c1) floor.css has a prefers-reduced-motion: reduce block"
else
  no "(c1) floor.css has a prefers-reduced-motion: reduce block"
fi
if has_lit "$CSS" "animation: none !important" && has_lit "$CSS" "transition: none !important"; then
  ok "(c2) the reduced-motion block removes BOTH animation and transition"
else
  no "(c2) the reduced-motion block removes BOTH animation and transition"
fi
if has_re "$CSS" '^:root \{'; then
  ok "(c3) the light palette is defined on bare :root (the default, no query required)"
else
  no "(c3) the light palette is defined on bare :root"
fi
if has_lit "$CSS" "@media (prefers-color-scheme: dark)" && has_lit "$CSS" ':root:not([data-theme="light"])'; then
  ok "(c4) dark is defined under prefers-color-scheme: dark for :root:not([data-theme=\"light\"])"
else
  no "(c4) dark is defined under prefers-color-scheme: dark for :root:not([data-theme=\"light\"])"
fi
if has_lit "$CSS" ':root[data-theme="dark"]'; then
  ok "(c5) dark is ALSO defined on an explicit :root[data-theme=\"dark\"]"
else
  no "(c5) dark is ALSO defined on an explicit :root[data-theme=\"dark\"]"
fi
if has_lit "$CSS" "background: var(--bg)"; then
  ok "(c6) body carries an explicit token background (var(--bg))"
else
  no "(c6) body carries an explicit token background (var(--bg))"
fi
n_kf="$(occ "$CSS" '@keyframes')"
[ "$n_kf" = "1" ] && has_lit "$CSS" "@keyframes pulse" \
  && ok "(c7) exactly ONE @keyframes exists and it is 'pulse' — the single stated exemption" \
  || no "(c7) exactly ONE @keyframes exists and it is 'pulse'" "found $n_kf @keyframes blocks"
if has_lit "$CSS" ".lane.pulse" && has_lit "$CSS" ".lane.stalled"; then
  ok "(c8) the pulse is applied per-lane and a stalled lane has its own rule (floor.js removes pulse when stalled)"
else
  no "(c8) the pulse is applied per-lane and a stalled lane has its own rule"
fi
if has_lit "$CSS" "border-style: dashed" && has_lit "$CSS" ".dot.hollow"; then
  ok "(c9) non-colour cues exist: dashed stalled lane border and a hollow read-only dot"
else
  no "(c9) non-colour cues exist: dashed stalled lane border and a hollow read-only dot"
fi
if has_lit "$JS" "read-only unknown"; then
  ok "(c10) an OMITTED read_only renders as 'read-only unknown', never as 'not read-only'"
else
  no "(c10) an OMITTED read_only renders as 'read-only unknown'"
fi
if has_lit "$HTML" "liveness unavailable — a lane shows recorded events, never a running process"; then
  ok "(c11) the permanent liveness note is rendered on every load"
else
  no "(c11) the permanent liveness note is rendered on every load"
fi
# Liveness words, scanned in BOTH the script that writes text and the markup that ships it.
# The leading [^-] excludes `aria-live`, an ARIA attribute that claims nothing about a
# process; the trailing [^ln] excludes "liveness", which is the word the permanent note uses
# to say the opposite. What is left is the word used as a LABEL, and there must be none.
n_live="$(( $(occ "$JS" '[^-][Ll]ive[^ln]') + $(occ "$HTML" '[^-][Ll]ive[^ln]') ))"
n_active="$(( $(occ "$JS" '[Aa]ctive') + $(occ "$HTML" '[Aa]ctive') ))"
# `active` legitimately appears as the CSS class for the highlighted pipeline stage, which is
# a phase marker and not a liveness claim, and never as rendered text (n_active for the MARKUP
# must be 0). The budget below allows the script's class handling and nothing in index.html.
n_active_html="$(occ "$HTML" '[Aa]ctive')"
[ "$n_live" = "0" ] && [ "$n_active_html" = "0" ] && [ "$n_active" -le 6 ] \
  && ok "(c12) no liveness word is rendered: 'live' as a label appears $n_live times, and 'active' $n_active_html times in the markup (only the stage class in the script, $n_active)" \
  || no "(c12) no liveness word is rendered" "live=$n_live active=$n_active active_in_markup=$n_active_html"

# ===========================================================================
echo "(d) AC-fixtures-conform — validated against the schema block, not a restated key list"
# ===========================================================================

# The key set comes OUT of the `## FLOOR_PROJECTION` block, exactly as test-build-floor.sh
# case (h) derives it. Restating the keys here would let a schema change pass unnoticed.
schema_block() {
  awk '/^## FLOOR_PROJECTION$/{f=1} f&&/^```yaml$/{y=1;next} y&&/^```$/{exit} y' "$SCHEMA_MD"
}
parse_required() { schema_block | sed -nE "s/^$1([a-z_]+):.*#[^#]*,[[:space:]]*required.*/\\1/p"; }
TOP_REQ="$(parse_required '  ')"; ENTRY_REQ="$(parse_required '    ')"
n_top="$(printf '%s\n' "$TOP_REQ" | awk 'NF{n++} END{print n+0}')"
n_ent="$(printf '%s\n' "$ENTRY_REQ" | awk 'NF{n++} END{print n+0}')"
[ "$n_top" -gt 0 ] && [ "$n_ent" -gt 0 ] \
  && ok "(d1) parsed $n_top top-level + $n_ent per-entry required keys out of the FLOOR_PROJECTION block" \
  || no "(d1) parsed no required keys from the schema block — every fixture assertion below would be vacuous"

validate_fixture() {
  local j="$1" rc=0 k sk st has_c sv
  [ "$n_top" -gt 0 ] && [ "$n_ent" -gt 0 ] || { echo "schema parse produced nothing"; return 2; }
  jq empty "$j" >/dev/null 2>&1 || { echo "not valid JSON"; return 1; }
  for k in $TOP_REQ; do
    jq -e --arg k "$k" 'has($k)' "$j" >/dev/null 2>&1 || { echo "missing required key: $k"; rc=1; }
  done
  sv="$(jq -r '.schema_version // "absent"' "$j" 2>/dev/null)"
  [ "$sv" = "1" ] || { echo "schema_version is $sv, not 1"; rc=1; }
  for sk in $(jq -r '.surfaces | keys[]' "$j" 2>/dev/null); do
    for k in $ENTRY_REQ; do
      jq -e --arg s "$sk" --arg k "$k" '.surfaces[$s] | has($k)' "$j" >/dev/null 2>&1 \
        || { echo "missing required key: surfaces.$sk.$k"; rc=1; }
    done
    st="$(jq -r --arg s "$sk" '.surfaces[$s].status // ""' "$j" 2>/dev/null)"
    has_c="$(jq -r --arg s "$sk" 'if (.surfaces[$s] | has("count")) then "y" else "n" end' "$j" 2>/dev/null)"
    case "$st" in
      counted)           [ "$has_c" = y ] || { echo "surfaces.$sk: status counted without count"; rc=1; } ;;
      absent|unverified) [ "$has_c" = n ] || { echo "surfaces.$sk: count present with status $st"; rc=1; } ;;
      *)                 echo "surfaces.$sk: status not in the documented enum: $st"; rc=1 ;;
    esac
  done
  return $rc
}

n_fix=0
for j in "$FIX_DIR"/*.json; do
  [ -f "$j" ] || continue
  n_fix=$((n_fix+1))
  vout="$(validate_fixture "$j" 2>&1)"; vrc=$?
  [ "$vrc" -eq 0 ] \
    && ok "(d2) $(basename "$j") conforms to the FLOOR_PROJECTION contract" \
    || no "(d2) $(basename "$j") conforms to the FLOOR_PROJECTION contract" "$vout"
done
[ "$n_fix" -eq 5 ] \
  && ok "(d3) all five committed fixtures were validated (found $n_fix)" \
  || no "(d3) all five committed fixtures were validated" "found $n_fix"

# Mutation control: a fixture that violates the omit-not-zero rule must be REJECTED.
MUT_FIX="$TMPROOT/mut-fixture.json"
jq '.surfaces.automate_runs.count = 0' "$FIX_DIR/floor-live.json" > "$MUT_FIX" 2>/dev/null
if mutant_ok "$FIX_DIR/floor-live.json" "$MUT_FIX"; then
  mout="$(validate_fixture "$MUT_FIX" 2>&1)"; mrc=$?
  [ "$mrc" -eq 1 ] && in_str "$mout" "count present with status absent" \
    && ok "(d4) MUTATION CONTROL: a fabricated count: 0 on an absent surface IS rejected by name" \
    || no "(d4) MUTATION CONTROL: a fabricated count: 0 on an absent surface IS rejected by name" "rc=$mrc out=$mout"
fi

# ===========================================================================
echo "(e) fixture facts the browser half will read"
# ===========================================================================

LIVE="$FIX_DIR/floor-live.json"; STALLED="$FIX_DIR/floor-stalled.json"
EMPTY="$FIX_DIR/floor-empty.json"; STALE="$FIX_DIR/floor-stale.json"
NOSESS="$FIX_DIR/floor-nosession.json"

n_rows="$(jq -r '.surfaces.sessions.detail.current.agents | length' "$LIVE" 2>/dev/null)"
n_typed="$(jq -r '[.surfaces.sessions.detail.current.agents[] | select(has("agent_type"))] | length' "$LIVE" 2>/dev/null)"
[ "$n_rows" = "3" ] && [ "$n_typed" = "2" ] \
  && ok "(e1) floor-live has exactly 3 lane rows, exactly 2 of them typed (rows=$n_rows typed=$n_typed)" \
  || no "(e1) floor-live has exactly 3 lane rows, exactly 2 of them typed" "rows=$n_rows typed=$n_typed"

# The two typed rows must resolve to roster names AFTER the doubled-prefix strip, or the
# browser half's "shows the roster name and colour" claim has nothing to resolve against.
unmatched="$(jq -r '
  (.surfaces.agents.detail.roster | map(.name)) as $names
  | [ .surfaces.sessions.detail.current.agents[]
      | select(has("agent_type"))
      | (.agent_type | sub("^(loomwright:)+";""))
      | select(. as $n | ($names | index($n)) == null) ]
  | join(",")' "$LIVE" 2>/dev/null)"
[ -z "$unmatched" ] \
  && ok "(e2) every typed row resolves to a roster name once the loomwright: prefixes are stripped" \
  || no "(e2) every typed row resolves to a roster name once the loomwright: prefixes are stripped" "unmatched: $unmatched"

# The tri-state carried from the projector: a roster row with NO read_only key at all.
n_ro_absent="$(jq -r '[.surfaces.agents.detail.roster[] | select(has("read_only") | not)] | length' "$LIVE" 2>/dev/null)"
[ "$n_ro_absent" -ge 1 ] 2>/dev/null \
  && ok "(e3) floor-live exercises the read_only TRI-STATE: $n_ro_absent roster row(s) omit the key entirely" \
  || no "(e3) floor-live exercises the read_only tri-state (a roster row omitting read_only)" "found $n_ro_absent"

n_stalled="$(jq -r '
  .generated_at_epoch as $g
  | [ .surfaces.sessions.detail.current.agents[]
      | select((.last_ts | fromdateiso8601) < ($g - 300)) ] | length' "$STALLED" 2>/dev/null)"
[ "$n_stalled" = "1" ] \
  && ok "(e4) floor-stalled has exactly ONE row older than the 300 s default threshold" \
  || no "(e4) floor-stalled has exactly ONE row older than the 300 s default threshold" "found $n_stalled"
n_stalled_live="$(jq -r '
  .generated_at_epoch as $g
  | [ .surfaces.sessions.detail.current.agents[]
      | select((.last_ts | fromdateiso8601) < ($g - 300)) ] | length' "$LIVE" 2>/dev/null)"
[ "$n_stalled_live" = "0" ] \
  && ok "(e5) CONTROL: floor-live has NO stalled row, so the stalled class is discriminating" \
  || no "(e5) CONTROL: floor-live has NO stalled row" "found $n_stalled_live"

# A stage cell that must render an em dash rather than 0.
e_absent="$(jq -r '.surfaces.jobs_pending | "\(.status)/\(has("count"))/\(has("reason"))"' "$STALLED" 2>/dev/null)"
[ "$e_absent" = "absent/false/true" ] \
  && ok "(e6) floor-stalled's Queue surface is absent with a reason and NO count — the em-dash path" \
  || no "(e6) floor-stalled's Queue surface is absent with a reason and NO count" "got $e_absent"

# floor-empty is the GENUINELY IDLE case, and that is a MEASURED zero rather than an absent
# one: the sessions surface is counted, the newest session WAS identified, and no line of it
# carried an agent_id — which the projector records by omitting `agents` from `current`
# (never by emitting `[]`, per the omit-not-zero rule). This is the only shape from which
# "no run in flight" may be rendered.
e_empty="$(jq -r '"\(.surfaces.agents.status)/\(.surfaces.state.status)/\(.surfaces.sessions.status)/\(.surfaces.sessions.detail | has("current"))/\(.surfaces.sessions.detail.current | has("agents"))"' "$EMPTY" 2>/dev/null)"
[ "$e_empty" = "counted/absent/counted/true/false" ] \
  && ok "(e7) floor-empty is the earned 'no run in flight': sessions counted, a current session identified, zero agents in it" \
  || no "(e7) floor-empty is the earned 'no run in flight': sessions counted, current present, zero agents" "got $e_empty"

# floor-nosession is the CONTRAST, and it is the shape build-floor.sh really emits when no
# log line carries a `ts`: sessions COUNTED (so the surface is not absent and not unverified)
# but `current` OMITTED entirely with a note saying why — while `state` still records a phase.
# A page that renders this as "no run in flight" contradicts the state surface beside it.
e_nos="$(jq -r '"\(.surfaces.sessions.status)/\(.surfaces.sessions.detail | has("current"))/\(.surfaces.state.detail.phase)"' "$NOSESS" 2>/dev/null)"
[ "$e_nos" = "counted/false/EXECUTE" ] \
  && ok "(e9) floor-nosession: sessions counted with NO current view, beside a state surface recording phase EXECUTE" \
  || no "(e9) floor-nosession: sessions counted with NO current view, beside a state surface recording phase EXECUTE" "got $e_nos"
n_snote="$(jq -r '[.notes[] | select(startswith("sessions "))] | length' "$NOSESS" 2>/dev/null)"
[ "$n_snote" -ge 1 ] 2>/dev/null \
  && ok "(e10) floor-nosession carries the projector note the page reads its reason from ($n_snote sessions note(s))" \
  || no "(e10) floor-nosession carries a sessions note for the page to quote" "found $n_snote — the page would have nothing but its named fallback"

g_live="$(jq -r '.generated_at_epoch' "$LIVE" 2>/dev/null)"
g_stale="$(jq -r '.generated_at_epoch' "$STALE" 2>/dev/null)"
if [ "$g_stale" -lt $((g_live - 86400)) ] 2>/dev/null; then
  ok "(e8) floor-stale's generation time is more than a day older than floor-live's ($g_stale vs $g_live) — stale under any sane threshold"
else
  no "(e8) floor-stale's generation time is far older than floor-live's" "stale=$g_stale live=$g_live"
fi

# ===========================================================================
echo "(f) AC-engine-contract — check / apply / idempotency / drift / remove"
# ===========================================================================

F="$(mktmp)" || setup_fail "mktemp under $TMPROOT failed"
UI="$F/ui"

out="$(bash "$ENGINE" check --ui-dir "$UI" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && in_str "$out" "UI readiness: not configured" \
  && ok "(f1) check on an absent ui dir reports 'not configured' and exits 0" \
  || no "(f1) check on an absent ui dir reports 'not configured' and exits 0" "rc=$rc :: $out"
[ -d "$UI" ] && no "(f2) check WRITES NOTHING" "check created $UI" || ok "(f2) check writes nothing (the ui dir still does not exist)"

out="$(bash "$ENGINE" apply --ui-dir "$UI" 2>&1)"; rc=$?
missing=""
for b in index.html floor.css floor.js .loomwright-ui-module; do
  [ -f "$UI/$b" ] || missing="$missing $b"
done
[ "$rc" -eq 0 ] && [ -z "$missing" ] && in_str "$out" "apply: installed" \
  && ok "(f3) apply installs the three bundle files and the ownership marker" \
  || no "(f3) apply installs the three bundle files and the ownership marker" "rc=$rc missing:$missing :: $out"

drifted=""
for b in index.html floor.css floor.js; do
  cmp -s "$BUNDLE_DIR/$b" "$UI/$b" || drifted="$drifted $b"
done
[ -z "$drifted" ] && ok "(f4) every installed file is byte-identical to the plugin's copy" \
  || no "(f4) every installed file is byte-identical to the plugin's copy" "differs:$drifted"

out="$(bash "$ENGINE" apply --ui-dir "$UI" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && in_str "$out" "apply: no-op — already configured" \
  && ok "(f5) a second apply is 'no-op — already configured'" \
  || no "(f5) a second apply is 'no-op — already configured'" "rc=$rc :: $out"

printf '/* local edit */\n' >> "$UI/floor.css"
out="$(bash "$ENGINE" apply --ui-dir "$UI" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && in_str "$out" "apply: updated" && in_str "$out" "floor.css" \
  && ok "(f6) a drifted bundle is 'apply: updated' and NAMES the changed file"  \
  || no "(f6) a drifted bundle is 'apply: updated' and NAMES the changed file" "rc=$rc :: $out"
cmp -s "$BUNDLE_DIR/floor.css" "$UI/floor.css" \
  && ok "(f7) the drifted file was actually restored to the plugin's bytes" \
  || no "(f7) the drifted file was actually restored to the plugin's bytes"

out="$(bash "$ENGINE" check --ui-dir "$UI" 2>&1)"
in_str "$out" "UI readiness: configured" \
  && ok "(f8) check reports 'configured' once the bundle matches" \
  || no "(f8) check reports 'configured' once the bundle matches" "$out"

# A directory this module did not create must survive both apply and remove.
FOREIGN="$F/foreign"
mkdir -p "$FOREIGN" && printf 'the user keeps this\n' > "$FOREIGN/precious.txt"
fsig_before="$(tree_sig "$FOREIGN")"
out="$(bash "$ENGINE" apply --ui-dir "$FOREIGN" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && in_str "$out" "apply: WITHHELD" \
  && ok "(f9) apply WITHHOLDS on a directory with no marker" \
  || no "(f9) apply WITHHOLDS on a directory with no marker" "rc=$rc :: $out"
out="$(bash "$ENGINE" remove --ui-dir "$FOREIGN" 2>&1)"; rc=$?
fsig_after="$(tree_sig "$FOREIGN")"
[ "$rc" -eq 0 ] && in_str "$out" "remove: WITHHELD" && [ -d "$FOREIGN" ] && [ "$fsig_before" = "$fsig_after" ] \
  && ok "(f10) remove WITHHOLDS on a directory with no marker and PRESERVES it byte for byte" \
  || no "(f10) remove WITHHOLDS on a directory with no marker and PRESERVES it" "rc=$rc dir=$([ -d "$FOREIGN" ] && echo present || echo GONE) :: $out"

out="$(bash "$ENGINE" remove --ui-dir "$UI" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && in_str "$out" "remove: removed" && [ ! -d "$UI" ] \
  && ok "(f11) remove deletes an OWNED ui dir (marker present) and reports it" \
  || no "(f11) remove deletes an OWNED ui dir (marker present) and reports it" "rc=$rc :: $out"

# MUTATION CONTROL for (f10): strip the marker gate and the foreign directory dies. Without
# this, (f10) would also pass against an engine that simply never deletes anything.
# The mutant lives in its OWN directory: the engine resolves `script_dir` from $0 and refuses
# to delete anything at or under it, so a mutant sitting in $TMPROOT would be saved by THAT
# guard instead of the marker gate and the control would report a pass it did not earn.
MUT_ENG_DIR="$TMPROOT/mutbin"
mkdir -p "$MUT_ENG_DIR" || setup_fail "(f12) fixture: could not create $MUT_ENG_DIR"
MUT_ENG="$MUT_ENG_DIR/setup-ui.sh"
sed -e 's/^  if ! is_ours; then$/  if false; then/' \
    -e 's/^  if \[ ! -f "\$resolved\/\$MARKER" \]; then$/  if false; then/' "$ENGINE" > "$MUT_ENG" 2>/dev/null
# THREE sites, not two: `if ! is_ours; then` appears in do_check as well as in do_remove, and
# the resolved-path assertion is the third. do_apply's guard is `[ -d ... ] && ! is_ours` and
# is deliberately left intact, so the mutant changes only the removal path.
n_rev="$(occ "$MUT_ENG" 'if false; then')"
[ "$n_rev" = "3" ] || setup_fail "(f12) fixture: the mutant reverted $n_rev of the 3 marker assertions, so the control would not be testing the gate"
if mutant_ok "$ENGINE" "$MUT_ENG" shell; then
  FOREIGN2="$F/foreign2"; mkdir -p "$FOREIGN2"; printf 'x\n' > "$FOREIGN2/precious.txt"
  bash "$MUT_ENG" remove --ui-dir "$FOREIGN2" >/dev/null 2>&1
  [ ! -d "$FOREIGN2" ] \
    && ok "(f12) MUTATION CONTROL: with BOTH marker assertions reverted the foreign directory IS deleted — the gate is what saves it" \
    || no "(f12) MUTATION CONTROL: with BOTH marker assertions reverted the foreign directory IS deleted" "the mutant left $FOREIGN2 in place, so (f10) may be passing for the wrong reason"
fi

# --- a --ui-dir that is itself a SYMLINK ------------------------------------------------
# `remove` reports what it deleted, and that report has to be TRUE. Unlinking a symlink
# leaves every byte of the target — the bundle, the marker and the floor.json copy, which
# carry branch names, session ids and agent ids — sitting on disk under a message saying they
# are gone. Refusing is the only honest answer.
SLTGT="$F/link-target"
mkdir -p "$SLTGT" || setup_fail "(f13) fixture: could not create $SLTGT"
printf 'the user keeps this\n' > "$SLTGT/precious.txt"
printf 'marker\n' > "$SLTGT/.loomwright-ui-module"
SLINK="$F/ui-link"
ln -s "$SLTGT" "$SLINK" || setup_fail "(f13) fixture: could not create the symlink $SLINK"
[ -L "$SLINK" ] || setup_fail "(f13) fixture: $SLINK is not a symlink, so the case below would test nothing"
sl_before="$(tree_sig "$SLTGT")"
out="$(bash "$ENGINE" remove --ui-dir "$SLINK" 2>&1)"; rc=$?
sl_after="$(tree_sig "$SLTGT")"
if [ "$rc" -eq 0 ] && ! in_str "$out" "remove: removed" && [ -L "$SLINK" ] && [ "$sl_before" = "$sl_after" ]; then
  ok "(f13) remove REFUSES a --ui-dir that is itself a symlink, leaves the link in place and does not claim a removal"
else
  no "(f13) remove REFUSES a --ui-dir that is itself a symlink and does not claim a removal" \
     "rc=$rc link=$([ -L "$SLINK" ] && echo present || echo UNLINKED) target-unchanged=$([ "$sl_before" = "$sl_after" ] && echo yes || echo NO) :: $out"
fi

# --- the refusals must compare against the PHYSICAL path --------------------------------
# `remove` refuses `/`, `$HOME` and the plugin install dir. Resolving with bash's LOGICAL
# pwd makes all three blind to a symlinked parent: the path they compare is the link path,
# never the real target. Here the ui dir is a real directory whose PHYSICAL path IS the home
# directory, reached through a symlinked parent — the $HOME refusal must still fire.
FH="$F/fakehome"
FHUI="$FH/home-itself"
mkdir -p "$FHUI" || setup_fail "(f14) fixture: could not create $FHUI"
printf 'marker\n' > "$FHUI/.loomwright-ui-module"
printf 'the user keeps this\n' > "$FHUI/precious.txt"
PLINK="$F/parent-link"
ln -s "$FH" "$PLINK" || setup_fail "(f14) fixture: could not create the symlink $PLINK"
[ ! -L "$PLINK/home-itself" ] || setup_fail "(f14) fixture: the ui dir must NOT itself be a symlink, or (f13)'s guard would answer instead"
fh_before="$(tree_sig "$FHUI")"
out="$(HOME="$FHUI" bash "$ENGINE" remove --ui-dir "$PLINK/home-itself" 2>&1)"; rc=$?
fh_after="$(tree_sig "$FHUI")"
if [ "$rc" -eq 0 ] && in_str "$out" "remove: ABORTED" && [ -d "$FHUI" ] && [ "$fh_before" = "$fh_after" ]; then
  ok "(f14) the \$HOME refusal fires through a symlinked parent — the resolved path is the PHYSICAL one"
else
  no "(f14) the \$HOME refusal fires through a symlinked parent (physical resolution)" \
     "rc=$rc dir=$([ -d "$FHUI" ] && echo present || echo GONE) unchanged=$([ "$fh_before" = "$fh_after" ] && echo yes || echo NO) :: $out"
fi

# ===========================================================================
echo "(g) AC-engine-fail-safe — every branch exits 0, each with a named reason"
# ===========================================================================

# mkstub — a PATH containing symlinks to the commands the engine needs, MINUS the omitted one.
STUB_CMDS="dirname basename cp cmp mkdir rm mv ps sleep cut cat sed grep awk find sort head tail wc chmod ls touch shasum sha256sum cksum date stat git bash sh jq python3 curl kill"
mkstub() {
  local dir="$1" omit="$2" c p
  mkdir -p "$dir" || return 1
  for c in $STUB_CMDS; do
    case " $omit " in *" $c "*) continue ;; esac
    p="$(command -v "$c" 2>/dev/null)" || continue
    [ -n "$p" ] && ln -sf "$p" "$dir/$c" 2>/dev/null
  done
  return 0
}

G="$(mktmp)"; GUI="$G/ui"
bash "$ENGINE" apply --ui-dir "$GUI" >/dev/null 2>&1
[ -f "$GUI/index.html" ] || setup_fail "(g) fixture: apply did not install into $GUI"

STUB_NOPY="$G/bin-nopy"
mkstub "$STUB_NOPY" "python3" || setup_fail "(g) fixture: could not build the python3-absent PATH stub"
[ ! -e "$STUB_NOPY/python3" ] || setup_fail "(g) fixture: the python3-absent stub still contains python3"
out="$(PATH="$STUB_NOPY" bash "$ENGINE" serve --ui-dir "$GUI" --no-regen 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && in_str "$out" "serve: ABORTED — python3 not found" \
  && ok "(g1) with python3 absent, serve aborts by name and exits 0" \
  || no "(g1) with python3 absent, serve aborts by name and exits 0" "rc=$rc :: $out"

STUB_NOJQ="$G/bin-nojq"
mkstub "$STUB_NOJQ" "jq" || setup_fail "(g) fixture: could not build the jq-absent PATH stub"
[ ! -e "$STUB_NOJQ/jq" ] || setup_fail "(g) fixture: the jq-absent stub still contains jq"
JQUI="$G/ui-nojq"
out="$(PATH="$STUB_NOJQ" bash "$ENGINE" apply --ui-dir "$JQUI" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$JQUI/index.html" ] && in_str "$out" "apply: installed" \
  && ok "(g2) with jq absent, apply still copies the bundle (the bundle needs no jq)" \
  || no "(g2) with jq absent, apply still copies the bundle" "rc=$rc :: $out"

jq_port="$(python3 -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()' 2>/dev/null)"
case "$jq_port" in ''|*[!0-9]*) setup_fail "(g) fixture: could not obtain a free port for the jq-absent serve probe" ;; esac
out="$(PATH="$STUB_NOJQ" bash "$ENGINE" serve --ui-dir "$JQUI" --port "$jq_port" --detach 2>&1)"; rc=$?
SERVE_PIDFILES="$SERVE_PIDFILES $JQUI/serve.pid"
[ "$rc" -eq 0 ] && in_str "$out" "jq not found" && in_str "$out" "will NOT be regenerated" \
  && ok "(g3) with jq absent, serve reports that build-floor.sh will skip rather than pretending to regenerate" \
  || no "(g3) with jq absent, serve reports that build-floor.sh will skip" "rc=$rc :: $out"
PATH="$STUB_NOJQ" bash "$ENGINE" stop --ui-dir "$JQUI" >/dev/null 2>&1

# build-floor.sh absent: the engine ALONE in a directory, so its sibling resolution finds
# nothing. This is also the honest shape of a broken plugin install.
LONE="$G/lone"; mkdir -p "$LONE"
cp "$ENGINE" "$LONE/setup-ui.sh" || setup_fail "(g) fixture: could not stage a lone engine copy"
LUI="$G/lone-ui"; mkdir -p "$LUI"
printf 'marker\n' > "$LUI/.loomwright-ui-module"
printf '<!doctype html>\n' > "$LUI/index.html"
out="$(bash "$LONE/setup-ui.sh" serve --ui-dir "$LUI" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && in_str "$out" "serve: ABORTED — build-floor.sh not found" \
  && ok "(g4) with build-floor.sh missing, serve aborts by name and exits 0" \
  || no "(g4) with build-floor.sh missing, serve aborts by name and exits 0" "rc=$rc :: $out"

bad_rc=""
for args in "wibble" "check --nope" "stop" "remove"; do
  # shellcheck disable=SC2086
  bash "$ENGINE" $args --ui-dir "$G/nowhere" >/dev/null 2>&1
  r=$?
  [ "$r" -eq 0 ] || bad_rc="$bad_rc [$args=>$r]"
done
[ -z "$bad_rc" ] \
  && ok "(g5) an unknown subcommand, an unknown flag, stop with no pidfile and remove with no dir ALL exit 0" \
  || no "(g5) every branch exits 0" "non-zero:$bad_rc"

out="$(bash "$ENGINE" wibble --ui-dir "$G/nowhere" 2>&1)"
in_str "$out" "unknown subcommand" \
  && ok "(g6) an unknown subcommand says so and prints the usage line" \
  || no "(g6) an unknown subcommand says so and prints the usage line" "$out"

# HOME unset. The default ui dir is built from $HOME, and `set -u` turns an unset one into an
# abort with a bash diagnostic and rc=1 — which contradicts "EVERY branch exits 0" in this
# file's own header. A cron job, a container and a `sudo -i` all reach this branch.
if env -u HOME true >/dev/null 2>&1; then
  probe_home="$(env -u HOME bash -c 'printf %s "${HOME:-<unset>}"' 2>/dev/null)"
  if [ "$probe_home" != "<unset>" ]; then
    skipn "(g7) this bash repopulates HOME even when the environment omits it, so the branch cannot be reached from here"
  else
    out="$(env -u HOME bash "$ENGINE" check 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && in_str "$out" "HOME" \
      && ok "(g7) with HOME unset and no --ui-dir, the engine aborts with a named reason and exits 0" \
      || no "(g7) with HOME unset and no --ui-dir, the engine aborts with a named reason and exits 0" "rc=$rc :: $out"
    out="$(env -u HOME bash "$ENGINE" check --ui-dir "$G/nowhere" 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && in_str "$out" "UI readiness: not configured" \
      && ok "(g8) with HOME unset but --ui-dir given, the engine works normally" \
      || no "(g8) with HOME unset but --ui-dir given, the engine works normally" "rc=$rc :: $out"
  fi
else
  skipn "(g7/g8) \`env -u\` is unavailable on this host, so the HOME-unset branch cannot be exercised"
fi

# `--interval` is unbounded, and the page's freshness threshold is derived from the page's own
# fixed 2 s poll — it cannot see this flag. When 3x the interval exceeds that default, serve
# must hand the reader the `?stale=` value to open the page with, or the page renders a stale
# banner for a document that is being regenerated exactly as configured.
hint_port="$(python3 -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()' 2>/dev/null)"
case "$hint_port" in ''|*[!0-9]*) setup_fail "(g9) fixture: could not obtain a free port for the interval-hint probe" ;; esac
HINTUI="$G/ui-hint"
bash "$ENGINE" apply --ui-dir "$HINTUI" >/dev/null 2>&1
[ -f "$HINTUI/index.html" ] || setup_fail "(g9) fixture: apply did not install into $HINTUI"
out="$(bash "$ENGINE" serve --ui-dir "$HINTUI" --no-regen --detach --port "$hint_port" --interval 10 2>&1)"; rc=$?
SERVE_PIDFILES="$SERVE_PIDFILES $HINTUI/serve.pid"
[ "$rc" -eq 0 ] && in_str "$out" "?stale=30" \
  && ok "(g9) with --interval 10, serve prints the ?stale=30 the page needs to avoid a false stale banner" \
  || no "(g9) with --interval 10, serve prints the ?stale= value the page needs" "rc=$rc :: $out"
bash "$ENGINE" stop --ui-dir "$HINTUI" >/dev/null 2>&1

# The engine mirrors two of the page's constants to compute that hint, and a mirror nobody
# checks is a mirror that rots. These are derived from floor.js itself, never restated here.
js_poll="$(awk -F'[ =;]+' '/^ *var POLL_MS = / {print $4; exit}' "$JS")"
eng_poll="$(awk -F= '/^PAGE_POLL_SEC=/ {print $2; exit}' "$ENGINE")"
eng_stale="$(awk -F= '/^PAGE_STALE_DEFAULT=/ {print $2; exit}' "$ENGINE")"
case "${js_poll:-x}${eng_poll:-x}${eng_stale:-x}" in
  *[!0-9]*) no "(g11) the engine's mirrored page constants match floor.js" "could not parse them (js POLL_MS='$js_poll' engine poll='$eng_poll' stale='$eng_stale') — the assertion would be vacuous" ;;
  *)
    [ "$eng_poll" = "$((js_poll / 1000))" ] && [ "$eng_stale" = "$((eng_poll * 3))" ] \
      && ok "(g11) the engine's mirrored page constants match floor.js (poll ${eng_poll}s, default threshold ${eng_stale}s = 3x)" \
      || no "(g11) the engine's mirrored page constants match floor.js" "floor.js polls every $((js_poll / 1000))s; the engine believes ${eng_poll}s with a ${eng_stale}s threshold — the ?stale= hint would be computed against the wrong default" ;;
esac

# CONTROL: at the default interval the page default already covers the cadence, so there is
# nothing to say and serve must not invent a parameter the user did not need.
hint_port2="$(python3 -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()' 2>/dev/null)"
case "$hint_port2" in ''|*[!0-9]*) setup_fail "(g10) fixture: could not obtain a second free port" ;; esac
out="$(bash "$ENGINE" serve --ui-dir "$HINTUI" --no-regen --detach --port "$hint_port2" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ! in_str "$out" "?stale=" \
  && ok "(g10) CONTROL: at the default interval serve prints no ?stale= hint — the hint is interval-driven, not decoration" \
  || no "(g10) CONTROL: at the default interval serve prints no ?stale= hint" "rc=$rc :: $out"
bash "$ENGINE" stop --ui-dir "$HINTUI" >/dev/null 2>&1

# ===========================================================================
echo "(h) AC-loopback — a real server, a real fetch, and a refused off-host connect"
# ===========================================================================

H="$(mktmp)"; HUI="$H/ui"
bash "$ENGINE" apply --ui-dir "$HUI" >/dev/null 2>&1
cp "$LIVE" "$HUI/floor.json" || setup_fail "(h) fixture: could not stage floor.json into $HUI"
port="$(python3 -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()' 2>/dev/null)"
case "$port" in ''|*[!0-9]*) setup_fail "(h) fixture: could not obtain a free port" ;; esac

# CODE ONLY. The engine's header comment carries both `python3 -m http.server` and
# `--bind 127.0.0.1` on ONE line, so a whole-file scan was partly satisfied by PROSE — and
# reported "2 invocations" where the engine has one. A comment that claims the bind is not
# the bind; excluding `^\s*#` is what makes these two assertions about the code.
binds="$(awk '$0 !~ /^[[:space:]]*#/ && /python3 -m http[.]server/ { t++; if ($0 ~ /--bind 127\.0\.0\.1/) b++ } END { print (t+0) " " (b+0) }' "$ENGINE")"
n_bind="${binds%% *}"; n_loop="${binds##* }"
[ "$n_bind" = "1" ] 2>/dev/null && [ "$n_loop" = "1" ] \
  && ok "(h1) setup-ui.sh has exactly ONE non-comment http.server invocation and it passes --bind 127.0.0.1" \
  || no "(h1) setup-ui.sh has exactly ONE non-comment http.server invocation carrying --bind 127.0.0.1" "invocations=$n_bind bound=$n_loop"
# MUTATION CONTROL: drop the flag from the one real invocation and the count must diverge.
# Without this, (h1) would also pass against a scan that matched nothing at all.
MUT_BIND="$TMPROOT/mut-bind.sh"
sed 's/python3 -m http.server --bind 127.0.0.1/python3 -m http.server/' "$ENGINE" > "$MUT_BIND" 2>/dev/null
if mutant_ok "$ENGINE" "$MUT_BIND" shell; then
  mb="$(awk '$0 !~ /^[[:space:]]*#/ && /python3 -m http[.]server/ { t++; if ($0 ~ /--bind 127\.0\.0\.1/) b++ } END { print (t+0) " " (b+0) }' "$MUT_BIND")"
  [ "${mb%% *}" = "1" ] && [ "${mb##* }" = "0" ] \
    && ok "(h2) MUTATION CONTROL: an invocation with the loopback bind removed IS caught (invocations=${mb%% *} bound=${mb##* })" \
    || no "(h2) MUTATION CONTROL: an invocation with the loopback bind removed IS caught" "got invocations=${mb%% *} bound=${mb##* }"
fi

out="$(bash "$ENGINE" serve --no-regen --detach --port "$port" --ui-dir "$HUI" 2>&1)"; rc=$?
SERVE_PIDFILES="$SERVE_PIDFILES $HUI/serve.pid"
if [ "$rc" -ne 0 ] || [ ! -f "$HUI/serve.pid" ]; then
  no "(h3) serve --detach starts and records its pid" "rc=$rc :: $out"
else
  ok "(h3) serve --detach starts and records its pid in $HUI/serve.pid"

  # Poll for readiness. Reading a detached process's side effect immediately is a race.
  ready=0; i=0
  while [ "$i" -lt 40 ]; do
    if python3 -c 'import socket,sys
s = socket.socket(); s.settimeout(1)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
except Exception:
    sys.exit(1)
finally:
    s.close()' "$port" >/dev/null 2>&1; then ready=1; break; fi
    sleep 0.25; i=$((i+1))
  done

  if [ "$ready" -ne 1 ]; then
    no "(h4) the loopback listener accepts a connection on 127.0.0.1:$port" "never became ready"
  else
    GOT="$H/got.json"
    if command -v curl >/dev/null 2>&1; then
      curl -s -o "$GOT" "http://127.0.0.1:$port/floor.json" 2>/dev/null
    else
      python3 -c 'import sys, urllib.request
sys.stdout.flush()
open(sys.argv[2], "wb").write(urllib.request.urlopen(sys.argv[1], timeout=5).read())' \
        "http://127.0.0.1:$port/floor.json" "$GOT" >/dev/null 2>&1
    fi
    if [ -s "$GOT" ] && cmp -s "$GOT" "$LIVE"; then
      ok "(h4) a fetch of http://127.0.0.1:$port/floor.json returns the fixture bytes exactly"
    else
      no "(h4) a fetch of 127.0.0.1:$port/floor.json returns the fixture bytes exactly" "got $( [ -f "$GOT" ] && wc -c < "$GOT" | tr -d ' ' || echo 0) bytes"
    fi

    # The off-host half. A pass here means the listener is genuinely not reachable from this
    # machine's routable address — the whole point of --bind 127.0.0.1.
    extip="$(python3 -c 'import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.connect(("192.0.2.1", 80))
    ip = s.getsockname()[0]
except Exception:
    ip = ""
finally:
    s.close()
print("" if (not ip or ip.startswith("127.")) else ip)' 2>/dev/null)"
    if [ -z "$extip" ]; then
      skipn "no non-loopback address"
    else
      verdict="$(python3 -c 'import socket, sys
s = socket.socket(); s.settimeout(2)
try:
    s.connect((sys.argv[1], int(sys.argv[2])))
    print("CONNECTED")
except Exception:
    print("REFUSED")
finally:
    s.close()' "$extip" "$port" 2>/dev/null)"
      [ "$verdict" = "REFUSED" ] \
        && ok "(h5) a TCP connect to this host's non-loopback address $extip:$port is REFUSED" \
        || no "(h5) a TCP connect to this host's non-loopback address $extip:$port is REFUSED" "verdict=$verdict — the listener is reachable off the loopback interface"
    fi
  fi

  out="$(bash "$ENGINE" stop --ui-dir "$HUI" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && in_str "$out" "stop:" && [ ! -f "$HUI/serve.pid" ] \
    && ok "(h6) stop kills the recorded server and clears the pidfile" \
    || no "(h6) stop kills the recorded server and clears the pidfile" "rc=$rc :: $out"
fi

# ===========================================================================
echo "(i) AC-remove-residue — two hashed trees, plus the plugin bundle"
# ===========================================================================
# SCOPE, stated explicitly: this assertion covers exactly two trees — the fixture PARENT that
# holds the ui dir, and the fixture GIT REPO used as the working directory (because `serve`
# without --no-regen runs build-floor.sh in the CWD, and that one out-of-ui-dir write must
# land there, never in this checkout). It says nothing about the rest of the filesystem.

R="$(mktmp)"; RUI="$R/ui"
REPO="$(mktmp)"
( cd "$REPO" && git init -q . ) >/dev/null 2>&1
[ -d "$REPO/.git" ] || setup_fail "(i) fixture: git init did not produce a repo at $REPO"
printf '# fixture\n' > "$REPO/README.md"

parent_before="$(tree_sig "$R")"
repo_before="$(tree_sig "$REPO")"
bundle_before="$(tree_sig "$BUNDLE_DIR")"

rport="$(python3 -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()' 2>/dev/null)"
case "$rport" in ''|*[!0-9]*) setup_fail "(i) fixture: could not obtain a free port" ;; esac

(
  cd "$REPO" || exit 1
  bash "$ENGINE" apply --ui-dir "$RUI" >/dev/null 2>&1
  bash "$ENGINE" serve --detach --interval 1 --port "$rport" --ui-dir "$RUI" >/dev/null 2>&1
) || setup_fail "(i) fixture: the apply/serve sequence could not be run from $REPO"
SERVE_PIDFILES="$SERVE_PIDFILES $RUI/serve.pid"
sleep 2
bash "$ENGINE" stop --ui-dir "$RUI" >/dev/null 2>&1
sleep 2
out="$(bash "$ENGINE" remove --ui-dir "$RUI" 2>&1)"

parent_after="$(tree_sig "$R")"
repo_after="$(tree_sig "$REPO")"
bundle_after="$(tree_sig "$BUNDLE_DIR")"

[ "$parent_before" = "$parent_after" ] \
  && ok "(i1) the fixture parent contains nothing that was not there before the whole sequence" \
  || no "(i1) the fixture parent contains nothing that was not there before" "$(printf '%s\n' "$parent_after" | LC_ALL=C sort > "$TMPROOT/pa"; printf '%s\n' "$parent_before" | LC_ALL=C sort > "$TMPROOT/pb"; diff "$TMPROOT/pb" "$TMPROOT/pa" 2>/dev/null | head -20)"

printf '%s\n' "$repo_before" > "$TMPROOT/rb"
printf '%s\n' "$repo_after"  > "$TMPROOT/ra"
added="$(diff "$TMPROOT/rb" "$TMPROOT/ra" 2>/dev/null | sed -n 's/^> //p')"
removed="$(diff "$TMPROOT/rb" "$TMPROOT/ra" 2>/dev/null | sed -n 's/^< //p')"
unexpected=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in
    "./.supervisor DIR"|"./.supervisor/floor DIR") continue ;;
    "./.supervisor/floor/floor.json "*) continue ;;
    *) unexpected="$unexpected
$line" ;;
  esac
done <<EOF
$added
EOF
if [ -z "$unexpected" ] && [ -z "$removed" ]; then
  ok "(i2) the fixture repo differs ONLY by .supervisor/floor/floor.json (and its two containing dirs)"
else
  no "(i2) the fixture repo differs ONLY by .supervisor/floor/floor.json" "unexpected additions:$unexpected removals: $removed"
fi
# ANTI-VACUITY: (i2) would also pass if serve had never regenerated anything at all.
if [ -f "$REPO/.supervisor/floor/floor.json" ]; then
  ok "(i3) the one permitted write DID happen — serve really regenerated floor.json in the fixture repo, not in this checkout"
else
  no "(i3) the one permitted write DID happen (serve regenerated floor.json in the fixture repo)" "no .supervisor/floor/floor.json in $REPO — (i2) may be passing vacuously"
fi
[ "$bundle_before" = "$bundle_after" ] && [ "$REAL_BUNDLE_SIG" = "$bundle_after" ] \
  && ok "(i4) every file under floor-ui/ is byte-identical before and after the whole sequence" \
  || no "(i4) every file under floor-ui/ is byte-identical before and after the whole sequence"
in_str "$out" "remove: removed" && [ ! -d "$RUI" ] \
  && ok "(i5) the sequence ended with the ui dir genuinely gone" \
  || no "(i5) the sequence ended with the ui dir genuinely gone" "$out"

# The RESULT summary and the exit status are emitted by `finish` from the EXIT trap (see its
# definition above), so every assertion group below still runs and still counts.

# (z) release-surface parity — appended by subtask 3
# ===========================================================================
echo "(z) AC-module-registered — the release surfaces that make /setup ui a real module"
# ===========================================================================
# WHY THIS GROUP EXISTS AT ALL: a new /setup module has several enumerations spread across a
# skill and two command files, and NO CI gate covers any of them — check-command-sync.sh
# guards only commands/code-reviewer.md, and check-doc-currency.sh derives no module count.
# So all of them can rot while every gate stays green. This group is that gate.
#
# It is APPENDED at the anchor left by the bundle+engine change, and it runs because the
# RESULT summary and the exit status are emitted from the EXIT trap rather than inline — an
# appended group after an inline `exit` would never execute, which is the whole reason the
# trap is shaped that way.

SKILL_MD="$script_dir/../skills/setup/SKILL.md"
SETUP_MD="$script_dir/../commands/setup.md"
HELP_MD="$script_dir/../commands/agent-help.md"

for f in "$SKILL_MD" "$SETUP_MD" "$HELP_MD"; do
  [ -r "$f" ] || setup_fail "(z) fixture: $f is not readable, so every assertion below would be vacuous"
done

# --- the Pattern 2 registry row -------------------------------------------------------
# Matched on the leading table cell so a passing mention of `ui` in prose cannot satisfy it.
if grep -q '^| `ui` |' "$SKILL_MD"; then
  ok "(z1) skills/setup/SKILL.md carries a \`ui\` row in the Pattern 2 module registry"
else
  no "(z1) skills/setup/SKILL.md carries a \`ui\` row in the Pattern 2 module registry" \
     "the registry is what the skill's own 'New modules append a row here' sentence mandates"
fi

# --- the command flow section ---------------------------------------------------------
if grep -q '^## Module: ui$' "$SETUP_MD"; then
  ok "(z2) commands/setup.md carries a '## Module: ui' flow section"
else
  no "(z2) commands/setup.md carries a '## Module: ui' flow section" \
     "the skill mandates a registry row AND a flow section in the same change"
fi

# --- the bundled-status render recipe -------------------------------------------------
# Option 1 of the no-arg dashboard folds several modules behind one label, so the recipe has
# to name each one; a module missing from it renders a status that silently stands for it.
recipe="$(grep -n 'How to render the status on a BUNDLED option' "$SETUP_MD" 2>/dev/null || true)"
if [ -z "$recipe" ]; then
  no "(z3) commands/setup.md's bundled-status recipe names \`ui:\`" "the recipe paragraph itself was not found"
elif grep -q 'ui: <status>' "$SETUP_MD"; then
  ok "(z3) commands/setup.md's bundled-status recipe names \`ui: <status>\`"
else
  no "(z3) commands/setup.md's bundled-status recipe names \`ui: <status>\`" \
     "option 1 bundles the module but never renders its status"
fi

# --- the module is reachable from the dashboard ---------------------------------------
if grep -q '/setup ui' "$SETUP_MD"; then
  ok "(z4) commands/setup.md documents the direct \`/setup ui\` jump"
else
  no "(z4) commands/setup.md documents the direct \`/setup ui\` jump"
fi

# --- zero stale module-count residue ---------------------------------------------------
# The count moved when this module was added. Grep the OLD value across all three files
# rather than trusting an enumeration of where it was believed to live — that is exactly how
# the previous module's registration found two sites its own plan had not named.
stale=""
for f in "$SKILL_MD" "$SETUP_MD" "$HELP_MD"; do
  if grep -q '9 modules' "$f"; then stale="$stale $(basename "$f")"; fi
done
if [ -z "$stale" ]; then
  ok "(z5) no '9 modules' residue in the setup skill, commands/setup.md or agent-help.md"
else
  no "(z5) no '9 modules' residue in the setup skill, commands/setup.md or agent-help.md" \
     "still stale in:$stale"
fi
# ANTI-VACUITY for (z5): the grep above proves nothing if the current count is absent too —
# a file that mentions no module count at all would pass (z5) while being just as rotten.
if grep -q '10 modules' "$SKILL_MD" && grep -q '10 modules' "$SETUP_MD" && grep -q '10 modules' "$HELP_MD"; then
  ok "(z6) all three files state the CURRENT module count, so (z5) is not passing on an absent claim"
else
  no "(z6) all three files state the CURRENT module count" \
     "(z5) may be vacuous — one of the three carries no module-count claim at all"
fi

# --- the reference doc the flow points at ----------------------------------------------
if [ -r "$script_dir/../docs/FLOOR_UI.md" ]; then
  ok "(z7) docs/FLOOR_UI.md exists — the companion doc the module flow cites is not a dead pointer"
else
  no "(z7) docs/FLOOR_UI.md exists" "commands/setup.md cites it from the ## Module: ui flow"
fi

# --- the surfaces/formats basis is stated in ONE place and quoted, not restated ---------
# `build-floor.sh`'s own header is the basis sentence. A count copied into a fourth document
# goes stale silently: this doc still said "nine surfaces, four formats" after the projector
# grew to fourteen in five, and no gate could see it because nothing tied the two together.
# This assertion ties them: the words come OUT of build-floor.sh.
FLOOR_MD="$script_dir/../docs/FLOOR_UI.md"
FLOOR_SH="$script_dir/build-floor.sh"
if [ -r "$FLOOR_MD" ] && [ -r "$FLOOR_SH" ]; then
  # The sentence wraps across comment lines, so it is un-wrapped before it is read.
  basis_line="$(sed -n '1,40p' "$FLOOR_SH" | sed 's/^#[[:space:]]*//' | tr '\n' ' ' | tr -s ' ')"
  basis_phrase="$(printf '%s' "$basis_line" | sed -nE 's/.*(across [A-Za-z]+ projected surfaces in [A-Za-z]+ formats).*/\1/p' | head -1)"
  n_word="$(printf '%s' "$basis_phrase" | awk '{print $2}')"
  f_word="$(printf '%s' "$basis_phrase" | awk '{print $6}')"
  if [ -z "$basis_phrase" ] || [ -z "$n_word" ] || [ -z "$f_word" ]; then
    no "(z8) FLOOR_UI.md quotes build-floor.sh's own surfaces/formats basis sentence" \
       "could not parse the basis phrase out of build-floor.sh (phrase='$basis_phrase') — the assertion would be vacuous"
  elif has_lit "$FLOOR_MD" "$basis_phrase"; then
    ok "(z8) FLOOR_UI.md quotes build-floor.sh's basis sentence verbatim ('$basis_phrase')"
  else
    no "(z8) FLOOR_UI.md quotes build-floor.sh's basis sentence verbatim" \
       "build-floor.sh says '$basis_phrase'; FLOOR_UI.md does not carry that phrase — a restated number here would be a fourth copy that rots on its own"
  fi
  # The residue grep is deliberately for the PREVIOUS wording, which is what actually rotted.
  stale_md=""
  for s in "nine surfaces" "four formats"; do
    if has_lit "$FLOOR_MD" "$s"; then stale_md="$stale_md [$s]"; fi
  done
  [ -z "$stale_md" ] \
    && ok "(z9) no pre-fourteen surfaces/formats residue survives in FLOOR_UI.md" \
    || no "(z9) no pre-fourteen surfaces/formats residue survives in FLOOR_UI.md" "still present:$stale_md"
else
  no "(z8/z9) FLOOR_UI.md and build-floor.sh are both readable" "FLOOR_UI.md or build-floor.sh could not be read"
fi
