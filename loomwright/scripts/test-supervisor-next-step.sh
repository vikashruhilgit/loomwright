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
#   gh.stub            optional stub table, `<rc>\t<argv glob>\t<stdout>` per row, first match wins; an rc
#                      written `<rc>@<n>` answers only its first n matches, then the row is skipped (a gh
#                      that fails twice and then answers); every matched call is logged beside the table
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
#     run: <shell…>          run a shell line in the scratch checkout (the model's own git work between
#                            two calls — the merges, a commit); a non-zero exit is a broken expectation
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
#       labels (`lane-policy.sh catalog`), header = its code (a human-only gate too) and cant_ask
#       `preflight_overlap_detected`; under --non-interactive no call prints an ask; a `cant_ask` answer
#       takes the fail-closed park; a label outside the options exits 2 with nothing written.
#   S   MERGE SURFACE (AC9). The positive-grep file list equals the base commit's — read from
#       test-automate-next-step.sh's SURFACE_BASE, the one committed copy — and the driver contributes no
#       positive line.
#   R   NO REVIEWER (AC9). No instruction any leg printed spawns `code-reviewer`, and the driver's source
#       names no `code-reviewer` spawn.
#   B   BRANCHES the golden cases do not reach: the orchestrator route (a brief with no subtask table),
#       malformed reports / confirmations (exit 2, nothing written, the instruction re-prints), a run
#       that ended (exit 2), the abort / revise-scope answers; Phase 3 (B7–B11: malformed blocks, the
#       lane / gap adjudications both ways, Option C's reason per kind, a budget checkpoint), FINALIZE
#       (B12–B15: pre-merge points 2–4 and a missing worktree, point 5's answers / --non-interactive /
#       --skip-children-check, a conflict, a refused re-fold, write-marker refusals), the inline paths
#       (B16), every step-6.5 branch (B17), the step-4 .gitignore bootstrap under `/setup memory`'s
#       managed block (B18), and the base through resolve-base-branch.sh (B20: origin/HEAD →
#       development publishes `--base development`; an invalid brief `Base Branch:` / an unresolvable
#       base stops init with the resolver's status token, the brief unmoved).
#   P   PUBLISH ORDER (AC3). Every publish spawn a golden case prints is printed with the finalize-gate
#       marker on disk naming HEAD; guard-finalize-publish.sh and check-children-settled.sh are
#       byte-unchanged since the merge-base with origin/main (skipped, uncounted, without that ref).
#   A   QUESTION GATES (AC4, AC5). The SUP-ADJ-GAP / SUP-ADJ-LANE / SUP-CHILDREN / SUP-GH-RETRY asks carry
#       the catalog labels, the catalog header only for an allowed gate, and their named can't-ask status;
#       an interactive adjudication never picks; a first gh failure is retried exactly once.
#   K   BRACE EXPANSION OFF. The driver carries `set +B` (bash 3.2 brace-expands the source of a "$(…)"
#       argument, splitting its jq programs); where /bin/bash is 3.x, a spawn driven under it is well-formed.
#   V   VALIDATION 3. validation-3-drive (also a golden case) ends at the verified hand-over with the
#       guard's deny-then-allow and the real merges / push holding; SN_V3_PRINT=1 prints `do step` per line.
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
#         M2a the publish spawn printed before write-marker        ⇒ P
#         M2c no step-6.5 retry (the first gh failure sets the flag) ⇒ A4 (and the gh-retry case)
#         M2d an interactive adjudication auto-picks option A      ⇒ A5
#         MB  brace expansion left on (`set -B`)                    ⇒ K
#         MG  step 4 back on the exact-line .gitignore test          ⇒ B18
#         MBA init's resolver call replaced by the literal `main`    ⇒ B20 (development publish)
#         MBB the resolver call drops `--brief`                     ⇒ B20 (invalid brief stop)
#
# ENV: SN_CASES="<a> <b>" runs only those golden cases (G only); SN_SKIP_MUTANTS=1 skips M.
#   SN_WRITE_EXPECTED=1 (authoring only, honoured only together with SN_CASES): each selected case's
#   normalised tree and stream are written over its expected/ and expected.out, and the case still
#   reports its pre-write verdict — review the result with `git diff` before committing it.
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
plan-path-sequential plan-path-parallel execute-result-complete execute-result-partial execute-result-all-failed
execute-adjudication-ask execute-adjudication-non-interactive execute-manager-crash finalize-premerge-gate-fail
finalize-children-unsettled finalize-marker-written finalize-pr-base-verified finalize-pr-base-mismatch
finalize-pr-base-gh-retry"

GH_STUB_BODY='#!/usr/bin/env bash
all="$*"; n=0
if [ -n "${GOLDEN_GH_TABLE:-}" ] && [ -f "$GOLDEN_GH_TABLE" ]; then
  while IFS="	" read -r rc pat out || [ -n "$rc" ]; do
    n=$((n + 1))
    case "$rc" in ""|"#"*) continue ;; esac
    # shellcheck disable=SC2254
    case "$all" in $pat) ;; *) continue ;; esac
    case "$rc" in *@*)
      c="$GOLDEN_GH_TABLE.used.$n"; u="$(cat "$c" 2>/dev/null || echo 0)"
      [ "$u" -lt "${rc#*@}" ] || continue
      echo "$((u + 1))" > "$c"; rc="${rc%@*}" ;;
    esac
    printf "%s\n" "$all" >> "$GOLDEN_GH_TABLE.calls"
    [ -n "$out" ] && printf "%s\n" "$out"; exit "$rc"
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
    unset LOOMWRIGHT_GH_BIN SUPERVISOR_NEXT_STEP_FROM SUPERVISOR_NEXT_STEP_GUARD_CMD LOOMWRIGHT_HOST_MODE CLAUDE_PROJECT_DIR
    export HOME="$CASE_HOME" PATH="$CASE_BIN:$PATH" GOLDEN_GH_TABLE="$CASE_GH" SN_REC_LOG="$CASE_DIR/rec.log"
    export SUPERVISOR_NEXT_STEP_RETRY_SECONDS=0
    eval "export $GIT_ENV"
    export SUPERVISOR_NEXT_STEP_GUARD_CMD="$CASE_BIN/rec guard"
    export ROOT="$CASE_ROOT" SID="$CASE_SID" SN_SCRIPTS="$HERE"
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
# printed instruction is appended to $INSTR. After every call that printed the publish spawn
# (`what: finalize-publish`) the finalize-gate marker is probed: it must exist and name HEAD at that
# moment (PUB_SEEN / PUB_BAD — the AC3 order leg)
drive() {
  local cd_="$1" drv="$2" rs="$3" line rest k=0 o e rc seams want got w nm pend="" sc mk
  local ROOT="$CASE_ROOT" SID="$CASE_SID"
  seams="$CASE_DIR/seams.env"; : > "$seams"; LAST_OUT=""; DRIVE_ERR=""; LAST_RC=0; PUB_SEEN=0; PUB_BAD=""
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
        [ -s "$o" ] && sed "s|^|$(basename "$cd_")$TAB|" "$o" >> "$INSTR"
        if printf '%s' "$LAST_OUT" | jq -e '.what == "finalize-publish"' >/dev/null 2>&1; then
          PUB_SEEN=$((PUB_SEEN + 1)); mk="$CASE_ROOT/.supervisor/logs/$CASE_SID.finalize-gate"
          [ -f "$mk" ] && [ "$(jq -r '.head_sha // empty' "$mk" 2>/dev/null)" = "$(git -C "$CASE_ROOT" rev-parse HEAD 2>/dev/null)" ] \
            || PUB_BAD="${PUB_BAD}call $k printed the publish spawn with no finalize-gate marker naming HEAD; "
        fi ;;
      "run: "*)
        in_case "$seams" bash -c "$rest" >> "$CASE_DIR/run.log" 2>&1 || DRIVE_ERR="${DRIVE_ERR}run failed: $rest; " ;;
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
SN_CALL_SEAMS=/dev/null   # the seam env file sn_call hands to in_case (a case may point it at its own)
sn_call() { # <driver> <args…> — one call in the current case; sets NC_OUT NC_RC
  local drv="$1"; shift
  NC_OUT="$(in_case "$SN_CALL_SEAMS" bash "$drv" --session-id "$CASE_SID" "$@" 2>"$CASE_DIR/nc.err")"; NC_RC=$?
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

# leg_scripts_unchanged — AC3: the driver CALLS guard-finalize-publish.sh / check-children-settled.sh and
# never edits them: a branch that changes the driver changes neither since its merge-base with
# origin/main. Scoped to driver changes (#717): unscoped, the leg refused every later fix to the gate
# itself, which the driver does not own. Skipped, uncounted, when origin/main is absent (a shallow or
# offline clone) or the branch does not touch supervisor-next-step.sh.
leg_scripts_unchanged() {
  local mb f
  mb="$(git -C "$REPO" merge-base HEAD origin/main 2>/dev/null)"
  if [ -z "$mb" ]; then echo "  skip: origin/main not resolvable — the scripts-unchanged leg did not run"; return 0; fi
  if git -C "$REPO" diff --quiet "$mb" -- loomwright/scripts/supervisor-next-step.sh; then
    echo "  skip: the driver is unchanged on this branch — the scripts-unchanged leg did not run"; return 0
  fi
  for f in loomwright/scripts/guard-finalize-publish.sh loomwright/scripts/check-children-settled.sh; do
    if git -C "$REPO" diff --quiet "$mb" -- "$f"; then ok "AC3: $f byte-unchanged since the merge-base ($(printf '%s' "$mb" | cut -c1-7))"
    else no "AC3: $f changed on this branch — the driver must call it, never edit it"; fi
  done
}
# payload <case> <n> — the n-th `call: --result '<json>'` payload of a case's results file
payload() {
  awk -v n="$2" 'index($0, "call: --result '"'"'") == 1 { k++; if (k == n) { s = substr($0, 17); print substr(s, 1, length(s) - 1); exit } }' \
    "$FIX/$1/next-step.results" | sed "s/'\\\\''/'/g"
}
B_DRV="$DRIVER"
# b_exec <case> [flags…] — a scratch from <case>'s inputs, driven (--skip-preflight-sync) to its Phase 3 spawn
b_exec() {
  local c="$1"; shift
  new_scratch "$FIX/$c" || return 1
  sn_call "$B_DRV" --job ".supervisor/jobs/pending/$(ls "$FIX/$c/input/jobs/pending")" --skip-preflight-sync "$@"
  sn_call "$B_DRV" --result '{"confirmed":true}'
  sn_call "$B_DRV" --result '{"confirmed":true}'
  printf '%s' "$NC_OUT" | jq -e '.step == "execute" and .do == "spawn"' >/dev/null 2>&1
}
# b_fin <case> [flags…] — a Single-Agent finalize scratch driven to its publish spawn (the real commit included)
b_fin() {
  local c="$1"; shift
  b_exec "$c" "$@" || return 1
  in_case /dev/null bash -c 'printf "driver\n" > driver.sh' || return 1
  sn_call "$B_DRV" --result '{"subtask":"1","agent_id":"ac394bd015ea3ff94","status":"completed","gates":"passed"}'
  in_case /dev/null bash -c 'git add -A && git commit -qm "feat: golden"' || return 1
  sn_call "$B_DRV" --result '{"merged":[],"conflict":null,"refold":"ok"}'
  printf '%s' "$NC_OUT" | jq -e '.what == "finalize-publish"' >/dev/null 2>&1
}
jqo() { printf '%s' "$NC_OUT" | jq -e "$@" >/dev/null 2>&1; }   # the last call's instruction matches
catalog_labels() { bash "$HERE/lane-policy.sh" catalog | awk -F'\t' -v c="$1" '$1 == c { print $3 }'; }
# leg_adj_ask <driver> — AC5 / Validation 2d: an interactive adjudication prints the SUP-ADJ-GAP ask with
# the catalog labels, header = the code and the named can't-ask status — never a pick
leg_adj_ask() {
  B_DRV="$1"
  b_exec execute-adjudication-ask || { B_DRV="$DRIVER"; LEG_MSG="scratch not built"; return 1; }
  sn_call "$1" --result "$(payload execute-adjudication-ask 3)"
  B_DRV="$DRIVER"
  jqo --arg l "$(catalog_labels SUP-ADJ-GAP)" '.do == "ask" and .gate == "SUP-ADJ-GAP" and .header == "SUP-ADJ-GAP"
      and .options == ($l | split("|")) and .cant_ask == "adjudication_required_non_interactive"
      and (.question | test("api.md:ApiClient")) and (has("choice") | not)' \
    || { LEG_MSG="an interactive adjudication printed: $(printf '%s' "$NC_OUT" | head -c 200)"; return 1; }
}
# leg_retry_once <driver> — AC4 / Validation 2c: a first gh failure is retried ONCE; the retry's answer
# decides (verified, no ask, no flag) and gh was called exactly twice
leg_retry_once() {
  B_DRV="$1"
  b_fin finalize-pr-base-verified || { B_DRV="$DRIVER"; LEG_MSG="scratch not built"; return 1; }
  printf '1@1\tpr view *\t\n0\tpr view *\tmain\n' > "$CASE_GH"; rm -f "$CASE_GH.calls"
  sn_call "$1" --result '{"pr_url":"https://github.com/golden/repo/pull/12"}'
  B_DRV="$DRIVER"
  jqo '.do == "done" and .step == "handover" and .base_verify == "verified" and .base_mismatch_detected == false' \
    && [ "$(wc -l < "$CASE_GH.calls" | tr -d ' ')" = 2 ] \
    || { LEG_MSG="after one gh failure: $(printf '%s' "$NC_OUT" | head -c 200) (gh calls: $(wc -l < "$CASE_GH.calls" 2>/dev/null | tr -d ' '))"; return 1; }
}

# leg_brace_off <driver> — bash 3.2 (macOS /bin/bash) brace-expands the source of a "$(…)" argument, which
# splits the driver's jq programs: the driver must run with brace expansion off. Static: the `set +B` line.
# Dynamic, where /bin/bash is 3.x: the orchestrator spawn (a jq object built inside a "$(…)" argument)
# driven under /bin/bash is one well-formed instruction
leg_brace_off() {
  local o
  grep -qx 'set +B' "$1" || { LEG_MSG="the driver has no top-level 'set +B' line"; return 1; }
  case "$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)" in 3) ;; *) return 0 ;; esac
  new_scratch "$FIX/plan-path-parallel" || { LEG_MSG="scratch not built"; return 1; }
  printf '# Supervisor Job: No table\n\n## Acceptance Criteria\n- [ ] one\n\n## Subtask Structure\n\nnone\n' \
    > "$CASE_ROOT/.supervisor/jobs/pending/2026-10-17-golden-notable.md"
  in_case /dev/null /bin/bash "$1" --session-id "$CASE_SID" --job .supervisor/jobs/pending/2026-10-17-golden-notable.md --skip-preflight-sync >/dev/null 2>&1
  in_case /dev/null /bin/bash "$1" --session-id "$CASE_SID" --result '{"confirmed":true}' >/dev/null 2>&1
  o="$(in_case /dev/null /bin/bash "$1" --session-id "$CASE_SID" --result '{"confirmed":true}' 2>/dev/null)"
  printf '%s' "$o" | jq -e '.what == "orchestrator" and .brief_note == "read only the sections you need"' >/dev/null 2>&1 \
    || { LEG_MSG="under /bin/bash 3.x the orchestrator spawn came out as: $(printf '%s' "$o" | head -c 160)"; return 1; }
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
  grep -qE '^(run: [^ ]+|synthetic: .+)' < <(head -n 1 "$d/source" 2>/dev/null) || badsrc="$badsrc $c"
done
[ -z "$badsrc" ] && ok "every case's source names its real run (run: <id>) or says synthetic and why" || no "source:$badsrc"
sel="${SN_CASES:-}"
if [ -z "$sel" ]; then for d in "$FIX"/*/next-step.results; do sel="$sel $(basename "$(dirname "$d")")"; done; fi
W_BAD=""; P_SEEN=0; P_BAD=""
for c in $sel; do
  GC_MSG=""; GC_DIFF=""
  if golden_case "$c" "$DRIVER"; then ok "$c: .supervisor/ tree and instruction stream match"
  else no "$c: $GC_MSG"; [ -n "$GC_DIFF" ] && printf '%s\n' "$GC_DIFF" | sed 's/^/    /'; fi
  if [ -n "${SN_CASES:-}" ] && [ "${SN_WRITE_EXPECTED:-}" = 1 ] && [ -d "$CASE_DIR/got" ]; then
    rm -rf "$FIX/$c/expected" && cp -R "$CASE_DIR/got" "$FIX/$c/expected" && norm "$CASE_DIR/stream.out" > "$FIX/$c/expected.out" \
      && echo "  wrote: $c/expected/ and $c/expected.out" || no "$c: SN_WRITE_EXPECTED could not write"
  fi
  state_untouched || W_BAD="$W_BAD $c"
  P_SEEN=$((P_SEEN + PUB_SEEN)); [ -z "$PUB_BAD" ] || P_BAD="$P_BAD $c: $PUB_BAD"
done
[ -n "${SN_CASES:-}" ] && { echo "PASS: $pass FAIL: $fail"; [ "$fail" -eq 0 ]; exit $?; }

echo "-- W. state.md untouched by the driver (AC2)"
[ -z "$W_BAD" ] && ok "W: state.md byte-identical before/after the driver calls in every golden case" \
  || no "W: state.md changed in:$W_BAD"
nflag="$(cut -f2- "$INSTR" | jq -r 'select(.what == "context-keeper") | .ops[]' 2>/dev/null \
  | grep -cE 'operation: (set_flag|clear_flag|record_decision|record_error|initialize)' || true)"
ckbad="$(cut -f2- "$INSTR" | jq -c 'select(.what == "context-keeper") | select((.ops | type) != "array" or (.ops | length) == 0 or any(.ops[]; (startswith("Context-Keeper(operation: ") | not)))' 2>/dev/null)"
[ "$nflag" -gt 0 ] && [ -z "$ckbad" ] && ok "W: $nflag flag / decision / initialize op(s) were printed as context-keeper spawns carrying the operation text" \
  || no "W: context-keeper ops: $nflag, malformed: ${ckbad:-none}"
# the ops are read ONCE into a variable: `jq … | grep -q` under pipefail SIGPIPEs jq on an early match
ckops="$(cut -f2- "$INSTR" | jq -r 'select(.what == "context-keeper") | .ops[]' 2>/dev/null)"
for want in 'clear_flag, key: "base_mismatch_detected"' 'clear_flag, key: "non_interactive"' 'set_flag, key: "non_interactive"' \
  'set_flag, key: "max_tokens"' 'decision: "preflight_clear"' 'decision: "preflight_skipped"' \
  'set_flag, key: "base_mismatch_detected"' 'operation: record_error, phase: FINALIZE' 'operation: record_error, phase: EXECUTE' \
  'decision: "adjudication requires_gap: B: Insert remediation subtask"'; do
  grep -qF -- "$want" <<<"$ckops" \
    && ok "W: a context-keeper spawn carries $want" || no "W: no context-keeper spawn carries $want"
done

echo "-- P. the publish spawn only after write-marker (AC3)"
[ "$P_SEEN" -gt 0 ] && [ -z "$P_BAD" ] \
  && ok "P: $P_SEEN publish spawn(s) across the golden cases, each printed with the finalize-gate marker on disk naming HEAD" \
  || no "P: publish order broken (seen $P_SEEN):$P_BAD"
leg_scripts_unchanged

echo "-- I. idempotency"
for c in init-flags-non-interactive preflight-overlap-ask plan-path-parallel execute-adjudication-ask finalize-pr-base-gh-retry; do
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
     '.gate == "SUP-OVERLAP" and (.question | type) == "string" and (.question | test("PR #")) and .header == "SUP-OVERLAP"
      and .options == ($l | split("|")) and .cant_ask == "preflight_overlap_detected"
      and .questions[0].options == .options' >/dev/null 2>&1; then
  ok "Q: the SUP-OVERLAP ask carries the citing question, the catalog labels ($labels), header \"SUP-OVERLAP\" (its code, human-only too) and cant_ask preflight_overlap_detected"
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
  if printf '%s' "$o_plan" | jq -e '.do == "spawn" and .what == "orchestrator" and .cost_profile == "cheap" and .criteria == "2 acceptance criteria — read the brief'"'"'s ## Acceptance Criteria"' >/dev/null 2>&1 \
     && [ "$r_dup" = 2 ] && [ "$s0" = "$s1" ] \
     && printf '%s' "$NC_OUT" | jq -e '.what == "execute-manager" and .plan_source == "orchestrator" and .subtasks == ["a","b"] and .cost_profile == "cheap"' >/dev/null 2>&1; then
    ok "B1: no subtask table ⇒ the orchestrator spawn (--cheap ⇒ cost_profile cheap); a duplicate id exits 2, nothing written; its plan ⇒ the parallel spawn"
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

echo "-- A. the Phase 3 / FINALIZE question gates (AC4, AC5)"
LEG_MSG=""
if leg_adj_ask "$DRIVER"; then ok "A5: an interactive requires_gap adjudication prints the SUP-ADJ-GAP ask (catalog labels, header \"SUP-ADJ-GAP\", cant_ask adjudication_required_non_interactive) — never a pick"
else no "A5: $LEG_MSG"; fi
if grep "^execute-adjudication-non-interactive$TAB" "$INSTR" | cut -f2- | jq -e 'select(.do == "ask")' >/dev/null 2>&1; then
  no "A5: --non-interactive printed an adjudication ask"
else ok "A5: under --non-interactive the adjudication prints the record + park, never an ask"; fi
a="$(grep "^finalize-children-unsettled$TAB" "$INSTR" | cut -f2- | jq -c 'select(.do == "ask")' 2>/dev/null)"
printf '%s' "$a" | jq -e --arg l "$(catalog_labels SUP-CHILDREN)" '.gate == "SUP-CHILDREN" and .header == "SUP-CHILDREN"
    and .options == ($l | split("|")) and .cant_ask == "children_unsettled"' >/dev/null 2>&1 \
  && ok "A5: the SUP-CHILDREN ask carries its catalog header, the labels and cant_ask children_unsettled" \
  || no "A5: SUP-CHILDREN ask shape wrong: $(printf '%s' "$a" | head -c 200)"
a="$(grep "^finalize-pr-base-gh-retry$TAB" "$INSTR" | cut -f2- | jq -c 'select(.do == "ask")' 2>/dev/null)"
printf '%s' "$a" | jq -e --arg l "$(catalog_labels SUP-GH-RETRY)" '.gate == "SUP-GH-RETRY" and .header == "SUP-GH-RETRY"
    and .options == ($l | split("|")) and .cant_ask == "gh_unavailable_non_interactive"' >/dev/null 2>&1 \
  && ok "A4: the SUP-GH-RETRY ask carries retry|skip-verify-once|abort, header \"SUP-GH-RETRY\" and cant_ask gh_unavailable_non_interactive" \
  || no "A4: SUP-GH-RETRY ask shape wrong: $(printf '%s' "$a" | head -c 200)"
LEG_MSG=""
if leg_retry_once "$DRIVER"; then ok "A4: a first gh failure is retried once; the retry's main ⇒ the verified hand-over, two gh calls, no flag, no ask"
else no "A4: $LEG_MSG"; fi

echo "-- B. Phase 3 / FINALIZE branches the golden cases do not reach"
# B7 — malformed Phase 3 answers exit 2, nothing written, the spawn re-prints
if b_exec execute-result-complete; then
  pend="$NC_OUT"; s0="$(snapshot)"
  sn_call "$DRIVER" --result '{"result":"no block in this text"}'; r1=$NC_RC
  sn_call "$DRIVER" --result "$(jq -cn '{result: "EXECUTE_RESULT:\n  schema_version: 1\n  merge_order: [a\n"}')"; r2=$NC_RC
  sn_call "$DRIVER" --result '{"crashed":true}'; r3=$NC_RC
  sn_call "$DRIVER" --result "$(jq -cn '{result: "EXECUTE_RESULT:\n  schema_version: 1\n  subtasks_completed: []\n  merge_order: []\n  worktrees: []\n  summary: nothing"}')"; r4=$NC_RC
  s1="$(snapshot)"; sn_call "$DRIVER"
  [ "$r1$r2$r3$r4" = 2222 ] && [ "$s0" = "$s1" ] && [ "$NC_OUT" = "$pend" ] \
    && ok "B7: no block, an unparseable block, an error-less crash, an empty EXECUTE_RESULT ⇒ exit 2, nothing written, the spawn re-prints" \
    || no "B7: Phase 3 refusals wrong (rc $r1 $r2 $r3 $r4)"
else no "B7: scratch not built"; fi
# B8 — lane_collision, interactive: the SUP-ADJ-LANE ask; C ⇒ lane_collision (not inter_subtask_gap), job → failed/
if b_exec execute-adjudication-non-interactive; then
  sn_call "$DRIVER" --result "$(payload execute-adjudication-non-interactive 3)"; o_ask="$NC_OUT"
  sn_call "$DRIVER" --result '{"answers":["C: Exit to Launch Pad"]}'; o_rec="$NC_OUT"
  sn_call "$DRIVER" --result '{"confirmed":true}'
  printf '%s' "$o_ask" | jq -e --arg l "$(catalog_labels SUP-ADJ-LANE)" '.do == "ask" and .gate == "SUP-ADJ-LANE" and .header == "SUP-ADJ-LANE"
      and .options == ($l | split("|")) and .cant_ask == "adjudication_required_non_interactive"' >/dev/null 2>&1 \
    && printf '%s' "$o_rec" | jq -e '.ops[0] | test("decision: \"adjudication lane_collision: C: Exit to Launch Pad\"")' >/dev/null 2>&1 \
    && jqo '.do == "park" and .status == "failed" and .error == "lane_collision"' \
    && [ -f "$CASE_ROOT/.supervisor/jobs/failed/2026-10-17-golden-exec.md" ] \
    && ok "B8: lane_collision asks SUP-ADJ-LANE (its own labels); C ⇒ the record, then failed with lane_collision, job → failed/" \
    || no "B8: lane adjudication wrong ($(printf '%s' "$NC_OUT" | head -c 200))"
else no "B8: scratch not built"; fi
# B9 — requires_gap under --non-interactive: no ask, adjudication_required_non_interactive: requires_gap, job stays
if b_exec execute-adjudication-ask --non-interactive; then
  sn_call "$DRIVER" --result "$(payload execute-adjudication-ask 3)"; o1="$NC_OUT"
  sn_call "$DRIVER" --result '{"confirmed":true}'
  printf '%s' "$o1" | jq -e '.what == "context-keeper"' >/dev/null 2>&1 \
    && jqo '.do == "park" and .status == "failed" and .error == "adjudication_required_non_interactive: requires_gap"' \
    && [ -f "$CASE_ROOT/.supervisor/jobs/in-progress/2026-10-17-golden-exec.md" ] \
    && ok "B9: requires_gap under --non-interactive ⇒ no option picked, adjudication_required_non_interactive: requires_gap, brief stays in-progress" \
    || no "B9: non-interactive requires_gap wrong ($(printf '%s' "$NC_OUT" | head -c 200))"
else no "B9: scratch not built"; fi
# B10 — requires_gap ask: an off-list label exits 2; cant_ask takes the can't-ask park; C ⇒ inter_subtask_gap
if b_exec execute-adjudication-ask; then
  sn_call "$DRIVER" --result "$(payload execute-adjudication-ask 3)"
  s0="$(snapshot)"; sn_call "$DRIVER" --result '{"answers":["E: Pick for me"]}'; r1=$NC_RC; s1="$(snapshot)"
  sn_call "$DRIVER" --result '{"cant_ask":true}'; sn_call "$DRIVER" --result '{"confirmed":true}'
  [ "$r1" = 2 ] && [ "$s0" = "$s1" ] && jqo '.status == "failed" and .error == "adjudication_required_non_interactive: requires_gap"' \
    && ok "B10: an off-list adjudication label exits 2, nothing written; cant_ask ⇒ adjudication_required_non_interactive" \
    || no "B10: adjudication answers wrong (off-list rc $r1; $(printf '%s' "$NC_OUT" | head -c 160))"
fi
if b_exec execute-adjudication-ask; then
  sn_call "$DRIVER" --result "$(payload execute-adjudication-ask 3)"
  sn_call "$DRIVER" --result '{"answers":["C: Exit to Launch Pad"]}'; sn_call "$DRIVER" --result '{"confirmed":true}'
  jqo '.status == "failed" and .error == "inter_subtask_gap"' && [ -f "$CASE_ROOT/.supervisor/jobs/failed/2026-10-17-golden-exec.md" ] \
    && ok "B10: requires_gap C ⇒ failed with inter_subtask_gap, job → failed/" || no "B10: requires_gap C wrong ($(printf '%s' "$NC_OUT" | head -c 160))"
fi
# B11 — a budget EXECUTE_CHECKPOINT (no adjudication): the record, then the checkpoint park
if b_exec execute-result-complete; then
  sn_call "$DRIVER" --result "$(payload execute-adjudication-ask 3 | jq -c '.result |= (split("\n") | map(select(test("adjudication|missing_outputs|    - item|      producing|      check_run") | not)) | join("\n") | sub("reason: [^\n]*"; "reason: tool budget reached"))')"
  o1="$NC_OUT"; sn_call "$DRIVER" --result '{"confirmed":true}'
  printf '%s' "$o1" | jq -e '.ops[0] | test("decision: \"execute_checkpoint: tool budget reached\"")' >/dev/null 2>&1 \
    && jqo '.do == "park" and .status == "checkpoint" and (has("error") | not)' \
    && ok "B11: a non-adjudication EXECUTE_CHECKPOINT ⇒ the execute_checkpoint record, then the checkpoint park with the resume command" \
    || no "B11: budget checkpoint wrong ($(printf '%s' "$o1" | head -c 160) / $(printf '%s' "$NC_OUT" | head -c 160))"
fi
# B12 — pre-merge points 2, 3 (orphan; a missing worktree ⇒ checkpoint) and 4
if b_exec execute-result-complete; then
  sn_call "$DRIVER" --result "$(payload execute-result-complete 3 | sed 's/review_decision: PASS\\n    - task_id: b/review_decision: FAIL\\n    - task_id: b/')"
  sn_call "$DRIVER" --result '{"confirmed":true}'
  jqo '.status == "failed" and (.error | startswith("pre-merge safety gate point 2"))' && [ -f "$CASE_ROOT/.supervisor/jobs/failed/2026-10-17-golden-exec.md" ] \
    && ok "B12: a review_decision other than PASS ⇒ point 2 fails, job → failed/" || no "B12: point 2 wrong ($(printf '%s' "$NC_OUT" | head -c 200))"
fi
if b_exec execute-result-complete; then
  sn_call "$DRIVER" --result "$(payload execute-result-complete 3 | jq -c '.result |= sub("\n    - task_id: b\n      path: ../repo-b\n      branch: feature/exec-b\n      status: completed"; "")')"
  sn_call "$DRIVER" --result '{"confirmed":true}'
  jqo '.status == "failed" and (.error | test("point 3 .*feature/exec-b"))' \
    && ok "B12: a registered worktree on a result branch that the result does not list ⇒ point 3 (orphan) fails" || no "B12: orphan wrong ($(printf '%s' "$NC_OUT" | head -c 200))"
fi
if b_exec execute-result-complete; then
  in_case /dev/null bash -c 'git worktree remove --force ../repo-b' >/dev/null 2>&1
  sn_call "$DRIVER" --result "$(payload execute-result-complete 3)"; o1="$NC_OUT"
  sn_call "$DRIVER" --result '{"confirmed":true}'
  printf '%s' "$o1" | jq -e '.ops[0] | test("missing worktree ../repo-b")' >/dev/null 2>&1 \
    && jqo '.status == "checkpoint"' && [ -f "$CASE_ROOT/.supervisor/jobs/in-progress/2026-10-17-golden-exec.md" ] \
    && ok "B12: a missing worktree ⇒ checkpoint (reported, nothing merged), the job stays in-progress" || no "B12: missing worktree wrong ($(printf '%s' "$o1" | head -c 200))"
fi
if b_exec execute-result-complete; then
  in_case /dev/null bash -c 'git checkout -q main && git commit -q --allow-empty -m drift && git checkout -q feature/golden-exec' >/dev/null 2>&1
  sn_call "$DRIVER" --result "$(payload execute-result-complete 3)"; sn_call "$DRIVER" --result '{"confirmed":true}'
  jqo '.status == "failed" and (.error | startswith("pre-merge safety gate point 4"))' \
    && ok "B12: a feature branch that does not hold the base tip ⇒ point 4 fails" || no "B12: point 4 wrong ($(printf '%s' "$NC_OUT" | head -c 200))"
fi
# B13 — point 5: proceed anyway (the skip is recorded and the marker says skipped), investigate,
# --non-interactive (fail closed, no ask), and the --skip-children-check flag
if b_exec finalize-children-unsettled; then
  sn_call "$DRIVER" --result "$(payload finalize-children-unsettled 3)"
  sn_call "$DRIVER" --result '{"answers":["proceed anyway"]}'; o_rec="$NC_OUT"
  sn_call "$DRIVER" --result '{"confirmed":true}'; o_m="$NC_OUT"
  sn_call "$DRIVER" --result '{"merged":["feature/exec-a","feature/exec-b"],"conflict":null,"refold":"ok"}'
  printf '%s' "$o_rec" | jq -e '.ops[0] | test("decision: \"user_skipped_children_check\"")' >/dev/null 2>&1 \
    && printf '%s' "$o_m" | jq -e '.what == "finalize-merge"' >/dev/null 2>&1 \
    && jqo '.what == "finalize-publish" and .children_check == "skipped"' \
    && [ "$(jq -r .children_check "$CASE_ROOT/.supervisor/logs/$CASE_SID.finalize-gate" 2>/dev/null)" = skipped ] \
    && ok "B13: proceed anyway ⇒ user_skipped_children_check recorded, write-marker --skip-children-check, publish says skipped" \
    || no "B13: proceed anyway wrong ($(printf '%s' "$NC_OUT" | head -c 200))"
fi
if b_exec finalize-children-unsettled; then
  sn_call "$DRIVER" --result "$(payload finalize-children-unsettled 3)"; sn_call "$DRIVER" --result '{"answers":["investigate"]}'
  jqo '.do == "park" and .status == "checkpoint" and (.message | test("a2222222222222222"))' && [ -f "$CASE_ROOT/.supervisor/jobs/in-progress/2026-10-17-golden-exec.md" ] \
    && ok "B13: investigate ⇒ the checkpoint park naming the id, the job stays in-progress" || no "B13: investigate wrong"
fi
if b_exec finalize-children-unsettled --non-interactive; then
  sn_call "$DRIVER" --result "$(payload finalize-children-unsettled 3)"; o1="$NC_OUT"; sn_call "$DRIVER" --result '{"confirmed":true}'
  printf '%s' "$o1" | jq -e '.what == "context-keeper"' >/dev/null 2>&1 && jqo '.status == "failed" and .error == "children_unsettled: a2222222222222222"' \
    && [ -f "$CASE_ROOT/.supervisor/jobs/failed/2026-10-17-golden-exec.md" ] \
    && ok "B13: --non-interactive ⇒ no ask, children_unsettled: <ids> (fail closed), job → failed/" || no "B13: non-interactive point 5 wrong ($(printf '%s' "$NC_OUT" | head -c 200))"
fi
if b_exec finalize-children-unsettled --skip-children-check; then
  sn_call "$DRIVER" --result "$(payload finalize-children-unsettled 3)"; o1="$NC_OUT"; sn_call "$DRIVER" --result '{"confirmed":true}'
  printf '%s' "$o1" | jq -e '.ops == ["Context-Keeper(operation: record_decision, phase: FINALIZE, decision: \"user_skipped_children_check\", rationale: \"--skip-children-check flag\")"]' >/dev/null 2>&1 \
    && jqo '.what == "finalize-merge"' && ok "B13: --skip-children-check ⇒ the user_skipped_children_check record, then the merge spawn" \
    || no "B13: --skip-children-check wrong ($(printf '%s' "$o1" | head -c 200))"
fi
# B14 — the merge report: a conflict STOPs (checkpoint, merged / not-merged lists); a refused re-fold
# aborts (release_refold_refused, job → failed/); a merged list short of merge_order exits 2
if b_exec execute-result-complete; then
  sn_call "$DRIVER" --result "$(payload execute-result-complete 3)"
  s0="$(snapshot)"; sn_call "$DRIVER" --result '{"merged":["feature/exec-a"],"conflict":null,"refold":"ok"}'; r1=$NC_RC; s1="$(snapshot)"
  sn_call "$DRIVER" --result '{"merged":["feature/exec-a"],"conflict":{"branch":"feature/exec-b","files":["ui.md"]},"refold":"ok"}'; o1="$NC_OUT"
  sn_call "$DRIVER" --result '{"confirmed":true}'
  [ "$r1" = 2 ] && [ "$s0" = "$s1" ] && printf '%s' "$o1" | jq -e '.ops[0] | test("merge conflict: feature/exec-b: ui.md") and test("not merged: feature/exec-b")' >/dev/null 2>&1 \
    && jqo '.status == "checkpoint"' && ok "B14: a short merged list exits 2; a conflict ⇒ STOP: the record with the merged / not-merged lists, the checkpoint park" \
    || no "B14: conflict wrong (rc $r1; $(printf '%s' "$o1" | head -c 200))"
fi
if b_exec execute-result-complete; then
  sn_call "$DRIVER" --result "$(payload execute-result-complete 3)"
  sn_call "$DRIVER" --result '{"merged":["feature/exec-a","feature/exec-b"],"conflict":null,"refold":"refused","refold_reason":"fragment unfolded"}'
  sn_call "$DRIVER" --result '{"confirmed":true}'
  jqo '.status == "failed" and .error == "release_refold_refused"' && [ -f "$CASE_ROOT/.supervisor/jobs/failed/2026-10-17-golden-exec.md" ] \
    && [ ! -f "$CASE_ROOT/.supervisor/logs/$CASE_SID.finalize-gate" ] \
    && ok "B14: a refused re-fold ⇒ release_refold_refused, job → failed/, no marker, no publish" || no "B14: refold wrong ($(printf '%s' "$NC_OUT" | head -c 200))"
fi
# B15 — write-marker refuses: a missing session log ⇒ the checkpoint park and no publish; a Worker Results
# id with no terminal row ⇒ children_unsettled at the marker ⇒ the SUP-CHILDREN ask from finalize-marker
if b_exec finalize-marker-written; then
  sn_call "$DRIVER" --result '{"subtask":"1","agent_id":"ac394bd015ea3ff94","status":"completed","gates":"passed"}'
  in_case /dev/null bash -c 'printf "d\n" > d.sh && git add -A && git commit -qm x' >/dev/null 2>&1
  rm -f "$CASE_ROOT/.supervisor/logs/$CASE_SID.jsonl"
  sn_call "$DRIVER" --result '{"merged":[],"conflict":null,"refold":"ok"}'
  jqo '.do == "park" and .step == "finalize-marker" and .status == "checkpoint" and (.message | test("session_log_missing"))' \
    && ! grep -q '"what":"finalize-publish"' <<<"$NC_OUT" \
    && ok "B15: write-marker refusing (session_log_missing) ⇒ the checkpoint park, nothing published" || no "B15: marker refusal wrong ($(printf '%s' "$NC_OUT" | head -c 200))"
fi
if b_exec execute-result-complete; then
  printf '### a9999999999999999 (c)\n- agent_id: a9999999999999999\n' >> "$CASE_ROOT/.supervisor/state.md.tmp"
  awk '1; /^## Worker Results/ { while ((getline l < ARGV[2]) > 0) print l }' "$CASE_ROOT/.supervisor/state.md" "$CASE_ROOT/.supervisor/state.md.tmp" > "$CASE_ROOT/.supervisor/state.md.new" 2>/dev/null
  mv "$CASE_ROOT/.supervisor/state.md.new" "$CASE_ROOT/.supervisor/state.md"; rm -f "$CASE_ROOT/.supervisor/state.md.tmp"
  sn_call "$DRIVER" --result "$(payload execute-result-complete 3)"
  sn_call "$DRIVER" --result '{"merged":["feature/exec-a","feature/exec-b"],"conflict":null,"refold":"ok"}'; o_ask="$NC_OUT"
  sn_call "$DRIVER" --result '{"answers":["proceed anyway"]}'; sn_call "$DRIVER" --result '{"confirmed":true}'
  printf '%s' "$o_ask" | jq -e '.do == "ask" and .step == "finalize-marker" and .gate == "SUP-CHILDREN" and (.question | test("a9999999999999999"))' >/dev/null 2>&1 \
    && jqo '.what == "finalize-publish" and .children_check == "skipped"' \
    && ok "B15: an expected Worker Results id unsettled at write-marker ⇒ the SUP-CHILDREN ask; proceed anyway re-runs it with --skip-children-check" \
    || no "B15: marker-time unsettled wrong ($(printf '%s' "$o_ask" | head -c 200))"
fi
# B16 — the inline paths: the next sequential worker; a wrong subtask id / a passed partial exit 2; paused ⇒ checkpoint
if b_exec plan-path-sequential; then
  s0="$(snapshot)"
  sn_call "$DRIVER" --result '{"subtask":"2","agent_id":"a1","status":"completed","gates":"passed"}'; r1=$NC_RC
  sn_call "$DRIVER" --result '{"subtask":"1","agent_id":"a1","status":"partial","gates":"passed"}'; r2=$NC_RC
  s1="$(snapshot)"
  sn_call "$DRIVER" --result '{"subtask":"1","agent_id":"a1","status":"completed","gates":"passed"}'; o2="$NC_OUT"
  sn_call "$DRIVER" --result '{"subtask":"2","agent_id":"a2","status":"partial","gates":"paused","reason":"outputs_gap empty: spec unreadable"}'
  [ "$r1$r2" = 22 ] && [ "$s0" = "$s1" ] && printf '%s' "$o2" | jq -e '.what == "worker" and .subtask == "2"' >/dev/null 2>&1 \
    && jqo '.do == "park" and .status == "checkpoint" and (.message | test("Subtask 2 paused"))' \
    && ok "B16: sequential ⇒ the next subtask's worker; a wrong id / a passed partial exit 2; paused ⇒ the checkpoint park" \
    || no "B16: inline routing wrong (rc $r1 $r2; $(printf '%s' "$o2" | head -c 120))"
else no "B16: scratch not built"; fi
# B17 — step 6.5 branches: --non-interactive (no ask; gh_unavailable_non_interactive), skip-verify-once,
# abort, a failing retry, a cant_ask answer; a failed publish ⇒ checkpoint; a non-PR URL exits 2
b17() { # <flags…> — a finalize scratch whose gh always fails, at the pr_url answer
  b_fin finalize-pr-base-verified "$@" || return 1
  printf '1\tpr view *\t\n' > "$CASE_GH"
  sn_call "$DRIVER" --result '{"pr_url":"https://github.com/golden/repo/pull/12"}'
}
if b17 --non-interactive; then
  o1="$NC_OUT"; sn_call "$DRIVER" --result '{"confirmed":true}'
  printf '%s' "$o1" | jq -e '.what == "context-keeper" and (.ops[0] | test("reason\":\"gh_unavailable_non_interactive"))' >/dev/null 2>&1 \
    && jqo '.do == "done" and .base_mismatch_detected == true and .base_verify == "gh_unavailable_non_interactive"' \
    && ok "B17: --non-interactive, gh failing twice ⇒ no ask; base_mismatch_detected (gh_unavailable_non_interactive) ⇒ the cleanup hand-over" \
    || no "B17: non-interactive gh wrong ($(printf '%s' "$o1" | head -c 200))"
fi
if b17; then
  sn_call "$DRIVER" --result '{"answers":["skip-verify-once"]}'; o1="$NC_OUT"; sn_call "$DRIVER" --result '{"confirmed":true}'
  printf '%s' "$o1" | jq -e '.ops[0] | test("decision: \"user_skipped_base_verify\", rationale: \"gh repeatedly unavailable\"")' >/dev/null 2>&1 \
    && jqo '.do == "done" and .base_verify == "skipped" and .base_mismatch_detected == false' \
    && ok "B17: skip-verify-once ⇒ user_skipped_base_verify recorded, the hand-over as verified" || no "B17: skip-verify-once wrong"
fi
for ans in abort retry cant_ask; do
  if b17; then
    if [ "$ans" = cant_ask ]; then sn_call "$DRIVER" --result '{"cant_ask":true}'; else sn_call "$DRIVER" --result "{\"answers\":[\"$ans\"]}"; fi
    o1="$NC_OUT"; sn_call "$DRIVER" --result '{"confirmed":true}'
    want=user_aborted_gh_retry; [ "$ans" = cant_ask ] && want=gh_unavailable_non_interactive
    printf '%s' "$o1" | jq -e --arg w "$want" '.ops[0] | test("reason\":\"" + $w)' >/dev/null 2>&1 && jqo --arg w "$want" '.base_mismatch_detected == true and .base_verify == $w' \
      && ok "B17: $ans ⇒ base_mismatch_detected ($want) ⇒ the cleanup hand-over" || no "B17: $ans wrong ($(printf '%s' "$o1" | head -c 200))"
  fi
done
if b_fin finalize-pr-base-verified; then
  s0="$(snapshot)"; sn_call "$DRIVER" --result '{"pr_url":"not a url"}'; r1=$NC_RC; s1="$(snapshot)"
  sn_call "$DRIVER" --result '{"publish_failed":"push denied: run FINALIZE point 5 first"}'
  [ "$r1" = 2 ] && [ "$s0" = "$s1" ] && jqo '.do == "park" and .status == "checkpoint" and (.message | test("push denied"))' \
    && ok "B17: a non-PR URL exits 2, nothing written; a failed publish ⇒ the checkpoint park" || no "B17: publish answers wrong (rc $r1)"
fi
# B17b — the handover's test_guard (af/39c): armed (marker) · unarmed (<this session's skip row>) · unarmed
# (INIT arm failure) · unarmed (marker_missing) · not_applicable (host mode, unsafe gate root). The stub guard
# command never writes a marker, so the default hand-over reads marker_missing.
tg_case() { # <label> <expected> [setup-fn] — a finalize scratch at the pr_url answer; sets TG_OUT
  b_fin finalize-pr-base-verified || { no "B17b: $1 — scratch not built"; return 1; }
  [ -z "${3:-}" ] || "$3"
  sn_call "$DRIVER" --result '{"pr_url":"https://github.com/golden/repo/pull/12"}'
  SN_CALL_SEAMS=/dev/null
  if jqo --arg w "$2" '.do == "done" and .step == "handover" and .test_guard == $w'; then
    ok "B17b: handover test_guard — $1 ⇒ $2"
  else no "B17b: handover test_guard — $1: want '$2', got $(printf '%s' "$NC_OUT" | jq -r '.test_guard // "(none)"' 2>/dev/null)"; fi
}
tg_arm() { mkdir -p "$CASE_ROOT/.supervisor/guard" && printf '{"session_id":"%s","by":"test"}\n' "$CASE_SID" > "$CASE_ROOT/.supervisor/guard/$CASE_SID.json"; }
tg_rows() {
  # a skip row for ANOTHER session (later ts, must be ignored) and this session's older + newer rows
  mkdir -p "$CASE_ROOT/.supervisor/logs"
  {
    printf '{"event":"guard_arm_skipped","reason":"no_guard_dir","session_id":"other-sid","cc_session_id":"other-sid","ts":"2099-01-01T00:00:00Z"}\n'
    printf '{"event":"guard_arm_skipped","reason":"jq_missing","session_id":"%s","cc_session_id":"%s","ts":"2026-10-28T00:00:00Z"}\n' "$CASE_SID" "$CASE_SID"
    printf 'not json at all\n'
    printf '{"event":"guard_arm_skipped","reason":"marker_write_failed","session_id":"%s","cc_session_id":"%s","ts":"2026-10-28T00:00:05Z"}\n' "$CASE_SID" "$CASE_SID"
  } >> "$CASE_ROOT/.supervisor/logs/$CASE_SID.jsonl"
}
tg_host_unsafe() {
  local uid; uid="$(id -u 2>/dev/null || echo 0)"
  mkdir -p "$CASE_DIR/tg-tmp/loomwright-host-$uid" && chmod 777 "$CASE_DIR/tg-tmp/loomwright-host-$uid"
  printf '%s\n' 'LOOMWRIGHT_HOST_MODE=1' "TMPDIR=$CASE_DIR/tg-tmp" > "$CASE_DIR/tg-host.env"
  SN_CALL_SEAMS="$CASE_DIR/tg-host.env"
}
tg_case "marker present" armed tg_arm
tg_case "a skip row for this session (another session's row ignored; latest wins)" "unarmed (marker_write_failed)" tg_rows
tg_case "no marker, no row" "unarmed (marker_missing)"
printf '%s\n' 'SUPERVISOR_NEXT_STEP_GUARD_CMD=false' > "$WORK/tg-guard-fail.env"
SN_CALL_SEAMS="$WORK/tg-guard-fail.env"
if b_fin finalize-pr-base-verified; then
  SN_CALL_SEAMS=/dev/null
  sn_call "$DRIVER" --result '{"pr_url":"https://github.com/golden/repo/pull/12"}'
  jqo '.do == "done" and .test_guard == "unarmed (exit 1)"' \
    && ok "B17b: handover test_guard — INIT arm failed (no marker, no row) ⇒ unarmed (exit 1)" \
    || no "B17b: INIT arm failure — got $(printf '%s' "$NC_OUT" | jq -r '.test_guard // "(none)"' 2>/dev/null)"
else no "B17b: INIT-failure scratch not built"; fi
SN_CALL_SEAMS=/dev/null
tg_case "host mode, unsafe gate root" not_applicable tg_host_unsafe

# B18 — step 4 asks git, not the .gitignore text (#615). Under `/setup memory`'s branch-mode managed block
# (`.supervisor/*` + `!.supervisor/memory/`, no bare line) two real inits — the second a fresh session
# re-entering through in-progress/ (a second --job in the same session only re-prints) — leave .gitignore
# byte-unchanged, the memory store committable and the tree clean. Controls: with no rule the line is
# appended exactly once across both runs (onto its own line); outside a repo the exact-line test holds
B18_JOB=.supervisor/jobs/pending/2026-10-17-golden-tokens.md
b18_init_twice() { # <driver> — two real inits; B18_RAN = how many reached step 4 (it recreates history/)
  local s o
  B18_RAN=0
  for s in "$CASE_SID" "$CASE_SID-b18"; do
    rmdir "$CASE_ROOT/.supervisor/history" 2>/dev/null
    o="$(in_case /dev/null bash "$1" --session-id "$s" --job "$B18_JOB" 2>/dev/null)"
    [ -d "$CASE_ROOT/.supervisor/history" ] && printf '%s' "$o" | jq -e '.do == "spawn" and .step == "init"' >/dev/null 2>&1 \
      && B18_RAN=$((B18_RAN + 1))
  done
}
b18_managed() { # <driver> — sets LEG_MSG on failure
  local rc
  new_scratch "$FIX/init-flags-max-tokens" || { LEG_MSG="scratch not built"; return 1; }
  ( cd "$CASE_ROOT" && export HOME="$CASE_HOME" && eval "export $GIT_ENV" \
      && bash "$HERE/setup-memory.sh" apply --branch-mode loomwright-meta && rm -f .gitignore.backup.* \
      && git add -A && git commit -q -m "setup memory" ) >"$CASE_DIR/b18-setup.log" 2>&1 \
    || { LEG_MSG="setup-memory apply / commit failed (see $CASE_DIR/b18-setup.log)"; return 1; }
  grep -qxF '.supervisor/*' "$CASE_ROOT/.gitignore" && ! grep -qxF '.supervisor/' "$CASE_ROOT/.gitignore" \
    || { LEG_MSG="setup-memory did not leave a managed block without a bare line"; return 1; }
  [ -z "$(in_case /dev/null git status --porcelain)" ] || { LEG_MSG="tree not clean before the runs"; return 1; }
  cp "$CASE_ROOT/.gitignore" "$CASE_DIR/gitignore.before"
  b18_init_twice "$1"
  [ "$B18_RAN" = 2 ] || { LEG_MSG="the bootstrap ran $B18_RAN of 2 times"; return 1; }
  cmp -s "$CASE_DIR/gitignore.before" "$CASE_ROOT/.gitignore" \
    || { LEG_MSG=".gitignore changed: $(diff "$CASE_DIR/gitignore.before" "$CASE_ROOT/.gitignore" | grep '^[<>]' | tr '\n' ' ')"; return 1; }
  in_case /dev/null git check-ignore -q .supervisor/memory/LESSONS.md; rc=$?
  [ "$rc" = 1 ] || { LEG_MSG="git check-ignore .supervisor/memory/LESSONS.md exited $rc, want 1"; return 1; }
  [ -z "$(in_case /dev/null git status --porcelain)" ] \
    || { LEG_MSG="tree dirty: $(in_case /dev/null git status --porcelain | tr '\n' ' ')"; return 1; }
}
b18_append() { # <driver> <.gitignore before: printf format, or - for none> <want: printf format> [norepo]
  new_scratch "$FIX/init-flags-max-tokens" || { LEG_MSG="scratch not built"; return 1; }
  rm -f "$CASE_ROOT/.gitignore"
  [ "$2" = - ] || printf "$2" > "$CASE_ROOT/.gitignore"
  if [ "${4:-}" = norepo ]; then
    rm -rf "$CASE_ROOT/.git"
    ! in_case /dev/null git rev-parse --git-dir >/dev/null 2>&1 || { LEG_MSG="the scratch still sits inside a git repo"; return 1; }
    # no repo ⇒ no origin/HEAD: the base comes from the config key (resolve-base-branch.sh has no
    # `main` fallback — an unconfigured non-repo init stops with base_branch_unresolved)
    printf '{"base_branch":"main"}\n' > "$CASE_ROOT/.supervisor/config.json"
  fi
  printf "$3" > "$CASE_DIR/gitignore.want"
  b18_init_twice "$1"
  [ "$B18_RAN" = 2 ] || { LEG_MSG="the bootstrap ran $B18_RAN of 2 times"; return 1; }
  cmp -s "$CASE_DIR/gitignore.want" "$CASE_ROOT/.gitignore" \
    || { LEG_MSG=".gitignore is '$(tr '\n' '|' < "$CASE_ROOT/.gitignore" 2>/dev/null)', want '$(tr '\n' '|' < "$CASE_DIR/gitignore.want")'"; return 1; }
}
LEG_MSG=""
if b18_managed "$DRIVER"; then ok "B18: under /setup memory's managed block two inits leave .gitignore byte-unchanged, .supervisor/memory/ committable and the tree clean"
else no "B18: managed block: $LEG_MSG"; fi
LEG_MSG=""
if b18_append "$DRIVER" - '.supervisor/\n' && b18_append "$DRIVER" 'node_modules' 'node_modules\n.supervisor/\n'; then
  ok "B18: with no ignore rule the bare line is appended exactly once across two inits (on its own line)"
else no "B18: no-rule control: $LEG_MSG"; fi
LEG_MSG=""
if b18_append "$DRIVER" 'node_modules\n' 'node_modules\n.supervisor/\n' norepo && b18_append "$DRIVER" '.supervisor/\n' '.supervisor/\n' norepo; then
  ok "B18: outside a git repo the exact-line test holds (appended once; a present bare line left alone)"
else no "B18: outside-a-repo control: $LEG_MSG"; fi

# B19 — #618 script events (TEE, events ON; the case HOME holds no consent, so nothing is posted):
# a surfaced arm failure ⇒ ONE `fail <arm>-failed`; the hand-over ⇒ ONE `pass ok`; no message text.
SNEV="$WORK/sn-events.jsonl"
sn_ev() { python3 -I -c 'import json,sys
print(";".join("%s/%s/%s/%s" % (d["script"], d["step"], d["outcome"], d["code"]) for d in (json.loads(l) for l in open(sys.argv[1]) if l.strip())))' "$SNEV"; }
if new_scratch "$FIX/init-flags-max-tokens"; then
  rm -rf "$CASE_ROOT/.supervisor/history"; chmod 555 "$CASE_ROOT/.supervisor"   # init's mkdir now fails ⇒ sn_fail
  : > "$SNEV"
  LOOMWRIGHT_SCRIPT_EVENTS=1 LOOMWRIGHT_SCRIPT_EVENT_TEE="$SNEV" sn_call "$DRIVER" --job .supervisor/jobs/pending/2026-10-17-golden-tokens.md
  chmod 755 "$CASE_ROOT/.supervisor"
  [ "$NC_RC" = 1 ] && [ "$(sn_ev)" = "supervisor-next-step/run/fail/init-failed" ] \
    && ok "B19: a surfaced init failure (exit 1) ⇒ one script event fail init-failed" \
    || no "B19: init failure ⇒ exit $NC_RC, events '$(sn_ev)'"
else no "B19: scratch not built"; fi
if b_fin finalize-pr-base-verified; then
  printf '0\tpr view *\tmain\n' > "$CASE_GH"; : > "$SNEV"
  LOOMWRIGHT_SCRIPT_EVENTS=1 LOOMWRIGHT_SCRIPT_EVENT_TEE="$SNEV" sn_call "$DRIVER" --result '{"pr_url":"https://github.com/golden/repo/pull/12"}'
  jqo '.do == "done" and .step == "handover"' && [ "$(sn_ev)" = "supervisor-next-step/run/pass/ok" ] \
    && ok "B19: the hand-over ⇒ one script event pass ok (closes the run's open threads)" \
    || no "B19: hand-over ⇒ '$(printf '%s' "$NC_OUT" | head -c 120)' events '$(sn_ev)'"
else no "B19: finalize scratch not built"; fi

# B20 — the base through resolve-base-branch.sh (configurable-base AC1 / AC9). b20_dev: origin/HEAD →
# `development`, no .supervisor/config.json and no `Base Branch:` line ⇒ the run acquires, finalizes and
# publishes against development (`gh pr create --base development`). b20_stop: an invalid brief
# `Base Branch:` / an unresolvable base (no origin, a gh that fails, no config) ⇒ init stops with the
# resolver's status token — exit 1, nothing printed, the brief left in pending/ (never a `main` guess).
b20_dev() { # <driver> — sets LEG_MSG on failure
  local d="$1" j=".supervisor/jobs/pending/2026-10-17-golden-finalize.md"
  new_scratch "$FIX/finalize-pr-base-verified" || { LEG_MSG="scratch not built"; return 1; }
  in_case /dev/null bash -c 'git push -q origin main:development && git -C "$1" symbolic-ref HEAD refs/heads/development \
      && git fetch -q origin && git remote set-head origin -a' _ "$CASE_DIR/origin.git" >/dev/null 2>&1 \
    || { LEG_MSG="origin/HEAD → development not set up"; return 1; }
  [ "$(in_case /dev/null git symbolic-ref -q --short refs/remotes/origin/HEAD)" = origin/development ] \
    || { LEG_MSG="origin/HEAD does not name origin/development"; return 1; }
  ! grep -q 'Base Branch' "$CASE_ROOT/$j" && [ ! -e "$CASE_ROOT/.supervisor/config.json" ] \
    || { LEG_MSG="the brief or a config names the base — the leg must rest on origin/HEAD alone"; return 1; }
  sn_call "$d" --job "$j" --skip-preflight-sync
  sn_call "$d" --result '{"confirmed":true}'
  sn_call "$d" --result '{"confirmed":true}'
  jqo '.step == "execute" and .do == "spawn"' || { LEG_MSG="no execute spawn: $(printf '%s' "$NC_OUT" | head -c 160) $(head -c 160 "$CASE_DIR/nc.err")"; return 1; }
  [ "$(jq -r '.base_branch // empty' "$CASE_ROOT/.supervisor/logs/$CASE_SID.supervisor-next-step.json" 2>/dev/null)" = development ] \
    && in_case /dev/null git rev-parse -q --verify refs/heads/development >/dev/null 2>&1 \
    || { LEG_MSG="init did not record development as the base (or acquire did not check it out)"; return 1; }
  in_case /dev/null bash -c 'printf "driver\n" > driver.sh' || { LEG_MSG="driver.sh not written"; return 1; }
  sn_call "$d" --result '{"subtask":"1","agent_id":"ac394bd015ea3ff94","status":"completed","gates":"passed"}'
  in_case /dev/null bash -c 'git add -A && git commit -qm "feat: golden"' >/dev/null 2>&1 || { LEG_MSG="commit failed"; return 1; }
  sn_call "$d" --result '{"merged":[],"conflict":null,"refold":"ok"}'
  jqo '.what == "finalize-publish" and .base_branch == "development"
      and ([.commands[] | select(startswith("gh pr create --base development "))] | length) == 1' \
    || { LEG_MSG="publish spawn: $(printf '%s' "$NC_OUT" | head -c 240)"; return 1; }
}
b20_stop() { # <driver> <invalid|unresolved> — sets LEG_MSG on failure
  local d="$1" j=".supervisor/jobs/pending/2026-10-17-golden-tokens.md" want
  new_scratch "$FIX/init-flags-max-tokens" || { LEG_MSG="scratch not built"; return 1; }
  case "$2" in
    invalid) want='base_branch_invalid:brief'
      awk '{ print } $0 == "## Configuration" { print "- **Base Branch:** bad..name" }' "$CASE_ROOT/$j" > "$CASE_DIR/brief" \
        && mv "$CASE_DIR/brief" "$CASE_ROOT/$j" && grep -qF 'Base Branch:** bad..name' "$CASE_ROOT/$j" \
        || { LEG_MSG="invalid Base Branch: not written"; return 1; } ;;
    unresolved) want='base_branch_unresolved'
      in_case /dev/null git remote remove origin >/dev/null 2>&1 || { LEG_MSG="origin not removed"; return 1; } ;;
  esac
  sn_call "$d" --job "$j"
  [ "$NC_RC" = 1 ] && [ -z "$NC_OUT" ] || { LEG_MSG="$2: exit $NC_RC, printed '$(printf '%s' "$NC_OUT" | head -c 120)'"; return 1; }
  grep -qF -- "$want" "$CASE_DIR/nc.err" || { LEG_MSG="$2: stderr lacks $want: $(head -c 200 "$CASE_DIR/nc.err")"; return 1; }
  [ -f "$CASE_ROOT/$j" ] && [ ! -e "$CASE_ROOT/.supervisor/jobs/in-progress/${j##*/}" ] || { LEG_MSG="$2: the brief was moved"; return 1; }
}
LEG_MSG=""
if b20_dev "$DRIVER"; then ok "B20: origin/HEAD → development, no config, no Base Branch: ⇒ the publish spawn runs gh pr create --base development"
else no "B20: origin/HEAD development: $LEG_MSG"; fi
for b20c in invalid unresolved; do
  LEG_MSG=""
  if b20_stop "$DRIVER" "$b20c"; then ok "B20: $b20c base ⇒ init stops with the resolver's status token (exit 1, nothing printed, the brief unmoved)"
  else no "B20: $b20c: $LEG_MSG"; fi
done
# b20_acquire <driver> <resolves|unresolved> — acquire reads the base init recorded and resolves only when
# that state value is empty: with it deleted from the sidecar, acquire re-resolves (origin/HEAD → main) and
# records it; with origin gone too, acquire stops with base_branch_unresolved (exit 1, nothing printed)
b20_acquire() {
  local d="$1" j=".supervisor/jobs/pending/2026-10-17-golden-tokens.md" sc
  new_scratch "$FIX/init-flags-max-tokens" || { LEG_MSG="scratch not built"; return 1; }
  sn_call "$d" --job "$j"
  jqo '.do == "spawn" and .step == "init"' || { LEG_MSG="no init spawn: $(head -c 160 "$CASE_DIR/nc.err")"; return 1; }
  sc="$CASE_ROOT/.supervisor/logs/$CASE_SID.supervisor-next-step.json"
  jq -e '.base_branch == "main"' "$sc" >/dev/null 2>&1 || { LEG_MSG="init did not record main"; return 1; }
  jq 'del(.base_branch)' "$sc" > "$sc.t" && mv "$sc.t" "$sc" || { LEG_MSG="sidecar not edited"; return 1; }
  if [ "$2" = unresolved ]; then
    in_case /dev/null git remote remove origin >/dev/null 2>&1 || { LEG_MSG="origin not removed"; return 1; }
  fi
  sn_call "$d" --result '{"confirmed":true}'
  case "$2" in
    resolves) [ "$NC_RC" = 0 ] && jq -e '.base_branch == "main"' "$sc" >/dev/null 2>&1 \
      || { LEG_MSG="acquire rc $NC_RC, base_branch '$(jq -r '.base_branch // empty' "$sc" 2>/dev/null)': $(head -c 160 "$CASE_DIR/nc.err")"; return 1; } ;;
    unresolved) [ "$NC_RC" = 1 ] && [ -z "$NC_OUT" ] && grep -qF base_branch_unresolved "$CASE_DIR/nc.err" \
      || { LEG_MSG="acquire rc $NC_RC, printed '$(printf '%s' "$NC_OUT" | head -c 80)': $(head -c 160 "$CASE_DIR/nc.err")"; return 1; } ;;
  esac
}
for b20c in resolves unresolved; do
  LEG_MSG=""
  if b20_acquire "$DRIVER" "$b20c"; then ok "B20: acquire with no recorded base ⇒ $b20c (the resolver, called only when the state value is empty)"
  else no "B20: acquire $b20c: $LEG_MSG"; fi
done

echo "-- V. Validation 3: one item from Phase 0 to the Phase 4.5 hand-over (hermetic)"
if golden_case validation-3-drive "$DRIVER"; then
  seq3="$(grep -v '^\$ call\|^= ' "$CASE_DIR/stream.out" | jq -r '"\(.do) \(.step)"')"
  if [ "$(printf '%s\n' "$seq3" | tail -n 1)" = "done handover" ] \
     && printf '%s' "$LAST_OUT" | jq -e '.base_verify == "verified" and .children_check == "settled"' >/dev/null 2>&1; then
    ok "V: Phase 0 → hand-over in $(printf '%s\n' "$seq3" | wc -l | tr -d ' ') instructions; the guard denied the push before write-marker and allowed it after; base verified"
  else no "V: the drive did not end at a verified hand-over: $(printf '%s' "$LAST_OUT" | head -c 200)"; fi
  if [ "${SN_V3_PRINT:-}" = 1 ]; then printf '%s\n' "$seq3" | sed 's/^/    v3: /'; fi
else no "V: validation-3-drive: $GC_MSG"; fi

echo "-- K. brace expansion off (bash 3.2)"
LEG_MSG=""
if leg_brace_off "$DRIVER"; then ok "K: the driver runs with set +B$( [ "$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)" = 3 ] && printf ' and its orchestrator spawn is well-formed under /bin/bash 3.x')"
else no "K: $LEG_MSG"; fi

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
  # M2a — the publish spawn printed before write-marker ran ⇒ P red
  if m="$(build_mutant 2a '  [ "$(st children_check)" = skipped ] && args=(--skip-children-check)' '  sn_publish; return 0')"; then
    golden_case finalize-marker-written "$m" >/dev/null 2>&1
    [ "$PUB_SEEN" -gt 0 ] && [ -n "$PUB_BAD" ] && ok "M2a: the publish spawn before write-marker ⇒ P red" || no "M2a: P stayed green (seen $PUB_SEEN)"
  else no "M2a: mutant not built"; fi
  # M2c — no step-6.5 retry: the first gh failure sets the mismatch flag ⇒ A4 (and G) red
  if m="$(build_mutant 2c '  sleep "$(sn_retry_seconds)"' '  sn_pr_flag pr-verify "" gh_unavailable_non_interactive; return')"; then
    LEG_MSG=""; if leg_retry_once "$m"; then no "M2c: A4 stayed green without the retry"; else ok "M2c: the retry removed ⇒ A4 red"; fi
    golden_case finalize-pr-base-gh-retry "$m" >/dev/null 2>&1 && no "M2c: the gh-retry golden case stayed green" || ok "M2c: … and the gh-retry golden case goes red"
  else no "M2c: mutant not built"; fi
  # M2d — an interactive adjudication auto-picks option A instead of asking ⇒ A5 red
  if m="$(build_mutant 2d '  sn_ask execute-result "$gate" adjudication_required_non_interactive \' '  sn_emit done execute-result '"'"'{"choice":"A: Re-queue producer"}'"'"'; return 0; : \')"; then
    LEG_MSG=""; if leg_adj_ask "$m"; then no "M2d: A5 stayed green with an auto-pick"; else ok "M2d: an auto-picked adjudication ⇒ A5 red"; fi
  else no "M2d: mutant not built"; fi
  # MB — brace expansion left on ⇒ K red
  if m="$(build_mutant B 'set +B' 'set -B')"; then
    LEG_MSG=""; if leg_brace_off "$m"; then no "MB: K stayed green with brace expansion on"; else ok "MB: brace expansion on ⇒ K red ($LEG_MSG)"; fi
  else no "MB: mutant not built"; fi
  # MG — step 4 back on the exact-line test (git's answer ignored, so the fallback always runs) ⇒ B18 red
  if m="$(build_mutant G '    git check-ignore -q --no-index "$gp" >/dev/null 2>&1' '    (exit 128)')"; then
    LEG_MSG=""; if b18_managed "$m"; then no "MG: B18 stayed green on the exact-line test"; else ok "MG: the exact-line test restored ⇒ B18 red ($LEG_MSG)"; fi
  else no "MG: mutant not built"; fi
  # MBA — init's resolver call replaced by the literal `main` ⇒ B20's development publish red
  if m="$(build_mutant BA '  sn_resolve_base "$jp" || return 1' '  SN_BASE=main')"; then
    LEG_MSG=""; if b20_dev "$m"; then no "MBA: B20 stayed green with init's base hardcoded to main"; else ok "MBA: init's base hardcoded to main ⇒ B20 red ($LEG_MSG)"; fi
  else no "MBA: mutant not built"; fi
  # MBB — the resolver call drops the brief (`--brief`) ⇒ B20's invalid-brief stop red
  if m="$(build_mutant BB '--brief "$1" ' '')"; then
    LEG_MSG=""; if b20_stop "$m" invalid; then no "MBB: B20 stayed green with the brief not passed to the resolver"; else ok "MBB: the brief not passed ⇒ B20 invalid-brief red ($LEG_MSG)"; fi
  else no "MBB: mutant not built"; fi
  # MR — the plan step spawns code-reviewer instead of orchestrator ⇒ R red
  if m="$(build_mutant R 'sn_spawn plan orchestrator plan-result' 'sn_spawn plan code-reviewer plan-result')"; then
    LEG_MSG=""; if leg_reviewer "$m" "$INSTR"; then no "MR: R stayed green with a code-reviewer spawn"; else ok "MR: a code-reviewer spawn ⇒ R red ($LEG_MSG)"; fi
  else no "MR: mutant not built"; fi
fi

echo "PASS: $pass FAIL: $fail"
[ "$fail" -eq 0 ]
