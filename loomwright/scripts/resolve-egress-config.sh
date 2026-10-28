#!/usr/bin/env bash
# resolve-egress-config.sh — USER-SCOPED egress resolver (telemetry consent +
# webhook destination), keyed by repo slug.
#
# red-team-hardening item 02 (FATAL, reproduced 2026-09-21): a scratch repo
# containing only a planted `.supervisor/telemetry-consent.json` could grant
# its OWN telemetry consent and choose its OWN destination repo, because
# send-telemetry-core.sh read that repo-relative file directly. The same
# class of bug applied to send-webhook.sh's `.supervisor/config.json` ->
# `.webhook_url` read.
#
# SECURITY CONTRACT: consent + egress destinations are facts about the USER,
# not the repo. They live ONLY in ~/.claude/loomwright/egress.json, keyed by
# repo slug. A repo-relative file's values are read here too, but printed
# under separate REPO_REQUESTED_* keys — informational only. Callers (the two
# emitters) MUST NOT feed REPO_REQUESTED_* into anything that grants consent
# or chooses a destination; they may only compare it to the resolved value and
# log a "request ignored" line when it differs.
#
# Always exits 0 (fail-SAFE emitter contract — see docs/TELEMETRY.md). Prints
# `KEY=VALUE` lines, one per line. Unreadable or malformed user-scope file =>
# every value below prints empty (fail CLOSED — never a fabricated default).
#
# Output keys (all always printed, value may be empty):
#   REPO_SLUG                      - normalized "owner/repo" from `git remote get-url
#                                     origin`, else "local:<toplevel-basename>", else
#                                     empty when $PWD is not inside a git repo.
#   TELEMETRY                      - "always_allow" | "no" | empty — user-scope ONLY,
#                                     never influenced by any repo-relative file.
#   TELEMETRY_REPO                 - user-scope entry's telemetry_repo, overridden by
#                                     LOOMWRIGHT_TELEMETRY_REPO when set (highest
#                                     precedence for the REPO VALUE only — it does
#                                     NOT itself grant consent).
#   WEBHOOK_URL                    - user-scope entry's webhook_url, overridden by
#                                     LOOMWRIGHT_WEBHOOK_URL when set (highest
#                                     precedence).
#   WEBHOOK_URL_SHA256              - sha256 of the resolved WEBHOOK_URL above (empty
#                                     when WEBHOOK_URL is empty). Callers use this to
#                                     compare a repo-requested URL without needing to
#                                     re-derive it themselves.
#   INCLUDE_RESULT_BLOCK            - "true" | "" (empty means false/unset) — USER-SCOPE
#                                     ONLY, set via `/telemetry enable --include-result-block`.
#                                     INERT since triage PR-1: send-telemetry-core.sh ships
#                                     plugin facts only and ignores this value (it logs
#                                     include_result_block_ignored). Still printed so the
#                                     key's removal stays a separate owner decision.
#   REPO_REQUESTED_TELEMETRY_REPO  - informational only, from
#                                     .supervisor/telemetry-consent.json's
#                                     telemetry_repo field. NEVER fed into TELEMETRY
#                                     or TELEMETRY_REPO above.
#   REPO_REQUESTED_WEBHOOK_URL     - informational only, from .supervisor/config.json
#                                     (legacy .supervisor/notify-config.json fallback,
#                                     same precedence send-webhook.sh has always used)
#                                     webhook_url field. NEVER fed into WEBHOOK_URL
#                                     above.
#   PROVIDER_GRANTS                - comma-joined provider names the USER granted this
#                                     repo (repos.<slug>.providers), each filtered to
#                                     [A-Za-z0-9_-]+. User-scope ONLY — the consent
#                                     `lens-run.sh` and `resolve-routing.sh` check before
#                                     a non-Claude provider CLI is started. `claude` never
#                                     needs a grant. Empty on an unreadable / malformed file.
#   REPO_REQUESTED_PROVIDERS       - informational only, from .supervisor/config.json
#                                     (`routing.seats` values + `.voter_provider`): the
#                                     non-Claude providers the repo ASKS to route to.
#                                     NEVER fed into PROVIDER_GRANTS above; nothing grants
#                                     from it.
#
# User-scope schema (~/.claude/loomwright/egress.json):
#   {
#     "schema_version": 1,
#     "repos": {
#       "<slug>": {
#         "telemetry": "always_allow" | "no",
#         "telemetry_repo": "<owner>/<repo>",
#         "webhook_url": "https://...",
#         "webhook_url_sha256": "<hex>",
#         "providers": ["<provider>", ...]
#       }
#     }
#   }
# `webhook_url_sha256` is written by the tooling that writes this file
# (`/telemetry enable`, `/setup webhook`) for tamper-evidence / quick grep
# without exposing the raw URL; this resolver does not trust it — it always
# recomputes WEBHOOK_URL_SHA256 from the resolved WEBHOOK_URL itself.

set -u
trap 'exit 0' EXIT

REPO_SLUG=""
TELEMETRY=""
TELEMETRY_REPO=""
WEBHOOK_URL=""
WEBHOOK_URL_SHA256=""
INCLUDE_RESULT_BLOCK=""
REPO_REQUESTED_TELEMETRY_REPO=""
REPO_REQUESTED_WEBHOOK_URL=""
PROVIDER_GRANTS=""
REPO_REQUESTED_PROVIDERS=""

sha256_hex() {
  local s="${1:-}"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$s" | shasum -a 256 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$s" | sha256sum 2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    printf '%s' "$s" | openssl dgst -sha256 2>/dev/null | awk '{print $NF}'
  else
    printf ''
  fi
}

# ---- Repo slug ------------------------------------------------------------
if command -v git >/dev/null 2>&1 && git -C "$PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ORIGIN_URL="$(git -C "$PWD" remote get-url origin 2>/dev/null || true)"
  NORM=""
  if [ -n "$ORIGIN_URL" ]; then
    NORM="${ORIGIN_URL%.git}"
    NORM="${NORM%/}"
    case "$NORM" in
      git@*:*)
        NORM="${NORM#*@}"   # host:owner/repo
        NORM="${NORM#*:}"   # owner/repo
        ;;
      ssh://*|https://*|http://*|git://*)
        NORM="${NORM#*://}" # [user@]host/owner/repo
        NORM="${NORM#*@}"   # host/owner/repo (no-op if there was no user@)
        NORM="${NORM#*/}"   # owner/repo
        ;;
    esac
  fi
  if printf '%s' "$NORM" | grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'; then
    REPO_SLUG="$NORM"
  else
    TOPLEVEL="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$TOPLEVEL" ]; then
      REPO_SLUG="local:$(basename "$TOPLEVEL")"
    fi
  fi
fi

# ---- User-scope entry — the ONLY source of TELEMETRY / TELEMETRY_REPO /
#      WEBHOOK_URL. A missing/unreadable/malformed file, or no entry for this
#      slug, leaves all three empty (fail CLOSED). --------------------------
USER_SCOPE_FILE="${HOME:-}/.claude/loomwright/egress.json"
if [ -n "$REPO_SLUG" ] && [ -n "${HOME:-}" ] && [ -r "$USER_SCOPE_FILE" ] && command -v jq >/dev/null 2>&1; then
  if jq -e . "$USER_SCOPE_FILE" >/dev/null 2>&1; then
    TELEMETRY="$(jq -r --arg s "$REPO_SLUG" \
      '(.repos[$s].telemetry // "") | if type == "string" then . else "" end' \
      "$USER_SCOPE_FILE" 2>/dev/null || true)"
    TELEMETRY_REPO="$(jq -r --arg s "$REPO_SLUG" \
      '(.repos[$s].telemetry_repo // "") | if type == "string" then . else "" end' \
      "$USER_SCOPE_FILE" 2>/dev/null || true)"
    WEBHOOK_URL="$(jq -r --arg s "$REPO_SLUG" \
      '(.repos[$s].webhook_url // "") | if type == "string" then . else "" end' \
      "$USER_SCOPE_FILE" 2>/dev/null || true)"
    INCLUDE_RESULT_BLOCK="$(jq -r --arg s "$REPO_SLUG" \
      '(.repos[$s].include_result_block // false) | if type == "boolean" and . then "true" else "" end' \
      "$USER_SCOPE_FILE" 2>/dev/null || true)"
    # Provider grants: an array of names; a non-array, or a name failing the
    # allowlist (\A..\z, not ^..$ — Oniguruma's $ also matches before an embedded
    # newline), is dropped, never passed through.
    PROVIDER_GRANTS="$(jq -r --arg s "$REPO_SLUG" \
      '(.repos[$s].providers // []) | if type == "array" then [.[] | select(type == "string" and test("\\A[A-Za-z0-9_-]+\\z"))] | join(",") else "" end' \
      "$USER_SCOPE_FILE" 2>/dev/null || true)"
  fi
fi
# Any jq failure above leaves the three vars at their initial "" default.

# ---- Newline-injection defense (applies to EVERY printed value below) -----
# `jq -r` decodes a JSON `\n` escape into a REAL newline byte in the string
# it returns — it does not strip it. Every value below is printed as a
# `KEY=VALUE` line that BOTH emitters (send-telemetry-core.sh,
# send-webhook.sh) parse with a naive `while IFS='=' read -r rk rv` loop over
# this script's raw stdout. An attacker-controlled JSON string value (from
# either a repo-relative file OR — defense in depth — a corrupted/hostile
# user-scope file) containing an embedded newline followed by
# "REAL_KEY=forged_value" therefore becomes an EXTRA stdout line
# indistinguishable from a genuinely resolved key, letting a single
# REPO_REQUESTED_* value forge TELEMETRY=always_allow /
# TELEMETRY_REPO=<attacker repo> / WEBHOOK_URL=<attacker url> lines that the
# naive consumer loop overwrites its real (possibly empty/fail-closed) values
# with. Reproduced live 2026-09-21 against send-telemetry-core.sh --dry-run
# (WOULD_EXIT=0 / TARGET_REPO=attacker/sink despite an EMPTY user scope) and
# send-webhook.sh (an actual POST to an attacker URL). Fix: blank (never
# truncate-at-newline — that would still leak a forged suffix) any value that
# contains an embedded newline, before it is ever printed. `case` is used,
# not `${var//pattern/repl}`, per this repo's documented bash 3.2 O(n²)
# pattern-substitution trap on attacker-sized strings.
strip_if_newline() {
  local v="$1"
  case "$v" in
    *$'\n'*) printf '' ;;
    *) printf '%s' "$v" ;;
  esac
}

# ---- Process-env overrides (highest precedence for the REPO / URL VALUES
#      only — NEVER for the TELEMETRY consent decision itself; there is no
#      env var that can grant consent). -------------------------------------
if [ -n "${LOOMWRIGHT_TELEMETRY_REPO:-}" ]; then
  TELEMETRY_REPO="$LOOMWRIGHT_TELEMETRY_REPO"
fi
if [ -n "${LOOMWRIGHT_WEBHOOK_URL:-}" ]; then
  WEBHOOK_URL="$LOOMWRIGHT_WEBHOOK_URL"
fi

# Sanitize every value sourced so far (user-scope file AND env overrides)
# BEFORE it is used for anything further — in particular before the sha256
# below, so WEBHOOK_URL_SHA256 always matches the WEBHOOK_URL that actually
# gets printed, never the pre-sanitized original.
REPO_SLUG="$(strip_if_newline "$REPO_SLUG")"
TELEMETRY="$(strip_if_newline "$TELEMETRY")"
TELEMETRY_REPO="$(strip_if_newline "$TELEMETRY_REPO")"
WEBHOOK_URL="$(strip_if_newline "$WEBHOOK_URL")"
INCLUDE_RESULT_BLOCK="$(strip_if_newline "$INCLUDE_RESULT_BLOCK")"
PROVIDER_GRANTS="$(strip_if_newline "$PROVIDER_GRANTS")"

if [ -n "$WEBHOOK_URL" ]; then
  WEBHOOK_URL_SHA256="$(sha256_hex "$WEBHOOK_URL")"
fi

# ---- Repo-relative REQUESTS — informational only. Never assigned to
#      TELEMETRY / TELEMETRY_REPO / WEBHOOK_URL above. ----------------------
CONSENT_REQUEST_FILE="${PWD}/.supervisor/telemetry-consent.json"
if [ -r "$CONSENT_REQUEST_FILE" ] && command -v jq >/dev/null 2>&1; then
  if jq -e . "$CONSENT_REQUEST_FILE" >/dev/null 2>&1; then
    REPO_REQUESTED_TELEMETRY_REPO="$(jq -r \
      '(.telemetry_repo // "") | if type == "string" then . else "" end' \
      "$CONSENT_REQUEST_FILE" 2>/dev/null || true)"
  fi
fi

# Same file precedence send-webhook.sh has always used: new path wins, legacy
# path is still read as a fallback when the new one is absent/unreadable.
for _cfg in "${PWD}/.supervisor/config.json" "${PWD}/.supervisor/notify-config.json"; do
  [ -r "$_cfg" ] || continue
  command -v jq >/dev/null 2>&1 || break
  jq -e . "$_cfg" >/dev/null 2>&1 || continue
  _v="$(jq -r '(.webhook_url // "") | if type == "string" then . else "" end' "$_cfg" 2>/dev/null || true)"
  if [ -n "$_v" ]; then
    REPO_REQUESTED_WEBHOOK_URL="$_v"
    break
  fi
done

# Providers the repo asks to route to — informational only, never assigned to
# PROVIDER_GRANTS. Names are filtered to the same allowlist and `claude` (which
# needs no grant) is omitted.
if [ -r "${PWD}/.supervisor/config.json" ] && command -v jq >/dev/null 2>&1; then
  REPO_REQUESTED_PROVIDERS="$(jq -r \
    '[ ((.routing.seats // {}) | to_entries[]? | .value | (if type == "array" then .[] else . end) | select(type == "string") | split(":")[0]),
       ((.voter_provider // "") | select(type == "string" and . != "") | split(":")[0]) ]
     | map(select(test("\\A[A-Za-z0-9_-]+\\z") and . != "claude")) | unique | join(",")' \
    "${PWD}/.supervisor/config.json" 2>/dev/null || true)"
fi

# Same newline-injection defense as above, applied to the informational
# REPO_REQUESTED_* fields — these are the attacker's actual entry point
# (a repo-relative file this script's own header says is untrusted), so this
# is the sanitization that closes the live-reproduced vulnerability.
REPO_REQUESTED_TELEMETRY_REPO="$(strip_if_newline "$REPO_REQUESTED_TELEMETRY_REPO")"
REPO_REQUESTED_WEBHOOK_URL="$(strip_if_newline "$REPO_REQUESTED_WEBHOOK_URL")"
REPO_REQUESTED_PROVIDERS="$(strip_if_newline "$REPO_REQUESTED_PROVIDERS")"

printf 'REPO_SLUG=%s\n' "$REPO_SLUG"
printf 'TELEMETRY=%s\n' "$TELEMETRY"
printf 'TELEMETRY_REPO=%s\n' "$TELEMETRY_REPO"
printf 'WEBHOOK_URL=%s\n' "$WEBHOOK_URL"
printf 'WEBHOOK_URL_SHA256=%s\n' "$WEBHOOK_URL_SHA256"
printf 'INCLUDE_RESULT_BLOCK=%s\n' "$INCLUDE_RESULT_BLOCK"
printf 'REPO_REQUESTED_TELEMETRY_REPO=%s\n' "$REPO_REQUESTED_TELEMETRY_REPO"
printf 'REPO_REQUESTED_WEBHOOK_URL=%s\n' "$REPO_REQUESTED_WEBHOOK_URL"
printf 'PROVIDER_GRANTS=%s\n' "$PROVIDER_GRANTS"
printf 'REPO_REQUESTED_PROVIDERS=%s\n' "$REPO_REQUESTED_PROVIDERS"

exit 0
