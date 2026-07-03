#!/usr/bin/env bash
# add-rule.sh — the SOLE WRITER for the committed .agent/rules/ house-rules substrate.
# (New file — north-star slice #3b-ii enforcement side. Mechanizes the /rules add write discipline
#  from skills/rules/SKILL.md §7 IN CODE — the security-sensitive path where a malicious/typo
#  `category` could otherwise escape .agent/rules/. See §9.1: 3b-ii MUST mechanize the write discipline
#  into a sole-writer helper with a path-traversal-rejection test before any unattended seam leans on
#  it — this is that helper.)
#
# WRITE DISCIPLINE (per skills/rules/SKILL.md §7 — ALL enforced here in code, never as prose):
#   1. Category containment. Slug a LEGITIMATE category to a SINGLE `[a-z0-9-]` path segment via BENIGN
#      normalization only (lowercase, spaces→'-', collapse repeats, strip leading/trailing '-'). REJECT
#      — abort, non-zero, never silently sanitize/rewrite — any category with '/', '..', a leading dot,
#      shell metacharacters, or that is empty / empty-after-slug. The write can NEVER escape .agent/rules/.
#   2. Validate the OTHER values BEFORE writing (so we never author a rule read-rules.sh would later
#      SKIP): statement non-empty; the derived statement-slug non-empty; enforcement EXACTLY
#      `advisory`|`must`; check is a string OR null.
#   3. Array-only parse-gate the target `.agent/rules/<category-slug>.json` with `jq -e 'type=="array"'`
#      — ABORT (never clobber) on a malformed OR valid-but-non-array pre-existing file; create as a
#      single-element array if absent.
#   4. Deterministic unique `id` = `<category-slug>-<statement-slug>`; on collision across the MERGED
#      set (this file + every other .agent/rules/*.json, matching the reader's global dedup scope),
#      append a numeric `-N` suffix (`-2`, `-3`, …) until unique.
#   5. Stamp provenance.source (from --source) + provenance.added = UTC ISO-8601.
#   6. Build the object with `jq -n --arg …` — NEVER string-interpolate untrusted values into JSON.
#   7. Write via temp-file + atomic `mv` (append the new object to the array).
#   8. Read-back verify the written file parses AND contains the new id.
#   9. Confirm-only: write ONLY when --confirm is passed OR an interactive TTY confirms. With NO
#      --confirm and non-interactive (no TTY), PRINT the planned write (object + target path) and DO
#      NOT write.
#  10. Append-only: never edit or remove an existing rule.
#
# Usage:
#   add-rule.sh --category <str> --statement <str> [--enforcement advisory|must] [--check <str>]
#               [--source <str>] [--confirm]
# Exit:  0 = wrote OR planned-ok (dry-run) ; non-zero = rejected / error (no partial write).

set -euo pipefail

PROG="add-rule.sh"

die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit "${2:-1}"; }

# ---------------------------------------------------------------------------
# Parse args.
# ---------------------------------------------------------------------------
category=""
statement=""
enforcement="advisory"
check_set=0          # whether --check was supplied at all
check_val=""         # the raw --check value (a string; null when unset)
source_val="/rules add"
confirm=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --category)    [ "$#" -ge 2 ] || die "--category requires a value"; category="$2"; shift 2 ;;
    --statement)   [ "$#" -ge 2 ] || die "--statement requires a value"; statement="$2"; shift 2 ;;
    --enforcement) [ "$#" -ge 2 ] || die "--enforcement requires a value"; enforcement="$2"; shift 2 ;;
    --check)       [ "$#" -ge 2 ] || die "--check requires a value"; check_set=1; check_val="$2"; shift 2 ;;
    --source)      [ "$#" -ge 2 ] || die "--source requires a value"; source_val="$2"; shift 2 ;;
    --confirm)     confirm=1; shift ;;
    -h|--help)
      grep -E '^# ' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq is required but not available"

# ---------------------------------------------------------------------------
# 1. Category containment — REJECT hostile categories, slug only benign ones.
# ---------------------------------------------------------------------------
[ -n "$category" ] || die "rejected: --category is required and must be non-empty"

# Hard REJECT before any normalization: a hostile category is refused, NEVER silently rewritten into a
# safe-looking form (do NOT turn '../etc' into 'etc'). We reject the raw string on ANY traversal /
# separator / metachar / leading-dot signal.
case "$category" in
  */*)   die "rejected: category may not contain '/': $category" ;;
  *..*)  die "rejected: category may not contain '..': $category" ;;
  .*)    die "rejected: category may not start with a dot: $category" ;;
esac
# Shell metacharacters (any of these in the raw category ⇒ reject; we never sanitize them away).
case "$category" in
  *[';|&$`()<>*?!\\'\"]*) die "rejected: category contains shell metacharacters: $category" ;;
esac

# BENIGN slug: lowercase, non-[a-z0-9]→'-', collapse repeats, strip leading/trailing '-'.
slug() {
  # $1 = raw string; echoes the slug. Uses tr/sed only on already-validated benign input.
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/-+/-/g; s/^-//; s/-$//'
}

category_slug="$(slug "$category")"
[ -n "$category_slug" ] || die "rejected: category is empty after slugging: $category"
# Defensive: the slug MUST be a single [a-z0-9-] segment (never a path). This can only fail if slug()
# regressed — assert it so the containment invariant is code-checked, not assumed.
case "$category_slug" in
  *[!a-z0-9-]*) die "internal error: slug produced non-[a-z0-9-] output: $category_slug" ;;
  */*)          die "internal error: slug produced a path separator: $category_slug" ;;
esac

# ---------------------------------------------------------------------------
# 2. Validate the OTHER values BEFORE writing (mirror read-rules.sh so authored rules are readable).
# ---------------------------------------------------------------------------
[ -n "$statement" ] || die "rejected: --statement is required and must be non-empty"

statement_slug="$(slug "$statement")"
[ -n "$statement_slug" ] || die "rejected: statement has no [a-z0-9-] content to slug: $statement"

case "$enforcement" in
  advisory|must) : ;;
  *) die "rejected: --enforcement must be exactly 'advisory' or 'must' (got: $enforcement)" ;;
esac

# check is either a string (when --check supplied) or null (when unset). Both are valid per the schema.
# A supplied --check is always a string here (bash args are strings), so no further type-reject is
# possible from the CLI — the non-string-check rejection is exercised at the schema level and tested by
# constructing the object below. (The test harness asserts a numeric/non-string check is rejected by
# building the JSON directly; from THIS CLI, --check is inherently a string, which is valid.)

# ---------------------------------------------------------------------------
# Resolve the store dir (repo-root anchored, matching the reader).
# ---------------------------------------------------------------------------
GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
RULES_DIR="$GITROOT/.agent/rules"
target="$RULES_DIR/$category_slug.json"

# ---------------------------------------------------------------------------
# 3. Array-only parse-gate the target (abort, never clobber).
# ---------------------------------------------------------------------------
if [ -e "$target" ]; then
  if ! jq -e 'type=="array"' "$target" >/dev/null 2>&1; then
    die "rejected: existing target is malformed or not a JSON array (refusing to clobber): $target"
  fi
fi

# ---------------------------------------------------------------------------
# 4. Deterministic unique id across the MERGED set (this file + every other .agent/rules/*.json).
#    Collect all existing ids (fail-safe; a malformed sibling contributes no ids), then suffix -N until
#    unique. This matches read-rules.sh's global dedup scope so we never author a would-be-skipped dup.
# ---------------------------------------------------------------------------
existing_ids="$(mktemp)"
trap 'rm -f "$existing_ids" 2>/dev/null' EXIT
: > "$existing_ids"
if [ -d "$RULES_DIR" ]; then
  while IFS= read -r rf; do
    [ -n "$rf" ] || continue
    # Only array files contribute ids (matches reader). Extract string ids injection-safely.
    jq -r 'if type=="array" then (.[] | select(type=="object") | .id | select(type=="string")) else empty end' \
      "$rf" 2>/dev/null >> "$existing_ids" || true
  done < <(LC_ALL=C find "$RULES_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | LC_ALL=C sort)
fi

id_taken() { LC_ALL=C grep -qxF "$1" "$existing_ids"; }

base_id="$category_slug-$statement_slug"
new_id="$base_id"
n=2
while id_taken "$new_id"; do
  new_id="$base_id-$n"
  n=$((n + 1))
done

# ---------------------------------------------------------------------------
# 5 + 6. Stamp provenance + build the object with jq -n --arg (never string-interpolate).
# ---------------------------------------------------------------------------
added_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "$check_set" -eq 1 ]; then
  new_obj="$(jq -n \
    --arg id "$new_id" \
    --arg category "$category_slug" \
    --arg statement "$statement" \
    --arg enforcement "$enforcement" \
    --arg check "$check_val" \
    --arg source "$source_val" \
    --arg added "$added_ts" \
    '{id:$id, category:$category, statement:$statement, enforcement:$enforcement,
      check:$check, provenance:{source:$source, added:$added}, applies_to:null}')"
else
  new_obj="$(jq -n \
    --arg id "$new_id" \
    --arg category "$category_slug" \
    --arg statement "$statement" \
    --arg enforcement "$enforcement" \
    --arg source "$source_val" \
    --arg added "$added_ts" \
    '{id:$id, category:$category, statement:$statement, enforcement:$enforcement,
      check:null, provenance:{source:$source, added:$added}, applies_to:null}')"
fi

# ---------------------------------------------------------------------------
# 9. Confirm-only gate. Write only when --confirm OR an interactive TTY confirms. Otherwise DRY-RUN:
#    print the planned object + target path and DO NOT write.
# ---------------------------------------------------------------------------
proceed=0
if [ "$confirm" -eq 1 ]; then
  proceed=1
elif [ -t 0 ] && [ -t 1 ]; then
  printf 'Add this rule to %s ?\n' "$target" >&2
  printf '%s\n' "$new_obj" >&2
  printf 'Confirm write? [y/N] ' >&2
  read -r reply || reply=""
  case "$reply" in y|Y|yes|YES) proceed=1 ;; *) proceed=0 ;; esac
fi

if [ "$proceed" -ne 1 ]; then
  printf 'PLANNED WRITE (not written — pass --confirm to apply):\n'
  printf '  target: %s\n' "$target"
  printf '  object: %s\n' "$new_obj"
  exit 0
fi

# ---------------------------------------------------------------------------
# 7. Append via jq to a temp file, then atomic mv over the target.
# ---------------------------------------------------------------------------
mkdir -p "$RULES_DIR" || die "could not create rules dir: $RULES_DIR"

tmp="$(mktemp "$RULES_DIR/.add-rule.XXXXXX")"
# Extend cleanup to remove the temp target too.
trap 'rm -f "$existing_ids" "$tmp" 2>/dev/null' EXIT

if [ -e "$target" ]; then
  # Parse-gate already passed; append to the existing array injection-safely.
  jq --argjson obj "$new_obj" '. + [$obj]' "$target" > "$tmp" \
    || die "failed to append rule to existing array (target left untouched): $target"
else
  # Absent → create a single-element array.
  jq -n --argjson obj "$new_obj" '[$obj]' > "$tmp" \
    || die "failed to create new rule array: $target"
fi

mv -f "$tmp" "$target" || die "atomic move failed (target left untouched): $target"

# ---------------------------------------------------------------------------
# 8. Read-back verify: the written file parses as an array AND contains the new id.
# ---------------------------------------------------------------------------
if ! jq -e 'type=="array"' "$target" >/dev/null 2>&1; then
  die "read-back verify failed: written file is not a valid JSON array: $target"
fi
if ! jq -e --arg id "$new_id" 'any(.[]; (type=="object") and (.id == $id))' "$target" >/dev/null 2>&1; then
  die "read-back verify failed: new id '$new_id' not found in written file: $target"
fi

printf 'wrote rule id=%s to %s\n' "$new_id" "$target"
exit 0
