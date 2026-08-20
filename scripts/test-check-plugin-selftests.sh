#!/usr/bin/env bash
# test-check-plugin-selftests.sh — offline self-test for check-plugin-selftests.sh.
#
# WHY IT MATTERS (AC6): after this slice exactly ONE plugin in this repo ships a
# scripts/ dir, so the harness's per-plugin loud-on-empty branch has NO live
# subject. "Proven" therefore cannot mean "observed in this repo" — it means
# proven against the temp fixture trees below. The two load-bearing cases are:
#   (a) a plugin with scripts/test-*.sh present            -> exit 0
#   (b) a plugin with a scripts/ dir but NO test-*.sh       -> exit 1, naming it
#
# MUTATION CONTROL: delete the `[ "${#tests[@]}" -eq 0 ]` loud-on-empty branch
# and case (b) plus the "names the plugin" assertion flip. Recorded in the PR.
#
# Portability: bash 3.2 safe (macOS) + Ubuntu CI. Offline, deterministic.

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
GATE="$script_dir/check-plugin-selftests.sh"
[ -f "$GATE" ] || { echo "test-check-plugin-selftests: gate not found: $GATE" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/plugin-selftests.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0

# mkroot <path> — create and echo the CANONICAL path. The gate resolves plugin
# dirs with `cd ... && pwd`; a $TMPDIR with a trailing slash (macOS default)
# would otherwise break a literal substring assertion while the gate is correct.
mkroot() { mkdir -p "$1" && ( cd "$1" && pwd ); }

# mk_plugin <root> <name> <mode> — modes:
#   suites      scripts/ dir WITH test-*.sh          (the healthy case)
#   empty       scripts/ dir with NO test-*.sh       (the anti-drift case)
#   failing     scripts/ dir with a test that exits 1
#   no-scripts  no scripts/ dir at all               (the skip-silently case)
mk_plugin() {
  local root="$1" name="$2" mode="$3" p="$1/$2"
  mkdir -p "$p"
  case "$mode" in
    no-scripts) : ;;
    empty)      mkdir -p "$p/scripts"; printf '#!/usr/bin/env bash\nexit 0\n' > "$p/scripts/helper.sh" ;;
    suites)     mkdir -p "$p/scripts"
                printf '#!/usr/bin/env bash\necho "%s suite one ok"\nexit 0\n' "$name" > "$p/scripts/test-one.sh"
                printf '#!/usr/bin/env bash\necho "%s suite two ok"\nexit 0\n' "$name" > "$p/scripts/test-two.sh" ;;
    failing)    mkdir -p "$p/scripts"
                printf '#!/usr/bin/env bash\necho "%s deliberately fails"\nexit 1\n' "$name" > "$p/scripts/test-bad.sh" ;;
  esac
}

mk_manifest() {
  local root="$1"; shift
  mkdir -p "$root/.claude-plugin"
  {
    printf '{ "name": "fixture", "plugins": ['
    local first=1 n
    for n in "$@"; do
      [ "$first" -eq 1 ] || printf ','
      first=0
      printf '{ "name": "%s", "source": "./%s", "version": "1.0.0" }' "$n" "$n"
    done
    printf '] }\n'
  } > "$root/.claude-plugin/marketplace.json"
}

run_case() { # NAME EXPECT(zero|nonzero) ROOT [GREP_MUST_MATCH]
  local name="$1" expect="$2" root="$3" must="${4:-}" out status ok=1
  out="$(bash "$GATE" --root "$root" 2>&1)"; status=$?
  [ "$expect" = "zero" ]    && [ "$status" -ne 0 ] && ok=0
  [ "$expect" = "nonzero" ] && [ "$status" -eq 0 ] && ok=0
  if [ "$ok" -eq 1 ] && [ -n "$must" ]; then
    printf '%s\n' "$out" | grep -qF "$must" || ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    echo "PASS: $name (exit $status)"; pass=$((pass+1))
  else
    echo "FAIL: $name (exit=$status, expected $expect${must:+, expected output to contain: $must})"
    printf '%s\n' "$out" | sed 's/^/    | /'
    fail=$((fail+1))
  fi
}

# --- AC6 (a): a plugin whose scripts/test-*.sh are present -> exit 0 ---------
R1="$(mkroot "$tmp/a")"
mk_plugin "$R1" alphaplug suites
mk_manifest "$R1" alphaplug
run_case "AC6(a): plugin with scripts/test-*.sh runs them and exits 0" zero "$R1" "alphaplug suite one ok"

# --- AC6 (b): scripts/ dir but NO test-*.sh -> exit 1, message names the plugin
R2="$(mkroot "$tmp/b")"
mk_plugin "$R2" alphaplug suites
mk_plugin "$R2" betaplug  empty
mk_manifest "$R2" alphaplug betaplug
run_case "AC6(b): plugin with scripts/ but no test-*.sh exits 1" nonzero "$R2" "plugin 'betaplug' has a scripts/ dir but no test-*.sh"

# --- SKIP SILENTLY: a plugin with no scripts/ dir at all --------------------
R3="$(mkroot "$tmp/c")"
mk_plugin "$R3" alphaplug suites
mk_plugin "$R3" betaplug  no-scripts
mk_manifest "$R3" alphaplug betaplug
run_case "plugin with no scripts/ dir is skipped silently" zero "$R3" "alphaplug suite two ok"

# ...and it really is skipped, not silently counted:
out3="$(bash "$GATE" --root "$R3" 2>&1)"
case "$out3" in
  *"plugin: betaplug"*) echo "FAIL: skip-silently must not announce the scripts-less plugin"; fail=$((fail+1)) ;;
  *) echo "PASS: skip-silently does not announce the scripts-less plugin"; pass=$((pass+1)) ;;
esac

# --- EVERY plugin's suites run, not just the first --------------------------
R4="$(mkroot "$tmp/d")"
mk_plugin "$R4" alphaplug suites
mk_plugin "$R4" betaplug  suites
mk_manifest "$R4" alphaplug betaplug
run_case "a SECOND plugin's suites are also executed" zero "$R4" "betaplug suite one ok"

# --- a failing suite in the SECOND plugin fails the gate --------------------
R5="$(mkroot "$tmp/e")"
mk_plugin "$R5" alphaplug suites
mk_plugin "$R5" betaplug  failing
mk_manifest "$R5" alphaplug betaplug
run_case "a failing suite in the second plugin fails the gate" nonzero "$R5" "exited non-zero"

# --- ANTI-DRIFT TRIPWIRE: no suite-bearing plugin at all --------------------
R6="$(mkroot "$tmp/f")"
mk_plugin "$R6" alphaplug no-scripts
mk_manifest "$R6" alphaplug
run_case "zero suite-bearing plugins trips the anti-drift tripwire" nonzero "$R6" "gate matched nothing"

# --- missing manifest fails CLOSED ------------------------------------------
run_case "missing marketplace manifest fails closed" nonzero "$tmp/g-does-not-exist" "marketplace manifest not found"

echo "----------------------------------------"
echo "test-check-plugin-selftests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || { echo "test-check-plugin-selftests: FAILED" >&2; exit 1; }
echo "test-check-plugin-selftests: OK"
exit 0
