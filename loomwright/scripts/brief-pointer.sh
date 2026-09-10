#!/usr/bin/env bash
# brief-pointer.sh — THE one parser for a Supervisor brief's source-requirement
# pointer, and the containment gate that turns that pointer into a path a script
# may safely read or write.
#
# SOURCED, NEVER EXECUTED. Callers do:
#   script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
#   [ -r "$script_dir/brief-pointer.sh" ] && . "$script_dir/brief-pointer.sh"
# It defines functions and one prefix constant; it runs nothing and writes
# nothing at source time.
#
# WHY THIS EXISTS
# ---------------
# Launch Pad stamps ONE field under a brief's `## Environment` heading:
#     - **Source requirement:** <repo-root-relative path>
# and two lifecycle reconcilers read it — reconcile-jobs.sh (brief lifecycle) and
# stamp-requirement-status.sh (requirement close-out). They were written a month
# apart and each grew its own parse, so they disagreed about what the field says.
# Measured 2026-09-10 over the three briefs then in `.supervisor/jobs/in-progress/`:
# a backticked pointer resolved in the stamper and NOT in the reconciler; a
# backticked pointer with a trailing parenthetical resolved in NEITHER. One of
# those briefs' work had merged five days earlier and was stranded on a backtick.
#
# The root cause is mirror drift, not a typo: one producer, two consumers, and a
# producer contract that says "repo-root-relative path" and nothing about styling.
# Briefs are agent-written prose, so tightening the producer cannot retire the
# corpus that already exists. The consumers must be tolerant, and there must be
# exactly ONE of them. That is this file.
#
# TOLERATED SHAPES (measured against the real corpus, not imagined)
#   * bare path                       .supervisor/requirements/x/01-y.md
#   * wrapped in backticks/quotes     `…`   "…"   '…'
#   * trailing annotation             `…/01-y.md` (amended at intake — see …)
#   * label case and spacing          `- **Source requirement:**`, `**source
#                                     requirement:**`, leading whitespace, no `- `
#
# HONEST LIMIT, STATED RATHER THAN GUESSED AROUND. The path is taken as the
# pointer's FIRST whitespace-delimited token after delimiter stripping. An
# annotation that is NOT whitespace-separated from the path — `…/05-archive-views.md(amended)`
# — is therefore unreadable: the token carries the annotation, and the `-f` check
# refuses it. No brief in the corpus has that shape, and no heuristic guesses at
# prose structure here. A pointer that cannot be read is refused, never assumed.
#
# TWO DELIBERATE DIVERGENCES FROM NEARBY PRECEDENT — recorded here so neither is
# later "corrected" into a regression:
#
#   1. LOCATION: callers find this file by a plain `dirname "$0"` sibling lookup,
#      NOT by a harness-specific plugin-root variable. Both consumers, their
#      tests and this file all sit at allowance 0 in
#      loomwright/docs/vendor-coupling-manifest.json, and scripts/check-vendor-coupling.sh
#      is a hard CI gate with no `|| true`. The resolution ladders in
#      validate-entry.sh / add-rule.sh are GRANDFATHERED DEBT (allowances 8 and 3),
#      not the sanctioned idiom; session-resume.sh's sibling lookup is.
#
#   2. FAILURE MODE: a caller that cannot find this file must SKIP SILENTLY, not
#      refuse loudly. Do NOT import add-rule.sh's fail-CLOSED load guard. That
#      guard is right for a WRITER whose purpose is a validated append — an
#      unvalidated append is the harm it prevents. Both consumers here are the
#      opposite shape: without this helper they perform NO stamp and NO
#      reclassification, i.e. no write at all, so a silent skip already IS the
#      safe outcome. reconcile-jobs.sh additionally runs on every SessionStart,
#      where an error exit would wedge every new session. Per CLAUDE.md's bimodal
#      rule these are runtime side-effect reconcilers (fail SAFE, always exit 0),
#      not correctness gates (fail CLOSED).
#
# FUNCTION NAMES ARE LOAD-BEARING. This file must NOT export `safe_requirement_path`
# — that was reconcile-jobs.sh's own name for its WEAKER containment function.
# Reusing it would make a regression silent: bash's last-definition-wins means a
# surviving local definition below the source line would quietly restore the weak
# guard set while every parsing test stayed green. Distinct names make that
# shadowing structurally impossible.
#
# bash-3.2 / BSD-userland safe: no mapfile, no associative arrays, no GNU-only
# sed/grep flags, no `sed -E` case-insensitivity flag (BSD sed has none).

# The one containment root. Both consumers previously spelled this themselves
# (`REQ_ROOT` without the trailing slash, `REQ_PREFIX` with it) — same rule, two
# copies. This is now the only copy.
BRIEF_REQUIREMENT_PREFIX=".supervisor/requirements/"

# brief_requirement_pointer <brief> — echo the source-requirement pointer with
# markdown delimiters and any trailing annotation removed. Returns non-zero and
# echoes nothing when the brief carries no pointer line (pre-feature briefs and
# direct `/supervisor task:` runs legitimately carry none — that is a silent
# no-op, never an error). Only the FIRST matching line is honoured.
brief_requirement_pointer() {
  local brief="${1:-}" raw ptr
  [ -n "$brief" ] || return 1

  raw="$(grep -m1 -iE '^[[:space:]]*-?[[:space:]]*\*\*Source requirement:\*\*' "$brief" 2>/dev/null)"
  [ -n "$raw" ] || return 1

  # Strip through the label. This matches the line's FIRST `**…**` bolded run
  # rather than the label's own words, on purpose: the grep above has already
  # established that this line IS the pointer line, so matching structure instead
  # of text makes the strip fully case-insensitive without a `sed` `I` flag (BSD
  # sed has none) and without spelling the label out as a character class — the
  # half-measure that let `**SOURCE REQUIREMENT:**` through the grep and then
  # past the strip unchanged.
  ptr="$(printf '%s' "$raw" | sed -E 's/^[^*]*\*\*[^*]*\*\*[[:space:]]*//')"

  # >>> delimiter-strip (AC-8 mutation target) >>>
  # Leading delimiters, then the first whitespace-delimited token, then any
  # trailing delimiter left on that token. Order matters: taking the token FIRST
  # would keep a leading backtick glued to the path, and stripping trailing
  # delimiters only at end-of-LINE (the previous stamper behaviour) leaves a
  # parenthetical annotation attached — it ends in `)`, not in a delimiter.
  ptr="$(printf '%s' "$ptr" | sed -E 's/^[`"'"'"'[:space:]]+//')"
  ptr="${ptr%%[[:space:]]*}"
  ptr="$(printf '%s' "$ptr" | sed -E 's/[`"'"'"']+$//')"
  # <<< delimiter-strip (AC-8 mutation target) <<<

  [ -n "$ptr" ] || return 1
  printf '%s' "$ptr"
}

# brief_requirement_path <pointer> <containment_root> — echo the pointer only
# when it survives EVERY containment guard; otherwise echo nothing and return a
# code naming the guard that refused it (see brief_requirement_reason).
#
# A brief is generated text, therefore UNTRUSTED input. A pointer naming
# `../../../../etc/passwd`, an absolute path, or a symlink would otherwise make a
# caller read or append to an arbitrary file. The last two guards are NOT
# redundant with the first three: those are purely LEXICAL, and `-f` FOLLOWS
# symlinks, so a link planted inside the prefix satisfied all of them while
# resolving to a target outside the root (reproduced before the guard existed).
#
#   <containment_root> is the directory the relative pointer is interpreted
#   against — passed in rather than derived, because the two callers have
#   different notions of it: stamp-requirement-status.sh resolves a repo root and
#   cd's to it, while reconcile-jobs.sh has no root notion at all and simply
#   passes its own cwd. Deriving it here (e.g. via the VCS CLI) would put a
#   subprocess on the SessionStart resume path, which is exactly what that
#   script's offline-by-construction contract forbids.
#
#   EVERY guard resolves the pointer against <containment_root>, NOT against the
#   process cwd, so the sentence above is true by construction rather than by
#   caller discipline. An earlier revision resolved `-L`, `dirname` and `-f`
#   against cwd and used <containment_root> only for the physical-prefix
#   comparison — which meant that a caller whose cwd differed from the root it
#   passed had its existence and symlink checks inspect a DIFFERENT FILE from
#   the one the containment check was reasoning about. Guard (b) happened to
#   refuse that divergence (a spurious refusal, never a bypass), so it was
#   invisible; but "happens to be caught by the next guard" is not a contract,
#   and the docstring was asserting a property the code did not have. Both
#   shipped callers keep cwd == root, so this is byte-identical for them.
#
#   RETURNS the pointer exactly as given — repo-root-RELATIVE. The caller must
#   interpret it against the SAME root it passed in (both shipped callers do,
#   trivially, since their cwd is that root).
#
# RETURN CODES (0 = resolved; anything else = refused, and the caller must be
# able to tell refusal apart from "resolved but unevidenced"):
#   1 empty/absent pointer          5 symlinked final component
#   2 absolute path                 6 unresolvable physically
#   3 `..` segment                  7 physically outside the root
#   4 outside the requirements dir  8 no such regular file
brief_requirement_path() {
  local ptr="${1:-}" root="${2:-}" req_dir root_p abs
  [ -n "$ptr" ] || return 1

  case "$ptr" in /*) return 2 ;; esac
  case "$ptr" in *..*) return 3 ;; esac
  case "$ptr" in
    "${BRIEF_REQUIREMENT_PREFIX}"*) : ;;
    *) return 4 ;;
  esac

  # Anchor the pointer to the ROOT WE WERE GIVEN, once, before any guard looks
  # at the filesystem. Every check below then inspects the same file the
  # containment comparison reasons about, whatever the process cwd happens to
  # be. `${root:-.}` keeps the no-root call meaning "relative to cwd", which is
  # what a bare `.` root has always meant.
  abs="${root:-.}/$ptr"

  # >>> symlink-guard (AC-6 mutation target) >>>
  # (a) `-L` rejects a symlinked FINAL component.
  if [ -L "$abs" ]; then return 5; fi

  # (b) physical resolution of the PARENT catches a symlinked DIRECTORY
  #     component, which (a) cannot see (e.g. `<prefix>/sub -> /etc`, then
  #     `sub/passwd`). Both sides use `pwd -P`, so a symlinked project root
  #     (on macOS `/tmp` -> `/private/tmp`, routinely) is not a spurious mismatch.
  req_dir="$(cd "$(dirname "$abs")" 2>/dev/null && pwd -P)"
  root_p="$(cd "${root:-.}" 2>/dev/null && pwd -P)"
  if [ -z "$req_dir" ] || [ -z "$root_p" ]; then return 6; fi
  case "$req_dir/" in
    "$root_p/${BRIEF_REQUIREMENT_PREFIX}"*) : ;;
    *) return 7 ;;
  esac
  # <<< symlink-guard (AC-6 mutation target) <<<

  [ -f "$abs" ] || return 8
  # Returned RELATIVE, as documented — the caller interprets it against the
  # root it passed. Deliberately not `$abs`: both callers print this value in
  # operator-facing evidence strings, where a repo-relative path is the useful
  # form and an absolute sandbox path is noise.
  printf '%s' "$ptr"
}

# brief_requirement_reason <code> — a human phrase for a brief_requirement_path
# refusal. Exists so the two callers keep reporting WHICH guard fired rather than
# collapsing every refusal onto one indistinguishable message.
brief_requirement_reason() {
  case "${1:-}" in
    2) printf 'absolute requirement path' ;;
    3) printf "'..' segment in requirement path" ;;
    4) printf 'requirement path outside %s' "$BRIEF_REQUIREMENT_PREFIX" ;;
    5) printf 'requirement path is a symlink (a requirement file is never legitimately one)' ;;
    6) printf 'cannot resolve requirement path physically' ;;
    7) printf 'requirement path physically resolves outside %s' "$BRIEF_REQUIREMENT_PREFIX" ;;
    8) printf 'requirement file not found' ;;
    *) printf 'requirement pointer did not resolve' ;;
  esac
}
