#!/usr/bin/env bash
# test-guard-onfailure.sh — a CRASHING fail-CLOSED guard must block, not let the action through.
#
# The fail-CLOSED PreToolUse leaves (guard-test-integrity.sh on Bash and Write|Edit,
# guard-finalize-publish.sh on Bash) deny with exit 2. Before this suite's change, any OTHER non-zero
# exit — the script missing, a `set -u` abort, a bad interpreter — was the host's non-blocking error:
# the guarded action ran, so each guard failed OPEN on its own crash. Claude Code 2.1.295+ treats
# that as a failure that blocks when the leaf carries `"onFailure": "block"` (docs: hooks reference,
# "Block the action when a hook fails"; probe evidence: fixtures/onfailure-block-probe.json — a
# pre-2.1.295 host ignores the key and still runs the hook, so the field costs an old host nothing).
#
# Covers:
#   (A) wiring, derived from hooks.json (no restated list): every fail-CLOSED `type: command` leaf
#       (one with no `|| true`) carries `onFailure: "block"` and no `async`/`asyncRewake` (block has
#       no effect on a background hook); both guard scripts are in that set; no fail-SAFE leaf
#       (`|| true`) carries `block` — an emitter must never stop the action it observes — and no
#       leaf carries it on an event where it is documented as having no effect.
#   (B) the host decision model (exit 0 allow, exit 2 block, any other exit: block iff onFailure is
#       "block") reproduces every run recorded in the probe fixture, so the model is pinned to what
#       real hosts did rather than to a reading of the docs.
#   (C) a crashing guard blocks: each fail-CLOSED leaf's EXACT hooks.json command string is run with
#       the plugin-root variable pointing at (1) a plugin root with the guard missing and (2) a copy whose
#       guard aborts on an unbound variable right after `set -u`. Each exits outside {0,2} and the
#       model, fed the leaf's own onFailure, says block.
#   (D) the allow path is unaffected: each real guard on an inert payload exits exactly 0 with empty
#       or valid-JSON stdout, so `block` (which also treats unparseable JSON as a failure) never
#       turns a clean allow into a block.
#       Deeper allow paths (an armed session, a live run whose command is not a publish) are pinned
#       to exactly exit 0 by test-guard-test-integrity.sh / test-guard-finalize-publish.sh, which
#       assert `rc=0`, never just "not 2" — that is what keeps `block` from firing on an allow.
#   MUTATION CONTROL: the same crashes on a hooks.json copy with the key removed read as ALLOW —
#       the pre-fix fail-open the key exists to close.
#
# EXPLICIT LIMIT: this pins the wiring and the scripts' exit contract; it cannot run the host. A
# timeout (also a failure under `block`) is not exercised. The host's own behavior is pinned by the
# recorded probe only, which a newer host could change — re-run the fixture's _how_to_reproduce.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"
HOOKS="$PLUGIN_ROOT/hooks/hooks.json"
FIXTURE="$HERE/fixtures/onfailure-block-probe.json"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
command -v jq >/dev/null 2>&1 || { echo "FATAL jq required" >&2; exit 1; }
for f in "$HOOKS" "$FIXTURE"; do [ -f "$f" ] || { echo "FATAL missing $f" >&2; exit 1; }; done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/guard-onfailure.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# host_decide <exit_code> <onFailure|""> -> prints allow|block. The documented PreToolUse contract.
host_decide() {
  case "$1" in
    0) echo allow ;;
    2) echo block ;;
    *) [ "$2" = block ] && echo block || echo allow ;;
  esac
}

# leaves <hooks.json> -> one TSV row per command leaf: event, command, onFailure, async-ish flag, matcher.
leaves() {
  jq -r '.hooks | to_entries[] | .key as $ev | .value[] | (.matcher // "") as $m | .hooks[]
         | select(.type == "command")
         | [$ev, .command, (.onFailure // ""), ((.async // false) or (.asyncRewake // false) | tostring), $m]
         | @tsv' "$1"
}

echo "== (A) wiring =="
closed=0; closed_scripts=""
while IFS=$'\t' read -r ev cmd of async matcher; do
  case "$cmd" in
    *'|| true'*)
      [ "$of" = block ] && no "fail-SAFE leaf carries onFailure block ($ev): $cmd" ;;
    *)
      leafname="${cmd##*/}"; leafname="${leafname%\"}"
      closed=$((closed+1)); closed_scripts="$closed_scripts $leafname"
      [ "$of" = block ] && ok "fail-CLOSED leaf has onFailure block ($ev $matcher): $leafname" \
        || no "fail-CLOSED leaf lacks onFailure block ($ev): $cmd"
      [ "$async" = false ] || no "fail-CLOSED leaf is async — onFailure has no effect there ($ev): $cmd" ;;
  esac
  if [ "$of" = block ]; then
    case "$ev" in Stop|SubagentStop|TaskCompleted|TeammateIdle)
      no "onFailure block on $ev, where the host documents it as having no effect: $cmd" ;;
    esac
  fi
done < <(leaves "$HOOKS")
[ "$closed" -gt 0 ] && ok "hooks.json has $closed fail-CLOSED command leaves" || no "no fail-CLOSED leaves found — wiring query broken"
for g in guard-test-integrity.sh guard-finalize-publish.sh; do
  case "$closed_scripts" in *"$g"*) ok "$g is in the fail-CLOSED set" ;; *) no "$g missing from the fail-CLOSED set" ;; esac
done

echo "== (B) host model vs recorded probe =="
nruns="$(jq '.runs | length' "$FIXTURE")"
[ "$nruns" -ge 4 ] || no "probe fixture has $nruns runs (expected >= 4)"
while IFS=$'\t' read -r host rc of ran; do
  # a pre-2.1.295 host does not know the key: it behaves as the default `continue`
  eff="$of"
  case "$host" in 2.1.2[0-8][0-9]|2.1.29[0-4]|2.0.*|1.*) eff="" ;; esac
  want=allow; [ "$ran" = false ] && want=block
  got="$(host_decide "$rc" "$eff")"
  [ "$got" = "$want" ] && ok "model matches probe: host $host exit $rc onFailure=$of -> $got" \
    || no "model disagrees with probe: host $host exit $rc onFailure=$of -> model $got, host $want"
done < <(jq -r '.runs[] | [.host, .hook_exit, .onFailure, .tool_ran] | @tsv' "$FIXTURE")

# run_leaf <command string> <plugin root> <payload> -> sets RC and OUT. The host runs the leaf as a
# shell command with the plugin-root variable set; here-string, never a pipe (an inert path exits without
# reading stdin, and a piped producer then races EPIPE).
run_leaf() {
  local cmd="$1" root="$2" payload="$3"
  OUT="$(CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PROJECT_DIR="$PROJ" bash -c "$cmd" <<<"$payload" 2>/dev/null)"
  RC=$?
}

PROJ="$TMP/proj"; mkdir -p "$PROJ"
P_BASH='{"session_id":"s-onfail","tool_name":"Bash","tool_input":{"command":"ls"}}'
P_EDIT='{"session_id":"s-onfail","tool_name":"Edit","tool_input":{"file_path":"src/a.txt"}}'

# Crash roots: (1) no scripts at all; (2) each guard aborts on an unbound variable after `set -u`.
MISSING_ROOT="$TMP/missing"; mkdir -p "$MISSING_ROOT/scripts"
ABORT_ROOT="$TMP/abort"; mkdir -p "$ABORT_ROOT/scripts"
for g in guard-test-integrity.sh guard-finalize-publish.sh; do
  awk '{print} /^set -u$/ && !d {print ": \"${LW_ONFAILURE_PROBE_UNSET}\""; d=1}' "$HERE/$g" > "$ABORT_ROOT/scripts/$g"
  if cmp -s "$HERE/$g" "$ABORT_ROOT/scripts/$g" || ! bash -n "$ABORT_ROOT/scripts/$g"; then
    no "could not build the aborting copy of $g (no top-level 'set -u' line?)"
  fi
done

NOKEY="$TMP/hooks-nokey.json"
jq 'del(.. | objects | .onFailure)' "$HOOKS" > "$NOKEY"
cmp -s "$HOOKS" "$NOKEY" && no "mutation control: removing onFailure changed nothing — control inconclusive"

echo "== (C) a crashing guard blocks; (D) the allow path still allows =="
while IFS=$'\t' read -r ev cmd of async matcher; do
  case "$cmd" in *'|| true'*) continue ;; esac
  case "$ev" in PreToolUse) ;; *) continue ;; esac
  name="${cmd##*/}"; name="${name%\"}"
  # the payload shape this leaf's own matcher routes to it
  case "$matcher" in Bash) payloads=("$P_BASH") ;; 'Write|Edit') payloads=("$P_EDIT") ;; *) payloads=("$P_BASH" "$P_EDIT") ;; esac
  for payload in "${payloads[@]}"; do
    tool="$(jq -r .tool_name <<<"$payload")"
    for crash in missing abort; do
      root="$MISSING_ROOT"; [ "$crash" = abort ] && root="$ABORT_ROOT"
      run_leaf "$cmd" "$root" "$payload"
      d="$(host_decide "$RC" "$of")"
      if [ "$RC" != 0 ] && [ "$RC" != 2 ] && [ "$d" = block ]; then
        ok "$name ($tool, $crash) exits $RC -> host blocks"
      else
        no "$name ($tool, $crash) exits $RC -> host $d (a crashed guard must block)"
      fi
    done
    run_leaf "$cmd" "$PLUGIN_ROOT" "$payload"
    json_ok=1; [ -z "$OUT" ] || jq -e . >/dev/null 2>&1 <<<"$OUT" || json_ok=0
    if [ "$RC" = 0 ] && [ "$json_ok" = 1 ] && [ "$(host_decide "$RC" "$of")" = allow ]; then
      ok "$name ($tool, inert payload) exits 0 with clean stdout -> host allows"
    else
      no "$name ($tool, inert payload) rc=$RC json_ok=$json_ok — onFailure block would turn this allow into a block"
    fi
  done
done < <(leaves "$HOOKS")

echo "== mutation control: without the key, the same crashes fail OPEN =="
opened=0; total=0
while IFS=$'\t' read -r ev cmd of async matcher; do
  case "$cmd" in *'|| true'*) continue ;; esac
  [ "$ev" = PreToolUse ] || continue
  for root in "$MISSING_ROOT" "$ABORT_ROOT"; do
    p="$P_BASH"; [ "$matcher" = 'Write|Edit' ] && p="$P_EDIT"
    run_leaf "$cmd" "$root" "$p"
    total=$((total+1))
    [ "$(host_decide "$RC" "$of")" = allow ] && opened=$((opened+1))
  done
done < <(leaves "$NOKEY")
[ "$total" -gt 0 ] && [ "$opened" = "$total" ] \
  && ok "mutation control: with onFailure removed, all $total crash cases read allow (the pre-fix fail-open)" \
  || no "mutation control: only $opened/$total crash cases fail open without the key — the crash cases do not exercise it"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
