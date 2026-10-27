#!/usr/bin/env bash
# test-setup-base-branch.sh — self-test for setup-base-branch.sh, the `/setup base-branch` engine
# (status / set <branch> / remove over <repo>/.supervisor/config.json `.base_branch`).
#
# Runs against the REAL engine and the REAL resolver it calls, in mktemp -d fixtures only, with
# HOME relocated and a failing `gh` stub first on PATH (no case may reach the network). The
# fixture repo is a clone of a local bare origin carrying `main` and `development`, so origin/HEAD
# is `main` and `origin/development` exists; the bare origin is filled by `fetch` into it.
#
# Cases (each a function over an engine path, so the mutation controls re-run the same check):
#   c_status_default  status with no config ⇒ `base-branch: main (source: origin-head)`, no write
#   c_create          set development with no config.json ⇒ created, value set, status shows
#                     `development (source: config)` (AC16)
#   c_merge           set development over a config with other keys ⇒ one backup equal to the
#                     pre-write file, every other key preserved (jq -S diff), status from config (AC16)
#   c_idempotent      a second identical set ⇒ `no-op — already configured`, byte-identical file,
#                     no new backup (AC16)
#   c_refuse_missing  set no-such-branch ⇒ REFUSED (no_such_remote_branch), nothing written (AC17)
#   c_refuse_invalid  set bad..name / -x / "" ⇒ REFUSED (invalid_branch_name), nothing written (AC17)
#   c_remove          remove ⇒ only .base_branch deleted (jq -S diff of the rest), backup equal to
#                     the pre-write file; a second remove is a no-op (AC18)
#   c_malformed       unparseable / two-document config ⇒ set and remove ABORT (config_unparseable),
#                     byte-identical, no backup; status reports base_branch_invalid:config (AC18)
#   c_symlink         a symlinked config.json ⇒ set and remove ABORT (config_symlink); link and target kept
#   c_unresolved      no origin, no config ⇒ status `unresolved (base_branch_unresolved)`
#   c_usage           missing / unknown subcommand, set without a branch ⇒ exit 2
# Mutation controls (gated: non-empty + differs + bash -n, on a scratch copy beside a copy of the
# resolver): remove writes `{}` (c_remove must fail), the already-configured early exit deleted
# (c_idempotent must fail), the origin/<branch> check deleted (c_refuse_missing must fail).
# Exit 0 = all pass, 1 = any failure, 2 = fixture setup broken.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$HERE/setup-base-branch.sh"
RESOLVER="$HERE/resolve-base-branch.sh"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }
setup_fail() { printf '  SETUP BROKEN: %s\n' "$1" >&2; exit 2; }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

[ -f "$ENGINE" ] || setup_fail "setup-base-branch.sh not found at $ENGINE"
[ -f "$RESOLVER" ] || setup_fail "resolve-base-branch.sh not found at $RESOLVER"
command -v jq >/dev/null 2>&1 && printf '{}' | jq -e . >/dev/null 2>&1 || setup_fail "a working jq is required"

T="$(mktemp -d)" || setup_fail "mktemp -d failed"
trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"
mkdir -p "$T/home" "$T/bin" || setup_fail "mkdir"
export HOME="$T/home"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/gh"; chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_TERMINAL_PROMPT=0

# Bare origin with main + development, filled by fetch from a seed repo; then a clone of it.
SEED="$T/seed"; ORIGIN="$T/origin.git"
git init -q "$SEED" && git -C "$SEED" symbolic-ref HEAD refs/heads/main \
  && git -C "$SEED" commit -q --allow-empty -m init \
  && git -C "$SEED" branch development || setup_fail "seed repo"
git init -q --bare "$ORIGIN" && git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main \
  && git -C "$ORIGIN" fetch -q "$SEED" 'refs/heads/*:refs/heads/*' || setup_fail "bare origin"

# fresh <name> — a new clone at $T/<name>; prints its path.
fresh() {
  rm -rf "${T:?}/$1"
  git clone -q "$ORIGIN" "$T/$1" >/dev/null 2>&1 || setup_fail "clone $1"
  git -C "$T/$1" rev-parse -q --verify refs/remotes/origin/development >/dev/null || setup_fail "clone $1 lacks origin/development"
  printf '%s' "$T/$1"
}

# run <engine> <repo> <args...> -> $out / $rc
run() { local e="$1" r="$2"; shift 2; out="$(bash "$e" "$@" --repo "$r" 2>&1)"; rc=$?; }
nbackups() { ls -1 "$1".backup.* 2>/dev/null | wc -l | tr -d ' '; }
cfg() { printf '%s' "$1/.supervisor/config.json"; }
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

c_status_default() {
  local e="$1" r; r="$(fresh sd)"
  run "$e" "$r" status
  [ "$rc" -eq 0 ] && has "$out" "base-branch: main (source: origin-head)" && [ ! -e "$(cfg "$r")" ] \
    || { echo "rc=$rc out=$out"; return 1; }
}

c_create() {
  local e="$1" r; r="$(fresh cr)"
  run "$e" "$r" set development
  [ "$rc" -eq 0 ] && has "$out" "set: applied (created" || { echo "set: rc=$rc out=$out"; return 1; }
  [ "$(jq -r .base_branch "$(cfg "$r")")" = "development" ] || { echo "value not written"; return 1; }
  run "$e" "$r" status
  has "$out" "base-branch: development (source: config)" || { echo "status: $out"; return 1; }
}

c_merge() {
  local e="$1" r c; r="$(fresh mg)"; seed_cfg "$r"; c="$(cfg "$r")"
  cp "$c" "$T/mg.before"
  run "$e" "$r" set development
  [ "$rc" -eq 0 ] && has "$out" "set: applied" && has "$out" "backup: " || { echo "set: rc=$rc out=$out"; return 1; }
  [ "$(nbackups "$c")" = "1" ] || { echo "want exactly 1 backup, have $(nbackups "$c")"; return 1; }
  cmp -s "$T/mg.before" "$(ls -1 "$c".backup.* | head -1)" || { echo "backup differs from the pre-write file"; return 1; }
  [ "$(jq -S 'del(.base_branch)' "$c")" = "$(jq -S . "$T/mg.before")" ] || { echo "another key changed"; return 1; }
  [ "$(jq -r .base_branch "$c")" = "development" ] || { echo "value not written"; return 1; }
  run "$e" "$r" status
  has "$out" "base-branch: development (source: config)" || { echo "status: $out"; return 1; }
}

c_idempotent() {
  local e="$1" r c n; r="$(fresh id)"; seed_cfg "$r"; c="$(cfg "$r")"
  bash "$e" set development --repo "$r" >/dev/null 2>&1
  cp "$c" "$T/id.snap"; n="$(nbackups "$c")"
  run "$e" "$r" set development
  [ "$rc" -eq 0 ] && has "$out" "set: no-op — already configured" || { echo "second set: rc=$rc out=$out"; return 1; }
  cmp -s "$c" "$T/id.snap" || { echo "file changed on the second set"; return 1; }
  [ "$(nbackups "$c")" = "$n" ] || { echo "a new backup was made ($n -> $(nbackups "$c"))"; return 1; }
}

c_refuse_missing() {
  local e="$1" r c; r="$(fresh rm1)"; seed_cfg "$r"; c="$(cfg "$r")"; cp "$c" "$T/rm1.snap"
  run "$e" "$r" set no-such-branch
  [ "$rc" -eq 0 ] && has "$out" "set: REFUSED (no_such_remote_branch)" || { echo "rc=$rc out=$out"; return 1; }
  cmp -s "$c" "$T/rm1.snap" && [ "$(nbackups "$c")" = "0" ] || { echo "something was written"; return 1; }
  # with no config.json at all, a refusal must not create one
  r="$(fresh rm2)"
  run "$e" "$r" set no-such-branch
  has "$out" "REFUSED (no_such_remote_branch)" && [ ! -e "$(cfg "$r")" ] && [ ! -d "$r/.supervisor" ] \
    || { echo "no-config refusal: out=$out"; return 1; }
}

c_refuse_invalid() {
  local e="$1" r c v; r="$(fresh ri)"; seed_cfg "$r"; c="$(cfg "$r")"; cp "$c" "$T/ri.snap"
  for v in 'bad..name' '-x' '' 'a b' '@{-1}'; do
    run "$e" "$r" set "$v"
    [ "$rc" -eq 0 ] && has "$out" "set: REFUSED (invalid_branch_name)" || { echo "'$v': rc=$rc out=$out"; return 1; }
  done
  cmp -s "$c" "$T/ri.snap" && [ "$(nbackups "$c")" = "0" ] || { echo "something was written"; return 1; }
}

c_remove() {
  local e="$1" r c; r="$(fresh rv)"; seed_cfg "$r"; c="$(cfg "$r")"
  jq '.base_branch = "development"' "$c" > "$c.t" && mv "$c.t" "$c"
  cp "$c" "$T/rv.before"
  run "$e" "$r" remove
  [ "$rc" -eq 0 ] && has "$out" "remove: removed" || { echo "remove: rc=$rc out=$out"; return 1; }
  jq -e 'has("base_branch") | not' "$c" >/dev/null || { echo ".base_branch still present"; return 1; }
  [ "$(jq -S . "$c")" = "$(jq -S 'del(.base_branch)' "$T/rv.before")" ] || { echo "another key changed: $(cat "$c")"; return 1; }
  [ "$(nbackups "$c")" = "1" ] && cmp -s "$T/rv.before" "$(ls -1 "$c".backup.* | head -1)" || { echo "backup missing or differs"; return 1; }
  cp "$c" "$T/rv.after"
  run "$e" "$r" remove
  has "$out" "remove: no-op" && cmp -s "$c" "$T/rv.after" && [ "$(nbackups "$c")" = "1" ] || { echo "second remove: $out"; return 1; }
}

c_malformed() {
  local e="$1" r c body sub
  for body in '{"base_branch": "development", "a": 1' '{} {}' '[1, 2]'; do
    r="$(fresh mf)"; mkdir -p "$r/.supervisor"; c="$(cfg "$r")"; printf '%s\n' "$body" > "$c"; cp "$c" "$T/mf.snap"
    for sub in "set development" remove; do
      # shellcheck disable=SC2086
      run "$e" "$r" $sub
      [ "$rc" -eq 0 ] && has "$out" "ABORTED (config_unparseable)" || { echo "[$body] $sub: rc=$rc out=$out"; return 1; }
      cmp -s "$c" "$T/mf.snap" && [ "$(nbackups "$c")" = "0" ] || { echo "[$body] $sub wrote something"; return 1; }
    done
    run "$e" "$r" status
    has "$out" "base-branch: unresolved (base_branch_invalid:config)" && has "$out" "UNPARSEABLE" \
      || { echo "[$body] status: $out"; return 1; }
  done
}

c_symlink() {
  local e="$1" r c sub; r="$(fresh sl)"; mkdir -p "$r/.supervisor"; c="$(cfg "$r")"
  printf '{"k": 1}\n' > "$T/sl.target"; cp "$T/sl.target" "$T/sl.snap"; ln -s "$T/sl.target" "$c"
  for sub in "set development" remove; do
    # shellcheck disable=SC2086
    run "$e" "$r" $sub
    has "$out" "ABORTED (config_symlink)" || { echo "$sub: $out"; return 1; }
  done
  [ -L "$c" ] && cmp -s "$T/sl.target" "$T/sl.snap" || { echo "the link or its target changed"; return 1; }
}

c_unresolved() {
  local e="$1" r="$T/noorigin"
  rm -rf "$r"; git init -q "$r" && git -C "$r" commit -q --allow-empty -m init || return 1
  run "$e" "$r" status
  [ "$rc" -eq 0 ] && has "$out" "base-branch: unresolved (base_branch_unresolved)" || { echo "rc=$rc out=$out"; return 1; }
}

c_usage() {
  local e="$1" r; r="$(fresh us)"
  out="$(bash "$e" 2>&1)"; [ $? -eq 2 ] || { echo "no subcommand: not exit 2"; return 1; }
  out="$(bash "$e" frob --repo "$r" 2>&1)"; [ $? -eq 2 ] || { echo "unknown subcommand: not exit 2"; return 1; }
  out="$(bash "$e" set 2>&1)"; [ $? -eq 2 ] || { echo "set without branch: not exit 2"; return 1; }
  out="$(bash "$e" set --repo "$r" 2>&1)"; [ $? -eq 2 ] || { echo "set --repo without branch: not exit 2"; return 1; }
  [ ! -e "$(cfg "$r")" ] || { echo "a usage error wrote config.json"; return 1; }
}

CASES="c_status_default c_create c_merge c_idempotent c_refuse_missing c_refuse_invalid c_remove c_malformed c_symlink c_unresolved c_usage"

echo "== setup-base-branch.sh =="
for c in $CASES; do
  if msg="$($c "$ENGINE")"; then ok "$c"; else no "$c" "$msg"; fi
done

echo "== mutation controls (each must turn its case red) =="
# mutant <name> <awk program> <case> — scratch copy beside a copy of the resolver; gated.
mutant() {
  local name="$1" prog="$2" case_fn="$3" d="$T/mut-$1"
  mkdir -p "$d"; cp "$RESOLVER" "$d/resolve-base-branch.sh"
  awk "$prog" "$ENGINE" > "$d/setup-base-branch.sh"
  if [ ! -s "$d/setup-base-branch.sh" ] || cmp -s "$d/setup-base-branch.sh" "$ENGINE" || ! bash -n "$d/setup-base-branch.sh" 2>/dev/null; then
    no "MUTATION CONTROL $name: mutant is empty, identical or does not parse — control inconclusive"; return 0
  fi
  if "$case_fn" "$d/setup-base-branch.sh" >/dev/null 2>&1; then
    no "MUTATION CONTROL $name: $case_fn still PASSES against the mutant"
  else
    ok "MUTATION CONTROL $name: $case_fn is red against the mutant"
  fi
}
mutant remove-writes-empty '{ if (index($0, "proposed=\"$(jq '\''del(.base_branch)'\''")) sub(/del\(\.base_branch\)/, "{}"); print }' c_remove
mutant no-idempotent-exit '/if \[ "\$proposed" = "\$current" \]; then/ { skip = 4 } skip > 0 { skip--; next } { print }' c_idempotent
mutant no-origin-check '/refs\/remotes\/origin\/\$BRANCH\^\{commit\}/ { skip = 4 } skip > 0 { skip--; next } { print }' c_refuse_missing

echo
echo "test-setup-base-branch: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
