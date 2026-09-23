#!/usr/bin/env bash
# test-hook-payload-contract.sh — hook-payload FIELD CONTRACT gate
# (red-team-hardening item 08, Fix 5).
#
# WHY: this plugin's fail-SAFE emitters (emit-progress-event.sh,
# emit-token-ledger.sh, emit-lifecycle.sh, send-telemetry-core.sh, the
# validate-*.py result validators, ...) all read Claude Code hook-payload
# fields (session_id, agent_type, agent_id, last_assistant_message,
# agent_transcript_path, transcript_path, stop_hook_active, cwd, ...) that
# are NOT part of any documented, versioned schema. A silent upstream field
# rename would not error — these scripts are fail-SAFE by design — it would
# just turn them into silent no-ops. This gate is the regression net: it
# scans every hook-invoked script for the field-read idiom this codebase
# already uses everywhere (`payload.get("field")` / `payload["field"]`) and
# asserts each field name it finds actually appears in at least one recorded
# fixture under progress-event-fixtures/spawn-probe-2026-09-02/ — the real,
# live-captured payload shapes this plugin was last verified against
# (2026-09-02, per the SubagentStop-payload-shape memory lesson).
#
# SCOPE, HONESTLY STATED (do not silently widen this without re-reading this
# comment):
#   - "Hook script" = a script named literally in loomwright/hooks/hooks.json
#     (SCRIPT NAME extraction from the `command` strings), PLUS one level of
#     sibling scripts each of those files itself invokes by literal filename
#     (e.g. send-telemetry.sh's `CORE="$SCRIPT_DIR/send-telemetry-core.sh"`
#     pulls send-telemetry-core.sh into scope). This is why setup-ui.sh's
#     OWN local variable named "payload" (an HTTP POST body on The Floor's
#     loopback server, nothing to do with Claude Code hooks) is correctly
#     OUT of scope — it is never named in hooks.json.
#   - The field-read idiom scanned for is the literal-string form:
#     `payload.get("field")` / `payload.get('field')` /
#     `payload["field"]` / `payload['field']`. A field reached only through
#     variable indirection (`for key in ("a", "b"): payload.get(key)`) is
#     NOT extracted — that shape exists today (emit-token-ledger.sh's
#     forward-compat `usage`/`input_tokens`/... probe, scoped to a NESTED
#     tool_response object, not the top-level payload) and flagging it would
#     conflate "a script defensively probes for a field that may not exist
#     yet" with "a script depends on a field that used to exist and vanished"
#     — this gate is about the second failure mode.
#   - KNOWN_EXEMPT below are field reads the codebase's OWN comments already
#     document as deliberately NOT current top-level hook-payload fields:
#     result_block / output / agent_output are RETAINED LEGACY fallback
#     names (send-telemetry-core.sh's and validate-launch-pad-result.py's own
#     comments: "the legacy ... field names are retained ... so existing
#     fixtures and any future payload that re-adds them keep working" — they
#     are a compat shim, not a current-shape dependency). `error` is read by
#     emit-lifecycle.sh's `failed` subcommand, wired to the StopFailure hook
#     event (hooks.json) — a hook event this fixture directory does not
#     record a shape for at all (spawn-probe-2026-09-02 covers SubagentStop
#     + PostToolUse[Task] + PreToolUse[Task] only). That is a REAL, separate
#     gap (no fixture exists to verify `error` against), left open here
#     rather than papered over with an invented fixture — recording a
#     StopFailure fixture is future work, not silently done by this gate.
#
# MUTATION CONTROL: appends a read of a field name that exists in NO fixture
# (`xyz_never_recorded_field`) to a COPY of one real hook script and asserts
# the SAME scan function flags it — proving the assertion is load-bearing,
# not vacuously green because nothing is ever extracted.
#
# EXIT: 0 on full pass, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_JSON="$SCRIPT_DIR/../hooks/hooks.json"
FIXTURE_DIR="$SCRIPT_DIR/progress-event-fixtures/spawn-probe-2026-09-02"

command -v jq >/dev/null 2>&1 || { echo "FATAL  jq required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FATAL  python3 required" >&2; exit 1; }
[ -f "$HOOKS_JSON" ] || { echo "FATAL  hooks.json not found: $HOOKS_JSON" >&2; exit 1; }
[ -d "$FIXTURE_DIR" ] || { echo "FATAL  fixture dir not found: $FIXTURE_DIR" >&2; exit 1; }

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "ok   - $1"; }
no() { fail=$((fail + 1)); echo "FAIL - $1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/hook-payload-contract.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# ---- Authoritative fixture field union (mechanical, adapts if fixtures are
#      re-recorded) -----------------------------------------------------------
FIXTURE_FIELDS="$(python3 -c '
import json, os, sys
fields = set()
d = sys.argv[1]
for name in sorted(os.listdir(d)):
    if not name.endswith(".json"):
        continue
    try:
        obj = json.load(open(os.path.join(d, name)))
    except Exception:
        continue
    if isinstance(obj, dict):
        fields.update(obj.keys())
print("\n".join(sorted(fields)))
' "$FIXTURE_DIR")"
[ -n "$FIXTURE_FIELDS" ] || { echo "FATAL  no fixture fields extracted from $FIXTURE_DIR" >&2; exit 1; }

fixture_has_field() { # fixture_has_field <name>
  printf '%s\n' "$FIXTURE_FIELDS" | grep -qxF -- "$1"
}

# ---- Documented, deliberate exemptions (see header comment) -----------------
KNOWN_EXEMPT="result_block
output
agent_output
error"
is_exempt() { # is_exempt <name>
  printf '%s\n' "$KNOWN_EXEMPT" | grep -qxF -- "$1"
}

# ---- Hook-script set: named in hooks.json, plus one level of siblings ------
HOOK_SCRIPT_NAMES="$(python3 -c '
import json, re, sys
d = json.load(open(sys.argv[1]))
names = set()
for _event, arr in d.get("hooks", {}).items():
    for grp in arr:
        for h in grp.get("hooks", []):
            cmd = h.get("command", "")
            for m in re.finditer(r"scripts/([A-Za-z0-9_.-]+\.(?:sh|py))", cmd):
                names.add(m.group(1))
print("\n".join(sorted(names)))
' "$HOOKS_JSON")"

ALL_SCRIPT_NAMES="$HOOK_SCRIPT_NAMES"
while IFS= read -r nm; do
  [ -n "$nm" ] || continue
  f="$SCRIPT_DIR/$nm"
  [ -f "$f" ] || continue
  # One level of sibling-by-literal-filename indirection (e.g. send-telemetry.sh
  # -> send-telemetry-core.sh via CORE="$SCRIPT_DIR/send-telemetry-core.sh").
  sibs="$(grep -oE '[A-Za-z0-9_-]+\.(sh|py)' "$f" 2>/dev/null | sort -u)"
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    [ "$s" = "$nm" ] && continue
    [ -f "$SCRIPT_DIR/$s" ] || continue
    case "$(printf '%s\n' "$ALL_SCRIPT_NAMES")" in
      *"$s"*) ;;
      *) ALL_SCRIPT_NAMES="$ALL_SCRIPT_NAMES
$s" ;;
    esac
  done <<EOF
$sibs
EOF
done <<EOF
$HOOK_SCRIPT_NAMES
EOF
ALL_SCRIPT_NAMES="$(printf '%s\n' "$ALL_SCRIPT_NAMES" | sort -u | grep -v '^$')"

# ---- Core scan function: extract payload.get("x")/payload["x"] field names
#      from a file, print one per line -------------------------------------
scan_field_reads() { # scan_field_reads <file>
  grep -ohE "payload\.get\([[:space:]]*['\"][A-Za-z_][A-Za-z0-9_]*['\"]" "$1" 2>/dev/null \
    | sed -E "s/^payload\.get\([[:space:]]*['\"]//; s/['\"]\$//"
  grep -ohE "payload\[[[:space:]]*['\"][A-Za-z_][A-Za-z0-9_]*['\"][[:space:]]*\]" "$1" 2>/dev/null \
    | sed -E "s/^payload\[[[:space:]]*['\"]//; s/['\"][[:space:]]*\]\$//"
}

# ---- Main scan --------------------------------------------------------------
violations=""
scripts_scanned=0
fields_verified=0
while IFS= read -r nm; do
  [ -n "$nm" ] || continue
  f="$SCRIPT_DIR/$nm"
  [ -f "$f" ] || continue
  scripts_scanned=$((scripts_scanned + 1))
  while IFS= read -r field; do
    [ -n "$field" ] || continue
    if is_exempt "$field"; then
      continue
    fi
    if fixture_has_field "$field"; then
      fields_verified=$((fields_verified + 1))
    else
      violations="$violations
$nm:$field"
    fi
  done < <(scan_field_reads "$f" | sort -u)
done <<EOF
$ALL_SCRIPT_NAMES
EOF

if [ "$scripts_scanned" -gt 0 ] && [ "$fields_verified" -gt 0 ] && [ -z "$violations" ]; then
  ok "hook-payload field contract: $scripts_scanned script(s) scanned, $fields_verified field-read(s) all verified present in a recorded fixture"
else
  no "hook-payload field contract: scripts_scanned=$scripts_scanned fields_verified=$fields_verified violations:$violations"
fi

# ---- Anti-vacuity: the scan must have found a non-trivial, EXPECTED field
#      set — otherwise a broken extraction regex would pass by finding
#      nothing at all. ---------------------------------------------------
EXPECT_AT_LEAST="session_id
agent_type
last_assistant_message
agent_transcript_path"
missing_expected=""
FOUND_ALL="$(while IFS= read -r nm; do
  [ -n "$nm" ] || continue
  f="$SCRIPT_DIR/$nm"
  [ -f "$f" ] || continue
  scan_field_reads "$f"
done <<EOF
$ALL_SCRIPT_NAMES
EOF
)"
while IFS= read -r ef; do
  [ -n "$ef" ] || continue
  if ! printf '%s\n' "$FOUND_ALL" | grep -qxF -- "$ef"; then
    missing_expected="$missing_expected $ef"
  fi
done <<EOF
$EXPECT_AT_LEAST
EOF
if [ -z "$missing_expected" ]; then
  ok "anti-vacuity: the scan actually extracted the expected core fields (session_id, agent_type, last_assistant_message, agent_transcript_path) — it is not silently finding nothing"
else
  no "anti-vacuity: the scan should have found:$missing_expected — extraction regex may be broken"
fi

# ---- Mutation control: inject a read of a field absent from every fixture,
#      on a COPY of a real hook script, and confirm the SAME scan flags it --
MUTANT_SRC="$SCRIPT_DIR/emit-progress-event.sh"
if [ -f "$MUTANT_SRC" ]; then
  MUTANT="$TMP/emit-progress-event.mut.sh"
  cp "$MUTANT_SRC" "$MUTANT"
  printf '\n_never_recorded = payload.get("xyz_never_recorded_field")\n' >> "$MUTANT"
  MUT_FIELDS="$(scan_field_reads "$MUTANT" | sort -u)"
  if printf '%s\n' "$MUT_FIELDS" | grep -qxF -- "xyz_never_recorded_field"; then
    if fixture_has_field "xyz_never_recorded_field"; then
      no "mutation control: fixture precondition broken — xyz_never_recorded_field unexpectedly present in a fixture"
    else
      ok "mutation control: a field read absent from every fixture IS extracted by the scan and would FAIL the gate (xyz_never_recorded_field not in any fixture)"
    fi
  else
    no "mutation control: the injected read was not extracted by scan_field_reads — the mutation did not land, this control proves nothing"
  fi
  # Real script untouched.
  if cmp -s "$MUTANT_SRC" "$SCRIPT_DIR/emit-progress-event.sh"; then
    ok "mutation control: the real emit-progress-event.sh is untouched (mutant was a copy in a temp dir)"
  else
    no "mutation control: the real emit-progress-event.sh was modified — this must never happen"
  fi
else
  no "mutation control: emit-progress-event.sh not found, cannot construct the mutant"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
