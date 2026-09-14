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
#                                      malformed (a half-typed member must not silently vanish)
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
#                                      form rejected (exit 1)
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
[ "$before_p8" = "$(tree_hash "$r_p8")" ] && ok "(p8) neither rejected run wrote anything" || no "(p8) a rejected run modified the tree"

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
finish_real_agent_check

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
