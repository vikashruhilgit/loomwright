#!/usr/bin/env bash
# test-lens-run.sh — stub-backed self-tests for lens-run.sh. Mirrors this
# repo's stub-on-PATH testing convention (test-orca-mirror.sh) and its
# TMP-dir-plus-trap cleanup convention.
#
# The test writes its OWN provider-table entries into THIS directory
# (lens-run.sh resolves $SCRIPT_DIR/provider-$NAME.sh from its own
# BASH_SOURCE, so a stub provider must live here to be found at all) and
# removes them in its own EXIT trap — no test-only file is left behind on a
# clean exit (a SIGKILLed run can leave an untracked provider-teststub<n>.sh).
# Every per-run name — the provider-table entry provider-teststub<RUN_TAG>.sh
# and the stub CLI binary loomwright-test-stub-cli-<RUN_TAG> — carries
# RUN_TAG (this run's pid), so two suites running at once (two CI slots, or two
# runs in one checkout) never share a provider file or a stub name. Each
# scenario gets its OWN stub CLI binary (different PATH
# directories prepended per invocation) rather than one CLI branching on an
# env var, because lens-run.sh deliberately scrubs the child environment
# (`env -i`) before exec — any env var the test tried to use to steer stub
# behavior would be exactly the kind of leak the scrub exists to prevent, so
# per-scenario binaries are baked at generation time instead.
#
# Covers:
#   A. provider absent from PATH -> provider_unavailable, no subprocess
#      attempted (proxied by: the debug sandbox-path hatch never fires, i.e.
#      the run never got as far as creating the sandbox clone)
#   B. stub mutates the sandbox tree -> lens_mutated_tree, result discarded,
#      sandbox removed after, AND the PARENT repo's own `origin` remote is
#      still present afterward (proves the isolated-sandbox fix)
#   C. stub produces unparseable garbage -> lens_unparseable
#   D. stub produces well-formed JSON -> normalized issues[] matches
#      RESULT_SCHEMAS.md's exact fields (severity/category/file/line/
#      description/suggestion), including severity upcasing
#   E. scrubbed-env: GH_TOKEN is set in the test's OWN env, and must be
#      absent from the env the stub CLI actually observes
#   F. git remote remove origin fails -> fail-closed (CLI never runs)
#   G. stub mutates .git internals only (hook + remote; porcelain empty)
#      -> lens_mutated_tree (the reproduced porcelain-blind bypass)
#   H. hung CLI + LOOMWRIGHT_LENS_CLI_TIMEOUT=5 -> lens_unparseable,
#      process group killed, no leftover children — checked ONLY over the
#      pids/pgid this run's stub recorded, never a machine-wide name match
#   I. invalid --provider NAME (slash / `..`) -> provider_unavailable,
#      no source of a path outside $SCRIPT_DIR
#   J. missing provider-<name>.sh -> provider_unavailable
#   K. two overlapping lens-run.sh instances: B (released by a file, not a
#      timeout) is held alive while A (case H's hung CLI) times out — A's
#      scoped leftover checks pass with B's live stub on the machine, then B
#      is released and ends ok, not timed out
#   L. assert_no_leftovers self-check: forged pid files in this run's $TMP
#      make each refusal arm fire (missing leader pid, pgid != pid, pgid ==
#      the test's own group), probed in a subshell so the expected failures
#      never touch this suite's counters; plus a negative control (gone
#      record passes) and a positive control (a live setpgrp'd process is
#      flagged as a leftover, then killed)
#
# Exit 0 = all pass, 1 = any failure.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LENS="$HERE/lens-run.sh"
REPO_ROOT="$(cd "$HERE/../../../.." && pwd)"
BASH_BIN="$(command -v bash)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"; else no "$label (expected [$expected] got [$actual])"; fi
}
assert_true() {
  local label="$1" cond="$2"
  if [ "$cond" = "1" ]; then ok "$label"; else no "$label (condition false)"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "test-lens-run.sh: jq is required to run this suite"; echo "RESULT: 0 passed, 1 failed"; exit 1
fi
if [ ! -f "$LENS" ]; then
  echo "test-lens-run.sh: lens-run.sh not found at $LENS"; echo "RESULT: 0 passed, 1 failed"; exit 1
fi

TMP="$(mktemp -d)"
# Per-run identity. RUN_TAG is digits only, so every derived name passes
# lens-run.sh's provider-name allowlist [a-zA-Z0-9_-] (the basename of $TMP
# would not: macOS mktemp -d yields tmp.XXXXXXXX, and `.` is refused).
RUN_TAG="$$"
STUB_CLI_NAME="loomwright-test-stub-cli-$RUN_TAG"
PROVIDER_NAME="teststub$RUN_TAG"
PROVIDER_FILE="$HERE/provider-$PROVIDER_NAME.sh"
# Case K's second instance (B, the live neighbour) gets its own names and its
# own temp dir; its release file is written by the test (or by cleanup).
KB_STUB_CLI_NAME="$STUB_CLI_NAME-kb"
KB_PROVIDER_NAME="$PROVIDER_NAME-kb"
KB_PROVIDER_FILE="$HERE/provider-$KB_PROVIDER_NAME.sh"
KB_DIR="$TMP/k-b"
KB_RELEASE="$KB_DIR/release"
KB_LENS_PID=""
L_LIVE_PID=""
TEST_PGID="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
cleanup() {
  # An interrupted case K must not strand B: release its stub, then TERM B's
  # lens-run.sh (its own EXIT trap kills B's CLI process group). KB_LENS_PID is
  # this shell's own un-waited child, so its pid cannot have been reused.
  if [ -n "$KB_LENS_PID" ]; then
    : > "$KB_RELEASE" 2>/dev/null
    kill "$KB_LENS_PID" 2>/dev/null
    wait "$KB_LENS_PID" 2>/dev/null
    KB_LENS_PID=""
  fi
  # Case L's live positive-control process, if interrupted mid-block.
  if [ -n "$L_LIVE_PID" ]; then
    kill "$L_LIVE_PID" 2>/dev/null
    wait "$L_LIVE_PID" 2>/dev/null
    L_LIVE_PID=""
  fi
  rm -rf "$TMP"; rm -f "$PROVIDER_FILE" "$KB_PROVIDER_FILE"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---- test-only provider-table entries ---------------------------------------
# write_provider <file> <cli-name> — the CLI name is the only per-run value; it
# is written by printf OUTSIDE the quoted heredocs, so nothing else in the
# provider body is subject to expansion.
write_provider() {
  local file="$1" cli="$2"
  {
    cat <<'PROVIDER'
#!/usr/bin/env bash
# provider-teststub<RUN_TAG>.sh — TEST-ONLY provider-table entry, written by
# test-lens-run.sh at test start and removed in its own EXIT trap. Not a real
# provider; exists only to satisfy lens-run.sh's $SCRIPT_DIR/provider-<name>.sh
# lookup convention. See lens-run.sh's own header for the per-provider-file
# contract these globals/functions implement.
PROVIDER
    printf 'PROVIDER_CLI_NAME="%s"\n' "$cli"
    cat <<'PROVIDER'
PROVIDER_WORKSPACE_FLAG=0
PROVIDER_HOME_SCRUB=1

provider_build_argv() {
  PROVIDER_ARGV=("$PROMPT_CONTENT")
}

provider_extract_text() {
  local raw_file="$1"
  PROVIDER_EXTRACTED=""
  [ -s "$raw_file" ] || return 1
  PROVIDER_EXTRACTED="$(cat "$raw_file")"
  [ -n "$PROVIDER_EXTRACTED" ] || return 1
  return 0
}
PROVIDER
  } > "$file"
  chmod +x "$file"
}
write_provider "$PROVIDER_FILE" "$STUB_CLI_NAME"

# ---- fixed diff/prompt inputs ---------------------------------------------
DIFF_FILE="$TMP/diff.txt"
PROMPT_FILE="$TMP/prompt.txt"
printf 'diff --git a/src/foo.py b/src/foo.py\n+bug here\n' > "$DIFF_FILE"
printf 'Review this diff for bugs.\n' > "$PROMPT_FILE"

# ---- per-scenario stub CLI binaries ----------------------------------------
# B: mutates the sandbox tree (writes a file into cwd, which lens-run.sh sets
# to the throwaway sandbox clone before exec).
STUB_B_DIR="$TMP/stub-b"; mkdir -p "$STUB_B_DIR"
cat > "$STUB_B_DIR/$STUB_CLI_NAME" <<'STUB'
#!/usr/bin/env bash
echo "mutated" > ./lens-test-mutation-marker.txt
printf '{"issues":[]}\n'
STUB
chmod +x "$STUB_B_DIR/$STUB_CLI_NAME"

# C: garbage/unparseable output.
STUB_C_DIR="$TMP/stub-c"; mkdir -p "$STUB_C_DIR"
cat > "$STUB_C_DIR/$STUB_CLI_NAME" <<'STUB'
#!/usr/bin/env bash
printf 'this is not json at all {{{\n'
STUB
chmod +x "$STUB_C_DIR/$STUB_CLI_NAME"

# D: well-formed JSON, lower-case severity/category to also exercise
# normalization (severity upcasing; category already canonical).
STUB_D_DIR="$TMP/stub-d"; mkdir -p "$STUB_D_DIR"
cat > "$STUB_D_DIR/$STUB_CLI_NAME" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' '{"issues":[{"severity":"high","category":"new","file":"src/foo.py","line":42,"description":"unhandled error","suggestion":"add try/catch"}]}'
STUB
chmod +x "$STUB_D_DIR/$STUB_CLI_NAME"

# E: dumps its OWN observed environment to a FIXED path baked in at
# generation time (a literal path, not a runtime env-var lookup — env is
# scrubbed by lens-run.sh via `env -i` before this binary runs, so any env
# var the test tried to pass through would prove nothing).
STUB_E_DIR="$TMP/stub-e"; mkdir -p "$STUB_E_DIR"
ENV_DUMP_FILE="$TMP/env-dump-e.txt"
cat > "$STUB_E_DIR/$STUB_CLI_NAME" <<STUB
#!/usr/bin/env bash
env > "$ENV_DUMP_FILE" 2>/dev/null
printf '{"issues":[]}\n'
STUB
chmod +x "$STUB_E_DIR/$STUB_CLI_NAME"

# F: real git, except `remote remove origin` fails. CLI must never run.
STUB_F_DIR="$TMP/stub-f"; mkdir -p "$STUB_F_DIR"
CLI_RAN_F="$TMP/cli-ran-f.txt"
REAL_GIT="$(command -v git)"
cat > "$STUB_F_DIR/$STUB_CLI_NAME" <<STUB
#!/usr/bin/env bash
printf 'ran\n' > "$CLI_RAN_F"
printf '{"issues":[]}\n'
STUB
chmod +x "$STUB_F_DIR/$STUB_CLI_NAME"
cat > "$STUB_F_DIR/git" <<STUB
#!/usr/bin/env bash
case " \$* " in
  *" remote remove origin "*) exit 1 ;;
esac
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$STUB_F_DIR/git"

# G: mutates .git internals only (hook + new remote). Working tree stays
# clean so `git status --porcelain` is empty — the reproduced bypass.
STUB_G_DIR="$TMP/stub-g"; mkdir -p "$STUB_G_DIR"
PORCELAIN_G="$TMP/porcelain-g.txt"
cat > "$STUB_G_DIR/$STUB_CLI_NAME" <<STUB
#!/usr/bin/env bash
mkdir -p .git/hooks
printf '#!/bin/sh\\nexit 0\\n' > .git/hooks/pre-push
chmod +x .git/hooks/pre-push
git remote add attacker https://attacker.example/loot.git
git status --porcelain > "$PORCELAIN_G" 2>/dev/null
printf '%s\\n' '{"issues":[{"severity":"HIGH","category":"new","file":"src/foo.py","line":1,"description":"must be discarded","suggestion":null}]}'
STUB
chmod +x "$STUB_G_DIR/$STUB_CLI_NAME"

# H (and case K's instance A): hangs (leader + child) so the process-group
# timeout can be proven. The stub records its OWN pid and pgid as its FIRST
# action, before it backgrounds the child, so a slow exec under load shortens
# the time it has before the watchdog fires but never loses the record.
# write_hung_stub <dir> <cli-name> <pid-file-prefix>
write_hung_stub() {
  local dir="$1" cli="$2" pids="$3"
  mkdir -p "$dir"
  cat > "$dir/$cli" <<STUB
#!/usr/bin/env bash
printf '%s\\n' "\$\$" > "$pids.self"
ps -o pgid= -p "\$\$" 2>/dev/null | tr -d ' ' > "$pids.pgid"
sleep 120 &
printf '%s\\n' "\$!" > "$pids.child"
sleep 120
STUB
  chmod +x "$dir/$cli"
}
STUB_H_DIR="$TMP/stub-h"
PIDS_H="$TMP/pids-h"
write_hung_stub "$STUB_H_DIR" "$STUB_CLI_NAME" "$PIDS_H"

# assert_no_leftovers <label> <pid-file-prefix> — scoped leftover check over
# ONLY the processes this stub recorded: kill -0 on its leader and child pids
# and a process-group query on its recorded pgid. Never a machine-wide name
# match: another suite's live stub must not read as this run's leftover.
# The kill check is polled for up to 10s, so a slow-to-reap process under
# load is not a false leftover.
assert_no_leftovers() {
  local label="$1" pids="$2" self child pgid i=0 left
  self="$(cat "$pids.self" 2>/dev/null || true)"
  child="$(cat "$pids.child" 2>/dev/null || true)"
  pgid="$(cat "$pids.pgid" 2>/dev/null || true)"
  while [ "$i" -lt 50 ]; do
    left=0
    if [ -n "$self" ] && kill -0 "$self" 2>/dev/null; then left=1; fi
    if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then left=1; fi
    [ "$left" = "0" ] && break
    sleep 0.2; i=$((i+1))
  done
  if [ -n "$self" ]; then
    assert_eq "$label CLI leader is not still running" "0" "$( kill -0 "$self" 2>/dev/null && echo 1 || echo 0 )"
  else
    no "$label CLI never wrote its pid — timeout path may not have reached exec"
  fi
  if [ -n "$child" ]; then
    assert_eq "$label CLI child is not still running (process-group kill)" "0" "$( kill -0 "$child" 2>/dev/null && echo 1 || echo 0 )"
  else
    no "$label CLI never wrote a child pid — cannot prove process-group kill"
  fi
  # Guard before `pgrep -g`: without lens-run.sh's perl/python setpgrp launch
  # the stub would sit in THIS test's own group, and the query would list the
  # test itself.
  if [ -z "$pgid" ]; then
    no "$label CLI never wrote its pgid — cannot scope the process-group check"
  elif [ "$pgid" != "$self" ]; then
    no "$label CLI pgid [$pgid] != its pid [$self] — not launched as its own process group (setpgrp), group check refused"
  elif [ "$pgid" = "$TEST_PGID" ]; then
    no "$label CLI pgid [$pgid] is the test's own process group — group check refused"
  else
    assert_eq "$label no process left in the CLI's own process group (pgrep -g $pgid)" "" "$(pgrep -g "$pgid" 2>/dev/null | tr '\n' ' ')"
  fi
}

# ---- runner -----------------------------------------------------------------
# run_lens [as run_lens_named] <provider> <stub-bin-dir-or-empty> <out-file>
# invokes lens-run.sh from inside REPO_ROOT (so its own
# `git rev-parse --show-toplevel`/HEAD resolve to this checkout) with the
# fixed diff/prompt inputs. Additional env var prefixes on the CALL (e.g.
# `FOO=bar run_lens ...`) are honored the same way test-orca-mirror.sh's
# run_mirror honors them.
run_lens_named() {
  local provider="$1" stubdir="$2" outfile="$3"
  local use_path="$PATH"
  [ -n "$stubdir" ] && use_path="$stubdir:$PATH"
  ( cd "$REPO_ROOT" && PATH="$use_path" "$BASH_BIN" "$LENS" \
      --provider "$provider" --role review \
      --diff "$DIFF_FILE" --prompt "$PROMPT_FILE" --out "$outfile" )
}
run_lens() {
  run_lens_named "$PROVIDER_NAME" "$1" "$2"
}

echo "==== A: provider absent from PATH -> provider_unavailable, no subprocess attempted ===="
OUT_A="$TMP/out-a.json"
DEBUG_A="$TMP/debug-wt-a.txt"
RC_A=0
LOOMWRIGHT_LENS_DEBUG_WT_PATH_FILE="$DEBUG_A" run_lens "" "$OUT_A" || RC_A=$?
assert_eq "A rc=0" "0" "$RC_A"
assert_eq "A lens_status=provider_unavailable" "provider_unavailable" "$(jq -r '.lens_status' "$OUT_A" 2>/dev/null)"
assert_eq "A provider field echoes the requested name" "$PROVIDER_NAME" "$(jq -r '.provider' "$OUT_A" 2>/dev/null)"
assert_eq "A no subprocess attempted (sandbox-debug hatch never fired -> run never reached the exec stage)" "0" "$( [ -f "$DEBUG_A" ] && echo 1 || echo 0 )"

echo ""
echo "==== B: stub mutates the sandbox tree -> lens_mutated_tree, sandbox removed, parent origin intact ===="
ORIGIN_BEFORE="$(git -C "$REPO_ROOT" remote -v)"
OUT_B="$TMP/out-b.json"
DEBUG_B="$TMP/debug-wt-b.txt"
RC_B=0
LOOMWRIGHT_LENS_DEBUG_WT_PATH_FILE="$DEBUG_B" run_lens "$STUB_B_DIR" "$OUT_B" || RC_B=$?
assert_eq "B rc=0" "0" "$RC_B"
assert_eq "B lens_status=lens_mutated_tree" "lens_mutated_tree" "$(jq -r '.lens_status' "$OUT_B" 2>/dev/null)"
assert_eq "B issues discarded (empty array)" "[]" "$(jq -c '.issues' "$OUT_B" 2>/dev/null)"
if [ -s "$DEBUG_B" ]; then
  SANDBOX_B="$(cat "$DEBUG_B")"
  assert_eq "B sandbox clone removed after the run" "0" "$( [ -e "$SANDBOX_B" ] && echo 1 || echo 0 )"
else
  no "B sandbox-debug hatch did not record a path — cannot verify removal"
fi
ORIGIN_AFTER="$(git -C "$REPO_ROOT" remote -v)"
assert_eq "B PARENT repo's own origin remote unchanged after the run (proves clone-based isolation, not worktree-based)" "$ORIGIN_BEFORE" "$ORIGIN_AFTER"
assert_true "B PARENT repo's origin remote still present at all" "$( grep -q '^origin' < <(echo "$ORIGIN_AFTER") && echo 1 || echo 0 )"

echo ""
echo "==== C: stub produces unparseable garbage -> lens_unparseable ===="
OUT_C="$TMP/out-c.json"
RC_C=0
run_lens "$STUB_C_DIR" "$OUT_C" || RC_C=$?
assert_eq "C rc=0" "0" "$RC_C"
assert_eq "C lens_status=lens_unparseable" "lens_unparseable" "$(jq -r '.lens_status' "$OUT_C" 2>/dev/null)"
assert_eq "C issues empty" "[]" "$(jq -c '.issues' "$OUT_C" 2>/dev/null)"

echo ""
echo "==== D: stub produces well-formed JSON -> normalized issues[] matches RESULT_SCHEMAS.md shape ===="
OUT_D="$TMP/out-d.json"
RC_D=0
run_lens "$STUB_D_DIR" "$OUT_D" || RC_D=$?
assert_eq "D rc=0" "0" "$RC_D"
assert_eq "D lens_status=ok" "ok" "$(jq -r '.lens_status' "$OUT_D" 2>/dev/null)"
EXPECTED_D='[{"severity":"HIGH","category":"new","file":"src/foo.py","line":42,"description":"unhandled error","suggestion":"add try/catch"}]'
assert_eq "D issues[] normalized to the exact severity/category/file/line/description/suggestion fields (severity upcased)" "$EXPECTED_D" "$(jq -c '.issues' "$OUT_D" 2>/dev/null)"
assert_eq "D cost is honestly 'unknown', never '0'" "unknown" "$(jq -r '.cost' "$OUT_D" 2>/dev/null)"
assert_eq "D provider field" "$PROVIDER_NAME" "$(jq -r '.provider' "$OUT_D" 2>/dev/null)"
assert_eq "D model is null (no :model suffix given)" "null" "$(jq -c '.model' "$OUT_D" 2>/dev/null)"

echo ""
echo "==== E: scrubbed-env -> GH_TOKEN set in the test's OWN env does NOT reach the provider CLI ===="
OUT_E="$TMP/out-e.json"
RC_E=0
GH_TOKEN="totally-secret-leak-me-not-xyz" run_lens "$STUB_E_DIR" "$OUT_E" || RC_E=$?
assert_eq "E rc=0" "0" "$RC_E"
if [ -s "$ENV_DUMP_FILE" ]; then
  assert_eq "E GH_TOKEN absent from the env the provider CLI actually observed" "0" "$( grep -q '^GH_TOKEN=' "$ENV_DUMP_FILE" && echo 1 || echo 0 )"
  assert_true "E PATH still present (re-added on purpose so the CLI can be found)" "$( grep -q '^PATH=' "$ENV_DUMP_FILE" && echo 1 || echo 0 )"
  assert_true "E HOME redirected to a scrub dir, not the test's real HOME" "$( grep -q "^HOME=$HOME\$" "$ENV_DUMP_FILE" && echo 0 || echo 1 )"
else
  no "E stub CLI never ran / never wrote its env dump — cannot verify the scrub"
fi

echo ""
echo "==== F: git remote remove origin fails -> fail-closed, CLI never runs, parent origin intact ===="
ORIGIN_BEFORE_F="$(git -C "$REPO_ROOT" remote -v)"
OUT_F="$TMP/out-f.json"
DEBUG_F="$TMP/debug-wt-f.txt"
RC_F=0
LOOMWRIGHT_LENS_DEBUG_WT_PATH_FILE="$DEBUG_F" run_lens "$STUB_F_DIR" "$OUT_F" || RC_F=$?
assert_eq "F rc=0" "0" "$RC_F"
assert_eq "F lens_status=lens_unparseable (isolation setup failed closed)" "lens_unparseable" "$(jq -r '.lens_status' "$OUT_F" 2>/dev/null)"
assert_true "F notes name the origin-remove failure" "$( grep -q 'remote remove origin failed' < <(jq -r '.notes // empty' "$OUT_F" 2>/dev/null) && echo 1 || echo 0 )"
assert_eq "F provider CLI never ran" "0" "$( [ -f "$CLI_RAN_F" ] && echo 1 || echo 0 )"
if [ -s "$DEBUG_F" ]; then
  SANDBOX_F="$(cat "$DEBUG_F")"
  assert_eq "F sandbox removed after the failed isolate" "0" "$( [ -e "$SANDBOX_F" ] && echo 1 || echo 0 )"
else
  no "F sandbox-debug hatch did not record a path — isolate never reached checkout"
fi
ORIGIN_AFTER_F="$(git -C "$REPO_ROOT" remote -v)"
assert_eq "F PARENT repo origin unchanged" "$ORIGIN_BEFORE_F" "$ORIGIN_AFTER_F"

echo ""
echo "==== G: .git internals mutation (hook + remote) with empty porcelain -> lens_mutated_tree ===="
ORIGIN_BEFORE_G="$(git -C "$REPO_ROOT" remote -v)"
OUT_G="$TMP/out-g.json"
RC_G=0
run_lens "$STUB_G_DIR" "$OUT_G" || RC_G=$?
assert_eq "G rc=0" "0" "$RC_G"
assert_eq "G lens_status=lens_mutated_tree" "lens_mutated_tree" "$(jq -r '.lens_status' "$OUT_G" 2>/dev/null)"
assert_eq "G issues discarded (empty array)" "[]" "$(jq -c '.issues' "$OUT_G" 2>/dev/null)"
if [ -f "$PORCELAIN_G" ]; then
  assert_eq "G working-tree porcelain was empty (the bypass git status alone would have missed)" "" "$(cat "$PORCELAIN_G")"
else
  no "G stub never wrote a porcelain dump — cannot prove the porcelain-empty case"
fi
ORIGIN_AFTER_G="$(git -C "$REPO_ROOT" remote -v)"
assert_eq "G PARENT repo origin unchanged" "$ORIGIN_BEFORE_G" "$ORIGIN_AFTER_G"

echo ""
echo "==== H: hung CLI times out, process group killed, no leftover children ===="
# Why the timeout clock is not deferred until the stub's pid file exists: the
# clock is lens-run.sh's own watchdog, forked right after the CLI subshell, so
# it starts at CLI launch and the test cannot start it later. Load tolerance
# comes instead from (a) the stub writing its pid/pgid first, (b) a 5s timeout
# (was 1s) that leaves exec headroom under load, (c) the elapsed bound below,
# which still proves the timeout fired rather than the CLI exiting (the stub
# sleeps 120s), and (d) the 10s bounded kill poll in assert_no_leftovers.
# Honest limits: (1) a `sleep` shim on the PATH the test passes could defer the
# watchdog test-side, but it would alter the timing of the code under test, so
# it is deliberately not used; (2) an exec stall longer than the 5s timeout
# still fails "never wrote its pid" — the raise shrinks that flake window, it
# does not abolish it, and the 10s bound applies to the post-return kill poll,
# not to a pid-file wait.
OUT_H="$TMP/out-h.json"
RC_H=0
START_H="$(date +%s)"
LOOMWRIGHT_LENS_CLI_TIMEOUT=5 run_lens "$STUB_H_DIR" "$OUT_H" || RC_H=$?
END_H="$(date +%s)"
ELAPSED_H=$((END_H - START_H))
assert_eq "H rc=0" "0" "$RC_H"
assert_eq "H lens_status=lens_unparseable" "lens_unparseable" "$(jq -r '.lens_status' "$OUT_H" 2>/dev/null)"
assert_true "H notes name the timeout" "$( grep -q 'timed out' < <(jq -r '.notes // empty' "$OUT_H" 2>/dev/null) && echo 1 || echo 0 )"
assert_true "H finished well inside the hung-sleep (elapsed=${ELAPSED_H}s, bound: 5s timeout + 2s TERM->KILL grace, < 20s vs the stub's sleep 120)" "$( [ "$ELAPSED_H" -lt 20 ] && echo 1 || echo 0 )"
assert_no_leftovers "H" "$PIDS_H"

echo ""
echo "==== I: invalid --provider NAME (slash / ..) -> provider_unavailable, no source-escape ===="
OUT_I="$TMP/out-i.json"
RC_I=0
DEBUG_I="$TMP/debug-wt-i.txt"
LOOMWRIGHT_LENS_DEBUG_WT_PATH_FILE="$DEBUG_I" run_lens_named '../evil' "" "$OUT_I" || RC_I=$?
assert_eq "I rc=0" "0" "$RC_I"
assert_eq "I lens_status=provider_unavailable" "provider_unavailable" "$(jq -r '.lens_status' "$OUT_I" 2>/dev/null)"
assert_true "I notes name the invalid provider name" "$( grep -q 'invalid provider name' < <(jq -r '.notes // empty' "$OUT_I" 2>/dev/null) && echo 1 || echo 0 )"
assert_eq "I no sandbox created (rejected before isolate)" "0" "$( [ -f "$DEBUG_I" ] && echo 1 || echo 0 )"

echo ""
echo "==== J: missing provider-<name>.sh -> provider_unavailable ===="
OUT_J="$TMP/out-j.json"
RC_J=0
DEBUG_J="$TMP/debug-wt-j.txt"
LOOMWRIGHT_LENS_DEBUG_WT_PATH_FILE="$DEBUG_J" run_lens_named 'nosuchprovider' "" "$OUT_J" || RC_J=$?
assert_eq "J rc=0" "0" "$RC_J"
assert_eq "J lens_status=provider_unavailable" "provider_unavailable" "$(jq -r '.lens_status' "$OUT_J" 2>/dev/null)"
assert_true "J notes name the missing provider-table entry" "$( grep -q 'no provider-table entry' < <(jq -r '.notes // empty' "$OUT_J" 2>/dev/null) && echo 1 || echo 0 )"
assert_eq "J no sandbox created (rejected before isolate)" "0" "$( [ -f "$DEBUG_J" ] && echo 1 || echo 0 )"

echo ""
echo "==== K: overlapping lens-run.sh instances -> A's scoped leftover checks ignore live neighbour B ===="
# B is held alive by a RELEASE FILE the test writes after A's checks, not by a
# timeout: A's sandbox setup/teardown is unbounded under load, so B's lifetime
# must not depend on A's wall time. The effective limit on B is its stub's own
# ~60s release-poll loop (300 x 0.2s), after which it self-exits; B's 90s
# CLI timeout is never reached in practice.
KB_STUB_DIR="$KB_DIR/stub"; mkdir -p "$KB_STUB_DIR"
KB_PIDS="$KB_DIR/pids"
OUT_KB="$KB_DIR/out.json"
cat > "$KB_STUB_DIR/$KB_STUB_CLI_NAME" <<STUB
#!/usr/bin/env bash
printf '%s\\n' "\$\$" > "$KB_PIDS.self.tmp" && mv -f "$KB_PIDS.self.tmp" "$KB_PIDS.self"
i=0
while [ ! -e "$KB_RELEASE" ] && [ "\$i" -lt 300 ]; do sleep 0.2; i=\$((i+1)); done
printf '{"issues":[]}\\n'
exit 0
STUB
chmod +x "$KB_STUB_DIR/$KB_STUB_CLI_NAME"
write_provider "$KB_PROVIDER_FILE" "$KB_STUB_CLI_NAME"
# exec, so $! is B's lens-run.sh itself (cleanup TERMs exactly that process).
( cd "$REPO_ROOT" && LOOMWRIGHT_LENS_CLI_TIMEOUT=90 PATH="$KB_STUB_DIR:$PATH" exec "$BASH_BIN" "$LENS" \
    --provider "$KB_PROVIDER_NAME" --role review \
    --diff "$DIFF_FILE" --prompt "$PROMPT_FILE" --out "$OUT_KB" ) >"$KB_DIR/lens.log" 2>&1 &
KB_LENS_PID=$!
# B's sandbox setup runs before its stub starts and is unbounded under load:
# wait up to ~60s for B's pid file (or for B's lens-run.sh to exit early).
i=0
while [ ! -s "$KB_PIDS.self" ] && [ "$i" -lt 300 ] && kill -0 "$KB_LENS_PID" 2>/dev/null; do sleep 0.2; i=$((i+1)); done
KB_SELF="$(cat "$KB_PIDS.self" 2>/dev/null || true)"
if [ -z "$KB_SELF" ]; then
  no "K B never started its stub within the bound (~60s) — overlap cannot be established"
else
  STUB_KA_DIR="$TMP/stub-ka"
  PIDS_KA="$TMP/pids-ka"
  write_hung_stub "$STUB_KA_DIR" "$STUB_CLI_NAME" "$PIDS_KA"
  OUT_KA="$TMP/out-ka.json"
  RC_KA=0
  LOOMWRIGHT_LENS_CLI_TIMEOUT=5 run_lens "$STUB_KA_DIR" "$OUT_KA" || RC_KA=$?
  assert_eq "K A rc=0" "0" "$RC_KA"
  assert_eq "K A lens_status=lens_unparseable" "lens_unparseable" "$(jq -r '.lens_status' "$OUT_KA" 2>/dev/null)"
  assert_true "K A notes name the timeout" "$( grep -q 'timed out' < <(jq -r '.notes // empty' "$OUT_KA" 2>/dev/null) && echo 1 || echo 0 )"
  assert_no_leftovers "K A" "$PIDS_KA"
  if kill -0 "$KB_SELF" 2>/dev/null; then
    ok "K overlap held: B's stub (pid $KB_SELF) was alive during A's leftover checks"
  else
    no "K overlap not established — B exited before A's check"
  fi
fi
: > "$KB_RELEASE"
i=0
while kill -0 "$KB_LENS_PID" 2>/dev/null && [ "$i" -lt 300 ]; do sleep 0.2; i=$((i+1)); done
if kill -0 "$KB_LENS_PID" 2>/dev/null; then
  no "K B lens-run.sh still running ~60s after its release file was written"
  kill "$KB_LENS_PID" 2>/dev/null
fi
RC_KB=0
wait "$KB_LENS_PID" || RC_KB=$?
KB_LENS_PID=""
assert_eq "K B rc=0" "0" "$RC_KB"
assert_eq "K B lens_status=ok (ran and was released, not killed)" "ok" "$(jq -r '.lens_status' "$OUT_KB" 2>/dev/null)"
assert_eq "K B notes do not say timed out" "0" "$( grep -q 'timed out' < <(jq -r '.notes // empty' "$OUT_KB" 2>/dev/null) && echo 1 || echo 0 )"
if [ -n "$KB_SELF" ]; then
  i=0
  while kill -0 "$KB_SELF" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.2; i=$((i+1)); done
  assert_eq "K B stub leader is gone after release" "0" "$( kill -0 "$KB_SELF" 2>/dev/null && echo 1 || echo 0 )"
fi

echo ""
echo "==== L: assert_no_leftovers self-check -> each refusal arm fires on forged pid files ===="
# Cases H and K only ever feed the helper a well-formed record, so its refusal
# arms are never exercised by them. Here it is fed FORGED pid files in this
# run's own $TMP and must FAIL. Each expected-failure call runs in a subshell
# (run_leftovers_probe), so its `no` lines bump only the subshell's counters,
# never this suite's: the probe prints the helper's output plus the subshell's
# fail delta, and the assertions below run in this shell with the normal helpers.
# A reaped child's pid stands in for "a process that is gone".
( : ) & L_DEAD=$!; wait "$L_DEAD" 2>/dev/null
L_DIR="$TMP/l-selfcheck"; mkdir -p "$L_DIR"
# run_leftovers_probe <pid-file-prefix> [forged TEST_PGID] -> stdout: the
# helper's output, then a final line "DELTA <subshell fail increment>".
run_leftovers_probe() {
  ( [ -n "${2:-}" ] && TEST_PGID="$2"
    f0=$fail
    assert_no_leftovers "L" "$1"
    echo "DELTA $((fail - f0))" ) 2>&1
}
# l_expect_refusal <label> <probe-output> <expected FAIL text>
l_expect_refusal() {
  local label="$1" out="$2" want="$3"
  assert_true "$label: helper reported a failure" "$( printf '%s\n' "$out" | grep -qE '^DELTA [1-9]' && echo 1 || echo 0 )"
  assert_true "$label: refusal text [$want] fired" "$( printf '%s\n' "$out" | grep -F "FAIL: L " | grep -qF "$want" && echo 1 || echo 0 )"
}
# (a) missing leader pid file.
printf '%s\n' "$L_DEAD" > "$L_DIR/a.child"; printf '%s\n' "$L_DEAD" > "$L_DIR/a.pgid"
l_expect_refusal "L(a) missing leader pid file" "$(run_leftovers_probe "$L_DIR/a")" "CLI never wrote its pid"
# (b) recorded pgid != recorded leader pid (not launched via setpgrp).
printf '%s\n' "$L_DEAD" > "$L_DIR/b.self"; printf '%s\n' "$L_DEAD" > "$L_DIR/b.child"
printf '%s\n' "$((L_DEAD + 1))" > "$L_DIR/b.pgid"
l_expect_refusal "L(b) pgid != leader pid" "$(run_leftovers_probe "$L_DIR/b")" "not launched as its own process group"
# (c) pgid == leader pid == the test's own pgid. With the REAL test pgid this is
# reachable only by recording a live leader (the test's own group leader), which
# would spend the 10s kill poll and trip the "still running" arm as well; so the
# probe forges TEST_PGID to the dead pid instead. The arm is a pure comparison;
# this pins that it fires and that `pgrep -g` is never run on that group. It is
# still a defensive backstop: arm (b) already refuses any stub that was not
# setpgrp'd, since a process that is not a group leader never has pgid == pid.
printf '%s\n' "$L_DEAD" > "$L_DIR/c.self"; printf '%s\n' "$L_DEAD" > "$L_DIR/c.child"; printf '%s\n' "$L_DEAD" > "$L_DIR/c.pgid"
L_OUT_C="$(run_leftovers_probe "$L_DIR/c" "$L_DEAD")"
l_expect_refusal "L(c) pgid is the test's own group" "$L_OUT_C" "is the test's own process group"
assert_true "L(c) no pgrep -g query was run on the refused group" "$( printf '%s\n' "$L_OUT_C" | grep -q 'pgrep -g' && echo 0 || echo 1 )"
# Negative control: the same well-formed record of a gone, setpgrp'd process,
# checked against the REAL test pgid, passes — so the arms above fail for their
# own reason, not for any input.
L_OUT_N="$(run_leftovers_probe "$L_DIR/c")"
assert_true "L negative control: gone own-group record passes (DELTA 0)" "$( printf '%s\n' "$L_OUT_N" | grep -qx 'DELTA 0' && echo 1 || echo 0 )"
# Positive control: a LIVE setpgrp'd process recorded as leader+child+pgid must
# be flagged as a leftover (leader still running, and its group non-empty). It
# is killed right after the probe; cleanup() also kills it on an interrupt.
if command -v perl >/dev/null 2>&1; then
  perl -e 'setpgrp(0,0); exec @ARGV' sleep 30 &
else
  python3 -c 'import os,sys; os.setpgrp(); os.execvp(sys.argv[1], sys.argv[1:])' sleep 30 &
fi
L_LIVE_PID=$!
i=0
while [ "$(ps -o pgid= -p "$L_LIVE_PID" 2>/dev/null | tr -d ' ')" != "$L_LIVE_PID" ] && [ "$i" -lt 50 ]; do sleep 0.2; i=$((i+1)); done
printf '%s\n' "$L_LIVE_PID" > "$L_DIR/p.self"; printf '%s\n' "$L_LIVE_PID" > "$L_DIR/p.child"
ps -o pgid= -p "$L_LIVE_PID" 2>/dev/null | tr -d ' ' > "$L_DIR/p.pgid"
L_OUT_P="$(run_leftovers_probe "$L_DIR/p")"
kill "$L_LIVE_PID" 2>/dev/null; wait "$L_LIVE_PID" 2>/dev/null; L_LIVE_PID=""
l_expect_refusal "L positive control: live setpgrp'd leftover" "$L_OUT_P" "CLI leader is not still running"
assert_true "L positive control: its own process group reads non-empty" "$( printf '%s\n' "$L_OUT_P" | grep -qF "FAIL: L no process left in the CLI's own process group" && echo 1 || echo 0 )"

echo ""
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && exit 0 || exit 1
