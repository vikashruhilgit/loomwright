#!/usr/bin/env bash
# test-lens-run.sh — stub-backed self-tests for lens-run.sh. Mirrors this
# repo's stub-on-PATH testing convention (test-orca-mirror.sh) and its
# TMP-dir-plus-trap cleanup convention.
#
# The test writes its OWN provider-table entry, provider-teststub.sh, into
# THIS directory (lens-run.sh resolves $SCRIPT_DIR/provider-$NAME.sh from its
# own BASH_SOURCE, so a stub provider must live here to be found at all) and
# removes it in its own EXIT trap — no test-only file is left behind on a
# clean exit. Each scenario gets its OWN stub CLI binary (different PATH
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
#   H. hung CLI + LOOMWRIGHT_LENS_CLI_TIMEOUT=1 -> lens_unparseable,
#      process group killed, no leftover children
#   I. invalid --provider NAME (slash / `..`) -> provider_unavailable,
#      no source of a path outside $SCRIPT_DIR
#   J. missing provider-<name>.sh -> provider_unavailable
#
# Exit 0 = all pass, 1 = any failure.

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
PROVIDER_FILE="$HERE/provider-teststub.sh"
cleanup() { rm -rf "$TMP"; rm -f "$PROVIDER_FILE"; }
trap cleanup EXIT

# ---- test-only provider-table entry --------------------------------------
STUB_CLI_NAME="loomwright-test-stub-cli"
cat > "$PROVIDER_FILE" <<'PROVIDER'
#!/usr/bin/env bash
# provider-teststub.sh — TEST-ONLY provider-table entry, written by
# test-lens-run.sh at test start and removed in its own EXIT trap. Not a real
# provider; exists only to satisfy lens-run.sh's $SCRIPT_DIR/provider-<name>.sh
# lookup convention. See lens-run.sh's own header for the per-provider-file
# contract these globals/functions implement.
PROVIDER_CLI_NAME="loomwright-test-stub-cli"
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
chmod +x "$PROVIDER_FILE"

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

# H: hangs (leader + child) so the process-group timeout can be proven.
STUB_H_DIR="$TMP/stub-h"; mkdir -p "$STUB_H_DIR"
PIDS_H="$TMP/pids-h"
cat > "$STUB_H_DIR/$STUB_CLI_NAME" <<STUB
#!/usr/bin/env bash
sleep 120 &
printf '%s\\n' "\$!" > "$PIDS_H.child"
printf '%s\\n' "\$\$" > "$PIDS_H.self"
sleep 120
STUB
chmod +x "$STUB_H_DIR/$STUB_CLI_NAME"

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
  run_lens_named teststub "$1" "$2"
}

echo "==== A: provider absent from PATH -> provider_unavailable, no subprocess attempted ===="
OUT_A="$TMP/out-a.json"
DEBUG_A="$TMP/debug-wt-a.txt"
RC_A=0
LOOMWRIGHT_LENS_DEBUG_WT_PATH_FILE="$DEBUG_A" run_lens "" "$OUT_A" || RC_A=$?
assert_eq "A rc=0" "0" "$RC_A"
assert_eq "A lens_status=provider_unavailable" "provider_unavailable" "$(jq -r '.lens_status' "$OUT_A" 2>/dev/null)"
assert_eq "A provider field echoes the requested name" "teststub" "$(jq -r '.provider' "$OUT_A" 2>/dev/null)"
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
assert_eq "D provider field" "teststub" "$(jq -r '.provider' "$OUT_D" 2>/dev/null)"
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
OUT_H="$TMP/out-h.json"
RC_H=0
START_H="$(date +%s)"
LOOMWRIGHT_LENS_CLI_TIMEOUT=1 run_lens "$STUB_H_DIR" "$OUT_H" || RC_H=$?
END_H="$(date +%s)"
ELAPSED_H=$((END_H - START_H))
assert_eq "H rc=0" "0" "$RC_H"
assert_eq "H lens_status=lens_unparseable" "lens_unparseable" "$(jq -r '.lens_status' "$OUT_H" 2>/dev/null)"
assert_true "H notes name the timeout" "$( grep -q 'timed out' < <(jq -r '.notes // empty' "$OUT_H" 2>/dev/null) && echo 1 || echo 0 )"
assert_true "H finished well inside the hung-sleep (elapsed=${ELAPSED_H}s, bound ~1s+kill)" "$( [ "$ELAPSED_H" -lt 20 ] && echo 1 || echo 0 )"
H_SELF="$(cat "$PIDS_H.self" 2>/dev/null || true)"
H_CHILD="$(cat "$PIDS_H.child" 2>/dev/null || true)"
if [ -n "$H_SELF" ]; then
  assert_eq "H CLI leader is not still running" "0" "$( kill -0 "$H_SELF" 2>/dev/null && echo 1 || echo 0 )"
else
  no "H CLI never wrote its pid — timeout path may not have reached exec"
fi
if [ -n "$H_CHILD" ]; then
  assert_eq "H CLI child is not still running (process-group kill)" "0" "$( kill -0 "$H_CHILD" 2>/dev/null && echo 1 || echo 0 )"
else
  no "H CLI never wrote a child pid — cannot prove process-group kill"
fi
assert_eq "H no leftover stub CLI processes" "0" "$( pgrep -f "$STUB_CLI_NAME" >/dev/null 2>&1 && echo 1 || echo 0 )"

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
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && exit 0 || exit 1
