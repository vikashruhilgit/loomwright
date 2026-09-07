#!/usr/bin/env bash
# propose-product.sh — the PROPOSE-ONLY, CONFIRM-GATED bootstrap for the committed
# `.agent/product.json` product-context store (what this project IS, who it SERVES, who it
# COMPETES with). It SCANS the project for candidate values, PRINTS the proposal, and writes
# ONLY on `--confirm` or an interactive TTY "yes".
#
# It is the SOLE WRITER of `.agent/product.json`, and it writes NOTHING ELSE — not a log, not a
# marker, not a backup. The only other filesystem effect is creating the containing `.agent/`
# directory when it does not already exist, and a same-directory temp file that exists only for
# the duration of the atomic move.
#
# The store's SCHEMA AUTHORITY is `docs/RESULT_SCHEMAS.md` §"PRODUCT_CONTEXT"; this writer conforms
# to it, never the reverse. The reader is `read-product.sh` (advisory, fail-safe, never writes).
#
# ---------------------------------------------------------------------------------------------
# WHY THE CONFIRM GATE (see AGENT_GUIDELINES.md §"Sole-writer confirm gates"):
#   `.agent/product.json` lands in the TRACKED `.agent/` tree — no `.gitignore` entry covers it —
#   and is committed by design, so it falls on the COMMITTED side of the sole-writer rule and must
#   gate. (Do NOT try to re-derive that with `git ls-files .agent/product.json` in THIS repo: it
#   returns empty and always will, because the plugin deliberately ships no store of its own — the
#   bootstrap creates one per project at runtime. The literal test would answer "not tracked ⇒ no
#   gate", which is the opposite of the truth.)
#
# WHY THIS WRITER DOES NOT USE validate-entry.sh, DELIBERATELY:
#   The shared write-time validator's three blocking checks — contradiction, duplicate, provenance —
#   are all defined against an APPEND-ONLY store of curated prose ENTRIES. `.agent/product.json` is
#   a SINGLE STRUCTURED OBJECT: there is no second entry for a new one to duplicate or contradict,
#   so those checks have no referent here and running them would be theatre. This writer validates
#   SHAPE instead (see VALIDATION below). The confirm gate is unchanged and still required — the
#   validator and the gate answer different questions, and only the validator is being skipped.
#
# ---------------------------------------------------------------------------------------------
# WHAT IS SCANNED, AND WHAT IS NEVER GUESSED:
#   `domain`      — scanned. First non-empty candidate from, in order: README.md's H1 + first
#                   paragraph, `package.json` .description, `pyproject.toml` / `Cargo.toml`
#                   description, `composer.json` .description. Falls back to the repo directory
#                   name. Overridable with `--domain`. The proposal printout names WHICH source a
#                   candidate came from, so a human can see whether it is worth keeping.
#   `stance`      — NEVER scanned, NEVER guessed, and REQUIRED on the write path. `stance` decides
#                   the DEFAULT ACTION on a discovered gap (read-product.sh's `STANCE_ACTIONS`
#                   lookup), so a wrong guess here would tell a payments app to skip its missing
#                   fraud checks. There is no signal in a repo that distinguishes a product from a
#                   tool, so `--confirm` WITHOUT `--stance product|tool` REFUSES and writes nothing.
#                   A bare (no-`--confirm`) run still prints a full proposal and says so.
#   `audience`    — NOT scanned. Defaults to an explicitly-unverified marker string that says it is
#                   unfilled rather than pretending to know. Overridable with `--audience`.
#   `competitors` — NEVER auto-detected (an explicit non-goal) and NEVER fetched: this script makes
#                   no network call of any kind. Empty unless `--competitor "<name>|<url>"` is
#                   passed (repeatable). Every entry is written with `last_fetched: null`, meaning
#                   NEVER FETCHED, because nothing here has fetched anything. A date is never
#                   invented for that field.
#   `written_at` / `head_sha` — provenance, mirroring the `.agent/orientation/` memo header pair, so
#                   staleness is measurable against churn rather than guessed from elapsed time.
#
#   `stance_default_action` is EMITTED-BUT-NOT-STORED: it is a read-product.sh OUTPUT, never a key
#   in the file. This writer asserts its ABSENCE from the built object before writing (see
#   VALIDATION), so that rule is backed by a check rather than only by a comment.
#
# VALIDATION (shape only, run BEFORE the confirm gate so a malformed proposal is refused whether or
# not `--confirm` was passed):
#   V1  the built root is a JSON object
#   V2  every required key is PRESENT: domain, stance, audience, competitors, written_at, head_sha
#   V3  `stance` is exactly "product" or "tool"
#   V4  `competitors` is an array; each entry is an object whose `name` and `url` are non-empty
#       strings and which CARRIES `last_fetched` as a PRESENT KEY, asserted with jq `has()`.
#       `has()` and not `// <default>`: the value may legitimately be null (never fetched), so a
#       `//` default would silently accept a MISSING key as if it were an explicit null and the two
#       facts would become indistinguishable. (That exact defect shipped once before in this repo.)
#   V5  `stance_default_action` is ABSENT (emitted-but-not-stored, above)
#
# REFUSALS (nothing is written in any of these):
#   - a non-primary checkout: the top-level `.git` is a FILE, which means a linked git worktree OR a
#     git submodule. From a worktree the write would diverge and be lost on `git worktree remove`;
#     from a submodule it would land in the wrong repository. Same guard add-rule.sh carries.
#   - an EXISTING `.agent/product.json`. This is a bootstrap, not an editor: silently clobbering a
#     curated store would destroy hand-written product knowledge. Edit the file directly, or remove
#     it first.
#   - `jq` unavailable (this writer builds and validates JSON with it; unlike the READER, which
#     skips fail-safe, a writer that cannot validate must refuse rather than write unchecked bytes).
#   - any V1–V5 shape failure.
#
# INJECTION SAFETY: every scanned or user-supplied value enters jq as a `--arg` (or is read from a
# file jq opens by path). No value is ever interpolated into a shell command, eval'd, sourced or
# executed, and the jq program text is fixed.
#
# Usage:  propose-product.sh [--domain <str>] [--stance product|tool] [--audience <str>]
#                            [--competitor "<name>|<url>"]... [--confirm]
#   No `--confirm` and no interactive TTY  =>  PRINT the planned write, write NOTHING, exit 0.
#   `--confirm` (or an interactive TTY "y") + a valid `--stance`  =>  write `.agent/product.json`.
# Exit:  0 ok / dry-run · 1 refused · 2 shape validation failed · 3 non-primary checkout

set -euo pipefail

PROG="propose-product.sh"
die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit "${2:-1}"; }

# ---------------------------------------------------------------------------
# 1. Parse args. Flat flag namespace, matching add-rule.sh.
# ---------------------------------------------------------------------------
domain_arg=""
stance_arg=""
audience_arg=""
competitors_raw=""   # newline-TERMINATED accumulator of raw "<name>|<url>" values. A newline inside
                     # a value would be consumed as the accumulator's own delimiter and one flag
                     # would silently become two competitors, so it is rejected at parse time,
                     # BEFORE the value is appended — a later loop runs after the split and could
                     # never see it. (Same reasoning as add-rule.sh's --applies-to.)
confirm=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --domain)     [ "$#" -ge 2 ] || die "--domain requires a value"; domain_arg="$2"; shift 2 ;;
    --stance)     [ "$#" -ge 2 ] || die "--stance requires a value"; stance_arg="$2"; shift 2 ;;
    --audience)   [ "$#" -ge 2 ] || die "--audience requires a value"; audience_arg="$2"; shift 2 ;;
    --competitor)
      [ "$#" -ge 2 ] || die "--competitor requires a value of the form \"<name>|<url>\""
      case "$2" in
        *$'\n'*) die "rejected: --competitor may not contain newline characters" ;;
        *'|'*)   : ;;
        *)       die "rejected: --competitor must be of the form \"<name>|<url>\" (got: $2)" ;;
      esac
      competitors_raw="${competitors_raw}${2}"$'\n'; shift 2 ;;
    --confirm)    confirm=1; shift ;;
    -h|--help)    grep -E '^# ' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *)            die "unknown argument: $1 (see --help)" ;;
  esac
done

command -v jq >/dev/null 2>&1 \
  || die "jq is required but not available — this writer builds and shape-validates JSON with it, and a writer that cannot validate must refuse rather than write unchecked bytes"

# ---------------------------------------------------------------------------
# 2. Resolve the repo root, then the two guards that can refuse before anything is scanned.
# ---------------------------------------------------------------------------
GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# ---- Worktree / submodule guard (carried verbatim in intent from add-rule.sh) --------------
# A linked worktree's top-level carries a `.git` FILE ("gitdir: ..."); a primary checkout carries a
# DIRECTORY — that is the whole discriminator. A submodule's top-level carries a `.git` FILE too,
# and refusing there is equally correct (product context belongs to the superproject), so the
# message names BOTH rather than sending a reader hunting a worktree that does not exist.
if [ -f "$GITROOT/.git" ]; then
  die "refusing to write from a non-primary checkout ($GITROOT) — its top-level \`.git\` is a FILE, which means either a linked git worktree or a git submodule. Product context is written only from the primary repo root: from a worktree the write would diverge and be lost on \`git worktree remove\`; from a submodule it would land in the wrong repository. Run this from the primary checkout (or the superproject root)." 3
fi

STORE_DIR="$GITROOT/.agent"
STORE="$STORE_DIR/product.json"

# ---- No-clobber guard. A bootstrap creates; it never edits. --------------------------------
if [ -e "$STORE" ]; then
  die "refusing to overwrite an existing product-context store at $STORE. This is a BOOTSTRAP, not an editor — clobbering it would destroy curated product knowledge. Edit the file directly (its shape is documented in docs/RESULT_SCHEMAS.md §PRODUCT_CONTEXT), or remove it first if you really want to start over."
fi

# ---------------------------------------------------------------------------
# 3. SCAN for a `domain` candidate. Read-only: every source is opened for reading and nothing
#    scanned is ever executed. `domain_source` is reported in the proposal so a human can judge the
#    candidate by where it came from.
# ---------------------------------------------------------------------------
domain_source="none"

# first_para_of_readme — the README's H1 text plus the first non-empty, non-heading, non-badge line
# after it. Bounded to the first 60 lines so a very long README cannot dominate the value.
scan_readme() {
  local f="$GITROOT/README.md" h1="" para=""
  [ -f "$f" ] || return 1
  h1="$(sed -n '1,60p' "$f" | grep -m1 -E '^# +[^ ]' | sed -E 's/^# +//' || true)"
  para="$(sed -n '1,60p' "$f" \
          | grep -vE '^\s*$|^#|^!\[|^\[!\[|^>|^-|^\||^```' \
          | head -1 || true)"
  if [ -n "$h1" ] && [ -n "$para" ]; then printf '%s — %s' "$h1" "$para"; return 0; fi
  if [ -n "$h1" ];   then printf '%s' "$h1";   return 0; fi
  if [ -n "$para" ]; then printf '%s' "$para"; return 0; fi
  return 1
}

scan_json_description() {   # $1 = manifest filename
  local f="$GITROOT/$1" v=""
  [ -f "$f" ] || return 1
  v="$(jq -r 'if type=="object" and (has("description")) and (.description|type=="string") then .description else empty end' "$f" 2>/dev/null || true)"
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

scan_toml_description() {   # $1 = manifest filename — `description = "..."`, first match only
  local f="$GITROOT/$1" v=""
  [ -f "$f" ] || return 1
  v="$(grep -m1 -E '^[[:space:]]*description[[:space:]]*=' "$f" 2>/dev/null \
        | sed -E 's/^[^=]*=[[:space:]]*//; s/^"//; s/"[[:space:]]*$//' || true)"
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

domain=""
if [ -n "$domain_arg" ]; then
  domain="$domain_arg"; domain_source="--domain (explicit)"
else
  if   v="$(scan_readme)"                            && [ -n "$v" ]; then domain="$v"; domain_source="README.md"
  elif v="$(scan_json_description package.json)"     && [ -n "$v" ]; then domain="$v"; domain_source="package.json .description"
  elif v="$(scan_toml_description pyproject.toml)"   && [ -n "$v" ]; then domain="$v"; domain_source="pyproject.toml description"
  elif v="$(scan_toml_description Cargo.toml)"       && [ -n "$v" ]; then domain="$v"; domain_source="Cargo.toml description"
  elif v="$(scan_json_description composer.json)"    && [ -n "$v" ]; then domain="$v"; domain_source="composer.json .description"
  else
    domain="$(basename "$GITROOT") — SCAN FOUND NO DESCRIPTION; replace this with what this project is, in the terms its own market uses"
    domain_source="repo directory name (nothing else found — this is a placeholder, not a finding)"
  fi
fi
# Collapse any tab/newline/CR a scanned source may carry, so one field can never span lines.
domain="$(printf '%s' "$domain" | tr '\t\n\r' '   ')"

# `audience` is NOT scanned. There is no honest signal for it in a repo, so the default says so.
audience="${audience_arg:-unspecified — ASSUMED, not evidence-backed: record who this serves and how you know}"

# ---------------------------------------------------------------------------
# 4. Provenance.
# ---------------------------------------------------------------------------
written_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
head_sha="$(git -C "$GITROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"

# ---------------------------------------------------------------------------
# 5. Build the object with jq (every value passed as --arg — never interpolated).
#    `stance` is written as supplied, or as the empty string when it was not supplied; V3 below is
#    what turns "not supplied" into a refusal rather than a guess.
# ---------------------------------------------------------------------------
competitors_json='[]'
if [ -n "$competitors_raw" ]; then
  competitors_json='[]'
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    c_name="${entry%%|*}"
    c_url="${entry#*|}"
    [ -n "$c_name" ] || die "rejected: --competitor \"$entry\" has an empty name"
    [ -n "$c_url" ]  || die "rejected: --competitor \"$entry\" has an empty url"
    # `last_fetched` is written as an EXPLICIT null — the key is REQUIRED and null means NEVER
    # FETCHED, which is the truth: this script performs no network access. It must never be a date.
    competitors_json="$(jq -c -n --argjson acc "$competitors_json" --arg n "$c_name" --arg u "$c_url" \
      '$acc + [{name: $n, url: $u, last_fetched: null}]')" \
      || die "failed to build the competitors array"
  done <<EOF
$competitors_raw
EOF
fi

new_obj="$(jq -n \
  --arg domain "$domain" \
  --arg stance "$stance_arg" \
  --arg audience "$audience" \
  --argjson competitors "$competitors_json" \
  --arg written_at "$written_at" \
  --arg head_sha "$head_sha" \
  '{domain: $domain, stance: $stance, audience: $audience, competitors: $competitors,
    written_at: $written_at, head_sha: $head_sha}')" \
  || die "failed to build the proposed product-context object"

# ---------------------------------------------------------------------------
# 6. VALIDATION (V1–V5). Shape only, and deliberately BEFORE the confirm gate, so a malformed
#    proposal is refused whether or not --confirm was passed — a dry-run must never print a plan
#    that a confirmed run would reject.
# ---------------------------------------------------------------------------
printf '%s' "$new_obj" | jq -e 'type == "object"' >/dev/null 2>&1 \
  || die "V1: the proposed store root is not a JSON object" 2

for k in domain stance audience competitors written_at head_sha; do
  printf '%s' "$new_obj" | jq -e --arg k "$k" 'has($k)' >/dev/null 2>&1 \
    || die "V2: required key \`$k\` is absent from the proposed store" 2
done

# V3 — `stance` is exactly "product" or "tool". This one check is GATE-AWARE, and deliberately so:
#   - a stance that was SUPPLIED but is out of enum is a user error and is refused HERE, on every
#     path, so a dry-run can never print a plan a confirmed run would reject;
#   - a stance that was NOT SUPPLIED AT ALL is not a malformed proposal, it is an unanswered
#     question. Refusing the dry-run for it would make the propose-only mode — the whole point of
#     this script — unreachable for a first-time user, who has nothing to look at yet. So the
#     dry-run PRINTS the proposal and says, in the printout, that `--stance` is what stands between
#     it and a write; the WRITE path (§7) refuses.
stance_ok=0
if printf '%s' "$new_obj" | jq -e '.stance == "product" or .stance == "tool"' >/dev/null 2>&1; then
  stance_ok=1
elif [ -n "$stance_arg" ]; then
  die "V3: \`stance\` must be exactly \"product\" or \"tool\" (got: $stance_arg)" 2
fi

# V4 — competitors[] shape. `has(\"last_fetched\")` is the presence assertion; a `//` default here
# would collapse a legitimate null (never fetched) into the missing-key case.
printf '%s' "$new_obj" | jq -e '
  (.competitors | type == "array")
  and (.competitors | all(
        (type == "object")
        and (has("name")) and (.name | type == "string") and (.name | length > 0)
        and (has("url"))  and (.url  | type == "string") and (.url  | length > 0)
        and (has("last_fetched"))
      ))' >/dev/null 2>&1 \
  || die "V4: \`competitors\` must be an array whose every entry is an object with non-empty string \`name\` and \`url\` and a PRESENT \`last_fetched\` key (null is legal — it means never fetched)" 2

# V5 — `stance_default_action` is EMITTED-BUT-NOT-STORED. Asserted rather than merely documented.
printf '%s' "$new_obj" | jq -e 'has("stance_default_action") | not' >/dev/null 2>&1 \
  || die "V5: \`stance_default_action\` must NEVER be a key in the store — it is derived by read-product.sh at read time from \`stance\`, and storing it would let the two disagree" 2

# ---------------------------------------------------------------------------
# 7. Confirm-only gate. Write on --confirm, or on an interactive TTY "yes". Otherwise DRY-RUN:
#    print the planned write and the scan provenance, and write NOTHING.
# ---------------------------------------------------------------------------
proceed=0
if [ "$confirm" -eq 1 ]; then
  proceed=1
elif [ -t 0 ] && [ -t 1 ]; then
  printf 'Create the product-context store %s ?\n' "$STORE" >&2
  printf '%s\n' "$new_obj" >&2
  printf 'Confirm write? [y/N] ' >&2
  read -r reply || reply=""
  case "$reply" in y|Y|yes|YES) proceed=1 ;; *) proceed=0 ;; esac
fi

if [ "$proceed" -ne 1 ]; then
  printf 'PLANNED WRITE (not written — pass --confirm to apply):\n'
  printf '  target: %s\n' "$STORE"
  if [ "$stance_ok" -ne 1 ]; then
    printf '  BLOCKED: --stance is REQUIRED before this can be written, and is never guessed. It decides the DEFAULT ACTION on a discovered gap (read-product.sh derives stance_default_action from it: product => build-highest-priority, tool => do-not-build-by-default), and no signal in a repo distinguishes the two. Re-run with --stance product or --stance tool.\n'
  fi
  printf '  domain source: %s\n' "$domain_source"
  printf '  audience: NOT scanned — supply --audience, or edit the file after it is created\n'
  printf '  competitors: NEVER auto-detected and never fetched — supply --competitor "<name>|<url>" (each is written last_fetched: null, meaning never fetched)\n'
  printf '  object: %s\n' "$new_obj"
  exit 0
fi

# V3 on the WRITE path (see §6). Reached only when a write is actually about to happen.
if [ "$stance_ok" -ne 1 ]; then
  die "V3: \`stance\` was not supplied, and it is never guessed. It decides the DEFAULT ACTION on a discovered gap (read-product.sh's STANCE_ACTIONS lookup: product => build-highest-priority, tool => do-not-build-by-default), and no signal in a repo distinguishes the two — a guess here would tell a payments app to skip its missing fraud checks. Nothing was written. Re-run with --stance product or --stance tool." 2
fi

# ---------------------------------------------------------------------------
# 8. Write: temp file in the SAME directory, then an atomic move. Nothing outside
#    `.agent/product.json` is written (the containing `.agent/` directory is created when absent,
#    and the temp file exists only until the move).
# ---------------------------------------------------------------------------
mkdir -p "$STORE_DIR" || die "could not create the store directory: $STORE_DIR"

tmp="$(mktemp "$STORE_DIR/.propose-product.XXXXXX")" || die "could not allocate a temp file in $STORE_DIR"
trap 'rm -f "$tmp" 2>/dev/null' EXIT

printf '%s\n' "$new_obj" > "$tmp" || die "failed to stage the product-context store (nothing written to $STORE)"
mv -f "$tmp" "$STORE" || die "atomic move failed (nothing written to $STORE)"

# ---------------------------------------------------------------------------
# 9. Read-back verify: the written file parses as an object AND carries the stance we validated.
# ---------------------------------------------------------------------------
jq -e 'type == "object"' "$STORE" >/dev/null 2>&1 \
  || die "read-back verify failed: the written file is not a valid JSON object: $STORE"
jq -e --arg s "$stance_arg" '.stance == $s' "$STORE" >/dev/null 2>&1 \
  || die "read-back verify failed: the written store's \`stance\` is not the validated value: $STORE"

printf 'wrote product context to %s (stance: %s)\n' "$STORE" "$stance_arg"
printf 'Next: review it by hand — `audience` and `competitors` are the two fields nothing can scan for you. Read it back with read-product.sh.\n'
exit 0
