# exec-acceptance-lib.sh — shared classification/hash logic for a Supervisor-Ready Brief's
# `## Executable Acceptance` section. SOURCED (never executed directly) by BOTH
# `run-ground-truth.sh` (the enforcement side, Phase 4.5) and `exec-acceptance-hash.sh` (the
# human-facing / brief-authoring side). This is the ONE place the `cmd:`/`corpus-task:`/`rule:`/
# `verify:` (alias `qa-executor:`) classification rule, the `unknown_kind` refusal of any other
# `<word>:` prefix, and the content-keyed stamp hash are defined — factored out
# specifically so the two consumers can never silently diverge (red-team-hardening item 05, AC1
# risk mitigation: "the worker should factor the shared classification logic into one definition
# both scripts read, or add a cross-check test that fails if they ever diverge"). Sourcing the
# same file makes divergence structurally impossible rather than merely tested-against.
#
# Functions (all pure — no I/O beyond reading the given `<brief>` path; no execution, no writes):
#   trim <line>                          -> leading/trailing-whitespace-trimmed line
#   strip_bullet <line>                  -> `trim` PLUS a leading `- `/`-` bullet marker removed
#   classify_kind <line>                 -> `cmd` | `corpus-task` | `rule` | `verify` | `unknown_kind`
#                                           (`qa-executor:` -> `verify`, its alias; any other
#                                           `<word>:` prefix -> `unknown_kind`; a bare line with no
#                                           such prefix -> `cmd`)
#   extract_brief_section_bullets <brief> -> one stripped bullet per line from the brief's
#                                           `## Executable Acceptance` section (exact heading
#                                           match only — a sibling heading like "## Executable
#                                           Acceptance Notes" does NOT open the section); nothing
#                                           printed when the brief/section is absent.
#   extract_configuration_stamp <brief>  -> prints the FIRST `sha256:<64-hex>` value found on an
#                                           `- **Executable Acceptance Approved:** sha256:<hash>`
#                                           line inside the brief's `## Configuration` section, or
#                                           nothing if no such (syntactically well-formed) line exists.
#   sha256_hex <string>                  -> hex sha256 of the given string (no trailing newline
#                                           fed to the hasher); empty string if no sha256 tool is
#                                           available. Fallback chain mirrors send-webhook.sh's
#                                           sha256_hex: shasum -a 256 -> sha256sum -> openssl dgst.
#   exec_acceptance_hash <brief>         -> prints `sha256:<hex>` of the whitespace-normalized,
#                                           newline-joined list of `cmd:`/bare and `verify:`
#                                           (incl. `qa-executor:`) bullets, in brief order
#                                           (classify_kind == "cmd" or "verify"), or the literal
#                                           `none` when that filtered list is empty (incl.
#                                           brief/section absent, or only corpus-task:/rule:/
#                                           unknown_kind bullets present). A brief with no
#                                           qa-executor: bullet and no unknown <word>: bullet (a
#                                           prefix other than cmd:/corpus-task:/rule:/verify:)
#                                           hashes exactly as before (a verify: bullet was already
#                                           hashed whole as a bare line); a brief with either must
#                                           be re-stamped (its cmd: bullets read cmd_unapproved
#                                           until then).
#                                           Returns 1 (with a stderr diagnostic, no stdout) only
#                                           when the filtered list is non-empty and no sha256 tool
#                                           is available — a hash claiming to represent content it
#                                           could not actually compute would be worse than none.
#
# Whitespace normalization = the SAME leading/trailing trim already applied to every bullet at
# ingestion (both here and in run-ground-truth.sh's own `add_line`) — a trailing-space-only edit
# to a bullet therefore does NOT change the hash, matching run-ground-truth.sh's own bullet
# trimming (AC3 in the brief). Internal whitespace inside a bullet is NOT further normalized —
# consistent with run-ground-truth.sh's pre-existing behavior, which never did that either.
#
# Portability: bash 3.2 + BSD userland safe (macOS) and ubuntu-clean (ci.yml's
# `loomwright/scripts/test-*.sh` glob). No GNU-only flags, no associative arrays. Relies on bash
# process substitution (`< <(...)`) — POSIX sh is NOT sufficient; both consumers already require
# bash (indexed arrays, `${var+/-...}` idioms) so this is not a new constraint.
#
# NOT meant to be run with `set -e` assumptions from the sourcing script broken — this file itself
# sets no shell options (a sourced file inherits and should not fight the caller's `set -uo
# pipefail`); both current consumers already set it before sourcing this file.

# trim <line> — leading/trailing whitespace only (no bullet-marker removal). Safe for targets like
# `-x foo` where a leading dash is meaningful. Identical to run-ground-truth.sh's pre-existing trim.
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"   # ltrim
  s="${s%"${s##*[![:space:]]}"}"   # rtrim
  printf '%s' "$s"
}

# strip_bullet <line> — trim, then remove a leading `- ` (or bare `-`) bullet marker, then trim
# again. Only for line INGESTION (bullet-list parsing) — never for `<kind>: <target>` extraction,
# where a leading dash in the target (e.g. `cmd: -x foo`) is meaningful and must be preserved.
strip_bullet() {
  local line="$1"
  line="${line#"${line%%[![:space:]]*}"}"   # ltrim
  line="${line#- }"
  line="${line#-}"
  line="${line#"${line%%[![:space:]]*}"}"   # ltrim again (after marker)
  line="${line%"${line##*[![:space:]]}"}"   # rtrim
  printf '%s' "$line"
}

# classify_kind <line> — `cmd` | `corpus-task` | `rule` | `verify` | `unknown_kind`. IDENTICAL rule
# to run-ground-truth.sh's execution-time case statement (both read this single definition).
# `rule:` (plan-time-rule-routing) is a PRECONDITION, not a nicety: without its own arm a
# `rule: <id>` bullet would be hashed into the brief stamp, flagged by Plan Review Criterion 14,
# and EXECUTED as shell. With it, a `rule:` bullet is never hashed and run-ground-truth.sh resolves
# it by delegating to rules-check.sh; its authorization is the user-scope rules stamp, never the
# brief `sha256:` stamp.
# `verify:` (and `qa-executor:`, kept as its alias so no existing bullet changes meaning) is a
# criterion checked by the Selvedge CLI (ground-truth-verify.sh). It IS hashed (a step plan reaches
# only allowlisted origins, so the stamp records what the brief asks to check, not a shell grant).
# The prefix grammar: a line whose first token is `<word>:` followed by a blank or the end of the
# line, `<word>` = a letter then letters, digits, `-` or `_`, is a PREFIXED line. A prefixed line
# whose word is not a known kind is `unknown_kind` — never hashed, never run — so a typo (`verfy:`)
# or a kind this classifier does not know yet can never turn into a shell command. A line with no
# such prefix (`bash scripts/x.sh`, `npm test -- --grep "a: b"`, `abc:def`, `9x: y`) stays a bare
# shell `cmd`, exactly as before. Known kinds match on `<kind>:` alone (`rule:id`, `cmd:true`).
classify_kind() {
  local _ck_prefix_re='^[A-Za-z][A-Za-z0-9_-]*:([[:blank:]]|$)'
  case "$1" in
    cmd:*)          printf 'cmd\n' ;;
    corpus-task:*)  printf 'corpus-task\n' ;;
    verify:*)       printf 'verify\n' ;;
    qa-executor:*)  printf 'verify\n' ;;   # alias of verify:
    rule:*)         printf 'rule\n' ;;
    *)
      if [[ $1 =~ $_ck_prefix_re ]]; then
        printf 'unknown_kind\n'           # an unknown `<word>:` prefix — never hashed, never run
      else
        printf 'cmd\n'                    # bare line -> treat as shell cmd
      fi
      ;;
  esac
}

# extract_brief_section_bullets <brief> — one stripped bullet per line from the brief's
# `## Executable Acceptance` section. Mirrors run-ground-truth.sh's own `--brief` ingestion
# (exact heading match; only leading-`-` lines inside the section are collected; blank
# lines/prose ignored).
extract_brief_section_bullets() {
  local brief="$1"
  local in_section=0
  local raw heading trimmed s
  [ -n "$brief" ] && [ -f "$brief" ] || return 0
  while IFS= read -r raw || [ -n "$raw" ]; do
    heading="$(trim "$raw")"
    case "$heading" in
      "## Executable Acceptance") in_section=1; continue ;;
      "## "*) [ "$in_section" -eq 1 ] && in_section=0 ;;
    esac
    if [ "$in_section" -eq 1 ]; then
      trimmed="${raw#"${raw%%[![:space:]]*}"}"
      case "$trimmed" in
        -*)
          s="$(strip_bullet "$raw")"
          [ -n "$s" ] && printf '%s\n' "$s"
          ;;
      esac
    fi
  done < "$brief"
}

# extract_configuration_stamp <brief> — prints the FIRST well-formed `sha256:<64-hex>` value on an
# `- **Executable Acceptance Approved:** sha256:<hash>` line inside the brief's `## Configuration`
# section (exact heading match, same convention as the Executable Acceptance section above).
# Nothing printed if the brief/section/line is absent or the hash is not exactly 64 lowercase hex
# chars (a malformed stamp is treated as no stamp — never partially trusted).
extract_configuration_stamp() {
  local brief="$1"
  local in_section=0
  local raw heading hit
  [ -n "$brief" ] && [ -f "$brief" ] || return 0
  while IFS= read -r raw || [ -n "$raw" ]; do
    heading="$(trim "$raw")"
    case "$heading" in
      "## Configuration") in_section=1; continue ;;
      "## "*) [ "$in_section" -eq 1 ] && in_section=0 ;;
    esac
    if [ "$in_section" -eq 1 ]; then
      case "$raw" in
        *"Executable Acceptance Approved:"*"sha256:"*)
          hit="$(printf '%s\n' "$raw" | sed -nE 's/.*sha256:([0-9a-f]{64}).*/\1/p')"
          if [ -n "$hit" ]; then
            printf 'sha256:%s\n' "$hit"
            return 0
          fi
          ;;
      esac
    fi
  done < "$brief"
}

# sha256_hex <string> — hex sha256 of the given string (printf '%s', no trailing newline fed to
# the hasher). Fallback chain mirrors send-webhook.sh's sha256_hex exactly (shasum -a 256 first —
# macOS ships no sha256sum — then sha256sum, then openssl dgst). Empty string if none available.
sha256_hex() {
  local s="${1:-}"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$s" | shasum -a 256 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$s" | sha256sum 2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    printf '%s' "$s" | openssl dgst -sha256 2>/dev/null | awk '{print $NF}'
  else
    printf ''
  fi
}

# exec_acceptance_hash <brief> — see file header. Prints `sha256:<hex>` or `none`; exit 0 in both
# cases. Exit 1 (stderr diagnostic, no stdout) only when the filtered bullet list is non-empty and
# no sha256 tool is available.
exec_acceptance_hash() {
  local brief="$1"
  local line kind hash_input="" first=1 h
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    kind="$(classify_kind "$line")"
    if [ "$kind" = "cmd" ] || [ "$kind" = "verify" ]; then
      if [ "$first" -eq 1 ]; then
        hash_input="$line"
        first=0
      else
        hash_input="$hash_input"$'\n'"$line"
      fi
    fi
  done < <(extract_brief_section_bullets "$brief")

  if [ -z "$hash_input" ]; then
    printf 'none\n'
    return 0
  fi

  h="$(sha256_hex "$hash_input")"
  if [ -z "$h" ]; then
    echo "exec-acceptance-lib: no sha256 tool (shasum/sha256sum/openssl) available — cannot compute the Executable Acceptance stamp hash" >&2
    return 1
  fi
  printf 'sha256:%s\n' "$h"
}
