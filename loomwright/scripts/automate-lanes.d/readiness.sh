# ==================================================================================================
# lane-readiness <lane_dir|L<n>> — writes <lane>/.supervisor/automate/<run_id>.merge-readiness.md
# (advisory, never a merge executor). Five checks, each PASS / FAIL / NOT-RUN with its evidence:
#   validation     each `## Validation` entry of the item: PASS only with pasted output (a fenced block)
#                  in the PR body's matching section; mentioned without output, or absent ⇒ NOT-RUN
#   carried-notes  the brief's carried MEDIUM/LOW Plan Review notes, accounted for in the PR body
#   scope-fence    `gh pr diff --name-only` ⊆ the item's Touches set as the planner reserved it (`plan-waves
#                  --touches`: strict grammar + companions) / the brief's lanes + changelog.d/; advisory —
#                  whether drift collides with another lane of the same wave is wave-plan / wave-build's
#                  overlap check (wave.sh _lanes_wave_overlap), not this per-lane report
#   gates          required checks on the current head, dismissed-finding decisions, children-settled
#   headline-repro the Validation entry naming a mutation / repro (PASS n/a when none is named)
# Called by the lane at its ready_for_release park; re-written on demand (`lane-status --refresh-readiness`,
# which also covers a lane already closed out — `done` — so a report written before a fix is repairable).
# _lanes_rd_section <n> <title> <body_file> [nv] [<others>] [<tm>] — the PR body's lines for Validation
# entry n. With the 4th argument `nv` it prints instead ONE line: `NV` when any matched block starts
# under a PR-body heading (at any enclosing level) containing "not verified" or "not run"; else `NL`
# when such a heading says "skipped", or ANY non-fenced line of a matched block (its first line, a
# continuation, a heading-started section's body) says "not run" / "skipped" / "not verified" (or
# "not yet run", "wasn't run", "couldn't run", "could not get to", "not tested", "untested" — "was
# not run" / "could not run" are already "not run"; any such heading text is a "not run" heading) — each
# as a whole phrase, never inside a longer word ("not running hot" is not "not run"); else nothing —
# the same match, so the not-run tests can never drift from the evidence test. Fenced lines never raise
# NL (pasted output that says "skipped" is output, not the PR's statement). <others> is the item's
# entry titles, newline-separated; <tm> 0 disables the title match (a title another entry's title
# contains is not unique — that entry needs its own "validation <n>"). Titles are read through
# ENVIRON (awk -v would rewrite a backslash). Fence-aware: a line inside a ``` / ~~~ block (shell
# comments, `#!`, root prompts, pasted output) is never a heading, never starts a match, never ends one.
#   heading      `#`..`######` + a space, or a whole-line bold `**…**` naming "not verified" / "not run"
#                / "skipped" (a pseudo-heading below every `#` level)
#   match start  a line naming "validation <n>" (an anchored match), or containing the entry's title
#                (a title match, only when <tm> is not 0 and the line names no "validation <m>" —
#                another step's anchored line is never borrowed by a title)
#   match end    any heading; a line naming another "validation <m>"; for a match that started on a
#                list item, the next list item at the same or a shallower indent; for any non-heading
#                start, an unindented non-fence paragraph after a blank line that is a list item or
#                names another entry's title — and, for a title match, ANY such paragraph (a generic
#                mention never borrows the next paragraph's fence). An anchored match crosses such a
#                paragraph break ONLY when the last non-blank, non-fenced line before it ends in `:`
#                (an intro line: "Validation 1 (tests):" / blank / "Ran the suite:" / blank / fence
#                stays one passage) or, at its FIRST break only, when the new paragraph's line itself
#                ends in `:` (the step's sentence, then "Output:", then the fence); otherwise it closes,
#                so "… needs a quiet machine." / "CI is green." / "Shellcheck output:" + fence never
#                borrows that fence. The shape "<step sentence>." / "<x> output:" + fence is the same
#                for a run step and an unrun one — only the not-run vocabulary tells them apart. An
#                indented line never closes a match by this paragraph rule
_lanes_rd_section() {
  _RD_T="$2" _RD_O="${5:-}" awk -v n="$1" -v mode="${4:-}" -v tm="${6:-1}" '
    BEGIN { t = tolower(ENVIRON["_RD_T"]); vn = "validation[ #]*" n "([^0-9]|$)"; no = split(tolower(ENVIRON["_RD_O"]), ot, "\n") }
    function ind(s) { match(s, /^[ \t]*/); return RLENGTH }
    function ph(s, p,  st, i, j) { st = 1   # p in s as a whole phrase: no letter/digit on either side
      while ((i = index(substr(s, st), p)) > 0) { j = st + i - 1
        if ((j == 1 || substr(s, j - 1, 1) !~ /[a-z0-9]/) && substr(s, j + length(p), 1) !~ /[a-z0-9]/) return 1
        st = j + 1 }
      return 0 }
    function nrv(s) { return ph(s, "not verified") || ph(s, "not run") || ph(s, "not yet run") ||
      ph(s, "wasn\047t run") || ph(s, "wasn\342\200\231t run") || ph(s, "couldn\047t run") ||
      ph(s, "couldn\342\200\231t run") || ph(s, "could not get to") || ph(s, "not tested") || ph(s, "untested") }
    function nrl(s) { return nrv(s) || ph(s, "skipped") }
    function oth(s,  i) { for (i = 1; i <= no; i++) if (ot[i] != "" && !index(t, ot[i]) && index(s, ot[i])) return 1; return 0 }
    { l = tolower($0); wasin = inf; fl = 0; hd = 0 }
    l ~ /^[ \t]*(```|~~~)/ {
      fl = 1; x = l; sub(/^[ \t]*/, "", x); c = substr(x, 1, 3)
      if (!inf) { inf = 1; fc = c } else if (c == fc) inf = 0
    }
    !wasin && !fl && l ~ /^#+[ \t]/ && match(l, /[^#]/) - 1 <= 6 { lv = RSTART - 1; hd = 1 }
    !wasin && !fl && !hd && l ~ /^[ \t]*\*\*.*\*\*[ \t]*:?[ \t]*$/ && nrl(l) { lv = 7; hd = 1 }
    hd { h[lv] = l; for (k = lv + 1; k <= 7; k++) delete h[k]; top = lv }
    { li = (l ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/) }
    on && !wasin && !fl && (hd || (l ~ /validation[ #]*[0-9]/ && l !~ vn) ||
        (sk == "b" && li && ind(l) <= si) ||
        (sk != "h" && blank && l !~ /^[ \t]/ && l !~ /^[ \t]*$/ &&
         (!sw || li || oth(l) || (lnb !~ /:$/ && (pb || l !~ /:[ \t\r]*$/))))) { on = 0 }
    on && !wasin && !fl && sk != "h" && blank && l !~ /^[ \t]/ && l !~ /^[ \t]*$/ { pb = 1 }
    !on && !wasin && !fl && (l ~ vn || (tm != 0 && t != "" && index(l, t) > 0 && l !~ /validation[ #]*[0-9]/)) {
      on = 1; si = ind(l); sw = (l ~ vn); pb = 0
      sk = hd ? "h" : (li ? "b" : "p")
      for (k = 1; k <= top; k++) if (k in h) { if (nrv(h[k])) nv = 1; else if (ph(h[k], "skipped")) nl = 1 }
    }
    on && !wasin && !fl && nrl(l) { nl = 1 }
    on && mode != "nv" { print }
    { blank = (!wasin && !fl && l ~ /^[ \t]*$/); if (!wasin && !fl && !blank) { lnb = l; sub(/[ \t\r]+$/, "", lnb) } }
    END { if (mode == "nv") { if (nv) print "NV"; else if (nl) print "NL" } }' "$3"
}

# _lanes_validation_rows <item_file> <body_file> <gh_ok> [<pr>] — THE Validation reader, shared by
# lane-readiness and validation-gate (af36-remainder/01: no second parser). One TSV row per entry of
# the item's `## Validation` section:  n<TAB>title<TAB>kind<TAB>status<TAB>evidence
#   entries   a column-0 numbered line (`N. ` or `N) `) OR a column-0 `- ` / `* ` / `+ ` bullet; an indented line, or an unindented one right after it (no blank line between),
#             continues the entry; a blank line followed by unindented text ends it. Fence-aware: a
#             ``` / ~~~ block's lines never start an entry or end the section (they join the open entry)
#   number    a numbered entry keeps its own N; the section's bullets are numbered M+1..M+k in order,
#             M = the LARGEST N of any numbered entry anywhere in the section (0 when none) — so a
#             purely bulleted section reads 1..k, a purely numbered one reads as written, and a bullet
#             can never share a number with a numbered entry (af36-remainder/01 drain round 1: `1.` +
#             `- **Running system:**` once read as two entries numbered 1, and the Baseline's
#             "Validation 1" evidenced the Running system step). Two numbered entries that still share
#             a number (`1.` / `1.` as written) are each NOT-RUN — an anchored "validation <n>" is
#             ambiguous there, and ambiguity never reads as evidence (fail CLOSED)
#   title     the entry's first line: its first `**…**` span, else its first 60 chars; trailing `:`
#             stripped; every `|` → `/` and tab runs → one space, so `V<n> <title>` is always a legal
#             `current-escalation --check` value; `(untitled)` when empty
#   kind      running-system — the TITLE contains "running system" (checked first: a gated step is
#             never shadowed by a "reproduce" in its first line) · repro — the FIRST line names a
#             mutation / repro ("mutation", "must catch", "repro", "must fail"; today's rule) ·
#             running-system — the joined entry text contains "running system" · other (case-insensitive)
#   status    gh_ok 0 ⇒ NOT-RUN (PR body unreadable). Else the PR body's matching lines
#             (_lanes_rd_section): none ⇒ NOT-RUN; under a "not verified" / "not run" heading, or any
#             non-fenced matched line saying "not run" / "skipped" / "not verified" (or another phrase of
#             _lanes_rd_section's not-run set) ⇒ NOT-RUN; no fence
#             line ⇒ NOT-RUN; a non-repro entry whose output shows the word FAIL ⇒ FAIL; else PASS
#   unique    an entry whose title (case-insensitive) equals or is contained in another entry's title
#             gets NO title match — e.g. two `- **Running system:**` bullets — so one passage can never
#             evidence two steps: each needs its own "validation <n>" in the PR body, else NOT-RUN
#   unparsed  a `## Validation` section that EXISTS but yields no entry (prose only, or an unsupported
#             list style) prints ONE row instead: 0<TAB>(no parseable entry)<TAB>unparsed<TAB>NOT-RUN<TAB>
#             <reason> — fail CLOSED, so an unreadable section never reads as "no running-system step"
# An unreadable item file, or one with no `## Validation` section, prints nothing (callers that must
# fail CLOSED check readability themselves).
_lanes_validation_rows() {
  local itemf="$1" body="$2" gh_ok="$3" pr="${4:-}" n title kind tm st ev sec nvs ents titles
  ents="$(awk '
    function flush() {
      if (!cur) return
      t = first
      if (match(t, /\*\*[^*]+\*\*/)) t = substr(t, RSTART + 2, RLENGTH - 4)
      else { sub(/^([0-9]+[.)]|[-*+]) */, "", t); t = substr(t, 1, 60) }
      sub(/:$/, "", t); gsub(/\|/, "/", t); gsub(/[ \t]*\t[ \t]*/, " ", t)
      if (t == "") t = "(untitled)"
      lf = tolower(first); lt = tolower(t); lj = tolower(full)
      if (index(lt, "running system")) k = "running-system"
      else if (lf ~ /mutation|must catch|repro|must fail/) k = "repro"
      else if (index(lj, "running system")) k = "running-system"
      else k = "other"
      print num "\t" t "\t" k
      cur = 0; ne++
    }
    { wasin = inf; fl = ($0 ~ /^[ \t]*(```|~~~)/) }
    fl { x = $0; sub(/^[ \t]*/, "", x); c = substr(x, 1, 3); if (!inf) { inf = 1; fc = c } else if (c == fc) inf = 0 }
    fl || wasin { if (on && cur) { x = $0; gsub(/\t/, " ", x); sub(/^ +/, "", x); full = full " " x }; blank = 0; next }
    /^## / { flush(); on = ($0 ~ /^## Validation/); if (on) sec = 1; blank = 0; next }
    !on { next }
    /^[0-9]+[.)] / { flush(); num = $0; sub(/[.)].*/, "", num); cur = 1; blank = 0
                   first = $0; gsub(/\t/, " ", first); full = first; next }
    /^[-*+] / { flush(); num = "b"; cur = 1; blank = 0
            first = $0; gsub(/\t/, " ", first); full = first; next }
    /^[ \t]*$/ { blank = 1; next }
    cur && ($0 ~ /^[ \t]/ || !blank) { x = $0; gsub(/\t/, " ", x); sub(/^ +/, "", x); full = full " " x; blank = 0; next }
    { flush(); blank = 0 }
    END { flush(); if (sec && !ne) print "U" }' "$itemf" 2>/dev/null |
    awk -F'\t' -v OFS='\t' '$0 == "U" { print; next } { r[NR] = $0; if ($1 != "b" && $1 + 0 > m) m = $1 + 0 }
      END { for (i = 1; i <= NR; i++) { if (!(i in r)) continue; $0 = r[i]; if ($1 == "b") $1 = ++m; print } }')"
  [ -n "$ents" ] || return 0
  # Fail CLOSED: a section that exists but yields no entry is never "no step" — one row, kind unparsed.
  if [ "$ents" = U ]; then
    printf '0\t(no parseable entry)\tunparsed\tNOT-RUN\t%s\n' "the ## Validation section has no parseable entry (an entry is a column-0 N. / N) / - / * / + list item)"
    return 0
  fi
  titles="$(cut -f2 <<<"$ents")"
  # 4th column tm: 0 when this title equals / is contained in another entry's title (no title match).
  # 5th column du: 1 when another entry carries the same number (numbered `1.` / `1.` as written).
  awk -F'\t' '{ r[NR] = $0; lt[NR] = tolower($2); nn[NR] = $1 + 0; c[$1 + 0]++ }
    END { for (i = 1; i <= NR; i++) { tm = 1; for (j = 1; j <= NR; j++) if (j != i && index(lt[j], lt[i])) tm = 0; print r[i] "\t" tm "\t" (c[nn[i]] > 1) } }' <<<"$ents" |
  while IFS="$(printf '\t')" read -r n title kind tm du; do
    [ -n "$n" ] || continue
    # (`${pr:-…}` expands to $pr itself when set — the old one-expression form printed the URL twice)
    if [ "$gh_ok" = 0 ]; then st=NOT-RUN; if [ -n "$pr" ]; then ev="PR body unreadable ($pr)"; else ev="PR body unreadable: no PR recorded"; fi
    elif [ "$du" = 1 ]; then st=NOT-RUN; ev="entry number $n is not unique in the item's ## Validation section (renumber the item)"
    else
      sec="$(_lanes_rd_section "$n" "$title" "$body" "" "$titles" "$tm")"
      if [ -z "$sec" ]; then st=NOT-RUN; ev="no evidence in the PR body"
      elif nvs="$(_lanes_rd_section "$n" "$title" "$body" nv "$titles" "$tm")" && [ "$nvs" = NV ]; then st=NOT-RUN; ev="listed under a \"Not verified\" / \"Not run\" heading in the PR body"
      elif [ -n "$nvs" ]; then st=NOT-RUN; ev="marked not run / skipped / not verified in the PR body"
      elif ! grep -qE '^[[:space:]]*(```|~~~)' <<<"$sec"; then st=NOT-RUN; ev="mentioned in the PR body without pasted output"
      elif [ "$kind" != repro ] && grep -qw 'FAIL' <<<"$sec"; then st=FAIL; ev="pasted output shows FAIL"
      else st=PASS; ev="pasted output in the PR body"; fi
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$title" "$kind" "$st" "$ev"
  done
}

# ---- the declared set: ONE reader for lane-readiness's scope fence AND wave.sh's _lanes_wave_overlap, so a
# file one of them calls declared the other never calls drift (PR #586 review: the overlap check once read
# Touches only, the fence Touches + the brief).
# _lanes_brief_of <lane_dir> <item> — the newest `.supervisor/jobs/*/*.md` brief naming <item>; empty when none.
_lanes_brief_of() {
  local bl
  [ -n "${2:-}" ] || return 0
  bl="$(grep -l -F "$2" "$1"/.supervisor/jobs/*/*.md 2>/dev/null)"
  [ -n "$bl" ] || return 0
  printf '%s\n' "$bl" | while IFS= read -r f; do ls -t "$f"; done 2>/dev/null | head -1
}
# _lanes_declared <lane_dir> <item> <brief> <out> — writes the declared set to <out>: the item's Touches set
# exactly as the planner reserved it for the wave (`plan-waves --touches`: the planner's own parser +
# companion expansion, so no reader parses a Touches section a second way) + the brief's `path:` lines.
# The planner's helper is called directly, never through the $HELPERS seam: it is read-only and must be the
# real grammar. Sets LD_TOUCHES (known | unknown) and LD_NOTE (empty, or the fence line's `; Touches …` note).
_lanes_declared() {
  local d="$1" item="$2" brief="$3" out="$4" tw
  LD_TOUCHES=known; LD_NOTE=""
  tw="$(bash "$HERE/automate-helpers.sh" plan-waves "$d/$item" --touches --root "$d" 2>/dev/null)" || tw=""
  case "$tw" in
    known*) ;;
    unknown*) LD_TOUCHES=unknown; LD_NOTE="; Touches ${tw} — only the brief's paths are declared (the item ran alone in its wave)"; tw="" ;;
    *) LD_TOUCHES=unknown; LD_NOTE="; Touches unreadable (plan-waves --touches failed) — only the brief's paths are declared"; tw="" ;;
  esac
  {
    [ -n "$tw" ] && printf '%s\n' "$tw" | sed '1d'   # already normalized: a top-level dir reads `src`
    [ -n "$brief" ] && sed -n 's/.*path: *"\([^"]*\)".*/\1/p; s/^ *- *"\([^"]*\)" *$/\1/p' "$brief" \
      | sed 's#^\./##' | awk 'index($0, "/") || index($0, ".")'
  } 2>/dev/null | env LC_ALL=C sort -u > "$out"
}
# _lanes_is_declared <file> <declared set file> — 0 when <file> is inside one entry: equal, a path ending in
# `/<entry>`, under `<entry>/` (a normalized directory), under an entry written with a trailing `/`, or
# matching an entry carrying `*` (a brief glob).
_lanes_is_declared() {
  local dcl
  while IFS= read -r dcl; do
    [ -n "$dcl" ] || continue
    case "$1" in "$dcl"|*/"$dcl"|"$dcl"/*) return 0 ;; esac
    case "$dcl" in */) case "$1" in "$dcl"*) return 0 ;; esac ;; esac
    # shellcheck disable=SC2254 # unquoted on purpose: a brief entry with `*` is a glob
    case "$dcl" in *'*'*) case "$1" in $dcl) return 0 ;; esac ;; esac
  done < "$2"
  return 1
}

lanes_readiness() {
  local target="${1:-}" dir
  dir="$(_lanes_resolve "$target")"
  _lane_ctx "$dir" || die "lane-readiness: not a lane: ${target:-<none>}"
  local rf="$LN_DIR/.supervisor/automate/$LN_RUN.md" out="$LN_DIR/.supervisor/automate/$LN_RUN.merge-readiness.md"
  local status pause pr lp pd item itemf tmp view="" head=unknown gh_ok=0 brief=""
  IFS="$(printf '\t')" read -r status pause pr lp pd <<<"$(_lanes_runfile_fields "$rf")"
  pr="$(_lanes_dash "$pr")"; pd="$(_lanes_dash "$pd")"
  item="$(sed -n 's/^- \[.\] //p' "$LN_DIR/.supervisor/lane-backlog.md" 2>/dev/null | head -1)"
  itemf="$LN_DIR/$item"
  tmp="$(mktemp -d 2>/dev/null)" || die "lane-readiness: no temp dir"
  : > "$tmp/body"; : > "$tmp/files"
  if [ -n "$pr" ] && view="$("$LANES_GH" pr view "$pr" --json body,headRefOid 2>/dev/null)" && jq -e 'type == "object"' >/dev/null 2>&1 <<<"$view"; then
    gh_ok=1; jq -r '.body // ""' <<<"$view" > "$tmp/body"; head="$(jq -r '.headRefOid // "unknown"' <<<"$view")"
  fi
  # ---- a + e: Validation entries (the shared reader — validation-gate reads the same rows)
  local vrows="" erows="" n title kind st ev vworst=PASS eworst=PASS vlabel=""
  _lanes_validation_rows "$itemf" "$tmp/body" "$gh_ok" "$pr" > "$tmp/val"
  while IFS="$(printf '\t')" read -r n title kind st ev; do
    [ -n "$n" ] || continue
    if [ "$kind" = repro ]; then
      erows="$erows  - V$n $title: $st — $ev
"
      case "$st" in FAIL) eworst=FAIL ;; NOT-RUN) [ "$eworst" = FAIL ] || eworst=NOT-RUN ;; esac
    else
      vrows="$vrows  - V$n $title: $st — $ev
"
      case "$st" in
        FAIL) vworst=FAIL ;;
        NOT-RUN) [ "$vworst" = FAIL ] || vworst=NOT-RUN ;;
      esac
      if [ "$st" != PASS ]; then
        case "$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')" in
          *"running system"*) case "$vlabel" in ''|running-system) vlabel=running-system ;; *) vlabel=validation ;; esac ;;
          *) vlabel=validation ;;
        esac
      fi
    fi
  done < "$tmp/val"
  local vline eline
  if [ ! -s "$tmp/val" ]; then vworst=NOT-RUN; vlabel=validation; vline="validation: NOT-RUN — no ## Validation section in $item"
  else vline="validation: $vworst — $(printf '%s' "$vrows" | grep -c ' PASS ' | tr -d ' ') of $(printf '%s' "$vrows" | grep -c '^  - ' | tr -d ' ') entr(ies) evidenced"; fi
  if [ -z "$erows" ]; then eworst=PASS; eline="headline-repro: PASS — n/a (the Validation names no repro)"
  else eline="headline-repro: $eworst — the Validation's named repro"; fi
  # ---- b: carried Plan Review notes
  local cline crows="" nc
  brief="$(_lanes_brief_of "$LN_DIR" "$item")"
  local cworst
  if [ -z "$item" ] || [ -z "$brief" ]; then cworst=NOT-RUN; cline="carried-notes: NOT-RUN — no brief naming $item found in the lane"
  else
    grep -iE 'carried' "$brief" | grep -E 'MEDIUM|LOW' | sed 's/^[[:space:]-]*//' > "$tmp/carried"
    nc="$(wc -l < "$tmp/carried" | tr -d ' ')"
    if [ "$nc" = 0 ]; then cworst=PASS; cline="carried-notes: PASS — none carried ($(basename "$brief"))"
    elif grep -qi 'carried' "$tmp/body"; then cworst=PASS; cline="carried-notes: PASS — $nc carried note(s), accounted for in the PR body"
    else cworst=NOT-RUN; cline="carried-notes: NOT-RUN — $nc carried note(s), no accounting in the PR body"; fi
    crows="$(sed 's/^/  - /' "$tmp/carried")"
  fi
  # ---- c: scope fence — declared = _lanes_declared (above): Touches as the planner reserved it + the brief.
  local fline frows="" fworst f outside="" tnote
  _lanes_declared "$LN_DIR" "$item" "$brief" "$tmp/declared"; tnote="$LD_NOTE"
  if [ -z "$pr" ] || ! "$LANES_GH" pr diff "$pr" --name-only > "$tmp/files" 2>/dev/null; then
    fworst=NOT-RUN; if [ -n "$pr" ]; then fline="scope-fence: NOT-RUN — gh pr diff unreadable ($pr)"; else fline="scope-fence: NOT-RUN — gh pr diff unreadable: no PR recorded"; fi
  else
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in changelog.d/*) continue ;; esac
      _lanes_is_declared "$f" "$tmp/declared" || outside="$outside$f
"
    done < "$tmp/files"
    if [ -z "$outside" ]; then fworst=PASS; fline="scope-fence: PASS — $(grep -c . "$tmp/files" | tr -d ' ') file(s) within the declared files + changelog.d/$tnote"
    else fworst=FAIL; fline="scope-fence: FAIL — file(s) outside the declared files + changelog.d/$tnote"; frows="$(printf '%s' "$outside" | sed '/^$/d; s/^/  - /')"; fi
  fi
  # ---- d: gates
  local gline grows="" gworst=PASS cj cs
  if [ -z "$pr" ]; then gworst=NOT-RUN; grows="  - required checks: NOT-RUN — no PR recorded"
  else
    cj="$("$LANES_GH" pr checks "$pr" --required --json name,bucket 2>/dev/null)" || true
    if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$cj"; then gworst=NOT-RUN; grows="  - required checks: NOT-RUN — unreadable"
    else
      cs="$(jq -r --arg h "$head" 'if length == 0 then "NOT-RUN — no required checks reported"
        elif any(.[]; .bucket == "fail" or .bucket == "cancel") then "FAIL — " + ([.[] | select(.bucket == "fail" or .bucket == "cancel") | .name] | join(", "))
        elif all(.[]; .bucket == "pass" or .bucket == "skipping") then "PASS — \(length) required check(s) green on \($h)"
        else "NOT-RUN — pending: " + ([.[] | select(.bucket != "pass" and .bucket != "skipping") | .name] | join(", ")) end' <<<"$cj")"
      grows="  - required checks: $cs"
      case "$cs" in FAIL*) gworst=FAIL ;; NOT-RUN*) gworst=NOT-RUN ;; esac
    fi
  fi
  case "$pd" in
    ''|0) grows="$grows
  - dismissed findings: PASS — none pending an owner decision" ;;
    *[!0-9]*) grows="$grows
  - dismissed findings: NOT-RUN — pending_decisions unreadable ($pd)"; [ "$gworst" = FAIL ] || gworst=NOT-RUN ;;
    *) grows="$grows
  - dismissed findings: FAIL — $pd without an owner decision"; gworst=FAIL ;;
  esac
  if grep -qiE 'children[-_ ]settled' "$rf" 2>/dev/null; then
    grows="$grows
  - children-settled: PASS — $(grep -iE 'children[-_ ]settled' "$rf" | tail -1 | sed 's/^- //' | _lanes_clip 160)"
  else
    grows="$grows
  - children-settled: NOT-RUN — not recorded in the run file"; [ "$gworst" = FAIL ] || gworst=NOT-RUN
  fi
  gline="gates: $gworst"
  # ---- score
  local pass=0 total=5 bad="" w lbl
  for w in "validation:$vworst" "carried-notes:$cworst" "scope-fence:$fworst" "gates:$gworst" "headline-repro:$eworst"; do
    lbl="${w%%:*}"; st="${w#*:}"
    if [ "$st" = PASS ]; then pass=$((pass + 1)); else
      [ "$lbl" = validation ] && lbl="${vlabel:-validation}"
      bad="$bad${bad:+, }$lbl $st"
    fi
  done
  local summary="ready ($pass/$total)"; [ -n "$bad" ] && summary="ready ($pass/$total: $bad)"
  # The group's status is its LAST command's, so every optional row is an `if` (never `[ -n … ] &&`,
  # which exits 1 on an empty row and read as a write failure — parallel-automate/23 F5). A non-zero
  # status here now means a real write failure (the redirect, or a printf into a full disk).
  if {
    echo "# Merge readiness: $LN_RUN"
    echo
    echo "- item: ${item:-unknown} | pr: ${pr:-none} | head: $head | written: $(now_utc)"
    echo "- score: $pass/$total | summary: $summary"
    echo "- advisory only: this report never merges; the owner merges by hand."
    echo
    echo "## Checks"
    echo "- $vline"; if [ -n "$vrows" ]; then printf '%s' "$vrows"; fi
    echo "- $cline"; if [ -n "$crows" ]; then printf '%s\n' "$crows"; fi
    echo "- $fline"; if [ -n "$frows" ]; then printf '%s\n' "$frows"; fi
    echo "- $gline"; printf '%s\n' "$grows"
    echo "- $eline"; if [ -n "$erows" ]; then printf '%s' "$erows"; fi
  } > "$out.tmp.$$" 2>/dev/null && mv "$out.tmp.$$" "$out"; then :
  else rm -f "$out.tmp.$$"; rm -rf "$tmp"; echo "lane-readiness: $LN_LANE — report not written (unwritable): $out"; return 0; fi
  rm -rf "$tmp"
  echo "lane-readiness: $LN_LANE ($LN_RUN) — $summary — $out"
  return 0
}

# ==================================================================================================
# validation-gate <runfile> <item> <pr_url> [--waive <n> --words <text>] (af36-remainder/01) — the
# READY-park correctness gate: every "Running system" step of the item's `## Validation` section must
# have pasted evidence in the PR body (the shared reader, _lanes_validation_rows). Takes the run file and
# the item explicitly (never _lane_ctx), so a lane and a sequential run call it the same way. A relative
# <item> resolves against the checkout owning <runfile> (<root>/.supervisor/automate/<run>.md), else $PWD.
# Read-only form — fails CLOSED, prints EXACTLY one line, always exits 0 (stdout IS the verdict):
#   validation-gate: none — no running-system step in <item>
#   validation-gate: ok — <k> running-system step(s) evidenced
#   validation-gate: waived — V<n> <title>[; V<m> <title>…]   every non-PASS running-system step waived
#   validation-gate: unrun — V<n> <title>: <evidence>          the first non-PASS, un-waived one (FAIL too)
#   validation-gate: unrun — <reason>                           unreadable item file, usage error
#   validation-gate: unrun — <item>: the ## Validation section has no parseable entry (…)   (step-less)
# A readable item with no running-system step is `none` without reading the PR — but a `## Validation`
# section the reader parses to zero entries is `unrun`, never `none`; an unreadable PR body
# makes every step NOT-RUN, so any running-system step reads `unrun`. Callers treat anything but
# none / ok / waived as unrun.
# Waiver form (--waive <n> --words <text>) — called by the engine ONLY with an interactive owner's
# answer, never on a can't-ask path — appends ONE `## Progress` line through progress-append:
#   <utc> validation waived: <item> V<n> <title> — owner: "<text>"
# (<item> with any leading `./` stripped). A waiver counts only for the item it names, and only AFTER
# the run file's LAST `picked <item>` line (a re-pick needs a new waiver). Refusals print
# `validation-gate: refused — <reason>` and exit 1 with nothing written: empty words, a `|` or newline
# in them, <n> not a running-system entry, an unreadable item file, no `picked <item>` line in the run
# file, or <item> not the item of the run file's LAST `picked` line (a waiver is only ever for the item
# being parked now). An identical waiver already counted ⇒ `waiver already recorded`, nothing written.
_lanes_vg_itemf() { # <runfile> <item> — the item file's path
  local rf="$1" it="$2" d
  case "$it" in /*) printf '%s' "$it"; return 0 ;; esac
  d="$(cd "$(dirname "$rf")" 2>/dev/null && pwd -P)"
  case "$d" in */.supervisor/automate) printf '%s/%s' "${d%/.supervisor/automate}" "${it#./}" ;; *) printf '%s/%s' "$PWD" "${it#./}" ;; esac
}

_lanes_vg_after_pick() { # <runfile> <item> — the ## Progress lines after the LAST `picked <item>`; exit 1 when none
  VG_ITEM="${2#./}" awk '
    BEGIN { it = ENVIRON["VG_ITEM"] }
    /^## / { inp = ($0 ~ /^## Progress/); next }
    !inp { next }
    { n++; line[n] = $0; l = $0; sub(/^- /, "", l)
      if (l ~ /^([^ ]+ )?picked /) {
        x = l; sub(/^([^ ]+ )?picked /, "", x); split(x, a, " "); x = a[1]
        sub(/[;,]+$/, "", x); sub(/^\.\//, "", x)
        if (x == it) last = n
      } }
    END { if (!last) exit 1; for (i = last + 1; i <= n; i++) print line[i] }' "$1" 2>/dev/null
}

_lanes_vg_last_pick() { # <runfile> — the item of the LAST `picked` line in ## Progress (`./` stripped); exit 1 when none
  awk '
    /^## / { inp = ($0 ~ /^## Progress/); next }
    !inp { next }
    { l = $0; sub(/^- /, "", l)
      if (l ~ /^([^ ]+ )?picked /) {
        x = l; sub(/^([^ ]+ )?picked /, "", x); split(x, a, " "); x = a[1]
        sub(/[;,]+$/, "", x); sub(/^\.\//, "", x); last = x; f = 1
      } }
    END { if (!f || last == "") exit 1; print last }' "$1" 2>/dev/null
}

_lanes_vg_has() { # <lines> <prefix> [exact] — 0 when a `- [<one token> ]<prefix>…` line is there (exact: the whole rest)
  VG_P="$2" VG_X="${3:-}" awk '
    BEGIN { p = ENVIRON["VG_P"]; x = ENVIRON["VG_X"] }
    function hit(s) { return x == "exact" ? (s == p) : (index(s, p) == 1) }
    { l = $0; if (sub(/^- /, "", l) == 0) next
      if (hit(l)) { f = 1; exit }
      sub(/^[^ ]+ /, "", l); if (hit(l)) { f = 1; exit } }
    END { exit !f }' <<<"$1"
}

lanes_validation_gate() {
  local G="validation-gate:" rf="" item="" pr="" wn="" words="" waive=0 hw=0 pos=0
  local usage="usage: validation-gate <runfile> <item> <pr_url> [--waive <n> --words <text>]"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --waive) waive=1; [ "$#" -ge 2 ] || { echo "$G refused — --waive needs a value"; return 1; }; wn="$2"; shift 2 ;;
      --words) hw=1; [ "$#" -ge 2 ] || { echo "$G refused — --words needs a value"; return 1; }; words="$2"; shift 2 ;;
      *) pos=$((pos + 1))
         case "$pos" in 1) rf="$1" ;; 2) item="$1" ;; 3) pr="$1" ;; *) echo "$G unrun — unexpected argument '$1'; $usage"; return 0 ;; esac
         shift ;;
    esac
  done
  if [ "$hw" = 1 ] && [ "$waive" = 0 ]; then echo "$G refused — --words needs --waive <n>"; return 1; fi
  local itemf tab rows n title kind st ev
  tab="$(printf '\t')"
  if [ "$waive" = 1 ]; then
    [ -n "$rf" ] && [ -n "$item" ] || { echo "$G refused — $usage"; return 1; }
    [ "$hw" = 1 ] && [ -n "$words" ] || { echo "$G refused — --waive needs non-empty --words (the owner's own words)"; return 1; }
    case "$words" in *"|"*|*"
"*) echo "$G refused — the owner's words contain '|' or a newline"; return 1 ;; esac
    case "$wn" in ''|*[!0-9]*) echo "$G refused — --waive '$wn' is not an entry number"; return 1 ;; esac
    itemf="$(_lanes_vg_itemf "$rf" "$item")"
    [ -f "$itemf" ] && [ -r "$itemf" ] || { echo "$G refused — item file unreadable: $item"; return 1; }
    title="$(_lanes_validation_rows "$itemf" /dev/null 0 | awk -F'\t' -v n="$wn" '$1 == n && $3 == "running-system" { print $2; exit }')"
    [ -n "$title" ] || { echo "$G refused — V$wn is not a running-system Validation entry of $item"; return 1; }
    local after lastp
    if ! after="$(_lanes_vg_after_pick "$rf" "$item")"; then echo "$G refused — no \`picked $item\` line in $rf (a waiver would never count)"; return 1; fi
    lastp="$(_lanes_vg_last_pick "$rf")" || lastp=""
    if [ "$lastp" != "${item#./}" ]; then echo "$G refused — $item is not the run's current item (last picked: ${lastp:-none})"; return 1; fi
    if _lanes_vg_has "$after" "validation waived: ${item#./} V$wn $title — owner: \"$words\"" exact; then
      echo "$G waiver already recorded — V$wn $title"; return 0
    fi
    bash "$HELPERS" progress-append "$rf" "$(now_utc) validation waived: ${item#./} V$wn $title — owner: \"$words\"" >/dev/null 2>&1 \
      || { echo "$G refused — progress-append failed on $rf"; return 1; }
    echo "$G waiver recorded — V$wn $title"
    return 0
  fi
  [ -n "$rf" ] && [ -n "$item" ] || { echo "$G unrun — $usage"; return 0; }
  itemf="$(_lanes_vg_itemf "$rf" "$item")"
  if [ ! -f "$itemf" ] || [ ! -r "$itemf" ]; then echo "$G unrun — item file unreadable: $item"; return 0; fi
  rows="$(_lanes_validation_rows "$itemf" /dev/null 0)"
  # Fail CLOSED: a section the reader cannot parse is unrun (step-less, nothing to waive), never `none`.
  ev="$(awk -F'\t' '$3 == "unparsed" { print $5; exit }' <<<"$rows")"
  if [ -n "$ev" ]; then echo "$G unrun — $item: $ev"; return 0; fi
  if ! awk -F'\t' '$3 == "running-system" { f = 1 } END { exit !f }' <<<"$rows"; then
    echo "$G none — no running-system step in $item"; return 0
  fi
  local tmp view gh_ok=0 k=0 waived="" after=""
  tmp="$(mktemp -d 2>/dev/null)" || { echo "$G unrun — no temp dir"; return 0; }
  : > "$tmp/body"
  if [ -n "$pr" ] && view="$("$LANES_GH" pr view "$pr" --json body 2>/dev/null)" && jq -e 'type == "object" and (.body | type == "string")' >/dev/null 2>&1 <<<"$view"; then
    gh_ok=1; jq -r '.body' <<<"$view" > "$tmp/body"
  fi
  rows="$(_lanes_validation_rows "$itemf" "$tmp/body" "$gh_ok" "$pr")"
  after="$(_lanes_vg_after_pick "$rf" "$item")" || after=""
  rm -rf "$tmp"
  while IFS="$tab" read -r n title kind st ev; do
    [ "$kind" = running-system ] || continue
    k=$((k + 1))
    [ "$st" = PASS ] && continue
    if [ -n "$after" ] && _lanes_vg_has "$after" "validation waived: ${item#./} V$n $title — owner: \""; then
      waived="$waived${waived:+; }V$n $title"; continue
    fi
    echo "$G unrun — V$n $title: $ev"; return 0
  done <<EOF
$rows
EOF
  # Fail CLOSED: the pre-check saw a running-system step, so zero rows here is a reader failure, never `ok`.
  if [ "$k" = 0 ]; then echo "$G unrun — the Validation reader returned no running-system row for $item"; return 0; fi
  if [ -n "$waived" ]; then echo "$G waived — $waived"; return 0; fi
  echo "$G ok — $k running-system step(s) evidenced"
  return 0
}

