# Inverse of comment_bare_excludes.
uncomment_bare_excludes() {
  awk -v mark="$DISABLED_MARK" '
    {
      line = $0
      p = index(line, "   " mark)
      if (p > 0 && substr(line, 1, 2) == "# ") {
        print substr(line, 3, p - 3)
        next
      }
      print line
    }
  '
}

# The canonical managed block.
#
# THE LEDGER LINES ARE EMITTED ASYMMETRICALLY — see ledger_negation_in_block(). An affirmative
# `pass` EMITS them; an affirmative `refuse` BACKED BY REAL EXAMINED SLUGS withdraws them; a
# could-not-examine outcome (jq absent or broken, ledger unreadable, every record unparseable)
# PRESERVES whatever the file already carries. Withdrawing on a diagnosis we never made would
# silently re-ignore a ledger the user deliberately un-ignored and print a contamination message
# naming slugs that do not exist.
#
# BYTE-STABILITY, RESTATED HONESTLY (it is NOT broken — it is a function of one more input). The
# block is a PURE FUNCTION OF (the pre-existing .gitignore contents, the ledger gate outcome). For a
# FIXED gate outcome it is byte-identical across runs, which is exactly what the byte-compare
# idempotency contract requires. But the gate outcome IS an input now, so a repo that applied
# cleanly and LATER gains a foreign record will legitimately rewrite .gitignore on the next apply,
# WITHDRAWING the ledger negation. That transition is correct fail-closed behaviour and do_apply
# ANNOUNCES it — it is never a silent `apply: applied`.
#
# The alternative (emit the ledger lines unconditionally and gate only the verdict) was considered
# and REJECTED: it would have `apply` un-ignore an unfiltered cross-repo ledger, which is precisely
# the failure this gate exists to prevent.
managed_block() {
  printf '%s\n' "$MB_BEGIN"
  if [ -n "${EFFECTIVE_BRANCH:-}" ]; then
    managed_block_branch_mode
    printf '%s\n' "$MB_END"
    return 0
  fi
  cat <<'BLOCK'
# Negate CONTENTS, not the directory. Git cannot re-include a file whose parent directory is
# excluded, so the naive form
#     .claude/
#     !.claude/agent-memory/
# looks correct and silently does NOTHING. The `/*` form below excludes the directory's contents
# and leaves the directory itself traversable, so the `!` lines can re-include.
#
# Committed on purpose: the Twin's accumulated judgment (agent memory + distilled lessons),
# including their dot-prefixed provenance sidecars; the judgement TRAIL — what was asked
# (`.supervisor/requirements/`), what shipped or did not (`.supervisor/jobs/done/`, `jobs/failed/`)
# and how each automation run went (`.supervisor/automate/*.md`); and — when the repo-allowlist
# gate passes — the findings ledger `.supervisor/postmortem/results.jsonl`. Everything else under
# these directories stays ignored: worktree checkouts, machine-local settings, session logs,
# in-flight briefs (`jobs/pending/`, `jobs/in-progress/`), automate sidecars (`*.config-backup.json`),
# the nested `.supervisor/` trees hook emitters leave in any subfolder (a requirements folder,
# a `probes/` dir) when a command ran with its cwd there, and every other file under
# `.supervisor/postmortem/`.
#
# Managed by `/setup memory`. Edit via that command (`/setup memory remove` reverts it);
# hand-edits inside these sentinels are overwritten on the next apply.
.claude/*
!.claude/agent-memory/
.supervisor/*
!.supervisor/memory/
# The judgement trail. Same re-include-the-directory / re-exclude-its-contents / re-include-the-
# wanted-children shape as the ledger below; each `!<dir>/` line is dead without the `.supervisor/*`
# line above it, and pinned as such in test-setup-memory.sh group (t).
!.supervisor/requirements/
# A NESTED `.supervisor/` at ANY depth below the root (`*/**/` needs at least one leading path
# component, so the root store itself never matches): hook emitters write one wherever a command
# ran with its cwd — inside a requirements folder, or any project subfolder (`probes/.supervisor/
# .rules-nudge-shown`). A bare `.supervisor/` ignore used to hide these; `.supervisor/*` only
# matches the root, so without this line moving to the block would suddenly expose them.
*/**/.supervisor/
!.supervisor/jobs/
.supervisor/jobs/*
!.supervisor/jobs/done/
!.supervisor/jobs/failed/
!.supervisor/automate/
.supervisor/automate/*
!.supervisor/automate/*.md
BLOCK
  if ledger_negation_in_block; then
    cat <<'LEDGERBLOCK'
# The findings ledger, un-ignored only because every record's `.repo` is inside this repo's
# allowlist (`setup-memory.sh allowlist`). THREE lines, in THIS ORDER, and AFTER `.supervisor/*`:
# the first re-includes the DIRECTORY so git will descend into it, the second re-excludes its
# CONTENTS so nothing else there leaks, the third re-includes the one file. A single naive
# `!.supervisor/postmortem/results.jsonl` does NOTHING (its parent directory is excluded), and the
# same three lines placed BEFORE `.supervisor/*` do nothing either — both are pinned as negative
# controls in test-setup-memory.sh.
!.supervisor/postmortem/
.supervisor/postmortem/*
!.supervisor/postmortem/results.jsonl
LEDGERBLOCK
  fi
  printf '%s\n' "$MB_END"
}

# managed_block_branch_mode — the BRANCH-MODE body (between the sentinels). It keeps the two memory
# stores and the nested-.supervisor exclude, OMITS every run-history re-include and the ledger lines
# (they live on the metadata branch), and carries the mode line. The default block's "Committed on
# purpose: … the judgement TRAIL" paragraph is false here, so this body replaces it.
managed_block_branch_mode() {
  printf '%s%s\n' "$MODE_PREFIX" "$EFFECTIVE_BRANCH"
  cat <<'BLOCK'
# BRANCH MODE: run history (`.supervisor/requirements/`, `jobs/done/`, `jobs/failed/`,
# `automate/*.md`, the findings ledger) is NOT committed on this branch — it is synced to the
# metadata branch named on the line above by `meta-sync.sh`, and stays ignored here.
#
# Negate CONTENTS, not the directory. Git cannot re-include a file whose parent directory is
# excluded, so the naive form
#     .claude/
#     !.claude/agent-memory/
# looks correct and silently does NOTHING. The `/*` form below excludes the directory's contents
# and leaves the directory itself traversable, so the `!` lines can re-include.
#
# Committed on purpose: the Twin's accumulated judgment (agent memory + distilled lessons),
# including their dot-prefixed provenance sidecars. Everything else under these directories stays
# ignored, including the nested `.supervisor/` trees hook emitters leave in any subfolder.
#
# Managed by `/setup memory`. Edit via that command (`/setup memory remove` reverts it);
# hand-edits inside these sentinels are overwritten on the next apply.
.claude/*
!.claude/agent-memory/
.supervisor/*
!.supervisor/memory/
*/**/.supervisor/
BLOCK
}

# The bare token: ANY line inside the sentinels carrying it that is not exactly a mode line (an
# indented one, `# loomwright-meta-branch:x` with no space) is a near-miss — read_mode says
# `unknown`, never `off`, so a plain apply cannot silently drop a hand-mangled branch mode.
MODE_TOKEN='loomwright-meta-branch'

# read_mode — THE ONE READER of the branch-mode switch. Prints exactly ONE line:
#   off               no .gitignore (or not a regular file), no mode-line text anywhere in it, or a
#                     managed block without a mode line
#   on <branch>       the block's single, valid mode line
#   unknown <reason>  a .gitignore that cannot be read (a mode line cannot be ruled out); or one
#                     that carries mode-line text AND fails gitignore_gate's STRUCTURAL checks
#                     (symlink, NUL bytes, conflict markers, sentinel sanity); more than one mode
#                     line; or a mode line whose branch fails valid_branch_name (the intersection of
#                     `git check-ref-format --branch` unchanged and meta-sync.sh's refs/heads/<name>
#                     check, minus option-shaped/HEAD/@ and the reserved `off` — so `-x` and `off`
#                     read unknown, never `on -x` / `on off` / `off`). A carriage return
#                     (CRLF .gitignore) is shown as a literal `\r` in the reason, never stripped.
#                     An EMPTY branch (`# loomwright-meta-branch: ` and nothing after it) fails
#                     valid_branch_name too, so it reads `unknown`, never `off`; and any other line
#                     INSIDE the sentinels carrying the bare token (indented, no space after the
#                     colon) is a near-miss mode line ⇒ `unknown`. Token text OUTSIDE the sentinels
#                     is ignored (a repo that never opted in still reads `off`).
# "off" is decided from CONTENT first, never from the writer's rewrite-safety gate: a repo that
# never opted in (no mode-line text at all) reads `off` even when its .gitignore is read-only,
# conflict-marked or otherwise un-rewritable — `unknown` (which ABORTs /automate entry and fails
# trail-pr) fires only when a mode line could plausibly exist. Writability never matters to a reader.
read_mode() {
  local gate lines n b rc=0
  if [ ! -e "$GI" ] || [ ! -f "$GI" ]; then echo "off"; return 0; fi
  if [ ! -r "$GI" ]; then echo "unknown .gitignore is not readable (a mode line cannot be ruled out)"; return 0; fi
  # NO `LC_ALL=C` prefix on these greps, deliberately: read_mode always runs inside a command
  # substitution (a forked subshell), and disposing a temporary LC_ALL there makes bash call
  # setlocale() → libintl → CoreFoundation, which is not fork-safe — Homebrew bash 5.3 on macOS
  # SEGFAULTs in the subshell (`dispose_temporary_env → sv_locale → libintl_setlocale →
  # CFLocaleCopyPreferredLanguages`, exit 139) a few percent of the time, and the reader then
  # printed NOTHING. -qF on these ASCII tokens is locale-independent (a binary match still exits 0).
  # Repo-wide, scripts/check-locale-prefix.sh bans the temp-prefix shape; `env LC_ALL=C` is the safe form.
  grep -qF -- "$MODE_PREFIX" "$GI" 2>/dev/null || rc=$?
  # No exact prefix anywhere: a near-miss shape (no space after the colon) still carries the bare
  # token, so only a file WITHOUT the token at all is decided `off` here.
  if [ "$rc" -eq 1 ]; then rc=0; grep -qF -- "$MODE_TOKEN" "$GI" 2>/dev/null || rc=$?; fi
  case "$rc" in
    0) ;;
    1) echo "off"; return 0 ;;
    *) echo "unknown .gitignore could not be searched for a mode line (grep exited $rc)"; return 0 ;;
  esac
  gate="$(gitignore_gate read)"
  case "$gate" in
    ok) ;;
    *) echo "unknown $gate"; return 0 ;;
  esac
  # One MARKED line per in-block match — `L<value>` for an exact mode line (column 1, the full
  # prefix), `X` for any other in-block line carrying the bare token — so an EMPTY value is still a
  # counted match (`L`), never the empty output that used to read `off`. A failed awk is `unknown`.
  lines="$(awk -v b="$MB_BEGIN" -v e="$MB_END" -v m="$MODE_PREFIX" -v t="$MODE_TOKEN" '
    index($0, b) > 0 { inblk = 1; next }
    inblk && index($0, e) > 0 { inblk = 0; next }
    inblk && index($0, m) == 1 { print "L" substr($0, length(m) + 1); next }
    inblk && index($0, t) > 0 { print "X" }
  ' "$GI" 2>/dev/null)" || { echo "unknown .gitignore could not be parsed for a mode line (awk failed)"; return 0; }
  if [ -z "$lines" ]; then echo "off"; return 0; fi
  case "$lines" in
    X*|*$'\n'X*) echo "unknown a malformed mode line in the managed block (not exactly '${MODE_PREFIX}<branch>' at column 1)"; return 0 ;;
  esac
  n="$(printf '%s\n' "$lines" | wc -l | tr -d ' ')"
  if [ "$n" -gt 1 ]; then echo "unknown $n mode lines in the managed block"; return 0; fi
  b="${lines#L}"
  if ! valid_branch_name "$b"; then
    echo "unknown invalid branch name '${b//$'\r'/\\r}' in the mode line"; return 0
  fi
  echo "on $b"
}

# normalize_mode <answer> — FAIL-CLOSED shape check on a reader answer: prints `off` only for an
# exact `off`, `on <b>` only for a valid <b>, and `unknown <reason>` for EVERYTHING else (empty
# output from a crashed/killed reader, garbage, `on ` with an empty/invalid branch). Never maps an
# unrecognised answer to `off` — that is the fail-open the writer used to have (a plain apply then
# rewrote a branch-mode block as the default one). One line out, always.
normalize_mode() {
  local m="${1-}" b
  case "$m" in
    off) echo "off" ;;
    "on "*)
      b="${m#on }"
      # A multi-line answer is never a valid mode, whatever its first line says: fail closed to
      # `unknown`, truncated at the first newline like the arms below (one line out, always).
      if [ "$b" != "${b%%$'\n'*}" ]; then
        b="${b%%$'\n'*}"; echo "unknown mode reader returned a multi-line answer (first line 'on ${b//$'\r'/\\r}')"
      elif valid_branch_name "$b"; then echo "on $b"
      else echo "unknown mode reader returned an invalid branch '${b//$'\r'/\\r}'"; fi ;;
    "unknown "*) printf '%s\n' "${m%%$'\n'*}" ;;
    *) m="${m%%$'\n'*}"; echo "unknown mode reader returned '${m//$'\r'/\\r}'" ;;
  esac
}

# EFFECTIVE_BRANCH — the branch the block apply WOULD write names ("" = mode off). --branch-mode
# wins; otherwise the mode line already in the block is PRESERVED (a plain `apply` must never
# silently re-include run history in a branch-mode repo). Resolved once, in this shell, before the
# subcommand runs (apply / check / mode only), so every nested command substitution of
# managed_block sees the same answer.
CURRENT_MODE=""
EFFECTIVE_BRANCH=""
resolve_effective_branch() {
  # SCOPED to the subcommands that consult $CURRENT_MODE / $EFFECTIVE_BRANCH: `mode` prints it,
  # `apply` writes from it, `check` renders its disclosure from it. `remove` deliberately does NOT —
  # it never writes a block, and its post-write verify must describe the file it just wrote
  # (render_report reads the disk mode itself), not the mode it just deleted. `allowlist` /
  # `filter-ledger` never touch .gitignore at all, so they never run read_mode.
  case "$SUBCMD" in apply|check|mode) ;; *) return 0 ;; esac
  CURRENT_MODE="$(normalize_mode "$(read_mode)")"
  if [ "$BRANCH_MODE_SET" = 1 ]; then
    [ "$BRANCH_MODE_VAL" = "off" ] && EFFECTIVE_BRANCH="" || EFFECTIVE_BRANCH="$BRANCH_MODE_VAL"
    return 0
  fi
  # Exhaustive over normalize_mode's three shapes; `unknown` writes nothing (do_apply aborts on it).
  case "$CURRENT_MODE" in
    off) EFFECTIVE_BRANCH="" ;;
    "on "*) EFFECTIVE_BRANCH="${CURRENT_MODE#on }" ;;
    *) EFFECTIVE_BRANCH="" ;;
  esac
}
