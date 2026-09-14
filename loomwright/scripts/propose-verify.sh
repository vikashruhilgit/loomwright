#!/usr/bin/env bash
# propose-verify.sh — the PROPOSE-ONLY, CONFIRM-GATED bootstrap for the committed
# `.agent/verify.json` verification-environment contract (how the app under test is started /
# health-checked / authenticated / seeded / reset, and how the plugin proves the target is NOT
# production). It SCANS the project for candidate values, PRINTS the proposal, and writes ONLY on
# `--confirm` or an interactive TTY "yes".
#
# It is the SOLE WRITER of `.agent/verify.json`, and it writes NOTHING ELSE — not a log, not a
# marker, not a backup. The only other filesystem effect is creating the containing `.agent/`
# directory when it does not already exist, and a same-directory temp file that exists only for
# the duration of the atomic move. The seam test (test-verify-seam.sh, AC5) greps
# `loomwright/scripts/*.sh` for a move onto the literal store name and requires exactly ONE hit —
# the line in §8 below. Keep the literal on that line, and never add another.
#
# The store's SCHEMA AUTHORITY is `docs/RESULT_SCHEMAS.md` §"VERIFY_ENV"; this writer conforms to it,
# never the reverse. The reader is `read-verify.sh` (advisory, fail-safe, never writes); the executor
# is `verify-env.sh` (the ONLY thing that runs the contract's shell strings — this writer never does).
#
# ---------------------------------------------------------------------------------------------
# WHY THE CONFIRM GATE (see AGENT_GUIDELINES.md §"Sole-writer confirm gates"):
#   `.agent/verify.json` lands in the TRACKED `.agent/` tree — no `.gitignore` entry covers it —
#   and is committed by design, so it falls on the COMMITTED side of the sole-writer rule and must
#   gate. As with `.agent/product.json`, do NOT re-derive that with `git ls-files` in THIS repo: the
#   plugin ships no store of its own, so the literal test answers "not tracked", the opposite of the
#   truth. Derive by DESTINATION.
#
# WHY THIS WRITER DOES NOT USE validate-entry.sh, DELIBERATELY (same reasoning as propose-product.sh):
#   the shared validator's blocking checks (contradiction / duplicate / provenance) are defined
#   against an APPEND-ONLY store of prose ENTRIES; this store is a SINGLE STRUCTURED OBJECT with no
#   second entry to duplicate or contradict. This writer validates SHAPE instead (VALIDATION below).
#   The confirm gate is unchanged and still required.
#
# ---------------------------------------------------------------------------------------------
# WHAT IS SCANNED, AND WHAT IS NEVER GUESSED. Every scan is READ-ONLY: files are opened for
# reading and NOTHING scanned is ever executed. Each candidate's SOURCE is printed in the proposal.
#   `start`     — scanned, first hit wins: playwright.config.* `webServer.command` →
#                 package.json scripts `dev`|`start`|`serve` (→ `npm run <name>`) →
#                 docker-compose*.yml present (→ `docker compose up -d`) → Makefile target
#                 `dev`|`start`|`serve` (→ `make <target>`). Nothing found ⇒ null (= already
#                 running), stated as such. Overridable with `--start`.
#   `base_url`  — scanned: playwright.config.* `baseURL` → playwright `webServer.url` → `.env*`
#                 `APP_URL`|`BASE_URL` → `.env*` `PORT` (→ `http://localhost:<PORT>`). Overridable
#                 with `--base-url`. NEVER DEFAULTED when nothing is found: `non_prod_assert.
#                 base_url_matches` is evaluated AGAINST this value by the executor, so a guessed
#                 localhost placeholder would let the non-prod gate pass against a URL the app is
#                 not actually at. The dry run prints BLOCKED; the write path refuses (exit 2).
#   `health`    — NOT scanned (no honest signal). Defaults to the root path `/` (a harmless default:
#                 the executor only ever polls it for 2xx). Overridable with `--health`.
#   `auth`      — NOT scanned. Defaults to `{method: "none", storage_state_path: null,
#                 probe_path: null}`. `--auth-method storage_state --storage-state-path <p>
#                 [--probe-path <r>]` sets the alternative.
#   `non_prod_assert` — NEVER scanned, NEVER guessed, and REQUIRED on the write path. This is the
#                 `--stance` analogue in propose-product.sh: no signal in a repo says what
#                 PRODUCTION looks like for this project (a `.env` with `NODE_ENV=development` says
#                 nothing about where `base_url` points), and a wrong guess here is a run that
#                 touches production. So without `--non-prod <regex|env=NAME=VAL|cmd=<shell>>` the
#                 proposal is printed with a BLOCKED line and the script exits 1 — on EVERY path,
#                 `--confirm` or not — and nothing is written. Repeatable; each value becomes one
#                 member:  `env=NAME=VAL` → env_var_equals {name, value};  `cmd=<shell>` → cmd;
#                 anything else → base_url_matches (an ERE).
#   `seed` / `reset` — scanned: package.json scripts `db:seed` / `db:reset` (→ `npm run <name>`)
#                 → prisma/seed* present (→ `npx prisma db seed`, seed only) → Makefile target
#                 `seed` / `reset`. Nothing found ⇒ null. Overridable with `--seed` / `--reset`.
#   `stop`      — scanned: docker-compose*.yml present (→ `docker compose down`); otherwise null
#                 (the executor kills the pid it recorded at start). Overridable with `--stop`.
#   `ready_timeout_s` — 60 unless `--ready-timeout-s <n>` (positive integer).
#   `notes`     — a provenance line (who proposed it, when, against which commit) so a reviewer can
#                 tell a scanned draft from a curated contract. Overridable with `--notes`.
#
# VALIDATION (shape only, run BEFORE the confirm gate so a malformed proposal is refused whether or
# not `--confirm` was passed):
#   V1  the built root is a JSON object
#   V2  every required key is PRESENT (jq `has()`): start, base_url, health, auth, non_prod_assert,
#       seed, reset, stop — the four nullable ones asserted by PRESENCE, never by `// default`
#   V3  `base_url` and `health` are non-empty strings
#   V4  `auth.method` ∈ {none, storage_state}; storage_state_path non-empty when storage_state
#   V5  `ready_timeout_s` is a positive number
#   V6  the built object is accepted by the READER (`read-verify.sh --store <tmp>`) — the writer
#       must never produce a file the reader would then refuse; this is the seam the two share
#   (`non_prod_assert` emptiness is NOT a shape failure — it is the §7 refusal, exit 1, see above.)
#
# REFUSALS (nothing is written in any of these):
#   - a non-primary checkout: the top-level `.git` is a FILE (a linked worktree OR a submodule) —
#     exit 3. From a worktree the write would diverge and be lost on `git worktree remove`; from a
#     submodule it would land in the wrong repository. Same guard propose-product.sh / add-rule.sh
#     carry.
#   - an EXISTING `.agent/verify.json` — exit 1. A bootstrap creates; it never edits.
#   - `jq` unavailable — exit 1 (a writer that cannot validate must refuse).
#   - no `--non-prod` — exit 1, on every path.
#   - any V1–V6 shape failure — exit 2.
#
# INJECTION SAFETY: every scanned or user-supplied value enters jq as a `--arg`. No value is ever
# interpolated into a shell command, eval'd, sourced or executed, and the jq program text is fixed.
#
# Usage:  propose-verify.sh [--repo <dir>] --non-prod <regex|env=NAME=VAL|cmd=<shell>> [...]
#                           [--start <sh>] [--base-url <url>] [--health <path|url>]
#                           [--auth-method none|storage_state] [--storage-state-path <p>]
#                           [--probe-path <r>] [--seed <sh>] [--reset <sh>] [--stop <sh>]
#                           [--ready-timeout-s <n>] [--notes <str>] [--confirm]
#   No `--confirm` and no interactive TTY  =>  PRINT the planned write, write NOTHING, exit 0.
#   `--confirm` (or an interactive TTY "y") + `--non-prod`  =>  write `<repo>/.agent/verify.json`.
#   `--repo <dir>` targets another checkout (tests use it to write under a `mktemp -d` project).
# Exit:  0 ok / dry-run · 1 refused (incl. missing --non-prod) · 2 shape validation failed ·
#        3 non-primary checkout

set -euo pipefail

PROG="propose-verify.sh"
die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit "${2:-1}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$SCRIPT_DIR/read-verify.sh"

# ---------------------------------------------------------------------------
# 1. Parse args.
# ---------------------------------------------------------------------------
repo_arg=""
start_arg="";  start_set=0
base_url_arg=""
health_arg=""
auth_method_arg="none"
storage_state_path_arg=""
probe_path_arg=""
seed_arg="";   seed_set=0
reset_arg="";  reset_set=0
stop_arg="";   stop_set=0
ready_timeout_arg="60"
notes_arg=""
non_prod_raw=""   # newline-TERMINATED accumulator; a newline inside a value is rejected at parse
                  # time (it would split one flag into two members — same reasoning as
                  # propose-product.sh's --competitor).
non_prod_count=0
confirm=0

need() { [ "$#" -ge 2 ] || die "$1 requires a value"; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)               need "$@"; repo_arg="$2"; shift 2 ;;
    --start)              need "$@"; start_arg="$2"; start_set=1; shift 2 ;;
    --base-url)           need "$@"; base_url_arg="$2"; shift 2 ;;
    --health)             need "$@"; health_arg="$2"; shift 2 ;;
    --auth-method)        need "$@"; auth_method_arg="$2"; shift 2 ;;
    --storage-state-path) need "$@"; storage_state_path_arg="$2"; shift 2 ;;
    --probe-path)         need "$@"; probe_path_arg="$2"; shift 2 ;;
    --seed)               need "$@"; seed_arg="$2"; seed_set=1; shift 2 ;;
    --reset)              need "$@"; reset_arg="$2"; reset_set=1; shift 2 ;;
    --stop)               need "$@"; stop_arg="$2"; stop_set=1; shift 2 ;;
    --ready-timeout-s)    need "$@"; ready_timeout_arg="$2"; shift 2 ;;
    --notes)              need "$@"; notes_arg="$2"; shift 2 ;;
    --non-prod)
      need "$@"
      case "$2" in
        "")      die "rejected: --non-prod may not be empty" ;;
        *$'\n'*) die "rejected: --non-prod may not contain newline characters" ;;
        env=*)
          nv="${2#env=}"
          case "$nv" in
            *=*) [ -n "${nv%%=*}" ] || die "rejected: --non-prod env=NAME=VAL has an empty NAME (got: $2)" ;;
            *)   die "rejected: --non-prod env= form must be env=NAME=VAL (got: $2)" ;;
          esac ;;
        cmd=*)   [ -n "${2#cmd=}" ] || die "rejected: --non-prod cmd= has an empty command" ;;
        *)       : ;;   # an ERE for base_url_matches
      esac
      non_prod_raw="${non_prod_raw}${2}"$'\n'; non_prod_count=$((non_prod_count+1)); shift 2 ;;
    --confirm)            confirm=1; shift ;;
    -h|--help)            grep -E '^# ' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *)                    die "unknown argument: $1 (see --help)" ;;
  esac
done

case "$auth_method_arg" in
  none|storage_state) : ;;
  *) die "rejected: --auth-method must be none or storage_state (got: $auth_method_arg)" ;;
esac
case "$ready_timeout_arg" in
  ''|*[!0-9]*|0) die "rejected: --ready-timeout-s must be a positive integer (got: $ready_timeout_arg)" ;;
esac

command -v jq >/dev/null 2>&1 \
  || die "jq is required but not available — this writer builds and shape-validates JSON with it, and a writer that cannot validate must refuse rather than write unchecked bytes"
[ -f "$READER" ] || die "read-verify.sh not found beside this script ($READER) — the writer validates its proposal through the reader and cannot proceed without it"

# ---------------------------------------------------------------------------
# 2. Resolve the target checkout, then the guards that can refuse before anything is scanned.
# ---------------------------------------------------------------------------
if [ -n "$repo_arg" ]; then
  [ -d "$repo_arg" ] || die "--repo is not a directory: $repo_arg"
  GITROOT="$(cd "$repo_arg" && pwd)"
else
  GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# ---- Worktree / submodule guard (same discriminator as propose-product.sh / add-rule.sh) ------
if [ -f "$GITROOT/.git" ]; then
  die "refusing to write from a non-primary checkout ($GITROOT) — its top-level \`.git\` is a FILE, which means either a linked git worktree or a git submodule. The verification contract is written only from the primary repo root: from a worktree the write would diverge and be lost on \`git worktree remove\`; from a submodule it would land in the wrong repository. Run this from the primary checkout (or point --repo at it)." 3
fi

STORE_DIR="$GITROOT/.agent"
STORE="$STORE_DIR/verify.json"

# ---- No-clobber guard. A bootstrap creates; it never edits. --------------------------------
if [ -e "$STORE" ]; then
  die "refusing to overwrite an existing verification contract at $STORE. This is a BOOTSTRAP, not an editor — clobbering it would destroy a curated contract (and the non-prod assertion in it). Edit the file directly (its shape is documented in docs/RESULT_SCHEMAS.md §VERIFY_ENV), or remove it first."
fi

# ---------------------------------------------------------------------------
# 3. SCAN (read-only). Each helper prints ONE candidate value and returns 0, or returns 1.
# ---------------------------------------------------------------------------
first_file() {   # first_file <glob-pattern> — the first matching file under GITROOT, or return 1
  local f
  for f in "$GITROOT"/$1; do
    [ -f "$f" ] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

scan_pkg_script() {   # scan_pkg_script <name>... — first package.json script among the names
  local f="$GITROOT/package.json" n
  [ -f "$f" ] || return 1
  for n in "$@"; do
    if jq -e --arg n "$n" 'type=="object" and (.scripts|type=="object") and (.scripts|has($n)) and (.scripts[$n]|type=="string") and (.scripts[$n]|length>0)' "$f" >/dev/null 2>&1; then
      printf 'npm run %s' "$n"; return 0
    fi
  done
  return 1
}

# scan_playwright <key> — `baseURL: '<v>'` / `command: '<v>'` / `url: '<v>'` from the first
# playwright.config.* found. A regex scan of a JS/TS file, not a parser: the first single- or
# double-quoted literal following `<key>:` wins. Good enough for a human-reviewed proposal.
scan_playwright() {
  local f v
  f="$(first_file 'playwright.config.*')" || return 1
  v="$(sed -n -E "s/^[[:space:]]*$1[[:space:]]*:[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p" "$f" 2>/dev/null | head -1 || true)"
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

# scan_env <VAR>... — first `VAR=value` among the names in .env, .env.local, .env.development,
# .env.example (in that order); quotes stripped, `export ` prefix tolerated.
scan_env() {
  local f n v
  for f in "$GITROOT/.env" "$GITROOT/.env.local" "$GITROOT/.env.development" "$GITROOT/.env.example"; do
    [ -f "$f" ] || continue
    for n in "$@"; do
      v="$(sed -n -E "s/^[[:space:]]*(export[[:space:]]+)?$n[[:space:]]*=[[:space:]]*['\"]?([^'\"#]*)['\"]?.*/\2/p" "$f" 2>/dev/null | head -1 || true)"
      v="$(printf '%s' "$v" | sed -E 's/[[:space:]]+$//')"
      [ -n "$v" ] && { printf '%s' "$v"; return 0; }
    done
  done
  return 1
}

scan_make_target() {   # scan_make_target <target>... — first Makefile target among the names
  local f="$GITROOT/Makefile" n
  [ -f "$f" ] || return 1
  for n in "$@"; do
    if grep -qE "^$n[[:space:]]*:" "$f" 2>/dev/null; then printf 'make %s' "$n"; return 0; fi
  done
  return 1
}

has_compose() { first_file 'docker-compose*.yml' >/dev/null 2>&1 || first_file 'docker-compose*.yaml' >/dev/null 2>&1 || first_file 'compose.y*ml' >/dev/null 2>&1; }
has_prisma_seed() { first_file 'prisma/seed*' >/dev/null 2>&1; }

# ---- start ----
start_is_null=0; start_src=""
if [ "$start_set" -eq 1 ]; then
  start="$start_arg"; start_src="--start (explicit)"
  [ -n "$start" ] || start_is_null=1
elif v="$(scan_playwright command)" && [ -n "$v" ]; then start="$v"; start_src="playwright.config webServer.command"
elif v="$(scan_pkg_script dev start serve)" && [ -n "$v" ]; then start="$v"; start_src="package.json scripts"
elif has_compose; then start="docker compose up -d"; start_src="docker-compose file present"
elif v="$(scan_make_target dev start serve)" && [ -n "$v" ]; then start="$v"; start_src="Makefile target"
else start=""; start_is_null=1; start_src="nothing found — proposing null (= already running)"
fi

# ---- base_url (never defaulted; see header) ----
base_url=""; base_url_src=""
if [ -n "$base_url_arg" ]; then base_url="$base_url_arg"; base_url_src="--base-url (explicit)"
elif v="$(scan_playwright baseURL)" && [ -n "$v" ]; then base_url="$v"; base_url_src="playwright.config baseURL"
elif v="$(scan_playwright url)" && [ -n "$v" ]; then base_url="$v"; base_url_src="playwright.config webServer.url"
elif v="$(scan_env APP_URL BASE_URL)" && [ -n "$v" ]; then base_url="$v"; base_url_src=".env* APP_URL/BASE_URL"
elif v="$(scan_env PORT)" && [ -n "$v" ]; then base_url="http://localhost:$v"; base_url_src=".env* PORT (localhost assumed — REVIEW)"
else base_url_src="NOT FOUND — supply --base-url; never defaulted (non_prod_assert is evaluated against it)"
fi

# ---- health ----
if [ -n "$health_arg" ]; then health="$health_arg"; health_src="--health (explicit)"
else health="/"; health_src="default root path — replace with a real health route"
fi

# ---- seed / reset ----
seed_is_null=0; seed_src=""
if [ "$seed_set" -eq 1 ]; then seed="$seed_arg"; seed_src="--seed (explicit)"; [ -n "$seed" ] || seed_is_null=1
elif v="$(scan_pkg_script db:seed seed)" && [ -n "$v" ]; then seed="$v"; seed_src="package.json scripts"
elif has_prisma_seed; then seed="npx prisma db seed"; seed_src="prisma/seed* present"
elif v="$(scan_make_target seed)" && [ -n "$v" ]; then seed="$v"; seed_src="Makefile target"
else seed=""; seed_is_null=1; seed_src="nothing found — proposing null"
fi
reset_is_null=0; reset_src=""
if [ "$reset_set" -eq 1 ]; then reset="$reset_arg"; reset_src="--reset (explicit)"; [ -n "$reset" ] || reset_is_null=1
elif v="$(scan_pkg_script db:reset reset)" && [ -n "$v" ]; then reset="$v"; reset_src="package.json scripts"
elif v="$(scan_make_target reset)" && [ -n "$v" ]; then reset="$v"; reset_src="Makefile target"
else reset=""; reset_is_null=1; reset_src="nothing found — proposing null"
fi

# ---- stop ----
stop_is_null=0; stop_src=""
if [ "$stop_set" -eq 1 ]; then stop="$stop_arg"; stop_src="--stop (explicit)"; [ -n "$stop" ] || stop_is_null=1
elif has_compose; then stop="docker compose down"; stop_src="docker-compose file present"
else stop=""; stop_is_null=1; stop_src="nothing found — proposing null (executor kills the recorded pid)"
fi

# Collapse any tab/newline/CR a scanned source may carry, so one field can never span lines.
flat() { printf '%s' "$1" | tr '\t\n\r' '   '; }
start="$(flat "$start")"; base_url="$(flat "$base_url")"; health="$(flat "$health")"
seed="$(flat "$seed")"; reset="$(flat "$reset")"; stop="$(flat "$stop")"

# ---------------------------------------------------------------------------
# 4. Provenance note.
# ---------------------------------------------------------------------------
written_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
head_sha="$(git -C "$GITROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
notes="${notes_arg:-proposed by propose-verify.sh at $written_at against $head_sha — scanned draft, review every field}"

# ---------------------------------------------------------------------------
# 5. Build the object with jq (every value passed as --arg — never interpolated).
#    non_prod_assert is built ONLY from --non-prod values; with none it is `{}` and §7 refuses.
# ---------------------------------------------------------------------------
non_prod_json='{}'
if [ -n "$non_prod_raw" ]; then
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$entry" in
      env=*)
        nv="${entry#env=}"
        non_prod_json="$(jq -c -n --argjson acc "$non_prod_json" --arg n "${nv%%=*}" --arg v "${nv#*=}" \
          '$acc + {env_var_equals: {name: $n, value: $v}}')" ;;
      cmd=*)
        non_prod_json="$(jq -c -n --argjson acc "$non_prod_json" --arg c "${entry#cmd=}" '$acc + {cmd: $c}')" ;;
      *)
        non_prod_json="$(jq -c -n --argjson acc "$non_prod_json" --arg r "$entry" '$acc + {base_url_matches: $r}')" ;;
    esac
  done <<EOF
$non_prod_raw
EOF
fi

new_obj="$(jq -c -n \
  --arg start "$start" --argjson start_null "$start_is_null" \
  --arg base_url "$base_url" \
  --arg health "$health" \
  --arg auth_method "$auth_method_arg" \
  --arg ssp "$storage_state_path_arg" \
  --arg probe "$probe_path_arg" \
  --argjson non_prod "$non_prod_json" \
  --arg seed "$seed" --argjson seed_null "$seed_is_null" \
  --arg reset "$reset" --argjson reset_null "$reset_is_null" \
  --arg stop "$stop" --argjson stop_null "$stop_is_null" \
  --argjson ready "$ready_timeout_arg" \
  --arg notes "$notes" \
  '{ start:    (if $start_null == 1 then null else $start end),
     base_url: $base_url,
     health:   $health,
     auth:     { method: $auth_method,
                 storage_state_path: (if $ssp == "" then null else $ssp end),
                 probe_path:         (if $probe == "" then null else $probe end) },
     non_prod_assert: $non_prod,
     seed:     (if $seed_null == 1 then null else $seed end),
     reset:    (if $reset_null == 1 then null else $reset end),
     stop:     (if $stop_null == 1 then null else $stop end),
     ready_timeout_s: $ready,
     notes:    $notes }')" \
  || die "failed to build the proposed verification contract"

# ---------------------------------------------------------------------------
# 6. VALIDATION (V1–V6). Shape only, BEFORE the confirm gate. V6 runs the proposal through the
#    READER, so the writer can never land a store the reader would refuse — with ONE deliberate
#    carve-out: an empty non_prod_assert is the §7 refusal (exit 1), not a shape failure, so the
#    reader's `non_prod_assert_empty` verdict is masked here and re-asserted in §7 by this script.
# ---------------------------------------------------------------------------
printf '%s' "$new_obj" | jq -e 'type == "object"' >/dev/null 2>&1 \
  || die "V1: the proposed store root is not a JSON object" 2

for k in start base_url health auth non_prod_assert seed reset stop; do
  printf '%s' "$new_obj" | jq -e --arg k "$k" 'has($k)' >/dev/null 2>&1 \
    || die "V2: required key \`$k\` is absent from the proposed store" 2
done

base_url_ok=1
printf '%s' "$new_obj" | jq -e '(.base_url|type=="string") and (.base_url|length>0)' >/dev/null 2>&1 || base_url_ok=0
printf '%s' "$new_obj" | jq -e '(.health|type=="string") and (.health|length>0)' >/dev/null 2>&1 \
  || die "V3: \`health\` must be a non-empty string" 2

printf '%s' "$new_obj" | jq -e '(.auth.method=="none") or ((.auth.method=="storage_state") and (.auth.storage_state_path|type=="string") and (.auth.storage_state_path|length>0))' >/dev/null 2>&1 \
  || die "V4: \`auth.method\` storage_state requires a non-empty --storage-state-path" 2

printf '%s' "$new_obj" | jq -e '(.ready_timeout_s|type=="number") and (.ready_timeout_s>0)' >/dev/null 2>&1 \
  || die "V5: \`ready_timeout_s\` must be a positive number" 2

# V6 — the reader must accept the proposal. Evaluated against a scratch copy OUTSIDE the target
# repo (mktemp's own dir), never against the store path; the reader's stderr is captured so a
# non-empty-non_prod_assert rejection can be told apart from the masked empty case.
v6_tmp="$(mktemp)" || die "could not allocate a scratch file for reader validation"
trap 'rm -f "$v6_tmp" 2>/dev/null' EXIT
printf '%s\n' "$new_obj" > "$v6_tmp"
v6_err="$(VERIFY_REPO_DIR="$(dirname "$v6_tmp")" bash "$READER" --store "$v6_tmp" 2>&1 >/dev/null || true)"
v6_out="$(VERIFY_REPO_DIR="$(dirname "$v6_tmp")" bash "$READER" --store "$v6_tmp" 2>/dev/null || true)"
if [ -z "$v6_out" ]; then
  v6_residual="$(printf '%s\n' "$v6_err" | grep -v 'non_prod_assert_empty' | grep -v 'type_invalid:base_url' || true)"
  [ -z "$v6_residual" ] \
    || die "V6: the reader (read-verify.sh) refuses the proposal — it must never be written in a shape the reader rejects: $v6_residual" 2
fi

# ---------------------------------------------------------------------------
# 7. Confirm-only gate + the two never-guessed refusals. The proposal is ALWAYS printed first, so a
#    first-time user sees what the scan found and what stands between it and a write.
# ---------------------------------------------------------------------------
proceed=0
if [ "$confirm" -eq 1 ]; then
  proceed=1
elif [ -t 0 ] && [ -t 1 ] && [ "$non_prod_count" -gt 0 ] && [ "$base_url_ok" -eq 1 ]; then
  printf 'Create the verification contract %s ?\n' "$STORE" >&2
  printf '%s\n' "$new_obj" >&2
  printf 'Confirm write? [y/N] ' >&2
  read -r reply || reply=""
  case "$reply" in y|Y|yes|YES) proceed=1 ;; *) proceed=0 ;; esac
fi

print_proposal() {
  printf 'PLANNED WRITE (not written — pass --confirm to apply):\n'
  printf '  target: %s\n' "$STORE"
  if [ "$non_prod_count" -eq 0 ]; then
    printf '  BLOCKED: --non-prod is REQUIRED before this can be written, and is never guessed. It is how verify-env.sh proves the target is NOT production before it runs anything, and no signal in a repo says what production looks like for this project. Re-run with --non-prod "<regex over base_url>" or --non-prod env=NAME=VAL (or cmd=<shell>).\n'
  fi
  if [ "$base_url_ok" -ne 1 ]; then
    printf '  BLOCKED: base_url could not be scanned and is never defaulted (non_prod_assert.base_url_matches is evaluated against it). Re-run with --base-url <url>.\n'
  fi
  printf '  start source: %s\n' "$start_src"
  printf '  base_url source: %s\n' "$base_url_src"
  printf '  health source: %s\n' "$health_src"
  printf '  auth: NOT scanned — method %s (use --auth-method / --storage-state-path / --probe-path)\n' "$auth_method_arg"
  printf '  non_prod_assert: NEVER scanned — %s member(s) supplied via --non-prod\n' "$non_prod_count"
  printf '  seed source: %s\n' "$seed_src"
  printf '  reset source: %s\n' "$reset_src"
  printf '  stop source: %s\n' "$stop_src"
  printf '  object: %s\n' "$new_obj"
}

if [ "$non_prod_count" -eq 0 ]; then
  print_proposal
  die "refused: --non-prod was not supplied, and it is never guessed. Nothing was written. (See the BLOCKED line above.)" 1
fi

if [ "$proceed" -ne 1 ]; then
  print_proposal
  exit 0
fi

if [ "$base_url_ok" -ne 1 ]; then
  print_proposal
  die "V3: \`base_url\` could not be scanned and is never defaulted — supply --base-url. Nothing was written." 2
fi

# ---------------------------------------------------------------------------
# 8. Write: temp file in the SAME directory, then an atomic move onto the store. Nothing outside
#    the store is written (the containing `.agent/` directory is created when absent, and the temp
#    file exists only until the move). This is the ONE write path — the sole-writer grep in
#    test-verify-seam.sh counts it.
# ---------------------------------------------------------------------------
mkdir -p "$STORE_DIR" || die "could not create the store directory: $STORE_DIR"

tmp="$(mktemp "$STORE_DIR/.propose-verify.XXXXXX")" || die "could not allocate a temp file in $STORE_DIR"
trap 'rm -f "$tmp" "$v6_tmp" 2>/dev/null' EXIT

printf '%s\n' "$new_obj" | jq . > "$tmp" || die "failed to stage the verification contract (nothing written to $STORE)"
mv -f "$tmp" "$STORE_DIR/verify.json" || die "atomic move failed (nothing written to $STORE)"

# ---------------------------------------------------------------------------
# 9. Read-back verify THROUGH THE READER: the written file must come back as a validated object
#    carrying the non_prod_assert we were given.
# ---------------------------------------------------------------------------
back="$(VERIFY_REPO_DIR="$GITROOT" bash "$READER" --store "$STORE" 2>/dev/null || true)"
[ -n "$back" ] || die "read-back verify failed: read-verify.sh does not accept the written store: $STORE"
printf '%s' "$back" | jq -e --argjson n "$non_prod_json" '.non_prod_assert == $n' >/dev/null 2>&1 \
  || die "read-back verify failed: the written store's \`non_prod_assert\` is not the supplied value: $STORE"

printf 'wrote verification contract to %s (non_prod_assert members: %s)\n' "$STORE" "$non_prod_count"
printf 'Next: review every field by hand — start/seed/reset/stop are SHELL STRINGS verify-env.sh will run, and health/auth were not scanned. Read it back with read-verify.sh.\n'
exit 0
