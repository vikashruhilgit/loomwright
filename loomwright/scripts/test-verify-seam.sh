#!/usr/bin/env bash
# test-verify-seam.sh — self-tests for the `.agent/verify.json` verification-environment contract
# seam: the fail-safe reader (read-verify.sh), the propose-only confirm-gated bootstrap
# (propose-verify.sh) and — appended by the executor subtask below the marked anchor — the executor
# (verify-env.sh). Schema authority: docs/RESULT_SCHEMAS.md §VERIFY_ENV.
#
# WRITE CONTAINMENT IS THE POINT OF THIS FILE'S SHAPE. Every fixture lives under a `mktemp -d`
# scratch dir; every `--confirm` case runs inside a `mktemp -d` + `git init` throwaway tree (the
# writer's non-primary-checkout guard needs a `.git` DIRECTORY for the write to actually happen —
# without `git init` the assertion "it wrote exactly one file" would be vacuous, because nothing
# would be written at all). The suite NEVER runs the writer against this repo, and case (Z) closes
# the loop by hashing the developer's REAL `.agent/` before and after the whole run. Precedent:
# test-propose-product.sh / test-read-product.sh.
#
# Static-only: no network, no `gh`, no Docker. Exit 0 = all pass, 1 = any failure (auto-registered
# by ci.yml's `loomwright/scripts/test-*.sh` glob).
#
# Reader cases:
#   (a) AC1  absent store            → EMPTY stdout, exit 0, stderr NAMES THE PATH
#   (b) AC2  well-formed fixture     → exit 0, stdout is ONE JSON object EQUAL to the fixture (jq -S),
#                                      and the three null-valued keys come back PRESENT and null
#   (c) AC2  malformed roots         → unparseable JSON / non-object root: EMPTY stdout, reason on stderr
#   (d) AC2  each of the 8 required keys deleted in turn → EMPTY stdout, stderr names the key
#   (e) AC2  NULLABLE-REQUIRED, both directions → `seed: null` VALID; `seed` ABSENT malformed (and
#                                      the same pair for start / reset / stop)
#   (f) AC2  non_prod_assert with NO usable member → EMPTY stdout, reason token non_prod_assert_empty;
#                                      a present-but-mistyped member alongside a usable one is ALSO
#                                      malformed (a half-typed member must not silently vanish);
#                                      env_var_equals.name must be a POSIX identifier — a non-
#                                      identifier name is an UNUSABLE member [env_var_name_invalid:<n>]:
#                                      alone ⇒ non_prod_assert_empty, beside a usable member ⇒ the
#                                      store is still emitted (advisory on stderr)
#   (g)      auth / ready_timeout_s shape → out-of-enum method, storage_state without a path, and a
#                                      non-numeric timeout are each malformed
#   (h)      jq unavailable          → EMPTY stdout, reason on stderr, exit 0 (PATH-stubbed; the
#                                      simulation is verified effective before it is trusted)
#   (i)      pure-read + determinism → fixture bytes unchanged, no `.agent/` created, two runs identical
#   (j)      override mechanism      → VERIFY_STORE env resolves the fixture; `--store` WINS over it
#   (k)      THE READER NEVER EXECUTES A CONTRACT STRING → every shell-string member of a fixture is
#                                      `touch <marker>`; after a read, NO marker exists
# Bootstrap cases:
#   (p1) AC7 no --non-prod           → prints the proposal with a BLOCKED line, exit 1, writes
#                                      NOTHING — with AND without --confirm
#   (p2) AC7 --non-prod, no --confirm → prints the proposal, exit 0, tree byte-identical, no .agent/
#   (p3) AC7 --non-prod --confirm    → EXACTLY ONE added path (./.agent/verify.json), every
#                                      pre-existing file byte-identical, and the store READS BACK
#                                      through read-verify.sh with the supplied non_prod_assert
#   (p4)     the scan feeds the proposal (package.json start/seed, .env PORT) but non_prod_assert is
#                                      NEVER inferred from it — a repo shouting NODE_ENV=development
#                                      is still BLOCKED
#   (p5)     base_url is never defaulted → bare repo, no --base-url: dry run BLOCKED, confirm exit 2
#   (p6)     non-primary-checkout guard → a top-level `.git` FILE refuses with exit 3, with a
#                                      positive control proving the same dir passes once `git init`ed
#   (p7)     NO-CLOBBER              → a second --confirm run refuses, bytes intact
#   (p8)     --non-prod value shapes → env=NAME=VAL → env_var_equals; cmd=… → cmd; malformed env=
#                                      form rejected (exit 1); a NAME that is not a POSIX identifier
#                                      (env=NODE-ENV=x, env=1ABC=x) is refused at parse time (exit 1,
#                                      message names the rule, nothing written)
#   (p9)     --non-prod one per kind → a second regex / env= / cmd= value is refused (exit 1) with
#                                      nothing written, even with --confirm; one of each still accepted
# Invariants:
#   (S)  AC5 SOLE WRITER            → across loomwright/scripts/*.sh EXCLUDING test-*.sh, exactly ONE
#                                      line moves a file onto the literal `verify.json`, and it is in
#                                      propose-verify.sh (capture-then-test, never `| grep -q`)
#   (M)  AC8 MUTATION CONTROL       → delete the `has("seed")` presence check from a COPY of the
#                                      reader (gated: non-empty, differs from original, `bash -n`);
#                                      the missing-`seed` fixture must then be ACCEPTED by the mutant,
#                                      proving case (e) is not passing vacuously
#   (T)      tree_hash discriminates → a planted stray file and an in-place edit both change the hash
#   (Z)      the developer's REAL .agent/ is byte-identical before/after, and this repo never gains
#                                      a .agent/verify.json

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$HERE/read-verify.sh"
WRITER="$HERE/propose-verify.sh"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

for f in "$READER" "$WRITER"; do
  if [ ! -f "$f" ]; then
    echo "  FAIL: script not found at $f"
    echo "RESULT: 0 passed, 1 failed"
    exit 1
  fi
done

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

FAKE_REPO="$(mktmp)"   # the reader's --repo (keeps its memory.log append out of the real repo)

# ---------------------------------------------------------------------------
# Harness helpers.
# ---------------------------------------------------------------------------
write_fixture() { printf '%s' "$2" > "$1"; }

# run_reader <store> [reader-override] — stdout on stdout; stderr into the FIXED file $LAST_ERR
# (assigned outside the function: `$( ... )` runs it in a subshell, so an inner assignment would be
# invisible to the assertions that follow).
LAST_ERR="$ROOT/last-stderr.txt"
run_reader() {
  local store="$1" reader="${2:-$READER}"
  : > "$LAST_ERR"
  bash "$reader" --store "$store" --repo "$FAKE_REPO" 2>"$LAST_ERR"
}

tree_list() {
  ( cd "$1" 2>/dev/null && find . -path ./.git -prune -o -type f -print 2>/dev/null | LC_ALL=C sort )
}
tree_hash() {
  local d="$1" p
  ( cd "$d" 2>/dev/null || exit 0
    tree_list "." | while IFS= read -r p; do
      printf '%s\t' "$p"
      cksum < "$p" 2>/dev/null
    done
  ) | cksum
}

# new_repo — a throwaway PRIMARY checkout (`git init` ⇒ `.git` DIRECTORY) with a scannable
# package.json + .env, so the scan cascade has something to find.
new_repo() {
  local r; r="$(mktemp -d "$ROOT/repo.XXXXXX")"
  (
    cd "$r" || exit 1
    git init -q
    git config user.email t@t
    git config user.name t
    printf '{"name":"acme","scripts":{"dev":"next dev","db:seed":"prisma db seed"}}\n' > package.json
    printf 'PORT=3000\nNODE_ENV=development\n' > .env
    printf 'placeholder\n' > src.txt
    git add -A
    git commit -qm init
  ) >/dev/null 2>&1
  printf '%s' "$r"
}
# new_repo_bare — a PRIMARY checkout with NOTHING scannable (no package.json, no .env).
new_repo_bare() {
  local r; r="$(mktemp -d "$ROOT/repo.XXXXXX")"
  (
    cd "$r" || exit 1
    git init -q
    git config user.email t@t
    git config user.name t
    printf 'placeholder\n' > src.txt
    git add -A
    git commit -qm init
  ) >/dev/null 2>&1
  printf '%s' "$r"
}

# run_writer <repo> [args...] → OUT (stdout+stderr), RC. stdin is /dev/null so the interactive-TTY
# branch can never be taken. The writer is invoked from a NEUTRAL cwd with `--repo`, which is the
# mechanism that lets the suite target a throwaway tree rather than this checkout.
run_writer() {
  local repo="$1"; shift
  OUT="$( ( cd "$ROOT" && bash "$WRITER" --repo "$repo" "$@" ) </dev/null 2>&1 )"; RC=$?
}
proposed_object() {
  printf '%s\n' "$OUT" | sed -n 's/^  object: //p'
}

HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0

# ---------------------------------------------------------------------------
# (Z) PRE-flight half — snapshot the developer's REAL .agent/ before anything runs.
# ---------------------------------------------------------------------------
REAL_AGENT="$REPO_ROOT/.agent"
REAL_AGENT_BEFORE="$(tree_hash "$REAL_AGENT")"
REAL_STORE_ABSENT_BEFORE=0
[ ! -e "$REAL_AGENT/verify.json" ] && REAL_STORE_ABSENT_BEFORE=1

finish_real_agent_check() {
  echo "== (Z) the developer's REAL .agent/ is untouched by this entire suite =="
  local after; after="$(tree_hash "$REAL_AGENT")"
  [ "$REAL_AGENT_BEFORE" = "$after" ] \
    && ok "(Z) the real repo's .agent/ is byte-identical before and after the suite" \
    || no "(Z) THIS SUITE MODIFIED the real repo's .agent/ — write containment is broken"
  [ "$REAL_STORE_ABSENT_BEFORE" -eq 1 ] \
    && ok "(Z) precondition: the real repo carried no .agent/verify.json before the run" \
    || no "(Z) precondition FAILED: this repo already carries .agent/verify.json (the store is created per project, never here)"
  [ ! -e "$REAL_AGENT/verify.json" ] \
    && ok "(Z) the real repo still carries no .agent/verify.json" \
    || no "(Z) the suite CREATED .agent/verify.json in this repo"
}

# ---------------------------------------------------------------------------
# DEGRADED RUN when jq is absent: the reader must no-op (empty stdout, exit 0) and the writer must
# REFUSE; nothing else is reachable.
# ---------------------------------------------------------------------------
if [ "$HAVE_JQ" -eq 0 ]; then
  echo "== DEGRADED RUN: jq is absent on this host =="
  d="$(mktmp)"; write_fixture "$d/verify.json" '{}'
  out="$(run_reader "$d/verify.json")"; rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ] && ok "[no jq] the reader emits nothing and exits 0" \
                                    || no "[no jq] reader rc=$rc out=$out"
  r="$(new_repo)"; before="$(tree_hash "$r")"
  run_writer "$r" --non-prod '^http://localhost' --confirm
  after="$(tree_hash "$r")"
  [ "$RC" -ne 0 ] && ok "[no jq] the writer REFUSES (rc=$RC)" || no "[no jq] the writer did not refuse"
  [ "$before" = "$after" ] && ok "[no jq] nothing was written" || no "[no jq] the refused run modified the tree"
  finish_real_agent_check
  echo
  echo "RESULT: $pass passed, $fail failed (DEGRADED — jq absent)"
  [ "$fail" -eq 0 ] || exit 1
  exit 0
fi

# The canonical well-formed fixture: three null-valued nullable-required keys (start/seed/reset),
# a non-null stop, method none, one usable non_prod_assert member, and both optional keys.
FULL_JSON='{
  "start": null,
  "base_url": "http://localhost:3000",
  "health": "/healthz",
  "auth": {"method": "none", "storage_state_path": null, "probe_path": "/api/me"},
  "non_prod_assert": {"base_url_matches": "^http://localhost"},
  "seed": null,
  "reset": null,
  "stop": "pkill -f myapp",
  "ready_timeout_s": 5,
  "notes": "fixture"
}'
FIX_DIR="$(mktmp)"; FIX="$FIX_DIR/verify.json"
write_fixture "$FIX" "$FULL_JSON"

# ============================================================================
echo "== (a) AC1 absent store → empty stdout, exit 0, stderr names the path =="
A_DIR="$(mktmp)"
outA="$(run_reader "$A_DIR/verify.json")"; rcA=$?
[ "$rcA" -eq 0 ] && ok "(a) exits 0 with no store" || no "(a) expected exit 0, got $rcA"
[ -z "$outA" ] && ok "(a) emits NOTHING on stdout" || no "(a) expected empty stdout; got: $outA"
errA="$(cat "$LAST_ERR")"
case "$errA" in
  *"$A_DIR/verify.json"*) ok "(a) stderr NAMES THE PATH of the missing store" ;;
  *) no "(a) stderr did not name the path: $errA" ;;
esac
case "$errA" in
  *"[store_absent]"*) ok "(a) stderr carries the store_absent reason token" ;;
  *) no "(a) stderr lacks the store_absent token: $errA" ;;
esac

# ============================================================================
echo "== (b) AC2 well-formed fixture → ONE validated JSON object equal to the fixture =="
outB="$(run_reader "$FIX")"; rcB=$?
[ "$rcB" -eq 0 ] && ok "(b) exits 0" || no "(b) expected exit 0, got $rcB"
[ -n "$outB" ] && ok "(b) stdout is non-empty (machine consumers gate on this)" || no "(b) empty stdout for a valid store"
nlines="$(printf '%s\n' "$outB" | awk 'NF{n++} END{print n+0}')"
[ "$nlines" -eq 1 ] && ok "(b) stdout is exactly ONE line" || no "(b) expected 1 line, got $nlines"
if printf '%s' "$outB" | jq -e 'type=="object"' >/dev/null 2>&1; then
  ok "(b) stdout parses as a JSON object"
  want="$(jq -S -c . "$FIX")"; got="$(printf '%s' "$outB" | jq -S -c .)"
  [ "$want" = "$got" ] && ok "(b) the emitted object EQUALS the fixture (nothing invented, nothing dropped)" \
                       || no "(b) emitted object differs from the fixture: $got"
  for k in start seed reset; do
    printf '%s' "$outB" | jq -e --arg k "$k" 'has($k) and (.[$k] == null)' >/dev/null 2>&1 \
      && ok "(b) \`$k\` comes back PRESENT and null (nullable-required preserved)" \
      || no "(b) \`$k\` was not preserved as present+null"
  done
else
  no "(b) stdout is not a JSON object: $outB"
fi

# ============================================================================
echo "== (c) AC2 malformed roots → empty stdout, reason on stderr, exit 0 =="
C_DIR="$(mktmp)"
write_fixture "$C_DIR/bad.json" '{"start": null, "unterminated'
outC1="$(run_reader "$C_DIR/bad.json")"; rcC1=$?
[ "$rcC1" -eq 0 ] && [ -z "$outC1" ] && ok "(c1) unparseable JSON → empty stdout, exit 0" || no "(c1) rc=$rcC1 out=$outC1"
grep -qF "store_unparseable" "$LAST_ERR" && ok "(c1) stderr names the parse failure" || no "(c1) stderr: $(cat "$LAST_ERR")"
write_fixture "$C_DIR/arr.json" '["not", "an", "object"]'
outC2="$(run_reader "$C_DIR/arr.json")"; rcC2=$?
[ "$rcC2" -eq 0 ] && [ -z "$outC2" ] && ok "(c2) non-object root → empty stdout, exit 0" || no "(c2) rc=$rcC2 out=$outC2"
grep -qF "root_not_object" "$LAST_ERR" && ok "(c2) stderr names the non-object root" || no "(c2) stderr: $(cat "$LAST_ERR")"

# ============================================================================
echo "== (d) AC2 each required key deleted in turn → malformed, stderr names the key =="
D_DIR="$(mktmp)"
for k in start base_url health auth non_prod_assert seed reset stop; do
  jq --arg k "$k" 'del(.[$k])' "$FIX" > "$D_DIR/no-$k.json"
  outD="$(run_reader "$D_DIR/no-$k.json")"; rcD=$?
  if [ "$rcD" -eq 0 ] && [ -z "$outD" ]; then
    ok "(d) missing \`$k\` → empty stdout, exit 0"
  else
    no "(d) missing \`$k\`: rc=$rcD out=$outD"
  fi
  grep -qF "required_key_missing:$k" "$LAST_ERR" \
    && ok "(d) stderr names \`$k\` as the missing key" \
    || no "(d) stderr did not name \`$k\`: $(cat "$LAST_ERR")"
done

# ============================================================================
echo "== (e) AC2 NULLABLE-REQUIRED, both directions: null VALID, absent MALFORMED =="
E_DIR="$(mktmp)"
for k in start seed reset stop; do
  jq --arg k "$k" '.[$k] = null' "$FIX" > "$E_DIR/null-$k.json"
  jq --arg k "$k" 'del(.[$k])' "$FIX" > "$E_DIR/absent-$k.json"
  outE1="$(run_reader "$E_DIR/null-$k.json")"
  [ -n "$outE1" ] && ok "(e) \`$k: null\` reads as VALID (non-empty stdout)" \
                  || no "(e) \`$k: null\` was rejected: $(cat "$LAST_ERR")"
  outE2="$(run_reader "$E_DIR/absent-$k.json")"
  [ -z "$outE2" ] && ok "(e) \`$k\` ABSENT reads as MALFORMED (empty stdout)" \
                  || no "(e) \`$k\` absent was ACCEPTED — the presence check is not load-bearing"
done
# The pair used by the AC8 mutation control (M), kept as named files so (M) re-runs the SAME inputs.
SEED_NULL="$E_DIR/null-seed.json"; SEED_ABSENT="$E_DIR/absent-seed.json"
# A wrong TYPE is also malformed — a number where a shell string is expected.
jq '.seed = 42' "$FIX" > "$E_DIR/num-seed.json"
outE3="$(run_reader "$E_DIR/num-seed.json")"
[ -z "$outE3" ] && grep -qF "type_invalid:seed" "$LAST_ERR" \
  && ok "(e) \`seed: 42\` is malformed with type_invalid:seed" \
  || no "(e) a numeric seed was accepted or unnamed: out=$outE3 err=$(cat "$LAST_ERR")"

# ============================================================================
echo "== (f) AC2 non_prod_assert with NO usable member → non_prod_assert_empty =="
F_DIR="$(mktmp)"
jq '.non_prod_assert = {}' "$FIX" > "$F_DIR/empty.json"
jq '.non_prod_assert = {"base_url_matches": ""}' "$FIX" > "$F_DIR/emptyre.json"
jq '.non_prod_assert = {"unknown_member": true}' "$FIX" > "$F_DIR/unknown.json"
for f in empty emptyre unknown; do
  outF="$(run_reader "$F_DIR/$f.json")"; rcF=$?
  if [ "$rcF" -eq 0 ] && [ -z "$outF" ] && grep -qF "[non_prod_assert_empty]" "$LAST_ERR"; then
    ok "(f) $f → empty stdout, exit 0, token non_prod_assert_empty"
  else
    no "(f) $f: rc=$rcF out=$outF err=$(cat "$LAST_ERR")"
  fi
done
# A mistyped member ALONGSIDE a usable one is malformed too: the executor fails CLOSED, so a member
# the author wrote must never be silently dropped from what it evaluates.
jq '.non_prod_assert = {"base_url_matches": "^http://localhost", "env_var_equals": "NODE_ENV=dev"}' "$FIX" > "$F_DIR/mixed.json"
outF4="$(run_reader "$F_DIR/mixed.json")"
[ -z "$outF4" ] && grep -qF "type_invalid:non_prod_assert.env_var_equals" "$LAST_ERR" \
  && ok "(f) a mistyped env_var_equals beside a usable regex is still MALFORMED (never silently dropped)" \
  || no "(f) a mistyped member was tolerated: out=$outF4 err=$(cat "$LAST_ERR")"
# Each of the three member shapes is usable on its own.
jq '.non_prod_assert = {"env_var_equals": {"name": "NODE_ENV", "value": "development"}}' "$FIX" > "$F_DIR/env.json"
jq '.non_prod_assert = {"cmd": "test -f .not-prod"}' "$FIX" > "$F_DIR/cmd.json"
outF5="$(run_reader "$F_DIR/env.json")"; outF6="$(run_reader "$F_DIR/cmd.json")"
[ -n "$outF5" ] && ok "(f) env_var_equals alone is a usable member" || no "(f) env_var_equals alone rejected: $(cat "$LAST_ERR")"
[ -n "$outF6" ] && ok "(f) cmd alone is a usable member" || no "(f) cmd alone rejected: $(cat "$LAST_ERR")"
# env_var_equals.name must be a POSIX identifier — the SAME rule the executor's `${!name}` lookup
# and propose-verify.sh's parse-time refusal enforce. A well-typed member whose name is not an
# identifier is UNUSABLE (not mistyped): alone it leaves no usable member ⇒ non_prod_assert_empty,
# with the name called out; beside a usable regex the store is STILL EMITTED and the advisory is
# still named on stderr (the rule must never demote a previously-valid two-member store).
jq '.non_prod_assert = {"env_var_equals": {"name": "NODE-ENV", "value": "development"}}' "$FIX" > "$F_DIR/badname.json"
outF7="$(run_reader "$F_DIR/badname.json")"; rcF7=$?
[ "$rcF7" -eq 0 ] && [ -z "$outF7" ] && grep -qF "[env_var_name_invalid:NODE-ENV]" "$LAST_ERR" && grep -qF "[non_prod_assert_empty]" "$LAST_ERR" \
  && ok "(f) env_var_equals.name 'NODE-ENV' as the ONLY member → empty stdout, [env_var_name_invalid:NODE-ENV] + [non_prod_assert_empty]" \
  || no "(f) non-identifier name alone: rc=$rcF7 out=$outF7 err=$(cat "$LAST_ERR")"
jq '.non_prod_assert = {"env_var_equals": {"name": "1ABC", "value": "x"}}' "$FIX" > "$F_DIR/digitname.json"
outF8="$(run_reader "$F_DIR/digitname.json")"
[ -z "$outF8" ] && grep -qF "[env_var_name_invalid:1ABC]" "$LAST_ERR" \
  && ok "(f) a digit-leading name '1ABC' is likewise unusable" \
  || no "(f) digit-leading name accepted: out=$outF8 err=$(cat "$LAST_ERR")"
jq '.non_prod_assert = {"env_var_equals": {"name": "NODE-ENV", "value": "development"}, "base_url_matches": "^http://localhost"}' "$FIX" > "$F_DIR/badname-beside.json"
outF9="$(run_reader "$F_DIR/badname-beside.json")"
[ -n "$outF9" ] && printf '%s' "$outF9" | jq -e '.non_prod_assert.base_url_matches == "^http://localhost"' >/dev/null 2>&1 && grep -qF "[env_var_name_invalid:NODE-ENV]" "$LAST_ERR" && ! grep -qF "[non_prod_assert_empty]" "$LAST_ERR" \
  && ok "(f) a non-identifier name BESIDE a usable regex: store still emitted, advisory [env_var_name_invalid:NODE-ENV] on stderr, NOT malformed" \
  || no "(f) non-identifier beside usable: out=$outF9 err=$(cat "$LAST_ERR")"
[ "$(printf '%s\n' "$outF9" | wc -l | tr -d ' ')" = "1" ] && ok "(f) the advisory never leaks onto stdout (exactly one stdout line)" || no "(f) stdout is not exactly one line: $outF9"

# ============================================================================
echo "== (g) auth / ready_timeout_s shape =="
G_DIR="$(mktmp)"
jq '.auth.method = "oauth"' "$FIX" > "$G_DIR/enum.json"
jq '.auth = {"method": "storage_state"}' "$FIX" > "$G_DIR/nopath.json"
jq '.auth = {"method": "storage_state", "storage_state_path": ".auth/state.json", "probe_path": "/me"}' "$FIX" > "$G_DIR/ss.json"
jq '.ready_timeout_s = "60"' "$FIX" > "$G_DIR/tstr.json"
jq 'del(.ready_timeout_s) | del(.notes)' "$FIX" > "$G_DIR/noopt.json"
outG1="$(run_reader "$G_DIR/enum.json")"
[ -z "$outG1" ] && grep -qF "type_invalid:auth.method" "$LAST_ERR" && ok "(g) out-of-enum auth.method is malformed" || no "(g) out-of-enum auth.method accepted"
outG2="$(run_reader "$G_DIR/nopath.json")"
[ -z "$outG2" ] && grep -qF "type_invalid:auth.storage_state_path" "$LAST_ERR" && ok "(g) storage_state without a path is malformed" || no "(g) storage_state without a path accepted"
outG3="$(run_reader "$G_DIR/ss.json")"
[ -n "$outG3" ] && ok "(g) storage_state WITH a path is valid" || no "(g) storage_state with a path rejected: $(cat "$LAST_ERR")"
outG4="$(run_reader "$G_DIR/tstr.json")"
[ -z "$outG4" ] && grep -qF "type_invalid:ready_timeout_s" "$LAST_ERR" && ok "(g) a string ready_timeout_s is malformed" || no "(g) a string ready_timeout_s accepted"
outG5="$(run_reader "$G_DIR/noopt.json")"
[ -n "$outG5" ] && ok "(g) both optional keys absent is still valid" || no "(g) optional keys absent rejected: $(cat "$LAST_ERR")"

# ============================================================================
echo "== (h) jq unavailable → empty stdout, reason on stderr, exit 0 =="
STUBBIN="$(mktmp)/bin"; mkdir -p "$STUBBIN"
for b in git date mkdir dirname rm cat sed grep env bash sh mktemp printf; do
  src="$(command -v "$b" 2>/dev/null)"
  [ -n "$src" ] && ln -sf "$src" "$STUBBIN/$b"
done
# Probe in a FRESH bash: this shell's command hash table would report the already-resolved jq.
if PATH="$STUBBIN" bash -c 'command -v jq' >/dev/null 2>&1; then
  no "(h) jq-absent simulation failed — jq still resolvable on the stub PATH"
else
  ok "(h) jq-absent simulation effective"
  errH="$(mktmp)/err"
  outH="$(PATH="$STUBBIN" bash "$READER" --store "$FIX" --repo "$FAKE_REPO" 2>"$errH")"; rcH=$?
  [ "$rcH" -eq 0 ] && [ -z "$outH" ] && ok "(h) exits 0 with empty stdout when jq is unavailable" || no "(h) rc=$rcH out=$outH"
  grep -qF "jq_unavailable" "$errH" && ok "(h) stderr names jq as the reason" || no "(h) stderr: $(cat "$errH")"
fi

# ============================================================================
echo "== (i) pure-read + determinism =="
before="$(cksum < "$FIX")"
I1="$(run_reader "$FIX")"; I2="$(run_reader "$FIX")"
after="$(cksum < "$FIX")"
[ "$before" = "$after" ] && ok "(i) the store's bytes are unchanged after a run" || no "(i) the reader MODIFIED the store"
[ ! -e "$FAKE_REPO/.agent" ] && ok "(i) the reader created no .agent/ in the scratch repo" || no "(i) the reader created $FAKE_REPO/.agent"
[ "$I1" = "$I2" ] && ok "(i) two runs over the same fixture are byte-identical" || no "(i) output differs between two runs"

# ============================================================================
echo "== (j) override mechanism → VERIFY_STORE env, and --store wins over it =="
outJ1="$(VERIFY_STORE="$FIX" VERIFY_REPO_DIR="$FAKE_REPO" bash "$READER" 2>/dev/null)"
[ "$outJ1" = "$I1" ] && ok "(j) VERIFY_STORE resolves the same store as --store" || no "(j) VERIFY_STORE produced different output"
outJ2="$(VERIFY_STORE="$C_DIR/bad.json" bash "$READER" --store "$FIX" --repo "$FAKE_REPO" 2>/dev/null)"
[ "$outJ2" = "$I1" ] && ok "(j) --store WINS over VERIFY_STORE" || no "(j) --store did not take precedence"

# ============================================================================
echo "== (k) the READER NEVER EXECUTES a contract string =="
K_DIR="$(mktmp)"; MARK="$K_DIR/executed"
jq --arg m "touch $MARK" '.start = $m | .seed = $m | .reset = $m | .stop = $m | .non_prod_assert = {"cmd": $m}' "$FIX" > "$K_DIR/verify.json"
outK="$(run_reader "$K_DIR/verify.json")"
[ -n "$outK" ] && ok "(k) a fixture whose every shell string is \`touch <marker>\` reads as valid" || no "(k) marker fixture rejected: $(cat "$LAST_ERR")"
[ ! -e "$MARK" ] && ok "(k) NO marker exists after the read — no contract string was executed" \
                 || no "(k) THE READER EXECUTED A CONTRACT STRING — marker $MARK exists"

# ============================================================================
echo "== (p1) AC7 no --non-prod → proposal printed, exit 1, NOTHING written (± --confirm) =="
r_p1="$(new_repo)"; before_p1="$(tree_hash "$r_p1")"
run_writer "$r_p1"
[ "$RC" -eq 1 ] && ok "(p1) without --confirm: exit 1 (refused)" || no "(p1) expected exit 1, got $RC — $OUT"
case "$OUT" in *"PLANNED WRITE"*) ok "(p1) the proposal is still printed" ;; *) no "(p1) no proposal printed" ;; esac
case "$OUT" in *"BLOCKED: --non-prod"*) ok "(p1) the BLOCKED line names --non-prod" ;; *) no "(p1) no BLOCKED --non-prod line" ;; esac
case "$OUT" in *"never guessed"*) ok "(p1) the refusal says non-prod is never guessed" ;; *) no "(p1) refusal does not say never guessed" ;; esac
run_writer "$r_p1" --confirm
[ "$RC" -eq 1 ] && ok "(p1) WITH --confirm: still exit 1 (refused)" || no "(p1) --confirm without --non-prod exited $RC"
after_p1="$(tree_hash "$r_p1")"
[ "$before_p1" = "$after_p1" ] && ok "(p1) the tree is byte-identical after both runs" || no "(p1) a refused run modified the tree"
[ ! -e "$r_p1/.agent" ] && ok "(p1) no .agent/ was created" || no "(p1) .agent/ was created despite the refusal"

# ============================================================================
echo "== (p2) AC7 --non-prod, no --confirm, no TTY → proposal printed, exit 0, nothing written =="
r_p2="$(new_repo)"; before_p2="$(tree_hash "$r_p2")"; list_before_p2="$(tree_list "$r_p2")"
run_writer "$r_p2" --non-prod '^http://localhost'
after_p2="$(tree_hash "$r_p2")"; list_after_p2="$(tree_list "$r_p2")"
[ "$RC" -eq 0 ] && ok "(p2) the dry run exits 0" || no "(p2) dry run exited $RC — $OUT"
case "$OUT" in *"PLANNED WRITE (not written"*) ok "(p2) it PRINTS a proposal" ;; *) no "(p2) no proposal — $OUT" ;; esac
case "$OUT" in *"BLOCKED"*) no "(p2) a BLOCKED line appeared although --non-prod was supplied" ;; *) ok "(p2) no BLOCKED line" ;; esac
[ "$before_p2" = "$after_p2" ] && ok "(p2) the working tree is BYTE-IDENTICAL (hashed)" || no "(p2) the dry run MODIFIED the tree"
[ "$list_before_p2" = "$list_after_p2" ] && ok "(p2) no path added or removed" || no "(p2) the file list changed"
[ ! -e "$r_p2/.agent" ] && ok "(p2) no .agent/ directory was created" || no "(p2) .agent/ was created"
obj_p2="$(proposed_object)"
printf '%s' "$obj_p2" | jq -e '.non_prod_assert.base_url_matches == "^http://localhost"' >/dev/null 2>&1 \
  && ok "(p2) the printed object carries the supplied non_prod_assert" || no "(p2) printed object: $obj_p2"

# ============================================================================
echo "== (p3) AC7 --non-prod --confirm → EXACTLY ONE file, and it reads back through the reader =="
r_p3="$(new_repo)"; before_p3="$(tree_hash "$r_p3")"; list_before_p3="$(tree_list "$r_p3")"
run_writer "$r_p3" --non-prod '^http://localhost' --confirm
list_after_p3="$(tree_list "$r_p3")"; STORE_P3="$r_p3/.agent/verify.json"
[ "$RC" -eq 0 ] && ok "(p3) the confirmed run exits 0" || no "(p3) confirmed run exited $RC — $OUT"
[ -f "$STORE_P3" ] && ok "(p3) .agent/verify.json was created in the THROWAWAY tree" || no "(p3) store not created — $OUT"
added_p3="$(comm -13 <(printf '%s\n' "$list_before_p3") <(printf '%s\n' "$list_after_p3"))"
removed_p3="$(comm -23 <(printf '%s\n' "$list_before_p3") <(printf '%s\n' "$list_after_p3"))"
[ "$added_p3" = "./.agent/verify.json" ] && ok "(p3) the ONLY added path is ./.agent/verify.json (no temp file, log or backup left)" \
                                          || no "(p3) unexpected added paths: [$added_p3]"
[ -z "$removed_p3" ] && ok "(p3) no pre-existing path was removed" || no "(p3) paths removed: [$removed_p3]"
if [ -f "$STORE_P3" ]; then
  cp -R "$r_p3" "$ROOT/p3-copy"; rm -f "$ROOT/p3-copy/.agent/verify.json"; rmdir "$ROOT/p3-copy/.agent" 2>/dev/null
  [ "$before_p3" = "$(tree_hash "$ROOT/p3-copy")" ] && ok "(p3) every pre-existing file is byte-identical" || no "(p3) pre-existing files changed"
  back="$(bash "$READER" --store "$STORE_P3" --repo "$FAKE_REPO" 2>"$LAST_ERR")"
  [ -n "$back" ] && ok "(p3) the written store READS BACK as valid through read-verify.sh (writer↔reader seam)" \
                 || no "(p3) read-verify.sh rejects what propose-verify.sh wrote: $(cat "$LAST_ERR")"
  printf '%s' "$back" | jq -e '.non_prod_assert == {"base_url_matches": "^http://localhost"}' >/dev/null 2>&1 \
    && ok "(p3) non_prod_assert is EXACTLY the supplied member — nothing inferred was added" \
    || no "(p3) non_prod_assert differs from what was supplied: $back"
  for k in start base_url health auth non_prod_assert seed reset stop; do
    jq -e --arg k "$k" 'has($k)' "$STORE_P3" >/dev/null 2>&1 || no "(p3) written store lacks required key \`$k\`"
  done
  ok "(p3) the written store carries all eight required keys (jq has())"
  jq -e '.start == "npm run dev" and .seed == "npm run db:seed" and .base_url == "http://localhost:3000"' "$STORE_P3" >/dev/null 2>&1 \
    && ok "(p3) start/seed/base_url were SCANNED from the throwaway project (package.json + .env)" \
    || no "(p3) the scan did not feed the store: $(cat "$STORE_P3")"
  jq -e 'has("reset") and (.reset == null) and has("stop") and (.stop == null)' "$STORE_P3" >/dev/null 2>&1 \
    && ok "(p3) reset/stop (nothing scannable) were written PRESENT and null, not omitted" \
    || no "(p3) reset/stop not written as present+null"
fi

# ============================================================================
echo "== (p4) non_prod_assert is NEVER inferred from the scan =="
# new_repo()'s .env shouts NODE_ENV=development; without --non-prod that must change nothing.
r_p4="$(new_repo)"
run_writer "$r_p4"
obj_p4="$(proposed_object)"
printf '%s' "$obj_p4" | jq -e '.non_prod_assert == {}' >/dev/null 2>&1 \
  && ok "(p4) with NODE_ENV=development in .env the proposal's non_prod_assert is still {} (not inferred)" \
  || no "(p4) the scanner inferred a non_prod_assert: $obj_p4"
[ "$RC" -eq 1 ] && ok "(p4) and the run is still refused (exit 1)" || no "(p4) exit $RC"

# ============================================================================
echo "== (p5) base_url is never defaulted =="
r_p5="$(new_repo_bare)"; before_p5="$(tree_hash "$r_p5")"
run_writer "$r_p5" --non-prod '^http://localhost'
[ "$RC" -eq 0 ] && ok "(p5) the dry run still exits 0 (a first-time user sees the proposal)" || no "(p5) dry run exited $RC — $OUT"
case "$OUT" in *"BLOCKED: base_url"*) ok "(p5) the dry run prints a BLOCKED base_url line" ;; *) no "(p5) no BLOCKED base_url line — $OUT" ;; esac
run_writer "$r_p5" --non-prod '^http://localhost' --confirm
[ "$RC" -eq 2 ] && ok "(p5) --confirm without a scannable base_url refuses with exit 2 (shape)" || no "(p5) expected exit 2, got $RC — $OUT"
[ "$before_p5" = "$(tree_hash "$r_p5")" ] && ok "(p5) nothing was written" || no "(p5) the refused run modified the tree"
run_writer "$r_p5" --non-prod '^http://localhost' --base-url 'http://localhost:4000' --confirm
[ "$RC" -eq 0 ] && [ -f "$r_p5/.agent/verify.json" ] && ok "(p5) CONTROL: with --base-url the same repo writes" || no "(p5) control failed: rc=$RC — $OUT"

# ============================================================================
echo "== (p6) non-primary-checkout guard — a top-level .git FILE is refused (exit 3) =="
r_p6="$(mktemp -d "$ROOT/wt.XXXXXX")"
printf 'placeholder\n' > "$r_p6/src.txt"
printf 'gitdir: /nonexistent/worktrees/fake\n' > "$r_p6/.git"
[ -f "$r_p6/.git" ] && ok "(p6) simulation effective: the top-level .git is a FILE" || no "(p6) simulation INVALID"
before_p6="$(tree_hash "$r_p6")"
run_writer "$r_p6" --non-prod '^http://localhost' --base-url 'http://localhost:1' --confirm
[ "$RC" -eq 3 ] && ok "(p6) refused with the dedicated exit status 3" || no "(p6) expected exit 3, got $RC — $OUT"
case "$OUT" in
  *worktree*submodule*|*submodule*worktree*) ok "(p6) the refusal names BOTH the worktree and the submodule case" ;;
  *) no "(p6) the refusal does not name both causes — $OUT" ;;
esac
[ "$before_p6" = "$(tree_hash "$r_p6")" ] && ok "(p6) nothing was written in the refused checkout" || no "(p6) the refused checkout was modified"
rm -f "$r_p6/.git"
( cd "$r_p6" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init ) >/dev/null 2>&1
run_writer "$r_p6" --non-prod '^http://localhost' --base-url 'http://localhost:1' --confirm
[ "$RC" -eq 0 ] && ok "(p6) CONTROL: the same directory, as a real checkout, gets past the guard" \
                || no "(p6) CONTROL FAILED: the guard is not what refused (rc=$RC) — $OUT"

# ============================================================================
echo "== (p7) NO-CLOBBER — a second --confirm run refuses and leaves the store intact =="
if [ -f "$STORE_P3" ]; then
  bytes_before="$(cksum < "$STORE_P3")"
  run_writer "$r_p3" --non-prod '^https://staging' --confirm
  [ "$RC" -eq 1 ] && ok "(p7) the second confirmed run REFUSES (exit 1)" || no "(p7) second run rc=$RC"
  [ "$bytes_before" = "$(cksum < "$STORE_P3")" ] && ok "(p7) the existing store's bytes are unchanged" || no "(p7) the store was overwritten"
else
  no "(p7) no store from (p3) to run the no-clobber case against"
fi

# ============================================================================
echo "== (p8) --non-prod value shapes =="
r_p8="$(new_repo)"
run_writer "$r_p8" --non-prod 'env=NODE_ENV=development' --non-prod 'cmd=test -f .not-prod' --non-prod '^http://localhost'
obj_p8="$(proposed_object)"
printf '%s' "$obj_p8" | jq -e '.non_prod_assert == {"env_var_equals": {"name": "NODE_ENV", "value": "development"}, "cmd": "test -f .not-prod", "base_url_matches": "^http://localhost"}' >/dev/null 2>&1 \
  && ok "(p8) env=NAME=VAL → env_var_equals, cmd=… → cmd, other → base_url_matches" \
  || no "(p8) member mapping wrong: $obj_p8"
before_p8="$(tree_hash "$r_p8")"
run_writer "$r_p8" --non-prod 'env=NODE_ENV' --confirm
[ "$RC" -eq 1 ] && ok "(p8) a malformed env= form (no =VAL) is rejected with exit 1" || no "(p8) expected exit 1, got $RC"
run_writer "$r_p8" --non-prod '' --confirm
[ "$RC" -eq 1 ] && ok "(p8) an empty --non-prod is rejected with exit 1" || no "(p8) expected exit 1, got $RC"
# NAME must be a POSIX identifier — parity with the reader (unusable member) and the executor
# (`${!name}` lookup): a bad name is refused HERE, at parse time, so it can never pass proposal,
# --confirm and the reader only to fail closed at the first run.
run_writer "$r_p8" --non-prod 'env=NODE-ENV=x' --confirm
[ "$RC" -eq 1 ] && ok "(p8) env=NODE-ENV=x (hyphen in NAME) is refused with exit 1" || no "(p8) env=NODE-ENV=x: expected exit 1, got $RC — $OUT"
case "$OUT" in *"must be a POSIX identifier: [A-Za-z_][A-Za-z0-9_]*"*) ok "(p8) the refusal names the rule (POSIX identifier)" ;; *) no "(p8) refusal does not name the identifier rule: $OUT" ;; esac
run_writer "$r_p8" --non-prod 'env=1ABC=x' --confirm
[ "$RC" -eq 1 ] && ok "(p8) env=1ABC=x (digit-leading NAME) is refused with exit 1" || no "(p8) env=1ABC=x: expected exit 1, got $RC — $OUT"
run_writer "$r_p8" --non-prod 'env=NODE_ENV=x'
[ "$RC" -eq 0 ] && printf '%s' "$(proposed_object)" | jq -e '.non_prod_assert.env_var_equals.name == "NODE_ENV"' >/dev/null 2>&1 \
  && ok "(p8) CONTROL: env=NODE_ENV=x (an identifier) is still accepted" || no "(p8) CONTROL FAILED: rc=$RC — $OUT"
[ "$before_p8" = "$(tree_hash "$r_p8")" ] && [ ! -e "$r_p8/.agent" ] && ok "(p8) none of the rejected runs wrote anything (tree byte-identical, no .agent/)" || no "(p8) a rejected run modified the tree"

echo "== (p9) --non-prod is ONE PER KIND — a second value of a kind already given is refused, nothing written =="
# The store holds one member per kind, so a silent last-wins overwrite would drop an assertion the
# caller believes is in force. Each duplicate must exit 1 at parse time and leave the tree untouched,
# even with --confirm.
r_p9="$(new_repo)"; before_p9="$(tree_hash "$r_p9")"
run_writer "$r_p9" --non-prod '^http://localhost' --non-prod '^http://127' --confirm
[ "$RC" -eq 1 ] && ok "(p9) a second regex value is refused with exit 1" || no "(p9) second regex: expected exit 1, got $RC"
case "$OUT" in *"one member per kind"*) ok "(p9) the refusal says one member per kind" ;; *) no "(p9) refusal text does not say one member per kind: $OUT" ;; esac
case "$OUT" in *'combine regexes with `|`'*) ok "(p9) the refusal tells the caller to combine regexes with |" ;; *) no "(p9) refusal does not suggest combining with |: $OUT" ;; esac
run_writer "$r_p9" --non-prod 'env=NODE_ENV=development' --non-prod 'env=APP_ENV=staging' --confirm
[ "$RC" -eq 1 ] && ok "(p9) a second env= value is refused with exit 1" || no "(p9) second env=: expected exit 1, got $RC"
run_writer "$r_p9" --non-prod 'cmd=test -f .a' --non-prod 'cmd=test -f .b' --confirm
[ "$RC" -eq 1 ] && ok "(p9) a second cmd= value is refused with exit 1" || no "(p9) second cmd=: expected exit 1, got $RC"
[ "$before_p9" = "$(tree_hash "$r_p9")" ] && [ ! -e "$r_p9/.agent" ] \
  && ok "(p9) none of the three refused --confirm runs wrote anything (tree byte-identical, no .agent/)" \
  || no "(p9) a refused duplicate-kind run modified the tree"
# CONTROL: one of EACH kind (three distinct members) is still accepted — the guard is per kind, not per count.
run_writer "$r_p9" --non-prod '^http://localhost|^http://127' --non-prod 'env=NODE_ENV=development' --non-prod 'cmd=test -f .a'
[ "$RC" -eq 0 ] && printf '%s' "$(proposed_object)" | jq -e '.non_prod_assert | keys == ["base_url_matches","cmd","env_var_equals"]' >/dev/null 2>&1 \
  && ok "(p9) CONTROL: one value of each kind (a |-combined regex included) is accepted with all three members" \
  || no "(p9) CONTROL FAILED: rc=$RC out=$OUT"

# ============================================================================
echo "== (S) AC5 SOLE WRITER — exactly one move onto the literal verify.json in loomwright/scripts/*.sh =="
# Capture-then-test: never `producer | grep -q` under pipefail (SIGPIPE can fail a matching pipe).
# Comment lines are stripped first so prose never counts; the pattern then requires the `mv`
# command word followed by the literal store name on the same line. test-*.sh files are excluded
# (this suite mentions the string itself).
# (A function rather than an inline `$( for … case … )`: bash 3.2's command-substitution parser
# trips on the unbalanced `)` of a case pattern inside `$(...)`.)
sole_writer_hits() {
  local f b
  for f in "$HERE"/*.sh; do
    b="$(basename "$f")"
    case "$b" in test-*.sh) continue ;; esac
    grep -nE '(^|[^[:alnum:]_-])mv[[:space:]].*verify\.json' "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$b:|"
  done
  return 0
}
sole_hits="$(sole_writer_hits)"
sole_count="$(printf '%s\n' "$sole_hits" | awk 'NF{n++} END{print n+0}')"
[ "$sole_count" -eq 1 ] && ok "(S) exactly ONE mv onto verify.json across the non-test scripts" \
                        || no "(S) expected 1 mv onto verify.json, found $sole_count: $sole_hits"
case "$sole_hits" in
  propose-verify.sh:*) ok "(S) and it lives in propose-verify.sh" ;;
  *) no "(S) the mv is not in propose-verify.sh: $sole_hits" ;;
esac
reader_mv="$(grep -cE '(^|[^[:alnum:]_-])mv[[:space:]]' "$READER" 2>/dev/null)"
[ "${reader_mv:-0}" -eq 0 ] && ok "(S) read-verify.sh contains no mv at all" || no "(S) read-verify.sh contains $reader_mv mv line(s)"
# The grep must be able to SEE a hit — plant one in a scratch copy and confirm it is counted.
plant="$(mktmp)"; printf 'mv -f "$tmp" "$D/verify.json"\n# mv comment verify.json\n' > "$plant/x.sh"
plant_n="$(grep -nE '(^|[^[:alnum:]_-])mv[[:space:]].*verify\.json' "$plant/x.sh" | grep -vE '^[0-9]+:[[:space:]]*#' | awk 'NF{n++} END{print n+0}')"
[ "$plant_n" -eq 1 ] && ok "(S) CONTROL: the sole-writer grep counts a planted mv once and ignores a comment" \
                     || no "(S) CONTROL FAILED: planted mv counted $plant_n times"

# ============================================================================
echo "== (M) AC8 MUTATION CONTROL — delete the has(\"seed\") presence check from a COPY of the reader =="
MUT="$(mktmp)/read-verify-mutant.sh"
# The reader's presence check is the generic nullable_required($o; $k). To disable it for `seed`
# ONLY, the mutant replaces that call with an empty check — the `//`-default collapse in effect.
sed 's/+ nullable_required(\$o; "seed")/+ []/' "$READER" > "$MUT"
if [ ! -s "$MUT" ] || cmp -s "$MUT" "$READER"; then
  no "(M) mutation control could not be applied (sed matched nothing?) — case (e) is UNPROVEN"
elif ! bash -n "$MUT" 2>/dev/null; then
  no "(M) the mutant does not parse — the control is meaningless"
else
  ok "(M) mutant is non-empty, differs from the original, and parses"
  mut_null="$(run_reader "$SEED_NULL" "$MUT")"
  [ -n "$mut_null" ] && ok "(M) the mutant still accepts \`seed: null\` (only the presence guard was removed)" \
                     || no "(M) the mutant is broken beyond the guard — control meaningless"
  mut_absent="$(run_reader "$SEED_ABSENT" "$MUT")"; mut_rc=$?
  [ "$mut_rc" -eq 0 ] && ok "(M) the mutant still runs (exit 0)" || no "(M) mutant rc=$mut_rc"
  if [ -n "$mut_absent" ]; then
    ok "(M) CONTROL HELD: with the presence check gone, the missing-\`seed\` fixture is ACCEPTED ⇒ case (e) is NOT vacuous"
  else
    no "(M) CONTROL BROKEN: the mutant still rejects the missing-seed fixture — (e) may pass for another reason"
  fi
fi

# ============================================================================
echo "== (T) tree_hash discriminates (control for every byte-identical assertion above) =="
r_t="$(new_repo)"; h0="$(tree_hash "$r_t")"
printf 'stray\n' > "$r_t/stray.txt"; h1="$(tree_hash "$r_t")"
[ "$h0" != "$h1" ] && ok "(T) a planted stray file changes the tree hash" || no "(T) tree_hash ignored a new file — the containment assertions are VACUOUS"
rm -f "$r_t/stray.txt"; printf 'edited\n' > "$r_t/src.txt"; h2="$(tree_hash "$r_t")"
[ "$h0" != "$h2" ] && ok "(T) an in-place content edit changes the tree hash" || no "(T) tree_hash ignored a content edit"

# --- executor cases (Subtask 2 appends below this line) ---

# ============================================================================
# EXECUTOR CASES (verify-env.sh) — Subtask 2. Same containment rules: every fixture, state dir and
# marker lives under $ROOT; the http.server fixture binds 127.0.0.1 on a port chosen free at run
# time and is killed on exit whatever happens above.
#   (AC3) assert-non-prod   → three arms (empty / failed / pass) + env_var_equals + cmd; nothing is
#                             persisted; `{"non_prod_assert":{}}` forwards the READER's token
#   (AC4) start             → never-2xx fixture: [health_timeout] after ready_timeout_s AND stop ran;
#                             python3 -m http.server fixture: exit 0 + `ready`; stop kills the pid;
#                             auth-probe against the live server; --ready-timeout-s overrides;
#                             LIFECYCLE: a second start refuses [already_started] and touches nothing;
#                             a start string exiting non-zero is [start_exited:<rc>] even with health
#                             2xx elsewhere; exit 0 is a detached starter; a stale record does NOT
#                             refuse a re-start [stale_pid_cleared]; stop with a dead recorded pid is
#                             non-zero [not_running]; ready_timeout_s is wall-clock (hanging curl);
#                             HEALTH IS 2xx ONLY: a PATH-stubbed curl printing `302` never yields
#                             `ready` (health_timeout), one printing `200` does
#   (AC9) refuse-before-run → every mutating subcommand refuses under a failing assertion and its
#                             marker-touching string never runs; a pass in a PREVIOUS invocation
#                             buys nothing; MUTATION CONTROL: delete the dispatch-level gate call
#                             from a COPY ⇒ the inner [non_prod_not_asserted] check still refuses;
#                             the reader is located as a SIBLING (a lone copy reports reader_missing)
# ============================================================================
EXEC="$HERE/verify-env.sh"
if [ ! -f "$EXEC" ]; then
  no "(exec) executor not found at $EXEC — every executor case below is unreachable"
fi

# run_exec <args...> — stdout → OUT_E, exit → RC_E, stderr → $LAST_ERR. Runs from a NEUTRAL cwd
# (the executor takes --repo), stdin closed.
run_exec() {
  : > "$LAST_ERR"
  OUT_E="$( ( cd "$ROOT" && bash "$EXEC" "$@" ) </dev/null 2>"$LAST_ERR" )"; RC_E=$?
}
# Reason-token presence, capture-then-test (never `| grep -q` under pipefail).
has_token() { grep -qF "[$1]" "$LAST_ERR"; }

SERVER_PID=""
kill_server() { [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null; return 0; }
trap 'kill_server; rm -rf "$ROOT" 2>/dev/null' EXIT

free_port() {
  python3 -c 'import socket
s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null
}
HAVE_PY=1; command -v python3 >/dev/null 2>&1 || HAVE_PY=0

# ============================================================================
echo "== (AC3) assert-non-prod =="
A_DIR="$(mktmp)"; A_STATE="$A_DIR/state"
# Arm 1 — EMPTY: the literal `{"non_prod_assert":{}}` from the AC, and the full fixture with the
# member emptied. Both are refused by the READER; the executor must forward that token, not invent
# `store unreadable` as the reason.
printf '%s' '{"non_prod_assert":{}}' > "$A_DIR/literal.json"
jq '.non_prod_assert = {}' "$FIX" > "$A_DIR/empty.json"
for f in literal empty; do
  run_exec assert-non-prod --store "$A_DIR/$f.json" --repo "$A_DIR" --state-dir "$A_STATE"
  [ "$RC_E" -ne 0 ] && has_token non_prod_assert_empty \
    && ok "(AC3) $f: assert-non-prod exits non-zero (rc=$RC_E) with reason non_prod_assert_empty" \
    || no "(AC3) $f: rc=$RC_E err=$(cat "$LAST_ERR")"
  grep -E '^verify-env:.*\[non_prod_assert_empty\]' "$LAST_ERR" >/dev/null \
    && ok "(AC3) $f: the executor's OWN verdict line carries the reader's token (forwarded, not re-parsed)" \
    || no "(AC3) $f: the executor's verdict line does not carry non_prod_assert_empty: $(grep '^verify-env:' "$LAST_ERR")"
done
# Arm 2 — FAILED: regex ^http://localhost vs base_url https://app.example.com.
jq '.base_url = "https://app.example.com" | .non_prod_assert = {"base_url_matches": "^http://localhost"}' "$FIX" > "$A_DIR/failed.json"
run_exec assert-non-prod --store "$A_DIR/failed.json" --repo "$A_DIR" --state-dir "$A_STATE"
[ "$RC_E" -ne 0 ] && has_token non_prod_assert_failed \
  && ok "(AC3) failed: ^http://localhost vs https://app.example.com → rc=$RC_E, reason non_prod_assert_failed" \
  || no "(AC3) failed: rc=$RC_E err=$(cat "$LAST_ERR")"
# Arm 3 — PASS: a matching regex.
run_exec assert-non-prod --store "$FIX" --repo "$A_DIR" --state-dir "$A_STATE"
[ "$RC_E" -eq 0 ] && ok "(AC3) pass: ^http://localhost matches http://localhost:3000 → exit 0" \
                  || no "(AC3) pass: rc=$RC_E err=$(cat "$LAST_ERR")"
[ ! -e "$A_STATE" ] && ok "(AC3) a pass persists NOTHING (no state dir was created by assert-non-prod)" \
                    || no "(AC3) assert-non-prod created state at $A_STATE — a pass must not outlive its process"
# env_var_equals — equal / different / unset / not-an-identifier (the reader refuses a non-identifier
# name as the ONLY member and forwards [env_var_name_invalid:<name>]; beside another member the
# executor's OWN check must still fail CLOSED on a name it cannot look up — belt and suspenders).
jq '.non_prod_assert = {"env_var_equals": {"name": "VERIFY_SEAM_ENV", "value": "development"}}' "$FIX" > "$A_DIR/env.json"
VERIFY_SEAM_ENV=development run_exec assert-non-prod --store "$A_DIR/env.json" --repo "$A_DIR"
[ "$RC_E" -eq 0 ] && ok "(AC3) env_var_equals: \$VERIFY_SEAM_ENV=development → exit 0" || no "(AC3) env equal: rc=$RC_E err=$(cat "$LAST_ERR")"
VERIFY_SEAM_ENV=production run_exec assert-non-prod --store "$A_DIR/env.json" --repo "$A_DIR"
[ "$RC_E" -ne 0 ] && has_token non_prod_assert_failed && ok "(AC3) env_var_equals: \$VERIFY_SEAM_ENV=production → non_prod_assert_failed" || no "(AC3) env differ: rc=$RC_E err=$(cat "$LAST_ERR")"
( unset VERIFY_SEAM_ENV; run_exec assert-non-prod --store "$A_DIR/env.json" --repo "$A_DIR"; exit "$RC_E" ); rc_unset=$?
[ "$rc_unset" -ne 0 ] && has_token non_prod_assert_failed && ok "(AC3) env_var_equals: variable UNSET → non_prod_assert_failed (unset is not 'equal to anything')" || no "(AC3) env unset: rc=$rc_unset err=$(cat "$LAST_ERR")"
jq '.non_prod_assert = {"env_var_equals": {"name": "NOT-A-NAME", "value": ""}}' "$FIX" > "$A_DIR/badname.json"
run_exec assert-non-prod --store "$A_DIR/badname.json" --repo "$A_DIR"
[ "$RC_E" -eq 3 ] && has_token "env_var_name_invalid:NOT-A-NAME" && has_token non_prod_assert_empty && has_token verify_store_unreadable \
  && ok "(AC3) env_var_equals: an invalid identifier as the ONLY member is refused by the READER (exit 3), tokens forwarded" \
  || no "(AC3) bad name alone: rc=$RC_E err=$(cat "$LAST_ERR")"
jq '.base_url = "https://app.example.com" | .non_prod_assert = {"env_var_equals": {"name": "NOT-A-NAME", "value": ""}, "base_url_matches": "^http://localhost"}' "$FIX" > "$A_DIR/badname-beside.json"
run_exec assert-non-prod --store "$A_DIR/badname-beside.json" --repo "$A_DIR"
[ "$RC_E" -eq 1 ] && has_token non_prod_assert_failed && grep -qF "(2 evaluated)" "$LAST_ERR" \
  && ok "(AC3) env_var_equals: an invalid identifier BESIDE a failing regex reaches the executor and fails CLOSED (non_prod_assert_failed)" \
  || no "(AC3) bad name beside: rc=$RC_E err=$(cat "$LAST_ERR")"
# cmd — exit 0 = pass; runs in the --repo dir (a relative path resolves there, never in the cwd).
jq '.non_prod_assert = {"cmd": "test -f .not-prod"}' "$FIX" > "$A_DIR/cmd.json"
run_exec assert-non-prod --store "$A_DIR/cmd.json" --repo "$A_DIR"
[ "$RC_E" -ne 0 ] && has_token non_prod_assert_failed && ok "(AC3) cmd: 'test -f .not-prod' with no such file → non_prod_assert_failed" || no "(AC3) cmd fail: rc=$RC_E err=$(cat "$LAST_ERR")"
: > "$A_DIR/.not-prod"
run_exec assert-non-prod --store "$A_DIR/cmd.json" --repo "$A_DIR"
[ "$RC_E" -eq 0 ] && ok "(AC3) cmd: same string once .not-prod exists in the --repo dir → exit 0 (cmd runs in the repo dir)" || no "(AC3) cmd pass: rc=$RC_E err=$(cat "$LAST_ERR")"
# ≥1 pass suffices: a failing regex beside a passing cmd passes.
jq '.base_url = "https://app.example.com" | .non_prod_assert = {"base_url_matches": "^http://localhost", "cmd": "test -f .not-prod"}' "$FIX" > "$A_DIR/mixed.json"
run_exec assert-non-prod --store "$A_DIR/mixed.json" --repo "$A_DIR"
[ "$RC_E" -eq 0 ] && grep -q "1 of 2" "$LAST_ERR" && ok "(AC3) at least one passing member suffices (regex fails, cmd passes → exit 0, '1 of 2')" || no "(AC3) mixed: rc=$RC_E err=$(cat "$LAST_ERR")"
# During assert-non-prod ONLY the cmd member runs — never start/stop/seed/reset.
M_DIR="$(mktmp)"
jq --arg s "touch $M_DIR/m-start" --arg t "touch $M_DIR/m-stop" --arg e "touch $M_DIR/m-seed" --arg r "touch $M_DIR/m-reset" --arg c "touch $M_DIR/m-cmd" \
   '.start = $s | .stop = $t | .seed = $e | .reset = $r | .non_prod_assert = {"cmd": $c}' "$FIX" > "$M_DIR/verify.json"
run_exec assert-non-prod --store "$M_DIR/verify.json" --repo "$M_DIR"
[ "$RC_E" -eq 0 ] && [ -e "$M_DIR/m-cmd" ] && ok "(AC3) the cmd member IS executed by assert-non-prod (it is the assertion)" || no "(AC3) cmd member did not run: rc=$RC_E err=$(cat "$LAST_ERR")"
[ ! -e "$M_DIR/m-start" ] && [ ! -e "$M_DIR/m-stop" ] && [ ! -e "$M_DIR/m-seed" ] && [ ! -e "$M_DIR/m-reset" ] \
  && ok "(AC3) assert-non-prod ran NO step string (start/stop/seed/reset markers absent)" \
  || no "(AC3) assert-non-prod executed a step string: $(ls "$M_DIR")"
# Absent store: the executor announces the absence BY NAME, names the bootstrap, and stops (exit 3).
run_exec assert-non-prod --store "$A_DIR/nope.json" --repo "$A_DIR"
[ "$RC_E" -eq 3 ] && has_token store_absent && has_token verify_store_unreadable && grep -q "propose-verify.sh" "$LAST_ERR" \
  && ok "(AC3) absent store → exit 3, [store_absent] forwarded, bootstrap named, nothing run" \
  || no "(AC3) absent store: rc=$RC_E err=$(cat "$LAST_ERR")"
# Usage failures are exit 2 and never reach the gate.
run_exec --store "$FIX" --repo "$A_DIR"
[ "$RC_E" -eq 2 ] && has_token usage && ok "(AC3) no subcommand → exit 2 [usage]" || no "(AC3) no subcommand: rc=$RC_E"
run_exec start --store "$FIX" --repo "$A_DIR" --ready-timeout-s abc
[ "$RC_E" -eq 2 ] && has_token usage && ok "(AC3) --ready-timeout-s abc → exit 2 [usage] (a malformed override is never silently the default)" || no "(AC3) bad timeout: rc=$RC_E err=$(cat "$LAST_ERR")"

# ============================================================================
echo "== (AC4) start: health_timeout runs stop; python3 -m http.server fixture passes =="
B_DIR="$(mktmp)"
if [ "$HAVE_PY" -eq 1 ]; then
  # Never-2xx arm: health points at a port nobody listens on (chosen free, then NOT bound).
  DEAD_PORT="$(free_port)"
  jq --arg s "touch $B_DIR/started" --arg t "touch $B_DIR/stopped" --arg u "http://127.0.0.1:$DEAD_PORT" \
     '.start = $s | .stop = $t | .base_url = $u | .health = "/healthz" | .non_prod_assert = {"base_url_matches": "^http://127"} | .ready_timeout_s = 2' \
     "$FIX" > "$B_DIR/never.json"
  t0="$(date +%s)"
  run_exec start --store "$B_DIR/never.json" --repo "$B_DIR" --state-dir "$B_DIR/state-never"
  t1="$(date +%s)"; elapsed=$((t1 - t0))
  [ "$RC_E" -ne 0 ] && has_token health_timeout \
    && ok "(AC4) never-2xx: start exits non-zero (rc=$RC_E) with reason health_timeout" \
    || no "(AC4) never-2xx: rc=$RC_E err=$(cat "$LAST_ERR")"
  [ -e "$B_DIR/started" ] && ok "(AC4) never-2xx: the start string DID run (the gate had passed)" || no "(AC4) never-2xx: start string never ran"
  [ -e "$B_DIR/stopped" ] && ok "(AC4) never-2xx: stop RAN after the timeout (marker present)" || no "(AC4) never-2xx: stop did not run — marker absent"
  [ "$elapsed" -ge 2 ] && [ "$elapsed" -le 15 ] && ok "(AC4) never-2xx: gave up after ready_timeout_s (elapsed ${elapsed}s, window 2..15)" \
                                                 || no "(AC4) never-2xx: elapsed ${elapsed}s is outside the 2..15s window for ready_timeout_s=2"
  # The flag overrides the store's ready_timeout_s (store says 30; flag says 1).
  jq '.ready_timeout_s = 30' "$B_DIR/never.json" > "$B_DIR/never30.json"
  t0="$(date +%s)"
  run_exec start --store "$B_DIR/never30.json" --repo "$B_DIR" --state-dir "$B_DIR/state-never" --ready-timeout-s 1
  t1="$(date +%s)"; elapsed=$((t1 - t0))
  [ "$RC_E" -ne 0 ] && has_token health_timeout && [ "$elapsed" -le 10 ] \
    && ok "(AC4) --ready-timeout-s 1 overrides the store's 30 (elapsed ${elapsed}s)" \
    || no "(AC4) override: rc=$RC_E elapsed=${elapsed}s err=$(cat "$LAST_ERR")"

  # Live arm: python3 -m http.server on a free port; health "/" is served by it.
  LIVE_PORT="$(free_port)"
  jq --arg s "python3 -m http.server $LIVE_PORT --bind 127.0.0.1" --arg u "http://127.0.0.1:$LIVE_PORT" \
     '.start = $s | .stop = null | .base_url = $u | .health = "/" | .non_prod_assert = {"base_url_matches": "^http://127"} | .ready_timeout_s = 15
      | .auth = {"method": "storage_state", "storage_state_path": "state.json", "probe_path": "/"}' \
     "$FIX" > "$B_DIR/live.json"
  printf '%s' '{"cookies":[{"name":"session","value":"abc123","domain":"127.0.0.1","path":"/"}],"origins":[]}' > "$B_DIR/state.json"
  run_exec start --store "$B_DIR/live.json" --repo "$B_DIR" --state-dir "$B_DIR/state-live"
  SERVER_PID="$(cat "$B_DIR/state-live/pid" 2>/dev/null)"
  [ "$RC_E" -eq 0 ] && [ "$OUT_E" = "ready" ] \
    && ok "(AC4) http.server fixture: start exits 0 within the timeout and prints 'ready'" \
    || no "(AC4) http.server: rc=$RC_E out=$OUT_E err=$(cat "$LAST_ERR")"
  case "$SERVER_PID" in
    ''|*[!0-9]*) no "(AC4) http.server: no numeric pid recorded under --state-dir (got '$SERVER_PID')" ;;
    *) kill -0 "$SERVER_PID" 2>/dev/null && ok "(AC4) http.server: recorded pid $SERVER_PID is alive" || no "(AC4) http.server: recorded pid $SERVER_PID is not running" ;;
  esac
  # --- LIFECYCLE VERDICTS ARE NEVER VACUOUS (start/stop guarantees must actually hold) ---
  # Replay hole: a second `start` while the recorded pid is alive must REFUSE [already_started] —
  # not launch a second instance, not overwrite the record, and not print `ready` on the strength
  # of health served by the first instance.
  run_exec start --store "$B_DIR/live.json" --repo "$B_DIR" --state-dir "$B_DIR/state-live"
  [ "$RC_E" -ne 0 ] && has_token already_started && [ "$OUT_E" != "ready" ] \
    && ok "(AC4) a second start while the recorded pid is alive refuses (rc=$RC_E) [already_started], no 'ready'" \
    || no "(AC4) second start: rc=$RC_E out=$OUT_E err=$(cat "$LAST_ERR")"
  [ "$(cat "$B_DIR/state-live/pid" 2>/dev/null)" = "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null \
    && ok "(AC4) the refused start left the pid record ($SERVER_PID) and the running server untouched" \
    || no "(AC4) the refused start overwrote the record or killed the server (record='$(cat "$B_DIR/state-live/pid" 2>/dev/null)')"
  # start_exited: a start string that dies non-zero while health is 2xx (served by the STILL-RUNNING
  # live server) is a FAILED start — never `ready` — and its dead pid record is dropped.
  jq --arg u "http://127.0.0.1:$LIVE_PORT" '.start = "exit 3" | .base_url = $u | .health = "/" | .ready_timeout_s = 5' "$B_DIR/live.json" > "$B_DIR/dies.json"
  run_exec start --store "$B_DIR/dies.json" --repo "$B_DIR" --state-dir "$B_DIR/state-dies"
  [ "$RC_E" -ne 0 ] && has_token "start_exited:3" && [ "$OUT_E" != "ready" ] && [ ! -e "$B_DIR/state-dies/pid" ] \
    && ok "(AC4) a start string that exits 3 while health is 2xx elsewhere → non-zero [start_exited:3], no 'ready', record dropped" \
    || no "(AC4) start_exited: rc=$RC_E out=$OUT_E pid_record=$([ -e "$B_DIR/state-dies/pid" ] && echo present || echo absent) err=$(cat "$LAST_ERR")"
  # A start string that exits 0 is a DETACHED starter (docker compose up -d shape): health from the
  # live server still counts, `ready` is printed, and the dead pid record is dropped rather than kept.
  jq '.start = "true"' "$B_DIR/dies.json" > "$B_DIR/detached.json"
  run_exec start --store "$B_DIR/detached.json" --repo "$B_DIR" --state-dir "$B_DIR/state-detached"
  [ "$RC_E" -eq 0 ] && [ "$OUT_E" = "ready" ] && has_token start_detached && [ ! -e "$B_DIR/state-detached/pid" ] \
    && ok "(AC4) a start string that exits 0 is a detached starter: 'ready' (health 2xx), [start_detached], no dead pid kept" \
    || no "(AC4) detached: rc=$RC_E out=$OUT_E err=$(cat "$LAST_ERR")"
  # auth-probe against the live server: cookies from the storage state, 2xx ⇒ authenticated.
  run_exec auth-probe --store "$B_DIR/live.json" --repo "$B_DIR" --state-dir "$B_DIR/state-live"
  [ "$RC_E" -eq 0 ] && [ "$OUT_E" = "authenticated" ] && ok "(AC4) auth-probe: 2xx with the storage-state cookie → 'authenticated'" \
                                                       || no "(AC4) auth-probe live: rc=$RC_E out=$OUT_E err=$(cat "$LAST_ERR")"
  jq '.auth.probe_path = "/definitely-not-here"' "$B_DIR/live.json" > "$B_DIR/live404.json"
  run_exec auth-probe --store "$B_DIR/live404.json" --repo "$B_DIR"
  [ "$RC_E" -ne 0 ] && has_token "auth_probe_unexpected:404" && ok "(AC4) auth-probe: a 404 is neither verdict → non-zero [auth_probe_unexpected:404]" \
                                                             || no "(AC4) auth-probe 404: rc=$RC_E out=$OUT_E err=$(cat "$LAST_ERR")"
  jq '.auth.storage_state_path = "missing-state.json"' "$B_DIR/live.json" > "$B_DIR/livenostate.json"
  run_exec auth-probe --store "$B_DIR/livenostate.json" --repo "$B_DIR"
  [ "$RC_E" -ne 0 ] && has_token storage_state_absent && ok "(AC4) auth-probe: a missing storage state file → [storage_state_absent]" \
                                                       || no "(AC4) auth-probe no state: rc=$RC_E err=$(cat "$LAST_ERR")"
  # stop with `stop: null` kills the recorded pid and clears the record.
  run_exec stop --store "$B_DIR/live.json" --repo "$B_DIR" --state-dir "$B_DIR/state-live"
  gone=0; i=0
  while [ "$i" -lt 10 ]; do kill -0 "$SERVER_PID" 2>/dev/null || { gone=1; break; }; sleep 1; i=$((i+1)); done
  [ "$RC_E" -eq 0 ] && [ "$gone" -eq 1 ] && ok "(AC4) stop (null) killed the recorded pid — server gone" || no "(AC4) stop: rc=$RC_E gone=$gone err=$(cat "$LAST_ERR")"
  [ ! -e "$B_DIR/state-live/pid" ] && ok "(AC4) stop removed the pid record" || no "(AC4) pid record still present after stop"
  [ "$gone" -eq 1 ] && SERVER_PID=""
  run_exec stop --store "$B_DIR/live.json" --repo "$B_DIR" --state-dir "$B_DIR/state-live"
  [ "$RC_E" -eq 0 ] && ok "(AC4) a second stop with nothing recorded is a no-op (exit 0)" || no "(AC4) second stop: rc=$RC_E err=$(cat "$LAST_ERR")"
  # Legitimate re-start after stop / crash: a STALE record (its process is gone) must NOT trip the
  # replay guard — it is cleared [stale_pid_cleared] and the start proceeds to `ready`.
  ( exit 0 ) & STALE_PID=$!; wait "$STALE_PID" 2>/dev/null   # a reaped pid: certainly not running
  mkdir -p "$B_DIR/state-live"; printf '%s\n' "$STALE_PID" > "$B_DIR/state-live/pid"
  run_exec start --store "$B_DIR/live.json" --repo "$B_DIR" --state-dir "$B_DIR/state-live"
  SERVER_PID="$(cat "$B_DIR/state-live/pid" 2>/dev/null)"
  [ "$RC_E" -eq 0 ] && [ "$OUT_E" = "ready" ] && has_token stale_pid_cleared && [ -n "$SERVER_PID" ] && [ "$SERVER_PID" != "$STALE_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null \
    && ok "(AC4) a stale pid record does NOT refuse a re-start: cleared [stale_pid_cleared], new server $SERVER_PID alive, 'ready'" \
    || no "(AC4) stale-record re-start: rc=$RC_E out=$OUT_E pid=$SERVER_PID err=$(cat "$LAST_ERR")"
  # stop when the recorded pid is NOT running (killed out from under us) stopped nothing → non-zero
  # [not_running]; the dead record is cleared so the next stop is the contract's no-op again.
  if [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null; then
    i=0; while [ "$i" -lt 10 ] && kill -0 "$SERVER_PID" 2>/dev/null; do sleep 1; i=$((i+1)); done
  fi
  run_exec stop --store "$B_DIR/live.json" --repo "$B_DIR" --state-dir "$B_DIR/state-live"
  [ "$RC_E" -ne 0 ] && has_token not_running && [ ! -e "$B_DIR/state-live/pid" ] \
    && ok "(AC4) stop with a recorded pid that is not running → non-zero [not_running] (nothing was stopped), record cleared" \
    || no "(AC4) stop not_running: rc=$RC_E pid_record=$([ -e "$B_DIR/state-live/pid" ] && echo present || echo absent) err=$(cat "$LAST_ERR")"
  SERVER_PID=""
  run_exec stop --store "$B_DIR/live.json" --repo "$B_DIR" --state-dir "$B_DIR/state-live"
  [ "$RC_E" -eq 0 ] && ok "(AC4) after the cleared record, stop is the contract no-op again (idempotent, exit 0)" || no "(AC4) stop after clear: rc=$RC_E err=$(cat "$LAST_ERR")"
else
  no "(AC4) python3 is unavailable — the http.server fixture and the free-port pick cannot run on this host"
fi
# `method: none` ⇒ `anonymous` with NO request: a PATH-stubbed curl that touches a marker must not fire.
STUB="$(mktmp)"; CURL_MARK="$B_DIR/curl-called"
printf '#!/bin/sh\ntouch "%s"\nexit 22\n' "$CURL_MARK" > "$STUB/curl"; chmod +x "$STUB/curl"
PATH="$STUB:$PATH" run_exec auth-probe --store "$FIX" --repo "$B_DIR"
[ "$RC_E" -eq 0 ] && [ "$OUT_E" = "anonymous" ] && [ ! -e "$CURL_MARK" ] \
  && ok "(AC4) auth-probe with method none → 'anonymous' and curl was never invoked" \
  || no "(AC4) method none: rc=$RC_E out=$OUT_E curl_called=$([ -e "$CURL_MARK" ] && echo yes || echo no)"
# The stub is effective (control): with start null and a stubbed curl that always fails, health
# polling must time out — proving the executor reaches curl BY NAME through PATH.
jq '.start = null | .stop = null | .ready_timeout_s = 1' "$FIX" > "$B_DIR/stubbed.json"
PATH="$STUB:$PATH" run_exec start --store "$B_DIR/stubbed.json" --repo "$B_DIR" --state-dir "$B_DIR/state-stub"
[ "$RC_E" -ne 0 ] && has_token health_timeout && [ -e "$CURL_MARK" ] \
  && ok "(AC4) CONTROL: the PATH-stubbed curl IS what the health poll calls (marker set, health_timeout)" \
  || no "(AC4) CONTROL FAILED: rc=$RC_E marker=$([ -e "$CURL_MARK" ] && echo yes || echo no) err=$(cat "$LAST_ERR")"
# HEALTH IS 2xx ONLY. The status code is READ (`-w '%{http_code}'`), never inferred from curl's
# exit status: `curl -f` fails only on 4xx/5xx, so a health route that 302s to a login page would
# have counted as healthy. A stub that prints `302` (exit 0, as curl without -f does) must time out;
# the same stub printing `200` is the positive control that the poll still reaches `ready`.
CODE_STUB="$(mktmp)"
printf '#!/bin/sh\nprintf 302\nexit 0\n' > "$CODE_STUB/curl"; chmod +x "$CODE_STUB/curl"
PATH="$CODE_STUB:$PATH" run_exec start --store "$B_DIR/stubbed.json" --repo "$B_DIR" --state-dir "$B_DIR/state-302"
[ "$RC_E" -ne 0 ] && has_token health_timeout && [ "$OUT_E" != "ready" ] \
  && ok "(AC4) a health endpoint answering 302 is NOT ready: health_timeout, no 'ready' (3xx never counts as 2xx)" \
  || no "(AC4) 302 accepted as healthy: rc=$RC_E out=$OUT_E err=$(cat "$LAST_ERR")"
printf '#!/bin/sh\nprintf 200\nexit 0\n' > "$CODE_STUB/curl"; chmod +x "$CODE_STUB/curl"
PATH="$CODE_STUB:$PATH" run_exec start --store "$B_DIR/stubbed.json" --repo "$B_DIR" --state-dir "$B_DIR/state-200"
[ "$RC_E" -eq 0 ] && [ "$OUT_E" = "ready" ] \
  && ok "(AC4) CONTROL: the same stub printing 200 → exit 0, 'ready'" \
  || no "(AC4) 200 CONTROL FAILED: rc=$RC_E out=$OUT_E err=$(cat "$LAST_ERR")"
# ready_timeout_s is WALL-CLOCK, not an iteration count: with a curl that hangs 2s per call (the
# --max-time shape) and ready_timeout_s=2, the poll must give up in ~2s — a per-iteration counter
# would take 2×(2+1)=6s. Window 2..4 discriminates the two.
HANG="$(mktmp)"
printf '#!/bin/sh\nsleep 2\nexit 22\n' > "$HANG/curl"; chmod +x "$HANG/curl"
jq '.ready_timeout_s = 2' "$B_DIR/stubbed.json" > "$B_DIR/hang.json"
t0="$(date +%s)"
PATH="$HANG:$PATH" run_exec start --store "$B_DIR/hang.json" --repo "$B_DIR" --state-dir "$B_DIR/state-hang"
t1="$(date +%s)"; elapsed=$((t1 - t0))
[ "$RC_E" -ne 0 ] && has_token health_timeout && [ "$elapsed" -ge 2 ] && [ "$elapsed" -le 4 ] \
  && ok "(AC4) a hanging health endpoint honours ready_timeout_s as wall-clock (elapsed ${elapsed}s for 2s, window 2..4)" \
  || no "(AC4) wall-clock timeout: rc=$RC_E elapsed=${elapsed}s (a per-iteration counter would take ~6s) err=$(cat "$LAST_ERR")"

# ============================================================================
echo "== (AC9) refuse-before-run =="
C_DIR="$(mktmp)"
# A store whose non_prod_assert FAILS and whose every step string touches a marker. For auth-probe
# the "did it run" evidence is the PATH-stubbed curl marker.
jq --arg s "touch $C_DIR/ran-start" --arg t "touch $C_DIR/ran-stop" --arg e "touch $C_DIR/ran-seed" --arg r "touch $C_DIR/ran-reset" \
   '.base_url = "https://app.example.com" | .non_prod_assert = {"base_url_matches": "^http://localhost"}
    | .start = $s | .stop = $t | .seed = $e | .reset = $r | .ready_timeout_s = 1
    | .auth = {"method": "storage_state", "storage_state_path": "state.json", "probe_path": "/api/me"}' "$FIX" > "$C_DIR/prod.json"
printf '%s' '{"cookies":[],"origins":[]}' > "$C_DIR/state.json"
CURL_MARK9="$C_DIR/ran-curl"
printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$CURL_MARK9" > "$STUB/curl"; chmod +x "$STUB/curl"
for sub in start stop seed reset auth-probe; do
  PATH="$STUB:$PATH" run_exec "$sub" --store "$C_DIR/prod.json" --repo "$C_DIR" --state-dir "$C_DIR/state"
  [ "$RC_E" -ne 0 ] && has_token non_prod_assert_failed \
    && ok "(AC9) $sub under a failing assertion refuses (rc=$RC_E) with reason non_prod_assert_failed" \
    || no "(AC9) $sub: rc=$RC_E err=$(cat "$LAST_ERR")"
done
[ ! -e "$C_DIR/ran-start" ] && [ ! -e "$C_DIR/ran-stop" ] && [ ! -e "$C_DIR/ran-seed" ] && [ ! -e "$C_DIR/ran-reset" ] && [ ! -e "$CURL_MARK9" ] \
  && ok "(AC9) NO step string ran and NO request was made under the failing assertion (all five markers absent)" \
  || no "(AC9) SOMETHING RAN under a failing assertion: $(ls "$C_DIR" | grep '^ran-' | tr '\n' ' ')"
[ ! -e "$C_DIR/state" ] && ok "(AC9) no state dir was created by a refused invocation" || no "(AC9) a refused invocation created state at $C_DIR/state"
# A pass in a PREVIOUS invocation buys nothing: pass on the good store, then the failing store with
# the same --state-dir must still refuse.
run_exec assert-non-prod --store "$FIX" --repo "$C_DIR" --state-dir "$C_DIR/state"
[ "$RC_E" -eq 0 ] || no "(AC9) precondition: the good store did not pass (rc=$RC_E)"
run_exec seed --store "$C_DIR/prod.json" --repo "$C_DIR" --state-dir "$C_DIR/state"
[ "$RC_E" -ne 0 ] && has_token non_prod_assert_failed && [ ! -e "$C_DIR/ran-seed" ] \
  && ok "(AC9) a pass in a PREVIOUS invocation does not carry over — seed still refused, marker absent" \
  || no "(AC9) carry-over: rc=$RC_E marker=$([ -e "$C_DIR/ran-seed" ] && echo present || echo absent)"
# Positive control for the marker mechanism: the SAME store with a passing assertion runs seed.
jq '.base_url = "http://localhost:3000"' "$C_DIR/prod.json" > "$C_DIR/nonprod.json"
run_exec seed --store "$C_DIR/nonprod.json" --repo "$C_DIR" --state-dir "$C_DIR/state"
[ "$RC_E" -eq 0 ] && [ -e "$C_DIR/ran-seed" ] && ok "(AC9) CONTROL: the same store with a passing assertion DOES run seed (marker present)" \
                                              || no "(AC9) CONTROL FAILED: rc=$RC_E marker=$([ -e "$C_DIR/ran-seed" ] && echo present || echo absent) err=$(cat "$LAST_ERR")"
rm -f "$C_DIR/ran-seed"

# MUTATION CONTROL — delete the dispatch-level `gate_non_prod;` from the `seed)` and `start)` arms
# of a COPY. The inner check at the bash -c sites must STILL refuse with non_prod_not_asserted and
# run nothing, even against a store whose assertion WOULD pass. The copy sits beside a copy of the
# reader because the executor locates the reader as a sibling.
MUT="$(mktmp)"
cp "$READER" "$MUT/read-verify.sh"
sed -e '/^  seed)/s/gate_non_prod; //' -e '/^  start)/s/gate_non_prod; //' "$EXEC" > "$MUT/verify-env.sh"
if [ -s "$MUT/verify-env.sh" ] && ! cmp -s "$EXEC" "$MUT/verify-env.sh" && bash -n "$MUT/verify-env.sh" 2>/dev/null \
   && [ "$(grep -cE '^  (seed|start)\).*gate_non_prod' "$MUT/verify-env.sh")" -eq 0 ]; then
  ok "(AC9) mutant is well-formed: non-empty, differs from the original, bash -n clean, seed/start arms carry no gate call"
  : > "$LAST_ERR"
  ( cd "$ROOT" && bash "$MUT/verify-env.sh" seed --store "$C_DIR/nonprod.json" --repo "$C_DIR" --state-dir "$C_DIR/state" ) </dev/null >/dev/null 2>"$LAST_ERR"; rc_m=$?
  [ "$rc_m" -ne 0 ] && has_token non_prod_not_asserted && [ ! -e "$C_DIR/ran-seed" ] \
    && ok "(AC9) MUTANT seed (gate call deleted): the inner check still refuses [non_prod_not_asserted], marker absent" \
    || no "(AC9) MUTANT seed ran or misreported: rc=$rc_m marker=$([ -e "$C_DIR/ran-seed" ] && echo present || echo absent) err=$(cat "$LAST_ERR")"
  : > "$LAST_ERR"
  ( cd "$ROOT" && bash "$MUT/verify-env.sh" start --store "$C_DIR/nonprod.json" --repo "$C_DIR" --state-dir "$C_DIR/state" ) </dev/null >/dev/null 2>"$LAST_ERR"; rc_m=$?
  [ "$rc_m" -ne 0 ] && has_token non_prod_not_asserted && [ ! -e "$C_DIR/ran-start" ] \
    && ok "(AC9) MUTANT start (gate call deleted): the background-launch check still refuses, marker absent" \
    || no "(AC9) MUTANT start ran or misreported: rc=$rc_m marker=$([ -e "$C_DIR/ran-start" ] && echo present || echo absent) err=$(cat "$LAST_ERR")"
else
  no "(AC9) MUTATION CONTROL could not be armed: the sed did not produce a distinct, parseable copy with the gate calls removed"
fi
# Sibling-locate: a LONE copy of the executor (no reader beside it) reports reader_missing (exit 3)
# rather than reaching for any fixed install path.
LONE="$(mktmp)"; cp "$EXEC" "$LONE/verify-env.sh"
: > "$LAST_ERR"
( cd "$ROOT" && bash "$LONE/verify-env.sh" assert-non-prod --store "$FIX" --repo "$C_DIR" ) </dev/null >/dev/null 2>"$LAST_ERR"; rc_l=$?
[ "$rc_l" -eq 3 ] && has_token reader_missing \
  && ok "(AC9) the executor locates the reader as a SIBLING — a lone copy exits 3 [reader_missing]" \
  || no "(AC9) lone copy: rc=$rc_l err=$(cat "$LAST_ERR")"
# The executor never writes the store (AC5 already counts the mv; this is the runtime half): the
# fixture bytes are unchanged after every executor call above.
[ "$(printf '%s' "$FULL_JSON" | cksum)" = "$(cksum < "$FIX")" ] \
  && ok "(AC9) the canonical fixture is byte-identical after every executor call (the executor never writes the store)" \
  || no "(AC9) the fixture changed under the executor"

# ============================================================================
finish_real_agent_check

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
