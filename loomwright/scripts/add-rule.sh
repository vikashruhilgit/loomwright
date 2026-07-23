#!/usr/bin/env bash
# add-rule.sh — the SOLE WRITER for the committed .agent/rules/ house-rules substrate.
# (New file — north-star slice #3b-ii enforcement side. Mechanizes the /rules add write discipline
#  from skills/rules/SKILL.md §7 IN CODE — the security-sensitive path where a malicious/typo
#  `category` could otherwise escape .agent/rules/. See §9.1: 3b-ii MUST mechanize the write discipline
#  into a sole-writer helper with a path-traversal-rejection test before any unattended seam leans on
#  it — this is that helper.)
#
# Curation/anti-rot (ST-1) added TWO things on top of the original add-only writer:
#   - `--supersedes <rule-id>` — an OPTIONAL flag on the (default) ADD action. Stamps a `supersedes`
#     member on the newly-authored rule object, naming the id of an OLDER rule it replaces. This is
#     purely declarative: the older rule object is left untouched in its file — it is read-rules.sh
#     (the reader) that hides it at read time (single-hop, non-transitive; see read-rules.sh's
#     "SUPERSESSION" docstring). No `--replacement` flag is needed for this path: the newly-added rule
#     itself IS the replacement content.
#   - `--retract` — a NEW action (mutually exclusive with the add-only flags) that REMOVES an existing
#     rule object from whichever `.agent/rules/*.json` array contains it. Mirrors
#     curate-postmortem.sh's shape (`--target`/`--reason`/`--replacement`/`--confirm`) and validate-
#     before-write / fail-loud discipline. `--replacement` is ALWAYS REJECTED here — this file has no
#     `supersede` action, only a bare `--supersedes` flag on add (see above), so a "replacement" pointer
#     has no meaning on a retract (curate-postmortem's own reasoning: "a supersede without a replacement
#     would be an indistinguishable synonym for retract" — the inverse holds too, --replacement on a
#     pure retract is a contradiction in terms). Retraction REMOVES the object outright; there is no
#     in-store home for the retraction reason (see the Normative encoding contract — a sidecar would
#     violate the freeze), so the writer PRINTS a one-line provenance reason to stdout and the commit
#     that lands the removal is the durable record.
#
# WRITE DISCIPLINE — ADD action (per skills/rules/SKILL.md §7 — ALL enforced here in code, never prose):
#   1. Category containment. Slug a LEGITIMATE category to a SINGLE `[a-z0-9-]` path segment via BENIGN
#      normalization only (lowercase, spaces→'-', collapse repeats, strip leading/trailing '-'). REJECT
#      — abort, non-zero, never silently sanitize/rewrite — any category with '/', '..', a leading dot,
#      shell metacharacters, or that is empty / empty-after-slug. The write can NEVER escape .agent/rules/.
#   2. Validate the OTHER values BEFORE writing (so we never author a rule read-rules.sh would later
#      SKIP): statement non-empty; the derived statement-slug non-empty; enforcement EXACTLY
#      `advisory`|`must`; check is a string OR null; `--supersedes` (when given) non-empty, newline-free,
#      and not equal to the about-to-be-created id (self-reference rejected at write time even though
#      the reader would separately fail-safe-ignore it).
#   3. Array-only parse-gate the target `.agent/rules/<category-slug>.json` with `jq -e 'type=="array"'`
#      — ABORT (never clobber) on a malformed OR valid-but-non-array pre-existing file; create as a
#      single-element array if absent.
#   4. Deterministic unique `id` = `<category-slug>-<statement-slug>`; on collision across the MERGED
#      set (this file + every other .agent/rules/*.json, matching the reader's global dedup scope),
#      append a numeric `-N` suffix (`-2`, `-3`, …) until unique.
#   5. Stamp provenance.source (from --source) + provenance.added = UTC ISO-8601.
#   6. Build the object with `jq -n --arg …` — NEVER string-interpolate untrusted values into JSON.
#      `supersedes` is an OPTIONAL member — OMITTED entirely when `--supersedes` was not given (never
#      stamped as an explicit null; the reader treats "missing" and "null" identically anyway).
#   7. Write via temp-file + atomic `mv` (append the new object to the array).
#   8. Read-back verify the written file parses AND contains the new id.
#   9. Confirm-only: write ONLY when --confirm is passed OR an interactive TTY confirms. With NO
#      --confirm and non-interactive (no TTY), PRINT the planned write (object + target path) and DO
#      NOT write.
#  10. Append-only: the ADD action never edits or removes an existing rule. (`--retract` is the one
#      sanctioned exception — see below — and it only ever REMOVES, never edits, an object.)
#
# WRITE DISCIPLINE — RETRACT action (curate-postmortem.sh shape, validate-before-write, fail loud):
#   R1. `--retract` is mutually exclusive with every add-only flag (`--category`/`--statement`/
#       `--check`/`--supersedes`) — combining them is rejected outright (exit 2), never silently
#       ignored, so a caller can't accidentally mix modes.
#   R2. `--target <rule-id>` is REQUIRED (non-empty, no embedded newline/CR — mirrors
#       curate-postmortem.sh's own target guard so a target could never accidentally match nothing).
#   R3. `--reason <text>` is REQUIRED (non-empty) — printed in the provenance line (see below).
#   R4. `--replacement` is ALWAYS REJECTED on retract (exit 2) — see the rationale in the header note
#       above.
#   R5. The target rule id is located by searching every WELL-FORMED (`jq -e 'type=="array"'`)
#       `.agent/rules/*.json` array (LC_ALL=C path-sorted, first match) for an object whose `.id`
#       equals `--target`. A target that exists ONLY inside a malformed file (one this writer could not
#       safely rewrite anyway) is reported not-found — this mirrors the reader's own fail-safe search
#       scope: a rule that a malformed file has never made visible to read-rules.sh has nothing here to
#       retract from a caller's point of view. Not found ⇒ fail loud (exit 2), nothing written.
#   R6. Confirm-only: identical gate semantics to the ADD action (write only on --confirm or an
#       interactive TTY "yes"; otherwise PRINT the planned retract and exit 0 without writing).
#   R7. Remove the object via temp-file + atomic `mv` (never a partial/in-place edit); read-back verify
#       the file still parses as an array AND no longer contains the target id.
#   R8. PRINT a single provenance line to stdout naming the id, source file, and reason — this IS the
#       durable trail (no in-store sidecar; see the Normative encoding contract in the job brief).
#
# Usage:
#   add-rule.sh --category <str> --statement <str> [--enforcement advisory|must] [--check <str>]
#               [--source <str>] [--supersedes <rule-id>] [--confirm]
#   add-rule.sh --retract --target <rule-id> --reason <str> [--confirm]
# Exit:  0 = wrote/retracted OR planned-ok (dry-run) ; non-zero = rejected / error (no partial write).

set -euo pipefail

PROG="add-rule.sh"

die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit "${2:-1}"; }

# ---------------------------------------------------------------------------
# Parse args. Every action shares one flat flag namespace (add-rule.sh has always been all-flags, no
# positional actions) — `--retract` is itself the mode-selector flag, matching the ST-1 contract's
# `kind: flag, name: --retract` (a grep-verifiable literal, not a positional verb).
# ---------------------------------------------------------------------------
category=""
statement=""
enforcement="advisory"
check_set=0          # whether --check was supplied at all
check_val=""         # the raw --check value (a string; null when unset)
source_val="/rules add"
confirm=0
supersedes_set=0     # whether --supersedes was supplied at all (ADD action only)
supersedes_val=""
retract=0            # whether --retract mode was selected
target_id_set=0      # whether --target was supplied at all (RETRACT action only)
target_id=""
reason_set=0         # whether --reason was supplied at all (RETRACT action only)
reason=""
replacement_set=0    # whether --replacement was supplied at all (ALWAYS rejected in this file)
replacement_val=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --category)    [ "$#" -ge 2 ] || die "--category requires a value"; category="$2"; shift 2 ;;
    --statement)   [ "$#" -ge 2 ] || die "--statement requires a value"; statement="$2"; shift 2 ;;
    --enforcement) [ "$#" -ge 2 ] || die "--enforcement requires a value"; enforcement="$2"; shift 2 ;;
    --check)       [ "$#" -ge 2 ] || die "--check requires a value"; check_set=1; check_val="$2"; shift 2 ;;
    --source)      [ "$#" -ge 2 ] || die "--source requires a value"; source_val="$2"; shift 2 ;;
    --supersedes)  [ "$#" -ge 2 ] || die "--supersedes requires a value"; supersedes_set=1; supersedes_val="$2"; shift 2 ;;
    --retract)     retract=1; shift ;;
    --target)      [ "$#" -ge 2 ] || die "--target requires a value"; target_id_set=1; target_id="$2"; shift 2 ;;
    --reason)      [ "$#" -ge 2 ] || die "--reason requires a value"; reason_set=1; reason="$2"; shift 2 ;;
    --replacement) [ "$#" -ge 2 ] || die "--replacement requires a value"; replacement_set=1; replacement_val="$2"; shift 2 ;;
    --confirm)     confirm=1; shift ;;
    -h|--help)
      grep -E '^# ' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq is required but not available"

# ---------------------------------------------------------------------------
# Resolve the store dir (repo-root anchored, matching the reader) — needed by both actions.
# ---------------------------------------------------------------------------
GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
RULES_DIR="$GITROOT/.agent/rules"

# =============================================================================
# RETRACT action.
# =============================================================================
if [ "$retract" -eq 1 ]; then
  # R1. Mutually exclusive with every add-only flag.
  if [ -n "$category" ] || [ -n "$statement" ] || [ "$check_set" -eq 1 ] || [ "$supersedes_set" -eq 1 ]; then
    die "rejected: --retract cannot be combined with add-only flags (--category/--statement/--check/--supersedes)" 2
  fi

  # R2. --target required, non-empty, newline/CR-free (mirrors curate-postmortem.sh's target guard).
  [ "$target_id_set" -eq 1 ] || die "rejected: --retract requires --target <rule-id>" 2
  [ -n "$target_id" ] || die "rejected: --target must be non-empty" 2
  nl=$'\n'; cr=$'\r'
  case "$target_id" in
    *"$nl"*) die "rejected: --target may not contain newline characters" 2 ;;
    *"$cr"*) die "rejected: --target may not contain carriage-return characters" 2 ;;
  esac
  case "$target_id" in
    *[![:space:]]*) : ;;
    *) die "rejected: --target must contain at least one non-whitespace character (whitespace-only value)" 2 ;;
  esac

  # R3. --reason required, non-empty.
  [ "$reason_set" -eq 1 ] || die "rejected: --retract requires --reason <text>" 2
  [ -n "$reason" ] || die "rejected: --reason must be non-empty" 2

  # R4. --replacement is ALWAYS rejected on retract (see header rationale).
  if [ "$replacement_set" -eq 1 ]; then
    die "rejected: --replacement is only meaningful for a supersede action — a retract has no replacement (use --supersedes on the ADD action to author a replacement rule instead)" 2
  fi

  # R5. Locate the target across .agent/rules/*.json — only WELL-FORMED arrays are searched (mirrors
  #     the reader's fail-safe scope: a malformed sibling contributes nothing either way).
  found_file=""
  if [ -d "$RULES_DIR" ]; then
    while IFS= read -r rf; do
      [ -n "$rf" ] || continue
      if jq -e 'type=="array"' "$rf" >/dev/null 2>&1; then
        if jq -e --arg t "$target_id" 'any(.[]?; (type=="object") and (.id == $t))' "$rf" >/dev/null 2>&1; then
          found_file="$rf"
          break
        fi
      fi
    done < <(LC_ALL=C find "$RULES_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | LC_ALL=C sort)
  fi
  [ -n "$found_file" ] || die "rejected: target rule id not found in any .agent/rules/*.json array: $target_id" 2

  # R6. Confirm-only gate (same semantics as the ADD action's own gate).
  proceed=0
  if [ "$confirm" -eq 1 ]; then
    proceed=1
  elif [ -t 0 ] && [ -t 1 ]; then
    printf 'Retract rule id=%s from %s ?\n' "$target_id" "$found_file" >&2
    printf 'reason: %s\n' "$reason" >&2
    printf 'Confirm retract? [y/N] ' >&2
    read -r reply || reply=""
    case "$reply" in y|Y|yes|YES) proceed=1 ;; *) proceed=0 ;; esac
  fi

  if [ "$proceed" -ne 1 ]; then
    printf 'PLANNED RETRACT (not written — pass --confirm to apply):\n'
    printf '  target: %s\n' "$target_id"
    printf '  file: %s\n' "$found_file"
    printf '  reason: %s\n' "$reason"
    exit 0
  fi

  # R7. Remove via temp-file + atomic mv (never a partial/in-place edit). Non-object elements pass
  #     through untouched (defensive — mirrors the reader's own tolerance of stray non-object array
  #     entries); only an object whose id matches is dropped.
  tmp="$(mktemp "$RULES_DIR/.add-rule.XXXXXX")"
  trap 'rm -f "$tmp" 2>/dev/null' EXIT
  jq --arg t "$target_id" 'map(select( (type != "object") or (.id != $t) ))' "$found_file" > "$tmp" \
    || die "failed to remove target from array (target file left untouched): $found_file"
  mv -f "$tmp" "$found_file" || die "atomic move failed (target file left untouched): $found_file"

  # Read-back verify: still a valid array AND the target id is gone.
  if ! jq -e 'type=="array"' "$found_file" >/dev/null 2>&1; then
    die "read-back verify failed: written file is not a valid JSON array: $found_file"
  fi
  if jq -e --arg t "$target_id" 'any(.[]?; (type=="object") and (.id == $t))' "$found_file" >/dev/null 2>&1; then
    die "read-back verify failed: target id still present after retract: $found_file"
  fi

  # R8. PRINT the one-line provenance reason — this IS the durable record (no in-store sidecar).
  printf '%s: retracted rule id=%s from %s — reason: %s\n' "$PROG" "$target_id" "$found_file" "$reason"
  exit 0
fi

# =============================================================================
# ADD action (default — existing behavior, extended with --supersedes).
# =============================================================================
# Retract-only flags are meaningless without --retract — reject rather than silently ignore.
if [ "$target_id_set" -eq 1 ] || [ "$reason_set" -eq 1 ] || [ "$replacement_set" -eq 1 ]; then
  die "rejected: --target/--reason/--replacement are only valid together with --retract" 2
fi

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

# --supersedes (curation/anti-rot ST-1): when supplied, must be non-empty and newline-free. Dangling /
# unresolvable targets are NOT rejected here — the reader (read-rules.sh) already fail-safe-ignores a
# dangling supersedes (demote-never-crash); rejecting it at write time would be a stricter, divergent
# policy from the reader's own tolerance. Self-reference IS rejected here (checked below once the new
# rule's own id is known).
if [ "$supersedes_set" -eq 1 ]; then
  [ -n "$supersedes_val" ] || die "rejected: --supersedes must be non-empty when supplied"
  nl_s=$'\n'; cr_s=$'\r'
  case "$supersedes_val" in
    *"$nl_s"*) die "rejected: --supersedes may not contain newline characters" ;;
    *"$cr_s"*) die "rejected: --supersedes may not contain carriage-return characters" ;;
  esac
fi

# ---------------------------------------------------------------------------
# Resolve the target file (repo-root anchored, matching the reader).
# ---------------------------------------------------------------------------
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

# --supersedes self-reference guard: now that new_id is known, reject a --supersedes value that would
# name this about-to-be-created rule itself (nonsensical — a rule cannot supersede itself).
if [ "$supersedes_set" -eq 1 ] && [ "$supersedes_val" = "$new_id" ]; then
  die "rejected: --supersedes cannot reference this rule's own about-to-be-created id (self-reference): $new_id"
fi

# ---------------------------------------------------------------------------
# 5 + 6. Stamp provenance + build the object with jq -n --arg (never string-interpolate untrusted
#    values into JSON — the jq PROGRAM TEXT here is fixed/single-quoted; only --arg/--argjson values
#    cross the boundary). `supersedes` is OMITTED entirely when --supersedes was not supplied (a truly
#    optional member, merged in only conditionally) rather than stamped as an explicit null.
# ---------------------------------------------------------------------------
added_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

new_obj="$(jq -n \
  --arg id "$new_id" \
  --arg category "$category_slug" \
  --arg statement "$statement" \
  --arg enforcement "$enforcement" \
  --arg source "$source_val" \
  --arg added "$added_ts" \
  --argjson check_set "$check_set" \
  --arg check_val "$check_val" \
  --argjson supersedes_set "$supersedes_set" \
  --arg supersedes_val "$supersedes_val" \
  '
  {
    id: $id, category: $category, statement: $statement, enforcement: $enforcement,
    check: (if $check_set == 1 then $check_val else null end),
    provenance: {source: $source, added: $added},
    applies_to: null
  }
  | if $supersedes_set == 1 then . + {supersedes: $supersedes_val} else . end
  ')"

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
