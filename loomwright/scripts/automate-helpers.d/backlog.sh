# --help usage (the `#:  ` lines): this family's segment of automate-helpers.sh --help, assembled
# by the dispatcher's _ah_usage in _AH_HELP_SEGMENTS order; fixture: fixtures/automate-helpers-help/backlog.golden.
#:  item-state       <item> [--json] [--root <checkout>]  # parallel-automate/18a: READ-ONLY — the ONE status reader: prints `<state>\t<item>\t<evidence>` (state from the closed set done|abandoned|parked|proposed|brief_shipped|merged_unstamped|pr_open|in_flight|conflict|open|unknown, first match of the precedence in the backlog.sh header) plus one `stale_run\t<run file>\t<reason>` row per unfinished run whose ## Current the item's own stamp beats; --json prints ONE object; exit 1 on usage / item not found
#:  backlog          [--json] [--state <s>] [--unknown | --verify-list [<item>...]] [--root <checkout>]  # parallel-automate/18a: READ-ONLY board — every requirement item (the _rs_skip_path set) once, grouped by folder, with item-state's state + evidence, run / lane, PR and a right-size column (ONE `right-size --json` call; failure ⇒ `unknown`), totals summing to the item count and `stale_run` runs; ONE cached `gh pr list` read per state (merged, open), gh failing ⇒ every PR field `unverified` + header `github: unverified`; --state filters rows (totals stay whole-tree); --unknown lists unknown + brief_shipped items with a suggested fix; --verify-list lists items with no merge evidence (brief_shipped, unknown, conflict, or the named items) with candidate merged PRs; writes nothing; exit 1 on usage
#:  backlog-stamp    <item> <done|done_with_escalation|abandoned|kept-open> [--pr <url>]... [--owed <text>] [--reason <text>] [--supersedes <run_id>] [--date YYYY-MM-DD] [--root <checkout>] --confirm  # parallel-automate/18a: the owner-approved stamp writer — appends exactly the engine shape (done / done_with_escalation: closeout's sentinel + `## Status:` + Completed + Brief + one PR line per --pr [+ Owed]; abandoned: `## Status: done_with_escalation — ABANDONED (<reason>)`; kept-open: `- **Kept open:** <date> — supersedes <run_id>`) to ONE file under <root>/.supervisor/requirements/; without --confirm prints the block and writes nothing; refuses (exit 1, nothing written) an already-done item, a path outside the requirements tree, and an absolute home path in any argument

# --------------------------------------------------------------------------- #
# backlog — every requirement item's real state, derived from evidence (parallel-automate/18a).
# --------------------------------------------------------------------------- #
#
# A requirement's first `## Status:` line is not updated on merge (closeout APPENDS its done stamp),
# so a hand count of "pending" first lines over-counts open work and re-offers shipped work. Nothing
# here is a hand-kept label: every value is recomputed from the sources on every run.
#
# THE ITEM SET: every `*.md` under <root>/.supervisor/requirements/ minus the files _rs_skip_path
# (automate-helpers.d/reconcile-status.sh) skips — that function is the list, never restated here.
# `proposed/` files are items.
#
# STATES (the ONE closed set, _BL_STATES; each item reads exactly one, the board counts each once):
# done abandoned parked proposed brief_shipped merged_unstamped pr_open in_flight conflict open unknown.
# One RUN state, `stale_run`, is listed under "runs needing attention" and never counted as an item.
#
# PRECEDENCE (first match wins; the evidence names the line it rests on):
#  1. The item's own stamp. is_done (ANY `## Status:` line — so a done stamp appended under a
#     first-line `pending` reads done) ⇒ `done`, or `abandoned` when the last terminal line is
#     `## Status: done_with_escalation — ABANDONED (…)`. A first status line `parked (merged … into X)`
#     / `parked (split … into X)` reads X's state and names X (followed hop by hop; a cycle or more
#     than 8 hops ⇒ `unknown (parked chain cycle)`; a target that does not resolve ⇒ `parked`). Any
#     other `parked` ⇒ `parked`. A `proposed` first status line, or a file under `proposed/` ⇒
#     `proposed`. An unfinished run whose ## Current names such an item is listed `stale_run`.
#  2. Merge evidence with no done stamp ⇒ `merged_unstamped`: a run file's plain `- [x] <path>` row
#     (no `  # ` suffix), a `fleet closeout: <lane> <path> done` line, or a merged PR from the
#     cached list that names a DISTINCTIVE key of the item as a whole token. The keys: the slug
#     (basename without `.md`) only when it carries an `NN-`/`NNa-` id prefix, and the
#     folder-qualified slug `<folder>/<slug>` / `<folder>-<slug>` — each only when no other item
#     of the whole item set yields the same key (`pk/01-fix` and `qq/01-fix` share `01-fix`, so
#     only their folder-qualified keys count). A PR names a key when its
#     headRefName equals it or ends with `/<key>` (or `-<key>`, id-prefixed slug only), or its
#     title holds it with no [A-Za-z0-9_/-] after and no [A-Za-z0-9] before (nor `_`/`-` before a
#     folder-qualified key). A bare id-less slug (`spec`), a substring hit (`x01-fix` for `01-fix`),
#     a longer sibling (`01-fix-guard` for `01-fix`, `sub-bl/spec` for `bl/spec`) or a longer path
#     (`bl/spec/notes` for `bl/spec`) is never evidence — only a `--verify-list` candidate. A
#     false match here would hide steps 3–4, so the rule errs toward no match.
#  3. `conflict` — _bl_is_conflict below (owner decision D-conflict-1).
#  4. A live claim: an unfinished run's (is_run_file, not is_done) `## Current` item, else a lane's
#     item from `lane-status --json` (`.lanes[]`, a removed / abandoned lane excluded; absent or
#     failing output ⇒ no lane claims) ⇒ `in_flight` naming the run or lane; `pr_open` when the
#     claim's PR is in the cached OPEN list.
#  5. A first status line `brief-shipped` ⇒ `brief_shipped`; explicit `pending` / `ready`
#     (_rs_first_status_open) ⇒ `open` (`unknown` when github is unverified, below); anything
#     else ⇒ `unknown`, with the offending line or `no status line`.
# GITHUB: exactly two reads per pass, `gh pr list --state merged|open --limit $_BL_PR_LIMIT`. Either
# failing (or not JSON) ⇒ `github: unverified`: every item's pr_state reads `unverified`, step 2's PR
# lookup is skipped, a claim stays `in_flight` (never `pr_open`), and an item that would read `open`
# reads `unknown` with `(merged-PR lookup unverified)` in its evidence — no item reads `open` or
# `pr_open` because of the failure, and `--verify-list` says its candidates are unverified.
# RIGHT-SIZE (board only): ONE `right-size <item list> --json --root <root>` call over the whole item
# list, joined on its `item` display name; any failure ⇒ the column reads `unknown`, nothing else.
#
# READ-ONLY (item-state, backlog): writes only its own mktemp dir (trap-removed); never git; `gh`
# only for the two list reads. NO ABSOLUTE PATHS in any printed row: paths are repo-relative.
#
# backlog-stamp is the one writer here (the dispatcher header's carve-out): one requirement file,
# only under --confirm, appended through a temp copy + mv; never git, never `gh`.
#
# TEST SEAMS (tests only — never set them in a real run): LOOMWRIGHT_LANE_STATUS_BIN names a command
# run as `<bin> --json` in <root> instead of the sibling `automate-lanes.sh lane-status --json`;
# LOOMWRIGHT_RIGHT_SIZE_BIN names a command run as `<bin> <item list> --json --root <root>` instead of
# this process's own right_size. Each only replaces where the data comes from, never how it is read.


_BL_STATES="done abandoned parked proposed brief_shipped merged_unstamped pr_open in_flight conflict open unknown"
_BL_PR_LIMIT=1000
_BL_DATE_RE='([0-9]{4}-[0-9]{2}-[0-9]{2})'
_BL_TMP=""
_BL_HERE=""
_BL_US=$'\037'
_BL_RE_PARKED='^## Status:[[:space:]]*parked([^A-Za-z0-9_-]|$)'
_BL_RE_PROPOSED='^## Status:[[:space:]]*proposed([^A-Za-z0-9_-]|$)'
_BL_RE_SHIPPED='^## Status:[[:space:]]*brief-shipped([^A-Za-z0-9_-]|$)'

_bl_fail() { echo "$1: $2" >&2; exit 1; }

# _bl_clean <text> — sets BL_C: one line, tabs and separator bytes as spaces (a field never splits).
_bl_clean() {
  local s="$1"
  s="${s//$'\t'/ }"; s="${s//$'\r'/ }"; s="${s//$'\n'/ }"
  s="${s//$'\035'/ }"; s="${s//$'\036'/ }"; s="${s//$'\037'/ }"
  BL_C="$s"
}

# _bl_is_conflict <item abs> <item repo-rel> <automate_dir> [<run file>] — owner decision
# D-conflict-1, the ONE definition of `conflict` (reconcile-status's guard calls it too). True when
# the item is not done, its FIRST `## Status:` line is explicit pending/ready (_rs_first_status_open),
# and some `- [x] <rel>  # abandoned: …` / `# skipped: …` row in a `*.md` under <automate_dir> (only
# <run file> when given) is NOT settled. A row is settled by a `- **Kept open:** <YYYY-MM-DD> —
# supersedes <run_id>` line in the item: a dated row by any marker dated on or after its run_id's
# date, an undated run_id only by a marker that names that run_id. On true, prints the latest
# unsettled row as `<run file repo-rel>\t<run_id>\t<run date|undated>\t<row verbatim>`.
_bl_is_conflict() {
  local f="$1" rel="$2" adir="$3" only="${4:-}" kd=0 ids=" " m d rid rf rdate rdn out line hit="" proj files
  [ -f "$f" ] || return 1
  is_done "$f" && return 1
  _rs_first_status_open "$f" || return 1
  while IFS= read -r m; do
    d=""; if [[ "$m" =~ $_BL_DATE_RE ]]; then d="${BASH_REMATCH[1]}"; fi
    if [ -n "$d" ] && [ "${d//-/}" -gt "$kd" ]; then kd="${d//-/}"; fi
    case "$m" in *"supersedes "*) rid="${m##*supersedes }"; rid="${rid%% *}"; ids="$ids$rid " ;; esac
  done < <(grep -E '^- \*\*Kept open:\*\*' "$f" 2>/dev/null)
  proj="${adir%/.supervisor/automate}"
  if [ -n "$only" ]; then files=("$only"); else files=("$adir"/*.md); fi
  while IFS= read -r out; do
    rf="${out%%.md:*}.md"; line="${out#*.md:}"
    case "$line" in
      "- [x] $rel  # abandoned: "*|"- [x] $rel  # skipped: "*) ;;
      *) continue ;;
    esac
    rid="${rf##*/}"; rid="${rid%.md}"; rdate=undated
    if [[ "$rid" =~ $_BL_DATE_RE ]]; then rdate="${BASH_REMATCH[1]}"; fi
    if [ "$rdate" = undated ]; then
      case "$ids" in *" $rid "*) continue ;; esac
    else
      rdn="${rdate//-/}"
      if [ "$rdn" -le "$kd" ]; then continue; fi
    fi
    hit="${rf#"$proj"/}	$rid	$rdate	$line"
  done < <(grep -H -F -- "- [x] $rel  # " "${files[@]}" 2>/dev/null)
  [ -n "$hit" ] || return 1
  printf '%s\n' "$hit"
}

# _bl_resolve <given> <root> — the physical path of an item named as given (cwd-relative,
# root-relative, requirements-relative, each with or without `.md`); non-zero when none exists.
_bl_resolve() {
  local g="$1" root="$2" c
  for c in "$g" "$g.md" "$root/$g" "$root/$g.md" "$root/.supervisor/requirements/$g" "$root/.supervisor/requirements/$g.md"; do
    case "$g" in /*) case "$c" in "$g"|"$g.md") ;; *) continue ;; esac ;; esac
    if [ -f "$c" ]; then _pw_abs "$c"; return $?; fi
  done
  return 1
}

# _bl_items <root> — the item set (header), one physical path per line, sorted. _rs_skip_path runs
# with right-size's fork-free basename / dirname stand-ins (its own rules, no exec per file).
_bl_items() {
  (
    basename() { _rsz_basename "$@"; }
    dirname() { _rsz_dirname "$@"; }
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      _rs_skip_path "$f" "$1" && continue
      printf '%s\n' "$f"
    done < <(find "$1/.supervisor/requirements" -type f -name '*.md' 2>/dev/null | env LC_ALL=C sort)
  )
}

# _BL_RUNS_AWK — one run file ⇒ index rows (`live` = 1 for an unfinished run file):
#   X\t<path>\t<run file>                       a plain `- [x] <path>` row
#   A\t<path>\t<run file>\t<row>                a `- [x] <path>  # abandoned: | # skipped: …` row
#   F\t<path>\t<run file>\t<pr|"">              a `fleet closeout: <lane> <path> done (PR <url>)` line
#   C\t<path>\t<run file>\t<pr|"">\t<status>    an unfinished run's `## Current` item
_BL_RUNS_AWK='
  function norm(p) { sub(/^\.\//, "", p); sub(/[ \t]+$/, "", p); return p }
  { l = $0; sub(/\r$/, "", l) }
  /^## / { sec = l; sub(/[ \t]+$/, "", sec) }
  substr(l, 1, 6) == "- [x] " {
    p = substr(l, 7)
    if (index(p, "  # abandoned: ") || index(p, "  # skipped: ")) { q = p; sub(/  # .*/, "", q); print "A\t" norm(q) "\t" rf "\t" l }
    else if (!index(p, "  #")) print "X\t" norm(p) "\t" rf
    next
  }
  index(l, "fleet closeout: ") {
    x = l; sub(/.*fleet closeout: /, "", x)
    n = split(x, a, " ")
    if (n >= 3 && a[1] ~ /^L[0-9]+$/ && a[3] == "done") {
      pr = ""; if (match(x, /\(PR https:[^ )]*/)) pr = substr(x, RSTART + 4, RLENGTH - 4)
      print "F\t" norm(a[2]) "\t" rf "\t" pr
    }
  }
  live && sec == "## Current" && substr(l, 1, 8) == "- item: " {
    it = substr(l, 9); sub(/ \|.*/, "", it); it = norm(it)
    pr = ""; if (match(l, /\| pr: [^ |]+/)) pr = substr(l, RSTART + 6, RLENGTH - 6)
    st = ""; if (match(l, /\| status: [^ |]+/)) st = substr(l, RSTART + 10, RLENGTH - 10)
    if (pr == "null" || pr == "-") pr = ""
    if (it != "" && it != "null") print "C\t" it "\t" rf "\t" pr "\t" st
  }'

# _BL_PREP_AWK — ONE pass joining every per-item fact (BEGIN-only: the item list, the run index, the
# lane rows and both PR lists are read with getline, so no argument list grows with the tree). One
# \037-separated row per item, in list order:
#    abs rel disp first_status last_done_line last_dated x_rf f_rf f_pr c_rf c_pr c_all(\036) a_n
#    lane lane_state lane_pr m_num m_url cand(\036 rows of num\035url\035title) c_pr_open lane_pr_open
#    m_key
# last_done_line only DISPLAYS which terminal line is_done matched; whether the item is done is
# always is_done's answer. The PR match is the precedence-2 rule (whole-token, on a distinctive key
# only — see the header); m_key names the key and where it matched. Candidates are the looser
# `--verify-list` match (the slug without its leading `NN-`/`NNa-` id, case-insensitive, head or
# title), at most 3 — a candidate is never merge evidence.
_BL_PREP_AWK='
  function g(f, k, v) { return (k in v) ? v[k] : "" }
  # tok(s, t, fq) — t occurs in s as a whole token: the character after is not [A-Za-z0-9_-] (a
  # longer sibling slug `11-conflict-guard` never names `11-conflict`) nor `/` (a longer path:
  # `bl/spec/notes` never names `bl/spec`), the character before is not [A-Za-z0-9] — nor `_`/`-`
  # when t is folder-qualified (fq: `sub-bl/spec` never names `bl/spec`)
  function tok(s, t, fq,   off, i, b, a) {
    if (t == "") return 0
    off = 0
    while ((i = index(substr(s, off + 1), t)) > 0) {
      i += off; b = (i == 1) ? "" : substr(s, i - 1, 1); a = substr(s, i + length(t), 1)
      if (b !~ /[A-Za-z0-9]/ && !(fq && b ~ /[_-]/) && a !~ /[A-Za-z0-9_\/-]/) return 1
      off = i
    }
    return 0
  }
  # headm(h, t, fq) — the branch h is t, or ends with `/t` or (t not folder-qualified) `-t`
  function headm(h, t, fq,   c) {
    if (t == "") return 0
    if (h == t) return 1
    if (length(h) <= length(t) || substr(h, length(h) - length(t) + 1) != t) return 0
    c = substr(h, length(h) - length(t), 1)
    return (c == "/" || (c == "-" && !fq))
  }
  # keys(f) — the distinctive keys of item f into K1 K2 K3: the id-prefixed slug (`NN-…`), and the
  # folder-qualified slug (`<folder>/<slug>`, `<folder>-<slug>`); a bare id-less slug (`spec`) is
  # never one
  function keys(f,   slug, fd) {
    slug = f; sub(/.*\//, "", slug); sub(/\.md$/, "", slug)
    K1 = (slug ~ /^[0-9]+[a-z]?-./) ? slug : ""
    fd = substr(f, length(root) + 2); sub(/^\.supervisor\/requirements\//, "", fd); K2 = ""; K3 = ""
    if (sub(/\/[^\/]*$/, "", fd)) { sub(/.*\//, "", fd); K2 = fd "/" slug; K3 = fd "-" slug }
  }
  # own(k, f) — k, unless another item of the whole item set also owns it (`pk/01-foo` and
  # `qq/01-foo` share `01-foo`; `bl/spec` and `x/bl/spec` share `bl/spec`): a shared key cannot
  # say which item a PR shipped, so it is no key at all (the item keeps its candidates)
  function own(k, f) { return (k == "" || (k in KS) || ((k in KO) && KO[k] != f)) ? "" : k }
  BEGIN {
    FS = "\t"; US = "\037"; RS1 = "\036"; GS = "\035"
    while ((getline l < runs) > 0) {
      split(l, a, "\t"); k = a[1]; p = a[2]
      if (k == "X") { if (!(p in X)) X[p] = a[3] }
      else if (k == "F") { if (!(p in F)) { F[p] = a[3]; FP[p] = a[4] } }
      else if (k == "C") { if (!(p in C)) { C[p] = a[3]; CP[p] = a[4] }; CA[p] = ((p in CA) ? CA[p] RS1 : "") a[3] }
      else if (k == "A") AN[p]++
    }
    while ((getline l < lanes) > 0) { split(l, a, "\t"); if (a[1] != "" && !(a[1] in LL)) { LL[a[1]] = a[2]; LS[a[1]] = a[3]; LP[a[1]] = a[4] } }
    nm = 0
    while ((getline l < merged) > 0) { nm++; split(l, a, "\t"); MN[nm] = a[1]; MU[nm] = a[2]; MH[nm] = a[3]; MT[nm] = a[4]; ML[nm] = tolower(a[3] " " a[4]) }
    while ((getline l < open) > 0) { split(l, a, "\t"); if (a[2] != "") O[a[2]] = 1 }
    # every key of the WHOLE item set (not just <list>, which item-state narrows to one item) and its
    # owner; a key a second item also yields is marked shared (KS)
    while ((getline f < items) > 0) {
      keys(f); kk[1] = K1; kk[2] = K2; kk[3] = K3
      for (j = 1; j <= 3; j++) if (kk[j] != "") { if ((kk[j] in KO) && KO[kk[j]] != f) KS[kk[j]] = 1; else KO[kk[j]] = f }
    }
    close(items)   # the board passes the same file as <list>: reopen it from the start
    while ((getline f < list) > 0) {
      rel = substr(f, length(root) + 2); disp = rel
      sub(/^\.supervisor\/requirements\//, "", disp); sub(/\.md$/, "", disp)
      fs = ""; ld = ""; sd = ""
      while ((getline l < f) > 0) {
        sub(/\r$/, "", l)
        st = (substr(l, 1, 10) == "## Status:")
        if (st) { if (fs == "") fs = l; if (l ~ /^## Status:[ \t]*done/) ld = l }
        if ((st || index(l, "- **Completed:**") == 1 || index(l, "- **Kept open:**") == 1) \
            && match(l, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) sd = substr(l, RSTART, RLENGTH)
      }
      close(f)
      slug = f; sub(/.*\//, "", slug); sub(/\.md$/, "", slug)
      key = slug; sub(/^[0-9]+[a-z]?-/, "", key); lk = tolower(key)
      keys(f); k1 = own(K1, f); k2 = own(K2, f); k3 = own(K3, f)
      mn = ""; mu = ""; mk = ""; cand = ""; nc = 0
      for (i = 1; i <= nm; i++) {
        h = MH[i]
        if (mn == "") {
          if (headm(h, k1, 0)) mk = k1 " (head " h ")"
          else if (headm(h, k2, 1)) mk = k2 " (head " h ")"
          else if (headm(h, k3, 1)) mk = k3 " (head " h ")"
          else if (tok(MT[i], k1, 0)) mk = k1 " (title)"
          else if (tok(MT[i], k2, 1)) mk = k2 " (title)"
          else if (tok(MT[i], k3, 1)) mk = k3 " (title)"
          if (mk != "") { mn = MN[i]; mu = MU[i] }
        }
        if (nc < 3 && lk != "" && index(ML[i], lk)) { cand = cand (nc ? RS1 : "") MN[i] GS MU[i] GS MT[i]; nc++ }
      }
      lk2 = (rel in LL) ? rel : ((disp in LL) ? disp : "")
      lane = ""; lst = ""; lpr = ""
      if (lk2 != "") { lane = LL[lk2]; lst = LS[lk2]; lpr = LP[lk2] }
      cp = g(f, rel, CP)
      printf "%s", f US rel US disp US fs US ld US (sd == "" ? "undated" : sd) US g(f, rel, X) US g(f, rel, F) US g(f, rel, FP) US g(f, rel, C) US cp US g(f, rel, CA) US ((rel in AN) ? AN[rel] : 0)
      printf "%s\n", US lane US lst US lpr US mn US mu US cand US ((cp != "" && (cp in O)) ? 1 : 0) US ((lpr != "" && (lpr in O)) ? 1 : 0) US mk
    }
  }'

# _bl_context <root> — load the per-pass sources into $_BL_TMP: runs (the index above), merged.tsv /
# open.tsv (`<number>\t<url>\t<headRefName>\t<title>`, _BL_GH verified or unverified) and lanes.tsv
# (`<item>\t<lane>\t<state>\t<pr>`).
_bl_context() {
  local root="$1" rf live j1 j2 rc1=0 rc2=0 lj
  _BL_ROOT="$root"; _BL_ADIR="$root/.supervisor/automate"
  : > "$_BL_TMP/runs"; : > "$_BL_TMP/merged.tsv"; : > "$_BL_TMP/open.tsv"; : > "$_BL_TMP/lanes.tsv"; : > "$_BL_TMP/stale"
  for rf in "$_BL_ADIR"/*.md; do
    [ -f "$rf" ] || continue
    live=0
    if is_run_file "$rf" && ! is_done "$rf"; then live=1; fi
    env LC_ALL=C awk -v rf="${rf#"$root"/}" -v live="$live" "$_BL_RUNS_AWK" "$rf" >> "$_BL_TMP/runs" 2>/dev/null
  done
  j1="$(cd "$root" && "$GH" pr list --state merged --limit "$_BL_PR_LIMIT" --json number,url,title,headRefName 2>/dev/null)" || rc1=$?
  j2="$(cd "$root" && "$GH" pr list --state open --limit "$_BL_PR_LIMIT" --json number,url,title,headRefName 2>/dev/null)" || rc2=$?
  _BL_GH=unverified
  if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] \
     && "$JQ" -e 'type == "array"' >/dev/null 2>&1 <<<"$j1" && "$JQ" -e 'type == "array"' >/dev/null 2>&1 <<<"$j2"; then
    _BL_GH=verified
    "$JQ" -r '.[] | [(.number | tostring), (.url // ""), (.headRefName // ""), ((.title // "") | gsub("[\t\r\n\u001d-\u001f]"; " "))] | @tsv' <<<"$j1" > "$_BL_TMP/merged.tsv" 2>/dev/null
    "$JQ" -r '.[] | [(.number | tostring), (.url // ""), (.headRefName // ""), ((.title // "") | gsub("[\t\r\n\u001d-\u001f]"; " "))] | @tsv' <<<"$j2" > "$_BL_TMP/open.tsv" 2>/dev/null
  fi
  if [ -n "${LOOMWRIGHT_LANE_STATUS_BIN:-}" ]; then
    lj="$(cd "$root" && "$LOOMWRIGHT_LANE_STATUS_BIN" --json 2>/dev/null)" || lj=""
  else
    lj="$(cd "$root" && bash "$_BL_HERE/automate-lanes.sh" lane-status --json 2>/dev/null)" || lj=""
  fi
  "$JQ" -r '.lanes[]? | select(.state != "removed" and .state != "abandoned")
    | [((.item // "") | sub("^\\./"; "")), (.lane // ""), (.state // ""), (.pr // "")] | @tsv' <<<"$lj" > "$_BL_TMP/lanes.tsv" 2>/dev/null \
    || : > "$_BL_TMP/lanes.tsv"
}

# _bl_prep <list file> <out> — _BL_PREP_AWK over the physical paths in <list file>; the key owners
# come from the whole item set, $_BL_TMP/list.abs (every caller writes it first).
_bl_prep() {
  env LC_ALL=C awk -v list="$1" -v items="$_BL_TMP/list.abs" -v root="$_BL_ROOT" -v runs="$_BL_TMP/runs" -v lanes="$_BL_TMP/lanes.tsv" \
    -v merged="$_BL_TMP/merged.tsv" -v open="$_BL_TMP/open.tsv" "$_BL_PREP_AWK" > "$2"
}

# _bl_load <prep row> — the row's fields into P_* (the classifier's only per-item input besides
# is_done, _bl_is_conflict and _rs_first_status_open).
_bl_load() {
  IFS="$_BL_US" read -r P_ABS P_REL P_DISP P_FS P_LD P_SD P_X P_F P_FP P_C P_CP P_CA P_AN \
    P_LANE P_LST P_LPR P_MN P_MU P_K P_COPEN P_LOPEN P_MK <<<"$1"
}

# _bl_target_abs <X> <item abs> — X (from `parked (merged|split … into X …)`) resolved: under the
# requirements tree, the item's folder, the root; with or without `.md`.
_bl_target_abs() {
  local x="$1" c
  for c in "$_BL_ROOT/.supervisor/requirements/$x" "${2%/*}/$x" "$_BL_ROOT/$x"; do
    if [ -f "$c" ]; then _pw_abs "$c"; return $?; fi
    if [ -f "$c.md" ]; then _pw_abs "$c.md"; return $?; fi
  done
  return 1
}

# _bl_classify <chain> — the header's precedence over the loaded P_* row; sets BL_S (state), BL_E
# (evidence), BL_RUN, BL_LANE, BL_PR, BL_PRS, BL_VIA, BL_CF (_bl_is_conflict's row + the item's
# last dated stamp, or ""). Records stale runs in $_BL_TMP/stale. <chain> is the \t-joined parked
# hops already taken (cycle guard).
_bl_classify() {
  local chain="$1" f="$P_ABS" rel="$P_REL" disp="$P_DISP" fs="$P_FS" ca="$P_CA" x tgt="" tabs tdisp row hops r1 r2 r3 r4 r5
  BL_S=""; BL_E=""; BL_RUN=""; BL_LANE=""; BL_PR=""; BL_PRS=""; BL_VIA=""; BL_CF=""

  # 1. the item's own stamp
  if is_done "$f"; then   # the stamp step: is_done matches ANY `## Status:` line
    case "$P_LD" in
      *done_with_escalation*" ABANDONED"*) BL_S=abandoned ;;
      *) BL_S=done ;;
    esac
    BL_E="${P_LD:-## Status: done}"
  elif [[ "$fs" =~ $_BL_RE_PARKED ]]; then
    case "$fs" in
      *"(merged "*" into "*|*"(split "*" into "*)
        x="${fs#* into }"
        case "$x" in '`'*) x="${x#\`}"; tgt="${x%%\`*}" ;; *) x="${x%% *}"; tgt="${x%%[),;]*}" ;; esac ;;
    esac
    if [ -n "$tgt" ] && tabs="$(_bl_target_abs "$tgt" "$f")"; then
      hops="${chain//[!$'\t']/}"
      case "$chain"$'\t' in
        *$'\t'"$tabs"$'\t'*) BL_S=unknown; BL_E="parked chain cycle (into $tgt)" ;;
        *)
          if [ "${#hops}" -ge 8 ]; then
            BL_S=unknown; BL_E="parked chain cycle (more than 8 hops at $tgt)"
          else
            row="$(env LC_ALL=C awk -F "$_BL_US" -v a="$tabs" '$1 == a { print; exit }' "$_BL_TMP/prep.tsv")"
            if [ -z "$row" ]; then
              printf '%s\n' "$tabs" > "$_BL_TMP/one.list"; _bl_prep "$_BL_TMP/one.list" "$_BL_TMP/one.prep"
              row="$(cat "$_BL_TMP/one.prep")"
            fi
            _bl_load "$row"; tdisp="$P_DISP"
            _bl_classify "$chain"$'\t'"$f"
            BL_VIA="$tdisp"; BL_E="parked into $tdisp: $BL_E"; BL_CF=""
          fi ;;
      esac
    else
      BL_S=parked; BL_E="$fs"; [ -z "$tgt" ] || BL_E="$fs (target $tgt not found)"
    fi
  elif [[ "$fs" =~ $_BL_RE_PROPOSED ]]; then
    BL_S=proposed; BL_E="$fs"
  else
    case "$rel" in .supervisor/requirements/proposed/*) BL_S=proposed; BL_E="file under proposed/" ;; esac
  fi
  if [ -n "$BL_S" ]; then
    if [ -n "$ca" ]; then
      while IFS= read -r r1; do
        [ -n "$r1" ] && printf '%s\t%s\t%s\n' "$r1" "$rel" "its ## Current item $disp reads $BL_S" >> "$_BL_TMP/stale"
      done <<<"${ca//$'\036'/$'\n'}"
    fi
    return 0
  fi

  # 2. merge evidence with no done stamp
  if [ -n "$P_X" ]; then BL_S=merged_unstamped; BL_RUN="$P_X"; BL_E="run file $P_X: - [x] $rel"; return 0; fi
  if [ -n "$P_F" ]; then
    BL_S=merged_unstamped; BL_RUN="$P_F"; BL_PR="$P_FP"
    BL_E="run file $P_F: fleet closeout $rel done (PR ${P_FP:-none recorded})"; return 0
  fi
  if [ "$_BL_GH" = verified ] && [ -n "$P_MN" ]; then
    BL_S=merged_unstamped; BL_PR="$P_MU"; BL_PRS=merged; BL_E="merged PR #$P_MN names $P_MK"; return 0
  fi

  # 3. conflict (D-conflict-1) — only an item some run's abandoned/skipped row names can be one
  if [ "${P_AN:-0}" -gt 0 ] && row="$(_bl_is_conflict "$f" "$rel" "$_BL_ADIR")"; then
    IFS=$'\t' read -r r1 r2 r3 r4 <<<"$row"
    BL_S=conflict; BL_RUN="$r1"; BL_CF="$row"$'\t'"$P_SD"
    BL_E="$r4 in $r1 (run $r2, $r3) vs the item's own $fs (last dated stamp: $P_SD)"; return 0
  fi

  # 4. a live claim
  if [ -n "$P_C" ]; then
    BL_S=in_flight; BL_RUN="$P_C"; BL_PR="$P_CP"; BL_E="## Current of unfinished run $P_C"; r5="$P_COPEN"
  elif [ -n "$P_LANE" ]; then
    BL_S=in_flight; BL_LANE="$P_LANE"; BL_PR="$P_LPR"; BL_E="lane $P_LANE ($P_LST) from lane-status"; r5="$P_LOPEN"
  fi
  if [ "$BL_S" = in_flight ]; then
    case "$BL_PR" in -|null) BL_PR="" ;; esac
    if [ "$_BL_GH" != verified ]; then BL_PRS=unverified
    elif [ -n "$BL_PR" ] && [ "$r5" = 1 ]; then BL_S=pr_open; BL_PRS=open; BL_E="$BL_E; PR open"
    elif [ -n "$BL_PR" ]; then BL_PRS=not_open
    fi
    return 0
  fi

  # 5. the item's own non-terminal status. `open` asserts "no merge evidence", which needs the
  # merged-PR list: with github unverified the item reads `unknown`, never `open` (AC5).
  if [[ "$fs" =~ $_BL_RE_SHIPPED ]]; then BL_S=brief_shipped; BL_E="$fs"
  elif _rs_first_status_open "$f"; then
    if [ "$_BL_GH" = verified ]; then BL_S=open; else BL_S=unknown; fi
    BL_E="$fs"
  elif [ -z "$fs" ]; then BL_S=unknown; BL_E="no status line"
  else BL_S=unknown; BL_E="off-enum status line: $fs"
  fi
  [ "$_BL_GH" = verified ] || BL_E="$BL_E (merged-PR lookup unverified)"
  return 0
}

# _bl_rows <prep file> — classify every prep row and append ONE items.tsv row each: item, path,
# folder, state, evidence, run, lane, pr, pr_state, right_size (empty: _bl_doc joins it), via, conflict (5
# fields: run_file, run_id, run_date, row, item_stamp_date — empty when none), candidates (the prep
# row's \036/\035 encoding).
_bl_rows() {
  local line rs cf1 cf2 cf3 cf4 cf5 ev k folder disp rel
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    _bl_load "$line"
    k="$P_K"; disp="$P_DISP"; rel="$P_REL"; folder="${disp%/*}"; [ "$folder" != "$disp" ] || folder="."
    rs=""
    _bl_classify ""
    [ "$_BL_GH" = verified ] || BL_PRS=unverified
    cf1=""; cf2=""; cf3=""; cf4=""; cf5=""
    [ -z "$BL_CF" ] || IFS=$'\t' read -r cf1 cf2 cf3 cf4 cf5 <<<"$BL_CF"
    _bl_clean "$BL_E"; ev="$BL_C"; _bl_clean "$cf4"; cf4="$BL_C"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$disp" "$rel" "$folder" "$BL_S" "$ev" "$BL_RUN" "$BL_LANE" "$BL_PR" "$BL_PRS" "$rs" "$BL_VIA" \
      "$cf1" "$cf2" "$cf3" "$cf4" "$cf5" "${k//$'\t'/ }" >> "$_BL_TMP/items.tsv"
  done < "$1"
}

# _bl_doc <state filter|""> <right-size status|""> [<verdict map file>] — the board document (ONE
# jq-built object) from items.tsv + stale; with a map file (the board: `{<item>: <verdict>}`) each
# item's right_size is its verdict, else `unknown`; without one (item-state) it is null. Totals are
# a reduction over the closed set _BL_STATES.
_bl_doc() {
  local map="${3:-}"
  [ -n "$map" ] || { map="$_BL_TMP/nomap.json"; printf 'null' > "$map"; }
  "$JQ" -n --rawfile items "$_BL_TMP/items.tsv" --rawfile stale "$_BL_TMP/stale" --slurpfile rsm "$map" \
    --arg states "$_BL_STATES" --arg gh "$_BL_GH" --arg rsz "$2" --arg filter "$1" '
    def n: if . == "" then null else . end;
    ($items | split("\n") | map(select(length > 0) | split("\t")
      | {item: .[0], path: .[1], folder: .[2], state: .[3], evidence: .[4], run: (.[5] | n), lane: (.[6] | n),
         pr: (.[7] | n), pr_state: (.[8] | n), right_size: (if $rsm[0] == null then null else ($rsm[0][.[0]] // "unknown") end), via: (.[10] | n),
         conflict: (if .[11] == "" then null else {run_file: .[11], run_id: .[12], run_date: .[13], row: .[14], item_stamp_date: .[15]} end),
         candidates: ((.[16] // "") | split("\u001e") | map(select(length > 0) | split("\u001d")
           | {number: ((.[0] | tonumber?) // .[0]), url: .[1], title: (.[2] // "")}))})) as $all
    | ($states | split(" ")) as $S
    | {schema_version: 1, github: $gh, right_size: ($rsz | n), item_count: ($all | length),
       totals: (reduce $S[] as $s ({}; .[$s] = ([$all[] | select(.state == $s)] | length))),
       state_filter: ($filter | n),
       items: (if $filter == "" then $all else [$all[] | select(.state == $filter)] end),
       stale_runs: ($stale | split("\n") | map(select(length > 0) | split("\t") | {run_file: .[0], item: .[1], reason: .[2]}) | unique)}'
}

_bl_setup() {
  _BL_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || _BL_HERE="$(dirname "$0")"
  command -v "$JQ" >/dev/null 2>&1 || _bl_fail "$1" "jq not found"
  _BL_TMP="$(mktemp -d)" || _bl_fail "$1" "mktemp -d failed"
  trap 'rm -rf "$_BL_TMP"' EXIT
  : > "$_BL_TMP/items.tsv"
}

# item-state <item> [--json] [--root <checkout>]
item_state() {
  local json=0 root="" given="" f doc
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json) json=1; shift ;;
      --root) case "${2:-}" in ""|-*) _bl_fail item-state "--root requires a checkout path" ;; esac; root="$2"; shift 2 ;;
      -*) _bl_fail item-state "unknown option $1" ;;
      *) [ -z "$given" ] || _bl_fail item-state "one item only (got '$1' too)"; given="$1"; shift ;;
    esac
  done
  [ -n "$given" ] || { echo "usage: automate-helpers.sh item-state <item> [--json] [--root <checkout>]" >&2; exit 1; }
  root="$(_rsz_root "$root")" || _bl_fail item-state "--root is not a directory"
  { [ -n "$root" ] && [ -d "$root/.supervisor/requirements" ]; } || _bl_fail item-state "no .supervisor/requirements/ under the root"
  f="$(_bl_resolve "$given" "$root")" || _bl_fail item-state "item not found: $given"
  case "$f" in "$root/.supervisor/requirements/"*) ;; *) _bl_fail item-state "not under .supervisor/requirements/: $given" ;; esac
  _bl_setup item-state
  set +e   # FAIL-SAFE reads from here: a source that cannot be read degrades, never aborts
  _bl_context "$root"
  _bl_items "$root" > "$_BL_TMP/list.abs"
  _bl_prep "$_BL_TMP/list.abs" "$_BL_TMP/prep.tsv"
  printf '%s\n' "$f" > "$_BL_TMP/one.list"; _bl_prep "$_BL_TMP/one.list" "$_BL_TMP/item.prep"
  _bl_rows "$_BL_TMP/item.prep"
  doc="$(_bl_doc "" "")"
  if [ "$json" = 1 ]; then
    "$JQ" '.items[0] + {github: .github, stale_runs: .stale_runs}' <<<"$doc"
  else
    "$JQ" -r '(.items[0] | "\(.state)\t\(.item)\t\(.evidence)"), (.stale_runs[] | "stale_run\t\(.run_file)\t\(.reason)")' <<<"$doc"
  fi
  return 0
}

# backlog [--json] [--state <s>] [--unknown | --verify-list [<item>...]] [--root <checkout>]
backlog_board() {
  local json=0 root="" state="" mode=board named="" f g rsz=ok rc=0 rspid="" doc names
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json) json=1; shift ;;
      --state) case "${2:-}" in ""|-*) _bl_fail backlog "--state requires a state" ;; esac; state="$2"; shift 2 ;;
      --unknown) [ "$mode" = board ] || _bl_fail backlog "--unknown and --verify-list are exclusive"; mode=unknown; shift ;;
      --verify-list) [ "$mode" = board ] || _bl_fail backlog "--unknown and --verify-list are exclusive"; mode=verify; shift ;;
      --root) case "${2:-}" in ""|-*) _bl_fail backlog "--root requires a checkout path" ;; esac; root="$2"; shift 2 ;;
      -*) _bl_fail backlog "unknown option $1" ;;
      *) [ "$mode" = verify ] || _bl_fail backlog "unexpected argument '$1' (items are named only after --verify-list)"
         named="$named$1"$'\n'; shift ;;
    esac
  done
  if [ -n "$state" ]; then
    case " $_BL_STATES " in *" $state "*) ;; *) _bl_fail backlog "unknown state '$state' (one of: $_BL_STATES)" ;; esac
  fi
  root="$(_rsz_root "$root")" || _bl_fail backlog "--root is not a directory"
  { [ -n "$root" ] && [ -d "$root/.supervisor/requirements" ]; } || _bl_fail backlog "no .supervisor/requirements/ under the root"
  names=""
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    f="$(_bl_resolve "$g" "$root")" || _bl_fail backlog "item not found: $g"
    names="$names${f#"$root"/}"$'\n'
  done <<<"$named"
  _bl_setup backlog
  set +e   # FAIL-SAFE reads from here: a source that cannot be read degrades, never aborts
  _bl_context "$root"
  _bl_items "$root" > "$_BL_TMP/list.abs"
  while IFS= read -r f; do printf '%s\n' "${f#"$root"/}"; done < "$_BL_TMP/list.abs" > "$_BL_TMP/list.txt"
  # the right-size column: ONE call over the whole item list, run beside the classification (it is
  # the slow source) and joined by _bl_doc; any failure ⇒ `unknown` in that column only
  printf '{}' > "$_BL_TMP/rs.map"
  if [ -s "$_BL_TMP/list.txt" ]; then
    (
      if [ -n "${LOOMWRIGHT_RIGHT_SIZE_BIN:-}" ]; then exec "$LOOMWRIGHT_RIGHT_SIZE_BIN" "$_BL_TMP/list.txt" --json --root "$root"; fi
      set -euo pipefail; right_size "$_BL_TMP/list.txt" --json --root "$root"
    ) > "$_BL_TMP/rs.json" 2>/dev/null &
    rspid=$!
  fi
  _bl_prep "$_BL_TMP/list.abs" "$_BL_TMP/prep.tsv"
  _bl_rows "$_BL_TMP/prep.tsv"
  if [ -n "$rspid" ]; then
    wait "$rspid"; rc=$?
    if [ "$rc" -eq 0 ] && "$JQ" -e 'type == "array"' "$_BL_TMP/rs.json" >/dev/null 2>&1 \
       && "$JQ" -c 'reduce .[] as $r ({}; if ($r.verdict | type) == "string" then .[$r.item] = $r.verdict else . end)' \
            "$_BL_TMP/rs.json" > "$_BL_TMP/rs.map" 2>/dev/null; then :
    else rsz=unknown; printf '{}' > "$_BL_TMP/rs.map"; fi
  fi
  doc="$(_bl_doc "$state" "$rsz" "$_BL_TMP/rs.map")"
  case "$mode" in
    unknown)
      doc="$("$JQ" '.items |= map(select(.state == "unknown" or .state == "brief_shipped")
        | (if (.candidates | length) > 0 then " (candidate #\(.candidates[0].number) \(.candidates[0].url))" else "" end) as $c
        | . + {fix: (if .state == "brief_shipped" then "verify its acceptance criteria, then stamp done with the PR that shipped it\($c); or mark abandoned"
                     elif (.evidence | test("^## Status:[[:space:]]*(pending|ready)([^A-Za-z0-9_-]|$)")) then "re-run when gh can read the merged-PR list (it reads open only once that lookup is verified)"
                     else "add ## Status: pending, stamp done with the PR that shipped it\($c), or mark abandoned" end)})' <<<"$doc")"
      if [ "$json" = 1 ]; then printf '%s\n' "$doc"
      else "$JQ" -r '.items[] | "\(.item)\t\(.state)\t\(.evidence)\tfix: \(.fix)"' <<<"$doc"; fi
      return 0 ;;
    verify)
      doc="$("$JQ" --arg names "$names" '($names | split("\n") | map(select(length > 0))) as $N
        | .items |= map(select(.state == "brief_shipped" or .state == "unknown" or .state == "conflict" or (.path as $p | $N | index($p))))' <<<"$doc")"
      if [ "$json" = 1 ]; then printf '%s\n' "$doc"
      else "$JQ" -r '.github as $gh | .items[] | "verify\t\(.item)\t\(.state)\t\(.evidence)",
          (if $gh != "verified" then "  candidate: unverified (the merged-PR list could not be read)"
           elif (.candidates | length) == 0 then "  candidate: none in the cached merged list" else (.candidates[] | "  candidate: #\(.number) \(.url) — \(.title)") end)' <<<"$doc"; fi
      return 0 ;;
  esac
  if [ "$json" = 1 ]; then printf '%s\n' "$doc"; return 0; fi
  "$JQ" -r '
    def d: if . == null then "-" else . end;
    "backlog: \(.item_count) items — github: \(.github) — right-size: \(.right_size // "ok")\(if .state_filter then " — state: \(.state_filter)" else "" end)",
    (.items | group_by(.folder)[] | ("\(.[0].folder)/",
      (.[] | "  \(.item | split("/") | last)\t\(.state)\tsize: \(.right_size | d)\t\(if .lane then "lane \(.lane)" elif .run then .run else "-" end)\t\(if .pr_state == "unverified" then "\(.pr // "-") (unverified)" else "\(.pr | d)\(if .pr_state then " (\(.pr_state))" else "" end)" end)\t— \(.evidence)"))),
    "totals: \([.totals | to_entries[] | "\(.key) \(.value)"] | join(" · ")) = \(.totals | add) of \(.item_count) items",
    (if (.stale_runs | length) > 0 then "runs needing attention:", (.stale_runs[] | "  stale_run \(.run_file) — \(.reason)") else empty end)' <<<"$doc"
  return 0
}

# backlog-stamp <item> <mode> … --confirm (usage above). Validation first, then the --confirm guard,
# then ONE append through a temp copy + mv.
backlog_stamp() {
  local root="" given="" mode="" owed="" reason="" sup="" date="" today confirm=0 a f rel prs="" block brief="" tmp em lk n
  em="$(printf '\342\200\224')"
  for a in "$@"; do
    if grep -qE '(^|[^A-Za-z0-9._-])/(Users|home)/[^/]' <<<"$a"; then
      _bl_fail backlog-stamp "refused — an absolute home path in an argument (nothing written)"
    fi
  done
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --confirm) confirm=1; shift ;;
      --pr) [[ "${2:-}" =~ ^https://[^[:space:][:cntrl:]]+/pull/[0-9]+$ ]] || _bl_fail backlog-stamp "refused — --pr needs one https://…/pull/<n> PR url (nothing written)"
            prs="$prs$2"$'\n'; shift 2 ;;
      --owed) [ -n "${2:-}" ] || _bl_fail backlog-stamp "refused — --owed needs text (nothing written)"; owed="$2"; shift 2 ;;
      --reason) [ -n "${2:-}" ] || _bl_fail backlog-stamp "refused — --reason needs text (nothing written)"; reason="$2"; shift 2 ;;
      --supersedes) [ -n "${2:-}" ] || _bl_fail backlog-stamp "refused — --supersedes needs a run_id (nothing written)"; sup="$2"; shift 2 ;;
      --date) case "${2:-}" in ""|-*) _bl_fail backlog-stamp "refused — --date needs YYYY-MM-DD (nothing written)" ;; esac; date="$2"; shift 2 ;;
      --root) case "${2:-}" in ""|-*) _bl_fail backlog-stamp "--root requires a checkout path" ;; esac; root="$2"; shift 2 ;;
      -*) _bl_fail backlog-stamp "refused — unknown option $1 (nothing written)" ;;
      *) if [ -z "$given" ]; then given="$1"; elif [ -z "$mode" ]; then mode="$1"; else _bl_fail backlog-stamp "refused — unexpected argument '$1' (nothing written)"; fi; shift ;;
    esac
  done
  [ -n "$given" ] && [ -n "$mode" ] || { echo "usage: automate-helpers.sh backlog-stamp <item> <done|done_with_escalation|abandoned|kept-open> [--pr <url>]... [--owed <text>] [--reason <text>] [--supersedes <run_id>] [--date YYYY-MM-DD] [--root <checkout>] --confirm" >&2; exit 1; }
  # every value written into the file is ONE line of printable text (a --pr was checked whole above)
  case "$owed$reason$sup$date" in *$'\n'*) _bl_fail backlog-stamp "refused — a multi-line argument (nothing written)" ;; esac
  case "$owed$reason$sup$date" in *[[:cntrl:]]*) _bl_fail backlog-stamp "refused — a control character in an argument (nothing written)" ;; esac
  case "$mode" in
    done)
      [ -n "$prs" ] || _bl_fail backlog-stamp "refused — done needs at least one --pr (nothing written)"
      [ -z "$owed$reason$sup$date" ] || _bl_fail backlog-stamp "refused — done takes only --pr (nothing written)" ;;
    done_with_escalation)
      [ -n "$prs" ] && [ -n "$owed" ] || _bl_fail backlog-stamp "refused — done_with_escalation needs --pr and --owed (nothing written)"
      [ -z "$reason$sup$date" ] || _bl_fail backlog-stamp "refused — done_with_escalation takes only --pr and --owed (nothing written)" ;;
    abandoned)
      [ -n "$reason" ] || _bl_fail backlog-stamp "refused — abandoned needs --reason (nothing written)"
      [ -z "$prs$owed$sup$date" ] || _bl_fail backlog-stamp "refused — abandoned takes only --reason (nothing written)" ;;
    kept-open)
      [ -n "$sup" ] || _bl_fail backlog-stamp "refused — kept-open needs --supersedes <run_id> (nothing written)"
      [ -z "$prs$owed$reason" ] || _bl_fail backlog-stamp "refused — kept-open takes only --supersedes and --date (nothing written)"
      case "$sup" in *[!A-Za-z0-9._-]*) _bl_fail backlog-stamp "refused — --supersedes is not a run_id (nothing written)" ;; esac
      today="$(date -u +%Y-%m-%d)"
      [ -n "$date" ] || date="$today"
      grep -qE '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$' <<<"$date" || _bl_fail backlog-stamp "refused — --date is not YYYY-MM-DD (nothing written)"
      # a marker settles every row dated on or before it, so a future date would settle rows from
      # runs that have not happened yet (D-conflict-1: a later run's row must raise the conflict again)
      [ "$((10#${date//-/}))" -le "$((10#${today//-/}))" ] || _bl_fail backlog-stamp "refused — --date $date is later than today ($today UTC; nothing written)" ;;
    *) _bl_fail backlog-stamp "refused — unknown stamp '$mode' (done|done_with_escalation|abandoned|kept-open; nothing written)" ;;
  esac
  root="$(_rsz_root "$root")" || _bl_fail backlog-stamp "--root is not a directory"
  [ -n "$root" ] && [ -d "$root/.supervisor/requirements" ] || _bl_fail backlog-stamp "refused — no .supervisor/requirements/ under the root (nothing written)"
  f="$(_bl_resolve "$given" "$root")" || _bl_fail backlog-stamp "refused — item not found: $given (nothing written)"
  case "$f" in "$root/.supervisor/requirements/"*) ;; *) _bl_fail backlog-stamp "refused — not under .supervisor/requirements/: $given (nothing written)" ;; esac
  [ ! -L "$f" ] || _bl_fail backlog-stamp "refused — the item is a symlink (nothing written)"
  rel="${f#"$root"/}"
  if is_done "$f"; then _bl_fail backlog-stamp "refused — $rel is already done (nothing written)"; fi
  case "$mode" in
    done|done_with_escalation)
      _rs_load_brief_pointer
      brief="$(set +e; _rs_find_done_brief "$rel" "$root/.supervisor/jobs/done")" || brief=""
      brief="${brief#"$root"/}"
      block="$(printf '\n<!-- loomwright:requirement-closeout -->\n## Status: %s\n- **Completed:** %s\n- **Brief:** %s\n' "$mode" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${brief:-unknown}")"
      while IFS= read -r a; do [ -n "$a" ] && block="$block"$'\n'"- **PR:** $a"; done <<<"$prs"
      [ "$mode" = done ] || block="$block"$'\n'"- **Owed:** $owed" ;;
    abandoned) block=$'\n'"## Status: done_with_escalation $em ABANDONED ($reason)" ;;
    kept-open) block=$'\n'"- **Kept open:** $date $em supersedes $sup" ;;
  esac
  [ "$confirm" = 1 ] || { printf 'backlog-stamp: would append to %s:\n%s\n' "$rel" "$block"; echo "backlog-stamp: refused — --confirm not given (nothing written)" >&2; exit 1; }
  # One writer at a time per item: the copy + append + mv below is a read-modify-write, so two
  # concurrent stamps would each report `stamped` while one append is lost. A `mkdir` lock beside the
  # item (atomic on every filesystem) serializes them; the done check re-runs inside it. Waits at
  # most ~10 s, then refuses with nothing written. (closeout and reconcile-status do not take it.)
  lk="$f.backlog-stamp.lock"; n=0
  until mkdir "$lk" 2>/dev/null; do
    n=$((n + 1))
    [ "$n" -le 100 ] || _bl_fail backlog-stamp "refused — $rel is locked by another backlog-stamp (${lk#"$root"/}; nothing written)"
    sleep 0.1
  done
  if is_done "$f"; then rmdir "$lk"; _bl_fail backlog-stamp "refused — $rel is already done (nothing written)"; fi
  tmp="$(mktemp "$f.XXXXXX")" || { rmdir "$lk"; _bl_fail backlog-stamp "refused — cannot create a temp file (nothing written)"; }
  if cp -p "$f" "$tmp" && printf '%s\n' "$block" >> "$tmp" && mv -f "$tmp" "$f"; then
    rmdir "$lk"
    case "$mode" in
      kept-open) printf 'backlog-stamp: stamped %s — Kept open %s, supersedes %s\n' "$rel" "$date" "$sup" ;;
      abandoned) printf 'backlog-stamp: stamped %s — done_with_escalation %s ABANDONED\n' "$rel" "$em" ;;
      *) printf 'backlog-stamp: stamped %s — %s\n' "$rel" "$mode" ;;
    esac
    return 0
  fi
  rm -f "$tmp"; rmdir "$lk"
  _bl_fail backlog-stamp "write failed for $rel (the item is unchanged)"
}
