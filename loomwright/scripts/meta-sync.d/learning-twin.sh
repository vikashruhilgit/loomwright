# ---- learning stores: consent (push) and the twin set (pull + push) ----
# read_consent — asks the sibling setup-memory.sh (`consent status`, the ONE reader of the
# user-scope record; this script never parses it and never writes it) and sets CONSENT to
# granted | declined | none | `unknown <reason>`. FAIL-CLOSED on the answer's shape: only an exact
# single-line `granted` grants; a missing reader, a non-zero exit, empty or multi-line output is
# `unknown`, which publishes nothing.
CONSENT=""
read_consent() {
  local out rc=0 nl='
'
  if [ ! -f "$HERE/setup-memory.sh" ]; then CONSENT="unknown setup-memory.sh is missing"; return 0; fi
  out="$(bash "$HERE/setup-memory.sh" --root "$ROOT" consent status 2>/dev/null)" || rc=$?
  if [ "$rc" -ne 0 ]; then CONSENT="unknown setup-memory.sh consent status exited $rc"; return 0; fi
  case "$out" in
    *"$nl"*)                CONSENT="unknown multi-line answer" ;;
    granted|declined|none)  CONSENT="$out" ;;
    "")                     CONSENT="unknown empty answer" ;;
    *)                      CONSENT="unknown $out" ;;
  esac
}

# consent_skip — push only. Every SELECTED learning-store row that would publish (take-L: an add,
# change or delete on the branch; union) is skipped unless this repo's consent reads `granted`:
# named on stderr (`learning_skipped`), then held (hold_rows SKIP: not pushed, meta-base keeps its
# previous entry). The record is read only when such a row exists.
consent_skip() {
  awk -F'\t' -v LF="$WORK/learning.lst" 'FILENAME == LF { c[$1] = 1; next }
    ($2 in c) && $6 == 1 && ($1 == "TAKE_L" || $1 == "UNION") { print $2 }' \
    "$WORK/learning.lst" "$WORK/plan" > "$WORK/publish.learning" || return 1
  [ -s "$WORK/publish.learning" ] || return 0
  read_consent
  [ "$CONSENT" = "granted" ] && return 0
  sed 's/^/meta_sync: learning_skipped /; s/$/ — no consent (run \/setup memory)/' "$WORK/publish.learning" >&2
  warn "$(wc -l < "$WORK/publish.learning" | tr -d ' ') learning-store path(s) above not published — this repo's consent reads '${CONSENT%% *}' (run /setup memory to record one); run history still pushes"
  hold_rows "$WORK/publish.learning" SKIP
}

# tracked_learning_hold [quiet:0|1] — pull, push and status --learning. GIT OWNS A TRACKED LEARNING
# STORE (header: TRACKED LEARNING STORES): every learning-store plan path this checkout's git index
# tracks is named on stderr (`learning_tracked`, unless quiet) and held (hold_rows TRACKED: never
# written, deleted, merged, published or reported as a conflict; meta-base keeps its PREVIOUS
# entry). Run-history paths are never looked up here, so a tracked run-history path syncs exactly
# as before. The index is read NUL-delimited over the learning roots only, with the caller's
# GIT_INDEX_FILE / GIT_DIR / GIT_WORK_TREE cleared (an inherited GIT_INDEX_FILE naming a missing
# file reads as an empty index with exit 0), and FAILS CLOSED (non-zero) like every other git read:
# a failed read is never "nothing tracked". Sets TRACKED_N.
TRACKED_N=0
tracked_learning_hold() {
  TRACKED_N=0
  : > "$WORK/tracked.learning" || return 1
  [ -s "$WORK/learning.lst" ] || return 0
  env -u GIT_INDEX_FILE -u GIT_DIR -u GIT_WORK_TREE git -C "$ROOT" ls-files -z -- .supervisor/twin .supervisor/agent-memory-proposals .supervisor/eval > "$WORK/tl.raw" 2>/dev/null \
    || { warn "could not read this checkout's git index (git ls-files failed)"; return 1; }
  no_newline_in "$WORK/tl.raw" "the tracked files under the learning-store roots" || return 1
  tr '\0' '\n' < "$WORK/tl.raw" \
    | awk -F'\t' -v LF="$WORK/learning.lst" 'FILENAME == LF { c[$1] = 1; next } ($0 in c) && !s[$0]++' "$WORK/learning.lst" - \
    | env LC_ALL=C sort > "$WORK/tracked.learning" || return 1
  [ -s "$WORK/tracked.learning" ] || return 0
  TRACKED_N="$(wc -l < "$WORK/tracked.learning" | tr -d ' ')"
  if [ "${1:-0}" = "0" ]; then
    sed 's/^/meta_sync: learning_tracked /; s/$/ — tracked by git, left to git/' "$WORK/tracked.learning" >&2
    warn "$TRACKED_N learning-store path(s) above are tracked by this checkout's git index — git owns them: not written, deleted, merged or published here, meta-base keeps their previous entry; run history still syncs"
  fi
  hold_rows "$WORK/tracked.learning" TRACKED
}

# twin_sha — sha256 of stdin, with the SAME tool order read-system-contract.sh uses.
twin_sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else return 1; fi
}
# twin_field <line> <key> — read-system-contract.sh's own STRING-field extractor, verbatim.
twin_field() { printf '%s' "$1" | sed -E "s/.*\"$2\":\"([^\"]*)\".*/\1/"; }
# twin_trusted <provenance file> <out> — the content_hashes of the chain-valid `add` entries, by
# read-system-contract.sh's walk exactly: blank lines skipped, prev_hash GENESIS first and then the
# sha256 of the previous raw line, the walk stops at the first break.
twin_trusted() {
  local line prev="GENESIS" ch
  : > "$2" || return 1
  [ -f "$1" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ "$(twin_field "$line" prev_hash)" = "$prev" ] || break
    if [ "$(twin_field "$line" action)" = "add" ]; then
      ch="$(twin_field "$line" content_hash)"; [ -n "$ch" ] && printf '%s\n' "$ch" >> "$2"
    fi
    prev="$(printf '%s' "$line" | twin_sha)" || return 1
  done < "$1"
}
# twin_post_bytes <side> <outcome> <path> <L> <R> <sel> <out> — the bytes the twin path would hold
# on <side> after the sync (pull: the working folder; push: the branch) into <out>; returns 2 when
# the path would be absent there. Local bytes of a pull come from the working file (a pull hashes
# without -w, so L is not in the object store); every other side is a blob read. Fails closed.
twin_post_bytes() {
  local v
  if [ "$1" = "pull" ]; then
    if [ "$2" = "TAKE_R" ]; then v="$5"; else v="$4"; [ "$v" = "-" ] && return 2; cat "$ROOT/$3" > "$7" 2>/dev/null; return $?; fi
  else
    if [ "$2" = "TAKE_L" ] && [ "$6" = "1" ]; then v="$4"; else v="$5"; fi
  fi
  [ "$v" = "-" ] && return 2
  g cat-file blob "$v" > "$7" 2>/dev/null
}
# twin_pair_check <side> — appends `<path><TAB><reason>` to $WORK/twin.bad for every contract the
# post-state of <side> would hold WITHOUT a chain-valid `add` entry in that post-state's provenance.
twin_pair_check() {
  local o p l r nb sel rc
  printf 'x' | twin_sha >/dev/null 2>&1 || {
    printf '%s\tno sha256 tool — the pair rule cannot be checked\n' "$TWIN_PROV" >> "$WORK/twin.bad"; return 0; }
  : > "$WORK/twin.prov" || return 1
  while IFS="$TAB" read -r o p l r nb sel; do
    [ "$p" = "$TWIN_PROV" ] || continue
    twin_post_bytes "$1" "$o" "$p" "$l" "$r" "$sel" "$WORK/twin.prov"; rc=$?
    [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ] || { warn "could not read the post-sync bytes of $p"; return 1; }
    [ "$rc" -eq 2 ] && rm -f "$WORK/twin.prov"
  done < "$WORK/twin.rows"
  twin_trusted "$WORK/twin.prov" "$WORK/twin.trusted" || { warn "could not walk the provenance chain"; return 1; }
  while IFS="$TAB" read -r o p l r nb sel; do
    [ "$p" = "$TWIN_PROV" ] && continue
    twin_post_bytes "$1" "$o" "$p" "$l" "$r" "$sel" "$WORK/twin.body"; rc=$?
    [ "$rc" -eq 2 ] && continue
    [ "$rc" -eq 0 ] || { warn "could not read the post-sync bytes of $p"; return 1; }
    grep -qxF -- "$(twin_sha < "$WORK/twin.body")" "$WORK/twin.trusted" \
      || printf '%s\tno chain-valid add provenance entry\n' "$p" >> "$WORK/twin.bad"
  done < "$WORK/twin.rows"
  return 0
}

# twin_gate <pull|push> [selected-only:0|1] — the TWIN SET rule (header: TWIN SET). Runs only when
# the sync would change the twin set on <side> (pull: a take-R twin row; push: a selected take-L
# twin row) or a twin path conflicts. Any twin conflict, or a pair-rule break in <side>'s
# post-state, REFUSES THE TWIN SET: every offending path named (`twin_refused`), then EVERY twin
# row held (hold_rows HOLD: nothing of the twin set written or deleted, meta-base keeps every twin
# path's previous entry). Sets TWIN_REFUSED. Non-zero only when a read failed (fail closed).
TWIN_REFUSED=0
twin_gate() {
  local side="$1" so="${2:-0}"
  TWIN_REFUSED=0
  awk -F'\t' -v LF="$WORK/learning.lst" 'FILENAME == LF { if ($2 == "twin") t[$1] = 1; next } ($2 in t)' \
    "$WORK/learning.lst" "$WORK/plan" > "$WORK/twin.rows" || return 1
  [ -s "$WORK/twin.rows" ] || return 0
  : > "$WORK/twin.bad" || return 1
  awk -F'\t' -v OFS='\t' -v so="$so" '$1 == "CONFLICT" && (so == 0 || $6 == 1) { print $2, "conflict" }' \
    "$WORK/twin.rows" >> "$WORK/twin.bad" || return 1
  if awk -F'\t' -v side="$side" '(side == "pull" && $1 == "TAKE_R") || (side == "push" && $1 == "TAKE_L" && $6 == 1) { f = 1 } END { exit !f }' "$WORK/twin.rows"; then
    twin_pair_check "$side" || return 1
  fi
  [ -s "$WORK/twin.bad" ] || return 0
  awk -F'\t' '{ print "meta_sync: twin_refused " $1 ": " $2 }' "$WORK/twin.bad" >&2
  if [ "$side" = "pull" ]; then side="the working folder"; else side="the branch"; fi
  warn "twin set refused on $side — nothing of it written or deleted there, meta-base keeps every twin path's previous entry; run history and the other stores still sync. To resolve, keep ONE side's chain (discard the local twin set and pull, or re-append onto the branch's chain), then reprovenance-twin-contracts.sh --confirm only to re-bless contract bodies left without a chain entry."
  cut -f2 "$WORK/twin.rows" > "$WORK/twin.paths" || return 1
  hold_rows "$WORK/twin.paths" HOLD || return 1
  TWIN_REFUSED=1
  return 0
}

