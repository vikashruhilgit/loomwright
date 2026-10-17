# ============================================================================
echo "== (e) idempotency + BACKUP-BEFORE-WRITE — a second apply is a no-op that writes NOTHING =="
Ee="$(newgit https://github.com/acme/widget.git)"
printf '# junk\n.claude/\n.supervisor/\n' > "$Ee/.gitignore"
# Snapshot the PRISTINE user file BEFORE the first apply. Backup-first is the module's only
# user-data safety net, so it is asserted POSITIVELY below (the backup EXISTS and its CONTENT is
# this snapshot) — never as a count comparison across the no-op second apply, which passes as
# "0 = 0" when no backup is ever written and left `cp "$GI" "$backup"` completely unasserted.
gi_pristine="$(sum "$Ee/.gitignore")"
mem "$Ee" apply >/dev/null 2>&1
gi1="$(sum "$Ee/.gitignore")"
cfg1="$(sum "$Ee/.supervisor/config.json" 2>/dev/null || echo none)"
bk1="$(ls "$Ee"/.gitignore.backup.* 2>/dev/null | wc -l | tr -d ' ')"
bk1_path="$(ls "$Ee"/.gitignore.backup.* 2>/dev/null | head -n1)"
[ "$bk1" -eq 1 ] && ok "(e) the first apply wrote EXACTLY ONE .gitignore.backup.* (backup-before-write happened at all)" || no "(e) the first apply wrote $bk1 backup(s), expected exactly 1 — backup-before-write did NOT happen"
if [ -n "$bk1_path" ] && [ "$(sum "$bk1_path")" = "$gi_pristine" ]; then
  ok "(e) that backup holds the PRISTINE pre-apply .gitignore byte-for-byte (recoverable original)"
else
  no "(e) the backup does not match the pre-apply .gitignore — the user's original is NOT recoverable"
fi
[ "$gi1" != "$gi_pristine" ] && ok "(e) the first apply really did rewrite .gitignore (the backup is not a copy of the new file)" || no "(e) the first apply did not change .gitignore — the backup assertion above would be vacuous"
out_e="$(mem "$Ee" apply 2>&1)"; rc_e=$?
gi2="$(sum "$Ee/.gitignore")"
cfg2="$(sum "$Ee/.supervisor/config.json" 2>/dev/null || echo none)"
bk2="$(ls "$Ee"/.gitignore.backup.* 2>/dev/null | wc -l | tr -d ' ')"
[ "$rc_e" -eq 0 ] && ok "(e) second apply exits 0" || no "(e) second apply non-zero ($rc_e)"
# Anchored to the apply STATUS LINE: `seed_allowlist` prints "already configured" on every second
# apply regardless of what the .gitignore path did, so `hasi 'already configured'` was passing
# without discriminating the no-op at all.
has '^apply: no-op' "$out_e" && ok "(e) second apply reports the 'apply: no-op' status line" || no "(e) second apply did not report 'apply: no-op'"
[ "$gi1" = "$gi2" ] && ok "(e) .gitignore byte-identical after the second apply (nothing written)" || no "(e) second apply MUTATED .gitignore"
[ "$cfg1" = "$cfg2" ] && ok "(e) .supervisor/config.json byte-identical after the second apply" || no "(e) second apply MUTATED the config"
[ "$bk2" -eq 1 ] && ok "(e) still EXACTLY ONE backup after the no-op apply (it wrote none)" || no "(e) the no-op apply changed the backup count ($bk1 → $bk2)"
c1="$(mem "$Ee" check 2>/dev/null)"; c2="$(mem "$Ee" check 2>/dev/null)"
[ "$c1" = "$c2" ] && ok "(e) check stdout byte-identical across two runs" || no "(e) check stdout differed between runs"

# --- SAME-SECOND BACKUP COLLISION -------------------------------------------------------------
# The backup name is second-granular, so two applies inside one second resolve to the same path
# and the second `cp` would OVERWRITE the first backup — losing the user's pristine original and
# leaving only a copy of the tool's own output. Driven with a PINNED clock (a fake `date` first on
# PATH) so the collision is deterministic instead of a race the suite would only sometimes hit.
Ec="$(newgit https://github.com/acme/widget.git)"
printf '# junk\n.claude/\n' > "$Ec/.gitignore"
ec_pristine="$(sum "$Ec/.gitignore")"
mkdir -p "$Ec/fakebin"
printf '#!/bin/sh\necho 20260101-000000\n' > "$Ec/fakebin/date"
chmod +x "$Ec/fakebin/date"
PATH="$Ec/fakebin:$PATH" bash "$MEM" --root "$Ec" apply >/dev/null 2>&1
printf '*.log\n' >> "$Ec/.gitignore"   # forces the SECOND apply to be a real write, not a no-op
PATH="$Ec/fakebin:$PATH" bash "$MEM" --root "$Ec" apply >/dev/null 2>&1
n_bk_ec="$(ls "$Ec"/.gitignore.backup.* 2>/dev/null | wc -l | tr -d ' ')"
[ "$n_bk_ec" -eq 2 ] && ok "(e) two applies in the SAME second produce TWO distinct backups (no collision)" || no "(e) same-second applies left $n_bk_ec backup(s) — one overwrote the other"
[ "$(sum "$Ec/.gitignore.backup.20260101-000000")" = "$ec_pristine" ] && ok "(e) the FIRST backup still holds the pristine original after the same-second second apply" || no "(e) the same-second second apply OVERWROTE the user's pristine original backup"

# --- BACKUP-NAME EXHAUSTION MUST FAIL CLOSED --------------------------------------------------
# unique_backup_path escalates <file>.backup.<ts> → .<pid> → .<pid>.<n> with the counter BOUNDED,
# so "a free name always exists" is not something it can promise. It used to fall out of the loop
# AT the bound and return `.<pid>.<bound>` with that file still present — a path it never verified,
# which the caller's `cp` would then have OVERWRITTEN. It now returns EMPTY and write_gitignore
# aborts. Driven deterministically, not as a race: the clock is pinned with a fake `date` on PATH,
# and the seeding must happen while the helper is alive but has not yet run, because the candidate
# names are qualified by the helper's OWN pid — which does not exist until it is running. That
# chicken-and-egg is the only reason a handshake exists here at all.
#
# THE HANDSHAKE MUST NOT BE ABLE TO HANG THIS SUITE, ON ANY PLATFORM. This file is a HARD CI GATE
# inside a `for t in test-*.sh` loop that sets NO per-test timeout, so a wedged fixture does not
# report a failure — it burns the entire job. An earlier revision sequenced this with a FIFO, which
# put a blocking open(2) on the critical path (`echo go > fifo` blocks until a reader arrives) and
# then tried to defuse it with `exec 9<>` — O_RDWR on a FIFO, which is formally UNDEFINED in POSIX
# and therefore a portability bet, not a guarantee. Both are gone. The gate is now two plain files
# and two BOUNDED polls, so no step can block on any platform:
#   · the helper publishes its own `$$` (atomically: write-temp + rename) and then polls for `go`
#   · the parent polls for `pid`, seeds every candidate name, then creates `go`
#   · BOTH loops are capped at a fixed iteration count (~60s of budget either way). Exhaustion is
#     never silent: the helper exits 97 with a distinct message, the parent records a FAILED
#     assertion. The parent's `wait` is therefore bounded by the helper's own cap even if the
#     helper is never released, and a helper that dies early just makes `wait` return immediately.
# Fractional `sleep` is a GNU/BSD extension, not POSIX, so it is PROBED once rather than assumed —
# a shell without it falls back to whole seconds with a proportionally smaller cap, never to a
# spin that would exhaust the bound instantly and fail spuriously.
if sleep 0.05 2>/dev/null; then   # fixed-sleep-ok: capability probe (does this sleep take fractions?), not a wait
  gate_unit=0.05; gate_max=1200; else gate_unit=1; gate_max=60; fi
Ex="$(newgit https://github.com/acme/widget.git)"
printf '# junk\n.claude/\n' > "$Ex/.gitignore"
ex_pristine="$(sum "$Ex/.gitignore")"
mkdir -p "$Ex/fakebin"
printf '#!/bin/sh\necho 20260101-000000\n' > "$Ex/fakebin/date"
chmod +x "$Ex/fakebin/date"
# $1=fixture root, $2=setup-memory.sh, $3=poll unit, $4=poll cap. `$$` here is the helper's own pid
# and survives the `exec`, so it is the pid `unique_backup_path` will use.
bash -c '
  printf "%s\n" "$$" > "$1/pid.tmp" && mv -f "$1/pid.tmp" "$1/pid"
  n=0
  while [ ! -e "$1/go" ]; do
    n=$((n + 1))
    [ "$n" -le "$4" ] || { echo "fixture: helper timed out waiting for the go flag" >&2; exit 97; }
    sleep "$3"
  done
  export PATH="$1/fakebin:$PATH"
  exec bash "$2" --root "$1" apply
' _ "$Ex" "$MEM" "$gate_unit" "$gate_max" > "$Ex/out.txt" 2>&1 &
ex_job=$!
ex_pid=""; n=0
while [ "$n" -le "$gate_max" ]; do
  if [ -s "$Ex/pid" ]; then ex_pid="$(cat "$Ex/pid" 2>/dev/null)"; [ -n "$ex_pid" ] && break; fi
  n=$((n + 1)); sleep "$gate_unit"
done
[ -n "$ex_pid" ] && ok "(e) the exhaustion helper published its pid before the seeding step" || no "(e) the exhaustion helper never published a pid within the poll bound — fixture did not run"
ex_base="$Ex/.gitignore.backup.20260101-000000"
: > "$ex_base"                         # the pristine-original slot — must NOT be clobbered
if [ -n "$ex_pid" ]; then
  : > "$ex_base.$ex_pid"               # the pid-qualified fallback
  touch "$ex_base.$ex_pid."{1..1000}   # every counter slot, up to the helper's bound
fi
ex_seed_sum="$(sum "$ex_base")"
: > "$Ex/go"                           # release the helper; it calls the pinned `date` from here on
wait "$ex_job"; rc_ex=$?
ex_out="$(cat "$Ex/out.txt" 2>/dev/null)"
[ "$rc_ex" -eq 0 ] && ok "(e) apply still exits 0 when no backup name is free (fail-safe)" || no "(e) apply exited $rc_ex on backup exhaustion"
has '^apply: ABORTED' "$ex_out" && ok "(e) apply ABORTS when no non-colliding backup name can be derived" || no "(e) apply did not abort on backup exhaustion (got: $(head -n3 <<< "$ex_out"))"
# Pin the EXHAUSTION branch specifically — a generic `cp`-failure abort would satisfy the line above.
hasF 'refusing to overwrite an existing backup' "$ex_out" && ok "(e) the abort names backup-name EXHAUSTION as the reason (not a generic cp failure)" || no "(e) the abort did not come from the exhaustion branch"
[ "$(sum "$Ex/.gitignore")" = "$ex_pristine" ] && ok "(e) .gitignore is byte-identical after the exhaustion abort (nothing written)" || no "(e) .gitignore was REWRITTEN despite having no backup"
[ "$(sum "$ex_base")" = "$ex_seed_sum" ] && ok "(e) the pre-existing backup was NOT overwritten (the user's pristine original survives)" || no "(e) the exhausted path CLOBBERED an existing backup"

# ============================================================================
echo "== (f) absent / unparseable .gitignore — change nothing, say why, no partial write =="
# (f1) ABSENT — nothing is ignoring the stores, so there is nothing to negate.
F1="$(newgit)"
out_f1="$(mem "$F1" apply 2>&1)"; rc_f1=$?
[ "$rc_f1" -eq 0 ] && ok "(f1) apply on a repo with NO .gitignore exits 0 (fail-safe)" || no "(f1) non-zero on absent .gitignore ($rc_f1)"
has '^apply: ABORTED' "$out_f1" && ok "(f1) apply reports ABORTED on an absent .gitignore" || no "(f1) apply did not report ABORTED"
hasi 'no .gitignore' "$out_f1" && ok "(f1) the abort states WHY (no .gitignore)" || no "(f1) abort gave no reason"
[ ! -e "$F1/.gitignore" ] && ok "(f1) no .gitignore was created (changed nothing)" || no "(f1) apply CREATED a .gitignore"

# (f2) UNPARSEABLE — unresolved conflict markers.
F2="$(newgit)"
printf '.claude/\n<<<<<<< HEAD\n.supervisor/\n=======\n.supervisor/*\n>>>>>>> other\n' > "$F2/.gitignore"
before_f2="$(sum "$F2/.gitignore")"
out_f2="$(mem "$F2" apply 2>&1)"; rc_f2=$?
[ "$rc_f2" -eq 0 ] && ok "(f2) apply on a conflict-marked .gitignore exits 0" || no "(f2) non-zero ($rc_f2)"
has '^apply: ABORTED' "$out_f2" && ok "(f2) apply ABORTS on a conflict-marked .gitignore" || no "(f2) apply did not abort on conflict markers"
hasi 'conflict marker' "$out_f2" && ok "(f2) the abort names the reason (conflict markers)" || no "(f2) abort did not name the reason"
[ "$before_f2" = "$(sum "$F2/.gitignore")" ] && ok "(f2) .gitignore byte-identical after the abort (no partial write)" || no "(f2) .gitignore MUTATED despite the abort"
[ -z "$(ls "$F2"/.gitignore.backup.* 2>/dev/null)" ] && ok "(f2) no backup written on the abort path (nothing was staged)" || no "(f2) a backup was written despite aborting"

# (f3) UNPARSEABLE — a half-deleted managed block (hand-edited: BEGIN without END).
F3="$(newgit)"
printf '.claude/\n# >>> loomwright /setup memory BEGIN — committable Twin stores (managed block) >>>\n.claude/*\n' > "$F3/.gitignore"
before_f3="$(sum "$F3/.gitignore")"
out_f3="$(mem "$F3" apply 2>&1)"
has '^apply: ABORTED' "$out_f3" && ok "(f3) apply ABORTS on an unbalanced managed block (hand-edited)" || no "(f3) apply did not abort on an unbalanced block"
hasi 'sentinel' "$out_f3" && ok "(f3) the abort names the sentinel imbalance" || no "(f3) abort did not name the sentinel problem"
[ "$before_f3" = "$(sum "$F3/.gitignore")" ] && ok "(f3) .gitignore unchanged after the sentinel abort" || no "(f3) .gitignore MUTATED on the sentinel abort path"
# remove must abort on the same input rather than half-repairing it
out_f3r="$(mem "$F3" remove 2>&1)"
has '^remove: ABORTED' "$out_f3r" && ok "(f3) remove ABORTS on the same unparseable file (never half-repairs)" || no "(f3) remove did not abort on an unparseable file"
[ "$before_f3" = "$(sum "$F3/.gitignore")" ] && ok "(f3) .gitignore unchanged after the remove abort" || no "(f3) remove MUTATED an unparseable .gitignore"

# (f4) AN INDENTED BEGIN SENTINEL MUST NEVER PRODUCE A DUPLICATED BLOCK.
# The presence gate counts sentinels with `grep -F` (substring, anywhere on the line) while the
# stripper used to anchor at column 1. An indented BEGIN therefore passed the gate as "one valid
# block" but was NOT stripped, so apply APPENDED a second block — after which the file held
# BEGIN x2 / END x2 and every later apply AND remove aborted with "duplicated managed-block
# sentinels": a corrupt state the tool created itself and then refused to repair. One matcher now
# serves both, so the file must stay repairable by BOTH subcommands.
F4="$(newgit https://github.com/acme/widget.git)"
seed_stores "$F4"
{
  printf '# editor\n*.swp\n.claude/\n'
  printf '   # >>> loomwright /setup memory BEGIN — committable Twin stores (managed block) >>>\n'
  printf '.claude/*\n!.claude/agent-memory/\n'
  printf '   # <<< loomwright /setup memory END <<<\n'
} > "$F4/.gitignore"
out_f4="$(mem "$F4" apply 2>&1)"; rc_f4=$?
[ "$rc_f4" -eq 0 ] && ok "(f4) apply on an INDENTED-sentinel .gitignore exits 0" || no "(f4) non-zero ($rc_f4)"
nb_f4="$(grep -cF '>>> loomwright /setup memory BEGIN' "$F4/.gitignore" 2>/dev/null | tr -d ' ')"
ne_f4="$(grep -cF '<<< loomwright /setup memory END'   "$F4/.gitignore" 2>/dev/null | tr -d ' ')"
[ "${nb_f4:-0}" -eq 1 ] && [ "${ne_f4:-0}" -eq 1 ] && ok "(f4) apply left EXACTLY ONE managed block (indented sentinel stripped, never duplicated)" || no "(f4) apply left BEGIN x${nb_f4:-0} / END x${ne_f4:-0} — it duplicated the block and bricked the file"
assert_committable "$F4" "$P_MEM" "(f4) the rewritten file still makes $P_MEM committable"
# the brick state must be UNREACHABLE: both subcommands still work on the once-indented file
out_f4b="$(mem "$F4" apply 2>&1)"
hasi 'duplicated managed-block sentinels' "$out_f4b" && no "(f4) a follow-up apply is BRICKED with 'duplicated managed-block sentinels'" || ok "(f4) a follow-up apply is not bricked"
has '^apply: no-op' "$out_f4b" && ok "(f4) the follow-up apply is a clean no-op (the first pass produced canonical content)" || no "(f4) the follow-up apply was not a no-op"
out_f4r="$(mem "$F4" remove 2>&1)"; rc_f4r=$?
[ "$rc_f4r" -eq 0 ] && ok "(f4) remove exits 0 on the once-indented file" || no "(f4) remove non-zero ($rc_f4r)"
hasi 'duplicated managed-block sentinels' "$out_f4r" && no "(f4) remove is BRICKED on the same file" || ok "(f4) remove is not bricked either"
nb_f4r="$(grep -cF 'loomwright /setup memory' "$F4/.gitignore" 2>/dev/null | tr -d ' ')"
[ "${nb_f4r:-1}" -eq 0 ] && ok "(f4) remove leaves NO managed-block sentinel behind (fully repairable)" || no "(f4) remove left ${nb_f4r} managed-block line(s) behind"

# (f5) SYMLINK — the gate refuses to FOLLOW it. The point is not merely "abort": it is that
# someone else's file (the link TARGET) is never rewritten, and the link itself is left intact.
F5="$(newgit)"
printf '# someone else owns this\n.claude/\n.supervisor/\n' > "$F5/real-gitignore.txt"
target_f5="$(sum "$F5/real-gitignore.txt")"
ln -s real-gitignore.txt "$F5/.gitignore" \
  || setup_fail "(f5) ln -s failed — $F5/.gitignore could not be made a symlink"
# Assert the SHAPE, not just ln's exit status: this whole group is meaningless unless .gitignore
# really is a symlink at the moment apply runs.
[ -L "$F5/.gitignore" ] || setup_fail "(f5) $F5/.gitignore is not a symlink after ln -s"
out_f5="$(mem "$F5" apply 2>&1)"; rc_f5=$?
[ "$rc_f5" -eq 0 ] && ok "(f5) apply on a SYMLINK .gitignore exits 0 (fail-safe)" || no "(f5) non-zero ($rc_f5)"
has '^apply: ABORTED' "$out_f5" && ok "(f5) apply ABORTS on a symlinked .gitignore" || no "(f5) apply did not abort on a symlink"
hasi 'symlink' "$out_f5" && ok "(f5) the abort names the reason (symlink)" || no "(f5) abort did not name the symlink"
[ -L "$F5/.gitignore" ] && ok "(f5) .gitignore is STILL a symlink (the link was not replaced by a regular file)" || no "(f5) the symlink was clobbered"
[ "$target_f5" = "$(sum "$F5/real-gitignore.txt")" ] && ok "(f5) the symlink TARGET is byte-identical (someone else's file was not rewritten)" || no "(f5) the rewriter FOLLOWED the symlink and mutated the target"
[ -z "$(ls "$F5"/.gitignore.backup.* 2>/dev/null)" ] && ok "(f5) no backup written on the symlink abort path" || no "(f5) a backup was written despite aborting"

# (f6) NON-REGULAR FILE — a directory named .gitignore exists (`-e` true, `-f` false), so the
# absent branch must NOT swallow it and the rewriter must not try to write through it.
F6="$(newgit)"
mkdir "$F6/.gitignore" || setup_fail "(f6) mkdir failed — $F6/.gitignore could not be made a directory"
[ -d "$F6/.gitignore" ] && [ ! -L "$F6/.gitignore" ] \
  || setup_fail "(f6) $F6/.gitignore is not a plain directory after mkdir"
out_f6="$(mem "$F6" apply 2>&1)"; rc_f6=$?
[ "$rc_f6" -eq 0 ] && ok "(f6) apply on a DIRECTORY named .gitignore exits 0 (fail-safe)" || no "(f6) non-zero ($rc_f6)"
has '^apply: ABORTED' "$out_f6" && ok "(f6) apply ABORTS on a non-regular .gitignore" || no "(f6) apply did not abort on a non-regular file"
hasi 'not a regular file' "$out_f6" && ok "(f6) the abort names the reason (not a regular file)" || no "(f6) abort did not name the non-regular file"
[ -d "$F6/.gitignore" ] && ok "(f6) .gitignore is STILL a directory (nothing was written through it)" || no "(f6) the .gitignore directory was replaced"
[ -z "$(ls "$F6"/.gitignore.backup.* 2>/dev/null)" ] && ok "(f6) no backup written on the non-regular abort path" || no "(f6) a backup was written despite aborting"

# (f7) NOT READABLE/WRITABLE — `chmod 000`. SKIPPED UNDER ROOT: root bypasses the permission
# bits entirely, so `[ -r ]`/`[ -w ]` are both true there and the guard legitimately does not
# fire; asserting it would fail spuriously in a root CI container.
if [ "$(id -u)" = 0 ]; then
  ok "(f7) running as root — the chmod-000 permission fixture is skipped (root bypasses mode bits)"
else
  F7="$(newgit)"
  printf '# editor\n*.swp\n.claude/\n' > "$F7/.gitignore" \
    || setup_fail "(f7) could not write $F7/.gitignore"
  before_f7="$(sum "$F7/.gitignore")"
  chmod 000 "$F7/.gitignore" || setup_fail "(f7) chmod 000 failed on $F7/.gitignore"
  # The guard under test is the permission bits, so assert they really did take — a fixture that
  # is still readable would make the "did not abort" assertion below a false accusation.
  { [ ! -r "$F7/.gitignore" ] || [ ! -w "$F7/.gitignore" ]; } \
    || setup_fail "(f7) $F7/.gitignore is still readable AND writable after chmod 000"
  out_f7="$(mem "$F7" apply 2>&1)"; rc_f7=$?
  chmod 644 "$F7/.gitignore"   # restore BEFORE any assertion so the trap can always clean up
  [ "$rc_f7" -eq 0 ] && ok "(f7) apply on an unreadable/unwritable .gitignore exits 0 (fail-safe)" || no "(f7) non-zero ($rc_f7)"
  has '^apply: ABORTED' "$out_f7" && ok "(f7) apply ABORTS on a chmod-000 .gitignore" || no "(f7) apply did not abort on chmod 000"
  hasi 'readable and writable' "$out_f7" && ok "(f7) the abort names the reason (not both readable and writable)" || no "(f7) abort did not name the permission problem"
  [ "$before_f7" = "$(sum "$F7/.gitignore")" ] && ok "(f7) .gitignore byte-identical after the permission abort" || no "(f7) .gitignore MUTATED despite the abort"
  [ -z "$(ls "$F7"/.gitignore.backup.* 2>/dev/null)" ] && ok "(f7) no backup written on the permission abort path" || no "(f7) a backup was written despite aborting"
fi

# (f8) NUL BYTES — binary content is not a line-oriented ignore file.
# THIS FIXTURE IS DELIBERATELY TWO-SIDED. The guard was once written `grep -q $'\0' "$GI"`,
# which CANNOT work: bash cannot hold a NUL in a variable, so `$'\0'` collapses to the EMPTY
# pattern, which matches every line of every file — every .gitignore was reported as binary.
# A one-sided "a NUL file aborts" assertion would pass under that broken form too (it aborts on
# everything), so it would be vacuous. The negative control below — a plain TEXT .gitignore must
# NOT be reported as binary — is what actually pins the `tr | cmp` fix.
F8="$(newgit)"
printf '.claude/\nbin\000ary\n' > "$F8/.gitignore" || setup_fail "(f8) could not write $F8/.gitignore"
# The NUL is the entire point of this fixture; a printf that dropped it would silently turn the
# group into a duplicate of the text control below. Counted with `tr -d`, deliberately NOT with a
# grep for `$'\0'` — bash cannot hold a NUL in a variable, so that pattern collapses to the EMPTY
# pattern and matches every file (the very regression the (f8) negative control exists to pin).
[ "$(env LC_ALL=C tr -d '\000' < "$F8/.gitignore" | wc -c)" -lt "$(wc -c < "$F8/.gitignore")" ] \
  || setup_fail "(f8) $F8/.gitignore contains no NUL byte — printf dropped it"
before_f8="$(sum "$F8/.gitignore")"
out_f8="$(mem "$F8" apply 2>&1)"; rc_f8=$?
[ "$rc_f8" -eq 0 ] && ok "(f8) apply on a NUL-containing .gitignore exits 0 (fail-safe)" || no "(f8) non-zero ($rc_f8)"
has '^apply: ABORTED' "$out_f8" && ok "(f8) apply ABORTS on a .gitignore containing NUL bytes" || no "(f8) apply did not abort on NUL bytes"
hasi 'NUL bytes' "$out_f8" && ok "(f8) the abort names the reason (NUL bytes / binary)" || no "(f8) abort did not name the NUL bytes"
[ "$before_f8" = "$(sum "$F8/.gitignore")" ] && ok "(f8) .gitignore byte-identical after the binary abort" || no "(f8) .gitignore MUTATED despite the abort"
[ -z "$(ls "$F8"/.gitignore.backup.* 2>/dev/null)" ] && ok "(f8) no backup written on the binary abort path" || no "(f8) a backup was written despite aborting"
# NEGATIVE CONTROL — the same content with the NUL removed is ordinary text and must be handled
# normally. This is the assertion that goes RED if the guard regresses to an empty-pattern grep.
F8b="$(newgit)"
seed_stores "$F8b"
printf '.claude/\nbinary\n' > "$F8b/.gitignore"
out_f8b="$(mem "$F8b" apply 2>&1)"
hasi 'NUL bytes' "$out_f8b" && no "(f8) a plain TEXT .gitignore was misreported as binary (empty-pattern regression)" || ok "(f8) a plain TEXT .gitignore is NOT misreported as binary (guard is not an empty pattern)"
has '^apply: applied' "$out_f8b" && ok "(f8) the text control applies normally (the binary guard did not swallow it)" || no "(f8) the text control did not apply"

# ============================================================================
echo "== (g) remove — reverts exactly, and says plainly that history retains what was pushed =="
Gg="$(newgit https://github.com/acme/widget.git)"
seed_stores "$Gg"
printf '# editor\n*.swp\n\n# runtime\n.claude/\n.supervisor/\n' > "$Gg/.gitignore"
orig_g="$(mkfix)/orig.gitignore"; cp "$Gg/.gitignore" "$orig_g"
mem "$Gg" apply >/dev/null 2>&1
assert_committable "$Gg" "$P_MEM" "(g) precondition: $P_MEM committable after apply"
out_g="$(mem "$Gg" remove 2>&1)"; rc_g=$?
[ "$rc_g" -eq 0 ] && ok "(g) remove exits 0" || no "(g) remove non-zero ($rc_g)"
has '^remove: removed' "$out_g" && ok "(g) remove reports 'removed'" || no "(g) remove did not report 'removed'"
# future tracking stops again — per path
assert_ignored "$Gg" "$P_MEM" "(g) after remove $P_MEM is ignored again (future tracking stopped)"
assert_ignored "$Gg" "$P_LES" "(g) after remove $P_LES is ignored again"
gi_g="$(cat "$Gg/.gitignore")"
hasF '>>> loomwright /setup memory BEGIN' "$gi_g" && no "(g) the managed block survived remove" || ok "(g) the managed block is gone after remove"
# byte-exact round-trip: apply → remove restores the original file
if cmp -s "$orig_g" "$Gg/.gitignore"; then ok "(g) apply → remove restores .gitignore BYTE-EXACTLY"; else no "(g) apply → remove did not restore the original .gitignore"; fi
# the history statement — a required, explicit user-facing claim, not an implication
hasi 'history' "$out_g" && ok "(g) remove output mentions git history" || no "(g) remove output never mentions history"
hasE 'does NOT unpublish|cannot take it back' "$out_g" && ok "(g) remove states plainly that removal does NOT unpublish what was already pushed" || no "(g) remove does not state that history retains pushed content"
hasF 'git rm -r --cached' "$out_g" && ok "(g) remove tells the user how to stop tracking already-tracked files (git rm --cached)" || no "(g) remove omits the already-tracked guidance"
hasi 'NEVER runs git rm' "$out_g" && ok "(g) remove states that the helper itself never runs git rm/add/commit" || no "(g) remove omits the never-runs-git claim"

# ============================================================================
echo "== (h) consent disclosure is printed BEFORE anything is written =="
Hh="$(newgit https://github.com/acme/widget.git)"
printf '.claude/\n.supervisor/\n' > "$Hh/.gitignore"
out_hc="$(mem "$Hh" check 2>&1)"
hasi 'becomes VERSION-CONTROLLED' "$out_hc" && ok "(h) check prints what becomes version-controlled" || no "(h) check omits the version-controlled disclosure"
hasi 'Committing publishes' "$out_hc" && ok "(h) check warns that committing publishes the memory" || no "(h) check omits the publishing warning"
hasi 'proprietary' "$out_hc" && ok "(h) check names the proprietary/client-detail risk explicitly" || no "(h) check omits the proprietary-content risk"
hasi 'does NOT unpublish' "$out_hc" && ok "(h) check states up front that removal does not unpublish" || no "(h) check omits the not-unpublishable warning"
out_ha="$(mem "$Hh" apply 2>&1)"
line_disc="$(grep -n 'becomes VERSION-CONTROLLED' <<< "$out_ha" | head -n1 | cut -d: -f1)"
line_app="$(grep -n '^apply: applied' <<< "$out_ha" | head -n1 | cut -d: -f1)"
if [ -n "$line_disc" ] && [ -n "$line_app" ] && [ "$line_disc" -lt "$line_app" ]; then
  ok "(h) apply prints the disclosure BEFORE reporting the write (line $line_disc < $line_app)"
else
  no "(h) apply did not print the disclosure before the write (disc=$line_disc app=$line_app)"
fi

# ============================================================================
echo "== (i) write containment — only .gitignore(+backup) and .supervisor/config.json =="
Ii="$(newgit https://github.com/acme/widget.git)"
seed_stores "$Ii"
printf '.claude/\n.supervisor/\n' > "$Ii/.gitignore"
# (i1) check writes NOTHING at all.
before_i="$(cd "$Ii" && find . -not -path './.git/*' -not -name '.git' | env LC_ALL=C sort)"
mem "$Ii" check >/dev/null 2>&1
after_i="$(cd "$Ii" && find . -not -path './.git/*' -not -name '.git' | env LC_ALL=C sort)"
[ "$before_i" = "$after_i" ] && ok "(i1) check created no files at all (read-only)" || no "(i1) check created or removed files"
# (i2) apply touches only the sanctioned paths — anything else under the root is a containment breach.
head_before="$(git -C "$Ii" rev-parse HEAD 2>/dev/null)"
idx_before="$(git -C "$Ii" diff --cached --name-only 2>/dev/null | env LC_ALL=C sort)"
mem "$Ii" apply >/dev/null 2>&1
unexpected="$(cd "$Ii" && find . -not -path './.git/*' -not -name '.git' -type f \
  ! -name '.gitignore' ! -name '.gitignore.backup.*' ! -name 'seed.txt' \
  ! -path './.supervisor/config.json' \
  ! -path './.claude/agent-memory/*' ! -path './.supervisor/memory/*' \
  ! -path './.claude/worktrees/*' ! -name 'settings.local.json' ! -path './.supervisor/logs/*' \
  | env LC_ALL=C sort)"
[ -z "$unexpected" ] && ok "(i2) apply wrote ONLY .gitignore, its backup, and .supervisor/config.json" || no "(i2) apply wrote unexpected files: $(tr '\n' ' ' <<< "$unexpected")"
[ ! -e "$Ii/.claude/settings.json" ] && ok "(i2) no <root>/.claude/settings.json written" || no "(i2) apply wrote <root>/.claude/settings.json"
# (i3) nothing was staged, committed, or otherwise pushed into git — behavioural, not a grep.
mem "$Ii" remove >/dev/null 2>&1
head_after="$(git -C "$Ii" rev-parse HEAD 2>/dev/null)"
idx_after="$(git -C "$Ii" diff --cached --name-only 2>/dev/null | env LC_ALL=C sort)"
[ "$head_before" = "$head_after" ] && ok "(i3) HEAD unchanged across apply+remove (nothing committed)" || no "(i3) HEAD MOVED — the helper committed something"
[ "$idx_before" = "$idx_after" ] && ok "(i3) the git index is unchanged across apply+remove (nothing staged)" || no "(i3) the helper STAGED files (index changed)"
# (i4) static corroboration: every git invocation in the helper is read-only. Extracted from the
# actual `git -C "<dir>" <subcommand>` call sites, NOT a bare `git rm` text grep — the helper's
# user-facing copy legitimately QUOTES `git rm -r --cached` as guidance, and a text grep would
# false-positive on that prose.
git_subs="$(grep -oE 'git -C "[^"]*" [a-z-]+' "$MEMB" | awk '{print $NF}' | env LC_ALL=C sort -u | tr '\n' ' ')"
case "$git_subs" in
  *add*|*commit*|*rm*|*push*|*reset*|*checkout*|*stash*)
    no "(i4) a mutating git subcommand is invoked by setup-memory.sh: $git_subs" ;;
  *)
    ok "(i4) only read-only git subcommands are invoked: $git_subs" ;;
esac
# The WRITE-CONTAINMENT INVARIANT's ONE amendment (af36-03): the user-scope consent record. So the
# code may reference HOME ONLY inside do_consent (the record's sole writer/reader) — never in any
# other code line; comment lines may name the record's path. Group (cs) proves the behaviour (grant
# writes exactly that one file); this static leg pins WHERE the reference may live.
mem_src="$(awk '/^do_consent\(\) \{$/ { inc = 1 } inc && /^}$/ { inc = 0; next } !inc && $0 !~ /^[[:space:]]*#/' "$MEMB")"
hasF 'HOME' "$mem_src" && no "(i4) setup-memory.sh references \$HOME outside do_consent (must never write under ~/.claude/ except the consent record)" || ok "(i4) setup-memory.sh references \$HOME only inside do_consent (the one user-scope write)"
hasF 'HOME' "$(awk '/^do_consent\(\) \{$/ { inc = 1 } inc { print } inc && /^}$/ { exit }' "$MEMB")" && ok "(i4) do_consent is where the HOME reference lives (the scan above is not vacuous)" || no "(i4) do_consent was not found — the HOME scan scoped nothing"

# ============================================================================
echo "== (j) fail-safe — every subcommand exits 0, including on hostile input =="
Jj="$(mkfix)"   # a bare directory: NOT a git repo, no .gitignore
for sub in check apply remove allowlist; do
  mem "$Jj" "$sub" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && ok "(j) '$sub' exits 0 on a non-git, .gitignore-less root" || no "(j) '$sub' exited $rc on a non-git root"
done
mem "$Jj" filter-ledger --ledger "$Jj/nope.jsonl" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "(j) 'filter-ledger' exits 0 on a missing ledger" || no "(j) filter-ledger exited $rc on a missing ledger"
bash "$MEM" --root "$Jj" check --bogus-flag >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "(j) an unknown flag is warned about and exits 0" || no "(j) unknown flag exited $rc"
bash "$MEM" --root >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "(j) a valueless trailing --root exits 0 (no arg-shift underflow / spin)" || no "(j) valueless --root exited $rc"
# `--ledger` and `--allow` carry the SAME shift-underflow hazard as `--root` above (a bare trailing
# flag must not `shift 2`), and both early-exit 0 with a stderr reason. Untested until now.
err_lg="$(bash "$MEM" --root "$Jj" filter-ledger --ledger 2>&1 >/dev/null)"; rc=$?
[ "$rc" -eq 0 ] && ok "(j) a valueless trailing --ledger exits 0 (no arg-shift underflow / spin)" || no "(j) valueless --ledger exited $rc"
hasF '--ledger requires a path argument' "$err_lg" && ok "(j) valueless --ledger says WHY on stderr (never a silent fall-back)" || no "(j) valueless --ledger gave no reason (got: $err_lg)"
err_al="$(bash "$MEM" --root "$Jj" allowlist --allow 2>&1 >/dev/null)"; rc=$?
[ "$rc" -eq 0 ] && ok "(j) a valueless trailing --allow exits 0 (no arg-shift underflow / spin)" || no "(j) valueless --allow exited $rc"
hasF '--allow requires an owner/repo argument' "$err_al" && ok "(j) valueless --allow says WHY on stderr" || no "(j) valueless --allow gave no reason (got: $err_al)"
bash "$MEM" --help >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "(j) --help exits 0" || no "(j) --help exits $rc"
# check on a non-git root must degrade to 'unknown', never crash or claim a status it did not probe
chk_j="$(mem "$Jj" check 2>/dev/null)"
has 'unknown' "$chk_j" && ok "(j) a non-git root reports ignore status as 'unknown' (never an unprobed claim)" || no "(j) non-git root did not report 'unknown'"
has '^  .gitignore:        absent' "$chk_j" && ok "(j) a missing .gitignore is reported as 'absent'" || no "(j) missing .gitignore not reported as absent"
# The VERDICT must inherit that too. With every cell 'unknown' the old fall-through printed
# "partial (an unintended path is committable …)" — asserting a state it never probed.
has '^Memory readiness: unknown' "$chk_j" && ok "(j) the VERDICT is 'unknown' when nothing could be probed (never 'partial', which claims an unprobed state)" || no "(j) non-git verdict is not 'unknown' (got: $(grep '^Memory readiness:' <<< "$chk_j"))"
hasF 'could not be probed' "$chk_j" && ok "(j) the unknown verdict says WHY (not a git repo)" || no "(j) the unknown verdict gives no reason"

# ============================================================================
# mkgate — a fixture carrying BOTH memory stores, a `.supervisor/postmortem/` directory, a CLEAN
# single-record ledger attributed to the fixture's own remote slug, one SIBLING artifact in the same
# directory (which must stay ignored), and the historical bare directory excludes. Echoes the dir.
mkgate() {
  local d
  d="$(newgit https://github.com/acme/widget.git)"
  seed_stores "$d"
  mkdir -p "$d/.supervisor/postmortem"
  printf '{"repo":"acme/widget","number":1,"review_rounds":2}\n' > "$d/$P_LEDGER"
  printf '{"stray":true}\n' > "$d/$P_LEDGER_SIBLING"
  printf '.claude/\n.supervisor/\n' > "$d/.gitignore"
  printf '%s' "$d"
}

echo "== (l) the findings-ledger gate — a THIRD managed store, un-ignored ONLY when it is clean =="
# The ledger is structurally CROSS-REPO (a /pr-postmortem append lands in the CURRENT working
# .supervisor/, never the analysed repo's), so un-ignoring an unfiltered one PUBLISHES another repo's
# churn analysis. Everything below drives that gate against real `git check-ignore` probes.

# -----------------------------------------------------------------------------------------------
# test_negation_wrong_position_still_ignored — TWO NEGATIVE CONTROLS THAT BOTH LOOK CORRECT.
#
# Git applies the LAST matching rule, so a `!` line placed BEFORE the exclude that beats it is dead;
# and git cannot re-include a file whose PARENT DIRECTORY is excluded, so the naive one-liner is dead
# too. Both were live design mistakes in this change, and neither is visible by reading — only a real
# probe distinguishes them. Deliberately driven WITHOUT the helper: these fixtures assert what GIT
# does, which is the reference the emitted block has to satisfy.
# -----------------------------------------------------------------------------------------------
test_negation_wrong_position_still_ignored() {
  local d1 d2 d3 gi ln_sup ln_neg
  # (i) the CORRECT three lines in the WRONG POSITION — emitted BEFORE `.supervisor/*`.
  d1="$(newgit https://github.com/acme/widget.git)"
  mkdir -p "$d1/.supervisor/postmortem"; printf '{"repo":"acme/widget"}\n' > "$d1/$P_LEDGER"
  printf '.claude/*\n!.claude/agent-memory/\n!.supervisor/postmortem/\n.supervisor/postmortem/*\n!.supervisor/postmortem/results.jsonl\n.supervisor/*\n!.supervisor/memory/\n' > "$d1/.gitignore"
  assert_ignored "$d1" "$P_LEDGER" "(l7) NEGATIVE CONTROL: the correct three lines placed BEFORE '.supervisor/*' leave the ledger IGNORED — position is load-bearing, git applies the LAST matching rule"

  # (ii) the NAIVE ONE-LINER, correctly positioned but structurally dead.
  d2="$(newgit https://github.com/acme/widget.git)"
  mkdir -p "$d2/.supervisor/postmortem"; printf '{"repo":"acme/widget"}\n' > "$d2/$P_LEDGER"
  printf '.supervisor/*\n!.supervisor/memory/\n!.supervisor/postmortem/results.jsonl\n' > "$d2/.gitignore"
  assert_ignored "$d2" "$P_LEDGER" "(l7) NEGATIVE CONTROL: the NAIVE one-line '!.supervisor/postmortem/results.jsonl' does NOTHING — its parent directory is excluded"

  # (iii) POSITIVE CONTROL on the same fixture — the shipped shape DOES work, so (i) and (ii) prove
  # a real ordering/shape failure rather than a broken probe.
  printf '.supervisor/*\n!.supervisor/memory/\n!.supervisor/postmortem/\n.supervisor/postmortem/*\n!.supervisor/postmortem/results.jsonl\n' > "$d2/.gitignore"
  assert_committable "$d2" "$P_LEDGER" "(l7) POSITIVE CONTROL: the shipped three-line form AFTER '.supervisor/*' DOES re-include the ledger"

  # (iv) STRUCTURAL: what the helper ACTUALLY emits must sit INSIDE the managed block and AFTER the
  # block's own `.supervisor/*`. A hand-added copy OUTSIDE the block (the pre-fix shape) is defeated
  # by the block that apply appends afterwards, so "it worked once by hand" is not the contract.
  d3="$(mkgate)"
  printf '!.supervisor/postmortem/\n.supervisor/postmortem/*\n!.supervisor/postmortem/results.jsonl\n' >> "$d3/.gitignore"
  mem "$d3" apply >/dev/null 2>&1
  gi="$(cat "$d3/.gitignore")"
  ln_sup="$(grep -n '^\.supervisor/\*$' <<< "$gi" | tail -n1 | cut -d: -f1)"
  ln_neg="$(grep -n '^!\.supervisor/postmortem/results\.jsonl$' <<< "$gi" | tail -n1 | cut -d: -f1)"
  if [ -n "$ln_sup" ] && [ -n "$ln_neg" ] && [ "$ln_neg" -gt "$ln_sup" ]; then
    ok "(l7) the EMITTED ledger negation sits AFTER the managed block's own '.supervisor/*' (line $ln_neg > $ln_sup)"
  else
    no "(l7) the emitted ledger negation is mis-positioned (.supervisor/* at line ${ln_sup:-none}, negation at line ${ln_neg:-none})"
  fi
  assert_committable "$d3" "$P_LEDGER" "(l7) and the ledger really is committable after apply, hand-added stray lines notwithstanding"
}

if [ -z "$JQ" ]; then
  ok "(l) jq unavailable — the ledger-gate group is skipped (pass)"
else
  # (l1) CLEAN LEDGER ⇒ the gate PASSES, and the negation re-includes the LEDGER ONLY.
  L1="$(mkgate)"
  assert_ignored "$L1" "$P_LEDGER" "(l1) precondition: the ledger is ignored before apply"
  out_l1="$(mem "$L1" apply 2>&1)"; rc_l1=$?
  [ "$rc_l1" -eq 0 ] && ok "(l1) apply exits 0 with a clean ledger" || no "(l1) apply non-zero ($rc_l1)"
  assert_committable "$L1" "$P_LEDGER"         "(l1) a CLEAN ledger is COMMITTABLE after apply (the gate passed)"
  assert_ignored     "$L1" "$P_LEDGER_SIBLING" "(l1) a SIBLING file under .supervisor/postmortem/ stays IGNORED — the negation is ONE FILE wide, not a directory"
  assert_committable "$L1" "$P_MEM"            "(l1) the two memory stores are unaffected by the third store"
  assert_ignored     "$L1" "$P_LOGS"           "(l1) .supervisor/logs/ still ignored alongside the new negation"
  has '^Memory readiness: configured' "$out_l1" && ok "(l1) the verdict is 'configured' with a clean ledger" || no "(l1) verdict not configured (got: $(grep '^Memory readiness:' <<< "$out_l1" | head -n1))"
  hasE "^ +${P_LEDGER//./\\.} +committable$" "$out_l1" && ok "(l1) the ledger is PROBED and reported under 'intended (must be committable)'" || no "(l1) the ledger is not probed in the intended set"
  # (l1b) IDEMPOTENCY — the negation lives INSIDE the managed block, so re-emission cannot lose it.
  out_l1b="$(mem "$L1" apply 2>&1)"
  has '^apply: no-op' "$out_l1b" && ok "(l1) the second apply is a byte-compare no-op" || no "(l1) the second apply was not a no-op"
  assert_committable "$L1" "$P_LEDGER" "(l1) the ledger is STILL committable after a SECOND apply (a hand-added line outside the block would have been re-ignored here)"

  # ---------------------------------------------------------------------------------------------
  # test_gate_blocks_foreign_spaced_form — THE NAMED SPACED-FORM FIXTURE CASE.
  #
  # This plugin's own ledger carries ONE spaced-form record (`"repo": "…"`) among 88 compact ones, so
  # `grep -c '"repo":"vikashruhilgit/loomwright"'` returns 38 where jq returns 39. The consequence is
  # not a cosmetic under-count: a FOREIGN record appended in the spaced form is INVISIBLE to a compact
  # grep, which would make a grep-based gate a guard that cannot fire. The evasion is proven inside the
  # fixture (grep=0, jq=1) before the gate is exercised, so this can never decay into a jq-vs-jq
  # tautology.
  # ---------------------------------------------------------------------------------------------
  test_gate_blocks_foreign_spaced_form() {
    local d out rc n_jq n_grep out2
    d="$(mkgate)"
    mem "$d" apply >/dev/null 2>&1
    assert_committable "$d" "$P_LEDGER" "(l2) precondition: the ledger is committable while clean"
    printf '{"schema_version": 1, "ts": "2026-08-04T14:06:03Z", "repo": "otherhub/otherrepo", "number": 124}\n' >> "$d/$P_LEDGER"
    n_grep="$(grep -cF '"repo":"otherhub/otherrepo"' "$d/$P_LEDGER" 2>/dev/null || true)"; [ -n "$n_grep" ] || n_grep=0
    n_jq="$(jq -s 'map(select(.repo == "otherhub/otherrepo")) | length' "$d/$P_LEDGER" 2>/dev/null)"
    if [ "${n_grep:-0}" -eq 0 ] && [ "$n_jq" = "1" ]; then
      ok "(l2) THE EVASION IS REAL: a compact-form grep sees 0 spaced-form foreign records where jq sees 1 — this is why every ledger assertion here is jq"
    else
      no "(l2) the spaced-form evasion fixture did not behave as claimed (grep=$n_grep, jq=$n_jq) — the gate assertion below would be vacuous"
    fi
    out="$(mem "$d" apply 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && ok "(l2) apply STILL EXITS 0 on the refusal path (fail-closed in the WRITE dimension, never in the exit status)" || no "(l2) apply exited $rc on the refusal path — the FAIL-SAFE CONTRACT is broken"
    assert_ignored     "$d" "$P_LEDGER" "(l2) the gate REFUSED: the ledger is IGNORED again, so the spaced-form foreign record cannot be published"
    assert_committable "$d" "$P_MEM"    "(l2) the two memory stores stay APPLIED while only the ledger is withheld"
    hasF 'otherhub/otherrepo' "$out" && ok "(l2) the refusal NAMES the offending slug" || no "(l2) the refusal does not name the offending slug"
    # ...and removing the record makes the gate PASS again — red↔green both proven, so the gate keys
    # on the record and not on some incidental property of the fixture.
    jq -c 'select(.repo != "otherhub/otherrepo")' "$d/$P_LEDGER" > "$d/ledger.clean" 2>/dev/null && mv "$d/ledger.clean" "$d/$P_LEDGER"
    out2="$(mem "$d" apply 2>&1)"
    assert_committable "$d" "$P_LEDGER" "(l2) removing the foreign record makes the gate PASS again and re-emits the negation"
    has '^Memory readiness: configured' "$out2" && ok "(l2) the verdict returns to 'configured' once the ledger is clean" || no "(l2) the verdict did not return to 'configured'"
  }
  test_gate_blocks_foreign_spaced_form

  # (l3) LEDGER ABSENT ⇒ the gate PASSES. This is every fresh user repo, and it is load-bearing for
  # test-committed-twin-scrub.sh's group (F) fixture, which asserts `configured` with no ledger.
  L3="$(newgit https://github.com/acme/widget.git)"
  seed_stores "$L3"
  printf '.claude/\n.supervisor/\n' > "$L3/.gitignore"
  out_l3="$(mem "$L3" apply 2>&1)"; rc_l3=$?
  [ "$rc_l3" -eq 0 ] && ok "(l3) apply exits 0 with NO ledger present" || no "(l3) apply non-zero ($rc_l3) with no ledger"
  has '^Memory readiness: configured' "$out_l3" && ok "(l3) an ABSENT ledger PASSES the gate and the verdict still reaches 'configured' (no records ⇒ no foreign records)" || no "(l3) an absent ledger did not reach 'configured' (got: $(grep '^Memory readiness:' <<< "$out_l3" | head -n1))"
  has '^Memory readiness: gated' "$out_l3" && no "(l3) an absent ledger was treated as CONTAMINATED — that would redden every fresh repo" || ok "(l3) an absent ledger is not treated as contaminated"

  # (l5) EMPTY ALLOWLIST ⇒ REFUSE. filter_ledger_by_allowlist retains NOTHING under an empty list, so
  # every record is outside it. Fail-closed: "nothing configured" must never read as "all fine".
  L5="$(newgit)"   # no remote at all → nothing to default from
  seed_stores "$L5"
  mkdir -p "$L5/.supervisor/postmortem"
  printf '{"repo":"acme/widget","number":1}\n' > "$L5/$P_LEDGER"
  printf '.claude/\n.supervisor/\n' > "$L5/.gitignore"
  out_l5="$(mem "$L5" apply 2>&1)"; rc_l5=$?
  [ "$rc_l5" -eq 0 ] && ok "(l5) apply exits 0 with an empty allowlist" || no "(l5) apply non-zero ($rc_l5)"
  assert_ignored "$L5" "$P_LEDGER" "(l5) an EMPTY allowlist REFUSES the negation (fail-closed — never 'nothing configured ⇒ retain everything')"

  # (l6) A RECORD WITH NO `.repo` is unattributable and must REFUSE — it cannot be SHOWN to belong here.
  L6="$(mkgate)"
  printf '{"number":42,"review_rounds":1}\n' >> "$L6/$P_LEDGER"
  out_l6="$(mem "$L6" apply 2>&1)"
  assert_ignored "$L6" "$P_LEDGER" "(l6) an UNATTRIBUTABLE record (no .repo) REFUSES the negation"
  hasF 'no .repo field' "$out_l6" && ok "(l6) the refusal says WHICH problem it found (a record with no .repo field)" || no "(l6) the refusal does not identify the unattributable record"

  # (l8) A MALFORMED ledger line cannot be parsed, so it cannot be shown to be allowlisted ⇒ REFUSE.
  #
  # THE FIXTURE DELIBERATELY OMITS THE TRAILING NEWLINE. A malformed record is, in practice, a
  # TRUNCATED one — an interrupted `/pr-postmortem` append leaves exactly this shape — and a bare
  # `while IFS= read -r line; do … done < "$ledger"` NEVER RUNS ITS BODY for an unterminated final
  # line (`read` returns non-zero at EOF even though it filled $line). The per-line fallback then
  # examined nothing, produced no output, and the gate read "no output" as "clean" ⇒ FAIL-OPEN, with
  # the negation emitted over a ledger holding an unexaminable record. Writing this fixture WITH a
  # trailing newline is what hid that bug, so the newline must stay off.
  L8="$(mkgate)"
  printf 'NOT JSON AT ALL' >> "$L8/$P_LEDGER"
  out_l8="$(mem "$L8" apply 2>&1)"; rc_l8=$?
  [ "$rc_l8" -eq 0 ] && ok "(l8) apply exits 0 on a ledger holding a malformed line" || no "(l8) apply non-zero ($rc_l8) on a malformed ledger"
  assert_ignored "$L8" "$P_LEDGER" "(l8) an UNPARSEABLE record REFUSES the negation (fail-closed per-line fallback, never a silent skip)"
  hasF 'unparseable record' "$out_l8" && ok "(l8) the refusal names the unparseable record" || no "(l8) the refusal does not name the unparseable record"

  # (l9) AN UNREADABLE LEDGER (`chmod 000`) must REFUSE, never pass.
  #
  # `[ -f "$ledger" ]` is TRUE for a chmod-000 regular file, so the gate does not take its
  # ledger-absent PASS shortcut; the whole-file jq then cannot open it (rc≠0) and the per-line
  # fallback's `done < "$ledger"` redirect fails outright, so the loop body never runs. "Examined
  # nothing" and "examined everything and found nothing foreign" both produced EMPTY output, and the
  # gate could not tell them apart ⇒ FAIL-OPEN. A record that cannot be READ cannot be shown to
  # belong to this repo, so the only sound verdict is refuse.
  #
  # SKIPPED UNDER ROOT, mirroring (f7): root bypasses the mode bits entirely, so the ledger stays
  # readable there and this case would pass VACUOUSLY rather than driving the branch.
  if [ "$(id -u)" = 0 ]; then
    ok "(l9) running as root — the chmod-000 unreadable-ledger fixture is skipped (root bypasses mode bits)"
  else
    L9="$(mkgate)"
    chmod 000 "$L9/$P_LEDGER" || setup_fail "(l9) chmod 000 failed on $L9/$P_LEDGER"
    # Same reasoning as (f7): the unreadable bit IS the fixture, so prove it took rather than
    # letting a still-readable ledger turn a vacuous pass into an apparent fail-open.
    [ ! -r "$L9/$P_LEDGER" ] || setup_fail "(l9) $L9/$P_LEDGER is still readable after chmod 000"
    out_l9="$(mem "$L9" apply 2>&1)"; rc_l9=$?
    chmod 644 "$L9/$P_LEDGER"   # restore BEFORE any assertion so the trap can always clean up
    [ "$rc_l9" -eq 0 ] && ok "(l9) apply exits 0 on an UNREADABLE ledger (fail-safe in the exit status)" || no "(l9) apply non-zero ($rc_l9) on an unreadable ledger"
    assert_ignored "$L9" "$P_LEDGER" "(l9) an UNREADABLE ledger REFUSES the negation — 'could not examine' is never 'examined and clean'"
    hasF 'could not be read' "$out_l9" && ok "(l9) the refusal says the ledger could not be read at all" || no "(l9) the refusal does not name the unreadable ledger"
    assert_committable "$L9" "$P_MEM" "(l9) the two memory stores are still applied while only the unreadable ledger is withheld"
  fi

  test_negation_wrong_position_still_ignored
fi

# (l4) jq ABSENT ⇒ the gate is NOT EVALUATED: nothing is probed, the negation is NOT emitted, the
# pre-existing verdict is unchanged and the exit code is still 0. Failing toward `gated` would
# permanently mis-report for every jq-less user; failing toward emitting would publish an unchecked
# ledger. Driven by a PATH containing symlinks to the helper's own dependencies and nothing else —
# not by deleting jq, and not by a shim named `jq` (which `command -v` would still find).
# Outside the JQ guard on purpose: this branch is about jq's ABSENCE.
L4="$(mkgate)"
L4BIN="$L4/onlybin"; mkdir -p "$L4BIN"
for _c in bash sh git awk grep sed cut head tail tr cmp date cp mv rm mkdir rmdir dirname basename wc cat ls sort uniq find id chmod touch expr sleep env; do
  _p="$(command -v "$_c" 2>/dev/null)" && ln -sf "$_p" "$L4BIN/$_c"
done
# Probed in a FRESH bash, not with `PATH=… command -v jq` in this shell: bash caches command
# locations in its own hash table, so the builtin resolves a previously-hashed jq even under a PATH
# that does not contain it — and this meta-check would then fail while the branch below is in fact
# genuinely driven. A fresh interpreter starts with an empty hash table.
if PATH="$L4BIN" bash -c 'command -v jq' >/dev/null 2>&1; then
  no "(l4) the jq-absent fixture still resolves jq on its pinned PATH — the branch below would be untested"
else
  ok "(l4) the jq-absent fixture really has no jq on PATH (the branch is genuinely driven)"
fi
out_l4="$(PATH="$L4BIN" bash "$MEM" --root "$L4" apply 2>&1)"; rc_l4=$?
[ "$rc_l4" -eq 0 ] && ok "(l4) apply exits 0 with jq unavailable (fail-safe)" || no "(l4) apply exited $rc_l4 without jq"
has '^Memory readiness: configured' "$out_l4" && ok "(l4) without jq the pre-existing verdict is PRESERVED ('configured' for the two memory stores)" || no "(l4) the verdict changed when jq went missing (got: $(grep '^Memory readiness:' <<< "$out_l4" | head -n1))"
has '^Memory readiness: gated' "$out_l4" && no "(l4) a missing jq failed toward 'gated' — that would permanently mis-report for every jq-less user" || ok "(l4) a missing jq does NOT fail toward 'gated'"
hasF 'gate not evaluated' "$out_l4" && ok "(l4) the report says plainly that the gate was NOT evaluated (never an unprobed claim)" || no "(l4) the report makes no statement about the unevaluated gate"
assert_ignored "$L4" "$P_LEDGER" "(l4) with the gate unevaluated the negation is NOT emitted — the ledger stays ignored (never publish what was not checked)"
out_l4c="$(PATH="$L4BIN" bash "$MEM" --root "$L4" check 2>&1)"; rc_l4c=$?
[ "$rc_l4c" -eq 0 ] && ok "(l4) check also exits 0 with jq unavailable" || no "(l4) check exited $rc_l4c without jq"

