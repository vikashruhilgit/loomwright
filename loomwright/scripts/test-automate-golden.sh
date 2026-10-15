#!/usr/bin/env bash
# test-automate-golden.sh — golden run-file tests for the `/automate` per-item loop
# (automate-speed/05). They pin TODAY's behaviour so items 06–09 (control flow moving
# from prose into a `next-step` script) can prove they produce the same run file.
# UNCOUNTED by the doc-currency gate.
#
# THREE PHASES, one tally (`PASS: <n> FAIL: <m>`, exit 1 on any failure):
#
#   1. UNIT MAP. Units are extracted LIVE from the prose — never hand-copied — in
#      skills/automate-loop/{resume,per-item-loop,modes-and-merge-gate}.md, fenced code
#      blocks skipped: (a) every `##`/`###`/`####` heading, id `<file>|<heading text>`;
#      (b) every column-0 numbered list item, id `<file>|<nearest heading>|L<k>.<n>`
#      (k = 1-based ordinal of that numbered list under the heading — a list restarts at
#      `1.` — and n = the item number). The committed map
#      fixtures/automate-golden/MAP.tsv holds data rows `<unit id><TAB><case>` or
#      `<unit id><TAB>judgment — covered at the step boundary: <case>` (`#` lines and
#      blank lines are comments). One `map: <unit id> → <target>` line per unit, then:
#      `FAIL: unmapped unit <id>`, `FAIL: stale map row <id>` (its unit is gone),
#      `FAIL: map names missing case <case>`, `FAIL: duplicate map row <id>`.
#   2. SCRUB. No file under the fixtures dir may contain `/Users/` or `/home/`
#      (`FAIL: home path in <file>`).
#   3. CASES. Each fixtures/automate-golden/<case>/ holds:
#        input.md      the run file BEFORE the step (trimmed from a real run)
#        steps         one invocation per line, in the prose's order (`#`/blank skipped):
#                      `<subcommand> <args…>` runs `bash "$H" <subcommand> <args…>`;
#                      `loop: <shell>` is the LOOP's own write where no helper exists
#                      (e.g. the `## Status:` line through runfile-write) — named so a
#                      reader sees exactly where today's loop has no helper.
#                      Placeholders (shell variables, expanded by eval): $RF the scratch
#                      run file, $ROOT the scratch checkout, $AD its .supervisor/automate,
#                      $H the helper, $RUN_ID, $PREV the previous step's stdout file.
#        expected.md   the run file AFTER the steps
#        expected.out  per step: `$ <line>`, its stdout, each stderr line as `! <line>`,
#                      then `= <exit code>` (MANDATORY: the run file cannot show e.g. the
#                      drain-start guard's exit 3, which fires after its line is appended)
#        source        MANDATORY provenance: `run: <real run id>` (also the scratch run
#                      file's name), then free text naming the trimmed lines and any gap
#      optional:
#        gh.stub       the scripted `gh` answer table, one rule per line:
#                      `<exit code><TAB><bash glob over "$*"><TAB><stdout>`; first match
#                      wins; an unmatched call exits 1 (stderr `gh-stub: unmatched`)
#        tree/         copied into the scratch checkout root before the steps (sidecars,
#                      requirement files, drafts, a merge-watch marker, ctx.json …)
#        setup         sourced in the scratch root before the steps (deterministic git
#                      commits/remotes only); its output is not compared
#      The case runs in its own `mktemp -d` checkout (`git init`, branch main, HOME and the
#      git identity sandboxed, the stub `gh` first on PATH — no network, never this
#      checkout). Actual and expected are both normalised — ISO timestamps
#      `YYYY-MM-DDTHH:MM:SSZ` → `<TS>`, the scratch root → `<ROOT>`, the case dir → `<CASE>`,
#      the work dir → `<TMP>`
#      — then compared byte for byte: `FAIL: <case>: run file differs` /
#      `FAIL: <case>: step output differs`, each with a unified diff.
#   4. MUTATION LEGS (AC4; skipped when GOLDEN_SKIP_LEGS=1, which every inner run sets, and under
#      GOLDEN_WRITE=1; an inner run never inherits GOLDEN_WRITE).
#      Each runs this suite again against a mutated COPY — never the working tree — and is
#      gated: the mutant is non-empty, differs from the original, the anchor occurs exactly
#      once, and a mutated script passes `bash -n`; a leg whose mutant cannot be built
#      FAILS. Each asserts the inner run exits non-zero AND names the expected case/unit.
#        M1 bundle: `owned drain started)'` → `owned drain startex)'` (runfile.sh's
#           _progress_current_guard re_g)            ⇒ drain-pinned-start-line-current-not-set
#        M2 bundle: `local msg="current_rebuilt:` → `…rebuilx:`  ⇒ resume-current-rebuild
#        M3 automate-dismissed.sh copy beside the bundle (its symlink removed first, the
#           real file asserted unchanged): `dismissed: $decision` → `dismissex: $decision`
#                                                    ⇒ dismissed-findings-decision-step
#        M4 prose copy + `### Scratch heading`       ⇒ unmapped unit
#        M5 prose copy minus `### Termination (two exits)` ⇒ stale map row
#        M6 fixtures copy + a `/Users/x/` line        ⇒ home path
#
# ENV OVERRIDES (tests and by-hand mutation control only):
#   GOLDEN_HELPERS=<bundle path>  run the cases through this helper instead of a fresh
#                                 bundle (its directory must hold the sibling scripts)
#   GOLDEN_PROSE_DIR=<dir>        read the three prose files from <dir>
#   GOLDEN_FIXTURES=<dir>         read MAP.tsv and the cases from <dir>
#   GOLDEN_CASES="<a> <b>"|-      run only these cases (`-` = none); default all
#   GOLDEN_SKIP_LEGS=1            skip phase 4
#   GOLDEN_WRITE=1                AUTHORING ONLY: write each case's actual run file and
#                                 output over expected.md / expected.out (scratch root
#                                 normalised to <ROOT>); every written case counts as a
#                                 FAIL, so a run under it can never pass.
#
# Bash 3.2 / BSD-userland safe; every mktemp -d lives under one work dir removed in a trap.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
PROSE_DIR="${GOLDEN_PROSE_DIR:-$HERE/../skills/automate-loop}"
FIX="${GOLDEN_FIXTURES:-$HERE/fixtures/automate-golden}"
PROSE_FILES="resume.md per-item-loop.md modes-and-merge-gate.md"
JUDGE_PREFIX="judgment — covered at the step boundary: "
TAB="$(printf '\t')"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "FAIL: $1"; fail=$((fail + 1)); }

WORK="$(mktemp -d)" || { echo "FAIL: mktemp -d"; exit 1; }
WORK_P="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

# --------------------------------------------------------------------------------------
# the helper under test — the shape of test-automate-helpers.sh's ah_build_bundle: the
# dispatcher's own _ah_bundle expansion, written beside a symlink to every other scripts/
# entry so each `$(dirname "$0")` sibling lookup resolves.
# --------------------------------------------------------------------------------------
build_bundle() { # <dir>
  local d="$1" e
  mkdir -p "$d" || return 1
  eval "$(awk '/^_ah_bundle\(\) \{$/,/^}$/' "$HERE/automate-helpers.sh")"
  for e in "$HERE"/*; do
    [ "$e" = "$HERE/automate-helpers.sh" ] || ln -s "$e" "$d/$(basename "$e")" || return 1
  done
  _ah_bundle "$HERE/automate-helpers.sh" > "$d/automate-helpers.sh" && [ -s "$d/automate-helpers.sh" ] || return 1
  echo "$d/automate-helpers.sh"
}

# --------------------------------------------------------------------------------------
# phase 1 — units, live
# --------------------------------------------------------------------------------------
extract_units() { # <prose dir> — one unit id per line, in file order
  local f
  for f in $PROSE_FILES; do
    if [ ! -f "$1/$f" ]; then echo "__MISSING_PROSE__|$f"; continue; fi
    awk -v F="$f" '
      { sub(/\r$/, "") }
      /^(   |  | )?(```|~~~)/ { fence = !fence; next }
      fence { next }
      /^(##|###|####) / { h = $0; sub(/^#+ /, "", h); sub(/[ \t]+$/, "", h); print F "|" h; k = 0; next }
      /^[0-9]+\. / { n = $0; sub(/\..*/, "", n); if (n == "1") k++; print F "|" h "|L" k "." n; next }
    ' "$1/$f"
  done
}

check_map() {
  local units map rows id tgt cs n dup
  units="$WORK/units.txt"; rows="$WORK/maprows.tsv"
  extract_units "$PROSE_DIR" > "$units"
  if grep -q '^__MISSING_PROSE__|' "$units"; then
    no "prose file missing under $PROSE_DIR: $(grep '^__MISSING_PROSE__|' "$units" | sed 's/^__MISSING_PROSE__|//' | tr '\n' ' ')"
    return
  fi
  map="$FIX/MAP.tsv"
  [ -f "$map" ] || { no "MAP.tsv missing under $FIX"; return; }
  awk '/^#/ || /^[ \t]*$/ { next } { print }' "$map" > "$rows"
  n=0
  while IFS= read -r id; do
    n=$((n + 1))
    tgt="$(awk -F'\t' -v u="$id" '$1 == u { print $2; exit }' "$rows")"
    if [ -z "$tgt" ]; then no "unmapped unit $id"; continue; fi
    echo "map: $id → $tgt"
  done < "$units"
  dup="$(cut -f1 "$rows" | env LC_ALL=C sort | uniq -d)"
  if [ -n "$dup" ]; then
    while IFS= read -r id; do no "duplicate map row $id"; done <<EOF
$dup
EOF
  fi
  local bad=0
  while IFS="$TAB" read -r id tgt; do
    if ! grep -qxF -- "$id" "$units"; then no "stale map row $id"; bad=1; fi
    cs="${tgt#"$JUDGE_PREFIX"}"
    if [ -z "$cs" ] || [ ! -d "$FIX/$cs" ]; then no "map names missing case ${cs:-<empty>}"; bad=1; fi
  done < "$rows"
  [ "$bad" = 0 ] && ok "MAP.tsv: no stale row, every named case exists"
  if ! grep -q '' "$units"; then no "no unit extracted from $PROSE_DIR"; return; fi
  ok "unit map read: $n unit(s) extracted live from $PROSE_FILES"
}

# --------------------------------------------------------------------------------------
# phase 2 — scrub
# --------------------------------------------------------------------------------------
check_scrub() {
  local hits f
  hits="$(grep -rlE '/Users/|/home/' "$FIX" 2>/dev/null | env LC_ALL=C sort)"
  if [ -n "$hits" ]; then
    while IFS= read -r f; do no "home path in ${f#"$FIX"/}"; done <<EOF
$hits
EOF
  else
    ok "no /Users/ or /home/ path under the fixtures"
  fi
}

# --------------------------------------------------------------------------------------
# phase 3 — cases
# --------------------------------------------------------------------------------------
GH_STUB_BODY='#!/usr/bin/env bash
# golden gh stub: first rule of $GOLDEN_GH_TABLE whose glob matches "$*" answers.
all="$*"
if [ -n "${GOLDEN_GH_TABLE:-}" ] && [ -f "$GOLDEN_GH_TABLE" ]; then
  while IFS="	" read -r rc pat out || [ -n "$rc" ]; do
    case "$rc" in ""|"#"*) continue ;; esac
    # shellcheck disable=SC2254
    case "$all" in $pat) [ -n "$out" ] && printf "%s\n" "$out"; exit "$rc" ;; esac
  done < "$GOLDEN_GH_TABLE"
fi
echo "gh-stub: unmatched: $all" >&2
exit 1
'

norm() { # <file> — print it normalised (scratch root/work dir → <ROOT>/<TMP>, ISO ts → <TS>)
  local c
  c="$(cat "$1"; printf x)"; c="${c%x}"
  c="${c//"$CASE_ROOT_P"/<ROOT>}"; c="${c//"$CASE_ROOT"/<ROOT>}"
  c="${c//"$CASE_DIR_P"/<CASE>}"; c="${c//"$CASE_DIR"/<CASE>}"
  c="${c//"$WORK_P"/<TMP>}"; c="${c//"$WORK"/<TMP>}"
  printf '%s' "$c" | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/<TS>/g'
}

unroot() { # <file> — the file with only the scratch paths normalised (GOLDEN_WRITE)
  local c
  c="$(cat "$1"; printf x)"; c="${c%x}"
  c="${c//"$CASE_ROOT_P"/<ROOT>}"; c="${c//"$CASE_ROOT"/<ROOT>}"
  c="${c//"$CASE_DIR_P"/<CASE>}"; c="${c//"$CASE_DIR"/<CASE>}"
  c="${c//"$WORK_P"/<TMP>}"; c="${c//"$WORK"/<TMP>}"
  printf '%s' "$c"
}

run_case() { # <case dir>
  local cd_="$1" name f run_id cw bin home rf out line k=0 rc o e
  name="$(basename "$cd_")"
  for f in input.md steps expected.md expected.out source; do
    [ -f "$cd_/$f" ] || { no "$name: missing $f"; return; }
  done
  run_id="$(sed -n 's/^run: *\([^ ]*\).*/\1/p' "$cd_/source" | head -n1)"
  [ -n "$run_id" ] || { no "$name: source names no 'run: <id>'"; return; }
  cw="$(mktemp -d "$WORK/case.XXXXXX")" || { no "$name: mktemp -d"; return; }
  CASE_ROOT="$cw/repo"; bin="$cw/bin"; home="$cw/home"
  mkdir -p "$CASE_ROOT/.supervisor/automate" "$bin" "$home"
  CASE_ROOT_P="$(cd "$CASE_ROOT" && pwd -P)"; CASE_DIR="$cw"; CASE_DIR_P="$(cd "$cw" && pwd -P)"
  printf '%s' "$GH_STUB_BODY" > "$bin/gh"; chmod +x "$bin/gh"
  rf="$CASE_ROOT/.supervisor/automate/$run_id.md"
  out="$cw/actual.out"; : > "$out"
  (
    cd "$CASE_ROOT" || exit 1
    export HOME="$home" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=golden GIT_AUTHOR_EMAIL=golden@example.invalid \
      GIT_COMMITTER_NAME=golden GIT_COMMITTER_EMAIL=golden@example.invalid \
      GIT_AUTHOR_DATE="2026-10-13T12:00:00Z" GIT_COMMITTER_DATE="2026-10-13T12:00:00Z"
    git init -q . && git symbolic-ref HEAD refs/heads/main
  ) >/dev/null 2>&1 || { no "$name: git init failed"; return; }
  cp "$cd_/input.md" "$rf"
  [ -d "$cd_/tree" ] && cp -R "$cd_/tree/." "$CASE_ROOT/"
  if [ -f "$cd_/setup" ]; then
    if ! ( cd "$CASE_ROOT" && export HOME="$home" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=golden \
             GIT_AUTHOR_EMAIL=golden@example.invalid GIT_COMMITTER_NAME=golden \
             GIT_COMMITTER_EMAIL=golden@example.invalid GIT_AUTHOR_DATE="2026-10-13T12:00:00Z" \
             GIT_COMMITTER_DATE="2026-10-13T12:00:00Z" ROOT="$CASE_ROOT" RF="$rf" RUN_ID="$run_id" \
           && . "$cd_/setup" ) >"$cw/setup.log" 2>&1; then
      no "$name: setup failed"; sed 's/^/    /' "$cw/setup.log"; return
    fi
  fi
  local prev="$cw/prev.none"; : > "$prev"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ""|"#"*) continue ;; esac
    k=$((k + 1)); o="$cw/step$k.out"; e="$cw/step$k.err"
    (
      cd "$CASE_ROOT" || exit 98
      unset LOOMWRIGHT_GH_BIN LOOMWRIGHT_HOLDER_PID
      export HOME="$home" PATH="$bin:$PATH" GOLDEN_GH_TABLE="$cd_/gh.stub" GIT_CONFIG_NOSYSTEM=1 \
        GIT_AUTHOR_NAME=golden GIT_AUTHOR_EMAIL=golden@example.invalid \
        GIT_COMMITTER_NAME=golden GIT_COMMITTER_EMAIL=golden@example.invalid \
        GIT_AUTHOR_DATE="2026-10-13T12:00:00Z" GIT_COMMITTER_DATE="2026-10-13T12:00:00Z" \
        RF="$rf" ROOT="$CASE_ROOT" AD="$CASE_ROOT/.supervisor/automate" H="$H" RUN_ID="$run_id" PREV="$prev"
      case "$line" in
        "loop: "*) eval "${line#loop: }" ;;
        *) eval "bash \"\$H\" $line" ;;
      esac
    ) > "$o" 2> "$e" < /dev/null
    rc=$?
    {
      printf '$ %s\n' "$line"
      cat "$o"
      sed 's/^/! /' "$e"
      printf '= %s\n' "$rc"
    } >> "$out"
    prev="$o"
  done < "$cd_/steps"
  if [ "${GOLDEN_WRITE:-}" = 1 ]; then
    unroot "$rf" > "$cd_/expected.md"; unroot "$out" > "$cd_/expected.out"
    no "$name: WROTE expected.md + expected.out (GOLDEN_WRITE — re-run without it to verify)"
    return
  fi
  local bad=0
  norm "$rf" > "$cw/a.md"; norm "$cd_/expected.md" > "$cw/x.md"
  if ! cmp -s "$cw/a.md" "$cw/x.md"; then
    no "$name: run file differs"; diff -u "$cw/x.md" "$cw/a.md" | sed 's/^/    /'; bad=1
  fi
  norm "$out" > "$cw/a.out"; norm "$cd_/expected.out" > "$cw/x.out"
  if ! cmp -s "$cw/a.out" "$cw/x.out"; then
    no "$name: step output differs"; diff -u "$cw/x.out" "$cw/a.out" | sed 's/^/    /'; bad=1
  fi
  [ "$bad" = 0 ] && ok "$name: run file + step output match ($k step(s))"
}

run_cases() {
  local c d sel="${GOLDEN_CASES:-}"
  if [ "$sel" = "-" ]; then return; fi
  if [ -n "$sel" ]; then
    for c in $sel; do
      if [ -d "$FIX/$c" ]; then run_case "$FIX/$c"; else no "GOLDEN_CASES names missing case $c"; fi
    done
    return
  fi
  for d in "$FIX"/*/; do
    [ -f "$d/steps" ] || [ -f "$d/input.md" ] || continue
    run_case "${d%/}"
  done
}

# --------------------------------------------------------------------------------------
# phase 4 — mutation legs
# --------------------------------------------------------------------------------------
count_of() { # <fixed string> <file> — occurrences (lines) of the string
  grep -cF -- "$1" "$2" 2>/dev/null || true
}

mutate_file() { # <file> <anchor> <replacement> <out> — copy with the ONE anchor replaced
  AN="$2" RE="$3" awk 'BEGIN { a = ENVIRON["AN"]; r = ENVIRON["RE"] }
    { i = index($0, a); if (i > 0 && !d) { $0 = substr($0, 1, i - 1) r substr($0, i + length(a)); d = 1 } print }' "$1" > "$4"
}

gate_mutant() { # <leg> <original> <mutant> <anchor> <script?1|0> — 0 when the mutant is usable
  local leg="$1" orig="$2" mut="$3" anchor="$4" isscript="$5" c
  c="$(count_of "$anchor" "$orig")"
  [ "$c" = 1 ] || { no "$leg: anchor occurs $c time(s) in $(basename "$orig"), want exactly 1 — mutant not built"; return 1; }
  [ -s "$mut" ] || { no "$leg: mutant is empty"; return 1; }
  if cmp -s "$orig" "$mut"; then no "$leg: mutant does not differ from the original"; return 1; fi
  if [ "$isscript" = 1 ] && ! bash -n "$mut" 2>/dev/null; then no "$leg: mutant fails bash -n"; return 1; fi
  return 0
}

inner() { # <log> <env assignments…> — run this suite again; prints its exit code
  local log="$1"; shift
  # Never inherit GOLDEN_WRITE: an inner run under a mutant must not overwrite a case's expected files.
  env -u GOLDEN_WRITE GOLDEN_SKIP_LEGS=1 "$@" bash "$SELF" > "$log" 2>&1
  echo $?
}

leg_assert() { # <leg> <rc> <log> <must-contain>
  if [ "$2" -ne 0 ] && grep -qF -- "$4" "$3"; then
    ok "$1: inner run red (exit $2), names: $4"
  else
    no "$1: inner run exit $2, wanted non-zero naming '$4'"; tail -n 15 "$3" | sed 's/^/    /'
  fi
}

run_legs() {
  local d b rc anchor
  # M1 — the drain-start guard's `owned drain started` alternative.
  d="$WORK/m1"; b="$(build_bundle "$d")" || { no "M1: bundle not built"; b=""; }
  if [ -n "$b" ]; then
    anchor="owned drain started)'"
    cp "$b" "$WORK/m1.orig"; mutate_file "$WORK/m1.orig" "$anchor" "owned drain startex)'" "$b"
    if gate_mutant M1 "$WORK/m1.orig" "$b" "$anchor" 1; then
      rc="$(inner "$WORK/m1.log" GOLDEN_HELPERS="$b" GOLDEN_CASES=drain-pinned-start-line-current-not-set)"
      leg_assert M1 "$rc" "$WORK/m1.log" "FAIL: drain-pinned-start-line-current-not-set:"
    fi
  fi
  # M2 — current-rebuild's `current_rebuilt:` message.
  d="$WORK/m2"; b="$(build_bundle "$d")" || { no "M2: bundle not built"; b=""; }
  if [ -n "$b" ]; then
    anchor='local msg="current_rebuilt:'
    cp "$b" "$WORK/m2.orig"; mutate_file "$WORK/m2.orig" "$anchor" 'local msg="current_rebuilx:' "$b"
    if gate_mutant M2 "$WORK/m2.orig" "$b" "$anchor" 1; then
      rc="$(inner "$WORK/m2.log" GOLDEN_HELPERS="$b" GOLDEN_CASES=resume-current-rebuild)"
      leg_assert M2 "$rc" "$WORK/m2.log" "FAIL: resume-current-rebuild:"
    fi
  fi
  # M3 — dismissed-decide's progress prefix, in a COPY of automate-dismissed.sh beside the
  # bundle. The bundle dir holds a SYMLINK to the real file: remove it first, so the mutant
  # is written as a new file and never through the link into the working tree.
  local real="$HERE/automate-dismissed.sh" before after
  before="$(cksum < "$real")"
  d="$WORK/m3"; b="$(build_bundle "$d")" || { no "M3: bundle not built"; b=""; }
  if [ -n "$b" ]; then
    anchor='dismissed: $decision'
    rm -f "$d/automate-dismissed.sh"
    mutate_file "$real" "$anchor" 'dismissex: $decision' "$d/automate-dismissed.sh"
    if [ -L "$d/automate-dismissed.sh" ]; then
      no "M3: mutant path is still a symlink"
    elif gate_mutant M3 "$real" "$d/automate-dismissed.sh" "$anchor" 1; then
      rc="$(inner "$WORK/m3.log" GOLDEN_HELPERS="$b" GOLDEN_CASES=dismissed-findings-decision-step)"
      leg_assert M3 "$rc" "$WORK/m3.log" "FAIL: dismissed-findings-decision-step:"
    fi
  fi
  after="$(cksum < "$real")"
  if [ "$before" = "$after" ] && { ! git -C "$HERE" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
       || git -C "$HERE" diff --quiet -- automate-dismissed.sh; }; then
    ok "M3: the real automate-dismissed.sh is unchanged"
  else
    no "M3: the real automate-dismissed.sh CHANGED"
  fi
  # M4 — an extra heading in a prose copy.
  d="$WORK/m4"; mkdir -p "$d"; cp "$PROSE_DIR"/*.md "$d/"
  printf '\n### Scratch heading\n' >> "$d/per-item-loop.md"
  if [ -s "$d/per-item-loop.md" ] && ! cmp -s "$PROSE_DIR/per-item-loop.md" "$d/per-item-loop.md"; then
    rc="$(inner "$WORK/m4.log" GOLDEN_PROSE_DIR="$d" GOLDEN_CASES=-)"
    leg_assert M4 "$rc" "$WORK/m4.log" "FAIL: unmapped unit per-item-loop.md|Scratch heading"
  else
    no "M4: prose mutant not built"
  fi
  # M5 — a mapped heading removed from a prose copy.
  d="$WORK/m5"; mkdir -p "$d"; cp "$PROSE_DIR"/*.md "$d/"
  anchor="### Termination (two exits)"
  awk -v a="$anchor" '$0 != a' "$PROSE_DIR/per-item-loop.md" > "$d/per-item-loop.md"
  if gate_mutant M5 "$PROSE_DIR/per-item-loop.md" "$d/per-item-loop.md" "$anchor" 0; then
    rc="$(inner "$WORK/m5.log" GOLDEN_PROSE_DIR="$d" GOLDEN_CASES=-)"
    leg_assert M5 "$rc" "$WORK/m5.log" "FAIL: stale map row per-item-loop.md|Termination (two exits)"
  fi
  # M6 — a home path in a fixtures copy.
  d="$WORK/m6"; mkdir -p "$d"; cp -R "$FIX/." "$d/"
  printf '%s\n' "- leaked /Users/x/ path" >> "$d/MAP.tsv"
  if [ -s "$d/MAP.tsv" ] && ! cmp -s "$FIX/MAP.tsv" "$d/MAP.tsv"; then
    rc="$(inner "$WORK/m6.log" GOLDEN_FIXTURES="$d" GOLDEN_CASES=-)"
    leg_assert M6 "$rc" "$WORK/m6.log" "FAIL: home path in MAP.tsv"
  else
    no "M6: fixture mutant not built"
  fi
}

# --------------------------------------------------------------------------------------
echo "== test-automate-golden.sh — prose: $PROSE_DIR · fixtures: $FIX"
if [ -n "${GOLDEN_HELPERS:-}" ]; then
  H="$GOLDEN_HELPERS"
  [ -f "$H" ] || { echo "FAIL: GOLDEN_HELPERS not found: $H"; echo "PASS: 0 FAIL: 1"; exit 1; }
else
  H="$(build_bundle "$WORK/bundle")" || { echo "FAIL: could not build the automate-helpers.sh bundle"; echo "PASS: 0 FAIL: 1"; exit 1; }
fi
CASE_ROOT=""; CASE_ROOT_P=""; CASE_DIR=""; CASE_DIR_P=""

echo "-- 1. unit map"
check_map
echo "-- 2. home-path scrub"
check_scrub
echo "-- 3. golden cases"
run_cases
if [ "${GOLDEN_WRITE:-}" = 1 ]; then
  echo "-- 4. mutation legs skipped (GOLDEN_WRITE authoring run)"
elif [ "${GOLDEN_SKIP_LEGS:-}" != 1 ]; then
  echo "-- 4. mutation legs"
  run_legs
fi
echo "PASS: $pass FAIL: $fail"
[ "$fail" -eq 0 ]
