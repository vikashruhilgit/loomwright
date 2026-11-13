#!/usr/bin/env bash
# setup-base-branch.sh — deterministic engine for the `/setup base-branch` module: view, set and
# remove the project's configured base (integration) branch, the `.base_branch` key of
# `<repo>/.supervisor/config.json` that `resolve-base-branch.sh` reads at its `config` step.
#
# WHAT IT WRITES — and the whole list is one file:
#   <repo>/.supervisor/config.json, key `.base_branch` ONLY (+ one timestamped backup sibling
#   `config.json.backup.<ts>` before rewriting a pre-existing file). Every other key at every
#   level is preserved — the write is a jq merge (`set`) or a jq `del` (`remove`), never a rewrite
#   from scratch. No user-scope write, no .gitignore write, no git ref write, no git history.
#
# THE RESOLUTION IS NOT RESTATED HERE. `status` prints `resolve-base-branch.sh --explain`'s own
# answer, and `set` validates a name by asking the same resolver (`--flag <name>`), so this
# module cannot drift from what every run will actually use.
#
# SUBCOMMANDS
#   status          read-only for the config. Prints the config path, the raw `.base_branch`
#                   cell, and the headline `base-branch: <branch> (source: <step>)` from the
#                   resolver (or `base-branch: unresolved (<status token>)`). Note: the resolver's
#                   origin-head step may itself run `git remote set-head origin -a`.
#                   Then, for a github.com origin whose config has no valid `required_checks`, one
#                   read-only protection read (`drain-gh-read.sh required-checks`); when it yields
#                   no list, an `advisory:` line (what every drain will do) and a `fix:` line.
#                   `set`/`remove`'s `verify:` block never makes that read.
#   set <branch>   write `.base_branch = <branch>`. Refused when the name is not a valid branch
#                   name or `origin/<branch>` is not a remote-tracking ref of <repo>. Backup-first,
#                   parse-gated, atomic (tmp + mv), and idempotent by byte-comparison: when the
#                   document it would write equals the one on disk (in jq's normal form), it
#                   writes nothing and makes no backup.
#   remove          delete `.base_branch` and nothing else. Backup-first, parse-gated, atomic;
#                   a config with no `.base_branch` is a no-op.
#
# HEADLINE LINES (the command layer relays them verbatim; exactly one per set/remove run)
#   set: applied (created <config>)        set: applied   (+ `  backup: <path>`)
#   set: no-op — already configured …      set: REFUSED (invalid_branch_name) — …
#   set: REFUSED (no_such_remote_branch) — …
#   remove: removed  (+ `  backup: <path>`)   remove: no-op — …
#   <set|remove>: ABORTED (<reason>) — …   reasons: jq_unavailable | config_unparseable |
#                                           config_symlink | path_outside_repo |
#                                           containment_unavailable | no_backup_name |
#                                           backup_failed | write_failed
#   (config_symlink: `mv` would replace the link with a regular file, so a symlinked
#   config.json is refused rather than silently detached from its target. path_outside_repo: the
#   config's physical location is not under the repo — a committed `.supervisor -> /elsewhere`
#   would otherwise make the rewrite and its backup land outside it; checked by
#   contained-path-lib.sh, loaded from this script's directory — one that cannot load is
#   containment_unavailable.)
#
# FAIL-SAFE CONTRACT (mirrors setup-statusline.sh / setup-memory.sh): every REFUSED / ABORTED
# branch writes nothing, makes no backup, and exits 0 — "fails closed" means refuse-to-write plus a
# named-reason headline. A malformed config.json (unparseable, or not exactly one JSON object)
# ABORTS set and remove; it is never "repaired". Only a usage error (missing subcommand argument,
# unknown subcommand or flag) exits 2.
#
# USAGE
#   setup-base-branch.sh status [--repo <dir>]
#   setup-base-branch.sh set <branch> [--repo <dir>]
#   setup-base-branch.sh remove [--repo <dir>]
#     --repo <dir>   repository whose .supervisor/config.json is used (default: the git top-level
#                    of the current directory, else the current directory — the resolver's rule)
#
# Portability: bash 3.2 / BSD userland safe. jq is `command -v`-guarded and probed functionally.

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
RESOLVER="$script_dir/resolve-base-branch.sh"
ME="setup-base-branch"

usage_die() {
  printf '%s: usage error: %s\n' "$ME" "$1" >&2
  printf '%s: usage: setup-base-branch.sh status | set <branch> | remove [--repo <dir>]\n' "$ME" >&2
  exit 2
}

SUBCMD="${1:-}"
[ $# -gt 0 ] && shift
BRANCH=""
REPO=""
REPO_GIVEN=0

case "$SUBCMD" in
  status|remove) ;;
  set)
    [ $# -gt 0 ] || usage_die "set needs a branch name"
    case "$1" in --repo) usage_die "set needs a branch name before --repo" ;; esac
    BRANCH="$1"; shift ;;
  -h|--help) sed -n '2,/^$/{s/^# \{0,1\}//;p;}' "$0"; exit 0 ;;
  '') usage_die "missing subcommand" ;;
  *) usage_die "unknown subcommand: $SUBCMD" ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || usage_die "--repo needs a value"; REPO="$2"; REPO_GIVEN=1; shift 2 ;;
    *) usage_die "unknown argument: $1" ;;
  esac
done

if [ "$REPO_GIVEN" -eq 1 ]; then
  { [ -n "$REPO" ] && [ -d "$REPO" ]; } || usage_die "--repo '$REPO' is not a directory"
  REPO="$(cd "$REPO" && pwd)"
else
  REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || REPO=""
  [ -n "$REPO" ] || REPO="$(pwd)"
fi
CFG="$REPO/.supervisor/config.json"

# jq PRESENCE is not jq FUNCTION — probe it, and treat broken exactly like absent.
jq_works() {
  command -v jq >/dev/null 2>&1 || return 1
  printf '{}' | jq -e . >/dev/null 2>&1
}

# config_is_object — the WHOLE file parses as exactly one JSON object (slurped, so trailing junk
# or a second document is refused — the resolver's own parse rule for this file).
config_is_object() {
  jq -se 'length == 1 and (.[0] | type) == "object"' "$CFG" >/dev/null 2>&1
}

# config_cell — the raw `.base_branch` value as a status cell.
config_cell() {
  if [ ! -f "$CFG" ]; then printf 'absent (no config.json)'; return 0; fi
  if ! jq_works; then printf 'not probed (jq unavailable or non-functional)'; return 0; fi
  if ! config_is_object; then printf 'UNPARSEABLE (not exactly one JSON object) — set/remove would ABORT'; return 0; fi
  jq -r 'if has("base_branch") | not then "absent"
         elif (.base_branch | type) == "string" then .base_branch
         else "NOT A STRING (" + (.base_branch | tojson) + ")" end' "$CFG" 2>/dev/null
}

# backup_path — a `<config>.backup.<ts>` sibling that does not exist yet; pid- then
# counter-suffixed on a same-second collision; EMPTY (status 1) when every name is taken, so a
# caller aborts rather than overwrite an earlier backup.
backup_path() {
  local base cand i
  base="$CFG.backup.$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)"
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

# write_backed_up <verb> <document> — backup, stage, atomic replace. Prints the backup line, or
# the ABORTED headline (returning 1) when any step fails before the replace.
write_backed_up() {
  local verb="$1" doc="$2" backup tmp
  backup="$(backup_path)" || {
    echo "$verb: ABORTED (no_backup_name) — every candidate backup name for $CFG is taken; nothing was written."
    return 1
  }
  cp -p "$CFG" "$backup" 2>/dev/null || {
    echo "$verb: ABORTED (backup_failed) — could not back up $CFG; refusing to rewrite it unbacked-up. Nothing was written."
    return 1
  }
  tmp="$CFG.tmp.$$"
  if ! printf '%s\n' "$doc" > "$tmp" 2>/dev/null || ! mv "$tmp" "$CFG" 2>/dev/null; then
    rm -f "$tmp" "$backup" 2>/dev/null
    echo "$verb: ABORTED (write_failed) — could not replace $CFG; it is unchanged."
    return 1
  fi
  BACKUP_WRITTEN="$backup"
  return 0
}

# refuse_symlink <label> — return 1 (headline already printed) when $CFG must not be written: a
# symlinked leaf (`config_symlink`) or a physical location outside $REPO (`path_outside_repo`, e.g.
# a committed `.supervisor -> /elsewhere`). The library loads lazily, from the executed script's
# directory, right before the check; one that cannot load refuses (fail CLOSED).
refuse_symlink() {
  # shellcheck source=contained-path-lib.sh
  . "$script_dir/contained-path-lib.sh" 2>/dev/null || {
    echo "$1: ABORTED (containment_unavailable) — contained-path-lib.sh could not be loaded, so $CFG cannot be checked. Nothing was written."
    return 1
  }
  cpl_check_write "$1" "$CFG" "$REPO" config_symlink
}

# origin_github_slug — `<owner>/<repo>` of a github.com `origin` remote (ssh or https form); empty
# for any other origin (a local path, another host), so the advisory below has nothing to read.
origin_github_slug() {
  local u
  u="$(git -C "$REPO" remote get-url origin 2>/dev/null)" || return 0
  case "$u" in
    git@github.com:*) u="${u#git@github.com:}" ;;
    ssh://git@github.com/*) u="${u#ssh://git@github.com/}" ;;
    https://github.com/*|http://github.com/*) u="${u#*://github.com/}" ;;
    https://*@github.com/*) u="${u#*@github.com/}" ;;
    *) return 0 ;;
  esac
  u="${u%/}"; u="${u%.git}"
  [[ "$u" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && printf '%s' "$u"
  return 0
}

# required_checks_key — the config's `required_checks` key: `valid` (a set the drain accepts —
# required-checks-named.sh's named_required_valid, the drain's own rule: a non-empty array of check
# names, each with a non-space character and no control character), `absent`, `malformed`, or
# `unknown` (jq unavailable, the config unparseable, or the shared library missing: nothing
# reliable to say).
required_checks_key() {
  if [ ! -f "$CFG" ]; then printf 'absent'; return 0; fi
  if ! jq_works || ! config_is_object; then printf 'unknown'; return 0; fi
  # shellcheck source=required-checks-named.sh
  . "$script_dir/required-checks-named.sh" 2>/dev/null || { printf 'unknown'; return 0; }
  if ! jq -e 'has("required_checks")' "$CFG" >/dev/null 2>&1; then printf 'absent'; return 0; fi
  if jq -c '.required_checks' "$CFG" 2>/dev/null | named_required_valid jq >/dev/null; then
    printf 'valid'
  else
    printf 'malformed'
  fi
}

# required_checks_advisory <base> — `status` only, advisory only (never changes the exit status).
# Reads the base's required-check list with the drain's own reader (`drain-gh-read.sh
# required-checks`) and, when that read yields no list and the config names no valid
# `required_checks`, says what every drain will do and how to fix it. Prints nothing when the key
# is set (no read is made), when the read succeeds (even with an empty list — readable protection
# always wins), when the failed read still says a protection exists (the drain's own predicate,
# required-checks-named.sh's required_read_no_list: a 404 "Required status checks not enabled", or
# classic readable with only the ruleset read failed — the drain ignores the key there, so adding
# it fixes nothing), when origin is not a github.com repo, or when no `gh` is found to read with.
required_checks_advisory() {
  local base="$1" key slug rd rc=0 err why
  key="$(required_checks_key)"
  case "$key" in valid|unknown) return 0 ;; esac
  slug="$(origin_github_slug)"
  [ -n "$slug" ] || return 0
  command -v "${LOOMWRIGHT_GH_BIN:-gh}" >/dev/null 2>&1 || return 0   # no gh: no read, nothing known
  rd="$(GH="${LOOMWRIGHT_GH_BIN:-gh}" bash "$script_dir/drain-gh-read.sh" required-checks "$slug" "$base" </dev/null 2>"$TMPERR")" || rc=$?
  [ "$rc" -ne 0 ] || return 0
  err="$(cat "$TMPERR" 2>/dev/null)"
  # the key matters only where the drain lets a named set stand in; a missing library says nothing
  . "$script_dir/required-checks-named.sh" 2>/dev/null || return 0
  required_read_no_list "$rd $err" || return 0
  # shellcheck source=protection-paid-plan.sh
  . "$script_dir/protection-paid-plan.sh" 2>/dev/null || protection_paid_plan_refusal() { return 1; }
  if protection_paid_plan_refusal "$rd $err"; then
    why="GitHub's paid-plan refusal (a private repo on GitHub Free cannot protect a branch)"
  else
    why="$(printf '%s\n' "$err" | head -n 1 | tr -d '\r' | cut -c1-160)"
    why="not readable${why:+ ($why)}"
  fi
  if [ "$key" = malformed ]; then
    echo "advisory: base branch has no readable required-check list and \`required_checks\` is malformed ($(jq -c '.required_checks' "$CFG" 2>/dev/null | cut -c1-80)) — a drain run without --required-checks ends ESCALATED required_checks_unavailable"
    echo "  protection read ($slug $base): $why"
    echo "  fix: make \"required_checks\" in $CFG a non-empty array of check names, e.g. [\"<check name>\"]"
    return 0
  fi
  echo "advisory: base branch has no readable required-check list and no \`required_checks\` set — every drain will gate READY on every non-neutral check (or escalate)"
  echo "  protection read ($slug $base): $why"
  echo "  fix: add \"required_checks\": [\"<check name>\", …] to $CFG — the drain then gates READY on exactly that set while protection supplies no list (or pass --required-checks name:<a>,<b> to one drain run)"
}

do_status() {
  local out rc tok
  echo "== base-branch =="
  echo "config: $CFG"
  echo "config .base_branch: $(config_cell)"
  out="$(bash "$RESOLVER" --repo "$REPO" --explain 2>"$TMPERR")"; rc=$?
  if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
    echo "base-branch: $out"
    [ "$SUBCMD" != status ] || required_checks_advisory "${out%% *}"
  else
    tok="$(head -1 "$TMPERR" 2>/dev/null)"
    echo "base-branch: unresolved (${tok:-resolver_failed})"
    sed -n '2p' "$TMPERR" 2>/dev/null | sed 's/^/  /'
  fi
}

do_set() {
  local proposed current
  # Name validation is the resolver's own (`--flag` step): a refused name is refused here too.
  # An empty name is refused first — the resolver reads an empty --flag as "not given".
  if [ -z "$BRANCH" ] || ! bash "$RESOLVER" --repo "$REPO" --flag "$BRANCH" >/dev/null 2>&1; then
    echo "set: REFUSED (invalid_branch_name) — '$BRANCH' is not a valid branch name; nothing was written."
    return 0
  fi
  if ! git -C "$REPO" rev-parse -q --verify "refs/remotes/origin/$BRANCH^{commit}" >/dev/null 2>&1; then
    echo "set: REFUSED (no_such_remote_branch) — origin/$BRANCH is not a remote-tracking branch of $REPO (run \`git fetch origin $BRANCH\` first if it exists on the remote); nothing was written."
    return 0
  fi
  if ! jq_works; then
    echo "set: ABORTED (jq_unavailable) — jq is unavailable or non-functional; nothing was written."
    return 0
  fi
  refuse_symlink set || return 0
  if [ ! -f "$CFG" ]; then
    mkdir -p "$(dirname "$CFG")" 2>/dev/null || {
      echo "set: ABORTED (write_failed) — could not create $(dirname "$CFG"); nothing was written."
      return 0
    }
    local tmp="$CFG.tmp.$$"
    if ! jq -n --arg b "$BRANCH" '{base_branch: $b}' > "$tmp" 2>/dev/null || ! mv "$tmp" "$CFG" 2>/dev/null; then
      rm -f "$tmp" 2>/dev/null
      echo "set: ABORTED (write_failed) — could not create $CFG; nothing was written."
      return 0
    fi
    echo "set: applied (created $CFG)"
    echo "verify:"; do_status
    return 0
  fi
  if ! config_is_object; then
    echo "set: ABORTED (config_unparseable) — $CFG is not exactly one JSON object. Nothing was written and no backup was made; fix it by hand first."
    return 0
  fi
  proposed="$(jq --arg b "$BRANCH" '.base_branch = $b' "$CFG" 2>/dev/null)"
  current="$(jq . "$CFG" 2>/dev/null)"
  if [ -z "$proposed" ]; then
    echo "set: ABORTED (write_failed) — could not compose the merged document; nothing was written."
    return 0
  fi
  # Byte-compare idempotency: the document set WOULD write vs the one on disk, same normal form.
  if [ "$proposed" = "$current" ]; then
    echo "set: no-op — already configured ($CFG already has .base_branch = \"$BRANCH\"); nothing was written."
    return 0
  fi
  BACKUP_WRITTEN=""
  write_backed_up set "$proposed" || return 0
  echo "set: applied"
  echo "  backup: $BACKUP_WRITTEN"
  echo "verify:"; do_status
}

do_remove() {
  local proposed
  if ! jq_works; then
    echo "remove: ABORTED (jq_unavailable) — jq is unavailable or non-functional; nothing was written."
    return 0
  fi
  refuse_symlink remove || return 0
  if [ ! -f "$CFG" ]; then
    echo "remove: no-op — $CFG does not exist; nothing was written."
    return 0
  fi
  if ! config_is_object; then
    echo "remove: ABORTED (config_unparseable) — $CFG is not exactly one JSON object. Nothing was written and no backup was made; fix it by hand first."
    return 0
  fi
  if ! jq -e 'has("base_branch")' "$CFG" >/dev/null 2>&1; then
    echo "remove: no-op — $CFG has no .base_branch; nothing was written."
    return 0
  fi
  proposed="$(jq 'del(.base_branch)' "$CFG" 2>/dev/null)"
  if [ -z "$proposed" ]; then
    echo "remove: ABORTED (write_failed) — could not compose the document; nothing was written."
    return 0
  fi
  BACKUP_WRITTEN=""
  write_backed_up remove "$proposed" || return 0
  echo "remove: removed (.base_branch deleted; every other key kept)"
  echo "  backup: $BACKUP_WRITTEN"
  echo "verify:"; do_status
}

TMPERR="$(mktemp "${TMPDIR:-/tmp}/setup-base-branch.XXXXXX" 2>/dev/null)" || TMPERR="/dev/null"
trap '[ "$TMPERR" != /dev/null ] && rm -f "$TMPERR"' EXIT

case "$SUBCMD" in
  status) do_status ;;
  set) do_set ;;
  remove) do_remove ;;
esac
exit 0
