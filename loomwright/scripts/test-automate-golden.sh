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
#      `1.` — and n = the item number). A fence opens on a 0–3-space-indented run of 3+
#      backticks or 3+ tildes and closes ONLY on a bare run of the SAME character at least
#      as long (CommonMark), so a ``` line inside a ~~~ block is content. The committed map
#      fixtures/automate-golden/MAP.tsv holds data rows `<unit id><TAB><case>` or
#      `<unit id><TAB>judgment — covered at the step boundary: <case>` (`#` lines and
#      blank lines are comments). One `map: <unit id> → <target>` line per unit, then:
#      `FAIL: unmapped unit <id>`, `FAIL: stale map row <id>` (its unit is gone),
#      `FAIL: map names missing case <case>`, `FAIL: duplicate map row <id>`,
#      `FAIL: duplicate unit <id>` (a repeated heading would silently share one map row).
#   2. SCRUB. No file under the fixtures dir may contain `/Users/`, `/home/` or a `~/`
#      home-relative path (`FAIL: home path in <file>`). And when the fixtures dir in use sits in a git work
#      tree, no file under it may be gitignored (`FAIL: ignored fixture <path>`): an
#      ignored fixture exists on the author's disk but never in a clean checkout, so the
#      suite would pass here and fail in CI (the as05 `*/**/.supervisor/` incident).
#      Editor/OS junk (`.DS_Store`, `*.swp`, `*.swo`, `*~`) is skipped by that check: it is
#      never a fixture, and a dev checkout's stray copy is ignored on purpose.
#      And no `<case>/expected.out` may hold the stderr noise line of phase 3's rule
#      (`FAIL: sigpipe noise pinned in <case>/expected.out`).
#      And no step may read $PREV right after a `current-set` / `runfile-write` step, or on
#      the first step (`FAIL: <case>: $PREV read after <subcommand>` / `… before any step`):
#      those print a fixed status token, never a diagnostic (the drain-round-1 bug).
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
#                      requirement files, drafts, a merge-watch marker, ctx.json …).
#                      Dot-paths are STORED as `dot-<name>` (e.g. `tree/dot-supervisor/`,
#                      `tree/lanes/L1/dot-supervisor/`) because the repo ignores
#                      `*/**/.supervisor/`; the copy maps every `dot-<name>` path
#                      component back to `.<name>` in the scratch root — FILES as well
#                      as directories, by design: a case needing e.g. a `.gitignore`
#                      stores it as `dot-gitignore`, because a real `.gitignore` under
#                      tree/ would act on THIS repo's own ignore rules.
#        setup         sourced in the scratch root before the steps (deterministic git
#                      commits/remotes only); its output is not compared
#      The case runs in its own `mktemp -d` checkout (`git init`, branch main, HOME and the
#      git identity sandboxed, the stub `gh` first on PATH — no network, never this
#      checkout). Actual and expected are both normalised — ISO timestamps
#      `YYYY-MM-DDTHH:MM:SSZ` → `<TS>`, the scratch root → `<ROOT>`, the case dir → `<CASE>`,
#      the work dir → `<TMP>`
#      — then compared byte for byte: `FAIL: <case>: run file differs` /
#      `FAIL: <case>: step output differs`, each with a unified diff.
#      HONEST LIMIT: the `<TS>` normalisation hides WHICH timestamp a helper wrote — a wrong
#      but well-formed `YYYY-MM-DDTHH:MM:SSZ` (stale, future, another field's) still matches;
#      only a malformed or missing one differs. No leg pins a timestamp's value or order.
#      ONE STDERR NOISE RULE (step output only, applied identically to actual and expected,
#      and to what GOLDEN_WRITE writes, so no expected.out ever holds it): a recorded stderr
#      line matching SIGPIPE_NOISE_RE (below: `! <path>: line <n>: printf: write error:
#      Broken pipe` whose <path> is `automate-lanes.sh` or an `automate-lanes.d/<part>.sh`)
#      is dropped. The same Broken-pipe line from any other script is compared. The filter
#      keeps every other byte, a NUL included (`grep -a`, C locale).
#      Every other stderr line is compared. Why: automate-lanes.sh's validation-gate --waive
#      pipes _lanes_validation_rows (a `printf` per row inside a `while read` loop) into an
#      awk that `exit`s on the first matching row. Bash names the file that DEFINES the
#      printing function, so today the line names automate-lanes.d/readiness.sh, the part
#      _lanes_validation_rows lives in. When the process inherits SIGPIPE as
#      IGNORED (CI runners do; a default-disposition shell is killed silently instead), the
#      next printf gets EPIPE and bash prints that line — whether it fires depends on the
#      disposition and on whether awk has exited yet. Stdout, the exit code and the run file
#      are unaffected; the line carries no contract. A pre-existing helper race (evidence
#      F9), recorded, not fixed here. Leg M10 proves the rule is that narrow.
#   4. MUTATION LEGS (AC4; skipped when GOLDEN_SKIP_LEGS=1, which every inner run sets, and under
#      GOLDEN_WRITE=1; an inner run never inherits GOLDEN_WRITE).
#      Each runs this suite again against a mutated COPY — never the working tree — and is
#      gated: the mutant is non-empty, differs from the original, the anchor occurs exactly
#      once, and a mutated script passes `bash -n`; a leg whose mutant cannot be built
#      FAILS. Each asserts the inner run exits non-zero AND names the expected case/unit.
#        M0 the UNMUTATED control for M1–M3: a freshly built bundle runs their three cases
#           ⇒ exit 0, each case ok; while M0 is not green, M1–M3 are not judged (FAIL)
#        M1 bundle:`owned drain started)'` → `owned drain startex)'` (runfile.sh's
#           _progress_current_guard re_g)            ⇒ drain-pinned-start-line-current-not-set
#        M2 bundle: `local msg="current_rebuilt:` → `…rebuilx:`  ⇒ resume-current-rebuild
#        M3 automate-dismissed.sh copy beside the bundle (its symlink removed first, the
#           real file asserted unchanged): `dismissed: $decision` → `dismissex: $decision`
#                                                    ⇒ dismissed-findings-decision-step
#        M4 prose copy + `### Scratch heading`       ⇒ unmapped unit
#        M5 prose copy minus `### Termination (two exits)` ⇒ stale map row
#        M6 fixtures copy + a `/Users/x/` line        ⇒ home path
#        M6b fixtures copy, a done brief + a `~/Documents/x` Project line ⇒ home path
#        M7 prose copy + `~~~` / ``` / `~~~` then `### After mixed fence` ⇒ unmapped unit
#        M7b prose copy + a ```` fence holding ``` and `### Inside long fence`, then
#           `### After long fence` ⇒ unmapped unit After…, and Inside… NOT a unit (the
#           shorter ``` line does not close the longer fence)
#        M8 prose copy + a second `### Termination (two exits)` ⇒ duplicate unit
#        M9 a scratch git repo ignoring `*/**/.supervisor/` holding a fixtures copy with a
#           `tree/.supervisor/` file                 ⇒ ignored fixture
#        M9b as M9, plus an ignored `.DS_Store` and `*.swp` in the copy ⇒ the real ignored
#           fixture is named, the junk is NOT
#        M10 the stderr noise rule, on fixtures copies of gate-validation-waive (one line
#           inserted before the waive step's `= ` line of expected.out):
#           a the Broken-pipe line naming automate-lanes.sh ⇒ the case stays GREEN (`ok:
#             gate-validation-waive:`); the scrub names it (`sigpipe noise pinned`)
#           a2 the same, naming automate-lanes.d/readiness.sh (today's real producer) ⇒ GREEN
#           b the same line with `echo:` for `printf:` ⇒ step output differs (red)
#           c an unrelated `! unexpected stderr` line ⇒ step output differs (red)
#           e the Broken-pipe line naming automate-helpers.sh ⇒ step output differs (red)
#           d the unmutated case run with SIGPIPE inherited as ignored (the CI condition
#             that produces the line)             ⇒ stays GREEN
#           f the filter itself, fed a NUL byte before the noise line and no final newline
#             ⇒ output is the input minus that line, byte for byte (no line lost after
#             the NUL, the missing final newline kept)
#           g a suite copy whose filter exits 139 at once (a crash leaves BOTH sides empty,
#             hence equal) ⇒ `FAIL: <case>: step-output filter failed` (red), never a match
#        M11 fixtures copy of pick-time-lane-guard-park/steps restored to its pre-fix shape
#           (cache step dropped, Progress step reads $PREV) ⇒ $PREV read after current-set
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
      /^(   |  | )?(```|~~~)/ {
        s = $0; sub(/^ */, "", s); c = substr(s, 1, 1); n = 0
        while (substr(s, n + 1, 1) == c) n++
        if (fc == "") { fc = c; fl = n; next }
        if (c == fc && n >= fl && substr(s, n + 1) ~ /^[ \t]*$/) { fc = ""; fl = 0 }
        next
      }
      fc != "" { next }
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
  dup="$(env LC_ALL=C sort "$units" | uniq -d)"
  if [ -n "$dup" ]; then
    while IFS= read -r id; do no "duplicate unit $id"; done <<EOF
$dup
EOF
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
  hits="$(grep -rlE '/Users/|/home/|~/' "$FIX" 2>/dev/null | env LC_ALL=C sort)"
  if [ -n "$hits" ]; then
    while IFS= read -r f; do no "home path in ${f#"$FIX"/}"; done <<EOF
$hits
EOF
  else
    ok "no /Users/, /home/ or ~/ path under the fixtures"
  fi
  # the noise rule's line is never pinned (GOLDEN_WRITE drops it; this catches a hand edit)
  hits="$(grep -lE "$SIGPIPE_NOISE_RE" "$FIX"/*/expected.out 2>/dev/null | env LC_ALL=C sort)"
  if [ -n "$hits" ]; then
    while IFS= read -r f; do no "sigpipe noise pinned in ${f#"$FIX"/}"; done <<EOF
$hits
EOF
  else
    ok "no expected.out pins the SIGPIPE noise line"
  fi
}

# $PREV is ONLY the immediately preceding step's stdout (run_case reassigns it after every
# step). `current-set` and `runfile-write` print a fixed status token (`current-set: written`
# or nothing), never a diagnostic, so a step reading $PREV right after one of them is pinning
# the wrong producer (the as05 drain-round-1 bug: three parks pinned `current-set: written`
# instead of their refusal). Cache the producer's stdout right after it instead
# (`loop: cp "$PREV" "$ROOT/.<name>.line"`). A loop step's subcommand is the last
# `"$H" <word>` it invokes. A $PREV read on the first step reads the empty prev.none.
check_prev_reads() {
  local f c hits=0 msg
  for f in "$FIX"/*/steps; do
    [ -f "$f" ] || continue
    c="${f%/steps}"; c="${c##*/}"
    while IFS= read -r msg; do
      [ -n "$msg" ] || continue
      no "$c: $msg"; hits=$((hits + 1))
    done <<EOF
$(awk '
  /^[ \t]*$/ || /^#/ { next }
  {
    if (index($0, "$PREV") > 0) {
      if (n == 0) print "$PREV read before any step"
      else if (sub_ == "current-set" || sub_ == "runfile-write") print "$PREV read after " sub_
    }
    n++
    if (substr($0, 1, 6) == "loop: ") {
      sub_ = "loop"; s = $0
      while ((i = index(s, "\"$H\" ")) > 0) { s = substr(s, i + 5); split(s, w, /[ \t]/); sub_ = w[1] }
    } else { split($0, w, /[ \t]/); sub_ = w[1] }
  }' "$f")
EOF
  done
  [ "$hits" = 0 ] && ok "no step reads \$PREV after current-set / runfile-write (or before any step)"
}

check_ignored() { # every file under the fixtures dir IN USE must be committable
  local top hits rc f
  top="$(git -C "$FIX" rev-parse --show-toplevel 2>/dev/null)" || top=""
  if [ -z "$top" ]; then
    echo "  note: $FIX is not in a git work tree — ignored-fixture check not applicable"
    return
  fi
  # read-only: find lists, check-ignore only answers; nothing in the work tree is touched.
  # Editor/OS junk is never a fixture, and a dev checkout's stray copy is ignored on purpose (M9b).
  hits="$(cd "$FIX" && find . -type f ! -name .DS_Store ! -name '*.swp' ! -name '*.swo' ! -name '*~' \
    | sed 's|^\./||' | git check-ignore --stdin)"; rc=$?
  if [ "$rc" -gt 1 ]; then no "git check-ignore failed (exit $rc) under $FIX"; return; fi
  if [ -n "$hits" ]; then
    while IFS= read -r f; do no "ignored fixture $f"; done <<EOF
$(printf '%s\n' "$hits" | env LC_ALL=C sort)
EOF
  else
    ok "no gitignored file under the fixtures (a clean checkout sees every fixture)"
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

SIGPIPE_NOISE_RE='^! (.*/)?automate-lanes(\.d/[^/:]+)?\.sh: line [0-9]+: printf: write error: Broken pipe$'
drop_sigpipe_noise() { # stdin → stdout minus the ONE stderr noise line (header); every other byte kept
  local t n rc
  # a file, never "$(cat)": command substitution drops NUL bytes (M10f)
  t="$(mktemp "$WORK/noise.XXXXXX")" || return 1
  cat > "$t"
  # -a + C locale: a NUL (or, for GNU grep, an invalid multibyte byte) must not switch grep to
  # binary mode, which prints `Binary file … matches` in place of every line after it. `env`, never
  # a bare `LC_ALL=C grep` prefix: Homebrew bash 5.3 segfaults restoring its locale after one
  # (docs/PITFALLS.md; scripts/check-locale-prefix.sh)
  env LC_ALL=C grep -a -vE "$SIGPIPE_NOISE_RE" "$t" > "$t.f"; rc=$?
  [ "$rc" -le 1 ] || { rm -f "$t" "$t.f"; return 1; }   # 1 = every line dropped; >1 = grep error
  # grep terminates its last line; keep a missing final newline missing, so the pin stays exact
  n="$(wc -c < "$t.f" | tr -d ' ')"
  if [ -s "$t" ] && [ "$(tail -c 1 "$t" | od -An -tx1 | tr -d ' \n')" != 0a ] && [ "$n" -gt 0 ] \
     && [ "$(tail -c 1 "$t.f" | od -An -tx1 | tr -d ' \n')" = 0a ]; then
    head -c "$((n - 1))" "$t.f"
  else
    cat "$t.f"
  fi
  rm -f "$t" "$t.f"
}

stage_tree() { # <tree dir> <stage dir> — copy, then every `dot-<name>` component → `.<name>`
  # (files too, deliberately — no `-type d`: see the header's tree/ entry)
  local p b t
  cp -R "$1/." "$2/" || return 1
  # deepest first, so a parent rename never invalidates a listed child path; every rename
  # stays inside its own parent directory under <stage dir>
  find "$2" -depth -name 'dot-?*' > "$2.dots" || return 1
  while IFS= read -r p; do
    b="${p##*/}"; t="${p%/*}/.${b#dot-}"
    [ -e "$t" ] && { echo "both ${p#"$2"/} and its dot-form exist" >&2; return 1; }
    mv "$p" "$t" || return 1
  done < "$2.dots"
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
  if [ -d "$cd_/tree" ]; then
    mkdir "$cw/tree" && stage_tree "$cd_/tree" "$cw/tree" 2>"$cw/tree.log" && cp -R "$cw/tree/." "$CASE_ROOT/" \
      || { no "$name: tree copy failed"; sed 's/^/    /' "$cw/tree.log"; return; }
  fi
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
    unroot "$rf" > "$cd_/expected.md"; unroot "$out" | drop_sigpipe_noise > "$cd_/expected.out"
    no "$name: WROTE expected.md + expected.out (GOLDEN_WRITE — re-run without it to verify)"
    return
  fi
  local bad=0
  norm "$rf" > "$cw/a.md"; norm "$cd_/expected.md" > "$cw/x.md"
  if ! cmp -s "$cw/a.md" "$cw/x.md"; then
    no "$name: run file differs"; diff -u "$cw/x.md" "$cw/a.md" | sed 's/^/    /'; bad=1
  fi
  # a failed (or crashed) filter leaves BOTH sides empty and equal — never compare that (M10g)
  if ! norm "$out" | drop_sigpipe_noise > "$cw/a.out" || ! norm "$cd_/expected.out" | drop_sigpipe_noise > "$cw/x.out"; then
    no "$name: step-output filter failed — output not compared"; return
  fi
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
  # M0 — the unmutated control for M1–M3: the same freshly built bundle, NOT mutated, runs
  # their three cases green. A red M1–M3 means something only while this is green.
  local m0=0 c m13="drain-pinned-start-line-current-not-set resume-current-rebuild dismissed-findings-decision-step"
  d="$WORK/m0"; b="$(build_bundle "$d")" || { no "M0: bundle not built"; b=""; }
  if [ -n "$b" ]; then
    rc="$(inner "$WORK/m0.log" GOLDEN_HELPERS="$b" GOLDEN_CASES="$m13")"
    m0=1
    for c in $m13; do grep -qF -- "ok: $c: run file + step output match" "$WORK/m0.log" || m0=0; done
    if [ "$rc" -eq 0 ] && [ "$m0" = 1 ]; then
      ok "M0: the unmutated bundle runs the M1–M3 cases green (exit 0)"
    else
      m0=0; no "M0: unmutated control exit $rc, wanted 0 with $m13 ok"; tail -n 15 "$WORK/m0.log" | sed 's/^/    /'
    fi
  fi
  # M1 — the drain-start guard's `owned drain started` alternative.
  d="$WORK/m1"; b="$(build_bundle "$d")" || { no "M1: bundle not built"; b=""; }
  if [ -n "$b" ]; then
    anchor="owned drain started)'"
    cp "$b" "$WORK/m1.orig"; mutate_file "$WORK/m1.orig" "$anchor" "owned drain startex)'" "$b"
    if [ "$m0" != 1 ]; then
      no "M1: not judged — the M0 unmutated control is not green"
    elif gate_mutant M1 "$WORK/m1.orig" "$b" "$anchor" 1; then
      rc="$(inner "$WORK/m1.log" GOLDEN_HELPERS="$b" GOLDEN_CASES=drain-pinned-start-line-current-not-set)"
      leg_assert M1 "$rc" "$WORK/m1.log" "FAIL: drain-pinned-start-line-current-not-set:"
    fi
  fi
  # M2 — current-rebuild's `current_rebuilt:` message.
  d="$WORK/m2"; b="$(build_bundle "$d")" || { no "M2: bundle not built"; b=""; }
  if [ -n "$b" ]; then
    anchor='local msg="current_rebuilt:'
    cp "$b" "$WORK/m2.orig"; mutate_file "$WORK/m2.orig" "$anchor" 'local msg="current_rebuilx:' "$b"
    if [ "$m0" != 1 ]; then
      no "M2: not judged — the M0 unmutated control is not green"
    elif gate_mutant M2 "$WORK/m2.orig" "$b" "$anchor" 1; then
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
    elif [ "$m0" != 1 ]; then
      no "M3: not judged — the M0 unmutated control is not green"
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
  # M6b — a `~/` home-relative path (the copied done briefs' old Project line) in a fixtures copy.
  local db="reconcile-closeout-merged/tree/dot-supervisor/jobs/done/2026-10-15-af39a-sweep.md"
  d="$WORK/m6b"; mkdir -p "$d"; cp -R "$FIX/." "$d/"
  printf '%s\n' "- **Project:** ~/Documents/x" >> "$d/$db"
  if [ -s "$d/$db" ] && [ -f "$FIX/$db" ] && ! cmp -s "$FIX/$db" "$d/$db"; then
    rc="$(inner "$WORK/m6b.log" GOLDEN_FIXTURES="$d" GOLDEN_CASES=-)"
    leg_assert M6b "$rc" "$WORK/m6b.log" "FAIL: home path in $db"
  else
    no "M6b: fixture mutant not built ($db)"
  fi
  # M7 — a ``` line inside a ~~~ fence must not close it.
  d="$WORK/m7"; mkdir -p "$d"; cp "$PROSE_DIR"/*.md "$d/"
  printf '\n~~~\n```\n~~~\n\n### After mixed fence\n' >> "$d/per-item-loop.md"
  if [ -s "$d/per-item-loop.md" ] && ! cmp -s "$PROSE_DIR/per-item-loop.md" "$d/per-item-loop.md"; then
    rc="$(inner "$WORK/m7.log" GOLDEN_PROSE_DIR="$d" GOLDEN_CASES=-)"
    leg_assert M7 "$rc" "$WORK/m7.log" "FAIL: unmapped unit per-item-loop.md|After mixed fence"
  else
    no "M7: prose mutant not built"
  fi
  # M7b — a ``` line inside a LONGER ```` fence must not close it (the fence-length branch):
  # the heading inside stays content, and the fence still closes on its own ```` line.
  d="$WORK/m7b"; mkdir -p "$d"; cp "$PROSE_DIR"/*.md "$d/"
  printf '\n````\n```\n### Inside long fence\n````\n\n### After long fence\n' >> "$d/per-item-loop.md"
  if [ -s "$d/per-item-loop.md" ] && ! cmp -s "$PROSE_DIR/per-item-loop.md" "$d/per-item-loop.md"; then
    rc="$(inner "$WORK/m7b.log" GOLDEN_PROSE_DIR="$d" GOLDEN_CASES=-)"
    if grep -qF -- "Inside long fence" "$WORK/m7b.log"; then
      no "M7b: the heading inside the four-backtick fence was read as a unit"; grep -F -- "Inside long fence" "$WORK/m7b.log" | sed 's/^/    /'
    else
      leg_assert M7b "$rc" "$WORK/m7b.log" "FAIL: unmapped unit per-item-loop.md|After long fence"
    fi
  else
    no "M7b: prose mutant not built"
  fi
  # M8 — a repeated heading.
  d="$WORK/m8"; mkdir -p "$d"; cp "$PROSE_DIR"/*.md "$d/"
  anchor="### Termination (two exits)"
  printf '\n%s\n' "$anchor" >> "$d/per-item-loop.md"
  if [ "$(count_of "$anchor" "$PROSE_DIR/per-item-loop.md")" = 1 ] && [ "$(count_of "$anchor" "$d/per-item-loop.md")" = 2 ]; then
    rc="$(inner "$WORK/m8.log" GOLDEN_PROSE_DIR="$d" GOLDEN_CASES=-)"
    leg_assert M8 "$rc" "$WORK/m8.log" "FAIL: duplicate unit per-item-loop.md|Termination (two exits)"
  else
    no "M8: prose mutant not built (anchor must occur once, then twice)"
  fi
  # M9 — a fixture the repo ignores (a scratch git repo, never this checkout).
  d="$WORK/m9"; mkdir -p "$d/fx"; cp -R "$FIX/." "$d/fx/"
  mkdir -p "$d/fx/run-record-pr/tree/.supervisor"; printf 'x\n' > "$d/fx/run-record-pr/tree/.supervisor/leak"
  printf '%s\n' '*/**/.supervisor/' > "$d/.gitignore"
  if git -C "$d" init -q . >/dev/null 2>&1 && [ -f "$d/fx/run-record-pr/tree/.supervisor/leak" ]; then
    rc="$(inner "$WORK/m9.log" GOLDEN_FIXTURES="$d/fx" GOLDEN_CASES=-)"
    leg_assert M9 "$rc" "$WORK/m9.log" "FAIL: ignored fixture run-record-pr/tree/.supervisor/leak"
  else
    no "M9: scratch repo not built"
  fi
  # M9b — as M9, plus ignored editor/OS junk in the copy: the real ignored fixture is still
  # named, the junk is not (a dev checkout's stray .DS_Store / *.swp is no fixture).
  d="$WORK/m9b"; mkdir -p "$d/fx"; cp -R "$FIX/." "$d/fx/"
  mkdir -p "$d/fx/run-record-pr/tree/.supervisor"; printf 'x\n' > "$d/fx/run-record-pr/tree/.supervisor/leak"
  printf 'x' > "$d/fx/.DS_Store"; printf 'x' > "$d/fx/run-record-pr/.steps.swp"
  printf '%s\n' '*/**/.supervisor/' '.DS_Store' '*.swp' > "$d/.gitignore"
  if git -C "$d" init -q . >/dev/null 2>&1 && git -C "$d" check-ignore -q fx/.DS_Store \
     && git -C "$d" check-ignore -q fx/run-record-pr/.steps.swp \
     && git -C "$d" check-ignore -q fx/run-record-pr/tree/.supervisor/leak; then
    rc="$(inner "$WORK/m9b.log" GOLDEN_FIXTURES="$d/fx" GOLDEN_CASES=-)"
    if grep -E -- '^FAIL: ignored fixture .*(\.DS_Store|\.swp)$' "$WORK/m9b.log" >/dev/null; then
      no "M9b: ignored editor/OS junk was reported as a fixture"; grep -E -- '^FAIL: ignored fixture' "$WORK/m9b.log" | sed 's/^/    /'
    else
      leg_assert M9b "$rc" "$WORK/m9b.log" "FAIL: ignored fixture run-record-pr/tree/.supervisor/leak"
    fi
  else
    no "M9b: scratch repo not built (want the junk and the leak all ignored)"
  fi
  # M10 — the stderr noise rule is exactly one line wide.
  local wc_="gate-validation-waive" v ins
  for v in a a2 b c e; do
    case "$v" in
      a) ins='! <TMP>/bundle/automate-lanes.sh: line 3039: printf: write error: Broken pipe' ;;
      a2) ins='! <TMP>/bundle/automate-lanes.d/readiness.sh: line 131: printf: write error: Broken pipe' ;;
      b) ins='! <TMP>/bundle/automate-lanes.sh: line 3039: echo: write error: Broken pipe' ;;
      c) ins='! unexpected stderr' ;;
      e) ins='! <TMP>/bundle/automate-helpers.sh: line 3039: printf: write error: Broken pipe' ;;
    esac
    d="$WORK/m10$v"; mkdir -p "$d"; cp -R "$FIX/." "$d/"
    # insert before the SECOND `= ` line (the --waive step's exit code)
    IN="$ins" awk 'BEGIN { s = ENVIRON["IN"] } /^= / && ++n == 2 { print s } { print }' \
      "$FIX/$wc_/expected.out" > "$d/$wc_/expected.out"
    if [ "$(grep -c '^= ' "$FIX/$wc_/expected.out")" -ge 2 ] \
       && [ "$(count_of "$ins" "$FIX/$wc_/expected.out")" = 0 ] && [ "$(count_of "$ins" "$d/$wc_/expected.out")" = 1 ] \
       && [ "$(wc -l < "$d/$wc_/expected.out")" -eq "$(( $(wc -l < "$FIX/$wc_/expected.out") + 1 ))" ]; then
      rc="$(inner "$WORK/m10$v.log" GOLDEN_FIXTURES="$d" GOLDEN_CASES="$wc_")"
      if [ "$v" = a ] || [ "$v" = a2 ]; then
        if grep -qF -- "ok: $wc_: run file + step output match" "$WORK/m10$v.log" \
           && ! grep -qF -- "FAIL: $wc_:" "$WORK/m10$v.log" \
           && grep -qF -- "FAIL: sigpipe noise pinned in $wc_/expected.out" "$WORK/m10$v.log"; then
          ok "M10$v: Broken-pipe line dropped (case green), and the scrub names it as pinned"
        else
          no "M10$v: wanted case green + 'sigpipe noise pinned in $wc_/expected.out'"; tail -n 15 "$WORK/m10$v.log" | sed 's/^/    /'
        fi
      else
        leg_assert "M10$v" "$rc" "$WORK/m10$v.log" "FAIL: $wc_: step output differs"
      fi
    else
      no "M10$v: expected.out mutant not built (want exactly one inserted line)"
    fi
  done
  # M10d — the CI condition itself: SIGPIPE inherited as ignored, unmutated fixtures.
  env -u GOLDEN_WRITE GOLDEN_SKIP_LEGS=1 GOLDEN_CASES="$wc_" \
    bash -c 'trap "" PIPE; exec bash "$1"' _ "$SELF" > "$WORK/m10d.log" 2>&1
  rc=$?
  if [ "$rc" -eq 0 ] && grep -qF -- "ok: $wc_: run file + step output match" "$WORK/m10d.log"; then
    ok "M10d: $wc_ green with SIGPIPE inherited as ignored"
  else
    no "M10d: inner run exit $rc under an ignored SIGPIPE, wanted 0 with $wc_ ok"; tail -n 15 "$WORK/m10d.log" | sed 's/^/    /'
  fi
  # M10f — the filter itself keeps every byte but the noise line: a NUL byte, the lines after
  # it, and a missing final newline (`grep -a`; command substitution would drop the NUL).
  printf 'keep1\000tail\n%s\nkeep2\nkeep3' '! <TMP>/bundle/automate-lanes.sh: line 1: printf: write error: Broken pipe' \
    > "$WORK/m10f.in"
  printf 'keep1\000tail\nkeep2\nkeep3' > "$WORK/m10f.want"
  if [ "$(tr -d '\000' < "$WORK/m10f.in" | wc -c)" -lt "$(wc -c < "$WORK/m10f.in")" ] \
     && ! cmp -s "$WORK/m10f.in" "$WORK/m10f.want"; then
    drop_sigpipe_noise < "$WORK/m10f.in" > "$WORK/m10f.got" 2> "$WORK/m10f.err"
    if cmp -s "$WORK/m10f.want" "$WORK/m10f.got" && [ ! -s "$WORK/m10f.err" ]; then
      ok "M10f: noise filter keeps a NUL byte, every line after it and the missing final newline"
    else
      no "M10f: noise filter output differs from the input minus the noise line"
      od -c "$WORK/m10f.got" | head -n 6 | sed 's/^/    /'; sed 's/^/    ! /' "$WORK/m10f.err"
    fi
  else
    no "M10f: NUL-byte input not built"
  fi
  # M10g — a failing filter is a FAIL, never a match: a suite copy whose filter returns 139 at
  # once (a crash's exit) leaves both sides empty; the case must still go red.
  anchor='  t="$(mktemp "$WORK/noise.'"XXXXXX"'")" || return 1'   # split, so this line is not a 2nd copy
  d="$WORK/m10g"; mkdir -p "$d"; ln -s "$HERE/hermetic-test-env.sh" "$d/hermetic-test-env.sh"
  mutate_file "$SELF" "$anchor" '  return 139' "$d/$(basename "$SELF")"
  if gate_mutant M10g "$SELF" "$d/$(basename "$SELF")" "$anchor" 1; then
    env -u GOLDEN_WRITE GOLDEN_SKIP_LEGS=1 GOLDEN_HELPERS="$H" GOLDEN_PROSE_DIR="$PROSE_DIR" GOLDEN_FIXTURES="$FIX" \
      GOLDEN_CASES="$wc_" bash "$d/$(basename "$SELF")" > "$WORK/m10g.log" 2>&1
    leg_assert M10g "$?" "$WORK/m10g.log" "FAIL: $wc_: step-output filter failed"
  fi
  # M11 — the $PREV lint, on a fixtures copy of pick-time-lane-guard-park restored to its
  # pre-fix shape: the cache step dropped and the Progress step reading $PREV again.
  local pc="pick-time-lane-guard-park" cache_line='loop: cp "$PREV" "$ROOT/.lane-guard.line"'
  d="$WORK/m11"; mkdir -p "$d"; cp -R "$FIX/." "$d/"
  anchor='$(cat "$ROOT/.lane-guard.line")'
  mutate_file "$FIX/$pc/steps" "$anchor" '$(cat "$PREV")' "$d/$pc/steps.tmp"
  awk -v c="$cache_line" '$0 != c' "$d/$pc/steps.tmp" > "$d/$pc/steps"; rm -f "$d/$pc/steps.tmp"
  if [ "$(count_of "$cache_line" "$FIX/$pc/steps")" = 1 ] && [ "$(count_of "$cache_line" "$d/$pc/steps")" = 0 ] \
     && gate_mutant M11 "$FIX/$pc/steps" "$d/$pc/steps" "$anchor" 0; then
    rc="$(inner "$WORK/m11.log" GOLDEN_FIXTURES="$d" GOLDEN_CASES=-)"
    leg_assert M11 "$rc" "$WORK/m11.log" "FAIL: $pc: \$PREV read after current-set"
  else
    no "M11: steps mutant not built (want the cache step removed and \$PREV restored)"
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
check_ignored
check_prev_reads
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
