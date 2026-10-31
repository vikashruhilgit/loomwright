#!/usr/bin/env bash
# lens-run.sh — ADAPTER (loomwright/scripts/adapters/providers/). Turns any
# installed agent CLI ("provider") into a second-opinion review LENS that
# returns findings in the exact shape the multi-voter merge rule already
# consumes (docs/RESULT_SCHEMAS.md CODE_REVIEW_RESULT `issues[]` fields:
# severity/category/file/line/description/suggestion). Source requirement:
# .supervisor/requirements/orca-derived/07-provider-lens.md — read its
# "Probe result — 2026-09-18, DEFERRED" section before trusting any claim
# below about read-only safety; it is NOT "enforced", see SAFETY POSTURE.
#
# USAGE
#   lens-run.sh --provider <name>[:<model>] --role <role> \
#       --diff <diff-file> --prompt <prompt-file> --out <output-json-file> \
#       [--commit <sha>]
#
#   --provider   REQUIRED. One of the provider-table entries — every
#                `provider-<name>.sh` file in this script's own directory is
#                one (list them there; this header does not restate the set).
#                Adding a provider means adding one new `provider-<name>.sh`
#                file, never editing this one. Optionally
#                suffixed `:<model>` (e.g. `cursor:gpt-5`). NAME is allowlisted
#                to `[A-Za-z0-9_-]` before it is spliced into a sourced path.
#   --role       REQUIRED. A role registered in lens-roles.sh: `review` (the
#                generic review lens) or a seat id printed by
#                `scripts/resolve-routing.sh seats` (this header does not restate
#                that list). A role selects the OUTPUT CONTRACT folded into the
#                composed prompt and how the answer is read: an `issues` role
#                (`review`, and the seats whose marker column is `-`) returns the
#                normalized `issues[]`; a `text` role returns `result_text`, and
#                is `ok` only when that text contains the role's registered marker.
#                An unregistered role is `lens_unparseable` ("unknown role"),
#                no CLI started. See lens-roles.sh.
#   --diff       REQUIRED. Path to a file containing the diff text to review.
#   --prompt     REQUIRED. Path to a file containing the review instructions
#                (caller-authored; folded verbatim into the composed prompt).
#   --out        REQUIRED. Path to write the normalized JSON result to.
#   --commit     OPTIONAL. The commit the throwaway isolated sandbox checks out.
#                Defaults to `git rev-parse HEAD` in the invoking checkout —
#                this script is normally run from inside a checkout already at
#                the diff's target commit (Phase 4.5's self-heal loop, or the
#                `--until-mergeable` drain), so HEAD is the right default; a
#                caller reviewing a different commit overrides explicitly.
#
# ENV (optional)
#   LOOMWRIGHT_LENS_CLI_TIMEOUT  Positive integer seconds to bound the provider
#                                CLI (default 300). On expiry the CLI's process
#                                group is signaled TERM then KILL. Non-numeric
#                                / zero / empty values fall back to 300.
#
# OUTPUT SHAPE (written to --out; NOT the full CODE_REVIEW_RESULT envelope —
# only the `issues[]` field shape is shared, per the AC's own scoping):
#   {
#     "lens_status": "ok" | "provider_unavailable" | "provider_not_granted" | "lens_mutated_tree" | "lens_unparseable",
#     "provider": "<name>", "model": "<model>" | null,
#     "issues": [ {severity, category, file, line, description, suggestion}, ... ],
#                          # always [] for a `text` role
#     "result_text": "<the provider's final text>",   # a `text` role, status ok
#                          # only; byte-bounded (LENS_RESULT_TEXT_MAX in
#                          # lens-roles.sh) — over the bound is lens_unparseable,
#                          # never a truncated "ok"
#     "cost": "unknown",   # D11 cost-honesty: provider usage is not in
#                          # token_ledger and no CLI here reports usage in a
#                          # confirmed shape — "unknown", NEVER "0".
#     "notes": "<optional short string>"   # present only on non-"ok" statuses
#   }
#
# DEGRADATION (five outcomes, ALL exit 0, ALL treated identically by the
# calling multi-voter loop — "voter errored/timed out", the EXISTING fail-safe
# degradation skills/self-heal-advisory/SKILL.md already specifies):
#   provider_unavailable  — the provider's CLI is not on PATH, the --provider
#                            NAME fails the allowlist, or no provider-<name>.sh
#                            exists. Checked BEFORE any other work (cheapest
#                            gate first, mirrors orca-mirror.sh) — NO
#                            subprocess is attempted.
#   provider_not_granted  — the provider is not `claude` and the invoking repo's
#                            user-scope grant (resolve-egress-config.sh
#                            PROVIDER_GRANTS) does not name it. Checked after the
#                            provider-table lookup, the CLI availability check
#                            and the role lookup, BEFORE any sandbox work: no
#                            sandbox is created, no provider CLI is started, and
#                            nothing is sent. There is NO flag or environment
#                            bypass — one would be a consent bypass. An
#                            unreadable grant source reads as "no grant".
#   lens_mutated_tree      — after the CLI ran, the sandbox working tree was
#                            dirty (`git status --porcelain` non-empty) OR
#                            security-relevant `.git` state changed (remotes,
#                            local config, refs, HEAD, non-sample hooks).
#                            Result DISCARDED; sandbox removed either way.
#   lens_unparseable        — the CLI's raw output did not parse into the
#                            expected envelope, or `jq` itself is unavailable
#                            on this machine, or sandbox isolation could not
#                            be established (shallow fetch / origin-remove
#                            failed), or the CLI hit LOOMWRIGHT_LENS_CLI_TIMEOUT.
#                            Degrades rather than guessing. When the output
#                            did not parse AND it matches the provider's own
#                            PROBE_AUTH_NOT_LOGGED_IN_RE, `notes` BEGINS with
#                            the named status `not_logged_in_isolated` (the
#                            same token setup-providers.sh `check` prints):
#                            the CLI has no login under the isolated HOME,
#                            i.e. its login did not cross (see the provider
#                            file's PROVIDER_LOGIN_FILES / PROVIDER_LOGIN_ENV).
#                            A parsed answer is never re-read for that pattern.
#   ok                     — well-formed, normalized `issues[]`.
#
# SAFETY POSTURE — READ THIS BEFORE RELYING ON IT (honesty required by the
# source requirement; never call this "enforced" or "safe" elsewhere in this
# repo's docs/comments):
#   The throwaway-isolated-sandbox-plus-integrity-check below DETECTS mutation
#   of the sandbox working tree AND of security-relevant `.git` internals
#   (remotes, local config, refs/HEAD, non-sample hooks). `git status
#   --porcelain` alone is BLIND to `.git/` (hooks, remotes, refs) — that gap
#   was empirically reproduced: planting a hook / adding a remote left
#   porcelain empty. The widened fingerprint exists to fail-closed
#   (`lens_mutated_tree`) on that class of mutation.
#   It does NOT prevent, and does NOT claim to prevent:
#     - writes OUTSIDE the sandbox (the main checkout, ~/.claude, ...),
#     - network egress. In particular `git push <url> --all` accepts an
#       explicit destination and needs NO configured remote. `git remote
#       remove origin` only stops a bare `git push` / `git push origin`;
#       it is NOT "nowhere to go". A CLI (or a prompt-injected one) can
#       still push the cloned tip to an attacker URL. That is UNMITIGATED
#       here — there is no network-egress denial.
#     - PROMPT INJECTION via the reviewed diff and the caller prompt,
#       which are folded VERBATIM into the instruction stream sent to a
#       fully agentic CLI. A hostile reviewed change can try to jailbreak
#       the provider. Combined with UNVERIFIED/DEFERRED deny-by-default
#       tool-permission behavior on providers whose live headless mode
#       has not been probed, this is a distinct residual risk.
#   Mitigations actually in scope (detection + blast-radius reduction, not
#   a sandbox):
#     (a) a scrubbed, allow-list child environment and an isolated HOME, both
#         built by the shared launcher launch-provider-cli.sh (beside this
#         file; its header is the authority): `env -i` starts EMPTY, so no
#         ambient credential, including GH_TOKEN, survives; only PATH, HOME,
#         TMPDIR and the provider file's declared PROVIDER_LOGIN_ENV vars that
#         are set cross, and the isolated HOME holds only copies of its
#         declared PROVIDER_LOGIN_FILES,
#     (b) `--workspace <dir>` (or, for a provider with no such flag, running
#         with cwd = the sandbox — see each provider-<name>.sh file's own
#         PROVIDER_WORKSPACE_FLAG),
#     (c) an INDEPENDENT sandbox repo (never `git worktree add` — worktrees
#         share the parent `.git/config`, so `git remote remove origin`
#         inside one removes origin for the ENTIRE shared repo; incident:
#         an earlier version did this and deleted the parent origin —
#         recovered manually). Populated by a shallow `file://` fetch of
#         the reviewed tip only (`--depth 1 --no-tags`): git IGNORES
#         `--depth` on local-path / `--local` clones, so a `file://` URL
#         is load-bearing. Blast radius is that tip, not full history of
#         every local ref. Then `git remote remove origin` is FAIL-CLOSED
#         — if it fails, or any remote remains, the provider CLI is never
#         started (`lens_unparseable`).
#     (d) post-run integrity fingerprint (working tree + the `.git` state
#         listed above). Any delta is `lens_mutated_tree`.
#     (e) a wall-clock bound on the provider CLI; the process group is
#         signaled TERM then KILL on expiry so cleanup is not racing a
#         hung child.
#   The `cursor-agent -f`/deny-by-default probe named in the source
#   requirement's Mechanism section is DEFERRED (cursor-agent is installed on
#   this machine but NOT authenticated, and the owner declined an interactive
#   login during the automated run that produced this file — see that
#   requirement file's "Probe result — 2026-09-18, DEFERRED" section). Until
#   that probe runs, treat (a)-(e) as the ONLY confirmed levers — NOT a
#   backstop to a confirmed deny-by-default, and NOT "enforced" sandboxing.
#   See docs/ARCHITECTURE_CONTRACTS.md §"Portability" for the same framing.
#
# INJECTION SAFETY — every provider CLI invocation is built as a bash ARRAY
# (PROVIDER_ARGV, assembled by the provider's own provider_build_argv; see
# each provider-<name>.sh file), never a single interpolated command string,
# never `eval`. A hostile diff/prompt/model value can only ever become ONE
# argv element and can never break out into a second command. This is argv
# construction hygiene, NOT a prompt-injection defense (see SAFETY POSTURE).
# The --provider NAME is allowlisted before it is used to build a sourced
# path, so a slash / `..` / metacharacter cannot escape $SCRIPT_DIR.
#
# PROVIDER-TABLE FILE CONTRACT (every loomwright/scripts/adapters/providers/
# provider-<name>.sh file, sourced by this script, must define):
#   PROVIDER_CLI_NAME       string  — the binary `command -v` checks for.
#   PROVIDER_WORKSPACE_FLAG 0 | 1   — documentation-only (this script ALWAYS
#                                     runs the subprocess with cwd = the
#                                     sandbox regardless); 1 means the
#                                     provider's own file ALSO appends an
#                                     explicit workspace flag to PROVIDER_ARGV.
#   PROVIDER_HOME_SCRUB     0 | 1   — documentation-only: every entry declares
#                                     1, and no launch reads it — the launcher
#                                     ALWAYS runs this script's CLI under its
#                                     isolated HOME. A provider whose login
#                                     needs the real HOME declares that login
#                                     below instead.
#   PROVIDER_LOGIN_FILES    array   — OPTIONAL. Paths relative to $HOME that the
#                                     launcher COPIES (read-only, never a link)
#                                     into the isolated HOME. Unset or empty =
#                                     nothing crosses.
#   PROVIDER_LOGIN_ENV      array   — OPTIONAL. Env var names passed to the CLI
#                                     when set in the caller. Unset or empty =
#                                     none. Validation rules for both:
#                                     launch-provider-cli.sh's header.
#   provider_build_argv()  — reads globals MODEL / PROMPT_CONTENT /
#                            WORKSPACE_DIR; sets array PROVIDER_ARGV (the argv
#                            AFTER the binary name). PROMPT_CONTENT MUST be
#                            the LAST element (this script's own test stub
#                            locates test directives via the last positional
#                            argv element).
#   provider_extract_text() — `provider_extract_text <raw_stdout_file>`; sets
#                            PROVIDER_EXTRACTED to the candidate JSON text
#                            (before this script's own canonical-shape
#                            validation); returns 1 (PROVIDER_EXTRACTED empty)
#                            on a structurally missing/malformed envelope.
#
# Exit: ALWAYS 0, except a genuine CLI usage error (a required flag missing —
# there is then no --out target to honestly write a marker to).

set +e   # FAIL-SAFE beyond usage errors — see the exit-0 contract above.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ="${LOOMWRIGHT_JQ_BIN:-jq}"

usage_error() {
  printf 'lens-run.sh: %s\n' "$1" >&2
  printf 'usage: lens-run.sh --provider <name>[:<model>] --role <role> --diff <file> --prompt <file> --out <file> [--commit <sha>]\n' >&2
  exit 64
}

# ---- parse args ---------------------------------------------------------------
PROVIDER_ARG=""
ROLE=""
DIFF_FILE=""
PROMPT_FILE=""
OUT_FILE=""
COMMIT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --provider) PROVIDER_ARG="${2:-}"; shift 2 ;;
    --role) ROLE="${2:-}"; shift 2 ;;
    --diff) DIFF_FILE="${2:-}"; shift 2 ;;
    --prompt) PROMPT_FILE="${2:-}"; shift 2 ;;
    --out) OUT_FILE="${2:-}"; shift 2 ;;
    --commit) COMMIT="${2:-}"; shift 2 ;;
    *) usage_error "unrecognized argument: $1" ;;
  esac
done

[ -n "$PROVIDER_ARG" ] || usage_error "--provider is required"
[ -n "$ROLE" ] || usage_error "--role is required"
[ -n "$DIFF_FILE" ] || usage_error "--diff is required"
[ -n "$PROMPT_FILE" ] || usage_error "--prompt is required"
[ -n "$OUT_FILE" ] || usage_error "--out is required"

# Split --provider on the FIRST ':' into NAME and MODEL.
case "$PROVIDER_ARG" in
  *:*) NAME="${PROVIDER_ARG%%:*}"; MODEL="${PROVIDER_ARG#*:}" ;;
  *)   NAME="$PROVIDER_ARG"; MODEL="" ;;
esac

HAVE_JQ=0
command -v "$JQ" >/dev/null 2>&1 && HAVE_JQ=1

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# emit_result <lens_status> <issues_json_array> [notes] [result_text] — writes
# --out and exits 0. `issues_json` must already be a valid JSON array string when
# HAVE_JQ=1; the HAVE_JQ=0 fallback never receives a non-"[]" issues array
# (see the jq-unavailable short-circuit below), so no fallback parsing of it
# is needed. A non-empty `result_text` (a `text` role, status ok) is passed to jq
# on stdin via --rawfile, never as an argv string: it can be far larger than one
# argument is allowed to be.
emit_result() {
  local status="$1" issues_json="$2" notes="${3:-}" result_text="${4:-}"
  if [ "$HAVE_JQ" = "1" ] && [ -n "$result_text" ]; then
    printf '%s' "$result_text" | "$JQ" -n \
      --arg status "$status" \
      --arg provider "$NAME" \
      --arg model "$MODEL" \
      --argjson issues "$issues_json" \
      --arg notes "$notes" \
      --rawfile result_text /dev/stdin \
      '{lens_status: $status, provider: $provider,
        model: (if $model == "" then null else $model end),
        issues: $issues, result_text: $result_text, cost: "unknown"} +
       (if $notes == "" then {} else {notes: $notes} end)' \
      >"$OUT_FILE" 2>/dev/null
  elif [ "$HAVE_JQ" = "1" ]; then
    "$JQ" -n \
      --arg status "$status" \
      --arg provider "$NAME" \
      --arg model "$MODEL" \
      --argjson issues "$issues_json" \
      --arg notes "$notes" \
      '{lens_status: $status, provider: $provider,
        model: (if $model == "" then null else $model end),
        issues: $issues, cost: "unknown"} +
       (if $notes == "" then {} else {notes: $notes} end)' \
      >"$OUT_FILE" 2>/dev/null
  else
    printf '{"lens_status":"%s","provider":"%s","model":%s,"issues":[],"cost":"unknown","notes":"%s"}\n' \
      "$(json_escape "$status")" "$(json_escape "$NAME")" \
      "$( [ -n "$MODEL" ] && printf '"%s"' "$(json_escape "$MODEL")" || printf 'null' )" \
      "$(json_escape "${notes:-jq unavailable on this machine}")" \
      >"$OUT_FILE" 2>/dev/null
  fi
  exit 0
}

# ---- cheapest gate first: allowlist NAME, then the provider-table file, then the CLI -----
# Allowlist BEFORE building a sourced path — a slash / `..` / metacharacter in
# NAME must not escape $SCRIPT_DIR. operator-supplied flag or config, not
# diff content, but the same argv hygiene the header already claims.
case "$NAME" in
  ""|*[!a-zA-Z0-9_-]*)
    emit_result "provider_unavailable" "[]" "invalid provider name"
    ;;
esac

PROVIDER_FILE="$SCRIPT_DIR/provider-$NAME.sh"
if [ ! -r "$PROVIDER_FILE" ]; then
  emit_result "provider_unavailable" "[]" "no provider-table entry named '$NAME' under $SCRIPT_DIR"
fi

# shellcheck disable=SC1090
. "$PROVIDER_FILE"

command -v "$PROVIDER_CLI_NAME" >/dev/null 2>&1 || emit_result "provider_unavailable" "[]" ""

# ---- role registry (string checks only; no sandbox, no provider CLI) -----------
# The note never echoes the role: it is a caller-supplied string and the jq-less
# fallback writer only escapes quotes and backslashes.
ROLES_FILE="$SCRIPT_DIR/lens-roles.sh"
[ -r "$ROLES_FILE" ] || emit_result "lens_unparseable" "[]" "lens-roles.sh is missing - no role can be resolved"
# shellcheck disable=SC1090
. "$ROLES_FILE"
lens_role_lookup "$ROLE" || emit_result "lens_unparseable" "[]" "unknown role (not registered in lens-roles.sh)"

# ---- consent: a non-claude provider runs only with a user-scope grant ----------
# Read from resolve-egress-config.sh, the one reader of the user-scope file, in the
# invoking checkout (it keys the grant by that repo's slug). This sits BEFORE every
# sandbox step on purpose: an ungranted provider gets no clone and no process, and
# nothing of the diff or prompt leaves the machine. No flag or env var skips it.
# A missing / unreadable resolver or a value outside the name allowlist is "no grant".
if [ "$NAME" != "claude" ]; then
  EGRESS_RESOLVER="$SCRIPT_DIR/../../resolve-egress-config.sh"
  LENS_GRANTS=""
  if [ -r "$EGRESS_RESOLVER" ]; then
    LENS_GRANTS="$(bash "$EGRESS_RESOLVER" 2>/dev/null | sed -n 's/^PROVIDER_GRANTS=//p' | head -n 1)"
  fi
  case "$LENS_GRANTS" in *[!A-Za-z0-9_,-]*) LENS_GRANTS="" ;; esac
  case ",$LENS_GRANTS," in
    *",$NAME,"*) ;;
    *) emit_result "provider_not_granted" "[]" "no user-scope grant for this provider in this repo; nothing was sent" ;;
  esac
fi

[ -r "$DIFF_FILE" ] || emit_result "lens_unparseable" "[]" "--diff file not readable: $DIFF_FILE"
[ -r "$PROMPT_FILE" ] || emit_result "lens_unparseable" "[]" "--prompt file not readable: $PROMPT_FILE"

[ -n "$COMMIT" ] || COMMIT="$(git rev-parse HEAD 2>/dev/null)"
[ -n "$COMMIT" ] || emit_result "lens_unparseable" "[]" "could not resolve a target commit (not a git checkout, or --commit invalid)"

LENS_CLI_TIMEOUT="${LOOMWRIGHT_LENS_CLI_TIMEOUT:-300}"
case "$LENS_CLI_TIMEOUT" in
  ''|*[!0-9]*) LENS_CLI_TIMEOUT=300 ;;
esac
if [ "$LENS_CLI_TIMEOUT" -le 0 ]; then
  LENS_CLI_TIMEOUT=300
fi

# ---- the shared launcher (isolated HOME, scrubbed env, process group, bound) --
LAUNCHER="$SCRIPT_DIR/launch-provider-cli.sh"
[ -r "$LAUNCHER" ] || emit_result "lens_unparseable" "[]" "launch-provider-cli.sh is missing - the provider CLI cannot be started"
# shellcheck disable=SC1090
. "$LAUNCHER"

# ---- throwaway isolated sandbox, always cleaned up ---------------------------
# Atomic directory creation (not mktemp -u): git init / fetch into an empty
# dir is allowed, and there is no symlink-race window on the path name. The
# CLI's scrubbed HOME is the launcher's own per-launch isolated HOME, which the
# launcher removes on its normal and timeout paths; SCRUB_HOME below names it
# for the abort path.
WT_PATH="$(mktemp -d "${TMPDIR:-/tmp}/loomwright-lens-wt-XXXXXX" 2>/dev/null)"
SCRUB_HOME=""
if [ -z "$WT_PATH" ] || [ ! -d "$WT_PATH" ]; then
  emit_result "lens_unparseable" "[]" "could not create a sandbox temp dir"
fi

RAW_OUT=""
RAW_ERR=""
INTEGRITY_BEFORE=""

cleanup() {
  # A still-running CLI (this script was signalled mid-launch): kill its process
  # group and remove its isolated HOME.
  SCRUB_HOME="${LPC_HOME:-}"
  launch_provider_cli_abort
  # The CLI ran with its cwd in WT_PATH, so it could have re-permissioned dirs
  # there: the launcher's rmtree restores u+rwx (never through a symlink) first.
  launch_provider_cli_rmtree "$WT_PATH"
  launch_provider_cli_rmtree "$SCRUB_HOME"
  rm -f "$RAW_OUT" "$RAW_ERR" "$INTEGRITY_BEFORE" 2>/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Use an INDEPENDENT sandbox repo, never `git worktree add` — worktrees share
# the parent repository's .git/config, so `git remote remove origin` inside a
# worktree removes origin for the ENTIRE shared repo (main checkout + every
# other worktree sharing it). A fresh `git init` + shallow fetch gives this
# sandbox its own .git directory and its own config. (Incident: an earlier
# version of this script used `git worktree add` here and it deleted the
# parent repo's origin remote during testing — recovered manually. Do not
# revert to worktree add.)
#
# Shallow on purpose: `git clone --local` (and any local-path clone) silently
# IGNORES `--depth`, so a naive local clone copies full history of every
# local ref — the blast radius of a later `git push <url> --all`. `file://`
# forces the upload-pack path so `--depth 1 --no-tags` is honored. Only the
# reviewed tip is fetched.
SRC_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$SRC_ROOT" ] || emit_result "lens_unparseable" "[]" "could not resolve invoking checkout toplevel"
if ! git init --quiet "$WT_PATH" >/dev/null 2>&1; then
  emit_result "lens_unparseable" "[]" "git init failed for sandbox creation"
fi
if ! git -C "$WT_PATH" remote add origin "file://${SRC_ROOT}" >/dev/null 2>&1; then
  emit_result "lens_unparseable" "[]" "could not add isolated origin for shallow fetch"
fi
if ! git -C "$WT_PATH" fetch --depth 1 --no-tags --quiet origin "$COMMIT" >/dev/null 2>&1; then
  emit_result "lens_unparseable" "[]" "shallow fetch of $COMMIT failed for sandbox creation"
fi
if ! git -C "$WT_PATH" checkout --quiet --detach FETCH_HEAD >/dev/null 2>&1; then
  emit_result "lens_unparseable" "[]" "git checkout --detach failed for commit $COMMIT in sandbox"
fi

# TEST-ONLY INTROSPECTION HATCH (never read by production code paths): when
# set, records the resolved sandbox path so test-lens-run.sh can assert it
# was removed after the run. Documented here rather than left implicit so a
# future reader does not mistake it for a real feature.
if [ -n "${LOOMWRIGHT_LENS_DEBUG_WT_PATH_FILE:-}" ]; then
  printf '%s\n' "$WT_PATH" > "$LOOMWRIGHT_LENS_DEBUG_WT_PATH_FILE" 2>/dev/null
fi

# FAIL-CLOSED: do not run an untrusted CLI in a sandbox that still has a
# remote. Discarding this exit status was the earlier hole — if remove
# failed, origin still pointed at the parent (or the file:// URL) while
# the CLI ran anyway.
if ! git -C "$WT_PATH" remote remove origin >/dev/null 2>&1; then
  emit_result "lens_unparseable" "[]" "git remote remove origin failed — refuse to run provider CLI in a sandbox that still has a remote"
fi
if [ -n "$(git -C "$WT_PATH" remote 2>/dev/null)" ]; then
  emit_result "lens_unparseable" "[]" "sandbox still has remotes after origin removal — fail closed"
fi

# Snapshot security-relevant .git state AFTER isolation is established and
# BEFORE the CLI runs. Compared after the CLI; any delta is lens_mutated_tree
# even when `git status --porcelain` is empty.
git_integrity_fingerprint() {
  local repo="$1"
  {
    printf 'remotes:\n'
    git -C "$repo" remote -v 2>/dev/null | sort
    printf 'local-config:\n'
    git -C "$repo" config --local --list 2>/dev/null | sort
    printf 'config-cksum:\n'
    if [ -f "$repo/.git/config" ]; then
      cksum < "$repo/.git/config" 2>/dev/null
    fi
    printf 'refs:\n'
    git -C "$repo" show-ref 2>/dev/null | sort
    printf 'head:\n'
    git -C "$repo" rev-parse HEAD 2>/dev/null
    printf 'hooks:\n'
    if [ -d "$repo/.git/hooks" ]; then
      find "$repo/.git/hooks" \( -type f -o -type l \) ! -name '*.sample' -print 2>/dev/null \
        | sort \
        | while IFS= read -r hookf; do
            rel="${hookf#"$repo"/}"
            if [ -x "$hookf" ]; then hx=1; else hx=0; fi
            printf '%s x=%s %s\n' "$rel" "$hx" "$(cksum < "$hookf" 2>/dev/null)"
          done
    fi
  }
}

INTEGRITY_BEFORE="$(mktemp "${TMPDIR:-/tmp}/loomwright-lens-int-XXXXXX" 2>/dev/null)"
[ -n "$INTEGRITY_BEFORE" ] || emit_result "lens_unparseable" "[]" "could not allocate integrity snapshot file"
git_integrity_fingerprint "$WT_PATH" > "$INTEGRITY_BEFORE" 2>/dev/null

# ---- compose the prompt (shared across all providers) -----------------------
PROMPT_CONTENT="$(
  printf 'Role: %s\n\n' "$ROLE"
  cat "$PROMPT_FILE"
  printf '\n\n--- DIFF ---\n'
  cat "$DIFF_FILE"
  printf '\n\n--- OUTPUT CONTRACT ---\n'
  lens_role_contract "$ROLE"
)"

WORKSPACE_DIR="$WT_PATH"
provider_build_argv

RAW_OUT="$(mktemp "${TMPDIR:-/tmp}/loomwright-lens-out-XXXXXX" 2>/dev/null)"
RAW_ERR="$(mktemp "${TMPDIR:-/tmp}/loomwright-lens-err-XXXXXX" 2>/dev/null)"
[ -n "$RAW_OUT" ] && [ -n "$RAW_ERR" ] \
  || emit_result "lens_unparseable" "[]" "could not allocate temp files for provider output"

# ---- run the provider CLI inside the sandbox, through the shared launcher ----
# `isolated` home mode, cwd = the sandbox, bounded by LENS_CLI_TIMEOUT: the
# launcher owns the scrubbed env, the per-launch HOME with the provider's
# declared login copies, the own-process-group launch and the TERM -> KILL
# chain (see SAFETY POSTURE above for the honest limit of all of it).
if ! launch_provider_cli isolated "$LENS_CLI_TIMEOUT" "$WT_PATH" "$RAW_OUT" "$RAW_ERR" \
     "$PROVIDER_CLI_NAME" "${PROVIDER_ARGV[@]}"; then
  emit_result "lens_unparseable" "[]" "could not launch the provider CLI: $LPC_ERROR"
fi
CLI_TIMED_OUT="$LPC_TIMED_OUT"

# The provider's own not-logged-in pattern, checked once over the raw output.
# Used ONLY to name an otherwise-unparseable result (lens_parse_failure below).
CLI_NOT_LOGGED_IN=0
if [ -n "${PROBE_AUTH_NOT_LOGGED_IN_RE:-}" ] \
   && grep -qE -- "$PROBE_AUTH_NOT_LOGGED_IN_RE" "$RAW_OUT" "$RAW_ERR" 2>/dev/null; then
  CLI_NOT_LOGGED_IN=1
fi

# lens_parse_failure <note> — lens_unparseable; when the output matched the
# not-logged-in pattern the note BEGINS with the named status.
lens_parse_failure() {
  if [ "$CLI_NOT_LOGGED_IN" = "1" ]; then
    emit_result "lens_unparseable" "[]" "not_logged_in_isolated: the provider CLI reports no login under the isolated HOME; its login did not cross (declare it in provider-$NAME.sh: PROVIDER_LOGIN_FILES / PROVIDER_LOGIN_ENV${PROVIDER_LOGIN_ENV[0]:+; or set one of its declared login env vars: ${PROVIDER_LOGIN_ENV[*]}}) - $1"
  fi
  emit_result "lens_unparseable" "[]" "$1"
}

# ---- mutation / .git-integrity check (fail-closed, discard result) ----------
MUTATION="$(git -C "$WT_PATH" status --porcelain 2>/dev/null)"
INTEGRITY_AFTER="$(git_integrity_fingerprint "$WT_PATH" 2>/dev/null)"
INTEGRITY_PREV="$(cat "$INTEGRITY_BEFORE" 2>/dev/null)"
if [ -n "$MUTATION" ] || [ "$INTEGRITY_AFTER" != "$INTEGRITY_PREV" ]; then
  emit_result "lens_mutated_tree" "[]" "throwaway sandbox working tree or .git internals changed after the provider CLI ran; result discarded"
fi

if [ "$CLI_TIMED_OUT" = "1" ]; then
  emit_result "lens_unparseable" "[]" "provider CLI timed out after ${LENS_CLI_TIMEOUT}s; process group killed; result discarded"
fi

# ---- parse + normalize --------------------------------------------------------
if [ "$HAVE_JQ" != "1" ]; then
  emit_result "lens_unparseable" "[]" "jq unavailable on this machine — cannot parse or normalize provider output"
fi

if ! provider_extract_text "$RAW_OUT"; then
  lens_parse_failure "provider output did not match the expected envelope shape"
fi

if [ "$LENS_ROLE_KIND" = "text" ]; then
  RESULT_BYTES="$(printf '%s' "$PROVIDER_EXTRACTED" | env LC_ALL=C wc -c | tr -d ' ')"
  case "$RESULT_BYTES" in
    ""|*[!0-9]*) emit_result "lens_unparseable" "[]" "could not measure the provider text" ;;
  esac
  if [ "$RESULT_BYTES" -gt "$LENS_RESULT_TEXT_MAX" ]; then
    emit_result "lens_unparseable" "[]" "provider text exceeds the ${LENS_RESULT_TEXT_MAX}-byte result_text bound; result discarded"
  fi
  case "$PROVIDER_EXTRACTED" in
    *"$LENS_ROLE_MARKER"*) emit_result "ok" "[]" "" "$PROVIDER_EXTRACTED" ;;
    *) lens_parse_failure "provider text did not contain the role marker" ;;
  esac
fi

NORMALIZED="$(printf '%s' "$PROVIDER_EXTRACTED" | "$JQ" -c '
  if (type == "object") and ((.issues? // []) | type == "array") then
    [ (.issues // [])[] | {
        severity: (
          ((.severity // "MEDIUM") | tostring | ascii_upcase) as $s
          | if ($s | IN("BLOCKING","HIGH","MEDIUM","LOW")) then $s else "MEDIUM" end
        ),
        category: (
          ((.category // "new") | tostring) as $c
          | if ($c | IN("new","pre_existing","nit")) then $c else "new" end
        ),
        file: ((.file // "unknown") | tostring),
        line: (.line // null),
        description: ((.description // "") | tostring),
        suggestion: (if .suggestion == null then null else (.suggestion | tostring) end)
      } ]
  else
    null
  end
' 2>/dev/null)"

case "$NORMALIZED" in
  ""|null)
    lens_parse_failure "provider text did not contain a valid {\"issues\":[...]} object"
    ;;
  *)
    emit_result "ok" "$NORMALIZED" ""
    ;;
esac
