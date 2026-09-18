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
#      still present afterward (proves the git-clone-based isolation fix)
#   C. stub produces unparseable garbage -> lens_unparseable
#   D. stub produces well-formed JSON -> normalized issues[] matches
#      RESULT_SCHEMAS.md's exact fields (severity/category/file/line/
#      description/suggestion), including severity upcasing
#   E. scrubbed-env: GH_TOKEN is set in the test's OWN env, and must be
#      absent from the env the stub CLI actually observes
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

# ---- runner -----------------------------------------------------------------
# run_lens <stub-bin-dir-or-empty> <out-file> -- invokes lens-run.sh from
# inside REPO_ROOT (so its own `git rev-parse --show-toplevel`/HEAD resolve
# to this checkout) with the fixed diff/prompt inputs and the teststub
# provider. Additional env var prefixes on the CALL (e.g.
# `FOO=bar run_lens ...`) are honored the same way test-orca-mirror.sh's
# run_mirror honors them.
run_lens() {
  local stubdir="$1" outfile="$2"
  local use_path="$PATH"
  [ -n "$stubdir" ] && use_path="$stubdir:$PATH"
  ( cd "$REPO_ROOT" && PATH="$use_path" "$BASH_BIN" "$LENS" \
      --provider teststub --role review \
      --diff "$DIFF_FILE" --prompt "$PROMPT_FILE" --out "$outfile" )
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
assert_true "B PARENT repo's origin remote still present at all" "$( echo "$ORIGIN_AFTER" | grep -q '^origin' && echo 1 || echo 0 )"

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
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && exit 0 || exit 1
