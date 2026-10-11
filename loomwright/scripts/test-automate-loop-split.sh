#!/usr/bin/env bash
# test-automate-loop-split.sh — structural self-test for the parallel-automate/22 split of the
# /automate engine's shared doc surfaces.
#
# Three surfaces stay an INDEX at their old path and move whole sections, verbatim, into split files:
#   skills/automate-loop/SKILL.md          -> skills/automate-loop/<concern>.md
#   commands/automate.md                   -> skills/automate-loop/command-lanes.md (never a new file
#                                             under commands/ — that would count as a new command)
#   docs/result-schemas/automate-run.md    -> docs/result-schemas/automate-run/<concern>.md (a SUBDIR:
#                                             test-result-schemas-split.sh owns docs/result-schemas/*.md)
# An index marks each moved run of sections with `<!-- split:begin <file> -->` … `<!-- split:end
# <file> -->` and index-only prose with `<!-- index-only:begin -->` … `<!-- index-only:end -->`;
# fixtures/automate-loop-split/assemble.sh turns an index back into its DOCUMENTED-ORDER text (index
# segments + split files, in marker order). The tests that read moved sections read that assembly.
#
# Checks (each surface):
#   A. the index assembles (exit 0, non-empty);
#   A2. assemble.sh's split-path bound, on a scratch plugin: a leading `../` inside the plugin root
#      assembles; a `..` after a named segment, a climb out of the plugin root, and a climb from an
#      index with no plugin root each fail CLOSED (non-zero, empty stdout, an `assemble:` reason);
#   B. INDEX ENTRIES — inside every split block, each heading of the split file, in order, is a heading
#      line followed by exactly one `See [<file>](<file>).` line, and nothing else; the split file
#      starts with its first heading and ends with a newline;
#   C. NO ORPHANS — every *.md in skills/automate-loop/ (but SKILL.md) is named by exactly one SKILL.md
#      or commands/automate.md block, every *.md in result-schemas/automate-run/ by exactly one
#      automate-run.md block, and every block names a file in its surface's own split directory (C3/C4);
#   D. HEADINGS (AC1) — the index's heading sequence (kept headings + entries) equals the assembled
#      text's, so every pre-split heading is still at the old path, in place or as an entry;
#   E. MOVE-ONLY (AC2) — the assembled text equals the pre-split original byte for byte: its sha256,
#      size and line count match fixtures/automate-loop-split/move-only.txt (recorded from base
#      da2fac5; no git history needed). The only allowed delta is SKILL.md's frontmatter `version:` /
#      `lastUpdated:` lines (a minor bump, AC1), substituted back before hashing. This proves the SPLIT
#      COMMIT: it runs while every index and split file still has its split-time sha256 (also in the
#      fixture; an index is hashed with its index-only blocks dropped, so index-only prose — which
#      assemble.sh drops — may change without retiring the proof); once a later item edits one, the
#      proof prints one SKIP line naming the files — the byte identity is a property of the move, not
#      a freeze of the engine docs;
#   F. STEP 0 (AC5) — commands/automate.md Step 0 names every skill split file, in documented order;
#   G. CITATIONS (AC3) — every citation of a split surface in the tracked tree (CHANGELOG.md excluded):
#      the skill path (`automate-loop/SKILL.md`, `automate-loop SKILL`, `automate-loop`) followed by a
#      section sign and a number and/or a quoted anchor, or by a space and a quoted anchor; the command
#      path or the AUTOMATE_RUN doc followed by a quoted anchor. A number resolves to an index heading
#      `## §N …`; an anchor to an index heading, a bold bullet label in the index's own text, or a row
#      of the index's `## Cited sub-section anchors` table — and through an entry or a row, the named
#      split file must hold that heading or label. Matching drops backticks, ignores a leading
#      `§N — `, and accepts a word-boundary prefix. A quoted anchor wrapped onto the next line is joined;
#   H. READER WIRING (C1/C2) — the tests that read moved text read the assembly: no raw read of the
#      skill or AUTOMATE_RUN index, every `result-schemas/*.md` glob also covers `automate-run/*.md`, no
#      multi-file absence scan of the raw command body, and test-rules-gate-seams.sh's AL names the
#      split file the SKILL index gives for `## §10`;
#   M. MUTATION CONTROLS — each mutant gated on non-empty + differs (+ bash -n for a script mutant):
#      an index entry's See line dropped (B), an unreferenced split file (C), a split file with one
#      changed byte (E), an index-only edit keeping E running while an edit outside index-only blocks
#      retires it (E gating), Step 0 missing one file (F), the index entry a citation uses removed — exactly
#      one line fewer — and an anchors-table row removed (G), a reader re-pointed back to the raw index (H),
#      assemble.sh with its `..` guard deleted — exactly two lines fewer — accepting the traversal (A2).
# Read-only; scratch files under mktemp -d. Exit 0 = all pass, 1 = any failure.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$PLUGIN/.." && pwd)"
ASM="$HERE/fixtures/automate-loop-split/assemble.sh"
FIXTURE="$HERE/fixtures/automate-loop-split/move-only.txt"
SKILL_IDX="loomwright/skills/automate-loop/SKILL.md"
CMD_IDX="loomwright/commands/automate.md"
RUN_IDX="loomwright/docs/result-schemas/automate-run.md"
SKILL_DIR="loomwright/skills/automate-loop"
RUN_DIR="loomwright/docs/result-schemas/automate-run"
ANCHOR_H='## Cited sub-section anchors'

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
# norm — stdin lines: backticks dropped, whitespace runs collapsed, ends trimmed.
norm() { tr -d '`' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'; }

# headings <file> — every `##`..`######` heading line outside fenced blocks, in order (verbatim).
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
      if (fence == "" && /^#{2,6} /) print
    }' "$1"
}

# drop_index_only <file> — the index without its index-only blocks.
drop_index_only() { awk '$0 == "<!-- index-only:begin -->" {s = 1; next} $0 == "<!-- index-only:end -->" {s = 0; next} !s' "$1"; }

# blocks <index> — one "<file>\t<begin line>\t<end line>" row per split block.
blocks() {
  awk '/^<!-- split:begin [^ ]+ -->$/ {f = $3; b = NR} /^<!-- split:end [^ ]+ -->$/ {print f "\t" b "\t" NR}' "$1"
}

# expected_entries <file-as-named> <split file> — the index entries a split block must hold.
expected_entries() {
  headings "$2" | awk -v f="$1" 'NR > 1 {print ""} {print; print ""; print "See [" f "](" f ")."}'
}

# physical <dir> <rel> — the physical absolute path of <dir>/<rel> (empty when the dir is missing).
physical() { local d; d="$(cd "$1/$(dirname "$2")" 2>/dev/null && pwd -P)" || return 1; echo "$d/$(basename "$2")"; }

# check_entries <index> — B for one index; one line per problem; returns 0 iff none.
check_entries() {
  local idx="$1" dir probs=0 f b e sf
  dir="$(dirname "$idx")"
  [ -n "$(blocks "$idx")" ] || { echo "    $idx: no split blocks"; return 1; }
  while IFS="$(printf '\t')" read -r f b e; do
    sf="$dir/$f"
    if [ ! -s "$sf" ]; then echo "    $f: split file missing or empty"; probs=$((probs+1)); continue; fi
    [ "$(tail -c 1 "$sf" | od -An -c | tr -d ' ')" = '\n' ] || { echo "    $f: does not end with a newline"; probs=$((probs+1)); }
    [ "$(head -1 "$sf")" = "$(headings "$sf" | head -1)" ] || { echo "    $f: does not start with its first heading"; probs=$((probs+1)); }
    expected_entries "$f" "$sf" > "$TMP/want.$$"
    awk -v b="$b" -v e="$e" 'NR > b && NR < e' "$idx" > "$TMP/have.$$"
    if [ ! -s "$TMP/want.$$" ]; then echo "    $f: holds no heading"; probs=$((probs+1))
    elif ! cmp -s "$TMP/want.$$" "$TMP/have.$$"; then
      echo "    $f: its index block is not exactly one heading + 'See [$f]($f).' entry per heading of the file, in order"
      diff "$TMP/want.$$" "$TMP/have.$$" | sed -n '1,6s/^/      /p'
      probs=$((probs+1))
    fi
  done <<EOF
$(blocks "$idx")
EOF
  [ "$probs" -eq 0 ]
}

# check_orphans <split dir> <index>… — C for one split directory; one line per problem.
check_orphans() {
  local sdir="$1" probs=0 x idx f b e p cnt; shift
  : > "$TMP/named.$$"
  for idx in "$@"; do
    while IFS="$(printf '\t')" read -r f b e; do
      [ -n "$f" ] || continue
      p="$(physical "$(dirname "$idx")" "$f")" || p=""
      case "$p" in
        "$(cd "$sdir" && pwd -P)"/*) echo "$p" >> "$TMP/named.$$" ;;
        *) echo "    ${idx#"$REPO"/}: block names $f, outside ${sdir#"$REPO"/}/"; probs=$((probs+1)) ;;
      esac
    done <<EOF
$(blocks "$idx")
EOF
  done
  for x in "$sdir"/*.md; do
    [ -f "$x" ] || continue
    [ "${x##*/}" = "SKILL.md" ] && continue
    p="$(physical "$sdir" "${x##*/}")"
    cnt="$(grep -cxF -- "$p" "$TMP/named.$$")"
    [ "$cnt" = "1" ] || { echo "    ${x#"$REPO"/}: named by $cnt split block(s) (want exactly 1)"; probs=$((probs+1)); }
  done
  [ "$probs" -eq 0 ]
}

# check_headings <index> — D: index heading sequence (index-only blocks dropped) == assembled text's.
check_headings() {
  drop_index_only "$1" > "$TMP/idx-noio.$$"
  headings "$TMP/idx-noio.$$" > "$TMP/ih.$$"
  bash "$ASM" "$1" > "$TMP/asm.$$" 2>/dev/null || { echo "    $1 does not assemble"; return 1; }
  headings "$TMP/asm.$$" > "$TMP/ah.$$"
  cmp -s "$TMP/ih.$$" "$TMP/ah.$$" && return 0
  echo "    heading sequences differ (index < > assembled):"; diff "$TMP/ih.$$" "$TMP/ah.$$" | sed -n '1,6s/^/      /p'
  return 1
}

echo "== A. each index assembles =="
for rel in "$SKILL_IDX" "$CMD_IDX" "$RUN_IDX"; do
  if bash "$ASM" "$REPO/$rel" > "$TMP/asm-${rel##*/}" 2> "$TMP/asm.err" && [ -s "$TMP/asm-${rel##*/}" ]; then
    ok "A: $rel assembles ($(wc -l < "$TMP/asm-${rel##*/}" | tr -d ' ') lines from the index + $(bash "$ASM" --files "$REPO/$rel" | wc -l | tr -d ' ') split file(s))"
  else
    no "A: $rel does not assemble: $(cat "$TMP/asm.err")"
  fi
done

echo "== A2. assemble.sh bounds .. in split paths (fail-CLOSED) =="
# A scratch plugin: P/.claude-plugin/plugin.json, an index under P/commands/, a split file under
# P/skills/, a decoy just OUTSIDE P, and an index in a tree with no plugin root at all.
T2="$TMP/a2"; P="$T2/plug"; mkdir -p "$P/.claude-plugin" "$P/commands" "$P/skills" "$T2/noplug/x"
printf '{}\n' > "$P/.claude-plugin/plugin.json"
printf '## In\n\nbody.\n' > "$P/skills/a.md"; printf '## Out\n\nescaped.\n' > "$T2/outside.md"
printf '## Out\n\nescaped.\n' > "$T2/noplug/y.md"
# a2_idx <index path> <split path> — write an index whose one block names <split path>.
a2_idx() { printf '# Idx\n\n<!-- split:begin %s -->\n<!-- split:end %s -->\n' "$2" "$2" > "$1"; }
# a2_rejects <assemble> <index> — 0 iff it exits non-zero with nothing on stdout and a reason on stderr.
a2_rejects() {
  local rc; bash "$1" "$2" > "$TMP/a2.out" 2> "$TMP/a2.err"; rc=$?
  [ "$rc" -ne 0 ] && [ ! -s "$TMP/a2.out" ] && grep -q '^assemble: ' "$TMP/a2.err"
}
a2_idx "$P/commands/ok.md" "../skills/a.md"
if bash "$ASM" "$P/commands/ok.md" > "$TMP/a2.out" 2>/dev/null && grep -qx 'body.' "$TMP/a2.out"; then
  ok "A2: a leading ../ that stays inside the plugin root assembles (../skills/a.md from commands/)"
else no "A2: a leading ../ inside the plugin root was refused — the bound is too narrow"; fi
a2_idx "$P/commands/mid.md" "../skills/../skills/a.md"
a2_rejects "$ASM" "$P/commands/mid.md" && ok "A2: a .. after a named segment (../skills/../skills/a.md) is REJECTED" \
  || no "A2: a .. after a named segment was ACCEPTED"
a2_idx "$P/commands/foo.md" "foo/../ok.md"
a2_rejects "$ASM" "$P/commands/foo.md" && ok "A2: foo/../ok.md is REJECTED" || no "A2: foo/../ok.md was ACCEPTED"
a2_idx "$P/commands/esc.md" "../../outside.md"
a2_rejects "$ASM" "$P/commands/esc.md" && ok "A2: a ../../ climb out of the plugin root is REJECTED (the target exists)" \
  || no "A2: a ../../ climb out of the plugin root was ACCEPTED"
a2_idx "$T2/noplug/x/idx.md" "../y.md"
a2_rejects "$ASM" "$T2/noplug/x/idx.md" && ok "A2: a ../ climb from an index with no plugin root above it is REJECTED" \
  || no "A2: a ../ climb with no plugin root was ACCEPTED"

echo "== B. index entries mirror each split file's headings =="
for rel in "$SKILL_IDX" "$CMD_IDX" "$RUN_IDX"; do
  if out="$(check_entries "$REPO/$rel")"; then ok "B: $rel — every split block holds one heading + See entry per heading of its file"
  else no "B: $rel index entries drifted:"; printf '%s\n' "$out"; fi
done

echo "== C. no orphan split file; every block names its surface's own split directory =="
if out="$(check_orphans "$REPO/$SKILL_DIR" "$REPO/$SKILL_IDX" "$REPO/$CMD_IDX")"; then
  ok "C: every $SKILL_DIR/*.md split file is named by exactly one SKILL.md / commands/automate.md block"
else no "C: $SKILL_DIR split files:"; printf '%s\n' "$out"; fi
if out="$(check_orphans "$REPO/$RUN_DIR" "$REPO/$RUN_IDX")"; then
  ok "C: every $RUN_DIR/*.md split file is named by exactly one automate-run.md block"
else no "C: $RUN_DIR split files:"; printf '%s\n' "$out"; fi
ncmd="$(git -C "$REPO" ls-files -- 'loomwright/commands/*.md' 2>/dev/null | wc -l | tr -d ' ')"
ndir="$(ls "$PLUGIN"/commands/*.md 2>/dev/null | wc -l | tr -d ' ')"
[ "$ncmd" = "$ndir" ] && [ "$ndir" -gt 0 ] && ok "C: commands/ holds only tracked command files ($ndir) — the split added none (C4)" \
  || no "C: commands/ has $ndir *.md on disk vs $ncmd tracked — a split file under commands/ would count as a command"

echo "== D. every pre-split heading is still at the old path (AC1) =="
for rel in "$SKILL_IDX" "$CMD_IDX" "$RUN_IDX"; do
  if out="$(check_headings "$REPO/$rel")"; then ok "D: $rel — index heading sequence == assembled heading sequence ($(wc -l < "$TMP/ih.$$" | tr -d ' ') headings)"
  else no "D: $rel:"; printf '%s\n' "$out"; fi
done
fm="$(awk 'NR == 1 && $0 != "---" {exit} NR > 1 && $0 == "---" {exit} NR > 1 {print}' "$REPO/$SKILL_IDX")"
case "$fm" in *'name: automate-loop'*'version: "'[0-9]*.[0-9]*.[0-9]*'"'*) ok "D: SKILL.md keeps its frontmatter (name automate-loop, a semver version)" ;;
  *) no "D: SKILL.md frontmatter lost its name or version" ;; esac

echo "== E. move-only: the assembled text is the pre-split original, byte for byte (AC2) =="
# assembled_for_proof <index rel> <out> — the assembly, frontmatter exemptions substituted back.
assembled_for_proof() {
  local rel="$1" out="$2" key orig split
  bash "$ASM" "$REPO/$rel" "$out" 2>/dev/null || return 1
  while IFS="$(printf '\t')" read -r key orig split; do
    [ -n "$key" ] || continue
    awk -v k="$key" -v o="$orig" -v s="$split" '
      NR == 1 && $0 == "---" {fm = 1; print; next}
      fm && $0 == "---" {fm = 0}
      fm && $0 == k ": \"" s "\"" {print k ": \"" o "\""; next}
      {print}' "$out" > "$out.x" && mv "$out.x" "$out"
  done <<EOF
$(awk -F '\t' -v r="$rel" '$1 == "frontmatter" && $2 == r {print $3 "\t" $4 "\t" $5}' "$FIXTURE")
EOF
}
# proof_matches <index rel> <assembled file> — 0 iff sha256 / bytes / lines equal the fixture row.
proof_matches() {
  local want got
  want="$(awk -F '\t' -v r="$1" '$1 == "original" && $2 == r {print $3 " " $4 " " $5}' "$FIXTURE")"
  got="$(sha256 < "$2") $(wc -c < "$2" | tr -d ' ') $(wc -l < "$2" | tr -d ' ')"
  [ -n "$want" ] && [ "$want" = "$got" ]
}
# split_hash <file> <rel> — the split-time hash: an index (SKILL / command / AUTOMATE_RUN) is hashed
# with its index-only blocks dropped (assemble.sh drops them too, so index-only prose may change
# without retiring the proof); a split file is hashed raw.
split_hash() {
  case "$2" in
    "$SKILL_IDX"|"$CMD_IDX"|"$RUN_IDX") drop_index_only "$1" | sha256 ;;
    *) sha256 < "$1" ;;
  esac
}
# edited_since_split <root> — " <rel>" per split-time surface under <root> whose split_hash differs.
edited_since_split() {
  local p want out=""
  while IFS="$(printf '\t')" read -r p want; do
    [ -n "$p" ] || continue
    if [ ! -f "$1/$p" ]; then out="$out $p(gone)"; continue; fi
    [ "$(split_hash "$1/$p" "$p")" = "$want" ] || out="$out $p"
  done <<EOF
$(awk -F '\t' '$1 == "split-time" {print $2 "\t" $3}' "$FIXTURE")
EOF
  printf '%s' "$out"
}
if ! printf 'x' | sha256 >/dev/null 2>&1; then
  no "E: no sha256 tool (shasum / sha256sum) — the move-only proof cannot run (never read as clean)"
elif [ ! -s "$FIXTURE" ]; then
  no "E: fixture missing: $FIXTURE"
else
  edited="$(edited_since_split "$REPO")"
  nsplit="$(awk -F '\t' '$1 == "split-time"' "$FIXTURE" | wc -l | tr -d ' ')"
  [ "$nsplit" -gt 0 ] || no "E: the fixture records no split-time file"
  if [ -n "$edited" ]; then
    echo "  SKIP: E move-only proof — split surface(s) edited since the parallel-automate/22 split:$edited (it proves the split commit only)"
  else
    for rel in "$SKILL_IDX" "$CMD_IDX" "$RUN_IDX"; do
      if assembled_for_proof "$rel" "$TMP/proof-${rel##*/}" && proof_matches "$rel" "$TMP/proof-${rel##*/}"; then
        ok "E: assembled $rel == its pre-split original (sha256, size and line count)"
      else
        no "E: assembled $rel differs from its pre-split original"
        if git -C "$REPO" cat-file -e "da2fac5d4f54bea55fc91700ebe5729755f587ef:$rel" 2>/dev/null; then
          git -C "$REPO" show "da2fac5d4f54bea55fc91700ebe5729755f587ef:$rel" | diff - "$TMP/proof-${rel##*/}" | sed -n '1,8s/^/      /p'
        fi
      fi
    done
    # The exempted frontmatter delta is a minor bump (AC1): same major, minor + 1, patch 0.
    vrow="$(awk -F '\t' -v r="$SKILL_IDX" '$1 == "frontmatter" && $2 == r && $3 == "version" {print $4 " " $5}' "$FIXTURE")"
    set -- $vrow
    if [ "$#" -eq 2 ] && [ "$(echo "$1" | awk -F. '{print $1 "." $2 + 1 ".0"}')" = "$2" ]; then
      ok "E: the only exempted delta is SKILL.md's version $1 -> $2 (a minor bump) + its lastUpdated"
    else
      no "E: SKILL.md version exemption is not a minor bump: '$vrow'"
    fi
    # When the base commit is reachable, the fixture's original hashes are re-derived from it.
    if git -C "$REPO" cat-file -e "da2fac5d4f54bea55fc91700ebe5729755f587ef^{commit}" 2>/dev/null; then
      bad=""
      for rel in "$SKILL_IDX" "$CMD_IDX" "$RUN_IDX"; do
        git -C "$REPO" show "da2fac5d4f54bea55fc91700ebe5729755f587ef:$rel" > "$TMP/base-orig"
        proof_matches "$rel" "$TMP/base-orig" || bad="$bad $rel"
      done
      [ -z "$bad" ] && ok "E: the fixture's original rows equal git show da2fac5 for all three surfaces" || no "E: fixture original row(s) differ from da2fac5:$bad"
    else
      echo "  note: base da2fac5 not in this clone — the fixture's original rows are trusted as committed"
    fi
  fi
fi

echo "== F. commands/automate.md Step 0 reads every skill split file (AC5) =="
# step0_names <command file> — the backticked *.md names (SKILL.md excepted) in Step 0's index-only block.
step0_names() {
  awk '/^### Step 0/ {s = 1; next} s && /^### / {exit} s && $0 == "<!-- index-only:begin -->" {io = 1; next} s && $0 == "<!-- index-only:end -->" {io = 0} s && io' "$1" \
    | grep -oE '`[A-Za-z0-9._-]+\.md`' | tr -d '`' | grep -vx 'SKILL.md'
}
want_step0() { { bash "$ASM" --files "$REPO/$SKILL_IDX"; bash "$ASM" --files "$REPO/$CMD_IDX"; } | sed 's|.*/||'; }
want_step0 > "$TMP/step0-want"
check_step0() { step0_names "$1" > "$TMP/step0-have"; [ -s "$TMP/step0-want" ] && cmp -s "$TMP/step0-want" "$TMP/step0-have"; }
if check_step0 "$REPO/$CMD_IDX"; then ok "F: Step 0 names all $(wc -l < "$TMP/step0-want" | tr -d ' ') skill split files, in documented order"
else no "F: Step 0 names [$(tr '\n' ' ' < "$TMP/step0-have")] — want [$(tr '\n' ' ' < "$TMP/step0-want")]"; fi
grep -qF -- '${CLAUDE_PLUGIN_ROOT}/skills/automate-loop/' < <(awk '/^### Step 0/ {s = 1; next} s && /^### / {exit} s' "$REPO/$CMD_IDX") \
  && ok "F: Step 0 resolves them under the plugin install root's skills/automate-loop/" || no "F: Step 0 does not name the runtime skill directory"

echo "== G. every citation of a split surface resolves through its index (AC3) =="
# candidates <index> — one "<line>\t<kind>\t<file>\t<normalized text>" row per anchor target
# (<file> is "-" when none: tab is IFS whitespace, so an empty field would collapse on read):
#   h = a heading outside index-only blocks (<file> = its split block's file, else "-");
#   b = a line-leading bold label in the index's own text (outside blocks and fences);
#   r = a row of the index-only `## Cited sub-section anchors` table (<file> = its link).
candidates() {
  awk -v A="$ANCHOR_H" '
    function strip(s) { gsub(/`/, "", s); gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
    /^<!-- split:begin [^ ]+ -->$/ {blk = $3; next}
    /^<!-- split:end [^ ]+ -->$/ {blk = ""; next}
    $0 == "<!-- index-only:begin -->" {io = 1; next}
    $0 == "<!-- index-only:end -->" {io = 0; ia = 0; next}
    io && $0 == A {ia = 1; next}
    io && ia && /^\| / {
      if (match($0, /\| \[[^]]+\]\([^)]+\) \|$/)) {
        cell = substr($0, 3, RSTART - 3); lk = substr($0, RSTART + 3); sub(/\].*$/, "", lk)
        tg = substr($0, RSTART); sub(/^[^(]*\(/, "", tg); sub(/\).*$/, "", tg)
        if (cell != "Anchor") print NR "\tr\t" (lk == tg ? lk : lk "|MISMATCH|" tg) "\t" strip(cell)
      }
      next
    }
    io {next}
    /^[ ]{0,3}(```+|~~~+)/ {fence = !fence; next}
    fence {next}
    /^#{2,6} / {t = $0; sub(/^#+ /, "", t); print NR "\th\t" (blk == "" ? "-" : blk) "\t" strip(t); next}
    blk == "" && /^[ \t]*([-*]|[0-9]+\.)?[ \t]*\*\*/ {
      t = $0; sub(/^[^*]*\*\*/, "", t); sub(/\*\*.*$/, "", t); print NR "\tb\t-\t" strip(t)
    }' "$1"
}
# file_holds <file> <anchor> — 0 iff the file has a heading or line-leading bold label matching it.
file_holds() {
  local x
  while IFS="$(printf '\t')" read -r _ k _ x; do
    [ "$k" = "r" ] && continue
    matches "$x" "$2" && return 0
  done <<EOF
$(candidates "$1")
EOF
  return 1
}
# matches <text> <anchor> — 0 iff text (or text minus a leading "§N — ") equals the anchor or starts
# with it at a word boundary. A numeric anchor "§N" matches only a "§N " prefix.
matches() {
  local t="$1" a="$2" u
  case "$a" in "§"*) case "$t " in "$a "*) return 0 ;; esac; return 1 ;; esac
  u="$(printf '%s' "$t" | sed -E 's/^§[0-9]+(\.[0-9]+)? — //')"
  case "$t" in "$a"|"$a "*) return 0 ;; esac
  case "$u" in "$a"|"$a "*) return 0 ;; esac
  return 1
}
# cited <surface> — one "<normalized anchor>\t<citing file>" row per citation of that surface.
SK_PFX='automate-loop(/SKILL\.md|/SKILL| SKILL)?(`|'"'"'s|`'"'"'s)?'
QUOTED='"[A-Za-z`-][^"]*"'
cited() {
  local surface="$1" pre re1 re2
  case "$surface" in
    skill) pre='automate-loop'
           re1="${SK_PFX} ?§ ?([0-9]+(\\.[0-9]+)?( ${QUOTED})?|${QUOTED})"
           re2="automate-loop/SKILL\\.md\`? ${QUOTED}" ;;
    cmd)   pre='commands/automate\.md'
           re1="commands/automate\\.md(\`|'s)? ?§ ?${QUOTED}"
           re2="commands/automate\\.md\`? ${QUOTED}" ;;
    run)   pre='automate-run\.md|AUTOMATE_RUN'
           re1="(automate-run\\.md\`?|§ ?\"?AUTOMATE_RUN\"?\`?) ?§ ?${QUOTED}"
           re2="(automate-run\\.md\`?|§ ?\"?AUTOMATE_RUN\"?\`?) ${QUOTED}" ;;
  esac
  git -C "$REPO" grep -lE "$pre" -- . ':!CHANGELOG.md' ':!loomwright/scripts/test-automate-loop-split.sh' 2>/dev/null \
  | while IFS= read -r f; do
      awk '
        function open_quote(s,   t) { t = s; if (!sub(/.*(§ ?([0-9]+(\.[0-9]+)? )?|SKILL\.md`? |automate\.md`? |AUTOMATE_RUN"?`? |automate-run\.md`? )"/, "", t)) return 0; return (index(t, "\"") == 0) }
        {
          buf = $0; k = 0
          while (open_quote(buf) && k < 2 && (getline nxt) > 0) {
            sub(/^[ \t]*(#|\/\/|\*|--|>)?[ \t]*/, "", nxt); buf = buf " " nxt; k++
          }
          print buf
        }' "$REPO/$f" \
      | grep -oE "($re1)|($re2)" \
      | while IFS= read -r m; do
          case "$surface" in
            skill)
              rest="$(printf '%s' "$m" | sed -E 's/^automate-loop(\/SKILL\.md|\/SKILL| SKILL)?(`|'"'"'s|`'"'"'s)? ?//')"
              case "$rest" in "§"*) rest="$(printf '%s' "$rest" | sed -E 's/^§ ?//')" ;; esac
              num="$(printf '%s' "$rest" | grep -oE '^[0-9]+(\.[0-9]+)?' || true)"
              [ -n "$num" ] && printf '§%s\t%s\n' "$num" "$f"
              q="$(printf '%s' "$rest" | grep -oE '"[^"]+"$' || true)"
              [ -n "$q" ] && printf '%s\n' "${q:1:${#q}-2}" | norm | awk -v F="$f" 'NF {print $0 "\t" F}' ;;
            *)
              q="$(printf '%s' "$m" | grep -oE '"[^"]+"$' || true)"
              [ -n "$q" ] && printf '%s\n' "${q:1:${#q}-2}" | norm | awk -v F="$f" 'NF {print $0 "\t" F}' ;;
          esac
        done
    done | sort -u
}
# resolve <index> <cites file> <used-lines out> — one line per unresolved citation; returns 0 iff
# none. Appends "<index line>\t<anchor>" for each citation that resolves through exactly ONE line.
resolve() {
  local idx="$1" cites="$2" used="$3" probs=0 a src ln k f x hits hitln okf dir
  dir="$(dirname "$idx")"
  candidates "$idx" > "$TMP/cand.$$"
  while IFS="$(printf '\t')" read -r a src; do
    [ -n "$a" ] || continue
    hits=0; hitln=""; okf=1
    while IFS="$(printf '\t')" read -r ln k f x; do
      matches "$x" "$a" || continue
      case "$a" in "§"*) [ "$k" = "h" ] || continue ;; esac
      case "$f" in *"|MISMATCH|"*) okf=0; continue ;; esac
      if [ "$f" != "-" ] && ! file_holds "$dir/$f" "$a"; then okf=0; continue; fi
      hits=$((hits+1)); hitln="$ln"
    done < "$TMP/cand.$$"
    if [ "$hits" -eq 0 ]; then
      echo "    '$a' (cited in $src) resolves to no heading, bold label or anchors row in ${idx#"$REPO"/}$([ "$okf" = 0 ] && echo ' (a match named a file that does not hold it)')"
      probs=$((probs+1))
    elif [ "$hits" -eq 1 ]; then printf '%s\t%s\n' "$hitln" "$a" >> "$used"
    fi
  done < "$cites"
  [ "$probs" -eq 0 ]
}
if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  for s in skill cmd run; do
    case "$s" in skill) idx="$REPO/$SKILL_IDX" ;; cmd) idx="$REPO/$CMD_IDX" ;; run) idx="$REPO/$RUN_IDX" ;; esac
    cited "$s" > "$TMP/cites-$s"
    n="$(wc -l < "$TMP/cites-$s" | tr -d ' ')"
    : > "$TMP/used-$s"
    if [ "$s" = "skill" ] && [ "$n" -eq 0 ]; then no "G: found no citation of automate-loop/SKILL.md in the tracked tree — the scan is broken"; continue; fi
    if out="$(resolve "$idx" "$TMP/cites-$s" "$TMP/used-$s")"; then
      ok "G: all $n distinct (anchor, file) citation(s) of the $s surface resolve through ${idx#"$REPO"/}"
    else no "G: $s surface citations that do not resolve:"; printf '%s\n' "$out"; fi
  done
else
  no "G: $REPO is not a git work tree — cannot list tracked citations (never read as clean)"
fi

echo "== H. the tests that read moved text read the assembly (C1/C2) =="
READERS="test-automate-dismissed.sh test-automate-helpers.sh test-automate-trail.sh test-non-interactive-gates-seam.sh test-run-lock.sh test-classify-risk.sh"
# wiring <reader file> — one line per wiring defect; returns 0 iff none.
wiring() {
  local f="$1" probs=0 l
  grep -qF 'fixtures/automate-loop-split/assemble.sh' "$f" || { echo "    ${f##*/}: never calls assemble.sh"; probs=$((probs+1)); }
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    case "$l" in *assemble.sh*|*'bash "$ASM"'*) ;; *) echo "    ${f##*/}: raw index read: ${l:0:110}"; probs=$((probs+1)) ;; esac
  done <<EOF
$(grep -E '\$[A-Za-z_{][^" ]*/(automate-loop/SKILL|automate-run)\.md"' "$f" | grep -vE '^[[:space:]]*#' || true)
EOF
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    case "$l" in *'result-schemas/automate-run/*.md'*) ;; *) echo "    ${f##*/}: result-schemas/*.md glob without automate-run/*.md: ${l:0:110}"; probs=$((probs+1)) ;; esac
  done <<EOF
$(grep -F 'result-schemas/*.md' "$f" | grep -vE '^[[:space:]]*#' | grep -vF '(+ result-schemas/*.md)' || true)
EOF
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    echo "    ${f##*/}: multi-file absence scan of the raw command body: ${l:0:110}"; probs=$((probs+1))
  done <<EOF
$(grep -F 'commands/automate.md"' "$f" | grep -E 'grep -n|for p in' || true)
EOF
  [ "$probs" -eq 0 ]
}
for r in $READERS; do
  if out="$(wiring "$HERE/$r")"; then ok "H: $r reads the assembled skill / AUTOMATE_RUN text"
  else no "H: $r wiring:"; printf '%s\n' "$out"; fi
done
al="$(sed -nE 's/^AL="([^"]+)"$/\1/p' "$HERE/test-rules-gate-seams.sh")"
gate_file="$(awk '/^<!-- split:begin [^ ]+ -->$/ {f = $3} /^<!-- split:end / {f = ""} f != "" && /^## §10 / {print f; exit}' "$REPO/$SKILL_IDX")"
if [ -n "$gate_file" ] && [ "$al" = "$SKILL_DIR/$gate_file" ]; then
  ok "H: test-rules-gate-seams.sh AL ($al) is the split file the index names for ## §10"
else
  no "H: test-rules-gate-seams.sh AL='$al' but the index names '${gate_file:-nothing}' for ## §10"
fi

echo "== M. mutation controls =="
# M1 — B: the first See line of the SKILL index removed.
M1="$TMP/m1/SKILL.md"; mkdir -p "$TMP/m1"; cp "$REPO/$SKILL_DIR"/*.md "$TMP/m1/"
awk '!d && /^See \[/ {d = 1; next} {print}' "$REPO/$SKILL_IDX" > "$M1"
if [ -s "$M1" ] && ! cmp -s "$M1" "$REPO/$SKILL_IDX"; then
  check_entries "$M1" >/dev/null && no "MUTATION CONTROL: an index entry with its See line removed was ACCEPTED (B)" \
    || ok "MUTATION CONTROL: an index entry with its See line removed is REJECTED (B)"
else no "could not build the See-line-removed mutant — B control inconclusive"; fi
# M2 — C: an extra, unreferenced split file, in a mirror of the skill + command dirs (the mirror
# itself must pass first, so the control discriminates the orphan and nothing else).
M2="$TMP/m2/loomwright"; mkdir -p "$M2/skills/automate-loop" "$M2/commands"
cp "$REPO/$SKILL_DIR"/*.md "$M2/skills/automate-loop/"; cp "$REPO/$CMD_IDX" "$M2/commands/automate.md"
if check_orphans "$M2/skills/automate-loop" "$M2/skills/automate-loop/SKILL.md" "$M2/commands/automate.md" >/dev/null; then
  printf '## §99 — Orphan\n\nunreferenced.\n' > "$M2/skills/automate-loop/orphan.md"
  if [ -s "$M2/skills/automate-loop/orphan.md" ] && [ "$(ls "$M2/skills/automate-loop" | wc -l | tr -d ' ')" -gt "$(ls "$REPO/$SKILL_DIR" | wc -l | tr -d ' ')" ]; then
    check_orphans "$M2/skills/automate-loop" "$M2/skills/automate-loop/SKILL.md" "$M2/commands/automate.md" >/dev/null \
      && no "MUTATION CONTROL: an unreferenced split file was ACCEPTED (C)" || ok "MUTATION CONTROL: an unreferenced split file is REJECTED (C)"
  else no "could not build the orphan mutant — C control inconclusive"; fi
else no "the unmutated mirror fails C — the orphan control is inconclusive"; fi
# M3 — E: one split file with one byte changed (the proof core, run directly on the mutant tree).
M3="$TMP/m3"; mkdir -p "$M3"; cp "$REPO/$SKILL_DIR"/*.md "$M3/"
victim="$(bash "$ASM" --files "$REPO/$SKILL_IDX" | head -1 | sed 's|.*/||')"
if [ -n "$victim" ]; then sed '1s/^## /## X/' "$REPO/$SKILL_DIR/$victim" > "$M3/$victim"; fi
if [ -n "$victim" ] && [ -s "$M3/$victim" ] && ! cmp -s "$M3/$victim" "$REPO/$SKILL_DIR/$victim" && printf 'x' | sha256 >/dev/null 2>&1; then
  bash "$ASM" "$M3/SKILL.md" "$TMP/m3-asm" 2>/dev/null
  awk -F '\t' -v r="$SKILL_IDX" '$1 == "frontmatter" && $2 == r {print $3 "\t" $4 "\t" $5}' "$FIXTURE" > "$TMP/m3-fm"
  while IFS="$(printf '\t')" read -r key orig split; do
    awk -v k="$key" -v o="$orig" -v s="$split" 'NR == 1 && $0 == "---" {fm = 1; print; next} fm && $0 == "---" {fm = 0} fm && $0 == k ": \"" s "\"" {print k ": \"" o "\""; next} {print}' "$TMP/m3-asm" > "$TMP/m3-x" && mv "$TMP/m3-x" "$TMP/m3-asm"
  done < "$TMP/m3-fm"
  proof_matches "$SKILL_IDX" "$TMP/m3-asm" && no "MUTATION CONTROL: a split file with one changed byte passed the move-only proof (E)" \
    || ok "MUTATION CONTROL: a split file with one changed byte fails the move-only proof (E)"
else no "could not build the changed-byte mutant — E control inconclusive"; fi
# M9 — E gating: in a mirror of every split-time surface, an index-only edit to the SKILL index keeps
# the proof RUNNING (no surface reads as edited), while an edit outside index-only blocks retires it.
M9="$TMP/m9"
awk -F '\t' '$1 == "split-time" {print $2}' "$FIXTURE" > "$TMP/m9-paths"
while IFS= read -r p; do
  [ -n "$p" ] && [ -f "$REPO/$p" ] || continue
  mkdir -p "$M9/$(dirname "$p")"; cp "$REPO/$p" "$M9/$p"
done < "$TMP/m9-paths"
if [ -n "$(edited_since_split "$REPO")" ]; then
  echo "  note: E is skipped on this tree — the M9 gating control has no unedited baseline to mutate"
elif [ -n "$(edited_since_split "$M9")" ]; then
  no "the unmutated M9 mirror reads as edited — E gating control inconclusive"
else
  awk '{print} !d && $0 == "<!-- index-only:end -->" {print "<!-- index-only:begin -->"; print "M9 index-only note."; print "<!-- index-only:end -->"; d = 1}' \
    "$REPO/$SKILL_IDX" > "$M9/$SKILL_IDX"
  if ! cmp -s "$M9/$SKILL_IDX" "$REPO/$SKILL_IDX"; then
    [ -z "$(edited_since_split "$M9")" ] && ok "MUTATION CONTROL: an index-only edit to the SKILL index keeps the move-only proof RUNNING (E)" \
      || no "MUTATION CONTROL: an index-only edit to the SKILL index retired the move-only proof (E)"
  else no "could not build the index-only mutant — E gating control inconclusive"; fi
  awk '!d && $0 == "<!-- index-only:end -->" {print; print "M9 text outside index-only."; d = 1; next} {print}' \
    "$REPO/$SKILL_IDX" > "$M9/$SKILL_IDX"
  if ! cmp -s "$M9/$SKILL_IDX" "$REPO/$SKILL_IDX"; then
    case "$(edited_since_split "$M9")" in *" $SKILL_IDX"*) ok "MUTATION CONTROL: an edit outside index-only blocks still retires the move-only proof (E)" ;;
      *) no "MUTATION CONTROL: an edit outside index-only blocks did NOT retire the move-only proof (E)" ;; esac
  else no "could not build the outside-index-only mutant — E gating control inconclusive"; fi
fi
# M4 — F: Step 0 with one split file name dropped.
M4="$TMP/m4-automate.md"; drop="$(sed -n '2p' "$TMP/step0-want")"
awk -v d="\`$drop\`, " '/^### Step 0/ {s = 1} s && !done && index($0, d) {sub(d, ""); done = 1} {print}' "$REPO/$CMD_IDX" > "$M4"
if [ -n "$drop" ] && [ -s "$M4" ] && ! cmp -s "$M4" "$REPO/$CMD_IDX"; then
  check_step0 "$M4" && no "MUTATION CONTROL: Step 0 missing $drop was ACCEPTED (F)" || ok "MUTATION CONTROL: Step 0 missing $drop is REJECTED (F)"
else no "could not build the Step-0 mutant — F control inconclusive"; fi
# M5 — G: the index line a citation resolves through (and only it) removed — exactly one line fewer.
if [ -s "$TMP/cites-skill" ] && [ -s "$TMP/used-skill" ]; then
  pick="$(awk -F '\t' 'NR == FNR {if ($2 != "-") inblk[$1] = 1; next} ($1 in inblk) {print; exit}' \
          <(candidates "$REPO/$SKILL_IDX" | awk -F '\t' '$2 == "h" || $2 == "r" {print $1 "\t" $3}') "$TMP/used-skill")"
  pln="$(printf '%s' "$pick" | cut -f1)"; pan="$(printf '%s' "$pick" | cut -f2)"
  M5="$TMP/m5/SKILL.md"; mkdir -p "$TMP/m5"; cp "$REPO/$SKILL_DIR"/*.md "$TMP/m5/"
  awk -v n="$pln" 'NR != n' "$REPO/$SKILL_IDX" > "$M5"
  if [ -n "$pln" ] && [ -s "$M5" ] && ! cmp -s "$M5" "$REPO/$SKILL_IDX" \
     && [ "$(wc -l < "$M5" | tr -d ' ')" -eq $(( $(wc -l < "$REPO/$SKILL_IDX" | tr -d ' ') - 1 )) ]; then
    resolve "$M5" "$TMP/cites-skill" /dev/null >/dev/null && no "MUTATION CONTROL: the index entry citation '$pan' uses was removed and the citations still RESOLVED (G)" \
      || ok "MUTATION CONTROL: removing the one index line citation '$pan' uses (line $pln) is REJECTED (G)"
  else no "could not build the entry-removed mutant (line '${pln:-none}') — G control inconclusive"; fi
  # M6 — G: the anchors-table row removed.
  rln="$(candidates "$REPO/$SKILL_IDX" | awk -F '\t' '$2 == "r" {print $1; exit}')"
  M6="$TMP/m5/SKILL-m6.md"; awk -v n="$rln" 'NR != n' "$REPO/$SKILL_IDX" > "$M6"
  if [ -n "$rln" ] && [ -s "$M6" ] && ! cmp -s "$M6" "$REPO/$SKILL_IDX"; then
    cp "$M6" "$TMP/m5/SKILL.md"
    resolve "$TMP/m5/SKILL.md" "$TMP/cites-skill" /dev/null >/dev/null && no "MUTATION CONTROL: an anchors table with its row removed was ACCEPTED (G)" \
      || ok "MUTATION CONTROL: an anchors table with its row removed is REJECTED (G)"
  else no "could not build the anchors-row mutant — G control inconclusive"; fi
else no "G produced no citations — the G mutation controls are inconclusive"; fi
# M7 — H: a reader re-pointed back to the raw SKILL index.
M7="$TMP/m7-test-run-lock.sh"
awk '!d && index($0, "assemble.sh") && index($0, "skills/automate-loop/SKILL.md") {print "AL_SK=\"$PLUGIN_ROOT/skills/automate-loop/SKILL.md\""; d = 1; next} {print}' "$HERE/test-run-lock.sh" \
  | sed 's|fixtures/automate-loop-split/assemble\.sh|fixtures/automate-loop-split/removed.sh|g' > "$M7"
if [ -s "$M7" ] && ! cmp -s "$M7" "$HERE/test-run-lock.sh" && bash -n "$M7" 2>/dev/null; then
  wiring "$M7" >/dev/null && no "MUTATION CONTROL: a reader reading the raw SKILL index was ACCEPTED (H)" \
    || ok "MUTATION CONTROL: a reader reading the raw SKILL index is REJECTED (H)"
else no "could not build the raw-reader mutant — H control inconclusive"; fi
# M8 — A2: assemble.sh with its .. guard (after-segment reject + plugin-root bound) deleted must
# ACCEPT the escape and the mid-path cases, so A2's rejections are the guard's doing.
M8="$TMP/m8-assemble.sh"
grep -vF 'fail("a .. segment after a named segment' "$ASM" | grep -vF 'fail("split path climbs out of the plugin root' > "$M8"
if [ -s "$M8" ] && ! cmp -s "$M8" "$ASM" && bash -n "$M8" 2>/dev/null \
   && [ "$(wc -l < "$M8" | tr -d ' ')" -eq $(( $(wc -l < "$ASM" | tr -d ' ') - 2 )) ]; then
  if a2_rejects "$M8" "$P/commands/esc.md" || a2_rejects "$M8" "$P/commands/mid.md"; then
    no "MUTATION CONTROL: with the .. guard removed a traversal path is STILL rejected — A2 does not discriminate the guard"
  else ok "MUTATION CONTROL: with the .. guard removed the traversal paths assemble — A2's rejections are the guard's (A2)"; fi
else no "could not build the guard-removed assemble.sh mutant — A2 control inconclusive"; fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
