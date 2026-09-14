#!/usr/bin/env bash
# verify-env.sh — EXECUTOR for the committed `.agent/verify.json` verification-environment contract.
# The ONLY surface in the plugin that RUNS the contract's shell strings (`start`, `stop`, `seed`,
# `reset`, `non_prod_assert.cmd`); the reader (read-verify.sh) and the bootstrap (propose-verify.sh)
# never do. Schema authority: docs/RESULT_SCHEMAS.md §"VERIFY_ENV" — this executor conforms to it.
#
# Usage:  verify-env.sh <subcommand> [--store <file>] [--repo <dir>] [--state-dir <dir>]
#                                    [--ready-timeout-s <n> | --health-timeout <n>]
#   assert-non-prod   evaluate `non_prod_assert`; exit 0 only if ≥1 usable member PASSES
#   start             run `start` (if non-null) in the background, poll `health` until 2xx or the
#                     deadline (`ready_timeout_s` is WALL-CLOCK seconds, not an iteration count);
#                     on timeout run `stop` and exit non-zero [health_timeout]. Refuses when the
#                     pid recorded by a previous `start` is still alive [already_started] (a stale
#                     record whose process is gone is cleared, never refused). A start string that
#                     exits NON-zero before health is trusted (a 1s grace follows the first 2xx) is a
#                     failure [start_exited:<rc>] — the pid record is dropped and `stop` runs; one
#                     that exits 0 is a detached starter
#                     (e.g. `docker compose up -d`): its pid record is dropped and polling continues
#   stop              run `stop` (if non-null), else kill the pid recorded by `start` and WAIT for it
#                     to exit (SIGTERM, then SIGKILL). A recorded pid that was not running is exit
#                     non-zero [not_running] (nothing was stopped — the record is cleared); one that
#                     survives both signals is [stop_failed]. No record at all is a contract no-op
#   seed | reset      run the string (null ⇒ nothing to do, exit 0)
#   auth-probe        GET `auth.probe_path` with the storage-state cookies; print
#                     `authenticated` (2xx) or `anonymous` (401/403/302); `method: none` ⇒ print
#                     `anonymous` without a request
#   env overrides (tests): VERIFY_STORE / VERIFY_REPO_DIR (forwarded to the reader) /
#                          VERIFY_STATE_DIR / VERIFY_READY_TIMEOUT_S. Precedence: flags > env > store.
#
# THE NON-PROD GATE IS THE POINT OF THIS FILE'S SHAPE (fail CLOSED):
#   * EVERY subcommand calls `gate_non_prod` FIRST, in the SAME process, before anything else. A
#     store whose `non_prod_assert` has no usable member is refused [non_prod_assert_empty]; one
#     whose members all fail is refused [non_prod_assert_failed]. Nothing is persisted between
#     invocations — a pass in a previous run buys the next run nothing.
#   * Contract STEPS reach `bash -c` at exactly two sites — `run_step` (stop/seed/reset, foreground)
#     and `do_start`'s background launch — and BOTH re-check the in-process flag themselves: if the
#     gate did not pass in THIS invocation they refuse with [non_prod_not_asserted] and run nothing
#     (belt-and-suspenders — test-verify-seam.sh's AC9 mutation control deletes the dispatch-level
#     gate call from a COPY and proves the inner check still refuses).
#   * The single deliberate exception is `non_prod_assert.cmd`, which IS the assertion: it runs
#     (via `run_assert_cmd`) as part of evaluating the gate, exactly as the schema states
#     ("a shell string; exit 0 = pass").
#
# LOADS THROUGH THE READER, NEVER RE-PARSES: the contract is obtained from the sibling
# `read-verify.sh` (located relative to this file's own directory — a vendor-neutral core script,
# never a harness install path). Empty reader stdout ⇒ [verify_store_unreadable], with the reader's
# stderr forwarded VERBATIM so its reason token (e.g. [non_prod_assert_empty],
# [required_key_missing:seed], [store_absent]) is the reason this executor reports.
#
# TRUST SURFACE: the strings run with the caller's full shell privileges — trusted exactly like
# `package.json` scripts. Never run this against a store you have not read.
#
# NEVER WRITES `.agent/verify.json` (sole writer: propose-verify.sh). Its only writes are under the
# state dir (default `<repo>/.supervisor/verify/env/`): the recorded pid and the start log.
#
# Portability: bash 3.2 / BSD userland — no `timeout`, no `setsid`, polling is `while`/`sleep 1`
# against a `date +%s` deadline. `curl` is invoked by name so a test can PATH-stub it.
#
# LIFECYCLE VERDICTS ARE NEVER VACUOUS: a subcommand exits 0 only when the guarantee its name
# promises actually held in THIS invocation — `start` only with the launched child alive (or a
# detached starter) AND health 2xx; `stop` only when something recorded was actually stopped, or
# nothing was recorded. "Recorded pid was not running" is a failure, not a success.
#
# Exit: 0 = ok | 1 = gate refusal / step failure / health_timeout / probe failure
#       2 = usage | 3 = contract unreadable (reader empty, reader missing, jq missing)

set -uo pipefail   # no `set -e`: every failure path names its reason and chooses its exit code.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$SCRIPT_DIR/read-verify.sh"

diag() { echo "verify-env: $1" >&2; }
usage() {
  echo "usage: verify-env.sh <assert-non-prod|start|stop|seed|reset|auth-probe> [--store <file>] [--repo <dir>] [--state-dir <dir>] [--ready-timeout-s <n>]" >&2
}

# ---------------------------------------------------------------------------
# 1. Arguments.
# ---------------------------------------------------------------------------
SUB=""
store_arg=""; repo_arg=""; state_arg=""; timeout_arg=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    assert-non-prod|start|stop|seed|reset|auth-probe)
      if [ -n "$SUB" ]; then diag "more than one subcommand given [usage]"; usage; exit 2; fi
      SUB="$1"; shift ;;
    --store)     [ "$#" -ge 2 ] || { diag "--store needs a value [usage]"; exit 2; }; store_arg="$2"; shift 2 ;;
    --repo)      [ "$#" -ge 2 ] || { diag "--repo needs a value [usage]"; exit 2; };  repo_arg="$2";  shift 2 ;;
    --state-dir) [ "$#" -ge 2 ] || { diag "--state-dir needs a value [usage]"; exit 2; }; state_arg="$2"; shift 2 ;;
    --ready-timeout-s|--health-timeout)
                 [ "$#" -ge 2 ] || { diag "$1 needs a value [usage]"; exit 2; }; timeout_arg="$2"; shift 2 ;;
    -h|--help)   usage; exit 2 ;;
    *)           diag "unknown argument: $1 [usage]"; usage; exit 2 ;;
  esac
done
if [ -z "$SUB" ]; then diag "no subcommand given [usage]"; usage; exit 2; fi

# Positive-integer check for a timeout override (fail CLOSED: a malformed override is a usage error,
# never silently the default).
timeout_arg="${timeout_arg:-${VERIFY_READY_TIMEOUT_S:-}}"
if [ -n "$timeout_arg" ]; then
  case "$timeout_arg" in
    ''|*[!0-9]*) diag "ready timeout must be a positive integer, got '$timeout_arg' [usage]"; exit 2 ;;
    0)           diag "ready timeout must be a positive integer, got 0 [usage]"; exit 2 ;;
  esac
fi

# ---------------------------------------------------------------------------
# 2. Tooling + reader presence.
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  diag "jq unavailable — cannot load the verification contract [jq_unavailable] [verify_store_unreadable]"
  exit 3
fi
if [ ! -f "$READER" ]; then
  diag "sibling reader not found at $READER [reader_missing] [verify_store_unreadable]"
  exit 3
fi

REPO_DIR="${repo_arg:-${VERIFY_REPO_DIR:-}}"
if [ -z "$REPO_DIR" ]; then
  REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
STATE_DIR="${state_arg:-${VERIFY_STATE_DIR:-$REPO_DIR/.supervisor/verify/env}}"

# ---------------------------------------------------------------------------
# 3. Load the contract THROUGH the reader. Never re-parse the store. Forward the reader's stderr
#    verbatim so its reason token is ours.
# ---------------------------------------------------------------------------
reader_err="$(mktemp "${TMPDIR:-/tmp}/verify-env-reader.XXXXXX")" || { diag "mktemp failed [verify_store_unreadable]"; exit 3; }
trap 'rm -f "$reader_err" 2>/dev/null' EXIT
reader_args=()
[ -n "$store_arg" ] && reader_args+=(--store "$store_arg")
[ -n "$repo_arg" ]  && reader_args+=(--repo "$repo_arg")
if [ "${#reader_args[@]}" -gt 0 ]; then
  CONTRACT="$(bash "$READER" "${reader_args[@]}" 2>"$reader_err")"
else
  CONTRACT="$(bash "$READER" 2>"$reader_err")"
fi
if [ -z "$CONTRACT" ]; then
  # Forward every reader line first (they carry the bracketed reason tokens), then our own verdict.
  cat "$reader_err" >&2
  if grep -qF "[store_absent]" "$reader_err" 2>/dev/null; then
    diag "no .agent/verify.json — create one with propose-verify.sh (propose-only, --confirm-gated, requires --non-prod). Stopping before the app is touched [verify_store_unreadable]"
  else
    # The reader's bracketed reason token(s) become THIS executor's reason, verbatim — never a
    # re-parse, never a token of our own invention (AC3: `{"non_prod_assert":{}}` reports
    # non_prod_assert_empty).
    reader_tokens="$(grep -oE '\[[A-Za-z0-9_.:-]+\]' "$reader_err" 2>/dev/null | tr '\n' ' ')"
    diag "the reader emitted no contract — refusing to run anything; reader reason: ${reader_tokens:-(none)}[verify_store_unreadable]"
  fi
  exit 3
fi

field() { printf '%s' "$CONTRACT" | jq -r "$1"; }
# Nullable-required keys: PRESENCE was already asserted by the reader (jq has()), so at this level
# `null` and absent cannot be confused — null simply means "nothing to run here".
C_START="$(field 'if .start == null then "" else .start end')"
C_STOP="$(field 'if .stop == null then "" else .stop end')"
C_SEED="$(field 'if .seed == null then "" else .seed end')"
C_RESET="$(field 'if .reset == null then "" else .reset end')"
C_BASE_URL="$(field '.base_url')"
C_HEALTH="$(field '.health')"
C_AUTH_METHOD="$(field '.auth.method')"
C_STORAGE="$(field 'if .auth.storage_state_path == null then "" else .auth.storage_state_path end')"
C_PROBE="$(field 'if (.auth | has("probe_path")) and .auth.probe_path != null then .auth.probe_path else "" end')"
C_TIMEOUT="$(field 'if has("ready_timeout_s") then (.ready_timeout_s | floor | tostring) else "60" end')"
READY_TIMEOUT_S="${timeout_arg:-$C_TIMEOUT}"
case "$READY_TIMEOUT_S" in ''|*[!0-9]*|0) READY_TIMEOUT_S=60 ;; esac

# ---------------------------------------------------------------------------
# 4. The non-prod gate. In-process flag only; NOTHING is persisted.
# ---------------------------------------------------------------------------
NON_PROD_ASSERTED=0

# run_assert_cmd <string> — the ONE deliberate pre-gate `bash -c`: `non_prod_assert.cmd` IS the
# assertion (exit 0 = pass). Runs in the repo dir with stdin closed.
run_assert_cmd() {
  ( cd "$REPO_DIR" 2>/dev/null || exit 1; bash -c "$1" </dev/null >/dev/null 2>&1 )
}

assert_non_prod() {
  local passed=0 evaluated=0 re name value actual cmd
  # The reader already refused a store with no usable member, so reaching here with none is a
  # reader/executor drift — still fail CLOSED with the same token.
  if [ "$(field '.non_prod_assert | (has("base_url_matches") or has("env_var_equals") or has("cmd"))')" != "true" ]; then
    diag "non_prod_assert has no usable member [non_prod_assert_empty]"
    return 1
  fi
  if [ "$(field '.non_prod_assert | has("base_url_matches")')" = "true" ]; then
    evaluated=$((evaluated+1))
    re="$(field '.non_prod_assert.base_url_matches')"
    if grep -Eq -- "$re" <<<"$C_BASE_URL"; then
      diag "non_prod_assert.base_url_matches: '$re' matches base_url '$C_BASE_URL' — PASS"
      passed=$((passed+1))
    else
      diag "non_prod_assert.base_url_matches: '$re' does NOT match base_url '$C_BASE_URL' — fail"
    fi
  fi
  if [ "$(field '.non_prod_assert | has("env_var_equals")')" = "true" ]; then
    evaluated=$((evaluated+1))
    name="$(field '.non_prod_assert.env_var_equals.name')"
    value="$(field '.non_prod_assert.env_var_equals.value')"
    case "$name" in
      *[!A-Za-z0-9_]*|[0-9]*|'')
        diag "non_prod_assert.env_var_equals: '$name' is not a valid environment variable name — fail" ;;
      *)
        if [ -n "${!name+x}" ]; then
          actual="${!name}"
          if [ "$actual" = "$value" ]; then
            diag "non_prod_assert.env_var_equals: \$$name equals '$value' — PASS"
            passed=$((passed+1))
          else
            diag "non_prod_assert.env_var_equals: \$$name is '$actual', expected '$value' — fail"
          fi
        else
          diag "non_prod_assert.env_var_equals: \$$name is unset — fail"
        fi ;;
    esac
  fi
  if [ "$(field '.non_prod_assert | has("cmd")')" = "true" ]; then
    evaluated=$((evaluated+1))
    cmd="$(field '.non_prod_assert.cmd')"
    if run_assert_cmd "$cmd"; then
      diag "non_prod_assert.cmd exited 0 — PASS"
      passed=$((passed+1))
    else
      diag "non_prod_assert.cmd exited non-zero — fail"
    fi
  fi
  if [ "$passed" -ge 1 ]; then
    diag "non-prod asserted ($passed of $evaluated member(s) passed)"
    NON_PROD_ASSERTED=1
    return 0
  fi
  diag "every non_prod_assert member failed ($evaluated evaluated) — this target could be production; refusing [non_prod_assert_failed]"
  return 1
}

# gate_non_prod — called FIRST by every subcommand. Exits the process on refusal.
gate_non_prod() {
  assert_non_prod || exit 1
}

# run_step <label> <string> — the foreground site that runs a contract STEP via `bash -c` (the other
# is do_start's background launch). Refuses unless the gate passed in THIS process.
run_step() {
  local label="$1" str="$2" rc
  if [ "$NON_PROD_ASSERTED" -ne 1 ]; then
    diag "refusing to run '$label': non-prod was not asserted in this invocation [non_prod_not_asserted]"
    exit 1
  fi
  diag "running $label"
  ( cd "$REPO_DIR" 2>/dev/null || exit 1; bash -c "$str" </dev/null ); rc=$?
  if [ "$rc" -ne 0 ]; then
    diag "$label exited $rc [step_failed:$label]"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 5. Subcommand bodies.
# ---------------------------------------------------------------------------
health_url() {
  case "$C_HEALTH" in
    http://*|https://*) printf '%s' "$C_HEALTH" ;;
    *) printf '%s/%s' "${C_BASE_URL%/}" "${C_HEALTH#/}" ;;
  esac
}
probe_url() {
  case "$C_PROBE" in
    http://*|https://*) printf '%s' "$C_PROBE" ;;
    *) printf '%s/%s' "${C_BASE_URL%/}" "${C_PROBE#/}" ;;
  esac
}

# pid_alive <pid> — true while the process exists (kill -0). A pid reaped by us (the launched
# child) fails this as soon as bash has collected it — verified on bash 3.2.
pid_alive() { kill -0 "$1" 2>/dev/null; }

do_stop() {
  local pidf="$STATE_DIR/pid" pid i
  if [ -n "$C_STOP" ]; then
    run_step stop "$C_STOP" || return 1
    rm -f "$pidf" 2>/dev/null
    return 0
  fi
  if [ -f "$pidf" ]; then
    pid="$(cat "$pidf" 2>/dev/null)"
    case "$pid" in
      ''|*[!0-9]*) diag "recorded pid file is not numeric — nothing killed [pid_unreadable]"; rm -f "$pidf"; return 1 ;;
    esac
    if ! pid_alive "$pid"; then
      # Nothing was stopped: the guarantee did not hold, so this is NOT a success. The dead record
      # is cleared so the next start/stop is not confused by it (and so a reused pid is never killed).
      diag "stop is null — recorded pid $pid was not running; nothing was stopped (stale record cleared) [not_running]"
      rm -f "$pidf" 2>/dev/null
      return 1
    fi
    kill "$pid" 2>/dev/null
    i=0
    while [ "$i" -lt 5 ] && pid_alive "$pid"; do sleep 1; i=$((i+1)); done
    if pid_alive "$pid"; then
      diag "stop is null — pid $pid ignored SIGTERM for 5s, sending SIGKILL"
      kill -9 "$pid" 2>/dev/null
      i=0
      while [ "$i" -lt 5 ] && pid_alive "$pid"; do sleep 1; i=$((i+1)); done
    fi
    if pid_alive "$pid"; then
      diag "stop is null — recorded pid $pid is STILL running after SIGTERM and SIGKILL; record kept [stop_failed]"
      return 1
    fi
    diag "stop is null — killed recorded pid $pid (confirmed gone)"
    rm -f "$pidf" 2>/dev/null
    return 0
  fi
  diag "stop is null and no pid was recorded — nothing to stop"
  return 0
}

# check_start_child — inspects the child launched by do_start (dynamic scope: reads/writes its
# `child` and `pidf`). Alive ⇒ nothing. Exited NON-zero ⇒ the start failed [start_exited:<rc>]:
# record dropped, `stop` run, exit 1. Exited 0 ⇒ a detached starter (`docker compose up -d`): the
# record is dropped (a dead pid must never be kept — `stop` would kill whatever reused it) and
# `child` is cleared so health polling continues without it.
check_start_child() {
  local crc
  [ -n "$child" ] || return 0
  pid_alive "$child" && return 0
  wait "$child" 2>/dev/null; crc=$?
  if [ "$crc" -ne 0 ]; then
    diag "start exited $crc before health was trusted (see $STATE_DIR/start.log) — running stop [start_exited:$crc]"
    rm -f "$pidf" 2>/dev/null
    do_stop || diag "stop after start failure also failed"
    exit 1
  fi
  diag "start exited 0 — treating it as a detached starter; its pid record is dropped (stop: null cannot kill what it did not keep) [start_detached]"
  rm -f "$pidf" 2>/dev/null
  child=""
  return 0
}

do_start() {
  local url child="" deadline started_at now pidf="$STATE_DIR/pid" prev
  mkdir -p "$STATE_DIR" 2>/dev/null || { diag "cannot create state dir $STATE_DIR [state_dir_unwritable]"; exit 1; }
  if [ -n "$C_START" ]; then
    if [ "$NON_PROD_ASSERTED" -ne 1 ]; then
      diag "refusing to run 'start': non-prod was not asserted in this invocation [non_prod_not_asserted]"
      exit 1
    fi
    # Replay guard: a second start while the recorded instance is alive would launch a second
    # process (typically dying on bind), overwrite the record, and let health — served by the FIRST
    # instance — report `ready`; the later `stop` would then miss the real server. Refuse instead.
    # A stale record (process gone) is NOT a refusal: a legitimate re-start after a crash or an
    # unclean exit must work, so the dead record is cleared and the start proceeds.
    if [ -f "$pidf" ]; then
      prev="$(cat "$pidf" 2>/dev/null)"
      case "$prev" in
        ''|*[!0-9]*) diag "recorded pid file is not numeric — clearing the unreadable record before start [stale_pid_cleared]"; rm -f "$pidf" 2>/dev/null ;;
        *) if pid_alive "$prev"; then
             diag "start refused: the app is already running as recorded pid $prev — run stop first [already_started]"
             exit 1
           fi
           diag "recorded pid $prev is no longer running — clearing the stale record before start [stale_pid_cleared]"
           rm -f "$pidf" 2>/dev/null ;;
      esac
    fi
    diag "running start in the background (log: $STATE_DIR/start.log)"
    # Detach stdio from ours so a caller capturing our stdout is not held open by the child.
    ( cd "$REPO_DIR" 2>/dev/null || exit 1; exec bash -c "$C_START" </dev/null >"$STATE_DIR/start.log" 2>&1 ) &
    child="$!"
    printf '%s\n' "$child" > "$pidf"
  else
    diag "start is null — assuming the app is already running"
    rm -f "$pidf" 2>/dev/null
  fi
  url="$(health_url)"
  diag "polling $url for 2xx (ready_timeout_s=$READY_TIMEOUT_S, wall-clock)"
  started_at="$(date +%s)"
  deadline=$((started_at + READY_TIMEOUT_S))
  while :; do
    # The launched child is inspected BEFORE health is trusted: a 2xx served by some OTHER process
    # while our own start string has already died is not "ready", it is a start that failed.
    check_start_child
    if curl -fsS -o /dev/null --max-time 2 "$url" 2>/dev/null; then
      if [ -n "$child" ]; then
        # Grace re-check: a child that dies on bind does so a few ms AFTER launch, i.e. possibly
        # after this first 2xx (served by an instance we did not start). One second closes that
        # window; a child still alive after it is trusted.
        sleep 1
        check_start_child
      fi
      now="$(date +%s)"
      diag "healthy after $((now - started_at))s"
      echo "ready"
      return 0
    fi
    now="$(date +%s)"
    [ "$now" -lt "$deadline" ] || break
    sleep 1
  done
  diag "health never answered 2xx within ${READY_TIMEOUT_S}s — running stop [health_timeout]"
  do_stop || diag "stop after health timeout also failed"
  exit 1
}

do_auth_probe() {
  local url cookie code
  if [ "$C_AUTH_METHOD" = "none" ]; then
    diag "auth.method is none — no request made"
    echo "anonymous"
    return 0
  fi
  if [ -z "$C_PROBE" ]; then
    diag "auth.probe_path is not set — nothing to probe [auth_probe_path_missing]"
    return 1
  fi
  local ss="$C_STORAGE"
  case "$ss" in /*) ;; *) ss="$REPO_DIR/$ss" ;; esac
  if [ ! -f "$ss" ]; then
    diag "auth.storage_state_path '$ss' does not exist [storage_state_absent]"
    return 1
  fi
  cookie="$(jq -r '[.cookies[]? | "\(.name)=\(.value)"] | join("; ")' "$ss" 2>/dev/null)" || cookie=""
  if [ -z "$cookie" ]; then
    diag "storage state carries no cookies — probing anonymously [storage_state_no_cookies]"
  fi
  url="$(probe_url)"
  # No -L: a 302 to the login page is the anonymous signal, so redirects must be observed, not followed.
  if [ -n "$cookie" ]; then
    code="$(curl -sS -o /dev/null --max-time 10 -w '%{http_code}' -H "Cookie: $cookie" "$url" 2>/dev/null)" || code=""
  else
    code="$(curl -sS -o /dev/null --max-time 10 -w '%{http_code}' "$url" 2>/dev/null)" || code=""
  fi
  case "$code" in
    2[0-9][0-9]) diag "probe $url answered $code"; echo "authenticated"; return 0 ;;
    401|403|302) diag "probe $url answered $code"; echo "anonymous"; return 0 ;;
    '')          diag "probe $url made no HTTP response [auth_probe_unreachable]"; return 1 ;;
    *)           diag "probe $url answered $code — neither authenticated nor anonymous [auth_probe_unexpected:$code]"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# 6. Dispatch. gate_non_prod is the FIRST statement of every arm.
# ---------------------------------------------------------------------------
case "$SUB" in
  assert-non-prod) gate_non_prod; echo "non-prod asserted"; exit 0 ;;
  start)           gate_non_prod; do_start; exit $? ;;
  stop)            gate_non_prod; do_stop; exit $? ;;
  seed)            gate_non_prod; if [ -z "$C_SEED" ]; then diag "seed is null — nothing to seed"; exit 0; fi; run_step seed "$C_SEED"; exit $? ;;
  reset)           gate_non_prod; if [ -z "$C_RESET" ]; then diag "reset is null — nothing to reset"; exit 0; fi; run_step reset "$C_RESET"; exit $? ;;
  auth-probe)      gate_non_prod; do_auth_probe; exit $? ;;
esac
diag "unreachable dispatch for '$SUB' [usage]"
exit 2
