# --------------------------------------------------------------------------- #
# plan-waves — read-only wave planner (parallel-automate/04). Its ONLY caller is the
# `--parallel N>1` coordinator (item 05); the sequential loop never calls it, and it is
# never called when N = 1 (`--max 1` is NOT queue order once an item depends on a
# later-numbered one, so the guarantee is by not calling it).
# --------------------------------------------------------------------------- #
#
# plan-waves <runfile|dir|item-list> --max N [--root <checkout>]
# Input: a run file (is_run_file) ⇒ the plan set is its unchecked `- [ ]` Queue rows, and its
# checked rows say which dependencies are merged-done; a directory ⇒ resolve_folder's output;
# any other regular file ⇒ one item path per non-blank, non-`#` line. Queue rows and item-list
# lines are resolved against --root (default `git rev-parse --show-toplevel`, else $PWD).
#
# Grammar (outside ``` fences; a section runs to the next `# `/`## ` heading; blank lines ignored):
#   `## Touches`    — one repo-relative path per line, chars [A-Za-z0-9._/@+-] only, no leading
#                     `/`, no `.` or `..` segment, no `//`; trailing `/` = directory; the sole line
#                     `unknown` = not known. Missing, empty, duplicated, `unknown`-mixed or ANY
#                     bad line ⇒ the WHOLE section is unknown ⇒ the item runs ALONE.
#   `## Depends on` — `none` (sole line), a 1-3 digit id (resolved to the single `NN-*.md` in the
#                     dependent's own directory, numeric equality), or a `*.md` path relative to
#                     the dependent's directory. A section that does not parse = a MISSING one ⇒
#                     the item depends on EVERY earlier plan-set item (input order).
# Every comparison (plan-set membership, Queue lookup, cycles) uses the PHYSICAL absolute path.
# A dependency outside the plan set must be merged-done: a plain `- [x]` Queue row (run-file
# input) or a done `## Status:` line on ANY heading (is_done) — an ABANDONED stamp, and a
# `# skipped:` / `# abandoned:` Queue row mark, win over a done stamp (Phase 4.5 stamps before merge).
# Companion expansion: <root>/.agent/companions.json (strict shape, read with jq) adds paths to
# an item's Touches set — ONE pass, added paths are not re-expanded; `when` is an unquoted,
# case-sensitive bash `case` pattern for a FILE entry (a `"new": true` rule only when the file is
# absent under <root>; `when` and `add` obey the Touches path rules — no leading `/`, no `//`, no
# `.`/`..` segment — so a literal comparison never misses a non-canonical spelling); a DIRECTORY entry `D/` fires a rule when the rule's literal prefix (the
# `when` text before its first glob character) starts with `D/` or `D/` starts with it. Absent ⇒
# one stderr note, no expansion; malformed (or jq missing) ⇒ exit 1 `companions_malformed`.
# Intersection is literal prefix on normalized entries (trailing `/` stripped): a == b, or one
# starts with the other plus `/`. Waves fill greedily in input order, at most N items, no two
# intersecting, an unknown-Touches item alone in its wave.
# Output (stdout, only after the WHOLE plan is computed): `wave <k>: <item> …` lines then one
# `blocked <item>: <why>` per unplaced item; exit 0. Exit 1 with NOTHING on stdout on usage
# errors, `item not found: <item>` (a plan-set entry — Queue row, item-list line or resolve-folder
# result — names no file on disk), an unknown dependency, a dependency cycle, or companions_malformed.
# READ-ONLY: writes only its own `mktemp -d` dir (trap-removed); the only git call is
# `rev-parse --show-toplevel`; never `gh`.
#
# --explain (parallel-automate/10) — same inputs, same `wave`/`blocked` lines and exit codes; then,
# for every PLACED item not in wave 1 (wave order, then input order), `explain <item> (wave <k>):`
# and one indented line per distinct reason it stayed out of an earlier wave, recorded where the
# wave loop made the decision: `conflicts with <item> on <path> (declared)` /
# `conflicts with <item> on <path> (companion: <when>)` (the contained path of the intersecting
# pair; companion when either side's entry came from a companion rule), `depends on <item>`,
# `runs alone: Touches unknown (missing)` / `(unparsable line <N>: "<text>")` / `(declared unknown)`,
# `runs alone: Depends on missing ⇒ depends on every earlier item`, `wave <w> full (--max <N>)`,
# `wave <w> runs <item> alone (Touches unknown)`. A blocked item's reason is its `blocked` line.
# --lint (parallel-automate/10) — `<item|dir|runfile|item-list> --lint`: a directory ⇒
# resolve_folder's output; a run file ⇒ its unchecked Queue rows; any other `*.md` ⇒ that ONE item;
# any other file ⇒ an item list. `--max` is not needed (ignored when given). Per item ONE line
# `<item>: Touches <v>; Depends on <v>`, <v> = `ok` | `ok (declared unknown)` (Touches only) |
# `missing section` | `line <N>: "<text>" — <reason>` [` (+<k> more)`], N = 1-based line in the
# item file; then `<k> of <n> items will run alone: <items|none>` (Touches not known) and
# `<m> of <n> items depend on every earlier item: <items|none>` (Depends on missing). Exit 1 when
# ANY section of ANY item is missing or unparsable, else 0; exit 1 + empty stdout on usage /
# item not found. The verdict is a by-product of the SAME awk pass the planner reads
# (_pw_touches / _pw_depends with a diag file), so lint `ok` ⇔ the planner reads the section as known.

_PW_TMP=""
_PW_EXPLAIN=0
_pw_fail()  { echo "plan-waves: $*" >&2; exit 1; }
_pw_usage() { echo "plan-waves: ${1:-bad usage}" >&2; echo "usage: automate-helpers.sh plan-waves <runfile|dir|item-list> --max N [--explain] [--root <checkout>]" >&2; echo "       automate-helpers.sh plan-waves <item|dir|runfile|item-list> --lint [--root <checkout>]" >&2; exit 1; }

# _pw_abs <path> — "<physical dir>/<basename>"; non-zero when the directory does not exist.
_pw_abs() {
  local d
  d="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s\n' "$d" "$(basename "$1")"
}

# The section parsers. ONE awk pass per section yields BOTH the planner's verdict (stdout, byte-for-
# byte what the planner has always read) and — only when a diag file is given — its diagnosis
# (the --lint / --explain view): `ok`, `declared` (Touches: the sole `unknown`), `missing`, or one
# `bad<TAB><line N><TAB><reason><TAB><text>` row per offending line in line order. Every verdict
# that is not `known`/`none`/ids and not missing/declared carries at least one `bad` row, so the
# lint verdict and the planner's verdict cannot disagree (there is no second grammar to drift).
# Shared awk helpers: _pw_diag records a row; _pw_flush sorts rows by line and writes them.
_PW_AWK_DIAG='
  function _pw_diag(ln, r, s) { if (DG == "") return; gsub(/\t/, " ", s); nd++; DL[nd] = ln; DR[nd] = r; DT[nd] = s }
  function _pw_flush(   a, b, t) {
    for (a = 2; a <= nd; a++) for (b = a; b > 1 && DL[b - 1] > DL[b]; b--) {
      t = DL[b]; DL[b] = DL[b - 1]; DL[b - 1] = t; t = DR[b]; DR[b] = DR[b - 1]; DR[b - 1] = t
      t = DT[b]; DT[b] = DT[b - 1]; DT[b - 1] = t }
    for (a = 1; a <= nd; a++) printf "bad\t%d\t%s\t%s\n", DL[a], DR[a], DT[a] > DG
  }'

# _pw_touches <file> [diag file] — prints `unknown`, or `known` then one RAW entry per line.
# The Touches path grammar on its PW_TOUCHES_GRAMMAR line (charset [A-Za-z0-9._/@+-], no leading `/`,
# no `//`, no `.`/`..` segment) is hand-copied, sharing no code, in automate-dismissed.sh (the
# PATH_TOK / BAD_SEG regexes beside touches_of) and propose-from-verify.sh (vt_touches); change all
# three together — test-automate-helpers.sh §X7 feeds one token set through all three and fails on drift.
_pw_touches() {
  PW_DG="${2:-}" env LC_ALL=C awk "$_PW_AWK_DIAG"'
    # _pw_why — the lint reason for a line the grammar below rejects (diagnosis only; the
    # accept/reject decision is the single PW_TOUCHES_GRAMMAR line, never this function).
    function _pw_why(s,   t) {
      if (s ~ /^- /) return "\"- \" bullet"
      if (index(s, "`")) return "backticks"
      if (s ~ /[()]/) return "parenthetical/prose"
      if (index(s, ",")) return "comma list"
      t = s; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      if (t != s && t !~ /[ \t]/) return "leading/trailing whitespace"
      if (s ~ /[ \t]/) return "parenthetical/prose"
      if (s ~ /^\//) return "leading /"
      if (s ~ /\/\//) return "//"
      if (s ~ /(^|\/)\.\.?(\/|$)/) return ". or .. segment"
      return "character outside [A-Za-z0-9._/@+-]"
    }
    BEGIN { DG = ENVIRON["PW_DG"]; fence = 0; insec = 0; count = 0; n = 0; bad = 0; unk = 0; nd = 0 }
    /^```/ { fence = !fence; if (insec) { bad = 1; _pw_diag(NR, "fenced block inside the section", $0) }; next }
    !fence && (/^# / || /^## /) { insec = 0; if ($0 == "## Touches") { count++; insec = 1; if (count == 1) hl = NR; else _pw_diag(NR, "duplicated section", $0) }; next }
    !insec { next }
    /^[ \t]*$/ { next }
    $0 == "unknown" { unk = 1; if (!ul) ul = NR; next }
    !/^[A-Za-z0-9._\/@+-]+$/ || /^\// || /\/\// || /(^|\/)\.\.?(\/|$)/ { bad = 1; _pw_diag(NR, _pw_why($0), $0); next }   # PW_TOUCHES_GRAMMAR
    { E[++n] = $0 }
    END {
      if (count == 0) { if (DG != "") print "missing" > DG; print "unknown"; exit }   # PW_MISSING_TOUCHES: a missing section runs alone, never an empty set
      if (count > 1 || bad || unk || n == 0) {
        if (DG != "") {
          if (count == 1 && !bad && n == 0 && unk) print "declared" > DG
          else {
            if (unk && n > 0) _pw_diag(ul, "unknown mixed with paths", "unknown")
            if (count == 1 && !bad && n == 0 && !unk) _pw_diag(hl, "empty section", "## Touches")
            _pw_flush()
          }
        }
        print "unknown"; exit
      }
      if (DG != "") print "ok" > DG
      print "known"; for (i = 1; i <= n; i++) print E[i]
    }' "$1"
}

# _pw_depends <file> [diag file] — prints `missing` (absent or unparseable), `none`, or one id/path per line.
_pw_depends() {
  PW_DG="${2:-}" env LC_ALL=C awk "$_PW_AWK_DIAG"'
    BEGIN { DG = ENVIRON["PW_DG"]; fence = 0; insec = 0; count = 0; n = 0; nn = 0; bad = 0; nd = 0 }
    /^```/ { fence = !fence; if (insec) { bad = 1; _pw_diag(NR, "fenced block inside the section", $0) }; next }
    !fence && (/^# / || /^## /) { insec = 0; if ($0 == "## Depends on") { count++; insec = 1; if (count == 1) hl = NR; else _pw_diag(NR, "duplicated section", $0) }; next }
    !insec { next }
    /^[ \t]*$/ { next }
    $0 == "none" { nn++; if (nn == 1) n1 = NR; if (nn == 2) n2 = NR; next }
    /^[0-9][0-9]?[0-9]?$/ { D[++n] = $0; next }
    /^[A-Za-z0-9._\/@+-]+\.md$/ && !/^\// && !/\/\// { D[++n] = $0; next }
    { bad = 1; _pw_diag(NR, "not an id or *.md path", $0) }
    END {
      if (count != 1 || bad || (nn && (n || nn > 1)) || (!nn && !n)) {
        if (DG != "") {
          if (count == 0) print "missing" > DG
          else {
            if (count == 1 && !bad && !nn && !n) _pw_diag(hl, "empty section", "## Depends on")
            if (nn > 1) _pw_diag(n2, "none repeated", "none")
            if (nn && n) _pw_diag(n1, "none mixed with ids", "none")
            _pw_flush()
          }
        }
        print "missing"; exit
      }
      if (DG != "") print "ok" > DG
      if (nn) { print "none"; exit }
      for (i = 1; i <= n; i++) print D[i]
    }' "$1"
}

# _pw_verdict <diag file> — the lint verdict text for one section; exit 0 when it is
# `ok` / `ok (declared unknown)`, 1 when the section is missing or unparsable.
_pw_verdict() {
  local first
  first="$(head -n1 "$1" 2>/dev/null)"
  case "$first" in
    ok) echo ok; return 0 ;;
    declared) echo "ok (declared unknown)"; return 0 ;;
    missing) echo "missing section"; return 1 ;;
  esac
  env LC_ALL=C awk -F '\t' 'NR == 1 { printf "line %s: \"%s\" — %s", $2, $4, $3 }
    END { if (NR > 1) printf " (+%d more)", NR - 1; printf "\n" }' "$1"
  return 1
}

# _pw_touches_why <diag file> — the parenthesised reason in `runs alone: Touches unknown (<why>)`.
_pw_touches_why() {
  case "$(head -n1 "$1" 2>/dev/null)" in
    missing) echo missing ;;
    declared) echo "declared unknown" ;;
    *) env LC_ALL=C awk -F '\t' 'NR == 1 { printf "unparsable line %s: \"%s\"\n", $2, $4; exit }' "$1" ;;
  esac
}

# _pw_resolve_dep <dependent abs path> <id> — prints the dependency's physical absolute path;
# non-zero unless it names exactly one existing regular *.md file.
_pw_resolve_dep() {
  local dir id="$2" f b p hit="" n=0
  dir="$(dirname "$1")"
  case "$id" in
    *.md) f="$dir/$id"; [ -f "$f" ] || return 1; _pw_abs "$f"; return $? ;;
  esac
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"; p="${b%%-*}"
    [ "$p" != "$b" ] || continue
    case "$p" in ""|*[!0-9]*) continue ;; esac
    [ "${#p}" -le 9 ] || continue
    [ "$((10#$p))" -eq "$((10#$id))" ] || continue
    n=$((n+1)); hit="$f"
  done
  [ "$n" -eq 1 ] || return 1
  _pw_abs "$hit"
}

# _pw_abandoned <file> — true when ANY `## Status:` line carries the ABANDONED close-out stamp.
_pw_abandoned() {
  awk 'index($0, "## Status:") == 1 && index($0, "done_with_escalation — ABANDONED") { f = 1 } END { exit f ? 0 : 1 }' "$1" 2>/dev/null
}

# _pw_dep_state <abs path> — `done` | `never <skipped|abandoned>` | `notready <parked|proposed>` | `pending`.
_pw_dep_state() {
  local f="$1" row
  row="$(PW_K="$f" awk -F '\t' '$2 == ENVIRON["PW_K"] { print $1; exit }' "$_PW_TMP/checked")"
  if _pw_abandoned "$f"; then echo "never abandoned"; return 0; fi
  # The owner's Queue row mark outranks the (gitignored) file stamp: Phase 4.5 writes
  # done / done_with_escalation BEFORE any merge, so a `# skipped:` / `# abandoned:` row over a
  # done stamp still never landed.
  case "$row" in skipped|abandoned) echo "never $row"; return 0 ;; esac
  if [ "$row" = done ] || is_done "$f"; then echo done; return 0; fi
  if is_not_ready "$f"; then
    if grep -qE '^## Status:[[:space:]]*parked\b' "$f"; then echo "notready parked"; else echo "notready proposed"; fi
    return 0
  fi
  echo pending
}

# _pw_load_companions <root> — writes $_PW_TMP/rules: `<when>\t<0|1 new>\t<add path>` per add path.
_pw_load_companions() {
  local cf="$1/.agent/companions.json"
  : > "$_PW_TMP/rules"
  if [ ! -e "$cf" ]; then
    echo "plan-waves: no $cf — no companion expansion" >&2
    return 0
  fi
  command -v "$JQ" >/dev/null 2>&1 || _pw_fail "companions_malformed jq not found (needed to read $cf)"
  # `-s` slurps every JSON document into one array and the shape check demands EXACTLY one:
  # `jq -e` alone exits on the LAST document only, so a malformed first document followed by a
  # valid one would pass and have its rules loaded.
  "$JQ" -se '
    length == 1 and (.[0] |
    type == "object" and ((keys - ["companions", "schema_version"]) | length) == 0
    and .schema_version == 1 and (.companions | type) == "array"
    and all(.companions[];
      type == "object" and ((keys - ["add", "new", "when"]) | length) == 0
      and (.when | type) == "string" and (.when | test("^[A-Za-z0-9._/@+*?\\[\\]!-]+$"))
      and (.when | test("^/|//|(^|/)\\.\\.?(/|$)") | not)
      and (.add | type) == "array" and (.add | length) > 0
      and all(.add[]; type == "string" and test("^[A-Za-z0-9._/@+-]+$")
        and (test("^/|//|(^|/)\\.\\.?(/|$)") | not))
      and ((has("new") | not) or .new == true)))' "$cf" >/dev/null 2>&1 \
    || _pw_fail "companions_malformed $cf is not {\"schema_version\":1,\"companions\":[{\"when\":<glob>,[\"new\":true,]\"add\":[<path>,…]},…]}"
  "$JQ" -sr '.[0].companions[] | . as $r | .add[] | [$r.when, (if $r.new then "1" else "0" end), .] | @tsv' "$cf" > "$_PW_TMP/rules" 2>/dev/null \
    || _pw_fail "companions_malformed $cf could not be read"
}

# _pw_expand <raw entries file> <root> <out> — normalized (trailing `/` stripped), sorted, unique
# Touches set plus ONE pass of companion additions.
# Under --explain it also writes <out>.why: `<entry>\t<declared | companion: <when>>` per entry of
# <out> (declared wins when an entry is both), so a conflict can name the rule that added it.
_pw_expand() {
  local e d w nw a pfx tab
  tab="$(printf '\t')"
  : > "$3.raw"; : > "$3.prov"
  while IFS= read -r e; do
    d="${e%/}"
    printf '%s\n' "$d" >> "$3.raw"
    if [ "$_PW_EXPLAIN" = 1 ]; then printf '%s\tdeclared\n' "$d" >> "$3.prov"; fi
    while IFS="$tab" read -r w nw a; do
      if [ "$d" != "$e" ]; then
        pfx="${w%%[*?[]*}"
        case "$pfx" in
          "$d/"*) ;;
          *) case "$d/" in "$pfx"*) ;; *) continue ;; esac ;;
        esac
      else
        # shellcheck disable=SC2254 # unquoted on purpose: `when` is a glob
        case "$e" in $w) ;; *) continue ;; esac
        if [ "$nw" = 1 ] && [ -e "$2/$e" ]; then continue; fi
      fi
      printf '%s\n' "${a%/}" >> "$3.raw"
      if [ "$_PW_EXPLAIN" = 1 ]; then printf '%s\tcompanion: %s\n' "${a%/}" "$w" >> "$3.prov"; fi
    done < "$_PW_TMP/rules"
  done < "$1"
  env LC_ALL=C sort -u "$3.raw" > "$3"
  if [ "$_PW_EXPLAIN" = 1 ]; then
    env LC_ALL=C awk -F '\t' '!($1 in P) || $2 == "declared" { P[$1] = $2 } END { for (p in P) print p "\t" P[p] }' "$3.prov" \
      | env LC_ALL=C sort > "$3.why"
  fi
}

# _pw_conflicts <A.why> <B.why> — one `<path>\t<provenance>` per intersecting pair (the contained,
# i.e. longer, path; `companion: <when>` when either side's entry came from a companion rule, A's first).
_pw_conflicts() {
  env LC_ALL=C awk -F '\t' 'NR == FNR { A[++na] = $1; PA[na] = $2; next }
    { for (i = 1; i <= na; i++) { a = A[i]; b = $1
        if (a == b || index(a, b "/") == 1 || index(b, a "/") == 1) {
          p = (length(b) > length(a)) ? b : a
          v = (PA[i] != "declared") ? PA[i] : $2
          print p "\t" v } } }' "$1" "$2" | env LC_ALL=C sort -u
}

# _pw_intersect <setA> <setB> — true when an entry of A equals, contains or is contained by one of B.
_pw_intersect() {
  [ -s "$1" ] && [ -s "$2" ] || return 1
  awk 'NR == FNR { A[++na] = $0; next }
       { for (i = 1; i <= na; i++) { a = A[i]; b = $0
           if (a == b || index(a, b "/") == 1 || index(b, a "/") == 1) { hit = 1; exit } } }
       END { exit hit ? 0 : 1 }' "$1" "$2"
}

plan_waves() {
  local input="" max="" root="" mode="plan" line p f a i j k n=0 st id ds placed total cnt alone ready changed left msg
  local waitj alonei members m w tv dv rc ka kd la ld tab
  local DISP=() ABS=() TS=() DEPJ=() BLK=() W=() OK=()
  tab="$(printf '\t')"
  _PW_EXPLAIN=0   # reset per call: a prior --explain in the same shell must not leak into a default run
  while [ $# -gt 0 ]; do
    case "$1" in
      --max) [ $# -ge 2 ] || _pw_usage "--max requires a value"; max="$2"; shift 2 ;;
      --root)
        case "${2:-}" in ""|-*) _pw_usage "--root requires a checkout path (got '${2:-}')" ;; esac
        root="$2"; shift 2 ;;
      --explain) [ "$mode" != lint ] || _pw_usage "--explain and --lint are separate modes"; mode=explain; shift ;;
      --lint) [ "$mode" != explain ] || _pw_usage "--explain and --lint are separate modes"; mode=lint; shift ;;
      -*) _pw_usage "unknown option $1" ;;
      *) [ -z "$input" ] || _pw_usage "more than one input ($input, $1)"; input="$1"; shift ;;
    esac
  done
  [ -n "$input" ] || _pw_usage "missing <runfile|dir|item-list>"
  [ -e "$input" ] || _pw_usage "input not found: $input"
  if [ "$mode" != lint ]; then
    case "$max" in ""|*[!0-9]*) _pw_usage "--max must be a positive integer (got '$max')" ;; esac
    [ "${#max}" -le 6 ] && [ "$((10#$max))" -ge 1 ] || _pw_usage "--max must be a positive integer (got '$max')"
    max=$((10#$max))
  fi
  [ "$mode" != explain ] || _PW_EXPLAIN=1
  if [ -z "$root" ]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
    [ -n "$root" ] || root="$PWD"
  fi
  root="$(cd "$root" 2>/dev/null && pwd -P)" || _pw_usage "--root is not a directory"

  _PW_TMP="$(mktemp -d)" || _pw_fail "mktemp -d failed"
  trap 'rm -rf "$_PW_TMP"' EXIT
  : > "$_PW_TMP/checked"; : > "$_PW_TMP/plan"

  # 1. The plan set, as `<display>\t<path to open>` lines.
  if [ -d "$input" ]; then
    resolve_folder "${input%/}" | while IFS= read -r line; do printf '%s\t%s\n' "$line" "$line"; done > "$_PW_TMP/plan"
  elif is_run_file "$input"; then
    env LC_ALL=C awk '
      /^## Queue[ \t]*$/ { q = 1; next }
      /^## / { q = 0 }
      !q { next }
      /^- \[ \] / { p = substr($0, 7); sub(/[ \t]+#.*$/, "", p); sub(/[ \t]+$/, "", p); print "U\t" p; next }
      /^- \[x\] / { p = substr($0, 7); m = "done"
        if (index(p, "# skipped:")) m = "skipped"; else if (index(p, "# abandoned:")) m = "abandoned"
        sub(/[ \t]+#.*$/, "", p); sub(/[ \t]+$/, "", p); print "X\t" m "\t" p }
    ' "$input" > "$_PW_TMP/queue"
    while IFS="$(printf '\t')" read -r st a p; do
      if [ "$st" = U ]; then
        case "$a" in /*) f="$a" ;; *) f="$root/$a" ;; esac
        printf '%s\t%s\n' "$a" "$f" >> "$_PW_TMP/plan"
      else
        case "$p" in /*) f="$p" ;; *) f="$root/$p" ;; esac
        f="$(_pw_abs "$f")" || continue
        printf '%s\t%s\n' "$a" "$f" >> "$_PW_TMP/checked"
      fi
    done < "$_PW_TMP/queue"
  elif [ "$mode" = lint ] && [ -f "$input" ] && case "$input" in *.md) true ;; *) false ;; esac; then
    # --lint only: a `*.md` that is not a run file is ONE item (the planner reads any non-run file
    # as an item list, unchanged).
    printf '%s\t%s\n' "$input" "$input" > "$_PW_TMP/plan"
  elif [ -f "$input" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      case "$line" in ""|"#"*) continue ;; esac
      case "$line" in /*) f="$line" ;; *) f="$root/$line" ;; esac
      printf '%s\t%s\n' "$line" "$f" >> "$_PW_TMP/plan"
    done < "$input"
  else
    _pw_usage "input is neither a run file, a directory nor an item list: $input"
  fi

  # 1b. --lint: per item, the SAME parsers with a diag file; no dependency resolution, no waves.
  if [ "$mode" = lint ]; then
    rc=0; ka=0; kd=0; la=""; ld=""
    : > "$_PW_TMP/out"
    while IFS="$tab" read -r p f; do
      [ -f "$f" ] || _pw_fail "item not found: $p"
      _pw_touches "$f" "$_PW_TMP/tdiag.$n" > "$_PW_TMP/t.$n"
      _pw_depends "$f" "$_PW_TMP/ddiag.$n" > /dev/null
      tv="$(_pw_verdict "$_PW_TMP/tdiag.$n")" || rc=1
      dv="$(_pw_verdict "$_PW_TMP/ddiag.$n")" || rc=1
      if [ "$(head -n1 "$_PW_TMP/t.$n")" != known ]; then ka=$((ka+1)); la="${la:+$la }$p"; fi
      if [ "$(head -n1 "$_PW_TMP/ddiag.$n")" != ok ]; then kd=$((kd+1)); ld="${ld:+$ld }$p"; fi
      printf '%s: Touches %s; Depends on %s\n' "$p" "$tv" "$dv" >> "$_PW_TMP/out"
      n=$((n+1))
    done < "$_PW_TMP/plan"
    printf '%s of %s items will run alone: %s\n' "$ka" "$n" "${la:-none}" >> "$_PW_TMP/out"
    printf '%s of %s items depend on every earlier item: %s\n' "$kd" "$n" "${ld:-none}" >> "$_PW_TMP/out"
    cat "$_PW_TMP/out"
    return "$rc"
  fi

  # 2. Per item: physical path, Touches, Depends.
  while IFS="$(printf '\t')" read -r p f; do
    [ -f "$f" ] || _pw_fail "item not found: $p"
    DISP[n]="$p"; ABS[n]="$(_pw_abs "$f")"
    if [ "$_PW_EXPLAIN" = 1 ]; then _pw_touches "$f" "$_PW_TMP/tdiag.$n" > "$_PW_TMP/t.$n"; else _pw_touches "$f" > "$_PW_TMP/t.$n"; fi
    TS[n]="$(head -n1 "$_PW_TMP/t.$n")"
    sed '1d' "$_PW_TMP/t.$n" > "$_PW_TMP/raw.$n"
    _pw_depends "$f" > "$_PW_TMP/d.$n"
    n=$((n+1))
  done < "$_PW_TMP/plan"

  # 3. Dependencies: in-set edges (DEPJ, " j " list; ids in e.<i>) and out-of-set states (x.<i>).
  i=0
  while [ "$i" -lt "$n" ]; do
    DEPJ[i]=" "; : > "$_PW_TMP/e.$i"; : > "$_PW_TMP/x.$i"
    ds="$(head -n1 "$_PW_TMP/d.$i")"
    if [ "$ds" = missing ]; then
      j=0
      while [ "$j" -lt "$i" ]; do
        DEPJ[i]="${DEPJ[i]}$j "; printf '%s\t%s\n' "$j" "${DISP[j]}" >> "$_PW_TMP/e.$i"; j=$((j+1))
      done
    elif [ "$ds" != none ]; then
      while IFS= read -r id; do
        a="$(_pw_resolve_dep "${ABS[i]}" "$id")" || _pw_fail "unknown dependency $id in ${DISP[i]}"
        j=0; k=-1
        while [ "$j" -lt "$n" ]; do [ "${ABS[j]}" = "$a" ] && { k=$j; break; }; j=$((j+1)); done
        if [ "$k" -ge 0 ]; then
          DEPJ[i]="${DEPJ[i]}$k "; printf '%s\t%s\n' "$k" "$id" >> "$_PW_TMP/e.$i"
        else
          printf '%s\t%s\n' "$(_pw_dep_state "$a")" "$id" >> "$_PW_TMP/x.$i"
        fi
      done < "$_PW_TMP/d.$i"
    fi
    i=$((i+1))
  done

  # 4. Cycles (Kahn): an item resolves once every in-set dependency has; what is left is pruned of
  #    items nothing left depends on, so only the items on (or between) cycles are named.
  i=0; while [ "$i" -lt "$n" ]; do OK[i]=0; i=$((i+1)); done
  : > "$_PW_TMP/order"
  changed=1
  while [ "$changed" -eq 1 ]; do
    changed=0; i=0
    while [ "$i" -lt "$n" ]; do
      if [ "${OK[i]}" -eq 0 ]; then
        ready=1
        for j in ${DEPJ[i]}; do [ "${OK[j]}" -eq 1 ] || ready=0; done
        if [ "$ready" -eq 1 ]; then OK[i]=1; changed=1; echo "$i" >> "$_PW_TMP/order"; fi
      fi
      i=$((i+1))
    done
  done
  left=0; i=0; while [ "$i" -lt "$n" ]; do [ "${OK[i]}" -eq 1 ] || left=$((left+1)); i=$((i+1)); done
  if [ "$left" -gt 0 ]; then
    changed=1
    while [ "$changed" -eq 1 ]; do
      changed=0; i=0
      while [ "$i" -lt "$n" ]; do
        if [ "${OK[i]}" -eq 0 ]; then
          ready=0; j=0
          while [ "$j" -lt "$n" ]; do
            if [ "${OK[j]}" -eq 0 ]; then case "${DEPJ[j]}" in *" $i "*) ready=1 ;; esac; fi
            j=$((j+1))
          done
          [ "$ready" -eq 1 ] || { OK[i]=2; changed=1; }
        fi
        i=$((i+1))
      done
    done
    msg=""; i=0
    while [ "$i" -lt "$n" ]; do [ "${OK[i]}" -eq 0 ] && msg="$msg ${DISP[i]}"; i=$((i+1)); done
    _pw_fail "dependency cycle:$msg"
  fi

  # 5. Blocked (dependency order): an out-of-set dependency not merged-done, or a blocked in-set one.
  i=0; while [ "$i" -lt "$n" ]; do BLK[i]=""; W[i]=0; i=$((i+1)); done
  while IFS= read -r i; do
    while IFS="$(printf '\t')" read -r st id; do
      [ -z "${BLK[i]}" ] || break
      case "$st" in
        done) ;;
        "never "*) BLK[i]="waits on $id (${st#never } — never landed)" ;;
        "notready "*) BLK[i]="depends on ${st#notready } $id" ;;
        *) BLK[i]="waits on $id" ;;
      esac
    done < "$_PW_TMP/x.$i"
    while IFS="$(printf '\t')" read -r j id; do
      [ -z "${BLK[i]}" ] || break
      [ -z "${BLK[j]}" ] || BLK[i]="waits on $id"
    done < "$_PW_TMP/e.$i"
  done < "$_PW_TMP/order"

  # 6. Companion-expanded Touches sets for every placeable known-Touches item.
  _pw_load_companions "$root"
  total=0; i=0
  while [ "$i" -lt "$n" ]; do
    if [ -z "${BLK[i]}" ]; then
      total=$((total+1))
      [ "${TS[i]}" = known ] && _pw_expand "$_PW_TMP/raw.$i" "$root" "$_PW_TMP/s.$i"
    fi
    i=$((i+1))
  done

  # 7. Waves: greedy, input order, deps in earlier waves, <= max items, no intersection, unknown alone.
  #    Under --explain the scan does not stop at a full / alone wave (nothing more can be placed in
  #    it either way) so every unplaced item gets its reason recorded where the decision is made.
  : > "$_PW_TMP/out"
  placed=0; k=0
  while [ "$placed" -lt "$total" ]; do
    k=$((k+1)); cnt=0; alone=0; alonei=""; members=""; line=""; : > "$_PW_TMP/wave"
    i=0
    while [ "$i" -lt "$n" ]; do
      if [ -z "${BLK[i]}" ] && [ "${W[i]}" -eq 0 ]; then
        ready=1; waitj=""
        for j in ${DEPJ[i]}; do { [ "${W[j]}" -ge 1 ] && [ "${W[j]}" -lt "$k" ]; } || { ready=0; waitj="$waitj $j"; }; done
        if [ "$ready" -eq 1 ]; then
          if [ "$alone" -ne 0 ] || [ "$cnt" -ge "$max" ]; then
            [ "$_PW_EXPLAIN" = 1 ] || break
            if [ "$alone" -ne 0 ]; then
              printf 'wave %s runs %s alone (Touches unknown)\n' "$k" "${DISP[alonei]}" >> "$_PW_TMP/why.$i"
            else
              printf 'wave %s full (--max %s)\n' "$k" "$max" >> "$_PW_TMP/why.$i"
            fi
          elif [ "${TS[i]}" != known ]; then
            if [ "$cnt" -eq 0 ]; then
              W[i]=$k; alone=1; alonei=$i; cnt=1; line="${DISP[i]}"
            elif [ "$_PW_EXPLAIN" = 1 ]; then
              printf 'runs alone: Touches unknown (%s)\n' "$(_pw_touches_why "$_PW_TMP/tdiag.$i")" >> "$_PW_TMP/why.$i"
            fi
          elif [ "$cnt" -eq 0 ] || ! _pw_intersect "$_PW_TMP/s.$i" "$_PW_TMP/wave"; then
            W[i]=$k; cnt=$((cnt+1)); line="${line:+$line }${DISP[i]}"; members="$members $i"
            cat "$_PW_TMP/s.$i" >> "$_PW_TMP/wave"
          elif [ "$_PW_EXPLAIN" = 1 ]; then
            for m in $members; do
              _pw_conflicts "$_PW_TMP/s.$i.why" "$_PW_TMP/s.$m.why" | while IFS="$tab" read -r p a; do
                printf 'conflicts with %s on %s (%s)\n' "${DISP[m]}" "$p" "$a"
              done >> "$_PW_TMP/why.$i"
            done
          fi
        elif [ "$_PW_EXPLAIN" = 1 ]; then
          if [ "$(head -n1 "$_PW_TMP/d.$i")" = missing ]; then
            printf 'runs alone: Depends on missing ⇒ depends on every earlier item\n' >> "$_PW_TMP/why.$i"
          else
            for j in $waitj; do printf 'depends on %s\n' "${DISP[j]}" >> "$_PW_TMP/why.$i"; done
          fi
        fi
      fi
      i=$((i+1))
    done
    [ "$cnt" -gt 0 ] || _pw_fail "internal: no placeable item for wave $k"
    placed=$((placed+cnt))
    printf 'wave %s: %s\n' "$k" "$line" >> "$_PW_TMP/out"
  done
  i=0
  while [ "$i" -lt "$n" ]; do
    [ -z "${BLK[i]}" ] || printf 'blocked %s: %s\n' "${DISP[i]}" "${BLK[i]}" >> "$_PW_TMP/out"
    i=$((i+1))
  done
  # 8. --explain: one block per placed item not in wave 1 (wave order, then input order), each
  #    distinct reason once, in the order first recorded.
  if [ "$_PW_EXPLAIN" = 1 ]; then
    w=2
    while [ "$w" -le "$k" ]; do
      i=0
      while [ "$i" -lt "$n" ]; do
        if [ -z "${BLK[i]}" ] && [ "${W[i]}" -eq "$w" ]; then
          printf 'explain %s (wave %s):\n' "${DISP[i]}" "$w" >> "$_PW_TMP/out"
          if [ -f "$_PW_TMP/why.$i" ]; then
            awk '!seen[$0]++ { print "  " $0 }' "$_PW_TMP/why.$i" >> "$_PW_TMP/out"
          fi
        fi
        i=$((i+1))
      done
      w=$((w+1))
    done
  fi
  cat "$_PW_TMP/out"
}

