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
#                suffixed `:<model>` (e.g. `cursor:gpt-5`).
#   --role       REQUIRED. Free-form string folded into the composed prompt
#                header (e.g. "review"). Not branched on here — a caller-owned
#                convention, kept generic for future roles (e.g. a future
#                "refute" role used by the multi-voter refute check — see
#                skills/self-heal-advisory/SKILL.md §"Multi-voter verification").
#   --diff       REQUIRED. Path to a file containing the diff text to review.
#   --prompt     REQUIRED. Path to a file containing the review instructions
#                (caller-authored; folded verbatim into the composed prompt).
#   --out        REQUIRED. Path to write the normalized JSON result to.
#   --commit     OPTIONAL. The commit the throwaway isolated local clone checks out.
#                Defaults to `git rev-parse HEAD` in the invoking checkout —
#                this script is normally run from inside a checkout already at
#                the diff's target commit (Phase 4.5's self-heal loop, or the
#                `--until-mergeable` drain), so HEAD is the right default; a
#                caller reviewing a different commit overrides explicitly.
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
#   provider_unavailable  — the provider's CLI is not on PATH. Checked BEFORE
#                            any other work (cheapest gate first, mirrors
#                            orca-mirror.sh) — NO subprocess is attempted.
#   lens_mutated_tree      — the throwaway isolated local clone was dirty
#                            (`git status --porcelain` non-empty) after the
#                            CLI ran. Result DISCARDED; sandbox clone removed
#                            either way (see SAFETY POSTURE).
#   lens_unparseable        — the CLI's raw output did not parse into the
#                            expected envelope, or `jq` itself is unavailable
#                            on this machine (parsing is infeasible without
#                            it — degrades rather than guessing).
#   ok                     — well-formed, normalized `issues[]`.
#
# SAFETY POSTURE — READ THIS BEFORE RELYING ON IT (honesty required by the
# source requirement; never call this "enforced" or "safe" elsewhere in this
# repo's docs/comments):
#   The throwaway-isolated-clone-plus-mutation-check below DETECTS mutation of
#   the sandbox clone ONLY. A CLI with bash/tool access can still write
#   OUTSIDE the sandbox clone (the main checkout, ~/.claude, a `git push` to
#   some other remote) — that is UNMITIGATED here. Mitigations actually in scope:
#     (a) a scrubbed, allow-list child environment (`env -i` — starts EMPTY,
#         so no ambient credential, including GH_TOKEN, survives unless this
#         script explicitly re-adds it; it does not),
#     (b) `--workspace <dir>` (or, for a provider with no such flag, running
#         with cwd = the sandbox clone — see each provider-<name>.sh file's own
#         PROVIDER_WORKSPACE_FLAG),
#     (c) `git remote remove origin` in the isolated local clone before the
#         CLI runs, so a push from inside it has nowhere to go.
#   The `cursor-agent -f`/deny-by-default probe named in the source
#   requirement's Mechanism section is DEFERRED (cursor-agent is installed on
#   this machine but NOT authenticated, and the owner declined an interactive
#   login during the automated run that produced this file — see that
#   requirement file's "Probe result — 2026-09-18, DEFERRED" section). Until
#   that probe runs, treat (a)-(c) as the ONLY confirmed levers — NOT a
#   backstop to a confirmed deny-by-default. See
#   docs/ARCHITECTURE_CONTRACTS.md §"Portability" for the same framing.
#
# INJECTION SAFETY — every provider CLI invocation is built as a bash ARRAY
# (PROVIDER_ARGV, assembled by the provider's own provider_build_argv; see
# each provider-<name>.sh file), never a single interpolated command string,
# never `eval`. A hostile diff/prompt/model value can only ever become ONE
# argv element and can never break out into a second command.
#
# PROVIDER-TABLE FILE CONTRACT (every loomwright/scripts/adapters/providers/
# provider-<name>.sh file, sourced by this script, must define):
#   PROVIDER_CLI_NAME       string  — the binary `command -v` checks for.
#   PROVIDER_WORKSPACE_FLAG 0 | 1   — documentation-only (this script ALWAYS
#                                     runs the subprocess with cwd = the
#                                     sandbox clone regardless); 1 means the
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

# ---- cheapest gate first: resolve the provider-table file, then the CLI -----
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

# ---- throwaway isolated local clone + scrubbed HOME, always cleaned up ------
WT_PATH="$(mktemp -u "${TMPDIR:-/tmp}/loomwright-lens-wt-XXXXXX" 2>/dev/null)"
[ -n "$WT_PATH" ] || WT_PATH="${TMPDIR:-/tmp}/loomwright-lens-wt-$$"
SCRUB_HOME="$(mktemp -d "${TMPDIR:-/tmp}/loomwright-lens-home-XXXXXX" 2>/dev/null)"
if [ -z "$SCRUB_HOME" ] || [ ! -d "$SCRUB_HOME" ]; then
  emit_result "lens_unparseable" "[]" "could not create a scrubbed HOME temp dir"
fi

cleanup() {
  rm -rf "$WT_PATH" "$SCRUB_HOME" 2>/dev/null
}
trap cleanup EXIT

# Use an INDEPENDENT local clone, never `git worktree add` — worktrees share
# the parent repository's .git/config, so `git remote remove origin` inside a
# worktree removes origin for the ENTIRE shared repo (main checkout + every
# other worktree sharing it). `git clone --local` gives this sandbox its own
# .git directory and its own config, so removing ITS origin is fully isolated
# from the parent repo. (Incident: an earlier version of this script used
# `git worktree add` here and it deleted the parent repo's origin remote
# during testing — recovered manually. Do not revert to worktree add.)
if ! git clone --local --no-hardlinks --quiet "$(git rev-parse --show-toplevel)" "$WT_PATH" >/dev/null 2>&1; then
  emit_result "lens_unparseable" "[]" "git clone --local failed for sandbox creation"
fi
if ! git -C "$WT_PATH" checkout --quiet --detach "$COMMIT" >/dev/null 2>&1; then
  emit_result "lens_unparseable" "[]" "git checkout --detach failed for commit $COMMIT in sandbox clone"
fi

# TEST-ONLY INTROSPECTION HATCH (never read by production code paths): when
# set, records the resolved sandbox path so test-lens-run.sh can assert it
# was removed after the run. Documented here rather than left implicit so a
# future reader does not mistake it for a real feature.
if [ -n "${LOOMWRIGHT_LENS_DEBUG_WT_PATH_FILE:-}" ]; then
  printf '%s\n' "$WT_PATH" > "$LOOMWRIGHT_LENS_DEBUG_WT_PATH_FILE" 2>/dev/null
fi

git -C "$WT_PATH" remote remove origin >/dev/null 2>&1   # isolated clone — safe here, does not touch the parent repo

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
[ -n "$RAW_OUT" ] && [ -n "$RAW_ERR" ] || emit_result "lens_unparseable" "[]" "could not allocate temp files for provider output"
# shellcheck disable=SC2064
trap "cleanup; rm -f '$RAW_OUT' '$RAW_ERR'" EXIT

# ---- run the provider CLI inside the sandbox clone, with a scrubbed environment --
# `env -i` starts with an EMPTY environment — no ambient var (GH_TOKEN
# included) survives unless explicitly re-added below. PATH is re-added so the
# CLI (and anything it shells out to) can still be found; HOME/TMPDIR point at
# the throwaway scrub dir (see SAFETY POSTURE above for the honest limit of
# this mitigation).
(
  cd "$WT_PATH" || exit 90
  exec env -i PATH="$PATH" HOME="$SCRUB_HOME" TMPDIR="$SCRUB_HOME" \
    "$PROVIDER_CLI_NAME" "${PROVIDER_ARGV[@]}"
) >"$RAW_OUT" 2>"$RAW_ERR"

# ---- mutation check (AC: non-empty -> discard + lens_mutated_tree) ----------
MUTATION="$(git -C "$WT_PATH" status --porcelain 2>/dev/null)"
if [ -n "$MUTATION" ]; then
  emit_result "lens_mutated_tree" "[]" "throwaway sandbox clone was dirty after the provider CLI ran; result discarded"
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
