#!/usr/bin/env bash
# test-supervisor-next-step.sh — self-test for supervisor-next-step.sh, the inline Supervisor's step
# driver (automate-speed/11). UNCOUNTED by the doc-currency gate. One tally (`PASS: <n> FAIL: <m>`, exit 1
# on any failure). Hermetic: every case runs in its own `mktemp -d` checkout — a git repo on `main` with a
# local bare `origin` (so the branch guard's fetch / pull run for real, no network), HOME and the git
# identity sandboxed, a stub `gh` first on PATH, the guard arm replaced by a recorder through the driver's
# SUPERVISOR_NEXT_STEP_GUARD_CMD.
#
# GOLDEN CASE LAYOUT (fixtures/supervisor-golden/<case>/):
#   source             first line `run: <session id / run id>` naming the real past run the case was built
#                      from, or `synthetic: <why>` (item 05's method); later lines say what was kept
#   input/             staged as the scratch checkout's `.supervisor/` (state.md, jobs/, autonomous/…);
#                      `session-logs/` stands for `logs/` (the repo's .gitignore drops any `logs/` dir) and
#                      holds exactly one `<sid>.jsonl` — its basename is the case's session id
#   setup              optional, sourced in the scratch checkout after the base commit (branches, commits)
#   gh.stub            optional stub table, `<rc>\t<argv glob>\t<stdout>` per row (no Phase 0-2 step calls gh)
#   next-step.results  the directives that drive the driver (grammar below)
#   expected/          the scratch `.supervisor/` after the run, file for file (`session-logs/` again);
#                      empty directories are not compared (git keeps none)
#   expected.out       the printed instruction stream: per call `$ call: <args as written>`, its stdout,
#                      `= <exit code>`
#   Normalisation (both sides): ISO-8601 Z timestamps → <TS>, the scratch root → <ROOT>, 40-hex shas → <SHA>.
#   next-step.results grammar (one directive per line, `#` / blank skipped; `$SID $ROOT` expanded by eval):
#     call: <args…>          `bash supervisor-next-step.sh --session-id $SID <args…>` in the scratch root
#     expect: <do>|none      the last call printed {"do":"<do>",…} (none = it printed nothing)
#     expect-exit: <n>       the last call exited <n> (directly after its call:; without it a non-zero
#                            exit is a broken expectation)
#     env: <NAME>=<value> …  set (an empty value unsets) a driver env var for the calls below
#     gh: <rc>\t<glob>\t<out> one stub-table row appended to the case's scratch table
#     file: <path> <content> write <content> (one shell word) to <path> under the scratch root
#     sidecar: <json>        merge <json> into the driver's sidecar before the next call (a mid-run case)
#
# LEGS
#   G   GOLDEN PARITY (AC1). Every case in REQUIRED_CASES exists with source / input / next-step.results
#       / expected / expected.out; every case with a results file is driven and its `.supervisor/` tree
#       and instruction stream must equal expected/ and expected.out byte for byte (normalised).
#   W   STATE.MD UNTOUCHED (AC2). Across every golden case, `.supervisor/state.md` after the driver calls
#       alone is byte-identical to before (absent stays absent); every Phase Flag and decision the cases
#       reach was printed as a `context-keeper` spawn carrying the operation text.
#   I   IDEMPOTENCY. After a case ends on a spawn / ask, two calls with no --result re-print the
#       byte-identical instruction and leave `.supervisor/` byte-unchanged; the same --job entry re-prints.
#   Q   QUESTION GATE (AC5, Phase 1.5). The SUP-OVERLAP ask carries the question, the catalog's exact
#       labels (`lane-policy.sh catalog`), header "" (a human-only gate) and cant_ask
#       `preflight_overlap_detected`; under --non-interactive no call prints an ask; a `cant_ask` answer
#       takes the fail-closed park; a label outside the options exits 2 with nothing written.
#   S   MERGE SURFACE (AC9). The positive-grep file list equals the base commit's — read from
#       test-automate-next-step.sh's SURFACE_BASE, the one committed copy — and the driver contributes no
#       positive line.
#   R   NO REVIEWER (AC9). No instruction any leg printed spawns `code-reviewer`, and the driver's source
#       names no `code-reviewer` spawn.
#   B   BRANCHES the golden cases do not reach: the orchestrator route (a brief with no subtask table),
#       malformed reports / confirmations (exit 2, nothing written, the instruction re-prints), a run
#       that ended (exit 2), the abort / revise-scope answers.
#   D   DOC MIRROR. docs/result-schemas/supervisor-result.md §"supervisor next-step instruction" names
#       exactly the driver's `case` arms and its `what` values, and its `do` values are a subset of the
#       shared closed enum.
#   M   MUTATION CONTROLS — each mutant gated non-empty + differs from the driver + `bash -n` (its anchor
#       occurring exactly once); each must turn its leg red:
#         M2b the init step appends one line to state.md          ⇒ W (and G)
#         MD  one `case` arm the schema section does not name     ⇒ D
#         MS  one un-negated merge-command line (assembled from pieces here, so this file never holds the
#             positive literal on one line)                         ⇒ S
#         MR  the plan step spawns `code-reviewer`                 ⇒ R
#
# ENV: SN_CASES="<a> <b>" runs only those golden cases (G only); SN_SKIP_MUTANTS=1 skips M.
# Bash 3.2 / BSD-userland safe; everything lives under one work dir removed in a trap.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FIX="$HERE/fixtures/supervisor-golden"
DRIVER="$HERE/supervisor-next-step.sh"
DOC="$HERE/../docs/result-schemas/supervisor-result.md"
TAB="$(printf '\t')"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "FAIL: $1"; fail=$((fail + 1)); }

WORK="$(mktemp -d)" || { echo "FAIL: mktemp -d"; exit 1; }
WORK_P="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
INSTR="$WORK/instructions.log"; : > "$INSTR"

REQUIRED_CASES="init-flags-non-interactive init-flags-max-tokens acquire-job-move acquire-branch-reuse-tip-equal
acquire-branch-collision acquire-autonomous-state-json preflight-clear preflight-overlap-ask
preflight-overlap-non-interactive preflight-skip preflight-unverified plan-path-single-agent
plan-path-sequential plan-path-parallel"

GH_STUB_BODY='#!/usr/bin/env bash
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
REC_BODY='#!/usr/bin/env bash
printf "%s\n" "$*" >> "$SN_REC_LOG"
exit 0
'
GIT_ENV="GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=golden GIT_AUTHOR_EMAIL=golden@example.invalid GIT_COMMITTER_NAME=golden GIT_COMMITTER_EMAIL=golden@example.invalid GIT_AUTHOR_DATE=2026-10-17T12:00:00Z GIT_COMMITTER_DATE=2026-10-17T12:00:00Z"

norm() { # <file> — the normalised text on stdout
  local c
  c="$(cat "$1"; printf x)"; c="${c%x}"
  c="${c//"$CASE_ROOT_P"/<ROOT>}"; c="${c//"$CASE_ROOT"/<ROOT>}"
  c="${c//"$WORK_P"/<TMP>}"; c="${c//"$WORK"/<TMP>}"
  printf '%s' "$c" | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/<TS>/g; s/[0-9a-f]{40}/<SHA>/g'
}
# stage <src dir> <dst dir> — copy a fixture tree, `session-logs` ⇒ `logs`
stage() {
  mkdir -p "$2" && cp -R "$1/." "$2/" || return 1
  if [ -d "$2/session-logs" ]; then mv "$2/session-logs" "$2/logs" || return 1; fi
}

# new_scratch <case dir> — sets CASE_DIR CASE_ROOT CASE_ROOT_P CASE_BIN CASE_HOME CASE_GH CASE_SID
new_scratch() {
  local cd_="$1" cw n
  n="$(ls "$cd_/input/session-logs" 2>/dev/null | grep -c '\.jsonl$')"
  [ "$n" = 1 ] || return 1
  CASE_SID="$(ls "$cd_/input/session-logs" | sed -n 's/\.jsonl$//p')"
  cw="$(mktemp -d "$WORK/case.XXXXXX")" || return 1
  CASE_DIR="$cw"; CASE_ROOT="$cw/repo"; CASE_BIN="$cw/bin"; CASE_HOME="$cw/home"
  mkdir -p "$CASE_ROOT" "$CASE_BIN" "$CASE_HOME"
  CASE_ROOT_P="$(cd "$CASE_ROOT" && pwd -P)"
  printf '%s' "$GH_STUB_BODY" > "$CASE_BIN/gh"; chmod +x "$CASE_BIN/gh"
  printf '%s' "$REC_BODY" > "$CASE_BIN/rec"; chmod +x "$CASE_BIN/rec"
  : > "$cw/rec.log"
  ( export HOME="$CASE_HOME"; eval "export $GIT_ENV"
    git init -q --bare "$cw/origin.git" && git -C "$cw/origin.git" symbolic-ref HEAD refs/heads/main \
    && cd "$CASE_ROOT" && git init -q . && git symbolic-ref HEAD refs/heads/main \
    && printf '.supervisor/\n' > .gitignore && printf '# scratch\n' > README.md \
    && git add -A && git commit -q -m "base" && git remote add origin "$cw/origin.git" && git push -q origin main
  ) >/dev/null 2>&1 || return 1
  stage "$cd_/input" "$CASE_ROOT/.supervisor" || return 1
  if [ -f "$cd_/setup" ]; then
    ( cd "$CASE_ROOT" && export HOME="$CASE_HOME" && eval "export $GIT_ENV" && ROOT="$CASE_ROOT" SID="$CASE_SID" \
        && . "$cd_/setup" ) >"$cw/setup.log" 2>&1 || return 1
  fi
  CASE_GH="$cw/gh.table"
  if [ -f "$cd_/gh.stub" ]; then cp "$cd_/gh.stub" "$CASE_GH" || return 1; else : > "$CASE_GH"; fi
  if [ -s "$CASE_GH" ] && [ -n "$(tail -c 1 "$CASE_GH")" ]; then echo >> "$CASE_GH"; fi
  return 0
}

# in_case <seam env file> <command…> — run one command in the case's sandbox
in_case() {
  local seams="$1"; shift
  (
    cd "$CASE_ROOT" || exit 98
    unset LOOMWRIGHT_GH_BIN SUPERVISOR_NEXT_STEP_FROM SUPERVISOR_NEXT_STEP_GUARD_CMD
    export HOME="$CASE_HOME" PATH="$CASE_BIN:$PATH" GOLDEN_GH_TABLE="$CASE_GH" SN_REC_LOG="$CASE_DIR/rec.log"
    eval "export $GIT_ENV"
    export SUPERVISOR_NEXT_STEP_GUARD_CMD="$CASE_BIN/rec guard"
    export ROOT="$CASE_ROOT" SID="$CASE_SID"
    local n v
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      v="${n#*=}"; n="${n%%=*}"
      if [ -n "$v" ]; then export "$n=$v"; else unset "$n"; fi
    done < "$seams"
    "$@"
  ) < /dev/null
}

# drive <case dir> <driver> <results file> — runs the directives; writes $CASE_DIR/stream.out (the
# instruction stream), sets LAST_OUT / LAST_RC and DRIVE_ERR (non-empty on a broken expectation); every
# printed instruction is appended to $INSTR
drive() {
  local cd_="$1" drv="$2" rs="$3" line rest k=0 o e rc seams want got w nm pend="" sc
  local ROOT="$CASE_ROOT" SID="$CASE_SID"
  seams="$CASE_DIR/seams.env"; : > "$seams"; LAST_OUT=""; DRIVE_ERR=""; LAST_RC=0
  : > "$CASE_DIR/stream.out"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ""|"#"*) continue ;; esac
    rest="${line#*:}"; rest="${rest# }"
    case "$line" in "expect-exit: "*) ;; *) DRIVE_ERR="$DRIVE_ERR$pend"; pend="" ;; esac
    case "$line" in
      "expect-exit: "*)
        [ "$LAST_RC" = "$rest" ] || DRIVE_ERR="${DRIVE_ERR}call $k exit $LAST_RC, want $rest; "
        pend="" ;;
      "gh: "*) printf '%s\n' "$rest" >> "$CASE_GH" ;;
      "file: "*)
        eval "set -- $rest"
        if [ "$#" = 2 ]; then mkdir -p "$(dirname "$CASE_ROOT/$1")" && printf '%s' "$2" > "$CASE_ROOT/$1" || DRIVE_ERR="${DRIVE_ERR}file not written: $1; "
        else DRIVE_ERR="${DRIVE_ERR}file: wants <path> <content>: $rest; "; fi ;;
      "sidecar: "*)
        eval "set -- $rest"; sc="$CASE_ROOT/.supervisor/logs/$CASE_SID.supervisor-next-step.json"
        mkdir -p "$(dirname "$sc")"; [ -f "$sc" ] || printf '{}\n' > "$sc"
        jq -S --argjson x "$1" '. + $x' "$sc" > "$sc.t" 2>/dev/null && mv "$sc.t" "$sc" || DRIVE_ERR="${DRIVE_ERR}sidecar seed refused: $rest; " ;;
      "env: "*)
        eval "set -- $rest"
        for w in "$@"; do
          nm="${w%%=*}"; awk -v n="$nm" -F= '$1 != n' "$seams" > "$seams.t"; mv "$seams.t" "$seams"; printf '%s\n' "$w" >> "$seams"
        done ;;
      "call:"*)
        k=$((k + 1)); o="$CASE_DIR/call$k.out"; e="$CASE_DIR/call$k.err"
        eval "set -- $rest"
        in_case "$seams" bash "$drv" --session-id "$CASE_SID" "$@" > "$o" 2> "$e"
        rc=$?; LAST_RC=$rc
        LAST_OUT="$(cat "$o")"
        { printf '$ call: %s\n' "$rest"; cat "$o"; printf '= %s\n' "$rc"; } >> "$CASE_DIR/stream.out"
        [ "$rc" -eq 0 ] || pend="call $k exit $rc ($(head -n 3 "$e" | tr '\n' ' ')); "
        [ -s "$o" ] && sed "s|^|$(basename "$cd_")$TAB|" "$o" >> "$INSTR" ;;
      "expect: "*)
        want="$rest"
        if [ -z "$LAST_OUT" ]; then got=none; else got="$(printf '%s' "$LAST_OUT" | jq -r '.do // "?"' 2>/dev/null)"; fi
        [ "$got" = "$want" ] || DRIVE_ERR="${DRIVE_ERR}call $k printed do=$got, want $want; " ;;
      *) DRIVE_ERR="${DRIVE_ERR}bad directive: $line; " ;;
    esac
  done < "$rs"
  DRIVE_ERR="$DRIVE_ERR$pend"
}

# tree_files <dir> — the sorted relative file list (empty dirs dropped)
tree_files() { ( cd "$1" 2>/dev/null && find . -type f | sed 's|^\./||' | env LC_ALL=C sort ); }
# got_tree — the scratch .supervisor/ as a comparable tree (logs ⇒ session-logs), normalised, in $CASE_DIR/got
got_tree() {
  local f d
  rm -rf "$CASE_DIR/got"; mkdir -p "$CASE_DIR/got"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    d="$f"; case "$d" in logs/*) d="session-logs/${d#logs/}" ;; esac
    mkdir -p "$(dirname "$CASE_DIR/got/$d")"; norm "$CASE_ROOT/.supervisor/$f" > "$CASE_DIR/got/$d"
  done <<EOF
$(tree_files "$CASE_ROOT/.supervisor")
EOF
}
want_tree() { # <case dir>
  local f
  rm -rf "$CASE_DIR/want"; mkdir -p "$CASE_DIR/want"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    mkdir -p "$(dirname "$CASE_DIR/want/$f")"; norm "$1/expected/$f" > "$CASE_DIR/want/$f"
  done <<EOF
$(tree_files "$1/expected")
EOF
}

# golden_case <case> <driver> — 0 when the tree and the stream match (and every expectation held)
golden_case() {
  local c="$1" drv="$2" cd_="$FIX/$1"
  GC_DIFF=""
  [ -f "$cd_/next-step.results" ] || { GC_MSG="no next-step.results"; return 1; }
  new_scratch "$cd_" || { GC_MSG="scratch checkout not built (one input/session-logs/<sid>.jsonl? setup?)"; return 1; }
  if [ -f "$CASE_ROOT/.supervisor/state.md" ]; then cksum < "$CASE_ROOT/.supervisor/state.md" > "$CASE_DIR/state.before"
  else echo absent > "$CASE_DIR/state.before"; fi
  drive "$cd_" "$drv" "$cd_/next-step.results"
  if [ -f "$CASE_ROOT/.supervisor/state.md" ]; then cksum < "$CASE_ROOT/.supervisor/state.md" > "$CASE_DIR/state.after"
  else echo absent > "$CASE_DIR/state.after"; fi
  got_tree; want_tree "$cd_"
  if [ "$(tree_files "$CASE_DIR/got")" != "$(tree_files "$CASE_DIR/want")" ]; then
    GC_MSG="file list differs${DRIVE_ERR:+ [$DRIVE_ERR]}"
    GC_DIFF="$(diff <(tree_files "$CASE_DIR/want") <(tree_files "$CASE_DIR/got"))"; return 1
  fi
  if ! diff -r "$CASE_DIR/want" "$CASE_DIR/got" > "$CASE_DIR/tree.diff" 2>&1; then
    GC_MSG="tree differs${DRIVE_ERR:+ [$DRIVE_ERR]}"; GC_DIFF="$(head -n 40 "$CASE_DIR/tree.diff")"; return 1
  fi
  norm "$CASE_DIR/stream.out" > "$CASE_DIR/stream.norm"; norm "$cd_/expected.out" > "$CASE_DIR/stream.want"
  if ! cmp -s "$CASE_DIR/stream.want" "$CASE_DIR/stream.norm"; then
    GC_MSG="instruction stream differs${DRIVE_ERR:+ [$DRIVE_ERR]}"
    GC_DIFF="$(diff -u "$CASE_DIR/stream.want" "$CASE_DIR/stream.norm" | head -n 40)"; return 1
  fi
  [ -z "$DRIVE_ERR" ] || { GC_MSG="$DRIVE_ERR"; return 1; }
  return 0
}
state_untouched() { cmp -s "$CASE_DIR/state.before" "$CASE_DIR/state.after"; }

snapshot() { ( cd "$CASE_ROOT/.supervisor" && find . -type f | env LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done ); }
sn_call() { # <driver> <args…> — one call in the current case; sets NC_OUT NC_RC
  local drv="$1"; shift
  NC_OUT="$(in_case /dev/null bash "$drv" --session-id "$CASE_SID" "$@" 2>"$CASE_DIR/nc.err")"; NC_RC=$?
}

# --- the merge-surface list (AC9): the one committed copy is test-automate-next-step.sh's SURFACE_BASE
MC_PIECE_A="gh pr merge"; MC_PIECE_B="--squash"
SURFACE_BASE="$(awk '/^SURFACE_BASE="/ { s = 1; sub(/^SURFACE_BASE="/, "") } s { e = sub(/"$/, ""); print; if (e) exit }' "$HERE/test-automate-next-step.sh")"
surface_list() { # <driver file> — the positive grep's file list, the driver file standing in for the real one
  local drv="$1" pat="$MC_PIECE_A $MC_PIECE_B"
  {
    ( cd "$REPO" && grep -rn -- "$pat" loomwright/ | grep -viE "no |never |not " | cut -d: -f1 ) \
      | grep -vxF loomwright/scripts/supervisor-next-step.sh
    if grep -q . < <(grep -n -- "$pat" "$drv" | grep -viE "no |never |not "); then echo loomwright/scripts/supervisor-next-step.sh; fi
  } | env LC_ALL=C sort -u
}
leg_surface() {
  local got
  [ -n "$SURFACE_BASE" ] || { LEG_MSG="SURFACE_BASE not readable from test-automate-next-step.sh"; return 1; }
  got="$(surface_list "$1")"
  [ "$got" = "$SURFACE_BASE" ] || { LEG_MSG="surface list differs from base: $(printf '%s\n' "$got" | tr '\n' ' ')"; return 1; }
}
# leg_reviewer <driver> <instruction log> — no code-reviewer spawn, printed or in the source
leg_reviewer() {
  if cut -f2- "$2" | jq -e 'select(.what == "code-reviewer" or ((.agent // "") | test("code-reviewer")))' >/dev/null 2>&1; then
    LEG_MSG="an instruction spawns code-reviewer"; return 1
  fi
  if grep -nE 'sn_spawn [^ ]+ code-reviewer|what: "code-reviewer"|loomwright:code-reviewer' "$1" >/dev/null; then
    LEG_MSG="the driver source names a code-reviewer spawn"; return 1
  fi
  return 0
}
# leg_doc <driver> — the schema section names exactly the driver's arms and what values
leg_doc() {
  local arms docarms whats docwhats docdos
  arms="$(awk '/^sn_dispatch\(\) \{/,/^}/' "$1" | sed -n 's/^    \([a-z][a-z-]*\)) .*/\1/p' | env LC_ALL=C sort | tr '\n' ' ')"
  docarms="$(grep -F "one of the driver's \`case\` arms:" "$DOC" | sed 's/.*arms: //; s/).*//' | grep -oE '`[a-z-]+`' | tr -d '`' | env LC_ALL=C sort | tr '\n' ' ')"
  [ -n "$arms" ] && [ "$arms" = "$docarms" ] || { LEG_MSG="steps: driver '$arms' vs doc '$docarms'"; return 1; }
  whats="$(grep -oE 'sn_spawn ("\$1"|[a-z-]+) [a-z-]+ ' "$1" | awk '{print $3}' | env LC_ALL=C sort -u | tr '\n' ' ')"
  docwhats="$(grep -F '**`what` values (closed):**' "$DOC" | grep -oE '`[a-z-]+`' | tr -d '`' | grep -vx what | env LC_ALL=C sort -u | tr '\n' ' ')"
  [ -n "$whats" ] && [ "$whats" = "$docwhats" ] || { LEG_MSG="what: driver '$whats' vs doc '$docwhats'"; return 1; }
  docdos="$(grep -oE 'sn_emit (spawn|ask|park|done|[a-z]+) ' "$1" | awk '{print $2}' | env LC_ALL=C sort -u)"
  printf '%s\n' "$docdos" | grep -vxE 'spawn|ask|park|done' >/dev/null && { LEG_MSG="a do value outside the closed enum: $(echo $docdos)"; return 1; }
  return 0
}

# build_mutant <name> <anchor> <replacement|-append:<line>> — a driver copy beside symlinks to every other
# scripts/ entry; prints its path; gated: anchor once, non-empty, differs, bash -n
build_mutant() {
  local name="$1" anchor="$2" repl="$3" d c e
  d="$WORK/mut-$name"; mkdir -p "$d"
  for e in "$HERE"/*; do [ "$e" = "$DRIVER" ] || ln -s "$e" "$d/$(basename "$e")"; done
  case "$repl" in
    -append:*) cp "$DRIVER" "$d/supervisor-next-step.sh"; printf '%s\n' "${repl#-append:}" >> "$d/supervisor-next-step.sh" ;;
    *)
      c="$(grep -cF -- "$anchor" "$DRIVER")"
      [ "$c" = 1 ] || { echo "anchor occurs $c time(s)" >&2; return 1; }
      AN="$anchor" RE="$repl" awk 'BEGIN { a = ENVIRON["AN"]; r = ENVIRON["RE"] }
        { i = index($0, a); if (i > 0 && !d) { $0 = substr($0, 1, i - 1) r substr($0, i + length(a)); d = 1 } print }' \
        "$DRIVER" > "$d/supervisor-next-step.sh" ;;
  esac
  [ -s "$d/supervisor-next-step.sh" ] || { echo "mutant empty" >&2; return 1; }
  ! cmp -s "$DRIVER" "$d/supervisor-next-step.sh" || { echo "mutant does not differ" >&2; return 1; }
  bash -n "$d/supervisor-next-step.sh" 2>/dev/null || { echo "mutant fails bash -n" >&2; return 1; }
  echo "$d/supervisor-next-step.sh"
}

# ======================================================================================
echo "== test-supervisor-next-step.sh — driver: $DRIVER"
bash -n "$DRIVER" && ok "driver passes bash -n" || no "driver fails bash -n"

echo "-- G. golden parity (AC1)"
missing=""
for c in $REQUIRED_CASES; do
  for f in source next-step.results expected.out; do [ -f "$FIX/$c/$f" ] || missing="$missing $c/$f"; done
  for f in input expected; do [ -d "$FIX/$c/$f" ] || missing="$missing $c/$f/"; done
done
[ -z "$missing" ] && ok "every required case carries source, input/, next-step.results, expected/, expected.out" \
  || no "missing:$missing"
badsrc=""
for d in "$FIX"/*/; do
  c="$(basename "$d")"
  head -n 1 "$d/source" 2>/dev/null | grep -qE '^(run: [^ ]+|synthetic: .+)' || badsrc="$badsrc $c"
done
[ -z "$badsrc" ] && ok "every case's source names its real run (run: <id>) or says synthetic and why" || no "source:$badsrc"
sel="${SN_CASES:-}"
if [ -z "$sel" ]; then for d in "$FIX"/*/next-step.results; do sel="$sel $(basename "$(dirname "$d")")"; done; fi
W_BAD=""
for c in $sel; do
  GC_MSG=""; GC_DIFF=""
  if golden_case "$c" "$DRIVER"; then ok "$c: .supervisor/ tree and instruction stream match"
  else no "$c: $GC_MSG"; [ -n "$GC_DIFF" ] && printf '%s\n' "$GC_DIFF" | sed 's/^/    /'; fi
  state_untouched || W_BAD="$W_BAD $c"
done
[ -n "${SN_CASES:-}" ] && { echo "PASS: $pass FAIL: $fail"; [ "$fail" -eq 0 ]; exit $?; }

echo "-- W. state.md untouched by the driver (AC2)"
[ -z "$W_BAD" ] && ok "W: state.md byte-identical before/after the driver calls in every golden case" \
  || no "W: state.md changed in:$W_BAD"
nflag="$(cut -f2- "$INSTR" | jq -r 'select(.what == "context-keeper") | .ops[]' 2>/dev/null \
  | grep -cE 'operation: (set_flag|clear_flag|record_decision|initialize)' || true)"
ckbad="$(cut -f2- "$INSTR" | jq -c 'select(.what == "context-keeper") | select((.ops | type) != "array" or (.ops | length) == 0 or any(.ops[]; (startswith("Context-Keeper(operation: ") | not)))' 2>/dev/null)"
[ "$nflag" -gt 0 ] && [ -z "$ckbad" ] && ok "W: $nflag flag / decision / initialize op(s) were printed as context-keeper spawns carrying the operation text" \
  || no "W: context-keeper ops: $nflag, malformed: ${ckbad:-none}"
for want in 'clear_flag, key: "base_mismatch_detected"' 'clear_flag, key: "non_interactive"' 'set_flag, key: "non_interactive"' \
  'set_flag, key: "max_tokens"' 'decision: "preflight_clear"' 'decision: "preflight_skipped"'; do
  cut -f2- "$INSTR" | jq -r 'select(.what == "context-keeper") | .ops[]' 2>/dev/null | grep -qF -- "$want" \
    && ok "W: a context-keeper spawn carries $want" || no "W: no context-keeper spawn carries $want"
done

echo "-- I. idempotency"
for c in init-flags-non-interactive preflight-overlap-ask plan-path-parallel; do
  if golden_case "$c" "$DRIVER"; then
    last="$LAST_OUT"; s0="$(snapshot)"
    sn_call "$DRIVER"; o1="$NC_OUT"; r1=$NC_RC
    sn_call "$DRIVER"; o2="$NC_OUT"
    if [ "$r1" = 0 ] && [ "$o1" = "$last" ] && [ "$o2" = "$last" ] && [ "$s0" = "$(snapshot)" ]; then
      ok "I $c: two no-result calls re-print the instruction, nothing written"
    else no "I $c: re-print wrong (rc $r1; '$(printf '%s' "$o1" | head -c 120)')"; fi
  else no "I $c: case did not run: $GC_MSG"; fi
done
if golden_case init-flags-non-interactive "$DRIVER"; then
  last="$LAST_OUT"; s0="$(snapshot)"
  sn_call "$DRIVER" --job .supervisor/jobs/pending/2026-10-17-golden-init.md --non-interactive
  [ "$NC_RC" = 0 ] && [ "$NC_OUT" = "$last" ] && [ "$s0" = "$(snapshot)" ] \
    && ok "I: the same --job entry while its spawn is pending re-prints it, nothing written" \
    || no "I: --job re-entry did not re-print (rc $NC_RC)"
fi

echo "-- Q. the Phase 1.5 question gate (AC5)"
labels="$(bash "$HERE/lane-policy.sh" catalog | awk -F'\t' '$1 == "SUP-OVERLAP" { print $3 }')"
pol="$(bash "$HERE/lane-policy.sh" catalog | awk -F'\t' '$1 == "SUP-OVERLAP" { print $2 }')"
asks="$(grep "^preflight-overlap-ask$TAB" "$INSTR" | cut -f2- | jq -c 'select(.do == "ask")' 2>/dev/null)"
if [ -n "$asks" ] && [ "$pol" = human-only ] && printf '%s\n' "$asks" | jq -e --arg l "$labels" \
     '.gate == "SUP-OVERLAP" and (.question | type) == "string" and (.question | test("PR #")) and .header == ""
      and .options == ($l | split("|")) and .cant_ask == "preflight_overlap_detected"
      and .questions[0].options == .options' >/dev/null 2>&1; then
  ok "Q: the SUP-OVERLAP ask carries the citing question, the catalog labels ($labels), header \"\" and cant_ask preflight_overlap_detected"
else no "Q: SUP-OVERLAP ask shape wrong: $(printf '%s' "$asks" | head -c 300)"; fi
if grep "^preflight-overlap-non-interactive$TAB" "$INSTR" | cut -f2- | jq -e 'select(.do == "ask")' >/dev/null 2>&1; then
  no "Q: --non-interactive printed an ask"
else ok "Q: under --non-interactive the overlap prints the named park, never an ask"; fi
# a cant_ask answer and an off-list label
if golden_case preflight-overlap-ask "$DRIVER"; then
  s0="$(snapshot)"
  sn_call "$DRIVER" --result '{"answers":["proceed anyway"]}'; r_bad=$NC_RC
  s1="$(snapshot)"
  sn_call "$DRIVER" --result '{"cant_ask":true}'
  if [ "$r_bad" = 2 ] && [ "$s0" = "$s1" ] && [ "$NC_RC" = 0 ] \
     && printf '%s' "$NC_OUT" | jq -e '.do == "park" and .status == "failed" and .error == "preflight_overlap_detected"' >/dev/null 2>&1 \
     && [ -f "$CASE_ROOT/.supervisor/jobs/failed/2026-10-17-golden-overlap.md" ]; then
    ok "Q: an off-list label exits 2 with nothing written; cant_ask takes the fail-closed park (job → failed/)"
  else no "Q: answer handling wrong (off-list rc $r_bad; cant_ask: $(printf '%s' "$NC_OUT" | head -c 200))"; fi
fi

echo "-- S. merge surface (AC9)"
LEG_MSG=""
if leg_surface "$DRIVER"; then ok "S: the positive-grep file list equals the base commit's (driver absent from it)"; else no "S: $LEG_MSG"; fi

echo "-- B. branches the golden cases do not reach"
# B1 — a brief with no subtask table: the orchestrator spawn, then path selection from its report
if new_scratch "$FIX/plan-path-parallel"; then
  printf '# Supervisor Job: No table\n\n## Acceptance Criteria\n- [ ] one\n- [ ] two\n\n## Subtask Structure\n\nsee the orchestrator\n' \
    > "$CASE_ROOT/.supervisor/jobs/pending/2026-10-17-golden-notable.md"
  sn_call "$DRIVER" --job .supervisor/jobs/pending/2026-10-17-golden-notable.md --skip-preflight-sync --cheap
  sn_call "$DRIVER" --result '{"confirmed":true}'
  sn_call "$DRIVER" --result '{"confirmed":true}'; o_plan="$NC_OUT"
  s0="$(snapshot)"
  sn_call "$DRIVER" --result '{"subtasks":[{"id":"a"},{"id":"a"}]}'; r_dup=$NC_RC
  s1="$(snapshot)"
  sn_call "$DRIVER" --result '{"subtasks":[{"id":"a","title":"A"},{"id":"b","title":"B"}]}'
  if printf '%s' "$o_plan" | jq -e '.do == "spawn" and .what == "orchestrator" and .model == "sonnet" and .criteria == "2 acceptance criteria — read the brief'"'"'s ## Acceptance Criteria"' >/dev/null 2>&1 \
     && [ "$r_dup" = 2 ] && [ "$s0" = "$s1" ] \
     && printf '%s' "$NC_OUT" | jq -e '.what == "execute-manager" and .plan_source == "orchestrator" and .subtasks == ["a","b"] and .model == "sonnet"' >/dev/null 2>&1; then
    ok "B1: no subtask table ⇒ the orchestrator spawn (--cheap ⇒ sonnet); a duplicate id exits 2, nothing written; its plan ⇒ the parallel spawn"
  else no "B1: orchestrator route wrong (plan: $(printf '%s' "$o_plan" | head -c 160); dup rc $r_dup; then: $(printf '%s' "$NC_OUT" | head -c 160))"; fi
else no "B1: scratch not built"; fi
# B2 — a malformed confirmation / report exits 2, nothing written, and the instruction re-prints
if new_scratch "$FIX/preflight-clear"; then
  sn_call "$DRIVER" --job .supervisor/jobs/pending/2026-10-17-next-step-supervisor.md --branch feature/as11-next-step-supervisor
  s0="$(snapshot)"; sn_call "$DRIVER" --result '{"confirmed":"yes"}'; r1=$NC_RC; s1="$(snapshot)"
  sn_call "$DRIVER" --result '{"confirmed":true}'; pf="$NC_OUT"
  s2="$(snapshot)"
  sn_call "$DRIVER" --result '{"classification":"clear","version":"1","base_tip":"abcdef1"}'; r2=$NC_RC
  sn_call "$DRIVER" --result '{"classification":"CLEAR","version":"1"}'; r3=$NC_RC
  sn_call "$DRIVER" --result '{"classification":"OVERLAP"}'; r4=$NC_RC
  sn_call "$DRIVER" --result "$(jq -cn '{classification: "CLEAR", version: "1\n2", base_tip: "abcdef1"}')"; r5=$NC_RC
  s3="$(snapshot)"; sn_call "$DRIVER"
  if [ "$r1" = 2 ] && [ "$s0" = "$s1" ] && [ "$r2" = 2 ] && [ "$r3" = 2 ] && [ "$r4" = 2 ] && [ "$r5" = 2 ] \
     && [ "$s2" = "$s3" ] && [ "$NC_OUT" = "$pf" ]; then
    ok "B2: a non-true confirmation, a lowercase / sha-less CLEAR, a citation-less OVERLAP and a multi-line field exit 2; nothing written; the spawn re-prints"
  else no "B2: refusals wrong (rc $r1 $r2 $r3 $r4 $r5)"; fi
  # B3 — abort: the record, then the failed park with the job in failed/; then the run has ended
  sn_call "$DRIVER" --result '{"classification":"SUPERSEDED","citations":"abc1234 landed it; a.md"}'; o_ask="$NC_OUT"
  sn_call "$DRIVER" --result '{"answers":["abort"]}'; o_rec="$NC_OUT"
  sn_call "$DRIVER" --result '{"confirmed":true}'; o_park="$NC_OUT"
  sn_call "$DRIVER" --result '{"confirmed":true}'; r_end=$NC_RC
  if printf '%s' "$o_ask" | jq -e '.do == "ask"' >/dev/null 2>&1 \
     && printf '%s' "$o_rec" | jq -e '.ops == ["Context-Keeper(operation: record_decision, phase: PRE_FLIGHT_SYNC, decision: \"preflight_abort\", rationale: \"SUPERSEDED — abc1234 landed it; a.md\")"]' >/dev/null 2>&1 \
     && printf '%s' "$o_park" | jq -e '.status == "failed" and .error == "preflight_overlap_detected: SUPERSEDED — abc1234 landed it; a.md" and (.job | startswith(".supervisor/jobs/failed/"))' >/dev/null 2>&1 \
     && [ "$r_end" = 2 ]; then
    ok "B3: abort ⇒ preflight_abort record ⇒ the failed park (job → failed/); a later --result exits 2 (run_ended)"
  else no "B3: abort route wrong ($(printf '%s' "$o_park" | head -c 200); end rc $r_end)"; fi
else no "B2: scratch not built"; fi
# B4 — revise-scope: the record, then the checkpoint park; the job stays in in-progress/, the branch is kept
if new_scratch "$FIX/preflight-overlap-ask"; then
  sn_call "$DRIVER" --job .supervisor/jobs/pending/2026-10-17-golden-overlap.md
  sn_call "$DRIVER" --result '{"confirmed":true}'
  sn_call "$DRIVER" --result '{"classification":"OVERLAP","citations":"PR #41 touches docs/a.md"}'
  sn_call "$DRIVER" --result '{"answers":["revise-scope"]}'; o_rec="$NC_OUT"
  sn_call "$DRIVER" --result '{"confirmed":true}'
  if printf '%s' "$o_rec" | jq -e '.ops[0] | test("decision: \"preflight_revise_scope\"")' >/dev/null 2>&1 \
     && printf '%s' "$NC_OUT" | jq -e '.do == "park" and .status == "checkpoint" and (has("error") | not) and .preflight_sync == null' >/dev/null 2>&1 \
     && [ -f "$CASE_ROOT/.supervisor/jobs/in-progress/2026-10-17-golden-overlap.md" ] \
     && git -C "$CASE_ROOT" rev-parse --verify --quiet refs/heads/feature/golden-overlap >/dev/null; then
    ok "B4: revise-scope ⇒ preflight_revise_scope record ⇒ the checkpoint park; job stays in-progress, branch kept"
  else no "B4: revise route wrong ($(printf '%s' "$NC_OUT" | head -c 200))"; fi
else no "B4: scratch not built"; fi
# B5 — usage refusals: no session id, a malformed one, --job with --result, a flag without --job
if new_scratch "$FIX/init-flags-max-tokens"; then
  r1="$(in_case /dev/null bash "$DRIVER" --job x.md >/dev/null 2>&1; echo $?)"
  r2="$(in_case /dev/null bash "$DRIVER" --session-id 'a b' --job x.md >/dev/null 2>&1; echo $?)"
  r3="$(in_case /dev/null bash "$DRIVER" --session-id s --job x.md --result '{}' >/dev/null 2>&1; echo $?)"
  r4="$(in_case /dev/null bash "$DRIVER" --session-id s --cheap >/dev/null 2>&1; echo $?)"
  r5="$(in_case /dev/null bash "$DRIVER" --session-id s --job .supervisor/jobs/pending/nope.md >/dev/null 2>&1; echo $?)"
  [ "$r1$r2$r3$r4$r5" = 22222 ] && [ ! -e "$CASE_ROOT/.supervisor/logs/s.supervisor-next-step.json" ] \
    && ok "B5: session_id_missing / _malformed, --job with --result, a flag without --job, job_not_found ⇒ exit 2, no sidecar" \
    || no "B5: usage refusals exit $r1 $r2 $r3 $r4 $r5"
fi
# B6 — an absolute --job path (the logical scratch path: under macOS's /var → /private/var symlink it differs
# from the physical root) still moves the brief and is reported repo-relative; a silent guard failure is named
if new_scratch "$FIX/preflight-skip"; then
  printf '%s\n' 'SUPERVISOR_NEXT_STEP_GUARD_CMD=false' > "$CASE_DIR/b6.env"
  o="$(in_case "$CASE_DIR/b6.env" bash "$DRIVER" --session-id "$CASE_SID" --job "$CASE_ROOT/.supervisor/jobs/pending/2026-10-17-golden-skip.md" 2>/dev/null)"
  if printf '%s' "$o" | jq -e '.job == ".supervisor/jobs/in-progress/2026-10-17-golden-skip.md"
       and any(.ops[]; test("decision: \"guard_armed: failed: exit 1\""))' >/dev/null 2>&1 \
     && [ -f "$CASE_ROOT/.supervisor/jobs/in-progress/2026-10-17-golden-skip.md" ]; then
    ok "B6: an absolute --job path is moved and reported repo-relative; a silent guard failure records 'failed: exit 1'"
  else no "B6: absolute job / guard failure wrong: $(printf '%s' "$o" | head -c 300)"; fi
else no "B6: scratch not built"; fi

echo "-- R. no per-subtask reviewer (AC9)"
LEG_MSG=""
if leg_reviewer "$DRIVER" "$INSTR"; then ok "R: no printed instruction and no driver line spawns code-reviewer"; else no "R: $LEG_MSG"; fi

echo "-- D. the schema doc mirrors the driver (closed lists)"
LEG_MSG=""
grep -qF '### supervisor next-step instruction' "$DOC" && ok "D: supervisor-result.md carries the 'supervisor next-step instruction' section" \
  || no "D: no '### supervisor next-step instruction' heading in $DOC"
if leg_doc "$DRIVER"; then ok "D: the doc's step and what lists equal the driver's case arms and spawns; do ⊆ spawn|ask|park|done"
else no "D: $LEG_MSG"; fi

if [ "${SN_SKIP_MUTANTS:-}" != 1 ]; then
  echo "-- M. mutation controls"
  # M2b — the init step appends one line to state.md ⇒ W red
  if m="$(build_mutant 2b 'sn_init() {' 'sn_init() { printf '"'"'%s\n'"'"' "- mutant" >> "$ROOT/.supervisor/state.md";')"; then
    mw=""; for c in init-flags-non-interactive acquire-job-move; do golden_case "$c" "$m" >/dev/null 2>&1; state_untouched || mw="$mw $c"; done
    [ -n "$mw" ] && ok "M2b: a driver writing state.md ⇒ W red ($mw)" || no "M2b: W stayed green with the driver writing state.md"
  else no "M2b: mutant not built"; fi
  # MD — one case arm the doc does not name ⇒ D red
  if m="$(build_mutant D '    execute) sn_execute ;;' '    execute) sn_execute ;;
    mutant-arm) sn_execute ;;')"; then
    LEG_MSG=""; if leg_doc "$m"; then no "MD: D stayed green with an undocumented arm"; else ok "MD: an undocumented case arm ⇒ D red ($LEG_MSG)"; fi
  else no "MD: mutant not built"; fi
  # MS — an un-negated merge-command line (the literal assembled here from pieces) ⇒ S red
  if m="$(build_mutant S - "-append:$(printf '%s %s "$PR"' "$MC_PIECE_A" "$MC_PIECE_B")")"; then
    LEG_MSG=""; if leg_surface "$m"; then no "MS: S stayed green with an unguarded merge line"; else ok "MS: an unguarded merge-command line ⇒ S red"; fi
  else no "MS: mutant not built"; fi
  # MR — the plan step spawns code-reviewer instead of orchestrator ⇒ R red
  if m="$(build_mutant R 'sn_spawn plan orchestrator plan-result' 'sn_spawn plan code-reviewer plan-result')"; then
    LEG_MSG=""; if leg_reviewer "$m" "$INSTR"; then no "MR: R stayed green with a code-reviewer spawn"; else ok "MR: a code-reviewer spawn ⇒ R red ($LEG_MSG)"; fi
  else no "MR: mutant not built"; fi
fi

echo "PASS: $pass FAIL: $fail"
[ "$fail" -eq 0 ]
