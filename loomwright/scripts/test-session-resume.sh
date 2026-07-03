#!/usr/bin/env bash
# test-session-resume.sh — self-tests for the no-house-rules NUDGE folded into
# session-resume.sh (rules enforcement slice #3b-ii). The nudge is an advisory,
# debounced, fail-safe line appended to the SessionStart `additionalContext`
# envelope when a plugin-active repo (.supervisor/ present) has NO applicable
# house rules — gated on the sibling read-rules.sh emitting EMPTY stdout (NOT on
# bare file presence), so it also fires for a store holding only INVALID rules.
#
# Runs session-resume.sh inside ISOLATED temp git repos (mktemp -d + git init) so
# it NEVER touches the real project state. The hook reads its `source` from stdin
# JSON and emits a JSON envelope on stdout; we feed a `resume` source and inspect
# `.hookSpecificOutput.additionalContext`. Mirrors the test-read-rules.sh harness
# convention. Exit 0 = all pass, 1 = any failure (auto-registered by ci.yml's
# test-*.sh glob).
#
# Covers cases (a)–(f):
#   (a) No valid rules (absent .agent/rules/) + resume ⇒ nudge line present ONCE.
#   (b) Store present but ALL rules invalid (reader emits empty) ⇒ nudge STILL
#       fires (proves it gates on reader OUTPUT, not file presence).
#   (c) Store with ≥1 VALID rule ⇒ NO nudge line.
#   (d) Debounce ⇒ nudge suppressed on an immediate re-run (marker fresh).
#   (e) .supervisor/-absent ⇒ no nudge (the bail is preserved, no crash).
#   (f) The script ALWAYS exits 0 in every case (asserted throughout).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/session-resume.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

NUDGE_LINE="No committed house rules found — run \`/rules suggest\` to propose some, or \`/rules add\` to author."

# All temp dirs live under ONE root so a single trap reliably cleans everything.
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

# Isolated temp git repo (so the reader's `git rev-parse --show-toplevel` = it).
new_repo() {
  local r; r="$(mktmp)"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$r"
}

# Give a repo the plugin-active marker directory (.supervisor/) that the hook
# requires past its bail.
make_plugin_active() { mkdir -p "$1/.supervisor"; }

# Write a *.json rule file under a repo's .agent/rules/. $1 repo $2 fname $3 json.
seed_rules_file() {
  local repo="$1" fname="$2" content="$3"
  mkdir -p "$repo/.agent/rules"
  printf '%s' "$content" > "$repo/.agent/rules/$fname"
}

# Run the hook inside a temp repo with a given `source`; capture the extracted
# additionalContext on stdout. Echoes the additionalContext string; sets the
# global RC to the hook's exit code.
RC=0
run_hook_ctx() {
  local repo="$1" src="$2" out
  out="$( cd "$repo" && printf '{"source":"%s"}' "$src" | bash "$HOOK" )"
  RC=$?
  # Extract additionalContext (empty string if the envelope wasn't emitted).
  printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true
}

if ! command -v jq >/dev/null 2>&1; then
  echo "test-session-resume: jq absent on this host — session-resume.sh no-ops (exit 0). Skipping assertions."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

# ============================================================================
echo "== (a) no valid rules (absent .agent/rules/) + resume ⇒ nudge present exactly once =="
RA="$(new_repo)"; make_plugin_active "$RA"
ctxA="$(run_hook_ctx "$RA" resume)"; rcA=$RC
[ "$rcA" -eq 0 ] && ok "(a) exits 0" || no "(a) expected exit 0, got $rcA"
countA="$(printf '%s\n' "$ctxA" | grep -cF -- "$NUDGE_LINE")"
[ "$countA" -eq 1 ] && ok "(a) nudge line present exactly once" \
  || no "(a) expected nudge exactly once, got $countA occurrences"

# ============================================================================
echo "== (b) store present but ALL rules invalid ⇒ nudge STILL fires (gates on reader output) =="
RB="$(new_repo)"; make_plugin_active "$RB"
# An invalid rule the reader skips (missing the required `enforcement` field ⇒
# zero valid rules ⇒ reader emits EMPTY ⇒ nudge must still fire).
seed_rules_file "$RB" "allbad.json" '[
  {"id":"b-bad","category":"safety","statement":"missing enforcement field","check":null,"provenance":{"source":"test"}}
]'
ctxB="$(run_hook_ctx "$RB" resume)"; rcB=$RC
[ "$rcB" -eq 0 ] && ok "(b) exits 0" || no "(b) expected exit 0, got $rcB"
if printf '%s\n' "$ctxB" | grep -qF -- "$NUDGE_LINE"; then
  ok "(b) nudge fires for an all-invalid store (proves reader-output gate, not file presence)"
else
  no "(b) nudge should fire when the store holds only invalid rules"
fi

# ============================================================================
echo "== (c) store with ≥1 VALID rule ⇒ NO nudge line =="
RC1="$(new_repo)"; make_plugin_active "$RC1"
seed_rules_file "$RC1" "good.json" '[
  {"id":"c-good","category":"safety","statement":"A valid house rule exists","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
ctxC="$(run_hook_ctx "$RC1" resume)"; rcC=$RC
[ "$rcC" -eq 0 ] && ok "(c) exits 0" || no "(c) expected exit 0, got $rcC"
if printf '%s\n' "$ctxC" | grep -qF -- "$NUDGE_LINE"; then
  no "(c) nudge must NOT fire when ≥1 valid rule is present"
else
  ok "(c) no nudge when a valid rule is present"
fi

# ============================================================================
echo "== (d) debounce ⇒ nudge suppressed on an immediate re-run (marker fresh) =="
RD="$(new_repo)"; make_plugin_active "$RD"   # absent .agent/rules/ ⇒ empty reader ⇒ nudge eligible
ctxD1="$(run_hook_ctx "$RD" resume)"; rcD1=$RC
ctxD2="$(run_hook_ctx "$RD" resume)"; rcD2=$RC
[ "$rcD1" -eq 0 ] && [ "$rcD2" -eq 0 ] && ok "(d) both runs exit 0" \
  || no "(d) expected exit 0 on both runs ($rcD1/$rcD2)"
c1="$(printf '%s\n' "$ctxD1" | grep -cF -- "$NUDGE_LINE")"
c2="$(printf '%s\n' "$ctxD2" | grep -cF -- "$NUDGE_LINE")"
[ "$c1" -eq 1 ] && ok "(d) first run shows the nudge" || no "(d) first run should show nudge (got $c1)"
[ "$c2" -eq 0 ] && ok "(d) second (debounced) run suppresses the nudge" \
  || no "(d) second run should be debounced (got $c2)"
# Sanity: the debounce marker was written under .supervisor/.
[ -f "$RD/.supervisor/.rules-nudge-shown" ] && ok "(d) debounce marker written under .supervisor/" \
  || no "(d) expected debounce marker at .supervisor/.rules-nudge-shown"

# ============================================================================
echo "== (e) .supervisor/-absent ⇒ no nudge (bail preserved, no crash) =="
RE="$(new_repo)"   # NO make_plugin_active ⇒ no .supervisor/ ⇒ hook bails before nudge
ctxE="$(run_hook_ctx "$RE" resume)"; rcE=$RC
[ "$rcE" -eq 0 ] && ok "(e) exits 0 with no .supervisor/" || no "(e) expected exit 0, got $rcE"
if printf '%s\n' "$ctxE" | grep -qF -- "$NUDGE_LINE"; then
  no "(e) nudge must NOT fire in a truly-fresh repo (no .supervisor/)"
else
  ok "(e) no nudge when .supervisor/ absent (bail preserved)"
fi

# ============================================================================
echo "== (f) ALWAYS exits 0 — including on a 'startup' source (silent) =="
RF="$(new_repo)"; make_plugin_active "$RF"
# startup ⇒ the hook silent no-ops before building any envelope; must exit 0 and
# emit NO nudge.
outF="$( cd "$RF" && printf '{"source":"startup"}' | bash "$HOOK" )"; rcF=$?
[ "$rcF" -eq 0 ] && ok "(f) exits 0 on startup source" || no "(f) expected exit 0 on startup, got $rcF"
if printf '%s\n' "$outF" | grep -qF -- "$NUDGE_LINE"; then
  no "(f) startup source must stay silent (no nudge)"
else
  ok "(f) startup source silent (no nudge)"
fi
# Empty stdin ⇒ exit 0.
( printf '' | bash "$HOOK" ) >/dev/null 2>&1; rcFe=$?
[ "$rcFe" -eq 0 ] && ok "(f) exits 0 on empty stdin" || no "(f) expected exit 0 on empty stdin, got $rcFe"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
