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
#   c_outside         (a) `.supervisor -> <outside>` (absolute link) ⇒ set and remove ABORT
#                     (path_outside_repo); the outside folder is byte-identical (listing + cksum), holds
#                     no backup and no temp file, with an existing outside config.json and with none
#   c_inside_link     (b) `.supervisor -> ./real-supervisor` inside the repo ⇒ set and remove still write
#   c_ancestor_link   (c) a repo reached through a symlinked ancestor ⇒ set and remove still write
#   c_unresolved      no origin, no config ⇒ status `unresolved (base_branch_unresolved)`
#   c_usage           missing / unknown subcommand, set without a branch ⇒ exit 2
# The required-checks advisory (a github.com origin and a scripted `gh` stub on PATH per case):
#   c_adv_paid        paid-plan refusal, no `required_checks` ⇒ the advisory + fix lines, exit 0,
#                     the drain's own read made, nothing written
#   c_adv_unprotected classic 404 with no ruleset list ⇒ the advisory line
#   c_adv_key_set     `required_checks` set ⇒ no advisory and no protection read at all
#   c_adv_readable    a 200 read (a list, or an empty list) ⇒ no advisory
#   c_adv_malformed   `[]` / a string / `[1]` / `[""]` ⇒ the malformed-key line, not the no-key one
#   c_adv_quiet       a non-GitHub origin, no `gh` to read with, and set's / remove's verify:
#                     blocks ⇒ no line, no read
# Mutation controls (gated: non-empty + differs + bash -n, on a scratch copy beside a copy of the
# resolver, contained-path-lib.sh and the protection readers, which the engine loads from its own
# directory): remove writes
# `{}` (c_remove must fail), the already-configured early exit deleted (c_idempotent must fail), the
# origin/<branch> check deleted (c_refuse_missing must fail), the containment call neutralized
# (`cpl_check_write` → `true`; c_outside must fail), the advisory echo deleted (c_adv_paid must
# fail), the `required_checks`-present guard dropped (c_adv_key_set must fail).
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
[ -f "$HERE/contained-path-lib.sh" ] || setup_fail "contained-path-lib.sh not found beside the engine"
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

# dsnap <dir> — a stable fingerprint of a directory: every path plus a cksum of every file.
dsnap() { (cd "$1" && { find . | env LC_ALL=C sort; find . -type f -exec cksum {} + 2>/dev/null | env LC_ALL=C sort; }); }

# c_outside — (a) a committed `.supervisor -> <outside>` must not let set/remove write, back up or
# stage anything in <outside>.
c_outside() {
  local e="$1" r o sub before pass_i
  for pass_i in with-config no-config; do
    for sub in "set main" remove; do
      r="$(fresh ou)"; o="$T/outside-ou"; rm -rf "$o"; mkdir -p "$o"
      if [ "$pass_i" = with-config ]; then printf '{"keep":1,"base_branch":"development"}\n' > "$o/config.json"; fi
      ln -s "$o" "$r/.supervisor"
      before="$(dsnap "$o")"
      # shellcheck disable=SC2086
      run "$e" "$r" $sub
      [ "$rc" -eq 0 ] && has "$out" "${sub%% *}: ABORTED (path_outside_repo)" || { echo "[$pass_i] $sub: rc=$rc out=$out"; return 1; }
      [ "$(dsnap "$o")" = "$before" ] || { echo "[$pass_i] $sub changed the outside folder: $(ls -la "$o")"; return 1; }
      [ "$(nbackups "$o/config.json")" = "0" ] || { echo "[$pass_i] $sub left a backup outside"; return 1; }
      [ -L "$r/.supervisor" ] || { echo "[$pass_i] $sub replaced the link"; return 1; }
    done
  done
}

# c_inside_link — (b) a symlinked parent that points INSIDE the repo is not a false refusal.
c_inside_link() {
  local e="$1" r c; r="$(fresh il)"; mkdir -p "$r/real-supervisor"; ln -s ./real-supervisor "$r/.supervisor"
  c="$r/real-supervisor/config.json"; printf '{"keep":1}\n' > "$c"
  run "$e" "$r" set development
  [ "$rc" -eq 0 ] && has "$out" "set: applied" || { echo "set: rc=$rc out=$out"; return 1; }
  [ "$(jq -r .base_branch "$c")" = "development" ] && [ "$(jq -r .keep "$c")" = "1" ] || { echo "value not written: $(cat "$c")"; return 1; }
  [ "$(nbackups "$c")" = "1" ] || { echo "want 1 backup inside the repo, have $(nbackups "$c")"; return 1; }
  run "$e" "$r" remove
  has "$out" "remove: removed" && jq -e 'has("base_branch") | not' "$c" >/dev/null || { echo "remove: rc=$rc out=$out"; return 1; }
  # and a create through the inside link
  rm -f "$c".backup.* "$c"
  run "$e" "$r" set development
  has "$out" "set: applied (created" && [ "$(jq -r .base_branch "$c")" = "development" ] || { echo "create: out=$out"; return 1; }
}

# c_ancestor_link — (c) the repo path runs through a symlink ABOVE its root (macOS /tmp style).
c_ancestor_link() {
  local e="$1" r l c; r="$(fresh al)"; l="$T/al-link"
  rm -rf "$T/al-real" "$l"; mkdir -p "$T/al-real"; mv "$r" "$T/al-real/repo"; ln -s "$T/al-real" "$l"
  c="$l/repo/.supervisor/config.json"
  run "$e" "$l/repo" set development
  [ "$rc" -eq 0 ] && has "$out" "set: applied (created" && [ "$(jq -r .base_branch "$c")" = "development" ] || { echo "create: rc=$rc out=$out"; return 1; }
  printf '{"keep":1,"base_branch":"main"}\n' > "$c"
  run "$e" "$l/repo" set development
  has "$out" "set: applied" && [ "$(nbackups "$c")" = "1" ] && [ "$(jq -r .base_branch "$c")" = "development" ] || { echo "set: out=$out"; return 1; }
  run "$e" "$l/repo" remove
  has "$out" "remove: removed" && jq -e 'has("base_branch") | not' "$c" >/dev/null || { echo "remove: out=$out"; return 1; }
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

# ---- the required-checks advisory (status only) ----------------------------------------------
# Each case runs in its own `$(…)` subshell, so the PATH / env set by adv_env stays in that case.
# adv_env <mode> — a scripted `gh` first on PATH (overriding the failing one) that logs every call
# to $T/adv-<mode>.log and answers the protection reads, never the network:
#   paid      every api call: GitHub's paid-plan refusal (403, stdout + stderr as captured live)
#   notprot   classic 404 "Branch not protected"; rules read `[]` (no ruleset list)
#   protected classic 200 requiring `ci`        empty   classic 200 with an empty list
ADV_LINE='advisory: base branch has no readable required-check list and no `required_checks` set — every drain will gate READY on every non-neutral check (or escalate)'
adv_env() {
  local d="$T/adv-bin-$1"
  mkdir -p "$d"; ADV_LOG="$T/adv-$1.log"; : > "$ADV_LOG"
  cat > "$d/gh" <<GHEOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$ADV_LOG"
mode="$1"
case "\$*" in
  *"/rules/branches/"*)
    [ "\$mode" = paid ] || { echo '[]'; exit 0; } ;;
esac
case "\$mode" in
  paid)
    echo '{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","documentation_url":"https://docs.github.com/rest","status":"403"}'
    echo 'gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)' >&2; exit 1 ;;
  notprot)
    echo '{"message":"Branch not protected","status":"404"}'
    echo 'gh: Branch not protected (HTTP 404)' >&2; exit 1 ;;
  protected) echo '{"strict":true,"contexts":["ci"],"checks":[{"context":"ci","app_id":null}]}' ;;
  empty) echo '{"strict":false,"contexts":[],"checks":[]}' ;;
esac
exit 0
GHEOF
  chmod +x "$d/gh"
  unset LOOMWRIGHT_GH_BIN GH
  export PATH="$d:$PATH"
}
# gh_repo <name> — a fresh clone whose origin URL is a github.com one; origin/HEAD stays the
# clone's, so the resolver answers from origin-head without touching the remote.
gh_repo() { local r; r="$(fresh "$1")"; git -C "$r" remote set-url origin https://github.com/acme/widgets.git; printf '%s' "$r"; }
adv_count() { printf '%s\n' "$1" | grep -c '^advisory: ' | tr -d ' '; }

c_adv_paid() {
  local e="$1" r; adv_env paid; r="$(gh_repo ap)"
  run "$e" "$r" status
  [ "$rc" -eq 0 ] && has "$out" "base-branch: main (source: origin-head)" || { echo "rc=$rc out=$out"; return 1; }
  printf '%s\n' "$out" | grep -qxF "$ADV_LINE" || { echo "advisory line missing: $out"; return 1; }
  printf '%s\n' "$out" | grep -q '^  fix: add "required_checks": \[' || { echo "fix line missing: $out"; return 1; }
  has "$out" "paid-plan refusal" || { echo "cause not named: $out"; return 1; }
  grep -qF 'api --method GET repos/acme/widgets/branches/main/protection/required_status_checks' "$ADV_LOG" \
    || { echo "the drain's protection read was not made: $(cat "$ADV_LOG")"; return 1; }
  [ ! -e "$(cfg "$r")" ] || { echo "status wrote a config"; return 1; }
  # the same with a config carrying other keys but no required_checks
  seed_cfg "$r"; cp "$(cfg "$r")" "$T/ap.snap"
  run "$e" "$r" status
  [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qxF "$ADV_LINE" || { echo "with other keys: rc=$rc out=$out"; return 1; }
  cmp -s "$(cfg "$r")" "$T/ap.snap" && [ "$(nbackups "$(cfg "$r")")" = "0" ] || { echo "status changed the config"; return 1; }
}

c_adv_unprotected() {
  local e="$1" r; adv_env notprot; r="$(gh_repo an)"
  run "$e" "$r" status
  [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qxF "$ADV_LINE" || { echo "rc=$rc out=$out"; return 1; }
  has "$out" "not readable (gh: Branch not protected (HTTP 404))" || { echo "cause: $out"; return 1; }
}

c_adv_key_set() {
  local e="$1" r; adv_env paid; r="$(gh_repo ak)"
  mkdir -p "$r/.supervisor"; printf '{"required_checks": ["Unit Tests"]}\n' > "$(cfg "$r")"
  run "$e" "$r" status
  [ "$rc" -eq 0 ] && has "$out" "base-branch: main (source: origin-head)" || { echo "rc=$rc out=$out"; return 1; }
  [ "$(adv_count "$out")" = "0" ] && ! has "$out" "  fix: " || { echo "advisory printed with the key set: $out"; return 1; }
  [ ! -s "$ADV_LOG" ] || { echo "a read was made with the key set: $(cat "$ADV_LOG")"; return 1; }
}

c_adv_readable() {
  local e="$1" r m; for m in protected empty; do
    adv_env "$m"; r="$(gh_repo "ar-$m")"
    run "$e" "$r" status
    [ "$rc" -eq 0 ] && [ "$(adv_count "$out")" = "0" ] || { echo "[$m] rc=$rc out=$out"; return 1; }
    [ -s "$ADV_LOG" ] || { echo "[$m] no protection read was made"; return 1; }
  done
}

c_adv_malformed() {
  local e="$1" r v; for v in '[]' '"Unit Tests"' '[1]' '[""]'; do
    adv_env paid; r="$(gh_repo am)"
    mkdir -p "$r/.supervisor"; printf '{"required_checks": %s}\n' "$v" > "$(cfg "$r")"
    run "$e" "$r" status
    [ "$rc" -eq 0 ] && [ "$(adv_count "$out")" = "1" ] && has "$out" '`required_checks` is malformed' \
      && has "$out" "required_checks_unavailable" && ! printf '%s\n' "$out" | grep -qxF "$ADV_LINE" \
      || { echo "[$v] rc=$rc out=$out"; return 1; }
  done
}

c_adv_quiet() {
  local e="$1" r; adv_env paid
  # a non-GitHub origin (the local bare one): nothing to read, no line, no gh call
  r="$(fresh aq)"
  run "$e" "$r" status
  [ "$rc" -eq 0 ] && [ "$(adv_count "$out")" = "0" ] && [ ! -s "$ADV_LOG" ] || { echo "local origin: rc=$rc out=$out log=$(cat "$ADV_LOG")"; return 1; }
  # a GitHub origin but no gh to read with: nothing is known, so no line
  r="$(gh_repo aq1)"
  out="$(LOOMWRIGHT_GH_BIN="$T/no-such-gh" bash "$e" status --repo "$r" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && [ "$(adv_count "$out")" = "0" ] && has "$out" "base-branch: main (source: origin-head)" || { echo "no gh: rc=$rc out=$out"; return 1; }
  # set's and remove's verify: blocks never read protection
  r="$(gh_repo aq2)"
  run "$e" "$r" set development
  has "$out" "set: applied (created" && [ "$(adv_count "$out")" = "0" ] || { echo "set: $out"; return 1; }
  run "$e" "$r" remove
  has "$out" "remove: removed" && [ "$(adv_count "$out")" = "0" ] && [ ! -s "$ADV_LOG" ] || { echo "remove: $out log=$(cat "$ADV_LOG")"; return 1; }
}

CASES="c_status_default c_create c_merge c_idempotent c_refuse_missing c_refuse_invalid c_remove c_malformed c_symlink c_outside c_inside_link c_ancestor_link c_unresolved c_usage"
CASES="$CASES c_adv_paid c_adv_unprotected c_adv_key_set c_adv_readable c_adv_malformed c_adv_quiet"

echo "== setup-base-branch.sh =="
for c in $CASES; do
  if msg="$($c "$ENGINE")"; then ok "$c"; else no "$c" "$msg"; fi
done

echo "== mutation controls (each must turn its case red) =="
# mutant <name> <awk program> <case> — scratch copy beside a copy of the resolver; gated.
mutant() {
  local name="$1" prog="$2" case_fn="$3" d="$T/mut-$1"
  mkdir -p "$d"; cp "$RESOLVER" "$d/resolve-base-branch.sh"; cp "$HERE/contained-path-lib.sh" "$d/contained-path-lib.sh"
  cp "$HERE/drain-gh-read.sh" "$HERE/protection-paid-plan.sh" "$HERE/required-checks-rulesets.sh" "$d/"
  awk "$prog" "$ENGINE" > "$d/setup-base-branch.sh"
  if [ ! -s "$d/setup-base-branch.sh" ] || cmp -s "$d/setup-base-branch.sh" "$ENGINE" || ! bash -n "$d/setup-base-branch.sh" 2>/dev/null; then
    no "MUTATION CONTROL $name: mutant is empty, identical or does not parse — control inconclusive"; return 0
  fi
  if ( "$case_fn" "$d/setup-base-branch.sh" ) >/dev/null 2>&1; then
    no "MUTATION CONTROL $name: $case_fn still PASSES against the mutant"
  else
    ok "MUTATION CONTROL $name: $case_fn is red against the mutant"
  fi
}
mutant remove-writes-empty '{ if (index($0, "proposed=\"$(jq '\''del(.base_branch)'\''")) sub(/del\(\.base_branch\)/, "{}"); print }' c_remove
mutant no-idempotent-exit '/if \[ "\$proposed" = "\$current" \]; then/ { skip = 4 } skip > 0 { skip--; next } { print }' c_idempotent
mutant no-containment '{ if (index($0, "cpl_check_write \"$1\" \"$CFG\" \"$REPO\" config_symlink")) sub(/cpl_check_write/, "true"); print }' c_outside
mutant no-origin-check '/refs\/remotes\/origin\/\$BRANCH\^\{commit\}/ { skip = 4 } skip > 0 { skip--; next } { print }' c_refuse_missing
mutant no-advisory-line '{ if (index($0, "every drain will gate READY on every non-neutral check (or escalate)\"")) next; print }' c_adv_paid
mutant no-key-guard '{ if (index($0, "case \"$key\" in valid|unknown)")) sub(/valid[|]unknown/, "unknown"); print }' c_adv_key_set

echo
echo "test-setup-base-branch: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
