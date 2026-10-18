# build_pull_base — the meta-base a pull records after REFUSING the twin set or leaving a tracked
# learning path to git: R's entry for every path, except every held path (HOLD: a refused twin path;
# TRACKED: a learning path git tracks), which keeps its previous base entry (hold_rows wrote it into
# the newbase column; "-" = absent). Prints the tree SHA.
build_pull_base() {
  rm -f "$META_BASE_INDEX"
  GIT_INDEX_FILE="$META_BASE_INDEX" g read-tree --empty || return 1
  awk -F'\t' '{ v = ($1 == "HOLD" || $1 == "TRACKED") ? $5 : $4; if (v != "-") print "100644 " v "\t" $2 }' "$WORK/plan" \
    | GIT_INDEX_FILE="$META_BASE_INDEX" g update-index --index-info || return 1
  GIT_INDEX_FILE="$META_BASE_INDEX" g write-tree
}

# ---- subcommands ----
cmd_init() {
  remote_probe
  case "$REMOTE_STATE" in
    present) die "init_refused — '$BRANCH' already exists on origin ($REMOTE_SHA); nothing was changed" ;;
    unreachable) die "fetch_failed — origin is unreachable; nothing was created" ;;
  esac
  local empty c
  empty="$(g mktree < /dev/null)" || die "could not write the empty tree"
  c="$(printf '%s\n' "meta-sync: initialise $BRANCH" | g commit-tree "$empty")" || die "commit-tree failed (is user.name / user.email configured?)"
  g push -q origin "$c:refs/heads/$BRANCH" || die "init push failed — '$BRANCH' was not created"
  say "initialised $BRANCH at $c"
}

fetch_or_exit() {
  local rc
  fetch_remote; rc=$?
  case "$rc" in
    0) return 0 ;;
    3) no_remote_branch_msg; exit 1 ;;
    *) warn "fetch_failed — could not fetch '$BRANCH' from origin"; [ -s "$WORK/fetch.err" ] && sed 's/^/  /' "$WORK/fetch.err" >&2; exit 1 ;;
  esac
}

cmd_pull() {
  local rc
  refuse_bad_base
  refuse_foreign_base
  fetch_or_exit
  compute_plan 0; rc=$?
  [ "$rc" -eq 2 ] && die "$BASE_REFUSAL"
  [ "$rc" -eq 0 ] || exit 1
  tracked_learning_hold || die "could not check which learning-store paths git tracks; nothing was changed"
  twin_gate pull 0 || die "could not evaluate the twin set; nothing was changed"
  report_conflicts 0 || exit 1
  report_not_a_file 0 || exit 1
  local o p l r nb sel written=0 deleted=0 dst tmp phase
  # Containment pre-pass: nothing is written or deleted unless EVERY path the plan touches is a
  # canonical managed path with no symlinked component (list_local already refused symlinks where
  # run history lives; this re-checks the exact plan paths before the first write).
  while IFS="$TAB" read -r o p l r nb sel; do
    case "$o" in
      TAKE_R|UNION)
        is_managed "$p" || die "refusing non-managed path in the plan: $p (nothing was changed)"
        path_has_no_symlink "$p" || die "refusing — a component of $p is a symlink (nothing was changed)" ;;
    esac
  done < "$WORK/plan"
  # UNION rows first, then TAKE_R: the union re-reads the working ledger and refuses when it no
  # longer hashes to the planned L (`changed during the sync`). Run first, that refusal happens
  # before any other managed file is written or deleted — so it really changes nothing.
  for phase in UNION TAKE_R; do
    while IFS="$TAB" read -r o p l r nb sel; do
      [ "$o" = "$phase" ] || continue
      dst="$ROOT/$p"
      # Defence in depth (a symlink planted after the pre-pass): re-check right before the act, and
      # after any mkdir -p confirm the parent resolves physically under .supervisor/.
      path_has_no_symlink "$p" || die "refusing — a component of $p is a symlink (meta-base untouched)"
      if [ -e "$dst" ] && [ ! -f "$dst" ]; then
        die "refusing — $p exists locally but is not a regular file (meta-base untouched)"
      fi
      if [ "$o" = "TAKE_R" ] && [ "$r" = "-" ]; then
        parent_inside "$p" || die "refusing — $p does not resolve under .supervisor/ (meta-base untouched)"
        rm -f "$dst" || die "could not delete $p (meta-base untouched)"
        deleted=$((deleted + 1))
        continue
      fi
      mkdir -p "$(dirname "$dst")" || die "could not create the folder for $p (meta-base untouched)"
      parent_inside "$p" || die "refusing — $p does not resolve under .supervisor/ (meta-base untouched)"
      tmp="$(mktemp "$dst.meta-sync.tmp.XXXXXX" 2>/dev/null)" || die "could not create a temp file for $p (meta-base untouched)"
      chmod "$FILE_MODE" "$tmp" || { rm -f "$tmp"; die "could not set the mode of a temp file for $p (meta-base untouched)"; }
      if [ "$o" = "TAKE_R" ]; then
        g cat-file blob "$r" > "$tmp" 2>/dev/null && mv -f "$tmp" "$dst" \
          || { rm -f "$tmp"; die "could not write $p (meta-base untouched)"; }
      else
        union_into "$r" "$l" "$tmp" "$dst" "$p" && mv -f "$tmp" "$dst" \
          || { rm -f "$tmp"; die "could not write the union of $p (it runs first: nothing was changed, meta-base untouched)"; }
      fi
      written=$((written + 1))
    done < "$WORK/plan"
  done
  # A refused twin set or a left-alone tracked learning path must not look agreed: meta-base is then
  # per-path (header: WHAT meta-base RECORDS) — R's entry everywhere except the held paths, which
  # keep their previous entry.
  if [ "$TWIN_REFUSED" = "1" ] || [ "$TRACKED_N" != "0" ]; then
    nb="$(build_pull_base)" || die "could not build the per-path meta-base (held paths); meta-base untouched"
  else
    nb="$RT"
  fi
  write_base_file "$nb" || die "could not write meta-base"
  say "pulled $R ($written written, $deleted deleted)"
}

# build_agreed_base — the per-path agreed-state tree for a push (see header); prints its SHA.
build_agreed_base() {
  rm -f "$META_BASE_INDEX"
  GIT_INDEX_FILE="$META_BASE_INDEX" g read-tree --empty || return 1
  awk -F'\t' '$5 != "-" { print "100644 " $5 "\t" $2 }' "$WORK/plan" \
    | GIT_INDEX_FILE="$META_BASE_INDEX" g update-index --index-info || return 1
  GIT_INDEX_FILE="$META_BASE_INDEX" g write-tree
}

cmd_push() {
  [ -z "$PATHS_FROM" ] || [ -f "$PATHS_FROM" ] || die "usage: --paths-from '$PATHS_FROM' is not a file"
  local attempt=1 o p l r nb sel s newtree commit changed abort_sel rc
  refuse_bad_base
  refuse_foreign_base
  while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    fetch_or_exit
    compute_plan 1; rc=$?
    [ "$rc" -eq 2 ] && die "$BASE_REFUSAL"
    [ "$rc" -eq 0 ] || exit 1
    # With a base, an unlisted path is ignored entirely; without one the derivation covers the
    # whole managed set and any non-twin conflict anywhere aborts (meta-base must cover every
    # path; a twin conflict instead refuses the twin set, whose paths then keep their previous
    # meta-base entry — header: TWIN SET). Learning-store paths publish only with consent.
    abort_sel=1
    [ "$HAVE_BASE" = "1" ] || abort_sel=0
    tracked_learning_hold || die "could not check which learning-store paths git tracks; nothing was pushed"
    consent_skip || die "could not apply the learning-store consent; nothing was pushed"
    twin_gate push "$abort_sel" || die "could not evaluate the twin set; nothing was pushed"
    report_conflicts "$abort_sel" || exit 1
    report_not_a_file "$abort_sel" || exit 1
    rm -f "$META_INDEX"
    GIT_INDEX_FILE="$META_INDEX" g read-tree "$RT" || die "read-tree into the separate index failed"
    : > "$WORK/candidates"
    : > "$WORK/planned"
    changed=0
    while IFS="$TAB" read -r o p l r nb sel; do
      [ "$sel" = "1" ] || continue
      case "$o" in TAKE_L|UNION) printf '%s\n' "$p" >> "$WORK/planned" ;; esac
      case "$o" in
        TAKE_L)
          if [ "$l" = "-" ]; then
            GIT_INDEX_FILE="$META_INDEX" g update-index --force-remove -- "$p" || die "update-index failed for $p"
          else
            GIT_INDEX_FILE="$META_INDEX" g update-index --add --cacheinfo 100644 "$l" "$p" || die "update-index failed for $p"
            printf '%s\t%s\n' "$p" "$l" >> "$WORK/candidates"
          fi
          changed=$((changed + 1)) ;;
        UNION)
          union_into "$r" "$l" "$WORK/union.out" "" "$p" || die "could not build the union of $p"
          s="$(g hash-object -w --no-filters --stdin < "$WORK/union.out")" || die "hash-object failed for $p"
          GIT_INDEX_FILE="$META_INDEX" g update-index --add --cacheinfo 100644 "$s" "$p" || die "update-index failed for $p"
          printf '%s\t%s\n' "$p" "$s" >> "$WORK/candidates"
          changed=$((changed + 1)) ;;
      esac
    done < "$WORK/plan"
    newtree="$(GIT_INDEX_FILE="$META_INDEX" g write-tree)" || die "write-tree failed"
    if [ "$changed" -eq 0 ] || [ "$newtree" = "$RT" ]; then
      nb="$(build_agreed_base)" || die "could not build the agreed-state base tree"
      write_base_file "$nb" || die "could not write meta-base"
      say "no_changes"
      exit 0
    fi
    # tree_guard — the new tree may differ from R's ONLY at the selected take-L / union paths.
    g diff-tree -r -z --no-renames --name-only "$RT" "$newtree" > "$WORK/touched.z" \
      || die "tree_guard — could not diff the new tree against $RT; nothing was pushed"
    no_newline_in "$WORK/touched.z" "the new tree" || die "tree_guard — the new tree holds a newline name; nothing was pushed, meta-base untouched"
    tr '\0' '\n' < "$WORK/touched.z" | awk -v PF="$WORK/planned" 'FILENAME == PF { ok[$0] = 1; next } NF && !($0 in ok)' "$WORK/planned" - > "$WORK/unplanned" \
      || die "tree_guard — could not compare the new tree with the plan; nothing was pushed"
    if [ -s "$WORK/unplanned" ]; then
      sed 's/^/  unplanned: /' "$WORK/unplanned" >&2
      die "tree_guard — the new tree changes $(wc -l < "$WORK/unplanned" | tr -d ' ') path(s) the plan did not select; nothing was pushed, meta-base untouched"
    fi
    if ! scrub_candidates "$WORK/candidates" >&2; then
      warn "aborted — scrub hit(s) above; nothing was pushed, the branch and meta-base are unchanged (exclude or clean the named paths)"
      exit 2
    fi
    commit="$(printf '%s\n' "$MESSAGE" | g commit-tree "$newtree" -p "$R")" \
      || die "commit-tree failed (is user.name / user.email configured?)"
    if g push -q origin "$commit:refs/heads/$BRANCH" 2>"$WORK/push.err"; then
      nb="$(build_agreed_base)" || die "pushed $commit but could not build the agreed-state base tree; meta-base untouched"
      write_base_file "$nb" || die "pushed $commit but could not write meta-base"
      say "pushed $commit ($changed path(s))"
      exit 0
    fi
    warn "rejected (attempt $attempt/$MAX_ATTEMPTS) — re-fetching and recomputing"
    attempt=$((attempt + 1))
    [ "$attempt" -le "$MAX_ATTEMPTS" ] && sleep 1
  done
  sed 's/^/  /' "$WORK/push.err" >&2 2>/dev/null
  die "push_failed — rejected $MAX_ATTEMPTS times; nothing forced, meta-base untouched"
}

# status_paths <outcome>... — under --paths, the plan's paths with those outcomes (see STATUS).
status_paths() {
  [ "$STATUS_PATHS" = "1" ] || return 0
  awk -F'\t' -v want=" $* " 'index(want, " " $1 " ") { print "  " $2 ($3 == "-" ? " (deleted locally)" : "") }' "$WORK/plan" \
    | env LC_ALL=C sort
}

# split_learning_rows — moves the learning-store rows out of $WORK/plan into $WORK/plan.learning,
# so status's first line (count_outcome / status_paths over $WORK/plan) counts run history only.
split_learning_rows() {
  awk -F'\t' -v LF="$WORK/learning.lst" -v LO="$WORK/plan.learning" 'FILENAME == LF { c[$1] = 1; next }
    ($2 in c) { print > LO; next } { print }' "$WORK/learning.lst" "$WORK/plan" > "$WORK/plan.rh" \
    && touch "$WORK/plan.learning" && mv -f "$WORK/plan.rh" "$WORK/plan"
}

# status_done <learning state> — prints the opt-in learning line (--learning) and exits 0; a
# `; tracked <n>` suffix names how many learning-store paths git tracks here (left to git, so not
# counted in <state>) — only when there is at least one, so the line is unchanged otherwise.
status_done() {
  if [ "$STATUS_LEARNING" = "1" ]; then
    read_consent
    echo "learning: $1; consent ${CONSENT%% *}$([ "$TRACKED_N" = "0" ] || printf '; tracked %s' "$TRACKED_N")"
  fi
  exit 0
}

# learning_state — the learning stores' state over $WORK/plan.learning, same precedence as the
# first line: conflict <n> > local_ahead <n> > remote_ahead > synced.
learning_state() {
  awk -F'\t' '$1 == "CONFLICT" { c++ } $1 == "TAKE_L" || $1 == "UNION" { a++ } $1 == "TAKE_R" { r++ }
    END { if (c) print "conflict " c; else if (a) print "local_ahead " a; else if (r) print "remote_ahead"; else print "synced" }' \
    "$WORK/plan.learning" 2>/dev/null || echo "unreachable"
}

cmd_status() {
  local rc n ls
  fetch_remote; rc=$?
  case "$rc" in
    0) : ;;
    3) echo "no_remote_branch"; status_done no_remote_branch ;;
    *) echo "unreachable"; status_done unreachable ;;
  esac
  [ -f "$META_BASE" ] || { echo "never_synced"; status_done never_synced; }
  compute_plan 0 >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && { echo "base_branch_mismatch"; status_done base_branch_mismatch; }
  [ "$rc" -eq 0 ] || { echo "unreachable"; status_done unreachable; }
  [ "$HAVE_BASE" = "1" ] || { echo "never_synced"; status_done never_synced; }
  # --learning only: tracked learning paths are git's (header: TRACKED LEARNING STORES) — held out
  # of the learning state and counted on the learning line; an unreadable index makes it unreachable.
  ls=""
  if [ "$STATUS_LEARNING" = "1" ]; then tracked_learning_hold 1 2>/dev/null || { TRACKED_N=0; ls="unreachable"; }; fi
  split_learning_rows || { echo "unreachable"; status_done unreachable; }
  [ -n "$ls" ] || ls="$(learning_state)"
  n="$(count_outcome CONFLICT)"
  [ "$n" -gt 0 ] && { echo "conflict $n"; status_paths CONFLICT; status_done "$ls"; }
  n=$(( $(count_outcome TAKE_L) + $(count_outcome UNION) ))
  [ "$n" -gt 0 ] && { echo "local_ahead $n"; status_paths TAKE_L UNION; status_done "$ls"; }
  [ "$(count_outcome TAKE_R)" -gt 0 ] && { echo "remote_ahead"; status_done "$ls"; }
  echo "synced $R on $BRANCH"
  status_done "$ls"
}

# cmd_scrub — push's scrub as a DRY RUN over the --paths-from list (working-tree files under the
# root; blank / `#` lines ignored, a leading `./` and a trailing CR stripped, duplicates scanned
# once). Every listed path goes through the SAME scan_file (with-line mode); a path that is missing
# or not a readable regular file is the `unreadable` hit, printed here. Hits go to stderr; exit 2
# on any hit, 0 when clean. Writes nothing, takes no lock, needs no branch.
cmd_scrub() {
  local p n=0 bad=0 any
  { [ -f "$PATHS_FROM" ] && [ -r "$PATHS_FROM" ]; } \
    || die "usage: --paths-from '$PATHS_FROM' is not a readable file; nothing was scanned"
  sed -e 's/\r$//' -e 's|^\./||' < "$PATHS_FROM" | awk 'NF && $0 !~ /^#/ && !seen[$0]++' > "$WORK/scrub.list" \
    || die "could not read --paths-from '$PATHS_FROM'; nothing was scanned"
  load_allowlist
  while IFS= read -r p; do
    n=$((n + 1)); any=0
    if [ -f "$ROOT/$p" ] && [ -r "$ROOT/$p" ]; then
      scan_file "$ROOT/$p" "$p" 1 >&2 || any=1
    else
      scrub_report "$p" unreadable - 1 >&2; any=1
    fi
    [ "$any" -eq 0 ] || bad=$((bad + 1))
  done < "$WORK/scrub.list"
  if [ "$bad" -gt 0 ]; then
    warn "aborted — scrub hit(s) above in $bad of $n file(s); nothing was changed (clean or exclude the named paths before a push)"
    exit 2
  fi
  say "clean ($n file(s) scanned)"
}

# cmd_list_managed — every path is_managed accepts, one per line, LC_ALL=C-sorted. Default: the
# local working folder through list_local (the exact enumeration pull / push use, so its symlink,
# unsearchable-root and newline-name refusals apply: exit 1). --tracked: `git ls-files` (the index)
# under .supervisor/, read NUL-delimited (a newline name is refused, as everywhere else) with the
# caller's GIT_INDEX_FILE / GIT_DIR / GIT_WORK_TREE cleared, so an inherited index override can
# never make this checkout's tracked set read as empty.
cmd_list_managed() {
  local p
  if [ "$TREE_SET" = "1" ]; then
    g rev-parse -q --verify "$TREE_SRC^{tree}" >/dev/null 2>&1 \
      || die "list-managed --tree: '$TREE_SRC' is not a tree-ish in this repository; nothing was changed"
    list_tree "$TREE_SRC" "$WORK/lm.tsv" || die "could not list the managed entries of '$TREE_SRC'; nothing was changed"
    cut -f1 "$WORK/lm.tsv" > "$WORK/lm.out" || die "could not read the tree's managed-file list"
  elif [ "$TRACKED" = "1" ]; then
    env -u GIT_INDEX_FILE -u GIT_DIR -u GIT_WORK_TREE git -C "$ROOT" ls-files -z -- .supervisor > "$WORK/lm.z" 2>/dev/null \
      || die "could not list the tracked files (git ls-files failed); nothing was changed"
    no_newline_in "$WORK/lm.z" "the tracked files under .supervisor/" || exit 1
    tr '\0' '\n' < "$WORK/lm.z" \
      | while IFS= read -r p; do if is_managed "$p"; then printf '%s\n' "$p"; fi; done \
      | env LC_ALL=C sort -u > "$WORK/lm.out" || die "could not filter the tracked files"
  else
    list_local "$WORK/lm.tsv" 0 || die "could not enumerate the local managed files; nothing was changed"
    cut -f1 "$WORK/lm.tsv" > "$WORK/lm.out" || die "could not read the local managed-file list"
  fi
  if [ "$RUN_HISTORY" = "1" ]; then
    while IFS= read -r p; do if ! is_learning_path "$p"; then printf '%s\n' "$p"; fi; done < "$WORK/lm.out" > "$WORK/lm.rh" \
      || die "could not filter the run-history paths"
    mv -f "$WORK/lm.rh" "$WORK/lm.out" || die "could not filter the run-history paths"
  fi
  cat "$WORK/lm.out"
}

