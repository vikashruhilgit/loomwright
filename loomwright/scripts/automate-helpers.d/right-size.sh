# --help usage (the `#:  ` lines): this family's segment of automate-helpers.sh --help, assembled
# by the dispatcher's _ah_usage in _AH_HELP_SEGMENTS order; fixture: fixtures/automate-helpers-help/right-size.golden.
#:  right-size       <item|dir|item-list|plan doc>... [--json] [--root <checkout>]  # parallel-automate/18b: READ-ONLY advisory size verdict, one line per item — `<item>: small|ok|large|unknown (…)` counted from the companion-expanded Touches set (plan-waves' own parser + one companion pass); `small` names up to 3 merge candidates, `large` says `will not fit one PR: split by Part`; a plan doc first gets `plan doc: sections ok` / `plan doc: missing: <names>`, then one verdict per checklist item; a `## Measurements` section naming no frozen sha adds a `measurements:` line; --json prints ONE array; exit 1 + empty stdout on usage / item not found / companions_malformed, every verdict exits 0
#:  merge-items      <out.md> --title <t> --goal <text> [--date YYYY-MM-DD] [--root <checkout>] <X>:<original.md>...  # parallel-automate/18b: the owner-invoked lossless merge — each original VERBATIM as `## Part <X> — <its title>` (headings demoted one level; its Status / Depends on / Touches folded into the merged item's own sections), originals stamped `parked (merged …)`, every dependent re-pointed; writes ONLY requirement files under <root>/.supervisor/requirements/, all-or-nothing after the lost-line post-check; exit 1 with NOTHING written on a lost line, a done / operator-run / already-merged original, or a merge that would make a dependency cycle

# --------------------------------------------------------------------------- #
# right-size — read-only, advisory size verdict for requirement items (parallel-automate/18b).
# Every `/automate` item pays a fixed run cost whatever its size. S2's five lanes (2026-10-05):
# a small fix ~$17 and 4 owner questions, tests only ~$19 / 5, medium ~$26 / 6 and ~$36 / 6, large
# ~$40 / 8, plus 2-4 h wall clock each — so the floor (~$17-20, four or more questions) is paid even
# by a one-file change. `large` means "will not fit one PR": of 138 past agent PRs in the postmortem
# ledger the median touched 13 files and 90% touched 29 or fewer, and Plan Review FAILs a brief with
# more than 7 subtasks (one Part per subtask is the comfortable form). The owner set the thresholds
# on 2026-10-22; their defaults live ONCE, in automate-helpers.d/config.sh's right_size_* readers
# (keys right_size_small / right_size_large_files / right_size_max_parts in <root>/.supervisor/config.json).
# --------------------------------------------------------------------------- #
#
# right-size <item|dir|item-list|plan doc>... [--json] [--root <checkout>]
# Inputs (one or more): a directory ⇒ resolve_folder's output (not done, not proposed/parked); a
# `*.md` file ⇒ ONE item, or a plan doc (its first `# ` heading says "plan doc", or it has a
# `## Checklist` heading) ⇒ the doc's section check, then every `- [ ] <path>` checklist item whose
# file is not done (paths repo-root-relative, else relative to the doc); any other file ⇒ one item
# path per non-blank, non-`#` line, resolved against --root (default `git rev-parse --show-toplevel`,
# else $PWD).
#
# Count (_rsz_count — THE count rule; plan-waves --explain calls the same function on its own
# already-expanded set, so the two can never count one set two ways): the item's Touches set exactly
# as `plan-waves <item> --touches` reads it (_pw_touches, then ONE _pw_expand pass of
# <root>/.agent/companions.json — never a second `## Touches` parse). Each entry counts 1; an entry
# that is a directory under <root> counts the regular files under it (at least 1); an entry that does
# not exist yet counts 1; a file named by two entries (`a/` and `a/b.sh`) counts once.
# Verdict, first match wins:
# - large    count > right_size_large_files OR `## Part ` (H2, outside fences) headings >
#            right_size_max_parts — `large (<N> files[, <P> parts]) — will not fit one PR: split by
#            Part`, naming only the causes that hold. A Touches-unknown item can still be large by parts.
# - unknown  the Touches set is not known — `unknown (Touches <why>)`, <why> as plan-waves --touches
#            prints it (`missing`, `declared unknown`, `unparsable line <N>: "<text>"`). NEVER small.
# - small    count <= right_size_small — `small (<N> files, <S> scope items, <A> criteria) — merge
#            candidates: <cand> (<k> shared files[, same chain][, same folder])[, …]` or `none`.
# - ok       otherwise — `ok (<N> files, <S> scope items, <A> criteria)`.
# (The words stay plural at 1 — `1 files` — so a reader can parse the line without a singular form.)
# Scope items = top-level `- ` / `* ` / `+ ` / `N.` / `N)` lines under an H2/H3 heading starting
# "Scope"; criteria = the same lines under an H2/H3 "Acceptance criteria" heading (case-insensitive).
#
# Merge candidates (only for `small` — `ok`, `large` and `unknown` items do no pool work): every
# `*.md` under <root>/.supervisor/requirements/ (recursive) except `proposed/`, _rs_skip_path's list
# (`00-*`, `_*`, `README*`, `operator-run/`, a top-level task plan), done (is_done), parked or proposed
# (is_not_ready), run files and the item itself. A candidate qualifies by >= 1 shared path of the two
# companion-expanded sets (literal-prefix intersection, the planner's rule; <k> counts the contained
# path of each intersecting pair once), by being in the same `## Depends on` chain (one reaches the
# other through resolved dependencies), or by sitting in the same folder. It is REFUSED when merging
# would make a cycle: a dependency path between the two that passes through a third item (a direct
# edge between them collapses and is allowed). The dependency graph is every requirement file's
# resolved `## Depends on` (done and parked files included: a path through them still cycles); an
# unresolvable or missing section adds no edge. Ranked by shared count, then same chain, then same
# folder, then name; at most 3. A display name is the path under .supervisor/requirements/ without
# `.md` (an item outside that tree keeps the path as given).
#
# Plan doc (the user-story-writing skill's template, read at run time between its
# `plan-doc-template:begin/end` markers — never a copy here): `<doc>: plan doc: sections ok`, or
# `plan doc: missing: <name>, …` naming every template `## ` heading the doc lacks (a heading is
# named by its text before ` (`, so `## Status: done (…)` is `Status: done`), or
# `plan doc: sections unknown (template unreadable)`. Measurements: an item with a `## Measurements`
# section (to the next H1/H2, fences included) holding no 7-40 character lower-case hex token with a
# digit in it prints one more `<item>: measurements: no frozen commit named` line.
#
# --json — stdout is ONE JSON array (built with jq, never shell-templated), one object per input row:
#   {"item": <display>, "verdict": "small"|"ok"|"large"|"unknown"|null (null = a plan doc row),
#    "files": <int>|null, "scope_items": <int>|null, "criteria": <int>|null, "parts": <int>|null,
#    "causes": [ "files" | "parts" | "touches_unknown" … ],
#    "candidates": [ {"item": <display>, "shared_files": <int>, "same_chain": <bool>, "same_folder": <bool>} … ],
#    "plan_doc": null | "ok" | [<missing name> …] | "unknown",
#    "measurements": null | "no_frozen_commit", "touches_why": null | <why>}
# Exit 0 on every verdict (unknown, large and missing plan-doc sections included — advisory only);
# exit 1 with NOTHING on stdout on usage errors, an input / plan-set entry / checklist path that names
# no file (`item not found: <path>`), companions_malformed, or `--json` without jq.
# READ-ONLY: writes only its own `mktemp -d` dir (trap-removed); the only git call is
# `rev-parse --show-toplevel`; never `gh`.
#
# merge-items <out.md> --title <t> --goal <text> [--date YYYY-MM-DD] [--root <checkout>] <X>:<orig.md>...
# The hand procedure made mechanical, on the owner's explicit invocation only. <X> is one capital
# letter per original (unique, at least two originals). <out.md> must not exist; it and every
# original must lie under <root>/.supervisor/requirements/. Output, in order: `# <title>`;
# `## Merged from (<date>)` with one `- Part <X>: `<path from out's folder>` — <original title>` line
# each and one sentence saying nothing was paraphrased; `## Goal` + <text>; per original
# `## Part <X> — <its H1 text>` then its body VERBATIM — every line after its first `# ` heading
# (lines before it too), headings outside fences demoted one level, runs of blank lines outside
# fences collapsed to one — WITHOUT its `## Status:` line(s) and its `## Depends on` / `## Touches`
# sections (a section ends at the next `# `/`## ` heading or the close-out sentinel, the planner's
# boundary). `## Depends on`: the originals' lines in order, minus `none` and references to the
# originals, de-duplicated by the file they resolve to (re-written as a path from out's folder when
# that differs from the original's), else `none`. `## Touches`: the originals' lines, sorted unique,
# each `changelog.d/<file>.md` fragment replaced by ONE `changelog.d/<out-slug>.md` (<out-slug> = out's
# path under .supervisor/requirements/ without `.md`, `/` → `-`).
# Each original's first `## Status:` line becomes `## Status: parked (merged <date> into <out path
# under .supervisor/requirements/> as Part <X> — do not run this file)` (inserted after its title
# when it had none). Every other requirement file (run files aside) whose `## Depends on` names an
# original is re-pointed: each such line becomes the path from that file's folder to <out>, and a
# second line naming the same file is dropped; nothing else in the file changes.
# Refused (exit 1, nothing written): a done original, one under `operator-run/`, an already-merged one
# (`## Status: parked (merged …`), an original whose Touches is not known or whose Depends on is
# missing/unparsable (fix it first — a merge cannot fold an unknown set), and a merge that would make
# a cycle (a dependency path from one original to any original through a non-original).
# POST-CHECK (all writes are staged in a private temp dir and copied into place only after it passes;
# out first, then dependents, then originals): (a) every non-blank, non-heading line of each original
# outside its Status line and Depends on / Touches sections appears in that original's Part as often
# as in the original; (b) every Touches line of each original appears in the merged `## Touches`,
# except a changelog.d fragment, which must map to the one out fragment; (c) every Depends on line of
# each original (except `none` and the originals themselves) resolves to the same file as a merged
# `## Depends on` line; (d) no original's Status line is carried, and each staged original carries its
# parked stamp. Any loss ⇒ one stderr line per lost line, exit 1, nothing written. Success prints
# `merge-items: post-check ok — 0 lost lines (…)` then one `wrote` / `parked` / `re-pointed` line each.
# The copy into place is file by file, not one atomic transaction: a crash mid-copy can leave a subset
# written (out first, so a parked original never points at a missing file). <out.md> is created with a
# hard link, so one that appears after the existence check is never overwritten (exit 1, nothing written).
# TEST SEAM (tests only — never set it in a real run): LOOMWRIGHT_MERGE_ITEMS_DROP=<line> removes every
# staged-output line equal to <line> just before the post-check, so a test can prove the post-check
# catches a lost body / Touches / Depends on line. It can only make a merge fail, never pass.

_RSZ_TMP=""
_rsz_fail()  { echo "right-size: $*" >&2; exit 1; }
_rsz_usage() { echo "right-size: ${1:-bad usage}" >&2; echo "usage: automate-helpers.sh right-size <item|dir|item-list|plan doc>... [--json] [--root <checkout>]" >&2; exit 1; }
_mi_fail()   { echo "merge-items: $*" >&2; exit 1; }
_mi_usage()  { echo "merge-items: ${1:-bad usage}" >&2; echo "usage: automate-helpers.sh merge-items <out.md> --title <t> --goal <text> [--date YYYY-MM-DD] [--root <checkout>] <X>:<original.md>..." >&2; exit 1; }

# _rsz_root <given|""> — the physical checkout root (default: git toplevel, else $PWD); non-zero if not a dir.
_rsz_root() {
  local r="$1"
  if [ -z "$r" ]; then
    r="$(git rev-parse --show-toplevel 2>/dev/null)" || r=""
    [ -n "$r" ] || r="$PWD"
  fi
  (cd "$r" 2>/dev/null && pwd -P)
}

# _rsz_count <expanded-set-file> <root> — THE count rule (header): prints one integer.
_rsz_count() {
  local e any
  {
    while IFS= read -r e || [ -n "$e" ]; do
      e="${e%/}"
      [ -n "$e" ] || continue
      if [ -d "$2/$e" ]; then
        any="$(cd "$2" && find "./$e" -type f 2>/dev/null | sed 's#^\./##')" || any=""
        if [ -n "$any" ]; then printf '%s\n' "$any"; else printf '%s/\n' "$e"; fi
      else
        printf '%s\n' "$e"
      fi
    done < "$1"
  } | env LC_ALL=C sort -u | env LC_ALL=C awk 'END { print NR }'
}

# _rsz_set <item> <root> <out> — writes <out> = the item's Touches set as plan-waves --touches reads
# it; prints `known`, or `unknown <why>` (then <out> is empty). Needs the companion rules already
# loaded into $_PW_TMP/rules (right_size loads them once).
_rsz_set() {
  _pw_touches "$1" "$3.diag" > "$3.t"
  if [ "$(head -n1 "$3.t")" != known ]; then : > "$3"; echo "unknown $(_pw_touches_why "$3.diag")"; return 0; fi
  sed '1d' "$3.t" > "$3.decl"
  sed 's#/$##' "$3.decl" | env LC_ALL=C sort -u > "$3"   # the declared entries, normalized
  _pw_expand "$3.decl" "$2" "$3"   # + ONE companion pass (plan-waves --touches' own); replaces <out>
  echo known
}

# _rsz_shared <setA> <setB> — how many distinct paths the two sets share (the contained path of each
# intersecting pair, the planner's literal-prefix rule).
_rsz_shared() {
  if [ ! -s "$1" ] || [ ! -s "$2" ]; then echo 0; return 0; fi
  env LC_ALL=C awk 'FILENAME == ARGV[1] { A[++na] = $0; next }
    { for (i = 1; i <= na; i++) { a = A[i]; b = $0
        if (a == b || index(a, b "/") == 1 || index(b, a "/") == 1) P[(length(b) > length(a)) ? b : a] = 1 } }
    END { n = 0; for (p in P) n++; print n }' "$1" "$2"
}

# _RSZ_SECT_AWK — one pass over an item: `<scope items> <criteria> <parts> <none|frozen|no_frozen_commit>`.
_RSZ_SECT_AWK='
  function lev(s) { match(s, /^#+/); return RLENGTH }
  BEGIN { fence = 0; sec = ""; sc = 0; cr = 0; pa = 0; hm = 0; body = "" }
  /^```/ { fence = !fence; if (sec == "meas") body = body " " $0; next }
  fence { if (sec == "meas") body = body " " $0; next }
  /^#+ / {
    l = lev($0)
    if (sec == "meas" && l > 2) { body = body " " $0; next }
    h = $0; sub(/^#+[ \t]+/, "", h); h = tolower(h); sec = ""
    if (l == 2 && index($0, "## Part ") == 1) pa++
    if ((l == 2 || l == 3) && h ~ /^scope([^a-z]|$)/) sec = "scope"
    else if ((l == 2 || l == 3) && h ~ /^acceptance criteria([^a-z]|$)/) sec = "crit"
    else if (l == 2 && h ~ /^measurements([^a-z]|$)/) { sec = "meas"; hm = 1 }
    next
  }
  sec == "scope" && /^([-*+]|[0-9]+[.)])[ \t]/ { sc++ }
  sec == "crit" && /^([-*+]|[0-9]+[.)])[ \t]/ { cr++ }
  sec == "meas" { body = body " " $0 }
  END {
    m = "none"
    if (hm) {
      m = "no_frozen_commit"; t = body; gsub(/[^0-9a-f]+/, " ", t); n = split(t, w, " ")
      for (i = 1; i <= n; i++) if (length(w[i]) >= 7 && length(w[i]) <= 40 && w[i] ~ /[0-9]/) { m = "frozen"; break }
    }
    print sc, cr, pa, m
  }'

# _RSZ_GRAPH_AWK — ARGV[1]: `<from>\t<to>` dependency edges (physical paths); ARGV[2]: queries.
#   `C\t<item>\t<cand>`  ⇒ `<cand>\t<same chain 0|1>\t<cycle 0|1>`
#   `M\t<o1>\t<o2>…`     ⇒ `<cycle 0|1>` for merging that set
# cycle = some member has a dependency (not a member) from which a member is reachable.
_RSZ_GRAPH_AWK='
  BEGIN { FS = "\t" }
  function reach(src, dst,   q, h, t, seen, cur, n, a, i) {
    split("", seen); split("", q); h = 1; t = 0; q[++t] = src
    while (h <= t) {
      cur = q[h++]
      n = split(substr(S[cur], 2), a, "\t")
      for (i = 1; i <= n; i++) {
        if (a[i] == dst) return 1
        if (!(a[i] in seen)) { seen[a[i]] = 1; q[++t] = a[i] }
      }
    }
    return 0
  }
  function cyc(   o, n, a, i, m) {
    for (o in IN) {
      n = split(substr(S[o], 2), a, "\t")
      for (i = 1; i <= n; i++) {
        if (a[i] in IN) continue
        for (m in IN) if (reach(a[i], m)) return 1
      }
    }
    return 0
  }
  FILENAME == ARGV[1] { S[$1] = S[$1] "\t" $2; next }
  $1 == "C" { split("", IN); IN[$2] = 1; IN[$3] = 1
    print $3 "\t" ((reach($2, $3) || reach($3, $2)) ? 1 : 0) "\t" cyc(); next }
  $1 == "M" { split("", IN); for (i = 2; i <= NF; i++) IN[$i] = 1; print cyc(); next }'

# _rsz_edges <requirements dir> <out> — every requirement file's resolved `## Depends on` edges.
_rsz_edges() {
  local f id a
  : > "$2"
  [ -d "$1" ] || return 0
  find "$1" -type f -name '*.md' 2>/dev/null | env LC_ALL=C sort > "$2.files"
  # One awk over every file picks a SUPERSET of the files with an edge — those whose `## Depends on`
  # section holds a line other than `none` (it ignores fences, so it can only over-include) — and
  # only those get the planner's own _pw_depends parse below.
  : > "$2.cand"
  if [ -s "$2.files" ]; then
    tr '\n' '\0' < "$2.files" | xargs -0 env LC_ALL=C awk 'FNR == 1 { s = 0 }
      /^# / || /^## / { s = ($0 == "## Depends on"); next }
      s && $0 !~ /^[ \t]*$/ && $0 != "none" && !(FILENAME in P) { P[FILENAME] = 1; print FILENAME }' > "$2.cand"
  fi
  while IFS= read -r f; do
    _pw_depends "$f" > "$2.d"
    case "$(head -n1 "$2.d")" in missing|none|"") continue ;; esac
    while IFS= read -r id; do
      a="$(_pw_resolve_dep "$f" "$id")" || continue
      printf '%s\t%s\n' "$f" "$a" >> "$2"
    done < "$2.d"
  done < "$2.cand"
}

# _rsz_disp <abs> <root> <as given> — the display name (header).
_rsz_disp() {
  local r
  case "$1" in
    "$2/.supervisor/requirements/"*) r="${1#"$2"/.supervisor/requirements/}"; printf '%s\n' "${r%.md}" ;;
    *) printf '%s\n' "$3" ;;
  esac
}

# _rsz_is_plan_doc <file> — its first `# ` heading names a plan doc, or it has a `## Checklist` heading.
_rsz_is_plan_doc() {
  env LC_ALL=C awk '/^```/ { f = !f; next } f { next }
    /^# / && !t { t = 1; if (index(tolower($0), "plan doc")) hit = 1 }
    /^## Checklist[ \t]*$/ { hit = 1 }
    END { exit hit ? 0 : 1 }' "$1" 2>/dev/null
}

# _rsz_heads <file> <template|doc> — the `## ` heading names, each cut at its first ` (`. A template
# is the user-story-writing skill: only the lines between its markers (the body sits inside a fence).
_rsz_heads() {
  if [ "$2" = template ]; then
    env LC_ALL=C awk '/<!-- plan-doc-template:begin -->/ { on = 1; next } /<!-- plan-doc-template:end -->/ { on = 0 }
      on && /^## / { h = substr($0, 4); sub(/ \(.*$/, "", h); sub(/[ \t]+$/, "", h); print h }' "$1"
  else
    env LC_ALL=C awk '/^```/ { f = !f; next } !f && /^## / { h = substr($0, 4); sub(/ \(.*$/, "", h); sub(/[ \t]+$/, "", h); print h }' "$1"
  fi
}

# _rsz_template — the skill file holding the plan-doc template, found beside the real scripts dir
# (automate-helpers.d is resolved physically, so a bundle or symlinked copy still finds it).
_rsz_template() {
  local d
  d="$(cd -P "$(dirname "$0")/automate-helpers.d" 2>/dev/null && cd ../.. && pwd -P)" || return 1
  printf '%s\n' "$d/skills/user-story-writing/SKILL.md"
}

# _rsz_plan_doc_check <doc> — prints `ok`, `unknown`, or the missing names one per line.
_rsz_plan_doc_check() {
  local tpl
  tpl="$(_rsz_template)" || tpl=""
  if [ -z "$tpl" ] || [ ! -r "$tpl" ]; then echo unknown; return 0; fi
  _rsz_heads "$tpl" template > "$_RSZ_TMP/tpl.heads"
  if [ ! -s "$_RSZ_TMP/tpl.heads" ]; then echo unknown; return 0; fi
  _rsz_heads "$1" doc > "$_RSZ_TMP/doc.heads"
  env LC_ALL=C awk 'FILENAME == ARGV[1] { H[$0] = 1; next } !($0 in H) { print; m = 1 } END { if (!m) print "ok" }' \
    "$_RSZ_TMP/doc.heads" "$_RSZ_TMP/tpl.heads"
}

# _rsz_add <as given> <path> — append one input to the plan set ($_RSZ_TMP/rows:
# `item|doc\t<display>\t<path>`): a plan doc adds its doc row and its not-done checklist items.
_rsz_add() {
  local given="$1" f="$2" abs line p c
  [ -f "$f" ] || _rsz_fail "item not found: $given"
  abs="$(_pw_abs "$f")" || _rsz_fail "item not found: $given"
  if _rsz_is_plan_doc "$f"; then
    printf 'doc\t%s\t%s\n' "$(_rsz_disp "$abs" "$_RSZ_ROOT" "$given")" "$f" >> "$_RSZ_TMP/rows"
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in "- [ ] "*) ;; *) continue ;; esac
      p="${line:6}"; p="${p%%  #*}"; p="$(printf '%s' "$p" | sed 's/[[:space:]]*$//')"
      [ -n "$p" ] || continue
      case "$p" in
        /*) c="$p" ;;
        *) c="$_RSZ_ROOT/$p"; [ -f "$c" ] || c="$(dirname "$f")/$p" ;;
      esac
      [ -f "$c" ] || _rsz_fail "item not found: $p (checklist of $given)"
      if is_done "$c"; then continue; fi
      abs="$(_pw_abs "$c")" || _rsz_fail "item not found: $p"
      printf 'item\t%s\t%s\n' "$(_rsz_disp "$abs" "$_RSZ_ROOT" "$p")" "$c" >> "$_RSZ_TMP/rows"
    done < "$f"
  else
    printf 'item\t%s\t%s\n' "$(_rsz_disp "$abs" "$_RSZ_ROOT" "$given")" "$f" >> "$_RSZ_TMP/rows"
  fi
}

# _rsz_basename / _rsz_dirname — fork-free stand-ins with POSIX basename(1) / dirname(1) output
# (trailing slashes stripped, `/` kept, an optional suffix removed unless it is the whole name).
# _rsz_pool_init runs the pool build in a subshell where `basename` / `dirname` are these
# functions: the planner's _pw_resolve_dep and _pw_abs (and _rs_skip_path) fork one of them per
# file of a folder per numeric id, which made a 479-file tree's scan take ~8 s instead of ~3 s.
# The rules stay the planner's own; only the fork goes. 17-right-size compares both with the
# real utilities.
_rsz_basename() {
  local p="$1"
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  [ "$p" = / ] || p="${p##*/}"
  if [ -n "${2:-}" ] && [ "$p" != "$2" ]; then p="${p%"$2"}"; fi
  printf '%s\n' "$p"
}
_rsz_dirname() {
  local p="$1"
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  case "$p" in
    */*) p="${p%/*}"; while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done; [ -n "$p" ] || p=/ ;;
    *) p=. ;;
  esac
  printf '%s\n' "$p"
}

# _rsz_pool_init — once per run (first small item): the candidate pool ($_RSZ_TMP/pool:
# `<abs>\t<display>`, set files pool.<k>) and the dependency edges ($_RSZ_TMP/edges).
# ORDERING CONTRACT: pool.<k> belongs to the k-th row of pool only by position — _rsz_pool_build
# and _rsz_candidates both walk pool in file order with one shared counter k. Nothing may sort,
# filter or rewrite pool between the build and the candidate pass, or pool.<k> desyncs from its row.
_RSZ_POOL=0
_rsz_pool_init() {
  [ "$_RSZ_POOL" = 0 ] || return 0
  _RSZ_POOL=1
  (
    basename() { _rsz_basename "$@"; }
    dirname() { _rsz_dirname "$@"; }
    _rsz_pool_build
  ) || exit 1
}
_rsz_pool_build() {
  local req="$_RSZ_ROOT/.supervisor/requirements" f k=0
  : > "$_RSZ_TMP/pool"
  _rsz_edges "$req" "$_RSZ_TMP/edges"
  [ -d "$req" ] || return 0
  while IFS= read -r f; do
    case "$f" in */proposed/*) continue ;; esac
    if _rs_skip_path "$f" "$_RSZ_ROOT"; then continue; fi
    if is_done "$f" || is_not_ready "$f"; then continue; fi
    if is_run_file "$f"; then continue; fi
    _rsz_set "$f" "$_RSZ_ROOT" "$_RSZ_TMP/pool.$k" > /dev/null
    printf '%s\t%s\n' "$f" "$(_rsz_disp "$f" "$_RSZ_ROOT" "$f")" >> "$_RSZ_TMP/pool"
    k=$((k+1))
  done < "$_RSZ_TMP/edges.files"
}

# _rsz_candidates <item abs> <item set> — prints the ranked, capped candidate rows
# `<shared>\t<chain 0|1>\t<folder 0|1>\t<display>`. It reads pool.<k> by row position (the
# ordering contract at _rsz_pool_init): k advances on EVERY row, skipped rows included.
_rsz_candidates() {
  local abs="$1" set="$2" f d k=0 sh fo ch cy qx tab
  tab="$(printf '\t')"
  _rsz_pool_init
  : > "$_RSZ_TMP/q"; : > "$_RSZ_TMP/c"
  while IFS="$tab" read -r f d; do
    [ "$f" = "$abs" ] || printf 'C\t%s\t%s\n' "$abs" "$f" >> "$_RSZ_TMP/q"
  done < "$_RSZ_TMP/pool"
  [ -s "$_RSZ_TMP/q" ] || return 0
  env LC_ALL=C awk "$_RSZ_GRAPH_AWK" "$_RSZ_TMP/edges" "$_RSZ_TMP/q" > "$_RSZ_TMP/qa"
  while IFS="$tab" read -r f d; do
    if [ "$f" = "$abs" ]; then k=$((k+1)); continue; fi
    IFS="$tab" read -r qx ch cy <<EOF
$(env LC_ALL=C awk -F '\t' -v f="$f" '$1 == f { print; exit }' "$_RSZ_TMP/qa")
EOF
    if [ "$cy" = 1 ]; then k=$((k+1)); continue; fi   # merging would make a dependency cycle
    sh="$(_rsz_shared "$set" "$_RSZ_TMP/pool.$k")"
    fo=0; if [ "$(dirname "$f")" = "$(dirname "$abs")" ]; then fo=1; fi
    if [ "$sh" -gt 0 ] || [ "$ch" = 1 ] || [ "$fo" = 1 ]; then
      printf '%s\t%s\t%s\t%s\n' "$sh" "$ch" "$fo" "$d" >> "$_RSZ_TMP/c"
    fi
    k=$((k+1))
  done < "$_RSZ_TMP/pool"
  env LC_ALL=C sort -t "$tab" -k1,1nr -k2,2nr -k3,3nr -k4,4 "$_RSZ_TMP/c" | env LC_ALL=C awk 'NR <= 3'
}

right_size() {
  local json=0 root="" n=0 i=0 kind disp f abs st why files sc cr pa ms verdict causes cand line tab pd
  local S L P
  local IN=()
  tab="$(printf '\t')"
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1; shift ;;
      --root)
        case "${2:-}" in ""|-*) _rsz_usage "--root requires a checkout path (got '${2:-}')" ;; esac
        root="$2"; shift 2 ;;
      -*) _rsz_usage "unknown option $1" ;;
      *) IN[n]="$1"; n=$((n+1)); shift ;;
    esac
  done
  [ "$n" -gt 0 ] || _rsz_usage "missing <item|dir|item-list|plan doc>"
  _RSZ_ROOT="$(_rsz_root "$root")" || _rsz_usage "--root is not a directory"
  [ -n "$_RSZ_ROOT" ] || _rsz_usage "--root is not a directory"
  if [ "$json" = 1 ] && ! command -v "$JQ" >/dev/null 2>&1; then _rsz_fail "jq not found (needed for --json)"; fi
  _RSZ_TMP="$(mktemp -d)" || _rsz_fail "mktemp -d failed"
  trap 'rm -rf "$_RSZ_TMP"' EXIT
  _PW_TMP="$_RSZ_TMP"; _PW_EXPLAIN=0; _RSZ_POOL=0
  : > "$_RSZ_TMP/rows"; : > "$_RSZ_TMP/out"; : > "$_RSZ_TMP/objs"
  S="$(right_size_small "$_RSZ_ROOT")"; L="$(right_size_large_files "$_RSZ_ROOT")"; P="$(right_size_max_parts "$_RSZ_ROOT")"

  # 1. The plan set.
  while [ "$i" -lt "$n" ]; do
    f="${IN[i]}"
    [ -e "$f" ] || _rsz_fail "item not found: $f"
    if [ -d "$f" ]; then
      resolve_folder "${f%/}" > "$_RSZ_TMP/dir"
      while IFS= read -r line; do _rsz_add "$line" "$line"; done < "$_RSZ_TMP/dir"
    elif [ -f "$f" ] && case "$f" in *.md) true ;; *) false ;; esac; then
      _rsz_add "$f" "$f"
    elif [ -f "$f" ]; then
      while IFS= read -r line || [ -n "$line" ]; do
        line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        case "$line" in ""|"#"*) continue ;; esac
        case "$line" in /*) _rsz_add "$line" "$line" ;; *) _rsz_add "$line" "$_RSZ_ROOT/$line" ;; esac
      done < "$f"
    else
      _rsz_usage "input is neither a directory, an item nor an item list: $f"
    fi
    i=$((i+1))
  done

  # 2. The companion rules, loaded once (absent ⇒ the planner's one stderr note; malformed ⇒ exit 1).
  ( _pw_load_companions "$_RSZ_ROOT" ) || exit 1

  # 3. One verdict per row.
  i=0
  while IFS="$tab" read -r kind disp f; do
    if [ "$kind" = doc ]; then
      _rsz_plan_doc_check "$f" > "$_RSZ_TMP/pd"
      pd="$(head -n1 "$_RSZ_TMP/pd")"
      case "$pd" in
        ok) printf '%s: plan doc: sections ok\n' "$disp" >> "$_RSZ_TMP/out" ;;
        unknown) printf '%s: plan doc: sections unknown (template unreadable)\n' "$disp" >> "$_RSZ_TMP/out" ;;
        *) printf '%s: plan doc: missing: %s\n' "$disp" "$(env LC_ALL=C awk 'NR > 1 { printf ", " } { printf "%s", $0 }' "$_RSZ_TMP/pd")" >> "$_RSZ_TMP/out" ;;
      esac
      if [ "$json" = 1 ]; then
        "$JQ" -nc --arg item "$disp" --rawfile pd "$_RSZ_TMP/pd" '($pd | split("\n") | map(select(length > 0))) as $l
          | {item: $item, verdict: null, files: null, scope_items: null, criteria: null, parts: null, causes: [], candidates: [],
             plan_doc: (if $l == ["ok"] then "ok" elif $l == ["unknown"] then "unknown" else $l end),
             measurements: null, touches_why: null}' >> "$_RSZ_TMP/objs"
      fi
      i=$((i+1)); continue
    fi
    abs="$(_pw_abs "$f")"
    st="$(_rsz_set "$f" "$_RSZ_ROOT" "$_RSZ_TMP/s.$i")"
    why=""; files=""
    if [ "$st" = known ]; then files="$(_rsz_count "$_RSZ_TMP/s.$i" "$_RSZ_ROOT")"; else why="${st#unknown }"; fi
    read -r sc cr pa ms <<EOF
$(env LC_ALL=C awk "$_RSZ_SECT_AWK" "$f")
EOF
    causes=""; : > "$_RSZ_TMP/cand"
    if [ -n "$files" ] && [ "$files" -gt "$L" ]; then causes="files"; fi
    if [ "$pa" -gt "$P" ]; then causes="${causes:+$causes }parts"; fi
    if [ -n "$causes" ]; then verdict=large
    elif [ "$st" != known ]; then verdict=unknown   # never small: an unknown set is not a small one
    elif [ "$files" -le "$S" ]; then verdict=small
    else verdict=ok
    fi
    case "$verdict" in
      large)
        line=""
        case " $causes " in *" files "*) line="$files files" ;; esac
        case " $causes " in *" parts "*) line="${line:+$line, }$pa parts" ;; esac
        printf '%s: large (%s) — will not fit one PR: split by Part\n' "$disp" "$line" >> "$_RSZ_TMP/out" ;;
      unknown)
        causes="touches_unknown"
        printf '%s: unknown (Touches %s)\n' "$disp" "$why" >> "$_RSZ_TMP/out" ;;
      small)
        _rsz_candidates "$abs" "$_RSZ_TMP/s.$i" > "$_RSZ_TMP/cand"
        cand="$(env LC_ALL=C awk -F '\t' 'NR > 1 { printf ", " }
          { printf "%s (%s shared files%s%s)", $4, $1, ($2 == 1 ? ", same chain" : ""), ($3 == 1 ? ", same folder" : "") }' "$_RSZ_TMP/cand")"
        printf '%s: small (%s files, %s scope items, %s criteria) — merge candidates: %s\n' "$disp" "$files" "$sc" "$cr" "${cand:-none}" >> "$_RSZ_TMP/out" ;;
      ok)
        printf '%s: ok (%s files, %s scope items, %s criteria)\n' "$disp" "$files" "$sc" "$cr" >> "$_RSZ_TMP/out" ;;
    esac
    if [ "$ms" = no_frozen_commit ]; then printf '%s: measurements: no frozen commit named\n' "$disp" >> "$_RSZ_TMP/out"; fi
    if [ "$json" = 1 ]; then
      "$JQ" -nc --arg item "$disp" --arg verdict "$verdict" --arg files "$files" --arg sc "$sc" --arg cr "$cr" --arg pa "$pa" \
        --arg causes "$causes" --arg ms "$ms" --arg why "$why" --rawfile cand "$_RSZ_TMP/cand" '
        {item: $item, verdict: $verdict, files: (if $files == "" then null else ($files | tonumber) end),
         scope_items: ($sc | tonumber), criteria: ($cr | tonumber), parts: ($pa | tonumber),
         causes: ($causes | split(" ") | map(select(length > 0))),
         candidates: ($cand | split("\n") | map(select(length > 0) | split("\t")
           | {item: .[3], shared_files: (.[0] | tonumber), same_chain: (.[1] == "1"), same_folder: (.[2] == "1")})),
         plan_doc: null, measurements: (if $ms == "no_frozen_commit" then "no_frozen_commit" else null end),
         touches_why: (if $why == "" then null else $why end)}' >> "$_RSZ_TMP/objs"
    fi
    i=$((i+1))
  done < "$_RSZ_TMP/rows"

  if [ "$json" = 1 ]; then "$JQ" -s . "$_RSZ_TMP/objs"; else cat "$_RSZ_TMP/out"; fi
}

# --------------------------------------------------------------------------- #
# merge-items (header above)
# --------------------------------------------------------------------------- #

# _MI_BODY_AWK — an original's Part body: everything but its title, Status line(s) and Depends on /
# Touches sections; headings outside fences demoted one level; blank runs outside fences collapsed.
_MI_BODY_AWK='
  function out(s) { if (pend && seen) print ""; pend = 0; seen = 1; print s }
  BEGIN { fence = 0; t1 = 0; skip = 0; pend = 0; seen = 0 }
  /^```/ { if (!skip) out($0); fence = !fence; next }
  fence { if (!skip) out($0); next }
  !t1 && /^# / { t1 = 1; next }
  index($0, "## Status:") == 1 { skip = 0; next }
  /^# / || /^## / { skip = ($0 == "## Depends on" || $0 == "## Touches"); if (!skip) out("#" $0); next }
  $0 == "<!-- loomwright:requirement-closeout -->" { skip = 0; out($0); next }
  skip { next }
  /^#+ / { match($0, /^#+/); if (RLENGTH < 6) out("#" $0); else out($0); next }
  /^[ \t]*$/ { pend = 1; next }
  { out($0) }'

# _MI_MUST_AWK — the post-check's own list of the lines an original's Part must carry (a): every
# non-blank, non-heading line outside its Status line and Depends on / Touches sections.
_MI_MUST_AWK='
  /^```/ { f = !f; if (!s) print; next }
  f { if (!s && $0 !~ /^[ \t]*$/) print; next }
  index($0, "## Status:") == 1 { s = 0; next }
  /^# / || /^## / { s = ($0 == "## Depends on" || $0 == "## Touches"); next }
  $0 == "<!-- loomwright:requirement-closeout -->" { s = 0 }
  s { next }
  /^#+ / { next }
  /^[ \t]*$/ { next }
  { print }'

# _MI_DEPLINES_AWK — `<NR>\t<line>` for each non-blank line of the `## Depends on` section (the
# planner's section boundary).
_MI_DEPLINES_AWK='
  /^```/ { f = !f; next }
  !f && (/^# / || /^## /) { s = ($0 == "## Depends on"); next }
  !f && $0 == "<!-- loomwright:requirement-closeout -->" { s = 0; next }
  s && $0 !~ /^[ \t]*$/ { print NR "\t" $0 }'

# _mi_title <file> — the text of its first `# ` heading outside fences, else its file name stem.
_mi_title() {
  local t
  t="$(env LC_ALL=C awk '/^```/ { f = !f; next } !f && /^# / { print substr($0, 3); exit }' "$1")"
  if [ -z "$t" ]; then t="$(basename "$1" .md)"; fi
  printf '%s\n' "$t"
}

# _mi_status_lines <file> — its `## Status:` lines outside fences.
_mi_status_lines() {
  env LC_ALL=C awk '/^```/ { f = !f; next } !f && index($0, "## Status:") == 1' "$1"
}

# _mi_rel <from dir (abs)> <to file (abs)> — the relative path from the directory to the file.
_mi_rel() {
  local common="$1" up=""
  while :; do
    case "$2" in "$common"/*) break ;; esac
    if [ "$common" = / ]; then break; fi
    common="$(dirname "$common")"; up="../$up"
  done
  if [ "$common" = / ]; then printf '%s%s\n' "$up" "${2#/}"; else printf '%s%s\n' "$up" "${2#"$common"/}"; fi
}

# _mi_part <staged out> <label> — the lines of that Part's section (title line excluded).
_mi_part() {
  MI_L="$2" env LC_ALL=C awk 'BEGIN { want = "## Part " ENVIRON["MI_L"] " — " }
    !on && !done && index($0, want) == 1 { on = 1; next }
    on && ($0 ~ /^## Part [A-Z] — / || $0 == "## Depends on") { on = 0; done = 1 }
    on { print }' "$1"
}

# _mi_postcheck <staged out> <out abs> <out fragment> <n> — checks (a)–(d) over originals 0..n-1
# (MI_ABS / MI_FILE / MI_LAB arrays and the staged originals $_RSZ_TMP/orig.<i>); one stderr line per
# loss; prints `<body> <touches> <depends>` checked counts; non-zero on any loss.
_mi_postcheck() {
  local so="$1" oabs="$2" frag="$3" n="$4" i lost=0 nb=0 nt=0 nd=0 l t m hit j x
  _pw_touches "$so" > "$_RSZ_TMP/pc.mt"
  if [ "$(head -n1 "$_RSZ_TMP/pc.mt")" != known ]; then echo "merge-items: post-check: the merged ## Touches does not parse" >&2; lost=$((lost+1)); fi
  sed '1d' "$_RSZ_TMP/pc.mt" > "$_RSZ_TMP/pc.mtl"
  _pw_depends "$so" > "$_RSZ_TMP/pc.md"
  if [ "$(head -n1 "$_RSZ_TMP/pc.md")" = missing ]; then echo "merge-items: post-check: the merged ## Depends on does not parse" >&2; lost=$((lost+1)); fi
  : > "$_RSZ_TMP/pc.mdt"
  while IFS= read -r m; do
    case "$m" in none|missing|"") continue ;; esac
    x="$(_pw_resolve_dep "$oabs" "$m")" || x="?$m"
    printf '%s\n' "$x" >> "$_RSZ_TMP/pc.mdt"
  done < "$_RSZ_TMP/pc.md"
  i=0
  while [ "$i" -lt "$n" ]; do
    # (a) body lines, as often as in the original
    env LC_ALL=C awk "$_MI_MUST_AWK" "${MI_FILE[i]}" > "$_RSZ_TMP/pc.must"
    nb=$((nb + $(env LC_ALL=C awk 'END { print NR }' "$_RSZ_TMP/pc.must")))
    _mi_part "$so" "${MI_LAB[i]}" > "$_RSZ_TMP/pc.part"
    env LC_ALL=C awk -v lab="${MI_LAB[i]}" 'FILENAME == ARGV[1] { P[$0]++; next }
      { if (P[$0] > 0) P[$0]--; else { print "merge-items: post-check: Part " lab " lost body line: " $0 > "/dev/stderr"; bad++ } }
      END { exit bad ? 1 : 0 }' "$_RSZ_TMP/pc.part" "$_RSZ_TMP/pc.must" || lost=$((lost+1))
    # (b) Touches lines
    _pw_touches "${MI_FILE[i]}" | sed '1d' > "$_RSZ_TMP/pc.ot"
    while IFS= read -r l; do
      nt=$((nt+1))
      case "$l" in changelog.d/*/*) t="$l" ;; changelog.d/*.md) t="$frag" ;; *) t="$l" ;; esac
      if ! grep -qxF -- "$t" "$_RSZ_TMP/pc.mtl"; then echo "merge-items: post-check: Part ${MI_LAB[i]} lost Touches line: $l" >&2; lost=$((lost+1)); fi
    done < "$_RSZ_TMP/pc.ot"
    # (c) Depends on lines (by the file they resolve to)
    _pw_depends "${MI_FILE[i]}" > "$_RSZ_TMP/pc.od"
    while IFS= read -r l; do
      case "$l" in none|missing|"") continue ;; esac
      x="$(_pw_resolve_dep "${MI_ABS[i]}" "$l")" || x=""
      hit=0; j=0
      while [ "$j" -lt "$n" ]; do if [ -n "$x" ] && [ "$x" = "${MI_ABS[j]}" ]; then hit=1; fi; j=$((j+1)); done
      if [ "$hit" = 1 ]; then continue; fi   # a reference to an original folds away
      nd=$((nd+1))
      if [ -z "$x" ]; then x="?$l"; fi
      if ! grep -qxF -- "$x" "$_RSZ_TMP/pc.mdt"; then echo "merge-items: post-check: Part ${MI_LAB[i]} lost Depends on line: $l" >&2; lost=$((lost+1)); fi
    done < "$_RSZ_TMP/pc.od"
    # (d) the Status line is not carried; the staged original carries its stamp
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      if grep -qxF -- "$l" "$so"; then echo "merge-items: post-check: Part ${MI_LAB[i]} carried its Status line: $l" >&2; lost=$((lost+1)); fi
    done <<EOF
$(_mi_status_lines "${MI_FILE[i]}")
EOF
    if ! grep -qxF -- "${MI_STAMP[i]}" "$_RSZ_TMP/orig.$i"; then echo "merge-items: post-check: original ${MI_LAB[i]} is not stamped parked" >&2; lost=$((lost+1)); fi
    i=$((i+1))
  done
  printf '%s %s %s\n' "$nb" "$nt" "$nd"
  [ "$lost" -eq 0 ]
}

merge_items() {
  local out="" title="" goal="" date="" root="" a lab f n=0 i j k req oabs odir orel oslug frag x t key tab line cnt d
  local MI_ABS=() MI_FILE=() MI_LAB=() MI_STAMP=() MI_GIVEN=()
  tab="$(printf '\t')"
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) [ $# -ge 2 ] || _mi_usage "--title requires a value"; title="$2"; shift 2 ;;
      --goal)  [ $# -ge 2 ] || _mi_usage "--goal requires a value"; goal="$2"; shift 2 ;;
      --date)  [ $# -ge 2 ] || _mi_usage "--date requires a value"; date="$2"; shift 2 ;;
      --root)
        case "${2:-}" in ""|-*) _mi_usage "--root requires a checkout path (got '${2:-}')" ;; esac
        root="$2"; shift 2 ;;
      -*) _mi_usage "unknown option $1" ;;
      *)
        if [ -z "$out" ]; then out="$1"
        else
          case "$1" in [A-Z]:?*) lab="${1%%:*}"; f="${1#?:}" ;; *) _mi_usage "an original is <X>:<file.md>, X one capital letter (got $1)" ;; esac
          j=0; while [ "$j" -lt "$n" ]; do [ "${MI_LAB[j]}" != "$lab" ] || _mi_usage "label $lab given twice"; j=$((j+1)); done
          MI_LAB[n]="$lab"; MI_GIVEN[n]="$f"; n=$((n+1))
        fi
        shift ;;
    esac
  done
  [ -n "$out" ] || _mi_usage "missing <out.md>"
  case "$out" in *.md) ;; *) _mi_usage "<out.md> must end in .md (got $out)" ;; esac
  [ -n "$title" ] || _mi_usage "missing --title"
  case "$title" in *"$NL_CHAR"*) _mi_usage "--title must be one line" ;; esac
  [ -n "$goal" ] || _mi_usage "missing --goal"
  [ -n "$date" ] || date="$(date -u +%Y-%m-%d)"
  case "$date" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) _mi_usage "--date must be YYYY-MM-DD (got $date)" ;; esac
  [ "$n" -ge 2 ] || _mi_usage "at least two <X>:<original.md> are needed"
  _RSZ_ROOT="$(_rsz_root "$root")" || _mi_usage "--root is not a directory"
  [ -n "$_RSZ_ROOT" ] || _mi_usage "--root is not a directory"
  req="$_RSZ_ROOT/.supervisor/requirements"
  [ -d "$req" ] || _mi_fail "no requirements tree: $req"
  [ ! -e "$out" ] || _mi_fail "<out.md> already exists: $out"
  oabs="$(_pw_abs "$out")" || _mi_fail "the folder of <out.md> does not exist: $out"
  case "$oabs" in "$req/"*) ;; *) _mi_fail "<out.md> must lie under $req (got $out)" ;; esac
  odir="$(dirname "$oabs")"; orel="${oabs#"$req"/}"; oslug="${orel%.md}"; oslug="$(printf '%s' "$oslug" | tr '/' '-')"
  frag="changelog.d/$oslug.md"
  _RSZ_TMP="$(mktemp -d)" || _mi_fail "mktemp -d failed"
  trap 'rm -rf "$_RSZ_TMP"' EXIT

  # 1. Originals: readable, under the tree, distinct, and mergeable.
  i=0
  while [ "$i" -lt "$n" ]; do
    f="${MI_GIVEN[i]}"
    case "$f" in *.md) ;; *) _mi_fail "original ${MI_LAB[i]} is not a *.md file: $f" ;; esac
    [ -f "$f" ] || _mi_fail "original ${MI_LAB[i]} not found: $f"
    a="$(_pw_abs "$f")" || _mi_fail "original ${MI_LAB[i]} not found: $f"
    case "$a" in "$req/"*) ;; *) _mi_fail "original ${MI_LAB[i]} must lie under $req (got $f)" ;; esac
    j=0; while [ "$j" -lt "$i" ]; do [ "${MI_ABS[j]}" != "$a" ] || _mi_fail "original $f given twice"; j=$((j+1)); done
    if is_done "$a"; then _mi_fail "refused: original ${MI_LAB[i]} is done: $f"; fi
    case "$a" in */operator-run/*) _mi_fail "refused: original ${MI_LAB[i]} is under operator-run/: $f" ;; esac
    if grep -q '^## Status:[[:space:]]*parked (merged' "$a"; then _mi_fail "refused: original ${MI_LAB[i]} is already merged: $f"; fi
    if [ "$(_pw_touches "$a" | head -n1)" != known ]; then _mi_fail "refused: original ${MI_LAB[i]} has no known ## Touches (fix it first): $f"; fi
    if [ "$(_pw_depends "$a" | head -n1)" = missing ]; then _mi_fail "refused: original ${MI_LAB[i]} has a missing or unparsable ## Depends on (fix it first): $f"; fi
    MI_ABS[i]="$a"; MI_FILE[i]="$a"
    MI_STAMP[i]="## Status: parked (merged $date into $orel as Part ${MI_LAB[i]} — do not run this file)"
    i=$((i+1))
  done

  # 2. Cycle: a dependency path from an original, through a non-original, back to an original.
  _rsz_edges "$req" "$_RSZ_TMP/edges"
  { printf 'M'; i=0; while [ "$i" -lt "$n" ]; do printf '\t%s' "${MI_ABS[i]}"; i=$((i+1)); done; printf '\n'; } > "$_RSZ_TMP/mq"
  if [ "$(env LC_ALL=C awk "$_RSZ_GRAPH_AWK" "$_RSZ_TMP/edges" "$_RSZ_TMP/mq")" = 1 ]; then _mi_fail "refused: merging these originals would make a dependency cycle"; fi

  # 3. The merged item, staged.
  : > "$_RSZ_TMP/deps"; : > "$_RSZ_TMP/depkeys"; : > "$_RSZ_TMP/touch"
  i=0
  while [ "$i" -lt "$n" ]; do
    _pw_depends "${MI_ABS[i]}" > "$_RSZ_TMP/od"
    while IFS= read -r line; do
      case "$line" in none|missing|"") continue ;; esac
      x="$(_pw_resolve_dep "${MI_ABS[i]}" "$line")" || x=""
      j=0; k=0; while [ "$j" -lt "$n" ]; do if [ -n "$x" ] && [ "$x" = "${MI_ABS[j]}" ]; then k=1; fi; j=$((j+1)); done
      if [ "$k" = 1 ]; then continue; fi
      if [ -n "$x" ]; then key="$x"; else key="?$line"; fi
      if grep -qxF -- "$key" "$_RSZ_TMP/depkeys"; then continue; fi
      printf '%s\n' "$key" >> "$_RSZ_TMP/depkeys"
      if [ -n "$x" ] && [ "$(dirname "${MI_ABS[i]}")" != "$odir" ]; then t="$(_mi_rel "$odir" "$x")"; else t="$line"; fi
      printf '%s\n' "$t" >> "$_RSZ_TMP/deps"
    done < "$_RSZ_TMP/od"
    _pw_touches "${MI_ABS[i]}" | sed '1d' >> "$_RSZ_TMP/touch"
    i=$((i+1))
  done
  if grep -qE '^changelog\.d/[^/]+\.md$' "$_RSZ_TMP/touch"; then
    { grep -vE '^changelog\.d/[^/]+\.md$' "$_RSZ_TMP/touch" || true; printf '%s\n' "$frag"; } > "$_RSZ_TMP/touch2"
  else
    cp "$_RSZ_TMP/touch" "$_RSZ_TMP/touch2"
  fi
  {
    printf '# %s\n\n' "$title"
    printf '## Merged from (%s)\n' "$date"
    i=0; while [ "$i" -lt "$n" ]; do
      printf -- '- Part %s: `%s` — %s\n' "${MI_LAB[i]}" "$(_mi_rel "$odir" "${MI_ABS[i]}")" "$(_mi_title "${MI_ABS[i]}")"; i=$((i+1))
    done
    printf '\nThe originals are parked with a pointer here. Their text is kept below VERBATIM as parts (headings\n'
    printf 'demoted one level, their Status / Depends on / Touches folded into this file'"'"'s own sections). Nothing was paraphrased.\n\n'
    printf '## Goal\n%s\n' "$goal"
    i=0; while [ "$i" -lt "$n" ]; do
      printf '\n## Part %s — %s\n\n' "${MI_LAB[i]}" "$(_mi_title "${MI_ABS[i]}")"
      env LC_ALL=C awk "$_MI_BODY_AWK" "${MI_ABS[i]}"
      i=$((i+1))
    done
    printf '\n## Depends on\n'
    if [ -s "$_RSZ_TMP/deps" ]; then cat "$_RSZ_TMP/deps"; else echo none; fi
    printf '\n## Touches\n'
    env LC_ALL=C sort -u "$_RSZ_TMP/touch2"
  } > "$_RSZ_TMP/out.md"

  # 4. The originals, restamped (staged).
  i=0
  while [ "$i" -lt "$n" ]; do
    if [ -n "$(_mi_status_lines "${MI_ABS[i]}")" ]; then
      MI_S="${MI_STAMP[i]}" env LC_ALL=C awk 'BEGIN { s = ENVIRON["MI_S"] }
        /^```/ { f = !f; print; next }
        !f && !done && index($0, "## Status:") == 1 { print s; done = 1; next }
        { print }' "${MI_ABS[i]}" > "$_RSZ_TMP/orig.$i"
    else
      MI_S="${MI_STAMP[i]}" env LC_ALL=C awk 'BEGIN { s = ENVIRON["MI_S"] }
        /^```/ { f = !f; print; next }
        !f && !done && /^# / { print; print ""; print s; done = 1; next }
        { print }
        END { if (!done) { print ""; print s } }' "${MI_ABS[i]}" > "$_RSZ_TMP/orig.$i"
    fi
    i=$((i+1))
  done

  # 5. Dependents re-pointed (staged): `<staged>\t<target>` rows in $_RSZ_TMP/dependents.
  : > "$_RSZ_TMP/dependents"; k=0
  while IFS= read -r d; do
    j=0; x=0; while [ "$j" -lt "$n" ]; do if [ "$d" = "${MI_ABS[j]}" ]; then x=1; fi; j=$((j+1)); done
    if [ "$x" = 1 ]; then continue; fi
    if is_run_file "$d"; then continue; fi
    case "$(_pw_depends "$d" | head -n1)" in missing|none|"") continue ;; esac
    env LC_ALL=C awk "$_MI_DEPLINES_AWK" "$d" > "$_RSZ_TMP/dl"
    : > "$_RSZ_TMP/edits"; : > "$_RSZ_TMP/seen"; cnt=0
    while IFS="$tab" read -r a line; do
      x="$(_pw_resolve_dep "$d" "$line")" || x=""
      j=0; t=""; while [ "$j" -lt "$n" ]; do if [ -n "$x" ] && [ "$x" = "${MI_ABS[j]}" ]; then t=1; fi; j=$((j+1)); done
      if [ -n "$t" ]; then key="$oabs"; else key="${x:-?$line}"; fi
      if grep -qxF -- "$key" "$_RSZ_TMP/seen"; then printf '%s\tD\n' "$a" >> "$_RSZ_TMP/edits"; cnt=$((cnt+1)); continue; fi
      printf '%s\n' "$key" >> "$_RSZ_TMP/seen"
      if [ -n "$t" ]; then printf '%s\tR\t%s\n' "$a" "$(_mi_rel "$(dirname "$d")" "$oabs")" >> "$_RSZ_TMP/edits"; cnt=$((cnt+1)); fi
    done < "$_RSZ_TMP/dl"
    if ! grep -q "${tab}R${tab}" "$_RSZ_TMP/edits"; then continue; fi
    env LC_ALL=C awk -F '\t' 'FILENAME == ARGV[1] { A[$1] = $2; T[$1] = $3; next }
      (FNR in A) { if (A[FNR] == "R") print T[FNR]; next } { print }' "$_RSZ_TMP/edits" "$d" > "$_RSZ_TMP/dep.$k"
    printf '%s\t%s\n' "$_RSZ_TMP/dep.$k" "$d" >> "$_RSZ_TMP/dependents"
    k=$((k+1))
  done < "$_RSZ_TMP/edges.files"

  # 6. The lost-line post-check, then the writes (out first, then dependents, then originals).
  if [ -n "${LOOMWRIGHT_MERGE_ITEMS_DROP:-}" ]; then
    { grep -vxF -- "$LOOMWRIGHT_MERGE_ITEMS_DROP" "$_RSZ_TMP/out.md" || true; } > "$_RSZ_TMP/out.seam"; mv -f "$_RSZ_TMP/out.seam" "$_RSZ_TMP/out.md"
  fi
  cnt="$(_mi_postcheck "$_RSZ_TMP/out.md" "$oabs" "$frag" "$n")" || _mi_fail "post-check failed — nothing written"
  read -r a t x <<EOF
$cnt
EOF
  echo "merge-items: post-check ok — 0 lost lines ($a body, $t Touches, $x Depends on lines checked)"
  # create-only: a hard link never replaces a file that appeared since the existence check
  cp "$_RSZ_TMP/out.md" "$oabs.mi.$$" || _mi_fail "could not write $out"
  if ! ln "$oabs.mi.$$" "$oabs" 2>/dev/null; then rm -f "$oabs.mi.$$"; _mi_fail "<out.md> appeared while merging, or could not be created: $out — nothing written"; fi
  rm -f "$oabs.mi.$$"
  echo "merge-items: wrote $out"
  while IFS="$tab" read -r a d; do
    cp "$a" "$d.mi.$$" && mv -f "$d.mi.$$" "$d" || _mi_fail "could not re-point $d"
    echo "merge-items: re-pointed $(_rsz_disp "$d" "$_RSZ_ROOT" "$d")"
  done < "$_RSZ_TMP/dependents"
  i=0
  while [ "$i" -lt "$n" ]; do
    cp "$_RSZ_TMP/orig.$i" "${MI_ABS[i]}.mi.$$" && mv -f "${MI_ABS[i]}.mi.$$" "${MI_ABS[i]}" || _mi_fail "could not stamp ${MI_GIVEN[i]}"
    echo "merge-items: parked ${MI_GIVEN[i]} (Part ${MI_LAB[i]})"
    i=$((i+1))
  done
}
