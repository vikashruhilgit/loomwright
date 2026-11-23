#!/usr/bin/env bash
# test-check-permission-files.sh — static suite for check-permission-files.sh and the publish guard's
# step (iv-a) (guard-finalize-publish.sh): never publish `.claude/settings.local.json`, nor a
# `.claude/settings.json` holding a secret-shaped value.
#
# Every case runs in a mktemp git repo with a local bare remote; no network, no gh. Fake tokens are
# ASSEMBLED AT RUNTIME (`"gh""p_"…`) so no token-shaped literal is committed to this repo (a push
# scanner would flag it, and the CI `tracked` check below runs over this very file).
#
# Covers: checker — a clean repo passes; an outgoing commit adding settings.local.json is refused
# (whatever it holds, nested too); a file added and then deleted in later outgoing commits is still
# refused (history ships); a pushed commit is not re-judged; a deletion passes; the index is judged;
# settings.json with a secret in an allow rule is refused, naming the SHAPE and never the value;
# settings.json without one passes; `${VAR}` references pass; `--pending` judges files on disk
# (force-add, not-ignored, ignored+plain); `tracked` mode; not a checkout -> 0; bad args -> 64.
# Guard — with NO live run (ungated) the incident push is denied, a clean push and a non-publish
# command are allowed; `add -f … && commit && push` in one command is denied; `commit -am && push`
# with the file ignored is allowed; `gh pr create` is judged; the checker missing denies
# guard_unavailable. MUTATION CONTROL: removing step (iv-a)'s deny flips the incident push to allowed.
# bash 3.2 / BSD userland safe.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -u

HERE="${BASH_SOURCE[0]%/*}"; [ "$HERE" = "${BASH_SOURCE[0]}" ] && HERE="."
HERE="$(cd "$HERE" && pwd)"
CHK="$HERE/check-permission-files.sh"
GUARD="$HERE/guard-finalize-publish.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-permission-files.XXXXXX")"
cleanup() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "${TMP:?}"; }
trap cleanup EXIT

GH_TOKEN_FAKE="gh""p_$(printf '%036d' 7)"
AWS_FAKE="AK""IA$(printf '%016d' 3)"
# hermetic git: no global/system config or global excludes file (a machine that ignores
# settings.local.json globally would otherwise turn the "not gitignored" cases into passes)
mkdir -p "$TMP/xdg"; export XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
: > "$TMP/gitconfig"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# new_repo -> echoes a fresh repo dir with one pushed commit and a bare remote. Called in `$( … )`,
# so it keeps no counter (a subshell's increment is lost): mktemp names each repo.
new_repo() {
  local r; r="$(mktemp -d "$TMP/r.XXXXXX")"
  git init -q -b main "$r" && git init -q --bare "$r.git"
  git -C "$r" remote add origin "$r.git"
  git -C "$r" commit -q --allow-empty -m init && git -C "$r" push -q origin main 2>/dev/null
  mkdir -p "$r/.claude"
  printf '%s' "$r"
}
local_settings() { printf '{"permissions":{"allow":["Bash(curl -H \\"Authorization: Bearer %s\\" https://api.example)"]}}\n' "$GH_TOKEN_FAKE" > "$1/.claude/settings.local.json"; }
chk() { OUT="$(bash "$CHK" "$@" 2>/dev/null)"; RC=$?; }

echo "== checker =="
R="$(new_repo)"
chk outgoing "$R"; [ "$RC" = 0 ] && ok "clean repo -> 0" || no "clean repo rc=$RC"

local_settings "$R"; git -C "$R" add -f .claude/settings.local.json; git -C "$R" commit -qm leak
chk outgoing "$R"
[ "$RC" = 1 ] && case "$OUT" in permission_file:*commit*settings.local.json*) true ;; *) false ;; esac \
  && ok "outgoing commit adds settings.local.json -> 1, names commit + path" || no "incident commit rc=$RC out=$OUT"
case "$OUT" in *"$GH_TOKEN_FAKE"*) no "refusal line leaks the secret" ;; *) ok "refusal line does not carry the secret" ;; esac

git -C "$R" rm -q --cached .claude/settings.local.json; git -C "$R" commit -qm unleak
chk outgoing "$R"; [ "$RC" = 1 ] && ok "added then removed in later outgoing commits -> still 1 (history ships)" || no "add+remove rc=$RC"

R="$(new_repo)"; local_settings "$R"; git -C "$R" add -f .claude/settings.local.json; git -C "$R" commit -qm old
git -C "$R" push -q origin main 2>/dev/null
chk outgoing "$R"; [ "$RC" = 0 ] && ok "already-pushed commit is not re-judged -> 0" || no "pushed rc=$RC"
git -C "$R" rm -q --cached .claude/settings.local.json; git -C "$R" commit -qm remove
chk outgoing "$R"; [ "$RC" = 0 ] && ok "deleting a tracked settings.local.json -> 0" || no "deletion rc=$RC"

R="$(new_repo)"; mkdir -p "$R/pkg/a/.claude"; printf '{}\n' > "$R/pkg/a/.claude/settings.local.json"
git -C "$R" add -f pkg; git -C "$R" commit -qm nested
chk outgoing "$R"; [ "$RC" = 1 ] && ok "nested settings.local.json with empty content -> 1" || no "nested rc=$RC"

R="$(new_repo)"; local_settings "$R"; git -C "$R" add -f .claude/settings.local.json
chk outgoing "$R"
[ "$RC" = 1 ] && case "$OUT" in *"staged change"*) true ;; *) false ;; esac && ok "staged settings.local.json -> 1" || no "staged rc=$RC out=$OUT"

R="$(new_repo)"
printf '{"permissions":{"allow":["Bash(export AWS_ACCESS_KEY_ID=%s)"]}}\n' "$AWS_FAKE" > "$R/.claude/settings.json"
git -C "$R" add .claude/settings.json; git -C "$R" commit -qm s
chk outgoing "$R"
[ "$RC" = 1 ] && case "$OUT" in permission_secret:*aws_access_key*) true ;; *) false ;; esac \
  && ok "settings.json with a secret in an allow rule -> 1, names the shape" || no "settings.json secret rc=$RC out=$OUT"
case "$OUT" in *"$AWS_FAKE"*) no "secret refusal leaks the value" ;; *) ok "secret refusal does not carry the value" ;; esac

for shape in "Bash(curl -H \\\"Authorization: Bearer $GH_TOKEN_FAKE\\\" x)|github_token" \
             "Bash(gh auth login --with-token $(printf 'token=%s' "abcdEFGH1234ijklMNOP"))|keyword_value" \
             "Bash(git clone https://bob:hunter2pass@example.com/r.git)|basic_auth_url"; do
  rule="${shape%|*}"; want="${shape##*|}"
  R="$(new_repo)"; printf '{"permissions":{"allow":["%s"]}}\n' "$rule" > "$R/.claude/settings.json"
  git -C "$R" add .claude/settings.json; git -C "$R" commit -qm s
  chk outgoing "$R"
  [ "$RC" = 1 ] && case "$OUT" in *"($want)"*) true ;; *) false ;; esac && ok "shape $want refused" || no "shape $want rc=$RC out=$OUT"
done

R="$(new_repo)"
printf '{"permissions":{"allow":["Bash(npm test)","Bash(curl -H \\"Authorization: Bearer ${API_TOKEN}\\" x)","Bash(export TOKEN=$GITHUB_TOKEN)"]},"apiKeyHelper":"~/bin/key.sh"}\n' > "$R/.claude/settings.json"
git -C "$R" add .claude/settings.json; git -C "$R" commit -qm s
chk outgoing "$R"; [ "$RC" = 0 ] && ok "settings.json with only variable references -> 0" || no "clean settings.json rc=$RC out=$OUT"

echo "== --pending =="
R="$(new_repo)"; local_settings "$R"
chk outgoing "$R" --pending force; [ "$RC" = 1 ] && ok "on disk + force-add -> 1" || no "pending force rc=$RC"
chk outgoing "$R" --pending plain; [ "$RC" = 1 ] && ok "on disk, not gitignored, plain -> 1" || no "pending not-ignored rc=$RC"
printf '.claude/settings.local.json\n' > "$R/.gitignore"; git -C "$R" add .gitignore; git -C "$R" commit -qm gi
chk outgoing "$R" --pending plain; [ "$RC" = 0 ] && ok "file now gitignored by an unpushed commit, plain -> 0" || no "pending newly-ignored rc=$RC out=$OUT"
git -C "$R" push -q origin main 2>/dev/null
chk outgoing "$R" --pending plain; [ "$RC" = 0 ] && ok "on disk, gitignored, plain -> 0" || no "pending ignored rc=$RC out=$OUT"
chk outgoing "$R"; [ "$RC" = 0 ] && ok "on disk, no --pending -> 0 (the commit is what is judged)" || no "no-pending rc=$RC"

echo "== tracked / args =="
R="$(new_repo)"; chk tracked "$R"; [ "$RC" = 0 ] && ok "tracked: clean -> 0" || no "tracked clean rc=$RC"
local_settings "$R"; git -C "$R" add -f .claude/settings.local.json; git -C "$R" commit -qm t; git -C "$R" push -q origin main 2>/dev/null
chk tracked "$R"; [ "$RC" = 1 ] && ok "tracked: a pushed settings.local.json -> 1" || no "tracked leak rc=$RC"
mkdir -p "$TMP/plain"; chk outgoing "$TMP/plain"; [ "$RC" = 0 ] && ok "not a checkout -> 0" || no "non-git rc=$RC"
chk bogus "$R"; [ "$RC" = 64 ] && ok "bad mode -> 64" || no "bad mode rc=$RC"
chk outgoing "$R" --pending maybe; [ "$RC" = 64 ] && ok "bad --pending -> 64" || no "bad pending rc=$RC"

echo "== guard step (iv-a), no live run =="
# run_g <repo> <command> [guard] -> RC (stderr in GERR)
run_g() {
  local p; p="$(jq -n --arg c "$2" --arg d "$1" '{session_id:"cc-1",cwd:$d,tool_name:"Bash",tool_input:{command:$c}}')"
  GERR="$(CLAUDE_PROJECT_DIR="$1" bash "${3:-$GUARD}" <<<"$p" 2>&1 >/dev/null)"; RC=$?
}
R="$(new_repo)"; printf '.claude/settings.local.json\n' > "$R/.gitignore"; git -C "$R" add .gitignore; git -C "$R" commit -qm gi
git -C "$R" push -q origin main 2>/dev/null; local_settings "$R"
run_g "$R" "git push"; [ "$RC" = 0 ] && ok "clean push, file ignored on disk -> allowed" || no "clean push rc=$RC $GERR"
run_g "$R" "ls -la"; [ "$RC" = 0 ] && ok "non-publish command -> allowed" || no "ls rc=$RC"
run_g "$R" "git commit -am x && git push"; [ "$RC" = 0 ] && ok "commit -am && push with the file ignored -> allowed" || no "commit-am rc=$RC $GERR"
run_g "$R" "git add -f .claude/settings.local.json && git commit -m x && git push"
[ "$RC" = 2 ] && ok "force-add + commit + push in one command -> denied" || no "one-liner rc=$RC"
git -C "$R" add -f .claude/settings.local.json; git -C "$R" commit -qm leak
run_g "$R" "git push origin HEAD"
[ "$RC" = 2 ] && case "$GERR" in *permission_file*) true ;; *) false ;; esac && ok "the incident push (no live run) -> denied permission_file" || no "incident rc=$RC $GERR"
run_g "$R" "gh pr create --fill"; [ "$RC" = 2 ] && ok "gh pr create with the commit unpushed -> denied" || no "pr create rc=$RC"
run_g "$R" "cd /tmp && git -C $R push"; [ "$RC" = 2 ] && ok "git -C <repo> push from elsewhere -> denied (the publish's own checkout)" || no "-C rc=$RC $GERR"

mkdir -p "$TMP/g"; cp "$GUARD" "$HERE/loom-log-owner.sh" "$HERE/host-mode.sh" "$TMP/g/" 2>/dev/null
run_g "$R" "git push" "$TMP/g/guard-finalize-publish.sh"
[ "$RC" = 2 ] && case "$GERR" in *"check-permission-files.sh missing"*) true ;; *) false ;; esac \
  && ok "checker missing -> denied guard_unavailable (fail closed)" || no "missing checker rc=$RC $GERR"

cp "$CHK" "$TMP/g/"
sed 's/^    1) deny "\${perm_out.*$/    1) ;;/' "$GUARD" > "$TMP/g/guard-finalize-publish.sh"
if cmp -s "$GUARD" "$TMP/g/guard-finalize-publish.sh"; then no "mutation control: sed changed nothing"
else
  run_g "$R" "git push origin HEAD" "$TMP/g/guard-finalize-publish.sh"
  [ "$RC" = 0 ] && ok "mutation control: without the (iv-a) deny the incident push is allowed" || no "mutation control rc=$RC"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" = 0 ]
