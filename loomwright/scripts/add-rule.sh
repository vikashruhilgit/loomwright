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
# PATH ROUTING added ONE more optional flag on the (default) ADD action:
#   - `--applies-to <glob>` — REPEATABLE. N flags author an N-element `applies_to` array of `case`-glob
#     patterns; the flag OMITTED leaves `applies_to: null`, which means REPO-WIDE (the historical
#     default, unchanged). `read-rules.sh` is what acts on it at read time: a rule with a non-empty
#     pattern array is emitted only when a touched path matches one of its patterns, and EVERY
#     ambiguous shape fails OPEN there (see read-rules.sh's "PATH ROUTING" docstring). Patterns are
#     validated here (non-empty, no newline/CR/tab, no `..`, not absolute, not `~`-relative) so this
#     writer can never author a scope that is silently dead or that walks out of the repo.
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
#      the reader would separately fail-safe-ignore it); each `--applies-to` (when given) non-empty,
#      newline/CR/tab-free, `..`-free, and neither absolute (`/…`) nor home-relative (`~…`).
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
#       `--check`/`--supersedes`/`--applies-to`) — combining them is rejected outright (exit 2), never silently
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
#               [--source <str>] [--supersedes <rule-id>] [--applies-to <glob> ...] [--confirm]
#   add-rule.sh --retract --target <rule-id> --reason <str> [--confirm]
# Exit:  0 = wrote/retracted OR planned-ok (dry-run) ; non-zero = rejected / error (no partial write).

set -euo pipefail

PROG="add-rule.sh"

die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit "${2:-1}"; }

# ---------------------------------------------------------------------------
# WRITE-TIME VALIDATION — LOAD GUARD (decision (a) of the write-time-validation brief).
# See validate-entry.sh's LOAD GUARD CONTRACT. Three clauses, ALL required:
#   (i)   `. validate-entry.sh` must exit 0. `|| true` is FORBIDDEN on that line — discarding the
#         status IS the silent unvalidated append this design does not sanction. The status is
#         CAPTURED instead, and the caller's own errexit state is saved and restored around the
#         source so this block cannot change the shell options the rest of the script runs under.
#   (ii)  all five validator functions must be present. Bash defines every function ABOVE a syntax
#         error before aborting the parse, so a truncated helper leaves SOME validators defined —
#         a one-function probe would report "examined and clean" over half a validator.
#   (iii) $VALIDATE_ENTRY_CONTRACT must equal the HARDCODED literal below. Comparing against a
#         variable the helper exports (VALIDATE_ENTRY_CONTRACT_EXPECTED), or iterating the list it
#         exports ($VALIDATE_ENTRY_FUNCTIONS), would be CIRCULAR: both are assigned ABOVE the
#         sentinel, so a truncated copy could define them and pass its own test.
# Any shortfall is REFUSE_VALIDATOR_UNAVAILABLE, exit 2 (could-not-examine), nothing written.
# ---------------------------------------------------------------------------
REFUSE_VALIDATOR_UNAVAILABLE="REFUSE_VALIDATOR_UNAVAILABLE"
VALIDATE_ENTRY_CONTRACT_REQUIRED="validate-entry/2"
VALIDATOR_REQUIRED_FUNCS="validate_duplicate validate_contradiction validate_provenance validate_dead_reference validate_cross_repo_reference validate_entry_advisory_notice"

# Resolved BEFORE any `cd`: $0 may be relative, and three of these writers cd to the repo root.
VE_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || printf '%s' ".")"

# _ve_load_validator — runs the three-clause guard. Called on the write path, never at parse time.
_ve_load_validator() {
  VALIDATOR="${ADD_RULE_VALIDATOR:-}"
  if [ -z "$VALIDATOR" ]; then
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/validate-entry.sh" ]; then
      VALIDATOR="${CLAUDE_PLUGIN_ROOT}/scripts/validate-entry.sh"
    else
      VALIDATOR="$VE_HERE/validate-entry.sh"
    fi
  fi

  # ---- LOAD GUARD BEGIN -----------------------------------------------------
  # BEGIN/END delimit the guard as ONE replaceable unit so this suite's mandated mutation control
  # can replace it with `|| true` in a single edit and prove AC2 goes RED. Structural, not decor.
  if [ ! -f "$VALIDATOR" ] || [ ! -r "$VALIDATOR" ]; then
    printf '%s: %s — the shared write-time validator is missing or unreadable at "%s", so this entry could not be examined; refusing rather than appending it unvalidated. Nothing was written.
'       "add-rule.sh" "$REFUSE_VALIDATOR_UNAVAILABLE" "$VALIDATOR" >&2
    exit 2
  fi

  # Clause (i). errexit is saved/restored rather than assumed: these five writers do not all run
  # under `set -e` (write-system-contract.sh is `set -uo pipefail`), so an unconditional `set -e`
  # here would silently change the failure semantics of everything downstream.
  case "$-" in *e*) _ve_had_e=1 ;; *) _ve_had_e=0 ;; esac
  set +e
  # shellcheck source=/dev/null
  . "$VALIDATOR"
  _ve_src_rc=$?
  if [ "$_ve_had_e" -eq 1 ]; then set -e; fi
  if [ "$_ve_src_rc" -ne 0 ]; then
    printf '%s: %s — sourcing the shared write-time validator "%s" failed (status %s: unparseable or truncated), so this entry could not be examined. Nothing was written.
'       "add-rule.sh" "$REFUSE_VALIDATOR_UNAVAILABLE" "$VALIDATOR" "$_ve_src_rc" >&2
    exit 2
  fi

  # Clause (ii). All five are probed, plus the aggregate the call site actually uses — never one
  # name as a proxy for the rest.
  for _vef in $VALIDATOR_REQUIRED_FUNCS validate_entry_all; do
    if ! command -v "$_vef" >/dev/null 2>&1; then
      printf '%s: %s — the shared write-time validator loaded but "%s" is not defined (a partially-loaded validator would report "examined and clean" over half a check), so this entry could not be examined. Nothing was written.
'         "add-rule.sh" "$REFUSE_VALIDATOR_UNAVAILABLE" "$_vef" >&2
      exit 2
    fi
  done

  # Clause (iii). Compared against the HARDCODED literal — see the circularity note above.
  if [ "${VALIDATE_ENTRY_CONTRACT:-}" != "$VALIDATE_ENTRY_CONTRACT_REQUIRED" ]; then
    printf '%s: %s — the shared write-time validator contract sentinel is "%s", not the expected "%s" (the file is truncated, or its contract changed), so this entry could not be examined. Nothing was written.
'       "add-rule.sh" "$REFUSE_VALIDATOR_UNAVAILABLE" "${VALIDATE_ENTRY_CONTRACT:-<unset>}" "$VALIDATE_ENTRY_CONTRACT_REQUIRED" >&2
    exit 2
  fi
  # ---- LOAD GUARD END -------------------------------------------------------
}


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
applies_to_set=0     # whether --applies-to was supplied at all (ADD action only; REPEATABLE)
applies_to_raw=""    # newline-terminated accumulator of the raw --applies-to values (see A1 below).
                     # A newline-delimited string rather than a bash array on purpose: `"${arr[@]}"`
                     # on an EMPTY array is an unbound-variable error under `set -u` in bash 3.2 (the
                     # macOS dev shell), and embedded newlines are rejected outright (A2), so the
                     # delimiter is unambiguous by construction.
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
    --applies-to)  [ "$#" -ge 2 ] || die "--applies-to requires a value"; applies_to_set=1
                   # A2-newline, checked HERE and nowhere else: the accumulator below is newline-
                   # TERMINATED, so an embedded newline would be consumed as the accumulator's OWN
                   # delimiter and one flag would silently become two patterns. The validation loop at
                   # A2 runs AFTER that split and therefore can never see it — the reject must happen
                   # before the value is appended.
                   case "$2" in
                     *$'\n'*) die "rejected: --applies-to may not contain newline characters" ;;
                   esac
                   applies_to_raw="${applies_to_raw}${2}"$'\n'; shift 2 ;;
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

# ---- Worktree guard (red-team F1) — AC10b ---------------------------------
# This writer shipped with NO worktree guard: `git rev-parse --show-toplevel` in a LINKED worktree
# returns the WORKTREE's own toplevel, not the main checkout, so a worker running in a worktree
# wrote to the worktree's .agent/rules/ and the write was lost on `git worktree remove`.
# A linked worktree's top-level carries a `.git` FILE ("gitdir: ..."); the main checkout carries a
# directory — that is the whole discriminator.
# A `.git` FILE IS NOT UNIQUE TO A WORKTREE: a git SUBMODULE's top-level carries one too. Refusing
# there is correct (a curated store belongs in the superproject, not the submodule), but the message
# must not name `git worktree remove` as the consequence — that sends the reader hunting a worktree
# that does not exist. The discriminator is kept as-is rather than replaced with
# `git rev-parse --git-common-dir`: both cases are refused either way, so the extra subprocess would
# buy only a finer message. The message names BOTH instead.
# DELIBERATELY NOT COPIED from write-lessons.sh: its hard `exit 2` when there is no git repo at all.
# This writer's documented fallback outside a repo is `pwd` (fixtures and temp stores are legitimate
# callers), and that behaviour is UNCHANGED here — only the worktree case is newly refused.
if [ -f "$GITROOT/.git" ]; then
  die "refusing to write from a non-primary checkout ($GITROOT) — its top-level \`.git\` is a FILE, which means either a linked git worktree or a git submodule. Rules are written only from the primary repo root (red-team F1): from a worktree the write would diverge and be lost on \`git worktree remove\`; from a submodule it would land in the wrong repository. Run this from the primary checkout (or the superproject root)." 3
fi

RULES_DIR="$GITROOT/.agent/rules"

# =============================================================================
# RETRACT action.
# =============================================================================
if [ "$retract" -eq 1 ]; then
  # R1. Mutually exclusive with every add-only flag.
  if [ -n "$category" ] || [ -n "$statement" ] || [ "$check_set" -eq 1 ] || [ "$supersedes_set" -eq 1 ] \
     || [ "$applies_to_set" -eq 1 ]; then
    die "rejected: --retract cannot be combined with add-only flags (--category/--statement/--check/--supersedes/--applies-to)" 2
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

# --applies-to (PATH ROUTING): REPEATABLE — N flags produce an N-element `applies_to` array; OMITTED
# ⇒ `applies_to: null` (repo-wide), the historical default, unchanged. Each pattern is a `case` glob
# matched by read-rules.sh against a touched path (`*`/`**` are equivalent and BOTH cross `/` — this
# is NOT .gitignore syntax; see read-rules.sh's "PATH ROUTING" docstring and skills/rules/SKILL.md §1).
#
# A1. Validate BEFORE writing, mirroring the category-containment discipline: a pattern is REJECTED
#     (abort, non-zero, never silently rewritten), never sanitized into a safe-looking form.
# A2. Rejected shapes, and why each one:
#       empty                → matches nothing; a silent dead rule.
#       whitespace-only      → same defect as empty, one step further in: no touched path is literally
#                              a bare space, so the pattern is stored, survives every other guard, and
#                              routes the rule to nothing. Mirrors the `--target` whitespace-only guard
#                              in the retract path above (same `*[![:space:]]*` idiom — bash 3.2 here,
#                              so NOT `${var//[[:space:]]/}`, which is O(n²) on this host).
#       newline / CR         → newline is this accumulator's own delimiter (see the declaration above)
#                              AND the reader strips it, so accepting one would author a pattern that
#                              means something other than what was typed. CR is rejected for the
#                              writer's own reason — a line-ending hazard in a line-framed store; the
#                              reader does NOT strip CR (its gsub set is tab/newline/0x1F). NOTE the NEWLINE arm
#                              lives in the `--applies-to)` PARSING case, not in the loop below: by the
#                              time we get here the newline would already have been consumed as the
#                              delimiter, splitting one flag into two patterns. CR/tab/`..`/`/`/`~`
#                              survive the split intact and are rejected below.
#       tab                  → the reader neutralizes tab inside a pattern (line-framing safety), so
#                              the stored pattern would silently differ from the authored one.
#       0x1F (unit sep)      → the reader's `route_spec` strips it with the same `gsub` as tab/newline
#                              (its `gsub("[\t\n\u001f]"; "")`) because 0x1F is the route
#                              cell's own JOIN delimiter — so an accepted 0x1F would both mutate the
#                              stored pattern AND collide with the cell framing it was chosen for.
#       contains `..`        → traversal-style; the store is repo-relative and a rule scope has no
#                              business walking upward. Same raw-string reject as the `category`
#                              containment guard — item 1 of this file's own "WRITE DISCIPLINE — ADD
#                              action" list above (NOT a `skills/rules/SKILL.md §N` reference; the
#                              `§N` citations elsewhere in this file all point at that external doc).
#                              That anchor is DESCRIPTIVE on purpose: a bare line number in a comment
#                              is a live claim that nothing checks, and this one was already wrong
#                              twice. Cite the construct, not the line.
#       leading `/`          → absolute path; the reader matches repo-relative touched paths, so an
#                              absolute pattern can only ever match nothing.
#       leading `~`          → home-relative; same reasoning as absolute, plus shell-expansion optics.
if [ "$applies_to_set" -eq 1 ]; then
  nl_a=$'\n'; cr_a=$'\r'; tab_a=$'\t'; us_a=$'\037'
  # Iterate the accumulator without a bash array (see the declaration comment). The accumulator is
  # newline-TERMINATED, so a trailing empty segment is expected and is simply the loop's exit.
  at_rest="$applies_to_raw"
  at_count=0
  while [ -n "$at_rest" ]; do
    at_pat="${at_rest%%"$nl_a"*}"
    at_rest="${at_rest#*"$nl_a"}"
    [ -n "$at_pat" ] || die "rejected: --applies-to must be non-empty when supplied"
    # ORDER MATTERS: the SPECIFIC control-character/shape rejects run FIRST, the whitespace-only
    # catch-all LAST — mirroring the `--target` guard in the retract path, which likewise checks
    # newline/CR before its whitespace-only arm. A lone CR or lone TAB is entirely whitespace under
    # `[:space:]`, so with the catch-all first those two specific arms were unreachable for the
    # lone-control-character shape and the caller got the generic message instead. An unreachable
    # branch is a guarantee that exists only on paper. Every input rejected before is still rejected;
    # only WHICH diagnostic fires changed. (bash 3.2: `case`, never `${var//[[:space:]]/}`.)
    case "$at_pat" in
      *"$cr_a"*)  die "rejected: --applies-to may not contain carriage-return characters: $at_pat" ;;
      *"$tab_a"*) die "rejected: --applies-to may not contain tab characters: $at_pat" ;;
      *"$us_a"*)  die "rejected: --applies-to may not contain 0x1F unit-separator characters: $at_pat" ;;
      *..*)       die "rejected: --applies-to may not contain '..' (traversal): $at_pat" ;;
      /*)         die "rejected: --applies-to must be a repo-relative pattern, not absolute: $at_pat" ;;
      '~'*)       die "rejected: --applies-to must be a repo-relative pattern, not home-relative: $at_pat" ;;
    esac
    # Whitespace-only is the empty case one step further in — see the A2 table.
    case "$at_pat" in
      *[![:space:]]*) : ;;
      *) die "rejected: --applies-to must contain at least one non-whitespace character (whitespace-only pattern matches nothing): $at_pat" ;;
    esac
    at_count=$((at_count + 1))
  done
  [ "$at_count" -gt 0 ] || die "rejected: --applies-to must be non-empty when supplied"
fi

# Build the JSON array injection-safely: the raw text crosses into jq via `-R -s` (read as a raw
# string on STDIN) and is split INSIDE jq's data model — never interpolated into the program text.
# The trailing empty segment from the newline terminator is dropped by the length filter.
applies_to_json="null"
if [ "$applies_to_set" -eq 1 ]; then
  applies_to_json="$(printf '%s' "$applies_to_raw" \
    | jq -R -s -c 'split("\n") | map(select(length > 0))')" \
    || die "internal error: could not encode --applies-to values as a JSON array"
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
  --argjson applies_to "$applies_to_json" \
  '
  {
    id: $id, category: $category, statement: $statement, enforcement: $enforcement,
    check: (if $check_set == 1 then $check_val else null end),
    provenance: {source: $source, added: $added},
    # PATH ROUTING: an ARRAY of `case`-glob patterns when --applies-to was supplied (repeatable),
    # otherwise `null` — the historical default, meaning REPO-WIDE. `null` is a MEANINGFUL value
    # here (not a placeholder), so unlike `supersedes` it is always stamped explicitly.
    applies_to: $applies_to
  }
  | if $supersedes_set == 1 then . + {supersedes: $supersedes_val} else . end
  ')"

# ---------------------------------------------------------------------------
# THE VALIDATOR CALL SITE (see the LOAD GUARD block above). Placed BEFORE the confirm gate on
# purpose: a dry-run that prints a plan the real write would refuse is a misleading plan, so the
# entry is examined first and a violation is refused whether or not --confirm was passed.
# The examined text is the rule statement plus its --reason, which is where a rule's cited paths
# and repo references live.
# ---------------------------------------------------------------------------
_ve_load_validator
_ve_entry="$statement"
[ -n "$reason" ] && _ve_entry="$statement
$reason"
# ---- VALIDATOR CALL BEGIN ---------------------------------------------------
set +e
validate_entry_all --entry "$_ve_entry" --store "$target" \
  --source "$source_val" --root "$GITROOT"
_ve_rc=$?
set -e
# rc 0 IS NOT NECESSARILY SILENT. Two of the five checks (dead-reference, cross-repo) are ADVISORY:
# they report on stderr and never refuse, so a clean exit can still carry findings. The call-site
# notice that repeats them in this writer's own voice is deliberately NOT emitted here: its text
# ends "...and THE WRITE PROCEEDED", which is a lie on the dry-run path a few lines below (the
# confirm gate has not been evaluated yet). It fires AFTER `proceed` is decided instead — see
# "THE ADVISORY NOTICE" past the gate. The per-finding `ADVISORY:` lines from the checks themselves
# still print on both paths, so a dry-run still shows what a real write would report.
case "$_ve_rc" in
  0) : ;;
  1) die "refusing to write — the rule was examined and violates a write-time check (see the reason above). Nothing was written." 1 ;;
  *) die "refusing to write — the rule COULD NOT BE EXAMINED (see the reason above); refusing rather than reporting it clean. Nothing was written." 2 ;;
esac
# ---- VALIDATOR CALL END -----------------------------------------------------

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

# THE ADVISORY NOTICE — the LAST thing before the success line, and that position is deliberate on
# both sides. It sits past the confirm gate, so a dry-run can never print its "...and THE WRITE
# PROCEEDED" sentence alongside "PLANNED WRITE (not written)". And it sits past the read-back
# verify, so the sentence is not merely on the write PATH but after the write has actually landed
# and been verified — every failure between the gate and here `die`s, and none of those runs should
# claim the write proceeded either. Reached ONLY when the validator returned 0 (rc 1 and rc 2 `die`
# at the call site), so it cannot be suppressed on a genuine write: every successful write ends
# here. The RETRACT action returns long before the validator is called and is unaffected either way.
validate_entry_advisory_notice "$PROG"

printf 'wrote rule id=%s to %s\n' "$new_id" "$target"
exit 0
