#!/usr/bin/env bash
# retention-sweep.sh — the `.supervisor/` retention policy, enforced: one
# recorded verdict per directory, a REPORT-ONLY default, and deletion of NOTHING
# that is not classified exhaust.
#
# WHY THIS EXISTS. Nothing pruned `.supervisor/` (measured 2026-09-12: 21
# directories, 7.8 M of session logs, 737 drain ledgers of which 732 were test
# pollution). The naive fix — age everything out — is worse than the growth,
# because three things in that tree look like garbage and are not: the per-PR
# dispatch markers are idempotency guards durable BY DESIGN; the session logs are
# the input the curation cadence (`curation-status.sh`) counts, so removing old
# ones silently tells you your recorded knowledge is fresh when it is not; and
# five files are tracked and committed — the Twin's accumulated judgment, the
# least distinguishable from exhaust by age. So this is a CLASSIFICATION first
# (the POLICY table below, mirrored in docs/ARCHITECTURE_CONTRACTS.md
# §".supervisor/ retention policy" and held equal by test-retention-sweep.sh)
# and a sweep second, downstream of it.
#
# USAGE   (plugin-relative; run it from the plugin's scripts/ dir or by path)
#   bash scripts/retention-sweep.sh [--project-root <dir>] [--older-than <days>] [--delete]
#   bash scripts/retention-sweep.sh policy
#
#   (default)        REPORT: per directory, the class, the rule and the
#                    consumers; for the two exhaust rows the files that WOULD be
#                    removed (count, bytes, oldest/newest age). Removes nothing.
#   --delete         perform exactly the removal the report lists.
#   --older-than N   age threshold in whole days, default 90. Age is
#                    `find -mtime +N` — strictly MORE than N whole 24-hour
#                    periods, POSIX, no stat(1) flavor. N must match
#                    ^[1-9][0-9]*$: `0`, a leading zero (`08` — bash arithmetic
#                    would read it as octal) or a non-integer is rejected with a
#                    one-line reason and the run falls back to REPORT.
#   --project-root D taken verbatim (as stamp-requirement-status.sh does);
#                    default = `git rev-parse --show-toplevel`, else $PWD. The
#                    tool acts on <root>/.supervisor and nothing else.
#   policy           print the classification as `dir<TAB>class` lines (one per
#                    policy row; the top-level-entries row prints as `.`) — the
#                    machine surface the doc-mirror test compares.
#
# EXIT: ALWAYS 0, on every path including argument errors (a fail-SAFE
#   operator tool under CLAUDE.md §"Failure-Mode Invariants"; an operator's
#   shell `&&` chain must never be broken by a report).
#
# GUARDS, layered, ALL evaluated before the first `rm`:
#   (i)   the candidate's directory must be an `exhaust` row of the POLICY table.
#         The tool never constructs a path under any other row — memory/ and
#         postmortem/ are never even listed as candidates.
#   (ii)  `git -C <root> ls-files --error-unmatch -- <rel>` must return EXACTLY
#         rc 1 (git answered: not tracked). rc 0 ⇒ tracked, kept. ANY other rc —
#         128 for a non-git --project-root, a safe.directory refusal, a corrupt
#         repo — ⇒ "git could not answer" and --delete degrades to REPORT for
#         the whole run. `git` absent ⇒ the same. "Could not answer" is never
#         read as "nothing is tracked". A probe with a nonexistent path runs
#         once up front so the degradation is decided before any rm.
#   (iii) `jq` absent ⇒ the same degradation (curation-status.sh cannot answer
#         the pending set without it, and this tool refuses rather than guess).
#   (iv)  the file must still match the row's glob, be a regular file and not a
#         symlink at deletion time; candidates come ONLY from
#         `find <dir> -maxdepth 1 -type f -name <glob> -mtime +<days>` in
#         exactly that argument order — no recursion, no `-L`.
#   (v)   an unreadable directory or a failed rm is reported per file/dir and
#         never widens. A directory on disk with NO policy row is reported
#         `unclassified — not swept` (the policy fails closed as the plugin
#         grows). Top-level entries are never listed as candidates at all.
#
# THE SESSION-LOG EXCLUSION (consumer honesty). `logs/*.jsonl` older than the
#   threshold are candidates ONLY when their id (basename minus .jsonl) is absent
#   from `curation-status.sh pending-ids` — the union of every log that currently
#   counts toward /dreaming's or /insights' pending number. The sibling script is
#   resolved next to THIS file and run FROM THE TARGET ROOT (it has no root flag
#   and resolves $PWD/.supervisor first); run from the caller's cwd the keep-set
#   would come from the wrong corpus. If it is absent or returns non-zero,
#   `logs/*.jsonl` is reported `not swept: pending set unavailable`. The
#   consequence to know: `curation-state.json`'s consumed.logs keeps the ids of
#   deleted logs as inert members, and /insights' and build-loop-evidence.sh's
#   totals shrink to the retained window — the corpus is conditional on this
#   tool once it has been run with --delete.
#
# PORTABILITY: macOS bash 3.2 + BSD userland AND ubuntu. No `timeout`, no
#   `stat` for the decision (display only, GNU-first then BSD, validated
#   numeric), no `mapfile`, no associative arrays, no `sed -i`, no GNU-only
#   find predicates. `set -u` only — never -e / pipefail (every failure here
#   degrades, none aborts).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURATION="$SCRIPT_DIR/curation-status.sh"
DEFAULT_DAYS=90

IRREVERSIBLE_LINE='retention-sweep: IRREVERSIBLE — .supervisor/ is gitignored and exists only in this checkout; nothing removed here can be recovered.'

# ---- POLICY ------------------------------------------------------------------
# row <dir> <class> <glob> <consumers> <rule>
#   dir        directory name under .supervisor/ (`.` = the top-level entries)
#   class      tracked | guard | consumed | exhaust | "consumed → partial exhaust"
#   glob       `-` for a never-swept row; otherwise the comma-separated
#              -name patterns swept from that directory (exhaust rows ONLY)
#   consumers  what keeps it (prose)
#   rule       what the tool does (prose)
# The doc table in ARCHITECTURE_CONTRACTS.md carries the same rows (dir · class
# · consumers · rule); `policy` prints dir<TAB>class and the mirror test holds
# the two equal in both directions. Only a row whose class contains `exhaust`
# is ever entered by the sweep, and only through its own glob column.
row() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"; }
policy_rows() {
  row memory tracked - '4 tracked files; read-lessons.sh, read-project-memory.sh, /dreaming, build-vault.sh' 'never'
  row postmortem tracked - 'results.jsonl tracked; read-postmortem.sh, curate-postmortem.sh, curation-status.sh' 'never'
  row review-dispatch guard - 'per-PR idempotency marker, dispatch-pr-review.sh' 'never (a PR-closed rule is a separate decision — out of scope)'
  row postmortem-dispatch guard - 'per-PR at-most-once marker, dispatch-pr-postmortem.sh' 'never'
  row worktrees consumed - 'no producer or reader in the plugin; pre-sibling-worktree-era leftover of unknown provenance — retained' 'never'
  row salvage consumed - 'the operator restoring rescued work (worktree-salvage.sh)' 'never — explicitly out of scope'
  row jobs consumed - 'Supervisor lifecycle, reconcile-jobs.sh, stamp-requirement-status.sh, automate-helpers.sh brief-repair, /dreaming, floor/handoff' 'never'
  row requirements consumed - 'user-authored intake; /automate, stamp-requirement-status.sh, brief-pointer.sh' 'never'
  row automate consumed - '/automate RESUME state, reconcile-jobs.sh, build-floor.sh, build-handoff.sh' 'never'
  row autonomous consumed - 'session-resume.sh, build-handoff.sh, notify-desktop.sh, send-webhook.sh, hook-dispatch-on-pr-create.sh' 'never'
  row twin consumed - 'read-system-contract.sh (provenance-gated), /dreaming, build-insights.sh' 'never'
  row history consumed - 'archive: cp copies of state.md at FINALIZE; no runtime reader — retained as provenance, read-only after creation' 'never'
  row insights consumed - 'curation-status.sh (dashboard.md mtime IS the /insights watermark), build-floor.sh' 'never'
  row heal-signal consumed - 'build-insights.sh confusion matrix, build-loop-evidence.sh' 'never'
  row eval consumed - 'build-insights.sh, run-eval.sh' 'never'
  row floor consumed - 'the Floor UI serves it; rebuilt by build-floor.sh' 'never'
  row handoff consumed - '/handoff output; rebuilt by build-handoff.sh' 'never'
  row worker-summaries consumed - 'Execute Manager, /dreaming (N most recent), build-floor.sh, result_block_parser.py' 'never'
  row scratch consumed - 'spike outputs cited from memory/provenance; no runtime reader — retained as provenance' 'never'
  row logs 'consumed → partial exhaust' '*.jsonl,pr-postmortem-dispatch-*.log' 'curation-status.sh, build-insights.sh, build-floor.sh, build-handoff.sh, build-loop-evidence.sh, session-resume.sh, status-line.sh, telemetry' 'sweep ONLY *.jsonl older than threshold whose id is NOT in curation-status.sh pending-ids, and pr-postmortem-dispatch-*.log older than threshold; review-pr-dispatch-*.log is CONSUMED (build-insights.sh opt-out evidence) and kept; everything else untouched'
  row drain-rounds exhaust '*.json' 'drain-rounds.sh during a drain only (init resets at every drain start); build-floor.sh counts files' 'sweep *.json older than threshold'
  row . consumed - 'Supervisor/engine state and config (config.json, curation-state.json, notify-config.json, state.md) and the session-resume.sh dotfile markers' 'never (top-level entries are never listed as candidates)'
}

# ---- helpers -----------------------------------------------------------------
is_uint() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# file_bytes <path> — `wc -c` is POSIX; strip the BSD leading blanks.
file_bytes() { local n; n="$(wc -c < "$1" 2>/dev/null | tr -d ' ')"; is_uint "$n" && printf '%s' "$n" || printf '0'; }

# file_age_days <path> — display only (never the sweep decision, which is
# find -mtime). GNU `stat -c %Y` first, BSD `stat -f %m` fallback, validated
# numeric before arithmetic (the recorded BSD/GNU stat trap). `?` when unknown.
NOW_EPOCH="$(date +%s 2>/dev/null || true)"
file_age_days() {
  local m
  m="$(stat -c %Y "$1" 2>/dev/null || true)"
  is_uint "$m" || m="$(stat -f %m "$1" 2>/dev/null || true)"
  if is_uint "$m" && is_uint "$NOW_EPOCH" && [ "$NOW_EPOCH" -ge "$m" ]; then
    printf '%s' "$(( (NOW_EPOCH - m) / 86400 ))"
  else
    printf '?'
  fi
}

# git_tracked_rc <rel-path> — prints git's exit status for `ls-files
# --error-unmatch` run from the root: 0 tracked, 1 not tracked, anything else
# "could not answer".
git_tracked_rc() {
  git -C "$ROOT" ls-files --error-unmatch -- "$1" >/dev/null 2>&1
  printf '%s' "$?"
}

# ---- argument parsing --------------------------------------------------------
MODE="REPORT"
DAYS="$DEFAULT_DAYS"
ROOT=""
ARG_NOTES=""
note_arg() { ARG_NOTES="${ARG_NOTES}retention-sweep: $1
"; }

if [ "${1:-}" = "policy" ]; then
  policy_rows | cut -f1,2
  exit 0
fi
case "${1:-}" in
  -h|--help|help)
    printf 'usage: retention-sweep.sh [--project-root <dir>] [--older-than <days>] [--delete] | policy\n'
    exit 0 ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --delete) MODE="DELETE" ;;
    --older-than)
      if [ $# -ge 2 ]; then
        case "$2" in
          ''|*[!0-9]*) note_arg "--older-than '$2' is not a positive integer — REPORT only, threshold stays $DEFAULT_DAYS" ;;
          0*)          note_arg "--older-than '$2' is rejected (zero, or a leading zero bash arithmetic would read as octal) — REPORT only, threshold stays $DEFAULT_DAYS" ;;
          *)           DAYS="$2" ;;
        esac
        shift
      else
        note_arg "--older-than needs a value — REPORT only, threshold stays $DEFAULT_DAYS"
      fi ;;
    --project-root)
      if [ $# -ge 2 ]; then ROOT="$2"; shift; else note_arg "--project-root needs a value — REPORT only"; fi ;;
    *) note_arg "unknown argument '$1' — REPORT only" ;;
  esac
  shift
done
if [ -n "$ARG_NOTES" ]; then MODE="REPORT"; fi

# ---- root resolution ---------------------------------------------------------
printf '%s\n' "$IRREVERSIBLE_LINE"
printf '%s' "$ARG_NOTES"

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$ROOT" ] || ROOT="$PWD"
fi
if [ ! -d "$ROOT" ]; then
  printf 'retention-sweep: project root %s is not a directory — nothing done.\n' "$ROOT"
  exit 0
fi
ROOT="$(cd "$ROOT" 2>/dev/null && pwd -P)" || { printf 'retention-sweep: cannot enter the project root — nothing done.\n'; exit 0; }
SUP="$ROOT/.supervisor"
if [ ! -d "$SUP" ]; then
  printf 'retention-sweep: no .supervisor/ under %s — nothing to do.\n' "$ROOT"
  exit 0
fi

# ---- run-wide degradations (all decided BEFORE any rm) -----------------------
DEGRADED=""
degrade() { DEGRADED="${DEGRADED}retention-sweep: not swept: $1
"; }

if ! command -v git >/dev/null 2>&1; then
  degrade "git unavailable — the tracked-file guard cannot run"
else
  probe_rc="$(git_tracked_rc ".supervisor/.retention-sweep-probe-$$-does-not-exist")"
  [ "$probe_rc" = "1" ] || degrade "git could not answer (rc $probe_rc) for $ROOT — is it a git work tree?"
fi
command -v jq >/dev/null 2>&1 || degrade "jq unavailable — curation-status.sh cannot compute the pending set"

if [ -n "$DEGRADED" ] && [ "$MODE" = "DELETE" ]; then
  MODE="REPORT"
  DEGRADED="${DEGRADED}retention-sweep: --delete degraded to REPORT for this run.
"
fi

printf 'retention-sweep: root=%s  mode=%s  older-than=%s days\n' "$ROOT" "$MODE" "$DAYS"
printf '%s' "$DEGRADED"

# ---- pending set (the session-log keep-set) ---------------------------------
TMP="$(mktemp -d 2>/dev/null || true)"
if [ -z "$TMP" ] || [ ! -d "$TMP" ]; then
  printf 'retention-sweep: cannot create a temp dir — nothing done.\n'
  exit 0
fi
trap 'rm -rf "$TMP" 2>/dev/null' EXIT
PENDING="$TMP/pending-ids"
CANDIDATES="$TMP/candidates"
: > "$PENDING"; : > "$CANDIDATES"
PENDING_OK=0
if [ -d "$SUP/logs" ]; then
  if [ -f "$CURATION" ]; then
    # From the TARGET root — the sibling resolves $PWD/.supervisor first.
    ( cd "$ROOT" && bash "$CURATION" pending-ids ) > "$PENDING" 2> "$TMP/pending-ids.err"
    prc=$?
    if [ "$prc" -eq 0 ]; then
      PENDING_OK=1
      if [ -s "$TMP/pending-ids.err" ]; then
        printf 'retention-sweep: logs/: pending set is fail-closed — %s\n' "$(head -1 "$TMP/pending-ids.err")"
      fi
    else
      printf 'retention-sweep: logs/*.jsonl not swept: pending set unavailable (curation-status.sh pending-ids rc %s)\n' "$prc"
    fi
  else
    printf 'retention-sweep: logs/*.jsonl not swept: pending set unavailable (curation-status.sh not found beside this script)\n'
  fi
fi

# ---- pass 1: classify, list, and check every candidate -----------------------
total_files=0; total_bytes=0
policy_rows | while IFS="$(printf '\t')" read -r dir class globs consumers rule; do
  if [ "$dir" = "." ]; then
    printf '.supervisor/ top-level entries: %s — %s [%s]\n' "$class" "$rule" "$consumers"
    continue
  fi
  d="$SUP/$dir"
  if [ ! -d "$d" ]; then
    printf '%s/: %s — %s [absent]\n' "$dir" "$class" "$rule"
    continue
  fi
  printf '%s/: %s — %s [%s]\n' "$dir" "$class" "$rule" "$consumers"
  case "$class" in *exhaust*) ;; *) continue ;; esac
  [ "$globs" != "-" ] || continue
  if ! { [ -r "$d" ] && [ -x "$d" ]; }; then
    printf '  %s/: unreadable — not swept\n' "$dir"
    continue
  fi
  n=0; b=0; oldest=""; newest=""
  oldIFS="$IFS"; IFS=','
  set -f; set -- $globs; set +f
  IFS="$oldIFS"
  for glob in "$@"; do
    if [ "$dir" = "logs" ] && [ "$glob" = "*.jsonl" ] && [ "$PENDING_OK" -ne 1 ]; then
      continue
    fi
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      base="${path##*/}"
      rel=".supervisor/$dir/$base"
      if [ "$dir" = "logs" ] && [ "$glob" = "*.jsonl" ]; then
        id="${base%.jsonl}"
        if grep -qxF -- "$id" "$PENDING"; then printf '  keep (pending for /dreaming or /insights): %s\n' "$rel"; continue; fi   # PENDING-IDS-EXCLUSION
      fi
      trc=1   # overwritten by the guard on the next line; 1 = "git said: not tracked"
      trc="$(git_tracked_rc "$rel")"   # LS-FILES-GUARD
      case "$trc" in
        1) ;;
        0) printf '  keep (tracked by git): %s\n' "$rel"; continue ;;
        *) printf '  keep (git could not answer, rc %s): %s\n' "$trc" "$rel"; printf 'git-rc-%s\n' "$trc" >> "$TMP/degrade-late"; continue ;;
      esac
      bytes="$(file_bytes "$path")"
      age="$(file_age_days "$path")"
      printf '  would remove: %s (%s bytes, %s days old)\n' "$rel" "$bytes" "$age"
      printf '%s\t%s\t%s\t%s\n' "$dir" "$glob" "$path" "$bytes" >> "$CANDIDATES"
      n=$((n + 1)); b=$((b + bytes))
      if is_uint "$age"; then
        if [ -z "$oldest" ] || [ "$age" -gt "$oldest" ]; then oldest="$age"; fi
        if [ -z "$newest" ] || [ "$age" -lt "$newest" ]; then newest="$age"; fi
      fi
    done < <(find "$d" -maxdepth 1 -type f -name "$glob" -mtime +"$DAYS" 2>/dev/null)
  done
  printf '  candidates: %s file(s), %s bytes, oldest %s days, newest %s days\n' "$n" "$b" "${oldest:-n/a}" "${newest:-n/a}"
done

# Directories on disk with no policy row — reported, never entered.
for d in "$SUP"/*/ "$SUP"/.*/; do
  [ -d "$d" ] || continue
  name="${d%/}"; name="${name##*/}"
  case "$name" in .|..) continue ;; esac
  if ! policy_rows | cut -f1 | grep -qxF -- "$name"; then
    printf '%s/: unclassified — not swept\n' "$name"
  fi
done

if [ -s "$TMP/degrade-late" ] && [ "$MODE" = "DELETE" ]; then
  MODE="REPORT"
  printf 'retention-sweep: not swept: git could not answer for at least one candidate — --delete degraded to REPORT for this run.\n'
fi

# ---- pass 2: remove (DELETE mode only) ---------------------------------------
if [ "$MODE" = "DELETE" ]; then
  printf 'retention-sweep: removing…\n'
  removed_summary=""
  # One summary line per exhaust ROW of the policy (never a hard-coded dir
  # list — the row verdict is the only thing that admits a directory here).
  for dir in $(policy_rows | awk -F'\t' '$2 ~ /exhaust/ {print $1}'); do
    rn=0; rb=0; rf=0
    while IFS="$(printf '\t')" read -r cdir glob path bytes; do
      [ "$cdir" = "$dir" ] || continue
      base="${path##*/}"
      # Guard (iv), re-evaluated at deletion time.
      case "$base" in $glob) ;; *) printf '  skipped (no longer matches %s): %s\n' "$glob" "$path"; continue ;; esac
      if [ -L "$path" ] || [ ! -f "$path" ]; then printf '  skipped (not a regular file now): %s\n' "$path"; continue; fi
      if rm -f -- "$path" 2>/dev/null; then
        rn=$((rn + 1)); rb=$((rb + bytes))
      else
        rf=$((rf + 1)); printf '  rm failed: %s\n' "$path"
      fi
    done < "$CANDIDATES"
    removed_summary="${removed_summary}  ${dir}/: removed ${rn} file(s), ${rb} bytes"
    [ "$rf" -eq 0 ] || removed_summary="${removed_summary} (${rf} rm failure(s))"
    removed_summary="${removed_summary}
"
  done
  printf 'retention-sweep: summary — removed per directory:\n%s' "$removed_summary"
else
  cn="$(grep -c . "$CANDIDATES" 2>/dev/null)"; is_uint "$cn" || cn=0
  printf 'retention-sweep: summary — %s candidate file(s); nothing removed (report-only; pass --delete to remove the files listed above)\n' "$cn"
fi
exit 0
