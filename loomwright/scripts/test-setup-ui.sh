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
#       relative path `floor.json`, the served index and a per-project URL BUILT from a fixed
#       prefix and an encoded slug rather than taken from a served document. TWO call sites
#       COUNTED IN CODE — the READ helper `fetchText` and the WRITE helper `postAction`, which
#       item 07 added — and no third (see code_occ: a truthful comment naming `fetch(` must not
#       redden a gate that is counting calls). With mutation controls: a copy carrying one
#       remote href must be flagged, a real EXTRA call site must be counted, and a
#       commented-out one must not be, or the scanner proves nothing
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
#   (l) AC-multiproject — one server showing many projects. The SCHEDULING BOUND is a
#       MEASUREMENT, not an inspection: a stub projector of known cost, five registered
#       projects, a fixed number of ticks, and a budget expressed in units of that same stub
#       calibrated in the same run — with a naive mutant that must be OVER it and a null mutant
#       that must be within it. Plus the served index (`index.json`) that the picker reads:
#       every registered project at the exact relative path the page builds, a project deleted
#       under a live serve rendering `unavailable` with its reason while the others keep going
#       and the server survives, an ABSENT registry and an UNPARSEABLE one reported as the two
#       different claims they are, jq unfindable still yielding a valid index that names jq, and
#       write containment hashed rather than argued. Plus the page halves that are checkable
#       headlessly: no write verb, no egress, no second timer, both fetched URLs built in
#       floor.js rather than read out of the served document, and the five committed
#       served-index fixtures a browser pass will load — none of which may pin a key the engine
#       can no longer emit
#   (z) release-surface parity for the /setup ui module registration, plus the surfaces/formats
#       basis sentence, which is QUOTED from build-floor.sh rather than restated
#   (m) AC-entrypoint-parity — the two commands' documented verb sets must UNION to exactly the
#       engine's own dispatch table, parsed out of the pinned `case "$SUBCMD" in` rather than
#       restated here. (Listed late because this list stopped being maintained for a release;
#       (m) and (n) below existed before (o) was written and were missing from it.)
#   (n) AC-guarded-writes — the four mutating endpoints, the four-part guard, and one control
#       per part that disables that part alone and watches the refused request succeed
#   (o) AC-registry-lock — the cross-process lock that lets two writers share one registry. It
#       is a MEASUREMENT, not an inspection: real concurrent invocations, with the race made
#       deterministic by a deliberately slowed `jq` on PATH rather than by editing the engine,
#       so the subject of the primary assertion is the shipped file byte for byte. Both
#       registrations must survive and the pair must take materially longer than one writer;
#       the control changes ONE token so the write path takes no lock, and one write is lost.
#       Plus release proven on a refusal path taken with the lock already held (the EXIT trap
#       is the only release site there), the timeout refusal and its anti-vacuity arm, and all
#       FOUR staleness verdicts — owner exited, pid reused, ownerless-and-old, and the arm that
#       an ownerless-and-FRESH lock is left alone, without which a detector that called every
#       lock stale would pass the other three while destroying the mechanism
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
# code_occ counts occurrences in CODE ONLY, with /* */ and // comments stripped first.
# WHY IT EXISTS, because a comment-aware counter can be WEAKER than a naive one and that is a
# real cost: `occ` counts raw text, so a truthful comment NAMING the construct it describes
# ("there is exactly ONE `fetch(` call site in this file") reddened (a4) while the code still
# held exactly one call. That is the same false-positive class item 05 recorded when a widened
# read-only scanner matched JavaScript's own `delete` OPERATOR - a gate that pressures the next
# author into deleting a correct line to appease it. The resolution there was to scope the gate
# rather than contort the source, and it is the resolution here.
# THE STRIPPER IS DELIBERATELY NAIVE - it knows nothing about string literals - and that is safe
# in THIS bundle for a reason that is itself asserted: (a1) proves no `//`-bearing URL exists in
# any of the three files, so there is no string a `//` scan can truncate. It is used ONLY by the
# counting assertions below, each of which carries both controls: one proving a real second call
# still reddens, one proving a merely-mentioned or commented-out call does not.
code_occ() {
  awk -v pat="$2" '
    BEGIN { inblk = 0; n = 0 }
    {
      line = $0; out = ""
      while (length(line)) {
        if (inblk) {
          i = index(line, "*/")
          if (i == 0) { line = "" } else { line = substr(line, i + 2); inblk = 0 }
        } else {
          i = index(line, "/*"); j = index(line, "//")
          if (i > 0 && (j == 0 || i < j)) { out = out substr(line, 1, i - 1); line = substr(line, i + 2); inblk = 1 }
          else if (j > 0) { out = out substr(line, 1, j - 1); line = "" }
          else { out = out line; line = "" }
        }
      }
      n += gsub(pat, "", out)
    }
    END { print n + 0 }
  ' "$1" 2>/dev/null
}
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
# NOREG — a registry path that deliberately does NOT exist, passed to every `serve` in this
# file. `serve` became a registry-touching verb when it gained the multi-project half: it
# READS the registry and then runs the projector INSIDE every project it finds there, so a
# serve case written in the ordinary style would regenerate the developer's real projects —
# writing `.supervisor/floor/floor.json` into repositories this suite has never heard of. The
# ui-directory override cannot prevent that (the registry is a SIBLING of the ui dir), so the
# isolation gate at (k26) now requires an explicit token on `serve` too, and this is it.
NOREG="$TMPROOT/no-such-registry.json"
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
JS_SIG_BEFORE="$(csum "$JS")"

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

# (a3) The page now reads TWO documents per tick - the served index, then the selected
# project's floor - and it does so through ONE call site, `fetchText(url)`. So the assertion is
# no longer a single literal call: it is the call site's shape PLUS every URL that call site can
# ever be given, each of which is built in floor.js from a fixed relative string. A URL taken
# verbatim from a served document would be the hole this checks for.
a3_bad=""
has_lit "$JS" "fetch(url, { cache: 'no-store' })" || a3_bad="$a3_bad [no single no-store call site]"
has_lit "$JS" "return 'floor.json';" || a3_bad="$a3_bad [the root url is not a relative literal]"
has_lit "$JS" "return 'projects/' + encodeURIComponent(slug) + '/floor.json';" \
  || a3_bad="$a3_bad [the per-project url is not built from a fixed prefix and an encoded slug]"
has_lit "$JS" "var SERVED_INDEX = 'index.json';" || a3_bad="$a3_bad [the served index url is not a relative literal]"
[ -z "$a3_bad" ] \
  && ok "(a3) every URL floor.js fetches is a relative literal built in floor.js (floor.json, index.json, projects/<encoded slug>/floor.json) and the READ call site passes cache: 'no-store'" \
  || no "(a3) every URL floor.js fetches is a relative literal built in floor.js" "$a3_bad"

# (a4) counts CALL SITES IN CODE. See code_occ above for why this is comment-aware and why that
# does not weaken it: the two controls below are what keep it honest.
n_fetch="$(code_occ "$JS" 'fetch[(]')"
n_fetch_raw="$(occ "$JS" 'fetch[(]')"
# RE-BASELINED, NOT LOOSENED. Item 07 gave the page a WRITE helper, so there are now exactly
# TWO call sites in code: `fetchText` (read) and `postAction` (write). The tempting repair —
# relaxing this to `-ge 1` — would destroy the gate, because "at least one" is satisfied by any
# number of smuggled-in third, fourth and fifth requests. The number moved; the SHAPE did not.
N_FETCH_EXPECT=2
[ "$n_fetch" = "$N_FETCH_EXPECT" ] \
  && ok "(a4) floor.js makes exactly $N_FETCH_EXPECT fetch calls in code — the read helper and the write helper, and no third (found $n_fetch; $n_fetch_raw occurrences including the comments that describe them)" \
  || no "(a4) floor.js makes exactly $N_FETCH_EXPECT fetch calls in code" "found $n_fetch"
# ANTI-VACUITY: comment-stripping must actually be doing something here, or (a4) is just `occ`
# under another name and the two controls below would be testing a mechanism nothing uses.
[ "${n_fetch_raw:-0}" -gt "${n_fetch:-0}" ] 2>/dev/null \
  && ok "(a4a) ANTI-VACUITY: the raw count ($n_fetch_raw) exceeds the code count ($n_fetch), so the comment-stripping in (a4) is live rather than decorative" \
  || no "(a4a) ANTI-VACUITY: the comment-stripping in (a4) is live" "raw=$n_fetch_raw code=$n_fetch — if these are equal, (a4) is `occ` under another name"
# CONTROL 1 - a REAL second call site must still redden (a4). This is the property a
# comment-aware counter could have silently lost.
MUT_F2="$TMPROOT/mut-fetch-two.js"
{ cat "$JS"; printf '\nvar sneaky = fetch("floor.json");\n'; } > "$MUT_F2" 2>/dev/null
if mutant_ok "$JS" "$MUT_F2"; then
  m_f2="$(code_occ "$MUT_F2" 'fetch[(]')"
  # The expected value is DERIVED from (a4)'s baseline rather than restated, so re-baselining
  # (a4) can never leave this control asserting a number the shipped file no longer has.
  [ "$m_f2" = "$((N_FETCH_EXPECT + 1))" ] \
    && ok "(a4b) MUTATION CONTROL: a genuine EXTRA fetch call site is counted ($m_f2 = the $N_FETCH_EXPECT baseline plus one) — comment-awareness did not blind the gate" \
    || no "(a4b) MUTATION CONTROL: a genuine extra fetch call site is counted" "code_occ said $m_f2, expected $((N_FETCH_EXPECT + 1))"
fi
# CONTROL 2 - prose must NOT redden it. A commented-out call and a comment naming `fetch(` are
# both legitimate; flagging either is the false positive this fix exists to remove, and the one
# that pressures the next author into deleting a correct comment.
MUT_FC="$TMPROOT/mut-fetch-comment.js"
{ cat "$JS"; printf '\n// var oldWay = fetch("floor.json");\n/* the fetch( above is the only one */\n'; } > "$MUT_FC" 2>/dev/null
if mutant_ok "$JS" "$MUT_FC"; then
  m_fc="$(code_occ "$MUT_FC" 'fetch[(]')"
  m_fc_raw="$(occ "$MUT_FC" 'fetch[(]')"
  [ "$m_fc" = "$N_FETCH_EXPECT" ] && [ "${m_fc_raw:-0}" -ge 3 ] 2>/dev/null \
    && ok "(a4c) MUTATION CONTROL: a commented-out call and a comment MENTIONING fetch( leave the code count at $m_fc (raw count $m_fc_raw) — the gate reads code, not prose" \
    || no "(a4c) MUTATION CONTROL: commented-out and mentioned fetch( calls do not redden (a4)" "code=$m_fc (want $N_FETCH_EXPECT) raw=$m_fc_raw (want >=3)"
fi
# The mutation controls above must not have touched the shipped file.
[ "$(csum "$JS")" = "$JS_SIG_BEFORE" ] \
  && ok "(a4d) floor.js is byte-identical after both (a4) mutation controls (sha256 unchanged)" \
  || no "(a4d) floor.js is byte-identical after the (a4) mutation controls" "before='$JS_SIG_BEFORE' after='$(csum "$JS")'"

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

# --- (c13)-(c17) THE LANES VIEW RENDERS THE READ-ONLY WORDS, NOT THE DOT SHAPE ALONE ------
# floor.css's own header states the page-wide rule as "read-only agent -> hollow dot + the text
# 'read-only'", and (c9)/(c10) each checked one half of it in the wrong place: (c9) that the
# hollow-dot RULE exists in the stylesheet, (c10) that the string 'read-only unknown' exists
# SOMEWHERE in floor.js. Both passed while the Lanes view — the one view that shows a run —
# applied the hollow class and rendered no words at all, so a read-only lane was distinguishable
# by SHAPE alone. Neither assertion could have caught that, because neither is scoped to a VIEW.
# This one is: the whole predicate is evaluated over renderLanes's own body, which is also what
# lets the two controls below point the SAME rule at a mutant rather than hold a second copy of
# it — the drift (j14) recorded when a re-inlined copy of a shared scanner went quietly vacuous.
lane_ro_faults() { # <file> -> the halves of the read-only cue this file's LANES view is missing
  local body bad=""
  body="$(awk '/^  function renderLanes/{f=1} f{print} f&&/^  }$/{exit}' "$1" 2>/dev/null)"
  [ -n "$body" ] || { printf '%s' "[renderLanes was not found in $(basename "$1") — every claim below would be vacuous]"; return 0; }
  in_str "$body" "classList.add('hollow')" || bad="$bad [no hollow dot]"
  in_str "$body" "row.read_only === true) ? 'read-only'" || bad="$bad [a read-only agent's lane carries no 'read-only' text — the dot shape is the only cue]"
  in_str "$body" "row.read_only === false) ? ''" || bad="$bad [a WRITING agent's lane is not left silent, so the cue would appear on every lane and distinguish nothing]"
  in_str "$body" "'read-only unknown'" || bad="$bad [an absent read_only is not reported as unknown, so it reads as 'not read-only']"
  in_str "$body" "fmtAge(age) + roSuffix" || bad="$bad [the text never reaches a STALLED lane's meta line]"
  in_str "$body" "fmtAge(age)) + roSuffix" || bad="$bad [the text never reaches a non-stalled lane's meta line]"
  printf '%s' "${bad# }"
}
C_RO_MUTANTS=0
c_ro_faults="$(lane_ro_faults "$JS")"
[ -z "$c_ro_faults" ] \
  && ok "(c13) the Lanes view renders BOTH halves of the read-only cue — the hollow dot AND renderRoster's own words, on the same tri-state and the same condition as the dot, reaching the meta line of a stalled lane and a non-stalled one alike" \
  || no "(c13) the Lanes view renders both halves of the read-only cue" "$c_ro_faults"

# CONTROL 1 — the exact defect this fixes: the class is applied, the words are not rendered.
MUT_LRO1="$TMPROOT/mut-lane-readonly-silent.js"
sed 's/ + roSuffix;/;/g' "$JS" > "$MUT_LRO1" 2>/dev/null
if mutant_ok "$JS" "$MUT_LRO1"; then
  C_RO_MUTANTS=$((C_RO_MUTANTS + 1))
  m_lro1="$(lane_ro_faults "$MUT_LRO1")"
  if in_str "$m_lro1" "STALLED lane's meta line" && in_str "$m_lro1" "non-stalled lane's meta line"; then
    ok "(c14) MUTATION CONTROL: a Lanes view that computes the read-only words and never renders them IS flagged, on BOTH the stalled and the non-stalled branch — which is precisely the state this view shipped in"
  else
    no "(c14) MUTATION CONTROL: words computed but never rendered IS flagged" "lane_ro_faults said: ${m_lro1:-<clean, so (c13) would pass a view that renders nothing>}"
  fi
fi

# CONTROL 2 — the tri-state's third arm collapsed to silence. An agent whose roster row omits
# read_only, or that has no roster row at all, would then be rendered exactly like one that is
# known to write: measured-absence presented as a measured negative, which is the failure
# renderRoster's own comment names and (c10) exists for.
MUT_LRO2="$TMPROOT/mut-lane-readonly-unknown.js"
sed "s/          : 'read-only unknown';/          : '';/" "$JS" > "$MUT_LRO2" 2>/dev/null
if mutant_ok "$JS" "$MUT_LRO2"; then
  C_RO_MUTANTS=$((C_RO_MUTANTS + 1))
  m_lro2="$(lane_ro_faults "$MUT_LRO2")"
  if in_str "$m_lro2" "absent read_only is not reported as unknown"; then
    ok "(c15) MUTATION CONTROL: a Lanes view that renders an ABSENT read_only as silence — indistinguishable from a known writer — IS flagged"
  else
    no "(c15) MUTATION CONTROL: an absent read_only rendered as silence IS flagged" "lane_ro_faults said: ${m_lro2:-<clean>}"
  fi
fi

# ANTI-VACUITY: both controls must have EXECUTED. Each lives inside an `if mutant_ok`, and a
# mutant whose sed anchor no longer matches the file produces an identical copy — mutant_ok
# reddens on that, but the control it guards is then simply not run, which is the silent-skip
# shape this suite has been bitten by before. The count is the proof that neither was skipped.
[ "$C_RO_MUTANTS" = "2" ] \
  && ok "(c16) ANTI-VACUITY: both (c13) mutation controls EXECUTED — neither (c14) nor (c15) was skipped inside its if" \
  || no "(c16) ANTI-VACUITY: both (c13) mutation controls executed" "$C_RO_MUTANTS of 2 ran — a control that did not run proves nothing about (c13)"
[ "$(csum "$JS")" = "$JS_SIG_BEFORE" ] \
  && ok "(c17) floor.js is byte-identical after the (c13) mutation controls (sha256 unchanged)" \
  || no "(c17) floor.js is byte-identical after the (c13) mutation controls" "before='$JS_SIG_BEFORE' after='$(csum "$JS")'"

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
out="$(PATH="$STUB_NOPY" bash "$ENGINE" serve --registry "$NOREG" --ui-dir "$GUI" --no-regen 2>&1)"; rc=$?
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
out="$(PATH="$STUB_NOJQ" bash "$ENGINE" serve --registry "$NOREG" --ui-dir "$JQUI" --port "$jq_port" --detach 2>&1)"; rc=$?
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
out="$(bash "$LONE/setup-ui.sh" serve --registry "$NOREG" --ui-dir "$LUI" 2>&1)"; rc=$?
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
out="$(bash "$ENGINE" serve --registry "$NOREG" --ui-dir "$HINTUI" --no-regen --detach --port "$hint_port" --interval 10 2>&1)"; rc=$?
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
out="$(bash "$ENGINE" serve --registry "$NOREG" --ui-dir "$HINTUI" --no-regen --detach --port "$hint_port2" 2>&1)"; rc=$?
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
      out="$(bash "$ENGINE" serve --registry "$NOREG" --ui-dir "$GUI" --no-regen --port "$busy_port" 2>&1)"; rc=$?
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
          out="$(bash "$ENGINE" serve --registry "$NOREG" --ui-dir "$GUI" --no-regen --detach --port "$free_port" 2>&1)"; rc=$?
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

# CODE ONLY, AND RE-EXPRESSED AGAINST THE NEW ENGINE — not deleted, and not loosened.
# (h1) used to require exactly one non-comment `python3 -m http.server ... --bind 127.0.0.1`.
# Item 07 replaced that static server with a routed stdlib handler, which took BOTH counts to
# zero and would have reddened this assertion; the tempting repairs were to delete it or to
# accept "at least one bind". The SHAPE is what matters and the shape is kept: exactly ONE
# non-comment construction of the server, and that one construction binds the loopback address.
# The subject moved from an invocation to a constructor expression; the claim did not.
# Excluding `^\s*#` is still what makes this an assertion about the code: the engine's header
# now carries the words `python3 -m http.server` in PROSE (explaining what was replaced and
# why), and it names the bind in prose too. A comment that claims the bind is not the bind.
# RE-EXPRESSED A SECOND TIME, and again the SHAPE is what is kept. The traceback fix subclasses
# `ThreadingHTTPServer` as `FloorServer` (so that `handle_error` can be overridden for the whole
# server rather than patched at two known raises), which moved the construction off the base
# class name — taking the old count to ZERO, not to two. The tempting repairs were the same two
# as last time: delete the assertion, or accept `>= 1`. Instead the pattern matches a
# CONSTRUCTION of either name — `Name((` , the double paren of `(server_address, handler)` —
# which the `class FloorServer(ThreadingHTTPServer):` definition line does NOT match (one paren)
# and the import line does not match either. So it still resolves to exactly one line, and that
# line still has to carry the loopback literal. `n_srvdef` keeps the two names tied together:
# the thing constructed must actually BE the threading HTTP server, or an author could satisfy
# this gate with a `FloorServer` that subclasses something else entirely.
BIND_EXPR='(ThreadingHTTPServer|FloorServer)[(][(]'
binds="$(awk -v pat="$BIND_EXPR" '$0 !~ /^[[:space:]]*#/ && $0 ~ pat { t++; if ($0 ~ /"127\.0\.0\.1"/) b++ } END { print (t+0) " " (b+0) }' "$ENGINE")"
n_bind="${binds%% *}"; n_loop="${binds##* }"
n_srvdef="$(awk '$0 !~ /^[[:space:]]*#/ && /^class FloorServer\(ThreadingHTTPServer\):$/ {n++} END{print n+0}' "$ENGINE")"
[ "$n_bind" = "1" ] 2>/dev/null && [ "$n_loop" = "1" ] && [ "$n_srvdef" = "1" ] \
  && ok "(h1) setup-ui.sh constructs exactly ONE non-comment HTTP server, it binds 127.0.0.1, and the class it constructs is the ONE subclass of ThreadingHTTPServer (constructions=$n_bind bound=$n_loop subclass-definitions=$n_srvdef)" \
  || no "(h1) setup-ui.sh constructs exactly ONE non-comment HTTP server carrying the 127.0.0.1 bind" "constructions=$n_bind bound=$n_loop subclass-definitions=$n_srvdef"
# MUTATION CONTROL, RE-AUTHORED SO IT ACTUALLY RUNS. The old mutant sed-replaced the literal
# `python3 -m http.server --bind 127.0.0.1`; the moment that literal left the engine the sed
# became a NO-OP, `mutant_ok` saw an unchanged file, and this control would have been SKIPPED
# INSIDE ITS `if` — neither red nor green — leaving (h1) with nothing proving it can fail.
# The mutant below rebinds the real constructor to a wildcard address, so it genuinely differs
# from the shipped engine; `mutant_ok` returning true is therefore part of what (h3b) asserts.
MUT_BIND="$TMPROOT/mut-bind.sh"
sed 's/FloorServer(("127\.0\.0\.1", PORT)/FloorServer(("0.0.0.0", PORT)/' "$ENGINE" > "$MUT_BIND" 2>/dev/null
h2_ran=0
if mutant_ok "$ENGINE" "$MUT_BIND" shell; then
  h2_ran=1
  mb="$(awk -v pat="$BIND_EXPR" '$0 !~ /^[[:space:]]*#/ && $0 ~ pat { t++; if ($0 ~ /"127\.0\.0\.1"/) b++ } END { print (t+0) " " (b+0) }' "$MUT_BIND")"
  [ "${mb%% *}" = "1" ] && [ "${mb##* }" = "0" ] \
    && ok "(h2) MUTATION CONTROL: a construction with the loopback bind replaced by a wildcard IS caught (constructions=${mb%% *} bound=${mb##* })" \
    || no "(h2) MUTATION CONTROL: a construction with the loopback bind replaced IS caught" "got constructions=${mb%% *} bound=${mb##* }"
fi
# (h2) IS AN `if`, AND A SKIPPED `if` IS NOT A PASS. This is the assertion that makes the
# silent-vacuity failure mode visible: if the mutant were ever to stop differing from the
# engine — the exact way the previous (h2) died — this goes RED instead of disappearing.
[ "$h2_ran" = "1" ] \
  && ok "(h3b) ANTI-VACUITY: (h2)'s mutant passed mutant_ok, so the control above actually EXECUTED rather than being skipped inside its if" \
  || no "(h3b) ANTI-VACUITY: (h2)'s mutation control actually executed" "mutant_ok rejected $MUT_BIND — the sed no longer matches the engine, so (h2) was SKIPPED and (h1) is uncontrolled"

out="$(bash "$ENGINE" serve --registry "$NOREG" --no-regen --detach --port "$port" --ui-dir "$HUI" 2>&1)"; rc=$?
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
  bash "$ENGINE" serve --registry "$NOREG" --detach --interval 1 --port "$rport" --ui-dir "$RUI" >/dev/null 2>&1
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
# THE RULE LIVES IN EXACTLY ONE PLACE. It used to live in two: this function, and a verbatim
# re-inlined copy inside (j14)'s mutation control. That was harmless only while the expected
# answer was "no matches anywhere" — the moment the shared rule was re-baselined (which item 07
# forced, because the page gained a write helper), the control would have kept grepping with the
# OLD rule, its mutant would still have matched, and (j14) would have stayed GREEN while
# controlling nothing. One copy; every caller reaches it through no_write_verbs.
NO_WRITE_VERB_RE="(method[[:space:]]*[:=][[:space:]]*['\"]?(post|put|delete)|['\"](post|put|delete)['\"])"
# no_write_verbs [file ...] — PARAMETERISED over a file list, defaulting to the three bundle
# files. The parameter is what lets (j14) point the SHARED scanner at a mutant instead of
# holding its own copy of the rule.
no_write_verbs() {
  local f
  if [ $# -eq 0 ]; then set -- "$HTML" "$CSS" "$JS"; fi
  for f in "$@"; do
    # Matches the METHOD POSITION, case-insensitively, rather than bare verb tokens. Both halves
    # of that are load-bearing and each was arrived at by measurement, not taste:
    #   * case-insensitive, because the Fetch spec NORMALIZES a lowercase known method, so
    #     `fetch(u, {method: 'post'})` performs a real POST. An uppercase-only scanner reads like
    #     a read-only guarantee while letting the lowercase spelling straight through.
    #   * position-scoped, because a bare case-insensitive \bDELETE\b matches JavaScript's own
    #     `delete` OPERATOR - `delete laneEls[k];` in floor.js is legitimate object-property
    #     removal, and flagging it would be a false positive that pressures a future author into
    #     deleting a correct line to appease the gate.
    # Verified against four inputs: the pre-07 bundle 0, `method: 'post'` 1, `method: 'PUT'` 1,
    # and the bare `delete` operator 0.
    grep -inE "$NO_WRITE_VERB_RE" "$f" 2>/dev/null | sed "s|^|$(basename "$f"): |"
  done
}

# THE EXACT, ENUMERATED BASELINE — re-baselined for item 07's write path, never widened.
# The page can now write, so `method: 'POST'` is legitimately in floor.js and this scanner
# necessarily matches it. Both tempting repairs destroy the gate: relaxing the PATTERN would
# stop it seeing a real smuggled verb, and relaxing the ASSERTION to "no worse than before"
# would let any number of further ones through. What is asserted instead is a count PER FILE.
# index.html and floor.css stay at ZERO — the markup and the styles have no business carrying a
# write verb at all, and a <form method="post"> is a cross-origin write primitive that needs no
# script and cannot carry the custom header the guard requires, so zero there is load-bearing.
NWV_HTML_EXPECT=0
NWV_CSS_EXPECT=0
NWV_JS_EXPECT=1
# ...and floor.js's ONE permitted occurrence is NAMED, not merely counted, so a different single
# occurrence cannot quietly take the write helper's place.
NWV_JS_ALLOWED="method: 'POST'"
nwv_count() { no_write_verbs "$1" | awk 'END{print NR+0}'; }
# no_write_verbs_baseline -> empty when the bundle matches the baseline exactly, else the
# deviation. BOTH assertion sites call THIS. That is the point: (j13) and (l19) run the same
# scanner against the same expectation 1,400 lines apart, so they cannot drift apart, and a
# fix applied to one is applied to both by construction rather than by discipline.
no_write_verbs_baseline() {
  local n_html n_css n_js bad="" js_hits
  n_html="$(nwv_count "$HTML")"; n_css="$(nwv_count "$CSS")"; n_js="$(nwv_count "$JS")"
  [ "$n_html" = "$NWV_HTML_EXPECT" ] || bad="$bad [index.html: $n_html write-verb occurrence(s), expected exactly $NWV_HTML_EXPECT]"
  [ "$n_css"  = "$NWV_CSS_EXPECT"  ] || bad="$bad [floor.css: $n_css write-verb occurrence(s), expected exactly $NWV_CSS_EXPECT]"
  [ "$n_js"   = "$NWV_JS_EXPECT"   ] || bad="$bad [floor.js: $n_js write-verb occurrence(s), expected exactly $NWV_JS_EXPECT]"
  js_hits="$(no_write_verbs "$JS")"
  case "$js_hits" in
    *"$NWV_JS_ALLOWED"*) ;;
    *) bad="$bad [floor.js's permitted occurrence is not the write helper's \`$NWV_JS_ALLOWED\`: ${js_hits:-<nothing found>}]" ;;
  esac
  printf '%s' "${bad# }"
}

write_findings="$(no_write_verbs_baseline)"
[ -z "$write_findings" ] \
  && ok "(j13) no_write_verbs: index.html and floor.css carry no POST/PUT/DELETE token at all, and floor.js carries exactly $NWV_JS_EXPECT — the write helper's own \`$NWV_JS_ALLOWED\` and nothing else" \
  || no "(j13) no_write_verbs: the bundle matches the exact write-verb baseline" "$write_findings"
# Mutation control: a write verb appearing BEYOND the baseline must be caught.
MUT_WRITE="$TMPROOT/mut-write.js"
# The mutant uses the LOWERCASE spelling on purpose: an uppercase one passes against an
# uppercase-only scanner too, so it could not prove the case-insensitive widening.
{ cat "$JS"; printf "\n// fetch('floor.json', { method: 'post' })\n"; } > "$MUT_WRITE" 2>/dev/null
if mutant_ok "$JS" "$MUT_WRITE"; then
  # CALLS THE SHARED SCANNER against the mutant — it does NOT re-inline the rule. And the
  # expected value is DERIVED from the baseline, so re-baselining moves this control with it.
  m_write="$(nwv_count "$MUT_WRITE")"
  [ "$m_write" = "$((NWV_JS_EXPECT + 1))" ] \
    && ok "(j14) MUTATION CONTROL: a LOWERCASE post token added BEYOND the baseline takes the shared scanner's count to $m_write (baseline $NWV_JS_EXPECT + 1) — the control calls no_write_verbs rather than holding a private copy of its regex, so a re-baselined rule cannot leave it green and controlling nothing" \
    || no "(j14) MUTATION CONTROL: an added lowercase post token is flagged by the SHARED no_write_verbs" "the shared scanner counted $m_write in the mutant, expected $((NWV_JS_EXPECT + 1))"
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
#      one. This is the rule that binds the groups a later subtask appends. `serve` is on that
#      list and was ADDED to it by the multi-project change: it reads the registry and then runs
#      the projector inside every project it finds, so an unisolated `serve` does not merely
#      read the developer's config tree, it writes into every repository named in it.
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
      regverb = ($0 ~ /"\$[A-Za-z_][A-Za-z_0-9]*"[[:space:]]+(add|list|forget|scan|serve)([[:space:]]|$)/)
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

# MUTATION CONTROL for the SERVE half of rule B, which (k27) above does not cover: it strips a
# fixture HOME from a `list`, and would still pass if `serve` had never been added to the rule.
# `serve` is the invocation with the largest blast radius in this file — it writes into every
# registered project — so the rule that isolates it gets its own control.
KMUT2="$TMPROOT/k-self-mutant-serve.sh"
awk 'BEGIN { done = 0 }
     {
       if (!done && index($0, "bash \"$ENGINE\" serve --registry \"$NOREG\"") > 0) { sub(/--registry "\$NOREG" /, ""); done = 1 }
       print
     }' "$SELF" > "$KMUT2" 2>/dev/null
if mutant_ok "$SELF" "$KMUT2" shell; then
  k_mviol2="$(reg_isolation_scan "$KMUT2" findings)"
  [ -n "$k_mviol2" ] \
    && ok "(k27b) MUTATION CONTROL: stripping the registry override from one SERVE call site reddens the gate — serve really is covered by rule B, not merely mentioned in its comment" \
    || no "(k27b) MUTATION CONTROL: a serve call site with its registry override stripped is flagged" \
         "the gate stayed clean on a serve that would regenerate every project in the developer's real registry"
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


# (k30)/(k31) — write CONTAINMENT against a hostile slug. Added at Phase 4.5 after the
# integrated reviewer DEMONSTRATED (not inferred) that a hand-edited registry slug of
# "../../ESCAPED" walked regen_project's `mkdir -p "$UI_DIR/projects/$slug"` clean out of the
# ui directory. `add`/`scan` can never generate such a slug — project_slug folds [^a-z0-9] to
# `-` — which is exactly why the (i) write-containment group could not see it: every slug it
# uses is well formed. The engine designs for hand-edited registries explicitly, and the PAGE
# already defended against this input while the WRITER did not; that asymmetry was the defect.
#
# (k31) IS THE ANTI-VACUITY ARM AND IT IS NOT OPTIONAL. A guard that rejected every slug would
# satisfy (k30) perfectly while destroying the feature, so a well-formed slug must still
# produce its slot IN THE SAME RUN, from the same registry, or (k30) proves nothing worth
# having. Both arms share one serve so neither can pass under conditions the other did not face.
k_hs_root="$TMPROOT/hostile-slug"; mkdir -p "$k_hs_root/home" "$k_hs_root/elsewhere"
k_hs_ui="$k_hs_root/uidir"; k_hs_reg="$k_hs_root/reg.json"
HOME="$k_hs_root/fakehome" bash "$ENGINE" apply --ui-dir "$k_hs_ui" >/dev/null 2>&1
printf '{"projects":[{"slug":"../../ESCAPED","path":"%s"},{"slug":"goodslug","path":"%s"}]}\n' \
  "$k_hs_root/home" "$k_hs_root/home" > "$k_hs_reg"
k_hs_port="$(python3 -c 'import socket
s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null)"
case "$k_hs_port" in ''|*[!0-9]*) setup_fail "(k30) fixture: could not obtain a free port for the hostile-slug serve probe" ;; esac
( cd "$k_hs_root/elsewhere" && HOME="$k_hs_root/fakehome" bash "$ENGINE" serve \
    --ui-dir "$k_hs_ui" --registry "$k_hs_reg" --port "$k_hs_port" --interval 1 --detach >/dev/null 2>&1 )
# THE WINDOW MUST OUTLAST A FULL ROUND-ROBIN, NOT JUST THE FIRST HIT. Non-selected projects
# regenerate ONE AT A TIME on the slow cadence, so stopping the moment goodslug appears leaves
# whichever entry is scheduled later without a turn. With the hostile entry listed first that
# happens to be harmless; REORDER THE FIXTURE AND (k30) GOES GREEN ON A BROKEN ENGINE, because
# the traversal write would have landed on the NEXT background tick and the server is already
# stopped. That is the same under-powered-negative trap that made the original reproduction of
# this very defect fail twice, and leaving it here would bake it into a permanent gate. So:
# wait for goodslug, THEN keep serving for a full slow cycle across every entry, so each one
# provably gets its turn regardless of registry order.
k_hs_waited=0
while [ "$k_hs_waited" -lt 30 ]; do
  [ -d "$k_hs_ui/projects/goodslug" ] && break
  sleep 1; k_hs_waited=$((k_hs_waited+1))
done
# SLOW_FACTOR ticks per entry, 2 entries, 1s interval, plus margin — order-independent.
k_hs_extra=0
while [ "$k_hs_extra" -lt 14 ]; do sleep 1; k_hs_extra=$((k_hs_extra+1)); done
HOME="$k_hs_root/fakehome" bash "$ENGINE" stop --ui-dir "$k_hs_ui" >/dev/null 2>&1

if [ ! -e "$k_hs_root/ESCAPED" ] && [ -z "$(find "$k_hs_root" -path "$k_hs_ui" -prune -o -type d -name 'ESCAPED*' -print 2>/dev/null)" ]; then
  ok "(k30) a hand-edited registry slug of '../../ESCAPED' writes NOTHING outside the ui directory — reg_rows shape-filters it out and regen_project refuses it a second time"
else
  no "(k30) a traversal slug writes nothing outside the ui directory" \
     "found an ESCAPED path under $k_hs_root — the slug reached a filesystem write"
fi

if [ -d "$k_hs_ui/projects/goodslug" ]; then
  ok "(k31) ANTI-VACUITY: a well-formed slug in that SAME registry still gets its slot — (k30) is containment, not a guard that rejects everything"
else
  no "(k31) ANTI-VACUITY: a well-formed slug still gets its slot" \
     "goodslug produced no slot after ${k_hs_waited}s, so (k30) would pass even with the feature broken"
fi


# (k32) — the SELECTED project's slug takes a DIFFERENT path into the engine than every other
# project's: selected_slug_for() reads the registry directly, while reg_rows() feeds the rest.
# (k30)/(k31) poison an "other" project and therefore cannot see this path at all. The CI
# reviewer found the consequence: a function-wide `return` in regen_project's slug guard also
# skipped the root_too copy, which has NOTHING to do with the slug — so one hand-edited entry
# matching the serve directory silently stopped "$UI_DIR/floor.json" updating on EVERY tick.
# Fail-safe, but a silent availability regression against pre-registry behaviour, and the root
# copy is exactly what a page with no served index falls back to. This case pins the root copy
# keeping up while the slot is refused.
k_sel_root="$TMPROOT/poisoned-selected"; mkdir -p "$k_sel_root/home"
k_sel_ui="$k_sel_root/uidir"; k_sel_reg="$k_sel_root/reg.json"
HOME="$k_sel_root/fakehome" bash "$ENGINE" apply --ui-dir "$k_sel_ui" >/dev/null 2>&1
# The poisoned entry's path IS the directory serve runs in, so it becomes the SELECTED project.
# THE PATH MUST BE THE PHYSICAL ONE. selected_slug_for() matches `.path == $SERVE_CWD`, and
# SERVE_CWD is resolved (`pwd -P`), so on a host where the fixture root sits under a symlinked
# /tmp a logical path NEVER matches — SELECTED_SLUG comes back empty, the slug guard is never
# reached, and this case passes for the wrong reason. Observed exactly that on macOS while
# proving this assertion red: it stayed green with the bug reinstated because it was measuring
# nothing. Resolve it here so the entry genuinely becomes the SELECTED project.
k_sel_home_phys="$(cd "$k_sel_root/home" && pwd -P)"
printf '{"projects":[{"slug":"BAD..slug","path":"%s"}]}\n' "$k_sel_home_phys" > "$k_sel_reg"
k_sel_port="$(python3 -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()' 2>/dev/null)"
case "$k_sel_port" in ''|*[!0-9]*) setup_fail "(k32) fixture: could not obtain a free port" ;; esac
( cd "$k_sel_root/home" && HOME="$k_sel_root/fakehome" bash "$ENGINE" serve \
    --ui-dir "$k_sel_ui" --registry "$k_sel_reg" --port "$k_sel_port" --interval 1 --detach >/dev/null 2>&1 )
k_sel_waited=0
while [ "$k_sel_waited" -lt 20 ]; do
  [ -f "$k_sel_ui/floor.json" ] && break
  sleep 1; k_sel_waited=$((k_sel_waited+1))
done
HOME="$k_sel_root/fakehome" bash "$ENGINE" stop --ui-dir "$k_sel_ui" >/dev/null 2>&1

if [ -f "$k_sel_ui/floor.json" ]; then
  ok "(k32) a malformed slug on the SELECTED project refuses only its own slot — the root floor.json still updates, so one hand-edited entry cannot silently stop the whole page refreshing"
else
  no "(k32) a malformed slug on the selected project still lets the root floor.json update" \
     "no $k_sel_ui/floor.json after ${k_sel_waited}s — the slug guard skipped the root copy too"
fi

if [ ! -d "$k_sel_ui/projects/BAD..slug" ] && [ -z "$(find "$k_sel_root" -path "$k_sel_ui" -prune -o -name 'BAD*' -print 2>/dev/null)" ]; then
  ok "(k32b) and its slot is still refused — the root copy proceeding is not the guard failing open"
else
  no "(k32b) the malformed selected slug is still refused a slot" "a BAD..slug path exists"
fi

# ===========================================================================
echo "(l) AC-multiproject — one server, many projects, and a loop whose cost is measured"
# ===========================================================================
# WHAT THIS GROUP PROVES AND WHAT IT DELIBERATELY CANNOT.
#
# AC-2b is a TIMING claim and it is asserted by MEASUREMENT, never by reading the loop: at the
# measured ~1 s per real projector run, regenerating every registered project on every tick
# falls behind a 2 s interval at TWO projects, and every project then renders permanently
# stale. Item 05 shipped a 4.1x runtime regression that passed 338 assertions and seven repo
# gates in silence, which is exactly why inspection is not accepted here.
#
# The measurement follows test-build-floor.sh case (x) and rejects the same two shapes it did:
#   1. Timing the REAL projector. Too slow to run three arms of, and machine-dependent.
#   2. An ABSOLUTE wall-clock ceiling. This repo has rejected that twice: a bound tight enough
#      to catch a regression on a laptop flakes on CI, and one loose enough for CI catches
#      nothing. Unusable in both directions.
# So the bound is a RATIO against a UNIT calibrated in the SAME RUN on the SAME machine: one
# invocation of a STUB projector whose cost is known because it sleeps for it. The bound is
#   budget = (measured tick period - the configured interval) / unit
# i.e. "how many projector runs of work does one tick cost", which is hardware-independent by
# construction - a slow or loaded runner slows the unit and the loop together.
#
# THREE ARMS, because a bound with no control is a bound that has never been red:
#   (l6)  PRIMARY  - the shipped engine, five projects, must be WITHIN budget.
#   (l8)  CONTROL  - a mutant whose loop regenerates EVERY project EVERY tick (the naive shape
#                    R2 names) must be OVER it. This is the arm that proves the measurement can
#                    detect the starvation it claims to.
#   (l9)  NULL-MUTATION CONTROL - a mutant that differs, still parses, and changes nothing the
#                    loop does must stay WITHIN budget. Without it, (l8) would also "pass"
#                    against a measurement that simply flagged any mutant at all.
# Measured on the maintainer tree at STUB_COST=0.4 s, interval 1 s, 5 projects, 6 ticks: the
# shipped engine and the null mutant both sit at 137 hundredths (1.37 projector runs of work
# per tick - the selected project every tick, one other every fifth, plus the index write); the
# naive mutant sits at 412. The budget below sits between them with margin on both sides.
# Wall-clock figures are NOISY, so quoting one exact pair as though it were repeatable would
# claim a precision this measurement does not have; the property that matters is the gap.

L="$(mktmp)" || setup_fail "(l) fixture: mktemp under $TMPROOT failed"
LSCHED_BUDGET=250          # hundredths of one projector run of work per tick; see above
LSTUB_COST="0.4"
LTICKS=6
LINTERVAL=1
LREG="$L/registry.json"
LENG_SIG_BEFORE="$(csum "$ENGINE")"
LJS_SIG_BEFORE="$(csum "$JS")"

# --- (l1) PRESERVATION: subtask 1 is still standing after this subtask's edits ----------
# Sequential sharing grants VISIBILITY, not PRESERVATION: the deterministic outputs gate checked
# subtask 1's symbols at ITS completion and nothing re-checks them after a later subtask edits
# the same file. This is that re-check, and it is an assertion rather than authoring discipline.
l_missing=""
for fn in do_add do_list do_forget do_scan registry_path registry_read project_slug; do
  [ "$(grep -c "^$fn()" "$ENGINE")" -ge 1 ] || l_missing="$l_missing $fn"
done
# The sibling relationship is MEASURED from the engine's own report rather than matched against
# the literal path, for two reasons: a literal would be a second copy of a path that can move,
# and spelling a host-tool directory here would put a vendor token in a file that carries none
# and move a ratchet this subtask has no business moving. Under a fixture HOME with no --ui-dir,
# the reported ui dir and the reported registry must live in the SAME parent — which is the
# property `remove` depends on and the reason the registry survives it.
LSIB_H="$L/home-sibling"
mkdir -p "$LSIB_H" || setup_fail "(l1) fixture: could not create $LSIB_H"
l_sib_out="$(HOME="$LSIB_H" bash "$ENGINE" check 2>/dev/null)"
l_sib_ui="$(printf '%s\n' "$l_sib_out" | sed -n 's/^ui dir:  *//p' | awk 'NR==1')"
l_sib_reg="$(printf '%s\n' "$l_sib_out" | sed -n 's/^registry: //p' | awk 'NR==1')"
case "$l_sib_ui/$l_sib_reg" in
  /*) [ "$(dirname "$l_sib_ui")" = "$(dirname "$l_sib_reg")" ] || l_missing="$l_missing registry-is-no-longer-a-sibling-of-the-ui-dir" ;;
  *)  l_missing="$l_missing could-not-read-the-engine's-own-paths" ;;
esac
[ -z "$l_missing" ] \
  && ok "(l1) PRESERVATION: every symbol subtask 1 provided still resolves in the engine, and the registry the engine names is still a SIBLING of the ui dir it names ($(dirname "$l_sib_reg"))" \
  || no "(l1) PRESERVATION: subtask 1's symbols still resolve and the registry is still a sibling of the ui dir" "missing:$l_missing"

# --- (l2) the symbols THIS subtask provides, in the engine and in the page ---------------
l_missing=""
for fn in regen_project write_served_index; do
  [ "$(grep -c "^$fn()" "$ENGINE")" -ge 1 ] || l_missing="$l_missing $fn"
done
for fn in renderProjectPicker projectStateLabel; do
  [ "$(grep -c "function $fn" "$JS")" -ge 1 ] || l_missing="$l_missing $fn"
done
has_lit "$HTML" 'id="project-picker"' || l_missing="$l_missing project-picker"
[ -z "$l_missing" ] \
  && ok "(l2) regen_project and write_served_index exist in the engine, renderProjectPicker and projectStateLabel in floor.js, and index.html carries the project-picker element" \
  || no "(l2) the multi-project symbols exist in the engine, the page and the markup" "missing:$l_missing"

# --- the timing fixture: a plugin directory holding a COPY of the real engine beside a stub --
# The engine resolves build-floor.sh as its own sibling, so a stub projector is installed by
# giving the engine a different directory to live in - never by editing the engine, which is
# what keeps (l6) a measurement of the SHIPPED code. (l3) asserts that copy is byte-identical.
LP="$L/plugin"
mkdir -p "$LP/floor-ui" || setup_fail "(l) fixture: could not create $LP"
cp "$ENGINE" "$LP/setup-ui.sh" || setup_fail "(l) fixture: could not copy the engine"
cp "$BUNDLE_DIR"/* "$LP/floor-ui/" 2>/dev/null || setup_fail "(l) fixture: could not copy the bundle"
cat > "$LP/build-floor.sh" <<'__STUB__'
#!/usr/bin/env bash
# STUB PROJECTOR with a KNOWN cost. It writes the artefact the engine copies, then sleeps for
# STUB_COST and records the finishing time and the directory it ran in. The sleep and the
# timestamp come from ONE python3 process, so the recorded cost includes the startup the
# harness will later calibrate against.
mkdir -p .supervisor/floor 2>/dev/null
printf '{"schema_version":1,"generated_at_epoch":0,"repo_head":"stub","surfaces":{},"notes":[]}\n' \
  > .supervisor/floor/floor.json 2>/dev/null
python3 -c 'import time,os
time.sleep(float(os.environ.get("STUB_COST","0.4")))
f = open(os.environ["STUB_LOG"], "a"); f.write("%.4f %s\n" % (time.time(), os.getcwd())); f.close()' 2>/dev/null
exit 0
__STUB__
LENG="$LP/setup-ui.sh"
[ "$(csum "$LENG")" = "$LENG_SIG_BEFORE" ] \
  && ok "(l3) the engine the timing arms measure is byte-identical to the shipped one (sha256) — the stub is installed by moving the engine, never by editing it" \
  || no "(l3) the engine the timing arms measure is byte-identical to the shipped one" "the copy at $LENG differs from $ENGINE"

# five registered projects, each a real directory, registered by the engine's own `add`
li=1
while [ "$li" -le 5 ]; do
  mkdir -p "$L/proj-$li" || setup_fail "(l) fixture: could not create $L/proj-$li"
  ( cd "$L/proj-$li" && bash "$LENG" add --registry "$LREG" ) >/dev/null 2>&1
  li=$((li + 1))
done
l_n_reg="$(jq -r '.projects | length' "$LREG" 2>/dev/null)"
[ "$l_n_reg" = "5" ] \
  || setup_fail "(l) fixture: five projects were not registered (got '$l_n_reg') — every timing arm below would measure the wrong scenario"

# The measurement driver. It calibrates the unit, starts the loop, waits for a FIXED number of
# ticks of the SELECTED project and reports the period - never a pass/fail verdict, which stays
# in bash where every other assertion in this file lives.
LDRV="$L/measure.py"
cat > "$LDRV" <<'__PY_SCHED__'
import json, os, subprocess, sys, time
engine, uidir, reg, sel, stub_log, interval, nticks, port = sys.argv[1:9]
interval = int(interval); nticks = int(nticks)
env = dict(os.environ); env["STUB_LOG"] = stub_log
stubdir = os.path.dirname(engine)
scratch = os.path.join(os.path.dirname(stub_log), "unit-scratch-" + os.path.basename(stub_log))
if not os.path.isdir(scratch):
    os.makedirs(scratch)

def one():
    t = time.time()
    subprocess.call(["bash", os.path.join(stubdir, "build-floor.sh")], cwd=scratch, env=env,
                    stdout=open(os.devnull, "w"), stderr=subprocess.STDOUT)
    return time.time() - t

# THE UNIT: the cheapest of three runs of the same stub, in this same run on this same machine.
unit = min(one() for _ in range(3))
open(stub_log, "w").close()

subprocess.call(["bash", engine, "serve", "--ui-dir", uidir, "--registry", reg,
                 "--port", port, "--interval", str(interval), "--detach"],
                cwd=sel, env=env, stdout=open(os.devnull, "w"), stderr=subprocess.STDOUT)
deadline = time.time() + nticks * (interval + 6 * unit) + 25
sel_real = os.path.realpath(sel)

def stamps():
    out = []
    try:
        for ln in open(stub_log):
            parts = ln.rstrip("\n").split(" ", 1)
            if len(parts) == 2 and os.path.realpath(parts[1]) == sel_real:
                out.append(float(parts[0]))
    except Exception:
        pass
    return out

while time.time() < deadline:
    if len(stamps()) >= nticks + 1:
        break
    time.sleep(0.05)
s = stamps()
subprocess.call(["bash", engine, "stop", "--ui-dir", uidir, "--registry", reg],
                stdout=open(os.devnull, "w"), stderr=subprocess.STDOUT)
total = 0
if os.path.exists(stub_log):
    total = sum(1 for _ in open(stub_log))
others = total - len(s)
if unit <= 0 or len(s) < nticks + 1:
    print(json.dumps({"ok": False, "ticks_seen": len(s), "total_runs": total}))
else:
    period = (s[nticks] - s[0]) / nticks
    print(json.dumps({"ok": True, "unit_ms": int(unit * 1000), "period_ms": int(period * 1000),
                      "units_x100": int(round((period - interval) / unit * 100)),
                      "selected_runs": len(s), "other_runs": others, "total_runs": total}))
__PY_SCHED__

l_free_port() { python3 -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()' 2>/dev/null; }

# l_measure <engine> <ui dir> <log> -> the driver's JSON on stdout
l_measure() {
  local eng="$1" uid="$2" log="$3" port
  port="$(l_free_port)"
  case "${port:-x}" in ''|*[!0-9]*) printf '{"ok":false,"reason":"no free port"}'; return 0 ;; esac
  bash "$eng" apply --ui-dir "$uid" --registry "$LREG" >/dev/null 2>&1
  SERVE_PIDFILES="$SERVE_PIDFILES $uid/serve.pid"
  STUB_COST="$LSTUB_COST" python3 "$LDRV" "$eng" "$uid" "$LREG" "$L/proj-1" "$log" "$LINTERVAL" "$LTICKS" "$port" 2>/dev/null
}

l_field() { printf '%s' "$1" | jq -r --arg k "$2" '.[$k] // "x"' 2>/dev/null; }

# --- (l4) PREMISE: the stub really costs something, and really writes the artefact -------
# A stub that cost nothing would make every arm below measure only the sleep in the loop, and a
# stub that wrote nothing would make the engine's copy step a no-op.
mkdir -p "$L/premise" || setup_fail "(l) fixture: could not create $L/premise"
l_prem_ms="$(python3 -c 'import sys,os,time,subprocess
env = dict(os.environ); env["STUB_LOG"] = sys.argv[3]; env["STUB_COST"] = sys.argv[4]
t = time.time()
subprocess.call(["bash", sys.argv[1]], cwd=sys.argv[2], env=env, stdout=open(os.devnull,"w"), stderr=subprocess.STDOUT)
print(int((time.time() - t) * 1000))' "$LP/build-floor.sh" "$L/premise" "$L/premise.log" "$LSTUB_COST" 2>/dev/null)"
case "${l_prem_ms:-x}" in
  ''|*[!0-9]*) no "(l4) PREMISE: the stub projector has a measurable cost" "could not time it (got '$l_prem_ms')" ;;
  *)
    [ "$l_prem_ms" -ge 300 ] && [ -f "$L/premise/.supervisor/floor/floor.json" ] \
      && ok "(l4) PREMISE: the stub projector costs ${l_prem_ms}ms and writes .supervisor/floor/floor.json — the arms below measure a real cost, not an empty loop" \
      || no "(l4) PREMISE: the stub projector has a real cost and writes the artefact" \
           "cost=${l_prem_ms}ms artefact=$([ -f "$L/premise/.supervisor/floor/floor.json" ] && echo written || echo MISSING)" ;;
esac

# --- (l5)/(l6)/(l7) PRIMARY ARM: the shipped engine, five projects -----------------------
L_REAL="$(l_measure "$LENG" "$L/ui-real" "$L/stub-real.log")"
l_ok="$(l_field "$L_REAL" ok)"
l_units="$(l_field "$L_REAL" units_x100)"
l_sel_runs="$(l_field "$L_REAL" selected_runs)"
l_other_runs="$(l_field "$L_REAL" other_runs)"
if [ "$l_ok" != "true" ]; then
  no "(l5) PRIMARY: the serve loop completed $LTICKS ticks with five projects registered" \
     "the loop never reached $((LTICKS + 1)) regenerations of the selected project: $L_REAL — which is ITSELF the starvation this case is about, reported as inconclusive rather than as a pass"
  no "(l6) PRIMARY: the loop's per-tick cost is within $LSCHED_BUDGET hundredths of one projector run" "no measurement: $L_REAL"
  no "(l7) ANTI-VACUITY: the background projects were really regenerated" "no measurement: $L_REAL"
else
  ok "(l5) PRIMARY: with five projects registered the loop completed $LTICKS ticks and regenerated the selected project $l_sel_runs times (period $(l_field "$L_REAL" period_ms)ms against a ${LINTERVAL}s interval, unit $(l_field "$L_REAL" unit_ms)ms)"
  if [ "$l_units" -le "$LSCHED_BUDGET" ] 2>/dev/null; then
    ok "(l6) PRIMARY: one tick costs $l_units hundredths of a projector run, within the $LSCHED_BUDGET budget — the loop does not fall behind its own interval at five projects"
  else
    no "(l6) PRIMARY: one tick costs $l_units hundredths of a projector run, OVER the $LSCHED_BUDGET budget" \
       "the loop is falling behind its own interval — every project on this page would render permanently stale"
  fi
  if [ "$l_other_runs" -ge 1 ] 2>/dev/null; then
    ok "(l7) ANTI-VACUITY: $l_other_runs background regeneration(s) happened inside that window — the bound is not being met by simply never regenerating the other projects"
  else
    no "(l7) ANTI-VACUITY: the background projects were regenerated at least once in the window" \
       "0 background runs — (l6) would pass for a loop that ignores every project but the selected one"
  fi
fi

# --- (l8) CONTROL: the naive shape must be OVER budget ----------------------------------
LNAIVE="$L/naive"
mkdir -p "$LNAIVE/floor-ui" || setup_fail "(l) fixture: could not create $LNAIVE"
cp "$LP/build-floor.sh" "$LNAIVE/" && cp "$BUNDLE_DIR"/* "$LNAIVE/floor-ui/" \
  || setup_fail "(l) fixture: could not stage the naive mutant's plugin directory"
python3 - "$ENGINE" "$LNAIVE/setup-ui.sh" <<'__PY_NAIVE__'
import io, sys
src, dst = sys.argv[1], sys.argv[2]
s = io.open(src, encoding='utf-8').read()
a = '  if [ "$REGEN" -eq 1 ] && [ $((tick % SLOW_FACTOR)) -eq 0 ]; then\n'
b = '  write_served_index\n'
i = s.index(a)
j = s.index(b, i)
naive = (
  '  if [ "$REGEN" -eq 1 ]; then\n'
  '    reg_rows | awk -F"$TAB" -v sel="$SELECTED_SLUG" \'NF && $1 != sel\' > "$UI_DIR/.mutant-others" 2>/dev/null\n'
  '    while IFS="$TAB" read -r o_slug o_path; do\n'
  '      [ -n "$o_slug" ] && [ -n "$o_path" ] && regen_project "$o_path" "$o_slug"\n'
  '    done < "$UI_DIR/.mutant-others"\n'
  '  fi\n'
)
io.open(dst, 'w', encoding='utf-8').write(s[:i] + naive + s[j:])
__PY_NAIVE__
if mutant_ok "$ENGINE" "$LNAIVE/setup-ui.sh" shell; then
  L_NAIVE="$(l_measure "$LNAIVE/setup-ui.sh" "$L/ui-naive" "$L/stub-naive.log")"
  l_n_units="$(l_field "$L_NAIVE" units_x100)"
  if [ "$(l_field "$L_NAIVE" ok)" != "true" ]; then
    ok "(l8) MUTATION CONTROL: the naive mutant (every project regenerated every tick) could not deliver $LTICKS ticks inside the deadline at all — the starvation is measurable ($L_NAIVE)"
  elif [ "$l_n_units" -gt "$LSCHED_BUDGET" ] 2>/dev/null; then
    ok "(l8) MUTATION CONTROL: the naive mutant costs $l_n_units hundredths per tick, OVER the $LSCHED_BUDGET budget (shipped engine: $l_units) — (l6) can detect the starvation it claims to"
  else
    no "(l8) MUTATION CONTROL: a loop that regenerates every project every tick is OVER budget" \
       "the naive mutant measured $l_n_units, within the $LSCHED_BUDGET budget — (l6) is not discriminating and would pass through the very regression it exists to catch"
  fi
fi

# --- (l9) NULL-MUTATION CONTROL: a harmless mutant must stay WITHIN budget ---------------
# Without this, (l8) would also "pass" for a measurement that flagged any mutant whatsoever,
# and the naive control would be proving nothing about the SCHEDULING.
LNULL="$L/nullmut"
mkdir -p "$LNULL/floor-ui" || setup_fail "(l) fixture: could not create $LNULL"
cp "$LP/build-floor.sh" "$LNULL/" && cp "$BUNDLE_DIR"/* "$LNULL/floor-ui/" \
  || setup_fail "(l) fixture: could not stage the null mutant's plugin directory"
{ cat "$ENGINE"; printf '\n# null mutation: this comment changes nothing the serve loop does.\n'; } > "$LNULL/setup-ui.sh" 2>/dev/null
if mutant_ok "$ENGINE" "$LNULL/setup-ui.sh" shell; then
  L_NULL="$(l_measure "$LNULL/setup-ui.sh" "$L/ui-null" "$L/stub-null.log")"
  l_z_units="$(l_field "$L_NULL" units_x100)"
  if [ "$(l_field "$L_NULL" ok)" != "true" ]; then
    no "(l9) NULL-MUTATION CONTROL: a mutant that changes nothing measures within budget" "inconclusive: $L_NULL"
  elif [ "$l_z_units" -le "$LSCHED_BUDGET" ] 2>/dev/null; then
    ok "(l9) NULL-MUTATION CONTROL: a mutant that parses, differs and does no damage measures $l_z_units hundredths — still within budget, so (l8) is detecting the SCHEDULING change and not merely the presence of a mutant"
  else
    no "(l9) NULL-MUTATION CONTROL: a harmless mutant stays within budget" \
       "it measured $l_z_units, over the $LSCHED_BUDGET budget — the measurement flags mutants rather than starvation, which would make (l8) worthless"
  fi
fi

# --- (l10)/(l11) the served index: every registered project, at the paths the page builds --
L_IDX="$L/ui-real/index.json"
if [ -f "$L_IDX" ]; then
  l_idx_n="$(jq -r '.projects | length' "$L_IDX" 2>/dev/null)"
  l_idx_sel="$(jq -r '.serve.selected_slug // ""' "$L_IDX" 2>/dev/null)"
  l_idx_keys="$(jq -r '[(.module|has("bundle")), (.registry|has("state")), (.serve|has("interval_seconds")), (.serve|has("slow_cadence_ticks"))] | all' "$L_IDX" 2>/dev/null)"
  [ "$l_idx_n" = "5" ] && [ "$l_idx_sel" = "proj-1" ] && [ "$l_idx_keys" = "true" ] \
    && ok "(l10) the served index lists all five registered projects, names the selected one ($l_idx_sel) and carries the module state, the registry state and the cadence the page renders" \
    || no "(l10) the served index lists every registered project and carries module/registry/cadence state" \
         "projects=$l_idx_n selected='$l_idx_sel' keys=$l_idx_keys"
  l_slots="$(find "$L/ui-real/projects" -name floor.json 2>/dev/null | awk 'END{print NR+0}')"
  l_slot_named="$(jq -r '[.projects[] | select(.state == "ready") | .slug] | length' "$L_IDX" 2>/dev/null)"
  [ "${l_slots:-0}" -ge 2 ] 2>/dev/null && [ "${l_slot_named:-0}" -ge 2 ] 2>/dev/null \
    && ok "(l11) every project the loop regenerated has a document at the exact relative path the page builds — projects/<slug>/floor.json, $l_slots slot(s) on disk and $l_slot_named row(s) reported ready — so the picker adds no request this static server cannot answer" \
    || no "(l11) each regenerated project has a document at projects/<slug>/floor.json" "slots=$l_slots ready-rows=$l_slot_named"
else
  no "(l10) the served index is written into the ui directory" "no index.json in $L/ui-real"
  no "(l11) each regenerated project has a document at projects/<slug>/floor.json" "no index.json to read"
fi

# --- (l12)/(l13) AC-2c: a project whose directory vanishes UNDER A LIVE SERVE ------------
# The other projects must keep rendering and the server must not exit - so this deletes the
# directory WHILE the loop is running and then reads the next index the loop wrote.
LC_UI="$L/ui-vanish"
bash "$LENG" apply --ui-dir "$LC_UI" --registry "$LREG" >/dev/null 2>&1
lc_port="$(l_free_port)"
case "${lc_port:-x}" in
  ''|*[!0-9]*) skipn "(l12) no free port could be obtained for the vanishing-project probe" ;;
  *)
    ( cd "$L/proj-1" && STUB_COST="$LSTUB_COST" STUB_LOG="$L/stub-vanish.log" \
        bash "$LENG" serve --ui-dir "$LC_UI" --registry "$LREG" --port "$lc_port" --interval 1 --detach ) >/dev/null 2>&1
    SERVE_PIDFILES="$SERVE_PIDFILES $LC_UI/serve.pid"
    lc_pid="$(awk 'NR==1' "$LC_UI/serve.pid" 2>/dev/null)"
    rm -rf "$L/proj-3"
    lc_state=""; lc_i=0
    while [ "$lc_i" -lt 60 ]; do
      lc_state="$(jq -r '[.projects[] | select(.slug == "proj-3") | .state] | first // ""' "$LC_UI/index.json" 2>/dev/null)"
      [ "$lc_state" = "unavailable" ] && break
      sleep 0.25; lc_i=$((lc_i + 1))
    done
    lc_reason="$(jq -r '[.projects[] | select(.slug == "proj-3") | .reason] | first // ""' "$LC_UI/index.json" 2>/dev/null)"
    lc_others="$(jq -r '[.projects[] | select(.slug != "proj-3")] | length' "$LC_UI/index.json" 2>/dev/null)"
    lc_alive=no; kill -0 "$lc_pid" 2>/dev/null && lc_alive=yes
    bash "$LENG" stop --ui-dir "$LC_UI" --registry "$LREG" >/dev/null 2>&1
    [ "$lc_state" = "unavailable" ] && [ -n "$lc_reason" ] && [ "$lc_others" = "4" ] && [ "$lc_alive" = "yes" ] \
      && ok "(l12) AC-2c: a registered project deleted UNDER a live serve renders 'unavailable' with a reason, the other 4 keep being listed, and the server was still running afterwards" \
      || no "(l12) a project deleted under a live serve renders unavailable with its reason, the others keep rendering and the server survives" \
           "state='$lc_state' reason='$lc_reason' others='$lc_others' (want 4) server-alive=$lc_alive"
    lc_still="$(jq -r '[.projects[] | select(.slug == "proj-3")] | length' "$LREG" 2>/dev/null)"
    [ "$lc_still" = "1" ] \
      && ok "(l13) the vanished project is STILL in the registry — the serve loop reports what it found and never edits the user's registry on its behalf" \
      || no "(l13) the vanished project is still in the registry" "found $lc_still entries for proj-3 — the loop mutated the registry" ;;
esac

# --- (l14)/(l15) AC-2e: absent and unparseable are TWO different claims ------------------
LE_UI="$L/ui-regstate"
bash "$LENG" apply --ui-dir "$LE_UI" --registry "$L/no-such-registry.json" >/dev/null 2>&1
le_port="$(l_free_port)"
( cd "$L/proj-1" && bash "$LENG" serve --ui-dir "$LE_UI" --registry "$L/no-such-registry.json" --port "$le_port" --no-regen --detach ) >/dev/null 2>&1
SERVE_PIDFILES="$SERVE_PIDFILES $LE_UI/serve.pid"
bash "$LENG" stop --ui-dir "$LE_UI" --registry "$L/no-such-registry.json" >/dev/null 2>&1
le_absent="$(jq -r '.registry.state' "$LE_UI/index.json" 2>/dev/null)"
le_absent_reason="$(jq -r '.registry.reason // ""' "$LE_UI/index.json" 2>/dev/null)"
[ "$le_absent" = "absent" ] && [ -n "$le_absent_reason" ] && [ ! -e "$L/no-such-registry.json" ] \
  && ok "(l14) AC-2e: with no registry file the served index says 'absent' with a reason and creates nothing — never 'unparseable', which is a different claim about a file the user actually has" \
  || no "(l14) an absent registry is reported as absent, with a reason, and is not created" \
       "state='$le_absent' reason='$le_absent_reason' created=$([ -e "$L/no-such-registry.json" ] && echo YES || echo no)"

LBAD="$L/bad-registry.json"
printf '{ this is not json\n' > "$LBAD"
lbad_sig="$(csum "$LBAD")"
LB_UI="$L/ui-badreg"
bash "$LENG" apply --ui-dir "$LB_UI" --registry "$LBAD" >/dev/null 2>&1
lb_port="$(l_free_port)"
( cd "$L/proj-1" && bash "$LENG" serve --ui-dir "$LB_UI" --registry "$LBAD" --port "$lb_port" --no-regen --detach ) >/dev/null 2>&1
SERVE_PIDFILES="$SERVE_PIDFILES $LB_UI/serve.pid"
bash "$LENG" stop --ui-dir "$LB_UI" --registry "$LBAD" >/dev/null 2>&1
lb_state="$(jq -r '.registry.state' "$LB_UI/index.json" 2>/dev/null)"
lb_reason="$(jq -r '.registry.reason // ""' "$LB_UI/index.json" 2>/dev/null)"
[ "$lb_state" = "unparseable" ] && [ -n "$lb_reason" ] && [ "$lbad_sig" = "$(csum "$LBAD")" ] \
  && ok "(l15) AC-2e: an unparseable registry is reported as 'unparseable' with a reason, DISTINCTLY from absent, and the file is preserved byte for byte — serve reads it and refuses, exactly like every other verb" \
  || no "(l15) an unparseable registry is reported as unparseable, distinctly, and preserved byte for byte" \
       "state='$lb_state' reason='$lb_reason' preserved=$([ "$lbad_sig" = "$(csum "$LBAD")" ] && echo yes || echo NO)"

# --- (l16) with jq UNFINDABLE, serve still writes an honest index ------------------------
# The registry is JSON this engine will not parse by hand, and without jq nothing can be
# regenerated either, because build-floor.sh needs it too. The page must therefore receive a
# document that NAMES jq rather than an empty project list with no reason.
LJ_STUB="$L/bin-nojq"
mkstub "$LJ_STUB" "jq" || setup_fail "(l) fixture: could not build the jq-absent PATH stub"
[ ! -e "$LJ_STUB/jq" ] || setup_fail "(l) fixture: the jq-absent stub still contains jq"
LJ_UI="$L/ui-nojq"
bash "$LENG" apply --ui-dir "$LJ_UI" --registry "$LREG" >/dev/null 2>&1
lj_port="$(l_free_port)"
( cd "$L/proj-1" && PATH="$LJ_STUB" bash "$LENG" serve --ui-dir "$LJ_UI" --registry "$LREG" --port "$lj_port" --no-regen --detach ) >/dev/null 2>&1
SERVE_PIDFILES="$SERVE_PIDFILES $LJ_UI/serve.pid"
bash "$LENG" stop --ui-dir "$LJ_UI" --registry "$LREG" >/dev/null 2>&1
lj_state="$(jq -r '.registry.state' "$LJ_UI/index.json" 2>/dev/null)"
lj_reason="$(jq -r '.registry.reason // ""' "$LJ_UI/index.json" 2>/dev/null)"
lj_valid=no; jq -e . "$LJ_UI/index.json" >/dev/null 2>&1 && lj_valid=yes
[ "$lj_state" = "unreadable" ] && [ "$lj_valid" = "yes" ] && in_str "$lj_reason" "jq" \
  && ok "(l16) with jq UNFINDABLE, serve still writes a VALID served index reporting the registry 'unreadable' and naming jq — the page gets a reason, not an empty list" \
  || no "(l16) with jq unfindable, serve writes a valid index naming jq as the reason" \
       "state='$lj_state' valid-json=$lj_valid reason='$lj_reason'"

# --- (l17)/(l18) WRITE CONTAINMENT: a regenerated project gains its floor.json, nothing else -
# `serve` now runs the projector inside directories the user registered. That is the feature and
# it is also the largest new blast radius in this change, so it is HASHED rather than reasoned
# about: every fixture project must hold exactly the projector's own artefact and nothing more.
l_dirty=""
for li in 1 2 4 5; do
  [ -d "$L/proj-$li" ] || continue
  l_extra="$(cd "$L/proj-$li" && find . -mindepth 1 2>/dev/null \
    | grep -v -E '^\./\.supervisor(/floor(/floor\.json)?)?$' | LC_ALL=C sort | tr '\n' ' ')"
  [ -n "$l_extra" ] && l_dirty="$l_dirty [proj-$li:$l_extra]"
done
[ -z "$l_dirty" ] \
  && ok "(l17) every regenerated project contains .supervisor/floor/floor.json and NOTHING else — registering a project is not a licence to write into it" \
  || no "(l17) a regenerated project contains only .supervisor/floor/floor.json" "$l_dirty"
l_wrote="$(find "$L/proj-2" "$L/proj-4" "$L/proj-5" -name floor.json 2>/dev/null | awk 'END{print NR+0}')"
[ "${l_wrote:-0}" -ge 1 ] 2>/dev/null \
  && ok "(l18) ANTI-VACUITY: the loop really did regenerate a project other than the selected one ($l_wrote artefact(s)), so (l17) is not passing on directories nothing ever touched" \
  || no "(l18) ANTI-VACUITY: the loop regenerated at least one background project" "found $l_wrote — (l17) may be vacuous"

# --- (l19)/(l20) AC-2d and AC-2f, re-run over the CHANGED bundle -------------------------
# The SAME shared scanner AND the same shared expectation (j13) uses — not a private copy of
# either. This site re-runs the check 1,400 lines later over the same shipped bundle, and it
# reddens byte-for-byte identically; routing both through no_write_verbs_baseline is what makes
# "they cannot drift apart" a fact of the code rather than a note in a review.
l_write_findings="$(no_write_verbs_baseline)"
[ -z "$l_write_findings" ] \
  && ok "(l19) AC-2d: the bundle carrying the picker AND the write path still matches the exact write-verb baseline — index.html and floor.css at zero, floor.js at exactly $NWV_JS_EXPECT (the shared scanner and shared expectation (j13) defines, re-run over the changed files)" \
  || no "(l19) the bundle matches the exact write-verb baseline" "$l_write_findings"
l_egress=""
for lf in "$HTML" "$CSS" "$JS"; do
  lout="$(scan_egress "$lf")"
  [ -n "$lout" ] && l_egress="$l_egress
$(basename "$lf"): $lout"
done
[ -z "$l_egress" ] \
  && ok "(l20) AC-2f: the bundle carrying the picker still references nothing off this origin (the scanner (a1) defines, re-run over the changed files)" \
  || no "(l20) the bundle carrying the picker references nothing off this origin" "$l_egress"

# --- (l21) THE MOTION BUDGET SURVIVES THE PICKER -----------------------------------------
# Per-project scheduling on the page is driven from the ONE existing poll. A second timer would
# be the easiest possible way to smuggle motion in, so the budget is re-counted, in code.
l_int="$(code_occ "$JS" 'setInterval[(]')"
l_raf="$(code_occ "$JS" 'requestAnimationFrame')"
l_to="$(code_occ "$JS" 'setTimeout[(]')"
[ "$l_int" = "1" ] && [ "$l_raf" = "0" ] && [ "$l_to" = "0" ] \
  && ok "(l21) the picker added NO timer: floor.js still has exactly one setInterval and no rAF or setTimeout in code (int=$l_int rAF=$l_raf timeout=$l_to)" \
  || no "(l21) the picker added no timer" "setInterval=$l_int rAF=$l_raf setTimeout=$l_to"

# --- (l22)/(l23) the fetched URL is BUILT here, never taken from the served document ------
# The index is a document the page did not author. If the per-project URL were read out of it, a
# hostile or merely wrong index could point the page at another path entirely; the CSP would
# refuse an off-origin fetch, but that is a header, and this makes it a property of the code.
l_url_bad=""
has_lit "$JS" "fetchText(projectUrl(selectedSlug))" || l_url_bad="$l_url_bad [the floor url is not built by projectUrl]"
has_lit "$JS" "fetchText(SERVED_INDEX)" || l_url_bad="$l_url_bad [the index url is not the fixed constant]"
[ "$(code_occ "$JS" 'fetchText[(]')" = "3" ] || l_url_bad="$l_url_bad [fetchText has call sites beyond the two expected]"
[ -z "$l_url_bad" ] \
  && ok "(l22) both URLs the page fetches are built in floor.js — a fixed constant and projectUrl(<encoded slug>) — never read out of the served index" \
  || no "(l22) both fetched URLs are built in floor.js, never read from the served index" "$l_url_bad"
MUT_URL="$TMPROOT/mut-url.js"
sed 's|fetchText(projectUrl(selectedSlug))|fetchText(idx.projects[0].floor_url)|' "$JS" > "$MUT_URL" 2>/dev/null
if mutant_ok "$JS" "$MUT_URL"; then
  m_url=0
  has_lit "$MUT_URL" "fetchText(projectUrl(selectedSlug))" && m_url=1
  [ "$m_url" = "0" ] \
    && ok "(l23) MUTATION CONTROL: a page that fetched a URL taken verbatim from the served index IS flagged by (l22)" \
    || no "(l23) MUTATION CONTROL: a URL taken from the served index is flagged" "the gate stayed clean on a mutant that fetches a document-supplied path"
fi

# --- (l24)/(l25) the page's OWN words for each state --------------------------------------
l_lit_bad=""
for llit in "'unavailable'" "'never-regenerated'" "registry absent" "registry unparseable" "no served index at this origin"; do
  has_lit "$JS" "$llit" || l_lit_bad="$l_lit_bad [$llit]"
done
[ -z "$l_lit_bad" ] \
  && ok "(l24) floor.js names each state in its own words: unavailable, never regenerated, registry absent, registry unparseable, and no served index at this origin" \
  || no "(l24) floor.js names each project and registry state distinctly" "missing:$l_lit_bad"
# MUTATION CONTROL: collapsing absent and unparseable into one message must redden (l24). That
# collapse is the specific defect AC-2e forbids and it is invisible to every other assertion.
MUT_REG="$TMPROOT/mut-regstate.js"
sed "s|return 'registry unparseable|return 'registry absent|" "$JS" > "$MUT_REG" 2>/dev/null
if mutant_ok "$JS" "$MUT_REG"; then
  m_reg=0
  has_lit "$MUT_REG" "registry unparseable" && m_reg=1
  [ "$m_reg" = "0" ] \
    && ok "(l25) MUTATION CONTROL: a page reporting an unparseable registry as an absent one IS flagged — the two claims cannot be collapsed without (l24) noticing" \
    || no "(l25) MUTATION CONTROL: collapsing unparseable into absent is flagged" "the mutant still carries both literals"
fi

# --- (l26)/(l27) THE COMMITTED BROWSER FIXTURES -------------------------------------------
# The browser halves of AC-2a, AC-2d and AC-2e are NOT verified here and this file does not
# pretend otherwise (see the header). What IS asserted is that the fixtures a browser pass will
# load exist, that each really exercises the state it is named for, and — crucially — that none
# of them pins a shape the engine can no longer produce. They were GENERATED by running the real
# engine against fixture registries, with the temp paths then rewritten to a readable stand-in;
# (l27) is what keeps that generation honest as the engine moves.
LFIX="$FIX_DIR/served"
if [ ! -d "$LFIX" ]; then
  no "(l26) the served-index browser fixtures are committed" "no directory at $LFIX"
  no "(l27) no committed served-index fixture pins a key the engine can no longer emit" "no fixtures to check"
else
  l_fix_bad=""
  l_check() {
    local got; got="$(jq -r "$2" "$LFIX/$1" 2>/dev/null)"
    [ "$got" = "$3" ] || l_fix_bad="$l_fix_bad [$1: $2 = '$got', want '$3']"
  }
  l_check index-two-projects.json         '.projects | length' 2
  l_check index-two-projects.json         '.registry.state' ok
  l_check index-five-projects.json        '.projects | length' 5
  l_check index-five-projects.json        '[.projects[] | select(.selected == true)] | length' 1
  l_check index-three-one-missing.json    '.projects | length' 3
  l_check index-three-one-missing.json    '[.projects[] | select(.state == "unavailable")] | length' 1
  l_check index-three-one-missing.json    '[.projects[] | select(.state == "unavailable") | .reason] | first | (. != null and . != "")' true
  l_check index-registry-absent.json      '.registry.state' absent
  l_check index-registry-unparseable.json '.registry.state' unparseable
  [ -z "$l_fix_bad" ] \
    && ok "(l26) all five committed served-index fixtures exercise the states they are named for (two projects, five projects, one missing path WITH a reason, registry absent, registry unparseable)" \
    || no "(l26) the committed served-index fixtures exercise their named states" "$l_fix_bad"

  # The live key set is the UNION over every index this run wrote — the registry-ok one, the
  # absent one, the unparseable one and the jq-less one. One index alone would be the wrong
  # subject: `registry.reason` is OMITTED when the registry read cleanly, so comparing an
  # absent-registry fixture against an ok-registry index would flag a key the engine emits
  # constantly. The union is the set of keys the engine CAN emit, which is the actual claim.
  if [ -f "$L_IDX" ]; then
    l_keys_live=" $(jq -r '[paths(scalars) | map(select(type == "string")) | join(".")] | unique | .[]' \
        "$L_IDX" "$LE_UI/index.json" "$LB_UI/index.json" "$LJ_UI/index.json" 2>/dev/null \
        | LC_ALL=C sort -u | tr '\n' ' ')"
    l_key_bad=""
    for lfx in "$LFIX"/*.json; do
      [ -f "$lfx" ] || continue
      for lk in $(jq -r '[paths(scalars) | map(select(type == "string")) | join(".")] | unique | .[]' "$lfx" 2>/dev/null); do
        in_str "$l_keys_live" " $lk " || l_key_bad="$l_key_bad [$(basename "$lfx"):$lk]"
      done
    done
    [ -z "$l_key_bad" ] \
      && ok "(l27) no committed served-index fixture pins a key the engine no longer emits — every key in every fixture appears in an index this run's engine actually wrote" \
      || no "(l27) no committed fixture pins a key the engine can no longer emit" "$l_key_bad"
  else
    no "(l27) no committed fixture pins a key the engine can no longer emit" "the live index from (l10) is missing, so there is nothing to compare against"
  fi
fi

# --- (l28) the shipped files are untouched by every mutant above ---------------------------
l_eng_after="$(csum "$ENGINE")"; l_js_after="$(csum "$JS")"
l_residue="$(ls "$script_dir"/setup-ui-*.sh "$BUNDLE_DIR"/*.mut.js 2>/dev/null || true)"
[ "$LENG_SIG_BEFORE" = "$l_eng_after" ] && [ "$LJS_SIG_BEFORE" = "$l_js_after" ] && [ -z "$l_residue" ] \
  && ok "(l28) the shipped engine and floor.js are byte-identical after every (l) mutation control (sha256 unchanged) and no mutant was left in the plugin's own directories" \
  || no "(l28) the shipped engine and floor.js are byte-identical after the (l) mutation controls" \
       "engine before='$LENG_SIG_BEFORE' after='$l_eng_after'; js before='$LJS_SIG_BEFORE' after='$l_js_after'; residue='$l_residue'"

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

# --- (z10)-(z15): the /ui command's own registration surfaces ---------------------------
# Appended by the `/ui` item. Same reasoning as (z1)-(z3) one level out: a new COMMAND has
# enumerations spread across a command-reference doc, its own flow file and the module docs
# that must not pretend it does not exist, and NO CI gate covers any of them —
# check-command-sync.sh guards only commands/code-reviewer.md, and check-doc-currency.sh
# derives no per-command registration claim at all. These are FOUR separate subjects on
# purpose: a single added row must not be able to satisfy the gate while three go unmet.
UI_MD="$script_dir/../commands/ui.md"
REPO_ROOT="$(cd "$script_dir/../.." 2>/dev/null && pwd)"

# --- (z10) the registry row: the command-reference doc lists /ui ------------------------
# Matched on the heading shape so a passing mention of `/ui` in prose cannot satisfy it.
if has_re "$HELP_MD" '^### .* /ui — '; then
  ok "(z10) commands/agent-help.md carries a \`/ui\` row in its command reference"
else
  no "(z10) commands/agent-help.md carries a \`/ui\` row in its command reference" \
     "agent-help.md is the surface a user reads to discover a command; a command absent from it is unregistered in practice"
fi

# --- (z11) the module flow: the command's own flow document exists ----------------------
if [ -r "$UI_MD" ] && has_re "$UI_MD" '^# Command: /ui$'; then
  ok "(z11) commands/ui.md exists and carries the '# Command: /ui' flow heading"
else
  no "(z11) commands/ui.md exists and carries the '# Command: /ui' flow heading" \
     "the command file IS the flow; agent-help.md only points at it"
fi

# --- (z12) the cross-reference: the module docs do not hide the second entry point ------
# ONE claim, two places it has to hold: a reader who arrives at the module through either
# `/setup ui`'s flow or the setup skill's registry row must learn that the operational half
# lives in `/ui`. Two entry points documented in mutual ignorance is how a user ends up back
# in a terminal running the engine by hand, which is the friction this item removed.
z12_flow=0; z12_row=0
if awk '/^## Module: ui$/{f=1} f&&/^## /&&!/^## Module: ui$/{f=0} f&&index($0,"`/ui`")>0{n++} END{exit !(n>0)}' "$SETUP_MD"; then z12_flow=1; fi
if awk 'index($0,"| `ui` |")==1 && index($0,"`/ui`")>0 {n++} END{exit !(n>0)}' "$SKILL_MD"; then z12_row=1; fi
if [ "$z12_flow" -eq 1 ] && [ "$z12_row" -eq 1 ]; then
  ok "(z12) commands/setup.md's '## Module: ui' flow AND skills/setup/SKILL.md's \`ui\` registry row both name the direct \`/ui\` command"
else
  no "(z12) the module docs name the direct \`/ui\` command" \
     "flow=$z12_flow row=$z12_row (1 = names it) — the half that says 0 documents the module as if the second entry point did not exist"
fi

# --- (z13) zero stale command-count residue ---------------------------------------------
# The command count moved 21 -> 22. Grep the OLD value across the release surfaces rather
# than trusting an enumeration of where it was believed to live: check-doc-currency.sh
# verifies claims that ARE made and structurally cannot see one that should have been made,
# and the previous count bump found two sites its own plan had not named. CHANGELOG.md is
# deliberately NOT scanned — its entries are historical and correctly keep the old number.
#
# WHICH PHRASINGS ARE SWEPT, and one that is DELIBERATELY NOT, because getting this wrong in
# either direction is silent. Only the CURRENT-STATE phrasings are swept. The bare form
# `21 commands` is excluded because a per-release `Counts: 14 agents / N commands / N skills /
# N hooks` line describes THAT release, not the current state, and sweeping the bare form would
# pressure the next author into rewriting frozen release history to appease a gate. That is the
# historical convention CHANGELOG.md uses, and is why CHANGELOG.md is unscanned.
# NOTE (README banners removed): README.md used to carry nine such dated `NEW in vX.Y.Z` banners
# and was the measurement behind this exclusion; its release banners have since been replaced by
# a pointer to CHANGELOG.md, so no scanned surface states a historical count today. The
# narrowing is retained as-is rather than silently tightened — sweeping the bare form is now
# available as a deliberate change, not a side effect of a docs edit. The
# parenthesised `(21 commands` IS swept, because that is the current-state form README uses
# in its live "Commands are in ..." pointer. (z14) is what keeps this narrowing honest: it
# requires the current claim to actually be present, so a surface that simply stopped stating
# a count cannot pass (z13) by having nothing to be stale about.
Z_SURFACES="$REPO_ROOT/README.md $REPO_ROOT/CLAUDE.md $REPO_ROOT/.claude-plugin/README.md $REPO_ROOT/.claude-plugin/marketplace.json $script_dir/../.claude-plugin/plugin.json $HELP_MD"
z_seen=0; z_stale=""
for f in $Z_SURFACES; do
  [ -r "$f" ] || continue
  z_seen=$((z_seen + 1))
  for pat in '21 slash commands' 'Slash commands (21)' '21 entry points' '(21 commands'; do
    if has_lit "$f" "$pat"; then z_stale="$z_stale [$(basename "$f"):$pat]"; fi
  done
done
if [ "$z_seen" -lt 5 ]; then
  no "(z13) no stale '21 commands' residue on the release surfaces" \
     "only $z_seen of 6 surfaces were readable from this suite, so the sweep would be near-vacuous"
elif [ -z "$z_stale" ]; then
  ok "(z13) no stale '21 commands' residue across $z_seen release surfaces"
else
  no "(z13) no stale '21 commands' residue across the release surfaces" "still stale in:$z_stale"
fi

# --- (z14) ANTI-VACUITY for (z13) --------------------------------------------------------
# The grep above proves nothing if the count claim is simply ABSENT: a surface that states no
# command count at all passes (z13) while being just as rotten. This is the same anti-vacuity
# pairing (z6) makes for (z5), one enumeration over.
z14_missing=""
for f in "$REPO_ROOT/README.md" "$REPO_ROOT/CLAUDE.md" "$REPO_ROOT/.claude-plugin/README.md" "$HELP_MD"; do
  [ -r "$f" ] || { z14_missing="$z14_missing [unreadable:$(basename "$f")]"; continue; }
  if has_re "$f" '22 slash commands|Slash commands \(22\)|22 entry points|\(22 commands'; then :; else
    z14_missing="$z14_missing [$(basename "$f")]"
  fi
done
if [ -z "$z14_missing" ]; then
  ok "(z14) all four prose surfaces state the CURRENT command count, so (z13) is not passing on an absent claim"
else
  no "(z14) all four prose surfaces state the CURRENT command count" \
     "(z13) may be vacuous — no command-count claim found in:$z14_missing"
fi

# --- (z15) AC-3d: the write list stays EXHAUSTIVE ----------------------------------------
# `docs/FLOOR_UI.md`'s "What it writes — the whole list" says "the whole list" and "Nothing
# else, anywhere". `serve` gained a served index, and a section that claims exhaustiveness
# while omitting a write is worse than one that never claimed it. The obligation gets a
# MECHANICAL subject rather than staying prose: the filename is read out of the engine's own
# SERVED_INDEX assignment, so this cannot rot into a check for a literal the engine renamed.
served_index_name="$(sed -n 's/^SERVED_INDEX="\([^"]*\)".*$/\1/p' "$ENGINE" | head -1)"
write_list="$(awk '/^## What it writes — the whole list$/{f=1;next} f&&/^## /{f=0} f{print}' "$FLOOR_MD")"
if [ -z "$served_index_name" ]; then
  no "(z15) FLOOR_UI.md's write list names the served index" \
     "SERVED_INDEX could not be parsed out of the engine, so this assertion would be vacuous"
elif [ -z "$write_list" ]; then
  no "(z15) FLOOR_UI.md's write list names the served index" \
     "the '## What it writes — the whole list' section was not found in $FLOOR_MD"
elif in_str "$write_list" "$served_index_name"; then
  ok "(z15) FLOOR_UI.md's '## What it writes — the whole list' names the served index ('$served_index_name'), read out of the engine"
else
  no "(z15) FLOOR_UI.md's '## What it writes — the whole list' names the served index" \
     "the engine writes '$served_index_name' but that section does not name it — the section claims to be the whole list"
fi

# --- (z16) the same exhaustiveness claim, for the SERVE LOG this item added ----------------
# `serve` gained a second file it writes into the ui directory, and "the whole list" is a claim
# that has to be re-earned every time the engine grows a write — mechanically, with the engine
# as the subject, rather than by a reviewer remembering. Same shape as (z15) deliberately: the
# name is READ OUT OF THE ENGINE, so renaming it there fails here instead of shipping a write
# list that quietly stopped being whole.
serve_log_name="$(sed -n 's/^SERVE_LOG="\([^"]*\)".*$/\1/p' "$ENGINE" | head -1)"
if [ -z "$serve_log_name" ]; then
  no "(z16) FLOOR_UI.md's write list names the serve log" \
     "SERVE_LOG could not be parsed out of the engine, so this assertion would be vacuous"
elif [ -z "$write_list" ]; then
  no "(z16) FLOOR_UI.md's write list names the serve log" \
     "the '## What it writes — the whole list' section could not be read out of FLOOR_UI.md"
elif in_str "$write_list" "$serve_log_name"; then
  ok "(z16) FLOOR_UI.md's '## What it writes — the whole list' names the serve log ('$serve_log_name'), read out of the engine"
else
  no "(z16) FLOOR_UI.md's '## What it writes — the whole list' names the serve log" \
     "the engine writes '$serve_log_name' into the ui directory but that section does not name it — the section claims to be the whole list"
fi

# --- (z17) FLOOR_UI.md explains the threat model, in its own section (AC17) ----------------
# A reader who does not understand WHY a loopback port needs a token will remove the guard as
# ceremony. The section is required to exist AND to name both attacks by their mechanism —
# the other tab's write landing without the reply being readable, and DNS rebinding — plus the
# fact an Origin check alone cannot cover the second, which is the whole reason Host is a
# separate part. Presence of the heading alone would be satisfied by an empty section.
z_guard="$(awk '/^## Why the guard exists$/{f=1;next} f&&/^## /{f=0} f{print}' "$FLOOR_MD")"
z_missing=""
for zphrase in "another tab" "rebinding" "preflight" "Host" "Origin"; do
  case "$z_guard" in *"$zphrase"*) ;; *) z_missing="$z_missing [$zphrase]" ;; esac
done
[ -n "$z_guard" ] && [ -z "$z_missing" ] \
  && ok "(z17) FLOOR_UI.md carries a '## Why the guard exists' section that states the threat model in plain terms — the other-tab write, DNS rebinding, the preflight the custom header forces, and why an Origin check alone does not cover the rebinding case" \
  || no "(z17) FLOOR_UI.md documents the threat model in plain terms" "section $( [ -n "$z_guard" ] && echo present || echo ABSENT ); unexplained:$z_missing"



# (l29)/(l30) — LANE MEMORY MUST BE RESET BY THE ASSIGNMENT, NOT BY ONE CALLER OF IT.
# The CI reviewer found that resetProjectMemory() was wired to the picker's onchange alone,
# while renderProjectPicker ALSO reassigns selectedSlug on two paths the reader never touches:
# the served index going momentarily absent/unreadable (root fallback), and the "follow it"
# branch when the viewed project drops out of the registry. Those paths switched the rendered
# document while prevEvents/shuttleStep still held the PREVIOUS project's per-agent counts —
# and untyped rows fall back to a positional id ('row-' + i), so two unrelated projects' first
# untyped rows collide on "row-0" and a shuttle can advance purely because the old project
# reported a higher count there. Motion with no event behind it in the document being rendered
# is the single invariant this bundle exists to enforce, so the guard is STRUCTURAL: exactly one
# site may mutate selectedSlug, and that site resets. A future author adding a fourth assignment
# reintroduces the bug silently, which is what (l29) is here to stop.
l_sel_assign="$(grep -cE '(^|[^a-zA-Z])selectedSlug[[:space:]]*=[^=]' "$JS")"
l_sel_infn="$(awk '/^  function setSelectedSlug/{f=1} f&&/selectedSlug[[:space:]]*=[^=]/{n++} f&&/^  }/{exit} END{print n+0}' "$JS")"
l_sel_decl="$(grep -cE '^  var selectedSlug = null;$' "$JS")"
if [ "$l_sel_assign" = "$((l_sel_infn + l_sel_decl))" ] && [ "$l_sel_infn" = "1" ] && [ "$l_sel_decl" = "1" ]; then
  ok "(l29) selectedSlug is mutated in exactly ONE place — inside setSelectedSlug, which always resets lane memory (found $l_sel_assign assignment(s): $l_sel_decl declaration + $l_sel_infn in the setter)"
else
  no "(l29) selectedSlug is mutated only inside setSelectedSlug" \
     "found $l_sel_assign total assignment(s), $l_sel_infn in the setter, $l_sel_decl declaration — an assignment outside the setter switches the document without clearing prevEvents/shuttleStep"
fi

# (l30) ANTI-VACUITY. (l29) is a counting assertion, and a counting assertion whose count can
# never move proves nothing. Reintroduce a bare assignment outside the setter — the exact shape
# of the reported defect — and require (l29)'s predicate to break.
l_sel_mut="$TMPROOT/floor-sel-mutant.js"
sed 's|      setSelectedSlug(null);|      selectedSlug = null;|' "$JS" > "$l_sel_mut" 2>/dev/null
if mutant_ok "$JS" "$l_sel_mut"; then
  m_assign="$(grep -cE '(^|[^a-zA-Z])selectedSlug[[:space:]]*=[^=]' "$l_sel_mut")"
  m_infn="$(awk '/^  function setSelectedSlug/{f=1} f&&/selectedSlug[[:space:]]*=[^=]/{n++} f&&/^  }/{exit} END{print n+0}' "$l_sel_mut")"
  m_decl="$(grep -cE '^  var selectedSlug = null;$' "$l_sel_mut")"
  if [ "$m_assign" != "$((m_infn + m_decl))" ]; then
    ok "(l30) ANTI-VACUITY: a bare selectedSlug assignment outside the setter BREAKS (l29)'s predicate ($m_assign total vs $((m_infn + m_decl))) — the count can move, so (l29) is a real gate"
  else
    no "(l30) ANTI-VACUITY: a bare assignment outside the setter breaks (l29)" \
       "the mutant counted $m_assign total and $((m_infn + m_decl)) accounted-for — (l29) would pass with the defect present"
  fi
else
  no "(l30) ANTI-VACUITY fixture: the selectedSlug mutant is unusable" "mutant_ok rejected it"
fi

# ===========================================================================
echo "(m) AC-entrypoint-parity — /setup ui, /ui and the engine name the same verbs"
# ===========================================================================
# WHAT THIS GROUP PROVES. Two commands now drive one engine, and the failure this prevents is
# quiet: the engine gains a subcommand and NEITHER file documents it, so it exists and nobody
# can find it. The predicate is therefore not pairwise equality — the three sets are
# deliberately unequal (`/setup ui` keeps apply/remove, `/ui` adds the registry verbs) — it is
# that the UNION of the two documented sets EQUALS the engine's real set.
#
# THE ENGINE'S SET IS PARSED, NEVER RESTATED HERE. A literal list in this file would be a
# third enumeration that rots on its own, which is the exact defect (z8) exists to prevent one
# document over. Two details of the parse are load-bearing:
#   1. It is PINNED to `case "$SUBCMD" in`. The engine contains several `case` statements
#      (argument parsing, numeric validation, pid filtering); parsing the wrong one silently
#      yields a nonsense verb set and every clause below would then be measuring nothing.
#      (m1) asserts the anchor is unique and (m2) asserts the parsed set is plausible.
#   2. It reads the ARM LABELS. The `*)` arm's error text restates the verb list in prose —
#      a SECOND in-file enumeration that can drift by itself — so reading it would be reading
#      a copy rather than the dispatch. (m10) controls for exactly that.
#
# WHY THE OBVIOUS MUTATION CONTROL IS ABSENT, recorded rather than glossed: deleting one of
# check/apply/serve/stop/remove from commands/ui.md provably does NOT redden, because
# commands/setup.md documents all five and the UNION is unchanged. The two controls used
# instead are (m8) delete a verb documented ONLY in commands/ui.md, and (m9) append an
# undocumented verb to a scratch copy of the engine's dispatch.

for f in "$ENGINE" "$SETUP_MD" "$UI_MD"; do
  [ -r "$f" ] || setup_fail "(m) fixture: $f is not readable, so every assertion below would be vacuous"
done
M_ENG_SIG_BEFORE="$(csum "$ENGINE")"
M_UI_SIG_BEFORE="$(csum "$UI_MD")"

# engine_verbs <engine file> -> the arm labels of the pinned dispatch case, one per line.
engine_verbs() {
  awk '
    $0 == "case \"$SUBCMD\" in" { inb = 1; next }
    inb && $0 == "esac" { inb = 0 }
    inb {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (match(line, /^[a-z][a-z0-9_-]*\)/)) print substr(line, 1, RLENGTH - 1)
    }
  ' "$1"
}
# doc_verbs <md file> <section-start ERE|""> <section-end ERE|""> -> the backticked tokens on
# the section's `subcommands` enumeration line(s). The token filter is shape-based
# (`^[a-z][a-z0-9_-]*$`) and DELIBERATELY does not consult the engine's set: a documented verb
# the engine does not have must be able to fail clauses (i)/(ii) rather than be filtered away.
# It drops the backticked PATHS that share those lines - the engine's own filename, the
# projector's, and the plugin-install-root variable form the command files use - because none
# of them match that shape. (Those path forms are DESCRIBED rather than quoted here on purpose:
# this file deliberately holds no vendor-coupling allowance, and spelling one of them literally
# would put the first entry on it just to write a comment.)
doc_verbs() {
  awk -v s="$2" -v e="$3" '
    BEGIN { inb = (s == "") ? 1 : 0 }
    s != "" && $0 ~ s { inb = 1; next }
    inb && e != "" && $0 ~ e { inb = 0 }
    inb && index($0, "subcommands") > 0 {
      n = split($0, parts, "`")
      for (i = 2; i <= n; i += 2) if (parts[i] ~ /^[a-z][a-z0-9_-]*$/) print parts[i]
    }
  ' "$1"
}
doc_enum_lines() {
  awk -v s="$2" -v e="$3" '
    BEGIN { inb = (s == "") ? 1 : 0; n = 0 }
    s != "" && $0 ~ s { inb = 1; next }
    inb && e != "" && $0 ~ e { inb = 0 }
    inb && index($0, "subcommands") > 0 { n++ }
    END { print n + 0 }
  ' "$1"
}
setify() { tr ' \t' '\n\n' | sed '/^$/d' | LC_ALL=C sort -u | tr '\n' ' '; }
# not_in <candidate set> <reference set> -> members of the candidate absent from the reference
not_in() {
  local v out=""
  for v in $1; do case " $2 " in *" $v "*) ;; *) out="$out $v" ;; esac; done
  printf '%s' "${out# }"
}

m_anchor_n="$(grep -c -F -- 'case "$SUBCMD" in' "$ENGINE" 2>/dev/null || true)"
case "$m_anchor_n" in ''|*[!0-9]*) m_anchor_n=0 ;; esac
if [ "$m_anchor_n" -eq 1 ]; then
  ok "(m1) the dispatch anchor \`case \"\$SUBCMD\" in\` occurs exactly once in setup-ui.sh — the parse is pinned to one of the file's several case statements"
else
  no "(m1) the dispatch anchor occurs exactly once in setup-ui.sh" \
     "found $m_anchor_n — a second anchor would make the parsed verb set ambiguous and every clause below unreliable"
fi

M_ENGINE_SET="$(engine_verbs "$ENGINE" | setify)"
M_SETUP_SET="$(doc_verbs "$SETUP_MD" '^## Module: ui$' '^## ' | setify)"
M_UI_SET="$(doc_verbs "$UI_MD" '' '' | setify)"

# (m2) PREMISE: the parsed engine set is plausible. Without this, a parse that silently
# returned nothing would make (m4)/(m5) pass vacuously (every member of a set is in it).
m2_missing="$(not_in "check apply serve stop remove" "$M_ENGINE_SET")"
m2_n="$(printf '%s' "$M_ENGINE_SET" | wc -w | tr -d ' ')"
if [ -z "$m2_missing" ] && [ "$m2_n" -ge 5 ]; then
  ok "(m2) the parsed engine verb set is plausible ($m2_n verbs, including all five module verbs): $M_ENGINE_SET"
else
  no "(m2) the parsed engine verb set is plausible" \
     "parsed '$M_ENGINE_SET' ($m2_n verbs); missing from it: '$m2_missing' — the wrong case statement was almost certainly read"
fi

# (m3) PREMISE: each document carries EXACTLY ONE enumeration line and it yields verbs. A
# second enumeration in either file is a loud failure rather than a silently merged basis.
m3_setup_lines="$(doc_enum_lines "$SETUP_MD" '^## Module: ui$' '^## ')"
m3_ui_lines="$(doc_enum_lines "$UI_MD" '' '')"
if [ "$m3_setup_lines" = "1" ] && [ "$m3_ui_lines" = "1" ] && [ -n "$M_SETUP_SET" ] && [ -n "$M_UI_SET" ]; then
  ok "(m3) each command file carries exactly one verb enumeration and both parse non-empty — setup.md: $M_SETUP_SET| ui.md: $M_UI_SET"
else
  no "(m3) each command file carries exactly one verb enumeration and both parse non-empty" \
     "setup.md lines=$m3_setup_lines set='$M_SETUP_SET'; ui.md lines=$m3_ui_lines set='$M_UI_SET'"
fi

# (m4) CLAUSE (i)
m4_extra="$(not_in "$M_SETUP_SET" "$M_ENGINE_SET")"
if [ -z "$m4_extra" ]; then
  ok "(m4) clause (i): every verb documented in commands/setup.md's '## Module: ui' flow exists in the engine's dispatch"
else
  no "(m4) clause (i): every verb documented in commands/setup.md's '## Module: ui' flow exists in the engine" \
     "documented but not dispatched: $m4_extra"
fi

# (m5) CLAUSE (ii)
m5_extra="$(not_in "$M_UI_SET" "$M_ENGINE_SET")"
if [ -z "$m5_extra" ]; then
  ok "(m5) clause (ii): every verb documented in commands/ui.md exists in the engine's dispatch"
else
  no "(m5) clause (ii): every verb documented in commands/ui.md exists in the engine" \
     "documented but not dispatched: $m5_extra"
fi

# (m6) CLAUSE (iii) — the union, which is the clause the two controls exercise.
M_UNION="$(printf '%s %s' "$M_SETUP_SET" "$M_UI_SET" | setify)"
if [ "$M_UNION" = "$M_ENGINE_SET" ]; then
  ok "(m6) clause (iii): the UNION of the two documented sets equals the engine's dispatch set ($M_ENGINE_SET)"
else
  no "(m6) clause (iii): the UNION of the two documented sets equals the engine's dispatch set" \
     "union='$M_UNION' engine='$M_ENGINE_SET'; undocumented by either file: '$(not_in "$M_ENGINE_SET" "$M_UNION")'"
fi

# (m7) the enumeration is a FAITHFUL PROXY for "documented" in commands/ui.md: every verb it
# lists has a `### \`verb\`` section, and every such section is listed. Without this, the
# enumeration line could drift away from the sections it summarises and the clauses above
# would be measuring a sentence rather than the document.
M_UI_SECTIONS="$(sed -n 's/^### `\([a-z][a-z0-9_-]*\)`.*$/\1/p' "$UI_MD" | setify)"
if [ "$M_UI_SECTIONS" = "$M_UI_SET" ]; then
  ok "(m7) commands/ui.md's verb enumeration and its per-verb '###' sections name the same verbs ($M_UI_SET)"
else
  no "(m7) commands/ui.md's verb enumeration and its per-verb sections name the same verbs" \
     "enumeration='$M_UI_SET' sections='$M_UI_SECTIONS'"
fi

# --- (m8) CONTROL c1: a verb documented ONLY in commands/ui.md is deleted ----------------
m_c1="$TMPROOT/ui.md.c1.mut"
awk 'index($0,"subcommands")>0 { gsub(/ \/ `forget`/, "") } { print }' "$UI_MD" > "$m_c1" 2>/dev/null
if mutant_ok "$UI_MD" "$m_c1"; then
  m_c1_set="$(doc_verbs "$m_c1" '' '' | setify)"
  m_c1_union="$(printf '%s %s' "$M_SETUP_SET" "$m_c1_set" | setify)"
  if [ "$m_c1_union" != "$M_ENGINE_SET" ]; then
    ok "(m8) CONTROL c1: dropping \`forget\` — documented ONLY in commands/ui.md — reddens clause (iii) (union='$m_c1_union')"
  else
    no "(m8) CONTROL c1: dropping a ui.md-only verb must redden clause (iii)" \
       "the union still equals the engine set, so (m6) cannot detect a doc-side drop and is vacuous"
  fi
fi

# --- (m9) CONTROL c2: the engine gains a verb nobody documents ---------------------------
# The engine-side drift, which otherwise has NO control at all. The mutant is a scratch copy
# in the temp tree; the shipped engine is never written (m11 proves it by hash).
m_c2="$TMPROOT/setup-ui.c2.mut.sh"
awk '$0 == "case \"$SUBCMD\" in" { print; print "  purge)  do_check ;;"; next } { print }' "$ENGINE" > "$m_c2" 2>/dev/null
if mutant_ok "$ENGINE" "$m_c2" shell; then
  m_c2_set="$(engine_verbs "$m_c2" | setify)"
  case " $m_c2_set " in
    *" purge "*)
      if [ "$M_UNION" != "$m_c2_set" ]; then
        ok "(m9) CONTROL c2: a verb appended to the engine's dispatch and documented nowhere reddens clause (iii) (engine set gained 'purge')"
      else
        no "(m9) CONTROL c2: an undocumented engine verb must redden clause (iii)" \
           "the union still equals the mutated engine set ('$m_c2_set'), so engine-side drift is invisible"
      fi ;;
    *)
      no "(m9) CONTROL c2 is well-formed" "the mutant's parsed set '$m_c2_set' does not contain the injected verb, so the control proves nothing" ;;
  esac
fi

# --- (m10) CONTROL c3: the parse reads ARM LABELS, not the *) arm's error string ----------
# The `*)` arm restates the verb list in prose. A parser that read THAT would be reading a
# second enumeration which can drift on its own — so a mutant that drifts ONLY the error
# string must leave the parsed set completely unchanged.
m_c3="$TMPROOT/setup-ui.c3.mut.sh"
awk '{ gsub(/expected check \| apply/, "expected purge | check | apply"); print }' "$ENGINE" > "$m_c3" 2>/dev/null
if mutant_ok "$ENGINE" "$m_c3" shell; then
  m_c3_set="$(engine_verbs "$m_c3" | setify)"
  if [ "$m_c3_set" = "$M_ENGINE_SET" ]; then
    ok "(m10) CONTROL c3: drifting the \`*)\` arm's error string leaves the parsed set unchanged — the parse reads arm labels, not that second enumeration"
  else
    no "(m10) CONTROL c3: the parse must read arm labels, not the \`*)\` arm's error string" \
       "the error-string mutant changed the parsed set: '$m_c3_set' vs '$M_ENGINE_SET'"
  fi
fi

# --- (m11) the shipped files are untouched by every (m) mutant ---------------------------
m_eng_after="$(csum "$ENGINE")"; m_ui_after="$(csum "$UI_MD")"
m_residue="$(ls "$script_dir"/*.mut.sh "$script_dir"/../commands/*.mut* 2>/dev/null || true)"
if [ "$M_ENG_SIG_BEFORE" = "$m_eng_after" ] && [ "$M_UI_SIG_BEFORE" = "$m_ui_after" ] && [ -z "$m_residue" ]; then
  ok "(m11) setup-ui.sh and commands/ui.md are byte-identical after every (m) mutation control (sha256 unchanged) and no mutant was left in the plugin's own directories"
else
  no "(m11) setup-ui.sh and commands/ui.md are byte-identical after the (m) mutation controls" \
     "engine before='$M_ENG_SIG_BEFORE' after='$m_eng_after'; ui.md before='$M_UI_SIG_BEFORE' after='$m_ui_after'; residue='$m_residue'"
fi

# ===========================================================================
echo "(n) AC-guarded-writes — four endpoints, a four-part guard, and a control per part"
# ---------------------------------------------------------------------------
# WHAT THIS GROUP IS FOR. Item 04 justified having no authentication with "there is nothing to
# authenticate against on loopback". That was sound for a page that could only render, and it
# stopped being sound the moment a write existed: a loopback port is NOT a security boundary in
# a browser. Any site open in another tab can `fetch` a POST at 127.0.0.1:<port> — the attacker
# never reads the response, but the write has already landed — and DNS rebinding extends the
# same reach to a remote origin.
#
# THE FOUR CONTROLS AT THE END ARE THE POINT OF THE GROUP. A four-part guard is exactly where a
# vacuous assertion hides: every refusal below would also be produced by a server that refused
# EVERYTHING, and every acceptance by one that checked NOTHING. So each part is disabled ALONE,
# in a mutant that must first pass `mutant_ok`, and the previously-refused request is watched
# SUCCEEDING. Without those four, this group could not tell a working guard from a guard that
# never fires.
#
# Every request below goes through n_req, which speaks http.client rather than curl: curl is not
# guaranteed on the plugin's CI image and python3 already is (the suite refuses to start
# without it). n_req prints "<status><TAB><body>", and "0" is a status this suite never gets
# from a live server, so a connection failure can never be mistaken for a refusal.

# n_req <port> <method> <path> <token> <origin> <host> <body> <token-header-name>
# Every argument is positional and REQUIRED (pass "" to omit one), because an optional argument
# that silently defaults is how a test ends up asserting against a request it did not send.
n_req() {
  python3 - "$@" 2>/dev/null <<'__PY_REQ__'
import sys
import http.client

port, method, path, token, origin, host, body, hdrname = sys.argv[1:9]
try:
    conn = http.client.HTTPConnection("127.0.0.1", int(port), timeout=15)
    headers = {}
    if token:
        headers[hdrname or "X-Floor-Token"] = token
    if origin:
        headers["Origin"] = origin
    if host:
        headers["Host"] = host
    if body:
        headers["Content-Type"] = "application/json"
    conn.request(method, path, body=(body if body else None), headers=headers)
    resp = conn.getresponse()
    data = resp.read().decode("utf-8", "replace")
    sys.stdout.write(str(resp.status) + "\t" + data.replace("\n", " "))
except Exception as exc:
    sys.stdout.write("0\t" + type(exc).__name__ + ": " + str(exc))
__PY_REQ__
}
n_status() { printf '%s' "$1" | awk -F'\t' '{print $1; exit}'; }
n_body()   { printf '%s' "$1" | awk -F'\t' '{print $2; exit}'; }

n_free_port() {
  python3 -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()' 2>/dev/null
}
# n_wait_up <port> — a bounded poll, never a fixed sleep and never `timeout` (which stock macOS
# does not ship). "Dispatched" is not "listening", and asserting on a socket that has not been
# accepted yet is the race that makes a suite flaky rather than wrong.
n_wait_up() {
  local i=0 st
  while [ "$i" -lt 60 ]; do
    st="$(n_status "$(n_req "$1" GET / "" "" "" "" "")")"
    [ "$st" = "200" ] && return 0
    i=$((i + 1)); sleep 0.1
  done
  return 1
}
n_wait_down() {
  local i=0 st
  while [ "$i" -lt 60 ]; do
    st="$(n_status "$(n_req "$1" GET / "" "" "" "" "")")"
    [ "$st" = "0" ] && return 0
    i=$((i + 1)); sleep 0.1
  done
  return 1
}
n_token_of() { printf '%s' "$1" | sed -n 's|.*#token=\([A-Za-z0-9_-][A-Za-z0-9_-]*\).*|\1|p' | head -1; }

# ---- the fixture: a private HOME, because the permitted root IS $HOME ---------------------
# The engine confines every page-supplied path to the home directory of the serve that received
# it. A fixture HOME is therefore not merely isolation hygiene here (though it is that too, and
# (k26) requires it): it is what makes the confinement assertions testable at all without
# naming a real directory of the developer's.
N="$(mktmp)"
# Captured before any (n) mutant exists, so (n28) can prove the plugin's own engine was never
# the thing being mutated.
N_ENG_SIG_BEFORE="$(csum "$ENGINE")"
# The ui directory deliberately does NOT mirror the engine's real default path here, and this
# comment deliberately does not spell that path either — the ratchet is a literal `grep -oF`,
# so a PROSE mention of it counts exactly as much as a code one, which is a thing this file
# learned by tripping the gate with the sentence that was here before:
# this suite is CORE at allowance 0 in the vendor-coupling manifest, and spelling that path
# would be a vendor reference the ratchet counts. `--ui-dir` makes the location irrelevant to
# every assertion below, and the permitted root is $HOME, which is what NHOME is for.
NHOME="$N/home"; NUI="$N/ui"; NREG="$N/projects.json"
NPROJ="$NHOME/work/demo-project"; NOTHER="$NHOME/work/second-project"
mkdir -p "$NPROJ/.git" "$NOTHER/.git" || setup_fail "(n) fixture: could not create the fixture project tree"
printf 'a\n' > "$NPROJ/file.txt" || setup_fail "(n) fixture: could not seed the fixture project"
bash "$ENGINE" apply --ui-dir "$NUI" >/dev/null 2>&1
[ -f "$NUI/index.html" ] || setup_fail "(n) fixture: apply did not install the bundle into $NUI"
cp "$LIVE" "$NUI/floor.json" || setup_fail "(n) fixture: could not stage floor.json into $NUI"

nport="$(n_free_port)"
case "$nport" in ''|*[!0-9]*) setup_fail "(n) fixture: could not obtain a free port" ;; esac

# A FIRST serve run, started and stopped, exists ONLY to mint a token that will be stale by the
# time (n8) presents it. A "previous run's token" cannot be simulated by inventing a string —
# an invented one is merely a WRONG token, which is a different claim.
nstale_port="$(n_free_port)"
case "$nstale_port" in ''|*[!0-9]*) setup_fail "(n) fixture: could not obtain a second free port" ;; esac
n_prev_out="$( cd "$NPROJ" && HOME="$NHOME" bash "$ENGINE" serve --registry "$NREG" --ui-dir "$NUI" --no-regen --detach --port "$nstale_port" 2>&1 )"
SERVE_PIDFILES="$SERVE_PIDFILES $NUI/serve.pid"
NSTALE_TOKEN="$(n_token_of "$n_prev_out")"
[ -n "$NSTALE_TOKEN" ] || setup_fail "(n) fixture: the first serve run printed no #token= to go stale"
n_wait_up "$nstale_port" >/dev/null 2>&1
bash "$ENGINE" stop --ui-dir "$NUI" >/dev/null 2>&1
n_wait_down "$nstale_port" >/dev/null 2>&1

# THE RUN EVERY ASSERTION BELOW TALKS TO.
n_out="$( cd "$NPROJ" && HOME="$NHOME" bash "$ENGINE" serve --registry "$NREG" --ui-dir "$NUI" --no-regen --detach --port "$nport" 2>&1 )"; n_rc=$?
SERVE_PIDFILES="$SERVE_PIDFILES $NUI/serve.pid"
NTOKEN="$(n_token_of "$n_out")"
[ "$n_rc" -eq 0 ] || setup_fail "(n) fixture: serve exited $n_rc :: $n_out"
[ -n "$NTOKEN" ] || setup_fail "(n) fixture: serve printed no #token= URL :: $n_out"
[ "$NTOKEN" != "$NSTALE_TOKEN" ] || setup_fail "(n) fixture: two serve runs minted the SAME token — the per-run claim is false and (n8) could not test it"
n_wait_up "$nport" || setup_fail "(n) fixture: the new handler never answered a GET on 127.0.0.1:$nport"

NORIGIN="http://127.0.0.1:$nport"
nreg_sig() { [ -f "$NREG" ] && csum "$NREG" || printf 'ABSENT'; }

# --- (n1) AC1: GET IS BYTE-FOR-BYTE WHAT THE STATIC SERVER ANSWERED ------------------------
# Not "looks right" and not "still 200": the SAME bytes, captured from BOTH servers in the same
# run, over the same directory. `python3 -m http.server` is started here for exactly this
# comparison — it is the thing being replaced, and it is the only honest reference for the
# claim that replacing it changed nothing on the read path.
nold_port="$(n_free_port)"
case "$nold_port" in ''|*[!0-9]*) setup_fail "(n1) fixture: could not obtain a port for the reference server" ;; esac
python3 -m http.server --bind 127.0.0.1 --directory "$NUI" "$nold_port" >/dev/null 2>&1 &
n_old_pid=$!
HOLDER_PIDS="$HOLDER_PIDS $n_old_pid"
if ! n_wait_up "$nold_port"; then
  no "(n1) every GET the static server answered is answered byte-for-byte by the new handler" "the reference python3 -m http.server never came up on $nold_port"
  no "(n2) an unrouted write still answers 501, exactly as the static server did" "no reference server"
else
  n_diff=""
  for ndoc in /index.html /floor.css /floor.js /index.json /floor.json; do
    n_new="$(n_req "$nport" GET "$ndoc" "" "" "" "" "")"
    n_ref="$(n_req "$nold_port" GET "$ndoc" "" "" "" "" "")"
    [ "$n_new" = "$n_ref" ] || n_diff="$n_diff [$ndoc: new='$(n_status "$n_new")' ref='$(n_status "$n_ref")' bodies $( [ "$(n_body "$n_new")" = "$(n_body "$n_ref")" ] && echo match || echo DIFFER )]"
  done
  [ -z "$n_diff" ] \
    && ok "(n1) AC1: index.html, floor.css, floor.js, index.json and floor.json come back with the same status AND the same bytes from the new handler as from python3 -m http.server over the same directory" \
    || no "(n1) AC1: every GET is byte-identical to the static server's answer" "$n_diff"
  # --- (n2) AC1: the unrouted write answers what it always answered -----------------------
  n_bad=""
  for npair in "PUT /" "POST /floor.json" "PATCH /index.json"; do
    nm="${npair%% *}"; np="${npair##* }"
    n_new="$(n_status "$(n_req "$nport" "$nm" "$np" "" "" "" "" "")")"
    n_ref="$(n_status "$(n_req "$nold_port" "$nm" "$np" "" "" "" "" "")")"
    [ "$n_new" = "501" ] && [ "$n_ref" = "501" ] || n_bad="$n_bad [$npair: new=$n_new ref=$n_ref]"
  done
  [ -z "$n_bad" ] \
    && ok "(n2) AC1: an unrouted write (PUT /, POST /floor.json, PATCH /index.json) still answers 501 — the same status the static file server answered, verified against it in this run" \
    || no "(n2) AC1: an unrouted write still answers 501" "$n_bad"
fi
kill "$n_old_pid" 2>/dev/null

# --- (n3) AC2: NO TOKEN -> 403 ON ALL FOUR, AND THE REGISTRY IS UNTOUCHED ------------------
# Hashed before and after each call, per endpoint, because "the write was refused" and "the
# write happened and was then undone" produce the same final list and different histories.
n_bad=""
for nact in add forget scan stop; do
  nsig="$(nreg_sig)"
  nres="$(n_req "$nport" POST "/api/$nact" "" "$NORIGIN" "" '{"path":"'"$NPROJ"'","slug":"demo-project"}' "")"
  nst="$(n_status "$nres")"
  [ "$nst" = "403" ] || n_bad="$n_bad [$nact: status $nst, expected 403]"
  case "$(n_body "$nres")" in *token-missing-or-wrong*) ;; *) n_bad="$n_bad [$nact: the refusal does not name the token part: $(n_body "$nres")]" ;; esac
  [ "$(nreg_sig)" = "$nsig" ] || n_bad="$n_bad [$nact: THE REGISTRY CHANGED across a refused request]"
done
[ -z "$n_bad" ] \
  && ok "(n3) AC2: add, forget, scan and stop each answer 403 with no token, each names the token as the reason, and the registry is byte-identical across every one of the four" \
  || no "(n3) AC2: a mutating request with no token is refused and writes nothing" "$n_bad"

# --- (n4) AC2/AC12: the server is still alive after all that, and still serving ------------
[ "$(n_status "$(n_req "$nport" GET /index.json "" "" "" "" "")")" = "200" ] \
  && ok "(n4) AC12: four refused writes later the handler is still serving — a refusal is a refusal, never a crash" \
  || no "(n4) AC12: the handler survives a refused write" "GET /index.json no longer answers 200"

# --- (n5) AC13 PRECONDITION / R8: a FULLY VALID request must SUCCEED ----------------------
# Every refusal above is also what a server that refused everything would produce. This is the
# positive control that makes the whole group non-vacuous, and it is asserted BEFORE the
# stale-token case so that case cannot pass for the wrong reason.
nsig="$(nreg_sig)"
n_ok_res="$(n_req "$nport" POST /api/add "$NTOKEN" "$NORIGIN" "" '{"path":"'"$NPROJ"'"}' "")"
n_ok_st="$(n_status "$n_ok_res")"
n_registered="$(jq -r '[.projects[] | select(.path | endswith("demo-project"))] | length' "$NREG" 2>/dev/null)"
case "$n_registered" in ''|*[!0-9]*) n_registered=0 ;; esac
[ "$n_ok_st" = "200" ] && [ "$n_registered" -eq 1 ] && [ "$(nreg_sig)" != "$nsig" ] \
  && ok "(n5) POSITIVE CONTROL: a request carrying this run's token, the custom header, a loopback Origin and a loopback Host is ACCEPTED and really registers the project — so every refusal in this group is discriminating, not blanket" \
  || no "(n5) POSITIVE CONTROL: a fully valid mutating request succeeds" "status=$n_ok_st registered=$n_registered :: $(n_body "$n_ok_res")"

# --- (n6) AC7: a legitimate absolute path DISCRIMINATES from the refusals below ------------
nsig="$(nreg_sig)"
n_res="$(n_req "$nport" POST /api/add "$NTOKEN" "$NORIGIN" "" '{"path":"'"$NOTHER"'"}' "")"
n_second="$(jq -r '[.projects[] | select(.path | endswith("second-project"))] | length' "$NREG" 2>/dev/null)"
case "$n_second" in ''|*[!0-9]*) n_second=0 ;; esac
[ "$(n_status "$n_res")" = "200" ] && [ "$n_second" -eq 1 ] \
  && ok "(n6) AC7: a legitimate absolute path to a real directory inside the permitted root is REGISTERED — the confinement check discriminates rather than blanket-refusing" \
  || no "(n6) AC7: a legitimate absolute path succeeds" "status=$(n_status "$n_res") registered=$n_second :: $(n_body "$n_res")"

# --- (n7) AC3: a WRONG token is refused ---------------------------------------------------
nsig="$(nreg_sig)"
n_res="$(n_req "$nport" POST /api/add "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" "$NORIGIN" "" '{"path":"'"$NPROJ"'"}' "")"
[ "$(n_status "$n_res")" = "403" ] && [ "$(nreg_sig)" = "$nsig" ] \
  && ok "(n7) AC3: a syntactically valid but WRONG token is refused and the registry is byte-identical" \
  || no "(n7) AC3: a wrong token is refused" "status=$(n_status "$n_res") :: $(n_body "$n_res")"

# --- (n8) AC3: a token from a PREVIOUS serve run is refused — the token is PER-RUN ---------
nsig="$(nreg_sig)"
n_res="$(n_req "$nport" POST /api/add "$NSTALE_TOKEN" "$NORIGIN" "" '{"path":"'"$NPROJ"'"}' "")"
[ "$(n_status "$n_res")" = "403" ] && [ "$(nreg_sig)" = "$nsig" ] \
  && ok "(n8) AC3: a token minted by a PREVIOUS serve run — captured from that run's own printed URL, not invented — is refused by this one, and (n5) already proved this server accepts its own; so the token is per-run and dies with the process" \
  || no "(n8) AC3: a previous run's token is refused" "status=$(n_status "$n_res") :: $(n_body "$n_res")"

# --- (n9) AC4: a foreign Origin, and NO Origin at all, are both refused --------------------
n_bad=""
for norg in "http://evil.example.test" "https://attacker.example.com:8443" "null" ""; do
  nsig="$(nreg_sig)"
  n_res="$(n_req "$nport" POST /api/add "$NTOKEN" "$norg" "" '{"path":"'"$NPROJ"'"}' "")"
  [ "$(n_status "$n_res")" = "403" ] || n_bad="$n_bad [Origin='${norg:-<absent>}': status $(n_status "$n_res")]"
  case "$(n_body "$n_res")" in *origin-not-this-server*) ;; *) n_bad="$n_bad [Origin='${norg:-<absent>}': refusal does not name the Origin part]" ;; esac
  [ "$(nreg_sig)" = "$nsig" ] || n_bad="$n_bad [Origin='${norg:-<absent>}': THE REGISTRY CHANGED]"
done
[ -z "$n_bad" ] \
  && ok "(n9) AC4: a foreign Origin, an https one, the literal 'null' Origin a sandboxed frame sends, and NO Origin at all are each refused by name with the registry unchanged" \
  || no "(n9) AC4: a cross-origin mutating request is refused" "$n_bad"

# --- (n10) AC5: a non-loopback Host is refused (the DNS-rebinding case) --------------------
n_bad=""
for nhost in "evil.example.com" "evil.example.com:$nport" "192.168.1.10:$nport" "127.0.0.1.nip.io:$nport"; do
  nsig="$(nreg_sig)"
  n_res="$(n_req "$nport" POST /api/add "$NTOKEN" "$NORIGIN" "$nhost" '{"path":"'"$NPROJ"'"}' "")"
  [ "$(n_status "$n_res")" = "403" ] || n_bad="$n_bad [Host=$nhost: status $(n_status "$n_res")]"
  case "$(n_body "$n_res")" in *host-not-loopback*) ;; *) n_bad="$n_bad [Host=$nhost: refusal does not name the Host part]" ;; esac
  [ "$(nreg_sig)" = "$nsig" ] || n_bad="$n_bad [Host=$nhost: THE REGISTRY CHANGED]"
done
[ -z "$n_bad" ] \
  && ok "(n10) AC5: a forged Host sent to the loopback socket is refused by name — including a rebinding-style name that RESOLVES to 127.0.0.1, which an Origin check alone cannot catch" \
  || no "(n10) AC5: a non-loopback Host is refused" "$n_bad"

# --- (n11) AC5: all six accepted loopback Host spellings really are accepted ---------------
# The refusals above would also be produced by a server that refused every Host it was given.
# `scan` without --confirm is the probe because it writes nothing, so this stays a pure
# read of the guard's decision.
n_bad=""
for nhost in "127.0.0.1" "127.0.0.1:$nport" "localhost" "localhost:$nport" "[::1]" "[::1]:$nport"; do
  n_res="$(n_req "$nport" POST /api/scan "$NTOKEN" "$NORIGIN" "$nhost" '{"path":"'"$NPROJ"'","confirm":false}' "")"
  [ "$(n_status "$n_res")" = "200" ] || n_bad="$n_bad [Host=$nhost: status $(n_status "$n_res") :: $(n_body "$n_res")]"
done
[ -z "$n_bad" ] \
  && ok "(n11) AC5: 127.0.0.1, localhost and [::1] are each accepted with and without the :$nport suffix — all six spellings, so (n10) is refusing foreign names rather than refusing everything" \
  || no "(n11) AC5: the six loopback Host spellings are accepted" "$n_bad"

# --- (n12) AC7: untrusted paths are refused with a NAMED reason and register nothing -------
ln -sfn /etc "$NHOME/escape-link" 2>/dev/null
printf 'x\n' > "$NHOME/not-a-directory" 2>/dev/null
n_bad=""
n_case() {
  local label="$1" path="$2" want="$3" sig res
  sig="$(nreg_sig)"
  res="$(n_req "$nport" POST /api/add "$NTOKEN" "$NORIGIN" "" '{"path":"'"$path"'"}' "")"
  case "$(n_status "$res")" in 400) ;; *) n_bad="$n_bad [$label: status $(n_status "$res"), expected 400]" ;; esac
  case "$(n_body "$res")" in *"$want"*) ;; *) n_bad="$n_bad [$label: expected the named reason '$want', got: $(n_body "$res")]" ;; esac
  [ "$(nreg_sig)" = "$sig" ] || n_bad="$n_bad [$label: THE REGISTRY CHANGED across a refused path]"
}
n_case "traversal sequence"       "$NHOME/../../etc"      "path-traversal"
n_case "relative traversal"       "../../etc"             "path-not-absolute"
n_case "not a directory"          "$NHOME/not-a-directory" "path-not-a-directory"
n_case "symlink escaping the root" "$NHOME/escape-link"    "path-outside-permitted-root"
n_case "a real directory outside the root" "/etc"          "path-outside-permitted-root"
[ -z "$n_bad" ] \
  && ok "(n12) AC7: a traversal sequence, a bare relative path, a non-directory, a symlink resolving outside the permitted root and a real directory outside it are each refused with their OWN named reason and register nothing" \
  || no "(n12) AC7: add rejects untrusted paths by name and registers nothing" "$n_bad"

# --- (n13) AC7: a malformed slug cannot reach `forget` -------------------------------------
nsig="$(nreg_sig)"
n_res="$(n_req "$nport" POST /api/forget "$NTOKEN" "$NORIGIN" "" '{"slug":"../../x"}' "")"
[ "$(n_status "$n_res")" = "400" ] && [ "$(nreg_sig)" = "$nsig" ] \
  && case "$(n_body "$n_res")" in *slug-malformed*) true ;; *) false ;; esac \
  && ok "(n13) AC7: a slug carrying a traversal sequence is refused by name before it reaches the engine — a slug is a filesystem path component and one arriving from a browser is untrusted input" \
  || no "(n13) AC7: a malformed slug is refused by name" "status=$(n_status "$n_res") :: $(n_body "$n_res")"

# --- (n14)/(n15) AC8: scan PROPOSES and does not write; only --confirm registers -----------
bash "$ENGINE" forget second-project --ui-dir "$NUI" --registry "$NREG" >/dev/null 2>&1
bash "$ENGINE" forget demo-project --ui-dir "$NUI" --registry "$NREG" >/dev/null 2>&1
nsig="$(nreg_sig)"
n_res="$(n_req "$nport" POST /api/scan "$NTOKEN" "$NORIGIN" "" '{"path":"'"$NHOME/work"'","confirm":false}' "")"
n_body_txt="$(n_body "$n_res")"
[ "$(n_status "$n_res")" = "200" ] && [ "$(nreg_sig)" = "$nsig" ] \
  && case "$n_body_txt" in *"PROPOSAL"*) true ;; *) false ;; esac \
  && ok "(n14) AC8: scan from the page lists its candidates as a PROPOSAL and the registry is byte-identical afterwards — the same --confirm contract the command has, because the endpoint runs the command" \
  || no "(n14) AC8: an unconfirmed scan proposes and writes nothing" "status=$(n_status "$n_res") registry-changed=$( [ "$(nreg_sig)" = "$nsig" ] && echo no || echo YES ) :: $n_body_txt"
n_res="$(n_req "$nport" POST /api/scan "$NTOKEN" "$NORIGIN" "" '{"path":"'"$NHOME/work"'","confirm":true}' "")"
n_after="$(jq -r '.projects | length' "$NREG" 2>/dev/null)"
case "$n_after" in ''|*[!0-9]*) n_after=0 ;; esac
[ "$(n_status "$n_res")" = "200" ] && [ "$n_after" -eq 2 ] \
  && ok "(n15) AC8: only the explicitly CONFIRMING request registers anything — it registered the $n_after candidates the proposal named" \
  || no "(n15) AC8: a confirming scan registers the proposed candidates" "status=$(n_status "$n_res") projects=$n_after :: $(n_body "$n_res")"

# --- (n16) AC9: forget removes a registry entry and NOTHING else ---------------------------
n_tree_before="$(tree_sig "$NPROJ")"
n_res="$(n_req "$nport" POST /api/forget "$NTOKEN" "$NORIGIN" "" '{"slug":"demo-project"}' "")"
n_tree_after="$(tree_sig "$NPROJ")"
n_left="$(jq -r '[.projects[] | select(.slug == "demo-project")] | length' "$NREG" 2>/dev/null)"
case "$n_left" in ''|*[!0-9]*) n_left=9 ;; esac
[ "$(n_status "$n_res")" = "200" ] && [ "$n_left" -eq 0 ] && [ "$n_tree_before" = "$n_tree_after" ] \
  && ok "(n16) AC9: forget from the page dropped the registry entry and the project directory is byte-identical — hashed whole, before and after, not reasoned about" \
  || no "(n16) AC9: forget removes only a registry entry" "status=$(n_status "$n_res") remaining=$n_left tree-changed=$( [ "$n_tree_before" = "$n_tree_after" ] && echo no || echo YES )"

# --- (n17) AC6: THE TOKEN APPEARS NOWHERE IT COULD LEAK ------------------------------------
# (a) the served bytes of every document the page can fetch, read back OFF THE WIRE rather than
# off disk, because the claim is about what a browser receives; (b) every file the module
# writes anywhere under the ui directory, and the registry beside it; (c) the server's own
# stdout and stderr, which is why `serve.log` exists at all — it used to be /dev/null, and a
# claim about a stream nothing captures is unfalsifiable.
n_leak=""
for ndoc in / /index.html /floor.css /floor.js /index.json /floor.json; do
  case "$(n_body "$(n_req "$nport" GET "$ndoc" "" "" "" "" "")")" in
    *"$NTOKEN"*) n_leak="$n_leak [served $ndoc]" ;;
  esac
done
while IFS= read -r nf; do
  [ -f "$nf" ] || continue
  c="$(grep -c -F -- "$NTOKEN" "$nf" 2>/dev/null || true)"
  case "$c" in ''|*[!0-9]*) c=0 ;; esac
  [ "$c" -gt 0 ] && n_leak="$n_leak [file $nf]"
done <<EOF
$(find "$NUI" -type f 2>/dev/null; printf '%s\n' "$NREG")
EOF
[ -f "$NUI/$(sed -n 's/^SERVE_LOG="\([^"]*\)".*$/\1/p' "$ENGINE" | head -1)" ] \
  || n_leak="$n_leak [there is no serve log, so claim (c) could not be tested at all]"
[ -z "$n_leak" ] \
  && ok "(n17) AC6: this run's token appears in NONE of the served documents, none of the files under the ui directory, the registry, or the server's own captured stdout/stderr — the single place a human sees it is the URL serve printed" \
  || no "(n17) AC6: the token never appears where it could leak" "$n_leak"

# --- (n18) AC6 ANTI-VACUITY: the leak scan can actually find a token -----------------------
# Without this, (n17) passes just as happily against a token that is the empty string or a
# grep that never runs.
n_canary="$TMPROOT/n-canary.txt"
printf 'prefix %s suffix\n' "$NTOKEN" > "$n_canary" 2>/dev/null
n_canary_hits="$(grep -c -F -- "$NTOKEN" "$n_canary" 2>/dev/null || true)"
case "$n_canary_hits" in ''|*[!0-9]*) n_canary_hits=0 ;; esac
[ "${#NTOKEN}" -ge 20 ] && [ "$n_canary_hits" -ge 1 ] \
  && ok "(n18) ANTI-VACUITY: the token is ${#NTOKEN} characters long and the same grep (n17) uses finds it in a planted file — so (n17)'s clean result is a measurement, not an empty needle" \
  || no "(n18) ANTI-VACUITY: (n17)'s leak scan can find a planted token" "token length ${#NTOKEN}, canary hits $n_canary_hits"

# --- (n19) AC12: a bad request is refused, names a reason, and does not take the server down
n_bad=""
n_res="$(n_req "$nport" POST /api/add "$NTOKEN" "$NORIGIN" "" 'this is not json at all' "")"
case "$(n_status "$n_res")" in 400) ;; *) n_bad="$n_bad [malformed body: status $(n_status "$n_res")]" ;; esac
n_res="$(n_req "$nport" POST /api/nonesuch "$NTOKEN" "$NORIGIN" "" '{}' "")"
case "$(n_status "$n_res")" in 501) ;; *) n_bad="$n_bad [unknown route: status $(n_status "$n_res"), expected 501]" ;; esac
n_res="$(n_req "$nport" POST /api/add "$NTOKEN" "$NORIGIN" "" '{"path":12345}' "")"
case "$(n_status "$n_res")" in 400) ;; *) n_bad="$n_bad [non-string path: status $(n_status "$n_res")]" ;; esac
[ "$(n_status "$(n_req "$nport" GET /index.json "" "" "" "" "")")" = "200" ] || n_bad="$n_bad [the handler stopped serving after the bad requests]"
[ -z "$n_bad" ] \
  && ok "(n19) AC12: a malformed body, an unknown route and a non-string path are each refused with a named reason, and the handler is still serving afterwards — refuse-and-name, never a crash and never a non-zero exit" \
  || no "(n19) AC12: every bad-request path refuses safely" "$n_bad"

# --- (n20)/(n21) AC11: the page's stop really kills THIS server, and reports it as stopped --
# R1 IN FULL. `do_stop` kills only a pid whose command line names `http.server` or
# `setup-ui.sh`. Replacing the static server changed that command line, so the regression this
# case exists for is a `stop` that reports "0 process(es) stopped" while the server keeps
# running — silently, because nothing else would notice.
n_res="$(n_req "$nport" POST /api/stop "$NTOKEN" "$NORIGIN" "" '{}' "")"
n_stop_st="$(n_status "$n_res")"
n_down=no; n_wait_down "$nport" && n_down=yes
[ "$n_stop_st" = "200" ] && [ "$n_down" = "yes" ] \
  && ok "(n20) AC11: stop from the page answered 200 and the socket really stopped answering — the process is gone, not merely asked" \
  || no "(n20) AC11: stop from the page stops the server" "status=$n_stop_st still-listening=$( [ "$n_down" = yes ] && echo no || echo YES )"

# The command-line half of the same claim, on a FRESH server: `stop` must report it as stopped
# and must NOT report it as `not killed … (not-ours)`.
nport2="$(n_free_port)"
case "$nport2" in ''|*[!0-9]*) setup_fail "(n21) fixture: could not obtain a port" ;; esac
n_out2="$( cd "$NPROJ" && HOME="$NHOME" bash "$ENGINE" serve --registry "$NREG" --ui-dir "$NUI" --no-regen --detach --port "$nport2" 2>&1 )"
SERVE_PIDFILES="$SERVE_PIDFILES $NUI/serve.pid"
if n_wait_up "$nport2"; then
  n_stop_out="$(bash "$ENGINE" stop --ui-dir "$NUI" 2>&1)"
  n_down=no; n_wait_down "$nport2" && n_down=yes
  n_killed="$(printf '%s' "$n_stop_out" | sed -n 's/^stop: \([0-9][0-9]*\) process.*$/\1/p' | head -1)"
  case "$n_killed" in ''|*[!0-9]*) n_killed=0 ;; esac
  [ "$n_killed" -ge 1 ] && [ "$n_down" = "yes" ] && ! in_str "$n_stop_out" "not-ours" \
    && ok "(n21) AC11 (R1 REGRESSION GUARD): 'stop' killed $n_killed recorded process(es), the socket went quiet, and it did NOT report the new handler as 'not killed … (not-ours)' — the replaced server still matches the pidfile guard verbatim" \
    || no "(n21) AC11: stop kills the replaced server and does not refuse it as not-ours" "killed=$n_killed still-listening=$( [ "$n_down" = yes ] && echo no || echo YES ) :: $n_stop_out"
else
  no "(n21) AC11: stop kills the replaced server" "the second serve never came up on $nport2 :: $n_out2"
fi

# --- (n22) AC11: the pidfile guard still REFUSES a pid that is not this module's -----------
# That refusal path had ZERO coverage before this item (grep -c 'not killed' returned 0), which
# is precisely why extending the guard would have been the dangerous repair: nothing would have
# noticed it going too far.
n_foreign_ui="$(mktmp)"
mkdir -p "$n_foreign_ui" 2>/dev/null
sleep 30 &
n_foreign_pid=$!
HOLDER_PIDS="$HOLDER_PIDS $n_foreign_pid"
printf '%s\n' "$n_foreign_pid" > "$n_foreign_ui/serve.pid"
n_stop_out="$(bash "$ENGINE" stop --ui-dir "$n_foreign_ui" 2>&1)"
n_alive=no; kill -0 "$n_foreign_pid" 2>/dev/null && n_alive=yes
in_str "$n_stop_out" "not-ours" && [ "$n_alive" = "yes" ] \
  && ok "(n22) AC11: a pidfile naming a process whose command line is NOT this module's is REFUSED by name ('not-ours') and that process is still running — the guard was matched, not widened" \
  || no "(n22) AC11: stop refuses a foreign pid and leaves it alone" "still-running=$n_alive :: $n_stop_out"
kill "$n_foreign_pid" 2>/dev/null

# A THIRD shipped-engine server, started here because (n20) and (n21) deliberately killed the
# other two: each control below compares the mutant's answer against the SHIPPED engine's answer
# to the identical request, and a comparison probe sent to a dead socket would come back "0" and
# quietly prove nothing.
NSHIP_PORT="$(n_free_port)"
case "$NSHIP_PORT" in ''|*[!0-9]*) setup_fail "(n) fixture: could not obtain a port for the reference run" ;; esac
n_ship_out="$( cd "$NPROJ" && HOME="$NHOME" bash "$ENGINE" serve --registry "$N/ship.json" --ui-dir "$NUI" --no-regen --detach --port "$NSHIP_PORT" 2>&1 )"
SERVE_PIDFILES="$SERVE_PIDFILES $NUI/serve.pid"
NSHIP_TOKEN="$(n_token_of "$n_ship_out")"
NSHIP_ORIGIN="http://127.0.0.1:$NSHIP_PORT"
[ -n "$NSHIP_TOKEN" ] || setup_fail "(n) fixture: the reference serve printed no #token= :: $n_ship_out"
n_wait_up "$NSHIP_PORT" || setup_fail "(n) fixture: the reference serve never came up on $NSHIP_PORT"

# ===========================================================================
# (n23)-(n26) AC13 — ONE MUTATION CONTROL PER GUARD PART
# ---------------------------------------------------------------------------
# Each mutant disables EXACTLY ONE part and leaves the other three intact, then sends the
# request that part alone was refusing and requires it to SUCCEED. A guard with no such control
# is indistinguishable from a guard that never fires: every 403 above would be produced by a
# server that refused everything, and the four positive cases ((n5), (n6), (n11), (n15)) prove
# only that the guard can say yes, not that each part is load-bearing.
# Every mutant goes through `mutant_ok` first — non-empty, genuinely different, and still valid
# bash — and n_guard_ran records whether it did, so a sed that silently stops matching the
# engine goes RED at (n27) instead of skipping inside its `if`.
NG_PORT=""; NG_TOKEN=""; NG_UI=""; NG_ENGINE=""; NG_RAN=""
n_stage_mutant() {
  # <name> <sed expression> [serve cwd]. The cwd defaults to the fixture project; (n37)
  # overrides it, because that control's whole subject is a serve whose LAUNCH DIRECTORY
  # differs from the path the request body carries — the defect registers the former in place
  # of the latter, and the two are indistinguishable when they are the same directory.
  local name="$1" sedexpr="$2" cwd="${3:-$NPROJ}" d out
  NG_PORT=""; NG_TOKEN=""; NG_UI=""; NG_ENGINE=""
  d="$N/mut-$name"
  mkdir -p "$d/floor-ui" 2>/dev/null || return 1
  cp "$BUNDLE_DIR"/* "$d/floor-ui/" 2>/dev/null || return 1
  sed "$sedexpr" "$ENGINE" > "$d/setup-ui.sh" 2>/dev/null || return 1
  mutant_ok "$ENGINE" "$d/setup-ui.sh" shell || return 1
  NG_RAN="$NG_RAN $name"
  NG_ENGINE="$d/setup-ui.sh"; NG_UI="$d/ui"
  bash "$NG_ENGINE" apply --ui-dir "$NG_UI" >/dev/null 2>&1
  [ -f "$NG_UI/index.html" ] || return 1
  NG_PORT="$(n_free_port)"
  case "$NG_PORT" in ''|*[!0-9]*) return 1 ;; esac
  out="$( cd "$cwd" && HOME="$NHOME" bash "$NG_ENGINE" serve --registry "$N/mut-$name.json" --ui-dir "$NG_UI" --no-regen --detach --port "$NG_PORT" 2>&1 )"
  SERVE_PIDFILES="$SERVE_PIDFILES $NG_UI/serve.pid"
  NG_TOKEN="$(n_token_of "$out")"
  [ -n "$NG_TOKEN" ] || return 1
  n_wait_up "$NG_PORT" || return 1
  return 0
}
# The probe every control sends is `scan` WITHOUT --confirm: it exercises the full guard and
# writes nothing, so a control that succeeds does not leave a registered project behind.
n_probe() { n_req "$1" POST /api/scan "$2" "$3" "$4" '{"path":"'"$NPROJ"'","confirm":false}' "$5"; }

# --- (n23) PART 1: the token VALUE -------------------------------------------------------
n_shipped="$(n_status "$(n_probe "$NSHIP_PORT" "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" "$NSHIP_ORIGIN" "" "")")"
# The sed targets the COMPARISON line alone. The `if raw is None or TOKEN == ""` line above it
# in the engine stays intact, so the mutant still refuses a missing header — what it stops
# checking is the token's VALUE, which is exactly the one part this control is for.
if n_stage_mutant token 's|        return hmac.compare_digest(str(raw).encode("utf-8", "replace"), TOKEN.encode("utf-8"))|        return True|'; then
  n_mut="$(n_status "$(n_probe "$NG_PORT" "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" "http://127.0.0.1:$NG_PORT" "" "")")"
  [ "$n_mut" = "200" ] \
    && ok "(n23) MUTATION CONTROL — PART 1 (the token value): the SHIPPED engine answered $n_shipped to a wrong token; with the token comparison alone disabled the identical request SUCCEEDS ($n_mut) — so the token check is load-bearing, not decoration" \
    || no "(n23) MUTATION CONTROL: disabling the token check alone lets a wrong-token write through" "the mutant answered $n_mut, expected 200 — this control cannot distinguish a working token check from one that never fires"
else
  no "(n23) MUTATION CONTROL — PART 1 (the token value)" "the token mutant could not be staged or started"
fi

# --- (n24) PART 2: the CUSTOM header ------------------------------------------------------
# The custom header is what forces a CORS preflight a hostile page cannot satisfy. Disabling
# that part means accepting the token from a CORS-SAFELISTED header instead — `Content-Language`
# — which is precisely the "simple request" hole where a write lands even though the attacker
# never reads the reply. The probe sends the token ONLY in that safelisted header.
if n_stage_mutant header 's|^TOKEN_HEADER="X-Floor-Token"$|TOKEN_HEADER="Content-Language"|'; then
  n_mut="$(n_status "$(n_probe "$NG_PORT" "$NG_TOKEN" "http://127.0.0.1:$NG_PORT" "" "Content-Language")")"
  n_ship="$(n_status "$(n_probe "$NSHIP_PORT" "$NSHIP_TOKEN" "$NSHIP_ORIGIN" "" "Content-Language")")"
  [ "$n_mut" = "200" ] \
    && [ "$n_ship" != "200" ] \
    && ok "(n24) MUTATION CONTROL — PART 2 (the custom header): the SHIPPED engine answered $n_ship to a token sent ONLY in the CORS-safelisted Content-Language header; with the header name alone changed to that same safelisted header, the identical request SUCCEEDS ($n_mut) — so requiring a CUSTOM header is what closes the simple-request hole, and it is load-bearing" \
    || no "(n24) MUTATION CONTROL: moving the token to a safelisted header lets the write through" "the mutant answered $n_mut, expected 200 (the shipped engine answered $n_ship to the same shape)"
else
  no "(n24) MUTATION CONTROL — PART 2 (the custom header)" "the header mutant could not be staged or started"
fi

# --- (n25) PART 3: Origin validation ------------------------------------------------------
if n_stage_mutant origin 's|    return origin is not None and origin in ALLOWED_ORIGINS|    return True|'; then
  n_mut="$(n_status "$(n_probe "$NG_PORT" "$NG_TOKEN" "http://evil.example.test" "" "")")"
  [ "$n_mut" = "200" ] \
    && ok "(n25) MUTATION CONTROL — PART 3 (Origin): with the Origin check alone disabled, a request carrying a FOREIGN Origin SUCCEEDS ($n_mut) where the shipped engine refuses it" \
    || no "(n25) MUTATION CONTROL: disabling the Origin check alone lets a cross-origin write through" "the mutant answered $n_mut, expected 200"
else
  no "(n25) MUTATION CONTROL — PART 3 (Origin)" "the origin mutant could not be staged or started"
fi

# --- (n26) PART 4: Host validation --------------------------------------------------------
if n_stage_mutant host 's|    return host is not None and host in ALLOWED_HOSTS|    return True|'; then
  n_mut="$(n_status "$(n_probe "$NG_PORT" "$NG_TOKEN" "http://127.0.0.1:$NG_PORT" "evil.example.com" "")")"
  [ "$n_mut" = "200" ] \
    && ok "(n26) MUTATION CONTROL — PART 4 (Host): with the Host check alone disabled, a request carrying a FORGED Host SUCCEEDS ($n_mut) — this is the DNS-rebinding case, and it is the part an Origin check provably cannot cover, since the Origin above was the legitimate one" \
    || no "(n26) MUTATION CONTROL: disabling the Host check alone lets a rebound request through" "the mutant answered $n_mut, expected 200"
else
  no "(n26) MUTATION CONTROL — PART 4 (Host)" "the host mutant could not be staged or started"
fi

# ===========================================================================
# (n36)/(n37) A BODY THIS SERVER CANNOT READ IS REFUSED, NEVER TREATED AS ABSENT
# ---------------------------------------------------------------------------
# These sit HERE, between (n26) and (n27), rather than at the end of the group where their
# numbers would suggest: (n37) is the fifth engine mutation control, (n27) is the anti-vacuity
# check over ALL of them, and an anti-vacuity check that runs before the thing it is checking
# would report a mutant it could not yet have seen as missing. Contiguous controls, one check
# over the set, in that order.
#
# THE DEFECT. `_payload` branched on `Content-Length` alone. A request carrying
# `Transfer-Encoding: chunked` has NO `Content-Length`, so it fell into the
# `raw is None -> return {}` arm — "no body, use the defaults". For `add` the default path is
# the directory `serve` was launched in, so a chunked POST carrying a real path in its body
# silently registered THE SERVE CWD INSTEAD: a WRITE on a failure path, which is precisely the
# outcome `_payload`'s own docstring says the None-vs-{} split exists to prevent. The body also
# stayed unread on the socket. The fix reads `Transfer-Encoding` FIRST and returns None, so the
# request is refused by name like any other body this server cannot read.
#
# THE FIXTURE'S ONE LOAD-BEARING PROPERTY: the serve is launched in a directory that is NOT the
# one the request body names. When the two are the same directory, "registered the serve cwd"
# and "registered the requested path" produce an identical registry and the control below could
# not tell the defect from the fix.
NCWD="$NHOME/work/chunked-serve-cwd"
mkdir -p "$NCWD/.git" || setup_fail "(n36) fixture: could not create the distinct serve-cwd directory"
# `add` stores what `cd -P … pwd -P` gives it, and the fixture root sits under a symlinked
# temporary directory on this platform, so the raw fixture strings would never match a registry
# entry. Resolve both sides the same way the engine does, once.
NCWD_REAL="$( cd -P "$NCWD" 2>/dev/null && pwd -P )"
NPROJ_REAL="$( cd -P "$NPROJ" 2>/dev/null && pwd -P )"
[ -n "$NCWD_REAL" ] && [ -n "$NPROJ_REAL" ] && [ "$NCWD_REAL" != "$NPROJ_REAL" ] \
  || setup_fail "(n36) fixture: the serve cwd and the requested path must resolve to two DIFFERENT directories, or the control below cannot discriminate (cwd='$NCWD_REAL' path='$NPROJ_REAL')"

# n_reg_has <registry file> <resolved absolute path> -> "yes" / "no".
# "no" for a registry that does not exist, because ABSENT is a defined state here and a missing
# file must not make this read like an error.
n_reg_has() {
  [ -f "$1" ] || { printf 'no'; return 0; }
  if jq -e --arg p "$2" 'any(.projects[]?; .path == $p)' "$1" >/dev/null 2>&1; then
    printf 'yes'
  else
    printf 'no'
  fi
}

# n_chunked_probe <port> <token> <origin> <json body>
# A RAW SOCKET, because `n_req` speaks http.client and http.client ALWAYS sets Content-Length —
# it structurally cannot emit the request this case is about. The body is properly chunk-encoded
# (`<hexlen>\r\n<data>\r\n0\r\n\r\n`) under `Transfer-Encoding: chunked` with NO `Content-Length`:
# a well-formed HTTP/1.1 request, not a malformed one, which is what makes it the interesting
# case. Prints "<status><TAB><body>" exactly like n_req, and "0" — a status this suite never
# gets from a live server — when no reply was written at all, so a dropped connection can never
# be misread as a refusal.
n_chunked_probe() {
  python3 - "$1" "$2" "$3" "$4" 2>/dev/null <<'__PY_CH__'
import socket
import sys

port = int(sys.argv[1])
token, origin, body = sys.argv[2], sys.argv[3], sys.argv[4].encode("utf-8")
host_hdr = ("127.0.0.1:%d" % port).encode("ascii")
req = (b"POST /api/add HTTP/1.1\r\nHost: " + host_hdr +
       b"\r\nOrigin: " + origin.encode("ascii") +
       b"\r\nX-Floor-Token: " + token.encode("ascii") +
       b"\r\nContent-Type: application/json" +
       b"\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n" +
       ("%x\r\n" % len(body)).encode("ascii") + body + b"\r\n0\r\n\r\n")
s = socket.create_connection(("127.0.0.1", port), timeout=15)
try:
    s.sendall(req)
except Exception:
    # A server that refuses without draining the body may close first. Whatever it managed to
    # write is still worth reading, so this does not abort the probe.
    pass
data = b""
try:
    while True:
        chunk = s.recv(4096)
        if not chunk:
            break
        data += chunk
except Exception:
    pass
s.close()
if not data:
    sys.stdout.write("0\tthe connection was closed without any response being written")
else:
    head, _sep, rest = data.partition(b"\r\n\r\n")
    parts = head.split(b"\r\n", 1)[0].decode("latin-1").split(" ")
    sys.stdout.write((parts[1] if len(parts) > 1 else "0") + "\t" +
                     rest.decode("utf-8", "replace").replace("\n", " "))
__PY_CH__
}

# A SHIPPED-ENGINE serve of its own, launched in NCWD with its own registry and its own ui
# directory: the runs above were all launched in the fixture project, and reusing one would make
# the serve cwd and the requested path the same directory. Its own ui dir also keeps its pidfile
# from displacing another run's in the cleanup list.
NCH_UI="$N/chunk-ui"
NCH_REG="$N/chunk-ship.json"
bash "$ENGINE" apply --ui-dir "$NCH_UI" >/dev/null 2>&1
[ -f "$NCH_UI/index.html" ] || setup_fail "(n36) fixture: apply did not install the bundle into $NCH_UI"
NCH_PORT="$(n_free_port)"
case "$NCH_PORT" in ''|*[!0-9]*) setup_fail "(n36) fixture: could not obtain a port for the chunked-body run" ;; esac
n_ch_out="$( cd "$NCWD" && HOME="$NHOME" bash "$ENGINE" serve --registry "$NCH_REG" --ui-dir "$NCH_UI" --no-regen --detach --port "$NCH_PORT" 2>&1 )"
SERVE_PIDFILES="$SERVE_PIDFILES $NCH_UI/serve.pid"
NCH_TOKEN="$(n_token_of "$n_ch_out")"
[ -n "$NCH_TOKEN" ] || setup_fail "(n36) fixture: the chunked-body serve printed no #token= :: $n_ch_out"
n_wait_up "$NCH_PORT" || setup_fail "(n36) fixture: the chunked-body serve never came up on $NCH_PORT"
n_ch_sig() { [ -f "$NCH_REG" ] && csum "$NCH_REG" || printf 'ABSENT'; }

# --- (n36) a chunked POST to /api/add is REFUSED and writes nothing ------------------------
# Everything else about this request is VALID — this run's token in the custom header, a
# loopback Origin, a loopback Host, and a real absolute path inside the permitted root — so the
# only thing it can be refused for is the one property under test. (n5) already proved the same
# shape with a Content-Length body is accepted and really registers.
n_ch_before="$(n_ch_sig)"
n_ch_res="$(n_chunked_probe "$NCH_PORT" "$NCH_TOKEN" "http://127.0.0.1:$NCH_PORT" '{"path":"'"$NPROJ"'"}')"
n_ch_after="$(n_ch_sig)"
n_ch_cwd_in="$(n_reg_has "$NCH_REG" "$NCWD_REAL")"
n_ch_proj_in="$(n_reg_has "$NCH_REG" "$NPROJ_REAL")"
n_ch_bad=""
[ "$(n_status "$n_ch_res")" = "400" ] || n_ch_bad="$n_ch_bad [status $(n_status "$n_ch_res"), expected 400 — a status of 0 would mean no reply was written at all]"
in_str "$(n_body "$n_ch_res")" "body-not-json" || n_ch_bad="$n_ch_bad [the reply does not name body-not-json: $(n_body "$n_ch_res")]"
[ "$n_ch_before" = "$n_ch_after" ] || n_ch_bad="$n_ch_bad [the registry changed on a refused request: before='$n_ch_before' after='$n_ch_after']"
[ "$n_ch_cwd_in" = "no" ] || n_ch_bad="$n_ch_bad [THE SERVE CWD $NCWD_REAL WAS REGISTERED — this is the defect itself: the write landed, on a failure path, naming a directory nobody asked for]"
[ "$n_ch_proj_in" = "no" ] || n_ch_bad="$n_ch_bad [the requested path $NPROJ_REAL was registered, so the chunked body was decoded after all and this case is testing something else]"
[ -z "$n_ch_bad" ] \
  && ok "(n36) a chunked POST to /api/add — valid token, custom header, loopback Origin and Host, a real absolute path in a correctly chunk-encoded body — is REFUSED 400 naming body-not-json, the registry is byte-identical across it, and the directory serve was launched in ($NCWD_REAL) was NOT registered: a body this server cannot read is refused, never treated as absent" \
  || no "(n36) a chunked body is refused by name and registers nothing" "$n_ch_bad"

# --- (n37) MUTATION CONTROL: the Transfer-Encoding check is what stops the wrong write ------
# The one part disabled is the `Transfer-Encoding` test itself; `_payload`'s Content-Length
# arms, and all four guard parts, stay intact — so the identical request is refused by nothing
# and takes the pre-fix route. This is the control that proves BOTH halves of the claim: that
# the check is load-bearing, and that the defect it closes was real rather than theoretical.
# It must fail RED, not skip, if the mutant cannot be staged: a control that quietly disappears
# proves exactly nothing, which is why the `else` below is a `no` and why (n27) enumerates it.
if n_stage_mutant chunked 's|if self.headers.get("Transfer-Encoding") is not None:|if False:|' "$NCWD"; then
  n_ch_mut_reg="$N/mut-chunked.json"
  n_ch_mut_res="$(n_chunked_probe "$NG_PORT" "$NG_TOKEN" "http://127.0.0.1:$NG_PORT" '{"path":"'"$NPROJ"'"}')"
  n_ch_mut_st="$(n_status "$n_ch_mut_res")"
  n_ch_mut_cwd="$(n_reg_has "$n_ch_mut_reg" "$NCWD_REAL")"
  n_ch_mut_proj="$(n_reg_has "$n_ch_mut_reg" "$NPROJ_REAL")"
  [ "$n_ch_mut_st" = "200" ] && [ "$n_ch_mut_cwd" = "yes" ] && [ "$n_ch_mut_proj" = "no" ] \
    && ok "(n37) MUTATION CONTROL — the chunked body: the SHIPPED engine refused this exact request 400 body-not-json and wrote nothing; with the Transfer-Encoding check ALONE disabled it SUCCEEDS ($n_ch_mut_st) and registers THE WRONG DIRECTORY — $NCWD_REAL, the one serve was launched in, in place of the $NPROJ_REAL the body asked for — so the check is load-bearing and the silent wrong write it prevents was real" \
    || no "(n37) MUTATION CONTROL: removing the Transfer-Encoding check lets a chunked body register the serve cwd" \
         "the mutant answered $n_ch_mut_st (expected 200); serve-cwd registered=$n_ch_mut_cwd (expected yes); requested-path registered=$n_ch_mut_proj (expected no) :: $(n_body "$n_ch_mut_res")"
else
  no "(n37) MUTATION CONTROL — the chunked body" "the chunked mutant could not be staged or started, so the Transfer-Encoding check is UNCONTROLLED"
fi

# --- (n27) ANTI-VACUITY: all five mutation controls actually EXECUTED -------------------------------
# Each control lives inside an `if mutant_ok`. A sed that stops matching the engine makes that
# `if` false, and the control then disappears — neither red nor green — which is exactly how
# the previous (h2) died. This turns that silence into a failure.
n_missing=""
for npart in token header origin host chunked; do
  case " $NG_RAN " in *" $npart "*) ;; *) n_missing="$n_missing $npart" ;; esac
done
[ -z "$n_missing" ] \
  && ok "(n27) ANTI-VACUITY: all five engine mutants — the four guard parts and the chunked-body check — passed mutant_ok and their controls EXECUTED: none of (n23)-(n26) or (n37) was skipped inside its if" \
  || no "(n27) ANTI-VACUITY: all five mutation controls executed" "these mutants never ran:$n_missing — their sed no longer matches the engine, so the corresponding check is UNCONTROLLED"

# --- (n28) the shipped engine and bundle are untouched by every (n) mutant -----------------
n_eng_after="$(csum "$ENGINE")"
n_residue="$(ls "$script_dir"/*.n.mut.sh 2>/dev/null || true)"
[ "$n_eng_after" = "$N_ENG_SIG_BEFORE" ] && [ -z "$n_residue" ] \
  && ok "(n28) setup-ui.sh is byte-identical after every (n) mutation control (sha256 unchanged) and no mutant was left in the plugin's own directories" \
  || no "(n28) setup-ui.sh is byte-identical after the (n) mutation controls" "before='$N_ENG_SIG_BEFORE' after='$n_eng_after' residue='$n_residue'"

# --- (n29) the four routes are FOUR, read out of the engine --------------------------------
# `apply` and `remove` are excluded BY DECISION, not by omission: they are install-level, and a
# page able to uninstall itself buys nothing and risks something. Read from the engine rather
# than restated, so a fifth route added there fails here instead of shipping unnoticed.
n_routes="$(sed -n 's/^ROUTES = (\(.*\))$/\1/p' "$ENGINE" | head -1 | tr -d '"' | tr ',' ' ')"
n_route_set="$(printf '%s\n' $n_routes | LC_ALL=C sort | tr '\n' ' ')"
[ "$n_route_set" = "add forget scan stop " ] \
  && ok "(n29) the engine exposes exactly four mutating routes and they are add, forget, scan and stop — apply and remove are excluded by decision, and the set is read out of the engine rather than restated here" \
  || no "(n29) the engine exposes exactly the four intended mutating routes" "parsed '$n_route_set', expected 'add forget scan stop '"

# --- (n30) AC10 STATIC HALF: the page has a DISTINCT stopped state --------------------------
# The browser half of AC10 (does the stopped banner actually read that way in a DOM, with a
# clean console?) is verified by a human or at Phase 4.5 against the committed fixtures, exactly
# like the other render states in this suite. What is checkable HERE is the mechanism, and the
# mechanism is what makes the browser half possible: a flag the poll is gated on, a render that
# names the state, controls that disable, and NOT any of the three dishonest alternatives — a
# spinner, the last floor presented as current, or a stream of fetch errors about a server the
# reader deliberately stopped.
n_stop_bad=""
has_lit "$JS" "function renderStopped()" || n_stop_bad="$n_stop_bad [no renderStopped]"
has_lit "$JS" "if (serverStopped) { return; }" || n_stop_bad="$n_stop_bad [the poll is not gated on the stopped flag, so it would keep fetching a server that is gone]"
has_lit "$JS" "this server was stopped from this page" || n_stop_bad="$n_stop_bad [the stopped state has no words of its own]"
has_lit "$JS" "not a current one" || n_stop_bad="$n_stop_bad [the page does not say the floor it is showing is a snapshot rather than current]"
# RE-POINTED, NOT RELAXED. The inline disable loop this used to match was hoisted into
# `setActionsDisabled(flag)` when the write guard below became its second caller, so the old
# literal would have vanished and this half of (n30) would have gone red for a property that
# is still there. Both halves are asserted instead, and the second is scoped to renderStopped's
# own body so that runAction's identical call cannot satisfy it on renderStopped's behalf.
has_lit "$JS" "controls[i].disabled = flag;" || n_stop_bad="$n_stop_bad [there is no single place that enables or disables the action controls]"
n_stop_body="$(awk '/^  function renderStopped\(\)/{f=1} f{print} f&&/^  }$/{exit}' "$JS" 2>/dev/null)"
in_str "$n_stop_body" "setActionsDisabled(true);" || n_stop_bad="$n_stop_bad [the action controls are not disabled, so the page still offers writes it cannot make]"
[ -z "$n_stop_bad" ] \
  && ok "(n30) AC10 (static half): the page carries a distinct stopped render — a flag the ONE poll returns early on, its own words, an explicit statement that the floor shown is a snapshot rather than current, and disabled controls" \
  || no "(n30) AC10: the page renders a distinct stopped state" "$n_stop_bad"
# MUTATION CONTROL: an ungated poll is the specific defect this state exists to prevent — it
# would banner a fetch failure about a server the reader themselves stopped.
MUT_STOP="$TMPROOT/mut-stopped.js"
sed 's|if (serverStopped) { return; }||' "$JS" > "$MUT_STOP" 2>/dev/null
if mutant_ok "$JS" "$MUT_STOP"; then
  m_stop=0; has_lit "$MUT_STOP" "if (serverStopped) { return; }" && m_stop=1
  [ "$m_stop" = "0" ] \
    && ok "(n31) MUTATION CONTROL: a poll that is NOT gated on the stopped flag IS flagged by (n30) — so that assertion is reading the gate rather than merely finding the word" \
    || no "(n31) MUTATION CONTROL: an ungated poll is flagged" "the mutant still carries the guard literal"
fi

# --- (n32) NO CORS HEADER, EVER, AND NO PREFLIGHT ANSWER ------------------------------------
# Both are one-line regressions that re-open the other-tab attack the custom header closes, and
# neither would redden any other assertion in this suite: adding `Access-Control-Allow-Origin`
# lets the attacker READ the reply, and answering an OPTIONS preflight lets the write be SENT.
n_cors="$(occ "$ENGINE" 'Access-Control-Allow-Origin')"
n_opts="$(awk '$0 !~ /^[[:space:]]*#/ && /def do_OPTIONS/ {n++} END{print n+0}' "$ENGINE")"
n_acao_code="$(awk '$0 !~ /^[[:space:]]*#/ && /Access-Control-Allow-Origin/ {n++} END{print n+0}' "$ENGINE")"
[ "$n_acao_code" = "0" ] && [ "$n_opts" = "0" ] && [ "$n_cors" -ge 1 ] 2>/dev/null \
  && ok "(n32) the engine sends NO Access-Control-Allow-Origin on any response and answers no OPTIONS preflight — both verified in CODE (0 and 0), while the comment saying so is still present ($n_cors raw mentions), so a future author reads the reason before deleting the property" \
  || no "(n32) no CORS header and no preflight answer" "ACAO in code=$n_acao_code do_OPTIONS=$n_opts raw mentions=$n_cors — a raw count of 0 would mean the explanatory comment went too, which is how this property gets removed by accident"

# --- (n33)-(n35) NOTHING PUTS A TRACEBACK INTO THE LOG THE PAGE CAN FETCH -------------------
# TWO CONFIRMED WAYS a request thread used to raise, and one class-level fix for both.
#   (a) PRE-AUTHENTICATION. `hmac.compare_digest` on two `str` raises TypeError the moment
#       either side carries a character above 127. HTTP headers are latin-1 decoded, so ANY
#       unauthenticated caller could reach that raise with one byte > 127 in the token header,
#       and the reply it produced was NO reply at all — the client saw the connection drop.
#       That is the exact opposite of AC12: every failure path refuses with a NAMED reason.
#   (b) ORDINARY USE. A client that closes its tab mid-reply raises BrokenPipeError inside the
#       response write, which reached `socketserver.handle_error` and its `print_exc`.
# In both cases the traceback went to stderr, which for this server IS `serve.log` — a file
# INSIDE THE SERVED ROOT, fetchable with `GET /serve.log` — written unlocked from every thread
# at once, so two concurrent aborts interleave into corrupted multi-line noise. That falsified
# the log invariant restated on four surfaces (engine header, SERVE_LOG comment, FLOOR_UI.md
# and CHANGELOG.md). The fix is `FloorServer.handle_error`, which is why this asserts the CLASS
# property — zero `Traceback` lines, whatever raised — rather than the two known instances.
#
# The probes speak raw sockets rather than http.client: (a) has to put a byte on the wire that
# a client-side header encoder would refuse first, and (b) has to RESET a connection, which no
# request helper offers.
n_tb_probe() {
  python3 - "$1" "$2" 2>/dev/null <<'__PY_TB__'
import socket
import struct
import sys

port = int(sys.argv[1])
mode = sys.argv[2]
host_hdr = ("127.0.0.1:%d" % port).encode("ascii")

if mode == "nonascii":
    req = (b"POST /api/scan HTTP/1.1\r\nHost: " + host_hdr +
           b"\r\nX-Floor-Token: \xc3\xa9\xff\r\nOrigin: http://" + host_hdr +
           b"\r\nContent-Type: application/json\r\nContent-Length: 2\r\n"
           b"Connection: close\r\n\r\n{}")
    s = socket.create_connection(("127.0.0.1", port), timeout=15)
    s.sendall(req)
    data = b""
    try:
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
    except Exception:
        pass
    s.close()
    if not data:
        # "0" is the status this suite never gets from a live server, so the no-reply case can
        # never be mistaken for a refusal — which is precisely what the old behaviour was.
        sys.stdout.write("0\tthe connection was closed without any response being written")
    else:
        head, _sep, body = data.partition(b"\r\n\r\n")
        parts = head.split(b"\r\n", 1)[0].decode("latin-1").split(" ")
        sys.stdout.write((parts[1] if len(parts) > 1 else "0") + "\t" +
                         body.decode("utf-8", "replace").replace("\n", " "))
else:
    # SO_LINGER 0 makes `close` send an RST, so the handler's write lands on a dead peer.
    # Repeated, because whether the reply had already been flushed is a race and one attempt
    # could miss it; the reviewer's own reproduction took three.
    for _i in range(6):
        s = socket.create_connection(("127.0.0.1", port), timeout=15)
        s.sendall(b"GET /floor.json HTTP/1.1\r\nHost: " + host_hdr + b"\r\n\r\n")
        s.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
        s.close()
    sys.stdout.write("aborted\tsix requests were sent and reset before any reply could be read")
__PY_TB__
}
# ONE grep, named once, used by both the measurement and its anti-vacuity control — so the two
# cannot drift into asserting different things about different patterns.
n_tb_count() {
  local c
  c="$(grep -c -F -- 'Traceback' "$1" 2>/dev/null || true)"
  case "$c" in ''|*[!0-9]*) c=0 ;; esac
  printf '%s' "$c"
}

n_tb_log="$NUI/$(sed -n 's/^SERVE_LOG="\([^"]*\)".*$/\1/p' "$ENGINE" | head -1)"
n_tb_a="$(n_tb_probe "$NSHIP_PORT" nonascii)"
n_tb_b="$(n_tb_probe "$NSHIP_PORT" abort)"
n_tb_alive="$(n_status "$(n_req "$NSHIP_PORT" GET /index.json "" "" "" "" "")")"

# --- (n33) AC12: a non-ASCII token header is REFUSED BY NAME, not dropped -------------------
n_tb_bad=""
[ "$(n_status "$n_tb_a")" = "403" ] || n_tb_bad="$n_tb_bad [status $(n_status "$n_tb_a"), expected 403 — a status of 0 is the pre-fix behaviour: no reply at all]"
in_str "$(n_body "$n_tb_a")" "token-missing-or-wrong" || n_tb_bad="$n_tb_bad [the reply does not name the refusing part: $(n_body "$n_tb_a")]"
[ "$n_tb_alive" = "200" ] || n_tb_bad="$n_tb_bad [the handler stopped serving afterwards: GET /index.json answered $n_tb_alive]"
[ -z "$n_tb_bad" ] \
  && ok "(n33) AC12: a token header carrying a byte above 127 — reachable PRE-AUTHENTICATION by any caller, and the input on which comparing two str raises TypeError — is refused 403 with the guard part NAMED, and the handler keeps serving" \
  || no "(n33) AC12: a non-ASCII token header is refused with a named reason" "$n_tb_bad"

# --- (n34) the serve log carries NO traceback after either trigger --------------------------
n_tb_hits="$(n_tb_count "$n_tb_log")"
if [ ! -f "$n_tb_log" ]; then
  no "(n34) the serve log holds no traceback after a non-ASCII token header and an aborted connection" "there is no serve log at $n_tb_log, so this could not be measured at all"
else
  [ "$n_tb_hits" = "0" ] \
    && ok "(n34) after a non-ASCII token header ($(n_status "$n_tb_a")) and six reset connections, the serve log holds ZERO 'Traceback' lines — FloorServer.handle_error collapses every unhandled raise to one audited line in a file the page can itself fetch" \
    || no "(n34) the serve log holds no traceback after a non-ASCII token header and an aborted connection" "$n_tb_hits 'Traceback' line(s) in $n_tb_log — the multi-line, thread-interleaved dump is back, in a file inside the served root"
fi

# --- (n35) ANTI-VACUITY: that grep can actually find a traceback ----------------------------
# Without this, (n34) passes just as happily against a misspelled pattern, an unreadable file,
# or a `grep -c` whose non-zero exit was swallowed. The plant goes into a scratch COPY, never
# into the served directory, so the measurement above is not disturbed by its own control.
n_tb_planted="$N/n-traceback-planted.log"
{ cat "$n_tb_log" 2>/dev/null || true
  printf 'Traceback (most recent call last):\n  File "<string>", line 1, in <module>\nTypeError: comparing strings with non-ASCII characters is not supported\n'
} > "$n_tb_planted" 2>/dev/null
n_tb_plant_hits="$(n_tb_count "$n_tb_planted")"
[ "$n_tb_plant_hits" -ge 1 ] 2>/dev/null \
  && ok "(n35) ANTI-VACUITY: the same grep (n34) uses finds $n_tb_plant_hits planted 'Traceback' line(s) in a scratch copy of that very log — so (n34)'s zero is a measurement, not an empty needle" \
  || no "(n35) ANTI-VACUITY: (n34)'s traceback scan can find a planted traceback" "the planted copy $n_tb_planted returned $n_tb_plant_hits hits"

# --- (n38)-(n43) THE WRITE PATH CARRIES THE READ PATH'S IN-FLIGHT GUARD --------------------
# The read poll has held an explicit in-flight flag for as long as it has existed, and
# (b20)/(b21) assert it: one request at a time, cleared on every settle path, so a hung origin
# cannot stack fetches. runAction — which backs all four write buttons — had no equivalent. It
# checked `serverStopped` and the token and fired, so one double-click put two `add` /
# `scan --confirm` / `forget` requests on the wire at once against a registry that is a single
# file. The flag is per-PAGE and the assertion claims no more than that: the same URL in a
# SECOND TAB is a different closure and only the server sees both. The asymmetry with the read-side
# guard is what makes this a gap rather than an accepted trade-off, so the assertion is written
# to the same shape and adds the half a write has that a read does not: controls disabled for
# the length of the request and re-enabled on EVERY exit — including the failing ones, because a
# button left permanently dead by one network error is a worse defect than the double-click.
# As in (c13), the rule lives in ONE function so the three controls can point it at a mutant.
n_write_guard_faults() { # <file> -> the parts of the write-side in-flight guard it is missing
  local f="$1" bad="" n body
  has_lit "$f" "var writeInFlight = false;" \
    || bad="$bad [no write in-flight flag]"
  has_lit "$f" "if (writeInFlight) { return; }" \
    || bad="$bad [runAction is not gated on the flag, so a second click is not refused]"
  has_lit "$f" "writeInFlight = true;" \
    || bad="$bad [the flag is never raised, so the gate can never fire]"
  has_lit "$f" "if (!serverStopped) { setActionsDisabled(false); }" \
    || bad="$bad [the controls are never re-enabled, or the re-enable is not withheld from the stopped state]"
  body="$(awk '/^  function runAction\(/{f=1} f{print} f&&/^  }$/{exit}' "$f" 2>/dev/null)"
  in_str "$body" "setActionsDisabled(true);" \
    || bad="$bad [the controls are not disabled while a write is outstanding]"
  n="$(occ "$f" 'releaseWrite[(][)];')"
  [ "${n:-0}" -ge 3 ] 2>/dev/null \
    || bad="$bad [${n:-0} release site(s), expected one per exit path — resolve, reject, and a request that could not be started at all]"
  printf '%s' "${bad# }"
}
N_WG_MUTANTS=0
n_wg_faults="$(n_write_guard_faults "$JS")"
[ -z "$n_wg_faults" ] \
  && ok "(n38) the write path carries an in-flight guard in the same shape as the read poll's — a flag, an early return, the controls disabled for the length of the request, and a release on each of the three exit paths" \
  || no "(n38) the write path carries an in-flight guard in the read poll's shape" "$n_wg_faults"

# CONTROL 1 — the guard itself removed. This is the shipped state the finding names: two
# concurrent writes are reachable by a reader, not only by a hung origin.
MUT_WG1="$TMPROOT/mut-write-ungated.js"
sed 's|if (writeInFlight) { return; }||' "$JS" > "$MUT_WG1" 2>/dev/null
if mutant_ok "$JS" "$MUT_WG1"; then
  N_WG_MUTANTS=$((N_WG_MUTANTS + 1))
  m_wg1="$(n_write_guard_faults "$MUT_WG1")"
  if in_str "$m_wg1" "not gated on the flag"; then
    ok "(n39) MUTATION CONTROL: a runAction that raises the flag but never RETURNS on it IS flagged by (n38) — so that assertion is reading the gate rather than merely finding the variable"
  else
    no "(n39) MUTATION CONTROL: an ungated runAction IS flagged" "n_write_guard_faults said: ${m_wg1:-<clean, so (n38) would pass a write path with no guard at all>}"
  fi
fi

# CONTROL 2 — the re-enable removed. A guard whose visible half never comes back leaves every
# button dead after the first failed write; it is a guard that has become the bug.
MUT_WG2="$TMPROOT/mut-write-stuck.js"
sed 's|if (!serverStopped) { setActionsDisabled(false); }||' "$JS" > "$MUT_WG2" 2>/dev/null
if mutant_ok "$JS" "$MUT_WG2"; then
  N_WG_MUTANTS=$((N_WG_MUTANTS + 1))
  m_wg2="$(n_write_guard_faults "$MUT_WG2")"
  if in_str "$m_wg2" "never re-enabled"; then
    ok "(n40) MUTATION CONTROL: a guard that disables the controls and never re-enables them IS flagged — the stuck-button failure a network error would otherwise make permanent"
  else
    no "(n40) MUTATION CONTROL: controls that are never re-enabled ARE flagged" "n_write_guard_faults said: ${m_wg2:-<clean>}"
  fi
fi

# CONTROL 3 — ONE release site dropped. The count is the only part of (n38) that says the
# release happens on every exit rather than merely somewhere, so it needs its own control: a
# guard released on two of three paths passes every literal check above.
MUT_WG3="$TMPROOT/mut-write-one-exit.js"
awk 'BEGIN{done=0} { if (!done && index($0, "releaseWrite();")) { sub(/releaseWrite\(\);/, ""); done=1 } print }' "$JS" > "$MUT_WG3" 2>/dev/null
if mutant_ok "$JS" "$MUT_WG3"; then
  N_WG_MUTANTS=$((N_WG_MUTANTS + 1))
  m_wg3="$(n_write_guard_faults "$MUT_WG3")"
  if in_str "$m_wg3" "release site(s)"; then
    ok "(n41) MUTATION CONTROL: dropping ONE of the three release sites IS flagged — every literal in (n38) still matches that file, so the per-exit-path count is doing work no presence check does"
  else
    no "(n41) MUTATION CONTROL: a missing release site IS flagged" "n_write_guard_faults said: ${m_wg3:-<clean>}"
  fi
fi

# ANTI-VACUITY: all three controls must have EXECUTED. Each sits inside an `if mutant_ok`, and
# a sed whose anchor has moved yields an identical copy — mutant_ok reddens, but the control it
# guards is then silently not run, which is exactly how a gate goes vacuous without going red.
[ "$N_WG_MUTANTS" = "3" ] \
  && ok "(n42) ANTI-VACUITY: all three (n38) mutation controls EXECUTED — none of (n39), (n40) or (n41) was skipped inside its if" \
  || no "(n42) ANTI-VACUITY: all three (n38) mutation controls executed" "$N_WG_MUTANTS of 3 ran — a control that did not run proves nothing about (n38)"
[ "$(csum "$JS")" = "$JS_SIG_BEFORE" ] \
  && ok "(n43) floor.js is byte-identical after the three (n38) mutation controls (sha256 unchanged)" \
  || no "(n43) floor.js is byte-identical after the (n38) mutation controls" "before='$JS_SIG_BEFORE' after='$(csum "$JS")'"

# ===========================================================================
echo "(o) AC-registry-lock — two writers on one registry, and the lock that makes both survive"
# ===========================================================================
# WHY THIS GROUP IS A MEASUREMENT AND NOT AN INSPECTION. Every other engine guard in this file
# can be shown with a single invocation: give it the input, read the refusal. A concurrency
# control cannot — its whole subject is what TWO processes do to each other, and reading the
# lock code proves only that a lock was typed. So this group runs real concurrent invocations
# and asserts on the registry they leave behind.
#
# THE RACE IS MADE DETERMINISTIC BY THE ENVIRONMENT, NOT BY EDITING THE ENGINE. Two `add`s
# launched together overlap only if their read-modify-write windows overlap, and that window is
# a few tens of milliseconds — so a naive pair would race sometimes, which is a flaky test in
# BOTH directions: green by luck on a broken engine, red by luck on a correct one. The window is
# therefore widened by putting a jq on PATH that sleeps before exec'ing the real one. `add` calls
# jq several times between its snapshot and its `mv`, so the critical section grows to seconds
# while THE ENGINE UNDER TEST STAYS BYTE-IDENTICAL — the subject of (o2) is the shipped file.
# (o1) measures that the stub really is slow, so the widening is asserted rather than assumed.
#
# THE CONTROL CHANGES EXACTLY ONE THING. (o3) runs the same two writers, under the same slow jq,
# against an engine copy whose only difference is that the write path never takes the lock — one
# token in reg_prepare's mode test. One writer's registration must be LOST there. Without that
# arm (o2) would pass just as happily against an engine that serialises for some other reason,
# or against a race that simply did not happen.
#
# STALENESS GETS FOUR CASES, NOT ONE, because a detector that called every lock stale would pass
# the three breaking cases while destroying the mechanism: (o9)/(o10)/(o12) are the three ways to
# be stale, and (o11) is the arm proving a lock that is NOT stale is left alone.

O="$(mktmp)" || setup_fail "(o) fixture: mktemp under $TMPROOT failed"
OREG="$O/reg.json"
mkdir -p "$O/p1" "$O/p2" "$O/slowbin" || setup_fail "(o) fixture: could not build the lock fixture tree"

O_REALJQ="$(command -v jq 2>/dev/null || true)"
[ -n "$O_REALJQ" ] || setup_fail "(o) fixture: jq is not on PATH, and every assertion in this group needs the registry verbs to work at all"
# The stub is a REAL executable that delays and then hands over to the real jq. It is not a
# mock: the engine's jq output has to stay correct, or (o2) would be measuring a broken `add`.
cat > "$O/slowbin/jq" <<SLOWJQ
#!/bin/sh
sleep 1
exec "$O_REALJQ" "\$@"
SLOWJQ
chmod +x "$O/slowbin/jq" || setup_fail "(o) fixture: could not make the slow-jq stub executable"
OSLOW="$O/slowbin"

# --- (o1) the widened window is MEASURED ------------------------------------------------
o_t0="$(date +%s)"
PATH="$OSLOW:$PATH" jq -n '1' >/dev/null 2>&1
o_t1="$(date +%s)"
o_stub_cost=$((o_t1 - o_t0))
[ "$o_stub_cost" -ge 1 ] \
  && ok "(o1) the slow-jq stub really delays a jq call (${o_stub_cost}s), so the critical section (o2)/(o3) race inside is genuinely widened rather than assumed to be" \
  || no "(o1) the slow-jq stub delays a jq call" \
       "one jq call took ${o_stub_cost}s — the window is not widened, so (o2) would pass on luck and (o3) could not lose a write reliably"

# --- calibration: what ONE writer costs, in this run, on this host ----------------------
# (o2)'s serialisation claim is "the pair took materially longer than one writer", and that
# needs one writer's cost measured HERE rather than a constant — the same reason group (l)
# calibrates its stub projector in the run that uses it.
o_t0="$(date +%s)"
PATH="$OSLOW:$PATH" bash "$ENGINE" add "$O/p1" --registry "$O/calib.json" >/dev/null 2>&1
o_t1="$(date +%s)"
o_solo=$((o_t1 - o_t0))
[ "$o_solo" -ge 2 ] \
  && ok "(o1b) one locked writer under the slow stub costs ${o_solo}s — a measured baseline for (o2), not a constant that could drift away from this host" \
  || no "(o1b) one writer under the slow stub has a measurable cost" \
       "a single add took ${o_solo}s, which is too short to distinguish serialised from overlapped in (o2)"
o_min=$((o_solo + o_solo / 2))

# --- (o2) THE CLAIM: two concurrent writers, both registrations survive -----------------
rm -f "$OREG"
o_t0="$(date +%s)"
( PATH="$OSLOW:$PATH" bash "$ENGINE" add "$O/p1" --registry "$OREG" >"$O/a.log" 2>&1 ) &
( PATH="$OSLOW:$PATH" bash "$ENGINE" add "$O/p2" --registry "$OREG" >"$O/b.log" 2>&1 ) &
wait
o_t1="$(date +%s)"
o_pair=$((o_t1 - o_t0))
o_n="$(jq -r '.projects | length' "$OREG" 2>/dev/null)"
o_slugs="$(jq -r '[.projects[].slug] | sort | join(",")' "$OREG" 2>/dev/null)"
if [ "$o_n" = "2" ] && [ "$o_slugs" = "p1,p2" ]; then
  ok "(o2) two genuinely concurrent 'add' invocations on ONE registry both survive — the shipped engine, unmutated, left both p1 and p2 registered where a last-mv-wins engine keeps one"
else
  no "(o2) two concurrent 'add' invocations both survive" \
     "entries='$o_n' (want 2) slugs='$o_slugs' (want 'p1,p2') — one registration was discarded
     a.log: $(cat "$O/a.log" 2>/dev/null)
     b.log: $(cat "$O/b.log" 2>/dev/null)"
fi
[ "$o_pair" -ge "$o_min" ] \
  && ok "(o2b) and they were SERIALISED rather than merely lucky: the pair took ${o_pair}s against a ${o_solo}s single writer (threshold ${o_min}s), so the second one demonstrably waited for the first" \
  || no "(o2b) the two writers were serialised" \
       "the pair took ${o_pair}s against a ${o_solo}s single writer — under the ${o_min}s threshold, so their critical sections may simply not have overlapped and (o2) proves nothing about the lock"

# --- (o3) MUTATION CONTROL: the lock is load-bearing ------------------------------------
# One token: reg_prepare's write-mode test can no longer be true, so `add`/`forget`/`scan
# --confirm` run exactly as before EXCEPT that they take nothing. Everything else — the slow
# jq, the two projects, the concurrency — is identical to (o2).
O_ENGINE_SIG_BEFORE="$(csum "$ENGINE")"
OMUT="$O/setup-ui-nolock.sh"
awk 'BEGIN { done = 0 }
     {
       if (!done && index($0, "if [ \"$mode\" = \"write\" ]; then") > 0) { sub(/= "write"/, "= \"never\""); done = 1 }
       print
     }' "$ENGINE" > "$OMUT" 2>/dev/null
O_MUT_RAN=0
if mutant_ok "$ENGINE" "$OMUT" shell; then
  O_MUT_RAN=1
  rm -f "$O/mut.json"
  ( PATH="$OSLOW:$PATH" bash "$OMUT" add "$O/p1" --registry "$O/mut.json" >"$O/ma.log" 2>&1 ) &
  ( PATH="$OSLOW:$PATH" bash "$OMUT" add "$O/p2" --registry "$O/mut.json" >"$O/mb.log" 2>&1 ) &
  wait
  om_n="$(jq -r '.projects | length' "$O/mut.json" 2>/dev/null)"
  # THE MUTANT MUST HAVE REACHED ITS OWN WRITE PATH, TWICE. "One entry" is also what one dead
  # writer looks like, and the two are indistinguishable from the registry alone — so both
  # reports are read, and a control that only half ran is called BROKEN rather than passing.
  om_wrote=0
  in_str "$(cat "$O/ma.log" 2>/dev/null)" "add: registered" && om_wrote=$((om_wrote + 1))
  in_str "$(cat "$O/mb.log" 2>/dev/null)" "add: registered" && om_wrote=$((om_wrote + 1))
  if [ "$om_wrote" != "2" ]; then
    no "(o3) MUTATION CONTROL: without the lock, one concurrent registration is LOST" \
       "only $om_wrote of the 2 mutant writers reported a successful registration, so this control proves nothing:
       ma.log: $(cat "$O/ma.log" 2>/dev/null)
       mb.log: $(cat "$O/mb.log" 2>/dev/null)"
  elif [ "$om_n" = "1" ]; then
    ok "(o3) MUTATION CONTROL: an engine identical except that the write path takes NO lock loses one of the two registrations — both writers reported success, one entry survives. The lock in (o2) is load-bearing, not decorative"
  else
    no "(o3) MUTATION CONTROL: without the lock, one concurrent registration is LOST" \
       "both mutant writers reported success and the registry holds $om_n entries (want 1) — the race did not occur, so (o2) is not being controlled for"
  fi
fi
[ "$O_MUT_RAN" = "1" ] \
  && ok "(o3b) ANTI-VACUITY: the (o3) mutant was actually built and RUN — an awk whose anchor had moved would yield an identical copy, reddening mutant_ok while silently skipping the control it guards" \
  || no "(o3b) ANTI-VACUITY: the (o3) mutant executed" "mutant_ok rejected it, so the only control over (o2) did not run"

# --- (o4) release is structural: no lock survives ANY path out --------------------------
rm -f "$OREG"
bash "$ENGINE" add "$O/p1" --registry "$OREG" >/dev/null 2>&1
[ ! -e "$OREG.lock" ] \
  && ok "(o4) a SUCCESSFUL write leaves no lock behind — the next verb is not blocked by the last one" \
  || no "(o4) a successful write leaves no lock behind" "$OREG.lock still exists"

# The abort path matters more than the success path: the lock is taken BEFORE the registry is
# read, so an unparseable registry is refused with the lock already held. That branch has no
# release of its own — the EXIT trap is the only one — which is precisely what this asserts.
OBAD="$O/bad.json"
printf 'this is not JSON {{{\n' > "$OBAD" || setup_fail "(o4) fixture: could not write the malformed registry $OBAD"
o_bad_sig="$(csum "$OBAD")"
out="$(bash "$ENGINE" add "$O/p1" --registry "$OBAD" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && in_str "$out" "not valid JSON" && [ ! -e "$OBAD.lock" ] && [ "$o_bad_sig" = "$(csum "$OBAD")" ] \
  && ok "(o5) a REFUSAL taken with the lock already held still releases it — the unparseable-registry branch has no release of its own, so this is the EXIT trap being asserted rather than a per-path release being counted" \
  || no "(o5) a refusal taken with the lock held still releases it" \
       "rc=$rc lock=$([ -e "$OBAD.lock" ] && echo LEFT-BEHIND || echo released) registry-unchanged=$([ "$o_bad_sig" = "$(csum "$OBAD")" ] && echo yes || echo NO) :: $out"

# --- (o6)/(o7) the TIMEOUT branch, and the control that it is the lock saying no ---------
rm -f "$OREG"
( PATH="$OSLOW:$PATH" bash "$ENGINE" add "$O/p1" --registry "$OREG" >/dev/null 2>&1 ) &
o_holder=$!
sleep 1
out="$(bash "$ENGINE" add "$O/p2" --registry "$OREG" --lock-timeout 1 2>&1)"; rc=$?
wait "$o_holder" 2>/dev/null
o_n="$(jq -r '[.projects[] | select(.slug == "p2")] | length' "$OREG" 2>/dev/null)"
[ "$rc" -eq 0 ] && in_str "$out" "ABORTED" && in_str "$out" "$OREG.lock" && in_str "$out" "1s" && [ "$o_n" = "0" ] \
  && ok "(o6) a writer that cannot get the lock within --lock-timeout REFUSES by name — it names the lock path and the timeout, writes nothing, and exits 0 like every other branch in this engine" \
  || no "(o6) a contended writer refuses by name, writes nothing and exits 0" \
       "rc=$rc registered-anyway='$o_n' :: $out"
[ ! -e "$OREG.lock" ] \
  && ok "(o6b) and the holder released the lock when it finished — a timeout refusal does not leave the loser's or the winner's lock behind" \
  || no "(o6b) the lock is gone after the contended pair" "$OREG.lock still exists"
out="$(bash "$ENGINE" add "$O/p2" --registry "$OREG" --lock-timeout 30 2>&1)"; rc=$?
o_n="$(jq -r '[.projects[] | select(.slug == "p2")] | length' "$OREG" 2>/dev/null)"
[ "$rc" -eq 0 ] && [ "$o_n" = "1" ] \
  && ok "(o7) ANTI-VACUITY: the SAME add succeeds once the lock is free — (o6) is the lock refusing, not a blanket refusal that would pass with the feature broken" \
  || no "(o7) ANTI-VACUITY: the same add succeeds once the lock is free" "rc=$rc registered='$o_n' (want 1) :: $out"

# --- (o8)-(o11) the four staleness verdicts ---------------------------------------------
# Each builds the lock BY HAND, in the exact shape a crash would leave, and asserts on what the
# engine then does. The three breaking cases must each name their OWN reason: "the owner is
# gone", "the pid was reused" and "there is no owner and it is old" are three different
# findings, and reporting all three as the first would be claiming something unmeasured.
o_lockcase() {   # <label> -> prints the engine's add output for a hand-built lock
  rm -f "$O/s.json"
  printf '{"version":1,"projects":[]}\n' > "$O/s.json"
  rm -rf "$O/s.json.lock"
  mkdir -p "$O/s.json.lock"
}

o_lockcase
( bash -c 'exit 0' ) & o_dead=$!
wait "$o_dead" 2>/dev/null
printf '%s\n' "$o_dead" > "$O/s.json.lock/owner"
out="$(bash "$ENGINE" add "$O/p1" --registry "$O/s.json" --lock-timeout 2 2>&1)"; rc=$?
o_n="$(jq -r '.projects | length' "$O/s.json" 2>/dev/null)"
[ "$rc" -eq 0 ] && [ "$o_n" = "1" ] && in_str "$out" "stale registry lock" && in_str "$out" "(pid $o_dead) is gone" \
  && ok "(o8) a lock whose recorded owner has EXITED is broken, named as such (pid $o_dead), and the write proceeds — a killed run cannot wedge the registry permanently" \
  || no "(o8) a lock whose owner has exited is broken and named" "rc=$rc entries='$o_n' :: $out"

o_lockcase
sleep 60 & o_alien=$!
printf '%s\n' "$o_alien" > "$O/s.json.lock/owner"
out="$(bash "$ENGINE" add "$O/p1" --registry "$O/s.json" --lock-timeout 2 2>&1)"; rc=$?
kill "$o_alien" 2>/dev/null
o_n="$(jq -r '.projects | length' "$O/s.json" 2>/dev/null)"
[ "$rc" -eq 0 ] && [ "$o_n" = "1" ] && in_str "$out" "now belongs to a different program" \
  && ok "(o9) a lock whose recorded pid is ALIVE but belongs to some other program is treated as a REUSED pid — broken, and named differently from (o8), because 'the owner exited' is not what was observed here" \
  || no "(o9) a live-but-foreign owner pid is treated as reuse and named as such" "rc=$rc entries='$o_n' :: $out"

o_lockcase
out="$(bash "$ENGINE" add "$O/p1" --registry "$O/s.json" --lock-timeout 1 2>&1)"; rc=$?
o_n="$(jq -r '.projects | length' "$O/s.json" 2>/dev/null)"
[ "$rc" -eq 0 ] && [ "$o_n" = "0" ] && in_str "$out" "ABORTED" \
  && ok "(o10) ANTI-VACUITY FOR STALENESS: a FRESH lock carrying no owner yet is NOT broken — that is what a healthy holder looks like between its mkdir and its pid write, so the engine waits and refuses instead. A detector that called everything stale would pass (o8), (o9) and (o11) and fail only here" \
  || no "(o10) a fresh ownerless lock is not broken" \
       "rc=$rc entries='$o_n' (want 0 — the lock was broken, so nothing is protecting a holder mid-acquisition) :: $out"

# Same lock, same shape, one variable changed: its age. It must now break.
touch -t 202001010000 "$O/s.json.lock" 2>/dev/null || setup_fail "(o11) fixture: could not backdate the lock directory"
out="$(bash "$ENGINE" add "$O/p1" --registry "$O/s.json" --lock-timeout 2 2>&1)"; rc=$?
o_n="$(jq -r '.projects | length' "$O/s.json" 2>/dev/null)"
[ "$rc" -eq 0 ] && [ "$o_n" = "1" ] && in_str "$out" "records no owner" \
  && ok "(o11) the SAME ownerless lock, backdated and nothing else changed, IS broken and says why — so (o10)'s refusal is the grace period doing work rather than an ownerless lock never being breakable" \
  || no "(o11) an old ownerless lock is broken and names the reason" "rc=$rc entries='$o_n' :: $out"

# --- (o12) the READ verbs are not gated -------------------------------------------------
# A lock a writer must wait for must NOT stop `list`, `check` or an unconfirmed `scan`: a reader
# is already safe against a writer here, because the registry only ever becomes visible whole
# via `mv`. If reads took the lock, one wedged writer would blind every view of the registry.
o_lockcase
o_t0="$(date +%s)"
out="$(bash "$ENGINE" list --registry "$O/s.json" 2>&1)"; rc=$?
out2="$(bash "$ENGINE" scan "$O" --registry "$O/s.json" 2>&1)"; rc2=$?
o_t1="$(date +%s)"
o_read=$((o_t1 - o_t0))
[ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ] && in_str "$out" "registry:" && in_str "$out2" "scan:" && [ "$o_read" -lt 5 ] \
  && ok "(o12) with a lock held, 'list' and an unconfirmed 'scan' both answer immediately (${o_read}s) — the read verbs take no lock, so a wedged writer cannot blind every view of the registry" \
  || no "(o12) the read verbs are not gated by the lock" \
       "list rc=$rc scan rc=$rc2 elapsed=${o_read}s (a value near the default timeout means the read path is waiting on a writer's lock)"

# --- (o13) a CONFIRMED scan is a writer, and an unconfirmed one is not -------------------
mkdir -p "$O/scanroot/repo-x/.git" || setup_fail "(o13) fixture: could not build the scan fixture"
# RE-STAMP THE LOCK THIS INHERITS FROM (o12). It is an OWNERLESS lock, which the engine breaks
# once it is older than the acquisition grace — so on a host slow enough for (o12)'s two reads
# plus this mkdir to outlast that grace, (o13) would be measuring the stale-break path instead
# of the contended one and would fail for a reason that has nothing to do with `scan`.
touch "$O/s.json.lock" 2>/dev/null || setup_fail "(o13) fixture: could not re-stamp the held lock"
out="$(bash "$ENGINE" scan "$O/scanroot" --confirm --registry "$O/s.json" --lock-timeout 1 2>&1)"; rc=$?
o_n="$(jq -r '.projects | length' "$O/s.json" 2>/dev/null)"
[ "$rc" -eq 0 ] && in_str "$out" "ABORTED" && [ "$o_n" = "0" ] \
  && ok "(o13) 'scan --confirm' is a WRITER and is refused by the same held lock, registering nothing — the verb that takes no lock when it only proposes takes one when it writes" \
  || no "(o13) 'scan --confirm' is gated by the lock" "rc=$rc entries='$o_n' :: $out"
rm -rf "$O/s.json.lock"
out="$(bash "$ENGINE" scan "$O/scanroot" --confirm --registry "$O/s.json" --lock-timeout 5 2>&1)"; rc=$?
o_n="$(jq -r '.projects | length' "$O/s.json" 2>/dev/null)"
[ "$rc" -eq 0 ] && [ "$o_n" -ge 1 ] \
  && ok "(o13b) ANTI-VACUITY: the same confirmed scan registers its candidate once the lock is gone — (o13) is the lock refusing, not a scan that never writes" \
  || no "(o13b) ANTI-VACUITY: the confirmed scan writes once the lock is free" "rc=$rc entries='$o_n' :: $out"

# --- (o14) 'forget' holds the lock too --------------------------------------------------
# Asserted separately rather than reasoned from `add`: the two verbs call reg_prepare on
# different lines, and a lock wired into one of them is exactly the shape this group exists for.
o_fslug="$(jq -r '[.projects[].slug] | first // ""' "$O/s.json" 2>/dev/null)"
[ -n "$o_fslug" ] || setup_fail "(o14) fixture: $O/s.json holds no entry, so the forget assertion would have no subject"
mkdir -p "$O/s.json.lock"
out="$(bash "$ENGINE" forget "$o_fslug" --registry "$O/s.json" --lock-timeout 1 2>&1)"; rc=$?
o_n="$(jq -r --arg s "$o_fslug" '[.projects[] | select(.slug == $s)] | length' "$O/s.json" 2>/dev/null)"
[ "$rc" -eq 0 ] && in_str "$out" "ABORTED" && [ "$o_n" = "1" ] \
  && ok "(o14) 'forget' takes the lock as well — with it held the entry SURVIVES, so a contended forget cannot half-drop a project" \
  || no "(o14) 'forget' is gated by the lock" "rc=$rc entry-still-present='$o_n' (want 1) :: $out"
rm -rf "$O/s.json.lock"
out="$(bash "$ENGINE" forget "$o_fslug" --registry "$O/s.json" --lock-timeout 5 2>&1)"; rc=$?
o_n="$(jq -r --arg s "$o_fslug" '[.projects[] | select(.slug == $s)] | length' "$O/s.json" 2>/dev/null)"
[ "$rc" -eq 0 ] && [ "$o_n" = "0" ] \
  && ok "(o14b) ANTI-VACUITY: the same forget drops the entry once the lock is gone" \
  || no "(o14b) ANTI-VACUITY: the same forget succeeds once the lock is free" "rc=$rc still-present='$o_n' :: $out"

# --- (o15) --lock-timeout gets the same numeric hygiene as --port and --interval ---------
out="$(bash "$ENGINE" add "$O/p1" --registry "$O/hyg.json" --lock-timeout not-a-number 2>&1)"; rc=$?
o_n="$(jq -r '.projects | length' "$O/hyg.json" 2>/dev/null)"
[ "$rc" -eq 0 ] && in_str "$out" "--lock-timeout must be" && [ "$o_n" = "1" ] \
  && ok "(o15) a non-numeric --lock-timeout is reported and falls back rather than reaching arithmetic under 'set -u' — the same hygiene --port and --interval already get, and the verb still does its job" \
  || no "(o15) a non-numeric --lock-timeout is reported and falls back" "rc=$rc entries='$o_n' :: $out"

# --- (o16) the real engine is untouched by the (o3) mutant ------------------------------
o_eng_after="$(csum "$ENGINE")"
o_residue="$(ls "$script_dir"/setup-ui-*.sh 2>/dev/null || true)"
[ -n "$O_ENGINE_SIG_BEFORE" ] && [ "$O_ENGINE_SIG_BEFORE" = "$o_eng_after" ] && [ -z "$o_residue" ] \
  && ok "(o16) the real engine is byte-identical after the (o3) mutation control (sha256 unchanged) and no mutant copy was left in the plugin's scripts directory" \
  || no "(o16) the real engine is byte-identical after the (o3) mutation control" \
       "before='$O_ENGINE_SIG_BEFORE' after='$o_eng_after' residue='$o_residue'"
