#!/usr/bin/env bash
# test-loop-inventory.sh — keeps the four loop-inventory tables (loomwright/docs/loop-inventory/*.md)
# honest against the loop prose they list (automate-speed/04).
#
# GROUPS (the group -> source-file map lives HERE, once; each inventory's `## Sources` must equal it):
#   automate-loop          skills/automate-loop/*.md (a glob, so a new split file needs rows) + commands/automate.md
#   supervisor             agents/supervisor.md, commands/supervisor.md, skills/self-heal-advisory/SKILL.md,
#                          skills/self-heal-advisory/{on-entry,escalation,multi-voter,completion-tail}.md,
#                          skills/async-orchestration/SKILL.md, skills/async-orchestration/finalize.md
#   review-heal            skills/review-heal/SKILL.md, skills/review-heal/fallback-review.md,
#                          skills/review-heal/escalation.md, skills/review-heal/dispatch.md,
#                          commands/review-pr.md, agents/review-pr.md
#   launch-pad-autonomous  agents/launch-pad.md, commands/launch-pad.md, skills/autonomous-loop/SKILL.md,
#                          skills/autonomous-loop/multi-iteration.md, commands/autonomous.md
#
# CHECKED (every FAIL line names the row id, or the group/file and heading):
#   * SHAPE — the file's `## ` sections are exactly Sources, Inventory, Gap list (ordered by risk), Counts,
#     in that order (so it ENDS with the gap list and the counts); the table header is the contract's nine
#     columns; every row has nine cells (`\|` is a literal pipe, unescaped before matching); id is
#     <prefix>-NNN (three or more digits) with the group's prefix (AL/SV/RH/LP); kind is one of
#     deterministic/judgment/rule/story; home is prose, script:<file>[ <sub>], hook:<leaf>, step-scoped,
#     global or rationale:<doc>#<anchor>; implemented by is `-` or script:<file>[ <sub>]; the anchor is
#     `h: #…` or `q: <text of 12 or more characters>`; the file cell is one of the group's sources.
#   * HEADING COVERAGE (AC2) — every `###`/`####` heading line of every source, outside fenced code blocks
#     and outside `<!-- split:begin … -->`/`<!-- split:end … -->` index blocks, is the `h:` anchor of at
#     least one row whose file cell names that file (fence reading: see DELIBERATE CHOICES). A fence
#     (or split block) still open at end of file fails too: it would hide every heading after it.
#   * LIVE ANCHORS (AC4) — a row whose home is `prose` or `global`: an `h:` anchor must equal a line of its
#     file, a `q:` anchor must be a substring of one line of it; else `FAIL <id>: anchor not found in <file>`.
#     A row whose home is `step-scoped`, `hook:…` or `script:…` is not anchor-checked.
#   * RATIONALE HOMES — a `rationale:<doc>#<anchor>` home: <doc>, relative to the plugin root, must be
#     readable (else `FAIL <id>: rationale doc not found: <doc>`), and one of its `#`/`##`/`###` heading
#     lines must slug to <anchor> (slug = lowercase; spaces -> `-`; characters other than [a-z0-9-]
#     dropped), else `FAIL <id>: rationale anchor not found: <anchor>`. The row's own anchor is not checked.
#   * SCRIPT SUBCOMMANDS (AC5) — a `script:<file> <sub>` cell (home or implemented by) passes iff <file>
#     exists under loomwright/scripts/ and has a line that is a shell `case` arm whose `|`-separated labels
#     (quotes stripped) include <sub>, followed by `)`. `script:<file>` alone only needs the file.
#   * UNIQUE IDS (AC6) — within one file and across the four.
#   * GAP LIST + COUNTS (AC7) — the gap list names every GAP row exactly once and nothing else; all six
#     `## Counts` lines (rows, the four kinds, GAP) exist once each and equal the table. One informational
#     `GAP <group>: <n>` line per group is printed and is never a failure on its own.
#   * TEST CELLS (AC7b) — a non-GAP test cell names a test-*.sh existing under loomwright/scripts/ or the
#     repo's scripts/.
#   * FIXTURE LEGS (AC8, default mode only) on mktemp -d scratch copies: each mutant is checked non-empty
#     and different from its original before its leg is trusted; red legs assert a non-zero exit AND the
#     line naming the culprit; green legs assert exit 0 (fence- and split-block exemption, step-scoped home,
#     a rationale: home resolving in a scratch rationale doc).
#     Beyond the AC8 set, the fence-union reading and every remaining FAIL branch (row shape, header,
#     sections, Sources, count/gap-line shape, unclosed split block) get one red leg each.
#
# NOT CHECKED: that a list item stating a branch or rule has its own row (AC3 — reviewer's judgment; the
# test checks headings only); that a q: anchor is unique in its file or says what the row claims; that
# the gap list is ordered by risk; that ids are gap-free (ids are never reused, so holes are legal); that
# a script's case arm is the dispatcher's (any case arm in the named file counts); that a rationale doc's
# matching heading sits outside a fenced block (every `#`/`##`/`###` line of the doc counts).
#
# DELIBERATE CHOICES:
#   * Heading lines and h: anchors are compared with trailing whitespace stripped (two headings in
#     skills/async-orchestration/SKILL.md end in a space; the inventory's anchors are trimmed).
#   * Fences are read TWO ways and a line is exempt only when BOTH put it inside a fenced block. Reading 1
#     is CommonMark at top level, as test-automate-loop-split.sh's extractor does: a fence opens on 0-3
#     spaces + 3 or more backticks or tildes and closes only on a BARE fence of the same character at
#     least as long. Reading 2 is a naive toggle: every fence line, at ANY indentation, flips the state.
#     The toggle is indentation-blind on purpose: a list-item fence that opens at 3 spaces and closes at
#     4+ (valid CommonMark inside a list item; the sources carry 4-6-space fences) leaves Reading 1 open,
#     and an indentation-bound toggle would stay open with it, exempting every later heading; the blind
#     toggle pairs the two lines, so the headings after the block are checked (a red fixture leg pins
#     this). Limit, stated plainly: the union is not "fails toward checking more" in every case — a stray
#     unpaired fence line can desync both readings at once and exempt headings until the next fence line;
#     only when both readings are still open at end of file does the never-closes check catch it.
#     The readings disagree in agents/launch-pad.md's Phase 4 (DECOMPOSE) output template, where a ```yaml
#     block is nested inside a ```markdown one: CommonMark closes the OUTER block at the inner bare ```, so
#     the template's tail headings become live text, and every later bare ``` then flips CommonMark's
#     reading against the author's until the Phase 5.5 template's ```markdown opener lines the two up
#     again. The toggle reading pairs the fences the way the author meant. Picked on purpose: CommonMark
#     alone would leave the headings in that out-of-step stretch (the Phase 5 / Phase 5.5 step headings)
#     unchecked, the toggle alone would skip the template headings CommonMark renders; the union checks
#     both, and the real tree is green under it. A block that never closes under BOTH readings fails.
#   * Coverage asks only for ###/#### headings; rows anchored on `##` headings or table rows are fine.
#   * This file names no vendor-coupling token (scripts/check-vendor-coupling.sh counts this directory).
#
# usage: test-loop-inventory.sh               the checker on this repo's loomwright/, then the fixture legs
#        test-loop-inventory.sh --root <dir>  the checker only, on <dir> as the plugin root (tests are
#                                             looked up in <dir>/scripts and <dir>/../scripts)
# Static: bash 3.2 + BSD userland, awk/cp/cmp/mktemp only; no network, no gh, no git. Exit 0 = pass, 1 = fail.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$PLUGIN/.." && pwd)"

# group <TAB> id prefix <TAB> inventory file (relative to the plugin root)
GROUPS_TSV='automate-loop	AL	docs/loop-inventory/automate-loop.md
supervisor	SV	docs/loop-inventory/supervisor.md
review-heal	RH	docs/loop-inventory/review-heal.md
launch-pad-autonomous	LP	docs/loop-inventory/launch-pad-autonomous.md'

# group_sources <root> <group> — the group's source files, one per line, relative to <root>.
group_sources() {
  (
    shopt -s nullglob
    cd "$1" 2>/dev/null || exit 0
    case "$2" in
      automate-loop)
        for f in skills/automate-loop/*.md; do printf '%s\n' "$f"; done
        printf '%s\n' commands/automate.md ;;
      supervisor)
        printf '%s\n' agents/supervisor.md commands/supervisor.md skills/self-heal-advisory/SKILL.md \
          skills/self-heal-advisory/on-entry.md skills/self-heal-advisory/escalation.md \
          skills/self-heal-advisory/multi-voter.md skills/self-heal-advisory/completion-tail.md \
          skills/async-orchestration/SKILL.md skills/async-orchestration/finalize.md ;;
      review-heal)
        printf '%s\n' skills/review-heal/SKILL.md skills/review-heal/fallback-review.md \
          skills/review-heal/escalation.md skills/review-heal/dispatch.md commands/review-pr.md agents/review-pr.md ;;
      launch-pad-autonomous)
        printf '%s\n' agents/launch-pad.md commands/launch-pad.md skills/autonomous-loop/SKILL.md \
          skills/autonomous-loop/multi-iteration.md commands/autonomous.md ;;
    esac
  )
}

# Shared awk helpers: a cell's literal `\|` is protected as \001 before splitting on `|`, then restored.
# Plain index()/substr() loops, no regex escapes, so BSD awk, gawk and mawk read them the same way.
AWK_PIPES='
function protect(t,   o, p) { o = ""; while ((p = index(t, "\\|")) > 0) { o = o substr(t, 1, p - 1) "\001"; t = substr(t, p + 2) } return o t }
function restore(t, r,   o, p) { o = ""; while ((p = index(t, "\001")) > 0) { o = o substr(t, 1, p - 1) r; t = substr(t, p + 1) } return o t }
'

# check_root <plugin root> — prints FAIL lines, the GAP lines and a verdict; exit 0 clean, 1 not.
check_root() {
  local root="$1" g p inv
  [ -d "$root" ] || { echo "FAIL --root is not a directory: $root"; return 1; }
  {
    printf '%s\n' "$GROUPS_TSV" | while IFS='	' read -r g p inv; do
      printf 'G\t%s\t%s\t%s\n' "$g" "$p" "$inv"
      group_sources "$root" "$g" | while IFS= read -r s; do printf 'S\t%s\t%s\n' "$g" "$s"; done
    done
  } | awk -F'\t' -v root="$root" "$AWK_PIPES"'
    function rstrip(s) { sub(/[ \t\r]+$/, "", s); return s }
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function bad(m) { print "FAIL " m; nbad++ }
    function readable(p,   l, r) { r = (getline l < p); close(p); return (r >= 0) }
    function load(rel,   p, l, n, r, big) {
      p = root "/" rel; n = 0; big = "\n"
      while ((r = (getline l < p)) > 0) { n++; SRC[rel, n] = l; big = big l "\n"; HL[rel, rstrip(l)] = 1 }
      close(p)
      if (r < 0 && n == 0) return 0
      NL[rel] = n; BIG[rel] = big; return 1
    }
    function unquote(k) {
      if (substr(k, 1, 1) == "\"" || substr(k, 1, 1) == "\047") k = substr(k, 2)
      if (substr(k, length(k)) == "\"" || substr(k, length(k)) == "\047") k = substr(k, 1, length(k) - 1)
      return k
    }
    function arms(f,   p, l, s, i, n, lab) {
      if (f in ARMDONE) return
      ARMDONE[f] = 1; p = root "/scripts/" f
      while ((getline l < p) > 0) {
        if (l !~ /^[ \t]*\(?[ \t]*[^ \t()|]+([ \t]*\|[ \t]*[^ \t()|]+)*[ \t]*\)/) continue
        s = l; sub(/^[ \t]*\(?/, "", s); s = substr(s, 1, index(s, ")") - 1)
        n = split(s, lab, "|")
        for (i = 1; i <= n; i++) ARM[f, unquote(trim(lab[i]))] = 1
      }
      close(p)
    }
    function check_script(id, cell, what,   rest, sp, f, sc) {
      rest = substr(cell, 8); sp = index(rest, " ")
      if (sp) { f = substr(rest, 1, sp - 1); sc = trim(substr(rest, sp + 1)) } else { f = rest; sc = "" }
      if (f == "" || f ~ /\.\./ || f ~ /^\//) { bad(id ": " what " names an invalid script path: " cell); return }
      if (!readable(root "/scripts/" f)) { bad(id ": " what " names a script missing from scripts/: " f); return }
      if (sc == "") return
      if (sc ~ /[ \t]/) { bad(id ": " what " names more than one subcommand: " cell); return }
      arms(f)
      if (!((f, sc) in ARM)) bad(id ": " what " " f " has no case arm for \047" sc "\047")
    }
    # slug: lowercase; spaces -> "-"; every character other than [a-z0-9-] dropped.
    function slug(s) { s = tolower(s); gsub(/ /, "-", s); gsub(/[^a-z0-9-]/, "", s); return s }
    # check_rationale: a rationale:<doc>#<anchor> home needs <doc> (relative to the plugin root) readable and
    # one of its #/##/### heading lines whose text slugs to <anchor>.
    function check_rationale(id, cell,   rest, rdoc, ranc, p, l, hl, found) {
      rest = substr(cell, 11); rdoc = substr(rest, 1, index(rest, "#") - 1); ranc = substr(rest, index(rest, "#") + 1)
      if (!readable(root "/" rdoc)) { bad(id ": rationale doc not found: " rdoc); return }
      p = root "/" rdoc; found = 0
      while ((getline l < p) > 0) {
        if (l !~ /^(#|##|###)[ \t]/) continue
        hl = rstrip(l); sub(/^#+[ \t]+/, "", hl)
        if (slug(hl) == ranc) found = 1
      }
      close(p)
      if (!found) bad(id ": rationale anchor not found: " ranc)
    }
    $1 == "G" { ng++; GN[ng] = $2; GP[$2] = $3; GINV[$2] = $4; next }
    $1 == "S" { EXP[$2, $3] = 1; NE[$2]++; ES[$2, NE[$2]] = $3; next }
    END {
      header = "| id | file | anchor | condition | action | kind | home | implemented by | test |"
      split("rows deterministic judgment rule story GAP", CK, " ")
      split("Sources|Inventory|Gap list (ordered by risk)|Counts", WANTSEC, "|")
      for (gi = 1; gi <= ng; gi++) {
        g = GN[gi]; p = root "/" GINV[g]; sec = ""; nsec = 0; nd = 0; ln = 0; sawhdr = 0; gl = 0
        while ((r = (getline l < p)) > 0) {
          ln++
          if (l ~ /^## /) { sec = rstrip(substr(l, 4)); nsec++; SEC[nsec] = sec; continue }
          if (sec == "Sources") {
            if (l ~ /^- `[^`]+`/) { s = substr(l, 4); s = substr(s, 1, index(s, "`") - 1); nd++; DECL[g, s] = 1; DS[g, nd] = s }
            continue
          }
          if (sec == "Inventory") {
            if (l !~ /^\|/) continue
            t = protect(rstrip(l))
            if (!sawhdr) {
              sawhdr = 1; h = t; gsub(/[ \t]+/, " ", h)
              if (h != header) bad(g ": the ## Inventory table header is not the contract header: " l)
              continue
            }
            if (t ~ /^\|[-: |]+\|$/) continue
            n = split(t, c, "|"); NR_G[g]++; label = g " row #" NR_G[g]
            if (n != 11 || trim(c[1]) != "" || trim(c[11]) != "") { bad(label ": malformed row (" n - 2 " cells, want 9): " substr(l, 1, 80)); continue }
            for (i = 2; i <= 10; i++) { cell[i - 1] = restore(trim(c[i]), "|") }
            nrow++; RG[nrow] = g; RID[nrow] = cell[1]; RFILE[nrow] = cell[2]; RANCH[nrow] = cell[3]
            RKIND[nrow] = cell[6]; RHOME[nrow] = cell[7]; RIMPL[nrow] = cell[8]; RTEST[nrow] = cell[9]; RLAB[nrow] = label
            continue
          }
          if (sec == "Gap list (ordered by risk)") {
            if (trim(l) == "") continue
            if (l !~ /^[0-9]+\. [A-Z][A-Z]-[0-9][0-9][0-9]+ — [^ ]/) { bad(g ": malformed ## Gap list line (want `N. <id> — <reason>`): " l); continue }
            s = l; sub(/^[0-9]+\. /, "", s); s = substr(s, 1, index(s, " ") - 1)
            if ((g, s) in GL) bad(s ": listed twice in the " g " ## Gap list")
            GL[g, s] = 1; gl++; GLID[g, gl] = s
            continue
          }
          if (sec == "Counts") {
            if (trim(l) == "") continue
            if (l !~ /^- (rows|deterministic|judgment|rule|story|GAP): [0-9]+$/) { bad(g ": malformed ## Counts line: " l); continue }
            s = substr(l, 3); k = substr(s, 1, index(s, ":") - 1); v = substr(s, index(s, ":") + 2) + 0
            if ((g, k) in CNT) bad(g ": ## Counts has two \047- " k ":\047 lines")
            CNT[g, k] = v
            continue
          }
        }
        close(p); NGL[g] = gl
        if (r < 0 && ln == 0) { bad(g ": inventory file missing or unreadable: " GINV[g]); MISSING[g] = 1; continue }
        order = ""; for (i = 1; i <= nsec; i++) order = order (i > 1 ? " / " : "") SEC[i]
        okorder = (nsec == 4); for (i = 1; i <= 4 && okorder; i++) if (SEC[i] != WANTSEC[i]) okorder = 0
        if (!okorder) bad(g ": ## sections must be exactly Sources / Inventory / Gap list (ordered by risk) / Counts, found: " order)
        if (!sawhdr) bad(g ": no ## Inventory table")
        for (i = 1; i <= nd; i++) if (!((g, DS[g, i]) in EXP)) bad(g ": ## Sources lists " DS[g, i] ", which is not a source of the group")
        for (i = 1; i <= NE[g]; i++) {
          s = ES[g, i]
          if (!((g, s) in DECL)) bad(g ": ## Sources is missing " s)
          if (!load(s)) { bad(g ": source file missing or unreadable: " s); continue }
          LOADED[s] = 1
        }
      }
      # rows
      for (k = 1; k <= nrow; k++) {
        g = RG[k]; id = RID[k]
        if (id !~ /^[A-Z][A-Z]-[0-9][0-9][0-9]+$/) { bad(RLAB[k] ": malformed id \047" id "\047 (want " GP[g] "-NNN)"); id = RLAB[k] }
        else {
          if (substr(id, 1, 2) != GP[g]) bad(id ": id prefix is not the " g " group\047s " GP[g])
          if (id in IDG) bad(id ": duplicate id (" IDG[id] " and " g ")")
          else IDG[id] = g
        }
        f = RFILE[k]; a = RANCH[k]; fileok = ((g, f) in EXP) && (f in LOADED)
        if (!((g, f) in EXP)) bad(id ": file \047" f "\047 is not a source of the " g " group")
        atype = ""
        if (a ~ /^h: #/) { atype = "h"; av = rstrip(substr(a, 4)) }
        else if (a ~ /^q: /) { atype = "q"; av = substr(a, 4); if (length(av) < 12) bad(id ": q: anchor shorter than 12 characters: " a) }
        else bad(id ": anchor must start with \047h: #\047 or \047q: \047: " a)
        if (atype == "h" && fileok) COV[f, av] = 1
        kd = RKIND[k]
        if (kd != "deterministic" && kd != "judgment" && kd != "rule" && kd != "story") bad(id ": unknown kind \047" kd "\047")
        else KC[g, kd]++
        hm = RHOME[k]
        if (hm == "prose" || hm == "global") {
          if (fileok && atype == "h" && !((f, av) in HL)) bad(id ": anchor not found in " f)
          if (fileok && atype == "q" && index(BIG[f], av) == 0) bad(id ": anchor not found in " f)
        }
        else if (hm ~ /^script:./) check_script(id, hm, "home")
        else if (hm ~ /^rationale:[^#]+#./) check_rationale(id, hm)
        else if (hm ~ /^hook:./ || hm == "step-scoped") { }
        else bad(id ": unknown home \047" hm "\047")
        im = RIMPL[k]
        if (im ~ /^script:./) check_script(id, im, "implemented by")
        else if (im != "-") bad(id ": implemented by must be \047-\047 or script:<file>[ <sub>], got \047" im "\047")
        ts = RTEST[k]; ROWS[g]++
        if (ts == "GAP") { GAPN[g]++; GAPROW[g, id] = 1; GAPID[g, GAPN[g]] = id }
        else if (ts !~ /^test-[A-Za-z0-9._-]+\.sh$/ || !(readable(root "/scripts/" ts) || readable(root "/../scripts/" ts)))
          bad(id ": test cell names no existing test-*.sh under loomwright/scripts/ or scripts/: " ts)
      }
      # heading coverage
      for (gi = 1; gi <= ng; gi++) {
        g = GN[gi]
        for (i = 1; i <= NE[g]; i++) {
          s = ES[g, i]; if (!(s in LOADED) || (s in COVDONE)) continue
          COVDONE[s] = 1; fence = ""; tog = 0; split_ = 0
          for (j = 1; j <= NL[s]; j++) {
            l = SRC[s, j]
            # toggle reading: a fence line at ANY indentation flips it (list-item fences sit at 4+ spaces)
            if (l ~ /^ *(```|~~~)/) {
              tog = !tog
              if (!match(l, /^( |  |   )?(```+|~~~+)/)) continue
              m = substr(l, RSTART, RLENGTH); sub(/^ +/, "", m)
              if (fence == "") { fence = m; continue }
              rest = l; sub(/^ +/, "", rest)
              if (substr(m, 1, 1) == substr(fence, 1, 1) && length(m) >= length(fence) && rest ~ /^[`~]+[ \t]*$/) fence = ""
              continue
            }
            # exempt only when BOTH readings (CommonMark, naive toggle) put the line inside a fence
            if (fence != "" && tog) continue
            if (l ~ /^<!-- split:begin[ \t]/) { split_ = 1; continue }
            if (l ~ /^<!-- split:end[ \t]/) { split_ = 0; continue }
            if (split_) continue
            if (l ~ /^####?([ \t]|$)/ && !((s, rstrip(l)) in COV)) bad(s ": heading has no h: row: " rstrip(l))
          }
          if (fence != "" && tog) bad(s ": a fenced block never closes, so headings after it were not checked")
          if (split_) bad(s ": a split:begin block never closes, so headings after it were not checked")
        }
      }
      # gap lists + counts
      for (gi = 1; gi <= ng; gi++) {
        g = GN[gi]; if (g in MISSING) continue
        for (i = 1; i <= GAPN[g]; i++) if (!((g, GAPID[g, i]) in GL)) bad(GAPID[g, i] ": GAP row missing from the " g " ## Gap list")
        for (i = 1; i <= NGL[g]; i++) if (!((g, GLID[g, i]) in GAPROW)) bad(GLID[g, i] ": in the " g " ## Gap list but not a GAP row of its table")
        want["rows"] = ROWS[g] + 0; want["GAP"] = GAPN[g] + 0
        want["deterministic"] = KC[g, "deterministic"] + 0; want["judgment"] = KC[g, "judgment"] + 0
        want["rule"] = KC[g, "rule"] + 0; want["story"] = KC[g, "story"] + 0
        for (i = 1; i <= 6; i++) {
          k = CK[i]
          if (!((g, k) in CNT)) bad(g ": ## Counts has no \047- " k ":\047 line (the table has " want[k] ")")
          else if (CNT[g, k] != want[k]) bad(g ": ## Counts says \047- " k ": " CNT[g, k] "\047 but the table has " want[k])
        }
      }
      for (gi = 1; gi <= ng; gi++) { g = GN[gi]; print "GAP " g ": " (GAPN[g] + 0); total += ROWS[g] }
      if (nbad) { print "loop-inventory: FAIL — " nbad " problem(s)"; exit 1 }
      print "loop-inventory: OK — " total " rows across " ng " groups"
    }'
}

if [ "$#" -gt 0 ]; then
  case "$1" in
    --root)
      [ "$#" -eq 2 ] || { echo "usage: test-loop-inventory.sh [--root <dir>]" >&2; exit 2; }
      check_root "$2"; exit $? ;;
    -h|--help) sed -n '2,/^# Static:/p' "$SELF"; exit 0 ;;
    *) echo "usage: test-loop-inventory.sh [--root <dir>]" >&2; exit 2 ;;
  esac
fi

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

echo "== the real tree ($PLUGIN)"
real_out="$(check_root "$PLUGIN")"; real_rc=$?
printf '%s\n' "$real_out"
if [ "$real_rc" -eq 0 ]; then ok "real tree: every check green"; else no "real tree: the checker is red (FAIL lines above)"; fi
ngap="$(awk '/^GAP [a-z-]+: [0-9]+$/ {n++} END {print n + 0}' <<<"$real_out")"
if [ "$ngap" -eq 4 ]; then ok "AC7: one informational GAP line per group (4)"; else no "AC7: want 4 GAP lines, got $ngap"; fi

# ---------------------------------------------------------------- fixture legs (AC8)
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT
BASE="$TMP/base"
mkdir -p "$BASE/loomwright/docs" "$BASE/loomwright/scripts" "$BASE/loomwright/skills" "$BASE/scripts"
cp -R "$PLUGIN/docs/loop-inventory" "$BASE/loomwright/docs/" && cp -R "$PLUGIN/agents" "$PLUGIN/commands" "$BASE/loomwright/" \
  || { no "fixture: could not copy the inventory and prose into $BASE"; echo "RESULT: $pass/$((pass+fail)) passed"; exit 1; }
# rationale: homes name docs under docs/rationale, so the base mirrors it whenever the real tree has it.
if [ -d "$PLUGIN/docs/rationale" ]; then
  cp -R "$PLUGIN/docs/rationale" "$BASE/loomwright/docs/" \
    || { no "fixture: could not copy docs/rationale into $BASE"; echo "RESULT: $pass/$((pass+fail)) passed"; exit 1; }
fi
for d in automate-loop self-heal-advisory async-orchestration review-heal autonomous-loop; do cp -R "$PLUGIN/skills/$d" "$BASE/loomwright/skills/"; done
# Scripts: real bodies (the case-arm check reads them); test files as empty stand-ins (only existence is checked).
for f in "$PLUGIN"/scripts/*; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in test-*.sh) : > "$BASE/loomwright/scripts/$(basename "$f")" ;; *) cp "$f" "$BASE/loomwright/scripts/" ;; esac
done
for f in "$REPO"/scripts/test-*.sh; do [ -f "$f" ] && : > "$BASE/scripts/$(basename "$f")"; done

INV="loomwright/docs/loop-inventory"
PIL="loomwright/skills/automate-loop/per-item-loop.md"

# new_leg <name> [scripts] — a fresh copy of the base tree's prose and inventory; prints its path. The two
# scripts directories are symlinks to the base's (no leg writes through them) unless `scripts` asks for a copy.
new_leg() {
  local d="$TMP/$1"
  mkdir -p "$d/loomwright" && cp -R "$BASE/loomwright/docs" "$BASE/loomwright/skills" "$BASE/loomwright/agents" \
    "$BASE/loomwright/commands" "$d/loomwright/" || return 1
  if [ "${2:-}" = scripts ]; then cp -R "$BASE/loomwright/scripts" "$d/loomwright/" && cp -R "$BASE/scripts" "$d/" || return 1
  else ln -s "$BASE/loomwright/scripts" "$d/loomwright/scripts" && ln -s "$BASE/scripts" "$d/scripts" || return 1; fi
  printf '%s\n' "$d"
}
# mutant_ok <orig> <mutant> — the mutant is non-empty and differs from its original.
mutant_ok() { [ -s "$2" ] && ! cmp -s "$1" "$2"; }
# apply <file> <awk program> [awk -v args…] — rewrite <file> through awk; fails (and leaves it) unless the
# result is a valid mutant.
apply() {
  local f="$1" prog="$2"; shift 2
  awk "$@" "$prog" "$f" > "$f.mut" || return 1
  mutant_ok "$f" "$f.mut" || { rm -f "$f.mut"; return 1; }
  mv "$f.mut" "$f"
}
# set_cell <inventory> <id> <column 1..9> <value> — rewrite one cell of the row with that id.
SET_CELL="$AWK_PIPES"'{ t = protect($0); n = split(t, c, "|")
  if (!done && n == 11 && c[2] == " " id " ") { c[col + 1] = " " val " "; t = c[1]; for (i = 2; i <= n; i++) t = t "|" c[i]; done = 1 }
  print restore(t, "\\|") }'
set_cell() { apply "$1" "$SET_CELL" -v id="$2" -v col="$3" -v val="$4"; }
# run_leg <dir> — the checker on a scratch tree; sets out/rc.
run_leg() { out="$(bash "$SELF" --root "$1/loomwright" 2>&1)"; rc=$?; }
# expect_red <what> <needle> — non-zero exit AND a line containing <needle>.
expect_red() {
  local line
  line="$(awk -v n="$2" 'index($0, n) && !f {print; f = 1}' <<<"$out")"
  if [ "$rc" -ne 0 ] && [ -n "$line" ]; then ok "$1 red — $line"; else no "$1: want a non-zero exit and a line with '$2' (rc=$rc)"; sed -n '1,6p' <<<"$out"; fi
}
expect_green() {
  if [ "$rc" -eq 0 ]; then ok "$1 green"; else no "$1: want exit 0 (rc=$rc)"; sed -n '1,6p' <<<"$out"; fi
}
# row_field <inventory> <awk condition over cells c[2..10]> <column 1..9> — the first matching row's cell.
row_field() {
  awk -v col="$3" "$AWK_PIPES"'/^\| [A-Z][A-Z]-[0-9]/ { t = protect($0); n = split(t, c, "|")
    for (i = 2; i <= 10; i++) { sub(/^ +/, "", c[i]); sub(/ +$/, "", c[i]) }
    if (n == 11 && ('"$2"')) { print c[col + 1]; exit } }' "$1"
}

echo "== fixture legs (scratch copies under $TMP)"
run_leg "$BASE"; expect_green "unmutated scratch copy"

# AC2 — a new ### heading with no row.
NEWH="### Fixture heading with no inventory row"
d="$(new_leg ac2)"
if apply "$d/$PIL" '{print} END {print ""; print h}' -v h="$NEWH"; then run_leg "$d"; expect_red "AC2 (new heading)" "skills/automate-loop/per-item-loop.md: heading has no h: row: $NEWH"
else no "AC2: mutant invalid"; fi

# AC2 exemptions — the same heading inside a fenced block, and inside a split-index block, needs no row.
d="$(new_leg fence)"
if apply "$d/$PIL" '{print} END {print ""; print "```text"; print h; print "```"}' -v h="$NEWH"; then run_leg "$d"; expect_green "exemption: heading inside a fenced block"
else no "fence exemption: mutant invalid"; fi
d="$(new_leg splitblock)"
if apply "$d/loomwright/skills/automate-loop/SKILL.md" '{print} END {print ""; print "<!-- split:begin per-item-loop.md -->"; print h; print "See [per-item-loop.md](per-item-loop.md)."; print "<!-- split:end per-item-loop.md -->"}' -v h="$NEWH"; then
  run_leg "$d"; expect_green "exemption: heading inside a split-index block"
else no "split-block exemption: mutant invalid"; fi

# Fence reading (header: DELIBERATE CHOICES) — a heading only ONE reading puts outside a fence still needs a
# row, in both directions; a block that never closes under either reading fails.
d="$(new_leg nest-cm)"
if apply "$d/$PIL" '{print} END {print ""; print "```markdown"; print "```yaml"; print "```"; print h; print "```"}' -v h="$NEWH"; then
  run_leg "$d"; expect_red "fence union (live under CommonMark only)" "per-item-loop.md: heading has no h: row: $NEWH"
else no "fence union (CommonMark): mutant invalid"; fi
d="$(new_leg nest-tog)"
if apply "$d/$PIL" '{print} END {print ""; print "````markdown"; print "```yaml"; print h; print "```"; print "````"}' -v h="$NEWH"; then
  run_leg "$d"; expect_red "fence union (live under the toggle only)" "per-item-loop.md: heading has no h: row: $NEWH"
else no "fence union (toggle): mutant invalid"; fi
# A list-item fence opening at 3 spaces and closing at 4 (valid CommonMark inside a list item): CommonMark-at-
# top-level reads its closer as content, so the indentation-blind toggle must pair it and leave the heading
# after it live. The later closed block re-syncs both readings by end of file, so the never-closes check
# cannot stand in for the heading check here (an indentation-bound toggle was green on this mutant).
d="$(new_leg indent-34)"
if apply "$d/$PIL" '{print} END {print ""; print "1. item"; print "   ```text"; print "   body"; print "    ```"; print ""; print h; print ""; print "```text"; print "x"; print "```"}' -v h="$NEWH"; then
  run_leg "$d"; expect_red "fence union (list-item fence, opener 3 / closer 4 spaces)" "per-item-loop.md: heading has no h: row: $NEWH"
else no "fence union (indent 3/4): mutant invalid"; fi
d="$(new_leg unclosed)"
if apply "$d/$PIL" '{print} END {print ""; print "```text"; print h}' -v h="$NEWH"; then
  run_leg "$d"; expect_red "fence never closes" "per-item-loop.md: a fenced block never closes"
else no "unclosed fence: mutant invalid"; fi

# AC4 — an anchored heading deleted from per-item-loop.md (the first prose h: row anchored there whose
# heading occurs exactly once in the file).
hrow=""; hhead=""
while IFS='	' read -r rid rhead; do
  if [ "$(awk -v h="$rhead" '{ s = $0; sub(/[ \t]+$/, "", s); if (s == h) n++ } END {print n + 0}' "$BASE/$PIL")" -eq 1 ]; then hrow="$rid"; hhead="$rhead"; break; fi
done < <(awk "$AWK_PIPES"'/^\| [A-Z][A-Z]-[0-9]/ { t = protect($0); n = split(t, c, "|")
  for (i = 2; i <= 10; i++) { sub(/^ +/, "", c[i]); sub(/ +$/, "", c[i]) }
  if (n == 11 && c[3] == "skills/automate-loop/per-item-loop.md" && c[4] ~ /^h: #/ && c[8] == "prose") print c[2] "\t" substr(c[4], 4) }' "$BASE/$INV/automate-loop.md")
DEL_HEAD='{ s = $0; sub(/[ \t]+$/, "", s); if (s == h) next; print }'
if [ -z "$hrow" ]; then no "AC4: precondition — no prose h: row anchored on a unique per-item-loop.md heading"
else
  d="$(new_leg ac4)"
  if apply "$d/$PIL" "$DEL_HEAD" -v h="$hhead"; then
    echo "  (deleted '$hhead' from a scratch copy of per-item-loop.md; its row is $hrow)"
    run_leg "$d"; expect_red "AC4 (anchored heading deleted)" "FAIL $hrow: anchor not found in skills/automate-loop/per-item-loop.md"
  else no "AC4: mutant invalid"; fi
  # AC4 exemption — the same deletion, with the row's home moved off prose, is not anchor-checked.
  d="$(new_leg nonprose)"
  if set_cell "$d/$INV/automate-loop.md" "$hrow" 7 step-scoped && apply "$d/$PIL" "$DEL_HEAD" -v h="$hhead"; then
    run_leg "$d"; expect_green "exemption: home step-scoped, anchor gone"
  else no "non-prose exemption: mutant invalid"; fi
  # A global home is anchor-checked exactly like prose: the same deletion is red.
  d="$(new_leg global)"
  if set_cell "$d/$INV/automate-loop.md" "$hrow" 7 global && apply "$d/$PIL" "$DEL_HEAD" -v h="$hhead"; then
    run_leg "$d"; expect_red "global row anchor gone" "FAIL $hrow: anchor not found in skills/automate-loop/per-item-loop.md"
  else no "global row anchor gone: mutant invalid"; fi
fi

# rationale:<doc>#<anchor> homes — a scratch rationale doc whose heading exercises every slug rule
# (case, spaces, dropped punctuation); the doc resolves, a missing doc and a missing anchor are red.
RDOC="docs/rationale/fixture-rationale.md"
RSLUG="why-the---x-flag--more"
rat_leg() { # <name> <id> <home cell> [needle] — no needle = expect green
  local d; d="$(new_leg "$1")"
  if mkdir -p "$d/loomwright/docs/rationale" \
    && printf '# Fixture rationale\n\n## Why: the `--x` flag & More\n\nBecause.\n\n#### Not A Slug Source\n' > "$d/loomwright/$RDOC" \
    && set_cell "$d/$INV/automate-loop.md" "$2" 7 "$3"; then
    run_leg "$d"; if [ -n "${4:-}" ]; then expect_red "$1" "$4"; else expect_green "$1"; fi
  else no "$1: mutant invalid"; fi
}
rid="$(row_field "$BASE/$INV/automate-loop.md" 1 1)"
if [ -z "$rid" ]; then no "rationale legs: precondition — automate-loop has no row"
else
  rat_leg "rationale row resolves in a scratch rationale doc" "$rid" "rationale:$RDOC#$RSLUG"
  rat_leg "rationale doc not found" "$rid" "rationale:docs/rationale/no-such-doc.md#$RSLUG" \
    "FAIL $rid: rationale doc not found: docs/rationale/no-such-doc.md"
  rat_leg "rationale anchor not found" "$rid" "rationale:$RDOC#not-a-slug-source" \
    "FAIL $rid: rationale anchor not found: not-a-slug-source"
fi

# AC5 — script subcommands.
SUB="gate-eval"; HELPERS="automate-helpers.sh"
grow="$(row_field "$BASE/$INV/automate-loop.md" "c[9] == \"script:$HELPERS $SUB\" || c[8] == \"script:$HELPERS $SUB\"" 1)"
if [ -z "$grow" ]; then no "AC5: precondition — no row reads script:$HELPERS $SUB"
else
  if [ -z "$(awk -v n="FAIL $grow:" 'index($0, n)' <<<"$real_out")" ]; then ok "AC5: row $grow reads script:$HELPERS $SUB and passes on the real tree"
  else no "AC5: row $grow reads script:$HELPERS $SUB but is red on the real tree"; fi
  d="$(new_leg ac5row)"
  if set_cell "$d/$INV/automate-loop.md" "$grow" 8 "script:$HELPERS $SUB-no-such-arm"; then
    run_leg "$d"; expect_red "AC5 (row renamed to a missing subcommand)" "FAIL $grow: implemented by $HELPERS has no case arm for '$SUB-no-such-arm'"
  else no "AC5 row rename: mutant invalid"; fi
  d="$(new_leg ac5arm scripts)"
  if apply "$d/loomwright/scripts/$HELPERS" '{ if (!done && $0 ~ "^[ \t]*" s "\\)") { sub(s "\\)", s "x)"); done = 1 } print }' -v s="$SUB"; then
    run_leg "$d"; expect_red "AC5 (case arm renamed in the script)" "FAIL $grow: implemented by $HELPERS has no case arm for '$SUB'"
  else no "AC5 arm rename: mutant invalid"; fi
fi

# AC6 — duplicate ids, within one file and across two.
id1="$(row_field "$BASE/$INV/automate-loop.md" 1 1)"
id2="$(awk '/^\| AL-[0-9]/ { n++; if (n == 2) { split($0, c, "|"); gsub(/ /, "", c[2]); print c[2]; exit } }' "$BASE/$INV/automate-loop.md")"
d="$(new_leg ac6a)"
if [ -n "$id1" ] && [ -n "$id2" ] && set_cell "$d/$INV/automate-loop.md" "$id2" 1 "$id1"; then
  run_leg "$d"; expect_red "AC6 (duplicate id in one file)" "FAIL $id1: duplicate id (automate-loop and automate-loop)"
else no "AC6 within-file: mutant invalid"; fi
sv1="$(row_field "$BASE/$INV/supervisor.md" 1 1)"
d="$(new_leg ac6b)"
if [ -n "$sv1" ] && set_cell "$d/$INV/supervisor.md" "$sv1" 1 "$id1"; then
  run_leg "$d"; expect_red "AC6 (duplicate id across files)" "FAIL $id1: duplicate id (automate-loop and supervisor)"
else no "AC6 cross-file: mutant invalid"; fi

# AC7 — a wrong count value, a missing ## Counts line, a deleted gap-list line.
d="$(new_leg ac7a)"
if apply "$d/$INV/supervisor.md" '{ if (!done && sub(/^- rows: /, "- rows: 9")) done = 1; print }'; then
  run_leg "$d"; expect_red "AC7 (wrong count value)" "FAIL supervisor: ## Counts says '- rows: 9"
else no "AC7 wrong count: mutant invalid"; fi
d="$(new_leg ac7b)"
if apply "$d/$INV/review-heal.md" '/^- GAP:/ {next} {print}'; then
  run_leg "$d"; expect_red "AC7 (missing GAP count line)" "FAIL review-heal: ## Counts has no '- GAP:' line"
else no "AC7 missing line: mutant invalid"; fi
# The gap row is synthesized in the scratch copy (review-heal reached GAP 0 in automate-speed/12, so it has no
# gap-list line left to delete): the first row whose test cell is not GAP becomes a GAP row, the GAP count
# follows it, and no gap-list line names it.
gid="$(row_field "$BASE/$INV/review-heal.md" 'c[10] != "GAP"' 1)"
d="$(new_leg ac7c)"
if [ -n "$gid" ] && set_cell "$d/$INV/review-heal.md" "$gid" 9 GAP \
   && apply "$d/$INV/review-heal.md" '{ if (!done && match($0, /^- GAP: [0-9]+$/)) { $0 = "- GAP: " (substr($0, 8) + 1); done = 1 } print }'; then
  run_leg "$d"; expect_red "AC7 (GAP row missing from the gap list)" "FAIL $gid: GAP row missing from the review-heal ## Gap list"
else no "AC7 gap-list drift: mutant invalid (gap id '$gid')"; fi

# AC7b — a test cell naming a file that does not exist.
trow="$(row_field "$BASE/$INV/automate-loop.md" 'c[10] == "test-automate-helpers.sh"' 1)"
d="$(new_leg ac7t)"
if [ -n "$trow" ] && set_cell "$d/$INV/automate-loop.md" "$trow" 9 test-does-not-exist.sh; then
  run_leg "$d"; expect_red "AC7b (test cell names a missing file)" "FAIL $trow: test cell names no existing test-*.sh"
else no "AC7b: mutant invalid"; fi

# Shape branches — one red leg per remaining FAIL branch of the checker, so none is dead code.
ALF="$INV/automate-loop.md"
cell_leg() { # <name> <id> <column 1..9> <value> <needle>
  local d; d="$(new_leg "$1")"
  if set_cell "$d/$ALF" "$2" "$3" "$4"; then run_leg "$d"; expect_red "$1" "$5"; else no "$1: mutant invalid"; fi
}
file_leg() { # <name> <file> <needle> <awk program> [awk -v args…]
  local name="$1" rel="$2" needle="$3" prog="$4" d; shift 4
  d="$(new_leg "$name")"
  if apply "$d/$rel" "$prog" "$@"; then run_leg "$d"; expect_red "$name" "$needle"; else no "$name: mutant invalid"; fi
}
cell_leg shape-kind "$id1" 6 maybe "FAIL $id1: unknown kind 'maybe'"
cell_leg shape-home "$id1" 7 elsewhere "FAIL $id1: unknown home 'elsewhere'"
cell_leg shape-q-short "$id1" 3 "q: too short" "FAIL $id1: q: anchor shorter than 12 characters"
cell_leg shape-anchor-form "$id1" 3 "x: not an anchor form" "FAIL $id1: anchor must start with"
cell_leg shape-impl-missing "$id1" 8 "script:no-such-script.sh" "FAIL $id1: implemented by names a script missing from scripts/: no-such-script.sh"
cell_leg shape-impl-form "$id1" 8 "maybe later" "FAIL $id1: implemented by must be"
cell_leg shape-file "$id1" 2 commands/supervisor.md "FAIL $id1: file 'commands/supervisor.md' is not a source of the automate-loop group"
cell_leg shape-id-prefix "$id1" 1 SV-999 "FAIL SV-999: id prefix is not the automate-loop group's AL"
cell_leg shape-id-form "$id1" 1 AL-1 "FAIL automate-loop row #1: malformed id 'AL-1'"
gal="$(awk '/^## Gap list/ {s = 1; next} s && /^[0-9]+\. AL-/ { sub(/^[0-9]+\. /, ""); sub(/ .*/, ""); print; exit }' "$BASE/$ALF")"
if [ -n "$gal" ]; then cell_leg gap-not-gap "$gal" 9 test-automate-helpers.sh "FAIL $gal: in the automate-loop ## Gap list but not a GAP row"
else no "gap-not-gap: precondition — automate-loop has no gap-list line"; fi
file_leg shape-cells "$ALF" "FAIL automate-loop row #1: malformed row (10 cells, want 9)" \
  '{ if (!d && index($0, "| " id " |") == 1) { $0 = $0 " extra |"; d = 1 } print }' -v id="$id1"
file_leg shape-sources "$ALF" "FAIL automate-loop: ## Sources is missing commands/automate.md" '$0 == "- `commands/automate.md`" {next} {print}'
file_leg shape-header "$ALF" "FAIL automate-loop: the ## Inventory table header is not the contract header" \
  '{ if (!d && sub(/\| implemented by \|/, "| impl |")) d = 1; print }'
file_leg shape-sections "$ALF" "FAIL automate-loop: ## sections must be exactly" '{ if ($0 == "## Counts") $0 = "## Totals"; print }'
file_leg shape-count-line "$ALF" "FAIL automate-loop: malformed ## Counts line: - rows: many" '{ sub(/^- rows: [0-9]+$/, "- rows: many"); print }'
file_leg shape-count-dup "$INV/review-heal.md" "FAIL review-heal: ## Counts has two '- GAP:' lines" '{print} /^- GAP:/ {print}'
# a synthesized gap-list line with a hyphen where the em dash belongs (works whether or not review-heal has gaps)
file_leg shape-gap-line "$INV/review-heal.md" "FAIL review-heal: malformed ## Gap list line" '{print} /^## Gap list/ {print "1. RH-001 - reason"}'
file_leg split-unclosed "loomwright/skills/automate-loop/SKILL.md" "SKILL.md: a split:begin block never closes" \
  '{print} END {print ""; print "<!-- split:begin x.md -->"}'

echo "RESULT: $pass/$((pass+fail)) passed"
[ "$fail" -eq 0 ]
