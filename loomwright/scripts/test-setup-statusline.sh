#!/usr/bin/env bash
# test-setup-statusline.sh — STATIC, fixture-driven self-tests for setup-statusline.sh (the
# `/setup statusline` module engine: check / apply / remove against a user-scope settings JSON).
#
# STATIC ONLY: no network, no Docker, no GitHub — it runs on the plugin's Ubuntu CI like every
# other test-*.sh (auto-registered by ci.yml's `loomwright/scripts/test-*.sh` glob).
#
# Exit 0 = all pass, 1 = any assertion failed, 2 = FIXTURE SETUP is broken.
# 1 and 2 are deliberately distinct: 1 means the assertions ran and the engine misbehaved;
# 2 means a fixture could not be BUILT as specified, so the assertions after it would be
# testing something other than what they name.
#
# FIXTURE ISOLATION IS LOAD-BEARING — AND IT IS ASSERTED, NOT ASSUMED.
# The developer running this has a REAL status line configured, and destroying it would be the
# precise failure this module exists to prevent. Every case below passes `--settings` pointing
# into its own `mktemp -d`, and group (j) checksums the developer's real settings document
# before and after the whole run. That assertion is what makes the isolation a fact rather than
# an intention.
#
# Covers (each = an acceptance criterion):
#   (a) an UNPARSEABLE settings document ABORTS: nothing written, byte-identical afterwards,
#       and NO backup created (a backup implies something was staged)
#   (b) BACKUP-FIRST, asserted POSITIVELY — the backup exists AND its content equals the
#       pre-write document. A count comparison would pass as 0 = 0 across a no-op
#   (c) UNRELATED KEYS SURVIVE — asserted by DIFFING the two documents with the status-line keys
#       removed, never by spot-checking individual keys
#   (d) a FOREIGN status line is PRESERVED and merely reported; replacing it needs --replace
#   (e) the REPLACED value is recorded and `remove` RESTORES IT VERBATIM. This is the regression
#       pin for a real defect: writing the record inside the jq pipeline
#       (`.statusLine = $sl | .[$k] = (.statusLine // null)`) records OUR OWN line, because jq
#       evaluates left to right and the first assignment has already landed. The user's status
#       line was then unrecoverable and `remove` handed back a copy of what it undid
#   (f) idempotency: a second apply writes nothing and makes NO second backup, and the restore
#       record survives re-application unchanged
#   (g) `remove` REFUSES a status line this plugin did not write
#   (h) with no prior status line, `remove` deletes ours outright and leaves no residue key
#   (i) fail-safe: every subcommand exits 0 — including a bad flag, a bad subcommand, an absent
#       settings file, and a missing command file
#   (j) write containment (see above)
#   (k) OWNERSHIP IS ANCHORED (regression pin). `is_ours` once matched any `.command` merely
#       CONTAINING `status-line.sh`, so a user's own `my-status-line.sh` read as ours: `apply`
#       overwrote it with no `--replace` and no WITHHELD gate, recorded `prior: null`, and
#       `remove` then deleted it while printing "there was no statusLine before this module
#       applied". Pinned with a mutation control that reverts the two-signal rule and shows the
#       same fixture BEING overwritten
#   (l) a SYMLINKED settings document survives the write. `mv` replaces a symlink with a
#       regular file, silently detaching a dotfiles-managed config from version control; the
#       engine resolves one level first, so the link stays a link and the TARGET is written
#
# NO `producer | grep -q` PIPELINES (SIGPIPE turns a match into rc=141 under pipefail).

set -uo pipefail
export LC_ALL=C

script_dir="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$script_dir/setup-statusline.sh"
SLCMD="$script_dir/status-line.sh"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }
setup_fail() { printf '  SETUP BROKEN: %s\n' "$1" >&2; exit 2; }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

[ -f "$ENGINE" ] || setup_fail "setup-statusline.sh not found at $ENGINE"
[ -f "$SLCMD" ]  || setup_fail "status-line.sh not found at $SLCMD"

command -v jq >/dev/null 2>&1 || setup_fail "jq is required to run these assertions"
printf '{}' | jq -e . >/dev/null 2>&1 || setup_fail "jq is present but non-functional"

TMPROOT="$(mktemp -d)" || setup_fail "mktemp -d failed"
trap 'rm -rf "$TMPROOT"' EXIT

# (j) baseline — the developer's REAL settings document, captured before anything runs.
REAL_SETTINGS="$HOME/.claude/settings.json"
if [ -f "$REAL_SETTINGS" ]; then
  real_before="$(wc -c < "$REAL_SETTINGS" | tr -d ' ')/$(cat "$REAL_SETTINGS")"
else
  real_before="ABSENT"
fi
# (j2) baseline — how many backups of the REAL settings document already exist. Without this
# the assertion below had nothing to compare against: `${STRAY_BASELINE:-$stray}` expanded to
# `$stray`, making the test `[ "$stray" = "$stray" ]` — true for any value, including one this
# run created. Captured HERE, before anything runs, so a backup made DURING the run is the only
# thing that can move the number.
STRAY_BASELINE="$(ls -1 "$REAL_SETTINGS".backup.* 2>/dev/null | wc -l | tr -d ' ')"
case "$STRAY_BASELINE" in ''|*[!0-9]*) STRAY_BASELINE=0 ;; esac

# eng <fixture-settings-path> <subcmd> [flags...]  -> $out / $rc
eng() {
  local s="$1" sub="$2"; shift 2
  out="$(bash "$ENGINE" "$sub" --settings "$s" --command "$SLCMD" "$@" 2>&1)"; rc=$?
}

# backup_count <settings-path>
backup_count() {
  local n
  n="$(ls -1 "$1".backup.* 2>/dev/null | wc -l | tr -d ' ')"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

# nostatus <settings-path> — the document with BOTH status-line keys removed. This is the
# "everything unrelated" projection that (c) diffs.
nostatus() { jq 'del(.statusLine, .loomwrightStatusLinePrior)' "$1" 2>/dev/null; }

echo "== (a) unparseable settings — abort, no write, no backup =="

FA="$TMPROOT/a"; mkdir -p "$FA" || setup_fail "mkdir a"
SA="$FA/settings.json"
printf '{"model":"opus", this is not JSON at all\n' > "$SA" || setup_fail "could not write the unparseable fixture"
before="$(cat "$SA")"
eng "$SA" apply
after="$(cat "$SA")"
if [ "$rc" -eq 0 ] && has "$out" "ABORTED" && [ "$before" = "$after" ]; then
  ok "(a1) apply on an unparseable document ABORTS, exits 0, and leaves it byte-identical"
else
  no "(a1) apply on an unparseable document ABORTS, exits 0, and leaves it byte-identical" "rc=$rc out=$out"
fi
if [ "$(backup_count "$SA")" = "0" ]; then
  ok "(a2) …and creates NO backup (nothing was staged, so there is nothing to roll back)"
else
  no "(a2) …and creates NO backup (nothing was staged, so there is nothing to roll back)" "$(backup_count "$SA") backup(s)"
fi
eng "$SA" check
if [ "$rc" -eq 0 ] && has "$out" "UNPARSEABLE"; then
  ok "(a3) check reports the document as UNPARSEABLE rather than claiming a readiness state"
else
  no "(a3) check reports the document as UNPARSEABLE rather than claiming a readiness state" "rc=$rc out=$out"
fi

echo "== (b)/(c) backup-first and unrelated-key preservation =="

FB="$TMPROOT/b"; mkdir -p "$FB" || setup_fail "mkdir b"
SB="$FB/settings.json"
cat > "$SB" <<'JSONEOF' || setup_fail "could not write the (b) fixture"
{
  "model": "opus",
  "env": { "FOO": "1", "BAR": "two" },
  "permissions": { "allow": ["Bash(ls:*)"] },
  "hooks": { "Stop": [] }
}
JSONEOF
jq -e . "$SB" >/dev/null 2>&1 || setup_fail "the (b) fixture is not valid JSON"
pristine="$(cat "$SB")"
pristine_projection="$(nostatus "$SB")"
[ -n "$pristine_projection" ] || setup_fail "the (b) fixture projection is empty — (c) would be vacuous"

eng "$SB" apply
if [ "$rc" -eq 0 ] && has "$out" "apply: applied"; then
  ok "(b1) apply on a valid document reports 'apply: applied'"
else
  no "(b1) apply on a valid document reports 'apply: applied'" "rc=$rc out=$out"
fi

bk="$(ls -1 "$SB".backup.* 2>/dev/null | head -1)"
if [ -n "$bk" ] && [ -f "$bk" ]; then
  ok "(b2) a timestamped backup exists after the write"
  if [ "$(cat "$bk")" = "$pristine" ]; then
    ok "(b3) the backup's CONTENT is the pristine pre-write document — asserted positively, not by counting"
  else
    no "(b3) the backup's CONTENT is the pristine pre-write document — asserted positively, not by counting" \
       "the backup does not match the pre-write file"
  fi
else
  no "(b2) a timestamped backup exists after the write"
  no "(b3) the backup's CONTENT is the pristine pre-write document (skipped — no backup)"
fi

if diff <(printf '%s\n' "$pristine_projection") <(nostatus "$SB") >/dev/null 2>&1; then
  ok "(c1) every key unrelated to the status line survives — DIFFED with the status-line keys removed, not spot-checked"
else
  no "(c1) every key unrelated to the status line survives — DIFFED with the status-line keys removed, not spot-checked" \
     "$(diff <(printf '%s\n' "$pristine_projection") <(nostatus "$SB") 2>&1 | head -20)"
fi
# Control: the diff above must be capable of FAILING, or (c1) proves nothing.
mangled="$(jq '.env.FOO = "CHANGED"' "$SB" 2>/dev/null | jq 'del(.statusLine, .loomwrightStatusLinePrior)')"
if ! diff <(printf '%s\n' "$pristine_projection") <(printf '%s\n' "$mangled") >/dev/null 2>&1; then
  ok "(c2) control — the same diff DOES fail when an unrelated key is altered, so (c1) is not vacuous"
else
  no "(c2) control — the same diff DOES fail when an unrelated key is altered, so (c1) is not vacuous"
fi

installed="$(jq -r '.statusLine.command // ""' "$SB" 2>/dev/null)"
if [ "$installed" = "$SLCMD" ]; then
  ok "(c3) the installed statusLine.command is the status-line script"
else
  no "(c3) the installed statusLine.command is the status-line script" "got '$installed'"
fi

echo "== (f) idempotency =="

n1="$(backup_count "$SB")"
snap="$(cat "$SB")"
eng "$SB" apply
n2="$(backup_count "$SB")"
if [ "$rc" -eq 0 ] && has "$out" "no-op — already configured" && [ "$snap" = "$(cat "$SB")" ]; then
  ok "(f1) a second apply is a no-op and the document is byte-identical"
else
  no "(f1) a second apply is a no-op and the document is byte-identical" "rc=$rc out=$out"
fi
if [ "$n1" = "$n2" ]; then
  ok "(f2) …and no SECOND backup was written"
else
  no "(f2) …and no SECOND backup was written" "$n1 -> $n2"
fi

echo "== (d)/(e) a foreign status line: preserved, then replaced, then restored =="

FD="$TMPROOT/d"; mkdir -p "$FD" || setup_fail "mkdir d"
SD="$FD/settings.json"
FOREIGN='{"type":"command","command":"/Users/someone/.claude/statusline-command.sh"}'
jq -n --argjson sl "$FOREIGN" '{model:"opus", env:{KEEP:"yes"}, statusLine:$sl}' > "$SD" \
  || setup_fail "could not write the (d) foreign fixture"
d_pristine="$(cat "$SD")"

eng "$SD" check
if [ "$rc" -eq 0 ] && has "$out" "NOT installed by this plugin" && has "$out" "readiness: foreign"; then
  ok "(d1) check REPORTS a foreign status line and names the verdict 'foreign'"
else
  no "(d1) check REPORTS a foreign status line and names the verdict 'foreign'" "rc=$rc out=$out"
fi
if has "$out" "statusline-command.sh"; then
  ok "(d2) …and reports the existing VALUE, so the user can see what would be replaced"
else
  no "(d2) …and reports the existing VALUE, so the user can see what would be replaced" "$out"
fi

eng "$SD" apply
if [ "$rc" -eq 0 ] && has "$out" "WITHHELD" && [ "$d_pristine" = "$(cat "$SD")" ]; then
  ok "(d3) apply WITHOUT --replace does NOT overwrite it — WITHHELD, document byte-identical"
else
  no "(d3) apply WITHOUT --replace does NOT overwrite it — WITHHELD, document byte-identical" "rc=$rc out=$out"
fi
if [ "$(backup_count "$SD")" = "0" ]; then
  ok "(d4) …and no backup was written, because nothing was staged"
else
  no "(d4) …and no backup was written, because nothing was staged" "$(backup_count "$SD") backup(s)"
fi
if has "$out" "--replace"; then
  ok "(d5) …and the refusal names the explicit flag required to proceed"
else
  no "(d5) …and the refusal names the explicit flag required to proceed" "$out"
fi

eng "$SD" apply --replace
if [ "$rc" -eq 0 ] && has "$out" "REPLACED"; then
  ok "(e1) apply --replace installs ours and announces that it replaced something"
else
  no "(e1) apply --replace installs ours and announces that it replaced something" "rc=$rc out=$out"
fi
recorded="$(jq -c '.loomwrightStatusLinePrior' "$SD" 2>/dev/null)"
expected="$(printf '%s' "$FOREIGN" | jq -c .)"
if [ "$recorded" = "$expected" ]; then
  ok "(e2) the recorded prior value is the USER'S line, not ours — the jq left-to-right pipeline trap is not present"
else
  no "(e2) the recorded prior value is the USER'S line, not ours — the jq left-to-right pipeline trap is not present" \
     "recorded=$recorded expected=$expected"
fi

# Re-apply before removing: the record must survive re-application, or `remove` restores our own
# line on any repo where apply ran twice.
eng "$SD" apply --replace
recorded2="$(jq -c '.loomwrightStatusLinePrior' "$SD" 2>/dev/null)"
if [ "$recorded2" = "$expected" ]; then
  ok "(e3) the record SURVIVES re-application unchanged (a second apply must not recapture our own line)"
else
  no "(e3) the record SURVIVES re-application unchanged (a second apply must not recapture our own line)" \
     "recorded=$recorded2 expected=$expected"
fi

eng "$SD" remove
restored="$(jq -c '.statusLine' "$SD" 2>/dev/null)"
if [ "$rc" -eq 0 ] && [ "$restored" = "$expected" ]; then
  ok "(e4) remove RESTORES the user's original status line verbatim"
else
  no "(e4) remove RESTORES the user's original status line verbatim" "rc=$rc restored=$restored out=$out"
fi
resid="$(jq -r 'has("loomwrightStatusLinePrior")' "$SD" 2>/dev/null)"
if [ "$resid" = "false" ]; then
  ok "(e5) …and the restore record is deleted, leaving no residue key behind"
else
  no "(e5) …and the restore record is deleted, leaving no residue key behind" "has(prior)=$resid"
fi
if diff <(jq 'del(.statusLine,.loomwrightStatusLinePrior)' <<<"$d_pristine") <(nostatus "$SD") >/dev/null 2>&1; then
  ok "(e6) …and the full apply→remove round-trip left every unrelated key untouched"
else
  no "(e6) …and the full apply→remove round-trip left every unrelated key untouched"
fi

echo "== (g) remove refuses a foreign status line =="

FG="$TMPROOT/g"; mkdir -p "$FG" || setup_fail "mkdir g"
SG="$FG/settings.json"
jq -n --argjson sl "$FOREIGN" '{statusLine:$sl, env:{A:"1"}}' > "$SG" || setup_fail "could not write the (g) fixture"
g_pristine="$(cat "$SG")"
eng "$SG" remove
if [ "$rc" -eq 0 ] && has "$out" "REFUSED" && [ "$g_pristine" = "$(cat "$SG")" ]; then
  ok "(g1) remove REFUSES a status line this plugin did not write and leaves it byte-identical"
else
  no "(g1) remove REFUSES a status line this plugin did not write and leaves it byte-identical" "rc=$rc out=$out"
fi

echo "== (h) no prior status line: remove deletes ours outright =="

FH="$TMPROOT/h"; mkdir -p "$FH" || setup_fail "mkdir h"
SH="$FH/settings.json"
printf '{"env":{"Z":"9"}}\n' > "$SH" || setup_fail "could not write the (h) fixture"
h_pristine_projection="$(nostatus "$SH")"
eng "$SH" apply
if [ "$rc" -eq 0 ] && has "$out" "apply: applied"; then
  ok "(h1) apply installs cleanly when there was no status line at all"
else
  no "(h1) apply installs cleanly when there was no status line at all" "rc=$rc out=$out"
fi
eng "$SH" remove
after_sl="$(jq -r 'has("statusLine")' "$SH" 2>/dev/null)"
after_pr="$(jq -r 'has("loomwrightStatusLinePrior")' "$SH" 2>/dev/null)"
if [ "$rc" -eq 0 ] && [ "$after_sl" = "false" ] && [ "$after_pr" = "false" ]; then
  ok "(h2) remove deletes the status line outright and drops the record — no residue of either key"
else
  no "(h2) remove deletes the status line outright and drops the record — no residue of either key" \
     "rc=$rc has(statusLine)=$after_sl has(prior)=$after_pr"
fi
if diff <(printf '%s\n' "$h_pristine_projection") <(nostatus "$SH") >/dev/null 2>&1; then
  ok "(h3) …and the document is back to its pre-apply content"
else
  no "(h3) …and the document is back to its pre-apply content"
fi
eng "$SH" remove
if [ "$rc" -eq 0 ] && has "$out" "no-op"; then
  ok "(h4) a second remove is a no-op, not an error"
else
  no "(h4) a second remove is a no-op, not an error" "rc=$rc out=$out"
fi

echo "== (k) ownership is ANCHORED: a same-substring foreign line is not ours =="

# The reported bypass verbatim: a user's own status line whose basename merely CONTAINS
# `status-line.sh`, in a document this module has never touched (no marker key).
FK="$TMPROOT/k"; mkdir -p "$FK" || setup_fail "mkdir k"
SK="$FK/settings.json"
# Deliberately NOT under the host's config directory: living somewhere else isolates the
# BASENAME SUBSTRING as the only reason the old rule claimed this line as ours.
LOOKALIKE='{"type":"command","command":"/Users/someone/bin/my-status-line.sh"}'
jq -n --argjson sl "$LOOKALIKE" '{model:"opus", env:{KEEP:"yes"}, statusLine:$sl}' > "$SK" \
  || setup_fail "could not write the (k) look-alike fixture"
k_pristine="$(cat "$SK")"
# The fixture is only a regression pin if it really is the shape that used to slip through:
# no marker key, and a command that the OLD substring rule would have claimed.
[ "$(jq -r 'has("loomwrightStatusLinePrior")' "$SK")" = "false" ] \
  || setup_fail "the (k) fixture carries a marker key — it would not exercise the bypass"
case "$(jq -r '.statusLine.command' "$SK")" in
  *status-line.sh*) : ;;
  *) setup_fail "the (k) fixture's command does not contain 'status-line.sh' — the old rule would not have claimed it, so (k) proves nothing" ;;
esac

eng "$SK" check
if [ "$rc" -eq 0 ] && has "$out" "readiness: foreign"; then
  ok "(k1) check calls a look-alike command FOREIGN, not ours"
else
  no "(k1) check calls a look-alike command FOREIGN, not ours" "rc=$rc out=$out"
fi

eng "$SK" apply
if [ "$rc" -eq 0 ] && has "$out" "WITHHELD" && [ "$k_pristine" = "$(cat "$SK")" ]; then
  ok "(k2) apply WITHOUT --replace WITHHOLDS against a look-alike and leaves it byte-identical"
else
  no "(k2) apply WITHOUT --replace WITHHOLDS against a look-alike and leaves it byte-identical" "rc=$rc out=$out"
fi
if [ "$(backup_count "$SK")" = "0" ]; then
  ok "(k3) …and writes no backup, because nothing was staged"
else
  no "(k3) …and writes no backup, because nothing was staged" "$(backup_count "$SK") backup(s)"
fi

eng "$SK" remove
if [ "$rc" -eq 0 ] && has "$out" "REFUSED" && [ "$k_pristine" = "$(cat "$SK")" ]; then
  ok "(k4) remove REFUSES to touch a look-alike and leaves it byte-identical"
else
  no "(k4) remove REFUSES to touch a look-alike and leaves it byte-identical" "rc=$rc out=$out"
fi
if ! has "$out" "there was no statusLine before"; then
  ok "(k5) …and never prints the false 'there was no statusLine before this module applied'"
else
  no "(k5) …and never prints the false 'there was no statusLine before this module applied'" "$out"
fi

# Mutation control. (k2)-(k5) are only evidence if they can FAIL, and the thing they guard is a
# rule that was WRITTEN into the engine — a passing fixture proves nothing unless the fixture is
# shown failing with that rule removed. The mutant reverts is_ours to the unanchored,
# marker-free form and re-runs (k2) against a FRESH copy of the same fixture.
MUT="$TMPROOT/mutant-engine.sh"
sed -e '/jq -e --arg k "\$PRIOR_KEY"/d' \
    -e 's#in "\$SL_COMMAND".\*/status-line\.sh)#in *status-line.sh*)#' \
    "$ENGINE" > "$MUT" 2>/dev/null || setup_fail "could not build the (k) mutant"
mut_valid=1
[ -s "$MUT" ] || mut_valid=0
cmp -s "$MUT" "$ENGINE" && mut_valid=0
bash -n "$MUT" 2>/dev/null || mut_valid=0
# The two edits must both have LANDED — a sed that matched nothing yields a file that differs
# in neither respect and would "prove" the fix while testing the fixed code.
grep -q 'in \*status-line.sh\*)' "$MUT" 2>/dev/null || mut_valid=0
grep -q "jq -e --arg k \"\$PRIOR_KEY\"" "$MUT" 2>/dev/null && mut_valid=0
if [ "$mut_valid" -ne 1 ]; then
  no "(k6) mutation control — the reverted-rule mutant is a valid, actually-mutated script" \
     "the mutant is empty, identical, syntactically broken, or the sed edits did not land"
else
  ok "(k6) mutation control — the reverted-rule mutant is a valid, actually-mutated script"
  FKM="$TMPROOT/km"; mkdir -p "$FKM" || setup_fail "mkdir km"
  SKM="$FKM/settings.json"
  printf '%s\n' "$k_pristine" > "$SKM" || setup_fail "could not copy the (k) fixture for the mutant"
  km_pristine="$(cat "$SKM")"
  mout="$(bash "$MUT" apply --settings "$SKM" --command "$SLCMD" 2>&1)"; mrc=$?
  if [ "$mrc" -eq 0 ] && ! has "$mout" "WITHHELD" && [ "$km_pristine" != "$(cat "$SKM")" ]; then
    ok "(k7) …and with the anchored rule REVERTED the same fixture IS silently overwritten — (k2) is not vacuous"
  else
    no "(k7) …and with the anchored rule REVERTED the same fixture IS silently overwritten — (k2) is not vacuous" \
       "mrc=$mrc mout=$mout"
  fi
fi

echo "== (l) a SYMLINKED settings document keeps its link; the TARGET is written =="

FL="$TMPROOT/l"; mkdir -p "$FL/real" || setup_fail "mkdir l"
LTARGET="$FL/real/settings.json"
LLINK="$FL/settings.json"
printf '{"env":{"L":"1"}}\n' > "$LTARGET" || setup_fail "could not write the (l) target"
ln -s "$LTARGET" "$LLINK" || setup_fail "could not create the (l) absolute symlink"
[ -L "$LLINK" ] || setup_fail "the (l) fixture is not a symlink — the case would be vacuous"

eng "$LLINK" apply
if [ "$rc" -eq 0 ] && has "$out" "apply: applied"; then
  ok "(l1) apply through a symlinked settings path succeeds"
else
  no "(l1) apply through a symlinked settings path succeeds" "rc=$rc out=$out"
fi
if [ -L "$LLINK" ]; then
  ok "(l2) the settings path is STILL a symlink — it was not replaced by a regular file"
else
  no "(l2) the settings path is STILL a symlink — it was not replaced by a regular file" \
     "$(ls -l "$LLINK" 2>&1)"
fi
if [ "$(jq -r '.statusLine.command // ""' "$LTARGET" 2>/dev/null)" = "$SLCMD" ]; then
  ok "(l3) …and the TARGET file is the one that received the write"
else
  no "(l3) …and the TARGET file is the one that received the write" \
     "target statusLine=$(jq -c '.statusLine' "$LTARGET" 2>&1)"
fi
if [ "$(backup_count "$LTARGET")" != "0" ] && [ "$(backup_count "$LLINK")" = "0" ]; then
  ok "(l4) …and the backup was written beside the TARGET, not beside the link"
else
  no "(l4) …and the backup was written beside the TARGET, not beside the link" \
     "target=$(backup_count "$LTARGET") link=$(backup_count "$LLINK")"
fi

# The RELATIVE-target branch of the resolver is a separate code path: a relative link resolves
# against the LINK's directory, not the caller's cwd. A documented branch with no case is the
# shape this repo's review keeps catching, so it gets its own fixture.
FL2="$TMPROOT/l2"; mkdir -p "$FL2/real" || setup_fail "mkdir l2"
L2TARGET="$FL2/real/settings.json"
L2LINK="$FL2/settings.json"
printf '{"env":{"L2":"1"}}\n' > "$L2TARGET" || setup_fail "could not write the (l) relative target"
ln -s "real/settings.json" "$L2LINK" || setup_fail "could not create the (l) relative symlink"
eng "$L2LINK" apply
if [ "$rc" -eq 0 ] && [ -L "$L2LINK" ] && [ "$(jq -r '.statusLine.command // ""' "$L2TARGET" 2>/dev/null)" = "$SLCMD" ]; then
  ok "(l5) a RELATIVE symlink resolves against the link's own directory: link intact, target written"
else
  no "(l5) a RELATIVE symlink resolves against the link's own directory: link intact, target written" \
     "rc=$rc link=$([ -L "$L2LINK" ] && echo symlink || echo regular) target=$(jq -c '.statusLine' "$L2TARGET" 2>&1)"
fi

echo "== (i) fail-safe: every branch exits 0 =="

FI="$TMPROOT/i"; mkdir -p "$FI" || setup_fail "mkdir i"
SI="$FI/settings.json"

eng "$SI" check
if [ "$rc" -eq 0 ] && has "$out" "not configured"; then
  ok "(i1) check on an ABSENT settings file reports 'not configured' and exits 0"
else
  no "(i1) check on an ABSENT settings file reports 'not configured' and exits 0" "rc=$rc out=$out"
fi
eng "$SI" apply
if [ "$rc" -eq 0 ] && [ -f "$SI" ] && [ "$(jq -r '.statusLine.command // ""' "$SI")" = "$SLCMD" ]; then
  ok "(i2) apply CREATES an absent settings file with just the status line"
else
  no "(i2) apply CREATES an absent settings file with just the status line" "rc=$rc out=$out"
fi

out="$(bash "$ENGINE" apply --settings "$TMPROOT/i2.json" --command "$TMPROOT/does-not-exist.sh" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && has "$out" "ABORTED" && [ ! -f "$TMPROOT/i2.json" ]; then
  ok "(i3) apply ABORTS when the status-line command does not exist, and writes nothing"
else
  no "(i3) apply ABORTS when the status-line command does not exist, and writes nothing" "rc=$rc out=$out"
fi

out="$(bash "$ENGINE" not-a-subcommand --settings "$SI" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && has "$out" "unknown subcommand"; then
  ok "(i4) an unknown subcommand prints usage and still exits 0"
else
  no "(i4) an unknown subcommand prints usage and still exits 0" "rc=$rc out=$out"
fi

out="$(bash "$ENGINE" check --settings "$SI" --bogus-flag 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  ok "(i5) an unknown flag does not make the engine fail"
else
  no "(i5) an unknown flag does not make the engine fail" "rc=$rc out=$out"
fi

echo "== (j) write containment: the developer's real settings document =="

if [ -f "$REAL_SETTINGS" ]; then
  real_after="$(wc -c < "$REAL_SETTINGS" | tr -d ' ')/$(cat "$REAL_SETTINGS")"
else
  real_after="ABSENT"
fi
if [ "$real_before" = "$real_after" ]; then
  ok "(j1) the real user-scope settings document is byte-identical after the whole run"
else
  no "(j1) the real user-scope settings document is byte-identical after the whole run" \
     "THIS SUITE MODIFIED THE DEVELOPER'S OWN SETTINGS — restore from a .backup.* sibling"
fi
stray="$(ls -1 "$REAL_SETTINGS".backup.* 2>/dev/null | wc -l | tr -d ' ')"
case "$stray" in ''|*[!0-9]*) stray=0 ;; esac
if [ "$stray" = "$STRAY_BASELINE" ]; then
  ok "(j2) no backup of the real settings document was created by this run"
else
  no "(j2) no backup of the real settings document was created by this run" \
     "backups of $REAL_SETTINGS went $STRAY_BASELINE -> $stray — THIS SUITE WROTE OUTSIDE ITS FIXTURES"
fi
# Every DIRECT engine invocation must carry --settings. A call without it would default to the
# real user-scope document — which is exactly what (j1) guards, but (j1) can only notice AFTER
# the damage, and it cannot notice at all on a machine where that file does not exist. This
# asserts the DISCIPLINE, so a future case added without the flag is caught up front.
#
# Only DIRECT `bash "$ENGINE"` lines are in scope: the `eng` wrapper supplies --settings from
# its own first argument, so calls through it are safe by construction. The wrapper's own
# definition line is the one direct invocation that legitimately has no literal flag, and it is
# excluded by name rather than by a pattern that could quietly widen.
# The `ctl=` line below and the `eng` wrapper both mention the engine without a literal flag,
# and neither is a case invocation — they are excluded by NAME (an assignment to ctl/direct/
# bare, and the wrapper's own body) rather than by a pattern that could quietly widen.
direct="$(grep -n 'bash "\$ENGINE"' "$0" | grep -v 'out="\$(bash "\$ENGINE" "\$sub"' | grep -vE ':[[:space:]]*(ctl|direct|bare)=' || true)"
bare="$(printf '%s\n' "$direct" | grep -v -- '--settings' || true)"
bare="$(printf '%s' "$bare" | tr -d '[:space:]')"
# Control: the matcher must fire on a line that really is missing the flag, or a clean result
# proves nothing about the matcher.
ctl="$(printf 'bash "$ENGINE" apply --command x\n' | grep -c 'bash "\$ENGINE"' || true)"
[ "$ctl" = "1" ] || setup_fail "the (j3) matcher does not fire on a direct engine call (ctl=$ctl) — the assertion would be vacuous"
ndirect="$(printf '%s\n' "$direct" | grep -c . || true)"
case "$ndirect" in ''|*[!0-9]*) ndirect=0 ;; esac
[ "$ndirect" -ge 3 ] || setup_fail "only $ndirect direct engine invocations were found — (j3) would be near-vacuous"
if [ -z "$bare" ]; then
  ok "(j3) all $ndirect direct engine invocations pass --settings (no case can target the real document)"
else
  no "(j3) all $ndirect direct engine invocations pass --settings (no case can target the real document)" "$bare"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
