#!/usr/bin/env bash
# test-resolve-routing.sh — direct unit tests for resolve-routing.sh
#
# Covers the resolver's contract (docs/PROVIDER_ROUTING.md): the closed seat list,
# the no-routing default for every seat, the string / array seat values, the
# malformed-input reasons, the five-step precedence (each step its own leg), the
# user-scope consent rule, and the unavailable-provider fallback / strict split.
#
# ISOLATION: the resolver runs from a COPY of the scripts in a scratch plugin tree,
# so the test can add stub provider-table entries without touching the repo; HOME
# is a scratch dir (the real operator's egress.json is never read); the repo under
# test is a scratch git repo with a pinned `origin` so its slug is hermetic; stub
# provider CLIs are PATH-stub files. Nothing touches the network.
#
# EXIT: 0 on full pass, 1 on any failure.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_ROUTING="$SCRIPT_DIR/resolve-routing.sh"
SRC_EGRESS="$SCRIPT_DIR/resolve-egress-config.sh"

for f in "$SRC_ROUTING" "$SRC_EGRESS"; do
  [ -f "$f" ] || { echo "FATAL  missing $f" >&2; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "FATAL  jq required" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FATAL  git required" >&2; exit 1; }

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS  $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL  $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
assert_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  expected='$2' actual='$3'"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

# ---- scratch plugin tree: real scripts + real provider table + three stubs ------
TAG="$$"
PLUGIN="$TMP/plugin"
mkdir -p "$PLUGIN/scripts/adapters/providers" "$TMP/bin"
cp "$SRC_ROUTING" "$SRC_EGRESS" "$PLUGIN/scripts/"
cp "$SCRIPT_DIR"/adapters/providers/provider-*.sh "$PLUGIN/scripts/adapters/providers/"
RESOLVER="$PLUGIN/scripts/resolve-routing.sh"

# teststub: granted + installed. teststubgone: granted, CLI never on PATH.
# teststubnog: installed but never granted.
make_provider() { # $1=name $2=cli
  printf 'PROVIDER_CLI_NAME="%s"\n' "$2" > "$PLUGIN/scripts/adapters/providers/provider-$1.sh"
}
make_provider teststub "teststub-cli-$TAG"
make_provider teststubgone "teststubgone-cli-$TAG"
make_provider teststubnog "teststubnog-cli-$TAG"
for c in "teststub-cli-$TAG" "teststubnog-cli-$TAG"; do
  printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/$c"
  chmod +x "$TMP/bin/$c"
done

# ---- scratch HOME with a user-scope grant, scratch repo with a pinned slug ------
SLUG="routing-owner/routing-repo"
H="$TMP/home"
EGRESS_FILE="$H/.claude/loomwright/egress.json"
mkdir -p "$(dirname "$EGRESS_FILE")"
export HOME="$H"
write_grants() { # $1 = JSON array for repos.<SLUG>.providers
  printf '{"schema_version":1,"repos":{"%s":{"providers":%s}}}' "$SLUG" "$1" > "$EGRESS_FILE"
}
write_grants '["teststub","teststubgone"]'

REPO="$TMP/repo"
mkdir -p "$REPO/.supervisor"
git -C "$REPO" init -q
git -C "$REPO" remote add origin "https://github.com/${SLUG}.git"

cfg() { printf '%s' "$1" > "$REPO/.supervisor/config.json"; }
nocfg() { rm -f "$REPO/.supervisor/config.json"; }

rr() { # resolver run inside the scratch repo; stub dir first on PATH
  ( cd "$REPO" && PATH="$TMP/bin:$PATH" bash "$RESOLVER" "$@" )
}
field() { printf '%s\n' "$1" | sed -nE "s/^$2=(.*)\$/\1/p" | head -n 1; }

# expect <label> <expected PROVIDER> <expected MODEL> <expected SOURCE> <expected REASON> <args...>
expect() {
  local label="$1" ep="$2" em="$3" es="$4" er="$5" out rc
  shift 5
  out="$(rr "$@")"; rc=$?
  assert_eq "$label rc=0" "0" "$rc"
  assert_eq "$label PROVIDER" "$ep" "$(field "$out" PROVIDER)"
  assert_eq "$label MODEL" "$em" "$(field "$out" MODEL)"
  assert_eq "$label SOURCE" "$es" "$(field "$out" SOURCE)"
  assert_eq "$label REASON" "$er" "$(field "$out" REASON)"
}

echo "==== Group 1: the closed seat list (seats) ===="
SEATS_OUT="$(rr seats)"
assert_eq "seats rc=0" "0" "$?"
BAD_ARITY="$(printf '%s\n' "$SEATS_OUT" | awk 'NF != 4 {print $0}')"
assert_eq "seats every line has 4 fields" "" "$BAD_ARITY"
DUPES="$(printf '%s\n' "$SEATS_OUT" | awk '{print $1}' | sort | uniq -d)"
assert_eq "seats ids are unique" "" "$DUPES"
BAD_HOME=""
BAD_VALIDATOR=""
while read -r sid home marker validator; do
  [ -f "$PLUGIN_ROOT/$home" ] || BAD_HOME="$BAD_HOME $sid($home)"
  if [ "$validator" != "-" ] && [ ! -f "$SCRIPT_DIR/$validator" ]; then BAD_VALIDATOR="$BAD_VALIDATOR $sid($validator)"; fi
done <<EOF
$SEATS_OUT
EOF
assert_eq "seats every home file exists" "" "$BAD_HOME"
assert_eq "seats every validator script exists" "" "$BAD_VALIDATOR"
# AC14: the conductor roles are not seats.
for conductor in worker supervisor supervisor_runner execute_manager context_keeper main_session autonomous automate drain_runner task_completed; do
  if printf '%s\n' "$SEATS_OUT" | awk '{print $1}' | grep -qx "$conductor"; then
    fail "conductor $conductor must not be a seat"
  else
    pass "conductor $conductor is not a seat"
  fi
done
expect "seat worker is unknown_seat" claude "" default unknown_seat seat worker
rr seats extra >/dev/null 2>&1; assert_eq "seats with extra arg is a usage error" "2" "$?"

echo ""
echo "==== Group 2: no routing block => every seat resolves to Claude (AC1) ===="
nocfg
while read -r sid _rest; do
  out="$(rr seat "$sid")"; rc=$?
  assert_eq "default $sid" "claude|||default|" "$(field "$out" PROVIDER)|$(field "$out" MODEL)||$(field "$out" SOURCE)|$(field "$out" REASON)"
  assert_eq "default $sid rc=0" "0" "$rc"
  assert_eq "default $sid SEAT echoed" "$sid" "$(field "$out" SEAT)"
  assert_eq "default $sid ON_UNAVAILABLE" "fallback_to_default" "$(field "$out" ON_UNAVAILABLE)"
done <<EOF
$SEATS_OUT
EOF
cfg '{"unrelated":true}'
expect "config without routing key" claude "" default "" seat heal_voter
cfg '{"routing":{}}'
expect "empty routing object" claude "" default "" seat heal_voter

echo ""
echo "==== Group 3: seat values — string split and ordered array (AC2) ===="
cfg '{"routing":{"seats":{"red_team":"teststub:gpt-5"}}}'
expect "string splits on first colon" teststub gpt-5 config "" seat red_team
cfg '{"routing":{"seats":{"red_team":"teststub:vendor/model:high"}}}'
expect "only the FIRST colon splits" teststub vendor/model:high config "" seat red_team
cfg '{"routing":{"seats":{"red_team":"teststub"}}}'
expect "no model => empty MODEL" teststub "" config "" seat red_team
cfg '{"routing":{"seats":{"red_team":["teststubnog:a","teststubgone:b","teststub:c","claude"]}}}'
expect "array: first granted AND installed wins (skips ungranted, skips uninstalled)" teststub c config "" seat red_team
cfg '{"routing":{"seats":{"red_team":["teststubgone","claude"]}}}'
expect "array: claude entry after an unavailable one wins" claude "" config "" seat red_team
cfg '{"routing":{"seats":{"red_team":"teststub:x"}}}'
out="$(rr seat red_team)"
assert_eq "on_unavailable absent reads fallback_to_default" "fallback_to_default" "$(field "$out" ON_UNAVAILABLE)"
cfg '{"routing":{"seats":{"red_team":"claude:sonnet"}}}'
expect "explicit claude needs no grant" claude sonnet config "" seat red_team

echo ""
echo "==== Group 4: malformed input => Claude with a named REASON (AC3) ===="
cfg 'not json at all'
expect "unparseable config" claude "" default config_unparseable seat red_team
cfg '[1,2]'
expect "config that is an array" claude "" default config_unparseable seat red_team
cfg '{"a":1}{"b":2}'
expect "config with two JSON documents" claude "" default config_unparseable seat red_team
: > "$REPO/.supervisor/config.json"
expect "empty config file" claude "" default config_unparseable seat red_team
cfg '{"routing":"teststub"}'
expect "routing not an object" claude "" default config_unparseable seat red_team
cfg '{"routing":{"seats":["teststub"]}}'
expect "routing.seats not an object" claude "" default config_unparseable seat red_team
cfg '{"routing":{"on_unavailable":"sometimes"}}'
expect "unknown on_unavailable value" claude "" default config_unparseable seat red_team
cfg '{"routing":{"default":"teststub"}}'
expect "routing.default other than claude" claude "" default routing_default_not_claude seat red_team
cfg '{"routing":{"default":"claude"}}'
expect "routing.default claude is fine" claude "" default "" seat red_team
cfg '{"routing":{"seats":{"not_a_seat":"teststub"}}}'
expect "config seat key not in seats" claude "" default unknown_seat seat red_team
cfg '{"routing":{"seats":{"red_team":"../../etc/x"}}}'
expect "provider name with path chars" claude "" config invalid_provider seat red_team
cfg '{"routing":{"seats":{"red_team":"nosuchprovider"}}}'
expect "provider with no table file" claude "" config invalid_provider seat red_team
cfg '{"routing":{"seats":{"red_team":"teststub:bad model"}}}'
expect "model failing its allowlist" claude "" config invalid_provider seat red_team
cfg '{"routing":{"seats":{"red_team":["teststub","nosuchprovider"]}}}'
expect "one bad entry poisons the whole list" claude "" config invalid_provider seat red_team
cfg '{"routing":{"seats":{"red_team":[]}}}'
expect "empty preference list" claude "" config invalid_provider seat red_team
cfg '{"routing":{"seats":{"red_team":42}}}'
expect "seat value of the wrong type" claude "" config invalid_provider seat red_team
cfg '{"routing":{"seats":{"red_team":"teststub\nclaude"}}}'
expect "newline inside a seat value" claude "" config invalid_provider seat red_team
nocfg
expect "unknown seat argument" claude "" default unknown_seat seat not_a_seat
expect "--route naming an unknown seat" claude "" default unknown_seat seat red_team --route not_a_seat=teststub
expect "--route with an invalid provider" claude "" route_flag invalid_provider seat red_team --route 'red_team=bad!name'
# usage errors exit 2
rr >/dev/null 2>&1; assert_eq "no subcommand is a usage error" "2" "$?"
rr bogus >/dev/null 2>&1; assert_eq "unknown subcommand is a usage error" "2" "$?"
rr seat >/dev/null 2>&1; assert_eq "seat without an id is a usage error" "2" "$?"
rr seat red_team --route nonsense >/dev/null 2>&1; assert_eq "--route without = is a usage error" "2" "$?"
rr seat red_team --route >/dev/null 2>&1; assert_eq "--route without a value is a usage error" "2" "$?"
rr seat red_team --repo "$TMP/does-not-exist" >/dev/null 2>&1; assert_eq "--repo missing dir is a usage error" "2" "$?"
rr seat red_team --bogus >/dev/null 2>&1; assert_eq "unknown flag is a usage error" "2" "$?"
rr seat $'red_team\nPROVIDER=cursor' >/dev/null 2>&1; assert_eq "seat id with a newline is a usage error (no forged KEY line)" "2" "$?"
out="$(rr seat 'not a seat')"
assert_eq "odd seat id => one PROVIDER line, unknown_seat" "1|unknown_seat" "$(printf '%s\n' "$out" | grep -c '^PROVIDER=')|$(field "$out" REASON)"

echo ""
echo "==== Group 5: precedence — one leg per step (AC4) ===="
# MODEL names the winner: flag=f, route=r, config=c, alias=a.
FULL='{"voter_provider":"teststub:a","routing":{"seats":{"heal_voter":"teststub:c","red_team":"teststub:c"}}}'
cfg "$FULL"
expect "heal_voter: --voter-provider flag beats everything" teststub f flag "" seat heal_voter --voter-provider teststub:f --route heal_voter=teststub:r
expect "heal_voter: --route beats config and alias" teststub r route_flag "" seat heal_voter --route heal_voter=teststub:r
expect "heal_voter: routing.seats beats the alias" teststub c config "" seat heal_voter
cfg '{"voter_provider":"teststub:a"}'
expect "heal_voter: the .voter_provider alias beats the default" teststub a voter_provider_alias "" seat heal_voter
nocfg
expect "heal_voter: nothing set is the default" claude "" default "" seat heal_voter
cfg "$FULL"
expect "other seat: --route beats config" teststub r route_flag "" seat red_team --route red_team=teststub:r
expect "other seat: routing.seats beats the default" teststub c config "" seat red_team
expect "other seat: --voter-provider does not apply" teststub c config "" seat red_team --voter-provider teststub:f
expect "other seat: the alias does not apply" claude "" default "" seat code_reviewer
expect "a --route for ANOTHER seat is ignored here" teststub c config "" seat red_team --route code_reviewer=teststub:r
expect "repeated --route: the last one wins" teststub r2 route_flag "" seat red_team --route red_team=teststub:r1 --route red_team=teststub:r2
expect "empty --voter-provider value falls through" teststub r route_flag "" seat heal_voter --voter-provider "" --route heal_voter=teststub:r

echo ""
echo "==== Group 6: consent is user scope only (AC7) ===="
cfg '{"routing":{"seats":{"red_team":"teststubnog:m"}}}'
expect "installed but no grant => provider_not_granted" claude "" config provider_not_granted seat red_team
cfg '{"routing":{"on_unavailable":"strict","seats":{"red_team":"teststubnog:m"}}}'
expect "provider_not_granted regardless of strict" claude "" config provider_not_granted seat red_team
cfg '{"routing":{"seats":{"red_team":"cursor:gpt-5"}}}'
expect "real cursor entry, no grant for it => provider_not_granted" claude "" config provider_not_granted seat red_team
# The repo asking is not a grant: it appears only under REPO_REQUESTED_PROVIDERS.
REQ_OUT="$( cd "$REPO" && bash "$PLUGIN/scripts/resolve-egress-config.sh" )"
assert_eq "repo request is informational" "cursor" "$(field "$REQ_OUT" REPO_REQUESTED_PROVIDERS)"
assert_eq "repo request grants nothing" "teststub,teststubgone" "$(field "$REQ_OUT" PROVIDER_GRANTS)"
# A planted grant in the REPO's own config is ignored.
cfg '{"providers":["teststubnog"],"repos":{"x":{"providers":["teststubnog"]}},"routing":{"seats":{"red_team":"teststubnog"}}}'
expect "a grant written into the repo config grants nothing" claude "" config provider_not_granted seat red_team
# No user-scope file at all.
mv "$EGRESS_FILE" "$H/egress.json.off"
cfg '{"routing":{"seats":{"red_team":"teststub"}}}'
expect "no egress.json => provider_not_granted" claude "" config provider_not_granted seat red_team
printf 'not json' > "$EGRESS_FILE"
expect "malformed egress.json => provider_not_granted (fail closed)" claude "" config provider_not_granted seat red_team
rm -f "$EGRESS_FILE"
mv "$H/egress.json.off" "$EGRESS_FILE"
# A grant for a DIFFERENT repo slug does not carry over.
printf '{"schema_version":1,"repos":{"other/repo":{"providers":["teststub"]}}}' > "$EGRESS_FILE"
expect "grant keyed to another repo => provider_not_granted" claude "" config provider_not_granted seat red_team
write_grants '["teststub","teststubgone"]'
expect "granted + installed => the provider" teststub "" config "" seat red_team

echo ""
echo "==== Group 7: granted but CLI not on PATH (AC9) ===="
cfg '{"routing":{"seats":{"red_team":"teststubgone:m"}}}'
expect "fallback_to_default (absent) => Claude + provider_unavailable" claude "" config provider_unavailable seat red_team
cfg '{"routing":{"on_unavailable":"fallback_to_default","seats":{"red_team":"teststubgone:m"}}}'
expect "fallback_to_default (explicit)" claude "" config provider_unavailable seat red_team
cfg '{"routing":{"on_unavailable":"strict","seats":{"red_team":"teststubgone:m"}}}'
out="$(rr seat red_team)"
assert_eq "strict => PROVIDER empty" "" "$(field "$out" PROVIDER)"
assert_eq "strict => REASON" "provider_unavailable_strict" "$(field "$out" REASON)"
assert_eq "strict => MODEL empty" "" "$(field "$out" MODEL)"
assert_eq "strict => ON_UNAVAILABLE echoed" "strict" "$(field "$out" ON_UNAVAILABLE)"
assert_eq "strict output still has a PROVIDER= line" "1" "$(printf '%s\n' "$out" | grep -c '^PROVIDER=$')"
cfg '{"routing":{"on_unavailable":"strict","seats":{"red_team":["teststubgone","teststub:ok"]}}}'
expect "strict + array: a later installed entry still wins" teststub ok config "" seat red_team
cfg '{"routing":{"on_unavailable":"strict","seats":{"red_team":["teststubnog","teststubgone"]}}}'
expect "strict + array: ungranted then granted-missing => strict" "" "" config provider_unavailable_strict seat red_team
cfg '{"routing":{"on_unavailable":"strict","seats":{"red_team":["teststubnog"]}}}'
expect "strict + only ungranted entries => provider_not_granted" claude "" config provider_not_granted seat red_team
cfg '{"routing":{"on_unavailable":"strict"}}'
expect "strict with nothing routed stays default" claude "" default "" seat red_team
nocfg
expect "--route + unavailable provider (no config) falls back" claude "" route_flag provider_unavailable seat red_team --route red_team=teststubgone

echo ""
echo "==== Group 8: --repo points the resolver at another checkout ===="
OTHER="$TMP/other"
mkdir -p "$OTHER/.supervisor"
git -C "$OTHER" init -q
git -C "$OTHER" remote add origin "https://github.com/${SLUG}.git"
printf '{"routing":{"seats":{"red_team":"teststub:other"}}}' > "$OTHER/.supervisor/config.json"
nocfg
out="$( cd "$TMP" && PATH="$TMP/bin:$PATH" bash "$RESOLVER" seat red_team --repo "$OTHER" )"
assert_eq "--repo reads that repo's config" "teststub|other|config" "$(field "$out" PROVIDER)|$(field "$out" MODEL)|$(field "$out" SOURCE)"

echo ""
echo "==== Group 9: docs/PROVIDER_ROUTING.md keeps its contract ===="
DOC="$PLUGIN_ROOT/docs/PROVIDER_ROUTING.md"
if [ -f "$DOC" ]; then
  assert_eq "doc has the Routed seat protocol section" "1" "$(grep -c '^## Routed seat protocol' "$DOC")"
  assert_eq "doc points at resolve-routing.sh seats for the seat list" "1" "$( [ "$(grep -c 'resolve-routing.sh seats' "$DOC")" -ge 1 ] && echo 1 || echo 0 )"
  assert_eq "doc states an empty PROVIDER takes the seat's degraded path" "1" "$(grep -qi 'empty `PROVIDER`' "$DOC" && echo 1 || echo 0)"
  # The doc must not restate the whole seat list (it lives only in the `seats` arm).
  RESTATED=0
  MISSING=0
  while read -r sid _rest; do
    if grep -q "\`$sid\`" "$DOC"; then RESTATED=$((RESTATED + 1)); else MISSING=$((MISSING + 1)); fi
  done <<EOF
$SEATS_OUT
EOF
  assert_eq "doc does not restate every seat id" "1" "$( [ "$MISSING" -ge 1 ] && echo 1 || echo 0 )"
else
  fail "docs/PROVIDER_ROUTING.md missing"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "=========================================="
echo "RESULT  total=$TOTAL  passed=$PASS_COUNT  failed=$FAIL_COUNT"
echo "=========================================="
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
