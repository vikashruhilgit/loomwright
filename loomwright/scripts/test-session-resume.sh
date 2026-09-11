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
#   (g) LOOMWRIGHT_RULES_NUDGE opt-out.
#   (h)–(m) The curation-cadence nudge and its dedicated `startup)` arm.
#   (n) System Twin store health reaches the resume digest (dark only).
#   (o)–(v) The STRANDED-BRIEF line on the startup arm (v15.64.0): fires on
#       startup via the offline reconciler (o); byte-identical when nothing is
#       stranded, incl. a captured origin/main baseline (p); no .supervisor/ +
#       opt-out + 24h debounce (q); the gate is NOT widened, asserted per item
#       (r); resume path unchanged (s); helpers reachable above the case —
#       static + dynamic + mutant (t); offline + four fail-safe degradations
#       (u); mutation control + ONE composed envelope (v).
#   (w)–(y) The ORPHANED-WORKTREES advisory section (v15.66.0): a sibling
#       worktree-audit.sh whose `report` prints one row ⇒ the section + row on
#       startup AND resume (w); report empty / sibling absent ⇒ startup cmp-equal
#       to the curation-only formula and no header on either arm, plus the
#       local-only origin/main resume baseline and a mutant that appends the
#       section unconditionally (x); header string deleted ⇒ (w) red (y).

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

# Observability-probe tripwire fixture, shared by (i) and (r). VENDOR-COUPLING
# RATCHET (load-bearing): this test file sits AT its manifest allowance for the
# vendor tokens, and the three literals below are its ONLY occurrences — they
# are defined here ONCE and reached through these accessors from every group.
# Do NOT inline them again anywhere in this file.
#
# make_unreachable_telemetry_home <dir> — a HOME whose settings.json configures
# telemetry against an unreachable endpoint: if observability_probe ran at all
# it would curl, fire notify-desktop.sh, and stamp its own 24h marker.
make_unreachable_telemetry_home() {
  local h="$1"
  mkdir -p "$h/.claude"
  printf '%s' '{"env":{"CLAUDE_CODE_ENABLE_TELEMETRY":"1","OTEL_EXPORTER_OTLP_ENDPOINT":"http://127.0.0.1:9/v1/traces"}}' \
    > "$h/.claude/settings.json"
}
# curl_shim_called_marker — the file the curl shim stamps when invoked.
curl_shim_called_marker() { printf '%s' "$ROOT/startup-called-curl"; }
# make_curl_shim — (re)creates the shim dir on stdout; clears the marker.
make_curl_shim() {
  local shim="$ROOT/shim-bin"; mkdir -p "$shim"
  rm -f "$shim/curl"
  cat > "$shim/curl" <<EOF
#!/bin/sh
: > "$(curl_shim_called_marker)"
exit 0
EOF
  chmod +x "$shim/curl"
  rm -f "$(curl_shim_called_marker)"
  printf '%s' "$shim"
}
# obs_warned_marker <fakehome> — PRINTS the observability probe's debounce path.
obs_warned_marker() { printf '%s/.claude/loomwright/observability/.last-warned' "$1"; }

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
  # ONE assertion per command, each pinning THAT command's own noun next to its
  # own count. A single shared pattern silently degrades into testing whichever
  # half still matches: the fixture makes BOTH halves ready, so a regression that
  # dropped the count from one line would sail through on the other's text.
  printf '%s\n' "$ctx" | grep -qE '/dreaming [0-9]+ unreflected session log' \
    && ok "(h) the /dreaming half of the startup line carries a real COUNT, not merely a date" \
    || no "(h) the /dreaming half of the startup line carries no count: $ctx"
  printf '%s\n' "$ctx" | grep -qE '/insights [0-9]+ new session log' \
    && ok "(h) the /insights half of the startup line carries a real COUNT, not merely a date" \
    || no "(h) the /insights half of the startup line carries no count: $ctx"
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
  fakehome="$ROOT/fakehome"; make_unreachable_telemetry_home "$fakehome"
  shim="$(make_curl_shim)"

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
  [ ! -e "$(curl_shim_called_marker)" ] \
    && ok "(i) NO curl invocation on the startup path (observability probe never ran)" \
    || no "(i) startup invoked curl — a network call on every fresh session start"
  [ ! -e "$(obs_warned_marker "$fakehome")" ] \
    && ok "(i) NO observability marker written (the probe and its desktop notification never ran)" \
    || no "(i) the observability probe ran on the startup path"
}
test_startup_emits_nothing_else

# ---------------------------------------------------------------------------
echo "== (j) the startup arm's CWD-RELATIVE .supervisor/ gate (scope + discrimination) =="
# The shared `[ ! -d ".supervisor" ]` bail sits BELOW the case the startup arm
# exits from, so without its own check the nudge would fire in every directory
# the user opens.
#
# SCOPE HONESTY — what the first case does and does NOT prove. In a repo with no
# .supervisor/ ANYWHERE up to the git root, the assertion is also satisfied by
# curation-status.sh's own `[ -d "$SUP_DIR" ] || return 0` in cmd_nudge — a THIRD
# copy of the predicate, in a separate process. So this case pins the OUTCOME
# ("silent in a directory with no .supervisor/ anywhere up to the git root"), not
# the hook-side guard. It is kept because that outcome is the user-visible
# contract; the case below is what actually discriminates the guard.
test_startup_silent_without_supervisor_anywhere() {
  local r out rc
  r="$(new_repo)"   # deliberately NO make_plugin_active
  out="$(run_hook_raw "$r" startup)"; rc="$(lastrc)"
  [ "$rc" -eq 0 ] && ok "(j) exits 0 with no .supervisor/" || no "(j) expected exit 0, got $rc"
  [ -z "$out" ] && ok "(j) silent in a directory with no .supervisor/ anywhere up to the git root" \
    || no "(j) startup must be silent with no .supervisor/ up to the git root, got: $out"
  [ ! -e "$r/.supervisor" ] && ok "(j) the startup arm created no .supervisor/ of its own" \
    || no "(j) startup created a .supervisor/ directory"
}
test_startup_silent_without_supervisor_anywhere

# THE DISCRIMINATING CASE. The two guards resolve `.supervisor/` by DIFFERENT
# rules, and a subdirectory of a plugin-active repo is exactly where they
# disagree:
#   - session-resume.sh's gate is CWD-RELATIVE: `[ -d ".supervisor" ]`, false here.
#   - curation-status.sh walks up via `git rev-parse --show-toplevel`, so its own
#     `[ -d "$SUP_DIR" ]` finds the repo-root .supervisor/ and is TRUE — it would
#     happily produce a full nudge line.
# So with the hook-side guard removed, this fixture EMITS; with it present, it is
# silent. That is the semantic being pinned: the startup nudge is scoped to the
# directory Claude Code was actually opened in, not to the enclosing repo.
# Sub-fixture is deliberately given enough pending work to produce a line, so a
# silent result cannot be explained away as "nothing to say".
test_startup_silent_in_subdir_of_plugin_repo() {
  local r sub out rc ctl
  r="$(new_repo)"; make_plugin_active "$r"; make_curation_pending "$r"
  sub="$r/src/deep"
  mkdir -p "$sub"

  # Control: from the repo ROOT the same fixture DOES nudge — so the silence
  # below is attributable to the cwd, not to an empty corpus.
  ctl="$(run_hook_raw "$r" startup)"
  printf '%s\n' "$ctl" | grep -qF -- "$CURATION_MARK" \
    && ok "(j) control: the same fixture DOES nudge from the repo root" \
    || no "(j) control failed: fixture produced no nudge at the root, so the subdir case proves nothing"
  # Clear the debounce marker the control just stamped, or the subdir run would
  # be silent for the WRONG reason.
  rm -f "$r/.supervisor/.curation-nudge-shown"

  out="$(run_hook_raw "$sub" startup)"; rc="$(lastrc)"
  [ "$rc" -eq 0 ] && ok "(j) exits 0 from a subdirectory of a plugin-active repo" \
    || no "(j) expected exit 0 from a subdir, got $rc"
  if printf '%s\n' "$out" | grep -qF -- "$CURATION_MARK"; then
    no "(j) startup nudged from a SUBDIRECTORY — the cwd-relative .supervisor/ gate is gone (the probe's git-root fallback found the repo root)"
  else
    ok "(j) silent from a subdirectory of a plugin-active repo (cwd-relative gate holds)"
  fi
  [ ! -e "$sub/.supervisor" ] && ok "(j) no stray .supervisor/ created in the subdirectory" \
    || no "(j) startup created a .supervisor/ in the subdirectory"
  [ ! -e "$r/.supervisor/.curation-nudge-shown" ] \
    && ok "(j) the suppressed subdir run did NOT burn the repo's 24h debounce window" \
    || no "(j) the subdir run stamped the debounce marker despite emitting nothing"
}
test_startup_silent_in_subdir_of_plugin_repo

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
# ============================================================================
echo "== (n) System Twin store health reaches the resume digest — dark only, never healthy =="
# WHY THIS SECTION EXISTS: on 2026-09-01 the twin read path had been 100% dark since 2026-08-12 —
# 21 stored contracts, every one dropped for want of provenance after a tree-wide `sed` rewrote
# their bodies outside the sole writer. Every gate was green throughout, because a total drop was
# recorded only in .supervisor/logs/twin.log and looked to consumers exactly like an empty store.
# This hook is the surface a human actually passes, so the dark state has to show up here.
SR_TWIN_WRITE="$(cd "$(dirname "$HOOK")" && pwd)/write-system-contract.sh"
if [ ! -r "$SR_TWIN_WRITE" ]; then
  no "(n) write-system-contract.sh not found next to the hook — this section would assert nothing"
else
  # -- healthy store: the section must NOT appear (a standing banner on a working store is noise,
  #    and noise is how a real warning gets ignored).
  RN1="$(new_repo)"; make_plugin_active "$RN1"
  ( cd "$RN1" && printf 'SYSTEM_CONTRACT hotel\nsubsystem: hotel\ninvariants: [hotel reads session_end events]\n' \
      | bash "$SR_TWIN_WRITE" --subsystem "hotel" --source "session:fixture-000n" ) >/dev/null 2>&1
  if [ ! -f "$RN1/.supervisor/twin/contracts/hotel.md" ]; then
    no "(n) SEED FAILED — no contract stored; the healthy/dark contrast below would be vacuous"
  else
    ctxN1="$(run_hook_ctx "$RN1" resume)"; rcN1="$(lastrc)"
    [ "$rcN1" -eq 0 ] && ok "(n1) exits 0 on a healthy twin store" || no "(n1) expected exit 0, got $rcN1"
    if grep -q 'System Twin contract store is' <<< "$ctxN1"; then
      no "(n1) a HEALTHY store emitted a twin-health section — the warning would become background noise"
    else
      ok "(n1) a healthy store emits no twin-health section"
    fi

    # -- the incident, reproduced: rewrite the stored body in place, outside the sole writer.
    ( cd "$RN1" && f=.supervisor/twin/contracts/hotel.md && sed 's/session_end/session_end_v2/' "$f" > "$f.x" && mv "$f.x" "$f" )
    ctxN2="$(run_hook_ctx "$RN1" resume)"; rcN2="$(lastrc)"
    [ "$rcN2" -eq 0 ] && ok "(n2) still exits 0 with a dark twin store — the probe cannot fail the hook" || no "(n2) expected exit 0, got $rcN2"
    grep -q 'System Twin contract store is DARK' <<< "$ctxN2" \
      && ok "(n2) a dark store DOES surface in the resume digest — the same input that produced (n1)'s silence" \
      || no "(n2) the dark store produced no section: $(tr '\n' ' ' <<< "$ctxN2" | cut -c1-200)"
    grep -q 'twin_store_status: dark' <<< "$ctxN2" \
      && ok "(n2) and quotes the machine-readable status line with its counts" || no "(n2) status line not quoted"
    grep -q 'reprovenance-twin-contracts.sh' <<< "$ctxN2" \
      && ok "(n2) and names the sanctioned repair path rather than leaving the reader to find it" || no "(n2) repair path not named"
    grep -q 'do NOT weaken it' <<< "$ctxN2" \
      && ok "(n2) and says explicitly that the gate is not the thing to change" || no "(n2) the do-not-weaken warning is missing"
  fi

  # -- DEGRADED: one verified contract alongside one dropped. Its own branch in the hook's case
  #    statement, so it needs its own fixture — (n2) proves nothing about it, and a text branch
  #    with no test is how the repair path goes missing from the one message that needed it.
  RN4="$(new_repo)"; make_plugin_active "$RN4"
  ( cd "$RN4" \
    && printf 'SYSTEM_CONTRACT india\nsubsystem: india\ninvariants: [india reads session logs]\n'      | bash "$SR_TWIN_WRITE" --subsystem "india" --source "session:fixture-000n" \
    && printf 'SYSTEM_CONTRACT juliet\nsubsystem: juliet\ninvariants: [juliet renders dashboards]\n' | bash "$SR_TWIN_WRITE" --subsystem "juliet" --source "session:fixture-000n" ) >/dev/null 2>&1
  if [ ! -f "$RN4/.supervisor/twin/contracts/india.md" ] || [ ! -f "$RN4/.supervisor/twin/contracts/juliet.md" ]; then
    no "(n4) SEED FAILED — need two stored contracts to darken exactly one; this case would assert nothing"
  else
    ( cd "$RN4" && f=.supervisor/twin/contracts/juliet.md && sed 's/renders/draws/' "$f" > "$f.x" && mv "$f.x" "$f" )
    ctxN4="$(run_hook_ctx "$RN4" resume)"; rcN4="$(lastrc)"
    [ "$rcN4" -eq 0 ] && ok "(n4) exits 0 on a degraded twin store" || no "(n4) expected exit 0, got $rcN4"
    grep -q 'System Twin contract store is DEGRADED' <<< "$ctxN4" \
      && ok "(n4) a PARTIALLY dropped store renders the DEGRADED branch, not the DARK one" \
      || no "(n4) degraded branch not rendered: $(tr '\n' ' ' <<< "$ctxN4" | cut -c1-200)"
    grep -q 'DARK' <<< "$ctxN4" && no "(n4) a degraded store was reported as DARK — the two branches are not discriminating" || ok "(n4) and does NOT claim the store is dark"
    grep -q 'twin_store_status: degraded (emitted 1, dropped 1, stored 2)' <<< "$ctxN4" \
      && ok "(n4) and quotes the real counts (1 served, 1 withheld)" || no "(n4) degraded counts missing/wrong: $(grep -o 'twin_store_status[^\`]*' <<< "$ctxN4" | head -1)"
    grep -q 'reprovenance-twin-contracts.sh' <<< "$ctxN4" \
      && ok "(n4) and still names the repair path — the branch a reader is most likely to skim" || no "(n4) degraded branch omits the repair path"
  fi

  # -- a repo with NO twin store at all must be byte-for-byte unaffected: this is the state the
  #    dark store was indistinguishable from, so it is the control that keeps (n2) honest.
  RN3="$(new_repo)"; make_plugin_active "$RN3"
  ctxN3="$(run_hook_ctx "$RN3" resume)"
  if grep -q 'System Twin contract store is' <<< "$ctxN3"; then
    no "(n3) a repo with no twin store emitted a twin-health section"
  else
    ok "(n3) a repo with no twin store is untouched — the probe costs one glob and says nothing"
  fi
fi

echo
# ============================================================================
# Stranded-brief line on the STARTUP arm — groups (o)–(v) (v15.64.0).
#
# WHY: on 2026-09-05 a merged brief sat in .supervisor/jobs/in-progress/ for five
# days because the reconciler fired only on resume|clear|compact — the session
# WITH prior context — and every fresh session was silent. The startup arm now
# composes the stranded line with the curation line into ONE envelope, and the
# groups below pin each obligation the header's SEAM NOTE names.
STRANDED_MARK="**Stranded brief:**"
STRANDED_BRIEF_LINE="**Stranded brief:** .supervisor/jobs/in-progress/b.md"
STRANDED_MARKER=".supervisor/.stranded-nudge-shown"
SECTION1_STRANDED_HDR="### Stranded briefs — lifecycle move never ran (NOT resumable)"
SECTION1_UNVERIFIED_HDR="### In-progress briefs (state UNVERIFIED — reconciler unavailable)"

# make_stranded_fixture <repo> — requirement stamped done + a brief pointing at
# it ⇒ reconcile-jobs.sh classifies `stranded_closed` (the same load-bearing
# shape as test-reconcile-jobs.sh case 3; this one is additionally `git init`'d
# by new_repo, which the reconciler does not need). $2 overrides the stamp so the
# same shape yields `unknown` (pending) for the unknown-only fixture.
make_stranded_fixture() {
  local r="$1" stamp="${2:-done}"
  mkdir -p "$r/.supervisor/requirements" "$r/.supervisor/jobs/in-progress"
  printf '# req\n\n## Status: %s\n' "$stamp" > "$r/.supervisor/requirements/req.md"
  printf '# Supervisor Job: b\n\n## Environment\n- **Source requirement:** .supervisor/requirements/req.md\n' \
    > "$r/.supervisor/jobs/in-progress/b.md"
}
make_unknown_only_fixture() { make_stranded_fixture "$1" pending; }

# Two copied-hook shapes, deliberately distinct:
#   copy_hook_sparse <dir> — the hook ALONE. Every sibling absent (curation line
#     empty, reconciler absent unless the group places its own stub). For the
#     fail-safe groups.
#   copy_hook_full <dir>   — the hook + the REAL siblings curation-status.sh,
#     reconcile-jobs.sh AND brief-pointer.sh, so ONLY the hook body differs from
#     production. For the MUTANT groups: reconcile-jobs.sh sources brief-pointer.sh
#     from its own dirname and stubs the pointer readers to `return 1` when it is
#     absent, so a reconciler copied alone classifies EVERY brief `unknown` — a
#     red mutant would then be red for the wrong reason.
copy_hook_sparse() { cp "$HOOK" "$1/session-resume.sh"; }
copy_hook_full() {
  copy_hook_sparse "$1"
  cp "$SCRIPT_DIR/curation-status.sh" "$SCRIPT_DIR/reconcile-jobs.sh" "$SCRIPT_DIR/brief-pointer.sh" "$1/"
}
# run_alt_hook_raw <hook> <repo> <src> [env assignments...] — like run_hook_raw
# but for a copied hook; stderr is captured to ERRFILE, rc to RCFILE.
ERRFILE="$ROOT/.last-err"
lasterr() { cat "$ERRFILE" 2>/dev/null; }
run_alt_hook_raw() {
  local hook="$1" repo="$2" src="$3" out rc
  shift 3
  out="$( cd "$repo" && printf '{"source":"%s"}' "$src" | env "$@" bash "$hook" 2>"$ERRFILE" )"
  rc=$?
  printf '%s' "$rc" > "$RCFILE"
  printf '%s' "$out"
}
ctx_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true; }
json_docs() { printf '%s' "$1" | jq -s 'length' 2>/dev/null || printf '0'; }

# gate_mutant <original> <mutant> <label> — every mutant is gated BEFORE its red
# is trusted (lesson from PR #208): non-empty, byte-different, `bash -n` clean.
# Returns 1 if any gate fails so the caller can skip the assertions that depend
# on it rather than count a broken mutant as a targeted revert.
gate_mutant() {
  local orig="$1" mut="$2" label="$3" okk=1
  [ -s "$mut" ] && ok "$label mutant is non-empty" || { no "$label mutant is EMPTY"; okk=0; }
  if cmp -s "$orig" "$mut"; then no "$label mutant is byte-identical to the original"; okk=0
  else ok "$label mutant is byte-different from the original"; fi
  bash -n "$mut" 2>/dev/null && ok "$label mutant parses (bash -n)" || { no "$label mutant does not parse"; okk=0; }
  [ "$okk" -eq 1 ]
}

# The pre-change arm's EXACT formula for a curation-only startup, computed
# independently of the hook. Mirrors the hook's `line="$(…)"` capture (which
# strips the trailing newline curation-status.sh prints) — piping the probe
# straight into jq would keep that newline and cmp-FAIL against the UNCHANGED
# hook. Run BEFORE the hook on the same repo (the probe stamps nothing; the hook
# stamps the debounce marker on first emit).
expected_curation_only_envelope() {
  local r="$1"
  ( cd "$r" && printf '%s' "$(bash "$SCRIPT_DIR/curation-status.sh" nudge 2>/dev/null)" \
      | { iconv -c -f UTF-8 -t UTF-8 2>/dev/null || cat; } \
      | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}' )
}

# ---------------------------------------------------------------------------
echo "== (o) the stranded line FIRES on source=startup — ONE envelope, parsed field =="
test_stranded_fires_on_startup() {
  local r out rc ctx
  r="$(new_repo)"; make_plugin_active "$r"; make_stranded_fixture "$r"
  out="$(run_hook_raw "$r" startup)"; rc="$(lastrc)"
  [ "$rc" -eq 0 ] && ok "(o) exits 0" || no "(o) expected exit 0, got $rc"
  [ "$(json_docs "$out")" = "1" ] \
    && ok "(o) stdout is exactly ONE JSON document (jq -s length == 1; jq -e alone accepts a stream)" \
    || no "(o) stdout is not exactly one JSON document: $(json_docs "$out") — $out"
  [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null)" = "SessionStart" ] \
    && ok "(o) hookEventName == SessionStart" || no "(o) hookEventName missing/wrong"
  ctx="$(ctx_of "$out")"
  grep -qF -- "$STRANDED_BRIEF_LINE" <<< "$ctx" \
    && ok "(o) additionalContext names the stranded brief" \
    || no "(o) additionalContext lacks '$STRANDED_BRIEF_LINE': $ctx"
  grep -qF -- "stamped" <<< "$ctx" \
    && ok "(o) additionalContext carries the porcelain row's evidence ('stamped')" \
    || no "(o) evidence substring 'stamped' missing: $ctx"
  grep -qF -- "--repair" <<< "$ctx" \
    && ok "(o) additionalContext carries the --repair trailer" \
    || no "(o) --repair trailer missing: $ctx"
  grep -qF -- "Not resumable" <<< "$ctx" \
    && ok "(o) the trailer says NOT resumable (classification, never a completion claim)" \
    || no "(o) 'Not resumable' wording missing: $ctx"
}
test_stranded_fires_on_startup

# ---------------------------------------------------------------------------
echo "== (p) byte-identical when nothing is stranded: (a) empty (b) curation-only cmp (c) unknown-only =="
test_stranded_byte_identical_when_none() {
  local ra rb rc1 outa outb outc expf gotf rcx
  # (a) nothing pending at all ⇒ ZERO bytes.
  ra="$(new_repo)"; make_plugin_active "$ra"
  outa="$(run_hook_raw "$ra" startup)"; rcx="$(lastrc)"
  [ "$rcx" -eq 0 ] && [ -z "$outa" ] && ok "(p-a) no briefs + no curation ⇒ zero bytes, rc 0" \
    || no "(p-a) expected zero bytes rc 0, got rc=$rcx out=$outa"
  [ ! -e "$ra/$STRANDED_MARKER" ] && ok "(p-a) no stranded marker written" || no "(p-a) stranded marker written on a silent run"

  # (b) curation pending, no briefs ⇒ cmp-identical to the pre-change formula.
  rb="$(new_repo)"; make_plugin_active "$rb"; make_curation_pending "$rb"
  expf="$ROOT/p-expected.json"; gotf="$ROOT/p-got.json"
  expected_curation_only_envelope "$rb" > "$expf"
  ( cd "$rb" && printf '{"source":"startup"}' | bash "$HOOK" ) > "$gotf"; rcx=$?
  [ "$rcx" -eq 0 ] && ok "(p-b) exits 0" || no "(p-b) expected exit 0, got $rcx"
  [ -s "$expf" ] && [ -s "$gotf" ] && ok "(p-b) both the expected and the actual envelope are non-empty" \
    || no "(p-b) a silent pair would be a false match: expected=$(wc -c < "$expf") got=$(wc -c < "$gotf")"
  if cmp -s "$expf" "$gotf"; then ok "(p-b) curation-only startup is cmp-identical to the pre-change formula"
  else no "(p-b) curation-only startup DIFFERS from the pre-change formula"; diff "$expf" "$gotf" | head -5; fi
  [ ! -e "$rb/$STRANDED_MARKER" ] && ok "(p-b) no stranded marker written" || no "(p-b) stranded marker written with nothing stranded"

  # (b') true captured baseline: origin/main's hook next to the real siblings,
  # each hook on its OWN fresh curation-pending repo (the first emit stamps the
  # curation marker, so a second run on the same repo is a false-green empty).
  local old="$ROOT/baseline"; mkdir -p "$old"
  local giterr="$ROOT/baseline.giterr" oldout newout ro rn
  if git -C "$SCRIPT_DIR/../.." show origin/main:loomwright/scripts/session-resume.sh > "$old/session-resume.sh" 2>"$giterr" \
     && [ -s "$old/session-resume.sh" ]; then
    cp "$SCRIPT_DIR/curation-status.sh" "$SCRIPT_DIR/reconcile-jobs.sh" "$SCRIPT_DIR/brief-pointer.sh" "$old/"
    ro="$(new_repo)"; make_plugin_active "$ro"; make_curation_pending "$ro"
    rn="$(new_repo)"; make_plugin_active "$rn"; make_curation_pending "$rn"
    oldout="$(run_alt_hook_raw "$old/session-resume.sh" "$ro" startup)"
    newout="$(run_hook_raw "$rn" startup)"
    if [ -n "$oldout" ] && [ -n "$newout" ]; then
      ok "(p-b') baseline and current both emitted (a silent pair is not a match)"
      printf '%s' "$oldout" > "$ROOT/p-old.json"; printf '%s' "$newout" > "$ROOT/p-new.json"
      cmp -s "$ROOT/p-old.json" "$ROOT/p-new.json" \
        && ok "(p-b') curation-only startup is cmp-identical to the captured origin/main hook" \
        || no "(p-b') curation-only startup DIFFERS from the captured origin/main hook"
    else
      no "(p-b') a silent pair: old=${#oldout} new=${#newout} bytes"
    fi
  else
    echo "  skipped: origin/main unavailable ($(tr '\n' ' ' < "$giterr" | cut -c1-160))"
  fi

  # (c) unknown-only: brief present, requirement NOT stamped ⇒ silent on startup.
  rc1="$(new_repo)"; make_plugin_active "$rc1"; make_unknown_only_fixture "$rc1"
  outc="$(run_hook_raw "$rc1" startup)"; rcx="$(lastrc)"
  [ "$rcx" -eq 0 ] && [ -z "$outc" ] && ok "(p-c) unknown-only fixture ⇒ zero bytes on startup (unknown is NOT reported there)" \
    || no "(p-c) unknown-only fixture should be silent on startup, got rc=$rcx out=$outc"
  [ ! -e "$rc1/$STRANDED_MARKER" ] && ok "(p-c) no stranded marker written" || no "(p-c) stranded marker written for an unknown-only repo"
}
test_stranded_byte_identical_when_none

# ---------------------------------------------------------------------------
echo "== (q) no .supervisor/ ⇒ silent; LOOMWRIGHT_STRANDED_NUDGE opt-out; 24h debounce =="
test_stranded_gate_optout_debounce() {
  local r out rc optout r2 c1 c2 c3
  # AC-3: the fixture FILES with no .supervisor/ directory around them.
  r="$(new_repo)"
  mkdir -p "$r/jobs/in-progress"
  printf '# Supervisor Job: b\n\n- **Source requirement:** .supervisor/requirements/req.md\n' > "$r/jobs/in-progress/b.md"
  rm -rf "$r/.supervisor"
  out="$(run_hook_raw "$r" startup)"; rc="$(lastrc)"
  [ "$rc" -eq 0 ] && [ -z "$out" ] && ok "(q) no .supervisor/ ⇒ zero bytes, rc 0 (the helper's OWN gate, above the shared bail)" \
    || no "(q) expected silence with no .supervisor/, got rc=$rc out=$out"
  [ ! -e "$r/.supervisor" ] && ok "(q) created no .supervisor/ of its own" || no "(q) created a .supervisor/"

  # AC-9(a): opt-out values silence and stamp nothing.
  r2="$(new_repo)"; make_plugin_active "$r2"; make_stranded_fixture "$r2"
  for optout in 0 off false no; do
    out="$( cd "$r2" && printf '{"source":"startup"}' | LOOMWRIGHT_STRANDED_NUDGE="$optout" bash "$HOOK" )"; rc=$?
    [ "$rc" -eq 0 ] && [ -z "$out" ] && ok "(q) LOOMWRIGHT_STRANDED_NUDGE=$optout ⇒ silent, rc 0" \
      || no "(q) opt-out=$optout should silence, got rc=$rc out=$out"
    [ ! -e "$r2/$STRANDED_MARKER" ] && ok "(q) opt-out=$optout stamped no marker" || no "(q) opt-out=$optout stamped the marker"
  done
  # AC-9(b): control — first sighting is never suppressed; marker now exists.
  c1="$(run_hook_ctx "$r2" startup)"
  grep -qF -- "$STRANDED_MARK" <<< "$c1" \
    && ok "(q) control — same repo emits the line without the opt-out (first sighting never suppressed)" \
    || no "(q) control — repo should emit once the opt-out is removed: $c1"
  [ -f "$r2/$STRANDED_MARKER" ] && ok "(q) marker $STRANDED_MARKER now exists" || no "(q) marker missing after an emit"
  # AC-9(c): immediate second run is debounced.
  c2="$(run_hook_raw "$r2" startup)"
  [ -z "$c2" ] && ok "(q) immediate second run emits nothing (24h debounce)" || no "(q) second run should be debounced: $c2"
  # AC-9(d): age the marker to a fixed past stamp ⇒ fires again, marker refreshed.
  touch -t 202001010000 "$r2/$STRANDED_MARKER"
  c3="$(run_hook_ctx "$r2" startup)"
  grep -qF -- "$STRANDED_MARK" <<< "$c3" \
    && ok "(q) after the marker is aged past 24h the line fires again" \
    || no "(q) aged marker should re-enable the line: $c3"
  [ -n "$(find "$r2/$STRANDED_MARKER" -mmin -1440 2>/dev/null)" ] \
    && ok "(q) the marker was refreshed on re-emit" || no "(q) the marker was not refreshed"
}
test_stranded_gate_optout_debounce

# ---------------------------------------------------------------------------
echo "== (r) the gate is NOT widened — every other section asserted absent, one at a time =="
# make_every_other_section_input <repo> — the stranded fixture PLUS every input
# that makes each other section of the hook non-empty on resume.
make_every_other_section_input() {
  local r="$1"
  make_stranded_fixture "$r"
  mkdir -p "$r/.supervisor/jobs/failed" "$r/.supervisor/twin/contracts" "$r/.supervisor/logs" "$r/.supervisor/autonomous/run1"
  echo "state tail" > "$r/.supervisor/state.md"
  echo "brief" > "$r/.supervisor/jobs/failed/f.md"
  echo "not a provenanced contract" > "$r/.supervisor/twin/contracts/x.md"
  echo '{"event":"session_end"}' > "$r/.supervisor/logs/s1.jsonl"
  echo '{"iteration":1}' > "$r/.supervisor/autonomous/run1/state.json"
  rm -rf "$r/.agent/rules"
}
# assert_startup_absence_set <label> <ctx> — the per-item absence checks, shared
# with the mutant run in (v) so the mutant is held to the same set.
assert_startup_absence_set() {
  local label="$1" ctx="$2" probe
  for probe in "prior-session context" "$SECTION1_STRANDED_HDR" "In-progress briefs" "Recent failed briefs" \
               "System Twin contract store" "Last 5 lines of .supervisor/state.md" "Last 3 entries from" \
               "Active /autonomous sessions" "Recovery hints" "### House rules" "$NUDGE_LINE" "notify-desktop.sh"; do
    if grep -qF -- "$probe" <<< "$ctx"; then no "$label startup output must NOT contain '$probe'"
    else ok "$label absent: '$probe'"; fi
  done
}
test_stranded_gate_not_widened() {
  local r out rc ctx fakehome shim
  r="$(new_repo)"; make_plugin_active "$r"; make_every_other_section_input "$r"
  fakehome="$ROOT/fakehome-r"; make_unreachable_telemetry_home "$fakehome"
  shim="$(make_curl_shim)"
  out="$( cd "$r" && printf '{"source":"startup"}' | HOME="$fakehome" PATH="$shim:$PATH" bash "$HOOK" )"; rc=$?
  [ "$rc" -eq 0 ] && ok "(r) exits 0" || no "(r) expected exit 0, got $rc"
  ctx="$(ctx_of "$out")"
  grep -qF -- "$STRANDED_MARK" <<< "$ctx" \
    && ok "(r) control — the stranded line IS present, so the absence checks are not vacuous" \
    || no "(r) control failed: no stranded line, the absence checks prove nothing: $out"
  assert_startup_absence_set "(r)" "$ctx"
  [ ! -e "$(curl_shim_called_marker)" ] && ok "(r) curl shim was NOT invoked (observability probe never ran)" \
    || no "(r) curl was invoked on the startup path"
  [ ! -e "$(obs_warned_marker "$fakehome")" ] && ok "(r) observability .last-warned marker does NOT exist under the fake HOME" \
    || no "(r) the observability probe stamped its marker on startup"
}
test_stranded_gate_not_widened

# ---------------------------------------------------------------------------
echo "== (s) the resume path is UNCHANGED — Section 1 wording, never the startup wording =="
test_stranded_resume_unchanged() {
  local r ctx d out
  r="$(new_repo)"; make_plugin_active "$r"; make_stranded_fixture "$r"
  ctx="$(run_hook_ctx "$r" resume)"
  grep -qF -- "$SECTION1_STRANDED_HDR" <<< "$ctx" \
    && ok "(s) resume carries the Section-1 stranded header" || no "(s) Section-1 stranded header missing on resume: $ctx"
  grep -qF -- "--repair" <<< "$ctx" && ok "(s) resume carries the --repair instruction" || no "(s) --repair missing on resume"
  grep -qF -- "$STRANDED_MARK" <<< "$ctx" \
    && no "(s) the startup wording leaked into the resume path" || ok "(s) the startup wording does NOT appear on resume"
  # Sparse copy (no reconcile-jobs.sh) ⇒ resume falls back to the neutral header.
  d="$(mktmp)"; copy_hook_sparse "$d"
  r="$(new_repo)"; make_plugin_active "$r"; make_stranded_fixture "$r"
  out="$(run_alt_hook_raw "$d/session-resume.sh" "$r" resume)"
  grep -qF -- "$SECTION1_UNVERIFIED_HDR" <<< "$(ctx_of "$out")" \
    && ok "(s) with the reconciler ABSENT, resume still emits the neutral UNVERIFIED fallback header" \
    || no "(s) neutral fallback header missing with the reconciler absent: $out"
}
test_stranded_resume_unchanged

# ---------------------------------------------------------------------------
echo "== (t) helpers are reachable from the startup arm — static, dynamic, and a moved-definition mutant =="
test_stranded_helper_reachable() {
  local l_helper l_emit l_case r out rc err d mut
  l_helper="$(awk '/^stranded_briefs_startup_line\(\) \{/ {print NR; exit}' "$HOOK")"
  l_emit="$(awk '/^startup_arm_emit\(\) \{/ {print NR; exit}' "$HOOK")"
  l_case="$(awk '/^case "\$SOURCE" in/ {print NR; exit}' "$HOOK")"
  [ -n "$l_helper" ] && [ -n "$l_emit" ] && [ -n "$l_case" ] \
    && ok "(t) static: found the two definitions and the case line ($l_helper / $l_emit / $l_case)" \
    || no "(t) static: could not locate helper=$l_helper emit=$l_emit case=$l_case"
  [ -n "$l_helper" ] && [ -n "$l_case" ] && [ "$l_helper" -lt "$l_case" ] \
    && ok "(t) static: stranded_briefs_startup_line is defined ABOVE the case" || no "(t) static: helper defined below the case"
  [ -n "$l_emit" ] && [ -n "$l_case" ] && [ "$l_emit" -lt "$l_case" ] \
    && ok "(t) static: startup_arm_emit is defined ABOVE the case" || no "(t) static: composer defined below the case"

  # Dynamic: a helper defined below the case prints `command not found` on stderr
  # before the arm's `exit 0` swallows rc 127 — so stderr must be EMPTY.
  r="$(new_repo)"; make_plugin_active "$r"; make_stranded_fixture "$r"
  out="$(run_alt_hook_raw "$HOOK" "$r" startup)"; rc="$(lastrc)"; err="$(lasterr)"
  [ "$rc" -eq 0 ] && ok "(t) dynamic: rc 0" || no "(t) dynamic: rc $rc"
  [ -z "$err" ] && ok "(t) dynamic: stderr is EMPTY on the stranded fixture" || no "(t) dynamic: stderr not empty: $err"
  grep -qF -- "$STRANDED_MARK" <<< "$(ctx_of "$out")" && ok "(t) dynamic: control — the line emitted" || no "(t) dynamic: control failed"

  # Mutant: move the stranded_briefs_startup_line DEFINITION to after `esac`.
  d="$(mktmp)"; copy_hook_full "$d"; mut="$d/session-resume.sh"
  awk '
    /^stranded_briefs_startup_line\(\) \{/ { inblk=1 }
    inblk { buf = buf $0 "\n"; if ($0 ~ /^\}$/) { inblk=0 }; next }
    { print }
    /^esac$/ && !moved { printf "%s", buf; moved=1 }
  ' "$HOOK" > "$mut"
  if gate_mutant "$HOOK" "$mut" "(t)"; then
    r="$(new_repo)"; make_plugin_active "$r"; make_stranded_fixture "$r"
    out="$(run_alt_hook_raw "$mut" "$r" startup)"; rc="$(lastrc)"; err="$(lasterr)"
    [ "$rc" -eq 0 ] && ok "(t) mutant: rc is STILL 0 (the exit 0 swallows rc 127 — which is exactly why stderr is the check)" \
      || no "(t) mutant: rc $rc"
    grep -q "command not found" <<< "$err" \
      && ok "(t) mutant: stderr contains 'command not found' — the dynamic check goes RED for a below-the-case helper" \
      || no "(t) mutant: expected 'command not found' on stderr, got: $err"
    grep -qF -- "$STRANDED_MARK" <<< "$(ctx_of "$out")" \
      && no "(t) mutant: the line was emitted from a below-the-case definition (mutant is not what it claims)" \
      || ok "(t) mutant: no stranded line emitted"
  fi
}
test_stranded_helper_reachable

# ---------------------------------------------------------------------------
echo "== (u) offline (gh never called) + four fail-safe reconciler degradations =="
test_stranded_offline_and_failsafe() {
  local r shim out rc d ctx
  # AC-7: a gh stub that records any call and fails loudly.
  shim="$ROOT/gh-shim"; mkdir -p "$shim"; rm -f "$ROOT/gh-called"
  printf '#!/bin/sh\n: > "%s/gh-called"\nexit 99\n' "$ROOT" > "$shim/gh"; chmod +x "$shim/gh"
  r="$(new_repo)"; make_plugin_active "$r"; make_stranded_fixture "$r"
  out="$( cd "$r" && printf '{"source":"startup"}' | PATH="$shim:$PATH" bash "$HOOK" )"; rc=$?
  [ "$rc" -eq 0 ] && ok "(u) exits 0 with a gh stub on PATH" || no "(u) rc $rc with gh stub"
  grep -qF -- "$STRANDED_MARK" <<< "$(ctx_of "$out")" && ok "(u) control — the line emitted with gh stubbed" \
    || no "(u) control failed with gh stubbed: $out"
  [ ! -e "$ROOT/gh-called" ] && ok "(u) gh was NEVER called on the startup path (offline by construction)" \
    || no "(u) the startup arm called gh"

  # AC-8: sparse copies, one degradation each. Each must emit ZERO bytes, rc 0,
  # and write no marker. curation-status.sh is absent in every sparse dir, so the
  # curation half is empty there too — which is itself the fail-safe path.
  failsafe_case() {
    local label="$1" prep="$2" dd rr oo rcc
    dd="$(mktmp)"; copy_hook_sparse "$dd"
    eval "$prep"
    rr="$(new_repo)"; make_plugin_active "$rr"; make_stranded_fixture "$rr"
    oo="$(run_alt_hook_raw "$dd/session-resume.sh" "$rr" startup)"; rcc="$(lastrc)"
    [ "$rcc" -eq 0 ] && ok "(u-$label) rc 0" || no "(u-$label) rc $rcc"
    [ -z "$oo" ] && ok "(u-$label) zero bytes on stdout" || no "(u-$label) expected silence, got: $oo"
    [ ! -e "$rr/$STRANDED_MARKER" ] && ok "(u-$label) no marker written" || no "(u-$label) marker written on a degraded run"
  }
  failsafe_case "i-absent" ':'
  # (ii) present but chmod 000 — premise probe: if reads are still allowed
  # (e.g. root), the case cannot be exercised here and is neither ok nor fail.
  d="$(mktmp)"; printf '#!/bin/sh\nexit 0\n' > "$d/probe"; chmod 000 "$d/probe"
  if [ -r "$d/probe" ]; then
    echo "  skipped: chmod 000 does not deny reads here"
  else
    failsafe_case "ii-unreadable" 'printf "#!/bin/sh\nexit 0\n" > "$dd/reconcile-jobs.sh"; chmod 000 "$dd/reconcile-jobs.sh"'
  fi
  failsafe_case "iii-exit3-junk-stderr" 'printf "#!/bin/sh\necho junk-on-stderr >&2\nexit 3\n" > "$dd/reconcile-jobs.sh"; chmod +x "$dd/reconcile-jobs.sh"'
  failsafe_case "iv-exit0-silent" 'printf "#!/bin/sh\nexit 0\n" > "$dd/reconcile-jobs.sh"; chmod +x "$dd/reconcile-jobs.sh"'
}
test_stranded_offline_and_failsafe

# ---------------------------------------------------------------------------
echo "== (v) mutation control (call removed ⇒ AC-1 red, everything else green) + ONE composed envelope =="
test_stranded_mutation_control() {
  local d mut r out ctx rc expf gotf
  d="$(mktmp)"; copy_hook_full "$d"; mut="$d/session-resume.sh"
  # The targeted revert: drop the CALL to stranded_briefs_startup_line inside
  # startup_arm_emit. The composer initialises `stranded=""`, so the mutant is
  # otherwise the pre-change arm.
  grep -v '^  stranded="\$(stranded_briefs_startup_line)"$' "$HOOK" > "$mut"
  if gate_mutant "$HOOK" "$mut" "(v)"; then
    grep -q 'stranded="\$(stranded_briefs_startup_line)"' "$mut" \
      && no "(v) the call line survived in the mutant" || ok "(v) the mutant no longer calls stranded_briefs_startup_line"
    # POSITIVE gate: the mutant still emits the curation line — a merely broken
    # hook cannot pass for a targeted revert.
    r="$(new_repo)"; make_plugin_active "$r"; make_curation_pending "$r"
    out="$(run_alt_hook_raw "$mut" "$r" startup)"
    if grep -qF -- "$CURATION_MARK" <<< "$(ctx_of "$out")"; then
      ok "(v) positive gate: the mutant still emits the curation line on the curation-pending fixture"
      # AC-1 must go RED against the mutant.
      r="$(new_repo)"; make_plugin_active "$r"; make_stranded_fixture "$r"
      out="$(run_alt_hook_raw "$mut" "$r" startup)"; rc="$(lastrc)"
      grep -qF -- "$STRANDED_MARK" <<< "$(ctx_of "$out")" \
        && no "(v) AC-1 stayed GREEN against the mutant — the suite would pass with the feature removed" \
        || ok "(v) AC-1 goes RED against the mutant (no stranded line)"
      [ "$rc" -eq 0 ] && ok "(v) mutant rc 0" || no "(v) mutant rc $rc"
      # ...while every other startup/resume invariant stays GREEN against it.
      r="$(new_repo)"; make_plugin_active "$r"
      out="$(run_alt_hook_raw "$mut" "$r" startup)"
      [ -z "$out" ] && ok "(v) AC-2(a) green against the mutant" || no "(v) AC-2(a) red against the mutant: $out"
      r="$(new_repo)"; make_plugin_active "$r"; make_curation_pending "$r"
      expf="$ROOT/v-expected.json"; gotf="$ROOT/v-got.json"
      expected_curation_only_envelope "$r" > "$expf"
      ( cd "$r" && printf '{"source":"startup"}' | bash "$mut" 2>/dev/null ) > "$gotf"
      [ -s "$expf" ] && [ -s "$gotf" ] && cmp -s "$expf" "$gotf" \
        && ok "(v) AC-2(b) green against the mutant (cmp-identical to the formula)" || no "(v) AC-2(b) red against the mutant"
      r="$(new_repo)"; make_plugin_active "$r"; make_unknown_only_fixture "$r"
      out="$(run_alt_hook_raw "$mut" "$r" startup)"
      [ -z "$out" ] && ok "(v) AC-2(c) green against the mutant" || no "(v) AC-2(c) red against the mutant: $out"
      r="$(new_repo)"
      out="$(run_alt_hook_raw "$mut" "$r" startup)"
      [ -z "$out" ] && ok "(v) AC-3 green against the mutant" || no "(v) AC-3 red against the mutant: $out"
      r="$(new_repo)"; make_plugin_active "$r"; make_every_other_section_input "$r"
      out="$(run_alt_hook_raw "$mut" "$r" startup)"
      assert_startup_absence_set "(v/AC-4)" "$(ctx_of "$out")"
      r="$(new_repo)"; make_plugin_active "$r"; make_stranded_fixture "$r"
      ctx="$(ctx_of "$(run_alt_hook_raw "$mut" "$r" resume)")"
      grep -qF -- "$SECTION1_STRANDED_HDR" <<< "$ctx" \
        && ok "(v) AC-5 green against the mutant (Section-1 stranded header on resume — real siblings present)" \
        || no "(v) AC-5 red against the mutant: $ctx"
      grep -qF -- "$SECTION1_UNVERIFIED_HDR" <<< "$ctx" \
        && no "(v) AC-5: the mutant dir's reconciler classified UNVERIFIED — brief-pointer.sh missing from the mutant dir?" \
        || ok "(v) AC-5: not the UNVERIFIED fallback (the mutant dir carries the real siblings)"
    else
      no "(v) positive gate failed: the mutant does not emit the curation line, so it is merely broken — not a targeted revert"
    fi
  fi

  # AC-13: both halves compose into ONE envelope, curation first, one \n between.
  r="$(new_repo)"; make_plugin_active "$r"; make_stranded_fixture "$r"; make_curation_pending "$r"
  out="$(run_hook_raw "$r" startup)"; rc="$(lastrc)"
  [ "$rc" -eq 0 ] && ok "(v/AC-13) exits 0" || no "(v/AC-13) rc $rc"
  [ "$(json_docs "$out")" = "1" ] && ok "(v/AC-13) exactly ONE JSON document on stdout" \
    || no "(v/AC-13) expected one JSON document, got $(json_docs "$out")"
  ctx="$(ctx_of "$out")"
  case "$ctx" in
    "**Curation cadence:**"*) ok "(v/AC-13) additionalContext STARTS with the curation line" ;;
    *) no "(v/AC-13) additionalContext does not start with the curation line: $(printf '%s' "$ctx" | head -c 80)" ;;
  esac
  # Exactly one \n between the halves: the char right before the stranded mark
  # is a newline and the one before THAT is not.
  local before="${ctx%%\*\*Stranded brief:\*\**}"
  [ "${#before}" -lt "${#ctx}" ] && ok "(v/AC-13) the stranded line is present after the curation line" \
    || no "(v/AC-13) stranded line missing from the composed envelope: $ctx"
  case "$before" in
    *$'\n\n') no "(v/AC-13) TWO newlines separate the halves (mis-join)" ;;
    *$'\n')   ok "(v/AC-13) exactly ONE newline separates the curation line from the stranded line" ;;
    *)        no "(v/AC-13) no newline between the halves: $(printf '%s' "$before" | tail -c 40)" ;;
  esac

  # Empty-LEFT-side composition: real reconciler, NO curation-status.sh ⇒ the
  # envelope is the stranded line alone, with no leading separator.
  d="$(mktmp)"; copy_hook_sparse "$d"; cp "$SCRIPT_DIR/reconcile-jobs.sh" "$SCRIPT_DIR/brief-pointer.sh" "$d/"
  r="$(new_repo)"; make_plugin_active "$r"; make_stranded_fixture "$r"; make_curation_pending "$r"
  out="$(run_alt_hook_raw "$d/session-resume.sh" "$r" startup)"
  ctx="$(ctx_of "$out")"
  [ "$(json_docs "$out")" = "1" ] && ok "(v/left-empty) one JSON document with the curation probe absent" \
    || no "(v/left-empty) expected one JSON document: $out"
  case "$ctx" in
    "**Stranded brief:**"*) ok "(v/left-empty) additionalContext starts with the stranded line — no leading separator when the curation half is empty" ;;
    *) no "(v/left-empty) unexpected leading bytes: $(printf '%s' "$ctx" | head -c 60)" ;;
  esac
  grep -qF -- "$CURATION_MARK" <<< "$ctx" && no "(v/left-empty) curation line present without its probe" \
    || ok "(v/left-empty) curation half empty (probe absent is fail-safe)"
}
test_stranded_mutation_control

# ---------------------------------------------------------------------------
echo "== (w) orphaned-worktrees section fires on startup AND resume when the sibling reports a row =="
ORPHAN_HDR="### Orphaned worktrees (advisory)"
ORPHAN_ROW_PATH="/tmp/example-project-BD-15a"
# stub_auditor <dir> <rows|""> — a sibling worktree-audit.sh whose `report` prints
# exactly the given rows (or nothing). Everything else is a no-op.
stub_auditor() {
  printf '#!/usr/bin/env bash\ncase "${1:-}" in report) printf %%s "%s" ;; esac\nexit 0\n' "$2" > "$1/worktree-audit.sh"
}
ORPHAN_ROW="$(printf 'orphan\t%s\tfeature/BD-15a\t2026-09-11T12:00:00Z\t00893aaf-4c1e-4f6b-9a2d-1b3c5d7e9f01\n' "$ORPHAN_ROW_PATH")"
test_orphans_fire() {
  local d r out ctx arm
  d="$(mktmp)"; copy_hook_full "$d"; stub_auditor "$d" "$ORPHAN_ROW"
  for arm in startup resume; do
    r="$(new_repo)"; make_plugin_active "$r"
    out="$(run_alt_hook_raw "$d/session-resume.sh" "$r" "$arm")"
    [ "$(lastrc)" -eq 0 ] && ok "(w) $arm exits 0" || no "(w) $arm rc $(lastrc)"
    [ "$(json_docs "$out")" = "1" ] && ok "(w) $arm: exactly ONE JSON document" || no "(w) $arm: $(json_docs "$out") documents"
    ctx="$(ctx_of "$out")"
    grep -qF -- "$ORPHAN_HDR" <<< "$ctx" && ok "(w) $arm carries the orphaned-worktrees header" || no "(w) $arm header missing: $ctx"
    grep -qF -- "- $ORPHAN_ROW_PATH (branch: feature/BD-15a" <<< "$ctx" && ok "(w) $arm carries the row's path + branch" || no "(w) $arm row missing: $ctx"
    grep -qF -- 'git worktree remove <path>' <<< "$ctx" && ok "(w) $arm carries the by-hand hint" || no "(w) $arm hint missing"
    grep -qF -- 'nothing here removes anything' <<< "$ctx" && ok "(w) $arm says it removes nothing" || no "(w) $arm removal disclaimer missing"
  done
}
test_orphans_fire

# ---------------------------------------------------------------------------
echo "== (x) empty report / sibling absent ⇒ byte-identical startup, no header on either arm =="
test_orphans_silent() {
  local d r out ctx expf gotf rcx variant
  for variant in empty-report sibling-absent; do
    d="$(mktmp)"; copy_hook_full "$d"
    [ "$variant" = "empty-report" ] && stub_auditor "$d" ""
    # STARTUP: cmp against the independent pre-change formula.
    r="$(new_repo)"; make_plugin_active "$r"; make_curation_pending "$r"
    expf="$ROOT/x-exp-$variant.json"; gotf="$ROOT/x-got-$variant.json"
    expected_curation_only_envelope "$r" > "$expf"
    # Run directly (not via the $(…)-capturing helper) so jq's trailing newline survives for cmp.
    ( cd "$r" && printf '{"source":"startup"}' | bash "$d/session-resume.sh" 2>/dev/null ) > "$gotf"; rcx=$?
    [ "$rcx" -eq 0 ] && ok "(x/$variant) startup exits 0" || no "(x/$variant) startup rc $rcx"
    [ -s "$expf" ] && [ -s "$gotf" ] && ok "(x/$variant) both envelopes non-empty (a silent pair is not a match)" || no "(x/$variant) silent pair"
    cmp -s "$expf" "$gotf" && ok "(x/$variant) startup is cmp-identical to expected_curation_only_envelope" \
      || { no "(x/$variant) startup DIFFERS from the pre-change formula"; diff "$expf" "$gotf" | head -3; }
    grep -qF -- "$ORPHAN_HDR" "$gotf" && no "(x/$variant) header present on startup" || ok "(x/$variant) no header on startup"
    # RESUME: header absence.
    r="$(new_repo)"; make_plugin_active "$r"; make_stranded_fixture "$r"
    out="$(run_alt_hook_raw "$d/session-resume.sh" "$r" resume)"; ctx="$(ctx_of "$out")"
    [ -n "$ctx" ] && ok "(x/$variant) resume emitted a non-empty envelope" || no "(x/$variant) resume silent"
    grep -qF -- "$ORPHAN_HDR" <<< "$ctx" && no "(x/$variant) header present on resume" || ok "(x/$variant) no header on resume"
  done

  # (x-b') local-only captured baseline for RESUME: origin/main's hook + real
  # siblings vs the current hook (real worktree-audit.sh, log absent ⇒ empty
  # report) on two fresh, identical, brief-free repos. Self-skips on a shallow
  # checkout — the (p-b') pattern.
  local old="$ROOT/x-baseline"; mkdir -p "$old"
  local giterr="$ROOT/x-baseline.giterr" oldout newout ro rn
  if git -C "$SCRIPT_DIR/../.." show origin/main:loomwright/scripts/session-resume.sh > "$old/session-resume.sh" 2>"$giterr" \
     && [ -s "$old/session-resume.sh" ]; then
    cp "$SCRIPT_DIR/curation-status.sh" "$SCRIPT_DIR/reconcile-jobs.sh" "$SCRIPT_DIR/brief-pointer.sh" "$old/"
    ro="$(new_repo)"; make_plugin_active "$ro"; make_curation_pending "$ro"
    rn="$(new_repo)"; make_plugin_active "$rn"; make_curation_pending "$rn"
    # The house-rules nudge is opted out on BOTH sides: it gates on the sibling
    # read-rules.sh, which the baseline dir deliberately does not carry.
    oldout="$(run_alt_hook_raw "$old/session-resume.sh" "$ro" resume LOOMWRIGHT_RULES_NUDGE=0)"
    newout="$(run_alt_hook_raw "$HOOK" "$rn" resume LOOMWRIGHT_RULES_NUDGE=0)"
    if [ -n "$oldout" ] && [ -n "$newout" ]; then
      ok "(x-b') baseline and current both emitted on resume"
      printf '%s' "$oldout" > "$ROOT/x-old.json"; printf '%s' "$newout" > "$ROOT/x-new.json"
      cmp -s "$ROOT/x-old.json" "$ROOT/x-new.json" \
        && ok "(x-b') resume with nothing orphaned is cmp-identical to the captured origin/main hook" \
        || { no "(x-b') resume DIFFERS from the captured origin/main hook"; diff "$ROOT/x-old.json" "$ROOT/x-new.json" | head -3; }
    else
      no "(x-b') a silent pair: old=${#oldout} new=${#newout} bytes"
    fi
  else
    echo "  skipped: origin/main unavailable ($(tr '\n' ' ' < "$giterr" | cut -c1-160))"
  fi

  # Mutant: the section is appended UNCONDITIONALLY (the report read replaced by
  # a constant row) ⇒ the startup cmp AND both header-absence assertions go red.
  d="$(mktmp)"; copy_hook_full "$d"; stub_auditor "$d" ""
  local mut="$d/session-resume.sh"
  sed -i.bak 's|rows="$(bash "$auditor" report 2>/dev/null \|\| true)"|rows="orphan	/mutant/wt	-	-	-"|' "$mut" && rm -f "$mut.bak"
  if gate_mutant "$HOOK" "$mut" "(x-mutant)"; then
    r="$(new_repo)"; make_plugin_active "$r"; make_curation_pending "$r"
    expected_curation_only_envelope "$r" > "$ROOT/xm-exp.json"
    ( cd "$r" && printf '{"source":"startup"}' | bash "$mut" 2>/dev/null ) > "$ROOT/xm-got.json"
    cmp -s "$ROOT/xm-exp.json" "$ROOT/xm-got.json" && no "(x-mutant) startup cmp stayed GREEN on the unconditional mutant" \
      || ok "(x-mutant) the unconditional mutant turns the startup cmp red"
    grep -qF -- "$ORPHAN_HDR" "$ROOT/xm-got.json" && ok "(x-mutant) startup header-absence goes red on the mutant" || no "(x-mutant) mutant did not add the header on startup"
    r="$(new_repo)"; make_plugin_active "$r"; make_stranded_fixture "$r"
    ctx="$(ctx_of "$(run_alt_hook_raw "$mut" "$r" resume)")"
    grep -qF -- "$ORPHAN_HDR" <<< "$ctx" && ok "(x-mutant) resume header-absence goes red on the mutant" || no "(x-mutant) mutant did not add the header on resume"
  fi
}
test_orphans_silent

# ---------------------------------------------------------------------------
echo "== (y) mutation: the section header string deleted from the hook ⇒ (w) red =="
test_orphans_header_mutant() {
  local d mut r ctx
  d="$(mktmp)"; copy_hook_full "$d"; stub_auditor "$d" "$ORPHAN_ROW"
  mut="$d/session-resume.sh"
  sed -i.bak 's|### Orphaned worktrees (advisory)\\n||' "$mut" && rm -f "$mut.bak"
  if gate_mutant "$HOOK" "$mut" "(y)"; then
    r="$(new_repo)"; make_plugin_active "$r"
    ctx="$(ctx_of "$(run_alt_hook_raw "$mut" "$r" startup)")"
    grep -qF -- "$ORPHAN_HDR" <<< "$ctx" && no "(y) header still present after deletion — the (w) assertion is not pinned to the hook" \
      || ok "(y) header gone ⇒ (w)'s header assertion goes red (startup)"
    grep -qF -- "- $ORPHAN_ROW_PATH" <<< "$ctx" && ok "(y) positive gate: the mutant still emits the row (merely the header was removed)" \
      || no "(y) the mutant lost the row too — broken, not targeted"
  fi
}
test_orphans_header_mutant

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
