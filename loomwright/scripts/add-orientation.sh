#!/usr/bin/env bash
# add-orientation.sh — the SOLE WRITER for the committed .agent/orientation/ memo store.
# (New file — orientation-memo substrate writer side, cloned from the add-rule.sh sole-writer
#  discipline: path-containment slug rules, hard REJECT of hostile input, temp-file + atomic-mv
#  writes, read-back verification.)
#
# The committed store is written ONLY via this helper, with per-item HUMAN approval — never by
# automated runs (those write proposals to the gitignored .supervisor/orientation-proposals/
# instead; a human promotes an approved proposal through this writer). Human approval is
# MECHANIZED, not prose: a confirm-only gate (cloned from add-rule.sh) writes ONLY when
# --confirm is passed OR an interactive TTY user answers y. Any other invocation (e.g. an
# automated non-TTY run without --confirm) is a DRY-RUN: it prints the planned memo + target
# path and exits 0 WITHOUT writing.
#
# WRITE DISCIPLINE (all enforced here in code, never as prose):
#   1. Slug containment. <area-slug> must be a single [a-z0-9-]+ segment. REJECT — abort,
#      non-zero, never silently sanitize/rewrite — any slug with '/', '..', a leading dot,
#      a leading or trailing '-', spaces/metacharacters, or that is empty. The write can
#      NEVER escape the store dir.
#   2. Cap. REJECT when summary+body exceed 1000 chars, and when the COMPOSED memo file
#      (header + summary + body) exceeds the 1000-char hard cap — so this writer can never
#      author a memo read-orientation.sh would later skip as over-cap.
#   3. Hostile markers. REJECT a summary/body containing any of the same instruction-injection
#      markers the reader scans for (case-insensitive, fixed-string): "ignore previous",
#      "ignore all previous", "system prompt", "you must now", "disregard", "<system>",
#      "[INST]". The scan runs against a WHITESPACE-NORMALIZED copy of the content (newlines/
#      tabs → single spaces) so a marker split across lines cannot evade it. Keep the list AND
#      the normalization in sync with read-orientation.sh.
#   4. Header stamp: current UTC ISO-8601 time + `git rev-parse --short HEAD` + `areas:` from
#      --areas (default: the slug itself as a path prefix). Areas are validated to a benign
#      character set (no '..', no '|'/metachars — '|' would break header parsing).
#   5. Confirm-only gate (per-item human approval). Write only when --confirm OR an
#      interactive TTY confirms y. Otherwise print the planned memo + target and exit 0
#      WITHOUT writing.
#   6. Write via temp file + atomic `mv` INSIDE the store dir. One memo per area: an existing
#      <area-slug>.md is atomically REPLACED (memo update), never partially written.
#   7. Read-back verify: header line parses + file under cap; on verify failure of a NEW memo
#      remove the written file; on verify failure of a memo UPDATE restore the prior memo
#      (stashed before the mv) — then exit non-zero either way.
#
# Usage:
#   add-orientation.sh <area-slug> <summary-line> <body-file-or-'-'>
#                      [--confirm] [--store <dir>] [--repo <dir>] [--areas "<paths>"]
#   defaults: repo = cwd git root; store = <repo>/.agent/orientation
#   env overrides (for tests): ORIENTATION_STORE_DIR / ORIENTATION_REPO_DIR
#   precedence: flags > env > defaults. Body '-' reads stdin.
# Exit:  0 = wrote + verified, OR dry-run (no --confirm, non-interactive: printed plan, wrote
#        nothing); non-zero = rejected / error (no partial write).

set -euo pipefail

PROG="add-orientation.sh"

die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit "${2:-1}"; }

# ---------------------------------------------------------------------------
# Parse args (three positionals + optional flags).
# ---------------------------------------------------------------------------
slug=""
summary=""
body_src=""
store_arg=""
repo_arg=""
areas_arg=""
confirm=0
pos=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --store) [ "$#" -ge 2 ] || die "--store requires a value"; store_arg="$2"; shift 2 ;;
    --repo)  [ "$#" -ge 2 ] || die "--repo requires a value";  repo_arg="$2";  shift 2 ;;
    --areas) [ "$#" -ge 2 ] || die "--areas requires a value"; areas_arg="$2"; shift 2 ;;
    --confirm) confirm=1; shift ;;
    -h|--help)
      grep -E '^# ' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    --*) die "unknown flag: $1 (see --help)" ;;
    *)
      pos=$((pos + 1))
      case "$pos" in
        1) slug="$1" ;;
        2) summary="$1" ;;
        3) body_src="$1" ;;
        *) die "too many positional arguments (see --help)" ;;
      esac
      shift ;;
  esac
done

[ "$pos" -eq 3 ] || die "usage: $PROG <area-slug> <summary-line> <body-file-or-'-'> [--confirm] [--store <dir>] [--repo <dir>] [--areas \"<paths>\"]"

# ---------------------------------------------------------------------------
# 1. Slug containment — REJECT hostile slugs, never sanitize (the write can never escape
#    the store dir). Explicit cases first for clear diagnostics; the final class check is
#    the containment invariant itself.
# ---------------------------------------------------------------------------
case "$slug" in
  "")   die "rejected: area-slug is empty" ;;
  */*)  die "rejected: area-slug may not contain '/': $slug" ;;
  *..*) die "rejected: area-slug may not contain '..': $slug" ;;
  .*)   die "rejected: area-slug may not start with a dot: $slug" ;;
  -*|*-) die "rejected: area-slug may not start or end with '-': $slug" ;;
  readme) die "rejected: 'readme' is reserved (collides with the store's README.md on case-insensitive filesystems)" ;;
esac
case "$slug" in
  *[!a-z0-9-]*) die "rejected: area-slug must be a single [a-z0-9-]+ segment (no spaces/metachars/uppercase): $slug" ;;
esac

# ---------------------------------------------------------------------------
# Summary + body intake.
# ---------------------------------------------------------------------------
[ -n "$summary" ] || die "rejected: summary-line is empty"
NL=$'\n'   # NB: $(printf '\n') would strip to "" and match everything — use $'\n' (bash-3.2 ok)
case "$summary" in
  *"$NL"*) die "rejected: summary-line must be a single line" ;;
esac

work="$(mktemp -d)" || die "mktemp failed"
tmp_in_store=""
trap 'rm -rf "$work" 2>/dev/null; [ -n "$tmp_in_store" ] && rm -f "$tmp_in_store" 2>/dev/null || true' EXIT

body_tmp="$work/body"
if [ "$body_src" = "-" ]; then
  cat > "$body_tmp"
else
  [ -f "$body_src" ] || die "body file not found: $body_src"
  cat "$body_src" > "$body_tmp"
fi

# ---------------------------------------------------------------------------
# 2. Cap: summary+body ≤ 1000 chars (the composed-file cap is re-checked below).
# ---------------------------------------------------------------------------
body_len="$(wc -c < "$body_tmp" | tr -d '[:space:]')"
sum_len="${#summary}"
if [ $((body_len + sum_len)) -gt 1000 ]; then
  die "rejected: summary+body total $((body_len + sum_len)) chars exceeds the 1000-char hard cap"
fi

# ---------------------------------------------------------------------------
# 3. Hostile / instruction-injection markers ⇒ REJECT (same list the reader scans;
#    case-insensitive, fixed-string; memo text is grepped as data, never executed).
#    The grep runs against a WHITESPACE-NORMALIZED copy (newlines/tabs → single spaces,
#    runs squeezed) so a marker split across lines cannot evade the line-scoped scan.
#    Keep the marker list AND this normalization in sync with read-orientation.sh.
# ---------------------------------------------------------------------------
scan="$work/scan"
{ printf '%s\n' "$summary"; cat "$body_tmp"; } \
  | LC_ALL=C tr '\r\n\t' '   ' | tr -s ' ' > "$scan"
for m in "ignore previous" "ignore all previous" "system prompt" "you must now" \
         "disregard" "<system>" "[INST]"; do
  if LC_ALL=C grep -qiF -- "$m" "$scan" 2>/dev/null; then
    die "rejected: summary/body contains a hostile instruction-injection marker: '$m'"
  fi
done

# ---------------------------------------------------------------------------
# Resolve repo + store (flags > env > defaults).
# ---------------------------------------------------------------------------
REPO_DIR="${repo_arg:-${ORIENTATION_REPO_DIR:-}}"
if [ -z "$REPO_DIR" ]; then
  REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
STORE_DIR="${store_arg:-${ORIENTATION_STORE_DIR:-}}"
[ -n "$STORE_DIR" ] || STORE_DIR="$REPO_DIR/.agent/orientation"

# ---------------------------------------------------------------------------
# 4. Header stamp: UTC now + short HEAD sha + areas (default: the slug as a path prefix).
# ---------------------------------------------------------------------------
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
sha="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null)" \
  || die "cannot resolve HEAD sha in repo: $REPO_DIR (is it a git repo with commits?)"

areas_val="${areas_arg:-$slug}"
# Bare-slug fallback rarely matches a real tracked path, so the reader's staleness
# check would never fire for this memo — surface the sharp edge (fail-safe: warn only).
if [ -z "$areas_arg" ]; then
  echo "warning: --areas not given; defaulting to bare slug '$slug' — if that matches no tracked path, staleness detection will never fire for this memo. Pass --areas \"<repo-relative path prefixes>\"." >&2
fi
[ -n "$areas_val" ] || die "rejected: --areas is empty"
# Benign character set only (letters, digits, dot, underscore, slash, space, hyphen) — a '|'
# or '<'/'>' etc. would break the pipe-delimited header comment; '..' is traversal-shaped.
bad_chars="$(printf '%s' "$areas_val" | tr -d 'A-Za-z0-9._/ -')"
[ -z "$bad_chars" ] || die "rejected: --areas contains disallowed characters: $bad_chars"
case "$areas_val" in
  *..*) die "rejected: --areas may not contain '..': $areas_val" ;;
esac

header="<!-- written_at: ${ts} | head_sha: ${sha} | areas: ${areas_val} -->"

# ---------------------------------------------------------------------------
# 2b. Compose OUTSIDE the store first; the COMPOSED file must also be ≤ 1000 chars, so a
#     writer-authored memo can never be reader-skipped as over-cap.
# ---------------------------------------------------------------------------
compose="$work/compose"
{
  printf '%s\n' "$header"
  printf '%s\n' "$summary"
  cat "$body_tmp"
} > "$compose"

total="$(wc -c < "$compose" | tr -d '[:space:]')"
if [ "$total" -gt 1000 ]; then
  die "rejected: composed memo file ($total chars incl. header) exceeds the 1000-char hard cap"
fi

# ---------------------------------------------------------------------------
# 5. Confirm-only gate (per-item human approval, cloned from add-rule.sh). Write only when
#    --confirm OR an interactive TTY confirms y. Otherwise DRY-RUN: print the planned memo +
#    target path and DO NOT write (exit 0) — an automated non-TTY run without --confirm can
#    never mutate the committed store.
# ---------------------------------------------------------------------------
target="$STORE_DIR/$slug.md"

proceed=0
if [ "$confirm" -eq 1 ]; then
  proceed=1
elif [ -t 0 ] && [ -t 1 ]; then
  printf 'Write this orientation memo to %s ?\n' "$target" >&2
  cat "$compose" >&2
  printf 'Confirm write? [y/N] ' >&2
  read -r reply || reply=""
  case "$reply" in y|Y|yes|YES) proceed=1 ;; *) proceed=0 ;; esac
fi

if [ "$proceed" -ne 1 ]; then
  printf 'PLANNED WRITE (not written — pass --confirm to apply):\n'
  printf '  target: %s\n' "$target"
  printf '  memo:\n'
  sed 's/^/    /' "$compose"
  exit 0
fi

# ---------------------------------------------------------------------------
# 6. Write via temp file INSIDE the store dir + atomic mv over the target. On a memo UPDATE,
#    stash the prior memo first so a failed read-back verify can restore it (never leave the
#    area memo-less because an update went bad).
# ---------------------------------------------------------------------------
mkdir -p "$STORE_DIR" || die "could not create store dir: $STORE_DIR"

prior="$work/prior"
had_prior=0
if [ -f "$target" ]; then
  cat "$target" > "$prior" || die "could not stash prior memo before update: $target"
  had_prior=1
fi

tmp_in_store="$(mktemp "$STORE_DIR/.add-orientation.XXXXXX")" || die "mktemp in store failed"
cat "$compose" > "$tmp_in_store" || die "could not stage memo in store dir"
mv -f "$tmp_in_store" "$target" || die "atomic move failed (target left untouched): $target"
tmp_in_store=""   # consumed by mv; nothing for the trap to clean

# ---------------------------------------------------------------------------
# 7. Read-back verify: header line parses + written file is under the cap. On failure of a
#    NEW memo remove the written file; on failure of an UPDATE restore the stashed prior memo.
# ---------------------------------------------------------------------------
undo_write() {
  # $1 = diagnostic reason. Restore prior memo (update) or remove the bad file (new), then die.
  if [ "$had_prior" -eq 1 ]; then
    cat "$prior" > "$target" 2>/dev/null \
      || die "read-back verify failed ($1) AND prior-memo restore failed: $target"
    die "read-back verify failed: $1 — restored prior memo at $target"
  fi
  rm -f "$target"
  die "read-back verify failed: $1 — removed $target"
}

first_line="$(head -n 1 "$target" 2>/dev/null)"
if ! printf '%s' "$first_line" \
   | grep -qE '^<!-- written_at: .+ \| head_sha: .+ \| areas: .+ -->$'; then
  undo_write "header line missing/unparseable"
fi
verify_total="$(wc -c < "$target" | tr -d '[:space:]')"
if [ "$verify_total" -gt 1000 ]; then
  undo_write "written file $verify_total chars exceeds cap"
fi

printf 'wrote orientation memo %s (%s chars) to %s\n' "$slug" "$verify_total" "$target"
exit 0
