#!/usr/bin/env bash
# test-curation-status.sh — self-tests for curation-status.sh, the curation-cadence
# probe behind /dreaming, /insights and /pr-postmortem readiness and the
# SessionStart curation nudge.
#
# Runs the probe inside ISOLATED temp git repos (mktemp -d + git init) so it NEVER
# touches the real project state. Ubuntu-clean: bash 3.2-safe (no associative
# arrays, no mapfile, no ${x^^}) AND GNU-safe (no BSD-only flags outside the
# fallbacks that are themselves under test). Auto-registered by ci.yml's
# `loomwright/scripts/test-*.sh` glob. Exit 0 = all pass, 1 = any failure.
#
# Groups:
#   (a) absent curation-state.json ⇒ last_run `never`; present-but-unparseable
#       ⇒ `unknown` (and therefore no decline); parseable-but-recordless ⇒
#       `never`. Exit 0 throughout.
#   (b) the ledger derivation EXCLUDES `automate_drain` records
#       (fixture's NEWEST line is an automate_drain record ⇒ a bare
#        `map(.ts)|max` implementation fails this red)
#   (c) insights mtime: `stat -c %Y` is tried FIRST, `-f %m` is the fallback, and
#       a non-numeric result yields `unknown` — never a crash, never `0`
#   (d) degradation matrix: absent ledger · unreadable ledger · absent jq ·
#       absent dashboard, across status / nudge / record — all exit 0, all report
#       `unknown`/`never`, none fabricates a count. Plus the OTHER degraded
#       `--json` route (jq present but the render throws): it must emit the same
#       all-unknown body as the jq-absent route, so `.commands.*.pending` is the
#       `"unknown"` sentinel down both and never a `null` down one
#   (e) pending counts match hand-counted values against a fixed last_run
#   (f) thresholds are genuinely configurable via .supervisor/config.json
#   (g) decline message names the count, the threshold, and "unvalidated";
#       at/above threshold there is NO decline (the proceed path)
#   (h) `record` wiring: `record dreaming` is the only legal target; plus the
#       remaining `main()` dispatch arms — the unknown-subcommand fallthrough and
#       all three help spellings (`-h` / `--help` / `help`)
#   (i) nudge: silent when nothing is pending, ONE counted line when pending,
#       env opt-out, and NO network call (no gh, no curl)
#   (j) every `exit` in the script is `exit 0` (runtime advisory emitter, not a gate)
#   (k) doc surfaces: the `record dreaming` wiring, `--force` Parameters rows,
#       /pr-postmortem's no-decline statement, and the "unvalidated" labelling
#   (l) the /pr-postmortem remote count: gh's EXIT STATUS, not the emptiness of
#       its output, decides examined-vs-could-not-examine (rc 0 + empty ⇒ an
#       honest 0; rc non-zero ⇒ unknown, even when it printed something), plus
#       the pure set-diff against the ledger, plus the same distinction one guard
#       clause later on the LEDGER side (absent ledger ⇒ a real count, since
#       "never run" is examined; present-but-unreadable ⇒ unknown) — all driven
#       by a gh STUB, never a real network call
#   (m) an unreadable .supervisor/logs/ ⇒ pending `unknown` (never a fabricated
#       0 that would silently make /dreaming and /insights never-decline)
#   (q) `record` hygiene: ids are pruned to what is on disk, survive whitespace,
#       and reach jq as DATA not filter text; plus the WRITE-path ladder — a
#       state file that exists but cannot be READ is refused outright (no write,
#       no mkdir), because `mv` would land regardless of the old file's
#       permissions and take the whole consumed set with it
#   (r) `unconsumed` — the selection that makes the backlog DRAIN: successive
#       default runs go 8 → 3 → 0 (a plain newest-by-mtime selection stalls at 3
#       forever), newest-first ordering, the N limit, noise-only exclusion,
#       silence-when-drained, fail-open on an unreadable consumed record; plus
#       `record`'s "newly consumed" delta being a real delta, not the named count

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROBE="$SCRIPT_DIR/curation-status.sh"

pass=0; fail=0; skip=0
ok()   { echo "  ok: $1"; pass=$((pass+1)); }
no()   { echo "  FAIL: $1"; fail=$((fail+1)); }
skp()  { echo "  SKIP: $1"; skip=$((skip+1)); }

ROOT="$(mktemp -d)"
trap 'chmod -R u+rwX "$ROOT" 2>/dev/null; rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-curation-status: jq absent on this host — curation-status.sh degrades to unknown (exit 0). Skipping assertions."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

# Isolated temp git repo with a .supervisor/ (plugin-active).
new_repo() {
  local r; r="$(mktmp)"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  mkdir -p "$r/.supervisor"
  printf '%s' "$r"
}

# run <repo> <args...> — run the probe in <repo>; stdout echoed, exit code in RC.
# LOOMWRIGHT_CURATION_REMOTE=0 keeps `status` hermetic (no gh probe) except where
# a group deliberately re-enables it.
# The exit code is stashed in a FILE, not a shell variable: `out="$(run ...)"`
# runs run() inside a command-substitution SUBSHELL, so any variable it assigns
# is discarded before the caller can read it — a plain `RC=$?` there would make
# every exit-code assertion silently vacuous.
RCFILE="$ROOT/.last-rc"
printf '0' > "$RCFILE"
run() {
  local repo="$1"; shift
  ( cd "$repo" && LOOMWRIGHT_CURATION_REMOTE=0 bash "$PROBE" "$@" 2>&1; printf '%s' "$?" > "$RCFILE" )
}
lastrc() { cat "$RCFILE" 2>/dev/null || printf '99'; }

# jget <json> <jq-filter>
jget() { printf '%s' "$1" | jq -r "$2" 2>/dev/null || true; }

# mk_bin <dir> <tool>... — a PATH dir holding symlinks to the named tools only.
mk_bin() {
  local d="$1"; shift
  mkdir -p "$d"
  local t p
  for t in "$@"; do
    p="$(command -v "$t" 2>/dev/null)" || continue
    [ -n "$p" ] && ln -sf "$p" "$d/$t"
  done
}
BASE_TOOLS="sh bash env date stat find git mkdir mv rm cat ls chmod grep sed head tail sort tr wc dirname basename cut uname mktemp touch"

# ============================================================================
echo "== (a) absent state ⇒ never; present-but-unparseable ⇒ unknown (never a claimed 0) =="
# ABSENCE and UNREADABILITY are different answers. `never` is a CLAIM that feeds
# the decline gate ("N new session log(s) since its last run"); emitting it for a
# file the script could not parse would let /dreaming decline on input it never
# read. Only a genuinely absent file — or a file that PARSED and simply carries
# no record — is an honest `never`.
RA="$(new_repo)"
outA="$(run "$RA" status --json)"
[ "$(lastrc)" -eq 0 ] && ok "(a) exits 0 with no curation-state.json" || no "(a) expected exit 0, got $(lastrc)"
[ "$(jget "$outA" '.commands.dreaming.last_run')" = "never" ] \
  && ok "(a) absent state file ⇒ last_run=never" \
  || no "(a) expected never, got '$(jget "$outA" '.commands.dreaming.last_run')'"

# Present but unparseable (truncated / not JSON / not an object) OR holding an
# unparseable timestamp ⇒ `unknown`.
for bad in '' '{"dreaming":' 'not json at all' '[]' '{"dreaming":{"last_run":"yesterday-ish"}}'; do
  printf '%s' "$bad" > "$RA/.supervisor/curation-state.json"
  outA2="$(run "$RA" status --json)"
  lr="$(jget "$outA2" '.commands.dreaming.last_run')"
  if [ "$(lastrc)" -eq 0 ] && [ "$lr" = "unknown" ]; then
    ok "(a) unparseable state (\"${bad:0:14}\") ⇒ last_run=unknown, exit 0"
  else
    no "(a) unparseable state (\"${bad:0:14}\") ⇒ expected unknown/exit 0, got '$lr'/rc=$(lastrc)"
  fi
done

# The consequence that makes it matter: an unparseable state file must NOT
# produce a decline citing a count derived from input the script could not read.
# A CORPUS IS REQUIRED for this to be the real test — with no .supervisor/logs/
# at all the count is an honest 0 ("no logs postdate ANY boundary"), and
# declining on it is correct no matter what last_run says. The fabrication risk
# only exists once there ARE logs to mis-attribute to "since its last run".
mkdir -p "$RA/.supervisor/logs"
for n in 1 2 3; do echo '{}' > "$RA/.supervisor/logs/a$n.jsonl"; done
printf '%s' '{"dreaming":' > "$RA/.supervisor/curation-state.json"
outA3="$(run "$RA" status --json)"
[ "$(jget "$outA3" '.commands.dreaming.pending')" = "unknown" ] \
  && ok "(a) unparseable state ⇒ pending=unknown (no count claimed against a boundary we lack)" \
  || no "(a) expected pending=unknown, got '$(jget "$outA3" '.commands.dreaming.pending')'"
[ "$(jget "$outA3" '.commands.dreaming.ready')" = "unknown" ] \
  && ok "(a) unparseable state ⇒ ready=unknown (the gate cannot decline on it)" \
  || no "(a) expected ready=unknown, got '$(jget "$outA3" '.commands.dreaming.ready')'"
[ -z "$(jget "$outA3" '.commands.dreaming.decline_message')" ] \
  && ok "(a) unparseable state ⇒ EMPTY decline_message (no fabricated 'N logs since its last run')" \
  || no "(a) unparseable state produced a decline message: $(jget "$outA3" '.commands.dreaming.decline_message')"

# A well-formed object with NO .dreaming.last_run is the honest `never`: we read
# it, and it holds no record. This is the case `unknown` must NOT swallow.
printf '%s' '{"other":{"k":1}}' > "$RA/.supervisor/curation-state.json"
outA4="$(run "$RA" status --json)"
[ "$(jget "$outA4" '.commands.dreaming.last_run')" = "never" ] \
  && ok "(a) parseable object with no .dreaming.last_run ⇒ never (read it; no record)" \
  || no "(a) expected never for a parseable recordless state, got '$(jget "$outA4" '.commands.dreaming.last_run')'"
[ "$(jget "$outA4" '.commands.dreaming.pending')" = "3" ] \
  && ok "(a) …and 'never' still counts the whole corpus (unknown did not swallow this case)" \
  || no "(a) expected pending=3 for a recordless state, got '$(jget "$outA4" '.commands.dreaming.pending')'"
rm -f "$RA/.supervisor/curation-state.json"
rm -rf "$RA/.supervisor/logs"

# ============================================================================
echo "== (b) /pr-postmortem derivation EXCLUDES automate_drain records =="
# The fixture's NEWEST line is an automate_drain record, so a bare `map(.ts)|max`
# implementation returns 2026-04-01 and fails this test RED. Note the interleaving:
# a manual record (2026-02-15) is newer than a drain record (2026-01-15), so the
# filter is load-bearing in general, not an artifact of file order.
test_postmortem_excludes_automate_drain() {
  local r; r="$(new_repo)"
  mkdir -p "$r/.supervisor/postmortem"
  cat > "$r/.supervisor/postmortem/results.jsonl" <<'EOF'
{"ts":"2026-01-01T00:00:00Z","source":"manual_postmortem","number":1}
{"ts":"2026-01-15T00:00:00Z","source":"automate_drain","automate_key":"k1","number":2}
{"ts":"2026-02-01T00:00:00Z","number":3}
{"ts":"2026-02-15T00:00:00Z","source":"manual_postmortem","number":4}
{ this line is not valid json at all
{"ts":"2026-04-01T00:00:00Z","source":"automate_drain","automate_key":"k2","number":5}
EOF
  local out lr
  out="$(run "$r" status --json)"
  lr="$(jget "$out" '.commands.pr_postmortem.last_run')"
  [ "$(lastrc)" -eq 0 ] && ok "(b) exits 0" || no "(b) expected exit 0, got $(lastrc)"
  if [ "$lr" = "2026-02-15T00:00:00Z" ]; then
    ok "(b) max .ts over non-automate_drain records (drain line 2026-04-01 correctly ignored)"
  else
    no "(b) expected 2026-02-15T00:00:00Z (naive max would be 2026-04-01T00:00:00Z), got '$lr'"
  fi
  # A source-less legacy record must be KEPT (null != "automate_drain").
  cat > "$r/.supervisor/postmortem/results.jsonl" <<'EOF'
{"ts":"2026-03-03T00:00:00Z","number":9}
{"ts":"2026-05-05T00:00:00Z","source":"automate_drain","automate_key":"k3","number":10}
EOF
  out="$(run "$r" status --json)"
  lr="$(jget "$out" '.commands.pr_postmortem.last_run')"
  [ "$lr" = "2026-03-03T00:00:00Z" ] \
    && ok "(b) source-less legacy record is kept, not misclassified as a drain line" \
    || no "(b) expected 2026-03-03T00:00:00Z, got '$lr'"
  # An all-drain ledger has no command-authored run at all ⇒ never (not the drain ts).
  cat > "$r/.supervisor/postmortem/results.jsonl" <<'EOF'
{"ts":"2026-06-06T00:00:00Z","source":"automate_drain","automate_key":"k4","number":11}
EOF
  out="$(run "$r" status --json)"
  lr="$(jget "$out" '.commands.pr_postmortem.last_run')"
  [ "$lr" = "never" ] \
    && ok "(b) all-drain ledger ⇒ never (no human ever ran /pr-postmortem)" \
    || no "(b) expected never for an all-drain ledger, got '$lr'"
}
test_postmortem_excludes_automate_drain

# ============================================================================
echo "== (c) mtime probe: -c %Y FIRST, -f %m fallback, non-numeric ⇒ unknown =="
RCQ="$(new_repo)"
mkdir -p "$RCQ/.supervisor/insights"
echo "dash" > "$RCQ/.supervisor/insights/dashboard.md"
outC="$(run "$RCQ" status --json)"
lrC="$(jget "$outC" '.commands.insights.last_run')"
case "$lrC" in
  ????-??-??T??:??:??Z) ok "(c) present dashboard ⇒ ISO last_run derived from mtime ($lrC)" ;;
  *) no "(c) expected an ISO timestamp from the dashboard mtime, got '$lrC'" ;;
esac

STATLOG="$ROOT/stat-args.log"
: > "$STATLOG"
BADSTAT="$ROOT/badstat-bin"
mk_bin "$BADSTAT" $BASE_TOOLS jq
# mk_bin symlinked the REAL stat here; `cat >` would follow that symlink and try
# to overwrite /usr/bin/stat. Remove the link before writing the shim.
rm -f "$BADSTAT/stat"
cat > "$BADSTAT/stat" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$STATLOG"
printf 'not-a-number\n'
exit 0
EOF
chmod +x "$BADSTAT/stat"
outC2="$( cd "$RCQ" && PATH="$BADSTAT:$PATH" LOOMWRIGHT_CURATION_REMOTE=0 bash "$PROBE" status --json 2>&1 )"; rcC2=$?
lrC2="$(jget "$outC2" '.commands.insights.last_run')"
[ "$rcC2" -eq 0 ] && ok "(c) exits 0 when stat returns garbage" || no "(c) expected exit 0, got $rcC2"
[ "$lrC2" = "unknown" ] \
  && ok "(c) non-numeric mtime ⇒ unknown (not a crash, not 0, not 1970)" \
  || no "(c) expected unknown for a non-numeric mtime, got '$lrC2'"
firstcall="$(head -1 "$STATLOG" 2>/dev/null || true)"
case "$firstcall" in
  "-c %Y "*) ok "(c) stat is called with -c %Y FIRST (GNU form), -f %m only as fallback" ;;
  *) no "(c) expected the first stat call to be '-c %Y ...', got '$firstcall'" ;;
esac
grep -qF -- '-f %m' "$STATLOG" \
  && ok "(c) the -f %m BSD fallback is exercised after -c %Y yields a non-numeric value" \
  || no "(c) expected a '-f %m' fallback call in the stat arg log"

# ============================================================================
echo "== (d) degradation matrix: absent/unreadable ledger, absent jq, absent dashboard =="
RD="$(new_repo)"     # no ledger, no dashboard, no state file
outD="$(run "$RD" status --json)"
[ "$(lastrc)" -eq 0 ] && ok "(d) status exits 0 on a bare .supervisor/" || no "(d) status rc=$(lastrc)"
[ "$(jget "$outD" '.commands.pr_postmortem.last_run')" = "never" ] \
  && ok "(d) absent ledger ⇒ /pr-postmortem last_run=never (not a fabricated ts)" \
  || no "(d) absent ledger: expected never, got '$(jget "$outD" '.commands.pr_postmortem.last_run')'"
[ "$(jget "$outD" '.commands.insights.last_run')" = "never" ] \
  && ok "(d) absent dashboard ⇒ /insights last_run=never" \
  || no "(d) absent dashboard: expected never, got '$(jget "$outD" '.commands.insights.last_run')'"
[ "$(jget "$outD" '.commands.pr_postmortem.pending')" = "unknown" ] \
  && ok "(d) /pr-postmortem pending is unknown without a remote probe (never a fabricated 0)" \
  || no "(d) expected pending=unknown, got '$(jget "$outD" '.commands.pr_postmortem.pending')'"
run "$RD" nudge >/dev/null; [ "$(lastrc)" -eq 0 ] && ok "(d) nudge exits 0 on a bare .supervisor/" || no "(d) nudge rc=$(lastrc)"
run "$RD" record dreaming >/dev/null; [ "$(lastrc)" -eq 0 ] && ok "(d) record exits 0 on a bare .supervisor/" || no "(d) record rc=$(lastrc)"
rm -f "$RD/.supervisor/curation-state.json"

# Unreadable ledger. chmod 000 does NOT block reads for uid 0, so under a root /
# container CI executor this assertion would pass for the WRONG reason — skip it
# visibly rather than asserting something untrue.
RDU="$(new_repo)"
mkdir -p "$RDU/.supervisor/postmortem"
echo '{"ts":"2026-01-01T00:00:00Z","number":1}' > "$RDU/.supervisor/postmortem/results.jsonl"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  skp "(d) unreadable-ledger fixture SKIPPED — running as uid 0, where chmod 000 does not block reads"
else
  chmod 000 "$RDU/.supervisor/postmortem/results.jsonl" 2>/dev/null || true
  outDU="$(run "$RDU" status --json)"
  lrDU="$(jget "$outDU" '.commands.pr_postmortem.last_run')"
  [ "$(lastrc)" -eq 0 ] && ok "(d) status exits 0 on an unreadable ledger" || no "(d) unreadable ledger rc=$(lastrc)"
  [ "$lrDU" = "unknown" ] \
    && ok "(d) unreadable ledger ⇒ unknown (NOT never, NOT a fabricated ts)" \
    || no "(d) unreadable ledger: expected unknown, got '$lrDU'"
  chmod 644 "$RDU/.supervisor/postmortem/results.jsonl" 2>/dev/null || true
fi

# Absent jq — a PATH holding every other tool but no jq at all.
NOJQ="$ROOT/nojq-bin"
mk_bin "$NOJQ" $BASE_TOOLS
if [ -e "$NOJQ/jq" ]; then rm -f "$NOJQ/jq"; fi
RDJ="$(new_repo)"
mkdir -p "$RDJ/.supervisor/insights"; echo d > "$RDJ/.supervisor/insights/dashboard.md"
mkdir -p "$RDJ/.supervisor/postmortem"; echo '{"ts":"2026-01-01T00:00:00Z"}' > "$RDJ/.supervisor/postmortem/results.jsonl"
for sub in "status" "status --json" "nudge" "record dreaming"; do
  # shellcheck disable=SC2086
  outDJ="$( cd "$RDJ" && PATH="$NOJQ" LOOMWRIGHT_CURATION_REMOTE=0 "$(command -v bash)" "$PROBE" $sub 2>&1 )"; rcDJ=$?
  [ "$rcDJ" -eq 0 ] && ok "(d) '$sub' exits 0 with jq absent" || no "(d) '$sub' with jq absent: rc=$rcDJ"
  case "$sub" in
    "status --json")
      if printf '%s' "$outDJ" | grep -qF '"jq":false' && ! printf '%s' "$outDJ" | grep -qE '"(last_run|pending)": *0'; then
        ok "(d) jq-absent --json reports unknown throughout (no fabricated 0)"
      else
        no "(d) jq-absent --json unexpected: $outDJ"
      fi
      ;;
    "nudge")
      [ -z "$outDJ" ] && ok "(d) jq-absent nudge emits nothing (no fabricated count)" \
        || no "(d) jq-absent nudge should emit nothing, got: $outDJ"
      ;;
    "record dreaming")
      printf '%s' "$outDJ" | grep -qF 'jq is absent' \
        && ok "(d) jq-absent record says so and writes nothing" \
        || no "(d) jq-absent record message missing: $outDJ"
      [ -f "$RDJ/.supervisor/curation-state.json" ] \
        && no "(d) jq-absent record must NOT create curation-state.json" \
        || ok "(d) jq-absent record created no state file"
      ;;
  esac
done

# jq PRESENT but the render itself throws — the other degraded --json route.
# `have_jq` is `command -v jq`, so a stub that EXISTS and always exits non-zero
# passes the presence check and then fails the `jq -n` render, which is exactly
# the narrow path the `render_failed` fallback exists for. It must emit the SAME
# all-unknown document as the jq-absent path: a consumer reading
# `.commands.dreaming.pending` has to see the documented `"unknown"` sentinel,
# never a `null` that would read as "no such key".
BADJQ="$ROOT/badjq-bin"
mk_bin "$BADJQ" $BASE_TOOLS
rm -f "$BADJQ/jq"
printf '#!/bin/sh\nexit 1\n' > "$BADJQ/jq"; chmod +x "$BADJQ/jq"
RDR="$(new_repo)"
mkdir -p "$RDR/.supervisor/insights"; echo d > "$RDR/.supervisor/insights/dashboard.md"
outRF="$( cd "$RDR" && PATH="$BADJQ" LOOMWRIGHT_CURATION_REMOTE=0 "$(command -v bash)" "$PROBE" status --json 2>&1 )"; rcRF=$?
[ "$rcRF" -eq 0 ] && ok "(d) status --json exits 0 when the jq render throws" \
  || no "(d) render-failure rc=$rcRF: $outRF"
# Control: without this the test could pass against the HAPPY path and prove nothing.
printf '%s' "$outRF" | grep -qF '"error":"render_failed"' \
  && ok "(d) render-failure control — the fixture really took the render_failed arm" \
  || no "(d) fixture did NOT reach the render_failed arm: $outRF"
printf '%s' "$outRF" | jq -e . >/dev/null 2>&1 \
  && ok "(d) the render_failed document is still valid JSON" \
  || no "(d) render_failed emitted invalid JSON: $outRF"
[ "$(jget "$outRF" '.commands.dreaming.pending')" = "unknown" ] \
  && ok "(d) render_failed ⇒ .commands.dreaming.pending is \"unknown\", NOT null" \
  || no "(d) render_failed .commands.dreaming.pending='$(jget "$outRF" '.commands.dreaming.pending')' (expected unknown)"
# Shape parity with the jq-absent path: identical once the preamble keys that
# legitimately differ (`jq`, `error`) are removed. This is the assertion that
# actually pins "the two degraded routes speak one sentinel" — it fails the
# moment either literal drifts from the other.
outNJ="$( cd "$RDJ" && PATH="$NOJQ" LOOMWRIGHT_CURATION_REMOTE=0 "$(command -v bash)" "$PROBE" status --json 2>&1 )"
bodyRF="$(printf '%s' "$outRF" | jq -S 'del(.jq, .error)' 2>/dev/null || true)"
bodyNJ="$(printf '%s' "$outNJ" | jq -S 'del(.jq, .error)' 2>/dev/null || true)"
if [ -n "$bodyRF" ] && [ "$bodyRF" = "$bodyNJ" ]; then
  ok "(d) render_failed and jq-absent emit the SAME all-unknown body"
else
  no "(d) degraded --json bodies diverge — render_failed='$bodyRF' vs jq-absent='$bodyNJ'"
fi

# ============================================================================
echo "== (e) pending counts equal the hand-counted values against a fixed last_run =="
RE="$(new_repo)"
mkdir -p "$RE/.supervisor/logs" "$RE/.supervisor/insights" "$RE/.supervisor/postmortem"
# Fixed /dreaming last_run: 2026-03-01T00:00:00Z.
printf '{"dreaming":{"last_run":"2026-03-01T00:00:00Z"}}' > "$RE/.supervisor/curation-state.json"
# 5 session logs: 3 AFTER (April) and 2 BEFORE (February) that boundary.
i=0
for stamp in 202604010000 202604020000 202604030000; do
  i=$((i+1)); echo '{}' > "$RE/.supervisor/logs/after-$i.jsonl"
  touch -t "$stamp" "$RE/.supervisor/logs/after-$i.jsonl"
done
i=0
for stamp in 202602010000 202602020000; do
  i=$((i+1)); echo '{}' > "$RE/.supervisor/logs/before-$i.jsonl"
  touch -t "$stamp" "$RE/.supervisor/logs/before-$i.jsonl"
done
# /insights last_run is derived from the dashboard mtime — set to May 2026, i.e.
# AFTER every log, so its hand-counted pending is 0 (a real zero, not `unknown`).
echo dash > "$RE/.supervisor/insights/dashboard.md"; touch -t 202605010000 "$RE/.supervisor/insights/dashboard.md"
# 3 ledger records (2 command-authored, 1 drain) — the drain line is the newest.
cat > "$RE/.supervisor/postmortem/results.jsonl" <<'EOF'
{"ts":"2026-01-10T00:00:00Z","source":"manual_postmortem","number":21}
{"ts":"2026-02-20T00:00:00Z","source":"manual_postmortem","number":22}
{"ts":"2026-07-30T00:00:00Z","source":"automate_drain","automate_key":"k9","number":23}
EOF
outE="$(run "$RE" status --json)"
[ "$(lastrc)" -eq 0 ] && ok "(e) exits 0" || no "(e) rc=$(lastrc)"
# /dreaming's pending is a SET complement, not a watermark comparison: none of
# the 5 logs has been recorded as consumed, so all 5 are pending even though only
# 3 postdate the stored last_run. That is the fix for the v15.29.0 shape, where a
# run stamped `now` and the 2 older unread logs stopped being counted forever.
[ "$(jget "$outE" '.commands.dreaming.pending')" = "5" ] \
  && ok "(e) /dreaming pending = 5 (hand-counted: 5 logs, NONE recorded consumed — last_run does not gate this count)" \
  || no "(e) /dreaming pending: expected 5, got '$(jget "$outE" '.commands.dreaming.pending')'"
[ "$(jget "$outE" '.commands.insights.pending')" = "0" ] \
  && ok "(e) /insights pending = 0 (hand-counted: no log postdates the dashboard mtime)" \
  || no "(e) /insights pending: expected 0, got '$(jget "$outE" '.commands.insights.pending')'"
[ "$(jget "$outE" '.commands.pr_postmortem.last_run')" = "2026-02-20T00:00:00Z" ] \
  && ok "(e) /pr-postmortem last_run = 2026-02-20 (hand-counted: newest of 2 command records)" \
  || no "(e) /pr-postmortem last_run: expected 2026-02-20T00:00:00Z, got '$(jget "$outE" '.commands.pr_postmortem.last_run')'"
[ "$(jget "$outE" '.commands.dreaming.last_run')" = "2026-03-01T00:00:00Z" ] \
  && ok "(e) /dreaming last_run is the STORED value, read back verbatim" \
  || no "(e) /dreaming last_run drifted: '$(jget "$outE" '.commands.dreaming.last_run')'"

# ============================================================================
echo "== (f) thresholds are genuinely configurable via .supervisor/config.json =="
RF="$(new_repo)"
mkdir -p "$RF/.supervisor/logs"
for n in 1 2 3 4; do echo '{}' > "$RF/.supervisor/logs/s$n.jsonl"; done   # 4 pending (last_run never)
outF0="$(run "$RF" status --json)"
[ "$(jget "$outF0" '.commands.dreaming.threshold')" = "15" ] \
  && ok "(f) in-script default threshold 15 applies with no config" \
  || no "(f) expected default 15, got '$(jget "$outF0" '.commands.dreaming.threshold')'"
[ "$(jget "$outF0" '.commands.dreaming.ready')" = "no" ] \
  && ok "(f) 4 pending vs default 15 ⇒ ready=no" \
  || no "(f) expected ready=no, got '$(jget "$outF0" '.commands.dreaming.ready')'"
printf '{"curation":{"thresholds":{"dreaming":3}}}' > "$RF/.supervisor/config.json"
outF1="$(run "$RF" status --json)"
[ "$(lastrc)" -eq 0 ] && ok "(f) exits 0 with a config override" || no "(f) rc=$(lastrc)"
[ "$(jget "$outF1" '.commands.dreaming.threshold')" = "3" ] \
  && ok "(f) config .curation.thresholds.dreaming=3 overrides the default" \
  || no "(f) expected threshold 3, got '$(jget "$outF1" '.commands.dreaming.threshold')'"
[ "$(jget "$outF1" '.commands.dreaming.ready')" = "yes" ] \
  && ok "(f) 4 pending vs configured 3 ⇒ does NOT decline (ready=yes)" \
  || no "(f) expected ready=yes with threshold 3, got '$(jget "$outF1" '.commands.dreaming.ready')'"
[ -z "$(jget "$outF1" '.commands.dreaming.decline_message')" ] \
  && ok "(f) no decline message on the proceed path" \
  || no "(f) unexpected decline message on the proceed path"
# A configured 0 is HONOURED, not rejected: `readiness` compares pending >= threshold,
# so 0 means "always ready — report the cadence, never decline". Silently substituting
# the in-script default for an explicitly configured 0 would override a value the user
# actually wrote, which is the class of dishonesty this script forbids elsewhere.
printf '{"curation":{"thresholds":{"dreaming":0}}}' > "$RF/.supervisor/config.json"
outF0z="$(run "$RF" status --json)"
[ "$(jget "$outF0z" '.commands.dreaming.threshold')" = "0" ] \
  && ok "(f) a configured threshold of 0 is honoured, not silently replaced by the default" \
  || no "(f) expected threshold 0, got '$(jget "$outF0z" '.commands.dreaming.threshold')'"
[ "$(jget "$outF0z" '.commands.dreaming.ready')" = "yes" ] \
  && ok "(f) threshold 0 ⇒ ready=yes always (reporting kept, declining switched off)" \
  || no "(f) expected ready=yes with threshold 0, got '$(jget "$outF0z" '.commands.dreaming.ready')'"
[ -z "$(jget "$outF0z" '.commands.dreaming.decline_message')" ] \
  && ok "(f) threshold 0 ⇒ no decline message" \
  || no "(f) threshold 0 produced a decline message"
# Malformed / hostile config values fall back to the default and still exit 0.
for badcfg in '{"curation":{"thresholds":{"dreaming":"lots"}}}' '{"curation":{"thresholds":{"dreaming":-4}}}' 'not json'; do
  printf '%s' "$badcfg" > "$RF/.supervisor/config.json"
  outF2="$(run "$RF" status --json)"
  if [ "$(lastrc)" -eq 0 ] && [ "$(jget "$outF2" '.commands.dreaming.threshold')" = "15" ]; then
    ok "(f) malformed config (\"${badcfg:0:22}\") ⇒ default 15, exit 0"
  else
    no "(f) malformed config (\"${badcfg:0:22}\") ⇒ expected default 15/exit 0, got '$(jget "$outF2" '.commands.dreaming.threshold')'/rc=$(lastrc)"
  fi
done
# The probe must never REWRITE config.json (it is live: webhook_url, allowlist, auto_review).
printf '{"webhook_url":"https://example.invalid/x","curation":{"thresholds":{"insights":2}}}' > "$RF/.supervisor/config.json"
before="$(cat "$RF/.supervisor/config.json")"
run "$RF" status >/dev/null; run "$RF" nudge >/dev/null; run "$RF" record dreaming >/dev/null
[ "$before" = "$(cat "$RF/.supervisor/config.json")" ] \
  && ok "(f) config.json is byte-identical after status/nudge/record (read, never rewritten)" \
  || no "(f) config.json was modified by the probe"

# ============================================================================
echo "== (g) decline message names the count, the threshold, and 'unvalidated' =="
RG="$(new_repo)"
mkdir -p "$RG/.supervisor/logs"
for n in 1 2; do echo '{}' > "$RG/.supervisor/logs/s$n.jsonl"; done       # 2 pending vs default 15
outG="$(run "$RG" status --json)"
msgG="$(jget "$outG" '.commands.dreaming.decline_message')"
[ -n "$msgG" ] && ok "(g) below threshold ⇒ a decline message is produced" || no "(g) expected a decline message"
printf '%s' "$msgG" | grep -qF ' 2 unreflected session log' && ok "(g) decline names the observed count (2)" \
  || no "(g) decline does not name the observed count: $msgG"
printf '%s' "$msgG" | grep -qF 'threshold of 15' && ok "(g) decline names the threshold (15)" \
  || no "(g) decline does not name the threshold: $msgG"
printf '%s' "$msgG" | grep -qi 'unvalidated' && ok "(g) decline says the threshold is an unvalidated guess" \
  || no "(g) decline omits the 'unvalidated' disclosure: $msgG"
printf '%s' "$msgG" | grep -qF -- '--force' && ok "(g) decline points at --force as the override" \
  || no "(g) decline does not mention --force: $msgG"
[ "$(lastrc)" -eq 0 ] && ok "(g) declining still exits 0 (advisory, never a gate)" || no "(g) rc=$(lastrc)"
# /pr-postmortem never declines, at any count.
[ "$(jget "$outG" '.commands.pr_postmortem.ready')" = "always" ] \
  && ok "(g) /pr-postmortem ready=always (targeted at one named PR — never declines)" \
  || no "(g) /pr-postmortem should never decline"
[ -z "$(jget "$outG" '.commands.pr_postmortem.decline_message')" ] \
  && ok "(g) /pr-postmortem carries no decline message" \
  || no "(g) /pr-postmortem must not carry a decline message"

# ============================================================================
echo "== (h) record: 'dreaming' is the ONLY legal target =="
RH="$(new_repo)"
before_h="$(run "$RH" status --json)"
[ "$(jget "$before_h" '.commands.dreaming.last_run')" = "never" ] && ok "(h) starts at never" || no "(h) expected never"
outH="$(run "$RH" record dreaming)"
[ "$(lastrc)" -eq 0 ] && ok "(h) record dreaming exits 0" || no "(h) rc=$(lastrc)"
after_h="$(run "$RH" status --json)"
lrH="$(jget "$after_h" '.commands.dreaming.last_run')"
case "$lrH" in
  ????-??-??T??:??:??Z) ok "(h) after record, /dreaming last_run is non-never ($lrH)" ;;
  *) no "(h) expected a recorded ISO last_run, got '$lrH'" ;;
esac
for badtarget in insights pr-postmortem "" bogus; do
  outH2="$(run "$RH" record $badtarget)"
  if [ "$(lastrc)" -eq 0 ] && printf '%s' "$outH2" | grep -qF 'accepts only `dreaming`'; then
    ok "(h) record '${badtarget:-<none>}' is rejected with a message and still exits 0"
  else
    no "(h) record '${badtarget:-<none>}' should be rejected and exit 0 (rc=$(lastrc)): $outH2"
  fi
done
after_h2="$(run "$RH" status --json)"
[ "$(jget "$after_h2" '.commands.dreaming.last_run')" = "$lrH" ] \
  && ok "(h) rejected record targets left the stored value untouched" \
  || no "(h) a rejected record target mutated the stored value"
# An unknown subcommand is reported, never an error exit.
outH3="$(run "$RH" wibble)"
[ "$(lastrc)" -eq 0 ] && printf '%s' "$outH3" | grep -qF 'unknown subcommand' \
  && ok "(h) unknown subcommand reported, exit 0" || no "(h) unknown subcommand: rc=$(lastrc) / $outH3"

# The help branch: all three spellings print usage and exit 0. Asserting the
# ABSENCE of the unknown-subcommand text is what proves each spelling took the
# help arm rather than falling through to `*)` — the arm every other spelling in
# this dispatch is already pinned against.
for helpform in -h --help help; do
  outH4="$(run "$RH" "$helpform")"
  if [ "$(lastrc)" -eq 0 ] \
    && printf '%s' "$outH4" | grep -qF 'usage: curation-status.sh' \
    && ! printf '%s' "$outH4" | grep -qF 'unknown subcommand'; then
    ok "(h) '$helpform' prints usage (not the unknown-subcommand fallthrough), exit 0"
  else
    no "(h) '$helpform' expected the usage line and exit 0 (rc=$(lastrc)): $outH4"
  fi
done
# Usage must name every subcommand the dispatch actually accepts, or it drifts
# into advertising a command set the script no longer has.
outH5="$(run "$RH" --help)"
for advertised in status record nudge; do
  printf '%s' "$outH5" | grep -qF "$advertised" \
    && ok "(h) usage names the '$advertised' subcommand" \
    || no "(h) usage omits '$advertised': $outH5"
done
# Help is read-only: it must not create or touch the state file.
[ "$(jget "$(run "$RH" status --json)" '.commands.dreaming.last_run')" = "$lrH" ] \
  && ok "(h) the help branch left the stored value untouched" \
  || no "(h) the help branch mutated the stored value"

# ============================================================================
echo "== (i) nudge: silent when idle, ONE counted line when pending, opt-out, NO network =="
RI="$(new_repo)"
mkdir -p "$RI/.supervisor/logs"
outI0="$(run "$RI" nudge)"
[ "$(lastrc)" -eq 0 ] && ok "(i) nudge exits 0 with nothing pending" || no "(i) rc=$(lastrc)"
[ -z "$outI0" ] && ok "(i) nothing pending ⇒ nudge emits NOTHING (no header, no blank section)" \
  || no "(i) expected empty output, got: $outI0"
printf '{"curation":{"thresholds":{"dreaming":1,"insights":1}}}' > "$RI/.supervisor/config.json"
for n in 1 2 3; do echo '{}' > "$RI/.supervisor/logs/s$n.jsonl"; done
outI1="$(run "$RI" nudge)"
linesI="$(printf '%s\n' "$outI1" | grep -c . || true)"
[ "$linesI" -eq 1 ] && ok "(i) pending ⇒ exactly ONE advisory line" || no "(i) expected 1 line, got $linesI"
printf '%s' "$outI1" | grep -qE '[0-9]+ (unreflected|new) session log' \
  && ok "(i) the line carries a real COUNT, not merely a date" \
  || no "(i) the nudge line carries no count: $outI1"
printf '%s' "$outI1" | grep -qi 'unvalidated' \
  && ok "(i) the line labels the thresholds unvalidated" || no "(i) missing 'unvalidated' in: $outI1"
for optout in 0 off false no; do
  outI2="$( cd "$RI" && LOOMWRIGHT_CURATION_NUDGE="$optout" bash "$PROBE" nudge 2>&1 )"; rcI2=$?
  if [ "$rcI2" -eq 0 ] && [ -z "$outI2" ]; then
    ok "(i) LOOMWRIGHT_CURATION_NUDGE=$optout silences the nudge (exit 0)"
  else
    no "(i) opt-out=$optout should silence the nudge (rc=$rcI2): $outI2"
  fi
done
# NO network call on the nudge path — asserted, not inspected.
NETBIN="$ROOT/net-bin"; mk_bin "$NETBIN" $BASE_TOOLS jq
for tool in gh curl; do
  rm -f "$NETBIN/$tool"
  cat > "$NETBIN/$tool" <<EOF
#!/bin/sh
: > "$ROOT/called-$tool"
exit 0
EOF
  chmod +x "$NETBIN/$tool"
done
rm -f "$ROOT/called-gh" "$ROOT/called-curl"
outI3="$( cd "$RI" && PATH="$NETBIN:$PATH" bash "$PROBE" nudge 2>&1 )"; rcI3=$?
[ "$rcI3" -eq 0 ] && ok "(i) nudge exits 0 with gh/curl shimmed onto PATH" || no "(i) rc=$rcI3"
[ -n "$outI3" ] && ok "(i) nudge still fires with the shims present (control)" || no "(i) control: nudge produced nothing"
[ ! -e "$ROOT/called-gh" ] && ok "(i) nudge invoked NO gh (local-only)" || no "(i) nudge invoked gh — network on the hook path"
[ ! -e "$ROOT/called-curl" ] && ok "(i) nudge invoked NO curl (local-only)" || no "(i) nudge invoked curl — network on the hook path"

# ============================================================================
echo "== (j) every exit in curation-status.sh is 'exit 0' =="
# The operand is OPTIONAL in the match pattern (`exit([[:space:]]|$)`), not
# required (`exit[[:space:]]+`): a BARE `exit` returns the PREVIOUS command's
# status — the exact non-zero path this invariant exists to forbid — and an
# operand-requiring pattern cannot match it, so the mutant would pass silently.
# The exclusion still requires an operand, so `exit 0` and only `exit 0` is
# subtracted from the matches.
badexits="$(grep -nE '(^|[^[:alnum:]_])exit([[:space:]]|$)' "$PROBE" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -vE 'exit[[:space:]]+0([^0-9]|$)' || true)"
if [ -z "$badexits" ]; then
  ok "(j) every exit is 'exit 0' (runtime advisory emitter, never a gate)"
else
  no "(j) non-zero exit path(s) found: $badexits"
fi
grep -qE '^exit 0$' "$PROBE" && ok "(j) the script ends on an explicit exit 0" || no "(j) missing a trailing 'exit 0'"

# ============================================================================
echo "== (k) doc surfaces carry the wiring, the --force flag, and the 'unvalidated' label =="
DREAM="$PLUGIN_ROOT/commands/dreaming.md"
INS="$PLUGIN_ROOT/commands/insights.md"
PM="$PLUGIN_ROOT/commands/pr-postmortem.md"
HELP="$PLUGIN_ROOT/commands/agent-help.md"

grep -qF 'curation-status.sh" record dreaming' "$DREAM" \
  && ok "(k) dreaming.md INVOKES curation-status.sh record dreaming" \
  || no "(k) dreaming.md does not invoke 'curation-status.sh record dreaming'"
grep -qE '^\| `--force`' "$DREAM" \
  && ok "(k) dreaming.md documents --force in a Parameters table row" \
  || no "(k) dreaming.md has no '| \`--force\`' Parameters row"
grep -qF '## Parameters' "$INS" \
  && ok "(k) insights.md has a Parameters section (created by this work)" \
  || no "(k) insights.md is missing a '## Parameters' section"
grep -qE '^\| `--force`' "$INS" \
  && ok "(k) insights.md documents --force in a Parameters table row" \
  || no "(k) insights.md has no '| \`--force\`' Parameters row"
grep -qi 'never declines' "$PM" \
  && ok "(k) pr-postmortem.md states it never declines" \
  || no "(k) pr-postmortem.md does not state that it never declines"
grep -qE '^\| `--force`' "$PM" \
  && no "(k) pr-postmortem.md must NOT gain a --force/decline gate" \
  || ok "(k) pr-postmortem.md documents no declining gate"
grep -qi 'unvalidated' "$DREAM" && ok "(k) dreaming.md labels the threshold unvalidated" \
  || no "(k) dreaming.md omits the 'unvalidated' label"
grep -qi 'unvalidated' "$INS" && ok "(k) insights.md labels the threshold unvalidated" \
  || no "(k) insights.md omits the 'unvalidated' label"
grep -qi 'unvalidated' "$PROBE" && ok "(k) curation-status.sh header labels the thresholds unvalidated" \
  || no "(k) curation-status.sh omits the 'unvalidated' label"
grep -qF -- '/dreaming --force' "$HELP" \
  && ok "(k) agent-help.md mirrors /dreaming's --force flag (no mirror drift)" \
  || no "(k) agent-help.md does not mirror /dreaming's --force flag"
# agent-help.md's /insights ENTRY must carry the flag too. A reader scanning the
# /insights section never sees the trailing clause in the /dreaming section, so
# mirroring it only there leaves that entry describing a command that cannot
# decline. Scoped to the /insights section, not the whole file, or the /dreaming
# entry's own mention would satisfy this vacuously.
help_insights_section() {
  sed -n '/^### .* \/insights /,/^### .* \/obsidian /p' "$HELP"
}
help_insights_section | grep -qF -- '/insights --force' \
  && ok "(k) agent-help.md's /insights ENTRY names --force (not only the /dreaming entry)" \
  || no "(k) agent-help.md's /insights entry does not name --force"
help_insights_section | grep -qi 'decline' \
  && ok "(k) agent-help.md's /insights entry says it can decline" \
  || no "(k) agent-help.md's /insights entry does not mention declining"
help_insights_section | grep -qF 'curation.thresholds.insights' \
  && ok "(k) agent-help.md's /insights entry names the threshold override key" \
  || no "(k) agent-help.md's /insights entry omits .curation.thresholds.insights"
# The window on the remote count is documented where the count is consumed.
grep -qF -- '--limit 50' "$PROBE" \
  && ok "(k) curation-status.sh header documents the gh --limit 50 window" \
  || no "(k) curation-status.sh does not document the --limit 50 window"
grep -qF -- 'limit 50' "$PM" \
  && ok "(k) pr-postmortem.md documents the 50-most-recent-merged window (lower bound)" \
  || no "(k) pr-postmortem.md does not document the gh --limit 50 window"

# ============================================================================
echo "== (l) /pr-postmortem remote count: gh's EXIT STATUS decides, not empty output =="
# THE CONFLATION THIS PINS: `merged=$(gh ... || true); [ -n "$merged" ] || unknown`
# reports `unknown` for a SUCCESSFUL call on a repo with zero merged PRs — an
# examined input reported as could-not-examine, exactly what the script header
# forbids. Non-zero exit ⇒ unknown; zero exit with empty output ⇒ an honest 0.
# Everything here runs against a gh STUB on PATH: no network, and the pure
# set-diff (pending_from_merged) is exercised through it without a real gh.
GHBIN="$ROOT/gh-bin"
mk_bin "$GHBIN" $BASE_TOOLS jq
# run_gh <repo> <stub-body-file-content...> — install a gh stub emitting $1 with
# exit status $2, then run `status --json` with the remote valve LEFT ON.
GHOUT="$ROOT/gh-stub-out"; GHRC="$ROOT/gh-stub-rc"; GHLOG="$ROOT/gh-stub-args.log"
rm -f "$GHBIN/gh"
cat > "$GHBIN/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$GHLOG"
cat "$GHOUT" 2>/dev/null
exit "\$(cat "$GHRC" 2>/dev/null || echo 0)"
EOF
chmod +x "$GHBIN/gh"
run_gh() {
  local repo="$1" out="$2" rc="$3"
  printf '%s' "$out" > "$GHOUT"
  printf '%s' "$rc" > "$GHRC"
  ( cd "$repo" && PATH="$GHBIN:$PATH" bash "$PROBE" status --json 2>&1; printf '%s' "$?" > "$RCFILE" )
}

RL="$(new_repo)"
( cd "$RL" && git remote add origin https://example.invalid/o/r.git ) >/dev/null 2>&1
mkdir -p "$RL/.supervisor/postmortem"
cat > "$RL/.supervisor/postmortem/results.jsonl" <<'EOF'
{"ts":"2026-01-01T00:00:00Z","source":"manual_postmortem","number":101}
{"ts":"2026-01-02T00:00:00Z","source":"automate_drain","automate_key":"k","number":102}
{ not json
EOF

# rc 0, EMPTY output — a repo with genuinely zero merged PRs. The honest answer
# is 0, and it must be distinguishable from the failure below.
outL="$(run_gh "$RL" '' 0)"
pL="$(jget "$outL" '.commands.pr_postmortem.pending')"
[ "$(lastrc)" -eq 0 ] && ok "(l) exits 0 with the gh stub on PATH" || no "(l) rc=$(lastrc)"
[ "$pL" = "0" ] \
  && ok "(l) gh exits 0 with NO merged PRs ⇒ pending=0 (examined, and there is nothing)" \
  || no "(l) expected pending=0 for a successful empty gh call, got '$pL'"

# rc non-zero — gh missing auth / no network / API error. Could-not-examine.
outL2="$(run_gh "$RL" '' 1)"
[ "$(jget "$outL2" '.commands.pr_postmortem.pending')" = "unknown" ] \
  && ok "(l) gh exits NON-ZERO ⇒ pending=unknown (could not examine)" \
  || no "(l) expected unknown for a failing gh call, got '$(jget "$outL2" '.commands.pr_postmortem.pending')'"

# rc non-zero WITH partial output — the status must still win over the bytes.
outL3="$(run_gh "$RL" '101
999' 1)"
[ "$(jget "$outL3" '.commands.pr_postmortem.pending')" = "unknown" ] \
  && ok "(l) gh exits NON-ZERO but PRINTED rows ⇒ still unknown (status wins over bytes)" \
  || no "(l) expected unknown for a failing-but-noisy gh call, got '$(jget "$outL3" '.commands.pr_postmortem.pending')'"

# The pure set-diff, driven through the stub: 101 is in the ledger, 998/999 are not.
outL4="$(run_gh "$RL" '101
998
999' 0)"
[ "$(jget "$outL4" '.commands.pr_postmortem.pending')" = "2" ] \
  && ok "(l) set-diff: 3 merged, 1 in the ledger ⇒ pending=2" \
  || no "(l) expected pending=2, got '$(jget "$outL4" '.commands.pr_postmortem.pending')'"
# A drain-authored record still COUNTS as ledger presence here: this column asks
# "is this PR in the corpus at all", not "did a human run /pr-postmortem on it".
outL5="$(run_gh "$RL" '101
102' 0)"
[ "$(jget "$outL5" '.commands.pr_postmortem.pending')" = "0" ] \
  && ok "(l) set-diff: every merged PR present in the ledger ⇒ pending=0" \
  || no "(l) expected pending=0, got '$(jget "$outL5" '.commands.pr_postmortem.pending')'"
# Non-numeric rows in gh's output are skipped, never counted as a missing PR.
outL6="$(run_gh "$RL" 'not-a-number
101' 0)"
[ "$(jget "$outL6" '.commands.pr_postmortem.pending')" = "0" ] \
  && ok "(l) non-numeric gh rows are skipped, not counted as missing" \
  || no "(l) expected pending=0 with a non-numeric row, got '$(jget "$outL6" '.commands.pr_postmortem.pending')'"
# The window is the one documented in the header — asserted on the real argv.
grep -qF -- '--limit 50' "$GHLOG" \
  && ok "(l) gh is invoked with the documented --limit 50 window" \
  || no "(l) expected '--limit 50' in the gh stub's arg log: $(cat "$GHLOG" 2>/dev/null)"
# …and the valve still wins over everything: REMOTE=0 makes no gh call at all.
rm -f "$GHLOG"
outL7="$(run "$RL" status --json)"   # run() sets LOOMWRIGHT_CURATION_REMOTE=0
[ "$(jget "$outL7" '.commands.pr_postmortem.pending')" = "unknown" ] \
  && ok "(l) LOOMWRIGHT_CURATION_REMOTE=0 ⇒ pending=unknown, gh never consulted" \
  || no "(l) expected unknown with the remote valve off, got '$(jget "$outL7" '.commands.pr_postmortem.pending')'"

# THE SAME CONFLATION, ONE GUARD CLAUSE LATER: an ABSENT ledger is not an
# unreadable one. A repo that has simply never run /pr-postmortem has an honest,
# computable answer — every merged PR is missing from a ledger that does not
# exist — and `derive_postmortem_last_run` already draws exactly this line
# (`[ -e ] || never` THEN `[ -r ] || unknown`). A single `[ -r ]` guard here
# collapses both into `unknown` and fabricates a could-not-examine on first run.
# This needs BOTH a working gh stub AND a missing ledger: the (d) absent-ledger
# fixture runs under LOOMWRIGHT_CURATION_REMOTE=0 and never reaches this guard,
# and the RL fixture above always pre-creates the ledger.
RLA="$(new_repo)"
( cd "$RLA" && git remote add origin https://example.invalid/o/r.git ) >/dev/null 2>&1
[ -e "$RLA/.supervisor/postmortem/results.jsonl" ] \
  && no "(l) absent-ledger fixture is not actually ledger-less" \
  || ok "(l) absent-ledger fixture control: no results.jsonl on disk"
outL8="$(run_gh "$RLA" '301
302
303' 0)"
[ "$(lastrc)" -eq 0 ] && ok "(l) exits 0 with an absent ledger and a working gh" || no "(l) rc=$(lastrc)"
[ "$(jget "$outL8" '.commands.pr_postmortem.pending')" = "3" ] \
  && ok "(l) ABSENT ledger + 3 merged PRs ⇒ pending=3 (never run ≠ could not examine)" \
  || no "(l) expected pending=3 for an absent ledger, got '$(jget "$outL8" '.commands.pr_postmortem.pending')'"

# …and the other half of the distinction: a ledger that EXISTS but cannot be read
# IS a genuine could-not-examine. Same uid-0 guard as (d)/(m) — chmod 000 does not
# block reads for root, so assert nothing rather than pass for the wrong reason.
RLU="$(new_repo)"
( cd "$RLU" && git remote add origin https://example.invalid/o/r.git ) >/dev/null 2>&1
mkdir -p "$RLU/.supervisor/postmortem"
echo '{"ts":"2026-01-01T00:00:00Z","source":"manual_postmortem","number":301}' \
  > "$RLU/.supervisor/postmortem/results.jsonl"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  skp "(l) unreadable-ledger-with-gh fixture SKIPPED — running as uid 0, where chmod 000 does not block reads"
else
  chmod 000 "$RLU/.supervisor/postmortem/results.jsonl" 2>/dev/null || true
  outL9="$(run_gh "$RLU" '301
302
303' 0)"
  [ "$(lastrc)" -eq 0 ] && ok "(l) exits 0 with an unreadable ledger and a working gh" || no "(l) rc=$(lastrc)"
  [ "$(jget "$outL9" '.commands.pr_postmortem.pending')" = "unknown" ] \
    && ok "(l) PRESENT-but-unreadable ledger + working gh ⇒ pending=unknown (a real could-not-examine)" \
    || no "(l) expected pending=unknown for an unreadable ledger, got '$(jget "$outL9" '.commands.pr_postmortem.pending')'"
  chmod 644 "$RLU/.supervisor/postmortem/results.jsonl" 2>/dev/null || true
fi

# ============================================================================
echo "== (m) unreadable .supervisor/logs/ ⇒ pending unknown, never a fabricated 0 =="
# This branch drives whether /dreaming and /insights report a real count or
# never decline. A fabricated 0 here would be the silent failure: the glob
# simply fails to expand on an unsearchable directory, so the count would come
# back 0 and the commands would decline on a corpus they never read.
# chmod 000 does NOT block reads for uid 0, so skip visibly under a root CI
# executor rather than asserting something untrue (same guard as (d)).
RM="$(new_repo)"
mkdir -p "$RM/.supervisor/logs"
for n in 1 2 3; do echo '{}' > "$RM/.supervisor/logs/s$n.jsonl"; done
outM0="$(run "$RM" status --json)"
[ "$(jget "$outM0" '.commands.dreaming.pending')" = "3" ] \
  && ok "(m) control — the readable fixture counts its 3 logs" \
  || no "(m) control: expected pending=3, got '$(jget "$outM0" '.commands.dreaming.pending')'"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  skp "(m) unreadable-logs-dir fixture SKIPPED — running as uid 0, where chmod 000 does not block reads"
else
  chmod 000 "$RM/.supervisor/logs" 2>/dev/null || true
  outM="$(run "$RM" status --json)"
  [ "$(lastrc)" -eq 0 ] && ok "(m) status exits 0 on an unreadable logs dir" || no "(m) rc=$(lastrc)"
  [ "$(jget "$outM" '.commands.dreaming.pending')" = "unknown" ] \
    && ok "(m) unreadable logs dir ⇒ /dreaming pending=unknown (NOT a fabricated 0)" \
    || no "(m) expected pending=unknown, got '$(jget "$outM" '.commands.dreaming.pending')'"
  [ "$(jget "$outM" '.commands.dreaming.ready')" = "unknown" ] \
    && ok "(m) unreadable logs dir ⇒ ready=unknown (the gate cannot decline on it)" \
    || no "(m) expected ready=unknown, got '$(jget "$outM" '.commands.dreaming.ready')'"
  [ -z "$(jget "$outM" '.commands.dreaming.decline_message')" ] \
    && ok "(m) unreadable logs dir ⇒ EMPTY decline_message" \
    || no "(m) unreadable logs dir produced a decline: $(jget "$outM" '.commands.dreaming.decline_message')"
  # …and the nudge does NOT go silent on it — `unknown` means do not suppress.
  outM2="$(run "$RM" nudge)"
  printf '%s' "$outM2" | grep -qF '/dreaming unknown unreflected session log' \
    && ok "(m) unreadable logs dir ⇒ the nudge still fires, carrying 'unknown'" \
    || no "(m) expected the nudge to fire with an unknown count, got: $outM2"
  chmod 755 "$RM/.supervisor/logs" 2>/dev/null || true
fi

# ============================================================================
echo "== (n) /dreaming pending is an unconsumed SET, and a run drains exactly what it read =="
# THE REGRESSION THIS PINS (v15.29.0): `record` stamped wall-clock `now`, and
# pending was "logs newer than that stamp". Because /dreaming consumes the
# --sessions N MOST RECENT logs, everything it did NOT read was OLDER than the
# stamp — so one run silently retired the entire unread backlog. Here: 6 logs,
# a run reads the 2 newest, and the 4 older ones must SURVIVE as pending.
RN="$(new_repo)"
mkdir -p "$RN/.supervisor/logs"
i=0
for stamp in 202601010000 202601020000 202601030000 202601040000 202601050000 202601060000; do
  i=$((i+1)); printf '{"event":"session_end","n":%s}\n' "$i" > "$RN/.supervisor/logs/s$i.jsonl"
  touch -t "$stamp" "$RN/.supervisor/logs/s$i.jsonl"
done
outN0="$(run "$RN" status --json)"
[ "$(jget "$outN0" '.commands.dreaming.pending')" = "6" ] \
  && ok "(n) 6 logs, none consumed ⇒ pending = 6" \
  || no "(n) expected pending=6, got '$(jget "$outN0" '.commands.dreaming.pending')'"

# A run that read the 2 NEWEST logs names them.
outNrec="$(run "$RN" record dreaming s6 s5)"
[ "$(lastrc)" -eq 0 ] && ok "(n) record with ids exits 0" || no "(n) record rc=$(lastrc)"
outN1="$(run "$RN" status --json)"
[ "$(jget "$outN1" '.commands.dreaming.pending')" = "4" ] \
  && ok "(n) after reading the 2 NEWEST, pending falls to exactly 4 — by what was read, not to zero" \
  || no "(n) expected pending=4, got '$(jget "$outN1" '.commands.dreaming.pending')'"
# The four survivors are the OLDER ones — the set a watermark could never count.
[ "$(run "$RN" status --json | jq -r '.commands.dreaming.last_run')" != "never" ] \
  && ok "(n) last_run was stamped by the same call" \
  || no "(n) last_run not stamped"

# The v15.29.0 shape, stated as a red: a SECOND run that reads nothing must NOT
# retire the 4 survivors. Under a wall-clock watermark this collapses to 0.
outN2="$(run "$RN" record dreaming)"
outN3="$(run "$RN" status --json)"
[ "$(jget "$outN3" '.commands.dreaming.pending')" = "4" ] \
  && ok "(n) a later run that consumed NOTHING leaves pending at 4 (a wall-clock watermark would report 0)" \
  || no "(n) the unread backlog was silently retired: pending='$(jget "$outN3" '.commands.dreaming.pending')'"
printf '%s' "$outN2" | grep -qF 'NO logs were named' \
  && ok "(n) recording zero ids WARNS that pending will not fall" \
  || no "(n) zero-id record did not warn: $outN2"

# Draining the remaining 4 reaches a real zero — the set is genuinely additive.
run "$RN" record dreaming s1 s2 s3 s4 >/dev/null
[ "$(run "$RN" status --json | jq -r '.commands.dreaming.pending')" = "0" ] \
  && ok "(n) naming the remaining 4 drains pending to 0 (ids UNION across calls)" \
  || no "(n) expected pending=0 after draining all 6"
# …and re-recording an already-consumed id is idempotent, never negative.
run "$RN" record dreaming s1 s1 s2 >/dev/null
[ "$(run "$RN" status --json | jq -r '.commands.dreaming.pending')" = "0" ] \
  && ok "(n) re-recording consumed ids is idempotent (unique), never double-counts" \
  || no "(n) duplicate ids perturbed the count"

# ============================================================================
echo "== (o) the count names the WINDOW that will drain it, pinned to dreaming.md =="
# GAP 1: v15.29.0 reported `pending=61 ready=yes` for a run whose --sessions
# default consumes 5. The readiness gate and the consumption window lived in two
# files with NOTHING asserting a relationship — this is that assertion.
doc_window="$(grep -E '^\| `--sessions N` \|' "$PLUGIN_ROOT/commands/dreaming.md" 2>/dev/null \
              | sed -E 's/^\|[^|]*\|[^|]*\| *`?([0-9]+)`? *\|.*/\1/' | head -1)"
script_window="$(grep -E '^DREAMING_DEFAULT_WINDOW=[0-9]+' "$PROBE" 2>/dev/null \
                 | sed -E 's/^DREAMING_DEFAULT_WINDOW=([0-9]+).*/\1/' | head -1)"
[ -n "$doc_window" ] \
  && ok "(o) commands/dreaming.md declares a numeric --sessions default ($doc_window)" \
  || no "(o) could not extract the --sessions default from commands/dreaming.md"
[ -n "$script_window" ] \
  && ok "(o) curation-status.sh declares DREAMING_DEFAULT_WINDOW ($script_window)" \
  || no "(o) could not extract DREAMING_DEFAULT_WINDOW from the probe"
[ -n "$doc_window" ] && [ "$doc_window" = "$script_window" ] \
  && ok "(o) the probe's window MIRRORS dreaming.md's Parameters table — the cross-file pin" \
  || no "(o) window drift: dreaming.md says '$doc_window', probe says '$script_window'"

outO="$(run "$RN" status)"   # RN now has 6 logs, all consumed ⇒ pending 0
printf '%s' "$outO" | grep -qF "window=$script_window" \
  && ok "(o) the /dreaming status row states the window alongside the count" \
  || no "(o) status row omits window=: $outO"
printf '%s' "$outO" | grep -qF 'note(/dreaming)' \
  && no "(o) window note fired with pending(0) <= window — it should be silent" \
  || ok "(o) pending <= window ⇒ no window note (nothing is being left behind)"
# …and it DOES fire when the backlog exceeds one run's reach.
RO="$(new_repo)"; mkdir -p "$RO/.supervisor/logs"
n=0; while [ "$n" -lt 9 ]; do n=$((n+1)); printf '{"event":"session_end"}\n' > "$RO/.supervisor/logs/w$n.jsonl"; done
outO2="$(run "$RO" status)"
printf '%s' "$outO2" | grep -qF 'note(/dreaming)' \
  && ok "(o) pending(9) > window ⇒ the note says the rest stay pending" \
  || no "(o) expected a window note at pending 9 > window $script_window: $outO2"
printf '%s' "$outO2" | grep -qE 'reads the [0-9]+ most recent UNCONSUMED of those 9 logs' \
  && ok "(o) the note names BOTH numbers (window and backlog), not just the backlog" \
  || no "(o) the note does not name both numbers: $outO2"
[ "$(jget "$(run "$RO" status --json)" '.commands.dreaming.window')" = "$script_window" ] \
  && ok "(o) --json carries .commands.dreaming.window too" \
  || no "(o) --json window missing/wrong"

# ============================================================================
echo "== (p) pending counts logs carrying reflection SIGNAL, not raw files =="
# Measured on the real repo 2026-08-09: 29 of 62 logs held ONLY token_ledger and
# subtask_complete events — ~96% of corpus bytes carrying 0% of the signal. A raw
# file count overstated the backlog by 1.9x. Both predicates FAIL OPEN.
RP="$(new_repo)"; mkdir -p "$RP/.supervisor/logs"
# 3 noise-only logs (many lines each, so this is not passing by being empty)
for n in 1 2 3; do
  : > "$RP/.supervisor/logs/noise$n.jsonl"
  k=0; while [ "$k" -lt 5 ]; do
    k=$((k+1))
    printf '{"event":"token_ledger","k":%s}\n' "$k" >> "$RP/.supervisor/logs/noise$n.jsonl"
    printf '{"event":"subtask_complete","k":%s}\n' "$k" >> "$RP/.supervisor/logs/noise$n.jsonl"
  done
done
# 1 log that is mostly noise but carries ONE real event — it must count
printf '{"event":"token_ledger"}\n{"event":"session_end","status":"ok"}\n{"event":"token_ledger"}\n' \
  > "$RP/.supervisor/logs/mixed.jsonl"
outP="$(run "$RP" status --json)"
[ "$(jget "$outP" '.commands.dreaming.pending')" = "1" ] \
  && ok "(p) 4 files, 3 noise-only ⇒ /dreaming pending = 1, not 4" \
  || no "(p) expected /dreaming pending=1, got '$(jget "$outP" '.commands.dreaming.pending')'"
[ "$(jget "$outP" '.commands.insights.pending')" = "1" ] \
  && ok "(p) /insights counts only logs carrying session_end (its sole input) ⇒ 1" \
  || no "(p) expected /insights pending=1, got '$(jget "$outP" '.commands.insights.pending')'"
# The two predicates are genuinely DIFFERENT, not one shared filter: a log with a
# non-noise event that is NOT session_end counts for /dreaming and not /insights.
printf '{"event":"pr_created","url":"x"}\n' > "$RP/.supervisor/logs/pronly.jsonl"
outP2="$(run "$RP" status --json)"
[ "$(jget "$outP2" '.commands.dreaming.pending')" = "2" ] \
  && ok "(p) a pr_created-only log counts for /dreaming (broad reader)" \
  || no "(p) expected /dreaming pending=2, got '$(jget "$outP2" '.commands.dreaming.pending')'"
[ "$(jget "$outP2" '.commands.insights.pending')" = "1" ] \
  && ok "(p) …and NOT for /insights, which consumes session_end alone" \
  || no "(p) expected /insights pending=1, got '$(jget "$outP2" '.commands.insights.pending')'"
# FAIL OPEN: a log whose shape the predicate cannot recognise counts as signal.
printf 'not json at all\n' > "$RP/.supervisor/logs/weird.jsonl"
[ "$(jget "$(run "$RP" status --json)" '.commands.dreaming.pending')" = "3" ] \
  && ok "(p) an unrecognisable log counts as SIGNAL (fail open — never silently suppressed)" \
  || no "(p) unrecognisable log was dropped from the count (fail-closed regression)"
# …and so does a log we cannot READ. This is the arm grep answers with exit 2;
# it is only reachable because log_has_signal has no `[ -r ]` pre-guard, and a
# mutation flipping it to fail-closed must be caught here.
printf '{"event":"token_ledger"}\n' > "$RP/.supervisor/logs/locked.jsonl"
chmod 000 "$RP/.supervisor/logs/locked.jsonl" 2>/dev/null || true
if [ ! -r "$RP/.supervisor/logs/locked.jsonl" ]; then
  [ "$(jget "$(run "$RP" status --json)" '.commands.dreaming.pending')" = "4" ] \
    && ok "(p) an UNREADABLE log counts as signal (grep rc>1 ⇒ fail open, never suppressed)" \
    || no "(p) unreadable log was dropped from the count (fail-closed regression)"
else
  skp "(p) cannot create an unreadable file here (running as root?) — fail-open arm not exercisable"
fi
chmod 644 "$RP/.supervisor/logs/locked.jsonl" 2>/dev/null || true

# ============================================================================
echo "== (q) record hygiene: prune to disk, ids are data, malformed state ⇒ unknown =="
RQ="$(new_repo)"; mkdir -p "$RQ/.supervisor/logs"
printf '{"event":"session_end"}\n' > "$RQ/.supervisor/logs/real1.jsonl"
outQ="$(run "$RQ" record dreaming real1 ghost-that-does-not-exist)"
printf '%s' "$outQ" | grep -qF 'not on disk' \
  && ok "(q) an id with no log on disk is reported, not silently stored" \
  || no "(q) no report for the off-disk id: $outQ"
[ "$(jq -r '[.dreaming.consumed.logs[]] | length' "$RQ/.supervisor/curation-state.json")" = "1" ] \
  && ok "(q) only the on-disk id is persisted (an unmatchable id would subtract forever)" \
  || no "(q) consumed set holds $(jq -c '.dreaming.consumed.logs' "$RQ/.supervisor/curation-state.json")"
# An id containing WHITESPACE must survive whole. A `for id in $*` implementation
# splits it into fragments, none of which names a file, so the id is silently
# dropped and the run is recorded as having consumed nothing — its logs then stay
# pending forever. The id must be STORED, not merely "not crash".
printf '{"event":"session_end"}\n' > "$RQ/.supervisor/logs/has space.jsonl"
run "$RQ" record dreaming "has space" >/dev/null
jq -e '.dreaming.consumed.logs | index("has space")' "$RQ/.supervisor/curation-state.json" >/dev/null 2>&1 \
  && ok "(q) an id containing whitespace is recorded WHOLE (never word-split into fragments)" \
  || no "(q) whitespace id lost: $(jq -c '.dreaming.consumed.logs' "$RQ/.supervisor/curation-state.json" 2>/dev/null)"

# Ids reach jq via --args, so a hostile filename is DATA, never filter text.
# NOTE the id carries no spaces: a spaced one would be dropped before reaching jq
# and the arm would pass without ever exercising the injection it claims to test.
hostile='a")|.dreaming="pwned"|("'
if printf '{"event":"session_end"}\n' > "$RQ/.supervisor/logs/$hostile.jsonl" 2>/dev/null \
   && [ -f "$RQ/.supervisor/logs/$hostile.jsonl" ]; then
  run "$RQ" record dreaming "$hostile" >/dev/null
  jq -e --arg h "$hostile" '.dreaming.consumed.logs | index($h)' "$RQ/.supervisor/curation-state.json" >/dev/null 2>&1 \
    && ok "(q) the hostile id was actually STORED — the injection arm is genuinely exercised" \
    || no "(q) hostile id never reached the store; this arm proves nothing"
  [ "$(jq -r '.dreaming.last_run | type' "$RQ/.supervisor/curation-state.json" 2>/dev/null)" = "string" ] \
    && ok "(q) …and a filename full of jq metacharacters stayed DATA — state file intact" \
    || no "(q) hostile id corrupted the state file"
  [ "$(jq -r '.dreaming' "$RQ/.supervisor/curation-state.json" 2>/dev/null)" != "pwned" ] \
    && ok "(q) …and the injected filter body did not execute" \
    || no "(q) jq filter injection SUCCEEDED"
else
  skp "(q) filesystem rejected the hostile filename — injection arm not exercisable here"
fi
# A state file we cannot PARSE must not yield a confident backlog number.
printf 'not json' > "$RQ/.supervisor/curation-state.json"
[ "$(jget "$(run "$RQ" status --json)" '.commands.dreaming.pending')" = "unknown" ] \
  && ok "(q) unparseable state ⇒ pending 'unknown', never every-log-is-pending" \
  || no "(q) unparseable state fabricated a count: '$(jget "$(run "$RQ" status --json)" '.commands.dreaming.pending')'"
# …but a state file that PARSES and simply has no consumed key is a real answer.
printf '{"dreaming":{"last_run":"2026-01-01T00:00:00Z"}}' > "$RQ/.supervisor/curation-state.json"
[ "$(jget "$(run "$RQ" status --json)" '.commands.dreaming.pending')" != "unknown" ] \
  && ok "(q) parseable state with no consumed key ⇒ a real count (absent ≠ unexaminable)" \
  || no "(q) a readable recordless state was reported as unexaminable"

# A state file that EXISTS and is perfectly well-formed but cannot be READ is
# the third rung of the ladder, and it is distinct from both neighbours: the
# `[ -e ]` guard above it says "something is recorded", so we may not answer
# with the absent-record count, and we never got far enough to parse it, so we
# may not answer with a parsed one either. A mutation relaxing the `[ -r ]`
# guard to `return 0` would silently treat the unreadable record as an EMPTY
# consumed set and report every log on disk as unreflected — a confident backlog
# manufactured out of an input we failed to read. chmod 000 does not block reads
# for uid 0, so skip visibly under a root executor rather than pass for the
# wrong reason.
RQU="$(new_repo)"; mkdir -p "$RQU/.supervisor/logs"
printf '{"event":"session_end"}\n' > "$RQU/.supervisor/logs/s1.jsonl"
printf '{"dreaming":{"last_run":"2026-01-01T00:00:00Z","consumed":{"logs":["s1"]}}}' \
  > "$RQU/.supervisor/curation-state.json"
chmod 000 "$RQU/.supervisor/curation-state.json" 2>/dev/null || true
if [ ! -r "$RQU/.supervisor/curation-state.json" ]; then
  outQU="$(run "$RQU" status --json)"
  [ "$(lastrc)" -eq 0 ] && ok "(q) status exits 0 on an unreadable state file" || no "(q) unreadable state rc=$(lastrc)"
  [ "$(jget "$outQU" '.commands.dreaming.pending')" = "unknown" ] \
    && ok "(q) unreadable state ⇒ pending 'unknown' (an unexaminable record never yields a number)" \
    || no "(q) unreadable state fabricated a count: '$(jget "$outQU" '.commands.dreaming.pending')'"
else
  skp "(q) unreadable-state fixture SKIPPED — running as uid 0, where chmod 000 does not block reads"
fi
chmod 644 "$RQU/.supervisor/curation-state.json" 2>/dev/null || true

# THE WRITE PATH OWES THE SAME LADDER THE READ PATHS WALK — and this is where it
# costs history rather than a number. `record` used to fold "unreadable" into
# "absent": the existing-state read fell back to `{}`, and the write then landed
# anyway, because `mv` renames into a WRITABLE DIRECTORY and never consults the
# old file's permission bits. The whole consumed set was replaced by the ids of
# the current run, every previously consumed log silently returned to `pending`
# forever, and the command printed a confident "newly consumed: 1" computed
# against a baseline of zero it had never actually seen. Reading it wrong is a
# bad answer; writing over it is unrecoverable, so the guard must refuse to write
# at all. Same uid-0 caveat as the fixture above: chmod 000 does not block root.
RQW="$(new_repo)"; mkdir -p "$RQW/.supervisor/logs"
for s in s1 s2 s3 s4 s5 s6; do printf '{"event":"session_end"}\n' > "$RQW/.supervisor/logs/$s.jsonl"; done
run "$RQW" record dreaming s1 s2 s3 s4 >/dev/null
[ "$(jq -r '.dreaming.consumed.logs | length' "$RQW/.supervisor/curation-state.json" 2>/dev/null)" = "4" ] \
  && ok "(q) baseline: four ids are consumed before the state file is made unreadable" \
  || no "(q) baseline consumed set is not 4: $(jq -c '.dreaming.consumed.logs' "$RQW/.supervisor/curation-state.json" 2>/dev/null)"
chmod 000 "$RQW/.supervisor/curation-state.json" 2>/dev/null || true
if [ ! -r "$RQW/.supervisor/curation-state.json" ]; then
  outQW="$(run "$RQW" record dreaming s5)"
  [ "$(lastrc)" -eq 0 ] \
    && ok "(q) record exits 0 on an unreadable state file (always-exit-0 invariant holds on the refusal path)" \
    || no "(q) record rc=$(lastrc) on an unreadable state file"
  printf '%s' "$outQW" | grep -qF 'NOT recorded' \
    && ok "(q) record SAYS it did not record, rather than reporting a write it refused to make" \
    || no "(q) record did not report the refusal: $outQW"
  printf '%s' "$outQW" | grep -qF 'destroy the consumed history' \
    && ok "(q) …and names the stake — overwriting would destroy the consumed history" \
    || no "(q) refusal does not explain the stake: $outQW"
  chmod 644 "$RQW/.supervisor/curation-state.json" 2>/dev/null || true
  jq -e '(.dreaming.consumed.logs | sort) == ["s1","s2","s3","s4"]' \
     "$RQW/.supervisor/curation-state.json" >/dev/null 2>&1 \
    && ok "(q) the four consumed ids SURVIVED — an unexaminable record is not licence to overwrite it" \
    || no "(q) consumed history was destroyed: $(jq -c '.dreaming.consumed.logs' "$RQW/.supervisor/curation-state.json" 2>/dev/null)"
  jq -e '.dreaming.consumed.logs | index("s5") | not' \
     "$RQW/.supervisor/curation-state.json" >/dev/null 2>&1 \
    && ok "(q) …and s5 was NOT added, so the refusal was total rather than a partial write" \
    || no "(q) s5 was recorded despite the refusal message"
else
  skp "(q) unreadable-state WRITE fixture SKIPPED — running as uid 0, where chmod 000 does not block reads"
fi
chmod 644 "$RQW/.supervisor/curation-state.json" 2>/dev/null || true

# ============================================================================
echo "== (r) unconsumed: the selection that actually DRAINS the backlog (8 → 3 → 0) =="
# THE DEFECT THIS PINS. GATHER used to select the `--sessions N` most recent logs
# BY MTIME, unconditionally. New sessions are always newer, so a log that fell out
# of the newest-N window could NEVER re-enter it and the unconsumed backlog was
# monotonically non-decreasing: measured on 8 signal-carrying logs with a window
# of 5, successive default runs gave pending 8 → 3 → 3 → 3 … forever, and s1/s2/s3
# were never read. Selecting the most recent UNCONSUMED logs keeps the recency
# bias AND lets repeated runs walk backwards through the tail: 8 → 3 → 0.
#
# stdout is the machine-readable id list, so these helpers keep stdout and stderr
# apart — run() folds them together, which would make the fail-open assertion
# below pass on a prose line printed into the id list.
run_out() {   # stdout only; rc stashed in RCFILE like run()
  local repo="$1"; shift
  ( cd "$repo" && LOOMWRIGHT_CURATION_REMOTE=0 bash "$PROBE" "$@" 2>/dev/null; printf '%s' "$?" > "$RCFILE" )
}
run_err() {   # stderr only
  local repo="$1"; shift
  ( cd "$repo" && LOOMWRIGHT_CURATION_REMOTE=0 bash "$PROBE" "$@" 2>&1 >/dev/null; printf '%s' "$?" > "$RCFILE" )
}
# consume_round <repo> <N> — one simulated default /dreaming run: take exactly
# what `unconsumed N` reports and record precisely those ids. Echoes how many ids
# the round consumed. Ids arrive newline-separated, so IFS is set to a newline
# (with globbing off) rather than relying on default word-splitting.
consume_round() {
  local repo="$1" n="$2" ids oldIFS
  ids="$(run_out "$repo" unconsumed "$n")"
  if [ -z "$ids" ]; then printf '0'; return 0; fi
  oldIFS="$IFS"; set -f; IFS='
'
  set -- $ids
  IFS="$oldIFS"; set +f
  ( cd "$repo" && LOOMWRIGHT_CURATION_REMOTE=0 bash "$PROBE" record dreaming "$@" >/dev/null 2>&1 )
  printf '%s' "$#"
}
dpending() { jget "$(run "$1" status --json)" '.commands.dreaming.pending'; }

RR="$(new_repo)"; mkdir -p "$RR/.supervisor/logs"
i=0
for stamp in 202601010000 202601020000 202601030000 202601040000 \
             202601050000 202601060000 202601070000 202601080000; do
  i=$((i+1))
  printf '{"event":"session_end","n":%s}\n' "$i" > "$RR/.supervisor/logs/s$i.jsonl"
  touch -t "$stamp" "$RR/.supervisor/logs/s$i.jsonl"
done   # s8 is the NEWEST, s1 the oldest

[ "$(dpending "$RR")" = "8" ] \
  && ok "(r) control — 8 signal-carrying logs, none consumed ⇒ pending 8" \
  || no "(r) control: expected pending=8, got '$(dpending "$RR")'"

# Ordering: newest mtime FIRST. Assert the exact ends of the list.
listR="$(run_out "$RR" unconsumed)"
[ "$(lastrc)" -eq 0 ] && ok "(r) unconsumed exits 0" || no "(r) unconsumed rc=$(lastrc)"
[ "$(printf '%s\n' "$listR" | head -1)" = "s8" ] \
  && ok "(r) unconsumed is NEWEST-first (first id is s8)" \
  || no "(r) expected s8 first, got '$(printf '%s\n' "$listR" | head -1)'"
[ "$(printf '%s\n' "$listR" | tail -1)" = "s1" ] \
  && ok "(r) …and oldest-last (last id is s1)" \
  || no "(r) expected s1 last, got '$(printf '%s\n' "$listR" | tail -1)'"
[ "$(printf '%s\n' "$listR" | grep -c .)" = "8" ] \
  && ok "(r) unconsumed with NO N returns all 8 unconsumed ids" \
  || no "(r) expected 8 ids with no limit, got $(printf '%s\n' "$listR" | grep -c .)"
[ "$(run_out "$RR" unconsumed 5 | grep -c .)" = "5" ] \
  && ok "(r) unconsumed N respects the limit (5 of 8)" \
  || no "(r) expected 5 ids for 'unconsumed 5', got $(run_out "$RR" unconsumed 5 | grep -c .)"

# THE CORE ASSERTION — two successive default runs must drain 8 → 3 → 0.
# Under the OLD newest-by-mtime selection round 2 re-reads s8..s4 and pending
# stalls at 3 forever, so this fails RED the moment `unconsumed` regresses to
# plain recency.
r1="$(consume_round "$RR" 5)"
[ "$r1" = "5" ] && ok "(r) run 1 consumed 5 ids" || no "(r) run 1 consumed '$r1', expected 5"
[ "$(dpending "$RR")" = "3" ] \
  && ok "(r) after run 1 pending falls 8 → 3" \
  || no "(r) after run 1 expected pending=3, got '$(dpending "$RR")'"
# Round 2 must return the OLD tail, not the newest again.
tail2="$(run_out "$RR" unconsumed 5)"
[ "$(printf '%s\n' "$tail2" | head -1)" = "s3" ] \
  && ok "(r) run 2 selects the next-newest UNCONSUMED (s3), not s8 again" \
  || no "(r) run 2 head expected s3, got '$(printf '%s\n' "$tail2" | head -1)'"
r2="$(consume_round "$RR" 5)"
[ "$r2" = "3" ] && ok "(r) run 2 consumed the remaining 3" || no "(r) run 2 consumed '$r2', expected 3"
[ "$(dpending "$RR")" = "0" ] \
  && ok "(r) THE BACKLOG DRAINS: 8 → 3 → 0 (plain newest-by-mtime stalls at 3 forever)" \
  || no "(r) backlog did NOT drain — pending='$(dpending "$RR")' (the 8→3→3→3 stall)"

# Fully drained ⇒ NOTHING on stdout, still exit 0.
outR0="$(run_out "$RR" unconsumed)"
[ -z "$outR0" ] && ok "(r) everything consumed ⇒ unconsumed prints NOTHING on stdout" \
  || no "(r) expected empty stdout when drained, got: $outR0"
[ "$(lastrc)" -eq 0 ] && ok "(r) …and still exits 0" || no "(r) drained unconsumed rc=$(lastrc)"

# Noise-only logs are excluded — same predicate `pending` uses, not a second one.
RRN="$(new_repo)"; mkdir -p "$RRN/.supervisor/logs"
: > "$RRN/.supervisor/logs/noise.jsonl"
k=0; while [ "$k" -lt 5 ]; do
  k=$((k+1))
  printf '{"event":"token_ledger","k":%s}\n' "$k" >> "$RRN/.supervisor/logs/noise.jsonl"
  printf '{"event":"subtask_complete","k":%s}\n' "$k" >> "$RRN/.supervisor/logs/noise.jsonl"
done
printf '{"event":"session_end"}\n' > "$RRN/.supervisor/logs/real.jsonl"
outRN="$(run_out "$RRN" unconsumed)"
[ "$outRN" = "real" ] \
  && ok "(r) unconsumed excludes noise-only logs (only 'real' returned)" \
  || no "(r) expected just 'real', got: $outRN"

# An absent logs dir / absent .supervisor is silent and exit 0, never an error.
RRE="$(new_repo)"
outRE="$(run_out "$RRE" unconsumed)"
[ "$(lastrc)" -eq 0 ] && [ -z "$outRE" ] \
  && ok "(r) absent logs dir ⇒ silent, exit 0" \
  || no "(r) absent logs dir: rc=$(lastrc), out='$outRE'"

# FAIL OPEN on an unexaminable consumed record: list ALL signal logs rather than
# nothing. Re-reading a log is harmless; silently reading nothing is not — that
# would be the fail-CLOSED shape that hides the entire backlog. Same uid-0 guard
# as (d)/(m)/(q): chmod 000 does not block reads for root.
RRU="$(new_repo)"; mkdir -p "$RRU/.supervisor/logs"
for n in 1 2 3; do printf '{"event":"session_end"}\n' > "$RRU/.supervisor/logs/u$n.jsonl"; done
printf '{"dreaming":{"last_run":"2026-01-01T00:00:00Z","consumed":{"logs":["u1","u2","u3"]}}}' \
  > "$RRU/.supervisor/curation-state.json"
chmod 000 "$RRU/.supervisor/curation-state.json" 2>/dev/null || true
if [ ! -r "$RRU/.supervisor/curation-state.json" ]; then
  outRU="$(run_out "$RRU" unconsumed)"
  [ "$(lastrc)" -eq 0 ] && ok "(r) unreadable consumed record ⇒ exit 0" || no "(r) unreadable state rc=$(lastrc)"
  [ "$(printf '%s\n' "$outRU" | grep -c .)" = "3" ] \
    && ok "(r) unreadable consumed record ⇒ ALL 3 signal logs listed (fail OPEN, not silence)" \
    || no "(r) fail-open regression — expected 3 ids, got: $outRU"
  errRU="$(run_err "$RRU" unconsumed)"
  printf '%s' "$errRU" | grep -qF 'could not be read' \
    && ok "(r) …and the explanatory note goes to STDERR" \
    || no "(r) no stderr note for the unreadable consumed record: $errRU"
  printf '%s' "$outRU" | grep -qF 'could not be read' \
    && no "(r) the note leaked onto STDOUT — it would be consumed as a session id" \
    || ok "(r) …and NEVER onto stdout (stdout stays a pure id list)"
else
  skp "(r) unreadable-consumed-record fixture SKIPPED — running as uid 0, where chmod 000 does not block reads"
fi
chmod 644 "$RRU/.supervisor/curation-state.json" 2>/dev/null || true

# FIX 2: "newly consumed" is a REAL delta, not the count of ids forwarded to jq.
# `record dreaming s1 s1 s2` over an already-full set names 3 ids and adds none.
outR2="$(run "$RR" record dreaming s1 s1 s2)"
printf '%s' "$outR2" | grep -qF 'logs named: 3' \
  && ok "(r) record still reports the validated/named count (3)" \
  || no "(r) named count missing from: $outR2"
printf '%s' "$outR2" | grep -qF 'newly consumed: 0' \
  && ok "(r) re-recording already-consumed ids reports newly consumed: 0 (a real delta)" \
  || no "(r) expected 'newly consumed: 0', got: $outR2"
# …and a genuinely new id reports a delta of 1.
printf '{"event":"session_end"}\n' > "$RR/.supervisor/logs/s9.jsonl"
outR3="$(run "$RR" record dreaming s9 s1)"
printf '%s' "$outR3" | grep -qF 'newly consumed: 1' \
  && ok "(r) one new id among two named ⇒ newly consumed: 1" \
  || no "(r) expected 'newly consumed: 1', got: $outR3"

echo
if [ "$skip" -gt 0 ]; then
  echo "RESULT: $pass passed, $fail failed, $skip skipped"
else
  echo "RESULT: $pass passed, $fail failed"
fi
[ "$fail" -eq 0 ] || exit 1
exit 0
