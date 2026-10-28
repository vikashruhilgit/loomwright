#!/usr/bin/env bash
# test-setup-routing.sh — self-test for setup-routing.sh, the `/setup providers` writer
# (status / apply --seat --grant --on-unavailable / remove over <repo>/.supervisor/config.json
# `.routing` and the user-scope egress.json `repos.<slug>.providers`).
#
# Runs against the REAL engine and the REAL resolvers it calls, in mktemp -d fixtures only, with HOME
# relocated (the real operator's egress.json is never read or written). The provider probe it asks
# (`setup-providers.sh check`) is pointed at a temp providers dir (LOOMWRIGHT_PROVIDERS_DIR) holding
# stub table files named after three REAL table entries (read from adapters/providers/, never
# restated here) and stub CLIs first on PATH, so each verdict is deterministic and nothing reaches a
# vendor: one read-only-usable, one write-seat-usable, one not usable. The fixture repo is a git repo
# with a pinned fake `origin` URL, so its slug is fixed whatever the host's remotes are.
#
# Cases (each a function over an engine path, so the mutation controls re-run the same check):
#   c_usage             missing / unknown subcommand, a flag on the wrong subcommand, apply with no
#                       work, a malformed value ⇒ exit 2, nothing written
#   c_status_default    status with no config ⇒ `.routing: absent`, no grants, every seat Claude
#                       (source default), nothing written (AC16)
#   c_status_routed     a routed seat shows provider_not_granted until a grant exists, then the
#                       provider; status writes nothing (AC16)
#   c_verdict_readonly  a `usable for read-only seats` provider is accepted (AC17)
#   c_verdict_write     a `usable for write seats` provider is accepted (AC17)
#   c_verdict_refused   a not-usable provider and an unprobed name are REFUSED for --seat and --grant,
#                       nothing written; `claude` needs no probe for a seat and is refused as a grant
#   c_refuse_names      unknown seat / bad provider / bad model ⇒ REFUSED, nothing written
#   c_create            apply --seat with no config ⇒ created; NO egress file is written (a seat
#                       write never grants) (AC17)
#   c_merge             apply over a config with other keys ⇒ one backup equal to the pre-write file,
#                       every other key and seat preserved
#   c_idempotent        a second identical apply ⇒ no-op, byte-identical file, no new backup
#   c_array             the same seat repeated ⇒ an ordered preference list
#   c_on_unavailable    --on-unavailable strict ⇒ written
#   c_grant             apply --grant ⇒ egress.json created / merged (other repos and keys kept),
#                       backup equal to the pre-write file, idempotent, appends without reordering
#   c_remove            remove ⇒ only `.routing` and this repo's `providers` deleted (jq -S diff of
#                       the rest), backups equal to the pre-write files; a second remove is a no-op (AC18)
#   c_malformed         unparseable / two-document / non-object-routing config or egress ⇒ ABORTED,
#                       byte-identical, no backup
#   c_symlink           a symlinked config.json or egress.json ⇒ ABORTED (symlink); link and target kept
#   c_no_slug           a non-git directory ⇒ grant REFUSED (no_repo_slug); routing still works
#   c_mode              a write keeps the target's mode (a 0600 egress.json stays 0600, a 0640 config
#                       stays 0640) and a new egress.json is created 0600 under umask 022
# Mutation controls (gated: non-empty + differs + bash -n, on a scratch copy beside copies of the
# resolvers): `del(.routing)` → `del(.)` (c_remove must fail), the usable-verdict gate removed
# (c_verdict_refused must fail), the already-configured early exit deleted (c_idempotent must fail).
# Exit 0 = all pass, 1 = any failure, 2 = fixture setup broken.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$HERE/setup-routing.sh"
RPDIR="$HERE/adapters/providers"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }
setup_fail() { printf '  SETUP BROKEN: %s\n' "$1" >&2; exit 2; }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

[ -f "$ENGINE" ] || setup_fail "setup-routing.sh not found at $ENGINE"
for f in resolve-routing.sh resolve-egress-config.sh setup-providers.sh; do
  [ -f "$HERE/$f" ] || setup_fail "$f not found beside the engine"
done
command -v jq >/dev/null 2>&1 && printf '{}' | jq -e . >/dev/null 2>&1 || setup_fail "a working jq is required"

T="$(mktemp -d)" || setup_fail "mktemp -d failed"
trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"
mkdir -p "$T/home" "$T/bin" "$T/providers" || setup_fail "mkdir"
export HOME="$T/home"
export PATH="$T/bin:$PATH"
export LOOMWRIGHT_PROVIDERS_DIR="$T/providers"
export LOOMWRIGHT_PROVIDER_SMOKE_TIMEOUT=20 LOOMWRIGHT_PROVIDER_QUICK_TIMEOUT=10
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_TERMINAL_PROMPT=0
EGRESS="$HOME/.claude/loomwright/egress.json"

# Three REAL provider names (never claude, never a test-only teststub file) — read, not restated.
names=""
for f in "$RPDIR"/provider-*.sh; do
  [ -f "$f" ] || continue
  n="${f##*/provider-}"; n="${n%.sh}"
  case "$n" in claude|teststub*|""|*[!A-Za-z0-9_-]*) continue ;; esac
  names="$names $n"
done
# shellcheck disable=SC2086
set -- $names
[ $# -ge 3 ] || setup_fail "need three non-claude provider-<name>.sh files in $RPDIR (have: ${names:-none})"
P_RO="$1"; P_WR="$2"; P_NO="$3"
P_UNPROBED="no-such-provider-zz"

# make_stub <cli> <smoke: pass|garbage> <help-text> — a fake provider CLI on PATH.
make_stub() {
  {
    printf '#!/usr/bin/env bash\nSMOKE=%q\nHELP_TEXT=%q\n' "$2" "$3"
    cat <<'STUB'
case "${1:-}" in
  --version) printf '1.0.0\n'; exit 0 ;;
  --help)    printf '%s\n' "$HELP_TEXT"; exit 0 ;;
  -p)        : ;;
  *)         exit 2 ;;
esac
case "$SMOKE" in
  pass)    printf '%s\n' '{"result":"{\"probe\":\"loomwright-ok\"}"}' ;;
  garbage) printf 'this is not json {{{\n' ;;
esac
exit 0
STUB
  } > "$T/bin/$1"
  chmod +x "$T/bin/$1"
}

# write_provider <name> <pin-flags> — a TEST-ONLY probe-entry table file under the temp providers dir.
write_provider() {
  {
    printf '#!/usr/bin/env bash\nPROVIDER_CLI_NAME=%q\n' "lwstub-$1"
    cat <<'P'
PROVIDER_WORKSPACE_FLAG=0
PROVIDER_HOME_SCRUB=1
provider_build_argv() { PROVIDER_ARGV=("-p" "$PROMPT_CONTENT"); }
provider_extract_text() {
  PROVIDER_EXTRACTED=""
  [ -s "$1" ] || return 1
  "$JQ" -e 'type == "object"' "$1" >/dev/null 2>&1 || return 1
  PROVIDER_EXTRACTED="$("$JQ" -r '.result // empty' "$1" 2>/dev/null)"
  [ -n "$PROVIDER_EXTRACTED" ]
}
PROBE_VERSION_ARGV=("--version")
PROBE_AUTH_ARGV=()
PROBE_AUTH_NOT_LOGGED_IN_RE='NOT-LOGGED-IN'
PROBE_HELP_ARGV=("--help")
probe_smoke_argv() { PROBE_ARGV=("-p" "$PROBE_PROMPT"); }
PROBE_BROWSER=no
P
    printf 'PROBE_PERM_PIN_FLAGS=%q\nPROBE_INSTALL_HINT=x\nPROBE_LOGIN_HINT=y\n' "$2"
  } > "$T/providers/provider-$1.sh"
}

write_provider "$P_RO" none
write_provider "$P_WR" "--allow --deny"
write_provider "$P_NO" none
make_stub "lwstub-$P_RO" pass "usage"
make_stub "lwstub-$P_WR" pass "usage --allow --deny"
make_stub "lwstub-$P_NO" garbage "usage"
# The REAL resolver (resolve-routing.sh) decides installed-ness from the real table file's CLI name,
# so put a harmless stub under that name first on PATH: a granted route then resolves to the provider.
for p in "$P_RO" "$P_WR"; do
  cli="$( . "$RPDIR/provider-$p.sh" >/dev/null 2>&1; printf '%s' "${PROVIDER_CLI_NAME:-}" )"
  [ -n "$cli" ] || setup_fail "provider-$p.sh declares no PROVIDER_CLI_NAME"
  make_stub "$cli" pass "usage"
done

# fresh <name> — a new git repo at $T/<name> with a pinned origin (slug example/<name>) and a clean HOME.
fresh() {
  rm -rf "${T:?}/$1" "$HOME/.claude"
  git init -q "$T/$1" >/dev/null 2>&1 || setup_fail "git init $1"
  git -C "$T/$1" remote add origin "https://github.com/example/$1.git" || setup_fail "remote add $1"
  printf '%s' "$T/$1"
}
slug_of() { printf 'example/%s' "$1"; }

# run <engine> <repo> <args...> -> $out / $rc
run() { local e="$1" r="$2"; shift 2; out="$(bash "$e" "$@" --repo "$r" 2>&1)"; rc=$?; }
nbackups() { ls -1 "$1".backup.* 2>/dev/null | wc -l | tr -d ' '; }
cfg() { printf '%s' "$1/.supervisor/config.json"; }
first_backup() { ls -1 "$1".backup.* 2>/dev/null | head -1; }
seed_cfg() {
  mkdir -p "$1/.supervisor"
  cat > "$(cfg "$1")" <<'JSONEOF'
{
  "voter_provider": "codex",
  "auto_review": false,
  "nested": { "a": [1, 2, {"b": null}], "s": "x" },
  "webhook_url": "https://hooks.example.invalid/x"
}
JSONEOF
}
seed_egress() { # seed_egress <slug> — other repos, other keys, and a pre-existing grant for <slug>
  mkdir -p "$(dirname "$EGRESS")"
  jq -n --arg s "$1" '{schema_version: 1, extra: {k: [1, 2]},
    repos: {($s): {telemetry: "always_allow", telemetry_repo: "o/r", providers: ["zeta"]},
            "other/repo": {telemetry: "no", providers: ["keepme"]}}}' > "$EGRESS"
}
untouched() { # untouched <file> <snapshot> — same bytes, no backup sibling
  cmp -s "$1" "$2" && [ "$(nbackups "$1")" = "0" ]
}

c_usage() {
  local e="$1" r; r="$(fresh us)"
  out="$(bash "$e" 2>&1)"; [ $? -eq 2 ] || { echo "no subcommand: not exit 2"; return 1; }
  out="$(bash "$e" frob --repo "$r" 2>&1)"; [ $? -eq 2 ] || { echo "unknown subcommand: not exit 2"; return 1; }
  out="$(bash "$e" status --seat "x=y" --repo "$r" 2>&1)"; [ $? -eq 2 ] || { echo "--seat on status: not exit 2"; return 1; }
  out="$(bash "$e" remove --grant x --repo "$r" 2>&1)"; [ $? -eq 2 ] || { echo "--grant on remove: not exit 2"; return 1; }
  out="$(bash "$e" apply --repo "$r" 2>&1)"; [ $? -eq 2 ] || { echo "empty apply: not exit 2"; return 1; }
  out="$(bash "$e" apply --seat nopair --repo "$r" 2>&1)"; [ $? -eq 2 ] || { echo "--seat without =: not exit 2"; return 1; }
  out="$(bash "$e" apply --on-unavailable maybe --repo "$r" 2>&1)"; [ $? -eq 2 ] || { echo "bad --on-unavailable: not exit 2"; return 1; }
  out="$(bash "$e" apply --grant --repo "$r" 2>&1)"; [ $? -eq 2 ] || { echo "--grant without value: not exit 2"; return 1; }
  out="$(bash "$e" status --repo "$T/does-not-exist" 2>&1)"; [ $? -eq 2 ] || { echo "bad --repo: not exit 2"; return 1; }
  [ ! -e "$(cfg "$r")" ] && [ ! -e "$EGRESS" ] || { echo "a usage error wrote something"; return 1; }
}

c_status_default() {
  local e="$1" r; r="$(fresh sd)"
  run "$e" "$r" status
  [ "$rc" -eq 0 ] && has "$out" "config .routing: absent (no config.json)" && has "$out" "grants (user scope, this repo): (none)" \
    && has "$out" "repo slug: $(slug_of sd)" || { echo "rc=$rc out=$out"; return 1; }
  has "$out" "heal_voter: provider=claude model= source=default reason=" || { echo "heal_voter line missing: $out"; return 1; }
  has "$out" "provider=$P_RO" && { echo "a seat resolved to a non-Claude provider: $out"; return 1; }
  [ ! -e "$(cfg "$r")" ] && [ ! -d "$r/.supervisor" ] && [ ! -e "$EGRESS" ] || { echo "status wrote something"; return 1; }
}

c_status_routed() {
  local e="$1" r; r="$(fresh sr)"
  run "$e" "$r" apply --seat "heal_voter=$P_RO:modelx"
  run "$e" "$r" status
  has "$out" "heal_voter: provider=claude model= source=config reason=provider_not_granted" || { echo "ungranted: $out"; return 1; }
  has "$out" "requested by this repo's config (informational — nothing grants from it): $P_RO" || { echo "requested line: $out"; return 1; }
  run "$e" "$r" apply --grant "$P_RO"
  run "$e" "$r" status
  has "$out" "grants (user scope, this repo): $P_RO" && has "$out" "heal_voter: provider=$P_RO model=modelx source=config reason=" \
    || { echo "granted: $out"; return 1; }
}

c_verdict_readonly() {
  local e="$1" r; r="$(fresh vr)"
  run "$e" "$r" apply --seat "refute=$P_RO"
  [ "$rc" -eq 0 ] && has "$out" "apply routing: applied (created" && [ "$(jq -r '.routing.seats.refute' "$(cfg "$r")")" = "$P_RO" ] \
    || { echo "seat: rc=$rc out=$out"; return 1; }
  run "$e" "$r" apply --grant "$P_RO"
  has "$out" "apply grant: applied (created" && jq -e --arg s "$(slug_of vr)" --arg p "$P_RO" '.repos[$s].providers == [$p]' "$EGRESS" >/dev/null \
    || { echo "grant: out=$out"; return 1; }
}

c_verdict_write() {
  local e="$1" r; r="$(fresh vw)"
  run "$e" "$r" apply --seat "refute=$P_WR" --grant "$P_WR"
  [ "$rc" -eq 0 ] && has "$out" "apply routing: applied (created" && has "$out" "apply grant: applied (created" \
    && [ "$(jq -r '.routing.seats.refute' "$(cfg "$r")")" = "$P_WR" ] \
    && jq -e --arg s "$(slug_of vw)" --arg p "$P_WR" '.repos[$s].providers == [$p]' "$EGRESS" >/dev/null \
    || { echo "rc=$rc out=$out"; return 1; }
}

c_verdict_refused() {
  local e="$1" r p flag; r="$(fresh vf)"; seed_cfg "$r"; cp "$(cfg "$r")" "$T/vf.cfg"
  seed_egress "$(slug_of vf)"; cp "$EGRESS" "$T/vf.egress"
  for flag in --seat --grant; do
    for p in "$P_NO" "$P_UNPROBED"; do
      if [ "$flag" = --seat ]; then run "$e" "$r" apply --seat "refute=$p"; else run "$e" "$r" apply --grant "$p"; fi
      [ "$rc" -eq 0 ] && has "$out" "apply: REFUSED (provider_not_" || { echo "$flag $p: rc=$rc out=$out"; return 1; }
    done
  done
  run "$e" "$r" apply --seat "refute=$P_NO"
  has "$out" "provider_not_usable" && has "$out" "not usable" || { echo "verdict not relayed: $out"; return 1; }
  run "$e" "$r" apply --seat "refute=$P_UNPROBED"
  has "$out" "provider_not_probed" || { echo "unprobed: $out"; return 1; }
  # a refused provider anywhere in the call refuses the WHOLE call: the good seat is not written either
  run "$e" "$r" apply --seat "refute=$P_RO" --grant "$P_NO"
  has "$out" "apply: REFUSED (provider_not_usable)" || { echo "mixed: $out"; return 1; }
  untouched "$(cfg "$r")" "$T/vf.cfg" && untouched "$EGRESS" "$T/vf.egress" || { echo "a refusal wrote something"; return 1; }
  # claude: a seat value needs no probe; as a grant it is refused
  run "$e" "$r" apply --grant claude
  has "$out" "REFUSED (claude_needs_no_grant)" || { echo "claude grant: $out"; return 1; }
  untouched "$EGRESS" "$T/vf.egress" || { echo "claude grant wrote"; return 1; }
  run "$e" "$r" apply --seat "refute=claude"
  has "$out" "apply routing: applied" && [ "$(jq -r '.routing.seats.refute' "$(cfg "$r")")" = "claude" ] || { echo "claude seat: $out"; return 1; }
}

c_refuse_names() {
  local e="$1" r; r="$(fresh rn)"; seed_cfg "$r"; cp "$(cfg "$r")" "$T/rn.cfg"
  run "$e" "$r" apply --seat "worker=$P_RO"
  has "$out" "REFUSED (unknown_seat)" || { echo "worker: $out"; return 1; }
  run "$e" "$r" apply --seat "Bad-Seat=$P_RO"
  has "$out" "REFUSED (unknown_seat)" || { echo "Bad-Seat: $out"; return 1; }
  run "$e" "$r" apply --seat 'refute=bad name'
  has "$out" "REFUSED (invalid_provider_name)" || { echo "bad provider: $out"; return 1; }
  run "$e" "$r" apply --seat "refute=$P_RO:bad model"
  has "$out" "REFUSED (invalid_model)" || { echo "bad model: $out"; return 1; }
  run "$e" "$r" apply --grant 'bad/name'
  has "$out" "REFUSED (invalid_provider_name)" || { echo "bad grant: $out"; return 1; }
  untouched "$(cfg "$r")" "$T/rn.cfg" && [ ! -e "$EGRESS" ] || { echo "a refusal wrote something"; return 1; }
}

c_create() {
  local e="$1" r; r="$(fresh cr)"
  run "$e" "$r" apply --seat "heal_voter=$P_RO:m1" --seat "refute=$P_RO"
  [ "$rc" -eq 0 ] && has "$out" "apply routing: applied (created" && has "$out" "verify:" || { echo "rc=$rc out=$out"; return 1; }
  [ "$(jq -r '.routing.seats.heal_voter' "$(cfg "$r")")" = "$P_RO:m1" ] && [ "$(jq -r '.routing.seats.refute' "$(cfg "$r")")" = "$P_RO" ] \
    || { echo "seats not written: $(cat "$(cfg "$r")")"; return 1; }
  jq -e '.routing | has("default") | not' "$(cfg "$r")" >/dev/null || { echo "a routing.default was written"; return 1; }
  # a seat write is a REQUEST: it never writes the user-scope grant
  [ ! -e "$EGRESS" ] || { echo "a seat write created the user-scope file"; return 1; }
}

c_merge() {
  local e="$1" r c; r="$(fresh mg)"; seed_cfg "$r"; c="$(cfg "$r")"
  jq '.routing = {on_unavailable: "strict", seats: {plan_reviewer: "claude"}}' "$c" > "$c.t" && mv "$c.t" "$c"
  cp "$c" "$T/mg.before"
  run "$e" "$r" apply --seat "refute=$P_RO"
  [ "$rc" -eq 0 ] && has "$out" "apply routing: applied" && has "$out" "backup: " || { echo "rc=$rc out=$out"; return 1; }
  [ "$(nbackups "$c")" = "1" ] && cmp -s "$T/mg.before" "$(first_backup "$c")" || { echo "want exactly 1 backup equal to the pre-write file"; return 1; }
  [ "$(jq -S 'del(.routing.seats.refute)' "$c")" = "$(jq -S . "$T/mg.before")" ] || { echo "another key or seat changed: $(cat "$c")"; return 1; }
  [ "$(jq -r '.routing.seats.refute' "$c")" = "$P_RO" ] || { echo "seat not written"; return 1; }
}

c_idempotent() {
  local e="$1" r c n; r="$(fresh id)"; seed_cfg "$r"; c="$(cfg "$r")"
  bash "$e" apply --seat "refute=$P_RO" --grant "$P_RO" --repo "$r" >/dev/null 2>&1
  cp "$c" "$T/id.cfg"; cp "$EGRESS" "$T/id.egress"; n="$(nbackups "$c")"
  run "$e" "$r" apply --seat "refute=$P_RO" --grant "$P_RO"
  [ "$rc" -eq 0 ] && has "$out" "apply routing: no-op — already configured" && has "$out" "apply grant: no-op — already granted" \
    || { echo "second apply: rc=$rc out=$out"; return 1; }
  cmp -s "$c" "$T/id.cfg" && cmp -s "$EGRESS" "$T/id.egress" || { echo "a file changed on the second apply"; return 1; }
  [ "$(nbackups "$c")" = "$n" ] && [ "$(nbackups "$EGRESS")" = "0" ] || { echo "a new backup was made"; return 1; }
}

c_array() {
  local e="$1" r c; r="$(fresh ar)"; c="$(cfg "$r")"
  run "$e" "$r" apply --seat "refute=$P_RO:a" --seat "refute=$P_WR" --seat "refute=$P_RO:a"
  [ "$rc" -eq 0 ] && jq -e --arg a "$P_RO:a" --arg b "$P_WR" '.routing.seats.refute == [$a, $b]' "$c" >/dev/null \
    || { echo "rc=$rc out=$out cfg=$(cat "$c" 2>/dev/null)"; return 1; }
}

c_on_unavailable() {
  local e="$1" r c; r="$(fresh ou)"; seed_cfg "$r"; c="$(cfg "$r")"
  run "$e" "$r" apply --on-unavailable strict
  [ "$rc" -eq 0 ] && has "$out" "apply routing: applied" && [ "$(jq -r '.routing.on_unavailable' "$c")" = "strict" ] \
    && jq -e '.routing | has("seats") | not' "$c" >/dev/null || { echo "rc=$rc out=$out cfg=$(cat "$c")"; return 1; }
}

c_grant() {
  local e="$1" r c s; r="$(fresh gr)"; s="$(slug_of gr)"
  seed_egress "$s"; cp "$EGRESS" "$T/gr.before"
  run "$e" "$r" apply --grant "$P_RO" --grant "$P_WR"
  [ "$rc" -eq 0 ] && has "$out" "apply grant: applied" && has "$out" "backup: " || { echo "rc=$rc out=$out"; return 1; }
  [ "$(nbackups "$EGRESS")" = "1" ] && cmp -s "$T/gr.before" "$(first_backup "$EGRESS")" || { echo "want exactly 1 backup equal to the pre-write file"; return 1; }
  # appended after the existing grant, existing order kept; everything else untouched
  jq -e --arg s "$s" --arg a "$P_RO" --arg b "$P_WR" '.repos[$s].providers[0] == "zeta" and (.repos[$s].providers | sort) == (["zeta", $a, $b] | sort)' "$EGRESS" >/dev/null \
    || { echo "providers wrong: $(cat "$EGRESS")"; return 1; }
  [ "$(jq -S --arg s "$s" 'del(.repos[$s].providers)' "$EGRESS")" = "$(jq -S --arg s "$s" 'del(.repos[$s].providers)' "$T/gr.before")" ] \
    || { echo "another key changed: $(cat "$EGRESS")"; return 1; }
  # the resolver every run uses agrees
  c="$( cd "$r" && bash "$HERE/resolve-egress-config.sh" | sed -n 's/^PROVIDER_GRANTS=//p' )"
  has ",$c," ",$P_RO," && has ",$c," ",$P_WR," || { echo "resolver PROVIDER_GRANTS=$c"; return 1; }
  # a grant never writes the repo config
  [ ! -e "$(cfg "$r")" ] || { echo "a grant wrote the repo config"; return 1; }
}

c_remove() {
  local e="$1" r c s; r="$(fresh rv)"; s="$(slug_of rv)"; seed_cfg "$r"; c="$(cfg "$r")"
  seed_egress "$s"
  bash "$e" apply --seat "refute=$P_RO" --grant "$P_RO" --repo "$r" >/dev/null 2>&1
  rm -f "$c".backup.* "$EGRESS".backup.*
  cp "$c" "$T/rv.cfg"; cp "$EGRESS" "$T/rv.egress"
  run "$e" "$r" remove
  [ "$rc" -eq 0 ] && has "$out" "remove routing: removed" && has "$out" "remove grant: removed" || { echo "remove: rc=$rc out=$out"; return 1; }
  jq -e 'has("routing") | not' "$c" >/dev/null || { echo ".routing still present"; return 1; }
  [ "$(jq -S . "$c")" = "$(jq -S 'del(.routing)' "$T/rv.cfg")" ] || { echo "another config key changed: $(cat "$c")"; return 1; }
  jq -e --arg s "$s" '.repos[$s] | has("providers") | not' "$EGRESS" >/dev/null || { echo "providers grant still present"; return 1; }
  [ "$(jq -S . "$EGRESS")" = "$(jq -S --arg s "$s" 'del(.repos[$s].providers)' "$T/rv.egress")" ] || { echo "another egress key changed: $(cat "$EGRESS")"; return 1; }
  jq -e '.repos["other/repo"].providers == ["keepme"] and .extra.k == [1, 2]' "$EGRESS" >/dev/null || { echo "another repo's grant or key was lost"; return 1; }
  [ "$(nbackups "$c")" = "1" ] && cmp -s "$T/rv.cfg" "$(first_backup "$c")" || { echo "config backup missing or differs"; return 1; }
  [ "$(nbackups "$EGRESS")" = "1" ] && cmp -s "$T/rv.egress" "$(first_backup "$EGRESS")" || { echo "egress backup missing or differs"; return 1; }
  cp "$c" "$T/rv.cfg2"; cp "$EGRESS" "$T/rv.egress2"
  run "$e" "$r" remove
  has "$out" "remove routing: no-op" && has "$out" "remove grant: no-op" && cmp -s "$c" "$T/rv.cfg2" && cmp -s "$EGRESS" "$T/rv.egress2" \
    && [ "$(nbackups "$c")" = "1" ] && [ "$(nbackups "$EGRESS")" = "1" ] || { echo "second remove: $out"; return 1; }
  # nothing to remove at all: no files, still a no-op
  r="$(fresh rv2)"
  run "$e" "$r" remove
  has "$out" "remove routing: no-op" && has "$out" "remove grant: no-op" && [ ! -e "$(cfg "$r")" ] && [ ! -e "$EGRESS" ] || { echo "empty remove: $out"; return 1; }
}

c_malformed() {
  local e="$1" r c body sub
  for body in '{"a": 1' '{} {}' '[1, 2]'; do
    r="$(fresh mf)"; mkdir -p "$r/.supervisor"; c="$(cfg "$r")"; printf '%s\n' "$body" > "$c"; cp "$c" "$T/mf.cfg"
    mkdir -p "$(dirname "$EGRESS")"; printf '%s\n' "$body" > "$EGRESS"; cp "$EGRESS" "$T/mf.egress"
    for sub in "apply --seat refute=$P_RO" "apply --grant $P_RO" remove; do
      # shellcheck disable=SC2086
      run "$e" "$r" $sub
      [ "$rc" -eq 0 ] && has "$out" "ABORTED (" || { echo "[$body] $sub: rc=$rc out=$out"; return 1; }
      untouched "$c" "$T/mf.cfg" && untouched "$EGRESS" "$T/mf.egress" || { echo "[$body] $sub wrote something"; return 1; }
    done
  done
  # well-formed JSON of the wrong shape
  r="$(fresh ms)"; mkdir -p "$r/.supervisor"; c="$(cfg "$r")"; printf '{"routing": [1]}\n' > "$c"; cp "$c" "$T/ms.cfg"
  run "$e" "$r" apply --seat "refute=$P_RO"
  has "$out" "ABORTED (routing_unexpected_shape)" && untouched "$c" "$T/ms.cfg" || { echo "routing array: $out"; return 1; }
  mkdir -p "$(dirname "$EGRESS")"; printf '{"repos": {"%s": {"providers": "x"}}}\n' "$(slug_of ms)" > "$EGRESS"; cp "$EGRESS" "$T/ms.egress"
  run "$e" "$r" apply --grant "$P_RO"
  has "$out" "ABORTED (egress_unexpected_shape)" && untouched "$EGRESS" "$T/ms.egress" || { echo "providers string: $out"; return 1; }
}

c_symlink() {
  local e="$1" r c sub; r="$(fresh sl)"; mkdir -p "$r/.supervisor"; c="$(cfg "$r")"
  printf '{"k": 1}\n' > "$T/sl.target"; cp "$T/sl.target" "$T/sl.snap"; ln -s "$T/sl.target" "$c"
  mkdir -p "$(dirname "$EGRESS")"; ln -s "$T/sl.target" "$EGRESS"
  for sub in "apply --seat refute=$P_RO" "apply --grant $P_RO" remove; do
    # shellcheck disable=SC2086
    run "$e" "$r" $sub
    has "$out" "ABORTED (symlink)" || { echo "$sub: $out"; return 1; }
  done
  [ -L "$c" ] && [ -L "$EGRESS" ] && cmp -s "$T/sl.target" "$T/sl.snap" || { echo "a link or its target changed"; return 1; }
}

mode_of() { ls -ld "$1" 2>/dev/null | cut -c1-10; }  # portable: no stat flavour

c_mode() {
  local e="$1" r c; r="$(fresh md)"; c="$(cfg "$r")"
  seed_egress "$(slug_of md)"; chmod 600 "$EGRESS"
  run "$e" "$r" apply --grant "$P_RO"
  has "$out" "apply grant: applied" && [ "$(mode_of "$EGRESS")" = "-rw-------" ] || { echo "merged egress: $(mode_of "$EGRESS") $out"; return 1; }
  seed_cfg "$r"; chmod 640 "$c"
  run "$e" "$r" apply --seat "refute=$P_RO"
  has "$out" "apply routing: applied" && [ "$(mode_of "$c")" = "-rw-r-----" ] || { echo "merged config: $(mode_of "$c") $out"; return 1; }
  r="$(fresh mn)"
  out="$(umask 022; bash "$e" apply --grant "$P_RO" --repo "$r" 2>&1)"
  has "$out" "apply grant: applied" && [ "$(mode_of "$EGRESS")" = "-rw-------" ] || { echo "new egress: $(mode_of "$EGRESS") $out"; return 1; }
}

c_no_slug() {
  local e="$1" r="$T/nogit"
  rm -rf "$r" "$HOME/.claude"; mkdir -p "$r"
  run "$e" "$r" apply --grant "$P_RO"
  has "$out" "apply grant: REFUSED (no_repo_slug)" && [ ! -e "$EGRESS" ] || { echo "grant: $out"; return 1; }
  run "$e" "$r" apply --seat "refute=$P_RO"
  has "$out" "apply routing: applied (created" || { echo "routing in a non-git dir: $out"; return 1; }
  run "$e" "$r" remove
  has "$out" "remove grant: REFUSED (no_repo_slug)" && has "$out" "remove routing: removed" || { echo "remove: $out"; return 1; }
}

CASES="c_usage c_status_default c_status_routed c_verdict_readonly c_verdict_write c_verdict_refused c_refuse_names c_create c_merge c_idempotent c_array c_on_unavailable c_grant c_remove c_malformed c_symlink c_mode c_no_slug"

echo "== setup-routing.sh =="
for c in $CASES; do
  if msg="$($c "$ENGINE")"; then ok "$c"; else no "$c" "$msg"; fi
done

echo "== mutation controls (each must turn its case red) =="
# mutant <name> <awk program> <case> — scratch copy beside copies of the scripts it calls; gated.
mutant() {
  local name="$1" prog="$2" case_fn="$3" d="$T/mut-$1" f
  mkdir -p "$d"
  for f in resolve-routing.sh resolve-egress-config.sh setup-providers.sh; do cp "$HERE/$f" "$d/$f"; done
  ln -s "$HERE/adapters" "$d/adapters"
  awk "$prog" "$ENGINE" > "$d/setup-routing.sh"
  if [ ! -s "$d/setup-routing.sh" ] || cmp -s "$d/setup-routing.sh" "$ENGINE" || ! bash -n "$d/setup-routing.sh" 2>/dev/null; then
    no "MUTATION CONTROL $name: mutant is empty, identical or does not parse — control inconclusive"; return 0
  fi
  if "$case_fn" "$d/setup-routing.sh" >/dev/null 2>&1; then
    no "MUTATION CONTROL $name: $case_fn still PASSES against the mutant"
  else
    ok "MUTATION CONTROL $name: $case_fn is red against the mutant"
  fi
}
mutant remove-deletes-everything '{ if (index($0, "proposed=\"$(jq '\''del(.routing)'\''")) sub(/del\(\.routing\)/, "del(.)"); print }' c_remove
mutant no-verdict-gate '/^provider_usable\(\) \{/ { print; print "  return 0"; next } { print }' c_verdict_refused
mutant no-idempotent-exit '/if \[ "\$proposed" = "\$current" \]; then/ { skip = 4 } skip > 0 { skip--; next } { print }' c_idempotent

echo
echo "test-setup-routing: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
