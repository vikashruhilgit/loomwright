#!/usr/bin/env bash
# write-run.sh — ADAPTER (loomwright/scripts/adapters/providers/). Runs the EDIT
# STEP of a routed write seat (`scripts/resolve-routing.sh write-seats` prints
# the seat ids; this header does not restate them) on a granted non-Claude
# provider CLI, in a caller's own checkout. The calling Claude task still runs
# every post-edit step itself (tests/lint, outputs_verified, the local commit,
# its result block): the provider never commits or pushes, and nothing it says
# decides anything here.
#
# USAGE
#   write-run.sh --provider <name>[:<model>] --seat <write-seat> \
#       --worktree <dir> --prompt <file> --out <json>
#   write-run.sh --restore <sha> --worktree <dir>
#
#   --provider  A provider-table entry (`provider-<name>.sh` beside this file),
#               optionally `:<model>`. NAME is allowlisted to [A-Za-z0-9_-]
#               before it is spliced into a sourced path.
#   --seat      A write seat id (checked against `resolve-routing.sh
#               write-seats`; anything else is a usage error).
#   --worktree  The TOP LEVEL of the checkout the provider edits (a linked
#               worktree, or the project root). The CLI runs with this cwd.
#   --prompt    File holding the edit instructions (folded verbatim, after a
#               fixed preamble, into the prompt sent to the provider).
#   --out       Where the one JSON result object is written.
#   There is no home-mode argument: the CLI is ONLY ever started through
#   `launch_provider_cli isolated` (launch-provider-cli.sh beside this file), so
#   the real HOME — and with it the harness's user settings file, whose
#   `permissions.defaultMode` would override the provider's pin — never reaches
#   the CLI. That launcher also refuses to copy anything under `.claude` in.
#
# ENV (optional)
#   LOOMWRIGHT_WRITE_CLI_TIMEOUT  Positive integer seconds bounding the CLI
#                                 (default 420). Empty / non-numeric / zero falls
#                                 back to 420; anything above 480 is clamped to
#                                 480, so the launch, its TERM->KILL chain and the
#                                 restore all end inside a 600-second caller-side
#                                 bound (a Bash tool call made with timeout
#                                 600000). A kill at that outer bound would leave
#                                 the provider's partial edits with no restore.
#
# OUTPUT (written to --out; exit 0 on EVERY outcome, 2 on a usage error only)
#   {
#     "write_status": <one of the closed list below>,
#     "provider": "<name>", "model": "<model>" | null,
#     "changed_files": [ "<path>", ... ],   # always an array: the paths the
#                       # provider changed (tracked edits + untracked
#                       # non-ignored files), measured BEFORE any restore; [] on
#                       # a pre-launch refusal
#     "tree_restored": true | false,        # present only on a post-launch
#                       # status: true when the tree is verified back at the
#                       # pre-launch commit and git state (the restore below ran
#                       # and was verified, or a launch-setup failure meant no CLI
#                       # ever started); false on `ok` (nothing restored, the
#                       # edits stay for the caller) and when a restore could not
#                       # be completed
#     "cost": "unknown",                    # provider usage is never metered here
#     "notes": "<short string>"             # present only when not `ok`
#   }
#
# write_status — a CLOSED enum owned by this header:
#   Pre-launch refusals (no CLI started, the tree is not touched), checked in
#   this order:
#     provider_unavailable        NAME fails the allowlist, no provider-<name>.sh,
#                                 or its CLI is not on PATH
#     write_claude_is_task_path   NAME is `claude`: a Claude edit is the calling
#                                 task's own path, never a launched CLI
#     provider_not_granted        the worktree repo's user-scope grant
#                                 (resolve-egress-config.sh PROVIDER_GRANTS) does
#                                 not name the provider
#     write_not_granted           PROVIDER_WRITE_GRANTS does not hold
#                                 `<seat>:<provider>`
#     write_unpinnable            the provider file defines no provider_write_argv
#     write_tree_dirty            the worktree had uncommitted or untracked
#                                 non-ignored changes (so a restore could not tell
#                                 the provider's files from the caller's)
#     write_repo_settings_present the worktree root holds a
#                                 `.claude/settings.local.json` (any content, even
#                                 gitignored: existence is the test), or a
#                                 `.claude/settings.json` with a `permissions` key
#                                 (or one that cannot be parsed): a repo-side file
#                                 that could widen the pin, which the eligibility
#                                 probe never tested
#   Post-launch:
#     ok                  the CLI ended inside the bound with exit 0 and the git
#                         fingerprint is unchanged. The edits stay.
#     write_timeout       the bound fired (process group killed)
#     write_failed        the CLI exited non-zero, could not be launched, or this
#                         script was interrupted mid-launch
#     write_git_tampered  the worktree's own HEAD or branch ref moved, or the
#                         remotes, local/common config, worktree config,
#                         info/exclude, or non-sample hooks (common dir and a
#                         core.hooksPath dir included) changed: the provider
#                         committed or rewired git. `notes` names every changed
#                         fingerprint section and path (config keys, never
#                         values). ALSO the status of any restore that could not
#                         be completed and verified (then tree_restored: false),
#                         never a softer one.
#   The provider's reply text is never read for the status.
#
# RESTORE — on every non-`ok` post-launch status: the tracked tree goes back to
# the pre-launch HEAD (`git reset --hard`) and untracked non-ignored files are
# removed (`git clean -ffd`). The tree was verified clean before launch, so
# everything removed is the provider's. On write_git_tampered the pre-launch
# BYTE snapshots of the common config, the worktree's config.worktree, the
# common info/exclude and the common hooks dir are put back first (hook files
# the provider added are removed), then HEAD and the worktree's own branch ref
# are reset to the pre-launch commit — so a planted hook or core.hooksPath never
# survives to run under the real HOME. Restore git commands run with
# core.fsmonitor and core.hooksPath overridden, so nothing the provider planted
# executes during the restore itself. Verified afterwards: HEAD is the
# pre-launch commit, the tree is clean, and the fingerprint matches the
# pre-launch one.
#
# --restore MODE — `write-run.sh --restore <sha> --worktree <dir>`: the same
# tree restore on its own, for a caller whose write-run returned `ok` but whose
# post-edit gate then failed. Starts no CLI. Refuses, changing nothing, when
# HEAD is not <sha>. Prints ONE line of JSON to stdout and exits 0:
#   {"restore_status": "ok" | "restore_head_moved" | "restore_failed",
#    "sha": "<sha>", "tree_restored": true | false, "notes": "..."?}
#
# CONSENT — the grant is read from the worktree's OWN repo through
# resolve-egress-config.sh (user scope, keyed by that repo's slug), exactly like
# lens-run.sh. There is no flag or environment bypass.
#
# HONEST LIMITS — the launcher is blast-radius reduction, not a sandbox: the CLI
# can still write outside the worktree and reach the network. Gitignored paths
# inside the worktree are neither checked by write_tree_dirty nor removed by the
# restore. The `own` fingerprint scope (git-integrity-lib.sh) does not see a NEW
# branch or tag. A SIGKILL of this script skips the restore (hence the clamp).
#
# PROVIDER FILE CONTRACT ADDITION (beyond lens-run.sh's header):
#   provider_write_argv()  — OPTIONAL. Reads MODEL / PROMPT_CONTENT /
#                            WORKSPACE_DIR, sets PROVIDER_ARGV, prompt LAST: the
#                            provider's pin mode plus explicit allow rules for
#                            file read/edit tools only. Absent => write_unpinnable.
#
# TEST-ONLY INTROSPECTION HATCH (never read by a decision): when
# LOOMWRIGHT_WRITE_DEBUG_TIMEOUT_FILE is set, the effective CLI timeout is written
# there so test-write-run.sh can pin the default and the clamp.
#
# Bash 3.2 compatible; no jq needed (the JSON is built here).

set +e   # FAIL-SAFE beyond usage errors — see the exit contract above.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITE_CLI_TIMEOUT_DEFAULT=420
WRITE_CLI_TIMEOUT_MAX=480

usage_error() {
  printf 'write-run.sh: %s\n' "$1" >&2
  printf 'usage: write-run.sh --provider <name>[:<model>] --seat <write-seat> --worktree <dir> --prompt <file> --out <json>\n' >&2
  printf '       write-run.sh --restore <sha> --worktree <dir>\n' >&2
  exit 2
}

# ---- parse args ---------------------------------------------------------------
PROVIDER_ARG=""; SEAT=""; WORKTREE=""; PROMPT_FILE=""; OUT_FILE=""; RESTORE_SHA=""; RESTORE_MODE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --provider|--seat|--worktree|--prompt|--out|--restore)
      [ $# -ge 2 ] || usage_error "$1 needs a value"
      case "$1" in
        --provider) PROVIDER_ARG="$2" ;;
        --seat) SEAT="$2" ;;
        --worktree) WORKTREE="$2" ;;
        --prompt) PROMPT_FILE="$2" ;;
        --out) OUT_FILE="$2" ;;
        --restore) RESTORE_SHA="$2"; RESTORE_MODE=1 ;;
      esac
      shift 2 ;;
    *) usage_error "unrecognized argument: $1" ;;
  esac
done

[ -n "$WORKTREE" ] || usage_error "--worktree is required"
[ -d "$WORKTREE" ] || usage_error "--worktree is not a directory: $WORKTREE"
WT="$(cd "$WORKTREE" 2>/dev/null && pwd -P)"
WT_TOP="$(git -C "$WT" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$WT_TOP" ] && WT_TOP="$(cd "$WT_TOP" 2>/dev/null && pwd -P)"
[ -n "$WT_TOP" ] && [ "$WT_TOP" = "$WT" ] || usage_error "--worktree must be the top level of a git work tree: $WORKTREE"

# wgit <args...> — git in the worktree with nothing the provider could have
# planted executing (no fsmonitor, no hooks).
wgit() {
  git -c core.fsmonitor=false -c core.hooksPath=/dev/null -C "$WT" "$@"
}

# json_str <s> — <s> as a JSON string literal (control characters other than
# tab / newline / CR are dropped).
json_str() {
  local s
  s="$(printf '%s' "$1" | env LC_ALL=C tr -d '\000-\010\013\014\016-\037')"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  printf '"%s"' "$s"
}

# tree_restore <sha> — reset the tracked tree to <sha> and remove untracked
# non-ignored files. 0 when HEAD is <sha> and the tree is clean afterwards.
tree_restore() {
  local sha="$1"
  wgit reset -q --hard "$sha" >/dev/null 2>&1 || return 1
  wgit clean -q -ffd >/dev/null 2>&1
  [ "$(wgit rev-parse HEAD 2>/dev/null)" = "$sha" ] || return 1
  [ -z "$(wgit status --porcelain --untracked-files=all 2>/dev/null)" ] || return 1
  return 0
}

# ---- --restore mode -------------------------------------------------------------
if [ "$RESTORE_MODE" = "1" ]; then
  [ -z "$PROVIDER_ARG$SEAT$PROMPT_FILE$OUT_FILE" ] || usage_error "--restore takes only --worktree"
  case "$RESTORE_SHA" in
    ""|*[!0-9a-fA-F]*) usage_error "--restore needs a hex commit sha" ;;
  esac
  FULL="$(wgit rev-parse --verify --quiet "${RESTORE_SHA}^{commit}" 2>/dev/null)"
  HEAD_NOW="$(wgit rev-parse --verify --quiet HEAD 2>/dev/null)"
  if [ -z "$FULL" ]; then
    printf '{"restore_status":"restore_failed","sha":%s,"tree_restored":false,"notes":"not a commit in this worktree; nothing changed"}\n' "$(json_str "$RESTORE_SHA")"
    exit 0
  fi
  if [ "$HEAD_NOW" != "$FULL" ]; then
    printf '{"restore_status":"restore_head_moved","sha":%s,"tree_restored":false,"notes":%s}\n' \
      "$(json_str "$FULL")" "$(json_str "HEAD is ${HEAD_NOW:-unborn}, not the given sha; nothing changed")"
    exit 0
  fi
  if tree_restore "$FULL"; then
    printf '{"restore_status":"ok","sha":%s,"tree_restored":true}\n' "$(json_str "$FULL")"
  else
    printf '{"restore_status":"restore_failed","sha":%s,"tree_restored":false,"notes":"reset/clean did not leave a clean tree at the sha"}\n' "$(json_str "$FULL")"
  fi
  exit 0
fi

# ---- write mode: the remaining required flags -----------------------------------
[ -n "$PROVIDER_ARG" ] || usage_error "--provider is required"
[ -n "$SEAT" ] || usage_error "--seat is required"
[ -n "$PROMPT_FILE" ] || usage_error "--prompt is required"
[ -n "$OUT_FILE" ] || usage_error "--out is required"
[ -r "$PROMPT_FILE" ] && [ -f "$PROMPT_FILE" ] || usage_error "--prompt file not readable: $PROMPT_FILE"

ROUTING_RESOLVER="$SCRIPT_DIR/../../resolve-routing.sh"
SEAT_OK=0
case "$SEAT" in
  ""|*[!A-Za-z0-9_-]*) ;;
  *)
    if [ -r "$ROUTING_RESOLVER" ]; then
      for s in $(bash "$ROUTING_RESOLVER" write-seats 2>/dev/null | awk '{print $1}'); do
        [ "$s" = "$SEAT" ] && SEAT_OK=1
      done
    fi ;;
esac
[ "$SEAT_OK" = "1" ] || usage_error "--seat '$SEAT' is not a write seat (resolve-routing.sh write-seats)"

PRE_SHA="$(wgit rev-parse --verify --quiet HEAD 2>/dev/null)"
[ -n "$PRE_SHA" ] || usage_error "--worktree has no commit to restore to"

case "$PROVIDER_ARG" in
  *:*) NAME="${PROVIDER_ARG%%:*}"; MODEL="${PROVIDER_ARG#*:}" ;;
  *)   NAME="$PROVIDER_ARG"; MODEL="" ;;
esac

LAUNCHED=0
RESULT_WRITTEN=0
SNAP=""; RAW_OUT=""; RAW_ERR=""; FP_BEFORE=""

# write_json <status> <changed_json_array> <tree_restored:true|false|""> [notes]
write_json() {
  local status="$1" changed="$2" restored="$3" notes="${4:-}" model_json
  if [ -n "$MODEL" ]; then model_json="$(json_str "$MODEL")"; else model_json="null"; fi
  {
    printf '{"write_status":%s,"provider":%s,"model":%s,"changed_files":%s' \
      "$(json_str "$status")" "$(json_str "$NAME")" "$model_json" "$changed"
    [ -n "$restored" ] && printf ',"tree_restored":%s' "$restored"
    printf ',"cost":"unknown"'
    [ "$status" != "ok" ] && printf ',"notes":%s' "$(json_str "${notes:-$status}")"
    printf '}\n'
  } 2>/dev/null > "$OUT_FILE"
  RESULT_WRITTEN=1
}

# refuse <status> <notes> — a pre-launch refusal: nothing started, nothing touched.
refuse() {
  write_json "$1" "[]" "" "$2"
  exit 0
}

# ---- pre-launch refusals (cheapest first; none starts a CLI or touches the tree)
case "$NAME" in
  ""|*[!a-zA-Z0-9_-]*) refuse "provider_unavailable" "invalid provider name" ;;
esac
[ "$NAME" = "claude" ] && refuse "write_claude_is_task_path" "provider claude: the calling Claude task makes the edit itself; no CLI is launched"
PROVIDER_FILE="$SCRIPT_DIR/provider-$NAME.sh"
[ -r "$PROVIDER_FILE" ] || refuse "provider_unavailable" "no provider-table entry named '$NAME'"
# shellcheck disable=SC1090
. "$PROVIDER_FILE"
[ -n "${PROVIDER_CLI_NAME:-}" ] && command -v "$PROVIDER_CLI_NAME" >/dev/null 2>&1 \
  || refuse "provider_unavailable" "the provider CLI is not on PATH"

# Consent: one resolver run in the worktree's own repo supplies both grants. A
# missing resolver or a value outside the allowlist reads as "no grant".
EGRESS_RESOLVER="$SCRIPT_DIR/../../resolve-egress-config.sh"
EGRESS_OUT=""
[ -r "$EGRESS_RESOLVER" ] && EGRESS_OUT="$( cd "$WT" && bash "$EGRESS_RESOLVER" 2>/dev/null )"
READ_GRANTS="$(printf '%s\n' "$EGRESS_OUT" | sed -n 's/^PROVIDER_GRANTS=//p' | head -n 1)"
WRITE_GRANTS="$(printf '%s\n' "$EGRESS_OUT" | sed -n 's/^PROVIDER_WRITE_GRANTS=//p' | head -n 1)"
case "$READ_GRANTS" in *[!A-Za-z0-9_,-]*) READ_GRANTS="" ;; esac
case "$WRITE_GRANTS" in *[!A-Za-z0-9_,:-]*) WRITE_GRANTS="" ;; esac
case ",$READ_GRANTS," in
  *",$NAME,"*) ;;
  *) refuse "provider_not_granted" "no user-scope grant for this provider in this repo; nothing was sent" ;;
esac
case ",$WRITE_GRANTS," in
  *",$SEAT:$NAME,"*) ;;
  *) refuse "write_not_granted" "no user-scope write grant for seat $SEAT on this provider in this repo; nothing was sent" ;;
esac

declare -F provider_write_argv >/dev/null 2>&1 \
  || refuse "write_unpinnable" "provider-$NAME.sh defines no provider_write_argv; it cannot run a write seat"

[ -z "$(wgit status --porcelain --untracked-files=all 2>/dev/null)" ] \
  || refuse "write_tree_dirty" "the worktree has uncommitted or untracked changes; commit or remove them first"

REPO_SETTINGS_DIR="$WT/.claude"
if [ -e "$REPO_SETTINGS_DIR/settings.local.json" ] || [ -L "$REPO_SETTINGS_DIR/settings.local.json" ]; then
  refuse "write_repo_settings_present" "the worktree root holds .claude/settings.local.json, which could widen the provider's pin"
fi
if [ -e "$REPO_SETTINGS_DIR/settings.json" ] || [ -L "$REPO_SETTINGS_DIR/settings.json" ]; then
  SETTINGS_OK=0
  if command -v jq >/dev/null 2>&1 \
     && jq -e 'type == "object" and (has("permissions") | not)' "$REPO_SETTINGS_DIR/settings.json" >/dev/null 2>&1; then
    SETTINGS_OK=1
  fi
  [ "$SETTINGS_OK" = "1" ] \
    || refuse "write_repo_settings_present" "the worktree root holds .claude/settings.json with a permissions key (or one that could not be read), which could widen the provider's pin"
fi

# ---- launch setup ----------------------------------------------------------------
WRITE_CLI_TIMEOUT="${LOOMWRIGHT_WRITE_CLI_TIMEOUT:-$WRITE_CLI_TIMEOUT_DEFAULT}"
case "$WRITE_CLI_TIMEOUT" in
  ''|*[!0-9]*) WRITE_CLI_TIMEOUT=$WRITE_CLI_TIMEOUT_DEFAULT ;;
esac
# Strip leading zeros so the value is never read as octal, and keep it short.
WRITE_CLI_TIMEOUT="$(printf '%s' "$WRITE_CLI_TIMEOUT" | sed 's/^0*//')"
[ -n "$WRITE_CLI_TIMEOUT" ] || WRITE_CLI_TIMEOUT=$WRITE_CLI_TIMEOUT_DEFAULT
if [ "${#WRITE_CLI_TIMEOUT}" -gt 6 ] || [ "$WRITE_CLI_TIMEOUT" -gt "$WRITE_CLI_TIMEOUT_MAX" ]; then
  WRITE_CLI_TIMEOUT=$WRITE_CLI_TIMEOUT_MAX
fi
if [ -n "${LOOMWRIGHT_WRITE_DEBUG_TIMEOUT_FILE:-}" ]; then
  printf '%s\n' "$WRITE_CLI_TIMEOUT" > "$LOOMWRIGHT_WRITE_DEBUG_TIMEOUT_FILE" 2>/dev/null
fi

LAUNCHER="$SCRIPT_DIR/launch-provider-cli.sh"
INTEGRITY_LIB="$SCRIPT_DIR/git-integrity-lib.sh"
if [ ! -r "$LAUNCHER" ] || [ ! -r "$INTEGRITY_LIB" ]; then
  write_json "write_failed" "[]" "true" "launch-provider-cli.sh or git-integrity-lib.sh is missing; no CLI was started"
  exit 0
fi
# shellcheck disable=SC1090
. "$LAUNCHER"
# shellcheck disable=SC1090
. "$INTEGRITY_LIB"

GITDIR="$(_gil_abs_dir "$WT" --absolute-git-dir)"
COMMONDIR="$(_gil_abs_dir "$WT" --git-common-dir)"
[ -n "$COMMONDIR" ] || COMMONDIR="$GITDIR"
PRE_REF="$(wgit symbolic-ref -q HEAD 2>/dev/null)"

cleanup() {
  if [ "$LAUNCHED" = "1" ] && [ "$RESULT_WRITTEN" = "0" ]; then
    # Interrupted mid-launch: stop the CLI, then the same evaluate-and-restore.
    launch_provider_cli_abort
    finish_post_launch "write_failed" "write-run.sh was interrupted while the CLI ran"
  fi
  launch_provider_cli_abort
  [ -n "$SNAP" ] && launch_provider_cli_rmtree "$SNAP"
  rm -f "$RAW_OUT" "$RAW_ERR" 2>/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

SNAP="$(mktemp -d "${TMPDIR:-/tmp}/loomwright-write-snap-XXXXXX" 2>/dev/null)"
RAW_OUT="$(mktemp "${TMPDIR:-/tmp}/loomwright-write-out-XXXXXX" 2>/dev/null)"
RAW_ERR="$(mktemp "${TMPDIR:-/tmp}/loomwright-write-err-XXXXXX" 2>/dev/null)"
if [ -z "$SNAP" ] || [ ! -d "$SNAP" ] || [ -z "$RAW_OUT" ] || [ -z "$RAW_ERR" ]; then
  write_json "write_failed" "[]" "true" "could not allocate temp files; no CLI was started"
  exit 0
fi

# Byte snapshot of the git files a restore puts back (absence recorded too).
# snap_file <src> <name>
snap_file() {
  if [ -f "$1" ] && [ ! -L "$1" ]; then
    cp -p "$1" "$SNAP/$2" 2>/dev/null || return 1
  else
    : > "$SNAP/$2.absent"
  fi
  return 0
}
SNAP_OK=1
snap_file "$COMMONDIR/config" config || SNAP_OK=0
snap_file "$GITDIR/config.worktree" config.worktree || SNAP_OK=0
snap_file "$COMMONDIR/info/exclude" exclude || SNAP_OK=0
if [ -d "$COMMONDIR/hooks" ] && [ ! -L "$COMMONDIR/hooks" ]; then
  cp -pRP "$COMMONDIR/hooks" "$SNAP/hooks" 2>/dev/null || SNAP_OK=0
else
  : > "$SNAP/hooks.absent"
fi
if [ "$SNAP_OK" != "1" ]; then
  write_json "write_failed" "[]" "true" "could not snapshot the git config and hooks; no CLI was started"
  exit 0
fi
FP_BEFORE="$SNAP/fingerprint"
git_integrity_fingerprint "$WT" own > "$FP_BEFORE" 2>/dev/null

# changed_files_json — the provider's changes as a JSON array of paths: tracked
# changes against the pre-launch commit plus untracked non-ignored files.
changed_files_json() {
  local first=1 p
  printf '['
  {
    wgit diff --name-only -z "$PRE_SHA" -- 2>/dev/null
    wgit ls-files -z --others --exclude-standard 2>/dev/null
  } | tr '\0' '\n' | env LC_ALL=C sort -u | while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ "$first" = "1" ]; then first=0; else printf ','; fi
    json_str "$p"
  done
  printf ']'
}

# tamper_notes <before> <after> — every changed fingerprint section, with the
# identifying field of each changed line (a refs line's ref name, every other
# line's first field: a path, a remote or a config KEY, never a value).
tamper_notes() {
  diff "$1" "$2" 2>/dev/null >/dev/null && return 0
  awk '
    FNR == 1 { file++ }
    /^[a-z-]+:$/ { sec = substr($0, 1, length($0) - 1); next }
    {
      key = sec SUBSEP $0
      if (file == 1) before[key] = 1; else after[key] = 1
      order[++n] = key
    }
    END {
      for (i = 1; i <= n; i++) {
        k = order[i]
        if ((k in before) && (k in after)) continue
        if (k in seen) continue
        seen[k] = 1
        split(k, parts, SUBSEP); s = parts[1]; line = parts[2]
        nf = split(line, f, " ")
        id = f[1]
        if (s == "refs" && nf >= 2) id = f[2]
        if (s == "head") id = "HEAD"
        if (s == "local-config") { sub(/=.*/, "", id) }
        if (!(s in secs)) { secs[s] = 1; slist[++m] = s }
        tag = s SUBSEP id
        if (!(tag in ids)) { ids[tag] = 1; list[s] = (list[s] == "" ? id : list[s] " " id) }
      }
      out = ""
      for (j = 1; j <= m; j++) out = out (out == "" ? "" : "; ") slist[j] " [" list[slist[j]] "]"
      print out
    }
  ' "$1" "$2"
}

# restore_git_state — put the snapshotted git files back, then HEAD and the own
# branch ref. 0 when every step succeeded.
restore_git_state() {
  local rc=0 name dst
  for name in config config.worktree exclude; do
    case "$name" in
      config) dst="$COMMONDIR/config" ;;
      config.worktree) dst="$GITDIR/config.worktree" ;;
      exclude) dst="$COMMONDIR/info/exclude" ;;
    esac
    if [ -e "$SNAP/$name.absent" ]; then
      if [ -e "$dst" ] || [ -L "$dst" ]; then rm -f "$dst" 2>/dev/null || rc=1; fi
    else
      rm -f "$dst" 2>/dev/null
      mkdir -p "${dst%/*}" 2>/dev/null
      cp -p "$SNAP/$name" "$dst" 2>/dev/null || rc=1
    fi
  done
  launch_provider_cli_rmtree "$COMMONDIR/hooks"
  if [ -e "$COMMONDIR/hooks" ] || [ -L "$COMMONDIR/hooks" ]; then rc=1; fi
  if [ ! -e "$SNAP/hooks.absent" ]; then
    cp -pRP "$SNAP/hooks" "$COMMONDIR/hooks" 2>/dev/null || rc=1
  fi
  if [ -n "$PRE_REF" ]; then
    wgit update-ref "$PRE_REF" "$PRE_SHA" >/dev/null 2>&1 || rc=1
    wgit symbolic-ref HEAD "$PRE_REF" >/dev/null 2>&1 || rc=1
  else
    wgit update-ref --no-deref HEAD "$PRE_SHA" >/dev/null 2>&1 || rc=1
  fi
  return $rc
}

# finish_post_launch <status> <notes> — evaluate the run, restore when not ok,
# write the result. Never exits (the EXIT trap calls it too).
finish_post_launch() {
  local status="$1" notes="$2" fp_after changes restored="false" tnotes
  fp_after="$SNAP/fingerprint.after"
  git_integrity_fingerprint "$WT" own > "$fp_after" 2>/dev/null
  if ! cmp -s "$FP_BEFORE" "$fp_after"; then
    tnotes="$(tamper_notes "$FP_BEFORE" "$fp_after")"
    status="write_git_tampered"
    notes="git state changed during the launch: ${tnotes:-unnamed change}"
    # Config and hooks go back BEFORE any command that reads the index or tree.
    restore_git_state || notes="$notes; git state restore incomplete"
  fi
  changes="$(changed_files_json)"
  if [ "$status" = "ok" ]; then
    write_json "ok" "$changes" "false"
    return 0
  fi
  if tree_restore "$PRE_SHA"; then
    git_integrity_fingerprint "$WT" own > "$fp_after" 2>/dev/null
    if cmp -s "$FP_BEFORE" "$fp_after"; then
      restored="true"
    else
      notes="$notes; git state still differs from the pre-launch snapshot after the restore: $(tamper_notes "$FP_BEFORE" "$fp_after")"
    fi
  else
    notes="$notes; the tree could not be reset to $PRE_SHA and cleaned"
  fi
  if [ "$restored" != "true" ]; then
    # A restore that could not be completed is never a softer status.
    status="write_git_tampered"
  fi
  if [ "$status" = "write_git_tampered" ]; then
    notes="$notes; restored: $restored"
  fi
  write_json "$status" "$changes" "$restored" "$notes"
  return 0
}

# ---- compose the prompt and launch (isolated HOME only) -----------------------
PROMPT_CONTENT="$(
  printf 'You are editing files in the current directory (a git checkout) for the write seat %s.\n' "$SEAT"
  printf 'Edit only what the task below asks. Do not run git, do not commit, push, or change git configuration or hooks: the caller tests, reviews and commits your edits.\n\n'
  cat "$PROMPT_FILE"
)"
WORKSPACE_DIR="$WT"
provider_write_argv

LAUNCHED=1
if ! launch_provider_cli isolated "$WRITE_CLI_TIMEOUT" "$WT" "$RAW_OUT" "$RAW_ERR" \
     "$PROVIDER_CLI_NAME" "${PROVIDER_ARGV[@]}"; then
  finish_post_launch "write_failed" "could not launch the provider CLI: $LPC_ERROR"
  exit 0
fi

if [ "$LPC_TIMED_OUT" = "1" ]; then
  finish_post_launch "write_timeout" "the provider CLI hit the ${WRITE_CLI_TIMEOUT}s bound; its process group was killed"
elif [ "$LPC_RC" != "0" ]; then
  finish_post_launch "write_failed" "the provider CLI exited $LPC_RC"
else
  finish_post_launch "ok" ""
fi
exit 0
