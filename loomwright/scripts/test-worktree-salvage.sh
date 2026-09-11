#!/usr/bin/env bash
# test-worktree-salvage.sh — self-tests for worktree-salvage.sh (salvage before
# removal) and its wiring into dispatch-pr-review.sh + the FINALIZE prose. Runs in
# temp dirs only (never touches the real .supervisor/). Exit 0 = all pass, 1 = any
# failure. UNCOUNTED by the doc-currency gate (test-*.sh).
#
# Groups (one per acceptance criterion of the salvage-before-removal brief):
#   AC-1  dirty tracked file → modified/<rel> byte-identical (cmp)
#   AC-2  untracked file (nested path) → untracked/<rel> byte-identical
#   AC-3  BASE_SHA == HEAD; tracked.patch APPLIES on a fresh detached checkout at
#         BASE_SHA and the result equals modified/; a staged new file round-trips
#   AC-3b unborn HEAD (fresh `git init`, no commit, one untracked file): README
#         `status: partial (BASE_SHA failed)` + `BASE_SHA: unknown`, no BASE_SHA
#         file, the untracked file still captured, exit 0 — `git rev-parse HEAD`
#         prints the literal `HEAD` there and must not be recorded as a base
#   AC-4  clean worktree → no directory, no stdout, no stderr, exit 0 (dest absent
#         stays absent; an existing dest gains no entry)
#   AC-5  gitignored .supervisor/ content is not "uncommitted work": ignored-only
#         tree is clean; mixed tree salvages only the real file; README says so
#   AC-6  removal still happens on salvage failure — (a) direct: unwritable --dest
#         (a FILE; a 0555 parent) on a DIRTY tree → exit 0, ONE stderr line, nothing
#         created, `git worktree remove --force` still succeeds; (b) FINALIZE-shaped:
#         salvage statement ABSENT (127) then a SEPARATE `git worktree remove` still
#         removes a clean tree; (c) trap path: .supervisor/salvage pre-created as a
#         FILE + the dirtying stub → real dispatcher's trap still removes the sibling,
#         marker exists, lock gone, no salvage dir; (d) absent tool: a dispatcher copy
#         WITHOUT worktree-salvage.sh still dispatches and its trap still removes
#   AC-7  REAL dispatcher + a stub `claude` that dirties the sibling → after the trap:
#         sibling gone, .supervisor/salvage/<name>-<ts>/ holds modified/ + untracked/
#         byte-identical, BASE_SHA == PR head SHA, README `reason: review-drain teardown`
#   AC-7b pre-add cleanup site: a pre-existing DIRTY sibling at the deterministic path
#         (a prior dispatch that hard-crashed) is salvaged with `reason: dispatch
#         pre-add cleanup` and the dispatch still completes (marker + stub ran) — the
#         only assertion that distinguishes SALVAGE_BIN resolved ABOVE site 1 from
#         one resolved below it under `set -u`
#   AC-7c trap path with RUN_LOG's directory DELETED by the stub before it exits ⇒
#         the salvage STILL runs (capture-then-append; a failed `>>"$_log"` on the
#         call itself would make bash skip it), sibling + lock gone, marker present;
#         in-suite mutant re-applies the pre-fix redirect form ⇒ AC-7c RED, AC-7 GREEN
#   AC-8  README: literal BASE_SHA, "will NOT apply to current" + "main", the
#         `git checkout -b salvage-` … `git apply tracked.patch` incantation, and
#         modified/ mentioned at a lower line than tracked.patch
#   AC-9  no collision: two worktrees → distinct dirs; TS pinned + <name>-<ts> and
#         -2 pre-created → lands in -3; TS='../../evil' ignored (lands under the
#         normal name, nothing at <dest>/../../evil*); 999-cap fall-through → exit 0,
#         one stderr line, no new entry
#   AC-10 mutation control: a COPY of worktree-salvage.sh with the capture
#         short-circuited (`exit 0` after the SALVAGE_MUTANT_ANCHOR line), gated
#         non-empty + cmp-different + `bash -n`, copied WITH its two `dirname "$0"`
#         siblings (dispatch-pr-review.sh, worktree-audit.sh): AC-1, AC-2, AC-7 and
#         AC-7b go RED against it; AC-4 stays GREEN (positive control)
#   AC-11 static seams: exactly 3 NON-COMMENT `worktree remove --force` lines in the
#         dispatcher, each preceded within 5 lines by a non-comment `bash "$…` call
#         carrying that site's `--reason "…"` literal; every `git worktree remove` in
#         async-orchestration + workflow-management has a salvage line directly above;
#         the FINALIZE step-4 salvage line sits above its remove; in-suite mutant
#         comments out the trap's salvage call in a scratch copy ⇒ dispatcher seam RED
#   AC-12 untracked NESTED REPOSITORY (`?? nested/` — an untracked dir reaches the
#         stream only when git refuses to descend into it): copied verbatim to
#         untracked/nested/ — file.txt cmp-identical, its own .git present, README
#         "Nested repositories" item, `status: complete`; in-suite mutant re-applies
#         the pre-fix silent `continue` ⇒ AC-12 RED, AC-1 GREEN (positive control)
#   AC-13 MODIFIED SUBMODULE (real `git submodule add` of a local repo committed on
#         BASE, then a commit inside it ⇒ ` M sub_mod`): NOT under modified/, the patch
#         carries `Subproject commit`, README item names the submodule, `status:
#         complete`
#   AC-14 RENAME entries in the -z stream (`R  new\0old\0`): `git mv a.txt b.txt` +
#         `git mv ab/sub/b.txt c.txt` FOLLOWED by a modified z.txt ⇒ modified/b.txt,
#         modified/c.txt, modified/z.txt present; modified/a.txt absent; and NO phantom
#         modified/sub/b.txt (the second origin is shaped so that, read as a record of
#         its own, it names a real UNMODIFIED file — the only observable trace of an
#         unconsumed origin field; z.txt alone does not discriminate); in-suite mutant
#         drops the origin read ⇒ AC-14 RED (phantom appears), AC-1 GREEN
#
# Bash-3.2/BSD-safe: no `timeout`, no `${var//…}` on large strings, `"$@"` under
# `set -u`. The Bash tool's shell is zsh — run this as `bash test-worktree-salvage.sh`.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SALVAGE="$HERE/worktree-salvage.sh"
DISPATCH="$HERE/dispatch-pr-review.sh"
AUDIT="$HERE/worktree-audit.sh"
ASYNC_SKILL="$HERE/../skills/async-orchestration/SKILL.md"
WORKFLOW_SKILL="$HERE/../skills/workflow-management/SKILL.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

PR="https://github.com/acme/widgets/pull/42"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# ----------------------------------------------------------------------------
# Direct-call fixtures
# ----------------------------------------------------------------------------

# fresh_wt <tag> — a temp repo with a gitignored .supervisor/, two tracked files
# (a.txt, sub/b.txt), and a detached worktree `wt` at HEAD. Sets FX_D, FX_REPO,
# FX_WT. All paths canonicalized via pwd -P (macOS /var vs /private/var).
fresh_wt() {
  local tag="${1:-wt}"
  FX_D="$(mktemp -d)"
  FX_D="$(cd "$FX_D" && pwd -P)"
  FX_REPO="$FX_D/repo"
  FX_WT="$FX_D/$tag"
  mkdir -p "$FX_REPO"
  ( cd "$FX_REPO"
    git init -q
    git config user.email t@t.t; git config user.name t
    git config commit.gpgsign false
    printf '.supervisor/\n' > .gitignore
    printf 'a\n' > a.txt
    mkdir -p sub; printf 'b\n' > sub/b.txt
    git add -A; git commit -qm base
    git worktree add -q --detach "$FX_WT" HEAD
  ) >/dev/null 2>&1
}

# dirty_wt <wt> — one modified tracked file (a.txt) + one nested untracked file
# (new/dir/f.txt). Writes the expected contents to FX_D/exp-*.
dirty_wt() {
  local wt="$1"
  printf 'changed %%s $x `y` "z"\n' > "$wt/a.txt"
  mkdir -p "$wt/new/dir"; printf 'untracked content\n' > "$wt/new/dir/f.txt"
  cp "$wt/a.txt" "$FX_D/exp-a.txt"; cp "$wt/new/dir/f.txt" "$FX_D/exp-f.txt"
}

# run_salvage <script> <args...> — capture stdout/stderr/rc separately.
run_salvage() {
  local s="$1"; shift
  S_OUT="$(bash "$s" "$@" 2>"$SCRATCH/stderr")"
  S_RC=$?
  S_ERR="$(cat "$SCRATCH/stderr")"
  S_ERR_LINES="$(grep -c . "$SCRATCH/stderr" 2>/dev/null)"
  S_ERR_LINES="${S_ERR_LINES:-0}"
}

# first_salvage_dir <dest> — the single salvage dir under <dest> (or empty).
first_salvage_dir() {
  ls -1d "$1"/*/ 2>/dev/null | head -1 | sed 's:/$::'
}

# ----------------------------------------------------------------------------
# Real-dispatcher harness (copied in shape from test-dispatch-pr-review.sh, not
# sourced): isolated git repo, stub gh answering `pr view`, stub claude pointed at
# via LOOMWRIGHT_CLAUDE_BIN that (by default) DIRTIES its cwd before exiting.
# ----------------------------------------------------------------------------

# fresh_git_repo [--clean-stub|--logs-killing-stub] — sets FX_REPO, FX_BIN,
# FX_HEAD_SHA, FX_CLAUDE_LOG, FX_EXP_HEAD (content the stub writes into head.txt),
# FX_EXP_NOTE (notes/new.md). --logs-killing-stub = the dirtying stub that ALSO
# deletes <repo>/.supervisor/logs (RUN_LOG's directory) before exiting, so the
# wrapper's trap fires with an unwritable $_log (AC-7c).
fresh_git_repo() {
  local clean_stub=0 kill_logs=0
  [ "${1:-}" = "--clean-stub" ] && clean_stub=1
  [ "${1:-}" = "--logs-killing-stub" ] && kill_logs=1
  local d; d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"
  FX_REPO="$d/repo"
  FX_BIN="$d/bin"
  FX_CLAUDE_LOG="$d/claude-calls.log"
  FX_EXP_HEAD="$d/exp-head.txt"
  FX_EXP_NOTE="$d/exp-note.md"
  mkdir -p "$FX_REPO" "$FX_BIN"
  ( cd "$FX_REPO"
    git init -q
    git config user.email t@t.t; git config user.name t
    git config commit.gpgsign false
    printf '.supervisor/\n' > .gitignore
    printf 'base\n' > base.txt
    git add -A; git commit -qm base
    git checkout -q -b feature/x
    printf 'head\n' > head.txt
    git add -A; git commit -qm head
  ) >/dev/null 2>&1
  FX_HEAD_SHA="$( cd "$FX_REPO" && git rev-parse HEAD )"
  mkdir -p "$FX_REPO/.supervisor"
  printf 'fixed by the drain\n' > "$FX_EXP_HEAD"
  printf 'scratch note\n' > "$FX_EXP_NOTE"
  cat > "$FX_BIN/gh" <<GHEOF
#!/usr/bin/env bash
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  printf '{"headRefOid":"%s","headRefName":"feature/x","isCrossRepository":false,"headRepositoryOwner":{"login":"o"}}\n' "$FX_HEAD_SHA"
  exit 0
fi
exit 0
GHEOF
  chmod +x "$FX_BIN/gh"
  if [ "$clean_stub" -eq 1 ]; then
    cat > "$FX_BIN/stub-claude" <<CLEOF
#!/usr/bin/env bash
printf 'cwd=%s args=%s\n' "\$(pwd)" "\$*" >> "$FX_CLAUDE_LOG"
exit 0
CLEOF
  elif [ "$kill_logs" -eq 1 ]; then
    # The DIRTYING stub that then removes RUN_LOG's directory: models a runner (or
    # a concurrent cleanup) that deleted .supervisor/logs/ before the trap runs.
    # The stub's own stdout is already an open fd on the log file, so its rm is
    # not self-harm — only the trap's LATER `>>"$_log"` can fail.
    cat > "$FX_BIN/stub-claude" <<CLEOF
#!/usr/bin/env bash
printf 'cwd=%s args=%s\n' "\$(pwd)" "\$*" >> "$FX_CLAUDE_LOG"
cp "$FX_EXP_HEAD" head.txt
mkdir -p notes && cp "$FX_EXP_NOTE" notes/new.md
rm -rf "$FX_REPO/.supervisor/logs"
exit 0
CLEOF
  else
    # The DIRTYING stub: one modified tracked file + one untracked file in its cwd.
    cat > "$FX_BIN/stub-claude" <<CLEOF
#!/usr/bin/env bash
printf 'cwd=%s args=%s\n' "\$(pwd)" "\$*" >> "$FX_CLAUDE_LOG"
cp "$FX_EXP_HEAD" head.txt
mkdir -p notes && cp "$FX_EXP_NOTE" notes/new.md
exit 0
CLEOF
  fi
  chmod +x "$FX_BIN/stub-claude"
}

# run_real <dispatcher> <repo> <args...> — run a dispatcher for real from the repo.
run_real() {
  local disp="$1" repo="$2"; shift 2
  ( cd "$repo" && PATH="$FX_BIN:$PATH" LOOMWRIGHT_CLAUDE_BIN="$FX_BIN/stub-claude" \
      bash "$disp" "$@" >/dev/null 2>&1 )
  RUN_RC=$?
}

wait_for_no_worktree() {
  local repo="$1" wt="$2" i
  for i in $(seq 1 50); do
    if [ ! -d "$wt" ] && ! ( cd "$repo" && git worktree list 2>/dev/null | grep -qF "$wt" ); then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

pr_hash() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$PR" | shasum | cut -d' ' -f1
  else
    printf '%s' "$PR" | sha1sum | cut -d' ' -f1
  fi
}

expected_wt_path() {
  local repo="$1" short top
  short="$(pr_hash | cut -c1-12)"
  top="$( cd "$repo" && git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$repo" )"
  printf '%s/%s-review-%s' "$(dirname "$top")" "$(basename "$top")" "$short"
}

# salvage_dir_with_reason <repo> <reason> — the salvage dir whose README carries
# `reason: <reason>` (or empty).
salvage_dir_with_reason() {
  local repo="$1" reason="$2" d
  for d in "$repo"/.supervisor/salvage/*/; do
    [ -f "$d/README.md" ] || continue
    if grep -qF "reason: $reason" "$d/README.md"; then printf '%s' "${d%/}"; return 0; fi
  done
  return 1
}

# ----------------------------------------------------------------------------
# Parameterized checks (return 0 = the AC holds) — reused by the mutant group.
# ----------------------------------------------------------------------------

check_ac1() {  # <script>
  local s="$1" dir
  fresh_wt; dirty_wt "$FX_WT"
  run_salvage "$s" "$FX_WT" --dest "$FX_D/dest" --reason "AC-1"
  dir="$(first_salvage_dir "$FX_D/dest")"
  [ "$S_RC" -eq 0 ] && [ -n "$dir" ] && [ -f "$dir/modified/a.txt" ] \
    && cmp -s "$dir/modified/a.txt" "$FX_D/exp-a.txt" \
    && [ "$S_OUT" = "$dir" ]
}

check_ac2() {  # <script>
  local s="$1" dir
  fresh_wt; dirty_wt "$FX_WT"
  run_salvage "$s" "$FX_WT" --dest "$FX_D/dest" --reason "AC-2"
  dir="$(first_salvage_dir "$FX_D/dest")"
  [ "$S_RC" -eq 0 ] && [ -n "$dir" ] && [ -f "$dir/untracked/new/dir/f.txt" ] \
    && cmp -s "$dir/untracked/new/dir/f.txt" "$FX_D/exp-f.txt"
}

check_ac4() {  # <script> — clean tree ⇒ nothing, silent, exit 0
  local s="$1" before after
  fresh_wt
  run_salvage "$s" "$FX_WT" --dest "$FX_D/dest-absent" --reason "AC-4"
  [ "$S_RC" -eq 0 ] && [ -z "$S_OUT" ] && [ -z "$S_ERR" ] && [ ! -e "$FX_D/dest-absent" ] || return 1
  mkdir -p "$FX_D/dest-exists/keep"
  before="$(ls -1 "$FX_D/dest-exists" | wc -l | tr -d ' ')"
  run_salvage "$s" "$FX_WT" --dest "$FX_D/dest-exists"
  after="$(ls -1 "$FX_D/dest-exists" | wc -l | tr -d ' ')"
  [ "$S_RC" -eq 0 ] && [ -z "$S_OUT" ] && [ -z "$S_ERR" ] && [ "$before" = "$after" ]
}

check_ac7() {  # <dispatcher> — real trap path with the dirtying stub
  local disp="$1" wt dir h
  fresh_git_repo
  run_real "$disp" "$FX_REPO" "$PR"
  wt="$(expected_wt_path "$FX_REPO")"
  h="$(pr_hash)"
  wait_for_no_worktree "$FX_REPO" "$wt" || return 1
  [ "$RUN_RC" -eq 0 ] || return 1
  [ -f "$FX_REPO/.supervisor/review-dispatch/$h" ] || return 1
  grep -qF "cwd=$wt" "$FX_CLAUDE_LOG" 2>/dev/null || return 1
  dir="$(salvage_dir_with_reason "$FX_REPO" "review-drain teardown")" || return 1
  [ -f "$dir/modified/head.txt" ] && cmp -s "$dir/modified/head.txt" "$FX_EXP_HEAD" \
    && [ -f "$dir/untracked/notes/new.md" ] && cmp -s "$dir/untracked/notes/new.md" "$FX_EXP_NOTE" \
    && [ "$(cat "$dir/BASE_SHA")" = "$FX_HEAD_SHA" ] \
    && [ "$(basename "$dir" | cut -d- -f1-3)" = "$(basename "$wt")" ]
}

check_ac7b() {  # <dispatcher> — pre-add cleanup site with a pre-existing DIRTY sibling
  local disp="$1" wt dir h
  fresh_git_repo --clean-stub
  wt="$(expected_wt_path "$FX_REPO")"
  ( cd "$FX_REPO" && git worktree add -q --detach "$wt" HEAD ) >/dev/null 2>&1 || return 1
  cp "$FX_EXP_HEAD" "$wt/head.txt"
  mkdir -p "$wt/notes" && cp "$FX_EXP_NOTE" "$wt/notes/new.md"
  run_real "$disp" "$FX_REPO" "$PR"
  h="$(pr_hash)"
  wait_for_no_worktree "$FX_REPO" "$wt" || return 1
  [ "$RUN_RC" -eq 0 ] || return 1
  [ -f "$FX_REPO/.supervisor/review-dispatch/$h" ] || return 1
  grep -qF "cwd=$wt" "$FX_CLAUDE_LOG" 2>/dev/null || return 1
  dir="$(salvage_dir_with_reason "$FX_REPO" "dispatch pre-add cleanup")" || return 1
  [ -f "$dir/modified/head.txt" ] && cmp -s "$dir/modified/head.txt" "$FX_EXP_HEAD" \
    && [ -f "$dir/untracked/notes/new.md" ] && cmp -s "$dir/untracked/notes/new.md" "$FX_EXP_NOTE"
}

check_ac7c() {  # <dispatcher> — trap path with RUN_LOG's directory DELETED before the trap
  local disp="$1" wt dir h
  fresh_git_repo --logs-killing-stub
  run_real "$disp" "$FX_REPO" "$PR"
  wt="$(expected_wt_path "$FX_REPO")"
  h="$(pr_hash)"
  wait_for_no_worktree "$FX_REPO" "$wt" || return 1
  [ "$RUN_RC" -eq 0 ] || return 1
  [ -f "$FX_REPO/.supervisor/review-dispatch/$h" ] || return 1
  [ ! -d "$FX_REPO/.supervisor/review-dispatch/$h.lock" ] || return 1
  grep -qF "cwd=$wt" "$FX_CLAUDE_LOG" 2>/dev/null || return 1
  # The stub really removed the log dir (else the arm is not exercising the class).
  [ ! -e "$FX_REPO/.supervisor/logs" ] || return 1
  dir="$(salvage_dir_with_reason "$FX_REPO" "review-drain teardown")" || return 1
  [ -f "$dir/modified/head.txt" ] && cmp -s "$dir/modified/head.txt" "$FX_EXP_HEAD" \
    && [ -f "$dir/untracked/notes/new.md" ] && cmp -s "$dir/untracked/notes/new.md" "$FX_EXP_NOTE"
}

check_ac12() {  # <script> — untracked nested repository copied verbatim, .git included
  local s="$1" dir
  fresh_wt
  ( cd "$FX_WT" && mkdir nested && cd nested && git init -q \
      && git config user.email t@t.t && git config user.name t && git config commit.gpgsign false \
      && printf 'inner\n' > file.txt && git add -A && git commit -qm inner ) >/dev/null 2>&1 || return 1
  cp "$FX_WT/nested/file.txt" "$FX_D/exp-nested.txt"
  # Pre-condition of the class: git lists the nested repo as ONE `?? nested/` entry.
  ( cd "$FX_WT" && git status --porcelain=v1 -z --untracked-files=all | tr '\0' '\n' | grep -qx '?? nested/' ) || return 1
  run_salvage "$s" "$FX_WT" --dest "$FX_D/dest" --reason "AC-12"
  dir="$(first_salvage_dir "$FX_D/dest")"
  [ "$S_RC" -eq 0 ] && [ -n "$dir" ] && [ -z "$S_ERR" ] \
    && [ -f "$dir/untracked/nested/file.txt" ] && cmp -s "$dir/untracked/nested/file.txt" "$FX_D/exp-nested.txt" \
    && [ -d "$dir/untracked/nested/.git" ] && [ -f "$dir/untracked/nested/.git/HEAD" ] \
    && grep -q '^status: complete$' "$dir/README.md" \
    && grep -q 'Nested repositories' "$dir/README.md" && grep -qF '`.git` included' "$dir/README.md"
}

check_ac14() {  # <script> — staged renames followed by a later modified file; no desync
  local s="$1" dir
  fresh_wt
  # Two more tracked files committed in the worktree itself (detached commit is fine):
  # z.txt (modified AFTER the renames in stream order) and ab/sub/b.txt, whose path
  # read as a record of its own (X='a', Y='b', REL=`sub/b.txt`) names the fixture's
  # real, UNMODIFIED sub/b.txt — a phantom modified/sub/b.txt is the observable
  # trace of an unconsumed origin field.
  ( cd "$FX_WT" && printf 'z\n' > z.txt && mkdir -p ab/sub && printf 'q\n' > ab/sub/b.txt \
      && git add -A && git commit -qm more \
      && git mv a.txt b.txt && git mv ab/sub/b.txt c.txt ) >/dev/null 2>&1 || return 1
  printf 'zz\n' > "$FX_WT/z.txt"
  cp "$FX_WT/z.txt" "$FX_D/exp-z.txt"; cp "$FX_WT/b.txt" "$FX_D/exp-b.txt"
  # Pre-condition of the class: the stream really carries the two-field rename records
  # and the modified z.txt sits AFTER them.
  ( cd "$FX_WT" && git status --porcelain=v1 -z --untracked-files=all | tr '\0' '|' ) > "$SCRATCH/ac14-stream"
  grep -qF 'R  b.txt|a.txt|R  c.txt|ab/sub/b.txt| M z.txt|' "$SCRATCH/ac14-stream" || return 1
  run_salvage "$s" "$FX_WT" --dest "$FX_D/dest" --reason "AC-14"
  dir="$(first_salvage_dir "$FX_D/dest")"
  [ "$S_RC" -eq 0 ] && [ -n "$dir" ] \
    && [ -f "$dir/modified/b.txt" ] && cmp -s "$dir/modified/b.txt" "$FX_D/exp-b.txt" \
    && [ -f "$dir/modified/c.txt" ] \
    && [ ! -e "$dir/modified/a.txt" ] && [ ! -e "$dir/modified/ab" ] \
    && [ -f "$dir/modified/z.txt" ] && cmp -s "$dir/modified/z.txt" "$FX_D/exp-z.txt" \
    && [ ! -e "$dir/modified/sub" ] \
    && [ "$(find "$dir/modified" -type f | wc -l | tr -d ' ')" = "3" ] \
    && grep -q '^status: complete$' "$dir/README.md"
}

# dispatcher_seam_ok <dispatcher> — the AC-11 dispatcher half: every NON-COMMENT
# `worktree remove --force` line has its own NON-COMMENT `bash "$…" … --reason "<site>"`
# call within the 5 lines above it, and there are exactly 3 such sites. Sets N_SITES
# and FOUND_REASONS for the report line; returns 0 when the seam holds.
dispatcher_seam_ok() {
  local disp="$1" SITES N i L
  SITES="$(grep -n 'worktree remove --force' "$disp" | grep -v ':[[:space:]]*#' | cut -d: -f1)"
  N_SITES="$(printf '%s\n' "$SITES" | grep -c . )"
  FOUND_REASONS=""
  for N in $SITES; do
    i=$((N-5))
    while [ "$i" -lt "$N" ]; do
      L="$(sed -n "${i}p" "$disp")"
      # NON-COMMENT lines only: a commented-out call (leading `#`, with or without
      # indentation) must not satisfy the seam. grep -E, not a `case` glob — bash 3.2
      # has no extglob, and `" "*\#*` would also skip a code line with a trailing comment.
      if printf '%s' "$L" | grep -qE '^[[:space:]]*#'; then i=$((i+1)); continue; fi
      case "$L" in
        *'bash "$'*'--reason "dispatch pre-add cleanup"'*)      FOUND_REASONS="$FOUND_REASONS pre-add" ;;
        *'bash "$'*'--reason "dispatch header-write teardown"'*) FOUND_REASONS="$FOUND_REASONS header-write" ;;
        *'bash "$'*'--reason "review-drain teardown"'*)         FOUND_REASONS="$FOUND_REASONS trap" ;;
      esac
      i=$((i+1))
    done
  done
  case "$FOUND_REASONS" in
    *pre-add*header-write*trap*) [ "$N_SITES" -eq 3 ] && return 0 ;;
  esac
  return 1
}

# ============================================================================

echo "== AC-1. dirty tracked file → modified/<rel> byte-identical =="
if check_ac1 "$SALVAGE"; then ok "AC-1: modified/a.txt cmp-identical; stdout is the salvage dir"
else no "AC-1 (rc=$S_RC out='$S_OUT' err='$S_ERR')"; fi

echo "== AC-2. untracked nested file → untracked/<rel> byte-identical =="
if check_ac2 "$SALVAGE"; then ok "AC-2: untracked/new/dir/f.txt cmp-identical, relative path preserved"
else no "AC-2 (rc=$S_RC out='$S_OUT' err='$S_ERR')"; fi

echo "== AC-3. BASE_SHA == HEAD; tracked.patch applies on a fresh checkout at BASE_SHA; staged new file round-trips =="
fresh_wt; dirty_wt "$FX_WT"
printf 'staged but uncommitted\n' > "$FX_WT/staged.txt"
( cd "$FX_WT" && git add staged.txt ) >/dev/null 2>&1
run_salvage "$SALVAGE" "$FX_WT" --dest "$FX_D/dest" --reason "AC-3"
DIR="$(first_salvage_dir "$FX_D/dest")"
HEAD_SHA="$( cd "$FX_WT" && git rev-parse HEAD )"
BASE_OK=0; [ -n "$DIR" ] && [ "$(cat "$DIR/BASE_SHA" 2>/dev/null)" = "$HEAD_SHA" ] && BASE_OK=1
APPLY_OK=0; STAGED_OK=0
if [ -n "$DIR" ] && ( cd "$FX_REPO" && git worktree add -q --detach "$FX_D/apply" "$(cat "$DIR/BASE_SHA")" ) >/dev/null 2>&1 \
   && ( cd "$FX_D/apply" && git apply "$DIR/tracked.patch" ) >/dev/null 2>&1; then
  cmp -s "$FX_D/apply/a.txt" "$DIR/modified/a.txt" && APPLY_OK=1
  [ -f "$FX_D/apply/staged.txt" ] && cmp -s "$FX_D/apply/staged.txt" "$DIR/modified/staged.txt" && STAGED_OK=1
fi
if [ "$S_RC" -eq 0 ] && [ "$BASE_OK" -eq 1 ] && [ "$APPLY_OK" -eq 1 ] && [ "$STAGED_OK" -eq 1 ]; then
  ok "AC-3: BASE_SHA == HEAD; patch applied on detached checkout == modified/; staged new file round-trips"
else no "AC-3 (rc=$S_RC base=$BASE_OK apply=$APPLY_OK staged=$STAGED_OK dir='$DIR' err='$S_ERR')"; fi

echo "== AC-3b. unborn HEAD: status partial (BASE_SHA failed), no BASE_SHA file, untracked file still captured =="
UB_D="$(mktemp -d)"; UB_D="$(cd "$UB_D" && pwd -P)"
mkdir -p "$UB_D/repo"
( cd "$UB_D/repo" && git init -q && git config user.email t@t.t && git config user.name t ) >/dev/null 2>&1
printf 'never committed\n' > "$UB_D/repo/orphan.txt"
run_salvage "$SALVAGE" "$UB_D/repo" --dest "$UB_D/dest" --reason "AC-3b"
DIR="$(first_salvage_dir "$UB_D/dest")"
UB_STATUS=0; [ -n "$DIR" ] && grep -q '^status: partial (BASE_SHA failed)$' "$DIR/README.md" 2>/dev/null && UB_STATUS=1
UB_BASE=0; [ -n "$DIR" ] && [ ! -e "$DIR/BASE_SHA" ] && grep -q '^BASE_SHA: unknown$' "$DIR/README.md" 2>/dev/null && UB_BASE=1
UB_FILE=0; [ -n "$DIR" ] && cmp -s "$DIR/untracked/orphan.txt" "$UB_D/repo/orphan.txt" && UB_FILE=1
if [ "$S_RC" -eq 0 ] && [ "$UB_STATUS" -eq 1 ] && [ "$UB_BASE" -eq 1 ] && [ "$UB_FILE" -eq 1 ]; then
  ok "AC-3b: unborn HEAD ⇒ status: partial (BASE_SHA failed), BASE_SHA: unknown, no BASE_SHA file, untracked/orphan.txt captured, exit 0"
else no "AC-3b (rc=$S_RC status=$UB_STATUS base=$UB_BASE file=$UB_FILE dir='$DIR' err='$S_ERR')"; fi
rm -rf "$UB_D"

echo "== AC-4. clean worktree ⇒ no directory, no stdout, no stderr, exit 0 =="
if check_ac4 "$SALVAGE"; then ok "AC-4: clean tree — absent dest stays absent, existing dest gains no entry, silent, exit 0"
else no "AC-4 (rc=$S_RC out='$S_OUT' err='$S_ERR')"; fi

echo "== AC-5. gitignored .supervisor/ runtime state is not uncommitted work =="
fresh_wt
mkdir -p "$FX_WT/.supervisor/logs" "$FX_WT/.supervisor/scratch"
printf '{}\n' > "$FX_WT/.supervisor/logs/x.jsonl"; printf 'y\n' > "$FX_WT/.supervisor/scratch/y"
run_salvage "$SALVAGE" "$FX_WT" --dest "$FX_D/dest5a"
IGN_ONLY_OK=0; [ "$S_RC" -eq 0 ] && [ -z "$S_OUT" ] && [ -z "$S_ERR" ] && [ ! -e "$FX_D/dest5a" ] && IGN_ONLY_OK=1
printf 'real\n' > "$FX_WT/real.txt"
run_salvage "$SALVAGE" "$FX_WT" --dest "$FX_D/dest5b"
DIR="$(first_salvage_dir "$FX_D/dest5b")"
MIXED_OK=0
if [ -n "$DIR" ] && [ -f "$DIR/untracked/real.txt" ] && [ ! -e "$DIR/untracked/.supervisor" ] \
   && [ "$(find "$DIR/untracked" -type f | wc -l | tr -d ' ')" = "1" ]; then MIXED_OK=1; fi
NOTCAP_OK=0; [ -n "$DIR" ] && grep -q '^## Not captured' "$DIR/README.md" 2>/dev/null \
  && grep -q 'not uncommitted work' "$DIR/README.md" && NOTCAP_OK=1
if [ "$IGN_ONLY_OK" -eq 1 ] && [ "$MIXED_OK" -eq 1 ] && [ "$NOTCAP_OK" -eq 1 ]; then
  ok "AC-5: ignored-only tree is clean; mixed tree salvages only real.txt; README has 'Not captured'"
else no "AC-5 (ignored_only=$IGN_ONLY_OK mixed=$MIXED_OK notcap=$NOTCAP_OK dir='$DIR')"; fi

echo "== AC-6(a). direct: unwritable --dest on a DIRTY tree ⇒ exit 0, ONE stderr line, nothing created, --force still removes =="
fresh_wt; dirty_wt "$FX_WT"
: > "$FX_D/destfile"
run_salvage "$SALVAGE" "$FX_WT" --dest "$FX_D/destfile" --reason "AC-6a"
FILE_OK=0; [ "$S_RC" -eq 0 ] && [ "$S_ERR_LINES" -eq 1 ] && [ -z "$S_OUT" ] && [ -f "$FX_D/destfile" ] \
  && [ ! -s "$FX_D/destfile" ] && FILE_OK=1
RO_OK=1
if [ "$(id -u)" -ne 0 ]; then
  RO_OK=0
  mkdir -p "$FX_D/ro"; chmod 0555 "$FX_D/ro"
  run_salvage "$SALVAGE" "$FX_WT" --dest "$FX_D/ro/salvage" --reason "AC-6a"
  [ "$S_RC" -eq 0 ] && [ "$S_ERR_LINES" -eq 1 ] && [ -z "$S_OUT" ] && [ ! -e "$FX_D/ro/salvage" ] && RO_OK=1
  chmod 0755 "$FX_D/ro"
fi
RM_OK=0; ( cd "$FX_REPO" && git worktree remove --force "$FX_WT" ) >/dev/null 2>&1 && [ ! -d "$FX_WT" ] && RM_OK=1
if [ "$FILE_OK" -eq 1 ] && [ "$RO_OK" -eq 1 ] && [ "$RM_OK" -eq 1 ]; then
  ok "AC-6(a): dest=FILE and dest under 0555 parent — exit 0, one stderr line, nothing created; --force removal still succeeds"
else no "AC-6(a) (file=$FILE_OK ro=$RO_OK rm=$RM_OK err='$S_ERR' lines=$S_ERR_LINES)"; fi

echo "== AC-6(b). FINALIZE-shaped: absent salvage script (127) as a SEPARATE statement, then plain remove still removes a clean tree =="
fresh_wt
ABSENT="$FX_D/no-such-dir/worktree-salvage.sh"
( cd "$FX_REPO"
  bash "$ABSENT" "$FX_WT" --reason "FINALIZE step 4"
  git worktree remove "$FX_WT"
) >/dev/null 2>&1
if [ ! -d "$FX_WT" ] && ! ( cd "$FX_REPO" && git worktree list | grep -qF "$FX_WT" ); then
  ok "AC-6(b): salvage absent (exit 127) did not prevent the separate-statement remove"
else no "AC-6(b): worktree still present after the documented sequence"; fi

echo "== AC-6(c). trap path: .supervisor/salvage is a FILE + dirtying stub ⇒ trap still removes sibling, marker exists, lock gone, no salvage dir =="
fresh_git_repo
: > "$FX_REPO/.supervisor/salvage"
run_real "$DISPATCH" "$FX_REPO" "$PR"
WT="$(expected_wt_path "$FX_REPO")"; H="$(pr_hash)"
REMOVED=0; wait_for_no_worktree "$FX_REPO" "$WT" && REMOVED=1
MARKER=0; [ -f "$FX_REPO/.supervisor/review-dispatch/$H" ] && MARKER=1
LOCK_GONE=0; [ ! -d "$FX_REPO/.supervisor/review-dispatch/$H.lock" ] && LOCK_GONE=1
NO_SALV=0; [ -f "$FX_REPO/.supervisor/salvage" ] && [ ! -d "$FX_REPO/.supervisor/salvage" ] && NO_SALV=1
RAN=0; grep -qF "cwd=$WT" "$FX_CLAUDE_LOG" 2>/dev/null && RAN=1
if [ "$RUN_RC" -eq 0 ] && [ "$REMOVED" -eq 1 ] && [ "$MARKER" -eq 1 ] && [ "$LOCK_GONE" -eq 1 ] && [ "$NO_SALV" -eq 1 ] && [ "$RAN" -eq 1 ]; then
  ok "AC-6(c): salvage failed against the FILE, trap still removed the sibling; marker present, lock gone, no salvage dir"
else no "AC-6(c) (rc=$RUN_RC removed=$REMOVED marker=$MARKER lock_gone=$LOCK_GONE no_salvage=$NO_SALV ran=$RAN)"; fi

echo "== AC-6(d). absent tool: dispatcher copy WITHOUT worktree-salvage.sh still dispatches and its trap still removes =="
NOTOOL="$SCRATCH/notool"; mkdir -p "$NOTOOL"
cp "$DISPATCH" "$NOTOOL/dispatch-pr-review.sh"; cp "$AUDIT" "$NOTOOL/worktree-audit.sh"
fresh_git_repo
run_real "$NOTOOL/dispatch-pr-review.sh" "$FX_REPO" "$PR"
WT="$(expected_wt_path "$FX_REPO")"; H="$(pr_hash)"
REMOVED=0; wait_for_no_worktree "$FX_REPO" "$WT" && REMOVED=1
MARKER=0; [ -f "$FX_REPO/.supervisor/review-dispatch/$H" ] && MARKER=1
LOCK_GONE=0; [ ! -d "$FX_REPO/.supervisor/review-dispatch/$H.lock" ] && LOCK_GONE=1
NO_SALV=0; [ ! -e "$FX_REPO/.supervisor/salvage" ] && NO_SALV=1
if [ "$RUN_RC" -eq 0 ] && [ "$REMOVED" -eq 1 ] && [ "$MARKER" -eq 1 ] && [ "$LOCK_GONE" -eq 1 ] && [ "$NO_SALV" -eq 1 ]; then
  ok "AC-6(d): no worktree-salvage.sh sibling (127 inside || true) — dispatched, marker present, trap removed, lock gone"
else no "AC-6(d) (rc=$RUN_RC removed=$REMOVED marker=$MARKER lock_gone=$LOCK_GONE no_salvage=$NO_SALV)"; fi

echo "== AC-7. REAL dispatcher trap path: dirtying stub ⇒ sibling gone, salvage holds both files, BASE_SHA == PR head, reason: review-drain teardown =="
if check_ac7 "$DISPATCH"; then ok "AC-7: trap salvaged modified/head.txt + untracked/notes/new.md (cmp), BASE_SHA == head SHA, reason: review-drain teardown"
else no "AC-7: trap-path salvage missing or wrong (repo=$FX_REPO)"; fi

echo "== AC-7b. pre-add cleanup site: pre-existing DIRTY sibling salvaged with reason: dispatch pre-add cleanup; dispatch completes =="
if check_ac7b "$DISPATCH"; then ok "AC-7b: stale dirty sibling salvaged (reason: dispatch pre-add cleanup), marker written, stub ran"
else no "AC-7b: pre-add cleanup salvage missing or dispatch did not complete (repo=$FX_REPO)"; fi

echo "== AC-7c. trap path with RUN_LOG's directory DELETED: salvage still runs (capture-then-append), sibling + lock gone, marker present =="
if check_ac7c "$DISPATCH"; then ok "AC-7c: .supervisor/logs gone at trap time — salvage dir still holds both files; worktree removed, lock gone, marker present"
else no "AC-7c: salvage skipped or teardown incomplete with RUN_LOG's directory absent (repo=$FX_REPO)"; fi
# Mutation control for AC-7c: re-apply the pre-fix `… >>"$_log" 2>&1 || true` form
# (a failed redirect makes bash SKIP the simple command) in a scratch copy and
# assert the arm goes RED — otherwise the arm is not discriminating on the class.
MUT7_DIR="$SCRATCH/mutant-ac7c"; mkdir -p "$MUT7_DIR"
cp "$SALVAGE" "$MUT7_DIR/worktree-salvage.sh"; cp "$AUDIT" "$MUT7_DIR/worktree-audit.sh"
awk -v old='  [ -n "$_salvage" ] && bash "$_salvage" "$_wt" --dest "$_mg/.supervisor/salvage" --reason "review-drain teardown" >>"$_log" 2>&1 || true' \
  'index($0, "_out=\"$(bash \"$_salvage\"") > 0 { print old; next } { print }' "$DISPATCH" > "$MUT7_DIR/dispatch-pr-review.sh"
MUT7="$MUT7_DIR/dispatch-pr-review.sh"
MUT7_GATE=0
if [ -s "$MUT7" ] && ! cmp -s "$MUT7" "$DISPATCH" && bash -n "$MUT7" 2>/dev/null \
   && grep -qF -e '--reason "review-drain teardown" >>"$_log" 2>&1 || true' "$MUT7"; then MUT7_GATE=1; fi
if [ "$MUT7_GATE" -eq 1 ]; then
  ok "AC-7c mutant gate: pre-fix redirect form re-applied, non-empty, cmp-different, bash -n clean"
  if check_ac7c "$MUT7"; then no "AC-7c survived the pre-fix redirect form (vacuous: arm does not discriminate)"; else ok "AC-7c RED against the pre-fix redirect form (salvage skipped when \$_log is unwritable)"; fi
  if check_ac7 "$MUT7"; then ok "AC-7 GREEN against the AC-7c mutant (positive control: the mutant only breaks the unwritable-log path)"; else no "AC-7 went red against the AC-7c mutant — mutant broke more than the redirect, not discriminating"; fi
else
  no "AC-7c mutant gate: mutant not usable (empty, identical, syntax error, or old form not re-applied) — control skipped"
fi

echo "== AC-8. README is accurate =="
fresh_wt; dirty_wt "$FX_WT"
run_salvage "$SALVAGE" "$FX_WT" --dest "$FX_D/dest" --reason "AC-8"
DIR="$(first_salvage_dir "$FX_D/dest")"
README="$DIR/README.md"
R_SHA=0; [ -f "$README" ] && grep -qF "$(cat "$DIR/BASE_SHA")" "$README" && R_SHA=1
R_MAIN=0; grep -qF 'will NOT apply to current' "$README" 2>/dev/null && grep -qF 'main' "$README" && R_MAIN=1
R_INC=0; grep -qF 'git checkout -b salvage-' "$README" 2>/dev/null && grep -qF 'git apply tracked.patch' "$README" && R_INC=1
L_MOD="$(grep -nF 'modified/' "$README" 2>/dev/null | head -1 | cut -d: -f1)"
L_PATCH="$(grep -nF 'tracked.patch' "$README" 2>/dev/null | head -1 | cut -d: -f1)"
R_ORDER=0; [ -n "$L_MOD" ] && [ -n "$L_PATCH" ] && [ "$L_MOD" -lt "$L_PATCH" ] && R_ORDER=1
R_FIELDS=0; grep -q '^reason: AC-8$' "$README" 2>/dev/null && grep -q '^status: complete$' "$README" && grep -q '^branch: ' "$README" && R_FIELDS=1
if [ "$R_SHA" -eq 1 ] && [ "$R_MAIN" -eq 1 ] && [ "$R_INC" -eq 1 ] && [ "$R_ORDER" -eq 1 ] && [ "$R_FIELDS" -eq 1 ]; then
  ok "AC-8: README has BASE_SHA literal, 'will NOT apply to current' + main, the checkout/apply incantation, modified/ (line $L_MOD) before tracked.patch (line $L_PATCH), reason/status/branch fields"
else no "AC-8 (sha=$R_SHA main=$R_MAIN incantation=$R_INC order=$R_ORDER fields=$R_FIELDS readme='$README')"; fi

echo "== AC-9. no collision: distinct dirs; pinned TS with -ts and -2 taken ⇒ -3; hostile TS ignored; 999 cap falls through =="
fresh_wt one; dirty_wt "$FX_WT"; D9="$FX_D"; WT1="$FX_WT"
( cd "$FX_REPO" && git worktree add -q --detach "$FX_D/two" HEAD ) >/dev/null 2>&1
printf 'two\n' > "$FX_D/two/a.txt"
run_salvage "$SALVAGE" "$WT1" --dest "$D9/dest"
run_salvage "$SALVAGE" "$FX_D/two" --dest "$D9/dest"
N_DIRS="$(ls -1d "$D9/dest"/*/ 2>/dev/null | wc -l | tr -d ' ')"
DISTINCT_OK=0
if [ "$N_DIRS" = "2" ] && cmp -s "$D9/dest"/one-*/modified/a.txt "$D9/exp-a.txt" \
   && [ "$(cat "$D9/dest"/two-*/modified/a.txt)" = "two" ]; then DISTINCT_OK=1; fi
# pinned TS, <name>-<ts> and <name>-<ts>-2 pre-created ⇒ lands in -3
PIN="20200101T000000Z"
mkdir -p "$D9/pin/one-$PIN" "$D9/pin/one-$PIN-2"
LOOMWRIGHT_SALVAGE_TS="$PIN" run_salvage "$SALVAGE" "$WT1" --dest "$D9/pin"
SUFFIX_OK=0; [ "$S_OUT" = "$D9/pin/one-$PIN-3" ] && [ -f "$D9/pin/one-$PIN-3/modified/a.txt" ] && SUFFIX_OK=1
# hostile TS ignored: lands under the normal name inside --dest; nothing escapes
mkdir -p "$D9/h/dest"
LOOMWRIGHT_SALVAGE_TS='../../evil' run_salvage "$SALVAGE" "$WT1" --dest "$D9/h/dest"
HOSTILE_OK=0
case "$(basename "$S_OUT")" in
  one-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z)
    [ "$(dirname "$S_OUT")" = "$D9/h/dest" ] && [ -d "$S_OUT" ] && ! ls -d "$D9"/evil* "$D9/h"/evil* >/dev/null 2>&1 && HOSTILE_OK=1 ;;
esac
# 999 cap: <name>-<ts> plus -2 … -999 pre-created ⇒ exit 0, one stderr line, no new entry
mkdir -p "$D9/cap/one-$PIN"
i=2; ARGS=""
while [ "$i" -le 999 ]; do mkdir "$D9/cap/one-$PIN-$i"; i=$((i+1)); done
CAP_BEFORE="$(ls -1 "$D9/cap" | wc -l | tr -d ' ')"
LOOMWRIGHT_SALVAGE_TS="$PIN" run_salvage "$SALVAGE" "$WT1" --dest "$D9/cap"
CAP_AFTER="$(ls -1 "$D9/cap" | wc -l | tr -d ' ')"
CAP_OK=0; [ "$S_RC" -eq 0 ] && [ "$S_ERR_LINES" -eq 1 ] && [ -z "$S_OUT" ] && [ "$CAP_BEFORE" = "999" ] && [ "$CAP_AFTER" = "999" ] && CAP_OK=1
if [ "$DISTINCT_OK" -eq 1 ] && [ "$SUFFIX_OK" -eq 1 ] && [ "$HOSTILE_OK" -eq 1 ] && [ "$CAP_OK" -eq 1 ]; then
  ok "AC-9: two worktrees → 2 dirs intact; pinned TS lands in -3; '../../evil' TS ignored; 999 cap → exit 0, one stderr line, no new entry"
else no "AC-9 (distinct=$DISTINCT_OK suffix=$SUFFIX_OK hostile=$HOSTILE_OK cap=$CAP_OK out='$S_OUT' err='$S_ERR' before=$CAP_BEFORE after=$CAP_AFTER)"; fi

echo "== AC-10. mutation control: capture short-circuited ⇒ AC-1/AC-2/AC-7/AC-7b RED, AC-4 GREEN =="
MUT_DIR="$SCRATCH/mutant"; mkdir -p "$MUT_DIR"
cp "$DISPATCH" "$MUT_DIR/dispatch-pr-review.sh"; cp "$AUDIT" "$MUT_DIR/worktree-audit.sh"
awk '{print} /SALVAGE_MUTANT_ANCHOR/{print "exit 0"}' "$SALVAGE" > "$MUT_DIR/worktree-salvage.sh"
MUT="$MUT_DIR/worktree-salvage.sh"
GATE_OK=0
if [ -s "$MUT" ] && ! cmp -s "$MUT" "$SALVAGE" && bash -n "$MUT" 2>/dev/null \
   && [ -f "$MUT_DIR/dispatch-pr-review.sh" ] && [ -f "$MUT_DIR/worktree-audit.sh" ]; then GATE_OK=1; fi
if [ "$GATE_OK" -eq 1 ]; then
  ok "AC-10 gate: mutant non-empty, cmp-different, bash -n clean, copied with both dirname-siblings"
  if check_ac1 "$MUT"; then no "AC-10: AC-1 survived the mutant (vacuous)"; else ok "AC-10: AC-1 RED against the mutant"; fi
  if check_ac2 "$MUT"; then no "AC-10: AC-2 survived the mutant (vacuous)"; else ok "AC-10: AC-2 RED against the mutant"; fi
  if check_ac4 "$MUT"; then ok "AC-10: AC-4 GREEN against the mutant (positive control: harness ran)"; else no "AC-10: AC-4 went red against the mutant — harness broken, not discriminating"; fi
  if check_ac7 "$MUT_DIR/dispatch-pr-review.sh"; then no "AC-10: AC-7 survived the mutant (vacuous)"; else ok "AC-10: AC-7 RED against the mutant"; fi
  if check_ac7b "$MUT_DIR/dispatch-pr-review.sh"; then no "AC-10: AC-7b survived the mutant (vacuous)"; else ok "AC-10: AC-7b RED against the mutant"; fi
else
  no "AC-10 gate: mutant not usable (empty, identical, or syntax error) — mutation group skipped"
fi

echo "== AC-11. static seams: 3 non-comment --force sites each preceded by its --reason call; every prose remove has a salvage line above =="
SEAM_OK=0; dispatcher_seam_ok "$DISPATCH" && SEAM_OK=1
# every `git worktree remove` line in the two skills has a salvage line directly above
PROSE_OK=1; PROSE_MISS=""
for F in "$ASYNC_SKILL" "$WORKFLOW_SKILL"; do
  for N in $(grep -n '^[[:space:]]*git worktree remove' "$F" | cut -d: -f1); do
    # The line directly above must be a NON-COMMENT salvage call (same rule as the
    # dispatcher seam — a `# … worktree-salvage.sh …` comment does not satisfy it).
    if ! sed -n "$((N-1))p" "$F" | grep -vE '^[[:space:]]*#' | grep -q 'worktree-salvage.sh'; then PROSE_OK=0; PROSE_MISS="$PROSE_MISS $(basename "$(dirname "$F")"):$N"; fi
  done
done
L_SALV="$(grep -n 'worktree-salvage.sh ../{project}-{subtask_id}' "$ASYNC_SKILL" | head -1 | cut -d: -f1)"
L_RM="$(grep -n 'git worktree remove ../{project}-{subtask_id}' "$ASYNC_SKILL" | head -1 | cut -d: -f1)"
FIN_OK=0; [ -n "$L_SALV" ] && [ -n "$L_RM" ] && [ "$L_SALV" -lt "$L_RM" ] && FIN_OK=1
if [ "$SEAM_OK" -eq 1 ] && [ "$PROSE_OK" -eq 1 ] && [ "$FIN_OK" -eq 1 ]; then
  ok "AC-11 seams: $N_SITES non-comment --force sites each preceded by its --reason call; every prose remove has a salvage line above; FINALIZE salvage (line $L_SALV) precedes remove (line $L_RM)"
else no "AC-11 seams (sites=$N_SITES reasons='$FOUND_REASONS' prose_ok=$PROSE_OK missing='$PROSE_MISS' finalize_salvage=$L_SALV finalize_remove=$L_RM)"; fi
# Mutation control for the comment-skip: comment out the trap's salvage call in a
# scratch copy (siblings beside it) and assert the dispatcher seam goes RED. A seam
# that still reports the commented line as a live call is not a seam.
MUT11_DIR="$SCRATCH/mutant-ac11"; mkdir -p "$MUT11_DIR"
cp "$SALVAGE" "$MUT11_DIR/worktree-salvage.sh"; cp "$AUDIT" "$MUT11_DIR/worktree-audit.sh"
awk 'index($0, "--reason \"review-drain teardown\"") > 0 && $0 !~ /^[[:space:]]*#/ { print "#" $0; next } { print }' \
  "$DISPATCH" > "$MUT11_DIR/dispatch-pr-review.sh"
MUT11="$MUT11_DIR/dispatch-pr-review.sh"
MUT11_GATE=0
if [ -s "$MUT11" ] && ! cmp -s "$MUT11" "$DISPATCH" && bash -n "$MUT11" 2>/dev/null \
   && [ "$(grep -c '^#.*--reason "review-drain teardown"' "$MUT11")" -eq 1 ]; then MUT11_GATE=1; fi
if [ "$MUT11_GATE" -eq 1 ]; then
  ok "AC-11 mutant gate: trap salvage line commented out in a scratch copy (exactly one), non-empty, cmp-different, bash -n clean"
  if dispatcher_seam_ok "$MUT11"; then no "AC-11 seam survived the commented-out trap salvage (comment-skip vacuous; reasons='$FOUND_REASONS')"
  else ok "AC-11 seam RED against the commented-out trap salvage (sites=$N_SITES reasons='$FOUND_REASONS')"; fi
else
  no "AC-11 mutant gate: mutant not usable (empty, identical, syntax error, or not exactly one line commented) — control skipped"
fi

echo "== AC-12. untracked nested repository ⇒ untracked/nested/ verbatim (.git included), README names it, status: complete =="
if check_ac12 "$SALVAGE"; then ok "AC-12: untracked/nested/file.txt cmp-identical, .git/HEAD present, README 'Nested repositories' + '.git included', status: complete, silent"
else no "AC-12 (rc=$S_RC out='$S_OUT' err='$S_ERR')"; fi
# Mutation control: re-apply the pre-fix silent `continue` for an untracked directory
# in a scratch copy and assert AC-12 goes RED while AC-1 stays GREEN.
MUT12_DIR="$SCRATCH/mutant-ac12"; mkdir -p "$MUT12_DIR"
cp "$DISPATCH" "$MUT12_DIR/dispatch-pr-review.sh"; cp "$AUDIT" "$MUT12_DIR/worktree-audit.sh"
awk 'index($0, "IS_NESTED_REPO=1") > 0 && $0 !~ /^[[:space:]]*#/ { print "    continue"; next } { print }' \
  "$SALVAGE" > "$MUT12_DIR/worktree-salvage.sh"
MUT12="$MUT12_DIR/worktree-salvage.sh"
MUT12_GATE=0
if [ -s "$MUT12" ] && ! cmp -s "$MUT12" "$SALVAGE" && bash -n "$MUT12" 2>/dev/null \
   && ! grep -q '^[^#]*IS_NESTED_REPO=1' "$MUT12"; then MUT12_GATE=1; fi
if [ "$MUT12_GATE" -eq 1 ]; then
  ok "AC-12 mutant gate: pre-fix silent continue re-applied, non-empty, cmp-different, bash -n clean"
  if check_ac12 "$MUT12"; then no "AC-12 survived the silent-continue mutant (vacuous)"; else ok "AC-12 RED against the silent-continue mutant (nested repo dropped, status still complete)"; fi
  if check_ac1 "$MUT12"; then ok "AC-1 GREEN against the AC-12 mutant (positive control: only the untracked-directory path is broken)"; else no "AC-1 went red against the AC-12 mutant — mutant broke more than the untracked-directory path"; fi
else
  no "AC-12 mutant gate: mutant not usable (empty, identical, syntax error, or line not replaced) — control skipped"
fi

echo "== AC-13. modified submodule ⇒ not under modified/, patch has Subproject commit, README item, status: complete =="
SM_D="$(mktemp -d)"; SM_D="$(cd "$SM_D" && pwd -P)"
( git init -q "$SM_D/subrepo" && cd "$SM_D/subrepo" \
    && git config user.email t@t.t && git config user.name t && git config commit.gpgsign false \
    && printf 's\n' > s.txt && git add -A && git commit -qm s ) >/dev/null 2>&1
( git init -q "$SM_D/repo" && cd "$SM_D/repo" \
    && git config user.email t@t.t && git config user.name t && git config commit.gpgsign false \
    && printf '.supervisor/\n' > .gitignore && printf 'a\n' > a.txt && git add -A && git commit -qm base \
    && git -c protocol.file.allow=always submodule add -q "$SM_D/subrepo" sub_mod && git commit -qm addsub \
    && cd sub_mod && git config user.email t@t.t && git config user.name t && git config commit.gpgsign false \
    && printf 't\n' > t.txt && git add -A && git commit -qm inner ) >/dev/null 2>&1
SM_PRE=0; ( cd "$SM_D/repo" && git status --porcelain=v1 -z --untracked-files=all | tr '\0' '\n' | grep -qx ' M sub_mod' ) && SM_PRE=1
run_salvage "$SALVAGE" "$SM_D/repo" --dest "$SM_D/dest" --reason "AC-13"
DIR="$(first_salvage_dir "$SM_D/dest")"
SM_NOT_COPIED=0; [ -n "$DIR" ] && [ ! -e "$DIR/modified/sub_mod" ] && SM_NOT_COPIED=1
SM_PATCH=0; [ -n "$DIR" ] && grep -q '^+Subproject commit ' "$DIR/tracked.patch" 2>/dev/null && SM_PATCH=1
SM_README=0; [ -n "$DIR" ] && grep -q 'submodule is a directory and is not copied' "$DIR/README.md" 2>/dev/null \
  && grep -qF '`Subproject commit` line' "$DIR/README.md" && grep -q '^status: complete$' "$DIR/README.md" && SM_README=1
if [ "$S_RC" -eq 0 ] && [ "$SM_PRE" -eq 1 ] && [ "$SM_NOT_COPIED" -eq 1 ] && [ "$SM_PATCH" -eq 1 ] && [ "$SM_README" -eq 1 ]; then
  ok "AC-13: ' M sub_mod' in the stream; nothing under modified/sub_mod; tracked.patch carries '+Subproject commit'; README submodule item present; status: complete"
else no "AC-13 (rc=$S_RC pre=$SM_PRE not_copied=$SM_NOT_COPIED patch=$SM_PATCH readme=$SM_README dir='$DIR' err='$S_ERR')"; fi
rm -rf "$SM_D"

echo "== AC-14. rename records in the -z stream: origin field consumed exactly once, later entries stay in register =="
if check_ac14 "$SALVAGE"; then ok "AC-14: modified/b.txt + c.txt + z.txt (cmp) present, a.txt absent, no phantom sub/b.txt, exactly 3 files, status: complete"
else no "AC-14 (rc=$S_RC out='$S_OUT' err='$S_ERR' stream='$(cat "$SCRATCH/ac14-stream" 2>/dev/null)')"; fi
# Mutation control: drop the origin-field read in a scratch copy — the stream desyncs
# by one record after each rename; the second rename's origin then lands on the
# real, unmodified sub/b.txt as a phantom copy. AC-14 must go RED; AC-1 stays GREEN.
MUT14_DIR="$SCRATCH/mutant-ac14"; mkdir -p "$MUT14_DIR"
cp "$DISPATCH" "$MUT14_DIR/dispatch-pr-review.sh"; cp "$AUDIT" "$MUT14_DIR/worktree-audit.sh"
awk 'index($0, "_ORIGIN || true ;;") > 0 && $0 !~ /^[[:space:]]*#/ { print "    R?|C?|?R|?C) : ;;"; next } { print }' \
  "$SALVAGE" > "$MUT14_DIR/worktree-salvage.sh"
MUT14="$MUT14_DIR/worktree-salvage.sh"
MUT14_GATE=0
if [ -s "$MUT14" ] && ! cmp -s "$MUT14" "$SALVAGE" && bash -n "$MUT14" 2>/dev/null \
   && ! grep -q '^[^#]*_ORIGIN' "$MUT14"; then MUT14_GATE=1; fi
if [ "$MUT14_GATE" -eq 1 ]; then
  ok "AC-14 mutant gate: origin-field read dropped, non-empty, cmp-different, bash -n clean"
  if check_ac14 "$MUT14"; then no "AC-14 survived the dropped-origin-read mutant (vacuous: arm does not discriminate)"; else ok "AC-14 RED against the dropped-origin-read mutant (phantom modified/sub/b.txt from the desynced stream)"; fi
  if check_ac1 "$MUT14"; then ok "AC-1 GREEN against the AC-14 mutant (positive control: a stream without renames is unaffected)"; else no "AC-1 went red against the AC-14 mutant — mutant broke more than rename parsing"; fi
else
  no "AC-14 mutant gate: mutant not usable (empty, identical, syntax error, or line not replaced) — control skipped"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
