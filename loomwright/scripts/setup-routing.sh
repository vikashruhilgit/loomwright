#!/usr/bin/env bash
# setup-routing.sh — deterministic engine for the `/setup providers` module: view, write and
# remove the per-seat provider routing a repo asks for (the `.routing` key of
# `<repo>/.supervisor/config.json`) and the user's per-repo, per-provider consent for it (the
# `repos.<slug>.providers` array of the USER-SCOPE `~/.claude/loomwright/egress.json`).
# `setup-providers.sh` stays the check-only probe; this is the one writer.
#
# WHAT IT WRITES — and the whole list is two files:
#   <repo>/.supervisor/config.json   key `.routing` ONLY        (apply --seat / --on-unavailable, remove)
#   ~/.claude/loomwright/egress.json key `.repos.<slug>.providers` ONLY   (apply --grant, remove)
#   Each is a jq merge or a jq `del`, never a rewrite from scratch, so every other key at every
#   level is preserved. Each rewrite of a pre-existing file makes one timestamped backup sibling
#   `<file>.backup.<ts>` first. No .gitignore write, no git ref write, no git history.
#
# CONSENT IS THE CALLER'S, NOT THIS SCRIPT'S. `--seat` only REQUESTS a route in the repo's own
# config (resolve-routing.sh treats that as `provider_not_granted` until a grant exists). `--grant`
# writes the user-scope grant, so the command layer (docs/command-parts/setup/providers.md) must
# run it only after an AskUserQuestion that names the provider and states what is sent to it. A
# seat write never writes a grant; a grant write never writes a seat.
#
# WHICH PROVIDERS. A non-Claude provider named by --seat or --grant must have a row in
# `setup-providers.sh check` whose verdict is `usable for read-only seats` or `usable for write
# seats` (a write-seat-usable provider is also usable read-only); any other verdict, or no row, is
# REFUSED. `claude` is always accepted as a seat value and needs (and takes) no grant. The seat ids
# are asked of `resolve-routing.sh seats` and the provider list of the check — neither is restated.
#
# SUBCOMMANDS
#   status
#       Read-only. Prints the config path, the raw `.routing` cell, this repo's slug, its
#       user-scope grants (PROVIDER_GRANTS), the providers the repo merely requests
#       (REPO_REQUESTED_PROVIDERS — informational, nothing grants from it), and one line per seat
#       from `resolve-routing.sh seat <id>` (the resolution every run will actually use). It does
#       NOT run the provider probe: the command layer renders `setup-providers.sh check` itself.
#   apply [--seat <id>=<provider>[:<model>]]... [--grant <provider>]... [--on-unavailable <v>]
#       --seat   set `.routing.seats.<id>`; repeat the same id for an ordered preference list.
#       --grant  add the provider to this repo's `providers` grant (user scope).
#       --on-unavailable fallback_to_default|strict   set `.routing.on_unavailable`.
#       At least one of the three is required (else a usage error). Every refusal happens before
#       any write, so a refused apply writes nothing. Idempotent by byte-comparison: when the
#       document it would write equals the one on disk (in jq's normal form) it writes nothing
#       and makes no backup. This run re-probes (`setup-providers.sh check`) when it names a
#       non-Claude provider.
#   remove
#       delete `.routing` from the repo config and this repo's `providers` grant — nothing else.
#       Each is backup-first and parse-gated; a target with nothing to remove is a no-op.
#
# HEADLINE LINES (the command layer relays them verbatim; one per target per run, prefixed with
# the subcommand and the target — `apply routing:`, `apply grant:`, `remove routing:`, `remove grant:`)
#   applied (created <file>)   applied  (+ `  backup: <path>`)   removed  (+ `  backup: <path>`)
#   no-op — <why>              REFUSED (<reason>) — <why>        ABORTED (<reason>) — <why>
#   REFUSED reasons: unknown_seat | invalid_provider_name | invalid_model | provider_not_probed |
#                    provider_not_usable | claude_needs_no_grant | no_repo_slug
#   ABORTED reasons: jq_unavailable | config_unparseable | routing_unexpected_shape |
#                    egress_unparseable | egress_unexpected_shape | symlink | path_outside_repo |
#                    containment_unavailable | no_home | seat_list_unavailable | no_backup_name |
#                    backup_failed | write_failed
#   (symlink: `mv` would replace a link with a regular file, so a symlinked target is refused.
#   path_outside_repo: the REPO config's physical location is not under the repo — a committed
#   `.supervisor -> /elsewhere` — refused by contained-path-lib.sh, which is loaded from this
#   script's directory (containment_unavailable when it cannot be). The user-scope egress.json
#   keeps its leaf-only `symlink` check: it lives outside any repo on purpose.)
#
# FAIL-SAFE CONTRACT (mirrors setup-base-branch.sh): every REFUSED / ABORTED branch writes
# nothing, makes no backup, and exits 0. A malformed target (unparseable, or not exactly one JSON
# object) ABORTS and is never "repaired". Only a usage error (missing subcommand, unknown
# subcommand or flag, a flag on the wrong subcommand, a malformed value) exits 2.
#
# USAGE
#   setup-routing.sh status [--repo <dir>]
#   setup-routing.sh apply [--seat <id>=<p>[:<m>]]... [--grant <p>]... [--on-unavailable <v>] [--repo <dir>]
#   setup-routing.sh remove [--repo <dir>]
#     --repo <dir>   repository whose .supervisor/config.json (and slug) is used (default: the git
#                    top-level of the current directory, else the current directory)
#
# Portability: bash 3.2 / BSD userland safe. jq is `command -v`-guarded and probed functionally.

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
ROUTING_RESOLVER="$script_dir/resolve-routing.sh"
EGRESS_RESOLVER="$script_dir/resolve-egress-config.sh"
PROBE="$script_dir/setup-providers.sh"
ME="setup-routing"
NL=$'\n'
TAB=$'\t'

# Return convention of apply_*/remove_* below: status 1 = "this target was written" (so a caller
# prints the verify block); status 0 = nothing was written (no-op, REFUSED or ABORTED).

usage_die() {
  printf '%s: usage error: %s\n' "$ME" "$1" >&2
  printf '%s: usage: setup-routing.sh status | apply [--seat <id>=<p>[:<m>]]... [--grant <p>]... [--on-unavailable <v>] | remove [--repo <dir>]\n' "$ME" >&2
  exit 2
}

SUBCMD="${1:-}"
[ $# -gt 0 ] && shift
SEAT_ARGS=""
GRANT_ARGS=""
ON_UNAV=""
REPO=""
REPO_GIVEN=0

case "$SUBCMD" in
  status|apply|remove) ;;
  -h|--help) sed -n '2,/^$/{s/^# \{0,1\}//;p;}' "$0"; exit 0 ;;
  '') usage_die "missing subcommand" ;;
  *) usage_die "unknown subcommand: $SUBCMD" ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || usage_die "--repo needs a value"; REPO="$2"; REPO_GIVEN=1; shift 2 ;;
    --seat)
      [ "$SUBCMD" = apply ] || usage_die "--seat is only valid for apply"
      [ $# -ge 2 ] || usage_die "--seat needs <id>=<provider>[:<model>]"
      case "$2" in *"$NL"*) usage_die "--seat value contains a newline" ;; esac
      case "$2" in ?*=?*) ;; *) usage_die "--seat needs <id>=<provider>[:<model>], got: $2" ;; esac
      SEAT_ARGS="${SEAT_ARGS}${2}${NL}"
      shift 2 ;;
    --grant)
      [ "$SUBCMD" = apply ] || usage_die "--grant is only valid for apply"
      [ $# -ge 2 ] || usage_die "--grant needs a provider name"
      case "$2" in *"$NL"*) usage_die "--grant value contains a newline" ;; esac
      [ -n "$2" ] || usage_die "--grant needs a provider name"
      GRANT_ARGS="${GRANT_ARGS}${2}${NL}"
      shift 2 ;;
    --on-unavailable)
      [ "$SUBCMD" = apply ] || usage_die "--on-unavailable is only valid for apply"
      [ $# -ge 2 ] || usage_die "--on-unavailable needs fallback_to_default or strict"
      case "$2" in fallback_to_default|strict) ON_UNAV="$2" ;; *) usage_die "--on-unavailable must be fallback_to_default or strict, got: $2" ;; esac
      shift 2 ;;
    *) usage_die "unknown argument: $1" ;;
  esac
done
if [ "$SUBCMD" = apply ] && [ -z "$SEAT_ARGS" ] && [ -z "$GRANT_ARGS" ] && [ -z "$ON_UNAV" ]; then
  usage_die "apply needs at least one of --seat, --grant, --on-unavailable"
fi

if [ "$REPO_GIVEN" -eq 1 ]; then
  { [ -n "$REPO" ] && [ -d "$REPO" ]; } || usage_die "--repo '$REPO' is not a directory"
  REPO="$(cd "$REPO" && pwd)"
else
  REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || REPO=""
  [ -n "$REPO" ] || REPO="$(pwd)"
fi
CFG="$REPO/.supervisor/config.json"
EGRESS="${HOME:-}/.claude/loomwright/egress.json"

# jq PRESENCE is not jq FUNCTION — probe it, and treat broken exactly like absent.
jq_works() {
  command -v jq >/dev/null 2>&1 || return 1
  printf '{}' | jq -e . >/dev/null 2>&1
}

# file_is_object <file> — the WHOLE file parses as exactly one JSON object (slurped, so trailing
# junk or a second document is refused).
file_is_object() {
  jq -se 'length == 1 and (.[0] | type) == "object"' "$1" >/dev/null 2>&1
}

# backup_path <file> — a `<file>.backup.<ts>` sibling that does not exist yet; pid- then
# counter-suffixed on a same-second collision; EMPTY (status 1) when every name is taken, so a
# caller aborts rather than overwrite an earlier backup.
backup_path() {
  local base cand i
  base="$1.backup.$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)"
  [ ! -e "$base" ] && { printf '%s' "$base"; return 0; }
  cand="$base.p$$"
  [ ! -e "$cand" ] && { printf '%s' "$cand"; return 0; }
  i=1
  while [ "$i" -le 50 ]; do
    cand="$base.p$$.$i"
    [ ! -e "$cand" ] && { printf '%s' "$cand"; return 0; }
    i=$((i + 1))
  done
  return 1
}

# stage_and_replace <label> <file> <doc> — parse-gate the composed document, stage it beside the
# target and atomically replace. Prints the ABORTED headline (returning 1) on any failure.
stage_and_replace() {
  local label="$1" file="$2" doc="$3" tmp tmp_failed=""
  if ! printf '%s' "$doc" | jq -se 'length == 1 and (.[0] | type) == "object"' >/dev/null 2>&1; then
    echo "$label: ABORTED (write_failed) — the composed document is not a JSON object; $file is unchanged."
    return 1
  fi
  tmp="$file.tmp.$$"
  # Keep the target's mode across the replace: stage over a `cp -p` copy of it (truncating keeps the
  # mode), so a 0600 egress.json never comes back 0644. A new egress.json is created owner-only.
  if [ -e "$file" ]; then
    cp -p "$file" "$tmp" 2>/dev/null || tmp_failed=1
  elif [ "$file" = "$EGRESS" ]; then
    ( umask 077 && : > "$tmp" ) 2>/dev/null || tmp_failed=1
  fi
  if [ -n "$tmp_failed" ] || ! printf '%s\n' "$doc" > "$tmp" 2>/dev/null || ! mv "$tmp" "$file" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null
    echo "$label: ABORTED (write_failed) — could not replace $file; it is unchanged."
    return 1
  fi
  return 0
}

# write_backed_up <label> <file> <doc> — backup, then stage_and_replace. Sets BACKUP_WRITTEN.
write_backed_up() {
  local label="$1" file="$2" doc="$3" backup
  backup="$(backup_path "$file")" || {
    echo "$label: ABORTED (no_backup_name) — every candidate backup name for $file is taken; nothing was written."
    return 1
  }
  cp -p "$file" "$backup" 2>/dev/null || {
    echo "$label: ABORTED (backup_failed) — could not back up $file; refusing to rewrite it unbacked-up. Nothing was written."
    return 1
  }
  if ! stage_and_replace "$label" "$file" "$doc"; then
    rm -f "$backup" 2>/dev/null
    return 1
  fi
  BACKUP_WRITTEN="$backup"
  return 0
}

# create_new <label> <file> <doc> — the target does not exist yet: make its directory and write it.
create_new() {
  local label="$1" file="$2" doc="$3"
  mkdir -p "$(dirname "$file")" 2>/dev/null || {
    echo "$label: ABORTED (write_failed) — could not create $(dirname "$file"); nothing was written."
    return 1
  }
  stage_and_replace "$label" "$file" "$doc"
}

refuse_symlink() { # refuse_symlink <label> <file>
  [ -L "$2" ] || return 0
  echo "$1: ABORTED (symlink) — $2 is a symlink; edit its target by hand. Nothing was written."
  return 1
}

# refuse_cfg <label> — the repo-scope twin of refuse_symlink: return 1 (headline printed) when $CFG
# is a symlink or its physical location is outside $REPO. The library loads lazily, from the
# executed script's directory; one that cannot load refuses (fail CLOSED).
refuse_cfg() {
  # shellcheck source=contained-path-lib.sh
  . "$script_dir/contained-path-lib.sh" 2>/dev/null || {
    echo "$1: ABORTED (containment_unavailable) — contained-path-lib.sh could not be loaded, so $CFG cannot be checked. Nothing was written."
    return 1
  }
  cpl_check_write "$1" "$CFG" "$REPO" symlink
}

# repo_slug — this repo's key in the user-scope file, exactly as resolve-egress-config.sh derives it.
repo_slug() {
  ( cd "$REPO" 2>/dev/null && bash "$EGRESS_RESOLVER" 2>/dev/null ) | sed -n 's/^REPO_SLUG=//p' | head -n 1
}

# egress_key <name> — one KEY=VALUE line's value from the resolver, run from the repo.
egress_key() {
  ( cd "$REPO" 2>/dev/null && bash "$EGRESS_RESOLVER" 2>/dev/null ) | sed -n "s/^$1=//p" | head -n 1
}

# routing_cell — the raw `.routing` value as a status cell.
routing_cell() {
  if [ ! -f "$CFG" ]; then printf 'absent (no config.json)'; return 0; fi
  if ! jq_works; then printf 'not probed (jq unavailable or non-functional)'; return 0; fi
  if ! file_is_object "$CFG"; then printf 'UNPARSEABLE (not exactly one JSON object) — apply/remove would ABORT'; return 0; fi
  jq -c 'if has("routing") | not then "absent" else .routing end' "$CFG" 2>/dev/null
}

do_status() {
  local slug grants requested id line
  echo "== providers routing =="
  echo "config: $CFG"
  echo "config .routing: $(routing_cell)"
  slug="$(egress_key REPO_SLUG)"
  grants="$(egress_key PROVIDER_GRANTS)"
  requested="$(egress_key REPO_REQUESTED_PROVIDERS)"
  echo "repo slug: ${slug:-(none — not inside a git repo)}"
  echo "user-scope file: $EGRESS"
  echo "grants (user scope, this repo): ${grants:-(none)}"
  echo "requested by this repo's config (informational — nothing grants from it): ${requested:-(none)}"
  echo "resolved seats (resolve-routing.sh):"
  if [ ! -r "$ROUTING_RESOLVER" ]; then
    echo "  (resolve-routing.sh not found at $ROUTING_RESOLVER)"
    return 0
  fi
  bash "$ROUTING_RESOLVER" seats 2>/dev/null | while IFS= read -r line; do
    id="${line%% *}"
    [ -n "$id" ] || continue
    bash "$ROUTING_RESOLVER" seat "$id" --repo "$REPO" 2>/dev/null | awk -F= -v id="$id" '
      $1 == "PROVIDER" { p = substr($0, 10) } $1 == "MODEL" { m = substr($0, 7) }
      $1 == "SOURCE" { s = substr($0, 8) } $1 == "REASON" { r = substr($0, 8) }
      END { printf "  %s: provider=%s model=%s source=%s reason=%s\n", id, p, m, s, r }'
  done
}

# ---- provider verdicts (apply only) ------------------------------------------------------
VERDICTS=""
VERDICTS_LOADED=0
load_verdicts() {
  [ "$VERDICTS_LOADED" -eq 0 ] || return 0
  VERDICTS_LOADED=1
  # Rows start at column 0 and end `=> <verdict>`; the label is `<name>` or `<name> (<cli>)`.
  VERDICTS="$(bash "$PROBE" check 2>/dev/null </dev/null | awk '
    /^[^[:space:]]/ && index($0, " => ") {
      v = $0; sub(/^.* => /, "", v)
      n = $0; sub(/:.*/, "", n); sub(/ .*/, "", n)
      print n "\t" v
    }')"
}

verdict_of() {
  printf '%s\n' "$VERDICTS" | awk -F'\t' -v n="$1" '$1 == n { print $2; exit }'
}

# provider_usable <label> <name> — 0 when the check marks <name> usable for read-only or write seats.
provider_usable() {
  local v
  load_verdicts
  v="$(verdict_of "$2")"
  case "$v" in
    "usable for read-only seats"|"usable for write seats") return 0 ;;
    "")
      echo "$1: REFUSED (provider_not_probed) — '$2' has no row in \`setup-providers.sh check\`; nothing was written."
      return 1 ;;
    *)
      echo "$1: REFUSED (provider_not_usable) — \`setup-providers.sh check\` reports '$2' as: $v. Only a provider marked 'usable for read-only seats' or 'usable for write seats' can be routed to; nothing was written."
      return 1 ;;
  esac
}

# ---- apply -------------------------------------------------------------------------------
PAIRS=""          # "<seat>\t<provider>[:<model>]" lines, validated
GRANT_LIST=""     # validated provider names, one per line

validate_apply_args() {
  local seat_ids entry sid val prov model g
  seat_ids=""
  if [ -n "$SEAT_ARGS" ]; then
    [ -r "$ROUTING_RESOLVER" ] && seat_ids=" $(bash "$ROUTING_RESOLVER" seats 2>/dev/null | awk '{printf "%s ", $1}')"
    if [ -z "${seat_ids# }" ]; then
      echo "apply: ABORTED (seat_list_unavailable) — \`resolve-routing.sh seats\` printed nothing; nothing was written."
      return 1
    fi
  fi
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    sid="${entry%%=*}"
    val="${entry#*=}"
    case "$sid" in
      ""|*[!a-z0-9_]*) echo "apply: REFUSED (unknown_seat) — '$sid' is not a seat id (see \`resolve-routing.sh seats\`); nothing was written."; return 1 ;;
    esac
    case "$seat_ids" in
      *" $sid "*) ;;
      *) echo "apply: REFUSED (unknown_seat) — '$sid' is not a seat id (see \`resolve-routing.sh seats\`); nothing was written."; return 1 ;;
    esac
    prov="${val%%:*}"
    model=""
    case "$val" in *:*) model="${val#*:}" ;; esac
    case "$prov" in
      ""|*[!A-Za-z0-9_-]*) echo "apply: REFUSED (invalid_provider_name) — '$prov' must match [A-Za-z0-9_-]+; nothing was written."; return 1 ;;
    esac
    case "$model" in
      *[!A-Za-z0-9._/@+:-]*) echo "apply: REFUSED (invalid_model) — '$model' has a character outside [A-Za-z0-9._/@+:-]; nothing was written."; return 1 ;;
    esac
    if [ "$prov" != claude ]; then
      provider_usable apply "$prov" || return 1
    fi
    PAIRS="${PAIRS}${sid}${TAB}${val}${NL}"
  done <<EOF
$SEAT_ARGS
EOF
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    case "$g" in
      *[!A-Za-z0-9_-]*) echo "apply: REFUSED (invalid_provider_name) — '$g' must match [A-Za-z0-9_-]+; nothing was written."; return 1 ;;
    esac
    if [ "$g" = claude ]; then
      echo "apply: REFUSED (claude_needs_no_grant) — claude never needs a grant; nothing was written."
      return 1
    fi
    provider_usable apply "$g" || return 1
    GRANT_LIST="${GRANT_LIST}${g}${NL}"
  done <<EOF
$GRANT_ARGS
EOF
  return 0
}

apply_routing() {
  local label="apply routing" seats_json proposed current
  if ! jq_works; then
    echo "$label: ABORTED (jq_unavailable) — jq is unavailable or non-functional; nothing was written."
    return 0
  fi
  refuse_cfg "$label" || return 0
  seats_json="$(printf '%s' "$PAIRS" | jq -Rn '
    reduce (inputs | select(length > 0) | split("\t")) as $p ({};
      (.[$p[0]] // []) as $a
      | .[$p[0]] = (if ($a | index($p[1])) != null then $a else $a + [$p[1]] end))
    | map_values(if length == 1 then .[0] else . end)' 2>/dev/null)"
  [ -n "$seats_json" ] || seats_json="{}"
  # shellcheck disable=SC2016
  local filter='.routing = ((.routing // {})
      | (if ($seats | length) > 0 then .seats = ((.seats // {}) + $seats) else . end)
      | (if $ou != "" then .on_unavailable = $ou else . end))'
  if [ ! -f "$CFG" ]; then
    proposed="$(printf '{}' | jq --argjson seats "$seats_json" --arg ou "$ON_UNAV" "$filter" 2>/dev/null)"
    create_new "$label" "$CFG" "$proposed" || return 0
    echo "$label: applied (created $CFG)"
    return 1   # signals "wrote something" to the caller
  fi
  if ! file_is_object "$CFG"; then
    echo "$label: ABORTED (config_unparseable) — $CFG is not exactly one JSON object. Nothing was written and no backup was made; fix it by hand first."
    return 0
  fi
  if ! jq -e '(.routing // {}) | type == "object" and ((.seats // {}) | type == "object")' "$CFG" >/dev/null 2>&1; then
    echo "$label: ABORTED (routing_unexpected_shape) — .routing (or .routing.seats) in $CFG is not an object. Nothing was written; fix it by hand first."
    return 0
  fi
  proposed="$(jq --argjson seats "$seats_json" --arg ou "$ON_UNAV" "$filter" "$CFG" 2>/dev/null)"
  current="$(jq . "$CFG" 2>/dev/null)"
  if [ -z "$proposed" ]; then
    echo "$label: ABORTED (write_failed) — could not compose the merged document; nothing was written."
    return 0
  fi
  if [ "$proposed" = "$current" ]; then
    echo "$label: no-op — already configured ($CFG already holds this routing); nothing was written."
    return 0
  fi
  BACKUP_WRITTEN=""
  write_backed_up "$label" "$CFG" "$proposed" || return 0
  echo "$label: applied"
  echo "  backup: $BACKUP_WRITTEN"
  return 1
}

apply_grant() {
  local label="apply grant" slug names_json proposed current
  if ! jq_works; then
    echo "$label: ABORTED (jq_unavailable) — jq is unavailable or non-functional; nothing was written."
    return 0
  fi
  if [ -z "${HOME:-}" ]; then
    echo "$label: ABORTED (no_home) — HOME is unset, so the user-scope file cannot be located; nothing was written."
    return 0
  fi
  slug="$(repo_slug)"
  if [ -z "$slug" ]; then
    echo "$label: REFUSED (no_repo_slug) — $REPO is not inside a git repository, so there is no slug to key the grant by; nothing was written."
    return 0
  fi
  refuse_symlink "$label" "$EGRESS" || return 0
  names_json="$(printf '%s' "$GRANT_LIST" | jq -Rn '[inputs | select(length > 0)] | unique' 2>/dev/null)"
  [ -n "$names_json" ] || names_json="[]"
  # shellcheck disable=SC2016
  local filter='.schema_version = (.schema_version // 1)
      | .repos = (.repos // {})
      | .repos[$s].providers = ((.repos[$s].providers // []) as $cur | $cur + ($g - $cur))'
  if [ ! -f "$EGRESS" ]; then
    proposed="$(printf '{}' | jq --arg s "$slug" --argjson g "$names_json" "$filter" 2>/dev/null)"
    create_new "$label" "$EGRESS" "$proposed" || return 0
    echo "$label: applied (created $EGRESS) — granted for $slug: $(printf '%s' "$GRANT_LIST" | tr '\n' ' ')"
    return 1
  fi
  if ! file_is_object "$EGRESS"; then
    echo "$label: ABORTED (egress_unparseable) — $EGRESS is not exactly one JSON object. Nothing was written and no backup was made; fix it by hand first."
    return 0
  fi
  if ! jq -e --arg s "$slug" '((.repos // {}) | type == "object") and (((.repos // {})[$s] // {}) | type == "object") and ((((.repos // {})[$s] // {}).providers // []) | type == "array")' "$EGRESS" >/dev/null 2>&1; then
    echo "$label: ABORTED (egress_unexpected_shape) — .repos, .repos[\"$slug\"] or its .providers in $EGRESS has the wrong type. Nothing was written; fix it by hand first."
    return 0
  fi
  proposed="$(jq --arg s "$slug" --argjson g "$names_json" "$filter" "$EGRESS" 2>/dev/null)"
  current="$(jq . "$EGRESS" 2>/dev/null)"
  if [ -z "$proposed" ]; then
    echo "$label: ABORTED (write_failed) — could not compose the merged document; nothing was written."
    return 0
  fi
  if [ "$proposed" = "$current" ]; then
    echo "$label: no-op — already granted ($EGRESS already lists these providers for $slug); nothing was written."
    return 0
  fi
  BACKUP_WRITTEN=""
  write_backed_up "$label" "$EGRESS" "$proposed" || return 0
  echo "$label: applied — granted for $slug: $(printf '%s' "$GRANT_LIST" | tr '\n' ' ')"
  echo "  backup: $BACKUP_WRITTEN"
  return 1
}

do_apply() {
  local wrote=0
  validate_apply_args || return 0
  if [ -n "$PAIRS" ] || [ -n "$ON_UNAV" ]; then
    apply_routing || wrote=1
  fi
  if [ -n "$GRANT_LIST" ]; then
    apply_grant || wrote=1
  fi
  if [ "$wrote" -eq 1 ]; then
    echo "verify:"; do_status
  fi
}

# ---- remove ------------------------------------------------------------------------------
remove_routing() {
  local label="remove routing" proposed
  if ! jq_works; then
    echo "$label: ABORTED (jq_unavailable) — jq is unavailable or non-functional; nothing was written."
    return 0
  fi
  refuse_cfg "$label" || return 0
  if [ ! -f "$CFG" ]; then
    echo "$label: no-op — $CFG does not exist; nothing was written."
    return 0
  fi
  if ! file_is_object "$CFG"; then
    echo "$label: ABORTED (config_unparseable) — $CFG is not exactly one JSON object. Nothing was written and no backup was made; fix it by hand first."
    return 0
  fi
  if ! jq -e 'has("routing")' "$CFG" >/dev/null 2>&1; then
    echo "$label: no-op — $CFG has no .routing; nothing was written."
    return 0
  fi
  proposed="$(jq 'del(.routing)' "$CFG" 2>/dev/null)"
  if [ -z "$proposed" ]; then
    echo "$label: ABORTED (write_failed) — could not compose the document; nothing was written."
    return 0
  fi
  BACKUP_WRITTEN=""
  write_backed_up "$label" "$CFG" "$proposed" || return 0
  echo "$label: removed (.routing deleted; every other key kept)"
  echo "  backup: $BACKUP_WRITTEN"
  return 1
}

remove_grant() {
  local label="remove grant" slug proposed
  if ! jq_works; then
    echo "$label: ABORTED (jq_unavailable) — jq is unavailable or non-functional; nothing was written."
    return 0
  fi
  if [ -z "${HOME:-}" ]; then
    echo "$label: ABORTED (no_home) — HOME is unset, so the user-scope file cannot be located; nothing was written."
    return 0
  fi
  slug="$(repo_slug)"
  if [ -z "$slug" ]; then
    echo "$label: REFUSED (no_repo_slug) — $REPO is not inside a git repository, so there is no slug to find a grant by; nothing was written."
    return 0
  fi
  refuse_symlink "$label" "$EGRESS" || return 0
  if [ ! -f "$EGRESS" ]; then
    echo "$label: no-op — $EGRESS does not exist; nothing was written."
    return 0
  fi
  if ! file_is_object "$EGRESS"; then
    echo "$label: ABORTED (egress_unparseable) — $EGRESS is not exactly one JSON object. Nothing was written and no backup was made; fix it by hand first."
    return 0
  fi
  if ! jq -e --arg s "$slug" '((.repos // {}) | type == "object") and (((.repos // {})[$s] // {}) | type == "object")' "$EGRESS" >/dev/null 2>&1; then
    echo "$label: ABORTED (egress_unexpected_shape) — .repos or .repos[\"$slug\"] in $EGRESS is not an object. Nothing was written; fix it by hand first."
    return 0
  fi
  if ! jq -e --arg s "$slug" '((.repos // {})[$s] // {}) | has("providers")' "$EGRESS" >/dev/null 2>&1; then
    echo "$label: no-op — $EGRESS has no providers grant for $slug; nothing was written."
    return 0
  fi
  proposed="$(jq --arg s "$slug" 'del(.repos[$s].providers)' "$EGRESS" 2>/dev/null)"
  if [ -z "$proposed" ]; then
    echo "$label: ABORTED (write_failed) — could not compose the document; nothing was written."
    return 0
  fi
  BACKUP_WRITTEN=""
  write_backed_up "$label" "$EGRESS" "$proposed" || return 0
  echo "$label: removed (providers grant for $slug deleted; every other key kept)"
  echo "  backup: $BACKUP_WRITTEN"
  return 1
}

do_remove() {
  local wrote=0
  remove_routing || wrote=1
  remove_grant || wrote=1
  if [ "$wrote" -eq 1 ]; then
    echo "verify:"; do_status
  fi
}

case "$SUBCMD" in
  status) do_status ;;
  apply) do_apply ;;
  remove) do_remove ;;
esac
exit 0
