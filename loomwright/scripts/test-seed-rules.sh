#!/usr/bin/env bash
# test-seed-rules.sh — STATIC, fixture-driven self-tests for seed-rules.sh (the `/setup rules`
# cold-start module engine). STATIC ONLY: no network, no Docker, no TTY — so it runs on the
# plugin's Ubuntu CI like every other test-*.sh (auto-registered by ci.yml's test-*.sh glob).
# Exit 0 = all pass, 1 = any failure.
#
# Mirrors test-setup-twin.sh / test-setup-memory.sh convention: pass/fail counters, ok()/no()
# helpers, a "RESULT: N passed, M failed" tail, exit 1 on any failure. Every fixture is a
# `mktemp -d` dir passed via --root; a `trap ... EXIT` cleans them up. The harness NEVER touches
# the real repo's `.agent/rules/` — every write in this file lands in a fixture.
#
# Covers (each = a facet of the acceptance criterion this module owns):
#   (a) PORTABILITY of the seed set — no statement names a file, a path, a tool or this project,
#       and every seed is repo-wide, because a path glob is a claim about a directory layout.
#   (b) SEEDED, NOT LEARNED — provenance.source is exactly `setup:rules-seed` on every written
#       rule and is readable back off the store; the module's OWN output says so in words too.
#   (c) NO NEW MEMBER on the rule object (the frozen 7) and NO sidecar file — the seeded/learned
#       distinction rides in provenance.source and nowhere else.
#   (d) `check` stays null and no shell command is ever synthesised into it (rules are DATA).
#   (e) WRITE POSTURE — `check` and a bare `seed` write NOTHING even with a live, ready stdin;
#       only `seed --confirm` writes. The `< /dev/null` detachment is asserted BEHAVIOURALLY
#       (feed the writer's own `y` answer in and assert the store is still absent), not by
#       grepping the source for the redirection.
#   (f) IDEMPOTENCE — a second `seed --confirm` writes nothing, duplicates nothing, exits 0.
#   (g) the documented EXIT CONTRACT on every path: 0 / 1 (a refused seed) / 2 (usage, missing
#       dependency), plus --help.
#
# SEED_RULES_BIN exists ONLY for mutation control (point it at a deliberately-broken copy and
# confirm the suite goes RED). It DEFAULTS to the real script, so it can never disarm an
# assertion here; the copy is given the real writer via --add-rule.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEED="${SEED_RULES_BIN:-$HERE/seed-rules.sh}"
ADDRULE="$HERE/add-rule.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

FIXTURES=()
mkfix() { local d; d="$(mktemp -d)"; FIXTURES+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${FIXTURES[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

# run the helper against a fixture root with the real writer wired in explicitly (so a mutated
# copy under SEED_RULES_BIN, which lives outside scripts/, still finds add-rule.sh).
seedrun() { local root="$1"; shift; bash "$SEED" --root "$root" --add-rule "$ADDRULE" "$@"; }

# merged view of every rule object in a fixture store (absent store → empty array).
store_json() {
  local root="$1"
  if [ -d "$root/.agent/rules" ] && ls "$root"/.agent/rules/*.json >/dev/null 2>&1; then
    jq -s 'add' "$root"/.agent/rules/*.json
  else
    echo '[]'
  fi
}
store_count() { store_json "$1" | jq 'length'; }

# ============================================================================
echo "== 0. preconditions =="
[ -f "$SEED" ] && ok "seed-rules.sh present at $SEED" || no "seed-rules.sh missing at $SEED"
if [ ! -f "$SEED" ]; then echo; echo "RESULT: $pass passed, $fail failed"; exit 1; fi
bash -n "$SEED" 2>/dev/null && ok "seed-rules.sh parses" || no "seed-rules.sh has a syntax error"
if ! command -v jq >/dev/null 2>&1; then
  ok "jq unavailable — the engine hard-requires it; store assertions skipped (pass)"
  echo; echo "RESULT: $pass passed, $fail failed"; [ "$fail" -eq 0 ] || exit 1; exit 0
fi

# ============================================================================
echo "== (a) check on a cold fixture: read-only, every seed ABSENT, nothing created =="
A="$(mkfix)"
out_a="$(seedrun "$A" check 2>&1)"; rc_a=$?
[ "$rc_a" -eq 0 ] && ok "(a) check exits 0 on a cold fixture" || no "(a) check exited $rc_a"
[ ! -e "$A/.agent" ] && ok "(a) check created no .agent/ directory (read-only)" || no "(a) check created .agent/"
n_absent="$(printf '%s\n' "$out_a" | grep -c 'seed: ABSENT' || true)"
[ "$n_absent" -ge 1 ] && ok "(a) check reports $n_absent absent seeds" || no "(a) check reported no absent seeds"
printf '%s\n' "$out_a" | grep -q 'no writer is invoked' && ok "(a) check states it invokes no writer" || no "(a) check does not state its read-only posture"

# ============================================================================
echo "== (e1) bare seed = PLAN ONLY, and it is stdin-detached (live 'y' on stdin changes nothing) =="
E="$(mkfix)"
# `y\n` is EXACTLY what add-rule.sh's interactive branch reads to authorise a write. If this
# script's writer invocations were not stdin-detached, this answer would reach that prompt.
out_e="$(printf 'y\ny\ny\ny\ny\n' | seedrun "$E" seed 2>&1)"; rc_e=$?
[ "$rc_e" -eq 0 ] && ok "(e1) bare seed exits 0" || no "(e1) bare seed exited $rc_e"
[ ! -e "$E/.agent/rules" ] && ok "(e1) bare seed wrote NOTHING even with a live 'y' on stdin (writer invocations are stdin-detached)" || no "(e1) bare seed WROTE to the store — the writer's prompt branch was reachable through this caller"
printf '%s\n' "$out_e" | grep -q 'PLANNED WRITE (not written' && ok "(e1) the writer's PLANNED-WRITE branch was the one reached" || no "(e1) no PLANNED WRITE line — the dry-run branch was not reached"
printf '%s\n' "$out_e" | grep -q 'NOTHING WAS WRITTEN' && ok "(e1) the summary says nothing was written" || no "(e1) summary does not say nothing was written"
printf '%s\n' "$out_e" | grep -q -- '< /dev/null' && ok "(e1) the composed invocation is printed with its stdin redirection, so a reader can check it" || no "(e1) composed invocation does not show the stdin redirection"
# (d) rules are DATA: no --check is ever composed, on any path.
printf '%s\n' "$out_e" | grep -q -- '--check' && no "(d) a --check flag was composed — a shell command must never be synthesised into a rule" || ok "(d) no --check flag is ever composed (rules stay DATA)"
# (a) portability: no --applies-to is ever composed — a path glob is a claim about a layout.
printf '%s\n' "$out_e" | grep -q -- '--applies-to' && no "(a) an --applies-to glob was composed — a portable seed must not assume a directory layout" || ok "(a) no --applies-to is composed; every seed is repo-wide by construction"
printf '%s\n' "$out_e" | grep -q 'scope=repo-wide (justification' && ok "(a) the repo-wide scope is a STATED justification, not a silent default" || no "(a) repo-wide scope is not justified in the output"

# ============================================================================
echo "== (e2) the stdin detachment is LOAD-BEARING, proven without a TTY =="
# (e1) alone is VACUOUS as a test of the `< /dev/null`: this harness has no TTY, so add-rule.sh's
# `[ -t 0 ]` branch is unreachable whether or not the redirection is there — measured, deleting
# the redirection left (e1) entirely green.
#
# The witness below closes that, and what it asserts had to be corrected once: a first version
# fed `y` down the caller's stdin and checked the writer never saw it. That ALSO stayed green
# with the redirection deleted, because the writer invocation sits inside a `while read … <<EOF`
# loop, so with no redirection it inherits the LOOP'S HEREDOC — the seed table — rather than the
# caller's pipe. Two things follow, and both are real: the caller's `y` never gets there either
# way, and a writer that reads one line STEALS A SEED from the loop.
#
# So the property asserted is the one that is actually guaranteed and actually protective: the
# writer's stdin is AT EOF — there is nothing there for a prompt to consume and nothing for a
# stray read to steal. `< /dev/null` gives exactly that; the accidental heredoc does not.
PSTUB="$(mkfix)/stdin-witness-writer.sh"
cat > "$PSTUB" <<'STUB'
#!/usr/bin/env bash
# Stands in for add-rule.sh's `read -r reply` without needing a TTY. Records ANY readable line —
# if this succeeds, the writer was handed a live stdin.
if IFS= read -r line; then printf '%s' "$line" > "${SEED_TEST_MARKER:?marker path not passed}"; fi
exit 0
STUB
chmod +x "$PSTUB"
E2="$(mkfix)"; MARKER="$E2/writer-received-readable-stdin"
printf 'y\ny\ny\ny\ny\n' | SEED_TEST_MARKER="$MARKER" bash "$SEED" --root "$E2" --add-rule "$PSTUB" seed >/dev/null 2>&1
[ ! -e "$MARKER" ] && ok "(e2) the writer's stdin is at EOF — nothing for a prompt to consume, nothing for a stray read to steal" || no "(e2) the writer was handed a READABLE stdin (it read: $(cat "$MARKER" 2>/dev/null | cut -c1-60)) — the /dev/null redirection is gone"
# Control for the control: handed a real stdin, the same stub DOES drop its marker — otherwise
# the assertion above would pass against a witness that can never fire at all.
MARKER2="$E2/control-marker"
printf 'y\n' | SEED_TEST_MARKER="$MARKER2" bash "$PSTUB"
[ -e "$MARKER2" ] && ok "(e2) control: the witness fires when stdin IS readable (the assertion above is not vacuous)" || no "(e2) control failed — the witness cannot fire at all, so (e2) proves nothing"

# ============================================================================
echo "== (b/c/d) seed --confirm: writes, stamped seeded, frozen schema, null check =="
W="$(mkfix)"
out_w="$(seedrun "$W" seed --confirm 2>&1)"; rc_w=$?
[ "$rc_w" -eq 0 ] && ok "(b) seed --confirm exits 0" || no "(b) seed --confirm exited $rc_w"
cnt_w="$(store_count "$W")"
# EXACT, not `-ge 1`. The seed table has five entries and writes all five or the run is broken; a
# write loop that stopped after the first seed satisfied `-ge 1` here and only surfaced two sections
# later as an idempotency mismatch — a confusing label on a defect that belongs to THIS assertion.
# Derived from the writer's own seed table, never hardcoded here — a second copy of the count is
# the exact drift this repo keeps paying for.
seed_n="$(awk '/<<.SEEDS.$/,/^SEEDS$/' "$SEED" | grep -cE '^[a-z-]+\|' || true)"
[ "${seed_n:-0}" -gt 0 ] || no "(b) could not read the seed table out of $SEED — the expected count is unknown"
[ "${cnt_w:-0}" -eq "$seed_n" ] \
  && ok "(b) seed --confirm wrote all $seed_n seeds (exact count, so a partial write cannot pass)" \
  || no "(b) seed --confirm wrote $cnt_w rules, expected exactly $seed_n — a partial write, not an idempotency problem"

# (b) EVERY written rule is stamped seeded, and it is readable back off the store.
bad_src="$(store_json "$W" | jq '[.[] | select(.provenance.source != "setup:rules-seed")] | length')"
[ "$bad_src" -eq 0 ] && ok "(b) every written rule carries provenance.source=setup:rules-seed (readable back off the store)" || no "(b) $bad_src rules carry a provenance.source other than setup:rules-seed"

# (c) NO NEW MEMBER — the frozen 7, exactly. `supersedes` is legal but is never authored here.
bad_keys="$(store_json "$W" | jq '[.[] | select((keys_unsorted | sort) != ["applies_to","category","check","enforcement","id","provenance","statement"])] | length')"
[ "$bad_keys" -eq 0 ] && ok "(c) every written rule has EXACTLY the frozen 7 members — no new member" || no "(c) $bad_keys rules deviate from the frozen 7-member schema"
# (c) and no sidecar: the only thing under .agent/ is the rules dir's own *.json files.
side="$(find "$W/.agent" -type f ! -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
[ "$side" -eq 0 ] && ok "(c) no sidecar file was written beside the store" || no "(c) $side non-JSON sidecar file(s) written under .agent/"

# (d) check stays null on every seed.
bad_check="$(store_json "$W" | jq '[.[] | select(.check != null)] | length')"
[ "$bad_check" -eq 0 ] && ok "(d) check is null on every written rule (no synthesised command)" || no "(d) $bad_check rules carry a non-null check"

# (a) repo-wide, and every rule is advisory.
bad_scope="$(store_json "$W" | jq '[.[] | select(.applies_to != null)] | length')"
[ "$bad_scope" -eq 0 ] && ok "(a) applies_to is null (repo-wide) on every written rule" || no "(a) $bad_scope rules carry a path scope"
bad_enf="$(store_json "$W" | jq '[.[] | select(.enforcement != "advisory")] | length')"
[ "$bad_enf" -eq 0 ] && ok "(a) every seeded rule is advisory (this module adds no gate)" || no "(a) $bad_enf rules are not advisory"

# ============================================================================
echo "== (a) PORTABILITY of the seed statements themselves =="
# A portable statement names no file, no path, no tool and no project. Each pattern below is a
# way a statement could smuggle in something that is only true HERE.
stmts="$(store_json "$W" | jq -r '.[].statement')"
if printf '%s\n' "$stmts" | grep -qiE 'loomwright|supervisor|beads|langfuse|graphify|claude'; then
  no "(a) a seed statement names this project or one of its tools"
else
  ok "(a) no seed statement names this project or one of its tools"
fi
if printf '%s\n' "$stmts" | grep -qE '\.(sh|md|json|py|ts|js|yml|yaml)([^a-zA-Z]|$)'; then
  no "(a) a seed statement names a concrete file"
else
  ok "(a) no seed statement names a concrete file"
fi
if printf '%s\n' "$stmts" | grep -qE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.*-]+'; then
  no "(a) a seed statement names a path or a glob (a claim about a directory layout)"
else
  ok "(a) no seed statement names a path or a glob"
fi
n_stmts="$(printf '%s\n' "$stmts" | grep -c . || true)"
[ "$n_stmts" -le 8 ] && ok "(a) the seed set is small and readable ($n_stmts rules)" || no "(a) the seed set has grown to $n_stmts rules — too many to be read and judged"

# ============================================================================
echo "== (b) the module's OWN output states these are seeded, not earned =="
# Asserted on ALL THREE modes' real captured output — a disclosure that only the write path
# prints would leave a user reading `check` believing the rules were earned.
assert_disclosure() {   # <mode-label> <captured output>
  local m="$1" body="$2"
  printf '%s\n' "$body" | grep -q 'NOT learned from this' \
    && ok "(b) [$m] output states the rules were NOT learned from this repo" \
    || no "(b) [$m] output does not say the rules were not learned here"
  printf '%s\n' "$body" | grep -q 'SEEDED' \
    && ok "(b) [$m] output labels them SEEDED" \
    || no "(b) [$m] output does not label them seeded"
  printf '%s\n' "$body" | grep -q 'setup:rules-seed' \
    && ok "(b) [$m] output names the provenance.source that carries the distinction" \
    || no "(b) [$m] output does not name setup:rules-seed"
}
assert_disclosure "check" "$out_a"
assert_disclosure "plan"  "$out_e"
assert_disclosure "write" "$out_w"

# ============================================================================
echo "== (f) idempotence — a second seed --confirm writes nothing and duplicates nothing =="
before="$(store_count "$W")"
out_f="$(seedrun "$W" seed --confirm 2>&1)"; rc_f=$?
after="$(store_count "$W")"
[ "$rc_f" -eq 0 ] && ok "(f) second seed --confirm exits 0 (an already-seeded repo is not a failure)" || no "(f) second run exited $rc_f"
[ "$before" = "$after" ] && ok "(f) rule count unchanged across the second run ($after)" || no "(f) rule count moved $before → $after on a second run"
dups="$(store_json "$W" | jq '[.[].id] | (length - (unique | length))')"
[ "$dups" -eq 0 ] && ok "(f) no duplicate rule ids after two runs" || no "(f) $dups duplicate rule ids after two runs"
printf '%s\n' "$out_f" | grep -q 'ALREADY SEEDED' && ok "(f) the second run reports the seeds as already seeded" || no "(f) second run does not report already-seeded"
printf '%s\n' "$out_f" | grep -q '5 already seeded\|already seeded · 0 absent' && ok "(f) the summary counts them as already seeded, 0 absent" || no "(f) summary does not show 0 absent on the second run"
# and `check` on the seeded fixture reports them present rather than absent.
out_f2="$(seedrun "$W" check 2>&1)"
printf '%s\n' "$out_f2" | grep -q 'seed: ABSENT' && no "(f) check still reports an ABSENT seed on a fully-seeded fixture" || ok "(f) check reports no absent seed on a fully-seeded fixture"

# ============================================================================
echo "== (g) exit contract =="
out_h="$(bash "$SEED" --help 2>&1)"; rc_h=$?
[ "$rc_h" -eq 0 ] && ok "(g) --help exits 0" || no "(g) --help exited $rc_h"
printf '%s\n' "$out_h" | grep -q 'WRITE POSTURE' && ok "(g) --help prints the write posture (which invocation writes)" || no "(g) --help does not print the write posture"

G="$(mkfix)"
bash "$SEED" --root "$G" --bogus-flag check >/dev/null 2>&1; rc_u=$?
[ "$rc_u" -eq 2 ] && ok "(g) an unknown argument exits 2 (rejected, never silently ignored)" || no "(g) unknown argument exited $rc_u (expected 2)"
bash "$SEED" --root "$G" >/dev/null 2>&1; rc_n=$?
[ "$rc_n" -eq 2 ] && ok "(g) a missing subcommand exits 2" || no "(g) missing subcommand exited $rc_n (expected 2)"
bash "$SEED" --root >/dev/null 2>&1; rc_v=$?
[ "$rc_v" -eq 2 ] && ok "(g) a valueless --root exits 2 (never a silent fall-back)" || no "(g) valueless --root exited $rc_v (expected 2)"

# A SECOND subcommand must DIE, never be silently dropped. `shift` used to run unconditionally while
# only the assignment was guarded, so `seed check --confirm` kept `seed`, discarded `check` with no
# diagnostic, and went on to WRITE — the caller asked to read and got a write. The assertion is the
# EXIT plus an EMPTY STORE: a rejection that still wrote would be no rejection at all.
Gd2="$(mkfix)"
out_d2="$(bash "$SEED" --root "$Gd2" --add-rule "$ADDRULE" seed check --confirm 2>&1)"; rc_d2=$?
if [ "$rc_d2" -eq 2 ] && printf '%s\n' "$out_d2" | grep -q 'only one subcommand'; then
  ok "(g) a duplicate subcommand ('seed check') exits 2 with a diagnostic naming both"
else
  no "(g) duplicate subcommand exited $rc_d2 (expected 2): $(printf '%s\n' "$out_d2" | head -1)"
fi
[ ! -e "$Gd2/.agent/rules" ] || [ "$(store_count "$Gd2")" = "0" ] \
  && ok "(g) the refused duplicate-subcommand run wrote NOTHING — the silent-drop-then-write path is closed" \
  || no "(g) the duplicate-subcommand run still wrote $(store_count "$Gd2") rules"
# Control: the same invocation with ONE subcommand is accepted, so the assertion above is not
# passing merely because this argv shape can never work.
Gd3="$(mkfix)"
bash "$SEED" --root "$Gd3" --add-rule "$ADDRULE" seed --confirm >/dev/null 2>&1; rc_d3=$?
[ "$rc_d3" -eq 0 ] && ok "(g) control: the same argv with a single subcommand still exits 0 and writes" \
  || no "(g) control failed — a single-subcommand seed --confirm exited $rc_d3, so the rejection above proves nothing"

[ ! -e "$G/.agent" ] && ok "(g) no usage-error path created a store" || no "(g) a usage-error path created a store"

# missing writer: `seed` REFUSES (2) rather than hand-building a rule object; `check` does not
# need the writer at all and still works.
Gw="$(mkfix)"
bash "$SEED" --root "$Gw" --add-rule "$Gw/no-such-writer.sh" seed >/dev/null 2>&1; rc_mw=$?
[ "$rc_mw" -eq 2 ] && ok "(g) a missing add-rule.sh exits 2 on seed (never hand-builds a rule object)" || no "(g) missing writer exited $rc_mw (expected 2)"
bash "$SEED" --root "$Gw" --add-rule "$Gw/no-such-writer.sh" check >/dev/null 2>&1; rc_cw=$?
[ "$rc_cw" -eq 0 ] && ok "(g) check exits 0 without a writer (it invokes none)" || no "(g) check exited $rc_cw without a writer"

# a REFUSED seed ⇒ exit 1, reported per seed, success never claimed.
STUB="$(mkfix)/refusing-writer.sh"
printf '#!/usr/bin/env bash\necho "refused: fixture writer always refuses" >&2\nexit 1\n' > "$STUB"
chmod +x "$STUB"
Gr="$(mkfix)"
out_r="$(bash "$SEED" --root "$Gr" --add-rule "$STUB" seed --confirm 2>&1)"; rc_r=$?
[ "$rc_r" -eq 1 ] && ok "(g) a refused seed exits 1" || no "(g) refused seed exited $rc_r (expected 1)"
printf '%s\n' "$out_r" | grep -q 'seed: FAILED' && ok "(g) the refused seed is named in the output" || no "(g) a refused seed was not reported"
[ "$(store_count "$Gr")" = "0" ] && ok "(g) nothing landed in the store when every write was refused" || no "(g) something landed in the store despite refusals"

# default writer resolution (no --add-rule) still works — the flag is a testing seam, not the path.
Gd="$(mkfix)"
bash "$SEED" --root "$Gd" seed --confirm >/dev/null 2>&1; rc_d=$?
[ "$rc_d" -eq 0 ] && ok "(g) default writer resolution (no --add-rule) works" || no "(g) default writer resolution exited $rc_d"
[ "$(store_count "$Gd")" -ge 1 ] && ok "(g) default resolution actually wrote the seeds" || no "(g) default resolution wrote nothing"

# ============================================================================
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
