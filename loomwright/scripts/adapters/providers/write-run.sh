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
#                       # provider changed (tracked edits + every untracked
#                       # file absent from the pre-launch untracked snapshot,
#                       # IGNORED OR NOT — a .gitignore it wrote hides nothing
#                       # here; a new file inside an already-ignored dir counts
#                       # too), measured BEFORE the tree restore
#                       # (and after the git dirs and config are verified back);
#                       # [] on a pre-launch refusal, and when the git dirs or
#                       # config could not be put back (then no index or tree
#                       # command runs at all)
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
#     write_protected_path
#                         the CLI ended `ok` with an unchanged fingerprint, but
#                         changed_files holds a path the test-integrity guard
#                         protects, or a `.gitignore` / `.gitattributes` at any
#                         depth (provider-authored ignore or attribute rules are
#                         never kept), or the guard could not be run on them, or
#                         the untracked files could not be listed (fail
#                         closed). The judge is guard-test-integrity.sh itself
#                         (its Write|Edit matcher, fed one synthetic Write
#                         payload per changed path: the ONE home of the
#                         protected list, never a copy here). Checked whether or
#                         not a session is armed (every write seat's caller arms
#                         one), and the guard's opt-out env is NOT honoured (a
#                         caller can set this script's env inline, never the
#                         hook's). `notes` names the paths. The tree is restored.
#     write_git_tampered  the worktree's own HEAD or branch ref moved, or the
#                         remotes, local/common config (included files too),
#                         worktree config, info/exclude, info/attributes, the
#                         checkout's `.git` gitfile or `commondir` file (or where
#                         git resolves the git dir / common dir), or non-sample
#                         hooks (common dir and a core.hooksPath dir included)
#                         changed: the provider committed or rewired git. `notes`
#                         names every changed fingerprint section and path
#                         (config keys, never values). ALSO the status of any
#                         restore that could not be completed and verified (then
#                         tree_restored: false), never a softer one.
#   The provider's reply text is never read for the status.
#
# UNTRACKED SNAPSHOT — just before launch, every untracked file is listed with
# `git ls-files --others` WITHOUT --exclude-standard (file granularity, no ignore
# rules consulted). The tree is clean then, so that list is the ignored content
# that already exists. After launch, an untracked path absent from it is the
# provider's whatever the ignore rules then say: it is in changed_files, put to
# the guard, and removed by the restore. A file another process creates in the
# checkout while the CLI runs counts the same way (the checkout is the
# provider's for the launch).
#
# RESTORE — on every non-`ok` post-launch status: first every new untracked
# FILE (absent from the untracked snapshot, ignored or not) is removed — so a
# planted .gitignore / .gitattributes is gone before git reads rules again —
# then the tracked tree goes back to the pre-launch HEAD (`git reset --hard`)
# and untracked non-ignored files are removed (`git clean -ffd`, no -x). Only
# paths absent from the snapshot are ever removed: content that existed before
# the launch, ignored or not, is never touched. A new nested repository (one
# `dir/` entry) is never removed (it may be another process's worktree): it is
# left, named in notes, and the restore reads incomplete. Verified afterwards
# too: no new untracked path remains. On write_git_tampered the git state goes
# back FIRST, in this order: (1) the checkout's own pointers — the `.git`
# gitfile and the git dir's `commondir` file — from their byte snapshots, then
# git must resolve the pre-launch git dir and common dir again; (2) the
# worktree's config.worktree; (3) the SHARED common-dir files (common config,
# info/exclude, info/attributes, the hooks dir; hook files the provider added are
# removed) from the shared baseline below; (4) HEAD and the worktree's own branch
# ref. Before ANY index or tree command (changed_files, reset, clean, status)
# the git dirs must resolve to the pre-launch paths and the config git loads
# (included files too) must equal the baseline's; otherwise none runs, the tree
# is left as it is, and the result is write_git_tampered with tree_restored
# false — so neither a redirected commondir nor a planted filter/process driver
# ever executes under the real HOME. Every restore and post-launch git command
# pins GIT_DIR / GIT_COMMON_DIR / GIT_WORK_TREE to the pre-launch paths and
# overrides core.fsmonitor and core.hooksPath. Verified afterwards: HEAD is the
# pre-launch commit, the tree is clean, and the git state matches.
#
# SHARED BASELINE — parallel siblings share the common dir, so a launch snapshot
# taken while another write-run was active may already hold that run's planted
# hook or config, and writing it back would re-plant what the sibling's restore
# removed. So each run registers in `<common dir>/loomwright-write-runs/` (a
# mkdir lock; dead pids are pruned). A run that finds no other live run takes
# the shared snapshot and publishes it as the baseline; a run that finds one
# uses the published baseline instead of its own snapshot. The shared files are
# only ever restored to (and verified against) that baseline, taken when no
# provider was running. The registry is removed by the last run out.
#
# --restore MODE — `write-run.sh --restore <sha> --worktree <dir>`: the tree
# restore's reset and clean on their own (no untracked snapshot exists here, so
# no new-file step — see HONEST LIMITS), for a caller whose write-run returned `ok` but whose
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
# can still write outside the worktree and reach the network. PRE-EXISTING
# gitignored content (e.g. `.supervisor/`) is not checked by write_tree_dirty,
# and an edit to or deletion of it during the launch is neither detected nor
# undone (only NEW untracked paths are, ignored or not). The untracked snapshot
# lists every ignored file, so a huge ignored tree (node_modules) costs two
# listings. --restore MODE has no snapshot: it removes untracked non-ignored
# files only, so a new ignored file an `ok` launch left (named in that launch's
# changed_files) stays. Ignore rules outside the checkout (the real HOME's
# global excludes file) are trusted by the final `git clean`. The `own` fingerprint scope (git-integrity-lib.sh) does not see a NEW
# branch or tag. A SIGKILL of this script skips the restore (hence the clamp)
# and leaves its registry entry, which the next run prunes as a dead pid. While
# a provider runs, anything it plants in shared git state is live for every
# sibling's own (unpinned) git commands until its restore returns. The snapshots
# and the baseline are files the provider could also write. A legitimate change
# to the shared files made while runs overlap (say, branch tracking config) is
# reverted by a tampered run's restore to the baseline.
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

# wgit <args...> — git in the worktree with no fsmonitor and no hooks executing.
# Filter / process drivers come from config, so a restore keeps them out by
# putting the config back (and checking it) before any index or tree command.
wgit() {
  git -c core.fsmonitor=false -c core.hooksPath=/dev/null -C "$WT" "$@"
}

# rgit <args...> — wgit with GIT_DIR / GIT_COMMON_DIR / GIT_WORK_TREE pinned to
# the pre-launch paths once they are known (PIN_GITDIR set at launch setup), so
# a rewritten `.git` gitfile or `commondir` file cannot point a restore or
# post-launch command at a git dir and config the provider wrote.
PIN_GITDIR=""; PIN_COMMONDIR=""
rgit() {
  if [ -n "$PIN_GITDIR" ]; then
    GIT_DIR="$PIN_GITDIR" GIT_COMMON_DIR="$PIN_COMMONDIR" GIT_WORK_TREE="$WT" wgit "$@"
  else
    wgit "$@"
  fi
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

# untracked_all <out> — every untracked file in the worktree, one path per line,
# sorted, IGNORE RULES NOT CONSULTED (`ls-files --others` without
# --exclude-standard: a .gitignore, info/exclude or core.excludesFile the
# provider wrote cannot hide a path from it). File granularity: a file inside an
# already-ignored dir is its own line. A nested repository is one `dir/` line.
untracked_all() {
  rgit ls-files -z --others > "$1.z" 2>/dev/null || return 1
  tr '\0' '\n' < "$1.z" | env LC_ALL=C sort -u > "$1" 2>/dev/null || return 1
  rm -f "$1.z" 2>/dev/null
  return 0
}

# new_untracked — untracked paths absent from the pre-launch snapshot
# ($SNAP/untracked.pre), ignored or not: the provider's new files.
new_untracked() {
  untracked_all "$SNAP/untracked.post" || return 1
  env LC_ALL=C comm -13 "$SNAP/untracked.pre" "$SNAP/untracked.post"
}

# remove_new_untracked — remove every new untracked FILE (header §"RESTORE").
# Only paths absent from the pre-launch snapshot are ever removed, so content
# that was there before the launch (ignored or not) is never touched. A new
# nested repository (`dir/`) is never removed: it may be another process's
# worktree; it is left, and the restore then reads incomplete.
remove_new_untracked() {
  local p
  new_untracked | while IFS= read -r p; do
    case "$p" in ""|*/) continue ;; esac
    case "/$p/" in */../*|*/./*) continue ;; esac
    rm -f -- "$WT/$p" 2>/dev/null
  done
}

# tree_restore <sha> [snapshot:1] — reset the tracked tree to <sha> and remove
# untracked non-ignored files. With the snapshot flag (write mode), every new
# untracked file — ignored or not — is removed FIRST (so a planted .gitignore or
# .gitattributes is gone before reset and clean read the rules), and none may
# remain afterwards. 0 when HEAD is <sha> and the tree is clean afterwards.
tree_restore() {
  local sha="$1" snap="${2:-0}"
  [ "$snap" = "1" ] && remove_new_untracked
  rgit reset -q --hard "$sha" >/dev/null 2>&1 || return 1
  rgit clean -q -ffd >/dev/null 2>&1
  [ "$(rgit rev-parse HEAD 2>/dev/null)" = "$sha" ] || return 1
  [ -z "$(rgit status --porcelain --untracked-files=all 2>/dev/null)" ] || return 1
  if [ "$snap" = "1" ]; then
    local left
    left="$(new_untracked)" || return 1
    [ -z "$left" ] || return 1
  fi
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
if [ -z "$GITDIR" ]; then
  write_json "write_failed" "[]" "true" "could not resolve the worktree's git dir; no CLI was started"
  exit 0
fi
PIN_GITDIR="$GITDIR"; PIN_COMMONDIR="$COMMONDIR"
PRE_REF="$(rgit symbolic-ref -q HEAD 2>/dev/null)"

# ---- the run registry and shared baseline (header §"SHARED BASELINE") ---------
REG_DIR="$COMMONDIR/loomwright-write-runs"
REG_ENTRY=""
SHARED_AT_LAUNCH=0

# reg_lock / reg_unlock — a mkdir lock on the registry. A lock older than ~5 s
# is a killed holder's and is broken once; 0 when held.
reg_lock() {
  local i=0
  mkdir -p "$REG_DIR" 2>/dev/null || return 1
  until mkdir "$REG_DIR/lock" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -eq 50 ] && rm -rf "$REG_DIR/lock" 2>/dev/null
    [ "$i" -ge 100 ] && return 1
    sleep 0.1
  done
  mkdir -p "$REG_DIR/active" 2>/dev/null || { rmdir "$REG_DIR/lock" 2>/dev/null; return 1; }
  return 0
}
reg_unlock() { rmdir "$REG_DIR/lock" 2>/dev/null; }

# reg_others_live — prune dead entries; 0 when another live run is registered.
reg_others_live() {
  local e pid live=1
  for e in "$REG_DIR/active"/*; do
    [ -e "$e" ] || continue
    pid="${e##*/}"
    case "$pid" in
      ""|*[!0-9]*) rm -f "$e" 2>/dev/null; continue ;;
    esac
    [ "$pid" = "$$" ] && continue
    if kill -0 "$pid" 2>/dev/null; then live=0; else rm -f "$e" 2>/dev/null; fi
  done
  return $live
}

# reg_leave — drop this run's entry; the last run out removes the registry.
reg_leave() {
  [ -n "$REG_ENTRY" ] || return 0
  rm -f "$REG_ENTRY" 2>/dev/null
  REG_ENTRY=""
  if reg_lock; then
    if ! reg_others_live; then
      rm -rf "$REG_DIR/baseline" 2>/dev/null
      rmdir "$REG_DIR/active" 2>/dev/null
    fi
    reg_unlock
    rmdir "$REG_DIR" 2>/dev/null
  fi
}

cleanup() {
  if [ "$LAUNCHED" = "1" ] && [ "$RESULT_WRITTEN" = "0" ]; then
    # Interrupted mid-launch: stop the CLI, then the same evaluate-and-restore.
    launch_provider_cli_abort
    finish_post_launch "write_failed" "write-run.sh was interrupted while the CLI ran"
  fi
  launch_provider_cli_abort
  reg_leave
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
# snap_file <src> <dir>/<name> — under $SNAP.
snap_file() {
  if [ -f "$1" ] && [ ! -L "$1" ]; then
    cp -p "$1" "$SNAP/$2" 2>/dev/null || return 1
  elif [ -e "$1" ] || [ -L "$1" ]; then
    return 1   # a link or a directory where a file belongs: cannot be put back
  else
    : > "$SNAP/$2.absent"
  fi
  return 0
}

# shared_dst <name> — where a shared-snapshot file lives in the common dir.
shared_dst() {
  case "$1" in
    config) printf '%s' "$COMMONDIR/config" ;;
    exclude) printf '%s' "$COMMONDIR/info/exclude" ;;
    attributes) printf '%s' "$COMMONDIR/info/attributes" ;;
  esac
}

# common_config_listing / worktree_config_listing — the config git loads from
# the repo, included files followed. Reading config executes nothing.
common_config_listing() {
  rgit config --local --includes --list 2>/dev/null | env LC_ALL=C sort
}
worktree_config_listing() {
  [ -f "$GITDIR/config.worktree" ] || return 0
  git config --file "$GITDIR/config.worktree" --includes --list 2>/dev/null | env LC_ALL=C sort
}

# take_shared_snapshot <dir> — the shared common-dir files into <dir>.
take_shared_snapshot() {
  local d="$1" n
  mkdir -p "$d" 2>/dev/null || return 1
  for n in config exclude attributes; do
    snap_file "$(shared_dst "$n")" "${d#"$SNAP"/}/$n" || return 1
  done
  if [ -d "$COMMONDIR/hooks" ] && [ ! -L "$COMMONDIR/hooks" ]; then
    cp -pRP "$COMMONDIR/hooks" "$d/hooks" 2>/dev/null || return 1
  elif [ -e "$COMMONDIR/hooks" ] || [ -L "$COMMONDIR/hooks" ]; then
    return 1
  else
    : > "$d/hooks.absent"
  fi
  common_config_listing > "$d/common-config.list" 2>/dev/null || return 1
  return 0
}

SNAP_OK=1; SNAP_WHY="could not snapshot the git config and hooks"
mkdir -p "$SNAP/own" 2>/dev/null || SNAP_OK=0
# The checkout's own pointers and worktree config.
if [ -d "$WT/.git" ] && [ ! -L "$WT/.git" ]; then
  : > "$SNAP/own/gitfile.dir"
elif [ -f "$WT/.git" ] && [ ! -L "$WT/.git" ]; then
  cp -p "$WT/.git" "$SNAP/own/gitfile" 2>/dev/null || SNAP_OK=0
else
  SNAP_OK=0; SNAP_WHY="the checkout's .git is neither a directory nor a regular file"
fi
snap_file "$GITDIR/commondir" own/commondir || SNAP_OK=0
snap_file "$GITDIR/config.worktree" own/config.worktree || SNAP_OK=0
# Register, then the shared snapshot: our own when no other run is live (and
# published as the baseline), else the published baseline.
if [ "$SNAP_OK" = "1" ]; then
  if reg_lock; then
    if reg_others_live; then SHARED_AT_LAUNCH=1; fi
    if : > "$REG_DIR/active/$$" 2>/dev/null; then
      REG_ENTRY="$REG_DIR/active/$$"
      if [ "$SHARED_AT_LAUNCH" = "0" ]; then
        rm -rf "$REG_DIR/baseline" "$REG_DIR/baseline.tmp" 2>/dev/null
        if take_shared_snapshot "$SNAP/shared" \
           && cp -pRP "$SNAP/shared" "$REG_DIR/baseline.tmp" 2>/dev/null \
           && mv "$REG_DIR/baseline.tmp" "$REG_DIR/baseline" 2>/dev/null; then
          :
        else
          SNAP_OK=0
        fi
      elif [ -d "$REG_DIR/baseline" ]; then
        cp -pRP "$REG_DIR/baseline" "$SNAP/shared" 2>/dev/null || SNAP_OK=0
      else
        SNAP_OK=0; SNAP_WHY="another write-run is active in this repository but published no shared baseline"
      fi
    else
      SNAP_OK=0; SNAP_WHY="could not register in the write-run registry"
    fi
    reg_unlock
  else
    SNAP_OK=0; SNAP_WHY="could not take the write-run registry lock"
  fi
fi
if [ "$SNAP_OK" != "1" ]; then
  write_json "write_failed" "[]" "true" "$SNAP_WHY; no CLI was started"
  exit 0
fi
FP_BEFORE="$SNAP/fingerprint"
git_integrity_fingerprint "$WT" own > "$FP_BEFORE" 2>/dev/null
worktree_config_listing > "$SNAP/own/worktree-config.list" 2>/dev/null
# The untracked set before launch (the tree is clean, so: the ignored files that
# already exist). Everything untracked after launch that is not in it is the
# provider's, whatever ignore rules say then.
if ! untracked_all "$SNAP/untracked.pre"; then
  write_json "write_failed" "[]" "true" "could not list the worktree's untracked files; no CLI was started"
  exit 0
fi

# changed_files_list — the provider's changes, one path per line: tracked
# changes against the pre-launch commit plus every untracked path absent from
# the pre-launch snapshot (ignored or not — header §"OUTPUT").
changed_files_list() {
  {
    rgit diff --name-only -z "$PRE_SHA" -- 2>/dev/null | tr '\0' '\n'
    new_untracked
  } | env LC_ALL=C sort -u
}

# changed_files_json — changed_files_list as a JSON array.
changed_files_json() {
  local first=1 p
  printf '['
  changed_files_list | while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ "$first" = "1" ]; then first=0; else printf ','; fi
    json_str "$p"
  done
  printf ']'
}

# protected_paths — stdin: changed paths (relative to the worktree); stdout: the
# ones guard-test-integrity.sh's Write|Edit matcher denies. Each path is put to
# the guard as one synthetic Write payload, under a throwaway project dir whose
# marker arms that payload's session; LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS and
# LOOMWRIGHT_HOST_MODE are removed from its env (the opt-out is not honoured;
# the marker dir is the throwaway one). rc 1 = the guard could not judge a path.
GUARD_SCRIPT="$SCRIPT_DIR/../../guard-test-integrity.sh"
protected_paths() {
  local proj sid p rc
  if [ ! -r "$GUARD_SCRIPT" ] || ! command -v jq >/dev/null 2>&1; then
    cat >/dev/null; return 1
  fi
  sid="write-run-$$"; proj="$SNAP/guard-proj"
  if ! mkdir -p "$proj/.supervisor/guard" 2>/dev/null \
     || ! printf '{}\n' > "$proj/.supervisor/guard/$sid.json" 2>/dev/null; then
    cat >/dev/null; return 1
  fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    printf '{"session_id":%s,"tool_name":"Write","tool_input":{"file_path":%s}}' \
        "$(json_str "$sid")" "$(json_str "$WT/$p")" \
      | ( cd "$WT" && env -u LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS -u LOOMWRIGHT_HOST_MODE \
            CLAUDE_PROJECT_DIR="$proj" bash "$GUARD_SCRIPT" ) >/dev/null 2>&1
    rc=$?
    case "$rc" in
      0) ;;
      2) printf '%s\n' "$p" ;;
      *) cat >/dev/null; return 1 ;;
    esac
  done
  return 0
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

RESTORE_NOTES=""
rnote() { RESTORE_NOTES="${RESTORE_NOTES:+$RESTORE_NOTES; }$1"; }

# put_back <snap-file> <dst> — <dst> back to the snapshot's bytes, or removed
# when the snapshot recorded it absent. A no-op when it already matches.
put_back() {
  local src="$1" dst="$2"
  if [ -e "$src.absent" ]; then
    if [ -e "$dst" ] || [ -L "$dst" ]; then rm -f "$dst" 2>/dev/null; fi
    [ ! -e "$dst" ] && [ ! -L "$dst" ]
    return
  fi
  if [ -f "$dst" ] && [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then return 0; fi
  rm -f "$dst" 2>/dev/null
  mkdir -p "${dst%/*}" 2>/dev/null
  cp -p "$src" "$dst" 2>/dev/null
}

# matches_snap <snap-file> <dst> — 0 when <dst> holds the snapshot's bytes (or
# is absent where the snapshot recorded absence).
matches_snap() {
  if [ -e "$1.absent" ]; then
    [ ! -e "$2" ] && [ ! -L "$2" ]
  else
    [ -f "$2" ] && [ ! -L "$2" ] && cmp -s "$1" "$2"
  fi
}

# hooks_listing <dir> — _gil_list_hooks with the dir prefix stripped, so two
# hooks dirs compare by relative path, mode bit and checksum.
hooks_listing() {
  _gil_list_hooks "$1" | awk -v p="$1/" 'index($0, p) == 1 { $0 = substr($0, length(p) + 1) } { print }'
}

# shared_matches — 0 when the shared common-dir files equal the shared
# snapshot (this run's own, or the published baseline).
shared_matches() {
  local s="$SNAP/shared" n
  for n in config exclude attributes; do
    matches_snap "$s/$n" "$(shared_dst "$n")" || return 1
  done
  if [ -e "$s/hooks.absent" ]; then
    [ ! -e "$COMMONDIR/hooks" ] && [ ! -L "$COMMONDIR/hooks" ] || return 1
  else
    [ "$(hooks_listing "$s/hooks")" = "$(hooks_listing "$COMMONDIR/hooks")" ] || return 1
  fi
  return 0
}

# git_dirs_back — 0 when git resolves this checkout to the pre-launch git dir
# and common dir again (read unpinned: what the owner's next git command sees).
git_dirs_back() {
  local gd cd
  gd="$(_gil_abs_dir "$WT" --absolute-git-dir)"
  cd="$(_gil_abs_dir "$WT" --git-common-dir)"
  [ -n "$cd" ] || cd="$gd"
  [ -n "$gd" ] && [ "$gd" = "$GITDIR" ] && [ "$cd" = "$COMMONDIR" ]
}

# config_back — 0 when the git dirs resolve as before launch AND the config git
# loads (common config and config.worktree, included files followed) equals the
# shared snapshot / own snapshot. The precondition for ANY index or tree
# command after a tamper: a filter, textconv or process driver can only come
# from config, so with this config no driver the provider wrote can run.
config_back() {
  git_dirs_back || { rnote "the checkout's git dir or common dir still resolves elsewhere"; return 1; }
  matches_snap "$SNAP/shared/config" "$COMMONDIR/config" \
    && [ "$(common_config_listing)" = "$(cat "$SNAP/shared/common-config.list" 2>/dev/null)" ] \
    || { rnote "the common config (or a file it includes) differs from the baseline"; return 1; }
  matches_snap "$SNAP/own/config.worktree" "$GITDIR/config.worktree" \
    && [ "$(worktree_config_listing)" = "$(cat "$SNAP/own/worktree-config.list" 2>/dev/null)" ] \
    || { rnote "config.worktree (or a file it includes) differs from the snapshot"; return 1; }
  return 0
}

# restore_git_state — the git state back, in the header's RESTORE order: the
# checkout's pointers, config.worktree, the shared files (from SNAP/shared:
# this run's own snapshot when no other run was live at launch, else the
# published baseline — never a snapshot that may hold a sibling's plant), then
# HEAD and the own branch ref. 0 = everything put back; 1 = something could not
# be (index and tree commands are still safe); 2 = the git dirs or config did
# not come back, so NO index or tree command may run.
restore_git_state() {
  local rc=0 n
  if [ -e "$SNAP/own/gitfile" ]; then
    if [ -d "$WT/.git" ] && [ ! -L "$WT/.git" ]; then launch_provider_cli_rmtree "$WT/.git"; fi
    put_back "$SNAP/own/gitfile" "$WT/.git" || { rc=1; rnote "the .git gitfile could not be put back"; }
  elif [ ! -d "$WT/.git" ] || [ -L "$WT/.git" ]; then
    rc=1; rnote "the checkout's .git directory was replaced"
  fi
  put_back "$SNAP/own/commondir" "$GITDIR/commondir" || { rc=1; rnote "the commondir file could not be put back"; }
  put_back "$SNAP/own/config.worktree" "$GITDIR/config.worktree" || { rc=1; rnote "config.worktree could not be put back"; }
  for n in config exclude attributes; do
    put_back "$SNAP/shared/$n" "$(shared_dst "$n")" || { rc=1; rnote "the common $n could not be put back"; }
  done
  launch_provider_cli_rmtree "$COMMONDIR/hooks"
  if [ -e "$COMMONDIR/hooks" ] || [ -L "$COMMONDIR/hooks" ]; then rc=1; rnote "the common hooks dir could not be removed"; fi
  if [ ! -e "$SNAP/shared/hooks.absent" ]; then
    cp -pRP "$SNAP/shared/hooks" "$COMMONDIR/hooks" 2>/dev/null || { rc=1; rnote "the common hooks dir could not be put back"; }
  fi
  if [ -n "$PRE_REF" ]; then
    rgit update-ref "$PRE_REF" "$PRE_SHA" >/dev/null 2>&1 || rc=1
    rgit symbolic-ref HEAD "$PRE_REF" >/dev/null 2>&1 || rc=1
  else
    rgit update-ref --no-deref HEAD "$PRE_SHA" >/dev/null 2>&1 || rc=1
  fi
  config_back || return 2
  return $rc
}

# fp_select <fingerprint> <sections...> — only the named sections.
fp_select() {
  local f="$1"; shift
  awk -v want=" $* " '
    /^[a-z-]+:$/ { sec = substr($0, 1, length($0) - 1); keep = index(want, " " sec " ") > 0 }
    keep { print }
  ' "$f"
}

# verify_git_state <fp_after> <git_restored:0|1> — 0 when the git state is back.
# After a restore from a published baseline (another run was live at launch) the
# shared files are checked against that baseline and only this checkout's own
# sections against the launch fingerprint, whose shared part may hold a
# sibling's plant; otherwise the whole fingerprint must match.
verify_git_state() {
  if [ "$2" = "1" ] && [ "$SHARED_AT_LAUNCH" = "1" ]; then
    local own="refs head worktree-config-cksum git-dirs hooks-path"
    [ "$(fp_select "$FP_BEFORE" $own)" = "$(fp_select "$1" $own)" ] && shared_matches
    return
  fi
  cmp -s "$FP_BEFORE" "$1"
}

# finish_post_launch <status> <notes> — evaluate the run, restore when not ok,
# write the result. Never exits (the EXIT trap calls it too).
finish_post_launch() {
  local status="$1" notes="$2" fp_after changes restored="false" tnotes grc=0 git_restored=0 prc
  fp_after="$SNAP/fingerprint.after"
  git_integrity_fingerprint "$WT" own > "$fp_after" 2>/dev/null
  if ! cmp -s "$FP_BEFORE" "$fp_after"; then
    tnotes="$(tamper_notes "$FP_BEFORE" "$fp_after")"
    status="write_git_tampered"
    notes="git state changed during the launch: ${tnotes:-unnamed change}"
    # The git state goes back BEFORE any command that reads the index or tree.
    RESTORE_NOTES=""
    restore_git_state; grc=$?; git_restored=1
    [ "$grc" != "0" ] && notes="$notes; git state restore incomplete${RESTORE_NOTES:+: $RESTORE_NOTES}"
    if [ "$grc" = "2" ]; then
      notes="$notes; no index or tree command was run (git would not load the pre-launch git dir and config), so changed_files was not measured and the tree was not reset; restored: false"
      write_json "write_git_tampered" "[]" "false" "$notes"
      return 0
    fi
  fi
  changes="$(changed_files_json)"
  if [ "$status" = "ok" ]; then
    changed_files_list | protected_paths > "$SNAP/protected" 2>/dev/null
    prc=$?
    # The untracked listing must have worked, or new files went unjudged.
    new_untracked >/dev/null 2>&1 || prc=1
    # A provider-authored ignore or attribute rules file, at any depth, is
    # never kept: it would hide files from the caller's own status and commit.
    changed_files_list | awk -F/ '$NF == ".gitignore" || $NF == ".gitattributes"' >> "$SNAP/protected" 2>/dev/null
    if [ "$prc" = "0" ] && [ ! -s "$SNAP/protected" ]; then
      write_json "ok" "$changes" "false"
      return 0
    fi
    status="write_protected_path"
    if [ "$prc" != "0" ]; then
      notes="the test-integrity guard could not judge the changed files (guard script or jq missing, a guard error, or the untracked files could not be listed), so they count as protected"
    else
      notes="the provider changed paths the test-integrity guard protects, or a .gitignore / .gitattributes file: $(env LC_ALL=C sort -u "$SNAP/protected" | tr '\n' ' ' | sed 's/ $//')"
    fi
  fi
  if tree_restore "$PRE_SHA" 1; then
    git_integrity_fingerprint "$WT" own > "$fp_after" 2>/dev/null
    if verify_git_state "$fp_after" "$git_restored"; then
      restored="true"
    else
      notes="$notes; git state still differs from the pre-launch snapshot after the restore: $(tamper_notes "$FP_BEFORE" "$fp_after")"
    fi
  else
    notes="$notes; the tree could not be reset to $PRE_SHA and cleaned"
    tnotes="$(new_untracked 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
    [ -n "$tnotes" ] && notes="$notes; new untracked paths left in place: $tnotes"
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
