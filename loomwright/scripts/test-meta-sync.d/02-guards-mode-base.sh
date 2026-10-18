echo "== 30. a newline in a name fails closed (remote tree, R's history, local find) =="
synced_pair
OG="$W/origin.git"
tip0="$(br_tip)"
fabblob="$(printf 'fabricated\n' | og hash-object -w --stdin)"
legit="$(printf 'legit\n' | og hash-object -w --stdin)"
# A directory named "x<LF>100644 blob <fabblob><TAB>.supervisor" holding requirements/fab.md: read
# line by line, its ls-tree record splits into `.supervisor/requirements/x` and a FABRICATED
# `100644 blob <fabblob><TAB>.supervisor/requirements/fab.md` record (fabblob is made reachable as
# fabsrc.md so a parser fooled by it can really write it). legit.md / fabsrc.md are pending take-Rs.
t_fab="$(printf '100644 blob %s\tfab.md\0' "$legit" | og mktree -z)"
t_mid="$(printf '040000 tree %s\trequirements\0' "$t_fab" | og mktree -z)"
nl_name="$(printf 'x\n100644 blob %s\t.supervisor' "$fabblob")"
req0="$(og rev-parse "$tip0:.supervisor/requirements")"
reqN="$({ og ls-tree -z "$req0"; printf '040000 tree %s\t%s\0' "$t_mid" "$nl_name"; printf '100644 blob %s\tlegit.md\0' "$legit"; printf '100644 blob %s\tfabsrc.md\0' "$fabblob"; } | og mktree -z)"
cN="$(printf 'newline name\n' | og commit-tree "$(swap_req "$reqN")" -p "$tip0")"
og update-ref "refs/heads/$BR" "$cN"
grep -qF "requirements/x|100644 blob $fabblob" < <(og ls-tree -r -z --name-only "$cN" | tr '\0\n' '\n|')
check $? "fixture: the branch tip really carries a tree entry whose name holds a newline"
base_before="$(base_of B)"
ms B pull
{ [ "$RC" -eq 1 ] && grep -q 'meta_sync: newline_in_path tree ' < <(printf '%s' "$OUT") && [ ! -e "$W/B/.supervisor/requirements/fab.md" ] \
  && [ ! -e "$W/B/.supervisor/requirements/legit.md" ] && [ ! -e "$W/B/.supervisor/requirements/fabsrc.md" ] && [ "$(base_of B)" = "$base_before" ] && [ -z "$(porcelain B)" ]; }
check $? "pull over a newline entry -> exit 1 newline_in_path, no fabricated fab.md, pending legit.md / fabsrc.md not written, meta-base unchanged (rc=$RC: $OUT)"
put B "$RQ/y.md" "y over a newline tip"; ms B push
{ [ "$RC" -eq 1 ] && grep -q 'meta_sync: newline_in_path tree ' < <(printf '%s' "$OUT") && [ "$(br_tip)" = "$cN" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "push over a newline entry -> exit 1 newline_in_path, branch tip and meta-base unchanged (rc=$RC: $OUT)"
cC="$(printf 'cleanup\n' | og commit-tree "$(swap_req "$(og rev-parse "$tip0:.supervisor/requirements")")" -p "$cN")"
og update-ref "refs/heads/$BR" "$cC"
ms B pull; rc_pull=$RC; out_pull="$OUT"
ms B push
{ [ "$rc_pull" -eq 0 ] && [ "$RC" -eq 0 ] && [ "$(br_show "$RQ/y.md")" = "y over a newline tip" ] && [ ! -e "$W/B/.supervisor/requirements/fab.md" ]; }
check $? "with the entry gone from the tip, the same clone (meta-base present) pulls and pushes again (pull rc=$rc_pull: $out_pull; push rc=$RC: $OUT)"
clone NL
ms NL pull
{ [ "$RC" -eq 1 ] && grep -q 'meta_sync: newline_in_path the history of ' < <(printf '%s' "$OUT") && [ ! -e "$W/NL/.git/meta-base" ] && [ ! -e "$W/NL/.supervisor" ]; }
check $? "a fresh clone (no meta-base) refuses the newline entry still in R's history: exit 1, nothing written, no meta-base (rc=$RC: $OUT)"
echo "-- a newline in a LOCAL name under a managed root --"
put A "$RQ/x.md" "x v2 from A"; ms A pull; ms A push
nl_local="$W/B/$RQ/$(printf 'a\nb.md')"
printf 'local newline\n' > "$nl_local"
tip="$(br_tip)"; base_before="$(base_of B)"
ms B pull
{ [ "$RC" -eq 1 ] && grep -q 'meta_sync: newline_in_path the local files' < <(printf '%s' "$OUT") && [ "$(get B "$RQ/x.md")" = "x v1" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "pull with a local newline name under requirements/ -> exit 1, pending x.md not written, meta-base unchanged (rc=$RC: $OUT)"
put B "$RQ/w.md" "w v2 from B"; ms B push
{ [ "$RC" -eq 1 ] && grep -q 'meta_sync: newline_in_path the local files' < <(printf '%s' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "push with a local newline name -> exit 1, branch tip and meta-base unchanged (rc=$RC: $OUT)"
rm -f "$nl_local"
mkdir -p "$W/B/.supervisor/logs"; printf 'x\n' > "$W/B/.supervisor/logs/$(printf 'n\nl.log')"
ms B pull; rc_pull=$RC; out_pull="$OUT"
ms B push
{ [ "$rc_pull" -eq 0 ] && [ "$RC" -eq 0 ] && [ "$(get B "$RQ/x.md")" = "x v2 from A" ] && [ "$(br_show "$RQ/w.md")" = "w v2 from B" ]; }
check $? "with it removed (a newline name under unmanaged .supervisor/logs is ignored) pull and push land (pull rc=$rc_pull: $out_pull; push rc=$RC: $OUT)"

echo "== 31. --paths-from is push/scrub-only (usage error elsewhere, nothing changed) =="
synced_pair
put A "$RQ/x.md" "x v2 from A"; ms A push
printf '%s\n' "$RQ/x.md" > "$W/pf.txt"
tip="$(br_tip)"; base_before="$(base_of B)"
for sc in pull status init list-managed; do
  ms B "$sc" --paths-from "$W/pf.txt"
  { [ "$RC" -eq 1 ] && grep -q "meta_sync: usage: --paths-from applies to push and scrub only, not '$sc'" < <(printf '%s' "$OUT") \
    && [ "$(get B "$RQ/x.md")" = "x v1" ] && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
  check $? "$sc --paths-from -> usage error exit 1, nothing written, branch and meta-base unchanged (rc=$RC: $OUT)"
done
ms B pull --paths-from ""
{ [ "$RC" -eq 1 ] && [ "$(get B "$RQ/x.md")" = "x v1" ]; }; check $? "pull --paths-from '' (empty value) is rejected too (rc=$RC: $OUT)"
ms B pull; { [ "$RC" -eq 0 ] && [ "$(get B "$RQ/x.md")" = "x v2 from A" ]; }; check $? "pull without the flag still lands (rc=$RC: $OUT)"

echo "== 32. project deny patterns (.agent/meta-sync-deny.txt) =="
synced_pair
DENY="$W/B/.agent/meta-sync-deny.txt"
mkdir -p "$W/B/.agent"
printf '%s\n' '# project deny terms' '' 'ACME-SECRET-[0-9]+' > "$DENY"
git -C "$W/B" add .agent/meta-sync-deny.txt && git -C "$W/B" commit -qm 'deny patterns'
put B "$RQ/deny.md" "ticket ACME-SECRET-42 notes"
put B "$RQ/clean.md" "nothing to see here"
tip="$(br_tip)"; base_before="$(base_of B)"
ms B push
{ [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub $RQ/deny.md: deny_pattern:3" < <(printf '%s\n' "$OUT") \
  && ! grep -qF "scrub $RQ/clean.md" < <(printf '%s' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "a matching deny ERE -> exit 2 naming deny_pattern:<line> (comment/blank lines counted), clean file not named, branch and meta-base unchanged (rc=$RC: $OUT)"
printf '%s\n' 'never-matches-zzz' '[unclosed' > "$DENY"
git -C "$W/B" commit -qam 'invalid deny pattern'
ms B push
{ [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub $RQ/deny.md: deny_pattern_invalid:2" < <(printf '%s\n' "$OUT") \
  && grep -qxF "meta_sync: scrub $RQ/clean.md: deny_pattern_invalid:2" < <(printf '%s\n' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "an invalid deny ERE -> exit 2 deny_pattern_invalid:<line> for every candidate (fail closed), branch and meta-base unchanged (rc=$RC: $OUT)"
git -C "$W/B" rm -q .agent/meta-sync-deny.txt && git -C "$W/B" commit -qm 'drop deny patterns'
ms B push
{ [ "$RC" -eq 0 ] && [ "$(br_show "$RQ/deny.md")" = "ticket ACME-SECRET-42 notes" ] && [ "$(br_show "$RQ/clean.md")" = "nothing to see here" ]; }
check $? "with the deny file absent the extension is a no-op and the same push lands (rc=$RC: $OUT)"

echo "== 33. the other fail-closed scrub branches (scan_error, ledger_unverifiable, unreadable) =="
# scan_error and unreadable are only reachable through a failing tool: the built-in EREs are fixed
# and valid, and every candidate blob was written by hash-object -w earlier in the same run. Both
# are fault-injected with PATH shims (the technique legs 22 and 27 use).
REAL_GREP="$(command -v grep)"
synced_pair
mkdir -p "$W/gshim"
cat > "$W/gshim/grep" <<SHIM
#!/bin/sh
# fault injection: the built-in case-insensitive rule scan (grep -i -E -q -e <re> <file>) errors,
# and so does the email rule's match listing (email_matches: grep -a -i -n -o -E -e <re> <file>)
if [ "\$1" = "-i" ] && [ "\$2" = "-E" ] && [ "\$3" = "-q" ]; then exit 2; fi
if [ "\$1" = "-a" ] && [ "\$2" = "-i" ] && [ "\$3" = "-n" ] && [ "\$4" = "-o" ]; then exit 2; fi
exec "$REAL_GREP" "\$@"
SHIM
chmod +x "$W/gshim/grep"
put B "$RQ/se.md" "plain clean text"
tip="$(br_tip)"; base_before="$(base_of B)"
OUT="$(PATH="$W/gshim:$PATH" bash "$SCRIPT" push --root "$W/B" 2>&1)"; RC=$?
{ [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub $RQ/se.md: scan_error(email)" < <(printf '%s\n' "$OUT") \
  && grep -qxF "meta_sync: scrub $RQ/se.md: scan_error(home_path)" < <(printf '%s\n' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "a scan that errors -> exit 2 scan_error(<rule>), branch and meta-base unchanged (rc=$RC: $OUT)"
rm -f "$W/B/$RQ/se.md"
# a PATH with every tool the SUT and setup-memory.sh use EXCEPT jq (macOS ships /usr/bin/jq, so
# dropping one directory is not enough): a hermetic dir of symlinks, built here.
NOJQ="$W/nojq-bin"; mkdir -p "$NOJQ"
for t in bash sh git cat dirname basename sed awk mktemp rm mkdir rmdir ps find date sleep tr sort uniq \
         paste wc grep chmod mv cp ln touch cut env ls head tail id xargs cmp tee od stat readlink uname \
         expr true false printf test; do
  tp="$(command -v "$t" 2>/dev/null)"
  case "$tp" in /*) ln -sf "$tp" "$NOJQ/$t" ;; esac
done
NOJQ_PATH="${HERMETIC_SHIM_DIR:+$HERMETIC_SHIM_DIR:}$NOJQ"
[ -z "$(PATH="$NOJQ_PATH" command -v jq)" ] && [ -n "$(PATH="$NOJQ_PATH" command -v git)" ]
check $? "fixture: the no-jq PATH has git but no jq"
printf '%s\n' '{"repo":"owner/repo","n":3}' >> "$W/B/.supervisor/postmortem/results.jsonl"
tip="$(br_tip)"; base_before="$(base_of B)"
OUT="$(PATH="$NOJQ_PATH" "$NOJQ/bash" "$SCRIPT" push --root "$W/B" 2>&1)"; RC=$?
{ [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub .supervisor/postmortem/results.jsonl: ledger_unverifiable(jq missing)" < <(printf '%s\n' "$OUT") \
  && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "jq missing -> the ledger is unverifiable: exit 2 ledger_unverifiable(jq missing), branch and meta-base unchanged (rc=$RC: $OUT)"
ms B push; { [ "$RC" -eq 0 ] && grep -q '"n":3' < <(br_show .supervisor/postmortem/results.jsonl); }; check $? "... and with jq back the same ledger push lands (rc=$RC: $OUT)"
mkdir -p "$W/cshim"
cat > "$W/cshim/git" <<SHIM
#!/bin/sh
# fault injection: a candidate blob the scrub cannot read back (git -C <root> cat-file blob <sha>)
if [ "\$3" = "cat-file" ] && [ "\$4" = "blob" ]; then exit 128; fi
exec "$REAL_GIT" "\$@"
SHIM
chmod +x "$W/cshim/git"
put B "$RQ/ur.md" "plain clean text"
tip="$(br_tip)"; base_before="$(base_of B)"
OUT="$(PATH="$W/cshim:$PATH" bash "$SCRIPT" push --root "$W/B" 2>&1)"; RC=$?
{ [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub $RQ/ur.md: unreadable" < <(printf '%s\n' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "a candidate the scrub cannot read -> exit 2 unreadable, branch and meta-base unchanged (rc=$RC: $OUT)"

echo "== 34. push-retry exhaustion: an origin that rejects every push =="
# The bound is the script's own MAX_ATTEMPTS (read here, never hard-coded). Attempts are counted by
# an independent observer (the origin's pre-receive hook), and every `git push` argv the script
# runs is logged by a PATH git shim (the technique legs 22 and 27 use). The SUT calls
# `git -C <root> push ...`, so the shim scans every argument for the verb, not just $1.
PX_N="$(grep -E '^MAX_ATTEMPTS=[0-9]+$' "$SUTB" | cut -d= -f2)"
# push_exhaust_world — synced pair, B holds one local change, origin's pre-receive rejects every push
# (one log line per invocation), and a git shim dir that logs each push argv as `[arg] [arg] ...`.
push_exhaust_world() {
  synced_pair
  put B "$RQ/y.md" "y v2 (rejected every time)"
  PX_TIP="$(br_tip)"; cp "$W/B/.git/meta-base" "$W/px-base.before"
  : > "$W/px-hook.log"; : > "$W/px-push.log"
  cat > "$W/origin.git/hooks/pre-receive" <<HOOK
#!/bin/sh
echo invoked >> "$W/px-hook.log"
cat > /dev/null
exit 1
HOOK
  chmod +x "$W/origin.git/hooks/pre-receive"
  mkdir -p "$W/pxshim"
  cat > "$W/pxshim/git" <<SHIM
#!/bin/sh
for a in "\$@"; do
  if [ "\$a" = "push" ]; then
    { printf '[%s] ' "\$@"; echo; } >> "$W/px-push.log"
    break
  fi
done
exec "$REAL_GIT" "\$@"
SHIM
  chmod +x "$W/pxshim/git"
}
# push_exhaust_run — run the SUT (or the current mutant) push from B through the shim; sets OUT / RC.
push_exhaust_run() {
  OUT="$(PATH="$W/pxshim:$PATH" bash "$SCRIPT" push --root "$W/B" 2>&1)"; RC=$?
  rm -f "$W/origin.git/hooks/pre-receive"
}
# px_failed_closed — the AC-1 headline: exit 1 with the exact push_failed line naming N.
px_failed_closed() {
  [ "$RC" -eq 1 ] && grep -qF "meta_sync: push_failed — rejected $PX_N times; nothing forced, meta-base untouched" < <(printf '%s\n' "$OUT")
}
px_hooks() { wc -l < "$W/px-hook.log" | tr -d ' '; }
px_pushes() { wc -l < "$W/px-push.log" | tr -d ' '; }
case "$PX_N" in ''|*[!0-9]*) false ;; *) [ "$PX_N" -ge 2 ] ;; esac
check $? "fixture: MAX_ATTEMPTS read from meta-sync.sh is a number >= 2 (N='$PX_N'), so retries are exercised"
push_exhaust_world
push_exhaust_run
px_failed_closed
check $? "exhausted retries -> exit 1 'push_failed — rejected $PX_N times; nothing forced, meta-base untouched' (rc=$RC: $OUT)"
[ "$(br_tip)" = "$PX_TIP" ]; check $? "exhausted retries -> the branch tip on origin is unchanged"
cmp -s "$W/px-base.before" "$W/B/.git/meta-base"; check $? "exhausted retries -> B's meta-base is byte-unchanged"
[ "$(px_hooks)" = "$PX_N" ]; check $? "the origin's pre-receive ran exactly MAX_ATTEMPTS=$PX_N times (hook log: $(px_hooks))"
{ [ "$(px_pushes)" = "$PX_N" ] \
  && ! grep -qE '\[(--force[^]]*|-[A-Za-z]*f[A-Za-z]*|\+[^]]*)\]' "$W/px-push.log"; }
check $? "the git shim logged exactly $PX_N push argvs (got $(px_pushes)), none with --force*, -f or a +refspec (log: $(tr '\n' '|' < "$W/px-push.log"))"

echo "== 35. meta-base object missing from the object store -> no-base (history-aware) derivation =="
# Fixed fixture: a well-formed but NONEXISTENT tree sha in <gitdir>/meta-base. (Deleting the gc
# anchor and pruning does not work: the SUT fetches R before load_base, and after a pull the
# meta-base tree is R's tree — part of branch history — so the fetch restores the object.)
MB_SHA="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
MB_WARN="meta_sync: meta-base '$MB_SHA' is missing from the object store — falling back to the no-base (history-aware) derivation"
# missing_base_world — synced pair; A deletes d.md and pushes, so B's untouched d.md equals a
# historical blob; B's meta-base then records MB_SHA. Returns 1 when the fixture did not take.
missing_base_world() {
  synced_pair
  rm "$W/A/$RQ/d.md"; ms A push
  { [ "$RC" -eq 0 ] && ! br_has "$RQ/d.md" && [ "$(get B "$RQ/d.md")" = "d v1" ]; } || return 1
  printf '%s\n' "$MB_SHA" > "$W/B/.git/meta-base"
  ! git -C "$W/B" cat-file -e "$MB_SHA^{tree}" 2>/dev/null
}
missing_base_world; check $? "fixture: d.md deleted on the branch, B still holds 'd v1', B's meta-base tree $MB_SHA is absent from B's object store"
put B "$RQ/new35.md" "brand new from B"
ms B push
{ [ "$RC" -eq 0 ] && grep -qF "$MB_WARN" < <(printf '%s\n' "$OUT"); }
check $? "push with a missing meta-base object -> exit 0 and the 'missing from the object store' warning naming the sha (rc=$RC: $OUT)"
! br_has "$RQ/d.md"; check $? "push (no-base derivation): the branch-deleted d.md is NOT re-added (branch d.md: '$(br_show "$RQ/d.md")')"
[ "$(br_show "$RQ/new35.md")" = "brand new from B" ]; check $? "push (no-base derivation): the genuinely new local file IS pushed"
missing_base_world; check $? "fixture (pull): missing meta-base object state rebuilt"
ms B pull
{ [ "$RC" -eq 0 ] && grep -qF "$MB_WARN" < <(printf '%s\n' "$OUT") && [ ! -e "$W/B/$RQ/d.md" ]; }
check $? "pull with a missing meta-base object -> exit 0, the same warning, and d.md deleted locally, not resurrected (rc=$RC: $OUT)"
missing_base_world; check $? "fixture (conflict): missing meta-base object state rebuilt"
put B "$RQ/x.md" "x edited away from every historical blob"
put B "$RQ/new35.md" "listed new file"
printf '%s\n' "$RQ/new35.md" > "$W/list35.txt"
tip="$(br_tip)"
ms B push --paths-from "$W/list35.txt"
{ [ "$RC" -eq 1 ] && grep -qF "meta_sync: conflict $RQ/x.md" < <(printf '%s\n' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$MB_SHA" ]; }
check $? "missing meta-base object + an unlisted conflict -> the --paths-from push exits 1 naming it, branch tip and meta-base unchanged (whole-set derivation) (rc=$RC: $OUT)"

echo "== 38. symlinks under requirements/: a non-managed FILE is ignored (never synced, not refused); a dangling or managed-.md one refuses =="
# design_png_world — synced pair; B holds requirements/q/design.png -> a regular file OUTSIDE
# .supervisor/, a pending take-R (A's x.md v2) and a genuinely local change (B's y.md v2).
design_png_world() {
  synced_pair
  mkdir -p "$W/outside"; printf 'png bytes\n' > "$W/outside/design.png"
  ln -s "$W/outside/design.png" "$W/B/$RQ/design.png"
  put A "$RQ/x.md" "x v2 from A"; ms A push
  put B "$RQ/y.md" "y v2 from B"
}
# design_png_sync — pull then push from B through $SCRIPT; 0 iff both exit 0, neither prints a
# `meta_sync: symlink` line, x.md arrived, y.md was published and the branch holds no design.png.
DP_DETAIL=""
design_png_sync() {
  local prc pout
  ms B pull; prc=$RC; pout="$OUT"
  ms B push
  DP_DETAIL="pull rc=$prc: $(printf '%s' "$pout" | tr '\n' '|'); push rc=$RC: $(printf '%s' "$OUT" | tr '\n' '|')"
  [ "$prc" -eq 0 ] && [ "$RC" -eq 0 ] || return 1
  grep -q 'meta_sync: symlink' < <(printf '%s\n%s\n' "$pout" "$OUT") && return 1
  [ "$(get B "$RQ/x.md")" = "x v2 from A" ] && [ "$(br_show "$RQ/y.md")" = "y v2 from B" ] || return 1
  ! grep -q 'design\.png' < <(br_names)
}
design_png_world
design_png_sync
check $? "a symlinked non-managed FILE (requirements/q/design.png -> a file outside .supervisor/) -> pull and push exit 0, no 'meta_sync: symlink' line, the branch carries no design.png ($DP_DETAIL)"
[ "$(cat "$W/outside/design.png")" = "png bytes" ] && [ -L "$W/B/$RQ/design.png" ]
check $? "... and the symlink and its target are left exactly as they were"
echo "-- a DANGLING symlink under requirements/ still refuses (it could become a folder of .md files) --"
synced_pair
ln -s "$W/nowhere/gone" "$W/B/$RQ/gone"
put A "$RQ/x.md" "x v2 from A"; ms A push
tip="$(br_tip)"; base_before="$(base_of B)"; names_before="$(br_names)"
ms B pull
{ [ "$RC" -eq 1 ] && grep -qxF "meta_sync: symlink $RQ/gone" < <(printf '%s\n' "$OUT") && [ "$(get B "$RQ/x.md")" = "x v1" ] && [ "$(base_of B)" = "$base_before" ] && [ "$(br_tip)" = "$tip" ]; }
check $? "pull with a dangling symlink -> exit 1 'meta_sync: symlink $RQ/gone', pending x.md not written, branch tip and meta-base unchanged (rc=$RC: $OUT)"
put B "$RQ/y.md" "y v2 from B"; ms B push
{ [ "$RC" -eq 1 ] && grep -qxF "meta_sync: symlink $RQ/gone" < <(printf '%s\n' "$OUT") && [ "$(br_tip)" = "$tip" ] && [ "$(br_names)" = "$names_before" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "push with a dangling symlink -> exit 1 naming it, branch tip unchanged, nothing deleted from the branch, meta-base unchanged (rc=$RC: $OUT)"
rm -f "$W/B/$RQ/gone"
echo "-- a symlinked managed .md (to a regular file) still refuses on pull too --"
mkdir -p "$W/outside"; printf 'victim\n' > "$W/outside/victim.md"
ln -s "$W/outside/victim.md" "$W/B/$RQ/link.md"
ms B pull
{ [ "$RC" -eq 1 ] && grep -qxF "meta_sync: symlink $RQ/link.md" < <(printf '%s\n' "$OUT") && [ "$(get B "$RQ/x.md")" = "x v1" ] && [ "$(base_of B)" = "$base_before" ] && [ "$(cat "$W/outside/victim.md")" = "victim" ]; }
check $? "pull with a symlinked managed .md -> exit 1 naming it, nothing written (target untouched), meta-base unchanged (rc=$RC: $OUT)"
rm -f "$W/B/$RQ/link.md"

echo "== 39. fetch fallback: a git that rejects --no-write-fetch-head (git < 2.29) =="
# mk_ff_shim <dir> <log> — a `git` that rejects ANY invocation carrying --no-write-fetch-head the
# way git's own parse-options does (exit 129, "error: unknown option \`no-write-fetch-head'"),
# logging FLAGGED; every other fetch is logged PLAIN; everything is otherwise the real git. The
# SUT calls `git -C <root> fetch ...`, so the shim scans every argument, not just $1.
mk_ff_shim() {
  mkdir -p "$1"
  cat > "$1/git" <<SHIM
#!/bin/sh
fetch=0
for a in "\$@"; do
  if [ "\$a" = "--no-write-fetch-head" ]; then
    echo FLAGGED >> "$2"
    echo "error: unknown option \\\`no-write-fetch-head'" >&2
    echo "usage: git fetch [<options>] [<repository> [<refspec>...]]" >&2
    exit 129
  fi
  [ "\$a" = "fetch" ] && fetch=1
done
[ "\$fetch" = 1 ] && echo PLAIN >> "$2"
exec "$REAL_GIT" "\$@"
SHIM
  chmod +x "$1/git"
}
FF_LOG=""
# fetch_fallback_ok — B pulls A's x.md v2 then pushes y.md v2, both through the shim; 0 iff both
# exit 0 with the content right AND each run's log reads exactly FLAGGED then PLAIN.
FF_DETAIL=""
fetch_fallback_ok() {
  local prc pout plog
  synced_pair
  put A "$RQ/x.md" "x v2 from A"; ms A push
  mk_ff_shim "$W/ffshim" "$W/ff-pull.log"; : > "$W/ff-pull.log"
  OUT="$(PATH="$W/ffshim:$PATH" bash "$SCRIPT" pull --root "$W/B" 2>&1)"; prc=$?; pout="$OUT"
  plog="$(tr '\n' ' ' < "$W/ff-pull.log")"
  put B "$RQ/y.md" "y v2 from B"
  mk_ff_shim "$W/ffshim" "$W/ff-push.log"; : > "$W/ff-push.log"
  OUT="$(PATH="$W/ffshim:$PATH" bash "$SCRIPT" push --root "$W/B" 2>&1)"; RC=$?
  FF_LOG="pull: $plog/ push: $(tr '\n' ' ' < "$W/ff-push.log")"
  FF_DETAIL="pull rc=$prc: $(printf '%s' "$pout" | tr '\n' '|'); push rc=$RC: $(printf '%s' "$OUT" | tr '\n' '|'); shim log $FF_LOG"
  [ "$prc" -eq 0 ] && [ "$(get B "$RQ/x.md")" = "x v2 from A" ] && [ "$plog" = "FLAGGED PLAIN " ] || return 1
  [ "$RC" -eq 0 ] && [ "$(br_show "$RQ/y.md")" = "y v2 from B" ] && [ "$(tr '\n' ' ' < "$W/ff-push.log")" = "FLAGGED PLAIN " ]
}
fetch_fallback_ok
check $? "a git rejecting --no-write-fetch-head (exit 129) -> pull and push retry with a plain fetch and succeed with the right content ($FF_DETAIL)"

echo "== 40. pull: the ledger changed during the sync -> refused, NOTHING changed =="
LG=".supervisor/postmortem/results.jsonl"
AUTO=".supervisor/automate/automate-2026-01-01-000000.md"
CDS_LINE='{"repo":"owner/repo","n":99}'
# cds_world — synced pair; A appends n:3 to the ledger and changes the automate run file, then
# pushes; B appends its own unpushed n:5. So B's pull plans a UNION on the ledger and a TAKE_R on
# $AUTO, which sorts BEFORE the ledger. A git shim appends $CDS_LINE to B's ledger right AFTER the
# real git returns on the planning `hash-object --stdin-paths` (list_local hashes the ledger there;
# bare git, paths on STDIN) — inside the window, before union_into copies the working file.
cds_world() {
  synced_pair
  printf '%s\n' '{"repo":"owner/repo","n":3}' >> "$W/A/$LG"; put A "$AUTO" "run v2 from A"; ms A push
  printf '%s\n' '{"repo":"owner/repo","n":5}' >> "$W/B/$LG"
  cp "$W/B/$LG" "$W/cds-ledger.before"; cp "$W/B/.git/meta-base" "$W/cds-base.before"
  CDS_SNAP_BEFORE="$(cds_snapshot)"
  mkdir -p "$W/cdsshim"; touch "$W/cds.mark"
  cat > "$W/cdsshim/git" <<SHIM
#!/bin/sh
hit=0
for a in "\$@"; do [ "\$a" = "--stdin-paths" ] && hit=1; done
if [ "\$hit" = 1 ] && [ -f "$W/cds.mark" ]; then
  rm -f "$W/cds.mark"
  "$REAL_GIT" "\$@"; rc=\$?
  printf '%s\n' '$CDS_LINE' >> "$W/B/$LG"
  exit \$rc
fi
exec "$REAL_GIT" "\$@"
SHIM
  chmod +x "$W/cdsshim/git"
}
# cds_snapshot — every regular file under B's .supervisor/ EXCEPT the ledger, with its checksum.
cds_snapshot() {
  (cd "$W/B" && find .supervisor -type f ! -path "./$LG" ! -path "$LG" | env LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$(cksum < "$f")" "$f"; done)
}
cds_run() { OUT="$(PATH="$W/cdsshim:$PATH" bash "$SCRIPT" pull --root "$W/B" 2>&1)"; RC=$?; }
# blob_at <tree-ish> <path> — the blob SHA B's meta-base tree holds at <path> (B's object store);
# br_blob <path> — the blob SHA the branch tip holds at <path> (origin's object store).
blob_at() { git -C "$W/B" rev-parse -q --verify "$1:$2" 2>/dev/null; }
br_blob() { git --git-dir="$W/origin.git" rev-parse -q --verify "refs/heads/$BR:$1" 2>/dev/null; }
cds_world
b_base="$(sed -n 1p "$W/B/.git/meta-base")"   # line 1 = the tree (line 2 = `branch <name>`)
{ [ -n "$(blob_at "$b_base" "$AUTO")" ] && [ -n "$(br_blob "$AUTO")" ] && [ -n "$(br_blob "$LG")" ] \
  && [ "$(blob_at "$b_base" "$AUTO")" = "$(git -C "$W/B" hash-object --no-filters "$AUTO")" ] && [ "$(br_blob "$AUTO")" != "$(blob_at "$b_base" "$AUTO")" ] \
  && [ "$(git -C "$W/B" hash-object --no-filters "$LG")" != "$(blob_at "$b_base" "$LG")" ] && [ "$(br_blob "$LG")" != "$(blob_at "$b_base" "$LG")" ] \
  && [ "$(printf '%s\n' "$AUTO" "$LG" | env LC_ALL=C sort | head -n1)" = "$AUTO" ]; } 2>/dev/null
check $? "fixture: B's pull plans TAKE_R on $AUTO (L == B != R) and UNION on the ledger (L != B, R != B), and $AUTO sorts before the ledger"
cds_run
{ [ ! -e "$W/cds.mark" ] && [ "$RC" -ne 0 ] && grep -qF 'changed during the sync' < <(printf '%s\n' "$OUT"); }
check $? "the hook fired inside the window and pull exits non-zero with 'changed during the sync' (rc=$RC: $OUT)"
{ cat "$W/cds-ledger.before"; printf '%s\n' "$CDS_LINE"; } > "$W/cds-ledger.want"
cmp -s "$W/cds-ledger.want" "$W/B/$LG"; check $? "the local ledger = its pre-pull bytes + the injected line only (ledger: $(tr '\n' ' ' < "$W/B/$LG"))"
cmp -s "$W/cds-base.before" "$W/B/.git/meta-base"; check $? "meta-base is byte-unchanged"
{ [ "$(cds_snapshot)" = "$CDS_SNAP_BEFORE" ] && [ "$(get B "$AUTO")" = "run" ]; }
check $? "NO other managed file was written or deleted: the take-R $AUTO keeps its pre-pull bytes (now: '$(get B "$AUTO")')"

echo "== 41. nested stale-lock reclaim: a dead holder's lock AND a dead reclaimer's marker =="
# nested_lock_world — synced pair; A's gitdir holds meta-sync.lock (pid file = dead pid P) AND
# meta-sync.lock.reclaim.P (pid file = dead pid Q: a reclaimer that died inside its marker). A has
# one change to push. A `git` shim logs ENTER/LEAVE around the first git call inside the lock (the
# remote probe), leg 27's holder-log technique.
nested_lock_world() {
  local p q
  synced_pair
  ( exit 0 ) & p=$!; wait "$p" 2>/dev/null
  ( exit 0 ) & q=$!; wait "$q" 2>/dev/null
  NL_LOCK="$W/A/.git/meta-sync.lock"; NL_P="$p"
  mkdir "$NL_LOCK" "$NL_LOCK.reclaim.$p"
  printf '%s\n' "$p" > "$NL_LOCK/pid"; printf '%s\n' "$q" > "$NL_LOCK.reclaim.$p/pid"
  put A "$RQ/x.md" "x after a nested reclaim"
  NL_D="$W/nestlock"; mkdir -p "$NL_D/shim"; : > "$NL_D/holders.log"
  cat > "$NL_D/shim/git" <<SHIM
#!/bin/sh
if [ "\$3" = "ls-remote" ]; then
  echo "ENTER \$MS_WHO" >> "$NL_D/holders.log"; sleep "\$MS_HOLD"; echo "LEAVE \$MS_WHO" >> "$NL_D/holders.log"
fi
exec "$REAL_GIT" "\$@"
SHIM
  chmod +x "$NL_D/shim/git"
}
# nested_lock_run <wait-secs> — a push and a pull contend for A's root at once through $SCRIPT.
nested_lock_run() {
  ( MS_WHO=PUSH MS_HOLD=1 META_SYNC_LOCK_WAIT_SECS="$1" PATH="$NL_D/shim:$PATH" bash "$SCRIPT" push --root "$W/A" > "$NL_D/push.out" 2>&1; echo $? > "$NL_D/push.rc" ) &
  ( MS_WHO=PULL MS_HOLD=1 META_SYNC_LOCK_WAIT_SECS="$1" PATH="$NL_D/shim:$PATH" bash "$SCRIPT" pull --root "$W/A" > "$NL_D/pull.out" 2>&1; echo $? > "$NL_D/pull.rc" ) &
  wait
  NL_RCS="$(cat "$NL_D/push.rc" "$NL_D/pull.rc" | tr '\n' ' ')"
  NL_MAX="$(awk '$1 == "ENTER" { n++; if (n > m) m = n } $1 == "LEAVE" { n-- } END { print m + 0 }' "$NL_D/holders.log")"
  NL_ENTERS="$(grep -c ENTER "$NL_D/holders.log")"
  NL_LEFT="$(ls -a "$W/A/.git" | grep '^meta-sync\.lock' | tr '\n' ' ')"
  NL_DETAIL="rcs=$NL_RCS max=$NL_MAX enters=$NL_ENTERS left=[$NL_LEFT] push: $(tr '\n' '|' < "$NL_D/push.out") pull: $(tr '\n' '|' < "$NL_D/pull.out")"
}
nested_lock_ok() {
  [ "$NL_RCS" = "0 0 " ] && [ "$NL_MAX" = "1" ] && [ "$NL_ENTERS" = "2" ] && [ -z "$NL_LEFT" ] && [ "$(br_show "$RQ/x.md")" = "x after a nested reclaim" ]
}
nested_lock_world
{ [ -d "$NL_LOCK" ] && [ -d "$NL_LOCK.reclaim.$NL_P" ]; }; check $? "fixture: the dead holder's lock and the dead reclaimer's marker are both planted"
nested_lock_run 30
nested_lock_ok
check $? "both are reclaimed (neither directory remains), push and pull both exit 0, the push lands, never two holders ($NL_DETAIL)"

echo "== 42. a DIRECTORY at <gitdir>/meta-base: pull and push refuse up front, nothing changed =="
# dirbase_world — synced pair; A pushes x.md v2 (a remote change B would pull); B adds a genuinely
# new file (a local change B would push — new, so the no-base derivation a directory meta-base
# reads as pushes it rather than calling it a conflict); B's meta-base is then a directory.
dirbase_world() {
  synced_pair
  put A "$RQ/x.md" "x v2 from A"; ms A push
  put B "$RQ/new42.md" "new from B"
  rm -f "$W/B/.git/meta-base"; mkdir "$W/B/.git/meta-base"
  DB_TIP="$(br_tip)"
}
db_refused() {
  [ "$RC" -eq 1 ] && grep -q 'meta_sync: .*meta-base.*not a regular file.*is a directory' < <(printf '%s\n' "$OUT") \
    && [ -d "$W/B/.git/meta-base" ] && [ -z "$(ls -A "$W/B/.git/meta-base")" ] && [ "$(br_tip)" = "$DB_TIP" ] \
    && [ "$(get B "$RQ/x.md")" = "x v1" ] && [ "$(get B "$RQ/new42.md")" = "new from B" ]
}
dirbase_world
ms B push
db_refused && ! br_has "$RQ/new42.md"
check $? "push against a directory meta-base -> exit 1 naming meta-base 'not a regular file (it is a directory)', nothing published (tip unchanged), the directory left empty in place, no local file touched (rc=$RC: $OUT)"
ms B pull
db_refused
check $? "pull against a directory meta-base -> exit 1 the same, the pending take-R x.md NOT written, the directory left empty in place (rc=$RC: $OUT)"

echo "== 43. the default branch comes from the checkout's mode line =="
TW="throwaway-meta"
# tw_world — origin with BOTH metadata branches: loomwright-meta (initialised from clone Z, which
# has no mode line) and $TW (initialised from clone T, whose mode line names $TW — written by
# `setup-memory.sh apply --branch-mode`, the real writer). World building always runs the shipped
# $SUT; the subject under test is $SCRIPT.
mode_line() {
  (cd "$W/$1" && bash "$HERE/setup-memory.sh" --root "$W/$1" apply --branch-mode "$2" >/dev/null 2>&1; rm -f .gitignore.backup.*)
}
br_tip_of() { git --git-dir="$W/origin.git" rev-parse -q --verify "refs/heads/$1" 2>/dev/null; }
br_show_of() { git --git-dir="$W/origin.git" show "refs/heads/$1:$2" 2>/dev/null; }
tw_world() {
  mkworld; clone Z; clone T
  bash "$SUT" init --root "$W/Z" >/dev/null 2>&1
  mode_line T "$TW"
  bash "$SUT" init --root "$W/T" >/dev/null 2>&1
  LM_TIP="$(br_tip_of "$BR")"
}
# tw_push_ok — T pushes a new file with NO flag through $SCRIPT; 0 iff it lands on $TW and the
# real loomwright-meta ref is untouched.
tw_push_ok() {
  put T "$RQ/tw.md" "on the throwaway branch"
  ms T push
  [ "$RC" -eq 0 ] && [ "$(br_show_of "$TW" "$RQ/tw.md")" = "on the throwaway branch" ] && [ "$(br_tip_of "$BR")" = "$LM_TIP" ]
}
tw_world
{ [ "$(bash "$HERE/setup-memory.sh" --root "$W/T" mode)" = "on $TW" ] && [ "$(bash "$HERE/setup-memory.sh" --root "$W/Z" mode)" = "off" ] \
  && [ -n "$(br_tip_of "$TW")" ] && [ -n "$LM_TIP" ]; }
check $? "fixture: T's mode line reads 'on $TW' (written by setup-memory.sh apply), Z reads off; a plain 'init' in each created $TW and $BR"
tw_push_ok
check $? "a clone whose mode line names $TW pushes it with NO flag; the real $BR ref is untouched (rc=$RC: $OUT)"
ms T status
[ "$OUT" = "synced $(br_tip_of "$TW") on $TW" ]; check $? "status names the branch: 'synced <tip> on $TW' (got '$OUT')"
clone T2; mode_line T2 "$TW"
ms T2 pull
{ [ "$RC" -eq 0 ] && [ "$(get T2 "$RQ/tw.md")" = "on the throwaway branch" ] && [ "$(br_tip_of "$BR")" = "$LM_TIP" ]; }
check $? "a second clone with the same mode line pulls $TW with no flag (rc=$RC: $OUT)"
echo "-- a --branch that disagrees with the mode line is refused, for every subcommand --"
tw_tip="$(br_tip_of "$TW")"; base_before="$(base_of T)"; fh_before="$(cksum < "$W/T/.git/FETCH_HEAD" 2>/dev/null)"
put T "$RQ/tw.md" "a change that must not move"
for sc in pull push status init; do
  ms T "$sc" --branch "$BR"
  { [ "$RC" -eq 1 ] && grep -q "^meta_sync: branch_mismatch — --branch '$BR' but this checkout's mode line names '$TW'" < <(printf '%s\n' "$OUT") \
    && [ "$(br_tip_of "$TW")" = "$tw_tip" ] && [ "$(br_tip_of "$BR")" = "$LM_TIP" ] && [ "$(base_of T)" = "$base_before" ] \
    && [ ! -e "$W/T/.git/meta-sync.lock" ] && [ "$(cksum < "$W/T/.git/FETCH_HEAD" 2>/dev/null)" = "$fh_before" ] && [ "$(get T "$RQ/tw.md")" = "a change that must not move" ]; }
  check $? "$sc --branch $BR under mode 'on $TW' -> exit 1 branch_mismatch naming both, nothing changed (no fetch result, no lock, both branches and meta-base untouched) (rc=$RC: $OUT)"
done
ms T push --branch "$TW"
{ [ "$RC" -eq 0 ] && [ "$(br_show_of "$TW" "$RQ/tw.md")" = "a change that must not move" ]; }; check $? "--branch equal to the mode's branch proceeds (rc=$RC: $OUT)"
ms T pull --allow-branch-mismatch
{ [ "$RC" -eq 1 ] && grep -qF 'meta_sync: usage: --allow-branch-mismatch requires --branch' < <(printf '%s\n' "$OUT"); }
check $? "--allow-branch-mismatch without --branch -> usage error exit 1 (rc=$RC: $OUT)"
clone T3; mode_line T3 "$TW"
ms T3 pull --branch "$BR" --allow-branch-mismatch
{ [ "$RC" -eq 0 ] && [ -f "$W/T3/.git/meta-base" ] && [ ! -e "$W/T3/$RQ/tw.md" ]; }
check $? "--branch $BR --allow-branch-mismatch overrides the mode line and pulls $BR (rc=$RC: $OUT)"
ms T3 status --branch "$BR" --allow-branch-mismatch
[ "$OUT" = "synced $LM_TIP on $BR" ]; check $? "... and status under the override names $BR (got '$OUT')"
echo "-- no mode line => loomwright-meta; a mode line naming loomwright-meta behaves the same --"
put Z "$RQ/z.md" "on the default branch"
tw_tip="$(br_tip_of "$TW")"
ms Z push
{ [ "$RC" -eq 0 ] && [ "$(br_show_of "$BR" "$RQ/z.md")" = "on the default branch" ] && [ "$(br_tip_of "$TW")" = "$tw_tip" ]; }
check $? "a clone with NO mode line pushes $BR with no flag, $TW untouched (rc=$RC: $OUT)"
LM_TIP="$(br_tip_of "$BR")"
ms Z status; [ "$OUT" = "synced $LM_TIP on $BR" ]; check $? "status (mode off) -> 'synced <tip> on $BR' (got '$OUT')"
clone P; mode_line P "$BR"
[ "$(bash "$HERE/setup-memory.sh" --root "$W/P" mode)" = "on $BR" ]; check $? "fixture: P's mode line reads 'on $BR'"
ms P pull
{ [ "$RC" -eq 0 ] && [ "$(get P "$RQ/z.md")" = "on the default branch" ]; }; check $? "mode 'on $BR' with no flag pulls $BR (rc=$RC: $OUT)"
put P "$RQ/p.md" "from P"; ms P push --branch "$BR"
{ [ "$RC" -eq 0 ] && [ "$(br_show_of "$BR" "$RQ/p.md")" = "from P" ] && [ "$(br_tip_of "$TW")" = "$tw_tip" ]; }
check $? "mode 'on $BR' accepts --branch $BR (the primary's unchanged path) (rc=$RC: $OUT)"
echo "-- an unknown mode is refused, with no flag and with a bare --branch --"
clone U; mode_line U "$TW"
sed "s/^# loomwright-meta-branch: .*/# loomwright-meta-branch: off/" "$W/U/.gitignore" > "$W/U/.gitignore.new" && mv "$W/U/.gitignore.new" "$W/U/.gitignore"
um="$(bash "$HERE/setup-memory.sh" --root "$W/U" mode)"
case "$um" in "unknown "*) true ;; *) false ;; esac; check $? "fixture: U's mode reads unknown (got '$um')"
lm_tip="$(br_tip_of "$BR")"; tw_tip="$(br_tip_of "$TW")"
for args in "pull" "status" "push --branch $BR" "pull --branch $TW"; do
  # shellcheck disable=SC2086
  ms U $args
  { [ "$RC" -eq 1 ] && grep -qxF "meta_sync: mode_unknown — ${um#unknown }; nothing was changed (repair the mode line with setup-memory.sh apply --branch-mode <branch>|off, or pass --branch <name> --allow-branch-mismatch)" < <(printf '%s\n' "$OUT") \
    && [ ! -e "$W/U/.git/meta-base" ] && [ ! -e "$W/U/.git/meta-sync.lock" ] && [ ! -e "$W/U/.supervisor/requirements" ] && [ "$(br_tip_of "$BR")" = "$lm_tip" ] && [ "$(br_tip_of "$TW")" = "$tw_tip" ]; }
  check $? "'$args' under an unknown mode -> exit 1 'meta_sync: mode_unknown — <reason>; nothing was changed', nothing changed (rc=$RC: $OUT)"
done
ms U pull --branch "$BR" --allow-branch-mismatch
{ [ "$RC" -eq 0 ] && [ "$(get U "$RQ/z.md")" = "on the default branch" ]; }; check $? "the override proceeds under an unknown mode (rc=$RC: $OUT)"
echo "-- a failed reader (no sibling setup-memory.sh) fails closed, even in a mode-off clone --"
NORD="$TROOT/no-reader"; mkdir -p "$NORD"; cp "$SUT" "$NORD/meta-sync.sh"
lm_tip="$(br_tip_of "$BR")"; base_before="$(base_of Z)"
put Z "$RQ/z.md" "must not be pushed"
OUT="$(bash "$NORD/meta-sync.sh" push --root "$W/Z" 2>&1)"; RC=$?
{ [ "$RC" -eq 1 ] && grep -qF 'meta_sync: mode_unknown — setup-memory.sh (the mode-line reader) is missing beside meta-sync.sh; nothing was changed' < <(printf '%s\n' "$OUT") \
  && [ "$(br_tip_of "$BR")" = "$lm_tip" ] && [ "$(base_of Z)" = "$base_before" ]; }
check $? "a copy with no sibling setup-memory.sh -> exit 1 mode_unknown, never the default branch (rc=$RC: $OUT)"
printf '#!/bin/sh\nexit 3\n' > "$NORD/setup-memory.sh"
OUT="$(bash "$NORD/meta-sync.sh" status --root "$W/Z" 2>&1)"; RC=$?
{ [ "$RC" -eq 1 ] && grep -qF 'meta_sync: mode_unknown — setup-memory.sh mode exited 3; nothing was changed' < <(printf '%s\n' "$OUT"); }
check $? "a reader that exits non-zero with no line -> exit 1 mode_unknown (rc=$RC: $OUT)"
printf '#!/bin/sh\nprintf "on a\\\\non b\\\\n"\n' > "$NORD/setup-memory.sh"
OUT="$(bash "$NORD/meta-sync.sh" status --root "$W/Z" 2>&1)"; RC=$?
{ [ "$RC" -eq 1 ] && grep -qF "meta_sync: mode_unknown — setup-memory.sh mode returned a multi-line answer (first line 'on a')" < <(printf '%s\n' "$OUT"); }
check $? "a multi-line reader answer -> exit 1 mode_unknown (rc=$RC: $OUT)"
printf '#!/bin/sh\necho maybe\n' > "$NORD/setup-memory.sh"
OUT="$(bash "$NORD/meta-sync.sh" status --root "$W/Z" 2>&1)"; RC=$?
{ [ "$RC" -eq 1 ] && grep -qF "meta_sync: mode_unknown — setup-memory.sh mode printed 'maybe'" < <(printf '%s\n' "$OUT"); }
check $? "an unrecognised reader answer -> exit 1 mode_unknown (rc=$RC: $OUT)"

echo "== 50. meta-base is bound to its branch: a branch switch never plans against the old base =="
LZ="lane-z"
# bsw_world — clone A syncs loomwright-meta (mode off; meta-base bound to it), then switches its
# mode line to $LZ with the real writer and inits $LZ (empty). World building always runs $SUT.
bsw_world() {
  mkworld; clone A
  bash "$SUT" init --root "$W/A" >/dev/null 2>&1
  put A "$RQ/a.md" "a v1"; put A "$RQ/b.md" "b v1"
  bash "$SUT" push --root "$W/A" >/dev/null 2>&1
  mode_line A "$LZ"
  bash "$SUT" init --root "$W/A" >/dev/null 2>&1
  BSW_LM_TIP="$(br_tip_of "$BR")"; BSW_LZ_TIP="$(br_tip_of "$LZ")"
  BSW_LM_NAMES="$(git --git-dir="$W/origin.git" ls-tree -r --name-only "refs/heads/$BR" 2>/dev/null)"
  BSW_BASE="$(base_of A)"
}
# bsw_untouched — 0 iff A's local files, both branches and meta-base are exactly as bsw_world left them.
bsw_untouched() {
  [ "$(get A "$RQ/a.md")" = "a v1" ] && [ "$(get A "$RQ/b.md")" = "b v1" ] \
    && [ "$(br_tip_of "$BR")" = "$BSW_LM_TIP" ] && [ "$(br_tip_of "$LZ")" = "$BSW_LZ_TIP" ] \
    && [ "$(base_of A)" = "$BSW_BASE" ] && [ ! -e "$W/A/.git/meta-sync.lock" ]
}
BSW_MSG="meta_sync: base_branch_mismatch — meta-base was recorded against branch '$BR' but this sync targets '$LZ'; nothing was changed"
bsw_world
{ [ "$(bash "$HERE/setup-memory.sh" --root "$W/A" mode)" = "on $LZ" ] && [ -n "$BSW_LZ_TIP" ] && [ -z "$(git --git-dir="$W/origin.git" ls-tree -r --name-only "refs/heads/$LZ")" ] \
  && [ "$(sed -n 2p "$W/A/.git/meta-base")" = "branch $BR" ] && [ "$BSW_LM_NAMES" = "$(printf '%s\n' "$RQ/a.md" "$RQ/b.md")" ]; }
check $? "fixture: A's mode line reads 'on $LZ', $LZ is an empty fresh branch, A's meta-base line 2 is 'branch $BR', $BR holds a.md + b.md"
ms A status
{ [ "$RC" -eq 0 ] && [ "$OUT" = "base_branch_mismatch" ]; }; check $? "status after the switch -> base_branch_mismatch, exit 0 (got '$OUT' rc=$RC)"
ms A pull
{ [ "$RC" -eq 1 ] && grep -qF "$BSW_MSG" < <(printf '%s\n' "$OUT") && ! grep -qF 'pulled' < <(printf '%s\n' "$OUT") && bsw_untouched; }
check $? "plain pull after the switch -> exit 1 base_branch_mismatch naming both; a.md / b.md NOT deleted, both branches and meta-base unchanged (rc=$RC: $OUT)"
put A "$RQ/n.md" "new after switch"
ms A push
{ [ "$RC" -eq 1 ] && grep -qF "$BSW_MSG" < <(printf '%s\n' "$OUT") && bsw_untouched; }
check $? "push after the switch -> exit 1 base_branch_mismatch, nothing published to either branch, meta-base unchanged (rc=$RC: $OUT)"
ms A pull --branch "$LZ" --allow-branch-mismatch
{ [ "$RC" -eq 1 ] && grep -qF "$BSW_MSG" < <(printf '%s\n' "$OUT") && bsw_untouched; }
check $? "the forced-branch path (--branch $LZ --allow-branch-mismatch) is refused the same way (rc=$RC: $OUT)"
rm -f "$W/A/$RQ/n.md"
ms A pull --branch "$BR" --allow-branch-mismatch
{ [ "$RC" -eq 0 ] && grep -qF 'meta_sync: pulled' < <(printf '%s\n' "$OUT") && bsw_untouched; }
check $? "the base's own branch still syncs (--branch $BR --allow-branch-mismatch): exit 0, nothing deleted (rc=$RC: $OUT)"
rm -f "$W/A/.git/meta-base"
ms A pull
{ [ "$RC" -eq 0 ] && grep -qF '(0 written, 0 deleted)' < <(printf '%s\n' "$OUT") && [ "$(get A "$RQ/a.md")" = "a v1" ] && [ "$(get A "$RQ/b.md")" = "b v1" ] \
  && [ "$(sed -n 2p "$W/A/.git/meta-base")" = "branch $LZ" ]; }
check $? "with meta-base removed by hand, the plain pull of $LZ is a first sync: nothing deleted, meta-base now bound to $LZ (rc=$RC: $OUT)"
ms A push
{ [ "$RC" -eq 0 ] && [ "$(br_show_of "$LZ" "$RQ/a.md")" = "a v1" ] && [ "$(br_show_of "$LZ" "$RQ/b.md")" = "b v1" ] && [ "$(br_tip_of "$BR")" = "$BSW_LM_TIP" ]; }
check $? "... and the next push carries a.md / b.md onto $LZ, $BR untouched (rc=$RC: $OUT)"

echo "== 51. a legacy (single-line) meta-base: adopted only when the target branch's history holds every entry =="
mkworld; clone A
bash "$SUT" init --root "$W/A" >/dev/null 2>&1
put A "$RQ/a.md" "a v1"; put A "$RQ/b.md" "b v1"
bash "$SUT" push --root "$W/A" >/dev/null 2>&1
sed -n 1p "$W/A/.git/meta-base" > "$W/A/.git/meta-base.legacy" && mv "$W/A/.git/meta-base.legacy" "$W/A/.git/meta-base"
[ "$(awk 'END { print NR }' "$W/A/.git/meta-base")" = "1" ]; check $? "fixture: A's meta-base rewritten to the legacy single-line form"
put A "$RQ/a.md" "a v2 local"
ms A push
{ [ "$RC" -eq 0 ] && [ "$(br_show "$RQ/a.md")" = "a v2 local" ] && [ "$(br_show "$RQ/b.md")" = "b v1" ] && [ "$(sed -n 2p "$W/A/.git/meta-base")" = "branch $BR" ]; }
check $? "a legacy base taken from the SAME branch is adopted (a local edit pushes as take-L, not a no-base conflict) and the rewrite binds it to $BR (rc=$RC: $OUT)"
sed -n 1p "$W/A/.git/meta-base" > "$W/A/.git/meta-base.legacy" && mv "$W/A/.git/meta-base.legacy" "$W/A/.git/meta-base"
LEG_BASE="$(base_of A)"
mode_line A "$LZ"
bash "$SUT" init --root "$W/A" >/dev/null 2>&1
lm_tip="$(br_tip_of "$BR")"; lz_tip="$(br_tip_of "$LZ")"
ms A status
{ [ "$RC" -eq 0 ] && [ "$OUT" = "base_branch_mismatch" ]; }; check $? "status with a legacy base from another branch -> base_branch_mismatch (got '$OUT' rc=$RC)"
ms A pull
{ [ "$RC" -eq 1 ] && grep -qF "meta_sync: base_branch_mismatch — the legacy meta-base " < <(printf '%s\n' "$OUT") && grep -qF "/.git/meta-base records no branch and holds 2 entr(y/ies) '$LZ''s history never held" < <(printf '%s\n' "$OUT") \
  && [ "$(get A "$RQ/a.md")" = "a v2 local" ] && [ "$(get A "$RQ/b.md")" = "b v1" ] && [ "$(base_of A)" = "$LEG_BASE" ] \
  && [ "$(br_tip_of "$BR")" = "$lm_tip" ] && [ "$(br_tip_of "$LZ")" = "$lz_tip" ]; }
check $? "pull with a legacy base from another branch -> exit 1, a.md / b.md NOT deleted, meta-base and both branches unchanged (rc=$RC: $OUT)"
ms A push
{ [ "$RC" -eq 1 ] && grep -qF 'meta_sync: base_branch_mismatch — the legacy meta-base' < <(printf '%s\n' "$OUT") && [ "$(base_of A)" = "$LEG_BASE" ] \
  && [ "$(br_tip_of "$BR")" = "$lm_tip" ] && [ "$(br_tip_of "$LZ")" = "$lz_tip" ]; }
check $? "push with a legacy base from another branch -> exit 1, nothing published, meta-base unchanged (rc=$RC: $OUT)"
printf '%s\nbranch %s\nextra\n' "$(sed -n 1p "$W/A/.git/meta-base")" "$LZ" > "$W/A/.git/meta-base"
bad_base="$(base_of A)"
ms A pull
{ [ "$RC" -eq 1 ] && grep -qF 'meta_sync: base_branch_mismatch — meta-base' < <(printf '%s\n' "$OUT") && grep -qF 'is not in a recognised format' < <(printf '%s\n' "$OUT") \
  && [ "$(get A "$RQ/a.md")" = "a v2 local" ] && [ "$(base_of A)" = "$bad_base" ]; }
check $? "a meta-base in no recognised format (a third line) -> exit 1, nothing changed (rc=$RC: $OUT)"
ms A status; [ "$OUT" = "base_branch_mismatch" ]; check $? "... and status says base_branch_mismatch (got '$OUT')"

