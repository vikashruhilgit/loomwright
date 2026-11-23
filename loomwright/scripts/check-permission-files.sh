#!/usr/bin/env bash
# check-permission-files.sh — refuse to publish Claude Code permission files, or a secret saved in one.
#
# WHY: Claude Code saves every "don't ask again" answer as an allow rule in the project's
# `.claude/settings.local.json`, verbatim — a rule for `curl -H "Authorization: Bearer <token>" …`
# carries the token. That file is per-user and never meant to be committed, but nothing stopped a
# commit + push of it: a worker's `git add -f .claude/settings.local.json` (or a plain `git add -A`
# in a repo that does not ignore the file) went out through every Loomwright guard, and CI had no
# check. Public scanners missed most of these secrets because they sit inside a command string
# (Apiiro / GitGuardian, 2026-11-22). This script is the one check, called by the publish guard
# (guard-finalize-publish.sh, before every `git push` / `gh pr create`) and by CI.
#
# USAGE
#   check-permission-files.sh outgoing <dir>   what a publish from <dir> could send: every commit of
#                                               HEAD not on a remote-tracking ref (`HEAD --not
#                                               --remotes`) — each commit, not the net diff, since a
#                                               file added then removed still ships in history — and
#                                               every STAGED add/change, since a `git commit` earlier
#                                               in the same command line makes it a commit first.
#   check-permission-files.sh outgoing <dir> --pending plain|force
#                                               as above, for a command that ALSO commits before it
#                                               pushes (`git add -f … && git commit … && git push`).
#                                               The hook runs before that commit exists, so the files
#                                               on disk at the checkout's top level are judged too:
#                                               `.claude/settings.local.json` on disk is refused when
#                                               it is tracked, not gitignored, or the command
#                                               force-adds (`force`); a settings.json on disk is
#                                               refused when it holds a secret shape.
#   check-permission-files.sh tracked <dir>     the files tracked at HEAD.
#   check-permission-files.sh --check           `tracked .` — the CI gate (ci.yml static job).
#
# WHAT IS REFUSED
#   - any added or changed `.claude/settings.local.json`, at any depth — refused whatever it holds;
#   - a `.claude/settings.json` (the shared, committable file) whose text matches a secret shape
#     below. The rest of a settings.json is allowed.
#   A deletion of either file is allowed (it removes the problem).
#
# EXIT: 0 clean (also: <dir> is not a git checkout or has no HEAD — nothing to publish) ·
#       1 refused, ONE line on stdout naming the commit, the path and the secret SHAPE, never the
#         secret itself (the line becomes a hook reason in a transcript) ·
#       3 cannot tell (git failed listing commits or reading a file) — a caller that gates fails CLOSED ·
#       64 bad arguments.
#
# HONEST LIMITS: this is a permission-file check, not a general secret scanner — a token pasted into
# source code, `.mcp.json` or an env file is not looked at. The secret shapes are known token
# formats plus a `key=value` keyword rule; a secret in no listed shape passes in a settings.json (a
# settings.local.json is refused regardless). `outgoing` judges HEAD only: a push whose refspec names
# another local branch is not looked at. `--pending` looks only at the top-level `.claude/` dir, not
# a nested package's. bash 3.2 / BSD userland safe; no jq.
set -u

MODE="${1:-}"; DIR="${2:-}"; PENDING=""
usage() { printf 'usage: check-permission-files.sh outgoing|tracked <dir> [--pending plain|force] | --check\n' >&2; exit 64; }
# `--check` = `tracked .`: the CI form (scripts/ci-local.sh mirrors `bash loomwright/scripts/<x>.sh
# --check` lines from ci.yml as gates).
if [ "$MODE" = --check ] && [ $# = 1 ]; then MODE=tracked; DIR="."; set -- tracked .; fi
case "$MODE" in outgoing|tracked) ;; *) usage ;; esac
if [ "${3:-}" = --pending ] && [ "$MODE" = outgoing ]; then
  case "${4:-}" in plain|force) PENDING="$4" ;; *) usage ;; esac
  [ $# -le 4 ] || usage
elif [ $# -gt 2 ]; then usage; fi
[ -n "$DIR" ] && [ -d "$DIR" ] || exit 0
git -C "$DIR" rev-parse --verify -q HEAD >/dev/null 2>&1 || exit 0

# Secret shapes: name<TAB>flags<TAB>ERE. flags `i` = case-insensitive. Shapes, never sample values.
SHAPES='github_token		gh[pousr]_[A-Za-z0-9]{30,}
github_pat		github_pat_[A-Za-z0-9_]{30,}
gitlab_token		glpat-[A-Za-z0-9_-]{20,}
api_key_sk		sk-[A-Za-z0-9_-]{24,}
stripe_live_key		[rs]k_live_[A-Za-z0-9]{20,}
aws_access_key		(AKIA|ASIA)[0-9A-Z]{16}
slack_token		xox[abprs]-[A-Za-z0-9-]{10,}
google_api_key		AIza[0-9A-Za-z_-]{35}
npm_token		npm_[A-Za-z0-9]{36}
private_key		-----BEGIN [A-Z ]*PRIVATE KEY
bearer_token	i	bearer[[:space:]]+[A-Za-z0-9._~+/=-]{20,}
basic_auth_url		://[^/[:space:]:@"]+:[^/[:space:]@"$]{6,}@
keyword_value	i	(api[_-]?key|access[_-]?key|secret|token|passwd|password)[^A-Za-z0-9$]{0,4}[=:][^A-Za-z0-9$]{0,3}[A-Za-z0-9._~+/=-]{16,}'

TAB='	'
# secret_shape <text> -> echoes the first matching shape's name; exit 0 on a match
secret_shape() {
  local text="$1" line name flags re
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name="${line%%"$TAB"*}"; line="${line#*"$TAB"}"
    flags="${line%%"$TAB"*}"; re="${line#*"$TAB"}"
    if [ "$flags" = i ]; then
      grep -Eiq -- "$re" <<<"$text" && { printf '%s' "$name"; return 0; }
    else
      grep -Eq -- "$re" <<<"$text" && { printf '%s' "$name"; return 0; }
    fi
  done <<SHAPES_END
$SHAPES
SHAPES_END
  return 1
}

# judge <rev> <path> <label> — exit 1 (with the refusal line) when <path> at <rev> must not be
# published; 3 when its content cannot be read. <rev> "" is the index (`git show :<path>`).
judge() {
  local rev="$1" p="$2" label="$3" body shape
  case "$p" in
    .claude/settings.local.json|*/.claude/settings.local.json)
      printf 'permission_file: %s adds %s — the per-user Claude Code permission file (its allow rules can hold secrets); never publish it\n' "$label" "$p"
      return 1 ;;
    .claude/settings.json|*/.claude/settings.json)
      body="$(git -C "$DIR" show "$rev:$p" 2>/dev/null)" || return 3
      if shape="$(secret_shape "$body")"; then
        printf 'permission_secret: %s — %s holds a value shaped like a secret (%s); remove it from the file and from every unpushed commit\n' "$label" "$p" "$shape"
        return 1
      fi ;;
  esac
  return 0
}

# judge_list <rev or %c> <label prefix> — reads paths on stdin; `\001<sha>` lines set the commit.
SOH=$'\001'
judge_list() {
  local rev="$1" label="$2" p c=""
  while IFS= read -r p; do
    case "$p" in
      "") continue ;;
      "$SOH"*) c="${p#"$SOH"}"; continue ;;
    esac
    if [ "$rev" = "%c" ]; then judge "$c" "$p" "commit ${c:0:12}" || return $?
    else judge "$rev" "$p" "$label" || return $?; fi
  done
  return 0
}

if [ "$MODE" = tracked ]; then
  files="$(git -C "$DIR" ls-tree -r --name-only HEAD 2>/dev/null)" || exit 3
  printf '%s\n' "$files" | judge_list HEAD "HEAD"
  exit $?
fi

# (1) outgoing commits: one `git log` lists each (\001<sha>) and the paths it added or changed.
# Merges are diffed against their first parent, so a file a merge brings in is seen too.
log="$(git -C "$DIR" log --format="${SOH}%H" --name-only --no-renames --diff-filter=d \
        --diff-merges=first-parent HEAD --not --remotes 2>/dev/null)" || exit 3
printf '%s\n' "$log" | judge_list %c ""; rc=$?
[ "$rc" = 0 ] || exit "$rc"

# (2) the index: what a `git commit` in the same command line would turn into an outgoing commit
staged="$(git -C "$DIR" diff --cached --name-only --no-renames --diff-filter=d 2>/dev/null)" || exit 3
printf '%s\n' "$staged" | judge_list "" "the staged change"; rc=$?
[ "$rc" = 0 ] || exit "$rc"
[ -n "$PENDING" ] || exit 0

# (3) --pending: the command commits before it pushes, so judge the files on disk at the top level.
top="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)" || exit 3
f="$top/.claude/settings.local.json"
if [ -f "$f" ] || [ -L "$f" ]; then
  why=""
  if [ "$PENDING" = force ]; then why="it force-adds"
  elif git -C "$top" ls-files --error-unmatch -- .claude/settings.local.json >/dev/null 2>&1; then why="the file is tracked"
  elif ! git -C "$top" check-ignore -q -- .claude/settings.local.json 2>/dev/null; then why="the file is not gitignored"
  fi
  if [ -n "$why" ]; then
    printf 'permission_file: this command commits and then publishes, %s, and .claude/settings.local.json is on disk — the per-user Claude Code permission file could go out in the new commit; keep it out of git, then commit in one command and push in another so the guard sees the commit\n' "$why"
    exit 1
  fi
fi
f="$top/.claude/settings.json"
if [ -f "$f" ] && shape="$(secret_shape "$(cat "$f" 2>/dev/null)")"; then
  printf 'permission_secret: this command commits and then publishes, and .claude/settings.json on disk holds a value shaped like a secret (%s); remove it before committing\n' "$shape"
  exit 1
fi
exit 0
