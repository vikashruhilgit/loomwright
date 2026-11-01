#!/usr/bin/env bash
# resolve-routing.sh — the ONE resolver for per-seat provider routing.
#
# A "seat" is a pipeline step that may run on a non-Claude AI CLI instead of the
# Claude Task / inline path. There are two closed lists, each with one home below:
# READ seats (`seats`: a reviewer, a grader, an analysis pass, run through
# lens-run.sh) and WRITE seats (`write-seats`: the code-edit step of a Claude task,
# delegated to adapters/providers/write-run.sh). This script answers, for one seat,
# "which provider runs it, and why". It never runs a provider itself. Procedure for
# the caller: docs/PROVIDER_ROUTING.md.
#
# SUBCOMMANDS
#   seats
#       The closed READ-seat list — THE one home of the read-seat ids (the
#       `seats)` case arm below). One line per seat: `<id> <home-file> <role-marker> <validator|->`
#       - <home-file>   plugin-root-relative path of the file that owns the seat's
#                       "Seat routing" paragraph.
#       - <role-marker> a whitespace-free token the routed provider's final text
#                       must contain (lens-roles.sh asks for it); `-` = the seat uses
#                       the lens-run.sh `issues[]` envelope and needs no marker.
#       - <validator>   the scripts/ validator run with `--raw` over the routed
#                       text (the SAME one the Claude path uses), `-` = none.
#       Read seats only. The conductor roles (main session, supervisor-runner,
#       execute-manager, context-keeper, the worker Task itself, the /autonomous and
#       /automate loops, the detached drain runner, the TaskCompleted hook) are NOT
#       seats and are not listed. The worker Task stays a conductor: only its edit
#       step is routable, as the `worker` WRITE seat below.
#   write-seats
#       The closed WRITE-seat list — THE one home of the write-seat ids (the
#       `write-seats)` case arm below). One line per seat: `<id> <home-file>`, where
#       <home-file> is the plugin-root-relative file that owns the seat's
#       "Seat routing" paragraph. A write seat resolves through `seat <id>` exactly
#       like a read seat, plus the per-seat write grant (CONSENT below). A write
#       seat never inherits another seat's provider: each reads only its own
#       `routing.seats.<id>` / `--route <id>=…`.
#   seat <id> [--route <seat>=<provider>[:<model>]]... [--voter-provider <p>[:<m>]] [--repo <dir>]
#       <id> is a read seat or a write seat. KEY=VALUE lines, always all six, in this order:
#         SEAT            the id asked about
#         PROVIDER        `claude` (run today's Task / inline path), a provider
#                         name, or EMPTY (strict + granted provider unavailable —
#                         the seat takes its existing degraded path, never a
#                         silent Claude run)
#         MODEL           the model part of `<provider>:<model>`, else empty
#         SOURCE          the winning precedence step: flag | route_flag | config |
#                         voter_provider_alias | default
#         REASON          empty on a clean resolution, else a named reason (below)
#         ON_UNAVAILABLE  fallback_to_default (default) | strict
#
# PRECEDENCE (first present step wins)
#   heal_voter:  --voter-provider  >  --route heal_voter=<p>  >  routing.seats.heal_voter
#                >  .voter_provider (the back-compatible alias)  >  default
#   any other:   --route <seat>=<p>  >  routing.seats.<seat>  >  default
#   default is always Claude. A seat value is `<provider>[:<model>]` (split on the
#   FIRST colon) or an ordered array of them; the first entry that is granted AND
#   whose provider CLI is on PATH wins.
#
# CONSENT: a non-Claude provider runs only when `resolve-egress-config.sh`'s
# PROVIDER_GRANTS (user scope, the egress file that script reads) names it for this
# repo. The repo's own config can only REQUEST a provider; a missing grant is
# `provider_not_granted` and never sends, whatever on_unavailable says. `claude`
# never needs a grant. A WRITE seat additionally needs the per-seat write grant:
# `resolve-egress-config.sh`'s PROVIDER_WRITE_GRANTS must hold `<seat>:<provider>`
# (user scope, `repos.<slug>.write_grants.<seat>`). A read grant without it is
# `write_not_granted`; a write grant without the read grant is still
# `provider_not_granted`. Neither ever sends, whatever on_unavailable says.
#
# REASONS (PROVIDER=claude unless noted; a malformed input never yields a
# non-Claude provider)
#   config_unparseable            config is not exactly one JSON object, or a
#                                 routing field has the wrong type / value
#   unknown_seat                  `seat <id>`, a routing.seats key or a --route
#                                 seat is in neither `seats` nor `write-seats`
#   invalid_provider              a provider name fails [A-Za-z0-9_-]+, has no
#                                 provider-<name>.sh table file, or a model fails
#                                 its character allowlist
#   routing_default_not_claude    routing.default is present and not `claude`
#   provider_not_granted          the provider has no user-scope grant for this repo
#   write_not_granted             a write seat's provider has the read grant but no
#                                 user-scope write grant for that seat
#   provider_unavailable          granted, but its CLI is not on PATH
#                                 (on_unavailable = fallback_to_default)
#   provider_unavailable_strict   same, with on_unavailable = strict — PROVIDER is EMPTY
#
# Exit: 0 for every known subcommand (a refusal is a REASON, not a failure);
# 2 on a usage error. Read-only: writes nothing. bash 3.2 + BSD userland safe.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVIDERS_DIR="$SCRIPT_DIR/adapters/providers"
EGRESS_RESOLVER="$SCRIPT_DIR/resolve-egress-config.sh"

usage() {
  printf 'resolve-routing.sh: %s\n' "${1:-usage error}" >&2
  printf 'usage: resolve-routing.sh seats\n' >&2
  printf '       resolve-routing.sh write-seats\n' >&2
  printf '       resolve-routing.sh seat <id> [--route <seat>=<provider>[:<model>]]... [--voter-provider <p>[:<m>]] [--repo <dir>]\n' >&2
  exit 2
}

SUBCMD="${1:-}"
case "$SUBCMD" in
  seats)
    [ $# -eq 1 ] || usage "seats takes no arguments"
    cat <<'SEATS'
plan_reviewer agents/launch-pad.md PLAN_REVIEW_RESULT validate-plan-review-result.py
orchestrator skills/async-orchestration/SKILL.md Work/Results -
rubric_grader skills/self-heal-advisory/completion-tail.md rubric_score -
heal_voter skills/self-heal-advisory/multi-voter.md - -
refute skills/self-heal-advisory/multi-voter.md - -
drain_reviewer skills/review-heal/SKILL.md CODE_REVIEW_RESULT validate-code-review-result.py
fallback_reviewer skills/review-heal/fallback-review.md CODE_REVIEW_RESULT validate-code-review-result.py
evaluate_reviewer skills/autonomous-loop/multi-iteration.md CODE_REVIEW_RESULT validate-code-review-result.py
postmortem_classifier skills/pr-postmortem/SKILL.md categories -
dreaming_analysis commands/dreaming.md Recurring -
capability_check commands/capability-check.md CAPABILITY_REPORT -
red_team commands/red-team-reviewer.md RED_TEAM_RESULT -
code_reviewer commands/code-reviewer.md CODE_REVIEW_RESULT validate-code-review-result.py
product_owner commands/product-owner.md HANDOFF -
qa_strategist commands/qa-strategist.md Classification -
SEATS
    exit 0
    ;;
  write-seats)
    [ $# -eq 1 ] || usage "write-seats takes no arguments"
    cat <<'WRITE_SEATS'
worker skills/async-orchestration/SKILL.md
heal_fix skills/self-heal-advisory/SKILL.md
drain_fix skills/review-heal/SKILL.md
WRITE_SEATS
    exit 0
    ;;
  seat) shift ;;
  *) usage "unknown or missing subcommand: ${SUBCMD}" ;;
esac

# ---- seat <id> ---------------------------------------------------------------
ID="${1:-}"
[ -n "$ID" ] || usage "seat needs an <id>"
shift
case "$ID" in -*) usage "seat needs an <id>, got a flag: $ID" ;; esac

NL=$'\n'
# The id is echoed as `SEAT=<id>`; an embedded newline would forge an extra
# KEY=VALUE line for a naive line-parsing consumer.
case "$ID" in *"$NL"*) usage "seat id contains a newline" ;; esac
FLAG_VOTER=""
ROUTE_FOR_ID=""
ROUTE_UNKNOWN=0
REPO="."

# The seat ids come from the `seats` and `write-seats` arms above — asked of this
# very script, so each list has exactly one home. Space-padded so `case` can match
# a whole id. SEAT_IDS is every routable id (read + write); WRITE_SEAT_IDS the
# write seats alone (they need the per-seat write grant).
WRITE_SEAT_IDS=" $(bash "${BASH_SOURCE[0]}" write-seats 2>/dev/null | awk '{printf "%s ", $1}')"
SEAT_IDS=" $(bash "${BASH_SOURCE[0]}" seats 2>/dev/null | awk '{printf "%s ", $1}')${WRITE_SEAT_IDS# }"

is_seat_id() {
  case "$1" in
    ""|*[!a-z0-9_]*) return 1 ;;
  esac
  case "$SEAT_IDS" in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

IS_WRITE_SEAT=0
case "$WRITE_SEAT_IDS" in
  *" $ID "*) IS_WRITE_SEAT=1 ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --route)
      [ $# -ge 2 ] || usage "--route needs <seat>=<provider>[:<model>]"
      case "$2" in
        *"$NL"*) usage "--route value contains a newline" ;;
        ?*=?*) ;;
        *) usage "--route needs <seat>=<provider>[:<model>], got: $2" ;;
      esac
      rs="${2%%=*}"
      rv="${2#*=}"
      if is_seat_id "$rs"; then
        [ "$rs" = "$ID" ] && ROUTE_FOR_ID="$rv"
      else
        ROUTE_UNKNOWN=1
      fi
      shift 2
      ;;
    --voter-provider)
      [ $# -ge 2 ] || usage "--voter-provider needs <provider>[:<model>]"
      case "$2" in *"$NL"*) usage "--voter-provider value contains a newline" ;; esac
      FLAG_VOTER="$2"
      shift 2
      ;;
    --repo)
      [ $# -ge 2 ] || usage "--repo needs a directory"
      REPO="$2"
      shift 2
      ;;
    *) usage "unrecognized argument: $1" ;;
  esac
done
[ -d "$REPO" ] || usage "--repo is not a directory: $REPO"

ON_UNAVAILABLE=fallback_to_default

# finish <provider> <model> <source> <reason> — print the six KEY=VALUE lines, exit 0.
finish() {
  printf 'SEAT=%s\n' "$ID"
  printf 'PROVIDER=%s\n' "$1"
  printf 'MODEL=%s\n' "$2"
  printf 'SOURCE=%s\n' "$3"
  printf 'REASON=%s\n' "$4"
  printf 'ON_UNAVAILABLE=%s\n' "$ON_UNAVAILABLE"
  exit 0
}

# SOURCE is `default` until a precedence step supplies a request.
SOURCE=default

is_seat_id "$ID" || finish claude "" "$SOURCE" unknown_seat
[ "$ROUTE_UNKNOWN" -eq 0 ] || finish claude "" "$SOURCE" unknown_seat

# ---- config (.supervisor/config.json) — fail CLOSED to Claude on anything malformed
CFG="$REPO/.supervisor/config.json"
HAVE_CFG=0
if [ -e "$CFG" ]; then
  command -v jq >/dev/null 2>&1 || finish claude "" "$SOURCE" config_unparseable
  jq -s -e 'length == 1 and (.[0] | type == "object")' "$CFG" >/dev/null 2>&1 \
    || finish claude "" "$SOURCE" config_unparseable
  HAVE_CFG=1

  STRUCT="$(jq -r '
    if (has("routing") and .routing != null and (.routing | type) != "object") then "config_unparseable"
    elif ((.routing // {}) | has("seats") and .seats != null and (.seats | type) != "object") then "config_unparseable"
    elif ((.routing // {}) | has("default") and .default != null and .default != "claude") then "routing_default_not_claude"
    elif ((.routing // {}) | has("on_unavailable") and .on_unavailable != null and .on_unavailable != "fallback_to_default" and .on_unavailable != "strict") then "config_unparseable"
    else "ok" end' "$CFG" 2>/dev/null)"
  case "$STRUCT" in
    ok) ;;
    config_unparseable|routing_default_not_claude) finish claude "" "$SOURCE" "$STRUCT" ;;
    *) finish claude "" "$SOURCE" config_unparseable ;;
  esac

  # A seat key the `seats` list does not know is a typo that would silently route
  # nothing — refuse every resolution until it is fixed (named, loud, still Claude).
  UNKNOWN_KEYS="$(jq -r --arg ids "$SEAT_IDS" '
    [ (.routing.seats // {}) | keys[] | . as $k
      | select(($k | test("\\A[a-z0-9_]+\\z") | not) or (($ids | contains(" " + $k + " ")) | not)) ] | length' "$CFG" 2>/dev/null)"
  case "$UNKNOWN_KEYS" in
    0) ;;
    *) finish claude "" "$SOURCE" unknown_seat ;;
  esac

  ON_UNAVAILABLE="$(jq -r '(.routing.on_unavailable // "fallback_to_default")' "$CFG" 2>/dev/null)"
  case "$ON_UNAVAILABLE" in
    fallback_to_default|strict) ;;
    *) ON_UNAVAILABLE=fallback_to_default; finish claude "" "$SOURCE" config_unparseable ;;
  esac
fi

# ---- precedence: which step supplies the request -----------------------------
ENTRIES=""
if [ "$ID" = "heal_voter" ] && [ -n "$FLAG_VOTER" ]; then
  ENTRIES="$FLAG_VOTER"
  SOURCE=flag
elif [ -n "$ROUTE_FOR_ID" ]; then
  ENTRIES="$ROUTE_FOR_ID"
  SOURCE=route_flag
fi

if [ -z "$ENTRIES" ] && [ "$HAVE_CFG" -eq 1 ]; then
  SEAT_KIND="$(jq -r --arg id "$ID" '
    (.routing.seats // {}) | if has($id) then
      (.[$id] | if type == "string" then "string" elif type == "array" then "array" elif . == null then "none" else "bad" end)
    else "none" end' "$CFG" 2>/dev/null)"
  case "$SEAT_KIND" in
    none) ;;
    string|array)
      # Entries are validated inside jq with \A..\z (Oniguruma's $ also matches
      # before an embedded newline); anything else becomes the "!INVALID" sentinel
      # that no provider name can equal.
      ENTRIES="$(jq -r --arg id "$ID" '
        .routing.seats[$id] | (if type == "string" then [.] else . end)
        | if (length > 0 and all(.[]; type == "string" and test("\\A[A-Za-z0-9_-]+(:[A-Za-z0-9._/@+:-]*)?\\z")))
          then .[] else "!INVALID" end' "$CFG" 2>/dev/null)"
      SOURCE=config
      [ -n "$ENTRIES" ] || ENTRIES="!INVALID"
      ;;
    *) finish claude "" config invalid_provider ;;
  esac
fi

if [ -z "$ENTRIES" ] && [ "$ID" = "heal_voter" ] && [ "$HAVE_CFG" -eq 1 ]; then
  ENTRIES="$(jq -r '(.voter_provider // "") | if type == "string" then . else "" end' "$CFG" 2>/dev/null)"
  [ -z "$ENTRIES" ] || SOURCE=voter_provider_alias
fi

# Nothing asked for anything: today's behaviour exactly.
[ -n "$ENTRIES" ] || finish claude "" "$SOURCE" ""

# ---- validate every entry before trusting any of them ------------------------
# split_entry <entry> sets E_NAME / E_MODEL; returns 1 when the entry is malformed.
split_entry() {
  E_NAME="${1%%:*}"
  E_MODEL=""
  case "$1" in *:*) E_MODEL="${1#*:}" ;; esac
  case "$1" in *"$NL"*) return 1 ;; esac
  case "$E_NAME" in ""|*[!A-Za-z0-9_-]*) return 1 ;; esac
  case "$E_MODEL" in *[!A-Za-z0-9._/@+:-]*) return 1 ;; esac
  [ -r "$PROVIDERS_DIR/provider-$E_NAME.sh" ] || return 1
  return 0
}

while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  split_entry "$entry" || finish claude "" "$SOURCE" invalid_provider
done <<EOF
$ENTRIES
EOF

# ---- grant (user scope only) and installed-ness ------------------------------
GRANTS=""
GRANTS_LOADED=0
load_grants() {
  [ "$GRANTS_LOADED" -eq 0 ] || return 0
  GRANTS_LOADED=1
  GRANTS=""
  [ -r "$EGRESS_RESOLVER" ] || return 0
  GRANTS="$( cd "$REPO" 2>/dev/null && bash "$EGRESS_RESOLVER" 2>/dev/null | sed -n 's/^PROVIDER_GRANTS=//p' | head -n 1 )"
  case "$GRANTS" in *[!A-Za-z0-9_,-]*) GRANTS="" ;; esac
}

is_granted() {
  load_grants
  case ",$GRANTS," in
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# The per-seat write grants, read from the same resolver run's sibling key. Every
# pair is `<seat>:<provider>`; anything outside that charset empties the whole value
# (fail CLOSED: no write grant).
WRITE_GRANTS=""
WRITE_GRANTS_LOADED=0
load_write_grants() {
  [ "$WRITE_GRANTS_LOADED" -eq 0 ] || return 0
  WRITE_GRANTS_LOADED=1
  WRITE_GRANTS=""
  [ -r "$EGRESS_RESOLVER" ] || return 0
  WRITE_GRANTS="$( cd "$REPO" 2>/dev/null && bash "$EGRESS_RESOLVER" 2>/dev/null | sed -n 's/^PROVIDER_WRITE_GRANTS=//p' | head -n 1 )"
  case "$WRITE_GRANTS" in *[!A-Za-z0-9_,:-]*) WRITE_GRANTS="" ;; esac
}

# is_write_granted <provider> — the user granted <provider> the write seat $ID here.
is_write_granted() {
  load_write_grants
  case ",$WRITE_GRANTS," in
    *",$ID:$1,"*) return 0 ;;
  esac
  return 1
}

# provider_cli <name> prints the table file's PROVIDER_CLI_NAME (empty when absent).
provider_cli() {
  ( . "$PROVIDERS_DIR/provider-$1.sh" >/dev/null 2>&1; printf '%s' "${PROVIDER_CLI_NAME:-}" )
}

NOT_GRANTED_SEEN=0
WRITE_NOT_GRANTED_SEEN=0
UNAVAILABLE_SEEN=0
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  split_entry "$entry" || finish claude "" "$SOURCE" invalid_provider
  if [ "$E_NAME" = "claude" ]; then
    finish claude "$E_MODEL" "$SOURCE" ""
  fi
  if ! is_granted "$E_NAME"; then
    NOT_GRANTED_SEEN=1
    continue
  fi
  if [ "$IS_WRITE_SEAT" -eq 1 ] && ! is_write_granted "$E_NAME"; then
    WRITE_NOT_GRANTED_SEEN=1
    continue
  fi
  CLI="$(provider_cli "$E_NAME")"
  [ -n "$CLI" ] || finish claude "" "$SOURCE" invalid_provider
  if command -v "$CLI" >/dev/null 2>&1; then
    finish "$E_NAME" "$E_MODEL" "$SOURCE" ""
  fi
  UNAVAILABLE_SEEN=1
done <<EOF
$ENTRIES
EOF

# No entry won. A granted-but-uninstalled provider follows on_unavailable; if every
# entry lacked a grant, the answer is write_not_granted (a write seat whose provider
# had the read grant but not the write grant) or provider_not_granted, whatever
# on_unavailable says — a missing grant never sends.
if [ "$UNAVAILABLE_SEEN" -eq 1 ]; then
  if [ "$ON_UNAVAILABLE" = "strict" ]; then
    finish "" "" "$SOURCE" provider_unavailable_strict
  fi
  finish claude "" "$SOURCE" provider_unavailable
fi
[ "$WRITE_NOT_GRANTED_SEEN" -eq 0 ] || finish claude "" "$SOURCE" write_not_granted
finish claude "" "$SOURCE" provider_not_granted
