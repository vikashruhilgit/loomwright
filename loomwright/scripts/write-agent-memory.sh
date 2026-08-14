#!/usr/bin/env bash
# write-agent-memory.sh — the SOLE WRITER for the .claude/agent-memory/<agent>/ stores, and the
# OWNER of each store's MEMORY.md index.
#
# (New file — the sixth sole writer. Cloned from add-orientation.sh's sole-writer discipline:
#  slug containment, hard REJECT of hostile input, temp-file + atomic-mv writes, read-back verify,
#  confirm-only human gate. Wired to the shared write-time validator like the other five.)
#
# WHY THIS EXISTS. Every other curated store already had a sanctioned write path; agent memory did
# not, so its only writes were hand-pasted. A hand-pasted store drifts from its own index the first
# time someone adds a file and forgets the pointer, and that is exactly what happened: one store
# reached 18 files with a single index pointer, making 17 files invisible to the agent that owns
# them. The fix is structural rather than procedural — THE INDEX IS NOT MAINTAINED, IT IS REBUILT.
# rebuild_memory_index() re-derives MEMORY.md from the files on disk on EVERY write, so a file can
# only be missing from the index if it is also missing from the directory.
#
# CONSEQUENCE, STATED PLAINLY: this writer OWNS MEMORY.md. Its H1 title line is preserved across
# rebuilds (so a store's human title survives), but everything below that line is regenerated from
# the entry files. Hand-written prose in the body of a MEMORY.md will be replaced on the next
# write. Put durable prose in an entry file, which the index will then point at.
#
# AGENT WRITE PERMISSION. `memory: project` agents may NOT write their own store directly. They
# write PROPOSALS to the gitignored .supervisor/agent-memory-proposals/ (surprise-only — a
# proposal is for something that genuinely surprised the agent, not for every run), and a human
# promotes an approved proposal through this writer:
#     write-agent-memory.sh --proposal .supervisor/agent-memory-proposals/<file>.md --confirm
# Human approval is MECHANIZED, not prose: the confirm-only gate below writes ONLY with --confirm
# or an interactive TTY `y`. Any other invocation is a DRY-RUN that prints the plan and writes
# nothing, so an automated non-TTY run can never mutate a store.
#
# THE QUEUE NOW HAS AN AUTOMATIC CONSUMER. Six agent prompts and AGENT_GUIDELINES instruct
# WRITING proposals here; this writer PROMOTES one; and `/dreaming` SURFACES the pending ones the
# same way it surfaces the orientation queue — its GATHER step lists the `*.md` files under the
# gitignored `.supervisor/agent-memory-proposals/` and offers each for per-item promotion labeled
# `PROMOTE PENDING PROPOSAL`, invoking this writer as `--proposal <file> --confirm` on Accept and
# deleting the proposal file (without writing) on Reject. See commands/dreaming.md §"Pending
# agent-memory proposals (promotion queue)". Listing that directory by hand is now a fallback,
# not the only path — and an ABSENT directory remains the normal empty case, never an error.
#
# WRITE-TIME VALIDATION (decision (a) of the write-time-validation brief). Every write is handed to
# the shared validator first — see validate-entry.sh's LOAD GUARD CONTRACT. The guard here is three
# clauses, all required:
#   (i)   `. validate-entry.sh` must exit 0. `|| true` IS FORBIDDEN on that line: it would discard
#         the status and let a broken helper fall through into a silent UNVALIDATED APPEND, which
#         is the one failure mode this design does not sanction. The status is captured with an
#         explicit `set +e`/`rc=$?` instead — that is the opposite of discarding it.
#   (ii)  all five validator functions must be present (`command -v` each). Bash defines every
#         function ABOVE a syntax error before aborting the parse, so a truncated helper leaves
#         SOME validators defined and a one-function probe would report "examined and clean" over
#         half a validator.
#   (iii) $VALIDATE_ENTRY_CONTRACT must equal the literal this file expects. The literal is
#         HARDCODED here on purpose. Comparing against a variable the helper itself exports (or
#         iterating a function list it exports) would be circular: those are assigned ABOVE the
#         sentinel, so a truncated copy could define them and pass its own test.
# Any shortfall is a named, greppable refusal — REFUSE_VALIDATOR_UNAVAILABLE — and NOTHING is
# written. A refusal is already this design's documented failure mode, so a broken helper degrades
# into sanctioned behaviour rather than into a crash or an unvalidated append.
#
# WHAT THE VALIDATOR IS COMPARED AGAINST — the corpus, NOT the index. This writer's store is a
# DIRECTORY of entry files rather than one file whose lines are entries. (This comment used to say
# it was the only one of the six, and that "the other five hand --store the file that holds full
# entry text, so their comparison is apples-to-apples". BOTH halves were false: add-orientation.sh
# stores a directory of memo documents and write-system-contract.sh a directory of per-subsystem
# artifacts, and each handed --store the single DOCUMENT it was about to write — the same shape
# defect described below, measured at 26% and 17% for a document compared against ITSELF. Both now
# build their own corpus the same way, and validate-entry.sh refuses the shape outright rather than
# reporting it clean.) Handing this writer's MEMORY.md over is not apples-to-apples: an index line is
# `- [title](slug.md) — description` with the description TRUNCATED to 200 chars, while --entry is
# the full summary+body up to the 4000-char cap. validate_duplicate / validate_contradiction score
# overlap as shared / max(|new|, |stored|), so once an entry has real body content the denominator
# is dominated by the new entry and the numerator is bounded by the truncated index line: the ratio
# collapses toward the length ratio and never reaches the 90 / 60 thresholds. MEASURED, not
# reasoned: with MEMORY.md as --store, a byte-for-byte repost of an existing entry's body under a
# new slug was written with no refusal at all — both checks had silently stopped discriminating.
# So build_compare_corpus() below re-derives a corpus from the store's own entry files, ONE LINE
# PER ENTRY (its `description:` plus its body, flattened), and THAT is what --store points at. One
# line per entry is the shape the validator's `_ve_store_lines` reader expects and the shape the
# three line-per-entry stores (lessons, project memory, rules) already have — the fix is to give
# this store the same shape, not to loosen a threshold. The corpus is built under the $work sandbox (never inside the store), so a refusal
# still leaves the store byte-identical and the EXIT trap removes it on every path.
#
# WORKTREE GUARD (red-team F1, from birth). Refuses to write when the RESOLVED repo root is a
# linked git worktree — a linked worktree's top-level carries a `.git` FILE where the main checkout
# carries a directory. Workers run in worktrees; a store write there diverges and is lost on
# `git worktree remove`. Resolving first and guarding the RESOLVED root (not merely $PWD) means an
# explicit --repo pointing at a worktree is refused too. The NON-GIT-REPO case is deliberately
# PERMISSIVE: like add-orientation.sh, this writer falls back to `pwd` outside a repo (fixtures and
# temp stores are legitimate) — write-lessons.sh's hard refusal there is NOT copied across.
#
# Usage:
#   write-agent-memory.sh <agent-slug> <entry-slug> <summary-line> <body-file-or-'-'>
#                         [--confirm] [--store <dir>] [--repo <dir>]
#                         [--title <text>] [--type <t>] [--source <id>]
#   write-agent-memory.sh --proposal <proposal-file> [--confirm] [--store <dir>] [--repo <dir>]
#
#   defaults: repo = cwd git root (or pwd); store = <repo>/.claude/agent-memory
#             the per-agent store dir is <store>/<agent-slug>, its index <store>/<agent-slug>/MEMORY.md
#   env overrides (for tests): AGENT_MEMORY_STORE_DIR / AGENT_MEMORY_REPO_DIR
#                              WRITE_AGENT_MEMORY_VALIDATOR (path to validate-entry.sh)
#   precedence: flags > env > defaults. Body '-' reads stdin.
#
#   A proposal file is an entry file with its routing in the frontmatter:
#       ---
#       agent: loomwright-loomwright-code-reviewer
#       name: some-entry-slug
#       description: the one-line summary the index will carry
#       source: PR #140
#       ---
#       <body>
#
# Exit: 0 = wrote + verified, OR dry-run (nothing written)
#       1 = REFUSED — examined, and a rule was violated (validation refusal, hostile marker, cap,
#           bad slug). Nothing written.
#       2 = REFUSED — COULD NOT EXAMINE (validator unavailable/partial, unreadable store, absent
#           jq inside a check, missing input). Never reported as clean. Nothing written.
#       3 = REFUSED — the resolved repo root is a git worktree.

set -euo pipefail

PROG="write-agent-memory.sh"
HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || printf '%s' ".")"

# The refusal token for the load guard. Named as a variable as well as printed so the token is
# greppable on disk (the self-reported outputs_verified gate keys on it) and so no call site can
# spell it differently.
REFUSE_VALIDATOR_UNAVAILABLE="REFUSE_VALIDATOR_UNAVAILABLE"

# The refusal token for a store whose entry files cannot all be read. Same greppable-on-disk reason
# as above: a store member that could not be read is a HOLE in the comparison corpus, so the
# duplicate/contradiction verdict would be "clean" over material nobody examined — the exact
# could-not-examine trap, one layer below the validator.
REFUSE_STORE_ENTRY_UNREADABLE="REFUSE_STORE_ENTRY_UNREADABLE"

# Clause (iii) of the LOAD GUARD CONTRACT. HARDCODED — see the header note on why comparing against
# anything the helper exports would be circular.
VALIDATE_ENTRY_CONTRACT_REQUIRED="validate-entry/2"

# The five names clause (ii) requires. Written out here rather than read from the helper's own
# $VALIDATE_ENTRY_FUNCTIONS for the same anti-circularity reason.
VALIDATOR_REQUIRED_FUNCS="validate_duplicate validate_contradiction validate_provenance validate_dead_reference validate_cross_repo_reference validate_entry_advisory_notice"

ENTRY_MAX_CHARS=4000

die()    { printf '%s: %s\n' "$PROG" "$1" >&2; exit "${2:-1}"; }
refuse() { printf '%s: %s — %s\n' "$PROG" "$1" "$2" >&2; exit "${3:-1}"; }

# ---------------------------------------------------------------------------
# Parse args.
# ---------------------------------------------------------------------------
agent_slug=""
entry_slug=""
summary=""
body_src=""
store_arg=""
repo_arg=""
title_arg=""
type_arg=""
source_arg=""
proposal_file=""
confirm=0
pos=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --store)    [ "$#" -ge 2 ] || die "--store requires a value" 2;    store_arg="$2";    shift 2 ;;
    --repo)     [ "$#" -ge 2 ] || die "--repo requires a value" 2;     repo_arg="$2";     shift 2 ;;
    --title)    [ "$#" -ge 2 ] || die "--title requires a value" 2;    title_arg="$2";    shift 2 ;;
    --type)     [ "$#" -ge 2 ] || die "--type requires a value" 2;     type_arg="$2";     shift 2 ;;
    --source)   [ "$#" -ge 2 ] || die "--source requires a value" 2;   source_arg="$2";   shift 2 ;;
    --proposal) [ "$#" -ge 2 ] || die "--proposal requires a value" 2; proposal_file="$2"; shift 2 ;;
    --confirm)  confirm=1; shift ;;
    -h|--help)
      grep -E '^# ' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    --*) die "unknown flag: $1 (see --help)" 2 ;;
    *)
      pos=$((pos + 1))
      case "$pos" in
        1) agent_slug="$1" ;;
        2) entry_slug="$1" ;;
        3) summary="$1" ;;
        4) body_src="$1" ;;
        *) die "too many positional arguments (see --help)" 2 ;;
      esac
      shift ;;
  esac
done

# ---------------------------------------------------------------------------
# Slug containment. REJECT, never sanitize — the write can never escape the store dir.
# Agent slugs carry a ':' in Claude Code's own naming (`loomwright:supervisor`) and a '-' in the
# on-disk plugin form (`loomwright-loomwright-code-reviewer`), so both are permitted; '/' and '..'
# never are. Entry slugs are the stricter [a-z0-9_-] set (the live stores use underscores).
# ---------------------------------------------------------------------------
validate_slug() {
  local s="$1" label="$2" allowed="$3"
  case "$s" in
    "")    refuse "REJECTED" "$label is empty" 1 ;;
    */*)   refuse "REJECTED" "$label may not contain '/': $s" 1 ;;
    *..*)  refuse "REJECTED" "$label may not contain '..': $s" 1 ;;
    .*)    refuse "REJECTED" "$label may not start with a dot: $s" 1 ;;
    -*|*-) refuse "REJECTED" "$label may not start or end with '-': $s" 1 ;;
  esac
  case "$s" in
    memory|readme)
      refuse "REJECTED" "$label '$s' is reserved (it would collide with the store's MEMORY.md / README.md on a case-insensitive filesystem)" 1 ;;
  esac
  case "$allowed" in
    agent) case "$s" in *[!a-z0-9:._-]*) refuse "REJECTED" "$label must be [a-z0-9:._-]+ (no spaces/metachars/uppercase): $s" 1 ;; esac ;;
    entry) case "$s" in *[!a-z0-9_-]*)   refuse "REJECTED" "$label must be [a-z0-9_-]+ (no spaces/metachars/uppercase): $s" 1 ;; esac ;;
  esac
}

# ---------------------------------------------------------------------------
# Frontmatter helpers. Used for BOTH reading a proposal and re-deriving the index from entry files
# already on disk, so the two can never disagree about what a field means.
# ---------------------------------------------------------------------------
fm_field() {   # <file> <key> — the first `key: value` inside the leading --- block
  awk -v k="$2" '
    NR == 1 && $0 == "---" { inf = 1; next }
    inf && $0 == "---"     { exit }
    inf {
      i = index($0, ":")
      if (i > 0) {
        key = substr($0, 1, i - 1); val = substr($0, i + 1)
        gsub(/^[ \t]+|[ \t]+$/, "", key); gsub(/^[ \t]+|[ \t]+$/, "", val)
        if (key == k) { print val; exit }
      }
    }
  ' "$1" 2>/dev/null
}

fm_body() {    # <file> — everything after the closing --- (the whole file when there is no block)
  awk '
    NR == 1 && $0 == "---" { inf = 1; next }
    inf && $0 == "---"     { inf = 0; body = 1; next }
    inf                    { next }
    { print }
  ' "$1" 2>/dev/null
}

first_heading() {   # <file> — the first `# ` heading OUTSIDE the frontmatter block
  awk '
    NR == 1 && $0 == "---" { inf = 1; next }
    inf && $0 == "---"     { inf = 0; next }
    inf                    { next }
    /^# / { sub(/^# /, ""); print; exit }
  ' "$1" 2>/dev/null
}

first_body_line() { # <file> — the first non-blank, non-heading body line
  awk '
    NR == 1 && $0 == "---" { inf = 1; next }
    inf && $0 == "---"     { inf = 0; next }
    inf                    { next }
    /^[[:space:]]*$/ { next }
    /^#/             { next }
    { gsub(/^[ \t]+|[ \t]+$/, ""); print; exit }
  ' "$1" 2>/dev/null
}

one_line() { printf '%s' "${1:-}" | tr '\r\n\t' '   ' | tr -s ' ' | sed -e 's/^ //' -e 's/ $//'; }

# entry_compare_line <file> — the stored entry as ONE comparable line: its frontmatter
# `description:` followed by its whole body, flattened. This is deliberately the SAME text the
# validator is handed for a NEW entry (`$entry_text` = summary + body), which is what makes the
# comparison apples-to-apples; see the corpus note in the header.
#
# ONE awk pass per file, not one per field: the corpus is rebuilt on every write, and this runs
# once per stored entry, so halving the process count here is the difference between a validator
# and a pause on an 18-entry store.
#
# Frontmatter keys OTHER than `description:` are deliberately EXCLUDED. `name:`, `written_at:`,
# `head_sha:` and friends are bookkeeping the new entry's text does not contain, so including them
# would pad the stored token set and depress every score — the same arithmetic that made the index
# comparison useless, reintroduced by the back door.
#
# The leading `#`, `>` and `-` run is stripped because the validator's own store reader skips
# comment/heading lines and strips a list bullet: a body that happens to start with a markdown
# heading would otherwise contribute NO corpus line at all, silently shrinking the corpus.
entry_compare_line() {
  awk '
    NR == 1 && $0 == "---" { inf = 1; next }
    inf && $0 == "---"     { inf = 0; next }
    inf {
      i = index($0, ":")
      if (i > 0) {
        key = substr($0, 1, i - 1); val = substr($0, i + 1)
        gsub(/^[ \t]+|[ \t]+$/, "", key); gsub(/^[ \t]+|[ \t]+$/, "", val)
        if (key == "description" && d == "") d = val
      }
      next
    }
    { b = b " " $0 }
    END {
      s = d " " b
      gsub(/[\r\t]/, " ", s)
      gsub(/  +/, " ", s)
      sub(/^[ ]+/, "", s); sub(/[ ]+$/, "", s)
      sub(/^[#>-]+[ ]*/, "", s)
      if (s ~ /[^ ]/) print s
    }
  ' "$1"
}

# build_compare_corpus <agent-dir> <out-file> <self-basename> — one line per stored entry, with
# MEMORY.md and the entry being written both excluded.
#
# MEMORY.md is excluded because it is not an entry: it is this writer's own rebuilt pointer index,
# and comparing an entry against the truncated summary of itself is precisely the defect this
# corpus replaces. Excluding it also means an unreadable MEMORY.md no longer blocks a write — the
# rebuild path already treats it as regenerable (see rebuild_memory_index's note), and it now
# contributes nothing to any verdict.
#
# THE ENTRY BEING WRITTEN IS EXCLUDED TOO, and that exclusion is not a loophole — it is the
# difference between "duplicate" and "update". This writer supports updating an entry in place (it
# stashes the prior file so a failed read-back can restore it), and an update necessarily re-posts
# most of the entry's own text. MEASURED once the corpus landed: a one-word typo fix on an existing
# entry scored ~98% against ITSELF and was refused as a duplicate — a regression the corpus
# introduced, caught by trying the operation rather than by reasoning about it. Every OTHER entry
# stays in the corpus, so this excludes exactly one thing: an entry being its own duplicate. The
# defect this corpus exists for is a body reposted under a DIFFERENT slug, which is unaffected —
# the original is still in the corpus and still refuses it.
#
# Return codes are the writer's could-not-examine discipline, not a convenience:
#   0  usable corpus (possibly EMPTY — an empty store means no prior entries, a real clean verdict)
#   2  the corpus file could not be staged
#   3  the store dir exists but cannot be listed
#   4  an entry file exists but cannot be read — a hole in the corpus, never reported as clean
build_compare_corpus() {
  local dir="$1" out="$2" self="${3:-}" f
  : > "$out" || return 2
  [ -d "$dir" ] || return 0                     # no store dir yet: there are no prior entries
  [ -r "$dir" ] && [ -x "$dir" ] || return 3
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue                     # unmatched glob stays literal under bash 3.2
    [ "${f##*/}" = "MEMORY.md" ] && continue
    [ -n "$self" ] && [ "${f##*/}" = "$self" ] && continue
    [ -r "$f" ] || { CORPUS_BAD_PATH="$f"; return 4; }
    entry_compare_line "$f" >> "$out" || return 2
  done
  return 0
}

# ---------------------------------------------------------------------------
# Intake — either a proposal file (routing in its frontmatter) or four positionals.
# ---------------------------------------------------------------------------
work="$(mktemp -d)" || die "mktemp failed" 2
tmp_in_store=""
tmp_index=""
index_lock=""
index_lock_token=""
index_breaker=""
index_lock_seq=0
cleanup() {
  rm -rf "$work" 2>/dev/null || true
  [ -n "$tmp_in_store" ] && rm -f "$tmp_in_store" 2>/dev/null || true
  [ -n "$tmp_index" ] && rm -f "$tmp_index" 2>/dev/null || true
  # THE LOCK IS RELEASED HERE TOO, not only by release_index_lock's normal path. `die` and every
  # `exit` route through this trap, so a refusal taken while the lock is held cannot strand it.
  # Idempotent: release_index_lock blanks $index_lock, so a normal release makes this a no-op — and
  # it goes through release_index_lock rather than a bare `rmdir` so the trap is OWNERSHIP-VERIFIED
  # too: a lock already broken as stale and re-taken by another writer must survive our cleanup.
  # (Guarded on emptiness, so a death before the primitive is defined cannot call it.)
  if [ -n "$index_lock" ]; then release_index_lock; fi
  # The stale-break arbitration directory is held for microseconds, but a signal inside that window
  # would strand it and make the break permanently unavailable — so it is released here as well.
  if [ -n "$index_breaker" ]; then rmdir "$index_breaker" 2>/dev/null || true; index_breaker=""; fi
  return 0
}
trap cleanup EXIT
# EXIT alone is NOT enough for a signal. bash runs the EXIT trap when the SHELL exits, and a
# default-disposition SIGINT/SIGTERM/SIGHUP kills it without one — which would strand the lock dir
# for the stale-breaker to clear instead of releasing it immediately. Trapping the three signals
# explicitly and exiting from the handler makes the EXIT trap run on those paths too; cleanup then
# runs twice (once here, once via EXIT) and is idempotent by construction.
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

body_tmp="$work/body"

if [ -n "$proposal_file" ]; then
  [ "$pos" -eq 0 ] || die "--proposal takes no positional arguments (the entry is described by the proposal's frontmatter)" 2
  [ -e "$proposal_file" ] || refuse "REFUSE_PROPOSAL_ABSENT" "no proposal file at '$proposal_file' — nothing was written" 2
  [ -r "$proposal_file" ] || refuse "REFUSE_PROPOSAL_UNREADABLE" "the proposal at '$proposal_file' exists but could not be read, so it could not be examined — nothing was written" 2
  agent_slug="$(one_line "$(fm_field "$proposal_file" agent)")"
  entry_slug="$(one_line "$(fm_field "$proposal_file" name)")"
  summary="$(one_line "$(fm_field "$proposal_file" description)")"
  [ -n "$title_arg" ]  || title_arg="$(one_line "$(fm_field "$proposal_file" title)")"
  [ -n "$source_arg" ] || source_arg="$(one_line "$(fm_field "$proposal_file" source)")"
  [ -n "$type_arg" ]   || type_arg="$(one_line "$(fm_field "$proposal_file" type)")"
  fm_body "$proposal_file" > "$body_tmp"
  [ -n "$agent_slug" ]  || refuse "REFUSE_PROPOSAL_INCOMPLETE" "the proposal at '$proposal_file' names no 'agent:' in its frontmatter, so there is no store to promote it into" 2
  [ -n "$entry_slug" ]  || refuse "REFUSE_PROPOSAL_INCOMPLETE" "the proposal at '$proposal_file' names no 'name:' in its frontmatter, so the entry has no slug" 2
  [ -n "$summary" ]     || refuse "REFUSE_PROPOSAL_INCOMPLETE" "the proposal at '$proposal_file' names no 'description:' in its frontmatter, so the index would have nothing to say about it" 2
else
  [ "$pos" -eq 4 ] || die "usage: $PROG <agent-slug> <entry-slug> <summary-line> <body-file-or-'-'> [--confirm] [--store <dir>] [--repo <dir>] [--title <text>] [--type <t>] [--source <id>]" 2
  [ -n "$summary" ] || refuse "REJECTED" "summary-line is empty" 1
  NL=$'\n'   # NB: $(printf '\n') strips to "" and would match everything — use $'\n' (bash-3.2 ok)
  case "$summary" in
    *"$NL"*) refuse "REJECTED" "summary-line must be a single line" 1 ;;
  esac
  if [ "$body_src" = "-" ]; then
    cat > "$body_tmp"
  else
    [ -f "$body_src" ] || refuse "REJECTED" "body file not found: $body_src" 2
    # Readability is checked SEPARATELY from existence, the same pair the --proposal path uses
    # above: without it an existing-but-unreadable body surfaces as a raw `cat` failure under
    # `set -e` — safe (the EXIT trap, installed well before this point, still removes $work) but
    # UNNAMED, and every other failure path in this file names itself.
    [ -r "$body_src" ] || refuse "REJECTED" "body file exists but could not be read: $body_src" 2
    cat "$body_src" > "$body_tmp"
  fi
fi

validate_slug "$agent_slug" "agent-slug" agent
validate_slug "$entry_slug" "entry-slug" entry
[ -n "$type_arg" ] || type_arg="project"
case "$type_arg" in
  user|feedback|project|reference) : ;;
  *) refuse "REJECTED" "--type must be one of user|feedback|project|reference (got: $type_arg)" 1 ;;
esac

# ---------------------------------------------------------------------------
# Resolve repo + store (flags > env > defaults), then the WORKTREE GUARD on the RESOLVED root.
# ---------------------------------------------------------------------------
REPO_DIR="${repo_arg:-${AGENT_MEMORY_REPO_DIR:-}}"
if [ -z "$REPO_DIR" ]; then
  # PERMISSIVE non-git fallback, deliberately: outside a repo this resolves to `pwd` rather than
  # refusing. write-lessons.sh's hard `exit 2` for that case is NOT copied here.
  REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
STORE_ROOT="${store_arg:-${AGENT_MEMORY_STORE_DIR:-}}"
[ -n "$STORE_ROOT" ] || STORE_ROOT="$REPO_DIR/.claude/agent-memory"

# A linked worktree's top-level has a `.git` FILE ("gitdir: ..."); the main checkout has a dir.
if [ -f "$REPO_DIR/.git" ]; then
  # A `.git` FILE means a linked WORKTREE **or** a git SUBMODULE top-level. Both are refused; the
  # message names both, because naming only 'git worktree remove' sends a submodule caller hunting a
  # worktree that does not exist. (Same wording as add-rule.sh / add-orientation.sh.)
  refuse "REFUSE_WORKTREE" "refusing to write from a non-primary checkout ($REPO_DIR) — its top-level '.git' is a FILE, which means either a linked git worktree or a git submodule. Agent memory is written only from the primary repo root (red-team F1): from a worktree the write would diverge and be lost on 'git worktree remove'; from a submodule it would land in the wrong repository. Nothing was written." 3
fi

AGENT_DIR="$STORE_ROOT/$agent_slug"
INDEX="$AGENT_DIR/MEMORY.md"
write_target="$AGENT_DIR/$entry_slug.md"

# ---------------------------------------------------------------------------
# LOAD GUARD — three clauses, all required (see the header). Any shortfall is
# REFUSE_VALIDATOR_UNAVAILABLE and nothing is written.
# ---------------------------------------------------------------------------
VALIDATOR="${WRITE_AGENT_MEMORY_VALIDATOR:-}"
if [ -z "$VALIDATOR" ]; then
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/validate-entry.sh" ]; then
    VALIDATOR="${CLAUDE_PLUGIN_ROOT}/scripts/validate-entry.sh"
  else
    VALIDATOR="$HERE/validate-entry.sh"
  fi
fi

# ---- LOAD GUARD BEGIN -------------------------------------------------------
# The BEGIN/END markers delimit the whole guard as ONE replaceable unit, so this suite's mandated
# mutation control can literally "replace the guard with `|| true`" in a single edit and prove the
# AC goes RED. They are structural, not decoration — do not remove them.
if [ ! -f "$VALIDATOR" ] || [ ! -r "$VALIDATOR" ]; then
  refuse "$REFUSE_VALIDATOR_UNAVAILABLE" \
    "the shared write-time validator is missing or unreadable at '$VALIDATOR', so this entry could not be examined — refusing rather than appending it unvalidated. Nothing was written." 2
fi

# Clause (i). `|| true` is FORBIDDEN here: it discards the status, and a discarded status IS the
# silent unvalidated append. `set +e` around the source captures the status instead of throwing it
# away — and `set -e` is restored immediately afterwards.
set +e
# shellcheck source=/dev/null
. "$VALIDATOR"
validator_src_rc=$?
set -e
if [ "$validator_src_rc" -ne 0 ]; then
  refuse "$REFUSE_VALIDATOR_UNAVAILABLE" \
    "sourcing the shared write-time validator '$VALIDATOR' failed (status $validator_src_rc — it is unparseable or truncated), so this entry could not be examined. Nothing was written." 2
fi

# Clause (ii). A truncated helper still defines every function ABOVE the syntax error, so all five
# names are probed, never one as a proxy for the rest.
for _f in $VALIDATOR_REQUIRED_FUNCS; do
  command -v "$_f" >/dev/null 2>&1 || refuse "$REFUSE_VALIDATOR_UNAVAILABLE" \
    "the shared write-time validator loaded but '$_f' is not defined (a partially-loaded validator would report 'examined and clean' over half a check), so this entry could not be examined. Nothing was written." 2
done
command -v validate_entry_all >/dev/null 2>&1 || refuse "$REFUSE_VALIDATOR_UNAVAILABLE" \
  "the shared write-time validator loaded but 'validate_entry_all' is not defined, so this entry could not be examined. Nothing was written." 2

# Clause (iii). Compared against the HARDCODED literal above — see the header on circularity.
if [ "${VALIDATE_ENTRY_CONTRACT:-}" != "$VALIDATE_ENTRY_CONTRACT_REQUIRED" ]; then
  refuse "$REFUSE_VALIDATOR_UNAVAILABLE" \
    "the shared write-time validator's contract sentinel is '${VALIDATE_ENTRY_CONTRACT:-<unset>}', not the expected '$VALIDATE_ENTRY_CONTRACT_REQUIRED' (the file is truncated, or its contract changed), so this entry could not be examined. Nothing was written." 2
fi
# ---- LOAD GUARD END ---------------------------------------------------------

# ---------------------------------------------------------------------------
# Cap + hostile instruction-injection markers. Same marker list and the same WHITESPACE-NORMALIZED
# scan add-orientation.sh / read-orientation.sh use, so a marker split across lines cannot evade the
# line-scoped grep. Memo text is grepped as DATA, never executed.
# ---------------------------------------------------------------------------
body_len="$(wc -c < "$body_tmp" | tr -d '[:space:]')"
sum_len="${#summary}"
if [ $((body_len + sum_len)) -gt "$ENTRY_MAX_CHARS" ]; then
  refuse "REJECTED" "summary+body total $((body_len + sum_len)) chars exceeds the ${ENTRY_MAX_CHARS}-char hard cap — an agent-memory entry is a distilled lesson, not a document" 1
fi

scan="$work/scan"
{ printf '%s\n' "$summary"; cat "$body_tmp"; } | LC_ALL=C tr '\r\n\t' '   ' | tr -s ' ' > "$scan"
for m in "ignore previous" "ignore all previous" "system prompt" "you must now" \
         "disregard" "<system>" "[INST]"; do
  if LC_ALL=C grep -qiF -- "$m" "$scan" 2>/dev/null; then
    refuse "REJECTED" "summary/body contains a hostile instruction-injection marker: '$m' — nothing was written" 1
  fi
done

# ---------------------------------------------------------------------------
# THE VALIDATOR CALL SITE. One call to validate_entry_all so a check cannot be silently omitted;
# --store is REQUIRED and is the DERIVED ENTRY CORPUS, one line per stored entry (omitting it
# returns 2, not 0). It is NOT MEMORY.md — see the corpus note in the header for the measurement
# that ruled the index out. The 1-vs-2 distinction is carried straight into this writer's exit
# status: 1 = examined and violating, 2 = could not examine. Neither is ever reported as clean.
# ---------------------------------------------------------------------------
entry_text="$summary
$(cat "$body_tmp")"

# The corpus is staged under $work — NEVER inside the store — so a refusal below leaves the store
# byte-identical, and the EXIT trap that already owns $work removes it on every path (success,
# refusal, die, or an interrupted run) without a second cleanup to keep in sync.
COMPARE_STORE="$work/store-entries.corpus"
CORPUS_BAD_PATH=""
set +e
build_compare_corpus "$AGENT_DIR" "$COMPARE_STORE" "$entry_slug.md"
corpus_rc=$?
set -e
case "$corpus_rc" in
  0) : ;;
  3) refuse "$REFUSE_STORE_ENTRY_UNREADABLE" \
       "the store dir '$AGENT_DIR' exists but could not be listed, so the entries this write would be compared against could not be examined — refusing rather than reporting it clean. Nothing was written." 2 ;;
  4) refuse "$REFUSE_STORE_ENTRY_UNREADABLE" \
       "the stored entry '$CORPUS_BAD_PATH' exists but could not be read, so it could not be compared against — a hole in the corpus would make a duplicate or contradiction verdict of 'clean' meaningless. Nothing was written." 2 ;;
  *) refuse "$REFUSE_STORE_ENTRY_UNREADABLE" \
       "the comparison corpus derived from '$AGENT_DIR' could not be staged (status $corpus_rc), so this entry could not be compared against the store. Nothing was written." 2 ;;
esac

# ---- VALIDATOR CALL BEGIN ---------------------------------------------------
# Delimited as one unit for the same reason as the load guard: the mandated per-writer mutation
# control DELETES the CALL (not the `source`) and proves this writer's fixtures go RED while the
# others stay green. A writer that sources the helper but never invokes it is otherwise invisible.
# A SECOND control (M4) rewrites `--store "$COMPARE_STORE"` back to `--store "$INDEX"` and proves
# the corpus itself is load-bearing — without it, "we compare against the store" is a claim no
# check backs, which is the failure class this whole change exists to close.
set +e
validate_entry_all --entry "$entry_text" --store "$COMPARE_STORE" --source "$source_arg" --root "$REPO_DIR"
validation_rc=$?
set -e
# rc 0 IS NOT NECESSARILY SILENT. Two of the five checks (dead-reference, cross-repo) are ADVISORY:
# they report on stderr and never refuse, so a clean exit can still carry findings. The call-site
# notice that repeats them in this writer's own voice is deliberately NOT emitted here: its text
# ends "...and THE WRITE PROCEEDED", which is a lie on the dry-run path below (the confirm gate has
# not been evaluated yet). It fires AFTER `proceed` is decided instead — see "THE ADVISORY NOTICE"
# past the gate. The per-finding `ADVISORY:` lines from the checks themselves still print on both
# paths, so a dry-run still shows what a real write would report.
case "$validation_rc" in
  0) : ;;
  1) printf '%s: refusing to write %s — the entry was examined and violates a write-time check (see the reason above). Nothing was written.\n' "$PROG" "$write_target" >&2
     # A duplicate/contradiction reason quotes the store it compared against, and that is now a
     # temp corpus path. Naming the real store dir here keeps the message actionable — a human
     # told only "already stored in /var/folders/.../store-entries.corpus" cannot go and look.
     printf '%s: (the store quoted above is the entry corpus derived from %s — one line per stored entry.)\n' "$PROG" "$AGENT_DIR" >&2
     exit 1 ;;
  *) printf '%s: refusing to write %s — the entry COULD NOT BE EXAMINED (see the reason above); refusing rather than reporting it clean. Nothing was written.\n' "$PROG" "$write_target" >&2; exit 2 ;;
esac
# ---- VALIDATOR CALL END -----------------------------------------------------

# ---------------------------------------------------------------------------
# Compose the entry file OUTSIDE the store.
# ---------------------------------------------------------------------------
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
sha="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || true)"
[ -n "$sha" ] || sha="unknown"
[ -n "$title_arg" ] || title_arg="$entry_slug"
title_arg="$(one_line "$title_arg")"
src_val="$(one_line "${source_arg:-unknown}")"

compose="$work/compose"
{
  printf -- '---\n'
  printf 'name: %s\n' "$entry_slug"
  printf 'title: %s\n' "$title_arg"
  printf 'description: %s\n' "$summary"
  printf 'metadata:\n  type: %s\n' "$type_arg"
  printf 'source: %s\n' "$src_val"
  printf 'written_at: %s\n' "$ts"
  printf 'head_sha: %s\n' "$sha"
  printf -- '---\n'
  cat "$body_tmp"
} > "$compose"

# ---------------------------------------------------------------------------
# rebuild_memory_index <agent-dir> — RE-DERIVE MEMORY.md from the files on disk.
#
# This is the whole point of this writer and it runs on EVERY write. The index is never patched
# and never appended to: it is rebuilt, so an entry file can only be missing a pointer if it is
# also missing from the directory. The invariant it establishes is N files / N-1 pointers —
# MEMORY.md does not index itself.
#
# The existing H1 title line is PRESERVED so a store's human title ("# QA Executor Memory —
# loomwright") survives a rebuild. Everything below it is regenerated; see the OWNERSHIP note in
# this file's header. Written via a temp file inside the store dir + atomic `mv`, so a MEMORY.md is
# never observed half-rebuilt.
#
# CONCURRENCY: THE WHOLE SCAN→COMPUTE→MOVE IS SERIALIZED, not just the `mv`. The `mv` was always
# atomic, but atomicity of the last step is not mutual exclusion of the sequence: two writers could
# interleave as scan(A) · land(B's entry) · scan(B) · mv(B) · mv(A), and A's older index — computed
# before B's file existed — would win. That silently drops B's entry from MEMORY.md while B's entry
# file is still on disk, which is precisely the invariant this writer exists to make impossible
# ("an entry can only be missing from the index if it is also missing from the directory").
#
# The primitive is a LOCK DIRECTORY, because `mkdir` is a single atomic create-or-fail syscall on
# every POSIX filesystem and needs no tooling. `flock(1)` is deliberately NOT used: it does not
# exist on stock macOS, which is the dev platform (and neither does `timeout(1)`, so the bounded
# wait is counted here rather than delegated). The lock lives INSIDE the store dir so it is on the
# same filesystem as the thing it guards, and its name shares the `.write-agent-memory.` prefix the
# atomicity test already sweeps for, so a leaked lock reads as temp residue rather than as nothing.
# ---------------------------------------------------------------------------
INDEX_LOCK_WAIT_SECS="${AGENT_MEMORY_INDEX_LOCK_WAIT_SECS:-30}"
case "$INDEX_LOCK_WAIT_SECS" in ''|*[!0-9]*) INDEX_LOCK_WAIT_SECS=30 ;; esac
[ "$INDEX_LOCK_WAIT_SECS" -ge 1 ] 2>/dev/null || INDEX_LOCK_WAIT_SECS=30

# >>> INDEX LOCK PRIMITIVE — extracted VERBATIM by the concurrency harness in
# `test-write-agent-memory.sh` (case (j4)/(j5)) between this marker and the closing one. Keep the
# three functions between the markers self-contained: they may read only $PROG,
# $INDEX_LOCK_WAIT_SECS and the four `index_lock*` globals, all of which the harness defines.

# _take_index_lock <lock-dir> -> 0 taken (and STAMPED with this process's ownership token), 1 not.
#
# THE OWNERSHIP STAMP IS WHAT MAKES RELEASE SAFE. `rmdir`-by-path releases whatever currently sits
# at the path, which after a stale break may be a lock some OTHER process legitimately holds. The
# token is written INSIDE the lock dir at acquire time and re-read at release time, so a release
# can only remove a lock this acquisition created. The token is `<pid>-<per-process sequence>-
# <$RANDOM>`: the sequence keeps it distinct across the repeated acquire/release cycles one run
# makes (undo path, retries), and pid REUSE cannot forge it because a recycled pid would also have
# to reproduce this process's sequence counter and its random draw — and, more fundamentally,
# because the value compared against is one THIS process wrote into the variable, never one read
# back from the filesystem and trusted.
#
# Stamping failure (a full or read-only disk) FAILS CLOSED: the just-created lock is removed and
# the take reports failure, rather than holding a lock whose ownership cannot later be proven.
_take_index_lock() {
  local lock="$1" token
  mkdir "$lock" 2>/dev/null || return 1
  index_lock_seq=$(( index_lock_seq + 1 ))
  token="$$-$index_lock_seq-${RANDOM:-0}"
  if printf '%s\n' "$token" > "$lock/owner" 2>/dev/null; then
    index_lock="$lock"
    index_lock_token="$token"
    return 0
  fi
  rm -f "$lock/owner" 2>/dev/null || true
  rmdir "$lock" 2>/dev/null || true
  return 1
}

# acquire_index_lock <agent-dir> [wait-secs] -> 0 held · 1 another writer holds it · 4 the lock dir
# could not be created for some OTHER reason (ENOSPC, EPERM, EROFS, a vanished store dir…).
# The two failure codes are kept apart because rc 1's refusal text names contention, and naming
# contention for a full disk sends the reader hunting a writer that does not exist.
# `wait-secs` defaults to $INDEX_LOCK_WAIT_SECS; `0` means ONE attempt with no wait at all (used by
# the undo path, which must not pay the bound a second time on the way to a refusal).
acquire_index_lock() {
  local dir="$1" lock="$1/.write-agent-memory.lock" breaker="$1/.write-agent-memory.lock.breaker"
  local wait_secs="${2-$INDEX_LOCK_WAIT_SECS}" tries=0 max=0 sleep_arg=0.1 per_sec=10
  case "$wait_secs" in ''|*[!0-9]*) wait_secs="$INDEX_LOCK_WAIT_SECS" ;; esac
  # UNCONTENDED FAST PATH, taken BEFORE anything sleeps. The overwhelmingly common case is a free
  # lock, and probing the sleep first would tax every ordinary write 100ms for a wait it never does.
  if _take_index_lock "$lock"; then return 0; fi
  if [ "$wait_secs" -gt 0 ]; then
    # THE RETRY BUDGET IS DERIVED FROM THE SLEEP THAT ACTUALLY WORKS, not assumed. A fixed count of
    # 10 attempts per second combined with a `sleep 1` fallback made the real wait 10× the
    # configured one wherever `sleep` rejects a fractional argument. Probing once and scaling the
    # count keeps the effective bound equal to $wait_secs on both kinds of platform.
    if ! sleep 0.1 2>/dev/null; then sleep_arg=1; per_sec=1; fi
    max=$(( wait_secs * per_sec ))
  fi
  while [ "$tries" -lt "$max" ]; do
    tries=$(( tries + 1 ))
    sleep "$sleep_arg" 2>/dev/null || true
    if _take_index_lock "$lock"; then return 0; fi
  done
  # STALE-LOCK BREAKER — a `kill -9`, a power loss or a full disk can strand the directory with no
  # process behind it, and a lock that can wedge the writer forever is worse than the race it
  # prevents. Age is read with `find -mmin`, which behaves identically on BSD and GNU find; `stat`
  # is avoided on purpose (`-f %m` succeeds with GARBAGE on GNU systems, so a portability slip there
  # is silent rather than loud).
  #
  # TEN MINUTES IS A HEURISTIC, AND ONLY A HEURISTIC. It is NOT derived from the bounded wait above:
  # that bound caps how long a WAITER waits, not how long a HOLDER holds, and nothing bounds a
  # holder — its hold time is however long `rebuild_memory_index_locked` takes. The threshold is
  # chosen as multiple orders of magnitude above any plausible rebuild of a store (a directory scan
  # and one `mv`), so a lock that old is overwhelmingly likely to be abandoned. It is a wager, and
  # the arbitration below is what keeps a losing wager from corrupting anything.
  if [ -n "$(find "$lock" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    # SINGLE-WINNER ARBITRATION, and it needs BOTH halves below.
    #   · `mkdir "$breaker"` is one atomic create-or-fail syscall, so of N racers that all observed
    #     the same stale lock exactly ONE enters this block; the losers never `rmdir` at all. That
    #     closes the SIMULTANEOUS interleaving (two racers acting on their observation at once).
    #   · Re-running the staleness test WHILE HOLDING the breaker closes the SEQUENTIAL one: a racer
    #     that observed the stale lock, then queued behind the breaker while the winner broke it and
    #     re-acquired, now sees a FRESH lock and leaves it alone. Without this, the loser would
    #     delete the winner's LIVE lock and both would end up inside the critical section.
    # A breaker stranded by a `kill -9` makes the break unavailable and the run REFUSES (fail
    # closed, named) — it never degrades into an unarbitrated break; clear it with `rmdir` by hand.
    if mkdir "$breaker" 2>/dev/null; then
      index_breaker="$breaker"
      if [ -n "$(find "$lock" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
        printf '%s: breaking a STALE index lock (older than 10 minutes — assumed abandoned): %s\n' \
          "$PROG" "$lock" >&2
        rm -f "$lock/owner" 2>/dev/null || true
        rmdir "$lock" 2>/dev/null || true
      fi
      rmdir "$breaker" 2>/dev/null || true
      index_breaker=""
    fi
  fi
  # ONE FINAL ATTEMPT, on both routes into here. It covers the stale-break above, and also the
  # holder that released during the last retry interval: without it that run refuses over a
  # lock that is already free, and a refusal costs a legitimate write.
  if _take_index_lock "$lock"; then return 0; fi
  # WHY the lock is unavailable, read from the filesystem rather than assumed: present ⇒ someone
  # holds it; absent ⇒ `mkdir` failed for some environmental reason (ENOSPC, EPERM, EROFS…). This
  # is a DIAGNOSTIC distinction, and it is sampled after the fact: a holder that released between
  # the failed `mkdir` and this test reads as rc 4. Both codes refuse identically, so the narrow
  # mis-labelling costs a less apt message and never a different outcome.
  if [ -d "$lock" ]; then return 1; fi
  return 4
}

# release_index_lock — always returns 0; blanks $index_lock so the EXIT trap's release is a no-op.
# OWNERSHIP-VERIFIED: it removes the lock only when the on-disk stamp is still this acquisition's
# token, so a lock that was broken as stale and re-taken by another writer survives our release.
release_index_lock() {
  # `if`, not `[ … ] && …`: under `set -e` a failing AND-list in statement position aborts the
  # script, which would turn "the lock was already gone" into a crash on the success path.
  if [ -n "$index_lock" ] && [ -n "$index_lock_token" ]; then
    if [ "$(cat "$index_lock/owner" 2>/dev/null)" = "$index_lock_token" ]; then
      rm -f "$index_lock/owner" 2>/dev/null || true
      rmdir "$index_lock" 2>/dev/null || true
    fi
  fi
  index_lock=""
  index_lock_token=""
  return 0
}
# <<< INDEX LOCK PRIMITIVE

# rebuild_memory_index <agent-dir> [wait-secs] — the LOCKED wrapper. Every call site goes through
# this, so the undo path is serialized against a concurrent writer too.
#   0 = rebuilt   2 = could not rebuild   3 = another writer holds the lock   4 = the lock dir could
#   not be created at all (not contention)
# rc 3 and rc 4 are kept DISTINCT so the call site can name the real reason; neither is a silent
# skip. `wait-secs` is passed through to acquire_index_lock (0 = one attempt, no wait).
rebuild_memory_index() {
  local dir="$1" wait_secs="${2-}" rc=0 arc=0
  [ -d "$dir" ] || return 2
  if [ -n "$wait_secs" ]; then
    acquire_index_lock "$dir" "$wait_secs" || arc=$?
  else
    acquire_index_lock "$dir" || arc=$?
  fi
  case "$arc" in
    0) : ;;
    4) return 4 ;;
    *) return 3 ;;
  esac
  # Not a subshell and not a pipeline: the lock is released by the next statement regardless of rc,
  # and by the EXIT trap if anything below dies outright.
  rebuild_memory_index_locked "$dir"; rc=$?
  release_index_lock
  return "$rc"
}

rebuild_memory_index_locked() {
  local dir="$1" idx="$1/MEMORY.md" header="" f base t d
  [ -d "$dir" ] || return 2
  # Absent and unreadable are DELIBERATELY conflated here, and only here — this is
  # the one place in this writer where could-not-examine does not refuse. It is safe
  # because this is a pure REBUILD path: the index is regenerated from the directory
  # listing regardless, so nothing is inferred from the old file's contents. The only
  # loss is a human-authored H1 title, which falls back to a generated one. Everywhere
  # a verdict depends on what a file SAYS, unreadable refuses (rc 2) — see the
  # PROPOSAL_ABSENT / PROPOSAL_UNREADABLE split above.
  if [ -f "$idx" ] && [ -r "$idx" ]; then
    header="$(head -n 1 "$idx" 2>/dev/null)"
    case "$header" in "# "*) : ;; *) header="" ;; esac
  fi
  [ -n "$header" ] || header="# ${dir##*/} memory"

  tmp_index="$(mktemp "$dir/.write-agent-memory.XXXXXX")" || return 2
  {
    printf '%s\n' "$header"
    printf '\n'
    # `ls` is deliberately not used: a `for f in "$dir"/*.md` glob is stable under bash 3.2 and
    # sorts in collation order. A directory with no entry files leaves the literal glob, which the
    # `-f` test then rejects — so an empty store yields a header-only index rather than a bogus
    # pointer to a file named `*.md`.
    for f in "$dir"/*.md; do
      [ -f "$f" ] || continue
      base="${f##*/}"
      [ "$base" = "MEMORY.md" ] && continue
      t="$(one_line "$(fm_field "$f" title)")"
      [ -n "$t" ] || t="$(one_line "$(first_heading "$f")")"
      [ -n "$t" ] || t="$(one_line "$(fm_field "$f" name)")"
      [ -n "$t" ] || t="${base%.md}"
      d="$(one_line "$(fm_field "$f" description)")"
      [ -n "$d" ] || d="$(one_line "$(first_body_line "$f")")"
      d="$(printf '%s' "$d" | cut -c1-200)"
      if [ -n "$d" ]; then
        printf -- '- [%s](%s) — %s\n' "$t" "$base" "$d"
      else
        printf -- '- [%s](%s)\n' "$t" "$base"
      fi
    done
  } > "$tmp_index" || { rm -f "$tmp_index" 2>/dev/null; tmp_index=""; return 2; }
  mv -f "$tmp_index" "$idx" || { rm -f "$tmp_index" 2>/dev/null; tmp_index=""; return 2; }
  tmp_index=""
  return 0
}

# ---------------------------------------------------------------------------
# Confirm-only gate (per-item human approval). Runs AFTER validation so a dry-run reports the same
# refusals a real write would, and BEFORE any write so a refusal leaves the store byte-identical.
# ---------------------------------------------------------------------------
proceed=0
if [ "$confirm" -eq 1 ]; then
  proceed=1
elif [ -t 0 ] && [ -t 1 ]; then
  printf 'Write this agent-memory entry to %s ?\n' "$write_target" >&2
  cat "$compose" >&2
  printf 'Confirm write? [y/N] ' >&2
  read -r reply || reply=""
  case "$reply" in y|Y|yes|YES) proceed=1 ;; *) proceed=0 ;; esac
fi

if [ "$proceed" -ne 1 ]; then
  printf 'PLANNED WRITE (not written — pass --confirm to apply):\n'
  printf '  target: %s\n' "$write_target"
  printf '  index:  %s (rebuilt on write)\n' "$INDEX"
  printf '  entry:\n'
  sed 's/^/    /' "$compose"
  exit 0
fi

# ---------------------------------------------------------------------------
# Write: temp file INSIDE the store dir + atomic mv. On an UPDATE the prior entry is stashed first
# so a failed read-back verify can restore it.
# ---------------------------------------------------------------------------
mkdir -p "$AGENT_DIR" || die "could not create store dir: $AGENT_DIR" 2

prior="$work/prior"
had_prior=0
if [ -f "$write_target" ]; then
  cat "$write_target" > "$prior" || die "could not stash prior entry before update: $write_target" 2
  had_prior=1
fi

tmp_in_store="$(mktemp "$AGENT_DIR/.write-agent-memory.XXXXXX")" || die "mktemp in store failed" 2
cat "$compose" > "$tmp_in_store" || die "could not stage entry in store dir" 2
mv -f "$tmp_in_store" "$write_target" || die "atomic move failed (target left untouched): $write_target" 2
tmp_in_store=""   # consumed by mv; nothing for the trap to clean

# REBUILD ON THE UNDO PATH TOO, or the undo re-creates the rot this writer exists to prevent.
# The index rebuild below runs BEFORE the read-back checks, so by the time undo_write fires,
# MEMORY.md already names the entry we are about to restore-or-remove. Removing the file without
# rebuilding would leave a pointer to a file that is gone — the exact index/directory disagreement
# `rebuild_memory_index` makes structurally impossible on the success path. The rebuild is
# best-effort here (`|| true`): this path is already dying with a named diagnostic, and a failed
# rebuild must not mask the original read-back reason with a second, less useful one. `|| true` is
# correct HERE for that reason and remains FORBIDDEN on the validator's source line.
# NO-WAIT ON THIS PATH (the `0` argument): the failure that brought us here may itself have been a
# contended lock, and paying the full INDEX_LOCK_WAIT_SECS a second time would double the delay in
# front of a refusal that is already decided. One attempt, then move on.
undo_write() {
  if [ "$had_prior" -eq 1 ]; then
    cat "$prior" > "$write_target" 2>/dev/null \
      || die "read-back verify failed ($1) AND prior-entry restore failed: $write_target" 2
    rebuild_memory_index "$AGENT_DIR" 0 || true
    die "read-back verify failed: $1 — restored prior entry at $write_target" 2
  fi
  rm -f "$write_target"
  rebuild_memory_index "$AGENT_DIR" || true
  die "read-back verify failed: $1 — removed $write_target" 2
}

# THE INDEX REBUILD. Every write, unconditionally.
# A LOCK TIMEOUT IS NOT A SKIP. rc 3 (the bounded wait expired with another writer holding the
# store lock) is routed into the SAME undo_write severity as any other failed rebuild, because the
# consequence is identical: the entry file is on disk and MEMORY.md does not name it. Reporting the
# distinct reason only changes the diagnostic, never the outcome.
set +e
rebuild_memory_index "$AGENT_DIR"
rebuild_rc=$?
set -e
case "$rebuild_rc" in
  0) : ;;
  3) undo_write "the MEMORY.md index rebuild could not acquire the store lock within ${INDEX_LOCK_WAIT_SECS}s — another writer is holding $AGENT_DIR/.write-agent-memory.lock" ;;
  # rc 4 is NOT contention, and saying "another writer is holding it" for a full or read-only disk
  # sends the reader hunting a process that does not exist. The lock dir is absent after the last
  # attempt, so `mkdir` failed for an environmental reason instead.
  4) undo_write "the MEMORY.md index rebuild could not CREATE the store lock $AGENT_DIR/.write-agent-memory.lock — this is not contention (no lock is present): check permissions, free space, and that the store is not on a read-only filesystem" ;;
  *) undo_write "the MEMORY.md index could not be rebuilt" ;;
esac

# ---------------------------------------------------------------------------
# Read-back verify: the entry file parses, and the rebuilt index actually names it. The second half
# is what makes the index rot structurally impossible — a rebuild that silently produced nothing is
# caught here rather than discovered months later as an invisible store.
# ---------------------------------------------------------------------------
[ -f "$write_target" ] || undo_write "the entry file is not present after the atomic move"
[ "$(one_line "$(fm_field "$write_target" name)")" = "$entry_slug" ] \
  || undo_write "the written entry's frontmatter 'name:' does not read back as '$entry_slug'"
[ -f "$INDEX" ] || undo_write "MEMORY.md is absent after the rebuild"
if ! grep -qF "($entry_slug.md)" "$INDEX" 2>/dev/null; then
  undo_write "the rebuilt MEMORY.md does not name $entry_slug.md"
fi

# Report-only counts. `|| true` is correct HERE and nowhere near the load guard: under `set -o
# pipefail` a glob matching nothing makes `ls` fail and takes the whole pipeline — and the assignment
# — down with it, turning a successful write into a non-zero exit over a cosmetic tally.
n_files="$(ls "$AGENT_DIR"/*.md 2>/dev/null | wc -l | tr -d '[:space:]' || true)"
[ -n "$n_files" ] || n_files="?"
n_ptrs="$(grep -cE '^- \[[^]]*\]\([^)]*\.md\)' "$INDEX" 2>/dev/null || true)"
[ -n "$n_ptrs" ] || n_ptrs=0

# THE ADVISORY NOTICE — the LAST thing before the success line, and that position is deliberate on
# both sides. It sits past the confirm gate, so a dry-run can never print its "...and THE WRITE
# PROCEEDED" sentence alongside "PLANNED WRITE (not written)". And it sits past the index rebuild
# and the read-back verify, so the sentence is not merely on the write PATH but after the write has
# actually landed and been verified — every failure between the gate and here exits through
# `undo_write`, which removes or restores the entry, and none of those runs should claim the write
# proceeded either. Reached ONLY when the validator returned 0 (rc 1 and rc 2 exit at the call
# site), so it cannot be suppressed on a genuine write.
validate_entry_advisory_notice "$PROG"

printf '%s: wrote agent-memory entry %s to %s and rebuilt %s (%s files / %s index pointers)\n' \
  "$PROG" "$entry_slug" "$write_target" "$INDEX" "$n_files" "$n_ptrs"
exit 0
