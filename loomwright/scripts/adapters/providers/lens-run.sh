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
#   --provider   REQUIRED. One of the provider-table entries below
#                (`claude`, `cursor`, `codex`, `gemini` as of this writing —
#                adding a fifth provider means adding one new
#                `provider-<name>.sh` file, never editing this one), optionally
#                suffixed `:<model>` (e.g. `cursor:gpt-5`). NAME is allowlisted
#                to `[A-Za-z0-9_-]` before it is spliced into a sourced path.
#   --role       REQUIRED. Free-form string folded into the composed prompt
#                header (e.g. "review"). Not branched on here — a caller-owned
#                convention, kept generic for future roles (e.g. a future
#                "refute" role used by the multi-voter refute check — see
#                skills/self-heal-advisory/SKILL.md §"Multi-voter verification").
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
#     "lens_status": "ok" | "provider_unavailable" | "lens_mutated_tree" | "lens_unparseable",
#     "provider": "<name>", "model": "<model>" | null,
#     "issues": [ {severity, category, file, line, description, suggestion}, ... ],
#     "cost": "unknown",   # D11 cost-honesty: provider usage is not in
#                          # token_ledger and no CLI here reports usage in a
#                          # confirmed shape — "unknown", NEVER "0".
#     "notes": "<optional short string>"   # present only on non-"ok" statuses
#   }
#
# DEGRADATION (four outcomes, ALL exit 0, ALL treated identically by the
# calling multi-voter loop — "voter errored/timed out", the EXISTING fail-safe
# degradation skills/self-heal-advisory/SKILL.md already specifies):
#   provider_unavailable  — the provider's CLI is not on PATH, the --provider
#                            NAME fails the allowlist, or no provider-<name>.sh
#                            exists. Checked BEFORE any other work (cheapest
#                            gate first, mirrors orca-mirror.sh) — NO
#                            subprocess is attempted.
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
#                            Degrades rather than guessing.
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
#     (a) a scrubbed, allow-list child environment (`env -i` — starts EMPTY,
#         so no ambient credential, including GH_TOKEN, survives unless this
#         script explicitly re-adds it; it does not),
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
#   PROVIDER_HOME_SCRUB     0 | 1   — always 1 today (every provider's real
#                                     HOME-survival requirement is UNVERIFIED
#                                     on this machine — see each file's own
#                                     header); reserved for a future provider
#                                     that proves it needs real HOME.
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

# emit_result <lens_status> <issues_json_array> [notes] — writes --out and
# exits 0. `issues_json` must already be a valid JSON array string when
# HAVE_JQ=1; the HAVE_JQ=0 fallback never receives a non-"[]" issues array
# (see the jq-unavailable short-circuit below), so no fallback parsing of it
# is needed.
emit_result() {
  local status="$1" issues_json="$2" notes="${3:-}"
  if [ "$HAVE_JQ" = "1" ]; then
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

# ---- throwaway isolated sandbox + scrubbed HOME, always cleaned up ----------
# Atomic directory creation (not mktemp -u): git init / fetch into an empty
# dir is allowed, and there is no symlink-race window on the path name.
WT_PATH="$(mktemp -d "${TMPDIR:-/tmp}/loomwright-lens-wt-XXXXXX" 2>/dev/null)"
SCRUB_HOME="$(mktemp -d "${TMPDIR:-/tmp}/loomwright-lens-home-XXXXXX" 2>/dev/null)"
if [ -z "$WT_PATH" ] || [ ! -d "$WT_PATH" ]; then
  emit_result "lens_unparseable" "[]" "could not create a sandbox temp dir"
fi
if [ -z "$SCRUB_HOME" ] || [ ! -d "$SCRUB_HOME" ]; then
  rm -rf "$WT_PATH" 2>/dev/null
  emit_result "lens_unparseable" "[]" "could not create a scrubbed HOME temp dir"
fi

CLI_PID=""
CLI_PGID=""
CLI_WATCHDOG_PID=""
CLI_OWN_PGROUP=0
LENS_SELF_PGID="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
RAW_OUT=""
RAW_ERR=""
INTEGRITY_BEFORE=""
TIMEOUT_FLAG=""

lens_kill_cli() {
  local sig="${1:-TERM}"
  if [ -n "${CLI_PGID:-}" ] && [ "$CLI_OWN_PGROUP" = "1" ] \
     && [ "$CLI_PGID" != "1" ] && [ "$CLI_PGID" != "$LENS_SELF_PGID" ]; then
    kill -s "$sig" -- -"$CLI_PGID" 2>/dev/null
    return 0
  fi
  if [ -n "${CLI_PID:-}" ]; then
    kill -s "$sig" "$CLI_PID" 2>/dev/null
    if command -v pgrep >/dev/null 2>&1; then
      local child
      for child in $(pgrep -P "$CLI_PID" 2>/dev/null); do
        kill -s "$sig" "$child" 2>/dev/null
      done
    fi
  fi
}

cleanup() {
  if [ -n "${CLI_WATCHDOG_PID:-}" ]; then
    kill "$CLI_WATCHDOG_PID" 2>/dev/null
    wait "$CLI_WATCHDOG_PID" 2>/dev/null
    CLI_WATCHDOG_PID=""
  fi
  if [ -n "${CLI_PID:-}" ] || [ -n "${CLI_PGID:-}" ]; then
    lens_kill_cli TERM
    sleep 1
    lens_kill_cli KILL
    CLI_PID=""
    CLI_PGID=""
  fi
  rm -rf "$WT_PATH" "$SCRUB_HOME" 2>/dev/null
  rm -f "$RAW_OUT" "$RAW_ERR" "$INTEGRITY_BEFORE" "$TIMEOUT_FLAG" 2>/dev/null
}
trap cleanup EXIT

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
  printf 'Respond with ONLY a single JSON object, no prose outside it, matching exactly:\n'
  printf '{"issues": [{"severity": "BLOCKING|HIGH|MEDIUM|LOW", "category": "new|pre_existing|nit", "file": "<path>", "line": <integer or null>, "description": "<string>", "suggestion": "<string or null>"}]}\n'
)"

WORKSPACE_DIR="$WT_PATH"
provider_build_argv

RAW_OUT="$(mktemp "${TMPDIR:-/tmp}/loomwright-lens-out-XXXXXX" 2>/dev/null)"
RAW_ERR="$(mktemp "${TMPDIR:-/tmp}/loomwright-lens-err-XXXXXX" 2>/dev/null)"
TIMEOUT_FLAG="$(mktemp "${TMPDIR:-/tmp}/loomwright-lens-tmo-XXXXXX" 2>/dev/null)"
[ -n "$RAW_OUT" ] && [ -n "$RAW_ERR" ] && [ -n "$TIMEOUT_FLAG" ] \
  || emit_result "lens_unparseable" "[]" "could not allocate temp files for provider output"

# ---- run the provider CLI inside the sandbox, scrubbed env, bounded --------
# `env -i` starts with an EMPTY environment — no ambient var (GH_TOKEN
# included) survives unless explicitly re-added below. PATH is re-added so the
# CLI (and anything it shells out to) can still be found; HOME/TMPDIR point at
# the throwaway scrub dir (see SAFETY POSTURE above for the honest limit of
# this mitigation).
#
# The CLI is launched as its own process group (perl/python setpgrp) so a
# timeout or cleanup can kill the whole tree — not just the leader — and so
# `rm -rf` of the sandbox is not racing a hung child. GNU timeout is a
# fallback, not the primary, because stock macOS has neither timeout nor
# gtimeout.

lens_exec_cli() {
  if command -v perl >/dev/null 2>&1; then
    exec perl -e 'setpgrp; exec @ARGV' \
      env -i PATH="$PATH" HOME="$SCRUB_HOME" TMPDIR="$SCRUB_HOME" \
      "$PROVIDER_CLI_NAME" "${PROVIDER_ARGV[@]}"
  fi
  if command -v python3 >/dev/null 2>&1; then
    exec python3 -c 'import os, sys; os.setpgrp(); os.execvp(sys.argv[1], sys.argv[1:])' \
      env -i PATH="$PATH" HOME="$SCRUB_HOME" TMPDIR="$SCRUB_HOME" \
      "$PROVIDER_CLI_NAME" "${PROVIDER_ARGV[@]}"
  fi
  if command -v timeout >/dev/null 2>&1; then
    exec timeout --kill-after=5 --signal=TERM "$LENS_CLI_TIMEOUT" \
      env -i PATH="$PATH" HOME="$SCRUB_HOME" TMPDIR="$SCRUB_HOME" \
      "$PROVIDER_CLI_NAME" "${PROVIDER_ARGV[@]}"
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    exec gtimeout --kill-after=5 --signal=TERM "$LENS_CLI_TIMEOUT" \
      env -i PATH="$PATH" HOME="$SCRUB_HOME" TMPDIR="$SCRUB_HOME" \
      "$PROVIDER_CLI_NAME" "${PROVIDER_ARGV[@]}"
  fi
  exec env -i PATH="$PATH" HOME="$SCRUB_HOME" TMPDIR="$SCRUB_HOME" \
    "$PROVIDER_CLI_NAME" "${PROVIDER_ARGV[@]}"
}

(
  cd "$WT_PATH" || exit 90
  lens_exec_cli
) >"$RAW_OUT" 2>"$RAW_ERR" &
CLI_PID=$!
CLI_PGID="$CLI_PID"
if command -v perl >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
  CLI_OWN_PGROUP=1
fi

(
  sleep "$LENS_CLI_TIMEOUT"
  if kill -0 "$CLI_PID" 2>/dev/null; then
    printf '1\n' > "$TIMEOUT_FLAG"
    lens_kill_cli TERM
    sleep 2
    lens_kill_cli KILL
  fi
) &
CLI_WATCHDOG_PID=$!

wait "$CLI_PID"
CLI_WAIT_RC=$?
if [ -n "$CLI_WATCHDOG_PID" ]; then
  kill "$CLI_WATCHDOG_PID" 2>/dev/null
  wait "$CLI_WATCHDOG_PID" 2>/dev/null
  CLI_WATCHDOG_PID=""
fi
CLI_PID=""
CLI_PGID=""

CLI_TIMED_OUT=0
if [ -s "$TIMEOUT_FLAG" ]; then
  CLI_TIMED_OUT=1
fi
# GNU timeout fallback path (no setpgrp helper): 124 means the bound fired.
if [ "$CLI_OWN_PGROUP" != "1" ] && [ "$CLI_WAIT_RC" -eq 124 ]; then
  CLI_TIMED_OUT=1
fi

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
  emit_result "lens_unparseable" "[]" "provider output did not match the expected envelope shape"
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
    emit_result "lens_unparseable" "[]" "provider text did not contain a valid {\"issues\":[...]} object"
    ;;
  *)
    emit_result "ok" "$NORMALIZED" ""
    ;;
esac
