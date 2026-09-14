#!/usr/bin/env bash
# read-verify.sh — fail-safe ADVISORY reader for the committed `.agent/verify.json` verification-
# environment contract (how the app under test is started / health-checked / authenticated / seeded /
# reset, and how the plugin can prove the target is NOT production).
# Parity with read-product.sh and the rest of the read-*.sh advisory-reader family. Pure-READ, NO side
# effects, NO network, NEVER writes the store — and, load-bearing for this store in particular, NEVER
# EXECUTES ANY OF THE SHELL STRINGS IT READS (see TRUST SURFACE below).
#
# The store's SCHEMA AUTHORITY is `docs/RESULT_SCHEMAS.md` §"VERIFY_ENV"; this reader conforms to it,
# never the reverse. The store is created per-project by the bootstrap (`propose-verify.sh`), never by
# this reader. The only thing that RUNS the contract is the executor (`verify-env.sh`), which loads it
# through this reader and never re-parses the file.
#
# STORED FIELDS (all top-level keys of a single JSON OBJECT):
#   start            (string|null)  shell string that starts the app; null = already running
#   base_url         (string)       the URL the app under test is reached at
#   health           (string)       a path (relative to base_url) or a full URL that must answer 2xx
#   auth             (object)       method: "none" | "storage_state";
#                                   storage_state_path (string, REQUIRED non-empty when method is
#                                   storage_state; may be null/absent for method none);
#                                   probe_path (string|null, optional — a route that 401/302s when
#                                   logged out; the executor's auth-probe target)
#   non_prod_assert  (object)       AT LEAST ONE USABLE MEMBER of: base_url_matches (non-empty string,
#                                   an ERE tested against base_url) / env_var_equals ({name, value},
#                                   both strings; name a POSIX identifier `[A-Za-z_][A-Za-z0-9_]*`)
#                                   / cmd (non-empty shell string; exit 0 = pass). A member that is
#                                   present but of the wrong TYPE is MALFORMED (the executor fails
#                                   CLOSED, so a half-typed member must not silently disappear). A
#                                   well-typed env_var_equals whose `name` is NOT an identifier is an
#                                   UNUSABLE member (the executor cannot look it up, so it can only
#                                   ever fail): it is named on stderr `[env_var_name_invalid:<name>]`
#                                   as an ADVISORY line and does not count as usable — the store is
#                                   MALFORMED only if NO usable member remains. NO usable member ⇒
#                                   MALFORMED with the reason token `non_prod_assert_empty`.
#   seed             (string|null)  shell string that seeds the app; null = nothing to seed
#   reset            (string|null)  shell string that resets state; null = nothing to reset
#   stop             (string|null)  shell string that stops the app; null = executor kills the pid it
#                                   recorded at start (or nothing, if start was null)
#   ready_timeout_s  (number)       OPTIONAL — seconds the executor polls health after start; the
#                                   DEFAULT (60) is applied by the executor, never by this reader.
#                                   Present but not a positive number ⇒ MALFORMED.
#   notes            (any)          OPTIONAL — free-form, passed through untouched.
#
# NULLABLE-REQUIRED KEYS — the distinction this reader exists to preserve:
#   `start`, `seed`, `reset` and `stop` are REQUIRED keys whose value MAY be `null`. Those are two
#   different facts:
#       key present, value null   -> "nothing to run here"       (a legitimate, complete contract)
#       key ABSENT                -> MALFORMED (an INCOMPLETE contract — the author never decided)
#   Presence is therefore asserted with jq `has("<key>")`, NEVER with `.<key> // empty` or any other
#   `//` default — a `//` default silently collapses a legitimate `null` into the missing-key case
#   and the two become indistinguishable. (That exact defect shipped once before in read-rules.sh's
#   `check` field and was missed by both a review and a full-marks rubric; test-verify-seam.sh's
#   mutation control deletes the `has("seed")` guard from a COPY of this file and asserts the
#   missing-`seed` case then passes for the wrong reason.)
#
# STRICT, NOT DEMOTE-NEVER-CRASH: unlike read-product.sh, which degrades an odd field to `unset` and
# emits the rest, THIS reader treats every shape defect as MALFORMED (empty stdout). The difference is
# deliberate: product context is prose a human reads, and a partial block is still useful; a
# verification contract is INPUT TO AN EXECUTOR that will start, seed and reset a live app, and a
# partially-valid contract handed to it is exactly the class of input the non-prod gate exists to
# refuse. Fail SAFE on the read (exit 0, nothing on stdout), so the executor fails CLOSED on the run.
#
# FAIL-SAFE (hard requirement): ALWAYS exit 0 — a read must never break its caller. In EVERY degraded
# case the reader emits NOTHING ON STDOUT, names the reason ON STDERR, and exits 0. The invariant is a
# RULE, not a count: NO path may reach `exit 0` with an empty stdout without having called `diag`
# first. The live set of reasons is what `grep -n 'diag "read-verify:' $0` plus the MALFORMED lines of
# JQ_PROG print — read it from the code, never from a count kept by hand. Every MALFORMED diagnostic
# ends with a stable, grep-able REASON TOKEN in brackets (e.g. `[required_key_missing:seed]`,
# `[non_prod_assert_empty]`) so a consumer — the executor in particular — can forward the reason
# verbatim instead of inventing its own.
#
# ABSENCE IS NOT THIS READER'S TO ANNOUNCE. An absent store is named on stderr and nothing more; it is
# the CONSUMER seam (`/verify`, the executor) that must say, loudly, that `.agent/verify.json` is
# missing, name the bootstrap, and STOP before the app is touched.
#
# TRUST SURFACE — READ THIS BEFORE EXTENDING THE READER: `start`, `stop`, `seed`, `reset` and
# `non_prod_assert.cmd` are arbitrary shell, committed by the project, and the executor runs them via
# `bash -c` with the caller's full privileges — trusted exactly like `package.json` scripts. This
# reader is the boundary that guarantees READING a store has no such effect: no value read from the
# store is ever executed, eval'd, sourced, `bash -c`'d, or passed to a command as anything but data.
# The store enters jq ONLY on jq's stdin via a `< "$STORE"` redirect (so the path is never shell-
# interpreted, never jq short options, and the content never reaches program text); the jq program
# text is fixed; nothing from the store is interpolated anywhere.
#
# INPUT CONTRACT (no-hang): this reader NEVER reads its own stdin.
#
# Usage:  read-verify.sh [--store <file>] [--repo <dir>]
#         defaults: repo = cwd git root (fallback: pwd); store = <repo>/.agent/verify.json
#         env overrides (for tests): VERIFY_STORE / VERIFY_REPO_DIR
#         precedence: flags > env > defaults. Unknown args are ignored (fail-safe).
# Output: on success, the VALIDATED contract as ONE compact JSON object line on stdout (machine
#         consumers gate on non-empty stdout, then `jq` it); otherwise nothing.
# Exit:   always 0; diagnostics go to stderr (and, best-effort, .supervisor/logs/memory.log).

set -uo pipefail   # `set -e` intentionally omitted — a read must NEVER fail its caller.

# ---------------------------------------------------------------------------
# 1. Resolve repo + store (flags > env > defaults). Fail-safe arg parsing, as read-product.sh.
# ---------------------------------------------------------------------------
store_arg=""
repo_arg=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --store) if [ "$#" -ge 2 ]; then store_arg="$2"; shift 2; else shift; fi ;;
    --repo)  if [ "$#" -ge 2 ]; then repo_arg="$2";  shift 2; else shift; fi ;;
    *)       shift ;;
  esac
done

REPO_DIR="${repo_arg:-${VERIFY_REPO_DIR:-}}"
if [ -z "$REPO_DIR" ]; then
  REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
STORE="${store_arg:-${VERIFY_STORE:-}}"
[ -n "$STORE" ] || STORE="$REPO_DIR/.agent/verify.json"

LOG="$REPO_DIR/.supervisor/logs/memory.log"

# diag() — the ONE diagnostic channel: stderr (contractual) plus a best-effort memory.log append.
diag() {
  echo "$1" >&2
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$1" >> "$LOG" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 2. Tooling presence (fail-safe): jq is REQUIRED; absent ⇒ say so, emit nothing.
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  diag "read-verify: jq unavailable — verification contract unreadable, emitting nothing (fail-safe) [jq_unavailable]"
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Store presence (fail-safe): absent ⇒ named on stderr, nothing on stdout, exit 0.
# ---------------------------------------------------------------------------
if [ ! -f "$STORE" ]; then
  diag "read-verify: no verification contract store at $STORE — emitting nothing (fail-safe) [store_absent]"
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Validate + render in ONE jq pass. jq emits prefixed lines the shell partitions:
#      OK\t<compact json>   -> stdout (exactly one line, only when NO MALFORMED line was produced)
#      MALFORMED\t<reason>  -> stderr + log; NOTHING reaches stdout
#      ADVISORY\t<reason>   -> stderr + log ONLY; the verdict is unaffected (an unusable-but-well-typed
#                              member beside a usable one — the store is still emitted)
# ---------------------------------------------------------------------------
render="$(mktemp 2>/dev/null)" || {
  diag "read-verify: could not allocate a temp file — emitting nothing (fail-safe) [tempfile_unavailable]"
  exit 0
}
trap 'rm -f "$render" 2>/dev/null' EXIT

JQ_PROG='
  def bad($msg; $tok): "MALFORMED\tread-verify: " + $msg + " — emitting nothing (fail-safe) [" + $tok + "]";
  def advise($msg; $tok): "ADVISORY\tread-verify: " + $msg + " [" + $tok + "]";
  def nonempty_string: (type == "string") and (length > 0);
  # posix_identifier — the shape the executor can look up via `${!name}`; the SAME rule
  # propose-verify.sh enforces at parse time, so the three surfaces never disagree on a name.
  def posix_identifier: (type == "string") and test("^[A-Za-z_][A-Za-z0-9_]*$");
  # token_safe — a store-supplied string rendered inside a bracketed reason token: anything outside
  # the token alphabet (a space, a bracket, a newline) becomes `?` so the line stays one line.
  def token_safe: tostring | gsub("[^A-Za-z0-9_.:-]"; "?");

  # nullable_required($o; $k) — the has() presence check. An ABSENT key and an explicit null are
  # different facts; only the former is a defect. A `//` default here would collapse the two.
  def nullable_required($o; $k):
    if ($o | has($k) | not) then
      [ bad("required key `" + $k + "` is absent (null is legal, absence is not)"; "required_key_missing:" + $k) ]
    elif ($o[$k] == null) then []
    elif ($o[$k] | nonempty_string) then []
    else
      [ bad("`" + $k + "` is a " + ($o[$k] | type) + ", expected a non-empty shell string or null"; "type_invalid:" + $k) ]
    end;

  def required_string($o; $k):
    if ($o | has($k) | not) then
      [ bad("required key `" + $k + "` is absent"; "required_key_missing:" + $k) ]
    elif ($o[$k] | nonempty_string) then []
    else
      [ bad("`" + $k + "` must be a non-empty string (got a " + ($o[$k] | type) + ")"; "type_invalid:" + $k) ]
    end;

  def check_auth($o):
    if ($o | has("auth") | not) then
      [ bad("required key `auth` is absent"; "required_key_missing:auth") ]
    elif (($o.auth | type) != "object") then
      [ bad("`auth` is a " + ($o.auth | type) + ", expected an object"; "type_invalid:auth") ]
    else
      ( $o.auth ) as $a
      | ( if ($a | has("method") | not) then
            [ bad("`auth.method` is absent (expected \"none\" or \"storage_state\")"; "required_key_missing:auth.method") ]
          elif ($a.method != "none" and $a.method != "storage_state") then
            [ bad("`auth.method` must be exactly \"none\" or \"storage_state\""; "type_invalid:auth.method") ]
          else [] end )
      + ( if ($a.method == "storage_state") and (($a | has("storage_state_path") | not) or ($a.storage_state_path | nonempty_string | not)) then
            [ bad("`auth.storage_state_path` must be a non-empty string when `auth.method` is \"storage_state\""; "type_invalid:auth.storage_state_path") ]
          elif ($a | has("storage_state_path")) and ($a.storage_state_path != null) and ($a.storage_state_path | nonempty_string | not) then
            [ bad("`auth.storage_state_path` must be a string or null"; "type_invalid:auth.storage_state_path") ]
          else [] end )
      + ( if ($a | has("probe_path")) and ($a.probe_path != null) and ($a.probe_path | nonempty_string | not) then
            [ bad("`auth.probe_path` must be a non-empty string or null"; "type_invalid:auth.probe_path") ]
          else [] end )
    end;

  # check_non_prod($o) — fail CLOSED semantics live in the EXECUTOR; here the contract must merely
  # carry at least one member the executor can evaluate, with every present member well-typed.
  def check_non_prod($o):
    if ($o | has("non_prod_assert") | not) then
      [ bad("required key `non_prod_assert` is absent"; "required_key_missing:non_prod_assert") ]
    elif (($o.non_prod_assert | type) != "object") then
      [ bad("`non_prod_assert` is a " + ($o.non_prod_assert | type) + ", expected an object"; "type_invalid:non_prod_assert") ]
    else
      ( $o.non_prod_assert ) as $n
      | ( if ($n | has("base_url_matches")) and ($n.base_url_matches | nonempty_string | not) then
            [ bad("`non_prod_assert.base_url_matches` must be a non-empty string (an ERE)"; "type_invalid:non_prod_assert.base_url_matches") ]
          else [] end )
      + ( if ($n | has("env_var_equals")) and (
              (($n.env_var_equals | type) != "object")
              or ($n.env_var_equals | has("name") | not) or ($n.env_var_equals.name | nonempty_string | not)
              or ($n.env_var_equals | has("value") | not) or (($n.env_var_equals.value | type) != "string")
            ) then
            [ bad("`non_prod_assert.env_var_equals` must be an object {name: non-empty string, value: string}"; "type_invalid:non_prod_assert.env_var_equals") ]
          else [] end )
      + ( if ($n | has("cmd")) and ($n.cmd | nonempty_string | not) then
            [ bad("`non_prod_assert.cmd` must be a non-empty shell string"; "type_invalid:non_prod_assert.cmd") ]
          else [] end )
      # env_well_typed: the member passes the TYPE check above. env_usable: well-typed AND `name`
      # is an identifier the executor can look up. Well-typed-but-not-usable is ADVISORY, not
      # MALFORMED — the store stands on its other members, and is refused only when none remains.
      + ( ( ($n | has("env_var_equals")) and (($n.env_var_equals | type) == "object")
            and ($n.env_var_equals | has("name")) and ($n.env_var_equals.name | nonempty_string)
            and ($n.env_var_equals | has("value")) and (($n.env_var_equals.value | type) == "string") ) as $env_well_typed
          | ( $env_well_typed and ($n.env_var_equals.name | posix_identifier) ) as $env_usable
          | ( if $env_well_typed and ($env_usable | not) then
                [ advise("`non_prod_assert.env_var_equals.name` " + ($n.env_var_equals.name | tojson) + " is not a POSIX identifier ([A-Za-z_][A-Za-z0-9_]*) — the executor cannot look it up, so this member is UNUSABLE and does not count"; "env_var_name_invalid:" + ($n.env_var_equals.name | token_safe)) ]
              else [] end )
          + ( ( ( ($n | has("base_url_matches")) and ($n.base_url_matches | nonempty_string) )
                or $env_usable
                or ( ($n | has("cmd")) and ($n.cmd | nonempty_string) ) ) as $usable
              | if $usable then [] else
                  [ bad("`non_prod_assert` has NO usable member (need at least one of base_url_matches / env_var_equals with an identifier name / cmd) — the executor would fail CLOSED"; "non_prod_assert_empty") ]
                end ) )
    end;

  def check_optional($o):
    ( if ($o | has("ready_timeout_s")) and ((($o.ready_timeout_s | type) != "number") or ($o.ready_timeout_s <= 0)) then
        [ bad("`ready_timeout_s` must be a positive number when present"; "type_invalid:ready_timeout_s") ]
      else [] end );

  . as $o
  | if ($o | type) != "object" then
      [ bad("store root is a " + ($o | type) + ", not a JSON object"; "root_not_object") ]
    else
      ( nullable_required($o; "start")
        + required_string($o; "base_url")
        + required_string($o; "health")
        + check_auth($o)
        + check_non_prod($o)
        + nullable_required($o; "seed")
        + nullable_required($o; "reset")
        + nullable_required($o; "stop")
        + check_optional($o)
      ) as $lines
      # Only MALFORMED lines block the OK line; ADVISORY lines ride along with it (a store with an
      # unusable env_var_equals beside a usable member is still emitted — and still says why).
      | if ($lines | map(select(startswith("MALFORMED\t"))) | length) > 0 then $lines
        else $lines + [ "OK\t" + ($o | tojson) ] end
    end
  | .[]
'

# The store is fed on STDIN, never as a jq operand (a dash-leading path would otherwise be eaten as
# jq short options — see read-product.sh case (l) for the incident).
if ! jq -r "$JQ_PROG" < "$STORE" > "$render" 2>/dev/null; then
  diag "read-verify: $STORE is not parseable JSON — emitting nothing (fail-safe) [store_unparseable]"
  exit 0
fi

if [ ! -s "$render" ]; then
  diag "read-verify: $STORE produced no readable verification contract — emitting nothing (fail-safe) [render_empty]"
  exit 0
fi

# 4a. ADVISORY lines are named on stderr whatever the verdict (they never touch stdout); then the
#     MALFORMED short-circuit: report EVERY reason on stderr, emit NOTHING on stdout.
malformed=0
while IFS= read -r line; do
  case "$line" in
    ADVISORY$'\t'*)  diag "${line#ADVISORY$'\t'}" ;;
    MALFORMED$'\t'*) malformed=1 ;;
  esac
done < "$render"
if [ "$malformed" -eq 1 ]; then
  while IFS= read -r line; do
    case "$line" in
      MALFORMED$'\t'*) diag "${line#MALFORMED$'\t'}" ;;
    esac
  done < "$render"
  exit 0
fi

# 4b. Emit the ONE validated object line. Nothing here is executed: the value is printed as data.
emitted=0
while IFS= read -r line; do
  case "$line" in
    OK$'\t'*) printf '%s\n' "${line#OK$'\t'}"; emitted=1 ;;
  esac
done < "$render"

# 4c. Terminal belt: a non-empty render with neither MALFORMED nor OK is output that did not come
#     from JQ_PROG at all; the fail-safe contract still requires the reason to be named.
if [ "$emitted" -eq 0 ]; then
  diag "read-verify: $STORE yielded no verification-contract output — emitting nothing (fail-safe) [render_unrecognized]"
fi

exit 0
