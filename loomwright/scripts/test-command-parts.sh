#!/usr/bin/env bash
# test-command-parts.sh — structural self-test for the automate-speed/22 split of three command
# docs into a router + on-demand part files (move-only, owner decision D6).
#
#   commands/setup.md       -> docs/command-parts/setup/<part>.md
#   commands/dreaming.md    -> docs/command-parts/dreaming/<part>.md
#   commands/agent-help.md  -> docs/command-parts/agent-help/<part>.md
#
# Parts live outside commands/ (a subdir there registers namespaced commands) and outside skills/
# (that would change the skill count). Each router is an INDEX in the parallel-automate/22
# convention: a moved run of sections is `<!-- split:begin <part> -->` … `<!-- split:end <part> -->`
# holding one index entry per moved heading, and runtime-only router prose (the read rule) sits in
# `<!-- index-only:begin -->` … `<!-- index-only:end -->`. The assembler is the precedent's own
# fixtures/automate-loop-split/assemble.sh (reused, never copied); this test copies the design of
# test-automate-loop-split.sh, not its file list.
#
# Checks (each router):
#   A. the router assembles (exit 0, non-empty);
#   B. INDEX ENTRIES — inside every split block, each heading of the part (fence-aware: a heading
#      inside a ``` / ~~~ fence is never an entry), in order, is a heading line followed by exactly
#      one `See [<path>](<path>).` line, `<path>` the marker's path; the part starts with its first
#      heading and ends with a newline;
#   C. NO ORPHANS — every *.md under docs/command-parts/<command>/ is named by exactly one block of
#      commands/<command>.md, every block names a file under that directory, and every directory
#      under docs/command-parts/ has a matching commands/<name>.md;
#   D. HEADINGS — the router's fence-aware heading sequence (index-only blocks dropped) equals the
#      assembled text's, so every moved heading is still at the old path as an entry. (A deleted KEPT
#      heading changes both sides equally; E is the check that sees that, mutation M-D2.)
#   E. MOVE-ONLY — the assembled text's sha256, size and line count equal the base row in
#      fixtures/command-parts/move-only.txt (recorded from 626f35f; no git history needed). It proves
#      the SPLIT COMMIT: once a router or part of a command no longer has its split-time sha256 (also
#      in the fixture, hashed with index-only blocks dropped, so read-rule prose may change without
#      retiring it), that command's proof prints ONE SKIP line naming the files;
#   F. SIZE — each router is < 20480 bytes. Never retired;
#   G. READ RULE — the router's index-only text names the runtime parts directory
#      (RT_DIR below, + <command>/) and every part file of the command (a full
#      path under it, or a backticked bare name once the directory is named); /setup's rule maps each
#      module name of its `## Parameters` list to exactly one part, and bare /setup to dashboard.md;
#   H. NO SQUASH — the positive form of CLAUDE.md's invariant grep finds nothing under
#      docs/command-parts/ (a part never claims to run `gh pr merge --squash`);
#   M. MUTATION CONTROLS — each mutant gated on non-empty + differs, on a mirror whose unmutated copy
#      passes the same check first: a split marker naming a missing part (A), a See line dropped (B),
#      an unreferenced part (C), a moved heading deleted from a part (D), a kept heading deleted (E),
#      one changed byte in a part (E), a router padded past 20480 bytes inside an index-only block (F
#      — E keeps running, the assembly is unchanged), the `memory` mapping removed from /setup's read
#      rule (G), a part gaining an un-negated `runs <the squash-merge command>` line (H); and M-I, a
#      scratch copy of the suite over a tree with one part edited after the split, which must exit 0
#      with exactly one SKIP line per edited command (E retired for it). The E-proof controls (M-D2 / M-E)
#      are gated per command on the LIVE tree: once a command is edited since the split they print
#      a `note:` (E's SKIP is that command's one retirement line), and M-F compares the padded
#      mirror's retirement state with the live tree's.
# Read-only; scratch files under mktemp -d. Exit 0 = all pass, 1 = any failure.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$PLUGIN/.." && pwd)"
ASM="$HERE/fixtures/automate-loop-split/assemble.sh"
FIXTURE="$HERE/fixtures/command-parts/move-only.txt"
BASE="626f35fab85796da1c0a4da0b2e80480a8249a02"
COMMANDS="setup dreaming agent-help"
LIMIT=20480
RT_DIR='${CLAUDE_PLUGIN_ROOT}/docs/command-parts/'

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT

sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  else return 1; fi
}

# headings <file> — every `#`..`######` heading line outside fenced blocks, in order (verbatim).
headings() {
  awk '
    {
      if (match($0, /^[ ]{0,3}(```+|~~~+)/)) {
        m = substr($0, RSTART, RLENGTH); sub(/^ +/, "", m)
        if (fence == "") { fence = m; next }
        rest = $0; sub(/^ +/, "", rest)
        if (substr(m, 1, 1) == substr(fence, 1, 1) && length(m) >= length(fence) && rest ~ /^[`~]+[ \t]*$/) { fence = ""; next }
        next
      }
      if (fence == "" && /^#{1,6} /) print
    }' "$1"
}

# drop_index_only <file> — the file without its index-only blocks.
drop_index_only() { awk '$0 == "<!-- index-only:begin -->" {s = 1; next} $0 == "<!-- index-only:end -->" {s = 0; next} !s' "$1"; }
# index_only <file> — the text INSIDE the file's index-only blocks (the read rule).
index_only() { awk '$0 == "<!-- index-only:begin -->" {s = 1; next} $0 == "<!-- index-only:end -->" {s = 0; next} s' "$1"; }

# blocks <router> — one "<file>\t<begin line>\t<end line>" row per split block.
blocks() {
  awk '/^<!-- split:begin [^ ]+ -->$/ {f = $3; b = NR} /^<!-- split:end [^ ]+ -->$/ {print f "\t" b "\t" NR}' "$1"
}

# expected_entries <path-as-named> <part> — the index entries a split block must hold.
expected_entries() {
  headings "$2" | awk -v f="$1" 'NR > 1 {print ""} {print; print ""; print "See [" f "](" f ")."}'
}

# physical <dir> <rel> — the physical absolute path of <dir>/<rel> (fails when the dir is missing).
physical() { local d; d="$(cd "$1/$(dirname "$2")" 2>/dev/null && pwd -P)" || return 1; echo "$d/$(basename "$2")"; }

# part_files <plugin root> <command> — every *.md under docs/command-parts/<command>/, sorted.
part_files() { [ -d "$1/docs/command-parts/$2" ] || return 0; find "$1/docs/command-parts/$2" -type f -name '*.md' | env LC_ALL=C sort; }

# check_assembles <plugin root> <command> <out> — A.
check_assembles() { bash "$ASM" "$1/commands/$2.md" "$3" 2> "$TMP/asm.err" && [ -s "$3" ]; }

# check_entries <router> — B; one line per problem; returns 0 iff none.
check_entries() {
  local idx="$1" dir probs=0 f b e sf
  dir="$(dirname "$idx")"
  [ -n "$(blocks "$idx")" ] || { echo "    $idx: no split blocks"; return 1; }
  while IFS="$(printf '\t')" read -r f b e; do
    sf="$dir/$f"
    if [ ! -s "$sf" ]; then echo "    $f: part missing or empty"; probs=$((probs+1)); continue; fi
    [ "$(tail -c 1 "$sf" | od -An -c | tr -d ' ')" = '\n' ] || { echo "    $f: does not end with a newline"; probs=$((probs+1)); }
    [ "$(head -1 "$sf")" = "$(headings "$sf" | head -1)" ] || { echo "    $f: does not start with its first heading"; probs=$((probs+1)); }
    expected_entries "$f" "$sf" > "$TMP/want.$$"
    awk -v b="$b" -v e="$e" 'NR > b && NR < e' "$idx" > "$TMP/have.$$"
    if [ ! -s "$TMP/want.$$" ]; then echo "    $f: holds no heading"; probs=$((probs+1))
    elif ! cmp -s "$TMP/want.$$" "$TMP/have.$$"; then
      echo "    $f: its block is not exactly one heading + 'See [$f]($f).' entry per heading of the part, in order"
      diff "$TMP/want.$$" "$TMP/have.$$" | sed -n '1,6s/^/      /p'
      probs=$((probs+1))
    fi
  done <<EOF
$(blocks "$idx")
EOF
  [ "$probs" -eq 0 ]
}

# check_orphans <plugin root> <command> — C for one command; one line per problem.
check_orphans() {
  local root="$1" c="$2" idx sdir probs=0 f b e p x cnt
  idx="$root/commands/$c.md"
  sdir="$(cd "$root/docs/command-parts/$c" 2>/dev/null && pwd -P)" || { echo "    docs/command-parts/$c/ is missing"; return 1; }
  : > "$TMP/named.$$"
  while IFS="$(printf '\t')" read -r f b e; do
    [ -n "$f" ] || continue
    p="$(physical "$(dirname "$idx")" "$f")" || p=""
    case "$p" in
      "$sdir"/*) echo "$p" >> "$TMP/named.$$" ;;
      *) echo "    commands/$c.md: block names $f, outside docs/command-parts/$c/"; probs=$((probs+1)) ;;
    esac
  done <<EOF
$(blocks "$idx")
EOF
  while IFS= read -r x; do
    [ -n "$x" ] || continue
    p="$(physical "$(dirname "$x")" "${x##*/}")"
    cnt="$(grep -cxF -- "$p" "$TMP/named.$$")"
    [ "$cnt" = "1" ] || { echo "    ${x#"$root"/}: named by $cnt split block(s) of commands/$c.md (want exactly 1)"; probs=$((probs+1)); }
  done <<EOF
$(part_files "$root" "$c")
EOF
  [ "$probs" -eq 0 ]
}

# check_dirs <plugin root> — C: every dir under docs/command-parts/ has a commands/<name>.md.
check_dirs() {
  local root="$1" d probs=0
  for d in "$root"/docs/command-parts/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    [ -f "$root/commands/${d##*/}.md" ] || { echo "    docs/command-parts/${d##*/}/ has no commands/${d##*/}.md"; probs=$((probs+1)); }
  done
  [ "$probs" -eq 0 ]
}

# check_headings <router> — D: router heading sequence (index-only dropped) == assembled text's.
check_headings() {
  drop_index_only "$1" > "$TMP/idx-noio.$$"
  headings "$TMP/idx-noio.$$" > "$TMP/ih.$$"
  bash "$ASM" "$1" > "$TMP/asm.$$" 2>/dev/null || { echo "    $1 does not assemble"; return 1; }
  headings "$TMP/asm.$$" > "$TMP/ah.$$"
  cmp -s "$TMP/ih.$$" "$TMP/ah.$$" && return 0
  echo "    heading sequences differ (router < > assembled):"; diff "$TMP/ih.$$" "$TMP/ah.$$" | sed -n '1,6s/^/      /p'
  return 1
}

# proof_matches <router rel> <assembled file> — 0 iff sha256 / bytes / lines equal the fixture row.
proof_matches() {
  local want got
  want="$(awk -F '\t' -v r="$1" '$1 == "original" && $2 == r {print $3 " " $4 " " $5}' "$FIXTURE")"
  got="$(sha256 < "$2") $(wc -c < "$2" | tr -d ' ') $(wc -l < "$2" | tr -d ' ')"
  [ -n "$want" ] && [ "$want" = "$got" ]
}
# edited_since_split <tree root> <command> — " <rel>" per split-time file of that command whose
# index-only-dropped sha256 differs (or that is gone).
edited_since_split() {
  local p want out=""
  while IFS="$(printf '\t')" read -r p want; do
    [ -n "$p" ] || continue
    if [ ! -f "$1/$p" ]; then out="$out $p(gone)"; continue; fi
    [ "$(drop_index_only "$1/$p" | sha256)" = "$want" ] || out="$out $p"
  done <<EOF
$(awk -F '\t' -v r="loomwright/commands/$2.md" -v d="loomwright/docs/command-parts/$2/" \
    '$1 == "split-time" && ($2 == r || index($2, d) == 1) {print $2 "\t" $3}' "$FIXTURE")
EOF
  printf '%s' "$out"
}

# names_part <rule text file> <command> <part rel to the command's parts dir> — 0 iff the read rule
# names the part: its full runtime path, or a backticked bare name (the dir is named once).
names_part() {
  grep -qF -- "$RT_DIR$2/$3" "$1" && return 0
  grep -qF -- "\`$3\`" "$1"
}
# check_read_rule <plugin root> <command> — G (every command); one line per problem.
check_read_rule() {
  local root="$1" c="$2" probs=0 x rel
  index_only "$root/commands/$c.md" > "$TMP/rule.$$"
  [ -s "$TMP/rule.$$" ] || { echo "    commands/$c.md has no index-only read rule"; return 1; }
  grep -qF -- "$RT_DIR$c/" "$TMP/rule.$$" || { echo "    the read rule never names $RT_DIR$c/"; probs=$((probs+1)); }
  while IFS= read -r x; do
    [ -n "$x" ] || continue
    rel="${x#"$root/docs/command-parts/$c/"}"
    names_part "$TMP/rule.$$" "$c" "$rel" || { echo "    the read rule does not name part $rel"; probs=$((probs+1)); }
  done <<EOF
$(part_files "$root" "$c")
EOF
  [ "$probs" -eq 0 ]
}
# check_setup_modules <setup router> — G (/setup): each `## Parameters` module maps to ONE part.
# A mapping is an index-only bullet `- <lhs> → <rhs>`: the module is backticked in <lhs>, and the
# part names in <rhs> are the [a-z0-9-]+.md tokens.
check_setup_modules() {
  local idx="$1" probs=0 mods m nb parts
  mods="$(awk '/^## Parameters/ {s = 1; next} s && /^## / {exit} s && /^- \*\*module\*\*/ {print; exit}' "$idx" \
          | grep -oE '`[a-z0-9-]+`' | tr -d '`')"
  [ -n "$mods" ] || { echo "    no module list under /setup's ## Parameters — the mapping check would be vacuous"; return 1; }
  index_only "$idx" | awk 'index($0, " → ") && /^[ ]*- / {print}' > "$TMP/map.$$"
  for m in $mods; do
    nb="$(awk -v m="\`$m\`" '{split($0, a, " → "); if (index(a[1], m)) n++} END {print n + 0}' "$TMP/map.$$")"
    parts="$(awk -v m="\`$m\`" '{split($0, a, " → "); if (index(a[1], m)) print a[2]}' "$TMP/map.$$" \
             | grep -oE '[a-z0-9-]+\.md' | env LC_ALL=C sort -u | tr '\n' ' ')"
    if [ "$nb" != "1" ] || [ "$(printf '%s' "$parts" | wc -w | tr -d ' ')" != "1" ]; then
      echo "    module '$m' maps through $nb rule line(s) to part(s) [${parts% }] (want exactly one line, one part)"; probs=$((probs+1))
    fi
  done
  parts="$(awk '{split($0, a, " → "); if (index(a[1], "bare") && index(a[1], "`/setup`")) print a[2]}' "$TMP/map.$$" \
           | grep -oE '[a-z0-9-]+\.md' | head -1)"
  [ "$parts" = "dashboard.md" ] || { echo "    bare /setup reads '${parts:-nothing}' first (want dashboard.md)"; probs=$((probs+1)); }
  [ "$probs" -eq 0 ]
}

# squash_hits <dir> — the positive-form invariant grep over <dir> (empty = clean).
# The needle is assembled from two pieces so this file is NOT itself a hit of CLAUDE.md's
# positive-form surface grep (whose output this split must not change, AC5); nothing here merges.
SQ="gh pr merge"; SQ="$SQ --squash"
squash_hits() { grep -rn -- "$SQ" "$1" 2>/dev/null | grep -viE "no |never |not " || true; }

echo "== A. each router assembles =="
for c in $COMMANDS; do
  if check_assembles "$PLUGIN" "$c" "$TMP/asm-$c.md"; then
    ok "A: commands/$c.md assembles ($(wc -l < "$TMP/asm-$c.md" | tr -d ' ') lines from the router + $(bash "$ASM" --files "$PLUGIN/commands/$c.md" | wc -l | tr -d ' ') part(s))"
  else
    no "A: commands/$c.md does not assemble: $(cat "$TMP/asm.err")"
  fi
done

echo "== B. index entries mirror each part's headings (fence-aware) =="
for c in $COMMANDS; do
  if out="$(check_entries "$PLUGIN/commands/$c.md")"; then ok "B: commands/$c.md — every split block holds one heading + See entry per heading of its part"
  else no "B: commands/$c.md index entries drifted:"; printf '%s\n' "$out"; fi
done

echo "== C. no orphan part; every block names its own command's parts dir =="
for c in $COMMANDS; do
  if out="$(check_orphans "$PLUGIN" "$c")"; then ok "C: every docs/command-parts/$c/*.md is named by exactly one block of commands/$c.md, and every block names a file there"
  else no "C: docs/command-parts/$c/:"; printf '%s\n' "$out"; fi
done
if out="$(check_dirs "$PLUGIN")"; then ok "C: every directory under docs/command-parts/ has a matching commands/<name>.md"
else no "C: orphaned parts directories:"; printf '%s\n' "$out"; fi

echo "== D. every moved heading is still at the old path =="
for c in $COMMANDS; do
  if out="$(check_headings "$PLUGIN/commands/$c.md")"; then ok "D: commands/$c.md — router heading sequence == assembled heading sequence ($(wc -l < "$TMP/ih.$$" | tr -d ' ') headings)"
  else no "D: commands/$c.md:"; printf '%s\n' "$out"; fi
done

echo "== E. move-only: the assembled text is the pre-split original, byte for byte =="
if ! printf 'x' | sha256 >/dev/null 2>&1; then
  no "E: no sha256 tool (shasum / sha256sum) — the move-only proof cannot run (never read as clean)"
elif [ ! -s "$FIXTURE" ]; then
  no "E: fixture missing: $FIXTURE"
else
  for c in $COMMANDS; do
    rel="loomwright/commands/$c.md"
    n="$(awk -F '\t' -v r="$rel" -v d="loomwright/docs/command-parts/$c/" '$1 == "split-time" && ($2 == r || index($2, d) == 1)' "$FIXTURE" | wc -l | tr -d ' ')"
    if [ "$n" -lt 2 ]; then no "E: the fixture records no split-time router + part for /$c"; continue; fi
    edited="$(edited_since_split "$REPO" "$c")"
    if [ -n "$edited" ]; then
      echo "  SKIP: E move-only proof for /$c — edited since the automate-speed/22 split:$edited (it proves the split commit only)"
    elif bash "$ASM" "$REPO/$rel" "$TMP/proof-$c.md" 2>/dev/null && proof_matches "$rel" "$TMP/proof-$c.md"; then
      ok "E: assembled commands/$c.md == its pre-split original (sha256, size and line count; $n split-time files unedited)"
    else
      no "E: assembled commands/$c.md differs from its pre-split original"
      if git -C "$REPO" cat-file -e "$BASE:$rel" 2>/dev/null; then
        git -C "$REPO" show "$BASE:$rel" | diff - "$TMP/proof-$c.md" | sed -n '1,8s/^/      /p'
      fi
    fi
  done
  # When the base commit is reachable, the fixture's original rows are re-derived from it.
  if git -C "$REPO" cat-file -e "$BASE^{commit}" 2>/dev/null; then
    bad=""
    for c in $COMMANDS; do
      git -C "$REPO" show "$BASE:loomwright/commands/$c.md" > "$TMP/base-orig"
      proof_matches "loomwright/commands/$c.md" "$TMP/base-orig" || bad="$bad $c"
    done
    [ -z "$bad" ] && ok "E: the fixture's original rows equal git show ${BASE:0:7} for all three commands" || no "E: fixture original row(s) differ from ${BASE:0:7}:$bad"
  else
    echo "  note: base ${BASE:0:7} not in this clone — the fixture's original rows are trusted as committed"
  fi
fi

echo "== F. each router is under $LIMIT bytes =="
for c in $COMMANDS; do
  sz="$(wc -c < "$PLUGIN/commands/$c.md" | tr -d ' ')"
  [ "$sz" -lt "$LIMIT" ] && ok "F: commands/$c.md is $sz bytes (< $LIMIT)" || no "F: commands/$c.md is $sz bytes (>= $LIMIT)"
done

echo "== G. the read rule names every part (and /setup maps every module to one part) =="
for c in $COMMANDS; do
  if out="$(check_read_rule "$PLUGIN" "$c")"; then ok "G: commands/$c.md's read rule names $RT_DIR$c/ and every one of its $(part_files "$PLUGIN" "$c" | wc -l | tr -d ' ') part(s)"
  else no "G: commands/$c.md read rule:"; printf '%s\n' "$out"; fi
done
if out="$(check_setup_modules "$PLUGIN/commands/setup.md")"; then ok "G: /setup's read rule maps every ## Parameters module to exactly one part, and bare /setup to dashboard.md"
else no "G: /setup module mapping:"; printf '%s\n' "$out"; fi

echo "== H. no part claims to run $SQ (positive form) =="
hits="$(squash_hits "$PLUGIN/docs/command-parts/")"
[ -z "$hits" ] && ok "H: the positive-form '$SQ' grep over docs/command-parts/ prints nothing" \
  || { no "H: a part carries a positive-form squash-merge line:"; printf '%s\n' "$hits" | sed 's/^/    /'; }

echo "== M. mutation controls =="
# mk_mirror <dir> — a scratch tree <dir>/loomwright/ with the plugin manifest, the three routers and
# docs/command-parts/ (so fixture rel paths and assemble.sh's plugin-root bound both resolve).
mk_mirror() {
  local p="$1/loomwright" c
  mkdir -p "$p/.claude-plugin" "$p/commands" "$p/docs"
  cp "$PLUGIN/.claude-plugin/plugin.json" "$p/.claude-plugin/"
  for c in $COMMANDS; do cp "$PLUGIN/commands/$c.md" "$p/commands/"; done
  cp -R "$PLUGIN/docs/command-parts" "$p/docs/"
}
# mutated <new> <orig> — the mutant is usable: non-empty and different.
mutated() { [ -s "$1" ] && ! cmp -s "$1" "$2"; }

# M-A — a split marker naming a missing part, in agent-help.md.
MA="$TMP/ma"; mk_mirror "$MA"; f="$MA/loomwright/commands/agent-help.md"
if check_assembles "$MA/loomwright" agent-help "$TMP/ma.out"; then
  awk '{print} !d && /^<!-- split:end / {print "<!-- split:begin ../docs/command-parts/agent-help/missing.md -->"; print "<!-- split:end ../docs/command-parts/agent-help/missing.md -->"; d = 1}' \
    "$PLUGIN/commands/agent-help.md" > "$f"
  if mutated "$f" "$PLUGIN/commands/agent-help.md"; then
    check_assembles "$MA/loomwright" agent-help "$TMP/ma.out" && no "MUTATION CONTROL: a block naming a missing part was ACCEPTED (A)" \
      || ok "MUTATION CONTROL: a block naming a missing part fails assembly (A)"
  else no "could not build the missing-part mutant — A control inconclusive"; fi
else no "the unmutated mirror fails A — the A control is inconclusive"; fi

# M-B — one See line of setup.md's memory.md block dropped.
MB="$TMP/mb"; mk_mirror "$MB"; f="$MB/loomwright/commands/setup.md"
if check_entries "$f" >/dev/null; then
  awk '!d && $0 == "See [../docs/command-parts/setup/memory.md](../docs/command-parts/setup/memory.md)." {d = 1; next} {print}' "$PLUGIN/commands/setup.md" > "$f"
  if mutated "$f" "$PLUGIN/commands/setup.md"; then
    check_entries "$f" >/dev/null && no "MUTATION CONTROL: an index entry with its See line removed was ACCEPTED (B)" \
      || ok "MUTATION CONTROL: an index entry with its See line removed is REJECTED (B)"
  else no "could not build the See-line-removed mutant — B control inconclusive"; fi
else no "the unmutated mirror fails B — the B control is inconclusive"; fi

# M-C — an unreferenced extra.md under docs/command-parts/setup/.
MC="$TMP/mc"; mk_mirror "$MC"
if check_orphans "$MC/loomwright" setup >/dev/null; then
  printf '## Extra\n\nunreferenced.\n' > "$MC/loomwright/docs/command-parts/setup/extra.md"
  if [ -s "$MC/loomwright/docs/command-parts/setup/extra.md" ] && [ "$(part_files "$MC/loomwright" setup | wc -l)" -gt "$(part_files "$PLUGIN" setup | wc -l)" ]; then
    check_orphans "$MC/loomwright" setup >/dev/null && no "MUTATION CONTROL: an unreferenced part was ACCEPTED (C)" \
      || ok "MUTATION CONTROL: an unreferenced part is REJECTED (C)"
  else no "could not build the orphan mutant — C control inconclusive"; fi
else no "the unmutated mirror fails C — the C control is inconclusive"; fi

# M-D — a moved heading deleted from a dreaming part: the router keeps its entry, the assembly loses it.
MD="$TMP/md"; mk_mirror "$MD"
victim="$(bash "$ASM" --files "$PLUGIN/commands/dreaming.md" | head -1)"; vrel="${victim##*/}"
vf="$MD/loomwright/docs/command-parts/dreaming/$vrel"
if [ -n "$vrel" ] && check_headings "$MD/loomwright/commands/dreaming.md" >/dev/null; then
  vh="$(headings "$victim" | sed -n '2p')"
  awk -v h="$vh" '!d && $0 == h {d = 1; next} {print}' "$victim" > "$vf"
  if [ -n "$vh" ] && mutated "$vf" "$victim"; then
    check_headings "$MD/loomwright/commands/dreaming.md" >/dev/null && no "MUTATION CONTROL: a moved heading deleted from $vrel was ACCEPTED (D)" \
      || ok "MUTATION CONTROL: a moved heading deleted from $vrel is REJECTED (D)"
  else no "could not build the moved-heading mutant — D control inconclusive"; fi
else no "the unmutated mirror fails D (or dreaming has no part) — the D control is inconclusive"; fi

# M-D2 / M-E — the move-only proof, run on a mirror: a KEPT heading deleted from dreaming.md, and
# one changed byte (a trailing space) on a moved line of setup/memory.md, each fail it.
# proof_on <mirror root> <command> — 0 iff the mirror's assembly matches the fixture's original row.
# Each control is gated on ITS OWN command: once the live tree has edited that command since the
# split, E has retired it to a SKIP and the mirror (built from the live tree) has no passing
# baseline to mutate, so the control prints a `note:` (not a second SKIP — E's one SKIP line per
# command is the retirement record) and the other command's control still runs. Same shape as the
# precedent's M9 note (test-automate-loop-split.sh).
proof_on() { bash "$ASM" "$1/loomwright/commands/$2.md" "$TMP/proof-on.$$" 2>/dev/null && proof_matches "loomwright/commands/$2.md" "$TMP/proof-on.$$"; }
ME="$TMP/me"; mk_mirror "$ME"
if ! printf 'x' | sha256 >/dev/null 2>&1; then
  no "no sha256 tool — the E controls are inconclusive"
else
  if [ -n "$(edited_since_split "$REPO" dreaming)" ]; then
    echo "  note: /dreaming is edited since the split (E retired) — the M-D2 kept-heading control has no unedited baseline to mutate"
  elif ! proof_on "$ME" dreaming; then
    no "the unmutated mirror fails the /dreaming move-only proof — the M-D2 control is inconclusive"
  else
    f="$ME/loomwright/commands/dreaming.md"
    kept="$(blocks "$PLUGIN/commands/dreaming.md" | awk -F '\t' '{print $2 "\t" $3}' > "$TMP/me.blk"; \
            awk 'NR == FNR {b[++n] = $1; e[n] = $2; next} /^## / {for (i = 1; i <= n; i++) if (FNR >= b[i] && FNR <= e[i]) next; print; exit}' "$TMP/me.blk" "$PLUGIN/commands/dreaming.md")"
    awk -v h="$kept" '!d && $0 == h {d = 1; next} {print}' "$PLUGIN/commands/dreaming.md" > "$f"
    if [ -n "$kept" ] && mutated "$f" "$PLUGIN/commands/dreaming.md"; then
      check_headings "$f" >/dev/null && dh=1 || dh=0
      proof_on "$ME" dreaming && no "MUTATION CONTROL: a deleted kept heading ('$kept') passed the move-only proof (E)" \
        || ok "MUTATION CONTROL: a deleted kept heading fails the move-only proof (E; D alone $([ "$dh" = 1 ] && echo 'cannot see it — both sides lose it' || echo 'also rejects it'))"
    else no "could not build the kept-heading mutant — E control inconclusive"; fi
    cp "$PLUGIN/commands/dreaming.md" "$f"
  fi
  if [ -n "$(edited_since_split "$REPO" setup)" ]; then
    echo "  note: /setup is edited since the split (E retired) — the M-E changed-byte control has no unedited baseline to mutate"
  elif ! proof_on "$ME" setup; then
    no "the unmutated mirror fails the /setup move-only proof — the M-E control is inconclusive"
  else
    f="$ME/loomwright/docs/command-parts/setup/memory.md"
    awk 'NR == 3 {print $0 " "; next} {print}' "$PLUGIN/docs/command-parts/setup/memory.md" > "$f"
    if mutated "$f" "$PLUGIN/docs/command-parts/setup/memory.md"; then
      proof_on "$ME" setup && no "MUTATION CONTROL: a part with one changed byte passed the move-only proof (E)" \
        || ok "MUTATION CONTROL: a part with one changed byte fails the move-only proof (E)"
      case "$(edited_since_split "$ME" setup)" in *"docs/command-parts/setup/memory.md"*) ok "MUTATION CONTROL: the changed part retires /setup's proof to a SKIP naming it (E gating)" ;;
        *) no "MUTATION CONTROL: the changed part did NOT retire /setup's proof (E gating)" ;; esac
    else no "could not build the changed-byte mutant — E control inconclusive"; fi
  fi
fi

# M-F — setup.md padded past the limit INSIDE an index-only block: F rejects it, while the assembly
# is unchanged and E keeps running (index-only prose never retires the proof).
MF="$TMP/mf"; mk_mirror "$MF"; f="$MF/loomwright/commands/setup.md"
pad="$(awk 'BEGIN {for (i = 0; i < 21000; i++) printf "x"}')"
awk -v p="$pad" '{print} !d && $0 == "<!-- index-only:begin -->" {print p; d = 1}' "$PLUGIN/commands/setup.md" > "$f"
if mutated "$f" "$PLUGIN/commands/setup.md"; then
  [ "$(wc -c < "$f" | tr -d ' ')" -lt "$LIMIT" ] && no "MUTATION CONTROL: a router padded past $LIMIT bytes was ACCEPTED (F)" \
    || ok "MUTATION CONTROL: a router padded past $LIMIT bytes is REJECTED (F)"
  # The padding must not change E's retirement state: compared with the LIVE tree's (empty on an
  # unedited tree, the same retired file list once /setup is edited since the split).
  bash "$ASM" "$f" "$TMP/mf.asm" 2>/dev/null && cmp -s "$TMP/mf.asm" "$TMP/asm-setup.md" \
    && [ "$(edited_since_split "$MF" setup)" = "$(edited_since_split "$REPO" setup)" ] \
    && ok "MUTATION CONTROL: the index-only padding leaves the assembly identical and E's retirement state unchanged (only F trips)" \
    || no "MUTATION CONTROL: the index-only padding changed the assembly or retired E — the F control is not isolated"
else no "could not build the padded mutant — F control inconclusive"; fi

# M-G — the line naming memory.md removed from /setup's read rule.
MG="$TMP/mg"; mk_mirror "$MG"; f="$MG/loomwright/commands/setup.md"
if check_read_rule "$MG/loomwright" setup >/dev/null && check_setup_modules "$f" >/dev/null; then
  awk '$0 == "<!-- index-only:begin -->" {io = 1} $0 == "<!-- index-only:end -->" {io = 0} io && index($0, "/docs/command-parts/setup/memory.md") {next} {print}' "$PLUGIN/commands/setup.md" > "$f"
  if mutated "$f" "$PLUGIN/commands/setup.md" && [ "$(wc -l < "$f" | tr -d ' ')" -eq $(( $(wc -l < "$PLUGIN/commands/setup.md" | tr -d ' ') - 1 )) ]; then
    check_setup_modules "$f" >/dev/null && no "MUTATION CONTROL: /setup's read rule without the memory mapping was ACCEPTED (G)" \
      || ok "MUTATION CONTROL: /setup's read rule without the memory mapping is REJECTED (G modules)"
    check_read_rule "$MG/loomwright" setup >/dev/null && no "MUTATION CONTROL: a read rule that no longer names memory.md was ACCEPTED (G)" \
      || ok "MUTATION CONTROL: a read rule that no longer names memory.md is REJECTED (G parts)"
  else no "could not build the memory-mapping mutant (exactly one line fewer) — G control inconclusive"; fi
else no "the unmutated mirror fails G — the G control is inconclusive"; fi

# M-H — a part gaining a positive-form squash-merge line.
MH="$TMP/mh"; mk_mirror "$MH"; f="$MH/loomwright/docs/command-parts/agent-help/guide.md"
if [ -z "$(squash_hits "$MH/loomwright/docs/command-parts/")" ]; then
  printf 'This step runs `%s` on the PR.\n' "$SQ" >> "$f"
  if mutated "$f" "$PLUGIN/docs/command-parts/agent-help/guide.md"; then
    [ -z "$(squash_hits "$MH/loomwright/docs/command-parts/")" ] && no "MUTATION CONTROL: a part with a positive-form squash line was ACCEPTED (H)" \
      || ok "MUTATION CONTROL: a part with a positive-form squash line is REJECTED (H)"
  else no "could not build the squash mutant — H control inconclusive"; fi
else no "the unmutated mirror fails H — the H control is inconclusive"; fi

# M-I — E retirement, end to end: a scratch copy of this suite + the three routers and their parts,
# with ONE byte appended to a moved line of setup/memory.md, must exit 0 with exactly one SKIP line
# for /setup (E's, naming memory.md) and one per command the live tree already edited — an edit after the split retires the proof, it never reds
# the suite. The nested copy skips M-I itself (TEST_COMMAND_PARTS_NESTED) so it cannot recurse.
if [ -n "${TEST_COMMAND_PARTS_NESTED:-}" ]; then
  echo "  note: M-I skipped inside the nested run (no recursion)"
else
  MI="$TMP/mi"; mk_mirror "$MI"
  mkdir -p "$MI/loomwright/scripts/fixtures/automate-loop-split" "$MI/loomwright/scripts/fixtures/command-parts"
  cp "$HERE/test-command-parts.sh" "$HERE/hermetic-test-env.sh" "$MI/loomwright/scripts/"
  cp "$ASM" "$MI/loomwright/scripts/fixtures/automate-loop-split/"
  cp "$FIXTURE" "$MI/loomwright/scripts/fixtures/command-parts/"
  f="$MI/loomwright/docs/command-parts/setup/memory.md"
  awk 'NR == 3 {print $0 " "; next} {print}' "$PLUGIN/docs/command-parts/setup/memory.md" > "$f"
  if mutated "$f" "$PLUGIN/docs/command-parts/setup/memory.md" && [ -n "$(edited_since_split "$MI" setup)" ]; then
    TEST_COMMAND_PARTS_NESTED=1 bash "$MI/loomwright/scripts/test-command-parts.sh" > "$TMP/mi.out" 2>&1; mrc=$?
    nskip="$(grep -c '^  SKIP:' "$TMP/mi.out")"
    # One SKIP per command edited in the scratch tree: /setup (this edit) plus any command the LIVE
    # tree has already edited since the split (the mirror is copied from it).
    want=0; for c in $COMMANDS; do [ -n "$(edited_since_split "$MI" "$c")" ] && want=$((want+1)); done
    nsetup="$(grep -c '^  SKIP: E move-only proof for /setup .*docs/command-parts/setup/memory.md' "$TMP/mi.out")"
    if [ "$mrc" -eq 0 ] && [ "$nskip" = "$want" ] && [ "$nsetup" = "1" ]; then
      ok "MUTATION CONTROL: one part edited after the split ⇒ the suite exits 0 with exactly ONE named SKIP for /setup ($nskip SKIP line(s), one per edited command)"
    else
      no "MUTATION CONTROL: one part edited after the split ⇒ rc=$mrc, $nskip SKIP line(s), $nsetup for /setup (want rc 0, $want total, exactly 1 naming /setup + memory.md):"
      grep -E '^  (FAIL|SKIP):' "$TMP/mi.out" | sed -n '1,8s/^/    /p'
    fi
  else no "could not build the edited-part tree — M-I control inconclusive"; fi
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
