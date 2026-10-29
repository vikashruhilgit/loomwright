echo "== (bm) branch mode: --branch-mode <branch>|off, plain-apply preservation, the one 'mode' reader =="
# Branch mode (skills/automate-loop/SKILL.md §"Branch mode"): the block omits every run-history
# re-include and carries ONE mode line; a plain apply preserves it; `mode` is the only reader.
MLINE='# loomwright-meta-branch: '
Bm="$(newgit https://github.com/acme/widget.git)"; seed_stores "$Bm"; printf 'node_modules/\n.supervisor/\n' > "$Bm/.gitignore"
Bo="$(newgit https://github.com/acme/widget.git)"; seed_stores "$Bo"; printf 'node_modules/\n.supervisor/\n' > "$Bo/.gitignore"
m0="$(mem "$Bm" mode 2>/dev/null)"
[ "$m0" = "off" ] && ok "(bm) mode with no managed block prints 'off'" || no "(bm) mode with no block: '$m0'"
s0="$(sum "$Bm/.gitignore")"
o="$(mem "$Bm" apply --branch-mode 2>/dev/null)"
if has 'requires a value' "$o" && [ "$(sum "$Bm/.gitignore")" = "$s0" ] && [ -z "$(ls "$Bm"/.gitignore.backup.* 2>/dev/null)" ]; then ok "(bm) bare --branch-mode is a usage error and writes nothing"; else no "(bm) bare --branch-mode: $o"; fi
o="$(mem "$Bm" apply --branch-mode 'bad..name' 2>/dev/null)"
if has 'apply: ABORTED — invalid --branch-mode branch name' "$o" && [ "$(sum "$Bm/.gitignore")" = "$s0" ]; then ok "(bm) an invalid branch name (check-ref-format) is refused with nothing written"; else no "(bm) invalid branch name: $o"; fi
o="$(mem "$Bm" check --branch-mode x 2>/dev/null)"
if has 'applies only to' "$o" && [ "$(sum "$Bm/.gitignore")" = "$s0" ]; then ok "(bm) --branch-mode with a non-apply subcommand is refused"; else no "(bm) --branch-mode on check: $o"; fi
o="$(mem "$Bm" apply --branch-mode loomwright-meta 2>/dev/null)"
has '^apply: applied (branch mode: loomwright-meta)' "$o" && ok "(bm) apply --branch-mode X reports the branch-mode write" || no "(bm) apply --branch-mode headline: $(grep '^apply' <<< "$o")"
blk="$(sed -n "/>>> loomwright \/setup memory BEGIN/,/<<< loomwright \/setup memory END/p" "$Bm/.gitignore")"
[ "$(grep -c "^${MLINE}loomwright-meta\$" <<< "$blk")" = 1 ] && ok "(bm) the block carries exactly ONE mode line '${MLINE}loomwright-meta'" || no "(bm) mode line count in block: $(grep -c "^$MLINE" <<< "$blk")"
for l in '!.supervisor/requirements/' '!.supervisor/jobs/' '.supervisor/jobs/*' '!.supervisor/jobs/done/' '!.supervisor/jobs/failed/' '!.supervisor/automate/' '.supervisor/automate/*' '!.supervisor/automate/*.md' '!.supervisor/postmortem/' '.supervisor/postmortem/*' '!.supervisor/postmortem/results.jsonl'; do
  if grep -qxF -- "$l" <<< "$blk"; then no "(bm) branch-mode block still carries run-history line '$l'"; else ok "(bm) branch-mode block omits '$l'"; fi
done
for l in '.claude/*' '!.claude/agent-memory/' '.supervisor/*' '!.supervisor/memory/' '*/**/.supervisor/'; do
  grep -qxF -- "$l" <<< "$blk" && ok "(bm) branch-mode block keeps '$l'" || no "(bm) branch-mode block lost '$l'"
done
grep -q 'judgement TRAIL' <<< "$blk" && no "(bm) branch-mode block still claims the trail is committed" || ok "(bm) branch-mode block drops the 'judgement TRAIL' committed-on-purpose claim"
assert_committable "$Bm" "$P_MEM" "(bm) $P_MEM stays committable in branch mode"
assert_committable "$Bm" "$P_LES" "(bm) $P_LES stays committable in branch mode"
assert_ignored "$Bm" "$P_REQ"  "(bm) $P_REQ is ignored in branch mode (on the metadata branch)"
assert_ignored "$Bm" "$P_DONE" "(bm) $P_DONE is ignored in branch mode"
assert_ignored "$Bm" ".supervisor/automate/automate-2026-01-01-000000.md" "(bm) automate run file is ignored in branch mode"
assert_ignored "$Bm" "$P_LEDGER" "(bm) the ledger is ignored in branch mode"
m1="$(mem "$Bm" mode 2>/dev/null)"
[ "$m1" = "on loomwright-meta" ] && ok "(bm) mode prints 'on loomwright-meta'" || no "(bm) mode after apply: '$m1'"
c1="$(mem "$Bm" check 2>/dev/null)"
has '^Memory readiness: configured' "$c1" && ok "(bm) check reads a branch-mode block as configured (no drift)" || no "(bm) check verdict in branch mode: $(grep '^Memory readiness' <<< "$c1")"
s1="$(sum "$Bm/.gitignore")"
o="$(mem "$Bm" apply 2>/dev/null)"
if [ "$(sum "$Bm/.gitignore")" = "$s1" ] && has '^apply: no-op' "$o"; then ok "(bm) a plain apply PRESERVES the mode line (byte-identical no-op)"; else no "(bm) plain apply rewrote the branch-mode block: $(grep '^apply' <<< "$o")"; fi
mem "$Bm" apply --branch-mode off >/dev/null 2>&1
mem "$Bo" apply >/dev/null 2>&1
if cmp -s "$Bm/.gitignore" "$Bo/.gitignore"; then ok "(bm) apply --branch-mode off restores the default block byte-for-byte"; else no "(bm) --branch-mode off differs from a default apply"; fi
[ "$(mem "$Bm" mode 2>/dev/null)" = "off" ] && ok "(bm) mode prints 'off' after --branch-mode off" || no "(bm) mode after off"
mem "$Bm" apply --branch-mode loomwright-meta >/dev/null 2>&1
mem "$Bm" remove >/dev/null 2>&1
if grep -qF '>>> loomwright /setup memory BEGIN' "$Bm/.gitignore" || grep -qF "$MLINE" "$Bm/.gitignore"; then no "(bm) remove left the block or the mode line"; else ok "(bm) remove deletes the whole block, mode line included"; fi
[ "$(mem "$Bm" mode 2>/dev/null)" = "off" ] && ok "(bm) mode prints 'off' after remove" || no "(bm) mode after remove"
# The three unknown shapes.
Bu="$(newgit)"; printf '.supervisor/\n' > "$Bu/.gitignore"; mem "$Bu" apply --branch-mode loomwright-meta >/dev/null 2>&1
awk -v m="${MLINE}other" '{print} index($0, "# loomwright-meta-branch: ") == 1 {print m}' "$Bu/.gitignore" > "$Bu/g" && mv "$Bu/g" "$Bu/.gitignore"
mu="$(mem "$Bu" mode 2>/dev/null)"
case "$mu" in "unknown "*) ok "(bm) two mode lines ⇒ mode prints 'unknown …' ($mu)" ;; *) no "(bm) two mode lines ⇒ '$mu'" ;; esac
su="$(sum "$Bu/.gitignore")"; o="$(mem "$Bu" apply 2>/dev/null)"
if has '^apply: ABORTED' "$o" && [ "$(sum "$Bu/.gitignore")" = "$su" ]; then ok "(bm) a plain apply on an unknown mode is refused (nothing written)"; else no "(bm) plain apply on unknown mode: $(grep '^apply' <<< "$o")"; fi
Bi="$(newgit)"; printf '.supervisor/\n' > "$Bi/.gitignore"; mem "$Bi" apply --branch-mode loomwright-meta >/dev/null 2>&1
sed 's/^# loomwright-meta-branch: loomwright-meta$/# loomwright-meta-branch: bad..name/' "$Bi/.gitignore" > "$Bi/g" && mv "$Bi/g" "$Bi/.gitignore"
mi="$(mem "$Bi" mode 2>/dev/null)"
case "$mi" in "unknown "*) ok "(bm) an invalid branch in the mode line ⇒ 'unknown …' ($mi)" ;; *) no "(bm) invalid mode-line branch ⇒ '$mi'" ;; esac
Bd="$(newgit)"; printf '.supervisor/\n' > "$Bd/.gitignore"; mem "$Bd" apply --branch-mode loomwright-meta >/dev/null 2>&1
# Via a temp file: GNU grep refuses a file that is both its input and its output (BSD grep allows it).
grep -F '>>> loomwright /setup memory BEGIN' "$Bd/.gitignore" > "$Bd/dup" && cat "$Bd/dup" >> "$Bd/.gitignore" && rm -f "$Bd/dup"
md="$(mem "$Bd" mode 2>/dev/null)"
case "$md" in "unknown unparseable"*) ok "(bm) a sentinel-sanity failure ⇒ 'unknown …' ($md)" ;; *) no "(bm) duplicated sentinel ⇒ '$md'" ;; esac
[ "$(mem "$Bd" mode 2>/dev/null | wc -l | tr -d ' ')" = 1 ] && ok "(bm) mode always prints exactly ONE line" || no "(bm) mode printed more than one line"

echo "== (bm-r) the mode READER decides 'off' from CONTENT, never from the writer's rewrite-safety gate =="
# A repo that NEVER opted in (no mode-line text anywhere) must read `off` even when its .gitignore
# is one apply would refuse to rewrite (read-only, conflict-marked, NUL bytes, not a regular file):
# `unknown` ABORTs /automate entry (meta-entry) and fails trail-pr, so a writer-gate verdict leaking
# into the reader turns every such repo's run into a failure. `unknown` stays for the cases where a
# mode line could exist: an unreadable file, or mode-line text inside a structurally broken file.
bmr_mode() { mem "$1" mode 2>/dev/null; }
Br="$(newgit)"; printf 'node_modules/\n.supervisor/\n' > "$Br/.gitignore"; chmod 444 "$Br/.gitignore"
[ "$(bmr_mode "$Br")" = "off" ] && ok "(bm-r) no mode line + read-only .gitignore ⇒ 'off'" || no "(bm-r) read-only, never opted in ⇒ '$(bmr_mode "$Br")'"
chmod 644 "$Br/.gitignore"
Bc="$(newgit)"; printf 'node_modules/\n<<<<<<< HEAD\na/\n=======\nb/\n>>>>>>> other\n' > "$Bc/.gitignore"
[ "$(bmr_mode "$Bc")" = "off" ] && ok "(bm-r) no mode line + conflict markers ⇒ 'off'" || no "(bm-r) conflict-marked, never opted in ⇒ '$(bmr_mode "$Bc")'"
Bn="$(newgit)"; printf 'node_modules/\nx\000y\n' > "$Bn/.gitignore"
[ "$(bmr_mode "$Bn")" = "off" ] && ok "(bm-r) no mode line + NUL bytes ⇒ 'off'" || no "(bm-r) NUL bytes, never opted in ⇒ '$(bmr_mode "$Bn")'"
Bk="$(newgit)"; mkdir "$Bk/.gitignore" || setup_fail "(bm-r) mkdir failed — $Bk/.gitignore could not be made a directory"
[ "$(bmr_mode "$Bk")" = "off" ] && ok "(bm-r) .gitignore is a directory (no content) ⇒ 'off'" || no "(bm-r) directory .gitignore ⇒ '$(bmr_mode "$Bk")'"
# Opted in + read-only: writability is irrelevant to a reader — the mode is still readable.
Bro="$(newgit)"; printf '.supervisor/\n' > "$Bro/.gitignore"; mem "$Bro" apply --branch-mode loomwright-meta >/dev/null 2>&1; chmod 444 "$Bro/.gitignore"
[ "$(bmr_mode "$Bro")" = "on loomwright-meta" ] && ok "(bm-r) branch-mode block + read-only .gitignore ⇒ 'on loomwright-meta'" || no "(bm-r) read-only branch-mode ⇒ '$(bmr_mode "$Bro")'"
sro="$(sum "$Bro/.gitignore")"; o="$(mem "$Bro" apply 2>/dev/null)"
if has '^apply: ABORTED' "$o" && [ "$(sum "$Bro/.gitignore")" = "$sro" ]; then ok "(bm-r) the WRITER still refuses a read-only .gitignore (gate unchanged for apply)"; else no "(bm-r) apply on read-only: $(grep '^apply' <<< "$o")"; fi
chmod 644 "$Bro/.gitignore"
# Opted in + structurally broken: a mode line could be one side of a conflict ⇒ stays loud.
Bco="$(newgit)"; printf '.supervisor/\n' > "$Bco/.gitignore"; mem "$Bco" apply --branch-mode loomwright-meta >/dev/null 2>&1
printf '<<<<<<< HEAD\na/\n=======\nb/\n>>>>>>> other\n' >> "$Bco/.gitignore"
case "$(bmr_mode "$Bco")" in "unknown unparseable: .gitignore contains unresolved git conflict markers") ok "(bm-r) mode line + conflict markers ⇒ 'unknown …' (loud)" ;; *) no "(bm-r) mode line + conflict ⇒ '$(bmr_mode "$Bco")'" ;; esac
# Unreadable: a mode line cannot be ruled out, so 'off' would be a claim about content never read.
if [ "$(id -u)" = 0 ]; then
  ok "(bm-r) running as root — the chmod-000 unreadable fixture is skipped (root bypasses mode bits)"
else
  Bur="$(newgit)"; printf 'node_modules/\n' > "$Bur/.gitignore"; chmod 000 "$Bur/.gitignore" \
    || setup_fail "(bm-r) chmod 000 failed on $Bur/.gitignore"
  case "$(bmr_mode "$Bur")" in "unknown .gitignore is not readable"*) ok "(bm-r) unreadable .gitignore ⇒ 'unknown …' (cannot rule a mode line out)" ;; *) no "(bm-r) unreadable ⇒ '$(bmr_mode "$Bur")'" ;; esac
  chmod 644 "$Bur/.gitignore"
fi
# A no-opt-in odd file must leave the plain-apply/check paths exactly as before: apply still aborts on
# the writer gate (conflict markers), nothing written.
sc="$(sum "$Bc/.gitignore")"; o="$(mem "$Bc" apply 2>/dev/null)"
if has '^apply: ABORTED — unparseable: .gitignore contains unresolved git conflict markers' "$o" && [ "$(sum "$Bc/.gitignore")" = "$sc" ]; then ok "(bm-r) apply on a conflict-marked never-opted-in file still aborts on the writer gate"; else no "(bm-r) apply on conflict-marked: $(grep '^apply' <<< "$o")"; fi
# Mutation control: a copy whose read_mode consults the WRITER's gate (the pre-fix shape) MUST turn
# the conflict-marked 'off' assertion red — proves the assertion above is load-bearing.
BMR_MUT="$(mktemp -d)"
sed -e 's/^  grep -qF -- "\$MODE_PREFIX" "\$GI" 2>\/dev\/null || rc=\$?$/  :/' \
    -e 's/gate="\$(gitignore_gate read)"/gate="$(gitignore_gate)"/' "$MEMB" > "$BMR_MUT/setup-memory.sh"
if cmp -s "$MEMB" "$BMR_MUT/setup-memory.sh"; then
  no "(bm-r) mutation control: the patch changed nothing — control inconclusive"
elif [ "$(bash "$BMR_MUT/setup-memory.sh" --root "$Bc" mode 2>/dev/null)" = "off" ]; then
  no "(bm-r) mutation control REFUTED: a reader on the writer's gate still reads 'off' for a conflict-marked file"
else
  ok "(bm-r) mutation control: a reader on the writer's gate reads '$(bash "$BMR_MUT/setup-memory.sh" --root "$Bc" mode 2>/dev/null)' — the 'off' assertion is load-bearing"
fi
rm -rf "$BMR_MUT"

echo "== (bm-v) branch names: option-shaped / reserved values refused; the accepted set is the INTERSECTION =="
# A name is valid only when it passes `git check-ref-format --branch` UNCHANGED, meta-sync.sh's own
# `git check-ref-format refs/heads/<name>`, and is not option-shaped / HEAD / @ (valid_branch_name).
# The review repro: `apply --branch-mode --root X` swallowed `--root` as the branch and wrote the
# mode line into the CWD repo's .gitignore — it must be a usage error with NOTHING written anywhere.
Bvc="$(newgit)"; printf 'node_modules/\n.supervisor/\n' > "$Bvc/.gitignore"
Bvt="$(newgit)"; printf 'node_modules/\n.supervisor/\n' > "$Bvt/.gitignore"
svc="$(sum "$Bvc/.gitignore")"; svt="$(sum "$Bvt/.gitignore")"
o="$(cd "$Bvc" && bash "$MEM" apply --branch-mode --root "$Bvt" 2>/dev/null)"; rc_v=$?
if has 'requires a value' "$o" && has "option-shaped '--root'" "$o"; then ok "(bm-v) 'apply --branch-mode --root X' is a usage error naming the option-shaped value"; else no "(bm-v) --branch-mode --root X: $o"; fi
[ "$rc_v" -eq 0 ] && ok "(bm-v) the usage error still exits 0 (fail-safe)" || no "(bm-v) --branch-mode --root X exited $rc_v"
if [ "$(sum "$Bvc/.gitignore")" = "$svc" ] && [ -z "$(ls "$Bvc"/.gitignore.backup.* 2>/dev/null)" ]; then ok "(bm-v) nothing written to the CWD repo's .gitignore (the reproduced bug)"; else no "(bm-v) --branch-mode --root X wrote the CWD repo's .gitignore"; fi
if [ "$(sum "$Bvt/.gitignore")" = "$svt" ] && [ -z "$(ls "$Bvt"/.gitignore.backup.* 2>/dev/null)" ]; then ok "(bm-v) nothing written to the target's .gitignore either"; else no "(bm-v) --branch-mode --root X wrote the target's .gitignore"; fi
if grep -qF "$MLINE" "$Bvc/.gitignore" "$Bvt/.gitignore"; then no "(bm-v) a mode line was recorded by --branch-mode --root X"; else ok "(bm-v) no mode line recorded in either repo"; fi
o="$(mem "$Bvt" apply --branch-mode -h 2>/dev/null)"
if has "option-shaped '-h'" "$o" && [ "$(sum "$Bvt/.gitignore")" = "$svt" ]; then ok "(bm-v) '--branch-mode -h' is refused as option-shaped (never prints help, nothing written)"; else no "(bm-v) --branch-mode -h: $o"; fi
for bad in HEAD '@{-1}' '@' 'a..b'; do
  o="$(mem "$Bvt" apply --branch-mode "$bad" 2>/dev/null)"
  if has 'apply: ABORTED — invalid --branch-mode branch name' "$o" && [ "$(sum "$Bvt/.gitignore")" = "$svt" ] && [ -z "$(ls "$Bvt"/.gitignore.backup.* 2>/dev/null)" ]; then ok "(bm-v) '--branch-mode $bad' is refused with nothing written"; else no "(bm-v) --branch-mode $bad: $o"; fi
done
# @{-N} would EXPAND under a cwd-relative --branch (to the previously checked-out branch) — run
# from a repo where it resolves, so the refusal cannot rest on "no previous branch" alone.
( cd "$Bvt" && git checkout -q -b vprev && git checkout -q - ) >/dev/null 2>&1
o="$(cd "$Bvt" && bash "$MEM" --root "$Bvt" apply --branch-mode '@{-1}' 2>/dev/null)"
if has 'apply: ABORTED — invalid --branch-mode branch name' "$o" && [ "$(sum "$Bvt/.gitignore")" = "$svt" ]; then ok "(bm-v) '@{-1}' is refused even where it expands to a real branch"; else no "(bm-v) resolvable @{-1}: $o"; fi
# The verdict never depends on the caller's cwd: from a DELETED cwd (where a cwd-relative
# `git check-ref-format --branch` dies with "Unable to read current working directory") a valid
# recorded mode still reads `on <branch>` and check still reads it as configured.
Bdc="$(newgit)"; printf '.supervisor/\n' > "$Bdc/.gitignore"; mem "$Bdc" apply --branch-mode loomwright-meta >/dev/null 2>&1
DCWD="$(mkfix)"
mdc="$(cd "$DCWD" && rmdir "$DCWD" && bash "$MEM" --root "$Bdc" mode 2>/dev/null)"
[ "$mdc" = "on loomwright-meta" ] && ok "(bm-v) from a deleted cwd a valid mode line still reads 'on loomwright-meta'" || no "(bm-v) deleted cwd ⇒ '$mdc'"
DCWD="$(mkfix)"
cdc="$(cd "$DCWD" && rmdir "$DCWD" && bash "$MEM" --root "$Bdc" check 2>/dev/null)"
has '^Memory readiness: configured' "$cdc" && ok "(bm-v) from a deleted cwd check still reads the branch-mode block as configured" || no "(bm-v) deleted cwd check: $(grep '^Memory readiness' <<< "$cdc")"
# A hand-written option-shaped / reserved mode line reads `unknown` (never `on -x`), and a plain
# apply on it aborts with nothing written.
for hb in '-x' 'HEAD' '--root'; do
  Bh="$(newgit)"; printf '.supervisor/\n' > "$Bh/.gitignore"; mem "$Bh" apply --branch-mode loomwright-meta >/dev/null 2>&1
  awk -v m="${MLINE}${hb}" 'index($0, "# loomwright-meta-branch: ") == 1 { print m; next } { print }' "$Bh/.gitignore" > "$Bh/g" && mv "$Bh/g" "$Bh/.gitignore"
  mh="$(mem "$Bh" mode 2>/dev/null)"
  [ "$mh" = "unknown invalid branch name '$hb' in the mode line" ] && ok "(bm-v) a hand-written '${MLINE}${hb}' line reads '$mh'" || no "(bm-v) mode line '$hb' ⇒ '$mh'"
  sh="$(sum "$Bh/.gitignore")"; o="$(mem "$Bh" apply 2>/dev/null)"
  if has '^apply: ABORTED' "$o" && [ "$(sum "$Bh/.gitignore")" = "$sh" ]; then ok "(bm-v) a plain apply on the '$hb' mode line is refused (nothing written)"; else no "(bm-v) plain apply on '$hb' mode line: $(grep '^apply' <<< "$o")"; fi
done
# A CRLF mode line is never silently stripped: it reads unknown and the reason SHOWS the \r.
Bcr="$(newgit)"; printf '.supervisor/\n' > "$Bcr/.gitignore"; mem "$Bcr" apply --branch-mode loomwright-meta >/dev/null 2>&1
awk 'index($0, "# loomwright-meta-branch: ") == 1 { printf "%s\r\n", $0; next } { print }' "$Bcr/.gitignore" > "$Bcr/g" && mv "$Bcr/g" "$Bcr/.gitignore"
mcr="$(mem "$Bcr" mode 2>/dev/null)"
[ "$mcr" = "unknown invalid branch name 'loomwright-meta\r' in the mode line" ] && ok "(bm-v) a CRLF mode line reads unknown and names the carriage return as a literal '\\r'" || no "(bm-v) CRLF mode line ⇒ '$mcr'"
# Previously-valid realistic names still round-trip: apply → mode on <name> → plain apply no-op.
for good in loomwright-meta meta/run-history feature/x_y-1 off-branch; do
  Bg="$(newgit)"; printf 'node_modules/\n.supervisor/\n' > "$Bg/.gitignore"
  o="$(mem "$Bg" apply --branch-mode "$good" 2>/dev/null)"
  has "^apply: applied (branch mode: $good)" "$o" && ok "(bm-v) '--branch-mode $good' is accepted" || no "(bm-v) --branch-mode $good: $(grep '^apply' <<< "$o")"
  [ "$(mem "$Bg" mode 2>/dev/null)" = "on $good" ] && ok "(bm-v) mode reads 'on $good'" || no "(bm-v) mode after $good: '$(mem "$Bg" mode 2>/dev/null)'"
  sg="$(sum "$Bg/.gitignore")"; o="$(mem "$Bg" apply 2>/dev/null)"
  if [ "$(sum "$Bg/.gitignore")" = "$sg" ] && has '^apply: no-op' "$o"; then ok "(bm-v) a plain apply preserves '$good' (byte-identical no-op)"; else no "(bm-v) plain apply on '$good': $(grep '^apply' <<< "$o")"; fi
done

echo "== (bm-f) the mode answer is FAIL-CLOSED: empty / malformed / unrecognised never reads 'off' =="
# Review (iteration 3): the writer mapped ANY answer that was not `on <b>` to mode off, and the reader
# turned an EMPTY mode value or a near-miss mode line (indented, no space after the colon) into
# `off` — so a plain apply silently rewrote a branch-mode block as the default one (mode line gone,
# run history re-included). Only an exact `off` or a valid `on <b>` may pass; everything else is
# `unknown …`, and a plain apply on `unknown` aborts with nothing written.
bmf_fix() { local d; d="$(newgit)"; printf '.supervisor/\n' > "$d/.gitignore"; mem "$d" apply --branch-mode loomwright-meta >/dev/null 2>&1; printf '%s\n' "$d"; }
bmf_sub() { awk -v m="$2" 'index($0, "# loomwright-meta-branch: ") == 1 { print m; next } { print }' "$1/.gitignore" > "$1/g" && mv "$1/g" "$1/.gitignore"; }
bmf_nbk() { ls "$1"/.gitignore.backup.* 2>/dev/null | wc -l | tr -d ' '; }
bmf_refused() {  # <script> <repo> <label> — plain apply ABORTs, .gitignore byte-identical, no NEW backup
  local s0 b0 o; s0="$(sum "$2/.gitignore")"; b0="$(bmf_nbk "$2")"; o="$(bash "$1" --root "$2" apply 2>/dev/null)"
  if has '^apply: ABORTED — the managed block' "$o" && [ "$(sum "$2/.gitignore")" = "$s0" ] && [ "$(bmf_nbk "$2")" = "$b0" ]; then ok "(bm-f) $3: a plain apply is refused, .gitignore unchanged, no new backup"; else no "(bm-f) $3: plain apply: $(grep '^apply' <<< "$o")"; fi
}
# (1) EMPTY branch value inside the sentinels.
Bfe="$(bmf_fix)"; bmf_sub "$Bfe" "$MLINE"
mfe="$(mem "$Bfe" mode 2>/dev/null)"
[ "$mfe" = "unknown invalid branch name '' in the mode line" ] && ok "(bm-f) an EMPTY mode-line branch reads '$mfe'" || no "(bm-f) empty mode-line branch ⇒ '$mfe'"
bmf_refused "$MEM" "$Bfe" "empty mode-line branch"
has '^  branch mode:       unknown invalid branch name' "$(mem "$Bfe" check 2>/dev/null)" && ok "(bm-f) check names the unknown mode (never silent)" || no "(bm-f) check on an empty mode-line branch printed no unknown mode line"
# (2) near-miss shapes inside the sentinels: indented, no space after the colon, bare colon.
for nm in "  ${MLINE}loomwright-meta" '# loomwright-meta-branch:loomwright-meta' '# loomwright-meta-branch:'; do
  Bfn="$(bmf_fix)"; bmf_sub "$Bfn" "$nm"
  mfn="$(mem "$Bfn" mode 2>/dev/null)"
  case "$mfn" in "unknown a malformed mode line in the managed block"*) ok "(bm-f) near-miss '$nm' reads 'unknown …'" ;; *) no "(bm-f) near-miss '$nm' ⇒ '$mfn'" ;; esac
  bmf_refused "$MEM" "$Bfn" "near-miss '$nm'"
done
# (3) the never-opted-in invariant holds for mode text OUTSIDE the sentinels, exact or near-miss.
Bfo="$(newgit)"; printf 'node_modules/\n%sx\n# loomwright-meta-branch:y\n  %sz\n' "$MLINE" "$MLINE" > "$Bfo/.gitignore"
[ "$(mem "$Bfo" mode 2>/dev/null)" = "off" ] && ok "(bm-f) mode text only OUTSIDE the sentinels (no block) ⇒ 'off'" || no "(bm-f) outside-only, no block ⇒ '$(mem "$Bfo" mode 2>/dev/null)'"
mem "$Bfo" apply >/dev/null 2>&1
[ "$(mem "$Bfo" mode 2>/dev/null)" = "off" ] && ok "(bm-f) mode text only OUTSIDE a default block ⇒ 'off'" || no "(bm-f) outside-only, default block ⇒ '$(mem "$Bfo" mode 2>/dev/null)'"
sfo="$(sum "$Bfo/.gitignore")"; o="$(mem "$Bfo" apply 2>/dev/null)"
if has '^apply: no-op' "$o" && [ "$(sum "$Bfo/.gitignore")" = "$sfo" ]; then ok "(bm-f) a plain re-apply there is still a byte-identical no-op"; else no "(bm-f) re-apply with outside-only mode text: $(grep '^apply' <<< "$o")"; fi
# (4) a crashed / garbage reader: stub read_mode in a scratch copy (the review's repro).
BMF_D="$(mktemp -d)"
cp "$HERE/contained-path-lib.sh" "$BMF_D/" || setup_fail "(bm-f) could not place contained-path-lib.sh beside the stubs (apply loads it from the entry's dir)"
bmf_stub() { awk -v s="$2" '/^resolve_effective_branch$/ { print s } { print }' "$MEMB" > "$BMF_D/$1.sh"; }
bmf_stub empty 'read_mode() { return 0; }'
bmf_stub garbage 'read_mode() { echo garbage; }'
bmf_stub onempty 'read_mode() { echo "on "; }'
for st in empty garbage onempty; do
  Bfs="$(bmf_fix)"
  mfs="$(bash "$BMF_D/$st.sh" --root "$Bfs" mode 2>/dev/null)"
  case "$mfs" in "unknown mode reader returned"*) ok "(bm-f) stubbed reader ($st) ⇒ mode prints '$mfs'" ;; *) no "(bm-f) stubbed reader ($st) ⇒ mode '$mfs'" ;; esac
  bmf_refused "$BMF_D/$st.sh" "$Bfs" "stubbed reader ($st)"
done
has '^  branch mode:       unknown mode reader returned' "$(bash "$BMF_D/empty.sh" --root "$Bfs" check 2>/dev/null)" && ok "(bm-f) check with a crashed reader names the unknown mode" || no "(bm-f) check with a crashed reader is silent about the mode"
# Mutation controls — each restores ONE pre-fix shape in a scratch copy and MUST turn the matching
# assertion above red (a copy the patch did not change is reported inconclusive, never green).
bmf_mut() {  # <name> <label> <repo> <expect-mode-not> ; runs plain apply, reports whether it was refused
  local s0 o
  if cmp -s "$MEMB" "$BMF_D/$1.sh"; then no "(bm-f) mutation control '$2': the patch changed nothing — inconclusive"; return; fi
  s0="$(sum "$3/.gitignore")"; o="$(bash "$BMF_D/$1.sh" --root "$3" apply 2>/dev/null)"
  if [ "$(sum "$3/.gitignore")" != "$s0" ] && ! has '^apply: ABORTED' "$o"; then ok "(bm-f) mutation control '$2': the pre-fix shape REWRITES the branch-mode block — the assertion is load-bearing"; else no "(bm-f) mutation control '$2' REFUTED: the pre-fix shape still refuses ($(grep '^apply' <<< "$o"))"; fi
}
# (a) the old catch-all: an unrecognised answer resolves to off.
{ awk '/^resolve_effective_branch$/ { print "read_mode() { return 0; }"; print "normalize_mode() { case \"$1\" in \"on \"*|unknown*) printf \"%s\\n\" \"$1\" ;; *) echo off ;; esac; }" } { print }' "$MEMB"; } > "$BMF_D/m_catchall.sh"
bmf_mut m_catchall "old catch-all (empty reader ⇒ off)" "$(bmf_fix)"
# (b) the old reader: no per-match marker, so an EMPTY value is empty output ⇒ off.
sed -e 's/print "L" substr(\$0, length(m) + 1); next/print substr($0, length(m) + 1); next/' -e 's/b="\${lines#L}"/b="$lines"/' "$MEMB" > "$BMF_D/m_nomarker.sh"
Bfm="$(bmf_fix)"; bmf_sub "$Bfm" "$MLINE"; bmf_mut m_nomarker "no per-match marker (empty value ⇒ off)" "$Bfm"
# (c) the old reader: in-block near-miss lines are not flagged.
grep -v 'inblk && index(\$0, t) > 0 { print "X" }' "$MEMB" > "$BMF_D/m_nonearmiss.sh"
Bfm="$(bmf_fix)"; bmf_sub "$Bfm" "  ${MLINE}loomwright-meta"; bmf_mut m_nonearmiss "near-miss not flagged (indented ⇒ off)" "$Bfm"
# (d) the old pre-check: only the exact prefix (with its trailing space) is searched for.
grep -v 'then rc=0; grep -qF -- "\$MODE_TOKEN"' "$MEMB" > "$BMF_D/m_prefixonly.sh"
Bfm="$(bmf_fix)"; bmf_sub "$Bfm" '# loomwright-meta-branch:loomwright-meta'; bmf_mut m_prefixonly "prefix-only pre-check (no-space ⇒ off)" "$Bfm"
rm -rf "$BMF_D"
# (5) the reader must not crash in its subshell: a temporary LC_ALL on a command inside a command
# substitution SEGFAULTs Homebrew bash 5.3 on macOS a few percent of the time (dispose_temporary_env
# → setlocale → CoreFoundation after fork), and a crashed reader is now — correctly — `unknown`. So
# read_mode carries no `LC_ALL=` prefix at all; pinned structurally (the crash itself is flaky).
# The same shape is banned repo-wide by scripts/check-locale-prefix.sh (CI gate); this pin is the
# reader's local, stricter form (no LC_ALL= at all, not even through env).
if awk '/^read_mode\(\) \{/ { f = 1 } f && /^}/ { exit } f && !/^[ \t]*#/ && /LC_ALL=/ { bad = 1 } END { exit !bad }' "$MEMB"; then no "(bm-f) read_mode carries an LC_ALL= temp-env prefix (crash-prone in a subshell)"; else ok "(bm-f) read_mode carries no LC_ALL= temp-env prefix"; fi
# (6) the realistic round trip is untouched: mode on → plain apply byte-identical no-op → mode on.
Bfr="$(bmf_fix)"; sfr="$(sum "$Bfr/.gitignore")"; o="$(mem "$Bfr" apply 2>/dev/null)"
if has '^apply: no-op' "$o" && [ "$(sum "$Bfr/.gitignore")" = "$sfr" ] && [ "$(mem "$Bfr" mode 2>/dev/null)" = "on loomwright-meta" ]; then ok "(bm-f) a valid branch-mode block still round-trips (plain apply no-op, mode on)"; else no "(bm-f) valid round trip: $(grep '^apply' <<< "$o")"; fi
# (7) a MULTI-LINE reader answer whose first line is a valid `on <b>`: the `on ` arm must apply the
# same one-line rule as the catch-all — exactly ONE `unknown …` line, never `on x`, never two lines.
BML_D="$(mktemp -d)"
awk '/^resolve_effective_branch$/ { print "read_mode() { printf '"'"'on x\\nextra\\n'"'"'; }" } { print }' "$MEMB" > "$BML_D/multiline.sh"
Bml="$(bmf_fix)"; mml="$(bash "$BML_D/multiline.sh" --root "$Bml" mode 2>/dev/null)"
[ "$(printf '%s\n' "$mml" | wc -l | tr -d ' ')" = 1 ] && ok "(bm-f) stubbed two-line reader ('on x' + 'extra') ⇒ mode prints exactly ONE line" || no "(bm-f) stubbed two-line reader ⇒ mode printed $(printf '%s\n' "$mml" | wc -l | tr -d ' ') lines: $mml"
case "$mml" in "unknown "*) ok "(bm-f) stubbed two-line reader ⇒ 'unknown …' ($mml)" ;; *) no "(bm-f) stubbed two-line reader ⇒ '$mml' (must be unknown, never on x)" ;; esac
rm -rf "$BML_D"

echo "== (fn) owner fix-now: branch-mode check wording, option-shaped flag values, reserved 'off', scoped reader =="
# (fn-1) BRANCH MODE: `check` reports the ledger honestly and PROBES it in the must-stay-ignored set;
# the disclosure and apply's Next: hint describe the branch-mode block. Seeded with a FOREIGN ledger
# record on purpose: the block never un-ignores the ledger here, so `gated` (and its filter-ledger
# remedy) would describe a write that cannot happen.
fn_unint() { awk '/^  unintended \(must stay ignored\):/ { f = 1; next } /^  tracked today:/ { f = 0 } f' <<< "$1"; }
fn_int()   { awk '/^  intended \(must be committable\):/ { f = 1; next } /^  unintended / { f = 0 } f' <<< "$1"; }
fn_bm_fixture() { local d; d="$(newgit https://github.com/acme/widgets.git)"; printf '.supervisor/\n' > "$d/.gitignore"
  mkdir -p "$d/.supervisor/postmortem"; printf '{"repo":"acme/widgets"}\n{"repo": "other/secret"}\n' > "$d/.supervisor/postmortem/results.jsonl"; printf '%s' "$d"; }
fn_check_assert() {  # <script> <label> — 0 when every branch-mode check expectation holds
  local d o; d="$(fn_bm_fixture)"; bash "$1" --root "$d" apply --branch-mode loomwright-meta >/dev/null 2>&1
  o="$(bash "$1" --root "$d" check 2>/dev/null)"
  hasF '.supervisor/postmortem/results.jsonl                     branch mode — on loomwright-meta, stays ignored here' "$(fn_int "$o")" \
    && hasF '.supervisor/postmortem/results.jsonl                     ignored' "$(fn_unint "$o")" \
    && ! hasF 'not probed (jq unavailable' "$o" && ! hasF 'GATED' "$o" \
    && hasF 'Memory readiness: configured' "$o"
}
if fn_check_assert "$MEM"; then ok "(fn-1) branch-mode check: ledger listed as 'branch mode — on loomwright-meta, stays ignored here', probed 'ignored' in the must-stay-ignored set, readiness configured (never gated / never 'jq unavailable')"; else no "(fn-1) branch-mode check ledger wording/probe"; fi
Bfn="$(fn_bm_fixture)"; oa="$(mem "$Bfn" apply --branch-mode loomwright-meta 2>/dev/null)"; oc="$(mem "$Bfn" check 2>/dev/null)"
for o_lbl in "apply:$oa" "check:$oc"; do
  lbl="${o_lbl%%:*}"; o="${o_lbl#*:}"
  if hasF 'What becomes VERSION-CONTROLLED if you apply this (BRANCH MODE — metadata branch `loomwright-meta`):' "$o" \
     && hasF 'so there is nothing to commit for run history on this branch' "$o" \
     && hasF 'Untracking it is a separate, deliberate operator step (migrate-branch-mode.sh plan), never this' "$o" \
     && ! hasF '.supervisor/requirements/** — the intake' "$o" && ! hasF 'GATED: it is un-ignored only while' "$o"; then
    ok "(fn-1) $lbl prints the BRANCH-MODE disclosure (memory stores only; run history on the metadata branch; untracking starts at migrate-branch-mode.sh plan, not this helper)"
  else no "(fn-1) $lbl disclosure still describes the default block"; fi
done
if hasF '  git status --short .claude/agent-memory .supervisor/memory' "$oa" && ! hasF '.supervisor/memory .supervisor/requirements' "$oa" \
   && hasF "Run history lives on the metadata branch 'loomwright-meta' (meta-sync.sh)," "$oa" \
   && hasF 'not on this branch — there is nothing to commit for it here.' "$oa" && hasF '(migrate-branch-mode.sh plan), never this' "$oa"; then
  ok "(fn-1) apply --branch-mode Next: hint names only the two memory stores and says run history lives on the metadata branch"
else no "(fn-1) apply --branch-mode Next: hint: $(grep -A5 '^Next:' <<< "$oa")"; fi
o="$(mem "$Bfn" apply 2>/dev/null)"
if has '^apply: no-op — already configured (the managed block' "$o" && ! hasF 'GATED' "$o"; then ok "(fn-1) plain re-apply in branch mode with a foreign ledger: plain no-op headline, never 'GATED'"; else no "(fn-1) branch-mode no-op headline: $(grep '^apply' <<< "$o")"; fi
o="$(mem "$Bfn" remove 2>/dev/null)"
! hasF 'not probed (jq unavailable' "$o" && ok "(fn-1) remove from branch mode: the verify report never claims 'jq unavailable' (reads the file it just wrote)" || no "(fn-1) remove from branch mode still reports 'not probed (jq unavailable …)'"
# Mode OFF keeps the default copy (byte identity vs origin/main is proven out-of-band with cmp).
Bfo2="$(newgit https://github.com/acme/widgets.git)"; printf '.supervisor/\n' > "$Bfo2/.gitignore"; o="$(mem "$Bfo2" check 2>/dev/null)"
if has '^What becomes VERSION-CONTROLLED if you apply this:$' "$o" && ! hasF 'branch mode' "$o"; then ok "(fn-1) mode off: default disclosure, no branch-mode wording anywhere in check"; else no "(fn-1) mode off check carries branch-mode wording"; fi
# Mutation self-check: a copy that never records the disk branch makes the (fn-1) check assertion fail.
FN_D="$(mktemp -d)"
cp "$HERE/contained-path-lib.sh" "$FN_D/" || setup_fail "(fn-1) could not place contained-path-lib.sh beside the mutants (apply loads it from the entry's dir)"
sed 's/^      r_branch="\${r_mode#on }"$/      :/' "$MEMB" > "$FN_D/mut1.sh"
if cmp -s "$MEMB" "$FN_D/mut1.sh"; then no "(fn-1) mutation self-check: the patch changed nothing — inconclusive"
elif fn_check_assert "$FN_D/mut1.sh"; then no "(fn-1) mutation self-check: the branch-mode check assertion is VACUOUS (passes without r_branch)"
else ok "(fn-1) mutation self-check: dropping the disk-branch capture fails the branch-mode check assertion"; fi

# (fn-2) --root / --ledger / --allow: an EMPTY or option-shaped value is a usage error — exit 0,
# stderr names the flag, NOTHING written. --root is run with the cwd inside a fixture so a silent
# fall-back to the cwd repo would show up as a written .gitignore there.
for fv in "--root|-x" "--root|--branch-mode" "--root|" "--ledger|-x" "--ledger|" "--allow|-x" "--allow|--root" "--allow|"; do
  fl="${fv%%|*}"; vv="${fv#*|}"
  Dfv="$(newgit https://github.com/acme/widgets.git)"; printf '.supervisor/\n' > "$Dfv/.gitignore"; s0="$(sum "$Dfv/.gitignore")"
  if [ "$fl" = "--root" ]; then
    err="$(cd "$Dfv" && bash "$MEM" "$fl" "$vv" apply 2>&1 >/dev/null)"; rc=$?
  else
    err="$(bash "$MEM" --root "$Dfv" "$fl" "$vv" apply 2>&1 >/dev/null)"; rc=$?
  fi
  if [ "$rc" = 0 ] && hasF "setup-memory: $fl requires" "$err" && hasF 'Nothing was written.' "$err" \
     && [ "$(sum "$Dfv/.gitignore")" = "$s0" ] && [ -z "$(ls "$Dfv"/.gitignore.backup.* 2>/dev/null)" ] && [ ! -e "$Dfv/.supervisor/config.json" ]; then
    ok "(fn-2) '$fl ${vv:-<empty>}' is a usage error: exit 0, stderr names it, nothing written"
  else no "(fn-2) '$fl ${vv:-<empty>}': rc=$rc err='$err'"; fi
done
err="$(bash "$MEM" --root "$Dfv" filter-ledger --ledger -x 2>&1 >/dev/null)"
hasF "got option-shaped '-x'" "$err" && ok "(fn-2) 'filter-ledger --ledger -x' names the option-shaped value" || no "(fn-2) filter-ledger --ledger -x: $err"
o="$(bash "$MEM" --root "$Dfv" --allow acme/widgets --allow owner/old-name allowlist 2>/dev/null)"
[ "$o" = "acme/widgets
owner/old-name" ] && ok "(fn-2) valid --allow values are unchanged" || no "(fn-2) valid --allow values: '$o'"

# (fn-4) `off` is RESERVED: a hand-written `off` mode line reads unknown (never `on off`, never
# silently `off`), a plain apply refuses it, and `--branch-mode off` is still the switch-off spelling.
Bro="$(bmf_fix)"; bmf_sub "$Bro" "${MLINE}off"
mro="$(mem "$Bro" mode 2>/dev/null)"
[ "$mro" = "unknown invalid branch name 'off' in the mode line" ] && ok "(fn-4) a hand-written 'off' mode line reads '$mro'" || no "(fn-4) 'off' mode line ⇒ '$mro'"
bmf_refused "$MEM" "$Bro" "reserved 'off' mode line"
o="$(mem "$Bro" apply --branch-mode off 2>/dev/null)"
if has '^apply: applied' "$o" && [ "$(mem "$Bro" mode 2>/dev/null)" = "off" ] && ! grep -qF "$MLINE" "$Bro/.gitignore"; then ok "(fn-4) '--branch-mode off' resolves it: mode 'off', no mode line recorded"; else no "(fn-4) --branch-mode off on an 'off' line: $(grep '^apply' <<< "$o")"; fi
Bon="$(bmf_fix)"; o="$(mem "$Bon" apply --branch-mode off 2>/dev/null)"
if has '^apply: applied' "$o" && [ "$(mem "$Bon" mode 2>/dev/null)" = "off" ] && ! grep -qF "$MLINE" "$Bon/.gitignore"; then ok "(fn-4) '--branch-mode off' still switches a branch-mode block off"; else no "(fn-4) --branch-mode off: $(grep '^apply' <<< "$o")"; fi
awk '/^resolve_effective_branch$/ { print "read_mode() { echo \"on off\"; }" } { print }' "$MEMB" > "$FN_D/onoff.sh"
mrs="$(bash "$FN_D/onoff.sh" --root "$Bon" mode 2>/dev/null)"
[ "$mrs" = "unknown mode reader returned an invalid branch 'off'" ] && ok "(fn-4) a reader answering 'on off' normalises to '$mrs'" || no "(fn-4) 'on off' reader ⇒ '$mrs'"
hasF 'RESERVED' "$(bash "$MEM" --help 2>/dev/null)" && ok "(fn-4) --help states that 'off' is reserved" || no "(fn-4) --help is silent about the reserved 'off'"
o="$(bash "$MEM" --root "$Bon" apply --branch-mode 2>/dev/null)"
hasF 'or off (reserved — never a branch name)' "$o" && ok "(fn-4) the --branch-mode usage error states 'off' is reserved" || no "(fn-4) --branch-mode usage: $o"
# commands/setup.md is a router since automate-speed/22 (§Branch mode lives in a part): the two doc
# checks below read the ASSEMBLED text (router + docs/command-parts/setup/), written once.
SETUP_ASM="$FIXTURE_ROOT/setup-assembled.md"
bash "$HERE/fixtures/automate-loop-split/assemble.sh" "$HERE/../commands/setup.md" "$SETUP_ASM" \
  || no "(fn-4) cannot assemble commands/setup.md (router + docs/command-parts/setup/)"
hasF '**`off` is reserved**' "$(cat "$SETUP_ASM" 2>/dev/null)" && ok "(fn-4) commands/setup.md §Branch mode states 'off' is reserved" || no "(fn-4) commands/setup.md does not state 'off' is reserved"
hasF '`branch mode — on <branch>, stays ignored here`' "$(cat "$SETUP_ASM" 2>/dev/null)" && ok "(fn-1) commands/setup.md §Branch mode documents the branch-mode ledger line the helper prints" || no "(fn-1) commands/setup.md does not document the branch-mode ledger line"
sed 's/-\*|HEAD|@|off) return 1/-*|HEAD|@) return 1/' "$MEMB" > "$FN_D/mut4.sh"
Bro2="$(bmf_fix)"; bmf_sub "$Bro2" "${MLINE}off"
mm="$(bash "$FN_D/mut4.sh" --root "$Bro2" mode 2>/dev/null)"
if cmp -s "$MEMB" "$FN_D/mut4.sh"; then no "(fn-4) mutation self-check: the patch changed nothing — inconclusive"
elif [ "$mm" = "on off" ]; then ok "(fn-4) mutation self-check: without the reservation the 'off' line reads 'on off' (the assertion above is load-bearing)"
else no "(fn-4) mutation self-check: unreserved copy ⇒ '$mm'"; fi

# (fn-5) allowlist / filter-ledger never run read_mode: a stub that leaves a marker proves it, and the
# same stub DOES fire for check / mode (positive control). A mutant without the subcommand scope
# fires for allowlist too (the probe is not vacuous).
fn_stub() { awk -v s="read_mode() { echo called >> \"$2\"; echo off; }" '/^resolve_effective_branch$/ { print s } { print }' "$1"; }
Bsc="$(newgit https://github.com/acme/widgets.git)"; printf '.supervisor/\n' > "$Bsc/.gitignore"
mkdir -p "$Bsc/.supervisor/postmortem"; printf '{"repo":"acme/widgets"}\n' > "$Bsc/.supervisor/postmortem/results.jsonl"
fn_stub "$MEMB" "$FN_D/mark" > "$FN_D/stub.sh"
for sc in "allowlist" "filter-ledger --ledger $Bsc/.supervisor/postmortem/results.jsonl"; do
  rm -f "$FN_D/mark"
  # shellcheck disable=SC2086
  bash "$FN_D/stub.sh" --root "$Bsc" $sc >/dev/null 2>&1
  [ ! -e "$FN_D/mark" ] && ok "(fn-5) '${sc%% *}' never runs read_mode" || no "(fn-5) '${sc%% *}' ran read_mode $(wc -l < "$FN_D/mark" | tr -d ' ')x"
done
for sc in check mode; do
  rm -f "$FN_D/mark"; bash "$FN_D/stub.sh" --root "$Bsc" "$sc" >/dev/null 2>&1
  [ -s "$FN_D/mark" ] && ok "(fn-5) positive control: '$sc' does run read_mode" || no "(fn-5) positive control: '$sc' never ran read_mode (the probe is blind)"
done
grep -v '^  case "\$SUBCMD" in apply|check|mode) ;; \*) return 0 ;; esac$' "$MEMB" > "$FN_D/mut5.sh"
fn_stub "$FN_D/mut5.sh" "$FN_D/mark" > "$FN_D/stub5.sh"; rm -f "$FN_D/mark"; bash "$FN_D/stub5.sh" --root "$Bsc" allowlist >/dev/null 2>&1
if cmp -s "$MEMB" "$FN_D/mut5.sh"; then no "(fn-5) mutation self-check: the patch changed nothing — inconclusive"
elif [ -s "$FN_D/mark" ]; then ok "(fn-5) mutation self-check: without the subcommand scope 'allowlist' runs read_mode (the probe is load-bearing)"
else no "(fn-5) mutation self-check: unscoped copy still shows no read_mode for allowlist"; fi
rm -rf "$FN_D"

echo "== (vb) valid-branch <name>: the SAME valid_branch_name predicate apply uses, exit code = answer, writes nothing =="
# A caller (migrate-branch-mode.sh) must vet a branch name BEFORE anything is written; `apply`
# exits 0 on a refusal, so only this predicate's exit code can answer. It must be the one
# predicate `apply --branch-mode` uses (a copy could drift), and it must write nothing.
Vb="$(newgit https://github.com/acme/widgets.git)"; printf 'node_modules/\n.supervisor/\n' > "$Vb/.gitignore"
vb_snap() { (cd "$1" && find . -path ./.git -prune -o -type f -print | env LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done; git status --porcelain; git rev-parse HEAD) 2>/dev/null; }
vb_before="$(vb_snap "$Vb")"
# vb_run <name> — run valid-branch with the fixture as BOTH the cwd and --root; sets VB_RC / VB_ERR / VB_OUT.
vb_run() { VB_ERR="$(cd "$Vb" && bash "$MEM" --root "$Vb" valid-branch "$1" 2>&1 >"$FIXTURE_ROOT/vb.out")"; VB_RC=$?; VB_OUT="$(cat "$FIXTURE_ROOT/vb.out")"; }
for good in loomwright-meta team-meta lane/z; do
  vb_run "$good"
  if [ "$VB_RC" -eq 0 ] && [ -z "$VB_ERR" ] && [ -z "$VB_OUT" ]; then ok "(vb) '$good' is accepted: exit 0, silent"; else no "(vb) '$good' ⇒ rc=$VB_RC err='$VB_ERR' out='$VB_OUT'"; fi
done
for bad in off HEAD @ -x --root 'a..b' '@{-1}' 'bad name' ''; do
  vb_run "$bad"
  nl="$(printf '%s\n' "$VB_ERR" | awk 'END { print NR }')"
  if [ "$VB_RC" -eq 1 ] && [ "$nl" -eq 1 ] && hasF "valid-branch: '$bad' is not a valid metadata branch name" "$VB_ERR" && [ -z "$VB_OUT" ]; then ok "(vb) '$bad' is refused: exit 1, ONE reason line on stderr"; else no "(vb) '$bad' ⇒ rc=$VB_RC lines=$nl err='$VB_ERR' out='$VB_OUT'"; fi
done
VB_ERR="$(bash "$MEM" --root "$Vb" valid-branch 2>&1 >/dev/null)"; VB_RC=$?
[ "$VB_RC" -eq 1 ] && ok "(vb) a missing name is refused (exit 1)" || no "(vb) missing name ⇒ rc=$VB_RC ($VB_ERR)"
VB_ERR="$(bash "$MEM" --root "$Vb" valid-branch loomwright-meta --branch-mode loomwright-meta 2>&1 >/dev/null)"; VB_RC=$?
if [ "$VB_RC" -eq 1 ] && hasF 'valid-branch takes only a name' "$VB_ERR"; then ok "(vb) a flag it could only ignore (--branch-mode) is refused (exit 1)"; else no "(vb) valid-branch + --branch-mode ⇒ rc=$VB_RC ($VB_ERR)"; fi
[ "$(vb_snap "$Vb")" = "$vb_before" ] && ok "(vb) no file changed: every fixture file, git status and HEAD byte-identical" || no "(vb) valid-branch changed the fixture"
if [ ! -e "$Vb/.supervisor/config.json" ] && [ -z "$(ls "$Vb"/.gitignore.backup.* 2>/dev/null)" ]; then ok "(vb) no .supervisor/config.json and no .gitignore.backup.* were created"; else no "(vb) valid-branch left a config or a backup"; fi
# Parity with the writer: for the names apply's predicate judges, valid-branch's verdict equals
# whether `apply --branch-mode <name>` records the mode line (a fresh fixture per name).
for nm in loomwright-meta team-meta HEAD @ 'a..b' '@{-1}'; do
  bash "$MEM" valid-branch "$nm" 2>/dev/null; vrc=$?
  Vp="$(newgit)"; printf '.supervisor/\n' > "$Vp/.gitignore"; mem "$Vp" apply --branch-mode "$nm" >/dev/null 2>&1
  if grep -qxF -e "${MLINE}${nm}" "$Vp/.gitignore"; then arc=0; else arc=1; fi
  if [ "$vrc" -eq "$arc" ]; then ok "(vb) parity: valid-branch '$nm' (rc=$vrc) agrees with apply --branch-mode (mode line recorded: rc=$arc)"; else no "(vb) parity broken for '$nm': valid-branch rc=$vrc, apply recorded rc=$arc"; fi
done
# Same predicate, never a copy: exactly one definition, and a mutant whose valid_branch_name
# refuses everything turns valid-branch's accept red (the subcommand really calls it).
vbdefs="$(grep -c '^valid_branch_name() {$' "$MEMB")"
[ "$vbdefs" -eq 1 ] && ok "(vb) setup-memory.sh defines valid_branch_name exactly once" || no "(vb) valid_branch_name is defined $vbdefs times"
VB_D="$(mkfix)"
sed 's/^valid_branch_name() {$/valid_branch_name() { return 1/' "$MEMB" > "$VB_D/mut.sh"
bash "$VB_D/mut.sh" valid-branch loomwright-meta >/dev/null 2>&1; mrc=$?
if cmp -s "$MEMB" "$VB_D/mut.sh"; then no "(vb) mutation self-check: the patch changed nothing — inconclusive"
elif [ "$mrc" -eq 1 ]; then ok "(vb) mutation self-check: a refuse-all valid_branch_name makes valid-branch refuse 'loomwright-meta' (it calls the one predicate)"
else no "(vb) mutation self-check: a refuse-all predicate still accepted (rc=$mrc) — valid-branch does not call valid_branch_name"; fi
rm -rf "$VB_D"

# ============================================================================
echo "== (am) the agent-memory probe path uses the naming of the stores this repo really tracks =="
# setup-memory.sh probes one agent-memory store for committability. A probe in a naming form the
# host never creates (the old `loomwright:supervisor`) still passes the gitignore probe while
# naming a directory that cannot exist. So the probe is pinned to the form of the stores this repo
# tracks: it must start with the longest common prefix of the tracked store names and carry no ':'.
# The prefix is derived from `git ls-files`, never typed here, so a future rename of the real
# stores moves the expectation with it. A built-in mutant (the colon form) proves the check bites.
AM_REL="$(dirname "$(dirname "$P_MEM")")"   # the agent-memory root, taken from the fixture constant
# store_names: the first path segment under $AM_REL of every line that starts with it (indent allowed).
store_names() {
  awk -v r="$AM_REL/" '{ sub(/^[ \t]+/, "") } index($0, r) == 1 { s = substr($0, length(r) + 1); sub(/\/.*/, "", s); if (s != "") print s }' | sort -u
}
AM_STORES="$(git -C "$PLUGIN_REPO" ls-files -- "$AM_REL" 2>/dev/null | store_names)"
am_n=0; am_prefix=""
while IFS= read -r am_s; do
  [ -n "$am_s" ] || continue
  am_n=$((am_n + 1))
  if [ "$am_n" -eq 1 ]; then am_prefix="$am_s"; continue; fi
  while [ -n "$am_prefix" ] && [ "${am_s#"$am_prefix"}" = "$am_s" ]; do am_prefix="${am_prefix%?}"; done
done <<EOF_AM
$AM_STORES
EOF_AM
[ "$am_n" -ge 2 ] \
  || setup_fail "(am) needs >= 2 tracked $AM_REL/<store>/ dirs in $PLUGIN_REPO to derive the naming prefix (found $am_n)"
[ -n "$am_prefix" ] || setup_fail "(am) the tracked store names share no common prefix — cannot derive the naming form"
case "$am_prefix" in *:*) setup_fail "(am) a tracked store name carries ':' ($am_prefix) — the fixture premise is wrong" ;; esac

# am_probe_names <check-output> → the agent-memory store names the intended-paths list probes.
am_probe_names() { store_names <<< "$1"; }
# am_probe_ok <check-output> → 0 when at least one probe is named and every one has the tracked form.
am_probe_ok() {
  local names n k=0
  names="$(am_probe_names "$1")"
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    k=$((k + 1))
    case "$n" in *:*) return 1 ;; esac
    [ "${n#"$am_prefix"}" != "$n" ] || return 1
  done <<EOF_AMP
$names
EOF_AMP
  [ "$k" -ge 1 ]
}

Am="$(newgit)"
seed_stores "$Am"
out_am="$(mem "$Am" check 2>&1)"
am_named="$(am_probe_names "$out_am" | tr '\n' ' ')"
[ -n "$am_named" ] && ok "(am) check lists an agent-memory probe store ($am_named)" \
  || no "(am) check output names no $AM_REL/<store>/ probe path"
if am_probe_ok "$out_am"; then
  ok "(am) the probe store ($am_named) has the tracked form '${am_prefix}<role>' and no ':'"
else
  no "(am) the probe store ($am_named) does not match the tracked store form '${am_prefix}<role>' (or carries ':')"
fi

# Mutation self-check: drop the ':' -> '-' rule (the old colon form) and the same predicate must fail.
AM_D="$(mkfix)"
sed "s/| tr ':' '-')\"; }\$/| cat)\"; }/" "$MEMB" > "$AM_D/mut.sh"
out_am_mut="$(bash "$AM_D/mut.sh" --root "$Am" check 2>&1)"
if cmp -s "$MEMB" "$AM_D/mut.sh"; then no "(am) mutation self-check: the patch changed nothing — inconclusive"
elif am_probe_ok "$out_am_mut"; then no "(am) mutation self-check: a colon-form probe ($(am_probe_names "$out_am_mut" | tr '\n' ' ')) still passed — the check does not bite"
else ok "(am) mutation self-check: the colon-form probe ($(am_probe_names "$out_am_mut" | tr '\n' ' ')) is rejected"; fi
rm -rf "$AM_D"

echo "== (cs) consent: the ONE user-scope write, keyed by repo, written only by grant / decline =="
CS_HOME="$(mkfix)"
CS_REC="$CS_HOME/.claude/loomwright/meta-sync-consent.json"
cs() { env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST HOME="$CS_HOME" bash "${CS_SUT:-$MEM}" --root "$1" consent "${@:2}" 2>/dev/null; }
# tree_sig <dir> — every file under <dir> with its checksum (the containment witness)
tree_sig() { (cd "$1" && find . -type f -print | env LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done); }
CSG="$(newgit "https://github.com/Acme/Widget.git")"
[ "$(cs "$CSG" status)" = "none" ] && ok "(cs) no record -> status prints exactly 'none'" || no "(cs) status without a record did not print 'none'"
[ -z "$(tree_sig "$CS_HOME")" ] && ok "(cs) status wrote nothing under HOME" || no "(cs) status wrote under HOME"
csg_repo0="$(tree_sig "$CSG")"
out_cs="$(cs "$CSG" grant)"
hasF "consent: recorded granted for Acme/Widget" "$out_cs" && ok "(cs) grant reports the record keyed by origin's owner/repo" || no "(cs) grant output: $out_cs"
[ "$(tree_sig "$CS_HOME" | cut -d' ' -f1)" = "./.claude/loomwright/meta-sync-consent.json" ] \
  && ok "(cs) grant wrote EXACTLY one file, the user-scope consent record" || no "(cs) grant wrote: $(tree_sig "$CS_HOME" | cut -d' ' -f1 | tr '\n' ' ')"
[ "$(tree_sig "$CSG")" = "$csg_repo0" ] && ok "(cs) grant wrote nothing under the repo" || no "(cs) grant changed the repo tree"
[ "$(jq -r '.repos["Acme/Widget"].learning_stores' "$CS_REC" 2>/dev/null)" = "granted" ] && ok "(cs) the record holds .repos[\"Acme/Widget\"].learning_stores = granted" || no "(cs) record shape wrong: $(cat "$CS_REC" 2>/dev/null)"
[ "$(cs "$CSG" status)" = "granted" ] && ok "(cs) status reads it back as 'granted'" || no "(cs) status after grant"
cs "$CSG" decline >/dev/null
[ "$(cs "$CSG" status)" = "declined" ] && ok "(cs) decline overwrites the decision -> 'declined'" || no "(cs) status after decline"
CSP="$(newgit "$CS_HOME/elsewhere/origin.git")"
cs "$CSP" grant >/dev/null
{ [ "$(cs "$CSP" status)" = "granted" ] && [ "$(jq -r '.repos["Acme/Widget"].learning_stores' "$CS_REC")" = "declined" ] \
  && [ "$(jq -r --arg k "$CS_HOME/elsewhere/origin.git" '.repos[$k].learning_stores' "$CS_REC")" = "granted" ]; } \
  && ok "(cs) a filesystem-path origin keys by the literal URL; the other repo's entry is preserved" || no "(cs) path-origin keying: $(cat "$CS_REC")"
CSN="$(newgit)"
rec0="$(cksum < "$CS_REC")"
[ "$(cs "$CSN" status)" = "none" ] && ok "(cs) no origin -> status 'none'" || no "(cs) no-origin status"
out_csn="$(cs "$CSN" grant)"
{ hasF "NOT recorded" "$out_csn" && [ "$(cksum < "$CS_REC")" = "$rec0" ]; } && ok "(cs) no origin -> grant writes nothing and says why" || no "(cs) no-origin grant: $out_csn"
out_bad="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST HOME="$CS_HOME" bash "$MEM" --root "$CSG" consent bogus 2>&1)"; rc_bad=$?
{ [ "$rc_bad" -eq 0 ] && hasF "Nothing was written" "$out_bad" && [ "$(cksum < "$CS_REC")" = "$rec0" ]; } && ok "(cs) a bad action is a usage line, exit 0, nothing written" || no "(cs) bad action (rc=$rc_bad): $out_bad"
for sub in check mode allowlist; do
  env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST HOME="$CS_HOME" bash "$MEM" --root "$CSG" "$sub" >/dev/null 2>&1
done
[ "$(cksum < "$CS_REC")" = "$rec0" ] && [ "$(tree_sig "$CS_HOME" | wc -l | tr -d ' ')" = "1" ] && ok "(cs) check / mode / allowlist write nothing under HOME" || no "(cs) a read-only subcommand wrote under HOME"
printf '[1, 2]\n' > "$CS_REC"
out_mal="$(cs "$CSG" grant)"
{ hasF "NOT recorded" "$out_mal" && [ "$(cat "$CS_REC")" = "[1, 2]" ]; } && ok "(cs) a malformed record is never clobbered" || no "(cs) malformed record: $out_mal / $(cat "$CS_REC")"
case "$(cs "$CSG" status)" in "unknown "*) ok "(cs) a malformed record reads 'unknown <reason>' (publishes nothing)" ;; *) no "(cs) malformed status: $(cs "$CSG" status)" ;; esac
CSB="$(newgit "https://github.com/Acme/Widget.git")"; printf '# x\n' > "$CSB/.gitignore"
env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST HOME="$CS_HOME" bash "$MEM" --root "$CSB" apply --branch-mode loomwright-meta >/dev/null 2>&1
out_bm="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST HOME="$CS_HOME" bash "$MEM" --root "$CSB" check 2>&1)"
{ hasF ".supervisor/twin/contracts/" "$out_bm" && hasF "setup-memory.sh consent" "$out_bm" && hasi "only pattern-checks" "$out_bm"; } \
  && ok "(cs) the branch-mode disclosure names the learning stores, the consent record and that the scrub only pattern-checks" || no "(cs) branch-mode disclosure lacks the learning-store paragraph"
# mutation control: a writer aimed at the repo root must fail the containment assertion
CS_MUT="$(mkfix)"
sed 's|file="\$HOME/\$CONSENT_FILE_REL"|file="$repo/$CONSENT_FILE_REL"|' "$MEMB" > "$CS_MUT/setup-memory.sh"
if cmp -s "$MEMB" "$CS_MUT/setup-memory.sh" || ! bash -n "$CS_MUT/setup-memory.sh"; then
  no "(cs) mutation control: the repo-root mutant did not build — inconclusive"
else
  CSM="$(newgit "https://github.com/Acme/Mutant.git")"; csm0="$(tree_sig "$CSM")"; home0="$(tree_sig "$CS_HOME")"
  CS_SUT="$CS_MUT/setup-memory.sh" cs "$CSM" grant >/dev/null
  if [ "$(tree_sig "$CSM")" != "$csm0" ] && [ "$(tree_sig "$CS_HOME")" = "$home0" ]; then
    ok "(cs) mutation control: the repo-root mutant writes under the repo, which the containment assertion rejects"
  else
    no "(cs) mutation control: the mutant did not write under the repo — the containment assertion does not bite"
  fi
fi
