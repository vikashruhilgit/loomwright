# ---- base ----
# load_base — reads <gitdir>/meta-base: line 1 the agreed-state tree, line 2 `branch <name>` (the
# branch it was recorded against; see the header's BRANCH BINDING). Sets HAVE_BASE / BASE_TREE /
# BASE_LEGACY, and BASE_REFUSAL (non-empty = refuse the sync, nothing changed) when the base is
# bound to ANOTHER branch, is unreadable, or is in no recognised format. The branch check runs
# BEFORE the object check, so a mismatched base never degrades to the no-base derivation.
HAVE_BASE=0; BASE_TREE=""; BASE_LEGACY=0; BASE_REFUSAL=""
load_base() {
  local l1="" l2="" l3="" nl bb=""
  HAVE_BASE=0; BASE_TREE=""; BASE_LEGACY=0; BASE_REFUSAL=""
  [ -f "$META_BASE" ] || return 0
  if [ ! -r "$META_BASE" ]; then
    BASE_REFUSAL="base_branch_mismatch — meta-base $META_BASE is unreadable, so the branch it was recorded against is unknown; nothing was changed (no file written, no ref moved, meta-base untouched). Fix its permissions by hand."
    return 0
  fi
  { IFS= read -r l1; IFS= read -r l2; IFS= read -r l3; } < "$META_BASE"
  nl="$(awk 'END { print NR }' "$META_BASE")"
  BASE_TREE="$(printf '%s' "$l1" | tr -d ' \t\r')"
  l2="${l2%$'\r'}"
  case "$l2" in
    "") BASE_LEGACY=1 ;;
    "branch "?*) bb="${l2#branch }" ;;
    *) nl=99 ;;
  esac
  if [ "$nl" -gt 2 ] || [ -n "$l3" ] || { [ -z "$BASE_TREE" ] && [ -n "$bb" ]; }; then
    BASE_REFUSAL="base_branch_mismatch — meta-base $META_BASE is not in a recognised format (line 1 a tree, line 2 'branch <name>'), so the branch it was recorded against is unknown; nothing was changed (no file written, no ref moved, meta-base untouched). Repair or remove it by hand."
    BASE_TREE=""; BASE_LEGACY=0
    return 0
  fi
  if [ -n "$bb" ] && [ "$bb" != "$BRANCH" ]; then
    BASE_REFUSAL="base_branch_mismatch — meta-base was recorded against branch '$bb' but this sync targets '$BRANCH'; nothing was changed (no file written, no ref moved, meta-base untouched). Planning '$BRANCH' against another branch's base would delete local or branch files '$BRANCH' never removed. Sync '$bb' with --branch '$bb' (plus --allow-branch-mismatch when the mode line names another branch), or remove $META_BASE by hand to treat '$BRANCH' as never synced (the history-aware first-sync derivation)."
    BASE_TREE=""; return 0
  fi
  if [ -n "$BASE_TREE" ] && g cat-file -e "$BASE_TREE^{tree}" 2>/dev/null; then
    HAVE_BASE=1
  else
    warn "meta-base '$BASE_TREE' is missing from the object store — falling back to the no-base (history-aware) derivation"
    BASE_LEGACY=0
    BASE_TREE=""
  fi
}

# ---- plan ----
# compute_plan <write-local-objects:0|1> — writes $WORK/plan: outcome<TAB>path<TAB>L<TAB>R<TAB>newbase<TAB>sel
# ("-" = absent). Outcomes: SAME TAKE_R TAKE_L UNION CONFLICT. newbase = the agreed-state entry a
# PUSH records for the path (pull records R's tree instead).
compute_plan() {
  local L="$WORK/L.tsv" Rf="$WORK/R.tsv" Bf="$WORK/B.tsv" Hf="$WORK/H.tsv" Sf="$WORK/S.lst" hs=0
  list_local "$L" "$1" || { warn "could not hash the local managed files"; return 1; }
  list_tree "$R" "$Rf" || { warn "could not list the remote tree $R"; return 1; }
  : > "$Bf" && : > "$Hf" && : > "$Sf" || return 1
  load_base
  [ -z "$BASE_REFUSAL" ] || return 2
  if [ "$HAVE_BASE" = "1" ]; then
    list_tree "$BASE_TREE" "$Bf" || { warn "could not list the meta-base tree $BASE_TREE"; return 1; }
    if [ "$BASE_LEGACY" = "1" ]; then
      # A legacy base (no branch line) is adopted for $BRANCH only when EVERY entry it holds is a
      # (path, blob) $BRANCH's own history held — i.e. it provably was not taken from another branch.
      local stray
      list_history "$R" "$Hf" || { warn "could not read the history of $R"; return 1; }
      stray="$(awk -F'\t' -v HF="$Hf" 'FILENAME == HF { h[$0] = 1; next } !($0 in h) { n++ } END { print n + 0 }' "$Hf" "$Bf")" \
        || { warn "could not check the legacy meta-base against the history of $R"; return 1; }
      if [ "$stray" != "0" ]; then
        BASE_REFUSAL="base_branch_mismatch — the legacy meta-base $META_BASE records no branch and holds $stray entr(y/ies) '$BRANCH''s history never held, so it may have been taken from another branch; nothing was changed (no file written, no ref moved, meta-base untouched). Sync the branch it came from with --branch <that branch>, or remove $META_BASE by hand to treat '$BRANCH' as never synced (the history-aware first-sync derivation)."
        return 2
      fi
      : > "$Hf" || return 1
    fi
  else
    list_history "$R" "$Hf" || { warn "could not read the history of $R"; return 1; }
  fi
  if [ -n "$PATHS_FROM" ]; then
    hs=1
    sed -e 's/\r$//' -e 's|^\./||' "$PATHS_FROM" | awk 'NF && $0 !~ /^#/' > "$Sf" \
      || { warn "could not read --paths-from '$PATHS_FROM'"; return 1; }
  fi
  awk -F'\t' -v OFS='\t' -v hb="$HAVE_BASE" -v hs="$hs" -v ledger="$LEDGER_PATH" \
      -v LF="$L" -v RF="$Rf" -v BF="$Bf" -v HF="$Hf" -v SF="$Sf" '
    # is_union — the UNION-PATH PREDICATE (header: 3-WAY RULE): the paths whose both-changed outcome
    # is a union instead of a conflict. The twin set is deliberately NOT here (a chain fork refuses
    # the twin set — see twin_gate); every .md is not here either (per-file conflict).
    function is_union(p) {
      if (p == ledger) return 1
      if (p == ".supervisor/eval/results.jsonl" || p == ".supervisor/eval/brain-baseline.jsonl") return 1
      if (p ~ /^\.supervisor\/automate\/[^\/]+\.dismissed-decisions$/) return 1
      return 0
    }
    FILENAME == LF { Lb[$1] = $2; U[$1] = 1; next }
    FILENAME == RF { Rb[$1] = $2; U[$1] = 1; next }
    FILENAME == BF { Bb[$1] = $2; U[$1] = 1; next }
    FILENAME == HF { H[$1 SUBSEP $2] = 1; HP[$1] = 1; next }
    FILENAME == SF { S[$0] = 1; next }
    END {
      for (p in U) {
        l = (p in Lb) ? Lb[p] : "-"
        r = (p in Rb) ? Rb[p] : "-"
        sel = (hs == 0 || (p in S)) ? 1 : 0
        if (hb == 1) {
          b = (p in Bb) ? Bb[p] : "-"
          if (l == r) { o = "SAME"; nb = r }
          else if (l == b) { o = "TAKE_R"; nb = b }
          else if (r == b) { o = "TAKE_L"; nb = (sel ? l : b) }
          else if (is_union(p)) { o = "UNION"; nb = (sel ? l : b) }
          else { o = "CONFLICT"; nb = b }
        } else if (r != "-") {
          if (l == r) { o = "SAME"; nb = r }
          else if (l == "-") { o = "TAKE_R"; nb = "-" }
          else if ((p SUBSEP l) in H) { o = "TAKE_R"; nb = l }
          else if (is_union(p)) { o = "UNION"; nb = (sel ? l : "-") }
          else { o = "CONFLICT"; nb = "-" }
        } else if (p in HP) {
          if ((p SUBSEP l) in H) { o = "TAKE_R"; nb = l }
          else { o = "CONFLICT"; nb = "-" }
        } else {
          o = "TAKE_L"; nb = (sel ? l : "-")
        }
        print o, p, l, r, nb, sel
      }
    }' "$L" "$Rf" "$Bf" "$Hf" "$Sf" | env LC_ALL=C sort -t "$TAB" -k2,2 > "$WORK/plan" \
    || { warn "could not compute the sync plan"; return 1; }
  classify_plan || { warn "could not classify the sync plan"; return 1; }
}

# classify_plan — writes $WORK/learning.lst: every plan path in the learning stores, one
# `<path><TAB>twin|store` line (twin = the twin set; store = the other learning stores).
classify_plan() {
  local o p rest
  while IFS="$TAB" read -r o p rest; do
    if is_twin_path "$p"; then printf '%s\ttwin\n' "$p"
    elif is_learning_path "$p"; then printf '%s\tstore\n' "$p"; fi
  done < "$WORK/plan" > "$WORK/learning.lst"
}

# hold_rows <paths-file> <outcome> — rewrites the plan rows of the listed paths: outcome <outcome>
# (HOLD = a refused twin path, SKIP = a learning path not published for want of consent; both are
# no-ops for pull and push), not selected, and newbase = the PREVIOUS base entry ("-" when there
# was none, or no base at all — B.tsv is empty then), so meta-base never records them as agreed.
hold_rows() {
  awk -F'\t' -v OFS='\t' -v o="$2" -v PF="$1" -v BF="$WORK/B.tsv" '
    FILENAME == PF { h[$1] = 1; next }
    FILENAME == BF { b[$1] = $2; next }
    ($2 in h) { $1 = o; $5 = (($2 in b) ? b[$2] : "-"); $6 = 0 }
    { print }' "$1" "$WORK/B.tsv" "$WORK/plan" > "$WORK/plan.new" \
    && mv -f "$WORK/plan.new" "$WORK/plan"
}

# count_outcome <outcome> [selected-only:0|1]
count_outcome() {
  awk -F'\t' -v o="$1" -v so="${2:-0}" '$1 == o && (so == 0 || $6 == 1) { n++ } END { print n + 0 }' "$WORK/plan"
}

# report_conflicts <selected-only:0|1> — prints one line per conflict; returns 0 when there are none.
report_conflicts() {
  local n
  n="$(count_outcome CONFLICT "$1")"
  [ "$n" -eq 0 ] && return 0
  awk -F'\t' -v so="$1" '$1 == "CONFLICT" && (so == 0 || $6 == 1) { print "meta_sync: conflict " $2 }' "$WORK/plan" >&2
  warn "aborted — $n conflict(s); nothing was changed (no file written, no ref moved, meta-base untouched). A conflict needs a human."
  return 1
}

# report_not_a_file <selected-only:0|1> — 0 unless a path the branch holds a FILE at is, locally,
# a directory or another non-regular file. find lists regular files only, so such a path reads as
# locally ABSENT: a pull would rename the branch file INTO the directory (and record it as synced)
# and a push would delete the branch file. Paths the branch does not hold are never refused.
report_not_a_file() {
  local o p l r nb sel n=0
  while IFS="$TAB" read -r o p l r nb sel; do
    [ "$r" != "-" ] || continue
    [ "$1" = "0" ] || [ "$sel" = "1" ] || continue
    if [ -e "$ROOT/$p" ] && [ ! -f "$ROOT/$p" ]; then
      warn "not_a_file $p"; n=$((n + 1))
    fi
  done < "$WORK/plan"
  [ "$n" -eq 0 ] && return 0
  warn "refusing — $n managed path(s) above exist locally as a directory or another non-regular file while the branch holds a file there; nothing was changed (no file written, no ref moved, meta-base untouched)"
  return 1
}

# union_into <R-blob|-> <L-blob|-> <out> [<L-file>|""] [<path>] — the union of a union path (see
# the header's 3-WAY RULE): for a .dismissed-decisions ledger the ORDERED merge (ordered_merge),
# for every other union path R's lines unchanged, then L's lines not present in R. With <L-file>
# (pull) L is read from the working file — a pull hashes local files WITHOUT -w, so L's blob is
# not in the object store — and must still hash to <L-blob> (a file changed mid-sync fails
# closed). Every read fails closed: a side that cannot be read is NEVER treated as empty (that
# silently drops the clone's unpushed ledger lines). "-" = absent side.
union_into() {
  { : > "$WORK/u.r" && : > "$WORK/u.l"; } || return 1
  if [ "$1" != "-" ]; then g cat-file blob "$1" > "$WORK/u.r" 2>/dev/null || return 1; fi
  if [ "$2" != "-" ]; then
    if [ -n "${4:-}" ]; then
      cat "$4" > "$WORK/u.l" 2>/dev/null || return 1
      [ "$(g hash-object --no-filters -- "$WORK/u.l" 2>/dev/null)" = "$2" ] \
        || { warn "$4 changed during the sync"; return 1; }
    else
      g cat-file blob "$2" > "$WORK/u.l" 2>/dev/null || return 1
    fi
  fi
  case "${5:-}" in
    .supervisor/automate/*.dismissed-decisions) ordered_merge "$WORK/u.r" "$WORK/u.l" "$3" ;;
    *) awk 'FNR == NR { inR[$0] = 1; print; next } !($0 in inR) && !seen[$0]++ { print }' "$WORK/u.r" "$WORK/u.l" > "$3" ;;
  esac
}

# ordered_merge <R-file> <L-file> <out> — the .dismissed-decisions union. Every distinct line is
# kept once (R's first, then L's new ones); `summary-member<TAB><h8><TAB><slot>` rows are a SET
# (automate-dismissed.sh collects them position-independently) and come first, then the decision
# rows `<draft><TAB><decision><TAB><ts>` sorted by their ISO-8601 ts — stable, so ties keep R's
# rows first — because the reader is last-row-wins: a plain union would let an OLDER local
# decision override a NEWER branch one. A row whose third field is not an ISO-8601 timestamp sorts
# with the set rows (oldest).
ordered_merge() {
  awk -v RF="$1" -v OFS='\t' '
    function emit(line,   n, f, grp, key) {
      n = split(line, f, "\t"); grp = 0; key = ""
      if (n >= 3 && f[1] != "summary-member" && f[1] != "" && f[3] ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T/) { grp = 1; key = f[3] }
      print grp, key, ++seq, line
    }
    !($0 in seen) { seen[$0] = 1; emit($0) }' "$1" "$2" \
    | env LC_ALL=C sort -t "$TAB" -k1,1n -k2,2 -k3,3n | cut -f4- > "$3"
}

# refuse_bad_base — pull / push refuse UP FRONT (after the lock, before any fetch, write or
# publish) when <gitdir>/meta-base exists but is not a regular file. load_base reads such a path as
# "no base", so without this a push would publish and only then fail to record meta-base, and a
# pull would write local files first. The path is left exactly as found (nothing moved into it).
refuse_bad_base() {
  local kind=""
  { [ -e "$META_BASE" ] || [ -L "$META_BASE" ]; } || return 0
  [ -f "$META_BASE" ] && return 0
  [ -d "$META_BASE" ] && kind=" (it is a directory)"
  die "refusing — meta-base $META_BASE is not a regular file$kind; remove or replace it by hand. Nothing was changed (no fetch, no file written, nothing published)."
}

# refuse_foreign_base — pull / push refuse UP FRONT (after the lock, before any fetch) when
# meta-base is bound to another branch, unreadable or malformed (load_base's BASE_REFUSAL). A
# LEGACY base is checked later, in compute_plan, because that check needs the fetched R.
refuse_foreign_base() {
  load_base 2>/dev/null
  [ -z "$BASE_REFUSAL" ] || die "$BASE_REFUSAL"
}

# write_base_file <tree> — atomic replace via a mktemp'd (O_EXCL, never a pre-existing symlink)
# sibling + rename; a meta-base that is a directory (mv would move INTO it) fails closed. Writes
# both lines in ONE file (tree, then `branch $BRANCH`), so the binding can never be torn from the
# tree; the lock (pull / push) means the branch checked by load_base is the branch written here.
write_base_file() {
  local tmp
  [ -d "$META_BASE" ] && { warn "$META_BASE is a directory"; return 1; }
  tmp="$(mktemp "$META_BASE.tmp.XXXXXX" 2>/dev/null)" || return 1
  chmod "$FILE_MODE" "$tmp" && printf '%s\nbranch %s\n' "$1" "$BRANCH" > "$tmp" && mv -f "$tmp" "$META_BASE" || { rm -f "$tmp"; return 1; }
  g update-ref "$BASE_REF" "$1" >/dev/null 2>&1 || warn "could not update the gc anchor $BASE_REF (meta-base itself was written)"
  return 0
}

