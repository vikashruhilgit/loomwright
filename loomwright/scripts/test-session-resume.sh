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
# additionalContext on stdout.
#
# The exit code is stashed in a FILE, not a shell variable: callers use
# `ctx="$(run_hook_ctx ...)"`, which runs this function inside a
# command-substitution SUBSHELL — any variable it assigns is discarded before
# the caller can read it, so a plain `RC=$?` here would make every exit-code
# assertion below silently vacuous. `lastrc` reads the real value back.
RCFILE="$ROOT/.last-rc"
printf '0' > "$RCFILE"
lastrc() { cat "$RCFILE" 2>/dev/null || printf '99'; }
run_hook_raw() {
  local repo="$1" src="$2" out rc
  out="$( cd "$repo" && printf '{"source":"%s"}' "$src" | bash "$HOOK" )"
  rc=$?
  printf '%s' "$rc" > "$RCFILE"
  printf '%s' "$out"
}
run_hook_ctx() {
  local out
  out="$(run_hook_raw "$1" "$2")"
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
ctxA="$(run_hook_ctx "$RA" resume)"; rcA="$(lastrc)"
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
ctxB="$(run_hook_ctx "$RB" resume)"; rcB="$(lastrc)"
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
ctxC="$(run_hook_ctx "$RC1" resume)"; rcC="$(lastrc)"
[ "$rcC" -eq 0 ] && ok "(c) exits 0" || no "(c) expected exit 0, got $rcC"
if printf '%s\n' "$ctxC" | grep -qF -- "$NUDGE_LINE"; then
  no "(c) nudge must NOT fire when ≥1 valid rule is present"
else
  ok "(c) no nudge when a valid rule is present"
fi

# ============================================================================
echo "== (d) debounce ⇒ nudge suppressed on an immediate re-run (marker fresh) =="
RD="$(new_repo)"; make_plugin_active "$RD"   # absent .agent/rules/ ⇒ empty reader ⇒ nudge eligible
ctxD1="$(run_hook_ctx "$RD" resume)"; rcD1="$(lastrc)"
ctxD2="$(run_hook_ctx "$RD" resume)"; rcD2="$(lastrc)"
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
ctxE="$(run_hook_ctx "$RE" resume)"; rcE="$(lastrc)"
[ "$rcE" -eq 0 ] && ok "(e) exits 0 with no .supervisor/" || no "(e) expected exit 0, got $rcE"
if printf '%s\n' "$ctxE" | grep -qF -- "$NUDGE_LINE"; then
  no "(e) nudge must NOT fire in a truly-fresh repo (no .supervisor/)"
else
  ok "(e) no nudge when .supervisor/ absent (bail preserved)"
fi

# ============================================================================
echo "== (f) ALWAYS exits 0 — and a 'startup' source never carries the HOUSE-RULES nudge =="
RF="$(new_repo)"; make_plugin_active "$RF"
# startup ⇒ the hook runs ONLY the curation-cadence arm (see (h)–(m) below) and
# exits; the house-rules nudge stays below the gate and must NOT appear. With no
# .supervisor/logs/ here nothing is pending either, so the output is empty.
outF="$( cd "$RF" && printf '{"source":"startup"}' | bash "$HOOK" )"; rcF=$?
[ "$rcF" -eq 0 ] && ok "(f) exits 0 on startup source" || no "(f) expected exit 0 on startup, got $rcF"
if printf '%s\n' "$outF" | grep -qF -- "$NUDGE_LINE"; then
  no "(f) startup source must not carry the house-rules nudge"
else
  ok "(f) startup source carries no house-rules nudge"
fi
[ -z "$outF" ] && ok "(f) startup with nothing pending emits nothing at all" \
  || no "(f) startup with nothing pending should be silent, got: $outF"
# Empty stdin ⇒ exit 0.
( printf '' | bash "$HOOK" ) >/dev/null 2>&1; rcFe=$?
[ "$rcFe" -eq 0 ] && ok "(f) exits 0 on empty stdin" || no "(f) expected exit 0 on empty stdin, got $rcFe"

# ============================================================================
echo "== (g) LOOMWRIGHT_RULES_NUDGE opt-out ⇒ nudge permanently silenced (nudge-eligible repo) =="
RG="$(new_repo)"; make_plugin_active "$RG"   # absent .agent/rules/ ⇒ nudge would otherwise fire
for optout in 0 off false no; do
  ctxG="$( cd "$RG" && LOOMWRIGHT_RULES_NUDGE="$optout" printf '{"source":"resume"}' | LOOMWRIGHT_RULES_NUDGE="$optout" bash "$HOOK" \
            | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null )"; rcG=$?
  [ "$rcG" -eq 0 ] && ok "(g) exits 0 with LOOMWRIGHT_RULES_NUDGE=$optout" \
    || no "(g) expected exit 0 with opt-out=$optout, got $rcG"
  if printf '%s\n' "$ctxG" | grep -qF -- "$NUDGE_LINE"; then
    no "(g) nudge must be silenced when LOOMWRIGHT_RULES_NUDGE=$optout"
  else
    ok "(g) opt-out=$optout suppresses the nudge"
  fi
done
# Control: the SAME repo with no opt-out DOES nudge (proves the suppression is the env var, not the repo).
ctxGc="$(run_hook_ctx "$RG" resume)"
if printf '%s\n' "$ctxGc" | grep -qF -- "$NUDGE_LINE"; then
  ok "(g) control — same repo nudges without the opt-out (marker was never stamped under opt-out)"
else
  no "(g) control — repo should nudge once the opt-out is removed"
fi

# ============================================================================
# Curation-cadence nudge groups (h)–(m).
#
# These exist because the obvious implementation of this feature provably never
# fires: `case "$SOURCE" in resume|clear|compact) ;; *) exit 0 ;; esac` bails on
# source=startup, and EVERY nudge test still passes if it only ever feeds
# {"source":"resume"}. Group (h) is the one that would catch that.
CURATION_MARK="**Curation cadence:**"

# make_curation_pending <repo> — give a repo enough local corpus that the probe
# reports /dreaming and /insights as ready (thresholds lowered to 1 so the
# fixture stays small; the threshold plumbing itself is covered by
# test-curation-status.sh).
make_curation_pending() {
  local r="$1"
  mkdir -p "$r/.supervisor/logs"
  printf '%s' '{"curation":{"thresholds":{"dreaming":1,"insights":1}}}' > "$r/.supervisor/config.json"
  echo '{"event":"session_end"}' > "$r/.supervisor/logs/s1.jsonl"
  echo '{"event":"session_end"}' > "$r/.supervisor/logs/s2.jsonl"
}

# ---------------------------------------------------------------------------
echo "== (h) curation nudge FIRES on source=startup (and on resume) =="
test_curation_nudge_fires_on_startup() {
  local r ctx rc
  r="$(new_repo)"; make_plugin_active "$r"; make_curation_pending "$r"
  ctx="$(run_hook_ctx "$r" startup)"; rc="$(lastrc)"
  [ "$rc" -eq 0 ] && ok "(h) exits 0 on startup" || no "(h) expected exit 0 on startup, got $rc"
  if printf '%s\n' "$ctx" | grep -qF -- "$CURATION_MARK"; then
    ok "(h) curation nudge FIRES on source=startup (the case the shared gate bails on)"
  else
    no "(h) curation nudge did NOT fire on startup — the feature never reaches a fresh session"
  fi
  printf '%s\n' "$ctx" | grep -qE '[0-9]+ new session log' \
    && ok "(h) the startup line carries a real COUNT, not merely a date" \
    || no "(h) the startup line carries no count: $ctx"
  # ...and the same line still fires on a resume source (a DIFFERENT repo, so the
  # 24h marker from the startup run above cannot mask it).
  local r2 ctx2 rc2
  r2="$(new_repo)"; make_plugin_active "$r2"; make_curation_pending "$r2"
  ctx2="$(run_hook_ctx "$r2" resume)"; rc2="$(lastrc)"
  [ "$rc2" -eq 0 ] && ok "(h) exits 0 on resume" || no "(h) expected exit 0 on resume, got $rc2"
  printf '%s\n' "$ctx2" | grep -qF -- "$CURATION_MARK" \
    && ok "(h) curation nudge also fires on source=resume" \
    || no "(h) curation nudge did not fire on resume"
}
test_curation_nudge_fires_on_startup

# ---------------------------------------------------------------------------
echo "== (i) startup emits the curation line and NOTHING ELSE (absence of each) =="
# Asserted as the ABSENCE of every other section, not as a two-item allow-list:
# guarding only some of the sections below must not be able to pass this.
test_startup_emits_nothing_else() {
  local r out fakehome shim rc probe
  r="$(new_repo)"; make_plugin_active "$r"; make_curation_pending "$r"
  # Populate exactly the state that makes every OTHER section of the hook
  # non-empty on this repo shape.
  mkdir -p "$r/.supervisor/jobs/in-progress" "$r/.supervisor/jobs/failed"
  echo "state tail" > "$r/.supervisor/state.md"
  echo "brief" > "$r/.supervisor/jobs/in-progress/j.md"
  echo "brief" > "$r/.supervisor/jobs/failed/f.md"

  # A HOME whose settings.json configures telemetry against an unreachable
  # endpoint: if observability_probe ran at all it would curl, fire
  # notify-desktop.sh, and stamp its own 24h marker. All three are asserted absent.
  fakehome="$ROOT/fakehome"; mkdir -p "$fakehome/.claude"
  printf '%s' '{"env":{"CLAUDE_CODE_ENABLE_TELEMETRY":"1","OTEL_EXPORTER_OTLP_ENDPOINT":"http://127.0.0.1:9/v1/traces"}}' \
    > "$fakehome/.claude/settings.json"

  shim="$ROOT/shim-bin"; mkdir -p "$shim"
  rm -f "$shim/curl"
  cat > "$shim/curl" <<EOF
#!/bin/sh
: > "$ROOT/startup-called-curl"
exit 0
EOF
  chmod +x "$shim/curl"
  rm -f "$ROOT/startup-called-curl"

  out="$( cd "$r" && printf '{"source":"startup"}' \
            | HOME="$fakehome" PATH="$shim:$PATH" bash "$HOOK" )"; rc=$?
  [ "$rc" -eq 0 ] && ok "(i) exits 0" || no "(i) expected exit 0, got $rc"

  printf '%s\n' "$out" | grep -qF -- "$CURATION_MARK" \
    && ok "(i) the curation line IS present (control — the absence checks below are not vacuous)" \
    || no "(i) control failed: the curation line is missing, so the absence checks prove nothing"

  for probe in "prior-session context" "Recovery hints" "In-progress briefs" "Recent failed briefs" "state.md" "notify-desktop.sh"; do
    if printf '%s\n' "$out" | grep -qF -- "$probe"; then
      no "(i) startup output must NOT contain '$probe'"
    else
      ok "(i) absent: '$probe'"
    fi
  done
  if printf '%s\n' "$out" | grep -qF -- "$NUDGE_LINE"; then
    no "(i) startup output must NOT contain the house-rules nudge"
  else
    ok "(i) absent: the house-rules nudge"
  fi
  [ ! -e "$ROOT/startup-called-curl" ] \
    && ok "(i) NO curl invocation on the startup path (observability probe never ran)" \
    || no "(i) startup invoked curl — a network call on every fresh session start"
  [ ! -e "$fakehome/.claude/loomwright/observability/.last-warned" ] \
    && ok "(i) NO observability marker written (the probe and its desktop notification never ran)" \
    || no "(i) the observability probe ran on the startup path"
}
test_startup_emits_nothing_else

# ---------------------------------------------------------------------------
echo "== (j) startup is SILENT outside a plugin repo (own .supervisor/ check) =="
# The shared `[ ! -d ".supervisor" ]` bail sits BELOW the case the startup arm
# exits from, so without its own check the nudge would fire in every repo the
# user opens.
test_startup_silent_without_supervisor() {
  local r out rc
  r="$(new_repo)"   # deliberately NO make_plugin_active
  out="$(run_hook_raw "$r" startup)"; rc="$(lastrc)"
  [ "$rc" -eq 0 ] && ok "(j) exits 0 with no .supervisor/" || no "(j) expected exit 0, got $rc"
  [ -z "$out" ] && ok "(j) emits NOTHING in a directory with no .supervisor/" \
    || no "(j) startup must be silent outside a plugin repo, got: $out"
  [ ! -e "$r/.supervisor" ] && ok "(j) the startup arm created no .supervisor/ of its own" \
    || no "(j) startup created a .supervisor/ directory"
}
test_startup_silent_without_supervisor

# ---------------------------------------------------------------------------
echo "== (k) the emitted line actually REACHES the model (real envelope, not a bare printf) =="
# session-resume.sh's own comment records that a bare top-level additionalContext
# is NOT recognized — it is dropped or shown as raw JSON. A bare `printf` would
# satisfy "the nudge fires" while never reaching the session.
test_startup_envelope_reaches_the_model() {
  local r out
  r="$(new_repo)"; make_plugin_active "$r"; make_curation_pending "$r"
  out="$(run_hook_raw "$r" startup)"
  if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    ok "(k) startup stdout parses as JSON"
  else
    no "(k) startup stdout is not valid JSON: $out"
  fi
  [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null)" = "SessionStart" ] \
    && ok "(k) .hookSpecificOutput.hookEventName == SessionStart" \
    || no "(k) missing/incorrect hookSpecificOutput.hookEventName"
  printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null \
    | grep -qF -- "$CURATION_MARK" \
    && ok "(k) .hookSpecificOutput.additionalContext carries the curation line" \
    || no "(k) additionalContext does not carry the curation line"
  # A bare top-level additionalContext would be the failure mode; assert it is not that shape.
  [ "$(printf '%s' "$out" | jq -r 'has("additionalContext")' 2>/dev/null)" = "false" ] \
    && ok "(k) NOT a bare top-level additionalContext (the shape Claude Code drops)" \
    || no "(k) emitted a bare top-level additionalContext"
}
test_startup_envelope_reaches_the_model

# ---------------------------------------------------------------------------
echo "== (l) rules_nudge's firing surface is UNCHANGED by this work =="
# rules_nudge is a different shipped feature (v15.1.0 slice #3b-ii). It must stay
# below the gate: silent on startup, still firing on resume. Pinned so the
# curation work cannot silently move another feature's firing surface.
test_rules_nudge_surface_unchanged() {
  local r ctx_startup ctx_resume
  r="$(new_repo)"; make_plugin_active "$r"; make_curation_pending "$r"  # zero valid house rules
  ctx_startup="$(run_hook_ctx "$r" startup)"
  printf '%s\n' "$ctx_startup" | grep -qF -- "$NUDGE_LINE" \
    && no "(l) the house-rules nudge must NOT fire on startup" \
    || ok "(l) house-rules nudge does not fire on startup (surface unchanged)"
  local r2 ctx2
  r2="$(new_repo)"; make_plugin_active "$r2"; make_curation_pending "$r2"
  ctx2="$(run_hook_ctx "$r2" resume)"
  printf '%s\n' "$ctx2" | grep -qF -- "$NUDGE_LINE" \
    && ok "(l) house-rules nudge still fires on resume in the same repo shape" \
    || no "(l) house-rules nudge stopped firing on resume — its surface moved"
}
test_rules_nudge_surface_unchanged

# ---------------------------------------------------------------------------
echo "== (m) curation nudge: 24h debounce marker + LOOMWRIGHT_CURATION_NUDGE opt-out =="
test_curation_nudge_debounce_and_optout() {
  local r c1 c2 optout out rc r2
  r="$(new_repo)"; make_plugin_active "$r"; make_curation_pending "$r"
  c1="$(run_hook_ctx "$r" startup)"
  c2="$(run_hook_ctx "$r" startup)"
  printf '%s\n' "$c1" | grep -qF -- "$CURATION_MARK" \
    && ok "(m) first startup run shows the curation line" || no "(m) first run should show the line"
  [ -z "$c2" ] && ok "(m) second (debounced) run within 24h emits nothing" \
    || no "(m) second run should be debounced, got: $c2"
  [ -f "$r/.supervisor/.curation-nudge-shown" ] \
    && ok "(m) debounce marker written at .supervisor/.curation-nudge-shown" \
    || no "(m) expected the 24h marker at .supervisor/.curation-nudge-shown"

  local r2
  r2="$(new_repo)"; make_plugin_active "$r2"; make_curation_pending "$r2"
  for optout in 0 off false no; do
    out="$( cd "$r2" && printf '{"source":"startup"}' \
              | ( cd "$r2" && LOOMWRIGHT_CURATION_NUDGE="$optout" bash "$HOOK" ) )"; local rc=$?
    [ "$rc" -eq 0 ] && ok "(m) exits 0 with LOOMWRIGHT_CURATION_NUDGE=$optout" \
      || no "(m) expected exit 0 with opt-out=$optout, got $rc"
    [ -z "$out" ] && ok "(m) opt-out=$optout silences the curation nudge" \
      || no "(m) opt-out=$optout should silence the curation nudge, got: $out"
  done
  # Control: the same repo DOES nudge once the opt-out is removed (proving the
  # suppression was the env var, and that no marker was stamped under opt-out).
  out="$(run_hook_ctx "$r2" startup)"
  printf '%s\n' "$out" | grep -qF -- "$CURATION_MARK" \
    && ok "(m) control — same repo nudges once the opt-out is removed" \
    || no "(m) control — repo should nudge without the opt-out"
}
test_curation_nudge_debounce_and_optout

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
