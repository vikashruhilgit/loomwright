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
# ISOLATION IS LOAD-BEARING AND IS ASSERTED, NOT ASSUMED — and it takes TWO mechanisms, not one.
# Every engine case passes `--ui-dir` into its own `mktemp -d`; group (i) hashes two trees — the
# fixture parent AND a fixture git repo used as the working directory — before and after the
# full apply/serve/stop/remove sequence, because `serve` without `--no-regen` runs
# `build-floor.sh` in the CWD and that write must land in the fixture repo rather than in this
# checkout.
#
# `--ui-dir` IS NOT ENOUGH FOR THE REGISTRY, and this paragraph used to say it was enough for
# everything. The project registry is deliberately a SIBLING of the ui directory (that sibling
# placement is what makes it survive `remove`), and the engine's arg loop sets only UI_DIR from
# `--ui-dir` — so `--ui-dir` provably cannot redirect the registry, and a registry case written
# in the ordinary style would write the DEVELOPER'S OWN projects.json while every one of its
# assertions passed. Group (k) therefore runs every registry-touching invocation under a fixture
# `HOME` or the engine's explicit `--registry` override, and (k26) is a static gate over THIS
# FILE asserting exactly that — with a mutation control at (k27) that strips one `HOME=` and
# requires the gate to redden. The gate is what enforces the rule; a hash alone cannot, because
# an add-then-forget sequence writes and then restores, so on a machine with no pre-existing
# registry the two hashes would match and the tree would still have been touched.
#
# ONE INVOCATION IN THIS FILE DELIBERATELY RUNS AGAINST THE REAL HOME: the `check` inside
# `real_loom_home` near the top, whose only purpose is to learn the path that the (k28)/(k29)
# backstop must then prove was never written. It is read-only by contract ((f2) asserts `check`
# writes nothing), and reading the path out of the engine is what keeps it from being restated
# here — and therefore able to drift — the same reason (z8) quotes build-floor.sh.
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
#       no cause it cannot observe. Plus the poll's in-flight guard and both of its clear sites.
#       Plus THE PHASE MAP, checked against the closed phase set PARSED OUT of the
#       state-management skill: the map may invent no phase, at least one closed-set phase
#       must be left unmapped (or the fallback is dead code), and a recorded-but-unmapped
#       phase must get its own note rather than rendering exactly like no phase at all — with
#       one control that invents a stage for it and one that deletes the note
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
#       saying why, beside a state surface still recording phase EXECUTE); floor-loop is the
#       stage-map contrast (every surface counted, lanes present, and a recorded phase the
#       map has no stage for); floor-stale's generation time is far older than the others'
#   (f) AC-engine-contract — check on an absent dir, apply installs, a second apply is a
#       no-op, a drifted bundle is `updated` naming the file, remove is WITHHELD on a
#       directory with no marker (and that directory survives), remove deletes an owned one.
#       With a mutation control that strips the marker gate and shows the foreign directory
#       being deleted. Plus the two paths on which a removal REPORT could be false: a
#       --ui-dir that is itself a symlink, and a real directory whose PHYSICAL path is $HOME
#       reached through a symlinked parent. Plus all THREE path refusals exercised directly —
#       `/` (twice: as the engine ships, and again with the ownership gate reverted so the
#       /-refusal itself has to answer, both under a `rm` that only writes a log), a BARE
#       $HOME, and an OWNED directory under the plugin install dir — against a fixture $HOME
#       and a fixture plugin root, each asserting the target survives byte for byte, with a
#       mutation control that reverts the plugin-dir guard and watches the delete go through
#   (g) AC-engine-fail-safe — python3 absent (PATH stub) aborts serve by name; jq absent still
#       applies and warns that build-floor.sh will skip; build-floor.sh absent aborts serve by
#       name; a bad subcommand and a bad flag both exit 0; an UNSET HOME aborts by name rather
#       than tripping `set -u`. EVERY branch exits 0. Plus the `?stale=` hint serve prints when
#       --interval outgrows the page's own threshold, its control at the default interval, and
#       a parity check on the two page constants the engine mirrors to compute it. The fourth
#       serve fail-safe branch — a BUSY PORT — is exercised against a socket this suite really
#       holds, with a free-port control proving the refusal is the conflict and not a blanket
#       one
#   (h) AC-loopback — a real detached server, a real fetch from 127.0.0.1 returning the fixture
#       bytes, and a refused connect to this host's first non-loopback IPv4 on the same port.
#       SKIPPED (reported separately from passes) when the host has no non-loopback address
#   (i) AC-remove-residue — the two hashed trees described above, plus the plugin's own bundle
#       hashed before and after
#   (k) AC-registry — the project registry the module keeps BESIDE its ui directory: `add`
#       registers the current project (or a named path) with a derived, collision-free slug and
#       is a no-op the second time; `list` prints slug, path and last-regenerated age and marks
#       a missing path `unavailable`, never mutating; `forget` drops one entry and is hash-proven
#       to leave the project directory itself alone; `scan` proposes and writes nothing until
#       `--confirm`, bounded at a stated depth; a module `remove` leaves the registry intact; an
#       unparseable registry makes every verb refuse by name, exit 0 and preserve the file byte
#       for byte; and with jq made UNFINDABLE on PATH every registry verb names jq rather than
#       pretending. Plus the isolation gate, its mutation control, and the real-tree backstop —
#       all three described in the isolation paragraph above
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
# HOLDER_PIDS: processes this suite starts that are NOT the engine's own server — currently
# the socket held on a port so the busy-port branch has something to collide with. They are
# killed from the same EXIT trap, because a probe that outlives the run holds a port hostage.
HOLDER_PIDS=""
cleanup_files() {
  local pf pid
  for pid in $HOLDER_PIDS; do
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    kill "$pid" 2>/dev/null
  done
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

# THE REAL USER-SCOPE TREE — captured HERE, before the first assertion, and compared again in
# group (k). Its path is deliberately NOT restated in this file: it is read OUT of the engine's
# own `check` report, for the same reason (z8) quotes build-floor.sh instead of repeating its
# numbers — a hard-coded second copy of the path would keep passing after the engine moved it.
# That single `check` is this suite's ONLY invocation against the developer's real HOME. It is
# read-only by contract ((f2) asserts check writes nothing), and it exists precisely so the
# backstop at (k) has a subject the rest of the suite must be proven never to have touched.
real_loom_home() {
  local line
  line="$(bash "$ENGINE" check 2>/dev/null | sed -n 's/^registry: //p' | awk 'NR==1')"
  case "$line" in
    /*) dirname "$line" ;;
    *)  printf 'UNRESOLVED' ;;
  esac
}
# real_tree_sig — DEFINED for an absent tree rather than skipped. CI has no user-scope
# loomwright directory at all, and "skip when absent" would make this backstop vacuous exactly
# where it is cheapest to run: `ABSENT` is a VALUE, so a run that turns ABSENT into a directory
# listing reddens instead of quietly passing.
real_tree_sig() {
  case "$1" in /*) ;; *) printf 'UNRESOLVED'; return 0 ;; esac
  [ -d "$1" ] || { printf 'ABSENT'; return 0; }
  tree_sig "$1"
}
REAL_LOOM_HOME="$(real_loom_home)"
REAL_LOOM_SIG_BEFORE="$(real_tree_sig "$REAL_LOOM_HOME")"
REAL_REG_BEFORE="ABSENT"
[ -f "$REAL_LOOM_HOME/projects.json" ] && REAL_REG_BEFORE="$(csum "$REAL_LOOM_HOME/projects.json")"

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


# --- A RECORDED PHASE OUTSIDE THE STAGE MAP MUST BE VISIBLE, NEVER SILENT ---------------
# `state.md`'s `phase` is a CLOSED SET, and it is PARSED OUT of the state-management skill
# here rather than restated, so a phase added there moves this assertion with it.
# PHASE_STAGE maps the pipeline phases onto the three middle stages, and it is deliberately
# PARTIAL: one member of the closed set sits BETWEEN items rather than inside the pipeline,
# so no stage corresponds to it and inventing one would be the guess this page exists to
# refuse. What the page must NOT do is render such a phase exactly as it renders NO phase —
# three em dashes and a note that says nothing — because that reads as "no phase was
# recorded" about a phase that WAS recorded, which is the measured-state-as-unknown failure
# floor.js's own header names. Three claims, none of which restates a phase name:
#   1. every key of the map is in the closed set (the map never invents a phase),
#   2. at least one closed-set phase is left UNMAPPED (or the fallback is dead code),
#   3. the page carries a distinct note for it, keyed on the MAP rather than on any phase
#      value — so no unmapped phase name may appear in floor.js at all.
STATE_SKILL="$script_dir/../skills/state-management/SKILL.md"
PHASE_NOTE_LIT="no pipeline stage corresponds to it"
map_keys_of() {
  awk '/var PHASE_STAGE = \{/{f=1} f{print} f&&/\};/{exit}' "$1" \
    | tr ',' '\n' | sed -nE 's/^[[:space:]]*([A-Z_]+)[[:space:]]*:.*/\1/p' | LC_ALL=C sort
}
not_in() { # not_in "<set>" "<candidates>" -> candidates absent from set
  local s="$1" c out="" x
  for x in $2; do case " $s " in *" $x "*) ;; *) out="$out $x" ;; esac; done
  printf '%s' "${out# }"
}
if [ ! -f "$STATE_SKILL" ]; then
  no "(b22) the phase closed set is parsed from the state-management skill" "not found: $STATE_SKILL — every phase assertion below would be vacuous"
else
  CLOSED_PHASES="$(sed -nE 's/^- phase: (.*)$/\1/p' "$STATE_SKILL" | head -1 | tr '|' ' ')"
  CLOSED_PHASES="$(printf '%s' "$CLOSED_PHASES" | tr -s ' ' | sed -e 's/^ //' -e 's/ $//')"
  MAP_KEYS="$(map_keys_of "$JS" | tr '\n' ' ' | sed -e 's/ $//')"
  n_closed="$(printf '%s\n' $CLOSED_PHASES | awk 'NF{n++} END{print n+0}')"
  n_map="$(printf '%s\n' $MAP_KEYS | awk 'NF{n++} END{print n+0}')"
  if [ "$n_closed" -lt 2 ] || [ "$n_map" -lt 1 ]; then
    no "(b22) the closed phase set and the PHASE_STAGE map were both parsed" "closed=$n_closed ($CLOSED_PHASES) map=$n_map ($MAP_KEYS) — the assertions below would be vacuous"
  else
    ok "(b22) parsed $n_closed closed-set phases from the skill and $n_map PHASE_STAGE keys from floor.js"
    invented="$(not_in "$CLOSED_PHASES" "$MAP_KEYS")"
    [ -z "$invented" ] \
      && ok "(b23) every PHASE_STAGE key is a member of the closed set — the map invents no phase" \
      || no "(b23) every PHASE_STAGE key is a member of the closed set" "not in the closed set:$invented"
    UNMAPPED="$(not_in "$MAP_KEYS" "$CLOSED_PHASES")"
    [ -n "$UNMAPPED" ] \
      && ok "(b24) at least one closed-set phase is deliberately UNMAPPED ($UNMAPPED), so the unmapped-phase path is live code and not decoration" \
      || no "(b24) at least one closed-set phase is deliberately unmapped" "every closed-set phase has a stage, so the fallback below can never run — either a stage was guessed for a phase that has none, or this assertion has rotted"
    named=""
    for p in $UNMAPPED; do
      [ "$(occ "$JS" "$p")" = "0" ] || named="$named $p"
    done
    if has_lit "$JS" "$PHASE_NOTE_LIT" && has_lit "$JS" "no phase is recorded" && [ -z "$named" ]; then
      ok "(b25) an unmapped recorded phase gets its own note ('$PHASE_NOTE_LIT'), distinct from 'no phase is recorded', and no unmapped phase is named in floor.js — the fallback is keyed on the map"
    else
      no "(b25) an unmapped recorded phase gets its own note, distinct from the no-phase case, with no hard-coded phase name" \
         "note-literal=$(has_lit "$JS" "$PHASE_NOTE_LIT" && echo yes || echo NO) no-phase-literal=$(has_lit "$JS" "no phase is recorded" && echo yes || echo NO) hard-coded:${named:-none}"
    fi
    # MUTATION CONTROL for (b24): give the unmapped phase a stage and the set must empty out.
    # This is the exact regression the finding describes in reverse — a page that answers for
    # a phase it cannot place — and (b24) has to be able to see it.
    first_unmapped="$(printf '%s\n' $UNMAPPED | awk 'NF{print; exit}')"
    if [ -n "$first_unmapped" ]; then
      MUT_MAP="$TMPROOT/mut-phasemap.js"
      sed "s/^    EXECUTE: 'execute',$/    EXECUTE: 'execute', $first_unmapped: 'execute',/" "$JS" > "$MUT_MAP" 2>/dev/null
      if mutant_ok "$JS" "$MUT_MAP"; then
        m_keys="$(map_keys_of "$MUT_MAP" | tr '\n' ' ' | sed -e 's/ $//')"
        m_unmapped="$(not_in "$m_keys" "$CLOSED_PHASES")"
        [ -z "$m_unmapped" ] \
          && ok "(b26) MUTATION CONTROL: a stage invented for $first_unmapped empties the unmapped set — (b24) can turn red" \
          || no "(b26) MUTATION CONTROL: a stage invented for $first_unmapped empties the unmapped set" "still unmapped:$m_unmapped"
      fi
    fi
    # MUTATION CONTROL for (b25): delete the note and the distinction disappears.
    MUT_NOTE="$TMPROOT/mut-phasenote.js"
    sed "s/ — $PHASE_NOTE_LIT//g" "$JS" > "$MUT_NOTE" 2>/dev/null
    if mutant_ok "$JS" "$MUT_NOTE"; then
      has_lit "$MUT_NOTE" "$PHASE_NOTE_LIT" \
        && no "(b27) MUTATION CONTROL: removing the unmapped-phase note IS detected" "the literal survived the mutation, so (b25) proves nothing" \
        || ok "(b27) MUTATION CONTROL: removing the unmapped-phase note IS detected — (b25) can turn red"
    fi
  fi
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
# 6 from item 04 (lanes/sessions states) + 5 from item 05's rules/churn views
# (floor-rules-churn-{live,absent,empty,unavailable,stale}.json) + 1 curation-faults fixture
# driving the self_referential / duplicate_ids / files_not_an_array renders = 12. This literal
# moves with the fixture set, per AC-suite-hermetic's sibling discipline in build-floor.sh.
[ "$n_fix" -eq 12 ] \
  && ok "(d3) all twelve committed fixtures were validated (found $n_fix)" \
  || no "(d3) all twelve committed fixtures were validated" "found $n_fix"

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
LOOPF="$FIX_DIR/floor-loop.json"

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


# floor-loop is the RECORDED-BUT-UNMAPPED phase, and it is the shape the projector really
# emits between items: everything else about the run looks exactly like floor-live — the
# sessions surface is counted, lanes are present — and the ONE difference is a phase that the
# page's stage map does not carry. Rendering it identically to "no phase is recorded" would be
# the same class of defect as the idle banner (e7)/(e9) exist for, one region up the page.
e_loop="$(jq -r '"\(.surfaces.state.status)/\(.surfaces.state.detail.phase)/\(.surfaces.sessions.status)"' "$LOOPF" 2>/dev/null)"
loop_phase="$(jq -r '.surfaces.state.detail.phase' "$LOOPF" 2>/dev/null)"
case " $UNMAPPED " in
  *" $loop_phase "*)
    ok "(e11) floor-loop records phase $loop_phase — a member of the closed set that the stage map deliberately does NOT carry, so the unmapped rendering has a fixture" ;;
  *)
    no "(e11) floor-loop records a phase the stage map does not carry" "phase=$loop_phase, unmapped set='${UNMAPPED:-<empty>}' — the fixture no longer exercises the unmapped path" ;;
esac
[ "${e_loop%%/*}" = "counted" ] && [ "$(printf '%s' "$e_loop" | awk -F/ '{print $3}')" = "counted" ] \
  && ok "(e12) floor-loop's state and sessions surfaces are BOTH counted, so the em dashes it renders can only come from the unmapped phase — never from an absent surface" \
  || no "(e12) floor-loop's state and sessions surfaces are both counted" "got $e_loop"
n_loop_rows="$(jq -r '.surfaces.sessions.detail.current.agents | length' "$LOOPF" 2>/dev/null)"
[ "$n_loop_rows" -ge 1 ] 2>/dev/null \
  && ok "(e13) CONTROL: floor-loop still has $n_loop_rows lane row(s), so no banner intercepts the page before the stage row is read" \
  || no "(e13) floor-loop still has lane rows" "found $n_loop_rows — an empty lane list would raise a banner and the stage row would not be what the reader sees"
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


# --- THE THREE PATH REFUSALS, EACH EXERCISED DIRECTLY -----------------------------------
# `do_remove` refuses `/`, `$HOME` and anything at or under the plugin install directory.
# The header, FLOOR_UI.md and commands/setup.md all describe these as load-bearing, and until
# now only the symlinked-parent variant of the $HOME one had a case: `/` had none, the BARE
# $HOME had none, and the plugin-install-dir guard was not merely uncovered but deliberately
# ROUTED AROUND — (f12)'s mutant is placed in its own directory precisely so that guard does
# not intercept it.
#
# NOTHING BELOW POINTS AT A REAL PATH. `$HOME` is a fixture directory under $TMPROOT for the
# duration of one command, the "plugin install directory" is a COPY of the engine in another
# one (the engine resolves script_dir from $0, which is the whole seam), and the two cases
# that name `/` run with a `rm` that only writes a log — so even a total failure of every
# guard could not delete anything. Each case asserts the refusal AND that the target is still
# there, byte for byte.
FAKE_HOME="$F/fake-home"
mkdir -p "$FAKE_HOME" || setup_fail "(f15) fixture: could not create $FAKE_HOME"
FAKE_BIN="$F/fake-bin"
mkdir -p "$FAKE_BIN" || setup_fail "(f15) fixture: could not create $FAKE_BIN"
RM_LOG="$F/rm-calls.log"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$RM_LOG" > "$FAKE_BIN/rm" \
  || setup_fail "(f15) fixture: could not stage the no-op rm"
chmod +x "$FAKE_BIN/rm" || setup_fail "(f15) fixture: could not make the no-op rm executable"
: > "$RM_LOG"
"$FAKE_BIN/rm" -r -- /proof-of-neutering >/dev/null 2>&1
if [ "$(awk 'END{print NR+0}' "$RM_LOG")" = "1" ] && [ -d / ]; then
  ok "(f15) fixture PREMISE: the no-op rm on the probe PATH records its arguments and deletes nothing"
else
  setup_fail "(f15) fixture: the no-op rm did not record its call, so the two /-refusal cases below would run against a REAL rm"
fi
: > "$RM_LOG"

out="$(HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" bash "$ENGINE" remove --ui-dir / 2>&1)"; rc=$?
n_rm="$(awk 'END{print NR+0}' "$RM_LOG")"
if [ "$rc" -eq 0 ] && ! in_str "$out" "remove: removed" && [ "$n_rm" = "0" ] && [ -d / ]; then
  ok "(f16) remove --ui-dir / refuses, exits 0 and never reaches a delete (rm calls: $n_rm)"
else
  no "(f16) remove --ui-dir / refuses, exits 0 and never reaches a delete" "rc=$rc rm-calls=$n_rm :: $out"
fi
# WHICH refusal answered matters. On any machine without a root-level marker the ownership
# gate answers FIRST, so the `/` assertion itself is unreachable from outside and would sit
# there untested forever — the exact shape of "a guard that cannot fire". Reverting only the
# two marker gates (the same three sites (f12) reverts) lets the next line of defence speak,
# and the no-op rm makes the probe harmless even if it did not.
: > "$RM_LOG"
MUT_ROOT_DIR="$TMPROOT/mutroot"
mkdir -p "$MUT_ROOT_DIR" || setup_fail "(f17) fixture: could not create $MUT_ROOT_DIR"
MUT_ROOT="$MUT_ROOT_DIR/setup-ui.sh"
sed -e 's/^  if ! is_ours; then$/  if false; then/' \
    -e 's/^  if \[ ! -f "\$resolved\/\$MARKER" \]; then$/  if false; then/' "$ENGINE" > "$MUT_ROOT" 2>/dev/null
n_rev_root="$(occ "$MUT_ROOT" 'if false; then')"
[ "$n_rev_root" = "3" ] || setup_fail "(f17) fixture: the mutant reverted $n_rev_root of the 3 marker assertions, so the /-refusal would not be the gate under test"
if mutant_ok "$ENGINE" "$MUT_ROOT" shell; then
  out="$(HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" bash "$MUT_ROOT" remove --ui-dir / 2>&1)"; rc=$?
  n_rm="$(awk 'END{print NR+0}' "$RM_LOG")"
  if [ "$rc" -eq 0 ] && in_str "$out" "the resolved ui dir is /, which this module will never delete" \
     && [ "$n_rm" = "0" ] && [ -d / ]; then
    ok "(f17) with the ownership gate removed the /-refusal ITSELF fires by name and still reaches no delete — it is a real second line of defence, not dead code behind the marker"
  else
    no "(f17) the /-refusal fires by name once the ownership gate is out of the way" "rc=$rc rm-calls=$n_rm :: $out"
  fi
fi

# The BARE $HOME — no symlinked parent, which is what makes it a different case from (f14).
# The marker is PRESENT, so the ownership gate cannot be what answers: the only thing left
# that can refuse a marker-carrying directory outside the plugin dir is the $HOME guard.
HOMEUI="$F/home-as-ui-dir"
mkdir -p "$HOMEUI" || setup_fail "(f18) fixture: could not create $HOMEUI"
printf 'marker\n' > "$HOMEUI/.loomwright-ui-module"
printf 'the user keeps this\n' > "$HOMEUI/precious.txt"
[ ! -L "$HOMEUI" ] || setup_fail "(f18) fixture: the ui dir must not be a symlink, or (f13)'s guard would answer instead"
hu_before="$(tree_sig "$HOMEUI")"
out="$(HOME="$HOMEUI" bash "$ENGINE" remove --ui-dir "$HOMEUI" 2>&1)"; rc=$?
hu_after="$(tree_sig "$HOMEUI")"
# Two spellings, one guard: on a host whose temp tree is reached through a symlink (macOS
# /var -> /private/var) the PHYSICAL comparison answers and names the symlink; on a host
# where it is not, the literal comparison answers. Either is the $HOME refusal.
home_named=0
in_str "$out" "which this module will never delete" && home_named=1
in_str "$out" "which is the home directory" && home_named=1
if [ "$rc" -eq 0 ] && in_str "$out" "remove: ABORTED" && [ "$home_named" = "1" ] \
   && [ -d "$HOMEUI" ] && [ "$hu_before" = "$hu_after" ]; then
  ok "(f18) a BARE --ui-dir equal to \$HOME is refused although it carries the marker, and survives byte for byte"
else
  no "(f18) a bare --ui-dir equal to \$HOME is refused and survives" \
     "rc=$rc named=$home_named dir=$([ -d "$HOMEUI" ] && echo present || echo GONE) unchanged=$([ "$hu_before" = "$hu_after" ] && echo yes || echo NO) :: $out"
fi

# An OWNED directory inside the plugin's own install dir. The install dir is wherever the
# engine is invoked from ($0), so a COPY of the engine in a fixture directory is a complete
# and hermetic fake of one — this never touches the real plugin tree.
FAKEPLUG="$F/fake-plugin"
mkdir -p "$FAKEPLUG" || setup_fail "(f19) fixture: could not create $FAKEPLUG"
cp "$ENGINE" "$FAKEPLUG/setup-ui.sh" || setup_fail "(f19) fixture: could not stage the engine copy"
PLUGUI="$FAKEPLUG/ui"
mkdir -p "$PLUGUI" || setup_fail "(f19) fixture: could not create $PLUGUI"
printf 'marker\n' > "$PLUGUI/.loomwright-ui-module"
printf 'the user keeps this\n' > "$PLUGUI/precious.txt"
pu_before="$(tree_sig "$PLUGUI")"
out="$(HOME="$FAKE_HOME" bash "$FAKEPLUG/setup-ui.sh" remove --ui-dir "$PLUGUI" 2>&1)"; rc=$?
pu_after="$(tree_sig "$PLUGUI")"
if [ "$rc" -eq 0 ] && in_str "$out" "inside the plugin install directory" \
   && [ -d "$PLUGUI" ] && [ "$pu_before" = "$pu_after" ]; then
  ok "(f19) an OWNED (marker-carrying) directory under the plugin install dir is refused by name and survives byte for byte"
else
  no "(f19) an owned directory under the plugin install dir is refused and survives" \
     "rc=$rc dir=$([ -d "$PLUGUI" ] && echo present || echo GONE) unchanged=$([ "$pu_before" = "$pu_after" ] && echo yes || echo NO) :: $out"
fi

# MUTATION CONTROL for (f19). (f18) and (f19) both assert a REFUSAL, and a refusal is exactly
# what an engine that never deletes anything also produces — so at least one of these guards
# has to be shown deleting when it is taken away. The plugin-install-dir guard is the one
# chosen because its whole blast radius is a fixture directory under $TMPROOT.
MUTPLUG="$F/fake-plugin-mut"
mkdir -p "$MUTPLUG" || setup_fail "(f20) fixture: could not create $MUTPLUG"
MUT_PLUG_ENG="$MUTPLUG/setup-ui.sh"
sed -e 's/^    "\$script_dir"|"\$script_dir"\/\*)$/    "@@no-such-path@@")/' \
    -e 's/^      "\$script_phys"|"\$script_phys"\/\*)$/      "@@no-such-path@@")/' "$ENGINE" > "$MUT_PLUG_ENG" 2>/dev/null
n_rev_plug="$(occ "$MUT_PLUG_ENG" '@@no-such-path@@')"
[ "$n_rev_plug" = "2" ] || setup_fail "(f20) fixture: the mutant reverted $n_rev_plug of the 2 plugin-install-dir patterns, so the control would not be testing that guard"
if mutant_ok "$ENGINE" "$MUT_PLUG_ENG" shell; then
  MUTPUI="$MUTPLUG/ui"
  mkdir -p "$MUTPUI" && printf 'marker\n' > "$MUTPUI/.loomwright-ui-module" && printf 'x\n' > "$MUTPUI/precious.txt" \
    || setup_fail "(f20) fixture: could not create $MUTPUI"
  SENTINEL="$F/sentinel"
  mkdir -p "$SENTINEL" && printf 'untouched\n' > "$SENTINEL/keep.txt" || setup_fail "(f20) fixture: could not create $SENTINEL"
  sent_before="$(tree_sig "$SENTINEL")"
  HOME="$FAKE_HOME" bash "$MUT_PLUG_ENG" remove --ui-dir "$MUTPUI" >/dev/null 2>&1
  sent_after="$(tree_sig "$SENTINEL")"
  if [ ! -d "$MUTPUI" ] && [ "$sent_before" = "$sent_after" ]; then
    ok "(f20) MUTATION CONTROL: with the plugin-install-dir guard reverted the owned directory IS deleted — the guard is what saved it in (f19), and the blast radius stayed inside the fixture"
  else
    no "(f20) MUTATION CONTROL: with the plugin-install-dir guard reverted the owned directory IS deleted" \
       "dir=$([ -d "$MUTPUI" ] && echo STILL-PRESENT || echo gone) sentinel-unchanged=$([ "$sent_before" = "$sent_after" ] && echo yes || echo NO) — (f19) may be passing against an engine that simply never deletes"
  fi
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


# A BUSY PORT IS THE FOURTH `serve` FAIL-SAFE BRANCH, and it was the only one with no case.
# The other three are stubbed ABSENCES (no python3, no jq, no build-floor.sh); this one needs
# a real conflict, so a socket is genuinely held on the port for the duration of the probe —
# the same bind the engine's own `port_free()` performs, from the other side. It matters
# because the module's stated posture is that a busy port is REPORTED and never silently
# moved: a moved port is a browser tab reading bytes from something else.
PORT_HOLDER_OUT="$G/busy-port.txt"
: > "$PORT_HOLDER_OUT"
python3 -c 'import socket, sys, time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0)); s.listen(5)
sys.stdout.write(str(s.getsockname()[1]) + "\n"); sys.stdout.flush()
time.sleep(120)' > "$PORT_HOLDER_OUT" 2>/dev/null &
PORT_HOLDER_PID=$!
HOLDER_PIDS="$HOLDER_PIDS $PORT_HOLDER_PID"
# Poll for the holder to publish its port. No `timeout` (absent on stock macOS) and no
# unbounded wait: a holder that never came up must SKIP, not hang and not assert on nothing.
hw=0
while [ "$hw" -lt 100 ]; do
  [ -s "$PORT_HOLDER_OUT" ] && break
  sleep 0.1; hw=$((hw + 1))
done
busy_port="$(head -1 "$PORT_HOLDER_OUT" 2>/dev/null)"
case "${busy_port:-x}" in
  ''|*[!0-9]*)
    kill "$PORT_HOLDER_PID" 2>/dev/null
    skipn "(g12) no socket could be held on this host, so the busy-port branch cannot be exercised from here" ;;
  *)
    if ! kill -0 "$PORT_HOLDER_PID" 2>/dev/null; then
      skipn "(g12) the port holder exited before the probe, so the port would not have been busy"
    else
      rm -f "$GUI/serve.pid" 2>/dev/null
      out="$(bash "$ENGINE" serve --ui-dir "$GUI" --no-regen --port "$busy_port" 2>&1)"; rc=$?
      if [ "$rc" -eq 0 ] \
         && in_str "$out" "serve: ABORTED — port $busy_port is already in use" \
         && in_str "$out" "Nothing was started" \
         && [ ! -f "$GUI/serve.pid" ]; then
        ok "(g12) with the port already held, serve aborts by name, exits 0, starts nothing and records no pidfile"
      else
        no "(g12) with the port already held, serve aborts by name and exits 0" \
           "rc=$rc pidfile=$([ -f "$GUI/serve.pid" ] && echo WRITTEN || echo none) :: $out"
      fi
      # CONTROL: the abort must be caused by the CONFLICT, not by serve refusing every port.
      free_port="$(python3 -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()' 2>/dev/null)"
      case "${free_port:-x}" in
        ''|*[!0-9]*) skipn "(g13) CONTROL: no free port could be obtained for the contrast run" ;;
        *)
          out="$(bash "$ENGINE" serve --ui-dir "$GUI" --no-regen --detach --port "$free_port" 2>&1)"; rc=$?
          SERVE_PIDFILES="$SERVE_PIDFILES $GUI/serve.pid"
          if [ "$rc" -eq 0 ] && ! in_str "$out" "already in use"; then
            ok "(g13) CONTROL: on a FREE port the same invocation does not abort — the refusal is the conflict, not a blanket refusal"
          else
            no "(g13) CONTROL: on a free port the same invocation does not abort" "rc=$rc :: $out"
          fi
          bash "$ENGINE" stop --ui-dir "$GUI" >/dev/null 2>&1 ;;
      esac
      kill "$PORT_HOLDER_PID" 2>/dev/null
    fi ;;
esac
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

# ===========================================================================
echo "(j) AC-views-render / AC-views-four-states / AC-no-scoring / AC-still-read-only — rules + churn views"
# ===========================================================================
# The bundle half of item 05 subtask 2. The BROWSER half of every AC below — does the DOM
# actually render the grouped categories, does a screen reader see the tri-state text — is
# recorded UNVERIFIED here and closed by the Supervisor at Phase 4.5 against these same
# fixtures, exactly as group (b)/(c) already say for the lanes/roster views.

check_lit "$JS" "function renderRules(d)" "(j1) floor.js defines renderRules(d)"
check_lit "$JS" "function renderChurn(d)" "(j2) floor.js defines renderChurn(d)"
n_rr_call="$(awk '/^  function apply\(d\)/{f=1} f{print} f&&/^  }$/{exit}' "$JS" | grep -c 'renderRules(d)\|renderChurn(d)' 2>/dev/null || true)"
[ "${n_rr_call:-0}" = "2" ] \
  && ok "(j3) apply() calls both renderRules(d) and renderChurn(d)" \
  || no "(j3) apply() calls both renderRules(d) and renderChurn(d)" "found $n_rr_call call(s) inside apply()"

# --- applies_to / check stay TRI-STATES in the render layer, decided by key PRESENCE ---------
check_lit "$JS" "hasOwnProperty.call(r, 'applies_to')" "(j4) applies_to is decided by hasOwnProperty, never truthiness"
check_lit "$JS" "hasOwnProperty.call(r, 'check')"       "(j5) check is decided by hasOwnProperty, never truthiness"
# supersedes now lives in ruleSupersedesLabel(r) alongside its three siblings, so the parameter
# is `r` like theirs - it was `rule` while the field was still rendered inline on the card.
check_lit "$JS" "hasOwnProperty.call(r, 'supersedes')" "(j6) supersedes presence (vs absence) is checked with hasOwnProperty"

# Mutation control: a truthy read of applies_to must be CAUGHT, or (j4) proves nothing.
MUT_TRI="$TMPROOT/mut-tristate.js"
sed "s/if (!Object.prototype.hasOwnProperty.call(r, 'applies_to')) { return 'no scope recorded'; }/if (!r.applies_to) { return 'no scope recorded'; }/" "$JS" > "$MUT_TRI" 2>/dev/null
if mutant_ok "$JS" "$MUT_TRI"; then
  has_lit "$MUT_TRI" "hasOwnProperty.call(r, 'applies_to')" \
    && no "(j7) MUTATION CONTROL: replacing the hasOwnProperty check with a truthy read IS detected" "the literal survived the mutation, so (j4) proves nothing" \
    || ok "(j7) MUTATION CONTROL: replacing the hasOwnProperty check with a truthy read IS detected — (j4) can turn red"
fi

# --- the flow-stage basis is READ from the projection, never restated as a literal -----------
# The pinned predicate string lives in ONE place: build-floor.sh's own emission. A second,
# hard-coded copy of it in floor.js would be a second place for the two to drift apart.
n_basis_literal="$(grep -c -F -- '.categories[].flow_stage' "$JS" 2>/dev/null || true)"
case "$n_basis_literal" in ''|*[!0-9]*) n_basis_literal=0 ;; esac
[ "$n_basis_literal" = "0" ] \
  && ok "(j8) floor.js never hard-codes the .categories[].flow_stage literal — it reads detail.flow_stage_basis (found $n_basis_literal)" \
  || no "(j8) floor.js never hard-codes the .categories[].flow_stage literal" "found $n_basis_literal occurrence(s) — the basis must come from the projection, not be restated"
check_lit "$JS" "detail.flow_stage_basis" "(j9) floor.js reads flow_stage_basis off the projected detail object"

# --- AC-no-scoring: nothing on this page ranks, scores, or sorts by desirability -------------
no_scoring_check() {
  local f="$1"
  grep -inE '\b(rank|ranking|score|scoring)\b' "$f" 2>/dev/null || true
}
scoring_findings=""
for f in "$HTML" "$CSS" "$JS"; do
  out="$(no_scoring_check "$f")"
  [ -n "$out" ] && scoring_findings="$scoring_findings
$(basename "$f"): $out"
done
[ -z "$scoring_findings" ] \
  && ok "(j10) AC-no-scoring: no rank/score/ranking/scoring word appears anywhere in the bundle" \
  || no "(j10) AC-no-scoring: no rank/score/ranking/scoring word appears anywhere in the bundle" "$scoring_findings"
# Mutation control: a page that DOES rank rules must be caught.
MUT_SCORE="$TMPROOT/mut-score.js"
{ cat "$JS"; printf "\n// top-ranked rule score placeholder\n"; } > "$MUT_SCORE" 2>/dev/null
if mutant_ok "$JS" "$MUT_SCORE"; then
  mout="$(no_scoring_check "$MUT_SCORE")"
  [ -n "$mout" ] \
    && ok "(j11) MUTATION CONTROL: an added 'ranked'/'score' comment IS flagged by the scanner" \
    || no "(j11) MUTATION CONTROL: an added 'ranked'/'score' comment IS flagged by the scanner" "scanner said: ${mout:-<nothing>}"
fi
# Distributions are sorted by KEY, not by value — the mechanism behind (j10)'s absence of the word.
check_lit "$JS" "keys.sort();" "(j12) distribution keys are sorted lexically (sort(), never sorted by count)"

# --- AC-still-read-only: CREATE the no-write-verb assertion (measured 0 today; this IS it) ---
# no_write_verbs — the literal name this subtask's `provides` entry pins, because the
# outputs_verified gate greps THIS repo for that exact token. Whole-word, uppercase (the HTTP
# method spelling), scoped to the three bundle files that ship to the browser.
no_write_verbs() {
  local f
  for f in "$HTML" "$CSS" "$JS"; do
    # Matches the METHOD POSITION, case-insensitively, rather than bare verb tokens. Both halves
    # of that are load-bearing and each was arrived at by measurement, not taste:
    #   * case-insensitive, because the Fetch spec NORMALIZES a lowercase known method, so
    #     `fetch(u, {method: 'post'})` performs a real POST. An uppercase-only scanner reads like
    #     a read-only guarantee while letting the lowercase spelling straight through.
    #   * position-scoped, because a bare case-insensitive \bDELETE\b matches JavaScript's own
    #     `delete` OPERATOR - floor.js:726 `delete laneEls[k];` is legitimate object-property
    #     removal, and flagging it would be a false positive that pressures a future author into
    #     deleting a correct line to appease the gate.
    # Verified against four inputs: the real bundle 0, `method: 'post'` 1, `method: 'PUT'` 1,
    # and the bare `delete` operator 0.
    grep -inE "(method[[:space:]]*[:=][[:space:]]*['\"]?(post|put|delete)|['\"](post|put|delete)['\"])" "$f" 2>/dev/null | sed "s|^|$(basename "$f"): |"
  done
}
write_findings="$(no_write_verbs)"
[ -z "$write_findings" ] \
  && ok "(j13) no_write_verbs: index.html / floor.css / floor.js carry no POST, PUT or DELETE token" \
  || no "(j13) no_write_verbs: index.html / floor.css / floor.js carry no POST, PUT or DELETE token" "$write_findings"
# Mutation control: a write verb really appearing in the bundle must be caught.
MUT_WRITE="$TMPROOT/mut-write.js"
# The mutant uses the LOWERCASE spelling on purpose: an uppercase one passes against the old
# uppercase-only scanner too, so it could not prove the widening. This one is red before the
# `grep -i` above and green after.
{ cat "$JS"; printf "\n// fetch('floor.json', { method: 'post' })\n"; } > "$MUT_WRITE" 2>/dev/null
if mutant_ok "$JS" "$MUT_WRITE"; then
  m_write="$(grep -inE "(method[[:space:]]*[:=][[:space:]]*['\"]?(post|put|delete)|['\"](post|put|delete)['\"])" "$MUT_WRITE" 2>/dev/null || true)"
  [ -n "$m_write" ] \
    && ok "(j14) MUTATION CONTROL: a LOWERCASE post token added to floor.js IS flagged by no_write_verbs (an uppercase-only scanner would have missed it)" \
    || no "(j14) MUTATION CONTROL: a POST token added to floor.js IS flagged by no_write_verbs" "scanner said: ${m_write:-<nothing>}"
fi

# --- (j32) a COUNTED surface with NO detail must not be rendered as an EMPTY one --------------
# A projection from a projector older than this page carries `status: counted, count: N` and no
# `detail` at all - `schema_version` stayed 1, so that combination is deliberately legal. The
# first cut of renderRules fell back to `rows.length` there and printed "(0 rule(s))" +
# "no rules recorded" for a store the projector had actually counted: a measured value displayed
# identically to an examined-and-empty one.
#
# The distinction cannot key on `detail` alone, and that was established by MEASUREMENT, not
# taste: a genuinely empty store also yields `counted / count 0` with NO detail, so the two
# shapes are identical apart from the count. `count` is therefore what separates them - zero
# files means there is nothing to browse either way, while a POSITIVE count with no detail means
# this page cannot enumerate a store that was counted.
[ "$(grep -c 'rules_parsed === .number. ? detail.rules_parsed : rows.length' "$JS")" = "0" ] \
  && ok "(j32) renderRules does NOT fall back to rows.length for a counted-but-detail-less surface" \
  || no "(j32) renderRules still falls back to rows.length - a counted surface renders as 0 rule(s)"

for lit in 'no rule detail in this projection' 'carries no rule detail' 'carries no churn detail'; do
  [ "$(grep -cF "$lit" "$JS")" -ge 1 ] \
    && ok "(j32) floor.js carries the never-examined literal: $lit" \
    || no "(j32) floor.js is missing the never-examined literal: $lit"
done

# ...and the EXAMINED-and-empty claim must still be reachable, or the fix traded one false
# statement for another.
[ "$(grep -cF 'no rules recorded' "$JS")" -ge 1 ] && [ "$(grep -cF 'no churn recorded' "$JS")" -ge 1 ] \
  && ok "(j32) the examined-and-empty claims are still present, so the fix did not delete the distinction" \
  || no "(j32) an examined-and-empty literal vanished - the never-examined text cannot be the only render"

# MUTATION CONTROL: restore the rows.length fallback and show (j32)'s first assertion goes red.
MUT_ZERO="$TMPROOT/mut-zero.js"
sed "s|if (typeof detail.rules_parsed === 'number') {|var n = (typeof detail.rules_parsed === 'number') ? detail.rules_parsed : rows.length; if (false) {|" "$JS" > "$MUT_ZERO" 2>/dev/null
if [ -s "$MUT_ZERO" ] && ! cmp -s "$MUT_ZERO" "$JS"; then
  [ "$(grep -c 'rows.length' "$MUT_ZERO")" -gt "$(grep -c 'rows.length' "$JS")" ] \
    && ok "(j33) MUTATION CONTROL: reintroducing the rows.length fallback IS detectable by (j32)'s scan" \
    || no "(j33) MUTATION CONTROL: the reintroduced fallback was not detectable - (j32) proves nothing"
else
  no "(j33) MUTATION CONTROL: could not build the rows.length mutant - control inconclusive"
fi

# --- (j34) applies_to / check have a FOURTH state, and it must not read as the first ----------
# Found by the CI reviewer on this PR, after both the Phase 4.5 review and my own pass missed it.
# ruleScopeLabel handled absent / null / array correctly and then fell through to the SAME string
# it uses for key-absent on any other value — so a rule written `"applies_to": "src/**"` (the
# bracket-forgotten authoring slip) rendered as "no scope recorded", indistinguishable from a rule
# that never declared a scope at all. That is the exact collapse the null branch exists to
# prevent, recurring one branch later.
#
# It is not hypothetical: read-rules.sh carries a dedicated WARN channel for a malformed
# applies_to, and build-floor.sh forwards the value verbatim whenever the key is present without
# validating its shape, so the malformed value reaches the page intact. The committed fixture now
# holds one such rule (id fixture-malformed-applies-to: applies_to a bare string, check an array).
[ "$(grep -cF 'applies_to is present but malformed' "$JS")" -ge 1 ] \
  && ok "(j34) floor.js names the malformed applies_to state instead of reusing the absent-key text" \
  || no "(j34) floor.js has no distinct label for a malformed applies_to - it collapses into 'no scope recorded'"

[ "$(grep -cF 'check is present but malformed' "$JS")" -ge 1 ] \
  && ok "(j34) floor.js names a malformed check rather than concatenating it into junk" \
  || no "(j34) floor.js would stringify a non-string check into the label"

# The absent-key text must still exist, and must NOT be what the malformed branch returns.
if grep -qF 'no scope recorded' "$JS"; then
  ok "(j34) the absent-key label is still present, so the fix added a state rather than renaming one"
else
  no "(j34) the absent-key label vanished - the malformed fix replaced the wrong branch"
fi

# MUTATION CONTROL: collapse the malformed branch back onto the absent-key text and prove (j34) reddens.
MUT_SCOPE="$TMPROOT/mut-scope.js"
sed "s|return 'applies_to is present but malformed (' +|return 'no scope recorded'; var _dead = (|" "$JS" > "$MUT_SCOPE" 2>/dev/null
if [ -s "$MUT_SCOPE" ] && ! cmp -s "$MUT_SCOPE" "$JS"; then
  [ "$(grep -cF 'applies_to is present but malformed' "$MUT_SCOPE")" -lt "$(grep -cF 'applies_to is present but malformed' "$JS")" ] \
    && ok "(j35) MUTATION CONTROL: collapsing the malformed branch back onto the absent-key text IS detected by (j34)" \
    || no "(j35) MUTATION CONTROL: the collapse was not detected - (j34) proves nothing"
else
  no "(j35) MUTATION CONTROL: could not build the scope-collapse mutant - control inconclusive"
fi

# --- (j40) the THIRD and FOURTH fields get the same branch coverage as the first two ----------
# (j34)/(j35) proved applies_to and check name their malformed state, with a mutation control.
# supersedes and provenance - the fields fixed one and two commits later, in a PR whose own
# narrative is "the same class, one field over" - got only (j36)'s does-the-function-exist check.
# That is real coverage but strictly weaker, and it is exactly the asymmetry that let the first
# two slips through. Every branch of all four label functions is now asserted by its literal, and
# every one has a driving fixture: `supersedes: ""` and the two malformed provenance shapes had
# no fixture at all before this, so three branches were unreachable from any committed input.
for lit in \
  'supersedes is present but malformed' \
  'declared, but recorded as null' \
  'declared, but empty' \
  'provenance is present but malformed' \
  'carries no source or added field'; do
  [ "$(grep -cF "$lit" "$JS")" -ge 1 ] \
    && ok "(j40) floor.js names this branch rather than collapsing it: $lit" \
    || no "(j40) floor.js is missing the branch literal: $lit"
done

# The fixtures that DRIVE those branches must exist, or the literals above are decoration.
rules_fx="$script_dir/fixtures/floor-rules/process.json"
[ "$(jq -r '[.[] | select(has("supersedes") and .supersedes == "")] | length' "$rules_fx" 2>/dev/null)" -ge 1 ] \
  && ok "(j40) a fixture rule carries supersedes as an EMPTY string" \
  || no "(j40) no fixture drives the empty-supersedes branch"
[ "$(jq -r '[.[] | select((.provenance | type) != "object" and (.provenance | type) != "string")] | length' "$rules_fx" 2>/dev/null)" -ge 1 ] \
  && ok "(j40) a fixture rule carries a provenance that is neither object nor string" \
  || no "(j40) no fixture drives the malformed-provenance branch"
[ "$(jq -r '[.[] | select((.provenance | type) == "object" and (has("provenance")) and ((.provenance | has("source")) or (.provenance | has("added")) | not))] | length' "$rules_fx" 2>/dev/null)" -ge 1 ] \
  && ok "(j40) a fixture rule carries a provenance object with neither source nor added" \
  || no "(j40) no fixture drives the provenance-object-missing-both-fields branch"

# MUTATION CONTROL: collapse the supersedes malformed branch onto its null text and the
# provenance one onto a bare concatenation; (j40) must see both.
MUT_S4="$TMPROOT/mut-fourth.js"
sed -e "s|return 'supersedes is present but malformed (' +|return 'supersedes: declared, but recorded as null — names no rule'; var _d1 = (|" \
    -e "s|return 'provenance is present but malformed (' +|return 'provenance: ' + v; var _d2 = (|" "$JS" > "$MUT_S4" 2>/dev/null
if [ -s "$MUT_S4" ] && ! cmp -s "$MUT_S4" "$JS"; then
  m_lost=0
  for lit in 'supersedes is present but malformed' 'provenance is present but malformed'; do
    [ "$(grep -cF "$lit" "$MUT_S4")" -lt "$(grep -cF "$lit" "$JS")" ] && m_lost=$((m_lost+1))
  done
  [ "$m_lost" -eq 2 ] \
    && ok "(j41) MUTATION CONTROL: collapsing BOTH fourth-state branches IS detected by (j40)" \
    || no "(j41) MUTATION CONTROL: only $m_lost of 2 collapsed branches were detected - (j40) is partly vacuous"
else
  no "(j41) MUTATION CONTROL: could not build the fourth-state mutant - control inconclusive"
fi

# --- (j42) the three curation-fault RENDER branches, driven by a UI fixture -------------------
# (y)/(y2) in test-build-floor.sh pinned these three on the PROJECTOR side. The RENDER side was
# still uncovered: floor.js has a branch for each of files_not_an_array, self_referential and
# duplicate_ids, and no committed floor-ui fixture populated ANY of them, so all three drew text
# nothing exercised. Same gap the previous round closed for supersedes/provenance, one surface
# over - which is why the fixture is committed here rather than the assertion alone.
RC_FAULTS="$script_dir/fixtures/floor-ui/floor-rules-curation-faults.json"
if [ -r "$RC_FAULTS" ]; then
  for k in files_not_an_array self_referential duplicate_ids; do
    n="$(jq -r --arg k "$k" '[(.surfaces.rules.detail[$k] // .surfaces.rules.detail.supersedes[$k] // [])[]] | length' "$RC_FAULTS" 2>/dev/null)"
    [ "${n:-0}" -ge 1 ] 2>/dev/null \
      && ok "(j42) the curation-faults fixture populates $k ($n entr(y/ies))" \
      || no "(j42) the curation-faults fixture does not populate $k - its render branch is undriven"
  done
  for lit in 'parsed but not understood' 'self-referential:' 'duplicate id:'; do
    [ "$(grep -cF "$lit" "$JS")" -ge 1 ] \
      && ok "(j42) floor.js carries the curation-fault literal: $lit" \
      || no "(j42) floor.js is missing the curation-fault literal: $lit"
  done
  # MUTATION CONTROL: drop the files_not_an_array render and require (j42) to notice.
  MUT_CF="$TMPROOT/mut-curation.js"
  sed "s@liNA.textContent = 'parsed but not understood: ' +@liNA.textContent = 'x' + (@" "$JS" > "$MUT_CF" 2>/dev/null
  if [ -s "$MUT_CF" ] && ! cmp -s "$MUT_CF" "$JS"; then
    [ "$(grep -cF 'parsed but not understood' "$MUT_CF")" -lt "$(grep -cF 'parsed but not understood' "$JS")" ] \
      && ok "(j43) MUTATION CONTROL: removing the not-understood render IS detected by (j42)" \
      || no "(j43) MUTATION CONTROL: the removal was not detected - (j42) proves nothing"
  else
    no "(j43) MUTATION CONTROL: could not build the curation mutant - control inconclusive"
  fi
else
  no "(j42) committed fixture $RC_FAULTS is missing - the curation-fault renders are undriven"
fi

# The provenance sub-fields are PRESENCE-checked, not truthy: an empty-but-present `source` used
# to be dropped and, with `added` also empty, the page then claimed the object carried NEITHER
# field while both keys were there - a false statement about the store.
for lit in 'source declared, but empty' 'added declared, but empty' 'check: declared, but empty'; do
  [ "$(grep -cF "$lit" "$JS")" -ge 1 ] \
    && ok "(j42) floor.js names the declared-but-empty state: $lit" \
    || no "(j42) floor.js collapses a declared-but-empty value: $lit"
done
[ "$(grep -c "typeof v.source === 'string' && v.source" "$JS")" = "0" ] \
  && ok "(j42) ruleProvenanceLabel no longer truthiness-tests its sub-fields" \
  || no "(j42) ruleProvenanceLabel still drops a present-but-empty source"

# --- (j44) the duplicate-id line must not state a resolution rule the projector contradicts ---
# The render said "first seen wins". The projector is LAST-write-wins: the edge map is `add` over
# single-key objects, so two rules sharing an id with different `supersedes` resolve to the LAST
# edge and the first vanishes. It was also false the other way round - `rules[]` dedups nothing,
# both rows are rendered. A false statement in the one view whose premise is reporting curation
# history faithfully, and the existing assertion could not catch it because it matched only the
# `duplicate id:` PREFIX. This pins the CLAUSE.
[ "$(grep -cF 'first seen wins' "$JS")" -le 1 ] \
  && ok "(j44) the duplicate-id render no longer claims first-seen-wins (any survivor is the comment explaining why)" \
  || no "(j44) 'first seen wins' still appears outside the explanatory comment"
grep -n 'liDI.textContent' -A2 "$JS" 2>/dev/null | grep -qF 'the walk follows the last' \
  && ok "(j44) the duplicate-id render states the actual resolution rule (walk follows the last)" \
  || no "(j44) the duplicate-id render does not state the projector's real resolution rule"

# The claim on the page and the claim in the projector must not diverge again.
grep -qF 'LAST-write-wins' "$script_dir/build-floor.sh" \
  && ok "(j44) build-floor.sh still documents LAST-write-wins, so page and projector agree" \
  || no "(j44) build-floor.sh no longer documents the merge order the page now cites"

# MUTATION CONTROL: restore the false clause and require (j44) to catch it.
MUT_DUP="$TMPROOT/mut-dup.js"
sed 's@ appears more than once in the merged store — both rows are listed above; where duplicates carry different supersedes values the walk follows the last@ appears more than once in the merged store — first seen wins@' "$JS" > "$MUT_DUP" 2>/dev/null
if [ -s "$MUT_DUP" ] && ! cmp -s "$MUT_DUP" "$JS"; then
  [ "$(grep -cF 'first seen wins' "$MUT_DUP")" -gt "$(grep -cF 'first seen wins' "$JS")" ] \
    && ok "(j45) MUTATION CONTROL: restoring the false first-seen-wins clause IS detected by (j44)" \
    || no "(j45) MUTATION CONTROL: the restored false clause was not detected - (j44) proves nothing"
else
  no "(j45) MUTATION CONTROL: could not build the duplicate-id mutant - control inconclusive"
fi

# The discovery surface must name --publish; commands/handoff.md documenting it is not enough,
# because check-command-sync.sh does not cover agent-help's Usage prose - which is exactly why
# all seven gates went green over the omission.
AH="$script_dir/../commands/agent-help.md"
if [ -r "$AH" ]; then
  grep -qF -- '--publish' "$AH" \
    && ok "(j44) agent-help.md's /handoff entry names --publish" \
    || no "(j44) agent-help.md still shows the pre-flag /handoff usage"
  grep -qF 'snapshot.md' "$AH" \
    && ok "(j44) agent-help.md names the snapshot output path" \
    || no "(j44) agent-help.md does not name .supervisor/handoff/snapshot.md"
else
  no "(j44) commands/agent-help.md is unreadable - the discovery-surface check cannot run"
fi

# --- (j38) no committed fixture pins a key the projector can no longer emit -------------------
# THE MISSING GATE, and the reason this case exists rather than the one-line fix above it.
#
# The evidence hoist changed a producer's serialisation, updated the producer's own test, and
# left the CONSUMER (floor.js) and the consumer's FIXTURES untouched. floor.js went on reading
# matched[].evidence, which the projector had stopped emitting, so every correlation rendered
# with no evidence under it while three doc surfaces claimed otherwise. The suite stayed green
# because (j31) asserted the OBSOLETE shape against a fixture that still had it: the fixture
# pinned the dead serialisation and disarmed the assertion meant to guard it. Regenerating the
# fixture correctly is what turned (j31) red.
#
# So the durable property is not "correlations carry evidence" - it is that a committed fixture
# never pins a key its producer can no longer emit. Checking that direction (fixture -> live)
# rather than equality is deliberate: fixtures legitimately model ABSENT and EMPTY surfaces and
# so carry FEWER keys than a live run, but a fixture carrying MORE is always drift.
# The reference is the UNION of SEVERAL runs, not one. A single projection cannot exercise
# mutually exclusive states - a store is either fully parsed or partly unparseable, a ledger
# either clean or malformed - so one run's missing keys would read as fixture drift. Seeding a
# bare repo produced 12-25 false positives per fixture and a clean-only seed still produced 7;
# the fixtures were right and the reference was impoverished each time. Union of: clean inputs,
# broken inputs, and a state.md.
ph_paths_of() {
  # UNFILTERED `paths`, deliberately: a filtered `paths(...)` yields only LEAF paths, so an
  # object-valued field registers as its children (provenance.added / provenance.source) and
  # never as `provenance` itself - while a fixture carrying that field as a STRING leafs at
  # `provenance` and read as drift. Both shapes are legal (the projector forwards provenance
  # verbatim and ruleProvenanceLabel handles a string), so that was a false positive of this
  # gate, not a defect in the fixture. Unfiltered paths include the intermediates, so a scalar
  # is always a subset of the object form.
  jq -r '[paths | select(.[0]=="surfaces") | join(".")] | .[]' "$1" 2>/dev/null \
    | grep -E '^surfaces\.[a-z_]+\.detail' | sed -E 's/\.[0-9]+(\.|$)/.[]\1/g' | LC_ALL=C sort -u
}
ph_seed() {   # $1 = repo dir, $2 = "clean"|"broken"
  mkdir -p "$1/.agent" "$1/agents" "$1/.supervisor/postmortem" "$1/.supervisor/logs"
  cp "$script_dir"/fixtures/floor-agents/*.md "$1/agents/" 2>/dev/null
  cp "$script_dir/fixtures/floor-sessions-current.jsonl" "$1/.supervisor/logs/ref.jsonl" 2>/dev/null
  # NB the leading "- ": st_field matches list items, so a bare `session_id:` parses as
  # nothing and the four state.detail keys never appear in the reference.
  printf '## Session\n- session_id: ref\n- branch: ref\n- status: running\n- phase: EXECUTE\n\n## Subtasks\n\n| # | Title | Status |\n|---|---|---|\n| 1 | ref | done |\n' > "$1/.supervisor/state.md"
  if [ "$2" = "broken" ]; then
    mkdir -p "$1/.agent/rules"
    cp "$script_dir"/fixtures/floor-rules-broken/*.json "$1/.agent/rules/" 2>/dev/null
    cp "$script_dir"/fixtures/floor-rules/*.json "$1/.agent/rules/" 2>/dev/null
    cp "$script_dir/fixtures/floor-postmortem-malformed.jsonl" "$1/.supervisor/postmortem/results.jsonl" 2>/dev/null
  elif [ "$2" = "curation" ]; then
    # Produces self_referential / duplicate_ids / files_not_an_array, which neither the clean nor
    # the broken seed emits - without this variant the reference lacks those keys and the
    # curation-faults FIXTURE reads as drift. The union is only as complete as its arms.
    mkdir -p "$1/.agent/rules"
    cp "$script_dir"/fixtures/floor-rules-curation/*.json "$1/.agent/rules/" 2>/dev/null
    cp "$script_dir/fixtures/floor-postmortem.jsonl" "$1/.supervisor/postmortem/results.jsonl" 2>/dev/null
  else
    cp -R "$script_dir/fixtures/floor-rules" "$1/.agent/rules" 2>/dev/null
    cp "$script_dir/fixtures/floor-postmortem.jsonl" "$1/.supervisor/postmortem/results.jsonl" 2>/dev/null
  fi
  ( cd "$1" && FLOOR_AGENTS_DIR="$1/agents" bash "$script_dir/build-floor.sh" >/dev/null 2>&1 )
}
live_paths="$TMPROOT/parity-live.paths"; : > "$live_paths"
ph_ok=1
for variant in clean broken curation; do
  ph_repo="$(mktemp -d "$TMPROOT/parity.XXXXXX")"
  ph_seed "$ph_repo" "$variant"
  if [ -s "$ph_repo/.supervisor/floor/floor.json" ]; then
    ph_paths_of "$ph_repo/.supervisor/floor/floor.json" >> "$live_paths"
  else
    ph_ok=0
  fi
done
LC_ALL=C sort -u "$live_paths" -o "$live_paths"

if [ "$ph_ok" -eq 1 ] && [ -s "$live_paths" ]; then
  parity_drift=""
  for fx in "$script_dir"/fixtures/floor-ui/*.json; do
    [ -e "$fx" ] || continue
    extra="$(ph_paths_of "$fx" | LC_ALL=C comm -23 - "$live_paths" | tr '\n' ' ')"
    [ -n "$extra" ] && parity_drift="$parity_drift | $(basename "$fx"): $extra"
  done
  [ -z "$parity_drift" ] \
    && ok "(j38) no committed floor-ui fixture pins a detail key the current projector cannot emit ($(wc -l < "$live_paths" | tr -d ' ') reference key paths across the clean, broken and curation runs)" \
    || no "(j38) FIXTURE/PROJECTOR SHAPE DRIFT - a fixture pins a key the producer no longer emits:$parity_drift"

  # ANTI-VACUITY: the comparison must be able to see a difference at all.
  ph_mut="$TMPROOT/parity-mutant.json"
  jq '.surfaces.rules.detail.correlations[0] += {a_key_the_projector_never_emits: 1}' \
     "$script_dir/fixtures/floor-ui/floor-rules-churn-live.json" > "$ph_mut" 2>/dev/null
  if [ -s "$ph_mut" ]; then
    [ -n "$(ph_paths_of "$ph_mut" | LC_ALL=C comm -23 - "$live_paths")" ] \
      && ok "(j39) ANTI-VACUITY: an injected phantom key IS seen by the parity comparison" \
      || no "(j39) ANTI-VACUITY FAILED: the comparison cannot see an injected key - (j38) proves nothing"
  else
    no "(j39) ANTI-VACUITY: could not build the parity mutant - control inconclusive"
  fi
else
  no "(j38) could not generate the reference projections for the fixture-parity comparison"
fi

# --- (j36) every page region has a FLOOR_UI.md row, and every optional field a guard ----------
# FLOOR_UI.md opens its table with "The page shows, top to bottom:" - an EXHAUSTIVE claim. This
# PR added two sections to index.html and did not touch the doc, so a reader consulting the
# authoritative page document would have concluded the Floor has no rules browser and no churn
# view. check-doc-currency.sh passed throughout: it verifies claims that ARE made and structurally
# cannot see one that should have been made, a caveat CLAUDE.md already records about it. This is
# the gate that can.
ui_doc="$script_dir/../docs/FLOOR_UI.md"
if [ -r "$ui_doc" ]; then
  missing_region=""
  for sec in $(grep -oE 'aria-labelledby="[a-z]+-h"' "$HTML" | sed 's/.*"\([a-z]*\)-h"/\1/'); do
    # the heading text is the region's name; require the doc to mention it in the table
    grep -qiE "^\| .*\*\*$sec" "$ui_doc" || grep -qi "$sec" "$ui_doc" || missing_region="$missing_region $sec"
  done
  [ -z "$missing_region" ] \
    && ok "(j36) every index.html section is described in FLOOR_UI.md's page-region table" \
    || no "(j36) FLOOR_UI.md's exhaustive region table omits:$missing_region"
else
  no "(j36) FLOOR_UI.md is unreadable - the region-parity gate cannot run"
fi

# All FOUR optional/objected rule fields get a presence-and-shape guard, not just the two that
# were fixed first. supersedes was left raw one commit after applies_to and check were guarded
# (the same class, one field over), and provenance - an OBJECT - was concatenated straight in,
# printing "provenance: [object Object]" on EVERY card against the real store.
for fn in ruleScopeLabel ruleCheckLabel ruleSupersedesLabel ruleProvenanceLabel; do
  [ "$(grep -c "function $fn" "$JS")" -ge 1 ] \
    && ok "(j36) $fn exists - the field is shape-guarded, not concatenated" \
    || no "(j36) $fn is missing - that field is rendered raw"
done

# The junk string itself must be unreachable from any rule field on a REAL-shaped store.
[ "$(grep -c "'supersedes: ' + rule.supersedes" "$JS")" = "0" ] \
  && [ "$(grep -c "'provenance: ' + rule.provenance" "$JS")" = "0" ] \
  && ok "(j36) neither supersedes nor provenance is concatenated raw onto the card" \
  || no "(j36) a rule field is still concatenated raw - [object Object] is reachable"

# MUTATION CONTROL: restore the raw provenance concatenation and show (j36) reddens.
MUT_PROV="$TMPROOT/mut-prov.js"
sed "s|var provLabel = ruleProvenanceLabel(rule);|var provLabel = null; bits.push('provenance: ' + rule.provenance);|" "$JS" > "$MUT_PROV" 2>/dev/null
if [ -s "$MUT_PROV" ] && ! cmp -s "$MUT_PROV" "$JS"; then
  [ "$(grep -c "'provenance: ' + rule.provenance" "$MUT_PROV")" -gt 0 ] \
    && ok "(j37) MUTATION CONTROL: reintroducing the raw provenance concatenation IS detected by (j36)" \
    || no "(j37) MUTATION CONTROL: the raw concatenation was not detected - (j36) proves nothing"
else
  no "(j37) MUTATION CONTROL: could not build the provenance mutant - control inconclusive"
fi

# --- AC-views-four-states: the four distinct renders, by their own literals ------------------
check_lit "$JS" "rules surface is not present in floor.json"      "(j15) rules ABSENT (surface key missing) has its own literal"
check_lit "$JS" "postmortem surface is not present in floor.json" "(j16) churn ABSENT (surface key missing) has its own literal"
check_lit "$JS" "no rules recorded"                                "(j17) rules EMPTY (counted, nothing in it) has its own literal, distinct from absent"
check_lit "$JS" "no churn recorded"                                "(j18) churn EMPTY (counted, nothing in it) has its own literal, distinct from absent"
check_lit "$JS" "could not examine every rule file:"               "(j19) rules UNAVAILABLE quotes the projector's own reason, distinct from empty and absent"
check_lit "$JS" "could not examine every ledger line:"             "(j20) churn UNAVAILABLE quotes the projector's own reason, distinct from empty and absent"
check_lit "$JS" "could not examine"                                "(j21) an unparseable rules FILE renders 'could not examine <file>', never silently as clean"

# --- fixture facts the browser half will read (mirrors group (e)'s style) --------------------
RC_LIVE="$FIX_DIR/floor-rules-churn-live.json"
RC_ABSENT="$FIX_DIR/floor-rules-churn-absent.json"
RC_EMPTY="$FIX_DIR/floor-rules-churn-empty.json"
RC_UNAVAIL="$FIX_DIR/floor-rules-churn-unavailable.json"
RC_STALE="$FIX_DIR/floor-rules-churn-stale.json"

rc_absent_keys="$(jq -r '.surfaces | has("rules"), has("postmortem")' "$RC_ABSENT" 2>/dev/null | tr '\n' ' ')"
[ "$rc_absent_keys" = "false false " ] \
  && ok "(j22) floor-rules-churn-absent carries NEITHER the rules NOR the postmortem surface key" \
  || no "(j22) floor-rules-churn-absent carries neither surface key" "got: $rc_absent_keys"

rc_empty_shape="$(jq -r '"\(.surfaces.rules.status)/\(.surfaces.rules|has("count"))/\(.surfaces.rules|has("detail"))/\(.surfaces.postmortem.status)/\(.surfaces.postmortem.detail.categories_total)"' "$RC_EMPTY" 2>/dev/null)"
[ "$rc_empty_shape" = "counted/true/false/counted/0" ] \
  && ok "(j23) floor-rules-churn-empty: both surfaces counted with nothing in them (rules count 0 no detail, postmortem categories_total 0)" \
  || no "(j23) floor-rules-churn-empty: both surfaces counted with nothing in them" "got: $rc_empty_shape"

rc_unavail_shape="$(jq -r '"\(.surfaces.rules.status)/\(.surfaces.rules|has("count"))/\(.surfaces.rules.detail|has("files_unparseable"))/\(.surfaces.postmortem.status)/\(.surfaces.postmortem.detail|has("malformed_lines"))"' "$RC_UNAVAIL" 2>/dev/null)"
[ "$rc_unavail_shape" = "unverified/false/true/unverified/true" ] \
  && ok "(j24) floor-rules-churn-unavailable: both surfaces unverified, no count, and the reason is named (files_unparseable / malformed_lines)" \
  || no "(j24) floor-rules-churn-unavailable: both surfaces unverified with a named reason" "got: $rc_unavail_shape"
rc_unavail_partial="$(jq -r '.surfaces.rules.detail.rules | length' "$RC_UNAVAIL" 2>/dev/null)"
[ "${rc_unavail_partial:-0}" -ge 1 ] 2>/dev/null \
  && ok "(j25) floor-rules-churn-unavailable STILL reports the valid file's rules ($rc_unavail_partial recorded) — could-not-examine never means examined-and-clean" \
  || no "(j25) floor-rules-churn-unavailable still reports the valid file's rules" "found $rc_unavail_partial"

g_rc_live="$(jq -r '.generated_at_epoch' "$RC_LIVE" 2>/dev/null)"
g_rc_stale="$(jq -r '.generated_at_epoch' "$RC_STALE" 2>/dev/null)"
if [ "$g_rc_stale" -lt $((g_rc_live - 86400)) ] 2>/dev/null; then
  ok "(j26) floor-rules-churn-stale's generation time is more than a day older than floor-rules-churn-live's ($g_rc_stale vs $g_rc_live)"
else
  no "(j26) floor-rules-churn-stale's generation time is far older than floor-rules-churn-live's" "stale=$g_rc_stale live=$g_rc_live"
fi
# CONTROL: the stale fixture still carries the SAME rules/churn content as live, so the browser
# half can show the views keep rendering recorded data while the freshness banner is up.
rc_stale_same="$(jq -r '.surfaces.rules.detail.rules_parsed == '"$(jq -r '.surfaces.rules.detail.rules_parsed' "$RC_LIVE" 2>/dev/null)" "$RC_STALE" 2>/dev/null)"
[ "$rc_stale_same" = "true" ] \
  && ok "(j27) CONTROL: floor-rules-churn-stale carries the same rules_parsed count as -live, so staleness alone is what differs" \
  || no "(j27) CONTROL: floor-rules-churn-stale carries the same rules_parsed count as -live" "got $rc_stale_same"

# --- the tri-state fixture coverage AC-rules-detail demands is present in THIS bundle's own
# fixture too (subtask 1 proved it at the projector; this proves the browser fixture still has it)
n_applies_absent="$(jq -r '[.surfaces.rules.detail.rules[] | select(has("applies_to")|not)] | length' "$RC_LIVE" 2>/dev/null)"
n_applies_null="$(jq -r '[.surfaces.rules.detail.rules[] | select(has("applies_to")) | select(.applies_to == null)] | length' "$RC_LIVE" 2>/dev/null)"
n_applies_array="$(jq -r '[.surfaces.rules.detail.rules[] | select(has("applies_to")) | select(.applies_to != null)] | length' "$RC_LIVE" 2>/dev/null)"
[ "${n_applies_absent:-0}" -ge 1 ] 2>/dev/null && [ "${n_applies_null:-0}" -ge 1 ] 2>/dev/null && [ "${n_applies_array:-0}" -ge 1 ] 2>/dev/null \
  && ok "(j28) floor-rules-churn-live exercises all three applies_to shapes: absent=$n_applies_absent null=$n_applies_null array=$n_applies_array" \
  || no "(j28) floor-rules-churn-live exercises all three applies_to shapes" "absent=$n_applies_absent null=$n_applies_null array=$n_applies_array"
n_check_absent="$(jq -r '[.surfaces.rules.detail.rules[] | select(has("check")|not)] | length' "$RC_LIVE" 2>/dev/null)"
n_check_null="$(jq -r '[.surfaces.rules.detail.rules[] | select(has("check")) | select(.check == null)] | length' "$RC_LIVE" 2>/dev/null)"
n_check_val="$(jq -r '[.surfaces.rules.detail.rules[] | select(has("check")) | select(.check != null)] | length' "$RC_LIVE" 2>/dev/null)"
[ "${n_check_absent:-0}" -ge 1 ] 2>/dev/null && [ "${n_check_null:-0}" -ge 1 ] 2>/dev/null && [ "${n_check_val:-0}" -ge 1 ] 2>/dev/null \
  && ok "(j29) floor-rules-churn-live exercises all three check shapes: absent=$n_check_absent null=$n_check_null value=$n_check_val" \
  || no "(j29) floor-rules-churn-live exercises all three check shapes" "absent=$n_check_absent null=$n_check_null value=$n_check_val"
n_chains="$(jq -r '.surfaces.rules.detail.supersedes.chains | length' "$RC_LIVE" 2>/dev/null)"
n_dangling="$(jq -r '.surfaces.rules.detail.supersedes.dangling | length' "$RC_LIVE" 2>/dev/null)"
n_cycles="$(jq -r '.surfaces.rules.detail.supersedes.cycles | length' "$RC_LIVE" 2>/dev/null)"
[ "${n_chains:-0}" -ge 1 ] 2>/dev/null && [ "${n_dangling:-0}" -ge 1 ] 2>/dev/null && [ "${n_cycles:-0}" -ge 1 ] 2>/dev/null \
  && ok "(j30) floor-rules-churn-live exercises a chain, a dangling pointer AND a cycle: chains=$n_chains dangling=$n_dangling cycles=$n_cycles" \
  || no "(j30) floor-rules-churn-live exercises a chain, a dangling pointer and a cycle" "chains=$n_chains dangling=$n_dangling cycles=$n_cycles"
n_corr="$(jq -r '.surfaces.rules.detail.correlations | length' "$RC_LIVE" 2>/dev/null)"
# Evidence lives ONCE PER CORRELATION in `evidence_by_line`, keyed by line, not on each match.
# This assertion used to require `matched[].evidence` - a shape the projector stopped emitting -
# and stayed green ONLY because the committed fixture had not been regenerated after that change.
# The fixture pinned the obsolete serialisation and disarmed the assertion that was supposed to
# guard it; regenerating the fixture correctly turned this red, which is how it was found.
# Assert the property that matters instead: every matched line RESOLVES to evidence.
n_corr_unres="$(jq -r '[.surfaces.rules.detail.correlations[] as $c | $c.matched[].line | tostring as $l | select((($c.evidence_by_line // {}) | has($l)) | not)] | length' "$RC_LIVE" 2>/dev/null)"
n_corr_ev="$(jq -r '[.surfaces.rules.detail.correlations[].evidence_by_line // {} | to_entries[]] | length' "$RC_LIVE" 2>/dev/null)"
[ "${n_corr:-0}" -ge 1 ] 2>/dev/null && [ "${n_corr_ev:-0}" -ge 1 ] 2>/dev/null && [ "${n_corr_unres:-1}" -eq 0 ] 2>/dev/null \
  && ok "(j31) floor-rules-churn-live exercises a correlation whose every matched line resolves to evidence ($n_corr correlation(s), $n_corr_ev evidence line(s), 0 unresolved)" \
  || no "(j31) floor-rules-churn-live: a matched line does not resolve to evidence" "corr=$n_corr evidence-lines=$n_corr_ev unresolved=$n_corr_unres"

# The RESULT summary and the exit status are emitted by `finish` from the EXIT trap (see its
# definition above), so every assertion group below still runs and still counts.

# ===========================================================================
echo "(k) AC-registry — add / list / forget / scan, and the isolation that keeps them off the real tree"
# ===========================================================================
# WHY ISOLATION HERE IS NOT THE ISOLATION EVERY OTHER GROUP USES. This file's header says every
# engine case passes `--ui-dir` into its own `mktemp -d`. That is true, and for every other
# group it is enough. It is NOT enough here. The registry is deliberately a SIBLING of the ui
# directory — that sibling placement is the whole reason it survives `remove` — and the engine's
# arg loop sets only UI_DIR from `--ui-dir`, so `--ui-dir` provably cannot redirect it. A
# registry case written in the ordinary style would write the DEVELOPER'S OWN projects.json
# while every assertion in it passed. So every engine invocation below carries a fixture `HOME`
# (the precedent (f14)/(f15)/(f18) already set in this file) or the engine's explicit
# `--registry` override, and (k26) is a STATIC gate asserting exactly that, with a mutation
# control at (k27) that strips one `HOME=` and requires the gate to redden.
#
# The hash backstop ((k28)/(k29)) is deliberately NOT the primary assertion and could not be:
# an add-then-forget sequence — the natural shape of these cases — writes and then restores, so
# on a machine with no pre-existing registry the two hashes would match and the tree would
# still have been touched. The static gate is what enforces the rule; the hashes catch residue.

K="$(mktmp)" || setup_fail "(k) fixture: mktemp under $TMPROOT failed"
KH="$K/home"
mkdir -p "$KH" || setup_fail "(k) fixture: could not create the fixture HOME $KH"
KUI="$K/ui"

# The registry path is READ OUT of the engine under the fixture HOME instead of being spelled
# here. That does two jobs at once: it gives every assertion below a subject that cannot drift
# from the engine, and it is itself the proof that a fixture HOME is what redirects the registry.
KREG="$(HOME="$KH" bash "$ENGINE" check --ui-dir "$KUI" 2>/dev/null | sed -n 's/^registry: //p' | awk 'NR==1')"
case "$KREG" in
  "$KH"/*)
    ok "(k1) a fixture HOME redirects the registry the engine names — asserted rather than assumed, because --ui-dir structurally cannot do it" ;;
  *)
    no "(k1) a fixture HOME redirects the registry the engine names" \
       "the engine reported registry '$KREG', which is not under the fixture HOME $KH"
    KREG="$KH/unresolved-registry.json" ;;
esac

out="$(HOME="$KH" bash "$ENGINE" check --ui-dir "$KUI" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && in_str "$out" "UI readiness" && in_str "$out" "no projects registered" \
  && ok "(k2) check reports module state AND registry state in ONE report, and an absent registry reads as 'no projects registered', never as an error" \
  || no "(k2) check reports module and registry state in one report; an absent registry reads as 'no projects registered'" "rc=$rc :: $out"

[ ! -e "$KREG" ] \
  && ok "(k3) that check WROTE NOTHING — the registry file still does not exist" \
  || no "(k3) check writes nothing" "a read-only subcommand created $KREG"

# --- add ------------------------------------------------------------------------------
KP1="$K/proj-alpha"
mkdir -p "$KP1/.git" || setup_fail "(k) fixture: could not create the fixture project $KP1"
KP1_PHYS="$(cd -P "$KP1" 2>/dev/null && pwd -P)" || setup_fail "(k) fixture: could not resolve $KP1"
out="$(cd "$KP1" && HOME="$KH" bash "$ENGINE" add 2>&1)"; rc=$?
k_path="$(jq -r '[.projects[].path] | first // ""' "$KREG" 2>/dev/null)"
k_slug="$(jq -r '[.projects[].slug] | first // ""' "$KREG" 2>/dev/null)"
[ "$rc" -eq 0 ] && [ "$k_path" = "$KP1_PHYS" ] && [ "$k_slug" = "proj-alpha" ] \
  && ok "(k4) 'add' with no argument registers the CURRENT project by absolute path, with a slug derived from it (slug=$k_slug)" \
  || no "(k4) 'add' with no argument registers the current project by absolute path and derived slug" \
       "rc=$rc path='$k_path' (want '$KP1_PHYS') slug='$k_slug' (want 'proj-alpha') :: $out"

k_sig="$(csum "$KREG")"
out="$(cd "$KP1" && HOME="$KH" bash "$ENGINE" add 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && in_str "$out" "already registered" && [ "$k_sig" = "$(csum "$KREG")" ] \
  && ok "(k5) a second 'add' in the same project reports 'already registered' and leaves the registry byte-identical" \
  || no "(k5) a second 'add' reports 'already registered' and writes nothing" "rc=$rc :: $out"

k_sig="$(csum "$KREG")"
out="$(HOME="$KH" bash "$ENGINE" add "$K/no-such-project" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$KREG" ] && in_str "$out" "$K/no-such-project" && [ "$k_sig" = "$(csum "$KREG")" ] \
  && ok "(k6) 'add <path>' on a path that does not exist writes nothing and NAMES the path in the reason" \
  || no "(k6) 'add <path>' on a non-existent path writes nothing and names the path" "rc=$rc :: $out"

# Two projects sharing a basename. A colliding slug would make 'forget <slug>' ambiguous, which
# is a data-loss shape, so the slugs must differ even though the basenames do not.
KP2="$K/proj-beta"
KP3="$K/nest/proj-alpha"
mkdir -p "$KP2/.git" "$KP3/.git" || setup_fail "(k) fixture: could not create the sibling fixture projects"
HOME="$KH" bash "$ENGINE" add "$KP2" >/dev/null 2>&1
HOME="$KH" bash "$ENGINE" add "$KP3" >/dev/null 2>&1
k_n="$(jq -r '.projects | length' "$KREG" 2>/dev/null)"
k_uniq="$(jq -r '[.projects[].slug] | if (length) == (unique | length) then "unique" else "COLLIDING" end' "$KREG" 2>/dev/null)"
[ "$k_n" = "3" ] && [ "$k_uniq" = "unique" ] \
  && ok "(k7) three projects register, and two projects sharing a basename get DISTINCT slugs" \
  || no "(k7) three projects register with distinct slugs" "count='$k_n' (want 3) slugs='$k_uniq'"

# --- list -----------------------------------------------------------------------------
mkdir -p "$KP1/.supervisor/floor" && printf '{}\n' > "$KP1/.supervisor/floor/floor.json" \
  || setup_fail "(k) fixture: could not give $KP1 a floor.json for the age assertion"
rm -r "$KP2" 2>/dev/null
[ ! -d "$KP2" ] || setup_fail "(k) fixture: $KP2 had to be removed so 'unavailable' has a subject"

k_sig="$(csum "$KREG")"
out="$(HOME="$KH" bash "$ENGINE" list 2>&1)"; rc=$?
k_after="$(csum "$KREG")"
[ "$rc" -eq 0 ] && in_str "$out" "$KP1_PHYS" && in_str "$out" "proj-alpha" && in_str "$out" "ago" \
  && ok "(k8) 'list' prints each project with its path, its slug and its last-regenerated age" \
  || no "(k8) 'list' prints path, slug and last-regenerated age" "rc=$rc :: $out"
in_str "$out" "unavailable" \
  && ok "(k9) a registered project whose path is currently missing is marked 'unavailable'" \
  || no "(k9) a missing project path is marked 'unavailable'" "$out"
[ -f "$KREG" ] && [ -n "$k_sig" ] && [ "$k_sig" = "$k_after" ] \
  && ok "(k10) 'list' never mutates the registry — including on the run where an entry was unavailable" \
  || no "(k10) 'list' never mutates the registry" "the registry checksum changed across a read-only verb"

# --- forget ---------------------------------------------------------------------------
KP3_PHYS="$(cd -P "$KP3" 2>/dev/null && pwd -P)" || setup_fail "(k) fixture: could not resolve $KP3"
k_slug3="$(jq -r --arg p "$KP3_PHYS" '[.projects[] | select(.path == $p) | .slug] | first // ""' "$KREG" 2>/dev/null)"
[ -n "$k_slug3" ] || setup_fail "(k) fixture: $KP3_PHYS is not in the registry, so the forget assertions would have no subject"
kp3_before="$(tree_sig "$KP3")"
out="$(HOME="$KH" bash "$ENGINE" forget "$k_slug3" 2>&1)"; rc=$?
kp3_after="$(tree_sig "$KP3")"
k_still="$(jq -r --arg s "$k_slug3" '[.projects[] | select(.slug == $s)] | length' "$KREG" 2>/dev/null)"
[ "$rc" -eq 0 ] && [ "$k_still" = "0" ] \
  && ok "(k11) 'forget <slug>' removes exactly that entry from the registry" \
  || no "(k11) 'forget <slug>' removes that entry" "rc=$rc still-present='$k_still' :: $out"
[ -d "$KP3" ] && [ -n "$kp3_before" ] && [ "$kp3_before" = "$kp3_after" ] \
  && ok "(k12) 'forget' leaves the project DIRECTORY itself untouched — the tree is hashed before and after" \
  || no "(k12) 'forget' leaves the project directory untouched (hashed before and after)" \
       "dir=$([ -d "$KP3" ] && echo present || echo GONE) unchanged=$([ "$kp3_before" = "$kp3_after" ] && echo yes || echo NO)"

k_sig="$(csum "$KREG")"
out="$(HOME="$KH" bash "$ENGINE" forget not-a-registered-slug 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && in_str "$out" "not-a-registered-slug" && [ "$k_sig" = "$(csum "$KREG")" ] \
  && ok "(k13) 'forget' on an unregistered slug writes nothing and says so, naming the slug" \
  || no "(k13) 'forget' on an unregistered slug writes nothing and says so" "rc=$rc :: $out"

# --- the module's own `remove` must not take the registry with it ----------------------
HOME="$KH" bash "$ENGINE" apply --ui-dir "$KUI" >/dev/null 2>&1
[ -f "$KUI/.loomwright-ui-module" ] || setup_fail "(k) fixture: apply did not install into $KUI, so the remove assertion would be vacuous"
k_sig="$(csum "$KREG")"
out="$(HOME="$KH" bash "$ENGINE" remove --ui-dir "$KUI" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ ! -d "$KUI" ] && [ -f "$KREG" ] && [ "$k_sig" = "$(csum "$KREG")" ] \
  && ok "(k14) a module 'remove' deletes the ui dir and leaves the registry INTACT — asserted directly, not reasoned from the path" \
  || no "(k14) a module 'remove' leaves the registry intact" \
       "rc=$rc ui=$([ -d "$KUI" ] && echo present || echo gone) registry=$([ -f "$KREG" ] && echo present || echo GONE) unchanged=$([ "$k_sig" = "$(csum "$KREG")" ] && echo yes || echo NO) :: $out"

# --- a registry that is not valid JSON ------------------------------------------------
# The bad registry lives under its OWN fixture HOME, derived from the good one by substituting
# the home prefix, so the path is never restated and this block cannot corrupt the fixture above.
KBAD="$K/home-bad"
mkdir -p "$KBAD" || setup_fail "(k) fixture: could not create $KBAD"
KBADREG="$KBAD${KREG#$KH}"
mkdir -p "$(dirname "$KBADREG")" 2>/dev/null
printf 'this is not JSON {{{\n' > "$KBADREG" || setup_fail "(k) fixture: could not write the malformed registry at $KBADREG"
kbad_sig="$(csum "$KBADREG")"
bad_bad=""; bad_out=""
for v in add list forget scan check; do
  o="$(HOME="$KBAD" bash "$ENGINE" "$v" "$K" --ui-dir "$K/ui-bad" 2>&1)"; r=$?
  [ "$r" -eq 0 ] || bad_bad="$bad_bad [$v exit=$r]"
  in_str "$o" "not valid JSON" || bad_bad="$bad_bad [$v names-no-reason]"
  bad_out="$bad_out
  --- $v: $o"
done
[ -z "$bad_bad" ] \
  && ok "(k15) a registry that is not valid JSON makes every registry-touching subcommand (add/list/forget/scan/check) refuse by name and exit 0" \
  || no "(k15) an unparseable registry: every subcommand refuses by name and exits 0" "$bad_bad ::$bad_out"
[ "$kbad_sig" = "$(csum "$KBADREG")" ] \
  && ok "(k16) the unparseable registry is preserved BYTE FOR BYTE across all five — the engine never rewrites a file it could not read" \
  || no "(k16) the unparseable registry is preserved byte for byte" "its checksum changed"

# --- jq unfindable --------------------------------------------------------------------
# AC-1e requires this asserted by making jq UNFINDABLE, not by inspecting the source. The stub
# PATH is the same mechanism group (g) uses, and the probe below proves the stub really works —
# without it, (k18) would pass just as happily against a PATH that still resolved jq.
KSTUB="$K/bin-nojq"
mkstub "$KSTUB" "jq" || setup_fail "(k) fixture: could not build the jq-absent PATH stub"
[ ! -e "$KSTUB/jq" ] || setup_fail "(k) fixture: the jq-absent stub still contains jq"
kj_probe="$(PATH="$KSTUB" bash -c 'command -v jq' 2>/dev/null || true)"
[ -z "$kj_probe" ] \
  && ok "(k17) the probe makes jq genuinely UNFINDABLE on PATH, so (k18) is a measurement rather than an inspection" \
  || no "(k17) the jq-absent probe makes jq unfindable" "PATH=$KSTUB still resolves jq to '$kj_probe'"

KJH="$K/home-nojq"
mkdir -p "$KJH" || setup_fail "(k) fixture: could not create $KJH"
KJREG="$KJH${KREG#$KH}"
jq_bad=""; jq_out=""
for v in add list forget scan check; do
  o="$(PATH="$KSTUB" HOME="$KJH" bash "$ENGINE" "$v" "$K" --ui-dir "$K/ui-nojq" 2>&1)"; r=$?
  [ "$r" -eq 0 ] || jq_bad="$jq_bad [$v exit=$r]"
  in_str "$o" "jq" || jq_bad="$jq_bad [$v does-not-name-jq]"
  jq_out="$jq_out
  --- $v: $o"
done
[ -z "$jq_bad" ] && [ ! -e "$KJREG" ] \
  && ok "(k18) with jq UNFINDABLE, every registry subcommand names jq as the reason, writes no registry, and exits 0 — the posture the engine header states" \
  || no "(k18) with jq unfindable, every registry subcommand names jq, writes nothing and exits 0" \
       "$jq_bad registry=$([ -e "$KJREG" ] && echo CREATED || echo absent) ::$jq_out"

# --- scan -----------------------------------------------------------------------------
KSCAN="$K/scanroot"
mkdir -p "$KSCAN/one/.git" "$KSCAN/a/b/two/.git" "$KSCAN/a/b/c/d/deep/.git" \
  || setup_fail "(k) fixture: could not build the scan fixture tree"
KSCAN_PHYS="$(cd -P "$KSCAN" 2>/dev/null && pwd -P)" || setup_fail "(k) fixture: could not resolve $KSCAN"
KSH="$K/home-scan"
mkdir -p "$KSH" || setup_fail "(k) fixture: could not create $KSH"
KSREG="$KSH${KREG#$KH}"
out="$(HOME="$KSH" bash "$ENGINE" scan "$KSCAN" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && in_str "$out" "$KSCAN_PHYS/one" && in_str "$out" "$KSCAN_PHYS/a/b/two" \
  && ok "(k19) 'scan <dir>' lists the candidate projects it found" \
  || no "(k19) 'scan <dir>' lists the candidates it found" "rc=$rc :: $out"
[ ! -e "$KSREG" ] \
  && ok "(k20) an unconfirmed scan is a PROPOSAL: the registry was not written — not even created" \
  || no "(k20) an unconfirmed scan writes nothing" "$KSREG exists after a scan with no confirmation"
if in_str "$out" "$KSCAN_PHYS/a/b/c/d/deep"; then
  no "(k21) the scan is bounded by a stated maximum depth" "a repo five levels below the scan root was proposed"
elif in_str "$out" "depth"; then
  ok "(k21) the scan is BOUNDED and says so: a repo five levels below the scan root is not proposed, and the report states the maximum depth"
else
  no "(k21) the scan states its maximum depth" "the depth bound held, but the report never states it :: $out"
fi
out="$(HOME="$KSH" bash "$ENGINE" scan "$KSCAN" --confirm 2>&1)"; rc=$?
ks_n="$(jq -r '.projects | length' "$KSREG" 2>/dev/null)"
[ "$rc" -eq 0 ] && [ "$ks_n" = "2" ] \
  && ok "(k22) an explicit --confirm is what actually registers the proposal (the two candidates within the depth bound)" \
  || no "(k22) --confirm registers the proposed candidates" "rc=$rc registered='$ks_n' (want 2) :: $out"

KEMPTY="$K/scan-empty"
mkdir -p "$KEMPTY/no/repos/here" || setup_fail "(k) fixture: could not create $KEMPTY"
out="$(HOME="$KSH" bash "$ENGINE" scan "$KEMPTY" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && in_str "$out" "found no" \
  && ok "(k23) a scan that finds nothing SAYS so rather than printing an empty success" \
  || no "(k23) a scan that finds nothing says so" "rc=$rc :: $out"

# --- the explicit override, and having no registry to name at all ----------------------
KALT="$K/alt-registry.json"
k_sig="$(csum "$KREG")"
out="$(HOME="$KH" bash "$ENGINE" add "$KP1" --registry "$KALT" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$KALT" ] && [ "$k_sig" = "$(csum "$KREG")" ] \
  && ok "(k24) '--registry <file>' is honoured by registry_path and WINS over the HOME-derived default, which was not touched" \
  || no "(k24) '--registry <file>' is honoured and wins over the HOME-derived default" \
       "rc=$rc alt=$([ -f "$KALT" ] && echo written || echo MISSING) home-registry-unchanged=$([ "$k_sig" = "$(csum "$KREG")" ] && echo yes || echo NO) :: $out"

if env -u HOME true >/dev/null 2>&1 && [ "$(env -u HOME bash -c 'printf %s "${HOME:-<unset>}"' 2>/dev/null)" = "<unset>" ]; then
  out="$(env -u HOME bash "$ENGINE" list --ui-dir "$K/ui-nohome" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && in_str "$out" "--registry" \
    && ok "(k25) with HOME unset and no --registry there is no registry file to name: the engine says so by name and still exits 0" \
    || no "(k25) with HOME unset and no --registry, the engine aborts by name and exits 0" "rc=$rc :: $out"
else
  skipn "(k25) \`env -u\` cannot produce an unset HOME on this host, so the no-registry-to-name branch cannot be exercised"
fi

# --- MUTATION CONTROLS for (k12) and (k16) ---------------------------------------------
# (k12) and (k16) are both PRESERVATION assertions — "this hash did not change" — and a
# preservation assertion passes just as happily against an engine that never ran at all. Each
# therefore gets an engine mutant that commits exactly the damage the assertion claims to
# detect, and the control is that the damage IS detected. They are named after the assertions
# they guard rather than given the next free number, because a control is only meaningful
# beside its subject; (k26a)/(k26b) already establish the suffix form in this file. They sit
# here, BEFORE the (k28)/(k29) backstop, so that backstop still covers every engine invocation.
#
# Neither control mutates the real engine: each writes a separate copy and (k16d) re-hashes the
# original afterwards. The mutants live under $TMPROOT and go with it in the EXIT trap.
K_ENGINE_SIG_BEFORE="$(csum "$ENGINE")"
KMUTDIR="$K/mutbin"
mkdir -p "$KMUTDIR" || setup_fail "(k12c) fixture: could not create $KMUTDIR"
KMH="$K/home-mut"
mkdir -p "$KMH" || setup_fail "(k12c) fixture: could not create the mutant-control fixture HOME $KMH"
KMREG="$KMH${KREG#$KH}"
KMP="$K/mut-project"
mkdir -p "$KMP" || setup_fail "(k12c) fixture: could not create $KMP"
printf 'the user keeps this\n' > "$KMP/precious.txt" || setup_fail "(k12c) fixture: could not seed $KMP"

# (k12c) — an engine whose `forget` also deletes a file inside the project it is forgetting.
# That is precisely the data-loss shape R5 names, and (k12) exists to catch it.
KMUT_FORGET="$KMUTDIR/setup-ui-forget.sh"
awk 'BEGIN { done = 0 }
     {
       if (!done && index($0, "forget: removed") > 0) { print "  rm -f \"$gone/precious.txt\" 2>/dev/null"; done = 1 }
       print
     }' "$ENGINE" > "$KMUT_FORGET" 2>/dev/null
if mutant_ok "$ENGINE" "$KMUT_FORGET" shell; then
  HOME="$KMH" bash "$ENGINE" add "$KMP" >/dev/null 2>&1
  km_slug="$(jq -r '[.projects[].slug] | first // ""' "$KMREG" 2>/dev/null)"
  kmp_before="$(tree_sig "$KMP")"
  out="$(HOME="$KMH" bash "$KMUT_FORGET" forget "$km_slug" 2>&1)"; rc=$?
  kmp_after="$(tree_sig "$KMP")"
  km_left="$(jq -r '.projects | length' "$KMREG" 2>/dev/null)"
  # THE MUTANT MUST HAVE REACHED ITS OWN CODE PATH. A mutant that died early — a syntax error,
  # a missing fixture, an abort before the write — leaves the project tree untouched and is
  # indistinguishable from a control that failed to redden, so it is checked separately and
  # reported as a BROKEN CONTROL rather than allowed to look like either outcome.
  if [ -z "$km_slug" ] || [ "$km_left" != "0" ] || ! in_str "$out" "forget: removed"; then
    no "(k12c) MUTATION CONTROL: (k12) catches a forget that damages the project tree" \
       "the mutant never reached its own forget path, so this control proves nothing: slug='$km_slug' entries-left='$km_left' rc=$rc :: $out"
  elif [ -n "$kmp_before" ] && [ "$kmp_before" != "$kmp_after" ]; then
    ok "(k12c) MUTATION CONTROL: an engine whose forget deletes a file inside the registered project makes (k12)'s before/after tree hash DIFFER — (k12) can detect the damage it claims to"
  else
    no "(k12c) MUTATION CONTROL: (k12) catches a forget that damages the project tree" \
       "the mutant ran and removed the registry entry, but the project tree hash did not change — (k12) would NOT have caught it"
  fi
fi

# (k16c) — an engine that treats an UNPARSEABLE registry as an empty one instead of refusing.
# It is a one-token change (the rc-1 arm of reg_prepare's case swallowing rc 2 as well), and it
# is the realistic bug: the next `add` then overwrites whatever the user actually had there.
KMUT_BAD="$KMUTDIR/setup-ui-badreg.sh"
awk 'BEGIN { done = 0 }
     {
       if (!done && index($0, "1) REG_JSON=") > 0) { sub(/1\) REG_JSON=/, "1|2) REG_JSON="); done = 1 }
       print
     }' "$ENGINE" > "$KMUT_BAD" 2>/dev/null
if mutant_ok "$ENGINE" "$KMUT_BAD" shell; then
  KMBH="$K/home-mut-bad"
  mkdir -p "$KMBH" || setup_fail "(k16c) fixture: could not create $KMBH"
  KMBREG="$KMBH${KREG#$KH}"
  mkdir -p "$(dirname "$KMBREG")" 2>/dev/null
  printf 'this is not JSON {{{\n' > "$KMBREG" || setup_fail "(k16c) fixture: could not write the malformed registry at $KMBREG"
  kmb_before="$(csum "$KMBREG")"
  out="$(HOME="$KMBH" bash "$KMUT_BAD" add "$KMP" 2>&1)"; rc=$?
  kmb_after="$(csum "$KMBREG")"
  if ! in_str "$out" "add: registered"; then
    no "(k16c) MUTATION CONTROL: (k16) catches an engine that rewrites an unparseable registry" \
       "the mutant never reached its write path, so this control proves nothing: rc=$rc :: $out"
  elif [ -n "$kmb_before" ] && [ "$kmb_before" != "$kmb_after" ]; then
    ok "(k16c) MUTATION CONTROL: an engine that treats an unparseable registry as empty OVERWRITES it, and (k16)'s byte-for-byte checksum sees that — (k16) is not passing on a file nothing opened"
  else
    no "(k16c) MUTATION CONTROL: (k16) catches an engine that rewrites an unparseable registry" \
       "the mutant reported a successful registration, but the malformed file's checksum did not change — (k16) would NOT have caught it"
  fi
fi

# (k16d) — the restore check. Neither control above edits the real engine, and this is what
# proves it: the same sha256 before and after, plus no mutant left anywhere in the plugin's own
# scripts directory. Without it, a control that mutated in place could leave every assertion in
# this file testing a file the repository does not contain.
k_eng_after="$(csum "$ENGINE")"
k_residue="$(ls "$script_dir"/setup-ui-*.sh 2>/dev/null || true)"
[ -n "$K_ENGINE_SIG_BEFORE" ] && [ "$K_ENGINE_SIG_BEFORE" = "$k_eng_after" ] && [ -z "$k_residue" ] \
  && ok "(k16d) the real engine is byte-identical after both mutation controls (sha256 unchanged) and no mutant copy was left in the plugin's scripts directory" \
  || no "(k16d) the real engine is byte-identical after both mutation controls and no mutant was left behind" \
       "before='$K_ENGINE_SIG_BEFORE' after='$k_eng_after' residue='$k_residue'"

# --- (k26) THE STATIC ISOLATION GATE — this is what actually enforces AC-1h ------------
# Two rules, and both are needed:
#   A. INSIDE this group, EVERY engine invocation must carry an isolation token. The verb is a
#      loop variable in several cases above, so a literal-verb rule alone would see half of them.
#   B. ANYWHERE in this file, an engine invocation naming a literal registry verb must carry
#      one. This is the rule that binds the groups a later subtask appends.
# An isolation token is a fixture `HOME=`, an explicit `--registry`, or `env -u HOME` (which
# provably cannot reach a home directory because there is not one).
SELF="$script_dir/test-setup-ui.sh"
[ -f "$SELF" ] || setup_fail "(k26) fixture: this file is not readable at $SELF, so the isolation gate has no subject"

reg_isolation_scan() {
  awk -v mode="$2" '
    function isolated(l) { return (l ~ /HOME=/) || (l ~ /--registry/) || (l ~ /env -u HOME/) }
    /^echo "\(k\) AC-registry/ { ink = 1 }
    /^echo "\(z\)/            { ink = 0 }
    {
      if ($0 !~ /bash[[:space:]]+"\$[A-Za-z_][A-Za-z_0-9]*"/) next
      regverb = ($0 ~ /"\$[A-Za-z_][A-Za-z_0-9]*"[[:space:]]+(add|list|forget|scan)([[:space:]]|$)/)
      if (!(ink || regverb)) next
      seen++
      if (mode == "findings" && !isolated($0)) printf "%d: %s\n", FNR, $0
    }
    END { if (mode == "count") print seen+0 }
  ' "$1"
}

k_seen="$(reg_isolation_scan "$SELF" count)"
case "$k_seen" in ''|*[!0-9]*) k_seen=0 ;; esac
[ "$k_seen" -ge 15 ] \
  && ok "(k26a) the isolation gate actually SEES the registry-touching invocations ($k_seen of them) — a gate whose pattern matched nothing would report 'clean' forever" \
  || no "(k26a) the isolation gate sees the registry-touching invocations" "it inspected only $k_seen lines; a pattern that stopped matching would make (k26b) vacuous"

k_viol="$(reg_isolation_scan "$SELF" findings)"
[ -z "$k_viol" ] \
  && ok "(k26b) every registry-touching engine invocation in this file carries a fixture HOME, an explicit --registry, or an unset HOME" \
  || no "(k26b) every registry-touching engine invocation carries an isolation token" \
       "these would run against the developer's real config tree:
$k_viol"

# MUTATION CONTROL for (k26b): strip the fixture HOME from ONE call site and the gate must
# redden. Without this the gate would also "pass" if its rules had quietly stopped applying.
KMUT="$TMPROOT/k-self-mutant.sh"
awk 'BEGIN { done = 0 }
     {
       if (!done && index($0, "HOME=\"$KH\" bash \"$ENGINE\" list") > 0) { sub(/HOME="\$KH" /, ""); done = 1 }
       print
     }' "$SELF" > "$KMUT" 2>/dev/null
if mutant_ok "$SELF" "$KMUT" shell; then
  k_mviol="$(reg_isolation_scan "$KMUT" findings)"
  [ -n "$k_mviol" ] \
    && ok "(k27) MUTATION CONTROL: stripping the fixture HOME from one call site reddens the gate — (k26b) is enforcing the rule, not restating it" \
    || no "(k27) MUTATION CONTROL: a call site with the fixture HOME stripped is flagged" \
         "the gate stayed clean on a mutant that reaches the real config tree"
fi

# --- (k28)/(k29) THE BACKSTOP: the real user-scope tree, hashed around the whole suite ---
# Captured before the first assertion in this file (see real_tree_sig near the top) and compared
# here — after every group that invokes the engine, since (z) below reads documents only. ABSENT
# is a DEFINED value, so CI, which has no user-scope loomwright directory at all, still runs
# this assertion instead of skipping it.
k_real_after="$(real_tree_sig "$REAL_LOOM_HOME")"
if [ "$REAL_LOOM_SIG_BEFORE" = "UNRESOLVED" ]; then
  no "(k28) the real user-scope tree is unchanged across the whole suite" \
     "the engine named no absolute registry path under the real HOME, so this backstop has no subject and is NOT passing"
elif [ "$REAL_LOOM_SIG_BEFORE" = "$k_real_after" ]; then
  ok "(k28) the real user-scope tree is byte-identical across the whole suite (state before: $([ "$REAL_LOOM_SIG_BEFORE" = "ABSENT" ] && echo ABSENT || echo present))"
else
  printf '%s\n' "$REAL_LOOM_SIG_BEFORE" > "$TMPROOT/real-before" 2>/dev/null
  printf '%s\n' "$k_real_after"         > "$TMPROOT/real-after"  2>/dev/null
  no "(k28) the real user-scope tree is unchanged across the whole suite" \
     "$(diff "$TMPROOT/real-before" "$TMPROOT/real-after" 2>/dev/null | head -20)
     (a live 'serve' writing into the real ui dir would also show here; a projects.json line means a case escaped its fixture HOME)"
fi

k_real_reg_after="ABSENT"
[ -f "$REAL_LOOM_HOME/projects.json" ] && k_real_reg_after="$(csum "$REAL_LOOM_HOME/projects.json")"
[ "$REAL_REG_BEFORE" = "$k_real_reg_after" ] \
  && ok "(k29) the real projects.json is unchanged across the whole suite (state before: $([ "$REAL_REG_BEFORE" = "ABSENT" ] && echo ABSENT || echo present)) — the precise subject, immune to anything else writing under that directory" \
  || no "(k29) the real projects.json is unchanged across the whole suite" \
       "before='$REAL_REG_BEFORE' after='$k_real_reg_after' — a registry case reached the developer's real config tree"

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
