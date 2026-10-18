# =============================================================================
echo "== B. run-file atomic write + append-only Progress + check-off + remaining =="

WD="$(mktemp -d)"; RF="$WD/automate/run-1.md"
bash "$H" runfile-write "$RF" <<'EOF'
# Automate Run: demo
## Status: running
## Source
- demo
## Run Config
- mode: safe | limit: 5
## Queue
- [ ] a.md
- [ ] b.md
- [x] c.md
## Current
- item: a.md | status: running
## Progress
- t0 picked a.md
EOF
# B1. atomic write produced a parseable file with all sections.
if [ -f "$RF" ] && grep -q '^## Queue' "$RF" && grep -q '^## Progress' "$RF"; then
  ok "atomic write: run file present + parseable (Queue/Progress sections)"
else
  no "atomic write produced a bad file"
fi

# B2. remaining counts ONLY "- [ ]" lines (2 unchecked; c.md checked is excluded).
run_h bash "$H" remaining "$RF"
if [ "$RUN_OUT" = "2" ]; then ok "remaining: counts only unchecked (2)"; else no "remaining wrong ($RUN_OUT, want 2)"; fi

# B3. append-only Progress never loses prior lines. The 2nd line carries a literal
#     backslash sequence (\t/\n) to ALSO guard the ENVIRON[...]-not-awk-v fix in
#     progress_append — backslashes must be stored VERBATIM, never interpreted.
bash "$H" progress-append "$RF" "t1 ran /autonomous"
bash "$H" progress-append "$RF" 't2 drain READY path\twith\nbackslashes'
if grep -q '^- t0 picked a.md' "$RF" \
   && grep -q '^- t1 ran /autonomous' "$RF" \
   && grep -qF -- '- t2 drain READY path\twith\nbackslashes' "$RF" \
   && [ "$(grep -c '^- t0 picked a.md' "$RF")" -eq 1 ]; then
  ok "append-only Progress: prior line intact, new lines appended in order (backslashes verbatim)"
else
  no "progress-append lost/duplicated lines or mangled backslashes:\n$(grep -n '^- t' "$RF")"
fi
# the new lines must be UNDER ## Progress, not elsewhere
if awk '/^## Progress/{p=1} p&&/^- t2 drain READY/{found=1} END{exit !found}' "$RF"; then
  ok "appended line lives under ## Progress"
else
  no "appended line not under ## Progress"
fi

# B4. check-off flips - [ ] -> - [x]; remaining drops.
bash "$H" queue-checkoff "$RF" "a.md"
run_h bash "$H" remaining "$RF"
if grep -q '^- \[x\] a.md$' "$RF" && [ "$RUN_OUT" = "1" ]; then
  ok "check-off: a.md flipped to [x], remaining now 1"
else
  no "check-off wrong (remaining=$RUN_OUT, line=$(grep 'a.md' "$RF"))"
fi

# B5. skipped form: check-off with a reason; remaining drops; never re-counted.
#     Reason carries a literal backslash sequence (why\tbecause) to ALSO guard the
#     ENVIRON[...]-not-awk-v fix in queue_checkoff: \t must be stored verbatim,
#     never interpreted as a tab.
bash "$H" queue-checkoff "$RF" "b.md" 'blocked upstream why\tbecause'
run_h bash "$H" remaining "$RF"
if grep -qF -- '- [x] b.md  # skipped: blocked upstream why\tbecause' "$RF" && [ "$RUN_OUT" = "0" ]; then
  ok "skipped form: b.md checked off with reason (backslash verbatim), remaining now 0 (skipped excluded)"
else
  no "skipped-form wrong (remaining=$RUN_OUT, line=$(grep 'b.md' "$RF"))"
fi

# B6. idempotency: check-off an ALREADY-[x] item leaves it untouched (no dup line).
before_c="$(grep -c '^- \[x\] c.md$' "$RF")"
bash "$H" queue-checkoff "$RF" "c.md"
after_c="$(grep -c '^- \[x\] c.md$' "$RF")"
if [ "$before_c" = "1" ] && [ "$after_c" = "1" ]; then
  ok "check-off idempotent: already-[x] c.md untouched (no duplicate)"
else
  no "idempotency wrong (before=$before_c after=$after_c)"
fi

# B7. abandoned mark: check-off with mark=abandoned writes the "# abandoned:" form (§5).
RF2="$WD/automate/run-2.md"
bash "$H" runfile-write "$RF2" <<'EOF'
# Automate Run: demo2
## Status: running
## Queue
- [ ] x.md
## Progress
- t0
EOF
bash "$H" queue-checkoff "$RF2" "x.md" "no longer needed" "abandoned"
if grep -qF -- '- [x] x.md  # abandoned: no longer needed' "$RF2"; then
  ok "abandoned mark: x.md checked off with '# abandoned:' form (§5)"
else
  no "abandoned-mark wrong (line=$(grep 'x.md' "$RF2"))"
fi

# B8. progress-append CREATES a "## Progress" section when the file lacks one (no drop).
RF3="$WD/automate/run-3.md"
bash "$H" runfile-write "$RF3" <<'EOF'
# Automate Run: demo3
## Status: running
## Queue
- [ ] y.md
EOF
bash "$H" progress-append "$RF3" "t0 created section"
if grep -q '^## Progress' "$RF3" && grep -qF -- '- t0 created section' "$RF3"; then
  ok "progress-append: creates ## Progress section when absent (no event dropped)"
else
  no "progress-create-section wrong:\n$(cat "$RF3")"
fi
rm -rf "$WD"

# =============================================================================
echo "== B9. fail-CLOSED run-file writes (SKILL §3 \"Validate before rename\") =="
# 2026-10-01 incident (loomwright-studio automate-2026-09-30-211858): BSD awk
# rejected a newline inside an `awk -v cur=…` value, exited non-zero and printed
# nothing; `runfile-write` accepted the empty stdin and renamed a 0-byte file over
# the ONLY copy of resume state, then three `progress-append`s fabricated a
# titleless `## Progress` stub on it (remaining → 0, resume-glob stops listing it).
# Every case asserts the run file is BYTE-UNCHANGED and no temp file is left.
# b9_scenarios <helper> <tag> — runs each corrupting input against <helper> and
# prints one "<case>=kept|CORRUPTED" token per case (used for the real helper AND
# for the mutation control below, which must print CORRUPTED).
B9_RF_BODY='# Automate Run: b9
## Status: running
## Source
- demo
## Run Config
- mode: safe | limit: 5
## Queue
- [ ] a.md
- [ ] b.md
## Current
- item: a.md | status: running
- pending_decisions: 0 | fix_now_reentered: false
## Progress
- t0 picked a.md
- t1 ran /autonomous'
b9_seed() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$B9_RF_BODY" > "$1"; cp "$1" "$1.orig-copy"; mv "$1.orig-copy" "$2"; }
b9_verdict() {  # <rf> <orig> <dir> → kept|CORRUPTED (also CORRUPTED when a temp is left)
  local extra; extra="$(ls -A "$3" | grep -vxF "$(basename "$1")" || true)"
  if cmp -s "$1" "$2" && [ -z "$extra" ]; then echo kept; else echo CORRUPTED; fi
}
b9_scenarios() {
  local helper="$1" d rf orig out=""
  d="$(mktemp -d)"; rf="$d/automate/run.md"; orig="$d/orig.md"
  # (1) empty stdin
  b9_seed "$rf" "$orig"; : | bash "$helper" runfile-write "$rf" >/dev/null 2>&1
  out="$out empty=$(b9_verdict "$rf" "$orig" "$d/automate")"
  # (2) stdin missing the title line
  b9_seed "$rf" "$orig"; grep -v '^# Automate Run:' "$orig" | bash "$helper" runfile-write "$rf" >/dev/null 2>&1
  out="$out no_title=$(b9_verdict "$rf" "$orig" "$d/automate")"
  # (3) the incident's exact pipe shape, literally: `awk -v cur="<multi-line>" … $RF | runfile-write $RF`.
  #     BSD awk (macOS) dies "newline in string" and prints nothing — the real
  #     reproduction; GNU awk/mawk accept it and `{print}` re-emits the file, an
  #     identity rewrite. Either way the bytes must come out unchanged.
  b9_seed "$rf" "$orig"
  awk -v cur="- item: b.md | status: running
- pause_reason: null" '{ print }' "$rf" 2>/dev/null | bash "$helper" runfile-write "$rf" >/dev/null 2>&1
  out="$out incident_awk=$(b9_verdict "$rf" "$orig" "$d/automate")"
  # (3b) the same pipe shape with a generator that fails on EVERY awk (syntax
  #      error ⇒ non-zero, no output) — the portable form of (3), so CI on GNU
  #      userland exercises the empty-stdin path too.
  b9_seed "$rf" "$orig"; awk '{ print ' "$rf" 2>/dev/null | bash "$helper" runfile-write "$rf" >/dev/null 2>&1
  out="$out failed_awk=$(b9_verdict "$rf" "$orig" "$d/automate")"
  # (4) progress-append + queue-checkoff on a titleless file (the cascade's second
  #     defect): an emptied run file and a sidecar-shaped stub.
  : > "$rf"; cp "$rf" "$orig"
  bash "$helper" progress-append "$rf" "t2 a" >/dev/null 2>&1
  bash "$helper" progress-append "$rf" "t3 b" >/dev/null 2>&1
  bash "$helper" progress-append "$rf" "t4 c" >/dev/null 2>&1
  out="$out append_on_empty=$(b9_verdict "$rf" "$orig" "$d/automate")"
  printf '## Progress\n- t0 stub\n' > "$rf"; cp "$rf" "$orig"
  bash "$helper" progress-append "$rf" "t2 a" >/dev/null 2>&1
  out="$out append_titleless=$(b9_verdict "$rf" "$orig" "$d/automate")"
  printf '## Queue\n- [ ] a.md\n' > "$rf"; cp "$rf" "$orig"
  bash "$helper" queue-checkoff "$rf" "a.md" >/dev/null 2>&1
  out="$out checkoff_titleless=$(b9_verdict "$rf" "$orig" "$d/automate")"
  # (5) missing ## Status: / missing ## Queue (both mandated by the §3 template)
  b9_seed "$rf" "$orig"; grep -v '^## Status:' "$orig" | bash "$helper" runfile-write "$rf" >/dev/null 2>&1
  out="$out no_status=$(b9_verdict "$rf" "$orig" "$d/automate")"
  b9_seed "$rf" "$orig"; grep -v '^## Queue' "$orig" | bash "$helper" runfile-write "$rf" >/dev/null 2>&1
  out="$out no_queue=$(b9_verdict "$rf" "$orig" "$d/automate")"
  # (6) a generator that died part-way: header sections intact, Progress tail lost
  b9_seed "$rf" "$orig"; sed '$d' "$orig" | bash "$helper" runfile-write "$rf" >/dev/null 2>&1
  out="$out truncated_progress=$(b9_verdict "$rf" "$orig" "$d/automate")"
  rm -rf "$d"
  printf '%s' "${out# }"
}
B9_WANT="empty=kept no_title=kept incident_awk=kept failed_awk=kept append_on_empty=kept append_titleless=kept checkoff_titleless=kept no_status=kept no_queue=kept truncated_progress=kept"
B9_OUT="$(b9_scenarios "$H")"
if [ "$B9_OUT" = "$B9_WANT" ]; then
  ok "B9 fail-closed: every corrupting payload refused, run file byte-unchanged, no temp left ($B9_OUT)"
else
  no "B9 fail-closed: some payload got through:\n  got:  $B9_OUT\n  want: $B9_WANT"
fi

# B9 refusal surface: exit 1 + the [runfile_write_refused] tag on stderr.
WD="$(mktemp -d)"; RF="$WD/automate/run.md"; b9_seed "$RF" "$WD/orig.md"
B9_ERR="$( : | bash "$H" runfile-write "$RF" 2>&1 >/dev/null)"; B9_RC=$?
if [ "$B9_RC" -eq 1 ] && grep -qF 'runfile_write_refused' <<<"$B9_ERR" && grep -qF 'empty content' <<<"$B9_ERR"; then
  ok "B9 refusal: exit 1 with a named reason + [runfile_write_refused] tag"
else
  no "B9 refusal surface wrong (rc=$B9_RC err='$B9_ERR')"
fi

# B9 positive controls — the guard must not block legitimate writes:
#   (a) a ## Current rewrite that SHRINKS the file (pending_decisions dropped) and
#       appends a Progress line; (b) first creation; (c) a human recovery write
#       over an emptied (non-run) file; (d) progress-append/queue-checkoff on a
#       valid run file still work through the validated rename.
sed -e '/^- pending_decisions:/d' -e 's/^- item: a.md | status: running$/- item: b.md | status: running/' "$WD/orig.md" > "$WD/new.md"
printf -- '- t2 picked b.md\n' >> "$WD/new.md"
bash "$H" runfile-write "$RF" < "$WD/new.md" 2>/dev/null; B9_A=$?
RF_NEW="$WD/automate/fresh.md"; printf '%s\n' "$B9_RF_BODY" | bash "$H" runfile-write "$RF_NEW" 2>/dev/null; B9_B=$?
RF_EMPTY="$WD/automate/emptied.md"; : > "$RF_EMPTY"
bash "$H" runfile-write "$RF_EMPTY" < "$WD/orig.md" 2>/dev/null; B9_C=$?
bash "$H" progress-append "$RF" "t3 ok" 2>/dev/null && bash "$H" queue-checkoff "$RF" "a.md" 2>/dev/null; B9_D=$?
if [ "$B9_A" -eq 0 ] && grep -qxF -- '- item: b.md | status: running' "$RF" && ! grep -q '^- pending_decisions:' "$RF" \
   && [ "$B9_B" -eq 0 ] && cmp -s "$RF_NEW" "$WD/orig.md" \
   && [ "$B9_C" -eq 0 ] && cmp -s "$RF_EMPTY" "$WD/orig.md" \
   && [ "$B9_D" -eq 0 ] && grep -qxF -- '- [x] a.md' "$RF" && [ "$(tail -n1 "$RF")" = "- t3 ok" ] \
   && [ "$(ls -A "$WD/automate" | wc -l | tr -d ' ')" = "3" ]; then
  ok "B9 positive controls: shrinking ## Current rewrite, first creation, recovery over an emptied file, and append/check-off on a valid run file all succeed"
else
  no "B9 positive controls blocked a legitimate write (a=$B9_A b=$B9_B c=$B9_C d=$B9_D):\n$(cat "$RF")\n$(ls -A "$WD/automate")"
fi
rm -rf "$WD"

# B9 mutation control: a COPY of the helper with the validation removed (the
# pre-rename refusal forced empty, both is_run_file pre-checks deleted) must let
# the SAME scenarios corrupt the file — proves the cases above are not vacuous.
MUTDIR="$(mktemp -d)"
sed -e 's/^  why="\$(_runfile_refusal .*$/  why=""/' \
    -e '/^  is_run_file "\$out" || die "progress-append: refused/d' \
    -e '/^  is_run_file "\$out" || die "queue-checkoff: refused/d' \
    "$H" > "$MUTDIR/automate-helpers.sh"
if [ -s "$MUTDIR/automate-helpers.sh" ] && ! cmp -s "$H" "$MUTDIR/automate-helpers.sh" && bash -n "$MUTDIR/automate-helpers.sh" 2>/dev/null \
   && grep -qxF '  why=""' "$MUTDIR/automate-helpers.sh" \
   && ! grep -q 'refused — \$out has no' "$MUTDIR/automate-helpers.sh"; then
  B9_MUT="$(b9_scenarios "$MUTDIR/automate-helpers.sh")"
  # incident_awk stays "kept" on GNU awk (identity rewrite) — every OTHER case must turn red.
  B9_MUT_RED=1
  for c in empty no_title failed_awk append_on_empty append_titleless checkoff_titleless no_status no_queue truncated_progress; do
    case " $B9_MUT " in *" $c=CORRUPTED "*) ;; *) B9_MUT_RED=0 ;; esac
  done
  if [ "$B9_MUT_RED" -eq 1 ]; then
    ok "B9 mutation control: validation removed ⇒ every corrupting case turns red ($B9_MUT)"
  else
    no "B9 mutation control did NOT discriminate — a case passes without the guard: $B9_MUT"
  fi
else
  no "B9 mutation control: could not build the mutant (sed did not apply or bash -n failed) -- control inconclusive"
fi
rm -rf "$MUTDIR"

# =============================================================================
echo "== B10. ## Current moves only through a helper (current-set / progress-append current_not_set guard / current-rebuild) =="
# automate-followups/32 Part C: lane w1-10 (run automate-2026-10-04-103627) wrote
# ## Current once at creation and never again — every later event was a
# progress-append — so a RESUME mid-drain would have read "nothing in flight".
CWD="$(mktemp -d)"
# cs_fixture <path> <first ## Current line> [<pause_reason line | "-" for none>]
cs_fixture() {
  local p="$1" il="$2" pl="${3:-- pause_reason: awaiting_go}"
  {
    printf '# Automate Run: cs\n## Status: running\n## Source\n- folder f\n## Run Config\n- mode: safe | limit: 5\n## Queue\n- [ ] a.md\n- [ ] b.md\n## Current\n'
    printf '%s\n' "$il"
    if [ "$pl" != "-" ]; then printf '%s\n' "$pl"; fi
    printf '%s\n' '- owned_drain_started: t9 | owned_drain_result: READY | suppressed_default_dispatch: true'
    printf '%s\n' '- pending_decisions: 2 | fix_now_reentered: false'
    printf '## Progress\n- t0 run created\n'
  } > "$p"
}
CRF="$CWD/r.md"
NULL_ITEM="- item: null | status: null | pr: null | branch: null"

# B10a. byte-diff: only the item + pause_reason lines change; owned_drain_*/pending_decisions untouched.
cs_fixture "$CRF" "$NULL_ITEM"; cp "$CRF" "$CWD/before"
run_h bash "$H" current-set "$CRF" --item a.md --status running --pr null --branch null --pause-reason null
if [ "$RUN_RC" -eq 0 ] && grep -qxF -- '- item: a.md | status: running | pr: null | branch: null' "$CRF" \
   && grep -qxF -- '- pause_reason: null' "$CRF" \
   && [ "$(diff "$CWD/before" "$CRF" | grep -c '^[<>]')" = 4 ] \
   && cmp -s <(grep -vE '^- (item|pause_reason):' "$CWD/before") <(grep -vE '^- (item|pause_reason):' "$CRF"); then
  ok "current-set: only the ## Current item + pause_reason lines change (owned_drain_*/pending_decisions and every other line byte-unchanged)"
else
  no "current-set byte-diff wrong (rc=$RUN_RC): $(diff "$CWD/before" "$CRF" | tr '\n' '|')"
fi
# B10b. idempotent: re-setting the identical values rewrites nothing.
cp "$CRF" "$CWD/set1"
run_h bash "$H" current-set "$CRF" --item a.md --status running --pr null --branch null --pause-reason null
if [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-set: unchanged" ] && cmp -s "$CWD/set1" "$CRF"; then
  ok "current-set: identical values ⇒ 'current-set: unchanged', file byte-identical"
else
  no "current-set re-set not idempotent (rc=$RUN_RC out=$RUN_OUT)"
fi
# B10c. refusals: exit 1, file byte-unchanged.
cs_fixture "$CWD/base" "- item: a.md | status: running | pr: https://github.com/acme/widgets/pull/1 | branch: f/a"
cs_refuse() {
  local label="$1"; shift
  cp "$CWD/base" "$CRF"
  bash "$H" current-set "$CRF" "$@" >/dev/null 2>&1; local rc=$?
  if [ "$rc" -eq 1 ] && cmp -s "$CWD/base" "$CRF"; then ok "current-set refuses $label (exit 1, byte-unchanged)"; else no "current-set $label: rc=$rc or the file changed"; fi
}
cs_refuse "an unknown status" --item a.md --status parked
cs_refuse "an unknown pause_reason (run-level form)" --pause-reason bogus
cs_refuse "an unknown pause_reason (item form)" --item a.md --status running --pause-reason parked
cs_refuse "a half-null item form (item null, status set)" --item null --status running
cs_refuse "a half-null item form (item set, status null)" --item a.md --status null
cs_refuse "an item form missing --status" --item a.md
cs_refuse "an item form missing --item" --status running
cs_refuse "a run-level form missing --pause-reason" --pr https://github.com/acme/widgets/pull/2
cs_refuse "no arguments at all"
cs_refuse "a '|'-bearing item" --item 'a.md | status: done' --status running
cs_refuse "a '|'-bearing pr" --item a.md --status running --pr 'x|y'
cs_refuse "a newline-bearing item" --item "$(printf 'a.md\nb.md')" --status running
cs_refuse "an empty value" --item a.md --status running --branch ''
cs_refuse "an unknown flag" --item a.md --status running --owner me
printf '## Status: running\n## Queue\n## Current\n- item: null | status: null\n## Progress\n' > "$CWD/norun.md"; cp "$CWD/norun.md" "$CWD/norun.before"
bash "$H" current-set "$CWD/norun.md" --item a.md --status running >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && cmp -s "$CWD/norun.before" "$CWD/norun.md" && ok "current-set refuses a non-run file (no title; exit 1, byte-unchanged)" || no "current-set on a non-run file: rc=$rc"
printf '# Automate Run: x\n## Status: running\n## Queue\n- [ ] a.md\n## Progress\n- t0\n' > "$CWD/nocur.md"; cp "$CWD/nocur.md" "$CWD/nocur.before"
bash "$H" current-set "$CWD/nocur.md" --pause-reason null >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && cmp -s "$CWD/nocur.before" "$CWD/nocur.md" && ok "current-set refuses a run file with no ## Current heading (exit 1, byte-unchanged)" || no "current-set on a Current-less file: rc=$rc"
# B10d. pr/branch retention: same item keeps them; a CHANGED item resets omitted ones to null.
cs_retention() {  # cs_retention <helper> — prints the two item lines it produced, '|'-joined
  local h="$1"
  cs_fixture "$CRF" "$NULL_ITEM"
  bash "$h" current-set "$CRF" --item a.md --status running --pr https://github.com/acme/widgets/pull/1 --branch f/a >/dev/null 2>&1
  bash "$h" current-set "$CRF" --item a.md --status awaiting_merge >/dev/null 2>&1
  printf '%s' "$(grep '^- item: ' "$CRF")"
  bash "$h" current-set "$CRF" --item b.md --status running >/dev/null 2>&1
  printf ' || %s' "$(grep '^- item: ' "$CRF")"
}
CS_WANT='- item: a.md | status: awaiting_merge | pr: https://github.com/acme/widgets/pull/1 | branch: f/a || - item: b.md | status: running | pr: null | branch: null'
cs_got="$(cs_retention "$H")"
[ "$cs_got" = "$CS_WANT" ] && ok "current-set: same --item keeps pr/branch; a changed --item resets omitted pr/branch to null" || no "current-set retention wrong: $cs_got"
# mutation control: without the reset, the previous item's PR rides into the new item.
CSM="$CWD/mut"; mkdir -p "$CSM"
sed '/^      if \[ "\$hp" = 0 \]; then pr=null; hp=1; fi$/d' "$H" > "$CSM/automate-helpers.sh"
if ! cmp -s "$H" "$CSM/automate-helpers.sh" && bash -n "$CSM/automate-helpers.sh" 2>/dev/null; then
  case "$(cs_retention "$CSM/automate-helpers.sh")" in
    *"- item: b.md | status: running | pr: https://github.com/acme/widgets/pull/1 |"*) ok "mutation control: without the item-change reset the old PR rides into b.md (the retention leg is load-bearing)" ;;
    *) no "pr-reset mutant did not carry the PR — the retention leg may be vacuous" ;;
  esac
else
  no "pr-reset mutant not built"
fi
# B10e. run-level form: --pause-reason closeout_leftover leaves the item line byte-unchanged.
cp "$CWD/base" "$CRF"
run_h bash "$H" current-set "$CRF" --pause-reason closeout_leftover
if [ "$RUN_RC" -eq 0 ] && grep -qxF -- '- pause_reason: closeout_leftover' "$CRF" \
   && cmp -s <(grep -v '^- pause_reason:' "$CWD/base") <(grep -v '^- pause_reason:' "$CRF"); then
  ok "current-set run-level form (--pause-reason closeout_leftover): item line and every other line byte-unchanged"
else
  no "run-level form wrong (rc=$RUN_RC): $(diff "$CWD/base" "$CRF" | tr '\n' '|')"
fi
# B10f. a block with no pause_reason line gets one appended INSIDE ## Current; a block
#       with no item line gets one right under the heading.
cs_fixture "$CRF" "- reason_hint: rate_limit" "-"
bash "$H" current-set "$CRF" --item a.md --status running --pause-reason awaiting_merge >/dev/null 2>&1
cs_blk="$(awk '/^## Current/{c=1;next} /^## /{c=0} c' "$CRF" | tr '\n' '|')"
[ "$cs_blk" = "- item: a.md | status: running | pr: null | branch: null|- reason_hint: rate_limit|- owned_drain_started: t9 | owned_drain_result: READY | suppressed_default_dispatch: true|- pending_decisions: 2 | fix_now_reentered: false|- pause_reason: awaiting_merge|" ] \
  && ok "current-set: absent item line inserted under the heading, absent pause_reason appended inside the block" || no "current-set insertion wrong: $cs_blk"

# B10g. progress-append current_not_set guard (exit 3, line still appended).
PRF="$CWD/g.md"
pg_case() {  # pg_case <label> <## Current item line> <line> <want rc>
  cs_fixture "$PRF" "$2"
  local err rc; err="$(bash "$H" progress-append "$PRF" "$3" 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -ne "$4" ]; then no "guard $1: rc=$rc want $4 (stderr: $err)"; return; fi
  if ! grep -qxF -- "- $3" "$PRF"; then no "guard $1: line not appended"; return; fi
  if [ "$4" -eq 3 ] && [ "$err" != "current_not_set: $3" ]; then no "guard $1: stderr '$err'"; return; fi
  ok "guard $1 ⇒ exit $4, line appended"
}
SET_A="- item: a.md | status: running | pr: null | branch: null"
pg_case "null item + '<ts> picked a.md'" "$NULL_ITEM" "t1 picked a.md" 3
pg_case "null item + 'picked a.md' (no ts)" "$NULL_ITEM" "picked a.md" 3
pg_case "null item + 'ran /autonomous → PR <url>'" "$NULL_ITEM" "t1 ran /autonomous → PR $PR" 3
pg_case "null item + 'owned drain started: …'" "$NULL_ITEM" "t1 owned drain started: /review-pr $PR --until-mergeable" 3
pg_case "absent item line + picked" "- reason_hint: x" "t1 picked a.md" 3
pg_case "empty item value + picked" "- item:  | status: running" "t1 picked a.md" 3
pg_case "null item + '<ts> parked …' (not guarded)" "$NULL_ITEM" "t1 parked limit_reached — remaining 2" 0
pg_case "null item + a run-level run_lock_held park line" "$NULL_ITEM" "t1 run_lock_held owner=automate:x pid=1 age=3 — paused" 0
pg_case "null item + a closeout step line" "$NULL_ITEM" "t1 closeout $PR: closeout: checked — - [x] a.md" 0
pg_case "Current set + picked a.md" "$SET_A" "t1 picked a.md" 0
pg_case "Current set + ran /autonomous" "$SET_A" "t1 ran /autonomous → PR $PR" 0
pg_case "Current set + owned drain started" "$SET_A" "t1 owned drain started: x" 0
pg_case "picked b.md while ## Current names non-done a.md" "$SET_A" "t5 picked b.md" 3
pg_case "picked b.md, (comma suffix) while a.md running" "$SET_A" "t5 picked b.md, owner go" 3
pg_case "picked b.md while a.md is done" "- item: a.md | status: done | pr: $PR | branch: f/a" "t5 picked b.md" 0
pg_case "'picked a.md (run-lock acquired; …)' with Current a.md" "$SET_A" "t5 picked a.md (run-lock acquired; session x)" 0
pg_case "'picked a.md (run-lock acquired; …)' with Current ./a.md" "- item: ./a.md | status: running | pr: null | branch: null" "t5 picked a.md (run-lock acquired; session x)" 0
pg_case "'picked ./a.md; suppressed …' with Current a.md" "$SET_A" "t5 picked ./a.md; suppressed auto_review" 0
# mutation control: the guard call deleted ⇒ the null-item picked case exits 0.
PGM="$CWD/pgm"; mkdir -p "$PGM"
sed '/^  _progress_current_guard "\$out" "\$line"$/d' "$H" > "$PGM/automate-helpers.sh"
if ! cmp -s "$H" "$PGM/automate-helpers.sh" && bash -n "$PGM/automate-helpers.sh" 2>/dev/null; then
  cs_fixture "$PRF" "$NULL_ITEM"
  bash "$PGM/automate-helpers.sh" progress-append "$PRF" "t1 picked a.md" >/dev/null 2>&1 \
    && ok "mutation control: without the guard a null-Current picked line exits 0 (the exit-3 legs are load-bearing)" || no "guard mutant still refused"
else
  no "guard mutant not built"
fi
# B10h. w1-10 replay (automate-2026-10-04-103627): the creation write, then its
#       Progress-only history — the guard refuses at the FIRST picked line.
W10="$CWD/w10.md"
W10_ITEM=".supervisor/requirements/parallel-automate/10-touches-backfill-lint-and-explain.md"
W10_PR="https://github.com/vikashruhilgit/loomwright/pull/377"
bash "$H" runfile-write "$W10" <<EOF
# Automate Run: S1 v2 lane w1-10 — item 10
## Status: running
## Source
- backlog .supervisor/s1-backlog.md
## Run Config
- mode: safe | limit: 5 | trust_unprotected: false
- auto_review_original: absent | config_backup: automate-2026-10-04-103627.config-backup.json
## Queue
- [ ] $W10_ITEM
## Current
- item: null | status: null | pr: null | branch: null
- pause_reason: null
## Progress
- 2026-10-04T10:36:27Z run created; queue confirmed by owner (1 item, start new — other incomplete runs left untouched)
EOF
w10_first=""; w10_n=0
while IFS= read -r l; do
  w10_n=$((w10_n+1))
  bash "$H" progress-append "$W10" "$l" >/dev/null 2>&1; rc=$?
  if [ "$rc" -ne 0 ] && [ -z "$w10_first" ]; then w10_first="$w10_n:$rc:$l"; fi
done <<EOF
trail-gate: clear — no open trail PR; sync skipped — already synced (main at origin/main)
trail-unstage: skipped — branch mode
2026-10-04T10:39:26Z picked $W10_ITEM
reconcile-status: would stamp .supervisor/requirements/token-economy/07-verify-spec-replay.md (done (PR #269, merge e319536))
2026-10-04T11:44:52Z session_id fa3574db (.supervisor/requirements/parallel-automate/10-touches-backfill-lint-and-explain.md)
2026-10-04T11:44:52Z ran /autonomous → PR $W10_PR (heal PASS after 1 fix iteration)
2026-10-04T11:45:12Z owned drain started: /review-pr $W10_PR --until-mergeable --no-auto-postmortem (suppressed_default_dispatch: true)
2026-10-04T14:19:45Z gate (safe mode): parked awaiting_merge — PR $W10_PR READY, left open for a human merge
2026-10-04T14:27:00Z closeout $W10_PR: closeout: synced — main at 2bdb2b7
EOF
[ "$w10_first" = "3:3:2026-10-04T10:39:26Z picked $W10_ITEM" ] \
  && ok "w1-10 replay: the guard refuses (exit 3) at the first picked line, every earlier line exits 0" || no "w1-10 replay first refusal wrong: $w10_first"
grep -qxF -- "- 2026-10-04T14:27:00Z closeout $W10_PR: closeout: synced — main at 2bdb2b7" "$W10" \
  && ok "w1-10 replay: every line is still appended (loud, not lossy)" || no "w1-10 replay lost a line"

# B10i. current-rebuild (stubbed gh: OPEN / MERGED / CLOSED / failing).
CBIN="$CWD/bin"; make_stub_bin "$CBIN"; CGH="$CWD/ghstub"; mkdir -p "$CGH"
cr_fixture() {  # cr_fixture <path> <progress line>...
  local p="$1" l; shift
  {
    printf '# Automate Run: cr\n## Status: paused\n## Source\n- folder q\n## Run Config\n- mode: safe | limit: 5\n## Queue\n- [x] q/01-a.md\n- [ ] q/02-b.md\n## Current\n'
    printf '%s\n' "$NULL_ITEM" '- pause_reason: awaiting_merge' '## Progress'
    for l in "$@"; do printf -- '- %s\n' "$l"; done
  } > "$p"
}
cr_run() { RUN_OUT="$(PATH="$CBIN:$PATH" GH_STUB_DIR="$CGH" bash "${CR_H:-$H}" current-rebuild "$1" 2>/dev/null)"; RUN_RC=$?; }
CRB="$CWD/cr.md"; B_PR="https://github.com/acme/widgets/pull/9"
for st in OPEN MERGED CLOSED fail; do
  rm -f "$CGH/pr-view-fail"
  case "$st" in
    fail) : > "$CGH/pr-view-fail"; want_state=unknown; want_br=null ;;
    MERGED) printf '{"state":"MERGED","mergedAt":"2026-10-05T00:00:00Z","headRefName":"feature/b"}\n' > "$CGH/pr-view.json"; want_state=MERGED; want_br=feature/b ;;
    *) printf '{"state":"%s","mergedAt":null,"headRefName":"feature/b"}\n' "$st" > "$CGH/pr-view.json"; want_state="$st"; want_br=feature/b ;;
  esac
  cr_fixture "$CRB" "t0 picked q/01-a.md" "t0 ran /autonomous → PR https://github.com/acme/widgets/pull/3" \
    "t1 picked q/02-b.md; suppressed auto_review (backup cr.config-backup.json)" "t2 ran /autonomous → PR $B_PR (heal PASS)"
  cr_run "$CRB"
  want_line="current_rebuilt: q/02-b.md pr $B_PR state $want_state"
  if [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "$want_line" ] \
     && grep -qxF -- "- item: q/02-b.md | status: running | pr: $B_PR | branch: $want_br" "$CRB" \
     && [ "$(tail -n1 "$CRB")" = "- $want_line" ]; then
    ok "current-rebuild ($st): ## Current rebuilt status running + pr + branch $want_br, '$want_line' printed and appended"
  else
    no "current-rebuild ($st) wrong (rc=$RUN_RC out=$RUN_OUT): $(grep '^- item:' "$CRB")"
  fi
done
rm -f "$CGH/pr-view-fail"
cp "$CRB" "$CWD/cr.set"; cr_run "$CRB"
[ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-rebuild: skipped — ## Current set" ] && cmp -s "$CWD/cr.set" "$CRB" \
  && ok "current-rebuild second run: 'skipped — ## Current set', nothing written" || no "current-rebuild second run wrong (rc=$RUN_RC out=$RUN_OUT)"
# B10i2. automate-followups/36 A3: current-rebuild writes pause_reason null beside status running —
# a stale pause-only reason (awaiting_go here) never survives the rebuild.
cr_pause() { # [<helper>] — rebuild a Current whose pause_reason is a stale awaiting_go
  cr_fixture "$CRB" "t1 picked q/02-b.md" "t2 ran /autonomous → PR $B_PR"
  sed 's/^- pause_reason: awaiting_merge$/- pause_reason: awaiting_go/' "$CRB" > "$CRB.t" && mv "$CRB.t" "$CRB"
  printf '{"state":"OPEN","mergedAt":null,"headRefName":"feature/b"}\n' > "$CGH/pr-view.json"
  CR_H="${1:-}" cr_run "$CRB"
}
cr_pause
if [ "$RUN_RC" -eq 0 ] && grep -qxF -- "- item: q/02-b.md | status: running | pr: $B_PR | branch: feature/b" "$CRB" \
   && grep -qxF -- '- pause_reason: null' "$CRB" && ! grep -q '^- pause_reason: awaiting_go' "$CRB"; then
  ok "(B10i2) current-rebuild: status running + pause_reason null (the stale awaiting_go is gone)"
else
  no "(B10i2) rebuild left: $(grep -E '^- (item|pause_reason):' "$CRB" | tr '\n' '|') (rc=$RUN_RC out=$RUN_OUT)"
fi
CRPM="$CWD/crpm"; mkdir -p "$CRPM"
sed 's/ --branch "\$branch" --pause-reason null >\/dev\/null$/ --branch "$branch" >\/dev\/null  # mutant A3/' "$H" > "$CRPM/automate-helpers.sh"
if grep -q '# mutant A3' "$CRPM/automate-helpers.sh" && bash -n "$CRPM/automate-helpers.sh"; then
  cr_pause "$CRPM/automate-helpers.sh"
  grep -qxF -- '- pause_reason: awaiting_go' "$CRB" && grep -q '^- item: q/02-b.md | status: running' "$CRB" \
    && ok "(B10i2) mutation control: without --pause-reason null the rebuild leaves 'status: running' beside 'pause_reason: awaiting_go'" \
    || no "(B10i2) mutation control did not discriminate: $(grep -E '^- (item|pause_reason):' "$CRB" | tr '\n' '|')"
else
  no "(B10i2) mutant A3 not built"
fi
# B10j. A `done` ## Current left behind by a PICK that skipped its current-set after a
# close-out (the guard exempts a done Current, so both lines append with exit 0) is
# stale: current-rebuild repairs it from the LAST picked line. Before the fix it
# printed 'skipped — ## Current set' and Current kept naming a.md while b's PR was open.
A_PR="https://github.com/acme/widgets/pull/3"; B2_PR="https://github.com/acme/widgets/pull/2"
crd_fixture() {  # crd_fixture <path> <progress line>...
  local p="$1" l; shift
  {
    printf '# Automate Run: crd\n## Status: running\n## Source\n- folder q\n## Run Config\n- mode: safe | limit: 5\n## Queue\n- [x] q/01-a.md\n- [ ] q/02-b.md\n## Current\n'
    printf '%s\n' "- item: q/01-a.md | status: done | pr: $A_PR | branch: feature/a" '- pause_reason: null' '## Progress'
    for l in "$@"; do printf -- '- %s\n' "$l"; done
  } > "$p"
}
crd_stale() {  # the reviewer's repro: a done a.md, then 'picked b' + 'ran → PR 2' with no current-set
  crd_fixture "$CRB" "t0 picked q/01-a.md" "t0 ran /autonomous → PR $A_PR" "t1 closeout $A_PR: closeout: checked — - [x] q/01-a.md"
  local r1 r2
  bash "$H" progress-append "$CRB" "t2 picked q/02-b.md; suppressed auto_review" 2>/dev/null; r1=$?
  bash "$H" progress-append "$CRB" "t3 ran /autonomous → PR $B2_PR" 2>/dev/null; r2=$?
  CRD_APPEND_RC="$r1/$r2"
  cr_run "$CRB"
}
printf '{"state":"OPEN","mergedAt":null,"headRefName":"feature/b"}\n' > "$CGH/pr-view.json"
crd_stale
[ "$CRD_APPEND_RC" = "0/0" ] && ok "(B10j) the guard lets 'picked b' + 'ran /autonomous' over a done a.md through (exit 0/0 — the documented exemption)" || no "(B10j) append rcs: $CRD_APPEND_RC"
[ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current_rebuilt: q/02-b.md pr $B2_PR state OPEN" ] \
  && grep -qxF -- "- item: q/02-b.md | status: running | pr: $B2_PR | branch: feature/b" "$CRB" \
  && ok "(B10j) current-rebuild repairs a stale done ## Current to the last picked item (b, its PR, running)" \
  || no "(B10j) stale done Current not rebuilt (rc=$RUN_RC out=$RUN_OUT): $(grep '^- item:' "$CRB")"
# Mutation control (the before-state): a done Current treated as 'set' ⇒ the repro is skipped.
CRDM="$CWD/crdm"; mkdir -p "$CRDM"
sed 's|^    \[ "\$cs" = done \] \|\| { echo "\$R ## Current set"; return 0; }$|    { echo "$R ## Current set"; return 0; }|' "$H" > "$CRDM/automate-helpers.sh"
if ! cmp -s "$H" "$CRDM/automate-helpers.sh" && bash -n "$CRDM/automate-helpers.sh" 2>/dev/null; then
  CR_H="$CRDM/automate-helpers.sh" crd_stale
  [ "$RUN_OUT" = "current-rebuild: skipped — ## Current set" ] && grep -q '^- item: q/01-a.md | status: done' "$CRB" \
    && ok "(B10j) mutation control: the pre-fix rule skips the repro and leaves a.md named" || no "(B10j) mutant did not reproduce the bug ($RUN_OUT)"
else
  no "(B10j) done-exemption mutant not built"
fi
# Negatives: a done Current that IS the last picked item (a correct close-out), and a
# done Current with a './'-prefixed picked token naming it, are never rebuilt.
crd_fixture "$CRB" "t0 picked q/01-a.md" "t0 ran /autonomous → PR $A_PR" "t1 closeout $A_PR: closeout: checked — - [x] q/01-a.md"
cp "$CRB" "$CWD/crd.same"; cr_run "$CRB"
[ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-rebuild: skipped — ## Current set" ] && cmp -s "$CWD/crd.same" "$CRB" \
  && ok "(B10j) a done Current naming the last picked item ⇒ skipped, nothing written" || no "(B10j) same-item done wrong (rc=$RUN_RC out=$RUN_OUT)"
crd_fixture "$CRB" "t0 picked ./q/01-a.md (run-lock acquired; session x)"
cp "$CRB" "$CWD/crd.dot"; cr_run "$CRB"
[ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-rebuild: skipped — ## Current set" ] && cmp -s "$CWD/crd.dot" "$CRB" \
  && ok "(B10j) a done Current vs './'-prefixed picked token of the same item ⇒ skipped" || no "(B10j) ./ compare wrong (rc=$RUN_RC out=$RUN_OUT)"
crd_fixture "$CRB" "t0 run created"
cp "$CRB" "$CWD/crd.np"; cr_run "$CRB"
[ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-rebuild: skipped — ## Current set" ] && cmp -s "$CWD/crd.np" "$CRB" \
  && ok "(B10j) a done Current with no picked line ⇒ skipped, nothing written" || no "(B10j) no-picked done wrong (rc=$RUN_RC out=$RUN_OUT)"
# Negative: foreign PR URLs on closeout / trail / cross-run lines and no ran
# /autonomous after the last picked ⇒ pr stays null ('(owner …)' suffix parsed).
cr_foreign() {
  cr_fixture "$CRB" "t0 picked q/01-a.md" "t0 ran /autonomous → PR https://github.com/acme/widgets/pull/3" \
    "t1 picked q/02-b.md (owner go)" "t2 closeout https://github.com/acme/widgets/pull/5: closeout: checked — - [x] q/01-a.md" \
    "trail-pr: opened https://github.com/acme/widgets/pull/6 (chore/cr-trail-1)" \
    "t3 cross-run closeout automate-x q/01-a.md https://github.com/acme/widgets/pull/4: complete"
  cr_run "$CRB"
}
cr_foreign
[ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current_rebuilt: q/02-b.md pr null state none" ] \
  && grep -qxF -- "- item: q/02-b.md | status: running | pr: null | branch: null" "$CRB" \
  && ok "current-rebuild: foreign PR URLs (closeout/trail/cross-run lines, an earlier item's ran line) never attach — pr null" || no "current-rebuild attached a foreign PR (out=$RUN_OUT): $(grep '^- item:' "$CRB")"
# mutation control: reading the PR from ANY later Progress line attaches a foreign one.
CRM="$CWD/crm"; mkdir -p "$CRM"
sed 's|^    NR > ENVIRON\["PN"\]+0 && /^- (\[^ \]+ )?ran \\/autonomous/ {$|    NR > ENVIRON["PN"]+0 {|' "$H" > "$CRM/automate-helpers.sh"
if ! cmp -s "$H" "$CRM/automate-helpers.sh" && bash -n "$CRM/automate-helpers.sh" 2>/dev/null; then
  CR_H="$CRM/automate-helpers.sh" cr_foreign
  case "$RUN_OUT" in *"pr null"*) no "foreign-PR mutant still null — the negative leg may be vacuous ($RUN_OUT)" ;; *) ok "mutation control: reading any Progress line attaches a foreign PR ($RUN_OUT)" ;; esac
else
  no "foreign-PR mutant not built"
fi
cr_fixture "$CRB" "t1 picked q/09-z.md" "t2 ran /autonomous → PR $B_PR"; cp "$CRB" "$CWD/cr.nq"; cr_run "$CRB"
[ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-rebuild: skipped — picked item not in Queue" ] && cmp -s "$CWD/cr.nq" "$CRB" \
  && ok "current-rebuild: picked item not in the Queue ⇒ skipped, nothing written" || no "current-rebuild not-in-Queue wrong (rc=$RUN_RC out=$RUN_OUT)"
cr_fixture "$CRB" "t1 run created"; cp "$CRB" "$CWD/cr.np"; cr_run "$CRB"
[ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-rebuild: skipped — no picked line in ## Progress" ] && cmp -s "$CWD/cr.np" "$CRB" \
  && ok "current-rebuild: no picked line ⇒ skipped, nothing written" || no "current-rebuild no-picked wrong (rc=$RUN_RC out=$RUN_OUT)"
# The w1-10 replay above, rebuilt (gh says MERGED): the ran line names PR 377.
printf '{"state":"MERGED","mergedAt":"2026-10-04T14:26:00Z","headRefName":"feature/parallel-automate-10-touches-lint-and-explain"}\n' > "$CGH/pr-view.json"
cr_run "$W10"
[ "$RUN_OUT" = "current_rebuilt: $W10_ITEM pr $W10_PR state MERGED" ] \
  && grep -qxF -- "- item: $W10_ITEM | status: running | pr: $W10_PR | branch: feature/parallel-automate-10-touches-lint-and-explain" "$W10" \
  && ok "current-rebuild on the w1-10 replay: item + PR 377 + branch, status running (never awaiting_merge)" || no "w1-10 rebuild wrong: $RUN_OUT"
rm -rf "$CWD"

